#!/usr/bin/env python3
"""Guarded M10 qualification of separated album addition (Decision 36); not a product command.

Each case uses a new empty synthetic library and runs the complete sequence:
seed addition, backup, evacuation, guarded removal of this run's registrations,
human empty-GUI confirmation, termination, editing while closed, separated
readdition, display observation before and after relaunch, and repeat safety.
Preparation and reporting never address Music.
"""

import argparse
import collections
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

sys.dont_write_bytecode = True
import timing_probe as timing
import qualification_snapshot as bulk

display = timing.display
base = display.base
require, safe_path, digest, write_json = base.require, base.safe_path, base.digest, base.write_json
FORMAT = "ilibrary-m10-qualification-2"
CASE_NAMES = ("scale-release", "artist", "artist-desc", "artist-release")
WAIT_SECONDS = 2.0
# Bounds the confirmation checks around each wait; 300 registrations take longer to read than 6.
WAIT_LIMIT = 120.0
GATE_FIELDS = ("id", "title", "album", "artist", "path", "path_error", "added")
FIRST_SOURCE = "bf84ee9"
FIRST_REPORT = "deb58894e0f00c6351c084e90fac8a4375019a714dd1ef2bc2da41d3684d421f"
DISPLAY_SOURCE = "f6511d56250504d82f1c55c1039905838615ebbc"
DISPLAY_REPORT = "6b859c028563f78efd741344ace1ebf23c67f70b0748ef11f029f68113795cfe"
TIMING_SOURCE = "4cd7c6b30065df1aef9c94b80bf5ab1bb2ef8f10"
TIMING_REPORT = "f7b026250623471c10d8e014565543b3b5ff25bda7076c0c26715f44ad0430ca"
SCRIPTS = ("qualification_probe.py", "qualification_snapshot.py", "timing_probe.py", "display_probe.py", "rebuild_probe.py")


def case_spec(name):
    require(name in CASE_NAMES, "検証ケースが不正です。")
    result = display.case_spec(name)
    result["library"] = "M10-separated-v2-" + name
    return result


def expected_files():
    expected = {"bin/ilibrary", "PROCEDURE.md", *SCRIPTS}
    for name in CASE_NAMES:
        expected.update(f"{name}/files/{r}" for r in display.relatives(case_spec(name)))
        expected.update((f"{name}/catalog.json", f"{name}/edited-catalog.json"))
    return expected


def verify_bundle(bundle):
    bundle = safe_path(bundle)
    manifest = json.loads(safe_path(bundle / "manifest.json").read_text())
    require(manifest.get("format") == FORMAT and re.fullmatch(r"[0-9a-f]{40}", manifest.get("commit", "")),
            "分離追加検証一式の形式が違います。")
    require(manifest.get("cases") == {name: case_spec(name) for name in CASE_NAMES} and
            manifest.get("wait_seconds") == WAIT_SECONDS and manifest.get("wait_limit") == WAIT_LIMIT,
            "検証計画が変わっています。")
    require(set(manifest.get("files", {})) == expected_files(), "必要な入力の一覧が違います。")
    base.verify_bundle_files(bundle, expected_files() | {"manifest.json"})
    for relative, checksum in manifest["files"].items():
        require(digest(safe_path(bundle / relative)) == checksum, "検証一式の内容が変わっています。")
    return manifest


