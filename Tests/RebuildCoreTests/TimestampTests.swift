import Foundation
import Testing

@testable import RebuildCore

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Creates and removes a temporary directory for one test.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ilibrary-rebuildcore-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    var path: String { url.path }

    func file(_ relative: String) -> URL { URL(fileURLWithPath: path + "/" + relative) }

    @discardableResult
    func write(_ relative: String, _ bytes: [UInt8]) throws -> URL {
        let target = file(relative)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes).write(to: target)
        return target
    }
}

/// Sets the creation time (Darwin only; the value must be exactly representable as a Double) and then the
/// modification time with nanosecond precision.
func stamp(_ url: URL, modification: FileTimestamp, creation: FileTimestamp? = nil) throws {
    #if canImport(Darwin)
        if let creation {
            let date = Date(timeIntervalSince1970: Double(creation.seconds) + Double(creation.nanoseconds) / 1e9)
            try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: url.path)
        }
    #endif
    var times = [
        timespec(tv_sec: Int(modification.seconds), tv_nsec: Int(modification.nanoseconds)),
        timespec(tv_sec: Int(modification.seconds), tv_nsec: Int(modification.nanoseconds)),
    ]
    #expect(utimensat(AT_FDCWD, url.path, &times, 0) == 0)
}

let sampleCreation = FileTimestamp(seconds: 1_000_000_000, nanoseconds: 500_000_000)
let sampleModification = FileTimestamp(seconds: 1_100_000_000, nanoseconds: 123_456_789)

