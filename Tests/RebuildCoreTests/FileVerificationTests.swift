import Foundation
import Testing

@testable import RebuildCore

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Builds a source tree, inventories it, and copies it with explicitly restored timestamps.
private struct Fixture {
    let source = try! TemporaryDirectory()
    let copy = try! TemporaryDirectory()
    let records: [FileRecord]

    init() throws {
        try source.write("A/one.m4a", Array("first track".utf8))
        try source.write("B/two.m4a", Array("second".utf8))
        try stamp(source.file("A/one.m4a"), modification: sampleModification, creation: sampleCreation)
        try stamp(
            source.file("B/two.m4a"), modification: FileTimestamp(seconds: 1_150_000_000, nanoseconds: 7),
            creation: FileTimestamp(seconds: 1_000_000_001))
        records = try FileInventory(root: source.url, selecting: ["A/one.m4a", "B/two.m4a"]).records
        for record in records {
            let target = copy.file(record.path)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source.file(record.path), to: target)
            try stamp(target, modification: record.modification, creation: record.creation)
        }
    }

    func kinds(_ policy: TimestampPolicy = .apfs) throws -> [VerificationMismatchKind] {
        try FileInventory.verify(copy: copy.url, against: records, policy: policy).mismatches.map(\.kind)
    }
}

@Suite struct FileVerificationTests {
    @Test func exactCopySucceeds() throws {
        let fixture = try Fixture()
        let report = try FileInventory.verify(copy: fixture.copy.url, against: fixture.records, policy: .apfs)
        #expect(report.isSuccess)
        #expect(report.mismatches.isEmpty)
        #expect(report.checkedCount == 2)
    }

    @Test func missingFile() throws {
        let fixture = try Fixture()
        try FileManager.default.removeItem(at: fixture.copy.file("B/two.m4a"))
        #expect(try fixture.kinds() == [.missing])
    }

    @Test func sizeMismatch() throws {
        let fixture = try Fixture()
        let target = fixture.copy.file("B/two.m4a")
        try Data("second!".utf8).write(to: target)
        try stamp(target, modification: fixture.records[1].modification, creation: fixture.records[1].creation)
        #expect(try fixture.kinds() == [.sizeDiffers])
    }

    @Test func digestMismatch() throws {
        let fixture = try Fixture()
        let target = fixture.copy.file("B/two.m4a")
        try Data("secone".utf8).write(to: target)
        try stamp(target, modification: fixture.records[1].modification, creation: fixture.records[1].creation)
        #expect(try fixture.kinds() == [.digestDiffers])
    }

    @Test func modificationTimeMismatch() throws {
        let fixture = try Fixture()
        let target = fixture.copy.file("A/one.m4a")
        try stamp(
            target, modification: FileTimestamp(seconds: sampleModification.seconds, nanoseconds: 123_456_788),
            creation: fixture.records[0].creation)
        #expect(try fixture.kinds() == [.modificationTimeDiffers])
    }

    #if canImport(Darwin)
        @Test func creationTimeMismatch() throws {
            let fixture = try Fixture()
            let target = fixture.copy.file("A/one.m4a")
            try stamp(
                target, modification: sampleModification,
                creation: FileTimestamp(seconds: 1_000_000_000, nanoseconds: 250_000_000))
            #expect(try fixture.kinds() == [.creationTimeDiffers])
        }
    #endif

    @Test func unavailableCreationTimeIsAMismatch() {
        let record = FileRecord(
            path: "a.m4a", size: 1, sha256: SHA256.digest(of: [1]), modification: sampleModification,
            creation: sampleCreation)
        for policy in TimestampPolicy.allCases {
            let status = FileStatus(
                kind: .regular, size: 1, inode: 1, device: 1, linkCount: 1,
                modification: policy == .apfs ? sampleModification : sampleModification.truncatedToSeconds,
                creation: nil)
            let found = FileInventory.timestampMismatches(expected: record, status: status, policy: policy)
            #expect(found.map(\.kind) == [.creationTimeUnavailable])
        }
        // Without an expected creation time, an unavailable one is not examined.
        let bare = FileRecord(
            path: "a.m4a", size: 1, sha256: record.sha256, modification: sampleModification, creation: nil)
        let plain = FileStatus(
            kind: .regular, size: 1, inode: 1, device: 1, linkCount: 1, modification: sampleModification,
            creation: nil)
        #expect(FileInventory.timestampMismatches(expected: bare, status: plain, policy: .apfs).isEmpty)
    }

