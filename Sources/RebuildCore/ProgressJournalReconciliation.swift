import Foundation

/// The observed state of one planned evacuation: the file at the source and at the staging path, each absent
/// (nil) or described.
public struct EvacuationObservation: Equatable, Sendable {
    public let sourcePath: String
    public let source: ObservedFile?
    public let staging: ObservedFile?

    public init(sourcePath: String, source: ObservedFile?, staging: ObservedFile?) {
        self.sourcePath = sourcePath
        self.source = source
        self.staging = staging
    }
}

/// External state as observed by the caller. Nothing in this module reads the filesystem or Music to produce it.
public struct ReconciliationSnapshot: Equatable, Sendable {
    public let evacuation: [EvacuationObservation]
    /// The persistent IDs of every registration in the library.
    public let registrationIDs: Set<String>
    public let musicRunning: Bool

    public init(evacuation: [EvacuationObservation], registrationIDs: Set<String>, musicRunning: Bool) {
        self.evacuation = evacuation
        self.registrationIDs = Set(registrationIDs.map { $0.uppercased() })
        self.musicRunning = musicRunning
    }
}

/// A disagreement between the state that the replayed journal implies and the observed state.
public enum ReconciliationProblem: Equatable, Sendable {
    case evacuationNotObserved(sourcePath: String)
    case sourceMissing(sourcePath: String)
    case sourceDiffers(sourcePath: String)
    case sourceStillPresentAfterRename(sourcePath: String)
    case stagingMissing(stagingPath: String)
    case stagingDiffers(stagingPath: String)
    case stagingUnexpectedlyPresent(stagingPath: String)
    /// An evacuation whose operation is open matches neither the state before nor the state after it.
    case openEvacuationInconsistent(sourcePath: String)
    case registrationMissing(persistentID: String)
    /// A registration that the journal records as removed is present.
    case registrationStillPresent(persistentID: String)
    /// A registration that is neither in the mapping nor among the recorded new IDs. While an `addAlbum`
    /// operation is open its new IDs are unknown, so any unexpected registration is reported then as well.
    case registrationUnexpected(persistentID: String)
    case musicRunningButMustBeClosed
}

extension ProgressJournal {
    /// Compares the external state that the replayed progress implies with an observation and reports every
    /// disagreement.
    ///
    /// A non-empty result means "refuse and reconcile". It is not an error that the program may resolve by
    /// itself.
    ///
    /// The hash chain cannot detect the removal of a valid suffix of the journal or its replacement by a valid
    /// older journal, because no independent trusted checkpoint records the head. This comparison detects a
    /// rolled-back or truncated journal whenever the operations that were rolled back changed observable state:
    /// files at the sources and in the staging directory, the registrations, and whether Music runs. It cannot
    /// detect anything that left no observable trace, such as an intent without effect, a stop, or a stage
    /// boundary. It also does not constrain the files of an evacuation whose application has been verified or is
    /// open, because the effect of the application on the staging path is not part of the recorded plan.
    public static func reconcile(record: RecoveryRecord, progress: RebuildProgress, snapshot: ReconciliationSnapshot)
        -> [ReconciliationProblem]
    {
        var found: [ReconciliationProblem] = []
        let observations = Dictionary(
            snapshot.evacuation.map { ($0.sourcePath, $0) }, uniquingKeysWith: { first, _ in first })
        let open = progress.openOperation
        let index = RecordIndex(record)

        for entry in record.evacuation {
            guard let observation = observations[entry.sourcePath] else {
                found.append(.evacuationNotObserved(sourcePath: entry.sourcePath))
                continue
            }
            guard let expected = index.inventoryByKey[PathKey.key(entry.sourcePath)] else { continue }
            if progress.isVerified(.applyFile, entry.stagingPath)
                || (open?.operation == .applyFile && open?.target == entry.stagingPath)
            {
                continue
            }
            let before = evacuationProblems(entry: entry, expected: expected, observation: observation, method: nil)
            if open?.operation == .evacuateFile && open?.target == entry.sourcePath {
                let afterRename = evacuationProblems(
                    entry: entry, expected: expected, observation: observation, method: "rename")
                let afterCopy = evacuationProblems(
                    entry: entry, expected: expected, observation: observation, method: "copy")
                if !before.isEmpty && !afterRename.isEmpty && !afterCopy.isEmpty {
                    found.append(.openEvacuationInconsistent(sourcePath: entry.sourcePath))
                }
            } else if let method = progress.evacuationMethods[entry.sourcePath] {
                found += evacuationProblems(entry: entry, expected: expected, observation: observation, method: method)
            } else {
                found += before
            }
        }

        let mapped = index.mappedIDs
        let removed = progress.verifiedSets[.removeRegistration] ?? []
        var implied = mapped.subtracting(removed).union(progress.newPersistentIDs)
        var uncertain = Set<String>()
        if open?.operation == .removeRegistration, let target = open?.target { uncertain.insert(target.uppercased()) }
        implied.subtract(uncertain)
        for id in implied.subtracting(snapshot.registrationIDs).sorted() {
            found.append(.registrationMissing(persistentID: id))
        }
        for id in snapshot.registrationIDs.subtracting(implied).subtracting(uncertain).sorted() {
            found.append(
                removed.contains(id)
                    ? .registrationStillPresent(persistentID: id) : .registrationUnexpected(persistentID: id))
        }

        let terminated = progress.verifiedCount(.terminateMusic) > 0 && !progress.completedStages.contains(.application)
        if snapshot.musicRunning && (terminated || progress.currentStage == .application) {
            found.append(.musicRunningButMustBeClosed)
        }
        return found
    }

    /// The disagreements for one evacuation: before it (`method` nil), or after a rename or a copy.
    private static func evacuationProblems(
        entry: EvacuationEntry, expected: FileRecord, observation: EvacuationObservation, method: String?
    ) -> [ReconciliationProblem] {
        var found: [ReconciliationProblem] = []
        switch method {
        case nil:
            if let source = observation.source {
                if !source.matches(expected) { found.append(.sourceDiffers(sourcePath: entry.sourcePath)) }
            } else {
                found.append(.sourceMissing(sourcePath: entry.sourcePath))
            }
            if observation.staging != nil { found.append(.stagingUnexpectedlyPresent(stagingPath: entry.stagingPath)) }
        case "copy":
            if let source = observation.source {
                if !source.matches(expected) { found.append(.sourceDiffers(sourcePath: entry.sourcePath)) }
            } else {
                found.append(.sourceMissing(sourcePath: entry.sourcePath))
            }
            found += stagingProblems(entry: entry, expected: expected, observation: observation)
        default:
            if observation.source != nil { found.append(.sourceStillPresentAfterRename(sourcePath: entry.sourcePath)) }
            found += stagingProblems(entry: entry, expected: expected, observation: observation)
        }
        return found
    }

    private static func stagingProblems(
        entry: EvacuationEntry, expected: FileRecord, observation: EvacuationObservation
    )
        -> [ReconciliationProblem]
    {
        guard let staging = observation.staging else { return [.stagingMissing(stagingPath: entry.stagingPath)] }
        return staging.matches(expected) ? [] : [.stagingDiffers(stagingPath: entry.stagingPath)]
    }
}
