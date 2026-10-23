import Foundation
import Testing

@testable import RebuildCore

@Suite struct RecoveryRecordTests {
    static let locations = RebuildLocations(
        sources: ["/lib/media/Music"], mediaFolder: "/lib/media", backupRoot: "/bk/backup",
        restorationDirectory: "/rs/restore", stagingDirectory: "/st/stage", workspaceDirectory: "/ws/work")
    static let one = "0000000000000001"
    static let two = "00000000000000AB"

    static func entry(_ path: String) -> SourcedFileRecord {
        SourcedFileRecord(
            sourceRoot: "/lib/media/Music",
            record: FileRecord(
                path: path, size: 3, sha256: SHA256.digest(of: Array(path.utf8)),
                modification: FileTimestamp(seconds: 100, nanoseconds: 5),
                creation: FileTimestamp(seconds: 90, nanoseconds: 7)))
    }

    static func sample() -> RecoveryRecord {
        let inventory = [entry("A/1.m4a"), entry("A/2.m4a")]
        let registrations = [
            RegistrationRecord(
                persistentID: one, name: "1", album: "A", artist: "x", albumArtist: "x",
                location: "/lib/media/Music/A/1.m4a", cloudStatus: "", dateAdded: 5),
            RegistrationRecord(
                persistentID: two, name: "2", album: "A", artist: "x", albumArtist: "x",
                location: "/lib/media/Music/A/2.m4a", cloudStatus: "unknown", dateAdded: nil),
        ]
        return RecoveryRecord(
            createdAt: "2026-10-20T12:00:00Z", ilibraryVersion: "0.2.0", catalogPath: "/ws/catalog.json",
            catalogSHA256: SHA256.digest(of: [9]), locations: locations, inventory: inventory,
            registrations: registrations,
            mapping: [
                RegistrationMapping(location: "/lib/media/Music/A/1.m4a", persistentID: one),
                RegistrationMapping(location: "/lib/media/Music/A/2.m4a", persistentID: two),
            ],
            additionList: ["a1", "a2", "a3"], expectedDisplayList: ["a3", "a2", "a1"],
            evacuation: EvacuationEntry.plan(inventory: inventory, stagingDirectory: "/st/stage"),
            backup: BackupSection(
                root: "/bk/backup", volumeUUID: "UUID-1", filesystemType: "apfs", timestampPolicy: .apfs,
                verification: VerificationSummary(checkedCount: 2, success: true), independenceReasons: [],
                maintainerConfirmed: true, verifiedAt: "2026-10-20T12:01:00Z", disconnectedAt: "2026-10-20T12:02:00Z"),
            restoration: RestorationSection(
                directory: "/rs/restore", verification: VerificationSummary(checkedCount: 2, success: true),
                verifiedAt: "2026-10-20T12:03:00Z"))
    }

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rr-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func names(_ url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    func problems(_ mutate: (inout RecoveryRecord) -> Void) throws -> [RecoveryRecordProblem] {
        var record = Self.sample()
        mutate(&record)
        return try record.sealed().problems()
    }

    /// Writes a record file by hand, bypassing validation, with a correct checksum, and loads it.
    func loadEdited(_ mutate: (inout RecoveryRecord) -> Void) throws -> Result<RecoveryRecord, RecoveryRecordError> {
        var record = Self.sample()
        mutate(&record)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(try record.sealed()).write(to: directory.appendingPathComponent(RecoveryRecord.fileName))
        do { return .success(try RecoveryRecord.load(from: directory)) } catch let error as RecoveryRecordError {
            return .failure(error)
        }
    }

    func invalid(_ result: Result<RecoveryRecord, RecoveryRecordError>) -> [RecoveryRecordProblem] {
        if case .failure(.invalid(let list)) = result { return list }
        return []
    }

    @Test func sampleIsValid() { #expect(Self.sample().problems().isEmpty) }

    @Test func writeAndLoadRoundTrip() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let written = try Self.sample().write(to: directory)
        #expect(names(directory) == [RecoveryRecord.fileName])
        let loaded = try RecoveryRecord.load(from: directory)
        #expect(loaded == written)
        #expect(loaded.format == "ilibrary-rebuild-record-1")
        #expect(loaded.stage == .prepared)
        #expect(!loaded.checksum.isEmpty)
        let text = try String(contentsOf: directory.appendingPathComponent(RecoveryRecord.fileName), encoding: .utf8)
        #expect(text.contains("/lib/media/Music/A/1.m4a"))
    }

    @Test func writeRefusesToOverwrite() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.sample().write(to: directory)
        let before = try Data(contentsOf: directory.appendingPathComponent(RecoveryRecord.fileName))
        #expect(throws: RecoveryRecordError.self) { try Self.sample().write(to: directory) }
        #expect(try Data(contentsOf: directory.appendingPathComponent(RecoveryRecord.fileName)) == before)
        #expect(names(directory) == [RecoveryRecord.fileName])
    }

