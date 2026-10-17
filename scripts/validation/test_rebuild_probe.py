"""Safety and result-classification tests; never send Apple Events."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("probe", Path(__file__).with_name("rebuild_probe.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ProbeTests(unittest.TestCase):
    def setUp(self):
        probe._diagnostic_work = None
        self.addCleanup(setattr, probe, "_diagnostic_work", None)
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.addCleanup(self.temp.cleanup)
        self.paths = {}
        self.records = []
        for number in (1, 2):
            relative = f"M10 Album 01/{number:02d} M10 Song {number:02d}.m4a"
            path = self.root / relative
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(b"original synthetic bytes" + bytes([number]))
            self.paths[relative] = path
            self.records.append({"id": f"{number:016X}", "title": f"M10 Song {number:02d}",
                                 "album": "M10 Album 01", "artist": probe.ARTIST,
                                 "path": str(path), "added": "100000"})
        self.image = self.root / "backup.dmg"
        self.image.write_bytes(b"detached synthetic backup")
        self.image_hash = probe.digest(self.image)
        self.states = probe.file_state(self.paths)

    def clear(self):
        probe.remove_seeded(self.records, self.paths, self.paths, self.states,
                            self.image, self.image_hash, self.root / "mount")

    def test_normal_user_is_refused_before_music(self):
        with patch.object(probe, "music") as music, patch.object(probe.sys, "platform", "darwin"), \
                patch.object(probe.pwd, "getpwuid", return_value=SimpleNamespace(pw_name="ordinary-user")):
            with self.assertRaises(probe.Refusal):
                probe.execute(self.root, "small")
            music.assert_not_called()

    def test_environment_name_cannot_bypass_user_guard(self):
        with patch.dict(probe.os.environ, {"USER": "ilibrarytest", "LOGNAME": "ilibrarytest"}), \
                patch.object(probe.pwd, "getpwuid", return_value=SimpleNamespace(pw_name="ordinary-user")):
            with self.assertRaises(probe.Refusal):
                probe.require_test_user()

    def test_lookalike_user_is_refused(self):
        with self.assertRaises(probe.Refusal):
            probe.require_test_user("ordinary-ilibrarytest")

    def test_test_user_names_are_accepted(self):
        with patch.object(probe.os, "getuid", return_value=501):
            for name in ("ilibrarytest", "ilibrarytest2", "ilibrary-test-m10"):
                probe.require_test_user(name)

    def test_root_is_refused(self):
        with patch.object(probe.os, "getuid", return_value=0):
            with self.assertRaises(probe.Refusal):
                probe.require_test_user("ilibrarytest")

    def test_symlink_parent_is_refused(self):
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(probe.Refusal):
            probe.safe_path(alias / "new-file")

    def test_prepare_dry_run_creates_nothing(self):
        destination = self.root / "output"
        with contextlib.redirect_stdout(io.StringIO()), patch.object(probe, "run") as run:
            probe.prepare(destination, Path("unused"), Path("unused"), Path("unused"), "a" * 40, True)
            self.assertFalse(destination.exists())
            run.assert_not_called()

    def test_full_timestamp_equality_is_required(self):
        records = [{"added": "100000"}, {"added": "100001"}]
        self.assertEqual(probe.date_result(records), {"unique": 2, "span_seconds": 1, "equal": False})

    def test_equal_timestamps_pass(self):
        self.assertEqual(probe.date_result(self.records), {"unique": 1, "span_seconds": 0, "equal": True})

    def test_empty_timestamps_do_not_pass(self):
        with self.assertRaises(probe.Refusal):
            probe.date_result([])

    def test_unexpected_track_stops_before_removal(self):
        unexpected = dict(self.records[0], id="F" * 16)
        with patch.object(probe, "snapshot", return_value=self.records + [unexpected]), patch.object(probe, "music") as delete:
            with self.assertRaises(probe.Refusal):
                self.clear()
            delete.assert_not_called()

    def test_changed_identity_stops_before_removal(self):
        changed = [dict(self.records[0], id="F" * 16), self.records[1]]
        with patch.object(probe, "snapshot", return_value=changed), patch.object(probe, "music") as delete:
            with self.assertRaises(probe.Refusal):
                self.clear()
            delete.assert_not_called()

    def test_unexpected_location_stops_before_removal(self):
        changed = [dict(self.records[0], path=str(self.root / "unrelated.m4a")), self.records[1]]
        with patch.object(probe, "snapshot", return_value=changed), patch.object(probe, "music") as delete:
            with self.assertRaises(probe.Refusal):
                self.clear()
            delete.assert_not_called()

    def test_missing_evacuated_file_stops_before_removal(self):
        next(iter(self.paths.values())).unlink()
        with patch.object(probe, "snapshot", return_value=self.records), patch.object(probe, "music") as delete:
            with self.assertRaises(OSError):
                self.clear()
            delete.assert_not_called()

    def test_changed_backup_stops_before_removal(self):
        self.image.write_bytes(b"changed")
        with patch.object(probe, "snapshot", return_value=self.records), patch.object(probe, "music") as delete:
            with self.assertRaises(probe.Refusal):
                self.clear()
            delete.assert_not_called()

    def test_mounted_backup_stops_before_removal(self):
        with patch.object(probe, "snapshot", return_value=self.records), patch.object(probe.os.path, "ismount", return_value=True), \
                patch.object(probe, "music") as delete:
            with self.assertRaises(probe.Refusal):
                self.clear()
            delete.assert_not_called()

    def test_only_recorded_ids_are_removed_once(self):
        with patch.object(probe, "snapshot", side_effect=[self.records, self.records[1:], []]), \
                patch.object(probe, "music") as delete:
            self.clear()
            self.assertEqual([call.args[1] for call in delete.call_args_list], [r["id"] for r in self.records])
            probe.compare_files(self.paths, self.states)

    def test_registration_added_during_removal_stops_further_removal(self):
        unexpected = dict(self.records[0], id="F" * 16)
        with patch.object(probe, "snapshot", side_effect=[self.records, self.records[1:] + [unexpected]]), \
                patch.object(probe, "music") as delete:
            with self.assertRaises(probe.Refusal):
                self.clear()
            self.assertEqual(delete.call_count, 1)

    def test_deletion_that_changes_a_file_stops_further_removal(self):
        def destructive_adapter(*args):
            next(iter(self.paths.values())).write_bytes(b"unexpected change")
        with patch.object(probe, "snapshot", return_value=self.records), \
                patch.object(probe, "music", side_effect=destructive_adapter) as delete:
            with self.assertRaises(probe.Refusal):
                self.clear()
            self.assertEqual(delete.call_count, 1)
            self.assertEqual(probe.digest(self.image), self.image_hash)

    def test_command_preserves_trailing_field_and_record_separators(self):
        response = "fields" + chr(31) * 2 + chr(30) + "\n"
        with patch.object(probe.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout=response, stderr="")):
            self.assertEqual(probe.run(["synthetic-reader"]), response[:-1])

    def test_snapshot_retains_both_location_forms_and_empty_error_fields(self):
        fields = ["1" * 16, "M10 Song 01", "M10 Album 01", probe.ARTIST,
                  str(self.root / "planned.m4a"), "100", "", "-1700", ""]
        probe._diagnostic_work = self.root
        raw = chr(31).join(fields) + chr(30)
        with patch.object(probe, "music", return_value=raw):
            record = probe.snapshot()[0]
        self.assertEqual(record["path"], fields[4])
        self.assertEqual(record["legacy_path"], "")
        self.assertEqual(record["legacy_error"], "-1700")
        self.assertEqual(record["path_error"], "")
        self.assertEqual(json.loads((self.root / "diagnostics.jsonl").read_text())["value"], raw)

    def test_malformed_snapshot_is_saved_before_parser_refusal(self):
        probe._diagnostic_work = self.root
        with patch.object(probe, "music", return_value="malformed"):
            with self.assertRaises(probe.Refusal):
                probe.snapshot()
        self.assertEqual(json.loads((self.root / "diagnostics.jsonl").read_text())["value"], "malformed")

    def test_diagnostic_classification_does_not_weaken_the_path_guard(self):
        relative, path = next(iter(self.paths.items()))
        changed = dict(self.records[0], path=str(path.parent) + "/./" + path.name,
                       legacy_path="", legacy_error="-1700")
        result = probe.location_diagnostics([changed], {relative: path})
        self.assertIn("get.representation_only=1", result)
        self.assertIn("legacy.read_error=1", result)
        with self.assertRaises(probe.Refusal):
            probe.assert_inventory([changed], {relative: path})

    def test_location_read_error_cannot_pass_inventory_even_with_a_path(self):
        changed = [dict(self.records[0], path_error="-1700"), self.records[1]]
        with self.assertRaises(probe.Refusal):
            probe.assert_inventory(changed, self.paths)

    def test_registration_repetition_ignores_only_auxiliary_diagnostics(self):
        changed = [dict(r, legacy_error="-1700") for r in self.records]
        self.assertEqual(probe.stable_registration(changed), probe.stable_registration(self.records))
        changed[0]["added"] = "100001"
        self.assertNotEqual(probe.stable_registration(changed), probe.stable_registration(self.records))

    def test_initial_location_stop_saves_evidence_before_backup_or_removal(self):
        bundle = self.root / "bundle"
        media = self.root / "Music" / "Media"
        media.mkdir(parents=True)
        source = bundle / "small/files"
        for relative in self.paths:
            path = source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"synthetic source")
        manifest = {"probeVersion": 2, "commit": "a" * 40,
                    "cases": {"small": {"tracks": 2, "albums": 1, "files": list(self.paths)}}}
        command_result = SimpleNamespace(returncode=0, stdout="synthetic command complete", stderr="")
        output = io.StringIO()
        with patch.object(probe, "require_test_user"), patch.object(probe.sys, "platform", "darwin"), \
                patch.object(probe.pwd, "getpwuid", return_value=SimpleNamespace(pw_dir=str(self.root))), \
                patch.object(probe, "verify_bundle", return_value=manifest), \
                patch.object(probe, "check_account"), patch("builtins.input", return_value="TEST"), \
                patch.object(probe, "media_directory", return_value=media), \
                patch.object(probe, "snapshot", side_effect=[[], self.records]), \
                patch.object(probe, "run", return_value="test OS"), \
                patch.object(probe.subprocess, "run", return_value=command_result), \
                patch.object(probe, "make_backup") as backup, patch.object(probe, "music") as music, \
                contextlib.redirect_stdout(output):
            self.assertEqual(probe.execute(bundle, "small"), 1)
        backup.assert_not_called()
        music.assert_not_called()
        work = bundle / "reference-private/small"
        self.assertEqual(json.loads((work / "initial-registration.json").read_text()), self.records)
        self.assertIn("stopped phase: initial-location-check", output.getvalue())
        self.assertIn("get.different=2", output.getvalue())
        self.assertNotIn(str(self.root), output.getvalue())
        self.assertTrue((work / "diagnostics.jsonl").is_file())
        self.assertIsNone(probe._diagnostic_work)

    def test_combined_report_includes_a_stop_and_an_unrun_case_without_music(self):
        work = self.root / "reference-private/small"
        work.mkdir(parents=True)
        (work / "ilibrary-m10-results.txt").write_text("STOP: incomplete\n")
        output = io.StringIO()
        with patch.object(probe, "verify_bundle", return_value={"probeVersion": 2}), patch.object(probe, "music") as music, \
                contextlib.redirect_stdout(output):
            probe.combined_report(self.root)
        music.assert_not_called()
        self.assertIn("STOP: incomplete", output.getvalue())
        self.assertIn("NOT RUN", output.getvalue())

    def test_keyboard_interruption_is_a_reported_stop_without_music(self):
        bundle = self.root / "bundle"
        bundle.mkdir()
        manifest = {"probeVersion": 2, "commit": "a" * 40,
                    "cases": {"small": {"tracks": 6, "albums": 3, "files": []}}}
        output = io.StringIO()
        with patch.object(probe, "require_test_user"), patch.object(probe.sys, "platform", "darwin"), \
                patch.object(probe.pwd, "getpwuid", return_value=SimpleNamespace(pw_dir=str(self.root))), \
                patch.object(probe, "verify_bundle", return_value=manifest), \
                patch.object(probe, "check_account"), patch("builtins.input", side_effect=KeyboardInterrupt), \
                patch.object(probe, "run", return_value="test OS"), patch.object(probe, "music") as music, \
                contextlib.redirect_stdout(output):
            self.assertEqual(probe.execute(bundle, "small"), 1)
        music.assert_not_called()
        saved = (bundle / "reference-private/small/ilibrary-m10-results.txt").read_text()
        self.assertIn("stopped phase: preflight", saved)
        self.assertIn("reason: KeyboardInterrupt", saved)


if __name__ == "__main__":
    unittest.main()
