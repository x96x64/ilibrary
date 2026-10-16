#!/bin/sh
# Spike S2: lossless conversion to Apple Lossless through AudioToolbox, verified by decoded PCM equality.
# Sources are synthetic PCM written as WAV and AIFF by SynthAudio and encoded to FLAC by the reference
# flac tool. FFmpeg decodes sources and outputs independently of Core Audio.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
spikes=$root/scripts/spikes
bin=$root/artifacts/spikes/bin
work=$root/artifacts/spikes/s2
rm -rf "$work"
mkdir -p "$bin" "$work"
cd "$work"
swiftc -O -swift-version 5 "$spikes/SynthAudio.swift" -o "$bin/SynthAudio"
swiftc -O -swift-version 5 "$spikes/ConversionSpike.swift" -o "$bin/ConversionSpike"
convert() { "$bin/ConversionSpike" convert "$@"; }
ffpcm() { ffmpeg -nostdin -v error -i "$1" -map 0:a:0 -f s32le -c:a pcm_s32le - | shasum -a 256 | cut -c1-16; }
failures=0

# rate bits channels seconds
# Multichannel results are reported but not counted: channel order is examined separately.
for spec in "44100 16 2 30" "44100 24 2 30" "48000 24 2 30" "96000 24 2 30" "192000 24 2 10" "44100 16 1 30" "48000 24 6 10"; do
    set -- $spec
    name="r$1-b$2-c$3"
    frames=$(($1 * $4 + 1237))
    "$bin/SynthAudio" "$name.wav" --rate "$1" --bits "$2" --channels "$3" --frames "$frames" --seed "$2$3"
    "$bin/SynthAudio" "$name.aiff" --rate "$1" --bits "$2" --channels "$3" --frames "$frames" --seed "$2$3"
    flac -s -f --best "$name.wav" -o "$name.flac"
    for kind in wav aiff flac; do
        label="$name.$kind"
        if result=$(convert "$label" "$label.m4a" 2>&1); then
            source_hash=$(ffpcm "$label")
            output_hash=$(ffpcm "$label.m4a")
            if [ "$source_hash" = "$output_hash" ]; then independent="FFmpeg PCM equal"; else
                independent="FFmpeg PCM DIFFERS"; [ "$3" -le 2 ] && failures=$((failures + 1)); fi
            echo "== $label: $(echo "$result" | grep converted | sed 's/^converted //'); $independent; $(echo "$result" | grep timing)"
        else
            echo "== $label: FAIL: $result"; failures=$((failures + 1))
        fi
    done
done

# Channel order of the six-channel conversion, by per-channel hashes from FFmpeg.
for file in r48000-b24-c6.wav r48000-b24-c6.wav.m4a; do
    hashes=""
    for c in 0 1 2 3 4 5; do
        hashes="$hashes $(ffmpeg -nostdin -v error -i "$file" -af "pan=mono|c0=c$c" -f s32le -c:a pcm_s32le - | shasum | cut -c1-6)"
    done
    echo "== channel hashes $file ($(afinfo "$file" | sed -n 's/^Channel layout: //p')):$hashes"
done

# Repeated decoding of the same output must be deterministic.
for i in 1 2 3; do "$bin/ConversionSpike" pcm r96000-b24-c2.flac.m4a; done | sort | uniq -c | sed 's/^/== repeated decoding: /'

# Container metadata after conversion.
flac -s -f -T TITLE=Synthetic -T "ARTIST=Example Artist" --picture="$root/artifacts/spikes/s1/cover.png" r44100-b16-c2.wav -o tagged.flac 2>/dev/null ||
    { ffmpeg -nostdin -v error -y -f lavfi -i "color=c=0x336699:s=600x600" -frames:v 1 cover.png
      flac -s -f -T TITLE=Synthetic -T "ARTIST=Example Artist" --picture=cover.png r44100-b16-c2.wav -o tagged.flac; }
