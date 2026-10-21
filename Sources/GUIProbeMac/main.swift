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

    /// The hard stop of a survey: the system terminates the probe when the timer expires. No handler is installed,
    /// so the default action of SIGALRM, termination, applies even while a request blocks; because a disposition and
    /// a signal mask are inherited across exec, the default is restored and the signal unblocked first. The timer
    /// signals only this process. Nothing is written when it fires.
    func armHardStop(seconds: Double) -> Bool {
        var action = sigaction()
        action.__sigaction_u.__sa_handler = SIG_DFL
        sigemptyset(&action.sa_mask)
        action.sa_flags = 0
        guard sigaction(SIGALRM, &action, nil) == 0 else { return false }
        // The installed disposition is read back: the default has no handler.
        var current = sigaction()
        guard sigaction(SIGALRM, nil, &current) == 0, current.__sigaction_u.__sa_handler == nil else { return false }
        var unblock = sigset_t()
        sigemptyset(&unblock)
        sigaddset(&unblock, SIGALRM)
        guard pthread_sigmask(SIG_UNBLOCK, &unblock, nil) == 0 else { return false }
        let whole = seconds.rounded(.down)
        var timer = itimerval(
            it_interval: timeval(tv_sec: 0, tv_usec: 0),
            it_value: timeval(tv_sec: Int(whole), tv_usec: Int32((seconds - whole) * 1_000_000)))
        return setitimer(ITIMER_REAL, &timer, nil) == 0
    }

    /// A survey. Its records are written only into a directory validated below the home directory of the process
    /// user, and published only when complete; failures before that directory is validated write nothing.
    func runSurvey(_ options: SurveyOptions) -> Never {
        let clock = ContinuousClock()
        let start = clock.now
        func elapsed() -> Double {
            let duration = start.duration(to: clock.now).components
            return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        }
        let hardLimit = options.timeBudgetSeconds + SurveyLimits.hardStopMarginSeconds
        // The hard stop is armed first, so that every later step, including validation and publication, is bounded.
        guard armHardStop(seconds: hardLimit) else { stop("the hard time limit could not be armed", status: 1) }

        // Refusals that need no file system access write nothing.
        let confirmations = options.confirmations
        var preflight = Preflight()
        preflight.operatorConfirmedSeparateTestUser = confirmations.separateTestUser
        preflight.operatorConfirmedSyntheticLibrary = confirmations.syntheticLibrary
        preflight.operatorConfirmedNoAppleAccount = confirmations.noAppleAccount
        preflight.operatorConfirmedNoCloudLibrary = confirmations.noCloudLibrary
        let user = getuid()
        preflight.processUserMatchesTestUserPattern = Preflight.isTestUserName(processUserName()) && user != 0
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        preflight.macOSVersionPresent = !macOSVersion.isEmpty
        preflight.profileSupplied = true
        let early = preflight.failures.filter {
            $0 != .accessibilityNotTrusted && $0 != .musicProcessNotRunning && $0 != .versionsMissing
        }
        if !early.isEmpty { stop("refused: " + early.map(\.description).joined(separator: "; "), status: 1) }

        // The destination directories, reached from the home directory in the password database.
        guard let entry = getpwuid(user), let homePointer = entry.pointee.pw_dir else {
            stop("the home directory of the process user is unknown", status: 1)
        }
        let home = String(cString: homePointer)
        let mappingName = SurveyPlacement.mappingName(for: options.outputName)
        let output: ValidatedDirectory
        let mapping: ValidatedDirectory
        do {
            output = try SurveyPlacement.openValidated(options.outputDirectory, home: home, user: user)
            mapping = try SurveyPlacement.openValidated(options.mappingDirectory, home: home, user: user)
            try SurveyPlacement.requireSeparate(output, mapping)
            try SurveyPlacement.requireAbsent(options.outputName, in: output)
            try SurveyPlacement.requireAbsent(mappingName, in: mapping)
        } catch {
            stop("the output location was refused: \(error)", status: 1)
        }
        let runID = UUID().uuidString

        func publish(_ data: Data, name: String, in directory: ValidatedDirectory) {
            do {
                try SurveyPlacement.recheck(directory, home: home, user: user)
                if let left = try Publication.publish(data, name: name, runID: runID, in: directory.descriptor) {
                    FileHandle.standardError.write(
                        Data("GUIProbeMac: published '\(name)', but the temporary file '\(left)' remains\n".utf8))
                }
            } catch {
                stop("'\(name)' was not published: \(error)", status: 1)
            }
        }
        func record(status: RunStatus, stopReason: String?, music: String?) -> ProbeOutput {
            var record = ProbeOutput(
                mode: "survey", status: status, stopReason: stopReason, sourceCommit: options.sourceCommit,
                macOSVersion: macOSVersion, musicVersion: music, confirmations: confirmations)
            record.format = ProbeOutput.surveyFormat
            record.operatorDisplayedView = options.displayedView.rawValue
            return record
        }
        func refuseSurvey(_ reasons: [Reason], music: String?) -> Never {
            let reason = reasons.map(\.description).joined(separator: "; ")
            FileHandle.standardError.write(Data("GUIProbeMac: refused: \(reason)\n".utf8))
            guard let data = try? record(status: .refused, stopReason: reason, music: music).json() else {
                stop("the refusal record could not be encoded", status: 1)
            }
            publish(data, name: options.outputName, in: output)
            exit(1)
        }

        preflight.accessibilityTrusted = AccessibilityReader.isTrustedWithoutPrompting()
        if !preflight.accessibilityTrusted { refuseSurvey([.accessibilityNotTrusted], music: nil) }
        let music = AccessibilityReader.musicProcess()
        preflight.musicProcess = music.state
        preflight.musicVersionPresent = music.musicVersion != nil
        guard music.state == .exactlyOne, let pid = music.processIdentifier, let musicVersion = music.musicVersion
        else { refuseSurvey(preflight.failures, music: music.musicVersion) }
        // Without a launch date, a replacement process that reused the identifier could not be told apart.
        guard let before = music.identity else { refuseSurvey([.musicProcessIdentityUnknown], music: musicVersion) }

        let application = AccessibilityReader.applicationElement(processIdentifier: pid)
        var limits = WalkLimits()
        limits.timeBudgetSeconds = options.timeBudgetSeconds
        limits.maximumConsecutiveTimedOutNodes = SurveyLimits.maximumConsecutiveTimedOutNodes
        let snapshot = AccessibilityReader.walk(application: application, limits: limits, elapsed: elapsed)
        let walkSeconds = elapsed()
        // The process is read again after the walk, so that a walk that spanned the end or replacement of Music
        // is recorded as stopped rather than completed.
        let after = AccessibilityReader.musicProcess().identity
        let outcome = SurveyRun.outcome(
            before: before, after: after, applicationInvalid: snapshot.applicationInvalid,
            treeStatus: snapshot.status)
        var aliases = IdentifierAliases()
        var surveyRecord = record(status: outcome.status, stopReason: outcome.stopReason, music: musicVersion)
        surveyRecord.survey = SurveySanitizer.section(
            snapshot, limits: limits, aliases: &aliases, elapsedSeconds: walkSeconds, hardLimitSeconds: hardLimit,
            runID: runID, identifierMappingName: mappingName)
        let map = IdentifierMapping(runID: runID, recordName: options.outputName, aliases: aliases)
        guard let recordData = try? surveyRecord.json(), let mapData = try? map.json() else {
            stop("the survey record could not be encoded", status: 1)
        }
        // The shareable record is published first; a stop between the two leaves a record whose mapping is
        // missing, never raw identifiers without their record.
        publish(recordData, name: options.outputName, in: output)
        publish(mapData, name: mappingName, in: mapping)
        if let reason = outcome.stopReason {
            FileHandle.standardError.write(Data("GUIProbeMac: stopped: \(reason)\n".utf8))
        } else if snapshot.status != .complete {
            FileHandle.standardError.write(
                Data("GUIProbeMac: the walk is incomplete: \(snapshot.status.rawValue)\n".utf8))
        }
        exit(outcome.exitStatus)
    }

    func run() -> Never {
        let command: ProbeCommand
        do {
            command = try CommandLineParser.parse(Array(CommandLine.arguments.dropFirst()))
        } catch {
            stop("\(error)\n\(CommandLineParser.usage)", status: 2)
        }
        let observeOptions: ObserveOptions
        switch command {
        case .survey(let options): runSurvey(options)
        case .observe(let options): observeOptions = options
        }
        let (mode, confirmations, outputPath, commit) = (
            "observe", observeOptions.confirmations, observeOptions.output, observeOptions.sourceCommit
        )
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
        do {
            let options = observeOptions
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
        do {
            let options = observeOptions
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
