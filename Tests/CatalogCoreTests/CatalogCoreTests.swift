import Foundation
import Testing

@testable import CatalogCore

func rules(_ style: TitleCase = .keep, remove: [String] = [], bracket: Bool = false, preserve: [String] = [])
    -> TitleRules
{
    TitleRules(
        TitleRuleSettings(caseStyle: style, removeQualifiers: remove, bracketNested: bracket, preserve: preserve))
}

@Suite struct TitleRuleTests {
    @Test func trailingQualifiersWithListedTermsAreRemoved() {
        let remaster = rules(remove: ["Remaster", "Remastered", "Remastered Version"])
        #expect(remaster.apply("Song (2012 Remaster)").title == "Song")
        #expect(remaster.apply("Song (Remastered)").title == "Song")
        #expect(remaster.apply("Song [Remastered Version 2015]").title == "Song")
        #expect(remaster.apply("Song (Live) (2015 Remaster)").title == "Song (Live)")
        #expect(remaster.apply("Song (Remasters Mix)").title == "Song (Remasters Mix)")
        #expect(remaster.apply("Song (Remaster) Coda").title == "Song (Remaster) Coda")
        #expect(rules().apply("Song (2012 Remaster)").title == "Song (2012 Remaster)")
    }

    @Test func nestedParentheticalsBecomeSquareBrackets() {
        let bracket = rules(bracket: true)
        #expect(bracket.apply("Under the Lights (Sam's Mix (Demo))").title == "Under the Lights [Sam's Mix (Demo)]")
        #expect(bracket.apply("Song (Demo)").title == "Song (Demo)")
        let unbalanced = bracket.apply("Song (Demo")
        #expect(unbalanced.title == "Song (Demo")
        #expect(unbalanced.reviews.map(\.reason) == ["unbalanced parentheses"])
    }

    @Test func mlaAndAPADifferForLongPrepositions() {
        #expect(rules(.mla).apply("walk with you").title == "Walk with You")
        #expect(rules(.apa).apply("walk with you").title == "Walk With You")
        #expect(rules(.start).apply("walk with you").title == "Walk With You")
        #expect(rules(.keep).apply("walk with you").title == "walk with you")
    }

    @Test func mlaLowercasesMinorWordsExceptFirstAndLast() {
        let mla = rules(.mla)
        #expect(mla.apply("the way the river runs").title == "The Way the River Runs")
        #expect(mla.apply("a Song For The Lovers And The Thieves").title == "A Song for the Lovers and the Thieves")
        #expect(mla.apply("what dreams are made of").title == "What Dreams Are Made Of")
        #expect(mla.apply("rock-a-bye baby").title == "Rock-a-Bye Baby")
        #expect(mla.apply("songs from the road: live at the hall").title == "Songs from the Road: Live at the Hall")
    }

    @Test func roleDependentWordsAreLeftUnchangedAndReported() {
        let mla = rules(.mla).apply("turn it up tonight")
        #expect(mla.title == "Turn It up Tonight")
        #expect(mla.reviews.map(\.word) == ["up"])
        let apa = rules(.apa).apply("turn it up")
        #expect(apa.title == "Turn It up")
        #expect(apa.reviews.map(\.word) == ["up"])
    }

    @Test func protectedWordsAreNeverChanged() {
        let mla = rules(.mla, preserve: ["HIGHway", "Q.R.S."])
        #expect(mla.apply("HIGHway and ZENITH").title == "HIGHway and ZENITH")
        #expect(mla.apply("Q.R.S. (quiet river song)").title == "Q.R.S. (Quiet River Song)")
        #expect(mla.apply("iTunes in the city").title == "iTunes in the City")
        #expect(mla.apply("君の名は").title == "君の名は")
        #expect(mla.apply("song for 東京").title == "Song for 東京")
        #expect(mla.apply("song for café").title == "Song for Café")
    }

    @Test func apostrophesStayWithinWords() {
        #expect(rules(.start).apply("don't wait 'til morning comes").title == "Don't Wait 'Til Morning Comes")
        let mla = rules(.mla).apply("Don't Wait 'Til Morning Comes")
        #expect(mla.title == "Don't Wait 'Til Morning Comes")
        #expect(mla.reviews.map(\.word) == ["'Til"])
    }

