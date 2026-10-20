#if os(macOS)
    import Foundation
    import Testing

    @testable import LibraryMac

    /// Returns the scripted statuses in order and repeats the last one.
    final class ScriptedProbe: @unchecked Sendable {
        var script: [MountStatus]
        var calls = 0

        init(_ script: [MountStatus]) { self.script = script }

        func next() -> MountStatus {
            defer { calls += 1 }
            return script[min(calls, script.count - 1)]
        }
    }

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
            #expect(MountState.status(volumeUUID: uuid) == .mounted)
            #expect(MountState.status(volumeUUID: uuid.lowercased()) == .mounted)
            #expect(MountState.status(volumeUUID: UUID().uuidString) != .mounted)
            #expect(MountState.status(volumeUUID: "") != .mounted)

            let started = Date()
            #expect(MountState.waitUntilUnmounted(volumeUUID: uuid, timeout: 0.5, poll: 0.1) == .stillMounted)
            #expect(Date().timeIntervalSince(started) >= 0.5)
            #expect(MountState.status(volumeUUID: uuid) == .mounted)

            image.detach()
            detached = true
            #expect(MountState.waitUntilUnmounted(volumeUUID: uuid, timeout: 10, poll: 0.1) == .unmounted)
            #expect(MountState.status(volumeUUID: uuid) != .mounted)
        }

        let wanted = "11111111-2222-3333-4444-555555555555"

        func entry(_ source: String, _ type: String, _ uuid: String?) -> MountEntry {
            MountEntry(source: source, filesystemType: type, volumeUUID: uuid)
        }

        @Test func anEmptyUUIDIsUnknownEvenWhenEveryEntryIsReadable() {
            let entries = [entry("/dev/disk1s1", "apfs", wanted)]
            guard case .unknown = MountState.status(volumeUUID: "", entries: entries) else {
                Issue.record("an empty UUID must be unknown")
                return
            }
        }

        @Test func aMatchingUUIDIsMountedIgnoringCaseAndOtherUnreadableEntries() {
            let entries = [entry("/dev/disk2s1", "apfs", nil), entry("/dev/disk1s1", "apfs", wanted)]
            #expect(MountState.status(volumeUUID: wanted, entries: entries) == .mounted)
            #expect(MountState.status(volumeUUID: wanted.lowercased(), entries: entries) == .mounted)
        }

        @Test func anUnreadableAPFSOrHFSDeviceEntryMakesAnAbsentVolumeUnknown() {
            for type in ["apfs", "hfs"] {
                let entries = [
                    entry("/dev/disk1s1", "apfs", "AAAAAAAA-0000-0000-0000-000000000000"),
                    entry("/dev/disk7s1", type, nil),
                ]
                guard case .unknown(let reason) = MountState.status(volumeUUID: wanted, entries: entries) else {
                    Issue.record("an unreadable \(type) device entry must make the result unknown")
                    continue
                }
                #expect(reason.contains("/dev/disk7s1"))
            }
        }

        @Test func unreadableEntriesOfOtherKindsAreIgnored() {
            // Network, virtual, and other filesystems cannot be the verified APFS or HFS+ backup.
            let entries = [
                entry("devfs", "devfs", nil), entry("//server/share", "smbfs", nil),
                entry("/dev/disk9s1", "msdos", nil), entry("map auto_home", "autofs", nil),
                entry("/dev/disk1s1", "apfs", "AAAAAAAA-0000-0000-0000-000000000000"),
            ]
            #expect(MountState.status(volumeUUID: wanted, entries: entries) == .notMounted)
            #expect(MountState.status(volumeUUID: wanted, entries: []) == .notMounted)
        }

        @Test func aFailedReaderYieldsUnknown() {
            struct Failure: Error {}
            guard case .unknown(let reason) = MountState.status(volumeUUID: wanted, readEntries: { throw Failure() })
            else {
                Issue.record("a failed read must be unknown")
                return
            }
            #expect(reason.contains("mount table"))
            #expect(MountState.status(volumeUUID: wanted, readEntries: { [] }) == .notMounted)
            guard case .unknown = MountState.status(volumeUUID: "", readEntries: { [] }) else {
                Issue.record("an empty UUID must be unknown")
                return
            }
        }

        @Test func aWaitThatIsAlwaysUnknownReturnsUnknownAfterTheTimeout() {
            let probe = ScriptedProbe([.unknown("unreadable")])
            let started = Date()
            let result = MountState.waitUntilUnmounted(volumeUUID: wanted, timeout: 0.3, poll: 0.05) { _ in
                probe.next()
            }
            #expect(result == .unknown("unreadable"))
            #expect(Date().timeIntervalSince(started) >= 0.3)
            #expect(probe.calls > 1)
        }

        @Test func unknownFollowedByNotMountedReturnsUnmounted() {
            let probe = ScriptedProbe([.unknown("unreadable"), .notMounted])
            let result = MountState.waitUntilUnmounted(volumeUUID: wanted, timeout: 5, poll: 0.01) { _ in probe.next() }
            #expect(result == .unmounted)
            #expect(probe.calls == 2)
        }

        @Test func aVolumeMountedUntilTheDeadlineReturnsStillMounted() {
            let probe = ScriptedProbe([.mounted])
            let started = Date()
            let result = MountState.waitUntilUnmounted(volumeUUID: wanted, timeout: 0.3, poll: 0.05) { _ in
                probe.next()
            }
            #expect(result == .stillMounted)
            #expect(Date().timeIntervalSince(started) >= 0.3)
        }

        @Test func mountedThenUnknownThenNotMountedReturnsUnmounted() {
            let probe = ScriptedProbe([.mounted, .unknown("unreadable"), .notMounted])
            let result = MountState.waitUntilUnmounted(volumeUUID: wanted, timeout: 5, poll: 0.01) { _ in probe.next() }
            #expect(result == .unmounted)
            #expect(probe.calls == 3)
        }

        @Test func anUnknownProbeIsNeverTurnedIntoUnmounted() {
            for script in [
                [MountStatus.unknown("a")], [.mounted, .unknown("b")], [.unknown("c"), .mounted, .unknown("d")],
            ] {
                let probe = ScriptedProbe(script)
                let result = MountState.waitUntilUnmounted(volumeUUID: wanted, timeout: 0.2, poll: 0.02) { _ in
                    probe.next()
                }
                #expect(result != .unmounted)
            }
        }
    }
#endif
