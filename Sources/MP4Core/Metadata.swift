import Foundation

/// The key of an item in the iTunes-style item list (`moov/udta/meta/ilst`).
public enum MetadataKey: Hashable, Sendable, CustomStringConvertible {
    case atom(FourCC)
    /// A `----` item identified by its `mean` and `name`, such as `com.apple.iTunes` and `iTunSMPB`.
    case freeform(mean: String, name: String)

    public static let title = MetadataKey.atom("©nam")
    public static let artist = MetadataKey.atom("©ART")
    public static let albumArtist = MetadataKey.atom("aART")
    public static let album = MetadataKey.atom("©alb")
    public static let genre = MetadataKey.atom("©gen")
    public static let composer = MetadataKey.atom("©wrt")
    public static let copyright = MetadataKey.atom("cprt")
    public static let releaseDate = MetadataKey.atom("©day")
    public static let comment = MetadataKey.atom("©cmt")
    public static let trackNumber = MetadataKey.atom("trkn")
    public static let discNumber = MetadataKey.atom("disk")
    public static let compilation = MetadataKey.atom("cpil")
    public static let artwork = MetadataKey.atom("covr")
    public static let gaplessInformation = MetadataKey.freeform(mean: "com.apple.iTunes", name: "iTunSMPB")

    public var description: String {
        switch self {
        case .atom(let code): code.description
        case .freeform(let mean, let name): "----:\(mean):\(name)"
        }
    }
}

public enum ImageFormat: UInt32, Sendable {
    case jpeg = 13
    case png = 14

    public init?(detecting data: Data) {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            self = .png
        } else if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            self = .jpeg
        } else {
            return nil
        }
    }
}

/// The value of one `data` box of an item.
public enum MetadataValue: Equatable, Sendable {
    case text(String)
    case integer(Int64)
    /// A track or disc number and the total, as stored in `trkn` and `disk`.
    case pair(number: Int, total: Int)
    case image(Data, ImageFormat)
    /// Any other well-known type, kept as it was read.
    case other(type: UInt32, Data)
}

public struct MetadataItem: Equatable, Sendable {
    public var key: MetadataKey
    public var values: [MetadataValue]

    public init(key: MetadataKey, values: [MetadataValue]) {
        self.key = key
        self.values = values
    }
}

extension MetadataValue {
    /// Integer widths in bytes used by the iTunes Store and Music for well-known keys.
    static let integerWidths: [FourCC: Int] = [
        "cpil": 1, "pgap": 1, "stik": 1, "rtng": 1, "akID": 1, "tmpo": 2, "plID": 8,
        "cnID": 4, "atID": 4, "geID": 4, "sfID": 4, "cmID": 4,
    ]

    init(dataBox payload: Data) {
        guard payload.count >= 8 else {
            self = .other(type: 0, payload)
            return
        }
        let type = UInt32(payload.bigEndianInteger(at: 0, width: 4))
        let body = payload.subdata(in: (payload.startIndex + 8)..<payload.endIndex)
        switch type {
        case 1:
            self = String(data: body, encoding: .utf8).map(MetadataValue.text) ?? .other(type: type, body)
        case 2:
            self = String(data: body, encoding: .utf16BigEndian).map(MetadataValue.text) ?? .other(type: type, body)
        case 13, 14:
            self = .image(body, ImageFormat(rawValue: type)!)
        case 21 where (1...8).contains(body.count):
            let unsigned = body.bigEndianInteger(at: 0, width: body.count)
            let shift = UInt64(64 - 8 * body.count)
            self = .integer(Int64(bitPattern: unsigned << shift) >> Int64(shift))
        case 0 where body.count == 6 || body.count == 8:
            self = .pair(
                number: Int(body.bigEndianInteger(at: 2, width: 2)), total: Int(body.bigEndianInteger(at: 4, width: 2)))
        default:
            self = .other(type: type, body)
        }
    }

    func dataBox(for key: MetadataKey) throws -> MP4Box {
        var payload = Data()
        func header(_ type: UInt32) {
            payload.appendBigEndian(type)
            payload.appendBigEndian(UInt32(0))
        }
        switch self {
        case .text(let text):
            header(1)
            payload.append(Data(text.utf8))
        case .integer(let value):
            var width = 4
            if case .atom(let code) = key, let known = MetadataValue.integerWidths[code] { width = known }
            let limit = width == 8 ? Int64.max : (Int64(1) << (8 * width - 1)) - 1
            guard value <= limit, value >= -limit - 1 else {
                throw MP4Error.invalidValue(key: key.description, reason: "\(value) does not fit in \(width) bytes")
            }
            header(21)
            payload.appendBigEndian(UInt64(bitPattern: value), width: width)
        case .pair(let number, let total):
            guard (0...Int(UInt16.max)).contains(number), (0...Int(UInt16.max)).contains(total) else {
                throw MP4Error.invalidValue(key: key.description, reason: "\(number)/\(total) is out of range")
            }
            header(0)
            payload.appendBigEndian(UInt16(0))
            payload.appendBigEndian(UInt16(number))
            payload.appendBigEndian(UInt16(total))
            // Track numbers carry two further reserved bytes; disc numbers do not.
            if key == .trackNumber { payload.appendBigEndian(UInt16(0)) }
        case .image(let data, let format):
            header(format.rawValue)
            payload.append(data)
        case .other(let type, let data):
            header(type)
            payload.append(data)
        }
        return MP4Box(type: "data", payload: payload)
    }
}

