// M1 spike S3 (read-only part): Automation permission state for Music, determined without
// launching Music, sending a library event, or presenting a consent prompt.
//
// Usage: automation-spike

import AppKit
import CoreServices
import Foundation

let bundleIdentifier = "com.apple.Music"
let running = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
print("== Music running: \(running)")

var target = AEAddressDesc()
let identifier = Array(bundleIdentifier.utf8)
let created = identifier.withUnsafeBytes {
    AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, $0.count, &target)
}
guard created == noErr else {
    print("== AECreateDesc failed: \(created)")
    exit(1)
}
defer { AEDisposeDesc(&target) }
// askUserIfNeeded is false: the call reports the stored decision and never prompts.
let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
let meaning: String
switch status {
case noErr: meaning = "permitted"
case OSStatus(errAEEventNotPermitted): meaning = "denied (errAEEventNotPermitted)"
case OSStatus(errAEEventWouldRequireUserConsent): meaning = "not yet decided (errAEEventWouldRequireUserConsent)"
case OSStatus(procNotFound): meaning = "target not running (procNotFound)"
default: meaning = "other"
}
print("== AEDeterminePermissionToAutomateTarget without prompting: \(status), \(meaning)")
print(
    "== Music running afterwards: \(!NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty)"
)
