import Foundation

/// A parsed MP4 file. Only the movie box is decoded; other top-level boxes refer to `source`.
public struct MP4File: Sendable {
    public let source: Data
    public var boxes: [MP4Box]

    public init(data: Data) throws {
        source = data.startIndex == 0 ? data : Data(data)
        boxes = try MP4File.parse(source, range: 0..<source.count, parent: nil).boxes
        guard boxes.first?.type == "ftyp" else { throw MP4Error.notMP4 }
        guard boxes.contains(where: { $0.type == "moov" }) else { throw MP4Error.missingMovie }
    }

    /// Reads a file through a memory mapping, so that media data is not loaded.
    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public var layout: [FourCC] { boxes.map(\.type) }

    public var movieIndex: Int { boxes.firstIndex { $0.type == "moov" }! }

    public var movie: MP4Box {
        get { boxes[movieIndex] }
        set { boxes[movieIndex] = newValue }
    }

    public var movieBeforeMediaData: Bool {
        movieIndex < (boxes.firstIndex { $0.type == "mdat" } ?? Int.max)
    }

    /// The sample entries of every track, in file order.
    public var sampleEntries: [MP4Box] {
        movie.descendants("stsd").flatMap(\.children)
    }

    /// The chunk offsets of every track, as stored in `stco` or `co64`.
    public func chunkOffsets() -> [[UInt64]] {
        movie.descendants("trak").map { track in
            track.descendants("stco").flatMap { MP4File.offsets(of: $0) }
                + track.descendants("co64").flatMap { MP4File.offsets(of: $0) }
        }
    }

    static func offsets(of table: MP4Box) -> [UInt64] {
        guard let payload = table.payload, payload.count >= 8 else { return [] }
        let width = table.type == "co64" ? 8 : 4
        let count = Int(payload.bigEndianInteger(at: 4, width: 4))
        guard payload.count >= 8 + count * width else { return [] }
        return (0..<count).map { payload.bigEndianInteger(at: 8 + $0 * width, width: width) }
    }

    // MARK: - Parsing

    static let plainContainers: Set<FourCC> = [
        "moov", "trak", "mdia", "minf", "stbl", "udta", "edts", "dinf", "ilst", "sinf", "pinf", "schi", "wave", "tref",
    ]
    static let audioSampleEntries: Set<FourCC> = [
        "mp4a", "alac", "drms", "enca", "ac-3", "ec-3", "fLaC", "Opus", "lpcm", "sowt", "twos", "in24",
    ]

    /// The length of the non-box prefix of a container, or nil for a box without children.
    static func containerPrefix(type: FourCC, parent: FourCC?, data: Data, payload: Range<Int>) -> Int? {
        if plainContainers.contains(type) || parent == "ilst" { return 0 }
        switch type {
        case "meta":
            // An ISO full box carries a version and flags before its children; a QuickTime atom does not.
            if payload.count >= 8, FourCC(data, at: payload.lowerBound + 4) == "hdlr" { return 0 }
            return 4
        case "stsd":
            return 8
        default:
            break
        }
        if parent == "stsd", audioSampleEntries.contains(type), payload.count >= 28 {
            let version = data.bigEndianInteger(at: payload.lowerBound + 8, width: 2)
            return 28 + (version == 1 ? 16 : version == 2 ? 36 : 0)
        }
        return nil
    }

    static func parse(_ data: Data, range: Range<Int>, parent: FourCC?) throws -> (boxes: [MP4Box], trailer: Data) {
        var boxes: [MP4Box] = []
        var offset = range.lowerBound
        while offset < range.upperBound {
            let remaining = range.upperBound - offset
            if remaining < 8 {
                // QuickTime permits a zero terminator at the end of some containers.
                let tail = data.subdata(in: offset..<range.upperBound)
                guard parent != nil, tail.allSatisfy({ $0 == 0 }) else {
                    throw MP4Error.trailingBytes(container: parent?.description ?? "file", offset: offset)
                }
                return (boxes, tail)
            }
            var size = Int(data.bigEndianInteger(at: offset, width: 4))
            let type = FourCC(data, at: offset + 4)
            var header = 8
            var largeSize = false
            if size == 1 {
                guard remaining >= 16 else {
                    throw MP4Error.truncatedBox(
                        type: type.description, offset: offset, declared: 16, available: remaining)
                }
                let large = data.bigEndianInteger(at: offset + 8, width: 8)
                size = large > UInt64(Int.max) ? Int.max : Int(large)
                header = 16
                largeSize = true
            } else if size == 0 {
                size = remaining
            }
            guard size >= header, size <= remaining else {
                throw MP4Error.truncatedBox(
                    type: type.description, offset: offset, declared: size, available: remaining)
            }
            let source = offset..<(offset + size)
            let payload = (offset + header)..<(offset + size)
            if parent == nil && type != "moov" {
                boxes.append(MP4Box(type: type, content: .source, sourceRange: source, usesLargeSize: largeSize))
            } else if let prefixLength = containerPrefix(type: type, parent: parent, data: data, payload: payload),
                prefixLength <= payload.count
            {
                let prefixEnd = payload.lowerBound + prefixLength
                let (children, trailer) = try parse(data, range: prefixEnd..<payload.upperBound, parent: type)
                let content = MP4Box.Content.container(
                    prefix: data.subdata(in: payload.lowerBound..<prefixEnd), children: children, trailer: trailer)
                boxes.append(MP4Box(type: type, content: content, sourceRange: source, usesLargeSize: largeSize))
            } else {
                let content = MP4Box.Content.leaf(data.subdata(in: payload))
                boxes.append(MP4Box(type: type, content: content, sourceRange: source, usesLargeSize: largeSize))
            }
            offset += size
        }
        return (boxes, Data())
    }
}
