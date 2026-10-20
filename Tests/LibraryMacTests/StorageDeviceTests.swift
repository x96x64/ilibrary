#if os(macOS)
    import Foundation
    import LibraryMac
    import RebuildCore
    import Testing

    @Suite struct StorageDeviceTests {
        func directory() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "ilibrary-storage-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        /// Runs hdiutil, which exists only in these tests, and returns its status.
        func hdiutil(_ arguments: [String]) -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return -1 }
            process.waitUntilExit()
            return process.terminationStatus
        }

        @Test func systemVolumeDirectoryHasKnownPhysicalDisk() throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let description = try StorageDevice.describe(path: root.path)
            #expect(description.physicalWholeDisk != nil)
            #expect(description.isDiskImage == false)
            #expect(description.isLocal)
            #expect(description.mediaBSDName != nil)
            #expect(description.physicalWholeDisk != description.mediaBSDName)
        }

        @Test func missingPathIsReported() {
            #expect(throws: StorageDeviceError.self) {
                try StorageDevice.describe(path: "/nonexistent-ilibrary-\(UUID().uuidString)")
            }
        }

        @Test func directoriesOnOneVolumeShareThePhysicalDiskAndAreRefused() throws {
            let first = try directory()
            let second = try directory()
            defer {
                try? FileManager.default.removeItem(at: first)
                try? FileManager.default.removeItem(at: second)
            }
            let a = try StorageDevice.describe(path: first.path)
            let b = try StorageDevice.describe(path: second.path)
            #expect(a.physicalWholeDisk != nil)
            #expect(a.physicalWholeDisk == b.physicalWholeDisk)
            let verdict = BackupIndependence.evaluate(backup: a.facts, others: [b.facts], maintainerConfirmed: true)
            guard case .refused(let reasons) = verdict else {
                Issue.record("a backup on the same disk was accepted")
                return
            }
            #expect(reasons.contains(.sameDevice(location: "other location 1", disk: a.physicalWholeDisk ?? "")))
        }

        @Test(arguments: ["APFS", "HFS+"])
        func diskImageIsReportedAndRefused(filesystem: String) throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let image = root.appendingPathComponent("test.dmg")
            let mount = root.appendingPathComponent("mount")
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            guard
                hdiutil(["create", "-size", "8m", "-fs", filesystem, "-volname", "ILTest", "-ov", image.path]) == 0
            else {
                try Test.cancel("hdiutil cannot create a \(filesystem) image here; the disk image test was skipped")
            }
            guard hdiutil(["attach", image.path, "-nobrowse", "-noverify", "-mountpoint", mount.path]) == 0 else {
                try Test.cancel("hdiutil cannot attach images here; the disk image test was skipped")
            }
            defer { _ = hdiutil(["detach", mount.path, "-force"]) }
            let marker = mount.appendingPathComponent("marker")
            #expect(FileManager.default.createFile(atPath: marker.path, contents: Data("x".utf8)))
            let description = try StorageDevice.describe(path: marker.path)
            #expect(description.mountPoint.hasSuffix("/mount"))
            #expect(description.isDiskImage == true)
            #expect(description.isLocal)
            #expect(description.interconnect == "Virtual Interface")
            #expect(description.imagePath?.hasSuffix("test.dmg") == true)
            let system = try StorageDevice.describe(path: root.path)
            let verdict = BackupIndependence.evaluate(
                backup: description.facts, others: [system.facts], maintainerConfirmed: true)
            guard case .refused(let reasons) = verdict else {
                Issue.record("a disk image was accepted as independent")
                return
            }
            #expect(reasons.contains(.diskImage))
        }
    }
#endif
