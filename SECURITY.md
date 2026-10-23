# Security Policy

## Supported Versions

Security fixes are made on `main` and released in the next version of iLibrary. Only the latest published release receives fixes; earlier releases are not patched separately, so upgrade through the channel you installed from before reporting a problem. The [releases page](https://github.com/x96x64/ilibrary/releases) lists the current version, and `ilibrary --version` prints the installed one.

Packaged executables target macOS 14 or later on Apple silicon and are signed ad hoc, without Developer ID signing or notarization. Source and Homebrew builds compile the same code with your own Swift toolchain. Linux builds exist only for development and tests.

## Reporting a Vulnerability

Do not describe a suspected vulnerability in a public issue, pull request, or discussion. If the repository's Security tab offers "Report a vulnerability", use that private form. Otherwise, open a short issue titled "Request for a private security contact", without technical details, and wait for a private channel to be arranged before sending the report.

A useful report names the iLibrary version or commit, the macOS version, the command and options with paths replaced by placeholders, and the effect you observed or expect. Reproduce the problem with generated audio and synthetic catalogs where possible. Never send purchased audio, a real library export, recovery records, journals, Apple Account details, or unredacted logs.

## What Counts as a Security Problem

iLibrary runs with your user's permissions and modifies files and a Music library that you own, so the most serious problems are those that change or remove data outside the selected scope. Examples are a path in a catalog, journal, or recovery record that makes a command write, move, or delete a file outside the selected directories; a symbolic link that a command follows although it should refuse it; text from file tags or catalogs that is interpreted as AppleScript instead of being quoted; an original deleted before its replacement was verified; and a registration removed from Music that the recovery record does not list.

Problems that depend on an attacker who already controls your user account, or on files you deliberately modified to defeat a documented check, are generally out of scope, although reports of them are still welcome. Apple Music's own behavior, including cloud matching, is not an iLibrary vulnerability.

## Safety Properties

Every mutating command offers `--dry-run` and prints its plan before changing anything. Rewrites go through a hidden partial file that is parsed and compared before it replaces the destination. Originals are moved to the Trash only after every output has been verified, and only when requested. Timestamp operations refuse missing paths and symbolic links. The addition journal is validated before it authorizes any move or library operation, the recovery record and progress journal of a rebuild carry checksums and are refused when damaged or edited, and the rebuild stages refuse to run out of order.

iLibrary has no network component: it never downloads audio, contacts a server, or sends telemetry. It controls only the Music application, through Apple Events that macOS permits only after you grant the Automation permission.

## Handling and Disclosure

Reports are acknowledged as soon as the maintainer can review them. A confirmed problem is fixed on `main` with a regression test and released in a new version, and the changelog describes the fix once a release is available. Credit is given in the changelog if the reporter wishes.

Because iLibrary is maintained by one person as a personal project, no response time is guaranteed. Please allow a reasonable period for a fix before disclosing details publicly.
