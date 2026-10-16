#!/bin/sh
# Live measurements of the Music app for milestones M5 and M6 (architecture spike, S3).
#
# Run this ONLY in a separate local macOS user that is not signed in to an Apple Account and whose Music
# library holds no tracks other than those this script adds. It refuses to run otherwise. It creates two
# synthetic albums, adds them to Music, and records how Music behaves: in-place addition, the tracks that
# `add` returns, persistent IDs across a relaunch, cloud status, duplicates, copies from outside the media
# folder, refresh, relinking, renaming an album, and file dates. The results are written to
# ~/Desktop/ilibrary-live-results.txt with the home folder and user name replaced, for the maintainer to
# share. The script never deletes anything.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$HOME/ilibrary-live-probe
results=$HOME/Desktop/ilibrary-live-results.txt
artist="iLibrary Probe Artist"
albumA="iLibrary Probe Album A"
albumB="iLibrary Probe Album B"
user=$(id -un)

sanitize() { sed -e "s|$HOME|~|g" -e "s|/Users/$user|/Users/<user>|g" -e "s|$user|<user>|g"; }
log() { printf '%s\n' "$*" | sanitize | tee -a "$results"; }
music() { osascript - "$@"; }

echo "This script must run in a separate test user without an Apple Account."
echo "It adds synthetic tracks to this user's Music library."
printf 'Type YES to continue: '
read -r answer
[ "$answer" = "YES" ] || { echo "Stopped; nothing was changed."; exit 1; }
if defaults read MobileMeAccounts Accounts 2>/dev/null | grep -q AccountID; then
    echo "This user is signed in to an Apple Account. Use a test user without one. Nothing was changed."
    exit 1
fi

# The library must be empty, so that no real library is ever changed and every measurement starts from a
# fresh library. A second run needs a new test user.
others=$(music <<'APPLESCRIPT'
on run argv
    with timeout of 120 seconds
        tell application "Music" to return count of tracks of library playlist 1
    end timeout
end run
APPLESCRIPT
) || {
    echo "Terminal could not control Music. Open Music once, then allow Terminal in System Settings, Privacy & Security, Automation. Nothing was changed."
    exit 1
}
if [ "$others" != "0" ]; then
    echo "This Music library holds $others tracks. Use a new test user, whose library is empty. Nothing was changed."
    exit 1
fi

mkdir -p "$work/bin" "$work/staging"
: >"$results"
log "iLibrary live Music measurements"
log "date: $(date -u +%Y-%m-%dT%H:%MZ)"
log "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
log "Music: $(defaults read /System/Applications/Music.app/Contents/Info.plist CFBundleShortVersionString)"
log "repository commit: $(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)"

swiftc -O -swift-version 5 "$root/scripts/spikes/SynthAudio.swift" -o "$work/bin/SynthAudio"
swiftc -O -swift-version 5 "$root/scripts/spikes/MP4Spike.swift" -o "$work/bin/MP4Spike"

# Two synthetic albums of Apple Lossless files with tags.
make_album() { # folder album tracks seed
    mkdir -p "$1"
    number=1
    while [ "$number" -le "$3" ]; do
        "$work/bin/SynthAudio" "$work/source.wav" --rate 44100 --bits 16 --channels 2 --frames 132300 --seed "$(($4 + number))"
        afconvert -f m4af -d alac "$work/source.wav" "$work/encoded.m4a"
        file=$(printf '%s/%02d Probe Song %d.m4a' "$1" "$number" "$number")
        "$work/bin/MP4Spike" tag "$work/encoded.m4a" "$file" --set "©nam=Probe Song $number" --set "©ART=$artist" \
            --set "aART=$artist" --set "©alb=$2" --set "©day=1980-06-01T00:00:00Z" --track "$number/$3" --disc 1/1 >/dev/null
        rm -f "$work/encoded.m4a"
        number=$((number + 1))
    done
    rm -f "$work/source.wav"
}

