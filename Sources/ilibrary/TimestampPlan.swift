import CatalogCore
import Foundation

/// A path whose creation and modification dates are to be set.
struct DatedPath: Equatable {
    enum Kind: String {
        case file
        case albumFolder = "album folder"
        case artistFolder = "artist folder"
    }

    var url: URL
    var kind: Kind
    var releaseDate: ReleaseDate
    var date: Date
    /// False where the time zone skips midnight and the first instant of the day is used instead.
    var isMidnight: Bool
}

struct TimestampPlan {
    /// Files first, then album folders, then artist folders, so that later operations do not disturb earlier ones.
    var targets: [DatedPath] = []
    /// Paths left unchanged, with the reason.
    var notes: [String] = []
}

enum TimestampPlanner {
    /// Plans dates at local midnight of each release date. An album folder is dated when it holds the files of
    /// exactly one album and lies inside a given directory; an artist folder is dated only when it is named after
    /// the album artist, lies inside a given directory, and the catalog gives the artist a `folderDate`. Folders
    /// outside the given directories are never changed.
    static func plan(
        files: [(url: URL, track: ResolvedTrack)], catalog: Catalog, roots: [URL], timeZone: TimeZone
    ) -> TimestampPlan {
        var plan = TimestampPlan()
        func dated(_ url: URL, _ kind: DatedPath.Kind, _ date: ReleaseDate) -> DatedPath {
            let start = date.localStart(in: timeZone)
            return DatedPath(url: url, kind: kind, releaseDate: date, date: start.date, isMidnight: start.isMidnight)
        }
        func inside(_ url: URL) -> Bool { roots.contains { isWithin(url, $0) } }

        for (url, track) in files.sorted(by: { $0.url.path < $1.url.path }) {
            if let date = track.releaseDate {
                plan.targets.append(dated(url, .file, date))
            } else {
                plan.notes.append("\(url.path) left unchanged: no release date")
            }
        }

        var folders: [String: Set<Int>] = [:]
        for (url, track) in files {
            folders[url.deletingLastPathComponent().path, default: []].insert(track.reference.album)
        }
        var albumFolders: [(album: Int, url: URL)] = []
        for album in Set(files.map(\.track.reference.album)).sorted() {
            let parents = Set(
                files.filter { $0.track.reference.album == album }.map { $0.url.deletingLastPathComponent().path })
            let name = catalog.albums[album].album
            guard parents.count == 1, let path = parents.first else {
                plan.notes.append(
                    "the folders of \"\(name)\" left unchanged: its files lie in \(parents.count) folders")
                continue
            }
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            guard inside(folder) else {
                plan.notes.append("\(path) left unchanged: it is outside the given directories")
                continue
            }
            guard folders[path]?.count == 1 else {
                plan.notes.append("\(path) left unchanged: it holds files of several albums")
                continue
            }
            guard let date = catalog.albums[album].releaseDate.flatMap({ ReleaseDate($0) }) else {
                plan.notes.append("\(path) left unchanged: \"\(name)\" has no release date")
                continue
            }
            plan.targets.append(dated(folder, .albumFolder, date))
            albumFolders.append((album, folder))
        }

        var artistFolders: [String: Set<String>] = [:]
        for (album, folder) in albumFolders {
            let entry = catalog.albums[album]
            artistFolders[folder.deletingLastPathComponent().path, default: []].insert(
                entry.albumArtist ?? entry.artist ?? "")
        }
        for (path, artists) in artistFolders.sorted(by: { $0.key < $1.key }) {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            guard artists.count == 1, let artist = artists.first, !artist.isEmpty,
                folder.lastPathComponent == Naming.component(artist)
            else { continue }
            guard inside(folder) else {
                plan.notes.append("\(path) left unchanged: it is outside the given directories")
                continue
            }
            guard let text = catalog.artists?[artist]?.folderDate, let date = ReleaseDate(text) else {
                plan.notes.append("\(path) left unchanged: the catalog gives \"\(artist)\" no folderDate")
                continue
            }
            plan.targets.append(dated(folder, .artistFolder, date))
        }
        for target in plan.targets where !target.isMidnight {
            plan.notes.append(
                "\(target.url.path): midnight of \(target.releaseDate) does not exist in \(timeZone.identifier); the first instant of the day is used"
            )
        }
        return plan
    }

    /// Prints the planned dates, with paths relative to `root` when it is given, and the paths left unchanged.
    static func printPlan(_ plan: TimestampPlan, timeZone: TimeZone, root: URL?, console: Console) {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        console.print("Dates: \(plan.targets.count) paths")
        for target in plan.targets {
            let path = root.map { relativePath(target.url, from: $0) } ?? target.url.path
            console.print("  \(target.kind.rawValue) \(path): \(formatter.string(from: target.date))")
        }
        for note in plan.notes { console.print("  note: \(note)") }
    }

    /// A shell script that sets the same dates with SetFile and touch. Each path is checked first; a missing path
    /// or a symbolic link is reported and skipped, so that the script never creates a path.
    static func script(_ plan: TimestampPlan, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var lines = [
            "#!/bin/sh",
            "# Generated by ilibrary \(version). Sets the creation and modification dates of files, then folders.",
            "# A missing path or a symbolic link is reported and skipped; no path is created.",
            "set -u",
            "TZ=\(quoted(timeZone.identifier))",
            "export TZ",
            "status=0",
            "set_dates() {",
            "    if [ -L \"$1\" ] || [ ! -e \"$1\" ]; then",
            "        echo \"skipped (missing or a symbolic link): $1\" >&2",
            "        status=1",
            "        return",
            "    fi",
            "    SetFile -d \"$2\" \"$1\" && touch -c -m -t \"$3\" \"$1\" || status=1",
            "}",
        ]
        for target in plan.targets {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: target.date)
            let setFile = String(
                format: "%02d/%02d/%04d %02d:%02d:%02d", c.month!, c.day!, c.year!, c.hour!, c.minute!, c.second!)
            let touch = String(
                format: "%04d%02d%02d%02d%02d.%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
            lines.append("set_dates \(quoted(target.url.path)) \(quoted(setFile)) \(quoted(touch))")
        }
        lines.append("exit $status")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Applies the plan in order and confirms each date. Stops at the first failure and reports it.
    static func execute(_ plan: TimestampPlan, environment: Environment) throws -> Int {
        guard let setDates = environment.setDates else {
            throw CommandError.failure("setting creation dates is supported only on macOS")
        }
        // Every path is checked before any date is set, so that a missing path or a link changes nothing.
        for target in plan.targets {
            switch pathKind(target.url) {
            case .missing:
                throw CommandError.failure("\(target.url.path) does not exist; no date was set and nothing was created")
            case .symbolicLink: throw CommandError.failure("\(target.url.path) is a symbolic link; no date was set")
            default: break
            }
        }
        var done = 0
        for target in plan.targets {
            do {
                try setDates(target.url, target.date)
            } catch {
                throw CommandError.failure(
                    "\(error) (\(done) of \(plan.targets.count) paths were dated before this failure)")
            }
            done += 1
        }
        return done
    }
}
