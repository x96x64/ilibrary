// M1 spikes S1 and S5: MP4 box parsing, item-list rewriting, chunk-offset relocation, and removal of
// iTunes Store purchase metadata without re-encoding. Foundation only; this is exploratory code that
// informs MP4Core and is not a production implementation.
//
// Usage:
//   mp4-spike dump FILE
//   mp4-spike chunks FILE              chunk offsets relative to the containing media-data payload
//   mp4-spike mdat FILE                payload offset and length of each media-data box
//   mp4-spike tag IN OUT [--set KEY=VALUE]... [--remove KEY]... [--track N/T] [--disc N/T]
//                        [--cover FILE] [--padding absorb|relocate] [--force-co64]
//   mp4-spike inject-store IN OUT      add synthetic placeholders of store metadata (test input only)
//   mp4-spike strip-store IN OUT       remove purchase and store metadata

import Foundation

enum MP4Error: Error, CustomStringConvertible {
    case malformed(String)
    case unsupported(String)
    var description: String {
        switch self {
        case .malformed(let message): "malformed file: \(message)"
        case .unsupported(let message): "unsupported: \(message)"
        }
    }
}

func fourCC(_ data: Data, _ offset: Int) -> String {
    String(bytes: data[offset..<offset + 4], encoding: .isoLatin1)!
}

func fourCCBytes(_ type: String) -> Data {
    let bytes = type.data(using: .isoLatin1)!
    precondition(bytes.count == 4, "four-character code \(type)")
    return bytes
}

func readUInt(_ data: Data, _ offset: Int, _ width: Int) -> UInt64 {
    var value: UInt64 = 0
    for index in 0..<width { value = value << 8 | UInt64(data[offset + index]) }
    return value
}

extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}

final class Box {
    var type: String
    /// For containers, the bytes between the header and the first child; for leaves, the payload.
    var prefix: Data
    var children: [Box]?
    /// Bytes after the last child that do not form a box, such as the QuickTime `udta` terminator.
    var trailer = Data()
    /// The original absolute range including the header, when the box was read from a file.
    let source: Range<Int>?
    let usedLargeSize: Bool
    /// True when the payload has not been loaded; the box is copied from `source` when written.
    let isReference: Bool

    init(type: String, prefix: Data = Data(), children: [Box]? = nil) {
        self.type = type
        self.prefix = prefix
        self.children = children
        source = nil
        usedLargeSize = false
        isReference = false
    }

    init(type: String, prefix: Data, children: [Box]?, source: Range<Int>, largeSize: Bool, reference: Bool) {
        self.type = type
        self.prefix = prefix
        self.children = children
        self.source = source
        usedLargeSize = largeSize
        isReference = reference
    }

    func child(_ type: String) -> Box? { children?.first { $0.type == type } }

    func descendants(_ type: String) -> [Box] {
        var found: [Box] = []
        for child in children ?? [] {
            if child.type == type { found.append(child) }
            found += child.descendants(type)
        }
        return found
    }

    var payloadSize: Int { prefix.count + (children ?? []).reduce(0) { $0 + $1.serializedSize } + trailer.count }
    var headerSize: Int { usedLargeSize || payloadSize + 8 > Int(UInt32.max) ? 16 : 8 }
    var serializedSize: Int {
        if isReference, let source { return source.count }
        return headerSize + payloadSize
    }

    func serialize(into output: inout Data) {
        precondition(!isReference, "reference boxes are copied from their source")
        if headerSize == 16 {
            output.appendBE(UInt32(1))
            output.append(fourCCBytes(type))
            output.appendBE(UInt64(serializedSize))
        } else {
            output.appendBE(UInt32(serializedSize))
            output.append(fourCCBytes(type))
        }
        output.append(prefix)
        for child in children ?? [] { child.serialize(into: &output) }
        output.append(trailer)
    }
}

let plainContainers: Set<String> = [
    "moov", "trak", "mdia", "minf", "stbl", "udta", "edts", "dinf", "ilst", "sinf", "pinf", "schi", "wave", "tref",
]
let audioSampleEntries: Set<String> = [
    "mp4a", "alac", "drms", "enca", "ac-3", "ec-3", "fLaC", "Opus", "lpcm", "sowt", "twos", "in24",
]

