import Foundation

/// One inventoried file: its normalized relative path, size, digest, and timestamps.
public struct FileRecord: Codable, Equatable, Sendable {
    /// NFC-normalized, "/"-separated, without a leading slash and without "." or ".." components.
    public let path: String
    public let size: UInt64
    public let sha256: SHA256Digest
    public let modification: FileTimestamp
    public let creation: FileTimestamp?

    public init(path: String, size: UInt64, sha256: SHA256Digest, modification: FileTimestamp, creation: FileTimestamp?)
    {
        self.path = path
        self.size = size
        self.sha256 = sha256
        self.modification = modification
        self.creation = creation
    }
}

/// The reason two paths cannot coexist in one inventory.
public enum PathCollisionKind: String, Equatable, Sendable {
    /// The paths are identical after Unicode NFC normalization.
    case normalization
    /// The paths differ only in letter case after NFC normalization.
    case caseFolding
}

/// The refusals of building an inventory or verifying a copy.
public enum FileInventoryError: Error, Equatable, Sendable {
    case rootMissing(path: String)
    case rootNotDirectory(path: String)
    case rootIsSymbolicLink(path: String)
    /// The relative path is empty or has an empty or "." component.
    case invalidPath(path: String)
    /// The relative path is absolute or has a ".." component.
    case escapesRoot(path: String)
    case missing(path: String)
    /// The file, or a directory between the root and the file, is a symbolic link; `path` names the link.
    case symbolicLink(path: String)
    case notRegularFile(path: String, kind: FileKind)
    case collision(path: String, other: String, kind: PathCollisionKind)
    /// The size or modification time changed while the file was hashed.
    case unstable(path: String)
    case unreadable(path: String, reason: String)
}

/// The kind of a difference between an expected record and a copy.
public enum VerificationMismatchKind: String, Equatable, Sendable {
    case missing
    case notRegularFile
    case symbolicLink
    case sizeDiffers
    case digestDiffers
    case modificationTimeDiffers
    case creationTimeDiffers
    /// The expected record has a creation time but the copy reports none.
    case creationTimeUnavailable
    case unstable
    case unreadable
    /// An .m4a file present in the copy that is not in the expected set.
    case extraFile
}

public struct VerificationMismatch: Equatable, Sendable {
    public let path: String
    public let kind: VerificationMismatchKind
    public let detail: String
}

/// The outcome of verifying a copy: a success only when there is no mismatch.
public struct VerificationReport: Equatable, Sendable {
    public let policy: TimestampPolicy
    public let checkedCount: Int
    public let mismatches: [VerificationMismatch]
    public var isSuccess: Bool { mismatches.isEmpty }
}

/// A sorted inventory of files under a root directory.
public struct FileInventory: Equatable, Sendable {
    public let records: [FileRecord]

    /// Inventories the selected relative paths under `root`. Nothing is returned unless every path passes every check.
    public init(root: URL, selecting relativePaths: [String]) throws {
        self = try FileInventory.build(root: root, relativePaths: relativePaths, afterHash: nil)
    }

    /// Inventories all regular files under `root` whose extension is in `extensions` (case-insensitive, without the
    /// dot), found recursively. Entries whose name begins with "." are skipped. Every symbolic link met during the
    /// walk is refused, so that nothing is silently omitted.
    public init(root: URL, extensions: Set<String>) throws {
        try FileInventory.checkRoot(root)
        let wanted = FileInventory.normalizedExtensions(extensions)
        var found: [String] = []
        if let problem = try FileInventory.walk(root: root.path, prefix: "", extensions: wanted, into: &found) {
            throw problem
        }
        self = try FileInventory.build(root: root, relativePaths: found, afterHash: nil)
    }

    private init(records: [FileRecord]) { self.records = records }

    // MARK: Path rules

