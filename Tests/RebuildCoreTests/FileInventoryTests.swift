import Foundation
import Testing

@testable import RebuildCore

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

private func album(in directory: TemporaryDirectory) throws {
    try directory.write("B/two.m4a", Array("second".utf8))
    try directory.write("A/one.M4A", Array("first track".utf8))
    try directory.write("A/cover.jpg", [9, 9])
    try directory.write("A/.hidden.m4a", [1])
    try directory.write(".Trash/gone.m4a", [1])
    try directory.write("top.m4a", [])
    try stamp(directory.file("B/two.m4a"), modification: sampleModification, creation: sampleCreation)
    try stamp(directory.file("A/one.M4A"), modification: sampleModification, creation: sampleCreation)
    try stamp(directory.file("top.m4a"), modification: sampleModification, creation: sampleCreation)
}

@Suite struct FileInventoryTests {
    @Test func inventoriesNestedFilesSortedWithDigests() throws {
        let directory = try TemporaryDirectory()
        try album(in: directory)
        let inventory = try FileInventory(root: directory.url, selecting: ["top.m4a", "B/two.m4a", "A/one.M4A"])
        #expect(inventory.records.map(\.path) == ["A/one.M4A", "B/two.m4a", "top.m4a"])
        #expect(inventory.records[0].sha256 == SHA256.digest(of: Array("first track".utf8)))
        #expect(inventory.records[0].size == 11)
        #expect(inventory.records[2].sha256 == SHA256.digest(of: [UInt8]()))
        #expect(inventory.records[2].size == 0)
        #expect(inventory.records[1].modification == sampleModification)
        #if canImport(Darwin)
            #expect(inventory.records[1].creation == sampleCreation)
        #else
            #expect(inventory.records[1].creation == nil)
        #endif
    }

    @Test func discoversExtensionsCaseInsensitivelySkippingHiddenEntries() throws {
        let directory = try TemporaryDirectory()
        try album(in: directory)
        let inventory = try FileInventory(root: directory.url, extensions: ["m4a"])
        #expect(inventory.records.map(\.path) == ["A/one.M4A", "B/two.m4a", "top.m4a"])
        let both = try FileInventory(root: directory.url, extensions: [".JPG", "m4a"])
        #expect(both.records.map(\.path) == ["A/cover.jpg", "A/one.M4A", "B/two.m4a", "top.m4a"])
    }

    @Test func recordsRoundTripThroughCodable() throws {
        let directory = try TemporaryDirectory()
        try album(in: directory)
        let inventory = try FileInventory(root: directory.url, selecting: ["A/one.M4A"])
        let data = try JSONEncoder().encode(inventory.records)
        #expect(try JSONDecoder().decode([FileRecord].self, from: data) == inventory.records)
    }

    @Test func normalizesRecordedPathToNFC() throws {
        let directory = try TemporaryDirectory()
        let decomposed = "Caf\u{65}\u{301}/track.m4a"
        try directory.write(decomposed, [1, 2])
        let inventory = try FileInventory(root: directory.url, selecting: [decomposed])
        #expect(inventory.records.map(\.path) == ["Caf\u{E9}/track.m4a"])
    }

