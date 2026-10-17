# Initial Rebuilding Feasibility Results

## Evidence and Scope

On October 17, 2026, the maintainer supplied the small and scale result files from the separate-user M10 probe at commit `8850bc0536c8d70c4a74adebd3f8a68cf519d0e5`. Both identify macOS 27.0.1. The small case began at 03:52 UTC with three albums and six tracks; the scale case began at 03:58 UTC with twenty albums and 300 tracks.

This evaluation reads the supplied result files and their existing failure records, command logs, start markers, and addition journals. Verified copies of that evidence remain under ignored `reference-private/`. It does not query Music, inspect either live test library, or access the personal library. Counts describe the recorded runs, not their current state. No private path, persistent ID, recording, or raw log is included in this report.

## Recorded Results

| Observation | Small | Scale | Classification |
| --- | --- | --- | --- |
| Files matched before initial addition | 6; none unmatched or refused | 300; none unmatched or refused | Measured, recorded command output |
| Initial album additions confirmed | 3 albums; 6 unique destinations and 6 recorded IDs | 20 albums; 300 unique destinations and 300 recorded IDs | Measured, command output and journals with every entry marked `added` |
| Probe outcome | `STOP`; `case gate: NOT SATISFIED` | `STOP`; `case gate: NOT SATISFIED` | Measured, supplied result files |
| Immediate refusal | Music location differs from an expected location | Same refusal | Measured, saved failure records |
| Post-addition inventory checkpoint | Not completed | Not completed | Inferred from the refusal, control flow, and absence of the next checkpoint |

The ordinary `add` command reported confirmation of each album after checking the returned track count, persistent-ID uniqueness, and locations against its destinations. This is evidence for initial addition in these two runs. It does not establish the later removal-and-readdition sequence or equality of addition timestamps.

Both result files contain no `PASS` line. Initial addition success is established by the accompanying command logs and journals, not by interpreting the declared case sizes as successful measurements.

## Gate Assessment

| M10 Condition | Assessment |
| --- | --- |
| Initial synthetic addition to the selected empty library | Initial addition is recorded as successful in both cases; the probe's subsequent location check refused it |
| Complete expected inventory before backup and removal | Not satisfied: the location comparison stopped both runs |
| Restore and detach the simulated backup | Unverified; not reached in the recorded control flow |
| Evacuate files without changing bytes or dates | Unverified; not reached |
| Remove only inventoried registrations while preserving evacuated files | Unverified; the probe did not reach its deletion calls |
| Confirm an empty library and GUI, then terminate Music | Unverified; not reached and no GUI observation was recorded |
| Edit tags while Music remains closed | Unverified; not reached |
| Readd one album at a time and verify every resulting registration | Unverified; initial addition is not readdition |
| Identical addition timestamps at Music's exposed precision | Unverified; no distinct-count or time-span measurement was recorded |
| Intended Recently Added order | Unverified; no maintainer observation was recorded |
| Preserve the verified backup throughout the complete sequence | Unverified; the backup phase was not reached |

Neither case satisfies M10. The recorded stop is an incomplete experiment, not a measured failure of timestamp equality or proof that the requested workflow is impossible. Conversely, the existing preparation tests and successful initial additions do not establish the missing conditions. M11 and product rebuilding implementation remain gated.

## Cause and Uncertainty

The saved refusal originates in `assert_inventory`, where each Music location is compared with an expected path. In these runs it occurs after initial addition and before the first inventory success record. Both addition journals use the planned relative destination structure, and the ordinary command reported successful location confirmation immediately before the probe's separate check.

The probe writes `initial-registration.json` only after that check succeeds. Neither run contains this file, so the actual value that failed the comparison is unavailable in the supplied evidence. The exact mismatch and its cause remain unknown. A difference in path representation, a missing value, or an intervening change cannot be distinguished from these records. There is no basis to relax the path guard, blame Music, or claim that files were lost.

The recorded control flow places the stop before backup creation, evacuation, and registration removal. The supplied directories contain no corresponding later checkpoint or backup artifact. This supports the inference that this probe invocation performed none of those later operations; it is not an independent inspection of current file or library state.

## Next Action and Stop Boundary

Preserve both test libraries, generated files, and result directories. Do not rerun either stopped case, delete registrations, move files, or use the personal library to investigate. The next diagnostic should read the saved plan and the actual locations under the same guarded separate test user, record comparison details privately before refusing a mismatch, and return only sanitized counts and classifications. It must make no library or music-file changes.

Only after the mismatch is understood should the probe be corrected and its synthetic guard tests extended. A fresh live run then requires specific separate-user instructions; these records do not authorize continuing deletion from either interrupted state. Retain the exact timestamp and GUI-order gates without alteration. Independent physical backup qualification and automatic GUI detection also remain outside the evidence from these runs.

This checkpoint changes documentation only. Existing preparation tests were not rerun, and no new live test, CI run, push, or publication occurred.
