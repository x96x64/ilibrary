import Foundation

/// A reason for which a proposed or recorded entry does not follow from the state before it.
public enum TransitionProblem: Equatable, Sendable {
    case notNextSequence(expected: Int, found: Int)
    case notChained
    case headerRepeated
    /// The first entry after the header, and every stage that follows another, must begin the next stage.
    case stageOutOfOrder(expected: RebuildStage?, found: RebuildStage)
    case stageAlreadyBegun(RebuildStage)
    case stageNotCompleted(current: RebuildStage)
    case noStageBegun
    /// No entry other than `stopped` may follow the completion of the last stage.
    case entryAfterFinalStage
    case stageNotCurrent(stage: RebuildStage, current: RebuildStage?)
    case stageIncomplete(stage: RebuildStage, missing: [String])
    case operationNotInStage(operation: RebuildOperation, stage: RebuildStage, current: RebuildStage)
    case unresolvedOperation(operation: RebuildOperation, target: String)
    case noOpenOperation
    case operationMismatch(open: RebuildOperation, openTarget: String, found: RebuildOperation, foundTarget: String)
    case duplicateOperation(operation: RebuildOperation, target: String)
    case duplicateReturn(operation: RebuildOperation, target: String)
    case duplicateVerification(operation: RebuildOperation, target: String)
    case notReturned(operation: RebuildOperation, target: String)
    case returnNotSucceeded(operation: RebuildOperation, target: String)
    case targetNotInPlan(operation: RebuildOperation, target: String)
    case targetOutOfOrder(operation: RebuildOperation, expected: String, found: String)
    case prerequisiteMissing(operation: RebuildOperation, requires: String)
    /// The reported result path of an `applyFile` operation is not an absolute, normalized path strictly inside
    /// the staging directory, or it equals the result of an earlier application or a staging path of another file.
    case resultPathInvalid(target: String, resultPath: String)
    case observationShape(operation: RebuildOperation, missing: [String], unexpected: [String])
    case unknownEvacuationMethod(String)
    case stagedFileDiffers(target: String)
    case sourceStateInconsistent(target: String, method: String)
    /// The reported number of mapped registrations not yet verified as removed differs from the number that the
    /// journal and the record imply, counting the target of the operation as removed.
    case remainingCountWrong(expected: Int, found: Int)
    case registrationCountNotZero(Int)
    case musicRunning(operation: RebuildOperation)
    case newPersistentIDsEmpty
    case newPersistentIDMalformed(String)
    case newPersistentIDNotDisjoint(String)
    case albumNotLater(target: String)
    case displayListDiffers(expected: [String], found: [String])
}

/// The failures of reading, parsing, replaying, and writing a progress journal.
public enum ProgressJournalError: Error, Equatable, Sendable {
    case notADirectory(path: String)
    /// The path is absent, a symbolic link, or not a regular file.
    case notARegularFile(path: String)
    case alreadyExists(path: String)
    case unreadable(path: String, reason: String)
    /// The file has a hard link, another owner, or write permission for the group or others.
    case unsafeFile(path: String, reason: String)
    /// Another descriptor holds the advisory lock.
    case locked(path: String)
    case empty
    /// The final entry is incomplete or fails its checksum while every earlier entry is valid. It is never
    /// ignored or truncated automatically.
    case tornFinalEntry
    /// An entry other than the final one is not a JSON object.
    case corruptEntry(Int)
    case unsupportedFormat(String, Int)
    case unsupportedEntryKind(String, Int)
    case malformedEntry(Int, String)
    case checksumMismatch(Int)
    case sequenceGap(expected: Int, found: Int)
    case brokenChain(Int)
    case headerMissing
    /// The header does not bind the supplied record file bytes and checksum.
    case recordMismatch
    case unsupportedScope(String)
    case invalidTransition(Int, TransitionProblem)
    /// A proposed entry was refused before anything was written.
    case invalidEntry([TransitionProblem])
    /// The journal head is not the expected one.
    case concurrentModification(expected: JournalHead, found: JournalHead)
    /// Nothing was written.
    case writeFailed(String)
    /// The journal file may exist and contain bytes. It is left in place as evidence.
    case creationUncertain(String)
    /// A write may have started. The outcome is unknown and is never retried automatically.
    case appendUncertain(String)
}

