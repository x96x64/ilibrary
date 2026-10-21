// Synthetic tests of the survey's time budget, timeout breaker, destination validation, publication, and record
// format. The clock is injected, the trees are synthetic, and the directories are disposable ones created by each
// test inside the temporary directory; nothing here reads Music, an accessibility interface, or a personal folder.
import Foundation
import Testing

@testable import GUIProbeMac

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// A clock that advances only when the synthetic tree is read.
final class SteppedClock {
    var now = 0.0
}

/// A synthetic tree whose every facts read advances the clock, and whose listed nodes report a timed-out request.
struct TimedTree: TreeSource {
    var tree: SyntheticTree
    let clock: SteppedClock
    var step = 1.0
    var timedOutNodes: Set<Int> = []

    func facts(of node: Int) -> NodeFacts {
        clock.now += step
        var facts = tree.facts(of: node)
        if timedOutNodes.contains(node) {
            facts.errors.append(AttributeError(attribute: "AXTitle", code: accessibilityCannotComplete))
        }
        return facts
    }

    func children(of node: Int) -> Children<Int> { tree.children(of: node) }
}

@Suite struct SurveyBudgetTests {
    /// The songs tree has nine nodes: application (0), window (1), view (2), scroll area (3), table (4), three rows
    /// (5 to 7), and placeholder (8); breadth-first, they are read in the order 0, 1, 2, 3, 8, 4, 5, 6, 7.
    static var tree: SyntheticTree { .songs(rows: 3, placeholder: true) }

    func walk(_ source: TimedTree, budget: Double?, breaker: Int? = nil, maximumNodes: Int = 5_000)
        -> TreeSnapshot<Int>
    {
        var limits = WalkLimits(maximumNodes: maximumNodes)
        limits.timeBudgetSeconds = budget
        limits.maximumConsecutiveTimedOutNodes = breaker
        return TreeWalker.walk(roots: [0], source: source, limits: limits, elapsed: { source.clock.now })
    }

    @Test func aWalkWithinItsBudgetIsComplete() {
        let snapshot = walk(TimedTree(tree: Self.tree, clock: SteppedClock()), budget: 100)
        #expect(snapshot.entries.count == 9 && snapshot.status == .complete)
        #expect(!snapshot.truncatedByDeadline && !snapshot.stoppedByRepeatedTimeouts)
    }

    @Test func aBudgetExpiredBeforeTheFirstNodeIsTruncatedNotMissing() {
        let clock = SteppedClock()
        clock.now = 5
        let snapshot = walk(TimedTree(tree: Self.tree, clock: clock), budget: 5)
        #expect(snapshot.entries.isEmpty && snapshot.truncatedByDeadline)
        #expect(snapshot.status == .truncatedByLimit)
    }

    @Test func aBudgetExpiringWithUnreadNodesStopsTheWalk() {
        let snapshot = walk(TimedTree(tree: Self.tree, clock: SteppedClock()), budget: 4)
        // The clock reaches 4 while reading the fourth node, whose children are therefore not enumerated.
        #expect(snapshot.entries.count == 4 && snapshot.truncatedByDeadline)
        #expect(snapshot.status == .truncatedByLimit)
        let section = SurveySanitizer.section(snapshot, limits: WalkLimits())
        #expect(section.truncatedByDeadline && section.treeStatus == .truncatedByLimit && section.nodes.count == 4)
    }

    @Test func aSkippedEnumerationIsIncompleteEvenForALeafThatReportedNoChildren() {
        // A single root that reports no children; the budget expires while its facts are read.
        var tree = SyntheticTree()
        tree.add(parent: nil, role: "AXApplication", childCount: 0)
        let snapshot = walk(TimedTree(tree: tree, clock: SteppedClock()), budget: 1)
        #expect(snapshot.entries.count == 1 && snapshot.truncatedByDeadline && snapshot.status != .complete)
    }

