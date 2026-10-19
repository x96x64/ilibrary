# Display-Order Validation Results

## Evidence and Scope

The maintainer supplied the combined M10 display-order report on October 17, 2026, and stated that the media folder had been set as instructed. The report identifies source commit `3b7e2fe1783cc838aa178147f3e1c7e28f3d72d5`, macOS 27.0.1, and a small-case start time of 05:40:56 UTC (14:40:56 Japan Standard Time). A byte-identical copy is retained under ignored `reference-private/`; its SHA-256 is `86222edaae5558eec324dec91a5ac5c1416515d078eda6c10eb56941b32474d9`.

This assessment reads the supplied report and the corresponding probe source. It does not query Music, inspect a personal library, or access the test user's library files. Earlier reports and the transferred probe remain unchanged. The maintainer's statement is recorded as reported evidence; the settings screen and the value read during the stopped run are not included in the supplied report.

## Recorded Results and Gate Assessment

| Condition | Result | Evidence Classification |
| --- | --- | --- |
| New small-case execution | Stopped during preflight after 5.827 seconds | Measured, supplied report |
| Probe's required media-path comparison | Refused before the legacy-evidence phase | Measured stop; comparison semantics established by source inspection |
| Reuse of saved small registrations and files | Not reached | Inferred from control flow |
| Recently Added order before and after relaunch | Not observed | No observations in the report; both prompts occur after the stop |
| Completed-addition repeat safety and final backup verification | Not reached | Inferred from control flow |
| New scale, artist, artist-desc, and artist-release cases | All four explicitly `NOT RUN` | Measured, supplied report |
| Current display qualification | Incomplete, not a measured display-order failure | No live display evidence was obtained |

The earlier version 2 small-case successes remain historical evidence: six generated tracks completed inventory, simulated backup restoration, evacuation, guarded removal, human-confirmed empty GUI, termination, editing while closed, and ordered readdition with file/library comparison. They are not fresh measurements of the current library. Its saved timestamps still establish two values one second apart. Under Decision 33, that difference alone is acceptable and does not qualify or disqualify the missing display observations.

M10 remains incomplete. M11 and product rebuilding implementation remain gated. Automatic GUI emptiness detection and independent physical backup qualification remain unverified; the present stop adds no evidence for either.

## What the Stop Establishes

The specific refusal occurs when `display_probe.py` compares the result of `media_directory(home)` with its fixed small-case path under `Music/M10-v2-small/Media`. The helper reads `media-folder-url` with `defaults read com.apple.Music`, parses the file URL, rejects symbolic links, and requires an existing directory within the test user's Music directory. The subsequent comparison uses normalized path spelling, not a filesystem-object identity comparison or a reading of the settings screen.

**Inferred from the source and the reported refusal:** the preliminary URL, directory, and containment checks passed, but the resulting path did not compare equal to the probe's expected path. The run stopped before querying Music's version, reading registrations, restoring a backup, or modifying music files or registrations. It did create diagnostic and result records. This establishes the control-flow boundary, not an independent post-run examination of every file.

**Unknown:** the value actually returned by the preference read and why it differed from the expected value. The combined report does not include that value. A difference in representation, a difference between the saved preference and the visible setting, or another discrepancy cannot be distinguished from this report. None is established as the cause. The maintainer's report that the setting was correct must not be replaced with an unsupported conclusion that the wrong folder was selected.

The preparation tests substitute `media_directory` and cover refusal of a supplied unexpected path. They do not demonstrate that this preference read always agrees with Music's settings after a library switch. The diagnostic record captures the command's actual output locally, but the combined report omits the comparison operands. This is a confirmed observability and test-coverage limitation; an exact live root cause has not yet been established. Do not weaken the guard or change the expected folder merely to pass the check.

## Next Action and Preservation

Do not repeat a live case, create another library, change a media-folder setting, clear registrations, or delete existing results. Preserve both bundles, the six existing small tracks, and all backups and records.

The next evidence is the stopped small case's existing `diagnostics.jsonl`, under the new bundle's `reference-private/small-existing/` directory. The fixed source records the successful preference command's output before the refusal. The maintainer can copy only that file into a dedicated shared `reference-private/` directory, without opening Music or running the probe. Confirm byte equality and preserve an existing different destination rather than overwriting it. Raw paths remain private; public findings should report only the comparison outcome and a sanitized explanation.

After inspecting that saved evidence, determine whether a read-only comparison with earlier saved records or a probe correction is necessary. Any correction must preserve exact-target protections, retain the stopped run, and be tested without Music before a replacement handoff. If another separate-user observation is needed, stop before it and provide one consolidated Japanese procedure. No current result authorizes M11, product rebuilding, personal-library operations, or publication.

## Verification of This Assessment

The received report copy matches its source byte for byte and is ignored by Git. Its source identifier, one preflight stop, four unrun cases, and absence of later phase records were checked. Source inspection located the refusal before the Music and legacy-reuse operations and confirmed that the raw preference output is retained in the local diagnostic log. Documentation changes were checked for consistency and whitespace errors. No executable source, prepared archive, live result, or historical report was changed, and no new runtime test, Music measurement, CI run, push, or publication is claimed.
