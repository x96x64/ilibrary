import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The stage of a rebuild as recorded in the recovery record. Only `prepared` is recorded in the record; later
/// progress is recorded in the progress journal. A record naming any other stage is refused.
public enum RecoveryStage: String, Codable, Equatable, Sendable {
    case prepared
}

/// The outcome of verifying a copy of the inventory.
public struct VerificationSummary: Codable, Equatable, Sendable {
    public let checkedCount: Int
    public let success: Bool

    public init(checkedCount: Int, success: Bool) {
        self.checkedCount = checkedCount
        self.success = success
    }
}

/// The planned move of one inventory file to the staging directory, which keeps the relative path.
public struct EvacuationEntry: Codable, Equatable, Sendable {
    public let sourcePath: String
    public let stagingPath: String

    public init(sourcePath: String, stagingPath: String) {
        self.sourcePath = sourcePath
        self.stagingPath = stagingPath
    }

    /// The evacuation plan of an inventory: each file's staging path is the staging directory joined with the
    /// file's relative path. Two roots with the same relative path produce equal staging paths, which validation
    /// refuses.
    public static func plan(inventory: [SourcedFileRecord], stagingDirectory: String) -> [EvacuationEntry] {
        inventory.map {
            EvacuationEntry(
                sourcePath: $0.absolutePath,
                stagingPath: (stagingDirectory == "/" ? "" : stagingDirectory) + "/" + $0.record.path)
        }
    }
}

/// The backup section. Physical BSD disk names are not stored, because they change between attachments.
public struct BackupSection: Codable, Equatable, Sendable {
    public var root: String
    public var volumeUUID: String?
    public var filesystemType: String?
    public var timestampPolicy: TimestampPolicy
    public var verification: VerificationSummary?
    /// The descriptions of the refusals of the independence verdict, if any.
    public var independenceReasons: [String]
    public var maintainerConfirmed: Bool
    public var verifiedAt: String?
    public var disconnectedAt: String?

    public init(
        root: String, volumeUUID: String?, filesystemType: String?, timestampPolicy: TimestampPolicy,
        verification: VerificationSummary?, independenceReasons: [String], maintainerConfirmed: Bool,
        verifiedAt: String?, disconnectedAt: String?
    ) {
        self.root = root
        self.volumeUUID = volumeUUID
        self.filesystemType = filesystemType
        self.timestampPolicy = timestampPolicy
        self.verification = verification
        self.independenceReasons = independenceReasons
        self.maintainerConfirmed = maintainerConfirmed
        self.verifiedAt = verifiedAt
        self.disconnectedAt = disconnectedAt
    }
}

public struct RestorationSection: Codable, Equatable, Sendable {
    public var directory: String
    public var verification: VerificationSummary?
    public var verifiedAt: String?

    public init(directory: String, verification: VerificationSummary?, verifiedAt: String?) {
        self.directory = directory
        self.verification = verification
        self.verifiedAt = verifiedAt
    }
}

/// A reason for which a record is invalid.
public enum RecoveryRecordProblem: Equatable, Sendable {
    case malformedPersistentID(String)
    case duplicatePersistentID(String)
    case invalidInventoryPath(String)
    case escapingInventoryPath(String)
    case collidingInventoryPaths(String, String)
    case inventoryUnsorted
    case unknownSourceRoot(String)
    case mappingNotOneToOne(String)
    case evacuationOutsideStaging(String)
    case evacuationNotUnique(String)
    case evacuationSourcesDiffer(String)
    case displayListNotReverse
    case backupDisconnectedWithoutVerification
    case inconsistent(String)
    case locationsInvalid([LocationRefusal])
}

/// The failures of writing and reading a recovery record.
public enum RecoveryRecordError: Error, Equatable, Sendable {
    case alreadyExists(path: String)
    case notADirectory(path: String)
    case notARegularFile(path: String)
    case unreadable(path: String, reason: String)
    case wrongFormat(String)
    case malformed(String)
    /// The checksum does not match: accidental corruption. The checksum is not a security measure.
    case checksumMismatch
    case invalid([RecoveryRecordProblem])
    case writeFailed(String)
    case readBackMismatch
}

/// File operations used by `RecoveryRecord.write`, replaceable so that a test can fail any step.
public struct RecordFileOperations: Sendable {
    public var fileExists: @Sendable (String) -> Bool
    /// Creates the file exclusively with mode 0600, writes all data, and synchronizes it.
    public var writeTemporary: @Sendable (String, Data) throws -> Void
    /// Publishes the first path as the second without replacing an existing file; the first path remains.
    public var publish: @Sendable (String, String) throws -> Void
    public var synchronizeDirectory: @Sendable (String) throws -> Void
    public var read: @Sendable (String) throws -> Data
    public var remove: @Sendable (String) -> Void

