import Foundation

#if canImport(LibraryMac)
    import LibraryMac
#endif
#if canImport(ConversionMac)
    import ConversionMac
#endif

/// The format of a lossless source and a bound of the size of its Apple Lossless conversion.
struct LosslessSource: Equatable, Sendable {
    var codec: String
    var sampleRate: Double
    var channels: Int
    var bits: Int
    var frames: Int64
    var estimatedSize: Int64

    var description: String {
        let codecName = ["lpcm": "PCM", "flac": "FLAC"][codec] ?? codec
        return "\(codecName) \(bits)-bit \(Int(sampleRate)) Hz \(channels == 1 ? "mono" : "stereo")"
    }
}

/// The Music app as `doctor` reports it.
struct MusicAppStatus: Sendable {
    var version: @Sendable () -> String?
    var isRunning: @Sendable () -> Bool
    /// One of `permitted`, `denied`, `not determined`, `Music not running`, and `unknown`.
    var permission: @Sendable () -> String
}

/// Lossless conversion, available where AudioToolbox is (macOS).
struct Converter: Sendable {
    /// Checks that a source can be converted losslessly (decision 7).
    var preflight: @Sendable (URL) throws -> LosslessSource
    /// Converts to Apple Lossless at a path that must not exist, and verifies the result.
    var convert: @Sendable (URL, URL) throws -> Void
    /// Verifies an Apple Lossless file against its source by decoded PCM.
    var verify: @Sendable (URL, URL) throws -> Void
}

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
    /// Conversion to Apple Lossless; nil where AudioToolbox is unavailable.
    var converter: Converter? = Environment.systemConverter
    /// Moves a file to the Trash and returns its new location; nil where there is no Trash.
    var moveToTrash: (@Sendable (URL) throws -> URL?)? = Environment.systemTrash
    /// Checks decoded duration, codec, and PCM before a cross-volume move removes its source.
    var verifyAudioCopy: (@Sendable (URL, URL) throws -> Void)? = Environment.systemAudioCopyVerification
    /// The Music library; nil where Music cannot be automated.
    var music: (any MusicLibrary)? = Environment.systemMusic
    /// The state of the Music app, read without launching it or prompting; nil where Music is unavailable.
    var musicStatus: MusicAppStatus? = Environment.systemMusicStatus

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

    static var systemConverter: Converter? {
        #if canImport(ConversionMac) && os(macOS)
            Converter(
                preflight: { url in
                    let format = try LosslessConverter.preflight(url)
                    return LosslessSource(
                        codec: format.codec, sampleRate: format.sampleRate, channels: format.channels,
                        bits: format.bitsPerSample, frames: format.declaredFrames,
                        estimatedSize: LosslessConverter.estimatedOutputSize(format))
                }, convert: { try LosslessConverter.convert($0, to: $1) },
                verify: { try LosslessConverter.verify(source: $0, output: $1) })
        #else
            nil
        #endif
    }

    static var systemAudioCopyVerification: (@Sendable (URL, URL) throws -> Void)? {
        #if canImport(ConversionMac) && os(macOS)
            return { source, output in
                let (sourceFormat, sourcePCM) = try LosslessConverter.decode(source)
                let (outputFormat, outputPCM) = try LosslessConverter.decode(output)
                guard sourceFormat == outputFormat, sourcePCM == outputPCM,
                    sourcePCM.frames > 0, sourcePCM.frames == sourceFormat.declaredFrames,
                    outputPCM.frames == outputFormat.declaredFrames
                else { throw CommandError.failure("the moved copy differs in codec, duration, or decoded PCM") }
            }
        #else
            return nil
        #endif
    }

    static var systemMusicStatus: MusicAppStatus? {
        #if canImport(LibraryMac) && os(macOS)
            MusicAppStatus(
                version: { MusicStatus.version }, isRunning: { MusicStatus.isRunning },
                permission: { MusicStatus.permission().rawValue })
        #else
            nil
        #endif
    }

    static var systemMusic: (any MusicLibrary)? {
        #if canImport(LibraryMac) && os(macOS)
            SystemMusicLibrary()
        #else
            nil
        #endif
    }

    static var systemTrash: (@Sendable (URL) throws -> URL?)? {
        #if os(macOS)
            return { url in
                var result: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                return result as URL?
            }
        #else
            return nil
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
