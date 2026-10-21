// Where a survey may write and how it publishes a file. Foundation and POSIX only. A destination is a directory
// below the home directory of the process user, reached from that home one component at a time through
// descriptors, never through a path string that the system resolves, and every file is published under its final
// name only after it has been written completely.
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The device and inode of an opened directory, which identify it independently of its path.
struct FileIdentity: Equatable, Sendable {
    var device: UInt64
    var inode: UInt64
}

enum PlacementError: Error, Equatable, CustomStringConvertible {
    case invalidComponent(String)
    case protectedLocation(String)
    case invalidName(String)
    case cannotOpen(String, Int32)
    case notOwned(String)
    case unsafePermissions(String)
    case repository(String)
    case accessControlList(String)
    case notLocal(String)
    case unknownProperty(String, Int32)
    case nested
    case alreadyExists(String)
    case moved(String)

    var description: String {
        switch self {
        case .invalidComponent(let name): "the path component '\(name)' is not allowed"
        case .protectedLocation(let name): "the home folder '\(name)' is not an allowed destination"
        case .invalidName(let name): "the file name '\(name)' is not allowed"
        case .cannotOpen(let name, let code): "'\(name)' could not be opened as a directory without links (\(code))"
        case .notOwned(let name): "'\(name)' is not owned by the process user"
        case .unsafePermissions(let name): "'\(name)' grants access to other users"
        case .repository(let name): "'\(name)' lies in a Git working tree"
        case .accessControlList(let name): "'\(name)' has an access control list"
        case .notLocal(let name): "'\(name)' is not on a local file system"
        case .unknownProperty(let name, let code): "a property of '\(name)' could not be determined (\(code))"
        case .nested: "the output and mapping directories must be distinct and not contain each other"
        case .alreadyExists(let name): "'\(name)' already exists; nothing is ever overwritten"
        case .moved(let name): "'\(name)' no longer resolves to the validated directory"
        }
    }
}

/// A validated destination directory: a held descriptor and the identities of the directories from the home
/// directory down to it.
struct ValidatedDirectory: Sendable {
    var descriptor: Int32
    var components: [String]
    var chain: [FileIdentity]
    var identity: FileIdentity { chain[chain.count - 1] }
}

enum SurveyPlacement {
    /// Folders of a home directory that a survey never writes to and never opens: privacy-protected, media,
    /// application, and shared folders. Components are restricted to ASCII, so a lowercase comparison is exact on
    /// a case-insensitive volume.
    static let protectedHomeFolders: Set<String> = [
        "applications", "desktop", "documents", "downloads", "library", "movies", "music", "pictures", "public",
    ]

    static let mappingSuffix = ".identifier-map.json"
    private static let recordSuffix = ".json"

