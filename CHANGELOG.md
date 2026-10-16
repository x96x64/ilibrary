# Changelog

All notable changes to iLibrary are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Version targets stated in dated entries record the plans at the time of release; they do not establish the current support policy or a commitment to a later release.

## [Unreleased]

### Added

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
