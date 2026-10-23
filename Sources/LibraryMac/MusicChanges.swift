// Changes to the Music library and app, and the addition dates they depend on. Built only on macOS.
//
// Removal uses the form measured with Music 1.7 on macOS 27.0.1: the track is found again by persistent ID among
// the file tracks, exactly one must exist, and its name, album, and artist must equal the recorded values before
// `delete` is sent. Dates use the conversion of the bulk reader.
#if os(macOS)
    import Foundation

    extension MusicApp {
        /// Deletes the one file track with a persistent ID after comparing its name, album, and artist, with case
        /// considered, with the given values. Throws, and deletes nothing, when no track, several tracks, or a
        /// different track is found.
        public static func remove(persistentID: String, name: String, album: String, artist: String) throws {
            let result = try run(
                """
                with timeout of 120 seconds
                    tell application "Music"
                        set matches to (every file track of library playlist 1 whose persistent ID is \(literal(persistentID)))
                        if (count of matches) is not 1 then return "count " & ((count of matches) as text)
                        set t to item 1 of matches
                        considering case
                            if (name of t) is not \(literal(name)) or (album of t) is not \(literal(album)) or ¬
                                (artist of t) is not \(literal(artist)) then return "differs"
                        end considering
                        delete t
                    end tell
                end timeout
                return "removed"
                """)
            switch result {
            case "removed": return
            case "differs":
                throw MusicAppError.unexpectedResult(
                    "the track \(persistentID) differs from the recorded name, album, or artist; it was not removed")
            default:
                throw MusicAppError.unexpectedResult(
                    "\(result.replacingOccurrences(of: "count ", with: "")) file tracks have the persistent ID "
                        + "\(persistentID); nothing was removed")
            }
        }

        /// The date added of each file track with one of the persistent IDs, in whole seconds since 1970. Reads only.
        public static func datesAdded(persistentIDs: [String]) throws -> [String: Int] {
            guard !persistentIDs.isEmpty else { return [:] }
            let list = persistentIDs.map(literal).joined(separator: ", ")
            let text = try run(
                """
                set base to current date
                set day of base to 1
                set year of base to 2000
                set month of base to January
                set time of base to 0
                set output to {}
                with timeout of 120 seconds
                    tell application "Music"
                        repeat with theID in {\(list)}
                            set matches to (every file track of library playlist 1 whose persistent ID is (contents of theID))
                            if (count of matches) is not 1 then error "a persistent ID does not name one file track"
                            set x to (date added of item 1 of matches) - base
                            set d to x div 86400
                            set r to (x - d * 86400) as integer
                            set end of output to (d as text) & " " & (r as text)
                        end repeat
                    end tell
                end timeout
                set savedDelimiters to AppleScript's text item delimiters
                set AppleScript's text item delimiters to character id 30
                set joined to output as text
                set AppleScript's text item delimiters to savedDelimiters
                return joined
                """)
            let items = text.components(separatedBy: recordSeparator)
            guard items.count == persistentIDs.count else {
                throw MusicAppError.unexpectedResult(
                    "\(items.count) dates were returned for \(persistentIDs.count) tracks")
            }
            var dates: [String: Int] = [:]
            for (id, item) in zip(persistentIDs, items) {
                dates[id] = unixSeconds(offsetFromYear2000: try dateOffset(item), timeZone: .autoupdatingCurrent)
            }
            return dates
        }

        /// Asks Music to quit. Whether it has quit is read separately.
        public static func quit() throws {
            _ = try run("tell application \"Music\" to quit")
        }
    }
#endif
