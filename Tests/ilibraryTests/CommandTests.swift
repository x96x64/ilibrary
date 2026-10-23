import CatalogCore
import Foundation
import MP4Core
import Testing

@testable import ilibrary

@Suite struct InterfaceTests {
    @Test func versionHelpAndUsageErrors() {
        #expect(Run(["--version"]).text == "ilibrary \(version)")
        #expect(Run([]).text.contains("Commands:"))
        #expect(Run(["help", "apply"]).text.contains("--rename"))
        #expect(Run(["apply", "--help"]).text.contains("--timestamps"))
        let unknown = Run(["frobnicate"])
        #expect(unknown.status == 2)
        #expect(unknown.errorText.contains("unknown command frobnicate"))
        #expect(Run(["schema", "extra"]).status == 2)
        #expect(Run(["apply", "catalog.json", "--bogus", "x"]).status == 2)
        #expect(Run(["export", "x"]).errorText.contains("-o CATALOG.json is required"))
    }

    @Test func argumentsAreParsed() throws {
        let syntax = CommandSyntax(
            name: "test", usage: "usage", valued: ["--output": ["-o"]], flags: ["--dry-run"], positionals: 1...3)
        let parsed = try syntax.parse(["a", "-o", "file", "--dry-run", "--", "--literal"])
        #expect(parsed.positionals == ["a", "--literal"])
        #expect(parsed.value("--output") == "file")
        #expect(parsed.flag("--dry-run"))
        #expect(try syntax.parse(["a", "--output=x"]).value("--output") == "x")
        #expect(throws: CommandError.self) { try syntax.parse(["a", "--dry-run=yes"]) }
        #expect(throws: CommandError.self) { try syntax.parse(["a", "-o"]) }
        #expect(throws: CommandError.self) { try syntax.parse(["a", "-o", "x", "-o", "y"]) }
        #expect(throws: CommandError.self) { try syntax.parse([]) }
    }

    @Test func schemaPrintsThePublishedSchema() {
        let run = Run(["schema"])
        #expect(run.status == 0)
        #expect(run.text == Catalog.jsonSchema)
    }
}

