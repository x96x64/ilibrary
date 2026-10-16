// The Music app through Apple Events. Built only on macOS; on other platforms it is empty.
//
// The forms used here follow the live measurements of Music 1.7 in a separate macOS user (Music Behavior
// report): the media-folder preference, `add` of a file list, the track description handler, and lookup by
// album and by persistent ID. Reading the composer, genre, year, and track and disc numbers was not part of
// those measurements. Track properties are never set, because Music then moves and renames files.
#if os(macOS)
    import Foundation

    /// A track of the Music library, read in one call.
    public struct MusicTrackInfo: Equatable, Sendable {
        public var persistentID: String
        public var name: String
        public var album: String
        public var artist: String
        public var albumArtist: String
        public var composer: String
        public var genre: String
        public var year: Int
        public var trackNumber: Int
        public var discNumber: Int
        public var comment: String
        public var trackCount: Int
        public var discCount: Int
        public var compilation: Bool
        /// The POSIX path of the track's file, when Music knows one.
        public var location: String?
        public var cloudStatus: String
    }

    public enum MusicAppError: Error, Equatable, Sendable, CustomStringConvertible {
        case scriptFailed(String)
        case unexpectedResult(String)

        public var description: String {
            switch self {
            case .scriptFailed(let message): "Music did not complete the request: \(message)"
            case .unexpectedResult(let message): "Music returned an unexpected result: \(message)"
            }
        }
    }

    public enum MusicApp {
        static let fieldSeparator = "\u{1F}"
        static let recordSeparator = "\u{1E}"

        /// The media folder that Music's preferences name, read without asking Music.
        public static func mediaFolder() -> URL? {
            guard let text = UserDefaults(suiteName: "com.apple.Music")?.string(forKey: "media-folder-url"),
                let url = URL(string: text), url.isFileURL
            else { return nil }
            return url
        }

        /// Quotes text as an AppleScript string literal.
        static func literal(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }

        static let describeHandler = """
            on describeTracks(theTracks)
                set fieldSeparator to character id 31
                set recordSeparator to character id 30
                set output to ""
                tell application "Music"
                    repeat with t in theTracks
                        set thePath to ""
                        try
                            set thePath to POSIX path of (get location of t)
                        end try
                        set theStatus to ""
                        try
                            set theStatus to (cloud status of t) as text
                        end try
                        set output to output & (persistent ID of t) & fieldSeparator & (name of t) & fieldSeparator & ¬
                            (album of t) & fieldSeparator & (artist of t) & fieldSeparator & (album artist of t) & ¬
                            fieldSeparator & (composer of t) & fieldSeparator & (genre of t) & fieldSeparator & ¬
                            ((year of t) as text) & fieldSeparator & ((track number of t) as text) & fieldSeparator & ¬
                            ((disc number of t) as text) & fieldSeparator & thePath & fieldSeparator & theStatus & ¬
                            fieldSeparator & (comment of t) & fieldSeparator & ((track count of t) as text) & ¬
                            fieldSeparator & ((disc count of t) as text) & fieldSeparator & ((compilation of t) as text) & recordSeparator
                    end repeat
                end tell
                return output
            end describeTracks
            """

        static func run(_ source: String) throws -> String {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                throw MusicAppError.scriptFailed("the script could not be compiled")
            }
            let result = script.executeAndReturnError(&error)
            if let error {
                throw MusicAppError.scriptFailed(error[NSAppleScript.errorMessage] as? String ?? "\(error)")
            }
            return result.stringValue ?? ""
        }

        static func parse(_ text: String) throws -> [MusicTrackInfo] {
            try text.components(separatedBy: recordSeparator).filter { !$0.isEmpty }.map { record in
                let fields = record.components(separatedBy: fieldSeparator)
                guard fields.count == 16 else {
                    throw MusicAppError.unexpectedResult("a track record has \(fields.count) fields")
                }
                return MusicTrackInfo(
                    persistentID: fields[0], name: fields[1], album: fields[2], artist: fields[3],
                    albumArtist: fields[4],
                    composer: fields[5], genre: fields[6], year: Int(fields[7]) ?? 0, trackNumber: Int(fields[8]) ?? 0,
                    discNumber: Int(fields[9]) ?? 0, comment: fields[12], trackCount: Int(fields[13]) ?? 0,
                    discCount: Int(fields[14]) ?? 0, compilation: fields[15] == "true",
                    location: fields[10].isEmpty ? nil : fields[10],
                    cloudStatus: fields[11])
            }
        }

        /// A read-only snapshot of file tracks, used to compare by location when cached tags are stale.
        public static func allTracks() throws -> [MusicTrackInfo] {
            try parse(
                run(
                    describeHandler + """

                        with timeout of 300 seconds
                            tell application "Music" to set theTracks to every file track of library playlist 1
                            return my describeTracks(theTracks)
                        end timeout
                        """))
        }

        /// The file tracks of the library whose album has the given name. Reads only.
        public static func tracks(album: String) throws -> [MusicTrackInfo] {
            try parse(
                run(
                    describeHandler + """

                        with timeout of 300 seconds
                            tell application "Music"
                                set theTracks to (every file track of library playlist 1 whose album is \(literal(album)))
                            end tell
                        end timeout
                        return my describeTracks(theTracks)
                        """))
        }

        /// The track with a persistent ID, or nil. Reads only.
        public static func track(persistentID: String) throws -> MusicTrackInfo? {
            try parse(
                run(
                    describeHandler + """

                        with timeout of 120 seconds
                            tell application "Music"
                                set theTracks to (every track of library playlist 1 whose persistent ID is \(literal(persistentID)))
                            end tell
                        end timeout
                        return my describeTracks(theTracks)
                        """)
            ).first
        }

        /// Adds files to the library in one call and describes the tracks that Music returns. A file that the
        /// library already holds is returned as its existing track, without a duplicate (measured).
        public static func add(_ files: [URL]) throws -> [MusicTrackInfo] {
            let list = files.map { "POSIX file \(literal($0.path))" }.joined(separator: ", ")
            return try parse(
                run(
                    describeHandler + """

                        set theFiles to {\(list)}
                        with timeout of 600 seconds
                            tell application "Music" to set added to (add theFiles to library playlist 1)
                        end timeout
                        if added is missing value then return ""
                        if class of added is not list then set added to {added}
                        return my describeTracks(added)
                        """))
        }
    }
#endif
