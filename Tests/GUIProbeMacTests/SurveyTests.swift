import Foundation
import Testing

@testable import GUIProbeMac

@Suite struct SurveyTests {
    func facts() -> NodeFacts {
        var facts = NodeFacts()
        facts.role = "AXGroup"
        facts.subrole = "Secret Subrole"
        facts.identifier = "has space and secret"
        facts.hasIdentifier = true
        facts.title = "Secret Title"
        facts.hasTitle = true
        facts.description = "Secret Album"
        facts.hasDescription = true
        facts.childCount = 3
        facts.scrollValue = 7
        return facts
    }

    @Test func labelsOutsideTheAllowListBecomeOther() {
        let node = SurveySanitizer.node(facts(), depth: 2)
        #expect(node.titleLabel == "other")
        #expect(node.descriptionLabel == "other")
        // The raw identifier is replaced by an alias and a shape; it never appears in the node.
        #expect(node.identifierAlias == "identifier-1" && node.identifierShape == "other")
        #expect(node.hasIdentifier)
        #expect(node.subrole == "other")
        #expect(node.role == "AXGroup")
        #expect(node.scrollValue == 1)
        #expect(node.depth == 2)
    }

    @Test(arguments: ["Songs", "Recently Added", "Library", "曲", "最近追加した項目", "ライブラリ"])
    func allowListedLabelsAreKept(label: String) {
        var value = facts()
        value.title = label
        value.description = label
        let node = SurveySanitizer.node(value, depth: 0)
        #expect(node.titleLabel == label)
        #expect(node.descriptionLabel == label)
    }

    @Test func absentTextIsNotRecordedAsOther() {
        let node = SurveySanitizer.node(NodeFacts(), depth: 0)
        #expect(node.titleLabel == nil)
        #expect(node.descriptionLabel == nil)
        #expect(!node.hasTitle)
    }

    @Test(arguments: [
        ("0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0", "uuid"), ("1234", "numeric"), ("00ff00ff00ff00ff", "hexadecimal"),
        ("songs-view", "word"), ("_NS:12", "other"), ("has space", "other"), ("é", "other"), ("abc1234", "word"),
        ("abcdef12", "hexadecimal"),
    ])
    func identifierShapesAreAClosedSet(text: String, shape: String) {
        #expect(SurveySanitizer.shape(text) == shape)
    }

    @Test func equalIdentifiersShareAnAliasWithinARun() {
        var aliases = IdentifierAliases()
        #expect(aliases.alias(for: "synthetic-a") == "identifier-1")
        #expect(aliases.alias(for: "synthetic-b") == "identifier-2")
        #expect(aliases.alias(for: "synthetic-a") == "identifier-1")
        // Canonically equivalent but byte-different strings are different identifiers.
        #expect(aliases.alias(for: "caf\u{E9}") != aliases.alias(for: "cafe\u{301}"))
        #expect(aliases.values == ["synthetic-a", "synthetic-b", "caf\u{E9}", "cafe\u{301}"])
    }

    @Test func anEmptyIdentifierHasNoAlias() {
        var value = facts()
        value.identifier = ""
        let node = SurveySanitizer.node(value, depth: 0)
        #expect(node.identifierAlias == nil && node.identifierShape == nil && node.hasIdentifier)
    }

    @Test func theMappingHoldsTheRawValuesAndOmitsLongOnes() throws {
        var aliases = IdentifierAliases()
        _ = aliases.alias(for: "synthetic-a")
        let long = String(repeating: "z", count: IdentifierMapping.maximumValueBytes + 1)
        _ = aliases.alias(for: long)
        let map = IdentifierMapping(runID: "RUN", recordName: "songs.json", aliases: aliases)
        #expect(map.format == "ilibrary-gui-probe-identifier-map-1" && map.runID == "RUN")
        #expect(map.entries[0] == IdentifierMapping.Entry(alias: "identifier-1", value: "synthetic-a"))
        #expect(map.entries[1].value == nil && map.entries[1].omittedValueSHA256?.count == 64)
        let text = String(decoding: try map.json(), as: UTF8.self)
        #expect(!text.contains(long) && text.contains("synthetic-a"))
    }