@Suite struct RoundTripTests {
    /// Exporting a library and reapplying the catalog changes nothing.
    @Test func exportAndReapplicationChangeNothing() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let before = try library.snapshot()
        let work = library.root.deletingLastPathComponent().appendingPathComponent("ilibrary-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let catalog = work.appendingPathComponent("catalog.json").path
        let export = Run([
            "export", library.root.path, "-o", catalog, "--artwork", work.appendingPathComponent("covers").path,
        ])
        #expect(export.status == 0, "\(export.errorText)")
        #expect(export.errors.isEmpty, "\(export.errorText)")
        #expect(export.text.contains("Exported 3 albums and 9 tracks from 9 files"))
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: work.appendingPathComponent("covers").path).sorted()
                == [
                    "Example Artist - Double Album.jpg", "Example Artist - Synthetic Album.png",
                ])

        let validate = Run(["validate", catalog, library.root.path])
        #expect(validate.status == 0, "\(validate.text)\n\(validate.errorText)")

        let apply = Run(["apply", catalog, library.root.path])
        #expect(apply.status == 0, "\(apply.errorText)")
        #expect(apply.text.contains("Tag changes: 0 of 9 files"))
        #expect(try library.snapshot() == before)

        let second = work.appendingPathComponent("second.json").path
        #expect(Run(["export", library.root.path, "-o", second]).status == 0)
        var first = try #require(Catalog.validate(try Data(contentsOf: URL(fileURLWithPath: catalog))).catalog)
        for index in first.albums.indices { first.albums[index].artwork = nil }
        let reexported = try #require(Catalog.validate(try Data(contentsOf: URL(fileURLWithPath: second))).catalog)
        #expect(reexported == first)
    }

    @Test func exportedValuesSitAtAlbumLevelWhenShared() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let url = library.root.appendingPathComponent("catalog.json")
        #expect(Run(["export", library.root.path, "-o", url.path]).status == 0)
        let catalog = try #require(Catalog.validate(try Data(contentsOf: url)).catalog)
        let first = try #require(catalog.albums.first { $0.album == "Synthetic Album" })
        #expect(first.artist == "Example Artist")
        #expect(first.releaseDate == "1980-06-01")
        #expect(first.composer == nil)
        #expect(first.discs[0].tracks.map(\.composer) == ["Example Writer", "Second Writer", "Example Writer"])
        let tribute = try #require(catalog.albums.first { $0.album == "Tribute Collection" })
        #expect(tribute.compilation == true)
        #expect(tribute.artist == nil)
        #expect(tribute.discs[0].tracks.map(\.artist) == ["First Guest", "Second Guest"])
        #expect(catalog.albums.first { $0.album == "Double Album" }?.discs.count == 2)
        #expect(catalog.albums.first { $0.album == "Double Album" }?.compilation == false)
    }

    @Test func exportListsItsWritesAndADryRunWritesNothing() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let before = try library.snapshot()
        let catalog = library.root.appendingPathComponent("catalog.json")
        let covers = library.root.appendingPathComponent("covers")
        let preview = Run(["export", library.root.path, "-o", catalog.path, "--artwork", covers.path, "--dry-run"])
        #expect(preview.status == 0, "\(preview.errorText)")
        #expect(preview.text.contains("Planned writes: 3 files"))
        #expect(preview.text.contains("cover \(covers.path)/Example Artist - Double Album.jpg: JPEG, 304 bytes"))
        #expect(preview.text.contains("Dry run: nothing was written."))
        #expect(pathKind(catalog) == .missing)
        #expect(pathKind(covers) == .missing)
        #expect(try library.snapshot() == before)
    }

    @Test func aFailedExportLeavesNoFilesBehind() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let covers = library.root.appendingPathComponent("covers")
        let unwritable = library.root.appendingPathComponent("missing-folder/catalog.json")
        let preflight = Run(["export", library.root.path, "-o", unwritable.path, "--artwork", covers.path])
        #expect(preflight.status == 1)
        #expect(preflight.errorText.contains("is not a writable directory; nothing was written"))
        #expect(pathKind(covers) == .missing)
        // A read-only catalog folder is also refused before any cover is written; root may write anyway.
        let catalog = library.root.appendingPathComponent("catalog.json")
        try FileManager.default.createDirectory(
            at: library.root.appendingPathComponent("blocked"), withIntermediateDirectories: false)
        let blockedCatalog = library.root.appendingPathComponent("blocked/catalog.json")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: blockedCatalog.deletingLastPathComponent().path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: blockedCatalog.deletingLastPathComponent().path)
        }
        if FileManager.default.isWritableFile(atPath: blockedCatalog.deletingLastPathComponent().path) { return }
        #expect(Run(["export", library.root.path, "-o", blockedCatalog.path, "--artwork", covers.path]).status == 1)
        #expect(pathKind(covers) == .missing)
        #expect(pathKind(catalog) == .missing)
    }

    @Test func exportNeverOverwrites() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let url = library.root.appendingPathComponent("catalog.json")
        try Data("keep".utf8).write(to: url)
        let run = Run(["export", library.root.path, "-o", url.path])
        #expect(run.status == 1)
        #expect(try Data(contentsOf: url) == Data("keep".utf8))
    }

    @Test func exportWarnsAboutNumbersThatACatalogCannotKeep() throws {
        var albums = [SyntheticLibrary.standardAlbums[0]]
        albums[0].tracks.remove(at: 1)
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        let run = Run(["export", library.root.path, "-o", library.root.appendingPathComponent("c.json").path])
        #expect(run.status == 0)
        #expect(run.errorText.contains("has track numbers [1, 3]"))
    }
}

@Suite struct ApplyTests {
    func exported(_ library: SyntheticLibrary) throws -> (url: URL, catalog: Catalog) {
        let url = library.root.deletingLastPathComponent().appendingPathComponent("catalog-\(UUID().uuidString).json")
        let run = Run(["export", library.root.path, "-o", url.path])
        precondition(run.status == 0, run.errorText)
        return (url, Catalog.validate(try Data(contentsOf: url)).catalog!)
    }

    func write(_ catalog: Catalog, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        try catalog.encoded().write(to: url)
    }

    @Test func editsArePreviewedAppliedVerifiedAndStable() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        var (url, catalog) = try exported(library)
        defer { try? FileManager.default.removeItem(at: url) }
        let album = try #require(catalog.albums.firstIndex { $0.album == "Synthetic Album" })
        catalog.albums[album].discs[0].tracks[0].title = "First Song (Revised)"
        catalog.albums[album].copyright = "℗ 1981 Example Records, Inc."
        catalog.albums[album].genre = ""
        try write(catalog, to: url)
        let original = try library.snapshot()
        let originals = try library.m4aFiles().map { try MP4File(data: Data(contentsOf: $0)) }

        let preview = Run(["apply", url.path, library.root.path, "--dry-run"])
        #expect(preview.status == 0, "\(preview.errorText)")
        #expect(preview.text.contains("Tag changes: 3 of 9 files"))
        #expect(preview.text.contains("title: \"First Song\" -> \"First Song (Revised)\""))
        #expect(!preview.text.contains("genre"))
        #expect(preview.text.contains("Dry run: nothing was changed."))
        #expect(try library.snapshot() == original)