/// The position of the last entry of a journal.
public struct JournalHead: Equatable, Sendable {
    public let sequence: Int
    public let checksum: String

    public init(sequence: Int, checksum: String) {
        self.sequence = sequence
        self.checksum = checksum
    }
}

/// An operation whose intent has been recorded and which has not been verified.
public struct OpenOperation: Equatable, Sendable {
    public let operation: RebuildOperation
    public let target: String
    public let returned: Bool
    /// True when the recorded return reported failure. No entry resolves such an operation, so the journal cannot
    /// proceed past it.
    public let returnFailed: Bool
}

/// The state that a journal implies. It claims an operation only when a verification was recorded, never on the
/// basis of an intent or a return.
public struct RebuildProgress: Equatable, Sendable {
    public internal(set) var head: JournalHead
    public internal(set) var completedStages: [RebuildStage] = []
    /// The stage that has begun and has not been completed.
    public internal(set) var currentStage: RebuildStage?
    /// The verified targets of each operation, in the order of verification.
    public internal(set) var verifiedTargets: [RebuildOperation: [String]] = [:]
    public internal(set) var openOperation: OpenOperation?
    /// The persistent IDs of the added tracks, in uppercase, in the order of verification.
    public internal(set) var newPersistentIDs: [String] = []
    /// The method of each verified evacuation, by source path.
    public internal(set) var evacuationMethods: [String: String] = [:]
    /// The result path of each verified `applyFile` operation, by its target (the staging path). The result path is
    /// the `resultPath` of the observation when present and otherwise the target itself.
    public internal(set) var appliedPaths: [String: String] = [:]
    public internal(set) var stopCount = 0

    // Derived lookups. They are maintained by `advance` alongside the ordered collections above, they carry no
    // information that those collections lack, and they are excluded from equality.

    /// The verified targets of each operation in their canonical form, as a set.
    var verifiedSets: [RebuildOperation: Set<String>] = [:]
    /// Every element of `newPersistentIDs`.
    var newPersistentIDSet: Set<String> = []
    /// The `PathKey.key` of every value of `appliedPaths`.
    var appliedPathKeys: Set<String> = []

    /// False when an operation is open or unresolved.
    public var canProceed: Bool { openOperation == nil }

    /// True when `target` (in its canonical form) has been verified for `operation`.
    public func isVerified(_ operation: RebuildOperation, _ target: String) -> Bool {
        verifiedSets[operation]?.contains(target) ?? false
    }

    func verifiedCount(_ operation: RebuildOperation) -> Int { verifiedSets[operation]?.count ?? 0 }

    public static func == (lhs: RebuildProgress, rhs: RebuildProgress) -> Bool {
        lhs.head == rhs.head && lhs.completedStages == rhs.completedStages && lhs.currentStage == rhs.currentStage
            && lhs.verifiedTargets == rhs.verifiedTargets && lhs.openOperation == rhs.openOperation
            && lhs.newPersistentIDs == rhs.newPersistentIDs && lhs.evacuationMethods == rhs.evacuationMethods
            && lhs.appliedPaths == rhs.appliedPaths && lhs.stopCount == rhs.stopCount
    }
}

/// Writing, parsing, and replaying the journal as pure functions of bytes, entries, and the recovery record.
public enum ProgressJournal {
    public static let fileName = "rebuild-journal.jsonl"

    /// The only target of a `confirmDisplay` operation. The `observed` list of its verification is the order of
    /// the exposed addition dates of the albums, newest first. It is not an observation of the Music window.
    public static let displayTarget = "date-added-order"

    // MARK: Parsing

