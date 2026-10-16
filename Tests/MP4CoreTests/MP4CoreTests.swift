import Foundation
import SyntheticMedia
import Testing

@testable import MP4Core

/// Reads every chunk at its stored offset and compares it with the fixture's pattern.
func chunksAreIntact(_ data: Data, fixture: SyntheticMP4) throws -> Bool {
    let file = try MP4File(data: data)
    let offsets = file.chunkOffsets().flatMap { $0 }
    guard offsets.count == fixture.chunkCount else { return false }
    for (index, offset) in offsets.enumerated() {
        let start = Int(offset)
        guard start + fixture.chunkSize <= data.count,
            data.subdata(in: start..<(start + fixture.chunkSize)) == fixture.chunk(index)
        else { return false }
    }
    return true
}

func rewritten(_ file: MP4File, padding: PaddingPolicy = .absorb) throws -> (Data, WritePlan) {
    let plan = try file.writePlan(padding: padding)
    return (plan.data(source: file.source), plan)
}

let descriptiveItems = [
    SyntheticMP4.textItem("©nam", "Synthetic Song"),
    SyntheticMP4.textItem("©ART", "Example Artist"),
    SyntheticMP4.freeformItem(
        mean: "com.apple.iTunes", name: "iTunSMPB", " 00000000 00000840 000003B7 0000000000001800"),
]

@Suite struct ParsingTests {
    @Test(arguments: [SyntheticMP4.Layout.movieFirst(padding: 0), .movieFirst(padding: 64), .movieLast])
    func unchangedFilesAreReproducedExactly(layout: SyntheticMP4.Layout) throws {
        var fixture = SyntheticMP4(layout: layout)
        fixture.items = descriptiveItems
        let file = try MP4File(data: fixture.data)
        let (output, plan) = try rewritten(file)
        #expect(output == fixture.data)
        #expect(plan.relocatedChunkOffsets == 0)
    }

    @Test func layoutsAreReported() throws {
        let first = try MP4File(data: SyntheticMP4(layout: .movieFirst(padding: 16)).data)
        #expect(first.layout == ["ftyp", "moov", "free", "mdat"])
        #expect(first.movieBeforeMediaData)
        let last = try MP4File(data: SyntheticMP4(layout: .movieLast).data)
        #expect(last.layout == ["ftyp", "free", "mdat", "moov"])
        #expect(!last.movieBeforeMediaData)
    }

    @Test func itemsAreDecodedInOrder() throws {
        var fixture = SyntheticMP4()
        fixture.items = descriptiveItems + [SyntheticMP4.integerItem("plID", 1 << 40, width: 8)]
        let file = try MP4File(data: fixture.data)
        #expect(file.metadata.map(\.key) == [.title, .artist, .gaplessInformation, .atom("plID")])
        #expect(file.metadataValues(.title) == [.text("Synthetic Song")])
        #expect(file.metadataValues(.atom("plID")) == [.integer(1 << 40)])
    }

    @Test func quickTimeMetaWithoutVersionIsParsed() throws {
        var fixture = SyntheticMP4()
        fixture.quickTimeMeta = true
        fixture.items = descriptiveItems
        let file = try MP4File(data: fixture.data)
        #expect(file.metadataValues(.artist) == [.text("Example Artist")])
        #expect(try rewritten(file).0 == fixture.data)
    }

    @Test func truncatedFilesAreRejected() throws {
        let data = SyntheticMP4(layout: .movieFirst(padding: 32)).data
        #expect(throws: MP4Error.self) { try MP4File(data: data.prefix(data.count - 10)) }
        #expect(throws: MP4Error.self) { try MP4File(data: data.prefix(300)) }
    }

