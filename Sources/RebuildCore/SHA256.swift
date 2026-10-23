import Foundation

/// A SHA-256 digest: 32 bytes, rendered as 64 lowercase hexadecimal digits.
public struct SHA256Digest: Equatable, Hashable, Codable, Sendable, CustomStringConvertible {
    public static let byteCount = 32

    public let bytes: [UInt8]

    /// Creates a digest from exactly 32 bytes; returns nil for any other length.
    public init?(bytes: [UInt8]) {
        guard bytes.count == SHA256Digest.byteCount else { return nil }
        self.bytes = bytes
    }

    /// Creates a digest from 64 hexadecimal digits (either case); returns nil for any other input.
    public init?(hex: String) {
        let digits = Array(hex.utf8)
        guard digits.count == 2 * SHA256Digest.byteCount else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(SHA256Digest.byteCount)
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let high = SHA256Digest.nibble(digits[index]), let low = SHA256Digest.nibble(digits[index + 1])
            else { return nil }
            result.append(high << 4 | low)
        }
        bytes = result
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let digest = SHA256Digest(hex: text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected 64 hexadecimal digits for a SHA-256 digest.")
        }
        self = digest
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    /// The lowercase hexadecimal representation.
    public var hex: String {
        let alphabet = Array("0123456789abcdef".utf8)
        var scalars: [UInt8] = []
        scalars.reserveCapacity(2 * bytes.count)
        for byte in bytes {
            scalars.append(alphabet[Int(byte >> 4)])
            scalars.append(alphabet[Int(byte & 0x0f)])
        }
        return String(decoding: scalars, as: UTF8.self)
    }

    public var description: String { hex }

    private static func nibble(_ digit: UInt8) -> UInt8? {
        switch digit {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return digit - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return digit - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return digit - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}

/// The failures of hashing a file.
public enum SHA256FileError: Error, Equatable, Sendable {
    case invalidChunkSize(Int)
    case missing(path: String)
    /// The path is a directory, a symbolic link, or another kind of entry that is not a regular file.
    case notRegularFile(path: String, kind: String)
    case readFailed(path: String, reason: String)
}

/// The result of hashing a file: the digest and the number of bytes hashed.
public struct SHA256FileResult: Equatable, Sendable {
    public let digest: SHA256Digest
    public let byteCount: UInt64
}

/// An incremental SHA-256 (FIPS 180-4). Any sequence of chunk sizes yields the same digest.
public struct SHA256: Sendable {
    /// The largest message length in bytes, so that the bit length fits in 64 bits.
    public static let maximumByteCount: UInt64 = 1 << 61

    private static let blockSize = 64

    private static let roundConstants: [UInt32] = [
        0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
        0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3, 0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
        0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
        0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7, 0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
        0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13, 0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
        0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
        0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
        0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208, 0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
    ]

    private var state: [UInt32] = [
        0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a, 0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
    ]
    private var pending: [UInt8] = []
    private var totalBytes: UInt64 = 0

    public init() {
        pending.reserveCapacity(SHA256.blockSize)
    }

    /// The number of bytes consumed so far.
    public var byteCount: UInt64 { totalBytes }

    public mutating func update(_ bytes: UnsafeRawBufferPointer) {
        guard !bytes.isEmpty else { return }
        let (sum, overflow) = totalBytes.addingReportingOverflow(UInt64(bytes.count))
        precondition(!overflow && sum <= SHA256.maximumByteCount, "SHA-256 input exceeds 2^61 bytes.")
        totalBytes = sum

        var offset = 0
        if !pending.isEmpty {
            let take = min(SHA256.blockSize - pending.count, bytes.count)
            pending.append(contentsOf: bytes[0..<take])
            offset = take
            if pending.count == SHA256.blockSize {
                pending.withUnsafeBytes { SHA256.compress(&state, $0.baseAddress!) }
                pending.removeAll(keepingCapacity: true)
            }
        }
        while bytes.count - offset >= SHA256.blockSize {
            SHA256.compress(&state, bytes.baseAddress! + offset)
            offset += SHA256.blockSize
        }
        if offset < bytes.count {
            pending.append(contentsOf: bytes[offset...])
        }
    }

    public mutating func update(_ data: some DataProtocol) {
        for region in data.regions {
            region.withUnsafeBytes { update($0) }
        }
    }

    public consuming func finalize() -> SHA256Digest {
        let bitLength = totalBytes << 3
        var tail = pending
        tail.append(0x80)
        while tail.count % SHA256.blockSize != SHA256.blockSize - 8 {
            tail.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            tail.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }
        var words = state
        tail.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                SHA256.compress(&words, buffer.baseAddress! + offset)
                offset += SHA256.blockSize
            }
        }
        var out: [UInt8] = []
        out.reserveCapacity(SHA256Digest.byteCount)
        for word in words {
            out.append(UInt8(truncatingIfNeeded: word >> 24))
            out.append(UInt8(truncatingIfNeeded: word >> 16))
            out.append(UInt8(truncatingIfNeeded: word >> 8))
            out.append(UInt8(truncatingIfNeeded: word))
        }
        return SHA256Digest(bytes: out)!
    }

