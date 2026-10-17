#!/usr/bin/env python3
"""Build distribution files from a clean commit; never publish or overwrite them."""

import base64
import csv
import gzip
import hashlib
import io
import json
from pathlib import Path
import platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TAG = "py3-none-macosx_14_0_arm64"
PYPI_NAME = "x96_64-ilibrary"


def run(*args, cwd=ROOT):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_wheel(stage, version, out):
    name = f"x96_64_ilibrary-{version}"
    info = f"{name}.dist-info"
    metadata = "\n".join([
        "Metadata-Version: 2.1", f"Name: {PYPI_NAME}", f"Version: {version}",
        "Summary: Catalog-driven music tagging and ordered import into Apple Music",
        "Home-page: https://github.com/x96x64/ilibrary", "License: Apache-2.0",
        "Classifier: Development Status :: 3 - Alpha",
        "Classifier: Operating System :: MacOS", "Classifier: Environment :: Console",
        "Requires-Python: >=3.9", "Description-Content-Type: text/markdown", "",
        (stage / "README.md").read_text(),
    ])
    entries = {
        f"{name}.data/scripts/ilibrary": ((stage / "bin/ilibrary").read_bytes(), 0o755),
        f"{info}/METADATA": (metadata.encode(), 0o644),
        f"{info}/WHEEL": (
            f"Wheel-Version: 1.0\nGenerator: iLibrary\nRoot-Is-Purelib: false\nTag: {TAG}\n".encode(), 0o644),
        f"{info}/LICENSE": ((stage / "LICENSE").read_bytes(), 0o644),
    }
    records = io.StringIO(newline="")
    writer = csv.writer(records, lineterminator="\n")
    for name_in_wheel, (data, _) in entries.items():
        digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
        writer.writerow((name_in_wheel, f"sha256={digest}", len(data)))
    writer.writerow((f"{info}/RECORD", "", ""))
    entries[f"{info}/RECORD"] = (records.getvalue().encode(), 0o644)
    with zipfile.ZipFile(out / f"{name}-{TAG}.whl", "x", zipfile.ZIP_DEFLATED) as archive:
        for name_in_wheel, (data, mode) in entries.items():
            item = zipfile.ZipInfo(name_in_wheel, date_time=(2026, 1, 1, 0, 0, 0))
            item.create_system = 3
            item.external_attr = (stat.S_IFREG | mode) << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(item, data)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 packaging/build.py NEW_OUTPUT_DIRECTORY")
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("Distribution builds require macOS on Apple silicon.")
    if run("git", "status", "--porcelain"):
        raise SystemExit("Commit all source changes before packaging.")
    version = re.search(r'^let version = "(\d+\.\d+\.\d+)"$',
                        (ROOT / "Sources/ilibrary/CommandLineInterface.swift").read_text(), re.M)
    if not version:
        raise SystemExit("The source version must be a three-part numeric version.")
    version = version[1]
    commit = run("git", "rev-parse", "HEAD")
    out = Path(sys.argv[1]).resolve()
    if out.exists():
        raise SystemExit("The output directory already exists; choose a new directory.")
    # Build from the same clean tree that supplies the source archive and metadata.
    subprocess.run(["swift", "build", "-c", "release", "--product", "ilibrary"], cwd=ROOT, check=True)
    binary = ROOT / ".build/release/ilibrary"
    if run(str(binary), "--version") != f"ilibrary {version}":
        raise SystemExit("The built executable does not match the source version.")
    if run("lipo", "-archs", str(binary)) != "arm64":
        raise SystemExit("Expected an arm64 executable.")
    out.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="ilibrary-package-") as temporary:
        stage = Path(temporary)
        (stage / "bin").mkdir()
        shutil.copy2(binary, stage / "bin/ilibrary")
        subprocess.run(["strip", "-x", str(stage / "bin/ilibrary")], check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(stage / "bin/ilibrary")], check=True)
        shutil.copyfile(ROOT / "LICENSE", stage / "LICENSE")
        shutil.copyfile(ROOT / "packaging/README.md", stage / "README.md")
        # The tar archive contains neither local ownership nor local timestamps.
        def normalize(item):
            item.uid = item.gid = 0
            item.uname = item.gname = ""
            item.mtime = 0
            return item
        with (out / f"ilibrary-{version}-macos-arm64.tar.gz").open("xb") as target:
            with gzip.GzipFile(filename="", mode="wb", fileobj=target, mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode="w") as archive:
                    for entry in ("bin", "LICENSE", "README.md"):
                        archive.add(stage / entry, arcname=entry, filter=normalize)
        package = json.loads((ROOT / "packaging/npm/package.json").read_text())
        package["version"] = version
        (stage / "package.json").write_text(json.dumps(package, indent=2) + "\n")
        subprocess.run(["npm", "pack", "--ignore-scripts", "--silent", "--pack-destination", str(out)],
                       cwd=stage, check=True)
        make_wheel(stage, version, out)
        binary_hash = sha256(stage / "bin/ilibrary")
    source = out / f"ilibrary-{version}-source.tar.gz"
    with source.open("xb") as target:
        with gzip.GzipFile(filename="", mode="wb", fileobj=target, mtime=0) as compressed:
            archive = subprocess.Popen(["git", "archive", "--format=tar", f"--prefix=ilibrary-{version}/", commit],
                                       cwd=ROOT, stdout=subprocess.PIPE)
            shutil.copyfileobj(archive.stdout, compressed)
            archive.stdout.close()
            if archive.wait() != 0:
                raise SystemExit("Source archiving failed.")
    formula = (ROOT / "packaging/homebrew/ilibrary.rb.in").read_text()
    (out / "ilibrary.rb").write_text(formula.replace("__VERSION__", version).replace("__SHA256__", sha256(source)))
    context = {
        "version": version, "source_commit": commit, "packaging_commit": commit, "binary_sha256": binary_hash,
        "platform": "macos-arm64", "deployment_target": "14.0",
        "build_macos": platform.mac_ver()[0], "swift": run("swift", "--version").splitlines()[0],
        "signing": "ad-hoc", "notarized": False,
    }
    (out / "build-info.json").write_text(json.dumps(context, indent=2) + "\n")
    if run("git", "rev-parse", "HEAD") != commit or run("git", "status", "--porcelain"):
        raise SystemExit("The source changed during packaging; discard these outputs.")
    (out / "SHA256SUMS").write_text("".join(f"{sha256(p)}  {p.name}\n" for p in sorted(out.iterdir())))
    print(f"Prepared {len(list(out.iterdir()))} files for iLibrary {version} from {commit}.")


if __name__ == "__main__":
    main()
