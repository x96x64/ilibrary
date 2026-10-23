// Nanosecond modification and creation times on macOS, for restoring backed-up files. Built only on macOS; on
// other platforms it is empty.
#if os(macOS)
    import Darwin
    import Foundation
    import RebuildCore

    /// Failures of precise date operations. A refused operation leaves the file system unchanged.
    public enum PreciseFileDatesError: Error, Equatable, Sendable, CustomStringConvertible {
        case missing(path: String)
        case symbolicLink(path: String)
        case failed(path: String, step: String, errno: Int32)

        public var description: String {
            switch self {
            case .missing(let path): "\(path) does not exist; nothing was created"
            case .symbolicLink(let path): "\(path) is a symbolic link, which is not followed"
            case .failed(let path, let step, let code):
                "\(step) failed for \(path): \(String(cString: strerror(code)))"
            }
        }
    }

    /// The times stored after a write, read back from the file system; callers compare them under a
    /// `TimestampPolicy`.
    public struct StoredFileDates: Equatable, Sendable {
        public var modification: FileTimestamp
        public var creation: FileTimestamp?
    }

    public enum PreciseFileDates {
        /// Sets the modification and creation times of an existing entry and returns the values stored.
        ///
        /// The path is examined with `lstat` first: a missing path and a symbolic link are refused before any
        /// write, and nothing is ever created. Both writes use no-follow forms (`utimensat` with
        /// `AT_SYMLINK_NOFOLLOW`, `setattrlist` with `FSOPT_NOFOLLOW`).
        ///
        /// The access time is left unchanged (`UTIME_OMIT`); it is not set equal to the modification time.
        ///
        /// Order: the modification time is written first and the creation time second. A write of a
        /// modification time earlier than the creation time can move the creation time on some filesystems
        /// (HFS+ historically lowers the creation time to the new modification time), whereas a creation-time
        /// write does not alter the modification time; writing the creation time last therefore leaves both
        /// requested values in place. The measured behavior is recorded by the tests.
        ///
        /// The stored values are not compared here, because the filesystem may truncate them (HFS+ stores whole
        /// seconds). The caller decides acceptance with `TimestampPolicy`.
        public static func set(
            path: String, modification: FileTimestamp, creation: FileTimestamp
        ) throws -> StoredFileDates {
            var status = stat()
            guard lstat(path, &status) == 0 else {
                if errno == ENOENT || errno == ENOTDIR { throw PreciseFileDatesError.missing(path: path) }
                throw PreciseFileDatesError.failed(path: path, step: "lstat", errno: errno)
            }
            if status.st_mode & S_IFMT == S_IFLNK { throw PreciseFileDatesError.symbolicLink(path: path) }

            var times = [
                timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)),
                timespec(tv_sec: Int(modification.seconds), tv_nsec: Int(modification.nanoseconds)),
            ]
            guard utimensat(AT_FDCWD, path, &times, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw PreciseFileDatesError.failed(path: path, step: "utimensat", errno: errno)
            }

            var list = attrlist()
            list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
            list.commonattr = attrgroup_t(ATTR_CMN_CRTIME)
            var created = timespec(tv_sec: Int(creation.seconds), tv_nsec: Int(creation.nanoseconds))
            guard
                setattrlist(path, &list, &created, MemoryLayout<timespec>.size, UInt32(FSOPT_NOFOLLOW)) == 0
            else {
                throw PreciseFileDatesError.failed(path: path, step: "setattrlist", errno: errno)
            }

            do {
                let stored = try FileStatus.read(atPath: path)
                return StoredFileDates(modification: stored.modification, creation: stored.creation)
            } catch {
                throw PreciseFileDatesError.failed(path: path, step: "read back", errno: errno)
            }
        }
    }
#endif
