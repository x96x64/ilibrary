#if os(macOS)
    import Foundation
    import Testing
    @testable import LibraryMac

    /// These tests send no Apple Event; they check parsing and selection logic, not the behavior of Music.
    @Suite struct MusicBulkTests {
        typealias Fields = [String]

        static func row(
            _ id: String, name: String = "Song", location: String = "/synthetic/a.m4a", composer: String = "C",
            genre: String = "G", comment: String = "N", year: String = "1958", trackCount: String = "10",
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
            let text = (Self.bulk(rows) + ["5", "0 0\u{1E}0 60\u{1E}-1 0"]).joined(separator: MusicApp.sectionSeparator)
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
            #expect(throws: MusicAppError.self) { try MusicApp.parseSnapshot(text("1", "0 0\u{1E}0 0"), timeZone: utc) }
            #expect(throws: MusicAppError.self) { try MusicApp.parseSnapshot(text("2", "0 0"), timeZone: utc) }
            #expect(throws: MusicAppError.self) { try MusicApp.parseSnapshot(text("2", "0 0\u{1E}x"), timeZone: utc) }
            #expect(throws: MusicAppError.self) { try MusicApp.parseSnapshot("short", timeZone: utc) }
            let duplicate = [Self.row("ID-1"), Self.row("ID-1")]
            let duplicated = (Self.bulk(duplicate) + ["2", "0 0\u{1E}0 0"]).joined(separator: MusicApp.sectionSeparator)
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
            #expect(script.contains("set x to (contents of v) - base"))
            #expect(script.contains("set d to x div 86400"))
            #expect(script.contains("set r to (x - d * 86400) as integer"))
            #expect(script.contains("(d as text) & \" \" & (r as text)"))
        }

        @Test func scriptNeverCoercesTheFullDateDifferenceToText() {
            let script = MusicApp.bulkScript(includeDates: true)
            #expect(!script.contains("as integer) as text"))
            #expect(!script.contains("- base) as text"))
            #expect(!script.contains("(x as text)") && !script.contains("x as text"))
        }

        static let utc = TimeZone(identifier: "UTC")!

        func snapshotDate(_ item: String) throws -> Int {
            let rows = [Self.row("ID-1")]
            let text = (Self.bulk(rows) + ["1", item]).joined(separator: MusicApp.sectionSeparator)
            return try MusicApp.parseSnapshot(text, timeZone: Self.utc).dateAddedSeconds["ID-1"]!
        }

        @Test func presentDayOffsetRecombinesExactlyToTheSecond() throws {
            // 2026-10-20T12:34:56Z is 1_792_499_696 s after 1970, so 845_814_896 s after 2000-01-01Z.
            let offset = 1_792_499_696 - 946_684_800
            #expect(offset == 845_814_896)
            let days = offset / 86400
            let remainder = offset - days * 86400
            #expect(try snapshotDate("\(days) \(remainder)") == 1_792_499_696)
            #expect(try snapshotDate("9789 41600") == 946_684_800 + 845_811_200)
        }

        @Test func integerBoundaryOffsetsRecombineExactly() throws {
            #expect(try MusicApp.dateOffset("6213 67711") == 536_870_911)
            #expect(try MusicApp.dateOffset("6213 67712") == 536_870_912)
            #expect(try MusicApp.dateOffset("-6213 -67712") == -536_870_912)
            #expect(try snapshotDate("6213 67712") == 946_684_800 + 536_870_912)
        }

        @Test func negativeOffsetsBeforeTheYear2000RecombineExactly() throws {
            #expect(try MusicApp.dateOffset("0 -1") == -1)
            #expect(try MusicApp.dateOffset("-1 0") == -86400)
            #expect(try MusicApp.dateOffset("-1 -1") == -86401)
            #expect(try MusicApp.dateOffset("0 -86399") == -86399)
            #expect(try MusicApp.dateOffset("-11574 -6400") == -1_000_000_000)
            #expect(try snapshotDate("-1 -1") == 946_684_800 - 86401)
        }

        @Test func remaindersRoundedToAFullDayRecombineCorrectly() throws {
            #expect(try MusicApp.dateOffset("0 86400") == 86400)
            #expect(try MusicApp.dateOffset("0 -86400") == -86400)
            #expect(try MusicApp.dateOffset("9789 86400") == 9790 * 86400)
            #expect(try MusicApp.dateOffset("-0 0") == 0)
        }

        @Test func dateItemsRefuseEverythingButTwoPlainIntegers() {
            let refused = [
                "8.458112E+8", "8.458112E+8 0", "9789 4.16E+4", "9789.0 41600", "9789 41600.5", "", " ", "9789",
                "9789 41600 0", "9789  41600", " 9789 41600", "9789 41600 ", "9789,41600", "9789\t41600",
                "+9789 41600", "9789 +1", "- 1", "-", "9789 -", "0x10 0", "1e3 0", "9789 86401", "9789 -86401",
                "0 999999999999", "9223372036854775807 0", "9223372036854775808 0", "-9223372036854775808 -1",
                "106751991167300 0", "4629629630 0", "\u{0661} 0", "x 0",
            ]
            for item in refused {
                #expect(throws: MusicAppError.self, "\(item)") { try MusicApp.dateOffset(item) }
                #expect(throws: MusicAppError.self, "\(item)") { try self.snapshotDate(item) }
            }
        }

        struct Marker: Error {}

        /// Selects between the readers with closures that send no Apple Event.
        static func select(
            bulk: @escaping () throws -> String, perTrack: @escaping () throws -> [MusicTrackInfo]
        ) throws -> [MusicTrackInfo] {
            try MusicApp.allTracksPreferringBulk(bulk: bulk, perTrack: perTrack)
        }

        static func text(_ sections: [String]) -> String { sections.joined(separator: MusicApp.sectionSeparator) }

        /// The varied samples with the one cloud status that the selection accepts from the bulk reader.
        static let unknownSamples: [Fields] = samples.map { sample in
            var row = sample
            row[11] = "unknown"
            return row
        }

        @Test func aConsistentBulkOutputWithOnlyUnknownStatusesIsReturnedWithoutThePerTrackReader() throws {
            #expect(MusicApp.bulkAcceptedCloudStatus == "unknown")
            #expect(Self.unknownSamples.count == 12)
            #expect(Set(Self.unknownSamples.map { $0[11] }) == ["unknown"])
            for rows in [Self.unknownSamples, [], [Self.unknownSamples[0]]] {
                let expected = try MusicApp.parse(Self.perTrack(rows))
                let actual = try Self.select(
                    bulk: { Self.text(Self.bulk(rows)) },
                    perTrack: {
                        Issue.record("the per-track reader was called")
                        throw Marker()
                    })
                #expect(actual == expected)
                #expect(actual.count == rows.count)
                #expect(actual.allSatisfy { $0.cloudStatus == "unknown" })
            }
        }

        @Test func anyOtherCloudStatusSelectsThePerTrackResultExactlyOnce() throws {
            let sentinel = try MusicApp.parse(Self.perTrack([Self.row("PER-TRACK", status: "unknown")]))
            for status in [
                "", "matched", "subscription", "uploaded", "kUnk", "Unknown", "unknown ", " unknown", "UNKNOWN",
            ] {
                for position in [0, 5, 11] {
                    var rows = Self.unknownSamples
                    rows[position][11] = status
                    var calls = 0
                    let actual = try Self.select(
                        bulk: { Self.text(Self.bulk(rows)) },
                        perTrack: {
                            calls += 1
                            return sentinel
                        })
                    #expect(actual == sentinel, "status \(status.debugDescription) at \(position)")
                    #expect(calls == 1, "status \(status.debugDescription) at \(position)")
                }
            }
            // A library of only one rejected status, and the mixed varied samples.
            for rows in [Self.samples, [Self.row("ID-1", status: "matched")]] {
                var calls = 0
                let actual = try Self.select(
                    bulk: { Self.text(Self.bulk(rows)) },
                    perTrack: {
                        calls += 1
                        return sentinel
                    })
                #expect(actual == sentinel && calls == 1)
            }
        }

        @Test func whenTheGuardRejectsTheBulkResultAPerTrackErrorPropagatesUnchanged() {
            let perTrackError = MusicAppError.scriptFailed("per-track")
            var rows = Self.unknownSamples
            rows[3][11] = "matched"
            #expect(throws: perTrackError) {
                try Self.select(bulk: { Self.text(Self.bulk(rows)) }, perTrack: { throw perTrackError })
            }
            #expect(throws: Marker.self) {
                try Self.select(bulk: { Self.text(Self.bulk(rows)) }, perTrack: { throw Marker() })
            }
        }

        @Test func everyFailureOfTheBulkReadYieldsThePerTrackResult() throws {
            // Valid bulk content with accepted statuses, so that only the structural failure selects the fallback.
            let rows = Array(Self.unknownSamples.prefix(3))
            let expected = try MusicApp.parse(Self.perTrack(rows))
            var shortList = Self.bulk(rows)
            shortList[2] = "Song\u{1E}Song"
            let outputs: [String] = [
                MusicApp.bulkUnavailable,
                Self.text(Array(Self.bulk(rows).dropLast())),
                Self.text(Self.bulk(rows) + ["extra"]),
                Self.text(shortList),
                Self.text(Self.bulk(rows, count: 4)),
                Self.text(Self.bulk(rows, lastIDs: ["ID-1", "ID-3", "ID-2"])),
                Self.text(Self.bulk(rows, lastIDs: ["ID-1", "ID-2"])),
                "",
                "garbage",
            ]
            for output in outputs {
                var calls = 0
                let actual = try Self.select(
                    bulk: { output },
                    perTrack: {
                        calls += 1
                        return expected
                    })
                #expect(actual == expected, "\(output.debugDescription)")
                #expect(calls == 1)
            }
            var calls = 0
            let thrown = try Self.select(
                bulk: { throw MusicAppError.scriptFailed("bulk") },
                perTrack: {
                    calls += 1
                    return expected
                })
            #expect(thrown == expected && calls == 1)
            let foreign = try Self.select(bulk: { throw Marker() }, perTrack: { expected })
            #expect(foreign == expected)
        }

        @Test func whenBothReadsFailThePerTrackErrorIsThrown() {
            let perTrackError = MusicAppError.scriptFailed("per-track")
            #expect(throws: perTrackError) {
                try Self.select(bulk: { throw MusicAppError.scriptFailed("bulk") }, perTrack: { throw perTrackError })
            }
            #expect(throws: perTrackError) {
                try Self.select(bulk: { MusicApp.bulkUnavailable }, perTrack: { throw perTrackError })
            }
            #expect(throws: perTrackError) {
                try Self.select(bulk: { "garbage" }, perTrack: { throw perTrackError })
            }
            #expect(throws: Marker.self) { try Self.select(bulk: { throw Marker() }, perTrack: { throw Marker() }) }
        }
    }
#endif
