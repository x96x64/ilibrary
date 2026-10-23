import CatalogCore
import Foundation
import RebuildCore
import Testing

@testable import ilibrary

/// A prepared rebuild of a synthetic library: the files in a media folder, their registrations in a substitute
/// library, a catalog exported from them, and a sealed recovery record in the workspace.
struct StageFixture {
    let base: URL
    let media: URL
    let musicFolder: URL
    let staging: URL
    let workspace: URL
    let catalog: URL
    let music: FakeMusic
    let record: RecoveryRecord
    var environment: Environment

    init(albums: [SyntheticLibrary.AlbumSpec] = SyntheticLibrary.standardAlbums) throws {
        let manager = FileManager.default
        let base = URL(
            fileURLWithPath: RebuildCommand.resolve(
                manager.temporaryDirectory.appendingPathComponent("ilibrary-rebuild-\(UUID().uuidString)").path),
            isDirectory: true)
        let media = base.appendingPathComponent("media")
        let musicFolder = media.appendingPathComponent("Music")
        let staging = base.appendingPathComponent("staging")
        let workspace = base.appendingPathComponent("workspace")
        let catalog = workspace.appendingPathComponent("catalog.json")
        (self.base, self.media, self.musicFolder, self.staging, self.workspace, self.catalog) =
            (base, media, musicFolder, staging, workspace, catalog)
        try manager.createDirectory(at: musicFolder, withIntermediateDirectories: true)
        try manager.createDirectory(at: workspace, withIntermediateDirectories: true)
        let library = try SyntheticLibrary(albums: albums)
        defer { library.remove() }
        for album in albums {
            let folder = musicFolder.appendingPathComponent(album.albumArtist).appendingPathComponent(album.album)
            try manager.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.moveItem(at: library.root.appendingPathComponent(album.folder), to: folder)
        }
        var testing = Environment.testing
        let export = Run(["export", musicFolder.path, "-o", catalog.path], environment: testing)
        guard export.status == 0 else { throw CommandError.failure(export.errorText) }
        let catalogData = try Data(contentsOf: catalog)
        let parsed = try #require(Catalog.validate(catalogData).catalog)

        let records = try FileInventory(root: musicFolder, extensions: ["m4a"]).records
        let inventory = records.map { SourcedFileRecord(sourceRoot: musicFolder.path, record: $0) }
        let music = FakeMusic(media: media)
        self.music = music
        let tracks = try music.add(inventory.map { URL(fileURLWithPath: $0.absolutePath) })
        music.running = false
        let registrations = tracks.map {
            RegistrationRecord(
                persistentID: $0.persistentID, name: $0.name, album: $0.album, artist: $0.artist,
                albumArtist: $0.albumArtist, location: $0.location, cloudStatus: "unknown", dateAdded: nil)
        }
        let additionList = parsed.albumOrder(.release).map { RebuildPrepare.albumLabel(parsed.albums[$0]) }
        let unsealed = RecoveryRecord(
            createdAt: "2026-10-23T00:00:00Z", ilibraryVersion: version, catalogPath: catalog.path,
            catalogSHA256: SHA256.digest(of: catalogData),
            locations: RebuildLocations(
                sources: [musicFolder.path], mediaFolder: media.path,
                backupRoot: base.appendingPathComponent("backup").path,
                restorationDirectory: base.appendingPathComponent("restore").path, stagingDirectory: staging.path,
                workspaceDirectory: workspace.path),
            inventory: inventory, registrations: registrations,
            mapping: tracks.map { RegistrationMapping(location: $0.location!, persistentID: $0.persistentID) },
            additionList: additionList, expectedDisplayList: additionList.reversed(),
            evacuation: EvacuationEntry.plan(inventory: inventory, stagingDirectory: staging.path),
            backup: BackupSection(
                root: base.appendingPathComponent("backup").path, volumeUUID: "UUID-1", filesystemType: "apfs",
                timestampPolicy: .apfs, verification: VerificationSummary(checkedCount: records.count, success: true),
                independenceReasons: [], maintainerConfirmed: true, verifiedAt: "2026-10-23T00:01:00Z",
                disconnectedAt: "2026-10-23T00:02:00Z"),
            restoration: RestorationSection(
                directory: base.appendingPathComponent("restore").path,
                verification: VerificationSummary(checkedCount: records.count, success: true),
                verifiedAt: "2026-10-23T00:03:00Z"))
        record = try unsealed.sealed().write(to: workspace)

        testing.music = music
        testing.musicStatus = MusicAppStatus(
            version: { "1.7" }, isRunning: { music.running }, permission: { "permitted" })
        environment = testing
    }

