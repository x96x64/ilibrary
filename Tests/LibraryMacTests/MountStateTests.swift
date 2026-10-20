#if os(macOS)
    import Foundation
    import LibraryMac
    import Testing

    @Suite struct MountStateTests {
        @Test func attachedImageIsMountedAndDetachedImageDisappears() throws {
            let image = try TestImage.attach(filesystem: "APFS")
            var detached = false
            defer { if !detached { image.detach() } }
            let marker = image.mount.appendingPathComponent("m")
            FileManager.default.createFile(atPath: marker.path, contents: Data())
            guard let uuid = try StorageDevice.describe(path: marker.path).volumeUUID else {
                try Test.cancel("the test volume reports no UUID; the test was skipped")
            }
            #expect(MountState.isMounted(volumeUUID: uuid))
            #expect(MountState.isMounted(volumeUUID: uuid.lowercased()))
            #expect(!MountState.isMounted(volumeUUID: UUID().uuidString))
            #expect(!MountState.isMounted(volumeUUID: ""))

            let started = Date()
            #expect(!MountState.waitUntilUnmounted(volumeUUID: uuid, timeout: 0.5, poll: 0.1))
            #expect(Date().timeIntervalSince(started) >= 0.5)
            #expect(MountState.isMounted(volumeUUID: uuid))

            image.detach()
            detached = true
            #expect(MountState.waitUntilUnmounted(volumeUUID: uuid, timeout: 10, poll: 0.1))
            #expect(!MountState.isMounted(volumeUUID: uuid))
        }
    }
#endif
