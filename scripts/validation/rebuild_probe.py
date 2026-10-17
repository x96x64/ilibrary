#!/usr/bin/env python3
"""M10 synthetic feasibility probe, not a product command or a recovery tool.

Preparation never sends Apple Events. Live execution requires a separate test user,
an initially empty library, and explicit local confirmation. No live command is
run by the agent during preparation. Results expose counts, not paths or IDs.
"""

import argparse
import collections
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import shutil
import stat
import subprocess
import sys
import time
import urllib.parse
import unicodedata


FORMAT = "ilibrary-m10-probe-1"
ARTIST = "iLibrary M10 Synthetic Artist"
CASES = {"small": (3, 2), "scale": (20, 15)}
PROBE_VERSION = 2
_diagnostic_work = None
_last_inventory_summary = None


class Refusal(Exception):
    pass


def require(condition, message):
    if not condition:
        raise Refusal(message)


def safe_path(path):
    path = Path(os.path.abspath(path))
    for part in (path, *path.parents):
        require(not part.is_symlink(), "シンボリックリンクを含む場所は使用できません。")
    return path


def digest(path):
    require(path.is_file() and not path.is_symlink(), "必要な通常ファイルがありません。")
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hashlib.sha256(stream.read()).hexdigest()


def run(command, *, input_text=None):
    # Never print captured stderr: paths and Music IDs belong only in local records.
    result = subprocess.run(command, input=input_text, text=True, capture_output=True, timeout=600)
    record_diagnostic("command", {"argv": command, "returncode": result.returncode,
                                  "stdout": result.stdout if result.returncode or command[0] != "/usr/bin/osascript" else "",
                                  "stderr": result.stderr})
    require(result.returncode == 0,
            f"外部コマンドが完了しませんでした（終了コード {result.returncode}）。結果を報告してください。")
    return result.stdout.rstrip("\r\n")


def record_diagnostic(kind, value):
    if _diagnostic_work is not None:
        with (_diagnostic_work / "diagnostics.jsonl").open("a", encoding="utf-8") as output:
            output.write(json.dumps({"kind": kind, "value": value}, ensure_ascii=False) + "\n")


