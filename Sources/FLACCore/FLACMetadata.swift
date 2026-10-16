import Foundation

/// Failures of FLAC metadata parsing.
public enum FLACError: Error, Equatable, Sendable, CustomStringConvertible {
    case notFLAC
    case truncatedBlock(type: Int, offset: Int, declared: Int, available: Int)
    case missingStreamInformation
    case invalidBlock(type: Int, reason: String)

    public var description: String {
        switch self {
        case .notFLAC: "the file is not a FLAC stream"
        case .truncatedBlock(let type, let offset, let declared, let available):
            "metadata block \(type) at offset \(offset) declares \(declared) bytes, but only \(available) remain"
        case .missingStreamInformation: "the stream has no STREAMINFO block"
        case .invalidBlock(let type, let reason): "invalid metadata block \(type): \(reason)"
        }
    }
}

/// The STREAMINFO block.
public struct FLACStreamInformation: Equatable, Sendable {
    public var sampleRate: Int
    public var channels: Int
    public var bitsPerSample: Int
    /// The total number of inter-channel samples (frames); 0 means that the encoder did not know it.
    public var totalFrames: UInt64
    public var md5: Data
}

/// A PICTURE block.
public struct FLACPicture: Equatable, Sendable {
    /// The picture type of ID3v2 APIC frames; 3 is the front cover.
    public var type: Int
    public var mimeType: String
    public var description: String
    public var width: Int
    public var height: Int
    public var depth: Int
    public var colors: Int
    public var data: Data
}

/// The metadata of a FLAC stream, read without decoding audio. Foundation only (decision 6).
public struct FLACMetadata: Equatable, Sendable {
    public var streamInformation: FLACStreamInformation
    public var vendor: String?
    /// Vorbis comments in stream order. Field names are case-insensitive; their case is preserved.
    public var comments: [(name: String, value: String)]
    public var pictures: [FLACPicture]
    /// Types and lengths of other blocks, such as PADDING (1), APPLICATION (2), SEEKTABLE (3), and CUESHEET (5).
    public var otherBlocks: [(type: Int, length: Int)]
    /// The offset of the first audio frame.
    public var audioOffset: Int

    public static func == (lhs: FLACMetadata, rhs: FLACMetadata) -> Bool {
        lhs.streamInformation == rhs.streamInformation && lhs.vendor == rhs.vendor
            && lhs.comments.map { [$0.name, $0.value] } == rhs.comments.map { [$0.name, $0.value] }
            && lhs.pictures == rhs.pictures
            && lhs.otherBlocks.map { [$0.type, $0.length] } == rhs.otherBlocks.map { [$0.type, $0.length] }
            && lhs.audioOffset == rhs.audioOffset
    }

