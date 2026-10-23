import CatalogCore
import Foundation
import RebuildCore

/// A step of `rebuild prepare` that did not pass, with every reason found in that step.
struct PrepareFailure: Error {
    var step: Int
    var title: String
    var reasons: [String]
}

/// What `rebuild prepare` has changed so far, so that the final line of a failure states it exactly.
final class PrepareProgress: @unchecked Sendable {
    var restoreAttempted = false
    var copiedFiles = 0
    var recordWritten = false
}

/// The facts of step 4 that the plan prints and the record keeps.
struct BackupFacts {
    var report: StorageReport
    var policy: TimestampPolicy
    var verifiedCount: Int
}

enum RebuildPrepare {
    static func run(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        let syntax = RebuildCommand.prepareSyntax
        let parsed = try syntax.parse(arguments)
        guard parsed.positionals.count == 2 else {
            throw CommandError.usage(
                "rebuild prepare: exactly one SOURCE directory is supported in this version; multiple sources are not supported yet"
            )
        }
        func required(_ name: String) throws -> String {
            guard let value = parsed.value(name) else {
                throw CommandError.usage("rebuild prepare: \(name) DIR is required")
            }
            return value
        }
        let workspaceOption = try required("--workspace")
        let backupOption = try required("--backup")
        let restoreOption = try required("--restore-test")
        let stagingOption = try required("--staging")
        guard let order = AlbumOrder(rawValue: parsed.value("--order") ?? "release") else {
            throw CommandError.usage("rebuild prepare: --order must be release, artist, artist-desc, or artist-release")
        }
        var timeout = 600
        if let text = parsed.value("--disconnect-timeout") {
            guard let seconds = Int(text), (0...86_400).contains(seconds) else {
                throw CommandError.usage(
                    "rebuild prepare: --disconnect-timeout must be a whole number of seconds from 0 to 86400")
            }
            timeout = seconds
        }
        let dryRun = parsed.flag("--dry-run")

        let catalogURL = URL(fileURLWithPath: parsed.positionals[0])
        let catalogPath =
            RebuildCommand.resolve(catalogURL.deletingLastPathComponent().path) + "/" + catalogURL.lastPathComponent
        let source = RebuildCommand.resolve(parsed.positionals[1])
        let workspace = RebuildCommand.resolve(workspaceOption)
        let backup = RebuildCommand.resolve(backupOption)
        let restoration = RebuildCommand.resolve(restoreOption)
        let staging = RebuildCommand.resolve(stagingOption)

        console.print("Resolved locations:")
        console.print("  catalog: \(catalogPath)")
        console.print("  source: \(source)")
        console.print("  backup: \(backup)")
        console.print("  restoration-test directory: \(restoration)")
        console.print("  staging directory: \(staging)")
        console.print("  workspace: \(workspace)")

        let progress = PrepareProgress()
        do {
            return try prepare(
                Inputs(
                    catalogPath: catalogPath, source: source, workspace: workspace, backup: backup,
                    restoration: restoration, staging: staging, order: order, timeout: timeout,
                    confirmed: parsed.flag("--confirm-separate-device"), dryRun: dryRun),
                console: console, environment: environment, progress: progress)
        } catch let failure as PrepareFailure {
            for reason in failure.reasons { console.error(reason) }
            let title = failure.step == 0 ? "the preliminary checks" : "step \(failure.step) (\(failure.title))"
            var changed = "nothing was changed"
            if progress.recordWritten {
                changed =
                    "the recovery record was written but is not trusted; \(progress.copiedFiles) restored file(s) in \(restoration) are kept"
            } else if progress.copiedFiles > 0 {
                changed =
                    "only the \(progress.copiedFiles) file(s) restored so far in \(restoration) were changed, and they are kept"
            } else if progress.restoreAttempted {
                changed =
                    "no complete file was restored; folders created by the attempt in \(restoration) are kept"
            }
            throw CommandError.failure("rebuild prepare stopped at \(title); \(changed)")
        }
    }

    struct Inputs {
        var catalogPath: String
        var source: String
        var workspace: String
        var backup: String
        var restoration: String
        var staging: String
        var order: AlbumOrder
        var timeout: Int
        var confirmed: Bool
        var dryRun: Bool
    }

    // MARK: Sequence

