import Testing

@testable import RebuildCore

@Suite struct CapacityPlanTests {
    let locations = RebuildLocations(
        sources: ["/lib/media/Music"], mediaFolder: "/lib/media", backupRoot: "/bk/backup",
        restorationDirectory: "/rs/restore", stagingDirectory: "/st/stage", workspaceDirectory: "/ws/work")
    let margin = CapacityPlan.workspaceMargin

    func volume(_ map: [String: String]) -> (String) -> String? {
        { path in map.first { path.hasPrefix($0.key) }?.value }
    }

    func room(_ map: [String: UInt64]) -> (String) -> UInt64? {
        { path in map.first { path.hasPrefix($0.key) }?.value }
    }

    @Test func sameVolumeStagingNeedsNothingAndRequirementsAreSummed() {
        // Everything on one volume: restoration (1000) plus the margin; staging adds nothing.
        let plan = CapacityPlan.evaluate(
            inventoryBytes: 1000, locations: locations, volumeOf: { _ in "A" }, availableBytes: { _ in 1000 + margin })
        #expect(plan.isSufficient)
        #expect(plan.volumes.count == 1)
        #expect(plan.volumes[0].required == 1000 + margin)
        #expect(plan.volumes[0].available == 1000 + margin)
        let tight = CapacityPlan.evaluate(
            inventoryBytes: 1000, locations: locations, volumeOf: { _ in "A" },
            availableBytes: { _ in 999 + margin })
        #expect(tight.refusals == [.shortfall(volume: "A", required: 1000 + margin, available: 999 + margin)])
    }

    @Test func crossVolumeStagingNeedsTheFullInventory() {
        let volumes = volume(["/lib": "S", "/rs": "R", "/st": "T", "/ws": "W"])
        let plan = CapacityPlan.evaluate(
            inventoryBytes: 500, locations: locations, volumeOf: volumes,
            availableBytes: room(["/rs": 500, "/st": 500, "/ws": margin]))
        #expect(plan.isSufficient)
        let required = Dictionary(uniqueKeysWithValues: plan.volumes.map { ($0.volume, $0.required) })
        #expect(required == ["R": 500, "T": 500, "W": margin])
    }

    @Test func stagingOnAnotherVolumeAndRestorationOnTheSameOneAreSummed() {
        let volumes = volume(["/lib": "S", "/rs": "X", "/st": "X", "/ws": "W"])
        let plan = CapacityPlan.evaluate(
            inventoryBytes: 500, locations: locations, volumeOf: volumes,
            availableBytes: room(["/rs": 999, "/st": 999, "/ws": margin]))
        #expect(plan.refusals == [.shortfall(volume: "X", required: 1000, available: 999)])
    }

    @Test func shortfallOnWorkspaceMargin() {
        let volumes = volume(["/lib": "S", "/rs": "R", "/st": "S", "/ws": "W"])
        let plan = CapacityPlan.evaluate(
            inventoryBytes: 1, locations: locations, volumeOf: volumes,
            availableBytes: room(["/rs": 10, "/ws": margin - 1]))
        #expect(plan.refusals == [.shortfall(volume: "W", required: margin, available: margin - 1)])
        #expect(plan.volumes.map(\.volume) == ["R", "W"])
    }

    @Test func unknownVolumeIdentityIsRefused() {
        for unknown in ["/lib", "/rs", "/st", "/ws"] {
            let plan = CapacityPlan.evaluate(
                inventoryBytes: 1, locations: locations,
                volumeOf: { $0.hasPrefix(unknown) ? nil : "A" }, availableBytes: { _ in UInt64.max })
            #expect(!plan.isSufficient, "\(unknown)")
            #expect(plan.refusals.contains { if case .unknownVolume = $0 { return true } else { return false } })
        }
    }

    @Test func unknownCapacityIsRefused() {
        let volumes = volume(["/lib": "S", "/rs": "R", "/st": "T", "/ws": "W"])
        let plan = CapacityPlan.evaluate(
            inventoryBytes: 1, locations: locations, volumeOf: volumes,
            availableBytes: { $0.hasPrefix("/st") ? nil : UInt64.max })
        #expect(plan.refusals == [.unknownCapacity(volume: "T", location: "staging directory")])
        #expect(plan.volumes.first { $0.volume == "T" }?.available == nil)
    }
}
