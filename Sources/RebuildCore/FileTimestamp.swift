import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// A point in time as whole seconds and nanoseconds since 1970-01-01T00:00:00Z, without floating-point conversion.
///
/// The value is normalized so that `nanoseconds` lies in `0..<1_000_000_000`. Instants before 1970 therefore have a
/// negative `seconds` and a non-negative `nanoseconds`; for example, 1.5 seconds before the epoch is `-2` seconds
/// and `500_000_000` nanoseconds. Ordering and truncation toward negative infinity follow directly from this form.
public struct FileTimestamp: Codable, Equatable, Hashable, Sendable {
    public static let nanosecondsPerSecond: Int32 = 1_000_000_000

    public let seconds: Int64
    public let nanoseconds: Int32

    /// Creates a timestamp. A `nanoseconds` value outside `0..<1_000_000_000` is carried into `seconds` by floor
    /// division, so that the stored value is always normalized. An unrepresentable carry saturates `seconds`.
    public init(seconds: Int64, nanoseconds: Int32 = 0) {
        let unit = Int64(FileTimestamp.nanosecondsPerSecond)
        let wide = Int64(nanoseconds)
        var carry = wide / unit
        var remainder = wide % unit
        if remainder < 0 {
            remainder += unit
            carry -= 1
        }
        let (sum, overflow) = seconds.addingReportingOverflow(carry)
        self.seconds = overflow ? (carry > 0 ? Int64.max : Int64.min) : sum
        self.nanoseconds = Int32(remainder)
    }

    /// The timestamp truncated toward negative infinity to whole seconds.
    public var truncatedToSeconds: FileTimestamp { FileTimestamp(seconds: seconds, nanoseconds: 0) }
}

/// The kind of a filesystem entry, determined without following a symbolic link.
public enum FileKind: String, Codable, Equatable, Hashable, Sendable {
    case regular
    case directory
    case symbolicLink
    case fifo
    case characterDevice
    case blockDevice
    case socket
    case other
}

/// The failures of reading the status of a path.
public enum FileStatusError: Error, Equatable, Sendable {
    /// The path, or a directory on it, does not exist (ENOENT or ENOTDIR).
    case missing(path: String)
    /// Access was denied (EACCES or EPERM).
    case permissionDenied(path: String)
    case other(path: String, errno: Int32)
}

/// The status of a filesystem entry as reported by `lstat`.
public struct FileStatus: Equatable, Sendable {
    public let kind: FileKind
    public let size: UInt64
    public let inode: UInt64
    public let device: Int64
    public let linkCount: UInt64
    public let modification: FileTimestamp
    /// The creation (birth) time. It is nil where the platform does not report one; on Darwin it is always present.
    public let creation: FileTimestamp?

    public init(
        kind: FileKind, size: UInt64, inode: UInt64, device: Int64, linkCount: UInt64,
        modification: FileTimestamp, creation: FileTimestamp?
    ) {
        self.kind = kind
        self.size = size
        self.inode = inode
        self.device = device
        self.linkCount = linkCount
        self.modification = modification
        self.creation = creation
    }

    #if canImport(Darwin) || canImport(Glibc)
        /// Reads the status of `path` with `lstat`, so that a symbolic link at the final component is described
        /// and not followed.
        public static func read(atPath path: String) throws -> FileStatus {
            var buffer = stat()
            guard lstat(path, &buffer) == 0 else {
                let code = errno
                switch code {
                case ENOENT, ENOTDIR: throw FileStatusError.missing(path: path)
                case EACCES, EPERM: throw FileStatusError.permissionDenied(path: path)
                default: throw FileStatusError.other(path: path, errno: code)
                }
            }
            #if canImport(Darwin)
                let modification = FileStatus.timestamp(buffer.st_mtimespec)
                let creation: FileTimestamp? = FileStatus.timestamp(buffer.st_birthtimespec)
            #else
                let modification = FileStatus.timestamp(buffer.st_mtim)
                let creation: FileTimestamp? = nil
            #endif
            return FileStatus(
                kind: FileStatus.kind(of: buffer.st_mode),
                size: buffer.st_size < 0 ? 0 : UInt64(buffer.st_size),
                inode: UInt64(buffer.st_ino),
                device: Int64(buffer.st_dev),
                linkCount: UInt64(buffer.st_nlink),
                modification: modification,
                creation: creation)
        }

        private static func timestamp(_ value: timespec) -> FileTimestamp {
            FileTimestamp(seconds: Int64(value.tv_sec), nanoseconds: Int32(truncatingIfNeeded: value.tv_nsec))
        }

        private static func kind(of mode: mode_t) -> FileKind {
            switch mode & S_IFMT {
            case S_IFREG: return .regular
            case S_IFDIR: return .directory
            case S_IFLNK: return .symbolicLink
            case S_IFIFO: return .fifo
            case S_IFCHR: return .characterDevice
            case S_IFBLK: return .blockDevice
            case S_IFSOCK: return .socket
            default: return .other
            }
        }
    #endif
}
