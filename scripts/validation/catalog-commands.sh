#!/bin/sh
# End-to-end validation of the catalog commands on a synthetic library of decodable audio (macOS).
# SynthAudio writes deterministic PCM; afconvert encodes Apple Lossless and AAC; FFmpeg writes the
# initial tags. The release build of ilibrary then exports, reapplies, edits, renames, and dates the
# library, and FFmpeg, Core Audio, cmp, and stat check the results independently. Every file is
# created under artifacts/validation/, which is ignored by Git and removed at the start of each run.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$root/artifacts/validation/catalog-commands
rm -rf "$work"
mkdir -p "$work/bin" "$work/library"
cd "$root"
swift build -c release --product ilibrary >/dev/null
ilibrary=$(swift build -c release --show-bin-path)/ilibrary
swiftc -O -swift-version 5 scripts/spikes/SynthAudio.swift -o "$work/bin/SynthAudio"
swiftc -O -swift-version 5 scripts/spikes/MP4Spike.swift -o "$work/bin/MP4Spike"
failures=0
check() { if [ "$2" = "$3" ]; then echo "  pass: $1"; else echo "  FAIL: $1 ($2 != $3)"; failures=$((failures + 1)); fi; }
ffpcm() { ffmpeg -nostdin -v error -i "$1" -map 0:a:0 -f s32le -c:a pcm_s32le - | shasum -a 256 | cut -c1-16; }
# Core Audio's decoding of AAC is not reproducible bit for bit (architecture spike, S1); it is compared for
# Apple Lossless only. Media-data payloads are compared with the spike's independent MP4 parser.
capcm() {
    [ "$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$1")" = alac ] || { echo aac; return; }
    afconvert -f WAVE -d LEI32 "$1" "$work/decoded.wav" >/dev/null 2>&1 && shasum -a 256 <"$work/decoded.wav" | cut -c1-16
}
mdat() {
    "$work/bin/MP4Spike" mdat "$1" | while read -r offset length; do
        tail -c +"$((offset + 1))" "$1" | head -c "$length" | shasum -a 256 | cut -c1-16
    done | tr -d '\n'
}

# album folder|album|album artist|date|codec|disc/total|track/total|title|composer
while IFS='|' read -r folder album artist date codec disc track title composer; do
    mkdir -p "$work/library/$folder"
    base="$work/library/$folder/$(echo "$track" | cut -d/ -f1)-$title"
    "$work/bin/SynthAudio" "$work/source.wav" --rate 44100 --bits 16 --channels 2 --frames 220517 --seed "$(echo "$title" | cksum | cut -c1-6)"
    afconvert -f m4af -d "$codec" "$work/source.wav" "$work/encoded.m4a"
    ffmpeg -nostdin -v error -y -i "$work/encoded.m4a" -c copy -metadata title="$title" -metadata artist="$artist" \
        -metadata album_artist="$artist" -metadata album="$album" -metadata date="$date" -metadata genre=Pop \
        -metadata composer="$composer" -metadata copyright="℗ ${date%%-*} Example Records, Inc." \
        -metadata track="$track" -metadata disc="$disc" "$base.m4a"
done <<'LIST'
Download One|Synthetic Album|Example Artist|1980-06-01T00:00:00Z|alac|1/1|1/3|First Song|Example Writer
Download One|Synthetic Album|Example Artist|1980-06-01T00:00:00Z|alac|1/1|2/3|Second Song|Second Writer
Download One|Synthetic Album|Example Artist|1980-06-01T00:00:00Z|alac|1/1|3/3|Third Song|Example Writer
Download Two|Double Album|Example Artist|1982-11-30T00:00:00Z|aac|1/2|1/2|Opening|Example Writer
Download Two|Double Album|Example Artist|1982-11-30T00:00:00Z|aac|1/2|2/2|Middle|Example Writer
Download Two|Double Album|Example Artist|1982-11-30T00:00:00Z|aac|2/2|1/2|Return|Example Writer
Download Two|Double Album|Example Artist|1982-11-30T00:00:00Z|aac|2/2|2/2|Closing|Example Writer
LIST
rm -f "$work/source.wav" "$work/encoded.m4a"
find "$work/library" -name '*.m4a' | sort >"$work/files.txt"
while IFS= read -r file; do echo "$(ffpcm "$file") $(capcm "$file") $(mdat "$file")"; done <"$work/files.txt" >"$work/pcm-before.txt"
snapshot() { (cd "$work/library" && find . -type f -name '*.m4a' -exec shasum -a 256 {} + | sort); }
snapshot >"$work/bytes-before.txt"

echo "== export and reapplication"
"$ilibrary" export "$work/library" -o "$work/catalog.json" >"$work/export.txt"
"$ilibrary" validate "$work/catalog.json" "$work/library" >"$work/validate.txt" && check "validate exit status" 0 0 || check "validate exit status" 0 1
"$ilibrary" apply "$work/catalog.json" "$work/library" >"$work/apply-1.txt"
check "planned tag changes after export" "$(grep -c '^Tag changes: 0 of 7 files' "$work/apply-1.txt")" 1
snapshot >"$work/bytes-after-reapply.txt"
check "file bytes after reapplication" "$(shasum <"$work/bytes-before.txt")" "$(shasum <"$work/bytes-after-reapply.txt")"
"$ilibrary" export "$work/library" -o "$work/catalog-2.json" >/dev/null
check "catalog after reapplication" "$(shasum <"$work/catalog.json" | cut -c1-16)" "$(shasum <"$work/catalog-2.json" | cut -c1-16)"

