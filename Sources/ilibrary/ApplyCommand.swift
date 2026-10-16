import CatalogCore
import Foundation
import MP4Core

enum ApplyCommand {
    static let syntax = CommandSyntax(
        name: "apply",
        usage: """
            Usage: ilibrary apply CATALOG.json PATH... [--dry-run] [--rename] [--timestamps]

            Matches the .m4a files under the paths to the catalog and writes the catalog's values to their tags
            without re-encoding. Values that the catalog leaves empty are not changed. Every planned change is
            listed before anything is written, and every written file is read back and compared with the plan.
            Nothing is changed when a file is unmatched or refused, when artwork is missing, or when a renamed
            file would replace another.

            Options:
              --dry-run      list the planned changes and change nothing
              --rename       move each file to PATH/Album Artist/Album/NN Title.m4a (PATH must be a directory)
              --timestamps   afterwards, set file and folder dates to release dates at local midnight (macOS)
            """, flags: ["--dry-run", "--rename", "--timestamps"], positionals: 2...Int.max)

    struct PlannedValue {
        var label: String
        var key: MetadataKey
        var values: [MetadataValue]
    }

    struct FilePlan {
        var file: AudioFile
        var track: ResolvedTrack
        var values: [PlannedValue]
        var changes: [(value: PlannedValue, old: [MetadataValue])]
        var destination: URL?
    }

    /// The values the catalog defines for a track. Unknown values are omitted, so that they stay unchanged.
    static func plannedValues(_ track: ResolvedTrack, album: Album, artwork: MetadataValue?) -> [PlannedValue] {
        var values: [PlannedValue] = [PlannedValue(label: "title", key: .title, values: [.text(track.title)])]
        func add(_ label: String, _ key: MetadataKey, _ text: String?) {
            if let text, !text.isEmpty { values.append(PlannedValue(label: label, key: key, values: [.text(text)])) }
        }
        add("artist", .artist, track.artist)
        add("album artist", .albumArtist, track.albumArtist)
        add("album", .album, track.album)
        add("genre", .genre, track.genre)
        add("composer", .composer, track.composer)
        add("copyright", .copyright, track.copyright)
        add("release date", .releaseDate, track.releaseDate?.tagValue)
        values.append(
            PlannedValue(
                label: "track", key: .trackNumber,
                values: [.pair(number: track.reference.track, total: track.trackCount)]))
        values.append(
            PlannedValue(
                label: "disc", key: .discNumber, values: [.pair(number: track.reference.disc, total: track.discCount)]))
        if let compilation = album.compilation {
            values.append(
                PlannedValue(label: "compilation", key: .compilation, values: [.integer(compilation ? 1 : 0)]))
        }
        if let artwork { values.append(PlannedValue(label: "artwork", key: .artwork, values: [artwork])) }
        return values
    }

    static func run(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        let parsed = try syntax.parse(arguments)
        let dryRun = parsed.flag("--dry-run")
        let rename = parsed.flag("--rename")
        let timestamps = parsed.flag("--timestamps")
        let paths = Array(parsed.positionals.dropFirst())
        let roots = paths.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }.filter {
            pathKind($0) == .directory
        }
        if rename, roots.count != paths.count {
            throw CommandError.usage("apply: --rename requires every PATH to be a directory")
        }
        if timestamps, environment.setDates == nil {
            throw CommandError.failure(
                "--timestamps requires macOS, where creation dates can be set; nothing was changed")
        }
        let (catalog, directory) = try loadCatalog(parsed.positionals[0], console: console)
        let correspondence = try Correspondence.build(paths, catalog: catalog)
        guard correspondence.print(to: console, catalog: catalog) else {
            throw CommandError.failure("some files are unmatched or refused; nothing was changed")
        }

        var artwork: [Int: MetadataValue] = [:]
        for (index, album) in catalog.albums.enumerated() {
            if let path = album.artwork, !path.isEmpty {
                artwork[index] = try loadArtwork(path, catalogDirectory: directory)
            }
        }
        var plans: [FilePlan] = correspondence.matchedFiles.map { file, match in
            let track = catalog.resolve(match.reference)
            let values = plannedValues(
                track, album: catalog.albums[match.reference.album], artwork: artwork[match.reference.album])
            let changes = values.compactMap { value -> (PlannedValue, [MetadataValue])? in
                let old = file.file.metadataValues(value.key)
                return old == value.values ? nil : (value, old)
            }
            return FilePlan(
                file: file, track: track, values: values, changes: changes.map { ($0.0, $0.1) }, destination: nil)
        }
        plans.sort { $0.file.url.path < $1.file.url.path }
        if rename { try planMoves(&plans, roots: roots) }

