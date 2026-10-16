import FLACCore
import Foundation
import MP4Core
import SyntheticMedia
import Testing

@testable import ilibrary

#if os(macOS)
    import ConversionMac
    import SyntheticMediaMac
#endif

/// A minimal FLAC header with the given comments and pictures, for tag mapping without audio.
func flacMetadata(comments: [String], pictures: [(type: Int, mime: String, data: Data)] = []) throws -> FLACMetadata {
    var information = Data([0x10, 0x00, 0x10, 0x00, 0x00, 0x00, 0x0E, 0x00, 0x40, 0x00])
    let packed = UInt64(44_100) << 44 | UInt64(1) << 41 | UInt64(15) << 36 | UInt64(441_000)
    information += Data((0..<8).map { UInt8(truncatingIfNeeded: packed >> UInt64(8 * (7 - $0))) }) + Data(count: 16)
    let bare = Data("fLaC".utf8) + Data([0x80, 0, 0, 34]) + information + Data([0xFF, 0xF8])
    return try FLACMetadata(data: SyntheticFLACMetadata.replacingTags(in: bare, comments: comments, pictures: pictures))
}

let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(count: 100)

@Suite struct ImportTagTests {
    @Test func standardFieldsAreCarriedAndOthersDropped() throws {
        let metadata = try flacMetadata(
            comments: [
                "TITLE=Synthetic Song", "ARTIST=Example Artist", "ARTIST=Guest Artist", "ALBUM ARTIST=Example Artist",
                "ALBUM=Synthetic Album", "GENRE=Pop", "COMPOSER=Example Writer",
                "COPYRIGHT=℗ 1980 Example Records, Inc.",
                "DATE=1980-06-01", "TRACKNUMBER=3", "TRACKTOTAL=9", "DISCNUMBER=1/2", "COMMENT=remove me",
                "ORGANIZATION=Example Records", "X-SYNTHETIC-IDENTIFIER=00000000", "ANOTHER_UNKNOWN=value",
            ], pictures: [(3, "image/png", png), (4, "image/png", png)])
        let tags = ImportTags(metadata)
        #expect(
            tags.items.map(\.key) == [
                .title, .artist, .albumArtist, .album, .genre, .composer, .copyright, .releaseDate, .trackNumber,
                .discNumber, .artwork,
            ])
        let values = Dictionary(uniqueKeysWithValues: tags.items.map { ($0.key, $0.values) })
        #expect(values[.artist] == [.text("Example Artist, Guest Artist")])
        #expect(values[.albumArtist] == [.text("Example Artist")])
        #expect(values[.releaseDate] == [.text("1980-06-01T00:00:00Z")])
        #expect(values[.trackNumber] == [.pair(number: 3, total: 9)])
        #expect(values[.discNumber] == [.pair(number: 1, total: 2)])
        #expect(values[.artwork] == [.image(png, .png)])
        #expect(tags.excludedStandardFields == ["COMMENT", "ORGANIZATION"])
        #expect(tags.unknownFieldCount == 2)
        #expect(tags.picturesDropped == 1)
        #expect(!tags.summary.contains("SYNTHETIC"))
        #expect(!tags.summary.contains("ANOTHER"))
    }

    @Test func partialDatesAndNumbersAreKeptOrDropped() throws {
        let tags = ImportTags(try flacMetadata(comments: ["DATE=1980", "TRACKNUMBER=x", "DISCNUMBER=2"]))
        let values = Dictionary(uniqueKeysWithValues: tags.items.map { ($0.key, $0.values) })
        #expect(values[.releaseDate] == [.text("1980")])
        #expect(values[.trackNumber] == nil)
        #expect(values[.discNumber] == [.pair(number: 2, total: 0)])
        #expect(!tags.pictureCarried)
    }
}

