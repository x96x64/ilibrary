# Changelog

All notable changes to iLibrary are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Version targets stated in dated entries record the plans at the time of release; they do not establish the current support policy or a commitment to a later release.

## [Unreleased]

### Added

- `rebuild prepare` and `rebuild status` (0.2.0 development state, not released): inventory of the selected files, classification of every Music registration, plan validation with per-volume capacity, verification of a backup on separate APFS or HFS+ storage, a restoration test that keeps its files, confirmation that the backup volume is ejected, and a versioned private recovery record in the workspace. The subcommands `stage`, `clear`, `apply`, and `add` are reserved and end with status 2. Source files, the backup, and Music are not modified.
- `export --strict`: refuses, without writing, an export that is not a complete inventory, namely skipped paths, files dropped for a missing album tag or track number, repeated or non-consecutive disc and track numbers, declared disc and track totals that disagree with the exported counts or with each other, and release dates that are present but not a full `YYYY-MM-DD` date. The non-strict export is unchanged.

### Changed

- `check --library` reads the Music library with bulk property requests instead of one request per track and property, and uses the previous per-track read whenever the bulk read fails or is inconsistent. Its findings, output, exit status, and errors are unchanged in synthetic tests; its live behavior has not yet been verified.

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
