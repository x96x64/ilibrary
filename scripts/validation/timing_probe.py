#!/usr/bin/env python3
"""Isolated M10 addition-timing experiment; no registration removal or product change."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import display_probe as display

base = display.base
require, safe_path, digest, write_json = base.require, base.safe_path, base.digest, base.write_json
FORMAT = "ilibrary-m10-timing-2"
NAME = "timing-v2-small"
WAIT_SECONDS = 2.0
WAIT_LIMIT = 30.0
PRIOR_SOURCE = "f6511d56250504d82f1c55c1039905838615ebbc"
PRIOR_REPORT = "6b859c028563f78efd741344ace1ebf23c67f70b0748ef11f029f68113795cfe"
STOPPED_SOURCE = "1493bdaa36257c848730a6fcdaabca17d24f1068"
STOPPED_REPORT = "5db76008caa4b5796bd05063f3edaa0a0b345c90503851970373e36ca3c32181"
STOPPED_INVENTORY = "2476349b1562f831fc09cc7863592c7b35cf79d59f66a0479449f899be9f4b47"
# Music 1.7 created these in a new Media.localized folder (measured inventory); contents are never read.
LOCALIZATION = re.compile(r"[a-z]{2,3}(?:_[A-Za-z0-9]{2,4})?\.strings")
SCAFFOLDING_LIMIT = 65536
MEDIA_ENTRY_LIMIT = 5000
MEDIA_DEPTH_LIMIT = 20


def spec():
    result = display.case_spec("small-existing")
    result["library"] = "M10-timing-v2-small"
    return result


def expected_files():
    return {"bin/ilibrary", "timing_probe.py", "display_probe.py", "rebuild_probe.py", "PROCEDURE.md",
            "catalog.json", "edited-catalog.json"} | {"files/" + r for r in display.relatives(spec())}


def verify_bundle(bundle):
    bundle = safe_path(bundle)
    manifest = json.loads(safe_path(bundle / "manifest.json").read_text())
    require(manifest.get("format") == FORMAT and re.fullmatch(r"[0-9a-f]{40}", manifest.get("commit", "")),
            "日時比較一式の形式が違います。")
    require(manifest.get("spec") == spec() and manifest.get("wait_seconds") == WAIT_SECONDS and
            manifest.get("wait_limit") == WAIT_LIMIT, "検証計画が変わっています。")
    require(set(manifest["files"]) == expected_files(), "必要な入力の一覧が違います。")
    base.verify_bundle_files(bundle, expected_files() | {"manifest.json"})
    for relative, checksum in manifest["files"].items():
        require(digest(safe_path(bundle / relative)) == checksum, "検証一式の内容が変わっています。")
    return manifest


def prepare(output, binary, tagger, audio, commit, dry_run=False):
    output = safe_path(output)
    require(not output.exists(), "準備先が既にあります。上書きしません。")
    require(re.fullmatch(r"[0-9a-f]{40}", commit), "コミット情報が不正です。")
    print("予定: 新しい日時比較一式と合成3アルバム・6曲を作成します。Musicと旧一式は操作しません。")
    if dry_run:
        return
    output.mkdir(parents=True)
    (output / "bin").mkdir()
    shutil.copy2(binary, output / "bin/ilibrary")
    for name in ("timing_probe.py", "display_probe.py", "rebuild_probe.py"):
        shutil.copy2(Path(__file__).with_name(name), output / name)
    shutil.copy2(Path(__file__).resolve().parents[2] / "docs/rebuild-timing-validation.md", output / "PROCEDURE.md")
    for album in spec()["albums"]:
        for track in range(1, album["tracks"] + 1):
            dest = output / "files" / album["artist"] / album["album"] / f"{track:02d} M10 Song {track:02d}.m4a"
            dest.parent.mkdir(parents=True, exist_ok=True)
            base.run([str(tagger), "tag", str(audio), str(dest), "--set", f"©nam=M10 Song {track:02d}",
                      "--set", f'©ART={album["artist"]}', "--set", f'aART={album["artist"]}',
                      "--set", f'©alb={album["album"]}', "--set", f'©day={album["date"]}T00:00:00Z',
                      "--set", "©wrt=M10 Original Writer", "--set", "©gen=Synthetic", "--track", "2/2" if track == 2 else "1/2",
                      "--disc", "1/1"])
    for edited, filename in ((False, "catalog.json"), (True, "edited-catalog.json")):
        write_json(output / filename, display.catalog(spec(), edited))
        base.run([str(output / "bin/ilibrary"), "validate", str(output / filename), str(output / "files")])
    manifest = {"format": FORMAT, "commit": commit, "spec": spec(), "wait_seconds": WAIT_SECONDS,
                "wait_limit": WAIT_LIMIT, "files": {r: digest(output / r) for r in sorted(expected_files())}}
    write_json(output / "manifest.json", manifest)
    verify_bundle(output)
    print("PASS: 合成6曲、2カタログ、検証一式の照合。Music未操作。")


def media_category(relative, info):
    """Classify one entry of a new media folder from its name, type, and size only."""
    parts = relative.split("/")
    if stat.S_ISDIR(info.st_mode):
        return "directory"
    if not stat.S_ISREG(info.st_mode):
        return None
    if parts[-1] == ".DS_Store":
        return "finder-state"
    if info.st_size > SCAFFOLDING_LIMIT:
        return None
    if parts == [".Media Preferences.plist"]:
        return "music-preferences"
    localized = parts[:-1] == [".localized"] or (
        len(parts) == 3 and parts[0].endswith(".localized") and parts[1] == ".localized")
    if localized and LOCALIZATION.fullmatch(parts[-1]):
        return "music-localization"
    return None


def media_inventory(media):
    """List a new media folder without following links or opening any file."""
    rows = []

    def visit(directory, prefix, depth):
        require(depth <= MEDIA_DEPTH_LIMIT, "新しいメディアフォルダの階層が深すぎます。")
        with os.scandir(directory) as entries:
            for entry in sorted(entries, key=lambda e: e.name):
                require(len(rows) < MEDIA_ENTRY_LIMIT, "新しいメディアフォルダの項目が多すぎます。")
                info = entry.stat(follow_symlinks=False)
                kind = ("directory" if stat.S_ISDIR(info.st_mode) else "file" if stat.S_ISREG(info.st_mode) else
                        "symlink" if stat.S_ISLNK(info.st_mode) else "other")
                row = {"relative": prefix + entry.name, "type": kind, "size": info.st_size,
                       "category": media_category(prefix + entry.name, info)}
                rows.append(row)
                if kind == "directory":
                    visit(entry.path, row["relative"] + "/", depth + 1)

    visit(safe_path(media), "", 0)
    return rows


def wait_between(check, clock=time.monotonic, sleep=time.sleep):
    """Wait after confirmation, then recheck state. Never infer Music dates from this clock."""
    start = clock()
    check()
    while True:
        remaining = WAIT_SECONDS - (clock() - start)
        if remaining <= 0:
            break
        sleep(min(0.25, remaining))
    check()
    elapsed = clock() - start
    require(WAIT_SECONDS <= elapsed <= WAIT_LIMIT, "待機中の確認が制限時間を超えました。次の追加は行いません。")
    return elapsed


def timing_boundary(previous, current):
    prior = [base.addition_seconds(r["added"]) for r in previous]
    added = [base.addition_seconds(r["added"]) for r in current]
    require(added, "新しいアルバムの追加日時がありません。")
    return {"previous_max": max(prior) if prior else None, "current_min": min(added),
            "current_max": max(added), "gap_seconds": min(added) - max(prior) if prior else None,
            "separated": not prior or min(added) > max(prior)}


class Measurement(display.Measurement):
    def __init__(self, bundle, manifest, home):
        self.bundle, self.name, self.manifest, self.home = bundle, NAME, manifest, home
        self.spec = spec()
        self.work = safe_path(bundle / "reference-private" / NAME)
        require(not self.work.exists(), "この測定の記録が既にあります。再実行せず報告してください。")
        self.work.mkdir(parents=True, mode=0o700)
        self.phase = "preflight"
        self.report = (self.work / "result.txt").open("x")
        self.result = {"case": NAME, "state": "STOP", "phase": self.phase, "observations": [],
                       "boundaries": [], "commit": manifest["commit"], "started": display.now()}
        self.started, self.media = time.monotonic(), None

    def unchanged(self, rows, paths):
        self.guard()
        require(base.music_running(), "Musicが終了しています。次の追加は行いません。")
        current = base.snapshot()
        display.inventory(current, paths)
        require(display.stable(current) == display.stable(rows), "確認済みの登録が変わりました。")

    def measure(self):
        self.step("empty-library")
        require(not self.capture("initial-registration", {}), "新しい空のライブラリではありません。")
        entries = media_inventory(self.media)
        write_json(self.work / "initial-media.json", entries)
        refused = [e for e in entries if e["category"] is None]
        counts = {c: sum(e["category"] == c for e in entries)
                  for c in ("directory", "finder-state", "music-preferences", "music-localization")}
        self.log(f"MEASURED: new media folder entries: {len(entries)}; directories: {counts['directory']}; "
                 f"Finder state: {counts['finder-state']}; Music preferences: {counts['music-preferences']}; "
                 f"Music localization: {counts['music-localization']}; refused: {len(refused)}")
        if refused:
            first = refused[0]
            self.log(f"REFUSED: first media entry {first['relative']!r}; type {first['type']}; size {first['size']}")
        require(not refused, "新しいメディアフォルダに想定外の項目があります。削除・移動せず報告してください。")
        self.log("PASS: new media folder holds no audio or other unexpected entry; contents were not read")
        self.step("copy-and-backup")
        staging = self.work / "staging"
        base.run(["/usr/bin/ditto", str(self.bundle / "files"), str(staging)])
        paths = {r: staging / r for r in display.relatives(self.spec)}
        self.cli("apply", self.bundle / "catalog.json", staging, "--timestamps", "--dry-run")
        self.cli("apply", self.bundle / "catalog.json", staging, "--timestamps")
        image, image_hash, original_states = base.make_backup(self.work, paths)
        write_json(self.work / "original-files.json", original_states)
        def backup_check():
            require(digest(image) == image_hash and not os.path.ismount(self.work / "backup-mount"),
                    "保存用コピーの内容か切り離し状態が変わりました。")
            base.compare_files({r: self.work / "restored-backup" / r for r in paths}, original_states)
        backup_check()
        self.log("PASS: synthetic original backup restored, verified, and detached; same physical storage")
        self.step("quit-and-edit")
        self.unchanged([], {})
        base.music('tell application "Music" to quit')
        base.wait_until_closed()
        require(not base.music_running(), "Musicが起動しています。編集しません。")
        self.cli("apply", self.bundle / "edited-catalog.json", staging, "--timestamps", "--dry-run")
        self.cli("apply", self.bundle / "edited-catalog.json", staging, "--timestamps")
        self.cli("check", staging)
        require(not base.music_running(), "編集中にMusicが起動しました。")
        states = base.file_state(paths)
        write_json(self.work / "edited-files.json", states)
        self.log("PASS: working copies edited while Music remained closed")
        self.step("separated-addition")
        self.guard()
        require(not self.capture("before-addition", {}), "再起動後のライブラリに登録があります。")
        final, destinations, journals = [], {}, []
        for album in self.spec["albums"]:
            number = album["number"]
            album_spec = dict(self.spec, albums=[album], addition=[number], display=[number])
            selected = display.relatives(album_spec)
            source = staging / album["artist"] / album["album"]
            self.unchanged(final, destinations)
            backup_check()
            base.compare_files({r: destinations.get(r, p) for r, p in paths.items()}, states)
            waited = wait_between(lambda: self.unchanged(final, destinations)) if final else 0
            self.log(f"WAIT: before album {number:02d}; observed monotonic seconds: {waited:.3f}")
            # One invocation contains exactly one album; the published executable is unchanged.
            self.cli("add", source, "--order", "release", "--dry-run")
            self.unchanged(final, destinations)
            backup_check()
            base.compare_files({r: destinations.get(r, p) for r, p in paths.items()}, states)
            self.cli("add", source, "--order", "release")
            destinations.update({r: self.media / "Music" / r for r in selected})
            current = self.capture(f"after-album-{number:02d}", destinations)
            prior_ids = {r["id"] for r in final}
            require(display.stable([r for r in current if r["id"] in prior_ids]) == display.stable(final),
                    "前のアルバムの登録が変わりました。")
            added = [r for r in current if r["id"] not in prior_ids]
            display.inventory(added, {r: destinations[r] for r in selected})
            boundary = timing_boundary(final, added)
            boundary.update(album=number, waited_seconds=round(waited, 3), observed_at=display.now())
            self.result["boundaries"].append(boundary)
            write_json(self.work / f"boundary-{number:02d}.json", boundary)
            self.log(f"MEASURED: album {number:02d}; minimum {boundary['current_min']}; maximum {boundary['current_max']}; "
                     f"gap from previous maximum: {boundary['gap_seconds']}; separated: {boundary['separated']}")
            require(boundary["separated"], "追加日時が前のアルバムより後になっていません。追加済みの曲を残して停止します。")
            journal = source / ".ilibrary-add.json"
            checksum = display.journal_check(journal, album_spec, paths, destinations, added)
            journals.append((journal, checksum, album_spec, added))
            base.compare_files({r: destinations.get(r, p) for r, p in paths.items()}, states)
            backup_check()
            final = current
        self.cli("check", self.media / "Music", "--library")
        self.result["dates"] = display.date_diagnostics(final)
        self.log("PASS: all three album timestamp ranges strictly increase without overlap")
        self.log(f"MEASURED: distinct addition timestamps: {self.result['dates']['unique']}; span seconds: {self.result['dates']['span_seconds']}")
        self.unchanged(final, destinations)
        self.observe("display-before-relaunch")
        self.step("relaunch")
        self.unchanged(final, destinations)
        base.music('tell application "Music" to quit')
        base.wait_until_closed()
        self.guard()
        require(display.stable(self.capture("after-relaunch", destinations)) == display.stable(final),
                "再起動で登録が変わりました。")
        self.observe("display-after-relaunch")
        self.step("repeat-and-preservation")
        for journal, checksum, album_spec, added in journals:
            self.unchanged(final, destinations)
            require(display.journal_check(journal, album_spec, paths, destinations, added) == checksum,
                    "完了済みの追加記録が変わりました。")
            self.cli("add", journal.parent, "--order", "release", "--dry-run")
            self.cli("add", journal.parent, "--order", "release")
            self.unchanged(final, destinations)
            require(digest(journal) == checksum, "再実行で追加記録が変わりました。")
        base.compare_files(destinations, states)
        backup_check()
        verify_bundle(self.bundle)
        self.log("PASS: repeated completed addition preserves IDs, dates, files, and all three journals")
        self.log("PASS: original synthetic backup and immutable bundle inputs verified at the final checkpoint")
        statuses = [o["status"] for o in self.result["observations"]]
        self.result["state"] = "PASS" if statuses == ["PASS", "PASS"] else ("FAIL" if "FAIL" in statuses else "UNVERIFIED")
        self.step("complete")


def execute(bundle, dry_run=False):
    require(sys.platform == "darwin", "この測定はmacOS専用です。")
    base.require_test_user()
    home = safe_path(base.pwd.getpwuid(os.getuid()).pw_dir)
    bundle = safe_path(bundle)
    require(bundle.is_relative_to(home) and not bundle.is_relative_to(home / "Music"),
            "一式は検証用ユーザーのホーム内、Musicフォルダ外へ置いてください。")
    manifest = verify_bundle(bundle)
    print("予定: 新しい空のM10-timing-v2-smallだけに合成3アルバムを追加します。登録削除は行いません。")
    print("予定: コピーの保全と編集、アルバム間の待機と日時照合、画面確認2回、完了済み追加の再実行を行います。")
    if dry_run:
        print("Dry run: Musicへのアクセスとファイル作成は行っていません。")
        return 0
    m = Measurement(bundle, manifest, home)
    base._diagnostic_work = m.work
    try:
        m.log("iLibrary M10 separated-addition timing validation")
        m.log("source commit: " + manifest["commit"])
        m.log("case: " + NAME)
        m.log("albums: 3; tracks: 6")
        m.log("planned addition album numbers: 1,2,3")
        m.log("planned display album numbers: 3,2,1")
        m.log("started: " + m.result["started"])
        m.log("macOS: " + base.run(["/usr/bin/sw_vers", "-productVersion"]))
        base.check_account()
        require(input("検証用ユーザー・Apple Account未設定・同期なし・新しい空のM10-timing-v2-smallを確認し、TESTと入力: ").strip() == "TEST",
                "開始を取り消しました。")
        m.media = display.selected_media(home, m.spec)
        m.log("PASS: selected media folder matches the new library; name: " + m.media.name)
        require(base.music_running(), "手順の新しいライブラリをMusicで開いてください。")
        require(shutil.disk_usage(m.media).free > 256 * 1024 * 1024 and shutil.disk_usage(bundle).free > 256 * 1024 * 1024,
                "合成検証用の空き容量が不足しています。")
        m.log("Music version: " + base.music('tell application "Music" to return version'))
        write_json(m.work / "plan.json", {"spec": m.spec, "media": str(m.media), "wait_seconds": WAIT_SECONDS,
                                          "wait_limit": WAIT_LIMIT, "time": display.now()})
        m.measure()
    except (base.Refusal, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired, EOFError, KeyboardInterrupt) as error:
        m.result["state"] = "STOP"
        m.log("STOP: measurement incomplete; preserve all state; do not rerun")
        m.log("stopped phase: " + m.phase)
        m.log("reason: " + (str(error) if isinstance(error, base.Refusal) else type(error).__name__))
        (m.work / "failure.txt").write_text(type(error).__name__ + ": " + str(error) + "\n")
    finally:
        m.result["finished"] = display.now()
        m.result["elapsed_seconds"] = round(time.monotonic() - m.started, 3)
        m.log("elapsed seconds: " + str(m.result["elapsed_seconds"]))
        m.log("case result: " + m.result["state"])
        write_json(m.work / "result.json", m.result)
        m.report.close()
        base._diagnostic_work = None
    return 1 if m.result["state"] == "STOP" else 0


def report(bundle, output, dry_run=False):
    bundle, output = safe_path(bundle), safe_path(output)
    manifest = verify_bundle(bundle)
    require(not output.exists() and output.parent.is_dir(), "報告先が既に存在するか、親フォルダがありません。上書きしません。")
    require(not output.is_relative_to(bundle), "共有報告は検証一式の外へ保存してください。")
    result = safe_path(bundle / "reference-private" / NAME / "result.txt")
    text = "iLibrary M10 timing comparison report\nsource commit: " + manifest["commit"] + "\n\n"
    text += ("== Historical comparison; not rerun\nsource commit: " + PRIOR_SOURCE + "\nreport SHA-256: " + PRIOR_REPORT +
             "\nObserved display before and after relaunch: 2,3,1; expected: 3,2,1\n"
             "Two distinct addition timestamps; one-second span; cross-album ties observed\n\n"
             "== Stopped timing comparison; not rerun\nsource commit: " + STOPPED_SOURCE + "\nreport SHA-256: " +
             STOPPED_REPORT + "\ninventory SHA-256: " + STOPPED_INVENTORY +
             "\nStopped in empty-library before addition; Music-created preference and localization files were refused\n\n"
             "== New isolated case\n")
    text += result.read_text() if result.is_file() else "NOT RUN: no saved measurement\n"
    saved = safe_path(result.with_name("result.json"))
    if result.is_file():
        if saved.is_file():
            data = json.loads(saved.read_text())
            require(data.get("case") == NAME and data.get("commit") == manifest["commit"] and
                    data.get("state") in ("PASS", "FAIL", "UNVERIFIED", "STOP"), "保存した結果の識別情報が違います。")
            require(f"case result: {data['state']}\n" in text and
                    (data["state"] == "STOP" or data.get("phase") == "complete"), "結果の本文と終了記録が一致しません。")
        else:
            text += "\nSTOP: final result record missing; measurement incomplete\n"
    text += ("\n== Scope\nNo registration removal in this experiment.\n"
             "A passing small timing case does not complete M10.\n"
             "Scale, other orders, and a production timing policy remain unqualified.\n"
             "Automatic GUI emptiness detection and independent physical backup remain unqualified.\n")
    print("予定: 共有場所へ新しい要約報告を1件保存します。元の結果は保持します。")
    if not dry_run:
        with output.open("x") as stream:
            stream.write(text)
        require(output.read_text() == text, "保存した報告の照合に失敗しました。")
        print("PASS: 共有報告を保存・照合しました。")
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prep = commands.add_parser("prepare")
    for option in ("output", "binary", "tagger", "audio", "commit"):
        prep.add_argument("--" + option, required=True)
    prep.add_argument("--dry-run", action="store_true")
    verify = commands.add_parser("verify")
    verify.add_argument("bundle", type=Path)
    live = commands.add_parser("run")
    live.add_argument("--bundle", type=Path, default=Path(__file__).resolve().parent)
    live.add_argument("--dry-run", action="store_true")
    summary = commands.add_parser("report")
    summary.add_argument("--bundle", type=Path, default=Path(__file__).resolve().parent)
    summary.add_argument("--output", required=True, type=Path)
    summary.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            prepare(Path(args.output), Path(args.binary), Path(args.tagger), Path(args.audio), args.commit, args.dry_run)
        elif args.command == "verify":
            verify_bundle(args.bundle)
            print("PASS: 検証一式の照合。Music未操作。")
        elif args.command == "report":
            report(args.bundle, args.output, args.dry_run)
        else:
            return execute(args.bundle, args.dry_run)
    except (base.Refusal, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        print("STOP: " + (str(error) if isinstance(error, base.Refusal) else "準備または入力の条件を確認できません。"))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
