# Command-Line Interface

## Overview

`ilibrary` is a command-based interface with verb subcommands. This reference describes the commands implemented in the current development version; `import`, `add`, `check`, and `doctor` are planned and end with exit status 2 and a message that they are not implemented.

```
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

### export

```bash
ilibrary export ~/Music/Staging -o catalog.json --artwork covers
```

Writes a draft catalog from the tags of the `.m4a` files. Files are grouped into albums by album and album artist, and into discs and tracks by their disc and track numbers. A value that every track of an album shares is written at album level; other values are written per track. Release dates are written as `YYYY-MM-DD` when a file carries a complete date, and omitted when it carries only a year.

- `-o`, `--output FILE` names the catalog to write. It is required, and an existing file is never overwritten.
- `--dry-run` lists the catalog and covers that would be written and writes nothing. Without it, the same list is printed before writing, and every written file is read back.
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

- `--rename` moves each file to `PATH/Album Artist/Album/NN Title.m4a`, or `D-NN Title.m4a` on multi-disc albums, with `_` in place of `:` and `/`. Every `PATH` must be a directory. Nothing is changed when a destination exists or two files would share one. Folders left empty are reported and not removed.
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
