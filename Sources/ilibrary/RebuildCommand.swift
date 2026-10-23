import CatalogCore
import Foundation
import RebuildCore

/// The `rebuild` command group: preparation, the four stages that rebuild the library, and status.
enum RebuildCommand {
    static let syntax = CommandSyntax(
        name: "rebuild",
        usage: """
            Usage: ilibrary rebuild SUBCOMMAND [OPTIONS] [ARGUMENTS]

            Rebuilds a Music library from its files in stages. Preparation inventories the files and the
            registrations, verifies a backup on separate storage, tests its restoration, and records the plan.
            The stages then move the files out of the media folder, remove their registrations, write the
            catalog to the files while Music is closed, and add the albums again in the planned order. Each stage
            records its progress in the workspace, resumes after an interruption, and refuses to run out of order.

            Subcommands:
              prepare   inventory, verify the backup, test restoration, and write a recovery record
              stage     move the inventoried files from the media folder to the staging directory
              clear     remove the recorded registrations, confirm that none remain, and quit Music
              apply     write the catalog, names, and optional dates to the staged files
              add       add the albums in the recorded order and confirm their addition dates
              status    report the recovery record and the progress of the stages

            Run 'ilibrary rebuild SUBCOMMAND --help' for the options of a subcommand.
            """, positionals: 0...Int.max)

    static let stageSyntax = CommandSyntax(
        name: "rebuild stage",
        usage: """
            Usage: ilibrary rebuild stage --workspace DIR [--dry-run]

            Moves every inventoried file from the media folder to its place in the staging directory, which keeps
            its relative path, and confirms that the moved file has the size, SHA-256, and dates of the inventory.
            Music must be closed, the staging directory must be on the volume of the media folder, and no staged
            path may exist. Registrations are not changed.

            Options:
              --workspace DIR   the directory that holds the recovery record
              --dry-run         check every file, list the moves, and change nothing
            """, valued: ["--workspace": []], flags: ["--dry-run"], positionals: 0...0)

    static let clearSyntax = CommandSyntax(
        name: "rebuild clear",
        usage: """
            Usage: ilibrary rebuild clear --workspace DIR [--dry-run]

            Removes the registrations recorded by rebuild prepare, one persistent ID per request, after confirming
            that each track still has its recorded name, album, and artist and that its file is still staged. It
            refuses to start when the library holds any other track or a staged file is missing or changed. It then confirms that Music reports no tracks and quits Music. The Music window is
            not inspected. Requires a completed stage, macOS, and the Automation permission for Music.

            Options:
              --workspace DIR   the directory that holds the recovery record
              --dry-run         compare the files and the library with the record, list the removals, and change
                                nothing; reading the library launches Music
            """, valued: ["--workspace": []], flags: ["--dry-run"], positionals: 0...0)

    static let applySyntax = CommandSyntax(
        name: "rebuild apply",
        usage: """
            Usage: ilibrary rebuild apply --workspace DIR [--timestamps] [--dry-run]

            Writes the recorded catalog to the staged files, as 'ilibrary apply --rename' does, and arranges them
            as Album Artist/Album/NN Title.m4a in the staging directory. Music must stay closed. The catalog must be
            the file that rebuild prepare recorded. Requires a completed clear.

            Options:
              --workspace DIR   the directory that holds the recovery record
              --timestamps      also set file dates to release dates at local midnight (macOS)
              --dry-run         list the planned changes and change nothing
            """, valued: ["--workspace": []], flags: ["--timestamps", "--dry-run"], positionals: 0...0)

    static let addSyntax = CommandSyntax(
        name: "rebuild add",
        usage: """
            Usage: ilibrary rebuild add --workspace DIR [--timestamps] [--dry-run]

            Moves each album's staged files into the media folder and adds them in place, one album per request,
            in the order recorded by rebuild prepare. Each album is added only after the clock has passed the
            latest addition second of the album before it, and its own addition seconds must be later. Finally the
            albums' addition dates, newest first, are compared with the expected Recently Added order. Requires a
            completed apply, macOS, and the Automation permission for Music; reading the library launches Music.

            Options:
              --workspace DIR   the directory that holds the recovery record
              --timestamps      afterwards, set album and artist folder dates in the media folder (macOS)
              --dry-run         list the albums and moves and change nothing
            """, valued: ["--workspace": []], flags: ["--timestamps", "--dry-run"], positionals: 0...0)