def write_json(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def synthetic_album(index):
    return f"M10 Album {index:02d}"


def catalog(albums, tracks, edited=False):
    return {"format": "ilibrary-catalog-1", "albums": [
        {"album": synthetic_album(a), "albumArtist": ARTIST, "artist": ARTIST,
         "releaseDate": f"{2000 + a:04d}-01-02", "genre": "Synthetic",
         "discs": [{"tracks": [
             {"title": f"M10 Song {t:02d}", "composer": "M10 Edited Writer" if edited else "M10 Original Writer"}
             for t in range(1, tracks + 1)]}]}
        for a in range(1, albums + 1)]}


def prepare(output, binary, tagger, audio, commit, dry_run=False):
    output = safe_path(output)
    require(not output.exists(), "準備先が既にあります。上書きしません。")
    require(re.fullmatch(r"[0-9a-f]{40}", commit), "コミットの識別情報が不正です。")
    print("予定: 合成音声、検証用実行ファイル、カタログを新しい準備先へ保存します。Music は読みません。")
    if dry_run:
        print("Dry run: 準備先を作成していません。")
        return
    output.mkdir(parents=True)
    (output / "bin").mkdir()
    shutil.copy2(binary, output / "bin/ilibrary")
    shutil.copy2(__file__, output / "rebuild_probe.py")
    shutil.copy2(Path(__file__).resolve().parents[2] / "docs/rebuild-feasibility-validation.md", output / "PROCEDURE.md")
    manifest = {"format": FORMAT, "probeVersion": PROBE_VERSION, "commit": commit, "files": {}, "cases": {}}
    for name, (albums, tracks) in CASES.items():
        case = output / name
        case.mkdir()
        entries = []
        for a in range(1, albums + 1):
            directory = case / "files" / synthetic_album(a)
            directory.mkdir(parents=True)
            for t in range(1, tracks + 1):
                file = directory / f"{t:02d} M10 Song {t:02d}.m4a"
                run([str(tagger), "tag", str(audio), str(file),
                     "--set", f"©nam=M10 Song {t:02d}", "--set", f"©ART={ARTIST}",
                     "--set", f"aART={ARTIST}", "--set", f"©alb={synthetic_album(a)}",
                     "--set", f"©day={2000 + a:04d}-01-02T00:00:00Z",
                     "--set", "©wrt=M10 Original Writer", "--set", "©gen=Synthetic",
                     "--track", f"{t}/{tracks}", "--disc", "1/1"])
                entries.append(str(file.relative_to(case / "files")))
        write_json(case / "catalog.json", catalog(albums, tracks))
        write_json(case / "edited-catalog.json", catalog(albums, tracks, edited=True))
        run([str(output / "bin/ilibrary"), "validate", str(case / "catalog.json"), str(case / "files")])
        run([str(output / "bin/ilibrary"), "validate", str(case / "edited-catalog.json"), str(case / "files")])
        manifest["cases"][name] = {"albums": albums, "tracks": len(entries), "files": entries}
    for file in sorted(output.rglob("*")):
        if file.is_file():
            manifest["files"][str(file.relative_to(output))] = digest(file)
    write_json(output / "manifest.json", manifest)
    verify_bundle(output)
    print("PASS: 6 曲と 300 曲の準備、カタログ照合、全ファイルのハッシュ照合。Music 未操作。")


def verify_bundle(bundle):
    bundle = safe_path(bundle)
    manifest = json.loads(safe_path(bundle / "manifest.json").read_text())
    require(manifest.get("format") == FORMAT, "検証一式の形式が違います。")
    require(re.fullmatch(r"[0-9a-f]{40}", manifest.get("commit", "")), "コミット情報が不正です。")
    actual = {str(p.relative_to(bundle)) for p in bundle.rglob("*")
              if p.is_file() and "reference-private" not in p.relative_to(bundle).parts}
    require(actual == set(manifest["files"]) | {"manifest.json"}, "検証一式のファイル一覧が一致しません。")
    for relative, expected in manifest["files"].items():
        path = safe_path(bundle / relative)
        require(path.is_relative_to(bundle) and digest(path) == expected, "検証一式の内容が変わっています。")
    for name, (albums, tracks) in CASES.items():
        expected = [f"{synthetic_album(a)}/{t:02d} M10 Song {t:02d}.m4a"
                    for a in range(1, albums + 1) for t in range(1, tracks + 1)]
        require(manifest["cases"][name] == {"albums": albums, "tracks": albums * tracks, "files": expected},
                "合成音声の一覧が不正です。")
    return manifest


def require_test_user(name=None):
    # Do not trust USER or LOGNAME: the guard must identify the actual process owner.
    name = pwd.getpwuid(os.getuid()).pw_name if name is None else name
    require(re.fullmatch(r"(?:ilibrarytest|ilibrary-test)[a-zA-Z0-9_-]*", name) is not None,
            "別の検証用ユーザーに切り替えてください。Music は操作していません。")
    require(os.getuid() != 0, "管理者権限で実行しないでください。")


def check_account():
    # Absence of a readable account preference is supplemented by an explicit
    # human confirmation. Neither this nor an 'unknown' cloud status proves sync off.
    result = subprocess.run(["/usr/bin/defaults", "export", "MobileMeAccounts", "-"], capture_output=True)
    if result.returncode == 0:
        accounts = plistlib.loads(result.stdout)
        require(not accounts.get("Accounts"), "Apple Account が設定されています。新しい検証用ユーザーを使ってください。")
    else:
        require(b"does not exist" in result.stderr or b"not found" in result.stderr,
                "Apple Account の設定を確認できません。状態を報告してください。")


def media_directory(home):
    value = run(["/usr/bin/defaults", "read", "com.apple.Music", "media-folder-url"])
    parsed = urllib.parse.urlparse(value)
    require(parsed.scheme == "file" and parsed.netloc in ("", "localhost"), "メディアフォルダの設定が不明です。")
    media = safe_path(urllib.parse.unquote(parsed.path))
    require(media.is_dir() and media.is_relative_to(safe_path(home / "Music")),
            "メディアフォルダが検証用ユーザーの Music フォルダ内にありません。")
    return media


SNAPSHOT = '''
on stamp(d)
    set base to current date
    set day of base to 1
    set year of base to 2000
    set month of base to January
    set time of base to 0
    return (d - base) as integer
end stamp
on run argv
    set output to ""
    set fs to character id 31
    set rs to character id 30
    with timeout of 300 seconds
        tell application "Music"
            set ts to every track of library playlist 1
            repeat with t in ts
                if class of t is not file track then error "Non-file track"
                set legacyPath to ""
                set legacyError to ""
                try
                    set legacyPath to POSIX path of (location of t)
                on error errText number errNumber
                    set legacyError to errNumber as text
                end try
                set p to ""
                set pathError to ""
                try
                    set p to POSIX path of (get location of t)
                on error errText number errNumber
                    set pathError to errNumber as text
                end try
                set output to output & (persistent ID of t) & fs & (name of t) & fs & (album of t) & fs & (artist of t) & fs & p & fs & ((my stamp(date added of t)) as text) & fs & legacyPath & fs & legacyError & fs & pathError & rs
            end repeat
        end tell
    end timeout
    return output
end run
'''

DELETE = '''
on run argv
    with timeout of 120 seconds
        tell application "Music"
            set ts to (every file track of library playlist 1 whose persistent ID is (item 1 of argv))
            if (count ts) is not 1 then error "Identity changed"
            set t to item 1 of ts
            if name of t is not (item 2 of argv) then error "Title changed"
            if album of t is not (item 3 of argv) then error "Album changed"
            if artist of t is not (item 4 of argv) then error "Artist changed"
            delete t
        end tell
    end timeout
end run
'''


def music(script, *args):
    return run(["/usr/bin/osascript", "-", *args], input_text=script)


def snapshot():
    records = []
    # Keep the raw response before parsing or comparing: failed reads and path
    # differences must remain diagnosable without repeating a destructive run.
    raw = music(SNAPSHOT)
    record_diagnostic("snapshot", raw)
    for row in raw.split(chr(30)):
        if not row.strip():
            continue
        fields = row.split(chr(31))
        require(len(fields) == 9 and re.fullmatch(r"[0-9A-Fa-f]{16}", fields[0]) is not None,
                "Music の登録情報を確認できません。")
        records.append(dict(zip(("id", "title", "album", "artist", "path", "added",
                                 "legacy_path", "legacy_error", "path_error"), fields)))
    require(len({r["id"] for r in records}) == len(records), "登録の識別子が重複しています。")
    return records


def location_diagnostics(records, expected_paths):
    """Classify differences without accepting, normalizing, or following them."""
    counts = collections.Counter()
    expected = {str(p) for p in expected_paths.values()}
    normalized = {unicodedata.normalize("NFC", os.path.normpath(p)) for p in expected}
    for record in records:
        for label, key, error in (("get", "path", "path_error"), ("legacy", "legacy_path", "legacy_error")):
            path = record.get(key, "")
            if record.get(error):
                state = "read_error"
            elif not path:
                state = "empty"
            elif path in expected:
                state = "exact"
            elif unicodedata.normalize("NFC", os.path.normpath(path)) in normalized:
                state = "representation_only"
            else:
                state = "different"
            counts[label + "." + state] += 1
    return "; ".join(f"{label}.{state}={counts[label + '.' + state]}"
                     for label in ("get", "legacy")
                     for state in ("exact", "representation_only", "empty", "read_error", "different"))


def stable_registration(records):
    # Auxiliary diagnostic fields are not library state.
    return sorted(({key: r[key] for key in ("id", "title", "album", "artist", "path", "added")}
                   for r in records), key=lambda r: r["id"])


def assert_inventory(records, expected_paths, expected_ids=None, old_paths=None):
    global _last_inventory_summary
    _last_inventory_summary = (f"expected tracks={len(expected_paths)}; observed tracks={len(records)}; "
                               + location_diagnostics(records, expected_paths))
    record_diagnostic("inventory-check", {"summary": _last_inventory_summary,
                      "expected": {r: str(p) for r, p in expected_paths.items()},
                      "expected_ids": expected_ids,
                      "old_paths": {r: str(p) for r, p in (old_paths or {}).items()}})
    require(len(records) == len(expected_paths), "ライブラリの件数が計画と違います。追加の削除はしません。")
    if expected_ids is not None:
        require({r["id"] for r in records} == set(expected_ids), "ライブラリの登録が変わりました。")
    seen = set()
    for record in records:
        matches = [relative for relative in expected_paths
                   if Path(relative).parent.name == record["album"] and
                   Path(relative).stem[3:] == record["title"]]
        require(record["artist"] == ARTIST and len(matches) == 1, "この測定以外の登録があります。")
        relative = matches[0]
        require(relative not in seen, "曲の対応が重複しています。")
        seen.add(relative)
        allowed = {str(expected_paths[relative])}
        if old_paths is not None:
            allowed.add(str(old_paths[relative]))
        require(not record.get("path_error"), "Music の保存場所を取得できませんでした。")
        require(record["path"] in allowed, "Music が予期しない場所を参照しています。")


def file_state(paths):
    states = {}
    for relative, path in paths.items():
        path = safe_path(path)
        info = path.stat()
        require(stat.S_ISREG(info.st_mode), "通常ファイル以外が含まれています。")
        states[relative] = {"sha256": digest(path), "size": info.st_size,
                            "modified_ns": info.st_mtime_ns,
                            "created": getattr(info, "st_birthtime", None)}
    return states


def compare_files(paths, expected):
    require(file_state(paths) == expected, "ファイルの内容または日時が変わりました。これ以上の変更を止めます。")


def date_result(records):
    values = [int(r["added"]) for r in records]
    require(values, "追加日時がありません。")
    return {"unique": len(set(values)), "span_seconds": max(values) - min(values),
            "equal": len(set(values)) == 1}


def remove_seeded(records, paths, originals, states, image, image_hash, mount):
    remaining = list(records)
    for record in records:
        expected = {r: paths[r] for r in paths if any(
            t["album"] == Path(r).parent.name and t["title"] == Path(r).stem[3:] for t in remaining)}
        assert_inventory(snapshot(), expected, [r["id"] for r in remaining], originals)
        compare_files(paths, states)
        require(digest(image) == image_hash and not os.path.ismount(mount), "保存用コピーが変化しました。")
        music(DELETE, record["id"], record["title"], record["album"], ARTIST)
        remaining = [r for r in remaining if r["id"] != record["id"]]
        compare_files(paths, states)
    require(not snapshot(), "全登録が空になっていません。")


def music_running():
    result = subprocess.run(["/usr/bin/pgrep", "-u", str(os.getuid()), "-x", "Music"], capture_output=True)
    require(result.returncode in (0, 1), "Music の終了状態を確認できません。")
    return result.returncode == 0


def wait_until_closed():
    deadline = time.monotonic() + 30
    while music_running() and time.monotonic() < deadline:
        time.sleep(0.25)
    require(not music_running(), "Music が終了していません。タグは編集しません。")


def make_backup(work, paths):
    # A read-only, detached image simulates offline storage for generated media
    # only. It is not independent hardware and never qualifies a real backup.
    source = work / "backup-input"
    source.mkdir()
    for relative, path in paths.items():
        dest = source / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        run(["/usr/bin/ditto", str(path), str(dest)])
        require(path.stat().st_ino != dest.stat().st_ino, "バックアップが独立したコピーではありません。")
    expected = file_state(paths)
    compare_files({r: source / r for r in paths}, expected)
    image = work / "synthetic-backup.dmg"
    run(["/usr/bin/hdiutil", "create", "-quiet", "-srcfolder", str(source), "-format", "UDRO", str(image)])
    mount = work / "backup-mount"
    mount.mkdir()
    run(["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(image)])
    try:
        restored = work / "restored-backup"
        run(["/usr/bin/ditto", str(mount), str(restored)])
        compare_files({r: restored / r for r in paths}, expected)
    finally:
        run(["/usr/bin/hdiutil", "detach", str(mount)])
    require(not os.path.ismount(mount), "バックアップの切り離しを確認できません。")
    image.chmod(0o400)
    return image, digest(image), expected


def execute(bundle, case_name, dry_run=False):
    global _diagnostic_work, _last_inventory_summary
    _diagnostic_work = None
    _last_inventory_summary = None
    require(sys.platform == "darwin", "この測定は macOS 専用です。")
    require_test_user()
    bundle = safe_path(bundle)
    manifest = verify_bundle(bundle)
    require(manifest.get("probeVersion") == PROBE_VERSION, "新しい v2 の検証一式を使ってください。旧版は再実行しません。")
    home = safe_path(pwd.getpwuid(os.getuid()).pw_dir)
    require(bundle.is_relative_to(home), "検証一式を検証用ユーザーのホームフォルダへコピーしてください。")
    case = manifest["cases"][case_name]
    print(f'予定: 空の検証用ライブラリへ合成音声 {case["tracks"]} 曲を追加し、退避・登録削除・終了・タグ編集・再追加を測定します。')
    print("削除対象はこの実行で追加する曲だけです。元の検証一式と保存用コピーは保持します。")
    if dry_run:
        print("Dry run: ファイルも Music も変更していません。ライブラリの状態はまだ調べていません。")
        return 0
    work = safe_path(bundle / "reference-private" / case_name)
    require(not work.exists(), "この測定の記録が既にあります。再実行せず結果を報告してください。")
    require(not work.is_relative_to(home / "Music"), "検証一式は Music フォルダの外へ置いてください。")
    work.mkdir(parents=True, mode=0o700)
    _diagnostic_work = work
    results = work / "ilibrary-m10-results.txt"
    with results.open("x") as report:
        phase_name = "preflight"

        def log(text):
            print(text)
            report.write(text + "\n")
            report.flush()

        def step(name):
            write_json(work / f"{name}.json", {"stage": name, "time": datetime.datetime.now(datetime.timezone.utc).isoformat()})

        def phase(name):
            nonlocal phase_name
            phase_name = name
            log("PHASE: " + name)

        log("iLibrary M10 rebuilding feasibility")
        log("date: " + datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ"))
        log("commit: " + manifest["commit"])
        log("probe version: " + str(PROBE_VERSION))
        log("macOS: " + run(["/usr/bin/sw_vers", "-productVersion"]))
        log("case: " + case_name)
        log(f'albums: {case["albums"]}; tracks: {case["tracks"]}')
        binary = bundle / "bin/ilibrary"

        def cli(*args):
            result = subprocess.run([str(binary), *map(str, args)], capture_output=True, text=True, timeout=600)
            with (work / "commands.log").open("a") as output:
                output.write(result.stdout + result.stderr)
            record_diagnostic("cli", {"argv": list(map(str, args)), "returncode": result.returncode,
                                      "stdout": result.stdout, "stderr": result.stderr})
            require(result.returncode == 0, "iLibrary の検査または処理が完了しませんでした。")

        try:
            phase("preflight")
            check_account()
            require(input("検証用ユーザーで Apple Account 未設定・同期なし・新しい空の Music ライブラリを選択済みなら TEST と入力: ") == "TEST",
                    "開始を取り消しました。")
            media = media_directory(home)
            record_diagnostic("media", str(media))
            require(not snapshot(), "Music に登録があります。削除せず停止しました。新しい空のライブラリを使ってください。")
            require(not work.is_relative_to(media) and not media.is_relative_to(bundle), "作業場所とメディアフォルダが重なっています。")
            require(shutil.disk_usage(media).free > 256 * 1024 * 1024 and shutil.disk_usage(bundle).free > 256 * 1024 * 1024,
                    "合成測定用の空き容量が不足しています。")
            step("started")
            phase("initial-addition")
            seed = work / "seed"
            shutil.copytree(bundle / case_name / "files", seed)
            cli("apply", bundle / case_name / "catalog.json", seed, "--timestamps")
            cli("add", seed, "--order", "release", "--dry-run")
            cli("add", seed, "--order", "release")
            originals = {r: media / "Music" / ARTIST / r for r in case["files"]}
            records = snapshot()
            write_json(work / "initial-registration.json", records)
            record_diagnostic("expected-locations", {r: str(p) for r, p in originals.items()})
            phase("initial-location-check")
            log("MEASURED: initial locations: " + location_diagnostics(records, originals))
            assert_inventory(records, originals)
            log("PASS: initial registrations match only the generated files")
            step("seeded")
            phase("backup")
            image, image_hash, original_states = make_backup(work, originals)
            write_json(work / "original-files.json", original_states)
            log("PASS: synthetic backup restored, verified, and detached (same physical storage)")
            phase("evacuation")
            retreat = work / "evacuated"
            paths = {r: retreat / r for r in case["files"]}
            require(retreat.stat().st_dev == media.stat().st_dev if retreat.exists() else work.stat().st_dev == media.stat().st_dev,
                    "M10 の退避は同じボリュームだけで測定します。")
            for relative, source in originals.items():
                destination = paths[relative]
                safe_path(destination)
                require(not destination.exists(), "退避先が既にあります。")
                destination.parent.mkdir(parents=True, exist_ok=True)
                source.rename(destination)
            compare_files(paths, original_states)
            relocated = snapshot()
            log("MEASURED: evacuated locations: " + location_diagnostics(relocated, paths))
            assert_inventory(relocated, paths, [r["id"] for r in records], originals)
            log("PASS: evacuation retained every byte and file date")
            step("evacuated")
            phase("registration-removal")
            remove_seeded(records, paths, originals, original_states, image, image_hash, work / "backup-mount")
            log("PASS: only inventoried registrations removed; evacuated files unchanged")
            step("cleared")
            phase("empty-gui-confirmation")
            music('tell application "Music" to activate')
            require(input("Music の「曲」と「最近追加した項目」が空になったことを見て確認し、EMPTY と入力: ") == "EMPTY",
                    "GUI が空であることを確認できませんでした。終了・編集は行いません。")
            require(not snapshot(), "GUI 確認中に登録が変わりました。")
            log("PASS: empty GUI confirmed by maintainer (not automated GUI detection)")
            phase("quit")
            music('tell application "Music" to quit')
            wait_until_closed()
            step("quit")
            log("PASS: Music terminated after the library and GUI became empty")
            phase("editing-while-closed")
            require(not music_running(), "Music が再起動しています。編集を止めます。")
            cli("apply", bundle / case_name / "edited-catalog.json", retreat, "--timestamps", "--dry-run")
            cli("apply", bundle / case_name / "edited-catalog.json", retreat, "--timestamps")
            cli("check", retreat)
            require(not music_running(), "編集中に Music が起動しました。")
            log("PASS: catalog applied while Music remained closed")
            edited_states = file_state(paths)
            step("edited")
            phase("readdition")
            # The product's add path performs one album per call, with confirmation.
            require(not snapshot(), "再起動したライブラリに登録があります。追加しません。")
            cli("add", retreat, "--order", "release")
            final = snapshot()
            write_json(work / "final-registration.json", final)
            log("MEASURED: final locations: " + location_diagnostics(final, originals))
            assert_inventory(final, originals)
            compare_files(originals, edited_states)
            cli("check", media / "Music" / ARTIST, "--library")
            journal = json.loads((retreat / ".ilibrary-add.json").read_text())
            require([e["album"] for e in journal["entries"]] == [synthetic_album(a) for a in range(1, case["albums"] + 1)],
                    "追加の順番が計画と違います。")
            log("PASS: one registration per file; release order and file/library metadata verified")
            dates = date_result(final)
            log(f'MEASURED: distinct addition timestamps: {dates["unique"]}; span seconds: {dates["span_seconds"]}')
            log(("PASS" if dates["equal"] else "FAIL") + ": every track has exactly the same addition timestamp")
            phase("recently-added-gui-confirmation")
            music('tell application "Music" to activate')
            print("「最近追加した項目」の先頭（新しい側）から Album の番号を確認してください。期待する順は大きい番号から小さい番号です。")
            answer = input("全アルバムの順序を確認できたら EXPECTED、違う場合 DIFFERENT、判断できない場合 UNKNOWN と入力: ")
            require(answer in ("EXPECTED", "DIFFERENT", "UNKNOWN"), "表示順の回答を記録できませんでした。")
            log(("PASS" if answer == "EXPECTED" else "FAIL") + ": Recently Added order: " + answer)
            phase("repeat-and-preservation-check")
            require(digest(image) == image_hash, "保存用コピーが変化しました。")
            # Completed add must not create another registration or change its date.
            cli("add", retreat, "--order", "release")
            require(stable_registration(snapshot()) == stable_registration(final),
                    "再実行で登録が変わりました。")
            log("PASS: completed addition is unchanged on repetition")
            log("PASS: original synthetic backup retained unchanged")
            step("completed")
            phase("complete")
            passed = dates["equal"] and answer == "EXPECTED"
            log("case gate: " + ("PASS" if passed else "NOT SATISFIED; M11 remains blocked"))
            log("Automatic GUI emptiness detection: NOT IMPLEMENTED")
            log("No personal library or private recordings were used. Synthetic registrations remain for inspection.")
            return 0 if passed else 1
        except (Refusal, OSError, ValueError, KeyError, subprocess.TimeoutExpired, EOFError, KeyboardInterrupt) as error:
            # Do not echo raw errors, which may contain personal paths or IDs.
            log("STOP: measurement incomplete; preserve the test user and all files; do not rerun")
            log("stopped phase: " + phase_name)
            log("reason: " + (str(error) if isinstance(error, Refusal) else type(error).__name__))
            if _last_inventory_summary is not None:
                log("last inventory check: " + _last_inventory_summary)
            log("case gate: NOT SATISFIED")
            with (work / "failure.txt").open("w") as raw:
                raw.write(type(error).__name__ + ": " + str(error) + "\n")
            return 1
        finally:
            _diagnostic_work = None


def combined_report(bundle):
    bundle = safe_path(bundle)
    manifest = verify_bundle(bundle)
    require(manifest.get("probeVersion") == PROBE_VERSION, "v2 の結果だけをまとめてください。")
    print("iLibrary M10 combined report; probe version 2")
    for name in CASES:
        print("\n== " + name)
        result = safe_path(bundle / "reference-private" / name / "ilibrary-m10-results.txt")
        if result.is_file():
            print(result.read_text(), end="")
        else:
            print("NOT RUN: no saved case result")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prep = commands.add_parser("prepare")
    for option in ("output", "binary", "tagger", "audio", "commit"):
        prep.add_argument("--" + option, required=True)
    prep.add_argument("--dry-run", action="store_true")
    check = commands.add_parser("verify")
    check.add_argument("bundle", type=Path)
    live = commands.add_parser("run")
    live.add_argument("--bundle", type=Path, default=Path(__file__).resolve().parent)
    live.add_argument("--case", choices=CASES, required=True)
    live.add_argument("--dry-run", action="store_true")
    report = commands.add_parser("report")
    report.add_argument("--bundle", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            prepare(Path(args.output), Path(args.binary), Path(args.tagger), Path(args.audio), args.commit, args.dry_run)
        elif args.command == "verify":
            verify_bundle(args.bundle)
            print("PASS: bundle verification; Music not accessed")
        elif args.command == "report":
            combined_report(args.bundle)
        else:
            return execute(args.bundle, args.case, args.dry_run)
    except (Refusal, OSError, ValueError, KeyError, subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        print("STOP: " + (str(error) if isinstance(error, Refusal) else "準備または入力の条件を確認できません。"))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