def prepare(output, binary, tagger, audio, commit, dry_run=False):
    output = safe_path(output)
    require(not output.exists(), "準備先が既にあります。上書きしません。")
    require(re.fullmatch(r"[0-9a-f]{40}", commit), "コミット情報が不正です。")
    count = sum(len(display.relatives(case_spec(name))) for name in CASE_NAMES)
    print(f"予定: 新しい分離追加検証一式と合成音声{count}曲を作成します。旧一式とMusicは操作しません。")
    if dry_run:
        return
    output.mkdir(parents=True)
    (output / "bin").mkdir()
    shutil.copy2(binary, output / "bin/ilibrary")
    for name in SCRIPTS:
        shutil.copy2(Path(__file__).with_name(name), output / name)
    shutil.copy2(Path(__file__).resolve().parents[2] / "docs/rebuild-qualification-v2-validation.md",
                      output / "PROCEDURE.md")
    for name in CASE_NAMES:
        spec = case_spec(name)
        directory = output / name
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
            write_json(directory / file, display.catalog(spec, edited))
            base.run([str(output / "bin/ilibrary"), "validate", str(directory / file), str(directory / "files")])
    manifest = {"format": FORMAT, "commit": commit, "cases": {name: case_spec(name) for name in CASE_NAMES},
                "wait_seconds": WAIT_SECONDS, "wait_limit": WAIT_LIMIT,
                "files": {r: digest(output / r) for r in sorted(expected_files())}}
    write_json(output / "manifest.json", manifest)
    verify_bundle(output)
    print(f"PASS: 合成音声{count}曲、4ケースのカタログ、検証一式の照合。Music未操作。")


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