media=$(defaults read com.apple.Music media-folder-url 2>/dev/null | sed -e 's|^file://||' -e 's|%20| |g' -e 's|/$||' || true)
log ""
log "== M1 media folder"
if [ -n "$media" ]; then log "preference media-folder-url: $media"; else log "preference media-folder-url: absent"; media="$HOME/Music/Music/Media.localized"; fi
log "media folder exists: $([ -d "$media" ] && echo yes || echo no)"
mkdir -p "$media/Music"
inside="$media/Music/$artist/$albumA"
outside="$work/staging/$albumB"
make_album "$inside" "$albumA" 3 100
make_album "$outside" "$albumB" 2 200
files_before=$(find "$media" -type f -name '*.m4a' | wc -l | tr -d ' ')
dates_before=$(stat -f '%m %B' "$inside/01 Probe Song 1.m4a")

describe='on describeTracks(theTracks)
    set fieldSeparator to character id 31
    set output to ""
    tell application "Music"
        repeat with t in theTracks
            set thePath to ""
            try
                set thePath to POSIX path of (get location of t)
            end try
            set theStatus to ""
            try
                set theStatus to (cloud status of t) as text
            end try
            set output to output & (persistent ID of t) & fieldSeparator & (name of t) & fieldSeparator & (album of t) & fieldSeparator & thePath & fieldSeparator & theStatus & linefeed
        end repeat
    end tell
    return output
end describeTracks'

add_files() { # files...
    { printf '%s\n' "$describe"; cat <<'APPLESCRIPT'
on run argv
    set theFiles to {}
    repeat with p in argv
        set end of theFiles to (POSIX file (p as text))
    end repeat
    with timeout of 300 seconds
        tell application "Music" to set added to (add theFiles to library playlist 1)
    end timeout
    if added is missing value then return ""
    if class of added is not list then set added to {added}
    return my describeTracks(added)
end run
APPLESCRIPT
    } | osascript - "$@"
}
find_id() { # persistent ID
    { printf '%s\n' "$describe"; cat <<'APPLESCRIPT'
on run argv
    with timeout of 120 seconds
        tell application "Music" to set found to (every track of library playlist 1 whose persistent ID is (item 1 of argv))
    end timeout
    return my describeTracks(found)
end run
APPLESCRIPT
    } | osascript - "$1" || true
}
count_tracks() {
    osascript -e 'with timeout of 120 seconds' -e 'tell application "Music" to return count of tracks of library playlist 1' -e 'end timeout' || echo "error"
}
field() { cut -d "$(printf '\037')" -f "$1"; }

log ""
log "== M2 addition of files inside the media folder (album A, 3 files)"
added=$(add_files "$inside/01 Probe Song 1.m4a" "$inside/02 Probe Song 2.m4a" "$inside/03 Probe Song 3.m4a" || echo "")
log "tracks returned by add: $(printf '%s' "$added" | grep -c . || true)"
printf '%s\n' "$added" | while IFS= read -r line; do [ -n "$line" ] && log "  track: id $(printf '%s' "$line" | field 1), location $(printf '%s' "$line" | field 4), cloud status $(printf '%s' "$line" | field 5)"; done
log "library tracks after add: $(count_tracks)"
log "m4a files in the media folder: before $files_before, after $(find "$media" -type f -name '*.m4a' | wc -l | tr -d ' ')"
log "file dates (modification, creation) of track 1: before $dates_before, after $(stat -f '%m %B' "$inside/01 Probe Song 1.m4a")"
# The tracks of album A are found by their album, independently of what add returned.
album_ids() { # album
    osascript - "$1" <<'APPLESCRIPT' || true
on run argv
    set output to ""
    with timeout of 120 seconds
        tell application "Music"
            repeat with t in (every file track of library playlist 1 whose album is (item 1 of argv))
                set output to output & (persistent ID of t) & linefeed
            end repeat
        end tell
    end timeout
    return output
end run
APPLESCRIPT
}
ids=$(album_ids "$albumA" | grep . || true)
log "tracks of album A found by album: $(printf '%s\n' "$ids" | grep -c . || true)"

log ""
log "== M3 adding the same file again"
before=$(count_tracks)
again=$(add_files "$inside/01 Probe Song 1.m4a" || echo "error")
log "tracks returned: $(printf '%s' "$again" | grep -c . || true); ids: $(printf '%s\n' "$again" | field 1 | tr '\n' ' ')"
log "library tracks: before $before, after $(count_tracks)"

