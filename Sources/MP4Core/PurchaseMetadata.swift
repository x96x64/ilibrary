import Foundation

/// What was removed from a file purchased from the iTunes Store.
public struct PurchaseMetadataRemoval: Equatable, Sendable {
    public var removedItems: [MetadataKey] = []
    public var removedSampleEntryBoxes: [String] = []
    public var zeroedPaddingBytes = 0

    public var isEmpty: Bool { removedItems.isEmpty && removedSampleEntryBoxes.isEmpty }
}

extension MP4File {
    /// Item-list atoms that identify the purchaser, the purchase, or catalog entries.
    public static let purchaseItemKeys: [FourCC] = [
        "apID", "ownr", "purd", "cnID", "atID", "plID", "geID", "sfID", "cmID", "akID", "flvr", "xid ",
    ]

    /// Children of an audio sample entry that are kept. Purchased files carry further, undocumented
    /// children, such as `pinf`, `dmix`, `udi2`, `udc2`, `udex`, and `sbtd`, which are removed without
    /// having to be identified.
    public static let sampleEntryChildAllowlist: Set<FourCC> = [
        "esds", "chan", "btrt", "wave", "alac", "dfLa", "dOps", "dac3", "dec3",
    ]

    /// Sample entries whose audio is encrypted: `drms` (iTunes FairPlay) and `enca` (ISO common encryption).
    public static let encryptedSampleEntries: Set<FourCC> = ["drms", "enca"]

    /// Refuses protected audio: a `.m4p` path or an encrypted sample entry. Purchase information in
    /// files that are not encrypted, such as the `pinf` box with the `itun` scheme, is not protection.
    public func ensureNotEncrypted(path: String? = nil) throws {
        if let path, path.lowercased().hasSuffix(".m4p") { throw MP4Error.protectedFile(path: path) }
        if let entry = sampleEntries.first(where: { MP4File.encryptedSampleEntries.contains($0.type) }) {
            throw MP4Error.encrypted(sampleEntry: entry.type.description)
        }
    }

    /// Removes purchase and store metadata without changing the audio stream: the purchase atoms of the
    /// item list, every sample-entry child outside the allowlist, and the contents of all padding.
    /// `iTunSMPB`, `stik`, and descriptive items are kept.
    @discardableResult
    public mutating func removePurchaseMetadata() throws -> PurchaseMetadataRemoval {
        try ensureNotEncrypted()
        var removal = PurchaseMetadataRemoval()
        var movie = self.movie
        movie.transformDescendants { box in
            if box.type == "stsd" {
                var entries = box.children
                for index in entries.indices where MP4File.audioSampleEntries.contains(entries[index].type) {
                    let children = entries[index].children
                    let removed = children.filter { !MP4File.sampleEntryChildAllowlist.contains($0.type) }
                    removal.removedSampleEntryBoxes += removed.map { "\(entries[index].type)/\($0.type)" }
                    entries[index].children = children.filter { MP4File.sampleEntryChildAllowlist.contains($0.type) }
                }
                box.children = entries
            }
            if box.type == "free" || box.type == "skip", let payload = box.payload {
                if payload.contains(where: { $0 != 0 }) { removal.zeroedPaddingBytes += payload.count }
                box.content = .leaf(Data(count: payload.count))
            }
        }
        self.movie = movie
        for (index, box) in boxes.enumerated() where box.type == "free" || box.type == "skip" {
            guard let range = box.sourceRange else { continue }
            let payload = source.subdata(in: (range.lowerBound + box.headerSize)..<range.upperBound)
            if payload.contains(where: { $0 != 0 }) {
                removal.zeroedPaddingBytes += payload.count
                var zeroed = box
                zeroed.content = .leaf(Data(count: payload.count))
                boxes[index] = zeroed
            }
        }
        for code in MP4File.purchaseItemKeys where try removeMetadata(.atom(code)) > 0 {
            removal.removedItems.append(.atom(code))
        }
        return removal
    }
}
