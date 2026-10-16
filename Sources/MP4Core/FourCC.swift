import Foundation

/// A four-character box or item type. Characters are interpreted as ISO 8859-1, so that `©nam` is one code.
public struct FourCC: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// Creates a code from four ISO 8859-1 characters, or returns nil.
    public init?(validating text: String) {
        guard let bytes = text.data(using: .isoLatin1), bytes.count == 4 else { return nil }
        rawValue = UInt32(bytes.bigEndianInteger(at: 0, width: 4))
    }

    public init(stringLiteral text: String) {
        guard let code = FourCC(validating: text) else { preconditionFailure("invalid four-character code \(text)") }
        self = code
    }

    init(_ data: Data, at offset: Int) {
        rawValue = UInt32(data.bigEndianInteger(at: offset, width: 4))
    }

    var bytes: Data {
        var data = Data()
        data.appendBigEndian(rawValue)
        return data
    }

    public var description: String { String(data: bytes, encoding: .isoLatin1) ?? String(rawValue, radix: 16) }
}
