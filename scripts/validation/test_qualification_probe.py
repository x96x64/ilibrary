"""Separated-addition qualification runs with substituted native operations."""

import contextlib
import copy
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import qualification_probe as probe
from test_timing_probe import music_scaffolding

timing, display, base, bulk = probe.timing, probe.display, probe.base, probe.bulk
PER_TRACK_SCRIPT = base.SNAPSHOT
ROW_KEYS = ("id", "title", "album", "artist", "path", "added", "legacy_path", "legacy_error", "path_error")


def serialize(rows):
    """Render rows as the Music scripts do: U+001F between fields and U+001E after each row."""
    return "".join(chr(31).join(str(r.get(k, r.get("path", "") if k == "legacy_path" else "")) for k in ROW_KEYS) +
                   chr(30) for r in rows)


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
            self.assertEqual(spec["library"], "M10-separated-v2-" + name)
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
        self.bundle = self.home / "ilibrary-m10-qualification-v2"
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
        self.rows, self.actions, self.running, self.snapshots = [], [], True, []
        self.second, self.clock = 845559600, 0.0
        self.readded_dates = None
        self.identifier = getattr(self, "identifier", 0)

    def music(self, script, *args):
        if script in (PER_TRACK_SCRIPT, bulk.BULK_SNAPSHOT):
            self.running = True
            self.snapshots.append("bulk" if script == bulk.BULK_SNAPSHOT else "per-track")
            return serialize(self.rows)
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
                (base, "music_running", lambda: self.running),
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


