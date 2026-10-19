# M10 Separated Addition Qualification Results

## Purpose and Scope

This report consolidates the assessment of the version 2 separated-addition qualification for milestone M10. The `scale-release` case was assessed in [Separated Addition Qualification, Version 2 Results](separated-addition-qualification-v2-results.md), which remains the historical record for that case. The `artist`, `artist-desc`, and `artist-release` cases were run afterwards by the maintainer in a separate macOS user and are assessed here. The report records no decision. Whether M10 is accepted and whether M11 implementation is authorized are decisions reserved to the maintainer.

Findings are classified as measured, inferred, maintainer-reported, or unknown. The environment was macOS 27.0.1, Music 1.7, and one Mac, with one run per case. Behavior on other macOS or Music versions is unknown.

## Evidence

The new report is preserved byte for byte under the ignored directory `reference-private/m10-qualification-v2-artist-orders-results-2026-10-20/report.txt`. It has 60,391 bytes and 745 lines, and its SHA-256 is `6fb7418f8f4da4303da64eb6b839e3cfee6a9f73f4749a93fccda27dfc3e88bd`; it is identical to the shared copy (measured).

Its header and `scale-release` section are byte-identical to the earlier report, whose SHA-256 is `0c1eb8ccfd87af9d4b39bfbdcbb6cd8a4934a9dfe43d511a001464e0512673d6` (measured). The `scale-release` case is therefore counted once, from the earlier assessment. Every case section names source commit `6843d357423db76a1b6c5022add8086212d2c168`, and `scripts/validation` at the current head is identical to that commit (measured). The report contains every section that the frozen report command emits. The aggregate reads four `PASS` results, zero cross-album ties, and "Separated-addition synthetic qualification: PASS" (measured). No `STOP`, `WARN`, `REFUSED`, `FAIL`, `UNVERIFIED`, or `INTERRUPTED` line appears, except the historical first-run line that the report carries (measured).

Library names of the form `M10-separated-v2-<case>` are inferred from the source, because the report prints only the media folder name.

## Cases

All four cases passed. The artist cases each used 4 albums and 8 tracks; the release case used 20 albums and 300 tracks.

| Case | Albums | Tracks | Result | Planned addition order | Expected display order | Started (UTC) |
| --- | --- | --- | --- | --- | --- | --- |
| scale-release | 20 | 300 | PASS | (earlier assessment) | (earlier assessment) | (earlier assessment) |
| artist | 4 | 8 | PASS | 2,4,1,3 | 3,1,4,2 | 2026-10-19 22:55:14.313 |
| artist-desc | 4 | 8 | PASS | 3,1,4,2 | 2,4,1,3 | 2026-10-19 22:57:32.299 |
| artist-release | 4 | 8 | PASS | 4,2,3,1 | 1,3,2,4 | 2026-10-19 22:59:35.773 |

For `scale-release`, the earlier assessment records a pass after 624.715 seconds (measured). Elapsed times of the artist cases were 99.077, 79.777, and 76.135 seconds in the order shown, each equal to the sum of its phase durations within 3 ms (measured).

## Phase Durations

The following durations are in seconds, for the three artist cases only, in the order artist, artist-desc, artist-release.

| Phase | artist | artist-desc | artist-release |
| --- | --- | --- | --- |
| preflight | 3.892 | 7.084 | 2.838 |
| empty-library | 0.105 | 0.115 | 0.105 |
| seed-addition | 4.168 | 4.213 | 4.163 |
| backup | 19.784 | 11.513 | 10.357 |
| evacuation | 0.247 | 0.250 | 0.239 |
| registration-removal | 3.424 | 3.458 | 3.475 |
| empty-gui | 15.973 | 14.433 | 11.182 |
| quit-and-edit | 1.066 | 0.447 | 0.453 |
| separated-readdition | 16.367 | 16.607 | 16.370 |
| display-before-relaunch | 20.277 | 12.072 | 14.532 |
| relaunch | 1.581 | 1.547 | 1.704 |
| display-after-relaunch | 9.965 | 5.826 | 8.519 |
| repeat-and-preservation | 2.227 | 2.209 | 2.198 |

All values are measured. Phases that include maintainer actions, such as the empty-GUI and display phases, contain human response time and are not product performance.

## Ordering Verification

The ordering rule is inferred from the source. The function `display_probe.case_spec` assigns artist A to albums 2 and 4 and artist B to albums 1 and 3, with release years 2004, 2003, 2002, and 2001 for albums 1 to 4. `Sources/CatalogCore/Ordering.swift` sorts `artist` by artist ascending then album, `artist-desc` by artist descending then album descending, and `artist-release` by artist, then date, then album. These rules yield exactly the planned addition orders in the table above and agree with `docs/command-line-interface.md`. The expected display is the plan's stated target of reverse addition order (`docs/stable-release-plan.md`, Display Order and Addition Dates).

## Gates by Case

The gates are judged against `docs/stable-release-plan.md`: the completion gate on line 73 (verified preservation and required sequence, exact registrations, intended GUI order after relaunch, repeat safety, recorded timestamp differences, and no missing required observation) and line 59 (small and scale evidence covers preservation, sequence, display, and repeat safety).

