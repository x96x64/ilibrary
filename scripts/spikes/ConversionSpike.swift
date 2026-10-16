// M1 spike S2: lossless conversion of FLAC, WAV, and AIFF to Apple Lossless through AudioToolbox,
// with verification by decoded PCM equality. Exploratory code that informs ConversionMac.
//
// Usage:
//   conversion-spike convert IN OUT.m4a      convert, verify, and move into place; prints timings
//   conversion-spike pcm FILE                decoded format, frame count, and PCM SHA-256
//   conversion-spike verify SOURCE OUT.m4a   compare decoded PCM, frame count, codec, and bit depth
//   conversion-spike info FILE               container metadata that Core Audio exposes
//   conversion-spike space PATH              available-capacity values for the volume of PATH
//   conversion-spike flac-metadata FILE      FLAC metadata blocks parsed without Core Audio

import AudioToolbox
import CryptoKit
import Foundation

struct SpikeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        let code = UInt32(bitPattern: status)
        let characters = (0..<4).map { UInt8(truncatingIfNeeded: code >> (24 - 8 * $0)) }
        let text =
            characters.allSatisfy({ $0 >= 32 && $0 < 127 }) ? " '\(String(decoding: characters, as: UTF8.self))'" : ""
        throw SpikeError("\(operation) failed with OSStatus \(status)\(text)")
    }
}

func formatName(_ id: AudioFormatID) -> String {
    let characters = (0..<4).map { UInt8(truncatingIfNeeded: id >> (24 - 8 * UInt32($0))) }
    return String(decoding: characters, as: UTF8.self)
}

/// Interleaved 32-bit signed integer PCM; every source depth is left-aligned into this client format.
func clientFormat(sampleRate: Double, channels: UInt32) -> AudioStreamBasicDescription {
    AudioStreamBasicDescription(
        mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 4 * channels, mFramesPerPacket: 1, mBytesPerFrame: 4 * channels,
        mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
}

final class AudioReader {
    let file: ExtAudioFileRef
    let format: AudioStreamBasicDescription
    let client: AudioStreamBasicDescription
    let lengthFrames: Int64

    init(_ url: URL) throws {
        var reference: ExtAudioFileRef?
        try check(ExtAudioFileOpenURL(url as CFURL, &reference), "ExtAudioFileOpenURL")
        file = reference!
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &format), "FileDataFormat")
        self.format = format
        client = clientFormat(sampleRate: format.mSampleRate, channels: format.mChannelsPerFrame)
        var clientCopy = client
        try check(
            ExtAudioFileSetProperty(
                file, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: clientCopy)),
                &clientCopy), "ClientDataFormat")
        var frames: Int64 = 0
        size = UInt32(MemoryLayout<Int64>.size)
        try check(
            ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &size, &frames), "FileLengthFrames")
        lengthFrames = frames
    }

    deinit { ExtAudioFileDispose(file) }

    var audioFile: AudioFileID? {
        var id: AudioFileID?
        var size = UInt32(MemoryLayout<AudioFileID?>.size)
        return ExtAudioFileGetProperty(file, kExtAudioFileProperty_AudioFile, &size, &id) == noErr ? id : nil
    }

    /// Bits per sample of the source; for ALAC the depth is carried in the format flags.
    var sourceBits: UInt32 {
        if format.mFormatID == kAudioFormatAppleLossless {
            switch format.mFormatFlags {
            case kAppleLosslessFormatFlag_16BitSourceData: return 16
            case kAppleLosslessFormatFlag_20BitSourceData: return 20
            case kAppleLosslessFormatFlag_24BitSourceData: return 24
            case kAppleLosslessFormatFlag_32BitSourceData: return 32
            default: return 0
            }
        }
        if format.mFormatID == kAudioFormatFLAC {
            switch format.mFormatFlags {
            case kAppleLosslessFormatFlag_16BitSourceData: return 16
            case kAppleLosslessFormatFlag_20BitSourceData: return 20
            case kAppleLosslessFormatFlag_24BitSourceData: return 24
            case kAppleLosslessFormatFlag_32BitSourceData: return 32
            default: return format.mBitsPerChannel
            }
        }
        return format.mBitsPerChannel
    }

    /// Reads the whole stream in blocks, passing each block of interleaved samples to `body`.
    func read(blockFrames: UInt32 = 32_768, _ body: (UnsafeBufferPointer<Int32>) throws -> Void) throws -> Int64 {
        let channels = Int(client.mChannelsPerFrame)
        var storage = [Int32](repeating: 0, count: Int(blockFrames) * channels)
        var total: Int64 = 0
        while true {
            var frames = blockFrames
            let status = storage.withUnsafeMutableBytes { raw -> OSStatus in
                var list = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: UInt32(channels), mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
                return ExtAudioFileRead(file, &frames, &list)
            }
            try check(status, "ExtAudioFileRead")
            if frames == 0 { break }
            try storage.withUnsafeBufferPointer {
                try body(UnsafeBufferPointer(rebasing: $0[0..<Int(frames) * channels]))
            }
            total += Int64(frames)
        }
        return total
    }
}

