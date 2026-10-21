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
        #expect(node.identifier == nil)
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

    @Test(arguments: [("songs-view", true), ("a.b_c-1", true), ("", false), ("has space", false), ("é", false)])
    func identifiersFollowThePattern(text: String, kept: Bool) {
        #expect((SurveySanitizer.identifier(text) != nil) == kept)
    }

    @Test func theIdentifierLengthIsBounded() {
        #expect(SurveySanitizer.identifier(String(repeating: "a", count: 64)) != nil)
        #expect(SurveySanitizer.identifier(String(repeating: "a", count: 65)) == nil)
    }

    @Test func noForbiddenFieldIsEmitted() throws {
        let data = try JSONEncoder().encode(SurveySanitizer.node(facts(), depth: 1))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("Secret"))
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        let allowed: Set<String> = [
            "depth", "role", "subrole", "identifier", "hasIdentifier", "hasTitle", "titleLabel", "hasDescription",
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
