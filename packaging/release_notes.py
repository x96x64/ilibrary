#!/usr/bin/env python3
"""Print the body of a GitHub release from its changelog section."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TITLE = "iLibrary: v{version}, Catalog-Driven Music Libraries for Apple Music on macOS"
REPOSITORY = "https://github.com/x96x64/ilibrary"


def section(changelog, version):
    match = re.search(rf"^## \[{re.escape(version)}\] - [^\n]*\n(.*?)(?=^## \[|\Z)", changelog, re.M | re.S)
    if not match or not match[1].strip():
        raise SystemExit(f"CHANGELOG.md has no section for {version}.")
    return match[1].strip()


def highlights(changes):
    """The changelog entries as one list, each labeled by its category."""
    items, category = [], None
    for line in changes.splitlines():
        if heading := re.fullmatch(r"### (.+)", line.strip()):
            category = heading[1]
        elif line.startswith("- "):
            items.append(f"- **{category}.** {line[2:]}" if category else line)
        elif line.startswith("  ") and items:
            items[-1] += " " + line.strip()
    if not items:
        raise SystemExit("The changelog section has no entries.")
    return "\n".join(items)


def notes(version, root=ROOT):
    changes = section((root / "CHANGELOG.md").read_text(), version)
    return f"""iLibrary is a macOS command that prepares music through a JSON catalog and adds albums to a local Apple \
Music library in a controlled order. Version {version} brings the changes highlighted below.

> [!IMPORTANT]
> iLibrary moves and rewrites your music files and changes your Music library. Begin with copies, keep independent \
backups of your library, and review every dry run. Cloud matching is not prevented. iLibrary is independent software \
with no affiliation with Apple. Use recordings and artwork that you have the right to process, and review catalogs, \
journals, and recovery records before sharing them.

## Highlights

{highlights(changes)}

Verification consists of the synthetic Swift tests, publication-guard tests, and strict formatting run by continuous \
integration on macOS and Linux, and of the build, package comparison, and installation checks of the release \
workflow on a GitHub macOS runner. See [Verification and Limits]({REPOSITORY}/blob/v{version}/docs/roadmap.md#verification-and-limits) \
for the Music behavior that was measured and the limits of this version.

## Installing and Upgrading

Install with `brew install x96x64/tap/ilibrary`, `npm install -g @x96_64/ilibrary@{version}`, or \
`python -m pip install x96_64-ilibrary=={version}` in a Python virtual environment. Update through the same channel \
with `brew upgrade ilibrary`, `npm install -g @x96_64/ilibrary@latest`, or `python -m pip install --upgrade \
x96_64-ilibrary` in that environment.

Homebrew builds from source and requires Swift 6 from Xcode or the Command Line Tools. npm and PyPI install a \
prebuilt native executable for macOS 14 or later on Apple silicon without a Swift toolchain. The executable is signed \
ad hoc; Developer ID signing and notarization are not provided. Keep backups, catalogs, and journals, and read \
[Library Operations and Recovery]({REPOSITORY}/blob/main/docs/library-operations.md) before changing a library.

See the [changelog]({REPOSITORY}/blob/v{version}/CHANGELOG.md) for the complete change record and \
[Distribution]({REPOSITORY}/blob/main/docs/distribution.md) for package identities and verification. iLibrary is \
licensed under the Apache License, Version 2.0.
"""


if __name__ == "__main__":
    if len(sys.argv) != 2 or not re.fullmatch(r"\d+\.\d+\.\d+", sys.argv[1]):
        raise SystemExit("usage: release_notes.py X.Y.Z")
    print(notes(sys.argv[1]), end="")