    func remove() { try? FileManager.default.removeItem(at: base) }

    func run(_ subcommand: String, _ arguments: [String] = []) -> Run {
        Run(["rebuild", subcommand, "--workspace", workspace.path] + arguments, environment: environment)
    }

    func files(under url: URL) -> [String] {
        (FileManager.default.enumerator(atPath: url.path)?.compactMap { $0 as? String } ?? []).filter {
            $0.hasSuffix(".m4a")
        }.sorted()
    }

    var progress: RebuildProgress? {
        guard let loaded = try? ProgressJournalFile.loadRecord(from: workspace) else { return nil }
        return try? ProgressJournalFile.read(in: workspace, record: loaded.record, recordBytes: loaded.bytes).progress
    }
}

@Suite struct RebuildStageTests {
    @Test func theFourStagesRebuildTheLibraryInTheRecordedOrder() throws {
        let fixture = try StageFixture()
        defer { fixture.remove() }
        let originals = fixture.files(under: fixture.musicFolder)
        #expect(originals.count == 9)

        let stage = fixture.run("stage")
        #expect(stage.status == 0, "\(stage.errorText)")
        #expect(fixture.files(under: fixture.musicFolder).isEmpty)
        #expect(fixture.files(under: fixture.staging) == originals)

        let clear = fixture.run("clear")
        #expect(clear.status == 0, "\(clear.errorText)")
        #expect(fixture.music.library.isEmpty)
        #expect(fixture.music.removals.count == 9)
        #expect(!fixture.music.running)
        #expect(clear.text.contains("The Music window was not inspected"))

        let apply = fixture.run("apply")
        #expect(apply.status == 0, "\(apply.errorText)")
        let applied = fixture.files(under: fixture.staging)
        #expect(applied.contains("Example Artist/Double Album/1-01 Opening.m4a"))
        #expect(applied.contains("Example Artist/Synthetic Album/02 Second Song_ Part 1_2.m4a"))

        let add = fixture.run("add")
        #expect(add.status == 0, "\(add.errorText)")
        #expect(fixture.files(under: fixture.staging).isEmpty)
        #expect(Set(fixture.files(under: fixture.musicFolder)) == Set(applied))
        #expect(fixture.music.library.count == 9)
        #expect(add.text.contains("the Music window was not inspected"))

        let progress = try #require(fixture.progress)
        #expect(progress.completedStages == RebuildStage.allCases)
        let order = fixture.record.additionList.map { label in
            fixture.music.library.filter { RebuildPrepare.albumLabel(albumOf: $0) == label }.map {
                fixture.music.dates[$0.persistentID]!
            }
        }
        for (earlier, later) in zip(order, order.dropFirst()) { #expect(later.min()! > earlier.max()!) }

        let status = Run(
            ["rebuild", "status", "--workspace", fixture.workspace.path], environment: fixture.environment)
        #expect(status.status == 0)
        #expect(status.text.contains("Completed stages: evacuation, clearing, application, addition, display"))
        #expect(status.text.contains("the rebuild is complete"))
        #expect(fixture.run("add").text.contains("already complete"))
    }

    @Test func dryRunsChangeNothing() throws {
        let fixture = try StageFixture()
        defer { fixture.remove() }
        let before = fixture.files(under: fixture.musicFolder)
        let stage = fixture.run("stage", ["--dry-run"])
        #expect(stage.status == 0, "\(stage.errorText)")
        #expect(stage.text.contains("Files to move from the media folder"))
        #expect(fixture.files(under: fixture.musicFolder) == before)
        #expect(fixture.progress == nil)
        #expect(fixture.run("stage").status == 0)
        let clear = fixture.run("clear", ["--dry-run"])
        #expect(clear.status == 0, "\(clear.errorText)")
        #expect(clear.text.contains("Registrations to remove, one per request: 9"))
        #expect(fixture.music.library.count == 9)
        #expect(fixture.music.removals.isEmpty)
    }

    @Test func stagesRefuseToRunOutOfOrder() throws {
        let fixture = try StageFixture()
        defer { fixture.remove() }
        for subcommand in ["clear", "apply", "add"] {
            let run = fixture.run(subcommand)
            #expect(run.status == 1)
            #expect(run.errorText.contains("requires the"), "\(subcommand): \(run.errorText)")
        }
        #expect(fixture.music.removals.isEmpty)
        #expect(fixture.files(under: fixture.musicFolder).count == 9)
    }

    @Test func stagingAndApplicationRequireMusicToBeClosed() throws {
        let fixture = try StageFixture()
        defer { fixture.remove() }
        fixture.music.running = true
        let stage = fixture.run("stage")
        #expect(stage.status == 1)
        #expect(stage.errorText.contains("quit Music"))
        #expect(fixture.files(under: fixture.staging).isEmpty)
        fixture.music.running = false
        #expect(fixture.run("stage").status == 0)
        #expect(fixture.run("clear").status == 0)
        fixture.music.running = true
        let apply = fixture.run("apply")
        #expect(apply.status == 1)
        #expect(apply.errorText.contains("Music must stay closed"))
    }

    @Test func clearRefusesALibraryThatDiffersFromTheRecord() throws {
        let fixture = try StageFixture()
        defer { fixture.remove() }
        #expect(fixture.run("stage").status == 0)
        fixture.music.library.append(
            LibraryTrack(
                persistentID: "00000000000000FF", name: "Other", album: "Other", artist: "Other", albumArtist: ""))
        let foreign = fixture.run("clear")
        #expect(foreign.status == 1)
        #expect(foreign.errorText.contains("which the record does not plan to remove"))
        #expect(fixture.music.removals.isEmpty)
        fixture.music.library.removeLast()
        fixture.music.otherTracks = 1
        let other = fixture.run("clear")
        #expect(other.status == 1)
        #expect(other.errorText.contains("tracks that are not files"))
        #expect(fixture.music.removals.isEmpty)
    }

    @Test func anInterruptedRemovalResumesWithoutRepeatingRemovals() throws {
        let fixture = try StageFixture()
        defer { fixture.remove() }
        #expect(fixture.run("stage").status == 0)
        let third = fixture.record.mapping[2].persistentID
        fixture.music.failOnRemove = third
        let first = fixture.run("clear")
        #expect(first.status == 1)
        #expect(fixture.music.removals.count == 2)
        #expect(fixture.progress?.openOperation?.target == third)
        let status = Run(
            ["rebuild", "status", "--workspace", fixture.workspace.path], environment: fixture.environment)
        #expect(status.text.contains("Open operation: removeRegistration \(third) (not yet performed)"))
        fixture.music.failOnRemove = nil
        let second = fixture.run("clear")
        #expect(second.status == 0, "\(second.errorText)")
        #expect(fixture.music.removals.count == 9)
        #expect(Set(fixture.music.removals).count == 9)
    }

    @Test func applyRefusesACatalogThatChangedAfterPreparation() throws {
        let fixture = try StageFixture()
        defer { fixture.remove() }
        #expect(fixture.run("stage").status == 0)
        #expect(fixture.run("clear").status == 0)
        var text = try String(contentsOf: fixture.catalog, encoding: .utf8)
        text += "\n"
        try text.write(to: fixture.catalog, atomically: true, encoding: .utf8)
        let apply = fixture.run("apply")
        #expect(apply.status == 1)
        #expect(apply.errorText.contains("differs from the one recorded"))
    }

    @Test func anAlbumSharingAnAdditionSecondStopsTheRebuild() throws {
        let fixture = try StageFixture()
        defer { fixture.remove() }
        for subcommand in ["stage", "clear", "apply"] { #expect(fixture.run(subcommand).status == 0) }
        fixture.music.fixedDate = 1_900_000_000
        let add = fixture.run("add")
        #expect(add.status == 1)
        #expect(add.errorText.contains("its addition dates do not follow those of the album before it"))
        #expect(fixture.progress?.completedStages.contains(.addition) == false)
    }

    @Test func anInterruptedAdditionResumes() throws {
        let fixture = try StageFixture()
        defer { fixture.remove() }
        for subcommand in ["stage", "clear", "apply"] { #expect(fixture.run(subcommand).status == 0) }
        fixture.music.failOnAdd = 2
        let first = fixture.run("add")
        #expect(first.status == 1)
        #expect(fixture.music.library.count < 9)
        fixture.music.failOnAdd = nil
        let second = fixture.run("add")
        #expect(second.status == 0, "\(second.errorText)")
        #expect(fixture.music.library.count == 9)
        #expect(fixture.progress?.completedStages == RebuildStage.allCases)
    }
}

extension RebuildPrepare {
    /// The label of the album of a library track, as the record names albums.
    static func albumLabel(albumOf track: LibraryTrack) -> String {
        albumLabel(Album(album: track.album, albumArtist: track.albumArtist, discs: []))
    }
}
