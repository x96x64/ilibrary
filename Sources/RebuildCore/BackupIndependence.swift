/// Facts about the storage that holds one location. A nil value means that the fact could not be determined.
public struct StorageFacts: Equatable, Sendable {
    /// Identifier of the physical whole disk, such as "disk0".
    public var physicalDisk: String?
    /// Filesystem type name, such as "apfs" or "hfs".
    public var filesystemType: String?
    public var isLocal: Bool?
    public var isDiskImage: Bool?
    /// Physical interconnect, such as "USB" or "PCI-Express"; informational only.
    public var interconnect: String?

    public init(
        physicalDisk: String?, filesystemType: String?, isLocal: Bool?, isDiskImage: Bool?,
        interconnect: String?
    ) {
        self.physicalDisk = physicalDisk
        self.filesystemType = filesystemType
        self.isLocal = isLocal
        self.isDiskImage = isDiskImage
        self.interconnect = interconnect
    }
}

/// A reason for which independence is not established.
public enum IndependenceRefusal: Equatable, Sendable, CustomStringConvertible {
    case unknownDeviceIdentity(location: String)
    case sameDevice(location: String, disk: String)
    case notLocal
    case localityUnknown
    case diskImage
    case diskImageUnknown
    case unsupportedFilesystem(String?)
    case notConfirmed

    public var description: String {
        switch self {
        case .unknownDeviceIdentity(let location): "unknown device identity of the \(location)"
        case .sameDevice(let location, let disk): "the backup shares the physical disk \(disk) with the \(location)"
        case .notLocal: "the backup volume is not local"
        case .localityUnknown: "whether the backup volume is local is unknown"
        case .diskImage: "the backup volume is a disk image"
        case .diskImageUnknown: "whether the backup volume is a disk image is unknown"
        case .unsupportedFilesystem(let type):
            "the backup filesystem \(type ?? "(unknown)") is neither apfs nor hfs"
        case .notConfirmed: "the maintainer has not confirmed that the backup medium is separate"
        }
    }
}

public enum IndependenceVerdict: Equatable, Sendable {
    case independent
    case refused([IndependenceRefusal])

    public var isIndependent: Bool { self == .independent }
}

/// Decides whether a backup location may be treated as physically independent of the locations that it protects.
/// The decision is pure, so that every refusal is testable on any platform, and it never asserts independence from
/// missing information: an unknown identifier, flag, or filesystem results in refusal.
public enum BackupIndependence {
    /// Evaluates the backup against every other location and lists every reason for refusal.
    public static func evaluate(
        backup: StorageFacts, others: [StorageFacts], maintainerConfirmed: Bool
    ) -> IndependenceVerdict {
        var reasons: [IndependenceRefusal] = []
        if backup.physicalDisk == nil { reasons.append(.unknownDeviceIdentity(location: "backup")) }
        for (index, other) in others.enumerated() {
            let name = "other location \(index + 1)"
            guard let disk = other.physicalDisk else {
                reasons.append(.unknownDeviceIdentity(location: name))
                continue
            }
            if let own = backup.physicalDisk, own == disk {
                reasons.append(.sameDevice(location: name, disk: disk))
            }
        }
        switch backup.isLocal {
        case .some(true): break
        case .some(false): reasons.append(.notLocal)
        case .none: reasons.append(.localityUnknown)
        }
        switch backup.isDiskImage {
        case .some(false): break
        case .some(true): reasons.append(.diskImage)
        case .none: reasons.append(.diskImageUnknown)
        }
        let filesystemType = backup.filesystemType?.lowercased()
        if filesystemType != "apfs" && filesystemType != "hfs" {
            reasons.append(.unsupportedFilesystem(backup.filesystemType))
        }
        if !maintainerConfirmed { reasons.append(.notConfirmed) }
        return reasons.isEmpty ? .independent : .refused(reasons)
    }
}
