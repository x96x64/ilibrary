#!/usr/bin/env python3
"""Combine the saved logs of the M11 qualification into one redacted report.

The script reads only files inside its own bundle directory and, optionally, the transferred archive checksum
in /Users/Shared. It never addresses Music. It writes exactly one new file, the report path given as the
argument, and refuses to overwrite it.

Usage: m11_collect.py REPORT
       m11_collect.py --check
"""

import hashlib
import json
import os
import re
import sys
from pathlib import Path

FORMAT = "ilibrary-m11-qualification-1"
ARCHIVE_DIRECTORY = Path("/Users/Shared")
ARCHIVE = "ilibrary-m11-qualification.zip"
EXPECTED_RESULTS = (
    "bundle-check.log", "staging-dates.log", "validate-staging.log", "doctor.log", "add-dry-run.log", "add.log",
    "readers.log", "readers.json", "catalog-strict.log", "catalog-strict.json", "validate-library.log",
    "backup-method.txt", "prepare-dry-run.log", "negative-internal.log", "prepare.log", "status.log",
)
ID_PATTERN = re.compile(r"(?<![0-9A-Fa-f])[0-9A-Fa-f]{16}(?![0-9A-Fa-f])")
VOLUME_PATTERN = re.compile(r"(?<![A-Za-z0-9_])(\\?/)Volumes\\?/[^/\\\"'\n]+")


def home_pattern(home):
    """Matches a home directory path, also when a JSON encoder escaped its slashes."""
    parts = [re.escape(part) for part in home.rstrip("/").split("/") if part]
    return re.compile(r"(?<![A-Za-z0-9_.~-])\\?/" + r"\\?/".join(parts) + r"(?![A-Za-z0-9_.-])")


def redact(text, homes):
    """Replaces the home directories, volume names, and persistent IDs. Home paths are replaced first so that
    a volume name inside a home path cannot survive."""
    for home in sorted({h for h in homes if h and h != "/"}, key=len, reverse=True):
        text = home_pattern(home).sub("~", text)
    text = VOLUME_PATTERN.sub(lambda match: match.group(1) + "Volumes" + match.group(1) + "BACKUP", text)
    return ID_PATTERN.sub("<id>", text)


def digest(path):
    hasher = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def check_bundle(bundle, manifest, allow_moved=True):
    """Compares the bundle with the manifest. After `ilibrary add`, staging files that were moved away are
    expected to be absent; every other difference is a failure."""
    problems, moved, verified = [], 0, 0
    for relative, expected in sorted(manifest["files"].items()):
        path = bundle / relative
        if not path.is_file():
            if allow_moved and relative.startswith("staging/"):
                moved += 1
            else:
                problems.append(f"missing: {relative}")
        elif digest(path) != expected:
            problems.append(f"differs: {relative}")
        else:
            verified += 1
    if problems:
        return f"FAIL ({'; '.join(problems)})"
    if not allow_moved:
        return f"PASS ({verified} files verified)"
    return f"PASS ({verified} files verified; {moved} staging files absent, as expected after ilibrary add)"


def check_archive(archive_directory):
    archive = archive_directory / ARCHIVE
    recorded = archive_directory / (ARCHIVE + ".sha256")
    if not archive.is_file() or not recorded.is_file():
        return "not checked (the transferred archive or its checksum file is not present)"
    fields = recorded.read_text().split()
    if not fields:
        return "FAIL (the checksum file is empty)"
    return "PASS" if digest(archive) == fields[0] else "FAIL (the archive differs from its checksum file)"


def build_report(bundle, homes, archive_directory=ARCHIVE_DIRECTORY):
    manifest = load_manifest(bundle)
    lines = [
        f"source commit: {manifest['commit']}",
        "iLibrary M11 backup and inventory qualification report",
        f"manifest format: {manifest['format']}",
        f"bundle SHA-256 check: {check_bundle(bundle, manifest)}",
        f"archive SHA-256 check: {check_archive(archive_directory)}",
        "",
    ]
    results = bundle / "results"
    present = sorted(p.name for p in results.iterdir() if p.is_file()) if results.is_dir() else []
    for name in [*EXPECTED_RESULTS, *[n for n in present if n not in EXPECTED_RESULTS]]:
        lines.append(f"== results/{name} ==")
        if name in present:
            lines.append(((results / name).read_text(errors="replace")).rstrip("\n"))
        else:
            lines.append("NOT RUN")
        lines.append("")
    return redact("\n".join(lines), homes)


def write_new(path, text):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    with os.fdopen(descriptor, "w") as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
    if Path(path).read_text() != text:
        raise SystemExit("m11_collect: the saved report differs from the text written")


def load_manifest(bundle):
    manifest = json.loads((bundle / "manifest.json").read_text())
    if manifest.get("format") != FORMAT:
        raise SystemExit(f"m11_collect: unexpected manifest format {manifest.get('format')!r}")
    return manifest


def main(arguments, bundle=None):
    if arguments == ["--check"]:
        bundle = bundle or Path(__file__).resolve().parent
        manifest = load_manifest(bundle)
        result = check_bundle(bundle, manifest, allow_moved=False)
        print(f"source commit: {manifest['commit']}")
        print(f"bundle SHA-256 check: {result}")
        if result.startswith("FAIL"):
            raise SystemExit(1)
        return
    if len(arguments) != 1 or arguments[0].startswith("--"):
        raise SystemExit("usage: m11_collect.py REPORT | --check")
    report = Path(arguments[0])
    if os.path.lexists(report):
        raise SystemExit(f"m11_collect: {report} already exists; it is never overwritten")
    if not report.parent.is_dir():
        raise SystemExit(f"m11_collect: the folder of {report} does not exist")
    bundle = bundle or Path(__file__).resolve().parent
    home = os.path.expanduser("~")
    text = build_report(bundle, {home, os.path.realpath(home)})
    write_new(report, text)
    print(f"PASS: report saved to {report}")


if __name__ == "__main__":
    main(sys.argv[1:])
