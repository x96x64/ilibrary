import Foundation

extension Data {
    /// Reads an unsigned big-endian integer of `width` bytes at `offset`, relative to `startIndex`.
    func bigEndianInteger(at offset: Int, width: Int) -> UInt64 {
        var value: UInt64 = 0
        let base = startIndex + offset
        for index in 0..<width { value = value << 8 | UInt64(self[base + index]) }
        return value
    }

    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    /// Appends the low `width` bytes of `value`, most significant first.
    mutating func appendBigEndian(_ value: UInt64, width: Int) {
        for index in 0..<width { append(UInt8(truncatingIfNeeded: value >> UInt64(8 * (width - 1 - index)))) }
    }

    /// Replaces `width` bytes at `offset`, relative to `startIndex`, with a big-endian integer.
    mutating func setBigEndianInteger(_ value: UInt64, at offset: Int, width: Int) {
        let base = startIndex + offset
        for index in 0..<width {
            self[base + index] = UInt8(truncatingIfNeeded: value >> UInt64(8 * (width - 1 - index)))
        }
    }
}
