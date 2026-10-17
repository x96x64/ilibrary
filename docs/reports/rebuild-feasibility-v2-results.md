# Version 2 Rebuilding Feasibility Results

## Evidence and Scope

The maintainer supplied the combined version 2 report on October 17, 2026. The small case identifies source commit `9fe4a53f8ef5aa78cb6245f48360ad5044cf780e`, macOS 27.0.1, and a start time of 04:39 UTC (13:39 Japan Standard Time). It contains three synthetic albums and six tracks. The scale case is explicitly `NOT RUN`.

A byte-identical copy of the supplied report is retained under ignored `reference-private/`; its SHA-256 is `1539b1454c4ca1cf6ee9c3d927554163463704010eac8d29106f6f1b3ee734b1`. This evaluation reads that report and the probe's source. The test user's saved registration snapshots are not readable from the current user, so their timestamp values were not inspected. No Music query or personal-library operation occurred. Recorded successes describe the test run, not a fresh inspection of its present state.

## Recorded Results and Gate Assessment

| Condition | Small Case | Evidence Classification |
| --- | --- | --- |
| Exact inventory of generated tracks | Passed: six exact locations and no retrieval errors with explicit `get` | Measured, supplied report |
| Simulated backup restoration and detachment | Passed | Measured, supplied report; same physical storage only |
| Evacuation without byte or file-date changes | Passed for all six files | Measured, supplied report |
| Removal limited to inventoried registrations, with evacuated files unchanged | Passed | Measured, supplied report |
| Empty library and GUI before termination | Passed, including the maintainer's `EMPTY` response | Measured, report and human observation; automatic GUI detection is not implemented |
| Music termination and catalog application while closed | Passed | Measured, supplied report |
| Album-by-album readdition, one registration per file, metadata and release-order verification | Passed | Measured, supplied report; addition order is separate from GUI display order |
| Identical addition timestamps at exposed precision | Unverified: calculation raised `ValueError` | Measured stop; no timestamp count or span was produced |
| Intended Recently Added display order | Unverified: prompt not reached | Inferred from the stopping point and control flow |
| Unchanged registration state on repeated addition | Unverified: not reached | Inferred from control flow |
| Backup unchanged at the final checkpoint | Unverified: final hash check not reached | Earlier backup checks passed; no final preservation conclusion |

The scale case establishes none of these live conditions because it was not run. The small case is an incomplete measurement, not a measured failure of timestamp equality. M10 has not passed; M11 and the product rebuilding implementation remain gated. Independent physical backup qualification and automatic GUI detection also remain outside this evidence.

## Location Retrieval and Timestamp Failure

The initial, evacuated, and final inventories each report six exact locations with explicit `get`. The legacy retrieval form reports six read errors at every checkpoint. This directly establishes a difference between the two forms in this run. It supports the earlier correction, but does not recover the missing raw response from the original version 1 runs.

The final successful line precedes `date_result(final)`. That function applies Python `int` directly to the text returned by AppleScript. A local reproduction using fixed synthetic integers, without addressing any application, returned `8.4539124E+8` for `845391240` and `8.45391241E+8` for `845391241`; the old parser raised `ValueError` for both (measured). Existing tests had used smaller plain-decimal values and missed this behavior.

Exponent notation is therefore a reproduced defect and the leading explanation for the live stop (inferred). The supplied report contains neither the original numeric strings nor the detailed exception, so the exact live input and actual timestamp equality remain unknown. The error does not establish a Music failure or lost files.

## Correction and Local Verification

Commit `a608017` changes the parser to accept finite, integral decimal and exponent representations within its signed 32-bit range, using `Decimal` rather than floating-point rounding. Fractional seconds, invalid values, and out-of-range values are refused. The exact-equality gate is unchanged.

All thirty-one probe tests pass (measured), including a one-second difference in exponent notation, equal values with different representations, and refusal without rounding. The corrected parser also preserved the one-second difference in the actual local AppleScript reproduction. The documented read-only supplement also passed four synthetic scenarios: equal timestamps, a one-second difference, invalid values, and a missing snapshot, with no external calls, private-field output, or file changes. No live Music run, Swift product change, CI run, push, or publication occurred. The previously transferred version 2 archive is unchanged; this local correction does not repair or complete an existing run retroactively.

## Next Action and Stop Boundary

Preserve the small library, its six readded tracks, the original bundle, the backup image, and all saved records. Do not rerun the stopped case or start scale yet. The next step is the [read-only saved-date supplement](../rebuild-feasibility-date-check.md), executed by the maintainer in the existing test user. It extracts only numeric timestamps from the saved final snapshot, without querying Music or changing files. This can establish the small case's timestamp result without repeating evacuation or removal.

If those saved timestamps differ, the current exact-equality condition is not satisfied for this run, and further rebuilding work stops for a maintainer decision. If they agree, the missing GUI-order, repeatability, final-preservation, and scale gates still require separate evidence. A later GUI observation must be identified as later evidence, not inserted into the original run. No outcome silently relaxes the approved conditions.
