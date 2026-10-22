// The review of a survey record before a copy of it leaves the test user. Foundation-only. A record is shareable
// only when it is exactly the probe's own canonical encoding of a completed survey and every text value in it
// belongs to a closed set or a fixed form, so that it can hold no free text, raw identifier, path, or account name.
// The review reads one record and nothing else; it never reads the private mapping and never writes.
import Foundation

enum SurveyReview {
    /// Larger files are refused before they are read.
    static let maximumRecordBytes = 64 << 20

    static let shareable = "GUIProbeMac review-survey: shareable"
    static let notShareable = "GUIProbeMac review-survey: not shareable"

    /// A reason why a record is not shareable. Each description is fixed text or names a field of the record
    /// format; none repeats a value from the record.
    enum Finding: Equatable, Sendable, CustomStringConvertible {
        case notASurveyRecord
        case notCanonical
        case notCompleted
        case unexpectedValue(String)
        case inconsistentStructure

        var description: String {
            switch self {
            case .notASurveyRecord: "the file is not a survey record of this probe"
            case .notCanonical: "the file differs from the probe's own encoding of its content"
            case .notCompleted: "the record does not report a completed run"
            case .unexpectedValue(let field): "the field '\(field)' holds a value outside its permitted form"
            case .inconsistentStructure: "the node structure is internally inconsistent"
            }
        }
    }

    static let identifierShapes: Set<String> = ["uuid", "numeric", "hexadecimal", "word", "other"]

    private static func isASCIILetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool { ("0"..."9").contains(scalar) }

    /// Whether the whole text has between `minimum` and `maximum` scalars and each satisfies `allowed`. Every
    /// scalar is examined, so that no line terminator or other suffix can escape the check.
    private static func consists(
        of text: Substring, minimum: Int, maximum: Int, _ allowed: (Unicode.Scalar) -> Bool
    ) -> Bool {
        let scalars = text.unicodeScalars
        return scalars.count >= minimum && scalars.count <= maximum && scalars.allSatisfy(allowed)
    }

    /// A constant of the accessibility interface, in the form the sanitizer keeps: `AX` and 1 to 60 ASCII letters
    /// or digits.
    static func isAccessibilityConstant(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count >= 3, scalars.count <= 62, scalars[0] == "A", scalars[1] == "X" else { return false }
        return scalars.allSatisfy(isASCIILetterOrDigit)
    }

    /// One to four dot-separated groups of 1 to 6 digits.
    static func isDottedVersion(_ text: Substring) -> Bool {
        let groups = text.split(separator: ".", omittingEmptySubsequences: false)
        return (1...4).contains(groups.count) && groups.allSatisfy { consists(of: $0, minimum: 1, maximum: 6, isDigit) }
    }

    /// The form of `ProcessInfo.operatingSystemVersionString` on macOS: `Version 27.0.1 (Build 26A434)`.
    static func isMacOSVersion(_ text: String) -> Bool {
        let prefix = "Version "
        let infix = " (Build "
        let suffix = ")"
        guard text.unicodeScalars.allSatisfy(\.isASCII), text.hasPrefix(prefix), text.hasSuffix(suffix),
            text.count > prefix.count + suffix.count
        else { return false }
        let middle = text.dropFirst(prefix.count).dropLast(suffix.count)
        let parts = middle.components(separatedBy: infix)
        guard parts.count == 2 else { return false }
        return isDottedVersion(Substring(parts[0]))
            && consists(of: Substring(parts[1]), minimum: 1, maximum: 16, isASCIILetterOrDigit)
    }

    /// A Git object name typed by the operator: 7 to 40 lowercase hexadecimal digits.
    static func isSourceLabel(_ text: String) -> Bool {
        consists(of: Substring(text), minimum: 7, maximum: 40) { isDigit($0) || ("a"..."f").contains($0) }
    }

