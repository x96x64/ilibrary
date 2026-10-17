#!/bin/sh
# Build a transferable M10 probe with synthetic media only. Never query Music.
set -eu
mode=${1:---dry-run}
case "$mode" in --dry-run|--prepare) ;; *) echo 'Usage: prepare-rebuild-probe.sh [--dry-run|--prepare]'; exit 2 ;; esac
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
echo '予定: artifacts/m10-preparation に検証用実行ファイルと合成音声 306 曲を作ります。Music は操作しません。'
[ "$mode" != --dry-run ] || exit 0
[ ! -e artifacts/m10-preparation ] || { echo '準備先が既にあります。上書きしません。'; exit 1; }
mkdir -p artifacts/m10-preparation/tools
work="$root/artifacts/m10-preparation"
swift build -c release --product ilibrary >"$work/build.log" 2>&1
binary=$(swift build -c release --show-bin-path)/ilibrary
swiftc -O -swift-version 5 scripts/spikes/SynthAudio.swift -o "$work/tools/SynthAudio"
swiftc -O -swift-version 5 scripts/spikes/MP4Spike.swift -o "$work/tools/MP4Spike"
"$work/tools/SynthAudio" "$work/source.wav" --rate 44100 --bits 16 --channels 2 --frames 4410 --seed 1010
"$binary" import "$work/source.wav" -o "$work/encoded" >"$work/import.log"
python3 scripts/validation/rebuild_probe.py prepare \
    --output "$work/ilibrary-m10" --binary "$binary" --tagger "$work/tools/MP4Spike" \
    --audio "$work/encoded/source.m4a" --commit "$(git rev-parse HEAD)"
python3 - "$work" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
import zipfile

work = Path(sys.argv[1])
bundle = work / "ilibrary-m10"
manifest = json.loads((bundle / "manifest.json").read_text())
archive = work / "ilibrary-m10.zip"
with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED) as output:
    for relative in sorted([*manifest["files"], "manifest.json"]):
        output.write(bundle / relative, "ilibrary-m10/" + relative)
with zipfile.ZipFile(archive) as result:
    assert result.testzip() is None
    for relative, expected in manifest["files"].items():
        assert hashlib.sha256(result.read("ilibrary-m10/" + relative)).hexdigest() == expected
    assert (result.getinfo("ilibrary-m10/bin/ilibrary").external_attr >> 16) & 0o111
checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
(work / "ilibrary-m10.zip.sha256").write_text(checksum + "  ilibrary-m10.zip\n")
PY
echo 'PASS: 準備のみ完了。別ユーザーでの操作の前に docs/rebuild-feasibility-validation.md を読んでください。'
