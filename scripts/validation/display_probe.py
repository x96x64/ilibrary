#!/usr/bin/env python3
"""Guarded M10 display-order measurements; not a product rebuild command.

Preparation and reporting never address Music. Live commands are restricted to
the separate test user and named synthetic media folders. Historical small-case
reuse never evacuates, removes, or adds a new registration.
"""

import argparse
import collections
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import rebuild_probe as base


FORMAT = "ilibrary-m10-display-1"
LEGACY_COMMIT = "9fe4a53f8ef5aa78cb6245f48360ad5044cf780e"
LEGACY_MANIFEST = "0f2a5b7d4da2db5d9427b9a3bcba0252409622211e2231683014dc01ef327d64"
LEGACY_REPORT = "71e6a720c24bf20b4681ae7ece0daab2cf305079596f492481fe24c8025f4a76"
ARTIST = base.ARTIST
CASE_NAMES = ("small-existing", "scale-release", "artist", "artist-desc", "artist-release")
require = base.require
safe_path = base.safe_path
digest = base.digest
write_json = base.write_json


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def case_spec(name):
    require(name in CASE_NAMES, "検証ケースが不正です。")
    scale = name == "scale-release"
    legacy = name == "small-existing"
    count, tracks = (20, 15) if scale else ((3, 2) if legacy else (4, 2))
    albums = []
    for index in range(1, count + 1):
        artist = ARTIST if scale or legacy else ARTIST + (" A" if index % 2 == 0 else " B")
        year = 2000 + index if scale or legacy else 2005 - index
        albums.append({"number": index, "album": base.synthetic_album(index), "artist": artist,
                       "date": f"{year}-01-02", "tracks": tracks})
    order = "release" if scale or legacy else name
    numbers = list(range(1, count + 1)) if scale or legacy else {
        "artist": [2, 4, 1, 3], "artist-desc": [3, 1, 4, 2], "artist-release": [4, 2, 3, 1]}[name]
    return {"mode": order, "albums": albums, "addition": numbers, "display": list(reversed(numbers)),
            "library": "M10-v2-small" if legacy else "M10-display-" + name}


def selected_media(home, spec):
    media = base.media_directory(home)
    parent = safe_path(home / "Music" / spec["library"])
    matches = media.parent == parent and media.name in ("Media", "Media.localized")
    base.record_diagnostic("display-media-check", {
        "observed": str(media), "expected_parent": str(parent),
        "allowed_names": ["Media", "Media.localized"], "matched": matches})
    require(matches, "保存されたメディアフォルダがこのケースの対象と一致しません。設定を変えず結果を報告してください。Musicは操作しません。")
    return media


def catalog(spec, edited=False):
    return {"format": "ilibrary-catalog-1", "albums": [
        {"album": a["album"], "albumArtist": a["artist"], "artist": a["artist"],
         "genre": "Synthetic", "releaseDate": a["date"], "discs": [{"tracks": [
             {"title": f"M10 Song {t:02d}", "composer": "M10 Edited Writer" if edited else "M10 Original Writer"}
             for t in range(1, a["tracks"] + 1)]}]} for a in spec["albums"]]}


def relatives(spec):
    return [f'{a["artist"]}/{a["album"]}/{t:02d} M10 Song {t:02d}.m4a'
            for a in spec["albums"] for t in range(1, a["tracks"] + 1)]


