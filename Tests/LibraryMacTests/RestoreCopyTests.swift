#if os(macOS)
    import Foundation
    import LibraryMac
    import RebuildCore
    import Testing

    @Suite struct RestoreCopyTests {
        struct Fixture {
            let base: URL
            let root: URL
            let source: URL
        }

        func fixture(bytes: Int, createRoot: Bool = true) throws -> Fixture {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(
                "ilibrary-restore-\(UUID().uuidString)")
            let root = base.appendingPathComponent("restored")
            try FileManager.default.createDirectory(
                at: createRoot ? root : base, withIntermediateDirectories: true)
            let source = base.appendingPathComponent("source.bin")
            var data = Data(count: bytes)
            for index in 0..<bytes { data[index] = UInt8(truncatingIfNeeded: index &* 31 &+ index >> 8) }
            try data.write(to: source)
            _ = try PreciseFileDates.set(
                path: source.path, modification: FileTimestamp(seconds: 1_600_000_000, nanoseconds: 123_456_789),
                creation: FileTimestamp(seconds: 1_500_000_000, nanoseconds: 987_654_321))
            return Fixture(base: base, root: root, source: source)
        }

        func leftovers(_ root: URL) -> [String] {
            let enumerator = FileManager.default.enumerator(atPath: root.path)
            return (enumerator?.allObjects as? [String] ?? []).filter { $0.contains(".ilibrary-restore-") }
        }

        @Test(arguments: [0, 1, 3_000_000 + 17])
        func copiesBytesExactlyAndLeavesTheSourceUntouched(size: Int) throws {
            let f = try fixture(bytes: size)
            defer { try? FileManager.default.removeItem(at: f.base) }
            let before = try FileStatus.read(atPath: f.source.path)
            let original = try Data(contentsOf: f.source)
            let destination = f.root.appendingPathComponent("Artist/Album/01 Song.bin")
            let count = try RestoreCopy.copy(from: f.source, to: destination, below: f.root, chunkSize: 65_536)
            #expect(count == size)
            #expect(try Data(contentsOf: destination) == original)
            #expect(try Data(contentsOf: f.source) == original)
            let after = try FileStatus.read(atPath: f.source.path)
            #expect(after.modification == before.modification)
            #expect(after.creation == before.creation)
            #expect(after.size == before.size)
            #expect(leftovers(f.root).isEmpty)
        }

        @Test func aRootUnderPrivateAndANewDestinationShareAPrefix() throws {
            let f = try fixture(bytes: 10)
            defer { try? FileManager.default.removeItem(at: f.base) }
            // /var and /tmp are links to /private/var and /private/tmp; both spellings name the same directory.
            guard f.root.path.hasPrefix("/var/") else { return }
            let root = URL(fileURLWithPath: "/private" + f.root.path)
            let destination = root.appendingPathComponent("Artist/./Album/../Album/01 Song.bin")
            #expect(try RestoreCopy.copy(from: f.source, to: destination, below: root) == 10)
            #expect(
                FileManager.default.contents(atPath: f.root.appendingPathComponent("Artist/Album/01 Song.bin").path)
                    == FileManager.default.contents(atPath: f.source.path))
        }

        @Test func existingDestinationIsRefusedAndKept() throws {
            let f = try fixture(bytes: 10)
            defer { try? FileManager.default.removeItem(at: f.base) }
            let destination = f.root.appendingPathComponent("x.bin")
            try Data("keep".utf8).write(to: destination)
            #expect(throws: RestoreCopyError.destinationExists(path: destination.path)) {
                try RestoreCopy.copy(from: f.source, to: destination, below: f.root)
            }
            #expect(try Data(contentsOf: destination) == Data("keep".utf8))
            #expect(leftovers(f.root).isEmpty)
        }

        @Test func symbolicLinkSourceIsRefused() throws {
            let f = try fixture(bytes: 10)
            defer { try? FileManager.default.removeItem(at: f.base) }
            let link = f.base.appendingPathComponent("link.bin")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.source)
            let destination = f.root.appendingPathComponent("x.bin")
            #expect(throws: RestoreCopyError.sourceNotRegular(path: link.path)) {
                try RestoreCopy.copy(from: link, to: destination, below: f.root)
            }
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        }

        @Test func directorySourceAndMissingSourceAreRefused() throws {
            let f = try fixture(bytes: 10)
            defer { try? FileManager.default.removeItem(at: f.base) }
            let destination = f.root.appendingPathComponent("x.bin")
            #expect(throws: RestoreCopyError.sourceNotRegular(path: f.root.path)) {
                try RestoreCopy.copy(from: f.root, to: destination, below: f.root)
            }
            let missing = f.base.appendingPathComponent("none.bin")
            #expect(throws: RestoreCopyError.sourceMissing(path: missing.path)) {
                try RestoreCopy.copy(from: missing, to: destination, below: f.root)
            }
        }

        @Test func theRestorationRootIsNeverCreated() throws {
            let f = try fixture(bytes: 10, createRoot: false)
            defer { try? FileManager.default.removeItem(at: f.base) }
            let destination = f.root.appendingPathComponent("Artist/x.bin")
            #expect(throws: RestoreCopyError.rootMissing(path: f.root.path)) {
                try RestoreCopy.copy(from: f.source, to: destination, below: f.root)
            }
            #expect(!FileManager.default.fileExists(atPath: f.root.path))
        }

        @Test func destinationsOutsideTheRootAndLinkedParentsAreRefused() throws {
            let f = try fixture(bytes: 10)
            defer { try? FileManager.default.removeItem(at: f.base) }
            let outside = f.base.appendingPathComponent("outside.bin")
            #expect(throws: RestoreCopyError.destinationOutsideRoot(path: outside.path)) {
                try RestoreCopy.copy(from: f.source, to: outside, below: f.root)
            }
            let elsewhere = f.base.appendingPathComponent("elsewhere")
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            let link = f.root.appendingPathComponent("Artist")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)
            #expect(throws: RestoreCopyError.parentNotDirectory(path: link.path)) {
                try RestoreCopy.copy(from: f.source, to: link.appendingPathComponent("x.bin"), below: f.root)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
        }

        @Test func injectedFailureLeavesNoTemporaryFileAndNoDestination() throws {
            let f = try fixture(bytes: 1_000_000)
            defer { try? FileManager.default.removeItem(at: f.base) }
            let destination = f.root.appendingPathComponent("A/x.bin")
            #expect(throws: RestoreCopyError.injected) {
                try RestoreCopy.copy(from: f.source, to: destination, below: f.root, chunkSize: 4096) { total in
                    if total >= 100_000 { throw RestoreCopyError.injected }
                }
            }
            #expect(!FileManager.default.fileExists(atPath: destination.path))
            #expect(leftovers(f.root).isEmpty)
            #expect(try Data(contentsOf: f.source).count == 1_000_000)
        }
    }
#endif
