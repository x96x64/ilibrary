import Foundation

/// The options a command accepts.
struct CommandSyntax {
    var name: String
    var usage: String
    /// Options that take a value, with their short aliases.
    var valued: [String: [String]] = [:]
    var flags: Set<String> = []
    var positionals: ClosedRange<Int>
}

struct ParsedArguments: Equatable {
    var positionals: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []

    func value(_ name: String) -> String? { values[name] }
    func flag(_ name: String) -> Bool { flags.contains(name) }
}

extension CommandSyntax {
    /// Parses `--name value`, `--name=value`, short aliases, flags, and positionals; `--` ends the options.
    func parse(_ arguments: [String]) throws -> ParsedArguments {
        var parsed = ParsedArguments()
        var index = 0
        var optionsEnded = false
        func canonical(_ option: String) -> String? {
            if valued[option] != nil || flags.contains(option) { return option }
            return valued.first { $0.value.contains(option) }?.key
        }
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if optionsEnded || !argument.hasPrefix("-") || argument == "-" {
                parsed.positionals.append(argument)
                continue
            }
            if argument == "--" {
                optionsEnded = true
                continue
            }
            var option = argument
            var inline: String?
            if let separator = argument.firstIndex(of: "="), argument.hasPrefix("--") {
                option = String(argument[..<separator])
                inline = String(argument[argument.index(after: separator)...])
            }
            guard let name = canonical(option) else {
                throw CommandError.usage("\(self.name): unknown option \(option)\n\(usage)")
            }
            if flags.contains(name) {
                guard inline == nil else { throw CommandError.usage("\(self.name): \(option) takes no value") }
                parsed.flags.insert(name)
            } else {
                let value: String
                if let inline {
                    value = inline
                } else {
                    guard index < arguments.count else {
                        throw CommandError.usage("\(self.name): \(option) requires a value")
                    }
                    value = arguments[index]
                    index += 1
                }
                guard parsed.values[name] == nil else {
                    throw CommandError.usage("\(self.name): \(option) is given more than once")
                }
                parsed.values[name] = value
            }
        }
        guard positionals.contains(parsed.positionals.count) else {
            throw CommandError.usage("\(name): wrong number of arguments\n\(usage)")
        }
        return parsed
    }
}
