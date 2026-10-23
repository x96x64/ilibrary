import Foundation
import Testing

@testable import ilibrary

@Suite struct RebuildInterfaceTests {
    @Test func helpIsAvailableForTheGroupAndItsSubcommands() {
        let group = Run(["rebuild", "--help"])
        #expect(group.status == 0)
        #expect(group.text.contains("Usage: ilibrary rebuild SUBCOMMAND"))
        #expect(!group.text.contains("not implemented"))
        #expect(Run(["help", "rebuild"]).text == group.text)
        #expect(Run(["rebuild", "-h"]).text == group.text)
        let prepare = Run(["rebuild", "prepare", "--help"])
        #expect(prepare.status == 0)
        #expect(prepare.text.contains("Usage: ilibrary rebuild prepare CATALOG.json SOURCE"))
        #expect(prepare.text.contains("--confirm-separate-device"))
        #expect(prepare.text.contains("multiple sources are not supported yet"))
        #expect(Run(["help", "rebuild", "prepare"]).text == prepare.text)
        for subcommand in ["stage", "clear", "apply", "add", "status"] {
            let help = Run(["rebuild", subcommand, "--help"])
            #expect(help.status == 0)
            #expect(help.text.contains("Usage: ilibrary rebuild \(subcommand) --workspace DIR"))
            #expect(Run(["help", "rebuild", subcommand]).text == help.text)
        }
    }

    @Test func theCommandTableAndOverviewListRebuild() {
        #expect(CommandLineInterface.commands.contains { $0.name == "rebuild" })
        #expect(Run([]).text.contains("rebuild"))
        #expect(CommandLineInterface.syntaxes["rebuild"] != nil)
    }

    @Test(arguments: ["stage", "clear", "apply", "add"])
    func stagesRequireAWorkspace(subcommand: String) {
        let run = Run(["rebuild", subcommand])
        #expect(run.status == 2)
        #expect(run.errorText.contains("--workspace DIR is required"))
        #expect(Run(["rebuild", subcommand, "--workspace", "w", "extra"]).status == 2)
    }

    @Test func unknownAndMissingSubcommandsAreUsageErrors() {
        let unknown = Run(["rebuild", "frobnicate"])
        #expect(unknown.status == 2)
        #expect(unknown.errorText.contains("unknown subcommand frobnicate"))
        let missing = Run(["rebuild"])
        #expect(missing.status == 2)
        #expect(missing.errorText.contains("a subcommand is required"))
    }

    @Test func prepareRejectsUsageErrorsBeforeAnything() {
        let required = ["--workspace", "w", "--backup", "b", "--restore-test", "r", "--staging", "s"]
        let missing = Run(["rebuild", "prepare", "catalog.json", "source", "--workspace", "w"])
        #expect(missing.status == 2)
        #expect(missing.errorText.contains("--backup DIR is required"))
        let several = Run(["rebuild", "prepare", "catalog.json", "one", "two"] + required)
        #expect(several.status == 2)
        #expect(several.errorText.contains("multiple sources are not supported yet"))
        #expect(Run(["rebuild", "prepare", "catalog.json"] + required).status == 2)
        let order = Run(["rebuild", "prepare", "catalog.json", "source", "--order", "random"] + required)
        #expect(order.status == 2)
        #expect(order.errorText.contains("--order must be"))
        for timeout in ["-1", "ten", "90000", "1.5"] {
            let run = Run(
                ["rebuild", "prepare", "catalog.json", "source", "--disconnect-timeout=\(timeout)"] + required)
            #expect(run.status == 2, "\(timeout)")
        }
        let status = Run(["rebuild", "status"])
        #expect(status.status == 2)
        #expect(status.errorText.contains("--workspace DIR is required"))
        #expect(Run(["rebuild", "status", "--workspace", "w", "extra"]).status == 2)
    }

    @Test func pathsAreResolvedThroughSymbolicLinksOfExistingAncestors() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ilibrary-resolve-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: base.appendingPathComponent("link"), withDestinationURL: real)
        let root = RebuildCommand.resolve(base.path)
        #expect(RebuildCommand.resolve(base.path + "/link/new/child") == root + "/real/new/child")
        #expect(RebuildCommand.resolve(base.path + "/link/../real/./x") == root + "/real/x")
        #expect(RebuildCommand.resolve(base.path + "/missing/../real") == root + "/real")
        #expect(RebuildCommand.resolve("/") == "/")
        #expect(!FileManager.default.fileExists(atPath: real.appendingPathComponent("new").path))
        let relative = RebuildCommand.resolve("a/b")
        #expect(relative.hasPrefix("/") && relative.hasSuffix("/a/b"))
        #expect(RebuildCommand.nearestExisting(root + "/real/new/child") == root + "/real")
    }
}

