// Synthetic tests of the survey outcome contract and of the structure that a survey records. Nothing here reads
// Music or an accessibility interface; the process identities are constructed values.
import Foundation
import Testing

@testable import GUIProbeMac

@Suite struct SurveyRunTests {
    static let launch = Date(timeIntervalSince1970: 1_000_000)
    static let before = ProcessIdentity(processIdentifier: 41, launchDate: launch)

    func outcome(after: ProcessIdentity?, invalid: Bool = false, tree: TreeStatus = .complete) -> SurveyRun.Outcome {
        SurveyRun.outcome(before: Self.before, after: after, applicationInvalid: invalid, treeStatus: tree)
    }

    @Test func onlyACompleteWalkOfAnUnchangedProcessExitsWithZero() {
        #expect(outcome(after: Self.before) == SurveyRun.Outcome(status: .completed, stopReason: nil, exitStatus: 0))
    }

    @Test(arguments: [TreeStatus.truncatedByLimit, .timedOut, .attributeError, .informationUnavailable, .notFound])
    func anIncompleteWalkIsNeverASuccessfulSurvey(tree: TreeStatus) {
        // The command ran to its end on an unchanged process, so the status is completed; the tree status, which
        // the record keeps, says that the hierarchy is incomplete, and the exit status is not zero.
        #expect(
            outcome(after: Self.before, tree: tree)
                == SurveyRun.Outcome(status: .completed, stopReason: nil, exitStatus: 1))
    }

    @Test func aReplacedProcessStopsTheSurvey() {
        let relaunched = ProcessIdentity(processIdentifier: 41, launchDate: Self.launch.addingTimeInterval(1))
        let another = ProcessIdentity(processIdentifier: 42, launchDate: Self.launch)
        for after in [relaunched, another] {
            let result = outcome(after: after)
            #expect(result.status == .stopped && result.exitStatus == 1)
            #expect(result.stopReason == SurveyRun.processChanged)
        }
    }

    @Test func aTerminatedOrUnidentifiableProcessStopsTheSurveyEvenWithACompleteTree() {
        let result = outcome(after: nil)
        #expect(result == SurveyRun.Outcome(status: .stopped, stopReason: SurveyRun.processChanged, exitStatus: 1))
    }

    @Test func anInvalidApplicationElementStopsTheSurvey() {
        let result = outcome(after: Self.before, invalid: true)
        #expect(result == SurveyRun.Outcome(status: .stopped, stopReason: SurveyRun.applicationInvalid, exitStatus: 1))
        let both = outcome(after: nil, invalid: true)
        #expect(both.status == .stopped && both.exitStatus == 1)
        #expect(both.stopReason == SurveyRun.processChanged + "; " + SurveyRun.applicationInvalid)
    }

    func section(_ tree: SyntheticTree, limits: WalkLimits = WalkLimits()) -> (TreeSnapshot<Int>, SurveySection) {
        let snapshot = TreeWalker.walk(roots: [0], source: tree, limits: limits)
        return (snapshot, SurveySanitizer.section(snapshot, limits: limits))
    }

    func record(_ section: SurveySection, _ outcome: SurveyRun.Outcome) throws -> [String: Any] {
        var output = ProbeOutput(
            mode: "survey", status: outcome.status, stopReason: outcome.stopReason, macOSVersion: Fixtures.macOS,
            musicVersion: Fixtures.music, confirmations: Confirmations())
        output.survey = section
        return try #require(JSONSerialization.jsonObject(with: output.json()) as? [String: Any])
    }

    @Test func aWalkOfAnInvalidApplicationIsRecordedAsStoppedWithItsPartialStructure() throws {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true)
        tree.nodes[0].errors = [AttributeError(attribute: "AXRole", code: accessibilityInvalidElement)]
        let (snapshot, section) = section(tree)
        #expect(section.applicationInvalid && section.treeStatus == .attributeError)
        let result = SurveyRun.outcome(
            before: Self.before, after: Self.before, applicationInvalid: section.applicationInvalid,
            treeStatus: section.treeStatus)
        let object = try record(section, result)
        #expect(object["status"] as? String == "stopped")
        #expect(object["stopReason"] as? String == SurveyRun.applicationInvalid)
        let survey = try #require(object["survey"] as? [String: Any])
        #expect(survey["treeStatus"] as? String == "attributeError")
        #expect(survey["applicationInvalid"] as? Bool == true)
        #expect((survey["nodes"] as? [Any])?.count == snapshot.entries.count)
    }

    @Test func aCompleteSurveyRecordsItsTreeStatus() throws {
        let (_, section) = section(.songs(rows: 1, placeholder: false))
        #expect(section.treeStatus == .complete && !section.applicationInvalid)
        let result = SurveyRun.outcome(
            before: Self.before, after: Self.before, applicationInvalid: false, treeStatus: section.treeStatus)
        #expect(result.exitStatus == 0)
        let survey = try #require(try record(section, result)["survey"] as? [String: Any])
        #expect(survey["treeStatus"] as? String == "complete")
    }

    @Test func anIncompleteSurveyRecordsWhyItIsIncomplete() throws {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true)
        tree.unknownChildCounts = [4]
        let (_, section) = section(tree)
        #expect(section.treeStatus == .informationUnavailable && section.childrenUnavailable)
        let result = SurveyRun.outcome(
            before: Self.before, after: Self.before, applicationInvalid: false, treeStatus: section.treeStatus)
        let object = try record(section, result)
        #expect(object["status"] as? String == "completed" && result.exitStatus == 1)
        #expect((object["survey"] as? [String: Any])?["treeStatus"] as? String == "informationUnavailable")
    }

    @Test func parentIndicesReconstructTheWalkedTree() throws {
        let tree = SyntheticTree.songs(rows: 2, placeholder: true)
        let (snapshot, section) = section(tree)
        #expect(section.nodes.first?.parent == nil)
        for (index, entry) in snapshot.entries.enumerated() {
            let expected = tree.parents[entry.node].flatMap { parent in
                snapshot.entries.firstIndex { $0.node == parent }
            }
            #expect(section.nodes[index].parent == expected)
            if let parent = section.nodes[index].parent {
                #expect(parent < index && section.nodes[parent].depth == section.nodes[index].depth - 1)
            }
        }
    }

    @Test func windowsMergedIntoTheApplicationHangFromIt() {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true)
        let extra = tree.add(parent: nil, role: "AXWindow")
        tree.mergedWindows[0] = [1, extra]
        let (snapshot, section) = section(tree)
        let index = snapshot.entries.firstIndex { $0.node == extra }
        #expect(index.map { section.nodes[$0].parent } == 0)
        #expect(section.nodes.filter { $0.parent == nil }.count == 1)
    }

    @Test func aTruncatedWalkRecordsOnlyParentsThatWereRecorded() {
        let (_, section) = section(.songs(rows: 5, placeholder: true), limits: WalkLimits(maximumNodes: 6))
        #expect(section.treeStatus == .truncatedByLimit && section.nodes.count == 6)
        for (index, node) in section.nodes.enumerated() {
            if let parent = node.parent { #expect(parent >= 0 && parent < index) } else { #expect(index == 0) }
        }
    }
}

#if canImport(ApplicationServices) && canImport(AppKit)
    /// The identity that a survey compares; constructed snapshots only, without reading the running processes.
    @Suite struct ProcessIdentityTests {
        @Test func anIdentityNeedsExactlyOneProcessWithAKnownLaunchDate() {
            let date = Date(timeIntervalSince1970: 5)
            let known = MusicProcessSnapshot(
                state: .exactlyOne, processIdentifier: 7, musicVersion: "1", launchDate: date)
            #expect(known.identity == ProcessIdentity(processIdentifier: 7, launchDate: date))
            #expect(
                MusicProcessSnapshot(state: .exactlyOne, processIdentifier: 7, musicVersion: "1", launchDate: nil)
                    .identity == nil)
            for state in [MusicProcessState.none, .terminated, .multiple] {
                #expect(
                    MusicProcessSnapshot(state: state, processIdentifier: 7, musicVersion: "1", launchDate: date)
                        .identity == nil)
            }
        }
    }
#endif
