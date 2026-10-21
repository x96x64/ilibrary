import Foundation
import Testing

@testable import GUIProbeMac

@Suite struct CommandLineTests {
    static let confirmations = [
        "--confirm-separate-test-user", "--confirm-synthetic-library", "--confirm-no-apple-account",
        "--confirm-no-cloud-library",
    ]
    static let observe = [
        "observe", "--profile", "p.json", "--readings", "5", "--interval", "2.5", "--locale", "en_US", "--output",
        "o.json",
    ]

    @Test func surveyParsesWithAllConfirmations() throws {
        let command = try CommandLineParser.parse(
            ["survey", "--output", "o.json", "--source-commit", "abc123"] + Self.confirmations)
        #expect(
            command
                == .survey(
                    SurveyOptions(
                        output: "o.json",
                        confirmations: Confirmations(
                            separateTestUser: true, syntheticLibrary: true, noAppleAccount: true, noCloudLibrary: true),
                        sourceCommit: "abc123")))
    }

    @Test func missingConfirmationsParseAsUnconfirmed() throws {
        let command = try CommandLineParser.parse(["survey", "--output", "o.json", "--confirm-synthetic-library"])
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

    @Test func surveyRequiresAnOutput() {
        #expect(throws: UsageError.missingOption("--output")) { try CommandLineParser.parse(["survey"]) }
    }

    @Test func malformedInvocationsAreUsageErrors() {
        #expect(throws: UsageError.missingCommand) { try CommandLineParser.parse([]) }
        #expect(throws: UsageError.unknownCommand("probe")) { try CommandLineParser.parse(["probe"]) }
        #expect(throws: UsageError.unknownOption("--prompt")) {
            try CommandLineParser.parse(["survey", "--output", "o", "--prompt"])
        }
        #expect(throws: UsageError.missingValue("--output")) { try CommandLineParser.parse(["survey", "--output"]) }
        #expect(throws: UsageError.missingValue("--output")) {
            try CommandLineParser.parse(["survey", "--output", "--confirm-no-cloud-library"])
        }
        #expect(throws: UsageError.duplicateOption("--output")) {
            try CommandLineParser.parse(["survey", "--output", "a", "--output", "b"])
        }
        #expect(throws: UsageError.duplicateOption("--confirm-no-cloud-library")) {
            try CommandLineParser.parse([
                "survey", "--output", "a", "--confirm-no-cloud-library", "--confirm-no-cloud-library",
            ])
        }
        #expect(throws: UsageError.unknownOption("--profile")) {
            try CommandLineParser.parse(["survey", "--output", "a", "--profile", "p"])
        }
        #expect(throws: UsageError.invalidValue("--output")) {
            try CommandLineParser.parse(["survey", "--output", ""])
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
