import Foundation
import Testing

@testable import RebuildCore

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The incremental state and append of `ProgressJournalFile`, which never read the whole journal again.
@Suite struct ProgressJournalIncrementalTests {
    typealias Workspace = ProgressJournalTests.Workspace
    typealias Injected = ProgressJournalTests.Injected

    func failure(_ run: () throws -> Any) -> ProgressJournalError? {
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

    func readState(_ workspace: Workspace) throws -> JournalState {
        try ProgressJournalFile.readState(in: workspace.url, record: workspace.record, recordBytes: workspace.bytes)
    }

    func append(
        _ body: JournalBody, _ workspace: Workspace, _ state: JournalState,
        operations: ProgressJournalFile.Operations = .system
    ) throws -> JournalState {
        try ProgressJournalFile.append(
            body, to: workspace.url, state: state, record: workspace.record, recordBytes: workspace.bytes,
            operations: operations)
    }

    /// A workspace whose journal holds the header and the entries of the first stage that has begun.
    func begun() throws -> (workspace: Workspace, state: JournalState) {
        let workspace = try Workspace()
        _ = try workspace.create()
        var state = try readState(workspace)
        state = try append(.stageBegan(.evacuation), workspace, state)
        return (workspace, state)
    }

    /// Replaces the byte at `offset` with a different one.
    func replaceByte(at offset: Int, in workspace: Workspace) throws {
        let handle = try FileHandle(forUpdating: URL(fileURLWithPath: workspace.journalPath))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let current = try handle.read(upToCount: 1) ?? Data()
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: Data([current.first == 0x61 ? 0x62 : 0x61]))
    }

    /// Overwrites the start of the journal with `bytes` without changing its size.
    func overwrite(_ bytes: Data, in workspace: Workspace) throws {
        let handle = try FileHandle(forUpdating: URL(fileURLWithPath: workspace.journalPath))
        defer { try? handle.close() }
        try handle.write(contentsOf: bytes)
    }

    // MARK: State

