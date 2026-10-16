import Foundation
import MP4Core
import Testing

@testable import ilibrary

/// A substitute Music library that behaves as Music 1.7 was measured to behave (Music Behavior report):
/// files inside the media folder are added in place, a file already in the library is returned as its existing
/// track, and files outside the media folder are copied into it.
final class FakeMusic: MusicLibrary, @unchecked Sendable {
    let media: URL?
    var library: [LibraryTrack] = []
    var addCalls: [[String]] = []
    var failOnAdd: Int?
    /// Report tracks at other places, as Music would after copying files.
    var misplace = false
    private var counter = 0

    init(media: URL?) { self.media = media }

    func mediaFolder() -> URL? { media }
    func tracks(album: String) throws -> [LibraryTrack] { library.filter { $0.album == album } }
    func track(persistentID: String) throws -> LibraryTrack? { library.first { $0.persistentID == persistentID } }

    func add(_ files: [URL]) throws -> [LibraryTrack] {
        addCalls.append(files.map(\.lastPathComponent))
        if failOnAdd == addCalls.count { throw CocoaError(.fileReadUnknown) }
        return try files.map { file in
            if let existing = library.first(where: { $0.location == file.path }) { return existing }
            let tags = try LibraryFiles.read(file)
            counter += 1
            var location = file.path
            if misplace || !(media.map { isWithin(file, $0) } ?? false) {
                location =
                    file.deletingLastPathComponent().appendingPathComponent("copy \(file.lastPathComponent)").path
            }
            let track = LibraryTrack(
                persistentID: String(format: "%016X", counter), name: tags.tags.title ?? "",
                album: tags.tags.album ?? "",
                artist: LibraryFiles.text(tags.file, .artist) ?? "", albumArtist: tags.tags.albumArtist ?? "",
                trackNumber: tags.tags.trackNumber ?? 0, discNumber: tags.tags.discNumber ?? 0, location: location)
            library.append(track)
            return track
        }
    }
}

struct AddFixture {
    let library: SyntheticLibrary
    let media: URL
    let music: FakeMusic
    var environment: Environment

    init() throws {
        library = try SyntheticLibrary()
        media = library.root.deletingLastPathComponent().appendingPathComponent(
            "media-\(UUID().uuidString)/Media.localized")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        music = FakeMusic(media: media)
        environment = Environment.testing
        environment.music = music
    }

    func remove() {
        library.remove()
        try? FileManager.default.removeItem(at: media.deletingLastPathComponent())
    }

    func run(_ arguments: [String]) -> Run { Run(["add", library.root.path] + arguments, environment: environment) }

    var journal: AddJournal {
        (try? AddJournal.load(library.root.appendingPathComponent(AddJournal.fileName))) ?? AddJournal()
    }

    func mediaFiles() -> [String] {
        let enumerator = FileManager.default.enumerator(atPath: media.path)
        var files: [String] = []
        while let path = enumerator?.nextObject() as? String {
            if path.hasSuffix(".m4a") { files.append(path) }
        }
        return files.sorted()
    }
}