/// A synthetic M4A with the structure of a purchased file: purchase atoms, purchase information, and padding.
func purchasedM4A() -> Data {
    var fixture = SyntheticMP4(layout: .movieFirst(padding: 64))
    fixture.topPaddingContent = Data("synthetic.purchaser@example.invalid".utf8)
    var scheme = Data(count: 4)
    scheme.append(Data("itun".utf8))
    scheme.appendUInt32(0)
    fixture.sampleEntryExtras = [
        SyntheticMP4.box("udi2", Data(count: 20)),
        SyntheticMP4.box(
            "pinf",
            children: [
                SyntheticMP4.box("frma", Data("mp4a".utf8)), SyntheticMP4.box("schm", scheme),
                SyntheticMP4.box("schi", children: [SyntheticMP4.box("name", Data("Synthetic Purchaser".utf8))]),
            ]),
    ]
    fixture.items = [
        SyntheticMP4.textItem("©nam", "Purchased Song"),
        SyntheticMP4.textItem("apID", "synthetic.purchaser@example.invalid"),
        SyntheticMP4.textItem("ownr", "Synthetic Purchaser"), SyntheticMP4.integerItem("cnID", 100_000_001, width: 4),
        SyntheticMP4.integerItem("stik", 1, width: 1),
    ]
    return fixture.data
}

struct ImportFolder {
    let root: URL
    var downloads: URL { root.appendingPathComponent("Downloads") }
    var staging: URL { root.appendingPathComponent("Staging") }

    init() throws {
        root =
            FileManager.default.temporaryDirectory.appendingPathComponent("ilibrary-import-\(UUID().uuidString)")
            .standardizedFileURL
        try FileManager.default.createDirectory(
            at: downloads.appendingPathComponent("iTunes"), withIntermediateDirectories: true)
        try purchasedM4A().write(to: downloads.appendingPathComponent("iTunes/01 Purchased Song.m4a"))
        try Data("notes".utf8).write(to: downloads.appendingPathComponent("readme.txt"))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func snapshot(_ url: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(atPath: url.path) else { return result }
        while let path = enumerator.nextObject() as? String {
            let file = url.appendingPathComponent(path)
            if pathKind(file) == .file { result[path] = try Data(contentsOf: file) }
        }
        return result
    }
}

@Suite struct ImportCopyTests {
    var noConversion: Environment {
        var environment = Environment.testing
        environment.converter = nil
        return environment
    }

