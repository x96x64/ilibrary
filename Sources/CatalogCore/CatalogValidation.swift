import Foundation

/// A finding of catalog validation, located by a JSON path such as `albums[0].discs[1].tracks[2].title`.
public struct CatalogDiagnostic: Equatable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable {
        case error, warning
    }

    public var severity: Severity
    public var path: String
    public var message: String

    public var description: String { "\(severity.rawValue): \(path.isEmpty ? "catalog" : path): \(message)" }
}

/// A JSON value, decoded identically on every platform, for structural validation before typed decoding.
enum JSONValue: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var kind: String {
        switch self {
        case .null: "null"
        case .bool: "a Boolean"
        case .number: "a number"
        case .string: "a string"
        case .array: "an array"
        case .object: "an object"
        }
    }
}

/// The fields of each object of the format. The JSON Schema is tested against these lists.
enum CatalogFields {
    static let root: [String] = ["format", "titleRules", "artists", "albums"]
    static let rootRequired: [String] = ["format", "albums"]
    static let titleRules: [String] = ["case", "removeQualifiers", "bracketNested", "preserve"]
    static let artist: [String] = ["folderDate"]
    static let album: [String] = [
        "album", "aliases", "albumArtist", "artist", "genre", "composer", "copyright", "releaseDate", "compilation",
        "artwork", "notes", "sources", "discs",
    ]
    static let albumRequired: [String] = ["album", "discs"]
    static let disc: [String] = ["tracks"]
    static let discRequired: [String] = ["tracks"]
    static let track: [String] = [
        "title", "artist", "composer", "genre", "copyright", "releaseDate", "notes", "sources",
    ]
    static let trackRequired: [String] = ["title"]
    static let dateFields: Set<String> = ["releaseDate", "folderDate"]
    static let stringArrays: Set<String> = ["aliases", "sources", "removeQualifiers", "preserve"]
    static let booleans: Set<String> = ["compilation", "bracketNested"]
}

public struct CatalogValidationResult: Sendable {
    /// The catalog, when validation found no errors.
    public var catalog: Catalog?
    public var diagnostics: [CatalogDiagnostic]

    public var errors: [CatalogDiagnostic] { diagnostics.filter { $0.severity == .error } }
    public var warnings: [CatalogDiagnostic] { diagnostics.filter { $0.severity == .warning } }
}

