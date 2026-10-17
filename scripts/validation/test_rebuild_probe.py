"""Safety and result-classification tests; never send Apple Events."""

import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("probe", Path(__file__).with_name("rebuild_probe.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ProbeTests(unittest.TestCase):
    def setUp(self):
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
                patch.object(probe.getpass, "getuser", return_value="ordinary-user"):
            with self.assertRaises(probe.Refusal):
                probe.execute(self.root, "small")
            music.assert_not_called()

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


if __name__ == "__main__":
    unittest.main()
