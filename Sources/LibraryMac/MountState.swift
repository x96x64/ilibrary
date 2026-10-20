// Mount state of volumes by UUID. Nothing here mounts or unmounts a volume.
#if os(macOS)
    import Darwin
    import DiskArbitration
    import Foundation

    /// What the mount table shows about one volume. Unknown means that the table could not be read completely
    /// enough to decide; it is never to be treated as absence.
    public enum MountStatus: Equatable, Sendable {
        case mounted
        case notMounted
        case unknown(String)
    }

    /// The outcome of waiting for a volume to disappear.
    public enum UnmountWait: Equatable, Sendable {
        case unmounted
        case stillMounted
        case unknown(String)
    }

    /// One entry of the mount table with the volume UUID that DiskArbitration reports for it. A nil UUID means that
    /// the device description or its volume UUID could not be read.
    public struct MountEntry: Equatable, Sendable {
        public var source: String
        public var filesystemType: String
        public var volumeUUID: String?

        public init(source: String, filesystemType: String, volumeUUID: String?) {
            self.source = source
            self.filesystemType = filesystemType
            self.volumeUUID = volumeUUID
        }
    }

    public enum MountState {
        /// Decides from mount-table entries whether the volume with a UUID is mounted. The comparison ignores case.
        public static func status(volumeUUID: String, entries: [MountEntry]) -> MountStatus {
            let wanted = volumeUUID.uppercased()
            if wanted.isEmpty { return .unknown("the volume UUID is empty") }
            if entries.contains(where: { $0.volumeUUID?.uppercased() == wanted }) { return .mounted }
            // Only a device entry of a filesystem that the backup could have (it was verified as APFS or HFS+) can
            // hide the volume when its identity is unreadable; network, virtual, and other entries are ignored.
            if let hidden = entries.first(where: {
                $0.volumeUUID == nil && $0.source.hasPrefix("/dev/")
                    && ($0.filesystemType == "apfs" || $0.filesystemType == "hfs")
            }) {
                return .unknown("the volume UUID of the mounted device \(hidden.source) could not be read")
            }
            return .notMounted
        }

        /// The status from the system mount table (`getfsstat`) and the volume UUID that DiskArbitration reports for
        /// each mounted device. A failure to create the session or to read the table yields unknown.
        public static func status(volumeUUID: String) -> MountStatus {
            status(volumeUUID: volumeUUID, readEntries: systemEntries)
        }

        /// The status from entries that `readEntries` supplies; a thrown error yields unknown.
        public static func status(volumeUUID: String, readEntries: () throws -> [MountEntry]) -> MountStatus {
            if volumeUUID.isEmpty { return .unknown("the volume UUID is empty") }
            do {
                return status(volumeUUID: volumeUUID, entries: try readEntries())
            } catch {
                return .unknown("the mount table could not be read: \(error)")
            }
        }

        struct ReadFailure: Error, CustomStringConvertible {
            var description: String
        }

        static func systemEntries() throws -> [MountEntry] {
            guard let session = DASessionCreate(kCFAllocatorDefault) else {
                throw ReadFailure(description: "a DiskArbitration session could not be created")
            }
            let count = getfsstat(nil, 0, MNT_NOWAIT)
            guard count > 0 else { throw ReadFailure(description: "getfsstat reported no mounts") }
            var table = Array(repeating: statfs(), count: Int(count))
            let bytes = Int32(MemoryLayout<statfs>.size * table.count)
            let filled = getfsstat(&table, bytes, MNT_NOWAIT)
            guard filled > 0 else { throw ReadFailure(description: "getfsstat failed") }
            var entries: [MountEntry] = []
            for index in 0..<Int(filled) {
                var entry = table[index]
                let source = withUnsafePointer(to: &entry.f_mntfromname) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
                }
                let type = withUnsafePointer(to: &entry.f_fstypename) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
                }
                var uuid: String?
                if source.hasPrefix("/dev/"),
                    let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, String(source.dropFirst(5))),
                    let description = DADiskCopyDescription(disk) as? [String: Any],
                    let value = description[kDADiskDescriptionVolumeUUIDKey as String]
                {
                    // The value is a CFUUID; Foundation bridges it opaquely.
                    uuid = CFUUIDCreateString(nil, (value as! CFUUID)) as String?
                }
                entries.append(MountEntry(source: source, filesystemType: type, volumeUUID: uuid))
            }
            return entries
        }

        /// Polls until the volume is reported as not mounted or `timeout` seconds have passed. It performs no
        /// unmount. Only a probe that reports not mounted ends the wait successfully; at the deadline the result is
        /// still mounted or, when the last probe could not decide, unknown with its reason.
        public static func waitUntilUnmounted(
            volumeUUID: String, timeout: TimeInterval, poll: TimeInterval = 1,
            probe: (String) -> MountStatus = { MountState.status(volumeUUID: $0) }
        ) -> UnmountWait {
            let deadline = Date().addingTimeInterval(timeout)
            while true {
                let status = probe(volumeUUID)
                if status == .notMounted { return .unmounted }
                if Date() >= deadline {
                    if case .unknown(let reason) = status { return .unknown(reason) }
                    return .stillMounted
                }
                Thread.sleep(forTimeInterval: max(0.01, min(poll, deadline.timeIntervalSinceNow)))
            }
        }
    }
#endif