    @Test func filesWithoutTypeOrMovieAreRejected() throws {
        #expect(throws: MP4Error.notMP4) { try MP4File(data: SyntheticMP4.box("mdat", Data(count: 16))) }
        let ftyp = SyntheticMP4.box("ftyp", Data("M4A ".utf8) + Data(count: 4))
        #expect(throws: MP4Error.missingMovie) { try MP4File(data: ftyp + SyntheticMP4.box("mdat", Data(count: 16))) }
    }
}

@Suite struct RewriteTests {
    func tagged(_ file: inout MP4File) throws {
        try file.setMetadata(.title, .text("Under the Lights [Synthetic Mix (Demo)]"))
        try file.setMetadata(.copyright, .text("℗ 1980 Example Records, Inc."))
        try file.setMetadata(.releaseDate, .text("1980-06-01T00:00:00Z"))
        try file.setMetadata(.trackNumber, .pair(number: 3, total: 9))
        try file.setMetadata(.discNumber, .pair(number: 1, total: 2))
        try file.setMetadata(.composer, .text("作曲者, Second Writer"))
        try file.setMetadata(.artwork, .image(Data([0x89, 0x50, 0x4E, 0x47]) + Data(count: 3_000), .png))
    }

    @Test func movieBeforeMediaDataRelocatesChunkOffsets() throws {
        var fixture = SyntheticMP4(layout: .movieFirst(padding: 0))
        fixture.items = descriptiveItems
        var file = try MP4File(data: fixture.data)
        try tagged(&file)
        let (output, plan) = try rewritten(file)
        #expect(plan.relocatedChunkOffsets == fixture.chunkCount)
        #expect(try chunksAreIntact(output, fixture: fixture))
        let reread = try MP4File(data: output)
        #expect(reread.streamDifferences(from: try MP4File(data: fixture.data)).isEmpty)
        #expect(reread.metadataValues(.trackNumber) == [.pair(number: 3, total: 9)])
        #expect(reread.metadataValues(.discNumber) == [.pair(number: 1, total: 2)])
        #expect(reread.metadataValues(.composer) == [.text("作曲者, Second Writer")])
        #expect(reread.metadataValues(.gaplessInformation) == fileValues(fixture, .gaplessInformation))
    }

    func fileValues(_ fixture: SyntheticMP4, _ key: MetadataKey) -> [MetadataValue] {
        (try? MP4File(data: fixture.data).metadataValues(key)) ?? []
    }

    @Test func movieAfterMediaDataKeepsChunkOffsets() throws {
        var fixture = SyntheticMP4(layout: .movieLast)
        fixture.items = descriptiveItems
        var file = try MP4File(data: fixture.data)
        try tagged(&file)
        let (output, plan) = try rewritten(file)
        #expect(plan.relocatedChunkOffsets == 0)
        #expect(try chunksAreIntact(output, fixture: fixture))
    }

    @Test func growthIsAbsorbedIntoItemListPadding() throws {
        var fixture = SyntheticMP4(layout: .movieFirst(padding: 0))
        fixture.items = descriptiveItems
        fixture.metaPadding = 200
        var file = try MP4File(data: fixture.data)
        try file.setMetadata(.album, .text("Example Album"))
        let (output, plan) = try rewritten(file)
        #expect(plan.absorbedIntoPadding)
        #expect(plan.relocatedChunkOffsets == 0)
        #expect(output.count == fixture.data.count)
        #expect(try chunksAreIntact(output, fixture: fixture))
    }

    @Test func growthIsAbsorbedIntoTopLevelPadding() throws {
        var fixture = SyntheticMP4(layout: .movieFirst(padding: 500))
        fixture.items = descriptiveItems
        var file = try MP4File(data: fixture.data)
        try file.setMetadata(.album, .text("Example Album"))
        let (output, plan) = try rewritten(file)
        #expect(plan.absorbedIntoPadding)
        #expect(plan.relocatedChunkOffsets == 0)
        #expect(try chunksAreIntact(output, fixture: fixture))
    }