    static func prepare(
        _ inputs: Inputs, console: Console, environment: Environment, progress: PrepareProgress
    ) throws -> Int32 {
        try preliminaryChecks(inputs, environment: environment)

        let analysis = try analyzeFiles(inputs, console: console)
        let records = analysis.inventory.records
        let totalBytes = records.reduce(UInt64(0)) { $0 &+ $1.size }
        let sourced = records.map { SourcedFileRecord(sourceRoot: inputs.source, record: $0) }
        let additionIndices = analysis.catalog.albumOrder(inputs.order)
        let additionList = additionIndices.map { albumLabel(analysis.catalog.albums[$0]) }
        let displayList = Array(additionList.reversed())
        console.print(
            "Step 1 passed: \(records.count) files (\(totalBytes) bytes) match \(analysis.catalog.albums.count) albums "
                + "of the catalog")

        let library = try readLibrary(sourced, source: inputs.source, environment: environment)
        console.print(
            "Step 2 passed: \(library.registrations.count) registrations map one-to-one to the files; "
                + "media folder \(library.mediaFolder)")

        let locations = RebuildLocations(
            sources: [inputs.source], mediaFolder: library.mediaFolder, backupRoot: inputs.backup,
            restorationDirectory: inputs.restoration, stagingDirectory: inputs.staging,
            workspaceDirectory: inputs.workspace)
        let capacity = try validatePlan(locations, totalBytes: totalBytes, environment: environment)
        console.print("Step 3 passed: the locations are separate and every volume has the capacity that the plan needs")

        let backup = try verifyBackup(
            inputs, locations: locations, records: records, environment: environment)
        console.print(
            "Step 4 passed: the backup holds all \(backup.verifiedCount) files under the policy \(backup.policy.rawValue)"
        )

        let evacuation = EvacuationEntry.plan(inventory: sourced, stagingDirectory: inputs.staging)
        printPlan(
            inputs, locations: locations, records: records, totalBytes: totalBytes, capacity: capacity,
            additionList: additionList, displayList: displayList, evacuation: evacuation, backup: backup,
            registrations: library.registrations.count, console: console)
        if inputs.dryRun {
            console.print("Dry run: steps 1 to 4 passed. Nothing was changed.")
            return 0
        }

        let restoration = try restore(
            inputs, records: records, backup: backup, environment: environment, console: console, progress: progress)
        console.print(
            "Step 5 passed: \(records.count) files were restored and verified under the policy \(restoration.policy.rawValue)"
        )

        let uuid = backup.report.volumeUUID ?? ""
        console.print("")
        console.print(
            "Eject the backup volume now: \(backup.report.mountPoint) (volume UUID \(uuid)). iLibrary does not unmount it. "
                + "Waiting up to \(inputs.timeout) seconds for the volume to disappear.")
        let disconnection = environment.waitUntilUnmounted?(uuid, TimeInterval(inputs.timeout)) ?? .stillMounted
        switch disconnection {
        case .confirmed: break
        case .stillMounted:
            throw PrepareFailure(
                step: 6, title: "disconnecting the backup",
                reasons: [
                    "the backup volume \(backup.report.mountPoint) is still mounted after \(inputs.timeout) seconds; "
                        + "eject it and run the command again"
                ])
        case .unknown(let reason):
            throw PrepareFailure(
                step: 6, title: "disconnecting the backup",
                reasons: [
                    "the disconnection of the backup volume \(backup.report.mountPoint) could not be confirmed: "
                        + "\(reason); nothing was recorded as disconnected"
                ])
        }
        let disconnectedAt = RecoveryRecord.timestampString(Date())
        console.print("Step 6 passed: the backup volume is no longer mounted")

        let record = RecoveryRecord(
            createdAt: RecoveryRecord.timestampString(Date()), ilibraryVersion: version,
            catalogPath: inputs.catalogPath, catalogSHA256: analysis.catalogDigest, locations: locations,
            inventory: sourced, registrations: library.registrations, mapping: library.mapping,
            additionList: additionList, expectedDisplayList: displayList, evacuation: evacuation,
            backup: BackupSection(
                root: inputs.backup, volumeUUID: backup.report.volumeUUID,
                filesystemType: backup.report.filesystemType, timestampPolicy: backup.policy,
                verification: VerificationSummary(checkedCount: backup.verifiedCount, success: true),
                independenceReasons: [], maintainerConfirmed: inputs.confirmed,
                verifiedAt: backup.verifiedAt, disconnectedAt: disconnectedAt),
            restoration: RestorationSection(
                directory: inputs.restoration,
                verification: VerificationSummary(checkedCount: records.count, success: true),
                verifiedAt: restoration.verifiedAt))
        let recordURL = URL(fileURLWithPath: inputs.workspace)
        do {
            let written = try record.write(to: recordURL)
            progress.recordWritten = true
            let loaded = try RecoveryRecord.load(from: recordURL)
            guard loaded == written else { throw RecoveryRecordError.readBackMismatch }
        } catch let error as RecoveryRecordError {
            throw PrepareFailure(
                step: 7, title: "writing the recovery record", reasons: RebuildCommand.describe(error))
        }
        console.print("Step 7 passed: the recovery record was written and read back")
        console.print("Recovery record: \(inputs.workspace)/\(RecoveryRecord.fileName)")
        console.print(
            "The record is private: it contains machine-specific paths and Music persistent IDs. Do not share, publish, or commit it."
        )
        console.print(
            "Prepared: stage prepared, \(records.count) files, \(additionList.count) albums. Restored files remain in "
                + "\(inputs.restoration); keep them, the recovery record, and the backup. Source files, the backup, and Music were not modified."
        )
        return 0
    }

