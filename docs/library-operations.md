# Library Operations and Recovery

## Before a Write

Keep a recoverable copy of the selected source files and an independent backup of the Music library. Begin with copies in a staging folder outside the Music media folder, and keep the staging folder, catalog, and artwork together until the run is complete.

1. Use `import --dry-run` to inspect conversions, copies, destinations, refusals, and capacity requirements. Omit `--delete-originals` while qualifying a workflow.
2. Export a catalog and keep its referenced covers alongside it. Review AI-generated values against evidence; unknown information should remain empty.
3. Run `validate CATALOG.json PATH...`, then `apply CATALOG.json PATH... --rename --timestamps --dry-run`. An unmatched file prevents application.
4. Apply only the reviewed plan and run `check PATH...`. A diagnostic is a reason to inspect the selected files, not an instruction to remove them.
5. Run `doctor`, then `add PATH... --order release --dry-run`. The latter reads Music even though it does not move or add files.

`import`, `export`, `apply`, `timestamps`, and `add` offer dry runs. A dry run describes the current state; it does not reserve space or prevent another process from changing files before execution. `timestamps --dry-run --script FILE` is an explicit output request: it writes the script while leaving file dates unchanged. To preview without creating any file, omit `--script`. `prompt` and `schema` print to standard output; a shell redirection can still create or replace a file.

## Ordered Addition

`add` selects M4A files, groups them by album artist and album, and uses one of four orders: `release`, `artist`, `artist-desc`, or `artist-release`. It stops when the library already contains a matching title in that album. Files move into Music's configured media folder before the album is added. Each destination and persistent ID must be confirmed before the next album begins.

Same-volume moves retain the file. Cross-volume moves use a temporary copy, compare bytes, decode and compare audio, and remove the selected source only after verification. Insufficient capacity or failed verification leaves the source in place. Empty source folders are retained. Sources not selected by the command are untouched.