/// Returns the length of the non-box prefix of a container, or nil for a leaf box.
func containerPrefix(type: String, parent: String?, data: Data, payload: Range<Int>) -> Int? {
    if plainContainers.contains(type) { return 0 }
    if parent == "ilst" { return 0 }
    switch type {
    case "meta":
        // ISO full box (version and flags before children) or QuickTime atom (children directly).
        if payload.count >= 12, fourCC(data, payload.lowerBound + 4) == "hdlr" { return 0 }
        return 4
    case "stsd":
        return 8
    default:
        break
    }
    if parent == "stsd", audioSampleEntries.contains(type), payload.count >= 28 {
        let version = readUInt(data, payload.lowerBound + 8, 2)
        return 28 + (version == 1 ? 16 : version == 2 ? 36 : 0)
    }
    return nil
}

func parseBoxes(_ data: Data, _ range: Range<Int>, parent: String?, topLevel: Bool) throws -> ([Box], Data) {
    var boxes: [Box] = []
    var offset = range.lowerBound
    while offset < range.upperBound {
        let remaining = range.upperBound - offset
        if remaining < 8 {
            let tail = Data(data[offset..<range.upperBound])
            guard tail.allSatisfy({ $0 == 0 }) else {
                throw MP4Error.malformed("trailing bytes in \(parent ?? "file")")
            }
            return (boxes, tail)
        }
        var size = Int(readUInt(data, offset, 4))
        let type = fourCC(data, offset + 4)
        var header = 8
        var largeSize = false
        if size == 1 {
            guard remaining >= 16 else { throw MP4Error.malformed("truncated large size of \(type)") }
            size = Int(readUInt(data, offset + 8, 8))
            header = 16
            largeSize = true
        } else if size == 0 {
            size = remaining
        }
        guard size >= header, size <= remaining else {
            throw MP4Error.malformed("box \(type) at \(offset) declares \(size) bytes; \(remaining) remain")
        }
        let payload = (offset + header)..<(offset + size)
        let source = offset..<(offset + size)
        if topLevel && type != "moov" {
            boxes.append(
                Box(type: type, prefix: Data(), children: nil, source: source, largeSize: largeSize, reference: true))
        } else if let prefixLength = containerPrefix(type: type, parent: parent, data: data, payload: payload),
            prefixLength <= payload.count
        {
            let prefixRange = payload.lowerBound..<(payload.lowerBound + prefixLength)
            let (children, trailer) = try parseBoxes(
                data, prefixRange.upperBound..<payload.upperBound, parent: type, topLevel: false)
            let box = Box(
                type: type, prefix: Data(data[prefixRange]), children: children, source: source, largeSize: largeSize,
                reference: false)
            box.trailer = trailer
            boxes.append(box)
        } else {
            boxes.append(
                Box(
                    type: type, prefix: Data(data[payload]), children: nil, source: source, largeSize: largeSize,
                    reference: false))
        }
        offset += size
    }
    return (boxes, Data())
}

