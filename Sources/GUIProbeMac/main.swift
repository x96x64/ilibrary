// GUIProbeMac: a read-only, validation-only feasibility probe for the maintainer's separate test user. It is not
// part of the `ilibrary` product and is never run by the public suite. It asks whether the Songs and Recently
// Added views of Music can be read, through the accessibility interface, with enough structure to support a
// candidate-for-emptiness verdict, and it refuses unless every precondition is confirmed. It never prompts for
// permission, never acts on Music, and writes only the exclusively created output file.
import Foundation
import RebuildCore

#if canImport(ApplicationServices) && canImport(AppKit)
    #if canImport(Darwin)
        import Darwin
    #endif

    func stop(_ message: String, status: Int32) -> Never {
        FileHandle.standardError.write(Data("GUIProbeMac: \(message)\n".utf8))
        exit(status)
    }

    func processUserName() -> String {
        guard let entry = getpwuid(getuid()), let name = entry.pointee.pw_name else { return "" }
        return String(cString: name)
    }

    /// Writes the output, or reports the failure; the status is that of the run unless writing fails.
    func finish(_ output: ProbeOutput, path: String, status: Int32) -> Never {
        do {
            try ExclusiveFile.createAndWrite(output.json(), to: path)
        } catch {
            stop("the output could not be written: \(error)", status: 1)
        }
        exit(status)
    }

    func refuse(
        mode: String, reasons: [Reason], confirmations: Confirmations, options: (output: String, commit: String?),
        macOS: String?, music: String?
    ) -> Never {
        var output = ProbeOutput(
            mode: mode, status: .refused, stopReason: reasons.map(\.description).joined(separator: "; "),
            sourceCommit: options.commit, macOSVersion: macOS, musicVersion: music, confirmations: confirmations)
        if reasons.isEmpty { output.stopReason = "refused" }
        FileHandle.standardError.write(Data("GUIProbeMac: refused: \(output.stopReason ?? "")\n".utf8))
        finish(output, path: options.output, status: 1)
    }

    func run() -> Never {
        let command: ProbeCommand
        do {
            command = try CommandLineParser.parse(Array(CommandLine.arguments.dropFirst()))
        } catch {
            stop("\(error)\n\(CommandLineParser.usage)", status: 2)
        }
        let mode: String
        let confirmations: Confirmations
        let outputPath: String
        let commit: String?
        switch command {
        case .survey(let options):
            (mode, confirmations, outputPath, commit) = (
                "survey", options.confirmations, options.output, options.sourceCommit
            )
        case .observe(let options):
            (mode, confirmations, outputPath, commit) = (
                "observe", options.confirmations, options.output, options.sourceCommit
            )
        }
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let context = (output: outputPath, commit: commit)

        // Refusals that precede every accessibility call.
        var preflight = Preflight()
        preflight.operatorConfirmedSeparateTestUser = confirmations.separateTestUser
        preflight.operatorConfirmedSyntheticLibrary = confirmations.syntheticLibrary
        preflight.operatorConfirmedNoAppleAccount = confirmations.noAppleAccount
        preflight.operatorConfirmedNoCloudLibrary = confirmations.noCloudLibrary
        preflight.processUserMatchesTestUserPattern = Preflight.isTestUserName(processUserName()) && getuid() != 0
        preflight.macOSVersionPresent = !macOSVersion.isEmpty
        preflight.profileSupplied = true
        let early = preflight.failures.filter {
            $0 != .accessibilityNotTrusted && $0 != .musicProcessNotRunning
                && $0 != .versionsMissing
        }
        if ExclusiveFile.exists(outputPath) {
            stop("the output file already exists; it is never overwritten", status: 1)
        }
        if !early.isEmpty {
            refuse(
                mode: mode, reasons: early, confirmations: confirmations, options: context, macOS: macOSVersion,
                music: nil)
        }
        // In observe mode the profile is read and checked before any accessibility call.
        var loadedProfile: InterfaceProfile?
        var profileDigest: String?
        if case .observe(let options) = command {
            let profile: InterfaceProfile
            do {
                let bytes = try Data(contentsOf: URL(fileURLWithPath: options.profilePath))
                profileDigest = SHA256.digest(of: bytes).hex
                profile = try InterfaceProfile.decode(from: bytes)
            } catch {
                refuse(
                    mode: mode, reasons: [.noReviewedProfile], confirmations: confirmations, options: context,
                    macOS: macOSVersion, music: nil)
            }
            let failures = profile.qualificationFailures(
                for: ObservedContext(
                    macOSVersion: macOSVersion, musicVersion: profile.musicVersion, locale: options.locale)
            )
            if !failures.isEmpty {
                refuse(
                    mode: mode, reasons: failures, confirmations: confirmations, options: context,
                    macOS: macOSVersion, music: nil)
            }
            loadedProfile = profile
        }
        preflight.accessibilityTrusted = AccessibilityReader.isTrustedWithoutPrompting()
        if !preflight.accessibilityTrusted {
            FileHandle.standardError.write(
                Data(
                    "GUIProbeMac: this process is not trusted for accessibility; the operator must grant it in System Settings\n"
                        .utf8))
            refuse(
                mode: mode, reasons: [.accessibilityNotTrusted], confirmations: confirmations, options: context,
                macOS: macOSVersion, music: nil)
        }
        let music = AccessibilityReader.musicProcess()
        preflight.musicProcess = music.state
        preflight.musicVersionPresent = music.musicVersion != nil
        guard music.state == .exactlyOne, let pid = music.processIdentifier, let musicVersion = music.musicVersion
        else {
            refuse(
                mode: mode, reasons: preflight.failures, confirmations: confirmations, options: context,
                macOS: macOSVersion, music: music.musicVersion)
        }

        if let loadedProfile, loadedProfile.musicVersion != musicVersion {
            refuse(
                mode: mode, reasons: [.versionMismatch], confirmations: confirmations, options: context,
                macOS: macOSVersion, music: musicVersion)
        }
        let application = AccessibilityReader.applicationElement(processIdentifier: pid)
        let limits = WalkLimits()
        switch command {
        case .survey:
            let snapshot = AccessibilityReader.walk(application: application, limits: limits)
            var output = ProbeOutput(
                mode: mode, status: .completed, sourceCommit: commit, macOSVersion: macOSVersion,
                musicVersion: musicVersion, confirmations: confirmations)
            output.survey = SurveySanitizer.section(snapshot, limits: limits)
            finish(output, path: outputPath, status: 0)
        case .observe(let options):
            guard let profile = loadedProfile else { stop("internal error: no profile", status: 1) }
            let observed = ObservedContext(
                macOSVersion: macOSVersion, musicVersion: musicVersion, locale: options.locale)
            let clock = ContinuousClock()
            let start = clock.now
            var songs: [ViewReading] = []
            var recent: [ViewReading] = []
            var stopReason: String?
            // The identifier alone could be reused by a replacement process; the launch date must also match, and an
            // unknown launch date never confirms identity.
            func sameLaunch(_ snapshot: MusicProcessSnapshot) -> Bool {
                guard let first = music.launchDate, let later = snapshot.launchDate else { return false }
                return first == later
            }
            for index in 0..<options.readings {
                if index > 0 {
                    Thread.sleep(forTimeInterval: options.interval)
                    let again = AccessibilityReader.musicProcess()
                    if again.state != .exactlyOne || again.processIdentifier != pid || !sameLaunch(again) {
                        stopReason = "the Music process changed or ended after \(songs.count) readings"
                        break
                    }
                }
                let snapshot = AccessibilityReader.walk(application: application, limits: limits)
                if snapshot.applicationInvalid {
                    stopReason = "the application element became invalid after \(songs.count) readings"
                    break
                }
                let duration = start.duration(to: clock.now).components
                let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                songs.append(ViewExtractor.reading(of: profile.songs, in: snapshot, elapsed: elapsed))
                recent.append(ViewExtractor.reading(of: profile.recentlyAdded, in: snapshot, elapsed: elapsed))
            }
            if stopReason == nil {
                // A process that ends during the last walk would otherwise leave a completed record.
                let after = AccessibilityReader.musicProcess()
                if after.state != .exactlyOne || after.processIdentifier != pid || !sameLaunch(after) {
                    stopReason = "the Music process changed or ended during the last reading"
                }
            }
            preflight.profileSupplied = true
            let inventory = InventoryEvidence(fileTrackCount: options.inventoryCount)
            func verdict(_ view: ViewKind, _ readings: [ViewReading]) -> Verdict {
                Classifier.classify(
                    readings: readings, view: view, preflight: preflight, context: observed, profile: profile,
                    inventory: inventory)
            }
            let stoppedRun = stopReason != nil
            let songsVerdict = stoppedRun ? Classifier.stopped(verdict(.songs, songs)) : verdict(.songs, songs)
            let recentVerdict =
                stoppedRun ? Classifier.stopped(verdict(.recentlyAdded, recent)) : verdict(.recentlyAdded, recent)
            let combined = Classifier.combine(songsVerdict, recentVerdict)
            var output = ProbeOutput(
                mode: mode, status: stopReason == nil ? .completed : .stopped, stopReason: stopReason,
                sourceCommit: commit, macOSVersion: macOSVersion, musicVersion: musicVersion,
                confirmations: confirmations)
            output.profileSHA256 = profileDigest
            output.observation = ObservationSection(
                readingsRequested: options.readings, intervalSeconds: options.interval, locale: options.locale,
                inventoryFileTrackCount: options.inventoryCount,
                songs: ViewObservation(readings: songs, verdict: VerdictRecord(songsVerdict)),
                recentlyAdded: ViewObservation(readings: recent, verdict: VerdictRecord(recentVerdict)),
                combined: VerdictRecord(combined))
            if stopReason != nil { finish(output, path: outputPath, status: 1) }
            if case .indeterminate = combined { finish(output, path: outputPath, status: 1) }
            finish(output, path: outputPath, status: 0)
        }
    }

    run()
#else
    FileHandle.standardError.write(Data("GUIProbeMac: the probe requires macOS\n".utf8))
    exit(2)
#endif
