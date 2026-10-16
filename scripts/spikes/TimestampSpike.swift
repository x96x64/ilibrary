// M1 spike S4: setting file and folder timestamps to release dates without creating paths.
// Exploratory code that informs LibraryMac. All paths are inside the work directory given as argument.
//
// Usage: timestamp-spike WORKDIR [OTHER-VOLUME-DIR]

import Foundation

let fileManager = FileManager.default
let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: timestamp-spike WORKDIR [OTHER-VOLUME-DIR]\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: arguments[1], isDirectory: true)
let otherVolume = arguments.count >= 3 ? URL(fileURLWithPath: arguments[2], isDirectory: true) : nil

let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime]

func localMidnight(_ text: String, _ zone: TimeZone) -> Date? {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}

func times(_ url: URL) -> String {
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return "missing" }
    let creation = (attributes[.creationDate] as? Date).map { iso.string(from: $0) } ?? "nil"
    let modification = (attributes[.modificationDate] as? Date).map { iso.string(from: $0) } ?? "nil"
    return "created \(creation), modified \(modification)"
}

func set(_ url: URL, _ date: Date) throws {
    // Refuse to act on a missing path; setAttributes itself does not create one, but this is explicit.
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
    }
    try fileManager.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
}

func report(_ label: String, _ body: () throws -> String) {
    do { print("== \(label): \(try body())") } catch { print("== \(label): error: \(error.localizedDescription)") }
}

// 1. Local midnight of release dates, including dates before 1970 and days whose midnight is skipped.
let zones = ["Asia/Tokyo", "America/New_York", "America/Sao_Paulo", "Europe/London"].compactMap(
    TimeZone.init(identifier:))
for date in ["1958-03-01", "1969-12-31", "1970-01-01", "1980-06-01", "2018-11-04", "2026-10-16"] {
    let values = zones.map { zone -> String in
        guard let midnight = localMidnight(date, zone) else { return "\(zone.identifier): nil" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: midnight)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = zone
        return "\(zone.identifier) \(formatter.string(from: midnight))\(hour == 0 ? "" : " (hour \(hour))")"
    }
    print("== local midnight \(date): \(values.joined(separator: "; "))")
}

try? fileManager.removeItem(at: work)
try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
let tokyo = TimeZone(identifier: "Asia/Tokyo")!
let release = localMidnight("1980-06-01", tokyo)!
let early = localMidnight("1958-03-01", tokyo)!

// 2. Files: setting both dates, a creation date later than the current one, and dates before 1970.
let file = work.appendingPathComponent("01 Track.m4a")
fileManager.createFile(atPath: file.path, contents: Data("synthetic".utf8))
report("new file") { times(file) }
report("set file to 1980-06-01") {
    try set(file, release)
    return times(file)
}
report("set file to a later date (creation increases)") {
    try set(file, localMidnight("1990-01-01", tokyo)!)
    return times(file)
}
report("set file to 1958-03-01") {
    try set(file, early)
    return times(file)
}
report("creation later than modification") {
    try fileManager.setAttributes([.creationDate: release], ofItemAtPath: file.path)
    try fileManager.setAttributes([.modificationDate: early], ofItemAtPath: file.path)
    return times(file)
}

// 3. Missing paths are never created.
let missingFolder = work.appendingPathComponent("Missing Artist", isDirectory: true)
report("missing folder") {
    do { try set(missingFolder, release) } catch {
        return
            "refused (\(error.localizedDescription)); exists afterwards: \(fileManager.fileExists(atPath: missingFolder.path))"
    }
    return "set (unexpected)"
}
report("FileManager.setAttributes on a missing path") {
    do {
        try fileManager.setAttributes([.modificationDate: release], ofItemAtPath: missingFolder.path)
    } catch {
        return
            "threw \((error as NSError).code); exists afterwards: \(fileManager.fileExists(atPath: missingFolder.path))"
    }
    return "succeeded; exists afterwards: \(fileManager.fileExists(atPath: missingFolder.path))"
}

// 4. Symbolic links: does setting the link's dates change the target?
let target = work.appendingPathComponent("target.m4a")
let link = work.appendingPathComponent("link.m4a")
fileManager.createFile(atPath: target.path, contents: Data())
try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
report("set dates through a symbolic link") {
    try fileManager.setAttributes([.creationDate: release, .modificationDate: release], ofItemAtPath: link.path)
    var linkStat = stat()
    lstat(link.path, &linkStat)
    let linkModified = iso.string(from: Date(timeIntervalSince1970: TimeInterval(linkStat.st_mtimespec.tv_sec)))
    return "target \(times(target)); link itself modified \(linkModified)"
}

// 5. Folders: entries added, renamed, or removed afterwards change the folder's modification date.
let album = work.appendingPathComponent("Example Album", isDirectory: true)
try fileManager.createDirectory(at: album, withIntermediateDirectories: false)
try set(album, release)
report("folder after setting") { times(album) }
fileManager.createFile(atPath: album.appendingPathComponent("01 New.m4a").path, contents: Data())
report("folder after adding an entry") { times(album) }
try set(album, release)
try fileManager.moveItem(
    at: album.appendingPathComponent("01 New.m4a"), to: album.appendingPathComponent("01 Renamed.m4a"))
report("folder after renaming an entry") { times(album) }
try set(album, release)
let inside = album.appendingPathComponent("01 Renamed.m4a")
try "x".write(to: inside, atomically: false, encoding: .utf8)
report("folder after writing an existing entry in place") { times(album) }
try set(album, release)
try "y".write(to: inside, atomically: true, encoding: .utf8)
report("folder after an atomic write of an entry") { times(album) }

// 6. Replacing a file (as a tag rewrite through a temporary file does) and its effect on dates.
let original = work.appendingPathComponent("02 Track.m4a")
fileManager.createFile(atPath: original.path, contents: Data("original".utf8))
try set(original, release)
let replacement = work.appendingPathComponent(".02 Track.m4a.partial")
fileManager.createFile(atPath: replacement.path, contents: Data("rewritten".utf8))
report("remove and move a rewritten file") {
    try fileManager.removeItem(at: original)
    try fileManager.moveItem(at: replacement, to: original)
    return times(original)
}
try set(original, release)
fileManager.createFile(atPath: replacement.path, contents: Data("rewritten again".utf8))
report("FileManager.replaceItemAt") {
    _ = try fileManager.replaceItemAt(original, withItemAt: replacement)
    return times(original)
}
try set(original, release)
report("write in place through FileHandle") {
    let handle = try FileHandle(forWritingTo: original)
    try handle.seek(toOffset: 0)
    try handle.write(contentsOf: Data("in place".utf8))
    try handle.close()
    return times(original)
}

// 7. Moving within a volume and across volumes.
try set(original, release)
let renamed = work.appendingPathComponent("02 Moved.m4a")
report("move within the volume") {
    try fileManager.moveItem(at: original, to: renamed)
    return times(renamed)
}
if let otherVolume {
    try? fileManager.removeItem(at: otherVolume.appendingPathComponent("02 Moved.m4a"))
    let destination = otherVolume.appendingPathComponent("02 Moved.m4a")
    report("move across volumes") {
        try fileManager.moveItem(at: renamed, to: destination)
        return "\(times(destination)); source exists afterwards: \(fileManager.fileExists(atPath: renamed.path))"
    }
} else {
    print("== move across volumes: unavailable (no second volume given)")
}
