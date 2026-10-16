# iLibrary

[![CI](https://github.com/x96x64/ilibrary/actions/workflows/ci.yml/badge.svg)](https://github.com/x96x64/ilibrary/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Linux: Core targets](https://img.shields.io/badge/Linux-Core%20targets-FCC624?logo=linux&logoColor=black)](#how-it-works)

iLibrary prepares downloaded music for a local Apple Music library and adds it in a controlled order. It is planned to convert lossless downloads to Apple Lossless, apply metadata from a catalog file, remove iTunes Store purchase metadata without re-encoding, name files as the Music app does, and add albums one at a time.

```bash
ilibrary apply catalog.json ~/Music/Staging
```

> [!IMPORTANT]
> iLibrary is in development, and its command-line interface is not implemented yet: the command above is planned. The Foundation-only libraries `MP4Core`, `FLACCore`, and `CatalogCore` are implemented and tested with synthetic files; conversion, Music automation, and the commands follow in later milestones of the [roadmap](docs/roadmap-to-stable.md). No release has been published. iLibrary is not affiliated with, endorsed by, or sponsored by Apple.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Catalog Format](#catalog-format)
- [How It Works](#how-it-works)
- [Apple Music and Cloud Matching](#apple-music-and-cloud-matching)
- [Limitations](#limitations)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [Acknowledgments](#acknowledgments)
- [License](#license)

## Features

Implemented in the libraries:

- **MP4 metadata without re-encoding.** `MP4Core` reads and writes the item list of M4A files, rebuilds only the movie box, copies the audio data unchanged, relocates chunk offsets, and replaces items in place, so that repeated application yields identical bytes. Every rewrite goes through a hidden partial file that is parsed again and compared with the source before it replaces the destination.
- **Removal of iTunes Store purchase metadata.** The purchaser's account, name, purchase date, store identifiers, and purchase information are removed, padding is zeroed, and the gapless information is kept. Encrypted files (`.m4p` and `drms` sample entries) are refused.
- **FLAC metadata.** `FLACCore` reads stream information, Vorbis comments, and pictures without decoding audio, and rejects truncated metadata.
- **Catalogs.** `CatalogCore` validates the `ilibrary-catalog-1` format with located diagnostics, and provides matching of files to catalog tracks, Music-style naming, four album orders, title rules, and release-date handling.

Planned:

- **Lossless conversion.** FLAC, WAV, and AIFF to Apple Lossless through AudioToolbox, verified by decoded PCM equality before any original is deleted.
- **Ordered, local-only import.** Albums moved into the Music media folder and added one at a time in release or artist order, stopping when the library already contains a matching track.
- **Checks.** Comparison of files with the library, cloud status, duplicates, and timestamps, and a `doctor` command for the environment.
- **Authoring with AI agents.** Catalogs drafted from existing tags, completed by an AI agent or chat, validated, and applied.

## Requirements

- macOS 14 or later on Apple silicon
- A Swift 6 toolchain: Xcode 16 or the Command Line Tools 16 or later

The Core libraries also build and test on Linux with Swift 6.4.

## Installation

### From Source

```bash
git clone https://github.com/x96x64/ilibrary.git
cd ilibrary
swift build -c release
```

The executable is `.build/release/ilibrary`. It currently reports its version and implements no commands. Homebrew, npm, and pip packages are planned after version 0.1.0; their names are decided before version 0.2.0.

## Quick Start

The commands below are planned for version 0.1.0 and are not implemented yet.

```bash
# 1. Check the environment and the Automation permission for Music
ilibrary doctor

# 2. Convert downloads and remove purchase metadata into a staging folder
ilibrary import ~/Downloads/mora -o ~/Music/Staging

# 3. Draft a catalog, complete it, validate it, and preview the changes
ilibrary export ~/Music/Staging -o catalog.json
ilibrary validate catalog.json ~/Music/Staging
ilibrary apply catalog.json ~/Music/Staging --dry-run

# 4. Apply it and add the albums to Music in release order
ilibrary apply catalog.json ~/Music/Staging --rename --timestamps
ilibrary add ~/Music/Staging --order release
```

## Usage

The planned interface is a command-based CLI with verb subcommands. Every mutating command will offer `--dry-run`, state what it will change before changing it, and verify its result afterwards.

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

Exit status is 0 on success, 1 on a runtime failure, and 2 on a usage error. Only `--version` is implemented.

## Catalog Format

A catalog is a UTF-8 JSON document identified by `"format": "ilibrary-catalog-1"`. Album-level values apply to every track and may be overridden per track; an empty string means that a value is unknown. The format, its validation, and the JSON Schema are implemented in `CatalogCore`; the commands that use them are planned.

```json
{
  "format": "ilibrary-catalog-1",
  "titleRules": { "case": "keep", "removeQualifiers": ["Remaster"], "bracketNested": true },
  "albums": [
    {
      "album": "Example Album",
      "aliases": ["Example Album (Remastered)"],
      "albumArtist": "Example Artist",
      "copyright": "℗ 1980 Example Records, Inc.",
      "releaseDate": "1980-06-01",
      "discs": [ { "tracks": [ { "title": "First Song", "composer": "Example Writer" } ] } ]
    }
  ]
}
```

- **Validation** reports unknown fields, wrong types, missing titles, invalid dates, and duplicate albums with their JSON paths, and rejects documents of other formats. The schema is published as [docs/schema/ilibrary-catalog-1.schema.json](docs/schema/ilibrary-catalog-1.schema.json).
- **Matching** selects the album by name or alias, then the track by disc and track number, by numbering that continues across discs, and by title. Numbers are accepted only when a file's title, if present, agrees, and every match and refusal is reported.
- **Naming** follows the Music app: `NN Title.m4a` on single-disc albums, `D-NN Title.m4a` on multi-disc albums, and `_` in place of `:` and `/`.
- **Orders** are `release`, `artist` (albums by name), `artist-desc` (artists and albums descending), and `artist-release` (albums by release date).
- **Title rules** remove listed qualifiers such as `(2012 Remaster)`, write nested parentheticals with square brackets, and apply the MLA, APA, or start-case style. Words whose capitalization depends on their grammatical role are left unchanged and reported.
- **Dates** are written to files as `YYYY-MM-DDT00:00:00Z`; file timestamps use local midnight, or the first instant of the day where a time zone skips midnight.

## How It Works

The package separates domain logic from platform integration, as iLyrics does. No external package or run-time tool is required.

| Target | Contents | Status |
| --- | --- | --- |
| `MP4Core` | Box parsing and rewriting, item lists, chunk offsets, purchase metadata | Implemented; Foundation only |
| `FLACCore` | FLAC metadata blocks | Implemented; Foundation only |
| `CatalogCore` | Catalog format, validation, matching, naming, ordering, title rules, dates | Implemented; Foundation only |
| `ConversionMac` | Conversion to Apple Lossless through AudioToolbox and PCM verification | Planned |
| `LibraryMac` | Music automation, media folder, moves, file timestamps | Planned |
| `ilibrary` | Command entry point and commands | Version report only |

The design rests on technical spikes recorded in the [Architecture Spike](docs/reports/architecture-spike.md) report, including measurements on synthetic files and on private copies of purchased and downloaded files.

## Apple Music and Cloud Matching

Albums imported into a library with iCloud Music Library may be identified with albums in the Apple Music catalog, and then shown with that catalog's metadata and artwork. The matching decision belongs to Apple's service. iLibrary will document procedures that reduce matching, such as removing store identifiers, and will report matched tracks; it does not claim to prevent matching.

## Limitations

- No command other than `--version` is implemented.
- Conversion will support mono and stereo only, and refuses floating-point PCM.
- Files that would need chunk offsets beyond 32 bits are refused rather than converted to 64-bit offsets.
- Protected audio (`.m4p`) is out of scope. iLibrary does not download audio.
- Further naming rules of the Music app, such as length limits, are unknown; affected names are reported instead of changed.
- The behavior of Music under automation has not yet been measured by iLibrary.

## Documentation

- [Technical Planning Study](docs/planning-study.md): the approved plan, preserved as a historical record
- [Roadmap to the Stable Release](docs/roadmap-to-stable.md): current status and decisions in force
- [Catalog JSON Schema](docs/schema/ilibrary-catalog-1.schema.json)
- [Documentation Index](docs/README.md): every engineering report, in chronological order

## Contributing

Issues and pull requests are welcome. Before submitting a change:

```bash
swift build
scripts/test.sh
swift format lint --strict --recursive Sources Tests Package.swift scripts
```

`scripts/test.sh` runs `swift test` with the paths that Swift Testing needs under the Command Line Tools. The public test suite uses only original synthetic data and needs neither the network, private files, nor a Music library. Read [AGENTS.md](AGENTS.md) for the engineering constraints, including library safety, evidence classification, and the rules for private reference material. Commits follow [Conventional Commits](https://www.conventionalcommits.org/).

## Acknowledgments

iLibrary is developed with [Claude](https://claude.ai) by Anthropic, credited as a co-author in the commit history.

## License

iLibrary is licensed under the [Apache License, Version 2.0](LICENSE).
