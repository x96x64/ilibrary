# Display-Order Version 2 Results

## Evidence and Scope

The maintainer supplied the display-v2 combined report on October 17, 2026. It identifies source commit `97d4c0bdf049fb2f5d4191a26f4bb6dfaa760375`, macOS 27.0.1, Music 1.7, and a small-case start time of 06:11:55 UTC (15:11:55 Japan Standard Time). A byte-identical copy is retained under ignored `reference-private/m10-display-v2-results-2026-10-17/`; its SHA-256 is `486f1ae64cbb9b1b7b41433dff48eeeb0695e3a4005444d93b3291b9f7c41cf6`.

This assessment uses that report and the recorded source. It does not query Music or inspect the separate user's bundle, registrations, or library files. Earlier reports and all transferred display archives remain unchanged.

## Recorded Results and Gate Assessment

| Condition | Result | Evidence Classification |
| --- | --- | --- |
| Selected media directory | Passed with `Media.localized` under the planned library | Measured, supplied report |
| Music version read | Returned 1.7 | Measured, supplied report |
| Retained bundle inventory | Stopped in `legacy-evidence` after 3.451 seconds | Measured, supplied report |
| Original manifest identity | Passed before the reported inventory refusal | Inferred from the source's ordered checks |
| Retained files' content hashes | Not reached by the stopped verifier | Inferred from control flow |
| Current small registrations, backup restoration, and edited-file comparison | Not reached | Inferred from control flow |
| Recently Added order before and after relaunch | No observation | Unverified |
| Completed-addition repeat safety and final preservation | Not reached | Unverified |
| Scale and three artist-order cases | All four explicitly `NOT RUN` | Measured, supplied report |

The media-name correction has passed its corresponding live check. M10 remains incomplete: this is a stopped prerequisite check, not a measured display-order failure. The earlier six-track sequence and one-second timestamp difference remain historical evidence, not fresh verification of current registrations or files. Decision 33 still permits that timestamp difference alone. Automatic GUI emptiness detection and independent physical backup qualification remain unverified.

## Meaning and Limits of the Refusal

The reported Japanese refusal means that the retained verification bundle's file list differs from its manifest. In `reuse_small`, the probe checks the pinned original manifest, then calls `rebuild_probe.verify_bundle` on the older `ilibrary-m10-v2` directory. That verifier compares regular file paths outside `reference-private` with the 313 manifest entries plus `manifest.json`. It checks content hashes only after the file-list equality check succeeds.

**Inferred from the source:** the pinned manifest identity passed, but this path-set comparison did not. The refusal can represent additional entries, missing entries, or both. It does not establish damaged audio, changed tags, an incorrect Music setting, or a changed registration. The report provides neither differing names nor content hashes, so the actual difference remains unknown. Locally constructed additional-file and missing-file examples both reproduce the same message; neither identifies the actual test-user discrepancy.

The stopped run read Music's version and wrote its own plan, diagnostics, and result records. It stopped before reading current registrations, mounting the retained backup, repeating addition, quitting Music, or editing library files. This is a source-based execution boundary, not an independent examination of the user's files after execution.

The synthetic existing-small tests substitute the old bundle verifier. They cover later reuse behavior but did not establish that an already used, extracted bundle would still satisfy this exact file-list check. This is a confirmed coverage and diagnostic limitation. Do not weaken the inventory check or remove an unexpected file before its identity and significance are known.

## Read-Only Diagnostic Handoff

Commit `c56190d` adds a standalone file-only diagnostic and its tests. It requires the separate test user, pins the original manifest hash, inventories the retained bundle without following symbolic links, prunes private records, and distinguishes missing files, additional files, nonregular entries, content mismatches, and unreadable expected files. Additional files are listed without reading their contents. Relative filenames are saved only under `reference-private`; console output contains counts. A manifest mismatch prevents further inventory interpretation.

The diagnostic offers `--dry-run`, states its output plan, creates a new report exclusively, and reads that report back. It does not import or execute either live probe, invoke the product, issue Apple Events, inspect Music preferences, or change the retained bundle. It is not a repair or a qualification run.

The script and checksum were copied to the shared directory without overwriting existing files; their bytes match the repository source. The script's SHA-256 is `865e7820931af3341feb72269f1a9eba5dfcd801df2788fd89d978a5def262ae`. The [Japanese diagnostic procedure](../rebuild-bundle-diagnostics.md) requires one command block in the existing test user and returns one private inventory report. Do not rerun any live case, create another library, change settings, delete an extra file, or restore a missing file before assessing that evidence.

## Verification and Next Boundary

**Measured locally:** nine diagnostic tests passed. They cover unchanged input bytes and modification dates, additional files without content reads, missing and changed files, non-followed symbolic links, private-record exclusion, manifest mismatch, exclusive report creation, ordinary-user refusal, and dry-run behavior. The retained preparation bundle in the development workspace matches all 314 expected regular files and content hashes. This is a local preparation copy, not the test user's extracted bundle.

The received report copy, relative documentation links, preview source hashes, and staged privacy and whitespace checks were verified. Live probe source and archives were not changed. No new live Music measurement, product implementation, CI run, push, or publication occurred. The next task is assessment of the read-only inventory report; M11 and product rebuilding remain gated on M10.