def prepare(output, binary, tagger, audio, commit, dry_run=False):
    output = safe_path(output)
    require(not output.exists(), "準備先が既にあります。上書きしません。")
    require(re.fullmatch(r"[0-9a-f]{40}", commit), "コミット情報が不正です。")
    print("予定: 新しい検証一式と合成音声324曲を作ります。旧一式は変更せず、Musicは操作しません。")
    if dry_run:
        return
    output.mkdir(parents=True)
    (output / "bin").mkdir()
    shutil.copy2(binary, output / "bin/ilibrary")
    for name in ("display_probe.py", "rebuild_probe.py"):
        shutil.copy2(Path(__file__).with_name(name), output / name)
    shutil.copy2(Path(__file__).resolve().parents[2] / "docs/rebuild-display-validation.md", output / "PROCEDURE.md")
    manifest = {"format": FORMAT, "commit": commit, "cases": {}, "files": {}}
    for name in CASE_NAMES:
        spec = case_spec(name)
        manifest["cases"][name] = spec
        if name == "small-existing":
            continue
        directory = output / name
        directory.mkdir()
        for album in spec["albums"]:
            for track in range(1, album["tracks"] + 1):
                dest = directory / "files" / album["artist"] / album["album"] / f"{track:02d} M10 Song {track:02d}.m4a"
                dest.parent.mkdir(parents=True, exist_ok=True)
                base.run([str(tagger), "tag", str(audio), str(dest),
                          "--set", f"©nam=M10 Song {track:02d}", "--set", f'©ART={album["artist"]}',
                          "--set", f'aART={album["artist"]}', "--set", f'©alb={album["album"]}',
                          "--set", f'©day={album["date"]}T00:00:00Z', "--set", "©wrt=M10 Original Writer",
                          "--set", "©gen=Synthetic", "--track", f'{track}/{album["tracks"]}', "--disc", "1/1"])
        for edited, file in ((False, "catalog.json"), (True, "edited-catalog.json")):
            write_json(directory / file, catalog(spec, edited))
            base.run([str(output / "bin/ilibrary"), "validate", str(directory / file), str(directory / "files")])
    for relative in sorted(base.bundle_files(output)):
        manifest["files"][relative] = digest(output / relative)
    write_json(output / "manifest.json", manifest)
    verify_bundle(output)
    print("PASS: 合成音声324曲、カタログ、検証一式の照合。Music未操作。")


def verify_bundle(bundle):
    bundle = safe_path(bundle)
    manifest = json.loads(safe_path(bundle / "manifest.json").read_text())
    require(manifest.get("format") == FORMAT and re.fullmatch(r"[0-9a-f]{40}", manifest.get("commit", "")),
            "表示順検証一式の形式が違います。")
    require(manifest.get("cases") == {name: case_spec(name) for name in CASE_NAMES}, "検証計画が変わっています。")
    expected = {"bin/ilibrary", "display_probe.py", "rebuild_probe.py", "PROCEDURE.md"}
    for name in CASE_NAMES[1:]:
        expected.update(f"{name}/files/{r}" for r in relatives(case_spec(name)))
        expected.update((f"{name}/catalog.json", f"{name}/edited-catalog.json"))
    require(set(manifest["files"]) == expected, "検証一式の登録ファイル一覧が違います。")
    base.verify_bundle_files(bundle, expected | {"manifest.json"})
    for relative, checksum in manifest["files"].items():
        require(digest(safe_path(bundle / relative)) == checksum, "検証一式の内容が変わっています。")
    return manifest


def inventory(records, paths, ids=None, previous=None):
    """Require the exact synthetic identity and path for every registration."""
    require(len(records) == len(paths), "登録件数が計画と違います。変更せず停止します。")
    by_identity = {}
    for relative in paths:
        path = Path(relative)
        key = (path.parts[-3], path.parts[-2], path.stem[3:])
        require(key not in by_identity, "計画内の曲の対応が重複しています。")
        by_identity[key] = relative
    found = set()
    seen_ids = set()
    for row in records:
        require(re.fullmatch(r"[0-9a-fA-F]{16}", row["id"]) and row["id"] not in seen_ids,
                "登録の識別情報が不正です。")
        seen_ids.add(row["id"])
        relative = by_identity.get((row["artist"], row["album"], row["title"]))
        require(relative is not None and relative not in found, "対象外または重複した登録があります。")
        found.add(relative)
        allowed = {str(paths[relative])}
        if previous is not None:
            allowed.add(str(previous[relative]))
        require(not row.get("path_error") and row["path"] in allowed, "登録の保存場所が計画と違います。")
        base.addition_seconds(row["added"])
    require(ids is None or seen_ids == set(ids), "登録の識別情報が変わりました。")


def stable(records):
    return base.stable_registration([dict(r, added=str(base.addition_seconds(r["added"]))) for r in records])