class RunAdditionTests(RunTests):
    """Additional full-sequence checks; inherited tests are not repeated."""

    test_complete_artist_case_runs_the_full_sequence_with_separated_readdition = None
    test_scale_case_separates_twenty_albums_and_removes_three_hundred_registrations = None
    test_cross_album_tie_stops_before_the_next_album_and_keeps_registrations = None
    test_gui_mismatch_is_completed_as_failed = None
    test_unknown_gui_is_not_a_pass = None
    test_unconfirmed_empty_gui_stops_before_quit_edit_or_readdition = None
    test_unexpected_registration_during_removal_stops_without_further_deletion = None
    test_late_music_launch_blocks_editing = None
    test_changed_registration_during_wait_stops_before_the_next_album = None
    test_unexpected_media_entry_is_retained_and_refused_before_addition = None
    test_existing_registration_and_other_libraries_are_refused_before_any_change = None
    test_cases_run_in_order_and_a_stop_is_not_bypassed = None
    test_dry_run_never_reads_music_preferences_or_creates_results = None
    test_existing_run_refuses_reexecution_and_preserves_every_record = None
    test_report_combines_cases_once_without_music_or_personal_paths = None
    test_report_marks_a_missing_final_record_incomplete_and_all_passes_as_synthetic_pass = None
    test_actual_bundle_verifier_rejects_corruption_plan_changes_and_links = None

    def journal(self, name=None):
        return bulk.read(self.bundle / "reference-private" / (name or self.name) / "removal-journal.jsonl")

    def events(self, name=None):
        path = self.bundle / "reference-private" / (name or self.name) / "removal-journal.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()]

    def wrap_music(self, wrapper):
        real = self.music
        return lambda s: s.enter_context(patch.object(base, "music", lambda script, *a: wrapper(real, script, *a)))

    def test_scale_run_uses_the_bulk_snapshot_after_the_equivalence_gate_and_records_progress(self):
        self.reset("scale-release")
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.result["state"], "PASS")
        self.assertEqual(self.snapshots.count("per-track"), 2)
        self.assertEqual(self.snapshots[:2], ["per-track", "per-track"])
        self.assertNotIn("per-track", self.snapshots[2:])
        self.assertIn("PASS: bulk snapshot equals the per-track snapshot", self.output)
        self.assertIn("MEASURED: per-track snapshot of 300 registrations", self.output)
        self.assertIn("MEASURED: bulk snapshot of 300 registrations", self.output)
        self.assertIn("PROGRESS: returned removals 300/300; remaining 0;", self.output)
        self.assertIn("CHECKPOINT: album M10 Album 20 fully removed; albums 20/20; registrations removed 300/300",
                      self.output)
        self.assertEqual(self.output.count("CHECKPOINT:"), 20)
        self.assertEqual(self.output.count("PROGRESS:"), 300)
        for phase in ("registration-removal", "seed-addition", "separated-readdition"):
            self.assertIn(phase, self.result["phase_seconds"])
            self.assertIn(f"DURATION: phase {phase}; seconds:", self.output)
        events = self.events()
        self.assertEqual([e["event"] for e in events[:3]], ["begin", "intent", "returned"])
        self.assertEqual(events[-1]["event"], "end")
        self.assertEqual(self.journal(), (300, 0, False, "end"))
        self.assertEqual(events[0]["count"], 300)
        self.assertEqual(events[0]["commit"], "a" * 40)

    def test_equivalence_gate_mismatch_stops_before_evacuation_and_saves_both_snapshots(self):
        self.complete_prior_cases()
        def wrapper(real, script, *args):
            result = real(script, *args)
            return result.replace("M10 Song 01", "M10 Song 99", 1) if script == bulk.BULK_SNAPSHOT else result
        self.assertEqual(self.execute(override=self.wrap_music(wrapper)), 1)
        self.assertEqual(self.result["state"], "STOP")
        self.assertEqual(self.result["phase"], "seed-addition")
        work = self.bundle / "reference-private/artist"
        self.assertTrue((work / "seed-registration.json").exists())
        self.assertTrue((work / "seed-registration-bulk.json").exists())
        self.assertFalse((work / "evacuated").exists())
        self.assertFalse((work / "removal-journal.jsonl").exists())
        self.assertNotIn("backup", self.actions)
        self.assertNotIn("delete", self.actions)
        self.assertIn("MEASURED: per-track snapshot", self.output)

    def gate_wrapper(self, mutate_bulk=None, mutate_per_track=None):
        def wrapper(real, script, *args):
            raw = real(script, *args)
            mutate = mutate_bulk if script == bulk.BULK_SNAPSHOT else mutate_per_track if script == PER_TRACK_SCRIPT else None
            if mutate and raw:
                rows = [row.split(chr(31)) for row in raw.split(chr(30)) if row]
                mutate(rows)
                raw = "".join(chr(31).join(row) + chr(30) for row in rows)
            return raw
        return wrapper

    def assert_gate_stops(self, mutate):
        self.complete_prior_cases()
        self.assertEqual(self.execute(override=self.wrap_music(self.gate_wrapper(mutate_bulk=mutate))), 1)
        self.assertEqual((self.result["state"], self.result["phase"]), ("STOP", "seed-addition"))
        self.assertNotIn("backup", self.actions)
        self.assertNotIn("delete", self.actions)
        self.assertFalse((self.bundle / "reference-private/artist/evacuated").exists())
        self.assertTrue((self.bundle / "reference-private/artist/seed-registration-bulk.json").exists())

    def test_gate_ignores_legacy_read_errors_of_the_per_track_snapshot(self):
        def legacy(rows):
            for row in rows:
                row[6], row[7] = "", "-1728"
        self.complete_prior_cases()
        self.assertEqual(self.execute(override=self.wrap_music(self.gate_wrapper(mutate_per_track=legacy))), 0)
        self.assertEqual(self.result["state"], "PASS")
        self.assertIn("legacy location read error (diagnostic only, not compared): 8 of 8", self.output)
        self.assertIn("PASS: bulk snapshot equals the per-track snapshot", self.output)

    def test_gate_fails_on_a_title_difference(self):
        self.assert_gate_stops(lambda rows: rows[0].__setitem__(1, "Other"))

    def test_gate_fails_on_an_album_difference(self):
        self.assert_gate_stops(lambda rows: rows[0].__setitem__(2, "Other"))

    def test_gate_fails_on_an_artist_difference(self):
        self.assert_gate_stops(lambda rows: rows[0].__setitem__(3, "Other"))

    def test_gate_fails_on_a_path_difference(self):
        self.assert_gate_stops(lambda rows: rows[0].__setitem__(4, rows[0][4] + "x"))

    def test_gate_fails_on_an_added_difference(self):
        self.assert_gate_stops(lambda rows: rows[0].__setitem__(5, str(int(rows[0][5]) + 1)))

    def test_gate_fails_on_a_path_error_difference(self):
        self.assert_gate_stops(lambda rows: rows[0].__setitem__(8, "-1728"))

    def test_gate_fails_on_a_different_identifier_set(self):
        self.assert_gate_stops(lambda rows: rows[0].__setitem__(0, "F" * 16))

    def test_interrupt_inside_delete_yields_interrupted_with_one_indeterminate_removal(self):
        self.complete_prior_cases()
        calls = []
        def wrapper(real, script, *args):
            calls.append(script)
            if script == base.DELETE and self.actions.count("delete") == 2:
                raise KeyboardInterrupt
            return real(script, *args)
        self.assertEqual(self.execute(override=self.wrap_music(wrapper)), 1)
        self.assertEqual(self.result["state"], "INTERRUPTED")
        self.assertEqual(self.result["phase"], "registration-removal")
        self.assertEqual(self.result["confirmed_removals"], 2)
        self.assertEqual(self.result["returned_unverified_removals"], 0)
        self.assertTrue(self.result["indeterminate_removal"])
        self.assertEqual(calls[-1], base.DELETE)
        self.assertEqual(self.actions.count("delete"), 2)
        self.assertEqual(self.journal(), (2, 0, True, "interrupted"))
        self.assertEqual(sum(e["event"] == "intent" for e in self.events()), 3)
        self.assertEqual(sum(e["event"] == "returned" for e in self.events()), 2)
        self.assertIn("INTERRUPTED: measurement interrupted", self.output)
        self.assertIn("removals verified by a later snapshot: 2", self.output)
        self.assertIn("indeterminate removal (intent without returned record): yes", self.output)
        self.assertIn("case result: INTERRUPTED", self.output)
        self.assertNotIn("STOP:", self.output)

    def test_interrupt_between_deletions_has_no_indeterminate_removal(self):
        self.complete_prior_cases()
        calls = []
        def wrapper(real, script, *args):
            calls.append(script)
            if script == bulk.BULK_SNAPSHOT and self.actions.count("delete") == 3:
                raise KeyboardInterrupt
            return real(script, *args)
        self.assertEqual(self.execute(override=self.wrap_music(wrapper)), 1)
        self.assertEqual(self.result["state"], "INTERRUPTED")
        self.assertEqual(self.result["confirmed_removals"], 2)
        self.assertEqual(self.result["returned_unverified_removals"], 1)
        self.assertFalse(self.result["indeterminate_removal"])
        self.assertEqual(self.journal(), (2, 1, False, "interrupted"))
        self.assertIn("removals returned without verification: 1", self.output)
        self.assertEqual(calls[-1], bulk.BULK_SNAPSHOT)
        self.assertIn("indeterminate removal (intent without returned record): no", self.output)

    def test_interrupt_outside_removal_reports_zero_confirmed_removals(self):
        self.complete_prior_cases()
        def wrapper(real, script, *args):
            if "to activate" in script:
                raise KeyboardInterrupt
            return real(script, *args)
        self.execute(override=self.wrap_music(wrapper))
        self.assertEqual(self.result["state"], "INTERRUPTED")
        self.assertEqual(self.result["phase"], "empty-gui")
        self.assertEqual((self.result["confirmed_removals"], self.result["returned_unverified_removals"],
                          self.result["indeterminate_removal"]), (8, 0, False))

    def test_interrupted_case_blocks_later_cases_and_the_report_prints_it_distinctly(self):
        self.reset("artist")
        self.complete_prior_cases("INTERRUPTED")
        with self.assertRaises(base.Refusal) as caught:
            self.execute(("TEST",))
        self.assertIn("INTERRUPTED", str(caught.exception))
        self.assertEqual(self.actions, [])
        # A later case recorded after an interruption must not be addressed either.
        (self.bundle / "reference-private/scale-release/result.json").write_text(json.dumps(
            {"case": "scale-release", "commit": "a" * 40, "state": "INTERRUPTED", "phase": "registration-removal"}))
        with contextlib.redirect_stdout(io.StringIO()):
            text = probe.report(self.bundle, self.home / "unused.txt", True)
        self.assertIn("scale-release: INTERRUPTED\nartist: NOT RUN\n", text)
        self.assertIn("Interrupted by the operator, not stopped by a refusal: scale-release", text)
        self.assertIn("NOT COMPLETE", text)
        self.assertIn("first qualification run: source bf84ee9; report SHA-256 " + probe.FIRST_REPORT, text)
        self.assertIn("KeyboardInterrupt after 803.057 seconds", text)


