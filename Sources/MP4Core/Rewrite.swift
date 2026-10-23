import Foundation

/// How a change in the size of the movie box is accommodated.
public enum PaddingPolicy: Sendable {
    /// Absorb the change into adjacent `free` padding when possible, so that chunk offsets stay unchanged.
    case absorb
    /// Always relocate chunk offsets.
    case relocate
}

/// The bytes of a rewritten file: new bytes for rewritten boxes, and ranges copied from the source.
public struct WritePlan: Sendable {
    public enum Segment: Sendable {
        case bytes(Data)
        case source(Range<Int>)
    }

    public let segments: [Segment]
    public let originalMovieSize: Int
    public let movieSize: Int
    public let relocatedChunkOffsets: Int
    public let absorbedIntoPadding: Bool

    public var size: Int {
        segments.reduce(0) {
            switch $1 {
            case .bytes(let data): $0 + data.count
            case .source(let range): $0 + range.count
            }
        }
    }

    /// The complete file in memory, for small files and tests.
    public func data(source: Data) -> Data {
        var output = Data(capacity: size)
        for segment in segments {
            switch segment {
            case .bytes(let data): output.append(data)
            case .source(let range): output.append(source.subdata(in: range))
            }
        }
        return output
    }
}

/// Maps original absolute offsets through a changed top-level layout. Offsets must lie in boxes that are
/// copied unchanged from the source; other boxes are rewritten and cannot be pointed into.
struct LayoutMap {
    let originalRanges: [Range<Int>]
    let newStarts: [Int]
    let copied: [Bool]
    let types: [FourCC]

    func map(_ offset: UInt64) throws -> UInt64 {
        guard
            let index = originalRanges.firstIndex(where: {
                UInt64($0.lowerBound) <= offset && offset < UInt64($0.upperBound)
            })
        else { throw MP4Error.chunkOffsetOutsideFile(offset) }
        guard copied[index] else {
            throw MP4Error.chunkOffsetInRewrittenBox(offset: offset, box: types[index].description)
        }
        return UInt64(newStarts[index]) + offset - UInt64(originalRanges[index].lowerBound)
    }
}

extension MP4File {
    /// Plans the rewritten file. The movie box is rebuilt; every other top-level box is copied unchanged,
    /// and chunk offsets are relocated through the original layout.
    public func writePlan(padding: PaddingPolicy = .absorb) throws -> WritePlan {
        var boxes = self.boxes
        let movieIndex = self.movieIndex
        let originalRanges = self.boxes.map { $0.sourceRange ?? 0..<0 }
        let originalMovieSize = originalRanges[movieIndex].count
        var movie = boxes[movieIndex]
        var absorbed = false

        if padding == .absorb {
            let delta = movie.serializedSize - originalMovieSize
            if delta != 0 {
                if MP4File.absorb(delta, intoPaddingOf: &movie) {
                    absorbed = true
                } else if movieIndex + 1 < boxes.count, boxes[movieIndex + 1].type == "free",
                    !boxes[movieIndex + 1].usesLargeSize, boxes[movieIndex + 1].payloadSize - delta >= 0
                {
                    // A smaller or larger top-level padding box keeps every later box in place.
                    var free = boxes[movieIndex + 1]
                    free.content = .leaf(Data(count: free.payloadSize - delta))
                    boxes[movieIndex + 1] = free
                    absorbed = true
                }
            }
        }
        boxes[movieIndex] = movie

        var newStarts: [Int] = []
        var position = 0
        for box in boxes {
            newStarts.append(position)
            position += box.serializedSize
        }
        let map = LayoutMap(
            originalRanges: originalRanges, newStarts: newStarts, copied: boxes.map(\.isSourceReference),
            types: boxes.map(\.type))

        var relocated = 0
        var failure: Error?
        movie.transformDescendants { box in
            guard failure == nil, box.type == "stco" || box.type == "co64", var payload = box.payload else { return }
            let width = box.type == "co64" ? 8 : 4
            do {
                for (index, offset) in MP4File.offsets(of: box).enumerated() {
                    let moved = try MP4File.relocated(offset, width: width, through: map)
                    if moved != offset { relocated += 1 }
                    payload.setBigEndianInteger(moved, at: 8 + index * width, width: width)
                }
                box.content = .leaf(payload)
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
        boxes[movieIndex] = movie

        var segments: [WritePlan.Segment] = []
        for box in boxes {
            if box.isSourceReference, let range = box.sourceRange {
                segments.append(.source(range))
            } else {
                var bytes = Data()
                box.serialize(into: &bytes)
                segments.append(.bytes(bytes))
            }
        }
        return WritePlan(
            segments: segments, originalMovieSize: originalMovieSize, movieSize: movie.serializedSize,
            relocatedChunkOffsets: relocated, absorbedIntoPadding: absorbed)
    }

    /// Maps one chunk offset. A 32-bit table is never widened to `co64`; an offset beyond 32 bits is an error.
    static func relocated(_ offset: UInt64, width: Int, through map: LayoutMap) throws -> UInt64 {
        let moved = try map.map(offset)
        if width == 4 && moved > UInt64(UInt32.max) { throw MP4Error.chunkOffsetsExceed32Bits }
        return moved
    }

    /// Resizes a `free` box inside `meta` or `udta` so that the movie box keeps its size.
    static func absorb(_ delta: Int, intoPaddingOf movie: inout MP4Box) -> Bool {
        var done = false
        _ = movie.withChild("udta") { udta in
            func resize(_ children: inout [MP4Box]) {
                guard !done, let index = children.firstIndex(where: { $0.type == "free" && $0.payload != nil }),
                    children[index].payloadSize - delta >= 0
                else { return }
                children[index].content = .leaf(Data(count: children[index].payloadSize - delta))
                done = true
            }
            _ = udta.withChild("meta") { meta in
                var children = meta.children
                resize(&children)
                meta.children = children
            }
            var children = udta.children
            resize(&children)
            udta.children = children
        }
        return done
    }
}
