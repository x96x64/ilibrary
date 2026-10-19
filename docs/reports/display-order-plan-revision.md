# Display-Order Plan Revision

## Decision and Scope

On October 17, 2026, the maintainer accepted differences in addition timestamps when Recently Added displays the intended album order and requested a revised plan through 1.0.0. This decision supersedes the exact-equality portion of Decision 29. It authorizes planning only, not implementation, Music operations, personal-library access, a new experiment, or publication. The active specification is the [Plan for the Stable Release](../stable-release-plan.md).

## Evidence and Remaining Uncertainty

**Measured, supplied numeric evidence:** the six saved timestamps from the version 2 small case contain two distinct values separated by one second. Two tracks have the earlier value and four the later value. The [historical timestamp assessment](rebuild-timestamp-gate.md) correctly records failure under the former requirement and remains unchanged.

**Measured, maintainer-reported:** the [version 2 experiment](rebuild-feasibility-v2-results.md) completed guarded evacuation and removal, human-confirmed GUI emptiness, termination, editing while closed, and ordered readdition with file/library verification. Its backup was a storage simulation, not a separate physical medium.

**Unknown:** actual Recently Added order, order persistence after relaunch, repeated-addition stability, final backup verification, and the 300-track scale result. Automatic GUI emptiness detection and independent physical backup qualification also remain unverified. No evidence establishes that reverse addition order is the actual display order in these runs.

**Inferred:** accepting timestamp variation removes the known equality blocker but cannot establish the missing display or preservation gates. M10 therefore remains incomplete.

## Revised Gates and Milestone Dependencies

The intended display list and the addition list must be recorded separately before an experiment. The initial target is reverse addition order, preserving the four existing command ordering modes. Qualification must compare all displayed albums, include timestamp ties and non-ties, and check persistence after relaunch. A journal alone is insufficient. A missing display observation remains unverified, and a mismatch fails the affected gate.

Addition timestamps become diagnostic evidence. Record their range and the execution history without inventing a tolerance from the small sample. The plan does not change Music's database or clock, edit read-only dates, or retry deletion automatically after a display failure. File creation and modification dates retain their separate catalog-driven checks.

M10 completes the missing synthetic feasibility evidence. M11 qualifies independent preservation and preflight. M12 implements the ordered rebuilding sequence, including reliable empty-GUI detection and explicit final display confirmation. M13 qualifies interruptions and resumption against preservation and display order. M14 qualifies scale, compatibility, and distribution. M15 requires all preceding gates and separate approval for 1.0.0 publication. The active plan supplies each stage's scope, gate, and Mac requirement.

## Preservation and Handoff Boundary

The required sequence remains backup verification, evacuation, exact registration removal, empty-GUI confirmation and termination, editing while Music is closed, album-by-album addition, and final verification. A verified backup on separate physical media must be restored in a test and disconnected before production registration removal. Working files, recovery records, and backups are not automatically discarded. Ordinary `add` never removes registrations.

This checkpoint updates the active plan, Current Status, handoff, and notices on superseded procedures. Historical reports and the transferred experiment remain unchanged. No executable code or Music state is changed. The next authorized activity must be established by a new maintainer instruction; any subsequent separate-user operation requires a prepared Japanese procedure and a stop immediately before that operation.
