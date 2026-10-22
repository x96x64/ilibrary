// Tests of the review that decides whether a survey record may leave the test user. Foundation-only, so that they
// run on Linux with the other portable survey tests.
import Foundation
import Testing

@testable import GUIProbeMac

@Suite struct SurveyReviewTests {
    static let runID = "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"
    static let name = "songs-1.json"

    /// A completed survey record built by the probe's own sanitizer from a synthetic tree whose nodes carry a raw
    /// identifier, a free-text title, and an allow-listed title.
    static func record(_ edit: (inout ProbeOutput) -> Void = { _ in }) -> ProbeOutput {
        var tree = SyntheticTree.songs(rows: 1, placeholder: true)
        tree.nodes[4].identifier = "/Users/someone/Music/private-identifier"
        tree.nodes[4].hasIdentifier = true
        tree.nodes[3].title = "A Private Playlist Name"
        tree.nodes[3].hasTitle = true
        let snapshot = TreeWalker.walk(roots: [0], source: tree, limits: WalkLimits())
        var aliases = IdentifierAliases()
        var record = ProbeOutput(
            mode: "survey", status: .completed, sourceCommit: "2f5e15b2ec3d914ea1ec0e484bd78fa9a795ec47",
            macOSVersion: "Version 27.0.1 (Build 26A434)", musicVersion: "1.6.1", confirmations: Confirmations())
        record.format = ProbeOutput.surveyFormat
        record.operatorDisplayedView = DisplayedView.songs.rawValue
        record.survey = SurveySanitizer.section(
            snapshot, limits: WalkLimits(), aliases: &aliases, elapsedSeconds: 1.25, hardLimitSeconds: 660,
            runID: runID, identifierMappingName: SurveyPlacement.mappingName(for: name))
        edit(&record)
        return record
    }

    static func findings(_ record: ProbeOutput) throws -> [SurveyReview.Finding] {
        SurveyReview.findings(of: try record.json(), recordName: name)
    }

    @Test func theProbesOwnCompletedRecordIsShareableAndHoldsNoRawText() throws {
        let data = try Self.record().json()
        #expect(SurveyReview.findings(of: data, recordName: Self.name).isEmpty)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("/Users/") && !text.contains("private-identifier") && !text.contains("Playlist"))
    }

    @Test func anyByteOutsideTheProbesEncodingIsRefused() throws {
        let data = try Self.record().json()
        let text = String(decoding: data, as: UTF8.self)
        // An added key, a trailing byte, and a re-encoding with other formatting each break the canonical form.
        let added = text.replacingOccurrences(
            of: "\"format\" :", with: "\"note\" : \"/Users/someone\",\n  \"format\" :")
        try #require(added != text)
        #expect(SurveyReview.findings(of: Data(added.utf8), recordName: Self.name).contains(.notCanonical))
        #expect(SurveyReview.findings(of: data + Data(" ".utf8), recordName: Self.name).contains(.notCanonical))
        let compact = try JSONEncoder().encode(Self.record())
        #expect(SurveyReview.findings(of: compact, recordName: Self.name).contains(.notCanonical))
    }

    @Test func duplicateKeysAMarkOrAnotherNumberFormIsRefused() throws {
        let data = try Self.record().json()
        let text = String(decoding: data, as: UTF8.self)
        let duplicate = text.replacingOccurrences(
            of: "\"format\" :", with: "\"mode\" : \"survey\",\n  \"format\" :")
        try #require(duplicate != text)
        let marked = Data([0xEF, 0xBB, 0xBF]) + data
        let decimal = text.replacingOccurrences(of: "\"hardLimitSeconds\" : 660", with: "\"hardLimitSeconds\" : 660.0")
        try #require(decimal != text)
        for variant in [Data(duplicate.utf8), marked, Data(decimal.utf8)] {
            let findings = SurveyReview.findings(of: variant, recordName: Self.name)
            #expect(findings.contains(.notCanonical) || findings == [.notASurveyRecord])
            #expect(!findings.isEmpty)
        }
    }

    @Test func otherFilesAreNotSurveyRecords() throws {
        let mapping = IdentifierMapping(runID: Self.runID, recordName: Self.name, aliases: IdentifierAliases())
        for data in [Data(), Data("{}".utf8), Data("not json".utf8), try mapping.json()] {
            #expect(SurveyReview.findings(of: data, recordName: Self.name) == [.notASurveyRecord])
        }
        let observe = ProbeOutput(
            mode: "observe", status: .completed, macOSVersion: "Version 27.0.1 (Build 26A434)", musicVersion: "1.6.1",
            confirmations: Confirmations())
        #expect(try Self.findings(observe) == [.notASurveyRecord])
    }

