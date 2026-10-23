import Foundation
import Testing

@testable import CatalogCore

let exampleCatalog = #"""
    {
      "format": "ilibrary-catalog-1",
      "titleRules": {
        "case": "keep",
        "removeQualifiers": ["Remaster", "Remastered", "Remastered Version"],
        "bracketNested": true,
        "preserve": ["SyNTH", "ABCDE", "X.Y.Z."]
      },
      "artists": { "Example Artist": { "folderDate": "1980-01-01" } },
      "albums": [
        {
          "album": "Example Album",
          "aliases": ["Example Album (Remastered)"],
          "albumArtist": "Example Artist",
          "artist": "Example Artist",
          "genre": "Pop",
          "copyright": "℗ 1980 Example Records, Inc.",
          "releaseDate": "1980-06-01",
          "artwork": "artwork/Example Album.png",
          "notes": "Copyright verified on the distributor's album page.",
          "sources": ["https://example.com/album"],
          "discs": [
            { "tracks": [ { "title": "First Song", "composer": "Example Writer, Second Writer" } ] }
          ]
        }
      ]
    }
    """#

func validate(_ text: String) -> CatalogValidationResult { Catalog.validate(Data(text.utf8)) }

func replacing(_ old: String, _ new: String) -> String {
    precondition(exampleCatalog.contains(old), old)
    return exampleCatalog.replacingOccurrences(of: old, with: new)
}

@Suite struct ValidationTests {
    @Test func theExampleCatalogIsValid() throws {
        let result = validate(exampleCatalog)
        #expect(result.diagnostics.isEmpty)
        let catalog = try #require(result.catalog)
        #expect(catalog.titleRules?.caseStyle == .keep)
        #expect(catalog.artists?["Example Artist"]?.folderDate == "1980-01-01")
        #expect(catalog.albums[0].discs[0].tracks[0].composer == "Example Writer, Second Writer")
    }

    @Test func encodingRoundTrips() throws {
        let catalog = try #require(validate(exampleCatalog).catalog)
        let reencoded = try #require(Catalog.validate(try catalog.encoded()).catalog)
        #expect(reencoded == catalog)
        #expect(try catalog.encoded().last == 0x0A)
    }

    @Test func unrelatedDocumentsAreRejected() {
        #expect(validate("not json").errors.map(\.message) == ["the document is not valid JSON"])
        #expect(validate("[1, 2]").errors.map(\.message) == ["the document must be a JSON object"])
        #expect(validate(#"{"albums": []}"#).errors.first?.path == "format")
        let future = validate(replacing(#""format": "ilibrary-catalog-1""#, #""format": "ilibrary-catalog-2""#))
        #expect(future.errors.first?.message.contains("is not supported") == true)
        #expect(future.catalog == nil)
    }

    @Test func unknownFieldsAreReportedWithTheirPaths() {
        let result = validate(replacing(#""genre": "Pop""#, #""genre": "Pop", "relaseDate": "1980-06-01""#))
        #expect(result.errors.map(\.path) == ["albums[0].relaseDate"])
        #expect(result.catalog == nil)
    }

    @Test func typesAndRequiredValuesAreChecked() {
        let types = validate(replacing(#""bracketNested": true"#, #""bracketNested": "yes""#))
        #expect(types.errors.map(\.path) == ["titleRules.bracketNested"])
        let caseStyle = validate(replacing(#""case": "keep""#, #""case": "title""#))
        #expect(caseStyle.errors.map(\.path) == ["titleRules.case"])
        let title = validate(replacing(#""title": "First Song""#, #""title": " ""#))
        #expect(title.errors.map(\.path) == ["albums[0].discs[0].tracks[0].title"])
        let missing = validate(replacing(#""title": "First Song", "#, ""))
        #expect(missing.errors.map(\.path) == ["albums[0].discs[0].tracks[0].title"])
        let discs = validate(
            replacing(#"{ "tracks": [ { "title": "First Song", "composer": "Example Writer, Second Writer" } ] }"#, ""))
        #expect(discs.errors.map(\.path) == ["albums[0].discs"])
        let aliases = validate(replacing(#"["Example Album (Remastered)"]"#, #"["Example Album (Remastered)", 3]"#))
        #expect(aliases.errors.map(\.path) == ["albums[0].aliases[1]"])
    }

    @Test(arguments: ["1980-02-30", "1980-13-01", "1980-6-1", "80-06-01", "１９８０-06-01", "1900-02-29"])
    func invalidDatesAreRejected(date: String) {
        let result = validate(replacing(#""releaseDate": "1980-06-01""#, #""releaseDate": "\#(date)""#))
        #expect(result.errors.map(\.path) == ["albums[0].releaseDate"])
    }

    @Test func titleRulesApplyToResolvedTitles() throws {
        let unchanged = try #require(validate(exampleCatalog).catalog)
        #expect(unchanged.resolvedTracks()[0].title == "First Song")
        let text = replacing(#""case": "keep""#, #""case": "mla""#)
            .replacingOccurrences(of: #""First Song""#, with: #""song alpha for song bravo (2012 Remaster)""#)
        let result = validate(text)
        #expect(result.diagnostics.isEmpty)
        let catalog = try #require(result.catalog)
        #expect(catalog.resolvedTracks()[0].title == "Song Alpha for Song Bravo")
        #expect(catalog.resolve(TrackReference(album: 0, disc: 1, track: 1)).title == "Song Alpha for Song Bravo")
        #expect(catalog.albums[0].discs[0].tracks[0].title == "song alpha for song bravo (2012 Remaster)")
    }

    @Test func aTitleThatTheRulesWouldEmptyIsRejected() {
        let result = validate(replacing(#""First Song""#, #""(2012 Remaster)""#))
        #expect(result.errors.map(\.path) == ["albums[0].discs[0].tracks[0].title"])
        #expect(result.errors.first?.message == "is empty after the title rules are applied")
        #expect(result.catalog == nil)
    }

    @Test func titleReviewsAreWarnings() throws {
        let text = replacing(#""case": "keep""#, #""case": "mla""#)
            .replacingOccurrences(of: #""First Song""#, with: #""song alpha on song bravo""#)
        let result = validate(text)
        #expect(result.errors.isEmpty)
        #expect(result.warnings.map(\.path) == ["albums[0].discs[0].tracks[0].title"])
        #expect(result.warnings.first?.message.hasPrefix("\"on\": MLA capitalization depends") == true)
        #expect(try #require(result.catalog).resolvedTracks()[0].title == "Song Alpha on Song Bravo")
    }

    @Test func emptyValuesMeanUnknown() throws {
        let result = validate(replacing(#""releaseDate": "1980-06-01""#, #""releaseDate": """#))
        #expect(result.diagnostics.isEmpty)
        let catalog = try #require(result.catalog)
        #expect(catalog.resolvedTracks()[0].releaseDate == nil)
    }

    @Test func duplicateAlbumsOfTheSameArtistAreRejected() {
        let album =
            #"{ "album": "Example Album", "albumArtist": "Example Artist", "discs": [ { "tracks": [ { "title": "X" } ] } ] }"#
        let result = validate(replacing(#""albums": ["#, #""albums": [ \#(album), "#))
        #expect(result.errors.map(\.path) == ["albums[1]"])
        let other = album.replacingOccurrences(of: "\"Example Artist\"", with: "\"Other Artist\"")
        #expect(validate(replacing(#""albums": ["#, #""albums": [ \#(other), "#)).errors.isEmpty)
    }

    @Test func conventionsProduceWarnings() {
        let copyright = validate(replacing("℗ 1980", "(P) 1980"))
        #expect(copyright.warnings.map(\.path) == ["albums[0].copyright"])
        #expect(copyright.catalog != nil)
        let empty = validate(#"{"format": "ilibrary-catalog-1", "albums": []}"#)
        #expect(empty.warnings.map(\.path) == ["albums"])
    }
}

@Suite struct SchemaTests {
    static var schemaURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/schema/ilibrary-catalog-1.schema.json")
    }

    @Test func thePublishedSchemaIsTheEmbeddedSchema() throws {
        let published = try String(contentsOf: SchemaTests.schemaURL, encoding: .utf8)
        #expect(published == Catalog.jsonSchema + "\n")
    }

    func object(_ value: JSONValue?, _ path: [String]) -> [String: JSONValue] {
        var current = value
        for key in path {
            guard case .object(let object)? = current else { return [:] }
            current = object[key]
        }
        if case .object(let object)? = current { return object }
        return [:]
    }

    func strings(_ value: JSONValue?) -> [String] {
        guard case .array(let items)? = value else { return [] }
        return items.compactMap { if case .string(let text) = $0 { return text } else { return nil } }
    }

    @Test func theSchemaDescribesTheFieldsThatValidationAccepts() throws {
        let schema = try JSONDecoder().decode(JSONValue.self, from: Data(Catalog.jsonSchema.utf8))
        let definitions: [(path: [String], fields: [String], required: [String])] = [
            ([], CatalogFields.root, CatalogFields.rootRequired),
            (["$defs", "titleRules"], CatalogFields.titleRules, []),
            (["$defs", "artist"], CatalogFields.artist, []),
            (["$defs", "album"], CatalogFields.album, CatalogFields.albumRequired),
            (["$defs", "disc"], CatalogFields.disc, CatalogFields.discRequired),
            (["$defs", "track"], CatalogFields.track, CatalogFields.trackRequired),
        ]
        for definition in definitions {
            let object = self.object(schema, definition.path)
            #expect(
                Set(self.object(.object(object), ["properties"]).keys) == Set(definition.fields), "\(definition.path)")
            #expect(strings(object["required"]) == definition.required, "\(definition.path)")
            #expect(object["additionalProperties"] == .bool(false), "\(definition.path)")
        }
    }
}

