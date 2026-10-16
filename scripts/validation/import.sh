#!/bin/sh
# End-to-end validation of import on synthetic sources (macOS). SynthAudio writes deterministic PCM; flac and
# metaflac write tagged FLAC with a cover; afconvert and the spike's MP4 tool write an AAC file with synthetic
# purchase metadata. The release build of ilibrary imports them, and FFmpeg, ffprobe, exiftool, the spike's
# MP4 parser, and shasum check the results independently. Moves to the Trash are not exercised here, so that
# no synthetic file reaches the maintainer's Trash; the tests cover them with a substitute Trash.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$root/artifacts/validation/import
rm -rf "$work"
mkdir -p "$work/bin" "$work/Downloads/Synthetic Album" "$work/Downloads/iTunes" "$work/Refused"
cd "$root"
swift build -c release --product ilibrary >/dev/null
ilibrary=$(swift build -c release --show-bin-path)/ilibrary
swiftc -O -swift-version 5 scripts/spikes/SynthAudio.swift -o "$work/bin/SynthAudio"
swiftc -O -swift-version 5 scripts/spikes/MP4Spike.swift -o "$work/bin/MP4Spike"
failures=0
check() { if [ "$2" = "$3" ]; then echo "  pass: $1"; else echo "  FAIL: $1 ($2 != $3)"; failures=$((failures + 1)); fi; }
ffpcm() { ffmpeg -nostdin -v error -i "$1" -map 0:a:0 -f s32le -c:a pcm_s32le - | shasum -a 256 | cut -c1-16; }
probe() { ffprobe -v error -select_streams a:0 -show_entries stream="$2" -of csv=p=0 "$1"; }
mdat() { "$work/bin/MP4Spike" mdat "$1" | while read -r offset length; do tail -c +"$((offset + 1))" "$1" | head -c "$length" | shasum -a 256 | cut -c1-16; done; }

album="$work/Downloads/Synthetic Album"
ffmpeg -nostdin -v error -y -f lavfi -i "color=c=0x336699:s=300x300" -frames:v 1 "$work/cover.png"
"$work/bin/SynthAudio" "$work/a.wav" --rate 96000 --bits 24 --channels 2 --frames 192011 --seed 11
flac -s -f --best "$work/a.wav" -o "$album/01-First Song_1001.flac"
metaflac --set-tag="TITLE=First Song" --set-tag="ARTIST=Example Artist" --set-tag="ALBUM=Synthetic Album" \
    --set-tag="TRACKNUMBER=1" --set-tag="TRACKTOTAL=3" --set-tag="DATE=1980-06-01" --set-tag="COMMENT=synthetic comment" \
    --set-tag="X-SYNTHETIC-IDENTIFIER=synthetic-unknown-value" --import-picture-from="3||||$work/cover.png" \
    "$album/01-First Song_1001.flac"
"$work/bin/SynthAudio" "$album/02-Second Song.wav" --rate 44100 --bits 16 --channels 2 --frames 88213 --seed 12
"$work/bin/SynthAudio" "$album/03-Third Song.aiff" --rate 48000 --bits 24 --channels 1 --frames 96017 --seed 13
"$work/bin/SynthAudio" "$work/b.wav" --rate 44100 --bits 16 --channels 2 --frames 132017 --seed 14
afconvert -f m4af -d aac -b 256000 "$work/b.wav" "$work/b.m4a"
"$work/bin/MP4Spike" inject-store "$work/b.m4a" "$work/Downloads/iTunes/01 Purchased Song.m4a" >/dev/null
echo "notes" >"$work/Downloads/readme.txt"
rm -f "$work/a.wav" "$work/b.wav" "$work/b.m4a"
sources() { (cd "$work/Downloads" && find . -type f -exec shasum -a 256 {} + | sort); }
sources >"$work/sources-before.txt"

echo "== dry run"
"$ilibrary" import "$work/Downloads" -o "$work/Staging" --dry-run >"$work/dry-run.txt"
check "the dry run creates nothing" "$([ -e "$work/Staging" ] && echo created || echo absent)" absent
check "the dry run plans four files" "$(grep -c '^Import: 4 files planned, 0 refused, 1 other files left untouched' "$work/dry-run.txt")" 1

