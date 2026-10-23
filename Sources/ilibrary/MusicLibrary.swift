import Foundation

#if canImport(LibraryMac)
    import LibraryMac
#endif

/// A track of the Music library as iLibrary compares it with files.
struct LibraryTrack: Equatable, Sendable {
    var persistentID: String
    var name: String
    var album: String
    var artist: String
    var albumArtist: String
    var composer: String = ""
    var genre: String = ""
    var year: Int = 0
    var trackNumber: Int = 0
    var discNumber: Int = 0
    var comment: String = ""
    var trackCount: Int = 0
    var discCount: Int = 0
    var compilation: Bool = false
    /// The POSIX path of the track's file, when Music knows one.
    var location: String?
    var cloudStatus: String = "unknown"
}

/// The whole library as one read for a rebuild: the file tracks, the counts that reveal tracks that are not
/// file tracks, and the date added of each file track in whole seconds since 1970-01-01T00:00:00Z.
struct LibrarySnapshot: Equatable, Sendable {
    var tracks: [LibraryTrack]
    var trackCount: Int
    var fileTrackCount: Int
    var dateAddedSeconds: [String: Int]
}

/// The operations on a Music library that iLibrary uses. Track properties are never set, because Music then
/// moves and renames files.
protocol MusicLibrary: Sendable {
    /// The media folder named by Music's preferences, or nil.
    func mediaFolder() -> URL?
    /// The file tracks whose album has the given name. Reads only.
    func tracks(album: String) throws -> [LibraryTrack]
    /// All file tracks, for a location-based comparison even when cached album tags differ. The system
    /// implementation reads in bulk with a per-track fallback and is designed to return the tracks of the per-track
    /// reader; the live equivalence of the two readers was measured only for 12 synthetic tracks.
    func allTracks() throws -> [LibraryTrack]
    /// Every file track, both track counts, and the dates added, read with a fixed number of requests. Reads only.
    func librarySnapshot() throws -> LibrarySnapshot
    /// The track with a persistent ID, or nil. Reads only.
    func track(persistentID: String) throws -> LibraryTrack?
    /// Adds files in one call and returns the tracks that Music reports for them.
    func add(_ files: [URL]) throws -> [LibraryTrack]
    /// The date added of each track, in whole seconds since 1970. Reads only.
    func datesAdded(_ persistentIDs: [String]) throws -> [String: Int]
    /// Deletes the one file track with the persistent ID after confirming its name, album, and artist.
    func remove(persistentID: String, name: String, album: String, artist: String) throws
    /// Asks Music to quit.
    func quit() throws
}

#if canImport(LibraryMac) && os(macOS)
    /// The Music app on this Mac, through Apple Events.
    struct SystemMusicLibrary: MusicLibrary {
        static func convert(_ track: MusicTrackInfo) -> LibraryTrack {
            LibraryTrack(
                persistentID: track.persistentID, name: track.name, album: track.album, artist: track.artist,
                albumArtist: track.albumArtist, composer: track.composer, genre: track.genre, year: track.year,
                trackNumber: track.trackNumber, discNumber: track.discNumber, comment: track.comment,
                trackCount: track.trackCount, discCount: track.discCount, compilation: track.compilation,
                location: track.location,
                cloudStatus: track.cloudStatus)
        }

        func mediaFolder() -> URL? { MusicApp.mediaFolder() }
        func tracks(album: String) throws -> [LibraryTrack] { try MusicApp.tracks(album: album).map(Self.convert) }
        func allTracks() throws -> [LibraryTrack] { try MusicApp.allTracksPreferringBulk().map(Self.convert) }
        func librarySnapshot() throws -> LibrarySnapshot {
            let snapshot = try MusicApp.librarySnapshot()
            return LibrarySnapshot(
                tracks: snapshot.tracks.map(Self.convert), trackCount: snapshot.trackCount,
                fileTrackCount: snapshot.fileTrackCount, dateAddedSeconds: snapshot.dateAddedSeconds)
        }
        func track(persistentID: String) throws -> LibraryTrack? {
            try MusicApp.track(persistentID: persistentID).map(Self.convert)
        }
        func add(_ files: [URL]) throws -> [LibraryTrack] { try MusicApp.add(files).map(Self.convert) }
        func datesAdded(_ persistentIDs: [String]) throws -> [String: Int] {
            try MusicApp.datesAdded(persistentIDs: persistentIDs)
        }
        func remove(persistentID: String, name: String, album: String, artist: String) throws {
            try MusicApp.remove(persistentID: persistentID, name: name, album: album, artist: artist)
        }
        func quit() throws { try MusicApp.quit() }
    }
#endif
