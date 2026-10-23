# iLibrary

[![Release](https://img.shields.io/github/v/release/x96x64/ilibrary)](https://github.com/x96x64/ilibrary/releases)
[![npm](https://img.shields.io/npm/v/%40x96_64%2Filibrary)](https://www.npmjs.com/package/@x96_64/ilibrary)
[![PyPI](https://img.shields.io/pypi/v/x96-64-ilibrary)](https://pypi.org/project/x96_64-ilibrary/)
[![Homebrew](https://img.shields.io/badge/Homebrew-x96x64%2Ftap-FBB040?logo=homebrew&logoColor=white)](https://github.com/x96x64/homebrew-tap)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://github.com/x96x64/ilibrary#requirements)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/x96x64/ilibrary/blob/main/LICENSE)

iLibrary prepares downloaded music for a local Apple Music library and adds it in a controlled order. It converts lossless downloads to Apple Lossless, copies iTunes Store purchases without their purchase metadata, applies metadata from a catalog file without re-encoding, names files as the Music app does, and sets file dates to release dates. It adds albums to Music one at a time and diagnoses differences between files and library records. This package description is condensed from the [iLibrary README](https://github.com/x96x64/ilibrary#readme), which is the complete reference.

> **Important:** iLibrary moves and rewrites your music files and changes your Music library. Begin with copies, keep independent backups of your library, and review every dry run. File processing is verified with synthetic tests, and Music operations are tested with a substitute library; the requests that iLibrary sends to Music use forms measured on macOS 27.0.1 with Music 1.7, but the rebuilding stages have not been run against the Music application. iLibrary does not prevent Apple Music cloud matching and is not affiliated with, endorsed by, or sponsored by Apple.

## Features

- **Ordered addition to Music.** `add` moves each album into the Music media folder, adds it there in place, and confirms one track per file before the next album, in release or artist order. Each album is added only after the clock has passed the previous album's addition second, so that Recently Added shows the intended order. It stops when the library already holds a matching track, never changes a track in Music, and resumes an interrupted run.
- **Lossless import.** `import` converts FLAC, WAV, and AIFF downloads to Apple Lossless, verified by decoded PCM equality, and copies iTunes Store files without re-encoding while removing purchase metadata. With `--delete-originals`, originals are moved to the Trash only after every output has been verified.
- **Catalog commands.** `export` drafts a catalog from existing tags, `prompt` prepares it for completion by an AI agent or chat, `validate` checks it and its correspondence with files, and `apply` writes it to the files without re-encoding audio. `export --strict` refuses, without writing, an export that is not a complete inventory.
- **Music-style names and release dates.** `apply --rename` arranges files as `Album Artist/Album/NN Song.m4a`, and `timestamps` sets file and folder dates to release dates. Missing paths are never created, and symbolic links are refused.
- **Library rebuilding.** `rebuild prepare` inventories the selected files and Music registrations, verifies a backup on separate storage, performs a restoration test, confirms that the backup volume is ejected, and writes a private recovery record. `rebuild stage` then moves the files out of the media folder, `rebuild clear` removes exactly the recorded registrations and confirms that Music reports no tracks, `rebuild apply` writes the catalog to the files while Music is closed, and `rebuild add` adds the albums again in the chosen order. Every stage records its progress, resumes after an interruption, and refuses to run out of order.
- **Checks and diagnostics.** `check` reports missing tags, duplicate tracks, and incorrect dates; `check --library` compares files with Music by location. `doctor` reports environment problems and recovery steps without launching Music or reading its library.

Every mutating command offers `--dry-run`, states what it will change before changing it, and verifies its result afterwards.

## Requirements

- macOS 14 or later on Apple silicon
- A Swift 6 toolchain supplied by Xcode or the Command Line Tools for source or Homebrew builds
- npm or Python 3.9 or later for the corresponding package installer; neither is needed by the native executable

The package declares macOS 14 as its deployment target, which is not a claim of testing every release since; releases are built and tested on GitHub's macOS runner, and Music behavior was measured on macOS 27.0.1 with Music 1.7. Packaged binaries are ad hoc-signed; Developer ID signing and notarization are not provided. Music commands require the installed Music app and Automation permission. An Apple Music subscription and Apple Account are not required for local file processing.

## Installation

The following commands install version 1.0.1. Choose one channel, and use only that channel in a given shell or environment, so that updating it updates the command you run. Every channel installs the same command, `ilibrary`. The package names include the author because `ilibrary` on npm and PyPI belongs to other projects, and PyPI does not support npm scopes.

### Homebrew

```bash
brew install x96x64/tap/ilibrary
ilibrary --version
```

The formula downloads the release source archive, which Homebrew checks against the checksum recorded in the formula, and builds it on your Mac. It requires Swift 6 or later from Xcode or the Command Line Tools and installs only the `ilibrary` executable.

### npm

```bash
npm install -g @x96_64/ilibrary@1.0.1
ilibrary --version
```

The package contains the prebuilt executable and declares `darwin` and `arm64`, so that npm refuses it on other systems. It runs no installation script and needs no Swift toolchain, and each version is published with npm provenance that links it to the commit and workflow run that built it.

### PyPI (pip)

Install in a virtual environment to avoid changing the system Python:

```bash
python3 -m venv .venv-ilibrary
.venv-ilibrary/bin/python -m pip install x96_64-ilibrary==1.0.1
.venv-ilibrary/bin/ilibrary --version
source .venv-ilibrary/bin/activate
```

npm and PyPI install the same native executable. To build from source instead, follow [From Source](https://github.com/x96x64/ilibrary#from-source) in the iLibrary README.

### Updating

Read the [changelog](https://github.com/x96x64/ilibrary/blob/main/CHANGELOG.md) and [Roadmap](https://github.com/x96x64/ilibrary/blob/main/docs/roadmap.md) before updating. Use `brew upgrade ilibrary`, `npm update -g @x96_64/ilibrary`, or `python -m pip install --upgrade x96_64-ilibrary` in the selected virtual environment.

Updating replaces the executable only; catalogs, staging folders, addition journals, and rebuild workspaces remain unchanged. If an `add` run or a rebuild stage was interrupted, keep its staging folder and journal and read [Library Operations and Recovery](https://github.com/x96x64/ilibrary/blob/main/docs/library-operations.md) before resuming with the new version.

### Uninstalling

Use `brew uninstall ilibrary`, `npm uninstall -g @x96_64/ilibrary`, or `python -m pip uninstall x96_64-ilibrary` in the selected environment. iLibrary has no background service. Keep catalogs, artwork, staging files, and `.ilibrary-add.json` journals until their recovery purpose is complete; removing the executable does not undo file or Music changes.

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

For the remaining Music step, preview `ilibrary add ./staging --order release --dry-run` before running without `--dry-run`, then compare the added files with `check --library`. `add` moves selected files out of staging; it retains a progress journal there. See [Library Operations and Recovery](https://github.com/x96x64/ilibrary/blob/main/docs/library-operations.md) before resuming an interrupted run.

## Usage

iLibrary is a command-based CLI with verb subcommands. The [Command-Line Interface](https://github.com/x96x64/ilibrary/blob/main/docs/command-line-interface.md) reference describes each command, and `ilibrary help COMMAND` prints its options.

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

The `rebuild` stages run in the order `prepare`, `stage`, `clear`, `apply`, and `add`, and `status` reports where a rebuild stands. See the [command reference](https://github.com/x96x64/ilibrary/blob/main/docs/command-line-interface.md#rebuild).

Exit status is 0 on success, 1 on a failure or a finding from `check` or `doctor`, and 2 on a usage error. `check` requires at least one path or `--library`.

## Rebuilding a Library

`rebuild` turns an existing local library into the state that a catalog describes, with Recently Added showing the albums in the chosen order. `rebuild prepare` verifies a backup on a separate device and writes a private recovery record; `stage`, `clear`, `apply`, and `add` then move the files out of the media folder, remove exactly the recorded registrations, write the catalog while Music is closed, and add the albums again one at a time. Playlists, ratings, and play counts are not kept, and iCloud Music Library is not supported. See [Rebuilding a Library](https://github.com/x96x64/ilibrary#rebuilding-a-library) in the iLibrary README.

## Catalogs

A catalog is a UTF-8 JSON document identified by `"format": "ilibrary-catalog-1"`. Album-level values apply to every track and may be overridden per track, and an empty string means that a value is unknown. `ilibrary schema` prints the [JSON Schema](https://github.com/x96x64/ilibrary/blob/main/docs/schema/ilibrary-catalog-1.schema.json), and [Catalogs](https://github.com/x96x64/ilibrary/blob/main/docs/catalogs.md) describes every field, the title rules, matching, and the authoring workflow.

## Apple Music and Cloud Matching

Albums imported into a library with iCloud Music Library may be identified with albums in the Apple Music catalog, and then shown with that catalog's metadata and artwork. The matching decision belongs to Apple's service. iLibrary removes store identifiers and reports the cloud statuses exposed by Music. The effect of identifier removal on cloud matching has not been measured, and iLibrary does not claim to prevent matching. An `unknown` status is inconclusive.

## Troubleshooting

| Symptom | Next Step |
| --- | --- |
| Music cannot be controlled | Run `doctor` and follow its Automation permission instructions. |
| A matching track already exists | Stop and inspect the duplicate. iLibrary never removes the existing entry automatically. |
| A run stopped while adding an album | Keep the staging folder and journal. Preview the same `add` command before resuming; see the [recovery guidance](https://github.com/x96x64/ilibrary/blob/main/docs/library-operations.md#interrupted-addition). |
| A catalog does not match every file | Run `validate` with the selected paths and correct the catalog or selection before applying. |
| `check` reports stale library values | Review the differences. It does not refresh, relink, rename, or delete Music entries. |
| Space is insufficient or a destination exists | Free space or choose a new destination. Do not delete an unverified original to make the command pass. |

Report problems through [GitHub Issues](https://github.com/x96x64/ilibrary/issues) with a synthetic reproduction, and security problems as the [security policy](https://github.com/x96x64/ilibrary/blob/main/SECURITY.md) describes.

## Rights and Privacy

Use audio and artwork that you are entitled to process. iLibrary does not download audio, bypass encryption, or distribute commercial recordings or store artwork. Removing purchase metadata is not a guarantee that a file contains no identifying information. Catalogs, prompts, command output, and progress journals may reveal titles, paths, or persistent IDs; review them before sharing.

## Limitations

- Live Music behavior was measured on one macOS version with Music 1.7; cloud matching remains unmeasured. Catalogs are exported from `.m4a` files only; FLAC tags reach a catalog through `import`.
- Conversion supports mono and stereo only, and refuses floating-point PCM. Protected audio (`.m4p`) is out of scope.
- Library comparison covers the file tracks and thirteen fields exposed by the adapter.
- Mutating batches are not transactions: a later failure can leave earlier files or albums completed. Keep backups and the addition journal; no automatic library rollback is attempted.
- Real Trash operations remain untested; public tests use a substitute Trash.
- `rebuild prepare` was exercised once on a synthetic library of 12 tracks with one external HFS+ backup drive; APFS backups and the refusal of partitions, disk images, and network volumes are covered by tests only. The later stages are tested with a substitute library and have not been run against Music. `rebuild clear` establishes an empty library by Music's track count, not by inspecting the Music window, and `rebuild add` compares exposed addition dates with the intended Recently Added order rather than observing the display. The staging directory must be on the volume of the media folder.
- `check --library` uses a bulk read only when its result is consistent and every track's cloud status is `unknown`, and otherwise uses the previous per-track read. In one maintainer-run comparison on a synthetic library of 12 tracks with macOS 27.0.1 and Music 1.7, its results matched those of the per-track read. Which read was used, its speed with larger libraries, and its behavior with other cloud statuses were not measured; libraries with other statuses keep the per-track read and its speed.

See [Limitations](https://github.com/x96x64/ilibrary#limitations) in the iLibrary README for the complete list.

## Documentation

- [README](https://github.com/x96x64/ilibrary#readme): the complete project description
- [Command-Line Interface](https://github.com/x96x64/ilibrary/blob/main/docs/command-line-interface.md): commands, options, and exit status
- [Library Operations and Recovery](https://github.com/x96x64/ilibrary/blob/main/docs/library-operations.md): dry runs, interrupted runs, rebuilding, privacy, and measured Music behavior
- [Catalogs](https://github.com/x96x64/ilibrary/blob/main/docs/catalogs.md): the catalog format, title rules, matching, and authoring
- [Distribution](https://github.com/x96x64/ilibrary/blob/main/docs/distribution.md): package names, contents, installation, and publication
- [Roadmap](https://github.com/x96x64/ilibrary/blob/main/docs/roadmap.md): the product's scope, rebuilding safety boundary, and verification limits
- [Changelog](https://github.com/x96x64/ilibrary/blob/main/CHANGELOG.md) and [releases](https://github.com/x96x64/ilibrary/releases)
- [Security Policy](https://github.com/x96x64/ilibrary/blob/main/SECURITY.md) and the [issue tracker](https://github.com/x96x64/ilibrary/issues)

## License

iLibrary is licensed under the [Apache License, Version 2.0](https://github.com/x96x64/ilibrary/blob/main/LICENSE), and this package includes a copy of it. The license permits use, modification, and redistribution in source or compiled form, for any purpose, provided that a redistribution includes the license, retains the existing copyright and attribution notices, and marks the files that were changed. It grants a patent license from each contributor, and the software is provided without warranties or conditions of any kind.

The license applies to the iLibrary software only. It grants no rights in the recordings, artwork, and metadata that you process, which remain subject to the terms of their rights holders, and no permission to use the project's name or marks except to describe the origin of the software. Apple, Apple Music, and macOS are trademarks of Apple Inc.; iLibrary uses Music and the system frameworks only through their public interfaces and includes no Apple software or assets.
