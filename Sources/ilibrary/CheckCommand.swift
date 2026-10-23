import CatalogCore
import Foundation
import MP4Core

enum CheckCommand {
    static let syntax = CommandSyntax(
        name: "check",
        usage: """
            Usage: ilibrary check [PATH...] [--library]

            Reports problems of the .m4a files under the paths: missing album, album artist, title, or track tags,
            files that share a disc and track number or a title within an album, and file dates that differ from
            the release date at local midnight. With --library, also compares the files with the Music library:
            files that are not in the library or are in it more than once, library tracks of the same albums
            whose files are missing, every field whose value differs between a file and its track, and cloud
            statuses such as matched or subscription. It reads the library and changes nothing. Exit status is 0
            when nothing is found, and 1 otherwise.

            Options:
              --library   compare the files with the Music library (macOS)
            """, flags: ["--library"], positionals: 0...Int.max)

    /// Cloud statuses that mean that Music identified a track with its catalog or does not hold it locally.
    static let notableCloudStatuses: Set<String> = [
        "matched", "subscription", "purchased", "removed", "error", "duplicate", "ineligible", "no longer available",
        "prerelease",
    ]

    struct Finding: Comparable {
        var path: String
        var message: String

        static func < (lhs: Finding, rhs: Finding) -> Bool { (lhs.path, lhs.message) < (rhs.path, rhs.message) }
    }