struct Digest {
    let frames: Int64
    let sha256: String
}

func pcmDigest(_ url: URL) throws -> (AudioReader, Digest) {
    let reader = try AudioReader(url)
    var hasher = SHA256()
    let frames = try reader.read { block in hasher.update(bufferPointer: UnsafeRawBufferPointer(block)) }
    let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    return (reader, Digest(frames: frames, sha256: digest))
}

func describe(_ reader: AudioReader) -> String {
    let format = reader.format
    return
        "\(formatName(format.mFormatID)) \(Int(format.mSampleRate)) Hz \(format.mChannelsPerFrame) ch \(reader.sourceBits)-bit"
}

func packetTable(_ reader: AudioReader) -> String {
    guard let audioFile = reader.audioFile else { return "unavailable" }
    var info = AudioFilePacketTableInfo()
    var size = UInt32(MemoryLayout<AudioFilePacketTableInfo>.size)
    let status = AudioFileGetProperty(audioFile, kAudioFilePropertyPacketTableInfo, &size, &info)
    guard status == noErr else { return "none" }
    return "valid \(info.mNumberValidFrames), priming \(info.mPrimingFrames), remainder \(info.mRemainderFrames)"
}

func availableCapacity(_ url: URL) -> (important: Int64?, plain: Int?) {
    let values = try? url.resourceValues(forKeys: [
        .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
    ])
    return (values?.volumeAvailableCapacityForImportantUsage, values?.volumeAvailableCapacity)
}

func verify(source: URL, output: URL) throws -> [String] {
    let (sourceReader, sourceDigest) = try pcmDigest(source)
    let (outputReader, outputDigest) = try pcmDigest(output)
    var problems: [String] = []
    if outputReader.format.mFormatID != kAudioFormatAppleLossless {
        problems.append("codec is \(formatName(outputReader.format.mFormatID))")
    }
    if outputReader.sourceBits != sourceReader.sourceBits {
        problems.append("bit depth \(outputReader.sourceBits) differs from \(sourceReader.sourceBits)")
    }
    if outputReader.format.mSampleRate != sourceReader.format.mSampleRate { problems.append("sample rate differs") }
    if outputReader.format.mChannelsPerFrame != sourceReader.format.mChannelsPerFrame {
        problems.append("channel count differs")
    }
    if outputDigest.frames != sourceDigest.frames {
        problems.append("decoded \(outputDigest.frames) frames; source has \(sourceDigest.frames)")
    }
    if outputReader.lengthFrames != outputDigest.frames {
        problems.append("declared \(outputReader.lengthFrames) frames; decoded \(outputDigest.frames)")
    }
    if outputDigest.sha256 != sourceDigest.sha256 { problems.append("decoded PCM differs") }
    // A truncated source decodes to fewer frames than its header declares; never count it as complete.
    if sourceReader.lengthFrames != sourceDigest.frames {
        problems.append("source declares \(sourceReader.lengthFrames) frames but decodes to \(sourceDigest.frames)")
    }
    return problems
}

/// Core Audio derives the frame count of WAV and AIFF files from the bytes present, so a truncated file
/// decodes without error. Compare the declared size of the sample chunk with the bytes that follow it.
func checkDeclaredLength(_ url: URL) throws {
    let data = try Data(contentsOf: url, options: .alwaysMapped)
    guard data.count >= 12 else { return }
    let form = String(decoding: data[0..<4], as: UTF8.self)
    let littleEndian = form == "RIFF"
    guard littleEndian || form == "FORM" else { return }
    func size(_ offset: Int) -> Int {
        let bytes = data[offset..<offset + 4]
        return (littleEndian ? bytes.reversed() : Array(bytes)).reduce(0) { $0 << 8 | Int($1) }
    }
    var offset = 12
    while offset + 8 <= data.count {
        let identifier = String(decoding: data[offset..<offset + 4], as: UTF8.self)
        let length = size(offset + 4)
        if identifier == "data" || identifier == "SSND" {
            let present = data.count - offset - 8
            guard present >= length else {
                throw SpikeError("\(identifier) chunk declares \(length) bytes but only \(present) are present")
            }
            return
        }
        offset += 8 + length + (length & 1)
    }
    throw SpikeError("no sample data chunk")
}

