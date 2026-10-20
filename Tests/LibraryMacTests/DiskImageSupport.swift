#if os(macOS)
    import Foundation
    import Testing

    /// A temporary disk image attached with -nobrowse. The caller detaches it in a defer block.
    struct TestImage {
        let root: URL
        let mount: URL

        static func hdiutil(_ arguments: [String]) -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return -1 }
            process.waitUntilExit()
            return process.terminationStatus
        }

        /// Creates and attaches an image; cancels the test with a message if that is impossible here.
        static func attach(filesystem: String) throws -> TestImage {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "ilibrary-image-\(UUID().uuidString)")
            let mount = root.appendingPathComponent("mount")
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            let image = root.appendingPathComponent("test.dmg")
            guard
                hdiutil(["create", "-size", "16m", "-fs", filesystem, "-volname", "ILTest", "-ov", image.path]) == 0
            else {
                try? FileManager.default.removeItem(at: root)
                try Test.cancel("hdiutil cannot create a \(filesystem) image here; the test was skipped")
            }
            guard hdiutil(["attach", image.path, "-nobrowse", "-noverify", "-mountpoint", mount.path]) == 0 else {
                try? FileManager.default.removeItem(at: root)
                try Test.cancel("hdiutil cannot attach images here; the test was skipped")
            }
            return TestImage(root: root, mount: mount)
        }

        func detach() {
            _ = TestImage.hdiutil(["detach", mount.path, "-force"])
            try? FileManager.default.removeItem(at: root)
        }
    }
#endif
