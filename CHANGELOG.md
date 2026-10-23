# Changelog

All notable changes to iLibrary are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Version targets stated in dated entries record the plans at the time of release; they do not establish the current support policy or a commitment to a later release.

## [Unreleased]

## [1.0.0] - 2026-10-23

### Added

- A catalog reference describing every field, the title rules, matching, the authoring workflow, and release dates, which replaces the shorter guide to completing catalogs with AI agents.

### Changed

- When the request that reads the addition dates of given tracks fails, `add` and `rebuild add` read them from the bulk library read, whose dates were measured to equal Music's, instead of stopping after the first album.
- The production code was simplified without changes to commands, output, file formats, or safety checks: shared handling of paths, catalogs, and date plans, commands split into named steps, shared descriptor handling in the progress journal, and comments that referred to development history removed.
- The README, the package description, and the roadmap describe the complete product.

### Removed

- Unused internal helpers with no caller in the product, including the album designation and naming review helpers of the catalog library.

## [0.3.0] - 2026-10-23

### Added

- `rebuild stage`, `rebuild clear`, `rebuild apply`, and `rebuild add`: the staged rebuilding of an existing Music library from a recovery record. `stage` moves the inventoried files from the media folder to the staging directory; `clear` removes exactly the recorded registrations, one persistent ID per request, confirms that Music reports no tracks, and quits Music; `apply` writes the recorded catalog, names, and optional dates to the staged files while Music is closed; and `add` adds the albums in the recorded order and compares their addition dates with the expected Recently Added order. Every stage offers `--dry-run`, records its operations in an append-only progress journal, resumes after an interruption, and refuses to run out of order. `rebuild status` reports the journal. The stages are tested with a substitute library and have not been run against the Music application.
- A security policy describing supported versions and private reporting.

### Changed

- Releases are built, verified, and created on a GitHub macOS runner by the `Publish Reviewed Packages` workflow; registry publication keeps its protected environments.
- `add` adds each album only after the clock has passed the latest addition second of the album before it, and stops when Music reports an addition second for the album that does not follow it, because Recently Added orders albums by their exposed addition seconds.

### Removed

- The qualification-only executables `GUIProbeMac`, `M11Probe`, and `ReferenceProbe`, their tests, the separate-user validation scripts and procedures, the architecture spikes, and the historical engineering reports. The measured Music behavior on which the commands rely is summarized in the library operations guide, and the plan is consolidated in a single roadmap.

## [0.2.0] - 2026-10-20

### Added

- `rebuild prepare` and `rebuild status`: inventory of the selected files, classification of every Music registration, plan validation with per-volume capacity, verification of a backup on separate APFS or HFS+ storage, a restoration test that keeps its files, confirmation that the backup volume is ejected, and a versioned private recovery record in the workspace. The subcommands `stage`, `clear`, `apply`, and `add` remain reserved and end with status 2. Source files, the backup, and Music are not modified.
- `export --strict`: refuses, without writing, an export that is not a complete inventory, namely skipped paths, files dropped for a missing album tag or track number, repeated or non-consecutive disc and track numbers, declared disc and track totals that disagree with the exported counts or with each other, and release dates that are present but not a full `YYYY-MM-DD` date. The non-strict export is unchanged.

### Changed

- `check --library` reads the Music library with bulk property requests instead of one request per track and property, and uses the previous per-track read whenever the bulk read fails or is inconsistent, or when any track's cloud status is not `unknown`, the only status for which the bulk read was observed live. Its findings, output, exit status, and errors are unchanged in synthetic tests and in one live comparison on a new 12-track synthetic library; its behavior with other cloud statuses and with larger or personal libraries has not been verified.

## [0.1.0] - 2026-10-17

### Added

- README badges and daily observed Star History charts with system fonts and light and dark themes.
- npm and PyPI packages containing the same native Apple silicon executable, a source-building Homebrew formula, installation checks, and explicit publication guards.
- M5/M6 live command validation and M8 private-copy qualification reports.

- Source installation and recovery guidance, contributor and support documents, and a Japanese separate-user handoff.
- `check`: file diagnostics and optional Music comparisons by location, including duplicates, stale metadata, cloud status, and missing files.
- `doctor`: environment diagnostics with recovery steps, without launching Music or requesting permission.
- A separate-user validation script for ordered addition and library checks, with a preparation-only mode.

- `MP4Core`: parsing and rewriting of M4A item lists without re-encoding, chunk-offset relocation, verified writing through a partial file, and removal of iTunes Store purchase metadata.
- `FLACCore`: reading of FLAC stream information, Vorbis comments, and pictures.
- `CatalogCore`: the `ilibrary-catalog-1` catalog format with validation and a JSON Schema, matching of files to catalog tracks, Music-style naming, four album orders, title rules, and release dates.
- Continuous integration on macOS and Linux.
- The commands `export` with `--dry-run`, `prompt`, `schema`, `validate`, `apply` with `--dry-run`, `--rename`, and `--timestamps`, and `timestamps` with `--dry-run` and `--script`.
- `LibraryMac`: setting file and folder dates on macOS without creating missing paths or following symbolic links.
- `ConversionMac`: conversion of FLAC, WAV, and AIFF to Apple Lossless on macOS, verified by decoded PCM.
- The command `add` with `--order` and `--dry-run`: albums moved into the Music media folder and added one at a time, each confirmed before the next, with resumption of interrupted runs.
- The command `import` with `--from`, `--delete-originals`, and `--dry-run`: lossless conversion that carries standard FLAC tags and the front cover, and copies of iTunes Store files without purchase metadata. Originals are moved to the Trash only after every output has been verified.

### Changed

- A file whose title differs from the catalog's at its disc and track numbers is matched there when no other track carries its title and more of the album's titles agree than differ, so that catalogs can correct titles.