echo "== edited catalog"
python3 -I - "$work/catalog.json" "$work/catalog-edited.json" <<'PY'
import json, sys
catalog = json.load(open(sys.argv[1]))
album = next(a for a in catalog["albums"] if a["album"] == "Synthetic Album")
album["discs"][0]["tracks"][1]["title"] = "Second Song (Revised)"
album["copyright"] = "℗ 1981 Example Records, Inc."
catalog["artists"] = {"Example Artist": {"folderDate": "1979-08-10"}}
json.dump(catalog, open(sys.argv[2], "w"), ensure_ascii=False, indent=2)
PY
"$ilibrary" apply "$work/catalog-edited.json" "$work/library" --dry-run >"$work/dry-run.txt"
check "dry run leaves bytes unchanged" "$(snapshot | shasum)" "$(shasum <"$work/bytes-before.txt")"
check "dry run lists three changed files" "$(grep -c '^Tag changes: 3 of 7 files' "$work/dry-run.txt")" 1
TZ=Asia/Tokyo "$ilibrary" apply "$work/catalog-edited.json" "$work/library" --rename --timestamps >"$work/apply-2.txt"
check "apply reports verification" "$(grep -c '^Applied: 3 files rewritten and verified, 7 moved, 10 paths dated' "$work/apply-2.txt")" 1
find "$work/library" -name '*.m4a' | sort >"$work/files-after.txt"
while IFS= read -r file; do echo "$(ffpcm "$file") $(capcm "$file") $(mdat "$file")"; done <"$work/files-after.txt" >"$work/pcm-after.txt"
check "decoded PCM after edits and moves (FFmpeg)" "$(cut -d' ' -f1 "$work/pcm-before.txt" | sort | shasum)" "$(cut -d' ' -f1 "$work/pcm-after.txt" | sort | shasum)"
check "decoded PCM of Apple Lossless (Core Audio)" "$(cut -d' ' -f2 "$work/pcm-before.txt" | sort | shasum)" "$(cut -d' ' -f2 "$work/pcm-after.txt" | sort | shasum)"
check "media-data payloads (spike parser)" "$(cut -d' ' -f3 "$work/pcm-before.txt" | sort | shasum)" "$(cut -d' ' -f3 "$work/pcm-after.txt" | sort | shasum)"
check "renamed paths" "$(cd "$work/library" && find "Example Artist" -name '*.m4a' | sort | tr '\n' ';')" \
    "Example Artist/Double Album/1-01 Opening.m4a;Example Artist/Double Album/1-02 Middle.m4a;Example Artist/Double Album/2-01 Return.m4a;Example Artist/Double Album/2-02 Closing.m4a;Example Artist/Synthetic Album/01 First Song.m4a;Example Artist/Synthetic Album/02 Second Song (Revised).m4a;Example Artist/Synthetic Album/03 Third Song.m4a;"
check "title read by FFmpeg" "$(ffprobe -v error -show_entries format_tags=title -of csv=p=0 "$work/library/Example Artist/Synthetic Album/02 Second Song (Revised).m4a")" "Second Song (Revised)"
check "copyright read by exiftool" "$(exiftool -s3 -Copyright "$work/library/Example Artist/Synthetic Album/01 First Song.m4a")" "℗ 1981 Example Records, Inc."
dates() { TZ=Asia/Tokyo stat -f '%SB %Sm' -t '%Y-%m-%dT%H:%M:%S' "$1"; }
check "file dates (stat)" "$(dates "$work/library/Example Artist/Synthetic Album/01 First Song.m4a")" "1980-06-01T00:00:00 1980-06-01T00:00:00"
check "album folder dates (stat)" "$(dates "$work/library/Example Artist/Double Album")" "1982-11-30T00:00:00 1982-11-30T00:00:00"
check "artist folder dates (stat)" "$(dates "$work/library/Example Artist")" "1979-08-10T00:00:00 1979-08-10T00:00:00"
"$ilibrary" apply "$work/catalog-edited.json" "$work/library" --rename >"$work/apply-3.txt"
check "reapplication of the edited catalog" "$(grep -c -e '^Tag changes: 0 of 7 files' -e '^Moves: 0 of 7 files' "$work/apply-3.txt")" 2

echo "== refusals"
mkdir -p "$work/library/Links"
ln -s "$work/library/Example Artist/Synthetic Album/01 First Song.m4a" "$work/library/Links/link.m4a"
before=$(snapshot | shasum)
if "$ilibrary" apply "$work/catalog-edited.json" "$work/library" >/dev/null 2>&1; then check "a symbolic link is refused" 0 1; else check "a symbolic link is refused" 1 1; fi
check "nothing changed after the refusal" "$(snapshot | shasum)" "$before"
rm -r "$work/library/Links"
if "$ilibrary" timestamps "$work/catalog-edited.json" "$work/library/Missing Artist" >/dev/null 2>&1; then check "a missing path is refused" 0 1; else check "a missing path is refused" 1 1; fi
check "the missing path was not created" "$([ -e "$work/library/Missing Artist" ] && echo created || echo absent)" absent
echo "== failures: $failures"
[ "$failures" -eq 0 ]
