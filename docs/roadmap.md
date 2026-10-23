# Roadmap to iLibrary 1.0.0

## Product Objective

iLibrary 1.0.0 automates the preparation and organization of a personal, local Apple Music library on macOS. It converts FLAC, WAV, and AIFF downloads to Apple Lossless; prepares purchased iTunes Store AAC files without re-encoding while removing purchaser and store metadata; applies catalog-based titles, artists, album artists, composers, genres, artwork, copyright, and release dates; normalizes titles; arranges files and folders as Music does; optionally sets release-date timestamps; adds albums in one of four orders so that Recently Added presents the intended sequence; and rebuilds an existing local library into that state.

The project is a personal tool maintained by one person. Reasonable file preservation, previews, error detection, and recovery are required. Exhaustive environment certification, repeated manual qualification, and formal proof of every hypothetical failure are not objectives. No release depends on further maintainer-operated test sessions, on a second macOS account, or on access by an agent to the maintainer's personal library.

This document supersedes the earlier stable-release plan, the M10 to M15 milestone sequence, and the status log that accompanied them. Their completed measurements remain valid evidence and are summarized in [Measured Music Behavior](library-operations.md#measured-music-behavior).

## Implemented Capabilities

Version 0.3.0 implements the complete workflow. `import` converts lossless downloads with decoded PCM verification and copies iTunes Store files without purchase metadata. `export`, `prompt`, `schema`, `validate`, and `apply` draft, complete, check, and write catalogs, with Music-style renaming and release-date timestamps. `add` moves albums into the media folder and adds them one at a time in four orders, each after the previous album's addition second, with resumption. `check` and `doctor` diagnose files, the library, and the environment.

`rebuild prepare` inventories the selected files and every Music registration, verifies a backup on separate storage, tests restoration, confirms that the backup volume is disconnected, and writes an immutable recovery record. `rebuild stage`, `clear`, `apply`, and `add` then move the files out of the media folder, remove exactly the recorded registrations, write the catalog to the files while Music is closed, and add the albums again in the recorded order, recording every operation in an append-only progress journal that `rebuild status` reports.

The Foundation-only targets (`MP4Core`, `FLACCore`, `CatalogCore`, `RebuildCore`) and the command logic build and test on Linux. Conversion, file dates, and Music automation are confined to the macOS targets `ConversionMac` and `LibraryMac` and are verified by macOS CI with substitute libraries.

## Remaining Product Work

No planned user-facing capability remains unimplemented. The rebuilding stages are tested with a substitute library and have not been run against the Music application; their Music requests use the forms measured in the separate-user qualifications, except the reading of addition dates by persistent ID and the request to quit, which were not among the measured forms. These are documented limitations rather than gaps in the workflow.

The work before 1.0.0 is engineering quality: a final pass over all production code, comments, and documentation, and the distribution review described below.

## Rebuilding Safety Boundary

The earlier plan required an automatic detector of an empty Music window before removal could be released. That detector was an Accessibility experiment that has no qualified method and would require further maintainer sessions. It is withdrawn. The boundary that replaces it consists of measures that iLibrary can verify itself: a verified and disconnected backup with a passing restoration test, a verified evacuation of every file before any registration is removed, removal limited to the recorded persistent IDs after the title, album, and artist of each track are compared with the record, a stop on any unexpected registration, and a final whole-library read reporting zero tracks.

iLibrary reports what it measured. A count of zero is reported as Music reporting no tracks, not as an empty window; the expected Recently Added order is reported as the order of the exposed addition dates, not as an observation of the display. Libraries with iCloud Music Library or cloud statuses other than `unknown` remain excluded at preparation, and iLibrary does not claim to prevent cloud matching.

Agents never run `rebuild` against the maintainer's library. Its Music-facing behavior is verified with substitute libraries in automated tests, and the AppleScript forms it uses are those measured in the separate-user qualifications. Behavior on other macOS or Music versions remains unmeasured and is stated as such in the documentation.

## Milestones

The repository consolidation precedes product work and is not a release. Completed in October 2026, it replaced the historical plans, reports, procedures, probes, and validation scripts with this roadmap and a small set of canonical documents and removed the qualification-only executables `GUIProbeMac`, `M11Probe`, and `ReferenceProbe`, after consolidating their essential findings. Removing the merged branches and enabling automatic deletion of merged head branches remain to be completed.

Version 0.3.0 completes the workflow: the four rebuilding stages, journal reporting in `rebuild status`, separated addition in ordinary `add`, and updated command reference and recovery guidance. Linux and macOS CI passed, and an independent review of the removal and evacuation paths and an automated review found defects that were corrected before integration.

Version 1.0.0 follows a final engineering pass over all production code: removal of duplicated and dead code and of unnecessary comments, measured performance changes where they matter, comparison of command behavior before and after, a final documentation and distribution review, and publication through the established channels. Releases keep the title defined in [Release Titles](distribution.md#release-titles).

## Verification and Limits

Cloud sessions build and test the Foundation-only targets and the command logic on Linux with Swift 6.4. Every change reaches `main` through a pull request whose macOS and Linux CI jobs pass. macOS CI compiles and tests the Music adapters against substitute libraries; it cannot exercise the real Music application or its window.

Behavior that only the real Music application can show is classified as measured only when it was measured in the earlier separate-user qualifications on macOS 27.0.1 with Music 1.7. Anything else is stated as inferred or unknown. Simulated results are never presented as Music observations.

Publication to npm and PyPI runs through the existing workflow and its protected environments, which require the maintainer's approval on GitHub. That approval is a platform control and the only maintainer action that a release requires.

## Repository Maintenance

Development uses short-lived branches merged through pull requests. GitHub deletes merged head branches automatically, and a private weekly maintenance task removes any remaining branch whose commits are already contained in `main`; neither deletes a branch with unmerged commits, rewrites `main`, or touches release tags. Permanent public files are limited to those needed to understand, build, test, install, maintain, and use the product.

Release tags `v0.1.0` and `v0.2.0`, their GitHub releases, their assets, and the published packages are preserved unchanged. Rewriting published history is considered only if a validated migration preserves those publications; an investigation of that question accompanies the consolidation.