    static func run(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        let parsed = try syntax.parse(arguments)
        let compareLibrary = parsed.flag("--library")
        var music: (any MusicLibrary)?
        if compareLibrary {
            guard let available = environment.music else {
                throw CommandError.failure("comparing with the Music library requires macOS")
            }
            music = available
        }
        guard !parsed.positionals.isEmpty || compareLibrary else {
            throw CommandError.usage("check requires a path or --library")
        }
        let tracks = try music?.allTracks() ?? []
        let locations = Set(tracks.compactMap(\.location))
        let supportedLocations = locations.filter {
            ["m4a", "m4p"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
        }
        let paths = parsed.positionals.isEmpty ? supportedLocations.sorted() : parsed.positionals
        var findings: [Finding] = []
        var selected: Set<URL> = []
        for path in paths {
            do {
                let scan = try LibraryFiles.scan([path])
                selected.formUnion(scan.files)
                findings += scan.refused.map { Finding(path: $0.path, message: $0.reason) }
            } catch {
                findings.append(Finding(path: path, message: "cannot scan: \(error)"))
            }
        }
        var files: [AudioFile] = []
        for url in selected.sorted(by: { $0.path < $1.path }) {
            do { files.append(try LibraryFiles.read(url)) } catch {
                findings.append(Finding(path: url.path, message: "cannot read audio metadata: \(error)"))
            }
        }
        findings += fileFindings(files, environment: environment)
        if compareLibrary {
            findings += libraryFindings(
                files, tracks: tracks,
                roots: parsed.positionals.map { URL(fileURLWithPath: $0).standardizedFileURL },
                entireLibrary: parsed.positionals.isEmpty)
        }
        if files.isEmpty && !parsed.positionals.isEmpty && findings.isEmpty {
            findings.append(Finding(path: parsed.positionals[0], message: "no M4A files were found"))
        }
        let root = parsed.positionals.count == 1 ? URL(fileURLWithPath: parsed.positionals[0]).standardizedFileURL : nil
        console.print("Checked \(files.count) files\(compareLibrary ? " against the Music library" : "")")
        for finding in findings.sorted() {
            let shown = root.map { relativePath(URL(fileURLWithPath: finding.path), from: $0) } ?? finding.path
            console.print("  \(shown): \(finding.message)")
        }
        if compareLibrary {
            if parsed.positionals.isEmpty, locations.count != supportedLocations.count {
                console.print(
                    "note: \(locations.count - supportedLocations.count) library file(s) use other formats; their audio metadata and dates were not examined"
                )
            }
            console.print(
                "note: artwork, copyright, and full release dates are not compared with Music; unknown cloud status does not confirm absence of matching"
            )
        }
        if environment.readDates == nil {
            console.print("note: file dates were not compared, because they cannot be read on this platform")
        }
        console.print(findings.isEmpty ? "No problems found." : "\(findings.count) problem(s) found.")
        return findings.isEmpty ? 0 : 1
    }

    static func key(of file: AudioFile) -> String {
        albumKey(
            artist: file.tags.albumArtist ?? LibraryFiles.text(file.file, .artist) ?? "", album: file.tags.album ?? "")
    }

    static func fileFindings(_ files: [AudioFile], environment: Environment) -> [Finding] {
        var findings: [Finding] = []
        for file in files {
            var missing: [String] = []
            if file.tags.album == nil { missing.append("album") }
            if file.tags.albumArtist == nil && LibraryFiles.text(file.file, .artist) == nil {
                missing.append("album artist")
            }
            if file.tags.title == nil { missing.append("title") }
            if file.tags.trackNumber == nil { missing.append("track number") }
            if !missing.isEmpty {
                findings.append(Finding(path: file.url.path, message: "no \(missing.joined(separator: ", ")) tag"))
            }
        }
        for (_, album) in Dictionary(grouping: files.filter { $0.tags.album != nil }, by: key(of:)) {
            for (_, group) in Dictionary(
                grouping: album.filter { $0.tags.trackNumber != nil },
                by: {
                    "\($0.tags.discNumber ?? 1)-\($0.tags.trackNumber!)"
                }) where group.count > 1
            {
                for file in group {
                    findings.append(
                        Finding(
                            path: file.url.path,
                            message:
                                "shares disc \(file.tags.discNumber ?? 1) track \(file.tags.trackNumber!) with \(group.count - 1) other file(s)"
                        ))
                }
            }
            for (_, group) in Dictionary(
                grouping: album.filter { $0.tags.title != nil },
                by: {
                    TitleRules.comparisonKey($0.tags.title!)
                }) where group.count > 1
            {
                for file in group {
                    findings.append(
                        Finding(
                            path: file.url.path,
                            message: "shares its title with \(group.count - 1) other file(s) of the album"))
                }
            }
        }
        if let readDates = environment.readDates {
            for file in files {
                guard let date = LibraryFiles.text(file.file, .releaseDate).flatMap({ ReleaseDate(tagValue: $0) })
                else {
                    findings.append(
                        Finding(path: file.url.path, message: "no complete release date; file dates cannot be checked"))
                    continue
                }
                let values: (created: Date?, modified: Date?)
                do { values = try readDates(file.url) } catch {
                    findings.append(Finding(path: file.url.path, message: "file dates could not be read: \(error)"))
                    continue
                }
                let expected = date.localStart(in: environment.timeZone).date
                func differs(_ value: Date?) -> Bool { value.map { abs($0.timeIntervalSince(expected)) >= 1 } ?? true }
                if differs(values.created) || differs(values.modified) {
                    let formatter = ISO8601DateFormatter()
                    formatter.timeZone = environment.timeZone
                    func shown(_ value: Date?) -> String { value.map(formatter.string) ?? "unknown" }
                    findings.append(
                        Finding(
                            path: file.url.path,
                            message:
                                "dates (created \(shown(values.created)), modified \(shown(values.modified))) differ from \(date) at local midnight"
                        ))
                }
            }
        }
        return findings
    }

    /// Compares each file with the library track at its location, and reports library tracks of the same albums
    /// whose files are missing. Music caches metadata independently of files, so a track can disagree with its file.
    static func libraryFindings(
        _ files: [AudioFile], tracks: [LibraryTrack], roots: [URL], entireLibrary: Bool
    ) -> [Finding] {
        var findings: [Finding] = []
        let albums = Set(files.map(key(of:)))
        let byLocation = Dictionary(
            tracks.compactMap { track in track.standardizedLocation.map { ($0, [track]) } }, uniquingKeysWith: +)
        for file in files {
            let candidates = byLocation[file.url.standardizedFileURL.path] ?? []
            guard !candidates.isEmpty else {
                findings.append(Finding(path: file.url.path, message: "not in the library"))
                continue
            }
            if candidates.count > 1 {
                findings.append(Finding(path: file.url.path, message: "in the library \(candidates.count) times"))
            }
            for track in candidates {
                for difference in differences(file, track) {
                    findings.append(Finding(path: file.url.path, message: difference))
                }
            }
        }
        for track in tracks {
            let key = albumKey(artist: track.effectiveAlbumArtist, album: track.album)
            let selected =
                track.location.map { location in
                    roots.contains { isWithin(URL(fileURLWithPath: location), $0) }
                } ?? false
            guard entireLibrary || selected || albums.contains(key) else { continue }
            let path = track.location ?? "\(track.album) / \(track.name)"
            if !entireLibrary, albums.contains(key), !selected,
                roots.contains(where: { pathKind($0) == .directory }), track.location != nil
            {
                findings.append(Finding(path: path, message: "a track of this album is outside the selected folders"))
            }
            if notableCloudStatuses.contains(track.cloudStatus.lowercased()) {
                findings.append(Finding(path: path, message: "cloud status is \(track.cloudStatus)"))
            }
            guard let location = track.location else {
                findings.append(Finding(path: path, message: "a library track without a file"))
                continue
            }
            switch pathKind(location) {
            case .missing:
                findings.append(Finding(path: location, message: "a library track whose file is missing"))
            case .symbolicLink:
                findings.append(Finding(path: location, message: "a library location is a symbolic link"))
            case .file: break
            default:
                findings.append(Finding(path: location, message: "a library location is not a regular file"))
            }
        }
        return findings
    }

    /// Every field whose value differs between a file and its library track.
    static func differences(_ file: AudioFile, _ track: LibraryTrack) -> [String] {
        let mp4 = file.file
        let year = LibraryFiles.text(mp4, .releaseDate).flatMap { Int($0.prefix(4)) } ?? 0
        let fields: [(String, String, String)] = [
            ("title", file.tags.title ?? "", track.name),
            ("album", file.tags.album ?? "", track.album),
            ("artist", LibraryFiles.text(mp4, .artist) ?? "", track.artist),
            ("album artist", file.tags.albumArtist ?? "", track.albumArtist),
            ("composer", LibraryFiles.text(mp4, .composer) ?? "", track.composer),
            ("genre", LibraryFiles.text(mp4, .genre) ?? "", track.genre),
            ("comment", LibraryFiles.text(mp4, .comment) ?? "", track.comment),
            ("track count", String(LibraryFiles.pair(mp4, .trackNumber)?.total ?? 0), String(track.trackCount)),
            ("disc count", String(LibraryFiles.pair(mp4, .discNumber)?.total ?? 0), String(track.discCount)),
            ("compilation", String(mp4.metadataValues(.compilation).contains(.integer(1))), String(track.compilation)),
            ("year", year == 0 ? "" : String(year), track.year == 0 ? "" : String(track.year)),
            (
                "track number", file.tags.trackNumber.map(String.init) ?? "",
                track.trackNumber == 0 ? "" : String(track.trackNumber)
            ),
            (
                "disc number", file.tags.discNumber.map(String.init) ?? "",
                track.discNumber == 0 ? "" : String(track.discNumber)
            ),
        ]
        return fields.filter { $0.1 != $0.2 }.map { "\($0.0) differs: file \"\($0.1)\", library \"\($0.2)\"" }
    }
}
