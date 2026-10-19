"""M10 display qualification guards and complete simulated runs; no Apple Events."""

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

import display_probe as probe

base = probe.base


class TestWorkspace(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.bundle = self.home / "bundle"
        self.bundle.mkdir()
        self.addCleanup(setattr, base, "_diagnostic_work", None)


class DisplayTests(TestWorkspace):
    def test_only_regular_finder_state_is_excluded_without_removal(self):
        payload = self.bundle / "nested/payload"
        payload.parent.mkdir()
        payload.write_bytes(b"required")
        metadata = [self.bundle / ".DS_Store", payload.parent / ".DS_Store"]
        for path in metadata:
            path.write_bytes(b"synthetic Finder state")
        before = {str(p): (p.read_bytes(), p.stat().st_mtime_ns) for p in [payload, *metadata]}
        base.verify_bundle_files(self.bundle, {"nested/payload"})
        self.assertEqual(before, {str(p): (p.read_bytes(), p.stat().st_mtime_ns) for p in [payload, *metadata]})

    def test_other_additions_and_missing_entries_remain_refusals_with_private_details(self):
        work = self.bundle / "reference-private"
        work.mkdir()
        base._diagnostic_work = work
        for name in (".DS_Store.backup", ".ds_store", "unknown.txt"):
            path = self.bundle / name
            path.write_bytes(b"unknown")
            with self.subTest(name=name), self.assertRaises(base.Refusal):
                base.verify_bundle_files(self.bundle, {"required"})
            row = json.loads((work / "diagnostics.jsonl").read_text().splitlines()[-1])
            self.assertEqual(row["value"]["missing"], ["required"])
            self.assertEqual(row["value"]["extra"], [name])
            path.unlink()

    def test_finder_named_links_directories_and_special_files_are_refused(self):
        entry = self.bundle / ".DS_Store"
        outside = self.home / "outside"
        outside.write_bytes(b"not read")
        entry.symlink_to(outside)
        with self.assertRaises(base.Refusal):
            base.bundle_files(self.bundle)
        entry.unlink()
        entry.mkdir()
        with self.assertRaises(base.Refusal):
            base.bundle_files(self.bundle)
        entry.rmdir()
        base.os.mkfifo(entry)
        with self.assertRaises(base.Refusal):
            base.bundle_files(self.bundle)

    def test_current_bundle_with_finder_state_still_verifies_required_hashes(self):
        files = {"bin/ilibrary", "display_probe.py", "rebuild_probe.py", "PROCEDURE.md"}
        for name in probe.CASE_NAMES[1:]:
            files.update(f"{name}/files/{r}" for r in probe.relatives(probe.case_spec(name)))
            files.update((f"{name}/catalog.json", f"{name}/edited-catalog.json"))
        manifest = {"format": probe.FORMAT, "commit": "a" * 40,
                    "cases": {n: probe.case_spec(n) for n in probe.CASE_NAMES}, "files": {}}
        for relative in files:
            path = self.bundle / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"synthetic fixture")
            manifest["files"][relative] = probe.digest(path)
        (self.bundle / "manifest.json").write_text(json.dumps(manifest))
        (self.bundle / ".DS_Store").write_bytes(b"synthetic Finder state")
        self.assertEqual(probe.verify_bundle(self.bundle), manifest)
        (self.bundle / "bin/ilibrary").write_bytes(b"changed")
        with self.assertRaises(base.Refusal):
            probe.verify_bundle(self.bundle)

    def test_both_media_names_pass_the_real_preference_parser(self):
        spec = probe.case_spec("small-existing")
        for name in ("Media", "Media.localized"):
            media = self.home / "Music" / spec["library"] / name
            media.mkdir(parents=True)
            with patch.object(base, "run", return_value=media.as_uri() + "/") as run, \
                    patch.object(base, "music") as music:
                self.assertEqual(probe.selected_media(self.home, spec), media)
                run.assert_called_once_with(["/usr/bin/defaults", "read", "com.apple.Music", "media-folder-url"])
                music.assert_not_called()
            if name == "Media.localized":
                self.assertNotEqual(media, self.home / "Music" / spec["library"] / "Media")

    def test_media_name_support_does_not_expand_the_planned_parent(self):
        spec = probe.case_spec("small-existing")
        parent = self.home / "Music" / spec["library"]
        for media in (parent / "Media.localized.backup", parent / "nested/Media.localized",
                      self.home / "Music/Other/Media.localized", self.home / "Other/Media.localized"):
            media.mkdir(parents=True)
            with patch.object(base, "run", return_value=media.as_uri()), self.assertRaises(base.Refusal):
                probe.selected_media(self.home, spec)

    def test_media_selection_refuses_missing_paths_and_symbolic_links(self):
        spec = probe.case_spec("small-existing")
        media = self.home / "Music" / spec["library"] / "Media.localized"
        media.parent.mkdir(parents=True)
        with patch.object(base, "run", return_value=media.as_uri()), self.assertRaises(base.Refusal):
            probe.selected_media(self.home, spec)
        other = self.home / "other"
        other.mkdir()
        media.symlink_to(other, target_is_directory=True)
        with patch.object(base, "run", return_value=media.as_uri()), self.assertRaises(base.Refusal):
            probe.selected_media(self.home, spec)

    def test_media_guard_pins_the_selected_path_even_between_accepted_names(self):
        spec = probe.case_spec("small-existing")
        parent = self.home / "Music" / spec["library"]
        m = SimpleNamespace(home=self.home, media=parent / "Media.localized")
        with patch.object(base, "require_test_user"), patch.object(base, "check_account"), \
                patch.object(base, "media_directory", return_value=parent / "Media"), \
                self.assertRaises(base.Refusal):
            probe.Measurement.guard(m)

    def test_user_guard_precedes_every_live_operation(self):
        with patch.object(probe.sys, "platform", "darwin"), \
                patch.object(base.pwd, "getpwuid", return_value=SimpleNamespace(pw_name="ordinary-user")), \
                patch.object(base, "music") as music, patch.object(base, "verify_bundle") as verify:
            for dry in (False, True):
                with self.assertRaises(base.Refusal):
                    probe.execute(self.bundle, "small-existing", dry)
            music.assert_not_called()
            verify.assert_not_called()

    def test_four_orders_have_distinct_expected_lists(self):
        expected = {"scale-release": list(range(1, 21)), "artist": [2, 4, 1, 3],
                    "artist-desc": [3, 1, 4, 2], "artist-release": [4, 2, 3, 1]}
        for name, numbers in expected.items():
            spec = probe.case_spec(name)
            self.assertEqual(spec["addition"], numbers)
            self.assertEqual(spec["display"], numbers[::-1])
        self.assertEqual(sum(len(probe.relatives(probe.case_spec(n))) for n in probe.CASE_NAMES[1:]), 324)

    def test_dates_are_diagnostics_with_cross_album_tie_evidence(self):
        rows = [{"artist": "a", "album": album, "added": date} for album, date in
                (("one", "8.45559632E+8"), ("two", "8.45559632E+8"), ("three", "8.45559633E+8"))]
        result = probe.date_diagnostics(rows)
        self.assertEqual(result["span_seconds"], 1)
        self.assertFalse(result["equal"])
        self.assertEqual(result["cross_album_ties"], 1)
        self.assertEqual(probe.display_answer([3, 2, 1], "1")["status"], "PASS")

    def test_display_difference_records_observation_without_inventing_success(self):
        result = probe.display_answer([3, 2, 1], "2", "02 03 01")
        self.assertEqual(result, {"status": "FAIL", "expected": [3, 2, 1], "observed": [2, 3, 1]})
        self.assertEqual(probe.display_answer([3, 2, 1], "2", "3 3 1")["observed"], [3, 3, 1])

    def test_missing_observation_is_unverified(self):
        self.assertEqual(probe.display_answer([3, 2, 1], "3")["status"], "UNVERIFIED")

    def test_invalid_or_private_input_is_refused(self):
        for answer, observed in (("EXPECTED", ""), ("2", "private path"), ("2", "99"), ("2", "3 2 1")):
            with self.subTest(answer=answer, observed=observed), self.assertRaises(base.Refusal):
                probe.display_answer([3, 2, 1], answer, observed)

    def test_unknown_cannot_disguise_observed_failure(self):
        self.assertEqual(probe.display_answer([3, 2, 1], "2", "UNKNOWN")["status"], "FAIL")

    def test_registration_comparison_normalizes_numeric_representation_only(self):
        row = dict(id="0" * 16, title="a", album="a", artist="a", path="a", added="8.45559632E+8")
        self.assertEqual(probe.stable([row]), probe.stable([dict(row, added="845559632")]))
        self.assertNotEqual(probe.stable([row]), probe.stable([dict(row, added="845559633")]))

    def test_inventory_refuses_wrong_artist_path_duplicate_or_id(self):
        rel = probe.relatives(probe.case_spec("artist"))[0]
        path = self.home / rel
        row = dict(id="A" * 16, title=Path(rel).stem[3:], album=Path(rel).parts[-2],
                   artist=Path(rel).parts[-3], path=str(path), added="845559632")
        probe.inventory([row], {rel: path}, [row["id"]])
        for changed in (dict(row, artist="different"), dict(row, path="different"), dict(row, path_error="-1700"),
                        dict(row, id="bad"), dict(row, added="NaN")):
            with self.assertRaises(base.Refusal):
                probe.inventory([changed], {rel: path}, [row["id"]])
        with self.assertRaises(base.Refusal):
            probe.inventory([row, row], {rel: path})

    def test_preparation_dry_run_never_creates_or_calls_external_tools(self):
        with patch.object(base, "run") as run, contextlib.redirect_stdout(io.StringIO()):
            probe.prepare(self.home / "new", Path("unused"), Path("unused"), Path("unused"), "a" * 40, True)
        run.assert_not_called()
        self.assertFalse((self.home / "new").exists())

    def test_bundle_manifest_cannot_add_a_traversal_path(self):
        manifest = {"format": probe.FORMAT, "commit": "a" * 40,
                    "cases": {n: probe.case_spec(n) for n in probe.CASE_NAMES}, "files": {"../outside": "x"}}
        (self.bundle / "manifest.json").write_text(json.dumps(manifest))
        with self.assertRaises(base.Refusal):
            probe.verify_bundle(self.bundle)

    def test_a_prior_stop_cannot_be_bypassed(self):
        work = self.bundle / "reference-private/small-existing"
        work.mkdir(parents=True)
        path = work / "result.json"
        for result in ({"case": "small-existing", "commit": "a" * 40, "state": "STOP", "phase": "relaunch"},
                       {"case": "small-existing", "commit": "b" * 40, "state": "PASS", "phase": "complete"}):
            path.write_text(json.dumps(result))
            with self.assertRaises(base.Refusal):
                probe.check_progress(self.bundle, "scale-release", "a" * 40)
        path.write_text(json.dumps({"case": "small-existing", "commit": "a" * 40,
                                    "state": "FAIL", "phase": "complete"}))
        probe.check_progress(self.bundle, "scale-release", "a" * 40)


