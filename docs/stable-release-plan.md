# Plan for the Stable Release

## Status and Evidence

Approved by the maintainer on October 17, 2026, and revised on the same date after the M10 timestamp measurements. The maintainer accepts differences in addition timestamps when Recently Added presents the intended album order. Decisions 34 to 36 authorize guarded probe preparation and separate-user handoffs, including the isolated timing comparison and the separated-addition qualification, with a stop before the maintainer's Music operations; they do not authorize product implementation, personal-library operations, or publication. Version 0.1.0 is published. This plan supersedes the prospective version assignments in the [historical study](planning-study.md#outlook-to-version-100), not its completed measurements.

| Classification | Evidence | Consequence |
| --- | --- | --- |
| Measured, maintainer-reported | The version 2 small case completed evacuation, guarded registration removal, human-confirmed empty GUI, termination, editing while closed, and album-by-album readdition with file/library verification | Preserve these results; do not repeat destructive steps solely because the timestamp requirement changed |
| Measured, supplied numeric evidence | Six saved addition timestamps contain two distinct values separated by one second | The historical equality gate failed; that difference alone does not fail the revised gate |
| Measured, supplied display-v3 report | The small case completed; expected order `3,2,1` differed from observed `2,3,1` before and after relaunch | M10 has not passed; pause the remaining cases while investigating the display failure |
| Measured, supplied display-v3 report | Backup restoration, reconstructed-file comparison, completed-addition repeat safety, and final synthetic backup verification passed | Preserve these qualified small-case results without repeating evacuation or removal |
| Measured locally | The isolated timing probe passed 93 substituted tests, file-only checks, bundle verification, and transfer | Retain the preparation evidence; it does not qualify fresh-library media contents or live timing |
| Measured, supplied timing report | Media selection passed, then the media-content check stopped before addition | Preserve the stopped run; do not rerun it |
| Measured, supplied inventory | The new media directory held only directories, Finder state, and Music-created preference and localization files; no audio | Timing version 2 accepts only those observed entries |
| Measured, supplied timing version 2 report | Separate per-album additions produced strictly increasing album timestamps; Recently Added showed the expected `3,2,1` before and after relaunch; repeat safety and preservation passed | One small candidate-method success; adopting the method and excluding ties requires an explicit decision |
| Unknown | Established cause of the display mismatch, Music's tie-breaking rule, the candidate method at scale, after removal, and in the three artist-order cases | Qualify the method before supporting it |
| Measured locally | The separated-addition qualification probe passed 116 substituted tests, preparation of 324 synthetic files, file-only checks of all four cases, bundle verification, and transfer | Retain the preparation evidence; it does not qualify live behavior at scale, after removal, or in the artist-order cases |
| Unknown | Automatic GUI emptiness detection, independent physical backup qualification, and behavior on other supported system versions | Retain explicit qualification work before production use |

See the [version 2 results](reports/rebuild-feasibility-v2-results.md), [timestamp assessment](reports/rebuild-timestamp-gate.md), and [plan revision record](reports/display-order-plan-revision.md). Music's installed scripting dictionary declares `date added` read-only. The revised plan does not depend on changing that property or on quitting Music aligning timestamps.

## Required Sequence

1. Inventory every selected file and registration, verify a separate backup, and test restoration.
2. Evacuate the files to an explicitly selected staging directory outside Music's media folder. Downloads is not a required location.
3. Remove the inventoried Music registrations automatically, one persistent ID per call.
4. Confirm that all registrations and the GUI are empty, then quit Music and confirm termination.
5. While Music remains closed, apply the reviewed catalog, names, and optional file dates to working files.
6. Launch Music and add one album at a time in the selected order.
7. Verify files, registrations, and the intended Recently Added album order; record addition timestamps and their differences.

Use the existing four automatic orders, with ascending release date as the default. Playlists, ratings, play counts, and other library-only history are not restored. This workflow supports local files without cloud library synchronization. It must not change synchronization settings automatically.

## Display Order and Addition Dates

Recently Added must show the intended album sequence. Differences produced during verified album-by-album addition are acceptable; exact timestamp equality is no longer a gate. Record the exposed timestamps, distinct values, total span, per-album spans, elapsed time, and any interruptions. No numerical tolerance is inferred from the one-second small-case result, and no maximum duration or timestamp spread is claimed to be qualified before measurement. Missing or unreadable timestamps remain an incomplete diagnostic result.

The four existing orders describe **addition order**: `release` sorts by ascending release date; `artist` by ascending artist and album name; `artist-desc` reverses both names; and `artist-release` sorts by ascending artist and release date. Retain the existing deterministic tie rules and placement of undated albums. Save the exact album list with the plan, rather than recomputing a changed catalog during execution.

Show a separate, explicit **expected display order**, read from the first visible album through the last in Recently Added. The initial qualification target is reverse addition order: for example, add albums A, B, and C from oldest to newest and expect C, B, and A on screen. This is the intended outcome to test, not a claim about measured Music behavior. Do not silently reverse command semantics or accept whatever order Music produces as the expectation.