    // MARK: Preliminary Checks

    static func preliminaryChecks(_ inputs: Inputs, environment: Environment) throws {
        var reasons: [String] = []
        if environment.describeStorage == nil || environment.restoreCopy == nil || environment.setPreciseDates == nil
            || environment.waitUntilUnmounted == nil
        {
            reasons.append(
                "rebuild prepare requires macOS: storage, copying, date setting, and mount state are unavailable")
        }
        let workspaceURL = URL(fileURLWithPath: inputs.workspace)
        switch pathKind(workspaceURL) {
        case .directory:
            let recordPath = inputs.workspace + "/" + RecoveryRecord.fileName
            if pathKind(URL(fileURLWithPath: recordPath)) != .missing {
                reasons.append(
                    "a recovery record already exists at \(recordPath); it is never overwritten. Use another workspace or remove it deliberately"
                )
            }
        case .missing: reasons.append("the workspace directory \(inputs.workspace) does not exist; create it first")
        default: reasons.append("the workspace \(inputs.workspace) is not a directory")
        }
        if !reasons.isEmpty { throw PrepareFailure(step: 0, title: "preliminary checks", reasons: reasons) }
    }

    // MARK: Step 1

    struct Analysis {
        var catalog: Catalog
        var catalogDigest: SHA256Digest
        var inventory: FileInventory
    }

