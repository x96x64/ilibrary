# Technical Planning Study

## Status

Planning baseline, approved by the maintainer on October 16, 2026. This document is preserved as a historical record; later decisions are recorded in `roadmap-to-stable.md` and in dated reports, and they supersede this study only where they say so. The Apache License, Version 2.0, was selected on the same date.

## Purpose

iLibrary is a macOS command-line tool that prepares downloaded music for a local Apple Music library and adds it in a controlled order. It generalizes a manual curation procedure that was carried out on a library of about three hundred tracks from mora and the iTunes Store: lossless conversion, metadata correction from a reference record, consistent file and folder names, file timestamps equal to release dates, and album-by-album import. The procedure and its failures are summarized in [Manual Library Curation](reports/manual-library-curation.md).

```bash
ilibrary import ~/Downloads/mora -o ~/Music/Staging
ilibrary apply catalog.json ~/Music/Staging
ilibrary add ~/Music/Staging --order release
```

## Requirements

1. The interface is a command-based CLI with verb subcommands, not an interactive text user interface.
2. Metadata is applied from a dedicated catalog file rather than inferred from examples.
3. Tracks purchased from the iTunes Store are made equivalent to other local files: purchase and store metadata are removed without re-encoding the audio.
4. Albums are added to Music one at a time, in release order by default, or by artist in ascending or descending order with albums in the same direction, or by artist in ascending order with albums in release order.
5. File and folder timestamps can optionally be set to release dates, as the maintainer's existing timestamp script does.
6. The supported sources are mora and the iTunes Store.
7. Imported albums should not be identified with albums in the Apple Music catalog. The maintainer observed that re-downloading every track removed such identification. Because the matching decision belongs to Apple's service, iLibrary documents measures that reduce matching and detects matched tracks; it does not claim to prevent matching.
8. Documentation, contributor guidance, Codex and Claude attribution, MLA title case, repository organization, About text, topics, commit messages, and release notes follow iLyrics.
9. A catalog can be drafted, completed by an AI agent or AI chat, validated, and applied.
10. Work can move between Claude Code and Codex at any time without loss of state.

## Command-Line Interface

```
ilibrary export PATH -o CATALOG.json [--artwork DIR]
ilibrary prompt CATALOG.json
ilibrary schema
ilibrary validate CATALOG.json [PATH...]
ilibrary apply CATALOG.json PATH... [--dry-run] [--rename] [--timestamps]
ilibrary import SOURCE... -o DIR [--from mora|itunes|auto] [--delete-originals]
ilibrary add PATH... [--order release|artist|artist-desc|artist-release] [--dry-run]
ilibrary timestamps CATALOG.json PATH... [--script FILE]
ilibrary check [PATH] [--library]
ilibrary doctor
ilibrary help [COMMAND] | --help | --version
```

- `export` writes a catalog from existing tags. Artwork is excluded unless `--artwork DIR` is given, in which case covers are written as PNG files and referenced by the catalog.
- `prompt` writes instructions for an AI agent or AI chat: the schema, the draft catalog, and the authoring rules. `schema` prints the JSON Schema. `validate` checks a catalog's format, required fields, dates, and, when paths are given, its correspondence with the files.
- `apply` matches each file by album name or alias, disc number, and track number, falls back to continuous numbering across discs, and then to the title. It reports every match and every change. `--rename` applies the naming of the Music media folder.
- `import` converts FLAC, WAV, and AIFF to Apple Lossless, and copies iTunes Store AAC without re-encoding while removing purchase and store metadata. Originals are deleted only with `--delete-originals` and only after decoded PCM equality has been verified.
- `add` moves each album into the Music media folder, adds it, and confirms the resulting track count before the next album. It stops when the library already contains a matching track.
- `timestamps` sets modification and creation dates to the release date at local midnight, and optionally writes an equivalent shell script. It never creates a missing path.
- `check` compares files with the library, and reports missing files, duplicates, cloud status, and timestamp mismatches. `doctor` reports the version, the Automation permission for Music, the media folder, and the toolchain, with a recovery step for each problem.

