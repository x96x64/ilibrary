import Foundation

/// The tags of one file, as read before metadata is applied.
public struct FileTags: Equatable, Sendable {
    public var path: String
    public var album: String?
    public var albumArtist: String?
    public var discNumber: Int?
    public var trackNumber: Int?
    public var title: String?

    public init(
        path: String, album: String?, albumArtist: String? = nil, discNumber: Int? = nil, trackNumber: Int? = nil,
        title: String? = nil
    ) {
        self.path = path
        self.album = album
        self.albumArtist = albumArtist
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.title = title
    }
}

public enum MatchMethod: String, Equatable, Sendable {
    /// The file's disc and track numbers address the track.
    case discAndTrack = "disc and track"
    /// The file's track number counts through all discs, as some multi-disc downloads number tracks.
    case continuousNumbering = "continuous numbering"
    /// The file's title identifies exactly one track of the album.
    case title
}

public struct TrackMatch: Equatable, Sendable {
    public var file: FileTags
    public var reference: TrackReference
    public var method: MatchMethod
    /// False when the file has no title to cross-check, or when its title differs.
    public var titleConfirmed: Bool
    /// True when the numbers were accepted although the file's title differs from the catalog's, which is
    /// the case when a catalog corrects a title. Applying the catalog then changes the title.
    public var titleDiffers = false
}

public struct UnmatchedFile: Equatable, Sendable {
    public var file: FileTags
    public var reason: String
}

public struct MatchReport: Equatable, Sendable {
    public var matches: [TrackMatch] = []
    public var unmatched: [UnmatchedFile] = []
    /// Tracks of matched albums for which no file was found.
    public var missing: [TrackReference] = []
}

/// Matches files to catalog tracks: by album name or alias, then by disc and track number, by numbering that
/// continues across discs, and by title. Numbers whose title disagrees are accepted only when no track of the
/// album carries the file's title, and only while more of the album's titles agree than differ: continuous
/// numbering read as disc and track numbers applied metadata to the wrong tracks during manual curation.
/// Every match and every refusal is reported.
public struct CatalogMatcher: Sendable {
    public let catalog: Catalog
    let rules: TitleRules

    public init(catalog: Catalog) {
        self.catalog = catalog
        rules = TitleRules(catalog.titleRules)
    }

    func albumKeys(_ album: Album) -> Set<String> {
        Set(([album.album] + (album.aliases ?? [])).map(rules.matchingKey))
    }

    func titlesAgree(_ fileTitle: String?, _ reference: TrackReference) -> Bool? {
        guard let fileTitle, !fileTitle.isEmpty else { return nil }
        return rules.matchingKey(fileTitle) == rules.matchingKey(catalog.track(reference).title)
    }

    public func match(_ files: [FileTags]) -> MatchReport {
        var report = MatchReport()
        var claimed: [TrackReference: [TrackMatch]] = [:]
        let keys = catalog.albums.map(albumKeys)
        for file in files {
            guard let album = file.album, !album.isEmpty else {
                report.unmatched.append(UnmatchedFile(file: file, reason: "the file has no album name"))
                continue
            }
            let key = rules.matchingKey(album)
            var candidates = catalog.albums.indices.filter { keys[$0].contains(key) }
            if candidates.count > 1, let artist = file.albumArtist, !artist.isEmpty {
                let artistKey = TitleRules.comparisonKey(artist)
                candidates = candidates.filter {
                    let album = catalog.albums[$0]
                    return TitleRules.comparisonKey(album.albumArtist ?? album.artist ?? "") == artistKey
                }
            }
            guard candidates.count == 1 else {
                let reason =
                    candidates.isEmpty
                    ? "album \"\(album)\" is not in the catalog"
                    : "album \"\(album)\" matches \(candidates.count) catalog albums"
                report.unmatched.append(UnmatchedFile(file: file, reason: reason))
                continue
            }
            switch matchTrack(file, album: candidates[0]) {
            case .success(let match): claimed[match.reference, default: []].append(match)
            case .failure(let failure): report.unmatched.append(failure)
            }
        }
        for (reference, matches) in claimed.sorted(by: { $0.key < $1.key }) {
            if matches.count == 1 {
                report.matches.append(matches[0])
            } else {
                for match in matches {
                    report.unmatched.append(
                        UnmatchedFile(file: match.file, reason: "\(matches.count) files match \(reference)"))
                }
            }
        }
        // An album with as many differing titles as agreeing ones is refused as a whole: its numbering,
        // or the release that the catalog describes, may differ from the files.
        for album in Set(report.matches.map(\.reference.album)) {
            let matches = report.matches.filter { $0.reference.album == album }
            // Only titles that agree support the numbering; files without a title tag support nothing.
            let differing = matches.filter(\.titleDiffers).count
            let confirmed = matches.filter(\.titleConfirmed).count
            guard differing > 0, differing >= confirmed else { continue }
            let reason =
                "the titles of \(differing) files differ from those of \"\(catalog.albums[album].album)\" at their disc "
                + "and track numbers, and only \(confirmed) agree; check the numbering and the album"
            report.unmatched += matches.map { UnmatchedFile(file: $0.file, reason: reason) }
            report.matches.removeAll { $0.reference.album == album }
        }
        let matchedAlbums = Set(report.matches.map(\.reference.album))
        let found = Set(report.matches.map(\.reference))
        for albumIndex in matchedAlbums.sorted() {
            for (discIndex, disc) in catalog.albums[albumIndex].discs.enumerated() {
                for trackIndex in disc.tracks.indices {
                    let reference = TrackReference(album: albumIndex, disc: discIndex + 1, track: trackIndex + 1)
                    if !found.contains(reference) { report.missing.append(reference) }
                }
            }
        }
        return report
    }

