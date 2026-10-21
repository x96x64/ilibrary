// Decision logic of the GUI-emptiness feasibility probe. Foundation-only, so that it builds and is tested on
// Linux. Nothing in this file touches an accessibility interface, Music, or the file system. The classifier is
// a pure function: absence of an element, an empty child list, or zero visible rows never proves emptiness.
import Foundation

/// The two Music views that the probe examines.
enum ViewKind: String, CaseIterable, Codable, Sendable {
    case songs
    case recentlyAdded
}

/// A closed set of reasons for a verdict other than a candidate for emptiness, or supporting a non-empty one.
enum Reason: Hashable, Sendable {
    case separateTestUserUnconfirmed
    case syntheticLibraryUnconfirmed
    case noAppleAccountUnconfirmed
    case noCloudLibraryUnconfirmed
    case userNameDoesNotMatchPattern
    case accessibilityNotTrusted
    case musicProcessNotRunning
    case musicProcessTerminated
    case musicProcessNotUnique
    case versionsMissing
    case noReviewedProfile
    case versionMismatch
    case stabilityUnqualified
    case notEnoughReadings(have: Int, need: Int)
    case spanTooShort
    case treeIncomplete
    case timedOut
    case viewNotIdentified
    case containerMissing
    case unexpectedStructure
    case unknownLabel
    case loading
    case loadingUnknown
    case scrollableOrUnknown
    case noPositiveEmptyEvidence
    case readingsDisagree
    case inventoryEvidenceMissing
    case inventoryEvidenceInvalid
    case contradictoryRowTotal
    /// The profile declares the row list complete, but a reading did not report its total.
    case rowTotalUnknown
    /// The observation stopped before every requested reading was taken and checked.
    case runStopped
    case inventoryContradictsView(count: Int)
    case visibleContent(items: Int)
    case inventoryCountPositive(count: Int)

    var description: String {
        switch self {
        case .separateTestUserUnconfirmed: "the operator did not confirm a separate test user"
        case .syntheticLibraryUnconfirmed: "the operator did not confirm a synthetic library"
        case .noAppleAccountUnconfirmed: "the operator did not confirm the absence of an Apple Account"
        case .noCloudLibraryUnconfirmed: "the operator did not confirm the absence of a cloud music library"
        case .userNameDoesNotMatchPattern: "the process user name does not match the test-user pattern"
        case .accessibilityNotTrusted: "the process is not trusted for accessibility"
        case .musicProcessNotRunning: "no Music process is running"
        case .musicProcessTerminated: "the Music process has terminated"
        case .musicProcessNotUnique: "more than one Music process is running"
        case .versionsMissing: "the macOS or Music version could not be determined"
        case .noReviewedProfile: "no reviewed interface profile was supplied"
        case .versionMismatch: "the observed versions or locale differ from those of the profile"
        case .stabilityUnqualified: "the profile declares no usable stability requirement"
        case .notEnoughReadings(let have, let need): "only \(have) of the required \(need) readings were taken"
        case .spanTooShort: "the readings span less than the required time"
        case .treeIncomplete: "the accessibility tree was not read completely"
        case .timedOut: "an accessibility request timed out"
        case .viewNotIdentified: "the view was not identified exactly once"
        case .containerMissing: "the content container was not found"
        case .unexpectedStructure: "the structure of the view differs from the profile"
        case .unknownLabel: "a label required for identification did not match the profile"
        case .loading: "the view reports that it is loading"
        case .loadingUnknown: "whether the view is loading could not be determined"
        case .scrollableOrUnknown: "the view is scrollable or its scrollability is unknown"
        case .noPositiveEmptyEvidence: "no positive evidence of emptiness was observed"
        case .readingsDisagree: "the readings differ from one another"
        case .inventoryEvidenceMissing: "no registration inventory count was supplied"
        case .inventoryEvidenceInvalid: "the supplied inventory count is not a valid count"
        case .contradictoryRowTotal: "the empty-state element is present but the complete row list is not empty"
        case .rowTotalUnknown: "the profile declares the row list complete, but its total was not reported"
        case .runStopped: "the observation stopped before every requested reading was taken"
        case .inventoryContradictsView(let count):
            "the inventory reports \(count) file tracks but the view shows no content"
        case .visibleContent(let items): "the view shows \(items) content items"
        case .inventoryCountPositive(let count): "the inventory reports \(count) file tracks"
        }
    }
}

/// A closed set of observations that together support a candidate for emptiness.
enum Evidence: Hashable, Sendable {
    case inventoryZero
    case stableReadings(count: Int, spanSeconds: Double)
    case noVisibleContent
    case placeholderPresent
    case zeroRowsReportedCompletely
    case notScrollable
    case notBusy

    var description: String {
        switch self {
        case .inventoryZero: "the inventory reports zero file tracks"
        case .stableReadings(let count, let span):
            "\(count) agreeing complete readings span \(String(format: "%.1f", span)) seconds"
        case .noVisibleContent: "no content item is visible"
        case .placeholderPresent: "the empty-state element of the profile is present"
        case .zeroRowsReportedCompletely: "the row list, declared complete, has zero rows"
        case .notScrollable: "the view is positively not scrollable"
        case .notBusy: "the view positively reports that it is not busy"
        }
    }
}

