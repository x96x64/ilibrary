#!/bin/sh
# Combine the saved logs of the M11 qualification bundle into one redacted report. Never address Music.
# Usage: collect.sh REPORT
set -eu
here=$(cd "$(dirname "$0")" && pwd)
PYTHONDONTWRITEBYTECODE=1 exec python3 -I "$here/m11_collect.py" "$@"
