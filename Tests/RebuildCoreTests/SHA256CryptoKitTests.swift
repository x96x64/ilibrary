import Foundation
import Testing

@testable import RebuildCore

#if canImport(CryptoKit)
    import CryptoKit

    @Suite struct SHA256CryptoKitTests {
        @Test func matchesCryptoKitOverManyLengths() {
            var generator = SeededGenerator(seed: 0xdead_beef)
            var lengths = Array(0...300)
            lengths += [511, 512, 513, 1023, 1024, 1025, 4095, 4096, 4097, 65_535, 65_536, 65_537, 1_000_003]
            lengths += [3 * 1_048_576 + 17, 8 * 1_048_576]
            for length in lengths {
                let data = generator.bytes(length)
                let expected = Data(CryptoKit.SHA256.hash(data: data))
                #expect(Data(RebuildCore.SHA256.digest(of: data).bytes) == expected, "length \(length)")
                #expect(Data(chunked(data, sizes: [65, 4096, 1, 63]).bytes) == expected, "chunked length \(length)")
            }
        }
    }
#endif