class Measurement(timing.Measurement):
    def __init__(self, bundle, name, manifest, home):
        self.bundle, self.name, self.manifest, self.home = bundle, name, manifest, home
        self.spec = case_spec(name)
        self.work = safe_path(bundle / "reference-private" / name)
        require(not self.work.exists(), "このケースの記録が既にあります。再実行せず最後の報告手順へ進んでください。")
        self.work.mkdir(parents=True, mode=0o700)
        self.phase = "preflight"
        self.report = (self.work / "result.txt").open("x")
        self.result = {"case": name, "state": "STOP", "phase": self.phase, "observations": [],
                       "boundaries": [], "commit": manifest["commit"], "started": display.now()}
        self.started, self.media = time.monotonic(), None
        self.result["phase_seconds"] = {}
        self.phase_clock, self.use_bulk = time.monotonic(), False

    def snapshot(self):
        # The per-track snapshot is used only until the equivalence gate has passed.
        return bulk.snapshot() if self.use_bulk else base.snapshot()

    def capture(self, label, paths, ids=None):
        self.guard()
        rows = self.snapshot()
        write_json(self.work / (label + ".json"), rows)
        display.inventory(rows, paths, ids)
        return rows

    def unchanged(self, rows, paths):
        self.guard()
        require(base.music_running(), "Musicが終了しています。次の追加は行いません。")
        current = self.snapshot()
        display.inventory(current, paths)
        require(display.stable(current) == display.stable(rows), "確認済みの登録が変わりました。")

    def step(self, name):
        self.close_phase()
        super().step(name)
        self.phase_clock = time.monotonic()

    def close_phase(self):
        if self.phase_clock is not None:
            seconds = round(time.monotonic() - self.phase_clock, 3)
            self.result["phase_seconds"][self.phase] = seconds
            self.phase_clock = None
            self.log(f"DURATION: phase {self.phase}; seconds: {seconds}")

    def equivalence_gate(self, paths):
        """Require the bulk snapshot to equal the per-track snapshot before any file is moved."""
        self.guard()
        start = time.monotonic()
        per_track = base.snapshot()
        middle = time.monotonic()
        bulk_rows = bulk.snapshot()
        end = time.monotonic()
        write_json(self.work / "seed-registration.json", per_track)
        self.log(f"MEASURED: per-track snapshot of {len(per_track)} registrations: {middle - start:.3f} seconds")
        self.log(f"MEASURED: bulk snapshot of {len(bulk_rows)} registrations: {end - middle:.3f} seconds")
        legacy_errors = sum(bool(r.get("legacy_error")) for r in per_track)
        self.log(f"MEASURED: per-track rows with a legacy location read error (diagnostic only, not compared): "
                 f"{legacy_errors} of {len(per_track)}")
        compared = lambda rows: sorted(({k: r[k] for k in GATE_FIELDS} for r in rows), key=lambda r: r["id"])
        if compared(per_track) != compared(bulk_rows):
            write_json(self.work / "seed-registration-bulk.json", bulk_rows)
            self.log("STOP: bulk snapshot differs from the per-track snapshot; both are saved; nothing was evacuated")
            raise base.Refusal("一括取得と1曲ずつの取得が一致しません。退避せず停止します。")
        display.inventory(per_track, paths)
        self.log("PASS: bulk snapshot equals the per-track snapshot (fields compared: id, title, album, artist, path, path_error, added; order-insensitive)")
        self.use_bulk = True
        return per_track

    def remove_registrations(self, records, paths, originals, states, image, image_hash, mount):
        """Delete this run's registrations one persistent ID per call; see display_probe.remove_seeded."""
        display.inventory(records, originals)
        by_identity = {(Path(r).parts[-3], Path(r).parts[-2], Path(r).stem[3:]): r for r in paths}
        total, completed, pending = len(records), 0, None
        left = collections.Counter((r["artist"], r["album"]) for r in records)
        albums_done, albums_total = 0, len(left)
        journal = bulk.Journal(self.work / "removal-journal.jsonl")
        started = time.monotonic()
        try:
            journal.write(event="begin", ids=[r["id"] for r in records], count=total,
                          image_sha256=image_hash, commit=self.manifest["commit"])
            remaining = list(records)
            for row in records:
                self.guard()
                if completed == 0:
                    base.compare_files(paths, states)
                selected = {by_identity[(t["artist"], t["album"], t["title"])]:
                            paths[by_identity[(t["artist"], t["album"], t["title"])]] for t in remaining}
                display.inventory(self.snapshot(), selected, [r["id"] for r in remaining], originals)
                require(digest(image) == image_hash and not os.path.ismount(mount), "保存用コピーが変化しました。")
                if pending:
                    # Only the inventory and image checks above prove that the previous deletion removed exactly that registration.
                    journal.write(event="verified", seq=pending[0], id=pending[1])
                    pending = None
                journal.write(event="intent", seq=completed + 1, id=row["id"])
                base.music(base.DELETE, row["id"], row["title"], row["album"], row["artist"])
                remaining = [r for r in remaining if r["id"] != row["id"]]
                base.compare_files(paths, states)
                completed += 1
                pending = (completed, row["id"])
                journal.write(event="returned", seq=completed, id=row["id"])
                elapsed = time.monotonic() - started
                self.log(f"PROGRESS: returned removals {completed}/{total}; remaining {total - completed}; "
                         f"phase elapsed seconds: {elapsed:.1f}; mean seconds per removal: {elapsed / completed:.2f}")
                key = (row["artist"], row["album"])
                left[key] -= 1
                if left[key] == 0:
                    albums_done += 1
                    self.log(f"CHECKPOINT: album {row['album']} fully removed; albums {albums_done}/{albums_total}; "
                             f"registrations removed {completed}/{total}")
            require(not self.snapshot(), "全登録が空になっていません。")
            if pending:
                journal.write(event="verified", seq=pending[0], id=pending[1])
                pending = None
        except BaseException as error:
            journal.write(event="interrupted" if isinstance(error, KeyboardInterrupt) else "stop",
                          returned=completed, verified=completed - (1 if pending else 0),
                          returned_unverified=1 if pending else 0, reason=type(error).__name__)
            raise
        else:
            journal.write(event="end", returned=completed, verified=completed)
        finally:
            journal.close()

    def journal_summary(self):
        verified, unverified, indeterminate, _ = bulk.read(self.work / "removal-journal.jsonl")
        self.result.update(confirmed_removals=verified, returned_unverified_removals=unverified,
                           indeterminate_removal=indeterminate)
        self.log(f"removals verified by a later snapshot: {verified}")
        self.log(f"removals returned without verification: {unverified}")
        self.log("indeterminate removal (intent without returned record): " + ("yes" if indeterminate else "no"))

    def media_check(self):
        entries = timing.media_inventory(self.media)
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

    def measure(self):
        spec, inputs = self.spec, self.bundle / self.name
        self.step("empty-library")
        require(not self.capture("initial-registration", {}), "新しい空のライブラリではありません。既存の登録は削除しません。")
        self.media_check()

        self.step("seed-addition")
        seed = self.work / "seed"
        base.run(["/usr/bin/ditto", str(inputs / "files"), str(seed)])
        self.cli("apply", inputs / "catalog.json", seed, "--timestamps", "--dry-run")
        self.cli("apply", inputs / "catalog.json", seed, "--timestamps")
        self.cli("add", seed, "--order", spec["mode"], "--dry-run")
        self.cli("add", seed, "--order", spec["mode"])
        originals = {r: self.media / "Music" / r for r in display.relatives(spec)}
        records = self.equivalence_gate(originals)
        display.journal_check(seed / ".ilibrary-add.json", spec, seed, originals, records)
        self.log("PASS: only freshly generated tracks registered; product addition order matches the saved plan")

        self.step("backup")
        image, image_hash, states = base.make_backup(self.work, originals)
        write_json(self.work / "original-files.json", states)
        def backup_check():
            require(digest(image) == image_hash and not os.path.ismount(self.work / "backup-mount"),
                    "保存用コピーの内容か切り離し状態が変わりました。")
            base.compare_files({r: self.work / "restored-backup" / r for r in originals}, states)
        backup_check()
        self.log("PASS: synthetic original backup restored, verified, and detached; same physical storage")

        self.step("evacuation")
        require(display.stable(self.capture("before-evacuation", originals)) == display.stable(records),
                "退避前に登録が変わりました。")
        retreat = self.work / "evacuated"
        paths = {r: retreat / r for r in originals}
        require(self.work.stat().st_dev == self.media.stat().st_dev, "この検証の退避は同じボリュームだけに限定します。")
        for relative, source in originals.items():
            dest = safe_path(paths[relative])
            require(not dest.exists(), "退避先が既にあります。")
            dest.parent.mkdir(parents=True, exist_ok=True)
            source.rename(dest)
        base.compare_files(paths, states)
        self.log("PASS: evacuation retains every byte and file date")

        self.step("registration-removal")
        self.remove_registrations(records, paths, originals, states, image, image_hash, self.work / "backup-mount")
        backup_check()
        self.log(f"PASS: removed only this run's {len(records)} inventoried registrations, one persistent ID per call; "
                 "evacuated files unchanged")

        self.step("empty-gui")
        base.music('tell application "Music" to activate')
        print("Musicの「曲」と「最近追加した項目」が両方空か確認してください。")
        require(input("1: 両方空 / 2: 空ではない・判断できない。番号を入力: ").strip() == "1",
                "空の画面を確認できません。終了・編集せず停止します。")
        self.guard()
        require(not self.snapshot(), "空の確認中に登録が変わりました。")
        self.log("PASS: empty GUI confirmed by maintainer; automatic GUI detection remains unverified")

        self.step("quit-and-edit")
        base.music('tell application "Music" to quit')
        base.wait_until_closed()
        require(not base.music_running(), "Musicが起動しています。編集しません。")
        self.cli("apply", inputs / "edited-catalog.json", retreat, "--timestamps", "--dry-run")
        self.cli("apply", inputs / "edited-catalog.json", retreat, "--timestamps")
        self.cli("check", retreat)
        require(not base.music_running(), "編集中にMusicが起動しました。")
        edited = base.file_state(paths)
        write_json(self.work / "edited-files.json", edited)
        self.log("PASS: Music terminated after the empty GUI; working files edited while Music remained closed")

        self.step("separated-readdition")
        self.guard()
        require(not self.capture("before-readdition", {}), "再起動後のライブラリに登録があります。追加しません。")
        albums = {a["number"]: a for a in spec["albums"]}
        final, destinations, journals = [], {}, []
        for number in spec["addition"]:
            album = albums[number]
            album_spec = dict(spec, albums=[album], addition=[number], display=[number])
            selected = display.relatives(album_spec)
            source = retreat / album["artist"] / album["album"]
            current_files = lambda: {r: destinations.get(r, p) for r, p in paths.items()}
            self.unchanged(final, destinations)
            backup_check()
            base.compare_files(current_files(), edited)
            waited = wait_between(lambda: self.unchanged(final, destinations)) if final else 0
            self.log(f"WAIT: before album {number:02d}; observed monotonic seconds: {waited:.3f}")
            # One invocation contains exactly one album; the published executable is unchanged.
            self.cli("add", source, "--order", spec["mode"], "--dry-run")
            self.unchanged(final, destinations)
            base.compare_files(current_files(), edited)
            self.cli("add", source, "--order", spec["mode"])
            destinations.update({r: originals[r] for r in selected})
            current = self.capture(f"after-album-{number:02d}", destinations)
            prior_ids = {r["id"] for r in final}
            require(display.stable([r for r in current if r["id"] in prior_ids]) == display.stable(final),
                    "前のアルバムの登録が変わりました。")
            added = [r for r in current if r["id"] not in prior_ids]
            display.inventory(added, {r: destinations[r] for r in selected})
            boundary = timing.timing_boundary(final, added)
            boundary.update(album=number, waited_seconds=round(waited, 3), observed_at=display.now())
            self.result["boundaries"].append(boundary)
            write_json(self.work / f"boundary-{number:02d}.json", boundary)
            self.log(f"MEASURED: album {number:02d}; minimum {boundary['current_min']}; maximum {boundary['current_max']}; "
                     f"gap from previous maximum: {boundary['gap_seconds']}; separated: {boundary['separated']}")
            require(boundary["separated"],
                    "追加日時が前のアルバムより後になっていません（対応範囲外の重なり）。追加済みの曲を残して停止します。")
            journal = source / ".ilibrary-add.json"
            journals.append((journal, display.journal_check(journal, album_spec, paths, destinations, added),
                             album_spec, added))
            base.compare_files(current_files(), edited)
            backup_check()
            final = current
        require(display.stable(self.capture("final-registration", originals)) == display.stable(final),
                "追加完了後に登録が変わりました。")
        base.compare_files(originals, edited)
        self.cli("check", self.media / "Music", "--library")
        dates = display.date_diagnostics(final)
        self.result["dates"] = dates
        require(dates["cross_album_ties"] == 0, "アルバム間で同じ追加日時の秒があります。対応範囲外として停止します。")
        self.log(f"PASS: all {len(spec['addition'])} album timestamp ranges strictly increase without overlap")
        self.log(f"MEASURED: distinct addition timestamps: {dates['unique']}; span seconds: {dates['span_seconds']}")
        self.log(f"MEASURED: seconds shared by multiple albums: {dates['cross_album_ties']}")
        for name, span in dates["album_spans"].items():
            self.log(f"MEASURED: {name}; timestamp span seconds: {span}")
        self.log("PASS: one registration per file; edited bytes, file dates, and library metadata verified")

        self.unchanged(final, originals)
        self.observe("display-before-relaunch")
        self.step("relaunch")
        self.unchanged(final, originals)
        base.music('tell application "Music" to quit')
        base.wait_until_closed()
        self.guard()
        require(display.stable(self.capture("after-relaunch", originals)) == display.stable(final),
                "再起動で登録が変わりました。")
        self.observe("display-after-relaunch")

        self.step("repeat-and-preservation")
        for journal, checksum, album_spec, added in journals:
            self.unchanged(final, originals)
            require(display.journal_check(journal, album_spec, paths, originals, added) == checksum,
                    "完了済みの追加記録が変わりました。")
            self.cli("add", journal.parent, "--order", spec["mode"], "--dry-run")
            self.cli("add", journal.parent, "--order", spec["mode"])
            self.unchanged(final, originals)
            require(digest(journal) == checksum, "再実行で追加記録が変わりました。")
        base.compare_files(originals, edited)
        backup_check()
        verify_bundle(self.bundle)
        self.log(f"PASS: repeated completed addition preserves IDs, dates, files, and all {len(journals)} journals")
        self.log("PASS: original synthetic backup and immutable bundle inputs verified at the final checkpoint")
        statuses = [o["status"] for o in self.result["observations"]]
        self.result["state"] = "PASS" if statuses == ["PASS", "PASS"] else ("FAIL" if "FAIL" in statuses else "UNVERIFIED")
        self.step("complete")


