# Rebuilding Probe Revision

## Scope and Evidence

On October 17, 2026, the maintainer confirmed that neither the empty-library prompt nor the Recently Added order prompt appeared in either initial run. This is consistent with the previously recorded stop before those stages. The maintainer subsequently authorized fresh synthetic measurements and requested a consolidated result to reduce repeated handoffs. Decision 32 records that scope; the personal library remains excluded.

The [initial results](rebuild-feasibility-results.md) remain unchanged. They establish initial addition followed by an unresolved location mismatch, not failure of the requested addition-timestamp or display-order conditions. Version 2 is prepared on `codex/m10-rebuild-feasibility`, with executable probe sources and its Japanese procedure fixed at `9fe4a53`. It is not a product `rebuild` implementation.

## Retrieval and Diagnostic Changes

The probe now retrieves each location with explicit `get`, matching the form already used by the product Music adapter. It also records the previous retrieval form and numerical errors from both forms. This is a reasoned correction based on the different source expressions (inferred); it does not establish the cause of the original mismatch or prove that a new live run will pass.

Raw replies are retained privately before parsing. Parsed initial and final registrations are saved before their inventory checks. Each comparison records its expected locations and a sanitized classification: exact, representation-only, empty, read error, or different. Representation-only differences remain refused by the exact path guard; they are classified for diagnosis, not accepted as equivalent. A retrieval error also prevents acceptance.

The result identifies the active phase and records a stopping reason, including a keyboard interruption. The command wrapper preserves trailing field separators so that an empty final error field does not corrupt a record. Repetition checks compare actual registration state, including addition timestamps, while excluding auxiliary diagnostic fields. Removal still uses the captured IDs one at a time and retains every existing backup, inventory, and file-preservation check.

The new `report` helper combines both saved case results without querying Music. An unrun case is explicitly marked `NOT RUN`. Raw paths and IDs stay in the case's private records; the combined report contains counts, classifications, phases, and conclusions.

## Local Verification

All twenty-eight synthetic probe tests passed (measured). New coverage includes trailing separators, both retrieval forms, preservation before parsing and inventory failures, refusal despite representational similarity or retrieval errors, timestamp-sensitive repetition, a recorded initial stop before backup or removal, combined reporting, and keyboard interruption. Tests substitute Music calls and do not establish live behavior.

The release build and preparation of 306 generated files passed (measured). The build emitted warnings for absent Command Line Tools search directories but completed successfully. Both catalogs validated against all corresponding generated files. The ZIP passed CRC and manifest-hash checks and retained its executable permission. The bundle identifies probe version 2 and uses the separate name `ilibrary-m10-v2`; earlier bundles were not overwritten. The actual combined-report command correctly reported both cases as unrun.

An additional offline exercise used disposable generated-file copies for both cases, set their release dates, created a read-only disk image, restored its contents, compared every selected file's bytes and creation and modification dates, detached the image, and verified unchanged source copies. All six small-case and 300 scale-case files passed (measured). The prepared bundle's hashes remained unchanged. No Music call occurred. This confirms the backup helper on synthetic files on this Mac; same-disk images remain insufficient evidence for independent physical backup qualification.

## Maintainer Procedure and Remaining Gates

The revised [Japanese procedure](../rebuild-feasibility-validation.md) uses new `M10-v2-small` and `M10-v2-scale` libraries with separate media folders. It specifies transfer checks, exact commands, the conditions for each prompt, the distinction between a completed `FAIL` and an early `STOP`, and one combined report. The initial libraries and all earlier results remain preserved. A safety stop prevents continuing to the scale case; the report records that case as unrun.

The agent stops before separate-user Music execution. Live location retrieval, evacuation and removal behavior, empty-GUI confirmation, termination, edits while closed, readdition, exact timestamp equality, and display order remain unverified for version 2. They must be assessed from the new result rather than inferred from preparation. No CI run, push, merge, release, or personal-library operation occurred at this checkpoint. Unexpected behavior can still require follow-up; a single report is an intended handoff, not a guaranteed successful measurement.
