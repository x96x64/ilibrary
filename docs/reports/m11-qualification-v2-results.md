# M11 Qualification Results, Version 2

## Purpose and Status

This report assesses the maintainer-operated run of [M11 Backup and Inventory Qualification, Version 2](../m11-qualification-v2.md), prepared as recorded in [M11 Date Correction and Qualification Version 2 Preparation](m11-date-correction-and-qualification-v2-preparation.md). Every live step from the bundle check to the full preparation, including the deliberate negative check, completed with its expected result. The final read-only `rebuild status` step of Step 11 is recorded as `NOT RUN`. M11 has not been accepted: acceptance is the maintainer's decision, and the recovery record's reported content has not been shown by the command intended for that purpose. Findings are classified as measured, inferred, or unknown; statements about the supplied report are measurements of its contents, not of operations performed during this assessment.

## Report Identity and Preservation

The report `/Users/Shared/ilibrary-m11-qualification-v2-report.txt`, written by the test user on October 20, 2026, is 26,936 bytes and 421 lines of ASCII text, with SHA-256 `92e3a4da6e84e581d55fbcaff37382380748b05e8d4f6fb3d9d574fa19dd3a28`. It is preserved byte for byte under the ignored `reference-private/m11-qualification-v2-results-2026-10-20/`, and the copy was compared with the original (measured). The original in `/Users/Shared` is retained.

The report names source commit `1de954cb96abd20f66fe58ae46c297b338615dee` and manifest format `ilibrary-m11-qualification-2`, which match the prepared bundle. The archive checksum check passed at collection, and the bundle check passed for all 18 files before the run and for the 6 remaining files at collection, with the 12 staging files absent as expected after `ilibrary add` (measured). No file under `Sources` and no `Package.swift` change exists between that commit and the commit at which this assessment was made, so the source reading below applies to the executables that ran (measured). The report records macOS 27.0.1 and Music 1.7.

The collection script replaces the test user's home directory with `~`, every volume name with `BACKUP`, and every persistent identifier with `<id>`. The redaction also removed the volume UUID from the line `Eject the backup volume now`, which the procedure anticipated as possible over-redaction. The report contains no personal path, Apple Account detail, or identifier, and this assessment quotes nothing beyond counts, durations, and command outcomes.

## Steps Completed

| Procedure step | Recorded evidence | Classification |
| --- | --- | --- |
| 1, bundle and archive | Archive checksum `PASS`; bundle check `PASS (18 files verified)` | Measured |
| 2, synthetic dates | Preview and change each matched 12 files with 0 refused; `Dated and verified: 15 paths`; validation matched 12 files | Measured |
| 3, new library | Not logged by design; `doctor` names the media folder `~/Music/M11-qualification-v2/Media.localized` | Measured indirectly |
| 4, environment | `doctor`: iLibrary 0.1.0, macOS 27.0.1, Music 1.7, Automation permitted, 35.5 GB free, `No problems found.` | Measured |
| 5, addition | Release order Album 02 (1998-11-02), Album 01 (2001-03-15), Album 03 (2005-07-21); `Added and confirmed: 3 album(s)`, each with 4 tracks confirmed | Measured |
| 6, reader probe | Probe report format `ilibrary-m11-readers-report-2` with the comparison, durations, cloud statuses, and date-added ages; no error | Measured |
| 6, strict export and library validation | `Exported 3 albums and 12 tracks from 12 files`; validation matched 12 files in the media folder | Measured |
| 7, Finder backup | Method recorded as a Finder copy of the media `Music` folder; drive format recorded as `Mac OS Extended (Case-sensitive, Journaled)` | Maintainer-reported |
| 9, preparation preview | Steps 1 to 4 passed; `Backup verification: 12 files verified for bytes, sizes, and dates`; `Dry run: steps 1 to 4 passed. Nothing was changed.` | Measured |
| 10, negative check | Refused at step 4 because the internal copy shares physical disk `disk0` with all five other locations; `nothing was changed`; exit status 1 | Measured |
| 11, full preparation | Steps 1 to 7 passed; `Prepared: stage prepared, 12 files, 3 albums` | Measured |
| 11, `rebuild status` | `NOT RUN` | Not performed |