convert tagged.flac tagged.m4a >/dev/null
echo "== FLAC metadata (spike parser): $("$bin/ConversionSpike" flac-metadata tagged.flac | grep -v '^block' | tr '\n' ';')"
echo "== FLAC metadata (metaflac): $(metaflac --export-tags-to=- tagged.flac | tr '\n' ';') picture $(metaflac --list --block-type=PICTURE tagged.flac | grep -E 'MIME|data length' | tr -s ' ' | tr '\n' ' ')"
echo "== FLAC metadata (Core Audio): $("$bin/ConversionSpike" info tagged.flac | grep -E '^info|artwork' | tr '\n' ';')"
echo "== metadata in converted output (ffprobe): $(ffprobe -v error -show_entries format_tags:stream=codec_name -of compact=p=0 tagged.m4a | tr '\n' ' ')"

# Floating-point input is refused.
ffmpeg -nostdin -v error -y -i r44100-b16-c2.wav -c:a pcm_f32le float.wav
if out=$(convert float.wav float.m4a 2>&1); then echo "== float input: accepted (FAIL)"; failures=$((failures + 1)); else echo "== float input: refused: $out"; fi

# A truncated source (an incomplete download) must not be counted as converted.
size=$(stat -f %z r44100-b16-c2.flac)
head -c $((size / 3)) r44100-b16-c2.flac >truncated.flac
echo "== truncated FLAC (Core Audio view): $("$bin/ConversionSpike" pcm truncated.flac 2>&1)"
if out=$(convert truncated.flac truncated.m4a 2>&1); then echo "== truncated FLAC: accepted (FAIL): $out"; failures=$((failures + 1))
else echo "== truncated FLAC: refused: $(echo "$out" | grep 'conversion-spike:')"; fi
[ -e truncated.m4a ] || [ -e .truncated.m4a.partial ] && { echo "== truncated FLAC: output left behind (FAIL)"; failures=$((failures + 1)); }
size=$(stat -f %z r44100-b16-c2.wav)
head -c $((size / 3)) r44100-b16-c2.wav >truncated.wav
echo "== truncated WAV (Core Audio view): $("$bin/ConversionSpike" pcm truncated.wav 2>&1)"
if out=$(convert truncated.wav truncated-wav.m4a 2>&1); then echo "== truncated WAV: accepted: $(echo "$out" | grep converted)"
else echo "== truncated WAV: refused: $(echo "$out" | grep 'conversion-spike:')"; fi
head -c $((size / 3)) r44100-b16-c2.aiff >truncated.aiff
if out=$(convert truncated.aiff truncated-aiff.m4a 2>&1); then echo "== truncated AIFF: accepted: $(echo "$out" | grep converted)"
else echo "== truncated AIFF: refused: $(echo "$out" | grep 'conversion-spike:')"; fi

# A truncated output must fail verification.
size=$(stat -f %z r44100-b16-c2.flac.m4a)
head -c $((size / 3)) r44100-b16-c2.flac.m4a >truncated-output.m4a
echo "== truncated output (moov first): $("$bin/ConversionSpike" verify r44100-b16-c2.flac truncated-output.m4a 2>&1 || true)"
echo "== truncated output layout: $(swiftc -O -swift-version 5 "$spikes/MP4Spike.swift" -o "$bin/MP4Spike" && "$bin/MP4Spike" dump r44100-b16-c2.flac.m4a | head -1)"

# Conversion followed by tag rewriting leaves the decoded audio unchanged.
"$bin/MP4Spike" tag r48000-b24-c2.flac.m4a tagged-alac.m4a --set "©nam=Converted and Tagged" --track 1/1 >/dev/null
echo "== conversion then tagging: $("$bin/ConversionSpike" verify r48000-b24-c2.flac tagged-alac.m4a)"

