import Foundation

/// The stages of a rebuild, in the order in which a journal may begin them.
public enum RebuildStage: String, Codable, CaseIterable, Equatable, Sendable {
    case evacuation
    case clearing
    case application
    case addition
    case display
}

/// The operations that a journal can record. Each belongs to exactly one stage.
///
/// The journal only records and validates these operations. Nothing in this module performs one.
public enum RebuildOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case evacuateFile
    case removeRegistration
    case confirmLibraryEmpty
    case terminateMusic
    case applyFile
    case addAlbum
    case confirmDisplay

    public var stage: RebuildStage {
        switch self {
        case .evacuateFile: .evacuation
        case .removeRegistration, .confirmLibraryEmpty, .terminateMusic: .clearing
        case .applyFile: .application
        case .addAlbum: .addition
        case .confirmDisplay: .display
        }
    }
}

/// A file as observed on disk: the fields of an inventory record other than its relative path.
public struct ObservedFile: Codable, Equatable, Sendable {
    public let size: UInt64
    public let sha256: SHA256Digest
    public let modification: FileTimestamp
    public let creation: FileTimestamp?

    public init(size: UInt64, sha256: SHA256Digest, modification: FileTimestamp, creation: FileTimestamp?) {
        self.size = size
        self.sha256 = sha256
        self.modification = modification
        self.creation = creation
    }

    public init(_ record: FileRecord) {
        self.init(
            size: record.size, sha256: record.sha256, modification: record.modification, creation: record.creation)
    }

    /// True when size, digest, modification time, and creation time all equal those of the inventory record.
    public func matches(_ record: FileRecord) -> Bool {
        size == record.size && sha256 == record.sha256 && modification == record.modification
            && creation == record.creation
    }
}

/// What was observed after an operation. Which fields are present depends on the operation; any other
/// combination is refused by the transition rules.
public struct JournalObservation: Codable, Equatable, Sendable {
    /// `evacuateFile`: "rename" or "copy".
    public var method: String?
    public var staged: ObservedFile?
    public var sourcePresent: Bool?
    public var source: ObservedFile?
    /// `removeRegistration`: the number of mapped registrations not yet verified as removed, counting the target
    /// of this operation as removed.
    public var remainingCount: Int?
    public var registrationCount: Int?
    public var musicRunning: Bool?
    public var result: ObservedFile?
    /// `applyFile`, optional: the absolute path of the file after the application, strictly inside the staging
    /// directory. When absent, the result is at the staging path that is the target.
    public var resultPath: String?
    public var newPersistentIDs: [String]?
    public var laterThanPreviousAlbum: Bool?
    /// `confirmDisplay`: the order of the albums' exposed addition dates, newest first. It is not an observation of
    /// the Music window.
    public var observed: [String]?

    public init(
        method: String? = nil, staged: ObservedFile? = nil, sourcePresent: Bool? = nil, source: ObservedFile? = nil,
        remainingCount: Int? = nil, registrationCount: Int? = nil, musicRunning: Bool? = nil,
        result: ObservedFile? = nil, resultPath: String? = nil, newPersistentIDs: [String]? = nil,
        laterThanPreviousAlbum: Bool? = nil, observed: [String]? = nil
    ) {
        self.method = method
        self.staged = staged
        self.sourcePresent = sourcePresent
        self.source = source
        self.remainingCount = remainingCount
        self.registrationCount = registrationCount
        self.musicRunning = musicRunning
        self.result = result
        self.resultPath = resultPath
        self.newPersistentIDs = newPersistentIDs
        self.laterThanPreviousAlbum = laterThanPreviousAlbum
        self.observed = observed
    }

    /// The names of the fields that are present.
    var presentFields: Set<String> {
        var names = Set<String>()
        if method != nil { names.insert("method") }
        if staged != nil { names.insert("staged") }
        if sourcePresent != nil { names.insert("sourcePresent") }
        if source != nil { names.insert("source") }
        if remainingCount != nil { names.insert("remainingCount") }
        if registrationCount != nil { names.insert("registrationCount") }
        if musicRunning != nil { names.insert("musicRunning") }
        if result != nil { names.insert("result") }
        if resultPath != nil { names.insert("resultPath") }
        if newPersistentIDs != nil { names.insert("newPersistentIDs") }
        if laterThanPreviousAlbum != nil { names.insert("laterThanPreviousAlbum") }
        if observed != nil { names.insert("observed") }
        return names
    }
}