@Suite struct TimestampTests {
    @Test func initializerNormalizesNanoseconds() {
        #expect(
            FileTimestamp(seconds: 5, nanoseconds: 1_500_000_000) == FileTimestamp(seconds: 6, nanoseconds: 500_000_000)
        )
        let negative = FileTimestamp(seconds: 5, nanoseconds: -1)
        #expect(negative.seconds == 4 && negative.nanoseconds == 999_999_999)
    }

    @Test func apfsRequiresExactEquality() {
        let source = FileTimestamp(seconds: 100, nanoseconds: 999_999_999)
        #expect(TimestampPolicy.apfs.compare(source: source, backup: source) == .match)
        #expect(
            TimestampPolicy.apfs.compare(source: source, backup: FileTimestamp(seconds: 100, nanoseconds: 999_999_998))
                == .mismatch(expected: source, actual: FileTimestamp(seconds: 100, nanoseconds: 999_999_998)))
        #expect(TimestampPolicy.apfs.compare(source: source, backup: FileTimestamp(seconds: 100)) != .match)
        #expect(TimestampPolicy.apfs.compare(source: source, backup: FileTimestamp(seconds: 101)) != .match)
    }

    @Test func hfsPlusAcceptsOnlyTheTruncatedValue() {
        let policy = TimestampPolicy.hfsPlus
        for nanoseconds: Int32 in [0, 1, 500_000_000, 999_999_999] {
            let source = FileTimestamp(seconds: 100, nanoseconds: nanoseconds)
            #expect(policy.compare(source: source, backup: FileTimestamp(seconds: 100)) == .match)
            #expect(policy.compare(source: source, backup: FileTimestamp(seconds: 101)) != .match)
            #expect(policy.compare(source: source, backup: FileTimestamp(seconds: 99)) != .match)
            #expect(policy.compare(source: source, backup: FileTimestamp(seconds: 100, nanoseconds: 1)) != .match)
        }
        // A source that is whole seconds still needs an exact whole-second backup.
        #expect(
            policy.compare(source: FileTimestamp(seconds: 7), backup: FileTimestamp(seconds: 7, nanoseconds: 1))
                != .match)
    }

    @Test func hfsPlusTruncatesTowardNegativeInfinity() {
        // 1.5 seconds before the epoch is -2 s + 0.5 s; the floor is -2, not the toward-zero value -1.
        let source = FileTimestamp(seconds: -2, nanoseconds: 500_000_000)
        #expect(TimestampPolicy.hfsPlus.compare(source: source, backup: FileTimestamp(seconds: -2)) == .match)
        #expect(TimestampPolicy.hfsPlus.compare(source: source, backup: FileTimestamp(seconds: -1)) != .match)
        #expect(source.truncatedToSeconds == FileTimestamp(seconds: -2))
        let last = FileTimestamp(seconds: -1, nanoseconds: 999_999_999)
        #expect(TimestampPolicy.hfsPlus.compare(source: last, backup: FileTimestamp(seconds: -1)) == .match)
        #expect(TimestampPolicy.hfsPlus.compare(source: last, backup: FileTimestamp(seconds: 0)) != .match)
    }

    @Test func filesystemNamesMapToPolicies() {
        #expect(TimestampPolicy(filesystemTypeName: "apfs") == .apfs)
        #expect(TimestampPolicy(filesystemTypeName: "hfs") == .hfsPlus)
        for name in ["msdos", "exfat", "smbfs", "nfs", "ext4", "", "APFS", "unknown"] {
            #expect(TimestampPolicy(filesystemTypeName: name) == nil, "\(name)")
        }
    }

    @Test func volumeLookupMatchesPlatform() throws {
        let directory = try TemporaryDirectory()
        #if canImport(Darwin)
            let name = try #require(TimestampPolicy.filesystemTypeName(containing: directory.path))
            #expect(!name.isEmpty)
            #expect(TimestampPolicy.forVolume(containing: directory.path) == TimestampPolicy(filesystemTypeName: name))
            #expect(TimestampPolicy.filesystemTypeName(containing: directory.path + "/missing") == nil)
        #else
            #expect(TimestampPolicy.filesystemTypeName(containing: directory.path) == nil)
            #expect(TimestampPolicy.forVolume(containing: directory.path) == nil)
        #endif
    }

    @Test func readsModificationWithNanoseconds() throws {
        let directory = try TemporaryDirectory()
        let url = try directory.write("a.bin", [1, 2, 3])
        try stamp(url, modification: sampleModification)
        let status = try FileStatus.read(atPath: url.path)
        #expect(status.kind == .regular)
        #expect(status.size == 3)
        #expect(status.linkCount == 1)
        #expect(status.modification == sampleModification)
        #if !canImport(Darwin)
            #expect(status.creation == nil)
        #endif
    }

    @Test func readsNegativeEpochModification() throws {
        let directory = try TemporaryDirectory()
        let url = try directory.write("a.bin", [1])
        let value = FileTimestamp(seconds: -2, nanoseconds: 500_000_000)
        try stamp(url, modification: value)
        #expect(try FileStatus.read(atPath: url.path).modification == value)
    }

    #if canImport(Darwin)
        @Test func readsCreationTimeOnDarwin() throws {
            let directory = try TemporaryDirectory()
            let url = try directory.write("a.bin", [1, 2, 3])
            try stamp(url, modification: sampleModification, creation: sampleCreation)
            let status = try FileStatus.read(atPath: url.path)
            #expect(status.creation == sampleCreation)
            #expect(status.modification == sampleModification)
        }
    #endif

    @Test func doesNotFollowFinalSymbolicLink() throws {
        let directory = try TemporaryDirectory()
        try directory.write("target.bin", [1, 2, 3, 4, 5])
        try FileManager.default.createSymbolicLink(
            atPath: directory.path + "/link.bin", withDestinationPath: directory.path + "/target.bin")
        #expect(try FileStatus.read(atPath: directory.path + "/link.bin").kind == .symbolicLink)
        #expect(try FileStatus.read(atPath: directory.path).kind == .directory)
    }

    @Test func mapsErrorsFromErrno() throws {
        let directory = try TemporaryDirectory()
        let missing = directory.path + "/nothing"
        #expect(throws: FileStatusError.missing(path: missing)) { try FileStatus.read(atPath: missing) }
        try directory.write("file", [1])
        let underFile = directory.path + "/file/child"
        #expect(throws: FileStatusError.missing(path: underFile)) { try FileStatus.read(atPath: underFile) }
        let locked = directory.path + "/locked"
        try FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: true)
        try directory.write("locked/inner", [1])
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked) }
        if geteuid() != 0 {
            #expect(throws: FileStatusError.permissionDenied(path: locked + "/inner")) {
                try FileStatus.read(atPath: locked + "/inner")
            }
        }
        let long = directory.path + "/" + String(repeating: "x", count: 5000)
        #expect(throws: FileStatusError.other(path: long, errno: ENAMETOOLONG)) { try FileStatus.read(atPath: long) }
    }
}
