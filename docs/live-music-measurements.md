# Live Music Measurements

## Purpose

Milestone M5 adds albums to a Music library, and milestone M6 compares files with a library. The behavior of Music on which they depend has not been measured by iLibrary (see S3 in the [Architecture Spike](reports/architecture-spike.md)): whether files inside the media folder are added in place, which tracks `add` returns, whether persistent IDs survive a relaunch, the cloud status of local files, how duplicates and files outside the media folder are treated, whether `refresh` rereads changed tags, whether a moved file can be relinked, and how renaming an album reorganizes folders.

These measurements are made in a separate local macOS user that is not signed in to an Apple Account, so that neither the maintainer's library nor the maintainer's iCloud Music Library is touched. `scripts/validation/music-live-probe.sh` performs them and writes a result file without personal paths.

## Procedure

1. In System Settings, Users & Groups, add a Standard user, for example `ilibrarytest`. Do not sign in to an Apple Account in that user, now or later.
2. Log in as that user. Skip every offer to sign in to an Apple Account during setup.
3. Open Music once, dismiss its welcome screens without signing in, and quit it. This creates an empty library and media folder.
4. In Terminal, run `git clone https://github.com/x96x64/ilibrary.git` and `cd ilibrary`.
5. Run `scripts/validation/music-live-probe.sh`, type `YES` when asked, and allow Terminal to control Music when macOS asks. The script refuses to run when the user is signed in to an Apple Account or the library holds any track, so that every run starts from an empty library; a second run needs a new test user.
6. When it ends, open `ilibrary-live-results.txt` on the Desktop, check that it contains no personal information, and give its contents to the agent.
7. Log out of the test user. The user and its library may be kept for later measurements or deleted in Users & Groups.

## Results

Each section of the result file corresponds to one question:

| Section | Question |
| --- | --- |
| M1 | Where the media folder is, as Music's preferences name it |
| M2 | Whether files inside the media folder are added in place, how many tracks `add` returns, their cloud status, and whether adding changes file dates |
| M3 | What adding the same file again does |
| M4 | Whether files outside the media folder are copied into it |
| M5 | Whether persistent IDs and locations survive a relaunch of Music |
| M6 | Whether Music rereads a changed title before and after `refresh` |
| M7 | Whether Music follows a moved file, and whether setting `location` relinks it |
| M8 | Whether renaming an album, one track per call, moves files or folders |
| M9 | Whether Terminal was allowed to control Music |

The results are recorded in a new report, and M5 and the library parts of M6 are designed from them.