    static func analyzeFiles(_ inputs: Inputs, console: Console) throws -> Analysis {
        let title = "catalog and file inventory"
        var reasons: [String] = []
        let catalogURL = URL(fileURLWithPath: inputs.catalogPath)
        guard pathKind(catalogURL) == .file else {
            let kind = pathKind(catalogURL) == .symbolicLink ? "is a symbolic link" : "is not a file"
            throw PrepareFailure(step: 1, title: title, reasons: ["the catalog \(inputs.catalogPath) \(kind)"])
        }
        let data: Data
        do {
            data = try Data(contentsOf: catalogURL)
        } catch {
            throw PrepareFailure(
                step: 1, title: title,
                reasons: ["the catalog \(inputs.catalogPath) cannot be read: \(error.localizedDescription)"])
        }
        let validation = Catalog.validate(data)
        for diagnostic in validation.diagnostics {
            let text = "catalog \(diagnostic.path.isEmpty ? "(root)" : diagnostic.path): \(diagnostic.message)"
            if diagnostic.severity == .error { reasons.append(text) } else { console.warning(text) }
        }
        let catalog = validation.catalog
        if let catalog {
            for (index, album) in catalog.albums.enumerated() {
                guard let artwork = album.artwork, !artwork.isEmpty else { continue }
                do {
                    _ = try loadArtwork(
                        artwork, catalogDirectory: catalogURL.deletingLastPathComponent())
                } catch let error as CommandError {
                    reasons.append("albums[\(index)]: \(error.message)")
                } catch {
                    reasons.append("albums[\(index)]: \(error)")
                }
            }
        } else if reasons.isEmpty {
            reasons.append("the catalog \(inputs.catalogPath) is not valid")
        }

        let sourceURL = URL(fileURLWithPath: inputs.source)
        var inventory: FileInventory?
        if pathKind(sourceURL) != .directory {
            reasons.append("the source \(inputs.source) is not an existing directory")
        } else {
            do {
                inventory = try FileInventory(root: sourceURL, extensions: ["m4a"])
            } catch let error as FileInventoryError {
                reasons.append("file inventory: \(describe(error))")
            } catch {
                reasons.append("file inventory: \(error)")
            }
            if let catalog {
                do {
                    let correspondence = try Correspondence.build([inputs.source], catalog: catalog)
                    for unmatched in correspondence.report.unmatched {
                        reasons.append("unmatched \(unmatched.file.path): \(unmatched.reason)")
                    }
                    for refusal in correspondence.refused {
                        reasons.append("refused \(refusal.path): \(refusal.reason)")
                    }
                    // The matcher reports missing tracks only for albums with at least one match, so every
                    // track of the catalog is enumerated here and a wholly absent album is reported as well.
                    var absent = Set<TrackReference>()
                    for (albumIndex, album) in catalog.albums.enumerated() {
                        for (discIndex, disc) in album.discs.enumerated() {
                            for trackIndex in disc.tracks.indices {
                                absent.insert(
                                    TrackReference(album: albumIndex, disc: discIndex + 1, track: trackIndex + 1))
                            }
                        }
                    }
                    absent.subtract(correspondence.report.matches.map(\.reference))
                    for reference in absent.sorted() {
                        reasons.append("no file for \(reference) \"\(catalog.track(reference).title)\"")
                    }
                    if let inventory {
                        let scanned = Set(
                            // standardizedFileURL drops a leading /private, so the paths are resolved again.
                            correspondence.files.map {
                                RebuildCommand.resolve($0.url.path).precomposedStringWithCanonicalMapping
                            })
                        let inventoried = Set(
                            inventory.records.map {
                                (inputs.source + "/" + $0.path).precomposedStringWithCanonicalMapping
                            })
                        for path in inventoried.subtracting(scanned).sorted() {
                            reasons.append("the inventoried file \(path) was not read for matching")
                        }
                        for path in scanned.subtracting(inventoried).sorted() {
                            reasons.append("the matched file \(path) is not in the inventory")
                        }
                    }
                } catch let error as CommandError {
                    reasons.append(error.message)
                } catch {
                    reasons.append("\(error)")
                }
            }
        }
        if let inventory {
            if inventory.records.isEmpty { reasons.append("the source holds no .m4a file") }
            for record in inventory.records where record.creation == nil {
                reasons.append("the creation date of \(record.path) is unavailable on this platform")
            }
        }
        guard reasons.isEmpty, let catalog, let inventory else {
            throw PrepareFailure(step: 1, title: title, reasons: reasons)
        }
        return Analysis(catalog: catalog, catalogDigest: SHA256.digest(of: data), inventory: inventory)
    }

    static func describe(_ error: FileInventoryError) -> String {
        switch error {
        case .rootMissing(let path): "the root \(path) does not exist"
        case .rootNotDirectory(let path): "the root \(path) is not a directory"
        case .rootIsSymbolicLink(let path): "the root \(path) is a symbolic link"
        case .invalidPath(let path): "invalid relative path '\(path)'"
        case .escapesRoot(let path): "the path '\(path)' escapes its root"
        case .missing(let path): "\(path) is missing"
        case .symbolicLink(let path): "\(path) is or lies behind a symbolic link"
        case .notRegularFile(let path, let kind): "\(path) is not a regular file (\(kind.rawValue))"
        case .collision(let path, let other, let kind):
            "\(path) and \(other) collide after \(kind == .normalization ? "Unicode normalization" : "case folding")"
        case .unstable(let path): "\(path) changed while it was read"
        case .unreadable(let path, let reason): "\(path) cannot be read: \(reason)"
        }
    }

    static func albumLabel(_ album: Album) -> String {
        let artist = album.albumArtist ?? album.artist ?? ""
        return artist.isEmpty ? album.album : "\(artist) - \(album.album)"
    }

    // MARK: Step 2

    struct LibraryReading {
        var registrations: [RegistrationRecord]
        var mapping: [RegistrationMapping]
        var mediaFolder: String
    }

