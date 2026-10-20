import Testing

@testable import RebuildCore

@Suite struct RegistrationClassificationTests {
    let root = "/lib/media/Music"

    func file(_ path: String, root: String = "/lib/media/Music") -> SourcedFileRecord {
        SourcedFileRecord(
            sourceRoot: root,
            record: FileRecord(
                path: path, size: 3, sha256: SHA256.digest(of: [1, 2, 3]), modification: FileTimestamp(seconds: 1),
                creation: nil))
    }

    func registration(
        _ id: String, _ location: String?, status: String = "", name: String = "t"
    ) -> RegistrationRecord {
        RegistrationRecord(
            persistentID: id, name: name, album: "al", artist: "ar", albumArtist: "aa", location: location,
            cloudStatus: status, dateAdded: 0)
    }

    let one = "0000000000000001"
    let two = "00000000000000AB"

    func classify(
        _ registrations: [RegistrationRecord], total: Int? = nil, files: Int? = nil,
        inventory: [SourcedFileRecord]? = nil,
        allowed: Set<String> = RegistrationClassification.defaultAllowedCloudStatuses
    ) -> Result<[RegistrationMapping], RegistrationClassificationError> {
        do {
            return .success(
                try RegistrationClassification.classify(
                    registrations: registrations, totalTrackCount: total ?? registrations.count,
                    fileTrackCount: files ?? registrations.count,
                    inventory: inventory ?? [file("A/1.m4a"), file("A/2.m4a")], sourceRoots: [root],
                    allowedCloudStatuses: allowed))
        } catch let error as RegistrationClassificationError {
            return .failure(error)
        } catch { fatalError("\(error)") }
    }

    func refusals(_ result: Result<[RegistrationMapping], RegistrationClassificationError>) -> [RegistrationRefusal] {
        if case .failure(let error) = result { return error.refusals }
        return []
    }

    let good = { (a: String, b: String) in
        [
            RegistrationRecord(
                persistentID: a, name: "1", album: "A", artist: "x", albumArtist: "x",
                location: "/lib/media/Music/A/1.m4a", cloudStatus: "", dateAdded: 5),
            RegistrationRecord(
                persistentID: b, name: "2", album: "A", artist: "x", albumArtist: "x",
                location: "/lib/media/Music/A/2.m4a", cloudStatus: "unknown", dateAdded: nil),
        ]
    }

    @Test func successMapsInventoryToPersistentIDs() throws {
        let result = classify(good(one, two))
        let mapping = try result.get()
        #expect(
            mapping == [
                RegistrationMapping(location: "/lib/media/Music/A/1.m4a", persistentID: one),
                RegistrationMapping(location: "/lib/media/Music/A/2.m4a", persistentID: two),
            ])
    }

    @Test func caseAndNormalizationDifferencesStillMatch() throws {
        let inventory = [file("Caf\u{00E9}/1.m4a")]
        let result = classify(
            [registration(one, "/LIB/media/music/Cafe\u{0301}/1.M4A")], inventory: inventory)
        #expect(try result.get().count == 1)
    }

    @Test func defaultAllowedStatusesAreEmptyAndUnknownOnly() {
        #expect(RegistrationClassification.defaultAllowedCloudStatuses == ["", "unknown"])
    }

    @Test func nonFileTracksAreRefused() {
        #expect(refusals(classify(good(one, two), total: 3, files: 2)) == [.nonFileTracks(total: 3, file: 2)])
    }

    @Test func missingLocationOutsideAndProtectedAreRefused() {
        let list = good(one, two)
        let noLocation = refusals(classify([list[0], registration(two, nil)]))
        #expect(noLocation.contains(.noLocation(persistentID: two)))
        let outside = refusals(classify([list[0], registration(two, "/elsewhere/2.m4a")]))
        #expect(outside.contains(.outsideSources(persistentID: two, location: "/elsewhere/2.m4a")))
        let rootItself = refusals(classify([list[0], registration(two, root)]))
        #expect(rootItself.contains(.outsideSources(persistentID: two, location: root)))
        let prefix = refusals(classify([list[0], registration(two, "/lib/media/Music2/A/2.m4a")]))
        #expect(prefix.contains(.outsideSources(persistentID: two, location: "/lib/media/Music2/A/2.m4a")))
        let protected = refusals(classify([list[0], registration(two, "/lib/media/Music/A/2.m4p")]))
        #expect(protected.contains(.protectedAudio(persistentID: two, location: "/lib/media/Music/A/2.m4p")))
    }

    @Test func duplicateLocationsAndCloudStatusAreRefused() {
        let list = good(one, two)
        let duplicate = refusals(classify(list + [registration("00000000000000CD", "/LIB/media/music/a/1.M4A")]))
        #expect(
            duplicate.contains(
                .duplicateLocation(
                    location: "/lib/media/Music/A/1.m4a", persistentIDs: [one, "00000000000000CD"])))
        let cloud = refusals(classify([list[0], registration(two, list[1].location, status: "matched")]))
        #expect(cloud == [.cloudStatus(persistentID: two, status: "matched")])
        let admitted = classify(
            [list[0], registration(two, list[1].location, status: "matched")], allowed: ["", "matched"])
        #expect((try? admitted.get()) != nil)
    }

    @Test func unregisteredFilesAndOrphanRegistrationsAreRefused() {
        let list = good(one, two)
        let unregistered = refusals(classify([list[0]], inventory: [file("A/1.m4a"), file("A/2.m4a")]))
        #expect(unregistered == [.unregisteredFile(path: "/lib/media/Music/A/2.m4a")])
        let orphan = refusals(classify(list, inventory: [file("A/1.m4a")]))
        #expect(orphan == [.registrationWithoutFile(persistentID: two, location: "/lib/media/Music/A/2.m4a")])
    }

    @Test func malformedAndDuplicateIDsAreRefused() {
        let list = good("XYZ", one)
        #expect(refusals(classify(list)).contains(.malformedPersistentID("XYZ")))
        let same = good(one, one.lowercased())
        #expect(refusals(classify(same)).contains(.duplicatePersistentID(one.lowercased())))
    }
}
