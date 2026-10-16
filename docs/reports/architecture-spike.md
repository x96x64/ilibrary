# Architecture Spike

## Status

Historical record, October 16, 2026. This report records milestone M1 of the [Technical Planning Study](../planning-study.md): spikes S1 to S5. The study is unchanged (SHA-256 `67acd45b4a36d2d0f2ca96085504bf4d410e5dc91b853a0fa23e990f37751369`). The report awaits the maintainer's review, which is the gate to milestone M2.

Two kinds of input were used. Synthetic fixtures were generated from deterministic pseudo-random and tonal PCM, with invented placeholders for purchase metadata. Private references were placed by the maintainer in the ignored `reference-private/` directory while the spikes were in progress: one AAC file purchased from the iTunes Store, a copy of it cleaned during manual curation, nine Apple Lossless files converted from mora downloads during manual curation, and one FLAC file downloaded from mora. Only copies inside `reference-private/work/` were processed, and every original was confirmed unchanged by byte comparison afterwards. This report records no file name, title, metadata value, or account detail from those files.

The maintainer's media folder and Music library were neither read nor modified. Music was not launched, and no Apple Event was sent to it.

Findings are classified as **measured** (directly observed in this environment), **inferred** (derived from measurements, documentation, or reference tools, but not observed as such), or **unknown**.

## Environment

Measurements were taken on a MacBook Air (`Mac16,12`) with an Apple M4 (10 cores) and 16 GiB of memory, under macOS 27.0.1 (`26A434`) on APFS. The toolchain was Apple Swift 6.4 (`swiftlang-6.4.0.34.1`) from the Command Line Tools for macOS 27.0, without Xcode. Music was version 1.7 (bundle version 1.7.0). Independent references were FFmpeg and ffprobe 9.0.2, exiftool 13.55, AtomicParsley 20240608.083822.1ed9031, flac and metaflac 1.5.0, and the system's `afconvert`, `afinfo`, `stat`, and `GetFileInfo`. These tools generated fixtures and checked results; no spike program invokes them.

## Summary

| Spike | Question | Result | Classification |
| --- | --- | --- | --- |
| S1 | Can item lists be rewritten without touching the audio? | Yes for 21 synthetic rewrites in three top-level layouts and for all 11 private files; outputs are idempotent and truncated inputs are rejected | Measured |
| S2 | Does AudioToolbox convert FLAC, WAV, and AIFF to Apple Lossless with equal decoded PCM? | Yes for mono and stereo at 16 and 24 bits up to 192 kHz, and for a private 24-bit 176.4-kHz FLAC file; six-channel order is not preserved as FFmpeg interprets it | Measured |
| S3 | Can Music be automated safely: in-place addition, persistent IDs, cloud status, media folder discovery? | Interfaces and configuration keys located; no live behavior measured | Dictionary and keys measured; behavior unknown |
| S4 | Can file and folder dates be set to release dates without creating paths? | Yes; several ordering constraints identified | Measured on APFS |
| S5 | Can purchase metadata be removed without re-encoding? | Yes for synthetic placeholders and for one purchased file, whose structure differs from the documented one | Measured; one purchased file only |

The architecture of the planning study is retained. The details below qualify it and propose decisions for M2.

## S1: MP4 Metadata Rewriting

### Method

`MP4Spike.swift` uses Foundation only. It parses the box tree, rebuilds the movie box (`moov`) in memory, and copies every other top-level box, including the media data (`mdat`), from a memory-mapped source without loading it. Every chunk offset in `stco` or `co64` is mapped through the original top-level layout to its new position. A size change is absorbed into `free` padding inside `meta` or `udta`, or into a `free` box immediately after `moov`, when one is large enough; otherwise the offsets are relocated. Output is written to a hidden sibling file, synchronized, parsed again, and only then moved into place.

Synthetic fixtures were 30-second stereo files. Core Audio (`afconvert`) produced 16-bit and 24-bit Apple Lossless and 256 kb/s AAC; FFmpeg produced Apple Lossless with the movie box at the end and, with `+faststart`, at the beginning, and AAC with `+faststart`; AtomicParsley retagged an FFmpeg file. Each was rewritten three ways: ten fields with a 2,360-byte PNG cover and removal of the comment, a small title change with padding absorption, and a forced conversion of `stco` to `co64`. Each private file was rewritten with a new title.

