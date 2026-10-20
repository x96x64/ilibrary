import Foundation
import Testing

@testable import RebuildCore

@Suite struct RebuildLocationsTests {
    func make(
        sources: [String] = ["/lib/media/Music"], media: String = "/lib/media", backup: String = "/bk/backup",
        restore: String = "/rs/restore", staging: String = "/st/stage", workspace: String = "/ws/work"
    ) -> RebuildLocations {
        RebuildLocations(
            sources: sources, mediaFolder: media, backupRoot: backup, restorationDirectory: restore,
            stagingDirectory: staging, workspaceDirectory: workspace)
    }

    func texts(_ locations: RebuildLocations) -> [String] { locations.validate().map(\.description) }

    @Test func separateLocationsAreValidAndSourcesInsideMediaArePermitted() {
        #expect(make().validate().isEmpty)
        #expect(make(sources: ["/lib/media"]).validate().isEmpty)
        #expect(make(sources: ["/lib/media/Music/A", "/lib/media/Music/B"]).validate().isEmpty)
    }

    @Test func relativeEmptyAndUnstandardizedPathsAreRefused() {
        for bad in ["", "relative/dir", "/a/../b", "/a/./b", "/a//b", "/a/b/"] {
            let found = make(backup: bad).validate()
            #expect(
                found.contains {
                    if case .invalidPath(let label, _, _) = $0 { return label == "backup root" }
                    return false
                }, "\(bad)")
        }
        #expect(make(sources: []).validate().contains(.noSources))
        // Every reason is listed together.
        #expect(make(sources: ["x"], backup: "", staging: "y").validate().count == 3)
    }

    @Test func sourcesEqualOrNestedAreRefused() {
        #expect(!texts(make(sources: ["/lib/media/Music", "/lib/media/Music"])).isEmpty)
        #expect(!texts(make(sources: ["/lib/media/Music", "/lib/media/Music/A"])).isEmpty)
        #expect(!texts(make(sources: ["/lib/media/Music/A", "/lib/media/Music"])).isEmpty)
    }

    @Test func mediaFolderInsideASourceIsRefused() {
        #expect(!texts(make(sources: ["/lib"])).isEmpty)
    }

    @Test func everyDirectoryAgainstEveryOtherLocationIsRefused() {
        let base = make()
        let names: [(String, WritableKeyPath<RebuildLocations, String>)] = [
            ("backup", \.backupRoot), ("restore", \.restorationDirectory), ("staging", \.stagingDirectory),
            ("workspace", \.workspaceDirectory),
        ]
        let others = ["/lib/media/Music", "/lib/media", "/bk/backup", "/rs/restore", "/st/stage", "/ws/work"]
        for (name, path) in names {
            for other in others where other != base[keyPath: path] {
                for variant in [other, other + "/inside"] {
                    var locations = base
                    locations[keyPath: path] = variant
                    #expect(!locations.validate().isEmpty, "\(name) at \(variant)")
                }
                // A directory containing the other location.
                var parent = base
                let up = other.split(separator: "/").dropLast().joined(separator: "/")
                parent[keyPath: path] = "/" + up
                #expect(!parent.validate().isEmpty, "\(name) containing \(other)")
            }
        }
    }

    @Test func rawStringPrefixIsNotNesting() {
        #expect(make(backup: "/lib/media2").validate().isEmpty)
        #expect(make(backup: "/st/stage2", staging: "/st/stage").validate().isEmpty)
    }

    @Test func normalizationAndCaseCollisionsAreRefused() {
        let composed = "/bk/caf\u{00E9}"
        let decomposed = "/bk/cafe\u{0301}"
        #expect(!make(backup: composed, restore: decomposed).validate().isEmpty)
        #expect(!make(backup: "/bk/Backup", restore: "/bk/backup").validate().isEmpty)
        #expect(
            !make(backup: "/BK/x", staging: "/bk/X").validate()
                .isEmpty)
        #expect(!make(sources: ["/lib/media/Music", "/LIB/media/music"]).validate().isEmpty)
        #expect(!make(backup: "/LIB/MEDIA/inside").validate().isEmpty)
    }

    @Test func symbolicLinkAtAnyExistingComponentIsRefused() {
        let locations = make()
        let link = FileStatus(
            kind: .symbolicLink, size: 0, inode: 1, device: 1, linkCount: 1, modification: FileTimestamp(seconds: 0),
            creation: nil)
        let directory = FileStatus(
            kind: .directory, size: 0, inode: 2, device: 1, linkCount: 1, modification: FileTimestamp(seconds: 0),
            creation: nil)
        let clean = locations.symbolicLinkRefusals { _ in directory }
        #expect(clean.isEmpty)
        let missing = locations.symbolicLinkRefusals { _ in throw FileStatusError.missing(path: "x") }
        #expect(missing.isEmpty)
        let ancestor = locations.symbolicLinkRefusals { path in path == "/bk" ? link : directory }
        #expect(ancestor.count == 1)
        if case .symbolicLink(_, _, let at) = ancestor[0] { #expect(at == "/bk") } else { Issue.record("wrong case") }
        let leaf = locations.symbolicLinkRefusals { path in path == "/st/stage" ? link : directory }
        #expect(leaf.count == 1)
        // A missing component stops the descent, so a deeper link is not reached.
        let stopped = locations.symbolicLinkRefusals { path in
            if path == "/bk" { throw FileStatusError.missing(path: path) }
            return path == "/bk/backup" ? link : directory
        }
        #expect(stopped.isEmpty)
        let denied = locations.symbolicLinkRefusals { path in
            if path == "/ws" { throw FileStatusError.permissionDenied(path: path) }
            return directory
        }
        #expect(denied.count == 1)
    }
}
