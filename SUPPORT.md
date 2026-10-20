# Support

## Supported Versions

iLibrary is experimental; the published version is 0.1.0 until version 0.2.0 is released. Read [Current Status](docs/roadmap-to-stable.md), the [Command-Line Interface](docs/command-line-interface.md), and [Library Operations and Recovery](docs/library-operations.md). The Music commands passed [separate-user validation](docs/reports/library-command-validation.md); other system versions and cloud behavior remain unverified.

Report the installed version and, where possible, reproduce the problem with the current release. The interface remains experimental; review the [changelog](CHANGELOG.md) before updating.

## Supported Platforms

| Component | Supported |
| --- | --- |
| Packaged operating system | macOS 14 or later; qualification used macOS 27.0.1 |
| Processor | Apple silicon; packaged executables are arm64 |
| Installation | Homebrew and source builds require Swift 6; npm and pip contain a prebuilt executable |
| Conversion | Integer mono and stereo FLAC, WAV, and AIFF to Apple Lossless |
| Music operations | macOS with Automation permission; validate in a separate test user first |
| Linux | Development and tests for the portable targets; no Linux package is distributed |

The deployment target does not establish successful execution on every intervening OS release. Developer ID signing, notarization, real Trash operations, and cloud behavior remain unverified.

## Getting Help

Use `ilibrary --version` and, in the intended test environment, `ilibrary doctor`. The latter does not launch Music or inspect tracks, but its output can include the media-folder path. Review [Troubleshooting](README.md#troubleshooting) and do not post complete diagnostics without checking them for private information.

Report problems through [GitHub Issues](https://github.com/x96x64/ilibrary/issues). Include:

- The commit (`git rev-parse --short HEAD`), iLibrary version, macOS or Linux version, and Swift version.
- The command with paths replaced by neutral placeholders, and whether `--dry-run` was used.
- The expected result, the actual result, exit status, and a short sanitized error excerpt.
- Whether the problem can be reproduced with generated audio; provide synthetic steps when possible.
- For Music problems, whether the test used a separate user without an Apple Account. Do not include the account name or library identifiers.

Do not upload purchased audio, store artwork, catalogs from a real library, Apple Account information, `.ilibrary-add.json`, or unredacted logs. A report can describe unavailable evidence without sharing it. The separate-user validation script produces a sanitized result specifically for reporting; see [its procedure](docs/test-library-validation.md#step-4-report-the-result).

### When an Operation Stops

Keep originals, staging folders, and journals. Do not delete tracks or overwrite destinations to force a retry. Follow [interrupted-operation guidance](docs/library-operations.md#interrupted-addition). A successful earlier file or album does not establish completion of the batch.

## Out of Scope

Protected audio, audio downloads, automatic removal of Music library entries, and guarantees against Apple Music cloud matching are outside the supported workflow. Apple Account and subscription problems require Apple's support. Do not provide private library data or commercial recordings as reproductions.