`verify-mp4.sh` compares the source and output by decoded PCM from FFmpeg and from Core Audio, the SHA-256 of every media-data payload, every chunk position relative to its media-data payload, and the audio duration, and fails on any FFmpeg decoding warning. For synthetic files it also reads the written fields back with ffprobe, exiftool, and AtomicParsley; for private files it prints no metadata value.

### Results

- **Container layouts (measured).** Core Audio writes `ftyp moov free mdat`, with 1,756 to 1,914 bytes of top-level padding and an `iTunSMPB` item even for Apple Lossless. FFmpeg writes `ftyp free mdat moov` by default and `ftyp moov free mdat` with `+faststart`. AtomicParsley rewrote the whole FFmpeg file as `ftyp free moov mdat` when adding two items. The purchased file has `ftyp moov free mdat` with 521,403 bytes of zero-filled top-level padding and 837 chunks. The nine private Apple Lossless files (24 bits, 176.4 kHz) and the cleaned AAC file have `ftyp free moov mdat`; the Apple Lossless movie boxes are about 2.5 MB because each holds a 2,447,628-byte JPEG cover.
- **Audio integrity (measured).** In all 21 synthetic and all 11 private rewrites, FFmpeg's decoded PCM, the media-data payloads, the chunk positions, and the durations were identical to the source. Relocation changed up to 59 chunk offsets in synthetic files and 14 to 837 in private files.
- **Fields (measured).** All three readers reported every written value, including `℗`, nested brackets, track `3 of 9`, disc `1 of 2`, the date `1980-06-01T00:00:00Z`, and the cover. The removed comment was absent. FFmpeg reports `timescale not set` for any embedded cover; a cover written by AtomicParsley produced the same warning, so the check excludes it.
- **Padding (measured).** A 29-byte growth was absorbed into the trailing padding of Core Audio files, leaving every chunk offset unchanged. FFmpeg's 8-byte padding could not absorb it, and offsets were relocated.
- **Idempotence (measured).** Reapplying the same title to a rewritten file produced identical bytes once items were replaced in place. The first implementation removed and appended items, which changed their order and the bytes.
- **Corrupt input (measured).** A file truncated to 3,000 bytes was rejected with the offending box named, and no output or partial file remained.
- **Core Audio decoding of AAC (measured; cause unknown).** Decoding through Core Audio to 32-bit integer PCM is not reproducible bit for bit. In every scripted S1 run, one rewritten synthetic AAC file decoded differently from its source, although FFmpeg's PCM, the media data, and the sample tables were identical. During S5, `ExtAudioFile` decoded the cleaned purchased file differently from the original in eight of nine decodes; a byte-identical copy at another path and `afconvert` decoded it identically. In the differing decode, 29,280,256 of 37,690,800 samples differed, in 17,951 of 18,403 AAC frames, by at most 704 units of 2⁻³¹ full scale, which is 0.011 of a 16-bit least significant bit. No Apple Lossless decode showed any difference.

### Consequences

- Rebuilding `moov` and copying media data by reference is sufficient for MP4Core. Relocation must be general, because layouts with the movie box first are common in both downloaded and processed files; padding absorption is an optimization, not a requirement.
- Items must be replaced in place to keep repeated application stable.
- For stream copies, equality of media-data payloads and sample tables is the evidence that audio is untouched. Decoded PCM of lossy audio is corroborating evidence only and must not be required to be bit-identical.
- Not covered: conversion to `co64` when relocated offsets exceed 32 bits (detected and refused by the spike), media data larger than 4 GiB, fragmented MP4, multiple tracks, chapters, and files written by Music itself.

## S2: Lossless Conversion

### Method