    @Test func insufficientPaddingFallsBackToRelocation() throws {
        var fixture = SyntheticMP4(layout: .movieFirst(padding: 10))
        fixture.items = descriptiveItems
        var file = try MP4File(data: fixture.data)
        try tagged(&file)
        let (output, plan) = try rewritten(file)
        #expect(!plan.absorbedIntoPadding)
        #expect(plan.relocatedChunkOffsets == fixture.chunkCount)
        #expect(try chunksAreIntact(output, fixture: fixture))
    }

    @Test func co64TablesAreRelocated() throws {
        var fixture = SyntheticMP4(layout: .movieFirst(padding: 0))
        fixture.useCo64 = true
        var file = try MP4File(data: fixture.data)
        try tagged(&file)
        let (output, plan) = try rewritten(file)
        #expect(plan.relocatedChunkOffsets == fixture.chunkCount)
        #expect(try chunksAreIntact(output, fixture: fixture))
    }

    @Test func offsetsBeyond32BitsAreRefused() throws {
        let gigabytes = 1 << 30
        let map = LayoutMap(
            originalRanges: [0..<100, 100..<(5 * gigabytes)], newStarts: [0, 200], copied: [false, true],
            types: ["moov", "mdat"])
        #expect(try MP4File.relocated(1_000, width: 4, through: map) == 1_100)
        #expect(throws: MP4Error.chunkOffsetsExceed32Bits) {
            try MP4File.relocated(UInt64(UInt32.max) - 50, width: 4, through: map)
        }
        #expect(try MP4File.relocated(UInt64(UInt32.max) - 50, width: 8, through: map) == UInt64(UInt32.max) + 50)
        #expect(throws: MP4Error.chunkOffsetInRewrittenBox(offset: 50, box: "moov")) {
            try MP4File.relocated(50, width: 4, through: map)
        }
    }

    @Test func repeatedApplicationYieldsIdenticalBytes() throws {
        var fixture = SyntheticMP4(layout: .movieFirst(padding: 0))
        fixture.items = descriptiveItems
        var file = try MP4File(data: fixture.data)
        try tagged(&file)
        let first = try rewritten(file).0
        var again = try MP4File(data: first)
        try tagged(&again)
        #expect(try rewritten(again).0 == first)
    }

    @Test func replacingAnItemKeepsItsPosition() throws {
        var fixture = SyntheticMP4()
        fixture.items = descriptiveItems
        var file = try MP4File(data: fixture.data)
        try file.setMetadata(.title, .text("Replaced"))
        #expect(file.metadata.map(\.key) == [.title, .artist, .gaplessInformation])
        try file.removeMetadata(.artist)
        #expect(file.metadata.map(\.key) == [.title, .gaplessInformation])
    }

    @Test func itemListIsCreatedWhenAbsent() throws {
        var file = try MP4File(data: SyntheticMP4(layout: .movieLast).data)
        try file.removeMetadata(.title)
        try file.setMetadata(.album, .text("Example Album"))
        let reread = try MP4File(data: try rewritten(file).0)
        #expect(reread.metadataValues(.album) == [.text("Example Album")])
    }

    @Test func valuesAreEncodedWithTheirConventionalWidths() throws {
        var file = try MP4File(data: SyntheticMP4().data)
        try file.setMetadata(.atom("plID"), .integer(Int64(1) << 40))
        try file.setMetadata(.compilation, .integer(1))
        try file.setMetadata(.trackNumber, .pair(number: 1, total: 12))
        try file.setMetadata(.discNumber, .pair(number: 2, total: 2))
        let items = try MP4File(data: try rewritten(file).0).movie.descendants("data")
        #expect(items.map { $0.payload!.count - 8 } == [8, 1, 8, 6])
        #expect(throws: MP4Error.self) { try file.setMetadata(.compilation, .integer(300)) }
        #expect(ImageFormat(detecting: Data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
        #expect(ImageFormat(detecting: Data("GIF8".utf8)) == nil)
    }
}

