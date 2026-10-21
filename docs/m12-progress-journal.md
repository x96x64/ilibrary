# M12 Progress Journal

## Status

This document describes the portable foundation of M12 (staged rebuilding, target version 0.3.0). It is in local development and unqualified. It is not released, not reviewed in a pull request, and not approved for live use. The maintainer approved, as the design baseline of this phase, an immutable prepared record with a separately versioned progress journal, explicit second invocations for human confirmations, whole-library scope for the first qualification, public macOS adapters isolated from portable code, reuse of the album-addition mechanics without changing ordinary `add`, the unchanged `ilibrary-catalog-1` schema, and the clarification of the M10 wording in `AGENTS.md`. Automatic detection of empty Songs and Recently Added views is not approved and not designed.

The phase adds only Foundation-only code in `RebuildCore` and its tests. Nothing in it removes a registration, quits Music, moves or edits a file, or adds an album. `rebuild stage`, `rebuild clear`, `rebuild apply`, and `rebuild add` remain reserved and exit with status 2; `rebuild prepare`, `rebuild status`, ordinary `add`, and ordinary `apply` are unchanged.

## Record and Journal

`rebuild prepare` writes `rebuild-record.json` (`ilibrary-rebuild-record-1`) once, through `link(2)`, and it is never rewritten. Version 0.2.0 records load unchanged; a record whose stage this version does not know is refused with a diagnostic that names the stage.

Progress is recorded in `rebuild-journal.jsonl` (`ilibrary-rebuild-journal-1`) beside the record. Each line is one canonical JSON entry (sorted keys, compact) terminated by a newline, with these fields:

| Field | Meaning |
| --- | --- |
| `format` | `ilibrary-rebuild-journal-1` |
| `sequence` | 0 for the header, then consecutive |
| `previous` | For the header, the SHA-256 of the exact record file bytes; otherwise the checksum of the previous entry |
| `kind` and `body` | The entry kind and its fields |
| `recordedAt` | UTC time, informational only |
| `checksum` | SHA-256 of the canonical entry with an empty checksum |

The header binds the record's checksum and file digest and declares the scope `whole-library`, the only accepted scope; a valid record already maps every registration. After the header, entries are `stageBegan`, `intent`, `returned`, `verified`, `stopped`, and `stageCompleted`. An unknown format or kind is refused by name; a line that is not canonical is refused as malformed.

## Stages and Operations

The stages are, in order, `evacuation`, `clearing`, `application`, `addition`, and `display`. Each operation belongs to one stage and targets only what the record plans: `evacuateFile` an evacuation source, `removeRegistration` a mapped persistent ID, `applyFile` a staging path, `addAlbum` the next album of the addition list, and `confirmDisplay` the views before and after relaunch. `confirmLibraryEmpty`, `establishGUIEmptiness`, and `terminateMusic` complete the clearing stage.

An operation is open from its `intent` until its `verified` entry, and only one operation may be open. A `returned` entry records that the external call came back; it never completes the operation. A `verified` entry requires a successful return and an observation that matches the plan: the staged file's size, digest, and dates; the exact remaining registrations after a removal; an empty library; Music not running during application; new persistent IDs disjoint from earlier ones with later addition times; and the expected display list. A failed return leaves the operation open, and no later progress is accepted; resolving it belongs to M13. A verified target cannot be repeated, and a stage completes only when all of its targets are verified.

No method for `establishGUIEmptiness` is qualified. The accepted set is empty, so that operation, `terminateMusic`, and the completion of the clearing stage are refused. A manual confirmation is deliberately not accepted as a substitute; that would change the M12 gate and requires the maintainer's decision.

## Writing

The journal is created with `O_CREAT | O_EXCL | O_NOFOLLOW` and mode 0600, synchronized with its directory, and read back. An append opens the file without following a symbolic link; requires a regular file with one link, owned by the effective user, without group or other write permission; takes an exclusive non-blocking `flock`; rereads and replays the whole journal; requires the caller's expected head (compare-and-append); validates the new entry with the same rules as the replay; writes one line; synchronizes; and requires the file to equal the previous bytes plus that line. A failure after a write may have started is reported as uncertain, is never reported as success, and is never retried.

These measures do not exceed what the system provides. `flock` is advisory and does not stop a writer that ignores it. Durability depends on the filesystem honouring `fsync` and `F_FULLFSYNC`. A power loss can leave a torn final entry, which the reader refuses and which is never truncated or repaired automatically.

## Detection Limits

The checksums and the chain detect accidental corruption, a torn final entry, gaps, reordering, a broken chain, and a journal bound to another record. They do not authenticate the journal: anyone who can edit the files can recompute them. A chain also cannot detect the removal of a valid suffix or the substitution of an older valid journal, because no independent trusted checkpoint records the head.

`ProgressJournal.reconcile` therefore compares the replayed progress with an observation of the source and staging files, the registrations, and the Music process, and reports every disagreement as a reason to refuse and reconcile. It detects a rolled-back or truncated journal only where the rolled-back operations changed observable state; it cannot detect an intent without effect, a stop, or a stage boundary. No adapter produces the observation yet. Whether a durable independent checkpoint is required before destructive stages is an open design decision.

## Boundaries and Prerequisites

M12 is to provide a qualified successful path that stops safely at every boundary. Automatic recovery within a stage, fault injection, and storage-disconnection handling belong to M13. Before any registration removal becomes eligible, the following remain outstanding: macOS adapters and command wiring, each separately authorized; a decision on GUI emptiness, preceded by a non-destructive Accessibility feasibility procedure performed by the maintainer in the separate test user; and a first maintainer-run qualification that begins with a non-destructive `rebuild prepare` phase observing the corrected disconnection and recovery-record paths on the backup medium.