    @Test func refusesMissingFile() throws {
        let directory = try TemporaryDirectory()
        try album(in: directory)
        #expect(throws: FileInventoryError.missing(path: "A/none.m4a")) {
            try FileInventory(root: directory.url, selecting: ["A/one.M4A", "A/none.m4a"])
        }
        #expect(throws: FileInventoryError.missing(path: "Z/none.m4a")) {
            try FileInventory(root: directory.url, selecting: ["Z/none.m4a"])
        }
    }

    @Test func refusesSymbolicLinkedFileAndDirectory() throws {
        let directory = try TemporaryDirectory()
        try album(in: directory)
        try FileManager.default.createSymbolicLink(
            atPath: directory.path + "/link.m4a", withDestinationPath: directory.path + "/top.m4a")
        try FileManager.default.createSymbolicLink(
            atPath: directory.path + "/Linked", withDestinationPath: directory.path + "/A")
        #expect(throws: FileInventoryError.symbolicLink(path: "link.m4a")) {
            try FileInventory(root: directory.url, selecting: ["link.m4a"])
        }
        #expect(throws: FileInventoryError.symbolicLink(path: "Linked")) {
            try FileInventory(root: directory.url, selecting: ["Linked/one.M4A"])
        }
        #expect(throws: FileInventoryError.symbolicLink(path: "Linked")) {
            try FileInventory(root: directory.url, extensions: ["m4a"])
        }
    }

    @Test func refusesSymbolicLinkedRoot() throws {
        let directory = try TemporaryDirectory()
        try album(in: directory)
        let link = directory.path + "/rootlink"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: directory.path + "/A")
        #expect(throws: FileInventoryError.rootIsSymbolicLink(path: link)) {
            try FileInventory(root: URL(fileURLWithPath: link), selecting: ["one.M4A"])
        }
        let missing = directory.path + "/absent"
        #expect(throws: FileInventoryError.rootMissing(path: missing)) {
            try FileInventory(root: URL(fileURLWithPath: missing), selecting: [])
        }
        let file = directory.path + "/top.m4a"
        #expect(throws: FileInventoryError.rootNotDirectory(path: file)) {
            try FileInventory(root: URL(fileURLWithPath: file), selecting: [])
        }
    }

    @Test func refusesNonRegularEntries() throws {
        let directory = try TemporaryDirectory()
        try album(in: directory)
        #expect(throws: FileInventoryError.notRegularFile(path: "A", kind: .directory)) {
            try FileInventory(root: directory.url, selecting: ["A"])
        }
        #expect(mkfifo(directory.path + "/pipe.m4a", 0o600) == 0)
        #expect(throws: FileInventoryError.notRegularFile(path: "pipe.m4a", kind: .fifo)) {
            try FileInventory(root: directory.url, selecting: ["pipe.m4a"])
        }
        #expect(throws: FileInventoryError.notRegularFile(path: "pipe.m4a", kind: .fifo)) {
            try FileInventory(root: directory.url, extensions: ["m4a"])
        }
        // A file used as a directory component is not a directory.
        #expect(throws: FileInventoryError.notRegularFile(path: "top.m4a/x.m4a", kind: .regular)) {
            try FileInventory(root: directory.url, selecting: ["top.m4a/x.m4a"])
        }
    }

    @Test func refusesPathsThatEscapeOrAreMalformed() throws {
        let directory = try TemporaryDirectory()
        try album(in: directory)
        for path in ["../x.m4a", "A/../../x.m4a", "/etc/hosts", "A/.."] {
            #expect(throws: FileInventoryError.escapesRoot(path: path), "\(path)") {
                try FileInventory(root: directory.url, selecting: [path])
            }
        }
        for path in ["", "A//one.M4A", "./top.m4a", "A/./one.M4A", "A/"] {
            #expect(throws: FileInventoryError.invalidPath(path: path), "\(path)") {
                try FileInventory(root: directory.url, selecting: [path])
            }
        }
    }

    @Test func refusesNormalizationAndCaseCollisions() throws {
        let directory = try TemporaryDirectory()
        let composed = "\u{E9}.m4a"
        let decomposed = "e\u{301}.m4a"
        #expect(throws: FileInventoryError.collision(path: decomposed, other: composed, kind: .normalization)) {
            try FileInventory(root: directory.url, selecting: [composed, decomposed])
        }
        #expect(throws: FileInventoryError.collision(path: "a.m4a", other: "A.m4a", kind: .caseFolding)) {
            try FileInventory(root: directory.url, selecting: ["A.m4a", "a.m4a"])
        }
        #expect(throws: FileInventoryError.collision(path: "x/y.m4a", other: "x/y.m4a", kind: .normalization)) {
            try FileInventory(root: directory.url, selecting: ["x/y.m4a", "x/y.m4a"])
        }
    }

    @Test func collisionDetectorOnPathStrings() {
        #expect(FileInventory.findCollision(in: []) == nil)
        #expect(FileInventory.findCollision(in: ["a/b.m4a", "a/c.m4a", "b/b.m4a"]) == nil)
        #expect(FileInventory.findCollision(in: ["\u{E9}", "e\u{301}"])?.kind == .normalization)
        #expect(FileInventory.findCollision(in: ["Album/Track.m4a", "album/track.m4a"])?.kind == .caseFolding)
        // Case and normalization together.
        #expect(FileInventory.findCollision(in: ["\u{C9}.m4a", "e\u{301}.m4a"])?.kind == .caseFolding)
        // Different directories are different paths.
        #expect(FileInventory.findCollision(in: ["a/x.m4a", "b/x.m4a"]) == nil)
    }

    @Test func stabilityComparison() {
        let base = FileStatus(
            kind: .regular, size: 10, inode: 5, device: 1, linkCount: 1, modification: sampleModification,
            creation: nil)
        #expect(FileInventory.isStable(before: base, after: base, hashedBytes: 10))
        #expect(!FileInventory.isStable(before: base, after: base, hashedBytes: 11))
        let grown = FileStatus(
            kind: .regular, size: 11, inode: 5, device: 1, linkCount: 1, modification: sampleModification,
            creation: nil)
        #expect(!FileInventory.isStable(before: base, after: grown, hashedBytes: 10))
        let touched = FileStatus(
            kind: .regular, size: 10, inode: 5, device: 1, linkCount: 1,
            modification: FileTimestamp(seconds: sampleModification.seconds, nanoseconds: 1), creation: nil)
        #expect(!FileInventory.isStable(before: base, after: touched, hashedBytes: 10))
    }

    @Test func refusesFileThatChangesWhileHashed() throws {
        let directory = try TemporaryDirectory()
        try album(in: directory)
        #expect(throws: FileInventoryError.unstable(path: "top.m4a")) {
            try FileInventory.build(root: directory.url, relativePaths: ["top.m4a"]) { _ in
                try? Data([1]).write(to: directory.file("top.m4a"))
            }
        }
        // A change of the modification time alone is also refused.
        #expect(throws: FileInventoryError.unstable(path: "B/two.m4a")) {
            try FileInventory.build(root: directory.url, relativePaths: ["B/two.m4a"]) { _ in
                try? stamp(directory.file("B/two.m4a"), modification: FileTimestamp(seconds: 1_200_000_000))
            }
        }
        // An unchanged file passes through the same hook.
        let ok = try FileInventory.build(root: directory.url, relativePaths: ["B/two.m4a"]) { _ in }
        #expect(ok.records.count == 1)
    }
}