        // Each rewrite needs room for one complete copy of the file beside it (decision 8).
        let largest = plans.filter { !$0.changes.isEmpty }.compactMap { plan -> Int? in
            (try? FileManager.default.attributesOfItem(atPath: plan.file.url.path)[.size] as? NSNumber)?.intValue
        }.max()
        if let largest, let first = plans.first(where: { !$0.changes.isEmpty }),
            let available = environment.availableCapacity(first.file.url.deletingLastPathComponent()),
            available < largest + (1 << 20)
        {
            throw CommandError.failure(
                "\(available) bytes are available, but rewriting needs \(largest + (1 << 20)); nothing was changed")
        }

        let finalFiles = plans.map { ($0.destination ?? $0.file.url, $0.track) }
        let datePlan =
            timestamps
            ? TimestampPlanner.plan(files: finalFiles, catalog: catalog, roots: roots, timeZone: environment.timeZone)
            : nil

        let root = roots.count == 1 ? roots[0] : nil
        func shown(_ url: URL) -> String { root.map { relativePath(url, from: $0) } ?? url.path }
        let changed = plans.filter { !$0.changes.isEmpty }
        console.print("Tag changes: \(changed.count) of \(plans.count) files")
        for plan in changed {
            console.print("  \(shown(plan.file.url))")
            for change in plan.changes {
                console.print("    \(change.value.label): \(describe(change.old)) -> \(describe(change.value.values))")
            }
        }
        let moves = plans.filter { $0.destination != nil && $0.destination != $0.file.url }
        if rename {
            console.print("Moves: \(moves.count) of \(plans.count) files")
            for plan in moves { console.print("  \(shown(plan.file.url)) -> \(shown(plan.destination!))") }
        }
        if let datePlan {
            console.print("Dates: \(datePlan.targets.count) paths")
            for target in datePlan.targets {
                console.print("  " + TimestampPlanner.describe(target, timeZone: environment.timeZone, root: root))
            }
            for note in datePlan.notes { console.print("  note: \(note)") }
        }
        if dryRun {
            console.print("Dry run: nothing was changed.")
            return 0
        }

        var written = 0
        for plan in changed {
            var file = plan.file.file
            for change in plan.changes { try file.setMetadata(change.value.key, change.value.values) }
            do {
                try MP4Writer.write(file, to: plan.file.url)
            } catch {
                throw CommandError.failure(
                    "\(plan.file.url.path): \(error) (\(written) files were written before this failure)")
            }
            let reread = try MP4File(contentsOf: plan.file.url)
            let mismatched = plan.values.filter { reread.metadataValues($0.key) != $0.values }.map(\.label)
            guard mismatched.isEmpty else {
                throw CommandError.failure(
                    "\(plan.file.url.path): \(mismatched.joined(separator: ", ")) did not read back as written")
            }
            written += 1
        }
        let moved = try executeMoves(moves, console: console, shown: shown)
        var dated = 0
        if let datePlan { dated = try TimestampPlanner.execute(datePlan, environment: environment) }
        console.print(
            "Applied: \(written) files rewritten and verified, \(moved) moved\(timestamps ? ", \(dated) paths dated" : "")"
        )
        return 0
    }

    /// Plans destinations under the directory argument that contains each file. Refuses collisions.
    static func planMoves(_ plans: inout [FilePlan], roots: [URL]) throws {
        var claimed: [String: String] = [:]
        for index in plans.indices {
            let source = plans[index].file.url
            guard let root = roots.filter({ isWithin(source, $0) }).max(by: { $0.path.count < $1.path.count }) else {
                throw CommandError.failure("\(source.path) is outside the given directories; nothing was changed")
            }
            guard let components = Naming.relativePath(for: plans[index].track) else {
                throw CommandError.failure(
                    "\"\(plans[index].track.album)\" has no album artist, which --rename requires; nothing was changed")
            }
            let destination = components.reduce(root) { $0.appendingPathComponent($1) }
            let key = destination.path.lowercased()
            if let other = claimed[key], other != source.path {
                throw CommandError.failure(
                    "\(other) and \(source.path) would both move to \(destination.path); nothing was changed")
            }
            claimed[key] = source.path
            if destination.path.lowercased() != source.path.lowercased(), pathKind(destination) != .missing {
                throw CommandError.failure(
                    "\(destination.path) already exists and is not replaced; nothing was changed")
            }
            plans[index].destination = destination
        }
    }

    static func executeMoves(_ moves: [FilePlan], console: Console, shown: (URL) -> String) throws -> Int {
        let manager = FileManager.default
        var moved = 0
        var vacated: Set<String> = []
        for plan in moves {
            let source = plan.file.url
            let destination = plan.destination!
            do {
                try manager.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if source.path.lowercased() == destination.path.lowercased() {
                    // A change of case only: move through a temporary name on case-insensitive volumes.
                    let temporary = source.deletingLastPathComponent().appendingPathComponent(
                        ".ilibrary-rename-\(UUID().uuidString)")
                    try manager.moveItem(at: source, to: temporary)
                    try manager.moveItem(at: temporary, to: destination)
                } else {
                    guard pathKind(destination) == .missing else {
                        throw CommandError.failure("\(destination.path) appeared during the move")
                    }
                    try manager.moveItem(at: source, to: destination)
                }
            } catch {
                throw CommandError.failure(
                    "moving \(source.path) failed: \(error) (\(moved) files were moved before this failure)")
            }
            guard pathKind(destination) == .file else {
                throw CommandError.failure("\(destination.path) is missing after the move")
            }
            moved += 1
            vacated.insert(source.deletingLastPathComponent().path)
        }
        for folder in vacated.sorted() {
            let remaining = (try? manager.contentsOfDirectory(atPath: folder))?.filter { $0 != ".DS_Store" } ?? []
            if remaining.isEmpty {
                console.print("  note: \(shown(URL(fileURLWithPath: folder))) is now empty; it was not removed")
            }
        }
        return moved
    }
}

