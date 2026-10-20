import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path

import m11_collect as collect

HOME = "/Users/ilibrarytest"


def sha(data):
    return hashlib.sha256(data).hexdigest()


class RedactionTests(unittest.TestCase):
    def redact(self, text, homes=(HOME,)):
        return collect.redact(text, set(homes))

    def test_home_directory_becomes_tilde(self):
        self.assertEqual(self.redact(f"source {HOME}/Music/M11/Media"), "source ~/Music/M11/Media")
        self.assertEqual(self.redact(f"workspace: {HOME}"), "workspace: ~")
        self.assertEqual(self.redact(f'"path": "{HOME}/a b"'), '"path": "~/a b"')

    def test_resolved_home_and_json_escaped_slashes(self):
        resolved = "/private/var/users/ilibrarytest"
        self.assertEqual(self.redact(f"{resolved}/x {HOME}/y", {HOME, resolved}), "~/x ~/y")
        self.assertEqual(self.redact(r"\/Users\/ilibrarytest\/Music"), r"~\/Music")

    def test_other_users_and_longer_names_are_not_treated_as_home(self):
        self.assertEqual(self.redact("/Users/ilibrarytest2/Music"), "/Users/ilibrarytest2/Music")
        self.assertEqual(self.redact("/Users/Shared/report.txt"), "/Users/Shared/report.txt")

    def test_volume_prefix_becomes_backup(self):
        self.assertEqual(self.redact("backup /Volumes/My Drive/M11/Music/a.m4a"), "backup /Volumes/BACKUP/M11/Music/a.m4a")
        self.assertEqual(self.redact('"/Volumes/Secret"'), '"/Volumes/BACKUP"')
        self.assertEqual(self.redact(r"\/Volumes\/Secret\/Music"), r"\/Volumes\/BACKUP\/Music")
        self.assertEqual(self.redact("/Volumes/Secret"), "/Volumes/BACKUP")
        self.assertEqual(self.redact("/Volumes/Secret/\n/Volumes/Other"), "/Volumes/BACKUP/\n/Volumes/BACKUP")
        self.assertNotIn("Secret", self.redact("eject /Volumes/Secret now"))

    def test_persistent_ids_become_placeholder(self):
        text = "ids A1B2C3D4E5F60718 and 0123456789abcdef, \"id\": \"FEDCBA9876543210\""
        self.assertEqual(self.redact(text), 'ids <id> and <id>, "id": "<id>"')

    def test_other_hexadecimal_runs_are_kept(self):
        digest = sha(b"x")
        self.assertEqual(self.redact(f"sha {digest}"), f"sha {digest}")
        self.assertEqual(self.redact("0123456789abcdef0"), "0123456789abcdef0")
        self.assertEqual(self.redact("0123456789abcde"), "0123456789abcde")

    def test_redaction_is_idempotent(self):
        text = f"{HOME}/a /Volumes/X/b A1B2C3D4E5F60718"
        once = self.redact(text)
        self.assertEqual(self.redact(once), once)


class ReportTests(unittest.TestCase):
    def make_bundle(self, root, results):
        files = {"bin/ilibrary": b"binary", "staging/A/B/01 T.m4a": b"audio", "catalog.json": b"{}"}
        for relative, data in files.items():
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        manifest = {"format": collect.FORMAT, "commit": "a" * 40, "files": {r: sha(d) for r, d in files.items()}}
        (root / "manifest.json").write_text(json.dumps(manifest))
        (root / "results").mkdir()
        for name, text in results.items():
            (root / "results" / name).write_text(text)

    def test_report_starts_with_commit_and_redacts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "bundle"
            root.mkdir()
            self.make_bundle(root, {"add.log": f"added {HOME}/Music/x A1B2C3D4E5F60718\n",
                                    "prepare.log": "backup /Volumes/Big Drive/M11\n"})
            text = collect.build_report(root, {HOME}, Path(directory) / "none")
            lines = text.splitlines()
            self.assertEqual(lines[0], "source commit: " + "a" * 40)
            self.assertIn("bundle SHA-256 check: PASS (3 files verified; 0 staging files absent", text)
            self.assertIn("added ~/Music/x <id>", text)
            self.assertIn("backup /Volumes/BACKUP/M11", text)
            self.assertNotIn("Big Drive", text)
            self.assertIn("== results/doctor.log ==\nNOT RUN", text)

    def test_moved_staging_is_expected_but_changed_binary_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "bundle"
            root.mkdir()
            self.make_bundle(root, {})
            (root / "staging/A/B/01 T.m4a").unlink()
            self.assertIn("PASS (2 files verified; 1 staging files absent", collect.build_report(root, {HOME}, root))
            (root / "bin/ilibrary").write_bytes(b"changed")
            self.assertIn("FAIL (differs: bin/ilibrary)", collect.build_report(root, {HOME}, root))

    def test_check_mode_requires_staging(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "bundle"
            root.mkdir()
            self.make_bundle(root, {})
            collect.main(["--check"], bundle=root)
            (root / "staging/A/B/01 T.m4a").unlink()
            with self.assertRaises(SystemExit):
                collect.main(["--check"], bundle=root)

    def test_refuses_to_overwrite_and_writes_only_the_report(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / "bundle"
            root.mkdir()
            self.make_bundle(root, {"add.log": "ok\n"})
            report = base / "out" / "report.txt"
            report.parent.mkdir()
            before = sorted(str(p) for p in base.rglob("*"))
            collect.main([str(report)], bundle=root)
            after = sorted(str(p) for p in base.rglob("*"))
            self.assertEqual(sorted(set(after) - set(before)), [str(report)])
            self.assertTrue(report.read_text().startswith("source commit: "))
            with self.assertRaises(SystemExit):
                collect.main([str(report)], bundle=root)
            link = base / "out" / "link.txt"
            os.symlink(base / "elsewhere", link)
            with self.assertRaises(SystemExit):
                collect.main([str(link)], bundle=root)
            self.assertFalse((base / "elsewhere").exists())


if __name__ == "__main__":
    unittest.main()