func convert(source: URL, destination: URL) throws {
    let start = Date()
    try checkDeclaredLength(source)
    let reader = try AudioReader(source)
    if reader.format.mFormatID == kAudioFormatLinearPCM && reader.format.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
        throw SpikeError("floating-point PCM cannot be represented losslessly in Apple Lossless")
    }
    let bits = reader.sourceBits
    let flags: AudioFormatFlags
    switch bits {
    case 16: flags = kAppleLosslessFormatFlag_16BitSourceData
    case 20: flags = kAppleLosslessFormatFlag_20BitSourceData
    case 24: flags = kAppleLosslessFormatFlag_24BitSourceData
    case 32: flags = kAppleLosslessFormatFlag_32BitSourceData
    default: throw SpikeError("unsupported source depth \(bits) for \(formatName(reader.format.mFormatID))")
    }
    // A conservative estimate: Apple Lossless never needs more than the PCM size plus container overhead.
    let required =
        Int64(Double(reader.lengthFrames) * Double(reader.format.mChannelsPerFrame) * Double(bits) / 8 * 1.02) + 1 << 20
    let capacity = availableCapacity(destination.deletingLastPathComponent())
    let available = capacity.important ?? Int64(capacity.plain ?? 0)
    print(
        "free space: required \(required), available for important usage \(capacity.important.map(String.init) ?? "nil"), available \(capacity.plain.map(String.init) ?? "nil")"
    )
    guard available >= required else {
        throw SpikeError("insufficient free space: \(available) bytes available, \(required) required")
    }

    var outputFormat = AudioStreamBasicDescription(
        mSampleRate: reader.format.mSampleRate, mFormatID: kAudioFormatAppleLossless, mFormatFlags: flags,
        mBytesPerPacket: 0, mFramesPerPacket: 4096, mBytesPerFrame: 0,
        mChannelsPerFrame: reader.format.mChannelsPerFrame, mBitsPerChannel: 0, mReserved: 0)
    let partial = destination.deletingLastPathComponent().appendingPathComponent(
        ".\(destination.lastPathComponent).partial")
    var reference: ExtAudioFileRef?
    try check(
        ExtAudioFileCreateWithURL(
            partial as CFURL, kAudioFileM4AType, &outputFormat, nil, AudioFileFlags.eraseFile.rawValue, &reference),
        "ExtAudioFileCreateWithURL")
    let writer = reference!
    var client = reader.client
    var written: Int64 = 0
    do {
        try check(
            ExtAudioFileSetProperty(
                writer, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: client)), &client),
            "ClientDataFormat (output)")
        let channels = Int(client.mChannelsPerFrame)
        written = try reader.read { block in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: UInt32(channels), mDataByteSize: UInt32(block.count * 4),
                    mData: UnsafeMutableRawPointer(mutating: block.baseAddress)))
            try check(ExtAudioFileWrite(writer, UInt32(block.count / channels), &list), "ExtAudioFileWrite")
        }
        try check(ExtAudioFileDispose(writer), "ExtAudioFileDispose")
    } catch {
        ExtAudioFileDispose(writer)
        try? FileManager.default.removeItem(at: partial)
        throw error
    }
    let encoded = Date()
    let problems = try verify(source: source, output: partial)
    let verified = Date()
    guard problems.isEmpty else {
        try? FileManager.default.removeItem(at: partial)
        throw SpikeError("verification failed: \(problems.joined(separator: "; "))")
    }
    if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
    try FileManager.default.moveItem(at: partial, to: destination)
    let output = try AudioReader(destination)
    print(
        "converted \(describe(reader)) -> \(describe(output)); \(written) frames; packet table: \(packetTable(output))")
    print(
        String(
            format: "timing: encode %.3f s, verify %.3f s", encoded.timeIntervalSince(start),
            verified.timeIntervalSince(encoded)))
}

func info(_ url: URL) throws {
    let reader = try AudioReader(url)
    print("format: \(describe(reader)); declared frames \(reader.lengthFrames); packet table: \(packetTable(reader))")
    guard let audioFile = reader.audioFile else { return }
    var dictionary: Unmanaged<CFDictionary>?
    var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
    if AudioFileGetProperty(audioFile, kAudioFilePropertyInfoDictionary, &size, &dictionary) == noErr,
        let values = dictionary?.takeRetainedValue() as? [String: Any]
    {
        for key in values.keys.sorted() { print("info \(key) = \(values[key]!)") }
    }
    var artworkSize: UInt32 = 0
    var writable: UInt32 = 0
    let status = AudioFileGetPropertyInfo(audioFile, kAudioFilePropertyAlbumArtwork, &artworkSize, &writable)
    print("album artwork property: \(status == noErr ? "available" : "status \(status)")")
}

