# Ordered Addition

## Status

Historical record, October 17, 2026. This report records milestone M5: the command `add` and the Music automation in `LibraryMac`. It is designed from the live measurements in [Music Behavior](music-behavior.md). The maintainer's own library was not touched: the command was verified with a substitute library that behaves as Music was measured to behave, and has not yet been run against Music itself. Findings are classified as measured, inferred, or unknown.

## Implementation

`LibraryMac` reaches Music through `NSAppleScript`. It reads the media folder from Music's preferences, looks up file tracks by album and tracks by persistent ID, and adds a list of files in one call, using the script forms that worked in the separate macOS user. It reads the composer, genre, year, and track and disc numbers as well, for M6; those reads were not part of the measurements (unknown). It never sets a track property, because setting the album or location made Music move and rename files (measured, M7 and M8).

`add` follows AGENTS.md and the measurements:

- **Order.** Albums are grouped by album and album artist and ordered with `CatalogCore`: by release date, by album artist and album name in either direction, or by album artist and release date.
- **Stop at existing tracks.** Before each album, the library is searched for a track with the same album artist, album, and title; one stops the run before the album is moved.
- **Move, then add in place.** Each album is moved to `Music/Album Artist/Album/` inside the media folder before it is added, because Music copied files added from outside (measured, M4) and added files inside in place (measured, M2).
- **Confirm before the next album.** Music must report as many tracks as files, with distinct persistent IDs, each located at the place of its file. Because Music returns the existing track for a file it already holds (measured, M3), a file added twice would not pass this check unnoticed.
- **Resume.** A journal in the first staging folder records each album before it is moved and its persistent IDs once confirmed, since persistent IDs survived a relaunch (measured, M5). An interrupted album is completed first: files left behind are moved, tracks already added are recognized by location, and otherwise the files are added.
- **Refuse before moving.** Missing album or album artist tags, existing destinations, folders on the way that are files or links, and staging folders that overlap the media folder change nothing.

## Verification

Measured on the maintainer's Mac on October 17, 2026: all 132 tests passed, 50 of them in `ilibraryTests`, and the formatting check reported no problem. Every test runs without the real Music app; the shared test environment removes it, and the `add` tests supply a substitute library. The substitute adds files inside the media folder in place, returns the existing track for a file it holds, and reports copies for files outside, as measured.

The tests cover the four orders, in-place addition with every file moved and every album confirmed, a dry run that changes nothing, a stop before the album whose track the library already holds, resumption after a failed addition without a second move, recognition of an album added but not recorded, tracks reported elsewhere, collisions in the media folder, staging folders inside the media folder, missing tags, an unknown media folder, and the absence of Music.

## Not Verified

- `add` has not been run against Music. The M5 gate, a test library, remains open until the maintainer runs the live validation in a new separate macOS user, which is prepared together with M6.
- Multi-disc albums, compilations, and names that differ from Music's organized names were not measured in Music; files are expected to carry Music's names already, and other names are reported.
- How Music behaves with iCloud Music Library enabled is unknown.
