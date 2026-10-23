import CatalogCore
import Foundation
import Testing

@testable import ilibrary

@Suite struct TimestampPlanTests {
    static let zone = TimeZone(identifier: "Asia/Tokyo")!

    func catalog(folderDate: String?) -> Catalog {
        Catalog(
            artists: folderDate.map { ["Example Artist": ArtistEntry(folderDate: $0)] },
            albums: [
                Album(
                    album: "Synthetic Album", albumArtist: "Example Artist", releaseDate: "1958-08-29",
                    discs: [Disc(tracks: [Track(title: "One"), Track(title: "Two", releaseDate: "1959-08-29")])]),
                Album(album: "Undated", albumArtist: "Example Artist", discs: [Disc(tracks: [Track(title: "Three")])]),
            ])
    }

    func files(_ catalog: Catalog, root: URL) -> [(url: URL, track: ResolvedTrack)] {
        let tracks = catalog.resolvedTracks()
        return [
            (root.appendingPathComponent("Example Artist/Synthetic Album/01 One.m4a"), tracks[0]),
            (root.appendingPathComponent("Example Artist/Synthetic Album/02 Two.m4a"), tracks[1]),
            (root.appendingPathComponent("Example Artist/Undated/01 Three.m4a"), tracks[2]),
        ]
    }

