"""Exercise publication refusals without contacting GitHub or a registry."""

import contextlib
import io
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path
import tarfile
import unittest
from unittest.mock import patch

import check_release
import release_notes
import repackage
from verify import historical_package_readme, tar_files


class NewReleaseTests(unittest.TestCase):
    commit = "c" * 40

    def tree(self, temporary, version="1.2.3",
             changelog="## [1.2.3] - 1958-08-29\n\n### Added\n\n- **Example Capability:** A change.\n"):
        root = Path(temporary)
        (root / "Sources/ilibrary").mkdir(parents=True)
        (root / "Sources/ilibrary/CommandLineInterface.swift").write_text(f'let version = "{version}"\n')
        (root / "CHANGELOG.md").write_text("# Changelog\n\n## [Unreleased]\n\n" + changelog + "\n## [1.2.2] - 1958-08-28\n\n- Older.\n")
        return root

    def test_a_new_release_of_an_integrated_versioned_commit_is_accepted(self):
        with tempfile.TemporaryDirectory() as temporary, \
                patch.object(check_release, "exists", return_value=False), \
                patch.object(check_release, "api", return_value={"status": "identical"}), \
                contextlib.redirect_stdout(io.StringIO()):
            check_release.check_new("v1.2.3", self.commit, self.tree(temporary))

    def test_an_existing_tag_or_release_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as temporary, \
                patch.object(check_release, "exists", return_value=True), \
                patch.object(check_release, "api", return_value={"status": "identical"}):
            with self.assertRaises(SystemExit):
                check_release.check_new("v1.2.3", self.commit, self.tree(temporary))

    def test_a_mismatched_version_or_undated_changelog_is_refused(self):
        for version, changelog in [("1.2.4", "## [1.2.3] - 1958-08-29\n\n- A change.\n"),
                                   ("1.2.3", "## [1.2.3]\n\n- A change.\n")]:
            with tempfile.TemporaryDirectory() as temporary, \
                    patch.object(check_release, "exists", return_value=False) as exists:
                with self.assertRaises(SystemExit):
                    check_release.check_new("v1.2.3", self.commit, self.tree(temporary, version, changelog))
                exists.assert_not_called()

    def test_release_notes_carry_the_version_section_only(self):
        with tempfile.TemporaryDirectory() as temporary:
            text = release_notes.notes("1.2.3", self.tree(temporary))
        self.assertIn("## Highlights\n\n- **Example Capability:** A change.\n", text)
        self.assertNotIn("Older.", text)
        self.assertIn("@x96_64/ilibrary@1.2.3", text)
        self.assertIn("blob/v1.2.3/CHANGELOG.md", text)
        self.assertEqual(release_notes.check(text, "1.2.3"), [])
        self.assertEqual(release_notes.TITLE.format(version="1.2.3"),
                         "iLibrary: v1.2.3, Catalog-Driven Music Libraries for Apple Music on macOS")

    def test_release_notes_keep_the_section_order(self):
        with tempfile.TemporaryDirectory() as temporary:
            text = release_notes.notes("1.2.3", self.tree(temporary))
        markers = ["> [!IMPORTANT]", "## Highlights", "- **Example Capability:**", "Verification consists",
                   "## Installing and Upgrading", "See the [changelog]"]
        positions = [text.index(marker) for marker in markers]
        self.assertEqual(positions, sorted(positions))
        self.assertGreater(positions[0], 0)
        self.assertNotRegex(text, r"\*\*[^*\n]+\.\*\*")

    def test_release_notes_require_a_section(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(SystemExit):
                release_notes.notes("9.9.9", self.tree(temporary))

    def test_release_notes_refuse_unlabeled_or_generic_entries(self):
        for entry in ["- A change.", "- **Fixed:** A change.", "- **Example Capability.** A change.",
                      "- **example capability:** A change.", "- **Example Capability**: A change."]:
            changelog = f"## [1.2.3] - 1958-08-29\n\n### Added\n\n{entry}\n"
            with self.subTest(entry=entry), tempfile.TemporaryDirectory() as temporary:
                with self.assertRaises(SystemExit):
                    release_notes.notes("1.2.3", self.tree(temporary, changelog=changelog))

    def test_release_notes_refuse_text_outside_entries(self):
        changelog = "## [1.2.3] - 1958-08-29\n\nA loose sentence.\n\n- **Example Capability:** A change.\n"
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(SystemExit):
                release_notes.notes("1.2.3", self.tree(temporary, changelog=changelog))


class ReleaseBodyCheckTests(unittest.TestCase):
    def body(self):
        with tempfile.TemporaryDirectory() as temporary:
            return release_notes.notes("1.2.3", NewReleaseTests.tree(None, temporary))

    def test_a_generated_body_conforms(self):
        self.assertEqual(release_notes.check(self.body(), "1.2.3"), [])

    def test_departures_from_the_layout_are_reported(self):
        body = self.body()
        cases = {
            "period label": body.replace("**Example Capability:**", "**Example Capability.**"),
            "generic label": body.replace("**Example Capability:**", "**Changed:**"),
            "missing notice": body.replace("> [!IMPORTANT]\n", ""),
            "extra heading": body.replace("## Highlights", "## Highlights\n\n### Added"),
            "reordered sections": body.replace("## Highlights", "## Installing").replace(
                "## Installing and Upgrading", "## Highlights").replace("## Installing\n", "## Installing and Upgrading\n"),
            "other version": body.replace("@x96_64/ilibrary@1.2.3", "@x96_64/ilibrary@1.2.2"),
            "changed closing": body.replace("for the complete change record", "for details"),
            "no verification paragraph": body.replace("Verification consists", "- **Other Capability:** Verification"),
        }
        for name, text in cases.items():
            with self.subTest(case=name):
                self.assertNotEqual(release_notes.check(text, "1.2.3"), [])

    def test_the_command_checks_a_body_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "body.md"
            path.write_text(self.body())
            release_notes.main(["--check", "1.2.3", str(path)])
            path.write_text(self.body().replace("**Example Capability:**", "**Example Capability.**"))
            with self.assertRaises(SystemExit):
                release_notes.main(["--check", "1.2.3", str(path)])
            with self.assertRaises(SystemExit):
                release_notes.main(["1.2"])


class ReleaseGuardTests(unittest.TestCase):
    commit = "a" * 40

    def test_corrected_readme_uses_the_recorded_commit(self):
        with tempfile.TemporaryDirectory(prefix='ilibrary-readme-history-') as temporary:
            root = Path(temporary)
            environment = dict(os.environ, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)

            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, env=environment)

            git('init', '-q')
            (root / 'packaging').mkdir()
            readme = root / 'packaging/README.md'
            readme.write_bytes(b'recorded description')
            git('add', 'packaging/README.md')
            git('-c', 'user.name=Synthetic Fixture', '-c', 'user.email=fixture@example.invalid',
                '-c', 'commit.gpgsign=false', 'commit', '-qm', 'record synthetic description')
            commit = git('rev-parse', 'HEAD').decode().strip()
            readme.write_bytes(b'later documentation')
            self.assertEqual(historical_package_readme(commit, root), b'recorded description')

    def test_invalid_packaging_commit_runs_no_git_command(self):
        with patch('verify.subprocess.check_output') as read:
            with self.assertRaises(ValueError):
                historical_package_readme('main:README.md')
            read.assert_not_called()

    def response(self, path):
        return {
            "commits/v0.1.0": {"sha": self.commit},
            f"compare/{self.commit}...main": {"status": "ahead"},
            "releases/tags/v0.1.0": {"draft": False, "prerelease": True, "tag_name": "v0.1.0"},
        }[path]

    def test_integrated_experimental_release_is_accepted(self):
        with patch.object(check_release, "api", side_effect=self.response), contextlib.redirect_stdout(io.StringIO()):
            check_release.main("v0.1.0", self.commit)

    def test_regular_experimental_release_is_accepted(self):
        def response(path):
            result = self.response(path)
            if path.startswith("releases/"):
                result["prerelease"] = False
            return result
        with patch.object(check_release, "api", side_effect=response), contextlib.redirect_stdout(io.StringIO()):
            check_release.main("v0.1.0", self.commit)

    def test_invalid_identifiers_make_no_request(self):
        with patch.object(check_release, "api") as api:
            for tag, commit in [("v1.0", self.commit), ("v0.1.0;bad", self.commit), ("v0.1.0", "main")]:
                with self.assertRaises(SystemExit):
                    check_release.main(tag, commit)
            api.assert_not_called()

    def test_moved_tag_is_refused(self):
        with patch.object(check_release, "api", return_value={"sha": "b" * 40}):
            with self.assertRaises(SystemExit):
                check_release.main("v0.1.0", self.commit)

    def test_unintegrated_commit_is_refused(self):
        with patch.object(check_release, "api", side_effect=[{"sha": self.commit}, {"status": "diverged"}]):
            with self.assertRaises(SystemExit):
                check_release.main("v0.1.0", self.commit)

    def test_draft_release_is_refused(self):
        for prerelease in (True, False):
            with patch.object(check_release, "api", side_effect=[
                {"sha": self.commit}, {"status": "identical"},
                {"draft": True, "prerelease": prerelease, "tag_name": "v0.1.0"},
            ]):
                with self.assertRaises(SystemExit):
                    check_release.main("v0.1.0", self.commit)

    def test_other_release_tag_is_refused(self):
        for prerelease in (True, False):
            with patch.object(check_release, "api", side_effect=[
                {"sha": self.commit}, {"status": "identical"},
                {"draft": False, "prerelease": prerelease, "tag_name": "v0.2.0"},
            ]):
                with self.assertRaises(SystemExit):
                    check_release.main("v0.1.0", self.commit)

    def test_archive_traversal_and_links_are_refused(self):
        for name, kind in [("../escape", tarfile.REGTYPE), ("/absolute", tarfile.REGTYPE), ("link", tarfile.SYMTYPE)]:
            with tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "test.tar"
                with tarfile.open(path, "w") as archive:
                    item = tarfile.TarInfo(name)
                    item.type = kind
                    item.linkname = "target" if kind == tarfile.SYMTYPE else ""
                    archive.addfile(item, io.BytesIO())
                with self.assertRaises(ValueError):
                    tar_files(path)

    def test_metadata_correction_refuses_changed_originals(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            files = {"build-info.json": json.dumps({"version": "0.1.0"}).encode()}
            files.update({f"asset-{index}": bytes([index]) for index in range(5)})
            for name, content in files.items():
                (directory / name).write_bytes(content)
            manifest = "".join(f"{hashlib.sha256(content).hexdigest()}  {name}\n"
                               for name, content in files.items()).encode()
            (directory / "SHA256SUMS").write_bytes(manifest)
            reviewed = hashlib.sha256(manifest).hexdigest()
            self.assertEqual(repackage.reviewed_files(directory, reviewed), {"version": "0.1.0"})
            (directory / "asset-0").write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "Original checksum mismatch"):
                repackage.reviewed_files(directory, reviewed)
            with self.assertRaisesRegex(ValueError, "not the reviewed manifest"):
                repackage.reviewed_files(directory, "0" * 64)

    def test_metadata_correction_refuses_manifest_traversal(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = "".join(f"{'0' * 64}  ../asset-{index}\n" for index in range(6)).encode()
            (directory / "SHA256SUMS").write_bytes(manifest)
            with self.assertRaisesRegex(ValueError, "Unsafe original manifest entry"):
                repackage.reviewed_files(directory, hashlib.sha256(manifest).hexdigest())

    def test_npm_publishes_the_downloaded_file(self):
        # npm reads an unprefixed "dist/NAME.tgz" as the GitHub repository shorthand "dist/NAME.tgz".
        workflow = (Path(__file__).resolve().parent.parent / ".github/workflows/release.yml").read_text()
        commands = [line.strip() for line in workflow.splitlines() if line.strip().startswith("npm publish ")]
        self.assertEqual(len(commands), 1)
        self.assertTrue(commands[0].startswith('npm publish "./dist/'), commands[0])


if __name__ == "__main__":
    unittest.main()
