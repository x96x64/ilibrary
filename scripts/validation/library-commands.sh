#!/bin/sh
# Combined M5/M6 qualification. --prepare-only never opens or queries Music.
# --run-live is restricted to a separate test user, no Apple Account, and an empty library or the five
# known synthetic tracks left by music-live-probe.sh. No library entries or user files are deleted.
set -eu
mode=${1:---prepare-only}
case "$mode" in --prepare-only|--run-live) ;; *) echo 'Usage: library-commands.sh [--prepare-only|--run-live]'; exit 2 ;; esac
root=$(cd "$(dirname "$0")/../.." && pwd)
if [ "$mode" = --run-live ]; then
    case "$(id -un)" in ilibrarytest*|ilibrary-test*) ;; *)
        echo '別の検証用ユーザー（アカウント名 ilibrarytest または ilibrary-test で始まる名前）に切り替えてください。'; exit 1 ;; esac
    if defaults read MobileMeAccounts Accounts 2>/dev/null | grep -q AccountID; then
        echo 'Apple Account にサインインしています。検証用ユーザーではサインインしないでください。'; exit 1
    fi
    echo 'この検証用ユーザーの Music に、合成音声のアルバムを2つ追加します。'
    echo '普段のユーザーではないことを確認してください。'
    printf '続行する場合は TEST と入力してください: '
    read -r answer
    [ "$answer" = TEST ] || exit 1
fi
mkdir -p "$root/artifacts/validation"
work=$(mktemp -d "$root/artifacts/validation/library-commands.XXXXXX")
mkdir -p "$work/bin" "$work/staging"
cd "$root"
swift build -c release --product ilibrary >"$work/build.log" 2>&1
ilibrary=$(swift build -c release --show-bin-path)/ilibrary
swiftc -O -swift-version 5 scripts/spikes/SynthAudio.swift -o "$work/bin/SynthAudio"
# The import command performs the conversion; the catalog supplies every public synthetic tag.
"$work/bin/SynthAudio" "$work/source.wav" --rate 44100 --bits 16 --channels 2 --frames 22050 --seed 17
"$ilibrary" import "$work/source.wav" -o "$work/encoded" >"$work/import.log"
cat >"$work/catalog.json" <<'JSON'
{"format":"ilibrary-catalog-1","albums":[
 {"album":"iLibrary Validation Album A","albumArtist":"iLibrary Validation Artist","artist":"iLibrary Validation Artist","releaseDate":"1980-06-01","genre":"Synthetic","discs":[{"tracks":[{"title":"Validation Song 1"},{"title":"Validation Song 2"}]}]},
 {"album":"iLibrary Validation Album B","albumArtist":"iLibrary Validation Artist","artist":"iLibrary Validation Artist","releaseDate":"1981-06-01","genre":"Synthetic","discs":[{"tracks":[{"title":"Validation Song 3"}]}]}
]}
JSON
swiftc -O -swift-version 5 scripts/spikes/MP4Spike.swift -o "$work/bin/MP4Spike"
make_track() {
    folder="$work/staging/$1"
    mkdir -p "$folder"
    "$work/bin/MP4Spike" tag "$work/encoded/source.m4a" "$folder/$3.m4a" \
        --set "©nam=$3" --set "©ART=iLibrary Validation Artist" --set "aART=iLibrary Validation Artist" \
        --set "©alb=$1" --track "$2" --disc 1/1 >/dev/null
}
make_track 'iLibrary Validation Album A' 1/2 'Validation Song 1'
make_track 'iLibrary Validation Album A' 2/2 'Validation Song 2'
make_track 'iLibrary Validation Album B' 1/1 'Validation Song 3'
"$ilibrary" apply "$work/catalog.json" "$work/staging" --rename --timestamps >"$work/apply.log"
"$ilibrary" check "$work/staging" >"$work/check-prepared.log"
if [ "$mode" = --prepare-only ]; then
    echo '準備とファイル検査が完了しました。Music は操作していません。'
    exit 0
