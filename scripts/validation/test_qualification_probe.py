"""Separated-addition qualification runs with substituted native operations."""

import contextlib
import copy
import io
import json
from pathlib import Path
import shutil
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import qualification_probe as probe
from test_timing_probe import music_scaffolding

timing, display, base = probe.timing, probe.display, probe.base


class WaitTests(unittest.TestCase):
    def test_wait_uses_monotonic_time_and_checks_both_sides(self):
        clock, checks = [10.0], []
        elapsed = probe.wait_between(lambda: checks.append(clock[0]), lambda: clock[0],
                                     lambda amount: clock.__setitem__(0, clock[0] + amount))
        self.assertEqual(elapsed, 2.0)
        self.assertEqual(checks, [10.0, 12.0])

    def test_slow_state_check_refuses_next_addition(self):
        clock = [0.0]
        def slow():
            clock[0] += probe.WAIT_LIMIT / 2 + 1
        with self.assertRaises(base.Refusal):
            probe.wait_between(slow, lambda: clock[0], lambda _: None)

    def test_cases_reuse_the_display_plans_in_new_libraries(self):
        for name in probe.CASE_NAMES:
            spec = probe.case_spec(name)
            self.assertEqual(spec["library"], "M10-separated-" + name)
            self.assertEqual(spec["display"], list(reversed(spec["addition"])))
            self.assertEqual({k: v for k, v in spec.items() if k != "library"},
                             {k: v for k, v in display.case_spec(name).items() if k != "library"})
        self.assertEqual(len(display.relatives(probe.case_spec("scale-release"))), 300)
        with self.assertRaises(base.Refusal):
            probe.case_spec("small-existing")


class RunTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name).resolve()
        self.bundle = self.home / "ilibrary-m10-qualification"
        self.bundle.mkdir()
        for name in probe.expected_files():
            path = self.bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"synthetic original " + name.encode())
        self.manifest = {"format": probe.FORMAT, "commit": "a" * 40,
                         "cases": {n: probe.case_spec(n) for n in probe.CASE_NAMES},
                         "wait_seconds": probe.WAIT_SECONDS, "wait_limit": probe.WAIT_LIMIT,
                         "files": {n: probe.digest(self.bundle / n) for n in probe.expected_files()}}
        (self.bundle / "manifest.json").write_text(json.dumps(self.manifest))
        (self.bundle / ".DS_Store").write_bytes(b"retained Finder state")
        self.old = self.home / "ilibrary-m10-timing-v2/reference-private/timing-v2-small/result.txt"
        self.old.parent.mkdir(parents=True)
        self.old.write_bytes(b"retained historical passing result")
        self.addCleanup(setattr, base, "_diagnostic_work", None)
        self.reset("artist")

    def reset(self, name):
        self.name = name
        self.spec = probe.case_spec(name)
        self.media = self.home / "Music" / self.spec["library"] / "Media.localized"
        self.media.mkdir(parents=True, exist_ok=True)
        if not (self.media / ".localized").exists():
            music_scaffolding(self.media)
        self.rows, self.actions, self.running = [], [], True
        self.second, self.clock = 845559600, 0.0
        self.readded_dates = None
        self.identifier = getattr(self, "identifier", 0)

    def snapshot(self):
        self.running = True
        return copy.deepcopy(self.rows)

    def music(self, script, *args):
        if script == base.DELETE:
            self.assertTrue(self.running)
            matches = [r for r in self.rows if r["id"] == args[0]]
            self.assertEqual(len(matches), 1)
            self.assertEqual((matches[0]["title"], matches[0]["album"], matches[0]["artist"]), tuple(args[1:]))
            self.rows.remove(matches[0])
            self.actions.append("delete")
            return ""
        self.assertNotIn("delete", script)
        if "to quit" in script:
            self.actions.append("quit")
            self.running = False
        elif "return version" in script:
            return "test-version"
        else:
            self.running = True
        return ""

    def native(self, argv):
        if argv[0].endswith("ditto"):
            shutil.copytree(argv[1], argv[2])
        return "test OS" if argv[0].endswith("sw_vers") else ""

    def backup(self, work, paths):
        image = work / "synthetic-backup.dmg"
        image.write_bytes(b"simulated immutable backup")
        for relative, source in paths.items():
            target = work / "restored-backup" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        self.actions.append("backup")
        return image, probe.digest(image), base.file_state(paths)

    def add_album(self, root, album, sources, destinations, ids, readdition):
        self.second += 3
        for i, relative in enumerate(display.relatives({"albums": [album]})):
            source = root / relative if not readdition else root / Path(relative).name
            dest = self.media / "Music" / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            source.rename(dest)
            self.identifier += 1
            identifier = f"{self.identifier:016X}"
            added = str(self.second)
            if readdition and self.readded_dates:
                added = self.readded_dates(album["number"], i, self.second)
            self.rows.append(dict(id=identifier, artist=album["artist"], album=album["album"],
                                  title=dest.stem[3:], path=str(dest), added=added))
            sources.append(str(source)); destinations.append(str(dest)); ids.append(identifier)

    def cli(self, measurement, *args):
        command = args[0]
        if command == "check" or "--dry-run" in args:
            return
        if command == "apply":
            if "edited-catalog" in str(args[1]):
                self.assertFalse(self.running)
                self.actions.append("edit")
                for file in Path(args[2]).rglob("*.m4a"):
                    info = file.stat()
                    file.write_bytes(file.read_bytes() + b" edited")
                    base.os.utime(file, ns=(info.st_atime_ns, info.st_mtime_ns))
            return
        self.assertEqual(command, "add")
        self.assertTrue(self.running)
        self.assertEqual(args[3], self.spec["mode"])
        root = Path(args[1])
        journal = root / ".ilibrary-add.json"
        if journal.exists():
            self.actions.append("repeat")
            return
        albums = {a["number"]: a for a in self.spec["albums"]}
        readdition = any(root.glob("*.m4a"))
        numbers = [int(root.name[-2:])] if readdition else self.spec["addition"]
        entries = []
        for number in numbers:
            album = albums[number]
            sources, destinations, ids = [], [], []
            self.add_album(root, album, sources, destinations, ids, readdition)
            entries.append(dict(album=album["album"], albumArtist=album["artist"], sources=sources,
                                destinations=destinations, persistentIDs=ids, state="added"))
        self.actions.append(numbers[0] if readdition else "seed")
        journal.write_text(json.dumps({"format": "ilibrary-add-journal-1", "entries": entries}))

    def advance(self, amount):
        self.clock += amount

    def execute(self, answers=("TEST", "1", "1", "1"), override=None, dry_run=False, name=None):
        name = name or self.name
        output = io.StringIO()
        real_state = base.file_state
        real_wait = probe.wait_between
        def states(paths):
            return {r: dict(s, created=None) for r, s in real_state(paths).items()}
        with contextlib.ExitStack() as stack:
            for obj, attribute, value in [
                (probe.sys, "platform", "darwin"), (base, "require_test_user", lambda: None),
                (base.pwd, "getpwuid", lambda uid: SimpleNamespace(pw_dir=str(self.home))),
                (base, "check_account", lambda: None), (base, "media_directory", lambda home: self.media),
                (base, "music_running", lambda: self.running), (base, "snapshot", self.snapshot),
                (base, "music", self.music), (base, "run", self.native), (base, "make_backup", self.backup),
                (base, "file_state", states), (base, "wait_until_closed", lambda: None),
                (probe.Measurement, "cli", lambda m, *a: self.cli(m, *a)),
                (probe, "wait_between", lambda check: real_wait(check, lambda: self.clock, self.advance)),
            ]:
                stack.enter_context(patch.object(obj, attribute, value))
            if override:
                override(stack)
            stack.enter_context(patch("builtins.input", side_effect=answers))
            stack.enter_context(contextlib.redirect_stdout(output))
            try:
                code = probe.execute(self.bundle, name, dry_run)
            finally:
                self.output = output.getvalue()
        path = self.bundle / "reference-private" / name / "result.json"
        self.result = json.loads(path.read_text()) if path.exists() else None
        self.assertNotIn(str(self.home), self.output)
        self.assertEqual(self.old.read_bytes(), b"retained historical passing result")
        return code

    def complete_prior_cases(self, state="PASS"):
        for prior in probe.CASE_NAMES[:probe.CASE_NAMES.index(self.name)]:
            work = self.bundle / "reference-private" / prior
            work.mkdir(parents=True)
            (work / "result.txt").write_text(f"case result: {state}\n")
            (work / "result.json").write_text(json.dumps({"case": prior, "commit": "a" * 40, "state": state,
                                                          "phase": "complete" if state != "STOP" else "evacuation"}))

    def test_complete_artist_case_runs_the_full_sequence_with_separated_readdition(self):
        self.complete_prior_cases()
        before = {n: probe.digest(self.bundle / n) for n in probe.expected_files()}
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.result["state"], "PASS")
        self.assertEqual(self.result["phase"], "complete")
        sequence = [a for a in self.actions if a not in ("repeat",)]
        self.assertEqual(sequence[:2], ["seed", "backup"])
        self.assertEqual(sequence.count("delete"), 8)
        removal_end = len(sequence) - 1 - sequence[::-1].index("delete")
        self.assertEqual(sequence[removal_end + 1:removal_end + 3], ["quit", "edit"])
        self.assertEqual([a for a in sequence if isinstance(a, int)], [2, 4, 1, 3])
        self.assertEqual(self.actions.count("repeat"), 4)
        self.assertEqual(self.actions.count("quit"), 2)
        self.assertEqual([b["album"] for b in self.result["boundaries"]], [2, 4, 1, 3])
        self.assertEqual([b["waited_seconds"] for b in self.result["boundaries"]], [0, 2, 2, 2])
        self.assertTrue(all(b["separated"] for b in self.result["boundaries"]))
        self.assertEqual(self.result["dates"]["cross_album_ties"], 0)
        self.assertEqual(len(self.rows), 8)
        self.assertEqual(before, {n: probe.digest(self.bundle / n) for n in before})
        self.assertIn("expected album numbers: 3,1,4,2", self.output)
        self.assertIn("PASS: removed only this run's 8 inventoried registrations", self.output)

    def test_scale_case_separates_twenty_albums_and_removes_three_hundred_registrations(self):
        self.reset("scale-release")
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.result["state"], "PASS")
        self.assertEqual(self.actions.count("delete"), 300)
        self.assertEqual([b["album"] for b in self.result["boundaries"]], list(range(1, 21)))
        self.assertEqual(self.actions.count("repeat"), 20)
        self.assertEqual(len(self.rows), 300)
        self.assertIn("planned display album numbers: " + ",".join(map(str, range(20, 0, -1))), self.output)

    def test_cross_album_tie_stops_before_the_next_album_and_keeps_registrations(self):
        self.complete_prior_cases()
        # Album 4 shares the last exposed second of album 2.
        self.readded_dates = lambda number, index, second: str(second - 3) if number == 4 and index == 0 else str(second)
        self.assertEqual(self.execute(), 1)
        self.assertEqual(self.result["state"], "STOP")
        self.assertEqual(self.result["phase"], "separated-readdition")
        self.assertFalse(self.result["boundaries"][-1]["separated"])
        self.assertEqual([a for a in self.actions if isinstance(a, int)], [2, 4])
        self.assertEqual(len(self.rows), 4)
        self.assertEqual(self.actions.count("delete"), 8)
        self.assertIn("対応範囲外の重なり", self.output)
        self.assertTrue((self.bundle / "reference-private/artist/synthetic-backup.dmg").exists())

    def test_gui_mismatch_is_completed_as_failed(self):
        self.complete_prior_cases()
        self.assertEqual(self.execute(("TEST", "1", "2", "1 3 4 2", "2", "1 3 4 2")), 0)
        self.assertEqual(self.result["state"], "FAIL")
        self.assertEqual(self.actions.count("repeat"), 4)

    def test_unknown_gui_is_not_a_pass(self):
        self.complete_prior_cases()
        self.execute(("TEST", "1", "3", "3"))
        self.assertEqual(self.result["state"], "UNVERIFIED")

    def test_unconfirmed_empty_gui_stops_before_quit_edit_or_readdition(self):
        self.complete_prior_cases()
        self.assertEqual(self.execute(("TEST", "2")), 1)
        self.assertEqual(self.result["phase"], "empty-gui")
        self.assertNotIn("quit", self.actions)
        self.assertNotIn("edit", self.actions)
        self.assertEqual(self.rows, [])
        evacuated = list((self.bundle / "reference-private/artist/evacuated").rglob("*.m4a"))
        self.assertEqual(len(evacuated), 8)

    def test_unexpected_registration_during_removal_stops_without_further_deletion(self):
        self.complete_prior_cases()
        real = self.music
        def music(script, *args):
            result = real(script, *args)
            if script == base.DELETE and self.actions.count("delete") == 2:
                self.rows.append(dict(id="F" * 16, artist="Other", album="Other", title="Other",
                                      path="/elsewhere", added="845559600"))
            return result
        self.assertEqual(self.execute(override=lambda s: s.enter_context(patch.object(base, "music", music))), 1)
        self.assertEqual(self.result["phase"], "registration-removal")
        self.assertEqual(self.actions.count("delete"), 2)
        self.assertIn("F" * 16, [r["id"] for r in self.rows])

    def test_late_music_launch_blocks_editing(self):
        self.complete_prior_cases()
        def closed():
            self.running = True
        self.assertEqual(self.execute(override=lambda s: s.enter_context(patch.object(base, "wait_until_closed", closed))), 1)
        self.assertEqual(self.result["phase"], "quit-and-edit")
        self.assertNotIn("edit", self.actions)

    def test_changed_registration_during_wait_stops_before_the_next_album(self):
        self.complete_prior_cases()
        def wait(check):
            check()
            self.rows[0]["added"] = str(int(self.rows[0]["added"]) + 1)
            check()
        self.assertEqual(self.execute(override=lambda s: s.enter_context(patch.object(probe, "wait_between", wait))), 1)
        self.assertEqual([a for a in self.actions if isinstance(a, int)], [2])

    def test_unexpected_media_entry_is_retained_and_refused_before_addition(self):
        self.complete_prior_cases()
        unexpected = self.media / "retained.wav"
        unexpected.write_bytes(b"retain")
        self.assertEqual(self.execute(("TEST",)), 1)
        self.assertEqual(self.actions, [])
        self.assertEqual(unexpected.read_bytes(), b"retain")
        self.assertIn("REFUSED: first media entry 'retained.wav'; type file; size 6", self.output)

    def test_existing_registration_and_other_libraries_are_refused_before_any_change(self):
        self.complete_prior_cases()
        self.rows = [{"id": "F" * 16}]
        self.assertEqual(self.execute(("TEST",)), 1)
        self.assertEqual(self.actions, [])
        case = RunTests(); case.setUp()
        try:
            case.complete_prior_cases()
            case.media = case.home / "Music/M10-timing-v2-small/Media.localized"
            case.media.mkdir(parents=True)
            self.assertEqual(case.execute(("TEST",)), 1)
            self.assertEqual(case.actions, [])
            self.assertEqual(case.result["phase"], "preflight")
        finally:
            case.doCleanups()

    def test_cases_run_in_order_and_a_stop_is_not_bypassed(self):
        with self.assertRaises(base.Refusal):
            self.execute(("TEST",))
        self.assertFalse((self.bundle / "reference-private/artist").exists())
        self.complete_prior_cases("STOP")
        with self.assertRaises(base.Refusal):
            self.execute(("TEST",))
        self.assertEqual(self.actions, [])

    def test_dry_run_never_reads_music_preferences_or_creates_results(self):
        def fail(*args):
            self.fail("native operation in dry run")
        self.execute((), dry_run=True, override=lambda s: s.enter_context(patch.object(base, "media_directory", fail)))
        self.assertIsNone(self.result)
        self.assertEqual(self.actions, [])
        self.assertFalse((self.bundle / "reference-private").exists())

    def test_existing_run_refuses_reexecution_and_preserves_every_record(self):
        self.complete_prior_cases()
        self.execute()
        before = {str(p): p.read_bytes() for p in (self.bundle / "reference-private").rglob("*") if p.is_file()}
        actions = list(self.actions)
        with self.assertRaises(base.Refusal):
            self.execute(())
        self.assertEqual(actions, self.actions)
        self.assertEqual(before, {str(p): p.read_bytes() for p in (self.bundle / "reference-private").rglob("*") if p.is_file()})

    def test_report_combines_cases_once_without_music_or_personal_paths(self):
        target = self.home / "report.txt"
        with patch.object(base, "music", side_effect=AssertionError("report accessed Music")), \
                contextlib.redirect_stdout(io.StringIO()):
            empty = probe.report(self.bundle, target, True)
            self.assertFalse(target.exists())
        self.assertEqual(empty.count("NOT RUN: no saved measurement"), 4)
        self.assertIn("Separated-addition synthetic qualification: NOT COMPLETE", empty)
        self.reset("scale-release")
        self.execute()
        self.reset("artist")
        self.execute(("TEST", "2"))
        with patch.object(base, "music", side_effect=AssertionError("report accessed Music")), \
                contextlib.redirect_stdout(io.StringIO()):
            probe.report(self.bundle, target)
            before = target.read_bytes()
            with self.assertRaises(base.Refusal):
                probe.report(self.bundle, target)
        text = target.read_text()
        self.assertEqual(before, target.read_bytes())
        self.assertIn("scale-release: PASS\nartist: STOP\nartist-desc: NOT RUN\nartist-release: NOT RUN\n", text)
        self.assertIn("Historical evidence; not rerun", text)
        self.assertIn(probe.TIMING_REPORT, text)
        self.assertIn("NOT COMPLETE", text)
        self.assertNotIn(str(self.home), text)
        with self.assertRaises(base.Refusal):
            probe.report(self.bundle, self.bundle / "inside.txt")

    def test_report_marks_a_missing_final_record_incomplete_and_all_passes_as_synthetic_pass(self):
        for name in probe.CASE_NAMES:
            self.reset(name)
            self.execute()
            self.assertEqual(self.result["state"], "PASS")
        with contextlib.redirect_stdout(io.StringIO()):
            text = probe.report(self.bundle, self.home / "unused.txt", True)
        self.assertIn("Separated-addition synthetic qualification: PASS", text)
        self.assertIn("Cross-album timestamp ties in completed readditions: 0", text)
        (self.bundle / "reference-private/artist-release/result.json").unlink()
        with contextlib.redirect_stdout(io.StringIO()):
            text = probe.report(self.bundle, self.home / "unused.txt", True)
        self.assertIn("STOP: final result record missing", text)
        self.assertIn("NOT COMPLETE", text)

    def test_actual_bundle_verifier_rejects_corruption_plan_changes_and_links(self):
        probe.verify_bundle(self.bundle)
        file = self.bundle / "artist" / "files" / display.relatives(probe.case_spec("artist"))[0]
        original = file.read_bytes()
        file.write_bytes(b"changed")
        with self.assertRaises(base.Refusal):
            probe.verify_bundle(self.bundle)
        file.write_bytes(original)
        changed = dict(self.manifest, wait_limit=30.0)
        (self.bundle / "manifest.json").write_text(json.dumps(changed))
        with self.assertRaises(base.Refusal):
            probe.verify_bundle(self.bundle)
        (self.bundle / "manifest.json").write_text(json.dumps(self.manifest))
        file.unlink()
        file.symlink_to(self.old)
        with self.assertRaises(base.Refusal):
            probe.verify_bundle(self.bundle)


if __name__ == "__main__":
    unittest.main()