    @Test func parentheticalsAndBracketsStartNewSegments() {
        #expect(
            rules(.start).apply("under the lights [sam's mix (demo)]").title == "Under The Lights [Sam's Mix (Demo)]")
        #expect(rules(.mla).apply("song of the year (the remix)").title == "Song of the Year (The Remix)")
    }

    @Test func matchingKeysIgnoreQualifiersCaseWidthAndDiacritics() {
        let key = rules(remove: ["Remaster"])
        #expect(key.matchingKey("Midnight Garden (2012 Remaster)") == key.matchingKey("MIDNIGHT GARDEN"))
        #expect(key.matchingKey("Mix [Demo]") == key.matchingKey("mix (demo)"))
        #expect(key.matchingKey("Don\u{2019}t") == key.matchingKey("Don't"))
        #expect(key.matchingKey("ＡＢＣ  Song") == key.matchingKey("abc song"))
        #expect(key.matchingKey("Beyoncé") == key.matchingKey("Beyonce"))
        #expect(key.matchingKey("Song A") != key.matchingKey("Song B"))
    }
}

@Suite struct MatchingTests {
    static let catalog = Catalog(
        titleRules: TitleRuleSettings(removeQualifiers: ["Remaster"]),
        albums: [
            Album(
                album: "Example Album", aliases: ["Example Album (Deluxe)"], albumArtist: "Example Artist",
                discs: [
                    Disc(tracks: ["A1", "A2", "A3"].map { Track(title: $0) }),
                    Disc(tracks: ["B1", "B2", "B3", "B4", "B5", "B6"].map { Track(title: $0) }),
                ]),
            Album(album: "Greatest Hits", albumArtist: "First Artist", discs: [Disc(tracks: [Track(title: "Hit")])]),
            Album(album: "Greatest Hits", albumArtist: "Second Artist", discs: [Disc(tracks: [Track(title: "Hit")])]),
        ])

    func match(_ files: [FileTags]) -> MatchReport { CatalogMatcher(catalog: MatchingTests.catalog).match(files) }

    func file(_ album: String?, _ disc: Int?, _ track: Int?, _ title: String?, artist: String? = nil) -> FileTags {
        FileTags(
            path: "\(disc ?? 0)-\(track ?? 0) \(title ?? "")", album: album, albumArtist: artist, discNumber: disc,
            trackNumber: track, title: title)
    }

    @Test func discAndTrackNumbersAreConfirmedByTitles() {
        let report = match([file("Example Album", 1, 2, "A2"), file("Example Album", 2, 1, "B1")])
        #expect(report.matches.map(\.method) == [.discAndTrack, .discAndTrack])
        #expect(report.matches.allSatisfy { $0.titleConfirmed })
        #expect(report.unmatched.isEmpty)
    }

    @Test func continuousNumberingIsRecognizedWhereDiscNumbersWouldMislead() {
        // Track 4 of disc 2 exists, but its title shows that the file is the first track of disc 2.
        let report = match([file("Example Album", 2, 4, "B1"), file("Example Album", 2, 9, "B6")])
        #expect(report.matches.map(\.method) == [.continuousNumbering, .continuousNumbering])
        #expect(
            report.matches.map(\.reference) == [
                TrackReference(album: 0, disc: 2, track: 1), TrackReference(album: 0, disc: 2, track: 6),
            ])
    }

    @Test func titlesAreTheLastResort() {
        let report = match([file("Example Album", nil, nil, "A3"), file("Example Album", 1, 2, "B5 (2012 Remaster)")])
        #expect(report.matches.map(\.method) == [.title, .title])
        // Matches are reported in catalog order.
        #expect(
            report.matches.map(\.reference) == [
                TrackReference(album: 0, disc: 1, track: 3), TrackReference(album: 0, disc: 2, track: 5),
            ])
    }

    @Test func aliasesAndAlbumArtistsSelectTheAlbum() {
        let report = match([
            file("Example Album (Deluxe)", 1, 1, "A1"), file("Greatest Hits", 1, 1, "Hit", artist: "Second Artist"),
        ])
        #expect(report.matches.map(\.reference.album) == [0, 2])
        let ambiguous = match([file("Greatest Hits", 1, 1, "Hit")])
        #expect(ambiguous.unmatched.map(\.reason) == ["album \"Greatest Hits\" matches 2 catalog albums"])
    }

    @Test func refusalsAreReportedWithReasons() {
        let report = match([
            file(nil, 1, 1, "A1"), file("Unknown Album", 1, 1, "A1"), file("Example Album", 1, 1, "Something Else"),
        ])
        #expect(report.matches.isEmpty)
        #expect(
            report.unmatched.map(\.reason) == [
                "the file has no album name", "album \"Unknown Album\" is not in the catalog",
                "the titles of 1 files differ from those of \"Example Album\" at their disc and track numbers, and only 0 agree; check the numbering and the album",
            ])
    }

    @Test func albumsRefusedAsAWholeAreReportedInAlbumOrder() {
        // The later album is given first, and the order of the unmatched files must still follow the catalog.
        let report = match([
            file("Greatest Hits", 1, 1, "Wrong Hit", artist: "Second Artist"), file("Example Album", 1, 1, "Wrong A"),
        ])
        #expect(report.matches.isEmpty)
        #expect(report.unmatched.map(\.file.path) == ["1-1 Wrong A", "1-1 Wrong Hit"])
    }

    @Test func aCorrectedTitleIsAcceptedWhileMostTitlesAgree() {
        let report = match([
            file("Example Album", 1, 1, "A1"), file("Example Album", 1, 2, "A2 Misspelt"),
            file("Example Album", 1, 3, "A3"),
        ])
        #expect(report.unmatched.isEmpty)
        #expect(report.matches.map(\.titleDiffers) == [false, true, false])
        #expect(report.matches[1].reference == TrackReference(album: 0, disc: 1, track: 2))
        // Files without a title tag do not support a correction; only agreeing titles do.
        let untitled = match([
            file("Example Album", 1, 1, nil), file("Example Album", 1, 2, "A2 Misspelt"),
            file("Example Album", 1, 3, nil),
        ])
        #expect(untitled.matches.isEmpty)
        #expect(untitled.unmatched.count == 3)
        let balanced = match([file("Example Album", 1, 1, "A1"), file("Example Album", 1, 2, "A2 Misspelt")])
        #expect(balanced.matches.isEmpty)
        // A title that belongs to another track is never overridden by numbers.
        let swapped = match([file("Example Album", 1, 1, "A2"), file("Example Album", 1, 2, "A1")])
        #expect(swapped.matches.map(\.method) == [.title, .title])
    }

    @Test func filesClaimingTheSameTrackAreBothRefused() {
        let report = match([file("Example Album", 1, 1, "A1"), file("Example Album", 1, 1, nil)])
        #expect(report.matches.isEmpty)
        #expect(report.unmatched.count == 2)
    }

    @Test func untitledFilesMatchByNumberWithoutConfirmation() {
        let report = match([file("Example Album", 1, 3, nil)])
        #expect(report.matches.map(\.titleConfirmed) == [false])
        #expect(report.missing.count == 8)
    }
}

