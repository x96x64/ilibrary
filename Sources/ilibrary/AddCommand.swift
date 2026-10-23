import CatalogCore
import Foundation
import MP4Core

/// The record of an `add` run, kept in the first staging folder so that an interrupted run can resume.
struct AddJournal: Codable, Equatable {
    static let fileName = ".ilibrary-add.json"
    static let formatIdentifier = "ilibrary-add-journal-1"

    struct Entry: Codable, Equatable {
        enum State: String, Codable {
            /// The files are being moved into the media folder or have been, but are not yet confirmed in Music.
            case moving
            /// Music returned one track per file, at the destination of each file.
            case added
        }

        var album: String
        var albumArtist: String
        var sources: [String]
        var destinations: [String]
        var state: State
        var persistentIDs: [String] = []
    }

    var format = AddJournal.formatIdentifier
    var entries: [Entry] = []

    static func load(_ url: URL) throws -> AddJournal {
        if pathKind(url) == .missing { return AddJournal() }
        guard pathKind(url) == .file else {
            throw CommandError.failure("the add journal is not a regular file; nothing was changed")
        }
        let journal = try JSONDecoder().decode(AddJournal.self, from: Data(contentsOf: url))
        guard journal.format == formatIdentifier else {
            throw CommandError.failure("\(url.path) is not a journal of this version")
        }
        return journal
    }

