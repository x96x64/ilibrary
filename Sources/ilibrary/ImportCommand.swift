import FLACCore
import Foundation
import MP4Core

enum ImportCommand {
    static let syntax = CommandSyntax(
        name: "import",
        usage: """
            Usage: ilibrary import SOURCE... -o DIR [--from mora|itunes|auto] [--delete-originals] [--dry-run]

            Converts FLAC, WAV, and AIFF files to Apple Lossless, carrying the standard FLAC tags and front cover,
            and copies M4A files from the iTunes Store without re-encoding, removing purchase metadata. Output keeps
            the relative structure of each source: the files under a SOURCE directory keep their paths relative to
            it under DIR, and a SOURCE file is placed directly in DIR, with the extension .m4a. Every output is
            verified before it is moved into place. Nothing is changed when any file is refused, a destination
            exists, or free space is insufficient. Conversion requires macOS.

            Options:
              -o, --output DIR        the folder that receives the imported files (required)
              --from mora|itunes|auto which files to import: FLAC from mora, M4A from the iTunes Store, or both
                                      with WAV and AIFF (default: auto)
              --delete-originals      after every output has been verified, move the originals to the Trash
              --dry-run               list the planned imports and change nothing
            """, valued: ["--output": ["-o"], "--from": []], flags: ["--delete-originals", "--dry-run"],
        positionals: 1...Int.max)

    enum Action {
        case convert(LosslessSource, tags: ImportTags?)
        case copy(PurchaseMetadataRemoval)
    }

    struct Item {
        var source: URL
        var destination: URL
        var action: Action
    }

    static let conversionExtensions: Set<String> = ["flac", "wav", "aif", "aiff"]

    static func accepts(_ extension: String, from source: String) -> Bool {
        switch source {
        case "mora": `extension` == "flac"
        case "itunes": `extension` == "m4a"
        default: conversionExtensions.contains(`extension`) || `extension` == "m4a"
        }
    }

