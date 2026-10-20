// Pure logic of the M11 qualification probe: the guards, the reader comparison, and the sanitized report.
// Nothing here sends an Apple Event or touches the file system. Built only on macOS because
// `MusicTrackInfo` exists only there.
#if os(macOS)
    import Foundation
    import LibraryMac

    /// The reason for which the probe declines to run.
    enum ProbeRefusal: Equatable {
        case notTestUser
        case privileged
        case accountSignedIn
        case accountUnreadable
        case outputExists

        var message: String {
            switch self {
            case .notTestUser: "the process user is not a separate test user; Music was not touched"
            case .privileged: "the probe must not run with administrator privileges"
            case .accountSignedIn: "an Apple Account is signed in; use a new test user"
            case .accountUnreadable: "the account preference could not be read; Music was not touched"
            case .outputExists: "the output file already exists; it is never overwritten"
            }
        }
    }

    /// The signed-in state read from the MobileMeAccounts preference.
    enum AccountState: Equatable {
        case signedIn
        case none
        case unreadable
    }

    /// The facts on which the guards decide, injected so that tests need no real user or preference.
    struct ProbeEnvironment: Equatable {
        var userName: String
        var uid: UInt32
        var account: AccountState
        var outputExists: Bool
    }

    enum ProbeGuards {
        /// The pattern of the M10 probe's `require_test_user`.
        static func isTestUserName(_ name: String) -> Bool {
            name.range(
                of: "^(ilibrarytest|ilibrary-test)[A-Za-z0-9_-]*$", options: .regularExpression) != nil
        }

        /// Returns the first refusal, or nil when every condition holds. The checks are ordered so that the
        /// cheapest identity checks precede the account and output checks.
        static func refusal(for environment: ProbeEnvironment) -> ProbeRefusal? {
            if !isTestUserName(environment.userName) { return .notTestUser }
            if environment.uid == 0 { return .privileged }
            switch environment.account {
            case .signedIn: return .accountSignedIn
            case .unreadable: return .accountUnreadable
            case .none: break
            }
            if environment.outputExists { return .outputExists }
            return nil
        }

        /// The logic of the M10 probe's `check_account`. A zero status with a non-empty `Accounts` array is a
        /// signed-in account. A nonzero status counts as no account only when the message says that the
        /// domain does not exist. Anything else is unreadable and refuses.
        static func classifyAccount(status: Int32, standardOutput: Data, standardError: String) -> AccountState {
            if status == 0 {
                guard
                    let plist = try? PropertyListSerialization.propertyList(from: standardOutput, format: nil),
                    let dictionary = plist as? [String: Any]
                else { return .unreadable }
                if let accounts = dictionary["Accounts"] as? [Any], !accounts.isEmpty { return .signedIn }
                if dictionary["Accounts"] != nil && !(dictionary["Accounts"] is [Any]) { return .unreadable }
                return .none
            }
            if standardError.contains("does not exist") || standardError.contains("not found") { return .none }
            return .unreadable
        }
    }

    /// The names of the sixteen fields of `MusicTrackInfo`, in a fixed order.
    enum TrackField: String, CaseIterable {
        case persistentID, name, album, artist, albumArtist, composer, genre, year, trackNumber
        case discNumber, location, cloudStatus, comment, trackCount, discCount, compilation

        func differs(_ a: MusicTrackInfo, _ b: MusicTrackInfo) -> Bool {
            switch self {
            case .persistentID: a.persistentID != b.persistentID
            case .name: a.name != b.name
            case .album: a.album != b.album
            case .artist: a.artist != b.artist
            case .albumArtist: a.albumArtist != b.albumArtist
            case .composer: a.composer != b.composer
            case .genre: a.genre != b.genre
            case .year: a.year != b.year
            case .trackNumber: a.trackNumber != b.trackNumber
            case .discNumber: a.discNumber != b.discNumber
            case .location: a.location != b.location
            case .cloudStatus: a.cloudStatus != b.cloudStatus
            case .comment: a.comment != b.comment
            case .trackCount: a.trackCount != b.trackCount
            case .discCount: a.discCount != b.discCount
            case .compilation: a.compilation != b.compilation
            }
        }
    }

    /// The outcome of comparing two reads of the same library.
    struct ReaderComparison: Equatable {
        var identical: Bool
        /// For `persistentID`, the number of IDs present in only one array. For every other field, the number
        /// of tracks present in both arrays whose values differ.
        var differingTracksByField: [String: Int]
        var duplicateIDsInFirst: Int
        var duplicateIDsInSecond: Int
    }

    enum ProbeAnalysis {
        static func duplicateCount(_ tracks: [MusicTrackInfo]) -> Int {
            tracks.count - Set(tracks.map(\.persistentID)).count
        }

        /// Compares order-insensitively by persistent ID. With duplicate IDs in either array the arrays are
        /// not reported as identical, and the first record of each ID is the one compared field by field.
        static func compare(_ first: [MusicTrackInfo], _ second: [MusicTrackInfo]) -> ReaderComparison {
            func index(_ tracks: [MusicTrackInfo]) -> [String: MusicTrackInfo] {
                var result: [String: MusicTrackInfo] = [:]
                for track in tracks where result[track.persistentID] == nil { result[track.persistentID] = track }
                return result
            }
            let a = index(first)
            let b = index(second)
            var counts = Dictionary(uniqueKeysWithValues: TrackField.allCases.map { ($0.rawValue, 0) })
            counts[TrackField.persistentID.rawValue] = Set(a.keys).symmetricDifference(Set(b.keys)).count
            for (id, left) in a {
                guard let right = b[id] else { continue }
                for field in TrackField.allCases where field != .persistentID && field.differs(left, right) {
                    counts[field.rawValue, default: 0] += 1
                }
            }
            let duplicatesFirst = duplicateCount(first)
            let duplicatesSecond = duplicateCount(second)
            let identical =
                duplicatesFirst == 0 && duplicatesSecond == 0 && first.count == second.count && a == b
            return ReaderComparison(
                identical: identical, differingTracksByField: counts, duplicateIDsInFirst: duplicatesFirst,
                duplicateIDsInSecond: duplicatesSecond)
        }

        static func cloudStatusCounts(_ tracks: [MusicTrackInfo]) -> [String: Int] {
            tracks.reduce(into: [:]) { $0[$1.cloudStatus, default: 0] += 1 }
        }

        static func missingLocationCount(_ tracks: [MusicTrackInfo]) -> Int {
            tracks.filter { $0.location == nil }.count
        }

        /// Lowercased extensions of the locations; an extensionless location is counted as "(none)".
        static func extensionCounts(_ tracks: [MusicTrackInfo]) -> [String: Int] {
            var result: [String: Int] = [:]
            for case let location? in tracks.map(\.location) {
                let value = (location as NSString).pathExtension.lowercased()
                result[value.isEmpty ? "(none)" : value, default: 0] += 1
            }
            return result
        }

        static func everyTrackHasDateAdded(_ snapshot: MusicLibrarySnapshot) -> Bool {
            snapshot.tracks.allSatisfy { snapshot.dateAddedSeconds[$0.persistentID] != nil }
        }

        static func sameIdentitySet(_ a: [MusicTrackInfo], _ b: [MusicTrackInfo]) -> Bool {
            Set(a.map(\.persistentID)) == Set(b.map(\.persistentID))
        }

        /// The smallest and largest age, in whole seconds before `reference`, of the snapshot's dates added, and
        /// the number of distinct values; nil when the snapshot holds no date added.
        static func dateAddedAges(_ snapshot: MusicLibrarySnapshot, reference: Int) -> ProbeReport.DateAddedAges? {
            let ages = snapshot.tracks.compactMap { snapshot.dateAddedSeconds[$0.persistentID] }.map { reference - $0 }
            guard let minimum = ages.min(), let maximum = ages.max() else { return nil }
            return ProbeReport.DateAddedAges(
                minimumSeconds: minimum, maximumSeconds: maximum, distinctCount: Set(ages).count)
        }
    }

    /// The sanitized report. It holds counts, durations, versions, enumeration names, file extensions, and the
    /// range of the ages of the dates added, and never a name, a path, a persistent ID, or an account detail.
    struct ProbeReport: Codable, Equatable {
        struct Readers: Codable, Equatable {
            var perTrackCount: Int
            var bulkCount: Int
            var snapshotTrackCount: Int
            var snapshotTotalTrackCount: Int
            var snapshotFileTrackCount: Int
        }
        struct Durations: Codable, Equatable {
            var perTrackSeconds: Double
            var bulkSeconds: Double
            var snapshotSeconds: Double
        }
        struct Equivalence: Codable, Equatable {
            var perTrackAndBulkIdentical: Bool
            var differingTracksByField: [String: Int]
            var duplicateIDsInPerTrack: Int
            var duplicateIDsInBulk: Int
            var snapshotAndPerTrackIDSetsEqual: Bool
        }
        /// The ages of the snapshot's dates added relative to the probe's clock. For tracks added shortly before
        /// the probe, plausible values are small and positive; they reveal no identity.
        struct DateAddedAges: Codable, Equatable {
            var minimumSeconds: Int
            var maximumSeconds: Int
            var distinctCount: Int
        }

        var format = "ilibrary-m11-readers-report-2"
        var userNameCheckPassed: Bool
        var macOSVersion: String
        var musicVersion: String
        var readers: Readers?
        var durations: Durations?
        var bulkFallbackUsed: Bool?
        var equivalence: Equivalence?
        var cloudStatusCounts: [String: Int]?
        var missingLocationCount: Int?
        var locationExtensionCounts: [String: Int]?
        var everySnapshotTrackHasDateAdded: Bool?
        var snapshotDateAddedAges: DateAddedAges?
        /// The message of the error that stopped the probe, when one did.
        var error: String?

        func json() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(self) + Data("\n".utf8)
        }
    }

    enum ProbeReportBuilder {
        /// Builds the complete report from the three reads. `referenceSeconds`, the probe's clock in whole seconds
        /// since 1970, dates the ages of the dates added; without it they are not reported. Pure.
        static func build(
            macOSVersion: String, musicVersion: String, perTrack: [MusicTrackInfo], bulk: [MusicTrackInfo],
            bulkFallbackUsed: Bool, snapshot: MusicLibrarySnapshot, durations: ProbeReport.Durations,
            referenceSeconds: Int? = nil
        ) -> ProbeReport {
            let comparison = ProbeAnalysis.compare(perTrack, bulk)
            var report = ProbeReport(userNameCheckPassed: true, macOSVersion: macOSVersion, musicVersion: musicVersion)
            report.readers = ProbeReport.Readers(
                perTrackCount: perTrack.count, bulkCount: bulk.count, snapshotTrackCount: snapshot.tracks.count,
                snapshotTotalTrackCount: snapshot.trackCount, snapshotFileTrackCount: snapshot.fileTrackCount)
            report.durations = durations
            report.bulkFallbackUsed = bulkFallbackUsed
            report.equivalence = ProbeReport.Equivalence(
                perTrackAndBulkIdentical: comparison.identical,
                differingTracksByField: comparison.differingTracksByField,
                duplicateIDsInPerTrack: comparison.duplicateIDsInFirst,
                duplicateIDsInBulk: comparison.duplicateIDsInSecond,
                snapshotAndPerTrackIDSetsEqual: ProbeAnalysis.sameIdentitySet(snapshot.tracks, perTrack))
            report.cloudStatusCounts = ProbeAnalysis.cloudStatusCounts(snapshot.tracks)
            report.missingLocationCount = ProbeAnalysis.missingLocationCount(snapshot.tracks)
            report.locationExtensionCounts = ProbeAnalysis.extensionCounts(snapshot.tracks)
            report.everySnapshotTrackHasDateAdded = ProbeAnalysis.everyTrackHasDateAdded(snapshot)
            if let referenceSeconds {
                report.snapshotDateAddedAges = ProbeAnalysis.dateAddedAges(snapshot, reference: referenceSeconds)
            }
            return report
        }
    }
#endif
