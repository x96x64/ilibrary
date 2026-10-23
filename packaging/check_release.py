#!/usr/bin/env python3
"""Check the identity of a release before it is created or before its packages are published."""

from pathlib import Path
import json
import re
import subprocess
import sys

REPOSITORY = "x96x64/ilibrary"
ROOT = Path(__file__).resolve().parents[1]
TAG = re.compile(r"v\d+\.\d+\.\d+")
COMMIT = re.compile(r"[0-9a-f]{40}")


def api(path):
    return json.loads(subprocess.check_output(["gh", "api", f"repos/{REPOSITORY}/{path}"], text=True))


def exists(path):
    result = subprocess.run(["gh", "api", f"repos/{REPOSITORY}/{path}"], capture_output=True, text=True)
    return result.returncode == 0


def require_identifiers(tag, commit):
    if not TAG.fullmatch(tag) or not COMMIT.fullmatch(commit):
        raise SystemExit("A vX.Y.Z tag and a full commit are required.")


def require_integrated(commit):
    if api(f"compare/{commit}...main")["status"] not in ("ahead", "identical"):
        raise SystemExit("The commit must be integrated into main.")


def main(tag, commit):
    """A published release whose tag still points at the reviewed commit."""
    require_identifiers(tag, commit)
    if api(f"commits/{tag}")["sha"] != commit:
        raise SystemExit("The tag no longer points to the reviewed commit.")
    require_integrated(commit)
    release = api(f"releases/tags/{tag}")
    if release["draft"] or release["tag_name"] != tag:
        raise SystemExit("A published GitHub release for the selected tag is required.")
    print(f"Verified {tag} at {commit}.")


def check_new(tag, commit, root=ROOT):
    """A release that does not exist yet, of a commit on main whose source and changelog name its version."""
    require_identifiers(tag, commit)
    version = tag[1:]
    source = (root / "Sources/ilibrary/CommandLineInterface.swift").read_text()
    if f'let version = "{version}"' not in source:
        raise SystemExit(f"The source version is not {version}.")
    changelog = (root / "CHANGELOG.md").read_text()
    if not re.search(rf"^## \[{re.escape(version)}\] - \d{{4}}-\d{{2}}-\d{{2}}$", changelog, re.M):
        raise SystemExit(f"CHANGELOG.md has no dated section for {version}.")
    if exists(f"git/ref/tags/{tag}") or exists(f"releases/tags/{tag}"):
        raise SystemExit(f"{tag} already exists; a release is never replaced.")
    require_integrated(commit)
    print(f"Ready to release {tag} from {commit}.")


if __name__ == "__main__":
    arguments = sys.argv[1:]
    if len(arguments) == 3 and arguments[0] == "--new":
        check_new(*arguments[1:])
    elif len(arguments) == 2:
        main(*arguments)
    else:
        raise SystemExit("usage: check_release.py [--new] TAG COMMIT")
