#if os(macOS)
    import Foundation
    import LibraryMac
    import RebuildCore
    import Testing

    @Suite struct PreciseFileDatesTests {
        func directory() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "ilibrary-precise-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func file(in root: URL, _ name: String = "a.bin") -> String {
            let path = root.appendingPathComponent(name).path
            FileManager.default.createFile(atPath: path, contents: Data("synthetic".utf8))
            return path
        }

        static let cases: [(String, FileTimestamp, FileTimestamp)] = [
            (
                "creation later", FileTimestamp(seconds: 1_600_000_000, nanoseconds: 123_456_789),
                FileTimestamp(seconds: 1_700_000_000, nanoseconds: 987_654_321)
            ),
            (
                "creation earlier", FileTimestamp(seconds: 1_700_000_000, nanoseconds: 111_111_111),
                FileTimestamp(seconds: 1_500_000_000, nanoseconds: 222_222_222)
            ),
            (
                "negative epoch", FileTimestamp(seconds: -372_000_000, nanoseconds: 500_000_001),
                FileTimestamp(seconds: -400_000_000, nanoseconds: 999_999_999)
            ),
            (
                "equal", FileTimestamp(seconds: 1_650_000_000, nanoseconds: 5),
                FileTimestamp(seconds: 1_650_000_000, nanoseconds: 5)
            ),
        ]

        @Test(arguments: cases)
        func apfsStoresNanosecondsExactly(label: String, modification: FileTimestamp, creation: FileTimestamp) throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            #expect(TimestampPolicy.forVolume(containing: root.path) == .apfs)
            let path = file(in: root)
            let stored = try PreciseFileDates.set(path: path, modification: modification, creation: creation)
            #expect(stored.modification == modification, "\(label)")
            #expect(stored.creation == creation, "\(label)")
            let again = try FileStatus.read(atPath: path)
            #expect(again.modification == modification)
            #expect(again.creation == creation)
        }

        @Test func accessTimeIsLeftUnchanged() throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let path = file(in: root)
            var before = stat()
            #expect(stat(path, &before) == 0)
            _ = try PreciseFileDates.set(
                path: path, modification: FileTimestamp(seconds: 1_000_000_000, nanoseconds: 1),
                creation: FileTimestamp(seconds: 900_000_000, nanoseconds: 2))
            var after = stat()
            #expect(stat(path, &after) == 0)
            #expect(before.st_atimespec.tv_sec == after.st_atimespec.tv_sec)
            #expect(before.st_atimespec.tv_nsec == after.st_atimespec.tv_nsec)
        }

        @Test func missingPathIsRefusedAndNothingIsCreated() throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let missing = root.appendingPathComponent("Missing").path
            let stamp = FileTimestamp(seconds: 1)
            #expect(throws: PreciseFileDatesError.missing(path: missing)) {
                try PreciseFileDates.set(path: missing, modification: stamp, creation: stamp)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }

        @Test func symbolicLinkIsRefusedAndTargetUnchanged() throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let target = file(in: root, "target.bin")
            let before = try FileStatus.read(atPath: target)
            let link = root.appendingPathComponent("link.bin").path
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
            let linkBefore = try FileStatus.read(atPath: link)
            let stamp = FileTimestamp(seconds: 1)
            #expect(throws: PreciseFileDatesError.symbolicLink(path: link)) {
                try PreciseFileDates.set(path: link, modification: stamp, creation: stamp)
            }
            #expect(try FileStatus.read(atPath: target) == before)
            #expect(try FileStatus.read(atPath: link) == linkBefore)
        }

        @Test func hfsPlusStoresWholeSecondsUnderItsPolicy() throws {
            let image = try TestImage.attach(filesystem: "HFS+")
            defer { image.detach() }
            #expect(TimestampPolicy.forVolume(containing: image.mount.path) == .hfsPlus)
            for (label, modification, creation) in Self.cases {
                let path = file(in: image.mount, "\(label).bin")
                let stored = try PreciseFileDates.set(path: path, modification: modification, creation: creation)
                print(
                    "HFS+ \(label): requested m=\(modification) c=\(creation); "
                        + "stored m=\(stored.modification) c=\(String(describing: stored.creation))")
                #expect(
                    TimestampPolicy.hfsPlus.compare(source: modification, backup: stored.modification) == .match,
                    "\(label) modification")
                #expect(
                    stored.creation.map { TimestampPolicy.hfsPlus.compare(source: creation, backup: $0) } == .match,
                    "\(label) creation")
                #expect(
                    TimestampPolicy.apfs.compare(source: modification, backup: stored.modification)
                        == (modification.nanoseconds == 0
                            ? .match : .mismatch(expected: modification, actual: stored.modification)))
            }
        }
    }
#endif