        let apply = Run(["apply", url.path, library.root.path])
        #expect(apply.status == 0, "\(apply.errorText)")
        #expect(apply.text.contains("Applied: 3 files rewritten and verified, 0 moved"))
        let files = try library.m4aFiles()
        for (file, before) in zip(files, originals) {
            let after = try MP4File(contentsOf: file)
            #expect(after.streamDifferences(from: before).isEmpty)
        }
        let changed = try MP4File(contentsOf: try #require(files.first { $0.lastPathComponent.hasPrefix("01-First") }))
        #expect(changed.metadataValues(.title) == [.text("First Song (Revised)")])
        #expect(changed.metadataValues(.copyright) == [.text("℗ 1981 Example Records, Inc.")])
        #expect(changed.metadataValues(.genre) == [.text("Pop")])

        let settled = try library.snapshot()
        let again = Run(["apply", url.path, library.root.path])
        #expect(again.text.contains("Tag changes: 0 of 9 files"))
        #expect(try library.snapshot() == settled)
    }

    @Test func renamingArrangesFoldersAsMusicDoes() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let (url, _) = try exported(library)
        defer { try? FileManager.default.removeItem(at: url) }
        let apply = Run(["apply", url.path, library.root.path, "--rename"])
        #expect(apply.status == 0, "\(apply.errorText)")
        let names = try library.m4aFiles().map { relativePath($0, from: library.root) }
        #expect(
            names == [
                "Example Artist/Double Album/1-01 Opening.m4a", "Example Artist/Double Album/1-02 Middle.m4a",
                "Example Artist/Double Album/2-01 Return.m4a", "Example Artist/Double Album/2-02 Closing.m4a",
                "Example Artist/Synthetic Album/01 First Song.m4a",
                "Example Artist/Synthetic Album/02 Second Song_ Part 1_2.m4a",
                "Example Artist/Synthetic Album/03 Third Song.m4a",
                "Various Artists/Tribute Collection/01 Cover Version.m4a",
                "Various Artists/Tribute Collection/02 Another Version.m4a",
            ])
        #expect(apply.text.contains("Download One is now empty; it was not removed"))
        #expect(pathKind(library.root.appendingPathComponent("Download One")) == .directory)
        let again = Run(["apply", url.path, library.root.path, "--rename"])
        #expect(again.text.contains("Moves: 0 of 9 files"))
    }

    @Test func titleRulesShapeWrittenTitlesAndNames() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        var (url, catalog) = try exported(library)
        defer { try? FileManager.default.removeItem(at: url) }
        let album = try #require(catalog.albums.firstIndex { $0.album == "Synthetic Album" })
        catalog.titleRules = TitleRuleSettings(caseStyle: .start, removeQualifiers: ["Remaster"], bracketNested: true)
        catalog.albums[album].discs[0].tracks[0].title = "first song (B's Mix (Demo)) (2012 Remaster)"
        try write(catalog, to: url)

        let preview = Run(["apply", url.path, library.root.path, "--rename", "--dry-run"])
        #expect(preview.status == 0, "\(preview.errorText)")
        #expect(preview.text.contains("title: \"First Song\" -> \"First Song [B's Mix (Demo)]\""))
        let apply = Run(["apply", url.path, library.root.path, "--rename"])
        #expect(apply.status == 0, "\(apply.errorText)")
        let renamed = library.root.appendingPathComponent(
            "Example Artist/Synthetic Album/01 First Song [B's Mix (Demo)].m4a")
        #expect(try MP4File(contentsOf: renamed).metadataValues(.title) == [.text("First Song [B's Mix (Demo)]")])
        let again = Run(["apply", url.path, library.root.path, "--rename"])
        #expect(again.text.contains("Tag changes: 0 of 9 files"))
        #expect(again.text.contains("Moves: 0 of 9 files"))
    }

    @Test func collisionsUnmatchedFilesAndLinksChangeNothing() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let (url, catalog) = try exported(library)
        defer { try? FileManager.default.removeItem(at: url) }
        let occupied = library.root.appendingPathComponent("Example Artist/Synthetic Album")
        try FileManager.default.createDirectory(
            at: occupied.appendingPathComponent("01 First Song.m4a"), withIntermediateDirectories: true)
        var before = try library.snapshot()
        let collision = Run(["apply", url.path, library.root.path, "--rename"])
        #expect(collision.status == 1)
        #expect(collision.errorText.contains("already exists and is not replaced; nothing was changed"))
        #expect(try library.snapshot() == before)
        try FileManager.default.removeItem(at: library.root.appendingPathComponent("Example Artist"))

        var reduced = catalog
        reduced.albums.removeAll { $0.album == "Tribute Collection" }
        try reduced.encoded().write(to: url, options: [])
        before = try library.snapshot()
        let unmatched = Run(["apply", url.path, library.root.path])
        #expect(unmatched.status == 1)
        #expect(unmatched.text.contains("unmatched "))
        #expect(try library.snapshot() == before)

        try catalog.encoded().write(to: url, options: [])
        let target = try #require(try library.m4aFiles().first)
        try FileManager.default.createSymbolicLink(
            at: library.root.appendingPathComponent("Download One/link.m4a"), withDestinationURL: target)
        let linked = Run(["apply", url.path, library.root.path])
        #expect(linked.status == 1)
        #expect(linked.text.contains("symbolic links are not followed"))

        let missing = Run(["apply", url.path, library.root.appendingPathComponent("Missing").path])
        #expect(missing.status == 1)
        #expect(missing.errorText.contains("does not exist"))
        #expect(pathKind(library.root.appendingPathComponent("Missing")) == .missing)
    }

    @Test func freeSpaceIsCheckedOnTheVolumeOfEveryChangedFile() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        var (url, catalog) = try exported(library)
        defer { try? FileManager.default.removeItem(at: url) }
        for index in catalog.albums.indices { catalog.albums[index].copyright = "℗ 2001 Example Records, Inc." }
        try write(catalog, to: url)
        let before = try library.snapshot()
        // The first folder has room; the folder of the last album does not.
        var environment = Environment.testing
        let full = library.root.appendingPathComponent("Download Three").path
        environment.availableCapacity = { $0.path == full ? 10 : 1 << 40 }
        environment.volumeIdentifier = { $0.path }
        let run = Run(["apply", url.path, library.root.path], environment: environment)
        #expect(run.status == 1)
        #expect(run.errorText.contains("10 bytes are available on the volume of \(full)"))
        #expect(try library.snapshot() == before)
    }

    @Test func addedArtworkCountsTowardTheRequiredSpace() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        var (url, catalog) = try exported(library)
        defer { try? FileManager.default.removeItem(at: url) }
        let cover = url.deletingLastPathComponent().appendingPathComponent("large-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: cover) }
        try (SyntheticLibrary.png + Data(count: 2 << 20)).write(to: cover)
        let album = try #require(catalog.albums.firstIndex { $0.album == "Tribute Collection" })
        catalog.albums[album].artwork = cover.lastPathComponent
        try write(catalog, to: url)
        let before = try library.snapshot()
        // Room for the old files and the margin, but not for two rewritten files that each gain 2 MiB.
        var environment = Environment.testing
        environment.availableCapacity = { _ in 3 << 20 }
        let run = Run(["apply", url.path, library.root.path], environment: environment)
        #expect(run.status == 1)
        #expect(run.errorText.contains("but rewriting needs"))
        #expect(try library.snapshot() == before)
    }

    @Test(arguments: ["..", String(repeating: "あ", count: 90)])
    func unsafeOrOversizedNamesStopRenamingBeforeAnyChange(name: String) throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        var (url, catalog) = try exported(library)
        defer { try? FileManager.default.removeItem(at: url) }
        let album = try #require(catalog.albums.firstIndex { $0.album == "Tribute Collection" })
        catalog.albums[album].albumArtist = name
        try write(catalog, to: url)
        let before = try library.snapshot()
        let outside = library.root.deletingLastPathComponent().appendingPathComponent("Tribute Collection")
        let run = Run(["apply", url.path, library.root.path, "--rename"])
        #expect(run.status == 1)
        #expect(run.errorText.contains("nothing was changed"))
        #expect(try library.snapshot() == before)
        #expect(pathKind(outside) == .missing)
    }

    @Test func missingArtworkStopsBeforeAnyChange() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        var (url, catalog) = try exported(library)
        defer { try? FileManager.default.removeItem(at: url) }
        catalog.albums[0].artwork = "covers/absent.png"
        try write(catalog, to: url)
        let before = try library.snapshot()
        let run = Run(["apply", url.path, library.root.path])
        #expect(run.status == 1)
        #expect(run.errorText.contains("does not exist"))
        #expect(try library.snapshot() == before)
        #expect(Run(["validate", url.path]).status == 1)
    }
}

@Suite struct PromptTests {
    @Test func promptContainsRulesSchemaAndDraft() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let url = library.root.appendingPathComponent("catalog.json")
        #expect(Run(["export", library.root.path, "-o", url.path]).status == 0)
        let run = Run(["prompt", url.path])
        #expect(run.status == 0)
        #expect(run.text.contains("Leave a value empty"))
        #expect(run.text.contains("分からない値は推測せず"))
        #expect(run.text.contains(Catalog.jsonSchema))
        #expect(run.text.contains("\"Synthetic Album\""))
        try Data("{\"format\": \"other\"}".utf8).write(to: url, options: [])
        #expect(Run(["prompt", url.path]).status == 1)
    }
}