    static let prepareSyntax = CommandSyntax(
        name: "rebuild prepare",
        usage: """
            Usage: ilibrary rebuild prepare CATALOG.json SOURCE --workspace DIR --backup DIR --restore-test DIR
                                            --staging DIR [--order release|artist|artist-desc|artist-release]
                                            [--confirm-separate-device] [--disconnect-timeout SECONDS] [--dry-run]

            Verifies that the library under SOURCE can be rebuilt, in this order, and stops at the first step
            that fails, listing every reason of that step.
              1. The catalog is validated against the .m4a files under SOURCE, which are inventoried (size,
                 SHA-256, and dates). Every file must match the catalog and every catalog track a file.
              2. The whole Music library is read. Every registration must be a file track of the inventory with
                 an admitted cloud status, and every file must be registered once.
              3. The locations must not overlap or pass through symbolic links, and every volume must have
                 the capacity that the plan needs.
              4. The backup must be on separate physical storage (APFS or HFS+, not a disk image, with a known
                 volume UUID) and must hold every file with equal bytes and dates.
              5. The backup is restored into the restoration-test directory, which must exist and be empty, and
                 the result is verified. Restored files are kept and never deleted by iLibrary.
              6. You are asked to eject the backup volume, and its disappearance is confirmed.
              7. A recovery record is written to the workspace and read back.
            Only one SOURCE directory is supported in this version; multiple sources are not supported yet.
            Source files, the backup, and Music are never modified, and no registration is added or removed.
            Requires macOS and the Automation permission for Music.

            Options:
              --workspace DIR              existing directory that receives the recovery record (private)
              --backup DIR                 existing directory that mirrors the relative paths of SOURCE
              --restore-test DIR           existing empty directory for the restoration test
              --staging DIR                directory outside Music's media folder planned for evacuation
              --order ORDER                release (default), artist, artist-desc, or artist-release
              --confirm-separate-device    state that the backup is on a separate physical device
              --disconnect-timeout SECONDS wait for the ejection at most this long (default 600)
              --dry-run                    perform steps 1 to 4, print the plan, and change nothing
            """,
        valued: [
            "--workspace": [], "--backup": [], "--restore-test": [], "--staging": [], "--order": [],
            "--disconnect-timeout": [],
        ], flags: ["--confirm-separate-device", "--dry-run"], positionals: 2...Int.max)

    static let statusSyntax = CommandSyntax(
        name: "rebuild status",
        usage: """
            Usage: ilibrary rebuild status --workspace DIR

            Reads the recovery record in the workspace and reports its creation time, locations, counts, backup
            and restoration results, stage, and the next required action. It does not access Music or the
            backup and changes nothing. The record is private: it contains machine-specific paths and Music
            persistent IDs. Exit status is 0 for a valid record and 1 for a missing or invalid one.

            Options:
              --workspace DIR   the directory that holds the recovery record
            """, valued: ["--workspace": []], positionals: 0...0)

    static let subcommands: [String: CommandSyntax] = [
        "prepare": prepareSyntax, "stage": stageSyntax, "clear": clearSyntax, "apply": applySyntax,
        "add": addSyntax, "status": statusSyntax,
    ]

    /// The help text of a subcommand, or of the group when the subcommand is nil or unknown.
    static func usage(for subcommand: String?) -> String {
        subcommand.flatMap { subcommands[$0]?.usage } ?? syntax.usage
    }

    static func workspace(_ parsed: ParsedArguments, _ name: String) throws -> String {
        guard let option = parsed.value("--workspace") else {
            throw CommandError.usage("rebuild \(name): --workspace DIR is required")
        }
        return option
    }

    static func run(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        guard let subcommand = arguments.first else {
            throw CommandError.usage("rebuild: a subcommand is required\n\n\(syntax.usage)")
        }
        let rest = Array(arguments.dropFirst())
        if subcommand == "--help" || subcommand == "-h" {
            console.print(syntax.usage)
            return 0
        }
        guard subcommands[subcommand] != nil else {
            throw CommandError.usage("rebuild: unknown subcommand \(subcommand)\n\n\(syntax.usage)")
        }
        if rest.contains("--help") || rest.contains("-h") {
            console.print(usage(for: subcommand))
            return 0
        }
        switch subcommand {
        case "prepare": return try RebuildPrepare.run(rest, console: console, environment: environment)
        case "stage": return try RebuildStages.stage(rest, console: console, environment: environment)
        case "clear": return try RebuildStages.clear(rest, console: console, environment: environment)
        case "apply": return try RebuildStages.apply(rest, console: console, environment: environment)
        case "add": return try RebuildStages.add(rest, console: console, environment: environment)
        default: return try RebuildStatus.run(rest, console: console)
        }
    }