final class MP4File {
    let data: Data
    var boxes: [Box]

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .alwaysMapped)
        boxes = try parseBoxes(data, 0..<data.count, parent: nil, topLevel: true).0
        guard boxes.first?.type == "ftyp" else { throw MP4Error.malformed("the file does not begin with ftyp") }
        guard boxes.contains(where: { $0.type == "moov" }) else { throw MP4Error.malformed("no moov box") }
    }

    var moov: Box { boxes.first { $0.type == "moov" }! }
    var moovBeforeMediaData: Bool {
        let types = boxes.map(\.type)
        return types.firstIndex(of: "moov")! < (types.firstIndex(of: "mdat") ?? Int.max)
    }

    func itemList(create: Bool) -> Box? {
        if let ilst = moov.child("udta")?.child("meta")?.child("ilst") { return ilst }
        guard create else { return nil }
        let udta =
            moov.child("udta")
            ?? {
                let box = Box(type: "udta", children: [])
                moov.children!.append(box)
                return box
            }()
        let meta =
            udta.child("meta")
            ?? {
                var handler = Data(count: 8)
                handler.append(fourCCBytes("mdir"))
                handler.append(fourCCBytes("appl"))
                handler.append(Data(count: 10))
                let box = Box(type: "meta", prefix: Data(count: 4), children: [Box(type: "hdlr", prefix: handler)])
                udta.children!.append(box)
                return box
            }()
        let ilst = Box(type: "ilst", children: [])
        if let index = meta.children!.firstIndex(where: { $0.type == "free" }) {
            meta.children!.insert(ilst, at: index)
        } else {
            meta.children!.append(ilst)
        }
        return ilst
    }

    /// Writes the file with the modified movie box, relocating chunk offsets that follow it.
    func write(to url: URL, padding: String, forceCo64: Bool) throws -> String {
        let originalMoovSize = moov.source!.count
        let originalRanges = boxes.map { $0.source! }
        var report: [String] = []

        if forceCo64 {
            for stco in moov.descendants("stco") {
                let count = Int(readUInt(stco.prefix, 4, 4))
                var payload = Data(stco.prefix[0..<8])
                for index in 0..<count { payload.appendBE(readUInt(stco.prefix, 8 + 4 * index, 4)) }
                stco.type = "co64"
                stco.prefix = payload
            }
            report.append("converted stco to co64")
        }

        // Absorb the size change into adjacent padding when requested and possible.
        if padding == "absorb" {
            let delta = moov.serializedSize - originalMoovSize
            let candidates = (moov.child("udta")?.child("meta")?.children ?? []) + (moov.child("udta")?.children ?? [])
            let moovIndex = boxes.firstIndex { $0.type == "moov" }!
            let following = moovIndex + 1 < boxes.count ? boxes[moovIndex + 1] : nil
            if delta != 0, let free = candidates.first(where: { $0.type == "free" }), free.prefix.count - delta >= 0 {
                free.prefix = Data(count: free.prefix.count - delta)
                report.append("absorbed \(delta) bytes into free padding inside moov")
            } else if delta != 0, let following, following.type == "free", !following.usedLargeSize,
                following.source!.count - 8 - delta >= 0
            {
                // Replace the top-level padding after moov with a smaller one; offsets after it are unchanged.
                boxes[moovIndex + 1] = Box(type: "free", prefix: Data(count: following.source!.count - 8 - delta))
                report.append("absorbed \(delta) bytes into top-level free padding")
            } else if delta != 0 {
                report.append("no padding could absorb \(delta) bytes; relocating")
            }
        }

        // Map each original absolute offset to its new position through the top-level layout.
        for _ in 0..<3 {
            var newStarts: [Int] = []
            var position = 0
            for box in boxes {
                newStarts.append(position)
                position += box.serializedSize
            }
            func relocate(_ offset: UInt64) throws -> UInt64 {
                for (index, box) in boxes.enumerated() {
                    let source = originalRanges[index]
                    if source.contains(Int(offset)) {
                        guard box.isReference else {
                            throw MP4Error.unsupported("chunk offset \(offset) points into a rewritten \(box.type) box")
                        }
                        return UInt64(newStarts[index] + Int(offset) - source.lowerBound)
                    }
                }
                throw MP4Error.malformed("chunk offset \(offset) lies outside the file")
            }
            var needsUpgrade = false
            var relocated = 0
            for table in moov.descendants("stco") + moov.descendants("co64") {
                let width = table.type == "co64" ? 8 : 4
                let originalTable = originalChunkTable(table)
                for (index, offset) in originalTable.enumerated() {
                    let moved = try relocate(offset)
                    if moved != offset { relocated += 1 }
                    if width == 4 && moved > UInt64(UInt32.max) { needsUpgrade = true }
                    let position = 8 + width * index
                    var bytes = Data()
                    if width == 4 { bytes.appendBE(UInt32(truncatingIfNeeded: moved)) } else { bytes.appendBE(moved) }
                    table.prefix.replaceSubrange(position..<position + width, with: bytes)
                }
            }
            if !needsUpgrade {
                report.append(
                    "moov \(originalMoovSize) -> \(moov.serializedSize) bytes; \(relocated) chunk offsets changed")
                break
            }
            throw MP4Error.unsupported(
                "chunk offsets exceed 32 bits; co64 upgrade during relocation is not implemented")
        }

        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).partial")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)
        for box in boxes {
            if box.isReference {
                var start = box.source!.lowerBound
                while start < box.source!.upperBound {
                    let end = min(start + 8 << 20, box.source!.upperBound)
                    try handle.write(contentsOf: data[start..<end])
                    start = end
                }
            } else {
                var bytes = Data()
                box.serialize(into: &bytes)
                try handle.write(contentsOf: bytes)
            }
        }
        try handle.synchronize()
        try handle.close()
        // Verify by parsing the written file before it replaces the destination.
        _ = try MP4File(url: temporary)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.moveItem(at: temporary, to: url)
        return report.joined(separator: "; ")
    }

    func originalChunkTable(_ table: Box) -> [UInt64] {
        // The table's prefix still holds the source values until it is rewritten; read from the source.
        let source = table.source!
        let payload = data[(source.lowerBound + 8)..<source.upperBound]
        let base = payload.startIndex
        let width = fourCC(data, source.lowerBound + 4) == "co64" ? 8 : 4
        let count = Int(readUInt(data, base + 4, 4))
        return (0..<count).map { readUInt(data, base + 8 + width * $0, width) }
    }
}

