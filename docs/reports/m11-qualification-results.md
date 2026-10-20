# M11 Qualification Results, First Run

## Purpose and Status

This report assesses the first maintainer-operated run of [M11 Backup and Inventory Qualification](../m11-qualification.md), prepared as recorded in [M11 Implementation and Qualification Preparation](m11-implementation-and-qualification-preparation.md). The run stopped at Step 6 on a defect of the bulk Music snapshot reader. M11 has not passed. Findings are classified as measured, inferred, or unknown; statements about the supplied report are measurements of its contents, not of operations performed during this assessment.

## Report Identity and Preservation

The maintainer supplied `/Users/Shared/ilibrary-m11-qualification-report.txt` on October 20, 2026. It is 15,420 bytes and 182 lines, with SHA-256 `22334f72bbd66238ab9d4fa7bf56af8f7e4dc7bfdacdd573319eef2edb81f36a`. It is preserved byte for byte under the ignored `reference-private/m11-qualification-results-2026-10-20/`, and the copy was compared with the original (measured). The original in `/Users/Shared` is retained.

The report names source commit `3b06a078cf8f0fda6774abec2926286065f3e4b7` and manifest format `ilibrary-m11-qualification-1`, which match the prepared bundle. No file under `Sources` changed between that commit and the commit at which this assessment was made, so the source reading below applies to the executables that ran (measured). The report records macOS 27.0.1 and Music 1.7.

The maintainer subsequently stated that Step 7 was not reached: no backup folder was created, no Finder copy was made, and no qualification operation was performed on the external drive (maintainer-reported). The test library `M11-qualification`, the extracted bundle, its logs, and the report are preserved unchanged at the maintainer's instruction.

## Steps Completed

| Procedure step | Recorded evidence | Classification |
| --- | --- | --- |
| 1, bundle and archive | Archive checksum `PASS`; bundle check `PASS (18 files verified)` before the run; `PASS (6 files verified; 12 staging files absent, as expected after ilibrary add)` at collection | Measured |
| 2, synthetic dates | Preview and change each matched 12 files with 0 refused; `Dated and verified: 15 paths`; validation matched 12 files | Measured |
| 3, new library | Not logged by design; `doctor` names the media folder `~/Music/M11-qualification/Media.localized` | Measured indirectly |
| 4, environment | `doctor`: iLibrary 0.1.0, macOS 27.0.1, Music 1.7, Automation permitted, `No problems found.` | Measured |
| 5, addition | Preview and addition in release order Album 02 (1998-11-02), Album 01 (2001-03-15), Album 03 (2005-07-21); `Added and confirmed: 3 album(s)`, each with 4 tracks confirmed | Measured |
| 6, reader probe | `M11Probe: the probe stopped on an error`; the probe report contains only the error `Music returned an unexpected result: a date added is not a number`, the versions, and the passed user-name check | Measured |
| 6, strict export and library validation | `NOT RUN` | Not performed |
| 7 to 11 | `NOT RUN` for the backup record, both previews, the negative check, the full preparation, and the status | Not performed |

The report does not record exit statuses; each completed step ends with the success line that the procedure names. Stopping after the probe error was consistent with the procedure's general stop rule.

## Cause of the Stop

The probe reads the Music version and then performs, in sequence and inside one error handler, the per-track read, the bulk read, and the library snapshot (`Sources/M11Probe/main.swift`). The error text occurs only in `MusicApp.parseSnapshot` (`Sources/LibraryMac/MusicBulk.swift`), which converts each date-added offset with `Int(offset)`. Since the version was recorded, the per-track and bulk reads completed without raising an error and the snapshot failed (inferred from the control flow and the unique message). The error discarded the other results, so the report contains no field comparison, fallback flag, durations, or cloud status values (measured).

The snapshot script computes each offset as `(((date added) - base) as integer) as text`, with `base` set to local 2000-01-01 00:00:00. A pure AppleScript computation without Music, run on the maintainer's Mac on October 20, 2026, returned `8.458112E+8` of class `real` for the current date and `1000` for an offset of 1,000 seconds (measured). AppleScript integers are limited to about ±536,870,911, so the offset of any date added after early January 2017 is a real number and its text form is a rounded exponent string. The twelve synthetic tracks were added on the day of the run, so every offset exceeded that range. The exact strings returned by Music were not recorded; this explanation is inferred, but it accounts for the error completely.

The exponent text keeps seven significant digits, a resolution of 100 seconds for present-day dates. A parser that accepted exponent notation, as commit `a608017` did for the M10 Python probe, would therefore not recover exact seconds; the conversion in the script must change (inferred from the measured string). The existing unit tests used only small offsets and did not exercise this range.

## Consequences

`ilibrary rebuild prepare` reads registrations through the same `librarySnapshot()` in its Step 2 (`Sources/ilibrary/MusicLibrary.swift`). It would refuse with "the Music library could not be read" for any library that contains a track added after early January 2017, so the run would have stopped again at procedure Step 9 (inferred from the code). The defect causes a refusal before any write, not a wrong result. The probe wrote only its exclusively created report file, and nothing in the report indicates any edit or removal of a registration or any access to the personal library.

## Gates That Remain Unmeasured

The following remain unknown: the live field-level equivalence of the bulk and per-track readers and the bulk reader's fallback behavior; the cloud status values that Music reports for local files; the strict export and validation of the library files; Finder date preservation on an external HFS+ or APFS drive; the device-independence signals of a real external drive; the refusal of an internal-disk copy in practice; the restoration test; the disconnection wait; and the recovery record and `rebuild status`. The change of `check --library` under Decision F remains deferred until live equivalence is established.

## Next Step

The maintainer authorized the correction of the date conversion with regression tests and the preparation of a replacement bundle and procedure for a new run with a fresh synthetic library, new paths, and a distinct report name. The correction and the preparation are recorded in a subsequent report. The first run's library, bundle folder, logs, and report are not reused, reset, or deleted.
