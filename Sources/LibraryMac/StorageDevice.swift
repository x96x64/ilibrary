// Classification of the storage that holds a path, from statfs, DiskArbitration, and the IORegistry.
// Every field that cannot be determined is nil; nothing is guessed.
#if os(macOS)
    import Darwin
    import DiskArbitration
    import Foundation
    import IOKit
    import RebuildCore

    /// Facts about the volume that contains a path.
    public struct StorageDescription: Equatable, Sendable {
        public var path: String
        public var mountPoint: String
        public var volumeUUID: String?
        /// Filesystem type name from statfs, such as "apfs".
        public var filesystemType: String
        /// True if the volume is mounted with MNT_LOCAL.
        public var isLocal: Bool
        public var isReadOnly: Bool
        /// BSD name of the volume's media, such as "disk3s5".
        public var mediaBSDName: String?
        /// BSD name of the physical whole disk, such as "disk0"; nil if it is unknown or ambiguous.
        public var physicalWholeDisk: String?
        public var interconnect: String?
        public var interconnectLocation: String?
        public var isInternal: Bool?
        public var isRemovable: Bool?
        public var isEjectable: Bool?
        public var isDiskImage: Bool?
        public var imagePath: String?
        public var deviceModel: String?

        /// The facts from which the independence of two storage locations is decided.
        public var facts: StorageFacts {
            StorageFacts(
                physicalDisk: physicalWholeDisk, filesystemType: filesystemType, isLocal: isLocal,
                isDiskImage: isDiskImage, interconnect: interconnect)
        }
    }

    public enum StorageDeviceError: Error, Equatable, Sendable, CustomStringConvertible {
        case missing(path: String)
        case failed(path: String, reason: String)

        public var description: String {
            switch self {
            case .missing(let path): "\(path) does not exist"
            case .failed(let path, let reason): "the storage of \(path) could not be described: \(reason)"
            }
        }
    }

    public enum StorageDevice {
        /// Describes the volume that contains `path`, which must exist.
        ///
        /// The physical whole disk is found by walking the IORegistry service plane upward from the IOMedia
        /// of the volume. Parents are followed through every intermediate object: an APFS volume, the APFS
        /// container, the synthesized whole IOMedia of the container (for example disk3, which is not a
        /// physical device), the partition IOMedia that stores the container (disk0s2), and the partition
        /// scheme. An IOMedia is accepted as the physical disk only if it is a whole IOMedia and an ancestor
        /// that is reached without passing through another IOMedia carries "Protocol Characteristics", which
        /// only storage devices (including virtual ones) provide. The synthesized container disk fails this
        /// test because its ancestors are APFS objects that lead to another IOMedia. If the walk reaches
        /// several different physical disks, as for a Fusion or striped container, the result is nil.
        public static func describe(path: String) throws -> StorageDescription {
            var info = statfs()
            guard FileManager.default.fileExists(atPath: path) else { throw StorageDeviceError.missing(path: path) }
            guard statfs(path, &info) == 0 else {
                throw StorageDeviceError.failed(path: path, reason: String(cString: strerror(errno)))
            }
            let mountPoint = string(&info.f_mntonname)
            let mountSource = string(&info.f_mntfromname)
            var result = StorageDescription(
                path: path, mountPoint: mountPoint, volumeUUID: nil, filesystemType: string(&info.f_fstypename),
                isLocal: info.f_flags & UInt32(MNT_LOCAL) != 0, isReadOnly: info.f_flags & UInt32(MNT_RDONLY) != 0,
                mediaBSDName: nil, physicalWholeDisk: nil, interconnect: nil, interconnectLocation: nil,
                isInternal: nil, isRemovable: nil, isEjectable: nil, isDiskImage: nil, imagePath: nil,
                deviceModel: nil)
            guard let session = DASessionCreate(kCFAllocatorDefault) else { return result }
            var disk: DADisk?
            if mountSource.hasPrefix("/dev/") {
                disk = DADiskCreateFromBSDName(
                    kCFAllocatorDefault, session, String(mountSource.dropFirst(5)))
            }
            if disk == nil {
                disk = DADiskCreateFromVolumePath(
                    kCFAllocatorDefault, session, URL(fileURLWithPath: mountPoint) as CFURL)
            }
            guard let disk, let description = DADiskCopyDescription(disk) as? [String: Any] else { return result }
            if let name = DADiskGetBSDName(disk) { result.mediaBSDName = String(cString: name) }
            if let uuid = description[kDADiskDescriptionVolumeUUIDKey as String] {
                // The value is a CFUUID; Foundation bridges it opaquely.
                result.volumeUUID = CFUUIDCreateString(nil, (uuid as! CFUUID)) as String?
            }
            result.isInternal = description[kDADiskDescriptionDeviceInternalKey as String] as? Bool
            result.isRemovable = description[kDADiskDescriptionMediaRemovableKey as String] as? Bool
            result.isEjectable = description[kDADiskDescriptionMediaEjectableKey as String] as? Bool
            result.deviceModel = description[kDADiskDescriptionDeviceModelKey as String] as? String
            let protocolName = description[kDADiskDescriptionDeviceProtocolKey as String] as? String
            var image = result.deviceModel == "Disk Image" || protocolName == "Virtual Interface"
            if let bsd = result.mediaBSDName, let media = media(named: bsd) {
                defer { IOObjectRelease(media) }
                let walk = physicalDisk(above: media)
                result.physicalWholeDisk = walk.disk
                result.interconnect = walk.interconnect
                result.interconnectLocation = walk.location
                if walk.interconnect == "Virtual Interface" { image = true }
                if let path = imagePath(of: media) {
                    result.imagePath = path
                    image = true
                }
                result.isDiskImage = image
            } else if image {
                result.isDiskImage = true
            }
            return result
        }

        private static func string<T>(_ field: inout T) -> String {
            withUnsafePointer(to: &field) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
        }

        private static func media(named bsd: String) -> io_registry_entry_t? {
            guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsd) else { return nil }
            let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
            return service == 0 ? nil : service
        }

        private static func imagePath(of media: io_registry_entry_t) -> String? {
            let value = IORegistryEntrySearchCFProperty(
                media, kIOServicePlane, "image-path" as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
            if let data = value as? Data {
                return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
            }
            return value as? String
        }

        private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }

        private static func isMedia(_ entry: io_registry_entry_t) -> Bool {
            IOObjectConformsTo(entry, "IOMedia") != 0
        }

        /// Returns the Protocol Characteristics of the nearest ancestor that has them, without passing
        /// through another IOMedia.
        private static func deviceCharacteristics(above entry: io_registry_entry_t) -> [String: Any]? {
            var parents: io_iterator_t = 0
            guard IORegistryEntryGetParentIterator(entry, kIOServicePlane, &parents) == KERN_SUCCESS else {
                return nil
            }
            defer { IOObjectRelease(parents) }
            while case let parent = IOIteratorNext(parents), parent != 0 {
                defer { IOObjectRelease(parent) }
                if isMedia(parent) { continue }
                if let characteristics = property(parent, "Protocol Characteristics") as? [String: Any] {
                    return characteristics
                }
                if let found = deviceCharacteristics(above: parent) { return found }
            }
            return nil
        }

        private struct Walk {
            var disks: Set<String> = []
            var interconnects: Set<String> = []
            var locations: Set<String> = []
            var visited: Set<UInt64> = []
        }

        private static func physicalDisk(above media: io_registry_entry_t) -> (
            disk: String?, interconnect: String?, location: String?
        ) {
            var walk = Walk()
            visit(media, &walk)
            let single = { (set: Set<String>) -> String? in set.count == 1 ? set.first : nil }
            guard walk.disks.count == 1 else { return (nil, nil, nil) }
            return (single(walk.disks), single(walk.interconnects), single(walk.locations))
        }

        private static func visit(_ entry: io_registry_entry_t, _ walk: inout Walk) {
            var identifier: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(entry, &identifier)
            guard walk.visited.insert(identifier).inserted else { return }
            if isMedia(entry), property(entry, "Whole") as? Bool == true,
                let name = property(entry, "BSD Name") as? String,
                let characteristics = deviceCharacteristics(above: entry)
            {
                walk.disks.insert(name)
                if let value = characteristics["Physical Interconnect"] as? String {
                    walk.interconnects.insert(value)
                }
                if let value = characteristics["Physical Interconnect Location"] as? String {
                    walk.locations.insert(value)
                }
                return
            }
            var parents: io_iterator_t = 0
            guard IORegistryEntryGetParentIterator(entry, kIOServicePlane, &parents) == KERN_SUCCESS else { return }
            defer { IOObjectRelease(parents) }
            while case let parent = IOIteratorNext(parents), parent != 0 {
                defer { IOObjectRelease(parent) }
                visit(parent, &walk)
            }
        }
    }
#endif
