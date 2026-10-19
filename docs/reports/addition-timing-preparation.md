# Separated Addition Timing Preparation

## Evidence and Scope

The maintainer authorized this preparation on October 17, 2026, after the completed negative display-v3 observation. That three-album case displayed `2,3,1` before and after relaunch instead of the expected `3,2,1`; it also recorded shared addition timestamps. The [assessment](display-order-v3-results.md) remains unchanged. A timestamp tie is a possible cause, not a measured explanation.

Commit `1493bdaa36257c848730a6fcdaabca17d24f1068` prepares one new three-album, six-track experiment in the separate test user. It uses newly generated synthetic files and a new initially empty library, retaining all old libraries and results. It performs no registration removal. The published executable and shared earlier probe modules are unchanged. This is an addition-method comparison, not another full evacuation and removal run or a product `rebuild` implementation.

## Timing Method

The probe invokes the existing `add` command once per album, in ascending release order `1,2,3`. After confirming an album, it waits at least two seconds on a monotonic clock before the next addition. State checks surround the wait; if they take more than thirty seconds, the next addition is refused when the check returns. Native subprocess calls retain their separate timeouts. The two-second interval is an experimental parameter, not a qualified minimum or a guarantee about Music's timestamps.

After each addition, the probe reads Music's actual exposed dates using the existing exact integral parser. Every date in the new album must be later than the maximum date in all previously added albums. A tie or reversal stops further addition without removing anything already added. Each boundary record contains the album number, observed minimum and maximum, previous maximum, gap, monotonic waiting duration, and observation time. Raw Music responses and exact identities remain in private diagnostics.

After all three ranges pass, the maintainer records Recently Added order twice, before and after relaunch. The expected sequence remains `3,2,1`. Separated timestamps alone cannot pass the experiment: an incorrect GUI sequence is `FAIL`, and an unavailable observation is `UNVERIFIED`. The experiment subsequently checks completed-addition repeat safety, files, journals, the preserved original backup, and the unchanged bundle inputs.

## Safety and Reporting

Live execution requires the established separate-user identity guard, no configured Apple Account, explicit confirmation of the new empty library, and the exact planned media parent. Either `Media` or `Media.localized` is accepted. Existing registrations, unexpected media files, symbolic links, insufficient space, changed registrations, modified files, or an altered backup prevent continued execution. The old library locations are not accepted.

Original synthetic copies are restored and compared from a detached read-only image. Music is then terminated before editing the working copies; editing is refused if it remains running. File contents and dates are compared after movement and repetition. Original inputs, images, journals, results, and prior bundles are never automatically removed. The image uses the same physical storage and does not qualify independent backup hardware.

`prepare`, `run`, and `report` offer `--dry-run`. Reporting reads saved results without querying Music, creates a new output exclusively, verifies its text, and labels a missing final result record as incomplete. The single report includes the historical negative observation with its source and report hash, without reopening the older test library. Completed or stopped live records cannot be overwritten by a repeated run. An early failure that prevents report generation must be returned as console output, with all existing state preserved.

## Verification

**Measured locally:** all 93 probe tests passed in 32.600 seconds, including twenty new timing tests. They cover complete substituted runs, actual bundle verification, strict timestamp separation, exponent-form dates, a slow or changed-state wait, changed files and backups, refusal of the old library and existing content, editing only while Music is closed, GUI disagreement and uncertainty, interruption reporting, incomplete final records, and refusal to repeat an existing run. Music, GUI responses, and native backup operations are substituted in these tests; they are not live Music measurements.

The initial restricted build could not write the normal compiler cache. Its failed preparation directory and log were retained. Preparation with normal development permissions subsequently completed the release build, generated six decodable synthetic files, validated both catalogs, and verified the ZIP contents, CRC, and executable mode. The packaged executable is byte-identical to the one in display-v3; bundled scripts and the Japanese procedure match the recorded commit.

A separate file-only check exercised the real executable on six working copies: original and edited catalog application with timestamps, file checks, catalog validation, native read-only image creation and restoration, and preservation of original backup contents all passed. It explicitly blocked Music calls. Bundle verification and a report of the unrun state also passed without creating a live-run record. These checks qualify preparation and file handling, not the waiting method's effect on Recently Added.

## Handoff

The new bundle is `ilibrary-m10-timing`. Its ZIP SHA-256 is `2eaac34237c317ae508572bf1be6af8151e0417b14bb4bcb8af94c4b29ec0380`. The ZIP and checksum were copied to the shared directory under new names without overwriting any earlier file; both destination copies matched.

The [Japanese procedure](../rebuild-timing-validation.md), also bundled as `PROCEDURE.md`, specifies the existing test user, one new library named `M10-timing-small`, archive verification, a dry run, one measurement, two GUI observations, and one shared report. The agent stops before these separate-user operations. The next evidence is `ilibrary-m10-timing-report.txt`, including failure or partial evidence when necessary. No live case was run during preparation.

## Remaining Gates

A passing small timing comparison would support further investigation of this method, not complete M10 or establish causation from a single comparison with historical data. Scale, the other ordering modes, repeated independent runs, timing and interruption limits, and the production policy remain unqualified. The historical tied-timestamp failure remains negative evidence; removing ties from the supported specification requires an explicit decision rather than silently changing the gate.

Automatic empty-GUI detection and independent physical backup retain their separate qualification requirements. Personal-library access, agent-run Music operations, M11–M15 implementation before M10 completion, pushes, and publication are outside this preparation. Current Status and the handoff identify the new bundle and pending result.
