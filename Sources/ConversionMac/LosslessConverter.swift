// Lossless conversion to Apple Lossless through AudioToolbox, verified by decoded PCM (decision 7).
// Built only on macOS; on other platforms the target is empty.
#if os(macOS)
    import AudioToolbox
    import CryptoKit
    import Foundation

    public enum ConversionError: Error, Equatable, Sendable, CustomStringConvertible {
        case unreadable(path: String, reason: String)
        case floatingPoint(path: String)
        case unsupportedChannels(path: String, channels: Int)
        case unsupportedDepth(path: String, bits: Int)
        case truncated(path: String, reason: String)
        case writeFailed(path: String, reason: String)
        case verificationFailed(path: String, problems: [String])

        public var description: String {
            switch self {
            case .unreadable(let path, let reason): "\(path) cannot be read as audio: \(reason)"
            case .floatingPoint(let path):
                "\(path) holds floating-point PCM, which Apple Lossless cannot represent losslessly"
            case .unsupportedChannels(let path, let channels):
                "\(path) has \(channels) channels; this version converts mono and stereo only"
            case .unsupportedDepth(let path, let bits): "\(path) has \(bits)-bit samples, which are not supported"
            case .truncated(let path, let reason): "\(path) is incomplete: \(reason)"
            case .writeFailed(let path, let reason): "\(path) could not be written: \(reason)"
            case .verificationFailed(let path, let problems):
                "\(path) failed verification: \(problems.joined(separator: "; "))"
            }
        }
    }

    /// The format of an audio file as Core Audio reads it.
    public struct AudioFormat: Equatable, Sendable {
        /// The four-character format code, such as `lpcm`, `flac`, or `alac`.
        public var codec: String
        public var sampleRate: Double
        public var channels: Int
        public var bitsPerSample: Int
        public var isFloat: Bool
        /// The frame count that the file declares.
        public var declaredFrames: Int64
    }

    /// The decoded PCM of a file: its frame count and the SHA-256 of its samples as 32-bit integers.
    public struct DecodedAudio: Equatable, Sendable {
        public var frames: Int64
        public var digest: String
    }

    public struct ConversionReport: Equatable, Sendable {
        public var source: AudioFormat
        public var output: AudioFormat
        public var decoded: DecodedAudio
    }

    public enum LosslessConverter {
        static func check(_ status: OSStatus, _ operation: String, _ path: String) throws {
            guard status == noErr else {
                throw ConversionError.unreadable(path: path, reason: "\(operation) failed with OSStatus \(status)")
            }
        }

        static func name(_ code: AudioFormatID) -> String {
            String(decoding: (0..<4).map { UInt8(truncatingIfNeeded: code >> (24 - 8 * UInt32($0))) }, as: UTF8.self)
        }

        static func clientFormat(sampleRate: Double, channels: UInt32) -> AudioStreamBasicDescription {
            AudioStreamBasicDescription(
                mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 4 * channels, mFramesPerPacket: 1, mBytesPerFrame: 4 * channels,
                mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
        }

        static func sourceBits(_ format: AudioStreamBasicDescription) -> Int {
            if format.mFormatID == kAudioFormatAppleLossless || format.mFormatID == kAudioFormatFLAC {
                switch format.mFormatFlags {
                case kAppleLosslessFormatFlag_16BitSourceData: return 16
                case kAppleLosslessFormatFlag_20BitSourceData: return 20
                case kAppleLosslessFormatFlag_24BitSourceData: return 24
                case kAppleLosslessFormatFlag_32BitSourceData: return 32
                default: return Int(format.mBitsPerChannel)
                }
            }
            return Int(format.mBitsPerChannel)
        }

        /// Opens a file for reading as 32-bit integer PCM, with every source depth left-aligned.
        static func open(_ url: URL) throws -> (ExtAudioFileRef, AudioFormat, AudioStreamBasicDescription) {
            var reference: ExtAudioFileRef?
            try check(ExtAudioFileOpenURL(url as CFURL, &reference), "ExtAudioFileOpenURL", url.path)
            let file = reference!
            do {
                var format = AudioStreamBasicDescription()
                var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                try check(
                    ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &format),
                    "reading the data format", url.path)
                var client = clientFormat(sampleRate: format.mSampleRate, channels: format.mChannelsPerFrame)
                try check(
                    ExtAudioFileSetProperty(
                        file, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: client)),
                        &client),
                    "setting the client format", url.path)
                var frames: Int64 = 0
                size = UInt32(MemoryLayout<Int64>.size)
                try check(
                    ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &size, &frames),
                    "reading the length", url.path)
                let info = AudioFormat(
                    codec: name(format.mFormatID), sampleRate: format.mSampleRate,
                    channels: Int(format.mChannelsPerFrame),
                    bitsPerSample: sourceBits(format),
                    isFloat: format.mFormatID == kAudioFormatLinearPCM
                        && format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                    declaredFrames: frames)
                return (file, info, client)
            } catch {
                ExtAudioFileDispose(file)
                throw error
            }
        }

        /// Reads all frames in blocks of interleaved samples. Returns the number of frames read.
        static func read(
            _ file: ExtAudioFileRef, channels: Int, path: String, _ body: (UnsafeBufferPointer<Int32>) throws -> Void
        )
            throws -> Int64
        {
            let blockFrames: UInt32 = 32_768
            var storage = [Int32](repeating: 0, count: Int(blockFrames) * channels)
            var total: Int64 = 0
            while true {
                var frames = blockFrames
                let status = storage.withUnsafeMutableBytes { raw -> OSStatus in
                    var list = AudioBufferList(
                        mNumberBuffers: 1,
                        mBuffers: AudioBuffer(
                            mNumberChannels: UInt32(channels), mDataByteSize: UInt32(raw.count), mData: raw.baseAddress)
                    )
                    return ExtAudioFileRead(file, &frames, &list)
                }
                try check(status, "decoding", path)
                if frames == 0 { break }
                try storage.withUnsafeBufferPointer {
                    try body(UnsafeBufferPointer(rebasing: $0[0..<Int(frames) * channels]))
                }
                total += Int64(frames)
            }
            return total
        }

        public static func format(of url: URL) throws -> AudioFormat {
            let (file, info, _) = try open(url)
            ExtAudioFileDispose(file)
            return info
        }

        public static func decode(_ url: URL) throws -> (AudioFormat, DecodedAudio) {
            let (file, info, _) = try open(url)
            defer { ExtAudioFileDispose(file) }
            var hasher = SHA256()
            let frames = try read(file, channels: info.channels, path: url.path) {
                hasher.update(bufferPointer: UnsafeRawBufferPointer($0))
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return (info, DecodedAudio(frames: frames, digest: digest))
        }

        /// Core Audio derives the length of WAV and AIFF files from the bytes present, so a truncated file decodes
        /// without error. The declared size of the sample chunk is compared with the bytes that follow it.
        public static func checkChunkLengths(_ url: URL) throws {
            let data: Data
            do {
                data = try Data(contentsOf: url, options: .alwaysMapped)
            } catch {
                throw ConversionError.unreadable(path: url.path, reason: error.localizedDescription)
            }
            guard data.count >= 12 else { return }
            let form = String(decoding: data[0..<4], as: UTF8.self)
            let littleEndian = form == "RIFF"
            guard littleEndian || form == "FORM" else { return }
            func size(_ offset: Int) -> Int {
                let bytes = Array(data[offset..<offset + 4])
                return (littleEndian ? bytes.reversed() : bytes).reduce(0) { $0 << 8 | Int($1) }
            }
            var offset = 12
            while offset + 8 <= data.count {
                let identifier = String(decoding: data[offset..<offset + 4], as: UTF8.self)
                let length = size(offset + 4)
                if identifier == "data" || identifier == "SSND" {
                    let present = data.count - offset - 8
                    guard present >= length else {
                        throw ConversionError.truncated(
                            path: url.path,
                            reason: "its \(identifier) chunk declares \(length) bytes, but \(present) are present")
                    }
                    return
                }
                offset += 8 + length + (length & 1)
            }
            throw ConversionError.truncated(path: url.path, reason: "it has no sample data chunk")
        }

        /// Checks that a source can be converted losslessly and returns its format (decision 7).
        public static func preflight(_ url: URL) throws -> AudioFormat {
            try checkChunkLengths(url)
            let info = try format(of: url)
            if info.isFloat { throw ConversionError.floatingPoint(path: url.path) }
            guard (1...2).contains(info.channels) else {
                throw ConversionError.unsupportedChannels(path: url.path, channels: info.channels)
            }
            guard [16, 20, 24, 32].contains(info.bitsPerSample) else {
                throw ConversionError.unsupportedDepth(path: url.path, bits: info.bitsPerSample)
            }
            return info
        }

        /// An upper bound of the size of the Apple Lossless file: the PCM size plus two percent and 1 MiB.
        public static func estimatedOutputSize(_ info: AudioFormat) -> Int64 {
            Int64(Double(info.declaredFrames) * Double(info.channels) * Double(info.bitsPerSample) / 8 * 1.02)
                + (1 << 20)
        }

        /// Converts `source` to Apple Lossless at `destination`, which must not exist, and verifies the result.
        /// On failure, the destination is removed and the source is never changed.
        @discardableResult
        public static func convert(_ source: URL, to destination: URL) throws -> ConversionReport {
            let info = try preflight(source)
            let flags: AudioFormatFlags
            switch info.bitsPerSample {
            case 16: flags = kAppleLosslessFormatFlag_16BitSourceData
            case 20: flags = kAppleLosslessFormatFlag_20BitSourceData
            case 24: flags = kAppleLosslessFormatFlag_24BitSourceData
            default: flags = kAppleLosslessFormatFlag_32BitSourceData
            }
            var outputFormat = AudioStreamBasicDescription(
                mSampleRate: info.sampleRate, mFormatID: kAudioFormatAppleLossless, mFormatFlags: flags,
                mBytesPerPacket: 0, mFramesPerPacket: 4096, mBytesPerFrame: 0, mChannelsPerFrame: UInt32(info.channels),
                mBitsPerChannel: 0, mReserved: 0)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw ConversionError.writeFailed(path: destination.path, reason: "it already exists")
            }
            let (reader, _, client) = try open(source)
            defer { ExtAudioFileDispose(reader) }
            var reference: ExtAudioFileRef?
            let created = ExtAudioFileCreateWithURL(
                destination as CFURL, kAudioFileM4AType, &outputFormat, nil, 0, &reference)
            guard created == noErr, let writer = reference else {
                throw ConversionError.writeFailed(
                    path: destination.path, reason: "ExtAudioFileCreateWithURL returned \(created)")
            }
            do {
                var clientCopy = client
                try check(
                    ExtAudioFileSetProperty(
                        writer, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: clientCopy)),
                        &clientCopy), "setting the output client format", destination.path)
                let channels = info.channels
                _ = try read(reader, channels: channels, path: source.path) { block in
                    var list = AudioBufferList(
                        mNumberBuffers: 1,
                        mBuffers: AudioBuffer(
                            mNumberChannels: UInt32(channels), mDataByteSize: UInt32(block.count * 4),
                            mData: UnsafeMutableRawPointer(mutating: block.baseAddress)))
                    let status = ExtAudioFileWrite(writer, UInt32(block.count / channels), &list)
                    guard status == noErr else {
                        throw ConversionError.writeFailed(
                            path: destination.path, reason: "ExtAudioFileWrite returned \(status)")
                    }
                }
                let disposed = ExtAudioFileDispose(writer)
                guard disposed == noErr else {
                    throw ConversionError.writeFailed(path: destination.path, reason: "closing returned \(disposed)")
                }
                return try verify(source: source, output: destination)
            } catch {
                ExtAudioFileDispose(writer)
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }

        /// Verifies an Apple Lossless file against its source: equal PCM digests and frame counts, declared and
        /// decoded counts equal in both, and the source's depth, rate, and channel count (decision 7).
        @discardableResult
        public static func verify(source: URL, output: URL) throws -> ConversionReport {
            try checkChunkLengths(source)
            let (sourceInfo, sourcePCM) = try decode(source)
            let (outputInfo, outputPCM) = try decode(output)
            var problems: [String] = []
            if outputInfo.codec != "alac" { problems.append("the codec is \(outputInfo.codec)") }
            if outputInfo.bitsPerSample != sourceInfo.bitsPerSample {
                problems.append("the depth is \(outputInfo.bitsPerSample) bits instead of \(sourceInfo.bitsPerSample)")
            }
            if outputInfo.sampleRate != sourceInfo.sampleRate { problems.append("the sample rate differs") }
            if outputInfo.channels != sourceInfo.channels { problems.append("the channel count differs") }
            if sourceInfo.declaredFrames != sourcePCM.frames {
                problems.append(
                    "the source declares \(sourceInfo.declaredFrames) frames but decodes to \(sourcePCM.frames)")
            }
            if outputInfo.declaredFrames != outputPCM.frames {
                problems.append(
                    "the output declares \(outputInfo.declaredFrames) frames but decodes to \(outputPCM.frames)")
            }
            if outputPCM.frames != sourcePCM.frames {
                problems.append("the output has \(outputPCM.frames) frames; the source has \(sourcePCM.frames)")
            }
            if outputPCM.digest != sourcePCM.digest { problems.append("the decoded PCM differs") }
            guard problems.isEmpty else {
                throw ConversionError.verificationFailed(path: output.path, problems: problems)
            }
            return ConversionReport(source: sourceInfo, output: outputInfo, decoded: outputPCM)
        }
    }
#endif