    public init(
        fileExists: @escaping @Sendable (String) -> Bool,
        writeTemporary: @escaping @Sendable (String, Data) throws -> Void,
        publish: @escaping @Sendable (String, String) throws -> Void,
        synchronizeDirectory: @escaping @Sendable (String) throws -> Void,
        read: @escaping @Sendable (String) throws -> Data, remove: @escaping @Sendable (String) -> Void
    ) {
        self.fileExists = fileExists
        self.writeTemporary = writeTemporary
        self.publish = publish
        self.synchronizeDirectory = synchronizeDirectory
        self.read = read
        self.remove = remove
    }

    public static let system = RecordFileOperations(
        fileExists: { (try? FileStatus.read(atPath: $0)) != nil },
        writeTemporary: { path, data in
            let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard descriptor >= 0 else { throw RecoveryRecordError.writeFailed("open \(path): errno \(errno)") }
            defer { close(descriptor) }
            var offset = 0
            try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                while offset < buffer.count {
                    let written = Foundation.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        throw RecoveryRecordError.writeFailed("write \(path): errno \(errno)")
                    }
                    offset += written
                }
            }
            try flush(descriptor, path)
        },
        publish: { from, to in
            // link(2) fails with EEXIST instead of replacing the destination, unlike rename(2).
            guard link(from, to) == 0 else {
                if errno == EEXIST { throw RecoveryRecordError.alreadyExists(path: to) }
                throw RecoveryRecordError.writeFailed("link \(from): errno \(errno)")
            }
        },
        synchronizeDirectory: { path in
            let descriptor = open(path, O_RDONLY)
            guard descriptor >= 0 else { throw RecoveryRecordError.writeFailed("open \(path): errno \(errno)") }
            defer { close(descriptor) }
            try flush(descriptor, path)
        },
        read: { try Data(contentsOf: URL(fileURLWithPath: $0)) },
        remove: { _ = unlink($0) })

    private static func flush(_ descriptor: Int32, _ path: String) throws {
        #if canImport(Darwin)
            if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
        #endif
        guard fsync(descriptor) == 0 else { throw RecoveryRecordError.writeFailed("fsync \(path): errno \(errno)") }
    }
}

/// The versioned recovery record of a prepared rebuild, stored only in the workspace directory.
///
/// It contains machine-specific paths and persistent IDs and is private: it is never added to a catalog or
/// committed. It is user-editable input; `load` validates it before it can authorize anything. The checksum guards
/// against accidental corruption and truncation only. It is not a security measure and does not authenticate the
/// record: anyone who can edit the file can recompute it.
public struct RecoveryRecord: Codable, Equatable, Sendable {
    public static let formatIdentifier = "ilibrary-rebuild-record-1"
    public static let fileName = "rebuild-record.json"

    public var format: String
    /// UTC ISO 8601, such as "2026-10-20T12:00:00Z".
    public var createdAt: String
    public var ilibraryVersion: String
    public var catalogPath: String
    public var catalogSHA256: SHA256Digest
    public var locations: RebuildLocations
    public var inventory: [SourcedFileRecord]
    public var registrations: [RegistrationRecord]
    public var mapping: [RegistrationMapping]
    /// Album identifiers in the order of addition.
    public var additionList: [String]
    /// The display order that Music is expected to show: the reverse of the addition list.
    public var expectedDisplayList: [String]
    public var evacuation: [EvacuationEntry]
    public var backup: BackupSection
    public var restoration: RestorationSection
    public var stage: RecoveryStage
    /// SHA-256 (hexadecimal) of the canonical encoding with this field empty; see `sealed()`.
    public var checksum: String

    public init(
        createdAt: String, ilibraryVersion: String, catalogPath: String, catalogSHA256: SHA256Digest,
        locations: RebuildLocations, inventory: [SourcedFileRecord], registrations: [RegistrationRecord],
        mapping: [RegistrationMapping], additionList: [String], expectedDisplayList: [String],
        evacuation: [EvacuationEntry], backup: BackupSection, restoration: RestorationSection,
        stage: RecoveryStage = .prepared, checksum: String = ""
    ) {
        self.format = RecoveryRecord.formatIdentifier
        self.createdAt = createdAt
        self.ilibraryVersion = ilibraryVersion
        self.catalogPath = catalogPath
        self.catalogSHA256 = catalogSHA256
        self.locations = locations
        self.inventory = inventory
        self.registrations = registrations
        self.mapping = mapping
        self.additionList = additionList
        self.expectedDisplayList = expectedDisplayList
        self.evacuation = evacuation
        self.backup = backup
        self.restoration = restoration
        self.stage = stage
        self.checksum = checksum
    }