    @Test func onlyACompletedRunIsShareable() throws {
        let stopped = Self.record {
            $0.status = .stopped
            $0.stopReason = SurveyRun.processChanged
        }
        #expect(try Self.findings(stopped) == [.notCompleted])
        #expect(try Self.findings(Self.record { $0.status = .refused }) == [.notCompleted])
        #expect(try Self.findings(Self.record { $0.stopReason = SurveyRun.processChanged }) == [.notCompleted])
    }

    @Test func everyTextFieldIsHeldToItsClosedForm() throws {
        let cases: [(String, (inout ProbeOutput) -> Void)] = [
            ("operatorSourceLabel", { (r: inout ProbeOutput) in r.sourceCommit = "my-branch" }),
            ("macOSVersion", { (r: inout ProbeOutput) in r.macOSVersion = "Version 27.0.1 (Build 26A434) someone" }),
            ("macOSVersion", { (r: inout ProbeOutput) in r.macOSVersion = nil }),
            ("musicVersion", { (r: inout ProbeOutput) in r.musicVersion = "1.6.1\n" }),
            ("operatorDisplayedView", { (r: inout ProbeOutput) in r.operatorDisplayedView = "albums" }),
            ("provenance", { (r: inout ProbeOutput) in r.provenance = "free text" }),
            ("probeVersion", { (r: inout ProbeOutput) in r.probeVersion = "9.9.9" }),
            ("profileSHA256", { (r: inout ProbeOutput) in r.profileSHA256 = "00" }),
            ("runID", { (r: inout ProbeOutput) in r.survey?.runID = "someone" }),
            ("runID", { (r: inout ProbeOutput) in r.survey?.runID = nil }),
            ("identifierMappingName", { (r: inout ProbeOutput) in r.survey?.identifierMappingName = "other.json" }),
            ("identifierPrivacy", { (r: inout ProbeOutput) in r.survey?.identifierPrivacy = "" }),
            ("errorCountsByCode", { (r: inout ProbeOutput) in r.survey?.errorCountsByCode = ["someone": 1] }),
            ("role", { (r: inout ProbeOutput) in r.survey?.nodes[1].role = "A Private Name" }),
            ("subrole", { (r: inout ProbeOutput) in r.survey?.nodes[1].subrole = "AXRow\n" }),
            ("label", { (r: inout ProbeOutput) in r.survey?.nodes[3].titleLabel = "A Private Playlist Name" }),
            ("identifierShape", { (r: inout ProbeOutput) in r.survey?.nodes[4].identifierShape = "path" }),
            ("identifierAlias", { (r: inout ProbeOutput) in r.survey?.nodes[4].identifierAlias = "/Users/someone" }),
            (
                "errors",
                { (r: inout ProbeOutput) in r.survey?.nodes[1].errors = [AttributeError(attribute: "someone", code: 1)]
                }
            ),
            ("scrollValue", { (r: inout ProbeOutput) in r.survey?.nodes[1].scrollValue = 2 }),
            ("counts", { (r: inout ProbeOutput) in r.survey?.nodes[1].childCount = -1 }),
            ("musicVersion", { (r: inout ProbeOutput) in r.musicVersion = nil }),
            ("operatorSourceLabel", { (r: inout ProbeOutput) in r.sourceCommit = String(repeating: "a", count: 41) }),
            (
                "observation",
                { (r: inout ProbeOutput) in
                    r.observation = ObservationSection(
                        readingsRequested: 1, intervalSeconds: 1, locale: "en_US", inventoryFileTrackCount: nil,
                        songs: nil,
                        recentlyAdded: nil, combined: VerdictRecord(.indeterminate(reasons: [.runStopped])))
                }
            ),
            (
                "label",
                { (r: inout ProbeOutput) in
                    r.survey?.nodes[1].hasDescription = true
                    r.survey?.nodes[1].descriptionLabel = "A Private Description"
                }
            ),
            ("errorCountsByCode", { (r: inout ProbeOutput) in r.survey?.errorCountsByCode = ["-25205": -1] }),
            ("survey", { (r: inout ProbeOutput) in r.survey?.elapsedSeconds = -1 }),
        ]
        for (field, edit) in cases {
            #expect(try Self.findings(Self.record(edit)).contains(.unexpectedValue(field)), "\(field)")
        }
    }

