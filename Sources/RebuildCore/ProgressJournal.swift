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
    /// No detector for the emptiness of the Music window has been qualified. This is the unresolved M12 gate.
    case guiEmptinessMethodNotQualified
    case observationShape(operation: RebuildOperation, missing: [String], unexpected: [String])
    case unknownEvacuationMethod(String)
    case stagedFileDiffers(target: String)
    case sourceStateInconsistent(target: String, method: String)
    case remainingSetWrong(expected: [String], found: [String])
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
    /// True when the recorded return reported failure. This phase offers no entry that resolves such an
    /// operation; resolution belongs to the reconciliation of M13.
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
    public internal(set) var stopCount = 0

    /// False when an operation is open or unresolved.
    public var canProceed: Bool { openOperation == nil }

    public func isVerified(_ operation: RebuildOperation, _ target: String) -> Bool {
        verifiedTargets[operation]?.contains(target) ?? false
    }

    func verified(_ operation: RebuildOperation) -> [String] { verifiedTargets[operation] ?? [] }
}

/// Writing, parsing, and replaying the journal as pure functions of bytes, entries, and the recovery record.
public enum ProgressJournal {
    public static let fileName = "rebuild-journal.jsonl"

    /// The methods that qualify as evidence that the Music window shows an empty library.
    ///
    /// This set is empty, and that is the unresolved M12 gate. No detector for the emptiness of the graphical
    /// library has been qualified, and a manual confirmation is deliberately not accepted as a substitute.
    /// While the set is empty, every intent of `establishGUIEmptiness` is refused, so that neither
    /// `terminateMusic` nor the completion of the clearing stage can be recorded. The set is a constant: no
    /// production code path adds a method.
    static let qualifiedGUIEmptinessMethods: Set<String> = []

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

    private static func parseLine(_ line: Data, index: Int, isFinal: Bool) throws -> JournalEntry {
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
        try replay(
            record: record, recordBytes: recordBytes, entries: entries,
            acceptedGUIEmptinessMethods: qualifiedGUIEmptinessMethods)
    }

    static func replay(
        record: RecoveryRecord, recordBytes: Data, entries: [JournalEntry], acceptedGUIEmptinessMethods: Set<String>
    ) throws -> RebuildProgress {
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
        var progress = RebuildProgress(head: JournalHead(sequence: 0, checksum: first.checksum))
        for entry in entries.dropFirst() {
            let found = nextEntryProblems(
                record: record, progress: progress, entry: entry,
                acceptedGUIEmptinessMethods: acceptedGUIEmptinessMethods)
            if let problem = found.first { throw ProgressJournalError.invalidTransition(entry.sequence, problem) }
            progress.advance(with: entry, record: record)
        }
        return progress
    }

    /// Parses and replays in one step.
    public static func load(data: Data, record: RecoveryRecord, recordBytes: Data) throws
        -> (entries: [JournalEntry], progress: RebuildProgress)
    {
        let entries = try parse(data)
        return (entries, try replay(record: record, recordBytes: recordBytes, entries: entries))
    }

    // MARK: Transition rules

    /// Every reason for which `entry` may not follow `progress`. The replay and the writer share this function,
    /// so the writer refuses an invalid entry before anything is written.
    public static func nextEntryProblems(record: RecoveryRecord, progress: RebuildProgress, entry: JournalEntry)
        -> [TransitionProblem]
    {
        nextEntryProblems(
            record: record, progress: progress, entry: entry, acceptedGUIEmptinessMethods: qualifiedGUIEmptinessMethods)
    }

    static func nextEntryProblems(
        record: RecoveryRecord, progress: RebuildProgress, entry: JournalEntry, acceptedGUIEmptinessMethods: Set<String>
    ) -> [TransitionProblem] {
        var found: [TransitionProblem] = []
        if entry.sequence != progress.head.sequence + 1 {
            found.append(.notNextSequence(expected: progress.head.sequence + 1, found: entry.sequence))
        }
        if entry.previous != progress.head.checksum { found.append(.notChained) }
        found += bodyProblems(
            record: record, progress: progress, body: entry.body, accepted: acceptedGUIEmptinessMethods)
        return found
    }