    @Test func writeRefusesAnInvalidRecordAndAMissingDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var record = Self.sample()
        record.expectedDisplayList = record.additionList
        #expect(throws: RecoveryRecordError.self) { try record.write(to: directory) }
        #expect(names(directory).isEmpty)
        #expect(throws: RecoveryRecordError.notADirectory(path: directory.path + "/none")) {
            try Self.sample().write(to: directory.appendingPathComponent("none"))
        }
    }

    struct Injected: Error {}

    @Test func failuresLeaveNoTemporaryFileBehind() throws {
        let steps = [
            "writeTemporary", "writeTemporaryAfterCreate", "publish", "synchronizeDirectory", "read", "readBack",
        ]
        for step in steps {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            var operations = RecordFileOperations.system
            let real = RecordFileOperations.system
            switch step {
            case "writeTemporary": operations.writeTemporary = { _, _ in throw Injected() }
            case "writeTemporaryAfterCreate":
                operations.writeTemporary = { path, data in
                    try real.writeTemporary(path, data)
                    throw Injected()
                }
            case "publish": operations.publish = { _, _ in throw Injected() }
            case "synchronizeDirectory": operations.synchronizeDirectory = { _ in throw Injected() }
            case "read": operations.read = { _ in throw Injected() }
            default: operations.read = { path in try real.read(path).dropLast() }
            }
            #expect(throws: (any Error).self) { try Self.sample().write(to: directory, operations: operations) }
            #expect(names(directory).isEmpty, "\(step) left \(names(directory))")
        }
    }

    @Test func aRecordCreatedByAnotherActorBeforePublicationIsNeverReplaced() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let finalURL = directory.appendingPathComponent(RecoveryRecord.fileName)
        let foreign = Data("foreign record".utf8)
        var operations = RecordFileOperations.system
        let real = RecordFileOperations.system
        // Models another actor that creates the record between the existence check and the publication.
        operations.writeTemporary = { path, data in
            try real.writeTemporary(path, data)
            try foreign.write(to: finalURL)
        }
        #expect(throws: RecoveryRecordError.alreadyExists(path: finalURL.path)) {
            try Self.sample().write(to: directory, operations: operations)
        }
        #expect(try Data(contentsOf: finalURL) == foreign)
        #expect(names(directory) == [RecoveryRecord.fileName])
    }

    @Test func aFailedPublicationRemovesOnlyTheTemporaryFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let finalURL = directory.appendingPathComponent(RecoveryRecord.fileName)
        let foreign = Data("foreign record".utf8)
        var operations = RecordFileOperations.system
        let real = RecordFileOperations.system
        operations.writeTemporary = { path, data in
            try real.writeTemporary(path, data)
            try foreign.write(to: finalURL)
        }
        operations.publish = { _, _ in throw RecoveryRecordError.writeFailed("link: injected") }
        #expect(throws: RecoveryRecordError.writeFailed("link: injected")) {
            try Self.sample().write(to: directory, operations: operations)
        }
        #expect(try Data(contentsOf: finalURL) == foreign)
        #expect(names(directory) == [RecoveryRecord.fileName])
    }

    @Test func aReadBackFailureAfterPublicationRemovesThePublishedRecord() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var operations = RecordFileOperations.system
        operations.read = { _ in throw Injected() }
        #expect(throws: (any Error).self) { try Self.sample().write(to: directory, operations: operations) }
        #expect(names(directory).isEmpty)
    }

    @Test func readBackDetectsADifferentFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var operations = RecordFileOperations.system
        let real = RecordFileOperations.system
        let other = try Self.sample().sealed()
        var altered = other
        altered.ilibraryVersion = "9.9.9"
        let alteredData = try JSONEncoder().encode(try altered.sealed())
        operations.read = { _ in alteredData }
        _ = real
        #expect(throws: RecoveryRecordError.readBackMismatch) {
            try Self.sample().write(to: directory, operations: operations)
        }
        #expect(names(directory).isEmpty)
    }

    @Test func loadRefusesWrongFormatAndMalformedFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(RecoveryRecord.fileName)
        #expect(throws: RecoveryRecordError.self) { try RecoveryRecord.load(from: directory) }
        try Data("not json".utf8).write(to: url)
        #expect(throws: RecoveryRecordError.self) { try RecoveryRecord.load(from: directory) }
        try Data(#"{"format":"ilibrary-rebuild-record-2"}"#.utf8).write(to: url)
        #expect(throws: RecoveryRecordError.wrongFormat("ilibrary-rebuild-record-2")) {
            try RecoveryRecord.load(from: directory)
        }
        try Data(#"{"format":"ilibrary-rebuild-record-1"}"#.utf8).write(to: url)
        do {
            _ = try RecoveryRecord.load(from: directory)
            Issue.record("expected a refusal")
        } catch let error as RecoveryRecordError {
            if case .malformed = error {} else { Issue.record("\(error)") }
        }
    }

    @Test func checksumCorruptionIsDetected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.sample().write(to: directory)
        let url = directory.appendingPathComponent(RecoveryRecord.fileName)
        let text = try String(contentsOf: url, encoding: .utf8)
        try text.replacingOccurrences(of: "0.2.0", with: "0.2.1").write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: RecoveryRecordError.checksumMismatch) { try RecoveryRecord.load(from: directory) }
    }

    @Test func stageOtherThanPreparedIsRefused() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.sample().write(to: directory)
        let url = directory.appendingPathComponent(RecoveryRecord.fileName)
        let text = try String(contentsOf: url, encoding: .utf8)
        try text.replacingOccurrences(of: "\"prepared\"", with: "\"evacuated\"").write(
            to: url, atomically: true, encoding: .utf8)
        #expect(throws: RecoveryRecordError.malformed("unsupported stage 'evacuated'")) {
            try RecoveryRecord.load(from: directory)
        }
    }

    @Test func aSealedRecordKeepsItsEncodingAndChecksum() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let written = try Self.sample().write(to: directory)
        let url = directory.appendingPathComponent(RecoveryRecord.fileName)
        let bytes = try Data(contentsOf: url)
        let loaded = try RecoveryRecord.load(from: directory)
        #expect(loaded == written)
        #expect(loaded.checksum == written.checksum)
        // Re-encoding the loaded record in the writer's format reproduces the file byte for byte.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        #expect(try encoder.encode(loaded) == bytes)
        #expect(try loaded.sealed().checksum == loaded.checksum)
    }

    @Test func aLiteralRecordOfTheCurrentEncodingLoadsAndEqualsTheSealedSample() throws {
        // The exact bytes that `write` produces for `sample()`, pinning the encoding and the checksum.
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(Self.literalRecord.utf8).write(to: directory.appendingPathComponent(RecoveryRecord.fileName))
        let loaded = try RecoveryRecord.load(from: directory)
        #expect(loaded == (try Self.sample().sealed()))
        #expect(loaded.checksum == "7cae8f6e39d7f07d5cf2b1616773ca0c7dd474e763b5efee653d94019c0d5f1c")
    }

    @Test func malformedAndDuplicatePersistentIDsAreRefused() throws {
        let bad = invalid(
            try loadEdited {
                $0.registrations[0] = RegistrationRecord(
                    persistentID: "12", name: "", album: "", artist: "", albumArtist: "",
                    location: $0.registrations[0].location, cloudStatus: "", dateAdded: nil)
            })
        #expect(bad.contains(.malformedPersistentID("12")))
        let duplicate = invalid(
            try loadEdited {
                $0.registrations[1] = RegistrationRecord(
                    persistentID: Self.one.lowercased(), name: "", album: "", artist: "", albumArtist: "",
                    location: $0.registrations[1].location, cloudStatus: "", dateAdded: nil)
            })
        #expect(duplicate.contains(.duplicatePersistentID(Self.one.lowercased())))
    }

    @Test func invalidInventoryPathsAreRefused() throws {
        for (path, escaping) in [
            ("../x.m4a", true), ("/abs.m4a", true), ("a//b.m4a", false), ("./a.m4a", false), ("", false),
            ("Cafe\u{0301}/x.m4a", false),
        ] {
            let found = try problems { record in
                record.inventory = [
                    SourcedFileRecord(
                        sourceRoot: "/lib/media/Music",
                        record: FileRecord(
                            path: path, size: 1, sha256: SHA256.digest(of: [1]),
                            modification: FileTimestamp(seconds: 0), creation: nil))
                ]
            }
            let list = found
            #expect(list.contains(escaping ? .escapingInventoryPath(path) : .invalidInventoryPath(path)), "\(path)")
        }
    }

    @Test func collidingUnsortedAndForeignInventoryIsRefused() throws {
        let colliding = try problems { $0.inventory = [Self.entry("A/x.m4a"), Self.entry("a/X.m4a")] }
        #expect(colliding.contains { if case .collidingInventoryPaths = $0 { return true } else { return false } })
        let unsorted = try problems { $0.inventory = [Self.entry("A/2.m4a"), Self.entry("A/1.m4a")] }
        #expect(unsorted.contains(.inventoryUnsorted))
        let duplicate = try problems { $0.inventory = [Self.entry("A/1.m4a"), Self.entry("A/1.m4a")] }
        #expect(duplicate.contains { if case .collidingInventoryPaths = $0 { return true } else { return false } })
        let foreign = try problems {
            $0.inventory[0] = SourcedFileRecord(sourceRoot: "/other", record: $0.inventory[0].record)
        }
        #expect(foreign.contains(.unknownSourceRoot("/other")))
    }

    @Test func mappingMustBeOneToOne() throws {
        let missing = try problems { $0.mapping.removeLast() }
        #expect(missing.contains { if case .mappingNotOneToOne = $0 { return true } else { return false } })
        let doubled = try problems { $0.mapping[1] = $0.mapping[0] }
        #expect(doubled.filter { if case .mappingNotOneToOne = $0 { return true } else { return false } }.count >= 2)
        let foreign = try problems {
            $0.mapping[1] = RegistrationMapping(location: "/lib/media/Music/Z/9.m4a", persistentID: Self.two)
        }
        #expect(foreign.contains { if case .mappingNotOneToOne = $0 { return true } else { return false } })
        let unknownID = try problems {
            $0.mapping[1] = RegistrationMapping(location: $0.mapping[1].location, persistentID: "00000000000000FF")
        }
        #expect(unknownID.contains { if case .mappingNotOneToOne = $0 { return true } else { return false } })
        let extra = try problems {
            $0.mapping.append(RegistrationMapping(location: $0.mapping[0].location, persistentID: "00000000000000FF"))
        }
        #expect(!extra.isEmpty)
    }

    @Test func evacuationPlanMustMatchTheInventoryAndStayInsideStaging() throws {
        let outside = try problems {
            $0.evacuation[0] = EvacuationEntry(
                sourcePath: $0.evacuation[0].sourcePath, stagingPath: "/st/other/A/1.m4a")
        }
        #expect(outside.contains(.evacuationOutsideStaging("/st/other/A/1.m4a")))
        let prefix = try problems {
            $0.evacuation[0] = EvacuationEntry(
                sourcePath: $0.evacuation[0].sourcePath, stagingPath: "/st/stage2/A/1.m4a")
        }
        #expect(prefix.contains(.evacuationOutsideStaging("/st/stage2/A/1.m4a")))
        let escaping = try problems {
            $0.evacuation[0] = EvacuationEntry(
                sourcePath: $0.evacuation[0].sourcePath, stagingPath: "/st/stage/../x/1.m4a")
        }
        #expect(escaping.contains(.evacuationOutsideStaging("/st/stage/../x/1.m4a")))
        let duplicate = try problems {
            $0.evacuation[1] = EvacuationEntry(
                sourcePath: $0.evacuation[1].sourcePath, stagingPath: $0.evacuation[0].stagingPath)
        }
        #expect(duplicate.contains(.evacuationNotUnique("/st/stage/A/1.m4a")))
        let missing = try problems { $0.evacuation.removeLast() }
        #expect(missing.contains { if case .evacuationSourcesDiffer = $0 { return true } else { return false } })
        let extra = try problems {
            $0.evacuation.append(EvacuationEntry(sourcePath: "/lib/media/Music/Q.m4a", stagingPath: "/st/stage/Q.m4a"))
        }
        #expect(extra.contains { if case .evacuationSourcesDiffer = $0 { return true } else { return false } })
        let moved = try problems {
            $0.evacuation[0] = EvacuationEntry(
                sourcePath: $0.evacuation[0].sourcePath, stagingPath: "/st/stage/renamed.m4a")
        }
        #expect(moved.contains { if case .evacuationSourcesDiffer = $0 { return true } else { return false } })
    }

    @Test func displayListMustBeTheReverseOfTheAdditionList() throws {
        #expect(try problems { $0.expectedDisplayList = $0.additionList }.contains(.displayListNotReverse))
        #expect(try problems { $0.expectedDisplayList.removeLast() }.contains(.displayListNotReverse))
    }

    @Test func disconnectedBackupMustBeVerifiedAndConfirmed() throws {
        #expect(try problems { $0.backup.verification = nil }.contains(.backupDisconnectedWithoutVerification))
        #expect(
            try problems { $0.backup.verification = VerificationSummary(checkedCount: 2, success: false) }.contains(
                .backupDisconnectedWithoutVerification))
        #expect(try problems { $0.backup.verifiedAt = nil }.contains(.backupDisconnectedWithoutVerification))
        #expect(try problems { $0.backup.maintainerConfirmed = false }.contains(.backupDisconnectedWithoutVerification))
        #expect(try problems { $0.backup.disconnectedAt = nil }.isEmpty)
    }

    @Test func invalidLocationsAndInconsistentSectionsAreRefused() throws {
        let overlap = invalid(try loadEdited { $0.locations.stagingDirectory = "/lib/media/stage" })
        #expect(overlap.contains { if case .locationsInvalid = $0 { return true } else { return false } })
        #expect(
            try problems { $0.backup.root = "/elsewhere" }.contains(
                .inconsistent("the backup root differs from the locations")))
        #expect(
            try problems { $0.createdAt = "yesterday" }.contains(.inconsistent("createdAt is not a UTC ISO 8601 time")))
        #expect(
            try problems { $0.backup.verification = VerificationSummary(checkedCount: 1, success: true) }.contains(
                .inconsistent("the backup verification did not check every inventory file")))
    }

    @Test func editedValidRecordWithCorrectChecksumLoads() throws {
        let result = try loadEdited { $0.ilibraryVersion = "0.2.1" }
        #expect((try? result.get().ilibraryVersion) == "0.2.1")
    }

    static let literalRecord = #"""
        {
          "additionList" : [
            "a1",
            "a2",
            "a3"
          ],
          "backup" : {
            "disconnectedAt" : "2026-10-20T12:02:00Z",
            "filesystemType" : "apfs",
            "independenceReasons" : [

            ],
            "maintainerConfirmed" : true,
            "root" : "/bk/backup",
            "timestampPolicy" : "apfs",
            "verification" : {
              "checkedCount" : 2,
              "success" : true
            },
            "verifiedAt" : "2026-10-20T12:01:00Z",
            "volumeUUID" : "UUID-1"
          },
          "catalogPath" : "/ws/catalog.json",
          "catalogSHA256" : "2b4c342f5433ebe591a1da77e013d1b72475562d48578dca8b84bac6651c3cb9",
          "checksum" : "7cae8f6e39d7f07d5cf2b1616773ca0c7dd474e763b5efee653d94019c0d5f1c",
          "createdAt" : "2026-10-20T12:00:00Z",
          "evacuation" : [
            {
              "sourcePath" : "/lib/media/Music/A/1.m4a",
              "stagingPath" : "/st/stage/A/1.m4a"
            },
            {
              "sourcePath" : "/lib/media/Music/A/2.m4a",
              "stagingPath" : "/st/stage/A/2.m4a"
            }
          ],
          "expectedDisplayList" : [
            "a3",
            "a2",
            "a1"
          ],
          "format" : "ilibrary-rebuild-record-1",
          "ilibraryVersion" : "0.2.0",
          "inventory" : [
            {
              "record" : {
                "creation" : {
                  "nanoseconds" : 7,
                  "seconds" : 90
                },
                "modification" : {
                  "nanoseconds" : 5,
                  "seconds" : 100
                },
                "path" : "A/1.m4a",
                "sha256" : "f5b607b70b2a518d4f213e61c0b9234358f360d48594fa1f41b25a3b7cc3acc0",
                "size" : 3
              },
              "sourceRoot" : "/lib/media/Music"
            },
            {
              "record" : {
                "creation" : {
                  "nanoseconds" : 7,
                  "seconds" : 90
                },
                "modification" : {
                  "nanoseconds" : 5,
                  "seconds" : 100
                },
                "path" : "A/2.m4a",
                "sha256" : "94355555853645984e392c767daf1ff197c2c82803177ecd48eef87b70272c4b",
                "size" : 3
              },
              "sourceRoot" : "/lib/media/Music"
            }
          ],
          "locations" : {
            "backupRoot" : "/bk/backup",
            "mediaFolder" : "/lib/media",
            "restorationDirectory" : "/rs/restore",
            "sources" : [
              "/lib/media/Music"
            ],
            "stagingDirectory" : "/st/stage",
            "workspaceDirectory" : "/ws/work"
          },
          "mapping" : [
            {
              "location" : "/lib/media/Music/A/1.m4a",
              "persistentID" : "0000000000000001"
            },
            {
              "location" : "/lib/media/Music/A/2.m4a",
              "persistentID" : "00000000000000AB"
            }
          ],
          "registrations" : [
            {
              "album" : "A",
              "albumArtist" : "x",
              "artist" : "x",
              "cloudStatus" : "",
              "dateAdded" : 5,
              "location" : "/lib/media/Music/A/1.m4a",
              "name" : "1",
              "persistentID" : "0000000000000001"
            },
            {
              "album" : "A",
              "albumArtist" : "x",
              "artist" : "x",
              "cloudStatus" : "unknown",
              "location" : "/lib/media/Music/A/2.m4a",
              "name" : "2",
              "persistentID" : "00000000000000AB"
            }
          ],
          "restoration" : {
            "directory" : "/rs/restore",
            "verification" : {
              "checkedCount" : 2,
              "success" : true
            },
            "verifiedAt" : "2026-10-20T12:03:00Z"
          },
          "stage" : "prepared"
        }
        """#
}
