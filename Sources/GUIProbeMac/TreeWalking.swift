// Foundation-only tree traversal and view extraction. The tree is reached through the `TreeSource` protocol, so
// that the traversal and the extraction are tested on synthetic trees and the macOS reader only supplies facts.
import Foundation

/// The accessibility error code for a request that did not complete in time.
let accessibilityCannotComplete: Int32 = -25204

/// The accessibility error code for an element that no longer exists.
let accessibilityInvalidElement: Int32 = -25202

/// A probe-defined code, outside the accessibility error range, for a successful count that is negative.
let invalidCountCode: Int32 = -1

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
    var hasSubrole = false
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

    /// Whether a text attribute could not be read: its request failed, or it returned a value that is not text.
    /// An attribute reported as no value or unsupported is absent, which is a definite absence and not unreadable.
    func isUnreadable(_ attribute: String, value: String?, returned: Bool) -> Bool {
        (returned && value == nil) || errors.contains { $0.attribute == attribute }
    }
}

struct Children<Node> {
    var nodes: [Node]
    var error: Int32?
    /// True when the node reported more children than were returned, so that the walk is incomplete.
    var truncated = false
    /// True when the collection could not be established at all, for example because its count was reported as
    /// no value or unsupported; this is never evidence that the node has no children.
    var unavailable = false
    /// The number of nodes that the node's own child collection returned before another collection, such as the
    /// windows of an application, was merged into the list; nil when nothing was merged. The child count read with
    /// the node's facts describes that collection alone, so it is compared with this number.
    var primaryCount: Int? = nil
}

/// The completeness of one bounded read of a collection attribute: the count that the element reported, the
/// count requested after the per-call limit, the count of entries returned (nil when no array came back), and the
/// count of usable elements among them. The count and the copy are separate requests and not an atomic snapshot,
/// so any disagreement is incompleteness and never evidence of an empty collection.
enum CollectionRead {
    static func isIncomplete(reported: Int, requested: Int, returned: Int?, usable: Int) -> Bool {
        if reported < 0 || requested < 0 || reported > requested { return true }
        guard let returned else { return requested > 0 }
        return returned != requested || usable != returned
    }
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
    var truncatedByChildLimit = false
    /// A child collection or count that could not be established, or that disagreed between two reads.
    var childrenUnavailable = false
    /// A node whose role could not be read as a string.
    var roleUnknown = false
    var errorCountsByCode: [Int32: Int] = [:]

    /// Whether the root element itself reported that it is invalid, as after the application has quit.
    var applicationInvalid: Bool {
        entries.first?.facts.errors.contains { $0.code == accessibilityInvalidElement } ?? false
    }

    var timedOut: Bool { errorCountsByCode[accessibilityCannotComplete] != nil }