def check_progress(bundle, name, commit):
    for prior in CASE_NAMES[:CASE_NAMES.index(name)]:
        path = safe_path(bundle / "reference-private" / prior / "result.json")
        require(path.is_file(), "先のケースの結果がありません。手順の順番を確認し、報告してください。")
        result = json.loads(path.read_text())
        require(result.get("state") != "INTERRUPTED",
                "先のケースが中断されています（INTERRUPTED）。次を始めず、一つの報告を作ってください。")
        require(result.get("case") == prior and result.get("commit") == commit and
                result.get("phase") == "complete" and result.get("state") in ("PASS", "FAIL", "UNVERIFIED"),
                "先のケースが途中で停止しています。次を始めず、一つの報告を作ってください。")


def execute(bundle, name, dry_run=False):
    require(sys.platform == "darwin", "この測定はmacOS専用です。")
    base.require_test_user()
    home = safe_path(base.pwd.getpwuid(os.getuid()).pw_dir)
    bundle = safe_path(bundle)
    require(bundle.is_relative_to(home) and not bundle.is_relative_to(home / "Music"),
            "一式は検証用ユーザーのホーム内、Musicフォルダ外へ置いてください。")
    manifest = verify_bundle(bundle)
    spec = case_spec(name)
    print(f"予定: 新しい空の{spec['library']}だけで、合成曲の追加・保存用コピー・退避・この実行の登録だけの削除・"
          "空の確認・終了中の編集・アルバムごとの再追加・表示順2回・再実行を行います。")
    print("追加順: " + ",".join(map(str, spec["addition"])))
    print("期待する表示順: " + ",".join(map(str, spec["display"])))
    print("元の検証一式・旧一式・ライブラリ・記録は保持します。個人のライブラリは対象外です。")
    if dry_run:
        print("Dry run: Musicへのアクセスとファイル作成は行っていません。")
        return 0
    check_progress(bundle, name, manifest["commit"])
    m = Measurement(bundle, name, manifest, home)
    base._diagnostic_work = m.work
    try:
        m.log("iLibrary M10 separated-addition qualification")
        m.log("source commit: " + manifest["commit"])
        m.log("case: " + name)
        m.log(f'albums: {len(spec["albums"])}; tracks: {len(display.relatives(spec))}')
        m.log("planned addition album numbers: " + ",".join(map(str, spec["addition"])))
        m.log("planned display album numbers: " + ",".join(map(str, spec["display"])))
        m.log("started: " + m.result["started"])
        m.log("macOS: " + base.run(["/usr/bin/sw_vers", "-productVersion"]))
        base.check_account()
        require(input(f"検証用ユーザー・Apple Account未設定・同期なし・新しい空の{spec['library']}を確認し、TESTと入力: ").strip() == "TEST",
                "開始を取り消しました。")
        m.media = display.selected_media(home, spec)
        m.log("PASS: selected media folder matches the new library; name: " + m.media.name)
        require(base.music_running(), "手順の新しいライブラリをMusicで開いてください。")
        require(shutil.disk_usage(m.media).free > 256 * 1024 * 1024 and
                shutil.disk_usage(bundle).free > 256 * 1024 * 1024, "合成検証用の空き容量が不足しています。")
        m.log("Music version: " + base.music('tell application "Music" to return version'))
        write_json(m.work / "plan.json", {"spec": spec, "media": str(m.media), "wait_seconds": WAIT_SECONDS,
                                          "wait_limit": WAIT_LIMIT, "time": display.now()})
        m.measure()
    except KeyboardInterrupt as error:
        m.result["state"] = "INTERRUPTED"
        m.log("INTERRUPTED: measurement interrupted by the operator; preserve all state; do not rerun")
        m.log("interrupted phase: " + m.phase)
        m.journal_summary()
        (m.work / "failure.txt").write_text(type(error).__name__ + "\n")
    except (base.Refusal, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired, EOFError) as error:
        m.result["state"] = "STOP"
        m.log("STOP: measurement incomplete; preserve all state; do not rerun")
        m.log("stopped phase: " + m.phase)
        m.journal_summary()
        m.log("reason: " + (str(error) if isinstance(error, base.Refusal) else type(error).__name__))
        (m.work / "failure.txt").write_text(type(error).__name__ + ": " + str(error) + "\n")
    finally:
        m.close_phase()
        m.result["finished"] = display.now()
        m.result["elapsed_seconds"] = round(time.monotonic() - m.started, 3)
        m.log("elapsed seconds: " + str(m.result["elapsed_seconds"]))
        m.log("case result: " + m.result["state"])
        write_json(m.work / "result.json", m.result)
        m.report.close()
        base._diagnostic_work = None
    # A completed negative observation may be followed by an independent case. A STOP or INTERRUPTED case must not be bypassed.
    return 1 if m.result["state"] in ("STOP", "INTERRUPTED") else 0


