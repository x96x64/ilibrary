import CatalogCore
import Foundation
import MP4Core

enum ExportCommand {
    static let syntax = CommandSyntax(
        name: "export",
        usage: """
            Usage: ilibrary export PATH... -o CATALOG.json [--artwork DIR]

            Writes a draft catalog from the tags of the .m4a files under the paths, grouped into albums and
            discs by their album, album artist, disc, and track tags. Values shared by every track of an album
            are written at album level. Artwork is excluded unless --artwork DIR is given; covers are then
            written to DIR in their embedded JPEG or PNG format and referenced by the catalog. Existing files
            are never overwritten.

            Options:
              -o, --output FILE   the catalog to write (required)
              --artwork DIR       write album covers to DIR
            """, valued: ["--output": ["-o"], "--artwork": []], positionals: 1...Int.max)

    struct Entry {
        var file: AudioFile
        var disc: Int
        var track: Int
    }

    static func run(_ arguments: [String], console: Console) throws -> Int32 {
        let parsed = try syntax.parse(arguments)
        guard let outputPath = parsed.value("--output") else {
            throw CommandError.usage("export: -o CATALOG.json is required")
        }
        let output = URL(fileURLWithPath: outputPath).standardizedFileURL
        guard pathKind(output) == .missing else {
            throw CommandError.failure("\(outputPath) already exists; it is not overwritten")
        }
        let artworkDirectory = parsed.value("--artwork").map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }

        let scan = try LibraryFiles.scan(parsed.positionals)
        for refusal in scan.refused { console.warning("\(refusal.path): \(refusal.reason); not exported") }
        let files = try scan.files.map(LibraryFiles.read)
        let (catalog, covers, warnings) = draft(
            files, catalogDirectory: output.deletingLastPathComponent(), artworkDirectory: artworkDirectory)
        for warning in warnings { console.warning(warning) }

        // Every destination is checked before anything is written.
        if let artworkDirectory, pathKind(artworkDirectory) != .missing, pathKind(artworkDirectory) != .directory {
            throw CommandError.failure("\(artworkDirectory.path) exists and is not a directory")
        }
        for cover in covers where pathKind(cover.url) != .missing {
            throw CommandError.failure("\(cover.url.path) already exists; it is not overwritten")
        }
        if let artworkDirectory, !covers.isEmpty {
            try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        }
        for cover in covers { try cover.data.write(to: cover.url, options: .withoutOverwriting) }
        try catalog.encoded().write(to: output, options: .withoutOverwriting)