    // MARK: Paths

    /// Resolves a path to an absolute one in which every symbolic link in the existing part is resolved. Relative
    /// paths are taken from the working directory. A ".." component removes the resolved component before it, as
    /// the system does. Components that do not exist are appended unchanged. Nothing is created.
    static func resolve(_ path: String) -> String {
        let base = path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
        var current = "/"
        for part in base.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..":
                let real = realPath(current) ?? current
                current = real == "/" ? "/" : parent(of: real)
            default:
                let candidate = (current == "/" ? "" : current) + "/" + part
                current = realPath(candidate) ?? candidate
            }
        }
        return current
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return "/" }
        return String(path[..<slash])
    }

    /// The path itself when it exists, and otherwise its nearest existing ancestor.
    static func nearestExisting(_ path: String) -> String {
        var current = path
        while current != "/", pathKind(current) == .missing { current = parent(of: current) }
        return current
    }

    // MARK: Descriptions of record errors

    static func describe(_ problem: RecoveryRecordProblem) -> String {
        switch problem {
        case .malformedPersistentID(let id): "malformed persistent ID '\(id)'"
        case .duplicatePersistentID(let id): "persistent ID \(id) occurs more than once"
        case .invalidInventoryPath(let path): "invalid inventory path '\(path)'"
        case .escapingInventoryPath(let path): "inventory path '\(path)' leaves its source root"
        case .collidingInventoryPaths(let first, let second): "inventory paths '\(first)' and '\(second)' collide"
        case .inventoryUnsorted: "the inventory is not sorted"
        case .unknownSourceRoot(let root): "an inventory file names the unknown source root '\(root)'"
        case .mappingNotOneToOne(let detail): "the registration mapping is not one-to-one: \(detail)"
        case .evacuationOutsideStaging(let path): "the evacuation target '\(path)' is outside the staging directory"
        case .evacuationNotUnique(let path): "the evacuation target '\(path)' occurs more than once"
        case .evacuationSourcesDiffer(let detail): "the evacuation plan differs from the inventory: \(detail)"
        case .displayListNotReverse: "the expected display list is not the reverse of the addition list"
        case .backupDisconnectedWithoutVerification:
            "the backup is recorded as disconnected without a successful verification and confirmation"
        case .inconsistent(let detail): detail
        case .locationsInvalid(let refusals):
            "the locations are invalid: " + refusals.map(\.description).joined(separator: "; ")
        }
    }

    static func describe(_ error: RecoveryRecordError) -> [String] {
        switch error {
        case .alreadyExists(let path): ["a recovery record already exists at \(path)"]
        case .notADirectory(let path): ["\(path) is not a directory"]
        case .notARegularFile(let path): ["\(path) is not a regular file"]
        case .unreadable(let path, let reason): ["\(path) cannot be read: \(reason)"]
        case .wrongFormat(let format): ["the record has the unsupported format '\(format)'"]
        case .malformed(let detail): ["the record is not well formed: \(detail)"]
        case .checksumMismatch: ["the record's checksum does not match its content (it is damaged or was edited)"]
        case .invalid(let problems): problems.map(describe)
        case .writeFailed(let detail): ["the record could not be written: \(detail)"]
        case .readBackMismatch: ["the record read back differs from the record written"]
        }
    }
}

