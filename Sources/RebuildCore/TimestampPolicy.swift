import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// The result of comparing a source timestamp with a backup timestamp.
public enum TimestampComparison: Equatable, Sendable {
    case match
    /// The backup timestamp is not acceptable; `expected` is the only value that would have matched.
    case mismatch(expected: FileTimestamp, actual: FileTimestamp)
}

/// The timestamp precision of a supported backup filesystem and the comparison that follows from it.
///
/// The precisions are taken from the filesystem specifications and have not been measured by iLibrary. The policy
/// never widens a tolerance to make a comparison pass.
public enum TimestampPolicy: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    /// APFS stores nanoseconds: modification and creation times must be equal exactly.
    case apfs
    /// HFS+ stores whole seconds: a backup timestamp is accepted only if it equals the source timestamp truncated
    /// toward negative infinity to whole seconds. No other tolerance applies.
    case hfsPlus

    /// Compares a source timestamp with the timestamp found on the backup.
    public func compare(source: FileTimestamp, backup: FileTimestamp) -> TimestampComparison {
        let expected: FileTimestamp
        switch self {
        case .apfs: expected = source
        case .hfsPlus: expected = source.truncatedToSeconds
        }
        return backup == expected ? .match : .mismatch(expected: expected, actual: backup)
    }

    /// Maps a `statfs` filesystem type name ("apfs" or "hfs") to a policy; any other name yields nil.
    public init?(filesystemTypeName name: String) {
        switch name {
        case "apfs": self = .apfs
        case "hfs": self = .hfsPlus
        default: return nil
        }
    }

    /// The filesystem type name of the volume containing `path`, as reported by `statfs` (`f_fstypename`).
    /// It is nil when the call fails and always nil on platforms other than Darwin.
    public static func filesystemTypeName(containing path: String) -> String? {
        #if canImport(Darwin)
            var buffer = statfs()
            guard statfs(path, &buffer) == 0 else { return nil }
            return withUnsafePointer(to: &buffer.f_fstypename) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
            }
        #else
            return nil
        #endif
    }

    /// The policy for the volume containing `path`, or nil when the filesystem is not APFS or HFS+ or cannot be
    /// determined (for example msdos, exfat, smbfs, or nfs), so that callers refuse. Always nil outside Darwin.
    public static func forVolume(containing path: String) -> TimestampPolicy? {
        guard let name = filesystemTypeName(containing: path) else { return nil }
        return TimestampPolicy(filesystemTypeName: name)
    }
}