    var status: TreeStatus {
        if entries.isEmpty { return .notFound }
        if timedOut { return .timedOut }
        if truncatedByNodeLimit || truncatedByDepthLimit || truncatedByChildLimit { return .truncatedByLimit }
        if childrenUnavailable || roleUnknown { return .informationUnavailable }
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
            // A role that cannot be read could hide a content item or a loading indicator.
            if facts.role == nil { snapshot.roleUnknown = true }
            if item.depth >= limits.maximumDepth {
                // Only a child count positively reported as zero shows that nothing lies beyond the limit.
                if facts.childCount != 0 { snapshot.truncatedByDepthLimit = true }
            } else {
                let kids = source.children(of: item.node)
                if let code = kids.error, !facts.errors.contains(where: { $0.attribute == "AXChildren" }) {
                    facts.errors.append(AttributeError(attribute: "AXChildren", code: code))
                }
                if kids.truncated { snapshot.truncatedByChildLimit = true }
                // An unknown child count, an unavailable collection, or a number of children that differs in either
                // direction from the earlier count cannot show that nothing is missing. For an application, the
                // count is compared with its own children before its windows were merged, so that a window added
                // by the merge cannot stand in for a child that the enumeration omitted.
                if kids.unavailable || facts.childCount == nil { snapshot.childrenUnavailable = true }
                let enumerated = kids.primaryCount ?? kids.nodes.count
                if let reported = facts.childCount, !kids.truncated, kids.error == nil, enumerated != reported {
                    snapshot.childrenUnavailable = true
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

    /// Whether an element satisfies a rule: definitely, definitely not, or possibly, when an attribute that the
    /// rule requires could not be read and no other requirement definitely fails.
    enum RuleMatch {
        case match
        case mismatch
        case uncertain
    }

    private static func condition(_ value: String?, equals expected: String, unreadable: Bool) -> RuleMatch {
        if value == expected { return .match }
        return unreadable ? .uncertain : .mismatch
    }

    static func match(_ facts: NodeFacts, _ rule: ElementRule, includeLabel: Bool) -> RuleMatch {
        var conditions: [RuleMatch] = [facts.role.map { $0 == rule.role ? .match : .mismatch } ?? .uncertain]
        if let subrole = rule.subrole {
            conditions.append(
                condition(
                    facts.subrole, equals: subrole,
                    unreadable: facts.isUnreadable("AXSubrole", value: facts.subrole, returned: facts.hasSubrole)))
        }
        if let identifier = rule.identifier {
            conditions.append(
                condition(
                    facts.identifier, equals: identifier,
                    unreadable: facts.isUnreadable(
                        "AXIdentifier", value: facts.identifier, returned: facts.hasIdentifier)))
        }
        if includeLabel, let label = rule.label {
            // The label may be carried by the title or by the description, so either one matching satisfies it,
            // and an unreadable one leaves it possible while the other does not match.
            let title = condition(
                facts.title, equals: label,
                unreadable: facts.isUnreadable("AXTitle", value: facts.title, returned: facts.hasTitle))
            let description = condition(
                facts.description, equals: label,
                unreadable: facts.isUnreadable(
                    "AXDescription", value: facts.description, returned: facts.hasDescription))
            if title == .match || description == .match {
                conditions.append(.match)
            } else {
                conditions.append(title == .uncertain || description == .uncertain ? .uncertain : .mismatch)
            }
        }
        if conditions.contains(.mismatch) { return .mismatch }
        if conditions.contains(.uncertain) { return .uncertain }
        return .match
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
        let outcomes = entries.map { match($0.facts, rule.identification, includeLabel: true) }
        let matched = entries.indices.filter { outcomes[$0] == .match }
        // A definite match is unique only when every other element is definitely excluded: an element that could
        // satisfy the rule but has an unreadable attribute could be the view, whether or not it has a container.
        reading.viewAmbiguous = outcomes.contains(.uncertain)
        let candidates = entries.indices.filter {
            match(entries[$0].facts, rule.identification, includeLabel: false) == .match
        }
        if rule.identification.label != nil && matched.isEmpty
            && candidates.contains(where: { outcomes[$0] == .mismatch })
        {
            reading.unknownLabel = true
        }
        guard matched.count == 1, !reading.viewAmbiguous, let view = matched.first else {
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
            // A vertical scroll bar on the container or on a scroll area that contains it, up to the window, shows
            // that the view can scroll. A scroll bar reported as no value, unsupported, or unreadable shows only
            // that no scroll-bar element was returned, not that the view cannot scroll, so scrollability is
            // otherwise unknown. No extracted reading therefore reports a view as not scrollable, and a candidate
            // for emptiness cannot arise from extracted readings until a reviewed change defines positive evidence.
            var scrollable = entries[container].facts.hasVerticalScrollBar == true
            var cursor = entries[container].parent
            while let ancestor = cursor {
                let facts = entries[ancestor].facts
                if facts.role == scrollAreaRole && facts.hasVerticalScrollBar == true { scrollable = true }
                if facts.role == windowRole { break }
                cursor = entries[ancestor].parent
            }
            if scrollable { reading.scrollable = true }
        }

        if let placeholder = rule.placeholder {
            let found = inside.map { match(entries[$0].facts, placeholder, includeLabel: true) }
            if found.contains(.match) {
                reading.placeholderPresent = true
            } else if complete && !found.contains(.uncertain) {
                reading.placeholderPresent = false
            }
        }
        var signals: [Bool] = []
        var loadingUncertain = false
        if let busy = entries[view].facts.busy { signals.append(busy) }
        if let loading = rule.loading {
            let found = inside.map { match(entries[$0].facts, loading, includeLabel: true) }
            if found.contains(.match) {
                signals.append(true)
            } else if found.contains(.uncertain) {
                // An element that could be the loading indicator is not evidence of loading, but it prevents a
                // reading of not busy, whatever the view's own busy attribute reports.
                loadingUncertain = true
            } else if complete {
                signals.append(false)
            }
        }
        if signals.contains(true) {
            reading.busy = true
        } else if !signals.isEmpty && !loadingUncertain {
            reading.busy = false
        }
        return reading
    }
}
