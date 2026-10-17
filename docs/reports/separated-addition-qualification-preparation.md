# Separated Addition Qualification Preparation

## Purpose and Authorization

Decision 36 adopts separated album addition as the M10 candidate method and authorizes preparing the remaining qualification cases with it, stopping before the maintainer's separate-user operations. This report records the probe, its local verification, and the prepared handoff. No Music query, separate-user operation, personal-library access, product change, push of the M10 branch, or publication was performed.

## Design

The new probe `scripts/validation/qualification_probe.py` imports the frozen timing, display, and rebuilding probes without changing them. Its four cases reuse the display-v3 plans and differ only in their new library names.

| Case | Albums and Tracks | Library | Addition Order | Expected Display Order |
| --- | --- | --- | --- | --- |
| `scale-release` | 20 albums, 300 tracks | `M10-separated-scale-release` | 1–20 | 20–1 |
| `artist` | 4 albums, 8 tracks | `M10-separated-artist` | 2, 4, 1, 3 | 3, 1, 4, 2 |
| `artist-desc` | 4 albums, 8 tracks | `M10-separated-artist-desc` | 3, 1, 4, 2 | 2, 4, 1, 3 |
| `artist-release` | 4 albums, 8 tracks | `M10-separated-artist-release` | 4, 2, 3, 1 | 1, 3, 2, 4 |

Each case requires a new empty library, refuses any existing registration, and admits only the media scaffolding accepted by timing version 2. It then runs this sequence:

1. Seed addition: the product adds the generated albums in one invocation in the case's order, and the journal must match the saved addition list.
2. Backup: a detached read-only synthetic image is created and its restoration verified.
3. Evacuation: files are moved on the same volume and their bytes and dates compared.
4. Removal: the display probe's guarded routine removes only the inventoried registrations, one persistent ID per call.
5. Empty GUI: the maintainer confirms that Songs and Recently Added are empty.
6. Editing: Music is quit, termination is confirmed, and the edited catalog is applied while Music is closed.
7. Separated readdition, as in timing version 2: one album per `ilibrary add` invocation, a wait of at least two seconds after the previous album is confirmed, and a stop before the next album if its earliest exposed timestamp is not later than every earlier timestamp.
8. Observation: file and library verification, display observation before and after relaunch, repetition of every completed per-album addition, and final checks of the backup and bundle.

A cross-album tie found after readdition also stops the case. Cases run in order, and a `STOP` prevents the remaining cases; `FAIL` and `UNVERIFIED` are completed results. A single report command combines the four cases with the display-v3 and timing version 2 history, refuses to overwrite, and reports `PASS` only when all four cases pass. Shared outputs contain album numbers, counts, timestamps, and states, not personal paths or persistent IDs.

The checks around each wait may take 120 seconds in total, compared with 30 in timing version 2, because reading 300 registrations takes longer than reading 6 (inferred; snapshot duration at that scale is unmeasured). This bound limits the checks; it does not qualify a waiting interval and does not weaken the timestamp gate. The preparation script refuses uncommitted or untracked probe sources, which the earlier preparation scripts did not detect for new files.

## Verification

Measured locally on October 17, 2026, at source commit `bf84ee97a058fe095023e66afbba1480f18b265c`:

- All 116 probe tests passed: 96 existing tests and 20 new ones. The new tests substitute Music, native commands, the backup image, and the monotonic clock. They cover complete artist and scale runs (300 single-call removals and 20 separated readditions), cross-album ties, GUI mismatch, unknown display, an unconfirmed empty GUI, an unexpected registration during removal, a late Music launch, a registration change during the wait, unexpected media entries, existing registrations, other libraries, case order, dry runs, re-execution, reports, and bundle corruption. The bundle-inventory tests also passed.
- Four deliberate faults were each detected by the new tests: an ignored timestamp boundary, an accepted unconfirmed empty GUI, editing without the termination check, and an omitted media check.
- Preparation built the release executable and created 324 synthetic files, eight catalogs, the bundle manifest, and a ZIP whose contents matched the manifest. The product executable is byte-identical to that of timing version 2.
- With Music calls blocked, file-only checks on copies of all four cases passed catalog application with timestamps, native read-only image creation and restoration, same-volume evacuation with byte and date equality, edited-catalog application, file checks, and validation. The bundled scripts and procedure matched the commit, and an unrun report listed all four cases as `NOT RUN`.
- In the ordinary user, `run --case scale-release` stopped at the test-user guard without addressing Music or creating records.
- The ZIP SHA-256 is `49b284482a177130e25340746d00d1c921f1377b51bee71de1fae9f4f2556a2b`. The ZIP and its checksum file were copied to `/Users/Shared/` without overwriting; both copies matched, `shasum -c` passed, and the timing version 2 archive was unchanged.

These checks qualify preparation and file handling. They do not establish Music's behavior at scale, after removal, or in the artist-order cases. They also do not qualify the snapshot duration within the wait bound, automatic GUI emptiness detection, or independent physical backup.

## Handoff and Remaining Gates

The maintainer runs the [Japanese procedure](../rebuild-qualification-validation.md) in the existing separate test user, creating each case's library immediately before that case, and returns `/Users/Shared/ilibrary-m10-qualification-report.txt`. All earlier libraries, bundles, backups, journals, and reports remain preserved and are not rerun. M10 remains incomplete until the returned evidence is assessed against the preservation, sequence, display, and repeat-safety gates. Product `rebuild`, ordinary `add`, personal-library access, and publication remain unchanged and unauthorized.