fi
# Validate the whole test library without printing any track properties.
initial=$(osascript <<'APPLESCRIPT'
tell application "Music"
    set total to count of tracks of library playlist 1
    if total is 0 then return 0
    if total is not 5 then error "Use an empty library or the original five-track probe library."
    repeat with t in every track of library playlist 1
        if artist of t is not "iLibrary Probe Artist" then error "This is not the synthetic probe library."
        if album of t is not "iLibrary Probe Album A Renamed" and album of t is not "iLibrary Probe Album B" then error "Unexpected album in the test library."
    end repeat
    return total
end tell
APPLESCRIPT
)
results="$HOME/Desktop/ilibrary-command-results.txt"
[ ! -e "$results" ] || { echo '前回の結果ファイルがあります。上書きせず終了します。'; exit 1; }
log() { printf '%s\n' "$*" | tee -a "$results"; }
failures=0
check() {
    if [ "$2" = "$3" ]; then log "PASS: $1"; else log "FAIL: $1"; failures=$((failures + 1)); fi
}
log 'iLibrary M5/M6 command validation'
log "date: $(date -u +%Y-%m-%dT%H:%MZ)"
log "commit: $(git rev-parse --short HEAD)"
log "macOS: $(sw_vers -productVersion)"
# Raw command output remains in the ignored workspace. Shared results contain counts and statuses only.
"$ilibrary" doctor >"$work/doctor.log" 2>&1 && doctor_status=0 || doctor_status=$?
check 'doctor after Automation permission' "$doctor_status" 0
"$ilibrary" add "$work/staging" --dry-run >"$work/dry-run.log" 2>&1
check 'dry run retains all staging tracks' "$(find "$work/staging" -name '*.m4a' | wc -l | tr -d ' ')" 3
"$ilibrary" add "$work/staging" --order release >"$work/add.log" 2>&1 || {
    log 'FAIL: add did not complete; preserve this test user and report this result file.'; exit 1;
}
count=$(osascript -e 'tell application "Music" to return count of tracks of library playlist 1')
check 'one new library track per file' "$count" "$((initial + 3))"
check 'selected sources were moved' "$(find "$work/staging" -name '*.m4a' | wc -l | tr -d ' ')" 0
# Read only the journal made by this run. Persistent IDs and personal paths are never copied to results.
python3 -I - "$work/staging/.ilibrary-add.json" "$work/destinations.txt" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
assert [e['album'] for e in j['entries']] == ['iLibrary Validation Album A', 'iLibrary Validation Album B']
assert all(e['state'] == 'added' for e in j['entries'])
with open(sys.argv[2], 'w') as f:
    for e in j['entries']:
        for p in e['destinations']: f.write(p + '\n')
PY
log 'PASS: albums added in release order and confirmed'
first=$(sed -n '1p' "$work/destinations.txt")
second=$(sed -n '2p' "$work/destinations.txt")
artist_folder=$(dirname "$(dirname "$first")")
"$ilibrary" check "$artist_folder" --library >"$work/check-library.log" 2>&1 && status=0 || status=$?
check 'file and library metadata agree' "$status" 0
"$ilibrary" add "$work/staging" >"$work/repeated-add.log" 2>&1 && status=0 || status=$?
check 'completed run is safe to repeat' "$status" 0
mkdir -p "$work/duplicate"
cp "$first" "$work/duplicate/duplicate.m4a"
"$ilibrary" add "$work/duplicate" >"$work/duplicate.log" 2>&1 && status=0 || status=$?
check 'existing track is refused' "$status" 1
check 'refused source remains' "$([ -f "$work/duplicate/duplicate.m4a" ] && echo yes || echo no)" yes
# Deliberately alter only a synthetic timestamp and restore it using the catalog.
touch -m -t 200101010101 "$first"
"$ilibrary" check "$artist_folder" >"$work/damaged-date.log" 2>&1 && status=0 || status=$?
check 'incorrect file date is detected' "$status" 1
"$ilibrary" timestamps "$work/catalog.json" "$artist_folder" >"$work/restored-dates.log"
# Hide a synthetic track outside the Music folder without deleting it; restore even after a failure.
hidden="$work/temporarily-hidden.m4a"
restore() { if [ -f "$hidden" ] && [ ! -e "$second" ]; then mv "$hidden" "$second"; fi; }
trap restore EXIT HUP INT TERM
mv "$second" "$hidden"
"$ilibrary" check "$artist_folder" --library >"$work/missing-file.log" 2>&1 && status=0 || status=$?
check 'missing or relocated library file is detected' "$status" 1
restore
trap - EXIT HUP INT TERM
log "failures: $failures"
log 'No private library was used. No library entries were deleted.'
echo '結果はデスクトップの ilibrary-command-results.txt にあります。この内容をそのまま報告してください。'
[ "$failures" -eq 0 ]