# Writing into a nearly full volume: an 8 MiB disk image receives a 30-second 24-bit 96-kHz conversion.
image="$work/full.dmg"
mount="$work/full-volume"
hdiutil create -quiet -size 8m -fs APFS -volname iLibrarySpike "$image"
mkdir -p "$mount"
hdiutil attach -quiet -nobrowse -mountpoint "$mount" "$image"
echo "== small volume capacity: $("$bin/ConversionSpike" space "$mount")"
if out=$(convert r96000-b24-c2.flac "$mount/out.m4a" 2>&1); then echo "== small volume: accepted (FAIL): $out"; failures=$((failures + 1))
else echo "== small volume, preflight: $(echo "$out" | grep 'conversion-spike:')"; fi
# Bypass the preflight to measure each encoder's own behavior when the volume fills up.
for tool in afconvert ffmpeg; do
    if [ "$tool" = afconvert ]; then
        out=$(afconvert -f m4af -d alac r96000-b24-c2.flac "$mount/$tool.m4a" 2>&1) && code=0 || code=$?
    else
        out=$(ffmpeg -nostdin -v error -y -i r96000-b24-c2.flac -c:a alac "$mount/$tool.m4a" 2>&1) && code=0 || code=$?
    fi
    echo "== small volume, $tool: exit $code: $(echo "$out" | tail -1)"
    if [ -e "$mount/$tool.m4a" ]; then
        echo "== small volume, $tool output: $(stat -f %z "$mount/$tool.m4a") bytes; $("$bin/ConversionSpike" verify r96000-b24-c2.flac "$mount/$tool.m4a" 2>&1 || true)"
        rm -f "$mount/$tool.m4a"
    else
        echo "== small volume, $tool output: none left"
    fi
done
hdiutil detach -quiet "$mount"
rm -f "$image"

# Throughput on a five-minute 24-bit 96-kHz stereo source.
"$bin/SynthAudio" long.wav --rate 96000 --bits 24 --channels 2 --frames $((96000 * 300)) --seed 9
flac -s -f long.wav -o long.flac
echo "== five-minute 24-bit 96-kHz FLAC: $(/usr/bin/time -p "$bin/ConversionSpike" convert long.flac long.m4a 2>&1 | grep -E 'timing|real' | tr '\n' ' ')"
echo "== sizes: FLAC $(stat -f %z long.flac), ALAC $(stat -f %z long.m4a), WAV $(stat -f %z long.wav)"
# Private references: copies of FLAC files under reference-private/ are converted inside
# reference-private/work/s2/, and each result is compared with the existing private Apple Lossless files.
private=$root/reference-private
found=$(find "$private" -name '*.flac' -not -path "$private/work/*" 2>/dev/null | sort)
if [ -n "$found" ]; then
    mkdir -p "$private/work/s2"
    cd "$private/work/s2"
    existing=$(find "$private" -name '*.m4a' -not -path "$private/work/*" | sort)
    echo "$found" | while IFS= read -r file; do
        label="private-$(basename "$file" .flac | shasum | cut -c1-8)"
        cp "$file" "$label.flac"
        echo "== $label: $(convert "$label.flac" "$label.m4a" 2>&1 | grep -E 'converted|timing|conversion-spike' | tr '\n' ' ')"
        hash=$(ffpcm "$label.flac")
        [ "$hash" = "$(ffpcm "$label.m4a")" ] && echo "  FFmpeg PCM equal" || echo "  FFmpeg PCM DIFFERS"
        matches=$(echo "$existing" | while IFS= read -r alac; do
            [ "$(ffpcm "$alac")" = "$hash" ] && echo "$alac"
        done | wc -l | tr -d ' ')
        echo "  existing private Apple Lossless files with equal PCM: $matches"
        cmp -s "$file" "$label.flac" && echo "  original unchanged: yes"
    done
    cd "$work"
else
    echo "== private references: unavailable (no FLAC files under reference-private/)"
fi
echo "== failures: $failures"