extension MP4File {
    /// The items of the item list, in file order. Empty when the file has no item list.
    public var metadata: [MetadataItem] {
        guard let list = movie.child("udta")?.child("meta")?.child("ilst") else { return [] }
        return list.children.map(MP4File.item(from:))
    }

    public func metadataValues(_ key: MetadataKey) -> [MetadataValue] {
        metadata.first { $0.key == key }?.values ?? []
    }

    static func item(from box: MP4Box) -> MetadataItem {
        MetadataItem(
            key: key(of: box),
            values: box.children.filter { $0.type == "data" }.map { MetadataValue(dataBox: $0.payload ?? Data()) })
    }

    static func key(of box: MP4Box) -> MetadataKey {
        guard box.type == "----" else { return .atom(box.type) }
        func text(_ type: FourCC) -> String {
            guard let payload = box.child(type)?.payload, payload.count >= 4 else { return "" }
            return String(decoding: payload.dropFirst(4), as: UTF8.self)
        }
        return .freeform(mean: text("mean"), name: text("name"))
    }

    static func itemBox(_ key: MetadataKey, _ values: [MetadataValue]) throws -> MP4Box {
        let data = try values.map { try $0.dataBox(for: key) }
        switch key {
        case .atom(let code):
            return MP4Box(type: code, children: data)
        case .freeform(let mean, let name):
            var meanPayload = Data(count: 4)
            meanPayload.append(Data(mean.utf8))
            var namePayload = Data(count: 4)
            namePayload.append(Data(name.utf8))
            return MP4Box(
                type: "----",
                children: [MP4Box(type: "mean", payload: meanPayload), MP4Box(type: "name", payload: namePayload)]
                    + data)
        }
    }

    /// Sets an item. An existing item is replaced in place, so that repeated application yields identical bytes.
    public mutating func setMetadata(_ key: MetadataKey, _ values: [MetadataValue]) throws {
        let item = try MP4File.itemBox(key, values)
        try modifyItemList(create: true) { children in
            if let index = children.firstIndex(where: { MP4File.key(of: $0) == key }) {
                children[index] = item
                var seen = false
                children.removeAll { box in
                    guard MP4File.key(of: box) == key else { return false }
                    defer { seen = true }
                    return seen
                }
            } else {
                children.append(item)
            }
        }
    }

    public mutating func setMetadata(_ key: MetadataKey, _ value: MetadataValue) throws {
        try setMetadata(key, [value])
    }

    /// Removes every item with the key and returns the number removed.
    @discardableResult
    public mutating func removeMetadata(_ key: MetadataKey) throws -> Int {
        var removed = 0
        try modifyItemList(create: false) { children in
            let before = children.count
            children.removeAll { MP4File.key(of: $0) == key }
            removed = before - children.count
        }
        return removed
    }

    mutating func modifyItemList(create: Bool, _ body: (inout [MP4Box]) throws -> Void) throws {
        var movie = self.movie
        let handler: MP4Box = {
            var payload = Data(count: 8)
            payload.append(FourCC("mdir").bytes)
            payload.append(FourCC("appl").bytes)
            payload.append(Data(count: 10))
            return MP4Box(type: "hdlr", payload: payload)
        }()
        _ = try movie.withChild("udta", create: create ? { MP4Box(type: "udta", children: []) } : nil) { udta in
            try udta.withChild(
                "meta", create: create ? { MP4Box(type: "meta", prefix: Data(count: 4), children: [handler]) } : nil
            ) { meta in
                var children = meta.children
                if !children.contains(where: { $0.type == "ilst" }) {
                    guard create else { return }
                    // Keep existing padding after the item list, as Music and the iTunes Store write it.
                    let index = children.firstIndex { $0.type == "free" } ?? children.endIndex
                    children.insert(MP4Box(type: "ilst", children: []), at: index)
                }
                let index = children.firstIndex { $0.type == "ilst" }!
                var items = children[index].children
                try body(&items)
                children[index].children = items
                meta.children = children
            }
        }
        self.movie = movie
    }
}
