import FLACCore
import Foundation
import Testing

/// Builds the metadata of a synthetic FLAC stream followed by placeholder frame bytes.
struct SyntheticFLAC {
    var sampleRate = 176_400
    var channels = 2
    var bitsPerSample = 24
    var totalFrames: UInt64 = 51_826_701
    var comments = ["TITLE=Synthetic Song", "ARTIST=Example Artist", "artist=Second Artist", "DATE=2009-06-25"]
    var picture: Data? = Data([0x89, 0x50, 0x4E, 0x47]) + Data(count: 60)
    var padding = 1_024
    var id3Prefix = false
    var includeStreamInformation = true

    static func block(_ type: Int, last: Bool, _ body: Data) -> Data {
        var data = Data([UInt8(type) | (last ? 0x80 : 0)])
        data.append(contentsOf: [
            UInt8(body.count >> 16 & 0xFF), UInt8(body.count >> 8 & 0xFF), UInt8(body.count & 0xFF),
        ])
        return data + body
    }

    static func little(_ value: Int) -> Data { Data((0..<4).map { UInt8(value >> (8 * $0) & 0xFF) }) }
    static func big(_ value: Int) -> Data { Data((0..<4).map { UInt8(value >> (8 * (3 - $0)) & 0xFF) }) }

    var streamInformation: Data {
        var data = Data([0x10, 0x00, 0x10, 0x00, 0x00, 0x00, 0x0E, 0x00, 0x40, 0x00])
        let packed =
            UInt64(sampleRate) << 44 | UInt64(channels - 1) << 41 | UInt64(bitsPerSample - 1) << 36 | totalFrames
        data.append(contentsOf: (0..<8).map { UInt8(truncatingIfNeeded: packed >> UInt64(8 * (7 - $0))) })
        data.append(Data((0..<16).map { UInt8($0) }))
        return data
    }

    var data: Data {
        var blocks: [(Int, Data)] = []
        if includeStreamInformation { blocks.append((0, streamInformation)) }
        var vorbis = SyntheticFLAC.little(9) + Data("synthetic".utf8) + SyntheticFLAC.little(comments.count)
        for comment in comments { vorbis += SyntheticFLAC.little(comment.utf8.count) + Data(comment.utf8) }
        blocks.append((4, vorbis))
        if let picture {
            var body = SyntheticFLAC.big(3) + SyntheticFLAC.big(9) + Data("image/png".utf8)
            body += SyntheticFLAC.big(5) + Data("Cover".utf8)
            body += SyntheticFLAC.big(600) + SyntheticFLAC.big(600) + SyntheticFLAC.big(24) + SyntheticFLAC.big(0)
            body += SyntheticFLAC.big(picture.count) + picture
            blocks.append((6, body))
        }
        if padding > 0 { blocks.append((1, Data(count: padding))) }
        var data = Data()
        if id3Prefix { data += Data("ID3".utf8) + Data([4, 0, 0, 0, 0, 0, 20]) + Data(count: 20) }
        data += Data("fLaC".utf8)
        for (index, (type, body)) in blocks.enumerated() {
            data += SyntheticFLAC.block(type, last: index == blocks.count - 1, body)
        }
        return data + Data([0xFF, 0xF8]) + Data(count: 100)
    }
}

@Suite struct FLACMetadataTests {
    @Test func streamInformationIsDecoded() throws {
        let metadata = try FLACMetadata(data: SyntheticFLAC().data)
        let information = metadata.streamInformation
        #expect(information.sampleRate == 176_400)
        #expect(information.channels == 2)
        #expect(information.bitsPerSample == 24)
        #expect(information.totalFrames == 51_826_701)
        #expect(information.md5 == Data((0..<16).map { UInt8($0) }))
    }

    @Test(arguments: [
        (44_100, 1, 16, UInt64(1_324_237)), (192_000, 2, 24, UInt64(1) << 35 + 7), (48_000, 8, 20, UInt64(0)),
    ])
    func streamInformationCoversTheFieldRanges(rate: Int, channels: Int, bits: Int, frames: UInt64) throws {
        var fixture = SyntheticFLAC()
        fixture.sampleRate = rate
        fixture.channels = channels
        fixture.bitsPerSample = bits
        fixture.totalFrames = frames
        let information = try FLACMetadata(data: fixture.data).streamInformation
        let format: [Int] = [information.sampleRate, information.channels, information.bitsPerSample]
        #expect(format == [rate, channels, bits])
        #expect(information.totalFrames == frames)
    }

    @Test func commentsKeepOrderAndMatchNamesWithoutCase() throws {
        let metadata = try FLACMetadata(data: SyntheticFLAC().data)
        #expect(metadata.vendor == "synthetic")
        #expect(metadata.comments.map { $0.name } == ["TITLE", "ARTIST", "artist", "DATE"])
        #expect(metadata.values("Artist") == ["Example Artist", "Second Artist"])
        #expect(metadata.values("title") == ["Synthetic Song"])
    }

    @Test func picturesAreRead() throws {
        let fixture = SyntheticFLAC()
        let picture = try #require(try FLACMetadata(data: fixture.data).pictures.first)
        #expect(picture.type == 3)
        #expect(picture.mimeType == "image/png")
        #expect(picture.description == "Cover")
        let geometry: [Int] = [picture.width, picture.height, picture.depth, picture.colors]
        #expect(geometry == [600, 600, 24, 0])
        #expect(picture.data == fixture.picture)
    }

    @Test func otherBlocksAndTheAudioOffsetAreReported() throws {
        let fixture = SyntheticFLAC()
        let metadata = try FLACMetadata(data: fixture.data)
        #expect(metadata.otherBlocks.map { $0.type } == [1])
        #expect(metadata.otherBlocks.map { $0.length } == [1_024])
        #expect(fixture.data[metadata.audioOffset] == 0xFF)
    }

    @Test func anID3v2PrefixIsSkipped() throws {
        var fixture = SyntheticFLAC()
        fixture.id3Prefix = true
        #expect(try FLACMetadata(data: fixture.data).values("TITLE") == ["Synthetic Song"])
    }

    @Test func truncatedMetadataIsRejected() throws {
        let data = SyntheticFLAC().data
        for length in [10, 50, 200, 600] {
            #expect(throws: FLACError.self) { try FLACMetadata(data: data.prefix(length)) }
        }
    }

    @Test func otherInputsAreRejected() throws {
        #expect(throws: FLACError.notFLAC) { try FLACMetadata(data: Data("RIFF....WAVE".utf8)) }
        var fixture = SyntheticFLAC()
        fixture.includeStreamInformation = false
        #expect(throws: FLACError.missingStreamInformation) { try FLACMetadata(data: fixture.data) }
        fixture = SyntheticFLAC()
        fixture.comments = ["NOSEPARATOR"]
        #expect(throws: FLACError.self) { try FLACMetadata(data: fixture.data) }
    }
}
