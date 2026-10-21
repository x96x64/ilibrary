import Foundation
import Testing

@testable import RebuildCore

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Builds journals in memory from the synthetic record of `RecoveryRecordTests`. Entries are sealed and chained but
/// not validated, so that a test can assemble an invalid sequence and observe the refusal of the replay.
struct JournalBuilder {
    static let time = "2026-10-21T00:00:00Z"
    static let gui: Set<String> = ["test-detector"]

    let record: RecoveryRecord
    let recordBytes: Data
    var entries: [JournalEntry] = []

    init(record: RecoveryRecord, recordBytes: Data) throws {
        self.record = record
        self.recordBytes = recordBytes
        let digest = SHA256.digest(of: recordBytes).hex
        add(
            .header(
                JournalHeader(recordChecksum: record.checksum, recordFileSHA256: digest, ilibraryVersion: "0.2.0")),
            previous: digest)
    }

    static func make() throws -> JournalBuilder {
        let sealed = try RecoveryRecordTests.sample().sealed()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("jb-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try sealed.write(to: directory)
        let loaded = try ProgressJournalFile.loadRecord(from: directory)
        return try JournalBuilder(record: loaded.record, recordBytes: loaded.bytes)
    }

    mutating func add(_ body: JournalBody, previous: String? = nil, time: String = JournalBuilder.time) {
        entries.append(
            try! JournalEntry(
                sequence: entries.count, previous: previous ?? entries.last!.checksum, body: body, recordedAt: time))
    }

    var data: Data { entries.reduce(Data()) { $0 + (try! $1.line()) } }

    func replay(accepted: Set<String> = []) throws -> RebuildProgress {
        try ProgressJournal.replay(
            record: record, recordBytes: recordBytes, entries: entries, acceptedGUIEmptinessMethods: accepted)
    }

    func inventory(_ sourcePath: String) -> FileRecord {
        record.inventory.first { $0.absolutePath == sourcePath }!.record
    }

    // Operation helpers: an intent, a successful return, and a verification.

    mutating func operation(
        _ operation: RebuildOperation, _ target: String, _ observation: JournalObservation, succeeded: Bool = true
    ) {
        add(.intent(operation: operation, target: target))
        add(.returned(operation: operation, target: target, succeeded: succeeded, detail: "ok"))
        if succeeded { add(.verified(operation: operation, target: target, observation: observation)) }
    }

    mutating func evacuateAll(method: String = "rename") {
        add(.stageBegan(.evacuation))
        for entry in record.evacuation { evacuate(entry.sourcePath, method: method) }
    }

    mutating func evacuate(_ sourcePath: String, method: String) {
        let file = ObservedFile(inventory(sourcePath))
        let copy = method == "copy"
        operation(
            .evacuateFile, sourcePath,
            JournalObservation(
                method: method, staged: file, sourcePresent: copy, source: copy ? file : nil))
    }

    mutating func removeAll() {
        add(.stageBegan(.clearing))
        var remaining = record.mapping.map(\.persistentID)
        for mapping in record.mapping {
            remaining.removeAll { $0.uppercased() == mapping.persistentID.uppercased() }
            operation(.removeRegistration, mapping.persistentID, JournalObservation(remaining: remaining))
        }
    }

    mutating func clearingThroughTermination() {
        removeAll()
        operation(.confirmLibraryEmpty, "", JournalObservation(registrationCount: 0))
        operation(.establishGUIEmptiness, "", JournalObservation(method: "test-detector"))
        operation(.terminateMusic, "", JournalObservation(musicRunning: false))
    }

    mutating func applyAll() {
        add(.stageBegan(.application))
        for entry in record.evacuation {
            operation(
                .applyFile, entry.stagingPath,
                JournalObservation(musicRunning: false, result: ObservedFile(inventory(entry.sourcePath))))
        }
    }

    static func newID(_ index: Int) -> String { String(format: "%016X", 0x100 + index) }

    mutating func addAll() {
        add(.stageBegan(.addition))
        for (index, album) in record.additionList.enumerated() {
            operation(
                .addAlbum, album,
                JournalObservation(newPersistentIDs: [Self.newID(index)], laterThanPreviousAlbum: true))
        }
    }

    mutating func displayBoth() {
        add(.stageBegan(.display))
        for target in ["before-relaunch", "after-relaunch"] {
            operation(.confirmDisplay, target, JournalObservation(observed: record.expectedDisplayList))
        }
    }

    mutating func completeThroughEvacuation() {
        evacuateAll()
        add(.stageCompleted(.evacuation))
    }

    /// A complete journal, which is reachable only with an injected accepted GUI method.
    static func complete() throws -> JournalBuilder {
        var builder = try make()
        builder.completeThroughEvacuation()
        builder.clearingThroughTermination()
        builder.add(.stageCompleted(.clearing))
        builder.applyAll()
        builder.add(.stageCompleted(.application))
        builder.addAll()
        builder.add(.stageCompleted(.addition))
        builder.displayBoth()
        builder.add(.stageCompleted(.display))
        return builder
    }
}

@Suite struct ProgressJournalTests {
    typealias Builder = JournalBuilder

    /// The transition problem that a replay reports, or nil when it succeeds or fails otherwise.
    func transition(_ builder: Builder, accepted: Set<String> = []) -> TransitionProblem? {
        do {
            _ = try builder.replay(accepted: accepted)
            return nil
        } catch ProgressJournalError.invalidTransition(_, let problem) {
            return problem
        } catch {
            Issue.record("unexpected error \(error)")
            return nil
        }
    }

    func error(_ run: () throws -> Any) -> ProgressJournalError? {
        do {
            _ = try run()
            return nil
        } catch let error as ProgressJournalError {
            return error
        } catch {
            Issue.record("unexpected error \(error)")
            return nil
        }
    }

    func parseError(_ data: Data) -> ProgressJournalError? { error { try ProgressJournal.parse(data) } }

    func lines(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).dropLast()
            .map(String.init)
    }

    func join(_ lines: [String]) -> Data { Data((lines.joined(separator: "\n") + "\n").utf8) }

    // MARK: Format

