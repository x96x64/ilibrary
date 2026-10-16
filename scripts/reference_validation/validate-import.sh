#!/bin/sh
# Validates import against private references: one FLAC file from reference-private/mora/ and one purchased
# M4A file from reference-private/itunes/. Only copies inside reference-private/work/ are processed, and the
# originals are compared by checksum before and after. No metadata value, title, file name, or account detail
# is printed; files are identified by hashes of their names, and unknown FLAC fields are only counted. The
# working copies are removed at the end. Without private files, the inputs are reported as unavailable.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
private=$root/reference-private
work=$private/work/import-validation
cd "$root"
git check-ignore -q reference-private/work/x || { echo "reference-private/ is not ignored; stopping"; exit 1; }
swift build -c release --product ilibrary >/dev/null
ilibrary=$(swift build -c release --show-bin-path)/ilibrary
label() { basename "$1" | shasum | cut -c1-8; }
flac=$(find "$private/mora" -type f -name '*.flac' -not -path "$private/work/*" 2>/dev/null | sort | head -1)
# The purchased file is the first whose dry run, which reads but never writes, removes purchase items.
purchased=$(find "$private/itunes" -type f -name '*.m4a' 2>/dev/null | sort | while IFS= read -r candidate; do
    if "$ilibrary" import "$candidate" -o "$private/dry-run-only" --from itunes --dry-run 2>/dev/null </dev/null |
        grep -q -E 'removes [1-9][0-9]* purchase items'; then
        echo "$candidate"
        break
    fi
done)
if [ -z "$flac" ] || [ -z "$purchased" ]; then
    echo "== private references: unavailable (a mora FLAC file and a purchased M4A file are required)"
    exit 0
fi
before=$(shasum -a 256 "$flac" "$purchased" | cut -c1-64)
rm -rf "$work"
mkdir -p "$work/sources/mora" "$work/sources/itunes"
cp "$flac" "$work/sources/mora/$(label "$flac").flac"
cp "$purchased" "$work/sources/itunes/$(label "$purchased").m4a"
failures=0
check() { if [ "$2" = "$3" ]; then echo "  pass: $1"; else echo "  FAIL: $1"; failures=$((failures + 1)); fi; }
ffpcm() { ffmpeg -nostdin -v error -i "$1" -map 0:a:0 -f s32le -c:a pcm_s32le - | shasum -a 256 | cut -c1-16; }
probe() { ffprobe -v error -select_streams a:0 -show_entries stream="$2" -of csv=p=0 "$1"; }

echo "== private import of copies ($(label "$flac").flac, $(label "$purchased").m4a)"
"$ilibrary" import "$work/sources" -o "$work/staging" >"$work/import.txt" 2>&1 || true
check "import reports two verified files" "$(grep -c '^Imported and verified: 2 files' "$work/import.txt")" 1
sed -n 's/.*; \([0-9]* tags carried.*\)$/  FLAC tags: \1/p' "$work/import.txt"
sed -n 's/.*\(removes [0-9]* purchase items and [0-9]* sample-entry boxes\)$/  purchased copy: \1/p' "$work/import.txt"
converted="$work/staging/mora/$(label "$flac").m4a"
copied="$work/staging/itunes/$(label "$purchased").m4a"
check "FLAC: decoded PCM equal (FFmpeg)" "$(ffpcm "$work/sources/mora/$(label "$flac").flac")" "$(ffpcm "$converted")"
check "FLAC: output codec is Apple Lossless" "$(probe "$converted" codec_name)" alac
check "FLAC: rate, channels, and depth kept" "$(probe "$work/sources/mora/$(label "$flac").flac" sample_rate,channels,bits_per_raw_sample)" \
    "$(probe "$converted" sample_rate,channels,bits_per_raw_sample)"
check "purchased: decoded PCM equal (FFmpeg)" "$(ffpcm "$work/sources/itunes/$(label "$purchased").m4a")" "$(ffpcm "$copied")"
check "purchased: purchaser strings absent" "$(python3 -I scripts/spikes/inspect-boxes.py "$work/sources/itunes/$(label "$purchased").m4a" "$copied" | tail -1 | grep -c "{'account': 0, 'owner': 0}")" 1
check "no temporary files remain" "$(find "$work/staging" -name '*ilibrary-partial*' | wc -l | tr -d ' ')" 0
check "originals unchanged" "$(shasum -a 256 "$flac" "$purchased" | cut -c1-64)" "$before"
rm -rf "$work"
rmdir "$private/work" 2>/dev/null || true
echo "== working copies removed; failures: $failures"
[ "$failures" -eq 0 ]
