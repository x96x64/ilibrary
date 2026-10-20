// M11Probe: a read-only qualification probe for the maintainer's separate test user. It is not part of the
// `ilibrary` product. Usage: M11Probe readers --output FILE
//
// The guards follow `require_test_user` and `check_account` of scripts/validation/rebuild_probe.py: the
// process owner is taken from the password database and not from USER or LOGNAME, `defaults export
// MobileMeAccounts -` must report no signed-in account, and the output file must not exist. `defaults` is the
// only external tool. The probe reads the Music library and writes only the exclusively created output file.
#if os(macOS)
    import Darwin
    import Foundation
    import LibraryMac

    func fail(_ message: String, status: Int32) -> Never {
        FileHandle.standardError.write(Data("M11Probe: \(message)\n".utf8))
        exit(status)
    }

    func processUserName() -> String {
        guard let entry = getpwuid(getuid()), let name = entry.pointee.pw_name else { return "" }
        return String(cString: name)
    }

    func readAccountState() -> AccountState {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["export", "MobileMeAccounts", "-"]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return .unreadable }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProbeGuards.classifyAccount(
            status: process.terminationStatus, standardOutput: outData,
            standardError: String(decoding: errData, as: UTF8.self))
    }

    func pathExists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// Creates the file exclusively with mode 0600 and writes the data, failing if the path exists.
    func writeExclusively(_ data: Data, to path: String) throws {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += written
            }
        }
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 3, arguments[0] == "readers", arguments[1] == "--output", !arguments[2].isEmpty
    else { fail("usage: M11Probe readers --output FILE", status: 64) }
    let outputPath = arguments[2]

    let userName = processUserName()
    let environment = ProbeEnvironment(
        userName: userName, uid: UInt32(getuid()),
        account: ProbeGuards.isTestUserName(userName) && getuid() != 0 ? readAccountState() : .unreadable,
        outputExists: pathExists(outputPath))
    if let refusal = ProbeGuards.refusal(for: environment) { fail(refusal.message, status: 2) }

    let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    var report = ProbeReport(
        userNameCheckPassed: true,
        macOSVersion: "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
        musicVersion: "")
    var status: Int32 = 0
    do {
        report.musicVersion = try MusicApp.musicVersion()
        let clock = ContinuousClock()
        var perTrack: [MusicTrackInfo] = []
        let perTrackTime = try clock.measure { perTrack = try MusicApp.allTracks() }
        var bulk: (tracks: [MusicTrackInfo], usedFallback: Bool) = ([], false)
        let bulkTime = try clock.measure { bulk = try MusicApp.allTracksBulkReportingFallback() }
        var snapshot = MusicLibrarySnapshot(tracks: [], trackCount: 0, fileTrackCount: 0, dateAddedSeconds: [:])
        let snapshotTime = try clock.measure { snapshot = try MusicApp.librarySnapshot() }
        report = ProbeReportBuilder.build(
            macOSVersion: report.macOSVersion, musicVersion: report.musicVersion, perTrack: perTrack,
            bulk: bulk.tracks, bulkFallbackUsed: bulk.usedFallback, snapshot: snapshot,
            durations: ProbeReport.Durations(
                perTrackSeconds: seconds(perTrackTime), bulkSeconds: seconds(bulkTime),
                snapshotSeconds: seconds(snapshotTime)))
    } catch {
        report.error = "\(error)"
        status = 1
    }
    do {
        try writeExclusively(report.json(), to: outputPath)
    } catch {
        fail("the report could not be written: \(error)", status: 1)
    }
    if status != 0 { fail("the probe stopped on an error; see the report", status: status) }
#endif