Qualification compares every expected album with the actual GUI, including albums requiring scrolling. Missing, duplicate, split, or out-of-order album cards prevent success. Check the result after the view has loaded and again after quitting and reopening Music. Under Decision 36, albums are added one at a time, and each album's exposed addition timestamps must be later than those of every earlier album; albums sharing an exposed second are outside supported behavior and stop a qualification run. Ties within one album are permitted. The ordering must not rely on an untested tie assumption. Verify all four selectable orders before claiming them as supported rebuilding modes.

The addition journal and timestamps do not prove GUI order. A recorded visual observation can qualify M10; it must identify the expected list, observed list, system version, and observation time. A product run must distinguish verified file/registration state from display confirmation. If reliable automatic observation is unavailable, it must report that display confirmation is pending and require a recorded user confirmation before reporting the whole rebuild verified. No interactive text user interface is planned.

If the intended display cannot be established or does not persist, stop the affected qualification and dependent release. A failed experiment is not repaired by automatically deleting and readding registrations. Do not edit Music's database, change the system clock, or rewrite or round timestamps to manufacture success.

## Remaining M10 Qualification

The [display-v3 assessment](reports/display-order-v3-results.md) records a completed negative small-case result. The media and bundle corrections passed their prerequisites, but both GUI observations differed from the planned order. Backup restoration, repeat safety, and final preservation passed. Retain all evidence and pause the remaining [display-v3 procedure](rebuild-display-validation.md); do not repeat the completed small case or its earlier removal sequence.

1. Investigate the display failure without changing the expected sequence or weakening the gate. Timestamp ties are a plausible explanation, not an established cause. The next recommended experiment is a new isolated synthetic comparison that separates album addition timestamps and records the actual boundaries, waiting time, timeout behavior, and GUI order before and after relaunch. The comparison is prepared in [the timing probe](reports/addition-timing-preparation.md); its [first run stopped before addition](reports/addition-timing-results.md) because the media guard refused Music-created scaffolding. The [corrected version 2](reports/timing-media-scaffolding.md) [passed the small case](reports/addition-timing-v2-results.md): separated album timestamps and the expected order before and after relaunch. This supports, but does not establish, timestamp ties as the earlier cause; any product policy remains unqualified.
2. Preserve the existing negative observation and successful preservation checks. A new method must demonstrate the required small-case order and repeat safety; a successful new case would not rewrite the old result. Excluding timestamp ties from supported behavior would require an explicit specification decision rather than silently dropping coverage.
3. After a candidate method succeeds, qualify the full sequence with 20 albums and 300 synthetic tracks. Compare every album card with the saved expectation, verify files and registrations, record timestamp differences, and check preservation and repeat safety. The scale case remains unrun; it is prepared with the three artist-order cases in the separated-addition qualification.
4. Cover all four order modes, deterministic ties, and empty-library detection. Keep API emptiness and human GUI emptiness distinct. Reliable automatic GUI confirmation remains a prerequisite for the fully automated clearing stage in M12.
5. Prepare and verify one reproducible procedure before asking for new separate-user operations. Produce one consolidated report distinguishing passed, failed, stopped, and unrun checks. A simulated detached disk-image backup qualifies only the synthetic experiment; independent physical backup and restoration remain M11 requirements.

M10 passes only when the small and scale evidence covers the revised preservation, sequence, display, and repeat-safety gates. A one-second timestamp difference alone is acceptable; the measured wrong order is not. M11–M15 implementation remains gated on M10. This assessment does not change the milestone scopes, gates, or authorization boundaries.

## Preservation and Recovery

Before registration removal, verify the bytes, relative paths, sizes, creation dates, and modification dates of the original files against a backup on a separate storage medium. A hard link is not a backup. Test restoration, then disconnect the backup medium. Insufficient capacity, missing files, unsupported registrations, ambiguous synchronization state, or an incomplete backup prevents removal.

Cross-volume evacuation retains its source until the replacement has been verified. Catalog edits affect working files only. Neither the backup nor recovery records are automatically deleted. These controls isolate a verified original from program and Music operations; they do not promise immunity to hardware failure or physical loss.

Remove only the persistent IDs captured in the verified plan. Stop if the inventory changes or an unexpected registration appears. An interrupted removal must not expand its scope. Recovery records distinguish evacuation, removal, confirmed termination, edits, and addition. Resuming addition must recheck preserved files, exact registrations, and intended display order. Record the interruption and resulting timestamp span; a larger span alone does not justify clearing or starting over. Successful file recovery alone does not establish a successful rebuild.

## Milestones and Gates