The report does not record exit statuses except for the negative check; each other completed step ends with the success line that the procedure names. The probe's console log is empty, and its JSON report is complete. Step 8 creates directories and produces no log; its success is implied by the later steps that use those directories (inferred).

## Findings

### Reader Equivalence and Dates Added

The per-track reader and the bulk reader each returned 12 tracks. All 16 compared fields (persistent ID, name, album, artist, album artist, composer, genre, year, track number, disc number, location, cloud status, comment, track count, disc count, and compilation) differed for 0 tracks; the probe reports `perTrackAndBulkIdentical: true`, no duplicate identifiers in either reader, and no fallback of the bulk reader (measured). The snapshot reader returned 12 tracks, all of them file tracks, with an identifier set equal to that of the per-track reader, and every snapshot track has a date added (measured). The live field-level equivalence of the two readers is therefore established for this synthetic library of 12 tracks, on macOS 27.0.1 and Music 1.7; it is not established for larger libraries, other track kinds, or other versions (unknown).

The snapshot's dates added have three distinct values whose ages relative to the probe's clock range from 12 to 14 seconds (measured). Three values match the three album additions, and small positive ages match additions made shortly before the probe (inferred). These are the dates whose conversion stopped the first run; the corrected conversion produced plausible exact-second values on real Music data, which removes the cause of the first stop for this case.

The probe recorded 0.304 seconds for the bulk read, 3.277 seconds for the per-track read, and 0.359 seconds for the snapshot (measured, one observation each). These durations describe 12 tracks and are not a performance qualification.

### Cloud Status Values

Music reported the cloud status `unknown` for all 12 tracks in a new library in the separate test user, which has no Apple Account (measured). `unknown` is one of the two statuses admitted by default by the registration classification (`Sources/RebuildCore/RegistrationClassification.swift`), and Step 2 of `rebuild prepare` passed with 12 registrations mapped one-to-one to the files (measured). This observation does not show that cloud matching is absent: `check --library` already states that an unknown cloud status does not confirm the absence of matching, and the statuses reported under iCloud Music Library or with an Apple Account signed in remain unknown.

### Strict Export and Library Files

The strict export of the media folder's `Music` tree exported 3 albums and 12 tracks with release dates 2001-03-15, 2005-07-21, and 1998-11-02, and the validation of the media folder against the bundle catalog matched all 12 files (measured). No refusal occurred, as expected for complete synthetic albums; the refusal paths are covered by the test suite, not by this run.

### Backup Dates on the External Drive

