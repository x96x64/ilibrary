# Separated Addition Qualification, Version 2 Results

## Purpose and Scope

This report assesses the maintainer's report of the version 2 separated-addition qualification, run on October 19, 2026 in a separate macOS user with the bundle `ilibrary-m10-qualification-v2`. The [first-run results](separated-addition-qualification-results.md) and the [removal performance revision](removal-performance-revision.md) are preserved unchanged. No probe was run, no Apple Event was sent, and Music was not used during this assessment. Findings are classified as measured, inferred, maintainer-reported, or unknown. M10 has not passed.

## Evidence

The maintainer's report is preserved byte for byte under the ignored directory `reference-private/m10-qualification-v2-results-2026-10-19/report.txt`. It has 44,671 bytes and 481 lines, and its SHA-256 is `0c1eb8ccfd87af9d4b39bfbdcbb6cd8a4934a9dfe43d511a001464e0512673d6`; it is identical to the copy in the shared folder (measured). The report names source `6843d357423db76a1b6c5022add8086212d2c168` in its header and in the case section. The probe sources at the assessed commit are identical to that commit, and the report contains every section that the frozen report command emits (measured). The environment was macOS 27.0.1 and Music 1.7 (measured, from the report).

The case records that the request to the maintainer named (`result.json`, the observation JSON files, `boundary-20.json`, and file times) were not supplied; only the report was (measured). Statements below that depend on those records are therefore marked as inferred or unknown.

## Cases

| Case | Result | Notes |
| --- | --- | --- |
| scale-release | PASS | 20 albums, 300 tracks, library `M10-separated-v2-scale-release`, 624.715 s, started 14:03:20.066 UTC |
| artist | NOT RUN | report text: "no saved measurement" |
| artist-desc | NOT RUN | report text: "no saved measurement" |
| artist-release | NOT RUN | report text: "no saved measurement" |
| aggregate | NOT COMPLETE | three required cases are unrun |

The report contains no STOP, WARN, REFUSED, FAIL, UNVERIFIED, or INTERRUPTED line and 15 PASS lines (measured). It gives no reason that the artist cases were not run. From the source, the frozen report cannot distinguish a case never invoked from one refused before its work directory existed (inferred). Why they were not run is unknown. The media folder held 92 scaffolding entries created by Music, none refused (measured).

## Phases

All 14 phases appear in procedure order, and the DURATION lines sum exactly to 624.715 s (measured).

| Phase | Duration (s) |
| --- | --- |
| preflight | 3.755 |
| empty-library | 0.131 |
| seed-addition | 125.524 |
| backup | 19.944 |
| evacuation | 0.526 |
| registration-removal | 167.168 |
| empty-gui | 20.629 |
| quit-and-edit | 1.016 |
| separated-readdition | 240.893 |
| display-before-relaunch | 19.338 |
| relaunch | 2.084 |
| display-after-relaunch | 4.800 |
| repeat-and-preservation | 18.907 |
| complete | 0.0 |

## Gates for the scale-release Case

The gates are judged against the M10 row and section of the [stable release plan](../stable-release-plan.md) and Decisions 29, 33, and 36, using report lines (measured unless stated).

Preservation is met. The backup was restored, verified, and detached on the same physical storage as the library. Evacuation retained bytes and dates, the evacuated files were unchanged through removal, and the edited bytes and dates were verified after readdition. The final backup and the bundle input check passed.

The process is met. The sequence was backup, evacuation, 300 guarded removals with one persistent ID per call, an empty GUI confirmed by the maintainer and by an empty snapshot, quit and edit while closed, and 20 separated additions with 0 cross-album ties. The 20 timestamps were distinct, gaps were 7 to 9 s with mean 8.05 s and span 153 s, and waits were 2.297 to 2.555 s.

The display order is met for release mode. Recently Added showed 20, 19, ..., 1 before relaunch (answered 14:13:18.992 UTC) and after relaunch (answered 14:13:25.875 UTC), equal to the expected order. Two caveats are inferred from source: on answer 1 the logged observed list is the expected list and not an independent transcription, and the 4.8 s second phase does not show whether all 20 cards were inspected.

Repeat execution is met: a repeated completed addition preserved identifiers, dates, files, and all 20 journals.

M10 as a whole has not passed, because the three artist-order modes required by the plan are unrun. Automatic detection of GUI emptiness and independent physical backup remain not qualified by design, and no waiting interval is qualified.

## Removal Performance

The equivalence gate between per-track and bulk snapshots passed on id, title, album, artist, path, path_error, and added. The legacy location read produced an error in 300 of 300 per-track rows; this is diagnostic only (measured).

