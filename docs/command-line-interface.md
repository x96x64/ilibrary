# Command-Line Interface

## Status

`ilibrary` is a command-based interface with verb subcommands. This reference describes the commands of this source tree. Begin with copies and keep independent backups of the Music library before running a command that changes it.

## Synopsis

```
ilibrary import SOURCE... -o DIR [--from mora|itunes|auto] [--delete-originals] [--dry-run]
ilibrary add PATH... [--order release|artist|artist-desc|artist-release] [--dry-run]
ilibrary rebuild prepare CATALOG.json SOURCE --workspace DIR --backup DIR --restore-test DIR --staging DIR
                         [--order release|artist|artist-desc|artist-release] [--confirm-separate-device]
                         [--disconnect-timeout SECONDS] [--dry-run]
ilibrary rebuild stage --workspace DIR [--dry-run]
ilibrary rebuild clear --workspace DIR [--dry-run]
ilibrary rebuild apply --workspace DIR [--timestamps] [--dry-run]
ilibrary rebuild add --workspace DIR [--timestamps] [--dry-run]
ilibrary rebuild status --workspace DIR
ilibrary export PATH... -o CATALOG.json [--artwork DIR] [--strict] [--dry-run]
ilibrary prompt CATALOG.json
ilibrary schema
ilibrary validate CATALOG.json [PATH...]
ilibrary apply CATALOG.json PATH... [--dry-run] [--rename] [--timestamps]
ilibrary timestamps CATALOG.json PATH... [--dry-run] [--script FILE]
ilibrary check [PATH...] [--library]
ilibrary doctor
ilibrary help [COMMAND] | --help | --version
```

`ilibrary help COMMAND` and `ilibrary COMMAND --help` print the options of a command; `ilibrary help rebuild`, `ilibrary rebuild --help`, and `ilibrary rebuild prepare --help` print the group and subcommand help. Options take their value as the next argument or after `=`, as in `--output=catalog.json`; `--` ends the options.

## Exit Status

| Status | Meaning |
| --- | --- |
| 0 | Success |
| 1 | A runtime failure, an invalid catalog, a refusal, a problem reported by `check` or `doctor`, a step of `rebuild prepare` that did not pass, a `rebuild` stage that refused or stopped, or a missing or invalid recovery record or journal reported by `rebuild status` |
| 2 | A usage error: an unknown command or option, or a missing argument |

Reports are written to standard output, and errors and warnings to standard error with the prefixes `ilibrary: error:` and `ilibrary: warning:`.

## Files

Paths may be files or directories. Directories are searched recursively for `.m4a` files; hidden entries are skipped. Symbolic links are never followed: a link to an audio file or a directory is refused. Protected `.m4p` files are refused. A path that does not exist ends the command with status 1 and is never created.

## Commands

### import

```bash
ilibrary import ~/Downloads/mora -o ~/Music/Staging --dry-run
ilibrary import ~/Downloads/mora -o ~/Music/Staging --delete-originals
```

Converts lossless downloads to Apple Lossless and copies iTunes Store files without re-encoding, into a staging folder.

- **Conversion.** FLAC, WAV, and AIFF files are converted through AudioToolbox at their own bit depth and sample rate. Each output is verified against its source by equal decoded PCM digests and frame counts, by declared against decoded lengths, and, for WAV and AIFF, by the length of the sample chunk (decision 7). Floating-point PCM, more than two channels, and incomplete files are refused. Conversion requires macOS.
- **FLAC tags.** The standard fields TITLE, ARTIST, ALBUMARTIST (or ALBUM ARTIST), ALBUM, GENRE, COMPOSER, COPYRIGHT, DATE, TRACKNUMBER with TRACKTOTAL, and DISCNUMBER with DISCTOTAL are carried, with several values of one field joined by `, `; a complete DATE is written as `YYYY-MM-DDT00:00:00Z`, and a year alone is kept as written. The front cover (picture type 3) is carried when it is a JPEG or PNG image. Track and disc numbers outside the range that MP4 stores (1 to 65535) are not carried and are reported by field name. COMMENT, ORGANIZATION, PERFORMER, and other recognized fields are not carried, and are named in the report; fields outside the standard set are dropped and only counted, because their names may identify a purchase.
- **Copies.** M4A files are copied without re-encoding, and purchase metadata is removed as by MP4Core (decisions 10 and 12). The copy's media data and sample tables are compared with the source. Encrypted sample entries and `.m4p` files are refused.
- **Output paths.** The files under a `SOURCE` directory keep their paths relative to that directory under `DIR`; a `SOURCE` file is placed directly in `DIR`. The extension becomes `.m4a`. Music-style names are applied later with `apply --rename`.

