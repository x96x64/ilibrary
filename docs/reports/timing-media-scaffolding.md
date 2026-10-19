# Timing Media Scaffolding Correction

## Evidence and Provenance

The maintainer ran the file-only [stopped timing probe diagnostic](../rebuild-timing-diagnostics.md) in the existing separate test user on October 17, 2026, and supplied `/Users/Shared/reference-private/ilibrary-m10-timing-media-inventory.json`. The diagnostic reads saved run records and the names, types, and sizes of entries in the selected media directory. It does not query Music, open media contents, follow symbolic links, or change the library. A byte-identical copy is retained under ignored `reference-private/m10-timing-inventory-2026-10-17/`. Its SHA-256 is `2476349b1562f831fc09cc7863592c7b35cf79d59f66a0479449f899be9f4b47`.

The inventory identifies source `1493bdaa36257c848730a6fcdaabca17d24f1068`, a saved initial registration count of zero, and the media directory name `Media.localized`. It was observed at 07:57:09 UTC, about fifty minutes after the stopped run, and describes the current filesystem rather than a snapshot of the stop. This assessment read only the supplied inventory and the frozen probe source; it did not read the test user's media directory or operate Music.

## Inventory Results

| Classification | Finding | Limit |
| --- | --- | --- |
| Measured, supplied inventory | The media directory held 93 entries: 3 directories and 90 regular files | Contents were not read |
| Measured, supplied inventory | The files were one `.DS_Store`, one `.Media Preferences.plist` of 309 bytes directly in the media directory, and 88 `.strings` files of 51 to 627 bytes | No other file, symbolic link, or special entry was present at observation |
| Measured, supplied inventory | The `.strings` files occupy two `.localized` directories, one directly in the media directory and one inside `Automatically Add to Music.localized`; each holds the same 44 locale names | The locale list is specific to this system and Music version |
| Measured, supplied inventory | No audio file and no `Music` subfolder were present | This holds at observation time |
| Measured, supplied inventory | The saved initial registration snapshot is an empty list | This confirms the earlier source inference; it is not a GUI observation |
| Inferred from frozen source | The original guard refused 89 of the 93 entries: every regular file except `.DS_Store` | Which entry the traversal reached first is unknown, since its order was not recorded |
| Inferred | Music created the preference and localization files when it created the new library and media directory | The names, the localized folder convention, and the 4.703-second stop before any working copy support this; creation time was not measured |

## Cause Assessment

The first timing run stopped because its media guard admitted only directories and `.DS_Store`, while a media directory newly created by Music 1.7 contains a preference file and folder localization files (inferred cause, consistent with the measured inventory). The stop was a defect of the validation guard, not evidence of a wrong library, an incorrect setting, a leftover audio file, or a timing failure. The guard's substituted tests used an empty fixture directory and therefore did not represent this content; the earlier preparation report already noted that fresh-library media contents were unqualified.

The display probe's fresh cases, which remain unrun, refuse only `.m4a` files in a new media directory and would not refuse this content. The timing guard was stricter by design, and the stricter intent is retained.

## Correction

Commit `4cd7c6b` prepares timing version 2. The guard now inventories the media directory without following links or opening files and accepts only:

- directories, which were accepted before;
- regular files named `.DS_Store` at any depth, which were accepted before, now excluding non-regular entries;
- one regular file `.Media Preferences.plist` directly in the media directory, of at most 64 KiB;
- regular files named in a locale form such as `ja.strings`, `en_GB.strings`, or `es_419.strings`, of at most 64 KiB, only in a `.localized` directory directly in the media directory or directly in a `.localized`-suffixed child of the media directory.

Every other entry, including symbolic links, audio files, misplaced or nested preference and localization names, and oversized scaffolding files, is refused before any working copy, edit, or addition. The complete inventory is saved privately as `initial-media.json`. The log records counts by category and, after a refusal, the relative name, type, and size of the first refused entry, so that a later stop identifies its cause without another diagnostic.

Version 2 uses a separate bundle, `ilibrary-m10-timing-v2`, a separate case name, `timing-v2-small`, and a separate new library, `M10-timing-v2-small`. Its shared report cites the stopped run's source, report checksum, and inventory checksum as history. The stopped bundle, `M10-timing-small`, its records, and the inventory remain unchanged and are not rerun. No registration-removal stage, waiting interval, completion gate, expected display order, or product feature changes.

## Preparation Verification

Measured locally on October 17, 2026:

- All 23 timing tests passed, three of them new, in a suite of 96 probe tests; all 105 validation tests, including bundle inventory, passed. The run fixture now contains the observed scaffolding names, types, and sizes with synthetic contents, and the complete run passes through it with zero refusals.
- New tests refuse misplaced localization names, nested preference and localization files, non-locale names in `.localized`, audio names, oversized scaffolding, an existing audio file, and symbolic links, without following or changing them. Inventory depth and entry count are bounded.
- Classifying the supplied inventory with the version 2 rule accepts all 93 entries; the version 1 rule refuses 89.
- The release build, six-file preparation, two catalogs, ZIP integrity, and bundle verification passed. The bundle manifest records commit `4cd7c6b30065df1aef9c94b80bf5ab1bb2ef8f10`, and its probe scripts and procedure match that commit.
- File-only checks with Music calls blocked passed catalog application, timestamps, file validation, native synthetic backup restoration, preservation of the original backup image, and an unrun report containing the stopped-run history.
- The product executable is byte-identical to that of timing version 1 and display-v3.
- The ZIP SHA-256 is `a21d381d87f382f172c1d0e70f5fd32526cad8a10e69dcd49a9aff05b9af146f`. The ZIP and its checksum were copied to the shared directory without overwriting existing files; both copies matched, and the earlier timing archive was unchanged.

These checks qualify the corrected guard against the observed inventory and the prepared bundle. They do not qualify live timing, GUI order, scaffolding on other system or Music versions, or any M10 gate.

## Remaining Gates and Handoff

M10 has not passed. The effect of separating album addition times on Recently Added order remains unknown, as do scale, the artist-order cases, a production timing policy, automatic GUI emptiness detection, and independent physical backup. The next evidence is one run of the [version 2 timing procedure](../rebuild-timing-validation.md) in the same test user with the new library, returning `/Users/Shared/ilibrary-m10-timing-v2-report.txt`. Preserve every earlier library, bundle, record, and report. Personal-library operations, product `rebuild`, and publication remain unauthorized.
