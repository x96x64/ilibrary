#!/usr/bin/env python3
"""Inspect the retained M10 v2 bundle without running it or addressing Music.

The target is read-only. Relative names are written only to a new diagnostic
record under reference-private; console output contains counts, not filenames.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import stat
import sys

EXPECTED_MANIFEST = "0f2a5b7d4da2db5d9427b9a3bcba0252409622211e2231683014dc01ef327d64"
EXPECTED_COMMIT = "9fe4a53f8ef5aa78cb6245f48360ad5044cf780e"
DESTINATION = Path("/Users/Shared/reference-private/m10-display-inventory/inventory.json")


def checked_path(path):
    path = Path(os.path.abspath(path))
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError("symbolic path")
    return path


def sha256(path):
    path = checked_path(path)
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError("not a regular file")
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def inspect_bundle(root, expected_hash=EXPECTED_MANIFEST):
    root = checked_path(root)
    manifest_path = checked_path(root / "manifest.json")
    result = {"format": "ilibrary-m10-bundle-inventory-1",
              "expected_commit": EXPECTED_COMMIT,
              "manifest_sha256": sha256(manifest_path),
              "manifest_matches": False, "file_list_matches": None,
              "missing": [], "extra": [], "non_regular": [],
              "content_mismatches": [], "unreadable": []}
    if result["manifest_sha256"] != expected_hash:
        return result
    result["manifest_matches"] = True
    manifest = json.loads(manifest_path.read_text())
    expected = set(manifest["files"]) | {"manifest.json"}
    for name in expected:
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("unsafe manifest path")
    actual = set()
    scanned_entries = 0

    def scan_error(error):
        raise error

    # Prune private records before traversal. Do not follow any symbolic link.
    for directory, dirs, files in os.walk(root, followlinks=False, onerror=scan_error):
        dirs[:] = [name for name in dirs if name != "reference-private"]
        scanned_entries += len(dirs) + len(files)
        if scanned_entries > 5000:
            raise ValueError("inventory limit exceeded")
        for name in dirs[:]:
            entry = Path(directory) / name
            if entry.is_symlink():
                result["non_regular"].append(str(entry.relative_to(root)))
                dirs.remove(name)
        for name in files:
            entry = Path(directory) / name
            relative = str(entry.relative_to(root))
            if "reference-private" in entry.relative_to(root).parts:
                continue
            if stat.S_ISREG(entry.lstat().st_mode):
                actual.add(relative)
            else:
                result["non_regular"].append(relative)
    result["expected_files"] = len(expected)
    result["regular_files"] = len(actual)
    result["missing"] = sorted(expected - actual)
    result["extra"] = sorted(actual - expected)
    result["non_regular"].sort()
    result["file_list_matches"] = actual == expected and not result["non_regular"]
    for name in sorted(set(manifest["files"]) & actual):
        try:
            if sha256(root / name) != manifest["files"][name]:
                result["content_mismatches"].append(name)
        except (OSError, ValueError):
            result["unreadable"].append(name)
    return result


def save_report(result, destination):
    destination = checked_path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    if json.loads(destination.read_text()) != result:
        raise ValueError("report verification failed")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="state the diagnostic plan without reading the bundle or writing a report")
    args = parser.parse_args(argv)
    try:
        account = pwd.getpwuid(os.getuid())
        if os.getuid() == 0 or not re.fullmatch(r"(?:ilibrarytest|ilibrary-test)[a-zA-Z0-9_-]*", account.pw_name):
            raise ValueError("test user required")
        if DESTINATION.exists() or DESTINATION.is_symlink():
            raise FileExistsError()
        print("予定: 以前の検証一式を読み取り、差分の記録だけを共有場所のreference-private内に新規保存します。")
        if args.dry_run:
            print("Dry run: 検証一式を読まず、記録も作成していません。Musicは操作していません。")
            return 0
        result = inspect_bundle(Path(account.pw_dir) / "ilibrary-m10-v2")
        save_report(result, DESTINATION)
        print("確認完了: 診断結果の保存と読み戻しが一致しました。")
        print("元の識別情報との一致:", result["manifest_matches"])
        print("元の一覧との一致:", result["file_list_matches"])
        for label, field in (("不足", "missing"), ("追加", "extra"), ("リンク等", "non_regular"),
                             ("内容の差", "content_mismatches"), ("読み取り不能", "unreadable")):
            print(label + ":", len(result[field]))
        print("検証一式・音声・以前の記録は変更していません。Musicは操作していません。")
        print("報告先: /Users/Shared/reference-private/m10-display-inventory/inventory.json")
        return 0
    except (OSError, ValueError, KeyError, TypeError):
        print("STOP: 診断記録を完成できませんでした。上書き・削除・再実行せず、この表示を報告してください。")
        return 1


if __name__ == "__main__":
    sys.exit(main())