/// The body of the header entry, which binds the journal to one recovery record.
public struct JournalHeader: Codable, Equatable, Sendable {
    /// The only accepted scope.
    public static let wholeLibraryScope = "whole-library"

    /// The sealed `checksum` of the record.
    public let recordChecksum: String
    /// The SHA-256 (lowercase hexadecimal) of the exact bytes of `rebuild-record.json`.
    public let recordFileSHA256: String
    public let ilibraryVersion: String
    public let scope: String

    public init(
        recordChecksum: String, recordFileSHA256: String, ilibraryVersion: String,
        scope: String = JournalHeader.wholeLibraryScope
    ) {
        self.recordChecksum = recordChecksum
        self.recordFileSHA256 = recordFileSHA256
        self.ilibraryVersion = ilibraryVersion
        self.scope = scope
    }
}

/// The kind-specific content of an entry.
public enum JournalBody: Equatable, Sendable {
    case header(JournalHeader)
    case stageBegan(RebuildStage)
    /// Recorded before an operation is performed. It claims nothing about the outcome.
    case intent(operation: RebuildOperation, target: String)
    /// The return of the operation as reported by the caller. A return, even a successful one, is not a
    /// verification.
    case returned(operation: RebuildOperation, target: String, succeeded: Bool, detail: String)
    /// The independent observation that the operation took effect.
    case verified(operation: RebuildOperation, target: String, observation: JournalObservation)
    /// A deliberate stop. It resolves nothing.
    case stopped(reason: String)
    case stageCompleted(RebuildStage)

    static let knownKinds: Set<String> = [
        "header", "stageBegan", "intent", "returned", "verified", "stopped", "stageCompleted",
    ]

    public var kind: String {
        switch self {
        case .header: "header"
        case .stageBegan: "stageBegan"
        case .intent: "intent"
        case .returned: "returned"
        case .verified: "verified"
        case .stopped: "stopped"
        case .stageCompleted: "stageCompleted"
        }
    }
}

extension JournalBody: Encodable {
    private struct StagePayload: Codable { let stage: RebuildStage }
    private struct IntentPayload: Codable {
        let operation: RebuildOperation
        let target: String
    }
    private struct ReturnedPayload: Codable {
        let operation: RebuildOperation
        let target: String
        let succeeded: Bool
        let detail: String
    }
    private struct VerifiedPayload: Codable {
        let operation: RebuildOperation
        let target: String
        let observation: JournalObservation
    }
    private struct StoppedPayload: Codable { let reason: String }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .header(let header): try header.encode(to: encoder)
        case .stageBegan(let stage), .stageCompleted(let stage): try StagePayload(stage: stage).encode(to: encoder)
        case .intent(let operation, let target):
            try IntentPayload(operation: operation, target: target).encode(to: encoder)
        case .returned(let operation, let target, let succeeded, let detail):
            try ReturnedPayload(operation: operation, target: target, succeeded: succeeded, detail: detail).encode(
                to: encoder)
        case .verified(let operation, let target, let observation):
            try VerifiedPayload(operation: operation, target: target, observation: observation).encode(to: encoder)
        case .stopped(let reason): try StoppedPayload(reason: reason).encode(to: encoder)
        }
    }

    static func decode(kind: String, sequence: Int, from container: KeyedDecodingContainer<JournalEntry.CodingKeys>)
        throws -> JournalBody
    {
        let key = JournalEntry.CodingKeys.body
        switch kind {
        case "header": return .header(try container.decode(JournalHeader.self, forKey: key))
        case "stageBegan": return .stageBegan(try container.decode(StagePayload.self, forKey: key).stage)
        case "stageCompleted": return .stageCompleted(try container.decode(StagePayload.self, forKey: key).stage)
        case "intent":
            let payload = try container.decode(IntentPayload.self, forKey: key)
            return .intent(operation: payload.operation, target: payload.target)
        case "returned":
            let payload = try container.decode(ReturnedPayload.self, forKey: key)
            return .returned(
                operation: payload.operation, target: payload.target, succeeded: payload.succeeded,
                detail: payload.detail)
        case "verified":
            let payload = try container.decode(VerifiedPayload.self, forKey: key)
            return .verified(operation: payload.operation, target: payload.target, observation: payload.observation)
        case "stopped": return .stopped(reason: try container.decode(StoppedPayload.self, forKey: key).reason)
        default: throw ProgressJournalError.unsupportedEntryKind(kind, sequence)
        }
    }
}