    private static func isASCIILetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
    }

    /// Whether every Unicode scalar of `text` is permitted: the first an ASCII letter or digit, each other one an
    /// ASCII letter, digit, or one of `extra`, with between 1 and `maximumLength` scalars. The whole input is
    /// examined, so no prefix or suffix, such as a line terminator, can be ignored, whatever a regular-expression
    /// engine would make of an end anchor.
    private static func consistsOfPermittedScalars(
        _ text: Substring.UnicodeScalarView, maximumLength: Int, extra: Set<Unicode.Scalar>
    ) -> Bool {
        guard let first = text.first, isASCIILetterOrDigit(first), text.count <= maximumLength else { return false }
        return text.allSatisfy { isASCIILetterOrDigit($0) || extra.contains($0) }
    }

    /// A path component: 1 to 64 scalars, starting with an ASCII letter or digit, otherwise letters, digits, and
    /// `._-` only.
    static func isPermittedComponent(_ text: String) -> Bool {
        consistsOfPermittedScalars(Substring(text).unicodeScalars, maximumLength: 64, extra: [".", "_", "-"])
    }

    /// A record name: a stem of 1 to 48 scalars, starting with an ASCII letter or digit, otherwise letters, digits,
    /// `_`, and `-`, followed by exactly `.json` and nothing else.
    static func isPermittedName(_ text: String) -> Bool {
        let scalars = Substring(text).unicodeScalars
        let suffix = Substring(recordSuffix).unicodeScalars
        guard scalars.count > suffix.count, scalars.suffix(suffix.count).elementsEqual(suffix) else { return false }
        return consistsOfPermittedScalars(scalars.dropLast(suffix.count), maximumLength: 48, extra: ["_", "-"])
    }

    /// The components of a directory relative to the home directory, checked without touching the file system:
    /// no absolute path, no empty, hidden, or traversal component, no character outside ASCII letters, digits, and
    /// `._-`, and no protected first component.
    static func components(of relativePath: String) throws -> [String] {
        guard !relativePath.hasPrefix("/") else { throw PlacementError.invalidComponent(relativePath) }
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { throw PlacementError.invalidComponent(relativePath) }
        for part in parts where !isPermittedComponent(part) { throw PlacementError.invalidComponent(part) }
        if protectedHomeFolders.contains(parts[0].lowercased()) { throw PlacementError.protectedLocation(parts[0]) }
        return parts
    }

    /// A record name: one component ending in `.json`, whose stem has no dot.
    static func validateName(_ name: String) throws {
        guard isPermittedName(name) else { throw PlacementError.invalidName(name) }
    }

    /// The private mapping's name, derived from the record's name; it never equals a record name.
    static func mappingName(for recordName: String) -> String {
        String(recordName.dropLast(".json".count)) + mappingSuffix
    }

    static func temporaryName(for name: String, runID: String) -> String { ".\(name).\(runID).partial" }

    private static func identity(of descriptor: Int32, name: String) throws -> (FileIdentity, stat) {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw PlacementError.unknownProperty(name, errno) }
        return (
            FileIdentity(
                device: UInt64(truncatingIfNeeded: info.st_dev), inode: UInt64(truncatingIfNeeded: info.st_ino)),
            info
        )
    }

    /// The properties required of every directory from the home directory down: a directory owned by the process
    /// user, writable by no one else, and not holding a `.git` entry. A final directory must also grant no access to
    /// group or others, carry no access control list, and lie on a local file system. A property that cannot be
    /// established refuses.
    private static func check(
        _ descriptor: Int32, name: String, user: uid_t, isHome: Bool, isFinal: Bool
    ) throws -> FileIdentity {
        let (identity, info) = try identity(of: descriptor, name: name)
        // The mode is widened explicitly, since its type and that of the constants differ between platforms.
        let mode = UInt32(info.st_mode)
        guard mode & UInt32(S_IFMT) == UInt32(S_IFDIR) else { throw PlacementError.cannotOpen(name, ENOTDIR) }
        guard info.st_uid == user else { throw PlacementError.notOwned(name) }
        guard mode & 0o022 == 0 else { throw PlacementError.unsafePermissions(name) }
        if isFinal && mode & 0o077 != 0 { throw PlacementError.unsafePermissions(name) }
        var marker = stat()
        if fstatat(descriptor, ".git", &marker, AT_SYMLINK_NOFOLLOW) == 0 { throw PlacementError.repository(name) }
        guard errno == ENOENT else { throw PlacementError.unknownProperty(name, errno) }
        #if canImport(Darwin)
            // A home directory normally carries a deny-delete entry, so only the directories below it are checked.
            if !isHome {
                errno = 0
                if let list = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) {
                    acl_free(UnsafeMutableRawPointer(list))
                    throw PlacementError.accessControlList(name)
                }
                guard errno == ENOENT else { throw PlacementError.unknownProperty(name, errno) }
            }
            if isFinal {
                var volume = statfs()
                guard fstatfs(descriptor, &volume) == 0 else { throw PlacementError.unknownProperty(name, errno) }
                guard (volume.f_flags & UInt32(MNT_LOCAL)) != 0 else { throw PlacementError.notLocal(name) }
            }
        #endif
        return identity
    }

    private static func openDirectory(at descriptor: Int32?, _ name: String) throws -> Int32 {
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        let opened = descriptor.map { openat($0, name, flags) } ?? open(name, flags)
        guard opened >= 0 else { throw PlacementError.cannotOpen(name, errno) }
        return opened
    }

    /// Opens the directory at `components` below `home` (the home path from the password database, never from the
    /// environment), checking each directory on the way through a descriptor opened without following a link.
    static func openValidated(_ components: [String], home: String, user: uid_t) throws -> ValidatedDirectory {
        var current = try openDirectory(at: nil, home)
        var chain: [FileIdentity] = []
        do {
            chain.append(try check(current, name: home, user: user, isHome: true, isFinal: false))
            for (index, component) in components.enumerated() {
                let next = try openDirectory(at: current, component)
                close(current)
                current = next
                chain.append(
                    try check(
                        current, name: component, user: user, isHome: false, isFinal: index == components.count - 1))
            }
        } catch {
            close(current)
            throw error
        }
        return ValidatedDirectory(descriptor: current, components: components, chain: chain)
    }

    /// The two directories must differ and neither may contain the other.
    static func requireSeparate(_ first: ValidatedDirectory, _ second: ValidatedDirectory) throws {
        if first.chain.contains(second.identity) || second.chain.contains(first.identity) {
            throw PlacementError.nested
        }
    }

    static func requireAbsent(_ name: String, in directory: ValidatedDirectory) throws {
        var info = stat()
        if fstatat(directory.descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            throw PlacementError.alreadyExists(name)
        }
        guard errno == ENOENT else { throw PlacementError.unknownProperty(name, errno) }
    }

    /// Checks a held directory again before publication: its properties on the held descriptor, and that its path
    /// below the home directory still leads to the same directory.
    static func recheck(_ directory: ValidatedDirectory, home: String, user: uid_t) throws {
        let name = directory.components.last ?? home
        _ = try check(directory.descriptor, name: name, user: user, isHome: false, isFinal: true)
        let again = try openValidated(directory.components, home: home, user: user)
        close(again.descriptor)
        guard again.identity == directory.identity else { throw PlacementError.moved(name) }
    }
}

