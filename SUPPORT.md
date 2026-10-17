# Support

## Before Reporting a Problem

iLibrary 0.1.0 is experimental. Read [Current Status](docs/roadmap-to-stable.md), the [Command-Line Interface](docs/command-line-interface.md), and [Library Operations and Recovery](docs/library-operations.md). The Music commands passed [separate-user validation](docs/reports/library-command-validation.md); other system versions and cloud behavior remain unverified.

Use `ilibrary --version` and, in the intended test environment, `ilibrary doctor`. The latter does not launch Music or inspect tracks, but its output can include the media-folder path. Do not post the complete output without reviewing it.

## A Useful Report

Report problems through [GitHub Issues](https://github.com/x96x64/ilibrary/issues). Include:

- The commit (`git rev-parse --short HEAD`), iLibrary version, macOS or Linux version, and Swift version.
- The command with paths replaced by neutral placeholders, and whether `--dry-run` was used.
- The expected result, the actual result, exit status, and a short sanitized error excerpt.
- Whether the problem can be reproduced with generated audio; provide synthetic steps when possible.
- For Music problems, whether the test used a separate user without an Apple Account. Do not include the account name or library identifiers.

Do not upload purchased audio, store artwork, catalogs from a real library, Apple Account information, `.ilibrary-add.json`, or unredacted logs. A report can describe unavailable evidence without sharing it. The separate-user validation script produces a sanitized result specifically for reporting; see [its procedure](docs/test-library-validation.md#step-4-report-the-result).

## When an Operation Stops

Keep originals, staging folders, and journals. Do not delete tracks or overwrite destinations to force a retry. Follow [interrupted-operation guidance](docs/library-operations.md#interrupted-addition). A successful earlier file or album does not establish completion of the batch.
