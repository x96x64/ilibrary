import CatalogCore
import Foundation
import MP4Core

/// The files under the given paths, read and matched to a catalog.
struct Correspondence {
    var files: [AudioFile]
    var report: MatchReport
    var refused: [(path: String, reason: String)]

    var matchedFiles: [(file: AudioFile, match: TrackMatch)] {
        let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.url.path, $0) })
        return report.matches.map { (byPath[$0.file.path]!, $0) }
    }

    static func build(_ paths: [String], catalog: Catalog) throws -> Correspondence {
        let scan = try LibraryFiles.scan(paths)
        let files = try scan.files.map(LibraryFiles.read)
        let report = CatalogMatcher(catalog: catalog).match(files.map(\.tags))
        return Correspondence(files: files, report: report, refused: scan.refused)
    }

    /// Prints every match, refusal, and missing track. Returns false when a file was refused or unmatched.
    func print(to console: Console, catalog: Catalog, root: URL? = nil) -> Bool {
        func shown(_ path: String) -> String { root.map { relativePath(URL(fileURLWithPath: path), from: $0) } ?? path }
        console.print(
            "Files: \(files.count) read, \(report.matches.count) matched, \(report.unmatched.count) unmatched, \(refused.count) refused"
        )
        for match in report.matches {
            let track = catalog.track(match.reference)
            let confirmation =
                match.titleDiffers
                ? "; its title \"\(match.file.title ?? "")\" differs and is replaced"
                : match.titleConfirmed ? "" : "; no title to confirm"
            console.print(
                "  matched \(shown(match.file.path)) -> \(match.reference) \"\(track.title)\" by \(match.method.rawValue)\(confirmation)"
            )
        }
        for unmatched in report.unmatched {
            console.print("  unmatched \(shown(unmatched.file.path)): \(unmatched.reason)")
        }
        for refusal in refused {
            console.print("  refused \(shown(refusal.path)): \(refusal.reason)")
        }
        for reference in report.missing {
            console.print("  no file for \(reference) \"\(catalog.track(reference).title)\"")
        }
        return report.unmatched.isEmpty && refused.isEmpty
    }
}

/// Reads the artwork that a catalog album names, relative to the catalog's directory.
func loadArtwork(_ path: String, catalogDirectory: URL) throws -> MetadataValue {
    let url = URL(fileURLWithPath: path, relativeTo: catalogDirectory).standardizedFileURL
    guard pathKind(url) == .file else {
        throw CommandError.failure(
            "artwork \(path) \(pathKind(url) == .symbolicLink ? "is a symbolic link" : "does not exist")")
    }
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw CommandError.failure("artwork \(path) cannot be read: \(error.localizedDescription)")
    }
    guard let format = ImageFormat(detecting: data) else {
        throw CommandError.failure("artwork \(path) is neither a PNG nor a JPEG image")
    }
    return .image(data, format)
}

enum ValidateCommand {
    static let syntax = CommandSyntax(
        name: "validate",
        usage: """
            Usage: ilibrary validate CATALOG.json [PATH...]

            Checks the format, fields, values, and dates of a catalog. With paths, also matches the .m4a files
            under them to the catalog and reports every match, unmatched file, and catalog track without a file.
            Exit status is 0 when the catalog is valid and every file matches, and 1 otherwise.
            """, positionals: 1...Int.max)

    static func run(_ arguments: [String], console: Console) throws -> Int32 {
        let parsed = try syntax.parse(arguments)
        let (catalog, directory) = try loadCatalog(parsed.positionals[0], console: console)
        let tracks = catalog.resolvedTracks()
        console.print(
            "Catalog: \(catalog.albums.count) albums, \(tracks.count) tracks; valid")
        var valid = true
        for (index, album) in catalog.albums.enumerated() {
            guard let artwork = album.artwork, !artwork.isEmpty else { continue }
            do {
                _ = try loadArtwork(artwork, catalogDirectory: directory)
            } catch let error as CommandError {
                console.error("albums[\(index)]: \(error.message)")
                valid = false
            }
        }
        let paths = Array(parsed.positionals.dropFirst())
        guard !paths.isEmpty else { return valid ? 0 : 1 }
        let correspondence = try Correspondence.build(paths, catalog: catalog)
        let complete = correspondence.print(to: console, catalog: catalog)
        return valid && complete ? 0 : 1
    }
}
