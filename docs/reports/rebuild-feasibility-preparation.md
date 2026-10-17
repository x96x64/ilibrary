# Rebuilding Feasibility Preparation

## Scope and Authorization

This M10 preparation record, dated October 17, 2026, implements the maintainer's instruction to prepare the revised plan and stop before separate-user Music operations. It does not implement a product `rebuild` command. No personal Music library was opened, queried, or modified during preparation.

The [stable-release plan](../stable-release-plan.md) requires verified backup, evacuation, automatic removal, empty-library and GUI confirmation, termination, editing, and album-by-album addition. Exact addition-timestamp equality and the intended Recently Added display are independent acceptance conditions. Failure or unavailable evidence blocks subsequent rebuilding implementation.

## Prepared Experiment

The Python probe prepares deterministic synthetic media in two cases: three albums of two tracks and twenty albums of fifteen tracks. It uses the existing release executable for imports, tagging, ordered addition, and checks; the exploratory tag writer only seeds generated inputs. No new package dependency is introduced.

Live execution requires a separate test-user name, explicit confirmation of no Apple Account or cloud synchronization, an initially empty library, a media folder inside that user's Music directory, an intact bundle, and a previously unused result directory. It records only newly added persistent IDs and removes one per call. Before each removal it rechecks the exact remaining inventory, the evacuated files, and the detached backup image. Unexpected registrations, locations, file changes, or backup changes stop further removal. A failure never triggers a second deletion attempt or an automatic rollback.

For synthetic inputs only, a read-only disk image simulates disconnected storage. The live procedure restores and compares its files before detaching it. It is not independent physical storage and does not qualify the future production backup gate. Original generated files also remain in the transfer bundle. The experiment intentionally leaves results and final registrations for inspection.

The maintainer observes GUI emptiness and Recently Added order. Those observations are reported separately from script measurements; automatic GUI detection is not implemented. The probe obtains the read-only `date added` property and compares the full returned second-resolution values. Equality of only the calendar date is not accepted. No clock adjustment or Music database modification is attempted.

## Local Verification

Eighteen synthetic guard tests passed (measured). They cover refusal of ordinary and root users, path links, dry-run non-mutation, exact timestamp classification, changed identities and locations, unexpected registrations, missing evacuated files, changed or mounted backups, per-ID deletion scope, and a simulated deletion that unexpectedly modifies a file. Music calls are substituted; these are not live Music measurements. Both CI jobs are configured to run the same tests, but this branch has not been pushed and its CI has not run.

Preparation of the transfer bundle, static checks, and documentation checks must be recorded after they finish. These checks do not qualify actual registration removal or timestamp behavior.

## Remaining Gates

Both live cases remain unperformed. Actual AppleScript execution, restoration from the detached image, file behavior during registration removal, GUI emptiness, post-termination edits, exact addition timestamps, and Recently Added order remain unverified. Follow the [Japanese procedure](../rebuild-feasibility-validation.md) and report only the generated result summaries. An incomplete case is not a pass. The maintainer must decide any relaxation of the exact timestamp or ordering requirement; the implementation must not decide it implicitly.

Future production qualification must additionally establish independent physical backups, automatic empty-state handling, all approved platform versions, and interruption behavior. The experiment's same-volume synthetic evacuation does not qualify cross-volume real-library rebuilding.

## Documentation Illustration

The maintainer separately requested the README example from the selected Bad recording. Its public descriptive tags yielded the title and album Bad, composer Michael Jackson, date 1987-08-31, and copyright ℗ 1987 MJJ Productions, Inc. (measured). The original file's bytes, creation date, and modification date remained unchanged. The remastered alias is an illustration, not a measured tag. Other maintained READMEs contain no equivalent example. Detailed measurements remain under ignored `reference-private/`; no recording, artwork, personal path, or purchase field is included in this report.
