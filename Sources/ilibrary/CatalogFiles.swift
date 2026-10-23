import CatalogCore
import Foundation
import MP4Core

/// Loads and validates a catalog, printing its diagnostics. Errors end the command.
func loadCatalog(_ path: String, console: Console) throws -> (catalog: Catalog, directory: URL) {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard pathKind(url) == .file else {
        throw CommandError.failure(
            pathKind(url) == .symbolicLink ? "\(path) is a symbolic link" : "\(path) is not a file")
    }
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw CommandError.failure("\(path) cannot be read: \(error.localizedDescription)")
    }
    let result = Catalog.validate(data)
    for diagnostic in result.diagnostics {
        let text = "\(path): \(diagnostic.path.isEmpty ? "catalog" : diagnostic.path): \(diagnostic.message)"
        if diagnostic.severity == .error { console.error(text) } else { console.warning(text) }
    }
    guard let catalog = result.catalog else {
        throw CommandError.failure("\(path) is not a valid catalog (\(result.errors.count) errors)")
    }
    return (catalog, url.deletingLastPathComponent())
}

extension Catalog {
    /// The artwork file that each album names, by album index. Albums without one are left out.
    var artworkPaths: [(album: Int, path: String)] {
        albums.enumerated().compactMap { index, album in
            guard let path = album.artwork, !path.isEmpty else { return nil }
            return (index, path)
        }
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