/// The failure of a publication, naming any temporary file that was left in place.
struct PublicationError: Error, Equatable, CustomStringConvertible {
    var stage: String
    var code: Int32
    var leftTemporaryFile: String?

    var description: String {
        let left = leftTemporaryFile.map { "; the temporary file '\($0)' was left in place" } ?? ""
        return "publication failed while \(stage) (\(code))\(left)"
    }
}

enum Publication {
    /// Publishes `data` under `name` in `directory`: the data is written to a new temporary file, created
    /// exclusively with owner-only permissions, and flushed; the file is then linked to its final name, which fails
    /// if that name exists and never replaces it; finally the temporary name is removed. An interruption therefore
    /// leaves no file, a partial or complete temporary file, or a complete final file. A temporary file is never
    /// deleted after a failure, so that it can be reviewed. The returned value is the temporary name that remains
    /// when only its final removal failed.
    @discardableResult
    static func publish(_ data: Data, name: String, runID: String, in directory: Int32) throws -> String? {
        let temporary = SurveyPlacement.temporaryName(for: name, runID: runID)
        let file = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw PublicationError(stage: "creating the temporary file", code: errno) }
        var failure: PublicationError?
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(file, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else {
                    failure = PublicationError(stage: "writing", code: errno, leftTemporaryFile: temporary)
                    return
                }
                offset += written
            }
        }
        if failure == nil {
            #if canImport(Darwin)
                // A full flush asks the device to persist the data, which a plain fsync does not on Darwin.
                let flushed = fcntl(file, F_FULLFSYNC) == 0 || fsync(file) == 0
            #else
                let flushed = fsync(file) == 0
            #endif
            if !flushed { failure = PublicationError(stage: "flushing", code: errno, leftTemporaryFile: temporary) }
        }
        close(file)
        if let failure { throw failure }
        guard linkat(directory, temporary, directory, name, 0) == 0 else {
            throw PublicationError(stage: "linking the final name", code: errno, leftTemporaryFile: temporary)
        }
        _ = fsync(directory)
        guard unlinkat(directory, temporary, 0) == 0 else { return temporary }
        _ = fsync(directory)
        return nil
    }
}
