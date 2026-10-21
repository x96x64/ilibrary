// Foundation-only tree traversal and view extraction. The tree is reached through the `TreeSource` protocol, so
// that the traversal and the extraction are tested on synthetic trees and the macOS reader only supplies facts.
import Foundation

/// The accessibility error code for a request that did not complete in time.
let accessibilityCannotComplete: Int32 = -25204

/// The accessibility error code for an element that no longer exists.
let accessibilityInvalidElement: Int32 = -25202

struct AttributeError: Codable, Equatable, Sendable {
    var attribute: String
    var code: Int32
}

/// What a source reports about one node. The text fields are raw and are compared or sanitized, never stored.
struct NodeFacts: Equatable, Sendable {
    var role: String?
    var subrole: String?
    var identifier: String?
    var title: String?
    var description: String?
    var hasIdentifier = false
    var hasTitle = false
    var hasDescription = false
    var childCount: Int?
    var rowCount: Int?
    var visibleRowCount: Int?
    var hasHorizontalScrollBar: Bool?
    var hasVerticalScrollBar: Bool?
    var scrollValue: Double?
    var busy: Bool?
    var errors: [AttributeError] = []
}

struct Children<Node> {
    var nodes: [Node]
    var error: Int32?
}

protocol TreeSource {
    associatedtype Node
    func facts(of node: Node) -> NodeFacts
    func children(of node: Node) -> Children<Node>
}

struct WalkLimits: Equatable, Sendable {
    var maximumNodes = 5_000
    var maximumDepth = 40
    var timeoutSeconds = 2.0
}

struct TreeEntry<Node> {
    var node: Node
    var depth: Int
    var parent: Int?
    var facts: NodeFacts
}

struct TreeSnapshot<Node> {
    var entries: [TreeEntry<Node>] = []
    var truncatedByNodeLimit = false
    var truncatedByDepthLimit = false
    var errorCountsByCode: [Int32: Int] = [:]

    /// Whether the root element itself reported that it is invalid, as after the application has quit.
    var applicationInvalid: Bool {
        entries.first?.facts.errors.contains { $0.code == accessibilityInvalidElement } ?? false
    }

    var timedOut: Bool { errorCountsByCode[accessibilityCannotComplete] != nil }

    var status: TreeStatus {
        if entries.isEmpty { return .notFound }
        if timedOut { return .timedOut }
        if truncatedByNodeLimit || truncatedByDepthLimit { return .truncatedByLimit }
        if !errorCountsByCode.isEmpty { return .attributeError }
        return .complete
    }
}

enum TreeWalker {
    /// A breadth-first walk bounded by node count and depth. A node at the depth limit is not expanded, and the
    /// walk is marked truncated only when such a node has children.
    static func walk<Source: TreeSource>(roots: [Source.Node], source: Source, limits: WalkLimits)
        -> TreeSnapshot<Source.Node>
    {
        var snapshot = TreeSnapshot<Source.Node>()
        var queue = roots.map { (node: $0, depth: 0, parent: Int?.none) }
        var head = 0
        while head < queue.count {
            let item = queue[head]
            head += 1
            if snapshot.entries.count >= limits.maximumNodes {
                snapshot.truncatedByNodeLimit = true
                break
            }
            var facts = source.facts(of: item.node)
            let index = snapshot.entries.count
            if item.depth >= limits.maximumDepth {
                if (facts.childCount ?? 0) > 0 { snapshot.truncatedByDepthLimit = true }
            } else {
                let kids = source.children(of: item.node)
                if let code = kids.error, !facts.errors.contains(where: { $0.attribute == "AXChildren" }) {
                    facts.errors.append(AttributeError(attribute: "AXChildren", code: code))
                }
                for kid in kids.nodes { queue.append((node: kid, depth: item.depth + 1, parent: index)) }
            }
            for error in facts.errors { snapshot.errorCountsByCode[error.code, default: 0] += 1 }
            snapshot.entries.append(TreeEntry(node: item.node, depth: item.depth, parent: item.parent, facts: facts))
        }
        return snapshot
    }
}