    /// Parses the bytes of a journal into entries. It checks, for every line in order, the JSON syntax, the
    /// format, the kind, the fields, the checksum, the canonical form, the sequence, and the chain. It does not
    /// need the recovery record; `replay` binds the header to it.
    public static func parse(_ data: Data) throws -> [JournalEntry] {
        guard !data.isEmpty else { throw ProgressJournalError.empty }
        var segments = data.split(separator: 0x0A, omittingEmptySubsequences: false).map { Data($0) }
        let terminated = data.last == 0x0A
        if terminated { segments.removeLast() }
        var entries: [JournalEntry] = []
        for (index, line) in segments.enumerated() {
            let isFinal = index == segments.count - 1
            if isFinal && !terminated { throw ProgressJournalError.tornFinalEntry }
            let entry = try parseLine(line, index: index, isFinal: isFinal)
            if entry.sequence != index {
                throw ProgressJournalError.sequenceGap(expected: index, found: entry.sequence)
            }
            if index > 0 {
                guard entry.previous == entries[index - 1].checksum else {
                    throw ProgressJournalError.brokenChain(index)
                }
            } else if case .header(let header) = entry.body, header.recordFileSHA256 != entry.previous {
                throw ProgressJournalError.malformedEntry(0, "the header digest differs from the previous field")
            }
            entries.append(entry)
        }
        return entries
    }

    static func parseLine(_ line: Data, index: Int, isFinal: Bool) throws -> JournalEntry {
        let invalid: ProgressJournalError = isFinal ? .tornFinalEntry : .corruptEntry(index)
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { throw invalid }
        guard let format = object["format"] as? String else {
            throw ProgressJournalError.malformedEntry(index, "the format is missing")
        }
        guard format == JournalEntry.formatIdentifier else {
            throw ProgressJournalError.unsupportedFormat(format, index)
        }
        guard let kind = object["kind"] as? String else {
            throw ProgressJournalError.malformedEntry(index, "the kind is missing")
        }
        guard JournalBody.knownKinds.contains(kind) else {
            throw ProgressJournalError.unsupportedEntryKind(kind, index)
        }
        let entry: JournalEntry
        do {
            entry = try JSONDecoder().decode(JournalEntry.self, from: line)
        } catch let error as ProgressJournalError {
            throw error
        } catch {
            throw ProgressJournalError.malformedEntry(index, "\(error)")
        }
        guard try entry.checksumIsValid() else {
            throw isFinal ? ProgressJournalError.tornFinalEntry : ProgressJournalError.checksumMismatch(index)
        }
        var canonical = try entry.line()
        canonical.removeLast()
        guard canonical == line else {
            throw ProgressJournalError.malformedEntry(index, "the line is not the canonical encoding")
        }
        guard RecoveryRecord.isUTCTimestamp(entry.recordedAt) else {
            throw ProgressJournalError.malformedEntry(index, "recordedAt is not a UTC ISO 8601 time")
        }
        return entry
    }

    // MARK: Replay

    /// Replays parsed entries against the verified record and the exact bytes of its file, and returns the
    /// progress that they imply, or throws the first violation.
    ///
    /// A valid prefix of a journal replays successfully: the format cannot detect the removal of a valid suffix or
    /// the substitution of an older valid journal, because no independent trusted checkpoint records the head.
    /// `reconcile` compares the replayed progress with observed external state for that purpose.
    public static func replay(record: RecoveryRecord, recordBytes: Data, entries: [JournalEntry]) throws
        -> RebuildProgress
    {
        try replayIndexed(record: record, recordBytes: recordBytes, entries: entries).progress
    }