`ConversionSpike.swift` reads the source through `ExtAudioFile` into interleaved 32-bit integer PCM, with every depth left-aligned, and writes Apple Lossless in an M4A file whose format flag matches the source depth. Before conversion it checks free space and, for WAV and AIFF, that the sample chunk is complete. After conversion it decodes source and output, and requires equal SHA-256 digests of the PCM, equal frame counts, a declared frame count equal to the decoded count for both files, the Apple Lossless codec, and the source depth, rate, and channel count. Only then is the hidden partial file moved into place. FFmpeg decoded each source and output independently.

Synthetic sources were WAV and AIFF files written by `SynthAudio.swift`, and FLAC files encoded from them by `flac --best`. Signals contain alternating full-scale extremes, digital silence, tones, and noise, and frame counts are not multiples of the 4,096-frame packet. The private source was a copy of the mora FLAC file.

### Results

- **PCM equality (measured).** Core Audio and FFmpeg both found the decoded output equal to the source for all 18 synthetic mono and stereo conversions: WAV, AIFF, and FLAC at 16 bits and 44.1 kHz (stereo and mono), and at 24 bits and 44.1, 48, 96, and 192 kHz. Packet tables declared the exact frame count, zero priming frames, and the remainder of the last packet. Three decodes of the same output were identical.
- **Private FLAC file (measured).** The 24-bit 176.4-kHz stereo file of 51,826,701 frames (4 minutes 54 seconds) converted in 4.8 s and verified in 3.3 s. FFmpeg's decoded PCM of source and output was equal, and also equal to that of one of the nine Apple Lossless files converted during manual curation, which independently confirms that earlier conversion.
- **Multichannel (measured).** Six-channel conversions passed Core Audio's own comparison but not FFmpeg's. Per-channel digests show that the source's channels in WAV order (L R C LFE Ls Rs) were stored unchanged under the Apple Lossless layout C L R Ls Rs LFE, so FFmpeg assigns them to different speakers. Which interpretation is correct is unknown.
- **Truncated FLAC (measured).** A FLAC file cut to one third decoded without error to 438,272 of its 1,324,237 declared frames. Only the comparison with the declared count refused it.
- **Truncated WAV and AIFF (measured).** Core Audio derives their frame counts from the bytes present, so a truncated file decodes completely and consistently with itself. The chunk-length check refused both files.
- **Truncated output (measured).** An output cut to one third could not be opened (`'wht?'`).
- **Floating-point input (measured).** A 32-bit floating-point WAV file was refused before conversion.
- **Metadata (measured).** Converted files contained no source tags. Core Audio exposed the FLAC title, artist, and encoder through its information dictionary and the picture through the album-artwork property. A Foundation-only parser in the spike read the stream information, every Vorbis comment, and the picture, in agreement with metaflac. Converting and then tagging with MP4Spike left the decoded audio verified.
- **Free space (measured).** On the startup volume, the capacity for important usage was 35 GB, while the plain available capacity was 20 GB. On an 8-MiB APFS disk image, the capacity for important usage was 0 and the plain capacity 7,970,816 bytes. The preflight refused conversion into the disk image.
- **Full volume (measured).** With the preflight bypassed, `afconvert`, which writes through `ExtAudioFileWrite`, failed with error −40 and left no file. FFmpeg failed with `No space left on device` and left a 6,815,788-byte file that Core Audio could not open (`'dta?'`).
- **Throughput (measured).** A synthetic five-minute 24-bit 96-kHz stereo FLAC file converted in 2.5 s and verified in 1.9 s. These are single runs on one machine, not a benchmark.

### Consequences

- AudioToolbox through `ExtAudioFile` is sufficient for ConversionMac in mono and stereo, including the 176.4-kHz rate of the private download. Version 0.1.0 should refuse more than two channels until channel layouts are understood.
- Verification must compare declared and decoded frame counts and, for WAV and AIFF, chunk lengths; decoding without error does not establish completeness. The 47 truncated files in the curation report are consistent with a check of this kind having been absent; their cause was not determined.
- The free-space check should use the plain available capacity, because the capacity for important usage was both larger than the plain capacity and zero on a small volume.
- Tags and artwork must be written after conversion. FLAC metadata needs a Foundation-only reader, which belongs in a Core target; its placement is proposed below.

## S3: Music Automation

### Measured Without Access to the Library