#if os(macOS)
    import CatalogCore
    import RebuildCore

    /// A Music library that answers a prepared snapshot. Adding is never expected.
    final class SnapshotMusic: MusicLibrary, @unchecked Sendable {
        var media: URL?
        var snapshot: LibrarySnapshot
        var readFails = false
        var addCalls = 0
        var snapshotReads = 0

        init(media: URL?, snapshot: LibrarySnapshot) {
            self.media = media
            self.snapshot = snapshot
        }

        func mediaFolder() -> URL? { media }
        func tracks(album: String) throws -> [LibraryTrack] { [] }
        func allTracks() throws -> [LibraryTrack] { snapshot.tracks }
        func track(persistentID: String) throws -> LibraryTrack? { nil }
        func add(_ files: [URL]) throws -> [LibraryTrack] {
            addCalls += 1
            throw CocoaError(.fileWriteUnknown)
        }
        func datesAdded(_ persistentIDs: [String]) throws -> [String: Int] { throw CocoaError(.fileReadUnknown) }
        func remove(persistentID: String, name: String, album: String, artist: String) throws {
            throw CocoaError(.fileWriteUnknown)
        }
        func quit() throws { throw CocoaError(.fileWriteUnknown) }
        func librarySnapshot() throws -> LibrarySnapshot {
            snapshotReads += 1
            if readFails { throw CocoaError(.fileReadUnknown) }
            return snapshot
        }
    }

    final class Counter: @unchecked Sendable { var value = 0 }

    /// The settings and counters of the substituted platform operations.
    final class RebuildFakes: @unchecked Sendable {
        var backupPath = ""
        var restorePath = ""
        var backupFacts = StorageFacts(
            physicalDisk: "disk9", filesystemType: "apfs", isLocal: true, isDiskImage: false, interconnect: "USB")
        var otherFacts = StorageFacts(
            physicalDisk: "disk0", filesystemType: "apfs", isLocal: true, isDiskImage: false,
            interconnect: "PCI-Express")
        var backupUUID: String? = "11111111-2222-3333-4444-555555555555"
        var backupPolicy: TimestampPolicy? = .apfs
        var restorePolicy: TimestampPolicy? = .apfs
        var disconnection = DisconnectionCheck.confirmed
        var capacity: Int? = 1 << 40
        var afterCopy: ((URL) throws -> Void)?
        var copyCalls = 0
        var dateCalls = 0
        var waitCalls: [(uuid: String, timeout: TimeInterval)] = []

        func isInside(_ path: String, _ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }
    }

    /// A synthetic library, a catalog, a backup, and empty directories, all in temporary folders.
    struct RebuildFixture {
        let library: SyntheticLibrary
        let base: URL
        let source: String
        let catalog: String
        let backup: String
        let restoration: String
        let staging: String
        let workspace: String
        let media: String
        let music: SnapshotMusic
        let fakes = RebuildFakes()
        var environment: Environment

        static let additionList = [
            "Example Artist - Synthetic Album", "Example Artist - Double Album", "Various Artists - Tribute Collection",
        ]

        init(truncateBackupDates: Bool = false, albums: [SyntheticLibrary.AlbumSpec] = SyntheticLibrary.standardAlbums)
            throws
        {
            library = try SyntheticLibrary(albums: albums)
            base = URL(
                fileURLWithPath: RebuildCommand.resolve(
                    FileManager.default.temporaryDirectory.appendingPathComponent(
                        "ilibrary-rebuild-\(UUID().uuidString)"
                    ).path))
            source = RebuildCommand.resolve(library.root.path)
            catalog = base.path + "/catalog.json"
            backup = base.path + "/backup"
            restoration = base.path + "/restore"
            staging = base.path + "/staging"
            workspace = base.path + "/workspace"
            media = base.path + "/media/Media.localized"
            for directory in [backup, restoration, workspace, media] {
                try FileManager.default.createDirectory(
                    atPath: directory, withIntermediateDirectories: true)
            }
            let export = Run(["export", source, "-o", catalog])
            #expect(export.status == 0, "\(export.errorText)")

            let setDates = try #require(Environment.systemPreciseDates)
            let inventory = try FileInventory(root: URL(fileURLWithPath: source), extensions: ["m4a"])
            var tracks: [LibraryTrack] = []
            for (index, record) in inventory.records.enumerated() {
                let from = source + "/" + record.path
                let to = backup + "/" + record.path
                try FileManager.default.createDirectory(
                    atPath: (to as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try FileManager.default.copyItem(atPath: from, toPath: to)
                let modification = truncateBackupDates ? record.modification.truncatedToSeconds : record.modification
                let creation = try #require(record.creation)
                _ = try setDates(to, modification, truncateBackupDates ? creation.truncatedToSeconds : creation)
                tracks.append(
                    LibraryTrack(
                        persistentID: String(format: "%016X", index + 1),
                        name: (record.path as NSString).lastPathComponent, album: "Album", artist: "Artist",
                        albumArtist: "Artist", location: from, cloudStatus: "unknown"))
            }
            music = SnapshotMusic(
                media: URL(fileURLWithPath: media),
                snapshot: LibrarySnapshot(
                    tracks: tracks, trackCount: tracks.count, fileTrackCount: tracks.count,
                    dateAddedSeconds: Dictionary(
                        uniqueKeysWithValues: tracks.map { ($0.persistentID, 1_700_000_000) })))

            fakes.backupPath = backup
            fakes.restorePath = restoration
            var environment = Environment.testing
            environment.music = music
            let fakes = fakes
            let systemCopy = try #require(Environment.systemRestoreCopy)
            environment.describeStorage = { path in
                if fakes.isInside(path, fakes.backupPath) {
                    return StorageReport(
                        mountPoint: fakes.backupPath, volumeUUID: fakes.backupUUID,
                        filesystemType: fakes.backupFacts.filesystemType ?? "", isReadOnly: false,
                        facts: fakes.backupFacts)
                }
                return StorageReport(
                    mountPoint: "/", volumeUUID: "00000000-0000-0000-0000-000000000000", filesystemType: "apfs",
                    isReadOnly: false, facts: fakes.otherFacts)
            }
            environment.timestampPolicy = { path in
                if fakes.isInside(path, fakes.backupPath) { return fakes.backupPolicy }
                if fakes.isInside(path, fakes.restorePath) { return fakes.restorePolicy }
                return .apfs
            }
            environment.volumeIdentifier = {
                fakes.isInside($0.path, fakes.backupPath) ? "volume-backup" : "volume-main"
            }
            environment.availableCapacity = { _ in fakes.capacity }
            environment.restoreCopy = { source, destination, root in
                fakes.copyCalls += 1
                try systemCopy(source, destination, root)
                try fakes.afterCopy?(destination)
            }
            environment.setPreciseDates = { path, modification, creation in
                fakes.dateCalls += 1
                return try setDates(path, modification, creation)
            }
            environment.waitUntilUnmounted = { uuid, timeout in
                fakes.waitCalls.append((uuid, timeout))
                return fakes.disconnection
            }
            self.environment = environment
        }

        func remove() {
            library.remove()
            try? FileManager.default.removeItem(at: base)
        }

        func arguments(confirm: Bool = true, staging: String? = nil, _ extra: [String] = []) -> [String] {
            [
                "rebuild", "prepare", catalog, source, "--workspace", workspace, "--backup", backup, "--restore-test",
                restoration,
                "--staging", staging ?? self.staging,
            ] + (confirm ? ["--confirm-separate-device"] : []) + extra
        }

        func prepare(confirm: Bool = true, staging: String? = nil, _ extra: [String] = []) -> Run {
            Run(arguments(confirm: confirm, staging: staging, extra), environment: environment)
        }

        /// The observable state that a refused or dry run must leave as it was.
        struct State: Equatable {
            var source: [FileRecord]?
            var sourceNames: [String]
            var backup: [FileRecord]
            var restoration: [String]
            var workspace: [String]
            var stagingExists: Bool
        }

        func state() throws -> State {
            func names(_ path: String) -> [String] {
                ((try? FileManager.default.subpathsOfDirectory(atPath: path)) ?? []).sorted()
            }
            return State(
                source: try? FileInventory(root: URL(fileURLWithPath: source), extensions: ["m4a"]).records,
                sourceNames: names(source),
                backup: try FileInventory(root: URL(fileURLWithPath: backup), extensions: ["m4a"]).records,
                restoration: names(restoration), workspace: names(workspace),
                stagingExists: FileManager.default.fileExists(atPath: staging))
        }

        /// Asserts the refusal at a step with its reasons and the untouched state, and returns the run.
        @discardableResult
        func expectRefusal(
            _ run: Run, step: Int, title: String, reasons: [String], before: State,
            sourceLocation: SourceLocation = #_sourceLocation
        ) throws -> Run {
            #expect(run.status == 1, "\(run.errorText)", sourceLocation: sourceLocation)
            for reason in reasons {
                #expect(
                    run.errorText.contains(reason), "missing reason: \(reason)\n\(run.errorText)",
                    sourceLocation: sourceLocation)
            }
            #expect(
                run.errorText.contains("rebuild prepare stopped at step \(step) (\(title)); nothing was changed"),
                "\(run.errorText)", sourceLocation: sourceLocation)
            #expect(try state() == before, sourceLocation: sourceLocation)
            #expect(try state().workspace.isEmpty, sourceLocation: sourceLocation)
            #expect(music.addCalls == 0, sourceLocation: sourceLocation)
            return run
        }
    }

    @Suite struct RebuildPrepareTests {
        @Test func aFullPreparationWritesALoadableRecordAndKeepsTheRestoredFiles() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let before = try fixture.state()
            let run = fixture.prepare()
            #expect(run.status == 0, "\(run.errorText)")
            #expect(run.text.contains("Resolved locations:"))
            #expect(run.text.contains("  source: \(fixture.source)"))
            #expect(run.text.contains("Plan:"))
            #expect(run.text.contains("Eject the backup volume now: \(fixture.backup)"))
            #expect(run.text.contains("The record is private"))
            #expect(run.text.contains("Recovery record: \(fixture.workspace)/rebuild-record.json"))
            #expect(fixture.fakes.waitCalls.count == 1)
            #expect(fixture.fakes.waitCalls.first?.uuid == "11111111-2222-3333-4444-555555555555")
            #expect(fixture.fakes.waitCalls.first?.timeout == 600)
            #expect(fixture.fakes.copyCalls == 9)

            let record = try RecoveryRecord.load(from: URL(fileURLWithPath: fixture.workspace))
            #expect(record.stage == .prepared)
            #expect(record.inventory.count == 9)
            #expect(record.registrations.count == 9)
            #expect(record.mapping.count == 9)
            #expect(record.registrations.allSatisfy { $0.dateAdded == 1_700_000_000 })
            #expect(record.additionList == RebuildFixture.additionList)
            #expect(record.expectedDisplayList == RebuildFixture.additionList.reversed())
            #expect(record.evacuation.count == 9)
            #expect(record.evacuation.allSatisfy { $0.stagingPath.hasPrefix(fixture.staging + "/") })
            #expect(record.locations.sources == [fixture.source])
            #expect(record.locations.mediaFolder == fixture.media)
            #expect(record.backup.volumeUUID == "11111111-2222-3333-4444-555555555555")
            #expect(record.backup.maintainerConfirmed)
            #expect(record.backup.disconnectedAt != nil)
            #expect(record.backup.verification == VerificationSummary(checkedCount: 9, success: true))
            #expect(record.restoration.verification == VerificationSummary(checkedCount: 9, success: true))
            #expect(record.catalogPath == fixture.catalog)

            let after = try fixture.state()
            #expect(after.source == before.source)
            #expect(after.backup == before.backup)
            #expect(after.workspace == ["rebuild-record.json"])
            #expect(!after.stagingExists)
            let restored = try FileInventory.verify(
                copy: URL(fileURLWithPath: fixture.restoration), against: record.inventory.map(\.record),
                policy: .apfs)
            #expect(restored.isSuccess, "\(restored.mismatches)")
            #expect(restored.checkedCount == 9)
            #expect(fixture.music.addCalls == 0)

            let status = Run(["rebuild", "status", "--workspace", fixture.workspace])
            #expect(status.status == 0, "\(status.errorText)")
            #expect(status.text.contains("Stage: prepared"))
            #expect(status.text.contains("Counts: 9 files"))
            #expect(status.text.contains("9 registrations, 3 albums"))
            #expect(status.text.contains("Backup disconnected: yes, confirmed at"))
            #expect(status.text.contains("Restoration test: verified 9 files"))
            #expect(status.text.contains("Next required action: keep the recovery record and the backup."))
            #expect(status.text.contains("private"))
        }

        @Test func theOrderOptionSelectsTheAdditionAndDisplayLists() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let run = fixture.prepare(["--order", "artist-desc", "--disconnect-timeout", "5"])
            #expect(run.status == 0, "\(run.errorText)")
            #expect(fixture.fakes.waitCalls.first?.timeout == 5)
            let record = try RecoveryRecord.load(from: URL(fileURLWithPath: fixture.workspace))
            #expect(
                record.additionList == [
                    "Various Artists - Tribute Collection", "Example Artist - Synthetic Album",
                    "Example Artist - Double Album",
                ])
            #expect(record.expectedDisplayList == record.additionList.reversed())
        }

        @Test func aBackupOnAnHFSPlusVolumeIsVerifiedAndRestoredToWholeSeconds() throws {
            let fixture = try RebuildFixture(truncateBackupDates: true)
            defer { fixture.remove() }
            fixture.fakes.backupPolicy = .hfsPlus
            let run = fixture.prepare()
            #expect(run.status == 0, "\(run.errorText)")
            let record = try RecoveryRecord.load(from: URL(fileURLWithPath: fixture.workspace))
            #expect(record.backup.timestampPolicy == .hfsPlus)
            let restored = try FileInventory.verify(
                copy: URL(fileURLWithPath: fixture.restoration), against: record.inventory.map(\.record),
                policy: .hfsPlus)
            #expect(restored.isSuccess, "\(restored.mismatches)")
        }

        @Test func aDryRunStopsBeforeRestorationAndWritesNothing() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let before = try fixture.state()
            let run = fixture.prepare(["--dry-run"])
            #expect(run.status == 0, "\(run.errorText)")
            #expect(run.text.contains("Plan (dry run):"))
            #expect(run.text.contains("Inventory: 9 files,"))
            #expect(run.text.contains("9 registrations"))
            #expect(run.text.contains("Capacity by volume:"))
            #expect(run.text.contains("restoration-test directory, workspace directory"))
            #expect(run.text.contains("Addition order (release), first added to last added:"))
            #expect(run.text.contains("  1. Example Artist - Synthetic Album"))
            #expect(run.text.contains("  3. Various Artists - Tribute Collection"))
            #expect(run.text.contains("Expected display order, first visible to last:"))
            #expect(run.text.contains("  1. Various Artists - Tribute Collection"))
            #expect(run.text.contains("Evacuation plan (recorded only; nothing is evacuated in this version): 9 files"))
            #expect(run.text.contains("Timestamp policy: apfs"))
            #expect(run.text.contains("Backup verification: 9 files verified"))
            #expect(run.text.contains("Dry run: steps 1 to 4 passed. Nothing was changed."))
            #expect(!run.text.contains("Eject"))
            #expect(fixture.fakes.copyCalls == 0)
            #expect(fixture.fakes.dateCalls == 0)
            #expect(fixture.fakes.waitCalls.isEmpty)
            #expect(try fixture.state() == before)
            #expect(fixture.music.addCalls == 0)
        }

        @Test func anExistingRecordIsNeverOverwritten() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            #expect(fixture.prepare().status == 0)
            let record = try Data(contentsOf: URL(fileURLWithPath: fixture.workspace + "/rebuild-record.json"))
            let before = try fixture.state()
            let reads = fixture.music.snapshotReads
            let run = fixture.prepare()
            #expect(run.status == 1)
            #expect(
                run.errorText.contains("a recovery record already exists at \(fixture.workspace)/rebuild-record.json"))
            #expect(run.errorText.contains("rebuild prepare stopped at the preliminary checks; nothing was changed"))
            #expect(try fixture.state() == before)
            #expect(fixture.music.snapshotReads == reads)
            #expect(try Data(contentsOf: URL(fileURLWithPath: fixture.workspace + "/rebuild-record.json")) == record)
        }

        @Test func preliminaryChecksRefuseAMissingWorkspaceAndMissingPlatformOperations() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let before = try fixture.state()
            var missing = Run(
                fixture.arguments().map { $0 == fixture.workspace ? fixture.base.path + "/absent" : $0 },
                environment: fixture.environment)
            #expect(missing.status == 1)
            #expect(missing.errorText.contains("the workspace directory \(fixture.base.path)/absent does not exist"))
            #expect(!FileManager.default.fileExists(atPath: fixture.base.path + "/absent"))
            var unavailable = fixture.environment
            unavailable.waitUntilUnmounted = nil
            missing = Run(fixture.arguments(), environment: unavailable)
            #expect(missing.status == 1)
            #expect(missing.errorText.contains("requires macOS"))
            unavailable = fixture.environment
            unavailable.music = nil
            let noMusic = Run(fixture.arguments(), environment: unavailable)
            #expect(noMusic.status == 1)
            #expect(noMusic.errorText.contains("reading the Music library requires macOS"))
            #expect(noMusic.errorText.contains("stopped at step 2 (Music library registrations); nothing was changed"))
            #expect(try fixture.state() == before)
        }

        // MARK: Step 1

        @Test func aCatalogTrackWithoutAFileIsRefusedAtStepOne() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let file = try #require(try fixture.library.m4aFiles().first)
            try FileManager.default.removeItem(at: file)
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 1, title: "catalog and file inventory", reasons: ["no file for album 1, disc 1, track 1"],
                before: before)
            #expect(fixture.music.snapshotReads == 0)
        }

        @Test func aCatalogAlbumWithoutAnyFileIsRefusedAtStepOne() throws {
            let albums = Array(SyntheticLibrary.standardAlbums.prefix(2))
            let fixture = try RebuildFixture(albums: albums)
            defer { fixture.remove() }
            // The album is absent from the source, the library, and the backup alike, so no later step refuses it.
            let absentFolder = fixture.source + "/" + albums[1].folder
            try FileManager.default.removeItem(atPath: absentFolder)
            try FileManager.default.removeItem(atPath: fixture.backup + "/" + albums[1].folder)
            fixture.music.snapshot.tracks.removeAll { ($0.location ?? "").hasPrefix(absentFolder + "/") }
            fixture.music.snapshot.trackCount = fixture.music.snapshot.tracks.count
            fixture.music.snapshot.fileTrackCount = fixture.music.snapshot.tracks.count
            #expect(fixture.music.snapshot.tracks.count == 3)
            let before = try fixture.state()
            let titles = [
                "album 2, disc 1, track 1 \"Opening\"", "album 2, disc 1, track 2 \"Middle\"",
                "album 2, disc 2, track 1 \"Return\"", "album 2, disc 2, track 2 \"Closing\"",
            ]
            for extra in [[], ["--dry-run"]] {
                let run = fixture.prepare(extra)
                try fixture.expectRefusal(
                    run, step: 1, title: "catalog and file inventory", reasons: titles.map { "no file for " + $0 },
                    before: before)
                #expect(!run.errorText.contains("no file for album 1"))
                #expect(fixture.fakes.copyCalls == 0)
                #expect(fixture.fakes.waitCalls.isEmpty)
                #expect(
                    !FileManager.default.fileExists(atPath: fixture.workspace + "/" + RecoveryRecord.fileName))
            }
        }

        @Test func aFileThatTheCatalogDoesNotMatchIsRefusedAtStepOne() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let file = try #require(try fixture.library.m4aFiles().first)
            try FileManager.default.copyItem(
                at: file, to: file.deletingLastPathComponent().appendingPathComponent("Copy.m4a"))
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 1, title: "catalog and file inventory", reasons: ["files match album 1, disc 1, track 1"],
                before: before)
        }

        @Test func aSymbolicLinkInTheSourceIsRefusedAtStepOne() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let file = try #require(try fixture.library.m4aFiles().first)
            try FileManager.default.createSymbolicLink(
                at: file.deletingLastPathComponent().appendingPathComponent("Link.m4a"), withDestinationURL: file)
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 1, title: "catalog and file inventory", reasons: ["symbolic link"], before: before)
            #expect(run.errorText.contains("Link.m4a"))
        }

        @Test func anInvalidOrMissingCatalogIsRefusedAtStepOne() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            try Data("{}".utf8).write(to: URL(fileURLWithPath: fixture.base.path + "/bad.json"))
            let before = try fixture.state()
            let bad = Run(
                fixture.arguments().map { $0 == fixture.catalog ? fixture.base.path + "/bad.json" : $0 },
                environment: fixture.environment)
            try fixture.expectRefusal(
                bad, step: 1, title: "catalog and file inventory", reasons: ["catalog"], before: before)
            let absent = Run(
                fixture.arguments().map { $0 == fixture.catalog ? fixture.base.path + "/absent.json" : $0 },
                environment: fixture.environment)
            try fixture.expectRefusal(
                absent, step: 1, title: "catalog and file inventory", reasons: ["absent.json is not a file"],
                before: before)
        }

        // MARK: Step 2

        @Test func aTrackThatIsNotAFileTrackIsRefusedAtStepTwo() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.music.snapshot.trackCount += 1
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 2, title: "Music library registrations",
                reasons: ["1 track(s) that are not file tracks"], before: before)
        }

        @Test func anUnadmittedCloudStatusIsRefusedAtStepTwo() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.music.snapshot.tracks[0].cloudStatus = "matched"
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 2, title: "Music library registrations",
                reasons: ["track 0000000000000001 has the unadmitted cloud status 'matched'"], before: before)
        }

        @Test func anUnregisteredFileIsRefusedAtStepTwo() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let removed = fixture.music.snapshot.tracks.removeLast()
            fixture.music.snapshot.trackCount -= 1
            fixture.music.snapshot.fileTrackCount -= 1
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 2, title: "Music library registrations",
                reasons: ["the file \(removed.location ?? "") has no registration"], before: before)
        }

        @Test func aRegistrationOutsideTheSourceIsRefusedAtStepTwo() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            var extra = fixture.music.snapshot.tracks[0]
            extra.persistentID = "00000000000000FF"
            extra.location = fixture.media + "/Other.m4a"
            fixture.music.snapshot.tracks.append(extra)
            fixture.music.snapshot.trackCount += 1
            fixture.music.snapshot.fileTrackCount += 1
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 2, title: "Music library registrations",
                reasons: ["track 00000000000000FF is outside every selected source root"], before: before)
        }

        @Test func anUnreadableLibraryAndAnUnknownMediaFolderAreRefusedAtStepTwo() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.music.readFails = true
            fixture.music.media = nil
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 2, title: "Music library registrations",
                reasons: ["the Music library could not be read", "media folder is unknown"], before: before)
        }

        // MARK: Step 3

        @Test func overlappingLocationsAreRefusedAtStepThree() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let before = try fixture.state()
            let run = fixture.prepare(staging: fixture.source + "/staging")
            try fixture.expectRefusal(
                run, step: 3, title: "plan validation", reasons: ["staging directory", "overlap"], before: before)
            #expect(!FileManager.default.fileExists(atPath: fixture.source + "/staging"))
        }

        @Test func aStagingDirectoryEqualToTheBackupIsRefusedAtStepThree() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let before = try fixture.state()
            let run = fixture.prepare(staging: fixture.backup)
            try fixture.expectRefusal(
                run, step: 3, title: "plan validation", reasons: ["are equal after normalization"], before: before)
        }

        @Test func insufficientCapacityIsRefusedAtStepThree() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.fakes.capacity = 10
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 3, title: "plan validation", reasons: ["volume volume-main needs", "bytes available"],
                before: before)
        }

        @Test func unknownCapacityIsRefusedAtStepThree() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.fakes.capacity = nil
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 3, title: "plan validation",
                reasons: ["the available capacity of volume volume-main is unknown"], before: before)
        }

        @Test func aNonEmptyRestorationDirectoryIsRefusedAndNeverEmptied() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            try Data("keep".utf8).write(to: URL(fileURLWithPath: fixture.restoration + "/.hidden"))
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 3, title: "plan validation",
                reasons: ["the restoration-test directory \(fixture.restoration) is not empty (1 entries)"],
                before: before)
            #expect(before.restoration == [".hidden"])
            #expect(fixture.fakes.copyCalls == 0)
        }

        @Test func aRestorationVolumeThatIsNeitherAPFSNorHFSPlusIsRefused() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.fakes.restorePolicy = nil
            let before = try fixture.state()
            let run = fixture.prepare(["--dry-run"])
            try fixture.expectRefusal(
                run, step: 3, title: "plan validation",
                reasons: ["the restoration volume is neither APFS nor HFS+"], before: before)
        }

        // MARK: Step 4

        @Test func aBackupOnTheSamePhysicalDiskIsRefusedAtStepFour() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.fakes.backupFacts.physicalDisk = "disk0"
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 4, title: "backup verification",
                reasons: [
                    "the backup shares the physical disk disk0 with the source root",
                    "the backup shares the physical disk disk0 with the workspace directory",
                ], before: before)
            #expect(fixture.fakes.copyCalls == 0)
        }

        @Test func aDiskImageBackupIsRefusedAtStepFour() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.fakes.backupFacts.isDiskImage = true
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 4, title: "backup verification", reasons: ["the backup volume is a disk image"],
                before: before)
        }

        @Test func aMissingConfirmationIsRefusedAtStepFour() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let before = try fixture.state()
            let run = fixture.prepare(confirm: false)
            try fixture.expectRefusal(
                run, step: 4, title: "backup verification",
                reasons: ["the maintainer has not confirmed that the backup medium is separate"], before: before)
        }

        @Test func anUnknownBackupVolumeUUIDIsRefusedAtStepFour() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.fakes.backupUUID = nil
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 4, title: "backup verification",
                reasons: ["the volume UUID of the backup is unknown"], before: before)
        }

        @Test func anUnsupportedBackupFilesystemIsRefusedAtStepFour() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.fakes.backupFacts.filesystemType = "exfat"
            fixture.fakes.backupPolicy = nil
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 4, title: "backup verification",
                reasons: ["the backup filesystem exfat is neither apfs nor hfs"], before: before)
            #expect(!run.errorText.contains("timestamp policy of the backup volume is undefined"))
        }

        @Test func anUndefinedBackupPolicyIsRefusedAtStepFour() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.fakes.backupPolicy = nil
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 4, title: "backup verification",
                reasons: ["the timestamp policy of the backup volume is undefined"], before: before)
        }

        @Test func aBackupWithDifferentBytesIsRefusedAtStepFour() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let record = try #require(
                try FileInventory(root: URL(fileURLWithPath: fixture.source), extensions: ["m4a"]).records.first)
            let path = fixture.backup + "/" + record.path
            var bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            bytes[bytes.count - 1] ^= 0xFF
            try bytes.write(to: URL(fileURLWithPath: path))
            let setDates = try #require(Environment.systemPreciseDates)
            _ = try setDates(path, record.modification, try #require(record.creation))
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 4, title: "backup verification",
                reasons: ["backup \(record.path): digestDiffers"], before: before)
        }

        @Test func aBackupWithDifferentDatesIsRefusedAtStepFour() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let record = try #require(
                try FileInventory(root: URL(fileURLWithPath: fixture.source), extensions: ["m4a"]).records.first)
            let setDates = try #require(Environment.systemPreciseDates)
            _ = try setDates(
                fixture.backup + "/" + record.path,
                FileTimestamp(seconds: record.modification.seconds + 1, nanoseconds: record.modification.nanoseconds),
                try #require(record.creation))
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 4, title: "backup verification",
                reasons: ["backup \(record.path): modificationTimeDiffers"], before: before)
        }

        @Test func aMissingBackupFileAndAnExtraBackupFileAreRefusedAtStepFour() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let records = try FileInventory(root: URL(fileURLWithPath: fixture.source), extensions: ["m4a"]).records
            try FileManager.default.removeItem(atPath: fixture.backup + "/" + records[0].path)
            try Data("x".utf8).write(to: URL(fileURLWithPath: fixture.backup + "/Extra.m4a"))
            let before = try fixture.state()
            let run = fixture.prepare()
            try fixture.expectRefusal(
                run, step: 4, title: "backup verification",
                reasons: ["backup \(records[0].path): missing", "backup Extra.m4a: extraFile"], before: before)
        }

        // MARK: Steps 5 to 7

        @Test func aRestorationThatDoesNotVerifyIsRefusedAndTheRestoredFilesAreKept() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let first = try #require(
                try FileInventory(root: URL(fileURLWithPath: fixture.source), extensions: ["m4a"]).records.first)
            fixture.fakes.afterCopy = { destination in
                guard destination.path.hasSuffix("/" + first.path) else { return }
                var bytes = try Data(contentsOf: destination)
                bytes[bytes.count - 1] ^= 0xFF
                try bytes.write(to: destination)
            }
            let before = try fixture.state()
            let run = fixture.prepare()
            #expect(run.status == 1)
            #expect(run.errorText.contains("restored \(first.path): digestDiffers"))
            #expect(
                run.errorText.contains(
                    "rebuild prepare stopped at step 5 (restoration test); only the 9 file(s) restored so far in \(fixture.restoration) were changed, and they are kept"
                ))
            let after = try fixture.state()
            #expect(after.source == before.source)
            #expect(after.backup == before.backup)
            #expect(after.workspace.isEmpty)
            #expect(after.restoration.filter { $0.hasSuffix(".m4a") }.count == 9)
            #expect(fixture.fakes.waitCalls.isEmpty)
            #expect(!after.stagingExists)
        }

        @Test func aFailedCopyStopsAtStepFiveAndKeepsWhatWasRestored() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let counter = Counter()
            let systemCopy = try #require(Environment.systemRestoreCopy)
            var environment = fixture.environment
            environment.restoreCopy = { source, destination, root in
                counter.value += 1
                if counter.value == 4 { throw CocoaError(.fileWriteOutOfSpace) }
                try systemCopy(source, destination, root)
            }
            let before = try fixture.state()
            let run = Run(fixture.arguments(), environment: environment)
            #expect(run.status == 1)
            #expect(run.errorText.contains("stopped at step 5 (restoration test); only the 3 file(s) restored so far"))
            let after = try fixture.state()
            #expect(after.source == before.source)
            #expect(after.backup == before.backup)
            #expect(after.workspace.isEmpty)
            #expect(after.restoration.filter { $0.hasSuffix(".m4a") }.count == 3)
        }

        @Test func aBackupThatStaysMountedIsRefusedAtStepSixWithoutARecord() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.fakes.disconnection = .stillMounted
            let before = try fixture.state()
            let run = fixture.prepare(["--disconnect-timeout", "3"])
            #expect(run.status == 1)
            #expect(run.text.contains("Eject the backup volume now: \(fixture.backup)"))
            #expect(run.errorText.contains("the backup volume \(fixture.backup) is still mounted after 3 seconds"))
            #expect(
                run.errorText.contains(
                    "stopped at step 6 (disconnecting the backup); only the 9 file(s) restored so far"))
            #expect(fixture.fakes.waitCalls.count == 1)
            let after = try fixture.state()
            #expect(after.workspace.isEmpty)
            #expect(after.source == before.source)
            #expect(after.backup == before.backup)
            #expect(after.restoration.filter { $0.hasSuffix(".m4a") }.count == 9)
        }

        @Test func aDisconnectionThatCannotBeConfirmedIsRefusedAtStepSixWithoutARecord() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            fixture.fakes.disconnection = .unknown("the mount table could not be read: synthetic failure")
            let before = try fixture.state()
            let run = fixture.prepare()
            #expect(run.status == 1)
            #expect(run.text.contains("Eject the backup volume now: \(fixture.backup)"))
            #expect(!run.text.contains("Step 6 passed"))
            #expect(
                run.errorText.contains(
                    "the disconnection of the backup volume \(fixture.backup) could not be confirmed"))
            #expect(run.errorText.contains("the mount table could not be read: synthetic failure"))
            #expect(run.errorText.contains("nothing was recorded as disconnected"))
            #expect(
                run.errorText.contains(
                    "stopped at step 6 (disconnecting the backup); only the 9 file(s) restored so far"))
            #expect(fixture.fakes.waitCalls.count == 1)
            let after = try fixture.state()
            #expect(after.workspace.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: fixture.workspace + "/" + RecoveryRecord.fileName))
            #expect(after.source == before.source)
            #expect(after.backup == before.backup)
            #expect(after.restoration.filter { $0.hasSuffix(".m4a") }.count == 9)
        }
    }

    @Suite struct RebuildStatusTests {
        @Test func aMissingRecordIsReportedAndNothingIsCreated() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            let run = Run(["rebuild", "status", "--workspace", fixture.workspace])
            #expect(run.status == 1)
            #expect(run.errorText.contains("there is no recovery record at \(fixture.workspace)/rebuild-record.json"))
            #expect(run.errorText.contains("no valid recovery record; nothing was changed"))
            #expect(try fixture.state().workspace.isEmpty)
        }

        @Test func aCorruptedRecordIsRefusedWithItsReasons() throws {
            let fixture = try RebuildFixture()
            defer { fixture.remove() }
            #expect(fixture.prepare().status == 0)
            let url = URL(fileURLWithPath: fixture.workspace + "/rebuild-record.json")
            let text = try String(contentsOf: url, encoding: .utf8)
            let edited = text.replacingOccurrences(
                of: "\"ilibraryVersion\" : \"\(version)\"", with: "\"ilibraryVersion\" : \"9.9.9\"")
            #expect(edited != text)
            try edited.write(to: url, atomically: false, encoding: .utf8)
            let run = Run(["rebuild", "status", "--workspace", fixture.workspace])
            #expect(run.status == 1)
            #expect(run.errorText.contains("the record's checksum does not match its content"))
            #expect(run.errorText.contains("invalid and is not trusted; nothing was changed"))
            #expect(!run.text.contains("Stage:"))
            try Data("not json".utf8).write(to: url)
            let garbage = Run(["rebuild", "status", "--workspace", fixture.workspace])
            #expect(garbage.status == 1)
            #expect(garbage.errorText.contains("the record is not well formed"))
            try Data(#"{"format":"ilibrary-rebuild-record-2"}"#.utf8).write(to: url)
            let future = Run(["rebuild", "status", "--workspace", fixture.workspace])
            #expect(future.status == 1)
            #expect(future.errorText.contains("unsupported format 'ilibrary-rebuild-record-2'"))
        }
    }
#endif