    /// The replay together with the index of the record that it built, which a caller may keep for later entries.
    static func replayIndexed(record: RecoveryRecord, recordBytes: Data, entries: [JournalEntry]) throws
        -> (progress: RebuildProgress, index: RecordIndex)
    {
        guard let first = entries.first, first.sequence == 0, case .header(let header) = first.body else {
            throw ProgressJournalError.headerMissing
        }
        let fileDigest = SHA256.digest(of: recordBytes).hex
        guard header.recordChecksum == record.checksum, header.recordFileSHA256 == fileDigest,
            first.previous == fileDigest, (try? RecoveryRecord.parse(recordBytes)) == record
        else { throw ProgressJournalError.recordMismatch }
        guard header.scope == JournalHeader.wholeLibraryScope else {
            throw ProgressJournalError.unsupportedScope(header.scope)
        }
        let index = RecordIndex(record)
        var progress = RebuildProgress(head: JournalHead(sequence: 0, checksum: first.checksum))
        for entry in entries.dropFirst() {
            let found = nextEntryProblems(index: index, record: record, progress: progress, entry: entry)
            if let problem = found.first { throw ProgressJournalError.invalidTransition(entry.sequence, problem) }
            progress.advance(with: entry, record: record)
        }
        return (progress, index)
    }

    /// Parses and replays in one step.
    public static func load(data: Data, record: RecoveryRecord, recordBytes: Data) throws
        -> (entries: [JournalEntry], progress: RebuildProgress)
    {
        let loaded = try loadIndexed(data: data, record: record, recordBytes: recordBytes)
        return (loaded.entries, loaded.progress)
    }

    static func loadIndexed(data: Data, record: RecoveryRecord, recordBytes: Data) throws
        -> (entries: [JournalEntry], progress: RebuildProgress, index: RecordIndex)
    {
        let entries = try parse(data)
        let replayed = try replayIndexed(record: record, recordBytes: recordBytes, entries: entries)
        return (entries, replayed.progress, replayed.index)
    }

    // MARK: Transition rules

    /// Every reason for which `entry` may not follow `progress`. The replay and the writer share this function,
    /// so the writer refuses an invalid entry before anything is written.
    ///
    /// Each call indexes the record at a cost proportional to its size; the replay and
    /// `ProgressJournalFile.append(_:to:state:...)` build the index once for many entries.
    public static func nextEntryProblems(record: RecoveryRecord, progress: RebuildProgress, entry: JournalEntry)
        -> [TransitionProblem]
    {
        nextEntryProblems(index: RecordIndex(record), record: record, progress: progress, entry: entry)
    }

    static func nextEntryProblems(
        index: RecordIndex, record: RecoveryRecord, progress: RebuildProgress, entry: JournalEntry
    ) -> [TransitionProblem] {
        var found: [TransitionProblem] = []
        if entry.sequence != progress.head.sequence + 1 {
            found.append(.notNextSequence(expected: progress.head.sequence + 1, found: entry.sequence))
        }
        if entry.previous != progress.head.checksum { found.append(.notChained) }
        found += bodyProblems(index: index, record: record, progress: progress, body: entry.body)
        return found
    }

    private static func bodyProblems(
        index: RecordIndex, record: RecoveryRecord, progress: RebuildProgress, body: JournalBody
    ) -> [TransitionProblem] {
        switch body {
        case .header: return [.headerRepeated]
        case .stopped: return []
        default: break
        }
        if progress.completedStages.contains(.display) { return [.entryAfterFinalStage] }
        switch body {
        case .stageBegan(let stage): return beginProblems(progress: progress, stage: stage)
        case .stageCompleted(let stage): return completionProblems(record: record, progress: progress, stage: stage)
        case .intent(let operation, let target):
            return intentProblems(
                index: index, record: record, progress: progress, operation: operation, target: target)
        case .returned(let operation, let target, _, _):
            return resolutionProblems(progress: progress, operation: operation, target: target, verifying: false)
        case .verified(let operation, let target, let observation):
            let found = resolutionProblems(progress: progress, operation: operation, target: target, verifying: true)
            if !found.isEmpty { return found }
            return observationProblems(
                index: index, record: record, progress: progress, operation: operation, target: target,
                observation: observation)
        case .header, .stopped: return []
        }
    }

