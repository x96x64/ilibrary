import Foundation
import MP4Core
import Testing

@testable import ilibrary

func musicStatus(version: String? = "1.7", running: Bool = true, permission: String = "permitted") -> MusicAppStatus {
    MusicAppStatus(version: { version }, isRunning: { running }, permission: { permission })
}

@Suite struct DoctorTests {
    func environment(media: URL?, permission: String = "permitted", version: String? = "1.7") -> Environment {
        var environment = Environment.testing
        environment.music = FakeMusic(media: media)
        environment.musicStatus = musicStatus(version: version, permission: permission)
        environment.availableCapacity = { _ in 50_000_000_000 }
        return environment
    }

    @Test func aHealthyEnvironmentReportsNoProblem() throws {
        let media = FileManager.default.temporaryDirectory.appendingPathComponent("doctor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: media) }
        let run = Run(["doctor"], environment: environment(media: media))
        #expect(run.status == 0, "\(run.text)")
        #expect(run.text.contains("ok      ilibrary: \(version)"))
        #expect(run.text.contains("ok      Music: version 1.7"))
        #expect(run.text.contains("ok      Automation: this terminal may control Music"))
        #expect(run.text.contains("50.0 GB available"))
        #expect(run.text.contains("No problems found."))
    }

    @Test func problemsComeWithRemedies() throws {
        let missing = Run(["doctor"], environment: environment(media: nil, permission: "denied"))
        #expect(missing.status == 1)
        #expect(missing.text.contains("problem media folder: Music's preferences name no media folder"))
        #expect(missing.text.contains("Open Music once"))
        #expect(missing.text.contains("problem Automation: this terminal may not control Music"))
        #expect(missing.text.contains("Privacy & Security, Automation"))
        #expect(missing.text.contains("2 problem(s) found."))
        let gone = Run(["doctor"], environment: environment(media: URL(fileURLWithPath: "/nonexistent-ilibrary-media")))
        #expect(gone.text.contains("does not exist"))
    }

    @Test func undeterminablePermissionsAreNotesNotProblems() throws {
        let media = FileManager.default.temporaryDirectory
        let notRunning = Run(["doctor"], environment: environment(media: media, permission: "Music not running"))
        #expect(notRunning.status == 0)
        #expect(notRunning.text.contains("doctor does not launch it"))
        let undecided = Run(["doctor"], environment: environment(media: media, permission: "not determined"))
        #expect(undecided.status == 0)
        #expect(undecided.text.contains("macOS asks the first time"))
        var unavailable = Environment.testing
        unavailable.musicStatus = nil
        #expect(Run(["doctor"], environment: unavailable).text.contains("note    Music: unavailable on this platform"))
    }
}

@Suite struct CheckTests {
    var noDates: Environment {
        var environment = Environment.testing
        environment.readDates = nil
        return environment
    }

    @Test func aConsistentLibraryHasNoProblems() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let run = Run(["check", library.root.path], environment: noDates)
        #expect(run.status == 0, "\(run.text)")
        #expect(run.text.contains("Checked 9 files"))
        #expect(run.text.contains("No problems found."))
    }

    @Test func damagedFilesAreDetected() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let files = try library.m4aFiles()
        // A second file claims disc 1 track 1 of its album, and another loses its title.
        var duplicate = try MP4File(contentsOf: files[1])
        try duplicate.setMetadata(.discNumber, .pair(number: 1, total: 2))
        try duplicate.setMetadata(.trackNumber, .pair(number: 1, total: 2))
        try MP4Writer.write(duplicate, to: files[1])
        var untitled = try MP4File(contentsOf: files[5])
        try untitled.removeMetadata(.title)
        try MP4Writer.write(untitled, to: files[5])
        var environment = noDates
        let release = Date(timeIntervalSince1970: 328_633_200)
        environment.readDates = { url in url == files[6] ? (Date(), Date()) : (release, release) }
        let run = Run(["check", library.root.path], environment: environment)
        #expect(run.status == 1)
        #expect(run.text.contains("shares disc 1 track 1 with 1 other file(s)"))
        #expect(run.text.contains("no title tag"))
        #expect(run.text.contains("differ from"))
    }

    @Test func libraryDifferencesAreDetected() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let music = FakeMusic(media: library.root)
        _ = try music.add(try library.m4aFiles())
        var environment = noDates
        environment.music = music
        let clean = Run(["check", library.root.path, "--library"], environment: environment)
        #expect(clean.text.contains("against the Music library"))
        // The substitute does not read composer, genre, or year; seed them from the files first.
        for index in music.library.indices {
            let file = try LibraryFiles.read(URL(fileURLWithPath: music.library[index].location!))
            music.library[index].composer = LibraryFiles.text(file.file, .composer) ?? ""
            music.library[index].genre = LibraryFiles.text(file.file, .genre) ?? ""
            music.library[index].year = Int(LibraryFiles.text(file.file, .releaseDate)?.prefix(4) ?? "") ?? 0
        }
        #expect(Run(["check", library.root.path, "--library"], environment: environment).status == 0)

        // Damage: a stale composer, a matched status, a file added twice, a missing file, and a file not added.
        music.library[0].composer = "Removed Writer"
        music.library[1].cloudStatus = "matched"
        music.library.append(music.library[2])
        let removed = try #require(music.library[3].location)
        try FileManager.default.removeItem(atPath: removed)
        let notAdded = music.library[4].location
        music.library.removeAll { $0.location == notAdded }
        let run = Run(["check", library.root.path, "--library"], environment: environment)
        #expect(run.status == 1)
        #expect(run.text.contains("composer differs: file \"Example Writer\", library \"Removed Writer\""))
        #expect(run.text.contains("cloud status is matched"))
        #expect(run.text.contains("in the library 2 times"))
        #expect(run.text.contains("a library track whose file is missing"))
        #expect(run.text.contains("not in the library"))
    }

    @Test func theLibraryComparisonRequiresMusic() {
        #expect(Run(["check", "/tmp", "--library"], environment: noDates).errorText.contains("requires macOS"))
    }
}