    @Test func symbolicLinkOnCopyPath() throws {
        let fixture = try Fixture()
        // Replace a directory of the copy by a link to an identical tree elsewhere.
        let elsewhere = try TemporaryDirectory()
        try FileManager.default.moveItem(at: fixture.copy.file("A"), to: elsewhere.file("A"))
        try FileManager.default.createSymbolicLink(
            atPath: fixture.copy.path + "/A", withDestinationPath: elsewhere.path + "/A")
        #expect(try fixture.kinds() == [.symbolicLink])
        // A link at the file itself.
        try FileManager.default.removeItem(atPath: fixture.copy.path + "/A")
        try FileManager.default.moveItem(at: elsewhere.file("A"), to: fixture.copy.file("A"))
        try FileManager.default.moveItem(at: fixture.copy.file("B/two.m4a"), to: elsewhere.file("two.m4a"))
        try FileManager.default.createSymbolicLink(
            atPath: fixture.copy.path + "/B/two.m4a", withDestinationPath: elsewhere.path + "/two.m4a")
        #expect(try fixture.kinds() == [.symbolicLink])
    }

    @Test func extraFileIsReported() throws {
        let fixture = try Fixture()
        try fixture.copy.write("C/extra.M4A", [1])
        try fixture.copy.write("C/notes.txt", [1])
        try fixture.copy.write(".hidden.m4a", [1])
        let report = try FileInventory.verify(copy: fixture.copy.url, against: fixture.records, policy: .apfs)
        #expect(report.mismatches.map(\.kind) == [.extraFile])
        #expect(report.mismatches.map(\.path) == ["C/extra.M4A"])
        #expect(!report.isSuccess)
    }

    @Test func verificationDoesNotWriteToTheCopy() throws {
        let fixture = try Fixture()
        func snapshot() throws -> [String: FileStatus] {
            var result: [String: FileStatus] = [:]
            let walker = try #require(FileManager.default.enumerator(atPath: fixture.copy.path))
            for case let name as String in walker {
                result[name] = try FileStatus.read(atPath: fixture.copy.path + "/" + name)
            }
            return result
        }
        let before = try snapshot()
        _ = try fixture.kinds()
        #expect(try snapshot() == before)
    }

    @Test func hfsPlusAcceptsTruncatedTimestampsOnly() throws {
        let fixture = try Fixture()
        // The expected modification times have nanoseconds; the copy holds the truncated values.
        for record in fixture.records {
            let target = fixture.copy.file(record.path)
            try stamp(
                target, modification: record.modification.truncatedToSeconds,
                creation: record.creation?.truncatedToSeconds)
        }
        #expect(try fixture.kinds(.hfsPlus).isEmpty)
        #expect(!(try fixture.kinds(.apfs)).isEmpty)
        // A one-second deviation, in either direction, is rejected.
        let target = fixture.copy.file("A/one.m4a")
        for delta: Int64 in [-1, 1] {
            try stamp(
                target, modification: FileTimestamp(seconds: sampleModification.seconds + delta),
                creation: fixture.records[0].creation?.truncatedToSeconds)
            #expect(try fixture.kinds(.hfsPlus) == [.modificationTimeDiffers])
        }
    }

    @Test func refusesUnusableInputs() throws {
        let fixture = try Fixture()
        let link = fixture.copy.path + "/../" + UUID().uuidString
        let linkURL = URL(fileURLWithPath: link).standardizedFileURL
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: fixture.copy.path)
        defer { try? FileManager.default.removeItem(at: linkURL) }
        #expect(throws: FileInventoryError.rootIsSymbolicLink(path: linkURL.path)) {
            try FileInventory.verify(copy: linkURL, against: fixture.records, policy: .apfs)
        }
        let bad = FileRecord(
            path: "../x.m4a", size: 0, sha256: SHA256.digest(of: [UInt8]()), modification: sampleModification,
            creation: nil)
        #expect(throws: FileInventoryError.escapesRoot(path: "../x.m4a")) {
            try FileInventory.verify(copy: fixture.copy.url, against: [bad], policy: .apfs)
        }
    }
}