    @Test func aBudgetReachedExactlyCountsAsExpired() {
        let exact = walk(TimedTree(tree: Self.tree, clock: SteppedClock()), budget: 9)
        #expect(exact.truncatedByDeadline && exact.status != .complete)
        let ample = walk(TimedTree(tree: Self.tree, clock: SteppedClock()), budget: 9.5)
        #expect(!ample.truncatedByDeadline && ample.status == .complete)
    }

    @Test func aDeadlineNeverHidesATimeout() {
        var source = TimedTree(tree: Self.tree, clock: SteppedClock())
        source.timedOutNodes = [1]
        let snapshot = walk(source, budget: 4)
        #expect(snapshot.truncatedByDeadline && snapshot.timedOut && snapshot.status == .timedOut)
        let section = SurveySanitizer.section(snapshot, limits: WalkLimits())
        #expect(section.truncatedByDeadline && section.errorCountsByCode[String(accessibilityCannotComplete)] == 1)
    }

    @Test func consecutiveTimedOutNodesStopTheWalk() {
        var source = TimedTree(tree: Self.tree, clock: SteppedClock())
        source.timedOutNodes = [0, 1, 2, 3, 8]
        let snapshot = walk(source, budget: nil, breaker: 5)
        #expect(snapshot.stoppedByRepeatedTimeouts && snapshot.entries.count == 5)
        #expect(snapshot.status == .timedOut && !snapshot.truncatedByDeadline)
    }

    @Test func aNodeWithoutATimeoutResetsTheCount() {
        var source = TimedTree(tree: Self.tree, clock: SteppedClock())
        // The placeholder, read fifth, has no timeout and resets the count after four.
        source.timedOutNodes = [0, 1, 2, 3, 4, 5, 6, 7]
        let snapshot = walk(source, budget: nil, breaker: 5)
        #expect(!snapshot.stoppedByRepeatedTimeouts && snapshot.entries.count == 9 && snapshot.status == .timedOut)
    }

    @Test func aBreakerOnTheLastNodeStillMarksTheWalkIncomplete() {
        var tree = SyntheticTree()
        tree.add(parent: nil, role: "AXApplication", childCount: 0)
        var source = TimedTree(tree: tree, clock: SteppedClock())
        source.timedOutNodes = [0]
        let snapshot = walk(source, budget: nil, breaker: 1)
        #expect(snapshot.stoppedByRepeatedTimeouts && snapshot.status != .complete)
    }

    @Test func severalCausesAreAllRecorded() {
        var source = TimedTree(tree: Self.tree, clock: SteppedClock())
        source.timedOutNodes = [2]
        let snapshot = walk(source, budget: 3, maximumNodes: 2)
        #expect(snapshot.truncatedByNodeLimit && snapshot.entries.count == 2)
        let deadline = walk(TimedTree(tree: Self.tree, clock: SteppedClock()), budget: 2, maximumNodes: 3)
        #expect(deadline.truncatedByDeadline && !deadline.truncatedByNodeLimit)
    }

    @Test func withoutLimitsTheWalkIsUnchanged() {
        // Observe passes neither limit, so neither flag can arise however slow or failing the reads are.
        var source = TimedTree(tree: Self.tree, clock: SteppedClock())
        source.step = 1_000
        source.timedOutNodes = Set(0..<9)
        let snapshot = walk(source, budget: nil, breaker: nil)
        #expect(snapshot.entries.count == 9 && !snapshot.truncatedByDeadline && !snapshot.stoppedByRepeatedTimeouts)
        #expect(WalkLimits().timeBudgetSeconds == nil && WalkLimits().maximumConsecutiveTimedOutNodes == nil)
    }
}

/// A disposable directory tree standing in for a home directory.
struct DisposableHome {
    let path: String

    init() throws {
        path =
            FileManager.default.temporaryDirectory.appendingPathComponent("guiprobe-home-\(UUID().uuidString)")
            .path
        try make("")
    }

