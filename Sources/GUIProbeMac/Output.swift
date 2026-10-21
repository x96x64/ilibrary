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

    static func node(_ facts: NodeFacts, depth: Int) -> SurveyNode {
        SurveyNode(
            depth: depth, role: constant(facts.role), subrole: constant(facts.subrole),
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
            errorCountsByCode: Dictionary(
                uniqueKeysWithValues: snapshot.errorCountsByCode.map { (String($0.key), $0.value) }),
            nodes: snapshot.entries.map { node($0.facts, depth: $0.depth) })
    }
}

struct Confirmations: Codable, Equatable, Sendable {
    var separateTestUser = false
    var syntheticLibrary = false
    var noAppleAccount = false
    var noCloudLibrary = false
}

enum RunStatus: String, Codable, Equatable, Sendable {
    /// The probe ran to its end and the output holds its observations.
    case completed
    /// The probe declined to read anything.
    case refused
    /// The probe began to read and stopped early; `stopReason` says why.
    case stopped
}

struct SurveySection: Codable, Equatable, Sendable {
    var nodeLimit: Int
    var depthLimit: Int
    var timeoutSeconds: Double
    var visitedNodeCount: Int
    var truncatedByNodeLimit: Bool
    var truncatedByDepthLimit: Bool
    var errorCountsByCode: [String: Int]
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
    var locale: String
    var inventoryFileTrackCount: Int?
    var songs: ViewObservation?
    var recentlyAdded: ViewObservation?
    var combined: VerdictRecord
}

struct ProbeOutput: Codable, Equatable, Sendable {
    var format = "ilibrary-gui-probe-output-1"
    var mode: String
    var status: RunStatus
    var stopReason: String?
    var probeVersion: String = GUIProbe.version
    var sourceCommit: String?
    var macOSVersion: String?
    var musicVersion: String?
    var confirmations: Confirmations
    var survey: SurveySection?
    var observation: ObservationSection?

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
