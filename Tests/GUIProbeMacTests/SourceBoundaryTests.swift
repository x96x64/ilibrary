import Foundation
import Testing

@Suite struct SourceBoundaryTests {
    static let sources: URL = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent("Sources/GUIProbeMac")
    }()

    static func swiftFiles() throws -> [(name: String, text: String)] {
        try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }.sorted()
            .map { ($0, try String(contentsOf: sources.appendingPathComponent($0), encoding: .utf8)) }
    }

    /// A token that ends in an opening parenthesis is a call; it must not be the tail of a longer identifier,
    /// such as the required `indeterminate(` case, which contains `terminate(`.
    static func contains(_ text: String, _ token: String) -> Bool {
        guard token.hasSuffix("("), let first = token.first, first.isLetter else { return text.contains(token) }
        let pattern = "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: token)
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    @Test func theTokenMatcherIgnoresLongerIdentifiers() {
        #expect(Self.contains("x.terminate(true)", "terminate("))
        #expect(Self.contains("terminate()", "terminate("))
        #expect(!Self.contains("return .indeterminate(reasons: [])", "terminate("))
        #expect(!Self.contains("musicProcess()", "Process("))
        #expect(Self.contains("Process()", "Process("))
        #expect(Self.contains("// osascript", "osascript"))
    }

    @Test func theProbeSourceUsesNoForbiddenInterface() throws {
        let forbidden = [
            "AXUIElementPerformAction", "AXUIElementSetAttributeValue", "AXUIElementCopyActionNames", "AXObserver",
            "activate(", "launchApplication", "openApplication", "NSWorkspace.shared.open", "terminate(",
            "forceTerminate", "NSAppleScript", "OSAScript", "osascript", "System Events", "CGEvent",
            "CGWindowListCreateImage", "SCScreenshot", "Process(", "NSTask", "ScriptingBridge", "SBApplication",
            "MediaPlayer", "iTunesLibrary", "ITLibrary", "sqlite", "FileManager.default.removeItem",
            "kAXTrustedCheckOptionPrompt: true", "posix_spawn", "popen(", "system(", "execv", "execl", "fork(",
            "ScreenCaptureKit", "SCStream", "SCShareable", "AXUIElementPostKeyboardEvent", "CGDisplayCreateImage",
            "CGWindowListCopyWindowInfo", "NSWorkspace", "AXObserverCreate", "kill(", "killpg(", "raise(",
            "unlink(", "rename(", "remove(", "renameat(",
        ]
        let files = try Self.swiftFiles()
        #expect(files.count >= 6)
        for file in files {
            for token in forbidden { #expect(!Self.contains(file.text, token), "\(file.name) contains \(token)") }
            for line in file.text.split(separator: "\n") where line.contains("TrustedCheckOptionPrompt") {
                #expect(!line.contains("true"), "\(file.name) enables the permission prompt")
            }
        }
    }

    @Test func theOnlyPromptOptionOccurrenceIsFalse() throws {
        var occurrences = 0
        for file in try Self.swiftFiles() {
            for line in file.text.split(separator: "\n") {
                let count = line.components(separatedBy: "AXTrustedCheckOptionPrompt").count - 1
                occurrences += count
                if count > 0 { #expect(line.contains(#"AXTrustedCheckOptionPrompt": false"#), "\(file.name)") }
            }
        }
        #expect(occurrences == 1)
    }

    @Test func theTrustCheckSetsThePromptOptionToFalseOnly() throws {
        let reader = try #require(Self.swiftFiles().first { $0.name == "AccessibilityReader.swift" })
        #expect(reader.text.contains(#"["AXTrustedCheckOptionPrompt": false]"#))
        #expect(reader.text.components(separatedBy: "AXIsProcessTrusted").count == 2)
    }

    @Test func onlyTheAllowListedAttributesAreRead() throws {
        let allowed: Set<String> = [
            "AXRole", "AXSubrole", "AXIdentifier", "AXChildren", "AXWindows", "AXMainWindow", "AXFocusedWindow",
            "AXRows", "AXVisibleRows", "AXVisibleChildren", "AXBusy", "AXTitle", "AXDescription",
            "AXHorizontalScrollBar", "AXVerticalScrollBar", "AXValue",
        ]
        let reader = try #require(Self.swiftFiles().first { $0.name == "AccessibilityReader.swift" })
        let pattern = try NSRegularExpression(pattern: #""(AX[A-Za-z]+)""#)
        let range = NSRange(reader.text.startIndex..., in: reader.text)
        let used = pattern.matches(in: reader.text, range: range).compactMap { match -> String? in
            Range(match.range(at: 1), in: reader.text).map { String(reader.text[$0]) }
        }
        // Role names and the application role are compared, not read as attributes.
        let comparedValues: Set<String> = [
            "AXApplication", "AXScrollBar", "AXScrollArea", "AXTable", "AXOutline", "AXList", "AXBrowser",
        ]
        for name in Set(used) where !comparedValues.contains(name) && name != "AXTrustedCheckOptionPrompt" {
            #expect(allowed.contains(name), "\(name) is not allow-listed")
        }
        #expect(!reader.text.contains("AXPosition") && !reader.text.contains("AXSize"))
    }

    @Test func theReaderIsGuardedAndTheDecisionFilesAreFoundationOnly() throws {
        let files = try Self.swiftFiles()
        let reader = try #require(files.first { $0.name == "AccessibilityReader.swift" })
        let trimmed = reader.text.split(separator: "\n").filter { !$0.hasPrefix("//") }
        #expect(trimmed.first == "#if canImport(ApplicationServices) && canImport(AppKit)")
        #expect(trimmed.last == "#endif")
        for name in ["Classification.swift", "Profile.swift", "TreeWalking.swift", "CommandLineOptions.swift"] {
            let file = try #require(files.first { $0.name == name })
            for module in ["AppKit", "ApplicationServices", "AVFoundation", "ScriptingBridge", "Darwin", "Glibc"] {
                #expect(!file.text.contains("import \(module)"), "\(name) imports \(module)")
            }
        }
    }

    /// The macOS reader is compiled but cannot run without the accessibility service, so this source check guards
    /// the merge of the application's windows into its children: a cut windows list must mark the merged list cut.
    @Test func theReaderKeepsTheTruncationOfTheWindowsList() throws {
        let files = try Self.swiftFiles()
        let reader = try #require(files.first { $0.name == "AccessibilityReader.swift" })
        #expect(reader.text.contains("let windows = elements(element, \"AXWindows\")"))
        #expect(reader.text.contains("if windows.truncated { result.truncated = true }"))
        #expect(reader.text.contains("if windows.unavailable { result.unavailable = true }"))
        // The windows are read for the application element by identity, not after a second role read.
        #expect(reader.text.contains("if CFEqual(element, application) {"))
        #expect(!reader.text.contains("var scratch = NodeFacts()\n                if text(element, \"AXRole\""))
    }

    /// The application's own child count is compared with its children before the windows are merged; the
    /// reader must keep that number before it reads the windows list.
    @Test func theReaderKeepsTheChildCountBeforeMergingWindows() throws {
        let files = try Self.swiftFiles()
        let reader = try #require(files.first { $0.name == "AccessibilityReader.swift" })
        let keep = try #require(reader.text.range(of: "result.primaryCount = result.nodes.count"))
        let windows = try #require(reader.text.range(of: "let windows = elements(element, \"AXWindows\")"))
        let merge = try #require(reader.text.range(of: "result.nodes.append(window)"))
        #expect(keep.lowerBound < windows.lowerBound && windows.lowerBound < merge.lowerBound)
        #expect(reader.text.components(separatedBy: "primaryCount").count == 2)
    }

    /// The subrole is read with its presence, so that a value that is not text is unreadable rather than absent.
    @Test func theReaderReadsTheSubroleWithItsPresence() throws {
        let files = try Self.swiftFiles()
        let reader = try #require(files.first { $0.name == "AccessibilityReader.swift" })
        #expect(reader.text.contains("(facts.subrole, facts.hasSubrole) = text(element, \"AXSubrole\", into: &facts)"))
    }

    /// The extractor never derives that a view cannot scroll.
    @Test func theExtractorNeverReportsAViewAsNotScrollable() throws {
        let files = try Self.swiftFiles()
        let walking = try #require(files.first { $0.name == "TreeWalking.swift" })
        #expect(!walking.text.contains("scrollable = false"))
        #expect(walking.text.contains("if scrollable { reading.scrollable = true }"))
    }

    /// The code of a source file without its string literals and comments, so that a check of the code can be
    /// neither met nor defeated by prose. This is static text analysis: it cannot see a function reached through
    /// dynamic lookup, which is excluded separately, and it does not prove runtime behavior.
    static func code(_ text: String) -> String {
        let tripleQuote = String(repeating: "\"", count: 3)
        var result = text.replacingOccurrences(
            of: tripleQuote + #"[\s\S]*?"# + tripleQuote, with: "\"\"", options: .regularExpression)
        result = result.replacingOccurrences(of: #""(?:[^"\\\n]|\\.)*""#, with: "\"\"", options: .regularExpression)
        result = result.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
        return result.replacingOccurrences(of: #"//[^\n]*"#, with: "", options: .regularExpression)
    }

    static func accessibilityNames(_ code: String) -> Set<String> {
        let pattern = try! NSRegularExpression(pattern: #"\bAX[A-Za-z0-9_]+\b"#)
        let range = NSRange(code.startIndex..., in: code)
        return Set(
            pattern.matches(in: code, range: range).compactMap { Range($0.range, in: code).map { String(code[$0]) } })
    }

    @Test func theCodeFilterIgnoresCommentsAndStrings() {
        let text = "// AXUIElementPerformAction\nlet a = \"AXUIElementSetAttributeValue\"\n_ = AXUIElementGetTypeID()"
        #expect(Self.accessibilityNames(Self.code(text)) == ["AXUIElementGetTypeID"])
    }

    /// A positive allow-list of the accessibility functions and types that the probe's code names: the non-prompting
    /// trust check, the creation of the application element, the client-side messaging timeout, and the attribute,
    /// count, and range reads. It supplements the deny-list above; a name outside it, such as an action, a setter,
    /// an observer, or the system-wide element, fails the test. It is a source check and is no proof of runtime
    /// behavior, so the reader remains subject to independent review.
    @Test func onlyAllowListedAccessibilityFunctionsAreNamed() throws {
        let allowed: Set<String> = [
            "AXIsProcessTrustedWithOptions", "AXUIElement", "AXUIElementCreateApplication",
            "AXUIElementSetMessagingTimeout", "AXUIElementCopyAttributeValue", "AXUIElementGetAttributeValueCount",
            "AXUIElementCopyAttributeValues", "AXUIElementGetTypeID",
        ]
        var named: Set<String> = []
        for file in try Self.swiftFiles() {
            let code = Self.code(file.text)
            let names = Self.accessibilityNames(code)
            if file.name != "AccessibilityReader.swift" {
                #expect(names.isEmpty, "\(file.name) names \(names.sorted())")
            }
            named.formUnion(names)
            for dynamic in [
                "dlsym", "dlopen", "NSClassFromString", "NSSelectorFromString", "perform(", "_silgen_name", "@_cdecl",
            ] {
                #expect(!Self.contains(code, dynamic), "\(file.name) uses \(dynamic)")
            }
        }
        #expect(named.isSubset(of: allowed), "not allow-listed: \(named.subtracting(allowed).sorted())")
        #expect(named.contains("AXUIElementCopyAttributeValue") && named.contains("AXIsProcessTrustedWithOptions"))
    }

    /// The survey path cannot run without the accessibility service, so this source check guards its contract: the
    /// launch identity is required before any element is created, the process is read again after the walk, and the
    /// status and exit status come from the outcome rule rather than being fixed as completed and zero.
    /// The code of the survey flow in main.swift.
    static func surveyCode() throws -> String {
        let main = try #require(swiftFiles().first { $0.name == "main.swift" })
        let code = Self.code(main.text)
        let start = try #require(code.range(of: "func runSurvey(_ options: SurveyOptions) -> Never {"))
        let end = try #require(code.range(of: "func run() -> Never {", range: start.upperBound..<code.endIndex))
        return String(code[start.upperBound..<end.lowerBound])
    }

    static func position(_ token: String, in text: String) throws -> String.Index {
        try #require(text.range(of: token), "missing: \(token)").lowerBound
    }

    /// The survey path cannot run without the accessibility service, so this source check guards its order: the
    /// hard stop is armed before any file system access; refusals that need no file system access write nothing;
    /// the destination is validated before any record can be written; the launch identity is required before an
    /// element is created; the process is read again after the walk; and the record is published before the
    /// private mapping, with the status and exit status taken from the outcome rule.
    @Test func theSurveyFlowKeepsItsReviewedOrder() throws {
        let survey = try Self.surveyCode()
        let order = [
            "armHardStop(seconds: hardLimit)", "if !early.isEmpty { stop(", "getpwuid(user)",
            "SurveyPlacement.openValidated(options.outputDirectory", "SurveyPlacement.requireSeparate(output, mapping)",
            "SurveyPlacement.requireAbsent(options.outputName, in: output)",
            "AccessibilityReader.isTrustedWithoutPrompting()", "guard let before = music.identity",
            "AccessibilityReader.applicationElement(", "AccessibilityReader.walk(",
            "AccessibilityReader.musicProcess().identity",
            "SurveyRun.outcome(", "publish(recordData, name: options.outputName, in: output)",
            "publish(mapData, name: mappingName, in: mapping)", "exit(outcome.exitStatus)",
        ]
        let positions = try order.map { try Self.position($0, in: survey) }
        #expect(positions == positions.sorted())
        #expect(survey.contains("record(status: outcome.status, stopReason: outcome.stopReason"))
        // The survey never uses the unvalidated output path of observe.
        for token in ["finish(", "ExclusiveFile", "refuse(", "status: .completed", "options.output,"] {
            #expect(!survey.contains(token), "the survey flow contains \(token)")
        }
        #expect(survey.contains("try SurveyPlacement.recheck(directory, home: home, user: user)"))
    }

    /// The hard stop uses only the default action of SIGALRM and a single-shot real-time timer of this process.
    @Test func theHardStopUsesOnlyTheDefaultActionOfItsOwnTimer() throws {
        let main = try #require(Self.swiftFiles().first { $0.name == "main.swift" })
        let code = Self.code(main.text)
        #expect(code.contains("action.__sigaction_u.__sa_handler = SIG_DFL"))
        #expect(code.components(separatedBy: "__sa_handler = ").count == 2)
        #expect(code.contains("guard sigaction(SIGALRM, &action, nil) == 0"))
        #expect(code.contains("pthread_sigmask(SIG_UNBLOCK, &unblock, nil)"))
        #expect(code.contains("setitimer(ITIMER_REAL, &timer, nil)"))
        #expect(code.contains("it_interval: timeval(tv_sec: 0, tv_usec: 0)"))
        for file in try Self.swiftFiles() {
            let text = Self.code(file.text)
            for token in [
                "signal(", "SIGKILL", "SIGTERM", "SIGINT", "SIGSTOP", "ITIMER_VIRTUAL", "ITIMER_PROF", "alarm(",
            ] {
                #expect(!Self.contains(text, token), "\(file.name) uses \(token)")
            }
            if file.name != "main.swift" {
                #expect(!text.contains("sigaction(") && !text.contains("setitimer("), "\(file.name)")
            }
        }
    }

    /// Survey records are published only through the descriptor-relative exclusive sequence.
    @Test func publicationLinksWithoutReplacing() throws {
        let file = try #require(Self.swiftFiles().first { $0.name == "SurveyPlacement.swift" })
        let code = Self.code(file.text)
        #expect(code.contains("O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600"))
        #expect(code.contains("linkat(directory, temporary, directory, name, 0)"))
        #expect(code.contains("O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC"))
        #expect(!code.contains("renameat") && !code.contains("rename("))
    }

    /// Source checks for the macOS count reads, which the synthetic tests cannot execute.
    @Test func theReaderNeverTakesAnUnavailableOrNegativeCountForEmptiness() throws {
        let files = try Self.swiftFiles()
        let reader = try #require(files.first { $0.name == "AccessibilityReader.swift" })
        #expect(
            reader.text.contains(
                "case .noValue, .attributeUnsupported: return Children(nodes: [], error: nil, unavailable: true)"))
        #expect(
            reader.text.contains("facts.errors.append(AttributeError(attribute: attribute, code: invalidCountCode))"))
    }

    @Test func theProbeAddsNoPackageDependency() throws {
        let package = Sources.packageManifest
        // The probe depends only on the repository's portable RebuildCore, for SHA-256; no package dependency.
        #expect(package.contains(#".executableTarget(name: "GUIProbeMac", dependencies: ["RebuildCore"])"#))
        #expect(!package.contains(".package("))
        #expect(package.contains(#".testTarget(name: "GUIProbeMacTests", dependencies: ["GUIProbeMac"])"#))
    }

    enum Sources {
        static var packageManifest: String {
            let root = SourceBoundaryTests.sources.deletingLastPathComponent().deletingLastPathComponent()
            return (try? String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)) ?? ""
        }
    }
}
