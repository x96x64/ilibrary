import CatalogCore
import Foundation
import Testing

@testable import ilibrary

@Suite struct ExportStrictTests {
    /// Item positions in `SyntheticLibrary.fixture`.
    static let albumItem = 3
    static let dateItem = 7
    static let trackItem = 8

    func rewrite(_ library: SyntheticLibrary, albumIndex: Int, trackIndex: Int, removing items: [Int]) throws {
        let album = library.albums[albumIndex]
        let spec = album.tracks[trackIndex]
        var fixture = SyntheticLibrary.fixture(album, spec)
        for item in items.sorted(by: >) { fixture.items.remove(at: item) }
        let name = library.root.appendingPathComponent(album.folder).appendingPathComponent(
            SyntheticLibrary.fileName(spec))
        try fixture.data.write(to: name)
    }

    /// Runs a strict export and checks the refusal, with and without `--dry-run`, and that nothing exists afterwards.
    func expectRefusal(
        _ library: SyntheticLibrary, extra: [String] = [], contains message: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let work = library.root.deletingLastPathComponent().appendingPathComponent("ilibrary-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let catalog = work.appendingPathComponent("catalog.json")
        let covers = work.appendingPathComponent("covers")
        for dry in [false, true] {
            let run = Run(
                ["export", library.root.path] + extra + ["-o", catalog.path, "--artwork", covers.path, "--strict"]
                    + (dry ? ["--dry-run"] : []))
            #expect(run.status == 1, "\(run.errorText)", sourceLocation: sourceLocation)
            #expect(run.errorText.contains("ilibrary: error: "), sourceLocation: sourceLocation)
            #expect(run.errorText.contains(message), "\(run.errorText)", sourceLocation: sourceLocation)
            #expect(
                run.errors.last == "ilibrary: error: strict export refused; nothing was changed",
                sourceLocation: sourceLocation)
            #expect(run.output.isEmpty, sourceLocation: sourceLocation)
            #expect(pathKind(catalog) == .missing, sourceLocation: sourceLocation)
            #expect(pathKind(covers) == .missing, sourceLocation: sourceLocation)
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty, sourceLocation: sourceLocation)
        }
    }

    @Test func aCompleteLibraryPassesAndMatchesTheNonStrictCatalog() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let work = library.root.deletingLastPathComponent().appendingPathComponent("ilibrary-work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let plain = work.appendingPathComponent("plain.json")
        let strict = work.appendingPathComponent("strict.json")
        let first = Run(["export", library.root.path, "-o", plain.path])
        let second = Run(["export", library.root.path, "-o", strict.path, "--strict"])
        #expect(first.status == 0 && second.status == 0, "\(second.errorText)")
        #expect(second.errors.isEmpty, "\(second.errorText)")
        #expect(try Data(contentsOf: plain) == Data(contentsOf: strict))
        let preview = Run([
            "export", library.root.path, "-o", work.appendingPathComponent("d.json").path, "--strict", "--dry-run",
        ])
        #expect(preview.status == 0)
        #expect(preview.text.contains("Dry run: nothing was written."))
        #expect(second.text.replacingOccurrences(of: strict.path, with: plain.path) == first.text)
    }

    @Test func aSkippedSymbolicLinkIsRefused() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let target = try #require(try library.m4aFiles().first)
        try FileManager.default.createSymbolicLink(
            at: library.root.appendingPathComponent("Download One/link.m4a"), withDestinationURL: target)
        try expectRefusal(library, contains: "symbolic links are not followed; not exported")
        let plain = Run(["export", library.root.path, "-o", library.root.appendingPathComponent("c.json").path])
        #expect(plain.status == 0)
        #expect(plain.errorText.contains("ilibrary: warning: "))
    }

    @Test func aProtectedFileIsRefused() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        try Data("x".utf8).write(to: library.root.appendingPathComponent("Download One/locked.m4p"))
        try expectRefusal(library, contains: "protected .m4p files are not supported; not exported")
    }

    @Test func anExplicitlyNamedNonM4aFileIsRefused() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let note = library.root.appendingPathComponent("note.txt")
        try Data("x".utf8).write(to: note)
        try expectRefusal(library, extra: [note.path], contains: "not an .m4a file; not exported")
    }

    @Test func aMissingAlbumTagIsRefused() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        try rewrite(library, albumIndex: 0, trackIndex: 0, removing: [Self.albumItem])
        try expectRefusal(library, contains: "has no album tag; not exported")
    }

    @Test func aMissingTrackNumberIsRefused() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        try rewrite(library, albumIndex: 0, trackIndex: 2, removing: [Self.trackItem])
        try expectRefusal(library, contains: "has no track number; not exported")
    }

    @Test func aRepeatedDiscAndTrackPairIsRefused() throws {
        var albums = SyntheticLibrary.standardAlbums
        var repeated = albums[2].tracks[1]
        repeated.title = "Repeated"
        albums[2].tracks[1].track = 1
        albums[2].tracks.append(repeated)
        albums[2].tracks[2].track = 1
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        try expectRefusal(library, contains: "repeats disc 1 track 1 of \"Tribute Collection\"; not exported")
    }

    @Test func discNumbersThatAreNotConsecutiveAreRefused() throws {
        var albums = SyntheticLibrary.standardAlbums
        for index in albums[1].tracks.indices where albums[1].tracks[index].disc == 2 {
            albums[1].tracks[index].disc = 3
        }
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        try expectRefusal(library, contains: "\"Double Album\" has disc numbers [1, 3]")
    }

    @Test func trackNumbersThatAreNotConsecutiveAreRefused() throws {
        var albums = [SyntheticLibrary.standardAlbums[0]]
        albums[0].tracks.remove(at: 1)
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        try expectRefusal(library, contains: "\"Synthetic Album\" disc 1 has track numbers [1, 3]")
    }

    @Test func aYearOnlyDateIsRefusedStrictlyAndExportedWithoutIt() throws {
        var albums = SyntheticLibrary.standardAlbums
        albums[0].date = "1980"
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        try expectRefusal(library, contains: "has the release date \"1980\", which is not a full YYYY-MM-DD date")
        let url = library.root.appendingPathComponent("catalog.json")
        let plain = Run(["export", library.root.path, "-o", url.path])
        #expect(plain.status == 0, "\(plain.errorText)")
        #expect(plain.errors.isEmpty, "\(plain.errorText)")
        let catalog = try #require(Catalog.validate(try Data(contentsOf: url)).catalog)
        #expect(catalog.albums.first { $0.album == "Synthetic Album" }?.releaseDate == nil)
    }

    @Test func aMalformedDateIsRefused() throws {
        var albums = SyntheticLibrary.standardAlbums
        albums[1].date = "1982-13-40"
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        try expectRefusal(library, contains: "has the release date \"1982-13-40\"")
    }

    @Test func anAbsentDateIsPermitted() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        for (albumIndex, album) in library.albums.enumerated() {
            for trackIndex in album.tracks.indices {
                try rewrite(library, albumIndex: albumIndex, trackIndex: trackIndex, removing: [Self.dateItem])
            }
        }
        let url = library.root.appendingPathComponent("catalog.json")
        let run = Run(["export", library.root.path, "-o", url.path, "--strict"])
        #expect(run.status == 0, "\(run.errorText)")
        #expect(run.errors.isEmpty, "\(run.errorText)")
        let catalog = try #require(Catalog.validate(try Data(contentsOf: url)).catalog)
        #expect(catalog.albums.allSatisfy { $0.releaseDate == nil })
    }

    @Test func everyReasonIsListedAndRemainingWarningsStayWarnings() throws {
        var albums = SyntheticLibrary.standardAlbums
        albums[0].date = "1980"
        albums[0].tracks.remove(at: 1)
        albums[2].tracks[1].artist = "Second Guest"
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        try rewrite(library, albumIndex: 1, trackIndex: 0, removing: [Self.albumItem])
        let catalog = library.root.appendingPathComponent("catalog.json")
        let run = Run(["export", library.root.path, "-o", catalog.path, "--strict"])
        #expect(run.status == 1)
        #expect(run.errorText.contains("has no album tag"))
        #expect(run.errorText.contains("has the release date \"1980\""))
        #expect(run.errorText.contains("has track numbers [1, 3]"))
        #expect(pathKind(catalog) == .missing)
    }

    @Test func aTrackTotalAboveTheExportedCountIsRefused() throws {
        var albums = SyntheticLibrary.standardAlbums
        for index in albums[2].tracks.indices { albums[2].tracks[index].trackTotal = 3 }
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        try expectRefusal(library, contains: "\"Tribute Collection\" disc 1 declares 3 tracks but 2 would be exported")
    }

    @Test func differingTrackTotalsWithinADiscAreRefused() throws {
        var albums = SyntheticLibrary.standardAlbums
        albums[2].tracks[0].trackTotal = 2
        albums[2].tracks[1].trackTotal = 5
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        try expectRefusal(
            library, contains: "\"Tribute Collection\" disc 1 has tracks that declare different track totals [2, 5]")
    }

    @Test func aDiscTotalAboveTheExportedCountIsRefused() throws {
        var albums = SyntheticLibrary.standardAlbums
        for index in albums[1].tracks.indices { albums[1].tracks[index].discTotal = 3 }
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        try expectRefusal(library, contains: "\"Double Album\" declares 3 discs but 2 would be exported")
    }

    @Test func differingDiscTotalsWithinAnAlbumAreRefused() throws {
        var albums = SyntheticLibrary.standardAlbums
        albums[1].tracks[0].discTotal = 3
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        try expectRefusal(
            library, contains: "\"Double Album\" has tracks that declare different disc totals [2, 3]")
    }

    @Test func undeclaredTotalsPass() throws {
        var albums = SyntheticLibrary.standardAlbums
        for album in albums.indices {
            for index in albums[album].tracks.indices {
                albums[album].tracks[index].trackTotal = 0
                albums[album].tracks[index].discTotal = 0
            }
        }
        albums[0].tracks.remove(at: 2)
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        let run = Run([
            "export", library.root.path, "-o", library.root.appendingPathComponent("c.json").path, "--strict",
        ])
        #expect(run.status == 0, "\(run.errorText)")
        #expect(run.errors.isEmpty, "\(run.errorText)")
    }
}