class RemovalFixture(unittest.TestCase):
    """The removal phase against a stubbed Music holding the 300 registrations of the scale-release case."""

    CASE = "scale-release"

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.spec = probe.case_spec(self.CASE)
        self.relatives = display.relatives(self.spec)
        self.originals = {r: self.root / "media" / r for r in self.relatives}
        self.paths = {r: self.root / "evacuated" / r for r in self.relatives}
        self.rows = []
        for index, relative in enumerate(self.relatives, 1):
            path = Path(relative)
            self.paths[relative].parent.mkdir(parents=True, exist_ok=True)
            self.paths[relative].write_bytes(b"synthetic " + relative.encode())
            self.rows.append({"id": f"{index:016X}", "artist": path.parts[-3], "album": path.parts[-2],
                              "title": path.stem[3:], "path": str(self.originals[relative]),
                              "added": str(845559600 + index)})
        self.records = copy.deepcopy(self.rows)
        self.states = base.file_state(self.paths)
        self.image = self.root / "backup.dmg"
        self.image.write_bytes(b"synthetic image")
        self.image_hash = probe.digest(self.image)
        self.snapshots, self.deletes, self.hook = [], [], None
        self.mounted, self.guards = False, 0
        bundle = self.root / "bundle"
        bundle.mkdir()
        self.addCleanup(setattr, base, "_diagnostic_work", None)
        self.m = probe.Measurement(bundle, self.CASE, {"commit": "b" * 40}, self.root)
        self.addCleanup(self.m.report.close)
        self.m.guard = self.guard
        self.m.use_bulk = True
        self.journal_path = self.m.work / "removal-journal.jsonl"

    def guard(self):
        self.guards += 1
        if self.hook:
            self.hook("guard", self.guards, None)

    def music(self, script, *args):
        if script in (PER_TRACK_SCRIPT, bulk.BULK_SNAPSHOT):
            self.snapshots.append("bulk" if script == bulk.BULK_SNAPSHOT else "per-track")
            return serialize(self.rows)
        self.assertEqual(script, base.DELETE)
        self.assertEqual(len(args), 4)
        self.deletes.append(args[0])
        # The intent must already be durable when Music is addressed.
        events = [json.loads(line) for line in self.journal_path.read_text().splitlines()]
        self.assertEqual((events[-1]["event"], events[-1]["id"]), ("intent", args[0]))
        if self.hook and self.hook("delete", len(self.deletes), args):
            return ""
        self.remove(args)
        return ""

    def remove(self, args):
        matches = [r for r in self.rows if r["id"] == args[0]]
        if len(matches) != 1 or (matches[0]["title"], matches[0]["album"], matches[0]["artist"]) != tuple(args[1:3] + args[3:]):
            raise base.Refusal("identity changed")
        self.rows.remove(matches[0])

    def run_removal(self):
        with patch.object(base, "music", self.music), contextlib.redirect_stdout(io.StringIO()):
            self.m.remove_registrations(self.records, self.paths, self.originals, self.states, self.image,
                                        self.image_hash, self.root / "backup-mount")

    def events(self):
        return [json.loads(line) for line in self.journal_path.read_text().splitlines()]