    func make(_ relative: String, mode: mode_t = 0o700) throws {
        let full = relative.isEmpty ? path : path + "/" + relative
        guard mkdir(full, mode) == 0 || errno == EEXIST, chmod(full, mode) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func remove() { try? FileManager.default.removeItem(atPath: path) }
}

@Suite struct SurveyPlacementTests {
    static let user = getuid()

    func prepared() throws -> DisposableHome {
        let home = try DisposableHome()
        for directory in ["survey", "survey/records", "survey/private"] { try home.make(directory) }
        return home
    }

    func open(_ relative: String, in home: DisposableHome) throws -> ValidatedDirectory {
        try SurveyPlacement.openValidated(
            try SurveyPlacement.components(of: relative), home: home.path, user: Self.user)
    }

    @Test func aPrivateDirectoryBelowTheHomeIsAccepted() throws {
        let home = try prepared()
        defer { home.remove() }
        let records = try open("survey/records", in: home)
        let mapping = try open("survey/private", in: home)
        defer {
            close(records.descriptor)
            close(mapping.descriptor)
        }
        #expect(records.chain.count == 3 && mapping.chain.count == 3)
        try SurveyPlacement.requireSeparate(records, mapping)
    }

    @Test func theSameOrANestedDirectoryIsRefused() throws {
        let home = try prepared()
        defer { home.remove() }
        let records = try open("survey/records", in: home)
        let same = try open("survey/records", in: home)
        let parent = try open("survey", in: home)
        defer { [records, same, parent].forEach { close($0.descriptor) } }
        #expect(throws: PlacementError.nested) { try SurveyPlacement.requireSeparate(records, same) }
        #expect(throws: PlacementError.nested) { try SurveyPlacement.requireSeparate(records, parent) }
        #expect(throws: PlacementError.nested) { try SurveyPlacement.requireSeparate(parent, records) }
    }

    @Test func aLinkedComponentIsRefused() throws {
        let home = try prepared()
        defer { home.remove() }
        #expect(symlink(home.path + "/survey", home.path + "/link") == 0)
        #expect(throws: PlacementError.self) { _ = try open("link/records", in: home) }
        #expect(symlink(home.path + "/survey/records", home.path + "/survey/final-link") == 0)
        #expect(throws: PlacementError.self) { _ = try open("survey/final-link", in: home) }
    }

    @Test func permissionsOpenToOthersAreRefused() throws {
        let home = try prepared()
        defer { home.remove() }
        try home.make("survey/records", mode: 0o750)
        #expect(throws: PlacementError.unsafePermissions("records")) { _ = try open("survey/records", in: home) }
        try home.make("survey/records", mode: 0o700)
        try home.make("survey", mode: 0o770)
        #expect(throws: PlacementError.unsafePermissions("survey")) { _ = try open("survey/records", in: home) }
        try home.make("survey", mode: 0o700)
        try home.make("", mode: 0o722)
        #expect(throws: PlacementError.unsafePermissions(home.path)) { _ = try open("survey/records", in: home) }
    }

    @Test func aGitWorkingTreeIsRefused() throws {
        let home = try prepared()
        defer { home.remove() }
        try home.make("survey/.git")
        #expect(throws: PlacementError.repository("survey")) { _ = try open("survey/records", in: home) }
    }

    @Test func aMissingDirectoryIsRefused() throws {
        let home = try prepared()
        defer { home.remove() }
        #expect(throws: PlacementError.self) { _ = try open("survey/absent", in: home) }
    }