@Suite struct WriterTests {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ilibrary-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func writesThroughAVerifiedPartialFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var fixture = SyntheticMP4(layout: .movieFirst(padding: 0))
        fixture.items = descriptiveItems
        let url = directory.appendingPathComponent("01 Track.m4a")
        try fixture.data.write(to: url)
        var file = try MP4File(contentsOf: url)
        try file.setMetadata(.title, .text("Rewritten Title"))
        let report = try MP4Writer.write(file, to: url)
        #expect(report.relocatedChunkOffsets == fixture.chunkCount)
        #expect(try MP4File(contentsOf: url).metadataValues(.title) == [.text("Rewritten Title")])
        #expect(try chunksAreIntact(Data(contentsOf: url), fixture: fixture))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["01 Track.m4a"])
    }

    @Test func failedRewritesLeaveTheDestinationUnchanged() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Chunk offsets that point into the movie box cannot be relocated.
        var fixture = SyntheticMP4(layout: .movieFirst(padding: 0))
        fixture.items = descriptiveItems
        var data = fixture.data
        let file = try MP4File(data: data)
        let table = file.movie.descendants("stco")[0].sourceRange!
        data.setBigEndianInteger(40, at: table.lowerBound + 16, width: 4)
        let url = directory.appendingPathComponent("01 Track.m4a")
        try data.write(to: url)
        var damaged = try MP4File(contentsOf: url)
        try damaged.setMetadata(.title, .text("Never Written"))
        #expect(throws: MP4Error.self) { try MP4Writer.write(damaged, to: url) }
        #expect(try Data(contentsOf: url) == data)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["01 Track.m4a"])
    }
}

@Suite struct PurchaseMetadataTests {
    static let account = "synthetic.purchaser@example.invalid"
    static let owner = "Synthetic Purchaser"

    /// A synthetic file with the structure observed in a purchased file: store atoms in the item list,
    /// undocumented sample-entry children, purchase information with the `itun` scheme, and padding.
    static func purchasedFixture(entry: String = "mp4a", extraEntryChildren: [Data] = []) -> SyntheticMP4 {
        var fixture = SyntheticMP4(layout: .movieFirst(padding: 128))
        fixture.sampleEntry = entry
        fixture.topPaddingContent = Data(account.utf8)
        var scheme = Data(count: 4)
        scheme.append(Data("itun".utf8))
        scheme.appendUInt32(0)
        var name = Data(owner.utf8)
        name.append(Data(count: 256 - name.count))
        let purchaseInformation = SyntheticMP4.box(
            "pinf",
            children: [
                SyntheticMP4.box("frma", Data("mp4a".utf8)), SyntheticMP4.box("schm", scheme),
                SyntheticMP4.box(
                    "schi",
                    children: [
                        SyntheticMP4.box("user", Data(count: 4)), SyntheticMP4.box("cert", Data(count: 4)),
                        SyntheticMP4.box("righ", Data(count: 80)), SyntheticMP4.box("name", name),
                        SyntheticMP4.box("chtb", Data(count: 632)),
                    ]),
                SyntheticMP4.box("sign", Data(count: 128)),
            ])
        fixture.sampleEntryExtras =
            [
                SyntheticMP4.box("dmix", Data(count: 10)), SyntheticMP4.box("udi2", Data(count: 58)),
                SyntheticMP4.box("udc2", Data(count: 23)), SyntheticMP4.box("udex", Data(count: 27)),
                SyntheticMP4.box("sbtd", Data(count: 7)), purchaseInformation,
                SyntheticMP4.box("free", Data(account.utf8) + Data(count: 64)),
            ] + extraEntryChildren
        fixture.items =
            descriptiveItems + [
                SyntheticMP4.textItem("apID", account), SyntheticMP4.textItem("ownr", owner),
                SyntheticMP4.textItem("purd", "2026-10-16 00:00:00"),
                SyntheticMP4.integerItem("cnID", 100_000_001, width: 4),
                SyntheticMP4.integerItem("atID", 100_000_002, width: 4),
                SyntheticMP4.integerItem("plID", 100_000_003, width: 8),
                SyntheticMP4.integerItem("geID", 100_000_004, width: 4),
                SyntheticMP4.integerItem("sfID", 143_462, width: 4),
                SyntheticMP4.integerItem("cmID", 100_000_005, width: 4),
                SyntheticMP4.textItem("xid ", "Synthetic:isrc:ZZ0000000000"),
                SyntheticMP4.integerItem("stik", 1, width: 1),
            ]
        fixture.metaPadding = 48
        return fixture
    }

