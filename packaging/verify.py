#!/usr/bin/env python3
"""Audit reviewed package bytes and optionally install them into temporary prefixes."""

import argparse
import base64
import csv
from email.parser import BytesParser
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile
import tempfile
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def tar_files(path):
    with tarfile.open(path) as archive:
        members = archive.getmembers()
        require(len({m.name for m in members}) == len(members), "Duplicate archive entries.")
        for member in members:
            parts = PurePosixPath(member.name).parts
            require(not member.name.startswith("/") and ".." not in parts, "Unsafe archive path.")
            require(member.isfile() or member.isdir(), "Links and special files are not allowed.")
        return {m.name: archive.extractfile(m).read() for m in members if m.isfile()}


def historical_package_readme(commit, root=None):
    require(re.fullmatch(r"[0-9a-f]{40}", commit), "Invalid packaging commit.")
    try:
        return subprocess.check_output(
            ["git", "show", f"{commit}:packaging/README.md"],
            cwd=root or Path(__file__).resolve().parents[1], stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as error:
        raise ValueError("Fetch the recorded packaging commit before verifying corrected metadata.") from error


def smoke(binary, version, schema):
    def output(*args):
        return subprocess.check_output([str(binary), *args], text=True)
    require(output("--version").strip() == f"ilibrary {version}", "Installed version differs.")
    require(json.loads(output("schema")) == json.loads(schema), "Installed schema differs.")
    for command in ("import", "export", "apply", "timestamps", "add"):
        require("--dry-run" in output("help", command), "Installed help is incomplete.")


def verify(args):
    directory = args.directory.resolve()
    version, commit = args.version, args.commit
    require(re.fullmatch(r"\d+\.\d+\.\d+", version), "Invalid version.")
    require(re.fullmatch(r"[0-9a-f]{40}", commit), "Invalid source commit.")
    names = {
        f"ilibrary-{version}-macos-arm64.tar.gz", f"ilibrary-{version}-source.tar.gz",
        f"x96_64-ilibrary-{version}.tgz", f"x96_64_ilibrary-{version}-py3-none-macosx_14_0_arm64.whl",
        "ilibrary.rb", "build-info.json",
    }
    require({p.name for p in directory.iterdir()} == names | {"SHA256SUMS"}, "Unexpected or missing release files.")
    require(all(p.is_file() and not p.is_symlink() for p in directory.iterdir()), "Invalid release entry.")
    manifest = (directory / "SHA256SUMS").read_bytes()
    if args.manifest_sha256:
        require(digest(manifest) == args.manifest_sha256, "The manifest is not the reviewed manifest.")
    rows = [line.split("  ") for line in manifest.decode().splitlines()]
    require(len(rows) == len(names) and all(len(row) == 2 for row in rows), "Invalid checksum manifest.")
    require({row[1] for row in rows} == names, "The checksum list differs from the release files.")
    for expected, name in rows:
        require(digest((directory / name).read_bytes()) == expected, f"Checksum mismatch: {name}")
    info = json.loads((directory / "build-info.json").read_bytes())
    require(info["version"] == version and info["source_commit"] == commit, "Build identity differs.")
    archive = tar_files(directory / f"ilibrary-{version}-macos-arm64.tar.gz")
    require(set(archive) == {"bin/ilibrary", "LICENSE", "README.md"}, "Unexpected binary archive contents.")
    binary = archive["bin/ilibrary"]
    require(digest(binary) == info["binary_sha256"], "The recorded binary digest differs.")
    require(binary[:4] == b"\xcf\xfa\xed\xfe", "The executable is not a 64-bit Mach-O file.")
    require(b"/Users/" not in binary and b"/home/" not in binary, "The executable contains a personal build path.")
    npm = tar_files(directory / f"x96_64-ilibrary-{version}.tgz")
    require(set(npm) == {"package/bin/ilibrary", "package/LICENSE", "package/README.md", "package/package.json"},
            "Unexpected npm contents.")
    package = json.loads(npm["package/package.json"])
    require(package["name"] == "@x96_64/ilibrary" and package["version"] == version, "npm identity differs.")
    require(package["os"] == ["darwin"] and package["cpu"] == ["arm64"], "npm platform differs.")
    require(package["bin"] == {"ilibrary": "bin/ilibrary"}, "npm executable mapping differs.")
    require(not package.get("scripts") and not package.get("dependencies"), "Unexpected npm runtime dependency.")
    require(npm["package/bin/ilibrary"] == binary, "npm executable differs.")
    require(npm["package/README.md"] == archive["README.md"], "npm README differs.")
    wheel_name = f"x96_64_ilibrary-{version}"
    dist = f"{wheel_name}.dist-info"
    with zipfile.ZipFile(directory / f"{wheel_name}-py3-none-macosx_14_0_arm64.whl") as wheel:
        expected_entries = {f"{wheel_name}.data/scripts/ilibrary", *(f"{dist}/{n}" for n in ("METADATA", "WHEEL", "LICENSE", "RECORD"))}
        require(set(wheel.namelist()) == expected_entries and len(wheel.namelist()) == len(expected_entries),
                "Unexpected wheel contents.")
        require(wheel.read(f"{wheel_name}.data/scripts/ilibrary") == binary, "PyPI executable differs.")
        metadata = BytesParser().parsebytes(wheel.read(f"{dist}/METADATA"))
        require(metadata["Name"] == "x96_64-ilibrary" and metadata["Version"] == version, "PyPI identity differs.")
        require(metadata["Requires-Python"] == ">=3.9" and not metadata.get_all("Requires-Dist"), "Unexpected Python dependency.")
        require(metadata.get_payload().strip() == archive["README.md"].decode().strip(), "PyPI README differs.")
        require(b"Tag: py3-none-macosx_14_0_arm64" in wheel.read(f"{dist}/WHEEL"), "Wheel platform differs.")
        records = list(csv.reader(io.StringIO(wheel.read(f"{dist}/RECORD").decode())))
        require(len(records) == len(expected_entries) and {r[0] for r in records} == expected_entries, "Wheel RECORD differs.")
        for name, expected, length in records:
            if name == f"{dist}/RECORD":
                require(expected == length == "", "Wheel RECORD self-entry is invalid.")
            else:
                content = wheel.read(name)
                actual = base64.urlsafe_b64encode(hashlib.sha256(content).digest()).rstrip(b"=").decode()
                require(expected == f"sha256={actual}" and int(length) == len(content), "Invalid wheel RECORD hash.")
    source = tar_files(directory / f"ilibrary-{version}-source.tar.gz")
    prefix = f"ilibrary-{version}/"
    forbidden = {"reference-private", "artifacts", ".build", ".git", "node_modules", ".DS_Store", "__pycache__"}
    for name in source:
        require(name.startswith(prefix) and not forbidden.intersection(PurePosixPath(name).parts), "Unexpected source archive path.")
    require(f'let version = "{version}"'.encode() in source[prefix + "Sources/ilibrary/CommandLineInterface.swift"],
            "Source version differs.")
    packaging_commit = info.get("packaging_commit", commit)
    require(re.fullmatch(r"[0-9a-f]{40}", packaging_commit), "Invalid packaging commit.")
    if packaging_commit == commit:
        require(source[prefix + "packaging/README.md"] == archive["README.md"], "Source README differs.")
    else:
        # Metadata-only corrections preserve the tagged executable and source archive.
        require(historical_package_readme(packaging_commit) == archive["README.md"],
                "The corrected package README differs from its recorded packaging commit.")
    for content in (npm["package/LICENSE"], source[prefix + "LICENSE"]):
        require(content == archive["LICENSE"], "License differs.")
    formula = (directory / "ilibrary.rb").read_text()
    source_hash = digest((directory / f"ilibrary-{version}-source.tar.gz").read_bytes())
    require(f'sha256 "{source_hash}"' in formula and f'version "{version}"' in formula, "Formula identity differs.")
    require(f"releases/download/v{version}/ilibrary-{version}-source.tar.gz" in formula, "Formula URL differs.")
    print("PASS: checksums, identities, contents, licenses, README, wheel RECORD, and shared executable")
    if args.install:
        with tempfile.TemporaryDirectory(prefix="ilibrary-install-") as temporary:
            root = Path(temporary)
            executable = root / "ilibrary"
            executable.write_bytes(binary)
            executable.chmod(0o755)
            subprocess.run(["codesign", "--verify", "--strict", str(executable)], check=True)
            require(subprocess.check_output(["lipo", "-archs", str(executable)], text=True).strip() == "arm64",
                    "Unexpected executable architecture.")
            load_commands = subprocess.check_output(["otool", "-l", str(executable)], text=True)
            require(re.search(r"\bminos 14\.0\b", load_commands), "Unexpected deployment target.")
            schema = source[prefix + "docs/schema/ilibrary-catalog-1.schema.json"]
            smoke(executable, version, schema)
            environment = dict(os.environ, npm_config_cache=str(root / "npm-cache"))
            subprocess.run(["npm", "install", "-g", "--prefix", str(root / "npm"), "--offline", "--ignore-scripts",
                            "--no-audit", "--no-fund", str(directory / f"x96_64-ilibrary-{version}.tgz")],
                           env=environment, check=True)
            smoke(root / "npm/bin/ilibrary", version, schema)
            subprocess.run([sys.executable, "-m", "venv", str(root / "venv")], check=True)
            subprocess.run([str(root / "venv/bin/python"), "-m", "pip", "install", "--no-index", "--no-deps",
                            str(directory / f"{wheel_name}-py3-none-macosx_14_0_arm64.whl")], check=True)
            smoke(root / "venv/bin/ilibrary", version, schema)
            print("PASS: archive, npm, and pip installations; signature, architecture, and deployment target")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--manifest-sha256")
    parser.add_argument("--install", action="store_true")
    verify(parser.parse_args())
