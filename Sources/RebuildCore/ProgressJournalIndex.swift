import Foundation

/// Hashed lookups over a recovery record, built once so that the transition rules check an entry in constant
/// expected time apart from the work proportional to the content of that entry.
///
/// The index is immutable and derived entirely from the record that it was built from, so it is safe to share
/// between a replay and the journal states that follow it. It is never part of a persistent format and never
/// takes part in an equality comparison.
final class RecordIndex: Sendable {
    /// The sealed checksum of the record, which identifies the record that the index belongs to.
    let recordChecksum: String
    /// The evacuation entries by the exact source path.
    let evacuationBySourcePath: [String: EvacuationEntry]
    /// The evacuation entries by `PathKey.key` of the source path.
    let evacuationBySourceKey: [String: EvacuationEntry]
    /// The evacuation entries by the exact staging path.
    let evacuationByStagingPath: [String: EvacuationEntry]
    /// `PathKey.key` of every staging path of the evacuation plan.
    let stagingKeys: Set<String>
    /// The inventory records by `PathKey.key` of the absolute path. The first record of a key wins.
    let inventoryByKey: [String: FileRecord]
    /// The mapped persistent IDs in uppercase.
    let mappedIDs: Set<String>
    /// The position of each addition-list label. The first position of a label wins.
    let additionPositions: [String: Int]

    init(_ record: RecoveryRecord) {
        recordChecksum = record.checksum
        var bySource: [String: EvacuationEntry] = [:]
        var bySourceKey: [String: EvacuationEntry] = [:]
        var byStaging: [String: EvacuationEntry] = [:]
        var stagingKeys = Set<String>()
        bySource.reserveCapacity(record.evacuation.count)
        bySourceKey.reserveCapacity(record.evacuation.count)
        byStaging.reserveCapacity(record.evacuation.count)
        stagingKeys.reserveCapacity(record.evacuation.count)
        for entry in record.evacuation {
            if bySource[entry.sourcePath] == nil { bySource[entry.sourcePath] = entry }
            let sourceKey = PathKey.key(entry.sourcePath)
            if bySourceKey[sourceKey] == nil { bySourceKey[sourceKey] = entry }
            if byStaging[entry.stagingPath] == nil { byStaging[entry.stagingPath] = entry }
            stagingKeys.insert(PathKey.key(entry.stagingPath))
        }
        evacuationBySourcePath = bySource
        evacuationBySourceKey = bySourceKey
        evacuationByStagingPath = byStaging
        self.stagingKeys = stagingKeys

        var inventory: [String: FileRecord] = [:]
        inventory.reserveCapacity(record.inventory.count)
        for item in record.inventory {
            let key = PathKey.key(item.absolutePath)
            if inventory[key] == nil { inventory[key] = item.record }
        }
        inventoryByKey = inventory

        var ids = Set<String>()
        ids.reserveCapacity(record.mapping.count)
        for item in record.mapping { ids.insert(item.persistentID.uppercased()) }
        mappedIDs = ids

        var positions: [String: Int] = [:]
        positions.reserveCapacity(record.additionList.count)
        for (position, label) in record.additionList.enumerated() where positions[label] == nil {
            positions[label] = position
        }
        additionPositions = positions
    }
}
