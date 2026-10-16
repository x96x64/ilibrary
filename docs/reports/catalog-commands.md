# Catalog Commands

## Status

Historical record, October 17, 2026. This report records milestone M3: the commands `export`, `prompt`, `schema`, `validate`, `apply`, and `timestamps`, the macOS-only target `LibraryMac` for file dates, and their verification. Following decision 16, only synthetic files were used; private references were not opened, and the maintainer's media folder and Music library were not touched. Findings are classified as measured, inferred, or unknown.

## Implementation

| Command | Behavior |
| --- | --- |
| `export` | Drafts a catalog from M4A tags, hoisting shared values to album level, and writes covers in their embedded JPEG or PNG format (decision 14). It never overwrites a file. |
| `prompt` | Prints the authoring rules in English with Japanese explanations, the JSON Schema, and the draft. |
| `schema` | Prints the embedded JSON Schema. |
| `validate` | Reports catalog diagnostics with JSON paths, missing or invalid artwork, and, with paths, every match, unmatched file, refused path, and missing track. |
| `apply` | Lists every planned change, then writes tags through `MP4Writer`, reads each file back, and optionally renames files and sets dates. |
| `timestamps` | Sets dates of files, then album folders, then artist folders with a `folderDate` (decision 15), and optionally writes an equivalent script. |

The command layer is in the `ilibrary` target and uses only Foundation, `MP4Core`, and `CatalogCore`. Setting creation dates is confined to `LibraryMac`, whose sources compile only on macOS; elsewhere `apply --timestamps` and `timestamps` without `--dry-run` end with status 1 before anything is changed. No package dependency was added.

### Design Choices

The following choices were made during implementation and are recorded for the maintainer's review.

- **All or nothing before writing.** `apply` changes nothing when any file is unmatched or refused, when artwork is missing or not an image, when a renamed file would replace another, or when free space is insufficient. Failures after writing has begun stop at once and report how many files were already written.
- **Unknown values stay unchanged.** A value that the catalog leaves empty or omits is not written, so that exporting and reapplying never erases information that a catalog cannot represent.
- **Totals come from the catalog.** Track and disc totals are written from the number of tracks and discs in the catalog.
- **Corrected titles.** M2's matcher refused a file whose title disagreed with the catalog at its disc and track numbers, which made title corrections impossible. Such a file is now matched there when no track of the album carries the file's title; an album with at least as many differing titles as agreeing ones is refused as a whole, and files without a title tag count as neither, so that the misnumbering observed during manual curation is still caught. `validate` and `apply` report each such match.
- **Renaming root.** `--rename` arranges files below the directory argument that contains them and requires every path to be a directory.
- **Folder dates.** An album folder is dated only when it holds the files of one album; an artist folder only when it is named after the album artist and the artist has a `folderDate`. Folders outside the given directories are never dated.
- **Script.** The equivalent script sets the time zone, checks each path with `[ -L ]` and `[ -e ]` before calling `SetFile -d` and `touch -c -m -t`, and exits with status 1 when it skipped a path.

## Verification

### Synthetic Tests

Measured on the maintainer's Mac (macOS 27.0.1, Swift 6.4 from the Command Line Tools) on October 17, 2026: all 100 tests passed, namely 23 in `ilibraryTests`, 24 in `MP4CoreTests`, 4 in `LibraryMacTests`, 8 in `FLACCoreTests`, and 41 in `CatalogCoreTests`, after the review corrections below. `swift format lint --strict` reported no problem.

The command tests build synthetic libraries of three albums and nine files, including a two-disc album, a compilation with per-track artists, PNG and JPEG covers, and a title containing `:` and `/`. They verify that `export --dry-run` writes nothing, that export followed by reapplication reports no change and leaves every file byte for byte identical, and that a second export equals the first. They verify that edits are previewed without change, applied with the audio streams intact, and stable when reapplied; that renaming produces the Music app's names; and that collisions, unmatched files, symbolic links, missing paths, missing artwork, and insufficient free space on the volume of any changed file change nothing. They also verify the order and folder rules of the date plan, the reporting of a skipped midnight, the quoting of the script, the refusal of missing paths and links before any date is set, dates read back after `apply --rename --timestamps`, and a run of the generated script that skips a deleted file without creating it.

### End-to-End Validation

`scripts/validation/catalog-commands.sh` builds a library of three Apple Lossless and four AAC files from synthetic PCM with `afconvert` and FFmpeg, and exercises the release build. All 21 checks passed in each of three runs (measured):

- After export, `validate` passed, `apply` planned no change, all file bytes were unchanged, and a second export was identical to the first.
- A dry run of an edited catalog left the bytes unchanged and listed three changed files. Applying it with `--rename --timestamps` rewrote and verified three files, moved seven, and dated ten paths.
- FFmpeg's decoded PCM of every file, Core Audio's decoded PCM of the Apple Lossless files, and the media-data payloads read by the spike's independent parser were unchanged by the edits and moves. FFmpeg and exiftool read the new values.
- `stat` reported both dates of a file, an album folder, and the artist folder at local midnight of the intended dates.
- Reapplying the edited catalog planned no tag change and no move.
- A symbolic link was refused without any change, and a missing path was refused and not created.

In the first run, Core Audio decoded two of the four AAC files differently after the edits, while FFmpeg's PCM and the media data were identical (measured). This is the irreproducibility of Core Audio's AAC decoding recorded in the architecture spike, not a change of the stream; the script therefore compares Core Audio's PCM for Apple Lossless only, in accordance with decision 7.

### Gate Assessment

The M3 gate requires export and reapplication of a library copy without unintended differences. On the synthetic library copies of the tests and of the end-to-end validation, reapplication changed no byte, no name, and no date, and re-export reproduced the catalog (measured). Whether real libraries contain values that a catalog cannot represent, such as gaps in track numbers, year-only dates, or totals that differ from the number of tracks, is unknown; `export` reports the first two, and `apply --dry-run` lists every resulting change.

## Review Corrections

The automated Codex review of commit `2e37aaa` on pull request #1 reported three findings, each corrected on the same branch before merging:

- **Corrected titles counted untitled files as support.** With one differing title and two files without title tags, the album was accepted although no title agreed. Agreeing titles must now outnumber differing ones.
- **Free space was checked on one volume only.** When changed files lay on several volumes, only the first file's volume was checked. Every changed file's folder is now checked.
- **`export` could not be previewed.** `export` now lists every file it will write, offers `--dry-run`, and reads written covers back as well as the catalog.

## Not Verified

- Linux: the Core and command tests are expected to run in the Linux CI job, which has not run for this branch because it has not been pushed (unknown).
- Real or private libraries were not used (decision 16).
- How Music responds to files rewritten, moved, or dated outside it is unknown, and is measured with the live S3 procedure before M5.
- Dates on volumes other than APFS are untested.
- The script depends on `SetFile`, which the Command Line Tools provide on this Mac; its availability elsewhere is unknown.

## Open Items

- Export from FLAC files and conversion belong to M4.
- Normalizing date-only tags such as `1980-06-01` to `1980-06-01T00:00:00Z` is reported by `apply` as a change; whether such files occur in the maintainer's library is unknown.