enum Verdict: Equatable, Sendable {
    case verifiedNonEmpty(reasons: [Reason])
    case candidateEmpty(evidence: [Evidence])
    case indeterminate(reasons: [Reason])

    var outcome: String {
        switch self {
        case .verifiedNonEmpty: "verifiedNonEmpty"
        case .candidateEmpty: "candidateEmpty"
        case .indeterminate: "indeterminate"
        }
    }

    var descriptions: [String] {
        switch self {
        case .verifiedNonEmpty(let reasons), .indeterminate(let reasons): reasons.map(\.description)
        case .candidateEmpty(let evidence): evidence.map(\.description)
        }
    }
}

enum MusicProcessState: Equatable, Sendable {
    case exactlyOne
    case none
    case terminated
    case multiple
}

/// The facts established before any view is read. Every value defaults to unmet; a missing value is a failure.
struct Preflight: Equatable, Sendable {
    var operatorConfirmedSeparateTestUser = false
    var operatorConfirmedSyntheticLibrary = false
    var operatorConfirmedNoAppleAccount = false
    var operatorConfirmedNoCloudLibrary = false
    var processUserMatchesTestUserPattern = false
    var accessibilityTrusted = false
    var musicProcess = MusicProcessState.none
    var macOSVersionPresent = false
    var musicVersionPresent = false
    var profileSupplied = false

    /// The password-database name pattern of M11Probe; a match is necessary and never sufficient.
    static func isTestUserName(_ name: String) -> Bool {
        name.range(of: "^(ilibrarytest|ilibrary-test)[A-Za-z0-9_-]*$", options: .regularExpression) != nil
    }

    var failures: [Reason] {
        var result: [Reason] = []
        if !operatorConfirmedSeparateTestUser { result.append(.separateTestUserUnconfirmed) }
        if !operatorConfirmedSyntheticLibrary { result.append(.syntheticLibraryUnconfirmed) }
        if !operatorConfirmedNoAppleAccount { result.append(.noAppleAccountUnconfirmed) }
        if !operatorConfirmedNoCloudLibrary { result.append(.noCloudLibraryUnconfirmed) }
        if !processUserMatchesTestUserPattern { result.append(.userNameDoesNotMatchPattern) }
        if !accessibilityTrusted { result.append(.accessibilityNotTrusted) }
        switch musicProcess {
        case .exactlyOne: break
        case .none: result.append(.musicProcessNotRunning)
        case .terminated: result.append(.musicProcessTerminated)
        case .multiple: result.append(.musicProcessNotUnique)
        }
        if !macOSVersionPresent || !musicVersionPresent { result.append(.versionsMissing) }
        if !profileSupplied { result.append(.noReviewedProfile) }
        return result
    }
}

/// The versions and locale observed on this system, compared with those of the profile.
struct ObservedContext: Equatable, Sendable {
    var macOSVersion: String?
    var musicVersion: String?
    var locale: String?
}

/// The file-track count of a separate, separately authorized read of the registration inventory.
struct InventoryEvidence: Equatable, Sendable {
    var fileTrackCount: Int?
}

enum TreeStatus: String, Codable, Equatable, Sendable {
    case complete
    case truncatedByLimit
    case timedOut
    case attributeError
    case notFound
}

/// One structural observation of one view. Times are relative to the first reading and carry no wall-clock date.
struct ViewReading: Codable, Equatable, Sendable {
    var elapsed: Double
    var treeStatus: TreeStatus
    var viewIdentified: Bool
    var containerFound: Bool
    var containerRole: String?
    var contentItemCount: Int?
    var totalItemCount: Int?
    var scrollable: Bool?
    var busy: Bool?
    var placeholderPresent: Bool?
    var unexpectedStructure: Bool
    var unknownLabel: Bool

    /// The structural fields that all readings of a candidate for emptiness must share; the time is excluded.
    fileprivate var structure: [String] {
        [
            treeStatus.rawValue, "\(viewIdentified)", "\(containerFound)", containerRole ?? "-",
            contentItemCount.map(String.init) ?? "-", totalItemCount.map(String.init) ?? "-",
            scrollable.map(String.init) ?? "-", busy.map(String.init) ?? "-",
            placeholderPresent.map(String.init) ?? "-", "\(unexpectedStructure)", "\(unknownLabel)",
        ]
    }
}