    @Test func protectedFoldersAreRefusedWithoutBeingOpened() throws {
        let home = try prepared()
        defer { home.remove() }
        // None of these folders exists in the disposable home; the refusal is lexical.
        for path in ["Music/x", "music/x", "LIBRARY", "Desktop/a", "documents", "Downloads/b", "Public"] {
            #expect(throws: PlacementError.self) { _ = try SurveyPlacement.components(of: path) }
        }
        // A trailing line terminator never passes the ASCII-only patterns.
        for path in [
            "/abs", "a/../b", "a//b", "./a", ".hidden", "a/", "caf\u{E9}", "", "survey\n", "survey\r\n",
            "survey\u{85}", "survey\u{2028}", "survey\u{2029}",
        ] {
            #expect(throws: PlacementError.self) { _ = try SurveyPlacement.components(of: path) }
        }
        #expect(
            try SurveyPlacement.components(of: "ilibrary-gui-survey/records") == ["ilibrary-gui-survey", "records"])
    }

    /// The checks are made on every Unicode scalar of the input, so a disallowed suffix is never ignored, whatever
    /// the platform's regular-expression engine does with an end anchor. Nothing here touches the file system.
    @Test(arguments: ["\n", "\r", "\r\n", "\u{85}", "\u{2028}", "\u{2029}", "\u{0}", "\t", " ", "\u{FEFF}"])
    func aDisallowedSuffixIsRefusedInComponentsAndNames(suffix: String) {
        for path in ["survey" + suffix, "survey" + suffix + "/records", "Music" + suffix, "music" + suffix + "/x"] {
            #expect(throws: PlacementError.self) { _ = try SurveyPlacement.components(of: path) }
        }
        for name in ["songs.json" + suffix, "songs" + suffix + ".json", suffix + "songs.json"] {
            #expect(throws: PlacementError.self) { try SurveyPlacement.validateName(name) }
            #expect(!SurveyPlacement.isPermittedName(name))
        }
        #expect(!SurveyPlacement.isPermittedComponent("survey" + suffix))
    }

