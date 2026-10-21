import Foundation
import Testing

@testable import GUIProbeMac

@Suite struct ProfileTests {
    static let view = """
        {"identification": {"role": "AXGroup", "identifier": "songs-view", "label": "Songs"},
         "containerRole": "AXTable", "contentRole": "AXRow", "rowsComplete": true}
        """

    func json(
        top: String = "", stability: String? = #""stability": {"minimumReadings": 3, "minimumSpanSeconds": 4.5}"#,
        omit: String? = nil
    ) -> Data {
        var fields = [
            #""musicVersion": "99.1""#, #""macOSVersion": "Version 99.0""#, #""locale": "en_US""#,
            #""songs": \#(Self.view)"#, #""recentlyAdded": \#(Self.view)"#,
        ]
        if let stability { fields.append(stability) }
        if !top.isEmpty { fields.append(top) }
        if let omit { fields.removeAll { $0.hasPrefix("\"\(omit)\"") } }
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

    @Test func aCompleteProfileDecodes() throws {
        let profile = try InterfaceProfile.decode(from: json())
        #expect(profile.musicVersion == "99.1")
        #expect(profile.songs.identification.label == "Songs")
        #expect(profile.songs.placeholder == nil)
        #expect(profile.stability == Stability(minimumReadings: 3, minimumSpanSeconds: 4.5))
    }

    @Test func aMissingStabilityDecodesAsAbsentAndIsNeverDefaulted() throws {
        let profile = try InterfaceProfile.decode(from: json(stability: nil))
        #expect(profile.stability == nil)
        let verdict = Fixtures.classify(Fixtures.emptyReadings, profile: profile)
        #expect(Fixtures.reasons(verdict).contains(.stabilityUnqualified))
    }

    @Test func aStabilityWithMissingFieldsIsRefused() {
        #expect(throws: DecodingError.self) {
            try InterfaceProfile.decode(from: json(stability: #""stability": {"minimumReadings": 3}"#))
        }
    }

    @Test(arguments: ["musicVersion", "macOSVersion", "locale", "songs", "recentlyAdded"])
    func eachMissingRequiredFieldIsRefused(field: String) {
        #expect(throws: DecodingError.self) { try InterfaceProfile.decode(from: json(omit: field)) }
    }

    @Test func unknownKeysAreRefusedAtEveryLevel() {
        #expect(throws: DecodingError.self) { try InterfaceProfile.decode(from: json(top: #""extra": 1"#)) }
        let nested = json(stability: #""stability": {"minimumReadings": 3, "minimumSpanSeconds": 4, "extra": 1}"#)
        #expect(throws: DecodingError.self) { try InterfaceProfile.decode(from: nested) }
        let view = Self.view.replacingOccurrences(of: #""rowsComplete": true"#, with: #""rowsComplete": true, "x": 1"#)
        let data = Data(
            String(decoding: json(), as: UTF8.self).replacingOccurrences(of: Self.view, with: view).utf8)
        #expect(throws: DecodingError.self) { try InterfaceProfile.decode(from: data) }
        let rule = Self.view.replacingOccurrences(of: #""role": "AXGroup""#, with: #""role": "AXGroup", "x": 1"#)
        let ruleData = Data(
            String(decoding: json(), as: UTF8.self).replacingOccurrences(of: Self.view, with: rule).utf8)
        #expect(throws: DecodingError.self) { try InterfaceProfile.decode(from: ruleData) }
    }

    @Test func emptyVersionsAndMalformedDocumentsAreRefused() {
        let empty = Data(String(decoding: json(), as: UTF8.self).replacingOccurrences(of: "99.1", with: "").utf8)
        #expect(throws: DecodingError.self) { try InterfaceProfile.decode(from: empty) }
        #expect(throws: (any Error).self) { try InterfaceProfile.decode(from: Data("[]".utf8)) }
        #expect(throws: (any Error).self) { try InterfaceProfile.decode(from: Data("{".utf8)) }
    }

    @Test func theRepositoryShipsNoProfile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/GUIProbeMac")
        let names = try FileManager.default.contentsOfDirectory(atPath: sources.path)
        #expect(names.allSatisfy { !$0.hasSuffix(".json") })
    }
}
