#if os(macOS)
    import AudioToolbox
    import ConversionMac
    import Foundation
    import SyntheticMedia
    import SyntheticMediaMac
    import Testing

    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ilibrary-conversion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Suite struct ConversionTests {
        @Test(arguments: [(44_100, 16, 2), (48_000, 24, 2), (96_000, 24, 2), (192_000, 24, 2), (44_100, 16, 1)])
        func everySourceFormatConvertsWithEqualPCM(rate: Int, bits: Int, channels: Int) throws {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let audio = SyntheticAudio(
                sampleRate: rate, bits: bits, channels: channels, frames: rate / 4 + 1_237, seed: UInt64(rate + bits))
            let wave = directory.appendingPathComponent("source.wav")
            let aiff = directory.appendingPathComponent("source.aiff")
            let flac = directory.appendingPathComponent("source.flac")
            try audio.wave().write(to: wave)
            try audio.aiff().write(to: aiff)
            try encodeFLAC(wave, to: flac, bits: bits)
            for source in [wave, aiff, flac] {
                let output = directory.appendingPathComponent(
                    source.deletingPathExtension().lastPathComponent + "-" + source.pathExtension + ".m4a")
                let report = try LosslessConverter.convert(source, to: output)
                #expect(report.output.codec == "alac")
                #expect(report.output.bitsPerSample == bits)
                #expect(report.output.channels == channels)
                #expect(report.output.sampleRate == Double(rate))
                #expect(report.decoded.frames == Int64(audio.frames))
                #expect(try LosslessConverter.decode(source).1 == report.decoded)
            }
        }

        @Test func floatingPointMultichannelAndExistingDestinationsAreRefused() throws {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let float = directory.appendingPathComponent("float.wav")
            try SyntheticAudio().wave(floatingPoint: true).write(to: float)
            #expect(throws: ConversionError.floatingPoint(path: float.path)) { try LosslessConverter.preflight(float) }
            let six = directory.appendingPathComponent("six.wav")
            try SyntheticAudio(bits: 24, channels: 6).wave().write(to: six)
            #expect(throws: ConversionError.unsupportedChannels(path: six.path, channels: 6)) {
                try LosslessConverter.preflight(six)
            }
            let stereo = directory.appendingPathComponent("stereo.wav")
            try SyntheticAudio().wave().write(to: stereo)
            let existing = directory.appendingPathComponent("existing.m4a")
            try Data("keep".utf8).write(to: existing)
            #expect(throws: ConversionError.self) { try LosslessConverter.convert(stereo, to: existing) }
            #expect(try Data(contentsOf: existing) == Data("keep".utf8))
        }

        @Test func truncatedSourcesAreRefusedAndLeaveNoOutput() throws {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let audio = SyntheticAudio(frames: 88_200)
            let wave = directory.appendingPathComponent("full.wav")
            try audio.wave().write(to: wave)
            let cutWave = directory.appendingPathComponent("cut.wav")
            try audio.wave().prefix(audio.wave().count / 3).write(to: cutWave)
            #expect(throws: ConversionError.self) {
                try LosslessConverter.convert(cutWave, to: directory.appendingPathComponent("a.m4a"))
            }
            let cutAIFF = directory.appendingPathComponent("cut.aiff")
            try audio.aiff().prefix(audio.aiff().count / 3).write(to: cutAIFF)
            #expect(throws: ConversionError.self) {
                try LosslessConverter.convert(cutAIFF, to: directory.appendingPathComponent("b.m4a"))
            }
            let flac = directory.appendingPathComponent("full.flac")
            try encodeFLAC(wave, to: flac, bits: 16)
            let data = try Data(contentsOf: flac)
            let cutFLAC = directory.appendingPathComponent("cut.flac")
            try data.prefix(data.count / 3).write(to: cutFLAC)
            let output = directory.appendingPathComponent("c.m4a")
            #expect(throws: ConversionError.self) { try LosslessConverter.convert(cutFLAC, to: output) }
            #expect(!FileManager.default.fileExists(atPath: output.path))
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.m4a").path))
        }

        @Test func verificationDetectsDifferentAudio() throws {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let first = directory.appendingPathComponent("first.wav")
            let second = directory.appendingPathComponent("second.wav")
            try SyntheticAudio(seed: 1).wave().write(to: first)
            try SyntheticAudio(seed: 2).wave().write(to: second)
            let output = directory.appendingPathComponent("first.m4a")
            try LosslessConverter.convert(first, to: output)
            #expect(throws: ConversionError.self) { try LosslessConverter.verify(source: second, output: output) }
        }

        @Test func flacMetadataCanBeReplacedWithoutChangingTheAudio() throws {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let wave = directory.appendingPathComponent("source.wav")
            try SyntheticAudio().wave().write(to: wave)
            let flac = directory.appendingPathComponent("plain.flac")
            try encodeFLAC(wave, to: flac, bits: 16)
            let tagged = directory.appendingPathComponent("tagged.flac")
            try SyntheticFLACMetadata.replacingTags(
                in: Data(contentsOf: flac), comments: ["TITLE=Synthetic Song"],
                pictures: [(3, "image/png", Data([0x89, 0x50, 0x4E, 0x47]))]
            ).write(to: tagged)
            #expect(try LosslessConverter.decode(tagged).1 == LosslessConverter.decode(wave).1)
        }
    }
#endif