def journal_check(path, spec, source, destinations, records):
    journal = json.loads(safe_path(path).read_text())
    require(journal.get("format") == "ilibrary-add-journal-1", "追加記録の形式が違います。")
    entries = journal["entries"]
    expected_albums = {a["number"]: a for a in spec["albums"]}
    require(len(entries) == len(spec["addition"]), "追加記録のアルバム数が違います。")
    for entry, number in zip(entries, spec["addition"]):
        album = expected_albums[number]
        rows = [r for r in relatives(spec) if Path(r).parts[-2] == album["album"]]
        matched = [r for r in records if r["album"] == album["album"] and r["artist"] == album["artist"]]
        require(entry["album"] == album["album"] and entry["albumArtist"] == album["artist"] and
                entry["state"] == "added" and entry["sources"] == [str(source[r] if isinstance(source, dict) else source / r) for r in rows] and
                entry["destinations"] == [str(destinations[r]) for r in rows] and
                len(entry["persistentIDs"]) == len(rows) and set(entry["persistentIDs"]) == {r["id"] for r in matched},
                "追加記録が完了済みの計画と一致しません。")
    staging = path.parent
    for child in staging.rglob("*"):
        safe_path(child)
        require(child.is_dir() or child == path, "追加元に予定外のファイルがあります。再実行しません。")
    return digest(path)


def date_diagnostics(records):
    result = base.date_result(records)
    albums = collections.defaultdict(list)
    seconds_to_albums = collections.defaultdict(set)
    for row in records:
        key = (row["artist"], row["album"])
        value = base.addition_seconds(row["added"])
        albums[key].append(value)
        seconds_to_albums[value].add(key)
    result["album_spans"] = {album: max(values) - min(values) for (_, album), values in sorted(albums.items())}
    result["cross_album_ties"] = sum(len(items) > 1 for items in seconds_to_albums.values())
    return result


def display_answer(expected, answer, observed=""):
    require(answer in ("1", "2", "3"), "回答は1・2・3から選んでください。未確認として停止します。")
    if answer == "1":
        return {"status": "PASS", "expected": expected, "observed": expected}
    if answer == "3":
        return {"status": "UNVERIFIED", "expected": expected, "observed": None}
    require(len(observed) <= 300, "表示順の入力が長すぎます。")
    if observed.strip().upper() == "UNKNOWN":
        values = None
    else:
        require(re.fullmatch(r"[0-9, ]+", observed) is not None, "表示順は番号だけで入力してください。")
        values = [int(v) for v in re.split(r"[, ]+", observed.strip()) if v]
        require(values and all(v in expected for v in values), "計画にない番号が入力されています。")
        require(values != expected, "不一致の回答と入力順が矛盾しています。")
    return {"status": "FAIL", "expected": expected, "observed": values}


def remove_seeded(records, paths, originals, states, image, image_hash, mount, guard):
    inventory(records, originals)
    by_identity = {(Path(r).parts[-3], Path(r).parts[-2], Path(r).stem[3:]): r for r in paths}
    remaining = list(records)
    for row in records:
        guard()
        selected = {by_identity[(t["artist"], t["album"], t["title"])]:
                    paths[by_identity[(t["artist"], t["album"], t["title"])]] for t in remaining}
        inventory(base.snapshot(), selected, [r["id"] for r in remaining], originals)
        base.compare_files(paths, states)
        require(digest(image) == image_hash and not os.path.ismount(mount), "保存用コピーが変化しました。")
        base.music(base.DELETE, row["id"], row["title"], row["album"], row["artist"])
        remaining = [r for r in remaining if r["id"] != row["id"]]
        base.compare_files(paths, states)
    require(not base.snapshot(), "全登録が空になっていません。")