Sources may not lie within one another; each file is selected through exactly one `SOURCE`. `--from` selects what is imported: `mora` imports FLAC files, `itunes` imports M4A files, and `auto`, the default, imports both and WAV and AIFF. Other files, such as WAV files under `--from mora`, are left untouched and counted.

Every file is planned and checked before anything is written. Nothing is changed when any file is refused, when two sources would produce the same output, when an output exists, when an existing folder on the way to an output is a file or a symbolic link, when `DIR` lies inside a `SOURCE` directory, or when the volume of `DIR` lacks room for all outputs, including carried covers, plus one further copy of the largest output for writing tags (decision 8). Each output is written under a hidden temporary name beside its destination, verified, and only then moved into place; a failure removes the temporary file and stops the import, and outputs completed before it remain.

- `-o`, `--output DIR` names the staging folder. It is created if it does not exist, provided that its parent exists.
- `--dry-run` lists every planned conversion and copy and changes nothing.
- `--delete-originals` moves the originals to the Trash after every output has been verified, and only if the whole import succeeded. Originals are never deleted permanently.

### add

```bash
ilibrary add ~/Music/Staging --order release --dry-run
ilibrary add ~/Music/Staging --order release
```

Adds the albums in the staging folders to Music, one album at a time. Music must be able to be controlled from the Terminal, which macOS asks to allow the first time.

