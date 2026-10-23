# iLibrary

[![Release](https://img.shields.io/github/v/release/x96x64/ilibrary)](https://github.com/x96x64/ilibrary/releases)
[![npm](https://img.shields.io/npm/v/%40x96_64%2Filibrary)](https://www.npmjs.com/package/@x96_64/ilibrary)
[![PyPI](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fpypi.org%2Fpypi%2Fx96-64-ilibrary%2Fjson&query=%24.info.version&prefix=v&label=pypi&color=blue)](https://pypi.org/project/x96-64-ilibrary/)
[![Homebrew](https://img.shields.io/badge/Homebrew-x96x64%2Ftap-FBB040?logo=homebrew&logoColor=white)](https://github.com/x96x64/homebrew-tap)
[![CI](https://github.com/x96x64/ilibrary/actions/workflows/ci.yml/badge.svg)](https://github.com/x96x64/ilibrary/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org)

iLibrary prepares downloaded music for a local Apple Music library and adds it in a controlled order. It converts lossless downloads to Apple Lossless, copies iTunes Store purchases without their purchase metadata, applies metadata from a catalog file without re-encoding, names files as the Music app does, and sets file dates to release dates. It adds albums to Music one at a time so that Recently Added shows them in the chosen order, rebuilds an existing library from its files, and diagnoses differences between files and library records.

```bash
ilibrary apply catalog.json ./staging --dry-run
```

> [!IMPORTANT]
> iLibrary moves and rewrites your music files and changes your Music library. Begin with copies, keep independent backups of your library, and review every dry run. File processing is verified with synthetic tests, and Music operations are tested with a substitute library; the requests that iLibrary sends to Music use forms measured on macOS 27.0.1 with Music 1.7, but the rebuilding stages have not been run against the Music application. iLibrary does not prevent Apple Music cloud matching and is not affiliated with, endorsed by, or sponsored by Apple.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Rebuilding a Library](#rebuilding-a-library)
- [Catalogs](#catalogs)
- [How It Works](#how-it-works)
- [Apple Music and Cloud Matching](#apple-music-and-cloud-matching)
- [Troubleshooting](#troubleshooting)
- [Rights and Privacy](#rights-and-privacy)
- [Limitations](#limitations)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [Star History](#star-history)
- [License](#license)

## Features

- **Ordered addition to Music:** `add` moves each album into the Music media folder, adds it there in place, and confirms one track per file before the next album, in release or artist order. Each album is added only after the clock has passed the previous album's addition second, so that Recently Added shows the intended order. It stops when the library already holds a matching track, never changes a track in Music, and resumes an interrupted run.
- **Lossless import:** `import` converts FLAC, WAV, and AIFF downloads to Apple Lossless through AudioToolbox, verified by decoded PCM equality, and copies iTunes Store files without re-encoding while removing purchase metadata. Standard FLAC tags and the front cover are carried; with `--delete-originals`, originals are moved to the Trash only after every output has been verified.
- **Catalog commands:** `export` drafts a catalog from existing tags, `prompt` prepares it for completion by an AI agent or chat, `validate` checks it and its correspondence with files, and `apply` writes it to the files. `export --strict` refuses, without writing, an export that is not a complete inventory. Every planned change is listed first; `--dry-run` stops there, and every written file is read back and compared with the plan.
- **Music-style names and release dates:** `apply --rename` arranges files as `Album Artist/Album/NN Song.m4a`, and `timestamps` sets file and folder dates to release dates at local midnight. Missing paths are never created, and symbolic links are refused.
- **MP4 metadata without re-encoding:** `MP4Core` reads and writes the item list of M4A files, rebuilds only the movie box, copies the audio data unchanged, relocates chunk offsets, and replaces items in place, so that repeated application yields identical bytes. Every rewrite goes through a hidden partial file that is parsed again and compared with the source before it replaces the destination.
- **Removal of iTunes Store purchase metadata:** The purchaser's account, name, purchase date, store identifiers, and purchase information are removed, padding is zeroed, and the gapless information is kept. Encrypted files (`.m4p` and `drms` sample entries) are refused.
- **FLAC metadata:** `FLACCore` reads stream information, Vorbis comments, and pictures without decoding audio, and rejects truncated metadata.
- **Catalogs:** `CatalogCore` validates the `ilibrary-catalog-1` format with located diagnostics, and provides matching of files to catalog tracks, Music-style naming, four album orders, title rules, and release-date handling.
- **Library rebuilding:** `rebuild prepare` inventories the selected files and Music registrations, verifies a backup on separate storage, performs a restoration test, confirms that the backup volume is ejected, and writes a private recovery record. `rebuild stage` then moves the files out of the media folder, `rebuild clear` removes exactly the recorded registrations and confirms that Music reports no tracks, `rebuild apply` writes the catalog to the files while Music is closed, and `rebuild add` adds the albums again in the chosen order. Every stage records its progress, resumes after an interruption, and refuses to run out of order.
- **Checks and diagnostics:** `check` reports missing tags, duplicate tracks, and incorrect dates; `check --library` compares files with Music by location and reports stale metadata, missing files, and notable cloud statuses. `doctor` reports environment problems and recovery steps without launching Music or reading its library.

## Requirements

- macOS 14 or later on Apple silicon
- A Swift 6 toolchain supplied by Xcode or the Command Line Tools for source or Homebrew builds
- npm or Python 3.9 or later for the corresponding package installer; neither is needed by the native executable

The package declares macOS 14 as its deployment target, which is not a claim of testing every release since. Continuous integration builds and tests every change on GitHub's macOS runner and, for the portable targets, on Linux with Swift 6.4; releases are built on the same macOS runner. Music behavior was measured on macOS 27.0.1 with Music 1.7. Music commands require the installed Music app and the Automation permission; an Apple Music subscription is not required.

## Installation

The following commands install version 1.0.3, the version of this source tree. The [releases page](https://github.com/x96x64/ilibrary/releases) and the package registries show which versions each channel provides; an earlier version is installed from npm or PyPI with the same commands and its version number. Choose one channel. The package names include the author because `ilibrary` on npm and PyPI belongs to other projects.

### Homebrew

```bash
brew install x96x64/tap/ilibrary
```

The formula in [x96x64/homebrew-tap](https://github.com/x96x64/homebrew-tap) downloads the release source archive, which Homebrew checks against the checksum recorded in the formula, and builds it on your Mac. It requires Swift 6 or later from Xcode or the Command Line Tools and stops with an explanation when an older toolchain is selected. It installs only the `ilibrary` executable, and `brew test ilibrary` checks its version, built-in schema, and help.

### npm

```bash
npm install -g @x96_64/ilibrary@1.0.3
```

The package contains the prebuilt executable, the license, and this project's package README, and declares `darwin` and `arm64` so that npm refuses it on other systems. It runs no installation script and needs no Swift toolchain. Releases are published from the release workflow with npm provenance, which links each version to the commit and workflow run that built it.

### PyPI (pip)

```bash
python3 -m venv .venv-ilibrary
.venv-ilibrary/bin/python -m pip install x96_64-ilibrary==1.0.3
source .venv-ilibrary/bin/activate
```

npm and PyPI install the same native executable. Packages target macOS 14 or later on Apple silicon and are ad hoc-signed; Developer ID signing and notarization are not provided. Run `ilibrary --version` after installation. See [Distribution](docs/distribution.md) and the shared [package README](packaging/README.md).

### From Source

```bash
git clone https://github.com/x96x64/ilibrary.git
cd ilibrary
swift build -c release
export PATH="$PWD/.build/release:$PATH"
ilibrary --version
```

The executable is `.build/release/ilibrary`. The `PATH` line makes it available in the current terminal session; alternatively, invoke it by its full path. No administrator installation is needed. Package installation does not require this source checkout.

### Updating

Use `brew upgrade ilibrary`, `npm update -g @x96_64/ilibrary`, or `python -m pip install --upgrade x96_64-ilibrary` in the selected virtual environment.

In a clean source checkout, run `git pull --ff-only` and rebuild with `swift build -c release`. Review [CHANGELOG.md](CHANGELOG.md) before adopting a new version or development commit. If Git reports local changes or divergent history, preserve those changes and resolve them before updating.

### Uninstalling

Use `brew uninstall ilibrary`, `npm uninstall -g @x96_64/ilibrary`, or `python -m pip uninstall x96_64-ilibrary` in the selected environment. For a source build, close the terminal session to discard the temporary `PATH` change. If the executable was copied elsewhere, remove only that copy. iLibrary has no background service. Keep catalogs, artwork, staging files, and `.ilibrary-add.json` journals until their recovery purpose is complete; removing the executable does not undo file or Music changes.

## Quick Start

Begin with copies in a dedicated workspace. The following commands prepare files and do not add them to Music. Replace `./downloads` with the selected copies; keep catalog and artwork together. Review the dry-run output before each write:

```bash
# 1. Convert downloads and copy purchases into a staging folder, after a dry run
ilibrary import ./downloads -o ./staging --dry-run
ilibrary import ./downloads -o ./staging

# 2. Draft a catalog from the files' tags, with their covers
ilibrary export ./staging -o catalog.json --artwork covers --dry-run
ilibrary export ./staging -o catalog.json --artwork covers

# 3. Complete it by hand, or with an AI agent or chat
ilibrary prompt catalog.json > prompt.md

# 4. Validate it, and preview every change
ilibrary validate catalog.json ./staging
ilibrary apply catalog.json ./staging --rename --timestamps --dry-run

# 5. Apply it, then inspect the files
ilibrary apply catalog.json ./staging --rename --timestamps
ilibrary check ./staging
```

For the remaining Music step, preview `ilibrary add ./staging --order release --dry-run` before running without `--dry-run`, then compare the added files with `check --library`. `add` moves selected files out of staging; it retains a progress journal there. See [Library Operations and Recovery](docs/library-operations.md) before resuming an interrupted run.

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
ilibrary rebuild prepare CATALOG.json SOURCE --workspace DIR --backup DIR --restore-test DIR --staging DIR [--dry-run]
ilibrary rebuild stage|clear --workspace DIR [--dry-run]
ilibrary rebuild apply|add --workspace DIR [--timestamps] [--dry-run]
ilibrary rebuild status --workspace DIR
ilibrary timestamps CATALOG.json PATH... [--dry-run] [--script FILE]
ilibrary check [PATH...] [--library]
ilibrary doctor
ilibrary help [COMMAND] | --help | --version
```

The `rebuild` stages run in the order `prepare`, `stage`, `clear`, `apply`, and `add`, and `status` reports where a rebuild stands. They are distinct from the top-level `ilibrary add` and `ilibrary apply`, which they reuse. See [Command-Line Interface](docs/command-line-interface.md#rebuild).

Exit status is 0 on success, 1 on a failure or a finding from `check` or `doctor`, and 2 on a usage error. `check` requires at least one path or `--library`.

## Rebuilding a Library

`rebuild` turns an existing local library into the state that a catalog describes: the files carry the catalog's metadata and Music's names, and Recently Added shows the albums in the chosen order. Playlists, ratings, play counts, and other library history are not kept, and iCloud Music Library is not supported.

```bash
ilibrary rebuild prepare catalog.json ~/Music/Music/Media.localized/Music --workspace ~/rebuild/work \
    --backup /Volumes/Backup/Music --restore-test ~/rebuild/restore --staging ~/rebuild/staging \
    --confirm-separate-device
ilibrary rebuild stage --workspace ~/rebuild/work
ilibrary rebuild clear --workspace ~/rebuild/work
ilibrary rebuild apply --workspace ~/rebuild/work --timestamps
ilibrary rebuild add --workspace ~/rebuild/work --timestamps
```

`prepare` verifies a backup that you made on a separate device, restores it into an empty test directory, asks you to eject the backup volume, and writes a private recovery record. The stages then move the files out of the media folder, remove exactly the recorded registrations and confirm that Music reports no tracks, write the catalog to the files while Music is closed, and add the albums again one at a time. Run each with `--dry-run` first; `rebuild status` reports where a rebuild stands. When a stage stops, run it again after correcting the cause: it completes the operation that was in progress, and it refuses to continue when the files or the library differ from the record. See [Rebuilding a Library](docs/library-operations.md#rebuilding-a-library) and the [command reference](docs/command-line-interface.md#rebuild).

## Catalogs

A catalog is a JSON document, `ilibrary-catalog-1`, that states the intended album names, artists, album artists, composers, genres, copyright lines, release dates, compilation flags, artwork, and track titles, with album-level values that tracks may override and empty strings for unknown values. Title rules remove qualifiers such as `(2012 Remaster)` and apply MLA, APA, or start case; files are matched to tracks by album name or alias, disc and track numbers, and title, and every match and refusal is reported. `ilibrary schema` prints the JSON Schema.

```json
{
  "format": "ilibrary-catalog-1",
  "albums": [
    {
      "album": "Bad",
      "albumArtist": "Michael Jackson",
      "releaseDate": "1987-08-31",
      "discs": [{ "tracks": [{ "title": "Bad", "composer": "Michael Jackson" }] }]
    }
  ]
}
```

[Catalogs](docs/catalogs.md) describes every field, the title rules, matching, and the authoring workflow with `export` and `prompt`.

## How It Works

The package separates domain logic from platform integration. No external package or run-time tool is required, and the Foundation-only targets build and test on Linux.

| Target | Contents | Status |
| --- | --- | --- |
| `MP4Core` | Box parsing and rewriting, item lists, chunk offsets, purchase metadata | Implemented; Foundation only |
| `FLACCore` | FLAC metadata blocks | Implemented; Foundation only |
| `CatalogCore` | Catalog format, validation, matching, naming, ordering, title rules, dates | Implemented; Foundation only |
| `ConversionMac` | Conversion to Apple Lossless through AudioToolbox and PCM verification | Implemented; macOS only |
| `LibraryMac` | File dates, Music automation, media folder, permission state | Implemented; macOS only |
| `RebuildCore` | Backup inventory and verification, recovery record, progress journal | Implemented; Foundation only |
| `ilibrary` | Command parsing, plans, and reports | Implemented; Foundation logic with conditional Mac adapters |

The design rests on technical spikes made with synthetic files and with private copies of purchased and downloaded files, and on live measurements of Music summarized in [Measured Music Behavior](docs/library-operations.md#measured-music-behavior).

## Apple Music and Cloud Matching

Albums imported into a library with iCloud Music Library may be identified with albums in the Apple Music catalog, and then shown with that catalog's metadata and artwork. The matching decision belongs to Apple's service. iLibrary removes store identifiers and reports the cloud statuses exposed by Music. The effect of identifier removal on cloud matching has not been measured, and iLibrary does not claim to prevent matching. A local test user without an Apple Account isolates application behavior; it does not measure the cloud service. An `unknown` status is inconclusive.

## Troubleshooting

| Symptom | Next Step |
| --- | --- |
| Music cannot be controlled | Run `doctor` and follow its Automation permission instructions. |
| A matching track already exists | Stop and inspect the duplicate. iLibrary never removes the existing entry automatically. |
| A run stopped while adding an album | Keep the staging folder and journal. Preview the same `add` command before resuming; see [recovery guidance](docs/library-operations.md#interrupted-addition). |
| A catalog does not match every file | Run `validate` with the selected paths and correct the catalog or selection before applying. |
| `check` reports stale library values | Review the differences. It does not refresh, relink, rename, or delete Music entries. |
| Space is insufficient or a destination exists | Free space or choose a new destination. Do not delete an unverified original to make the command pass. |

Report problems through [GitHub Issues](https://github.com/x96x64/ilibrary/issues) with a synthetic reproduction, as [CONTRIBUTING.md](CONTRIBUTING.md#before-you-start) describes, and security problems as [SECURITY.md](SECURITY.md) describes.

## Rights and Privacy

Use audio and artwork that you are entitled to process. The repository contains synthetic fixtures and no commercial recordings, store artwork, proprietary Apple assets, or private frameworks. iLibrary does not download audio or bypass encryption. Removing purchase metadata is not a guarantee that a file contains no identifying information. Catalogs, prompts, command output, and progress journals may reveal titles, paths, or persistent IDs; review them before sharing. See [Library Operations and Recovery](docs/library-operations.md#privacy-and-reports).

## Limitations

- Live Music behavior was measured on one macOS version with Music 1.7; cloud matching remains unmeasured. Catalogs are exported from `.m4a` files only; FLAC tags reach a catalog through `import`.
- Conversion and setting creation dates require macOS. On Linux, the catalog commands and copies by `import` run, but `timestamps` requires `--dry-run`, optionally with `--script`.
- A catalog numbers discs and tracks by position; `export` reports gaps and repetitions in the files' numbers.
- Conversion supports mono and stereo only, and refuses floating-point PCM. FLAC fields outside the standard set are not carried.
- Files that would need chunk offsets beyond 32 bits are refused rather than converted to 64-bit offsets.
- Protected audio (`.m4p`) is out of scope. iLibrary does not download audio.
- Further naming rules of the Music app, such as length limits, are unknown and are not applied.
- Library comparison covers the file tracks and thirteen fields exposed by the adapter. Artwork, copyright, full release dates, and cloud-only entries not exposed as file tracks are not compared.
- Mutating batches are not transactions: a later failure can leave earlier files or albums completed. Keep backups and the addition journal; no automatic library rollback is attempted.
- Real Trash operations remain untested; public tests use a substitute Trash.
- `rebuild prepare` was exercised once on a synthetic library of 12 tracks with one external HFS+ backup drive; APFS backups and the refusal of partitions, disk images, and network volumes are covered by tests only. The later stages are tested with a substitute library and have not been run against Music. `rebuild clear` establishes an empty library by Music's track count, not by inspecting the Music window, and `rebuild add` compares exposed addition dates with the intended Recently Added order rather than observing the display. The staging directory must be on the volume of the media folder.
- `check --library` uses a bulk read only when its result is consistent and every track's cloud status is `unknown`, and otherwise uses the previous per-track read. In one maintainer-run comparison on a synthetic library of 12 tracks with macOS 27.0.1 and Music 1.7, its results matched those of the per-track read. Which read was used, its speed with larger libraries, and its behavior with other cloud statuses were not measured; libraries with other statuses keep the per-track read and its speed.

## Documentation

- [Command-Line Interface](docs/command-line-interface.md): commands, options, and exit status
- [Library Operations and Recovery](docs/library-operations.md): dry runs, interrupted runs, rebuilding, privacy, and measured Music behavior
- [Catalogs](docs/catalogs.md): the catalog format, title rules, matching, and authoring, with the [catalog JSON Schema](docs/schema/ilibrary-catalog-1.schema.json)
- [Distribution](docs/distribution.md): package names, contents, installation, and publication
- [Roadmap](docs/roadmap.md): the product's scope, rebuilding safety boundary, and verification limits
- [Changelog](CHANGELOG.md) and [releases](https://github.com/x96x64/ilibrary/releases)
- [Security Policy](SECURITY.md): supported versions and private reporting

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) for build commands, tests, and pull requests, and [AGENTS.md](AGENTS.md) for the engineering constraints. The public test suite uses original synthetic data and needs neither network access, private files, nor a Music library. Commits follow Conventional Commits.

## Star History

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/media/stars/dark.svg">
  <img src="docs/media/stars/light.svg" alt="iLibrary star counts recorded daily, beginning on October 17, 2026 (UTC)" width="720">
</picture>

Star counts are recorded daily in UTC, beginning on October 17, 2026. Lines connect recorded observations; dates before the first observation and missed observations are not reconstructed. The [recorded counts](docs/media/stars/history.json) include decreases when stars are removed.

## License

iLibrary is licensed under the [Apache License, Version 2.0](LICENSE), and every release archive and package includes a copy of it. The license permits use, modification, and redistribution in source or compiled form, for any purpose, provided that a redistribution includes the license, retains the existing copyright and attribution notices, and marks the files that were changed. It also grants a patent license from each contributor for their contributions, which terminates for anyone who brings a patent claim alleging that the software infringes. The software is provided without warranties or conditions of any kind, and contributions submitted for inclusion are accepted under the same license.

The license applies to the iLibrary source code, documentation, and executables. It grants no rights in the recordings, artwork, and metadata that you process, which remain subject to the terms of their rights holders, and no permission to use the project's name or marks except to describe the origin of the software. Apple, Apple Music, and macOS are trademarks of Apple Inc.; iLibrary uses Music and the system frameworks only through their public interfaces and includes no Apple software or assets.
