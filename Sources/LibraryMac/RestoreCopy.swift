// Exclusive, streaming file copy for the M11 restoration test. The source is only read.
#if os(macOS)
    import Darwin
    import Foundation
    import RebuildCore

    public enum RestoreCopyError: Error, Equatable, Sendable, CustomStringConvertible {
        case sourceMissing(path: String)
        case sourceNotRegular(path: String)
        case rootMissing(path: String)
        case rootNotDirectory(path: String)
        case destinationOutsideRoot(path: String)
        case destinationExists(path: String)
        case parentNotDirectory(path: String)
        case failed(path: String, step: String, errno: Int32)
        case injected

        public var description: String {
            switch self {
            case .sourceMissing(let path): "the source \(path) does not exist"
            case .sourceNotRegular(let path): "the source \(path) is not a regular file (links are refused)"
            case .rootMissing(let path): "the restoration root \(path) does not exist and is not created"
            case .rootNotDirectory(let path): "the restoration root \(path) is not a directory"
            case .destinationOutsideRoot(let path): "the destination \(path) is not below the restoration root"
            case .destinationExists(let path): "\(path) already exists and is not overwritten"
            case .parentNotDirectory(let path): "\(path) is not a directory (symbolic links are refused)"
            case .failed(let path, let step, let code):
                "\(step) failed for \(path): \(String(cString: strerror(code)))"
            case .injected: "an injected failure interrupted the copy"
            }
        }
    }

    public enum RestoreCopy {
        public static let defaultChunkSize = 1 << 20

        /// The absolute path of a URL without "." components, empty components, or ".." components, computed
        /// without the file system. `standardizedFileURL` is not used, because it removes a leading "/private"
        /// from a path that exists and not from one that does not, so a root and a new destination below it
        /// would no longer share a prefix.
        static func lexicalPath(_ url: URL) -> String {
            var parts: [Substring] = []
            for part in url.path.split(separator: "/", omittingEmptySubsequences: true) {
                if part == "." { continue }
                if part == ".." {
                    if !parts.isEmpty { parts.removeLast() }
                    continue
                }
                parts.append(part)
            }
            return "/" + parts.joined(separator: "/")
        }

        /// Copies a regular file to a new name below an existing restoration root and returns the bytes copied.
        ///
        /// The final component of the source must be a regular file (opened with `O_NOFOLLOW`); checking the
        /// directories above it is the caller's task. Anything at the destination, including a dangling link,
        /// causes refusal. Missing directories between `root` and the destination are created one at a time;
        /// the root itself must already exist and is never created, and existing components must be real
        /// directories. The bytes are streamed in chunks of at most `chunkSize` into a hidden temporary file
        /// created with `O_EXCL` in the destination directory, synchronized with `F_FULLFSYNC` (or `fsync` where
        /// unsupported), and renamed without replacement (`renamex_np` with `RENAME_EXCL`, or `link` and
        /// `unlink` where that is unsupported). The temporary file is removed on every failure. Dates are not
        /// copied; the caller sets them with `PreciseFileDates`. `afterChunk`, called with the running byte
        /// count, exists so that tests can inject a failure.
        @discardableResult
        public static func copy(
            from source: URL, to destination: URL, below root: URL,
            chunkSize: Int = defaultChunkSize, afterChunk: ((Int) throws -> Void)? = nil
        ) throws -> Int {
            precondition(chunkSize > 0)
            let sourcePath = source.path
            let destinationPath = lexicalPath(destination)
            var rootPath = lexicalPath(root)
            if rootPath.count > 1, rootPath.hasSuffix("/") { rootPath.removeLast() }

            let input = open(sourcePath, O_RDONLY | O_NOFOLLOW)
            guard input >= 0 else {
                let code = errno
                if code == ENOENT || code == ENOTDIR { throw RestoreCopyError.sourceMissing(path: sourcePath) }
                if code == ELOOP { throw RestoreCopyError.sourceNotRegular(path: sourcePath) }
                throw RestoreCopyError.failed(path: sourcePath, step: "open source", errno: code)
            }
            defer { close(input) }
            var sourceStatus = stat()
            guard fstat(input, &sourceStatus) == 0 else {
                throw RestoreCopyError.failed(path: sourcePath, step: "fstat source", errno: errno)
            }
            guard sourceStatus.st_mode & S_IFMT == S_IFREG else {
                throw RestoreCopyError.sourceNotRegular(path: sourcePath)
            }

            var rootStatus = stat()
            guard lstat(rootPath, &rootStatus) == 0 else { throw RestoreCopyError.rootMissing(path: rootPath) }
            guard rootStatus.st_mode & S_IFMT == S_IFDIR else {
                throw RestoreCopyError.rootNotDirectory(path: rootPath)
            }

            let prefix = rootPath == "/" ? "/" : rootPath + "/"
            guard destinationPath.hasPrefix(prefix), destinationPath.count > prefix.count else {
                throw RestoreCopyError.destinationOutsideRoot(path: destinationPath)
            }
            var existing = stat()
            if lstat(destinationPath, &existing) == 0 {
                throw RestoreCopyError.destinationExists(path: destinationPath)
            }

            let relative = destinationPath.dropFirst(prefix.count).split(separator: "/").map(String.init)
            var directory = rootPath
            for part in relative.dropLast() {
                directory += (directory.hasSuffix("/") ? "" : "/") + part
                var status = stat()
                if lstat(directory, &status) == 0 {
                    guard status.st_mode & S_IFMT == S_IFDIR else {
                        throw RestoreCopyError.parentNotDirectory(path: directory)
                    }
                } else {
                    guard errno == ENOENT else {
                        throw RestoreCopyError.failed(path: directory, step: "lstat", errno: errno)
                    }
                    guard mkdir(directory, 0o755) == 0 || errno == EEXIST else {
                        throw RestoreCopyError.failed(path: directory, step: "mkdir", errno: errno)
                    }
                }
            }

            let temporary = directory + "/.ilibrary-restore-\(UUID().uuidString).tmp"
            let output = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard output >= 0 else {
                throw RestoreCopyError.failed(path: temporary, step: "create temporary file", errno: errno)
            }
            var outputOpen = true
            var complete = false
            defer {
                if outputOpen { close(output) }
                if !complete { unlink(temporary) }
            }

            var buffer = [UInt8](repeating: 0, count: chunkSize)
            var total = 0
            while true {
                let count = read(input, &buffer, chunkSize)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw RestoreCopyError.failed(path: sourcePath, step: "read", errno: errno)
                }
                if count == 0 { break }
                var written = 0
                while written < count {
                    let step = buffer.withUnsafeBytes { write(output, $0.baseAddress! + written, count - written) }
                    if step < 0 {
                        if errno == EINTR { continue }
                        throw RestoreCopyError.failed(path: temporary, step: "write", errno: errno)
                    }
                    written += step
                }
                total += count
                try afterChunk?(total)
            }
            guard UInt64(total) == UInt64(sourceStatus.st_size) else {
                throw RestoreCopyError.failed(path: sourcePath, step: "source size changed during copy", errno: EIO)
            }
            _ = fchmod(output, sourceStatus.st_mode & 0o777)
            if fcntl(output, F_FULLFSYNC) != 0, fsync(output) != 0 {
                throw RestoreCopyError.failed(path: temporary, step: "fsync", errno: errno)
            }
            outputOpen = false
            guard close(output) == 0 else {
                throw RestoreCopyError.failed(path: temporary, step: "close", errno: errno)
            }

            if renamex_np(temporary, destinationPath, UInt32(RENAME_EXCL)) != 0 {
                let code = errno
                if code == EEXIST { throw RestoreCopyError.destinationExists(path: destinationPath) }
                guard code == ENOTSUP || code == EINVAL else {
                    throw RestoreCopyError.failed(path: destinationPath, step: "rename", errno: code)
                }
                guard link(temporary, destinationPath) == 0 else {
                    if errno == EEXIST { throw RestoreCopyError.destinationExists(path: destinationPath) }
                    throw RestoreCopyError.failed(path: destinationPath, step: "link", errno: errno)
                }
                unlink(temporary)
            }
            complete = true
            return total
        }
    }
#endif