    @Test func noForbiddenFieldIsEmitted() throws {
        let data = try JSONEncoder().encode(SurveySanitizer.node(facts(), depth: 1))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("Secret"))
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        let allowed: Set<String> = [
            "depth", "parent", "role", "subrole", "identifierAlias", "identifierShape", "hasIdentifier", "hasTitle",
            "titleLabel",
            "hasDescription",
            "descriptionLabel", "childCount", "rowCount", "visibleRowCount", "hasHorizontalScrollBar",
            "hasVerticalScrollBar", "scrollValue", "busy", "errors",
        ]
        #expect(Set(keys).isSubset(of: allowed))
        for forbidden in ["title", "description", "value", "position", "size", "text"] {
            #expect(!keys.contains(forbidden))
        }
    }

    @Test func theNodeLimitTruncatesTheWalk() {
        var tree = SyntheticTree()
        let root = tree.add(parent: nil, role: "AXApplication")
        for _ in 0..<9 { tree.add(parent: root, role: "AXWindow") }
        let limits = WalkLimits(maximumNodes: 4, maximumDepth: 40, timeoutSeconds: 2)
        let snapshot = TreeWalker.walk(roots: [0], source: tree, limits: limits)
        #expect(snapshot.entries.count == 4)
        #expect(snapshot.truncatedByNodeLimit)
        #expect(snapshot.status == .truncatedByLimit)
        let section = SurveySanitizer.section(snapshot, limits: limits)
        #expect(section.visitedNodeCount == 4 && section.truncatedByNodeLimit && section.nodes.count == 4)
    }

    @Test func aTreeWithinTheNodeLimitIsComplete() {
        var tree = SyntheticTree()
        let root = tree.add(parent: nil, role: "AXApplication")
        for _ in 0..<3 { tree.add(parent: root, role: "AXWindow") }
        let snapshot = TreeWalker.walk(roots: [0], source: tree, limits: WalkLimits(maximumNodes: 4))
        #expect(snapshot.entries.count == 4)
        #expect(!snapshot.truncatedByNodeLimit)
        #expect(snapshot.status == .complete)
    }

    struct CutChildren: TreeSource {
        func facts(of node: Int) -> NodeFacts { NodeFacts(role: node == 0 ? "AXTable" : "AXRow", childCount: 1) }
        func children(of node: Int) -> Children<Int> {
            node == 0 ? Children(nodes: [1], error: nil, truncated: true) : Children(nodes: [], error: nil)
        }
    }

    @Test func aBoundedCollectionReadIsCompleteOnlyWhenEveryRequestedElementArrives() {
        // Complete: a reported zero, and a full read of every requested element.
        #expect(!CollectionRead.isIncomplete(reported: 0, requested: 0, returned: 0, usable: 0))
        #expect(!CollectionRead.isIncomplete(reported: 3, requested: 3, returned: 3, usable: 3))
        // A positive count followed by a success without an array.
        #expect(CollectionRead.isIncomplete(reported: 3, requested: 3, returned: nil, usable: 0))
        // Fewer entries than requested, compared with the bounded request rather than the reported count.
        #expect(CollectionRead.isIncomplete(reported: 3, requested: 3, returned: 2, usable: 2))
        #expect(CollectionRead.isIncomplete(reported: 2_500, requested: 2_000, returned: 2_000, usable: 2_000))
        #expect(CollectionRead.isIncomplete(reported: 2_000, requested: 2_000, returned: 1_999, usable: 1_999))
        #expect(!CollectionRead.isIncomplete(reported: 2_000, requested: 2_000, returned: 2_000, usable: 2_000))
        // More entries than requested, entries that are not elements, and invalid counts.
        #expect(CollectionRead.isIncomplete(reported: 3, requested: 3, returned: 4, usable: 4))
        #expect(CollectionRead.isIncomplete(reported: 3, requested: 3, returned: 3, usable: 2))
        #expect(CollectionRead.isIncomplete(reported: -1, requested: -1, returned: 0, usable: 0))
    }

    @Test func theReaderJudgesEveryCollectionReadByItsBoundedRequest() throws {
        // A source check: the macOS reader cannot run without the accessibility service.
        let url = SourceBoundaryTests.sources.appendingPathComponent("AccessibilityReader.swift")
        let reader = try String(contentsOf: url, encoding: .utf8)
        #expect(reader.contains("guard let values else { return Children(nodes: [], error: nil, truncated: true) }"))
        #expect(reader.contains("reported: total, requested: wanted, returned: items.count, usable: nodes.count"))
        #expect(!reader.contains("error == .success ? nil : error.rawValue"))
    }

    @Test func aChildListCutAtTheLimitMakesTheWalkIncomplete() {
        let snapshot = TreeWalker.walk(roots: [0], source: CutChildren(), limits: WalkLimits())
        #expect(snapshot.truncatedByChildLimit)
        #expect(snapshot.status == .truncatedByLimit)
        #expect(SurveySanitizer.section(snapshot, limits: WalkLimits()).truncatedByChildLimit)
    }

    @Test func theDepthLimitTruncatesOnlyWhenChildrenWereLeftUnread() {
        var chain = SyntheticTree()
        var parent: Int?
        for depth in 0..<5 { parent = chain.add(parent: parent, role: "AXGroup", childCount: depth < 4 ? 1 : 0) }
        let limits = WalkLimits(maximumNodes: 100, maximumDepth: 2, timeoutSeconds: 2)
        let cut = TreeWalker.walk(roots: [0], source: chain, limits: limits)
        #expect(cut.entries.map(\.depth) == [0, 1, 2])
        #expect(cut.truncatedByDepthLimit)
        let exact = TreeWalker.walk(roots: [0], source: chain, limits: WalkLimits(maximumNodes: 100, maximumDepth: 4))
        #expect(exact.entries.count == 5)
        #expect(!exact.truncatedByDepthLimit)
        #expect(exact.status == .complete)
    }

    @Test func attributeErrorsAreCountedByCodeAndATimeoutIsDistinguished() {
        var tree = SyntheticTree()
        let root = tree.add(
            parent: nil, role: "AXApplication", errors: [AttributeError(attribute: "AXTitle", code: -25202)])
        tree.add(parent: root, role: "AXWindow")
        var snapshot = TreeWalker.walk(roots: [0], source: tree, limits: WalkLimits())
        #expect(snapshot.errorCountsByCode == [-25202: 1])
        #expect(snapshot.status == .attributeError)
        tree.childErrors[root] = accessibilityCannotComplete
        snapshot = TreeWalker.walk(roots: [0], source: tree, limits: WalkLimits())
        #expect(snapshot.status == .timedOut)
        let section = SurveySanitizer.section(snapshot, limits: WalkLimits())
        #expect(section.errorCountsByCode["-25204"] == 1)
        #expect(section.nodes[0].errors.contains(AttributeError(attribute: "AXChildren", code: -25204)))
    }

    @Test func anEmptyWalkIsNotFound() {
        let snapshot = TreeWalker.walk(roots: [], source: SyntheticTree(), limits: WalkLimits())
        #expect(snapshot.status == .notFound)
    }

    @Test func theDefaultLimitsAreTheSpecifiedOnes() {
        let limits = WalkLimits()
        #expect(limits.maximumNodes == 5_000 && limits.maximumDepth == 40 && limits.timeoutSeconds == 2)
    }
}
