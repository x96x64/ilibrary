# Removal Performance Revision

## Purpose and Scope

This report records the investigation of the slow registration-removal phase of the first separated-addition qualification, the alternatives considered, the revision implemented in commit `7b16887` (`perf(m10): verify removal with bulk library snapshots`), and the procedure committed in `6843d35`. The [results report](separated-addition-qualification-results.md) is preserved unchanged. The maintainer approved on October 19, 2026 the M10 source changes, synthetic tests, documentation, and local commits for this revision, and stated that the maintainer personally performs the next separate-user qualification. The approval does not include pushing or merging the M10 branch, release or tag changes, or agent-run live verification. M10 has not passed.

Findings are classified as measured, inferred, or unknown. No Apple Events were sent, no probe was run, and Music was not used during the investigation or the synthetic tests.

## Investigation

In the first qualification, the `scale-release` case stopped in registration removal after 803.057 seconds. The maintainer observed about one removal per minute (maintainer-reported observation). The mechanism of the interruption is not inferred, and the number of registrations removed at the stop remains unknown.

The script text of `display_probe.remove_seeded` shows that, before each of the 300 deletions, it took a per-track snapshot. The snapshot AppleScript read about eight properties of every remaining track as separate Apple Events. The total is therefore about 361,200 events, and the cost of each iteration grows with the number of remaining tracks, so the total grows quadratically (inferred from the script text, not measured against Music).

With Music stubbed, the local work of all 300 iterations measured 11.4 seconds on synthetic data, about 38 ms per iteration (measured, synthetic). The local work is therefore not the dominant cost. The Apple Event traffic is the principal candidate, although the latency of an individual event in Music is unknown.

## Alternatives Considered

One alternative was to take full snapshots only at album checkpoints. It was rejected because it would allow up to fourteen deletions between full inventories, which weakens the guarantee that each deletion affects exactly one inventoried seed registration. The chosen design keeps an inventory of the remaining library before every deletion and reduces its cost instead of its frequency.

## Implemented Design

A qualification-only bulk snapshot, `scripts/validation/qualification_snapshot.py`, fetches each property for all tracks in one bulk reference. It uses nine Apple Events regardless of the track count. The ID list is fetched first and last, and the lengths of all property lists are checked against it, so that a change during the fetch or a misaligned list is detected as a failure.

An equivalence gate runs at seed registration, before evacuation. It requires the per-track snapshot and the bulk snapshot to agree on id, title, album, artist, path, path_error, and added. It logs both durations and the count of legacy-location diagnostic errors. The legacy location fields are diagnostic only, because the legacy expression returned read errors in the measured version 2 inventories.

Deletion semantics are unchanged: the same order, the same identity-checked DELETE by persistent ID, one deletion per call, and only the inventoried seed set. Before every deletion the probe still performs the remaining-library inventory, the image digest check, and the not-mounted check, and after every deletion it still performs the full comparison of the evacuated files. Only the duplicated pre-deletion file comparison was removed, because the post-deletion comparison of the preceding iteration covers the same state.

An append-only removal journal, `removal-journal.jsonl`, is flushed and synchronized with fsync at each record. It contains begin, intent, returned, verified, and end, stop, or interrupted records. A verified record is written only after the next snapshot and backup checks, or after the final empty snapshot. The probe prints PROGRESS, CHECKPOINT, and DURATION lines. A distinct INTERRUPTED state is recorded for KeyboardInterrupt and blocks later cases in the same way as STOP.

The bundle identifier is `ilibrary-m10-qualification-v2`, the manifest format is `ilibrary-m10-qualification-2`, and the new libraries are named `M10-separated-v2-<case>`. The display, rebuild, and timing probes are unchanged. The Japanese procedure, `docs/rebuild-qualification-v2-validation.md`, is copied into the bundle as `PROCEDURE.md`; the first-run procedure is unchanged.

## Safety Rationale

The guarantees retained are the identity-checked single deletion by persistent ID, the restriction to the inventoried seed set, the deletion order, the inventory of the remaining library before each deletion, the image and mount checks, and the full evacuated-file comparison after each deletion. The newly established properties are an equivalence check of the bulk snapshot against the per-track snapshot before any evacuation, a durable record of every intended and returned deletion, a verification record that depends on the following snapshot, and an explicit INTERRUPTED state that is distinguishable from STOP.

The residual risks are as follows. The bulk AppleScript has never been executed against Music, so its field formatting, list ordering, and error numbers are unknown until the live gate; the equivalence gate is designed to stop the case before evacuation if the two snapshots disagree. A change between the bulk fetches could produce a transient disagreement, which the first and last ID lists and length checks are intended to detect. The removal rate in Music is unknown and may remain slow if the bottleneck is the deletion rather than the snapshot. The revision does not establish that the interruption of the first run was caused by the snapshot cost.

## Tests

The probe test suite passed with 161 tests at `6843d35` (measured). It includes fault injection at deletion 7 for a different, extra, or added registration, a changed evacuated file, a changed or mounted image, a DELETE identity mismatch, a DELETE error, and KeyboardInterrupt both inside and between deletions. The 12 packaging tests passed (measured).

A synthetic stubbed removal of 300 registrations, with real local hashing and journal fsync and without Apple Events, took about 4.2 seconds, or about 14 ms per removal (measured, synthetic). This figure is not a prediction of Music performance.

## Bundle Identity

The bundle was prepared with `sh scripts/validation/prepare-qualification-probe.sh --prepare` at source commit `6843d357423db76a1b6c5022add8086212d2c168`. The manifest format is `ilibrary-m10-qualification-2` and lists 339 files. The archive is `ilibrary-m10-qualification-v2.zip`, with SHA-256 `6a8193942349aa21844d1ca3371932d8f005d2574bb7593db1ecb26939d1e7c1` and a size of 3,376,255 bytes. The extracted bundle passed its offline verify command, and its `PROCEDURE.md` equals the repository document. The archive and its checksum file were copied to the shared folder without overwriting, compared byte for byte, and the checksum was verified there (all measured). The first run's archive, checksum, report, library, and records are preserved.

## Unknowns

The behavior of the bulk snapshot in Music, the achievable removal rate, the cause of the first run's interruption, the number of registrations removed at that interruption, and the results of the artist-order cases are unknown. The display-order, preservation, and repeat gates of M10 have not been evaluated under the revised probe. M10 has not passed, and the next step is the maintainer's separate-user run of the version 2 procedure.