`rebuild prepare` selected the timestamp policy `hfsPlus` from the filesystem type of the backup volume and verified all 12 backup files for bytes, sizes, and dates in both the preview and the full run (measured). Under that policy (`Sources/RebuildCore/TimestampPolicy.swift`), the modification and creation dates of each backup file must equal the source dates truncated to whole seconds, with no other tolerance. A Finder copy from the APFS media folder to this HFS+ drive therefore preserved both dates within the resolution of HFS+ for these 12 files (measured through the command's verification). The recorded drive format string is identical to the example in the procedure, so whether the maintainer replaced it or the drive is in fact case-sensitive cannot be determined from the report (unknown); the measured filesystem type `hfs` is consistent with the maintainer's description of the drive as HFS+.

### Device Signals and the Internal-Copy Refusal

With `--confirm-separate-device` given, the preview and the full run accepted the external backup, and the plan's separate-location and capacity checks passed (measured). The deliberate internal copy was refused at step 4 because it shared the physical disk `disk0` with the source root, the media folder, the restoration-test directory, the staging directory, and the workspace, and nothing was changed (measured). The device signal therefore distinguished an internal copy from the external drive on this Mac. Whether it distinguishes every arrangement that the plan names, such as a partition of an external source drive, a disk image, or a network volume, was not exercised by this run and rests on the test suite (unknown for live hardware).

### Restoration, Disconnection, and Recovery Record

The full run stated before any write that it would copy 12 files (335,604 bytes) from the backup into `~/m11-v2-restore` and write one recovery record, and that source files, the backup, and Music would not be modified. Step 5 restored and verified 12 files under the `hfsPlus` policy; Step 6 reported that the backup volume was no longer mounted; and Step 7 reported that the recovery record was written and read back (measured). The command writes the record only after the unmount is observed and stores the verification and disconnection times in it, and its read-back requires equality with the written record (`Sources/ilibrary/RebuildPrepare.swift`, `Sources/RebuildCore/RecoveryRecord.swift`); that the record contains the verification and disconnection is therefore inferred from the code and the success lines. The record's content as reported by `rebuild status` was not captured, because that step was not run; the reason is unknown.

The ejection was performed by the maintainer in the Finder. Whether Time Machine was running during the run, and how long the wait lasted, are not recorded (unknown). No line of the report indicates any refusal, any offer to stop a Time Machine backup, any write to the drive by iLibrary, or any edit or removal of a Music registration.

## Gate Assessment

| Gate condition | Evidence | Assessment |
| --- | --- | --- |
| Restore bytes, paths, and required dates from separate physical media | Full restoration of 12 files from the external HFS+ drive, verified for bytes, paths, and modification and creation dates; separate device confirmed by the maintainer and not refused by the device signal | Met for this run (measured) |
| Verify and disconnect the backup | Backup verification in the preview and the full run; unmount observed at Step 6 | Met (measured) |
| Record the verification and disconnection in the recovery record | Record written after the unmount and read back; content not displayed because `rebuild status` was not run | Met by inference; display unmeasured |
| Reject incomplete inventories, overlap, unsupported values, insufficient capacity, and unsafe plans before mutation | Test suite, as recorded in the implementation and correction reports; live refusal of a same-disk backup before any change | Met by the suite; one refusal observed live |
| Live equivalence of the bulk and per-track readers (Decision F prerequisite) | 16 fields of 12 tracks identical; no fallback | Met for this synthetic library (measured) |

The evidence meets every completion-gate condition of the [M11 plan](../m11-plan.md) for this run, except that the recovery record's content was not displayed by `rebuild status`. That display is a planned observation of Step 11 rather than a separate gate, but without it the record's content rests on code inspection. Whether to accept M11 on this evidence, or after a supplementary `rebuild status` observation, is the maintainer's decision.

## Consequences

The defect that stopped the first run does not recur in this run, and the snapshot reader that `rebuild prepare` uses returned exact, plausible dates added (measured). The precondition of the conditional `check --library` change under Decision F, live equivalence of the bulk reader with the per-track reader, is now met for this synthetic library. Decision 41 approved that change as a separately reviewed commit that preserves every diagnostic field, output behavior, error condition, and classification; it has not been started.

The library `M11-qualification-v2`, the bundle folder `~/ilibrary-m11-qualification-v2` with its `results`, the restored files in `~/m11-v2-restore`, the recovery record in `~/m11-v2-workspace`, the internal copy and the negative-check directories, the backup folder `M11-v2-backup` on the external drive, and the report are evidence and are retained. The procedure forbids rerunning `rebuild prepare` in the same workspace. The first run's library, bundle folder, logs, and report also remain preserved.

## Next Step

The next maintainer action is to complete the omitted read-only observation in the test user: run `bin/ilibrary rebuild status --workspace ~/m11-v2-workspace 2>&1 | tee results/status.log` from `~/ilibrary-m11-qualification-v2`, which reads only the recovery record and accesses neither Music nor the backup drive, and then run `sh collect.sh` with a new report name, because the collection script never overwrites the existing report. Alternatively, the maintainer may accept M11 on the present evidence. The `check --library` change under Decision F is the remaining approved M11 implementation item and follows the maintainer's direction. No agent operates the test user, Music, or the backup drive.

## Addendum: Supplementary Status Observation and Acceptance

This addendum records evidence received after the assessment above; the preceding sections are retained unchanged as the record of that assessment.

On October 20, 2026, the maintainer ran the omitted `rebuild status` command in the test user and collected a new report, `/Users/Shared/ilibrary-m11-qualification-v2-status-report.txt`. It is 28,128 bytes and 437 lines of ASCII text, with SHA-256 `9fdb0db5a3bb9fc9b7c8d06232d61408b24eb60ce13b9f09283fab11e4b9187f`, and it is preserved byte for byte beside the first report under the ignored `reference-private/m11-qualification-v2-results-2026-10-20/`; the copy was compared with the original (measured). Its first 420 lines are byte-identical to the assessed report, including the source commit, the manifest format, and the bundle and archive checks, and its only difference is that the `results/status.log` section, previously `NOT RUN`, contains 17 lines of `rebuild status` output (measured). No earlier result changes.

The output names the recovery record in the workspace, format `ilibrary-rebuild-record-1`, created at 2026-10-20T03:14:25Z by iLibrary 0.1.0. It reports the stage `prepared`; 12 files of 335,604 bytes, 12 registrations, and 3 albums; locations equal to those of the preparation run; a backup verification of 12 files at 2026-10-20T03:13:45Z on a filesystem of type `hfs` under the policy `hfsPlus`, with the maintainer's confirmation of a separate device; a confirmed disconnection at 2026-10-20T03:14:25Z; and a restoration verification of 12 files at 2026-10-20T03:13:45Z, with the restoration directory kept (measured). The output ends with the next required action, which the command prints only after the record has passed its validation on load. That validation refuses a record that marks the backup as disconnected without a successful verification and the maintainer's confirmation, or whose backup or restoration verification did not check every inventory file (inferred from `Sources/ilibrary/RebuildCommand.swift` and `Sources/RebuildCore/RecoveryRecord.swift` together with the observed output). The exit status of the command is not recorded.

The two verification times fall in the same second; they are taken from separate clock readings, which is plausible for 12 small files (inferred). The disconnection and the record's creation follow 40 seconds later, consistent with the ejection wait, and precede the collection of the first report at 03:15Z (measured from the recorded times). The recording of the verification and disconnection in the recovery record, previously inferred from the code, is therefore now established by observed output, and the corresponding row of the gate assessment above is met (measured).

The status output also exposed a defect of the collection script: it prints the backup volume's UUID, which the script did not redact. The UUID is a device identifier; it remains only in the ignored preserved reports and is not reproduced in any tracked file. Commit `0be5b4e` corrects the collector so that canonical 8-4-4-4-12 UUIDs in either letter case become `<uuid>`, with 15 collector tests passing, and leaves the existing home, volume-name, and persistent-ID rules unchanged. Applied in memory to the two preserved reports, the corrected redaction removes the single UUID of the supplementary report and changes no other line of either report (measured). The existing reports are evidence and are not regenerated or altered, and the bundled procedure of the frozen version 2 bundle continues to describe the redaction of that bundle.

Under Decision 45 of the [roadmap](../roadmap-to-stable.md#decisions-in-force), the maintainer accepted M11 as passed on this evidence. The acceptance covers this synthetic library, this Mac, macOS 27.0.1, Music 1.7, and this HFS+ drive. It does not extend to personal libraries, other hardware, larger collections, APFS or other backup filesystems, or accounts with an Apple Account or iCloud Music Library. The cloud status `unknown` does not establish the absence of cloud matching; the drive's case sensitivity and the Time Machine state during the run are unknown; and the refusal of partitions, disk images, and network volumes rests on the test suite. The conditional `check --library` change under Decision F has not been implemented, and the reader comparison does not verify it.
