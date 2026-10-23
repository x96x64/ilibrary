import CatalogCore
import FLACCore
import Foundation
import MP4Core

/// The FLAC metadata that `import` carries into an Apple Lossless file. Only an allowlist of standard Vorbis
/// fields and the front cover are carried; every other field is dropped and only counted, because the names
/// of unknown fields may themselves identify a purchase.
struct ImportTags: Equatable {
    var items: [(key: MetadataKey, values: [MetadataValue])] = []
    /// Standard fields that are deliberately not carried, such as COMMENT, by name.
    var excludedStandardFields: [String] = []
    /// The number of fields outside the standard set; their names are not reported.
    var unknownFieldCount = 0
    /// Track or disc fields whose numbers are outside the range that MP4 stores; they are not carried.
    var invalidNumberFields: [String] = []
    var pictureCarried = false
    var picturesDropped = 0

    static func == (lhs: ImportTags, rhs: ImportTags) -> Bool {
        lhs.items.map { "\($0.key)=\($0.values)" } == rhs.items.map { "\($0.key)=\($0.values)" }
            && lhs.excludedStandardFields == rhs.excludedStandardFields
            && lhs.unknownFieldCount == rhs.unknownFieldCount
            && lhs.pictureCarried == rhs.pictureCarried && lhs.picturesDropped == rhs.picturesDropped
            && lhs.invalidNumberFields == rhs.invalidNumberFields
    }

    /// Fields carried as text items.
    static let textFields: [(field: String, aliases: [String], key: MetadataKey)] = [
        ("TITLE", [], .title), ("ARTIST", [], .artist), ("ALBUMARTIST", ["ALBUM ARTIST"], .albumArtist),
        ("ALBUM", [], .album), ("GENRE", [], .genre), ("COMPOSER", [], .composer), ("COPYRIGHT", [], .copyright),
    ]
    static let numberFields: Set<String> = [
        "DATE", "TRACKNUMBER", "TRACKTOTAL", "TOTALTRACKS", "DISCNUMBER", "DISCTOTAL", "TOTALDISCS",
    ]
    /// Standard Vorbis or common fields that are recognized but not carried.
    static let excludedFields: Set<String> = [
        "COMMENT", "DESCRIPTION", "ORGANIZATION", "PERFORMER", "ISRC", "LABEL", "LYRICS", "UNSYNCEDLYRICS", "VERSION",
        "LOCATION", "CONTACT", "LICENSE", "ENCODER", "ENCODED-BY", "ENCODEDBY",
    ]

    init(_ metadata: FLACMetadata) {
        var known: Set<String> = Set(ImportTags.numberFields)
        for field in ImportTags.textFields {
            known.insert(field.field)
            known.formUnion(field.aliases)
            let values = ([field.field] + field.aliases).flatMap { metadata.values($0) }
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            // Several values of one field, such as two ARTIST fields, are joined as they are displayed.
            if !values.isEmpty { items.append((field.key, [.text(values.joined(separator: ", "))])) }
        }
        if let date = metadata.values("DATE").first?.trimmingCharacters(in: .whitespaces), !date.isEmpty {
            items.append((.releaseDate, [.text(ReleaseDate(tagValue: date)?.tagValue ?? date)]))
        }
        // MP4 stores track and disc numbers as 16-bit values; others are not carried and are reported by name.
        var invalid: [String] = []
        func pair(_ number: String, _ totals: [String]) -> (Int, Int)? {
            guard let text = metadata.values(number).first else { return nil }
            let parts = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            let total =
                (parts.count > 1 ? Int(parts[1]) : nil)
                ?? totals.lazy.compactMap { metadata.values($0).first.flatMap { Int($0) } }.first
            guard let value = parts.first.flatMap({ Int($0) }), (1...65_535).contains(value),
                (0...65_535).contains(total ?? 0)
            else {
                invalid.append(number)
                return nil
            }
            return (value, total ?? 0)
        }
        if let (number, total) = pair("TRACKNUMBER", ["TRACKTOTAL", "TOTALTRACKS"]) {
            items.append((.trackNumber, [.pair(number: number, total: total)]))
        }
        if let (number, total) = pair("DISCNUMBER", ["DISCTOTAL", "TOTALDISCS"]) {
            items.append((.discNumber, [.pair(number: number, total: total)]))
        }
        invalidNumberFields = invalid
        let names = Set(metadata.comments.map { $0.name.uppercased() })
        excludedStandardFields = names.intersection(ImportTags.excludedFields).sorted()
        unknownFieldCount = names.subtracting(known).subtracting(ImportTags.excludedFields).count
        let front = metadata.pictures.first { $0.type == 3 }
        if let front, let format = ImageFormat(detecting: front.data) {
            items.append((.artwork, [.image(front.data, format)]))
            pictureCarried = true
        }
        picturesDropped = metadata.pictures.count - (pictureCarried ? 1 : 0)
    }

    /// The size in bytes of the front cover that conversion adds to the output.
    var coverSize: Int64 {
        items.filter { $0.key == .artwork }.flatMap(\.values).reduce(0) { total, value in
            if case .image(let data, _) = value { return total + Int64(data.count) }
            return total
        }
    }

    var summary: String {
        var parts = ["\(items.filter { $0.key != .artwork }.count) tags carried"]
        if pictureCarried { parts.append("front cover carried") }
        if !excludedStandardFields.isEmpty {
            parts.append("not carried: \(excludedStandardFields.joined(separator: ", "))")
        }
        if !invalidNumberFields.isEmpty {
            parts.append("out of range, not carried: \(invalidNumberFields.joined(separator: ", "))")
        }
        if unknownFieldCount > 0 { parts.append("\(unknownFieldCount) unknown fields dropped") }
        if picturesDropped > 0 { parts.append("\(picturesDropped) other pictures dropped") }
        return parts.joined(separator: "; ")
    }
}
