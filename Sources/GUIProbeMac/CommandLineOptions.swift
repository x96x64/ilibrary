// Argument parsing of the probe. Foundation-only. Missing confirmation flags are not usage errors: they parse
// as unconfirmed and make the probe refuse. Missing readings or interval, and every unknown option, are usage
// errors, and no value has a default.
import Foundation

/// The view that the operator declares was displayed during a survey.
enum DisplayedView: String, Equatable, Sendable {
    case songs
    case recentlyAdded = "recently-added"
}

struct SurveyOptions: Equatable, Sendable {
    /// Directories below the home directory of the process user, as checked lexical components.
    var outputDirectory: [String]
    var outputName: String
    var mappingDirectory: [String]
    var timeBudgetSeconds: Double
    var displayedView: DisplayedView
    var confirmations: Confirmations
    var sourceCommit: String?
}

/// The bounds of a survey's time budget and its hard stop. Between two budget checks the reader issues at most 15
/// requests for one node's facts, each bounded by the 2-second messaging timeout, so the budget can be overrun by
/// about 30 seconds; the hard stop allows twice that. These figures assume that the timeout is honored, which has
/// not been measured.
enum SurveyLimits {
    static let maximumTimeBudgetSeconds = 3_600.0
    static let maximumRequestsBetweenBudgetChecks = 15
    static let hardStopMarginSeconds = 60.0
    /// A hung application times out on every request, so five such nodes in a row stop the walk after about
    /// 150 seconds, while a single slow element in a responsive application resets the count.
    static let maximumConsecutiveTimedOutNodes = 5
}

struct ObserveOptions: Equatable, Sendable {
    var profilePath: String
    var inventoryCount: Int?
    var readings: Int
    var interval: Double
    var locale: String
    var output: String
    var confirmations: Confirmations
    var sourceCommit: String?
}

enum ProbeCommand: Equatable, Sendable {
    case survey(SurveyOptions)
    case observe(ObserveOptions)
}

enum UsageError: Error, Equatable, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case unknownOption(String)
    case missingValue(String)
    case duplicateOption(String)
    case missingOption(String)
    case invalidValue(String)

    var description: String {
        switch self {
        case .missingCommand: "a command is required: survey or observe"
        case .unknownCommand(let name): "unknown command '\(name)'"
        case .unknownOption(let name): "unknown option '\(name)'"
        case .missingValue(let name): "option \(name) requires a value"
        case .duplicateOption(let name): "option \(name) was given more than once"
        case .missingOption(let name): "option \(name) is required"
        case .invalidValue(let name): "option \(name) has an invalid value"
        }
    }
}

enum CommandLineParser {
    static let usage = """
        usage: GUIProbeMac survey --output-directory DIR --output-name NAME.json --mapping-directory DIR \
        --time-budget SECONDS --operator-displayed-view songs|recently-added CONFIRMATIONS [--source-commit HASH]
               GUIProbeMac observe --profile PROFILE.json --readings K --interval SECONDS --locale ID \
        --output FILE [--inventory-count N] CONFIRMATIONS [--source-commit HASH]
        CONFIRMATIONS: --confirm-separate-test-user --confirm-synthetic-library \
        --confirm-no-apple-account --confirm-no-cloud-library
        DIR is relative to the home directory of the process user.
        """

    private static func setConfirmation(_ option: String, in confirmations: inout Confirmations) -> Bool {
        switch option {
        case "--confirm-separate-test-user": confirmations.separateTestUser = true
        case "--confirm-synthetic-library": confirmations.syntheticLibrary = true
        case "--confirm-no-apple-account": confirmations.noAppleAccount = true
        case "--confirm-no-cloud-library": confirmations.noCloudLibrary = true
        default: return false
        }
        return true
    }

    static func parse(_ arguments: [String]) throws -> ProbeCommand {
        guard let name = arguments.first else { throw UsageError.missingCommand }
        let valueOptions: Set<String>
        switch name {
        case "survey":
            valueOptions = [
                "--output-directory", "--output-name", "--mapping-directory", "--time-budget",
                "--operator-displayed-view", "--source-commit",
            ]
        case "observe":
            valueOptions = [
                "--output", "--source-commit", "--profile", "--inventory-count", "--readings", "--interval",
                "--locale",
            ]
        default: throw UsageError.unknownCommand(name)
        }
        var values: [String: String] = [:]
        var confirmations = Confirmations()
        var seenFlags = Set<String>()
        var index = 1
        while index < arguments.count {
            let option = arguments[index]
            index += 1
            if setConfirmation(option, in: &confirmations) {
                guard seenFlags.insert(option).inserted else { throw UsageError.duplicateOption(option) }
            } else if valueOptions.contains(option) {
                guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                    throw UsageError.missingValue(option)
                }
                guard values[option] == nil else { throw UsageError.duplicateOption(option) }
                values[option] = arguments[index]
                index += 1
            } else {
                throw UsageError.unknownOption(option)
            }
        }
        func required(_ option: String) throws -> String {
            guard let value = values[option] else { throw UsageError.missingOption(option) }
            guard !value.isEmpty else { throw UsageError.invalidValue(option) }
            return value
        }
        if name == "survey" {
            func directory(_ option: String) throws -> [String] {
                do { return try SurveyPlacement.components(of: try required(option)) } catch is PlacementError {
                    throw UsageError.invalidValue(option)
                }
            }
            let outputDirectory = try directory("--output-directory")
            let mappingDirectory = try directory("--mapping-directory")
            let outputName = try required("--output-name")
            guard (try? SurveyPlacement.validateName(outputName)) != nil else {
                throw UsageError.invalidValue("--output-name")
            }
            guard let budget = Double(try required("--time-budget")), budget.isFinite, budget > 0,
                budget <= SurveyLimits.maximumTimeBudgetSeconds
            else { throw UsageError.invalidValue("--time-budget") }
            guard let view = DisplayedView(rawValue: try required("--operator-displayed-view")) else {
                throw UsageError.invalidValue("--operator-displayed-view")
            }
            return .survey(
                SurveyOptions(
                    outputDirectory: outputDirectory, outputName: outputName, mappingDirectory: mappingDirectory,
                    timeBudgetSeconds: budget, displayedView: view, confirmations: confirmations,
                    sourceCommit: values["--source-commit"]))
        }
        let output = try required("--output")
        let profile = try required("--profile")
        let locale = try required("--locale")
        guard let readings = Int(try required("--readings")), (1...1_000).contains(readings) else {
            throw UsageError.invalidValue("--readings")
        }
        guard let interval = Double(try required("--interval")), interval.isFinite, (0...3_600).contains(interval)
        else { throw UsageError.invalidValue("--interval") }
        var inventory: Int?
        if values["--inventory-count"] != nil {
            guard let count = Int(try required("--inventory-count")), count >= 0 else {
                throw UsageError.invalidValue("--inventory-count")
            }
            inventory = count
        }
        return .observe(
            ObserveOptions(
                profilePath: profile, inventoryCount: inventory, readings: readings, interval: interval,
                locale: locale, output: output, confirmations: confirmations,
                sourceCommit: values["--source-commit"]))
    }
}