enum Classifier {
    /// Classifies one view over its readings.
    static func classify(
        readings: [ViewReading], view: ViewKind, preflight: Preflight, context: ObservedContext,
        profile: InterfaceProfile?, inventory: InventoryEvidence
    ) -> Verdict {
        var gate = preflight.failures
        if profile == nil { gate.append(.noReviewedProfile) }
        if let profile { gate += profile.qualificationFailures(for: context) }
        gate = unique(gate)
        guard gate.isEmpty, let profile, let stability = profile.stability else { return .indeterminate(reasons: gate) }
        guard !readings.isEmpty else {
            return .indeterminate(reasons: [.notEnoughReadings(have: 0, need: stability.minimumReadings)])
        }

        let confirmed = readings.filter { $0.viewIdentified && $0.containerFound && $0.treeStatus == .complete }
        let largest = confirmed.compactMap(\.contentItemCount).max() ?? 0
        if largest >= 1 {
            var reasons: [Reason] = [.visibleContent(items: largest)]
            if let count = inventory.fileTrackCount, count > 0 { reasons.append(.inventoryCountPositive(count: count)) }
            return .verifiedNonEmpty(reasons: reasons)
        }

        var reasons: [Reason] = []
        switch inventory.fileTrackCount {
        case nil: reasons.append(.inventoryEvidenceMissing)
        case let count? where count < 0: reasons.append(.inventoryEvidenceInvalid)
        case let count? where count > 0: reasons.append(.inventoryContradictsView(count: count))
        default: break
        }
        if readings.count < stability.minimumReadings {
            reasons.append(.notEnoughReadings(have: readings.count, need: stability.minimumReadings))
        }
        let times = readings.map(\.elapsed)
        let span = (times.max() ?? 0) - (times.min() ?? 0)
        if !times.allSatisfy(\.isFinite) || !(span >= stability.minimumSpanSeconds) { reasons.append(.spanTooShort) }
        if readings.contains(where: { $0.treeStatus == .timedOut }) { reasons.append(.timedOut) }
        if readings.contains(where: { $0.treeStatus != .complete && $0.treeStatus != .timedOut }) {
            reasons.append(.treeIncomplete)
        }
        if readings.contains(where: { !$0.viewIdentified }) { reasons.append(.viewNotIdentified) }
        if readings.contains(where: { !$0.containerFound }) { reasons.append(.containerMissing) }
        if readings.contains(where: \.unexpectedStructure) { reasons.append(.unexpectedStructure) }
        if readings.contains(where: \.unknownLabel) { reasons.append(.unknownLabel) }
        if readings.contains(where: { $0.busy == true }) { reasons.append(.loading) }
        if readings.contains(where: { $0.busy == nil }) { reasons.append(.loadingUnknown) }
        if readings.contains(where: { $0.scrollable != false }) { reasons.append(.scrollableOrUnknown) }
        let rowsComplete = profile.rule(for: view).rowsComplete
        let positive = readings.allSatisfy { reading in
            reading.contentItemCount == 0
                && (reading.placeholderPresent == true || (rowsComplete && reading.totalItemCount == 0))
        }
        if !positive { reasons.append(.noPositiveEmptyEvidence) }
        // Where the profile declares the row list complete, its total must be reported as zero in every reading,
        // whatever the placeholder shows; an unreported total is unknown, never zero.
        if rowsComplete {
            if readings.contains(where: { ($0.totalItemCount ?? 0) > 0 }) { reasons.append(.contradictoryRowTotal) }
            if readings.contains(where: { $0.totalItemCount == nil }) { reasons.append(.rowTotalUnknown) }
        }
        if Set(readings.map(\.structure)).count > 1 { reasons.append(.readingsDisagree) }
        reasons = unique(reasons)
        if !reasons.isEmpty { return .indeterminate(reasons: reasons) }

        var evidence: [Evidence] = [
            .inventoryZero, .stableReadings(count: readings.count, spanSeconds: span), .noVisibleContent,
        ]
        evidence.append(
            readings.allSatisfy { $0.placeholderPresent == true } ? .placeholderPresent : .zeroRowsReportedCompletely)
        evidence += [.notScrollable, .notBusy]
        return .candidateEmpty(evidence: evidence)
    }

    /// The combined result: a candidate for emptiness only if both views are, non-empty if either is, and
    /// otherwise indeterminate.
    /// The verdict of a stopped observation: content seen in a complete reading still proves non-emptiness, but
    /// no candidate for emptiness survives a stop.
    static func stopped(_ verdict: Verdict) -> Verdict {
        switch verdict {
        case .verifiedNonEmpty: return verdict
        case .candidateEmpty: return .indeterminate(reasons: [.runStopped])
        case .indeterminate(let reasons): return .indeterminate(reasons: unique(reasons + [.runStopped]))
        }
    }

    static func combine(_ first: Verdict, _ second: Verdict) -> Verdict {
        switch (first, second) {
        case (.candidateEmpty(let a), .candidateEmpty(let b)): return .candidateEmpty(evidence: a + b)
        case (.verifiedNonEmpty(let a), .verifiedNonEmpty(let b)): return .verifiedNonEmpty(reasons: unique(a + b))
        case (.verifiedNonEmpty(let a), _), (_, .verifiedNonEmpty(let a)): return .verifiedNonEmpty(reasons: a)
        case (.indeterminate(let a), .indeterminate(let b)): return .indeterminate(reasons: unique(a + b))
        case (.indeterminate(let a), _), (_, .indeterminate(let a)): return .indeterminate(reasons: a)
        }
    }

    private static func unique(_ reasons: [Reason]) -> [Reason] {
        var seen = Set<Reason>()
        return reasons.filter { seen.insert($0).inserted }
    }
}