class RemovalTests(RemovalFixture):
    def test_exactly_the_three_hundred_seeded_ids_are_deleted_in_plan_order_one_per_call(self):
        self.assertEqual(len(self.records), 300)
        self.run_removal()
        self.assertEqual(self.deletes, [r["id"] for r in self.records])
        self.assertEqual(self.rows, [])
        self.assertEqual(bulk.read(self.journal_path), (300, 0, False, "end"))
        events = self.events()
        self.assertEqual(events[0]["ids"], [r["id"] for r in self.records])
        self.assertEqual((events[0]["count"], events[0]["image_sha256"], events[0]["commit"]),
                         (300, self.image_hash, "b" * 40))
        self.assertEqual([e["event"] for e in events[1:6]], ["intent", "returned", "verified", "intent", "returned"])
        self.assertEqual(sum(e["event"] == "verified" for e in events), 300)
        self.assertEqual([e["seq"] for e in events if e["event"] == "intent"], list(range(1, 301)))

    def test_snapshot_event_count_is_constant_per_iteration_and_no_per_track_snapshot_is_used(self):
        self.run_removal()
        # One bulk snapshot before every deletion plus the final emptiness check; none per track.
        self.assertEqual(self.snapshots, ["bulk"] * 301)
        self.assertEqual(self.guards, 300)

    def test_pre_delete_file_comparison_runs_once_before_the_first_deletion_and_after_every_deletion(self):
        real, calls = base.compare_files, []
        def counting(paths, expected):
            calls.append(len(self.deletes))
            return real(paths, expected)
        with patch.object(base, "compare_files", counting):
            self.run_removal()
        self.assertEqual(calls, [0] + list(range(1, 301)))

    def test_bulk_script_is_constant_in_track_count_and_checks_consistency(self):
        script = bulk.BULK_SNAPSHOT
        # Each bulk property is read by one reference; the loop below the tell block reads lists only.
        self.assertEqual(script.count('tell application "Music"'), 1)
        self.assertEqual(script.count("every track of library playlist 1"), 6)
        self.assertEqual(script.count("every file track of library playlist 1"), 2)
        self.assertIn("if firstIDs is not lastIDs then error", script)
        self.assertIn("Property lists differ in length", script)
        loop = script[script.index("repeat with i from 1"):]
        self.assertNotIn("tell application", loop)
        self.assertNotIn("library playlist", loop)

    def fault_at(self, j, phase, action, expect_raise=Exception):
        def hook(kind, number, args):
            if kind == phase and number == j:
                return action(args)
        self.hook = hook
        with self.assertRaises(expect_raise):
            self.run_removal()

    def check_stopped(self, j, confirmed, unverified, indeterminate):
        self.assertEqual(len(self.deletes), j)
        self.assertEqual(bulk.read(self.journal_path), (confirmed, unverified, indeterminate, "stop"))
        self.assertEqual(self.events()[-1]["verified"], confirmed)
        self.assertEqual(self.events()[-1]["returned_unverified"], unverified)
        self.assertEqual(self.deletes, [r["id"] for r in self.records][:len(self.deletes)])

    J = 7

    def test_fault_music_deletes_a_different_track(self):
        def other(args):
            del self.rows[-1]
            return True
        self.fault_at(self.J, "delete", other, base.Refusal)
        self.check_stopped(self.J, self.J - 1, 1, False)

    def test_fault_music_deletes_an_extra_track(self):
        def extra(args):
            self.remove(args)
            del self.rows[-1]
            return True
        self.fault_at(self.J, "delete", extra, base.Refusal)
        self.check_stopped(self.J, self.J - 1, 1, False)

    def test_fault_a_registration_is_added(self):
        def add(args):
            self.remove(args)
            self.rows.append(dict(id="F" * 16, artist="Other", album="Other", title="Other", path="/elsewhere",
                                  added="845559600"))
            return True
        self.fault_at(self.J, "delete", add, base.Refusal)
        self.check_stopped(self.J, self.J - 1, 1, False)

    def test_fault_an_evacuated_file_changes(self):
        def change(args):
            self.remove(args)
            next(iter(self.paths.values())).write_bytes(b"changed")
            return True
        self.fault_at(self.J, "delete", change, base.Refusal)
        self.check_stopped(self.J, self.J - 1, 0, True)

    def test_fault_the_image_changes(self):
        def change(args):
            self.remove(args)
            self.image.write_bytes(b"changed image")
            return True
        self.fault_at(self.J, "delete", change, base.Refusal)
        self.check_stopped(self.J, self.J - 1, 1, False)

    def test_fault_the_image_is_mounted(self):
        def mount(args):
            self.remove(args)
            self.mounted = True
            return True
        with patch.object(base.os.path, "ismount", lambda path: self.mounted):
            self.fault_at(self.J, "delete", mount, base.Refusal)
        self.check_stopped(self.J, self.J - 1, 1, False)

    def test_fault_delete_identity_mismatch(self):
        def mismatch(args):
            raise base.Refusal("Identity changed")
        self.fault_at(self.J, "delete", mismatch, base.Refusal)
        self.check_stopped(self.J, self.J - 1, 0, True)
        self.assertEqual(len(self.rows), 300 - (self.J - 1))

    def test_fault_delete_error(self):
        def error(args):
            raise subprocess.CalledProcessError(1, "osascript")
        self.fault_at(self.J, "delete", error, subprocess.CalledProcessError)
        self.check_stopped(self.J, self.J - 1, 0, True)

    def test_interrupt_inside_delete_leaves_one_indeterminate_intent_and_no_further_call(self):
        def interrupt(args):
            raise KeyboardInterrupt
        self.fault_at(self.J, "delete", interrupt, KeyboardInterrupt)
        self.assertEqual(bulk.read(self.journal_path), (self.J - 1, 0, True, "interrupted"))
        self.assertEqual(len(self.deletes), self.J)
        self.assertEqual(self.snapshots, ["bulk"] * self.J)
        events = self.events()
        self.assertEqual([e["event"] for e in events[-2:]], ["intent", "interrupted"])

    def test_interrupt_between_deletions_leaves_no_indeterminate_intent(self):
        def interrupt(args):
            raise KeyboardInterrupt
        self.fault_at(self.J, "guard", interrupt, KeyboardInterrupt)
        self.assertEqual(bulk.read(self.journal_path), (self.J - 2, 1, False, "interrupted"))
        self.assertEqual(len(self.deletes), self.J - 1)

    def test_journal_is_append_only_synchronized_and_survives_a_second_open(self):
        with patch.object(bulk.os, "fsync", wraps=bulk.os.fsync) as fsync:
            self.run_removal()
        self.assertEqual(fsync.call_count, 1 + 900 + 1)
        first = self.journal_path.read_bytes()
        journal = bulk.Journal(self.journal_path)
        journal.write(event="stop", completed=0)
        journal.close()
        self.assertTrue(self.journal_path.read_bytes().startswith(first))

    def test_synthetic_timing_of_the_stubbed_removal_phase(self):
        start = time.perf_counter()
        self.run_removal()
        seconds = time.perf_counter() - start
        print(f"\nSYNTHETIC: stubbed removal of 300 registrations (bulk snapshots, real local hashing and journal "
              f"fsync, no Apple Events): {seconds:.3f} seconds; {seconds / 300 * 1000:.1f} ms per removal")
        self.assertLess(seconds, 120)


