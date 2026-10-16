#!/bin/sh
# Compares a rewritten MP4 file with its source using independent references.
# Usage: verify-mp4.sh SOURCE REWRITTEN
# Prints one line per check and exits nonzero when the audio, the media data, or the chunk layout differ.
set -eu
bin=$(dirname "$0")/../../artifacts/spikes/bin
source=$1
rewritten=$2
status=0
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

pcm_ffmpeg() { ffmpeg -nostdin -v error -i "$1" -map 0:a:0 -f s32le -c:a pcm_s32le - | shasum -a 256 | cut -c1-16; }
pcm_coreaudio() {
    afconvert -f WAVE -d LEI32 "$1" "$scratch/decoded.wav" >/dev/null 2>&1 || { echo unavailable; return; }
    shasum -a 256 <"$scratch/decoded.wav" | cut -c1-16
}
mdat_hash() {
    "$bin/MP4Spike" mdat "$1" | while read -r offset length; do
        tail -c +"$((offset + 1))" "$1" | head -c "$length" | shasum -a 256 | cut -c1-16
    done | tr '\n' ' '
}
check() {
    if [ "$2" = "$3" ]; then echo "  same $1: $2"; else echo "  DIFF $1: $2 -> $3"; status=1; fi
}

check "decoded PCM (FFmpeg)" "$(pcm_ffmpeg "$source")" "$(pcm_ffmpeg "$rewritten")"
check "decoded PCM (Core Audio)" "$(pcm_coreaudio "$source")" "$(pcm_coreaudio "$rewritten")"
check "media data payload" "$(mdat_hash "$source")" "$(mdat_hash "$rewritten")"
check "chunk positions" "$("$bin/MP4Spike" chunks "$source" | shasum | cut -c1-16)" \
    "$("$bin/MP4Spike" chunks "$rewritten" | shasum | cut -c1-16)"
check "duration (ffprobe)" "$(ffprobe -v error -select_streams a:0 -show_entries stream=duration_ts,duration -of csv=p=0 "$source")" \
    "$(ffprobe -v error -select_streams a:0 -show_entries stream=duration_ts,duration -of csv=p=0 "$rewritten")"
# Private references are verified without printing any metadata value.
if [ "${VERIFY_PRIVATE:-0}" = 1 ]; then
    warnings=$(ffmpeg -nostdin -v warning -i "$rewritten" -map 0:a:0 -f null - 2>&1 | grep -v 'timescale not set' | head -3 || true)
    check "FFmpeg audio decode warnings" "" "$warnings"
    exit $status
fi
echo "  ffprobe tags: $(ffprobe -v error -show_entries format_tags -of compact=p=0 "$rewritten")"
echo "  exiftool: $(exiftool -q -q -s -Title -Artist -AlbumArtist -Album -Genre -Composer -Copyright -ContentCreateDate \
    -TrackNumber -DiskNumber -CoverArt -Comment "$rewritten" | tr -s ' ' | tr '\n' ';')"
echo "  AtomicParsley: $(AtomicParsley "$rewritten" -t 2>&1 | sed 's/Atom "\(....\)" contains: /\1=/' | tr '\n' ';')"
# FFmpeg reports "timescale not set" for any embedded cover, including covers written by AtomicParsley;
# that warning is excluded, and every other warning fails the check.
warnings=$(ffmpeg -nostdin -v warning -i "$rewritten" -map 0:a:0 -f null - 2>&1 | grep -v 'timescale not set' | head -3 || true)
check "FFmpeg audio decode warnings" "" "$warnings"
exit $status