    /// Returns the digest of a complete in-memory message.
    public static func digest(of data: some DataProtocol) -> SHA256Digest {
        var hasher = SHA256()
        hasher.update(data)
        return hasher.finalize()
    }

    /// Processes one 64-byte block.
    private static func compress(_ state: inout [UInt32], _ block: UnsafeRawPointer) {
        withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 64) { w in
            for index in 0..<16 {
                let base = block + 4 * index
                let b0 = UInt32(base.load(fromByteOffset: 0, as: UInt8.self))
                let b1 = UInt32(base.load(fromByteOffset: 1, as: UInt8.self))
                let b2 = UInt32(base.load(fromByteOffset: 2, as: UInt8.self))
                let b3 = UInt32(base.load(fromByteOffset: 3, as: UInt8.self))
                w[index] = b0 << 24 | b1 << 16 | b2 << 8 | b3
            }
            for index in 16..<64 {
                let x = w[index - 15]
                let y = w[index - 2]
                let s0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)
                let s1 = rotr(y, 17) ^ rotr(y, 19) ^ (y >> 10)
                w[index] = w[index - 16] &+ s0 &+ w[index - 7] &+ s1
            }
            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            var e = state[4]
            var f = state[5]
            var g = state[6]
            var h = state[7]
            roundConstants.withUnsafeBufferPointer { k in
                for index in 0..<64 {
                    let sigma1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                    let choose = (e & f) ^ (~e & g)
                    let t1 = h &+ sigma1 &+ choose &+ k[index] &+ w[index]
                    let sigma0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                    let majority = (a & b) ^ (a & c) ^ (b & c)
                    let t2 = sigma0 &+ majority
                    h = g
                    g = f
                    f = e
                    e = d &+ t1
                    d = c
                    c = b
                    b = a
                    a = t1 &+ t2
                }
            }
            state[0] = state[0] &+ a
            state[1] = state[1] &+ b
            state[2] = state[2] &+ c
            state[3] = state[3] &+ d
            state[4] = state[4] &+ e
            state[5] = state[5] &+ f
            state[6] = state[6] &+ g
            state[7] = state[7] &+ h
        }
    }

    @inline(__always)
    private static func rotr(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}

extension SHA256 {
    /// Streams a regular file through the hash in chunks of at most `chunkSize` bytes and returns the digest.
    public static func digest(fileAt url: URL, chunkSize: Int = 1 << 20) throws -> SHA256Digest {
        try hash(fileAt: url, chunkSize: chunkSize).digest
    }

    /// Streams a regular file through the hash and returns the digest with the number of bytes hashed.
    /// Memory use is bounded by `chunkSize`. A missing path, a path that is itself a symbolic link, and any
    /// other entry that is not a regular file are refused.
    public static func hash(fileAt url: URL, chunkSize: Int = 1 << 20) throws -> SHA256FileResult {
        guard chunkSize > 0 else { throw SHA256FileError.invalidChunkSize(chunkSize) }
        let path = url.path
        let attributes: [FileAttributeKey: Any]
        do {
            // attributesOfItem does not follow a symbolic link at the final path component.
            attributes = try FileManager.default.attributesOfItem(atPath: path)
        } catch {
            if let cocoa = error as? CocoaError, cocoa.code == .fileNoSuchFile || cocoa.code == .fileReadNoSuchFile {
                throw SHA256FileError.missing(path: path)
            }
            throw SHA256FileError.readFailed(path: path, reason: String(describing: error))
        }
        let type = attributes[.type] as? FileAttributeType
        guard type == .typeRegular else {
            throw SHA256FileError.notRegularFile(path: path, kind: type?.rawValue ?? "unknown")
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw SHA256FileError.readFailed(path: path, reason: String(describing: error))
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                hasher.update(chunk)
            }
        } catch {
            throw SHA256FileError.readFailed(path: path, reason: String(describing: error))
        }
        let count = hasher.byteCount
        return SHA256FileResult(digest: hasher.finalize(), byteCount: count)
    }
}