    /// Formats an instant as UTC ISO 8601 with whole seconds.
    public static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// True when `text` is a UTC ISO 8601 time with a "Z" suffix. The exact form "YYYY-MM-DDTHH:MM:SSZ" naming a
    /// valid calendar instant of the years 1900 to 2999 is recognized without a formatter, because a journal checks
    /// one time per entry and creating a formatter for each of tens of thousands of entries dominates its parsing;
    /// every other text is decided by `ISO8601DateFormatter`.
    static func isUTCTimestamp(_ text: String) -> Bool {
        if isPlainUTCInstant(text) { return true }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return text.hasSuffix("Z") && formatter.date(from: text) != nil
    }

    private static func isPlainUTCInstant(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count == 20, bytes[4] == 0x2D, bytes[7] == 0x2D, bytes[10] == 0x54, bytes[13] == 0x3A,
            bytes[16] == 0x3A, bytes[19] == 0x5A
        else { return false }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let digit = Int(bytes[index]) - 0x30
                guard digit >= 0 && digit <= 9 else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
            let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
            (1900...2999).contains(year), (1...12).contains(month), hour < 24, minute < 60, second < 60
        else { return false }
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
        return (1...days).contains(day)
    }

    // MARK: Encoding and checksum

    private static func encoder(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting =
            pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// The canonical encoding that the checksum covers: sorted keys, compact, with an empty checksum.
    func canonicalData() throws -> Data {
        var copy = self
        copy.checksum = ""
        return try RecoveryRecord.encoder(pretty: false).encode(copy)
    }

    /// A copy whose checksum is the SHA-256 of its canonical encoding.
    public func sealed() throws -> RecoveryRecord {
        var copy = self
        copy.checksum = SHA256.digest(of: try canonicalData()).hex
        return copy
    }

    // MARK: Validation

    /// Every problem of the record, apart from the format and the checksum. An empty result means valid.
    public func problems() -> [RecoveryRecordProblem] {
        var found: [RecoveryRecordProblem] = []
        let locationProblems = locations.validate()
        if !locationProblems.isEmpty { found.append(.locationsInvalid(locationProblems)) }
        if !RecoveryRecord.isUTCTimestamp(createdAt) {
            found.append(.inconsistent("createdAt is not a UTC ISO 8601 time"))
        }
        if ilibraryVersion.isEmpty { found.append(.inconsistent("the ilibrary version is empty")) }
        if PathKey.invalidReason(catalogPath) != nil {
            found.append(.inconsistent("the catalog path is not an absolute standardized path"))
        }
        if catalogSHA256.bytes.count != SHA256Digest.byteCount { found.append(.inconsistent("bad catalog digest")) }

        var previous: (root: Int, path: String)?
        var sortedOK = true
        var inventoryKeys: [String: String] = [:]
        for entry in inventory {
            guard let rootIndex = locations.sources.firstIndex(of: entry.sourceRoot) else {
                found.append(.unknownSourceRoot(entry.sourceRoot))
                continue
            }
            var pathIsValid = true
            do {
                _ = try FileInventory.components(of: entry.record.path)
                // Swift compares canonically equivalent strings as equal, so compare scalars.
                if !entry.record.path.unicodeScalars.elementsEqual(
                    FileInventory.normalize(entry.record.path).unicodeScalars)
                {
                    throw FileInventoryError.invalidPath(path: entry.record.path)
                }
            } catch FileInventoryError.escapesRoot(let path) {
                found.append(.escapingInventoryPath(path))
                pathIsValid = false
            } catch {
                found.append(.invalidInventoryPath(entry.record.path))
                pathIsValid = false
            }
            guard pathIsValid else { continue }
            let key = PathKey.key(entry.absolutePath)
            if let other = inventoryKeys[key] {
                found.append(.collidingInventoryPaths(entry.absolutePath, other))
            } else {
                inventoryKeys[key] = entry.absolutePath
            }
            if let previous,
                (rootIndex, entry.record.path) <= (previous.root, previous.path)
            {
                sortedOK = false
            }
            previous = (rootIndex, entry.record.path)
        }
        if !sortedOK { found.append(.inventoryUnsorted) }

        var ids = Set<String>()
        var registrationByID: [String: RegistrationRecord] = [:]
        for registration in registrations {
            if !RegistrationRecord.isWellFormedID(registration.persistentID) {
                found.append(.malformedPersistentID(registration.persistentID))
            } else if !ids.insert(registration.persistentID.uppercased()).inserted {
                found.append(.duplicatePersistentID(registration.persistentID))
            }
            registrationByID[registration.persistentID.uppercased()] = registration
        }
        var mappedKeys = Set<String>()
        var mappedIDs = Set<String>()
        for item in mapping {
            let key = PathKey.key(item.location)
            let id = item.persistentID.uppercased()
            if inventoryKeys[key] == nil {
                found.append(.mappingNotOneToOne("the mapped location is not in the inventory: \(item.location)"))
            } else if !mappedKeys.insert(key).inserted {
                found.append(.mappingNotOneToOne("the location is mapped more than once: \(item.location)"))
            }
            if !mappedIDs.insert(id).inserted {
                found.append(.mappingNotOneToOne("the persistent ID is mapped more than once: \(item.persistentID)"))
            }
            guard let registration = registrationByID[id] else {
                found.append(
                    .mappingNotOneToOne("the mapped persistent ID has no registration: \(item.persistentID)"))
                continue
            }
            if let location = registration.location, PathKey.key(location) != key {
                found.append(
                    .mappingNotOneToOne("the registration \(item.persistentID) lies elsewhere than \(item.location)"))
            } else if registration.location == nil {
                found.append(.mappingNotOneToOne("the registration \(item.persistentID) has no location"))
            }
        }
        for (key, path) in inventoryKeys where !mappedKeys.contains(key) {
            found.append(.mappingNotOneToOne("the inventory file has no mapping: \(path)"))
        }
        for id in ids where !mappedIDs.contains(id) {
            found.append(.mappingNotOneToOne("the registration is not mapped: \(id)"))
        }
        if mapping.count != inventoryKeys.count {
            found.append(.mappingNotOneToOne("the counts of mapping and inventory differ"))
        }

        if expectedDisplayList != additionList.reversed() { found.append(.displayListNotReverse) }

        let stagingKey = PathKey.key(locations.stagingDirectory)
        var stagingKeys = Set<String>()
        var evacuationSources = Set<String>()
        let expectedStaging = Dictionary(
            EvacuationEntry.plan(inventory: inventory, stagingDirectory: locations.stagingDirectory).map {
                (PathKey.key($0.sourcePath), $0.stagingPath)
            }, uniquingKeysWith: { first, _ in first })
        for entry in evacuation {
            if PathKey.invalidReason(entry.stagingPath) != nil
                || PathKey.relation(entry.stagingPath, locations.stagingDirectory) != .firstInsideSecond
                || !PathKey.key(entry.stagingPath).hasPrefix(stagingKey == "/" ? "/" : stagingKey + "/")
            {
                found.append(.evacuationOutsideStaging(entry.stagingPath))
            } else if !stagingKeys.insert(PathKey.key(entry.stagingPath)).inserted {
                found.append(.evacuationNotUnique(entry.stagingPath))
            }
            let sourceKey = PathKey.key(entry.sourcePath)
            if inventoryKeys[sourceKey] == nil {
                found.append(.evacuationSourcesDiffer("the source is not in the inventory: \(entry.sourcePath)"))
            } else if !evacuationSources.insert(sourceKey).inserted {
                found.append(.evacuationSourcesDiffer("the source occurs more than once: \(entry.sourcePath)"))
            } else if let expected = expectedStaging[sourceKey], expected != entry.stagingPath {
                found.append(
                    .evacuationSourcesDiffer("the staging path does not keep the relative path: \(entry.sourcePath)"))
            }
        }
        for (key, path) in inventoryKeys where !evacuationSources.contains(key) {
            found.append(.evacuationSourcesDiffer("the inventory file has no evacuation entry: \(path)"))
        }

        if PathKey.relation(backup.root, locations.backupRoot) != .equal {
            found.append(.inconsistent("the backup root differs from the locations"))
        }
        if PathKey.relation(restoration.directory, locations.restorationDirectory) != .equal {
            found.append(.inconsistent("the restoration directory differs from the locations"))
        }
        for (name, text) in [
            ("backup verifiedAt", backup.verifiedAt), ("backup disconnectedAt", backup.disconnectedAt),
            ("restoration verifiedAt", restoration.verifiedAt),
        ] {
            if let text, !RecoveryRecord.isUTCTimestamp(text) {
                found.append(.inconsistent("\(name) is not a UTC ISO 8601 time"))
            }
        }
        if let summary = backup.verification, summary.success, summary.checkedCount != inventory.count {
            found.append(.inconsistent("the backup verification did not check every inventory file"))
        }
        if let summary = restoration.verification, summary.success, summary.checkedCount != inventory.count {
            found.append(.inconsistent("the restoration verification did not check every inventory file"))
        }
        if backup.disconnectedAt != nil {
            let verified = backup.verification?.success == true && backup.verifiedAt != nil
            if !verified || !backup.maintainerConfirmed { found.append(.backupDisconnectedWithoutVerification) }
        }
        return found
    }

    // MARK: Reading

    /// Decodes and validates the bytes of a record. The format is checked before anything else, so that an
    /// unknown version is reported as such, then the checksum, then the content.
    static func parse(_ data: Data) throws -> RecoveryRecord {
        struct Header: Decodable { let format: String }
        let decoder = JSONDecoder()
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw RecoveryRecordError.malformed("not a recovery record: \(error)")
        }
        guard header.format == formatIdentifier else { throw RecoveryRecordError.wrongFormat(header.format) }
        // A stage that this version does not know is named in the diagnostic instead of being reported as a
        // generic decoding failure; it remains a `malformed` error.
        struct StageHeader: Decodable { let stage: String? }
        if let stage = (try? decoder.decode(StageHeader.self, from: data))?.stage,
            RecoveryStage(rawValue: stage) == nil
        {
            throw RecoveryRecordError.malformed("unsupported stage '\(stage)'")
        }
        let record: RecoveryRecord
        do {
            record = try decoder.decode(RecoveryRecord.self, from: data)
        } catch {
            throw RecoveryRecordError.malformed("\(error)")
        }
        guard record.checksum == SHA256.digest(of: try record.canonicalData()).hex else {
            throw RecoveryRecordError.checksumMismatch
        }
        let found = record.problems()
        if !found.isEmpty { throw RecoveryRecordError.invalid(found) }
        return record
    }

