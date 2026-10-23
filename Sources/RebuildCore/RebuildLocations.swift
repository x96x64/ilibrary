import Foundation

/// Path comparison that is component-wise on Unicode NFC-normalized, case-folded components. It never compares raw
/// string prefixes, so "/a/bc" is not inside "/a/b", and "/a/B" and "/a/b" are equal.
enum PathKey {
    enum Relation: Equatable, Sendable {
        case equal
        case firstInsideSecond
        case firstContainsSecond
        case disjoint
    }

    static func fold(_ component: String) -> String {
        component.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
            .precomposedStringWithCanonicalMapping
    }

    static func components(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map { fold(String($0)) }
    }

    /// A single string that is equal for two paths exactly when their components are equal after folding.
    static func key(_ path: String) -> String { "/" + components(path).joined(separator: "/") }

    static func relation(_ first: String, _ second: String) -> Relation {
        let a = components(first)
        let b = components(second)
        if a == b { return .equal }
        if a.count > b.count && a.starts(with: b) { return .firstInsideSecond }
        if b.count > a.count && b.starts(with: a) { return .firstContainsSecond }
        return .disjoint
    }

    /// The reason for which `path` is not an absolute standardized path, or nil.
    static func invalidReason(_ path: String) -> String? {
        if path.isEmpty { return "the path is empty" }
        if path.utf8.contains(0) { return "the path contains a NUL character" }
        if !path.hasPrefix("/") { return "the path is not absolute" }
        if path == "/" { return nil }
        let parts = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains("") { return "the path has an empty component or a trailing slash" }
        if parts.contains(".") || parts.contains("..") { return "the path is not standardized" }
        return nil
    }
}

/// A reason for which a set of rebuild locations is refused.
public enum LocationRefusal: Equatable, Sendable, CustomStringConvertible {
    case invalidPath(label: String, path: String, reason: String)
    case noSources
    /// Two locations are equal or one contains the other. `first` and `second` are labelled paths.
    case overlap(first: String, second: String, relationship: String)
    case symbolicLink(label: String, path: String, link: String)
    case unreadable(label: String, path: String, reason: String)

    public var description: String {
        switch self {
        case .invalidPath(let label, let path, let reason): "\(label) '\(path)': \(reason)"
        case .noSources: "no source root is selected"
        case .overlap(let first, let second, let relationship): "\(first) and \(second) \(relationship)"
        case .symbolicLink(let label, let path, let link):
            "\(label) '\(path)' passes through the symbolic link '\(link)'"
        case .unreadable(let label, let path, let reason): "\(label) '\(path)' cannot be examined: \(reason)"
        }
    }
}

/// The locations of a rebuild: one or more source roots, the Music media folder, the backup root, the
/// restoration-test directory, the staging directory, and the workspace directory.
///
/// Every path must be absolute and standardized (no empty, "." or ".." component and no trailing slash).
public struct RebuildLocations: Codable, Equatable, Sendable {
    public var sources: [String]
    public var mediaFolder: String
    public var backupRoot: String
    public var restorationDirectory: String
    public var stagingDirectory: String
    public var workspaceDirectory: String

    public init(
        sources: [String], mediaFolder: String, backupRoot: String, restorationDirectory: String,
        stagingDirectory: String, workspaceDirectory: String
    ) {
        self.sources = sources
        self.mediaFolder = mediaFolder
        self.backupRoot = backupRoot
        self.restorationDirectory = restorationDirectory
        self.stagingDirectory = stagingDirectory
        self.workspaceDirectory = workspaceDirectory
    }

    /// Every location with a label for messages.
    var labeled: [(label: String, path: String)] {
        sources.enumerated().map { ("source root \($0.offset + 1)", $0.element) } + [
            ("media folder", mediaFolder), ("backup root", backupRoot),
            ("restoration-test directory", restorationDirectory), ("staging directory", stagingDirectory),
            ("workspace directory", workspaceDirectory),
        ]
    }

    /// Checks the locations lexically and returns every reason for refusal; an empty result means they are valid.
    ///
    /// Sources equal to or nested inside each other are refused. The backup, restoration-test, staging, and
    /// workspace directories must not equal, lie inside, or contain any other location, including each source and
    /// the media folder. A source equal to or inside the media folder is permitted, because the selected files are
    /// the library's files; a media folder lying strictly inside a source is refused. Comparison is by normalized,
    /// case-folded components. Symbolic links are not examined here; see `symbolicLinkRefusals`.
    public func validate() -> [LocationRefusal] {
        var refusals: [LocationRefusal] = []
        if sources.isEmpty { refusals.append(.noSources) }
        var valid: [(label: String, path: String)] = []
        for item in labeled {
            if let reason = PathKey.invalidReason(item.path) {
                refusals.append(.invalidPath(label: item.label, path: item.path, reason: reason))
            } else {
                valid.append(item)
            }
        }
        func isSource(_ label: String) -> Bool { label.hasPrefix("source root") }
        func describe(_ item: (label: String, path: String)) -> String { "\(item.label) '\(item.path)'" }
        for i in valid.indices {
            for j in valid.indices where j > i {
                let first = valid[i]
                let second = valid[j]
                let relation = PathKey.relation(first.path, second.path)
                let text: String
                switch relation {
                case .disjoint: continue
                case .equal: text = "are equal after normalization and case folding"
                case .firstInsideSecond: text = "overlap: the first lies inside the second"
                case .firstContainsSecond: text = "overlap: the first contains the second"
                }
                // A source equal to or inside the media folder holds the library's own files.
                if isSource(first.label) && second.label == "media folder" && relation != .firstContainsSecond {
                    continue
                }
                refusals.append(.overlap(first: describe(first), second: describe(second), relationship: text))
            }
        }
        return refusals
    }

    /// Refuses a symbolic link at any existing component of any location. `status` is an lstat-like function; it
    /// must throw `FileStatusError.missing` for a path that does not exist, after which deeper components are not
    /// examined. Locations that are lexically invalid are skipped, since `validate` reports them.
    public func symbolicLinkRefusals(status: (String) throws -> FileStatus) -> [LocationRefusal] {
        var refusals: [LocationRefusal] = []
        for item in labeled where PathKey.invalidReason(item.path) == nil {
            var current = ""
            for part in item.path.split(separator: "/") {
                current += "/" + part
                do {
                    if try status(current).kind == .symbolicLink {
                        refusals.append(.symbolicLink(label: item.label, path: item.path, link: current))
                        break
                    }
                } catch FileStatusError.missing {
                    break
                } catch {
                    refusals.append(
                        .unreadable(label: item.label, path: item.path, reason: String(describing: error)))
                    break
                }
            }
        }
        return refusals
    }
}