class SimulatedRunTests(TestWorkspace):
    """The substitute preserves file bytes and timestamps except deliberate edits.

    It does not measure actual Music, GUI state, or physical backup behavior.
    """
    def setup_case(self, name="artist", media_name="Media"):
        self.name = name
        self.spec = probe.case_spec(name)
        self.media = self.home / "Music" / self.spec["library"] / media_name
        self.media.mkdir(parents=True)
        self.rows, self.mutations, self.running, self.next_id = [], [], True, 1
        self.source = self.bundle / name / "files"
        if name != "small-existing":
            for relative in probe.relatives(self.spec):
                file = self.source / relative
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(b"synthetic original")
        self.manifest = {"commit": "a" * 40}
        for prior in probe.CASE_NAMES[:probe.CASE_NAMES.index(name)]:
            path = self.bundle / "reference-private" / prior / "result.json"
            path.parent.mkdir(parents=True, exist_ok=True)
            if not path.exists():
                path.write_text(json.dumps({"case": prior, "commit": "a" * 40,
                                            "phase": "complete", "state": "PASS"}))

    def fake_snapshot(self):
        self.running = True
        return copy.deepcopy(self.rows)

    def fake_music(self, script, *args):
        if script == base.DELETE:
            self.mutations.append(("delete", args[0]))
            self.rows = [r for r in self.rows if r["id"] != args[0]]
        elif "to quit" in script:
            self.running = False
        elif "return version" in script:
            return "test-version"
        else:
            self.running = True
        return ""

    def fake_cli(self, measurement, *args):
        command = args[0]
        if "--dry-run" in args or command == "check":
            return
        if command == "apply":
            if "edited-catalog" in str(args[1]):
                for file in Path(args[2]).rglob("*.m4a"):
                    if not file.read_bytes().endswith(b" edited"):
                        old = file.stat()
                        file.write_bytes(file.read_bytes() + b" edited")
                        base.os.utime(file, ns=(old.st_atime_ns, old.st_mtime_ns))
            return
        self.assertEqual(command, "add")
        root = Path(args[1])
        journal = root / ".ilibrary-add.json"
        if journal.exists():
            return
        self.mutations.append(("add", str(root)))
        entries = []
        for number in self.spec["addition"]:
            album = next(a for a in self.spec["albums"] if a["number"] == number)
            sources, destinations, ids = [], [], []
            for relative in probe.relatives({"albums": [album]}):
                source = root / relative
                dest = self.media / "Music" / relative
                dest.parent.mkdir(parents=True, exist_ok=True)
                source.rename(dest)
                identifier = f"{self.next_id:016X}"
                self.next_id += 1
                ids.append(identifier)
                sources.append(str(source))
                destinations.append(str(dest))
                self.rows.append(dict(id=identifier, artist=album["artist"], album=album["album"],
                                      title=source.stem[3:], path=str(dest), added=str(845559632 + number // 3)))
            entries.append(dict(album=album["album"], albumArtist=album["artist"], sources=sources,
                                destinations=destinations, state="added", persistentIDs=ids))
        journal.write_text(json.dumps({"format": "ilibrary-add-journal-1", "entries": entries}))

    def fake_backup(self, work, paths):
        image = work / "synthetic-backup.dmg"
        image.write_bytes(b"simulated backup")
        return image, probe.digest(image), base.file_state(paths)

    def run_case(self, answers, *, override=None):
        output = io.StringIO()
        real_state = base.file_state
        def portable_states(paths):
            return {r: dict(s, created=None) for r, s in real_state(paths).items()}
        with contextlib.ExitStack() as stack:
            replacements = [
                (probe.sys, "platform", "darwin"), (base, "require_test_user", lambda: None),
                (base.pwd, "getpwuid", lambda uid: SimpleNamespace(pw_dir=str(self.home))),
                (probe, "verify_bundle", lambda bundle: self.manifest), (base, "check_account", lambda: None),
                (base, "media_directory", lambda home: self.media), (base, "music_running", lambda: self.running),
                (base, "snapshot", self.fake_snapshot), (base, "music", self.fake_music),
                (base, "make_backup", self.fake_backup), (base, "run", lambda argv: "test OS"),
                (base, "file_state", portable_states),
                (probe.Measurement, "cli", lambda measurement, *args: self.fake_cli(measurement, *args)),
            ]
            for obj, key, value in replacements:
                stack.enter_context(patch.object(obj, key, value))
            if override:
                override(stack)
            stack.enter_context(patch("builtins.input", side_effect=answers))
            stack.enter_context(contextlib.redirect_stdout(output))
            code = probe.execute(self.bundle, self.name)
        self.output = output.getvalue()
        self.result = json.loads((self.bundle / "reference-private" / self.name / "result.json").read_text())
        self.assertNotIn(str(self.home), self.output)
        for row in self.rows:
            self.assertNotIn(row["id"], self.output)
        return code

    def test_full_sequence_passes_with_timestamp_difference_and_two_display_observations(self):
        self.setup_case()
        self.assertEqual(self.run_case(["TEST", "1", "1", "1"]), 0)
        self.assertEqual(self.result["state"], "PASS")
        self.assertFalse(self.result["dates"]["equal"])
        self.assertEqual(len(self.result["observations"]), 2)
        self.assertEqual(sum(m[0] == "delete" for m in self.mutations), 8)
        self.assertEqual(sum(m[0] == "add" for m in self.mutations), 2)

    def test_localized_media_completes_fresh_cases_using_the_real_preference_parser(self):
        read_media = base.media_directory
        for name in probe.CASE_NAMES[1:]:
            with self.subTest(name=name):
                self.setup_case(name, "Media.localized")
                def override(stack):
                    stack.enter_context(patch.object(base, "media_directory", read_media))
                    stack.enter_context(patch.object(base, "run", side_effect=lambda args:
                        self.media.as_uri() + "/" if args[0].endswith("defaults") else "test OS"))
                self.assertEqual(self.run_case(["TEST", "1", "1", "1"], override=override), 0)
                self.assertEqual(self.result["state"], "PASS")
                self.assertIn("name: Media.localized", self.output)

    def test_all_fresh_order_modes_use_their_planned_journals(self):
        for name in ("scale-release", "artist-desc", "artist-release"):
            with self.subTest(name=name):
                self.setup_case(name)
                self.assertEqual(self.run_case(["TEST", "1", "1", "1"]), 0)
                self.assertEqual(self.result["state"], "PASS")

    def test_different_order_completes_with_failure_without_retrying_removal(self):
        self.setup_case()
        self.assertEqual(self.run_case(["TEST", "1", "2", "1 2 3 4", "1"]), 0)
        self.assertEqual(self.result["state"], "FAIL")
        self.assertEqual(sum(m[0] == "delete" for m in self.mutations), 8)

    def test_unknown_order_does_not_pass(self):
        self.setup_case()
        self.run_case(["TEST", "1", "3", "3"])
        self.assertEqual(self.result["state"], "UNVERIFIED")

    def test_empty_gui_refusal_prevents_quit_edit_and_readdition(self):
        self.setup_case()
        self.assertEqual(self.run_case(["TEST", "2"]), 1)
        self.assertEqual(self.result["phase"], "empty-gui")
        self.assertTrue(self.running)
        self.assertEqual(sum(m[0] == "add" for m in self.mutations), 1)
        self.assertEqual(len(list((self.bundle / "reference-private/artist/evacuated").rglob("*.m4a"))), 8)

    def test_wrong_selected_media_stops_before_music(self):
        self.setup_case()
        self.media = self.home / "Music" / "unrelated"
        self.assertEqual(self.run_case(["TEST"]), 1)
        self.assertEqual(self.mutations, [])

    def test_existing_registration_is_not_deleted(self):
        self.setup_case()
        self.rows = [{"id": "F" * 16}]
        self.assertEqual(self.run_case(["TEST"]), 1)
        self.assertEqual(self.mutations, [])

    def test_interrupt_produces_a_report_without_music_mutations(self):
        self.setup_case()
        self.assertEqual(self.run_case([KeyboardInterrupt()]), 1)
        self.assertIn("KeyboardInterrupt", self.output)
        self.assertEqual(self.mutations, [])

    def test_changed_backup_stops_before_any_registration_removal(self):
        self.setup_case()
        backup = self.fake_backup
        def corrupted(work, paths):
            image, checksum, states = backup(work, paths)
            image.write_bytes(b"changed")
            return image, checksum, states
        self.assertEqual(self.run_case(["TEST"], override=lambda stack: stack.enter_context(
            patch.object(base, "make_backup", corrupted))), 1)
        self.assertEqual(self.result["phase"], "registration-removal")
        self.assertFalse(any(m[0] == "delete" for m in self.mutations))

    def test_new_registration_during_removal_stops_before_second_delete(self):
        self.setup_case()
        snapshot = self.fake_snapshot
        def changed():
            rows = snapshot()
            if any(m[0] == "delete" for m in self.mutations):
                rows.append(dict(rows[0], id="F" * 16))
            return rows
        self.assertEqual(self.run_case(["TEST"], override=lambda stack: stack.enter_context(
            patch.object(base, "snapshot", changed))), 1)
        self.assertEqual(sum(m[0] == "delete" for m in self.mutations), 1)

    def test_unexpected_file_change_during_removal_stops_before_second_delete(self):
        self.setup_case()
        music = self.fake_music
        def changed(script, *args):
            result = music(script, *args)
            if script == base.DELETE:
                next((self.bundle / "reference-private/artist/evacuated").rglob("*.m4a")).write_bytes(b"unexpected")
            return result
        self.assertEqual(self.run_case(["TEST"], override=lambda stack: stack.enter_context(
            patch.object(base, "music", changed))), 1)
        self.assertEqual(sum(m[0] == "delete" for m in self.mutations), 1)

    def test_live_dry_run_never_queries_music_or_writes_a_result(self):
        self.setup_case()
        with patch.object(probe.sys, "platform", "darwin"), patch.object(base, "require_test_user"), \
                patch.object(base.pwd, "getpwuid", return_value=SimpleNamespace(pw_dir=str(self.home))), \
                patch.object(probe, "verify_bundle", return_value=self.manifest), \
                patch.object(base, "music") as music, patch.object(base, "media_directory") as media, \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(probe.execute(self.bundle, "artist", True), 0)
        self.assertFalse((self.bundle / "reference-private/artist").exists())
        music.assert_not_called()
        media.assert_not_called()

    def test_reuse_refuses_wrong_legacy_bundle_before_any_mutation(self):
        self.setup_case("small-existing")
        old = self.home / "ilibrary-m10-v2"
        old.mkdir()
        (old / "manifest.json").write_text("changed")
        self.assertEqual(self.run_case(["TEST"]), 1)
        self.assertEqual(self.mutations, [])

    def setup_legacy(self, media_name="Media"):
        self.setup_case("small-existing", media_name)
        old = self.home / "ilibrary-m10-v2"
        work = old / "reference-private/small"
        work.mkdir(parents=True)
        (work / "ilibrary-m10-results.txt").write_text("fixed legacy result")
        (work / "synthetic-backup.dmg").write_bytes(b"fixed backup image")
        backup = work / "restored-backup"
        staging = work / "evacuated"
        staging.mkdir()
        states, entries = {}, []
        for album in self.spec["albums"]:
            sources, destinations, ids = [], [], []
            for relative in probe.relatives({"albums": [album]}):
                short = str(Path(relative).relative_to(probe.ARTIST))
                original = backup / short
                original.parent.mkdir(parents=True, exist_ok=True)
                original.write_bytes(b"synthetic original")
                states[short] = dict(base.file_state({short: original})[short], created=None)
                dest = self.media / "Music" / relative
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(original, dest)
                info = dest.stat()
                dest.write_bytes(b"synthetic original edited")
                base.os.utime(dest, ns=(info.st_atime_ns, info.st_mtime_ns))
                identifier = f"{self.next_id:016X}"
                self.next_id += 1
                ids.append(identifier)
                sources.append(str(staging / short))
                destinations.append(str(dest))
                self.rows.append(dict(id=identifier, artist=probe.ARTIST, album=album["album"], title=dest.stem[3:],
                                      path=str(dest), added=str(845559632 + album["number"] // 3)))
            entries.append(dict(album=album["album"], albumArtist=probe.ARTIST, sources=sources,
                                destinations=destinations, state="added", persistentIDs=ids))
        (staging / ".ilibrary-add.json").write_text(json.dumps({"format": "ilibrary-add-journal-1", "entries": entries}))
        (work / "original-files.json").write_text(json.dumps(states))
        (work / "final-registration.json").write_text(json.dumps(self.rows))
        # Exercise the actual retained-bundle verifier, including both cases.
        manifest = {"format": base.FORMAT, "probeVersion": 2, "commit": probe.LEGACY_COMMIT,
                    "cases": {}, "files": {}}
        for name, (albums, tracks) in base.CASES.items():
            entries = []
            for a in range(1, albums + 1):
                for t in range(1, tracks + 1):
                    relative = f"{base.synthetic_album(a)}/{t:02d} M10 Song {t:02d}.m4a"
                    file = old / name / "files" / relative
                    file.parent.mkdir(parents=True, exist_ok=True)
                    file.write_bytes(b"synthetic original")
                    entries.append(relative)
            manifest["cases"][name] = {"albums": albums, "tracks": albums * tracks, "files": entries}
            for edited, filename in ((False, "catalog.json"), (True, "edited-catalog.json")):
                (old / name / filename).write_text(json.dumps(base.catalog(albums, tracks, edited)))
        for relative in ("bin/ilibrary", "rebuild_probe.py", "PROCEDURE.md"):
            file = old / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(b"synthetic test fixture; never executed")
        for file in old.rglob("*"):
            if file.is_file() and "reference-private" not in file.relative_to(old).parts:
                manifest["files"][str(file.relative_to(old))] = probe.digest(file)
        (old / "manifest.json").write_text(json.dumps(manifest))
        def native(argv):
            if argv[0].endswith("sw_vers"):
                return "test OS"
            if argv[0].endswith("ditto"):
                shutil.copytree(argv[1], argv[2], dirs_exist_ok=True)
            elif "attach" in argv:
                shutil.copytree(backup, argv[argv.index("-mountpoint") + 1], dirs_exist_ok=True)
            return ""
        def override(stack):
            stack.enter_context(patch.object(probe, "LEGACY_MANIFEST", probe.digest(old / "manifest.json")))
            stack.enter_context(patch.object(probe, "LEGACY_REPORT", probe.digest(work / "ilibrary-m10-results.txt")))
            stack.enter_context(patch.object(base, "run", native))
        return old, override

    def test_legacy_small_completes_without_repeating_addition_removal_or_editing_existing_files(self):
        old, override = self.setup_legacy()
        before = {str(p.relative_to(old)): probe.digest(p) for p in old.rglob("*") if p.is_file()}
        self.assertEqual(self.run_case(["TEST", "1", "1"], override=override), 0)
        self.assertEqual(self.result["state"], "PASS")
        self.assertEqual(self.mutations, [])
        self.assertEqual(before, {str(p.relative_to(old)): probe.digest(p) for p in old.rglob("*") if p.is_file()})

    def test_localized_legacy_reuse_preserves_records_and_uses_the_real_preference_parser(self):
        old, legacy_override = self.setup_legacy("Media.localized")
        (old / ".DS_Store").write_bytes(b"synthetic Finder state")
        before = {str(p.relative_to(old)): probe.digest(p) for p in old.rglob("*") if p.is_file()}
        read_media = base.media_directory
        def override(stack):
            legacy_override(stack)
            native = base.run
            stack.enter_context(patch.object(base, "media_directory", read_media))
            stack.enter_context(patch.object(base, "run", side_effect=lambda args:
                self.media.as_uri() + "/" if args[0].endswith("defaults") else native(args)))
        self.assertEqual(self.run_case(["TEST", "1", "1"], override=override), 0)
        self.assertEqual(self.result["state"], "PASS")
        self.assertEqual(self.mutations, [])
        self.assertEqual(before, {str(p.relative_to(old)): probe.digest(p) for p in old.rglob("*") if p.is_file()})

    def test_changed_existing_small_stops_before_backup_or_repetition(self):
        old, override = self.setup_legacy()
        self.rows[0]["id"] = "F" * 16
        self.assertEqual(self.run_case(["TEST"], override=override), 1)
        self.assertEqual(self.result["phase"], "legacy-evidence")
        self.assertEqual(self.mutations, [])

    def test_missing_legacy_input_stops_without_observations_or_mutations(self):
        old, override = self.setup_legacy()
        (old / "small/catalog.json").unlink()
        self.assertEqual(self.run_case(["TEST"], override=override), 1)
        self.assertEqual(self.result["phase"], "legacy-evidence")
        self.assertEqual(self.mutations, [])
        self.assertEqual(self.result["observations"], [])

    def test_changed_legacy_input_still_fails_its_actual_hash_check(self):
        old, override = self.setup_legacy()
        (old / ".DS_Store").write_bytes(b"synthetic Finder state")
        (old / "small/catalog.json").write_bytes(b"changed")
        self.assertEqual(self.run_case(["TEST"], override=override), 1)
        self.assertEqual(self.result["phase"], "legacy-evidence")
        self.assertEqual(self.mutations, [])
        self.assertEqual(self.result["observations"], [])

    def test_unknown_legacy_order_is_recorded_without_repeating_deletion(self):
        old, override = self.setup_legacy()
        self.assertEqual(self.run_case(["TEST", "3", "3"], override=override), 0)
        self.assertEqual(self.result["state"], "UNVERIFIED")
        self.assertEqual(self.mutations, [])

    def test_report_combines_completed_failure_stop_and_unrun_cases_without_music(self):
        self.setup_case()
        self.run_case(["TEST", "1", "3", "3"])
        report = io.StringIO()
        with patch.object(probe, "verify_bundle", return_value=self.manifest), \
                patch.object(base, "music") as music, contextlib.redirect_stdout(report):
            probe.combined_report(self.bundle)
        music.assert_not_called()
        self.assertIn("case result: UNVERIFIED", report.getvalue())
        self.assertIn("NOT RUN", report.getvalue())
        self.assertIn("Synthetic display qualification: NOT COMPLETE", report.getvalue())

    def test_completed_journal_rejects_pending_state_and_extra_audio(self):
        self.setup_case()
        self.run_case(["TEST", "1", "1", "1"])
        staging = self.bundle / "reference-private/artist/evacuated"
        path = staging / ".ilibrary-add.json"
        data = json.loads(path.read_text())
        data["entries"][0]["state"] = "moving"
        path.write_text(json.dumps(data))
        paths = {r: self.media / "Music" / r for r in probe.relatives(self.spec)}
        with self.assertRaises(base.Refusal):
            probe.journal_check(path, self.spec, staging, paths, self.rows)
        data["entries"][0]["state"] = "added"
        path.write_text(json.dumps(data))
        (staging / "unselected.wav").write_bytes(b"retained")
        with self.assertRaises(base.Refusal):
            probe.journal_check(path, self.spec, staging, paths, self.rows)


if __name__ == "__main__":
    unittest.main()