    static func readLibrary(_ sourced: [SourcedFileRecord], source: String, environment: Environment) throws
        -> LibraryReading
    {
        let title = "Music library registrations"
        guard let music = environment.music else {
            throw PrepareFailure(
                step: 2, title: title, reasons: ["reading the Music library requires macOS and the Music app"])
        }
        var reasons: [String] = []
        var mediaFolder = ""
        if let folder = music.mediaFolder() {
            mediaFolder = RebuildCommand.resolve(folder.path)
            if pathKind(URL(fileURLWithPath: mediaFolder)) != .directory {
                reasons.append("Music's media folder \(mediaFolder) is not an existing directory")
            }
        } else {
            reasons.append(
                "Music's media folder is unknown; open Music once and run 'ilibrary doctor'")
        }
        var registrations: [RegistrationRecord] = []
        var mapping: [RegistrationMapping] = []
        do {
            let snapshot = try music.librarySnapshot()
            registrations = snapshot.tracks.map {
                RegistrationRecord(
                    persistentID: $0.persistentID, name: $0.name, album: $0.album, artist: $0.artist,
                    albumArtist: $0.albumArtist, location: $0.location, cloudStatus: $0.cloudStatus,
                    dateAdded: snapshot.dateAddedSeconds[$0.persistentID].map(Int64.init))
            }.sorted { $0.persistentID < $1.persistentID }
            do {
                mapping = try RegistrationClassification.classify(
                    registrations: registrations, totalTrackCount: snapshot.trackCount,
                    fileTrackCount: snapshot.fileTrackCount, inventory: sourced, sourceRoots: [source])
            } catch let error as RegistrationClassificationError {
                reasons += error.refusals.map(\.description)
            }
        } catch {
            reasons.append("the Music library could not be read: \(error)")
        }
        if !reasons.isEmpty { throw PrepareFailure(step: 2, title: title, reasons: reasons) }
        return LibraryReading(registrations: registrations, mapping: mapping, mediaFolder: mediaFolder)
    }

    // MARK: Step 3

    static func validatePlan(_ locations: RebuildLocations, totalBytes: UInt64, environment: Environment) throws
        -> CapacityPlan
    {
        let title = "plan validation"
        var reasons = locations.validate().map(\.description)
        reasons += locations.symbolicLinkRefusals(status: { try FileStatus.read(atPath: $0) }).map(\.description)
        for (label, path) in [
            ("backup root", locations.backupRoot), ("restoration-test directory", locations.restorationDirectory),
        ] where pathKind(URL(fileURLWithPath: path)) != .directory {
            reasons.append("the \(label) \(path) is not an existing directory")
        }
        if pathKind(URL(fileURLWithPath: locations.stagingDirectory)) != .missing,
            pathKind(URL(fileURLWithPath: locations.stagingDirectory)) != .directory
        {
            reasons.append("the staging directory \(locations.stagingDirectory) exists and is not a directory")
        }
        if let problem = nonEmptyReason(locations.restorationDirectory) { reasons.append(problem) }
        if pathKind(URL(fileURLWithPath: locations.restorationDirectory)) == .directory,
            environment.timestampPolicy(locations.restorationDirectory) == nil
        {
            reasons.append(
                "the restoration volume is neither APFS nor HFS+, so its timestamps cannot be verified")
        }
        let plan = CapacityPlan.evaluate(
            inventoryBytes: totalBytes, locations: locations,
            volumeOf: { environment.volumeIdentifier(URL(fileURLWithPath: RebuildCommand.nearestExisting($0))) },
            availableBytes: {
                environment.availableCapacity(URL(fileURLWithPath: RebuildCommand.nearestExisting($0))).map {
                    UInt64(max($0, 0))
                }
            })
        reasons += plan.refusals.map(\.description)
        if !reasons.isEmpty { throw PrepareFailure(step: 3, title: title, reasons: reasons) }
        return plan
    }

