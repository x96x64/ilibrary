"""Timing separation and complete isolated runs with substituted native operations."""

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

import timing_probe as probe

base, display = probe.base, probe.display
# Locale names observed in a new Music 1.7 media folder; fixture contents are synthetic.
LOCALES = ("ar ca cs da de el en en_AU en_CA en_GB en_IN en_PH es es_419 es_US fi fr fr_CA he hi hr hu id it ja "
           "ko ms nl no pl pt pt_PT ro ru sk sl sv th tr uk vi zh_CN zh_HK zh_TW").split()


def music_scaffolding(media):
    """Create the observed names, types, and sizes with synthetic contents."""
    (media / ".DS_Store").write_bytes(b"synthetic Finder state")
    (media / ".Media Preferences.plist").write_bytes(b"synthetic preferences")
    for folder in (media, media / "Automatically Add to Music.localized"):
        (folder / ".localized").mkdir(parents=True)
        for locale in LOCALES:
            (folder / ".localized" / (locale + ".strings")).write_bytes(b"synthetic localization")


class TimingTests(unittest.TestCase):
    def test_wait_uses_monotonic_time_and_checks_both_sides(self):
        clock = [10.0]
        checks = []
        elapsed = probe.wait_between(lambda: checks.append(clock[0]), lambda: clock[0],
                                     lambda amount: clock.__setitem__(0, clock[0] + amount))
        self.assertEqual(elapsed, 2.0)
        self.assertEqual(checks, [10.0, 12.0])

    def test_slow_state_check_refuses_next_addition(self):
        clock = [0.0]
        def slow():
            clock[0] += 31.0
        with self.assertRaises(base.Refusal):
            probe.wait_between(slow, lambda: clock[0], lambda _: None)

    def test_changed_state_during_wait_is_not_ignored(self):
        def changed():
            raise base.Refusal("changed")
        with self.assertRaises(base.Refusal):
            probe.wait_between(changed)

    def test_ranges_must_be_strictly_separated_and_exponents_are_exact(self):
        previous = [{"added": "8.45559632E+8"}, {"added": "845559634"}]
        for value, passed in (("845559634", False), ("845559633", False), ("845559635", True)):
            with self.subTest(value=value):
                result = probe.timing_boundary(previous, [{"added": value}, {"added": "845559636"}])
                self.assertEqual(result["separated"], passed)
                self.assertEqual(result["previous_max"], 845559634)
        with self.assertRaises(base.Refusal):
            probe.timing_boundary([], [{"added": "845559634.5"}])


class RunTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name).resolve()
        self.bundle = self.home / "ilibrary-m10-timing-v2"
        self.bundle.mkdir()
        self.media = self.home / "Music/M10-timing-v2-small/Media.localized"
        self.media.mkdir(parents=True)
        music_scaffolding(self.media)
        self.rows, self.actions, self.running = [], [], True
        self.dates = {1: ["845559632", "845559632"], 2: ["845559635", "845559635"],
                      3: ["845559638", "845559638"]}
        self.clock = 0.0
        for name in probe.expected_files():
            path = self.bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"synthetic original")
        self.manifest = {"format": probe.FORMAT, "commit": "a" * 40, "spec": probe.spec(),
                         "wait_seconds": probe.WAIT_SECONDS, "wait_limit": probe.WAIT_LIMIT,
                         "files": {n: probe.digest(self.bundle / n) for n in probe.expected_files()}}
        (self.bundle / "manifest.json").write_text(json.dumps(self.manifest))
        (self.bundle / ".DS_Store").write_bytes(b"retained Finder state")
        self.old = self.home / "ilibrary-m10-display-v3/reference-private/small-existing/result.txt"
        self.old.parent.mkdir(parents=True)
        self.old.write_bytes(b"retained historical negative result")
        self.addCleanup(setattr, base, "_diagnostic_work", None)

    def snapshot(self):
        self.running = True
        return copy.deepcopy(self.rows)

    def music(self, script, *args):
        self.assertNotIn("delete", script)
        self.assertNotEqual(script, base.DELETE)
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
        return image, probe.digest(image), base.file_state(paths)

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
        root = Path(args[1])
        journal = root / ".ilibrary-add.json"
        if journal.exists():
            self.actions.append("repeat")
            return
        number = int(root.name[-2:])
        self.actions.append(number)
        album = next(a for a in probe.spec()["albums"] if a["number"] == number)
        sources, destinations, ids = [], [], []
        for i, relative in enumerate(display.relatives({"albums": [album]})):
            source = root / Path(relative).name
            dest = self.media / "Music" / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            source.rename(dest)
            identifier = f"{len(self.rows) + 1:016X}"
            self.rows.append(dict(id=identifier, artist=album["artist"], album=album["album"],
                                  title=dest.stem[3:], path=str(dest), added=self.dates[number][i]))
            sources.append(str(source)); destinations.append(str(dest)); ids.append(identifier)
        journal.write_text(json.dumps({"format": "ilibrary-add-journal-1", "entries": [dict(
            album=album["album"], albumArtist=album["artist"], sources=sources, destinations=destinations,
            persistentIDs=ids, state="added")]}))

    def advance(self, amount):
        self.clock += amount

    def execute(self, answers=("TEST", "1", "1"), override=None, dry_run=False):
        output = io.StringIO()
        real_state = base.file_state
        real_wait = probe.wait_between
        def states(paths):
            return {r: dict(s, created=None) for r, s in real_state(paths).items()}
        with contextlib.ExitStack() as stack:
            for obj, name, value in [
                (probe.sys, "platform", "darwin"), (base, "require_test_user", lambda: None),
                (base.pwd, "getpwuid", lambda uid: SimpleNamespace(pw_dir=str(self.home))),
                (base, "check_account", lambda: None), (base, "media_directory", lambda home: self.media),
                (base, "music_running", lambda: self.running), (base, "snapshot", self.snapshot),
                (base, "music", self.music), (base, "run", self.native), (base, "make_backup", self.backup),
                (base, "file_state", states),
                (probe.Measurement, "cli", lambda m, *args: self.cli(m, *args)),
                (probe, "wait_between", lambda check: real_wait(check, lambda: self.clock, self.advance)),
            ]:
                stack.enter_context(patch.object(obj, name, value))
            if override:
                override(stack)
            stack.enter_context(patch("builtins.input", side_effect=answers))
            stack.enter_context(contextlib.redirect_stdout(output))
            try:
                code = probe.execute(self.bundle, dry_run)
            finally:
                self.output = output.getvalue()
        path = self.bundle / "reference-private" / probe.NAME / "result.json"
        self.result = json.loads(path.read_text()) if path.exists() else None
        self.assertNotIn(str(self.home), self.output)
        self.assertEqual(self.old.read_bytes(), b"retained historical negative result")
        return code

    def test_complete_run_checks_waits_dates_gui_repeat_and_preservation(self):
        before = {n: probe.digest(self.bundle / n) for n in probe.expected_files()}
        self.assertEqual(self.execute(), 0)
        self.assertEqual(self.result["state"], "PASS")
        self.assertEqual([a for a in self.actions if isinstance(a, int)], [1, 2, 3])
        self.assertEqual(self.actions.count("repeat"), 3)
        self.assertEqual(self.actions.count("quit"), 2)
        self.assertEqual(self.result["dates"]["cross_album_ties"], 0)
        self.assertEqual([r["waited_seconds"] for r in self.result["boundaries"]], [0, 2, 2])
        self.assertEqual(before, {n: probe.digest(self.bundle / n) for n in before})
        saved = json.loads((self.bundle / "reference-private" / probe.NAME / "initial-media.json").read_text())
        self.assertEqual(len(saved), 93)
        self.assertNotIn(None, [e["category"] for e in saved])
        self.assertIn("directories: 3; Finder state: 1; Music preferences: 1; Music localization: 88; refused: 0",
                      self.output)

    def test_tied_or_reversed_dates_stop_before_the_next_album_without_removal(self):
        for date in ("845559632", "845559631"):
            with self.subTest(date=date):
                # Each subcase has its own disposable test fixture.
                case = RunTests(); case.setUp()
                try:
                    case.dates[2] = [date, date]
                    self.assertEqual(case.execute(), 1)
                    self.assertEqual(case.result["state"], "STOP")
                    self.assertEqual(len(case.rows), 4)
                    self.assertNotIn(3, case.actions)
                    self.assertFalse(case.result["boundaries"][-1]["separated"])
                    self.assertTrue((case.bundle / "reference-private" / probe.NAME / "synthetic-backup.dmg").exists())
                finally:
                    case.doCleanups()

    def test_gui_mismatch_remains_failed_even_with_separated_dates(self):
        self.assertEqual(self.execute(("TEST", "2", "2 3 1", "2", "2 3 1")), 0)
        self.assertEqual(self.result["state"], "FAIL")
        self.assertEqual(self.actions.count("repeat"), 3)

    def test_unknown_gui_is_not_a_pass(self):
        self.execute(("TEST", "3", "3"))
        self.assertEqual(self.result["state"], "UNVERIFIED")

    def test_dry_run_never_reads_music_preferences_or_creates_results(self):
        def fail(*args):
            self.fail("native operation in dry run")
        self.execute((), dry_run=True, override=lambda s: s.enter_context(patch.object(base, "media_directory", fail)))
        self.assertIsNone(self.result)
        self.assertEqual(self.actions, [])
        self.assertFalse((self.bundle / "reference-private").exists())

    def test_old_library_is_refused_before_any_music_command(self):
        self.media = self.home / "Music/M10-v2-small/Media"
        self.media.mkdir(parents=True)
        self.assertEqual(self.execute(("TEST",)), 1)
        self.assertEqual(self.actions, [])

    def test_existing_registration_is_refused_without_quit_edit_or_addition(self):
        self.rows = [{"id": "F" * 16}]
        self.assertEqual(self.execute(("TEST",)), 1)
        self.assertEqual(self.actions, [])

    def test_unregistered_existing_file_is_retained_and_refused(self):
        unexpected = self.media / "retained.wav"
        unexpected.write_bytes(b"retain")
        self.assertEqual(self.execute(("TEST",)), 1)
        self.assertEqual(self.actions, [])
        self.assertEqual(unexpected.read_bytes(), b"retain")
        self.assertIn("REFUSED: first media entry 'retained.wav'; type file; size 6", self.output)
        self.assertEqual(self.result["phase"], "empty-library")
        saved = json.loads((self.bundle / "reference-private" / probe.NAME / "initial-media.json").read_text())
        self.assertEqual([e["relative"] for e in saved if e["category"] is None], ["retained.wav"])

    def test_scaffolding_names_outside_their_observed_places_are_refused(self):
        cases = {
            "ja.strings": b"misplaced localization",
            "Music/.localized/ja.strings": b"nested localization",
            "Music/.Media Preferences.plist": b"nested preferences",
            ".localized/notes.txt": b"other localization entry",
            ".localized/ja.strings.m4a": b"audio name",
            ".localized/localization.strings": b"name outside the locale form",
            "Artist/Album/01 Song.m4a": b"audio",
        }
        for relative, content in cases.items():
            with self.subTest(relative=relative):
                media = self.home / ("case-" + str(len(list(self.home.glob("case-*"))))) / "Media.localized"
                media.mkdir(parents=True)
                music_scaffolding(media)
                path = media / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
                rows = {r["relative"]: r for r in probe.media_inventory(media)}
                self.assertIsNone(rows[relative]["category"])
                self.assertEqual(path.read_bytes(), content)
        media = self.home / "case-oversized" / "Media.localized"
        media.mkdir(parents=True)
        music_scaffolding(media)
        (media / ".localized/ja.strings").write_bytes(b"x" * (probe.SCAFFOLDING_LIMIT + 1))
        (media / ".Media Preferences.plist").write_bytes(b"x" * (probe.SCAFFOLDING_LIMIT + 1))
        rows = {r["relative"]: r for r in probe.media_inventory(media)}
        self.assertIsNone(rows[".localized/ja.strings"]["category"])
        self.assertIsNone(rows[".Media Preferences.plist"]["category"])
        self.assertEqual(rows[".DS_Store"]["category"], "finder-state")

    def test_links_in_the_media_folder_are_refused_without_being_followed(self):
        outside = self.home / "outside"
        (outside / ".localized").mkdir(parents=True)
        (outside / ".localized/ja.strings").write_bytes(b"outside")
        (self.media / "linked").symlink_to(outside, target_is_directory=True)
        (self.media / "Automatically Add to Music.localized/.localized/ja.strings").unlink()
        (self.media / "Automatically Add to Music.localized/.localized/ja.strings").symlink_to(
            outside / ".localized/ja.strings")
        rows = {r["relative"]: r for r in probe.media_inventory(self.media)}
        self.assertEqual(rows["linked"]["type"], "symlink")
        self.assertIsNone(rows["linked"]["category"])
        self.assertNotIn("linked/.localized/ja.strings", rows)
        self.assertIsNone(rows["Automatically Add to Music.localized/.localized/ja.strings"]["category"])
        self.assertEqual(self.execute(("TEST",)), 1)
        self.assertEqual(self.actions, [])
        self.assertEqual((outside / ".localized/ja.strings").read_bytes(), b"outside")

    def test_media_inventory_is_bounded(self):
        current = self.home / "deep" / "Media.localized"
        current.mkdir(parents=True)
        media = current
        for _ in range(probe.MEDIA_DEPTH_LIMIT + 2):
            current = current / "child"
            current.mkdir()
        with self.assertRaises(base.Refusal):
            probe.media_inventory(media)
        with patch.object(probe, "MEDIA_ENTRY_LIMIT", 10):
            with self.assertRaises(base.Refusal):
                probe.media_inventory(self.media)

    def test_changed_registration_during_wait_stops_before_second_addition(self):
        def wait(check):
            check()
            self.rows[0]["added"] = "845559633"
            check()
        self.assertEqual(self.execute(override=lambda s: s.enter_context(patch.object(probe, "wait_between", wait))), 1)
        self.assertNotIn(2, self.actions)

    def test_late_music_launch_blocks_editing(self):
        def closed():
            self.running = True
        self.assertEqual(self.execute(override=lambda s: s.enter_context(patch.object(base, "wait_until_closed", closed))), 1)
        self.assertNotIn("edit", self.actions)
        self.assertNotIn(1, self.actions)

    def test_file_change_during_wait_stops_before_second_addition(self):
        def wait(check):
            check()
            path = self.bundle / "reference-private/timing-small/staging" / display.relatives(probe.spec())[2]
            path.write_bytes(b"unexpected change")
            check()
            return 2.0
        self.assertEqual(self.execute(override=lambda s: s.enter_context(patch.object(probe, "wait_between", wait))), 1)
        self.assertNotIn(2, self.actions)
        self.assertEqual(len(self.rows), 2)

    def test_backup_change_during_wait_stops_before_second_addition(self):
        def wait(check):
            check()
            (self.bundle / "reference-private/timing-small/synthetic-backup.dmg").write_bytes(b"changed")
            return 2.0
        self.assertEqual(self.execute(override=lambda s: s.enter_context(patch.object(probe, "wait_between", wait))), 1)
        self.assertNotIn(2, self.actions)

    def test_interrupt_is_retained_and_can_be_reported_once(self):
        self.assertEqual(self.execute((KeyboardInterrupt(),)), 1)
        target = self.home / "report.txt"
        with patch.object(base, "music", side_effect=AssertionError("report accessed Music")), contextlib.redirect_stdout(io.StringIO()):
            probe.report(self.bundle, target, True)
            self.assertFalse(target.exists())
            probe.report(self.bundle, target)
            before = target.read_bytes()
            with self.assertRaises(base.Refusal):
                probe.report(self.bundle, target)
            self.assertEqual(before, target.read_bytes())
        self.assertIn("case result: STOP", target.read_text())
        self.assertIn("Historical comparison; not rerun", target.read_text())
        self.assertNotIn(str(self.home), target.read_text())

    def test_existing_run_refuses_reexecution_and_preserves_every_record(self):
        self.execute()
        before = {str(p): p.read_bytes() for p in (self.bundle / "reference-private").rglob("*") if p.is_file()}
        actions = list(self.actions)
        with self.assertRaises(base.Refusal):
            self.execute(())
        self.assertEqual(actions, self.actions)
        self.assertEqual(before, {str(p): p.read_bytes() for p in (self.bundle / "reference-private").rglob("*") if p.is_file()})

    def test_missing_final_record_is_reported_as_incomplete(self):
        self.execute()
        (self.bundle / "reference-private" / probe.NAME / "result.json").unlink()
        output = self.home / "incomplete-report.txt"
        with contextlib.redirect_stdout(io.StringIO()):
            probe.report(self.bundle, output)
        self.assertIn("STOP: final result record missing", output.read_text())

    def test_actual_bundle_verifier_rejects_corruption_and_links(self):
        probe.verify_bundle(self.bundle)
        file = self.bundle / "files" / display.relatives(probe.spec())[0]
        file.write_bytes(b"changed")
        with self.assertRaises(base.Refusal):
            probe.verify_bundle(self.bundle)
        file.unlink()
        file.symlink_to(self.old)
        with self.assertRaises(base.Refusal):
            probe.verify_bundle(self.bundle)


if __name__ == "__main__":
    unittest.main()
