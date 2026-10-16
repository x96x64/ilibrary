# Music Behavior

## Status

Historical record, October 17, 2026. This report records the live measurements of S3 that the [Architecture Spike](architecture-spike.md) left open, made by the maintainer with `scripts/validation/music-live-probe.sh` at commit `55095d0`, following [Live Music Measurements](../live-music-measurements.md). They were made in a separate local macOS user that was not signed in to an Apple Account, with a new, empty library, on macOS 27.0.1 (`26A434`) with Music 1.7. Two synthetic albums of Apple Lossless files were used: album A of three tracks inside the media folder, and album B of two tracks outside it. The maintainer's own library was not touched.

Each result below is measured in that environment unless it is marked otherwise. Behavior with iCloud Music Library, with other settings of Music, or with other versions is unknown.

## Results

| Question | Result |
| --- | --- |
| M1. Where is the media folder? | The preference `media-folder-url` named `~/Music/Music/Media.localized`, which existed. |
| M2. Are files inside the media folder added in place? | Yes. `add` returned three tracks for three files, each located at the path where the file had been placed, and the number of files in the media folder stayed at three. Every cloud status was `unknown`. Adding left the file's modification and creation dates unchanged. |
| M3. What does adding the same file again do? | `add` returned one track with the persistent ID of the existing track, and the library still held three tracks. No duplicate was created. |
| M4. Are files outside the media folder copied? | Yes. Both tracks were located in `Music/iLibrary Probe Artist/iLibrary Probe Album B/` inside the media folder, named `01 Probe Song 1.m4a` and `02 Probe Song 2.m4a`, and both sources remained outside. |
| M5. Do persistent IDs survive a relaunch? | Yes. After Music was quit and launched again, each persistent ID found exactly one track at its previous location. |
| M6. Does Music reread a changed title? | A file was rewritten with a changed title and replaced at the same path. Music already reported the new title before `refresh` was called, and still after it. When Music reread the file is unknown. |
| M7. Does Music follow a moved file, and does setting `location` relink it? | Music followed a file moved to another folder inside the media folder without being asked. Setting `location` to that new path then moved the file back to its organized path, `iLibrary Probe Album A/02 Probe Song 2.m4a`. |
| M8. What does renaming an album do? | Setting the album of each track by persistent ID, one per call, moved all three files into a new folder `iLibrary Probe Album A Renamed`, and renamed the file whose title had changed to `01 Probe Song 1 Changed.m4a`. The old album folder and the emptied `Relinked` folder no longer existed. |
| M9. Was Terminal allowed to control Music? | Yes, after the prompt that macOS showed. |

M7 and M8 together show that Music reorganized files in the media folder when track properties were set through Apple Events (measured); the setting that controls this was not read (unknown). The curation report observed a split album and broken references after a rename in the maintainer's library; the probe's album was not split, because every track was renamed.

## Consequences for M5 and M6

- **Move first, then add in place (M2, M4).** `add` must move each album to its organized path inside the media folder before adding it, as AGENTS.md requires; files added from outside would be copied.
- **Confirm by location.** After each `add`, the returned tracks must number as many as the files, and each must be located at the path where its file was placed.
- **Existing tracks.** Because `add` returns an existing track for a file already in the library (M3), a returned persistent ID that existed before is treated as a match, and the command stops. Tracks of the same album found before adding also stop it.
- **Never set album or location through Music (M7, M8).** Music moves and renames files when they are set. iLibrary writes tags to files and arranges folders before adding, as AGENTS.md requires, and does not change track properties.
- **Persistent IDs for resumption (M5).** Persistent IDs can be recorded to resume an interrupted run and to find tracks later.
- **Dates (M2).** Adding does not change file dates, so dates set by `timestamps` before `add` survive the addition itself. Whether later reorganization changes them is unknown.
- **Comparing files and the library (M6).** Music reread a changed title in this case, but the curation report measured stale comments and composers in the maintainer's library; `check` must therefore compare every field and report differences rather than assume either behavior.
- **Cloud status.** Without iCloud Music Library, every status was `unknown`; how `matched` and `subscription` appear remains unmeasured.

Multi-disc naming, compilation folders, files whose names differ from Music's organized names, and the effect of iCloud Music Library were not measured.