    private static func beginProblems(progress: RebuildProgress, stage: RebuildStage) -> [TransitionProblem] {
        if let open = progress.openOperation {
            return [.unresolvedOperation(operation: open.operation, target: open.target)]
        }
        if progress.completedStages.contains(stage) || progress.currentStage == stage {
            return [.stageAlreadyBegun(stage)]
        }
        if let current = progress.currentStage { return [.stageNotCompleted(current: current)] }
        let order = RebuildStage.allCases
        let expected = progress.completedStages.count < order.count ? order[progress.completedStages.count] : nil
        return stage == expected ? [] : [.stageOutOfOrder(expected: expected, found: stage)]
    }

    private static func completionProblems(record: RecoveryRecord, progress: RebuildProgress, stage: RebuildStage)
        -> [TransitionProblem]
    {
        if let open = progress.openOperation {
            return [.unresolvedOperation(operation: open.operation, target: open.target)]
        }
        guard let current = progress.currentStage else { return [.stageNotCurrent(stage: stage, current: nil)] }
        guard current == stage else { return [.stageNotCurrent(stage: stage, current: current)] }
        var missing: [String] = []
        switch stage {
        case .evacuation:
            missing = record.evacuation.map(\.sourcePath).filter { !progress.isVerified(.evacuateFile, $0) }
        case .clearing:
            let removed = progress.verifiedSets[.removeRegistration] ?? []
            missing = record.mapping.map { $0.persistentID.uppercased() }.filter { !removed.contains($0) }
            for operation in [RebuildOperation.confirmLibraryEmpty, .terminateMusic]
            where progress.verifiedCount(operation) == 0 {
                missing.append(operation.rawValue)
            }
        case .application:
            missing = record.evacuation.map(\.stagingPath).filter { !progress.isVerified(.applyFile, $0) }
        case .addition:
            missing = record.additionList.filter { !progress.isVerified(.addAlbum, $0) }
        case .display:
            missing = progress.isVerified(.confirmDisplay, displayTarget) ? [] : [displayTarget]
        }
        return missing.isEmpty ? [] : [.stageIncomplete(stage: stage, missing: missing)]
    }

    private static func intentProblems(
        index: RecordIndex, record: RecoveryRecord, progress: RebuildProgress, operation: RebuildOperation,
        target: String
    ) -> [TransitionProblem] {
        if let open = progress.openOperation {
            return [.unresolvedOperation(operation: open.operation, target: open.target)]
        }
        guard let current = progress.currentStage else { return [.noStageBegun] }
        guard operation.stage == current else {
            return [.operationNotInStage(operation: operation, stage: operation.stage, current: current)]
        }
        let inPlan =
            switch operation {
            case .evacuateFile: index.evacuationBySourcePath[target] != nil
            case .removeRegistration: index.mappedIDs.contains(target.uppercased())
            case .confirmLibraryEmpty, .terminateMusic: target.isEmpty
            case .applyFile: index.evacuationByStagingPath[target] != nil
            case .addAlbum: index.additionPositions[target] != nil
            case .confirmDisplay: target == displayTarget
            }
        guard inPlan else { return [.targetNotInPlan(operation: operation, target: target)] }
        let canonical = canonicalTarget(operation, target)
        if progress.isVerified(operation, canonical) {
            return [.duplicateOperation(operation: operation, target: target)]
        }
        switch operation {
        case .confirmLibraryEmpty:
            // Every verified removal is a mapped registration, so the counts are equal exactly when all are removed.
            if progress.verifiedCount(.removeRegistration) < index.mappedIDs.count {
                return [.prerequisiteMissing(operation: operation, requires: "removal of every mapped registration")]
            }
        case .terminateMusic:
            if progress.verifiedCount(.confirmLibraryEmpty) == 0 {
                return [
                    .prerequisiteMissing(operation: operation, requires: RebuildOperation.confirmLibraryEmpty.rawValue)
                ]
            }
        case .addAlbum:
            let next = progress.verifiedCount(.addAlbum)
            if next < record.additionList.count, record.additionList[next] != target {
                return [.targetOutOfOrder(operation: operation, expected: record.additionList[next], found: target)]
            }
        default: break
        }
        return []
    }

