// Mount state of volumes by UUID. Nothing here mounts or unmounts a volume.
#if os(macOS)
    import Darwin
    import DiskArbitration
    import Foundation

    public enum MountState {
        /// True if a volume with the given UUID is currently mounted, from the mount table (`getfsstat`) and the
        /// volume UUID that DiskArbitration reports for each mounted device. The comparison ignores case. An
        /// empty or unmatched UUID yields false.
        public static func isMounted(volumeUUID: String) -> Bool {
            let wanted = volumeUUID.uppercased()
            guard !wanted.isEmpty, let session = DASessionCreate(kCFAllocatorDefault) else { return false }
            let count = getfsstat(nil, 0, MNT_NOWAIT)
            guard count > 0 else { return false }
            var table = Array(repeating: statfs(), count: Int(count))
            let bytes = Int32(MemoryLayout<statfs>.size * table.count)
            let filled = getfsstat(&table, bytes, MNT_NOWAIT)
            guard filled > 0 else { return false }
            for index in 0..<Int(filled) {
                var entry = table[index]
                let source = withUnsafePointer(to: &entry.f_mntfromname) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
                }
                guard source.hasPrefix("/dev/"),
                    let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, String(source.dropFirst(5))),
                    let description = DADiskCopyDescription(disk) as? [String: Any],
                    let value = description[kDADiskDescriptionVolumeUUIDKey as String]
                else { continue }
                // The value is a CFUUID; Foundation bridges it opaquely.
                let uuid = CFUUIDCreateString(nil, (value as! CFUUID)) as String?
                if uuid?.uppercased() == wanted { return true }
            }
            return false
        }

        /// Polls until the volume is no longer mounted or `timeout` seconds have passed, and returns whether it
        /// disappeared. It performs no unmount. A volume that is already absent returns true immediately.
        public static func waitUntilUnmounted(
            volumeUUID: String, timeout: TimeInterval, poll: TimeInterval = 1
        ) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while isMounted(volumeUUID: volumeUUID) {
                if Date() >= deadline { return false }
                Thread.sleep(forTimeInterval: max(0.01, min(poll, deadline.timeIntervalSinceNow)))
            }
            return true
        }
    }
#endif
