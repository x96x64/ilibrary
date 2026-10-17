# Rebuilding Timestamp Gate Assessment

## Evidence and Calculation

On October 17, 2026, the maintainer supplied the read-only saved-date supplement for the version 2 small case at source commit `9fe4a53f8ef5aa78cb6245f48360ad5044cf780e`. It reports six saved timestamps, two distinct values, a span of one second, and `timestamp equality: FAIL`. The preceding [version 2 assessment](rebuild-feasibility-v2-results.md) records macOS 27.0.1 and the successful steps before timestamp aggregation stopped.

The result excerpt was transcribed without terminal identity or session history into ignored `reference-private/`. Its SHA-256 is `584114d45457ba0a583a7cd8d58d8052fb560e94e990ffda1972fe8b4b17ed8b`. This is maintainer-supplied evidence, not an independent read of the original snapshot. Exact local calculation with the corrected parser confirms the reported counts and span (measured).

| Offset from the Earliest Saved Timestamp | Tracks |
| --- | --- |
| 0 seconds | 2 |
| 1 second | 4 |

Every supplied value uses exponent notation and causes the former direct `int` conversion to raise `ValueError` (measured local reproduction on the supplied strings). This confirms that the old parser could not process the reported input. Correcting that parser exposes a real difference between the saved timestamps; it does not make them equal. The transcript does not associate values with album identities, so no per-album timestamp assignment is inferred.

## Gate Assessment

The small case does not satisfy the approved requirement that every track have exactly the same addition timestamp at Music's exposed precision. The supplied evidence is now a measured timestamp mismatch rather than an unclassified parser stop. M10 has not passed, and the dependent M11–M15 implementation and release progression remain gated under the current plan.

The earlier successful observations remain valid within the six-track synthetic run: backup restoration and detachment, evacuation preserving bytes and file dates, removal of the inventoried registrations without changing evacuated files, human confirmation of the empty GUI, termination, catalog application while closed, and ordered readdition with file/library verification. Those successes do not override the timestamp requirement.

Recently Added display order, unchanged registrations on repeated addition, the final backup check, and the scale run remain unverified. Automatic GUI detection and independent physical backup qualification also remain outside the evidence. A difference in registration timestamps is not evidence of lost audio or altered release-date file timestamps.

## Interpretation and Limits

Quitting Music after the empty-library confirmation, editing while closed, and readding albums sequentially did not produce identical timestamps in this run. The record therefore does not support a guarantee that this tested sequence aligns all addition timestamps. It does not prove that every possible supported workflow is incapable of doing so, nor that the intended Recently Added order is wrong.

The installed scripting interface's read-only addition-date property was recorded in the approved plan. This checkpoint does not change that interface or authorize database editing, clock changes, timestamp rounding, or acceptance of a one-second tolerance. Any change to the equality requirement must be decided by the maintainer and recorded before implementation resumes.

## Next Decision and Stop Boundary

Preserve the existing test libraries, files, backup image, bundle, and evidence. Do not rerun small, start scale, repeat the saved-date extraction, or remove registrations merely to seek a passing timestamp result. No further Mac operation is needed to interpret the supplied evidence.

The next task is a maintainer decision between retaining exact timestamp equality and keeping the dependent rebuilding work on hold, or requesting a revised proposal that prioritizes the desired display order and explicitly defines acceptable timestamp differences. The latter would still need separate qualification; it is not an approved gate change or a claim that the display-order condition will pass. No choice has been made at this checkpoint.

Only documentation and an exact calculation on supplied numeric strings changed. No Music query, personal-library access, new live run, product change, push, or publication occurred. Existing historical reports and the transferred version 2 archive are preserved.
