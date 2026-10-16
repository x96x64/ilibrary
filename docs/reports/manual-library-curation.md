# Manual Library Curation

## Status

Historical record, October 16, 2026. This report summarizes a manual curation procedure carried out between September 18 and October 16, 2026, on a local Music library of about three hundred tracks obtained from mora and the iTunes Store. It records the operations that iLibrary is intended to automate and the failures that its design must prevent. Library contents, account details, and personal paths are omitted. Observations are classified as measured, when they were directly observed, or inferred.

## Procedure

1. **Conversion.** FLAC downloads were converted to Apple Lossless in M4A containers with stream metadata and artwork preserved. Each output was checked for codec and duration before its source was deleted. Bit depth and sample rate were preserved; the library contained 16-bit 44.1-kHz, 24-bit 44.1-kHz, and 24-bit 48-kHz files.
2. **Metadata correction.** Copyright lines were normalized to the `℗` and `©` symbols, release years were unified per album where the maintainer required it, company names were researched and written consistently, composer lists were corrected and expanded from initials, and comments were removed.
3. **Reference record and reapplication.** Metadata excluding artwork was exported to a JSON record and reapplied to freshly downloaded files by album name, disc number, and track number.
4. **Naming.** File and folder names were made identical to those created by the Music app: `NN Title.m4a` for single-disc albums, `D-NN Title.m4a` for multi-disc albums, and `_` in place of `:` and `/`.
5. **Timestamps.** Modification and creation dates of files and folders were set to each album's release date at local midnight by a shell script ordered by date.
6. **iTunes Store purchase.** A purchased AAC file was rebuilt around its unchanged audio stream without purchase and store metadata, and artwork was embedded.
7. **Ordered import.** Albums were moved into the Music media folder and added one at a time in release order.

## Findings

| Finding | Classification | Consequence for iLibrary |
| --- | --- | --- |
| Conversion while storage was nearly full produced 47 truncated files of about ten seconds that were otherwise valid ALAC. | Measured | Check free space; verify duration and decoded PCM before any deletion. |
| Some multi-disc downloads number tracks continuously across discs; matching by disc and track number applied the metadata of the wrong tracks. | Measured | Match continuous numbering explicitly and cross-check titles. |
| Renaming tracks in Music while iterating over the track collection applied artist changes to unrelated tracks of another album. | Measured | Address tracks by persistent ID, one operation per call. |
| Changing an album name caused Music to reorganize folders, splitting one album across two folders and breaking eight file references. | Measured | Arrange folders explicitly and relink or re-add tracks. |
| Music retained comments and composers that had been removed from files. | Measured | Compare library and file metadata after every change. |
| Setting a release date in Music rewrote the file's date as a UTC timestamp derived from local time. | Measured | Write dates as `YYYY-MM-DDT00:00:00Z` and convert local times deliberately. |
| `touch` on a missing artist folder created an empty file, which later prevented the folder's creation and caused an import error. | Measured | Never create paths when setting timestamps. |
| Files placed inside the media folder were added without copying. | Measured | Move albums into the media folder and add them in place. |
| A track that matched an album in the Apple Music catalog was restored from iCloud with catalog metadata and artwork after removal and re-addition, despite re-encoding. Re-downloading every track removed the identification. | Measured for the observed cases; the mechanism is inferred | Do not claim to prevent matching; remove store identifiers and report cloud status. |
| Tracks matched to a different catalog release displayed that release's description and copyright on synchronized devices. | Measured | Report matched tracks so that they can be replaced by fresh downloads. |
| A purchased AAC file rebuilt by stream copy was shown by Music as an ordinary AAC audio file. | Measured | Rebuild purchased files without re-encoding. |