@Suite struct CheckCoverageTests {
    @Test func aRelocatedAlbumTrackIsReportedOutsideTheSelectedFolders() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let music = FakeMusic(media: library.root)
        _ = try music.add(try library.m4aFiles())
        let original = URL(fileURLWithPath: try #require(music.library[0].location))
        let relocated = FileManager.default.temporaryDirectory.appendingPathComponent("relocated-\(UUID()).m4a")
        try FileManager.default.moveItem(at: original, to: relocated)
        defer { try? FileManager.default.removeItem(at: relocated) }
        music.library[0].location = relocated.path
        var environment = Environment.testing
        environment.music = music
        environment.readDates = nil
        let run = Run(["check", library.root.path, "--library"], environment: environment)
        #expect(run.status == 1)
        #expect(run.text.contains("a track of this album is outside the selected folders"))
    }

    @Test func staleAlbumNamesStillMatchByLocationAndAllDuplicatesAreCompared() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let music = FakeMusic(media: library.root)
        _ = try music.add(try library.m4aFiles())
        let first = music.library[0]
        music.library[0].album = "Old Synthetic Album"
        var duplicate = first
        duplicate.persistentID = "SECOND"
        duplicate.comment = "Stale comment"
        duplicate.cloudStatus = "subscription"
        duplicate.trackCount = 99
        duplicate.discCount = 98
        duplicate.compilation = true
        music.library.append(duplicate)
        var environment = Environment.testing
        environment.music = music
        environment.readDates = nil
        let run = Run(["check", library.root.path, "--library"], environment: environment)
        #expect(run.status == 1)
        #expect(run.text.contains("album differs:"))
        #expect(run.text.contains("comment differs:"))
        #expect(run.text.contains("track count differs:"))
        #expect(run.text.contains("disc count differs:"))
        #expect(run.text.contains("compilation differs:"))
        #expect(run.text.contains("cloud status is subscription"))
    }

    @Test func missingAlbumAndBrokenFilesAreReportedTogether() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let music = FakeMusic(media: library.root)
        _ = try music.add(try library.m4aFiles())
        let file = try #require(try library.m4aFiles().first)
        try Data("broken".utf8).write(to: file)
        music.library.append(
            LibraryTrack(
                persistentID: "MISSING", name: "Lost Song", album: "Lost Album",
                artist: "Example Artist", albumArtist: "Example Artist",
                location: library.root.appendingPathComponent("missing.m4a").path))
        var environment = Environment.testing
        environment.music = music
        environment.readDates = nil
        let run = Run(["check", library.root.path, "--library"], environment: environment)
        #expect(run.status == 1)
        #expect(run.text.contains("cannot read audio metadata"))
        #expect(run.text.contains("a library track whose file is missing"))
        #expect(run.text.contains("Checked 8 files"))
    }

    @Test func libraryOnlyCheckReportsTracksWithoutFiles() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        let music = FakeMusic(media: library.root)
        music.library = [
            LibraryTrack(
                persistentID: "NOFILE", name: "Synthetic Song", album: "Synthetic Album",
                artist: "Example Artist", albumArtist: "Example Artist", cloudStatus: "matched")
        ]
        var environment = Environment.testing
        environment.music = music
        let run = Run(["check", "--library"], environment: environment)
        #expect(run.status == 1)
        #expect(run.text.contains("a library track without a file"))
        #expect(run.text.contains("cloud status is matched"))
        #expect(Run(["check"], environment: environment).status == 2)
    }

    @Test func unreadableDatesAreNotSilentlyAccepted() throws {
        let library = try SyntheticLibrary()
        defer { library.remove() }
        var environment = Environment.testing
        environment.readDates = { _ in throw CocoaError(.fileReadNoPermission) }
        let before = try library.snapshot()
        let run = Run(["check", library.root.path], environment: environment)
        #expect(run.status == 1)
        #expect(run.text.contains("file dates could not be read"))
        #expect(try library.snapshot() == before)
    }
}