    /// Validates a relative path and returns its components; refuses absolute paths and ".." components as escaping.
    static func components(of path: String) throws -> [String] {
        if path.hasPrefix("/") { throw FileInventoryError.escapesRoot(path: path) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.contains("..") { throw FileInventoryError.escapesRoot(path: path) }
        if path.isEmpty || parts.contains("") || parts.contains(".") || path.utf8.contains(0) {
            throw FileInventoryError.invalidPath(path: path)
        }
        return parts
    }

    static func normalize(_ path: String) -> String { path.precomposedStringWithCanonicalMapping }

    /// Returns the first pair of paths that collide after NFC normalization or after case folding, or nil.
    /// Identical paths collide as `normalization`.
    public static func findCollision(in paths: [String]) -> (path: String, other: String, kind: PathCollisionKind)? {
        var normalized: [String: String] = [:]
        var folded: [String: String] = [:]
        for path in paths {
            let nfc = normalize(path)
            if let earlier = normalized[nfc] { return (path, earlier, .normalization) }
            normalized[nfc] = path
            let key = normalize(nfc.lowercased())
            if let earlier = folded[key] { return (path, earlier, .caseFolding) }
            folded[key] = path
        }
        return nil
    }

    /// True when a file did not change while it was hashed.
    static func isStable(before: FileStatus, after: FileStatus, hashedBytes: UInt64) -> Bool {
        before.size == after.size && before.modification == after.modification && before.inode == after.inode
            && before.device == after.device && hashedBytes == after.size
    }

    private static func normalizedExtensions(_ extensions: Set<String>) -> Set<String> {
        Set(extensions.map { $0.drop(while: { $0 == "." }).lowercased() })
    }

    private static func hasExtension(_ name: String, in extensions: Set<String>) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        return extensions.contains(name[name.index(after: dot)...].lowercased())
    }

    // MARK: Filesystem checks

    private static func checkRoot(_ root: URL) throws {
        let path = root.path
        let status: FileStatus
        do {
            status = try FileStatus.read(atPath: path)
        } catch FileStatusError.missing {
            throw FileInventoryError.rootMissing(path: path)
        } catch {
            throw FileInventoryError.unreadable(path: path, reason: String(describing: error))
        }
        if status.kind == .symbolicLink { throw FileInventoryError.rootIsSymbolicLink(path: path) }
        if status.kind != .directory { throw FileInventoryError.rootNotDirectory(path: path) }
    }

    enum PathProblem: Error, Equatable {
        case missing
        case symbolicLink(at: String)
        case notRegular(FileKind)
        case unreadable(String)
    }

    /// Checks every component with lstat and returns the status of the final regular file, or the problem found.
    static func resolve(rootPath: String, components: [String]) -> Result<FileStatus, PathProblem> {
        var current = rootPath
        var relative = ""
        for (index, part) in components.enumerated() {
            current += (current.hasSuffix("/") ? "" : "/") + part
            relative += (relative.isEmpty ? "" : "/") + part
            let status: FileStatus
            do {
                status = try FileStatus.read(atPath: current)
            } catch FileStatusError.missing {
                return .failure(.missing)
            } catch {
                return .failure(.unreadable(String(describing: error)))
            }
            if status.kind == .symbolicLink { return .failure(.symbolicLink(at: relative)) }
            if index == components.count - 1 {
                return status.kind == .regular ? .success(status) : .failure(.notRegular(status.kind))
            }
            if status.kind != .directory { return .failure(.notRegular(status.kind)) }
        }
        return .failure(.missing)
    }

