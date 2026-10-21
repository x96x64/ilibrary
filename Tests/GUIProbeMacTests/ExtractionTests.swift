import Foundation
import Testing

@testable import GUIProbeMac

@Suite struct ExtractionTests {
    func read(_ tree: SyntheticTree, limits: WalkLimits = WalkLimits(), rule: ViewRule = Fixtures.songsRule)
        -> ViewReading
    {
        ViewExtractor.reading(of: rule, in: TreeWalker.walk(roots: [0], source: tree, limits: limits), elapsed: 1)
    }

    @Test func anEmptyViewIsReadWithItsEvidenceButWithUnknownScrollability() {
        let reading = read(.songs(rows: 0, placeholder: true))
        #expect(reading.treeStatus == .complete)
        #expect(reading.viewIdentified && reading.containerFound && !reading.viewAmbiguous)
        #expect(reading.containerRole == "AXTable")
        #expect(reading.contentItemCount == 0 && reading.totalItemCount == 0)
        #expect(reading.placeholderPresent == true && reading.busy == false)
        // Both the scroll area and the table report their scroll bar as no value, which is not positive evidence.
        #expect(reading.scrollable == nil)
        #expect(!reading.unexpectedStructure && !reading.unknownLabel)
    }

    @Test func endToEndAnExtractedEmptyViewIsNeverACandidateBecauseScrollabilityIsUnknown() {
        let reading = read(.songs(rows: 0, placeholder: true))
        let readings = [0.0, 3, 6].map { time -> ViewReading in
            var copy = reading
            copy.elapsed = time
            return copy
        }
        let verdict = Fixtures.classify(readings)
        #expect(verdict.outcome == "indeterminate")
        #expect(Fixtures.reasons(verdict) == [.scrollableOrUnknown])
    }

    /// Classifier only: a positive non-scrollability that no extracted reading supplies is substituted into the
    /// otherwise extracted readings, to show that the remaining requirements still demand repeated readings.
    @Test func classifierOnlyAHypotheticalNonScrollableReadingNeedsRepeatedReadings() {
        var reading = read(.songs(rows: 0, placeholder: true))
        reading.scrollable = false
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
        #expect(read(tree).scrollable == nil)
        tree.nodes[area].hasVerticalScrollBar = true
        #expect(read(tree).scrollable == true)
    }

    @Test func anUnknownScrollAreaLeavesScrollabilityUnknown() {
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

    /// A general accessibility failure, as an attribute read that fails records it; the reader never records a
    /// status of no value or unsupported as an error.
    static let failure: Int32 = -25200

    // MARK: Scroll bars

    @Test func anAbsentScrollBarNeverEstablishesNonScrollability() {
        // No scroll area: the table alone reports its scroll bar as no value.
        var tree = SyntheticTree()
        let app = tree.add(parent: nil, role: "AXApplication")
        let window = tree.add(parent: app, role: "AXWindow")
        let view = tree.add(parent: window, role: "AXGroup", identifier: "songs-view", title: "Songs", busy: false)
        tree.add(parent: view, role: "AXTable", rowCount: 0, verticalScrollBar: false)
        tree.add(parent: view, role: "AXStaticText", identifier: "empty-state")
        let reading = read(tree)
        #expect(reading.treeStatus == .complete && reading.scrollable == nil)
        let verdict = classifyRepeated(reading)
        #expect(verdict.outcome == "indeterminate" && Fixtures.reasons(verdict).contains(.scrollableOrUnknown))
    }

    @Test func aPositiveScrollBarOnTheContainerMakesTheViewScrollable() {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true)
        tree.nodes[Self.table].hasVerticalScrollBar = true
        let reading = read(tree)
        #expect(reading.scrollable == true)
        #expect(Fixtures.reasons(classifyRepeated(reading)).contains(.scrollableOrUnknown))
    }

    // MARK: Loading indicators

    static var spinnerRule: ViewRule {
        var rule = Fixtures.songsRule
        rule.loading = ElementRule(role: "AXProgressIndicator", identifier: "spinner", label: "Loading")
        return rule
    }