- **Scripting dictionary.** Music 1.7's dictionary offers `add` for files, returning track references, with an optional destination; `refresh` for a file track; a read-only `persistent ID` described as a hexadecimal string that "does not change over time"; a read-only `database ID`; a writable `location` for file tracks; and a read-only `cloud status` with the values unknown, purchased, matched, uploaded, ineligible, removed, error, duplicate, subscription, prerelease, no longer available, and not uploaded. Commands are grouped into the access groups `com.apple.Music.library.read` and `com.apple.Music.library.read-write`.
- **Missing properties.** The dictionary has no property for the media folder, for whether iCloud Music Library is enabled, or for the settings that organize the media folder and copy added files.
- **Preferences.** Music's preferences contain the keys `media-folder-url` and `library-url`, each with a bookmark. For this account, `media-folder-url` was a file URL ending in `Music/Media.localized`. No key indicating iCloud Music Library or folder organization was found. Only key names and types were read; values other than that suffix were not recorded.
- **Automation permission.** With Music not running, `AEDeterminePermissionToAutomateTarget` without a prompt returned `procNotFound` (−600), and Music remained closed. The permission therefore cannot be reported without Music running.

### Inferred

- `doctor` can locate the media folder from preferences, but whether the value follows a library chosen at launch is unknown.
- Addressing tracks by `persistent ID` is supported by the dictionary. Its stability across relaunches, re-addition, and relinking is unknown.
- Whether a matched track can be identified reliably from `cloud status` is unknown; the curation report measured matching only through its visible effects.
- In-place addition of files inside the media folder was measured during manual curation, not in this spike.

### Unknown and Proposed Procedure

Every live behavior of Music remains unmeasured: in-place addition, duplicate detection, the track count after `add`, persistent IDs, cloud status of synthetic files, the effect of `refresh` and of changing `location`, folder organization after album renaming, and whether Music treats a file cleaned by this spike as it treated the file cleaned during curation. Measuring them requires a library that may be modified, and a test library under the maintainer's Apple Account could upload or match synthetic tracks into the maintainer's iCloud Music Library. The proposed environment is a separate local macOS user that is not signed in to an Apple Account, with a new Music library and synthetic albums produced by S1 and S2. The procedure requires the maintainer's approval and, because Music must be launched in that user's session, the maintainer's participation. AppleScript through `osascript` or `NSAppleScript` and ScriptingBridge were not compared, because the comparison requires live events.

## S4: File Timestamps

`TimestampSpike.swift` sets creation and modification dates through `FileManager.setAttributes` and reads them back. `stat` and `GetFileInfo` independently confirmed the values.

- **Local midnight (measured).** Midnight was computed for six dates in four time zones. Dates before 1970 and the British Standard Time experiment (`1970-01-01T00:00:00+01:00` in London) were handled. In São Paulo, 2018-11-04 had no midnight; the calendar returned 01:00.
- **Setting dates (measured).** Both dates were set on files and folders to 1958, 1980, and 1990, in either direction. A creation date later than the modification date was accepted.
- **Missing paths (measured).** `setAttributes` on a missing path threw `NSFileNoSuchFileError` (4) and created nothing. `touch` on a missing path created a regular file, reproducing the hazard recorded during curation.
- **Symbolic links (measured).** Setting dates on a symbolic link changed the target, not the link.
- **Folders (measured).** Adding, renaming, or atomically rewriting an entry changed the folder's modification date; writing an existing entry in place did not.
- **Replacing files (measured).** Removing a file and moving a rewritten one into its place gave both dates of the moment of rewriting. `replaceItemAt` preserved the creation date and set the modification date to that moment; writing in place behaved the same way.
- **Moves (measured).** Moving within a volume and across APFS volumes preserved both dates. Other file systems are untested.

Consequences: timestamps are applied after every write, rename, and move, to files before their folders; `timestamps` must check `lstat` and refuse symbolic links; release dates whose local midnight does not exist use the first instant of the day and are reported; folder dates set before `add` may be changed by Music when it moves or organizes files, which is unknown.

## S5: Removal of iTunes Store Purchase Metadata

### Method