enum ViewExtractor {
    private static let scrollAreaRole = "AXScrollArea"
    private static let windowRole = "AXWindow"

    private static func matches(_ facts: NodeFacts, _ rule: ElementRule, includeLabel: Bool) -> Bool {
        guard facts.role == rule.role else { return false }
        if let subrole = rule.subrole, facts.subrole != subrole { return false }
        if let identifier = rule.identifier, facts.identifier != identifier { return false }
        if includeLabel, let label = rule.label, facts.title != label, facts.description != label { return false }
        return true
    }

    private static func isDescendant<Node>(_ index: Int, of ancestor: Int, in entries: [TreeEntry<Node>]) -> Bool {
        var current = entries[index].parent
        while let parent = current {
            if parent == ancestor { return true }
            current = entries[parent].parent
        }
        return false
    }

    /// Extracts one reading of one view from a snapshot. Nothing is inferred from absence alone: a flag that
    /// positive evidence would set stays nil when the evidence cannot be complete.
    static func reading<Node>(
        of rule: ViewRule, in snapshot: TreeSnapshot<Node>, elapsed: Double
    ) -> ViewReading {
        let entries = snapshot.entries
        let status = snapshot.status
        var reading = ViewReading(
            elapsed: elapsed, treeStatus: status, viewIdentified: false, containerFound: false, containerRole: nil,
            contentItemCount: nil, totalItemCount: nil, scrollable: nil, busy: nil, placeholderPresent: nil,
            unexpectedStructure: false, unknownLabel: false)
        let candidates = entries.indices.filter { matches(entries[$0].facts, rule.identification, includeLabel: false) }
        let matched = candidates.filter { matches(entries[$0].facts, rule.identification, includeLabel: true) }
        if rule.identification.label != nil && matched.isEmpty && !candidates.isEmpty { reading.unknownLabel = true }
        guard matched.count == 1, let view = matched.first else {
            return reading
        }
        reading.viewIdentified = true
        let inside = entries.indices.filter { isDescendant($0, of: view, in: entries) }
        let complete = status == .complete

        let containers = inside.filter { entries[$0].facts.role == rule.containerRole }
        reading.containerFound = !containers.isEmpty
        if containers.count > 1 { reading.unexpectedStructure = true }
        if let container = containers.first, containers.count == 1 {
            reading.containerRole = rule.containerRole
            reading.contentItemCount =
                inside.filter {
                    isDescendant($0, of: container, in: entries) && entries[$0].facts.role == rule.contentRole
                }.count
            if rule.rowsComplete { reading.totalItemCount = entries[container].facts.rowCount }
            // Scrollability is positive only when a scroll area that contains the container, up to the window,
            // reports no vertical scroll bar. The container's own flag can only show scrollability, and an
            // unsupported or unreadable attribute stays unknown.
            var areaFlags: [Bool?] = []
            var scrollable = entries[container].facts.hasVerticalScrollBar == true
            var cursor = entries[container].parent
            while let ancestor = cursor {
                let facts = entries[ancestor].facts
                if facts.role == scrollAreaRole {
                    areaFlags.append(facts.hasVerticalScrollBar)
                    if facts.hasVerticalScrollBar == true { scrollable = true }
                }
                if facts.role == windowRole { break }
                cursor = entries[ancestor].parent
            }
            if scrollable {
                reading.scrollable = true
            } else if !areaFlags.isEmpty && areaFlags.allSatisfy({ $0 == false }) {
                reading.scrollable = false
            }
        }

        if let placeholder = rule.placeholder {
            let found = inside.contains { matches(entries[$0].facts, placeholder, includeLabel: true) }
            reading.placeholderPresent = found ? true : (complete ? false : nil)
        }
        var signals: [Bool] = []
        if let busy = entries[view].facts.busy { signals.append(busy) }
        if let loading = rule.loading {
            let found = inside.contains { matches(entries[$0].facts, loading, includeLabel: true) }
            if found {
                signals.append(true)
            } else if complete {
                signals.append(false)
            }
        }
        if signals.contains(true) {
            reading.busy = true
        } else if !signals.isEmpty {
            reading.busy = false
        }
        return reading
    }
}