    /// Loads the record file in `directory`, treating it as user-editable input. It refuses a wrong format or
    /// version, a checksum mismatch, a stage other than `prepared`, and every problem listed by `problems()`.
    public static func load(from directory: URL) throws -> RecoveryRecord {
        let path = directory.appendingPathComponent(fileName).path
        do {
            let status = try FileStatus.read(atPath: path)
            guard status.kind == .regular else { throw RecoveryRecordError.notARegularFile(path: path) }
        } catch let error as RecoveryRecordError {
            throw error
        } catch {
            throw RecoveryRecordError.unreadable(path: path, reason: String(describing: error))
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw RecoveryRecordError.unreadable(path: path, reason: String(describing: error))
        }
        return try parse(data)
    }

    // MARK: Writing

    /// Writes the record as `rebuild-record.json` in `directory`.
    ///
    /// It refuses an existing record file and an invalid record. The data are written to a temporary file in the
    /// same directory and synchronized. The file is then published under its final name with a hard link, which
    /// fails instead of replacing a file that another actor created after the existence check; the temporary name is
    /// removed, the directory is synchronized, and the file is read back, decoded, and compared with the sealed
    /// record. A filesystem without hard links therefore causes a refusal. A failure before or during publication
    /// removes only the temporary file and never the destination. A failure after publication removes the record
    /// file that this call created, since it cannot be trusted.
    @discardableResult
    public func write(to directory: URL, operations: RecordFileOperations = .system) throws -> RecoveryRecord {
        let directoryPath = directory.path
        guard let status = try? FileStatus.read(atPath: directoryPath), status.kind == .directory else {
            throw RecoveryRecordError.notADirectory(path: directoryPath)
        }
        let finalPath = directoryPath + "/" + RecoveryRecord.fileName
        if operations.fileExists(finalPath) { throw RecoveryRecordError.alreadyExists(path: finalPath) }
        let sealedRecord = try sealed()
        let found = sealedRecord.problems()
        if !found.isEmpty { throw RecoveryRecordError.invalid(found) }
        let data = try RecoveryRecord.encoder(pretty: true).encode(sealedRecord)
        let temporaryPath = directoryPath + "/." + RecoveryRecord.fileName + "." + UUID().uuidString + ".tmp"

        do {
            try operations.writeTemporary(temporaryPath, data)
            try operations.publish(temporaryPath, finalPath)
        } catch {
            operations.remove(temporaryPath)
            throw error
        }
        operations.remove(temporaryPath)
        do {
            try operations.synchronizeDirectory(directoryPath)
            let readBack = try RecoveryRecord.parse(try operations.read(finalPath))
            guard readBack == sealedRecord else { throw RecoveryRecordError.readBackMismatch }
        } catch {
            operations.remove(finalPath)
            throw error
        }
        return sealedRecord
    }
}
