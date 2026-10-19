#if os(macOS)
    import Foundation
    import Testing
    @testable import LibraryMac

    /// These tests send no Apple Event. Live equivalence with the per-track reader is not measured here.
    @Suite struct MusicBulkTests {
        typealias Fields = [String]

        static func row(
            _ id: String, name: String = "Song", location: String = "/synthetic/a.m4a", composer: String = "C",
            genre: String = "G", comment: String = "N", year: String = "1980", trackCount: String = "10",
            discCount: String = "2", compilation: String = "false", status: String = "matched"
        ) -> Fields {
            [
                id, name, "Album", "Artist", "Album Artist", composer, genre, year, "2", "1", location, status,
                comment, trackCount, discCount, compilation,
            ]
        }

        static let samples: [Fields] = [
            row("ID-1"),
            row("ID-2", location: ""),
            row("ID-3", composer: "", genre: "", comment: ""),
            row("ID-4", year: "0", trackCount: "0", discCount: "0"),
            row("ID-5", compilation: "true"),
            row("ID-6", status: ""),
            row("ID-7", status: "kUnk"),
            row("ID-8"),
            row("ID-9"),
            row("ID-10", location: "/synthetic/b.mp3"),
            row("ID-11", location: "/synthetic/c.aiff"),
            row("ID-12", name: "He said \"Hi\" \\ Bye \u{00E9}\u{3042}\u{1F3B5}"),
        ]

        static func perTrack(_ rows: [Fields]) -> String {
            rows.map { $0.joined(separator: MusicApp.fieldSeparator) + MusicApp.recordSeparator }.joined()
        }

        static func bulk(_ rows: [Fields], lastIDs: [String]? = nil, count: Int? = nil) -> [String] {
            let columns = (0..<16).map { column in
                rows.map { $0[column] }.joined(separator: MusicApp.recordSeparator)
            }
            let last = (lastIDs ?? rows.map { $0[0] }).joined(separator: MusicApp.recordSeparator)
            return [String(count ?? rows.count)] + columns + [last]
        }

        @Test func bulkAssemblyEqualsPerTrackParsingForVariedRecords() throws {
            let expected = try MusicApp.parse(Self.perTrack(Self.samples))
            let actual = try MusicApp.assembleBulk(Self.bulk(Self.samples))
            #expect(actual == expected)
            #expect(actual.count == 12)
            #expect(actual[1].location == nil)
            #expect(actual[3].year == 0 && actual[3].trackCount == 0 && actual[3].discCount == 0)
            #expect(actual[4].compilation && !actual[0].compilation)
            #expect(actual[2].composer.isEmpty && actual[2].comment.isEmpty)
            #expect(actual[5].cloudStatus.isEmpty)
            #expect(actual[7].name == actual[8].name && actual[7].persistentID != actual[8].persistentID)
            #expect(actual[11].name.contains("\\") && actual[11].name.contains("\u{3042}"))
        }

        @Test func singleRecordWithEmptyFieldsIsNotConfusedWithAnEmptyLibrary() throws {
            let rows = [Self.row("ID-1", location: "", composer: "", genre: "", comment: "", status: "")]
            #expect(try MusicApp.assembleBulk(Self.bulk(rows)) == MusicApp.parse(Self.perTrack(rows)))
        }

        @Test func emptyLibraryYieldsNoRecords() throws {
            #expect(try MusicApp.assembleBulk(Self.bulk([])) == [])
            #expect(try MusicApp.parse("") == [])
        }

        @Test func assemblyRefusesInconsistentOutput() {
            let rows = Array(Self.samples.prefix(3))
            var shortList = Self.bulk(rows)
            shortList[2] = "Song\u{1E}Song"
            #expect(throws: MusicAppError.self) { try MusicApp.assembleBulk(shortList) }
            #expect(throws: MusicAppError.self) { try MusicApp.assembleBulk(Self.bulk(rows, count: 4)) }
            #expect(throws: MusicAppError.self) { try MusicApp.assembleBulk(Self.bulk(rows, count: -1)) }
            #expect(throws: MusicAppError.self) {
                try MusicApp.assembleBulk(Self.bulk(rows, lastIDs: ["ID-1", "ID-3", "ID-2"]))
            }
            #expect(throws: MusicAppError.self) {
                try MusicApp.assembleBulk(Self.bulk(rows, lastIDs: ["ID-1", "ID-2"]))
            }
            var nonEmpty = Self.bulk([])
            nonEmpty[2] = "Song"
            #expect(throws: MusicAppError.self) { try MusicApp.assembleBulk(nonEmpty) }
            #expect(throws: MusicAppError.self) { try MusicApp.assembleBulk(Array(Self.bulk(rows).dropLast())) }
        }

        @Test func snapshotParsesDatesAndCounts() throws {
            let rows = Array(Self.samples.prefix(3))
            let text = (Self.bulk(rows) + ["5", "0\u{1E}60\u{1E}-86400"]).joined(separator: MusicApp.sectionSeparator)
            let utc = TimeZone(identifier: "UTC")!
            let snapshot = try MusicApp.parseSnapshot(text, timeZone: utc)
            #expect(snapshot.trackCount == 5 && snapshot.fileTrackCount == 3)
            #expect(snapshot.dateAddedSeconds == ["ID-1": 946_684_800, "ID-2": 946_684_860, "ID-3": 946_598_400])
            #expect(snapshot.tracks == (try MusicApp.parse(Self.perTrack(rows))))
            let eastern = TimeZone(identifier: "America/New_York")!
            #expect(MusicApp.unixSeconds(offsetFromYear2000: 0, timeZone: eastern) == 946_702_800)
        }

        @Test func snapshotRefusesInconsistentOutput() {
            let rows = Array(Self.samples.prefix(2))
            let utc = TimeZone(identifier: "UTC")!
            func text(_ total: String, _ dates: String) -> String {
                (Self.bulk(rows) + [total, dates]).joined(separator: MusicApp.sectionSeparator)
            }
            #expect(throws: MusicAppError.self) { try MusicApp.parseSnapshot(text("1", "0\u{1E}0"), timeZone: utc) }
            #expect(throws: MusicAppError.self) { try MusicApp.parseSnapshot(text("2", "0"), timeZone: utc) }
            #expect(throws: MusicAppError.self) { try MusicApp.parseSnapshot(text("2", "0\u{1E}x"), timeZone: utc) }
            #expect(throws: MusicAppError.self) { try MusicApp.parseSnapshot("short", timeZone: utc) }
            let duplicate = [Self.row("ID-1"), Self.row("ID-1")]
            let duplicated = (Self.bulk(duplicate) + ["2", "0\u{1E}0"]).joined(separator: MusicApp.sectionSeparator)
            #expect(throws: MusicAppError.self) { try MusicApp.parseSnapshot(duplicated, timeZone: utc) }
        }

        static func tellBlock(_ script: String) -> String {
            let start = script.range(of: "tell application \"Music\"")!.upperBound
            let end = script.range(of: "end tell", range: start..<script.endIndex)!.lowerBound
            return String(script[start..<end])
        }

        @Test func scriptReadsBulkReferencesInsideTheTellBlock() {
            for dates in [false, true] {
                let script = MusicApp.bulkScript(includeDates: dates)
                let block = Self.tellBlock(script)
                #expect(script.contains("with timeout of 300 seconds"))
                #expect(script.contains("firstIDs is not lastIDs"))
                #expect(script.contains("Property lists differ in length"))
                #expect(block.contains("count of (every file track of library playlist 1)"))
                #expect(!block.contains(" of t\n") && !block.contains(" of t "))
                // Only the documented per-track fallbacks for location and cloud status repeat.
                #expect(block.components(separatedBy: "repeat with").count - 1 == 2)
                #expect(block.contains("-- Per-track fallback: the per-track handler reads location inside try."))
                #expect(block.contains("-- Per-track fallback: the per-track handler reads cloud status inside try."))
                for property in [
                    "persistent ID", "name", "album", "artist", "album artist", "composer", "genre", "year",
                    "track number", "disc number", "location", "cloud status", "comment", "track count",
                    "disc count", "compilation",
                ] {
                    #expect(block.contains("\(property) of every file track of library playlist 1"))
                }
                #expect(block.contains("date added of every file track") == dates)
                #expect(block.contains("count of (every track of library playlist 1)") == dates)
                let outside = String(script[script.range(of: "end timeout")!.upperBound...])
                #expect(outside.contains("POSIX path of") == false)  // conversions live in handlers
                #expect(script.contains("on pathList"))
                #expect(script.contains(MusicApp.bulkUnavailable))
            }
        }

        @Test func dateConversionUsesTheProbeEpochArithmetic() {
            let script = MusicApp.bulkScript(includeDates: true)
            #expect(script.contains("set year of base to 2000"))
            #expect(script.contains("set time of base to 0"))
            #expect(script.contains("- base) as integer"))
        }
    }
#endif