    private static func bodyProblems(
        record: RecoveryRecord, progress: RebuildProgress, body: JournalBody, accepted: Set<String>
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
                record: record, progress: progress, operation: operation, target: target, accepted: accepted)
        case .returned(let operation, let target, _, _):
            return resolutionProblems(progress: progress, operation: operation, target: target, verifying: false)
        case .verified(let operation, let target, let observation):
            let found = resolutionProblems(progress: progress, operation: operation, target: target, verifying: true)
            if !found.isEmpty { return found }
            return observationProblems(
                record: record, progress: progress, operation: operation, target: target, observation: observation,
                accepted: accepted)
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
            let removed = Set(progress.verified(.removeRegistration))
            missing = record.mapping.map { $0.persistentID.uppercased() }.filter { !removed.contains($0) }
            for operation in [RebuildOperation.confirmLibraryEmpty, .establishGUIEmptiness, .terminateMusic]
            where progress.verified(operation).isEmpty {
                missing.append(operation.rawValue)
            }
        case .application:
            missing = record.evacuation.map(\.stagingPath).filter { !progress.isVerified(.applyFile, $0) }
        case .addition:
            missing = record.additionList.filter { !progress.isVerified(.addAlbum, $0) }
        case .display:
            missing = ["before-relaunch", "after-relaunch"].filter { !progress.isVerified(.confirmDisplay, $0) }
        }
        return missing.isEmpty ? [] : [.stageIncomplete(stage: stage, missing: missing)]
    }

    private static func intentProblems(
        record: RecoveryRecord, progress: RebuildProgress, operation: RebuildOperation, target: String,
        accepted: Set<String>
    ) -> [TransitionProblem] {
        if let open = progress.openOperation {
            return [.unresolvedOperation(operation: open.operation, target: open.target)]
        }
        guard let current = progress.currentStage else { return [.noStageBegun] }
        guard operation.stage == current else {
            return [.operationNotInStage(operation: operation, stage: operation.stage, current: current)]
        }
        if operation == .establishGUIEmptiness && accepted.isEmpty { return [.guiEmptinessMethodNotQualified] }
        switch operation {
        case .evacuateFile:
            guard record.evacuation.contains(where: { $0.sourcePath == target }) else {
                return [.targetNotInPlan(operation: operation, target: target)]
            }
        case .removeRegistration:
            guard record.mapping.contains(where: { $0.persistentID.uppercased() == target.uppercased() }) else {
                return [.targetNotInPlan(operation: operation, target: target)]
            }
        case .confirmLibraryEmpty, .establishGUIEmptiness, .terminateMusic:
            guard target.isEmpty else { return [.targetNotInPlan(operation: operation, target: target)] }
        case .applyFile:
            guard record.evacuation.contains(where: { $0.stagingPath == target }) else {
                return [.targetNotInPlan(operation: operation, target: target)]
            }
        case .addAlbum:
            guard record.additionList.contains(target) else {
                return [.targetNotInPlan(operation: operation, target: target)]
            }
        case .confirmDisplay:
            guard target == "before-relaunch" || target == "after-relaunch" else {
                return [.targetNotInPlan(operation: operation, target: target)]
            }
        }
        let canonical = canonicalTarget(operation, target)
        if progress.isVerified(operation, canonical) {
            return [.duplicateOperation(operation: operation, target: target)]
        }
        switch operation {
        case .confirmLibraryEmpty:
            let removed = Set(progress.verified(.removeRegistration))
            if record.mapping.contains(where: { !removed.contains($0.persistentID.uppercased()) }) {
                return [.prerequisiteMissing(operation: operation, requires: "removal of every mapped registration")]
            }
        case .terminateMusic:
            if progress.verified(.confirmLibraryEmpty).isEmpty {
                return [
                    .prerequisiteMissing(operation: operation, requires: RebuildOperation.confirmLibraryEmpty.rawValue)
                ]
            }
            if progress.verified(.establishGUIEmptiness).isEmpty {
                return [
                    .prerequisiteMissing(
                        operation: operation, requires: RebuildOperation.establishGUIEmptiness.rawValue)
                ]
            }
        case .addAlbum:
            let next = progress.verified(.addAlbum).count
            if next < record.additionList.count, record.additionList[next] != target {
                return [.targetOutOfOrder(operation: operation, expected: record.additionList[next], found: target)]
            }
        case .confirmDisplay:
            if target == "after-relaunch" && !progress.isVerified(.confirmDisplay, "before-relaunch") {
                return [.prerequisiteMissing(operation: operation, requires: "before-relaunch")]
            }
        default: break
        }
        return []
    }

    /// The stored spelling of a target: persistent IDs are compared case-insensitively and kept in uppercase.
    static func canonicalTarget(_ operation: RebuildOperation, _ target: String) -> String {
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
        case .removeRegistration: (["remaining"], [])
        case .confirmLibraryEmpty: (["registrationCount"], [])
        case .establishGUIEmptiness: (["method"], [])
        case .terminateMusic: (["musicRunning"], [])
        case .applyFile: (["musicRunning", "result"], [])
        case .addAlbum: (["newPersistentIDs", "laterThanPreviousAlbum"], [])
        case .confirmDisplay: (["observed"], [])
        }
    }

    private static func observationProblems(
        record: RecoveryRecord, progress: RebuildProgress, operation: RebuildOperation, target: String,
        observation: JournalObservation, accepted: Set<String>
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
            guard let entry = record.inventory.first(where: { PathKey.key($0.absolutePath) == PathKey.key(target) })
            else { return [.targetNotInPlan(operation: operation, target: target)] }
            let expected = entry.record
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
            let removed = Set(progress.verified(.removeRegistration)).union([target.uppercased()])
            let expected = Set(record.mapping.map { $0.persistentID.uppercased() }).subtracting(removed)
            let reported = (observation.remaining ?? []).map { $0.uppercased() }
            if Set(reported).count != reported.count || Set(reported) != expected {
                return [.remainingSetWrong(expected: expected.sorted(), found: reported.sorted())]
            }
        case .confirmLibraryEmpty:
            if let count = observation.registrationCount, count != 0 { return [.registrationCountNotZero(count)] }
        case .establishGUIEmptiness:
            if !accepted.contains(observation.method ?? "") { return [.guiEmptinessMethodNotQualified] }
        case .terminateMusic, .applyFile:
            if observation.musicRunning != false { return [.musicRunning(operation: operation)] }
        case .addAlbum:
            let ids = (observation.newPersistentIDs ?? []).map { $0.uppercased() }
            if ids.isEmpty { return [.newPersistentIDsEmpty] }
            let original = Set(record.mapping.map { $0.persistentID.uppercased() })
            var seen = Set(progress.newPersistentIDs)
            for (id, raw) in zip(ids, observation.newPersistentIDs ?? []) {
                if !RegistrationRecord.isWellFormedID(raw) { return [.newPersistentIDMalformed(raw)] }
                if original.contains(id) || !seen.insert(id).inserted { return [.newPersistentIDNotDisjoint(raw)] }
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
            verifiedTargets[operation, default: []].append(ProgressJournal.canonicalTarget(operation, target))
            openOperation = nil
            if operation == .evacuateFile { evacuationMethods[target] = observation.method ?? "" }
            if operation == .addAlbum {
                newPersistentIDs += (observation.newPersistentIDs ?? []).map { $0.uppercased() }
            }
        case .stopped: stopCount += 1
        }
    }
}
