import Foundation

/// Where a command writes. Reports go to standard output; errors and warnings to standard error.
final class Console: @unchecked Sendable {
    private let writeOutput: (String) -> Void
    private let writeError: (String) -> Void

    init(output: @escaping (String) -> Void, error: @escaping (String) -> Void) {
        writeOutput = output
        writeError = error
    }

    static let standard = Console(
        output: { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) },
        error: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })

    func print(_ line: String = "") { writeOutput(line) }
    func error(_ message: String) { writeError("ilibrary: error: \(message)") }
    func warning(_ message: String) { writeError("ilibrary: warning: \(message)") }
}

/// A failure that ends a command with a message and an exit status: 1 at run time, 2 for usage errors.
struct CommandError: Error, Equatable {
    var message: String
    var status: Int32

    static func usage(_ message: String) -> CommandError { CommandError(message: message, status: 2) }
    static func failure(_ message: String) -> CommandError { CommandError(message: message, status: 1) }

    static let timestampsRequireMacOS = CommandError.failure(
        "--timestamps requires macOS, where creation dates can be set; nothing was changed")
}

extension Error {
    /// The message of a `CommandError`, and the description of any other error.
    var commandMessage: String { (self as? CommandError)?.message ?? "\(self)" }
}
