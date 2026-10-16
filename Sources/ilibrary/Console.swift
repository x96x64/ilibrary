import Foundation

#if canImport(LibraryMac)
    import LibraryMac
#endif

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

/// Platform services that commands use and tests replace.
struct Environment: Sendable {
    var timeZone: TimeZone
    /// Sets both dates of an existing path that is not a symbolic link and confirms them; nil where creation
    /// dates cannot be set.
    var setDates: (@Sendable (URL, Date) throws -> Void)?
    /// Reads the creation and modification dates without following symbolic links.
    var readDates: (@Sendable (URL) throws -> (created: Date?, modified: Date?))?
    /// The plain available capacity of the volume of a path, when known (decision 8).
    var availableCapacity: @Sendable (URL) -> Int?
    /// An identifier of the volume of a path, when known, so that paths on one volume are checked together.
    var volumeIdentifier: @Sendable (URL) -> String? = Environment.volumeIdentifier

    static var system: Environment {
        #if canImport(LibraryMac) && os(macOS)
            Environment(
                timeZone: .current, setDates: { try FileDates.set($0, to: $1) },
                readDates: { url in
                    let values = try FileDates.read(url)
                    return (values.created, values.modified)
                }, availableCapacity: plainAvailableCapacity)
        #else
            Environment(timeZone: .current, setDates: nil, readDates: nil, availableCapacity: plainAvailableCapacity)
        #endif
    }

    @Sendable static func volumeIdentifier(_ url: URL) -> String? {
        ((try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier).map { "\($0)" }
    }

    @Sendable static func plainAvailableCapacity(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity
    }
}

/// A failure that ends a command with a message and an exit status: 1 at run time, 2 for usage errors.
struct CommandError: Error, Equatable {
    var message: String
    var status: Int32

    static func usage(_ message: String) -> CommandError { CommandError(message: message, status: 2) }
    static func failure(_ message: String) -> CommandError { CommandError(message: message, status: 1) }
}
