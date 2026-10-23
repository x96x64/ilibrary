#!/usr/bin/env python3
"""Print the body of a GitHub release from its changelog section, or check an existing body.

Every body has the same layout: an introductory paragraph, an important notice, a Highlights section whose
entries carry specific labels such as `- **Title Rules:** ...`, a paragraph on verification and limits, an
Installing and Upgrading section, and a closing paragraph that links to the changelog, distribution, and license.
"""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TITLE = "iLibrary: v{version}, Catalog-Driven Music Libraries for Apple Music on macOS"
REPOSITORY = "https://github.com/x96x64/ilibrary"
VERSION = re.compile(r"\d+\.\d+\.\d+")
HIGHLIGHT = re.compile(r"- \*\*([A-Z][^*\n]*[^*\s:]):\*\* \S")
GENERIC_LABELS = {"added", "changed", "deprecated", "fixed", "removed", "security", "other", "changes", "misc"}
CLOSING = (
    "See the [changelog]({repository}/blob/v{version}/CHANGELOG.md) for the complete change record and "
    "[Distribution]({repository}/blob/main/docs/distribution.md) for package identities and verification. "
    "iLibrary is licensed under the Apache License, Version 2.0."
)


def section(changelog, version):
    match = re.search(rf"^## \[{re.escape(version)}\] - [^\n]*\n(.*?)(?=^## \[|\Z)", changelog, re.M | re.S)
    if not match or not match[1].strip():
        raise SystemExit(f"CHANGELOG.md has no section for {version}.")
    return match[1].strip()


def highlights(changes):
    """The changelog entries of a version, each of which must begin with a specific label."""
    items = []
    for line in changes.splitlines():
        if line.startswith("- "):
            items.append(line)
        elif line.startswith("  ") and items:
            items[-1] += " " + line.strip()
        elif line.strip() and not line.startswith("### "):
            raise SystemExit(f"The changelog section has text outside its entries: {line.strip()}")
    if not items:
        raise SystemExit("The changelog section has no entries.")
    for item in items:
        problem = label_problem(item)
        if problem:
            raise SystemExit(f"{problem}: {item[:80]}")
    return "\n".join(items)


def label_problem(item):
    match = HIGHLIGHT.match(item)
    if not match:
        return "A highlight must begin with a specific label such as '- **Title Rules:** '"
    if match[1].lower() in GENERIC_LABELS:
        return f"The label '{match[1]}' names a change category, not a capability"
    return None


def notes(version, root=ROOT):
    changes = section((root / "CHANGELOG.md").read_text(), version)
    body = f"""iLibrary is a macOS command that prepares music through a JSON catalog and adds albums to a local Apple \
Music library in a controlled order. Version {version} contains the changes highlighted below.

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

{CLOSING.format(repository=REPOSITORY, version=version)}
"""
    problems = check(body, version)
    if problems:
        raise SystemExit("The generated body is malformed: " + "; ".join(problems))
    return body


def check(body, version):
    """The departures of a release body from the common layout; empty when the body conforms."""
    problems = []
    blocks = [block.strip() for block in re.split(r"\n\s*\n", body.strip()) if block.strip()]
    headings = [block for block in blocks if block.startswith("#")]
    if headings != ["## Highlights", "## Installing and Upgrading"]:
        problems.append("the only headings must be '## Highlights' and then '## Installing and Upgrading'")
        return problems
    highlights_at = blocks.index("## Highlights")
    installing_at = blocks.index("## Installing and Upgrading")
    lead = blocks[:highlights_at]
    if len(lead) != 2 or lead[0].startswith((">", "-")) or not lead[1].startswith("> [!IMPORTANT]\n> "):
        problems.append("the body must open with one introductory paragraph and an important notice")
    middle = blocks[highlights_at + 1:installing_at]
    items = middle[0].splitlines() if middle and middle[0].startswith("- ") else []
    if not items:
        problems.append("Highlights must begin with a list of labeled entries")
    for item in items:
        problem = label_problem(item)
        if problem:
            problems.append(f"{problem}: {item[:60]}")
    if len(middle) != 2 or middle[1].startswith(("-", ">")):
        problems.append("Highlights must end with one paragraph on verification and limits")
    if re.search(r"\*\*[^*\n]+\.\*\*", body):
        problems.append("a bold label ends with a period instead of a colon inside the bold text")
    installing = blocks[installing_at + 1:]
    if len(installing) < 2:
        problems.append("Installing and Upgrading must hold installation guidance and the closing paragraph")
    elif installing[-1] != CLOSING.format(repository=REPOSITORY, version=version):
        problems.append("the closing paragraph must link to the changelog of this version, distribution, and license")
    references = re.findall(r"(?:@x96_64/ilibrary@|x96_64-ilibrary==|/blob/v|ilibrary-)(\d+\.\d+\.\d+)", body)
    if any(reference != version for reference in references):
        problems.append(f"the body refers to versions other than {version}: {sorted(set(references))}")
    return problems


def main(arguments):
    if len(arguments) == 1 and VERSION.fullmatch(arguments[0]):
        print(notes(arguments[0]), end="")
    elif len(arguments) == 3 and arguments[0] == "--check" and VERSION.fullmatch(arguments[1]):
        problems = check(Path(arguments[2]).read_text(), arguments[1])
        if problems:
            raise SystemExit("\n".join(f"{arguments[2]}: {problem}" for problem in problems))
    else:
        raise SystemExit("usage: release_notes.py X.Y.Z | release_notes.py --check X.Y.Z BODY.md")


if __name__ == "__main__":
    main(sys.argv[1:])