@Suite struct ReleaseDateTests {
    @Test func datesAreParsedStrictly() {
        #expect(ReleaseDate("2000-02-29")?.description == "2000-02-29")
        #expect(ReleaseDate("2024-02-29") != nil)
        #expect(ReleaseDate("1900-02-29") == nil)
        #expect(ReleaseDate("1980-06-31") == nil)
        #expect(ReleaseDate("1980-06-01 ") == nil)
        #expect(ReleaseDate("0000-01-01") == nil)
        #expect(ReleaseDate("1958-03-01")! < ReleaseDate("1980-06-01")!)
    }

    @Test func tagValuesUseMidnightUTC() {
        #expect(ReleaseDate("1980-06-01")?.tagValue == "1980-06-01T00:00:00Z")
        #expect(ReleaseDate(tagValue: "1980-06-01T00:00:00Z") == ReleaseDate("1980-06-01"))
        #expect(ReleaseDate(tagValue: "1980-06-01") == ReleaseDate("1980-06-01"))
        #expect(ReleaseDate(tagValue: "1980") == nil)
        #expect(ReleaseDate(tagValue: "1980-06-01X") == nil)
    }

    func components(_ date: Date, _ zone: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: zone)
        return formatter.string(from: date)
    }

    @Test func localStartIsMidnightWhereMidnightExists() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let start = ReleaseDate("1980-06-01")!.localStart(in: tokyo)
        #expect(start.isMidnight)
        #expect(components(start.date, "UTC") == "1980-05-31T15:00:00Z")
        let early = ReleaseDate("1958-03-01")!.localStart(in: tokyo)
        #expect(components(early.date, "UTC") == "1958-02-28T15:00:00Z")
        // British Standard Time kept the United Kingdom one hour ahead of UTC from 1968 to 1971.
        let london = try #require(TimeZone(identifier: "Europe/London"))
        #expect(components(ReleaseDate("1970-01-01")!.localStart(in: london).date, "UTC") == "1969-12-31T23:00:00Z")
    }

    @Test func skippedMidnightUsesTheFirstInstantAndIsReported() throws {
        let saoPaulo = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let start = ReleaseDate("2018-11-04")!.localStart(in: saoPaulo)
        #expect(!start.isMidnight)
        #expect(components(start.date, "America/Sao_Paulo") == "2018-11-04T01:00:00-02:00")
    }
}

