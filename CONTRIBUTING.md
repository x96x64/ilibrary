# Contributing to iLibrary

## Before You Start

iLibrary changes music files and an Apple Music library, so every contribution is judged first by whether it keeps those safe. Read [AGENTS.md](AGENTS.md) for the engineering constraints and [docs/roadmap.md](docs/roadmap.md) for the plan before proposing a larger change. Open an issue to discuss new commands, catalog-format changes, or anything that alters how files are moved, rewritten, or removed.

Bug reports are most useful when they include a synthetic reproduction. Do not attach real catalogs, journals, recovery records, command output, or audio files without reviewing them: they can contain titles, paths, persistent IDs, and copyrighted material. Report security problems as described in [SECURITY.md](SECURITY.md) rather than in a public issue.

## Development Setup

The source build requires Swift 6 and no other dependency. Verification currently uses Apple Swift 6.4 on macOS and Swift 6.4 on Linux.

```sh
swift build -c release
scripts/test.sh
swift format lint --strict --recursive Sources Tests Package.swift scripts
```

`scripts/test.sh` runs the whole test suite and supplies the Swift Testing discovery paths that some Command Line Tools installations omit. On Linux, only the Foundation-only targets and the command logic build; run them with `swift test --disable-xctest --filter 'MP4CoreTests|FLACCoreTests|CatalogCoreTests|RebuildCoreTests|ilibraryTests'`. The [`swift:6.4-noble`](https://hub.docker.com/_/swift) image used by CI reproduces that environment.

## Project Layout

`MP4Core`, `FLACCore`, `CatalogCore`, and `RebuildCore` hold the portable logic: MP4 boxes and item lists, FLAC metadata, the catalog format with matching, naming, ordering, and title rules, and the backup inventory, recovery record, and progress journal of a rebuild. `ConversionMac` converts audio through AudioToolbox, and `LibraryMac` sets file dates and talks to Music through Apple Events. The `ilibrary` target parses commands, builds plans, and prints reports.

Command logic reaches Music only through the `MusicLibrary` protocol and reaches the file system through small injectable operations. Tests use the substitute library in `Tests/ilibraryTests` and the generated media in `Tests/SyntheticMedia`, so that the suite needs no Music library, network access, private files, or Apple Music subscription.

## Writing Tests

Use generated audio and original synthetic metadata. Check decoded PCM equality for lossless conversion and audio-stream preservation for metadata rewrites. Test refusal paths and unchanged originals as well as successful writes, and add a regression test with every safety fix. Keep tests proportional to the changed behavior.

A substitute library shows how iLibrary reacts to the answers Music gives; it does not show what Music does. Describe behavior of the real application as measured only when it was observed in Music, and state the macOS and Music versions. Independent tools such as FFmpeg, ffprobe, or exiftool may be used to cross-check results during development, but no test or command may depend on them.

## Changes to Commands

Every mutating command offers `--dry-run`, prints its plan before changing anything, and verifies its result afterwards. Keep originals until the selected operation permits their removal, and never introduce automatic library cleanup outside `rebuild clear`. Update the command help, [docs/command-line-interface.md](docs/command-line-interface.md), and the README together when behavior or options change.

Distribution changes also require the offline package checks in [docs/distribution.md](docs/distribution.md). Ordinary pushes and tags never publish packages; registry publication uses only reviewed release files.

## Commits and Pull Requests

Use small [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): imperative subject` in lowercase, without a trailing period, with a body only for rationale and consequences. Keep the human author and committer. Add a `Co-Authored-By` trailer only for a material contribution by an AI assistant. Never commit generated files, personal paths, credentials, commercial recordings, or private metadata, and confirm that `reference-private/` and `artifacts/` remain ignored.

Describe the problem, the resulting behavior, the tests, and any remaining uncertainty in the pull request. Both CI jobs must pass before merging. Use MLA title case for documentation headings, and straight quotation marks (U+0027 and U+0022) in new prose.