class Measurement:
    def __init__(self, bundle, name, manifest, home):
        self.bundle, self.name, self.manifest, self.home = bundle, name, manifest, home
        self.spec = case_spec(name)
        self.work = safe_path(bundle / "reference-private" / name)
        require(not self.work.exists(), "このケースの記録が既にあります。再実行せず最後の報告手順へ進んでください。")
        self.work.mkdir(parents=True, mode=0o700)
        self.phase = "preflight"
        self.report = (self.work / "result.txt").open("x")
        self.result = {"case": name, "state": "STOP", "phase": self.phase, "observations": [],
                       "commit": manifest["commit"], "started": now()}
        self.started = time.monotonic()
        self.media = None

    def log(self, text):
        print(text, flush=True)
        self.report.write(text + "\n")
        self.report.flush()

    def step(self, name):
        self.phase = name
        self.result["phase"] = name
        self.log("PHASE: " + name)

    def cli(self, *args):
        if args[0] == "add" or "--library" in args:
            self.guard()
        base.run([str(self.bundle / "bin/ilibrary"), *map(str, args)])

    def guard(self):
        base.require_test_user()
        base.check_account()
        require(base.media_directory(self.home) == self.media, "選択中のメディアフォルダが変わりました。")

    def capture(self, label, paths, ids=None):
        self.guard()
        rows = base.snapshot()
        write_json(self.work / (label + ".json"), rows)
        inventory(rows, paths, ids)
        return rows

    def observe(self, label):
        self.step(label)
        base.music('tell application "Music" to activate')
        expected = self.spec["display"]
        text = " → ".join(f"{n:02d}" for n in expected)
        print("Musicの「最近追加した項目」を開き、先頭から左→右、上→下に、最後まで確認してください。")
        print("期待するAlbum番号: " + text)
        print("1: 全アルバムがこの順（抜け・重複・分裂なし） / 2: 違う / 3: 判断できない")
        answer = input("確認した結果の番号を入力: ").strip()
        observed = input("実際のAlbum番号を空白区切りで入力。番号で表せない場合は UNKNOWN: ") if answer == "2" else ""
        observation = display_answer(expected, answer, observed)
        observation.update({"checkpoint": label, "time": now()})
        self.result["observations"].append(observation)
        write_json(self.work / (label + "-observation.json"), observation)
        self.log(observation["status"] + ": observed Recently Added order; " + label)
        self.log("expected album numbers: " + ",".join(map(str, expected)))
        self.log("observed album numbers: " + (",".join(map(str, observation["observed"])) if observation["observed"] else "UNKNOWN"))
        self.log("observation time: " + observation["time"])

    def finish_checks(self, paths, states, final, staging, journal_source, backup_check):
        # The known completed journal must authorize no new file or registration.
        journal = staging / ".ilibrary-add.json"
        journal_hash = journal_check(journal, self.spec, journal_source, paths, final)
        dates = date_diagnostics(final)
        self.result["dates"] = dates
        self.log(f'MEASURED: distinct addition timestamps: {dates["unique"]}; span seconds: {dates["span_seconds"]}')
        self.log(f'MEASURED: seconds shared by multiple albums: {dates["cross_album_ties"]}')
        for album, span in dates["album_spans"].items():
            self.log(f"MEASURED: {album}; timestamp span seconds: {span}")
        self.log("Addition-timestamp equality: diagnostic only; not a completion gate")
        self.observe("display-before-relaunch")
        self.step("relaunch")
        require(stable(self.capture("before-quit", paths)) == stable(final), "表示確認中に登録が変わりました。")
        base.music('tell application "Music" to quit')
        base.wait_until_closed()
        self.guard()
        # A read restarts Music only after the correct media folder is rechecked.
        require(stable(self.capture("after-relaunch", paths)) == stable(final), "再起動で登録が変わりました。")
        self.observe("display-after-relaunch")
        self.step("repeat-and-preservation")
        require(stable(self.capture("before-repeat", paths)) == stable(final), "登録が変わりました。")
        journal_check(journal, self.spec, journal_source, paths, final)
        self.cli("add", staging, "--order", self.spec["mode"], "--dry-run")
        self.cli("add", staging, "--order", self.spec["mode"])
        require(stable(self.capture("after-repeat", paths)) == stable(final), "再実行で登録が変わりました。")
        require(digest(journal) == journal_hash, "完了済み追加記録が変わりました。")
        base.compare_files(paths, states)
        backup_check()
        self.log("PASS: repeated completed addition preserves IDs, dates, files, and journal")
        self.log("PASS: original synthetic backup verified at the final checkpoint")
        statuses = [o["status"] for o in self.result["observations"]]
        self.result["state"] = "PASS" if statuses == ["PASS", "PASS"] else ("FAIL" if "FAIL" in statuses else "UNVERIFIED")
        self.step("complete")


