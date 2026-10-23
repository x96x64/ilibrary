import Foundation

/// Adds albums so that each one's addition dates are strictly later than those of the album before it.
///
/// Music exposes the date added in whole seconds and orders Recently Added by it; the order of albums that share a
/// second is unknown. When each album was added only after the previous one had been confirmed and the clock had
/// passed its latest second, every measured case showed the intended order (Measured Music Behavior).
struct SeparatedAddition {
    /// The latest addition second of the previous album, or nil before the first.
    private(set) var latest: Int?

    init(latest: Int? = nil) { self.latest = latest }

    /// How far past the previous album's latest second the clock must be before the next album is added.
    static let margin: TimeInterval = 2

    /// Starts after an album added earlier, such as the last album of an interrupted run. When its tracks can no
    /// longer be read, for example because they were removed from Music, there is nothing to follow.
    mutating func follow(_ persistentIDs: [String], music: any MusicLibrary) {
        guard !persistentIDs.isEmpty else { return }
        latest = (try? music.datesAdded(persistentIDs))?.values.max()
    }

    /// Waits until the next album can be added.
    func waitForNext(environment: Environment) {
        guard let latest else { return }
        let ready = TimeInterval(latest) + 1 + SeparatedAddition.margin
        var remaining = ready - environment.now().timeIntervalSince1970
        while remaining > 0 {
            environment.pause(min(remaining, 1))
            remaining = ready - environment.now().timeIntervalSince1970
        }
    }

    /// Reads the addition dates of an album just added and confirms that they follow the previous album's.
    /// Returns false, leaving the previous album as the reference, when an addition second is not later.
    mutating func confirm(_ persistentIDs: [String], music: any MusicLibrary) throws -> Bool {
        let dates = try music.datesAdded(persistentIDs)
        guard dates.count == Set(persistentIDs).count, let earliest = dates.values.min(),
            let newest = dates.values.max()
        else { throw CommandError.failure("Music did not report the addition dates of the album") }
        if let latest, earliest <= latest { return false }
        latest = newest
        return true
    }
}
