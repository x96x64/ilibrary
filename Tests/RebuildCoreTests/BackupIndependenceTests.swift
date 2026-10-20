import Testing

@testable import RebuildCore

@Suite struct BackupIndependenceTests {
    func facts(
        disk: String? = "disk4", type: String? = "apfs", local: Bool? = true, image: Bool? = false
    ) -> StorageFacts {
        StorageFacts(physicalDisk: disk, filesystemType: type, isLocal: local, isDiskImage: image, interconnect: "USB")
    }

    let source = StorageFacts(
        physicalDisk: "disk0", filesystemType: "apfs", isLocal: true, isDiskImage: false, interconnect: "PCI-Express")

    func reasons(_ verdict: IndependenceVerdict) -> [IndependenceRefusal] {
        if case .refused(let list) = verdict { return list }
        return []
    }

    @Test func separateLocalApfsOrHfsIsIndependentWhenConfirmed() {
        #expect(BackupIndependence.evaluate(backup: facts(), others: [source], maintainerConfirmed: true).isIndependent)
        #expect(
            BackupIndependence.evaluate(
                backup: facts(type: "hfs"), others: [source, source], maintainerConfirmed: true
            )
            .isIndependent)
    }

    @Test func unknownBackupIdentityIsRefused() {
        let verdict = BackupIndependence.evaluate(backup: facts(disk: nil), others: [source], maintainerConfirmed: true)
        #expect(reasons(verdict) == [.unknownDeviceIdentity(location: "backup")])
        #expect(reasons(verdict).map(\.description) == ["unknown device identity of the backup"])
    }

    @Test func unknownOtherIdentityIsRefused() {
        var unknown = source
        unknown.physicalDisk = nil
        let verdict = BackupIndependence.evaluate(
            backup: facts(), others: [source, unknown], maintainerConfirmed: true)
        #expect(reasons(verdict) == [.unknownDeviceIdentity(location: "other location 2")])
    }

    @Test func sameDeviceIsRefused() {
        var same = source
        same.physicalDisk = "disk4"
        let verdict = BackupIndependence.evaluate(backup: facts(), others: [source, same], maintainerConfirmed: true)
        #expect(reasons(verdict) == [.sameDevice(location: "other location 2", disk: "disk4")])
    }

    @Test func nonLocalAndUnknownLocalityAreRefused() {
        #expect(
            reasons(
                BackupIndependence.evaluate(backup: facts(local: false), others: [source], maintainerConfirmed: true))
                == [.notLocal])
        #expect(
            reasons(BackupIndependence.evaluate(backup: facts(local: nil), others: [source], maintainerConfirmed: true))
                == [.localityUnknown])
    }

    @Test func diskImagesAndUnknownImageStatusAreRefused() {
        #expect(
            reasons(
                BackupIndependence.evaluate(backup: facts(image: true), others: [source], maintainerConfirmed: true))
                == [.diskImage])
        #expect(
            reasons(BackupIndependence.evaluate(backup: facts(image: nil), others: [source], maintainerConfirmed: true))
                == [.diskImageUnknown])
    }

    @Test func otherFilesystemsAndUnknownFilesystemAreRefused() {
        for type in ["exfat", "msdos", "ntfs", "smbfs", nil] {
            let verdict = BackupIndependence.evaluate(
                backup: facts(type: type), others: [source], maintainerConfirmed: true)
            #expect(reasons(verdict) == [.unsupportedFilesystem(type)])
        }
    }

    @Test func verdictDoesNotDependOnTheInterconnect() {
        func backup(disk: String?, interconnect: String?) -> StorageFacts {
            StorageFacts(
                physicalDisk: disk, filesystemType: "apfs", isLocal: true, isDiskImage: false,
                interconnect: interconnect)
        }
        for interconnect in [nil, "USB"] {
            let separate = BackupIndependence.evaluate(
                backup: backup(disk: "disk4", interconnect: interconnect), others: [source], maintainerConfirmed: true)
            #expect(separate.isIndependent)
            let shared = BackupIndependence.evaluate(
                backup: backup(disk: "disk0", interconnect: interconnect), others: [source], maintainerConfirmed: true)
            #expect(reasons(shared) == [.sameDevice(location: "other location 1", disk: "disk0")])
            let unknown = BackupIndependence.evaluate(
                backup: backup(disk: nil, interconnect: interconnect), others: [source], maintainerConfirmed: true)
            #expect(reasons(unknown) == [.unknownDeviceIdentity(location: "backup")])
        }
    }

    @Test func missingConfirmationIsRefused() {
        let verdict = BackupIndependence.evaluate(backup: facts(), others: [source], maintainerConfirmed: false)
        #expect(reasons(verdict) == [.notConfirmed])
    }

    @Test func everyReasonIsListed() {
        let backup = facts(disk: "disk0", type: "exfat", local: false, image: true)
        let verdict = BackupIndependence.evaluate(backup: backup, others: [source], maintainerConfirmed: false)
        #expect(reasons(verdict).count == 5)
    }
}
