import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Creating, reading, and appending to `rebuild-journal.jsonl` in the workspace directory.
///
/// What is not guaranteed: the advisory lock taken with `flock` does not stop a writer that does not cooperate;
/// durability depends on the filesystem honouring `fsync` and, on Darwin, `F_FULLFSYNC`; and a power loss can
/// leave a torn final entry, which the reader then refuses and which this code never repairs. A failure after a
/// write may have started is reported as uncertain and is never retried.
public enum ProgressJournalFile {
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
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ProgressJournalError.notARegularFile(path: path) }
        defer { close(descriptor) }
        try requireRegular(descriptor, path: path)
        let bytes = try Operations.system.readAll(descriptor)
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
                throw ProgressJournalError.writeFailed("the header could not be written: \(error)")
            }
            throw ProgressJournalError.creationUncertain("the header write failed after bytes were written: \(error)")
        }
        do {
            try operations.synchronize(descriptor)
            try operations.synchronizeDirectory(directoryPath)
            // The creating descriptor is write-only, so the read-back uses a second descriptor on the same path.
            let reader = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard reader >= 0 else {
                throw ProgressJournalError.creationUncertain("the journal cannot be reopened: errno \(errno)")
            }
            defer { close(reader) }
            guard try operations.readAll(reader) == line else {
                throw ProgressJournalError.creationUncertain("the journal read back differently from the header")
            }
        } catch let error as ProgressJournalError {
            if case .creationUncertain = error { throw error }
            throw ProgressJournalError.creationUncertain("\(error)")
        } catch {
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
        let path = directory.appendingPathComponent(ProgressJournal.fileName).path
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ProgressJournalError.notARegularFile(path: path) }
        defer { close(descriptor) }
        try requireRegular(descriptor, path: path)
        let data = try Operations.system.readAll(descriptor)
        return try ProgressJournal.load(data: data, record: record, recordBytes: recordBytes)
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
        if let status = try? FileStatus.read(atPath: path), status.kind != .regular {
            throw ProgressJournalError.notARegularFile(path: path)
        }
        let descriptor = open(path, O_RDWR | O_APPEND | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ProgressJournalError.notARegularFile(path: path) }
        defer { close(descriptor) }
        try requireRegular(descriptor, path: path, strict: true)
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { throw ProgressJournalError.locked(path: path) }
            throw ProgressJournalError.unreadable(path: path, reason: "flock: errno \(errno)")
        }

        let before = try operations.readAll(descriptor)
        let (_, progress) = try ProgressJournal.load(data: before, record: record, recordBytes: recordBytes)
        guard progress.head == expectedHead else {
            throw ProgressJournalError.concurrentModification(expected: expectedHead, found: progress.head)
        }
        let entry = try JournalEntry(
            sequence: progress.head.sequence + 1, previous: progress.head.checksum, body: body,
            recordedAt: RecoveryRecord.timestampString(recordedAt))
        let problems = ProgressJournal.nextEntryProblems(record: record, progress: progress, entry: entry)
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
        } catch let error as ProgressJournalError {
            if case .appendUncertain = error { throw error }
            throw ProgressJournalError.appendUncertain("\(error)")
        } catch {
            throw ProgressJournalError.appendUncertain("\(error)")
        }
        return JournalHead(sequence: entry.sequence, checksum: entry.checksum)
    }

    // MARK: Descriptor checks

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
