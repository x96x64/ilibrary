#if os(macOS)
    import Foundation
    import LibraryMac
    import Testing

    @Suite struct FileDatesTests {
        func directory() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "ilibrary-dates-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        @Test(arguments: [-372_000_000.0, 86_400.0, 1_760_000_000.0])
        func datesAreSetOnFilesAndFolders(seconds: Double) throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let file = root.appendingPathComponent("01 Song.m4a")
            #expect(FileManager.default.createFile(atPath: file.path, contents: Data("synthetic".utf8)))
            let date = Date(timeIntervalSince1970: seconds)
            try FileDates.set(file, to: date)
            try FileDates.set(root, to: date)
            #expect(try FileDates.read(file) == FileDateValues(created: date, modified: date))
            #expect(try FileDates.read(root) == FileDateValues(created: date, modified: date))
        }

        @Test func aLaterCreationDateIsApplied() throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let file = root.appendingPathComponent("01 Song.m4a")
            FileManager.default.createFile(atPath: file.path, contents: Data())
            try FileDates.set(file, to: Date(timeIntervalSince1970: 0))
            try FileDates.set(file, to: Date(timeIntervalSince1970: 1_000_000_000))
            #expect(try FileDates.read(file).created == Date(timeIntervalSince1970: 1_000_000_000))
        }

        @Test func missingPathsAreNeverCreated() throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let missing = root.appendingPathComponent("Missing Artist")
            #expect(throws: FileDateError.missing(path: missing.path)) { try FileDates.set(missing, to: Date()) }
            #expect(!FileManager.default.fileExists(atPath: missing.path))
        }

        @Test func symbolicLinksAreRefusedAndTheirTargetsUnchanged() throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let target = root.appendingPathComponent("target.m4a")
            FileManager.default.createFile(atPath: target.path, contents: Data())
            let before = try FileDates.read(target)
            let link = root.appendingPathComponent("link.m4a")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            #expect(throws: FileDateError.symbolicLink(path: link.path)) {
                try FileDates.set(link, to: Date(timeIntervalSince1970: 0))
            }
            #expect(try FileDates.read(target) == before)
        }
    }
#endif