    @Test func anInconsistentStructureIsRefused() throws {
        let edits: [(inout ProbeOutput) -> Void] = [
            { $0.survey?.visitedNodeCount += 1 },
            { $0.survey?.nodes[1].parent = 5 },
            { $0.survey?.nodes[1].depth = 3 },
            { $0.survey?.nodes[0].depth = 1 },
            { $0.survey?.nodes[4].identifierAlias = "identifier-7" },
            { $0.survey?.nodes[4].identifierShape = nil },
            { $0.survey?.nodes[3].hasTitle = false },
            { $0.survey?.nodes[1].hasDescription = true },
        ]
        for edit in edits { #expect(try Self.findings(Self.record(edit)).contains(.inconsistentStructure)) }
    }

    /// Extreme or malformed depths and parent indices are refused through the documented finding and never trap,
    /// including the reported case of a root at `Int.max` followed by a child of that root.
    @Test func extremeDepthsAndParentsAreRefusedWithoutTrapping() throws {
        let edits: [(inout ProbeOutput) -> Void] = [
            { $0.survey?.nodes[0].depth = Int.max },
            { $0.survey?.nodes[0].depth = Int.min },
            { $0.survey?.nodes[0].depth = -1 },
            { $0.survey?.nodes[1].depth = Int.max },
            { $0.survey?.nodes[1].depth = Int.min },
            { $0.survey?.nodes[1].depth = WalkLimits().maximumDepth + 1 },
            { $0.survey?.nodes[1].parent = Int.max },
            { $0.survey?.nodes[1].parent = Int.min },
            { $0.survey?.nodes[1].parent = -1 },
            { $0.survey?.nodes[1].parent = 1 },
            {
                $0.survey?.nodes[0].depth = Int.max
                $0.survey?.nodes[1].depth = Int.min
            },
        ]
        for edit in edits {
            let findings = try Self.findings(Self.record(edit))
            #expect(findings == [.inconsistentStructure])
        }
        // A chain that reaches the walk's depth limit exactly remains consistent.
        var tree = SyntheticTree()
        var parent = tree.add(parent: nil, role: "AXApplication")
        for _ in 0..<WalkLimits().maximumDepth { parent = tree.add(parent: parent, role: "AXGroup") }
        let snapshot = TreeWalker.walk(roots: [0], source: tree, limits: WalkLimits())
        var aliases = IdentifierAliases()
        let deep = Self.record {
            $0.survey = SurveySanitizer.section(
                snapshot, limits: WalkLimits(), aliases: &aliases, elapsedSeconds: 1, hardLimitSeconds: 660,
                runID: Self.runID, identifierMappingName: SurveyPlacement.mappingName(for: Self.name))
        }
        #expect(deep.survey?.nodes.last?.depth == WalkLimits().maximumDepth)
        #expect(try Self.findings(deep).isEmpty)
    }

    @Test func theFormChecksExamineEveryScalar() {
        #expect(SurveyReview.isMacOSVersion("Version 27.0.1 (Build 26A434)"))
        #expect(!SurveyReview.isMacOSVersion("Version 27.0.1 (Build 26A434)\n"))
        #expect(!SurveyReview.isMacOSVersion("Version  (Build 26A434)"))
        #expect(SurveyReview.isAccessibilityConstant("AXRow") && !SurveyReview.isAccessibilityConstant("AX"))
        #expect(!SurveyReview.isAccessibilityConstant("AXRow\u{0}") && !SurveyReview.isAccessibilityConstant("AXRöw"))
        #expect(SurveyReview.isRunID(Self.runID) && !SurveyReview.isRunID(Self.runID.lowercased()))
        #expect(SurveyReview.aliasNumber("identifier-12") == 12 && SurveyReview.aliasNumber("identifier-012") == nil)
        #expect(SurveyReview.isErrorCode("-25205") && !SurveyReview.isErrorCode("99999999999"))
        #expect(SurveyReview.isSourceLabel("2f5e15b") && !SurveyReview.isSourceLabel("2F5E15B"))
    }

    @Test func theDescriptionsNeverRepeatRecordContent() {
        let all: [SurveyReview.Finding] = [
            .notASurveyRecord, .notCanonical, .notCompleted, .unexpectedValue("role"), .inconsistentStructure,
        ]
        for finding in all { #expect(!finding.description.contains("/") && !finding.description.isEmpty) }
        #expect(SurveyReview.shareable == "GUIProbeMac review-survey: shareable")
        #expect(SurveyReview.notShareable == "GUIProbeMac review-survey: not shareable")
    }
}
