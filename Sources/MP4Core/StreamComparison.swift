import Foundation

extension MP4File {
    /// Compares the audio streams of two files without decoding: the payloads of the
    /// media-data boxes, the sample tables, and every chunk position relative to its media-data payload.
    /// Returns the differences; an empty result means that the streams are identical.
    public func streamDifferences(from other: MP4File) -> [String] {
        var differences: [String] = []
        let ours = mediaDataPayloads
        let theirs = other.mediaDataPayloads
        if ours.count != theirs.count {
            differences.append("\(ours.count) media-data boxes versus \(theirs.count)")
        } else {
            for (index, (a, b)) in zip(ours, theirs).enumerated()
            where a.count != b.count || source[a] != other.source[b] {
                differences.append("media-data box \(index) differs")
            }
        }
        let tablesA = sampleTables
        let tablesB = other.sampleTables
        if tablesA.count != tablesB.count {
            differences.append("\(tablesA.count) tracks versus \(tablesB.count)")
        }
        for (track, (a, b)) in zip(tablesA, tablesB).enumerated() {
            for name in Set(a.keys).union(b.keys).sorted() where a[name] != b[name] {
                differences.append("track \(track) \(name) differs")
            }
        }
        do {
            if try relativeChunkPositions() != other.relativeChunkPositions() {
                differences.append("chunk positions differ")
            }
        } catch {
            differences.append("chunk positions cannot be resolved: \(error)")
        }
        return differences
    }

    var mediaDataPayloads: [Range<Int>] {
        boxes.filter { $0.type == "mdat" }.compactMap { box in
            guard let range = box.sourceRange else { return nil }
            return (range.lowerBound + box.headerSize)..<range.upperBound
        }
    }

    /// The payloads of the boxes that define samples and timing, per track.
    var sampleTables: [[String: Data]] {
        let names: [FourCC] = ["stts", "stsc", "stsz", "stz2", "ctts", "stss", "elst", "mdhd"]
        return movie.descendants("trak").map { track in
            var tables: [String: Data] = [:]
            for name in names {
                for (index, box) in track.descendants(name).enumerated() {
                    tables["\(name)#\(index)"] = box.payload
                }
            }
            return tables
        }
    }

    /// Each chunk offset as (track, media-data box index, offset within its payload).
    func relativeChunkPositions() throws -> [[Int]] {
        let payloads = mediaDataPayloads
        return try chunkOffsets().enumerated().flatMap { track, offsets in
            try offsets.map { offset -> [Int] in
                guard
                    let index = payloads.firstIndex(where: {
                        UInt64($0.lowerBound) <= offset && offset < UInt64($0.upperBound)
                    })
                else { throw MP4Error.chunkOffsetOutsideFile(offset) }
                return [track, index, Int(offset) - payloads[index].lowerBound]
            }
        }
    }
}
