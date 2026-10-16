# Library Checks and Diagnostics

## Scope

Milestone M6 implements `check` and `doctor`. File analysis and comparison rules remain in the Foundation-only command target. Music's installed version, running state, Automation permission, and track records are obtained in `LibraryMac`. No package dependency was added.

## Evidence

- **Measured:** all 153 tests passed locally on macOS, including substitute-library cases for duplicate entries, stale album names and metadata, notable cloud statuses, missing or relocated files, corrupt metadata, and unreadable dates. The release build and strict formatting check passed. The public suite does not open Music.
- **Measured:** the locally installed public Music scripting dictionary exposes the additional fields used by the adapter: comment, track count, disc count, and compilation. A synthetic record verifies their parsing.
- **Measured:** `scripts/validation/library-commands.sh --prepare-only` generated three decodable synthetic tracks in two albums, applied names and dates, and passed file checks without querying Music.
- **Inferred:** a location-based snapshot permits comparison when Music caches an old album name. Substitute-library tests demonstrate the comparison rule, not the behavior of a running Music application.
- **Unknown:** the new commands have not been exercised against Music. The earlier [Music Behavior](music-behavior.md) probe records application behavior and is not an end-to-end qualification of these commands. Live cloud matching, artwork comparison, and actual Automation recovery remain unmeasured here.

## Diagnostic Boundaries

`check --library` compares thirteen exposed fields for every matching file track, including all duplicate records. It reports notable cloud states without claiming to prevent matching. Full release dates, copyright, and artwork are not compared with Music. Cloud-only entries not exposed as file tracks are outside the snapshot. File checks report errors and continue with readable inputs; they do not repair anything. File dates require macOS.

`doctor` reads application information, preferences, and existing permission state without launching Music or requesting permission. Missing permissions and folders have recovery instructions. Unknown state is explicitly distinguished from success. Its free-space threshold is diagnostic; mutating commands retain their own preflight calculations.

## Gate and Follow-Up

Artificial faults are detected in the public suite. The live M5 gate and confirmation of the M6 Music adapter remain pending. The [Test Library Validation](../test-library-validation.md) procedure prepares a separate macOS user and produces a sanitized result containing counts and statuses. It supports an empty test library or the five synthetic tracks from the earlier probe. It must not be run in the maintainer's personal user. No private files or Music library were accessed during this work.
