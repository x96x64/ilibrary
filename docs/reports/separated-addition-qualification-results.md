# Separated Addition Qualification Results

## Evidence and Provenance

The maintainer ran the [separated-addition qualification procedure](../rebuild-qualification-validation.md) in the existing separate test user and returned a summary report. The report identifies probe source `bf84ee97a058fe095023e66afbba1480f18b265c`, macOS 27.0.1, Music 1.7, and the first case, `scale-release` (20 albums, 300 tracks), which started at 12:25:03 UTC on October 17, 2026 in the new library `M10-separated-scale-release`. A byte-identical copy is retained under ignored `reference-private/m10-qualification-results-2026-10-17/`; its SHA-256 is `deb58894e0f00c6351c084e90fac8a4375019a714dd1ef2bc2da41d3684d421f`. The maintainer's shared copy has the same digest (measured by the coordinator).

The probe sources under `scripts/validation/` at the assessed commit are identical to those of `bf84ee9` (measured with `git diff`, which reported no difference). This assessment read the supplied report, the frozen probe sources, and their tests. It did not query Music, run any probe, read the test user's library, media directory, or records, or operate a personal library. Evidence is classified as measured (stated in the supplied report or verified locally), inferred (derived from the frozen source), or unknown.

## Outcome

**The `scale-release` case did not complete. It passed four phases, then stopped in `registration-removal` with the reason `KeyboardInterrupt` after 803.057 seconds. The cases `artist`, `artist-desc`, and `artist-release` were not run. The aggregate result is `NOT COMPLETE`.**

| Phase or Item | Result | Classification |
| --- | --- | --- |
| Media selection | The selected folder `Media.localized` belonged to the new library | Measured, supplied report |
| `empty-library` | No initial registration; 92 media entries (3 directories, no Finder state entry, 1 Music preference file, 88 localization files); none refused | Measured, supplied report |
| `seed-addition` | Only freshly generated tracks were registered; the product's addition order matched the saved plan | Measured, supplied report |
| `backup` | The synthetic original backup was restored, verified, and detached; same physical storage | Measured, supplied report |
| `evacuation` | Evacuation retained every byte and file date | Measured, supplied report |
| `registration-removal` | Stopped with `KeyboardInterrupt`; no completion line was written | Measured, supplied report |
| Elapsed time | 803.057 seconds at the stop | Measured, supplied report |
| Later phases | `empty-gui`, `quit-and-edit`, `separated-readdition`, display observations, relaunch, and repeat safety were not reached | Inferred from the phase sequence and the stop |
| `artist`, `artist-desc`, `artist-release` | `NOT RUN: no saved measurement` | Measured, supplied report |
| Cross-album timestamp ties in completed readditions | 0, because no readdition was completed | Measured, supplied report; not evidence of separation |

The media folder contained the Music-created scaffolding admitted by the timing version 2 correction and no Finder state entry; the guard refused no entry (measured, supplied report).

## Registration Removal in the Frozen Source

The following conclusions are inferred from `qualification_probe.py`, the frozen `display_probe.py` and `rebuild_probe.py` that it imports, and the probe tests; none is stated in the report.

Removal is issued per track, not in bulk. The phase calls `remove_seeded` once. For each of the 300 inventoried registrations in turn, it runs the identity guard, takes a full snapshot of the library, checks that the snapshot contains exactly the not-yet-removed seeded registrations and their expected files, compares the evacuated files with their saved states, recomputes the digest of the backup image and verifies its detachment, and only then issues one Music `delete` addressed by persistent ID, with title, album, and artist checks inside the script. It then compares the evacuated files again. After the loop it requires an empty snapshot. Each delete script is bounded at 120 seconds, and each external command at 600 seconds. A timeout would have been reported as `TimeoutExpired`, not as `KeyboardInterrupt`.

Because every iteration reads the whole remaining library, the work per removal grows with the library size. No per-removal progress line, counter, or timestamp is written to the report or to the result record; only the phase marker `PHASE: registration-removal` precedes the stop. The completion line, which would state that 300 registrations were removed, is written only after the loop and the backup check, and it is absent from the report. The sequence is therefore consistent with a stop at any point between the first and last of the 300 iterations.

`KeyboardInterrupt` is one of the exceptions caught in `execute`. The handler sets the state to `STOP`, writes the three-line stop notice with the phase name and the exception class, writes `failure.txt`, and the `finally` block records the finish time, the elapsed time, the case result, and `result.json`. The report command then reproduces the saved text. The handler performs no rollback, no snapshot, and no further Music call, so the library state at the stop is not recorded by the probe.

