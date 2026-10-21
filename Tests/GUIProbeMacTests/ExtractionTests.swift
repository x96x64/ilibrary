import Foundation
import Testing

@testable import GUIProbeMac

@Suite struct ExtractionTests {
    func read(_ tree: SyntheticTree, limits: WalkLimits = WalkLimits(), rule: ViewRule = Fixtures.songsRule)
        -> ViewReading
    {
        ViewExtractor.reading(of: rule, in: TreeWalker.walk(roots: [0], source: tree, limits: limits), elapsed: 1)
    }

    @Test func aPositivelyEmptyViewIsReadAsSuch() {
        let reading = read(.songs(rows: 0, placeholder: true))
        #expect(reading.treeStatus == .complete)
        #expect(reading.viewIdentified && reading.containerFound)
        #expect(reading.containerRole == "AXTable")
        #expect(reading.contentItemCount == 0 && reading.totalItemCount == 0)
        #expect(reading.placeholderPresent == true && reading.busy == false && reading.scrollable == false)
        #expect(!reading.unexpectedStructure && !reading.unknownLabel)
    }

    @Test func endToEndAnExtractedEmptyViewIsACandidateOnlyWithRepeatedReadings() {
        let reading = read(.songs(rows: 0, placeholder: true))
        let readings = [0.0, 3, 6].map { time -> ViewReading in
            var copy = reading
            copy.elapsed = time
            return copy
        }
        #expect(Fixtures.classify(readings).outcome == "candidateEmpty")
        #expect(Fixtures.classify([reading]).outcome == "indeterminate")
    }

    /// Three agreeing readings of one extracted reading, so that only completeness can decide the verdict.
    func classifyRepeated(_ reading: ViewReading, rule: ViewRule = Fixtures.songsRule) -> Verdict {
        var profile = Fixtures.profile()
        profile.songs = rule
        let readings = [0.0, 3, 6].map { time -> ViewReading in
            var copy = reading
            copy.elapsed = time
            return copy
        }
        return Fixtures.classify(readings, profile: profile)
    }

    // The table is node 4 of the songs tree: application, window, view, scroll area, table.
    static let table = 4

    @Test func aContainerWithAnUnknownChildCountBesideAPlaceholderIsNeverEmpty() {
        var rule = Fixtures.songsRule
        rule.rowsComplete = false
        var tree = SyntheticTree.songs(rows: 0, placeholder: true)
        tree.unknownChildCounts = [Self.table]
        let reading = read(tree, rule: rule)
        #expect(reading.treeStatus == .informationUnavailable)
        #expect(reading.placeholderPresent == true && reading.contentItemCount == 0)
        let verdict = classifyRepeated(reading, rule: rule)
        #expect(verdict.outcome == "indeterminate")
        #expect(Fixtures.reasons(verdict).contains(.treeIncomplete))
    }

    @Test func aContainerWhoseChildrenCannotBeEnumeratedIsNeverEmpty() {
        var rule = Fixtures.songsRule
        rule.rowsComplete = false
        var tree = SyntheticTree.songs(rows: 2, placeholder: true)
        tree.unavailableChildren = [Self.table]
        tree.unknownChildCounts = [Self.table]
        let reading = read(tree, rule: rule)
        #expect(reading.treeStatus == .informationUnavailable && reading.contentItemCount == 0)
        #expect(classifyRepeated(reading, rule: rule).outcome == "indeterminate")
    }

    @Test func aKnownCountFollowedByAnUnavailableOrShorterEnumerationIsIncomplete() {
        var rule = Fixtures.songsRule
        rule.rowsComplete = false
        var unavailable = SyntheticTree.songs(rows: 0, placeholder: true)
        unavailable.nodes[Self.table].childCount = 3
        unavailable.unavailableChildren = [Self.table]
        #expect(read(unavailable, rule: rule).treeStatus == .informationUnavailable)
        var shorter = SyntheticTree.songs(rows: 0, placeholder: true)
        shorter.nodes[Self.table].childCount = 3
        let reading = read(shorter, rule: rule)
        #expect(reading.treeStatus == .informationUnavailable)
        #expect(classifyRepeated(reading, rule: rule).outcome == "indeterminate")
    }

