# Library Operations and Recovery

## Before a Write

Keep a recoverable copy of selected source files and an independent backup of the Music library. Start with synthetic files or copies in staging, outside the Music media folder. The implemented Music commands passed [separate-user validation](reports/library-command-validation.md), and the approved [personal-file copy qualification](reports/library-qualification.md) completed without findings. Those measurements do not authorize access to another library. Use the [separate-user procedure](test-library-validation.md) before adopting the workflow.

1. Use `import --dry-run` to inspect conversions, copies, destinations, refusals, and capacity requirements. Omit `--delete-originals` while qualifying a workflow.
2. Export a catalog and keep its referenced covers alongside it. Review AI-generated values against evidence; unknown information should remain empty.
3. Run `validate CATALOG.json PATH...`, then `apply CATALOG.json PATH... --rename --timestamps --dry-run`. An unmatched file prevents application.
4. Apply only the reviewed plan and run `check PATH...`. A diagnostic is a reason to inspect the selected files, not an instruction to remove them.
5. In the separate test user, run `doctor`, then `add PATH... --order release --dry-run`. The latter reads Music even though it does not move or add files.

`import`, `export`, `apply`, `timestamps`, and `add` offer dry runs. A dry run describes the current state; it does not reserve space or prevent another process from changing files before execution. `timestamps --dry-run --script FILE` is an explicit output request: it writes the script while leaving file dates unchanged. To preview without creating any file, omit `--script`. `prompt` and `schema` print to standard output; a shell redirection can still create or replace a file.

## Ordered Addition

`add` selects M4A files, groups them by album artist and album, and uses one of four orders: `release`, `artist`, `artist-desc`, or `artist-release`. It stops when the library already contains a matching title in that album. Files move into Music's configured media folder before the album is added. Each destination and persistent ID must be confirmed before the next album begins.

Same-volume moves retain the file. Cross-volume moves use a temporary copy, compare bytes, decode and compare audio, and remove the selected source only after verification. Insufficient capacity or failed verification leaves the source in place. Empty source folders are retained. Sources not selected by the command are untouched.

Music may reorganize files when its properties change. iLibrary therefore writes tags and names before addition and does not change library track properties. Earlier application behavior was measured in [Music Behavior](reports/music-behavior.md); this does not establish all future behavior or cloud effects.

## Interrupted Addition

The first staging directory contains `.ilibrary-add.json`, which records source paths, destination paths, album state, and persistent IDs. Keep that directory and journal after an interruption, even if some or all audio files have moved.

1. Preserve the error output privately. Do not remove library entries, overwrite destinations, edit the journal, or move the remaining files to make the error disappear.
2. Correct an external problem such as unavailable storage or denied Automation permission.
3. Preview the same `add` command with the same paths and `--dry-run`.
4. If the plan is consistent, repeat without `--dry-run`. Resumption checks journal paths and duplicate tracks, moves any remaining files, and confirms every destination before proceeding.
5. If a destination and its source both exist, Music reports unexpected locations, or a duplicate prevents recovery, stop and inspect the copies. The command deliberately refuses ambiguous recovery instead of choosing which original or library entry to remove.

Addition is not an all-or-nothing transaction. Albums confirmed before a failure remain added. There is no automatic rollback or command to remove those entries. A failed cross-volume copy can leave an extra verified destination while retaining the source; preserve both until their roles are established.

## Other Interrupted Operations

`apply` verifies each rewrite before replacement, but a later failure can leave earlier files changed. Validate the current files against the catalog and inspect a new dry run before retrying. Naming and timestamp operations also verify their own results; do not infer completion for the entire batch from one successful file.

`import` verifies outputs before moving them into place. A failed batch can leave earlier verified outputs, and existing outputs are refused on a new run. Keep the originals and inspect those outputs; use a fresh empty destination when repeating a complete import. With `--delete-originals`, originals are moved to the Trash only after all outputs are verified, but a later Trash failure may leave some originals in the Trash and others in place. Real Trash behavior has not yet been qualified.

`export` refuses existing output names and removes files it created when its own verification fails. `timestamps` refuses missing paths and symlinks rather than creating entries. Follow the command's error and retain backups; no command promises recovery from hardware failure or concurrent edits by another application.

## Comparing Music with Files

Use `check PATH...` for file checks and add `--library` only when access to that Music library is intended. The comparison matches file locations so that stale album names are still detected. Select complete album directories: a library track of the selected album outside those directories is reported.

`check` does not refresh or repair Music. A report that the file and library differ is not permission to delete a track or change properties. Its snapshot excludes cloud-only entries not exposed as file tracks and does not compare artwork, copyright, or full release dates. `unknown` cloud status is inconclusive; identifier removal has not been shown to prevent matching.

## Privacy and Reports

Command output may contain old and new metadata, paths, and library information. Catalogs, prompts, journals, and artwork can also contain private or copyrighted material. Do not attach them unreviewed to public issues or commits. Private reference material belongs under ignored `reference-private/`; machine-specific synthetic logs belong under ignored `artifacts/`.

For separate-user validation, share only the generated `ilibrary-command-results.txt`, whose contents are counts and statuses. For other problems, follow [SUPPORT.md](../SUPPORT.md) and describe a synthetic reproduction. Removing purchase fields is not a comprehensive privacy audit of the file.
