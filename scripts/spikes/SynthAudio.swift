// Generates deterministic synthetic PCM audio as WAV or AIFF for the M1 spikes.
// Foundation only. The signal combines tones, full-range pseudo-random noise, sample extremes,
// and digital silence so that lossless round trips exercise every bit of each sample.
//
// Usage: synth-audio OUT.(wav|aiff) --rate HZ --bits 16|24 --channels N --frames N [--seed N]

import Foundation

struct Options {
    var output = ""
    var rate = 44_100
    var bits = 16
    var channels = 2
    var frames = 0
    var seed: UInt64 = 1
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    guard !arguments.isEmpty else { fail("usage: synth-audio OUT --rate HZ --bits 16|24 --channels N --frames N") }
    options.output = arguments.removeFirst()
    while !arguments.isEmpty {
        let name = arguments.removeFirst()
        guard let value = arguments.first.flatMap({ UInt64($0) }) else { fail("missing value for \(name)") }
        arguments.removeFirst()
        switch name {
        case "--rate": options.rate = Int(value)
        case "--bits": options.bits = Int(value)
        case "--channels": options.channels = Int(value)
        case "--frames": options.frames = Int(value)
        case "--seed": options.seed = value
        default: fail("unknown option \(name)")
        }
    }
    guard options.bits == 16 || options.bits == 24, options.frames > 0, options.channels > 0 else {
        fail("invalid format")
    }
    return options
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("synth-audio: \(message)\n".utf8))
    exit(2)
}

/// Returns interleaved integer samples in the range of the requested bit depth.
func synthesize(_ options: Options) -> [Int32] {
    let maximum = Int32((1 << (options.bits - 1)) - 1)
    let minimum = -maximum - 1
    var state = options.seed &* 0x9E37_79B9_7F4A_7C15 | 1
    func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 11
    }
    var samples = [Int32](repeating: 0, count: options.frames * options.channels)
    let silenceStart = options.frames / 2
    let silenceEnd = min(options.frames, silenceStart + options.rate / 10)
    for frame in 0..<options.frames {
        for channel in 0..<options.channels {
            let value: Int32
            if frame < 64 {
                value = (frame + channel) % 2 == 0 ? maximum : minimum
            } else if frame >= silenceStart && frame < silenceEnd {
                value = 0
            } else {
                let time = Double(frame) / Double(options.rate)
                let frequency = 220.0 * Double(channel + 1) + 3.0 * time
                let tone = 0.45 * sin(2 * Double.pi * frequency * time)
                let noise = Double(Int64(next() % 2_000_001) - 1_000_000) / 1_000_000 * 0.05
                value = Int32((tone + noise) * Double(maximum))
            }
            samples[frame * options.channels + channel] = value
        }
    }
    return samples
}

extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func append<T: FixedWidthInteger>(bigEndian value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
    mutating func appendASCII(_ string: String) { append(contentsOf: Array(string.utf8)) }
}

func pcmBytes(_ samples: [Int32], bits: Int, bigEndian: Bool) -> Data {
    var data = Data(capacity: samples.count * bits / 8)
    for sample in samples {
        let value = UInt32(bitPattern: sample)
        var bytes = (0..<(bits / 8)).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) }
        if bigEndian { bytes.reverse() }
        data.append(contentsOf: bytes)
    }
    return data
}

func wave(_ options: Options, _ samples: [Int32]) -> Data {
    let pcm = pcmBytes(samples, bits: options.bits, bigEndian: false)
    let blockAlign = options.channels * options.bits / 8
    // WAVE_FORMAT_EXTENSIBLE is required for more than 16 bits or more than two channels.
    let extensible = options.bits > 16 || options.channels > 2
    var data = Data()
    data.appendASCII("RIFF")
    data.append(littleEndian: UInt32((extensible ? 60 : 36) + pcm.count))
    data.appendASCII("WAVEfmt ")
    data.append(littleEndian: UInt32(extensible ? 40 : 16))
    data.append(littleEndian: UInt16(extensible ? 0xFFFE : 1))
    data.append(littleEndian: UInt16(options.channels))
    data.append(littleEndian: UInt32(options.rate))
    data.append(littleEndian: UInt32(options.rate * blockAlign))
    data.append(littleEndian: UInt16(blockAlign))
    data.append(littleEndian: UInt16(options.bits))
    if extensible {
        let masks: [Int: UInt32] = [1: 0x4, 2: 0x3, 6: 0x3F, 8: 0x63F]
        data.append(littleEndian: UInt16(22))
        data.append(littleEndian: UInt16(options.bits))
        data.append(littleEndian: masks[options.channels] ?? 0)
        // KSDATAFORMAT_SUBTYPE_PCM
        data.append(contentsOf: [
            0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71,
        ])
    }
    data.appendASCII("data")
    data.append(littleEndian: UInt32(pcm.count))
    data.append(pcm)
    return data
}

/// Encodes an integral sample rate as an IEEE 754 80-bit extended value, as AIFF requires.
func extended80(_ value: Int) -> Data {
    var mantissa = UInt64(value)
    var exponent: UInt16 = 16_383 + 63
    while mantissa & (1 << 63) == 0 {
        mantissa <<= 1
        exponent -= 1
    }
    var data = Data()
    data.append(bigEndian: exponent)
    data.append(bigEndian: mantissa)
    return data
}

func aiff(_ options: Options, _ samples: [Int32]) -> Data {
    let pcm = pcmBytes(samples, bits: options.bits, bigEndian: true)
    var data = Data()
    data.appendASCII("FORM")
    data.append(bigEndian: UInt32(4 + 26 + 16 + pcm.count))
    data.appendASCII("AIFFCOMM")
    data.append(bigEndian: UInt32(18))
    data.append(bigEndian: UInt16(options.channels))
    data.append(bigEndian: UInt32(options.frames))
    data.append(bigEndian: UInt16(options.bits))
    data.append(extended80(options.rate))
    data.appendASCII("SSND")
    data.append(bigEndian: UInt32(8 + pcm.count))
    data.append(bigEndian: UInt32(0))
    data.append(bigEndian: UInt32(0))
    data.append(pcm)
    return data
}

let options = parseOptions()
let samples = synthesize(options)
let lowercased = options.output.lowercased()
let data =
    lowercased.hasSuffix(".aiff") || lowercased.hasSuffix(".aif") ? aiff(options, samples) : wave(options, samples)
do {
    try data.write(to: URL(fileURLWithPath: options.output))
} catch {
    fail("cannot write \(options.output): \(error.localizedDescription)")
}
