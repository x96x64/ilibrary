import Foundation

/// The order in which albums are added to Music.
public enum AlbumOrder: String, CaseIterable, Sendable {
    /// Release date, earliest first.
    case release
    /// Artist ascending, and each artist's albums by name ascending.
    case artist
    /// Artist descending, and each artist's albums by name descending.
    case artistDescending = "artist-desc"
    /// Artist ascending, and each artist's albums by release date.
    case artistRelease = "artist-release"
}

extension Catalog {
    /// Album indices in the requested order. Albums without a release date follow dated ones where the date
    /// decides the order. Ties keep catalog order, so that the result is deterministic on every platform.
    public func albumOrder(_ order: AlbumOrder) -> [Int] {
        func artist(_ index: Int) -> String {
            TitleRules.comparisonKey(albums[index].albumArtist ?? albums[index].artist ?? "")
        }
        func name(_ index: Int) -> String { TitleRules.comparisonKey(albums[index].album) }
        func date(_ index: Int) -> ReleaseDate? { albums[index].releaseDate.flatMap { ReleaseDate($0) } }
        func byDate(_ a: Int, _ b: Int) -> Bool? {
            switch (date(a), date(b)) {
            case (let x?, let y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return nil
            }
        }
        func compare(_ a: String, _ b: String) -> Bool? { a == b ? nil : a < b }

        return albums.indices.sorted { a, b in
            let decided: Bool?
            switch order {
            case .release:
                decided = byDate(a, b) ?? compare(artist(a), artist(b)) ?? compare(name(a), name(b))
            case .artist:
                decided = compare(artist(a), artist(b)) ?? compare(name(a), name(b))
            case .artistDescending:
                decided = compare(artist(b), artist(a)) ?? compare(name(b), name(a))
            case .artistRelease:
                decided = compare(artist(a), artist(b)) ?? byDate(a, b) ?? compare(name(a), name(b))
            }
            return decided ?? (a < b)
        }
    }
}
