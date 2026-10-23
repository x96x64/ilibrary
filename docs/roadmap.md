# Roadmap

## Product Scope

iLibrary automates the preparation and organization of a personal, local Apple Music library on macOS. It converts FLAC, WAV, and AIFF downloads to Apple Lossless; prepares purchased iTunes Store AAC files without re-encoding while removing purchaser and store metadata; applies catalog-based titles, artists, album artists, composers, genres, artwork, copyright, and release dates; normalizes titles; arranges files and folders as Music does; optionally sets release-date timestamps; adds albums in one of four orders so that Recently Added presents the intended sequence; and rebuilds an existing local library into that state.

The project is a personal tool maintained by one person. Reasonable file preservation, previews, error detection, and recovery are required. Exhaustive environment certification, repeated manual qualification, and formal proof of every hypothetical failure are not objectives, and no release depends on maintainer-operated test sessions or on access by a development agent to a personal library.

## Delivered Capabilities

Version 1.0.0 implements the complete workflow. `import` converts lossless downloads with decoded PCM verification and copies iTunes Store files without purchase metadata. `export`, `prompt`, `schema`, `validate`, and `apply` draft, complete, check, and write catalogs, with Music-style renaming and release-date timestamps. `add` moves albums into the media folder and adds them one at a time in four orders, each after the previous album's addition second, with resumption. `check` and `doctor` diagnose files, the library, and the environment.

`rebuild prepare` inventories the selected files and every Music registration, verifies a backup on separate storage, tests restoration, confirms that the backup volume is disconnected, and writes an immutable recovery record. `rebuild stage`, `clear`, `apply`, and `add` then move the files out of the media folder, remove exactly the recorded registrations, write the catalog to the files while Music is closed, and add the albums again in the recorded order, recording every operation in an append-only progress journal that `rebuild status` reports. The journal is indexed and appended incrementally, so that libraries of several thousand tracks are practical.

## Rebuilding Safety Boundary

Removal of registrations is the only irreversible change to a library, and it is bounded by measures that iLibrary verifies itself: a verified and disconnected backup with a passing restoration test, a verified evacuation of every file that is checked again before each removal, removal limited to the recorded persistent IDs after the title, album, and artist of each track are compared with the record, a stop on any registration that the record does not explain, and a final whole-library read reporting zero tracks. An earlier plan to detect an empty Music window through the Accessibility interface was withdrawn because it required repeated manual sessions and offered no qualified method.

iLibrary reports what it measured. A count of zero is reported as Music reporting no tracks, not as an empty window, and the expected Recently Added order is reported as the order of the exposed addition dates, not as an observation of the display. Libraries with cloud statuses other than `unknown` are refused at preparation, and iLibrary does not claim to prevent cloud matching.

## Verification and Limits

Every change reaches `main` through a pull request whose macOS and Linux CI jobs pass. The Foundation-only targets and the command logic are tested on Linux with Swift 6.4, and macOS CI compiles and tests the Music adapters and conversion against substitute libraries and generated audio. Releases are built, verified, and created on a GitHub macOS runner, and registry publication passes through environments that require the maintainer's approval.

Music behavior is classified as measured only when it was measured in a separate macOS user on macOS 27.0.1 with Music 1.7; [Measured Music Behavior](library-operations.md#measured-music-behavior) summarizes those results. The rebuilding stages have been tested with a substitute library and have not been run against the Music application. The requests that read addition dates by persistent ID and ask Music to quit were not among the measured forms; the first falls back to the measured bulk read when it fails, and the second is judged by whether Music has quit. Behavior on other macOS and Music versions and with iCloud Music Library is unknown.

## Beyond 1.0.0

Developer ID signing and notarization of the packaged executable are deferred; packages remain signed ad hoc, and Homebrew builds from source. Restoring playlists, ratings, play counts, or other library history during a rebuild is outside the scope, as are iCloud Music Library, protected audio, and downloading audio.

Further work is driven by actual use and by reported problems. A change that alters how files are moved or rewritten, or how registrations are removed, keeps the safety boundary above and its tests, and is described in the changelog.

## Repository Maintenance

Development uses short-lived branches merged through pull requests. A private weekly maintenance task removes branches whose commits are already contained in `main`; it never deletes a branch with unmerged commits, rewrites `main`, or touches release tags. Permanent public files are limited to those needed to understand, build, test, install, maintain, and use the product.

Release tags, their GitHub releases, their assets, and the published packages are never rewritten or replaced.