exiftool's tag tables document item-list atoms `apID` (AppleStoreAccount), `ownr` (Owner), `purd` (PurchaseDate), `cnID`, `atID`, `plID`, `geID`, `sfID`, `cmID`, `akID`, and `xid `, and a `pinf` box (PurchaseInfo) in the `mp4a` sample entry. `MP4Spike inject-store` added synthetic placeholders with that structure, an invented account `synthetic.purchaser@example.invalid`, a flavor `flvr`, and stale padding containing the account string, to AAC files from Core Audio and FFmpeg with the movie box at either end. `strip-store` removes the store atoms, keeps only an allowlist of sample-entry children (`esds`, `chan`, `btrt`, `wave`, and the codec configuration boxes `alac`, `dfLa`, `dOps`, `dac3`, and `dec3`), zeroes all `free` and `skip` padding, and refuses protected sample entries. `inspect-boxes.py` takes the account and owner strings from the source's item list and counts their occurrences in any file without printing them.

### Results

- **Structure of the purchased file (measured).** The item list contains the store atoms `apID`, `ownr`, `purd`, `cnID`, `atID`, `plID`, `geID`, `sfID`, `cmID`, and `xid `, but not `akID` or `flvr`. The `mp4a` sample entry contains `esds`, five undocumented boxes (`dmix`, `udi2`, `udc2`, `udex`, `sbtd`), `pinf`, and 31,568 bytes of zero-filled `free` padding. `pinf` contains `frma`, `schm`, `schi` with `user`, `cert`, `righ`, `name`, and `chtb`, and a `sign` box; exiftool's tables name `key `, `iviv`, and `priv` instead of `cert`, `chtb`, and `sign`. The account string occurs once in the file, in `apID`, and the owner string once, in `ownr`. All padding was zero-filled.
- **Removal (measured).** For the purchased file and the three synthetic files, neither the account string nor the owner string occurred in the output, and exiftool reported no store or purchase tag. Before removal, exiftool reported 16 such tags in each synthetic file. For the purchased file, the movie box shrank from 113,859 to 80,586 bytes, 837 chunk offsets were relocated, and the sample entry was reduced to `esds`, as in the copy cleaned during curation.
- **Audio (measured).** For all four files, the media data, the chunk positions, the duration, and the decoded PCM from FFmpeg and from `afconvert` were identical to the source; for the synthetic files they were also identical to the file before injection. Core Audio reported 18,845,400 valid frames, 2,112 priming frames, and 232 remainder frames for the purchased file, its copy cleaned during curation, and the spike's output.
- **Comparison with the copy cleaned during curation (measured).** That copy, made by stream copy with FFmpeg, has the same media data and the same decoded PCM. FFmpeg, however, regrouped the samples from 837 into 14 chunks, replaced `iTunSMPB` with an edit list, and added sample-group boxes. The spike preserves the original sample tables and `iTunSMPB`.
- **Retained fields (measured).** `iTunSMPB`, `iTunNORM`, `stik` (Normal Music), `rtng`, `gnre`, `cpil`, `pgap`, and the descriptive fields were kept.
- **Protected audio (measured).** A sample entry renamed to `drms` was refused.

### Consequences

- Rebuilding the movie box removes purchase metadata without re-encoding. An allowlist of sample-entry children is required, because the purchased file carries undocumented boxes whose contents are unknown; a denylist built from the documentation would have kept five of them.
- Whether Music displays the spike's output as it displayed the copy cleaned during curation is unknown; it requires the live S3 environment.
- One purchased file is a narrow basis. Further purchases, especially of different dates or kinds, would show whether the structure varies.
- Whether `xid ` should be removed is a decision for the maintainer: exiftool describes it as an ISRC-like vendor identifier, which may contribute to catalog matching (inferred). The spike removes it.

## Failed Experiments and Corrections

