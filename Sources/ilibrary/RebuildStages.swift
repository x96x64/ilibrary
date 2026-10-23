import CatalogCore
import Foundation
import RebuildCore

/// A prepared rebuild: its recovery record and its progress journal in the workspace.
///
/// Every change is recorded as an operation: an intent, the return of an action, and a verified observation. An
/// action that fails leaves its intent open without a return, so that the next run repeats it; each action
/// therefore first checks whether its effect is already present.
struct RebuildSession {
    let workspace: URL
    let record: RecoveryRecord
    let recordBytes: Data
    private(set) var progress: RebuildProgress?

    init(workspace option: String) throws {
        workspace = URL(fileURLWithPath: RebuildCommand.resolve(option), isDirectory: true)
        do {
            (record, recordBytes) = try ProgressJournalFile.loadRecord(from: workspace)
        } catch {
            throw CommandError.failure(
                "there is no valid recovery record in \(workspace.path): \(error); run 'ilibrary rebuild prepare' first"
            )
        }
        if pathKind(workspace.appendingPathComponent(ProgressJournal.fileName)) != .missing {
            try reload()
        }
    }

    var hasJournal: Bool { progress != nil }

    func completed(_ stage: RebuildStage) -> Bool { progress?.completedStages.contains(stage) ?? false }

    func verified(_ operation: RebuildOperation, _ target: String) -> Bool {
        progress?.isVerified(operation, target) ?? false
    }

    /// Refuses to run a stage before the stages that precede it are complete.
    func require(_ stage: RebuildStage, after previous: RebuildStage?, command: String) throws {
        if let previous, !completed(previous) {
            throw CommandError.failure(
                "rebuild \(command) requires the \(previous.rawValue) stage to be complete; run 'ilibrary rebuild status'"
            )
        }
        if let current = progress?.currentStage, current != stage {
            throw CommandError.failure("the \(current.rawValue) stage is in progress; run 'ilibrary rebuild status'")
        }
        if let open = progress?.openOperation, open.operation.stage != stage {
            throw CommandError.failure("the operation \(open.operation.rawValue) \(open.target) is still open")
        }
    }

    mutating func reload() throws {
        do {
            progress = try ProgressJournalFile.read(in: workspace, record: record, recordBytes: recordBytes).progress
        } catch {
            throw CommandError.failure("the progress journal cannot be used: \(error)")
        }
    }

    mutating func createJournal() throws {
        guard progress == nil else { return }
        do {
            try ProgressJournalFile.create(
                in: workspace, record: record, recordBytes: recordBytes, ilibraryVersion: version)
        } catch {
            throw CommandError.failure("the progress journal could not be created: \(error)")
        }
        try reload()
    }

    mutating func append(_ body: JournalBody) throws {
        guard let head = progress?.head else { throw CommandError.failure("the progress journal does not exist") }
        do {
            try ProgressJournalFile.append(
                body, to: workspace, expectedHead: head, record: record, recordBytes: recordBytes)
        } catch {
            throw CommandError.failure("the progress journal refused an entry: \(error)")
        }
        try reload()
    }

    mutating func begin(_ stage: RebuildStage) throws {
        if progress?.currentStage != stage { try append(.stageBegan(stage)) }
    }

    mutating func complete(_ stage: RebuildStage) throws { try append(.stageCompleted(stage)) }

    /// Performs and records one operation, or completes it when an earlier run left it open.
    mutating func perform(
        _ operation: RebuildOperation, _ target: String, action: () throws -> Void,
        observe: () throws -> JournalObservation
    ) throws {
        if let open = progress?.openOperation {
            guard open.operation == operation, open.target == target else {
                throw CommandError.failure("the operation \(open.operation.rawValue) \(open.target) is still open")
            }
            guard !open.returnFailed else {
                throw CommandError.failure(
                    "the operation \(operation.rawValue) \(target) was recorded as failed; restore from the backup")
            }
        } else {
            try append(.intent(operation: operation, target: target))
        }
        if progress?.openOperation?.returned != true {
            try action()
            try append(.returned(operation: operation, target: target, succeeded: true, detail: "completed"))
        }
        try append(.verified(operation: operation, target: target, observation: observe()))
    }

