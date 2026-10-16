import Foundation

/// Failures of MP4 parsing, rewriting, and verification. Every failure leaves the destination untouched.
public enum MP4Error: Error, Equatable, Sendable, CustomStringConvertible {
    case notMP4
    case missingMovie
    case truncatedBox(type: String, offset: Int, declared: Int, available: Int)
    case trailingBytes(container: String, offset: Int)
    case chunkOffsetOutsideFile(UInt64)
    case chunkOffsetInRewrittenBox(offset: UInt64, box: String)
    /// Version 0.1.0 refuses rather than converts to `co64` (decision 5).
    case chunkOffsetsExceed32Bits
    case encrypted(sampleEntry: String)
    case protectedFile(path: String)
    case streamMismatch([String])
    case invalidValue(key: String, reason: String)

    public var description: String {
        switch self {
        case .notMP4: "the file does not begin with an ftyp box"
        case .missingMovie: "the file has no moov box"
        case .truncatedBox(let type, let offset, let declared, let available):
            "box \(type) at offset \(offset) declares \(declared) bytes, but only \(available) remain"
        case .trailingBytes(let container, let offset):
            "unexpected bytes at offset \(offset) inside \(container)"
        case .chunkOffsetOutsideFile(let offset): "chunk offset \(offset) lies outside the file"
        case .chunkOffsetInRewrittenBox(let offset, let box):
            "chunk offset \(offset) points into the rewritten box \(box)"
        case .chunkOffsetsExceed32Bits:
            "the rewritten file would need chunk offsets beyond 32 bits, which this version does not write"
        case .encrypted(let entry): "the audio is encrypted (sample entry \(entry)); protected audio is not supported"
        case .protectedFile(let path): "\(path) is a protected .m4p file; protected audio is not supported"
        case .streamMismatch(let differences):
            "the rewritten audio stream differs from the source: \(differences.joined(separator: "; "))"
        case .invalidValue(let key, let reason): "invalid value for \(key): \(reason)"
        }
    }
}