Exit status is 0 on success, 1 on a runtime failure, and 2 on a usage error.

## Catalog Format

A catalog is a UTF-8 JSON document identified by `"format": "ilibrary-catalog-1"`. The identifier rejects unrelated JSON, and its numeric suffix is incremented for any incompatible change so that earlier catalogs are never misread. From version 1.0.0, a change that breaks this format requires a new major version.

```json
{
  "format": "ilibrary-catalog-1",
  "titleRules": {
    "case": "keep",
    "removeQualifiers": ["Remaster", "Remastered", "Remastered Version"],
    "bracketNested": true,
    "preserve": ["HIStory", "XSCAPE", "P.Y.T."]
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
```

Album-level values apply to every track and may be overridden per track. Release dates are written to files as `YYYY-MM-DDT00:00:00Z`; file timestamps use local midnight of the same date. `notes` and `sources` record evidence and are ignored by `apply`.

### Title Rules

Title rules apply to track and album titles. Explicit titles in a catalog take precedence; the rules normalize source names and support matching.

- `removeQualifiers` removes trailing parenthesized qualifiers that contain a listed term, with or without a year, such as `(2012 Remaster)` or `(Remastered)`. The default list is empty, which keeps them.
- `bracketNested` converts a parenthetical that contains another parenthetical into square brackets, as the Music app displays it: `Behind the Mask (Mike's Mix (Demo))` becomes `Behind the Mask [Mike's Mix (Demo)]`.
- `case` selects `keep` (the default), `mla`, `apa`, or `start`. MLA lowercases articles, prepositions of any length, coordinating conjunctions, and `to` in infinitives, except as the first or last word. APA capitalizes every word of four or more letters and lowercases shorter articles, prepositions, and conjunctions; for example, MLA gives `Rock with You` and APA gives `Rock With You`. `start` capitalizes every word. Words whose treatment depends on their grammatical role are left unchanged and reported for review.
- Entries in `preserve`, words written entirely in capitals, words with internal capitals, abbreviations, and text outside the Latin script are never changed. Apostrophes are kept within words, as in `Don't` and `'Til`.
- Live recordings carry `(Live)`, or `[Live]` when the title already ends with a parenthetical; interludes carry no live designation. Version 0.1.0 reports deviations from this convention; automatic application is deferred.

### Authoring with AI Agents

The workflow is `export`, then `prompt`, then completion by an AI agent or AI chat, then `validate`, and then `apply --dry-run`. The JSON Schema is published in `docs/schema/ilibrary-catalog-1.schema.json`. The generated prompt instructs the model to leave unknown values empty rather than guess, to cite sources for copyright lines and release dates, and to follow the title and live conventions; it states the rules in English with Japanese explanations. Output from a model is never trusted without `validate`. `docs/catalog-for-agents.md` describes the same workflow for agents that run the command directly.

## Architecture

The package follows the separation used by iLyrics: Foundation-only targets hold domain logic and build on Linux, and macOS targets hold platform integration. No external package or run-time tool is required.

```
ilibrary/
├── .github/workflows/  ci.yml (macOS build, test, and format; Linux tests of the Core targets), release.yml
├── AGENTS.md  CLAUDE.md  README.md  SUPPORT.md  CHANGELOG.md  LICENSE
├── Package.swift  .swift-format  .gitignore
├── Sources/
│   ├── MP4Core/         box parsing and rewriting, item lists, artwork, removal of purchase metadata, chunk offsets
│   ├── CatalogCore/     catalog format, validation, matching, naming, ordering, title rules, dates
│   ├── ConversionMac/   FLAC, WAV, and AIFF to Apple Lossless through AudioToolbox; PCM verification
│   ├── LibraryMac/      Music automation, media folder, moves, file timestamps
│   ├── ProgressDisplay/ one line per stage, as in iLyrics
│   └── ilibrary/        command entry point and commands
├── Tests/
├── docs/                index, references, schema, and dated reports
├── fixtures/            original synthetic catalogs; audio is generated during tests
└── scripts/
```

