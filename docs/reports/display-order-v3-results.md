# Display-Order Version 3 Results

## Evidence and Scope

The maintainer supplied the display-v3 combined report on October 17, 2026. It identifies source commit `f6511d56250504d82f1c55c1039905838615ebbc`, macOS 27.0.1, and Music 1.7. The existing small case contains three albums and six synthetic tracks. It started at 06:34:06 UTC (15:34:06 Japan Standard Time) and completed in 116.183 seconds. A byte-identical copy is retained under ignored `reference-private/m10-display-v3-results-2026-10-17/`; its SHA-256 is `6b859c028563f78efd741344ace1ebf23c67f70b0748ef11f029f68113795cfe`.

This assessment reads the supplied report and the recorded source. The prepared bundle's manifest identifies that source, and its two probe scripts match both the commit and the current repository files (measured locally). The assessment does not query Music, inspect a personal library, or operate the separate test user's library. GUI results are the maintainer's recorded observations, not an independent automated or screenshot-based examination.

## Recorded Results and Gate Assessment

| Condition | Result | Evidence Classification |
| --- | --- | --- |
| Selected media directory | Passed with `Media.localized` under the planned library | Measured, supplied report |
| Retained small-case inputs and registrations | Reuse reached backup restoration after the pinned-input and registration checks | Inferred from the recorded source's control flow and completed phases |
| Restored original backup and reconstructed edited copies | Passed; current library files matched the reconstructed edited copies | Measured, supplied report |
| Addition timestamps | Two distinct timestamps over one second; one second shared by multiple albums; each album's internal span was zero | Measured, supplied report |
| Recently Added before relaunch | **Failed:** expected `3,2,1`; observed `2,3,1` at 06:35:34 UTC | Measured, maintainer-recorded GUI observation |
| Recently Added after relaunch | **Failed:** expected `3,2,1`; observed `2,3,1` at 06:36:00 UTC | Measured, maintainer-recorded GUI observation |
| Registration stability across relaunch | The comparison with the saved registrations passed before the second observation | Inferred from control flow |
| Repeating the completed addition | Passed; persistent IDs, dates, files, and the journal remained unchanged | Measured, supplied report |
| Final preservation checkpoint | Passed; the original synthetic backup was verified | Measured, supplied report |
| Scale and three artist-order cases | All four explicitly `NOT RUN` | Measured, supplied report |

**M10 has not passed.** The small case reached `PHASE: complete` and returned `FAIL`; this is a completed negative display experiment, not another prerequisite `STOP`. Both intended-order checks failed. The unchanged incorrect sequence after relaunch does not satisfy the required persistence of the intended sequence. The one-second timestamp difference alone remains acceptable under Decision 33.

The earlier successful evacuation, guarded removal, human-confirmed empty GUI, termination, editing while closed, and readdition remain evidence from source `9fe4a53`. The display-v3 supplement reused that state without repeating evacuation or registration removal. Its preservation checks establish the reported synthetic case, not protection against every possible storage failure.

## Meaning of the Display Failure

The recorded addition plan was `1,2,3`, and the expectation was fixed in advance as reverse addition order, `3,2,1`. The two observations instead place album 2 before album 3. The source verifies the completed addition journal before observation; ordered command execution and correct registrations therefore do not establish the intended GUI sequence.

**Measured:** albums share an exposed addition timestamp, and the intended display order failed. **Inferred:** timestamp ties are a plausible explanation for ordering that differs from the addition sequence. **Unknown:** Music's tie-breaking rule and whether separating album addition times would produce and preserve the intended order. The report supplies no controlled comparison that isolates the cause. It does not establish that a fixed delay of any particular duration is sufficient.

The media-directory and retained-bundle checks no longer prevent observation. There is no basis in this report for attributing the display mismatch to an incorrect media-folder setting or to damaged required inputs. The mismatch also does not prove that every possible album-by-album addition method is infeasible.

## Unqualified Conditions

The 20-album, 300-track release-order case and the three artist-order cases remain unrun, rather than failed. Neither GUI order at scale nor rebuilding support for all four ordering modes is qualified. No further separate-user execution is needed merely to classify this report.

The aggregate reports both timestamp ties and different timestamps, but these diagnostic observations do not override the failed order checks. Automatic detection of an empty GUI remains unqualified because the earlier check used human observation. A restored disk image on the same physical storage does not qualify the independent physical backup required in M11. Other system versions, interruption recovery, and product rebuilding remain outside this result.

## Next Investigation and Stop Boundary

Preserve all libraries, original and edited synthetic files, backup images, completed journals, reports, and transferred bundles. Pause the remaining display-v3 cases while assessing the failed small-case observation. Do not rerun the completed case, clear its records, delete registrations, change the expected sequence to the observed sequence, or mark the failure as a pass.

The recommended next investigation is a narrowly scoped synthetic comparison in which successive albums receive nonoverlapping exposed addition timestamps. Preparation must define and record the inter-album wait, the actual timestamp boundaries, an explicit timeout or refusal, the expected and observed GUI sequences, and the observations after relaunch. It must use a new isolated test case and retain this negative result; waiting is a hypothesis to test, not an implemented correction or a qualified guarantee. A future restriction that refuses or excludes timestamp ties would require an explicit specification decision before changing the qualification gates.

Only after a candidate method succeeds should the remaining scale and ordering qualification be prepared around that method. The agent must stop before any separate-user Music operation and provide one reproducible Japanese procedure and a consolidated reporting path. This assessment changes documentation only. The next experiment and product rebuilding remain unimplemented, and the M10 requirements remain in force. Personal-library operations, M11–M15 implementation, pushes, and publication retain their existing authorization and qualification boundaries.
