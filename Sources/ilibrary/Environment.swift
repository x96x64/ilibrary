import Foundation
import RebuildCore

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

/// The storage that holds a path, as `rebuild prepare` records and judges it. Physical disk names are not stored.
struct StorageReport: Equatable, Sendable {
    /// Where the volume is mounted, which names it in the instruction to eject it.
    var mountPoint: String
    var volumeUUID: String?
    var filesystemType: String
    var isReadOnly: Bool
    var facts: StorageFacts
}

/// Sets the modification and creation times (path, modification, creation) of an existing file with nanosecond
/// precision and returns the stored values.
typealias PreciseDateSetter =
    @Sendable (String, FileTimestamp, FileTimestamp) throws -> (modification: FileTimestamp, creation: FileTimestamp?)

/// Lossless conversion, available where AudioToolbox is (macOS).
struct Converter: Sendable {
    /// Checks that a source can be converted losslessly and describes it.
    var preflight: @Sendable (URL) throws -> LosslessSource
    /// Converts to Apple Lossless at a path that must not exist, and verifies the result.
    var convert: @Sendable (URL, URL) throws -> Void
    /// Verifies an Apple Lossless file against its source by decoded PCM.
    var verify: @Sendable (URL, URL) throws -> Void
}

/// The result of waiting for a volume to be disconnected. Only a confirmed disconnection counts as one.
enum DisconnectionCheck: Equatable, Sendable {
    case confirmed
    case stillMounted
    case unknown(String)
}

/// Platform services that commands use and tests replace.
struct Environment: Sendable {
    var timeZone: TimeZone
    /// Sets both dates of an existing path that is not a symbolic link and confirms them; nil where creation
    /// dates cannot be set.
    var setDates: (@Sendable (URL, Date) throws -> Void)?
    /// Reads the creation and modification dates without following symbolic links.
    var readDates: (@Sendable (URL) throws -> (created: Date?, modified: Date?))?
    /// The available capacity of the volume of a path, when known.
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
    /// Describes the storage of an existing path; nil where storage cannot be examined.
    var describeStorage: (@Sendable (String) throws -> StorageReport)? = Environment.systemStorageDescription
    /// The timestamp policy of the volume that holds a path, or nil when it is neither APFS nor HFS+.
    var timestampPolicy: @Sendable (String) -> TimestampPolicy? = { TimestampPolicy.forVolume(containing: $0) }
    /// Copies a regular file (source, destination, restoration root) exclusively and without its dates; nil where
    /// unavailable.
    var restoreCopy: (@Sendable (URL, URL, URL) throws -> Void)? = Environment.systemRestoreCopy
    /// Sets nanosecond-precision dates; nil where unavailable.
    var setPreciseDates: PreciseDateSetter? = Environment.systemPreciseDates
    /// Waits until the volume with a UUID is confirmed to be no longer mounted, for at most the given seconds. It
    /// never unmounts anything; nil where unavailable.
    var waitUntilUnmounted: (@Sendable (String, TimeInterval) -> DisconnectionCheck)? = Environment.systemUnmountWait
    /// The current time, and a pause of the given seconds; tests replace both with a simulated clock.
    var now: @Sendable () -> Date = { Date() }
    var pause: @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }

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

    static var systemStorageDescription: (@Sendable (String) throws -> StorageReport)? {
        #if canImport(LibraryMac) && os(macOS)
            return { path in
                let description = try StorageDevice.describe(path: path)
                return StorageReport(
                    mountPoint: description.mountPoint, volumeUUID: description.volumeUUID,
                    filesystemType: description.filesystemType, isReadOnly: description.isReadOnly,
                    facts: description.facts)
            }
        #else
            return nil
        #endif
    }

    static var systemRestoreCopy: (@Sendable (URL, URL, URL) throws -> Void)? {
        #if canImport(LibraryMac) && os(macOS)
            return { source, destination, root in _ = try RestoreCopy.copy(from: source, to: destination, below: root) }
        #else
            return nil
        #endif
    }

    static var systemPreciseDates: PreciseDateSetter? {
        #if canImport(LibraryMac) && os(macOS)
            return { path, modification, creation in
                let stored = try PreciseFileDates.set(path: path, modification: modification, creation: creation)
                return (stored.modification, stored.creation)
            }
        #else
            return nil
        #endif
    }

    static var systemUnmountWait: (@Sendable (String, TimeInterval) -> DisconnectionCheck)? {
        #if canImport(LibraryMac) && os(macOS)
            return {
                switch MountState.waitUntilUnmounted(volumeUUID: $0, timeout: $1) {
                case .unmounted: .confirmed
                case .stillMounted: .stillMounted
                case .unknown(let reason): .unknown(reason)
                }
            }
        #else
            return nil
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
