import Foundation
import Testing

@testable import GUIProbeMac

@Suite struct ClassificationTests {
    func content(_ items: Int, at elapsed: Double, scrollable: Bool? = false) -> ViewReading {
        var reading = Fixtures.empty(at: elapsed)
        reading.contentItemCount = items
        reading.totalItemCount = items
        reading.placeholderPresent = false
        reading.scrollable = scrollable
        return reading
    }

    @Test func aFullySupportedEmptyCaseIsACandidateForBothViewsAndCombined() {
        let songs = Fixtures.classify(Fixtures.emptyReadings, view: .songs)
        let recent = Fixtures.classify(Fixtures.emptyReadings, view: .recentlyAdded)
        guard case .candidateEmpty(let evidence) = songs else {
            Issue.record("expected a candidate, got \(songs)")
            return
        }
        #expect(evidence.contains(.inventoryZero))
        #expect(evidence.contains(.placeholderPresent))
        #expect(recent.outcome == "candidateEmpty")
        #expect(Classifier.combine(songs, recent).outcome == "candidateEmpty")
    }

    @Test func zeroRowsReportedCompletelyAreEnoughWithoutAPlaceholder() {
        let readings = Fixtures.emptyReadings.map { reading -> ViewReading in
            var copy = reading
            copy.placeholderPresent = nil
            return copy
        }
        #expect(Fixtures.classify(readings).outcome == "candidateEmpty")
    }

