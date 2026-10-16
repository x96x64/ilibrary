#!/bin/sh
# Spike S5: removal of iTunes Store purchase metadata without re-encoding.
# No purchased file is used. Synthetic placeholders with the structure that exiftool documents for
# purchased files (item-list store atoms and a pinf box in the mp4a sample entry) are injected into
# synthetic AAC files and then removed. Optional private references: .m4a files under reference-private/s5/.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
spikes=$root/scripts/spikes
bin=$root/artifacts/spikes/bin
work=$root/artifacts/spikes/s5
rm -rf "$work"
mkdir -p "$bin" "$work"
cd "$work"
swiftc -O -swift-version 5 "$spikes/SynthAudio.swift" -o "$bin/SynthAudio"
swiftc -O -swift-version 5 "$spikes/MP4Spike.swift" -o "$bin/MP4Spike"
"$bin/SynthAudio" s16.wav --rate 44100 --bits 16 --channels 2 --frames 1323017 --seed 5
afconvert -f m4af -d aac -b 256000 s16.wav af-aac.m4a
ffmpeg -nostdin -v error -y -i s16.wav -c:a aac -b:a 256k -movflags +faststart ff-aac-fast.m4a
ffmpeg -nostdin -v error -y -i s16.wav -c:a aac -b:a 256k ff-aac-end.m4a

failures=0
store_tags="-AppleStoreAccount -Owner -PurchaseDate -AppleStoreCatalogID -ArtistID -PlaylistID -GenreID \
-AppleStoreCountry -ComposerID -AppleStoreAccountType -ISRC -UserID -UserName -KeyID \
-InitializationVector -SchemeType -OriginalFormat -Rights -Private"
for name in af-aac ff-aac-fast ff-aac-end; do
    "$bin/MP4Spike" inject-store "$name.m4a" "$name.store.m4a" >/dev/null
    echo "== $name: injected layout: $("$bin/MP4Spike" dump "$name.store.m4a" | head -1)"
    # shellcheck disable=SC2086
    echo "  exiftool before: $(exiftool -q -q -s $store_tags "$name.store.m4a" | cut -d: -f1 | tr -s ' ' | tr '\n' ' ')"
    echo "  account string occurrences before: $(grep -o -a 'synthetic.purchaser@example.invalid' "$name.store.m4a" | wc -l | tr -d ' ')"
    echo "  $("$bin/MP4Spike" strip-store "$name.store.m4a" "$name.clean.m4a" | tr '\n' ' ')"
    # shellcheck disable=SC2086
    remaining=$(exiftool -q -q -s $store_tags "$name.clean.m4a" | cut -d: -f1 | tr -s ' ' | tr '\n' ' ')
    echo "  exiftool after: ${remaining:-none}"
    account=$(grep -c -a -e 'synthetic.purchaser@example.invalid' -e 'Synthetic Purchaser' "$name.clean.m4a" || true)
    echo "  account and name occurrences after: $account"
    echo "  retained media kind (stik): $(exiftool -q -q -s3 -MediaType "$name.clean.m4a")"
    echo "  ffprobe after: $(ffprobe -v error -show_entries format_tags -of compact=p=0 "$name.clean.m4a")"
    if [ -n "$remaining" ] || [ "$account" != 0 ]; then failures=$((failures + 1)); echo "  result: FAIL"; fi
    if "$spikes/verify-mp4.sh" "$name.store.m4a" "$name.clean.m4a" >verify.txt; then
        grep -E 'same|DIFF' verify.txt; echo "  result: pass"
    else
        grep -E 'same|DIFF' verify.txt; echo "  result: FAIL"; failures=$((failures + 1))
    fi
    # The cleaned file must decode identically to the file before injection as well.
    "$spikes/verify-mp4.sh" "$name.m4a" "$name.clean.m4a" | grep -E 'PCM|payload' | sed 's/^/  versus original: /'
done

# Protected sample entries are refused.
"$bin/MP4Spike" dump ff-aac-fast.m4a >/dev/null
sed 's/mp4a/drms/' ff-aac-fast.store.m4a >drms.m4a 2>/dev/null || true
if "$bin/MP4Spike" strip-store drms.m4a never.m4a 2>drms.err; then echo "== protected entry: accepted (FAIL)"
    failures=$((failures + 1))
else echo "== protected entry: $(cat drms.err)"; fi

# Private references: copies of .m4a files under reference-private/ that carry purchase metadata are
# cleaned inside reference-private/work/. No metadata value is printed; names are reported as hashes.
private=$root/reference-private
found=$(find "$private" -name '*.m4a' -not -path "$private/work/*" 2>/dev/null | sort)
if [ -n "$found" ]; then
    mkdir -p "$private/work/s5"
    cd "$private/work/s5"
    echo "$found" | while IFS= read -r file; do
        "$bin/MP4Spike" dump "$file" | grep -q -E '^ +(apID|ownr|pinf)' || continue
        label="private-$(basename "$file" .m4a | shasum | cut -c1-8)"
        cp "$file" "$label.source.m4a"
        echo "== $label: $("$bin/MP4Spike" dump "$label.source.m4a" | head -1)"
        echo "  $("$bin/MP4Spike" strip-store "$label.source.m4a" "$label.clean.m4a" | tr '\n' ' ')"
        python3 -I "$spikes/inspect-boxes.py" "$label.source.m4a" | tail -2 | sed 's/^/  before: /'
        python3 -I "$spikes/inspect-boxes.py" "$label.source.m4a" "$label.clean.m4a" | tail -1 | sed 's/^/  after: /'
        # shellcheck disable=SC2086
        echo "  exiftool tags after: $(exiftool -q -q -s $store_tags "$label.clean.m4a" | cut -d: -f1 | tr -s ' ' | tr '\n' ' ')"
        echo "  retained items: $("$bin/MP4Spike" dump "$label.clean.m4a" | sed -n '/ilst/,$p' | grep -E '^ {8}' | sed -E 's/ = .*//' | tr -s ' ' | tr '\n' ' ')"
        echo "  sample entry after: $("$bin/MP4Spike" dump "$label.clean.m4a" | sed -n '/stsd/,/stts/p' | sed -E 's/@[0-9]+ //' | tr -s ' ' | tr '\n' ';')"
        VERIFY_PRIVATE=1 "$spikes/verify-mp4.sh" "$label.source.m4a" "$label.clean.m4a" | sed 's/^/  /'
        cmp -s "$file" "$label.source.m4a" && echo "  original unchanged: yes"
    done
    cd "$work"
else
    echo "== private references: unavailable (no .m4a files under reference-private/)"
fi
echo "== failures: $failures"