    /// The values of a Vorbis comment field, compared case-insensitively, in stream order.
    public func values(_ name: String) -> [String] {
        comments.filter { $0.name.uppercased() == name.uppercased() }.map(\.value)
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public init(data source: Data) throws {
        let data = source.startIndex == 0 ? source : Data(source)
        var offset = FLACMetadata.skipID3v2(data)
        guard data.count >= offset + 4, data.subdata(in: offset..<(offset + 4)) == Data("fLaC".utf8) else {
            throw FLACError.notFLAC
        }
        offset += 4
        var information: FLACStreamInformation?
        var vendor: String?
        var comments: [(name: String, value: String)] = []
        var pictures: [FLACPicture] = []
        var otherBlocks: [(type: Int, length: Int)] = []
        var last = false
        while !last {
            guard offset + 4 <= data.count else {
                throw FLACError.truncatedBlock(type: -1, offset: offset, declared: 4, available: data.count - offset)
            }
            last = data[offset] & 0x80 != 0
            let type = Int(data[offset] & 0x7F)
            let length = FLACMetadata.big(data, offset + 1, 3)
            let body = offset + 4
            guard body + length <= data.count else {
                throw FLACError.truncatedBlock(
                    type: type, offset: offset, declared: length, available: data.count - body)
            }
            let block = data.subdata(in: body..<(body + length))
            switch type {
            case 0:
                guard information == nil else { throw FLACError.invalidBlock(type: 0, reason: "repeated STREAMINFO") }
                information = try FLACMetadata.streamInformation(block)
            case 4:
                let parsed = try FLACMetadata.vorbisComments(block)
                vendor = parsed.vendor
                comments += parsed.comments
            case 6:
                pictures.append(try FLACMetadata.picture(block))
            case 127:
                throw FLACError.invalidBlock(type: type, reason: "reserved block type")
            default:
                otherBlocks.append((type, length))
            }
            offset = body + length
        }
        guard let information else { throw FLACError.missingStreamInformation }
        streamInformation = information
        self.vendor = vendor
        self.comments = comments
        self.pictures = pictures
        self.otherBlocks = otherBlocks
        audioOffset = offset
    }

    static func big(_ data: Data, _ offset: Int, _ width: Int) -> Int {
        (0..<width).reduce(0) { $0 << 8 | Int(data[offset + $1]) }
    }

    static func little(_ data: Data, _ offset: Int) -> Int {
        (0..<4).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
    }

    /// Some encoders prepend an ID3v2 tag; its size is a 28-bit synchsafe integer.
    static func skipID3v2(_ data: Data) -> Int {
        guard data.count >= 10, data.starts(with: Array("ID3".utf8)) else { return 0 }
        let size = (6..<10).reduce(0) { $0 << 7 | Int(data[$1] & 0x7F) }
        let footer = data[5] & 0x10 != 0 ? 10 : 0
        return 10 + size + footer
    }

    static func streamInformation(_ block: Data) throws -> FLACStreamInformation {
        guard block.count == 34 else {
            throw FLACError.invalidBlock(type: 0, reason: "STREAMINFO has \(block.count) bytes")
        }
        let rate = big(block, 10, 3) >> 4
        let channels = (Int(block[12]) >> 1 & 0x07) + 1
        let bits = ((Int(block[12]) & 0x01) << 4 | Int(block[13]) >> 4) + 1
        let frames = UInt64(block[13] & 0x0F) << 32 | UInt64(big(block, 14, 4))
        guard rate > 0 else { throw FLACError.invalidBlock(type: 0, reason: "sample rate 0") }
        return FLACStreamInformation(
            sampleRate: rate, channels: channels, bitsPerSample: bits, totalFrames: frames,
            md5: block.subdata(in: 18..<34))
    }

    static func vorbisComments(_ block: Data) throws -> (vendor: String, comments: [(name: String, value: String)]) {
        var cursor = 0
        func string() throws -> String {
            guard cursor + 4 <= block.count else { throw FLACError.invalidBlock(type: 4, reason: "truncated length") }
            let length = little(block, cursor)
            cursor += 4
            guard length >= 0, cursor + length <= block.count else {
                throw FLACError.invalidBlock(type: 4, reason: "truncated comment")
            }
            defer { cursor += length }
            return String(decoding: block.subdata(in: cursor..<(cursor + length)), as: UTF8.self)
        }
        let vendor = try string()
        guard cursor + 4 <= block.count else { throw FLACError.invalidBlock(type: 4, reason: "truncated count") }
        let count = little(block, cursor)
        cursor += 4
        var comments: [(name: String, value: String)] = []
        for _ in 0..<count {
            let field = try string()
            guard let separator = field.firstIndex(of: "=") else {
                throw FLACError.invalidBlock(type: 4, reason: "comment without a field name")
            }
            comments.append((String(field[..<separator]), String(field[field.index(after: separator)...])))
        }
        return (vendor, comments)
    }

    static func picture(_ block: Data) throws -> FLACPicture {
        var cursor = 0
        func integer() throws -> Int {
            guard cursor + 4 <= block.count else { throw FLACError.invalidBlock(type: 6, reason: "truncated picture") }
            defer { cursor += 4 }
            return big(block, cursor, 4)
        }
        func bytes(_ length: Int) throws -> Data {
            guard length >= 0, cursor + length <= block.count else {
                throw FLACError.invalidBlock(type: 6, reason: "truncated picture")
            }
            defer { cursor += length }
            return block.subdata(in: cursor..<(cursor + length))
        }
        let type = try integer()
        let mimeType = String(decoding: try bytes(try integer()), as: UTF8.self)
        let description = String(decoding: try bytes(try integer()), as: UTF8.self)
        let width = try integer()
        let height = try integer()
        let depth = try integer()
        let colors = try integer()
        let data = try bytes(try integer())
        return FLACPicture(
            type: type, mimeType: mimeType, description: description, width: width, height: height, depth: depth,
            colors: colors, data: data)
    }
}
