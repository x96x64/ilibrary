import Foundation

/// A box of an MP4 file. Boxes inside the movie box are held in memory; other top-level boxes, including
/// the media data, refer to the source file and are copied unchanged when the file is written.
public struct MP4Box: Sendable {
    public enum Content: Sendable {
        /// The payload of a box without children.
        case leaf(Data)
        /// The bytes before the first child, the children, and bytes after the last child that form no box.
        case container(prefix: Data, children: [MP4Box], trailer: Data)
        /// An unchanged top-level box, copied from `sourceRange` of the source file.
        case source
    }

    public var type: FourCC
    public var content: Content
    /// The original absolute byte range including the header, for boxes read from a file.
    public internal(set) var sourceRange: Range<Int>?
    var usesLargeSize = false

    public init(type: FourCC, payload: Data) {
        self.type = type
        content = .leaf(payload)
    }

    public init(type: FourCC, prefix: Data = Data(), children: [MP4Box]) {
        self.type = type
        content = .container(prefix: prefix, children: children, trailer: Data())
    }

    init(type: FourCC, content: Content, sourceRange: Range<Int>?, usesLargeSize: Bool) {
        self.type = type
        self.content = content
        self.sourceRange = sourceRange
        self.usesLargeSize = usesLargeSize
    }

    public var payload: Data? {
        if case .leaf(let data) = content { return data }
        return nil
    }

    public var children: [MP4Box] {
        get {
            if case .container(_, let children, _) = content { return children }
            return []
        }
        set {
            if case .container(let prefix, _, let trailer) = content {
                content = .container(prefix: prefix, children: newValue, trailer: trailer)
            }
        }
    }

    public var isContainer: Bool {
        if case .container = content { return true }
        return false
    }

    public func child(_ type: FourCC) -> MP4Box? { children.first { $0.type == type } }

    /// Every descendant of the given type, in file order.
    public func descendants(_ type: FourCC) -> [MP4Box] {
        children.flatMap { ($0.type == type ? [$0] : []) + $0.descendants(type) }
    }

    /// Applies `body` to every descendant, depth first, children before their parents.
    mutating func transformDescendants(_ body: (inout MP4Box) throws -> Void) rethrows {
        guard case .container(let prefix, var children, let trailer) = content else { return }
        for index in children.indices {
            try children[index].transformDescendants(body)
            try body(&children[index])
        }
        content = .container(prefix: prefix, children: children, trailer: trailer)
    }

    /// Applies `body` to the first child of the given type, creating it with `create` when it is absent.
    mutating func withChild<T>(
        _ type: FourCC, create: (() -> MP4Box)? = nil, _ body: (inout MP4Box) throws -> T
    ) rethrows -> T? {
        var children = self.children
        if let index = children.firstIndex(where: { $0.type == type }) {
            let result = try body(&children[index])
            self.children = children
            return result
        }
        guard let create else { return nil }
        var box = create()
        let result = try body(&box)
        children.append(box)
        self.children = children
        return result
    }

    var payloadSize: Int {
        switch content {
        case .leaf(let data): return data.count
        case .container(let prefix, let children, let trailer):
            return prefix.count + children.reduce(0) { $0 + $1.serializedSize } + trailer.count
        case .source: return (sourceRange?.count ?? 0) - headerSize
        }
    }

    var headerSize: Int { usesLargeSize || payloadSizeExcludingHeaderNeedsLarge ? 16 : 8 }

    private var payloadSizeExcludingHeaderNeedsLarge: Bool {
        if case .source = content { return false }
        return payloadSize + 8 > Int(UInt32.max)
    }

    public var serializedSize: Int {
        if case .source = content { return sourceRange?.count ?? 0 }
        return headerSize + payloadSize
    }

    /// Serializes a box held in memory. Source boxes are written by the file writer instead.
    func serialize(into output: inout Data) {
        precondition(!isSourceReference, "source boxes are copied from the source file")
        if headerSize == 16 {
            output.appendBigEndian(UInt32(1))
            output.append(type.bytes)
            output.appendBigEndian(UInt64(serializedSize))
        } else {
            output.appendBigEndian(UInt32(serializedSize))
            output.append(type.bytes)
        }
        switch content {
        case .leaf(let data): output.append(data)
        case .container(let prefix, let children, let trailer):
            output.append(prefix)
            for child in children { child.serialize(into: &output) }
            output.append(trailer)
        case .source: break
        }
    }

    var isSourceReference: Bool {
        if case .source = content { return true }
        return false
    }
}
