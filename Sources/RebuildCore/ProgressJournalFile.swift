import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The progress that a journal file implies, together with the size of the file that it describes, so that a
/// writer appends without reading the file again. The state is an observation of one moment: the append that
/// takes it refuses to write when the file no longer ends as the state says.
public struct JournalState: Equatable, Sendable {
    public let progress: RebuildProgress
    /// The size in bytes of the journal file that `progress` describes.
    public let byteCount: Int
    /// The index of the record that `progress` was replayed against. It is derived data and takes no part in
    /// equality.
    let index: RecordIndex

    init(progress: RebuildProgress, byteCount: Int, index: RecordIndex) {
        self.progress = progress
        self.byteCount = byteCount
        self.index = index
    }

    public static func == (lhs: JournalState, rhs: JournalState) -> Bool {
        lhs.progress == rhs.progress && lhs.byteCount == rhs.byteCount
    }
}

/// Creating, reading, and appending to `rebuild-journal.jsonl` in the workspace directory.
///
/// What is not guaranteed: the advisory lock taken with `flock` does not stop a writer that does not cooperate;
/// durability depends on the filesystem honouring `fsync` and, on Darwin, `F_FULLFSYNC`; and a power loss can
/// leave a torn final entry, which the reader then refuses and which this code never repairs. A failure after a
/// write may have started is reported as uncertain and is never retried.
public enum ProgressJournalFile {
    public typealias JournalState = RebuildCore.JournalState

    /// The system calls used on an open descriptor, replaceable so that a test can fail any step.
    public struct Operations: Sendable {
        /// Writes all bytes, handling interruption and short writes.
        public var write: @Sendable (Int32, Data) throws -> Void
        public var synchronize: @Sendable (Int32) throws -> Void
        public var synchronizeDirectory: @Sendable (String) throws -> Void
        /// Reads the whole file from offset 0 through the descriptor.
        public var readAll: @Sendable (Int32) throws -> Data
        public var remove: @Sendable (String) -> Void

        public init(
            write: @escaping @Sendable (Int32, Data) throws -> Void,
            synchronize: @escaping @Sendable (Int32) throws -> Void,
            synchronizeDirectory: @escaping @Sendable (String) throws -> Void,
            readAll: @escaping @Sendable (Int32) throws -> Data, remove: @escaping @Sendable (String) -> Void
        ) {
            self.write = write
            self.synchronize = synchronize
            self.synchronizeDirectory = synchronizeDirectory
            self.readAll = readAll
            self.remove = remove
        }

        public static let system = Operations(
            write: { descriptor, data in
                var offset = 0
                try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                    while offset < buffer.count {
                        let written = Foundation.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                        if written < 0 {
                            if errno == EINTR { continue }
                            throw ProgressJournalError.writeFailed("write: errno \(errno)")
                        }
                        offset += written
                    }
                }
            },
            synchronize: { descriptor in try flush(descriptor, "journal") },
            synchronizeDirectory: { path in
                let descriptor = open(path, O_RDONLY | O_CLOEXEC)
                guard descriptor >= 0 else { throw ProgressJournalError.writeFailed("open \(path): errno \(errno)") }
                defer { close(descriptor) }
                try flush(descriptor, path)
            },
            readAll: { descriptor in try readEntireFile(descriptor) },
            remove: { _ = unlink($0) })

        private static func flush(_ descriptor: Int32, _ name: String) throws {
            #if canImport(Darwin)
                if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
            #endif
            guard fsync(descriptor) == 0 else {
                throw ProgressJournalError.writeFailed("fsync \(name): errno \(errno)")
            }
        }

