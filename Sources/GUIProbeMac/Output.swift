// The sanitized output of the probe and its exclusive creation. Foundation-only. The output holds structure,
// counts, versions, and allow-listed labels, and never other text, values, positions, or sizes of Music.
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The built-in labels that a title or description may be recorded as; any other text becomes `other`.
let surveyLabelAllowList: [String] = ["Songs", "Recently Added", "Library", "曲", "最近追加した項目", "ライブラリ"]

struct SurveyNode: Codable, Equatable, Sendable {
    var depth: Int
    /// The index in `nodes` of the node through which this node was reached; nil for the application element.
    /// It is a position in the record only, never an element reference or an interface value.
    var parent: Int?
    var role: String?
    var subrole: String?
    var identifier: String?
    var hasIdentifier: Bool
    var hasTitle: Bool
    var titleLabel: String?
    var hasDescription: Bool
    var descriptionLabel: String?
    var childCount: Int?
    var rowCount: Int?
    var visibleRowCount: Int?
    var hasHorizontalScrollBar: Bool?
    var hasVerticalScrollBar: Bool?
    var scrollValue: Double?
    var busy: Bool?
    var errors: [AttributeError]
}

enum SurveySanitizer {
    /// Role and subrole constants of the accessibility interface; anything else is replaced by `other`.
    static func constant(_ text: String?) -> String? {
        guard let text else { return nil }
        return text.range(of: "^AX[A-Za-z0-9]{1,60}$", options: .regularExpression) != nil ? text : "other"
    }

    static func identifier(_ text: String?) -> String? {
        guard let text, text.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil else {
            return nil
        }
        return text
    }

    static func label(_ text: String?, exists: Bool) -> String? {
        guard exists else { return nil }
        guard let text, surveyLabelAllowList.contains(text) else { return "other" }
        return text
    }

    static func node(_ facts: NodeFacts, depth: Int, parent: Int? = nil) -> SurveyNode {
        SurveyNode(
            depth: depth, parent: parent, role: constant(facts.role), subrole: constant(facts.subrole),
            identifier: identifier(facts.identifier), hasIdentifier: facts.hasIdentifier, hasTitle: facts.hasTitle,
            titleLabel: label(facts.title, exists: facts.hasTitle), hasDescription: facts.hasDescription,
            descriptionLabel: label(facts.description, exists: facts.hasDescription), childCount: facts.childCount,
            rowCount: facts.rowCount, visibleRowCount: facts.visibleRowCount,
            hasHorizontalScrollBar: facts.hasHorizontalScrollBar, hasVerticalScrollBar: facts.hasVerticalScrollBar,
            scrollValue: facts.scrollValue.map { min(max($0, 0), 1) }, busy: facts.busy,
            errors: facts.errors)
    }

    static func section<Node>(_ snapshot: TreeSnapshot<Node>, limits: WalkLimits) -> SurveySection {
        SurveySection(
            nodeLimit: limits.maximumNodes, depthLimit: limits.maximumDepth,
            timeoutSeconds: limits.timeoutSeconds, visitedNodeCount: snapshot.entries.count,
            truncatedByNodeLimit: snapshot.truncatedByNodeLimit,
            truncatedByDepthLimit: snapshot.truncatedByDepthLimit,
            truncatedByChildLimit: snapshot.truncatedByChildLimit,
            childrenUnavailable: snapshot.childrenUnavailable, roleUnknown: snapshot.roleUnknown,
            errorCountsByCode: Dictionary(
                uniqueKeysWithValues: snapshot.errorCountsByCode.map { (String($0.key), $0.value) }),
            treeStatus: snapshot.status, applicationInvalid: snapshot.applicationInvalid,
            nodes: snapshot.entries.map { node($0.facts, depth: $0.depth, parent: $0.parent) })
    }
}

struct Confirmations: Codable, Equatable, Sendable {
    var separateTestUser = false
    var syntheticLibrary = false
    var noAppleAccount = false
    var noCloudLibrary = false
}

enum RunStatus: String, Codable, Equatable, Sendable {
    /// The probe ran to its end on a Music process whose identity held throughout, and the output holds its
    /// observations. It says nothing about completeness: a survey states that in `survey.treeStatus`, and only a
    /// complete tree exits with status 0.
    case completed
    /// The probe declined to read anything.
    case refused
    /// The probe began to read and stopped early, or finished reading from a source that can no longer be trusted;
    /// `stopReason` says why, and any structure recorded is partial and never a complete observation.
    case stopped
}

/// The identity of the Music process that the probe compares across a run: its identifier together with its
/// launch date, since a replacement process can reuse an identifier.
struct ProcessIdentity: Equatable, Sendable {
    var processIdentifier: Int32
    var launchDate: Date
}