enum TimestampsCommand {
    static let syntax = CommandSyntax(
        name: "timestamps",
        usage: """
            Usage: ilibrary timestamps CATALOG.json PATH... [--dry-run] [--script FILE]

            Sets the creation and modification dates of the matched .m4a files to their release dates at local
            midnight, then of album folders that hold one album, then of artist folders for which the catalog
            gives a folderDate. A missing path is reported and never created; symbolic links are refused. Each
            date is read back after it is set. Setting creation dates requires macOS.

            Options:
              --dry-run       list the planned dates and change nothing
              --script FILE   also write an equivalent shell script that uses SetFile and touch
            """, valued: ["--script": []], flags: ["--dry-run"], positionals: 2...Int.max)

    static func run(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        let parsed = try syntax.parse(arguments)
        let dryRun = parsed.flag("--dry-run")
        let paths = Array(parsed.positionals.dropFirst())
        let roots = paths.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }.filter {
            pathKind($0) == .directory
        }
        if !dryRun, environment.setDates == nil {
            throw CommandError.failure("setting creation dates is supported only on macOS; use --dry-run or --script")
        }
        let script = parsed.value("--script").map { URL(fileURLWithPath: $0).standardizedFileURL }
        if let script, pathKind(script) != .missing {
            throw CommandError.failure("\(script.path) already exists; it is not overwritten")
        }
        let (catalog, _) = try loadCatalog(parsed.positionals[0], console: console)
        let correspondence = try Correspondence.build(paths, catalog: catalog)
        guard correspondence.print(to: console, catalog: catalog) else {
            throw CommandError.failure("some files are unmatched or refused; nothing was changed")
        }
        let files = correspondence.matchedFiles.map { ($0.file.url, catalog.resolve($0.match.reference)) }
        let plan = TimestampPlanner.plan(files: files, catalog: catalog, roots: roots, timeZone: environment.timeZone)
        let root = roots.count == 1 ? roots[0] : nil
        console.print("Dates: \(plan.targets.count) paths")
        for target in plan.targets {
            console.print("  " + TimestampPlanner.describe(target, timeZone: environment.timeZone, root: root))
        }
        for note in plan.notes { console.print("  note: \(note)") }
        if let script {
            try TimestampPlanner.script(plan, timeZone: environment.timeZone).write(
                to: script, atomically: false, encoding: .utf8)
            console.print("Wrote the equivalent script \(script.path)")
        }
        if dryRun {
            console.print("Dry run: no date was changed.")
            return 0
        }
        let dated = try TimestampPlanner.execute(plan, environment: environment)
        console.print("Dated and verified: \(dated) paths")
        return 0
    }
}