    @Test func entriesAreCanonicalLinesWithTheirOwnChecksum() throws {
        var builder = try Builder.make()
        builder.add(.stopped(reason: "a/b"))
        let data = builder.data
        #expect(data.last == 0x0A)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"kind\":\"header\""))
        #expect(text.contains("a/b"))
        #expect(!text.contains("\\/"))
        let parsed = try ProgressJournal.parse(data)
        #expect(parsed == builder.entries)
        #expect(parsed[0].sequence == 0 && parsed[1].sequence == 1)
        #expect(parsed[0].previous == SHA256.digest(of: builder.recordBytes).hex)
        #expect(parsed[1].previous == parsed[0].checksum)
        for entry in parsed { #expect(try entry.checksumIsValid()) }
    }

    @Test func aHeaderOnlyJournalReplaysToAnEmptyProgress() throws {
        let progress = try Builder.make().replay()
        #expect(progress.head.sequence == 0)
        #expect(progress.completedStages.isEmpty && progress.currentStage == nil)
        #expect(progress.canProceed)
    }

    // MARK: Header binding

    @Test func theHeaderMustBindTheRecordFileAndChecksum() throws {
        let builder = try Builder.make()
        var otherBytes = builder.recordBytes
        otherBytes.append(0x0A)
        #expect(
            error {
                try ProgressJournal.replay(record: builder.record, recordBytes: otherBytes, entries: builder.entries)
            }
                == .recordMismatch)
        var differentRecord = builder.record
        differentRecord.ilibraryVersion = "9.9.9"
        differentRecord = try differentRecord.sealed()
        #expect(
            error {
                try ProgressJournal.replay(
                    record: differentRecord, recordBytes: builder.recordBytes, entries: builder.entries)
            } == .recordMismatch)
        // A wrong record checksum in the header.
        var wrong = try Builder.make()
        wrong.entries.removeAll()
        let digest = SHA256.digest(of: wrong.recordBytes).hex
        wrong.add(
            .header(JournalHeader(recordChecksum: "00", recordFileSHA256: digest, ilibraryVersion: "0.2.0")),
            previous: digest)
        #expect(error { try wrong.replay() } == .recordMismatch)
    }

    @Test func aJournalWithoutAHeaderOrWithAnUnsupportedScopeIsRefused() throws {
        var builder = try Builder.make()
        builder.entries.removeAll()
        builder.add(.stopped(reason: "x"), previous: SHA256.digest(of: builder.recordBytes).hex)
        #expect(error { try builder.replay() } == .headerMissing)
        var scoped = try Builder.make()
        scoped.entries.removeAll()
        let digest = SHA256.digest(of: scoped.recordBytes).hex
        scoped.add(
            .header(
                JournalHeader(
                    recordChecksum: scoped.record.checksum, recordFileSHA256: digest, ilibraryVersion: "0.2.0",
                    scope: "album")), previous: digest)
        #expect(error { try scoped.replay() } == .unsupportedScope("album"))
        var repeated = try Builder.make()
        repeated.add(repeated.entries[0].body)
        #expect(transition(repeated) == .headerRepeated)
    }

    // MARK: Happy paths

    @Test func evacuationByRenameAndByCopyIsAccepted() throws {
        for method in ["rename", "copy"] {
            var builder = try Builder.make()
            builder.evacuateAll(method: method)
            builder.add(.stageCompleted(.evacuation))
            let progress = try builder.replay()
            #expect(progress.completedStages == [.evacuation], "\(method)")
            #expect(progress.verifiedTargets[.evacuateFile] == builder.record.evacuation.map(\.sourcePath))
            #expect(progress.canProceed && progress.currentStage == nil)
            #expect(progress.evacuationMethods.values.allSatisfy { $0 == method })
        }
    }

    @Test func everyMappedIDIsRemovedWithItsRemainingSetAndTheLibraryIsConfirmedEmpty() throws {
        var builder = try Builder.make()
        builder.completeThroughEvacuation()
        builder.removeAll()
        builder.operation(.confirmLibraryEmpty, "", JournalObservation(registrationCount: 0))
        let progress = try builder.replay()
        #expect(progress.currentStage == .clearing)
        #expect(
            progress.verifiedTargets[.removeRegistration] == builder.record.mapping.map { $0.persistentID.uppercased() }
        )
        #expect(progress.verifiedTargets[.confirmLibraryEmpty] == [""])
    }

    @Test func theGUIEmptinessGateRefusesEveryIntentAndThereforeTerminationAndClearingCompletion() throws {
        var builder = try Builder.make()
        builder.completeThroughEvacuation()
        builder.removeAll()
        builder.operation(.confirmLibraryEmpty, "", JournalObservation(registrationCount: 0))
        var gui = builder
        gui.add(.intent(operation: .establishGUIEmptiness, target: ""))
        #expect(transition(gui) == .guiEmptinessMethodNotQualified)
        #expect(ProgressJournal.qualifiedGUIEmptinessMethods.isEmpty)
        var terminate = builder
        terminate.add(.intent(operation: .terminateMusic, target: ""))
        #expect(
            transition(terminate)
                == .prerequisiteMissing(operation: .terminateMusic, requires: "establishGUIEmptiness"))
        var complete = builder
        complete.add(.stageCompleted(.clearing))
        #expect(
            transition(complete)
                == .stageIncomplete(stage: .clearing, missing: ["establishGUIEmptiness", "terminateMusic"]))
    }

    @Test func aMethodOutsideTheAcceptedSetIsRefusedEvenWhenAnotherIsAccepted() throws {
        var builder = try Builder.make()
        builder.completeThroughEvacuation()
        builder.removeAll()
        builder.operation(.confirmLibraryEmpty, "", JournalObservation(registrationCount: 0))
        builder.operation(.establishGUIEmptiness, "", JournalObservation(method: "manual"))
        #expect(transition(builder, accepted: Builder.gui) == .guiEmptinessMethodNotQualified)
    }

    @Test func theLaterStagesAreAcceptedWithATestOnlyAcceptedMethod() throws {
        let builder = try Builder.complete()
        let progress = try builder.replay(accepted: Builder.gui)
        #expect(progress.completedStages == RebuildStage.allCases)
        #expect(progress.currentStage == nil && progress.canProceed)
        #expect(progress.newPersistentIDs == (0..<3).map { Builder.newID($0) })
        // The same journal is refused by the production rules, which accept no method.
        #expect(transition(builder) == .guiEmptinessMethodNotQualified)
        // After the last stage only a stop may follow.
        var after = builder
        after.add(.stopped(reason: "done"))
        #expect(try after.replay(accepted: Builder.gui).stopCount == 1)
        after.add(.stageBegan(.evacuation))
        #expect(transition(after, accepted: Builder.gui) == .entryAfterFinalStage)
    }

    // MARK: Transition refusals

    @Test func stagesMustFollowTheirOrderAndNeverRepeat() throws {
        var first = try Builder.make()
        first.add(.stageBegan(.clearing))
        #expect(transition(first) == .stageOutOfOrder(expected: .evacuation, found: .clearing))
        var intentFirst = try Builder.make()
        intentFirst.add(.intent(operation: .evacuateFile, target: "x"))
        #expect(transition(intentFirst) == .noStageBegun)
        var unfinished = try Builder.make()
        unfinished.evacuateAll()
        unfinished.add(.stageBegan(.clearing))
        #expect(transition(unfinished) == .stageNotCompleted(current: .evacuation))
        var repeated = try Builder.make()
        repeated.completeThroughEvacuation()
        repeated.add(.stageBegan(.evacuation))
        #expect(transition(repeated) == .stageAlreadyBegun(.evacuation))
        var skipped = try Builder.make()
        skipped.completeThroughEvacuation()
        skipped.add(.stageBegan(.application))
        #expect(transition(skipped) == .stageOutOfOrder(expected: .clearing, found: .application))
        var early = try Builder.make()
        early.evacuate(early.record.evacuation[0].sourcePath, method: "rename")
        #expect(transition(early) == .noStageBegun)
    }

    @Test func aStageCannotCompleteBeforeEveryTargetIsVerified() throws {
        var builder = try Builder.make()
        builder.add(.stageBegan(.evacuation))
        builder.evacuate(builder.record.evacuation[0].sourcePath, method: "rename")
        builder.add(.stageCompleted(.evacuation))
        #expect(
            transition(builder)
                == .stageIncomplete(stage: .evacuation, missing: [builder.record.evacuation[1].sourcePath]))
        var wrongStage = try Builder.make()
        wrongStage.evacuateAll()
        wrongStage.add(.stageCompleted(.clearing))
        #expect(transition(wrongStage) == .stageNotCurrent(stage: .clearing, current: .evacuation))
        var noStage = try Builder.make()
        noStage.add(.stageCompleted(.evacuation))
        #expect(transition(noStage) == .stageNotCurrent(stage: .evacuation, current: nil))
    }

    @Test func anOperationInTheWrongStageOrOutsideThePlanIsRefused() throws {
        var wrongStage = try Builder.make()
        wrongStage.add(.stageBegan(.evacuation))
        wrongStage.add(.intent(operation: .removeRegistration, target: RecoveryRecordTests.one))
        #expect(
            transition(wrongStage)
                == .operationNotInStage(operation: .removeRegistration, stage: .clearing, current: .evacuation))
        var outside = try Builder.make()
        outside.add(.stageBegan(.evacuation))
        outside.add(.intent(operation: .evacuateFile, target: "/lib/media/Music/Z/9.m4a"))
        #expect(
            transition(outside) == .targetNotInPlan(operation: .evacuateFile, target: "/lib/media/Music/Z/9.m4a"))
        var unmapped = try Builder.make()
        unmapped.completeThroughEvacuation()
        unmapped.add(.stageBegan(.clearing))
        unmapped.add(.intent(operation: .removeRegistration, target: "00000000000000FF"))
        #expect(
            transition(unmapped) == .targetNotInPlan(operation: .removeRegistration, target: "00000000000000FF"))
        var early = try Builder.make()
        early.completeThroughEvacuation()
        early.add(.stageBegan(.clearing))
        early.add(.intent(operation: .confirmLibraryEmpty, target: ""))
        #expect(
            transition(early)
                == .prerequisiteMissing(
                    operation: .confirmLibraryEmpty, requires: "removal of every mapped registration"))
    }

    @Test func removalIsCaseInsensitiveAndRequiresTheExactRemainingSet() throws {
        var lower = try Builder.make()
        lower.completeThroughEvacuation()
        lower.add(.stageBegan(.clearing))
        lower.operation(
            .removeRegistration, RecoveryRecordTests.two.lowercased(),
            JournalObservation(remaining: [RecoveryRecordTests.one.lowercased()]))
        #expect(try lower.replay().verifiedTargets[.removeRegistration] == [RecoveryRecordTests.two.uppercased()])
        let wrongSets: [[String]] = [[], [RecoveryRecordTests.one, RecoveryRecordTests.two], ["00000000000000FF"]]
        for wrong in wrongSets {
            var builder = try Builder.make()
            builder.completeThroughEvacuation()
            builder.add(.stageBegan(.clearing))
            builder.operation(.removeRegistration, RecoveryRecordTests.two, JournalObservation(remaining: wrong))
            guard case .remainingSetWrong(let expected, _)? = transition(builder) else {
                Issue.record("expected remainingSetWrong for \(wrong)")
                continue
            }
            #expect(expected == [RecoveryRecordTests.one])
        }
        var duplicated = try Builder.make()
        duplicated.completeThroughEvacuation()
        duplicated.add(.stageBegan(.clearing))
        duplicated.operation(
            .removeRegistration, RecoveryRecordTests.two,
            JournalObservation(remaining: [RecoveryRecordTests.one, RecoveryRecordTests.one]))
        #expect(transition(duplicated) != nil)
        var nonEmpty = try Builder.make()
        nonEmpty.completeThroughEvacuation()
        nonEmpty.removeAll()
        nonEmpty.operation(.confirmLibraryEmpty, "", JournalObservation(registrationCount: 1))
        #expect(transition(nonEmpty) == .registrationCountNotZero(1))
    }

    @Test func evacuationObservationsMustMatchTheInventory() throws {
        let source = try Builder.make().record.evacuation[0].sourcePath
        func observation(_ builder: Builder, mutate: (inout JournalObservation) -> Void) throws -> TransitionProblem? {
            var copy = builder
            copy.add(.stageBegan(.evacuation))
            var value = JournalObservation(
                method: "rename", staged: ObservedFile(copy.inventory(source)), sourcePresent: false)
            mutate(&value)
            copy.operation(.evacuateFile, source, value)
            return transition(copy)
        }
        let base = try Builder.make()
        let good = ObservedFile(base.inventory(source))
        let wrongDigest = ObservedFile(
            size: good.size, sha256: SHA256.digest(of: [7]), modification: good.modification, creation: good.creation)
        let wrongTime = ObservedFile(
            size: good.size, sha256: good.sha256, modification: FileTimestamp(seconds: 1), creation: good.creation)
        let wrongSize = ObservedFile(
            size: good.size + 1, sha256: good.sha256, modification: good.modification, creation: good.creation)
        let noCreation = ObservedFile(
            size: good.size, sha256: good.sha256, modification: good.modification, creation: nil)
        for staged in [wrongDigest, wrongTime, wrongSize, noCreation] {
            #expect(try observation(base) { $0.staged = staged } == .stagedFileDiffers(target: source))
        }
        #expect(
            try observation(base) { $0.sourcePresent = true }
                == .sourceStateInconsistent(target: source, method: "rename"))
        #expect(
            try observation(base) { $0.source = good } == .sourceStateInconsistent(target: source, method: "rename"))
        #expect(
            try observation(base) {
                $0.method = "copy"
                $0.sourcePresent = false
            } == .sourceStateInconsistent(target: source, method: "copy"))
        #expect(
            try observation(base) {
                $0.method = "copy"
                $0.sourcePresent = true
                $0.source = wrongDigest
            } == .sourceStateInconsistent(target: source, method: "copy"))
        #expect(try observation(base) { $0.method = "link" } == .unknownEvacuationMethod("link"))
        #expect(
            try observation(base) { $0.musicRunning = false }
                == .observationShape(operation: .evacuateFile, missing: [], unexpected: ["musicRunning"]))
        #expect(
            try observation(base) { $0.staged = nil }
                == .observationShape(operation: .evacuateFile, missing: ["staged"], unexpected: []))
    }

    @Test func theApplicationRulesRefuseARunningMusic() throws {
        let builder = try Builder.complete()
        let index = builder.entries.firstIndex {
            if case .verified(.applyFile, _, _) = $0.body { return true } else { return false }
        }!
        // Rebuild the journal up to that point and record an observation with Music running.
        var truncated = builder
        truncated.entries.removeSubrange(index...)
        let target = builder.record.evacuation[0].stagingPath
        truncated.add(
            .verified(
                operation: .applyFile, target: target,
                observation: JournalObservation(
                    musicRunning: true, result: ObservedFile(builder.inventory(builder.record.evacuation[0].sourcePath))
                )))
        #expect(transition(truncated, accepted: Builder.gui) == .musicRunning(operation: .applyFile))
    }

    @Test func albumsMustBeAddedInOrderWithFreshWellFormedIDs() throws {
        func prefix() throws -> Builder {
            var builder = try Builder.make()
            builder.completeThroughEvacuation()
            builder.clearingThroughTermination()
            builder.add(.stageCompleted(.clearing))
            builder.applyAll()
            builder.add(.stageCompleted(.application))
            builder.add(.stageBegan(.addition))
            return builder
        }
        var outOfOrder = try prefix()
        outOfOrder.add(.intent(operation: .addAlbum, target: "a2"))
        #expect(
            transition(outOfOrder, accepted: Builder.gui)
                == .targetOutOfOrder(operation: .addAlbum, expected: "a1", found: "a2"))
        var unknown = try prefix()
        unknown.add(.intent(operation: .addAlbum, target: "zz"))
        #expect(
            transition(unknown, accepted: Builder.gui) == .targetNotInPlan(operation: .addAlbum, target: "zz"))
        func verdict(_ build: (inout Builder) -> Void) throws -> TransitionProblem? {
            var builder = try prefix()
            build(&builder)
            return transition(builder, accepted: Builder.gui)
        }
        let fresh = Builder.newID(0)
        #expect(
            try verdict {
                $0.operation(.addAlbum, "a1", JournalObservation(newPersistentIDs: [], laterThanPreviousAlbum: true))
            }
                == .newPersistentIDsEmpty)
        #expect(
            try verdict {
                $0.operation(
                    .addAlbum, "a1", JournalObservation(newPersistentIDs: ["12"], laterThanPreviousAlbum: true))
            }
                == .newPersistentIDMalformed("12"))
        #expect(
            try verdict {
                $0.operation(
                    .addAlbum, "a1",
                    JournalObservation(
                        newPersistentIDs: [RecoveryRecordTests.one.lowercased()], laterThanPreviousAlbum: true))
            } == .newPersistentIDNotDisjoint(RecoveryRecordTests.one.lowercased()))
        #expect(
            try verdict {
                $0.operation(
                    .addAlbum, "a1",
                    JournalObservation(newPersistentIDs: [fresh, fresh.lowercased()], laterThanPreviousAlbum: true))
            }
                == .newPersistentIDNotDisjoint(fresh.lowercased()))
        #expect(
            try verdict {
                $0.operation(
                    .addAlbum, "a1", JournalObservation(newPersistentIDs: [fresh], laterThanPreviousAlbum: false))
            }
                == .albumNotLater(target: "a1"))
        #expect(
            try verdict {
                $0.operation(
                    .addAlbum, "a1", JournalObservation(newPersistentIDs: [fresh], laterThanPreviousAlbum: true))
                $0.operation(
                    .addAlbum, "a2",
                    JournalObservation(newPersistentIDs: [fresh.lowercased()], laterThanPreviousAlbum: true))
            } == .newPersistentIDNotDisjoint(fresh.lowercased()))
        #expect(
            try verdict {
                $0.operation(
                    .addAlbum, "a1", JournalObservation(newPersistentIDs: [fresh], laterThanPreviousAlbum: true))
                $0.add(.intent(operation: .addAlbum, target: "a1"))
            } == .duplicateOperation(operation: .addAlbum, target: "a1"))
    }

    @Test func theDisplayRulesRequireTheExpectedListAndTheOrderOfConfirmations() throws {
        func prefix() throws -> Builder {
            var builder = try Builder.make()
            builder.completeThroughEvacuation()
            builder.clearingThroughTermination()
            builder.add(.stageCompleted(.clearing))
            builder.applyAll()
            builder.add(.stageCompleted(.application))
            builder.addAll()
            builder.add(.stageCompleted(.addition))
            builder.add(.stageBegan(.display))
            return builder
        }
        var wrong = try prefix()
        wrong.operation(.confirmDisplay, "before-relaunch", JournalObservation(observed: ["a1", "a2", "a3"]))
        #expect(
            transition(wrong, accepted: Builder.gui)
                == .displayListDiffers(expected: ["a3", "a2", "a1"], found: ["a1", "a2", "a3"]))
        var order = try prefix()
        order.add(.intent(operation: .confirmDisplay, target: "after-relaunch"))
        #expect(
            transition(order, accepted: Builder.gui)
                == .prerequisiteMissing(operation: .confirmDisplay, requires: "before-relaunch"))
        var target = try prefix()
        target.add(.intent(operation: .confirmDisplay, target: "later"))
        #expect(
            transition(target, accepted: Builder.gui) == .targetNotInPlan(operation: .confirmDisplay, target: "later"))
        var incomplete = try prefix()
        incomplete.operation(.confirmDisplay, "before-relaunch", JournalObservation(observed: ["a3", "a2", "a1"]))
        incomplete.add(.stageCompleted(.display))
        #expect(
            transition(incomplete, accepted: Builder.gui)
                == .stageIncomplete(stage: .display, missing: ["after-relaunch"]))
    }

    // MARK: Open operations

    func evacuationStart() throws -> (Builder, String) {
        var builder = try Builder.make()
        builder.add(.stageBegan(.evacuation))
        return (builder, builder.record.evacuation[0].sourcePath)
    }

    @Test func onlyOneOperationMayBeOpenAndNothingElseMayFollowAnIntent() throws {
        var (builder, source) = try evacuationStart()
        builder.add(.intent(operation: .evacuateFile, target: source))
        let open = try builder.replay()
        #expect(
            open.openOperation
                == OpenOperation(operation: .evacuateFile, target: source, returned: false, returnFailed: false))
        #expect(!open.canProceed)
        var second = builder
        second.add(.intent(operation: .evacuateFile, target: builder.record.evacuation[1].sourcePath))
        #expect(transition(second) == .unresolvedOperation(operation: .evacuateFile, target: source))
        var duplicate = builder
        duplicate.add(.intent(operation: .evacuateFile, target: source))
        #expect(transition(duplicate) == .unresolvedOperation(operation: .evacuateFile, target: source))
        var begin = builder
        begin.add(.stageCompleted(.evacuation))
        #expect(transition(begin) == .unresolvedOperation(operation: .evacuateFile, target: source))
        var stop = builder
        stop.add(.stopped(reason: "pause"))
        let stopped = try stop.replay()
        #expect(stopped.openOperation != nil && stopped.stopCount == 1 && !stopped.canProceed)
    }

    @Test func aVerifiedTargetReceivesNoNewIntentReturnOrVerification() throws {
        var (builder, source) = try evacuationStart()
        builder.evacuate(source, method: "rename")
        var intent = builder
        intent.add(.intent(operation: .evacuateFile, target: source))
        #expect(transition(intent) == .duplicateOperation(operation: .evacuateFile, target: source))
        var returned = builder
        returned.add(.returned(operation: .evacuateFile, target: source, succeeded: true, detail: ""))
        #expect(transition(returned) == .duplicateReturn(operation: .evacuateFile, target: source))
        var verified = builder
        verified.add(.verified(operation: .evacuateFile, target: source, observation: JournalObservation()))
        #expect(transition(verified) == .duplicateVerification(operation: .evacuateFile, target: source))
        var stray = builder
        stray.add(.returned(operation: .evacuateFile, target: "/x", succeeded: true, detail: ""))
        #expect(transition(stray) == .noOpenOperation)
    }

    @Test func returnAndVerificationMustMatchTheOpenIntentAndFollowEachOther() throws {
        var (builder, source) = try evacuationStart()
        let other = builder.record.evacuation[1].sourcePath
        builder.add(.intent(operation: .evacuateFile, target: source))
        var wrongTarget = builder
        wrongTarget.add(.returned(operation: .evacuateFile, target: other, succeeded: true, detail: ""))
        #expect(
            transition(wrongTarget)
                == .operationMismatch(open: .evacuateFile, openTarget: source, found: .evacuateFile, foundTarget: other)
        )
        var wrongOperation = builder
        wrongOperation.add(.returned(operation: .applyFile, target: source, succeeded: true, detail: ""))
        #expect(
            transition(wrongOperation)
                == .operationMismatch(open: .evacuateFile, openTarget: source, found: .applyFile, foundTarget: source))
        let observation = JournalObservation(
            method: "rename", staged: ObservedFile(builder.inventory(source)), sourcePresent: false)
        var unreturned = builder
        unreturned.add(.verified(operation: .evacuateFile, target: source, observation: observation))
        #expect(transition(unreturned) == .notReturned(operation: .evacuateFile, target: source))
        var twice = builder
        twice.add(.returned(operation: .evacuateFile, target: source, succeeded: true, detail: ""))
        twice.add(.returned(operation: .evacuateFile, target: source, succeeded: true, detail: ""))
        #expect(transition(twice) == .duplicateReturn(operation: .evacuateFile, target: source))
        var success = builder
        success.add(.returned(operation: .evacuateFile, target: source, succeeded: true, detail: ""))
        let returned = try success.replay()
        #expect(returned.openOperation?.returned == true && !returned.canProceed)
        #expect(returned.verifiedTargets[.evacuateFile] == nil)
    }

    @Test func aFailedReturnLeavesAnUnresolvedOperationThatNothingResolves() throws {
        var (builder, source) = try evacuationStart()
        builder.operation(.evacuateFile, source, JournalObservation(), succeeded: false)
        let progress = try builder.replay()
        #expect(progress.openOperation?.returnFailed == true)
        #expect(!progress.canProceed)
        #expect(progress.verifiedTargets[.evacuateFile] == nil)
        var verified = builder
        let observation = JournalObservation(
            method: "rename", staged: ObservedFile(builder.inventory(source)), sourcePresent: false)
        verified.add(.verified(operation: .evacuateFile, target: source, observation: observation))
        #expect(transition(verified) == .returnNotSucceeded(operation: .evacuateFile, target: source))
        var next = builder
        next.add(.intent(operation: .evacuateFile, target: builder.record.evacuation[1].sourcePath))
        #expect(transition(next) == .unresolvedOperation(operation: .evacuateFile, target: source))
        var again = builder
        again.add(.intent(operation: .evacuateFile, target: source))
        #expect(transition(again) == .unresolvedOperation(operation: .evacuateFile, target: source))
        var complete = builder
        complete.add(.stageCompleted(.evacuation))
        #expect(transition(complete) == .unresolvedOperation(operation: .evacuateFile, target: source))
    }

    @Test func theWriterAndTheReplayShareTheSameRules() throws {
        var builder = try Builder.make()
        builder.add(.stageBegan(.evacuation))
        let progress = try builder.replay()
        let good = try JournalEntry(
            sequence: 2, previous: progress.head.checksum,
            body: .intent(operation: .evacuateFile, target: builder.record.evacuation[0].sourcePath),
            recordedAt: Builder.time)
        #expect(ProgressJournal.nextEntryProblems(record: builder.record, progress: progress, entry: good).isEmpty)
        let badSequence = try JournalEntry(
            sequence: 5, previous: "x", body: good.body, recordedAt: Builder.time)
        #expect(
            ProgressJournal.nextEntryProblems(record: builder.record, progress: progress, entry: badSequence)
                == [.notNextSequence(expected: 2, found: 5), .notChained])
    }

    // MARK: Parsing refusals

    @Test func unknownFormatAndKindAreReportedSpecifically() throws {
        var builder = try Builder.make()
        builder.add(.stopped(reason: "x"))
        var text = lines(builder.data)
        let original = text[1]
        text[1] = original.replacingOccurrences(of: "ilibrary-rebuild-journal-1", with: "ilibrary-rebuild-journal-2")
        #expect(parseError(join(text)) == .unsupportedFormat("ilibrary-rebuild-journal-2", 1))
        text[1] = original.replacingOccurrences(of: "\"kind\":\"stopped\"", with: "\"kind\":\"mystery\"")
        #expect(parseError(join(text)) == .unsupportedEntryKind("mystery", 1))
        text[1] = original.replacingOccurrences(of: "\"reason\"", with: "\"cause\"")
        guard case .malformedEntry(1, _)? = parseError(join(text)) else {
            Issue.record("expected malformedEntry")
            return
        }
        text[1] = original.replacingOccurrences(of: "\"stopped\"", with: "\"Stopped\"")
        #expect(parseError(join(text)) == .unsupportedEntryKind("Stopped", 1))
        text[1] = original.replacingOccurrences(of: "\"format\":\"ilibrary-rebuild-journal-1\",", with: "")
        guard case .malformedEntry(1, _)? = parseError(join(text)) else {
            Issue.record("expected malformedEntry")
            return
        }
    }

    @Test func aNonCanonicalLineIsMalformed() throws {
        var builder = try Builder.make()
        builder.add(.stopped(reason: "x"))
        var text = lines(builder.data)
        text[1] = text[1].replacingOccurrences(of: ":\"x\"", with: ": \"x\"")
        guard case .malformedEntry(1, _)? = parseError(join(text)) else {
            Issue.record("expected malformedEntry")
            return
        }
    }

    @Test func emptyAndTornFilesAreDistinguishedFromInteriorCorruption() throws {
        #expect(parseError(Data()) == .empty)
        var builder = try Builder.make()
        builder.add(.stopped(reason: "one"))
        builder.add(.stopped(reason: "two"))
        let data = builder.data
        // The final entry lacks its newline.
        #expect(parseError(data.dropLast()) == .tornFinalEntry)
        // The final entry is cut in half.
        let text = lines(data)
        let half = String(text[2].prefix(text[2].count / 2))
        #expect(parseError(Data((text[0] + "\n" + text[1] + "\n" + half).utf8)) == .tornFinalEntry)
        #expect(parseError(Data((text[0] + "\n" + text[1] + "\n" + half + "\n").utf8)) == .tornFinalEntry)
        // The final entry has a bad checksum.
        var checksum = text[2]
        let range = checksum.range(of: "\"checksum\":\"")!
        checksum.replaceSubrange(
            range.upperBound...range.upperBound, with: checksum[range.upperBound] == "0" ? "1" : "0")
        #expect(parseError(join([text[0], text[1], checksum])) == .tornFinalEntry)
        // The same damage in an interior entry is a checksum mismatch, and an interior non-JSON line is corrupt.
        var interior = text[1]
        let interiorRange = interior.range(of: "\"checksum\":\"")!
        interior.replaceSubrange(
            interiorRange.upperBound...interiorRange.upperBound,
            with: interior[interiorRange.upperBound] == "0" ? "1" : "0")
        #expect(parseError(join([text[0], interior, text[2]])) == .checksumMismatch(1))
        #expect(parseError(join([text[0], String(text[1].prefix(20)), text[2]])) == .corruptEntry(1))
        #expect(parseError(join([text[0], "", text[2]])) == .corruptEntry(1))
        // A blank final line is also a torn entry.
        #expect(parseError(Data((String(decoding: data, as: UTF8.self) + "\n").utf8)) == .tornFinalEntry)
        // Tampered content with an unchanged checksum is a mismatch.
        let edited = text[1].replacingOccurrences(of: "one", with: "ONE")
        #expect(parseError(join([text[0], edited, text[2]])) == .checksumMismatch(1))
    }

    @Test func sequenceGapsAndBrokenChainsAreRefused() throws {
        var builder = try Builder.make()
        builder.add(.stopped(reason: "one"))
        builder.add(.stopped(reason: "two"))
        let text = lines(builder.data)
        #expect(parseError(join([text[0], text[2]])) == .sequenceGap(expected: 1, found: 2))
        #expect(parseError(join([text[0], text[1], text[1]])) == .sequenceGap(expected: 2, found: 1))
        var chained = try Builder.make()
        chained.add(.stopped(reason: "one"))
        chained.add(.stopped(reason: "two"), previous: SHA256.digest(of: [1]).hex)
        #expect(parseError(chained.data) == .brokenChain(2))
        var other = try Builder.make()
        other.add(.stopped(reason: "one"), previous: SHA256.digest(of: [1]).hex)
        #expect(parseError(other.data) == .brokenChain(1))
    }

    @Test func aHeaderDigestThatDiffersFromItsPreviousFieldIsMalformed() throws {
        var builder = try Builder.make()
        builder.entries.removeAll()
        builder.add(
            .header(
                JournalHeader(
                    recordChecksum: builder.record.checksum, recordFileSHA256: SHA256.digest(of: [1]).hex,
                    ilibraryVersion: "0.2.0")), previous: SHA256.digest(of: [2]).hex)
        guard case .malformedEntry(0, _)? = parseError(builder.data) else {
            Issue.record("expected malformedEntry")
            return
        }
    }

    @Test func aValidPrefixReplaysAndOnlyReconciliationRevealsTheTruncation() throws {
        var full = try Builder.make()
        full.completeThroughEvacuation()
        full.removeAll()
        let fullProgress = try full.replay()
        // Truncate the journal after the second evacuation: the later removals disappear without trace.
        var prefix = full
        prefix.entries.removeSubrange(7...)
        let prefixProgress = try ProgressJournal.load(
            data: prefix.data, record: prefix.record, recordBytes: prefix.recordBytes
        ).progress
        #expect(prefixProgress.head.sequence == 6)
        #expect(prefixProgress.head != fullProgress.head)
        #expect(prefixProgress.completedStages.isEmpty)
        // The observed state is that of the full journal: both files are evacuated and no registration remains.
        let snapshot = ReconciliationSnapshot(
            evacuation: Self.observations(full.record, evacuated: [0, 1], method: "rename"), registrationIDs: [],
            musicRunning: false)
        let problems = ProgressJournal.reconcile(record: full.record, progress: prefixProgress, snapshot: snapshot)
        // The prefix ends with the second evacuation returned and unverified, which reconciliation accepts in either
        // state; the removals that the truncation hid are revealed only because the registrations are absent.
        #expect(prefixProgress.openOperation?.operation == .evacuateFile)
        let hidden = full.record.mapping.map { $0.persistentID.uppercased() }.sorted()
        #expect(problems == hidden.map { ReconciliationProblem.registrationMissing(persistentID: $0) })
        #expect(ProgressJournal.reconcile(record: full.record, progress: fullProgress, snapshot: snapshot).isEmpty)
    }

    // MARK: Reconciliation

    static func observations(_ record: RecoveryRecord, evacuated: Set<Int>, method: String) -> [EvacuationObservation] {
        record.evacuation.enumerated().map { index, entry in
            let file = ObservedFile(record.inventory.first { $0.absolutePath == entry.sourcePath }!.record)
            let moved = evacuated.contains(index)
            return EvacuationObservation(
                sourcePath: entry.sourcePath, source: moved && method == "rename" ? nil : file,
                staging: moved ? file : nil)
        }
    }

    func snapshot(
        _ record: RecoveryRecord, evacuated: Set<Int> = [], method: String = "rename", ids: Set<String>? = nil,
        music: Bool = false
    ) -> ReconciliationSnapshot {
        ReconciliationSnapshot(
            evacuation: Self.observations(record, evacuated: evacuated, method: method),
            registrationIDs: ids ?? Set(record.mapping.map(\.persistentID)), musicRunning: music)
    }

    @Test func reconciliationAcceptsTheStateThatTheJournalImplies() throws {
        let fresh = try Builder.make()
        #expect(
            ProgressJournal.reconcile(
                record: fresh.record, progress: try fresh.replay(), snapshot: snapshot(fresh.record)
            ).isEmpty)
        for method in ["rename", "copy"] {
            var builder = try Builder.make()
            builder.evacuateAll(method: method)
            #expect(
                ProgressJournal.reconcile(
                    record: builder.record, progress: try builder.replay(),
                    snapshot: snapshot(builder.record, evacuated: [0, 1], method: method)
                ).isEmpty, "\(method)")
        }
        var cleared = try Builder.make()
        cleared.completeThroughEvacuation()
        cleared.removeAll()
        cleared.add(.stopped(reason: "x"))
        #expect(
            ProgressJournal.reconcile(
                record: cleared.record, progress: try cleared.replay(),
                snapshot: snapshot(cleared.record, evacuated: [0, 1], ids: [])
            ).isEmpty)
    }

    @Test func reconciliationReportsEveryDisagreement() throws {
        var builder = try Builder.make()
        builder.add(.stageBegan(.evacuation))
        let progress = try builder.replay()
        let record = builder.record
        let first = record.evacuation[0]
        // Nothing evacuated by the journal, but a staging file exists and a source is gone.
        let problems = ProgressJournal.reconcile(
            record: record, progress: progress, snapshot: snapshot(record, evacuated: [0]))
        #expect(
            problems == [
                .sourceMissing(sourcePath: first.sourcePath),
                .stagingUnexpectedlyPresent(stagingPath: first.stagingPath),
            ])
        // A changed source.
        let file = ObservedFile(builder.inventory(first.sourcePath))
        let changed = ObservedFile(
            size: file.size + 1, sha256: file.sha256, modification: file.modification, creation: file.creation)
        var altered = snapshot(record).evacuation
        altered[0] = EvacuationObservation(sourcePath: first.sourcePath, source: changed, staging: nil)
        #expect(
            ProgressJournal.reconcile(
                record: record, progress: progress,
                snapshot: ReconciliationSnapshot(
                    evacuation: altered, registrationIDs: snapshot(record).registrationIDs, musicRunning: false))
                == [.sourceDiffers(sourcePath: first.sourcePath)])
        // A missing observation.
        #expect(
            ProgressJournal.reconcile(
                record: record, progress: progress,
                snapshot: ReconciliationSnapshot(
                    evacuation: [], registrationIDs: snapshot(record).registrationIDs, musicRunning: false)
            ).count == 2)
        // Registrations: one missing, one unexpected.
        let ids = Set([RecoveryRecordTests.one, "00000000000000FF"])
        #expect(
            ProgressJournal.reconcile(record: record, progress: progress, snapshot: snapshot(record, ids: ids))
                == [
                    .registrationMissing(persistentID: RecoveryRecordTests.two.uppercased()),
                    .registrationUnexpected(persistentID: "00000000000000FF"),
                ])
    }

    @Test func reconciliationReportsARemovedRegistrationThatIsStillPresentAndAnEvacuatedFileThatIsBack() throws {
        var builder = try Builder.make()
        builder.completeThroughEvacuation()
        builder.add(.stageBegan(.clearing))
        builder.operation(
            .removeRegistration, RecoveryRecordTests.one, JournalObservation(remaining: [RecoveryRecordTests.two]))
        let progress = try builder.replay()
        let problems = ProgressJournal.reconcile(
            record: builder.record, progress: progress,
            snapshot: snapshot(builder.record, evacuated: [0], method: "rename"))
        #expect(problems.contains(.registrationStillPresent(persistentID: RecoveryRecordTests.one.uppercased())))
        #expect(
            problems.contains(.stagingMissing(stagingPath: builder.record.evacuation[1].stagingPath)))
        #expect(problems.contains(.sourceStillPresentAfterRename(sourcePath: builder.record.evacuation[1].sourcePath)))
        let copied = ProgressJournal.reconcile(
            record: builder.record, progress: progress,
            snapshot: snapshot(builder.record, evacuated: [0, 1], method: "copy", ids: [RecoveryRecordTests.two]))
        #expect(
            copied.contains(.sourceMissing(sourcePath: builder.record.evacuation[0].sourcePath)) == false)
        #expect(copied.contains(.sourceStillPresentAfterRename(sourcePath: builder.record.evacuation[0].sourcePath)))
    }

    @Test func reconciliationAllowsEitherSideOfAnOpenOperationAndRefusesOtherStates() throws {
        var builder = try Builder.make()
        builder.add(.stageBegan(.evacuation))
        let source = builder.record.evacuation[0].sourcePath
        builder.add(.intent(operation: .evacuateFile, target: source))
        let progress = try builder.replay()
        for evacuated in [Set<Int>(), [0]] {
            #expect(
                ProgressJournal.reconcile(
                    record: builder.record, progress: progress, snapshot: snapshot(builder.record, evacuated: evacuated)
                )
                .isEmpty)
        }
        var odd = snapshot(builder.record).evacuation
        odd[0] = EvacuationObservation(sourcePath: source, source: nil, staging: nil)
        #expect(
            ProgressJournal.reconcile(
                record: builder.record, progress: progress,
                snapshot: ReconciliationSnapshot(
                    evacuation: odd, registrationIDs: snapshot(builder.record).registrationIDs, musicRunning: false))
                == [.openEvacuationInconsistent(sourcePath: source)])
        var removal = try Builder.make()
        removal.completeThroughEvacuation()
        removal.add(.stageBegan(.clearing))
        removal.add(.intent(operation: .removeRegistration, target: RecoveryRecordTests.one))
        for ids in [Set(removal.record.mapping.map(\.persistentID)), [RecoveryRecordTests.two]] {
            #expect(
                ProgressJournal.reconcile(
                    record: removal.record, progress: try removal.replay(),
                    snapshot: snapshot(removal.record, evacuated: [0, 1], ids: ids)
                ).isEmpty)
        }
    }

    @Test func reconciliationRequiresMusicToBeClosedWhereTheJournalDemandsIt() throws {
        let builder = try Builder.complete()
        var upToTermination = try Builder.make()
        upToTermination.completeThroughEvacuation()
        upToTermination.clearingThroughTermination()
        let progress = try upToTermination.replay(accepted: Builder.gui)
        let running = snapshot(builder.record, evacuated: [0, 1], ids: [], music: true)
        #expect(
            ProgressJournal.reconcile(record: builder.record, progress: progress, snapshot: running)
                == [.musicRunningButMustBeClosed])
        #expect(
            ProgressJournal.reconcile(
                record: builder.record, progress: progress,
                snapshot: snapshot(builder.record, evacuated: [0, 1], ids: [], music: false)
            ).isEmpty)
        let full = try builder.replay(accepted: Builder.gui)
        let added = Set(full.newPersistentIDs)
        #expect(
            ProgressJournal.reconcile(
                record: builder.record, progress: full,
                snapshot: snapshot(builder.record, evacuated: [], ids: added, music: true)
            ).contains(
                .musicRunningButMustBeClosed) == false)
    }

    // MARK: Files

    final class Workspace {
        let url: URL
        let record: RecoveryRecord
        let bytes: Data

        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("pj-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            _ = try RecoveryRecordTests.sample().write(to: url)
            (record, bytes) = try ProgressJournalFile.loadRecord(from: url)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        var journalPath: String { url.appendingPathComponent(ProgressJournal.fileName).path }
        var data: Data { (try? Data(contentsOf: URL(fileURLWithPath: journalPath))) ?? Data() }

        func create(operations: ProgressJournalFile.Operations = .system) throws -> JournalHead {
            try ProgressJournalFile.create(
                in: url, record: record, recordBytes: bytes, ilibraryVersion: "0.2.0", operations: operations)
        }

        func append(
            _ body: JournalBody, head: JournalHead, operations: ProgressJournalFile.Operations = .system
        ) throws -> JournalHead {
            try ProgressJournalFile.append(
                body, to: url, expectedHead: head, record: record, recordBytes: bytes, operations: operations)
        }
    }

    struct Injected: Error {}

    @Test func creationWritesTheHeaderAndReadsItBack() throws {
        let workspace = try Workspace()
        let head = try workspace.create()
        #expect(head.sequence == 0)
        let state = try ProgressJournalFile.read(
            in: workspace.url, record: workspace.record, recordBytes: workspace.bytes)
        #expect(state.entries.count == 1 && state.progress.head == head)
        var buffer = stat()
        #expect(stat(workspace.journalPath, &buffer) == 0)
        #expect(buffer.st_mode & 0o777 == 0o600)
        #expect(String(decoding: workspace.data, as: UTF8.self).hasSuffix("}\n"))
        #expect(error { try workspace.create() } == .alreadyExists(path: workspace.journalPath))
        // The journal is bound to this exact record file.
        var other = workspace.bytes
        other.append(0x0A)
        #expect(
            error { try ProgressJournalFile.read(in: workspace.url, record: workspace.record, recordBytes: other) }
                == .recordMismatch)
        #expect(
            error {
                try ProgressJournalFile.create(
                    in: workspace.url, record: workspace.record, recordBytes: Data("junk".utf8),
                    ilibraryVersion: "0.2.0")
            } == .recordMismatch)
        let missing = workspace.url.appendingPathComponent("none")
        #expect(
            error {
                try ProgressJournalFile.create(
                    in: missing, record: workspace.record, recordBytes: workspace.bytes, ilibraryVersion: "0.2.0")
            } == .notADirectory(path: missing.path))
    }

    @Test func aFailureBeforeAnyByteIsWrittenRemovesTheEmptyFileAndALaterFailureKeepsIt() throws {
        let before = try Workspace()
        var failing = ProgressJournalFile.Operations.system
        failing.write = { _, _ in throw Injected() }
        guard case .writeFailed? = error({ try before.create(operations: failing) }) else {
            Issue.record("expected writeFailed")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: before.journalPath))

        let partial = try Workspace()
        let real = ProgressJournalFile.Operations.system
        var halfway = real
        halfway.write = { descriptor, data in
            try real.write(descriptor, data.prefix(10))
            throw Injected()
        }
        guard case .creationUncertain? = error({ try partial.create(operations: halfway) }) else {
            Issue.record("expected creationUncertain")
            return
        }
        #expect(partial.data.count == 10)

        let unsynced = try Workspace()
        var noSync = real
        noSync.synchronize = { _ in throw Injected() }
        guard case .creationUncertain? = error({ try unsynced.create(operations: noSync) }) else {
            Issue.record("expected creationUncertain")
            return
        }
        #expect(!unsynced.data.isEmpty)

        let mismatch = try Workspace()
        var different = real
        different.readAll = { _ in Data("other".utf8) }
        guard case .creationUncertain? = error({ try mismatch.create(operations: different) }) else {
            Issue.record("expected creationUncertain")
            return
        }
        #expect(!mismatch.data.isEmpty)
    }

    @Test func anEmptyJournalThatCannotBeRemovedMakesCreationUncertainWithoutRetry() throws {
        let workspace = try Workspace()
        let writes = CallCounter()
        var failing = ProgressJournalFile.Operations.system
        failing.write = { _, _ in
            _ = writes.next()
            throw Injected()
        }
        failing.remove = { _ in }
        guard case .creationUncertain? = error({ try workspace.create(operations: failing) }) else {
            Issue.record("expected creationUncertain")
            return
        }
        #expect(writes.next() == 2, "the header write was attempted exactly once")
        #expect(FileManager.default.fileExists(atPath: workspace.journalPath))
        #expect(workspace.data.isEmpty)
        // The empty file left behind is not a journal and is never accepted as one.
        #expect(
            error {
                try ProgressJournalFile.read(in: workspace.url, record: workspace.record, recordBytes: workspace.bytes)
            }
                == .empty)
    }

    func evacuationBodies(_ workspace: Workspace) -> [JournalBody] {
        let source = workspace.record.evacuation[0].sourcePath
        let file = ObservedFile(workspace.record.inventory[0].record)
        return [
            .stageBegan(.evacuation), .intent(operation: .evacuateFile, target: source),
            .returned(operation: .evacuateFile, target: source, succeeded: true, detail: "renamed"),
            .verified(
                operation: .evacuateFile, target: source,
                observation: JournalObservation(method: "rename", staged: file, sourcePresent: false)),
        ]
    }

    @Test func appendingValidEntriesAdvancesTheHeadAndKeepsEarlierBytes() throws {
        let workspace = try Workspace()
        var head = try workspace.create()
        var previous = workspace.data
        for body in evacuationBodies(workspace) {
            head = try workspace.append(body, head: head)
            let now = workspace.data
            #expect(now.starts(with: previous) && now.count > previous.count && now.last == 0x0A)
            previous = now
        }
        let state = try ProgressJournalFile.read(
            in: workspace.url, record: workspace.record, recordBytes: workspace.bytes)
        #expect(state.progress.head == head)
        #expect(state.progress.verifiedTargets[.evacuateFile] == [workspace.record.evacuation[0].sourcePath])
        var buffer = stat()
        #expect(stat(workspace.journalPath, &buffer) == 0 && buffer.st_mode & 0o777 == 0o600)
    }

    @Test func aStaleExpectedHeadIsRefusedAndTheFileIsUnchanged() throws {
        let workspace = try Workspace()
        let first = try workspace.create()
        let second = try workspace.append(.stageBegan(.evacuation), head: first)
        let bytes = workspace.data
        #expect(
            error { try workspace.append(.stopped(reason: "late"), head: first) }
                == .concurrentModification(expected: first, found: second))
        #expect(workspace.data == bytes)
        let wrongChecksum = JournalHead(sequence: second.sequence, checksum: first.checksum)
        guard
            case .concurrentModification? = error({ try workspace.append(.stopped(reason: "x"), head: wrongChecksum) })
        else {
            Issue.record("expected concurrentModification")
            return
        }
        #expect(workspace.data == bytes)
    }

    @Test func anInvalidEntryIsRefusedBeforeAnythingIsWritten() throws {
        let workspace = try Workspace()
        let head = try workspace.create()
        let bytes = workspace.data
        #expect(
            error { try workspace.append(.stageBegan(.clearing), head: head) }
                == .invalidEntry([.stageOutOfOrder(expected: .evacuation, found: .clearing)]))
        #expect(
            error { try workspace.append(.intent(operation: .establishGUIEmptiness, target: ""), head: head) }
                == .invalidEntry([.noStageBegun]))
        #expect(workspace.data == bytes)
    }

    @Test func aTornOrForeignJournalIsNeverAppendedTo() throws {
        let workspace = try Workspace()
        let head = try workspace.create()
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: workspace.journalPath))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"format\":".utf8))
        try handle.close()
        let bytes = workspace.data
        #expect(error { try workspace.append(.stageBegan(.evacuation), head: head) } == .tornFinalEntry)
        #expect(workspace.data == bytes)
        #expect(
            error {
                try ProgressJournalFile.read(in: workspace.url, record: workspace.record, recordBytes: workspace.bytes)
            }
                == .tornFinalEntry)
    }

    @Test func aSymbolicLinkInPlaceOfTheJournalIsRefused() throws {
        let workspace = try Workspace()
        let target = workspace.url.appendingPathComponent("real.jsonl")
        _ = try workspace.create()
        try FileManager.default.moveItem(atPath: workspace.journalPath, toPath: target.path)
        try FileManager.default.createSymbolicLink(atPath: workspace.journalPath, withDestinationPath: target.path)
        let head = JournalHead(sequence: 0, checksum: "")
        #expect(
            error { try workspace.append(.stageBegan(.evacuation), head: head) }
                == .notARegularFile(path: workspace.journalPath))
        #expect(
            error {
                try ProgressJournalFile.read(in: workspace.url, record: workspace.record, recordBytes: workspace.bytes)
            }
                == .notARegularFile(path: workspace.journalPath))
        #expect(error { try workspace.create() } == .alreadyExists(path: workspace.journalPath))
    }

    /// Runs `body` on a separate thread and waits at most `seconds` for it. If it has not finished, the test
    /// records a failure and opens the write end of `fifo`, which releases an open of its read end that blocked,
    /// so that a regression is reported instead of stalling the suite.
    static func withinBound<T: Sendable>(
        seconds: Double, releasing fifo: String, _ body: @escaping @Sendable () -> T
    ) -> T? {
        let result = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            result.set(body())
            done.signal()
        }
        if done.wait(timeout: .now() + seconds) == .success { return result.get() }
        Issue.record("the operation blocked on the named pipe for more than \(seconds) seconds")
        // A non-blocking open of the write end succeeds only while a reader is waiting, and then releases it; with no
        // reader it fails at once, so the release itself cannot block.
        let writer = open(fifo, O_WRONLY | O_NONBLOCK)
        if writer >= 0 { close(writer) }
        _ = done.wait(timeout: .now() + seconds)
        return nil
    }

    final class ResultBox<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T?
        func set(_ newValue: T) {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
        func get() -> T? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    @Test func aNamedPipeInPlaceOfTheJournalIsRefusedWithoutBlocking() throws {
        let workspace = try Workspace()
        let path = workspace.journalPath
        #expect(mkfifo(path, 0o600) == 0)
        let (url, record, bytes) = (workspace.url, workspace.record, workspace.bytes)
        let read = Self.withinBound(seconds: 10, releasing: path) {
            error { try ProgressJournalFile.read(in: url, record: record, recordBytes: bytes) }
        }
        #expect(read == .some(.notARegularFile(path: path)))
        let head = JournalHead(sequence: 0, checksum: "")
        let appended = Self.withinBound(seconds: 10, releasing: path) {
            error {
                try ProgressJournalFile.append(
                    .stageBegan(.evacuation), to: url, expectedHead: head, record: record, recordBytes: bytes)
            }
        }
        #expect(appended == .some(.notARegularFile(path: path)))
        #expect(error { try workspace.create() } == .alreadyExists(path: path))
    }

    @Test func aNamedPipeInPlaceOfTheRecordIsRefusedWithoutBlocking() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pj-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let path = url.appendingPathComponent(RecoveryRecord.fileName).path
        #expect(mkfifo(path, 0o600) == 0)
        let loaded = Self.withinBound(seconds: 10, releasing: path) {
            error { _ = try ProgressJournalFile.loadRecord(from: url) }
        }
        #expect(loaded == .some(.notARegularFile(path: path)))
    }

    @Test func aJournalWithAHardLinkOrUnsafePermissionsIsRefused() throws {
        let workspace = try Workspace()
        let head = try workspace.create()
        let bytes = workspace.data
        let alias = workspace.url.appendingPathComponent("alias").path
        #expect(link(workspace.journalPath, alias) == 0)
        guard case .unsafeFile? = error({ try workspace.append(.stageBegan(.evacuation), head: head) }) else {
            Issue.record("expected unsafeFile for a hard link")
            return
        }
        #expect(unlink(alias) == 0)
        #expect(chmod(workspace.journalPath, 0o622) == 0)
        guard case .unsafeFile? = error({ try workspace.append(.stageBegan(.evacuation), head: head) }) else {
            Issue.record("expected unsafeFile for permissions")
            return
        }
        #expect(chmod(workspace.journalPath, 0o660) == 0)
        guard case .unsafeFile? = error({ try workspace.append(.stageBegan(.evacuation), head: head) }) else {
            Issue.record("expected unsafeFile for group write")
            return
        }
        #expect(workspace.data == bytes)
        #expect(chmod(workspace.journalPath, 0o600) == 0)
        _ = try workspace.append(.stageBegan(.evacuation), head: head)
    }

    @Test func aLockHeldByAnotherDescriptorRefusesTheAppend() throws {
        let workspace = try Workspace()
        let head = try workspace.create()
        let holder = open(workspace.journalPath, O_RDONLY)
        #expect(holder >= 0)
        #expect(flock(holder, LOCK_EX | LOCK_NB) == 0)
        let bytes = workspace.data
        #expect(
            error { try workspace.append(.stageBegan(.evacuation), head: head) }
                == .locked(path: workspace.journalPath))
        #expect(workspace.data == bytes)
        close(holder)
        _ = try workspace.append(.stageBegan(.evacuation), head: head)
    }

    @Test func aFailedWriteOrSynchronizationIsUncertainAndNeverSuccess() throws {
        let real = ProgressJournalFile.Operations.system
        func attempt(_ change: (inout ProgressJournalFile.Operations) -> Void) throws -> (
            ProgressJournalError?, Data, Data
        ) {
            let workspace = try Workspace()
            let head = try workspace.create()
            let before = workspace.data
            var operations = real
            change(&operations)
            let result = error { try workspace.append(.stageBegan(.evacuation), head: head, operations: operations) }
            return (result, before, workspace.data)
        }
        let (writeError, writeBefore, writeAfter) = try attempt { $0.write = { _, _ in throw Injected() } }
        guard case .appendUncertain? = writeError else {
            Issue.record("expected appendUncertain, got \(String(describing: writeError))")
            return
        }
        #expect(writeAfter == writeBefore)
        let (partialError, partialBefore, partialAfter) = try attempt { operations in
            operations.write = { descriptor, data in
                try real.write(descriptor, data.prefix(7))
                throw Injected()
            }
        }
        guard case .appendUncertain? = partialError else {
            Issue.record("expected appendUncertain")
            return
        }
        #expect(partialAfter.count == partialBefore.count + 7)
        #expect(error { try ProgressJournal.parse(partialAfter) } == .tornFinalEntry)
        let (syncError, syncBefore, syncAfter) = try attempt { $0.synchronize = { _ in throw Injected() } }
        guard case .appendUncertain? = syncError else {
            Issue.record("expected appendUncertain")
            return
        }
        #expect(syncAfter.count > syncBefore.count)
        let (readError, _, _) = try attempt { $0.readAll = Self.failingSecondRead(real) }
        guard case .appendUncertain? = readError else {
            Issue.record("expected appendUncertain")
            return
        }
        let (extraError, _, _) = try attempt { operations in
            let original = operations.write
            operations.write = { descriptor, data in
                try original(descriptor, data)
                try original(descriptor, Data("x".utf8))
            }
        }
        guard case .appendUncertain? = extraError else {
            Issue.record("expected appendUncertain for unexpected bytes")
            return
        }
    }

    static func failingSecondRead(_ real: ProgressJournalFile.Operations) -> @Sendable (Int32) throws -> Data {
        let calls = CallCounter()
        return { descriptor in
            if calls.next() > 1 { throw Injected() }
            return try real.readAll(descriptor)
        }
    }

    final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return count
        }
    }
}