// MARK: - Item list values

enum ItemValue {
    case text(String)
    case integer(Int64, width: Int)
    case pair(Int, Int, width: Int)
    case image(Data, type: UInt32)

    func dataBox() -> Box {
        var payload = Data()
        switch self {
        case .text(let string):
            payload.appendBE(UInt32(1))
            payload.appendBE(UInt32(0))
            payload.append(Data(string.utf8))
        case .integer(let value, let width):
            payload.appendBE(UInt32(21))
            payload.appendBE(UInt32(0))
            for shift in stride(from: (width - 1) * 8, through: 0, by: -8) {
                payload.append(UInt8(truncatingIfNeeded: value >> Int64(shift)))
            }
        case .pair(let number, let total, let width):
            payload.appendBE(UInt32(0))
            payload.appendBE(UInt32(0))
            payload.appendBE(UInt16(0))
            payload.appendBE(UInt16(number))
            payload.appendBE(UInt16(total))
            if width == 8 { payload.appendBE(UInt16(0)) }
        case .image(let data, let type):
            payload.appendBE(type)
            payload.appendBE(UInt32(0))
            payload.append(data)
        }
        return Box(type: "data", prefix: payload)
    }
}

func describeItem(_ item: Box) -> String {
    var key = item.type
    if item.type == "----" {
        let mean = item.child("mean").map { String(decoding: $0.prefix.dropFirst(4), as: UTF8.self) } ?? "?"
        let name = item.child("name").map { String(decoding: $0.prefix.dropFirst(4), as: UTF8.self) } ?? "?"
        key = "----:\(mean):\(name)"
    }
    let values = (item.children ?? []).filter { $0.type == "data" }.map { box -> String in
        let payload = box.prefix
        guard payload.count >= 8 else { return "<short data>" }
        let type = readUInt(payload, 0, 4)
        let body = payload.dropFirst(8)
        switch type {
        case 1: return "\"\(String(decoding: body, as: UTF8.self))\""
        case 13, 14: return "image(\(type == 13 ? "JPEG" : "PNG"), \(body.count) bytes)"
        case 21: return body.isEmpty ? "int()" : "int(\(body.reduce(Int64(0)) { $0 << 8 | Int64($1) }))"
        case 0 where body.count >= 6:
            let bytes = Data(body)
            return "\(readUInt(bytes, 2, 2))/\(readUInt(bytes, 4, 2))"
        default: return "type \(type), \(body.count) bytes"
        }
    }
    return "\(key) = \(values.joined(separator: ", "))"
}

func dump(_ file: MP4File) {
    print("layout: \(file.boxes.map(\.type).joined(separator: " ")); moov before mdat: \(file.moovBeforeMediaData)")
    func visit(_ box: Box, depth: Int) {
        let location = box.source.map { "@\($0.lowerBound) size \($0.count)" } ?? "(new)"
        var line = String(repeating: "  ", count: depth) + "\(box.type) \(location)"
        if box.type == "stco" || box.type == "co64" {
            let count = readUInt(box.prefix, 4, 4)
            line += " entries \(count)"
        }
        if box.type == "stsd" { line += " entries \(readUInt(box.prefix, 4, 4))" }
        print(line)
        if box.type == "ilst" {
            for item in box.children ?? [] { print(String(repeating: "  ", count: depth + 1) + describeItem(item)) }
            return
        }
        for child in box.children ?? [] { visit(child, depth: depth + 1) }
    }
    for box in file.boxes { visit(box, depth: 0) }
}

