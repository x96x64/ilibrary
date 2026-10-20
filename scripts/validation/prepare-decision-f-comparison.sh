#!/bin/sh
# Build the transferable Decision F comparison bundle: the reference executable from the M11 merge commit, the
# candidate executable from the current commit, and 12 original synthetic tracks. Each executable is built from a
# verified `git archive` export of its commit. Never address Music, and stop before any separate-user operation.
set -eu
mode=${1:---dry-run}
case "$mode" in --dry-run|--prepare) ;; *) echo 'Usage: prepare-decision-f-comparison.sh [--dry-run|--prepare]'; exit 2 ;; esac
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
name=ilibrary-decision-f-comparison-v2
reference_commit=9821e686d169b7aee2448ceecf1f9cbe8654026f
candidate_commit=$(git rev-parse HEAD)
work="$root/artifacts/decision-f-comparison-v2-preparation"
echo "Plan: create $work with the bundle $name, its ZIP archive, and the SHA-256 file."
echo "Reference: $reference_commit (M11 merge). Candidate: $candidate_commit (the current commit)."
echo 'The bundle holds both release executables, 12 original synthetic tracks (3 albums by 2 artists), the comparison'
echo 'script, the collector, and the procedure. Music, every library, and every earlier bundle are not touched.'
[ "$mode" != --dry-run ] || { echo 'Dry run: nothing was created.'; exit 0; }
[ "$(uname -s)" = Darwin ] || { echo 'Preparation requires macOS.'; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo 'Commit every change before preparing the bundle.'; exit 1; }
[ ! -e "$work" ] || { echo "$work already exists; it is not overwritten."; exit 1; }
mkdir -p "$work/src-reference" "$work/src-candidate" "$work/tools"

# Exports whose embedded commit identifiers are verified, and isolated release builds of each.
for side in reference candidate; do
    commit=$([ "$side" = reference ] && echo "$reference_commit" || echo "$candidate_commit")
    git archive "$commit" >"$work/$side.tar"
    [ "$(git get-tar-commit-id <"$work/$side.tar")" = "$commit" ] || { echo "the $side export is not $commit"; exit 1; }
    tar -xf "$work/$side.tar" -C "$work/src-$side"
    touch "$work/build-$side-started"
    (cd "$work/src-$side" && swift build -c release --product ilibrary >"$work/build-$side.log" 2>&1)
done
reference_bin=$(cd "$work/src-reference" && swift build -c release --show-bin-path)
candidate_bin=$(cd "$work/src-candidate" && swift build -c release --show-bin-path)
for side in reference candidate; do
    bin=$([ "$side" = reference ] && echo "$reference_bin" || echo "$candidate_bin")
    [ "$bin/ilibrary" -nt "$work/build-$side-started" ] || { echo "the $side executable was not rebuilt"; exit 1; }
done
swiftc -O -swift-version 5 "$work/src-candidate/scripts/spikes/SynthAudio.swift" -o "$work/tools/SynthAudio"

# Original synthetic audio and tags, generated as for the M11 bundle under Decision F names.
python3 -I - "$work" "$work/src-candidate/scripts/validation" "$work/tools/SynthAudio" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

work, scripts, synth = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
ALBUMS = [
    ("iLibrary Decision F Synthetic Artist A", "Decision F Album 01", "2002-04-16"),
    ("iLibrary Decision F Synthetic Artist B", "Decision F Album 02", "1997-10-03"),
    ("iLibrary Decision F Synthetic Artist A", "Decision F Album 03", "2006-08-22"),
]
albums = []
seed = 2100
for number, (artist, album, date) in enumerate(ALBUMS, start=1):
    tracks = []
    for track in range(1, 5):
        title = f"Decision F Song {number:02d}-{track:02d}"
        tracks.append({"title": title})
        seed += 1
        wav = work / "wav" / f"{seed}.wav"
        wav.parent.mkdir(exist_ok=True)
        subprocess.run([synth, str(wav), "--rate", "44100", "--bits", "16", "--channels", "2",
                        "--frames", "4410", "--seed", str(seed)], check=True, stdout=subprocess.DEVNULL)
        flac = work / "flac" / artist / album / f"{track:02d} {title}.flac"
        flac.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([sys.executable, "-I", str(scripts / "synth_flac.py"), str(wav), str(flac),
                        f"ARTIST={artist}", f"ALBUMARTIST={artist}", f"ALBUM={album}", f"TITLE={title}",
                        "GENRE=Synthetic", f"TRACKNUMBER={track}", "TRACKTOTAL=4", "DISCNUMBER=1",
                        "DISCTOTAL=1"], check=True)
    albums.append({"album": album, "albumArtist": artist, "artist": artist, "genre": "Synthetic",
                   "releaseDate": date, "discs": [{"tracks": tracks}]})
catalog = {"format": "ilibrary-catalog-1", "albums": albums}
(work / "catalog.json").write_text(json.dumps(catalog, indent=2, sort_keys=True) + "\n")
PY
"$reference_bin/ilibrary" import "$work/flac" -o "$work/imported" >"$work/import.log"

# The bundle. Its scripts and procedure come from the candidate export, so that they match the candidate commit.
bundle="$work/$name"
mkdir -p "$bundle/bin/reference" "$bundle/bin/candidate"
cp "$reference_bin/ilibrary" "$bundle/bin/reference/ilibrary"
cp "$candidate_bin/ilibrary" "$bundle/bin/candidate/ilibrary"
cp "$work/catalog.json" "$bundle/catalog.json"
cp -R "$work/imported" "$bundle/staging"
"$bundle/bin/reference/ilibrary" apply "$bundle/catalog.json" "$bundle/staging" --rename --timestamps >"$work/apply.log"
"$bundle/bin/reference/ilibrary" validate "$bundle/catalog.json" "$bundle/staging" >"$work/validate.log"
"$bundle/bin/reference/ilibrary" export "$bundle/staging" -o "$work/strict-check.json" --strict >"$work/export-strict.log"
python3 -I - "$work/strict-check.json" <<'PY'
import json
import sys

albums = json.load(open(sys.argv[1]))["albums"]
dates = {album["releaseDate"] for album in albums}
assert len(albums) == 3 and sum(len(d["tracks"]) for a in albums for d in a["discs"]) == 12, "unexpected staging size"
assert len(dates) == 3 and all(len(date) == 10 for date in dates), "release dates are not distinct full dates"
PY
source="$work/src-candidate"
cp "$source/docs/decision-f-live-comparison.md" "$bundle/PROCEDURE.md"
cp "$source/scripts/validation/decision-f-compare.sh" "$bundle/compare.sh"
cp "$source/scripts/validation/decision_f_collect.py" "$bundle/df_collect.py"
cp "$source/scripts/validation/m11_collect.py" "$bundle/m11_collect.py"
chmod +x "$bundle/bin/reference/ilibrary" "$bundle/bin/candidate/ilibrary" "$bundle/compare.sh"
printf 'reference %s\ncandidate %s\n' "$reference_commit" "$candidate_commit" >"$bundle/SOURCES"
(cd "$bundle" && find . -type f ! -name SHA256SUMS ! -name .DS_Store | LC_ALL=C sort | sed 's|^\./||' |
    while IFS= read -r file; do shasum -a 256 "$file"; done >SHA256SUMS)
(cd "$work" && ditto -c -k --norsrc --noextattr --keepParent "$name" "$name.zip" &&
    shasum -a 256 "$name.zip" >"$name.zip.sha256")
echo "PASS: $name and its ZIP archive were created for reference $reference_commit and candidate $candidate_commit."
echo 'Music was not addressed. Stopping before any separate-user operation.'
