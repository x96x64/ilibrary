#!/bin/sh
# Spike S1: MP4 item-list rewriting and chunk-offset relocation on synthetic files.
# Fixtures are generated from synthetic PCM; Core Audio, FFmpeg, and AtomicParsley produce the
# container layouts, and FFmpeg, Core Audio, exiftool, and AtomicParsley verify the results.
# Optional private references: every .m4a file under reference-private/s1/ is copied and rewritten.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
spikes=$root/scripts/spikes
bin=$root/artifacts/spikes/bin
work=$root/artifacts/spikes/s1
rm -rf "$work"
mkdir -p "$bin" "$work"
cd "$work"
swiftc -O -swift-version 5 "$spikes/SynthAudio.swift" -o "$bin/SynthAudio"
swiftc -O -swift-version 5 "$spikes/MP4Spike.swift" -o "$bin/MP4Spike"

"$bin/SynthAudio" s16.wav --rate 44100 --bits 16 --channels 2 --frames 1323017 --seed 1
"$bin/SynthAudio" s24.wav --rate 48000 --bits 24 --channels 2 --frames 1440011 --seed 2
afconvert -f m4af -d alac s16.wav af-alac16.m4a
afconvert -f m4af -d alac s24.wav af-alac24.m4a
afconvert -f m4af -d aac -b 256000 s16.wav af-aac.m4a
ffmpeg -nostdin -v error -y -i s16.wav -c:a alac ff-alac.m4a
ffmpeg -nostdin -v error -y -i s16.wav -c:a alac -movflags +faststart ff-alac-fast.m4a
ffmpeg -nostdin -v error -y -i s16.wav -c:a aac -b:a 256k -movflags +faststart ff-aac-fast.m4a
cp ff-alac.m4a ap-alac.m4a
AtomicParsley ap-alac.m4a --title "Synthetic Song" --comment "Remove me" --overWrite >/dev/null
ffmpeg -nostdin -v error -y -f lavfi -i "color=c=0x336699:s=600x600" -frames:v 1 cover.png

failures=0
run() {
    run_label=$1
    run_input=$2
    shift 2
    run_output="$run_label.m4a"
    echo "== $run_label: $("$bin/MP4Spike" tag "$run_input" "$run_output" "$@")"
    "$bin/MP4Spike" dump "$run_output" | head -1
    if "$spikes/verify-mp4.sh" "$run_input" "$run_output"; then echo "  result: pass"; else echo "  result: FAIL"; failures=$((failures + 1)); fi
}

for source in af-alac16 af-alac24 af-aac ff-alac ff-alac-fast ff-aac-fast ap-alac; do
    run "$source.full" "$source.m4a" \
        --set "©nam=Behind the Mask [Synthetic Mix (Demo)]" --set "©ART=Example Artist" \
        --set "aART=Example Artist" --set "©alb=Example Album" --set "©gen=Pop" \
        --set "©wrt=Example Writer, Second Writer" --set "cprt=℗ 1980 Example Records, Inc." \
        --set "©day=1980-06-01T00:00:00Z" --track 3/9 --disc 1/2 --cover cover.png --remove "©cmt"
    run "$source.small-absorb" "$source.m4a" --set "©nam=Short" --padding absorb
    run "$source.co64" "$source.m4a" --set "©nam=Wide Offsets" --force-co64 yes
done

# Repeated application must be stable: tagging an output again with the same values yields the same bytes.
"$bin/MP4Spike" tag af-alac16.full.m4a again.m4a --set "©nam=Behind the Mask [Synthetic Mix (Demo)]" >/dev/null
if cmp -s af-alac16.full.m4a again.m4a; then echo "== idempotence: identical bytes"; else
    echo "== idempotence: bytes differ ($(cmp af-alac16.full.m4a again.m4a | head -1))"
fi

# Corrupt inputs must be rejected rather than rewritten.
head -c 3000 af-alac16.m4a >truncated.m4a
if "$bin/MP4Spike" tag truncated.m4a never.m4a --set "©nam=X" 2>truncated.err; then
    echo "== truncated input: accepted (FAIL)"; failures=$((failures + 1))
else echo "== truncated input: rejected: $(cat truncated.err)"; fi
[ ! -e never.m4a ] && [ ! -e .never.m4a.partial ] && echo "== truncated input: no output written"

# Private references: copies of every .m4a file under reference-private/ are rewritten inside
# reference-private/work/; originals are never opened for writing, and names are reported as hashes.
private=$root/reference-private
found=$(find "$private" -name '*.m4a' -not -path "$private/work/*" 2>/dev/null | sort)
if [ -n "$found" ]; then
    mkdir -p "$private/work/s1"
    cd "$private/work/s1"
    echo "$found" | while IFS= read -r file; do
        label="private-$(basename "$file" .m4a | shasum | cut -c1-8)"
        cp "$file" "$label.source.m4a"
        echo "== $label: $("$bin/MP4Spike" dump "$label.source.m4a" | head -1)"
        echo "  rewrite: $("$bin/MP4Spike" tag "$label.source.m4a" "$label.m4a" --set "©nam=Private Reference Title")"
        if VERIFY_PRIVATE=1 "$spikes/verify-mp4.sh" "$label.source.m4a" "$label.m4a" >verify.txt; then
            sed 's/^/  /' verify.txt; echo "  result: pass"
        else sed 's/^/  /' verify.txt; echo "  result: FAIL"; fi
        cmp -s "$file" "$label.source.m4a" && echo "  original unchanged: yes"
    done
    cd "$work"
else
    echo "== private references: unavailable (no .m4a files under reference-private/)"
fi
echo "== failures: $failures"