    @Test func oneRemainingTrackIsNonEmpty() {
        let readings = [content(1, at: 0), content(1, at: 3), content(1, at: 6)]
        #expect(
            Fixtures.classify(readings, inventory: 1)
                == .verifiedNonEmpty(reasons: [
                    .visibleContent(items: 1), .inventoryCountPositive(count: 1),
                ]))
    }

    @Test func multipleAlbumsAreNonEmptyEvenWithoutInventory() {
        let verdict = Fixtures.classify([content(40, at: 0)], inventory: nil)
        #expect(verdict == .verifiedNonEmpty(reasons: [.visibleContent(items: 40)]))
    }

    @Test func contentInAnyReadingProvesNonEmptinessWhenReadingsChange() {
        let readings = [Fixtures.empty(at: 0), content(2, at: 3), Fixtures.empty(at: 6)]
        #expect(Fixtures.classify(readings).outcome == "verifiedNonEmpty")
    }

    @Test func contentCountedInAnIncompleteTreeDoesNotVerify() {
        var reading = content(5, at: 0)
        reading.treeStatus = .truncatedByLimit
        let verdict = Fixtures.classify([reading], inventory: 0)
        #expect(verdict.outcome == "indeterminate")
        #expect(Fixtures.reasons(verdict).contains(.treeIncomplete))
    }

    @Test func contentOutsideTheVisibleRegionIsNotEmpty() {
        let readings = Fixtures.emptyReadings.map { reading -> ViewReading in
            var copy = reading
            copy.placeholderPresent = false
            copy.scrollable = true
            copy.totalItemCount = 12
            return copy
        }
        let verdict = Fixtures.classify(readings, inventory: 12)
        #expect(verdict.outcome == "indeterminate")
        #expect(Fixtures.reasons(verdict).contains(.scrollableOrUnknown))
        #expect(Fixtures.reasons(verdict).contains(.noPositiveEmptyEvidence))
        #expect(Fixtures.reasons(verdict).contains(.inventoryContradictsView(count: 12)))
    }

    @Test func totalRowsAboveZeroWithoutPlaceholderIsNotEmpty() {
        let readings = Fixtures.emptyReadings.map { reading -> ViewReading in
            var copy = reading
            copy.placeholderPresent = nil
            copy.totalItemCount = 3
            return copy
        }
        #expect(Fixtures.reasons(Fixtures.classify(readings)).contains(.noPositiveEmptyEvidence))
    }

    @Test func loadingAndUnknownLoadingAreIndeterminate() {
        let busy = Fixtures.emptyReadings.map { reading -> ViewReading in
            var copy = reading
            copy.busy = true
            return copy
        }
        #expect(Fixtures.reasons(Fixtures.classify(busy)).contains(.loading))
        let unknown = Fixtures.emptyReadings.map { reading -> ViewReading in
            var copy = reading
            copy.busy = nil
            return copy
        }
        #expect(Fixtures.reasons(Fixtures.classify(unknown)).contains(.loadingUnknown))
    }

    @Test func unknownScrollabilityIsIndeterminate() {
        let readings = Fixtures.emptyReadings.map { reading -> ViewReading in
            var copy = reading
            copy.scrollable = nil
            return copy
        }
        #expect(Fixtures.reasons(Fixtures.classify(readings)).contains(.scrollableOrUnknown))
    }

    @Test func disagreeingReadingsAreIndeterminate() {
        var middle = Fixtures.empty(at: 3)
        middle.totalItemCount = nil
        let verdict = Fixtures.classify([Fixtures.empty(at: 0), middle, Fixtures.empty(at: 6)])
        #expect(Fixtures.reasons(verdict).contains(.readingsDisagree))
    }

    @Test func tooFewReadingsAreIndeterminate() {
        let verdict = Fixtures.classify([Fixtures.empty(at: 0), Fixtures.empty(at: 9)])
        #expect(Fixtures.reasons(verdict) == [.notEnoughReadings(have: 2, need: 3)])
    }

    @Test func aShortSpanIsIndeterminate() {
        let verdict = Fixtures.classify([Fixtures.empty(at: 0), Fixtures.empty(at: 1), Fixtures.empty(at: 2)])
        #expect(Fixtures.reasons(verdict) == [.spanTooShort])
    }

    @Test func noReadingsAreIndeterminate() {
        let verdict = Fixtures.classify([])
        #expect(verdict.outcome == "indeterminate")
        #expect(Fixtures.reasons(verdict).contains(.notEnoughReadings(have: 0, need: 3)))
    }

    @Test func missingInventoryAndPositiveInventoryAreIndeterminate() {
        #expect(
            Fixtures.reasons(Fixtures.classify(Fixtures.emptyReadings, inventory: nil)) == [.inventoryEvidenceMissing])
        #expect(
            Fixtures.reasons(Fixtures.classify(Fixtures.emptyReadings, inventory: 4))
                == [.inventoryContradictsView(count: 4)])
    }

    @Test func noPlaceholderAndIncompleteRowsGiveNoPositiveEvidence() {
        var profile = Fixtures.profile()
        profile.songs.rowsComplete = false
        let readings = Fixtures.emptyReadings.map { reading -> ViewReading in
            var copy = reading
            copy.placeholderPresent = false
            return copy
        }
        let verdict = Fixtures.classify(readings, profile: profile)
        #expect(Fixtures.reasons(verdict) == [.noPositiveEmptyEvidence])
    }

    enum Defect: CaseIterable, Sendable {
        case viewNotIdentified, containerMissing, unexpectedStructure, unknownLabel, timedOut, truncated
        case attributeError, notFound

        var expected: Reason {
            switch self {
            case .viewNotIdentified: .viewNotIdentified
            case .containerMissing: .containerMissing
            case .unexpectedStructure: .unexpectedStructure
            case .unknownLabel: .unknownLabel
            case .timedOut: .timedOut
            case .truncated, .attributeError, .notFound: .treeIncomplete
            }
        }

        func apply(to reading: inout ViewReading) {
            switch self {
            case .viewNotIdentified: reading.viewIdentified = false
            case .containerMissing: reading.containerFound = false
            case .unexpectedStructure: reading.unexpectedStructure = true
            case .unknownLabel: reading.unknownLabel = true
            case .timedOut: reading.treeStatus = .timedOut
            case .truncated: reading.treeStatus = .truncatedByLimit
            case .attributeError: reading.treeStatus = .attributeError
            case .notFound: reading.treeStatus = .notFound
            }
        }
    }

    @Test(arguments: Defect.allCases)
    func eachStructuralDefectIsIndeterminate(defect: Defect) {
        var readings = Fixtures.emptyReadings
        defect.apply(to: &readings[1])
        let verdict = Fixtures.classify(readings)
        #expect(verdict.outcome == "indeterminate")
        #expect(Fixtures.reasons(verdict).contains(defect.expected))
    }

    enum PreflightFlag: CaseIterable, Sendable {
        case separateTestUser, syntheticLibrary, noAppleAccount, noCloudLibrary, userPattern, trusted
        case macOSVersion, musicVersion, profile

        func clear(_ preflight: inout Preflight) {
            switch self {
            case .separateTestUser: preflight.operatorConfirmedSeparateTestUser = false
            case .syntheticLibrary: preflight.operatorConfirmedSyntheticLibrary = false
            case .noAppleAccount: preflight.operatorConfirmedNoAppleAccount = false
            case .noCloudLibrary: preflight.operatorConfirmedNoCloudLibrary = false
            case .userPattern: preflight.processUserMatchesTestUserPattern = false
            case .trusted: preflight.accessibilityTrusted = false
            case .macOSVersion: preflight.macOSVersionPresent = false
            case .musicVersion: preflight.musicVersionPresent = false
            case .profile: preflight.profileSupplied = false
            }
        }
    }

    @Test(arguments: PreflightFlag.allCases)
    func eachPreflightFailureIsIndeterminateEvenWithContent(flag: PreflightFlag) {
        var preflight = Fixtures.preflight
        flag.clear(&preflight)
        #expect(preflight.failures.count == 1)
        for readings in [Fixtures.emptyReadings, [content(3, at: 0)]] {
            let verdict = Fixtures.classify(readings, preflight: preflight)
            #expect(verdict.outcome == "indeterminate")
            #expect(!Fixtures.reasons(verdict).isEmpty)
        }
    }

    @Test(arguments: [MusicProcessState.none, .terminated, .multiple])
    func aMusicProcessThatIsNotExactlyOneIsIndeterminate(state: MusicProcessState) {
        var preflight = Fixtures.preflight
        preflight.musicProcess = state
        #expect(Fixtures.classify(Fixtures.emptyReadings, preflight: preflight).outcome == "indeterminate")
    }

    @Test func noProfileGivesTheReviewedProfileReason() {
        var preflight = Fixtures.preflight
        preflight.profileSupplied = false
        let verdict = Fixtures.classify(Fixtures.emptyReadings, preflight: preflight, profile: nil)
        #expect(Fixtures.reasons(verdict) == [.noReviewedProfile])
        #expect(Fixtures.classify([content(9, at: 0)], preflight: preflight, profile: nil).outcome == "indeterminate")
    }

    @Test(arguments: [
        ObservedContext(macOSVersion: "Version 98.0", musicVersion: Fixtures.music, locale: Fixtures.locale),
        ObservedContext(macOSVersion: Fixtures.macOS, musicVersion: "98.1", locale: Fixtures.locale),
        ObservedContext(macOSVersion: Fixtures.macOS, musicVersion: Fixtures.music, locale: "ja_JP"),
        ObservedContext(macOSVersion: Fixtures.macOS, musicVersion: Fixtures.music, locale: nil),
    ])
    func aVersionOrLocaleMismatchIsIndeterminate(context: ObservedContext) {
        #expect(Fixtures.reasons(Fixtures.classify(Fixtures.emptyReadings, context: context)) == [.versionMismatch])
    }

    @Test(
        arguments: [
            nil, Stability(minimumReadings: 0, minimumSpanSeconds: 1),
            Stability(minimumReadings: 3, minimumSpanSeconds: -1),
            Stability(minimumReadings: 3, minimumSpanSeconds: .nan),
            Stability(minimumReadings: 1, minimumSpanSeconds: 4),
            Stability(minimumReadings: 3, minimumSpanSeconds: 0),
        ] as [Stability?])
    func anAbsentOrUnusableStabilityIsUnqualified(stability: Stability?) {
        let verdict = Fixtures.classify(Fixtures.emptyReadings, profile: Fixtures.profile(stability: stability))
        #expect(Fixtures.reasons(verdict) == [.stabilityUnqualified])
    }

    @Test func aStoppedObservationIsNeverACandidateForEmptiness() {
        let empty = Fixtures.classify(Fixtures.emptyReadings)
        guard case .candidateEmpty = empty else {
            Issue.record("expected the fixture to be a candidate for emptiness")
            return
        }
        #expect(Classifier.stopped(empty) == .indeterminate(reasons: [.runStopped]))
        let content = Classifier.stopped(.verifiedNonEmpty(reasons: [.visibleContent(items: 1)]))
        #expect(content == .verifiedNonEmpty(reasons: [.visibleContent(items: 1)]))
        #expect(
            Classifier.stopped(.indeterminate(reasons: [.loading])) == .indeterminate(reasons: [.loading, .runStopped]))
    }

    @Test func noReadingsAreNeverEmpty() {
        let verdict = Fixtures.classify([])
        #expect(Fixtures.reasons(verdict) == [.notEnoughReadings(have: 0, need: 3)])
    }

    @Test func aNegativeInventoryCountIsInvalidEvidence() {
        #expect(
            Fixtures.reasons(Fixtures.classify(Fixtures.emptyReadings, inventory: -1)) == [.inventoryEvidenceInvalid])
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteElapsedValuesFailTheSpan(value: Double) {
        let verdict = Fixtures.classify([Fixtures.empty(at: 0), Fixtures.empty(at: 3), Fixtures.empty(at: value)])
        #expect(verdict.outcome == "indeterminate")
        #expect(Fixtures.reasons(verdict).contains(.spanTooShort))
        let allNaN = Fixtures.classify([Fixtures.empty(at: .nan), Fixtures.empty(at: .nan), Fixtures.empty(at: .nan)])
        #expect(allNaN.outcome == "indeterminate")
    }

    @Test func aPlaceholderWithANonZeroCompleteRowTotalIsContradictory() {
        let readings = Fixtures.emptyReadings.map { reading -> ViewReading in
            var copy = reading
            copy.totalItemCount = 2
            return copy
        }
        let verdict = Fixtures.classify(readings)
        #expect(verdict.outcome == "indeterminate")
        #expect(Fixtures.reasons(verdict).contains(.contradictoryRowTotal))
        var incomplete = Fixtures.profile()
        incomplete.songs.rowsComplete = false
        #expect(!Fixtures.reasons(Fixtures.classify(readings, profile: incomplete)).contains(.contradictoryRowTotal))
    }

    @Test func combinationFollowsTheSafeDirection() {
        let empty = Verdict.candidateEmpty(evidence: [.inventoryZero])
        let non = Verdict.verifiedNonEmpty(reasons: [.visibleContent(items: 1)])
        let unknown = Verdict.indeterminate(reasons: [.loading])
        #expect(Classifier.combine(empty, non) == non)
        #expect(Classifier.combine(unknown, non) == non)
        #expect(Classifier.combine(non, unknown) == non)
        #expect(Classifier.combine(empty, unknown) == unknown)
        #expect(Classifier.combine(unknown, empty) == unknown)
        #expect(Classifier.combine(unknown, unknown) == unknown)
        #expect(Classifier.combine(empty, empty).outcome == "candidateEmpty")
    }

    @Test func descriptionsAreFixedAndCarryNoPersonalContent() {
        let reasons: [Reason] = [
            .separateTestUserUnconfirmed, .userNameDoesNotMatchPattern, .notEnoughReadings(have: 1, need: 3),
            .inventoryContradictsView(count: 2), .visibleContent(items: 4), .noReviewedProfile,
        ]
        for reason in reasons { #expect(!reason.description.isEmpty) }
        #expect(
            Reason.notEnoughReadings(have: 1, need: 3).description == "only 1 of the required 3 readings were taken")
    }

    @Test func theTestUserPatternMatchesM11Probe() {
        #expect(Preflight.isTestUserName("ilibrarytest"))
        #expect(Preflight.isTestUserName("ilibrary-test2"))
        #expect(!Preflight.isTestUserName("someone"))
        #expect(!Preflight.isTestUserName("xilibrarytest"))
        #expect(!Preflight.isTestUserName("ilibrarytest user"))
        #expect(!Preflight.isTestUserName(""))
    }
}