@Suite struct NamingTests {
    @Test func fileNamesFollowTheMusicApp() {
        #expect(Naming.fileName(title: "Walk with You", disc: 1, track: 3, discCount: 1) == "03 Walk with You.m4a")
        #expect(Naming.fileName(title: "First Song", disc: 2, track: 1, discCount: 2) == "2-01 First Song.m4a")
        #expect(Naming.fileName(title: "Title: Part 1/2", disc: 1, track: 12, discCount: 1) == "12 Title_ Part 1_2.m4a")
        #expect(Naming.fileName(title: "Long", disc: 1, track: 100, discCount: 1) == "100 Long.m4a")
    }

    @Test func pathsUseTheAlbumArtistAndAlbum() throws {
        let catalog = Catalog(albums: [
            Album(album: "Live: 1/2", albumArtist: "AC/DC", discs: [Disc(tracks: [Track(title: "Song")])]),
            Album(album: "No Artist", discs: [Disc(tracks: [Track(title: "Song")])]),
        ])
        let tracks = catalog.resolvedTracks()
        #expect(Naming.relativePath(for: tracks[0]) == ["AC_DC", "Live_ 1_2", "01 Song.m4a"])
        #expect(Naming.relativePath(for: tracks[1]) == nil)
    }
}

@Suite struct OrderingTests {
    static let catalog = Catalog(albums: [
        Album(album: "Bravo", albumArtist: "Beta", releaseDate: "1982-11-30", discs: []),
        Album(album: "Alpha", albumArtist: "Beta", releaseDate: "1979-08-10", discs: []),
        Album(album: "Charlie", albumArtist: "alpha", releaseDate: "1987-08-31", discs: []),
        Album(album: "Delta", albumArtist: "Älpha", discs: []),
        Album(album: "Echo", albumArtist: "Gamma", releaseDate: "1979-08-10", discs: []),
    ])

    @Test func releaseOrder() {
        #expect(OrderingTests.catalog.albumOrder(.release) == [1, 4, 0, 2, 3])
    }

    @Test func artistOrdersSortAlbumsInTheSameDirection() {
        #expect(OrderingTests.catalog.albumOrder(.artist) == [2, 3, 1, 0, 4])
        #expect(OrderingTests.catalog.albumOrder(.artistDescending) == [4, 0, 1, 3, 2])
    }

    @Test func artistReleaseOrderSortsAlbumsByDate() {
        #expect(OrderingTests.catalog.albumOrder(.artistRelease) == [2, 3, 1, 0, 4])
        #expect(AlbumOrder(rawValue: "artist-desc") == .artistDescending)
        #expect(AlbumOrder.allCases.map(\.rawValue) == ["release", "artist", "artist-desc", "artist-release"])
    }
}