    /// The form of `UUID().uuidString`: five groups of 8, 4, 4, 4, and 12 uppercase hexadecimal digits.
    static func isRunID(_ text: String) -> Bool {
        let groups = text.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12] else { return false }
        return groups.allSatisfy {
            consists(of: $0, minimum: 1, maximum: 12) { isDigit($0) || ("A"..."F").contains($0) }
        }
    }

    /// `identifier-N` with a decimal N without leading zeros.
    static func aliasNumber(_ text: String) -> Int? {
        let prefix = "identifier-"
        guard text.unicodeScalars.allSatisfy(\.isASCII), text.hasPrefix(prefix) else { return nil }
        let digits = text.dropFirst(prefix.count)
        guard consists(of: digits, minimum: 1, maximum: 9, isDigit), digits.first != "0" else { return nil }
        return Int(digits)
    }

    /// A decimal error code of the accessibility interface, possibly negative.
    static func isErrorCode(_ text: String) -> Bool {
        let digits = text.hasPrefix("-") ? Substring(text.dropFirst()) : Substring(text)
        return consists(of: digits, minimum: 1, maximum: 10, isDigit) && Int32(text) != nil
    }

    private static func isFiniteFraction(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && value >= 0 && value <= 1
    }

    private static func isFiniteNonNegative(_ value: Double?) -> Bool {
        guard let value else { return true }
        return value.isFinite && value >= 0
    }

    /// The reasons why the record in `data`, published under `recordName`, is not shareable; empty when it is.
    static func findings(of data: Data, recordName: String) -> [Finding] {
        guard data.count <= maximumRecordBytes,
            let record = try? JSONDecoder().decode(ProbeOutput.self, from: data),
            record.format == ProbeOutput.surveyFormat, record.mode == "survey", let survey = record.survey
        else { return [.notASurveyRecord] }
        var findings: [Finding] = []
        // A byte-for-byte match with the probe's own encoding shows that the file holds no key, value, or text
        // beyond the typed record checked below.
        if (try? record.json()) != data { findings.append(.notCanonical) }
        if record.status != .completed || record.stopReason != nil { findings.append(.notCompleted) }
        func require(_ condition: Bool, _ field: String) {
            if !condition && !findings.contains(.unexpectedValue(field)) { findings.append(.unexpectedValue(field)) }
        }
        require(record.probeVersion == GUIProbe.version, "probeVersion")
        require(record.sourceCommit.map(isSourceLabel) ?? true, "operatorSourceLabel")
        require(record.macOSVersion.map(isMacOSVersion) ?? false, "macOSVersion")
        require(record.musicVersion.map { isDottedVersion(Substring($0)) } ?? false, "musicVersion")
        require(record.profileSHA256 == nil, "profileSHA256")
        require(record.observation == nil, "observation")
        require(
            record.operatorDisplayedView.flatMap(DisplayedView.init(rawValue:)) != nil, "operatorDisplayedView")
        require(record.provenance == ProbeOutput.provenanceStatement, "provenance")
        require(survey.identifierPrivacy == SurveySection.identifierPrivacyStatement, "identifierPrivacy")
        require(survey.runID.map(isRunID) ?? false, "runID")
        require(survey.identifierMappingName == SurveyPlacement.mappingName(for: recordName), "identifierMappingName")
        require(survey.errorCountsByCode.keys.allSatisfy(isErrorCode), "errorCountsByCode")
        require(survey.errorCountsByCode.values.allSatisfy { $0 >= 0 }, "errorCountsByCode")
        require(
            [survey.timeoutSeconds, survey.timeBudgetSeconds, survey.hardLimitSeconds, survey.elapsedSeconds]
                .allSatisfy(isFiniteNonNegative), "survey")

        var structureHolds = survey.visitedNodeCount == survey.nodes.count
        // A walk records no depth beyond its fixed limit, so every depth, a parent's included, is checked against that
        // range before any arithmetic; a malformed record is then refused rather than trapping on overflow.
        let depths = 0...WalkLimits().maximumDepth
        var highestAlias = 0
        for (index, node) in survey.nodes.enumerated() {
            require(node.role.map { $0 == "other" || isAccessibilityConstant($0) } ?? true, "role")
            require(node.subrole.map { $0 == "other" || isAccessibilityConstant($0) } ?? true, "subrole")
            require(node.identifierShape.map(identifierShapes.contains) ?? true, "identifierShape")
            for label in [node.titleLabel, node.descriptionLabel] {
                require(label.map { $0 == "other" || surveyLabelAllowList.contains($0) } ?? true, "label")
            }
            require(node.errors.allSatisfy { isAccessibilityConstant($0.attribute) }, "errors")
            require(isFiniteFraction(node.scrollValue), "scrollValue")
            require(
                [node.childCount, node.rowCount, node.visibleRowCount].allSatisfy { ($0 ?? 0) >= 0 }, "counts")
            // Aliases are assigned in walk order, so each new alias is the next number.
            if let alias = node.identifierAlias {
                if let number = aliasNumber(alias) {
                    if number > highestAlias {
                        if number == highestAlias + 1 { highestAlias = number } else { structureHolds = false }
                    }
                } else {
                    require(false, "identifierAlias")
                }
            }
            if (node.identifierAlias == nil) != (node.identifierShape == nil) { structureHolds = false }
            if (node.titleLabel != nil) != node.hasTitle || (node.descriptionLabel != nil) != node.hasDescription {
                structureHolds = false
            }
            if !depths.contains(node.depth) {
                structureHolds = false
            } else if let parent = node.parent {
                if parent < 0 || parent >= index || !depths.contains(survey.nodes[parent].depth)
                    || node.depth != survey.nodes[parent].depth + 1
                {
                    structureHolds = false
                }
            } else if node.depth != 0 {
                structureHolds = false
            }
        }
        if !structureHolds { findings.append(.inconsistentStructure) }
        return findings
    }
}
