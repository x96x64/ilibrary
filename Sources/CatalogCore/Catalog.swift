import Foundation

/// A catalog in the `ilibrary-catalog-1` format: the reference record from which metadata is applied.
/// Album-level values apply to every track and may be overridden per track. Empty strings mean unknown.
public struct Catalog: Codable, Equatable, Sendable {
    public static let formatIdentifier = "ilibrary-catalog-1"

    public var format: String
    public var titleRules: TitleRuleSettings?
    public var artists: [String: ArtistEntry]?
    public var albums: [Album]

    public init(
        titleRules: TitleRuleSettings? = nil, artists: [String: ArtistEntry]? = nil, albums: [Album]
    ) {
        format = Catalog.formatIdentifier
        self.titleRules = titleRules
        self.artists = artists
        self.albums = albums
    }
}

public enum TitleCase: String, Codable, CaseIterable, Sendable {
    case keep, mla, apa, start
}

public struct TitleRuleSettings: Codable, Equatable, Sendable {
    public var caseStyle: TitleCase?
    public var removeQualifiers: [String]?
    public var bracketNested: Bool?
    public var preserve: [String]?

    enum CodingKeys: String, CodingKey {
        case caseStyle = "case"
        case removeQualifiers, bracketNested, preserve
    }

    public init(
        caseStyle: TitleCase? = nil, removeQualifiers: [String]? = nil, bracketNested: Bool? = nil,
        preserve: [String]? = nil
    ) {
        self.caseStyle = caseStyle
        self.removeQualifiers = removeQualifiers
        self.bracketNested = bracketNested
        self.preserve = preserve
    }
}

public struct ArtistEntry: Codable, Equatable, Sendable {
    /// The date given to the artist's folder, as `YYYY-MM-DD`.
    public var folderDate: String?

    public init(folderDate: String? = nil) { self.folderDate = folderDate }
}

public struct Album: Codable, Equatable, Sendable {
    public var album: String
    public var aliases: [String]?
    public var albumArtist: String?
    public var artist: String?
    public var genre: String?
    public var composer: String?
    public var copyright: String?
    public var releaseDate: String?
    public var compilation: Bool?
    public var artwork: String?
    /// Evidence for the values; ignored when metadata is applied.
    public var notes: String?
    public var sources: [String]?
    public var discs: [Disc]

    public init(
        album: String, aliases: [String]? = nil, albumArtist: String? = nil, artist: String? = nil,
        genre: String? = nil, composer: String? = nil, copyright: String? = nil, releaseDate: String? = nil,
        compilation: Bool? = nil, artwork: String? = nil, notes: String? = nil, sources: [String]? = nil,
        discs: [Disc]
    ) {
        self.album = album
        self.aliases = aliases
        self.albumArtist = albumArtist
        self.artist = artist
        self.genre = genre
        self.composer = composer
        self.copyright = copyright
        self.releaseDate = releaseDate
        self.compilation = compilation
        self.artwork = artwork
        self.notes = notes
        self.sources = sources
        self.discs = discs
    }
}

public struct Disc: Codable, Equatable, Sendable {
    public var tracks: [Track]

    public init(tracks: [Track]) { self.tracks = tracks }
}

public struct Track: Codable, Equatable, Sendable {
    public var title: String
    public var artist: String?
    public var composer: String?
    public var genre: String?
    public var copyright: String?
    public var releaseDate: String?
    public var notes: String?
    public var sources: [String]?

    public init(
        title: String, artist: String? = nil, composer: String? = nil, genre: String? = nil,
        copyright: String? = nil, releaseDate: String? = nil, notes: String? = nil, sources: [String]? = nil
    ) {
        self.title = title
        self.artist = artist
        self.composer = composer
        self.genre = genre
        self.copyright = copyright
        self.releaseDate = releaseDate
        self.notes = notes
        self.sources = sources
    }
}

/// The position of a track in a catalog, with one-based disc and track numbers.
public struct TrackReference: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var album: Int
    public var disc: Int
    public var track: Int

    public init(album: Int, disc: Int, track: Int) {
        self.album = album
        self.disc = disc
        self.track = track
    }

    public static func < (lhs: TrackReference, rhs: TrackReference) -> Bool {
        (lhs.album, lhs.disc, lhs.track) < (rhs.album, rhs.disc, rhs.track)
    }

    public var description: String { "album \(album + 1), disc \(disc), track \(track)" }
}

/// The effective metadata of one track after album-level values and per-track overrides are combined and the
/// title rules are applied.
public struct ResolvedTrack: Equatable, Sendable {
    public var reference: TrackReference
    public var title: String
    public var album: String
    public var artist: String?
    public var albumArtist: String?
    public var composer: String?
    public var genre: String?
    public var copyright: String?
    public var releaseDate: ReleaseDate?
    public var compilation: Bool
    public var artwork: String?
    public var discCount: Int
    public var trackCount: Int
}

extension Catalog {
    public func track(_ reference: TrackReference) -> Track {
        albums[reference.album].discs[reference.disc - 1].tracks[reference.track - 1]
    }

    /// Every track with its effective values. Empty strings are treated as unknown.
    public func resolvedTracks() -> [ResolvedTrack] {
        let rules = TitleRules(titleRules)
        return albums.enumerated().flatMap { albumIndex, album in
            album.discs.enumerated().flatMap { discIndex, disc in
                disc.tracks.indices.map { trackIndex in
                    resolve(TrackReference(album: albumIndex, disc: discIndex + 1, track: trackIndex + 1), rules: rules)
                }
            }
        }
    }

    /// The effective values of a track, with the catalog's title rules applied to its title.
    public func resolve(_ reference: TrackReference) -> ResolvedTrack {
        resolve(reference, rules: TitleRules(titleRules))
    }

    func resolve(_ reference: TrackReference, rules: TitleRules) -> ResolvedTrack {
        let album = albums[reference.album]
        let track = self.track(reference)
        func known(_ values: String?...) -> String? { values.first { ($0 ?? "").isEmpty == false } ?? nil }
        return ResolvedTrack(
            reference: reference, title: rules.apply(track.title).title, album: album.album,
            artist: known(track.artist, album.artist), albumArtist: known(album.albumArtist, album.artist),
            composer: known(track.composer, album.composer), genre: known(track.genre, album.genre),
            copyright: known(track.copyright, album.copyright),
            releaseDate: known(track.releaseDate, album.releaseDate).flatMap { ReleaseDate($0) },
            compilation: album.compilation ?? false, artwork: known(album.artwork), discCount: album.discs.count,
            trackCount: album.discs[reference.disc - 1].tracks.count)
    }
}
