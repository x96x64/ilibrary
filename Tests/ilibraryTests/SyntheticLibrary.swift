import Foundation
import MP4Core
import SyntheticMedia

@testable import ilibrary

/// A temporary staging folder with synthetic albums, named as downloads are named before renaming.
struct SyntheticLibrary {
    struct TrackSpec {
        var title: String
        var artist: String
        var composer: String
        var disc: Int
        var track: Int
        var trackTotal: Int
        var discTotal: Int
    }

    struct AlbumSpec {
        var folder: String
        var album: String
        var albumArtist: String
        var genre: String
        var copyright: String
        var date: String
        var compilation: Int?
        var cover: Data?
        var tracks: [TrackSpec]
    }

    let root: URL
    let albums: [AlbumSpec]

    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data((0..<400).map { UInt8($0 % 251) })
    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data((0..<300).map { UInt8(($0 * 7) % 251) })

    static let standardAlbums: [AlbumSpec] = [
        AlbumSpec(
            folder: "Download One", album: "Synthetic Album", albumArtist: "Example Artist", genre: "Pop",
            copyright: "℗ 1958 Example Records, Inc.", date: "1958-08-29T00:00:00Z", compilation: nil, cover: png,
            tracks: [
                TrackSpec(
                    title: "First Song", artist: "Example Artist", composer: "Example Writer", disc: 1, track: 1,
                    trackTotal: 3, discTotal: 1),
                TrackSpec(
                    title: "Second Song: Part 1/2", artist: "Example Artist", composer: "Second Writer", disc: 1,
                    track: 2, trackTotal: 3, discTotal: 1),
                TrackSpec(
                    title: "Third Song", artist: "Example Artist", composer: "Example Writer", disc: 1, track: 3,
                    trackTotal: 3, discTotal: 1),
            ]),
        AlbumSpec(
            folder: "Download Two", album: "Double Album", albumArtist: "Example Artist", genre: "Rock",
            copyright: "℗ 1958 Example Records, Inc.", date: "1958-08-30T00:00:00Z", compilation: 0, cover: jpeg,
            tracks: [
                TrackSpec(
                    title: "Opening", artist: "Example Artist", composer: "Example Writer", disc: 1, track: 1,
                    trackTotal: 2, discTotal: 2),
                TrackSpec(
                    title: "Middle", artist: "Example Artist", composer: "Example Writer", disc: 1, track: 2,
                    trackTotal: 2, discTotal: 2),
                TrackSpec(
                    title: "Return", artist: "Example Artist", composer: "Example Writer", disc: 2, track: 1,
                    trackTotal: 2, discTotal: 2),
                TrackSpec(
                    title: "Closing", artist: "Example Artist", composer: "Example Writer", disc: 2, track: 2,
                    trackTotal: 2, discTotal: 2),
            ]),
        AlbumSpec(
            folder: "Download Three", album: "Tribute Collection", albumArtist: "Various Artists", genre: "Pop",
            copyright: "℗ 1959 Example Records, Inc.", date: "1959-08-29T00:00:00Z", compilation: 1, cover: nil,
            tracks: [
                TrackSpec(
                    title: "Cover Version", artist: "First Guest", composer: "Example Writer", disc: 1, track: 1,
                    trackTotal: 2, discTotal: 1),
                TrackSpec(
                    title: "Another Version", artist: "Second Guest", composer: "Example Writer", disc: 1, track: 2,
                    trackTotal: 2, discTotal: 1),
            ]),
    ]

    /// The name of a track's file, as a download would name it.
    static func fileName(_ track: TrackSpec) -> String {
        String(
            format: "%02d-%@_%d.m4a", track.track + (track.disc - 1) * 10,
            track.title.replacingOccurrences(of: "/", with: "-"), 1000 + track.track)
    }

    static func pairItem(_ type: String, _ number: Int, _ total: Int) -> Data {
        var payload = Data()
        payload.appendUInt32(0)
        payload.appendUInt32(0)
        payload.appendUInt16(0)
        payload.appendUInt16(UInt16(number))
        payload.appendUInt16(UInt16(total))
        if type == "trkn" { payload.appendUInt16(0) }
        return SyntheticMP4.box(type, children: [SyntheticMP4.box("data", payload)])
    }

