import Foundation
import Testing

@testable import RebuildCore

/// A deterministic xorshift64* generator, so that test data is identical on every platform.
struct SeededGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9e37_79b9_7f4a_7c15 : seed }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_f491_4f6c_dd1d
    }

    mutating func bytes(_ count: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: count)
        var index = 0
        while index < count {
            var word = next()
            for _ in 0..<8 where index < count {
                result[index] = UInt8(truncatingIfNeeded: word)
                word >>= 8
                index += 1
            }
        }
        return result
    }
}

private func hexDigest(_ text: String) -> String {
    SHA256.digest(of: Array(text.utf8)).hex
}

func chunked(_ data: [UInt8], sizes: [Int]) -> SHA256Digest {
    var hasher = SHA256()
    var offset = 0
    var turn = 0
    while offset < data.count {
        let size = min(sizes[turn % sizes.count], data.count - offset)
        data[offset..<offset + size].withUnsafeBytes { hasher.update($0) }
        offset += size
        turn += 1
    }
    return hasher.finalize()
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ilibrary-sha256-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct SHA256VectorTests {
    @Test func emptyMessage() {
        #expect(hexDigest("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func abc() {
        #expect(hexDigest("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func fourHundredFortyEightBitMessage() {
        let message = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
        #expect(message.utf8.count * 8 == 448)
        #expect(hexDigest(message) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    @Test func eightHundredNinetySixBitMessage() {
        let message =
            "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
        #expect(message.utf8.count * 8 == 896)
        #expect(hexDigest(message) == "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1")
    }

    @Test func oneMillionRepetitionsOfA() {
        var hasher = SHA256()
        let block = [UInt8](repeating: UInt8(ascii: "a"), count: 1000)
        for _ in 0..<1000 { hasher.update(block) }
        #expect(hasher.byteCount == 1_000_000)
        #expect(hasher.finalize().hex == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
}

@Suite struct SHA256IncrementalTests {
    @Test func everySplitPointMatchesOneShotForShortMessages() {
        var generator = SeededGenerator(seed: 7)
        for length in 0...130 {
            let message = generator.bytes(length)
            let expected = SHA256.digest(of: message)
            for split in 0...length {
                var hasher = SHA256()
                message[0..<split].withUnsafeBytes { hasher.update($0) }
                hasher.update(Data(message[split...]))
                #expect(hasher.finalize() == expected, "length \(length), split \(split)")
            }
        }
    }

    @Test func chunkSizeSequencesYieldTheSameDigest() {
        var generator = SeededGenerator(seed: 0x1234_5678)
        let message = generator.bytes(100_003)
        let expected = SHA256.digest(of: message)
        let sequences = [[1], [63], [64], [65], [4096], [1, 63, 64, 65, 4096], [4096, 1, 65, 64, 63], [7, 129, 3]]
        for sizes in sequences {
            #expect(chunked(message, sizes: sizes) == expected, "sizes \(sizes)")
        }
    }

    @Test func emptyUpdatesDoNotChangeTheDigest() {
        var hasher = SHA256()
        hasher.update(Data())
        hasher.update(UnsafeRawBufferPointer(start: nil, count: 0))
        #expect(hasher.finalize().hex == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}

@Suite struct SHA256DigestTests {
    @Test func hexRoundTrip() throws {
        let digest = SHA256.digest(of: Array("abc".utf8))
        let parsed = try #require(SHA256Digest(hex: digest.hex))
        #expect(parsed == digest)
        #expect(digest.description == digest.hex)
        #expect(digest.hex.count == 64)
        #expect(SHA256Digest(hex: digest.hex.uppercased()) == digest)
        #expect(Set([digest, parsed]).count == 1)
    }

    @Test func invalidHexIsRejected() {
        let valid = String(repeating: "ab", count: 32)
        #expect(SHA256Digest(hex: valid) != nil)
        #expect(SHA256Digest(hex: "") == nil)
        #expect(SHA256Digest(hex: String(valid.dropLast())) == nil)
        #expect(SHA256Digest(hex: valid + "0") == nil)
        #expect(SHA256Digest(hex: String(repeating: "g", count: 64)) == nil)
        #expect(SHA256Digest(hex: " " + valid.dropFirst()) == nil)
        #expect(SHA256Digest(hex: String(repeating: "é", count: 32)) == nil)
        #expect(SHA256Digest(bytes: [UInt8](repeating: 0, count: 31)) == nil)
    }

    @Test func codableUsesTheHexString() throws {
        let digest = SHA256.digest(of: Array("abc".utf8))
        let encoded = try JSONEncoder().encode([digest])
        #expect(String(decoding: encoded, as: UTF8.self) == "[\"\(digest.hex)\"]")
        #expect(try JSONDecoder().decode([SHA256Digest].self, from: encoded) == [digest])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([SHA256Digest].self, from: Data("[\"zz\"]".utf8))
        }
    }
}

@Suite struct SHA256FileTests {
    @Test func emptyFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("empty")
        try Data().write(to: url)
        let result = try SHA256.hash(fileAt: url)
        #expect(result.byteCount == 0)
        #expect(result.digest.hex == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func fileOfExactlyOneBlock() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var generator = SeededGenerator(seed: 99)
        let content = generator.bytes(64)
        let url = directory.appendingPathComponent("block")
        try Data(content).write(to: url)
        for chunk in [1, 63, 64, 65, 4096] {
            let result = try SHA256.hash(fileAt: url, chunkSize: chunk)
            #expect(result.byteCount == 64)
            #expect(result.digest == SHA256.digest(of: content))
        }
    }

    @Test func largeFileMatchesTheDigestComputedWhileWriting() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("large")
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        var generator = SeededGenerator(seed: 2026)
        var expected = SHA256()
        let handle = try FileHandle(forWritingTo: url)
        var written: UInt64 = 0
        let sizes = [1_048_576, 999_983, 65_537, 1_310_720]
        var turn = 0
        while written < 17 * 1_048_576 {
            let piece = generator.bytes(sizes[turn % sizes.count])
            try handle.write(contentsOf: piece)
            expected.update(piece)
            written += UInt64(piece.count)
            turn += 1
        }
        try handle.close()
        #expect(written >= 16 * 1_048_576)
        let digest = expected.finalize()
        for chunk in [4096, 1 << 20] {
            let result = try SHA256.hash(fileAt: url, chunkSize: chunk)
            #expect(result.byteCount == written)
            #expect(result.digest == digest)
        }
        #expect(try SHA256.digest(fileAt: url) == digest)
    }

    @Test func missingFileIsReported() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("absent")
        #expect(throws: SHA256FileError.missing(path: url.path)) { try SHA256.digest(fileAt: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func directoryIsRefused() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try SHA256.digest(fileAt: directory)
            Issue.record("A directory must be refused.")
        } catch let error as SHA256FileError {
            guard case .notRegularFile(let path, _) = error else {
                Issue.record("Unexpected error \(error).")
                return
            }
            #expect(path == directory.path)
        }
    }

    @Test func symbolicLinkIsRefusedEvenWhenItsTargetIsRegular() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        try Data("abc".utf8).write(to: target)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        do {
            _ = try SHA256.digest(fileAt: link)
            Issue.record("A symbolic link must be refused.")
        } catch let error as SHA256FileError {
            guard case .notRegularFile(let path, _) = error else {
                Issue.record("Unexpected error \(error).")
                return
            }
            #expect(path == link.path)
        }
    }

    @Test func nonPositiveChunkSizeIsRefused() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("file")
        try Data("abc".utf8).write(to: url)
        #expect(throws: SHA256FileError.invalidChunkSize(0)) { try SHA256.digest(fileAt: url, chunkSize: 0) }
        #expect(throws: SHA256FileError.invalidChunkSize(-1)) { try SHA256.digest(fileAt: url, chunkSize: -1) }
    }

    @Test func unreadableFileIsReportedUnlessRunningAsRoot() throws {
        guard getuid() != 0 else { return }
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("secret")
        try Data("abc".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        do {
            _ = try SHA256.digest(fileAt: url)
            Issue.record("An unreadable file must fail.")
        } catch let error as SHA256FileError {
            guard case .readFailed = error else {
                Issue.record("Unexpected error \(error).")
                return
            }
        }
    }
}