    @Test func purchasedFilesAreCopiedWithoutPurchaseMetadata() throws {
        let folder = try ImportFolder()
        defer { folder.remove() }
        let before = try folder.snapshot(folder.downloads)
        let run = Run(
            ["import", folder.downloads.path, "-o", folder.staging.path, "--from", "itunes"], environment: noConversion)
        #expect(run.status == 0, "\(run.errorText)")
        #expect(run.text.contains("removes 3 purchase items and 2 sample-entry boxes"))
        #expect(run.text.contains("1 other files left untouched"))
        let output = folder.staging.appendingPathComponent("iTunes/01 Purchased Song.m4a")
        let data = try Data(contentsOf: output)
        #expect(data.occurrences(of: Data("synthetic.purchaser@example.invalid".utf8)) == 0)
        #expect(data.occurrences(of: Data("Synthetic Purchaser".utf8)) == 0)
        let written = try MP4File(data: data)
        #expect(written.metadata.map(\.key) == [.title, .atom("stik")])
        #expect(written.streamDifferences(from: try MP4File(data: purchasedM4A())).isEmpty)
        #expect(try folder.snapshot(folder.downloads) == before)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: output.deletingLastPathComponent().path) == [
                "01 Purchased Song.m4a"
            ])
    }

    @Test func aDryRunChangesNothing() throws {
        let folder = try ImportFolder()
        defer { folder.remove() }
        let run = Run(
            ["import", folder.downloads.path, "-o", folder.staging.path, "--dry-run"], environment: noConversion)
        #expect(run.status == 0, "\(run.errorText)")
        #expect(run.text.contains("create \(folder.staging.path)"))
        #expect(run.text.contains("Dry run: nothing was changed."))
        #expect(pathKind(folder.staging) == .missing)
    }

    @Test func refusalsChangeNothing() throws {
        let folder = try ImportFolder()
        defer { folder.remove() }
        var fixture = SyntheticMP4()
        fixture.sampleEntry = "drms"
        let encrypted = fixture.data
        try encrypted.write(to: folder.downloads.appendingPathComponent("iTunes/02 Encrypted.m4a"))
        try Data().write(to: folder.downloads.appendingPathComponent("03 Protected.m4p"))
        try FileManager.default.createSymbolicLink(
            at: folder.downloads.appendingPathComponent("link.m4a"),
            withDestinationURL: folder.downloads.appendingPathComponent("iTunes/01 Purchased Song.m4a"))
        let run = Run(["import", folder.downloads.path, "-o", folder.staging.path], environment: noConversion)
        #expect(run.status == 1)
        #expect(run.text.contains("audio is encrypted"))
        #expect(run.text.contains("protected .m4p files are not supported"))
        #expect(run.text.contains("symbolic links are not followed"))
        #expect(run.errorText.contains("nothing was changed"))
        #expect(pathKind(folder.staging) == .missing)
    }

    @Test func existingDestinationsOutputInsideSourcesAndSpaceAreChecked() throws {
        let folder = try ImportFolder()
        defer { folder.remove() }
        let existing = folder.staging.appendingPathComponent("iTunes/01 Purchased Song.m4a")
        try FileManager.default.createDirectory(
            at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: existing)
        let collision = Run(["import", folder.downloads.path, "-o", folder.staging.path], environment: noConversion)
        #expect(collision.status == 1)
        #expect(collision.text.contains("already exists and is not replaced"))
        #expect(try Data(contentsOf: existing) == Data("keep".utf8))
        try FileManager.default.removeItem(at: folder.staging)

        let inside = Run(
            ["import", folder.downloads.path, "-o", folder.downloads.appendingPathComponent("out").path],
            environment: noConversion)
        #expect(inside.status == 1)
        #expect(inside.errorText.contains("lies inside the source"))

        var full = noConversion
        full.availableCapacity = { _ in 10 }
        let space = Run(["import", folder.downloads.path, "-o", folder.staging.path], environment: full)
        #expect(space.status == 1)
        #expect(space.errorText.contains("bytes are available"))
        #expect(pathKind(folder.staging) == .missing)
    }

    @Test func overlappingSourcesAndUnsafeAncestorsAreRefused() throws {
        let folder = try ImportFolder()
        defer { folder.remove() }
        let overlap = Run(
            [
                "import", folder.downloads.path, folder.downloads.appendingPathComponent("iTunes").path, "-o",
                folder.staging.path,
            ], environment: noConversion)
        #expect(overlap.status == 2)
        #expect(overlap.errorText.contains("give each source once"))
        #expect(pathKind(folder.staging) == .missing)

        // An existing file where a folder belongs, and a link to a folder outside the output, are both refused.
        try FileManager.default.createDirectory(at: folder.staging, withIntermediateDirectories: true)
        try Data("file".utf8).write(to: folder.staging.appendingPathComponent("iTunes"))
        let file = Run(["import", folder.downloads.path, "-o", folder.staging.path], environment: noConversion)
        #expect(file.status == 1)
        #expect(file.text.contains("is not a directory that can hold the output"))
        try FileManager.default.removeItem(at: folder.staging.appendingPathComponent("iTunes"))
        let outside = folder.root.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: folder.staging.appendingPathComponent("iTunes"), withDestinationURL: outside)
        let link = Run(["import", folder.downloads.path, "-o", folder.staging.path], environment: noConversion)
        #expect(link.status == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func conversionAndTheTrashAreRefusedWhereUnavailable() throws {
        let folder = try ImportFolder()
        defer { folder.remove() }
        try SyntheticAudio().wave().write(to: folder.downloads.appendingPathComponent("rip.wav"))
        let conversion = Run(["import", folder.downloads.path, "-o", folder.staging.path], environment: noConversion)
        #expect(conversion.status == 1)
        #expect(conversion.text.contains("requires macOS"))
        var noTrash = noConversion
        noTrash.moveToTrash = nil
        let trash = Run(
            ["import", folder.downloads.path, "-o", folder.staging.path, "--from", "itunes", "--delete-originals"],
            environment: noTrash)
        #expect(trash.status == 1)
        #expect(trash.errorText.contains("requires a Trash"))
        #expect(pathKind(folder.staging) == .missing)
    }

    @Test func originalsAreMovedToTheTrashOnlyAfterVerification() throws {
        let folder = try ImportFolder()
        defer { folder.remove() }
        let trash = folder.root.appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        var environment = noConversion
        environment.moveToTrash = { url in
            let destination = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        let run = Run(
            ["import", folder.downloads.path, "-o", folder.staging.path, "--from", "itunes", "--delete-originals"],
            environment: environment)
        #expect(run.status == 0, "\(run.errorText)")
        #expect(run.text.contains("Moved to the Trash: 1 originals"))
        #expect(pathKind(folder.downloads.appendingPathComponent("iTunes/01 Purchased Song.m4a")) == .missing)
        #expect(pathKind(trash.appendingPathComponent("01 Purchased Song.m4a")) == .file)
        #expect(pathKind(folder.staging.appendingPathComponent("iTunes/01 Purchased Song.m4a")) == .file)
        #expect(pathKind(folder.downloads.appendingPathComponent("readme.txt")) == .file)
    }
}