def reuse_small(m):
    m.step("legacy-evidence")
    old = safe_path(m.home / "ilibrary-m10-v2")
    require(digest(old / "manifest.json") == LEGACY_MANIFEST, "保存済みv2の識別情報が一致しません。旧状態は変更しません。")
    legacy = base.verify_bundle(old)
    require(legacy["commit"] == LEGACY_COMMIT, "以前のsmallとコミットが違います。")
    work = safe_path(old / "reference-private/small")
    require(digest(work / "ilibrary-m10-results.txt") == LEGACY_REPORT, "以前のsmallの報告が一致しません。")
    final = json.loads(safe_path(work / "final-registration.json").read_text())
    paths = {r: m.media / "Music" / r for r in relatives(m.spec)}
    inventory(final, paths)
    m.log("Prior small source commit: " + LEGACY_COMMIT)
    m.log("Prior evidence: evacuation, removal, empty GUI, quit, editing, and readdition passed")
    m.log("Supplement: later observations only; no repeated evacuation or registration removal")
    current = m.capture("reuse-current", paths)
    require(stable(current) == stable(final), "保存済みsmallと現在の登録が違います。作り直さず停止します。")
    states = base.file_state(paths)
    write_json(m.work / "current-files-before-observation.json", states)
    m.cli("check", m.media / "Music" / ARTIST, "--library")
    # Reconstruct expected edited bytes from a restored copy, without touching
    # the existing library files or the previous experiment's records.
    m.step("legacy-backup-restoration")
    image = safe_path(work / "synthetic-backup.dmg")
    image_hash = digest(image)
    require(not os.path.ismount(work / "backup-mount"), "以前のバックアップがまだ接続されています。")
    original = json.loads(safe_path(work / "original-files.json").read_text())
    require(set(original) == {str(Path(r).relative_to(ARTIST)) for r in paths}, "以前のファイル一覧が違います。")
    mount = m.work / "legacy-backup-mount"
    mount.mkdir()
    restored = m.work / "restored-originals"
    base.run(["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(image)])
    try:
        base.run(["/usr/bin/ditto", str(mount), str(restored)])
        base.compare_files({r: restored / r for r in original}, original)
    finally:
        base.run(["/usr/bin/hdiutil", "detach", str(mount)])
    require(not os.path.ismount(mount) and digest(image) == image_hash, "バックアップの検証後状態が違います。")
    expected = m.work / "expected-edited"
    base.run(["/usr/bin/ditto", str(restored), str(expected)])
    m.cli("apply", old / "small/edited-catalog.json", expected, "--timestamps", "--dry-run")
    m.cli("apply", old / "small/edited-catalog.json", expected, "--timestamps")
    expected_states = base.file_state({r: expected / Path(r).relative_to(ARTIST) for r in paths})
    base.compare_files(paths, expected_states)
    m.log("PASS: current files equal reconstructed edited copies; original backup restored and verified")
    staging = safe_path(work / "evacuated")
    # Version 2 used album/file relative paths; its journal still contains full paths.
    # Keep the original completed journal in place. No pending entry or source
    # audio is accepted, so the product has no addition or move to perform.
    journal_source = {r: staging / Path(r).relative_to(ARTIST) for r in paths}
    m.finish_checks(paths, states, current, staging, journal_source,
                    lambda: verify_old_backup(image, image_hash, mount, restored, original))


def verify_old_backup(image, checksum, mount, restored, states):
    require(digest(image) == checksum and not os.path.ismount(mount), "元のバックアップが変わりました。")
    base.compare_files({r: restored / r for r in states}, states)


def fresh_case(m):
    spec = m.spec
    m.step("initial-addition")
    require(not base.snapshot(), "ライブラリが空ではありません。既存の登録は削除しません。")
    require(not list(m.media.rglob("*.m4a")), "新しいメディアフォルダに音声があります。変更しません。")
    seed = m.work / "seed"
    shutil.copytree(m.bundle / m.name / "files", seed)
    m.cli("apply", m.bundle / m.name / "catalog.json", seed, "--timestamps")
    m.cli("add", seed, "--order", spec["mode"], "--dry-run")
    m.cli("add", seed, "--order", spec["mode"])
    originals = {r: m.media / "Music" / r for r in relatives(spec)}
    records = m.capture("initial-registration", originals)
    journal_check(seed / ".ilibrary-add.json", spec, seed, originals, records)
    m.log("PASS: only freshly generated tracks registered in the planned addition order")
    m.step("backup")
    image, image_hash, states = base.make_backup(m.work, originals)
    write_json(m.work / "original-files.json", states)
    write_json(m.work / "backup-verification.json", {"sha256": image_hash, "time": now()})
    m.log("PASS: synthetic backup restored, verified, and detached (same physical storage)")
    m.step("evacuation")
    m.guard()
    require(stable(m.capture("before-evacuation", originals)) == stable(records), "退避前に登録が変わりました。")
    retreat = m.work / "evacuated"
    paths = {r: retreat / r for r in originals}
    require(m.work.stat().st_dev == m.media.stat().st_dev, "この検証の退避は同じボリュームだけに限定します。")
    for relative, source in originals.items():
        dest = safe_path(paths[relative])
        require(not dest.exists(), "退避先が既にあります。")
        dest.parent.mkdir(parents=True, exist_ok=True)
        source.rename(dest)
    base.compare_files(paths, states)
    m.log("PASS: evacuation retains every byte and file date")
    m.step("registration-removal")
    remove_seeded(records, paths, originals, states, image, image_hash, m.work / "backup-mount", m.guard)
    m.log("PASS: only this run's inventoried registrations removed; evacuated files unchanged")
    m.step("empty-gui")
    base.music('tell application "Music" to activate')
    print("Musicの「曲」と「最近追加した項目」が両方空か確認してください。")
    require(input("1: 両方空 / 2: 空ではない・判断できない。番号を入力: ").strip() == "1",
            "空の画面を確認できません。終了・編集せず停止します。")
    m.guard()
    require(not base.snapshot(), "空の確認中に登録が変わりました。")
    m.log("PASS: empty GUI confirmed by maintainer; automatic GUI detection remains unverified")
    m.step("quit-and-edit")
    base.music('tell application "Music" to quit')
    base.wait_until_closed()
    require(not base.music_running(), "Musicが起動しています。編集しません。")
    m.cli("apply", m.bundle / m.name / "edited-catalog.json", retreat, "--timestamps", "--dry-run")
    m.cli("apply", m.bundle / m.name / "edited-catalog.json", retreat, "--timestamps")
    m.cli("check", retreat)
    require(not base.music_running(), "編集中にMusicが起動しました。")
    edited = base.file_state(paths)
    write_json(m.work / "edited-files.json", edited)
    m.log("PASS: Music terminated after empty GUI; catalog edited while Music remained closed")
    m.step("readdition")
    m.guard()
    require(not base.snapshot(), "再起動後のライブラリに登録があります。追加しません。")
    m.cli("add", retreat, "--order", spec["mode"], "--dry-run")
    m.cli("add", retreat, "--order", spec["mode"])
    final = m.capture("final-registration", originals)
    base.compare_files(originals, edited)
    m.cli("check", m.media / "Music", "--library")
    m.log("PASS: one registration per file; edited bytes, file dates, and library metadata verified")
    m.finish_checks(originals, edited, final, retreat, retreat,
                    lambda: require(digest(image) == image_hash and not os.path.ismount(m.work / "backup-mount"),
                                    "保存用コピーが変わりました。"))


def check_progress(bundle, name, commit):
    for prior in CASE_NAMES[:CASE_NAMES.index(name)]:
        path = safe_path(bundle / "reference-private" / prior / "result.json")
        require(path.is_file(), "先のケースの結果がありません。手順の順番を確認し、報告してください。")
        result = json.loads(path.read_text())
        require(result.get("case") == prior and result.get("commit") == commit and
                result.get("phase") == "complete" and result.get("state") in ("PASS", "FAIL", "UNVERIFIED"),
                "先のケースが途中で停止しています。次を始めず、一つの報告を作ってください。")


def execute(bundle, name, dry_run=False):
    require(sys.platform == "darwin", "この測定はmacOS専用です。")
    base.require_test_user()
    home = safe_path(base.pwd.getpwuid(os.getuid()).pw_dir)
    bundle = safe_path(bundle)
    require(bundle.is_relative_to(home) and not bundle.is_relative_to(home / "Music"),
            "一式は検証用ユーザーのホーム内、Musicフォルダ外に置いてください。")
    manifest = verify_bundle(bundle)
    spec = case_spec(name)
    print("予定: " + ("保存済みsmallを照合し、表示・再起動・完了済み追加・バックアップを確認します。退避や登録削除は行いません。"
                    if name == "small-existing" else "新しい空の合成ライブラリで、退避・登録削除・終了・編集・再追加と表示順を測定します。"))
    print("追加順: " + ",".join(map(str, spec["addition"])))
    print("期待する表示順: " + ",".join(map(str, spec["display"])))
    print("元の検証一式・音声・記録は保持します。個人のライブラリは対象外です。")
    if dry_run:
        print("Dry run: ファイルもMusicも変更していません。選択ライブラリはまだ調べていません。")
        return 0
    check_progress(bundle, name, manifest["commit"])
    m = Measurement(bundle, name, manifest, home)
    base._diagnostic_work = m.work
    try:
        m.log("iLibrary M10 display-order validation")
        m.log("source commit: " + manifest["commit"])
        m.log("case: " + name)
        m.log(f'albums: {len(spec["albums"])}; tracks: {len(relatives(spec))}')
        m.log("planned addition album numbers: " + ",".join(map(str, spec["addition"])))
        m.log("planned display album numbers: " + ",".join(map(str, spec["display"])))
        m.log("started: " + m.result["started"])
        m.log("macOS: " + base.run(["/usr/bin/sw_vers", "-productVersion"]))
        base.check_account()
        require(input("検証用ユーザー・Apple Account未設定・同期なし・手順のライブラリ選択済みを確認し、TESTと入力: ").strip() == "TEST",
                "開始を取り消しました。")
        m.media = selected_media(home, spec)
        m.log("PASS: selected media folder matches the planned library; name: " + m.media.name)
        require(base.music_running(), "手順どおりのライブラリをMusicで開いてから実行してください。")
        require(shutil.disk_usage(m.media).free > 256 * 1024 * 1024 and shutil.disk_usage(bundle).free > 256 * 1024 * 1024,
                "合成測定用の空き容量が不足しています。")
        m.log("Music version: " + base.music('tell application "Music" to return version'))
        write_json(m.work / "plan.json", {"spec": spec, "media": str(m.media), "time": now()})
        if name == "small-existing":
            reuse_small(m)
        else:
            fresh_case(m)
    except (base.Refusal, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired, EOFError, KeyboardInterrupt) as error:
        m.result["state"] = "STOP"
        m.log("STOP: measurement incomplete; preserve all state; do not rerun")
        m.log("stopped phase: " + m.phase)
        m.log("reason: " + (str(error) if isinstance(error, base.Refusal) else type(error).__name__))
        (m.work / "failure.txt").write_text(type(error).__name__ + ": " + str(error) + "\n")
    finally:
        m.result["finished"] = now()
        m.result["elapsed_seconds"] = round(time.monotonic() - m.started, 3)
        m.log("elapsed seconds: " + str(m.result["elapsed_seconds"]))
        m.log("case result: " + m.result["state"])
        write_json(m.work / "result.json", m.result)
        m.report.close()
        base._diagnostic_work = None
    # A completed negative observation is reportable and may be followed by an
    # independent fresh case. A STOP must not be bypassed.
    return 1 if m.result["state"] == "STOP" else 0


def combined_report(bundle):
    bundle = safe_path(bundle)
    manifest = verify_bundle(bundle)
    print("iLibrary M10 display-order combined report")
    print("source commit: " + manifest["commit"])
    states, dates = [], []
    for name in CASE_NAMES:
        print("\n== " + name)
        result = safe_path(bundle / "reference-private" / name / "result.json")
        text = safe_path(result.with_name("result.txt"))
        if text.is_file():
            print(text.read_text(), end="")
        if not result.is_file():
            print("NOT RUN" if not text.exists() else "STOP: result record incomplete")
            states.append("NOT RUN")
            continue
        data = json.loads(result.read_text())
        states.append(data["state"])
        if "dates" in data:
            dates.append(data["dates"])
    ties = any(d["cross_album_ties"] > 0 for d in dates)
    different = any(d["unique"] > 1 for d in dates)
    print("\n== Aggregate")
    print("Cross-album timestamp ties observed: " + ("YES" if ties else "UNVERIFIED"))
    print("Different addition timestamps observed: " + ("YES" if different else "UNVERIFIED"))
    print("Synthetic display qualification: " + ("PASS" if states == ["PASS"] * len(CASE_NAMES) and ties and different else "NOT COMPLETE"))
    print("Automatic GUI emptiness detection: NOT QUALIFIED; human observations only")
    print("Independent physical backup: NOT QUALIFIED; synthetic storage simulation only")
    print("No product rebuild or personal-library operation is authorized by this result.")


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
    live.add_argument("--case", choices=CASE_NAMES, required=True)
    live.add_argument("--dry-run", action="store_true")
    live.add_argument("--bundle", type=Path, default=Path(__file__).resolve().parent)
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
    except (base.Refusal, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        print("STOP: " + (str(error) if isinstance(error, base.Refusal) else "準備または入力の条件を確認できません。"))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
