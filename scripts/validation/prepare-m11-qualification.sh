#!/bin/sh
# Build the transferable M11 backup and inventory qualification bundle, version 2, from synthetic audio.
# Never address Music, and stop before any separate-user operation.
set -eu
mode=${1:---dry-run}
case "$mode" in --dry-run|--prepare) ;; *) echo 'Usage: prepare-m11-qualification.sh [--dry-run|--prepare]'; exit 2 ;; esac
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
name=ilibrary-m11-qualification-v2
echo "Plan: create artifacts/m11-qualification-v2-preparation with the bundle $name, its ZIP archive, and the SHA-256 file."
echo 'The bundle holds the release builds of ilibrary and M11Probe and a synthetic staging tree of 12 original tracks (3 albums by 2 artists, 4 tracks each, distinct release dates).'
echo 'Music, the maintainer library, and every earlier bundle, including the first M11 bundle, are not touched.'
[ "$mode" != --dry-run ] || { echo 'Dry run: nothing was created.'; exit 0; }
[ "$(uname -s)" = Darwin ] || { echo 'Preparation requires macOS.'; exit 1; }
[ -z "$(git status --porcelain -- Sources Package.swift scripts/spikes/SynthAudio.swift \
    scripts/validation/prepare-m11-qualification.sh scripts/validation/m11-collect.sh \
    scripts/validation/m11_collect.py scripts/validation/synth_flac.py scripts/validation/test_m11_collect.py \
    docs/m11-qualification-v2.md)" ] || {
    echo 'Commit the sources of the qualification bundle before preparing it.'; exit 1;
}
work="$root/artifacts/m11-qualification-v2-preparation"
[ ! -e "$work" ] || { echo "$work already exists; it is not overwritten."; exit 1; }
mkdir -p "$work/tools"
commit=$(git rev-parse HEAD)
# SwiftPM builds only the last of several --product options, so each product is built separately, and an
# executable older than the start of the preparation is refused.
touch "$work/build-started"
for product in ilibrary M11Probe; do
    swift build -c release --product "$product" >>"$work/build.log" 2>&1
done
bin=$(swift build -c release --show-bin-path)
for product in ilibrary M11Probe; do
    [ "$bin/$product" -nt "$work/build-started" ] || { echo "$bin/$product was not rebuilt; it is not bundled."; exit 1; }
done
swiftc -O -swift-version 5 scripts/spikes/SynthAudio.swift -o "$work/tools/SynthAudio"

# Synthetic audio and tags. The product reads tags only from FLAC files, so each WAV is wrapped by synth_flac.py,
# a standard-library script, before `ilibrary import` converts it and carries the original synthetic tags.
python3 -I - "$work" "$root/scripts/validation" "$work/tools/SynthAudio" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

work, scripts, synth = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
ALBUMS = [
    ("iLibrary M11 Synthetic Artist A", "M11 Album 01", "2001-03-15"),
    ("iLibrary M11 Synthetic Artist B", "M11 Album 02", "1998-11-02"),
    ("iLibrary M11 Synthetic Artist A", "M11 Album 03", "2005-07-21"),
]
albums = []
seed = 1100
for number, (artist, album, date) in enumerate(ALBUMS, start=1):
    tracks = []
    for track in range(1, 5):
        title = f"M11 Song {number:02d}-{track:02d}"
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
"$bin/ilibrary" import "$work/flac" -o "$work/imported" >"$work/import.log"

# The bundle. Tagging beyond the carried FLAC fields uses only `ilibrary apply` on a copy.
bundle="$work/$name"
mkdir -p "$bundle/bin"
cp "$bin/ilibrary" "$bin/M11Probe" "$bundle/bin/"
cp "$work/catalog.json" "$bundle/catalog.json"
cp -R "$work/imported" "$bundle/staging"
"$bundle/bin/ilibrary" validate "$bundle/catalog.json" "$bundle/staging" >"$work/validate-before.log" || true
"$bundle/bin/ilibrary" apply "$bundle/catalog.json" "$bundle/staging" --rename --timestamps --dry-run >"$work/apply-dry-run.log"
"$bundle/bin/ilibrary" apply "$bundle/catalog.json" "$bundle/staging" --rename --timestamps >"$work/apply.log"
"$bundle/bin/ilibrary" validate "$bundle/catalog.json" "$bundle/staging" >"$work/validate.log"
"$bundle/bin/ilibrary" export "$bundle/staging" -o "$work/strict-check.json" --strict >"$work/export-strict.log"
python3 -I - "$work/strict-check.json" <<'PY'
import json
import sys

albums = json.load(open(sys.argv[1]))["albums"]
dates = {album["releaseDate"] for album in albums}
assert len(albums) == 3 and sum(len(d["tracks"]) for a in albums for d in a["discs"]) == 12, "unexpected staging size"
assert len(dates) == 3 and all(len(date) == 10 for date in dates), "release dates are not distinct full dates"
PY
cp "$root/docs/m11-qualification-v2.md" "$bundle/PROCEDURE.md"
cp "$root/scripts/validation/m11-collect.sh" "$bundle/collect.sh"
cp "$root/scripts/validation/m11_collect.py" "$bundle/m11_collect.py"
chmod +x "$bundle/bin/ilibrary" "$bundle/bin/M11Probe" "$bundle/collect.sh"
python3 -I - "$bundle" "$commit" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

bundle, commit = Path(sys.argv[1]), sys.argv[2]
files = {
    str(path.relative_to(bundle)): hashlib.sha256(path.read_bytes()).hexdigest()
    for path in sorted(bundle.rglob("*")) if path.is_file()
}
assert "manifest.json" not in files and not any(name.endswith(".DS_Store") for name in files)
manifest = {"format": "ilibrary-m11-qualification-2", "commit": commit, "files": files}
(bundle / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY

python3 -I - "$work" "$name" <<'PY'
import hashlib
import json
import sys
import zipfile
from pathlib import Path

work, name = Path(sys.argv[1]), sys.argv[2]
bundle = work / name
manifest = json.loads((bundle / "manifest.json").read_text())
archive = work / (name + ".zip")
with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED) as output:
    for relative in sorted([*manifest["files"], "manifest.json"]):
        output.write(bundle / relative, name + "/" + relative)
with zipfile.ZipFile(archive) as result:
    assert result.testzip() is None
    for relative, expected in manifest["files"].items():
        assert hashlib.sha256(result.read(name + "/" + relative)).hexdigest() == expected, relative
    for executable in ("bin/ilibrary", "bin/M11Probe", "collect.sh"):
        assert (result.getinfo(name + "/" + executable).external_attr >> 16) & 0o111, executable
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
(work / (name + ".zip.sha256")).write_text(checksum + "  " + name + ".zip\n")
PY
echo "PASS: the bundle and its ZIP archive were created and checked against the manifest for commit $commit. Stopping before any separate-user operation."