    @Test func anUnavailableWindowsListOfTheApplicationMakesTheWalkIncomplete() {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true)
        tree.unavailableChildren = [0]
        let snapshot = TreeWalker.walk(roots: [0], source: tree, limits: WalkLimits())
        #expect(snapshot.childrenUnavailable && snapshot.status == .informationUnavailable)
    }

    @Test func aBoundaryNodeWithAnUnknownChildCountTruncatesTheWalk() {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true)
        tree.unknownChildCounts = [Self.table]
        let limits = WalkLimits(maximumNodes: 100, maximumDepth: 4, timeoutSeconds: 2)
        let snapshot = TreeWalker.walk(roots: [0], source: tree, limits: limits)
        #expect(snapshot.truncatedByDepthLimit && snapshot.status == .truncatedByLimit)
        var known = SyntheticTree.songs(rows: 0, placeholder: true)
        known.nodes[Self.table].childCount = 0
        #expect(!TreeWalker.walk(roots: [0], source: known, limits: limits).truncatedByDepthLimit)
    }

    @Test func anElementWithoutARoleMakesTheWalkIncomplete() {
        var rule = Fixtures.songsRule
        rule.rowsComplete = false
        var tree = SyntheticTree.songs(rows: 1, placeholder: true)
        tree.nodes[Self.table + 1].role = nil
        let reading = read(tree, rule: rule)
        #expect(reading.treeStatus == .informationUnavailable && reading.contentItemCount == 0)
        #expect(classifyRepeated(reading, rule: rule).outcome == "indeterminate")
    }

    @Test func rowsAreCounted() {
        let reading = read(.songs(rows: 3, placeholder: false))
        #expect(reading.contentItemCount == 3 && reading.totalItemCount == 3)
        #expect(reading.placeholderPresent == false)
    }

    @Test func rowsOutsideTheVisibleRegionAreNotInvisible() {
        let reading = read(.songs(rows: 0, placeholder: false, verticalScrollBar: true, totalRows: 30))
        #expect(reading.contentItemCount == 0 && reading.totalItemCount == 30 && reading.scrollable == true)
        #expect(Fixtures.classify([reading, reading, reading]).outcome == "indeterminate")
    }

    @Test func incompleteRowsDeclarationLeavesTheTotalUnknown() {
        var rule = Fixtures.songsRule
        rule.rowsComplete = false
        #expect(read(.songs(rows: 0, placeholder: true), rule: rule).totalItemCount == nil)
    }

    @Test func aViewMatchedTwiceIsNotIdentified() {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true)
        tree.add(parent: 1, role: "AXGroup", identifier: "songs-view", title: "Songs")
        let reading = read(tree)
        #expect(!reading.viewIdentified && !reading.containerFound && reading.contentItemCount == nil)
    }

    @Test func anotherLocalizationIsAnUnknownLabel() {
        let reading = read(.songs(rows: 0, placeholder: true, label: "曲"))
        #expect(reading.unknownLabel && !reading.viewIdentified)
    }

    @Test func aMissingViewIsNotAnUnknownLabelAndNotEmpty() {
        var tree = SyntheticTree()
        let app = tree.add(parent: nil, role: "AXApplication")
        tree.add(parent: app, role: "AXWindow")
        let reading = read(tree)
        #expect(!reading.viewIdentified && !reading.unknownLabel && reading.contentItemCount == nil)
    }

    @Test func aMissingContainerIsReported() {
        var tree = SyntheticTree()
        let app = tree.add(parent: nil, role: "AXApplication")
        tree.add(parent: app, role: "AXGroup", identifier: "songs-view", title: "Songs", busy: false)
        let reading = read(tree)
        #expect(reading.viewIdentified && !reading.containerFound && reading.contentItemCount == nil)
    }

    @Test func twoContainersAreUnexpectedStructure() {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true)
        tree.add(parent: 2, role: "AXTable")
        let reading = read(tree)
        #expect(reading.unexpectedStructure && reading.containerFound && reading.contentItemCount == nil)
    }

    @Test func aTruncatedTreeNeverYieldsNegativeEvidence() {
        let reading = read(.songs(rows: 0, placeholder: false, busy: nil), limits: WalkLimits(maximumNodes: 4))
        #expect(reading.treeStatus == .truncatedByLimit)
        #expect(reading.placeholderPresent == nil)
        #expect(reading.busy == nil)
    }

    @Test func busyComesFromTheAttributeOrALoadingIndicator() {
        #expect(read(.songs(rows: 0, placeholder: true, busy: true)).busy == true)
        #expect(read(.songs(rows: 0, placeholder: true, busy: nil)).busy == false)
        var tree = SyntheticTree.songs(rows: 0, placeholder: true, busy: false)
        tree.add(parent: 2, role: "AXProgressIndicator")
        #expect(read(tree).busy == true)
    }

    @Test func withoutAnyLoadingSignalBusyIsUnknown() {
        var rule = Fixtures.songsRule
        rule.loading = nil
        #expect(read(.songs(rows: 0, placeholder: true, busy: nil), rule: rule).busy == nil)
    }

    @Test func aMissingScrollBarAttributeIsUnknownNotFalse() {
        #expect(read(.songs(rows: 0, placeholder: true, verticalScrollBar: nil)).scrollable == nil)
    }

    @Test func theEmptyStateRuleIsOptional() {
        var rule = Fixtures.songsRule
        rule.placeholder = nil
        #expect(read(.songs(rows: 0, placeholder: true), rule: rule).placeholderPresent == nil)
    }

    @Test func anUnsupportedScrollBarAttributeLeavesScrollabilityUnknown() {
        // The table does not support the attribute and no scroll area contains it.
        var tree = SyntheticTree()
        let app = tree.add(parent: nil, role: "AXApplication")
        let window = tree.add(parent: app, role: "AXWindow")
        let view = tree.add(parent: window, role: "AXGroup", identifier: "songs-view", title: "Songs", busy: false)
        let table = tree.add(parent: view, role: "AXTable", rowCount: 0, verticalScrollBar: false)
        _ = table
        tree.add(parent: view, role: "AXStaticText", identifier: "empty-state")
        let reading = read(tree)
        #expect(reading.containerFound && reading.scrollable == nil)
    }

    @Test func aScrollAreaAboveTheViewIsInspected() {
        var tree = SyntheticTree()
        let app = tree.add(parent: nil, role: "AXApplication")
        let window = tree.add(parent: app, role: "AXWindow")
        let area = tree.add(parent: window, role: "AXScrollArea", verticalScrollBar: false)
        let view = tree.add(parent: area, role: "AXGroup", identifier: "songs-view", title: "Songs", busy: false)
        tree.add(parent: view, role: "AXTable", rowCount: 0)
        #expect(read(tree).scrollable == false)
        tree.nodes[area].hasVerticalScrollBar = true
        #expect(read(tree).scrollable == true)
    }

    @Test func anUnknownScrollAreaBlocksAPositiveFalse() {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true, verticalScrollBar: false)
        let outer = tree.add(parent: 1, role: "AXScrollArea", verticalScrollBar: nil)
        tree.parents[2] = outer
        #expect(read(tree).scrollable == nil)
    }

    @Test func aWalkReportsAnInvalidApplicationElement() {
        var tree = SyntheticTree()
        tree.add(
            parent: nil, role: "AXApplication",
            errors: [AttributeError(attribute: "AXRole", code: accessibilityInvalidElement)])
        let snapshot = TreeWalker.walk(roots: [0], source: tree, limits: WalkLimits())
        #expect(snapshot.applicationInvalid)
        #expect(
            !TreeWalker.walk(roots: [0], source: SyntheticTree.songs(rows: 0, placeholder: true), limits: WalkLimits())
                .applicationInvalid)
    }
}
