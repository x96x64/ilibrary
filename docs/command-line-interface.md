# Command-Line Interface

## Overview

`ilibrary` is a command-based interface with verb subcommands. This reference describes the commands implemented in the current development version; `check` and `doctor` are planned and end with exit status 2 and a message that they are not implemented.

```
ilibrary import SOURCE... -o DIR [--from mora|itunes|auto] [--delete-originals] [--dry-run]
ilibrary add PATH... [--order release|artist|artist-desc|artist-release] [--dry-run]
ilibrary export PATH... -o CATALOG.json [--artwork DIR] [--dry-run]
ilibrary prompt CATALOG.json
ilibrary schema
ilibrary validate CATALOG.json [PATH...]
ilibrary apply CATALOG.json PATH... [--dry-run] [--rename] [--timestamps]
ilibrary timestamps CATALOG.json PATH... [--dry-run] [--script FILE]
ilibrary help [COMMAND] | --help | --version
```

`ilibrary help COMMAND` and `ilibrary COMMAND --help` print the options of a command. Options take their value as the next argument or after `=`, as in `--output=catalog.json`; `--` ends the options.

## Exit Status

| Status | Meaning |
| --- | --- |
| 0 | Success |
| 1 | A runtime failure, an invalid catalog, or a refusal to change anything |
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
4. The album's files are moved into the media folder named by Music's preferences, to `Music/Album Artist/Album/` with their names unchanged, and added there in one call. Music adds files inside the media folder in place (measured; see [Music Behavior](reports/music-behavior.md)).
5. Music must report one new track per file, each at the place of its file, before the next album begins. Otherwise the run stops and reports the album as not confirmed.

Nothing is moved when any file is refused, a destination already exists, or a folder on the way is a file or a symbolic link. A staging folder may not overlap the media folder. Track properties are never set in Music, because Music then moves and renames files. Files are expected to carry Music's names already, as `apply --rename` gives them; other names are reported, because Music may rename such files later.

Progress is recorded in `.ilibrary-add.json` in the first staging folder, with the persistent ID of every added track. When a run stops after moving an album but before Music confirmed it, the next run completes that album first: it moves any file left behind, recognizes tracks already added, and otherwise adds the files.

- `--order ORDER` selects the order.
- `--dry-run` lists the order, every move, and any track that would stop the run, and changes nothing. It reads the library.

### export

```bash
ilibrary export ~/Music/Staging -o catalog.json --artwork covers
```

Writes a draft catalog from the tags of the `.m4a` files. Files are grouped into albums by album and album artist, and into discs and tracks by their disc and track numbers. A value that every track of an album shares is written at album level; other values are written per track. Release dates are written as `YYYY-MM-DD` when a file carries a complete date, and omitted when it carries only a year.

- `-o`, `--output FILE` names the catalog to write. It is required, and an existing file is never overwritten.
- `--dry-run` lists the catalog and covers that would be written and writes nothing. Without it, the same list is printed before writing, and every written file is read back. The catalog's folder and the artwork location must be writable directories; when a write or readback fails, the files and the directory that the export created are removed.
- `--artwork DIR` writes each album's cover to `DIR` in its embedded JPEG or PNG format, without re-encoding (decision 14), and references it from the catalog by a path relative to the catalog. Without this option, the catalog names no artwork, and `apply` leaves the files' covers unchanged.

Files without an album tag or a track number are not exported. Gaps or repetitions in disc and track numbers are reported, because a catalog numbers its discs and tracks by position.

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

- `--rename` moves each file to `PATH/Album Artist/Album/NN Title.m4a`, or `D-NN Title.m4a` on multi-disc albums, with `_` in place of `:` and `/`. Every `PATH` must be a directory. Nothing is changed when a destination exists, when two files would share one, when a name derived from the catalog is empty, `.`, `..`, or longer than 255 bytes, or when a destination would lie outside its `PATH`. Folders left empty are reported and not removed.
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

Folders outside the given directories are never changed. Where a time zone skips midnight, the first instant of the day is used and reported. Every path is checked before any date is set: a missing path is reported and never created, and a symbolic link is refused. Each date is read back after it is set. Setting creation dates requires macOS; elsewhere, only `--dry-run` and `--script` are available.

- `--dry-run` lists the planned dates and changes nothing.
- `--script FILE` also writes an equivalent shell script. The script sets the time zone, checks that each path exists and is not a symbolic link before it calls `SetFile -d` and `touch -c -m -t`, reports and skips other paths, and exits with status 1 when any path was skipped. An existing file is never overwritten.

## Environment

Dates use the time zone of the process, which the `TZ` environment variable selects.
