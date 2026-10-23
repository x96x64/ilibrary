#if os(macOS)
    import Testing
    @testable import LibraryMac

    @Suite struct MusicRecordTests {
        @Test func snapshotsParseAllComparedFieldsWithoutCallingMusic() throws {
            let fields = [
                "SYNTHETIC-ID", "Song", "Album", "Artist", "Album Artist", "Composer", "Genre", "1958",
                "2", "1", "/synthetic/song.m4a", "unknown", "Comment", "10", "2", "true",
            ]
            let records = try MusicApp.parse(
                fields.joined(separator: MusicApp.fieldSeparator) + MusicApp.recordSeparator)
            #expect(records.count == 1)
            #expect(records[0].comment == "Comment")
            #expect(records[0].trackCount == 10)
            #expect(records[0].discCount == 2)
            #expect(records[0].compilation)
            #expect(throws: MusicAppError.self) { try MusicApp.parse("malformed") }
        }
    }
#endif