    func save(_ url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

enum AddCommand {
    static let syntax = CommandSyntax(
        name: "add",
        usage: """
            Usage: ilibrary add PATH... [--order release|artist|artist-desc|artist-release] [--dry-run]

            Adds the albums under the staging folders to Music, one album at a time. Each album is moved to its
            organized folder inside the Music media folder, Album Artist/Album, and added there in place; Music
            must then report one track per file at the place of each file before the next album begins. The run
            stops before an album when the library already holds a track of the same album artist, album, and
            title, and it never changes a track in Music. Each album is added only after the clock has passed the
            latest addition second of the album before it, and the run stops when Music reports an addition date
            that does not follow it, so that Recently Added shows the albums in the reverse of the order of addition.
            Progress is recorded in PATH/.ilibrary-add.json, so that an interrupted run resumes. Requires macOS and
            the Automation permission for Music.

            Options:
              --order ORDER   release (default), artist, artist-desc, or artist-release
              --dry-run       list the order, the moves, and the checks, and change nothing
            """, valued: ["--order": []], flags: ["--dry-run"], positionals: 1...Int.max)

    struct PlannedAlbum {
        var album: String
        var albumArtist: String
        var releaseDate: ReleaseDate?
        var files: [AudioFile]
        var destinations: [URL]
    }

    static func run(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        let parsed = try syntax.parse(arguments)
        guard let order = AlbumOrder(rawValue: parsed.value("--order") ?? "release") else {
            throw CommandError.usage("add: --order must be release, artist, artist-desc, or artist-release")
        }
        guard let music = environment.music else {
            throw CommandError.failure("adding to Music requires macOS; nothing was changed")
        }
        let roots = parsed.positionals.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
        for root in roots where pathKind(root) != .directory {
            throw CommandError.usage("add: \(root.path) is not a directory")
        }
        guard let mediaFolder = music.mediaFolder()?.standardizedFileURL, pathKind(mediaFolder) == .directory else {
            throw CommandError.failure(
                "Music's media folder is unknown or missing; open Music once and run 'ilibrary doctor'. Nothing was changed"
            )
        }
        let musicFolder = mediaFolder.appendingPathComponent("Music", isDirectory: true)
        guard [.missing, .directory].contains(pathKind(musicFolder)) else {
            throw CommandError.failure("the Music folder is not a regular directory; nothing was changed")
        }
        for root in roots where isWithin(root, mediaFolder) || isWithin(mediaFolder, root) {
            throw CommandError.usage("add: \(root.path) overlaps the media folder; use a staging folder outside it")
        }
        let journalURL = roots[0].appendingPathComponent(AddJournal.fileName)
        var journal = try AddJournal.load(journalURL)

        try validateJournal(journal, roots: roots, musicFolder: musicFolder)
        let pending = journal.entries.filter { $0.state == .moving }
        let pendingSources = Set(pending.flatMap(\.sources))
        let scan = try LibraryFiles.scan(roots.map(\.path))
        guard scan.refused.isEmpty else {
            for refusal in scan.refused { console.print("  refused \(refusal.path): \(refusal.reason)") }
            throw CommandError.failure("some files are refused; nothing was changed")
        }
        let albums = try plan(
            try scan.files.filter { !pendingSources.contains($0.path) }.map(LibraryFiles.read),
            musicFolder: musicFolder, order: order)
        let remainingMoves =
            pending.flatMap { entry in
                zip(entry.sources, entry.destinations).compactMap { source, destination -> (URL, URL)? in
                    let sourceURL = URL(fileURLWithPath: source)
                    return pathKind(sourceURL) == .file ? (sourceURL, URL(fileURLWithPath: destination)) : nil
                }
            } + albums.flatMap { Array(zip($0.files.map(\.url), $0.destinations)) }
        try checkMoveCapacity(remainingMoves, mediaFolder: mediaFolder, environment: environment)

        console.print("Media folder: \(mediaFolder.path)")
        if !pending.isEmpty {
            console.print("Resuming \(pending.count) album(s) that were moved but not confirmed in Music")
        }
        for entry in pending {
            console.print("  resume: \(entry.albumArtist) - \(entry.album)")
            for (source, destination) in zip(entry.sources, entry.destinations) {
                console.print(
                    "     confirm or move \(source) -> \(relativePath(URL(fileURLWithPath: destination), from: mediaFolder))"
                )
            }
        }
        console.print(
            "Albums to add in \(order.rawValue) order: \(albums.count), each after the previous album's addition dates")
        for (index, album) in albums.enumerated() {
            let date = album.releaseDate.map { " (\($0))" } ?? ""
            console.print("  \(index + 1). \(album.albumArtist) - \(album.album)\(date): \(album.files.count) files")
            for (file, destination) in zip(album.files, album.destinations) {
                console.print(
                    "     move \(file.url.lastPathComponent) -> \(relativePath(destination, from: mediaFolder))")
                let tags = file.tags
                if let title = tags.title, let track = tags.trackNumber {
                    let organized = Naming.fileName(
                        title: title, disc: tags.discNumber ?? 1, track: track,
                        discCount: Set(album.files.map { $0.tags.discNumber ?? 1 }).count)
                    if organized != file.url.lastPathComponent {
                        console.print(
                            "       note: Music may rename it to \(organized); run 'ilibrary apply --rename' first")
                    }
                }
            }
        }
        if parsed.flag("--dry-run") {
            for album in albums {
                if let match = try existingMatch(album, music: music) {
                    console.print("  stop expected: the library already holds \"\(match.name)\" of \"\(album.album)\"")
                }
            }
            console.print("Dry run: nothing was changed.")
            return 0
        }

        // Albums interrupted after their move are confirmed or added first, each after the album before it.
        for index in journal.entries.indices where journal.entries[index].state == .moving {
            var separation = SeparatedAddition()
            if let previous = journal.entries[..<index].last(where: { $0.state == .added }) {
                separation.follow(previous.persistentIDs, music: music)
            }
            separation.waitForNext(environment: environment)
            try resume(&journal.entries[index], music: music, console: console, environment: environment)
            try journal.save(journalURL)
            try requireLater(journal.entries[index], &separation, music: music)
        }
        var separation = SeparatedAddition()
        if let last = journal.entries.last(where: { $0.state == .added }) {
            separation.follow(last.persistentIDs, music: music)
        }
        var added = 0
        for album in albums {
            if let match = try existingMatch(album, music: music) {
                throw CommandError.failure(
                    "the library already holds \"\(match.name)\" of \"\(album.album)\" by \(album.albumArtist); "
                        + "\(added) album(s) were added before this stop. Remove the album from the staging folder to continue"
                )
            }
            var entry = AddJournal.Entry(
                album: album.album, albumArtist: album.albumArtist, sources: album.files.map(\.url.path),
                destinations: album.destinations.map(\.path), state: .moving)
            journal.entries.append(entry)
            try journal.save(journalURL)
            separation.waitForNext(environment: environment)
            try move(album, environment: environment)
            try confirm(&entry, music: music)
            journal.entries[journal.entries.count - 1] = entry
            try journal.save(journalURL)
            try requireLater(entry, &separation, music: music)
            added += 1
            console.print(
                "Added \(added) of \(albums.count): \(album.albumArtist) - \(album.album), \(album.files.count) tracks confirmed"
            )
        }
        console.print("Added and confirmed: \(added) album(s)")
        return 0
    }

    /// Groups files into albums and orders them. Every album needs an album and album artist tag, and every
    /// destination must be free; otherwise nothing is planned.
    static func plan(_ files: [AudioFile], musicFolder: URL, order: AlbumOrder) throws -> [PlannedAlbum] {
        var groups: [String: PlannedAlbum] = [:]
        var keys: [String] = []
        for file in files {
            guard let album = file.tags.album else {
                throw CommandError.failure("\(file.url.path) has no album tag; nothing was changed")
            }
            guard let artist = file.tags.albumArtist ?? LibraryFiles.text(file.file, .artist) else {
                throw CommandError.failure("\(file.url.path) has no album artist; nothing was changed")
            }
            guard file.tags.title != nil else {
                throw CommandError.failure("\(file.url.path) has no title for duplicate detection; nothing was changed")
            }
            let key = TitleRules.comparisonKey(artist) + "\u{0}" + TitleRules.comparisonKey(album)
            if groups[key] == nil {
                keys.append(key)
                groups[key] = PlannedAlbum(
                    album: album, albumArtist: artist,
                    releaseDate: LibraryFiles.text(file.file, .releaseDate).flatMap { ReleaseDate(tagValue: $0) },
                    files: [],
                    destinations: [])
            }
            groups[key]!.files.append(file)
        }
        var albums = keys.map { groups[$0]! }
        for index in albums.indices {
            albums[index].files.sort {
                ($0.tags.discNumber ?? 1, $0.tags.trackNumber ?? 0, $0.url.path)
                    < ($1.tags.discNumber ?? 1, $1.tags.trackNumber ?? 0, $1.url.path)
            }
            let folder = try albumFolder(artist: albums[index].albumArtist, album: albums[index].album, in: musicFolder)
            albums[index].destinations = albums[index].files.map {
                folder.appendingPathComponent($0.url.lastPathComponent)
            }
        }
        var claimed: Set<String> = []
        for album in albums {
            for (file, destination) in zip(album.files, album.destinations) {
                guard claimed.insert(destination.path.lowercased()).inserted else {
                    throw CommandError.failure("two files would be moved to \(destination.path); nothing was changed")
                }
                guard pathKind(destination) == .missing else {
                    throw CommandError.failure(
                        "\(destination.path) already exists in the media folder; nothing was changed")
                }
                if let blocked = ImportCommand.blockedAncestor(of: destination, below: musicFolder) {
                    throw CommandError.failure(
                        "\(blocked.path) is not a folder that can hold \(file.url.lastPathComponent); nothing was changed"
                    )
                }
            }
        }
        let catalog = Catalog(
            albums: albums.map {
                Album(album: $0.album, albumArtist: $0.albumArtist, releaseDate: $0.releaseDate?.description, discs: [])
            })
        return catalog.albumOrder(order).map { albums[$0] }
    }

    /// A track of the library with the album's album artist, album, and one of its titles, if any.
    static func existingMatch(_ album: PlannedAlbum, music: any MusicLibrary) throws -> LibraryTrack? {
        let titles = Set(album.files.compactMap { $0.tags.title }.map(TitleRules.comparisonKey))
        let artist = TitleRules.comparisonKey(album.albumArtist)
        return try music.tracks(album: album.album).first { track in
            let trackArtist = TitleRules.comparisonKey(track.albumArtist.isEmpty ? track.artist : track.albumArtist)
            return trackArtist == artist && titles.contains(TitleRules.comparisonKey(track.name))
        }
    }

    static func albumFolder(artist: String, album: String, in musicFolder: URL) throws -> URL {
        let components = [Naming.component(artist), Naming.component(album)]
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }) else {
            throw CommandError.failure("the album artist or album cannot be used as a folder name; nothing was changed")
        }
        let folder = components.reduce(musicFolder) { $0.appendingPathComponent($1) }.standardizedFileURL
        guard isWithin(folder, musicFolder) else {
            throw CommandError.failure("the album would leave the Music folder; nothing was changed")
        }
        return folder
    }