    @Test func theReportedExamplesAreRefused() {
        #expect(throws: PlacementError.invalidComponent("survey\n")) {
            _ = try SurveyPlacement.components(of: "survey\n")
        }
        #expect(throws: PlacementError.invalidName("songs.json\n")) { try SurveyPlacement.validateName("songs.json\n") }
    }

    @Test func embeddedDisallowedCharactersAreRefused() {
        for component in ["sur\nvey", "sur vey", "sur\u{2028}vey", "caf\u{E9}", "-survey", "_survey", "sur:vey"] {
            #expect(!SurveyPlacement.isPermittedComponent(component), "\(component.debugDescription)")
        }
        for name in ["so\nngs.json", "songs.js\non", "songs.json.json", "songs .json", "-songs.json", "songs.jso"] {
            #expect(!SurveyPlacement.isPermittedName(name), "\(name.debugDescription)")
        }
    }

    @Test func theLengthLimitsAreExact() {
        #expect(SurveyPlacement.isPermittedComponent("a") && SurveyPlacement.isPermittedComponent("a.b_c-1"))
        #expect(SurveyPlacement.isPermittedComponent(String(repeating: "a", count: 64)))
        #expect(!SurveyPlacement.isPermittedComponent(String(repeating: "a", count: 65)))
        #expect(!SurveyPlacement.isPermittedComponent(""))
        #expect(SurveyPlacement.isPermittedName("a.json") && SurveyPlacement.isPermittedName("recently-added_2.json"))
        #expect(SurveyPlacement.isPermittedName(String(repeating: "b", count: 48) + ".json"))
        #expect(!SurveyPlacement.isPermittedName(String(repeating: "b", count: 49) + ".json"))
        #expect(!SurveyPlacement.isPermittedName(".json") && !SurveyPlacement.isPermittedName("json"))
    }

    @Test func anExistingNameIsRefusedAndALinkCountsAsExisting() throws {
        let home = try prepared()
        defer { home.remove() }
        let records = try open("survey/records", in: home)
        defer { close(records.descriptor) }
        try SurveyPlacement.requireAbsent("songs.json", in: records)
        #expect(FileManager.default.createFile(atPath: home.path + "/survey/records/songs.json", contents: Data()))
        #expect(throws: PlacementError.alreadyExists("songs.json")) {
            try SurveyPlacement.requireAbsent("songs.json", in: records)
        }
        #expect(symlink("/nonexistent-target", home.path + "/survey/records/dangling.json") == 0)
        #expect(throws: PlacementError.alreadyExists("dangling.json")) {
            try SurveyPlacement.requireAbsent("dangling.json", in: records)
        }
    }

    @Test func aSubstitutedOrLoosenedDirectoryFailsTheRecheck() throws {
        let home = try prepared()
        defer { home.remove() }
        let records = try open("survey/records", in: home)
        defer { close(records.descriptor) }
        try SurveyPlacement.recheck(records, home: home.path, user: Self.user)
        #expect(rename(home.path + "/survey/records", home.path + "/survey/moved") == 0)
        try home.make("survey/records")
        #expect(throws: PlacementError.moved("records")) {
            try SurveyPlacement.recheck(records, home: home.path, user: Self.user)
        }
        let replacement = try open("survey/records", in: home)
        defer { close(replacement.descriptor) }
        try home.make("survey/records", mode: 0o755)
        #expect(throws: PlacementError.unsafePermissions("records")) {
            try SurveyPlacement.recheck(replacement, home: home.path, user: Self.user)
        }
    }

    @Test func namesAreSingleComponentsAndTheMappingNameIsNeverARecordName() throws {
        for name in ["songs.json", "recently-added_2.json"] { try SurveyPlacement.validateName(name) }
        for name in [
            "songs", "a/b.json", ".songs.json", "songs.v2.json", "../x.json", "", "x.JSON", "songs.json\n",
            "songs.json\u{2028}",
        ] {
            #expect(throws: PlacementError.invalidName(name)) { try SurveyPlacement.validateName(name) }
        }
        let mapping = SurveyPlacement.mappingName(for: "songs.json")
        #expect(mapping == "songs.identifier-map.json")
        #expect(throws: PlacementError.self) { try SurveyPlacement.validateName(mapping) }
        let temporary = SurveyPlacement.temporaryName(for: "songs.json", runID: "RUN")
        #expect(temporary == ".songs.json.RUN.partial")
        #expect(throws: PlacementError.self) { try SurveyPlacement.validateName(temporary) }
    }
}

@Suite struct SurveyPublicationTests {
    func directory() throws -> (DisposableHome, Int32) {
        let home = try DisposableHome()
        #if canImport(Darwin)
            let descriptor = Darwin.open(home.path, O_RDONLY | O_DIRECTORY)
        #else
            let descriptor = Glibc.open(home.path, O_RDONLY | O_DIRECTORY)
        #endif
        #expect(descriptor >= 0)
        return (home, descriptor)
    }