    static func imageItem(_ image: Data) -> Data {
        var payload = Data()
        payload.appendUInt32(image.starts(with: [0x89]) ? 14 : 13)
        payload.appendUInt32(0)
        payload.append(image)
        return SyntheticMP4.box("covr", children: [SyntheticMP4.box("data", payload)])
    }

    static func fixture(_ album: AlbumSpec, _ track: TrackSpec) -> SyntheticMP4 {
        var fixture = SyntheticMP4(layout: .movieFirst(padding: 0))
        fixture.chunkCount = 4
        fixture.chunkSize = 600 + track.track * 13 + track.disc * 7
        var items = [
            SyntheticMP4.textItem("©nam", track.title), SyntheticMP4.textItem("©ART", track.artist),
            SyntheticMP4.textItem("aART", album.albumArtist), SyntheticMP4.textItem("©alb", album.album),
            SyntheticMP4.textItem("©gen", album.genre), SyntheticMP4.textItem("©wrt", track.composer),
            SyntheticMP4.textItem("cprt", album.copyright), SyntheticMP4.textItem("©day", album.date),
            pairItem("trkn", track.track, track.trackTotal), pairItem("disk", track.disc, track.discTotal),
        ]
        if let compilation = album.compilation {
            items.append(SyntheticMP4.integerItem("cpil", UInt64(compilation), width: 1))
        }
        if let cover = album.cover { items.append(imageItem(cover)) }
        fixture.items = items
        return fixture
    }

    init(albums: [AlbumSpec] = SyntheticLibrary.standardAlbums) throws {
        root =
            FileManager.default.temporaryDirectory.appendingPathComponent("ilibrary-library-\(UUID().uuidString)")
            .standardizedFileURL
        self.albums = albums
        for album in albums {
            let folder = root.appendingPathComponent(album.folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for track in album.tracks {
                try SyntheticLibrary.fixture(album, track).data.write(
                    to: folder.appendingPathComponent(SyntheticLibrary.fileName(track)))
            }
        }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    /// The bytes of every file under the root, keyed by relative path.
    func snapshot() throws -> [String: Data] {
        var result: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(atPath: root.path)!
        while let path = enumerator.nextObject() as? String {
            let url = root.appendingPathComponent(path)
            if pathKind(url) == .file { result[path] = try Data(contentsOf: url) }
        }
        return result
    }

    func m4aFiles() throws -> [URL] { try LibraryFiles.scan([root.path]).files }
}

/// Runs the command line with captured output.
final class Run {
    let output: [String]
    let errors: [String]
    let status: Int32

    init(_ arguments: [String], environment: Environment = .testing) {
        var output: [String] = []
        var errors: [String] = []
        let console = Console(output: { output.append($0) }, error: { errors.append($0) })
        status = CommandLineInterface.run(arguments, console: console, environment: environment)
        self.output = output
        self.errors = errors
    }

    var text: String { output.joined(separator: "\n") }
    var errorText: String { errors.joined(separator: "\n") }
}

/// A clock that advances only when paused, shared by the test environments and the substitute libraries, so that
/// waits for later addition seconds take no real time.
final class SimulatedClock: @unchecked Sendable {
    static let shared = SimulatedClock()
    private let lock = NSLock()
    private var time: TimeInterval = 1_900_000_000

    var now: Date { lock.withLock { Date(timeIntervalSince1970: time) } }
    func advance(_ seconds: TimeInterval) { lock.withLock { time += max(0, seconds) } }
}

extension Environment {
    static var testing: Environment {
        var environment = Environment.system
        environment.now = { SimulatedClock.shared.now }
        environment.pause = { SimulatedClock.shared.advance($0) }
        environment.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // Tests never reach the real Music app; each test that needs a library supplies a substitute.
        environment.music = nil
        environment.musicStatus = nil
        // Nor do they reach real storage, copying, date setting, or mount state.
        environment.describeStorage = nil
        environment.restoreCopy = nil
        environment.setPreciseDates = nil
        environment.waitUntilUnmounted = nil
        return environment
    }
}
