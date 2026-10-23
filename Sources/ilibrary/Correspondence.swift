import CatalogCore
import Foundation

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

    /// Builds the correspondence, prints it, and refuses unless every file is matched and none is refused.
    static func requireComplete(_ paths: [String], catalog: Catalog, console: Console) throws -> Correspondence {
        let correspondence = try build(paths, catalog: catalog)
        guard correspondence.print(to: console, catalog: catalog) else {
            throw CommandError.failure("some files are unmatched or refused; nothing was changed")
        }
        return correspondence
    }

    /// Prints every match, refusal, and missing track. Returns false when a file was refused or unmatched.
    func print(to console: Console, catalog: Catalog) -> Bool {
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
                "  matched \(match.file.path) -> \(match.reference) \"\(track.title)\" by \(match.method.rawValue)\(confirmation)"
            )
        }
        for unmatched in report.unmatched {
            console.print("  unmatched \(unmatched.file.path): \(unmatched.reason)")
        }
        for refusal in refused {
            console.print("  refused \(refusal.path): \(refusal.reason)")
        }
        for reference in report.missing {
            console.print("  no file for \(reference) \"\(catalog.track(reference).title)\"")
        }
        return report.unmatched.isEmpty && refused.isEmpty
    }
}