    /// A journal is user-editable: validate every path before it can authorize a move or library operation.
    static func validateJournal(_ journal: AddJournal, roots: [URL], musicFolder: URL) throws {
        var sources: Set<String> = []
        var destinations: Set<String> = []
        for entry in journal.entries {
            let folder = try albumFolder(artist: entry.albumArtist, album: entry.album, in: musicFolder)
            guard !entry.sources.isEmpty, entry.sources.count == entry.destinations.count else {
                throw CommandError.failure("the add journal has inconsistent file lists; nothing was changed")
            }
            for (source, destination) in zip(entry.sources, entry.destinations) {
                let src = URL(fileURLWithPath: source).standardizedFileURL
                let dst = URL(fileURLWithPath: destination).standardizedFileURL
                guard source == src.path, destination == dst.path,
                    roots.contains(where: { isWithin(src, $0) && src != $0 }),
                    dst == folder.appendingPathComponent(src.lastPathComponent),
                    sources.insert(source).inserted, destinations.insert(destination.lowercased()).inserted,
                    ImportCommand.blockedAncestor(of: dst, below: musicFolder) == nil,
                    roots.allSatisfy({ !isWithin(src, $0) || ImportCommand.blockedAncestor(of: src, below: $0) == nil })
                else {
                    throw CommandError.failure(
                        "the add journal contains an unsafe or repeated path; nothing was changed")
                }
            }
        }
    }

