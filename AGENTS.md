# iLibrary Engineering Constraints

## Project Identity

Use `iLibrary` as the product name and `ilibrary` for the executable, repository, and lowercase technical identifiers. The interface is a command-based CLI with verb subcommands, modeled on established tools such as ripgrep, fd, GitHub CLI, Git, and FFmpeg and on the sibling project iLyrics; do not introduce an interactive text user interface. [docs/roadmap.md](docs/roadmap.md) is the authoritative plan, and [CONTRIBUTING.md](CONTRIBUTING.md) describes building, testing, and submitting changes.

The repository `README.md` is the canonical description of the product. `packaging/README.md` is the single condensed description shipped to npm and PyPI; derive it from the README with the same section order, terminology, installation-channel order (Homebrew, npm, PyPI), and absolute links, and review both at every release. Every GitHub release is titled exactly `iLibrary: vX.Y.Z, Catalog-Driven Music Libraries for Apple Music on macOS`, with only the version substituted; see [Release Titles](docs/distribution.md#release-titles).

## Architecture

Keep domain logic in the Foundation-only targets `MP4Core`, `FLACCore`, `CatalogCore`, and `RebuildCore`, which build and test on Linux. Confine AppKit, AudioToolbox, AVFoundation, and Apple Events to `ConversionMac` and `LibraryMac`. The command logic in `ilibrary` reaches Music only through the `MusicLibrary` protocol, so that it is tested with substitute libraries.

Do not depend on external tools such as AtomicParsley, exiftool, or FFmpeg at run time; they may be used only as independent references during verification. Do not add package dependencies. Classify findings about Apple Music as measured, inferred, or unknown, and never present unmeasured Music or iCloud Music Library behavior as measured. iLibrary removes store identifiers and reports cloud status, but it does not claim to prevent cloud matching.

## Library Safety

iLibrary modifies user-owned music files and an Apple Music library. Every mutating command offers `--dry-run`, states what it will change before changing it, and verifies its result afterwards.

- Never delete an original file unless the user requests deletion and the replacement has been verified: decoded duration, codec, and, for lossless conversion, decoded PCM equality.
- Check free space before conversions and moves. Treat truncated or partially written outputs as failures.
- Move files into the Music media folder instead of copying them, and add them album by album. Ordinary `add` stops when the library already contains a matching track and never removes library entries.
- Only `rebuild clear` removes registrations, and only those recorded by `rebuild prepare`, after a verified backup, a passing restoration test, and a verified evacuation of every file. It addresses each track by persistent ID, one operation per call, and stops on any registration that the record does not explain.
- Never set track properties through Music. Changing an album or location makes Music reorganize files, which can split an album and break file references. Write tags to files, arrange folders, and then add tracks.
- Music caches metadata independently of files. After editing files, compare the file and the library and report every difference.
- Never create a filesystem entry as a side effect of setting timestamps. A timestamp operation on a missing path does nothing and reports the path.
- Leave source files that the user did not select untouched.

Development and automated agents never operate on the maintainer's personal Music library or personal files. Music behavior is tested with substitute libraries and synthetic files.

## Scope and Rights

Do not incorporate proprietary Apple assets, private frameworks, store artwork, commercial recordings, credentials, Apple Account identifiers, or private library data. Public fixtures, examples, and tests use original synthetic albums and generated audio. Protected audio (`.m4p`) is out of scope, and iLibrary does not download audio.

Keep real purchased or downloaded files, library exports, and their derivatives under the ignored `reference-private/` directory, and keep generated outputs and machine-specific logs under the ignored `artifacts/` directory. Record hardware and toolchain context without hostnames, serial numbers, device identifiers, Apple Account details, or personal paths. The software is licensed under the Apache License, Version 2.0.

## Verification

Test box parsing and rewriting, chunk-offset relocation, catalog matching, naming, ordering, title rules, date handling, and rebuild planning with synthetic inputs. Validate conversions by decoding and comparing PCM, not by byte equality of encoded files. Test refusal paths and unchanged originals as well as successful writes, and add a regression test with every safety fix.

Cloud and Linux environments build and test the Foundation-only targets and the command logic; macOS-only code is verified through the macOS CI job. Every change reaches `main` through a pull request whose CI passes. Keep `docs/roadmap.md` accurate as milestones complete.

## Documentation and Commits

Use MLA headline-style title case for English documentation titles and headings while preserving the capitalization of product names, APIs, commands, files, options, and identifiers. Write documentation in precise, restrained English without promotional language. In new prose, use U+0027 and U+0022 rather than typographic quotation marks, and separate paired concepts with the middle dot "・" (U+30FB) where a slash would otherwise appear in running prose, keeping literal slashes in paths, URLs, commands, code, and established expressions.

Follow [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): subject`, with a lowercase, imperative, specific subject without a trailing period. Use a body only for rationale and consequences. Keep the human author and committer identities. When an AI assistant materially contributes to a commit, add the corresponding `Co-Authored-By` trailer in [GitHub's format](https://docs.github.com/en/pull-requests/how-tos/commit-changes/creating-a-commit-with-multiple-authors); do not add trailers to unassisted commits.