1. The `.m4a` files are grouped into albums by their album and album artist tags; a file without either is refused.
2. The albums are ordered: `release` (the default) by release date, `artist` by album artist and then album name, `artist-desc` by both in descending order, and `artist-release` by album artist and then release date.
3. For each album in turn, the library is searched for a track with the same album artist, album, and title. If one exists, the run stops before this album.
4. The album's files are moved into the media folder named by Music's preferences, to `Music/Album Artist/Album/` with their names unchanged, and added there in one call. Music adds files inside the media folder in place (measured; see [Measured Music Behavior](library-operations.md#measured-music-behavior)).
5. Music must report one new track per file, each at the place of its file, before the next album begins. Otherwise the run stops and reports the album as not confirmed.
6. Each album after the first is added only once the clock has passed the latest addition second of the album before it, and Music must report addition seconds for it that are all later. Otherwise the run stops after that album, because Recently Added might not show the intended order: Music exposes the date added in whole seconds, and its order for albums that share a second is unknown. Later runs with the same staging folder check that boundary again and refuse to continue past it; move the albums that remain to a new staging folder to add them in a new run.

Nothing is moved when any file is refused, a destination already exists, or a folder on the way is a file or a symbolic link. A staging folder may not overlap the media folder. Track properties are never set in Music, because Music then moves and renames files. Files are expected to carry Music's names already, as `apply --rename` gives them; other names are reported, because Music may rename such files later.

Folder names `.` and `..` are refused. Cross-volume moves check available space and verify the copied bytes, codec, decoded duration, and PCM before removing the selected source. Failed verification retains the source.

Progress is recorded in `.ilibrary-add.json` in the first staging folder, with the persistent ID of every added track. When a run stops after moving an album but before Music confirmed it, the next run completes that album first: it moves any file left behind, recognizes tracks already added, and otherwise adds the files. Resumption repeats duplicate checks, validates journal paths, and requires every destination and persistent ID to be distinct before continuing.

- `--order ORDER` selects the order.
- `--dry-run` lists the order, every move, and any track that would stop the run, and changes nothing. It reads the library.

### rebuild

```bash
ilibrary rebuild prepare catalog.json ~/Music/Media.localized/Music --workspace ~/ilibrary-work \
    --backup /Volumes/Backup/Music --restore-test ~/ilibrary-restore --staging ~/ilibrary-staging \
    --confirm-separate-device --dry-run
ilibrary rebuild stage --workspace ~/ilibrary-work --dry-run
ilibrary rebuild status --workspace ~/ilibrary-work
```

The `rebuild` group rebuilds an existing Music library from its files so that it matches a catalog and Recently Added presents the albums in the chosen order. `prepare` verifies a backup and writes a recovery record; then `stage`, `clear`, `apply`, and `add` run in that order, each once, and `status` reports the progress. Every stage reads the record, offers `--dry-run`, prints its plan before changing anything, and records each change in the progress journal. A stage refuses to run before the stages that precede it are complete, and running a completed stage again changes nothing. The behavior of iCloud Music Library under these procedures has not been measured; `prepare` refuses libraries whose cloud status it detects, and iLibrary does not claim to prevent cloud matching.

When a stage stops, because of an error or an interruption, its journal shows the operation that was in progress. Run the same stage again: it repeats that operation after checking whether its effect is already present, and then continues. Restore from the backup instead when a stage reports that the library or the files differ from the record.

#### rebuild prepare

`prepare` takes exactly one `SOURCE` directory in this version; multiple sources are not supported yet. There are no prompts. Every path option is resolved to an absolute path in which symbolic links of the existing part of the path are resolved, and the resolved paths are printed and used. `--workspace`, `--backup`, and `--restore-test` must name existing directories. A recovery record that already exists in the workspace is never overwritten, and the command refuses before any other work. Platform operations require macOS.

Each step runs only if the preceding steps passed. A failing step ends the command with status 1, one line on standard error per reason found in that step, and a final line that states what was changed: nothing, or only the files restored so far in the restoration directory, which are kept.

1. **Catalog and inventory.** The catalog is validated, and the `.m4a` files under `SOURCE` are inventoried by size, SHA-256, modification date, and creation date. Symbolic links, non-regular files, and colliding names are refused. Every file must match the catalog and every catalog track must have a file, by the rules of `validate`. The addition list is the catalog's album order for `--order` (`release` by default), and the expected display list is its reverse.
2. **Library registrations.** The whole library is read in a fixed number of requests. Every registration must be a file track whose location is a file of the inventory, with the cloud status empty or `unknown`, and every file must have exactly one registration. Non-file tracks, protected audio, duplicate locations, and registrations outside `SOURCE` are refused. Music's media folder must be known. Requires the Automation permission for Music.
3. **Plan validation.** The source, Music's media folder, the backup, the restoration-test directory, the staging directory, and the workspace must not overlap or pass through symbolic links; the source may lie inside the media folder. The restoration-test directory must be empty and on an APFS or HFS+ volume. Capacity is checked per volume with the plain available capacity: the restoration test needs the full inventory size, a staging directory on another volume needs a full copy, and the workspace needs 64 MiB. Unknown capacity is a refusal.
4. **Backup verification.** The backup must be on a local APFS or HFS+ volume that is not a disk image, must not share a physical disk with any other location, and must have a known volume UUID, without which its disconnection cannot be confirmed. `--confirm-separate-device` records the maintainer's statement that the medium is separate; without it, the backup is refused. Automatic device information refuses unsafe cases and never establishes independence alone. Every inventoried file must exist at the same relative path below the backup with equal size, bytes, and dates under the timestamp policy of the volume (APFS: exact nanoseconds; HFS+: the source time truncated to whole seconds); an additional `.m4a` file in the backup is also refused.
5. **Restoration test.** Every file is copied from the backup to the same relative path below the restoration-test directory, its dates are set, and the directory is verified against the inventory. If either volume is HFS+, the HFS+ policy applies. Restored files are kept and never deleted by iLibrary, including after a failure.
6. **Disconnection.** The command names the backup volume, asks you to eject it, and waits for at most `--disconnect-timeout` seconds (600 by default). It never unmounts anything. A volume that is still mounted is a refusal.
7. **Recovery record.** The record is written to the workspace, synchronized, and read back.

With `--dry-run`, steps 1 to 4 run, the complete plan is printed, and the command ends with status 0 and the statement that nothing was changed. The plan lists the resolved locations, the counts and total bytes, the capacity accounting for each volume, the addition and expected display lists, the evacuation plan summary, the backup facts, the timestamp policy, and the verification result. Without it, the same plan is printed before the restoration test, followed by the statement of the files that will be written.

- `--workspace DIR` names the directory that receives the recovery record.
- `--backup DIR` names the backup tree, which mirrors the relative paths below `SOURCE`. iLibrary never writes to it.
- `--restore-test DIR` names the empty directory that receives the restoration test.
- `--staging DIR` names the evacuation directory, outside Music's media folder. `rebuild stage` requires it to be on the volume of the media folder, so that files are moved rather than copied.
- `--order ORDER` selects `release` (default), `artist`, `artist-desc`, or `artist-release`.
- `--confirm-separate-device` states that the backup is on a separate physical device.
- `--disconnect-timeout SECONDS` sets the wait for the ejection, from 0 to 86400.

#### rebuild stage

`stage` moves every inventoried file from the media folder to its place in the staging directory, which keeps the file's path relative to `SOURCE`, and confirms that each moved file has the size, SHA-256, and dates of the inventory. Music must be closed. Each source must still match the inventory, no staging path may exist, and the staging directory must be on the volume of the media folder. Registrations are not changed. With `--dry-run`, every file is checked and the moves are listed.

#### rebuild clear

`clear` first confirms that every staged file still has its recorded size and modification time and that nothing has returned to its original place, then reads the whole library, which launches Music, and refuses to start when it holds any track that the record does not plan to remove, any non-file track, or a planned track whose name, album, or artist has changed. It then removes the recorded registrations one persistent ID per request: each request finds the one file track with that persistent ID and compares its name, album, and artist with case considered before deleting it, the track's file is confirmed to be still staged immediately before, and the track's absence is confirmed afterwards. When every registration is removed, the command confirms that Music reports no tracks at all and asks Music to quit, waiting up to a minute for it to close. The Music window is not inspected; an empty library is established by Music's track count. With `--dry-run`, the library is compared with the record and the removals are listed.

#### rebuild apply

`apply` writes the catalog recorded by `prepare` to the staged files and arranges them as `Album Artist/Album/NN Title.m4a` in the staging directory, exactly as `ilibrary apply --rename` would, and with `--timestamps` sets file dates to release dates at local midnight. Folder dates are set by `rebuild add --timestamps`, because the folders that remain are those in the media folder. Music must stay closed. The catalog must still have the SHA-256 recorded by `prepare`, every file in the staging directory must be one that the record lists, and every written file is read back. With `--dry-run`, the tag changes, moves, and dates are listed.

#### rebuild add

`add` moves the staged files of each album into the media folder, to `Music/Album Artist/Album/`, and adds them there in place, one album per request, in the addition order recorded by `prepare`. Before the first album, the library must contain no track other than those this rebuild has added, and no destination may be occupied; only the files of an album whose addition was interrupted may already be in the media folder. Music must report one track per file at the place of each file. Each album after the first is added only once the clock has passed the latest addition second of the album before it, and all of its addition seconds must be later; otherwise the command stops, because Recently Added might not show the intended order. Finally, the albums are ordered by their latest addition date, newest first, and the result must equal the expected display list of the record. Albums that share their latest addition second are refused, because Music's order for them is unknown. This compares Music's exposed addition dates, which order Recently Added; it is not an observation of the Music window. With `--timestamps`, the album folders, and artist folders for which the catalog gives a `folderDate`, are then dated in the media folder. With `--dry-run`, the albums and moves are listed. If an album's addition dates do not follow those of the album before it, the command stops and cannot continue that rebuild: the albums added so far remain in the library, and the backup is the way back to the original state.

#### rebuild status

`status` loads and validates the recovery record and the progress journal in `--workspace`, and prints the record's creation time, locations, counts, backup and restoration results, the completed stages, a stage in progress, an operation left open by an interrupted run, the counts of staged files, removed registrations, applied files, and added albums, and the next required action. It accesses neither Music nor the backup and changes nothing. A missing or invalid record or journal is reported with its reasons and ends with status 1.

#### Recovery Record

The record, `rebuild-record.json` in the workspace, has the format `ilibrary-rebuild-record-1`, distinct from the catalog format. It holds the inventory, the registrations and their mapping to files, the addition and expected display lists, the evacuation plan, the backup and restoration results, and the stage `prepared`. It is private: it contains machine-specific paths, the volume UUID of the backup, and Music persistent IDs. Never share, publish, or commit it. Its checksum detects accidental damage and does not authenticate it. Any change to the catalog, the files, the library, or the backup after preparation invalidates the record and requires a new `prepare` in a new workspace.

The progress journal, `rebuild-journal.jsonl` in the workspace, has the format `ilibrary-rebuild-journal-1`. It is append-only: each line records the beginning or completion of a stage, or the intent, return, or verified result of one operation, and carries the checksum of the line before it, so that a damaged or edited journal is refused. It is as private as the record. Never edit or remove it during a rebuild.

### export

```bash
ilibrary export ~/Music/Staging -o catalog.json --artwork covers
```

Writes a draft catalog from the tags of the `.m4a` files. Files are grouped into albums by album and album artist, and into discs and tracks by their disc and track numbers. A value that every track of an album shares is written at album level; other values are written per track. Release dates are written as `YYYY-MM-DD` when a file carries a complete date, and omitted when it carries only a year.

- `-o`, `--output FILE` names the catalog to write. It is required, and an existing file is never overwritten.
- `--dry-run` lists the catalog and covers that would be written and writes nothing. Without it, the same list is printed before writing, and every written file is read back. The catalog's folder and the artwork location must be writable directories; when a write or readback fails, the files and the directory that the export created are removed.
- `--artwork DIR` writes each album's cover to `DIR` in its embedded JPEG or PNG format, without re-encoding (decision 14), and references it from the catalog by a path relative to the catalog. Without this option, the catalog names no artwork, and `apply` leaves the files' covers unchanged.
- `--strict` refuses the export, with status 1 and without writing a catalog, artwork, or directory, when it would not be a complete inventory. Every reason is listed on standard error, followed by a line stating that nothing was changed. The check runs before any write and also under `--dry-run`; when it passes, the usual plan is printed.

Files without an album tag or a track number are not exported. Gaps or repetitions in disc and track numbers are reported, because a catalog numbers its discs and tracks by position.

Without `--strict`, every condition above is reported as a warning and the export proceeds as described. With `--strict`, the following conditions are refusals: a path skipped by the scan (a symbolic link, a protected `.m4p` file, an explicitly named file that is not `.m4a`, or any other scan refusal); a file without an album tag or a track number; a repeated disc and track pair; disc numbers that are not exactly 1 to n; track numbers within a disc that are not exactly 1 to n; a positive track total declared by the track-number tags of a disc that differs from the number of tracks exported for that disc, or that differs between tracks of the disc; a positive disc total declared by the disc-number tags of an album that differs from the number of discs exported, or that differs between tracks of the album (a total of 0 or an absent total is undeclared and is permitted); and a release date tag that is present but not a full `YYYY-MM-DD` date, such as a year alone, a year and month, or a malformed value. No month or day is invented, and nothing is renumbered. An absent release date is permitted, and an undated album keeps its documented placement. The following remain warnings in strict mode: several album artists in one album, a compilation flag on some tracks only, differing or missing covers, and a missing title replaced by the file name.

### prompt

```bash
ilibrary prompt catalog.json > prompt.md
```

Prints instructions for completing the catalog with an AI agent or AI chat: the authoring rules in English with Japanese explanations, the JSON Schema, and the draft. The catalog must be valid. The workflow is described in [Completing Catalogs with AI Agents](catalog-for-agents.md).

### schema

Prints the JSON Schema of the `ilibrary-catalog-1` format, identical to [docs/schema/ilibrary-catalog-1.schema.json](schema/ilibrary-catalog-1.schema.json).

### validate

```bash
ilibrary validate catalog.json ~/Music/Staging
```

Checks the catalog's format identifier, fields, types, required values, dates, duplicate albums, and the existence and format of its artwork, and prints each finding with its JSON path. With paths, it also matches the files to the catalog and reports every match, unmatched file, refused path, and catalog track without a file. Exit status is 0 only when the catalog is valid and every file matches.

### apply

```bash
ilibrary apply catalog.json ~/Music/Staging --dry-run
ilibrary apply catalog.json ~/Music/Staging --rename --timestamps
```

Writes the catalog's values to the matched files without re-encoding.

1. The catalog is validated and its artwork read.
2. Every file is matched. Nothing is changed when any file is unmatched or refused.
3. The planned changes are listed: every changed field with its old and new value, every move, and every date.
4. With `--dry-run`, the command stops here.
5. Tags are written through a hidden partial file whose audio stream is compared with the source before it replaces the file; each file is then read again and compared with the plan.
6. With `--rename`, files are moved; with `--timestamps`, dates are set last.

The fields written are the title, artist, album artist, album, genre, composer, copyright, release date (`YYYY-MM-DDT00:00:00Z`), track and disc numbers with their totals from the catalog's structure, the compilation flag when the catalog states it, and the artwork when the catalog names it. A value that the catalog leaves empty or omits is not changed. Reapplying a catalog whose values the files already carry changes nothing and leaves the files byte for byte identical.

- `--rename` moves each file to `PATH/Album Artist/Album/NN Song.m4a`, or `D-NN Song.m4a` on multi-disc albums, with `_` in place of `:` and `/`. Every `PATH` must be a directory. Nothing is changed when a destination exists, when two files would share one, when a name derived from the catalog is empty, `.`, `..`, or longer than 255 bytes, or when a destination would lie outside its `PATH`. Folders left empty are reported and not removed.
- `--timestamps` sets dates as `timestamps` does, after every write and move. It requires macOS.

Each rewrite writes a complete new copy of its file before replacing it. Before anything is written, the plain available capacity of every volume that holds a changed file must cover the largest rewritten file plus the growth of all changed files on that volume, with a margin of 1 MiB; the sizes come from the exact write plans, so that added artwork is counted (decision 8).

### timestamps

```bash
ilibrary timestamps catalog.json ~/Music/Staging --dry-run --script dates.sh
```

Sets the creation and modification dates to each release date at local midnight, in this order (decision 9):

1. Matched files, from the track's release date.
2. Album folders that hold the files of exactly one album, from the album's release date.
3. Artist folders named after the album artist, from the artist's `folderDate` in the catalog. Without a `folderDate`, an artist folder is left unchanged (decision 15).

Folders outside the given directories are never changed. Where a time zone skips midnight, the first instant of the day is used and reported. Every path is checked before any date is set: a missing path is reported and never created, and a symbolic link is refused. Each date is read back after it is set. Setting creation dates requires macOS; elsewhere, use `--dry-run`, optionally with `--script`.

- `--dry-run` lists the planned dates and leaves dates unchanged. With an explicit `--script FILE`, the script is still written; omit that option for a preview that creates no files.
- `--script FILE` also writes an equivalent shell script. The script sets the time zone, checks that each path exists and is not a symbolic link before it calls `SetFile -d` and `touch -c -m -t`, reports and skips other paths, and exits with status 1 when any path was skipped. An existing file is never overwritten.

### check

```bash
ilibrary check ~/Music/Staging
ilibrary check ~/Music/Staging --library
ilibrary check --library
```

Reads M4A files and reports missing tags, duplicate titles or disc・track positions within an album, damaged files, and creation or modification dates that disagree with a complete release date at local midnight. An unreadable file or date is a finding; other readable files are still checked. Year-only dates do not establish an expected day. File dates are unavailable on Linux and explicitly reported as unexamined.

`--library` takes a snapshot of Music's file tracks, matching by file location even when Music holds an old album name. It reports files absent from Music, duplicate library entries, missing or relocated album files, and differences in title, album, artist, album artist, composer, genre, comment, track and disc numbers and totals, compilation, and year. Every duplicate entry is compared. With directory paths, another track of a selected album outside those folders is reported; select the whole album when intentional splits should not be findings. With no paths, M4A file locations reported by Music are checked; other formats are counted as unexamined for audio metadata and dates, while missing locations and cloud status remain reportable. Protected M4P files are refused. Cloud-only tracks that are not exposed as file tracks are outside this snapshot.

Artwork, copyright, and the full release date are not compared with Music. Notable cloud statuses, including `matched`, `subscription`, and `purchased`, are reported as findings; `unknown` does not establish the absence of cloud matching. The command diagnoses differences and never repairs files or library entries. Its output can contain metadata and paths: do not publish an unredacted report from a personal library. Library access can launch Music and request Automation permission; the command does not add tracks or change properties.

### doctor

```bash
ilibrary doctor
```

Reports the iLibrary version, build-toolchain range, platform capabilities, installed Music version, media folder, available capacity, and stored Automation permission, with a recovery step for each problem. A media volume with less than 1 GB available is reported as a problem; this threshold is a diagnostic warning, not the per-operation space calculation.

The command reads installed application information, preferences, and existing permission state. It does not launch Music, request permission, or read library tracks. Undetermined permissions and unavailable platform features are notes, not proof that an operation will succeed. Status 0 means no diagnosed blocking problem; status 1 means at least one problem. Review output for personal paths before sharing it.

## Environment

Dates use the time zone of the process, which the `TZ` environment variable selects.

## Rights

Process only recordings and artwork that you have the right to use. iLibrary does not download audio and refuses protected files. Catalogs, prompts, journals, and diagnostics can contain private metadata; review them before sharing. See [Rights and Privacy](../README.md#rights-and-privacy) and [CONTRIBUTING.md](../CONTRIBUTING.md#before-you-start) for reporting problems.
