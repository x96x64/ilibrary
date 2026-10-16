import CatalogCore
import Foundation
import MP4Core

enum PathKind {
    case missing, symbolicLink, directory, file, other
}

/// The kind of a path, determined without following symbolic links.
func pathKind(_ url: URL) -> PathKind {
    // attributesOfItem does not traverse a final symbolic link.
    guard let type = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType else {
        return .missing
    }
    switch type {
    case .typeSymbolicLink: return .symbolicLink
    case .typeDirectory: return .directory
    case .typeRegular: return .file
    default: return .other
    }
}

/// An M4A file and the tags that matching uses.
struct AudioFile {
    var url: URL
    var file: MP4File
    var tags: FileTags
}

struct ScanResult {
    var files: [URL] = []
    /// Paths that a command refuses to process, with the reason.
    var refused: [(path: String, reason: String)] = []
}

enum LibraryFiles {
    /// Finds `.m4a` files in the given files and directories. Symbolic links are never followed and are
    /// refused, as are protected `.m4p` files. Hidden files are skipped. Paths are returned sorted.
    static func scan(_ paths: [String]) throws -> ScanResult {
        var result = ScanResult()
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            switch pathKind(url) {
            case .missing:
                throw CommandError.failure("\(path) does not exist")
            case .symbolicLink:
                result.refused.append((url.path, "symbolic links are not followed"))
            case .file:
                classify(url, into: &result, explicit: true)
            case .directory:
                try walk(url, into: &result)
            case .other:
                result.refused.append((url.path, "not a regular file or directory"))
            }
        }
        result.files = Array(Set(result.files)).sorted { $0.path < $1.path }
        result.refused.sort { $0.path < $1.path }
        return result
    }

    static func classify(_ url: URL, into result: inout ScanResult, explicit: Bool) {
        switch url.pathExtension.lowercased() {
        case "m4a": result.files.append(url)
        case "m4p": result.refused.append((url.path, "protected .m4p files are not supported"))
        default: if explicit { result.refused.append((url.path, "not an .m4a file")) }
        }
    }

    static func walk(_ directory: URL, into result: inout ScanResult) throws {
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        for name in entries where !name.hasPrefix(".") {
            let url = directory.appendingPathComponent(name)
            switch pathKind(url) {
            case .directory: try walk(url, into: &result)
            case .file: classify(url, into: &result, explicit: false)
            case .symbolicLink:
                if ["m4a", "m4p"].contains(url.pathExtension.lowercased())
                    || pathKind(url.resolvingSymlinksInPath()) == .directory
                {
                    result.refused.append((url.path, "symbolic links are not followed"))
                }
            case .missing, .other: break
            }
        }
    }

    static func read(_ url: URL) throws -> AudioFile {
        let file: MP4File
        do {
            file = try MP4File(contentsOf: url)
        } catch {
            throw CommandError.failure("\(url.path): \(error)")
        }
        return AudioFile(url: url, file: file, tags: tags(of: file, path: url.path))
    }

    static func text(_ file: MP4File, _ key: MetadataKey) -> String? {
        for value in file.metadataValues(key) {
            if case .text(let text) = value, !text.isEmpty { return text }
        }
        return nil
    }

    static func pair(_ file: MP4File, _ key: MetadataKey) -> (number: Int, total: Int)? {
        for value in file.metadataValues(key) {
            if case .pair(let number, let total) = value, number > 0 { return (number, total) }
        }
        return nil
    }

    static func tags(of file: MP4File, path: String) -> FileTags {
        FileTags(
            path: path, album: text(file, .album), albumArtist: text(file, .albumArtist),
            discNumber: pair(file, .discNumber)?.number, trackNumber: pair(file, .trackNumber)?.number,
            title: text(file, .title))
    }
}

/// A short, value-revealing description of tag values for reports of planned changes.
func describe(_ values: [MetadataValue]) -> String {
    guard !values.isEmpty else { return "(none)" }
    return values.map { value -> String in
        switch value {
        case .text(let text): "\"\(text)\""
        case .integer(let number): String(number)
        case .pair(let number, let total): "\(number)/\(total)"
        case .image(let data, let format): "\(format == .png ? "PNG" : "JPEG") image of \(data.count) bytes"
        case .other(let type, let data): "type \(type), \(data.count) bytes"
        }
    }.joined(separator: ", ")
}

/// Whether `url` lies inside `root` or is `root` itself.
func isWithin(_ url: URL, _ root: URL) -> Bool {
    let path = url.standardizedFileURL.path
    let base = root.standardizedFileURL.path
    return path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
}

/// The path of `url` relative to `base` when it lies inside it, and its absolute path otherwise.
func relativePath(_ url: URL, from base: URL) -> String {
    let path = url.standardizedFileURL.path
    let prefix = base.standardizedFileURL.path + "/"
    return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
}
