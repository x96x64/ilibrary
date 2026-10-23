import Foundation

/// A reason for which the capacity of a plan is refused.
public enum CapacityRefusal: Equatable, Sendable, CustomStringConvertible {
    case unknownVolume(location: String)
    case unknownCapacity(volume: String, location: String)
    case shortfall(volume: String, required: UInt64, available: UInt64)

    public var description: String {
        switch self {
        case .unknownVolume(let location): "the volume of the \(location) is unknown"
        case .unknownCapacity(let volume, let location):
            "the available capacity of volume \(volume) is unknown (queried at the \(location))"
        case .shortfall(let volume, let required, let available):
            "volume \(volume) needs \(required) bytes and has \(available) bytes available"
        }
    }
}

/// The requirement and the availability of one volume.
public struct VolumeAccounting: Equatable, Sendable {
    public let volume: String
    public let required: UInt64
    /// The smallest capacity reported for the locations on the volume; nil when any report was unknown.
    public let available: UInt64?
    /// The labels of the locations that contribute to the requirement.
    public let purposes: [String]
}

/// Per-volume capacity accounting for a rebuild.
public struct CapacityPlan: Equatable, Sendable {
    /// The margin required on the workspace volume for the recovery record: 64 MiB.
    public static let workspaceMargin: UInt64 = 64 * 1024 * 1024

    public let volumes: [VolumeAccounting]
    public let refusals: [CapacityRefusal]
    public var isSufficient: Bool { refusals.isEmpty }

    /// Computes the requirements: the inventory size on the restoration-test volume; the inventory size on the
    /// staging volume when it differs from the volume of any source (a cross-volume evacuation retains the source
    /// until the copy is verified), and nothing when it is the volume of every source; and `workspaceMargin` on the
    /// workspace volume. Requirements on one volume are summed. An unknown volume, or an unknown capacity on a
    /// volume with a requirement, is a refusal, as for `add`.
    ///
    /// The closures receive a location path and answer for the volume holding it. A caller whose location does not
    /// exist yet answers for its nearest existing ancestor. `availableBytes` is queried for each location that
    /// contributes to a volume; any unknown answer is a refusal, and otherwise the smallest answer applies.
    public static func evaluate(
        inventoryBytes: UInt64, locations: RebuildLocations, volumeOf: (String) -> String?,
        availableBytes: (String) -> UInt64?
    ) -> CapacityPlan {
        var refusals: [CapacityRefusal] = []
        var order: [String] = []
        var required: [String: UInt64] = [:]
        var contributors: [String: [(label: String, path: String)]] = [:]

        func add(volume: String, label: String, path: String, bytes: UInt64) {
            if required[volume] == nil { order.append(volume) }
            let (sum, overflow) = (required[volume] ?? 0).addingReportingOverflow(bytes)
            required[volume] = overflow ? UInt64.max : sum
            contributors[volume, default: []].append((label, path))
        }

        var sourceVolumes: [String] = []
        for (index, source) in locations.sources.enumerated() {
            if let volume = volumeOf(source) {
                sourceVolumes.append(volume)
            } else {
                refusals.append(.unknownVolume(location: "source root \(index + 1)"))
            }
        }
        if let volume = volumeOf(locations.restorationDirectory) {
            add(
                volume: volume, label: "restoration-test directory", path: locations.restorationDirectory,
                bytes: inventoryBytes)
        } else {
            refusals.append(.unknownVolume(location: "restoration-test directory"))
        }
        if let volume = volumeOf(locations.stagingDirectory) {
            let crossVolume = sourceVolumes.contains { $0 != volume }
            if crossVolume {
                add(
                    volume: volume, label: "staging directory", path: locations.stagingDirectory,
                    bytes: inventoryBytes)
            }
        } else {
            refusals.append(.unknownVolume(location: "staging directory"))
        }
        if let volume = volumeOf(locations.workspaceDirectory) {
            add(
                volume: volume, label: "workspace directory", path: locations.workspaceDirectory,
                bytes: workspaceMargin)
        } else {
            refusals.append(.unknownVolume(location: "workspace directory"))
        }

        var accounting: [VolumeAccounting] = []
        for volume in order {
            let need = required[volume] ?? 0
            let contributions = contributors[volume] ?? []
            var known: [UInt64] = []
            var unknown = false
            for (label, path) in contributions {
                if let bytes = availableBytes(path) {
                    known.append(bytes)
                } else {
                    unknown = true
                    refusals.append(.unknownCapacity(volume: volume, location: label))
                }
            }
            let available = unknown ? nil : known.min()
            if let available, need > available {
                refusals.append(.shortfall(volume: volume, required: need, available: available))
            }
            accounting.append(
                VolumeAccounting(
                    volume: volume, required: need, available: available, purposes: contributions.map(\.label)))
        }
        return CapacityPlan(volumes: accounting, refusals: refusals)
    }
}
