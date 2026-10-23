// The Automation permission for Music, read without prompting and without launching Music. Built only on
// macOS. With Music not running, macOS cannot report the permission and returns procNotFound.
#if os(macOS)
    import AppKit
    import CoreServices
    import Foundation

    public enum MusicPermission: String, Sendable {
        case permitted
        case denied
        case notDetermined = "not determined"
        case musicNotRunning = "Music not running"
        case unknown
    }

    public enum MusicStatus {
        public static let bundleIdentifier = "com.apple.Music"

        public static var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        }

        /// The version of the installed Music app, read from its bundle.
        public static var version: String? {
            Bundle(url: URL(fileURLWithPath: "/System/Applications/Music.app"))?
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        }

        /// The stored decision on whether this process may send Apple Events to Music, never prompting.
        public static func permission() -> MusicPermission {
            var target = AEAddressDesc()
            let identifier = Array(bundleIdentifier.utf8)
            let created = identifier.withUnsafeBytes {
                AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, $0.count, &target)
            }
            guard created == noErr else { return .unknown }
            defer { AEDisposeDesc(&target) }
            let status = AEDeterminePermissionToAutomateTarget(
                &target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
            switch status {
            case noErr: return .permitted
            case OSStatus(errAEEventNotPermitted): return .denied
            case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
            case OSStatus(procNotFound): return .musicNotRunning
            default: return .unknown
            }
        }
    }
#endif
