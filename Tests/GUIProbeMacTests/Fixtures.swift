// Synthetic fixtures for the GUI-emptiness probe tests. Nothing here reads Music, a preference, or an
// accessibility interface.
import Foundation

@testable import GUIProbeMac

enum Fixtures {
    static let macOS = "Version 99.0 (Build 99A1)"
    static let music = "99.1"
    static let locale = "en_US"

    static var songsRule: ViewRule {
        ViewRule(
            identification: ElementRule(role: "AXGroup", identifier: "songs-view", label: "Songs"),
            containerRole: "AXTable", contentRole: "AXRow", rowsComplete: true,
            placeholder: ElementRule(role: "AXStaticText", identifier: "empty-state"),
            loading: ElementRule(role: "AXProgressIndicator"))
    }

    static var recentRule: ViewRule {
        var rule = songsRule
        rule.identification = ElementRule(role: "AXGroup", identifier: "recent-view", label: "Recently Added")
        return rule
    }

    static func profile(stability: Stability? = Stability(minimumReadings: 3, minimumSpanSeconds: 4))
        -> InterfaceProfile
    {
        InterfaceProfile(
            musicVersion: music, macOSVersion: macOS, locale: locale, songs: songsRule, recentlyAdded: recentRule,
            stability: stability)
    }

    static var context: ObservedContext { ObservedContext(macOSVersion: macOS, musicVersion: music, locale: locale) }

    static var preflight: Preflight {
        Preflight(
            operatorConfirmedSeparateTestUser: true, operatorConfirmedSyntheticLibrary: true,
            operatorConfirmedNoAppleAccount: true, operatorConfirmedNoCloudLibrary: true,
            processUserMatchesTestUserPattern: true, accessibilityTrusted: true, musicProcess: .exactlyOne,
            macOSVersionPresent: true, musicVersionPresent: true, profileSupplied: true)
    }

    /// A complete, positively empty reading.
    static func empty(at elapsed: Double) -> ViewReading {
        ViewReading(
            elapsed: elapsed, treeStatus: .complete, viewIdentified: true, containerFound: true,
            containerRole: "AXTable", contentItemCount: 0, totalItemCount: 0, scrollable: false, busy: false,
            placeholderPresent: true, unexpectedStructure: false, unknownLabel: false)
    }

    static var emptyReadings: [ViewReading] { [empty(at: 0), empty(at: 3), empty(at: 6)] }

    static func classify(
        _ readings: [ViewReading], view: ViewKind = .songs, preflight: Preflight = Fixtures.preflight,
        context: ObservedContext = Fixtures.context, profile: InterfaceProfile? = Fixtures.profile(),
        inventory: Int? = 0
    ) -> Verdict {
        Classifier.classify(
            readings: readings, view: view, preflight: preflight, context: context, profile: profile,
            inventory: InventoryEvidence(fileTrackCount: inventory))
    }

    static func reasons(_ verdict: Verdict) -> [Reason] {
        if case .indeterminate(let reasons) = verdict { return reasons }
        return []
    }
}

/// A synthetic accessibility tree: facts per node and the parent of each node.
struct SyntheticTree: TreeSource {
    var nodes: [NodeFacts] = []
    var parents: [Int?] = []
    var childErrors: [Int: Int32] = [:]
    /// Nodes whose child count is reported as unknown. Every other node reports the number of its synthetic
    /// children unless a count is given explicitly; a real interface need not supply such counts.
    var unknownChildCounts: Set<Int> = []
    /// Nodes whose child collection cannot be enumerated.
    var unavailableChildren: Set<Int> = []

    @discardableResult
    mutating func add(
        parent: Int?, role: String, subrole: String? = nil, identifier: String? = nil, title: String? = nil,
        description: String? = nil, rowCount: Int? = nil, verticalScrollBar: Bool? = nil, busy: Bool? = nil,
        childCount: Int? = nil, errors: [AttributeError] = []
    ) -> Int {
        var facts = NodeFacts()
        facts.role = role
        facts.subrole = subrole
        facts.identifier = identifier
        facts.hasIdentifier = identifier != nil
        facts.title = title
        facts.hasTitle = title != nil
        facts.description = description
        facts.hasDescription = description != nil
        facts.rowCount = rowCount
        facts.hasVerticalScrollBar = verticalScrollBar
        facts.busy = busy
        facts.childCount = childCount
        facts.errors = errors
        nodes.append(facts)
        parents.append(parent)
        return nodes.count - 1
    }

    func facts(of node: Int) -> NodeFacts {
        var facts = nodes[node]
        if unknownChildCounts.contains(node) {
            facts.childCount = nil
        } else if facts.childCount == nil {
            facts.childCount = parents.filter { $0 == node }.count
        }
        return facts
    }

    func children(of node: Int) -> Children<Int> {
        if unavailableChildren.contains(node) { return Children(nodes: [], error: nil, unavailable: true) }
        return Children(nodes: parents.indices.filter { parents[$0] == node }, error: childErrors[node])
    }

    /// An application with one window holding the Songs view: a scroll area, a table with `rows` rows, and
    /// optionally the empty-state element.
    static func songs(
        rows: Int, placeholder: Bool, label: String = "Songs", busy: Bool? = false, verticalScrollBar: Bool? = false,
        totalRows: Int? = nil
    ) -> SyntheticTree {
        var tree = SyntheticTree()
        let app = tree.add(parent: nil, role: "AXApplication")
        let window = tree.add(parent: app, role: "AXWindow")
        let view = tree.add(parent: window, role: "AXGroup", identifier: "songs-view", title: label, busy: busy)
        let area = tree.add(parent: view, role: "AXScrollArea", verticalScrollBar: verticalScrollBar)
        let table = tree.add(parent: area, role: "AXTable", rowCount: totalRows ?? rows, verticalScrollBar: false)
        for _ in 0..<rows { tree.add(parent: table, role: "AXRow") }
        if placeholder { tree.add(parent: view, role: "AXStaticText", identifier: "empty-state") }
        return tree
    }
}
