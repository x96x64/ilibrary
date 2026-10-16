// Validates private reference files with MP4Core and FLACCore. It is run by
// scripts/reference_validation/validate-private.sh on copies under reference-private/work/, and it prints
// structure, counts, and outcomes only: never a metadata value, title, name, or account detail.
//
// Usage:
//   ReferenceProbe purchase-metadata IN OUT    remove purchase metadata and write a verified copy
//   ReferenceProbe retitle IN OUT              replace the title and write a verified copy
//   ReferenceProbe flac IN                     report the FLAC stream format and metadata counts

import FLACCore
import Foundation
import MP4Core

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ReferenceProbe: \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else { fail("usage: ReferenceProbe purchase-metadata|retitle IN OUT | flac IN") }
let input = URL(fileURLWithPath: arguments[1])

do {
    switch arguments[0] {
    case "purchase-metadata", "retitle":
        guard arguments.count == 3 else { fail("missing output path") }
        var file = try MP4File(contentsOf: input)
        print("layout: \(file.layout.map(\.description).joined(separator: " "))")
        print(
            "sample entries: \(file.sampleEntries.map { "\($0.type)(\($0.children.map(\.type.description).joined(separator: ",")))" })"
        )
        if arguments[0] == "purchase-metadata" {
            try file.ensureNotEncrypted(path: input.path)
            let removal = try file.removePurchaseMetadata()
            print("removed items: \(removal.removedItems.map(\.description).joined(separator: " "))")
            print("removed sample-entry boxes: \(removal.removedSampleEntryBoxes.joined(separator: " "))")
            print("zeroed padding bytes: \(removal.zeroedPaddingBytes)")
        } else {
            try file.setMetadata(.title, .text("Private Reference Title"))
        }
        let report = try MP4Writer.write(file, to: URL(fileURLWithPath: arguments[2]))
        print(
            "written: movie \(report.originalMovieSize) -> \(report.movieSize) bytes; "
                + "\(report.relocatedChunkOffsets) chunk offsets relocated; padding absorbed: \(report.absorbedIntoPadding)"
        )
        let written = try MP4File(contentsOf: URL(fileURLWithPath: arguments[2]))
        print("retained items: \(written.metadata.map(\.key.description).joined(separator: " "))")
        print(
            "stream differences from the source: \(written.streamDifferences(from: try MP4File(contentsOf: input)).count)"
        )
    case "flac":
        let metadata = try FLACMetadata(contentsOf: input)
        let information = metadata.streamInformation
        print(
            "stream: \(information.sampleRate) Hz, \(information.channels) channels, \(information.bitsPerSample) bits, "
                + "\(information.totalFrames) frames")
        // Field names outside the common set may themselves identify a purchase; only their number is printed.
        let common: Set<String> = [
            "ALBUM", "ALBUMARTIST", "ARTIST", "COMMENT", "COMPOSER", "COPYRIGHT", "DATE", "DISCNUMBER", "DISCTOTAL",
            "GENRE", "ISRC", "LABEL", "ORGANIZATION", "PERFORMER", "TITLE", "TRACKNUMBER", "TRACKTOTAL",
        ]
        let names = Set(metadata.comments.map { $0.name.uppercased() })
        print(
            "comments: \(metadata.comments.count); common fields: \(names.intersection(common).sorted().joined(separator: " ")); "
                + "other field names: \(names.subtracting(common).count)")
        print("pictures: \(metadata.pictures.map { "type \($0.type) \($0.mimeType) \($0.data.count) bytes" })")
        print("other blocks: \(metadata.otherBlocks.map { "\($0.type)" }.joined(separator: " "))")
    default:
        fail("unknown command \(arguments[0])")
    }
} catch {
    fail("\(error)")
}
