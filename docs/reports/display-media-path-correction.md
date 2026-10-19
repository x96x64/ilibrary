# Display-Probe Media-Path Correction

## Supplied Evidence and Direct Cause

On October 17, 2026, the maintainer supplied the diagnostic log from the stopped `small-existing` run at `3b7e2fe`. A byte-identical copy is retained under ignored `reference-private/m10-display-results-2026-10-17/`; its SHA-256 is `92d93d2e7f05be274bd427c960358038ace2d2422fbf701558c79c70245fe46d`. The log contains two successful commands: the macOS version read and the Music media-folder preference read. It contains no Music scripting command.

**Measured, supplied log:** the parsed preference path ends in `Music/M10-v2-small/Media.localized`. The probe required `Music/M10-v2-small/Media`. The planned library parent agrees; the final component differs. The returned URL is a local file URL, and the discrepancy is not surrounding whitespace or letter case. Personal path prefixes remain private.

**Confirmed by source inspection and local reproduction:** the fixed `Media` comparison rejects this `Media.localized` path before any Music scripting or existing-small validation. This identifies the direct cause of the reported stop. The probe failed to support the recorded media-directory name; this is not evidence that the maintainer selected the wrong library or failed to set the requested folder. The earlier [assessment](display-order-results.md) remains a historical record of the uncertainty before the diagnostic log was supplied.

## Bounded Correction

Commit `97d4c0bdf049fb2f5d4191a26f4bb6dfaa760375` changes only the validation probe, its tests, preparation script, and Japanese procedure. Selection still requires the exact planned library parent in the test user's Music directory. Only the two final names `Media` and `Media.localized` are accepted. The existing checks for an existing directory, test-user containment, and absence of symbolic links remain in place.

The selected path is retained for the entire run. A later preference change, including a switch between the two accepted names, still stops the run. The code does not strip `.localized` from file paths or substitute a different directory. Existing-small inventories, persistent IDs, saved paths, file comparisons, backup checks, and guards around registration removal remain unchanged. Detailed observed and expected path values are retained only in the private diagnostic log; successful public output includes only the accepted final name.

No product command or Swift source was changed. The correction does not qualify display order, authorize personal-library operations, or remove the M10 gate.

## Local Verification

**Measured:** all sixty-seven synthetic probe tests passed, including six added regression tests. The new coverage passes synthetic `file:` preference values through the actual URL and directory parsing helper with substituted command output. It accepts both exact media names and rejects an unrelated library, a nested or similarly named directory, a missing directory, and a symbolic link. A mid-run switch between accepted names remains a refusal.

Complete substituted runs cover existing-small reuse and all four fresh ordering modes with `Media.localized`, including the 300-track case. Existing-small reuse preserves the prior records and performs no new addition or removal. Music and native backup operations are substituted; these are not live Music measurements.

**Measured:** the release build completed, 324 synthetic files and eight catalogs were prepared and validated, the bundle manifest and ZIP entries matched, ZIP CRC and executable permission checks passed, and the new report correctly lists all five cases as unrun. The bundled sources and procedure match the committed files. Earlier live evidence and the original display archive remain unchanged. No new PCM reference measurement or live display observation is claimed.

## Replacement Bundle and Handoff

The corrected bundle uses the distinct name `ilibrary-m10-display-v2`, source commit `97d4c0b`, and archive SHA-256 `9676a7cea84544ebe37ce2b0c071ece781c8cbffffdd95a54c5a9116a3c49290`. Its ZIP and checksum were transferred to the shared directory without overwriting existing files, and both copies matched. The earlier display archive retains SHA-256 `e27697fff4c3cd8af28f0d28d5cab5adf044a78d8b82aba208e8e22f9c1cbe8a`.

The [Japanese procedure](../rebuild-display-validation.md) extracts the corrected bundle into a new directory and returns a separately named combined report. The old `ilibrary-m10-display` bundle, its preflight-stop records, and the older `ilibrary-m10-v2` experiment remain intact. The replacement begins with a new preflight and exact validation of the old small case; it does not resume an interrupted removal. No registration or music-file mutation was reached in the prior display attempt, and small reuse itself repeats neither evacuation nor removal.

Do not rename or recreate `Media.localized` to satisfy the old check, and do not run the old display bundle again. The four fresh cases still require their own initially empty synthetic libraries. The agent stops before test-user operations. The next evidence is the maintainer's single `ilibrary-m10-display-v2-report.txt`, produced according to the bundled procedure even if a case stops.

## Remaining Qualification

M10 remains incomplete. Actual Recently Added order, persistence after relaunch, repeat safety, final backup preservation, and the new scale and artist-order measurements remain unverified. The earlier one-second timestamp difference remains acceptable by itself under Decision 33. Human GUI confirmation and a same-disk backup simulation do not qualify automatic GUI detection or independent physical backup protection.

This correction and handoff preparation did not query Music or access a personal library. No push, publication, or implementation of M11 or product rebuilding occurred.