    static func run(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        let parsed = try syntax.parse(arguments)
        guard let outputPath = parsed.value("--output") else { throw CommandError.usage("import: -o DIR is required") }
        let from = parsed.value("--from") ?? "auto"
        guard ["mora", "itunes", "auto"].contains(from) else {
            throw CommandError.usage("import: --from must be mora, itunes, or auto")
        }
        let deleteOriginals = parsed.flag("--delete-originals")
        if deleteOriginals, environment.moveToTrash == nil {
            throw CommandError.failure(
                "--delete-originals requires a Trash, which this platform does not provide; nothing was changed")
        }
        let output = URL(fileURLWithPath: outputPath, isDirectory: true).standardizedFileURL
        switch pathKind(output) {
        case .directory: break
        case .missing:
            guard pathKind(output.deletingLastPathComponent()) == .directory else {
                throw CommandError.failure(
                    "\(output.deletingLastPathComponent().path) does not exist; nothing was changed")
            }
        default: throw CommandError.failure("\(outputPath) exists and is not a directory; nothing was changed")
        }

        // Overlapping sources would import one file twice, and the second move to the Trash would then fail.
        let roots = parsed.positionals.map { URL(fileURLWithPath: $0).standardizedFileURL }
        for (index, root) in roots.enumerated() {
            if let other = roots.enumerated().first(where: { $0.offset != index && isWithin(root, $0.element) }) {
                throw CommandError.usage(
                    "import: \(root.path) lies within \(other.element.path); give each source once")
            }
        }

        var refused: [(String, String)] = []
        var candidates: [(source: URL, relative: String)] = []
        var untouched = 0
        for path in parsed.positionals {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            switch pathKind(url) {
            case .missing: throw CommandError.failure("\(path) does not exist")
            case .symbolicLink: refused.append((url.path, "symbolic links are not followed"))
            case .directory:
                if isWithin(output, url) {
                    throw CommandError.failure(
                        "the output folder lies inside the source \(url.path); nothing was changed")
                }
                for (file, relative) in try walk(url, base: url, refused: &refused) {
                    let ext = file.pathExtension.lowercased()
                    if ext == "m4p" {
                        refused.append((file.path, "protected .m4p files are not supported"))
                    } else if accepts(ext, from: from) {
                        candidates.append((file, relative))
                    } else {
                        untouched += 1
                    }
                }
            case .file:
                let ext = url.pathExtension.lowercased()
                if ext == "m4p" {
                    refused.append((url.path, "protected .m4p files are not supported"))
                } else if accepts(ext, from: from) {
                    candidates.append((url, url.lastPathComponent))
                } else {
                    refused.append((url.path, "not a file that --from \(from) imports"))
                }
            case .other: refused.append((url.path, "not a regular file or directory"))
            }
        }

        var items: [Item] = []
        var claimed: [String: String] = [:]
        for (source, relative) in candidates.sorted(by: { $0.source.path < $1.source.path }) {
            let destination = output.appendingPathComponent(relative).deletingPathExtension().appendingPathExtension(
                "m4a"
            )
            .standardizedFileURL
            let key = destination.path.lowercased()
            if let other = claimed[key] {
                refused.append((source.path, "it and \(other) would both be imported as \(destination.path)"))
                continue
            }
            claimed[key] = source.path
            if pathKind(destination) != .missing {
                refused.append((source.path, "\(destination.path) already exists and is not replaced"))
                continue
            }
            // Every existing folder between the output folder and the destination must be a real directory, so
            // that no write fails part-way or follows a link out of the output folder.
            if let blocked = blockedAncestor(of: destination, below: output) {
                refused.append((source.path, "\(blocked.path) is not a directory that can hold the output"))
                continue
            }
            do {
                items.append(
                    Item(source: source, destination: destination, action: try plan(source, environment: environment)))
            } catch let error as CommandError {
                refused.append((source.path, error.message))
            } catch {
                refused.append((source.path, "\(error)"))
            }
        }
        console.print(
            "Import: \(items.count) files planned, \(refused.count) refused, \(untouched) other files left untouched")
        for (path, reason) in refused { console.print("  refused \(path): \(reason)") }
        guard refused.isEmpty else { throw CommandError.failure("some files are refused; nothing was changed") }
        guard !items.isEmpty else { throw CommandError.failure("no file to import was found") }

        // The outputs accumulate on the volume of the output folder. A converted file grows by the cover it
        // carries, and writing its tags needs room for one further copy of the largest output.
        let sizes = items.map { item -> Int64 in
            switch item.action {
            case .convert(let source, let tags):
                let cover = tags?.items.first { $0.key == .artwork }.map { item -> Int64 in
                    item.values.reduce(0) { total, value in
                        if case .image(let data, _) = value { return total + Int64(data.count) }
                        return total
                    }
                }
                return source.estimatedSize + (cover ?? 0)
            case .copy:
                let size = (try? FileManager.default.attributesOfItem(atPath: item.source.path)[.size] as? NSNumber)?
                    .intValue
                return Int64(size ?? 0)
            }
        }
        let required = sizes.reduce(0, +) + (sizes.max() ?? 0) + (1 << 20)
        let volume = pathKind(output) == .directory ? output : output.deletingLastPathComponent()
        if let available = environment.availableCapacity(volume) {
            guard Int64(available) >= required else {
                throw CommandError.failure(
                    "\(available) bytes are available, but the import needs up to \(required); nothing was changed")
            }
        } else {
            console.warning("the free space of the volume of \(volume.path) could not be determined")
        }

        if pathKind(output) == .missing { console.print("  create \(output.path)") }
        for item in items {
            let shown = relativePath(item.destination, from: output)
            switch item.action {
            case .convert(let source, let tags):
                let detail = tags.map { "; \($0.summary)" } ?? ""
                console.print("  convert \(item.source.path) (\(source.description)) -> \(shown)\(detail)")
            case .copy(let removal):
                console.print(
                    "  copy \(item.source.path) without re-encoding -> \(shown); removes \(removal.removedItems.count) purchase items and \(removal.removedSampleEntryBoxes.count) sample-entry boxes"
                )
            }
        }
        if deleteOriginals {
            console.print("  then move \(items.count) originals to the Trash, once every output is verified")
        }
        if parsed.flag("--dry-run") {
            console.print("Dry run: nothing was changed.")
            return 0
        }

        let manager = FileManager.default
        var completed: [Item] = []
        for item in items {
            do {
                try manager.createDirectory(
                    at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try execute(item, environment: environment)
            } catch {
                let message = (error as? CommandError)?.message ?? "\(error)"
                throw CommandError.failure(
                    "\(item.source.path): \(message) (\(completed.count) files were imported and verified before this failure; no original was moved)"
                )
            }
            completed.append(item)
        }
        console.print("Imported and verified: \(completed.count) files")
        guard deleteOriginals, let moveToTrash = environment.moveToTrash else { return 0 }
        var trashed = 0
        for item in completed {
            // A replacement is trusted only while it exists where it was verified.
            guard pathKind(item.destination) == .file else {
                throw CommandError.failure(
                    "\(item.destination.path) is missing; \(item.source.path) was kept (\(trashed) originals were moved)"
                )
            }
            do {
                _ = try moveToTrash(item.source)
            } catch {
                throw CommandError.failure(
                    "\(item.source.path) could not be moved to the Trash: \(error) (\(trashed) originals were moved)")
            }
            trashed += 1
        }
        console.print("Moved to the Trash: \(trashed) originals")
        return 0
    }

    static func blockedAncestor(of destination: URL, below output: URL) -> URL? {
        var folder = destination.deletingLastPathComponent().standardizedFileURL
        var ancestors: [URL] = []
        while isWithin(folder, output), folder.path != output.path {
            ancestors.append(folder)
            folder = folder.deletingLastPathComponent()
        }
        return ancestors.reversed().first { [.file, .symbolicLink, .other].contains(pathKind($0)) }
    }

    static func walk(_ directory: URL, base: URL, refused: inout [(String, String)]) throws -> [(URL, String)] {
        var found: [(URL, String)] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        where !name.hasPrefix(".") {
            let url = directory.appendingPathComponent(name)
            switch pathKind(url) {
            case .directory: found += try walk(url, base: base, refused: &refused)
            case .file: found.append((url, relativePath(url, from: base)))
            case .symbolicLink:
                let ext = url.pathExtension.lowercased()
                if conversionExtensions.contains(ext) || ["m4a", "m4p"].contains(ext)
                    || pathKind(url.resolvingSymlinksInPath()) == .directory
                {
                    refused.append((url.path, "symbolic links are not followed"))
                }
            case .missing, .other: break
            }
        }
        return found
    }

    static func plan(_ source: URL, environment: Environment) throws -> Action {
        let ext = source.pathExtension.lowercased()
        if ext == "m4a" {
            var file = try MP4File(contentsOf: source)
            try file.ensureNotEncrypted(path: source.path)
            return .copy(try file.removePurchaseMetadata())
        }
        guard let converter = environment.converter else {
            throw CommandError.failure("converting to Apple Lossless requires macOS")
        }
        let format = try converter.preflight(source)
        var tags: ImportTags?
        if ext == "flac" {
            do {
                tags = ImportTags(try FLACMetadata(contentsOf: source))
            } catch {
                throw CommandError.failure("its FLAC metadata cannot be read: \(error)")
            }
        }
        return .convert(format, tags: tags)
    }

    /// Writes the output under a hidden temporary name beside its destination, verifies it, and moves it into
    /// place. On failure, the temporary file is removed; the source is never changed.
    static func execute(_ item: Item, environment: Environment) throws {
        let manager = FileManager.default
        let partial = item.destination.deletingLastPathComponent()
            .appendingPathComponent(
                ".\(item.destination.deletingPathExtension().lastPathComponent).\(UUID().uuidString).ilibrary-partial.m4a"
            )
        do {
            switch item.action {
            case .convert(_, let tags):
                guard let converter = environment.converter else {
                    throw CommandError.failure("conversion requires macOS")
                }
                try converter.convert(item.source, partial)
                if let tags, !tags.items.isEmpty {
                    var file = try MP4File(contentsOf: partial)
                    for (key, values) in tags.items { try file.setMetadata(key, values) }
                    try MP4Writer.write(file, to: partial)
                    let reread = try MP4File(contentsOf: partial)
                    guard tags.items.allSatisfy({ reread.metadataValues($0.key) == $0.values }) else {
                        throw CommandError.failure("the carried tags did not read back as written")
                    }
                }
                // The tagged file is verified against the source once more before it is trusted.
                try converter.verify(item.source, partial)
            case .copy:
                var file = try MP4File(contentsOf: item.source)
                try file.removePurchaseMetadata()
                try MP4Writer.write(file, to: partial)
                let written = try MP4File(contentsOf: partial)
                let remaining = written.metadata.map(\.key).filter {
                    if case .atom(let code) = $0 { return MP4File.purchaseItemKeys.contains(code) }
                    return false
                }
                let extra = written.sampleEntries.flatMap(\.children).filter {
                    !MP4File.sampleEntryChildAllowlist.contains($0.type)
                }
                guard remaining.isEmpty, extra.isEmpty else {
                    throw CommandError.failure("purchase metadata remained after removal")
                }
                let differences = written.streamDifferences(from: try MP4File(contentsOf: item.source))
                guard differences.isEmpty else {
                    throw CommandError.failure("the audio stream differs: \(differences.joined(separator: "; "))")
                }
            }
            guard pathKind(item.destination) == .missing else {
                throw CommandError.failure("\(item.destination.path) appeared during the import")
            }
            try manager.moveItem(at: partial, to: item.destination)
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }
    }
}