    @Test func filesComeFirstThenAlbumAndArtistFolders() {
        let root = URL(fileURLWithPath: "/Staging")
        let catalog = catalog(folderDate: "1957-08-29")
        let plan = TimestampPlanner.plan(
            files: files(catalog, root: root), catalog: catalog, roots: [root], timeZone: TimestampPlanTests.zone)
        #expect(plan.targets.map(\.kind) == [.file, .file, .albumFolder, .artistFolder])
        #expect(
            plan.targets.map { relativePath($0.url, from: root) } == [
                "Example Artist/Synthetic Album/01 One.m4a", "Example Artist/Synthetic Album/02 Two.m4a",
                "Example Artist/Synthetic Album", "Example Artist",
            ])
        #expect(
            plan.targets.map(\.releaseDate.description) == ["1958-08-29", "1959-08-29", "1958-08-29", "1957-08-29"])
        #expect(plan.targets[0].date == Date(timeIntervalSince1970: -357_987_600))
        #expect(plan.notes.contains { $0.contains("01 Three.m4a left unchanged: no release date") })
        #expect(plan.notes.contains { $0.contains("\"Undated\" has no release date") })
    }

    @Test func artistFoldersWithoutFolderDateAreLeftUnchanged() {
        let root = URL(fileURLWithPath: "/Staging")
        let catalog = catalog(folderDate: nil)
        let plan = TimestampPlanner.plan(
            files: files(catalog, root: root), catalog: catalog, roots: [root], timeZone: TimestampPlanTests.zone)
        #expect(!plan.targets.contains { $0.kind == .artistFolder })
        #expect(plan.notes.contains { $0.contains("gives \"Example Artist\" no folderDate") })
    }

    @Test func foldersOutsideTheGivenDirectoriesAreNeverChanged() {
        let root = URL(fileURLWithPath: "/Staging/Example Artist/Synthetic Album")
        let catalog = catalog(folderDate: "1957-08-29")
        let plan = TimestampPlanner.plan(
            files: Array(files(catalog, root: URL(fileURLWithPath: "/Staging")).prefix(2)), catalog: catalog,
            roots: [root],
            timeZone: TimestampPlanTests.zone)
        #expect(plan.targets.map(\.kind) == [.file, .file, .albumFolder])
        #expect(
            plan.notes.contains { $0.contains("Example Artist left unchanged: it is outside the given directories") })
    }

    @Test func skippedMidnightIsReported() throws {
        let zone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let catalog = Catalog(albums: [
            Album(album: "A", albumArtist: "B", releaseDate: "2018-11-04", discs: [Disc(tracks: [Track(title: "T")])])
        ])
        let plan = TimestampPlanner.plan(
            files: [(URL(fileURLWithPath: "/S/B/A/01 T.m4a"), catalog.resolvedTracks()[0])], catalog: catalog,
            roots: [URL(fileURLWithPath: "/S")], timeZone: zone)
        #expect(plan.targets.allSatisfy { !$0.isMidnight })
        #expect(plan.notes.contains { $0.contains("does not exist in America/Sao_Paulo") })
    }

    @Test func theScriptChecksEveryPathAndQuotes() {
        let catalog = catalog(folderDate: "1971-08-29")
        let root = URL(fileURLWithPath: "/Staging/It's Here")
        let plan = TimestampPlanner.plan(
            files: files(catalog, root: root), catalog: catalog, roots: [root], timeZone: TimestampPlanTests.zone)
        let script = TimestampPlanner.script(plan, timeZone: TimestampPlanTests.zone)
        #expect(script.hasPrefix("#!/bin/sh\n"))
        #expect(script.contains("TZ='Asia/Tokyo'"))
        #expect(script.contains("if [ -L \"$1\" ] || [ ! -e \"$1\" ]; then"))
        #expect(script.contains("touch -c -m -t"))
        #expect(
            script.contains("set_dates '/Staging/It'\\''s Here/Example Artist' '08/29/1971 00:00:00' '197108290000.00'")
        )
        #expect(script.hasSuffix("exit $status\n"))
    }

    @Test func theScriptRefusesDatesThatSetFileCannotStore() {
        let catalog = catalog(folderDate: "1971-08-29")
        let root = URL(fileURLWithPath: "/Staging")
        let plan = TimestampPlanner.plan(
            files: files(catalog, root: root), catalog: catalog, roots: [root], timeZone: TimestampPlanTests.zone)
        let script = TimestampPlanner.script(plan, timeZone: TimestampPlanTests.zone)
        #expect(script.contains("refuse_date '/Staging/Example Artist/Synthetic Album/01 One.m4a' '1958-08-29'"))
        #expect(script.contains("refuse_date '/Staging/Example Artist/Synthetic Album/02 Two.m4a' '1959-08-29'"))
        #expect(!script.contains("set_dates '/Staging/Example Artist/Synthetic Album/01 One.m4a'"))
        #expect(!script.contains("08/29/1958"))
        #expect(script.contains("set_dates '/Staging/Example Artist' '08/29/1971 00:00:00' '197108290000.00'"))
        #expect(TimestampPlanner.scriptableDates.contains(Date(timeIntervalSince1970: 0)))
        #expect(!TimestampPlanner.scriptableDates.contains(Date(timeIntervalSince1970: -1)))
        #expect(!TimestampPlanner.scriptableDates.contains(Date(timeIntervalSince1970: 4_294_967_296)))
    }

    @Test func withoutCreationDatesOnlyDryRunsAndScriptsAreAvailable() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let url = library.root.appendingPathComponent("catalog.json")
        #expect(Run(["export", library.root.path, "-o", url.path]).status == 0)
        var environment = Environment.testing
        environment.setDates = nil
        let refused = Run(["timestamps", url.path, library.root.path], environment: environment)
        #expect(refused.status == 1)
        #expect(refused.errorText.contains("supported only on macOS"))
        let script = library.root.appendingPathComponent("dates.sh")
        let preview = Run(
            ["timestamps", url.path, library.root.path, "--dry-run", "--script", script.path], environment: environment)
        #expect(preview.status == 0, "\(preview.errorText)")
        #expect(preview.text.contains("Dates: 12 paths"))
        #expect(try String(contentsOf: script, encoding: .utf8).contains("refuse_date"))
        #expect(preview.errorText.contains("the script skips 12 paths whose dates SetFile cannot store"))
        #expect(Run(["apply", url.path, library.root.path, "--timestamps"], environment: environment).status == 1)
    }
}