        private static func readEntireFile(_ descriptor: Int32) throws -> Data {
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1 << 16)
            var offset: off_t = 0
            while true {
                let count = buffer.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, $0.count, offset) }
                if count < 0 {
                    if errno == EINTR { continue }
                    throw ProgressJournalError.unreadable(path: "journal", reason: "read: errno \(errno)")
                }
                if count == 0 { return data }
                data.append(contentsOf: buffer[0..<count])
                offset += off_t(count)
            }
        }
    }

    // MARK: Record

    /// Reads `rebuild-record.json` from the workspace and validates it, returning the exact bytes with the
    /// record, because the journal header binds the bytes.
    public static func loadRecord(from directory: URL) throws -> (record: RecoveryRecord, bytes: Data) {
        let path = directory.appendingPathComponent(RecoveryRecord.fileName).path
        let bytes = try readRegularFile(atPath: path)
        do {
            return (try RecoveryRecord.parse(bytes), bytes)
        } catch {
            throw ProgressJournalError.unreadable(path: path, reason: String(describing: error))
        }
    }

    // MARK: Creation

    /// Creates the journal with its header line. The header binds `recordBytes`, which must be the exact bytes of
    /// the record file and must parse to `record`.
    ///
    /// The file is created exclusively with mode 0600 without following a symbolic link. A failure before any
    /// byte was written removes the empty file; a failure after that leaves the file in place as evidence and is
    /// reported as `creationUncertain`.
    @discardableResult
    public static func create(
        in directory: URL, record: RecoveryRecord, recordBytes: Data, ilibraryVersion: String,
        recordedAt: Date = Date(), operations: Operations = .system
    ) throws -> JournalHead {
        let directoryPath = directory.path
        guard let status = try? FileStatus.read(atPath: directoryPath), status.kind == .directory else {
            throw ProgressJournalError.notADirectory(path: directoryPath)
        }
        guard (try? RecoveryRecord.parse(recordBytes)) == record else { throw ProgressJournalError.recordMismatch }
        let digest = SHA256.digest(of: recordBytes).hex
        let header = JournalHeader(
            recordChecksum: record.checksum, recordFileSHA256: digest, ilibraryVersion: ilibraryVersion)
        let entry = try JournalEntry(
            sequence: 0, previous: digest, body: .header(header),
            recordedAt: RecoveryRecord.timestampString(recordedAt))
        let line = try entry.line()
        let path = directoryPath + "/" + ProgressJournal.fileName

        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            if errno == EEXIST { throw ProgressJournalError.alreadyExists(path: path) }
            throw ProgressJournalError.writeFailed("open \(path): errno \(errno)")
        }
        defer { close(descriptor) }
        do {
            try operations.write(descriptor, line)
        } catch {
            var buffer = stat()
            if fstat(descriptor, &buffer) == 0 && buffer.st_size == 0 {
                operations.remove(path)
                if (try? FileStatus.read(atPath: path)) != nil {
                    throw ProgressJournalError.creationUncertain(
                        "the header could not be written, and the empty journal could not be removed: \(error)")
                }
                throw ProgressJournalError.writeFailed("the header could not be written: \(error)")
            }
            throw ProgressJournalError.creationUncertain("the header write failed after bytes were written: \(error)")
        }
        do {
            try operations.synchronize(descriptor)
            try operations.synchronizeDirectory(directoryPath)
            // The creating descriptor is write-only, so the read-back uses a second descriptor on the same path.
            let reader = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard reader >= 0 else {
                throw ProgressJournalError.creationUncertain("the journal cannot be reopened: errno \(errno)")
            }
            defer { close(reader) }
            guard try operations.readAll(reader) == line else {
                throw ProgressJournalError.creationUncertain("the journal read back differently from the header")
            }
        } catch {
            if case ProgressJournalError.creationUncertain = error { throw error }
            throw ProgressJournalError.creationUncertain("\(error)")
        }
        return JournalHead(sequence: 0, checksum: entry.checksum)
    }

    // MARK: Reading

    /// Reads, parses, and replays the journal of a workspace. A torn final entry, a bad chain, or any invalid
    /// transition is an error; nothing is truncated or repaired.
    public static func read(in directory: URL, record: RecoveryRecord, recordBytes: Data) throws
        -> (entries: [JournalEntry], progress: RebuildProgress)
    {
        let data = try readRegularFile(atPath: directory.appendingPathComponent(ProgressJournal.fileName).path)
        return try ProgressJournal.load(data: data, record: record, recordBytes: recordBytes)
    }

    /// Reads, parses, and replays the whole journal once, like `read`, and returns the progress with the byte count
    /// of the file, for the incremental `append(_:to:state:...)`.
    public static func readState(in directory: URL, record: RecoveryRecord, recordBytes: Data) throws -> JournalState {
        let data = try readRegularFile(atPath: directory.appendingPathComponent(ProgressJournal.fileName).path)
        let loaded = try ProgressJournal.loadIndexed(data: data, record: record, recordBytes: recordBytes)
        return JournalState(progress: loaded.progress, byteCount: data.count, index: loaded.index)
    }

    // MARK: Appending

    /// Appends one entry to the journal.
    ///
    /// The file is opened without following a symbolic link and must be a regular file with one link, owned by
    /// the effective user, without write permission for the group or others. An exclusive non-blocking advisory
    /// lock is taken (`locked` if unavailable). Under the lock the whole file is read through the same descriptor,
    /// parsed, and replayed; its head must equal `expectedHead` (`concurrentModification` otherwise); the entry
    /// that follows from `body` must satisfy the transition rules (`invalidEntry` otherwise, with nothing
    /// written). The single line is then written and synchronized, and the file is read again under the lock and
    /// must equal the previous bytes plus exactly that line. A failure after the write may have started is
    /// reported as `appendUncertain`, never as success, and is not retried. The lock is released by closing the
    /// descriptor.
    @discardableResult
    public static func append(
        _ body: JournalBody, to directory: URL, expectedHead: JournalHead, record: RecoveryRecord, recordBytes: Data,
        recordedAt: Date = Date(), operations: Operations = .system
    ) throws -> JournalHead {
        let path = directory.appendingPathComponent(ProgressJournal.fileName).path
        let descriptor = try openLocked(atPath: path)
        defer { close(descriptor) }

        let before = try operations.readAll(descriptor)
        let (_, progress, index) = try ProgressJournal.loadIndexed(
            data: before, record: record, recordBytes: recordBytes)
        guard progress.head == expectedHead else {
            throw ProgressJournalError.concurrentModification(expected: expectedHead, found: progress.head)
        }
        let entry = try JournalEntry(
            sequence: progress.head.sequence + 1, previous: progress.head.checksum, body: body,
            recordedAt: RecoveryRecord.timestampString(recordedAt))
        let problems = ProgressJournal.nextEntryProblems(
            index: index, record: record, progress: progress, entry: entry)
        guard problems.isEmpty else { throw ProgressJournalError.invalidEntry(problems) }

        let line = try entry.line()
        do {
            try operations.write(descriptor, line)
            try operations.synchronize(descriptor)
            let after = try operations.readAll(descriptor)
            guard after == before + line else {
                throw ProgressJournalError.appendUncertain(
                    "the journal after the append differs from the expected bytes")
            }
        } catch {
            if case ProgressJournalError.appendUncertain = error { throw error }
            throw ProgressJournalError.appendUncertain("\(error)")
        }
        return JournalHead(sequence: entry.sequence, checksum: entry.checksum)
    }

    /// Appends one entry to the journal that `state` describes, without reading the whole file again.
    ///
    /// The file is opened and locked exactly as by `append(_:to:expectedHead:...)`. Under the lock the file size
    /// must equal `state.byteCount`, and the final line, read from the end of the file only, must be an entry whose
    /// sequence and checksum equal `state.progress.head`; otherwise `concurrentModification` is thrown and nothing
    /// is written. When the final line cannot be read or parsed, the head reported as found has sequence -1 and an
    /// empty checksum. The entry that follows from `body` must satisfy the transition rules (`invalidEntry`
    /// otherwise, with nothing written). The line is then written and synchronized, and the bytes from offset
    /// `state.byteCount` onward must equal exactly that line, with the file ending there. A failure after the write
    /// may have started is reported as `appendUncertain` and is not retried. The returned state describes the file
    /// after the append.
    ///
    /// The check detects a writer that appended or truncated, and a change of the final line. It does not detect
    /// a change of an earlier line, which only a full `readState` examines. `record` must be the record of the
    /// replay that produced `state` (`recordMismatch` otherwise); `recordBytes` is accepted for symmetry with
    /// `readState`, because the state already carries the replay that bound the journal to those bytes.
    @discardableResult
    public static func append(
        _ body: JournalBody, to directory: URL, state: JournalState, record: RecoveryRecord, recordBytes: Data,
        recordedAt: Date = Date(), operations: Operations = .system
    ) throws -> JournalState {
        guard state.index.recordChecksum == record.checksum else { throw ProgressJournalError.recordMismatch }
        let path = directory.appendingPathComponent(ProgressJournal.fileName).path
        let descriptor = try openLocked(atPath: path)
        defer { close(descriptor) }

        let head = state.progress.head
        let size = try fileSize(descriptor, path: path)
        let tail = try finalHead(descriptor, size: size, path: path)
        guard size == state.byteCount, tail == head else {
            throw ProgressJournalError.concurrentModification(expected: head, found: tail ?? unreadableHead)
        }

        let entry = try JournalEntry(
            sequence: head.sequence + 1, previous: head.checksum, body: body,
            recordedAt: RecoveryRecord.timestampString(recordedAt))
        let problems = ProgressJournal.nextEntryProblems(
            index: state.index, record: record, progress: state.progress, entry: entry)
        guard problems.isEmpty else { throw ProgressJournalError.invalidEntry(problems) }

        let line = try entry.line()
        let expectedSize = state.byteCount + line.count
        do {
            try operations.write(descriptor, line)
            try operations.synchronize(descriptor)
            guard try fileSize(descriptor, path: path) == expectedSize,
                try readExactly(descriptor, offset: state.byteCount, count: line.count, path: path) == line
            else {
                throw ProgressJournalError.appendUncertain(
                    "the journal after the append differs from the expected bytes")
            }
        } catch {
            if case ProgressJournalError.appendUncertain = error { throw error }
            throw ProgressJournalError.appendUncertain("\(error)")
        }
        var progress = state.progress
        progress.advance(with: entry, record: record)
        return JournalState(progress: progress, byteCount: expectedSize, index: state.index)
    }

    // MARK: Descriptors

    /// The head reported when the final line of the journal cannot be read or parsed.
    private static let unreadableHead = JournalHead(sequence: -1, checksum: "")

    /// Opens the regular file at `path` without following a symbolic link and returns its bytes.
    private static func readRegularFile(atPath path: String) throws -> Data {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw ProgressJournalError.notARegularFile(path: path) }
        defer { close(descriptor) }
        try requireRegular(descriptor, path: path)
        return try Operations.system.readAll(descriptor)
    }

    /// Opens the journal for appending without following a symbolic link, requires a safe regular file, and takes
    /// the exclusive non-blocking advisory lock. Closing the returned descriptor releases the lock.
    private static func openLocked(atPath path: String) throws -> Int32 {
        if let status = try? FileStatus.read(atPath: path), status.kind != .regular {
            throw ProgressJournalError.notARegularFile(path: path)
        }
        let descriptor = open(path, O_RDWR | O_APPEND | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw ProgressJournalError.notARegularFile(path: path) }
        do {
            try requireRegular(descriptor, path: path, strict: true)
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                // EWOULDBLOCK equals EAGAIN on Darwin and Linux; EAGAIN alone avoids depending on the alias.
                if errno == EAGAIN { throw ProgressJournalError.locked(path: path) }
                throw ProgressJournalError.unreadable(path: path, reason: "flock: errno \(errno)")
            }
        } catch {
            close(descriptor)
            throw error
        }
        return descriptor
    }

    private static func fileSize(_ descriptor: Int32, path: String) throws -> Int {
        var buffer = stat()
        guard fstat(descriptor, &buffer) == 0 else {
            throw ProgressJournalError.unreadable(path: path, reason: "fstat: errno \(errno)")
        }
        return Int(buffer.st_size)
    }

    /// Reads `count` bytes at `offset` through `pread`, handling interruption and short reads. The result is
    /// shorter than `count` only when the file ends first.
    private static func readExactly(_ descriptor: Int32, offset: Int, count: Int, path: String) throws -> Data {
        var data = Data(count: count)
        var done = 0
        while done < count {
            let read = data.withUnsafeMutableBytes { buffer in
                pread(descriptor, buffer.baseAddress! + done, count - done, off_t(offset + done))
            }
            if read < 0 {
                if errno == EINTR { continue }
                throw ProgressJournalError.unreadable(path: path, reason: "read: errno \(errno)")
            }
            if read == 0 { break }
            done += read
        }
        return done == count ? data : Data(data.prefix(done))
    }

    /// The head that the final line of a file of `size` bytes states, or nil when the file is empty, does not end
    /// with a newline, or its final line is not a valid entry. Only the end of the file is read.
    private static func finalHead(_ descriptor: Int32, size: Int, path: String) throws -> JournalHead? {
        guard size > 0,
            try readExactly(descriptor, offset: size - 1, count: 1, path: path) == Data([0x0A])
        else { return nil }
        let block = 1 << 12
        var tail = Data()
        var start = size
        var lineStart = 0
        while start > 0 {
            let length = min(block, start)
            start -= length
            tail = try readExactly(descriptor, offset: start, count: length, path: path) + tail
            // The final newline ends the final line; the newline before it, if any, ends the previous line.
            if let newline = tail.dropLast().lastIndex(of: 0x0A) {
                lineStart = start + newline + 1
                break
            }
        }
        let line = Data(tail.suffix(size - lineStart).dropLast())
        guard let entry = try? ProgressJournal.parseLine(line, index: 0, isFinal: true) else { return nil }
        return JournalHead(sequence: entry.sequence, checksum: entry.checksum)
    }

    private static func requireRegular(_ descriptor: Int32, path: String, strict: Bool = false) throws {
        var buffer = stat()
        guard fstat(descriptor, &buffer) == 0 else {
            throw ProgressJournalError.unreadable(path: path, reason: "fstat: errno \(errno)")
        }
        guard buffer.st_mode & S_IFMT == S_IFREG else { throw ProgressJournalError.notARegularFile(path: path) }
        guard strict else { return }
        if buffer.st_nlink != 1 {
            throw ProgressJournalError.unsafeFile(path: path, reason: "the file has \(buffer.st_nlink) links")
        }
        if buffer.st_uid != geteuid() {
            throw ProgressJournalError.unsafeFile(path: path, reason: "the owner is not the effective user")
        }
        if buffer.st_mode & 0o022 != 0 {
            throw ProgressJournalError.unsafeFile(path: path, reason: "the group or others may write to the file")
        }
    }
}