log ""
log "== M4 addition of files outside the media folder (album B, 2 files)"
addedB=$(add_files "$outside/01 Probe Song 1.m4a" "$outside/02 Probe Song 2.m4a" || echo "")
printf '%s\n' "$addedB" | while IFS= read -r line; do [ -n "$line" ] && log "  track: location $(printf '%s' "$line" | field 4)"; done
log "source files still in the staging folder: $(find "$outside" -type f -name '*.m4a' | wc -l | tr -d ' ')"

log ""
log "== M5 persistent IDs after quitting and relaunching Music"
osascript -e 'tell application "Music" to quit'
sleep 8
osascript -e 'tell application "Music" to launch'
sleep 8
printf '%s\n' "$ids" | while IFS= read -r id; do
    [ -n "$id" ] || continue
    found=$(find_id "$id")
    log "  id $id: found $(printf '%s' "$found" | grep -c . || true), location $(printf '%s' "$found" | field 4)"
done

first=$(printf '%s\n' "$ids" | sed -n 1p)
second=$(printf '%s\n' "$ids" | sed -n 2p)
# Files are changed where Music says the tracks are, which may differ from where they were added.
firstFile=$([ -n "$first" ] && find_id "$first" | field 4 | sed -n 1p || true)
secondFile=$([ -n "$second" ] && find_id "$second" | field 4 | sed -n 1p || true)
log ""
log "== M6 a title changed in the file, before and after refresh"
if [ -n "$first" ] && [ -n "$firstFile" ] && [ -f "$firstFile" ]; then
"$work/bin/MP4Spike" tag "$firstFile" "$work/retitled.m4a" --set "©nam=Probe Song 1 Changed" >/dev/null
mv "$work/retitled.m4a" "$firstFile"
log "file changed: the location that Music reports for the track"
log "name in Music before refresh: $(find_id "$first" | field 2)"
{ printf '%s\n' "$describe"; cat <<'APPLESCRIPT'
on run argv
    with timeout of 120 seconds
        tell application "Music" to refresh (first file track of library playlist 1 whose persistent ID is (item 1 of argv))
    end timeout
    return ""
end run
APPLESCRIPT
} | osascript - "$first" >/dev/null 2>&1 || log "refresh: error"
sleep 2
log "name in Music after refresh: $(find_id "$first" | field 2)"
else
    log "skipped: no track of album A with a file location was found"
fi

log ""
log "== M7 a file moved within the media folder, then relinked"
if [ -n "$second" ] && [ -n "$secondFile" ] && [ -f "$secondFile" ]; then
mkdir -p "$media/Music/$artist/Relinked"
mv "$secondFile" "$media/Music/$artist/Relinked/02 Probe Song 2.m4a"
sleep 2
log "location after the move, before relinking: $(find_id "$second" | field 4)"
osascript - "$second" "$media/Music/$artist/Relinked/02 Probe Song 2.m4a" <<'APPLESCRIPT' >/dev/null 2>&1 || log "relinking: error"
on run argv
    set newFile to POSIX file (item 2 of argv)
    with timeout of 120 seconds
        tell application "Music" to set location of (first file track of library playlist 1 whose persistent ID is (item 1 of argv)) to newFile
    end timeout
end run
APPLESCRIPT
log "location after relinking: $(find_id "$second" | field 4)"
else
    log "skipped: no second track of album A with a file location was found"
fi

log ""
log "== M8 renaming album A in Music, one track per call"
printf '%s\n' "$ids" | while IFS= read -r id; do
    [ -n "$id" ] || continue
    osascript - "$id" "$albumA Renamed" <<'APPLESCRIPT' >/dev/null 2>&1 || log "renaming $id: error"
on run argv
    with timeout of 120 seconds
        tell application "Music" to set album of (first track of library playlist 1 whose persistent ID is (item 1 of argv)) to (item 2 of argv)
    end timeout
end run
APPLESCRIPT
done
sleep 5
printf '%s\n' "$ids" | while IFS= read -r id; do [ -n "$id" ] && log "  id $id: location $(find_id "$id" | field 4)"; done
log "folders under the artist folder:"
find "$media/Music/$artist" -type d | sort | while IFS= read -r folder; do log "  $folder"; done

log ""
log "== M9 the Automation permission as seen without prompting"
log "Terminal was allowed to control Music: $(osascript -e 'tell application "Music" to return name' >/dev/null 2>&1 && echo yes || echo no)"
log ""
log "== end of measurements"
echo
echo "The results are in $results (the home folder and user name are replaced)."