        // Verify by reading the catalog back.
        let reread = Catalog.validate(try Data(contentsOf: output))
        guard reread.catalog == catalog else {
            throw CommandError.failure("\(outputPath) did not read back as written")
        }
        let trackCount = catalog.resolvedTracks().count
        console.print(
            "Exported \(catalog.albums.count) albums and \(trackCount) tracks from \(files.count) files to \(outputPath)"
        )
        for cover in covers { console.print("  wrote cover \(cover.url.path)") }
        return 0
    }

    struct Cover {
        var url: URL
        var data: Data
    }

    /// Groups files into a catalog. Returns the covers to write and warnings about values that a catalog
    /// cannot represent, such as gaps in track numbers.
    static func draft(_ files: [AudioFile], catalogDirectory: URL, artworkDirectory: URL?)
        -> (Catalog, [Cover], [String])
    {
        var warnings: [String] = []
        var order: [String] = []
        var groups: [String: [Entry]] = [:]
        for file in files {
            guard let album = file.tags.album else {
                warnings.append("\(file.url.path) has no album tag; not exported")
                continue
            }
            guard let track = file.tags.trackNumber else {
                warnings.append("\(file.url.path) has no track number; not exported")
                continue
            }
            let key = TitleRules.comparisonKey(album) + "\u{0}" + TitleRules.comparisonKey(file.tags.albumArtist ?? "")
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(Entry(file: file, disc: file.tags.discNumber ?? 1, track: track))
        }
        var albums: [Album] = []
        var covers: [Cover] = []
        var coverNames: Set<String> = []
        for key in order {
            var entries = groups[key]!.sorted {
                ($0.disc, $0.track, $0.file.url.path) < ($1.disc, $1.track, $1.file.url.path)
            }
            let name = entries[0].file.tags.album!
            var seen: Set<[Int]> = []
            entries = entries.filter { entry in
                guard seen.insert([entry.disc, entry.track]).inserted else {
                    warnings.append(
                        "\(entry.file.url.path) repeats disc \(entry.disc) track \(entry.track) of \"\(name)\"; not exported"
                    )
                    return false
                }
                return true
            }
            let discNumbers = Array(Set(entries.map(\.disc))).sorted()
            if discNumbers != Array(1...discNumbers.count) {
                warnings.append(
                    "\"\(name)\" has disc numbers \(discNumbers); the catalog numbers its discs consecutively")
            }
            var discs: [Disc] = []
            for number in discNumbers {
                let discEntries = entries.filter { $0.disc == number }
                if discEntries.map(\.track) != Array(1...discEntries.count) {
                    warnings.append(
                        "\"\(name)\" disc \(number) has track numbers \(discEntries.map(\.track)); the catalog numbers its tracks consecutively"
                    )
                }
                discs.append(Disc(tracks: discEntries.map { track(for: $0.file) }))
            }
            var album = Album(album: name, discs: discs)
            hoist(&album, entries: entries.map(\.file), warnings: &warnings)
            if let artworkDirectory, let cover = cover(entries.map(\.file), album: album, warnings: &warnings) {
                var base = Naming.component(
                    [album.albumArtist, album.album].compactMap { $0 }.joined(separator: " - "))
                if base.hasPrefix(".") { base = "_" + base.dropFirst() }
                var fileName = "\(base).\(cover.format == .png ? "png" : "jpg")"
                var counter = 2
                while coverNames.contains(fileName.lowercased()) {
                    fileName = "\(base) \(counter).\(cover.format == .png ? "png" : "jpg")"
                    counter += 1
                }
                coverNames.insert(fileName.lowercased())
                let url = artworkDirectory.appendingPathComponent(fileName)
                covers.append(Cover(url: url, data: cover.data))
                album.artwork = relativePath(url, from: catalogDirectory)
            }
            albums.append(album)
        }
        return (Catalog(albums: albums), covers, warnings)
    }

    static func track(for file: AudioFile) -> Track {
        let title = file.tags.title ?? file.url.deletingPathExtension().lastPathComponent
        return Track(
            title: title, artist: LibraryFiles.text(file.file, .artist),
            composer: LibraryFiles.text(file.file, .composer),
            genre: LibraryFiles.text(file.file, .genre), copyright: LibraryFiles.text(file.file, .copyright),
            releaseDate: LibraryFiles.text(file.file, .releaseDate).flatMap { ReleaseDate(tagValue: $0) }?.description)
    }

    /// Moves values that every track shares to the album, and sets the album artist and compilation flag.
    static func hoist(_ album: inout Album, entries: [AudioFile], warnings: inout [String]) {
        let fields: [WritableKeyPath<Track, String?>] = [\.artist, \.composer, \.genre, \.copyright, \.releaseDate]
        let albumFields: [WritableKeyPath<Album, String?>] = [
            \.artist, \.composer, \.genre, \.copyright, \.releaseDate,
        ]
        for (trackField, albumField) in zip(fields, albumFields) {
            let values = album.discs.flatMap(\.tracks).map { $0[keyPath: trackField] }
            guard let first = values.first, let shared = first, values.allSatisfy({ $0 == shared }) else { continue }
            album[keyPath: albumField] = shared
            for disc in album.discs.indices {
                for track in album.discs[disc].tracks.indices {
                    album.discs[disc].tracks[track][keyPath: trackField] = nil
                }
            }
        }
        let artists = entries.compactMap { LibraryFiles.text($0.file, .albumArtist) }
        if let first = artists.first {
            album.albumArtist = first
            if Set(artists).count > 1 {
                warnings.append("\"\(album.album)\" has several album artists; \"\(first)\" is used")
            }
        }
        let flags = entries.map { file -> Int64? in
            for case .integer(let value) in file.file.metadataValues(.compilation) { return value }
            return nil
        }
        if flags.allSatisfy({ $0 == 1 }) {
            album.compilation = true
        } else if flags.allSatisfy({ $0 == 0 }) {
            album.compilation = false
        } else if flags.contains(where: { $0 != nil }) {
            warnings.append("\"\(album.album)\" has a compilation flag on some tracks only; it is not exported")
        }
    }

    static func cover(_ files: [AudioFile], album: Album, warnings: inout [String]) -> (
        data: Data, format: ImageFormat
    )? {
        let images = files.map { file -> (Data, ImageFormat)? in
            for case .image(let data, let format) in file.file.metadataValues(.artwork) { return (data, format) }
            return nil
        }
        guard let first = images.compactMap({ $0 }).first else { return nil }
        if images.contains(where: { $0?.0 != first.0 }) {
            warnings.append(
                "the tracks of \"\(album.album)\" carry different or missing covers; the first cover is exported")
        }
        return first
    }
}