func chunkReport(_ file: MP4File) throws {
    let mediaData = file.boxes.filter { $0.type == "mdat" }
    for (trackIndex, trak) in file.moov.descendants("trak").enumerated() {
        for table in trak.descendants("stco") + trak.descendants("co64") {
            for offset in file.originalChunkTable(table) {
                guard let index = mediaData.firstIndex(where: { $0.source!.contains(Int(offset)) }) else {
                    throw MP4Error.malformed("chunk offset \(offset) is outside every mdat box")
                }
                let source = mediaData[index].source!
                let header = mediaData[index].usedLargeSize ? 16 : 8
                print("track \(trackIndex) mdat \(index) +\(Int(offset) - source.lowerBound - header)")
            }
        }
    }
}

// MARK: - Store metadata

/// Item-list keys that identify the purchaser, the purchase, or catalog entries in the iTunes Store.
let storeItemKeys: Set<String> = [
    "apID", "ownr", "purd", "cnID", "atID", "plID", "geID", "sfID", "cmID", "akID", "flvr", "xid ",
]

/// Child boxes of an audio sample entry that decoding requires or that describe the stream.
/// Purchased files carry further, undocumented children (observed: dmix, udi2, udc2, udex, sbtd)
/// whose contents are unknown; an allowlist removes them without having to identify them.
let sampleEntryChildren: Set<String> = ["esds", "chan", "btrt", "wave", "alac", "dfLa", "dOps", "dac3", "dec3"]

func stripStore(_ file: MP4File) throws -> [String] {
    var removed: [String] = []
    for entry in file.moov.descendants("stsd").flatMap({ $0.children ?? [] }) {
        if entry.type == "drms" || entry.child("sinf") != nil {
            throw MP4Error.unsupported("protected sample entry \(entry.type); protected audio is out of scope")
        }
        guard let children = entry.children else { continue }
        removed += children.filter { !sampleEntryChildren.contains($0.type) }.map { "\(entry.type)/\($0.type)" }
        entry.children = children.filter { sampleEntryChildren.contains($0.type) }
    }
    if let ilst = file.itemList(create: false) {
        let before = ilst.children!.map(\.type)
        ilst.children!.removeAll { storeItemKeys.contains($0.type) }
        removed += before.filter { storeItemKeys.contains($0) }
    }
    // Erase residual bytes in padding, where earlier tools may have left superseded metadata.
    for free in file.moov.descendants("free") + file.moov.descendants("skip") {
        free.prefix = Data(count: free.prefix.count)
    }
    for (index, box) in file.boxes.enumerated() where box.type == "free" || box.type == "skip" {
        let source = box.source!
        file.boxes[index] = Box(
            type: box.type, prefix: Data(count: source.count - (box.usedLargeSize ? 16 : 8)), children: nil,
            source: source, largeSize: box.usedLargeSize, reference: false)
    }
    return removed
}

func box(_ type: String, _ payload: Data = Data(), _ children: [Box]? = nil) -> Box {
    Box(type: type, prefix: payload, children: children)
}

func injectStore(_ file: MP4File) throws {
    let ilst = file.itemList(create: true)!
    let placeholders: [(String, ItemValue)] = [
        ("apID", .text("synthetic.purchaser@example.invalid")),
        ("ownr", .text("Synthetic Purchaser")),
        ("purd", .text("2026-10-16 00:00:00")),
        ("cnID", .integer(100_000_001, width: 4)),
        ("atID", .integer(100_000_002, width: 4)),
        ("plID", .integer(100_000_003, width: 8)),
        ("geID", .integer(100_000_004, width: 4)),
        ("sfID", .integer(143_462, width: 4)),
        ("cmID", .integer(100_000_005, width: 4)),
        ("akID", .integer(0, width: 1)),
        ("flvr", .text("2:256")),
        ("xid ", .text("Synthetic:isrc:ZZ0000000000")),
        ("stik", .integer(1, width: 1)),
    ]
    for (key, value) in placeholders {
        ilst.children!.append(box(key, Data(), [value.dataBox()]))
    }
    guard let entry = file.moov.descendants("stsd").first?.children?.first, entry.type == "mp4a" else {
        throw MP4Error.unsupported("synthetic purchase information requires an mp4a sample entry")
    }
    var generator = SystemRandomNumberGenerator()
    func random(_ count: Int) -> Data { Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) }) }
    var scheme = Data(count: 4)
    scheme.append(fourCCBytes("itun"))
    scheme.appendBE(UInt32(0))
    var name = Data("Synthetic Purchaser".utf8)
    name.append(Data(count: 256 - name.count))
    let information = box(
        "pinf", Data(),
        [
            box("frma", fourCCBytes("mp4a")),
            box("schm", scheme),
            box(
                "schi", Data(),
                [
                    box("user", random(4)), box("key ", random(4)), box("iviv", random(16)),
                    box("righ", random(80)), box("name", name), box("priv", random(440)),
                ]),
        ])
    entry.children!.append(information)
    // Residual padding that carries a superseded account string, as some editors leave behind.
    var stale = Data("synthetic.purchaser@example.invalid".utf8)
    stale.append(Data(count: 64))
    file.moov.child("udta")!.children!.append(box("free", stale))
}