    /// The targets of a stage in order, with the open one, if any, first.
    func ordered(_ targets: [String], _ operation: RebuildOperation) -> [String] {
        let pending = targets.filter { !verified(operation, ProgressJournal.canonicalTarget(operation, $0)) }
        guard let open = progress?.openOperation, open.operation == operation,
            let index = pending.firstIndex(where: {
                ProgressJournal.canonicalTarget(operation, $0)
                    == ProgressJournal.canonicalTarget(operation, open.target)
            })
        else { return pending }
        return [pending[index]] + pending.enumerated().filter { $0.offset != index }.map(\.element)
    }

    /// The current path of each staged file: its result after application, or its staging path.
    var stagedFiles: [String] {
        record.evacuation.map { progress?.appliedPaths[$0.stagingPath] ?? $0.stagingPath }
    }
}

enum RebuildStages {
    // MARK: Shared checks

    /// The file at a path as an inventory would record it, or nil when nothing is there.
    static func observe(_ path: String) throws -> ObservedFile? {
        let url = URL(fileURLWithPath: path)
        switch pathKind(url) {
        case .missing: return nil
        case .file: break
        default: throw CommandError.failure("\(path) is not a regular file")
        }
        let inventory = try FileInventory(root: url.deletingLastPathComponent(), selecting: [url.lastPathComponent])
        return ObservedFile(inventory.records[0])
    }

    /// Confirms, by status rather than digest, that an evacuated file is still at its staging path with its
    /// recorded size and modification time and that nothing has returned to its original place.
    static func stillStaged(_ entry: EvacuationEntry, _ expected: FileRecord) -> Bool {
        guard pathKind(URL(fileURLWithPath: entry.sourcePath)) == .missing,
            let status = try? FileStatus.read(atPath: entry.stagingPath), status.kind == .regular
        else { return false }
        return status.size == expected.size && status.modification == expected.modification
    }

    /// A path as Music or the file system may spell it, reduced to one form for comparison.
    static func normalized(_ path: String) -> String {
        RebuildCommand.resolve(path).precomposedStringWithCanonicalMapping
    }

    /// True when Music is confirmed not to be running.
    static func musicClosed(_ environment: Environment) throws -> Bool {
        guard let status = environment.musicStatus else {
            throw CommandError.failure("the state of Music cannot be read on this system; nothing was changed")
        }
        return !status.isRunning()
    }

    static func requireMusic(_ environment: Environment) throws -> any MusicLibrary {
        guard let music = environment.music else {
            throw CommandError.failure("this stage requires macOS and the Automation permission for Music")
        }
        return music
    }

    /// Loads the recorded catalog after confirming that it is the file that was prepared.
    static func recordedCatalog(_ session: RebuildSession, console: Console) throws -> Catalog {
        let url = URL(fileURLWithPath: session.record.catalogPath)
        guard pathKind(url) == .file, let data = try? Data(contentsOf: url),
            SHA256.digest(of: data) == session.record.catalogSHA256
        else {
            throw CommandError.failure(
                "the catalog \(url.path) is missing or differs from the one recorded by rebuild prepare")
        }
        return try loadCatalog(url.path, console: console).catalog
    }

    // MARK: stage

