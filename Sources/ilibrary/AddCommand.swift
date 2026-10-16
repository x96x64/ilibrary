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
        guard pathKind(url) == .file else { return AddJournal() }
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
            title, and it never changes a track in Music. Progress is recorded in PATH/.ilibrary-add.json, so that
            an interrupted run resumes. Requires macOS and the Automation permission for Music.

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
        for root in roots where isWithin(root, mediaFolder) || isWithin(mediaFolder, root) {
            throw CommandError.usage("add: \(root.path) overlaps the media folder; use a staging folder outside it")
        }
        let journalURL = roots[0].appendingPathComponent(AddJournal.fileName)
        var journal = try AddJournal.load(journalURL)

        let scan = try LibraryFiles.scan(roots.map(\.path))
        guard scan.refused.isEmpty else {
            for refusal in scan.refused { console.print("  refused \(refusal.path): \(refusal.reason)") }
            throw CommandError.failure("some files are refused; nothing was changed")
        }
        let albums = try plan(try scan.files.map(LibraryFiles.read), musicFolder: musicFolder, order: order)
        let pending = journal.entries.filter { $0.state == .moving }

        console.print("Media folder: \(mediaFolder.path)")
        if !pending.isEmpty {
            console.print("Resuming \(pending.count) album(s) that were moved but not confirmed in Music")
        }
        console.print("Albums to add in \(order.rawValue) order: \(albums.count)")
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

        // Albums interrupted after their move are confirmed or added first.
        for index in journal.entries.indices where journal.entries[index].state == .moving {
            try resume(&journal.entries[index], music: music, console: console)
            try journal.save(journalURL)
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
            try move(album)
            try confirm(&entry, music: music)
            journal.entries[journal.entries.count - 1] = entry
            try journal.save(journalURL)
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
            let folder = musicFolder.appendingPathComponent(Naming.component(albums[index].albumArtist))
                .appendingPathComponent(Naming.component(albums[index].album))
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

    /// Moves an album's files to their destinations. A move across volumes is a copy followed by removal, which
    /// is verified by size before the source is removed.
    static func move(_ album: PlannedAlbum) throws {
        let manager = FileManager.default
        for (file, destination) in zip(album.files, album.destinations) {
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard pathKind(destination) == .missing else {
                throw CommandError.failure("\(destination.path) appeared before the move; the album was not added")
            }
            do {
                try manager.moveItem(at: file.url, to: destination)
            } catch {
                throw CommandError.failure("moving \(file.url.path) failed: \(error); the album was not added")
            }
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

    /// Completes an album that was being moved when an earlier run stopped.
    static func resume(_ entry: inout AddJournal.Entry, music: any MusicLibrary, console: Console) throws {
        let manager = FileManager.default
        for (source, destination) in zip(entry.sources, entry.destinations) {
            switch (pathKind(URL(fileURLWithPath: source)), pathKind(URL(fileURLWithPath: destination))) {
            case (.missing, .file): continue
            case (.file, .missing):
                try manager.createDirectory(
                    at: URL(fileURLWithPath: destination).deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try manager.moveItem(at: URL(fileURLWithPath: source), to: URL(fileURLWithPath: destination))
            default:
                throw CommandError.failure(
                    "\"\(entry.album)\" cannot be resumed: \(source) and \(destination) are not in the expected state")
            }
        }
        // If an earlier run added the album but stopped before recording it, its tracks are already present.
        let expected = Set(entry.destinations.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let present = try music.tracks(album: entry.album).filter {
            $0.location.map { expected.contains(URL(fileURLWithPath: $0).standardizedFileURL.path) } ?? false
        }
        if present.count == entry.destinations.count {
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