- Shell variables shared between functions in `run-s1.sh` misdirected outputs; the function variables were renamed.
- Replacing an item by removal and appending broke idempotence; items are now replaced in place.
- The first padding absorption ignored the top-level `free` box after `moov`; relocation also had to use the original layout once that box was replaced.
- The first S5 check counted the retained media kind as residual store metadata; it is now reported separately.
- The first removal of purchase metadata deleted only `pinf` from the sample entry. The purchased file showed five further undocumented boxes, and the denylist was replaced by an allowlist.
- The first residual check of the purchased file took the account string from the cleaned file, which no longer contained it, and was therefore vacuous. It now takes the strings from the source.
- FFmpeg read standard input inside a loop over private files and consumed the list of file names. All FFmpeg invocations now pass `-nostdin`.
- WAV fixtures with 24 bits or six channels require `WAVE_FORMAT_EXTENSIBLE`; FFmpeg refused the first six-channel fixture.
- The first full-volume test ran FFmpeg before `afconvert`, so FFmpeg's partial file filled the volume; each encoder now runs on an empty volume.
- The free-space preflight preferred the capacity for important usage and therefore refused a volume that reported 0. This is recorded as the measured hazard behind the proposed policy; the spike was not changed.

## Architecture Assessment

**Retained with qualifications.** The Foundation-only parsing and rewriting planned for MP4Core, the AudioToolbox conversion planned for ConversionMac, and the FileManager timestamp operations planned for LibraryMac are supported by measurements on synthetic and private files. No external run-time tool or package dependency is needed. The qualifications are the open items below; none of them changes the planned target structure.

The Music integration of LibraryMac is not validated. Its interfaces exist, but the safety rules in AGENTS.md rest on behavior observed during manual curation and remain unmeasured by iLibrary.

### Decisions Proposed for M2

These are proposals for the maintainer's review, not decisions in force.

1. MP4Core rebuilds `moov`, copies other boxes by reference, relocates chunk offsets through the original layout, absorbs size changes into adjacent padding when possible, replaces items in place, and writes through a hidden sibling file that is parsed again before replacement. Offsets beyond 32 bits are converted to `co64` or refused; M2 decides which, with a synthetic test.
2. A Foundation-only FLAC metadata reader is placed in a Core target, either MP4Core or a new target, so that tags can be carried into converted files.
3. Version 0.1.0 converts mono and stereo only, refuses floating-point PCM, and verifies conversions by PCM digests, declared and decoded frame counts, and WAV and AIFF chunk lengths. Stream copies are verified by media-data and sample-table equality, not by lossy decoding.
4. Free space is checked against the plain available capacity of the destination volume.
5. Timestamp operations refuse missing paths and symbolic links, run after all writes and moves, and set folders after their contents.
6. Purchase metadata is removed by the atom list above and an allowlist of sample-entry children, with all padding zeroed, `iTunSMPB` and `stik` retained, and the treatment of `xid ` decided by the maintainer.

## Reproduction

The spike programs and scripts are in `scripts/spikes/`. Each script compiles its programs with `swiftc` into the ignored `artifacts/spikes/bin/`, regenerates its fixtures under `artifacts/spikes/`, and prints the results summarized here. `run-s2.sh` and `run-s4.sh` create, attach, and detach 8-MiB disk images inside `artifacts/spikes/`. When `reference-private/` contains `.m4a` or `.flac` files, `run-s1.sh`, `run-s2.sh`, and `run-s5.sh` also process copies of them inside `reference-private/work/`, identify them by hashes of their names, print no metadata value, and confirm that the originals are unchanged; otherwise they report the private inputs as unavailable.

```bash
scripts/spikes/run-s1.sh
scripts/spikes/run-s2.sh
scripts/spikes/run-s4.sh
scripts/spikes/run-s5.sh
```

`AutomationSpike.swift` is compiled and run directly; it does not launch Music.

```bash
swiftc -O -swift-version 5 scripts/spikes/AutomationSpike.swift -o artifacts/spikes/bin/AutomationSpike
```

```bash
artifacts/spikes/bin/AutomationSpike
```

Without private files, each script completed in less than 30 seconds; with them, S1 took several minutes. The final runs reported the results above, with the synthetic AAC decoding difference as the only failure, in S1.

## Next Gate

The maintainer reviews this report and decides the proposals above and the S3 test environment. M2 can then implement MP4Core and CatalogCore with synthetic tests. The live S3 measurements are required before M5. Further purchased files would strengthen S5 before M4.