    static func stage(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        let parsed = try RebuildCommand.stageSyntax.parse(arguments)
        var session = try RebuildSession(workspace: try RebuildCommand.workspace(parsed, "stage"))
        let record = session.record
        if session.completed(.evacuation) {
            console.print("The evacuation stage is already complete; nothing was changed.")
            return 0
        }
        try session.require(.evacuation, after: nil, command: "stage")
        guard record.backup.verification?.success == true, record.backup.disconnectedAt != nil,
            record.restoration.verification?.success == true
        else { throw CommandError.failure("the record does not show a verified, disconnected backup and restoration") }
        guard try musicClosed(environment) else {
            throw CommandError.failure("quit Music before the files are moved out of its media folder")
        }
        let pending = session.ordered(record.evacuation.map(\.sourcePath), .evacuateFile)
        let entries = Dictionary(uniqueKeysWithValues: record.evacuation.map { ($0.sourcePath, $0) })
        let inventory = Dictionary(uniqueKeysWithValues: record.inventory.map { ($0.absolutePath, $0.record) })
        let staging = URL(fileURLWithPath: record.locations.stagingDirectory, isDirectory: true)
        let stagingVolume = environment.volumeIdentifier(
            URL(fileURLWithPath: RebuildCommand.nearestExisting(staging.path)))
        console.print("Workspace: \(session.workspace.path)")
        console.print("Files to move from the media folder to \(staging.path): \(pending.count)")
        for source in pending {
            let entry = entries[source]!
            let staged = try observe(entry.stagingPath)
            let present = try observe(source)
            let isOpen = session.progress?.openOperation?.target == source
            if let staged, staged.matches(inventory[source]!), present == nil, isOpen {
                console.print("  already moved: \(source)")
                continue
            }
            guard let present, present.matches(inventory[source]!) else {
                throw CommandError.failure("\(source) is missing or differs from the inventory; nothing was moved")
            }
            guard staged == nil else {
                throw CommandError.failure("\(entry.stagingPath) already exists; nothing was moved")
            }
            guard let stagingVolume, environment.volumeIdentifier(URL(fileURLWithPath: source)) == stagingVolume
            else {
                throw CommandError.failure(
                    "the staging directory must be on the volume of the media folder, so that files are moved without "
                        + "copying; nothing was moved")
            }
            console.print("  move \(source) -> \(entry.stagingPath)")
        }
        if parsed.flag("--dry-run") {
            console.print("Dry run: nothing was changed.")
            return 0
        }
        try session.createJournal()
        try session.begin(.evacuation)
        let manager = FileManager.default
        for source in pending {
            let entry = entries[source]!
            try session.perform(
                .evacuateFile, source,
                action: {
                    guard pathKind(URL(fileURLWithPath: source)) == .file else { return }
                    let target = URL(fileURLWithPath: entry.stagingPath)
                    try manager.createDirectory(
                        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard pathKind(target) == .missing else {
                        throw CommandError.failure("\(target.path) appeared before the move")
                    }
                    try manager.moveItem(at: URL(fileURLWithPath: source), to: target)
                },
                observe: {
                    guard let staged = try observe(entry.stagingPath), staged.matches(inventory[source]!),
                        try observe(source) == nil
                    else {
                        throw CommandError.failure("\(entry.stagingPath) does not match the inventory after the move")
                    }
                    return JournalObservation(method: "rename", staged: staged, sourcePresent: false)
                })
        }
        try session.complete(.evacuation)
        console.print("Staged: \(record.evacuation.count) files moved and verified. Next: ilibrary rebuild clear")
        return 0
    }

    // MARK: clear

    static func clear(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        let parsed = try RebuildCommand.clearSyntax.parse(arguments)
        var session = try RebuildSession(workspace: try RebuildCommand.workspace(parsed, "clear"))
        let record = session.record
        if session.completed(.clearing) {
            console.print("The clearing stage is already complete; nothing was changed.")
            return 0
        }
        try session.require(.clearing, after: .evacuation, command: "clear")
        let music = try requireMusic(environment)
        let registrations = Dictionary(
            uniqueKeysWithValues: record.registrations.map { ($0.persistentID.uppercased(), $0) })
        let inventory = Dictionary(uniqueKeysWithValues: record.inventory.map { ($0.absolutePath, $0.record) })
        let evacuations = Dictionary(uniqueKeysWithValues: record.evacuation.map { ($0.sourcePath, $0) })
        let locations = Dictionary(
            uniqueKeysWithValues: record.mapping.map { ($0.persistentID.uppercased(), $0.location) })
        let pending = session.ordered(record.mapping.map(\.persistentID), .removeRegistration)
        var problems: [String] = []
        for entry in record.evacuation where !stillStaged(entry, inventory[entry.sourcePath]!) {
            problems.append("\(entry.stagingPath) is missing or changed, or \(entry.sourcePath) exists again")
        }
        if !pending.isEmpty || !session.verified(.confirmLibraryEmpty, "") {
            let pendingIDs = Set(pending.map { $0.uppercased() })
            let snapshot = try music.librarySnapshot()
            let present = Set(snapshot.tracks.map { $0.persistentID.uppercased() })
            let openRemoval = session.progress?.openOperation.flatMap {
                $0.operation == .removeRegistration ? $0.target.uppercased() : nil
            }
            if snapshot.trackCount != snapshot.fileTrackCount {
                problems.append(
                    "the library holds \(snapshot.trackCount - snapshot.fileTrackCount) tracks that are not files")
            }
            for id in present.subtracting(pendingIDs).sorted() {
                problems.append("the library holds \(id), which the record does not plan to remove")
            }
            for id in pendingIDs.subtracting(present).subtracting(openRemoval.map { [$0] } ?? []).sorted() {
                problems.append("the planned registration \(id) is missing from the library")
            }
            for track in snapshot.tracks {
                guard let expected = registrations[track.persistentID.uppercased()] else { continue }
                if track.name != expected.name || track.album != expected.album || track.artist != expected.artist {
                    problems.append("\(track.persistentID) no longer has its recorded name, album, and artist")
                }
            }
        }
        guard problems.isEmpty else {
            for problem in problems { console.error(problem) }
            throw CommandError.failure("the files or the library differ from the recovery record; nothing was removed")
        }
        console.print("Workspace: \(session.workspace.path)")
        console.print("Registrations to remove, one per request: \(pending.count)")
        for id in pending {
            let registration = registrations[id.uppercased()]!
            console.print("  remove \(id): \(registration.artist) - \(registration.album) - \(registration.name)")
        }
        console.print("Then: confirm that Music reports no tracks, and quit Music. Reading the library launches Music.")
        if parsed.flag("--dry-run") {
            console.print("Dry run: nothing was changed.")
            return 0
        }
        try session.begin(.clearing)
        var remaining = Set(record.mapping.map { $0.persistentID.uppercased() }).subtracting(
            session.progress?.verifiedTargets[.removeRegistration] ?? [])
        for id in pending {
            let registration = registrations[id.uppercased()]!
            try session.perform(
                .removeRegistration, id,
                action: {
                    guard try music.track(persistentID: registration.persistentID) != nil else { return }
                    let location = locations[id.uppercased()]!
                    guard stillStaged(evacuations[location]!, inventory[location]!) else {
                        throw CommandError.failure("\(location) is no longer safely staged; \(id) was not removed")
                    }
                    try music.remove(
                        persistentID: registration.persistentID, name: registration.name, album: registration.album,
                        artist: registration.artist)
                },
                observe: {
                    guard try music.track(persistentID: registration.persistentID) == nil else {
                        throw CommandError.failure("\(id) is still in the library after its removal")
                    }
                    remaining.remove(id.uppercased())
                    return JournalObservation(remaining: remaining.sorted())
                })
        }
        if !session.verified(.confirmLibraryEmpty, "") {
            try session.perform(
                .confirmLibraryEmpty, "", action: {},
                observe: {
                    let count = try music.librarySnapshot().trackCount
                    guard count == 0 else {
                        throw CommandError.failure("Music still reports \(count) tracks; the clearing stage stopped")
                    }
                    return JournalObservation(registrationCount: 0)
                })
        }
        if !session.verified(.terminateMusic, "") {
            try session.perform(
                .terminateMusic, "",
                // Music may quit before it answers the request, so a failed request is judged by the result.
                action: { if !(try musicClosed(environment)) { try? music.quit() } },
                observe: {
                    guard try waitUntilClosed(environment) else {
                        throw CommandError.failure("Music did not quit; quit it and run rebuild clear again")
                    }
                    return JournalObservation(musicRunning: false)
                })
        }
        guard try waitUntilClosed(environment) else {
            throw CommandError.failure("Music is running again; quit it and run rebuild clear again")
        }
        try session.complete(.clearing)
        console.print(
            "Cleared: \(record.mapping.count) registrations removed; Music reports no tracks and has quit. The Music "
                + "window was not inspected. Next: ilibrary rebuild apply")
        return 0
    }

    /// Waits up to a minute for Music to quit.
    static func waitUntilClosed(_ environment: Environment) throws -> Bool {
        for _ in 0..<60 {
            if try musicClosed(environment) { return true }
            environment.pause(1)
        }
        return try musicClosed(environment)
    }

    // MARK: apply

    static func apply(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        let parsed = try RebuildCommand.applySyntax.parse(arguments)
        var session = try RebuildSession(workspace: try RebuildCommand.workspace(parsed, "apply"))
        let record = session.record
        if session.completed(.application) {
            console.print("The application stage is already complete; nothing was changed.")
            return 0
        }
        try session.require(.application, after: .clearing, command: "apply")
        guard try musicClosed(environment) else {
            throw CommandError.failure("Music must stay closed while the files are edited; quit it and run again")
        }
        _ = try recordedCatalog(session, console: console)
        let timestamps = parsed.flag("--timestamps")
        let prepared = try ApplyCommand.prepare(
            catalogPath: record.catalogPath, paths: [record.locations.stagingDirectory], rename: true,
            timestamps: timestamps, console: console, environment: environment)
        // Planned URLs are standardized, which on macOS turns /private/var into /var; the record holds resolved
        // paths, so every planned path is resolved the same way before it is compared.
        let current = { (plan: ApplyCommand.FilePlan) in RebuildCommand.resolve(plan.file.url.path) }
        let byPath = Dictionary(uniqueKeysWithValues: prepared.plans.map { (current($0), $0) })
        let known = Set(session.stagedFiles)
        let pending = session.ordered(record.evacuation.map(\.stagingPath), .applyFile)
        var planFor: [String: ApplyCommand.FilePlan] = [:]
        for target in pending {
            if let plan = byPath[target] {
                planFor[target] = plan
            } else if session.progress?.openOperation?.target == target {
                let moved = prepared.plans.filter { !known.contains(current($0)) }
                guard moved.count == 1 else { throw CommandError.failure("\(target) cannot be found in staging") }
                planFor[target] = moved[0]
            } else {
                throw CommandError.failure("\(target) is missing from the staging directory; nothing was changed")
            }
        }
        let expected = Set(pending.map { current(planFor[$0]!) }).union(
            known.subtracting(pending))
        let unexpected = prepared.plans.map(current).filter { !expected.contains($0) }
        guard unexpected.isEmpty else {
            throw CommandError.failure("the staging directory holds files that the record does not list: \(unexpected)")
        }
        if parsed.flag("--dry-run") {
            console.print("Dry run: nothing was changed.")
            return 0
        }
        try session.begin(.application)
        let fileDates = Dictionary(
            (prepared.datePlan?.targets ?? []).filter { $0.kind == .file }.map {
                (RebuildCommand.resolve($0.url.path), $0)
            },
            uniquingKeysWith: { first, _ in first })
        for target in pending {
            let plan = planFor[target]!
            let destination = URL(fileURLWithPath: RebuildCommand.resolve((plan.destination ?? plan.file.url).path))
            try session.perform(
                .applyFile, target,
                action: {
                    guard try musicClosed(environment) else { throw CommandError.failure("Music was opened") }
                    if !plan.changes.isEmpty { try ApplyCommand.rewrite(plan) }
                    if destination.path != current(plan) {
                        _ = try ApplyCommand.executeMoves([plan], console: console, shown: prepared.shown)
                    }
                    if let date = fileDates[destination.path] {
                        _ = try TimestampPlanner.execute(TimestampPlan(targets: [date]), environment: environment)
                    }
                },
                observe: {
                    guard let result = try observe(destination.path) else {
                        throw CommandError.failure("\(destination.path) is missing after its application")
                    }
                    return JournalObservation(
                        musicRunning: !(try musicClosed(environment)), result: result,
                        resultPath: destination.path == target ? nil : destination.path)
                })
        }
        try session.complete(.application)
        console.print(
            "Applied: \(record.evacuation.count) staged files written and verified. Next: ilibrary rebuild add")
        return 0
    }

    // MARK: add

    struct StagedAlbum {
        var label: String
        /// The current place of each file, and its place in the staging directory, which differ only for an album
        /// whose addition was interrupted.
        var files: [URL]
        var staged: [String]
        var destinations: [URL]
        var tracks: [ResolvedTrack]
    }

    /// Groups the applied files into the recorded albums and plans their places in the media folder.
    static func stagedAlbums(_ session: RebuildSession, console: Console) throws -> [StagedAlbum] {
        let catalog = try recordedCatalog(session, console: console)
        let musicFolder = URL(fileURLWithPath: session.record.locations.mediaFolder, isDirectory: true)
            .appendingPathComponent("Music", isDirectory: true)
        // A file of an album whose addition was interrupted may already be at its place in the media folder, which
        // mirrors its path in the staging directory.
        let stagingRoot = session.record.locations.stagingDirectory
        let staged = session.stagedFiles
        let paths = staged.map { path in
            pathKind(URL(fileURLWithPath: path)) == .file ? path : musicFolder.path + path.dropFirst(stagingRoot.count)
        }
        let stagedByPath = Dictionary(uniqueKeysWithValues: zip(paths.map(normalized), staged))
        let correspondence = try Correspondence.build(paths, catalog: catalog)
        guard correspondence.refused.isEmpty, correspondence.matchedFiles.count == paths.count else {
            throw CommandError.failure("the applied files no longer match the catalog; run 'ilibrary validate'")
        }
        var albums: [String: StagedAlbum] = [:]
        for (file, match) in correspondence.matchedFiles {
            let album = catalog.albums[match.reference.album]
            let label = RebuildPrepare.albumLabel(album)
            let track = catalog.resolve(match.reference)
            let folder = try AddCommand.albumFolder(
                artist: track.albumArtist ?? track.artist ?? "", album: track.album, in: musicFolder)
            albums[label, default: StagedAlbum(label: label, files: [], staged: [], destinations: [], tracks: [])]
                .files.append(file.url)
            albums[label]!.staged.append(stagedByPath[normalized(file.url.path)]!)
            albums[label]!.destinations.append(folder.appendingPathComponent(file.url.lastPathComponent))
            albums[label]!.tracks.append(track)
        }
        guard Set(albums.keys) == Set(session.record.additionList) else {
            throw CommandError.failure("the applied files do not form the albums recorded by rebuild prepare")
        }
        return session.record.additionList.map { albums[$0]! }
    }

    static func add(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        let parsed = try RebuildCommand.addSyntax.parse(arguments)
        var session = try RebuildSession(workspace: try RebuildCommand.workspace(parsed, "add"))
        let record = session.record
        if session.completed(.display) {
            console.print("The rebuild is already complete; nothing was changed.")
            return 0
        }
        if !session.completed(.addition) { try session.require(.addition, after: .application, command: "add") }
        let timestamps = parsed.flag("--timestamps")
        if timestamps, environment.setDates == nil {
            throw CommandError.failure(
                "--timestamps requires macOS, where creation dates can be set; nothing was changed")
        }
        let music = try requireMusic(environment)
        let albums = try stagedAlbums(session, console: console)
        let pending = session.ordered(record.additionList, .addAlbum)
        let added = Set(session.progress?.newPersistentIDs ?? [])
        let openLabel = session.progress?.openOperation.flatMap { $0.operation == .addAlbum ? $0.target : nil }
        let allowed = Set(
            (albums.first { $0.label == openLabel }?.destinations ?? []).map { normalized($0.path) })
        let snapshot = try music.librarySnapshot()
        let unexpected = snapshot.tracks.filter {
            !added.contains($0.persistentID.uppercased()) && !allowed.contains(normalized($0.location ?? ""))
        }
        guard unexpected.isEmpty, snapshot.trackCount == snapshot.fileTrackCount else {
            throw CommandError.failure(
                "the library holds \(unexpected.count) tracks that this rebuild did not add; nothing was added")
        }
        // A file is moved only from its staged place to a free destination. Only the album that an earlier run
        // was adding may already be in the media folder.
        for label in pending {
            let album = albums.first { $0.label == label }!
            for (staged, destination) in zip(album.staged, album.destinations) {
                let isStaged = pathKind(URL(fileURLWithPath: staged)) == .file
                let isPlaced = pathKind(destination) != .missing
                guard isStaged != isPlaced, isStaged || label == openLabel else {
                    throw CommandError.failure(
                        "\(destination.path) already exists in the media folder; nothing was added")
                }
            }
        }
        console.print("Workspace: \(session.workspace.path)")
        console.print(
            "Albums to add in the recorded order, each after the previous album's addition dates: \(pending.count)")
        for label in pending {
            let album = albums.first { $0.label == label }!
            console.print("  \(label): \(album.files.count) files")
            for (file, destination) in zip(album.files, album.destinations) {
                console.print("     move \(file.path) -> \(destination.path)")
            }
        }
        let datePlan =
            timestamps
            ? TimestampPlanner.plan(
                files: albums.flatMap { zip($0.destinations, $0.tracks).map { ($0, $1) } },
                catalog: try recordedCatalog(session, console: console),
                roots: [URL(fileURLWithPath: record.locations.mediaFolder).appendingPathComponent("Music")],
                timeZone: environment.timeZone)
            : nil
        let folderDates = datePlan.map { TimestampPlan(targets: $0.targets.filter { $0.kind != .file }) }
        if let folderDates {
            console.print("Folder dates after the addition: \(folderDates.targets.count) folders")
        }
        if parsed.flag("--dry-run") {
            console.print("Dry run: nothing was changed.")
            return 0
        }
        if !session.completed(.addition) {
            try session.begin(.addition)
            let dates = Dictionary(
                snapshot.dateAddedSeconds.map { ($0.key.uppercased(), $0.value) }, uniquingKeysWith: max)
            var separation = SeparatedAddition(latest: added.compactMap { dates[$0] }.max())
            for label in pending {
                let album = albums.first { $0.label == label }!
                var tracks: [LibraryTrack] = []
                separation.waitForNext(environment: environment)
                try session.perform(
                    .addAlbum, label,
                    action: {
                        for (staged, destination) in zip(album.staged, album.destinations)
                        where pathKind(URL(fileURLWithPath: staged)) == .file {
                            try AddCommand.moveFile(
                                URL(fileURLWithPath: staged), to: destination, environment: environment)
                        }
                    },
                    observe: {
                        tracks = try music.add(album.destinations)
                        let located = Set(tracks.compactMap(\.location).map(normalized))
                        let ids = tracks.map { $0.persistentID.uppercased() }
                        guard tracks.count == album.destinations.count, Set(ids).count == ids.count,
                            located == Set(album.destinations.map { normalized($0.path) })
                        else {
                            throw CommandError.failure(
                                "Music did not report one track per file of \"\(label)\" at its place; check it in Music"
                            )
                        }
                        guard try separation.confirm(tracks.map(\.persistentID), music: music) else {
                            throw CommandError.failure(
                                "\"\(label)\" was added, but its addition dates do not follow those of the album "
                                    + "before it, so Recently Added may not show the intended order. The rebuild "
                                    + "cannot continue; the library holds every album added so far, and the backup "
                                    + "remains the way back to the original state")
                        }
                        return JournalObservation(
                            newPersistentIDs: tracks.map(\.persistentID), laterThanPreviousAlbum: true)
                    })
                console.print("Added: \(label), \(tracks.count) tracks confirmed")
            }
            try session.complete(.addition)
        }
        if let folderDates {
            let dated = try TimestampPlanner.execute(folderDates, environment: environment)
            console.print("Dated: \(dated) folders in the media folder")
        }
        try session.begin(.display)
        try session.perform(
            .confirmDisplay, ProgressJournal.displayTarget, action: {},
            observe: { JournalObservation(observed: try additionDateOrder(albums, music: music)) })
        try session.complete(.display)
        console.print(
            "Rebuilt: \(albums.count) albums. Their addition dates, newest first, follow the expected Recently Added "
                + "order; the Music window was not inspected.")
        return 0
    }

    /// The album labels ordered by their latest addition date, newest first. Albums that share it are refused,
    /// because Music's order for them is unknown.
    static func additionDateOrder(_ albums: [StagedAlbum], music: any MusicLibrary) throws -> [String] {
        let snapshot = try music.librarySnapshot()
        var latest: [String: Int] = [:]
        for album in albums {
            let places = Set(album.destinations.map { normalized($0.path) })
            let dates = snapshot.tracks.filter { places.contains(normalized($0.location ?? "")) }.compactMap {
                snapshot.dateAddedSeconds[$0.persistentID]
            }
            guard dates.count == places.count, let newest = dates.max() else {
                throw CommandError.failure("the addition dates of \"\(album.label)\" cannot be read")
            }
            latest[album.label] = newest
        }
        guard Set(latest.values).count == latest.count else {
            throw CommandError.failure("two albums share their latest addition second; their order is unknown")
        }
        return latest.sorted { $0.value > $1.value }.map(\.key)
    }
}