    /// The stored spelling of a target: persistent IDs are compared case-insensitively and kept in uppercase.
    public static func canonicalTarget(_ operation: RebuildOperation, _ target: String) -> String {
        operation == .removeRegistration ? target.uppercased() : target
    }

    /// The rules shared by `returned` and `verified`.
    private static func resolutionProblems(
        progress: RebuildProgress, operation: RebuildOperation, target: String, verifying: Bool
    ) -> [TransitionProblem] {
        guard let open = progress.openOperation else {
            if progress.isVerified(operation, canonicalTarget(operation, target)) {
                return [
                    verifying
                        ? .duplicateVerification(operation: operation, target: target)
                        : .duplicateReturn(operation: operation, target: target)
                ]
            }
            return [.noOpenOperation]
        }
        guard open.operation == operation, open.target == target else {
            return [
                .operationMismatch(
                    open: open.operation, openTarget: open.target, found: operation, foundTarget: target)
            ]
        }
        if verifying {
            if !open.returned { return [.notReturned(operation: operation, target: target)] }
            if open.returnFailed { return [.returnNotSucceeded(operation: operation, target: target)] }
        } else if open.returned {
            return [.duplicateReturn(operation: operation, target: target)]
        }
        return []
    }

    // MARK: Observations

    private static func fieldRules(_ operation: RebuildOperation) -> (required: Set<String>, optional: Set<String>) {
        switch operation {
        case .evacuateFile: (["method", "staged", "sourcePresent"], ["source"])
        case .removeRegistration: (["remainingCount"], [])
        case .confirmLibraryEmpty: (["registrationCount"], [])
        case .terminateMusic: (["musicRunning"], [])
        case .applyFile: (["musicRunning", "result"], ["resultPath"])
        case .addAlbum: (["newPersistentIDs", "laterThanPreviousAlbum"], [])
        case .confirmDisplay: (["observed"], [])
        }
    }

    private static func observationProblems(
        index: RecordIndex, record: RecoveryRecord, progress: RebuildProgress, operation: RebuildOperation,
        target: String, observation: JournalObservation
    ) -> [TransitionProblem] {
        let rules = fieldRules(operation)
        let present = observation.presentFields
        let missing = rules.required.subtracting(present).sorted()
        let unexpected = present.subtracting(rules.required).subtracting(rules.optional).sorted()
        if !missing.isEmpty || !unexpected.isEmpty {
            return [.observationShape(operation: operation, missing: missing, unexpected: unexpected)]
        }
        switch operation {
        case .evacuateFile:
            guard let expected = index.inventoryByKey[PathKey.key(target)]
            else { return [.targetNotInPlan(operation: operation, target: target)] }
            let method = observation.method ?? ""
            guard observation.staged?.matches(expected) == true else { return [.stagedFileDiffers(target: target)] }
            switch method {
            case "rename":
                if observation.sourcePresent != false || observation.source != nil {
                    return [.sourceStateInconsistent(target: target, method: method)]
                }
            case "copy":
                if observation.sourcePresent != true || observation.source?.matches(expected) != true {
                    return [.sourceStateInconsistent(target: target, method: method)]
                }
            default: return [.unknownEvacuationMethod(method)]
            }
        case .removeRegistration:
            // The target is a mapped registration that has not been verified yet, because its intent was accepted.
            let removed = progress.verifiedCount(.removeRegistration)
            let targetIsNew = progress.isVerified(.removeRegistration, target.uppercased()) ? 0 : 1
            let expected = index.mappedIDs.count - removed - targetIsNew
            let reported = observation.remainingCount ?? 0
            if reported != expected { return [.remainingCountWrong(expected: expected, found: reported)] }
        case .confirmLibraryEmpty:
            if let count = observation.registrationCount, count != 0 { return [.registrationCountNotZero(count)] }
        case .terminateMusic:
            if observation.musicRunning != false { return [.musicRunning(operation: operation)] }
        case .applyFile:
            if observation.musicRunning != false { return [.musicRunning(operation: operation)] }
            if let resultPath = observation.resultPath,
                !resultPathIsAcceptable(
                    index: index, record: record, progress: progress, target: target, resultPath: resultPath)
            {
                return [.resultPathInvalid(target: target, resultPath: resultPath)]
            }
        case .addAlbum:
            let ids = (observation.newPersistentIDs ?? []).map { $0.uppercased() }
            if ids.isEmpty { return [.newPersistentIDsEmpty] }
            var batch = Set<String>()
            for (id, raw) in zip(ids, observation.newPersistentIDs ?? []) {
                if !RegistrationRecord.isWellFormedID(raw) { return [.newPersistentIDMalformed(raw)] }
                let known = index.mappedIDs.contains(id) || progress.newPersistentIDSet.contains(id)
                if known || !batch.insert(id).inserted { return [.newPersistentIDNotDisjoint(raw)] }
            }
            if observation.laterThanPreviousAlbum != true { return [.albumNotLater(target: target)] }
        case .confirmDisplay:
            let observed = observation.observed ?? []
            if observed != record.expectedDisplayList {
                return [.displayListDiffers(expected: record.expectedDisplayList, found: observed)]
            }
        }
        return []
    }

