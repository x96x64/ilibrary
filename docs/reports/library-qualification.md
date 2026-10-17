# Library Copy Qualification

## Scope and Authorization

On October 17, 2026, the maintainer authorized reading the personal media folder and validating copies kept under ignored `reference-private/`. The normal Music application and its library database were not accessed. No source file was modified. The measured run used the release build of commit `f54659f` on macOS 27.0.1 with Apple silicon.

The selected tree contained 301 M4A files in 20 album folders, totaling 29,322,864,878 bytes, with no symbolic links or other files. Available space did not permit a complete duplicate. Each album folder was copied, verified, and removed from the private working area after its checks completed, before processing the next folder. Original files were retained throughout.

## Procedure

For each folder, the private harness recorded source SHA-256 digests, sizes, creation dates, and modification dates; copied its files; and verified the copied bytes. It then performed these steps:

1. Preview catalog export and verify that no catalog or file change occurred.
2. Export and validate a catalog against all selected copies.
3. Preview and apply that unchanged catalog without renaming or setting dates.
4. Preview and execute `apply --rename --timestamps` within the private copy.
5. Repeat the same operation and compare names, bytes, creation dates, and modification dates.
6. Run `check` on the arranged files.
7. Compare the copied audio payloads with the initial payloads and recheck the originals.

After all folders completed, every original was hashed and its dates checked again. Raw catalogs, paths, logs, and digest records remain private. Only aggregate results are recorded here.

## Results

All 20 folders and 301 files completed the procedure (measured):

| Check | Result |
| --- | --- |
| Catalog tracks | 301; zero export warnings |
| Identity application | Zero planned tag changes; all file bytes unchanged |
| Dry runs | Selected copies retained their bytes, names, and dates |
| Arrangement | 301 file moves and 321 dated file or folder paths completed |
| Repeated arrangement | All bytes, relative names, creation dates, and modification dates unchanged |
| Audio payloads | All MP4 `mdat` payload digests unchanged |
| File diagnostics | Zero findings |
| Original files | All bytes, sizes, creation dates, and modification dates unchanged |

## Assessment and Limits

The authorized copy workflow completed without an observed defect. The sample produced no catalog warnings about numbering or dates; this does not establish that every possible library value is representable. This run did not introduce new tag values, export covers, convert audio, add tracks to Music, or test the real Trash. Those capabilities retain their separately recorded synthetic, private-reference, and separate-user evidence.

Audio preservation here is measured by unchanged file bytes for identity application and unchanged `mdat` payload digests after arrangement. It is not a new PCM-decoding experiment. The M8 evidence is ready for the maintainer's judgment; qualification of copies does not authorize operations on the normal Music library or establish cloud behavior.