extension Catalog {
    /// Validates a catalog document: the format identifier, the fields and types of every object, required
    /// values, dates, and duplicate albums. Output from an AI agent or chat is never applied without this check.
    public static func validate(_ data: Data) -> CatalogValidationResult {
        var diagnostics: [CatalogDiagnostic] = []
        func error(_ path: String, _ message: String) {
            diagnostics.append(CatalogDiagnostic(severity: .error, path: path, message: message))
        }
        func warning(_ path: String, _ message: String) {
            diagnostics.append(CatalogDiagnostic(severity: .warning, path: path, message: message))
        }
        let root: JSONValue
        do {
            root = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            return CatalogValidationResult(
                catalog: nil,
                diagnostics: [CatalogDiagnostic(severity: .error, path: "", message: "the document is not valid JSON")])
        }
        guard case .object(let object) = root else {
            error("", "the document must be a JSON object")
            return CatalogValidationResult(catalog: nil, diagnostics: diagnostics)
        }
        switch object["format"] {
        case .string(Catalog.formatIdentifier)?:
            break
        case .string(let other)? where other.hasPrefix("ilibrary-catalog-"):
            error("format", "\"\(other)\" is not supported; this version reads \"\(Catalog.formatIdentifier)\"")
            return CatalogValidationResult(catalog: nil, diagnostics: diagnostics)
        default:
            error(
                "format", "the document is not an iLibrary catalog: \"format\" must be \"\(Catalog.formatIdentifier)\"")
            return CatalogValidationResult(catalog: nil, diagnostics: diagnostics)
        }

        func checkObject(_ value: JSONValue, _ path: String, fields: [String], required: [String]) -> [String:
            JSONValue]?
        {
            guard case .object(let object) = value else {
                error(path, "must be an object, not \(value.kind)")
                return nil
            }
            for key in object.keys.sorted() where !fields.contains(key) {
                error(join(path, key), "is not a field of the format")
            }
            for key in required where object[key] == nil {
                error(join(path, key), "is required")
            }
            for (key, value) in object.sorted(by: { $0.key < $1.key }) where fields.contains(key) {
                checkType(value, join(path, key), field: key)
            }
            return object
        }
        func checkType(_ value: JSONValue, _ path: String, field: String) {
            if CatalogFields.booleans.contains(field) {
                if case .bool = value { return }
                error(path, "must be a Boolean, not \(value.kind)")
            } else if CatalogFields.stringArrays.contains(field) {
                guard case .array(let items) = value else {
                    return error(path, "must be an array of strings, not \(value.kind)")
                }
                for (index, item) in items.enumerated() {
                    if case .string = item { continue }
                    error("\(path)[\(index)]", "must be a string, not \(item.kind)")
                }
            } else if ["titleRules", "artists", "albums", "discs", "tracks"].contains(field) {
                return
            } else if field == "case" {
                guard case .string(let text) = value, TitleCase(rawValue: text) != nil else {
                    return error(path, "must be one of \(TitleCase.allCases.map(\.rawValue).joined(separator: ", "))")
                }
            } else {
                guard case .string(let text) = value else { return error(path, "must be a string, not \(value.kind)") }
                if CatalogFields.dateFields.contains(field), !text.isEmpty, ReleaseDate(text) == nil {
                    error(path, "\"\(text)\" is not a valid date in the form YYYY-MM-DD")
                }
                if field == "copyright", text.contains("(P)") || text.contains("(C)") || text.contains("(p)") {
                    warning(path, "use the symbols ℗ and © instead of (P) and (C)")
                }
            }
        }
        func requireText(_ object: [String: JSONValue], _ key: String, _ path: String) {
            if case .string(let text)? = object[key], text.trimmingCharacters(in: .whitespaces).isEmpty {
                error(join(path, key), "must not be empty")
            }
        }

        guard let root = checkObject(root, "", fields: CatalogFields.root, required: CatalogFields.rootRequired) else {
            return CatalogValidationResult(catalog: nil, diagnostics: diagnostics)
        }
        if let rules = root["titleRules"] {
            _ = checkObject(rules, "titleRules", fields: CatalogFields.titleRules, required: [])
        }
        if let artists = root["artists"] {
            if case .object(let entries) = artists {
                for (name, entry) in entries.sorted(by: { $0.key < $1.key }) {
                    _ = checkObject(entry, "artists[\"\(name)\"]", fields: CatalogFields.artist, required: [])
                }
            } else {
                error("artists", "must be an object, not \(artists.kind)")
            }
        }
        var seen: [String: String] = [:]
        struct RulesOnly: Decodable { var titleRules: TitleRuleSettings? }
        let rules = TitleRules((try? JSONDecoder().decode(RulesOnly.self, from: data))?.titleRules)
        if case .array(let albums)? = root["albums"] {
            if albums.isEmpty { warning("albums", "the catalog contains no albums") }
            for (albumIndex, albumValue) in albums.enumerated() {
                let albumPath = "albums[\(albumIndex)]"
                guard
                    let album = checkObject(
                        albumValue, albumPath, fields: CatalogFields.album, required: CatalogFields.albumRequired)
                else { continue }
                requireText(album, "album", albumPath)
                var artist = ""
                if case .string(let text)? = album["albumArtist"] ?? album["artist"] { artist = text }
                var names: [String] = []
                if case .string(let name)? = album["album"] { names.append(name) }
                if case .array(let aliases)? = album["aliases"] {
                    for case .string(let alias) in aliases { names.append(alias) }
                }
                for name in names {
                    let key = rules.matchingKey(name) + "\u{0}" + TitleRules.comparisonKey(artist)
                    if let earlier = seen[key], earlier != albumPath {
                        error(albumPath, "\"\(name)\" by the same album artist is also named by \(earlier)")
                    }
                    seen[key] = albumPath
                }
                guard case .array(let discs)? = album["discs"] else {
                    if album["discs"] != nil { error(join(albumPath, "discs"), "must be an array") }
                    continue
                }
                if discs.isEmpty { error(join(albumPath, "discs"), "must contain at least one disc") }
                for (discIndex, discValue) in discs.enumerated() {
                    let discPath = "\(albumPath).discs[\(discIndex)]"
                    guard
                        let disc = checkObject(
                            discValue, discPath, fields: CatalogFields.disc, required: CatalogFields.discRequired)
                    else { continue }
                    guard case .array(let tracks)? = disc["tracks"] else {
                        if disc["tracks"] != nil { error(join(discPath, "tracks"), "must be an array") }
                        continue
                    }
                    if tracks.isEmpty { error(join(discPath, "tracks"), "must contain at least one track") }
                    for (trackIndex, trackValue) in tracks.enumerated() {
                        let trackPath = "\(discPath).tracks[\(trackIndex)]"
                        if let track = checkObject(
                            trackValue, trackPath, fields: CatalogFields.track, required: CatalogFields.trackRequired)
                        {
                            requireText(track, "title", trackPath)
                        }
                    }
                }
            }
        } else if let albums = root["albums"] {
            error("albums", "must be an array, not \(albums.kind)")
        }

        guard !diagnostics.contains(where: { $0.severity == .error }) else {
            return CatalogValidationResult(catalog: nil, diagnostics: diagnostics)
        }
        do {
            return CatalogValidationResult(
                catalog: try JSONDecoder().decode(Catalog.self, from: data), diagnostics: diagnostics)
        } catch {
            diagnostics.append(
                CatalogDiagnostic(severity: .error, path: "", message: "the catalog could not be decoded"))
            return CatalogValidationResult(catalog: nil, diagnostics: diagnostics)
        }
    }

    /// Encodes a catalog with sorted keys and two-space indentation, ending with a newline.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}

func join(_ path: String, _ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }
