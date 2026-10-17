#!/usr/bin/env python3
"""Check that an explicitly selected experimental release retains its reviewed identity."""

import json
import re
import subprocess
import sys

REPOSITORY = "x96x64/ilibrary"


def api(path):
    return json.loads(subprocess.check_output(["gh", "api", f"repos/{REPOSITORY}/{path}"], text=True))


def main(tag, commit):
    if not re.fullmatch(r"v0\.\d+\.\d+", tag) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise SystemExit("An experimental v0.x.y tag and full reviewed commit are required.")
    if api(f"commits/{tag}")["sha"] != commit:
        raise SystemExit("The tag no longer points to the reviewed commit.")
    if api(f"compare/{commit}...main")["status"] not in ("ahead", "identical"):
        raise SystemExit("The reviewed commit must be integrated into main.")
    release = api(f"releases/tags/{tag}")
    if release["draft"] or release["tag_name"] != tag:
        raise SystemExit("A published GitHub release for the selected experimental tag is required.")
    print(f"Verified {tag} at {commit}.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: check_release.py TAG REVIEWED_COMMIT")
    main(*sys.argv[1:])
