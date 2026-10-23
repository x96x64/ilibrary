import Foundation

/// One Music track as read from the library, restricted to the fields that a rebuild records.
public struct RegistrationRecord: Codable, Equatable, Sendable {
    /// Sixteen hexadecimal digits.
    public let persistentID: String
    public let name: String
    public let album: String
    public let artist: String
    public let albumArtist: String
    /// An absolute POSIX path, or nil when Music reports none.
    public let location: String?
    public let cloudStatus: String
    /// Seconds since 1970-01-01T00:00:00Z, or nil.
    public let dateAdded: Int64?

    public init(
        persistentID: String, name: String, album: String, artist: String, albumArtist: String, location: String?,
        cloudStatus: String, dateAdded: Int64?
    ) {
        self.persistentID = persistentID
        self.name = name
        self.album = album
        self.artist = artist
        self.albumArtist = albumArtist
        self.location = location
        self.cloudStatus = cloudStatus
        self.dateAdded = dateAdded
    }

    static func isWellFormedID(_ id: String) -> Bool {
        id.utf8.count == 16
            && id.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 | 0x20 >= 0x61 && $0 | 0x20 <= 0x66) }
    }
}

/// A file of the inventory, with the source root under which its relative path lies.
public struct SourcedFileRecord: Codable, Equatable, Sendable {
    public let sourceRoot: String
    public let record: FileRecord

    public init(sourceRoot: String, record: FileRecord) {
        self.sourceRoot = sourceRoot
        self.record = record
    }

    /// The absolute path of the file: the source root joined with the relative path.
    public var absolutePath: String { sourceRoot == "/" ? "/" + record.path : sourceRoot + "/" + record.path }
}

/// The pairing of one inventory file, named by its absolute path, with one persistent ID.
public struct RegistrationMapping: Codable, Equatable, Sendable {
    public let location: String
    public let persistentID: String

    public init(location: String, persistentID: String) {
        self.location = location
        self.persistentID = persistentID
    }
}

/// A reason for which the registrations are refused. Each carries a persistent ID or a path.
public enum RegistrationRefusal: Equatable, Sendable, CustomStringConvertible {
    case nonFileTracks(total: Int, file: Int)
    case malformedPersistentID(String)
    case duplicatePersistentID(String)
    case noLocation(persistentID: String)
    case outsideSources(persistentID: String, location: String)
    case protectedAudio(persistentID: String, location: String)
    case duplicateLocation(location: String, persistentIDs: [String])
    case cloudStatus(persistentID: String, status: String)
    case unregisteredFile(path: String)
    case registrationWithoutFile(persistentID: String, location: String)

    public var description: String {
        switch self {
        case .nonFileTracks(let total, let file):
            "the library holds \(total - file) track(s) that are not file tracks (\(total) in total, \(file) file tracks)"
        case .malformedPersistentID(let id): "malformed persistent ID '\(id)'"
        case .duplicatePersistentID(let id): "persistent ID \(id) occurs more than once"
        case .noLocation(let id): "track \(id) has no location"
        case .outsideSources(let id, let location): "track \(id) is outside every selected source root: \(location)"
        case .protectedAudio(let id, let location): "track \(id) is protected audio (.m4p): \(location)"
        case .duplicateLocation(let location, let ids):
            "tracks \(ids.joined(separator: ", ")) share the location \(location)"
        case .cloudStatus(let id, let status): "track \(id) has the unadmitted cloud status '\(status)'"
        case .unregisteredFile(let path): "the file \(path) has no registration"
        case .registrationWithoutFile(let id, let location):
            "track \(id) at \(location) has no inventory file"
        }
    }
}

public struct RegistrationClassificationError: Error, Equatable, Sendable {
    public let refusals: [RegistrationRefusal]
}

public enum RegistrationClassification {
    /// The cloud status texts admitted by default: the empty string and "unknown" only. The values that Music
    /// reports for local-only files while iCloud Music Library is off have not been measured; any other value is
    /// refused until evidence justifies admitting it.
    public static let defaultAllowedCloudStatuses: Set<String> = ["", "unknown"]

    /// Classifies the library registrations against the inventory and returns the one-to-one mapping between the
    /// inventory files and the persistent IDs, sorted by location, or throws every refusal found.
    ///
    /// Non-file tracks are detected when `totalTrackCount` exceeds `fileTrackCount`. Locations are compared after
    /// Unicode NFC normalization and case folding, by component. A location equal to a source root is outside it.
    public static func classify(
        registrations: [RegistrationRecord], totalTrackCount: Int, fileTrackCount: Int,
        inventory: [SourcedFileRecord], sourceRoots: [String],
        allowedCloudStatuses: Set<String> = defaultAllowedCloudStatuses
    ) throws -> [RegistrationMapping] {
        var refusals: [RegistrationRefusal] = []
        if totalTrackCount > fileTrackCount {
            refusals.append(.nonFileTracks(total: totalTrackCount, file: fileTrackCount))
        }
        var seenIDs = Set<String>()
        var byKey: [String: [RegistrationRecord]] = [:]
        var keyOrder: [String] = []
        for registration in registrations {
            let id = registration.persistentID
            if !RegistrationRecord.isWellFormedID(id) {
                refusals.append(.malformedPersistentID(id))
            } else if !seenIDs.insert(id.uppercased()).inserted {
                refusals.append(.duplicatePersistentID(id))
            }
            if !allowedCloudStatuses.contains(registration.cloudStatus) {
                refusals.append(.cloudStatus(persistentID: id, status: registration.cloudStatus))
            }
            guard let location = registration.location, !location.isEmpty else {
                refusals.append(.noLocation(persistentID: id))
                continue
            }
            let inside =
                PathKey.invalidReason(location) == nil
                && sourceRoots.contains { PathKey.relation(location, $0) == .firstInsideSecond }
            if !inside {
                refusals.append(.outsideSources(persistentID: id, location: location))
                continue
            }
            if location.lowercased().hasSuffix(".m4p") {
                refusals.append(.protectedAudio(persistentID: id, location: location))
            }
            let key = PathKey.key(location)
            if byKey[key] == nil { keyOrder.append(key) }
            byKey[key, default: []].append(registration)
        }
        for key in keyOrder {
            if let group = byKey[key], group.count > 1 {
                refusals.append(
                    .duplicateLocation(location: group[0].location ?? key, persistentIDs: group.map(\.persistentID)))
            }
        }
        var inventoryKeys = Set<String>()
        var mapping: [RegistrationMapping] = []
        for entry in inventory {
            let key = PathKey.key(entry.absolutePath)
            inventoryKeys.insert(key)
            let group = byKey[key] ?? []
            if group.isEmpty {
                refusals.append(.unregisteredFile(path: entry.absolutePath))
            } else if group.count == 1 {
                mapping.append(RegistrationMapping(location: entry.absolutePath, persistentID: group[0].persistentID))
            }
            // A larger group was reported as a duplicate location.
        }
        for key in keyOrder where !inventoryKeys.contains(key) {
            for registration in byKey[key] ?? [] {
                refusals.append(
                    .registrationWithoutFile(
                        persistentID: registration.persistentID, location: registration.location ?? key))
            }
        }
        if !refusals.isEmpty { throw RegistrationClassificationError(refusals: refusals) }
        return mapping.sorted { $0.location < $1.location }
    }
}
