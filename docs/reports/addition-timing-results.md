# Separated Addition Timing Results

## Evidence and Provenance

The maintainer supplied `ilibrary-m10-timing-report.txt` on October 17, 2026. It identifies probe source `1493bdaa36257c848730a6fcdaabca17d24f1068`, macOS 27.0.1, Music 1.7, and the isolated three-album, six-track `timing-small` plan. A byte-identical copy is retained under ignored `reference-private/m10-timing-results-2026-10-17/`. Its SHA-256 is `5db76008caa4b5796bd05063f3edaa0a0b345c90503851970373e36ca3c32181`.

This assessment reads the supplied report and the frozen probe source. It does not query Music, inspect the test user's media directory, or operate a personal library. Historical reports and the stopped bundle remain unchanged.

## Outcome

**The new experiment returned `STOP` in `empty-library` after 4.703 seconds. Addition-time separation and display order remain unmeasured.** The report explicitly passes the selected media directory check with the name `Media.localized`. It then reports that the new media directory contains existing files. This does not establish a wrong directory selection or a failure of the waiting method.

| Classification | Finding | Limit |
|---|---|---|
| Measured, supplied report | The selected media directory matched the new library | This check does not establish that its contents are empty |
| Inferred from frozen source and reported stop reason | The initial registration snapshot passed the exact empty-inventory check | The saved snapshot itself was not supplied; this is not a new GUI observation |
| Measured, supplied report | The media-content guard refused continued execution | The report does not identify the offending entry |
| Inferred from frozen source | A traversed entry passed the symbolic-link check but was neither a directory nor named `.DS_Store` | Its name, type, origin, and purpose remain unknown |
| Not reached | Working-copy preparation, backup restoration, Music termination, tag editing, album addition, waiting, timestamp boundaries, GUI observations, and repeat-safety checks | None can be counted as passed or failed by this report |

The probe's saved plan and result are diagnostic writes. According to the frozen control flow, this run stopped before any working-copy change or Music registration mutation. This is not a new comprehensive preservation measurement. The experiment has no registration-removal stage.

## Diagnostic Limitation

The media-content loop records a generic refusal without saving the rejected relative name or entry type. The existing private diagnostics contain the selected media path and registration snapshot, but that does not identify the rejected filesystem entry. The report cannot distinguish application-generated metadata from an actual media file. Neither explanation is established.

The earlier Finder correction concerns a regular `.DS_Store` in bundle inventory; it does not explain this different media-directory stop. This timing guard already permits a non-link entry named `.DS_Store`. No extension of its allowlist, deletion of a file, or retry is justified from the present evidence.

The earlier 93 substituted tests and file-only preparation checks remain valid within their recorded scope. They did not establish the full contents Music creates in a fresh library's media directory. The current stop exposes that remaining live prerequisite, not a contradiction of the offline results.

## Historical Comparison and Remaining Gates

The report's historical section repeats the completed display-v3 result; it is not a new measurement. The earlier expected order `3,2,1` differed from `2,3,1` before and after relaunch, with cross-album timestamp ties. That negative result remains unchanged. Whether ties caused the order, and whether separating additions corrects it, remain unknown.

M10 has not passed. The small timing method, scale, other orders, a production timing policy, automatic GUI emptiness detection, and independent physical backup retain their qualification requirements. M11–M15 implementation and product `rebuild` remain gated. No completion criterion or supported-behavior claim changes.

## Assessment Verification

The supplied report was copied and compared byte-for-byte after confirming ignore rules. The refusal was traced against the exact reported source and its inherited registration-capture routine. Twelve local diagnostic checks passed using temporary synthetic directories and substituted account information: classification, preservation, link refusal and non-traversal, source and scope guards, existing-output preservation, a depth limit, and a dry run without input reads or output creation. These qualify the documented file-only diagnostic, not a live timing run. The diagnostic was extracted from the documented source and copied with its checksum to the shared directory without overwriting existing files; both destination copies matched. Its SHA-256 is `ea35917b7dd4133bd728879aa23122da8071e45551c4a1bba50e7c33ab5bac47`.

## Next Evidence and Handoff

Pause the timing procedure and preserve the stopped bundle, results, media directory, and all earlier test libraries. The next evidence is a bounded, file-only inventory under the [Japanese diagnostic procedure](../rebuild-timing-diagnostics.md), run by the maintainer in the same test user. It reads saved run records and entry names, types, and sizes without querying Music, opening media contents, following symbolic links, or changing the library. It saves one new private JSON report exclusively and refuses an existing output. It measures current directory state, which must not be represented as a recovered snapshot of the stop.

Only after reviewing that evidence should a correction and a new reproducible live handoff be prepared. Do not rerun the stopped probe, remove its records, delete media entries, or change the expected GUI order. The assessment updates Current Status and the handoff locally; no push or publication is performed.
