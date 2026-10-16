import Foundation

/// Deterministic synthetic PCM written as WAV or AIFF. The signal combines alternating full-scale extremes,
/// digital silence, tones, and noise, so that lossless round trips exercise every bit of each sample.
public struct SyntheticAudio {
    public var sampleRate = 44_100
    public var bits = 16
    public var channels = 2
    public var frames = 44_117
    public var seed: UInt64 = 1

    public init(sampleRate: Int = 44_100, bits: Int = 16, channels: Int = 2, frames: Int = 44_117, seed: UInt64 = 1) {
        self.sampleRate = sampleRate
        self.bits = bits
        self.channels = channels
        self.frames = frames
        self.seed = seed
    }

    public var samples: [Int32] {
        let maximum = Int32((Int64(1) << (bits - 1)) - 1)
        let minimum = -maximum - 1
        var state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
        var result = [Int32](repeating: 0, count: frames * channels)
        let silence = (frames / 2)..<min(frames, frames / 2 + sampleRate / 20)
        for frame in 0..<frames {
            for channel in 0..<channels {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let value: Int32
                if frame < 64 {
                    value = (frame + channel) % 2 == 0 ? maximum : minimum
                } else if silence.contains(frame) {
                    value = 0
                } else {
                    let time = Double(frame) / Double(sampleRate)
                    let tone = 0.45 * sin(2 * Double.pi * 220 * Double(channel + 1) * time)
                    let noise = Double(Int64((state >> 11) % 2_000_001) - 1_000_000) / 1_000_000 * 0.05
                    value = Int32((tone + noise) * Double(maximum))
                }
                result[frame * channels + channel] = value
            }
        }
        return result
    }

    func pcm(bigEndian: Bool) -> Data {
        var data = Data(capacity: frames * channels * bits / 8)
        for sample in samples {
            let value = UInt32(bitPattern: sample)
            var bytes = (0..<(bits / 8)).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) }
            if bigEndian { bytes.reverse() }
            data.append(contentsOf: bytes)
        }
        return data
    }

    static func little<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
    static func big<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }

    /// A WAV file; WAVE_FORMAT_EXTENSIBLE is used for more than 16 bits or two channels. With `floatingPoint`,
    /// the samples are written as 32-bit IEEE floats instead.
    public func wave(floatingPoint: Bool = false) -> Data {
        var body: Data
        var format: UInt16 = 1
        var depth = bits
        if floatingPoint {
            body = Data()
            let scale = Float(Int64(1) << (bits - 1))
            for sample in samples { body.append(SyntheticAudio.little((Float(sample) / scale).bitPattern)) }
            format = 3
            depth = 32
        } else {
            body = pcm(bigEndian: false)
        }
        let extensible = !floatingPoint && (bits > 16 || channels > 2)
        let blockAlign = channels * depth / 8
        var data =
            Data("RIFF".utf8) + SyntheticAudio.little(UInt32((extensible ? 60 : 36) + body.count))
            + Data("WAVEfmt ".utf8)
        data +=
            SyntheticAudio.little(UInt32(extensible ? 40 : 16))
            + SyntheticAudio.little(UInt16(extensible ? 0xFFFE : format))
        data += SyntheticAudio.little(UInt16(channels)) + SyntheticAudio.little(UInt32(sampleRate))
        data += SyntheticAudio.little(UInt32(sampleRate * blockAlign)) + SyntheticAudio.little(UInt16(blockAlign))
        data += SyntheticAudio.little(UInt16(depth))
        if extensible {
            let masks: [Int: UInt32] = [1: 0x4, 2: 0x3, 6: 0x3F]
            data +=
                SyntheticAudio.little(UInt16(22)) + SyntheticAudio.little(UInt16(bits))
                + SyntheticAudio.little(masks[channels] ?? 0)
            data += Data([
                0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71,
            ])
        }
        return data + Data("data".utf8) + SyntheticAudio.little(UInt32(body.count)) + body
    }

    public func aiff() -> Data {
        let body = pcm(bigEndian: true)
        var mantissa = UInt64(sampleRate)
        var exponent: UInt16 = 16_383 + 63
        while mantissa & (1 << 63) == 0 {
            mantissa <<= 1
            exponent -= 1
        }
        var data = Data("FORM".utf8) + SyntheticAudio.big(UInt32(4 + 26 + 16 + body.count)) + Data("AIFFCOMM".utf8)
        data +=
            SyntheticAudio.big(UInt32(18)) + SyntheticAudio.big(UInt16(channels)) + SyntheticAudio.big(UInt32(frames))
        data += SyntheticAudio.big(UInt16(bits)) + SyntheticAudio.big(exponent) + SyntheticAudio.big(mantissa)
        return data + Data("SSND".utf8) + SyntheticAudio.big(UInt32(8 + body.count)) + Data(count: 8) + body
    }
}

/// Replaces the Vorbis comments and pictures of a FLAC stream, keeping STREAMINFO, the seek table, and the frames.
public enum SyntheticFLACMetadata {
    public static func replacingTags(
        in flac: Data, comments: [String], pictures: [(type: Int, mime: String, data: Data)]
    ) -> Data {
        precondition(flac.starts(with: Array("fLaC".utf8)))
        func big(_ value: Int, _ width: Int) -> Data {
            Data((0..<width).map { UInt8(truncatingIfNeeded: value >> (8 * (width - 1 - $0))) })
        }
        func little(_ value: Int) -> Data { Data((0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }) }
        var kept: [(Int, Data)] = []
        var offset = 4
        var last = false
        while !last {
            last = flac[offset] & 0x80 != 0
            let type = Int(flac[offset] & 0x7F)
            let length = (1...3).reduce(0) { $0 << 8 | Int(flac[offset + $1]) }
            if type == 0 || type == 3 { kept.append((type, flac.subdata(in: (offset + 4)..<(offset + 4 + length)))) }
            offset += 4 + length
        }
        var vorbis = little(9) + Data("synthetic".utf8) + little(comments.count)
        for comment in comments { vorbis += little(comment.utf8.count) + Data(comment.utf8) }
        kept.append((4, vorbis))
        for picture in pictures {
            var body = big(picture.type, 4) + big(picture.mime.utf8.count, 4) + Data(picture.mime.utf8) + big(0, 4)
            body += big(600, 4) + big(600, 4) + big(24, 4) + big(0, 4) + big(picture.data.count, 4) + picture.data
            kept.append((6, body))
        }
        var output = Data("fLaC".utf8)
        for (index, (type, body)) in kept.enumerated() {
            output.append(UInt8(type) | (index == kept.count - 1 ? 0x80 : 0))
            output += big(body.count, 3) + body
        }
        return output + flac.subdata(in: offset..<flac.count)
    }
}
