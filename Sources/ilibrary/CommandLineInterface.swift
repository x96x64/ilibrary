import CatalogCore
import Foundation

let version = "0.3.0"

enum CommandLineInterface {
    static let commands: [(name: String, summary: String)] = [
        ("export", "write a catalog from the tags of existing files"),
        ("prompt", "write instructions for completing a catalog with an AI agent or chat"),
        ("schema", "print the JSON Schema of the catalog format"),
        ("validate", "check a catalog and, optionally, its correspondence with files"),
        ("apply", "apply a catalog to files, optionally renaming them and setting their dates"),
        ("timestamps", "set file and folder dates to release dates"),
        ("import", "convert or copy downloads into a staging folder without loss"),
        ("add", "add albums to Music one at a time, in order"),
        ("rebuild", "prepare and verify the rebuilding of a library (prepare and status only)"),
        ("check", "report problems of files and compare them with the library"),
        ("doctor", "report the environment and how to fix its problems"),
    ]

    static var overview: String {
        var lines = [
            "ilibrary \(version): prepare downloaded music for a local Apple Music library", "",
            "Usage: ilibrary COMMAND [OPTIONS] [ARGUMENTS]", "", "Commands:",
        ]
        for command in commands {
            lines.append("  " + command.name.padding(toLength: 12, withPad: " ", startingAt: 0) + command.summary)
        }
        lines += [
            "", "Run 'ilibrary help COMMAND' for the options of a command.",
            "Exit status: 0 on success, 1 on a runtime failure, 2 on a usage error.",
        ]
        return lines.joined(separator: "\n")
    }

    static let syntaxes: [String: CommandSyntax] = [
        "export": ExportCommand.syntax, "prompt": PromptCommand.syntax, "schema": SchemaCommand.syntax,
        "validate": ValidateCommand.syntax, "apply": ApplyCommand.syntax, "timestamps": TimestampsCommand.syntax,
        "import": ImportCommand.syntax, "add": AddCommand.syntax, "check": CheckCommand.syntax,
        "doctor": DoctorCommand.syntax,
        "rebuild": RebuildCommand.syntax,
    ]

    static func run(_ arguments: [String], console: Console, environment: Environment) -> Int32 {
        do {
            return try dispatch(arguments, console: console, environment: environment)
        } catch let error as CommandError {
            console.error(error.message)
            return error.status
        } catch {
            console.error("\(error)")
            return 1
        }
    }

    static func dispatch(_ arguments: [String], console: Console, environment: Environment) throws -> Int32 {
        guard let command = arguments.first else {
            console.print(overview)
            return 0
        }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "--version":
            console.print("ilibrary \(version)")
            return 0
        case "--help", "-h":
            console.print(overview)
            return 0
        case "help":
            guard let topic = rest.first else {
                console.print(overview)
                return 0
            }
            guard let syntax = syntaxes[topic] else { throw CommandError.usage("no help for \(topic)") }
            console.print(topic == "rebuild" ? RebuildCommand.usage(for: rest.dropFirst().first) : syntax.usage)
            return 0
        case "rebuild":
            return try RebuildCommand.run(rest, console: console, environment: environment)
        default:
            break
        }
        if rest.contains("--help") || rest.contains("-h"), let syntax = syntaxes[command] {
            console.print(syntax.usage)
            return 0
        }
        switch command {
        case "export": return try ExportCommand.run(rest, console: console)
        case "prompt": return try PromptCommand.run(rest, console: console)
        case "schema": return try SchemaCommand.run(rest, console: console)
        case "validate": return try ValidateCommand.run(rest, console: console)
        case "apply": return try ApplyCommand.run(rest, console: console, environment: environment)
        case "timestamps": return try TimestampsCommand.run(rest, console: console, environment: environment)
        case "import": return try ImportCommand.run(rest, console: console, environment: environment)
        case "add": return try AddCommand.run(rest, console: console, environment: environment)
        case "check": return try CheckCommand.run(rest, console: console, environment: environment)
        case "doctor": return try DoctorCommand.run(rest, console: console, environment: environment)
        default:
            throw CommandError.usage("unknown command \(command)\n\n\(overview)")
        }
    }
}