def report(bundle, output, dry_run=False):
    bundle, output = safe_path(bundle), safe_path(output)
    manifest = verify_bundle(bundle)
    require(not output.exists() and output.parent.is_dir(), "報告先が既に存在するか、親フォルダがありません。上書きしません。")
    require(not output.is_relative_to(bundle), "共有報告は検証一式の外へ保存してください。")
    text = "iLibrary M10 separated-addition qualification report\nsource commit: " + manifest["commit"] + "\n\n"
    text += ("== Historical evidence; not rerun\n"
             "display-v3 small: source " + DISPLAY_SOURCE + "; report SHA-256 " + DISPLAY_REPORT +
             "\nObserved display before and after relaunch: 2,3,1; expected: 3,2,1; cross-album ties observed\n"
             "first qualification run: source " + FIRST_SOURCE + "; report SHA-256 " + FIRST_REPORT +
             "\nscale-release STOP in registration-removal with KeyboardInterrupt after 803.057 seconds; "
             "artist cases not run\n"
             "timing v2 small: source " + TIMING_SOURCE + "; report SHA-256 " + TIMING_REPORT +
             "\nSeparated additions; observed display before and after relaunch: 3,2,1; expected: 3,2,1; no removal\n")
    states, ties = [], 0
    for name in CASE_NAMES:
        text += "\n== " + name + "\n"
        result = safe_path(bundle / "reference-private" / name / "result.txt")
        saved = safe_path(result.with_name("result.json"))
        if not result.is_file():
            text += "NOT RUN: no saved measurement\n"
            states.append("NOT RUN")
            continue
        body = result.read_text()
        text += body
        if not saved.is_file():
            text += "STOP: final result record missing; measurement incomplete\n"
            states.append("STOP")
            continue
        data = json.loads(saved.read_text())
        require(data.get("case") == name and data.get("commit") == manifest["commit"] and
                data.get("state") in ("PASS", "FAIL", "UNVERIFIED", "STOP", "INTERRUPTED"), "保存した結果の識別情報が違います。")
        require(f"case result: {data['state']}\n" in body and
                (data["state"] in ("STOP", "INTERRUPTED") or data.get("phase") == "complete"), "結果の本文と終了記録が一致しません。")
        states.append(data["state"])
        ties += data.get("dates", {}).get("cross_album_ties", 0)
    text += "\n== Aggregate\n"
    text += "".join(f"{name}: {state}\n" for name, state in zip(CASE_NAMES, states))
    if "INTERRUPTED" in states:
        text += "Interrupted by the operator, not stopped by a refusal: " + ", ".join(
            n for n, s in zip(CASE_NAMES, states) if s == "INTERRUPTED") + "\n"
    text += "Cross-album timestamp ties in completed readditions: " + str(ties) + "\n"
    text += ("Separated-addition synthetic qualification: " +
             ("PASS" if states == ["PASS"] * len(CASE_NAMES) else "NOT COMPLETE") + "\n")
    text += ("\n== Scope\nA passing result is synthetic evidence for the M10 assessment; it does not by itself complete M10.\n"
             "No fixed waiting interval is qualified by this result.\n"
             "Automatic GUI emptiness detection: NOT QUALIFIED; human observations only.\n"
             "Independent physical backup: NOT QUALIFIED; synthetic storage simulation only.\n"
             "No product rebuild or personal-library operation is authorized by this result.\n")
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
    live.add_argument("--case", choices=CASE_NAMES, required=True)
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
            return execute(args.bundle, args.case, args.dry_run)
    except (base.Refusal, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        print("STOP: " + (str(error) if isinstance(error, base.Refusal) else "準備または入力の条件を確認できません。"))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
