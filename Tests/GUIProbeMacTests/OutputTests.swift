import Foundation
import Testing

@testable import GUIProbeMac

@Suite struct OutputTests {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("guiprobe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    @Test func theOutputIsCreatedExclusivelyWithOwnerOnlyPermissions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("out.json").path
        #expect(!ExclusiveFile.exists(path))
        try ExclusiveFile.createAndWrite(Data("first\n".utf8), to: path)
        #expect(ExclusiveFile.exists(path))
        let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(throws: (any Error).self) { try ExclusiveFile.createAndWrite(Data("second\n".utf8), to: path) }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "first\n")
    }

    @Test func aMissingDirectoryIsAnErrorAndCreatesNothing() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("missing/out.json").path
        #expect(throws: (any Error).self) { try ExclusiveFile.createAndWrite(Data("x".utf8), to: path) }
        #expect(!ExclusiveFile.exists(path))
    }

    @Test func aRefusalRecordDistinguishesAnUnrunProbe() throws {
        let output = ProbeOutput(
            mode: "observe", status: .refused, stopReason: "no reviewed interface profile was supplied",
            sourceCommit: "abc", macOSVersion: Fixtures.macOS, musicVersion: nil, confirmations: Confirmations())
        let object = try #require(JSONSerialization.jsonObject(with: output.json()) as? [String: Any])
        #expect(object["status"] as? String == "refused")
        #expect(object["probeVersion"] as? String == GUIProbe.version)
        #expect(object["sourceCommit"] as? String == "abc")
        #expect(object["observation"] == nil && object["survey"] == nil)
        #expect((object["confirmations"] as? [String: Bool])?.values.allSatisfy { !$0 } == true)
    }

    @Test func anObservationRecordHoldsReadingsAndVerdicts() throws {
        let verdict = Fixtures.classify(Fixtures.emptyReadings)
        var output = ProbeOutput(
            mode: "observe", status: .completed, macOSVersion: Fixtures.macOS, musicVersion: Fixtures.music,
            confirmations: Confirmations(separateTestUser: true))
        output.observation = ObservationSection(
            readingsRequested: 3, intervalSeconds: 3, locale: Fixtures.locale, inventoryFileTrackCount: 0,
            songs: ViewObservation(readings: Fixtures.emptyReadings, verdict: VerdictRecord(verdict)),
            recentlyAdded: nil, combined: VerdictRecord(verdict))
        let decoded = try JSONDecoder().decode(ProbeOutput.self, from: output.json())
        #expect(decoded == output)
        #expect(decoded.observation?.combined.outcome == "candidateEmpty")
    }
}