#if os(macOS)
    @Suite struct ImportConversionTests {
        /// Sources of every kind: tagged FLAC with a cover, WAV, AIFF, a purchased M4A, and an unrelated file.
        func populate(_ folder: ImportFolder) throws {
            let album = folder.downloads.appendingPathComponent("Synthetic Album")
            try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
            let wave = folder.root.appendingPathComponent("source.wav")
            try SyntheticAudio(sampleRate: 48_000, bits: 24, frames: 30_011, seed: 3).wave().write(to: wave)
            let plain = folder.root.appendingPathComponent("plain.flac")
            try encodeFLAC(wave, to: plain, bits: 24)
            try SyntheticFLACMetadata.replacingTags(
                in: Data(contentsOf: plain),
                comments: [
                    "TITLE=First Song", "ARTIST=Example Artist", "ALBUM=Synthetic Album", "TRACKNUMBER=1",
                    "TRACKTOTAL=2",
                    "DATE=1980-06-01", "COMMENT=remove me", "X-SYNTHETIC-IDENTIFIER=00000000",
                ], pictures: [(3, "image/png", png)]
            ).write(to: album.appendingPathComponent("01-First Song_1001.flac"))
            try SyntheticAudio(seed: 4).wave().write(to: album.appendingPathComponent("02-Second Song.wav"))
            try SyntheticAudio(bits: 16, channels: 1, seed: 5).aiff().write(
                to: album.appendingPathComponent("03-Third Song.aiff"))
            try FileManager.default.removeItem(at: wave)
            try FileManager.default.removeItem(at: plain)
        }

        @Test func everyKindIsImportedAndVerified() throws {
            let folder = try ImportFolder()
            defer { folder.remove() }
            try populate(folder)
            let before = try folder.snapshot(folder.downloads)
            let run = Run(["import", folder.downloads.path, "-o", folder.staging.path])
            #expect(run.status == 0, "\(run.errorText)")
            #expect(run.text.contains("Imported and verified: 4 files"))
            #expect(run.text.contains("(FLAC 24-bit 48000 Hz stereo)"))
            #expect(run.text.contains("not carried: COMMENT; 1 unknown fields dropped"))
            #expect(!run.text.contains("SYNTHETIC-IDENTIFIER"))
            for name in ["01-First Song_1001", "02-Second Song", "03-Third Song"] {
                let source = try #require(
                    try FileManager.default.contentsOfDirectory(
                        atPath: folder.downloads.appendingPathComponent("Synthetic Album").path
                    ).first { $0.hasPrefix(name) })
                let output = folder.staging.appendingPathComponent("Synthetic Album/\(name).m4a")
                #expect(
                    try LosslessConverter.decode(output).1
                        == LosslessConverter.decode(
                            folder.downloads.appendingPathComponent("Synthetic Album/\(source)")
                        ).1)
                #expect(try LosslessConverter.format(of: output).codec == "alac")
            }
            let first = try MP4File(
                contentsOf: folder.staging.appendingPathComponent("Synthetic Album/01-First Song_1001.m4a"))
            #expect(first.metadataValues(.title) == [.text("First Song")])
            #expect(first.metadataValues(.trackNumber) == [.pair(number: 1, total: 2)])
            #expect(first.metadataValues(.releaseDate) == [.text("1980-06-01T00:00:00Z")])
            #expect(first.metadataValues(.artwork) == [.image(png, .png)])
            #expect(first.metadataValues(.comment).isEmpty)
            #expect(try folder.snapshot(folder.downloads) == before)
            let leftovers = try folder.snapshot(folder.staging).keys.filter { $0.contains("ilibrary-partial") }
            #expect(leftovers.isEmpty)
        }

        @Test func theRequiredSpaceCountsCoversAndTheTagRewrite() throws {
            let folder = try ImportFolder()
            defer { folder.remove() }
            let wave = folder.root.appendingPathComponent("source.wav")
            let audio = SyntheticAudio(frames: 4_410, seed: 6)
            try audio.wave().write(to: wave)
            let flac = folder.root.appendingPathComponent("plain.flac")
            try encodeFLAC(wave, to: flac, bits: 16)
            let cover = png + Data(count: 3 << 20)
            try SyntheticFLACMetadata.replacingTags(
                in: Data(contentsOf: flac), comments: ["TITLE=Large Cover"], pictures: [(3, "image/png", cover)]
            ).write(to: folder.downloads.appendingPathComponent("01-Large Cover.flac"))
            try FileManager.default.removeItem(at: folder.downloads.appendingPathComponent("iTunes"))
            // Enough for the estimated audio and the margin, but not for the 3 MiB cover written twice.
            var environment = Environment.testing
            environment.availableCapacity = { _ in 5 << 20 }
            let run = Run(["import", folder.downloads.path, "-o", folder.staging.path], environment: environment)
            #expect(run.status == 1)
            #expect(run.errorText.contains("bytes are available"))
            #expect(pathKind(folder.staging) == .missing)
        }

        @Test func moraSelectsFLACAndLeavesOtherSourcesUntouched() throws {
            let folder = try ImportFolder()
            defer { folder.remove() }
            try populate(folder)
            let run = Run(["import", folder.downloads.path, "-o", folder.staging.path, "--from", "mora"])
            #expect(run.status == 0, "\(run.errorText)")
            #expect(run.text.contains("Import: 1 files planned, 0 refused, 4 other files left untouched"))
            #expect(try folder.snapshot(folder.staging).keys.sorted() == ["Synthetic Album/01-First Song_1001.m4a"])
        }

        @Test func unconvertibleSourcesAreRefusedBeforeAnyChange() throws {
            let folder = try ImportFolder()
            defer { folder.remove() }
            try populate(folder)
            let album = folder.downloads.appendingPathComponent("Synthetic Album")
            try SyntheticAudio().wave(floatingPoint: true).write(to: album.appendingPathComponent("04-Float.wav"))
            try SyntheticAudio(bits: 24, channels: 6).wave().write(to: album.appendingPathComponent("05-Six.wav"))
            let wave = SyntheticAudio(frames: 44_100).wave()
            try wave.prefix(wave.count / 2).write(to: album.appendingPathComponent("06-Cut.wav"))
            try SyntheticAudio(seed: 9).wave().write(to: album.appendingPathComponent("02-Second Song.flac.wav"))
            try SyntheticAudio(seed: 8).wave().write(to: album.appendingPathComponent("03-Third Song.wav"))
            let run = Run(["import", folder.downloads.path, "-o", folder.staging.path])
            #expect(run.status == 1)
            #expect(run.text.contains("floating-point PCM"))
            #expect(run.text.contains("6 channels"))
            #expect(run.text.contains("is incomplete"))
            #expect(run.text.contains("would both be imported as"))
            #expect(pathKind(folder.staging) == .missing)
        }

        @Test func aFailureStopsTheImportAndKeepsEveryOriginal() throws {
            let folder = try ImportFolder()
            defer { folder.remove() }
            try populate(folder)
            let before = try folder.snapshot(folder.downloads)
            var environment = Environment.testing
            let real = try #require(environment.converter)
            environment.converter = Converter(
                preflight: real.preflight,
                convert: { source, destination in
                    try real.convert(source, destination)
                    if source.lastPathComponent.hasPrefix("02") { throw CocoaError(.fileWriteOutOfSpace) }
                }, verify: real.verify)
            nonisolated(unsafe) var trashed: [URL] = []
            environment.moveToTrash = { url in
                trashed.append(url)
                return nil
            }
            let run = Run(
                ["import", folder.downloads.path, "-o", folder.staging.path, "--delete-originals"],
                environment: environment)
            #expect(run.status == 1)
            #expect(
                run.errorText.contains("1 files were imported and verified before this failure; no original was moved"))
            #expect(trashed.isEmpty)
            #expect(try folder.snapshot(folder.downloads) == before)
            let written = try folder.snapshot(folder.staging).keys.sorted()
            #expect(written == ["Synthetic Album/01-First Song_1001.m4a"])
        }
    }
#endif
