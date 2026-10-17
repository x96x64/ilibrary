#!/usr/bin/env python3
"""Correct unpublished registry metadata while preserving reviewed program bytes."""

import argparse
import gzip
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

import build
from verify import digest, require, tar_files


def reviewed_files(directory, manifest_digest):
    manifest = (directory / "SHA256SUMS").read_bytes()
    require(digest(manifest) == manifest_digest, "The original manifest is not the reviewed manifest.")
    rows = [line.split("  ") for line in manifest.decode().splitlines()]
    require(len(rows) == 6 and all(len(row) == 2 for row in rows), "Invalid original manifest.")
    names = [row[1] for row in rows]
    require(len(set(names)) == len(names), "Duplicate original manifest entry.")
    require(all(Path(name).name == name and name not in (".", "..") for name in names),
            "Unsafe original manifest entry.")
    require({p.name for p in directory.iterdir()} == set(names) | {"SHA256SUMS"},
            "Unexpected original files.")
    for expected, name in rows:
        path = directory / name
        require(path.is_file() and not path.is_symlink(), "Invalid original file.")
        require(digest(path.read_bytes()) == expected, f"Original checksum mismatch: {name}")
    return json.loads((directory / "build-info.json").read_bytes())


def main(args):
    require(re.fullmatch(r"[0-9a-f]{64}", args.manifest_sha256), "Invalid original manifest digest.")
    require(not build.run("git", "status", "--porcelain"), "Commit packaging changes first.")
    packaging_commit = build.run("git", "rev-parse", "HEAD")
    original, out = args.original.resolve(), args.output.resolve()
    require(not out.exists(), "The output directory must not exist.")
    info = reviewed_files(original, args.manifest_sha256)
    version = info["version"]
    require(re.fullmatch(r"\d+\.\d+\.\d+", version), "Invalid original version.")
    require(re.fullmatch(r"[0-9a-f]{40}", info["source_commit"]), "Invalid original source commit.")
    source_name = f"ilibrary-{version}-source.tar.gz"
    archive_name = f"ilibrary-{version}-macos-arm64.tar.gz"
    contents = tar_files(original / archive_name)
    require(set(contents) == {"bin/ilibrary", "LICENSE", "README.md"}, "Unexpected original archive.")
    require(digest(contents["bin/ilibrary"]) == info["binary_sha256"], "Original program digest differs.")
    out.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="ilibrary-metadata-") as temporary:
        stage = Path(temporary)
        (stage / "bin").mkdir()
        for name in ("bin/ilibrary", "LICENSE"):
            (stage / name).write_bytes(contents[name])
        (stage / "bin/ilibrary").chmod(0o755)
        shutil.copyfile(build.ROOT / "packaging/README.md", stage / "README.md")

        def normalize(item):
            item.uid = item.gid = 0
            item.uname = item.gname = ""
            item.mtime = 0
            return item

        with (out / archive_name).open("xb") as target:
            with gzip.GzipFile(filename="", mode="wb", fileobj=target, mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode="w") as archive:
                    for entry in ("bin", "LICENSE", "README.md"):
                        archive.add(stage / entry, arcname=entry, filter=normalize)
        package = json.loads((build.ROOT / "packaging/npm/package.json").read_text())
        package["version"] = version
        (stage / "package.json").write_text(json.dumps(package, indent=2) + "\n")
        subprocess.run(["npm", "pack", "--ignore-scripts", "--silent", "--pack-destination", str(out)],
                       cwd=stage, check=True)
        build.make_wheel(stage, version, out)
    for name in (source_name, "ilibrary.rb"):
        shutil.copyfile(original / name, out / name)
    info.update(packaging_commit=packaging_commit, previous_manifest_sha256=args.manifest_sha256)
    (out / "build-info.json").write_text(json.dumps(info, indent=2) + "\n")
    require(build.run("git", "rev-parse", "HEAD") == packaging_commit
            and not build.run("git", "status", "--porcelain"), "The packaging checkout changed.")
    (out / "SHA256SUMS").write_text("".join(f"{build.sha256(p)}  {p.name}\n" for p in sorted(out.iterdir())))
    print(f"Prepared corrected metadata from {packaging_commit}; original executable and source are unchanged.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--manifest-sha256", required=True)
    main(parser.parse_args())