@Suite struct AddTests {
    @Test func albumsAreMovedAndAddedInPlaceOneAtATimeInReleaseOrder() throws {
        let fixture = try AddFixture()
        defer { fixture.remove() }
        let run = fixture.run([])
        #expect(run.status == 0, "\(run.errorText)")
        #expect(run.text.contains("Added and confirmed: 3 album(s)"))
        #expect(fixture.music.addCalls.map(\.count) == [3, 4, 2])
        #expect(fixture.music.addCalls[0].first == "01-First Song_1001.m4a")
        #expect(fixture.mediaFiles().filter { $0.hasPrefix("Music/Example Artist/Synthetic Album/") }.count == 3)
        #expect(fixture.mediaFiles().count == 9)
        #expect(try fixture.library.m4aFiles().isEmpty)
        let entries = fixture.journal.entries
        #expect(entries.map(\.state) == [.added, .added, .added])
        #expect(entries.map(\.album) == ["Synthetic Album", "Double Album", "Tribute Collection"])
        #expect(entries.allSatisfy { $0.persistentIDs.count == $0.destinations.count })
        #expect(
            fixture.music.library.allSatisfy {
                $0.location.map { isWithin(URL(fileURLWithPath: $0), fixture.media) } ?? false
            })
    }

    @Test(arguments: [
        ("artist", ["Double Album", "Synthetic Album", "Tribute Collection"]),
        ("artist-desc", ["Tribute Collection", "Synthetic Album", "Double Album"]),
        ("artist-release", ["Synthetic Album", "Double Album", "Tribute Collection"]),
    ])
    func everyOrderIsHonored(order: String, albums: [String]) throws {
        let fixture = try AddFixture()
        defer { fixture.remove() }
        #expect(fixture.run(["--order", order]).status == 0)
        #expect(fixture.journal.entries.map(\.album) == albums)
    }

    @Test func aDryRunChangesNothing() throws {
        let fixture = try AddFixture()
        defer { fixture.remove() }
        let before = try fixture.library.snapshot()
        let run = fixture.run(["--dry-run"])
        #expect(run.status == 0, "\(run.errorText)")
        #expect(run.text.contains("Albums to add in release order: 3"))
        #expect(run.text.contains("note: Music may rename it to 01 First Song.m4a"))
        #expect(run.text.contains("Dry run: nothing was changed."))
        #expect(try fixture.library.snapshot() == before)
        #expect(fixture.music.addCalls.isEmpty)
        #expect(fixture.mediaFiles().isEmpty)
    }

    @Test func anExistingTrackStopsTheRunBeforeItsAlbum() throws {
        let fixture = try AddFixture()
        defer { fixture.remove() }
        fixture.music.library = [
            LibraryTrack(
                persistentID: "EXISTING", name: "Opening", album: "Double Album", artist: "Example Artist",
                albumArtist: "Example Artist")
        ]
        let run = fixture.run([])
        #expect(run.status == 1)
        #expect(run.errorText.contains("the library already holds \"Opening\" of \"Double Album\""))
        #expect(run.errorText.contains("1 album(s) were added before this stop"))
        #expect(fixture.music.addCalls.count == 1)
        #expect(try fixture.library.m4aFiles().count == 6)
        #expect(fixture.mediaFiles().count == 3)
    }

    @Test func anInterruptedRunResumesWithoutMovingAgain() throws {
        let fixture = try AddFixture()
        defer { fixture.remove() }
        fixture.music.failOnAdd = 2
        let first = fixture.run([])
        #expect(first.status == 1)
        #expect(first.errorText.contains("run add again to resume"))
        #expect(fixture.journal.entries.map(\.state) == [.added, .moving])
        #expect(fixture.mediaFiles().count == 7)
        fixture.music.failOnAdd = nil
        let second = fixture.run([])
        #expect(second.status == 0, "\(second.errorText)")
        #expect(second.text.contains("Resuming 1 album(s)"))
        #expect(second.text.contains("Resumed: Example Artist - Double Album, 4 tracks confirmed"))
        #expect(fixture.journal.entries.map(\.state) == [.added, .added, .added])
        #expect(fixture.music.library.count == 9)
        #expect(fixture.mediaFiles().count == 9)
    }

    @Test func anAlbumAddedButNotRecordedIsRecognizedOnResumption() throws {
        let fixture = try AddFixture()
        defer { fixture.remove() }
        #expect(fixture.run([]).status == 0)
        var journal = fixture.journal
        journal.entries[1].state = .moving
        try journal.save(fixture.library.root.appendingPathComponent(AddJournal.fileName))
        let calls = fixture.music.addCalls.count
        let run = fixture.run([])
        #expect(run.status == 0, "\(run.errorText)")
        #expect(fixture.music.addCalls.count == calls)
        #expect(fixture.journal.entries[1].state == .added)
        #expect(fixture.music.library.count == 9)
    }

    @Test func tracksReportedElsewhereAreNotConfirmed() throws {
        let fixture = try AddFixture()
        defer { fixture.remove() }
        fixture.music.misplace = true
        let run = fixture.run([])
        #expect(run.status == 1)
        #expect(run.errorText.contains("the album is not confirmed"))
        #expect(fixture.journal.entries.map(\.state) == [.moving])
        #expect(fixture.music.addCalls.count == 1)
    }

    @Test func missingTagsCollisionsAndUnavailableMusicChangeNothing() throws {
        var fixture = try AddFixture()
        defer { fixture.remove() }
        let before = try fixture.library.snapshot()
        let occupied = fixture.media.appendingPathComponent("Music/Example Artist/Synthetic Album")
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: occupied.appendingPathComponent("01-First Song_1001.m4a"))
        let collision = fixture.run([])
        #expect(collision.status == 1)
        #expect(collision.errorText.contains("already exists in the media folder"))
        #expect(try fixture.library.snapshot() == before)
        try FileManager.default.removeItem(at: occupied.appendingPathComponent("01-First Song_1001.m4a"))

        let inside = Run(["add", fixture.media.path], environment: fixture.environment)
        #expect(inside.status == 2)
        #expect(
            Run(["add", fixture.library.root.path, "--order", "random"], environment: fixture.environment).status == 2)

        fixture.environment.music = nil
        let unavailable = fixture.run([])
        #expect(unavailable.status == 1)
        #expect(unavailable.errorText.contains("requires macOS"))
        fixture.environment.music = FakeMusic(media: nil)
        #expect(fixture.run([]).errorText.contains("media folder is unknown"))
        #expect(try fixture.library.snapshot() == before)
    }

    @Test func filesWithoutAnAlbumArtistAreRefused() throws {
        let fixture = try AddFixture()
        defer { fixture.remove() }
        let file = try #require(try fixture.library.m4aFiles().first)
        var mp4 = try MP4File(contentsOf: file)
        try mp4.removeMetadata(.albumArtist)
        try mp4.removeMetadata(.artist)
        try MP4Writer.write(mp4, to: file)
        let before = try fixture.library.snapshot()
        let run = fixture.run([])
        #expect(run.status == 1)
        #expect(run.errorText.contains("has no album artist"))
        #expect(try fixture.library.snapshot() == before)
        #expect(fixture.music.addCalls.isEmpty)
    }
}