    /// A reason when an existing directory holds any entry, including hidden ones.
    static func nonEmptyReason(_ directory: String) -> String? {
        guard pathKind(URL(fileURLWithPath: directory)) == .directory else { return nil }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return "the restoration-test directory \(directory) cannot be listed"
        }
        return entries.isEmpty
            ? nil
            : "the restoration-test directory \(directory) is not empty (\(entries.count) entries); it is never emptied"
    }

    // MARK: Step 4

    struct VerifiedBackup {
        var report: StorageReport
        var policy: TimestampPolicy
        var verifiedCount: Int
        var verifiedAt: String
    }

    static func verifyBackup(
        _ inputs: Inputs, locations: RebuildLocations, records: [FileRecord], environment: Environment
    ) throws -> VerifiedBackup {
        let title = "backup verification"
        guard let describeStorage = environment.describeStorage else {
            throw PrepareFailure(step: 4, title: title, reasons: ["storage cannot be examined on this platform"])
        }
        var reasons: [String] = []
        let backupReport: StorageReport
        do {
            backupReport = try describeStorage(inputs.backup)
        } catch {
            throw PrepareFailure(
                step: 4, title: title, reasons: ["the storage of the backup could not be described: \(error)"])
        }
        let others: [(label: String, path: String)] = [
            ("source root", locations.sources[0]), ("media folder", locations.mediaFolder),
            ("restoration-test directory", locations.restorationDirectory),
            ("staging directory", locations.stagingDirectory), ("workspace directory", locations.workspaceDirectory),
        ]
        var otherFacts: [StorageFacts] = []
        for other in others {
            do {
                otherFacts.append(try describeStorage(RebuildCommand.nearestExisting(other.path)).facts)
            } catch {
                otherFacts.append(
                    StorageFacts(
                        physicalDisk: nil, filesystemType: nil, isLocal: nil, isDiskImage: nil, interconnect: nil))
                reasons.append("the storage of the \(other.label) could not be described: \(error)")
            }
        }
        let verdict = BackupIndependence.evaluate(
            backup: backupReport.facts, others: otherFacts, maintainerConfirmed: inputs.confirmed)
        var unsupportedFilesystem = false
        if case .refused(let found) = verdict {
            for refusal in found {
                if case .unsupportedFilesystem = refusal { unsupportedFilesystem = true }
                var text = refusal.description
                for index in others.indices.reversed() {
                    text = text.replacingOccurrences(
                        of: "other location \(index + 1)", with: others[index].label)
                }
                reasons.append(text)
            }
        }
        if backupReport.volumeUUID?.isEmpty ?? true {
            reasons.append(
                "the volume UUID of the backup is unknown; its disconnection cannot be confirmed without it")
        }
        let policy = environment.timestampPolicy(inputs.backup)
        if policy == nil, !unsupportedFilesystem {
            reasons.append(
                "the timestamp policy of the backup volume is undefined: the filesystem \(backupReport.filesystemType) is neither APFS nor HFS+"
            )
        }
        var verifiedAt = ""
        if let policy {
            do {
                let report = try FileInventory.verify(
                    copy: URL(fileURLWithPath: inputs.backup), against: records, policy: policy)
                for mismatch in report.mismatches {
                    reasons.append("backup \(mismatch.path): \(mismatch.kind.rawValue): \(mismatch.detail)")
                }
                verifiedAt = RecoveryRecord.timestampString(Date())
            } catch let error as FileInventoryError {
                reasons.append("backup verification: \(describe(error))")
            } catch {
                reasons.append("backup verification: \(error)")
            }
        }
        guard reasons.isEmpty, let policy else { throw PrepareFailure(step: 4, title: title, reasons: reasons) }
        return VerifiedBackup(
            report: backupReport, policy: policy, verifiedCount: records.count, verifiedAt: verifiedAt)
    }

    // MARK: Plan

    static func printPlan(
        _ inputs: Inputs, locations: RebuildLocations, records: [FileRecord], totalBytes: UInt64,
        capacity: CapacityPlan, additionList: [String], displayList: [String], evacuation: [EvacuationEntry],
        backup: VerifiedBackup, registrations: Int, console: Console
    ) {
        console.print("")
        console.print(inputs.dryRun ? "Plan (dry run):" : "Plan:")
        console.print("Locations:")
        console.print("  source: \(locations.sources[0])")
        console.print("  media folder: \(locations.mediaFolder)")
        console.print("  backup: \(locations.backupRoot)")
        console.print("  restoration-test directory: \(locations.restorationDirectory)")
        console.print("  staging directory: \(locations.stagingDirectory)")
        console.print("  workspace: \(locations.workspaceDirectory)")
        console.print("Inventory: \(records.count) files, \(totalBytes) bytes, \(registrations) registrations")
        console.print("Capacity by volume:")
        for volume in capacity.volumes {
            console.print(
                "  volume \(volume.volume): needs \(volume.required) bytes for "
                    + volume.purposes.joined(separator: ", ") + "; available "
                    + (volume.available.map { "\($0) bytes" } ?? "unknown"))
        }
        console.print("Addition order (\(inputs.order.rawValue)), first added to last added:")
        for (index, album) in additionList.enumerated() { console.print("  \(index + 1). \(album)") }
        console.print("Expected display order, first visible to last:")
        for (index, album) in displayList.enumerated() { console.print("  \(index + 1). \(album)") }
        let crossVolume = capacity.volumes.contains { $0.purposes.contains("staging directory") }
        console.print(
            "Evacuation plan (recorded only; nothing is evacuated in this version): \(evacuation.count) files keep their relative paths under "
                + "\(locations.stagingDirectory); \(crossVolume ? "cross-volume, so the sources are retained until a verified copy exists" : "same volume as the sources")"
        )
        console.print(
            "Backup: \(backup.report.mountPoint), filesystem \(backup.report.filesystemType), interconnect "
                + "\(backup.report.facts.interconnect ?? "unknown"), volume UUID \(backup.report.volumeUUID ?? "unknown"); "
                + "physical independence: separate disk, confirmed by the maintainer")
        console.print("Timestamp policy: \(backup.policy.rawValue)")
        console.print(
            "Backup verification: \(backup.verifiedCount) files verified for bytes, sizes, and dates")
        if !inputs.dryRun {
            console.print(
                "Changes: copies \(records.count) files (\(totalBytes) bytes) from the backup into \(locations.restorationDirectory) and keeps them; "
                    + "writes one recovery record to \(locations.workspaceDirectory). Source files, the backup, and Music are not modified."
            )
        }
    }

    // MARK: Step 5

    struct Restoration {
        var policy: TimestampPolicy
        var verifiedAt: String
    }

    static func restore(
        _ inputs: Inputs, records: [FileRecord], backup: VerifiedBackup, environment: Environment, console: Console,
        progress: PrepareProgress
    ) throws -> Restoration {
        let title = "restoration test"
        guard let copy = environment.restoreCopy, let setDates = environment.setPreciseDates else {
            throw PrepareFailure(step: 5, title: title, reasons: ["copying and date setting are unavailable here"])
        }
        let root = URL(fileURLWithPath: inputs.restoration)
        if pathKind(root) != .directory {
            throw PrepareFailure(
                step: 5, title: title,
                reasons: ["the restoration-test directory \(inputs.restoration) is not an existing directory"])
        }
        if let problem = nonEmptyReason(inputs.restoration) {
            throw PrepareFailure(step: 5, title: title, reasons: [problem])
        }
        guard let restorePolicy = environment.timestampPolicy(inputs.restoration) else {
            throw PrepareFailure(
                step: 5, title: title,
                reasons: ["the restoration volume is neither APFS nor HFS+, so its timestamps cannot be verified"])
        }
        let policy: TimestampPolicy = (backup.policy == .hfsPlus || restorePolicy == .hfsPlus) ? .hfsPlus : .apfs
        console.print(
            "Restoring \(records.count) files from \(inputs.backup) into \(inputs.restoration) under the policy \(policy.rawValue). Restored files are kept."
        )
        for record in records {
            let from = URL(fileURLWithPath: inputs.backup + "/" + record.path)
            let to = URL(fileURLWithPath: inputs.restoration + "/" + record.path)
            progress.restoreAttempted = true
            do {
                try copy(from, to, root)
                progress.copiedFiles += 1
                // The dates that the policy accepts: whole seconds when either volume is HFS+.
                let modification = policy == .hfsPlus ? record.modification.truncatedToSeconds : record.modification
                let creation = record.creation.map { policy == .hfsPlus ? $0.truncatedToSeconds : $0 }
                guard let creation else {
                    throw PrepareFailure(step: 5, title: title, reasons: ["\(record.path) has no creation date"])
                }
                _ = try setDates(to.path, modification, creation)
            } catch let failure as PrepareFailure {
                throw failure
            } catch {
                throw PrepareFailure(step: 5, title: title, reasons: ["\(record.path): \(error)"])
            }
        }
        let report: VerificationReport
        do {
            report = try FileInventory.verify(copy: root, against: records, policy: policy)
        } catch let error as FileInventoryError {
            throw PrepareFailure(step: 5, title: title, reasons: ["restoration verification: \(describe(error))"])
        } catch {
            throw PrepareFailure(step: 5, title: title, reasons: ["restoration verification: \(error)"])
        }
        if !report.isSuccess {
            throw PrepareFailure(
                step: 5, title: title,
                reasons: report.mismatches.map { "restored \($0.path): \($0.kind.rawValue): \($0.detail)" })
        }
        return Restoration(policy: policy, verifiedAt: RecoveryRecord.timestampString(Date()))
    }
}
