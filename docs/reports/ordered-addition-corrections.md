# Ordered Addition Corrections

## Status

Subsequent findings, October 17, 2026. This report supplements the historical [Ordered Addition](ordered-addition.md) report. Five findings from the review of pull request #4 were confirmed by code inspection and reproduced with synthetic files and a substitute Music library. The maintainer authorized autonomous work through M7, with live Music operations restricted to a separate test user.

## Corrections

- Derived album and artist folders reject empty names, `.` and `..`; normalized destinations remain inside the Music folder. A journal is validated against the selected staging roots and expected destinations before it authorizes resumption.
- Cross-volume moves check capacity before the first write, copy through a hidden temporary file, compare file contents, and verify codec, decoded frame counts, and decoded PCM before removing the source. A failed verification retains the source. Same-volume moves retain the existing file through a rename.
- Resumption checks for matching tracks at other locations before moving any remaining file.
- Files belonging to a pending journal entry are excluded from the plan for new albums, so resumption does not process them twice.
- Confirmation of a resumed album requires distinct persistent IDs and the exact set of expected locations, in addition to the track count.

## Evidence and Limits

The complete synthetic suite passed 140 tests and the formatting check passed. The focused test run passed 17 tests on the maintainer's Mac (measured), including partial moves, duplicate locations, dot components, edited journal paths, capacity refusal, and retention of the original after verification failure. A synthetic Apple Lossless file was decoded before and after the cross-volume copy path, with equal PCM (measured); separate volumes were represented by an injected volume service, rather than a second physical volume.

The previous live probe measured Music behavior, not the implementation of `ilibrary add`. The M5 test-library gate remains pending until the combined M5/M6 live validation runs in a separate macOS user. No operation on the maintainer's Music library was performed.
