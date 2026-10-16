// File and folder dates on macOS. Creation dates cannot be set portably, so this target is built only
// on macOS; on other platforms it is empty.
#if os(macOS)
    import Darwin
    import Foundation

    /// Failures of date operations. A failed operation leaves the file system unchanged.
    public enum FileDateError: Error, Equatable, Sendable, CustomStringConvertible {
        case missing(path: String)
        case symbolicLink(path: String)
        case notApplied(path: String, expected: Date, created: Date?, modified: Date?)
        case failed(path: String, reason: String)

        public var description: String {
            switch self {
            case .missing(let path): "\(path) does not exist; nothing was created"
            case .symbolicLink(let path): "\(path) is a symbolic link, which is not followed"
            case .notApplied(let path, let expected, let created, let modified):
                "the dates of \(path) were not applied: expected \(expected), "
                    + "found created \(created.map(String.init(describing:)) ?? "unknown"), "
                    + "modified \(modified.map(String.init(describing:)) ?? "unknown")"
            case .failed(let path, let reason): "the dates of \(path) could not be set: \(reason)"
            }
        }
    }

    public struct FileDateValues: Equatable, Sendable {
        public var created: Date?
        public var modified: Date?

        public init(created: Date?, modified: Date?) {
            self.created = created
            self.modified = modified
        }
    }

    public enum FileDates {
        /// Requires that the path exists and is not a symbolic link, without following links (decision 9).
        public static func checkTarget(_ url: URL) throws {
            var status = stat()
            guard lstat(url.path, &status) == 0 else { throw FileDateError.missing(path: url.path) }
            if status.st_mode & S_IFMT == S_IFLNK { throw FileDateError.symbolicLink(path: url.path) }
        }

        public static func read(_ url: URL) throws -> FileDateValues {
            try checkTarget(url)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return FileDateValues(
                created: attributes[.creationDate] as? Date, modified: attributes[.modificationDate] as? Date)
        }

        /// Sets the creation and modification dates and confirms them by reading them back. A missing path
        /// is reported, never created; a symbolic link is refused rather than followed.
        public static func set(_ url: URL, to date: Date) throws {
            try checkTarget(url)
            do {
                try FileManager.default.setAttributes(
                    [.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
            } catch {
                throw FileDateError.failed(path: url.path, reason: error.localizedDescription)
            }
            let values = try read(url)
            func matches(_ value: Date?) -> Bool { value.map { abs($0.timeIntervalSince(date)) < 1 } ?? false }
            guard matches(values.created), matches(values.modified) else {
                throw FileDateError.notApplied(
                    path: url.path, expected: date, created: values.created, modified: values.modified)
            }
        }
    }
#endif
