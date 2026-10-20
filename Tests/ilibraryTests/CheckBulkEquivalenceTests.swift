#if canImport(LibraryMac) && os(macOS)
    import Foundation
    import Testing

    @testable import LibraryMac
    @testable import ilibrary

    /// A substitute Music library whose track read is supplied by a closure. These tests send no Apple Event.
    struct ReadingMusic: MusicLibrary {
        let read: @Sendable () throws -> [LibraryTrack]

        func mediaFolder() -> URL? { nil }
        func tracks(album: String) throws -> [LibraryTrack] { [] }
        func allTracks() throws -> [LibraryTrack] { try read() }
        func librarySnapshot() throws -> LibrarySnapshot {
            LibrarySnapshot(tracks: [], trackCount: 0, fileTrackCount: 0, dateAddedSeconds: [:])
        }
        func track(persistentID: String) throws -> LibraryTrack? { nil }
        func add(_ files: [URL]) throws -> [LibraryTrack] { [] }
    }

    /// Compares `check --library` under the per-track reader and under the selection function that prefers the
    /// bulk reader, for one synthetic Music state expressed as rows of the sixteen per-track fields.
    struct BulkEquivalenceFixture {
        typealias Fields = [String]

        struct Boom: Error, CustomStringConvertible {
            var description: String { "per-track read failed" }
        }

        let library: SyntheticLibrary
        var rows: [Fields]
        let files: [URL]

        static func fields(_ track: LibraryTrack) -> Fields {
            [
                track.persistentID, track.name, track.album, track.artist, track.albumArtist, track.composer,
                track.genre, String(track.year), String(track.trackNumber), String(track.discNumber),
                track.location ?? "", track.cloudStatus, track.comment, String(track.trackCount),
                String(track.discCount), track.compilation ? "true" : "false",
            ]
        }

        static func perTrackText(_ rows: [Fields]) -> String {
            rows.map { $0.joined(separator: MusicApp.fieldSeparator) + MusicApp.recordSeparator }.joined()
        }

        static func bulkText(_ rows: [Fields]) -> String {
            let columns = (0..<16).map { column in
                rows.map { $0[column] }.joined(separator: MusicApp.recordSeparator)
            }
            let last = rows.map { $0[0] }.joined(separator: MusicApp.recordSeparator)
            return ([String(rows.count)] + columns + [last]).joined(separator: MusicApp.sectionSeparator)
        }

        /// Twelve registrations over nine synthetic files, covering the cases that `check --library` classifies.
        init() throws {
            library = try SyntheticLibrary()
            files = try library.m4aFiles()
            let music = FakeMusic(media: library.root)
            _ = try music.add(files)
            for index in music.library.indices {
                let file = try LibraryFiles.read(URL(fileURLWithPath: music.library[index].location!))
                music.library[index].composer = LibraryFiles.text(file.file, .composer) ?? ""
                music.library[index].genre = LibraryFiles.text(file.file, .genre) ?? ""
                music.library[index].year = Int(LibraryFiles.text(file.file, .releaseDate)?.prefix(4) ?? "") ?? 0
            }
            var rows = music.library.map(Self.fields)
            rows[0][5] = ""  // an empty composer, which differs from the file
            rows[1][7] = "unknown"  // a non-numeric year, which parses to 0
            rows[1][13] = "n/a"  // a non-numeric track count, which parses to 0
            rows[2][11] = "matched"
            rows[3][11] = "subscription"
            rows[4][11] = "uploaded"
            rows[5][11] = ""
            rows[6][11] = "kUnk"
            rows[5][6] = ""  // an empty genre
            rows[5][12] = ""  // an empty comment
            try FileManager.default.removeItem(at: files[7])  // a registration whose file is missing
            let notRegistered = rows.remove(at: 8)  // a file that is not in the library
            #expect(notRegistered[10] == files[8].path)
            var duplicate = rows[2]  // two registrations of one file
            duplicate[0] = "DUPLICATE-ID"
            rows.append(duplicate)
            var withoutFile = rows[0]  // a registration without a file
            withoutFile[0] = "NO-FILE-ID"
            withoutFile[10] = ""
            rows.append(withoutFile)
            var mp3 = rows[0]
            mp3[0] = "MP3-ID"
            mp3[10] = library.root.appendingPathComponent("synthetic.mp3").path
            rows.append(mp3)
            var aiff = rows[0]
            aiff[0] = "AIFF-ID"
            aiff[10] = library.root.appendingPathComponent("synthetic.aiff").path
            rows.append(aiff)
            self.rows = rows
        }

        func environment(_ read: @escaping @Sendable () throws -> [LibraryTrack]) -> Environment {
            var environment = Environment.testing
            environment.readDates = nil
            environment.music = ReadingMusic(read: read)
            return environment
        }

        var originalTracks: [LibraryTrack] {
            get throws { try MusicApp.parse(Self.perTrackText(rows)).map(SystemMusicLibrary.convert) }
        }

        func optimizedTracks(bulk: @escaping () throws -> String) throws -> [LibraryTrack] {
            let text = Self.perTrackText(rows)
            return try MusicApp.allTracksPreferringBulk(bulk: bulk, perTrack: { try MusicApp.parse(text) })
                .map(SystemMusicLibrary.convert)
        }

        func runs(_ arguments: [String], original: [LibraryTrack], optimized: [LibraryTrack]) -> (Run, Run) {
            (
                Run(arguments, environment: environment { original }),
                Run(arguments, environment: environment { optimized })
            )
        }
    }

    @Suite struct CheckBulkEquivalenceTests {
        func expectIdentical(_ first: Run, _ second: Run) {
            #expect(first.status == second.status)
            #expect(first.output == second.output)
            #expect(first.errors == second.errors)
        }

        func expectFindings(_ run: Run, _ fixture: BulkEquivalenceFixture) {
            let text = run.text
            #expect(run.status == 1, "\(text)")
            #expect(run.errors.isEmpty)
            #expect(text.contains("cloud status is matched"))
            #expect(text.contains("cloud status is subscription"))
            #expect(!text.contains("cloud status is uploaded"))
            #expect(text.contains("composer differs: file \"Example Writer\", library \"\""))
            #expect(text.contains("year differs"))
            #expect(text.contains("track count differs"))
            #expect(text.contains("in the library 2 times"))
            #expect(text.contains("not in the library"))
            #expect(text.contains("a library track whose file is missing"))
            #expect(text.contains("note: artwork, copyright, and full release dates are not compared"))
        }

        @Test func bulkAndPerTrackReadsGiveIdenticalLibraryOnlyCheckResults() throws {
            let fixture = try BulkEquivalenceFixture()
            defer { fixture.library.remove() }
            let original = try fixture.originalTracks
            let optimized = try fixture.optimizedTracks(bulk: { BulkEquivalenceFixture.bulkText(fixture.rows) })
            #expect(optimized == original)
            #expect(original.count == 12)
            #expect(original.contains { $0.location == nil })
            #expect(
                Set(original.map(\.cloudStatus)).isSuperset(of: ["matched", "subscription", "uploaded", "", "kUnk"]))
            let (first, second) = fixture.runs(["check", "--library"], original: original, optimized: optimized)
            expectIdentical(first, second)
            #expect(first.status == 1, "\(first.text)")
            #expect(first.text.contains("cloud status is matched"))
            #expect(first.text.contains("cloud status is subscription"))
            #expect(!first.text.contains("cloud status is uploaded"))
            #expect(first.text.contains("2 library file(s) use other formats"))
            #expect(first.text.contains("cannot scan"))
            #expect(first.text.contains("a library track without a file"))
        }

        @Test func bulkAndPerTrackReadsGiveIdenticalCheckResultsForAPath() throws {
            let fixture = try BulkEquivalenceFixture()
            defer { fixture.library.remove() }
            let original = try fixture.originalTracks
            let optimized = try fixture.optimizedTracks(bulk: { BulkEquivalenceFixture.bulkText(fixture.rows) })
            let arguments = ["check", fixture.library.root.path, "--library"]
            let (first, second) = fixture.runs(arguments, original: original, optimized: optimized)
            expectIdentical(first, second)
            expectFindings(first, fixture)
        }

        @Test func aFailedBulkReadFallsBackToTheIdenticalPerTrackResult() throws {
            let fixture = try BulkEquivalenceFixture()
            defer { fixture.library.remove() }
            let original = try fixture.originalTracks
            let failures: [() throws -> String] = [
                { throw MusicAppError.scriptFailed("bulk") },
                { MusicApp.bulkUnavailable },
                { "garbage" },
            ]
            for failure in failures {
                let optimized = try fixture.optimizedTracks(bulk: failure)
                #expect(optimized == original)
                for arguments in [["check", "--library"], ["check", fixture.library.root.path, "--library"]] {
                    let (first, second) = fixture.runs(arguments, original: original, optimized: optimized)
                    expectIdentical(first, second)
                    #expect(first.status == 1)
                }
            }
        }

        @Test func whenBothReadsFailTheCommandReportsThePerTrackError() throws {
            let perTrackError = MusicAppError.scriptFailed("per-track")
            let original: @Sendable () throws -> [LibraryTrack] = { throw perTrackError }
            let optimized: @Sendable () throws -> [LibraryTrack] = {
                try MusicApp.allTracksPreferringBulk(
                    bulk: { throw MusicAppError.scriptFailed("bulk") }, perTrack: { throw perTrackError }
                ).map(SystemMusicLibrary.convert)
            }
            for arguments in [["check", "--library"], ["check", NSTemporaryDirectory(), "--library"]] {
                var base = Environment.testing
                base.readDates = nil
                var originalEnvironment = base
                originalEnvironment.music = ReadingMusic(read: original)
                var optimizedEnvironment = base
                optimizedEnvironment.music = ReadingMusic(read: optimized)
                let first = Run(arguments, environment: originalEnvironment)
                let second = Run(arguments, environment: optimizedEnvironment)
                expectIdentical(first, second)
                #expect(first.status != 0)
                #expect(first.errorText.contains("per-track"), "\(first.errorText)")
                #expect(!first.errorText.contains("bulk"))
            }
        }
    }
#endif