An interruption can therefore leave any number from zero to 299 of the 300 registrations removed. Zero would require an interruption before the first delete completed; 300 is excluded because the completion line is absent. A delete in flight at the interruption may or may not have been applied by Music. Whether Music applied it cannot be determined from the report (unknown). The evacuated files were moved before this phase and the removal phase does not modify them (inferred), but no file comparison ran after the interruption.

The diagnostic log of each case, `diagnostics.jsonl`, records each completed external command, including delete invocations and the raw response of each snapshot. A command interrupted before it returned is probably not recorded (inferred from the order of calls in `run`). A file-only inspection of the case's records could therefore establish how many deletes completed, but the assessment did not read them.

## Elapsed Time

The reported 803.057 seconds is case-total, not specific to the removal phase. The monotonic clock starts when the measurement object is created, before preflight, and the `finally` block reports the interval to the stop (inferred from the frozen source). It includes the maintainer's wait at the `TEST` confirmation prompt, the seed addition and its checks, the backup, the evacuation, and the removal iterations up to the stop. The report records no per-phase times, no stop time, and no number of completed removals. The elapsed time would place the stop at about 12:38 UTC if the monotonic start coincides with the recorded start time (inferred); this is not a phase duration. The share of the 803 seconds spent in removal is unknown.

## Cause of the Interruption

The cause of the `KeyboardInterrupt` is unknown. The report does not state whether it followed a manual Control-C, a closed terminal, or another SIGINT. The Japanese procedure expressly allows the maintainer to press Control-C when the run needs to be stopped, so a deliberate stop is possible (measured from the procedure text), but nothing in the report establishes it. A slow run that the maintainer abandoned, an unattended terminal, and an unrelated signal are all consistent with the evidence. This assessment asserts none of them.

The report also does not show whether Music itself failed, stalled, or remained responsive. No deliberate fault, Music error, or guard refusal is reported; a guard refusal would have been reported by its message, not as `KeyboardInterrupt` (inferred).

## Evidence Limits

The report gives no evidence about separated readdition at scale, display order, relaunch behavior, repeat safety, or the three artist-order modes. It does not show whether the removal phase is practical at 300 registrations; the only timing is the case-total stop time. No waiting interval is qualified. The automatic detection of an empty graphical interface and an independent physical backup remain not qualified, as the report's own scope section states. The seed addition, backup, and evacuation passing once at this scale is evidence for those phases only. M10 has not passed.

## Preservation Requirements

All libraries, bundles, backups, journals, and records are retained: the stopped `M10-separated-scale-release` library with its media folder, the qualification bundle and ZIP, the case's work directory with its seed, backup image, evacuated files, snapshots, diagnostics, and result records, the returned report and its copies, and every earlier library, bundle, backup, journal, and report. The stopped case must not be rerun or continued, and the cases that were not run must not be started until the maintainer decides. No registration is to be removed or readded manually, and no track is to be moved back, edited, or deleted. The case's work directory exists, so the probe refuses a rerun of the same case by design (inferred from the frozen source). This assessment performs no Music or personal-library operation, push, or publication.

## Questions for the Maintainer

The following matters cannot be resolved by this assessment and are returned for decision.

1. Whether the interruption was deliberate.
2. Whether to prepare a revised probe that reports removal progress and per-phase timing and that can stop at a bounded time without discarding state, run as a new case with a new library name while the record of this case remains frozen.
3. How the stopped state is to be inspected file-only, without Music, to establish how many registrations were removed and whether the evacuated files remain unchanged, and who performs that inspection in the test user.
4. Whether removing 300 registrations one at a time, with a full library snapshot, file comparison, and backup-image digest before each removal, is acceptable for the qualification, or whether the scale should be reduced or the checks made incremental. Any such change alters the qualification and requires a decision, as does any change of the gates.
5. Whether the three artist-order cases may proceed independently of the scale case, which the probe's stop rule currently forbids after a `STOP`.

## Conclusion

The first execution of the separated-addition qualification measured four passing phases and an incomplete removal phase. It does not pass or fail the method, and it neither supports nor contradicts the timestamp hypothesis. M10 has not passed. The next step requires a maintainer decision. No gate, expected order, waiting interval, or product feature has changed.