enum RebuildStatus {
    static func run(_ arguments: [String], console: Console) throws -> Int32 {
        let parsed = try RebuildCommand.statusSyntax.parse(arguments)
        let workspace = RebuildCommand.resolve(try RebuildCommand.workspace(parsed, "status"))
        let recordPath = workspace + "/" + RecoveryRecord.fileName
        console.print("Workspace: \(workspace)")
        guard pathKind(recordPath) != .missing else {
            console.error("there is no recovery record at \(recordPath)")
            throw CommandError.failure("rebuild status: no valid recovery record; nothing was changed")
        }
        let record: RecoveryRecord
        do {
            record = try RecoveryRecord.load(from: URL(fileURLWithPath: workspace))
        } catch let error as RecoveryRecordError {
            for reason in RebuildCommand.describe(error) { console.error(reason) }
            throw CommandError.failure(
                "rebuild status: the recovery record is invalid and is not trusted; nothing was changed")
        }
        let bytes = record.inventory.reduce(UInt64(0)) { $0 &+ $1.record.size }
        console.print("Recovery record: \(recordPath) (format \(record.format), private)")
        console.print("Created: \(record.createdAt) by ilibrary \(record.ilibraryVersion)")
        console.print("Catalog: \(record.catalogPath) (SHA-256 \(record.catalogSHA256))")
        console.print("Locations:")
        for (index, source) in record.locations.sources.enumerated() {
            console.print("  source \(index + 1): \(source)")
        }
        console.print("  media folder: \(record.locations.mediaFolder)")
        console.print("  backup: \(record.locations.backupRoot)")
        console.print("  restoration-test directory: \(record.locations.restorationDirectory)")
        console.print("  staging directory: \(record.locations.stagingDirectory)")
        console.print("  workspace: \(record.locations.workspaceDirectory)")
        console.print(
            "Counts: \(record.inventory.count) files (\(bytes) bytes), \(record.registrations.count) registrations, "
                + "\(record.additionList.count) albums")
        func verification(_ summary: VerificationSummary?) -> String {
            summary.map { $0.success ? "verified \($0.checkedCount) files" : "verification failed" } ?? "not verified"
        }
        let backup = record.backup
        console.print(
            "Backup: \(verification(backup.verification))"
                + (backup.verifiedAt.map { " at \($0)" } ?? "")
                + "; filesystem \(backup.filesystemType ?? "unknown"), timestamp policy \(backup.timestampPolicy.rawValue), "
                + "volume UUID \(backup.volumeUUID ?? "unknown"); separate device confirmed by the maintainer: "
                + (backup.maintainerConfirmed ? "yes" : "no"))
        console.print(
            "Backup disconnected: \(backup.disconnectedAt.map { "yes, confirmed at \($0)" } ?? "not confirmed")")
        let restoration = record.restoration
        console.print(
            "Restoration test: \(verification(restoration.verification))"
                + (restoration.verifiedAt.map { " at \($0)" } ?? "") + "; directory \(restoration.directory) (kept)")
        console.print("Record stage: \(record.stage.rawValue)")
        let journalPath = workspace + "/" + ProgressJournal.fileName
        var progress: RebuildProgress?
        if pathKind(journalPath) != .missing {
            do {
                let recordBytes = try ProgressJournalFile.loadRecord(from: URL(fileURLWithPath: workspace)).bytes
                progress = try ProgressJournalFile.read(
                    in: URL(fileURLWithPath: workspace), record: record, recordBytes: recordBytes
                ).progress
            } catch {
                console.error("the progress journal cannot be used: \(error)")
                throw CommandError.failure("rebuild status: the progress journal is invalid; nothing was changed")
            }
        }
        console.print("Progress journal: " + (progress == nil ? "none; no stage has begun" : journalPath))
        if let progress {
            let completed = progress.completedStages.map(\.rawValue)
            console.print("Completed stages: " + (completed.isEmpty ? "none" : completed.joined(separator: ", ")))
            if let current = progress.currentStage { console.print("Stage in progress: \(current.rawValue)") }
            if let open = progress.openOperation {
                console.print(
                    "Open operation: \(open.operation.rawValue) \(open.target)"
                        + (open.returned ? " (performed, not yet verified)" : " (not yet performed)"))
            }
            let counts: [(RebuildOperation, Int, String)] = [
                (.evacuateFile, record.evacuation.count, "files staged"),
                (.removeRegistration, record.mapping.count, "registrations removed"),
                (.applyFile, record.evacuation.count, "files applied"),
                (.addAlbum, record.additionList.count, "albums added"),
            ]
            for (operation, total, label) in counts {
                console.print("  \(progress.verifiedTargets[operation]?.count ?? 0) of \(total) \(label)")
            }
        }
        let next: String
        switch progress?.completedStages.last {
        case nil: next = "run 'ilibrary rebuild stage' with Music closed"
        case .evacuation: next = "run 'ilibrary rebuild clear'"
        case .clearing: next = "run 'ilibrary rebuild apply' while Music stays closed"
        case .application, .addition: next = "run 'ilibrary rebuild add'"
        case .display: next = "none; the rebuild is complete. Keep the backup until you have checked the library"
        }
        console.print("Next required action: \(next)")
        return 0
    }
}
