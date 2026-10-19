// Bulk reading of the Music library. Built only on macOS; on other platforms it is empty.
//
// Equivalence status: the bulk reader is designed to return, field for field, what the per-track reader
// (`describeHandler`, `MusicApp.parse`) returns. Live equivalence with the per-track reader has NOT been
// measured. It requires the maintainer's verification in a separate macOS user. The speed of the bulk read
// (0.482 s against 40.092 s for 300 tracks) was measured in the M10 qualification with one bulk reference per
// property; the behaviour of every property listed below under bulk reads, and the text produced by
// coercing a bulk-read cloud status outside the `tell` block, are unmeasured.
#if os(macOS)
    import Foundation

    /// A library snapshot for the rebuild inventory: the file tracks, the counts that reveal non-file
    /// tracks, and the date added of each file track.
    public struct MusicLibrarySnapshot: Equatable, Sendable {
        /// The file tracks, in the order of `every file track of library playlist 1`.
        public var tracks: [MusicTrackInfo]
        /// The count of `every track of library playlist 1`.
        public var trackCount: Int
        /// The count of `every file track of library playlist 1`. A value below `trackCount` means that the
        /// library holds tracks that are not file tracks.
        public var fileTrackCount: Int
        /// Whole seconds since 1970-01-01T00:00:00Z at which each file track was added, by persistent ID.
        public var dateAddedSeconds: [String: Int]

        public init(
            tracks: [MusicTrackInfo], trackCount: Int, fileTrackCount: Int, dateAddedSeconds: [String: Int]
        ) {
            self.tracks = tracks
            self.trackCount = trackCount
            self.fileTrackCount = fileTrackCount
            self.dateAddedSeconds = dateAddedSeconds
        }
    }

    extension MusicApp {
        static let sectionSeparator = "\u{1D}"
        /// Returned by the script when a bulk read of a property other than location and cloud status fails.
        static let bulkUnavailable = "bulk-unavailable"
        /// The sections of the bulk output: the file-track count, the persistent IDs, the fifteen other
        /// properties in the field order of the per-track record, and the persistent IDs read last.
        static let bulkSectionCount = 18

        /// Reads every file track with a fixed number of Apple Events. Intended to replace `allTracks()`.
        /// When a bulk read of a property other than location and cloud status raises an error, the result
        /// is that of `allTracks()`. Live equivalence with the per-track reader has not been measured.
        public static func allTracksBulk() throws -> [MusicTrackInfo] {
            let text = try run(bulkScript(includeDates: false))
            if text == bulkUnavailable { return try allTracks() }
            return try assembleBulk(splitSections(text, expected: bulkSectionCount))
        }

        /// Reads the file tracks, both track counts, and the date added of each file track. Throws when a
        /// bulk read other than location and cloud status fails. Live equivalence with the per-track reader
        /// has not been measured.
        public static func librarySnapshot() throws -> MusicLibrarySnapshot {
            let text = try run(bulkScript(includeDates: true))
            if text == bulkUnavailable {
                throw MusicAppError.unexpectedResult("a bulk read of the library failed")
            }
            return try parseSnapshot(text, timeZone: .autoupdatingCurrent)
        }

        static func splitSections(_ text: String, expected: Int) throws -> [String] {
            let sections = text.components(separatedBy: sectionSeparator)
            guard sections.count == expected else {
                throw MusicAppError.unexpectedResult("the bulk output has \(sections.count) sections, not \(expected)")
            }
            return sections
        }

        /// Splits one section into `count` items. An empty library has empty sections.
        static func items(_ section: String, count: Int) throws -> [String] {
            if count == 0 {
                guard section.isEmpty else {
                    throw MusicAppError.unexpectedResult("a property list is not empty for an empty library")
                }
                return []
            }
            let items = section.components(separatedBy: recordSeparator)
            guard items.count == count else {
                throw MusicAppError.unexpectedResult("a property list has \(items.count) items, not \(count)")
            }
            return items
        }

        /// Assembles records from the sections of the bulk output by rendering the per-track record format
        /// and applying `parse`, so that its semantics (`Int(...) ?? 0`, "true" for compilation, an empty
        /// location as nil) are those of the per-track reader. Pure; sends no Apple Event.
        static func assembleBulk(_ sections: [String]) throws -> [MusicTrackInfo] {
            guard sections.count == bulkSectionCount else {
                throw MusicAppError.unexpectedResult("the bulk output has \(sections.count) sections")
            }
            guard let count = Int(sections[0]), count >= 0 else {
                throw MusicAppError.unexpectedResult("the track count is not a number")
            }
            let lists = try sections[1...17].map { try items($0, count: count) }
            guard lists[0] == lists[16] else {
                throw MusicAppError.unexpectedResult("the library changed while it was read")
            }
            let records = (0..<count).map { index in
                lists[0..<16].map { $0[index] }.joined(separator: fieldSeparator)
            }
            return try parse(records.map { $0 + recordSeparator }.joined())
        }

        /// Parses the snapshot output: the bulk sections, the count of all tracks, and the date offsets.
        static func parseSnapshot(_ text: String, timeZone: TimeZone) throws -> MusicLibrarySnapshot {
            let sections = try splitSections(text, expected: bulkSectionCount + 2)
            let tracks = try assembleBulk(Array(sections[0..<bulkSectionCount]))
            guard let total = Int(sections[bulkSectionCount]), total >= tracks.count else {
                throw MusicAppError.unexpectedResult("the track count is inconsistent with the file-track count")
            }
            let offsets = try items(sections[bulkSectionCount + 1], count: tracks.count)
            var dates: [String: Int] = [:]
            for (track, offset) in zip(tracks, offsets) {
                guard let seconds = Int(offset) else {
                    throw MusicAppError.unexpectedResult("a date added is not a number")
                }
                guard
                    dates.updateValue(
                        unixSeconds(offsetFromYear2000: seconds, timeZone: timeZone), forKey: track.persistentID) == nil
                else { throw MusicAppError.unexpectedResult("a persistent ID occurs twice") }
            }
            return MusicLibrarySnapshot(
                tracks: tracks, trackCount: total, fileTrackCount: tracks.count, dateAddedSeconds: dates)
        }

        /// Converts a date added to whole seconds since 1970. The script, like the probe's `stamp` handler,
        /// subtracts the local time 2000-01-01 00:00:00 from the date, which yields elapsed seconds from that
        /// instant. The instant is 946684800 s after 1970 in UTC, less the zone's offset at that time.
        static func unixSeconds(offsetFromYear2000 offset: Int, timeZone: TimeZone) -> Int {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let components = DateComponents(year: 2000, month: 1, day: 1, hour: 0, minute: 0, second: 0)
            let base = calendar.date(from: components)?.timeIntervalSince1970 ?? 946_684_800
            return Int(base.rounded()) + offset
        }

        /// The script of the bulk reader. The `tell` block holds only bulk references, with a per-track
        /// fallback for location and cloud status, which the per-track handler also reads inside `try`.
        /// Conversions run in local loops after the `tell` block and send no Apple Event.
        static func bulkScript(includeDates: Bool) -> String {
            let dateRead = includeDates ? "set dateList to date added of every file track of library playlist 1" : ""
            let totalRead = includeDates ? "set totalCount to count of (every track of library playlist 1)" : ""
            let dateInit = includeDates ? "set dateList to {}\nset totalCount to 0" : ""
            let dateLength = includeDates ? " or (count of dateList) is not fileCount" : ""
            let dateConvert =
                includeDates
                ? """
                set base to current date
                set day of base to 1
                set year of base to 2000
                set month of base to January
                set time of base to 0
                set dateText to {}
                repeat with v in dateList
                    set end of dateText to (((contents of v) - base) as integer) as text
                end repeat
                """ : ""
            let tail = includeDates ? ", (totalCount as text), my joinText(dateText, rs)" : ""
            return """
                on joinText(theList, theDelimiter)
                    set savedDelimiters to AppleScript's text item delimiters
                    set AppleScript's text item delimiters to theDelimiter
                    try
                        set joined to theList as text
                    on error errText number errNumber
                        set AppleScript's text item delimiters to savedDelimiters
                        error errText number errNumber
                    end try
                    set AppleScript's text item delimiters to savedDelimiters
                    return joined
                end joinText
                on textList(theList)
                    set converted to {}
                    repeat with v in theList
                        set end of converted to (contents of v) as text
                    end repeat
                    return converted
                end textList
                on statusTextList(theList)
                    set converted to {}
                    -- The terminology of Music stays in scope for the coercion; no event is sent.
                    using terms from application "Music"
                        repeat with v in theList
                            try
                                set end of converted to (contents of v) as text
                            on error
                                set end of converted to ""
                            end try
                        end repeat
                    end using terms from
                    return converted
                end statusTextList
                on pathList(theList)
                    set converted to {}
                    repeat with v in theList
                        try
                            set end of converted to POSIX path of (contents of v)
                        on error
                            set end of converted to ""
                        end try
                    end repeat
                    return converted
                end pathList
                set rs to character id 30
                set gs to character id 29
                set bulkFailed to false
                set firstIDs to {}
                set lastIDs to {}
                set nameList to {}
                set albumList to {}
                set artistList to {}
                set albumArtistList to {}
                set composerList to {}
                set genreList to {}
                set yearList to {}
                set trackNumberList to {}
                set discNumberList to {}
                set locationList to {}
                set statusList to {}
                set commentList to {}
                set trackCountList to {}
                set discCountList to {}
                set compilationList to {}
                \(dateInit)
                with timeout of 300 seconds
                    tell application "Music"
                        set fileCount to count of (every file track of library playlist 1)
                        \(totalRead)
                        try
                            set firstIDs to persistent ID of every file track of library playlist 1
                            set nameList to name of every file track of library playlist 1
                            set albumList to album of every file track of library playlist 1
                            set artistList to artist of every file track of library playlist 1
                            set albumArtistList to album artist of every file track of library playlist 1
                            set composerList to composer of every file track of library playlist 1
                            set genreList to genre of every file track of library playlist 1
                            set yearList to year of every file track of library playlist 1
                            set trackNumberList to track number of every file track of library playlist 1
                            set discNumberList to disc number of every file track of library playlist 1
                            set commentList to comment of every file track of library playlist 1
                            set trackCountList to track count of every file track of library playlist 1
                            set discCountList to disc count of every file track of library playlist 1
                            set compilationList to compilation of every file track of library playlist 1
                            \(dateRead)
                        on error
                            set bulkFailed to true
                        end try
                        if not bulkFailed then
                            try
                                set locationList to location of every file track of library playlist 1
                            on error
                                -- Per-track fallback: the per-track handler reads location inside try.
                                set locationList to {}
                                repeat with i from 1 to fileCount
                                    try
                                        set end of locationList to (get location of file track i of library playlist 1)
                                    on error
                                        set end of locationList to missing value
                                    end try
                                end repeat
                            end try
                            try
                                set statusList to cloud status of every file track of library playlist 1
                            on error
                                -- Per-track fallback: the per-track handler reads cloud status inside try.
                                set statusList to {}
                                repeat with i from 1 to fileCount
                                    try
                                        set end of statusList to (get cloud status of file track i of library playlist 1)
                                    on error
                                        set end of statusList to missing value
                                    end try
                                end repeat
                            end try
                            set lastIDs to persistent ID of every file track of library playlist 1
                        end if
                    end tell
                end timeout
                if bulkFailed then return "\(bulkUnavailable)"
                if firstIDs is not lastIDs then error "Library changed during read"
                if (count of firstIDs) is not fileCount or (count of nameList) is not fileCount or (count of albumList) is not fileCount or (count of artistList) is not fileCount or (count of albumArtistList) is not fileCount or (count of composerList) is not fileCount or (count of genreList) is not fileCount or (count of yearList) is not fileCount or (count of trackNumberList) is not fileCount or (count of discNumberList) is not fileCount or (count of locationList) is not fileCount or (count of statusList) is not fileCount or (count of commentList) is not fileCount or (count of trackCountList) is not fileCount or (count of discCountList) is not fileCount or (count of compilationList) is not fileCount\(dateLength) then error "Property lists differ in length"
                set yearText to my textList(yearList)
                set trackNumberText to my textList(trackNumberList)
                set discNumberText to my textList(discNumberList)
                set trackCountText to my textList(trackCountList)
                set discCountText to my textList(discCountList)
                set compilationText to my textList(compilationList)
                set pathText to my pathList(locationList)
                set statusText to my statusTextList(statusList)
                \(dateConvert)
                return my joinText({(fileCount as text), my joinText(firstIDs, rs), my joinText(nameList, rs), ¬
                    my joinText(albumList, rs), my joinText(artistList, rs), my joinText(albumArtistList, rs), ¬
                    my joinText(composerList, rs), my joinText(genreList, rs), my joinText(yearText, rs), ¬
                    my joinText(trackNumberText, rs), my joinText(discNumberText, rs), my joinText(pathText, rs), ¬
                    my joinText(statusText, rs), my joinText(commentList, rs), my joinText(trackCountText, rs), ¬
                    my joinText(discCountText, rs), my joinText(compilationText, rs), my joinText(lastIDs, rs)\(tail)}, gs)
                """
        }
    }
#endif
