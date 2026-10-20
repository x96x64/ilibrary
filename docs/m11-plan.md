# Plan for M11: Backup, Inventory, and Recovery Records

## Status and Authorization

This document is the plan for milestone M11 (target version 0.2.0) of the [Plan for the Stable Release](stable-release-plan.md). Under Decision 40 (October 20, 2026), the maintainer accepted M10 as passed and authorized M11 planning. Under Decision 41 (October 20, 2026), the maintainer approved this plan, as proposed in commit `235bd79`, with the recommended answers to Decisions A to G and the safeguards recorded in [Approved Decisions and Safeguards](#approved-decisions-and-safeguards). Implementation begins on a new milestone branch only after the M10 branch has been integrated into `main`; opening the M10 pull request does not authorize merging it. Live Music qualification, operations on the maintainer's physical backup device, publication of 0.2.0, tags, and registry releases require separate approval.

Under Decision 45 (October 20, 2026), the maintainer accepted M11 as passed on the version 2 qualification recorded in [M11 Qualification Results, Version 2](reports/m11-qualification-v2-results.md), within the evidence limits recorded there. The conditional change under Decision F has not been implemented and requires separate authorization.

The evidence on which this plan relies is classified as in the rest of the repository. Statements about the existing source are established by a read-only survey of the M10 branch at `ebea671`. Statements about Music, filesystems, and storage devices that have not been measured are marked as inferred or unknown.

## Scope

The stable-release plan assigns M11 the following scope and gate.

| Scope | Completion Gate | Mac Requirement |
| --- | --- | --- |
| Independent backup verification, complete inventory, evacuation plans, strict catalog export, and versioned recovery records | Restore bytes, paths, and required dates from separate physical media; verify and disconnect the backup; reject incomplete inventories, overlap, unsupported values, insufficient capacity, and unsafe plans before mutation | Portable logic on Linux; dates, separate media, and restoration on macOS |

M11 prepares and verifies; it does not rebuild. It adds no operation that removes Music registrations, quits Music, edits files for a rebuild, evacuates files, or adds albums. Those operations belong to M12 (staged rebuilding) and M13 (interruption and recovery). The only Music access in M11 is reading registrations. Ordinary `add` keeps its duplicate refusal and never removes registrations.

## Proposed Interface

The stable-release plan reserves `rebuild prepare`, `rebuild stage`, `rebuild clear`, `rebuild apply`, `rebuild add`, and `rebuild status`. M11 implements only the read-only and preparatory parts, and the other verbs continue to report that they are not implemented.

```
ilibrary export PATH... -o CATALOG.json --strict [--artwork DIR] [--dry-run]
ilibrary rebuild prepare CATALOG.json PATH... --workspace DIR --backup DIR --restore-test DIR --staging DIR
                         [--order release|artist|artist-desc|artist-release] [--dry-run]
ilibrary rebuild status --workspace DIR
```

`export --strict` refuses, instead of warning, every condition that makes an export an incomplete inventory: a file dropped for a missing album tag or track number, a repeated disc and track pair, a gap that would be renumbered, and a release date that is present but year-only, partial, or unparseable. A missing release date remains permitted, because the plan retains the placement of undated albums. No month or day is invented, and no gap is closed silently. The non-strict export is unchanged.

`rebuild prepare` performs no mutation of source files, the backup, or Music. It writes only a new recovery record into the workspace and, after the preview, the restoration-test copy. It runs these steps in order and stops at the first failure:

1. Validate the catalog and the selected files with the strict rules, and build a file inventory.
2. Read the whole Music library and classify every registration.
3. Validate the plan: overlap, capacity, unsupported values, and synchronization state.
4. Verify the backup against the inventory.
5. Restore the backup into the restoration-test directory and verify the result.
6. Ask the user to disconnect the backup, and confirm that it is no longer mounted.
7. Record the addition list, the expected display list, the evacuation plan, and the verification results.

`--dry-run` performs steps 1 to 4 and prints the complete plan, including the evacuation plan and the capacity accounting. `rebuild status` reads a recovery record and reports the completed stages, the recorded verification, and the next required action. It accesses neither Music nor the backup.

## Workstreams

### Portable Integrity and File Inventory

A new Foundation-only target, provisionally `RebuildCore`, holds the inventory model, plan validation, and the recovery record, so that they build and test on Linux. Foundation provides no SHA-256, CryptoKit is unavailable on Linux, and AGENTS.md forbids new package dependencies without a decision. A streaming SHA-256 is therefore required (Decision A).

The file inventory records, for every selected file, the normalized relative path, the size, the SHA-256, the modification date with nanoseconds, and the creation date on macOS. It refuses symbolic links in the file or its ancestors, non-regular files, paths that collide after Unicode normalization or case folding, and hard links shared between the source and the backup. The M10 probe compared exactly this state; the product reimplements the comparison in Swift rather than reusing the probe.

### Strict Export

The refusal logic belongs in `ExportCommand.draft`, where files are dropped and numbers renumbered, because `Catalog.validate` sees only the normalized catalog. The strict check also makes a present but unparseable date visible: the current export silently treats such dates as absent.

### Whole-Library Music Inventory

`MusicApp.allTracks` reads 16 properties of every track as separate Apple Events. In the M10 qualification, the probe's bulk snapshot of 300 tracks took 0.482 s, against 40.092 s for a per-track read of 8 properties (measured). A new bulk reader in `LibraryMac` reads, in a fixed number of Apple Events, every field that the existing per-track reader `describeTracks` returns: persistent ID, name, album, artist, album artist, composer, genre, year, track number, disc number, location, cloud status, comment, track count, disc count, and compilation. It also reads date added. The field set is therefore a superset of what `check --library` uses, which resolves the difference noted in Decision F. A first-and-last ID consistency check guards it, and stub tests and a live equivalence check against the per-track reader establish that it returns the same fields. It is used by `rebuild prepare`. Changing `check --library` to use it is a separate decision (Decision F).

Each registration is classified as selected and supported, or as one of the following: unselected, a non-file or cloud-only track, a missing or unreadable location, a location outside the selection, a duplicate location, protected audio, or an ambiguous cloud status. Any classification other than selected and supported prevents preparation unless the plan defines how the registration is left untouched. Which cloud statuses Music reports for local-only files under the qualified conditions is only partly measured; the procedure requires iCloud Music Library to be off and records the observed statuses (unknown until measured).

### Plan Validation and Capacity

The plan rejects overlap among the source tree, the Music media folder, the backup, the restoration-test directory, the staging directory, and the workspace. It refuses symbolic-link ancestors and paths that are equal after normalization. Capacity accounting uses the plain available capacity, as the existing commands do, separately for each volume: the restoration test needs the full inventory size on its volume, and a cross-volume evacuation needs a full copy while the source is retained. Unknown capacity is a refusal, matching `add`. Any change to the catalog, the selection, the library, or the backup after preparation invalidates the record and requires a new `rebuild prepare`.

### Backup Verification, Restoration, and Disconnection

The backup is a directory tree that mirrors the selected relative paths. iLibrary never writes to it (Decision B). Verification requires every inventoried file to exist in the backup with equal bytes, size, and dates, under the date resolution of the backup filesystem (Decision E). The restoration test copies the backup into the restoration-test directory and verifies bytes, paths, and dates against the inventory again (Decision D). The backup must then be disconnected: the command asks the user to eject it, and it records the backup as verified and disconnected only when the volume is no longer mounted.

Physical independence cannot be established from the existing volume identifier, which distinguishes volumes and not devices. A partition of the source drive or a disk image would pass that check. The proposal therefore uses DiskArbitration in `LibraryMac` to refuse a backup on the same whole disk as any source, the media folder, or the restoration-test directory, and to refuse disk images and network volumes. It then records the user's explicit statement that the medium is separate (Decision C). Whether these signals are reliable on the maintainer's hardware is unknown until measured.

### Versioned Recovery Record

The recovery record has its own format identifier, `ilibrary-rebuild-record-1`, distinct from the public catalog format `ilibrary-catalog-1` and from the add journal. It is stored only in the workspace, outside the staging directory, the media folder, and the backup. It is written atomically with synchronization of the file and its directory. It contains the file inventory, the registration inventory, the addition list, the expected display list, the evacuation plan, the backup and restoration results, and the stage state. Only the `prepared` state is reachable in M11, and later states are reserved for M12 and M13. Like the add journal, it is validated on load as user-editable input before it can authorize anything. It contains machine-specific paths and persistent IDs, so it is never added to a catalog or committed; the documentation states that it is private.

### Command Group and Documentation

The command parser has no second-level dispatch; `rebuild` needs its own sub-verb dispatch and help, so that `ilibrary help rebuild` and `ilibrary rebuild prepare --help` work as for other commands. The README, the command reference, the operations guide, and the changelog describe the implemented subset as implemented and the remaining verbs as planned.

## Verification

Portable logic is tested with synthetic inputs on Linux and macOS in CI: SHA-256 against published test vectors, and on macOS also against CryptoKit; inventory edge cases; strict export refusals; plan validation for every overlap and capacity case; and recovery-record round trips, version checks, and tamper refusal. macOS tests cover creation-date reading, refusal of disk images, and DiskArbitration classification, using images that the tests create and attach.

The bulk Music reader is tested with stubs. Its live equivalence, the backup on separate physical media, the disconnection check, and the restoration of dates require a maintainer-operated qualification. That qualification uses a synthetic library in the separate test user and a removable drive the maintainer provides. As in M10, a procedure and bundle are prepared and the work stops before the maintainer's operations.

| Gate Condition | Planned Evidence |
| --- | --- |
| Restore bytes, paths, and required dates from separate physical media | Restoration test from the removable drive in the maintainer-operated qualification, with byte, path, and date comparison |
| Verify and disconnect the backup | Backup verification followed by a confirmed unmount, recorded in the recovery record |
| Reject incomplete inventories | Strict export and inventory refusal tests |
| Reject overlap | Plan-validation tests for every pair of locations |
| Reject unsupported values | Strict date and numbering refusals; registration classification tests |
| Reject insufficient capacity | Per-volume capacity tests, including unknown capacity |
| Reject unsafe plans before mutation | Tests that each refusal occurs before any write, and that a changed input invalidates the record |

## Approved Decisions and Safeguards

The maintainer approved the recommended answer to each decision below under Decision 41, subject to the safeguards that follow each paragraph. The safeguards are requirements of M11; none weakens an existing safety, evidence, or publication requirement.

Decision A concerns the SHA-256 implementation. A hand-written, streaming SHA-256 in the Foundation-only target, verified against the published test vectors and against CryptoKit on macOS, keeps the no-dependency rule. Adding `swift-crypto` would trade a small amount of audited code for a new package dependency. The recommendation is the hand-written implementation.

Safeguards for Decision A: the implementation streams with bounded memory and is verified against the published test vectors, against CryptoKit on macOS, across different chunk boundaries, for empty input and large files, and for read errors. Avoiding a dependency does not justify any loss of correctness or unbounded memory use.

Decision B concerns who creates the backup. In verification only, the user creates the backup, for example by a Finder copy to the removable drive, and iLibrary verifies it and never writes to it. The alternative is a command that creates the backup itself. The recommendation is verification only for 0.2.0, which keeps iLibrary from writing to the medium whose independence it must confirm.

Safeguard for Decision B: the maintainer creates the backup, and no iLibrary operation modifies its contents.

Decision C concerns how physical independence is established. Automatic refusal of the same whole disk, disk images, and network volumes, combined with a recorded explicit statement by the user, is recommended over the statement alone. Automatic signals that later prove unreliable are reported as limitations rather than relied upon.

Safeguard for Decision C: physical independence requires both the available device information and the maintainer's explicit confirmation. Unknown or unreliable device identity results in refusal, never in an assertion of independence.

Decision D concerns the extent of the restoration test. A full restoration into a user-selected directory, which is kept after verification and never deleted automatically, satisfies the gate as written. A sampled restoration needs less capacity but restores only part of the bytes and dates. The recommendation is a full restoration.

Safeguard for Decision D: the complete selected inventory is restored into a separate user-selected directory, its bytes, paths, and required dates are verified, and the restored files are kept until the maintainer removes them explicitly.

Decision E concerns the backup filesystem. Supporting only APFS and HFS+ backup volumes in 0.2.0, which store creation dates, is recommended. FAT and exFAT have coarse or missing creation dates and time-zone ambiguity, so they would require a weaker comparison. The exact date tolerance is set from the filesystem's resolution and recorded with each verification.

Safeguard for Decision E: before any verification result is accepted, the timestamp precision and tolerances of APFS and HFS+ are defined, documented, and tested. The date-preservation requirements are not weakened to make a comparison pass.

Decision F concerns `check --library`. A separate read-only investigation found that it sends one Apple Event plus 16 per track over the whole library, and proposed a bulk read (inferred from source; its live cost is unmeasured). Including that change in M11 reuses the new bulk reader but changes a published command's implementation. The recommendation is to include it as a separately reviewed commit with an equivalence test, without changing the command's output.

Safeguards for Decision F: the change is conditional. It preserves every existing diagnostic field, output behavior, error condition, and supported track classification of `check --library`. Tests demonstrate field-level and diagnostic equivalence, including missing locations, mixed audio formats, duplicate records, cloud statuses, and unavailable properties. The optimization is a separately reviewable commit. Live equivalence is not claimed before the maintainer's separate-user verification.

Decision G concerns integration. The M10 branch, `codex/m10-rebuild-feasibility`, was local and unpushed when this plan was proposed. The recommendation is to approve pushing it and opening a pull request to `main` after the usual preview and summary, and then to begin M11 on a new branch from `main`.

Safeguards for Decision G: before the push, the actual changes, principal summaries, test results, and the complete unpublished commit range are presented, and the range is checked for private information and unrelated changes. Under Decision 42, these materials are presented in English only. There is no force push or history rewrite. Opening the pull request does not authorize merging it; the complete diff, the required CI results, and the merge conditions are confirmed before integration authorization is requested. M11 implementation does not share a branch with the unpublished M10 history.

## Recommended Models and Effort

Bounded implementation and synthetic verification are delegated to Claude Sonnet 5.5 at medium effort; architecture, safety assessment, acceptance decisions, and final review remain with the coordinating agent. The roadmap table recommends Claude Opus 5.5 with high in Claude Code and GPT-6-Astra with high in Codex for M11. M11 adds no destructive Music operation, so the xhigh effort used for M10 and planned for M12 and M13 is not required. Do not use ultra.