    @Test func purchaseMetadataIsRemovedWithoutChangingTheStream() throws {
        let fixture = PurchaseMetadataTests.purchasedFixture()
        let original = try MP4File(data: fixture.data)
        #expect(fixture.data.occurrences(of: Data(PurchaseMetadataTests.account.utf8)) == 3)
        var file = original
        let removal = try file.removePurchaseMetadata()
        #expect(
            removal.removedItems.map(\.description) == [
                "apID", "ownr", "purd", "cnID", "atID", "plID", "geID", "sfID", "cmID", "xid ",
            ])
        #expect(
            removal.removedSampleEntryBoxes == [
                "mp4a/dmix", "mp4a/udi2", "mp4a/udc2", "mp4a/udex", "mp4a/sbtd", "mp4a/pinf", "mp4a/free",
            ])
        let output = try rewritten(file).0
        #expect(output.occurrences(of: Data(PurchaseMetadataTests.account.utf8)) == 0)
        #expect(output.occurrences(of: Data(PurchaseMetadataTests.owner.utf8)) == 0)
        let cleaned = try MP4File(data: output)
        #expect(cleaned.sampleEntries.map { $0.children.map(\.type) } == [["esds"]])
        #expect(cleaned.metadata.map(\.key) == [.title, .artist, .gaplessInformation, .atom("stik")])
        #expect(cleaned.streamDifferences(from: original).isEmpty)
        #expect(try chunksAreIntact(output, fixture: fixture))
    }

    @Test func purchaseInformationInUnencryptedEntriesIsRemovedNotRefused() throws {
        // A sinf box inside an mp4a entry does not make the audio encrypted; only the entry type does.
        let fixture = PurchaseMetadataTests.purchasedFixture(extraEntryChildren: [
            SyntheticMP4.box("sinf", Data(count: 16))
        ])
        var file = try MP4File(data: fixture.data)
        try file.ensureNotEncrypted(path: "01 Purchased.m4a")
        let removal = try file.removePurchaseMetadata()
        #expect(removal.removedSampleEntryBoxes.contains("mp4a/sinf"))
    }

    @Test(arguments: ["drms", "enca"])
    func encryptedSampleEntriesAreRefused(entry: String) throws {
        var file = try MP4File(data: PurchaseMetadataTests.purchasedFixture(entry: entry).data)
        #expect(throws: MP4Error.encrypted(sampleEntry: entry)) { try file.removePurchaseMetadata() }
    }

    @Test func protectedPathsAreRefused() throws {
        let file = try MP4File(data: SyntheticMP4().data)
        #expect(throws: MP4Error.protectedFile(path: "01 Track.M4P")) {
            try file.ensureNotEncrypted(path: "01 Track.M4P")
        }
    }

    @Test func appleLosslessConfigurationIsKept() throws {
        var fixture = SyntheticMP4()
        fixture.sampleEntry = "alac"
        var file = try MP4File(data: fixture.data)
        let removal = try file.removePurchaseMetadata()
        #expect(removal.isEmpty)
        #expect(file.sampleEntries.map { $0.children.map(\.type) } == [["alac"]])
    }
}