| Gate | artist | artist-desc | artist-release | scale-release |
| --- | --- | --- | --- | --- |
| Preservation | met | met | met | met |
| Process and required sequence | met | met | met | met |
| Exact registrations | met | met | met | met |
| GUI order after relaunch | met, maintainer-confirmed | met, maintainer-confirmed | met, maintainer-confirmed | met (earlier assessment) |
| Repeat safety | met | met | met | met |
| Timestamp differences recorded, no cross-album tie | met | met | met | met |
| Missing required observation | none | none | none | none |

Exact registrations rest on the equivalence gate, which passed in each artist case, and on one registration per file (measured). Display observations before and after relaunch equal the expected list in every artist case: artist at 22:56:39.616 and 22:56:51.162, artist-desc at 22:58:42.492 and 22:58:49.865, and artist-release at 23:00:39.486 and 23:00:49.708 UTC (measured). Scale evidence is release mode at 300 tracks; the artist modes are small cases at 8 tracks, and the plan does not require every mode at scale.

## Performance

Figures apply only to the named case, to this synthetic library, and to this Mac. They are not compared across workloads. Each is one observation.

| Case | Workload | Per-track snapshot | Bulk snapshot | Removal | Legacy read error |
| --- | --- | --- | --- | --- | --- |
| artist | 8 registrations | 1.152 s | 0.253 s | 3.424 s (mean about 0.43 s) | 8 of 8 (diagnostic) |
| artist-desc | 8 registrations | 1.154 s | 0.253 s | 3.458 s (mean about 0.43 s) | 8 of 8 (diagnostic) |
| artist-release | 8 registrations | 1.154 s | 0.255 s | 3.475 s (mean about 0.43 s) | 8 of 8 (diagnostic) |
| scale-release | 300 registrations | 40.092 s | 0.482 s | 167.168 s | (earlier assessment) |

Readdition boundary gaps between consecutive albums were 4, 3, and 4 seconds (span 11) for artist, 4, 3, and 4 seconds (span 11) for artist-desc, and 4, 4, and 4 seconds (span 12) for artist-release. Waits between albums were 2.262 to 2.282 seconds. No shared second occurred across albums, and within-album spans were 0 (measured). Relaunch took 1.581, 1.547, and 1.704 seconds respectively (measured).

## Display Evidence Caveat

On answer 1, `display_probe.display_answer` and the observation log record the expected list as the observed list. Each of the eight display `PASS` results across the four cases is therefore the maintainer's visual confirmation, and not an independent transcription or an automatic measurement (inferred from the source). The display gate rests on the maintainer's observation.

## Deterministic Ties

Remaining M10 Qualification item 4 lists deterministic ties. Ordering ties were not exercised live, because the synthetic sort keys are distinct (inferred). The product's ordering unit tests, which include a release-date tie and an undated album, passed locally: `swift test --filter CatalogCoreTests` ran 41 tests, all passing, on October 20, 2026 (measured). Whether this unit coverage satisfies item 4 is an interpretation reserved to the maintainer.

## Items Placed in Later Milestones

The plan places the following outside M10. Automatic GUI emptiness detection is a prerequisite for M12 (`docs/stable-release-plan.md`, item 4 and the M12 gate). Independent physical backup and restoration belong to M11 (item 5). No qualified waiting interval exists, and none is an M10 gate. Behavior on other macOS or Music versions is unknown, as the plan's Unknown row states.

## Startup and Check Library Concern

The maintainer previously reported that Music took approximately one minute to become usable after the additions; the event was not stated and the delay remains unmeasured (maintainer-reported). Inferred tails from the last album's addition second to the end of readdition, under a JST assumption, were 4.34, 4.42, and 3.95 seconds for the three artist cases. They include an unlogged `ilibrary check --library` over 8 tracks. These tails are compatible with, but do not test, the hypothesis of about 16 Apple Events per track, and they do not bear on the one-minute observation (inferred).

A separate read-only investigation of `check --library` found one plus sixteen Apple Events per track over the whole library, while `add` remains album-bounded, and it proposed a bulk-read design. The location of its document in the repository was not established, nothing was committed, and implementation requires the maintainer's approval (inferred from the session's account; unknown as to the document). This is a product performance concern and not an M10 gate.

## Conclusion and Pending Decisions

The qualification evidence satisfies every recorded M10 completion-gate condition, with the interpretation of deterministic ties noted above. Recording M10 as passed, accepting the ties interpretation, and authorizing M11 product implementation are maintainer decisions; `docs/stable-release-plan.md` states that M11 to M15 implementation remains gated on M10. No decision is recorded in this change, and nothing is pushed.

The next milestone is M11 (0.2.0): independent backup verification, complete inventory, evacuation plans, strict catalog export, and versioned recovery records. Its gate requires restoring bytes, paths, and required dates from separate physical media, verifying and disconnecting the backup, and rejecting incomplete inventories, overlap, unsupported values, insufficient capacity, and unsafe plans before mutation. Portable logic is developed on Linux; dates, separate media, and restoration are verified on macOS. The roadmap table recommends Claude Opus 5.5 at high effort and GPT-6-Astra at high effort.
