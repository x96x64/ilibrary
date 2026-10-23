import CatalogCore
import Foundation

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
        console.print("Catalog: \(catalog.albums.count) albums, \(tracks.count) tracks; valid")
        var valid = true
        for (index, path) in catalog.artworkPaths {
            do {
                _ = try loadArtwork(path, catalogDirectory: directory)
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