    @Test func theStateOfAHeaderOnlyJournalDescribesTheHeaderAndTheFileSize() throws {
        let workspace = try Workspace()
        let head = try workspace.create()
        let state = try readState(workspace)
        #expect(state.progress.head == head)
        #expect(state.byteCount == workspace.data.count)
        #expect(state == (try readState(workspace)))
        #expect(
            state.progress
                == (try ProgressJournalFile.read(
                    in: workspace.url, record: workspace.record, recordBytes: workspace.bytes))
                .progress)
    }

    @Test func readingTheStateRefusesWhatReadingRefuses() throws {
        let workspace = try Workspace()
        #expect(failure { try readState(workspace) } == .notARegularFile(path: workspace.journalPath))
        _ = try workspace.create()
        var other = workspace.bytes
        other.append(0x0A)
        #expect(
            failure {
                try ProgressJournalFile.readState(in: workspace.url, record: workspace.record, recordBytes: other)
            }
                == .recordMismatch)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: workspace.journalPath))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"format\":".utf8))
        try handle.close()
        #expect(failure { try readState(workspace) } == .tornFinalEntry)
    }

    // MARK: Success

    @Test func appendingEveryEntryOfACompleteJournalMatchesAFreshRead() throws {
        let workspace = try Workspace()
        _ = try workspace.create()
        var state = try readState(workspace)
        let bodies = try JournalBuilder.complete().entries.dropFirst().map(\.body)
        for (offset, body) in bodies.enumerated() {
            let before = workspace.data
            state = try append(body, workspace, state)
            let after = workspace.data
            #expect(after.starts(with: before) && after.last == 0x0A)
            #expect(state.byteCount == after.count)
            #expect(state.progress.head.sequence == offset + 1)
            if offset % 7 == 0 { #expect(state == (try readState(workspace))) }
        }
        #expect(state == (try readState(workspace)))
        #expect(state.progress.completedStages == RebuildStage.allCases)
        // Only a stop may follow the last stage, and many may follow one another.
        for index in 0..<200 { state = try append(.stopped(reason: "stop \(index)"), workspace, state) }
        #expect(state == (try readState(workspace)))
        #expect(state.progress.stopCount == 200)
        #expect(state.byteCount == workspace.data.count)
        let whole = try ProgressJournalFile.read(
            in: workspace.url, record: workspace.record, recordBytes: workspace.bytes)
        #expect(whole.progress == state.progress)
        var buffer = stat()
        #expect(stat(workspace.journalPath, &buffer) == 0 && buffer.st_mode & 0o777 == 0o600)
    }

    @Test func theReturnedStateKeepsTheLookupsOfTheProgressConsistent() throws {
        let workspace = try Workspace()
        _ = try workspace.create()
        var state = try readState(workspace)
        for entry in try JournalBuilder.complete().entries.dropFirst() {
            state = try append(entry.body, workspace, state)
        }
        let fresh = try readState(workspace).progress
        #expect(state.progress.newPersistentIDSet == fresh.newPersistentIDSet)
        #expect(state.progress.appliedPathKeys == fresh.appliedPathKeys)
        #expect(state.progress.verifiedSets == fresh.verifiedSets)
        for (operation, targets) in state.progress.verifiedTargets {
            #expect(Set(targets) == state.progress.verifiedSets[operation])
            for target in targets { #expect(state.progress.isVerified(operation, target)) }
        }
        #expect(!state.progress.isVerified(.evacuateFile, "/not/in/the/plan"))
    }

    // MARK: Refusals

    @Test func anEntryAppendedByAnotherWriterFirstIsDetectedAndNothingIsWritten() throws {
        let (workspace, stale) = try begun()
        // Another writer appends with the state that this one also holds.
        let newer = try append(.stopped(reason: "other writer"), workspace, stale)
        let bytes = workspace.data
        #expect(
            failure { try append(.stopped(reason: "late"), workspace, stale) }
                == .concurrentModification(expected: stale.progress.head, found: newer.progress.head))
        #expect(workspace.data == bytes)
        // A writer that appends by expected head is detected in the same way.
        let byHead = try workspace.append(.stopped(reason: "by head"), head: newer.progress.head)
        let byHeadBytes = workspace.data
        #expect(
            failure { try append(.stopped(reason: "late"), workspace, newer) }
                == .concurrentModification(expected: newer.progress.head, found: byHead))
        #expect(workspace.data == byHeadBytes)
        // A refreshed state is accepted.
        let refreshed = try readState(workspace)
        let accepted = try append(.stopped(reason: "again"), workspace, refreshed)
        #expect(accepted == (try readState(workspace)))
    }

    @Test func aTruncatedFileIsDetectedAndNothingIsWritten() throws {
        let (workspace, begun) = try begun()
        let first = try append(.stopped(reason: "one"), workspace, begun)
        let second = try append(.stopped(reason: "two"), workspace, first)
        let headerEntry = try ProgressJournal.parse(workspace.data)[0]
        // Truncation at a line boundary: the size differs and the final line is the earlier entry.
        #expect(truncate(workspace.journalPath, off_t(first.byteCount)) == 0)
        let bytes = workspace.data
        #expect(
            failure { try append(.stopped(reason: "late"), workspace, second) }
                == .concurrentModification(expected: second.progress.head, found: first.progress.head))
        #expect(workspace.data == bytes)
        // Truncation inside the final line: the file no longer ends with a newline.
        #expect(truncate(workspace.journalPath, off_t(first.byteCount - 5)) == 0)
        let torn = workspace.data
        #expect(
            failure { try append(.stopped(reason: "late"), workspace, first) }
                == .concurrentModification(
                    expected: first.progress.head, found: JournalHead(sequence: -1, checksum: "")))
        #expect(workspace.data == torn)
        // Truncation to the header alone.
        let headerLength = try headerEntry.line().count
        #expect(truncate(workspace.journalPath, off_t(headerLength)) == 0)
        #expect(
            failure { try append(.stopped(reason: "late"), workspace, begun) }
                == .concurrentModification(
                    expected: begun.progress.head, found: JournalHead(sequence: 0, checksum: headerEntry.checksum)))
    }

    @Test func aChangedByteOfTheFinalLineIsDetectedAndNothingIsWritten() throws {
        let (workspace, state) = try begun()
        let original = workspace.data
        let lineStart = original.dropLast().lastIndex(of: 0x0A)! + 1
        #expect(state.byteCount - lineStart > 40)
        // A byte of the checksum, a byte of the body, and the final newline.
        for offset in [state.byteCount - 5, lineStart + 12, state.byteCount - 1] {
            try replaceByte(at: offset, in: workspace)
            let changed = workspace.data
            #expect(changed != original && changed.count == original.count)
            #expect(
                failure { try append(.stopped(reason: "x"), workspace, state) }
                    == .concurrentModification(
                        expected: state.progress.head, found: JournalHead(sequence: -1, checksum: "")),
                "a change at offset \(offset)")
            #expect(workspace.data == changed)
            try overwrite(original, in: workspace)
            #expect(workspace.data == original)
        }
        // Once restored, the same state is accepted.
        _ = try append(.stopped(reason: "restored"), workspace, state)
    }

    @Test func aFinalLineWithoutANewlineOrWithTrailingBytesIsDetected() throws {
        let (workspace, state) = try begun()
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: workspace.journalPath))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("x".utf8))
        try handle.close()
        let bytes = workspace.data
        guard case .concurrentModification? = failure({ try append(.stopped(reason: "x"), workspace, state) }) else {
            Issue.record("expected concurrentModification")
            return
        }
        #expect(workspace.data == bytes)
    }

    @Test func anInvalidEntryIsRefusedBeforeAnythingIsWrittenAndTheStateStaysUsable() throws {
        let (workspace, state) = try begun()
        let bytes = workspace.data
        #expect(
            failure { try append(.stageBegan(.clearing), workspace, state) }
                == .invalidEntry([.stageNotCompleted(current: .evacuation)]))
        #expect(
            failure { try append(.intent(operation: .terminateMusic, target: ""), workspace, state) }
                == .invalidEntry([
                    .operationNotInStage(operation: .terminateMusic, stage: .clearing, current: .evacuation)
                ]))
        #expect(
            failure { try append(.intent(operation: .evacuateFile, target: "/not/planned"), workspace, state) }
                == .invalidEntry([.targetNotInPlan(operation: .evacuateFile, target: "/not/planned")]))
        #expect(workspace.data == bytes)
        let next = try append(.stopped(reason: "still usable"), workspace, state)
        #expect(next == (try readState(workspace)))
    }

    @Test func aStateOfAnotherRecordIsRefused() throws {
        let (workspace, state) = try begun()
        var other = workspace.record
        other.ilibraryVersion = "9.9.9"
        other = try other.sealed()
        let bytes = workspace.data
        #expect(
            failure {
                try ProgressJournalFile.append(
                    .stopped(reason: "x"), to: workspace.url, state: state, record: other, recordBytes: workspace.bytes)
            } == .recordMismatch)
        #expect(workspace.data == bytes)
    }

    @Test func theStrictFileChecksStillApply() throws {
        let (workspace, state) = try begun()
        let bytes = workspace.data
        let alias = workspace.url.appendingPathComponent("alias").path
        #expect(link(workspace.journalPath, alias) == 0)
        guard case .unsafeFile? = failure({ try append(.stopped(reason: "x"), workspace, state) }) else {
            Issue.record("expected unsafeFile for a hard link")
            return
        }
        #expect(unlink(alias) == 0)
        for mode in [mode_t(0o622), mode_t(0o660)] {
            #expect(chmod(workspace.journalPath, mode) == 0)
            guard case .unsafeFile? = failure({ try append(.stopped(reason: "x"), workspace, state) }) else {
                Issue.record("expected unsafeFile for mode \(String(mode, radix: 8))")
                return
            }
        }
        #expect(chmod(workspace.journalPath, 0o600) == 0)
        #expect(workspace.data == bytes)

        let holder = open(workspace.journalPath, O_RDONLY)
        #expect(holder >= 0)
        #expect(flock(holder, LOCK_EX | LOCK_NB) == 0)
        #expect(failure { try append(.stopped(reason: "x"), workspace, state) } == .locked(path: workspace.journalPath))
        close(holder)
        #expect(workspace.data == bytes)

        let target = workspace.url.appendingPathComponent("real.jsonl")
        try FileManager.default.moveItem(atPath: workspace.journalPath, toPath: target.path)
        try FileManager.default.createSymbolicLink(atPath: workspace.journalPath, withDestinationPath: target.path)
        #expect(
            failure { try append(.stopped(reason: "x"), workspace, state) }
                == .notARegularFile(path: workspace.journalPath))
        #expect(failure { try readState(workspace) } == .notARegularFile(path: workspace.journalPath))
        try FileManager.default.removeItem(atPath: workspace.journalPath)
        try FileManager.default.moveItem(atPath: target.path, toPath: workspace.journalPath)
        _ = try append(.stopped(reason: "restored"), workspace, state)
    }

    @Test func aMissingJournalIsRefused() throws {
        let (workspace, state) = try begun()
        try FileManager.default.removeItem(atPath: workspace.journalPath)
        #expect(
            failure { try append(.stopped(reason: "x"), workspace, state) }
                == .notARegularFile(path: workspace.journalPath))
    }

    // MARK: Uncertainty

    @Test func aFailureAfterTheWriteStartedIsUncertainAndTheOldStateIsThenRefused() throws {
        let real = ProgressJournalFile.Operations.system
        func attempt(_ change: (inout ProgressJournalFile.Operations) -> Void) throws -> (
            ProgressJournalError?, Data, Data, Workspace, JournalState
        ) {
            let (workspace, state) = try begun()
            let before = workspace.data
            var operations = real
            change(&operations)
            let result = failure { try append(.stopped(reason: "x"), workspace, state, operations: operations) }
            return (result, before, workspace.data, workspace, state)
        }
        let (writeError, writeBefore, writeAfter, _, _) = try attempt { $0.write = { _, _ in throw Injected() } }
        guard case .appendUncertain? = writeError else {
            Issue.record("expected appendUncertain, got \(String(describing: writeError))")
            return
        }
        #expect(writeAfter == writeBefore)
        let (partialError, partialBefore, partialAfter, partialSpace, partialState) = try attempt { operations in
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
        // The state no longer describes the file, so a retry with it is refused.
        guard case .concurrentModification? = failure({ try append(.stopped(reason: "y"), partialSpace, partialState) })
        else {
            Issue.record("expected concurrentModification after a partial write")
            return
        }
        let (syncError, syncBefore, syncAfter, _, _) = try attempt { $0.synchronize = { _ in throw Injected() } }
        guard case .appendUncertain? = syncError else {
            Issue.record("expected appendUncertain")
            return
        }
        #expect(syncAfter.count > syncBefore.count)
        let (extraError, extraBefore, extraAfter, _, _) = try attempt { operations in
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
        #expect(extraAfter.count > extraBefore.count + 1)
        let (shortError, _, _, _, _) = try attempt { operations in
            operations.write = { descriptor, data in try real.write(descriptor, Data(data.dropLast())) }
        }
        guard case .appendUncertain? = shortError else {
            Issue.record("expected appendUncertain for a short line")
            return
        }
    }
}