/// The outcome of a survey, decided from the process identity before and after the single walk, the validity of
/// the application element, and the completeness of the walk. The status reports the source and the command; the
/// tree status reports the hierarchy, and only a complete tree from an unchanged process exits with status 0.
enum SurveyRun {
    struct Outcome: Equatable, Sendable {
        var status: RunStatus
        var stopReason: String?
        var exitStatus: Int32
    }

    static let processChanged = "the Music process changed or ended during the walk"
    static let applicationInvalid = "the application element became invalid during the walk"

    /// `after` is nil when, after the walk, there is not exactly one Music process with a known identifier and
    /// launch date; an unknown identity never confirms the earlier one.
    static func outcome(
        before: ProcessIdentity, after: ProcessIdentity?, applicationInvalid: Bool, treeStatus: TreeStatus
    ) -> Outcome {
        var reasons: [String] = []
        if after != before { reasons.append(processChanged) }
        if applicationInvalid { reasons.append(Self.applicationInvalid) }
        if !reasons.isEmpty {
            return Outcome(status: .stopped, stopReason: reasons.joined(separator: "; "), exitStatus: 1)
        }
        return Outcome(status: .completed, stopReason: nil, exitStatus: treeStatus == .complete ? 0 : 1)
    }
}

struct SurveySection: Codable, Equatable, Sendable {
    var nodeLimit: Int
    var depthLimit: Int
    var timeoutSeconds: Double
    var visitedNodeCount: Int
    var truncatedByNodeLimit: Bool
    var truncatedByDepthLimit: Bool
    var truncatedByChildLimit: Bool
    var childrenUnavailable: Bool
    var roleUnknown: Bool
    var errorCountsByCode: [String: Int]
    /// The completeness of the walk, derived as for an observation; anything but `complete` means that the
    /// recorded structure may omit elements.
    var treeStatus: TreeStatus
    /// Whether the application element itself reported that it is invalid, as after Music has quit.
    var applicationInvalid: Bool
    var nodes: [SurveyNode]
}

struct VerdictRecord: Codable, Equatable, Sendable {
    var outcome: String
    var details: [String]

    init(_ verdict: Verdict) {
        outcome = verdict.outcome
        details = verdict.descriptions
    }
}

struct ViewObservation: Codable, Equatable, Sendable {
    var readings: [ViewReading]
    var verdict: VerdictRecord
}

struct ObservationSection: Codable, Equatable, Sendable {
    var readingsRequested: Int
    var intervalSeconds: Double
    /// Declared by the operator; the probe does not observe the locale.
    var locale: String
    /// Declared by the operator from a separate read; the probe does not read the library.
    var inventoryFileTrackCount: Int?
    var songs: ViewObservation?
    var recentlyAdded: ViewObservation?
    var combined: VerdictRecord

    // The serialized names mark operator-supplied values, so that a reader does not take them for measurements.
    private enum CodingKeys: String, CodingKey {
        case readingsRequested, intervalSeconds, songs, recentlyAdded, combined
        case locale = "operatorLocale"
        case inventoryFileTrackCount = "operatorInventoryFileTrackCount"
    }
}

struct ProbeOutput: Codable, Equatable, Sendable {
    var format = "ilibrary-gui-probe-output-1"
    var mode: String
    var status: RunStatus
    var stopReason: String?
    var probeVersion: String = GUIProbe.version
    /// A label typed by the operator; it is not verified against Git or the executable.
    var sourceCommit: String?
    var macOSVersion: String?
    var musicVersion: String?
    /// The operator's declarations; the probe verifies none of them.
    var confirmations: Confirmations
    /// The SHA-256 of the exact interface-profile bytes used, so that the reviewed profile can be identified. It
    /// identifies the file only; it does not show that the profile was reviewed.
    var profileSHA256: String?
    var survey: SurveySection?
    var observation: ObservationSection?
    var provenance = ProbeOutput.provenanceStatement

    static let provenanceStatement =
        "Fields named operator* are declarations by the operator and are not measured or verified by the probe; "
        + "the profile digest identifies a file and does not establish its review."

    private enum CodingKeys: String, CodingKey {
        case format, mode, status, stopReason, probeVersion, macOSVersion, musicVersion, profileSHA256, survey
        case observation, provenance
        case sourceCommit = "operatorSourceLabel"
        case confirmations = "operatorConfirmations"
    }

    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self) + Data("\n".utf8)
    }
}

enum GUIProbe {
    static let version = "0.1.0"
}

enum ExclusiveFile {
    static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// Creates the file exclusively with mode 0600 and writes the data, failing if the path exists.
    static func createAndWrite(_ data: Data, to path: String) throws {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += written
            }
        }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