@Suite struct ResolutionTests {
    @Test func trackValuesOverrideAlbumValuesAndEmptyMeansUnknown() throws {
        let catalog = Catalog(albums: [
            Album(
                album: "Example Album", albumArtist: "", artist: "Example Artist", genre: "Pop",
                composer: "Album Writer",
                releaseDate: "1980-06-01",
                discs: [
                    Disc(tracks: [
                        Track(title: "One", artist: "Guest Artist", genre: ""),
                        Track(title: "Two", composer: "Track Writer"),
                    ]),
                    Disc(tracks: [Track(title: "Three", releaseDate: "1981-01-01")]),
                ])
        ])
        let tracks = catalog.resolvedTracks()
        #expect(tracks.map(\.title) == ["One", "Two", "Three"])
        #expect(tracks[0].artist == "Guest Artist")
        #expect(tracks[0].albumArtist == "Example Artist")
        #expect(tracks[0].genre == "Pop")
        #expect(tracks[1].composer == "Track Writer")
        #expect(tracks[2].releaseDate == ReleaseDate("1981-01-01"))
        #expect(tracks[2].reference == TrackReference(album: 0, disc: 2, track: 1))
        #expect(tracks.map(\.trackCount) == [2, 2, 1])
        #expect(tracks.allSatisfy { $0.discCount == 2 })
    }
}