    /// Lists matching entries recursively. Returns a refusal for a symbolic link or a matching non-regular entry.
    private static func walk(
        root: String, prefix: String, extensions: Set<String>, into found: inout [String]
    ) throws -> FileInventoryError? {
        let directory = prefix.isEmpty ? root : root + "/" + prefix
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory).sorted()
        } catch {
            return .unreadable(path: prefix.isEmpty ? directory : prefix, reason: String(describing: error))
        }
        for name in names where !name.hasPrefix(".") {
            let relative = prefix.isEmpty ? name : prefix + "/" + name
            let status: FileStatus
            do {
                status = try FileStatus.read(atPath: root + "/" + relative)
            } catch {
                return .unreadable(path: relative, reason: String(describing: error))
            }
            switch status.kind {
            case .symbolicLink: return .symbolicLink(path: relative)
            case .directory:
                if let problem = try walk(root: root, prefix: relative, extensions: extensions, into: &found) {
                    return problem
                }
            case .regular:
                if hasExtension(name, in: extensions) { found.append(relative) }
            default:
                if hasExtension(name, in: extensions) { return .notRegularFile(path: relative, kind: status.kind) }
            }
        }
        return nil
    }

    // MARK: Building

    static func build(root: URL, relativePaths: [String], afterHash: ((String) -> Void)?) throws -> FileInventory {
        try checkRoot(root)
        var entries: [(path: String, normalized: String, components: [String])] = []
        for path in relativePaths {
            let parts = try components(of: path)
            entries.append((path, normalize(path), parts))
        }
        if let clash = findCollision(in: relativePaths) {
            throw FileInventoryError.collision(path: clash.path, other: clash.other, kind: clash.kind)
        }
        entries.sort { $0.normalized < $1.normalized }

        var before: [FileStatus] = []
        for entry in entries {
            switch resolve(rootPath: root.path, components: entry.components) {
            case .success(let status): before.append(status)
            case .failure(.missing): throw FileInventoryError.missing(path: entry.normalized)
            case .failure(.symbolicLink(let link)): throw FileInventoryError.symbolicLink(path: normalize(link))
            case .failure(.notRegular(let kind)):
                throw FileInventoryError.notRegularFile(path: entry.normalized, kind: kind)
            case .failure(.unreadable(let reason)):
                throw FileInventoryError.unreadable(path: entry.normalized, reason: reason)
            }
        }

        var records: [FileRecord] = []
        for (entry, first) in zip(entries, before) {
            let url = URL(fileURLWithPath: root.path + "/" + entry.path)
            let result: SHA256FileResult
            do {
                result = try SHA256.hash(fileAt: url)
            } catch {
                throw FileInventoryError.unreadable(path: entry.normalized, reason: String(describing: error))
            }
            afterHash?(entry.normalized)
            let second: FileStatus
            do {
                second = try FileStatus.read(atPath: url.path)
            } catch {
                throw FileInventoryError.unstable(path: entry.normalized)
            }
            guard second.kind == .regular, isStable(before: first, after: second, hashedBytes: result.byteCount) else {
                throw FileInventoryError.unstable(path: entry.normalized)
            }
            records.append(
                FileRecord(
                    path: entry.normalized, size: first.size, sha256: result.digest,
                    modification: first.modification, creation: first.creation))
        }
        return FileInventory(records: records)
    }

    // MARK: Verification

    /// The timestamp mismatches of one file under a policy. A creation time expected but unavailable never passes.
    static func timestampMismatches(
        expected: FileRecord, status: FileStatus, policy: TimestampPolicy
    ) -> [VerificationMismatch] {
        var result: [VerificationMismatch] = []
        if case .mismatch(let want, let got) = policy.compare(
            source: expected.modification, backup: status.modification)
        {
            result.append(
                VerificationMismatch(
                    path: expected.path, kind: .modificationTimeDiffers,
                    detail: "expected \(describe(want)), found \(describe(got))"))
        }
        if let sourceCreation = expected.creation {
            if let backupCreation = status.creation {
                if case .mismatch(let want, let got) = policy.compare(source: sourceCreation, backup: backupCreation) {
                    result.append(
                        VerificationMismatch(
                            path: expected.path, kind: .creationTimeDiffers,
                            detail: "expected \(describe(want)), found \(describe(got))"))
                }
            } else {
                result.append(
                    VerificationMismatch(
                        path: expected.path, kind: .creationTimeUnavailable,
                        detail: "the copy reports no creation time"))
            }
        }
        return result
    }

    private static func describe(_ value: FileTimestamp) -> String { "\(value.seconds)s+\(value.nanoseconds)ns" }

    /// Compares the files under `copy` with the expected records. It never writes to the copy. When the size
    /// differs, the digest is not computed. Invalid expected paths and an unusable root are thrown; every other
    /// difference is reported as a mismatch. Only .m4a files are considered when looking for extra files.
    public static func verify(
        copy root: URL, against expected: [FileRecord], policy: TimestampPolicy
    ) throws -> VerificationReport {
        try checkRoot(root)
        var parsed: [(record: FileRecord, components: [String])] = []
        for record in expected { parsed.append((record, try components(of: record.path))) }
        if let clash = findCollision(in: expected.map(\.path)) {
            throw FileInventoryError.collision(path: clash.path, other: clash.other, kind: clash.kind)
        }
        parsed.sort { $0.record.path < $1.record.path }

        var mismatches: [VerificationMismatch] = []
        func report(_ path: String, _ kind: VerificationMismatchKind, _ detail: String) {
            mismatches.append(VerificationMismatch(path: path, kind: kind, detail: detail))
        }
        for (record, parts) in parsed {
            let status: FileStatus
            switch resolve(rootPath: root.path, components: parts) {
            case .success(let value): status = value
            case .failure(.missing):
                report(record.path, .missing, "not present in the copy")
                continue
            case .failure(.symbolicLink(let link)):
                report(record.path, .symbolicLink, "symbolic link at \(normalize(link))")
                continue
            case .failure(.notRegular(let kind)):
                report(record.path, .notRegularFile, "entry kind is \(kind.rawValue)")
                continue
            case .failure(.unreadable(let reason)):
                report(record.path, .unreadable, reason)
                continue
            }
            if status.size != record.size {
                report(record.path, .sizeDiffers, "expected \(record.size) bytes, found \(status.size)")
            } else {
                do {
                    let result = try SHA256.hash(fileAt: URL(fileURLWithPath: root.path + "/" + record.path))
                    let after = try FileStatus.read(atPath: root.path + "/" + record.path)
                    if !isStable(before: status, after: after, hashedBytes: result.byteCount) {
                        report(record.path, .unstable, "changed while it was hashed")
                    } else if result.digest != record.sha256 {
                        report(record.path, .digestDiffers, "expected \(record.sha256), found \(result.digest)")
                    }
                } catch {
                    report(record.path, .unreadable, String(describing: error))
                }
            }
            mismatches += timestampMismatches(expected: record, status: status, policy: policy)
        }

        let known = Set(expected.map { normalize($0.path) })
        var extras: [VerificationMismatch] = []
        collectExtras(root: root.path, prefix: "", known: known, issues: &extras)
        mismatches += extras
        return VerificationReport(policy: policy, checkedCount: parsed.count, mismatches: mismatches)
    }

    /// Lists .m4a files of the copy that are not expected. Symbolic links are reported and never followed.
    private static func collectExtras(
        root: String, prefix: String, known: Set<String>, issues: inout [VerificationMismatch]
    ) {
        let directory = prefix.isEmpty ? root : root + "/" + prefix
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory).sorted()
        } catch {
            issues.append(
                VerificationMismatch(
                    path: prefix, kind: .unreadable, detail: "directory cannot be listed: \(error)"))
            return
        }
        for name in names where !name.hasPrefix(".") {
            let relative = normalize(prefix.isEmpty ? name : prefix + "/" + name)
            guard let status = try? FileStatus.read(atPath: root + "/" + relative) else { continue }
            let matches = hasExtension(name, in: ["m4a"])
            switch status.kind {
            case .directory: collectExtras(root: root, prefix: relative, known: known, issues: &issues)
            case .symbolicLink:
                if matches && !known.contains(relative) {
                    issues.append(
                        VerificationMismatch(path: relative, kind: .extraFile, detail: "unexpected symbolic link"))
                }
            default:
                if matches && !known.contains(relative) {
                    issues.append(
                        VerificationMismatch(path: relative, kind: .extraFile, detail: "not in the expected set"))
                }
            }
        }
    }
}
