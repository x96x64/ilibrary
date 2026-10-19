# Contributing to iLibrary

## Development Setup

Read [AGENTS.md](AGENTS.md), [Current Status](docs/roadmap-to-stable.md), and the historical [Technical Planning Study](docs/planning-study.md) before architectural changes. Work in this repository and use a focused branch. The source build requires Swift 6; current verification uses Apple Swift 6.4 on macOS and Swift 6.4 on Linux.

```sh
swift build -c release
scripts/test.sh
swift format lint --strict --recursive Sources Tests Package.swift scripts
```

The test wrapper supplies Swift Testing discovery paths when the selected Command Line Tools require them. It does not open Music. Core logic and portable commands build on Linux; Apple frameworks remain in `ConversionMac` and `LibraryMac`. No external tool or package dependency is required at runtime.

## Verification

Use generated audio and original synthetic metadata for public tests. Tests must work without private files, network access, an Apple Music subscription, or a populated library. Check decoding and PCM equality for lossless conversion, and audio-stream preservation for metadata rewrites. Test refusal paths and unchanged originals as well as successful writes.

On macOS, additional verification is available:

```sh
scripts/validation/catalog-commands.sh
scripts/validation/import.sh
scripts/validation/library-commands.sh --prepare-only
```

The first two scripts use independent reference tools, including FFmpeg/ffprobe, exiftool, and FLAC tools, in addition to Apple's command-line tools. Those tools are verification dependencies only. The preparation-only script uses generated audio and never queries Music. Outputs stay under ignored `artifacts/`. Do not run `--run-live` in a personal user: follow [Test Library Validation](docs/test-library-validation.md). Reference-validation scripts require explicit permission and ignored local inputs; they are not part of the public suite.

## Changes and Evidence

Distribution changes also require the offline package checks and isolated installation procedure in [Distribution](docs/distribution.md). Do not publish from a development test. Registry publication uses only explicitly reviewed release files; ordinary pushes and tag events do not publish packages.

Every mutating command must offer a dry run, print a plan before changes, and verify results. Retain verified originals until the selected operation permits removal; do not introduce automatic library cleanup. Keep tests proportional to the changed behavior and include regression cases for safety fixes.

Classify evidence as **measured**, **inferred**, or **unknown**. A test double does not measure Music, and an older application probe does not qualify a new command. Preserve completed engineering reports; add a new report for subsequent findings. Use MLA title case for English documentation titles and headings while retaining command and API capitalization. In newly written English prose, use straight quotation marks (U+0027 and U+0022) rather than typographic ones; leave code, literal data, fixtures, and historical quotations unchanged.

## Commits and Pull Requests

Use small Conventional Commits: `type(scope): imperative subject`, in formal English. Preserve the human author and committer. Add the supported co-author trailers required by AGENTS.md only for material contributions. Avoid generated files, personal paths, credentials, commercial titles, or private metadata in commits and messages.

Before a commit, review staged changes and run appropriate checks. Before publication, inspect the proposed history, untracked and ignored-file categories, and every staged path. Confirm that `reference-private/` and generated output remain ignored. Never publish the contents of those directories.

Describe the problem, resulting behavior, relevant tests, and remaining uncertainty in the pull request. Milestones integrate through pull requests. Update Current Status at each milestone so another agent can resume from the repository. Pushes, releases, tags, and package publication require authorization in the active conversation; existing authorization covers only its stated scope. Show changed-document previews, the principal summary, verification results, and the privacy check, in English, before each push.