    enum Outcome {
        case success(TrackMatch)
        case failure(UnmatchedFile)
    }

    func matchTrack(_ file: FileTags, album albumIndex: Int) -> Outcome {
        let album = catalog.albums[albumIndex]
        var byNumber: TrackReference?
        if let track = file.trackNumber {
            let disc = file.discNumber ?? 1
            if (1...album.discs.count).contains(disc), (1...max(1, album.discs[disc - 1].tracks.count)).contains(track),
                !album.discs[disc - 1].tracks.isEmpty
            {
                byNumber = TrackReference(album: albumIndex, disc: disc, track: track)
            }
        }
        var continuous: TrackReference?
        if let track = file.trackNumber, album.discs.count > 1 {
            var remaining = track
            for (discIndex, disc) in album.discs.enumerated() {
                if remaining >= 1 && remaining <= disc.tracks.count {
                    continuous = TrackReference(album: albumIndex, disc: discIndex + 1, track: remaining)
                    break
                }
                remaining -= disc.tracks.count
            }
        }
        var byTitle: [TrackReference] = []
        if let title = file.title, !title.isEmpty {
            let key = rules.matchingKey(title)
            for (discIndex, disc) in album.discs.enumerated() {
                for (trackIndex, track) in disc.tracks.enumerated() where rules.matchingKey(track.title) == key {
                    byTitle.append(TrackReference(album: albumIndex, disc: discIndex + 1, track: trackIndex + 1))
                }
            }
        }

        if let byNumber {
            switch titlesAgree(file.title, byNumber) {
            case nil:
                return .success(
                    TrackMatch(file: file, reference: byNumber, method: .discAndTrack, titleConfirmed: false))
            case true?:
                return .success(
                    TrackMatch(file: file, reference: byNumber, method: .discAndTrack, titleConfirmed: true))
            case false?: break
            }
        }
        if let continuous, continuous != byNumber, titlesAgree(file.title, continuous) != false {
            let confirmed = titlesAgree(file.title, continuous) == true
            // Without a title, continuous numbering is used only where disc and track numbers cannot apply.
            if confirmed || byNumber == nil {
                return .success(
                    TrackMatch(
                        file: file, reference: continuous, method: .continuousNumbering, titleConfirmed: confirmed))
            }
        }
        if byTitle.count == 1 {
            return .success(TrackMatch(file: file, reference: byTitle[0], method: .title, titleConfirmed: true))
        }
        if let byNumber, byTitle.isEmpty {
            return .success(
                TrackMatch(
                    file: file, reference: byNumber, method: .discAndTrack, titleConfirmed: false, titleDiffers: true))
        }
        let reason: String
        if byTitle.count > 1 {
            reason = "the title matches \(byTitle.count) tracks of \"\(album.album)\""
        } else if let byNumber {
            reason =
                "\(byNumber) is \"\(catalog.track(byNumber).title)\", but the file's title is \"\(file.title ?? "")\""
        } else {
            reason = "no track of \"\(album.album)\" matches its numbers or title"
        }
        return .failure(UnmatchedFile(file: file, reason: reason))
    }
}