echo "== import"
"$ilibrary" import "$work/Downloads" -o "$work/Staging" >"$work/import.txt"
check "the import reports verification" "$(grep -c '^Imported and verified: 4 files' "$work/import.txt")" 1
out="$work/Staging/Synthetic Album"
for name in "01-First Song_1001.flac" "02-Second Song.wav" "03-Third Song.aiff"; do
    stem=${name%.*}
    check "decoded PCM of $stem (FFmpeg)" "$(ffpcm "$album/$name")" "$(ffpcm "$out/$stem.m4a")"
    check "codec of $stem" "$(probe "$out/$stem.m4a" codec_name)" alac
    check "sample rate and channels of $stem" "$(probe "$album/$name" sample_rate,channels)" "$(probe "$out/$stem.m4a" sample_rate,channels)"
done
check "bit depth of the 24-bit FLAC" "$(probe "$out/01-First Song_1001.m4a" bits_per_raw_sample)" 24
check "title carried (exiftool)" "$(exiftool -s3 -Title "$out/01-First Song_1001.m4a")" "First Song"
check "track carried (exiftool)" "$(exiftool -s3 -TrackNumber "$out/01-First Song_1001.m4a")" "1 of 3"
check "date carried (exiftool)" "$(exiftool -s3 -ContentCreateDate "$out/01-First Song_1001.m4a")" "1980:06:01 00:00:00Z"
check "comment not carried" "$(exiftool -s3 -Comment "$out/01-First Song_1001.m4a")" ""
check "unknown field not carried" "$(grep -c -a 'synthetic-unknown-value' "$out/01-First Song_1001.m4a" || true)" 0
check "cover carried byte for byte" "$(shasum <"$work/cover.png" | cut -c1-16)" "$(exiftool -b -CoverArt "$out/01-First Song_1001.m4a" | shasum | cut -c1-16)"
purchased="$work/Staging/iTunes/01 Purchased Song.m4a"
check "purchased file: media data unchanged" "$(mdat "$work/Downloads/iTunes/01 Purchased Song.m4a")" "$(mdat "$purchased")"
check "purchased file: decoded PCM (FFmpeg)" "$(ffpcm "$work/Downloads/iTunes/01 Purchased Song.m4a")" "$(ffpcm "$purchased")"
check "purchased file: account and owner strings" "$(grep -c -a -e 'synthetic.purchaser@example.invalid' -e 'Synthetic Purchaser' "$purchased" || true)" 0
check "purchased file: store tags (exiftool)" "$(exiftool -s -AppleStoreAccount -Owner -PurchaseDate -AppleStoreCatalogID "$purchased" | wc -l | tr -d ' ')" 0
check "no temporary files remain" "$(find "$work/Staging" -name '*ilibrary-partial*' | wc -l | tr -d ' ')" 0
check "the unrelated file was not imported" "$([ -e "$work/Staging/readme.txt" ] && echo imported || echo absent)" absent
sources >"$work/sources-after.txt"
check "sources unchanged" "$(shasum <"$work/sources-before.txt")" "$(shasum <"$work/sources-after.txt")"

echo "== selection and refusals"
"$ilibrary" import "$work/Downloads" -o "$work/Mora" --from mora >"$work/mora.txt"
check "--from mora imports FLAC only" "$(cd "$work/Mora" && find . -type f | sort | tr '\n' ';')" "./Synthetic Album/01-First Song_1001.m4a;"
ffmpeg -nostdin -v error -y -i "$album/02-Second Song.wav" -c:a pcm_f32le "$work/Refused/float.wav"
if "$ilibrary" import "$work/Refused" -o "$work/RefusedOut" >"$work/refused.txt" 2>&1; then check "floating-point PCM is refused" 0 1; else check "floating-point PCM is refused" 1 1; fi
check "nothing is created after a refusal" "$([ -e "$work/RefusedOut" ] && echo created || echo absent)" absent
if "$ilibrary" import "$work/Downloads" -o "$work/Staging" >/dev/null 2>&1; then check "existing outputs are refused" 0 1; else check "existing outputs are refused" 1 1; fi
echo "== failures: $failures"
[ "$failures" -eq 0 ]
