import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// The outcome of a verified rewrite.
public struct RewriteReport: Equatable, Sendable {
    public let originalMovieSize: Int
    public let movieSize: Int
    public let relocatedChunkOffsets: Int
    public let absorbedIntoPadding: Bool
    public let size: Int
}

public enum MP4Writer {
    /// Writes `file` to `destination` through a hidden sibling file. The written file is parsed again and its
    /// audio stream compared with the source before it atomically replaces the destination. On any failure,
    /// the partial file is removed and the destination is unchanged.
    @discardableResult
    public static func write(_ file: MP4File, to destination: URL, padding: PaddingPolicy = .absorb) throws
        -> RewriteReport
    {
        let plan = try file.writePlan(padding: padding)
        let directory = destination.deletingLastPathComponent()
        let partial = directory.appendingPathComponent(".\(destination.lastPathComponent).ilibrary-partial")
        let manager = FileManager.default
        if manager.fileExists(atPath: partial.path) { try manager.removeItem(at: partial) }
        guard manager.createFile(atPath: partial.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: partial.path])
        }
        do {
            let handle = try FileHandle(forWritingTo: partial)
            do {
                for segment in plan.segments {
                    switch segment {
                    case .bytes(let data):
                        try handle.write(contentsOf: data)
                    case .source(let range):
                        var start = range.lowerBound
                        while start < range.upperBound {
                            let end = min(start + (8 << 20), range.upperBound)
                            try handle.write(contentsOf: file.source.subdata(in: start..<end))
                            start = end
                        }
                    }
                }
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            let written = try MP4File(contentsOf: partial)
            let attributes = try manager.attributesOfItem(atPath: partial.path)
            guard (attributes[.size] as? NSNumber)?.intValue == plan.size else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: partial.path])
            }
            let differences = written.streamDifferences(from: file)
            guard differences.isEmpty else { throw MP4Error.streamMismatch(differences) }
            guard rename(partial.path, destination.path) == 0 else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
            }
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }
        return RewriteReport(
            originalMovieSize: plan.originalMovieSize, movieSize: plan.movieSize,
            relocatedChunkOffsets: plan.relocatedChunkOffsets, absorbedIntoPadding: plan.absorbedIntoPadding,
            size: plan.size)
    }
}
