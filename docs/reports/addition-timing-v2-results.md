# Separated Addition Timing Version 2 Results

## Evidence and Provenance

The maintainer ran the [version 2 timing procedure](../rebuild-timing-validation.md) once in the existing separate test user, with the new library `M10-timing-v2-small`, and supplied `/Users/Shared/ilibrary-m10-timing-v2-report.txt` on October 17, 2026. The report identifies probe source `4cd7c6b30065df1aef9c94b80bf5ab1bb2ef8f10`, case `timing-v2-small`, macOS 27.0.1, Music 1.7, three albums, and six synthetic tracks. The run started at 08:11:53 UTC (17:11:53 Japan Standard Time) and completed in 67.064 seconds. A byte-identical copy is retained under ignored `reference-private/m10-timing-v2-results-2026-10-17/`; its SHA-256 is `f7b026250623471c10d8e014565543b3b5ff25bda7076c0c26715f44ad0430ca`.

The report's historical sections repeat the display-v3 failure and the stopped first timing run with their source commits and checksums; they are not new measurements. The report command accepts a saved result only when its case, source commit, and final state agree with the result text and a passing state reaches `complete` (inferred from the frozen source). This assessment read the supplied report and the frozen probe source. It did not query Music, read the test user's library or media directory, or operate a personal library.

## Outcome

**The isolated small timing case returned `PASS`. Recently Added showed the expected album order `3,2,1` before and after relaunch.** Each album was added in its own invocation after the previous album was confirmed; every album's addition timestamps were later than all earlier ones.

| Check | Result | Classification |
| --- | --- | --- |
| Media selection | The selected folder `Media.localized` belonged to the new library | Measured, supplied report |
| Initial media content | 92 entries: 3 directories, Music's preference file, and 88 localization files; no `.DS_Store`; zero refused | Measured, supplied report |
| Original backup | The synthetic original backup was restored, verified, and detached on the same physical storage | Measured, supplied report |
| Editing | Working copies were edited while Music remained closed | Measured, supplied report |
| Waiting | 2.397 seconds before album 2 and 2.678 seconds before album 3, by the probe's monotonic clock | Measured, supplied report |
| Addition timestamps | Albums 1, 2, and 3 at exposed seconds 845572329, 845572333, and 845572339; gaps of 4 and 6 seconds; each album's two tracks share one second | Measured, supplied report |
| Timestamp summary | Three distinct values over a 10-second span; no overlap between albums | Measured, supplied report |
| Recently Added before relaunch | Expected `3,2,1`; observed `3,2,1` at 08:12:45 UTC | Measured, maintainer's visual observation |
| Recently Added after relaunch | Expected `3,2,1`; observed `3,2,1` at 08:12:54 UTC | Measured, maintainer's visual observation |
| Registration stability across relaunch | Registrations matched the saved state before the second observation | Inferred from control flow |
| Repeat safety | Repeating each completed addition preserved IDs, dates, files, and all three journals | Measured, supplied report |
| Final preservation | The original synthetic backup and immutable bundle inputs verified at the final checkpoint | Measured, supplied report |

The timestamp gaps exceed the waits because each album's preview, addition, and verification also take time (inferred). The gaps are not a qualified interval.

## Assessment

**Measured:** in this case, separated album additions produced strictly increasing exposed timestamps between albums, and the GUI showed reverse addition order, which is the intended display order, both before and after relaunch. **Inferred:** together with the display-v3 failure, in which albums shared an exposed second and the GUI showed `2,3,1`, the result supports the hypothesis that cross-album timestamp ties caused the earlier wrong order. It does not establish that cause: the two cases also differ in their libraries, their addition invocations, and the earlier case's removal and readdition. **Unknown:** Music's tie-breaking rule, whether the same method holds for twenty albums and 300 tracks, whether it holds for the three artist-order modes and after registration removal, whether a fixed wait or a timestamp check is the right product policy, and behavior on other system and Music versions.

The second new library again contained Music's preference file and the same 88 localization files, while the first library's `.DS_Store` was absent. This repeats the scaffolding observation once and is consistent with Finder, not Music, having created the earlier `.DS_Store` (inferred). The version 2 media guard admitted this content and nothing else.

## Remaining Gates

M10 has not passed. This is one successful small case with a candidate method; it is not a qualification of the method. The remaining gates are unchanged:

- the 20-album, 300-track scale case, including the full preservation, removal, and readdition sequence;
- the `artist`, `artist-desc`, and `artist-release` order modes;
- deterministic ties and the treatment of albums that would share an addition second;
- automatic GUI emptiness detection and independent physical backup.

The plan requires an explicit specification decision before timestamp ties are excluded from supported behavior. Adopting separated per-album addition as the supported method would be such a decision. Until the maintainer decides, no product feature, waiting interval, completion gate, or expected order changes. The display-v3 remaining cases stay paused; their probe adds all albums in one invocation and would not test the candidate method.

## Preservation and Handoff

Preserve the new library, bundle, records, and report, and every earlier library, bundle, backup, journal, and report. Do not repeat the completed case or the stopped first run, and do not remove registrations or manually readd tracks. The next step is the maintainer's decision on whether to adopt separated addition as the candidate method for the scale and order-mode qualification. Preparing that qualification, like every separate-user run, stops before the maintainer's Music operations. This assessment updates documentation only; it performs no Music or personal-library operation, push, or publication.