#if os(macOS)
    @Suite struct TimestampExecutionTests {
        func dates(_ url: URL) throws -> (Date?, Date?) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.creationDate] as? Date, attributes[.modificationDate] as? Date)
        }

        @Test func applyWithRenameAndTimestampsDatesFilesThenFolders() throws {
            let library = try SyntheticLibrary()
            defer { library.remove() }
            let url = library.root.deletingLastPathComponent().appendingPathComponent(
                "catalog-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: url) }
            #expect(Run(["export", library.root.path, "-o", url.path]).status == 0)
            var catalog = try #require(Catalog.validate(try Data(contentsOf: url)).catalog)
            catalog.artists = ["Example Artist": ArtistEntry(folderDate: "1957-08-29")]
            try? FileManager.default.removeItem(at: url)
            try catalog.encoded().write(to: url)

            let run = Run(["apply", url.path, library.root.path, "--rename", "--timestamps"])
            #expect(run.status == 0, "\(run.errorText)")
            #expect(run.text.contains("paths dated"))
            let release = Date(timeIntervalSince1970: -357_987_600)
            let song = library.root.appendingPathComponent("Example Artist/Synthetic Album/01 First Song.m4a")
            #expect(try dates(song) == (release, release))
            #expect(
                try dates(library.root.appendingPathComponent("Example Artist/Synthetic Album")) == (release, release))
            let folderDate = ReleaseDate("1957-08-29")!.localStart(in: TimeZone(identifier: "Asia/Tokyo")!).date
            #expect(try dates(library.root.appendingPathComponent("Example Artist")) == (folderDate, folderDate))
            // Various Artists has no folderDate, so its folder keeps the dates it had.
            let various = try dates(library.root.appendingPathComponent("Various Artists"))
            #expect(various.0 != Date(timeIntervalSince1970: -326_451_600))
            #expect(run.text.contains("gives \"Various Artists\" no folderDate"))
        }

        @Test func missingTargetsAndLinksAreRefusedBeforeAnyDateIsSet() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "ilibrary-dates-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let present = directory.appendingPathComponent("present.m4a")
            FileManager.default.createFile(atPath: present.path, contents: Data())
            let before = try dates(present)
            let missing = directory.appendingPathComponent("Missing Folder")
            let date = ReleaseDate("1958-08-29")!
            func target(_ url: URL) -> DatedPath {
                DatedPath(
                    url: url, kind: .file, releaseDate: date, date: Date(timeIntervalSince1970: 0), isMidnight: true)
            }
            let plan = TimestampPlan(targets: [target(present), target(missing)], notes: [])
            #expect(throws: CommandError.self) { try TimestampPlanner.execute(plan, environment: .testing) }
            #expect(pathKind(missing) == .missing)
            #expect(try dates(present) == before)

            let link = directory.appendingPathComponent("link.m4a")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: present)
            #expect(throws: CommandError.self) {
                try TimestampPlanner.execute(TimestampPlan(targets: [target(link)], notes: []), environment: .testing)
            }
            #expect(try dates(present) == before)
        }

        @Test func theGeneratedScriptSetsTheSameDatesAndCreatesNothing() throws {
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/SetFile") else { return }
            let library = try SyntheticLibrary()
            defer { library.remove() }
            let url = library.root.appendingPathComponent("catalog.json")
            #expect(Run(["export", library.root.path, "-o", url.path]).status == 0)
            var catalog = try #require(Catalog.validate(try Data(contentsOf: url)).catalog)
            let album = try #require(catalog.albums.firstIndex { $0.album == "Synthetic Album" })
            catalog.albums[album].releaseDate = "1971-08-29"
            try FileManager.default.removeItem(at: url)
            try catalog.encoded().write(to: url)
            let older = library.root.appendingPathComponent("Download Two")
            let olderDates = try dates(older)
            let script = library.root.appendingPathComponent("dates.sh")
            #expect(Run(["timestamps", url.path, library.root.path, "--dry-run", "--script", script.path]).status == 0)
            let removed = library.root.appendingPathComponent("Download Three/02-Another Version_1002.m4a")
            try FileManager.default.removeItem(at: removed)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path]
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 1)
            #expect(pathKind(removed) == .missing)
            let release = Date(timeIntervalSince1970: 52_239_600)
            let song = library.root.appendingPathComponent("Download One/01-First Song_1001.m4a")
            for url in [song, library.root.appendingPathComponent("Download One")] {
                let (created, modified) = try dates(url)
                #expect(created == release, "creation date of \(url.lastPathComponent)")
                #expect(modified == release, "modification date of \(url.lastPathComponent)")
            }
            // The other albums are dated before 1970, which SetFile cannot store, so the script leaves them alone.
            #expect(try dates(older) == olderDates)
        }
    }
#endif