## Sources

- **mora** delivers FLAC files named `NN-Title_ID.flac`. Multi-disc albums may number tracks continuously across discs, and album names may carry qualifiers such as `(Remastered)` or `(2015 Remaster)`.
- **The iTunes Store** delivers DRM-free AAC files containing the purchaser's Apple Account, name, purchase date, store identifiers, and a purchase signature, usually without embedded artwork. These are removed by rebuilding the container around the unchanged audio stream.

## Apple Music Integration

Music is controlled through Apple Events and requires the Automation permission. Files inside the media folder are added in place without copying, as observed during manual curation. Store identifiers are never written. After import, `check` reads each track's cloud status and reports matched or subscription tracks. Whether iCloud Music Library is enabled cannot yet be determined programmatically; this is Unknown until verified.

## Agent Handoff

`AGENTS.md` is the single source of rules; `CLAUDE.md` imports it. Repository state, not conversation state, records progress: each milestone ends by updating the Current Status of `roadmap-to-stable.md`. The Foundation-only targets allow cloud agents on Linux to build and test domain logic. Work proceeds on milestone branches through pull requests. Pushes and publication require the maintainer's approval, preceded by a documentation preview, a summary of principal changes, and its Japanese translation.

## Milestones to Version 0.1.0

| Milestone | Work | Location | Gate |
| --- | --- | --- | --- |
| M0 | Planning baseline: rules, this study, curation findings, roadmap, skeleton | Maintainer's Mac | Maintainer approval of the plan |
| M1 | Spikes: S1 MP4 metadata rewriting against real files with independent references; S2 lossless conversion with PCM equality; S3 Music automation, in-place addition, persistent IDs, cloud status, media folder discovery; S4 file timestamps; S5 removal of iTunes Store purchase metadata | Maintainer's Mac | Maintainer review of `reports/architecture-spike.md` |
| M2 | `MP4Core` and `CatalogCore` with synthetic tests | Mac or cloud | CI on macOS and Linux |
| M3 | `export`, `schema`, `prompt`, `validate`, `apply`, `timestamps` | Mac, partly cloud | Export and reapplication of a library copy without differences |
| M4 | `import` for mora and the iTunes Store | Mac | Synthetic sources and a small private sample |
| M5 | `add` with the four orders and resumption | Mac | A test library |
| M6 | `check` and `doctor` | Mac | Detection of deliberately damaged cases |
| M7 | Documentation following iLyrics | Anywhere | Documentation review |
| M8 | Qualification on the maintainer's library, from dry runs to execution | Maintainer's Mac | Maintainer judgment |
| M9 | Version 0.1.0, release notes, documentation preview, summary, and Japanese translation | Maintainer's Mac | Maintainer approval to create the repository, push, tag, and publish a prerelease |

## Distribution

Version 0.1.0 is an experimental source release, as iLyrics 0.1.0 was. The names `ilibrary` on npm and PyPI were already taken on October 16, 2026; Homebrew and the GitHub name `x96x64/ilibrary` were available. Package names are to be decided before version 0.2.0. The proposed repository description is "Catalog-driven tagging and ordered, local-only import of music into Apple Music, for macOS", with the topics `apple-music`, `music-library`, `metadata`, `mp4`, `alac`, `flac`, `itunes`, `command-line-tool`, `macos`, `swift`, and `music`. Release titles follow the form `iLibrary: v0.1.0, Catalog-Driven Music Libraries for Apple Music on macOS`.

## Outlook to Version 1.0.0

These are intentions, not commitments.

- 0.2.0: a Homebrew tap, decided npm and pip package names, and update guidance in `doctor`.
- 0.3.0: compact-disc rips and other sources, merging of multi-disc albums into one disc, and catalog differences.
- 0.4.0: optional metadata candidates from the iTunes Search API, disabled by default, and safe replacement of existing library entries.
- 1.0.0: a stable `ilibrary-catalog-1` format and command-line interface, signing and notarization, and complete documentation.
