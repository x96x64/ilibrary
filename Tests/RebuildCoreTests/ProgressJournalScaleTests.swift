import Foundation
import Testing

@testable import RebuildCore

/// A library of 5,000 tracks in 500 albums of 10 files, built in memory. The files do not exist on disk, because
/// neither the replay nor the append touches them.
struct ScaleFixture {
    static let albumCount = 500
    static let filesPerAlbum = 10
    static var fileCount: Int { albumCount * filesPerAlbum }

    static let sourceRoot = "/lib/media/Music"
    static let stagingDirectory = "/st/stage"

    let record: RecoveryRecord
    let recordBytes: Data

    /// The shared fixture. Building it validates a record of 5,000 files, which is itself part of the scale.
    static let shared: ScaleFixture = {
        do { return try ScaleFixture() } catch { fatalError("the scale fixture cannot be built: \(error)") }
    }()

    static func persistentID(_ index: Int) -> String { String(format: "%016X", 0x1000 + index) }
    static func addedID(_ index: Int) -> String { String(format: "%016X", 0x200000 + index) }
    static func album(_ index: Int) -> String { String(format: "album-%03d", index) }

    init() throws {
        var inventory: [SourcedFileRecord] = []
        var registrations: [RegistrationRecord] = []
        var mapping: [RegistrationMapping] = []
        for album in 0..<Self.albumCount {
            for track in 0..<Self.filesPerAlbum {
                let index = album * Self.filesPerAlbum + track
                let path = String(format: "Artist/Album %03d/%02d Track.m4a", album, track + 1)
                let location = Self.sourceRoot + "/" + path
                inventory.append(
                    SourcedFileRecord(
                        sourceRoot: Self.sourceRoot,
                        record: FileRecord(
                            path: path, size: UInt64(1000 + index), sha256: SHA256.digest(of: Array(path.utf8)),
                            modification: FileTimestamp(seconds: 1_000_000 + Int64(index), nanoseconds: 5),
                            creation: FileTimestamp(seconds: 900_000 + Int64(index), nanoseconds: 7))))
                registrations.append(
                    RegistrationRecord(
                        persistentID: Self.persistentID(index), name: "Track \(track + 1)", album: "Album \(album)",
                        artist: "Artist", albumArtist: "Artist", location: location, cloudStatus: "",
                        dateAdded: 1_700_000_000 + Int64(index)))
                mapping.append(RegistrationMapping(location: location, persistentID: Self.persistentID(index)))
            }
        }
        let additionList = (0..<Self.albumCount).map(Self.album)
        let record = RecoveryRecord(
            createdAt: "2026-10-20T12:00:00Z", ilibraryVersion: "0.2.0", catalogPath: "/ws/catalog.json",
            catalogSHA256: SHA256.digest(of: [9]),
            locations: RebuildLocations(
                sources: [Self.sourceRoot], mediaFolder: "/lib/media", backupRoot: "/bk/backup",
                restorationDirectory: "/rs/restore", stagingDirectory: Self.stagingDirectory,
                workspaceDirectory: "/ws/work"),
            inventory: inventory, registrations: registrations, mapping: mapping, additionList: additionList,
            expectedDisplayList: additionList.reversed(),
            evacuation: EvacuationEntry.plan(inventory: inventory, stagingDirectory: Self.stagingDirectory),
            backup: BackupSection(
                root: "/bk/backup", volumeUUID: "UUID-1", filesystemType: "apfs", timestampPolicy: .apfs,
                verification: VerificationSummary(checkedCount: inventory.count, success: true),
                independenceReasons: [], maintainerConfirmed: true, verifiedAt: "2026-10-20T12:01:00Z",
                disconnectedAt: "2026-10-20T12:02:00Z"),
            restoration: RestorationSection(
                directory: "/rs/restore",
                verification: VerificationSummary(checkedCount: inventory.count, success: true),
                verifiedAt: "2026-10-20T12:03:00Z"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sf-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try record.write(to: directory)
        let loaded = try ProgressJournalFile.loadRecord(from: directory)
        self.record = loaded.record
        self.recordBytes = loaded.bytes
    }

    /// The bodies of a complete rebuild in order: an intent, a successful return, and a verification for every
    /// operation.
    func completeBodies() -> [JournalBody] {
        var bodies: [JournalBody] = []
        func operation(_ operation: RebuildOperation, _ target: String, _ observation: JournalObservation) {
            bodies.append(.intent(operation: operation, target: target))
            bodies.append(.returned(operation: operation, target: target, succeeded: true, detail: "ok"))
            bodies.append(.verified(operation: operation, target: target, observation: observation))
        }
        var files: [String: FileRecord] = [:]
        for item in record.inventory { files[item.absolutePath] = item.record }

        bodies.append(.stageBegan(.evacuation))
        for entry in record.evacuation {
            let file = ObservedFile(files[entry.sourcePath]!)
            operation(
                .evacuateFile, entry.sourcePath,
                JournalObservation(method: "rename", staged: file, sourcePresent: false))
        }
        bodies.append(.stageCompleted(.evacuation))

        bodies.append(.stageBegan(.clearing))
        var remaining = record.mapping.count
        for item in record.mapping {
            remaining -= 1
            operation(.removeRegistration, item.persistentID, JournalObservation(remainingCount: remaining))
        }
        operation(.confirmLibraryEmpty, "", JournalObservation(registrationCount: 0))
        operation(.terminateMusic, "", JournalObservation(musicRunning: false))
        bodies.append(.stageCompleted(.clearing))

        bodies.append(.stageBegan(.application))
        for entry in record.evacuation {
            let file = ObservedFile(files[entry.sourcePath]!)
            operation(.applyFile, entry.stagingPath, JournalObservation(musicRunning: false, result: file))
        }
        bodies.append(.stageCompleted(.application))

        bodies.append(.stageBegan(.addition))
        for (album, label) in record.additionList.enumerated() {
            let ids = (0..<Self.filesPerAlbum).map { Self.addedID(album * Self.filesPerAlbum + $0) }
            operation(.addAlbum, label, JournalObservation(newPersistentIDs: ids, laterThanPreviousAlbum: true))
        }
        bodies.append(.stageCompleted(.addition))

        bodies.append(.stageBegan(.display))
        operation(
            .confirmDisplay, ProgressJournal.displayTarget, JournalObservation(observed: record.expectedDisplayList))
        bodies.append(.stageCompleted(.display))
        return bodies
    }
}

/// The progress journal of a library of 5,000 tracks. The bounds are generous for a debug build on a CI runner;
/// the measured durations are printed so that a regression to quadratic behaviour is visible long before a bound
/// fails.
@Suite struct ProgressJournalScaleTests {
    @Test func aCompleteJournalOfFiveThousandTracksLoadsWithinTheBound() throws {
        let fixture = ScaleFixture.shared
        let clock = ContinuousClock()

        var builder = try JournalBuilder(record: fixture.record, recordBytes: fixture.recordBytes)
        let bodies = fixture.completeBodies()
        let buildStart = clock.now
        for body in bodies { builder.add(body) }
        var data = Data()
        for entry in builder.entries { data.append(try entry.line()) }
        let buildTime = buildStart.duration(to: clock.now)
        print("scale: built \(builder.entries.count) entries (\(data.count) bytes) in \(buildTime)")
        #expect(builder.entries.count > 45_000)

        let start = clock.now
        let loaded = try ProgressJournal.load(data: data, record: fixture.record, recordBytes: fixture.recordBytes)
        let elapsed = start.duration(to: clock.now)
        print("scale: ProgressJournal.load of \(loaded.entries.count) entries took \(elapsed)")
        #expect(elapsed < .seconds(30))

        let progress = loaded.progress
        #expect(loaded.entries.count == builder.entries.count)
        #expect(progress.completedStages == RebuildStage.allCases)
        #expect(progress.canProceed && progress.currentStage == nil)
        #expect(progress.verifiedCount(.evacuateFile) == ScaleFixture.fileCount)
        #expect(progress.verifiedCount(.removeRegistration) == ScaleFixture.fileCount)
        #expect(progress.verifiedCount(.applyFile) == ScaleFixture.fileCount)
        #expect(progress.verifiedCount(.addAlbum) == ScaleFixture.albumCount)
        #expect(progress.newPersistentIDs.count == ScaleFixture.fileCount)
        #expect(progress.isVerified(.confirmDisplay, ProgressJournal.displayTarget))
        #expect(progress.head.sequence == loaded.entries.count - 1)
    }

    @Test func threeThousandEntriesAreAppendedToARealFileWithoutRereadingIt() throws {
        let fixture = ScaleFixture.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sa-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try ProgressJournalFile.create(
            in: directory, record: fixture.record, recordBytes: fixture.recordBytes, ilibraryVersion: "0.2.0")
        var state = try ProgressJournalFile.readState(
            in: directory, record: fixture.record, recordBytes: fixture.recordBytes)

        let bodies = Array(fixture.completeBodies().prefix(3_001))
        let clock = ContinuousClock()
        let start = clock.now
        for body in bodies {
            state = try ProgressJournalFile.append(
                body, to: directory, state: state, record: fixture.record, recordBytes: fixture.recordBytes)
        }
        let elapsed = start.duration(to: clock.now)
        print("scale: \(bodies.count) incremental appends to a real file took \(elapsed)")
        #expect(elapsed < .seconds(60))

        #expect(state.progress.head.sequence == bodies.count)
        #expect(state.progress.verifiedCount(.evacuateFile) == (bodies.count - 1) / 3)
        let fresh = try ProgressJournalFile.readState(
            in: directory, record: fixture.record, recordBytes: fixture.recordBytes)
        #expect(fresh == state)
        let path = directory.appendingPathComponent(ProgressJournal.fileName).path
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.size] as? NSNumber)?.intValue == state.byteCount)
    }
}