/// One line of the journal: a canonical JSON object with a checksum over its own canonical encoding.
///
/// The checksum and the chain guard against accidental corruption and against an inconsistent edit. They are not
/// a security measure, because anyone who can edit the file can recompute them, and they cannot reveal the removal
/// of a valid suffix; see `ProgressJournal.reconcile`.
public struct JournalEntry: Equatable, Sendable {
    public static let formatIdentifier = "ilibrary-rebuild-journal-1"

    public let format: String
    public let sequence: Int
    /// For sequence 0, the SHA-256 of the record file; otherwise the checksum of the previous entry.
    public let previous: String
    public let body: JournalBody
    /// UTC ISO 8601. Informational only; ordering is by sequence.
    public let recordedAt: String
    public let checksum: String

    public var kind: String { body.kind }

    /// Creates a sealed entry.
    public init(sequence: Int, previous: String, body: JournalBody, recordedAt: String) throws {
        let unsealed = JournalEntry(
            format: JournalEntry.formatIdentifier, sequence: sequence, previous: previous, body: body,
            recordedAt: recordedAt, checksum: "")
        let digest = SHA256.digest(of: try unsealed.canonicalData()).hex
        self.init(
            format: JournalEntry.formatIdentifier, sequence: sequence, previous: previous, body: body,
            recordedAt: recordedAt, checksum: digest)
    }

    private init(
        format: String, sequence: Int, previous: String, body: JournalBody, recordedAt: String, checksum: String
    ) {
        self.format = format
        self.sequence = sequence
        self.previous = previous
        self.body = body
        self.recordedAt = recordedAt
        self.checksum = checksum
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// The canonical encoding that the checksum covers: sorted keys, compact, with an empty checksum.
    func canonicalData() throws -> Data {
        let unsealed = JournalEntry(
            format: format, sequence: sequence, previous: previous, body: body, recordedAt: recordedAt, checksum: "")
        return try JournalEntry.encoder().encode(unsealed)
    }

    /// The line as stored: the canonical encoding followed by exactly one newline.
    public func line() throws -> Data {
        var data = try JournalEntry.encoder().encode(self)
        data.append(0x0A)
        return data
    }

    /// True when the checksum equals the SHA-256 of the canonical encoding with an empty checksum.
    func checksumIsValid() throws -> Bool { checksum == SHA256.digest(of: try canonicalData()).hex }
}

extension JournalEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case format, sequence, previous, kind, body, recordedAt, checksum
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let format = try container.decode(String.self, forKey: .format)
        let sequence = try container.decode(Int.self, forKey: .sequence)
        let kind = try container.decode(String.self, forKey: .kind)
        guard format == JournalEntry.formatIdentifier else {
            throw ProgressJournalError.unsupportedFormat(format, sequence)
        }
        self.init(
            format: format, sequence: sequence, previous: try container.decode(String.self, forKey: .previous),
            body: try JournalBody.decode(kind: kind, sequence: sequence, from: container),
            recordedAt: try container.decode(String.self, forKey: .recordedAt),
            checksum: try container.decode(String.self, forKey: .checksum))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(previous, forKey: .previous)
        try container.encode(kind, forKey: .kind)
        try container.encode(body, forKey: .body)
        try container.encode(recordedAt, forKey: .recordedAt)
        try container.encode(checksum, forKey: .checksum)
    }
}
