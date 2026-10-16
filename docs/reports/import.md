# Import

## Status

Historical record, October 17, 2026. This report records milestone M4: the macOS-only target `ConversionMac` and the command `import` for mora and the iTunes Store. Synthetic files were used throughout; as the maintainer approved, copies of one mora FLAC file and one purchased iTunes Store file were processed inside the ignored `reference-private/work/` for an additional validation. No metadata value, title, file name, or account detail from those files is recorded here. The contents of unknown FLAC fields were not examined. The maintainer's media folder and the Music app were not touched. Findings are classified as measured, inferred, or unknown.

## Implementation

`ConversionMac` reads sources through `ExtAudioFile` as 32-bit integer PCM and writes Apple Lossless at the source's depth, as the architecture spike measured. It refuses floating-point PCM, more than two channels, unsupported depths, incomplete WAV and AIFF sample chunks, and existing destinations, and verifies each output by equal decoded PCM digests and frame counts, declared against decoded lengths, and the source's rate and channel count (decision 7). It removes its output on failure.

`import` plans every source before writing anything:

- FLAC, WAV, and AIFF files are converted, M4A files are copied without re-encoding with purchase metadata removed (decisions 10 and 12), and `.m4p` files, encrypted sample entries, and symbolic links are refused.
- FLAC tags are carried by an allowlist of standard fields and the front cover. Recognized fields that are not carried, such as COMMENT, are named in the report; fields outside the standard set are dropped and only counted.
- Output keeps each source's relative structure: the files under a source directory keep their paths relative to it under the output folder, and a source file is placed directly in it.
- Nothing is changed when any file is refused, an output exists or would be produced twice, the output folder lies inside a source, or the output volume lacks room for all outputs (decision 8).
- Each output is written under a hidden temporary name, verified, and then moved into place. A converted file is verified once more after its tags are written.
- `--delete-originals` moves originals to the Trash only after the whole import has been verified, as the maintainer decided.

Conversion and the Trash are injected into the command layer, which remains Foundation only; on Linux, copies are imported, while conversion and `--delete-originals` are refused before anything is changed.

## Verification

### Synthetic Tests

Measured on the maintainer's Mac (macOS 27.0.1, Swift 6.4 from the Command Line Tools) on October 17, 2026: all 120 tests passed, namely 38 in `ilibraryTests`, 5 in `ConversionMacTests`, 24 in `MP4CoreTests`, 4 in `LibraryMacTests`, 8 in `FLACCoreTests`, and 41 in `CatalogCoreTests`. `swift format lint --strict` reported no problem. FLAC fixtures were encoded with Core Audio, which encodes FLAC on this system (measured), so the public suite needs no external encoder.

- **Success.** WAV, AIFF, and FLAC sources at 16 and 24 bits, 44.1 to 192 kHz, mono and stereo converted with equal decoded PCM. A tagged FLAC file kept its allowlisted tags and cover, a purchased-style M4A file lost its purchase metadata with its stream unchanged, and the sources were byte for byte unchanged. `--from mora` imported FLAC only.
- **Refusals.** Floating-point PCM, six channels, a truncated WAV, AIFF, or FLAC file, an encrypted sample entry, an `.m4p` file, a symbolic link, colliding outputs, an existing output, an output folder inside a source, and insufficient space each changed nothing.
- **Failure.** A conversion that failed part-way stopped the import, left no temporary file, kept every original, and moved nothing to the Trash although `--delete-originals` was given.
- **Deletion.** With a substitute Trash, originals were moved only after every output had been verified, and unrelated files remained.

### End-to-End Validation

`scripts/validation/import.sh` passed all 30 checks on the release build (measured). FFmpeg decoded identical PCM from each source and its output; ffprobe reported Apple Lossless at the source's rate, channels, and depth; exiftool read the carried title, track, and date and no comment; an unknown field's value was absent from the output; the cover was carried byte for byte; the purchased-style copy kept its media data and lost its purchaser strings and store tags; no temporary file remained; the sources were unchanged; and `--from mora`, floating-point PCM, and existing outputs behaved as specified. Moves to the real Trash were not exercised, so that no synthetic file reached the maintainer's Trash. The tests cover the order and conditions of the moves with a substitute Trash; the call of `FileManager.trashItem` itself is untested (unknown).

### Private Validation

`scripts/reference_validation/validate-import.sh` imported copies of one mora FLAC file and one purchased M4A file. All eight checks passed (measured):

- The FLAC copy converted to Apple Lossless with equal decoded PCM (FFmpeg) and the same rate, channels, and depth. The report listed 8 carried tags and the front cover, named COMMENT, ORGANIZATION, and PERFORMER as not carried, and counted 9 unknown fields as dropped.
- The purchased copy was imported, not refused. Ten purchase items and seven sample-entry boxes were removed; FFmpeg decoded identical PCM, and the purchaser's account and owner strings occurred zero times in the output.
- No temporary file remained, the originals' checksums were unchanged, and the working copies were removed.

The first run of the script reported one failure, which was a defect in the script's own text comparison, not in the import; the corrected script passed.

## Not Verified

- Linux: the command tests, including the copy path of `import`, are expected to run in CI, which has not run for this branch (unknown).
- Moves to the real Trash through `FileManager.trashItem` (unknown, as above).
- Sources other than those measured: 20-bit and 32-bit integer PCM, FLAC files with an ID3v2 prefix in conversion, and multi-disc downloads with continuous numbering.
- How Music responds to imported files is measured with the live S3 procedure before M5.

## Open Items

- The nine unknown fields of the private FLAC file are dropped; what they contain was not examined.
- S5 still rests on one purchased file.