| Milestone | Scope | Completion Gate | Mac Requirement |
| --- | --- | --- | --- |
| M10 | Complete small and scale feasibility checks under the display-order requirement; qualify all four order modes | Verified preservation and required sequence, exact registrations, intended GUI order after relaunch, repeat safety, and recorded timestamp differences; no missing required observation | Maintainer's Mac in a separate test user; stop before live operations and provide the procedure |
| M11 / 0.2.0 | Independent backup verification, complete inventory, evacuation plans, strict catalog export, and versioned recovery records | Restore bytes, paths, and required dates from separate physical media; verify and disconnect the backup; reject incomplete inventories, overlap, unsupported values, insufficient capacity, and unsafe plans before mutation | Portable logic on Linux; dates, separate media, and restoration on macOS |
| M12 / 0.3.0 | Implement the qualified staged rebuilding sequence and explicit display confirmation | Separate-user end-to-end success, preserved originals, exactly one registration per file, correct file dates and GUI order; reliable empty-GUI detection before automatic quit, and no edits while Music runs | Maintainer's Mac in a separate test user; additional UI permissions, if needed, must be documented before testing |
| M13 / 0.4.0 | Interruptions during evacuation, removal, termination, editing, and addition; safe resumption and recovery | Fault tests preserve verified originals and exact scope; no duplicate registration or unverified source removal; resume only when files, registrations, and final display order can be verified, otherwise stop with recovery instructions | CI for portable state logic; macOS, storage-disconnection tests, and separate-user Music checks |
| M14 / 0.9.0 | Freeze features; qualify practical scale, system compatibility, installation routes, and documentation | Full synthetic workflow and restart checks pass on the declared supported environments; separately authorized private-copy checks complete; no unresolved major preservation, removal, registration, display-order, or recovery defect | Maintainer's Mac; private-copy access requires separate authorization; personal-library rebuilding remains separately restricted |
| M15 / 1.0.0 | Freeze CLI, catalog, and recovery-record compatibility; review and publish GitHub, npm, PyPI, and Homebrew artifacts | M10–M14 gates complete, final maintainer approval, clean artifact/privacy audit, successful CI, and installation checks through every published route | macOS for installation verification; explicit maintainer publication approval |

Version numbers are release targets, not publication authorizations. Each milestone depends on the preceding gate; do not publish 1.0.0 while the required display order or preservation remains unqualified.

Retain Apple silicon distribution. A macOS deployment target is not runtime qualification; qualify the stated minimum supported OS or revise the support declaration and package requirements before 1.0.0.

## Command and Compatibility Boundaries

The planned interface is `rebuild prepare`, `rebuild stage`, `rebuild clear`, `rebuild apply`, `rebuild add`, and `rebuild status`. Preparation inventories files and registrations, verifies backups, and records both addition and expected display lists. Staging evacuates files. Clearing removes only planned registrations and quits after registration and GUI emptiness are established. Application edits working files while Music is closed. Addition verifies the resulting library and records display confirmation separately. Status reports completed stages, timestamp differences, pending observations, failures, and the next required action. These are planned commands, not additions to the published interface.

Mutating stages require `--dry-run`, a complete preview, and post-operation verification. Plan changes require revalidation. Ordinary `add` retains its duplicate refusal and never removes registrations. Keep domain logic portable and platform operations in macOS targets; add no runtime package or external-tool dependency.

Retain `ilibrary-catalog-1`. Add `export --strict` before relying on an export as a complete rebuild inventory: missing tracks, numbering gaps, repeated numbers, and unrepresentable dates must prevent strict success. Do not invent months or days or silently close numbering gaps. Use a separate versioned recovery record rather than adding machine-specific paths and Music IDs to the public catalog format.

## Deferred Work

Network metadata candidates, multidisc flattening, cloud-synchronized rebuilding, and restoration of library-only history are outside 1.0.0. Developer ID signing and notarization are also deferred under the maintainer's no-additional-cost decision: Apple's [Developer Program](https://developer.apple.com/programs/) normally requires annual paid membership for [Developer ID](https://developer.apple.com/developer-id/). Preserve the distinction between existing ad hoc signing and Developer ID signing or notarization.

## Delivery and Handoff

Use milestone branches, atomic Conventional Commits, supported attribution trailers, and pull requests. Update Current Status at each checkpoint. Preserve historical reports. Before each approved push, present actual-file previews, section summaries, and Japanese translations. Future tags, releases, registry publication, and personal-library changes require explicit authorization; the 0.1.0 approvals do not extend to new releases.

M10 has not passed and product `rebuild` remains unimplemented. Display-v3 has supplied a completed negative small-case observation; its remaining cases are paused. The first bounded comparison stopped during its media-content prerequisite; a file-only inventory attributed the stop to Music-created scaffolding. The corrected version 2 small case passed. Decision 36 adopted separated per-album addition as the candidate method and excluded cross-album timestamp ties from supported behavior. The [separated-addition qualification](rebuild-qualification-validation.md) of the scale and three artist-order cases is [prepared](reports/separated-addition-qualification-preparation.md) and awaits the maintainer's separate-user run. Stop before separate-user operations and retain all earlier state. Personal-library operations and publication require separate authorization.

## Recommended Models and Effort

For M10 and the destructive-operation and recovery work in M12–M13, use Claude Opus 5.5 with xhigh in Claude Code or GPT-6-Astra with xhigh in Codex, following the existing M5 rationale. Use high for documentation and distribution checkpoints. Do not use ultra.
