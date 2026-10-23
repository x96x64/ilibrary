// Test support on macOS: FLAC fixtures encoded with Core Audio, so that tests need no external encoder.
#if os(macOS)
    import AudioToolbox
    import Foundation

    /// Encodes a PCM file to FLAC with Core Audio.
    public func encodeFLAC(_ source: URL, to destination: URL, bits: Int) throws {
        var reference: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(source as CFURL, &reference) == noErr, let reader = reference else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { ExtAudioFileDispose(reader) }
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        ExtAudioFileGetProperty(reader, kExtAudioFileProperty_FileDataFormat, &size, &format)
        let flags = bits == 24 ? kAppleLosslessFormatFlag_24BitSourceData : kAppleLosslessFormatFlag_16BitSourceData
        var output = AudioStreamBasicDescription(
            mSampleRate: format.mSampleRate, mFormatID: kAudioFormatFLAC, mFormatFlags: flags, mBytesPerPacket: 0,
            mFramesPerPacket: 4096, mBytesPerFrame: 0, mChannelsPerFrame: format.mChannelsPerFrame, mBitsPerChannel: 0,
            mReserved: 0)
        var writerReference: ExtAudioFileRef?
        let status = ExtAudioFileCreateWithURL(
            destination as CFURL, kAudioFileFLACType, &output, nil, AudioFileFlags.eraseFile.rawValue, &writerReference)
        guard status == noErr, let writer = writerReference else { throw CocoaError(.fileWriteUnknown) }
        let channels = format.mChannelsPerFrame
        var client = AudioStreamBasicDescription(
            mSampleRate: format.mSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 4 * channels,
            mFramesPerPacket: 1, mBytesPerFrame: 4 * channels, mChannelsPerFrame: channels, mBitsPerChannel: 32,
            mReserved: 0)
        ExtAudioFileSetProperty(
            reader, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: client)), &client)
        ExtAudioFileSetProperty(
            writer, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: client)), &client)
        var buffer = [Int32](repeating: 0, count: 8_192 * Int(channels))
        while true {
            var frames: UInt32 = 8_192
            let read = buffer.withUnsafeMutableBytes { raw -> OSStatus in
                var list = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: channels, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
                let status = ExtAudioFileRead(reader, &frames, &list)
                guard status == noErr, frames > 0 else { return status }
                list.mBuffers.mDataByteSize = frames * 4 * channels
                return ExtAudioFileWrite(writer, frames, &list)
            }
            guard read == noErr else { throw CocoaError(.fileWriteUnknown) }
            if frames == 0 { break }
        }
        guard ExtAudioFileDispose(writer) == noErr else { throw CocoaError(.fileWriteUnknown) }
    }
#endif