class BulkParsingTests(unittest.TestCase):
    def parse(self, raw):
        with patch.object(base, "music", lambda script, *a: raw if script == bulk.BULK_SNAPSHOT else self.fail()):
            return bulk.snapshot()

    def test_bulk_rows_do_not_fabricate_legacy_values(self):
        self.assertIn('& fs & "" & fs & "bulk-not-read" & fs & pathError & rs', bulk.BULK_SNAPSHOT)

    def test_empty_library_yields_no_rows(self):
        self.assertEqual(self.parse(""), [])

    def test_rows_use_the_per_track_format_and_the_parser_is_restored(self):
        row = ["0123456789ABCDEF", "M10 Song 01", "M10 Album 01", "M10 Artist 01", "/a/b.m4a",
               "8.45559600E+8", "/a/b.m4a", "", ""]
        rows = self.parse(chr(31).join(row) + chr(30))
        self.assertEqual(rows, [dict(zip(ROW_KEYS, row))])
        self.assertEqual(base.SNAPSHOT, PER_TRACK_SCRIPT)
        self.assertEqual(display.stable(rows)[0]["added"], "845559600")

    def test_non_file_track_row_is_parsed_but_refused_by_the_inventory(self):
        row = ["0123456789ABCDEF", "M10 Song 01", "M10 Album 01", "M10 Artist 01", "", "845559600", "",
               "non-file-track", "non-file-track"]
        rows = self.parse(chr(31).join(row) + chr(30))
        self.assertEqual(rows[0]["path_error"], "non-file-track")
        with self.assertRaises(base.Refusal):
            display.inventory(rows, {"M10 Artist 01/M10 Album 01/01 M10 Song 01.m4a":
                                     Path("/a/b.m4a")})

    def test_malformed_output_and_duplicate_identifiers_are_refused(self):
        with self.assertRaises(base.Refusal):
            self.parse("0123456789ABCDEF" + chr(31) + "x" + chr(30))
        row = chr(31).join(["0123456789ABCDEF", "t", "a", "r", "/p", "1", "/p", "", ""]) + chr(30)
        with self.assertRaises(base.Refusal):
            self.parse(row + row)

    def test_changed_identifier_list_fails_the_script_and_is_refused(self):
        # osascript exits non-zero when the script raises "Library changed during snapshot".
        failed = subprocess.CompletedProcess(["osascript"], 1, "", "Library changed during snapshot (-2700)")
        with patch.object(subprocess, "run", return_value=failed):
            with self.assertRaises(base.Refusal):
                bulk.snapshot()
        self.assertEqual(base.SNAPSHOT, PER_TRACK_SCRIPT)



if __name__ == "__main__":
    unittest.main()