/// Parses FLAC metadata blocks: STREAMINFO, VORBIS_COMMENT, and PICTURE. Foundation only.
func flacMetadata(_ url: URL) throws {
    let data = try Data(contentsOf: url)
    guard data.starts(with: Array("fLaC".utf8)) else { throw SpikeError("not a FLAC stream") }
    func big(_ offset: Int, _ width: Int) -> Int { (0..<width).reduce(0) { $0 << 8 | Int(data[offset + $1]) } }
    func little(_ offset: Int) -> Int { (0..<4).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) } }
    var offset = 4
    var last = false
    while !last {
        guard offset + 4 <= data.count else { throw SpikeError("truncated metadata header") }
        last = data[offset] & 0x80 != 0
        let type = Int(data[offset] & 0x7F)
        let length = big(offset + 1, 3)
        let body = offset + 4
        guard body + length <= data.count else { throw SpikeError("truncated metadata block \(type)") }
        switch type {
        case 0:
            let rate = big(body + 10, 3) >> 4
            let channels = (Int(data[body + 12]) >> 1 & 0x07) + 1
            let bits = ((Int(data[body + 12]) & 0x01) << 4 | Int(data[body + 13]) >> 4) + 1
            let samples = (Int(data[body + 13]) & 0x0F) << 32 | big(body + 14, 4)
            print("STREAMINFO \(rate) Hz \(channels) ch \(bits)-bit \(samples) frames")
        case 4:
            var cursor = body
            let vendorLength = little(cursor)
            cursor += 4 + vendorLength
            let count = little(cursor)
            cursor += 4
            for _ in 0..<count {
                let length = little(cursor)
                print("VORBIS_COMMENT \(String(decoding: data[(cursor + 4)..<(cursor + 4 + length)], as: UTF8.self))")
                cursor += 4 + length
            }
        case 6:
            var cursor = body
            let pictureType = big(cursor, 4)
            let mimeLength = big(cursor + 4, 4)
            let mime = String(decoding: data[(cursor + 8)..<(cursor + 8 + mimeLength)], as: UTF8.self)
            cursor += 8 + mimeLength
            cursor += 4 + big(cursor, 4) + 16
            let pictureLength = big(cursor, 4)
            let picture = data[(cursor + 4)..<(cursor + 4 + pictureLength)]
            let digest = SHA256.hash(data: picture).map { String(format: "%02x", $0) }.joined().prefix(16)
            print("PICTURE type \(pictureType) \(mime) \(pictureLength) bytes sha256 \(digest)")
        default:
            print("block type \(type), \(length) bytes")
        }
        offset = body + length
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    FileHandle.standardError.write(
        Data("usage: conversion-spike convert|pcm|verify|info|space|flac-metadata FILE...\n".utf8))
    exit(2)
}
do {
    let first = URL(fileURLWithPath: arguments[1])
    switch arguments[0] {
    case "convert":
        try convert(source: first, destination: URL(fileURLWithPath: arguments[2]))
    case "pcm":
        let (reader, digest) = try pcmDigest(first)
        print(
            "\(describe(reader)) declared \(reader.lengthFrames) decoded \(digest.frames) sha256 \(digest.sha256.prefix(16))"
        )
    case "pcm-dump":
        // Writes the decoded interleaved 32-bit PCM, for diagnosing decoder differences.
        FileManager.default.createFile(atPath: arguments[2], contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: arguments[2]))
        let reader = try AudioReader(first)
        _ = try reader.read { block in try handle.write(contentsOf: Data(buffer: block)) }
        try handle.close()
    case "verify":
        let problems = try verify(source: first, output: URL(fileURLWithPath: arguments[2]))
        print(problems.isEmpty ? "verified" : "FAILED: \(problems.joined(separator: "; "))")
        exit(problems.isEmpty ? 0 : 1)
    case "info":
        try info(first)
    case "space":
        let capacity = availableCapacity(first)
        print(
            "important usage \(capacity.important.map(String.init) ?? "nil"); available \(capacity.plain.map(String.init) ?? "nil")"
        )
    case "flac-metadata":
        try flacMetadata(first)
    default:
        throw SpikeError("unknown command \(arguments[0])")
    }
} catch {
    FileHandle.standardError.write(Data("conversion-spike: \(error)\n".utf8))
    exit(1)
}
