// macOS-only: the logic under test uses `MusicTrackInfo`, which exists only on macOS, so this target is not
// in the Linux CI filter. No test sends an Apple Event or reads a preference.
#if os(macOS)
    import Foundation
    import Testing

    @testable import LibraryMac
    @testable import M11Probe

    @Suite struct ProbeLogicTests {
        func track(
            _ id: String, name: String = "Secret Title", location: String? = "/Users/private/Secret Album/01.m4a",
            status: String = "local"
        ) -> MusicTrackInfo {
            MusicTrackInfo(
                persistentID: id, name: name, album: "Secret Album", artist: "Secret Artist",
                albumArtist: "Secret Album Artist", composer: "Secret Composer", genre: "Secret Genre", year: 2001,
                trackNumber: 1, discNumber: 1, comment: "Secret Comment", trackCount: 10, discCount: 1,
                compilation: false, location: location, cloudStatus: status)
        }

        func snapshot(_ tracks: [MusicTrackInfo], total: Int? = nil, dates: Bool = true) -> MusicLibrarySnapshot {
            MusicLibrarySnapshot(
                tracks: tracks, trackCount: total ?? tracks.count, fileTrackCount: tracks.count,
                dateAddedSeconds: dates ? Dictionary(uniqueKeysWithValues: tracks.map { ($0.persistentID, 1) }) : [:])
        }

        @Test func equalArraysInDifferentOrderAreIdentical() {
            let a = [track("A"), track("B"), track("C")]
            let result = ProbeAnalysis.compare(a, a.reversed())
            #expect(result.identical)
            #expect(result.differingTracksByField.values.allSatisfy { $0 == 0 })
            #expect(result.differingTracksByField.count == 16)
        }

        @Test(arguments: TrackField.allCases.filter { $0 != .persistentID })
        func eachFieldDifferenceIsCountedOnce(field: TrackField) {
            let base = [track("A"), track("B")]
            var changed = base
            switch field {
            case .name: changed[0].name = "x"
            case .album: changed[0].album = "x"
            case .artist: changed[0].artist = "x"
            case .albumArtist: changed[0].albumArtist = "x"
            case .composer: changed[0].composer = "x"
            case .genre: changed[0].genre = "x"
            case .year: changed[0].year = 1
            case .trackNumber: changed[0].trackNumber = 9
            case .discNumber: changed[0].discNumber = 9
            case .location: changed[0].location = nil
            case .cloudStatus: changed[0].cloudStatus = "x"
            case .comment: changed[0].comment = "x"
            case .trackCount: changed[0].trackCount = 9
            case .discCount: changed[0].discCount = 9
            case .compilation: changed[0].compilation = true
            case .persistentID: break
            }
            let result = ProbeAnalysis.compare(base, changed)
            #expect(!result.identical)
            for other in TrackField.allCases {
                #expect(result.differingTracksByField[other.rawValue] == (other == field ? 1 : 0))
            }
        }

        @Test func identityDifferencesAreCountedSymmetrically() {
            let result = ProbeAnalysis.compare([track("A"), track("B")], [track("B"), track("C"), track("D")])
            #expect(!result.identical)
            #expect(result.differingTracksByField["persistentID"] == 3)
            #expect(!ProbeAnalysis.sameIdentitySet([track("A")], [track("B")]))
            #expect(ProbeAnalysis.sameIdentitySet([track("A"), track("B")], [track("B"), track("A")]))
        }

        @Test func duplicateIdentifiersPreventIdentity() {
            let result = ProbeAnalysis.compare([track("A"), track("A")], [track("A"), track("A")])
            #expect(!result.identical)
            #expect(result.duplicateIDsInFirst == 1)
            #expect(result.duplicateIDsInSecond == 1)
        }

        @Test func locationsStatusesAndExtensionsAreSummarized() {
            let tracks = [
                track("A", location: "/x/a.M4A", status: "subscription"), track("B", location: "/x/b.m4a"),
                track("C", location: "/x/c.flac", status: "local"), track("D", location: nil, status: "unknown"),
                track("E", location: "/x/noextension"),
            ]
            #expect(ProbeAnalysis.missingLocationCount(tracks) == 1)
            #expect(ProbeAnalysis.extensionCounts(tracks) == ["m4a": 2, "flac": 1, "(none)": 1])
            #expect(ProbeAnalysis.cloudStatusCounts(tracks) == ["subscription": 1, "local": 3, "unknown": 1])
        }

        @Test func dateAddedCompletenessIsDetected() {
            #expect(ProbeAnalysis.everyTrackHasDateAdded(snapshot([track("A")])))
            #expect(!ProbeAnalysis.everyTrackHasDateAdded(snapshot([track("A")], dates: false)))
        }

        @Test func reportRecordsCountsFallbackAndDurations() throws {
            let tracks = [track("A"), track("B")]
            let report = ProbeReportBuilder.build(
                macOSVersion: "15.1.0", musicVersion: "1.5", perTrack: tracks, bulk: tracks, bulkFallbackUsed: true,
                snapshot: snapshot(tracks, total: 3),
                durations: .init(perTrackSeconds: 2, bulkSeconds: 1, snapshotSeconds: 0.5))
            #expect(
                report.readers
                    == .init(
                        perTrackCount: 2, bulkCount: 2, snapshotTrackCount: 2, snapshotTotalTrackCount: 3,
                        snapshotFileTrackCount: 2))
            #expect(report.bulkFallbackUsed == true)
            #expect(report.equivalence?.perTrackAndBulkIdentical == true)
            #expect(report.equivalence?.snapshotAndPerTrackIDSetsEqual == true)
            #expect(report.everySnapshotTrackHasDateAdded == true)
            #expect(report.userNameCheckPassed)
            #expect(report.error == nil)
            let decoded = try JSONDecoder().decode(ProbeReport.self, from: report.json())
            #expect(decoded == report)
        }

        @Test func reportJSONContainsNoNamePathOrIdentifier() throws {
            let tracks = [track("PERSISTENT-ID-0001"), track("PERSISTENT-ID-0002", location: "/Users/private/z.flac")]
            var changed = tracks
            changed[0].name = "Another Secret Title"
            let report = ProbeReportBuilder.build(
                macOSVersion: "15.1.0", musicVersion: "1.5", perTrack: tracks, bulk: changed, bulkFallbackUsed: false,
                snapshot: snapshot(tracks), durations: .init(perTrackSeconds: 1, bulkSeconds: 1, snapshotSeconds: 1))
            let text = String(decoding: try report.json(), as: UTF8.self)
            for forbidden in [
                "Secret", "PERSISTENT-ID", "/Users", "private", "Another", "01.m4a", "Comment",
            ] {
                #expect(!text.contains(forbidden), "the report contains \(forbidden)")
            }
            #expect(text.contains("\"flac\""))
        }

        @Test(arguments: [
            ("ilibrarytest", true), ("ilibrary-test", true), ("ilibrarytest2", true), ("ilibrary-test_a-1", true),
            ("ilibrarytest!", false), ("user", false), ("", false), ("Xilibrarytest", false),
            ("ilibrarytest\n", false), ("ilibrary test", false), ("ilibrary_test", false),
        ])
        func userNamePattern(name: String, expected: Bool) {
            #expect(ProbeGuards.isTestUserName(name) == expected)
        }

        func environment(
            user: String = "ilibrarytest", uid: UInt32 = 502, account: AccountState = .none, exists: Bool = false
        ) -> ProbeEnvironment {
            ProbeEnvironment(userName: user, uid: uid, account: account, outputExists: exists)
        }

        @Test func refusalLogicCoversEveryCondition() {
            #expect(ProbeGuards.refusal(for: environment()) == nil)
            #expect(ProbeGuards.refusal(for: environment(user: "user")) == .notTestUser)
            #expect(ProbeGuards.refusal(for: environment(uid: 0)) == .privileged)
            #expect(ProbeGuards.refusal(for: environment(account: .signedIn)) == .accountSignedIn)
            #expect(ProbeGuards.refusal(for: environment(account: .unreadable)) == .accountUnreadable)
            #expect(ProbeGuards.refusal(for: environment(exists: true)) == .outputExists)
            #expect(ProbeGuards.refusal(for: environment(user: "user", uid: 0, account: .signedIn)) == .notTestUser)
        }

        func plist(_ value: [String: Any]) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        }

        @Test func accountClassificationFollowsTheM10Probe() throws {
            let signedIn = try plist(["Accounts": [["AccountID": "x"]]])
            let empty = try plist(["Accounts": [Any]()])
            let absent = try plist(["Other": 1])
            #expect(ProbeGuards.classifyAccount(status: 0, standardOutput: signedIn, standardError: "") == .signedIn)
            #expect(ProbeGuards.classifyAccount(status: 0, standardOutput: empty, standardError: "") == .none)
            #expect(ProbeGuards.classifyAccount(status: 0, standardOutput: absent, standardError: "") == .none)
            #expect(
                ProbeGuards.classifyAccount(status: 0, standardOutput: Data("junk".utf8), standardError: "")
                    == .unreadable)
            #expect(
                ProbeGuards.classifyAccount(status: 1, standardOutput: Data(), standardError: "Domain does not exist")
                    == .none)
            #expect(
                ProbeGuards.classifyAccount(status: 1, standardOutput: Data(), standardError: "not found") == .none)
            #expect(
                ProbeGuards.classifyAccount(status: 1, standardOutput: Data(), standardError: "denied")
                    == .unreadable)
        }
    }
#endif