Music may reorganize files when its properties change. iLibrary therefore writes tags and names before addition and does not change library track properties; see [Measured Music Behavior](#measured-music-behavior).

## Interrupted Addition

The first staging directory contains `.ilibrary-add.json`, which records source paths, destination paths, album state, and persistent IDs. Keep that directory and journal after an interruption, even if some or all audio files have moved.

1. Preserve the error output privately. Do not remove library entries, overwrite destinations, edit the journal, or move the remaining files to make the error disappear.
2. Correct an external problem such as unavailable storage or denied Automation permission.
3. Preview the same `add` command with the same paths and `--dry-run`.
4. If the plan is consistent, repeat without `--dry-run`. Resumption checks journal paths and duplicate tracks, moves any remaining files, and confirms every destination before proceeding.
5. If a destination and its source both exist, Music reports unexpected locations, or a duplicate prevents recovery, stop and inspect the copies. The command deliberately refuses ambiguous recovery instead of choosing which original or library entry to remove.

Addition is not an all-or-nothing transaction. Albums confirmed before a failure remain added. There is no automatic rollback or command to remove those entries. A failed cross-volume copy can leave an extra verified destination while retaining the source; preserve both until their roles are established.

## Rebuilding a Library

A rebuild replaces the registrations of an existing library with freshly added albums, so that the files carry the catalog's metadata and Recently Added shows the chosen order. Playlists, ratings, play counts, and other library history are not restored. iCloud Music Library is not supported: preparation refuses any registration whose cloud status is other than empty or `unknown`.

1. Make a backup of the media folder's files on a separate physical device, mirroring the relative paths below the source directory. iLibrary verifies that backup but never creates or changes it.
2. Run `rebuild prepare` with `--dry-run`, then without it. It verifies the backup, restores it into an empty test directory, asks you to eject the backup volume, and writes the recovery record. Keep the backup disconnected until the rebuild has been checked.
3. Quit Music and run `rebuild stage`, which moves the files to the staging directory. Then run `rebuild clear`, which removes the recorded registrations, confirms that Music reports no tracks, and quits Music.
4. Without opening Music, run `rebuild apply`, optionally with `--timestamps` for file dates. Then run `rebuild add`, optionally with `--timestamps` for folder dates, which adds the albums one at a time in the recorded order.
5. Open Music, check Recently Added and the albums, and run `check --library` on the media folder.

Run each stage with `--dry-run` first; `rebuild status` shows the completed stages and the next one. When a stage stops, keep the workspace, the staging directory, and the media folder as they are, correct the reported cause, and run the same stage again: it completes the operation that was in progress before continuing. Never edit or delete the recovery record or the journal. If a stage reports that the library or the files differ from the record, stop and restore the affected files from the backup rather than forcing the stage.

## Other Interrupted Operations

`apply` verifies each rewrite before replacement, but a later failure can leave earlier files changed. Validate the current files against the catalog and inspect a new dry run before retrying. Naming and timestamp operations also verify their own results; do not infer completion for the entire batch from one successful file.

`import` verifies outputs before moving them into place. A failed batch can leave earlier verified outputs, and existing outputs are refused on a new run. Keep the originals and inspect those outputs; use a fresh empty destination when repeating a complete import. With `--delete-originals`, originals are moved to the Trash only after all outputs are verified, but a later Trash failure may leave some originals in the Trash and others in place. Real Trash behavior has not yet been qualified.

`export` refuses existing output names and removes files it created when its own verification fails. `timestamps` refuses missing paths and symlinks rather than creating entries. Follow the command's error and retain backups; no command promises recovery from hardware failure or concurrent edits by another application.

## Comparing Music with Files

Use `check PATH...` for file checks and add `--library` only when access to that Music library is intended. The comparison matches file locations so that stale album names are still detected. Select complete album directories: a library track of the selected album outside those directories is reported.

`check` does not refresh or repair Music. A report that the file and library differ is not permission to delete a track or change properties. Its snapshot excludes cloud-only entries not exposed as file tracks and does not compare artwork, copyright, or full release dates. `unknown` cloud status is inconclusive; identifier removal has not been shown to prevent matching.

## Privacy and Reports

Command output may contain old and new metadata, paths, and library information. Catalogs, prompts, journals, and artwork can also contain private or copyrighted material. Do not attach them unreviewed to public issues or commits. Private reference material belongs under ignored `reference-private/`; machine-specific synthetic logs belong under ignored `artifacts/`.

For problem reports, describe a synthetic reproduction as explained in [CONTRIBUTING.md](../CONTRIBUTING.md#before-you-start). Removing purchase fields is not a comprehensive privacy audit of the file.

## Measured Music Behavior

The following behavior was measured with synthetic Apple Lossless albums in a separate macOS user that was not signed in to an Apple Account, with new libraries, on macOS 27.0.1 with Music 1.7. Behavior with iCloud Music Library, other Music settings, or other versions is unknown, and every cloud status observed was `unknown`.

Music adds a file that is already inside the media folder in place, at its existing path, without changing its modification or creation date; it copies a file from outside the media folder into `Music/Album Artist/Album/` and leaves the source. Adding a file that the library already holds returns the existing track and creates no duplicate. Persistent IDs survive quitting and relaunching Music. These observations are why `add` moves each album to its organized folder before adding it and confirms one track per file at each destination.

Setting track properties through Apple Events makes Music reorganize the media folder: setting `location` moved a file back to its organized path, and setting the album of each track moved all its files into a new folder and renamed a file whose title had changed. An earlier manual rename in a real library split an album and broke file references. Music also reread a changed title without `refresh`, while stale comments and composers were observed in another library, so when Music rereads a file is unknown. iLibrary therefore never sets track properties and reports file・library differences instead of assuming either behavior.

Music's `date added` property is read-only and exposed in whole seconds. When albums were added in quick succession, some of them shared an addition second, and Recently Added then showed an order other than the intended one, both before and after relaunch. When each album was added in its own request only after the previous album had been confirmed, the exposed addition seconds of each album were strictly later than those of every earlier album, and Recently Added showed the albums in the reverse of the addition order, as intended. That separated addition passed in cases of 20 albums with 300 tracks and of four albums in each of the `artist`, `artist-desc`, and `artist-release` orders. Music's rule for ordering albums that share an addition second is unknown, so iLibrary treats such a tie as a failure rather than a supported result.

Removing a registration was measured by deleting each track by persistent ID, one per request, after confirming that exactly one file track had that ID and that its title, album, and artist matched the record; 300 registrations were removed this way in about 167 seconds. A bulk read of the whole library in nine requests returned the same fields as the per-track read for the libraries compared, in about half a second for 300 tracks.
