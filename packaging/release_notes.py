#!/usr/bin/env python3
"""Print the body of a GitHub release from its changelog section."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TITLE = "iLibrary: v{version}, Catalog-Driven Music Libraries for Apple Music on macOS"


def section(changelog, version):
    match = re.search(rf"^## \[{re.escape(version)}\] - [^\n]*\n(.*?)(?=^## \[|\Z)", changelog, re.M | re.S)
    if not match or not match[1].strip():
        raise SystemExit(f"CHANGELOG.md has no section for {version}.")
    return match[1].strip()


def notes(version, root=ROOT):
    changes = section((root / "CHANGELOG.md").read_text(), version)
    return f"""iLibrary {version} prepares downloaded music for a local Apple Music library on macOS: it converts \
lossless downloads, applies a catalog to the files, arranges them as Music does, and adds or rebuilds the library \
in a chosen order.

> [!IMPORTANT]
> Begin with copies and keep independent backups of your library. iLibrary does not prevent Apple Music cloud \
matching and is not affiliated with Apple.

{changes}

## Installing and Upgrading

Install with `brew install x96x64/tap/ilibrary`, `npm install -g @x96_64/ilibrary@{version}`, or \
`python -m pip install x96_64-ilibrary=={version}` in a Python virtual environment, and upgrade through the same \
channel. Homebrew builds from source with Swift 6; npm and PyPI install a prebuilt executable for macOS 14 or later \
on Apple silicon, signed ad hoc and not notarized.

See the [changelog](https://github.com/x96x64/ilibrary/blob/v{version}/CHANGELOG.md) for earlier versions. iLibrary \
is licensed under the Apache License, Version 2.0.
"""


if __name__ == "__main__":
    if len(sys.argv) != 2 or not re.fullmatch(r"\d+\.\d+\.\d+", sys.argv[1]):
        raise SystemExit("usage: release_notes.py X.Y.Z")
    print(notes(sys.argv[1]), end="")
