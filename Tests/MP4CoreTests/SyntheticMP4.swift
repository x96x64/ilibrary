import Foundation

/// Builds small, structurally complete MP4 audio files from synthetic bytes. The media data is a
/// deterministic pattern, not decodable audio; the tests verify structure and byte preservation.
struct SyntheticMP4 {
    enum Layout {
        /// `ftyp moov free mdat`, as Core Audio and the iTunes Store write files.
        case movieFirst(padding: Int)
        /// `ftyp free mdat moov`, as FFmpeg writes files by default.
        case movieLast
    }

    var layout: Layout = .movieFirst(padding: 0)
    var chunkCount = 6
    var chunkSize = 1_000
    var sampleEntry: String = "mp4a"
    var sampleEntryExtras: [Data] = []
    var items: [Data] = []
    var metaPadding = 0
    var useCo64 = false
    /// A QuickTime-style `meta` atom without version and flags.
    var quickTimeMeta = false
    /// Contents of the top-level padding of `movieFirst`, such as residual metadata left by an editor.
    var topPaddingContent: Data?

    static func box(_ type: String, _ payload: Data = Data()) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(8 + payload.count))
        data.append(type.data(using: .isoLatin1)!)
        data.append(payload)
        return data
    }

    static func box(_ type: String, children: [Data], prefix: Data = Data()) -> Data {
        box(type, prefix + children.reduce(Data(), +))
    }

    static func textItem(_ type: String, _ text: String) -> Data {
        var payload = Data()
        payload.appendUInt32(1)
        payload.appendUInt32(0)
        payload.append(Data(text.utf8))
        return box(type, children: [box("data", payload)])
    }

    static func integerItem(_ type: String, _ value: UInt64, width: Int) -> Data {
        var payload = Data()
        payload.appendUInt32(21)
        payload.appendUInt32(0)
        for index in 0..<width { payload.append(UInt8(truncatingIfNeeded: value >> UInt64(8 * (width - 1 - index)))) }
        return box(type, children: [box("data", payload)])
    }

    static func freeformItem(mean: String, name: String, _ text: String) -> Data {
        var meanPayload = Data(count: 4)
        meanPayload.append(Data(mean.utf8))
        var namePayload = Data(count: 4)
        namePayload.append(Data(name.utf8))
        var payload = Data()
        payload.appendUInt32(1)
        payload.appendUInt32(0)
        payload.append(Data(text.utf8))
        return box("----", children: [box("mean", meanPayload), box("name", namePayload), box("data", payload)])
    }

    /// The byte pattern of chunk `index`.
    func chunk(_ index: Int) -> Data {
        Data((0..<chunkSize).map { UInt8(truncatingIfNeeded: ($0 * 31 + index * 97 + 7) % 251) })
    }

    var mediaData: Data { (0..<chunkCount).reduce(Data()) { $0 + chunk($1) } }

    func movie(chunkBase: Int) -> Data {
        var sampleEntryPayload = Data(count: 6)
        sampleEntryPayload.appendUInt16(1)
        sampleEntryPayload.append(Data(count: 8))
        sampleEntryPayload.appendUInt16(2)
        sampleEntryPayload.appendUInt16(16)
        sampleEntryPayload.append(Data(count: 4))
        sampleEntryPayload.appendUInt32(44_100 << 16)
        let configuration =
            sampleEntry == "alac"
            ? SyntheticMP4.box("alac", Data(count: 28)) : SyntheticMP4.box("esds", Data(count: 43))
        sampleEntryPayload.append(configuration)
        for extra in sampleEntryExtras { sampleEntryPayload.append(extra) }
        var stsd = Data(count: 4)
        stsd.appendUInt32(1)
        stsd.append(SyntheticMP4.box(sampleEntry, sampleEntryPayload))

        var stts = Data(count: 4)
        stts.appendUInt32(1)
        stts.appendUInt32(UInt32(chunkCount))
        stts.appendUInt32(1_024)
        var stsc = Data(count: 4)
        stsc.appendUInt32(1)
        stsc.appendUInt32(1)
        stsc.appendUInt32(1)
        stsc.appendUInt32(1)
        var stsz = Data(count: 4)
        stsz.appendUInt32(UInt32(chunkSize))
        stsz.appendUInt32(UInt32(chunkCount))
        var offsets = Data(count: 4)
        offsets.appendUInt32(UInt32(chunkCount))
        for index in 0..<chunkCount {
            let offset = UInt64(chunkBase + index * chunkSize)
            if useCo64 { offsets.appendUInt64(offset) } else { offsets.appendUInt32(UInt32(offset)) }
        }
        let stbl = SyntheticMP4.box(
            "stbl",
            children: [
                SyntheticMP4.box("stsd", stsd), SyntheticMP4.box("stts", stts), SyntheticMP4.box("stsc", stsc),
                SyntheticMP4.box("stsz", stsz), SyntheticMP4.box(useCo64 ? "co64" : "stco", offsets),
            ])
        let minf = SyntheticMP4.box("minf", children: [SyntheticMP4.box("smhd", Data(count: 8)), stbl])
        var mdhd = Data(count: 12)
        mdhd.appendUInt32(44_100)
        mdhd.appendUInt32(UInt32(chunkCount * 1_024))
        mdhd.append(Data(count: 4))
        let mdia = SyntheticMP4.box("mdia", children: [SyntheticMP4.box("mdhd", mdhd), minf])
        let track = SyntheticMP4.box("trak", children: [SyntheticMP4.box("tkhd", Data(count: 84)), mdia])

        var handler = Data(count: 8)
        handler.append(Data("mdirappl".utf8))
        handler.append(Data(count: 10))
        var metaChildren = [SyntheticMP4.box("hdlr", handler), SyntheticMP4.box("ilst", children: items)]
        if metaPadding > 0 { metaChildren.append(SyntheticMP4.box("free", Data(count: metaPadding))) }
        let meta = SyntheticMP4.box("meta", children: metaChildren, prefix: quickTimeMeta ? Data() : Data(count: 4))
        let udta = SyntheticMP4.box("udta", children: [meta])
        return SyntheticMP4.box("moov", children: [SyntheticMP4.box("mvhd", Data(count: 100)), track, udta])
    }

    var data: Data {
        var ftypPayload = Data("M4A ".utf8)
        ftypPayload.appendUInt32(0)
        ftypPayload.append(Data("M4A mp42isom".utf8))
        let ftyp = SyntheticMP4.box("ftyp", ftypPayload)
        let mdat = SyntheticMP4.box("mdat", mediaData)
        switch layout {
        case .movieFirst(let padding):
            let content = topPaddingContent.map { $0 + Data(count: max(0, padding - $0.count)) } ?? Data(count: padding)
            let free = padding > 0 ? SyntheticMP4.box("free", content) : Data()
            let placeholder = movie(chunkBase: 0)
            let base = ftyp.count + placeholder.count + free.count + 8
            return ftyp + movie(chunkBase: base) + free + mdat
        case .movieLast:
            let free = SyntheticMP4.box("free")
            let base = ftyp.count + free.count + 8
            return ftyp + free + mdat + movie(chunkBase: base)
        }
    }
}

extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
    mutating func appendUInt32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
    mutating func appendUInt64(_ value: UInt64) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    func occurrences(of needle: Data) -> Int {
        guard !needle.isEmpty, count >= needle.count else { return 0 }
        var found = 0
        var start = startIndex
        while let range = self[start...].range(of: needle) {
            found += 1
            start = range.upperBound
        }
        return found
    }
}
