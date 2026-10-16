# iLibrary

[![CI](https://github.com/x96x64/ilibrary/actions/workflows/ci.yml/badge.svg)](https://github.com/x96x64/ilibrary/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![Linux: Core targets](https://img.shields.io/badge/Linux-Core%20targets-FCC624?logo=linux&logoColor=black)](#how-it-works)

iLibrary prepares downloaded music for a local Apple Music library and adds it in a controlled order. It converts lossless downloads to Apple Lossless, copies iTunes Store purchases without their purchase metadata, applies metadata from a catalog file without re-encoding, names files as the Music app does, and sets file dates to release dates. The addition of albums to Music one at a time is planned.

```bash
ilibrary apply catalog.json ~/Music/Staging
```

> [!IMPORTANT]
> iLibrary is in development. The commands `import`, `export`, `prompt`, `schema`, `validate`, `apply`, `timestamps`, and `add` are implemented and tested with synthetic files and a substitute Music library; `check` and `doctor` follow in later milestones of the [roadmap](docs/roadmap-to-stable.md). No release has been published. iLibrary does not touch the Music app or its library yet. iLibrary is not affiliated with, endorsed by, or sponsored by Apple.

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

Implemented:

- **Ordered addition to Music.** `add` moves each album into the Music media folder, adds it there in place, and confirms one track per file before the next album, in release or artist order. It stops when the library already holds a matching track, never changes a track in Music, and resumes an interrupted run.
- **Lossless import.** `import` converts FLAC, WAV, and AIFF downloads to Apple Lossless through AudioToolbox, verified by decoded PCM equality, and copies iTunes Store files without re-encoding while removing purchase metadata. Standard FLAC tags and the front cover are carried; with `--delete-originals`, originals are moved to the Trash only after every output has been verified.
- **Catalog commands.** `export` drafts a catalog from existing tags, `prompt` prepares it for completion by an AI agent or chat, `validate` checks it and its correspondence with files, and `apply` writes it to the files. Every planned change is listed first; `--dry-run` stops there, and every written file is read back and compared with the plan.
- **Music-style names and release dates.** `apply --rename` arranges files as `Album Artist/Album/NN Title.m4a`, and `timestamps` sets file and folder dates to release dates at local midnight. Missing paths are never created, and symbolic links are refused.
- **MP4 metadata without re-encoding.** `MP4Core` reads and writes the item list of M4A files, rebuilds only the movie box, copies the audio data unchanged, relocates chunk offsets, and replaces items in place, so that repeated application yields identical bytes. Every rewrite goes through a hidden partial file that is parsed again and compared with the source before it replaces the destination.
- **Removal of iTunes Store purchase metadata.** The purchaser's account, name, purchase date, store identifiers, and purchase information are removed, padding is zeroed, and the gapless information is kept. Encrypted files (`.m4p` and `drms` sample entries) are refused.
- **FLAC metadata.** `FLACCore` reads stream information, Vorbis comments, and pictures without decoding audio, and rejects truncated metadata.
- **Catalogs.** `CatalogCore` validates the `ilibrary-catalog-1` format with located diagnostics, and provides matching of files to catalog tracks, Music-style naming, four album orders, title rules, and release-date handling.

Planned:

- **Checks.** Comparison of files with the library, cloud status, duplicates, and timestamps, and a `doctor` command for the environment.

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

The executable is `.build/release/ilibrary`. Homebrew, npm, and pip packages are planned after version 0.1.0; their names are decided before version 0.2.0.

## Quick Start

The workflow up to the addition to Music is implemented:

```bash
# 1. Convert downloads and copy purchases into a staging folder, after a dry run
ilibrary import ~/Downloads/mora -o ~/Music/Staging --dry-run
ilibrary import ~/Downloads/mora -o ~/Music/Staging

# 2. Draft a catalog from the files' tags, with their covers
ilibrary export ~/Music/Staging -o catalog.json --artwork covers

# 3. Complete it with an AI agent or chat, or by hand
ilibrary prompt catalog.json > prompt.md

# 4. Validate it, and preview every change
ilibrary validate catalog.json ~/Music/Staging
ilibrary apply catalog.json ~/Music/Staging --rename --timestamps --dry-run

# 5. Apply it
ilibrary apply catalog.json ~/Music/Staging --rename --timestamps
```

Afterwards, `ilibrary add ~/Music/Staging --order release` adds the albums to Music one at a time.

## Usage

iLibrary is a command-based CLI with verb subcommands. Every mutating command offers `--dry-run`, states what it will change before changing it, and verifies its result afterwards. The [Command-Line Interface](docs/command-line-interface.md) reference describes each command.

```
ilibrary export PATH... -o CATALOG.json [--artwork DIR] [--dry-run]
ilibrary prompt CATALOG.json
ilibrary schema
ilibrary validate CATALOG.json [PATH...]
ilibrary apply CATALOG.json PATH... [--dry-run] [--rename] [--timestamps]
ilibrary import SOURCE... -o DIR [--from mora|itunes|auto] [--delete-originals] [--dry-run]
ilibrary add PATH... [--order release|artist|artist-desc|artist-release] [--dry-run]
ilibrary timestamps CATALOG.json PATH... [--dry-run] [--script FILE]
ilibrary check [PATH] [--library]
ilibrary doctor
ilibrary help [COMMAND] | --help | --version
```

`check` and `doctor` are planned. Exit status is 0 on success, 1 on a runtime failure, and 2 on a usage error.

## Catalog Format

A catalog is a UTF-8 JSON document identified by `"format": "ilibrary-catalog-1"`. Album-level values apply to every track and may be overridden per track; an empty string means that a value is unknown. `ilibrary schema` prints the JSON Schema, and [Completing Catalogs with AI Agents](docs/catalog-for-agents.md) describes the authoring workflow.

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
- **Matching** selects the album by name or alias, then the track by disc and track number, by numbering that continues across discs, and by title. A title that disagrees at a file's numbers is treated as a correction only when no other track carries it and more of the album's titles agree than differ; every match and refusal is reported.
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
| `ConversionMac` | Conversion to Apple Lossless through AudioToolbox and PCM verification | Implemented; macOS only |
| `LibraryMac` | File dates; Music automation and the media folder | File dates implemented; macOS only |
| `ilibrary` | Commands | Catalog commands implemented; Foundation only except dates |

The design rests on technical spikes recorded in the [Architecture Spike](docs/reports/architecture-spike.md) report, including measurements on synthetic files and on private copies of purchased and downloaded files.

## Apple Music and Cloud Matching

Albums imported into a library with iCloud Music Library may be identified with albums in the Apple Music catalog, and then shown with that catalog's metadata and artwork. The matching decision belongs to Apple's service. iLibrary will document procedures that reduce matching, such as removing store identifiers, and will report matched tracks; it does not claim to prevent matching.

## Limitations

- `check` and `doctor` are not implemented. `add` has been verified with a substitute library that behaves as Music was measured to behave, not yet with Music itself. Catalogs are exported from `.m4a` files only; FLAC tags reach a catalog through `import`.
- Conversion and setting creation dates require macOS. On Linux, the catalog commands and copies by `import` run, but `timestamps` offers only `--dry-run` and `--script`.
- A catalog numbers discs and tracks by position; `export` reports gaps and repetitions in the files' numbers.
- Conversion supports mono and stereo only, and refuses floating-point PCM. FLAC fields outside the standard set are not carried.
- Files that would need chunk offsets beyond 32 bits are refused rather than converted to 64-bit offsets.
- Protected audio (`.m4p`) is out of scope. iLibrary does not download audio.
- Further naming rules of the Music app, such as length limits, are unknown; affected names are reported instead of changed.
- The behavior of Music under automation has not yet been measured by iLibrary.

## Documentation

- [Technical Planning Study](docs/planning-study.md): the approved plan, preserved as a historical record
- [Command-Line Interface](docs/command-line-interface.md): commands, options, and exit status
- [Completing Catalogs with AI Agents](docs/catalog-for-agents.md): the authoring workflow
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

`scripts/test.sh` runs `swift test` with the paths that Swift Testing needs under the Command Line Tools. On macOS, `scripts/validation/catalog-commands.sh` and `scripts/validation/import.sh` also exercise the release build on decodable synthetic audio and checks the results with FFmpeg, Core Audio, exiftool, and `stat`. The public test suite uses only original synthetic data and needs neither the network, private files, nor a Music library. Read [AGENTS.md](AGENTS.md) for the engineering constraints, including library safety, evidence classification, and the rules for private reference material. Commits follow [Conventional Commits](https://www.conventionalcommits.org/).

## Acknowledgments

iLibrary is developed with [Codex](https://openai.com/codex) by OpenAI and [Claude](https://claude.ai) by Anthropic, credited as co-authors in the commit history.

## License

iLibrary is licensed under the [Apache License, Version 2.0](LICENSE).