    /// True when `resultPath` is an absolute, normalized path strictly inside the staging directory that differs
    /// from every earlier result and from every staging path of the record other than `target`.
    private static func resultPathIsAcceptable(
        index: RecordIndex, record: RecoveryRecord, progress: RebuildProgress, target: String, resultPath: String
    ) -> Bool {
        guard PathKey.invalidReason(resultPath) == nil, resultPath != "/",
            PathKey.relation(resultPath, record.locations.stagingDirectory) == .firstInsideSecond
        else { return false }
        let key = PathKey.key(resultPath)
        if progress.appliedPathKeys.contains(key) { return false }
        return key == PathKey.key(target) || !index.stagingKeys.contains(key)
    }
}

extension RebuildProgress {
    init(head: JournalHead) { self.head = head }

    /// Applies an entry that `nextEntryProblems` accepted. It records nothing beyond what the entry states.
    mutating func advance(with entry: JournalEntry, record: RecoveryRecord) {
        head = JournalHead(sequence: entry.sequence, checksum: entry.checksum)
        switch entry.body {
        case .header: break
        case .stageBegan(let stage): currentStage = stage
        case .stageCompleted(let stage):
            completedStages.append(stage)
            currentStage = nil
        case .intent(let operation, let target):
            openOperation = OpenOperation(operation: operation, target: target, returned: false, returnFailed: false)
        case .returned(_, _, let succeeded, _):
            if let open = openOperation {
                openOperation = OpenOperation(
                    operation: open.operation, target: open.target, returned: true, returnFailed: !succeeded)
            }
        case .verified(let operation, let target, let observation):
            let canonical = ProgressJournal.canonicalTarget(operation, target)
            verifiedTargets[operation, default: []].append(canonical)
            verifiedSets[operation, default: []].insert(canonical)
            openOperation = nil
            if operation == .evacuateFile { evacuationMethods[target] = observation.method ?? "" }
            if operation == .applyFile {
                let result = observation.resultPath ?? target
                appliedPaths[target] = result
                appliedPathKeys.insert(PathKey.key(result))
            }
            if operation == .addAlbum {
                let added = (observation.newPersistentIDs ?? []).map { $0.uppercased() }
                newPersistentIDs += added
                newPersistentIDSet.formUnion(added)
            }
        case .stopped: stopCount += 1
        }
    }
}
