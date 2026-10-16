#!/bin/sh
# Validates MP4Core and FLACCore against private reference files under reference-private/.
# Only copies inside reference-private/work/ are processed; originals are compared byte for byte
# afterwards. No metadata value, title, file name, or account detail is printed; files are identified
# by hashes of their names. The working copies are removed at the end. Without private files, the
# inputs are reported as unavailable and the script succeeds.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
private=$root/reference-private
work=$private/work/reference-validation
cd "$root"
originals=$(find "$private" -type f \( -name '*.m4a' -o -name '*.flac' \) -not -path "$private/work/*" 2>/dev/null | sort || true)
if [ -z "$originals" ]; then
    echo "== private references: unavailable (no .m4a or .flac files under reference-private/)"
    exit 0
fi
swift build --product ReferenceProbe >/dev/null
probe=$(swift build --show-bin-path)/ReferenceProbe
rm -rf "$work"
mkdir -p "$work"
ffpcm() { ffmpeg -nostdin -v error -i "$1" -map 0:a:0 -f s32le -c:a pcm_s32le - | shasum -a 256 | cut -c1-16; }
echo "$originals" | while IFS= read -r file; do
    label=$(basename "$file" | shasum | cut -c1-8)
    case "$file" in
    *.flac)
        cp "$file" "$work/$label.flac"
        echo "== $label (FLAC)"
        "$probe" flac "$work/$label.flac" | sed 's/^/  /' || echo "  FAIL: refused"
        ;;
    *.m4a)
        cp "$file" "$work/$label.m4a"
        if "$probe" purchase-metadata "$work/$label.m4a" "$work/$label.clean.m4a" >"$work/$label.txt" 2>&1; then
            echo "== $label (MP4): processed"
            grep -E '^(layout|sample entries|removed|zeroed|written|stream differences)' "$work/$label.txt" | sed 's/^/  /'
            if [ -n "$(sed -n 's/^removed items: //p' "$work/$label.txt")" ]; then
                python3 -I "$root/scripts/spikes/inspect-boxes.py" "$work/$label.m4a" "$work/$label.clean.m4a" | tail -1 | sed 's/^/  purchaser strings after removal: /'
            fi
            [ "$(ffpcm "$work/$label.m4a")" = "$(ffpcm "$work/$label.clean.m4a")" ] && echo "  decoded PCM (FFmpeg): equal" || echo "  decoded PCM (FFmpeg): DIFFERS"
        else
            echo "== $label (MP4): FAIL: $(tail -1 "$work/$label.txt")"
        fi
        "$probe" retitle "$work/$label.m4a" "$work/$label.retitled.m4a" | grep -E '^(written|stream differences)' | sed 's/^/  retitle: /'
        ;;
    esac
    cmp -s "$file" "$work/$label.$(echo "$file" | sed 's/.*\.//')" && echo "  original unchanged: yes" || echo "  original unchanged: NO"
done
rm -rf "$work"
rmdir "$private/work" 2>/dev/null || true
echo "== working copies removed"