    static func checkMoveCapacity(_ moves: [(URL, URL)], mediaFolder: URL, environment: Environment) throws {
        guard let targetVolume = environment.volumeIdentifier(mediaFolder) else {
            throw CommandError.failure("the media volume cannot be determined; nothing was changed")
        }
        var bytes = 0
        for (source, _) in moves {
            guard let sourceVolume = environment.volumeIdentifier(source) else {
                throw CommandError.failure("the source volume cannot be determined; nothing was changed")
            }
            if sourceVolume != targetVolume {
                guard environment.verifyAudioCopy != nil else {
                    throw CommandError.failure(
                        "verified cross-volume moves are unavailable; use staging on the media volume")
                }
                let size =
                    (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.intValue ?? 0
                let sum = bytes.addingReportingOverflow(size)
                guard !sum.overflow else { throw CommandError.failure("the move size is too large") }
                bytes = sum.partialValue
            }
        }
        if bytes > 0 {
            guard let available = environment.availableCapacity(mediaFolder), available > bytes,
                available - bytes >= 1 << 20
            else { throw CommandError.failure("insufficient or unknown free space for the moves; nothing was changed") }
        }
    }

    static func move(_ album: PlannedAlbum, environment: Environment) throws {
        for (file, destination) in zip(album.files, album.destinations) {
            try moveFile(file.url, to: destination, environment: environment)
        }
    }

    /// Same-volume moves rename the existing file. A cross-volume move verifies an explicit copy before
    /// removing the selected source. A failed verification leaves the source in place.
    static func moveFile(_ source: URL, to destination: URL, environment: Environment) throws {
        let manager = FileManager.default
        guard pathKind(source) == .file, pathKind(destination) == .missing else {
            throw CommandError.failure("the source or destination changed before the move; the album was not added")
        }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let sourceVolume = environment.volumeIdentifier(source),
            let targetVolume = environment.volumeIdentifier(destination.deletingLastPathComponent())
        else { throw CommandError.failure("the volume cannot be determined before moving the file") }
        if sourceVolume == targetVolume {
            try manager.moveItem(at: source, to: destination)
            guard pathKind(source) == .missing, pathKind(destination) == .file else {
                throw CommandError.failure("the moved file could not be confirmed")
            }
        } else {
            guard let verify = environment.verifyAudioCopy else {
                throw CommandError.failure("verified cross-volume moves are unavailable")
            }
            let partial = destination.deletingLastPathComponent().appendingPathComponent(
                ".ilibrary-move-\(UUID().uuidString).m4a")
            defer { try? manager.removeItem(at: partial) }
            try manager.copyItem(at: source, to: partial)
            guard manager.contentsEqual(atPath: source.path, andPath: partial.path) else {
                throw CommandError.failure("the copied file differs; the original was retained")
            }
            try verify(source, partial)
            try manager.moveItem(at: partial, to: destination)
            guard manager.contentsEqual(atPath: source.path, andPath: destination.path) else {
                throw CommandError.failure("the destination differs; the original was retained")
            }
            try manager.removeItem(at: source)
        }
    }

    /// Adds the moved files and confirms one new track per file at each file's destination (Music Behavior, M2).
    static func confirm(_ entry: inout AddJournal.Entry, music: any MusicLibrary) throws {
        let destinations = entry.destinations.map { URL(fileURLWithPath: $0) }
        let tracks: [LibraryTrack]
        do {
            tracks = try music.add(destinations)
        } catch {
            throw CommandError.failure(
                "Music did not add \"\(entry.album)\": \(error). Its files are in the media folder; run add again to resume"
            )
        }
        let expected = Set(entry.destinations.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let located = Set(tracks.compactMap { $0.location.map { URL(fileURLWithPath: $0).standardizedFileURL.path } })
        guard tracks.count == destinations.count, Set(tracks.map(\.persistentID)).count == tracks.count,
            located == expected
        else {
            throw CommandError.failure(
                "Music reported \(tracks.count) track(s) for the \(destinations.count) files of \"\(entry.album)\", or "
                    + "tracks at other places; the album is not confirmed. Check it in Music before running add again")
        }
        entry.persistentIDs = tracks.map(\.persistentID)
        entry.state = .added
    }

    /// Stops the run when an album's addition dates do not follow those of the album before it.
    static func requireLater(_ entry: AddJournal.Entry, _ separation: inout SeparatedAddition, music: any MusicLibrary)
        throws
    {
        guard try separation.confirm(entry.persistentIDs, music: music) else {
            throw CommandError.failure(
                "\"\(entry.album)\" was added, but its addition dates do not follow those of the album before it, so "
                    + "Recently Added may not show the intended order; the run stopped")
        }
    }

    /// Completes an album that was being moved when an earlier run stopped.
    static func resume(
        _ entry: inout AddJournal.Entry, music: any MusicLibrary, console: Console, environment: Environment
    ) throws {
        // Read the still-present source or its destination, and check for a matching track elsewhere before moving.
        let files = try zip(entry.sources, entry.destinations).map { source, destination in
            try LibraryFiles.read(
                URL(fileURLWithPath: pathKind(URL(fileURLWithPath: source)) == .file ? source : destination))
        }
        let titles = Set(files.compactMap(\.tags.title).map(TitleRules.comparisonKey))
        let expected = Set(entry.destinations)
        let known = try music.tracks(album: entry.album)
        if known.contains(where: { track in
            let artist = track.albumArtist.isEmpty ? track.artist : track.albumArtist
            return TitleRules.comparisonKey(artist) == TitleRules.comparisonKey(entry.albumArtist)
                && titles.contains(TitleRules.comparisonKey(track.name))
                && !(track.location.map { expected.contains(URL(fileURLWithPath: $0).standardizedFileURL.path) }
                    ?? false)
        }) {
            throw CommandError.failure(
                "the library already holds a matching track elsewhere; resumption changed nothing")
        }
        for (source, destination) in zip(entry.sources, entry.destinations) {
            switch (pathKind(URL(fileURLWithPath: source)), pathKind(URL(fileURLWithPath: destination))) {
            case (.missing, .file): continue
            case (.file, .missing):
                try moveFile(
                    URL(fileURLWithPath: source), to: URL(fileURLWithPath: destination), environment: environment)
            default:
                throw CommandError.failure(
                    "\"\(entry.album)\" cannot be resumed: \(source) and \(destination) are not in the expected state")
            }
        }
        // If an earlier run added the album but stopped before recording it, its tracks are already present.
        let present = known.filter {
            $0.location.map { expected.contains(URL(fileURLWithPath: $0).standardizedFileURL.path) } ?? false
        }
        if present.count == entry.destinations.count,
            Set(present.map(\.persistentID)).count == present.count,
            Set(present.compactMap { $0.location.map { URL(fileURLWithPath: $0).standardizedFileURL.path } })
                == expected
        {
            entry.persistentIDs = present.map(\.persistentID)
            entry.state = .added
        } else if present.isEmpty {
            try confirm(&entry, music: music)
        } else {
            throw CommandError.failure(
                "\"\(entry.album)\" is partly in the library; check it in Music before running add again")
        }
        console.print("Resumed: \(entry.albumArtist) - \(entry.album), \(entry.destinations.count) tracks confirmed")
    }
}