    func contents(_ home: DisposableHome) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: home.path).sorted()
    }

    @Test func aPublishedFileIsCompleteOwnerOnlyAndAlone() throws {
        let (home, descriptor) = try directory()
        defer {
            close(descriptor)
            home.remove()
        }
        let data = Data("{\"complete\": true}\n".utf8)
        #expect(try Publication.publish(data, name: "songs.json", runID: "RUN", in: descriptor) == nil)
        #expect(try contents(home) == ["songs.json"])
        let path = home.path + "/songs.json"
        #expect(FileManager.default.contents(atPath: path) == data)
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func anExistingFinalNameIsNeverReplaced() throws {
        let (home, descriptor) = try directory()
        defer {
            close(descriptor)
            home.remove()
        }
        let original = Data("original\n".utf8)
        #expect(FileManager.default.createFile(atPath: home.path + "/songs.json", contents: original))
        #expect(throws: PublicationError.self) {
            try Publication.publish(Data("new\n".utf8), name: "songs.json", runID: "RUN", in: descriptor)
        }
        #expect(FileManager.default.contents(atPath: home.path + "/songs.json") == original)
        // The complete temporary file is kept for review, under a name that is never a record name.
        #expect(try contents(home) == [".songs.json.RUN.partial", "songs.json"])
        #expect(FileManager.default.contents(atPath: home.path + "/.songs.json.RUN.partial") == Data("new\n".utf8))
    }

    @Test func anExistingTemporaryNameStopsBeforeAnythingIsWritten() throws {
        let (home, descriptor) = try directory()
        defer {
            close(descriptor)
            home.remove()
        }
        // A leftover from an interrupted run, such as a partial write, is neither overwritten nor published.
        let partial = Data("{\"inter".utf8)
        #expect(FileManager.default.createFile(atPath: home.path + "/.songs.json.RUN.partial", contents: partial))
        #expect(throws: PublicationError.self) {
            try Publication.publish(Data("{}\n".utf8), name: "songs.json", runID: "RUN", in: descriptor)
        }
        #expect(try contents(home) == [".songs.json.RUN.partial"])
        #expect(FileManager.default.contents(atPath: home.path + "/.songs.json.RUN.partial") == partial)
    }
}

@Suite struct SurveyRecordFormatTests {
    @Test func aSurveyRecordCarriesAliasesAndNeverARawIdentifier() throws {
        var tree = SyntheticTree.songs(rows: 1, placeholder: true)
        tree.nodes[4].identifier = "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"
        tree.nodes[4].hasIdentifier = true
        let snapshot = TreeWalker.walk(roots: [0], source: tree, limits: WalkLimits())
        var aliases = IdentifierAliases()
        var record = ProbeOutput(
            mode: "survey", status: .completed, macOSVersion: Fixtures.macOS, musicVersion: Fixtures.music,
            confirmations: Confirmations())
        record.format = ProbeOutput.surveyFormat
        record.operatorDisplayedView = DisplayedView.recentlyAdded.rawValue
        record.survey = SurveySanitizer.section(
            snapshot, limits: WalkLimits(), aliases: &aliases, elapsedSeconds: 1.5, hardLimitSeconds: 660,
            runID: "RUN", identifierMappingName: "songs.identifier-map.json")
        let data = try record.json()
        let text = String(decoding: data, as: UTF8.self)
        for raw in aliases.values { #expect(!text.contains(raw)) }
        #expect(!text.contains("\"identifier\""))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["format"] as? String == "ilibrary-gui-probe-output-2")
        #expect(object["operatorDisplayedView"] as? String == "recently-added")
        let survey = try #require(object["survey"] as? [String: Any])
        #expect(survey["runID"] as? String == "RUN" && survey["hardLimitSeconds"] as? Double == 660)
        #expect(survey["identifierMappingName"] as? String == "songs.identifier-map.json")
        #expect(survey["identifierPrivacy"] as? String == SurveySection.identifierPrivacyStatement)
        let nodes = try #require(survey["nodes"] as? [[String: Any]])
        #expect(nodes.compactMap { $0["identifierShape"] as? String }.contains("uuid"))
        #expect(aliases.values.contains("0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"))
    }

    @Test func anObserveRecordKeepsVersionOneAndItsFields() throws {
        let record = ProbeOutput(
            mode: "observe", status: .refused, stopReason: "refused", sourceCommit: "abc",
            macOSVersion: Fixtures.macOS, musicVersion: nil, confirmations: Confirmations())
        let object = try #require(JSONSerialization.jsonObject(with: record.json()) as? [String: Any])
        #expect(object["format"] as? String == "ilibrary-gui-probe-output-1")
        #expect(
            Set(object.keys) == [
                "format", "mode", "status", "stopReason", "probeVersion", "operatorSourceLabel", "macOSVersion",
                "operatorConfirmations", "provenance",
            ])
        #expect(object["operatorDisplayedView"] == nil && object["probeVersion"] as? String == "0.2.0")
    }
}