| Quantity | Value | Classification |
| --- | --- | --- |
| Per-track snapshot of 300 registrations | 40.092 s | measured, one observation |
| Bulk snapshot of 300 registrations | 0.482 s | measured, one observation |
| Ratio | about 83 | measured, derived |
| Registration removal, 300 removals | 167.168 s, mean 0.557 s | measured |
| Per-removal intervals | 0.4 to 0.9 s (0.1 s resolution), median 0.6 s | measured from PROGRESS lines |
| First 50 removals, mean | 0.650 s | measured |
| Last 50 removals, mean | 0.462 s | measured |

The interval decreased as tracks remained fewer. The first run's 803.057 s is a case total and is not comparable; its only removal-rate evidence is the maintainer's observation of about one removal per minute, so the roughly hundredfold difference is an uncontrolled order-of-magnitude statement that compares a maintainer-reported figure with a measured one. A model that assumes the old per-track snapshot cost scales linearly from 40.092 s at 300 tracks implies about 6,034 s for the old removal phase, about 36 times the measured 167.168 s (inferred; assumptions are zero fixed cost and constant event latency, and the model excludes about 0.44 s per removal of other work). The model's roughly 40 s for an early iteration differs from the observed roughly 60 s, and the difference is unexplained (unknown). The improvement is demonstrated only for this 300-track synthetic library on this Mac, macOS version, and Music version.

## Music Startup Observation

The maintainer reports that, after the 20 albums had been added, Music took approximately one minute to open or become usable (maintainer-reported, approximate, unmeasured). The maintainer's statement of the event and the wall-clock time is not available.

The probe has no explicit launch command; from source, Music is launched implicitly by the first osascript snapshot after each quit. The reconstructed timeline in UTC uses phase boundaries derived from the started time and durations, which agree with observation times within 2 ms. Album addition times are inferred assuming that the test user's time zone is JST. Seed-addition ran from 14:03:23.952 to 14:05:29.476, with the 20 albums added in one invocation, and the first read afterwards, the per-track snapshot, took 40.092 s. Removal ended at 14:08:37.114 and quit-and-edit at 14:08:58.759. Separated-readdition ran from 14:08:58.759 to 14:12:59.652, with the implicit launch at its start bounded to about 1 to 2 s before album 01 at 14:09:00, and album 20 was added at 14:11:33. The relaunch ran from 14:13:18.990 to 14:13:21.074, which is 2.084 s including the quit, the implicit launch, and a 300-row bulk snapshot, and display-after-relaunch was answered at 14:13:25.875.

No probe-recorded launch interval therefore contains a one-minute launch or Apple Event readiness delay (measured, with the time-zone inference for the readdition start). Rendering readiness of the GUI is not instrumented. The only probe-recorded interval after the 20th addition that is long enough to contain a one-minute delay is the 86 s tail from album 20 (14:11:33) to the end of separated-readdition (14:12:59.652), during which Music was running. In that interval the probe takes a bulk snapshot, compares 300 files, runs the product command `ilibrary check <media> --library`, computes date diagnostics, and takes another bulk snapshot (inferred from source).

In `Sources/LibraryMac/MusicApp.swift`, `describeTracks` reads about 16 properties of every track as separate Apple Events. By analogy with the measured 40.092 s for about 8 per-track reads in the probe snapshot, `check --library` would take on the order of 80 s for 300 tracks (inferred, unverified; the command duration is not logged). A hypothesis, which is not established, is that the maintainer perceived Music as slow or unusable while it serviced these events. The interval from the case end at 14:13:44.781 UTC to the report file's modification time of 14:24:11 UTC, about 626 s, is unrecorded, so a launch by the maintainer after the case, for example to create the library of the next case, cannot be excluded (unknown).

No acceptance criterion defines a startup duration; the observation is a performance concern and not a gate failure. If the inference holds, `check --library` scales linearly with library size at about 16 Apple Events per track and would be slow on large personal libraries (inferred). This concerns the published product command and not the probe, and it warrants a separate, explicitly approved investigation, for example bulk property reads in `LibraryMac` with an equivalence test and timing instrumentation, and not a change to the frozen qualification source. Evidence that would locate the delay without operating Music is the maintainer's statement of the event and approximate wall-clock time, and the modification and birth times of `final-registration.json`, `after-relaunch.json`, the observation files, and `boundary-NN.json`, together with `result.json` and `plan.json`.

## Limitations and Next Step

Only one of four cases has run, on one Mac, one macOS version, and one Music version, and the case records beyond the report were not supplied. The artist-order behavior, the cause of the non-execution of three cases, the startup delay, and the cost of `check --library` remain unknown or unverified. No gate, expected order, waiting interval, decision, or product feature has changed.

The next step belongs to the maintainer: to run the `artist`, `artist-desc`, and `artist-release` cases with the same version 2 bundle and procedure, each in a new library; to regenerate the report under a new file name, because the report command refuses to overwrite and the existing report must stay; and to state the event and approximate time of the startup delay. A repeated `scale-release` record, if produced, is to be assessed with the new report.
