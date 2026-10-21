import Foundation
import Testing

@testable import GUIProbeMac

@Suite struct CommandLineTests {
    static let confirmations = [
        "--confirm-separate-test-user", "--confirm-synthetic-library", "--confirm-no-apple-account",
        "--confirm-no-cloud-library",
    ]
    static let survey = [
        "survey", "--output-directory", "ilibrary-gui-survey/records", "--output-name", "songs-1.json",
        "--mapping-directory", "ilibrary-gui-survey/private", "--time-budget", "600", "--operator-displayed-view",
        "songs",
    ]
    static let observe = [
        "observe", "--profile", "p.json", "--readings", "5", "--interval", "2.5", "--locale", "en_US", "--output",
        "o.json",
    ]

    @Test func surveyParsesWithAllConfirmations() throws {
        let command = try CommandLineParser.parse(Self.survey + ["--source-commit", "abc123"] + Self.confirmations)
        #expect(
            command
                == .survey(
                    SurveyOptions(
                        outputDirectory: ["ilibrary-gui-survey", "records"], outputName: "songs-1.json",
                        mappingDirectory: ["ilibrary-gui-survey", "private"], timeBudgetSeconds: 600,
                        displayedView: .songs,
                        confirmations: Confirmations(
                            separateTestUser: true, syntheticLibrary: true, noAppleAccount: true, noCloudLibrary: true),
                        sourceCommit: "abc123")))
    }

    @Test func missingConfirmationsParseAsUnconfirmed() throws {
        let command = try CommandLineParser.parse(Self.survey + ["--confirm-synthetic-library"])
        guard case .survey(let options) = command else {
            Issue.record("expected survey")
            return
        }
        #expect(options.confirmations == Confirmations(syntheticLibrary: true))
        #expect(options.sourceCommit == nil)
    }

    @Test func observeParsesEveryValue() throws {
        let command = try CommandLineParser.parse(
            Self.observe + ["--inventory-count", "0"] + Self.confirmations)
        guard case .observe(let options) = command else {
            Issue.record("expected observe")
            return
        }
        #expect(options.profilePath == "p.json")
        #expect(options.readings == 5)
        #expect(options.interval == 2.5)
        #expect(options.inventoryCount == 0)
        #expect(options.locale == "en_US")
        #expect(options.confirmations.noCloudLibrary)
    }

    @Test func theInventoryCountIsOptionalAndNeverDefaulted() throws {
        guard case .observe(let options) = try CommandLineParser.parse(Self.observe) else {
            Issue.record("expected observe")
            return
        }
        #expect(options.inventoryCount == nil)
        #expect(options.confirmations == Confirmations())
    }

    @Test(arguments: ["--readings", "--interval", "--profile", "--output", "--locale"])
    func observeRequiresEachOption(option: String) throws {
        var arguments = Self.observe
        let index = try #require(arguments.firstIndex(of: option))
        arguments.removeSubrange(index...(index + 1))
        #expect(throws: UsageError.missingOption(option)) { try CommandLineParser.parse(arguments) }
    }

    @Test(arguments: [
        "--output-directory", "--output-name", "--mapping-directory", "--time-budget", "--operator-displayed-view",
    ])
    func surveyRequiresEachOption(option: String) throws {
        var arguments = Self.survey
        let index = try #require(arguments.firstIndex(of: option))
        arguments.removeSubrange(index...(index + 1))
        #expect(throws: UsageError.missingOption(option)) { try CommandLineParser.parse(arguments) }
    }

    @Test func surveyNoLongerTakesAnOutputPath() {
        #expect(throws: UsageError.unknownOption("--output")) {
            try CommandLineParser.parse(Self.survey + ["--output", "o.json"])
        }
    }

    @Test(arguments: [
        ("--time-budget", "0"), ("--time-budget", "-1"), ("--time-budget", "3601"), ("--time-budget", "nan"),
        ("--time-budget", "inf"), ("--time-budget", "1e400"), ("--time-budget", "ten"),
        ("--operator-displayed-view", "albums"), ("--operator-displayed-view", "Songs"),
        ("--output-name", "songs"), ("--output-name", "a/b.json"), ("--output-name", ".songs.json"),
        ("--output-name", "songs.v2.json"), ("--output-name", "../songs.json"),
        ("--output-directory", "/absolute/x"), ("--output-directory", "a/../b"), ("--output-directory", "a//b"),
        ("--output-directory", ".hidden"), ("--output-directory", "Music/x"), ("--output-directory", "documents"),
        ("--output-directory", "LIBRARY/x"), ("--mapping-directory", "Desktop/private"),
        ("--mapping-directory", "a/./b"), ("--output-directory", "caf\u{E9}"),
    ])
    func invalidSurveyValuesAreRefused(option: String, value: String) throws {
        var arguments = Self.survey
        let index = try #require(arguments.firstIndex(of: option))
        arguments[index + 1] = value
        #expect(throws: UsageError.invalidValue(option)) { try CommandLineParser.parse(arguments) }
    }

    @Test func theBudgetBoundsAreTheSpecifiedOnes() throws {
        var arguments = Self.survey
        let index = try #require(arguments.firstIndex(of: "--time-budget"))
        for value in ["0.5", "3600"] {
            arguments[index + 1] = value
            guard case .survey(let options) = try CommandLineParser.parse(arguments) else {
                Issue.record("expected survey")
                return
            }
            #expect(options.timeBudgetSeconds == Double(value))
        }
        // The hard stop allows twice the largest unchecked stretch of requests at the 2-second timeout.
        #expect(
            SurveyLimits.hardStopMarginSeconds
                >= 2 * Double(SurveyLimits.maximumRequestsBetweenBudgetChecks) * WalkLimits().timeoutSeconds)
        #expect(SurveyLimits.maximumTimeBudgetSeconds == 3_600 && SurveyLimits.maximumConsecutiveTimedOutNodes == 5)
    }

    @Test func malformedInvocationsAreUsageErrors() {
        #expect(throws: UsageError.missingCommand) { try CommandLineParser.parse([]) }
        #expect(throws: UsageError.unknownCommand("probe")) { try CommandLineParser.parse(["probe"]) }
        #expect(throws: UsageError.unknownOption("--prompt")) {
            try CommandLineParser.parse(Self.survey + ["--prompt"])
        }
        #expect(throws: UsageError.missingValue("--output-name")) {
            try CommandLineParser.parse(["survey", "--output-name"])
        }
        #expect(throws: UsageError.missingValue("--output-name")) {
            try CommandLineParser.parse(["survey", "--output-name", "--confirm-no-cloud-library"])
        }
        #expect(throws: UsageError.duplicateOption("--output-name")) {
            try CommandLineParser.parse(Self.survey + ["--output-name", "b.json"])
        }
        #expect(throws: UsageError.duplicateOption("--confirm-no-cloud-library")) {
            try CommandLineParser.parse(Self.survey + ["--confirm-no-cloud-library", "--confirm-no-cloud-library"])
        }
        #expect(throws: UsageError.unknownOption("--profile")) {
            try CommandLineParser.parse(Self.survey + ["--profile", "p"])
        }
        #expect(throws: UsageError.invalidValue("--output-name")) {
            var arguments = Self.survey
            arguments[4] = ""
            return try CommandLineParser.parse(arguments)
        }
    }

    @Test(arguments: [
        ("--readings", "0"), ("--readings", "1001"), ("--readings", "x"), ("--interval", "-1"), ("--interval", "nan"),
        ("--interval", "3601"), ("--interval", "inf"), ("--inventory-count", "-1"), ("--inventory-count", "x"),
    ])
    func outOfRangeValuesAreRefused(option: String, value: String) {
        var arguments = Self.observe
        if let index = arguments.firstIndex(of: option) {
            arguments[index + 1] = value
        } else {
            arguments += [option, value]
        }
        #expect(throws: UsageError.invalidValue(option)) { try CommandLineParser.parse(arguments) }
    }

    @Test func usageErrorsHaveFixedDescriptions() {
        #expect(UsageError.missingOption("--readings").description == "option --readings is required")
        #expect(CommandLineParser.usage.contains("survey"))
    }
}