// MARK: - Command line

func fail(_ message: String, status: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("mp4-spike: \(message)\n".utf8))
    exit(status)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first, arguments.count >= 2 else {
    fail("usage: mp4-spike dump|chunks|mdat|tag|inject-store|strip-store FILE [OUT] [options]", status: 2)
}
do {
    let input = URL(fileURLWithPath: arguments[1])
    let file = try MP4File(url: input)
    switch command {
    case "dump":
        dump(file)
    case "chunks":
        try chunkReport(file)
    case "mdat":
        for box in file.boxes where box.type == "mdat" {
            let header = box.usedLargeSize ? 16 : 8
            print("\(box.source!.lowerBound + header) \(box.source!.count - header)")
        }
    case "tag", "inject-store", "strip-store":
        guard arguments.count >= 3 else { fail("missing output path", status: 2) }
        let output = URL(fileURLWithPath: arguments[2])
        var padding = "relocate"
        var forceCo64 = false
        if command == "inject-store" {
            try injectStore(file)
        } else if command == "strip-store" {
            print("removed: \(try stripStore(file).joined(separator: " "))")
        } else {
            let ilst = file.itemList(create: true)!
            var options = Array(arguments.dropFirst(3))
            func set(_ key: String, _ value: ItemValue) {
                // Replace in place so that repeated application preserves item order and bytes.
                let item = box(key, Data(), [value.dataBox()])
                if let index = ilst.children!.firstIndex(where: { $0.type == key }) {
                    ilst.children![index] = item
                    ilst.children!.removeAll { $0.type == key && $0 !== item }
                } else {
                    ilst.children!.append(item)
                }
            }
            func pair(_ text: String) -> (Int, Int) {
                let parts = text.split(separator: "/").compactMap { Int($0) }
                guard parts.count == 2 else { fail("expected N/T, not \(text)", status: 2) }
                return (parts[0], parts[1])
            }
            while !options.isEmpty {
                let option = options.removeFirst()
                guard !options.isEmpty else { fail("missing value for \(option)", status: 2) }
                let value = options.removeFirst()
                switch option {
                case "--set":
                    guard let separator = value.firstIndex(of: "=") else { fail("expected KEY=VALUE", status: 2) }
                    set(String(value[..<separator]), .text(String(value[value.index(after: separator)...])))
                case "--remove":
                    ilst.children!.removeAll { $0.type == value }
                case "--track":
                    let (number, total) = pair(value)
                    set("trkn", .pair(number, total, width: 8))
                case "--disc":
                    let (number, total) = pair(value)
                    set("disk", .pair(number, total, width: 6))
                case "--cover":
                    let image = try Data(contentsOf: URL(fileURLWithPath: value))
                    let isPNG = image.starts(with: [0x89, 0x50, 0x4E, 0x47])
                    set("covr", .image(image, type: isPNG ? 14 : 13))
                case "--padding":
                    padding = value
                case "--force-co64":
                    forceCo64 = value == "yes"
                default:
                    fail("unknown option \(option)", status: 2)
                }
            }
        }
        print(try file.write(to: output, padding: padding, forceCo64: forceCo64))
    default:
        fail("unknown command \(command)", status: 2)
    }
} catch {
    fail("\(error)")
}
