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
            "CGWindowListCopyWindowInfo", "NSWorkspace", "AXObserverCreate",
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