    /// The songs tree, not busy by its own attribute, with one progress indicator inside the view.
    static func treeWithIndicator(
        identifier: String?, title: String?, description: String? = nil, errors: [AttributeError] = []
    ) -> (tree: SyntheticTree, indicator: Int) {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true, busy: false)
        let indicator = tree.add(
            parent: 2, role: "AXProgressIndicator", identifier: identifier, title: title, description: description,
            errors: errors)
        return (tree, indicator)
    }

    @Test func anIndicatorWithAnUnreadableIdentifierPreventsNotBusy() {
        let (tree, _) = Self.treeWithIndicator(
            identifier: nil, title: "Loading", errors: [AttributeError(attribute: "AXIdentifier", code: Self.failure)])
        let reading = read(tree, rule: Self.spinnerRule)
        #expect(reading.busy == nil)
        #expect(Fixtures.reasons(classifyRepeated(reading, rule: Self.spinnerRule)).contains(.loadingUnknown))
        // An identifier that is returned but is not text is likewise unreadable.
        var nonText = Self.treeWithIndicator(identifier: nil, title: "Loading")
        nonText.tree.nodes[nonText.indicator].hasIdentifier = true
        #expect(read(nonText.tree, rule: Self.spinnerRule).busy == nil)
    }

    @Test func anIndicatorWithAnUnreadableLabelPreventsNotBusy() {
        let unreadableTitle = Self.treeWithIndicator(
            identifier: "spinner", title: nil, errors: [AttributeError(attribute: "AXTitle", code: Self.failure)])
        #expect(read(unreadableTitle.tree, rule: Self.spinnerRule).busy == nil)
        // A title that differs does not exclude the indicator while its description is unreadable.
        let unreadableDescription = Self.treeWithIndicator(
            identifier: "spinner", title: "Other",
            errors: [AttributeError(attribute: "AXDescription", code: Self.failure)])
        #expect(read(unreadableDescription.tree, rule: Self.spinnerRule).busy == nil)
        // Either attribute carrying the label is a definite match.
        let byDescription = Self.treeWithIndicator(identifier: "spinner", title: "Other", description: "Loading")
        #expect(read(byDescription.tree, rule: Self.spinnerRule).busy == true)
    }

    @Test func aDefinitelyMismatchedIndicatorIsExcluded() {
        let otherIdentifier = Self.treeWithIndicator(identifier: "other", title: "Loading")
        #expect(read(otherIdentifier.tree, rule: Self.spinnerRule).busy == false)
        // An identifier reported as absent is a definite absence; the title cannot then rescue the match.
        let noIdentifier = Self.treeWithIndicator(identifier: nil, title: "Loading")
        #expect(read(noIdentifier.tree, rule: Self.spinnerRule).busy == false)
        // A definite mismatch of one requirement excludes the element even when another is unreadable.
        let mixed = Self.treeWithIndicator(
            identifier: "other", title: nil, errors: [AttributeError(attribute: "AXTitle", code: Self.failure)])
        #expect(read(mixed.tree, rule: Self.spinnerRule).busy == false)
    }

    @Test func aPossibleIndicatorIsNeitherLoadingNorNotBusy() {
        // The view's own busy attribute reports false, which must not override the uncertainty.
        let (tree, _) = Self.treeWithIndicator(
            identifier: "spinner", title: nil, errors: [AttributeError(attribute: "AXTitle", code: Self.failure)])
        let reading = read(tree, rule: Self.spinnerRule)
        #expect(reading.busy == nil)
        let reasons = Fixtures.reasons(classifyRepeated(reading, rule: Self.spinnerRule))
        #expect(reasons.contains(.loadingUnknown) && !reasons.contains(.loading))
        // A view that reports itself busy remains busy.
        var busy = tree
        busy.nodes[2].busy = true
        #expect(read(busy, rule: Self.spinnerRule).busy == true)
    }

    // MARK: View identity

    @Test func aSecondViewWithAnUnreadableIdentifierMakesTheViewAmbiguous() {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true)
        tree.add(
            parent: 1, role: "AXGroup", title: "Songs",
            errors: [AttributeError(attribute: "AXIdentifier", code: Self.failure)])
        let reading = read(tree)
        #expect(!reading.viewIdentified && reading.viewAmbiguous && !reading.unknownLabel)
        #expect(reading.contentItemCount == nil)
        let reasons = Fixtures.reasons(classifyRepeated(reading))
        #expect(reasons.contains(.viewAmbiguous) && reasons.contains(.viewNotIdentified))
    }

    @Test func aSecondViewWithAnUnreadableLabelMakesTheViewAmbiguous() {
        var unreadableTitle = SyntheticTree.songs(rows: 0, placeholder: true)
        unreadableTitle.add(
            parent: 1, role: "AXGroup", identifier: "songs-view",
            errors: [AttributeError(attribute: "AXTitle", code: Self.failure)])
        let reading = read(unreadableTitle)
        #expect(!reading.viewIdentified && reading.viewAmbiguous && !reading.unknownLabel)
        // A differing title does not exclude the element while its description is unreadable.
        var unreadableDescription = SyntheticTree.songs(rows: 0, placeholder: true)
        unreadableDescription.add(
            parent: 1, role: "AXGroup", identifier: "songs-view", title: "Other",
            errors: [AttributeError(attribute: "AXDescription", code: Self.failure)])
        #expect(read(unreadableDescription).viewAmbiguous)
        // An ambiguous view is not verified non-empty either.
        var withRows = SyntheticTree.songs(rows: 2, placeholder: false)
        withRows.add(
            parent: 1, role: "AXGroup", identifier: "songs-view",
            errors: [AttributeError(attribute: "AXTitle", code: Self.failure)])
        #expect(classifyRepeated(read(withRows)).outcome == "indeterminate")
    }

    @Test func anAmbiguousElementNeedsNoContainer() {
        // The second element has no descendants at all, and it still cannot be excluded.
        var tree = SyntheticTree.songs(rows: 0, placeholder: true)
        let other = tree.add(
            parent: 1, role: "AXGroup", identifier: "songs-view",
            errors: [AttributeError(attribute: "AXTitle", code: Self.failure)])
        #expect(tree.parents.filter { $0 == other }.isEmpty)
        #expect(read(tree).viewAmbiguous && !read(tree).viewIdentified)
    }

    @Test func aDefinitelyMismatchedSecondViewIsExcluded() {
        var otherIdentifier = SyntheticTree.songs(rows: 0, placeholder: true)
        otherIdentifier.add(parent: 1, role: "AXGroup", identifier: "albums-view", title: "Songs")
        let reading = read(otherIdentifier)
        #expect(reading.viewIdentified && !reading.viewAmbiguous)
        // An identifier reported as absent is a definite absence.
        var noIdentifier = SyntheticTree.songs(rows: 0, placeholder: true)
        noIdentifier.add(parent: 1, role: "AXGroup", title: "Songs")
        #expect(read(noIdentifier).viewIdentified)
        // A definitely different role excludes the element whatever else is unreadable.
        var otherRole = SyntheticTree.songs(rows: 0, placeholder: true)
        otherRole.add(
            parent: 1, role: "AXList", errors: [AttributeError(attribute: "AXIdentifier", code: Self.failure)])
        #expect(read(otherRole).viewIdentified && !read(otherRole).viewAmbiguous)
    }

    @Test func anUnreadableLabelOfTheOnlyCandidateIsAmbiguityNotAnUnknownLabel() {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true, label: "Songs")
        tree.nodes[2].title = nil
        tree.nodes[2].hasTitle = false
        tree.nodes[2].errors = [AttributeError(attribute: "AXTitle", code: Self.failure)]
        let reading = read(tree)
        #expect(!reading.viewIdentified && reading.viewAmbiguous && !reading.unknownLabel)
    }

    // MARK: Application enumeration

    /// An application whose own children are a window holding the songs view and, optionally, a menu bar, and
    /// whose windows list holds `windows`, merged as the reader merges them.
    static func application(
        reportedChildren: Int?, menuBar: Bool, mergeSongsWindow: Bool, extraWindow: Bool
    ) -> SyntheticTree {
        var tree = SyntheticTree.songs(rows: 0, placeholder: true)
        tree.nodes[0].childCount = reportedChildren
        if menuBar { tree.add(parent: 0, role: "AXMenuBar") }
        var windows: [Int] = mergeSongsWindow ? [1] : []
        if extraWindow { windows.append(tree.add(parent: nil, role: "AXWindow")) }
        tree.mergedWindows[0] = windows
        return tree
    }

    @Test func aWindowAddedByTheMergeCannotStandInForAMissingChild() {
        // The application reports three children, AXChildren returns two, and one distinct window is merged.
        let tree = Self.application(reportedChildren: 3, menuBar: true, mergeSongsWindow: true, extraWindow: true)
        #expect(tree.children(of: 0).nodes.count == 3 && tree.children(of: 0).primaryCount == 2)
        let snapshot = TreeWalker.walk(roots: [0], source: tree, limits: WalkLimits())
        #expect(snapshot.childrenUnavailable && snapshot.status == .informationUnavailable)
    }

    @Test func aConsistentMergeWithADuplicateWindowIsComplete() {
        let tree = Self.application(reportedChildren: 2, menuBar: true, mergeSongsWindow: true, extraWindow: false)
        #expect(tree.children(of: 0).nodes.count == 2)
        let snapshot = TreeWalker.walk(roots: [0], source: tree, limits: WalkLimits())
        #expect(!snapshot.childrenUnavailable && snapshot.status == .complete)
    }

    @Test func aCompleteApplicationWithAnExtraWindowIsComplete() {
        let tree = Self.application(reportedChildren: 1, menuBar: false, mergeSongsWindow: true, extraWindow: true)
        #expect(tree.children(of: 0).nodes.count == 2 && tree.children(of: 0).primaryCount == 1)
        let snapshot = TreeWalker.walk(roots: [0], source: tree, limits: WalkLimits())
        #expect(snapshot.status == .complete)
        #expect(read(tree).viewIdentified)
    }

    @Test func moreChildrenThanTheEarlierCountAreIncomplete() {
        // The application reports one child, and AXChildren returns two.
        let application = Self.application(
            reportedChildren: 1, menuBar: true, mergeSongsWindow: true, extraWindow: false)
        let snapshot = TreeWalker.walk(roots: [0], source: application, limits: WalkLimits())
        #expect(snapshot.childrenUnavailable && snapshot.status == .informationUnavailable)
        // Any other node likewise.
        var table = SyntheticTree.songs(rows: 2, placeholder: false)
        table.nodes[Self.table].childCount = 1
        #expect(TreeWalker.walk(roots: [0], source: table, limits: WalkLimits()).status == .informationUnavailable)
    }
}
