"""Bulk library snapshot and append-only removal journal for the M10 qualification probe.

This module is imported only by qualification_probe.py. The bulk snapshot issues a number of Apple Events
that does not depend on the number of tracks, and it reproduces the row format of the per-track snapshot
in rebuild_probe so that the existing parser can be reused unchanged.
"""

import datetime
import json
import os
import sys

sys.dont_write_bytecode = True
import rebuild_probe as base

# Every property is read once for the whole library, the persistent ID list is read first and last, and
# the rows are assembled by a local loop that sends no further Apple Event. Fields, delimiters, and the
# date offset conversion are those of rebuild_probe.SNAPSHOT.
BULK_SNAPSHOT = '''
on stamp(d)
    set base to current date
    set day of base to 1
    set year of base to 2000
    set month of base to January
    set time of base to 0
    return (d - base) as integer
end stamp
on run argv
    set output to ""
    set fs to character id 31
    set rs to character id 30
    with timeout of 300 seconds
        tell application "Music"
            set trackCount to count of tracks of library playlist 1
            if trackCount is 0 then return ""
            set firstIDs to persistent ID of every track of library playlist 1
            set nameList to name of every track of library playlist 1
            set albumList to album of every track of library playlist 1
            set artistList to artist of every track of library playlist 1
            set dateList to date added of every track of library playlist 1
            set fileCount to count of (every file track of library playlist 1)
            if fileCount is trackCount then
                set locationList to location of every file track of library playlist 1
            else
                set locationList to {}
            end if
            set lastIDs to persistent ID of every track of library playlist 1
        end tell
    end timeout
    if firstIDs is not lastIDs then error "Library changed during snapshot"
    if (count of firstIDs) is not trackCount or (count of nameList) is not trackCount or (count of albumList) is not trackCount or (count of artistList) is not trackCount or (count of dateList) is not trackCount then error "Property lists differ in length"
    if fileCount is trackCount and (count of locationList) is not trackCount then error "Property lists differ in length"
    repeat with i from 1 to trackCount
        set p to ""
        set pathError to ""
        if fileCount is not trackCount then
            set pathError to "non-file-track"
        else
            try
                set p to POSIX path of (item i of locationList)
            on error errText number errNumber
                set pathError to errNumber as text
            end try
        end if
        set output to output & (item i of firstIDs) & fs & (item i of nameList) & fs & (item i of albumList) & fs & (item i of artistList) & fs & p & fs & ((my stamp(item i of dateList)) as text) & fs & "" & fs & "bulk-not-read" & fs & pathError & rs
    end repeat
    return output
end run
'''


def snapshot():
    """Parse the bulk output with the unchanged per-track parser (rebuild_probe.snapshot)."""
    saved = base.SNAPSHOT
    base.SNAPSHOT = BULK_SNAPSHOT
    try:
        return base.snapshot()
    finally:
        base.SNAPSHOT = saved


def utc():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


class Journal:
    """Append-only JSON Lines journal; each record is flushed and synchronized before the caller proceeds."""

    def __init__(self, path):
        self.stream = path.open("a", encoding="utf-8")

    def write(self, **record):
        self.stream.write(json.dumps(dict(record, time=utc()), ensure_ascii=False, sort_keys=True) + "\n")
        self.stream.flush()
        os.fsync(self.stream.fileno())

    def close(self):
        self.stream.close()


def read(path):
    """Return verified removals, returned-but-unverified removals, whether an intent lacks its returned
    record, and the final event."""
    returned, verified, intents, last = set(), set(), [], None
    if not path.is_file():
        return 0, 0, False, None
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        last = record["event"]
        if record["event"] == "intent":
            intents.append(record["id"])
        elif record["event"] == "returned":
            returned.add(record["id"])
        elif record["event"] == "verified":
            verified.add(record["id"])
    return len(verified), len(returned - verified), any(i not in returned for i in intents), last
