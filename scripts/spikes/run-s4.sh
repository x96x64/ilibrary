#!/bin/sh
# Spike S4: file and folder timestamps. Results from FileManager are cross-checked with stat(1),
# GetFileInfo(1), and the behavior of touch(1) on a missing path.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
spikes=$root/scripts/spikes
bin=$root/artifacts/spikes/bin
work=$root/artifacts/spikes/s4
rm -rf "$work"
mkdir -p "$bin" "$work"
swiftc -O -swift-version 5 "$spikes/TimestampSpike.swift" -o "$bin/TimestampSpike"
image="$work/other.dmg"
mount="$work/other-volume"
hdiutil create -quiet -size 8m -fs APFS -volname iLibraryTimestamps "$image"
mkdir -p "$mount"
hdiutil attach -quiet -nobrowse -mountpoint "$mount" "$image"
"$bin/TimestampSpike" "$work/tree" "$mount"
echo "== independent check (stat, birth and modification, UTC): $(TZ=UTC stat -f '%N: %SB / %Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$work/tree/01 Track.m4a" | sed "s|$work/||")"
echo "== independent check (GetFileInfo, local time): $(GetFileInfo -d "$work/tree/01 Track.m4a") / $(GetFileInfo -m "$work/tree/01 Track.m4a")"
echo "== cross-volume copy (stat): $(TZ=UTC stat -f '%SB / %Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$mount/02 Moved.m4a" 2>/dev/null || echo missing)"
echo "== volume formats: work $(diskutil info "$(df "$work" | tail -1 | awk '{print $1}')" | sed -n 's/^ *File System Personality: *//p'), other $(diskutil info "$mount" | sed -n 's/^ *File System Personality: *//p')"
# The hazard recorded in the curation report: touch(1) creates a missing path.
touch -t 198006010000 "$work/tree/Missing Folder"
if [ -f "$work/tree/Missing Folder" ]; then echo "== touch on a missing path: created a regular file (hazard reproduced)"; fi
hdiutil detach -quiet "$mount"
rm -f "$image"
