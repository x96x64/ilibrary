# Changelog

All notable changes to iLibrary are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/). Version targets stated in dated entries record the plans at the time of release; they do not establish the current support policy or a commitment to a later release.

## [Unreleased]

### Added

- `MP4Core`: parsing and rewriting of M4A item lists without re-encoding, chunk-offset relocation, verified writing through a partial file, and removal of iTunes Store purchase metadata.
- `FLACCore`: reading of FLAC stream information, Vorbis comments, and pictures.
- `CatalogCore`: the `ilibrary-catalog-1` catalog format with validation and a JSON Schema, matching of files to catalog tracks, Music-style naming, four album orders, title rules, and release dates.
- Continuous integration on macOS and Linux.
