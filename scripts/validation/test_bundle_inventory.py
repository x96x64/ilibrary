"""File-only tests for the retained-bundle diagnostic handoff."""

import contextlib
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import inspect_rebuild_bundle as probe


class BundleInventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / "bundle"
        self.root.mkdir()
        (self.root / "fixture.txt").write_text("synthetic fixture")
        (self.root / "manifest.json").write_text(json.dumps({
            "files": {"fixture.txt": probe.sha256(self.root / "fixture.txt")}}))
        self.checksum = probe.sha256(self.root / "manifest.json")

    def inspect(self):
        return probe.inspect_bundle(self.root, self.checksum)

    def test_matching_files_remain_unchanged(self):
        before = {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.root.iterdir()}
        result = self.inspect()
        self.assertTrue(result["file_list_matches"])
        self.assertEqual(result["content_mismatches"], [])
        self.assertEqual(before, {p.name: (p.read_bytes(), p.stat().st_mtime_ns) for p in self.root.iterdir()})

    def test_additional_files_are_identified_without_reading_or_deleting_them(self):
        for name in (".DS_Store", "unrecognized.txt"):
            (self.root / name).write_text("do not disclose these contents")
        with patch.object(probe, "sha256", wraps=probe.sha256) as hashes:
            result = self.inspect()
        self.assertEqual(result["extra"], [".DS_Store", "unrecognized.txt"])
        self.assertFalse(result["file_list_matches"])
        self.assertNotIn("do not disclose", json.dumps(result))
        self.assertEqual({call.args[0].name for call in hashes.call_args_list}, {"manifest.json", "fixture.txt"})
        self.assertTrue((self.root / "unrecognized.txt").exists())

    def test_missing_and_changed_files_are_distinguished(self):
        (self.root / "fixture.txt").write_text("changed")
        self.assertEqual(self.inspect()["content_mismatches"], ["fixture.txt"])
        (self.root / "fixture.txt").unlink()
        result = self.inspect()
        self.assertEqual(result["missing"], ["fixture.txt"])
        self.assertEqual(result["content_mismatches"], [])

    def test_links_are_not_followed(self):
        outside = self.root.parent / "outside"
        outside.mkdir()
        (outside / "secret").write_text("private")
        (self.root / "linked-dir").symlink_to(outside)
        (self.root / "fixture.txt").unlink()
        (self.root / "fixture.txt").symlink_to(outside / "secret")
        result = self.inspect()
        self.assertEqual(result["non_regular"], ["fixture.txt", "linked-dir"])
        self.assertEqual(result["extra"], [])
        self.assertNotIn("secret", json.dumps(result))
        self.assertFalse(result["file_list_matches"])

    def test_private_records_are_not_traversed(self):
        private = self.root / "reference-private"
        private.mkdir()
        (private / "record.json").write_text("private")
        result = self.inspect()
        self.assertTrue(result["file_list_matches"])
        self.assertEqual(result["regular_files"], 2)

    def test_unknown_manifest_stops_before_scanning(self):
        with patch.object(probe.os, "walk") as walk:
            result = probe.inspect_bundle(self.root, "0" * 64)
        walk.assert_not_called()
        self.assertFalse(result["manifest_matches"])
        self.assertIsNone(result["file_list_matches"])

    def test_private_report_is_verified_and_never_overwritten(self):
        destination = self.root.parent / "reference-private" / "inventory.json"
        result = self.inspect()
        probe.save_report(result, destination)
        self.assertEqual(destination.stat().st_mode & 0o777, 0o644)
        with self.assertRaises(FileExistsError):
            probe.save_report({"changed": True}, destination)
        self.assertEqual(json.loads(destination.read_text()), result)

    def test_normal_user_is_refused_without_inspection_or_output_file(self):
        with patch.object(probe.pwd, "getpwuid", return_value=SimpleNamespace(pw_name="normal")), \
                patch.object(probe, "inspect_bundle") as inspect, \
                patch.object(probe, "save_report") as save, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(probe.main([]), 1)
        inspect.assert_not_called()
        save.assert_not_called()

    def test_dry_run_does_not_inspect_or_write(self):
        with patch.object(probe.pwd, "getpwuid", return_value=SimpleNamespace(pw_name="ilibrarytest")), \
                patch.object(probe.os, "getuid", return_value=501), \
                patch.object(probe, "DESTINATION", self.root.parent / "unused.json"), \
                patch.object(probe, "inspect_bundle") as inspect, \
                patch.object(probe, "save_report") as save, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(probe.main(["--dry-run"]), 0)
        inspect.assert_not_called()
        save.assert_not_called()


if __name__ == "__main__":
    unittest.main()
