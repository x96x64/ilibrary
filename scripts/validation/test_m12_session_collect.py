"""Tests of the M12 session collector with synthetic records, a synthetic executable, and temporary directories
in place of /Users/Shared and the test user's home. Nothing here reads real qualification evidence."""

import hashlib
import os
import plistlib
import shutil
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import m12_session_collect as collect

EXECUTABLE = b"synthetic GUIProbeMac\n"
EXECUTABLE_SHA = "421d23c473af8f4abc86d8f0f293419848f6c55511fdaca4cfde0acafafce33b"
SONGS = b'{"synthetic": "songs"}\n'
SONGS_SHA = "9b9106574289a3e78450413500416968059cf3324cfcadc86bb4dfca46dbc38d"
RECENT = b'{"synthetic": "recently added"}\n'
RECENT_SHA = "701d3b4d34ebd585b9dfd043f8a40f980196f0018742f04b854a3913f49a4fe2"

COMPLETE_SUMMARY = f"""format=ilibrary-m12-session-summary-1
guide=M12-S2S5-ENUI-v4
phase=prepared-in-test-user-before-logout
return=not-yet-performed
prepared-date=2026-10-24
executable-sha256={EXECUTABLE_SHA}
survey-portion=passed-78-of-78
revocation=passed-2-of-2
cloud-option=unavailable
export=passed
export-checks-passed=5
usable-records=both
songs-1-sha256={SONGS_SHA}
recently-added-1-sha256={RECENT_SHA}
"""

COMPLETE_REPORT = f"""M12 STAGES 2-5: ALL 90 CHECKS PASSED
GUIDE: M12-S2S5-ENUI-v4
REPORT FORMAT: ilibrary-m12-session-report-1
DATE: 2026-10-24
SUMMARY PREPARED IN TEST USER ON: 2026-10-24
MACOS (READ BY THE COLLECTOR IN THE PERSONAL ACCOUNT): 27.0.1 (26A434)
EXECUTABLE SHA-256 MEASURED IN TEST USER: {EXECUTABLE_SHA}
SURVEY PORTION, S0-1 TO S5-19: 78/78 PASSED (OPERATOR ATTESTED)
ACCESSIBILITY REVOCATION, R-1 AND R-2: 2/2 PASSED (OPERATOR ATTESTED)
EVIDENCE EXPORT, R-3 TO R-7: 5/5 PASSED (OPERATOR ATTESTED)
RETURN, R-8 TO R-12: 5/5 PASSED (OPERATOR CONFIRMED IN THE PERSONAL ACCOUNT)
REQUIRED CHECKS PASSED: 90/90
CLOUD LIBRARY OPTION: unavailable (OPERATOR OBSERVED; NOT AN OBSERVED DISABLED SETTING)
EXPORTED RECORDS IN /Users/Shared/ilibrary-m12-survey-records-v4: both records
EXPORTED RECORD SHA-256 (EQUAL TO ITS ORIGINAL; CHECKED AGAIN AT REPORT TIME): songs-1.json {SONGS_SHA}
EXPORTED RECORD SHA-256 (EQUAL TO ITS ORIGINAL; CHECKED AGAIN AT REPORT TIME): recently-added-1.json {RECENT_SHA}
GUI EMPTINESS: NOT QUALIFIED (structural survey only)
COLLECTOR SCOPE: the collector measured the executable digest and compared the exported copies; it did not observe Music, Accessibility, Terminal, or the logout, which rest on the operator's attestations
"""

EXPORT_FAILURE_REPORT = f"""M12 STAGES 2-5: SURVEY, REVOCATION, AND RETURN PASSED; EVIDENCE EXPORT FAILED
GUIDE: M12-S2S5-ENUI-v4
REPORT FORMAT: ilibrary-m12-session-report-1
DATE: 2026-10-24
SUMMARY PREPARED IN TEST USER ON: 2026-10-24
MACOS (READ BY THE COLLECTOR IN THE PERSONAL ACCOUNT): 27.0.1 (26A434)
EXECUTABLE SHA-256 MEASURED IN TEST USER: {EXECUTABLE_SHA}
SURVEY PORTION, S0-1 TO S5-19: 78/78 PASSED (OPERATOR ATTESTED)
ACCESSIBILITY REVOCATION, R-1 AND R-2: 2/2 PASSED (OPERATOR ATTESTED)
EVIDENCE EXPORT, R-3 TO R-7: FAILED AT R-7 (THE FIVE EXPORT CHECKS ARE COUNTED AS FAILED)
RETURN, R-8 TO R-12: 5/5 PASSED (OPERATOR CONFIRMED IN THE PERSONAL ACCOUNT)
REQUIRED CHECKS PASSED: 85/90
CLOUD LIBRARY OPTION: off (OPERATOR OBSERVED)
EXPORTED RECORDS IN /Users/Shared/ilibrary-m12-survey-records-v4: songs-1.json only
EXPORTED RECORD SHA-256 (EQUAL TO ITS ORIGINAL; CHECKED AGAIN AT REPORT TIME): songs-1.json {SONGS_SHA}
GUI EMPTINESS: NOT QUALIFIED (structural survey only)
COLLECTOR SCOPE: the collector measured the executable digest and compared the exported copies; it did not observe Music, Accessibility, Terminal, or the logout, which rest on the operator's attestations
"""


class Scenario:
    """A temporary layout: a shared directory, the test user's workspace, an export directory, and a system
    version file. All files are owned by the running user, who stands in for both accounts."""

    def __init__(self, root):
        self.root = Path(root)
        self.shared = self.root / "Shared"
        self.home = self.root / "home"
        self.workspace = self.home / "ilibrary-m12"
        self.export = self.shared / collect.EXPORT_DIRECTORY_NAME
        self.version = self.root / "SystemVersion.plist"
        for directory in (self.shared, self.workspace / "bin", self.workspace / "records"):
            directory.mkdir(parents=True)
        (self.workspace / "bin" / "GUIProbeMac").write_bytes(EXECUTABLE)
        (self.workspace / "records" / "songs-1.json").write_bytes(SONGS)
        (self.workspace / "records" / "recently-added-1.json").write_bytes(RECENT)
        for name in collect.RECORDS:
            os.chmod(self.workspace / "records" / name, 0o600)
        self.version.write_bytes(plistlib.dumps({"ProductVersion": "27.0.1", "ProductBuildVersion": "26A434"}))

    def export_records(self, names=collect.RECORDS):
        self.export.mkdir(mode=0o755)
        os.chmod(self.export, 0o755)
        for name in names:
            target = self.export / name
            shutil.copyfile(self.workspace / "records" / name, target)
            os.chmod(target, 0o644)

    def environment(self, answers, user=collect.TEST_USER):
        replies = iter(answers)

        def ask(prompt):
            try:
                return next(replies)
            except StopIteration:
                raise EOFError

        return collect.Environment(
            shared=self.shared, home=self.home, user=user, uid=os.getuid(),
            owner_name=lambda uid: collect.TEST_USER, system_version=self.version, ask=ask,
            today=lambda: "2026-10-24")

    def prepare(self, answers):
        return collect.prepare(self.environment(answers))

    def report(self, answers=("completed",)):
        return collect.report(self.environment(answers, user="maintainer"))

    def snapshot(self):
        result = {}
        for path in sorted(self.root.rglob("*")):
            if path.is_symlink():
                result[str(path)] = ("link", os.readlink(path))
            elif path.is_file():
                result[str(path)] = ("file", hashlib.sha256(path.read_bytes()).hexdigest(), stat.S_IMODE(path.stat().st_mode))
        return result


class CollectorTestCase(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.scenario = Scenario(self.directory.name)
        patcher = mock.patch.object(collect, "EXECUTABLE_SHA256", EXECUTABLE_SHA)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.directory.cleanup)

    def assertRefused(self, function, *arguments, message=None):
        before = self.scenario.snapshot()
        with self.assertRaises(collect.Refusal) as context:
            function(*arguments)
        self.assertFalse(context.exception.written)
        if message:
            self.assertIn(message, str(context.exception))
        self.assertEqual(self.scenario.snapshot(), before, "a refused step changed a file")
        self.assertEqual(list(self.scenario.shared.glob(".*partial")), [])

    def summary_text(self):
        return self.scenario.shared.joinpath(collect.SUMMARY_NAME).read_text()

    def report_text(self):
        return self.scenario.shared.joinpath(collect.REPORT_NAME).read_text()


class PrepareTests(CollectorTestCase):
    def test_a_complete_session_writes_the_exact_summary(self):
        self.scenario.export_records()
        digest = self.scenario.prepare(["passed", "passed", "unavailable", "passed"])
        self.assertEqual(self.summary_text(), COMPLETE_SUMMARY)
        self.assertEqual(digest, hashlib.sha256(COMPLETE_SUMMARY.encode()).hexdigest())
        mode = stat.S_IMODE(os.lstat(self.scenario.shared / collect.SUMMARY_NAME).st_mode)
        self.assertEqual(mode, 0o644)

    def test_every_export_failure_point_is_recorded_with_no_usable_record_before_r7(self):
        for check in ("R-3", "R-4", "R-5", "R-6"):
            with self.subTest(check=check):
                self.setUp()
                if check == "R-6":
                    self.scenario.export_records()
                self.scenario.prepare(["passed", "passed", "off", check])
                text = self.summary_text()
                self.assertIn(f"export=failed-at-{check}\n", text)
                self.assertIn("export-checks-passed=0\nusable-records=none\nsongs-1-sha256=none\n", text)

    def test_a_failure_at_r7_lists_only_the_copies_that_compare_equal(self):
        cases = [
            ((), "none"),
            (("songs-1.json",), "songs-1.json"),
            (("recently-added-1.json",), "recently-added-1.json"),
            (collect.RECORDS, "both"),
        ]
        for names, usable in cases:
            with self.subTest(names=names):
                self.setUp()
                self.scenario.export_records(collect.RECORDS)
                for name in collect.RECORDS:
                    if name not in names:
                        (self.scenario.export / name).write_bytes(b"different\n")
                self.scenario.prepare(["passed", "passed", "off", "R-7"])
                self.assertIn(f"usable-records={usable}\n", self.summary_text())

    def test_a_passed_export_requires_both_equal_copies(self):
        self.scenario.export_records(("songs-1.json",))
        self.assertRefused(self.scenario.prepare, ["passed", "passed", "unavailable", "passed"],
                           message="not every exported copy equals its original")

    def test_a_copy_with_another_mode_or_a_link_is_not_usable(self):
        self.scenario.export_records()
        os.chmod(self.scenario.export / "songs-1.json", 0o600)
        (self.scenario.export / "recently-added-1.json").unlink()
        os.symlink(self.scenario.workspace / "records" / "recently-added-1.json",
                   self.scenario.export / "recently-added-1.json")
        self.scenario.prepare(["passed", "passed", "off", "R-7"])
        self.assertIn("usable-records=none\n", self.summary_text())

    def test_a_linked_export_directory_is_not_trusted(self):
        elsewhere = self.scenario.root / "elsewhere"
        elsewhere.mkdir()
        os.symlink(elsewhere, self.scenario.export)
        self.assertRefused(self.scenario.prepare, ["passed", "passed", "off", "passed"])

    def test_every_attestation_must_be_an_exact_permitted_word(self):
        bad = [
            [], ["passed"], ["", "passed", "off", "passed"], ["yes", "passed", "off", "passed"],
            ["PASSED", "passed", "off", "passed"], ["passed", "failed", "off", "passed"],
            ["passed", "passed", "on", "passed"], ["passed", "passed", "Off", "passed"],
            ["passed", "passed", "unknown", "passed"], ["passed", "passed", "off", "R-8"],
            ["passed", "passed", "off", "r-7"], ["passed", "passed", "off", " passed"],
        ]
        self.scenario.export_records()
        for answers in bad:
            with self.subTest(answers=answers):
                self.assertRefused(self.scenario.prepare, answers, message="permitted words")

    def test_it_runs_only_in_the_test_user_and_never_as_root(self):
        self.scenario.export_records()
        answers = ["passed", "passed", "off", "passed"]
        self.assertRefused(collect.prepare, self.scenario.environment(answers, user="maintainer"))
        environment = self.scenario.environment(answers)
        environment.uid = 0
        self.assertRefused(collect.prepare, environment)

    def test_another_executable_is_refused(self):
        (self.scenario.workspace / "bin" / "GUIProbeMac").write_bytes(b"another executable\n")
        self.assertRefused(self.scenario.prepare, ["passed", "passed", "off", "passed"], message="SHA-256")

    def test_an_existing_summary_of_any_kind_is_never_replaced(self):
        target = self.scenario.shared / collect.SUMMARY_NAME
        for make in (lambda: target.write_text("existing\n"), lambda: os.symlink("/nonexistent", target),
                     lambda: target.mkdir()):
            with self.subTest(make=make):
                self.setUp()
                target = self.scenario.shared / collect.SUMMARY_NAME
                make()
                self.assertRefused(self.scenario.prepare, ["passed", "passed", "off", "passed"], message="already exists")


class ReportTests(CollectorTestCase):
    def prepared(self, answers=("passed", "passed", "unavailable", "passed"), records=collect.RECORDS):
        self.scenario.export_records(records)
        self.scenario.prepare(list(answers))

    def write_summary(self, text, mode=0o644):
        target = self.scenario.shared / collect.SUMMARY_NAME
        target.write_text(text)
        os.chmod(target, mode)

    def test_a_complete_session_produces_the_exact_complete_report(self):
        self.prepared()
        digest = self.scenario.report()
        self.assertEqual(self.report_text(), COMPLETE_REPORT)
        self.assertEqual(digest, hashlib.sha256(COMPLETE_REPORT.encode()).hexdigest())
        self.assertEqual(stat.S_IMODE(os.lstat(self.scenario.shared / collect.REPORT_NAME).st_mode), 0o644)

    def test_an_export_failure_produces_the_exact_export_failure_report(self):
        self.scenario.export_records()
        (self.scenario.export / "recently-added-1.json").write_bytes(b"different\n")
        self.scenario.prepare(["passed", "passed", "off", "R-7"])
        self.scenario.report()
        self.assertEqual(self.report_text(), EXPORT_FAILURE_REPORT)

    def test_every_failure_point_yields_85_of_90_and_names_the_check(self):
        for check in ("R-3", "R-4", "R-5", "R-6", "R-7"):
            with self.subTest(check=check):
                self.setUp()
                self.scenario.prepare(["passed", "passed", "off", check])
                self.scenario.report()
                text = self.report_text()
                self.assertTrue(text.startswith("M12 STAGES 2-5: SURVEY, REVOCATION, AND RETURN PASSED; EVIDENCE EXPORT FAILED\n"))
                self.assertIn(f"EVIDENCE EXPORT, R-3 TO R-7: FAILED AT {check} (", text)
                self.assertIn("REQUIRED CHECKS PASSED: 85/90\n", text)
                self.assertIn("ilibrary-m12-survey-records-v4: NONE USABLE\n", text)
                self.assertNotIn("90/90", text)
                self.assertNotIn("ALL 90", text)

    def test_a_present_summary_without_a_confirmed_return_produces_nothing(self):
        self.prepared()
        for answers in ([], [""], ["yes"], ["Completed"], ["completed "]):
            with self.subTest(answers=answers):
                self.assertRefused(self.scenario.report, answers, message="permitted words")

    def test_it_never_runs_in_the_test_user_or_as_root(self):
        self.prepared()
        self.assertRefused(collect.report, self.scenario.environment(["completed"]))
        self.assertRefused(collect.report, self.scenario.environment(["completed"], user="ilibrary-test-other"))
        environment = self.scenario.environment(["completed"], user="maintainer")
        environment.uid = 0
        self.assertRefused(collect.report, environment)

    def test_a_missing_summary_is_refused(self):
        self.assertRefused(self.scenario.report, message="is missing")

    def test_a_summary_not_created_by_the_test_user_is_refused(self):
        self.prepared()
        environment = self.scenario.environment(["completed"], user="maintainer")
        environment.owner_name = lambda uid: "someone"
        self.assertRefused(collect.report, environment, message="not created by the test user")

    def test_a_linked_or_loosened_summary_is_refused(self):
        self.prepared()
        target = self.scenario.shared / collect.SUMMARY_NAME
        os.chmod(target, 0o664)
        self.assertRefused(self.scenario.report)
        os.chmod(target, 0o644)
        moved = self.scenario.root / "moved-summary.txt"
        os.rename(target, moved)
        os.symlink(moved, target)
        self.assertRefused(self.scenario.report)

    def test_every_malformed_or_contradictory_summary_is_refused(self):
        lines = COMPLETE_SUMMARY.splitlines(keepends=True)

        def replaced(key, value):
            return "".join(f"{key}={value}\n" if line.startswith(key + "=") else line for line in lines)

        variants = [
            "", "\n", COMPLETE_SUMMARY.rstrip("\n"), COMPLETE_SUMMARY + "extra=1\n", COMPLETE_SUMMARY.replace("\n", "\r\n"),
            "".join(lines[1:]), "".join([lines[1], lines[0]] + lines[2:]), "".join(lines + [lines[-1]]),
            replaced("format", "ilibrary-m12-session-summary-2"), replaced("guide", "M12-S2S5-ENUI-v3"),
            replaced("phase", "returned"), replaced("return", "completed"), replaced("prepared-date", "2026-13-40"),
            replaced("prepared-date", "yesterday"), replaced("executable-sha256", "0" * 64),
            replaced("survey-portion", "passed-77-of-78"), replaced("revocation", "failed"),
            replaced("cloud-option", "on"), replaced("cloud-option", "/Users/someone"), replaced("export", "partial"),
            replaced("export", "failed-at-R-8"), replaced("export-checks-passed", "4"),
            replaced("usable-records", "songs-1.json"), replaced("usable-records", "none"),
            replaced("songs-1-sha256", "none"), replaced("songs-1-sha256", "X" * 64),
            replaced("export", "failed-at-R-5"), COMPLETE_SUMMARY.replace("unavailable", "unavailablé"),
            COMPLETE_SUMMARY.replace("=", " = ", 1), COMPLETE_SUMMARY + "x" * 5000,
        ]
        self.scenario.export_records()
        for text in variants:
            with self.subTest(text=text[:80]):
                target = self.scenario.shared / collect.SUMMARY_NAME
                if os.path.lexists(target):
                    target.unlink()
                target.write_bytes(text.encode("utf-8"))
                os.chmod(target, 0o644)
                self.assertRefused(self.scenario.report)
                self.assertFalse(os.path.lexists(self.scenario.shared / collect.REPORT_NAME))

    def test_an_exported_copy_changed_after_the_summary_is_refused(self):
        self.prepared()
        (self.scenario.export / "songs-1.json").write_bytes(b"changed\n")
        self.assertRefused(self.scenario.report, message="no longer matches")
        os.chmod(self.scenario.export / "songs-1.json", 0o644)

    def test_an_unreadable_system_version_is_refused(self):
        self.prepared()
        self.scenario.version.write_bytes(plistlib.dumps({"ProductVersion": "27.0.1 someone"}))
        self.assertRefused(self.scenario.report, message="macOS version")

    def test_an_existing_report_of_any_kind_is_never_replaced(self):
        self.prepared()
        target = self.scenario.shared / collect.REPORT_NAME
        for make, undo in ((lambda: target.write_text("earlier report\n"), target.unlink),
                           (lambda: os.symlink("/nonexistent", target), target.unlink),
                           (lambda: target.mkdir(), target.rmdir)):
            with self.subTest(make=make):
                make()
                self.assertRefused(self.scenario.report, message="already exists")
                undo()


class ReportHardeningTests(CollectorTestCase):
    def prepared(self):
        self.scenario.export_records()
        self.scenario.prepare(["passed", "passed", "unavailable", "passed"])

    def test_a_failure_before_r7_has_the_exact_none_usable_form(self):
        self.scenario.prepare(["passed", "passed", "off", "R-5"])
        self.scenario.report()
        expected = EXPORT_FAILURE_REPORT.replace("FAILED AT R-7", "FAILED AT R-5").replace(
            "songs-1.json only\n", "NONE USABLE\n").replace(
            f"EXPORTED RECORD SHA-256 (EQUAL TO ITS ORIGINAL; CHECKED AGAIN AT REPORT TIME): songs-1.json {SONGS_SHA}\n", "")
        self.assertEqual(self.report_text(), expected)

    def test_a_linked_loosened_or_crowded_export_directory_is_refused_at_report_time(self):
        for change in ("link", "mode", "extra"):
            with self.subTest(change=change):
                self.setUp()
                self.prepared()
                export = self.scenario.export
                if change == "link":
                    moved = self.scenario.root / "moved-export"
                    os.rename(export, moved)
                    os.symlink(moved, export)
                elif change == "mode":
                    os.chmod(export, 0o775)
                else:
                    (export / "other.json").write_text("{}\n")
                self.assertRefused(self.scenario.report, message="export directory")

    def test_a_copy_of_an_unmapped_owner_is_refused_without_a_traceback(self):
        self.prepared()
        environment = self.scenario.environment(["completed"], user="maintainer")
        calls = []

        def owner(uid):
            calls.append(uid)
            if len(calls) > 2:
                raise KeyError(uid)
            return collect.TEST_USER

        environment.owner_name = owner
        self.assertRefused(collect.report, environment, message="no longer matches")

    def test_a_hard_linked_copy_is_neither_usable_nor_accepted(self):
        self.scenario.export_records()
        os.link(self.scenario.export / "songs-1.json", self.scenario.root / "second-link")
        self.scenario.prepare(["passed", "passed", "off", "R-7"])
        self.assertIn("usable-records=recently-added-1.json\n", self.summary_text())

    def test_a_stale_or_future_summary_is_refused(self):
        self.prepared()
        for today in ("2026-10-23", "2026-10-26"):
            with self.subTest(today=today):
                environment = self.scenario.environment(["completed"], user="maintainer")
                environment.today = lambda: today
                self.assertRefused(collect.report, environment, message="today or yesterday")
        environment = self.scenario.environment(["completed"], user="maintainer")
        environment.today = lambda: "2026-10-25"
        collect.report(environment)
        self.assertIn("DATE: 2026-10-25\nSUMMARY PREPARED IN TEST USER ON: 2026-10-24\n", self.report_text())

    def test_a_version_with_a_trailing_line_break_is_refused(self):
        self.prepared()
        self.scenario.version.write_bytes(plistlib.dumps({"ProductVersion": "27.0.1\n", "ProductBuildVersion": "26A434"}))
        self.assertRefused(self.scenario.report, message="macOS version")

    def test_a_missing_shared_folder_is_a_refusal_not_a_traceback(self):
        self.scenario.export_records()
        environment = self.scenario.environment(["passed", "passed", "off", "R-3"])
        environment.shared = self.scenario.root / "absent"
        with self.assertRaises(collect.Refusal) as context:
            collect.prepare(environment)
        self.assertIn("could not be created in its folder", str(context.exception))
        self.assertFalse(context.exception.written)


class PublicationTests(CollectorTestCase):
    def test_an_interrupted_write_leaves_neither_a_report_nor_a_temporary_file(self):
        self.scenario.export_records()
        self.scenario.prepare(["passed", "passed", "unavailable", "passed"])
        real_write = os.write
        calls = []

        def failing_write(descriptor, data):
            calls.append(len(data))
            if len(calls) == 1:
                return real_write(descriptor, bytes(data[:10]))
            raise OSError("simulated interruption")

        with mock.patch.object(collect.os, "write", failing_write):
            self.assertRefused(self.scenario.report, message="could not be written")
        self.assertFalse(os.path.lexists(self.scenario.shared / collect.REPORT_NAME))

    def test_a_report_that_appears_during_publication_is_not_replaced(self):
        self.scenario.export_records()
        self.scenario.prepare(["passed", "passed", "unavailable", "passed"])
        target = self.scenario.shared / collect.REPORT_NAME
        real_link = os.link

        def racing_link(source, destination, **keywords):
            Path(destination).write_text("written by another process\n")
            return real_link(source, destination, **keywords)

        with mock.patch.object(collect.os, "link", racing_link):
            with self.assertRaises(collect.Refusal) as context:
                self.scenario.report()
        self.assertIn("appeared while it was being written", str(context.exception))
        self.assertEqual(target.read_text(), "written by another process\n")
        self.assertEqual(list(self.scenario.shared.glob(".*partial")), [])

    def test_a_failed_read_back_is_reported_and_the_file_is_left_for_review(self):
        self.scenario.export_records()
        self.scenario.prepare(["passed", "passed", "unavailable", "passed"])
        real_read = collect.read_regular

        def read(path, limit, owner_uid=None, mode=None):
            if Path(path).name == collect.REPORT_NAME:
                return b"tampered"
            return real_read(path, limit, owner_uid, mode)

        with mock.patch.object(collect, "read_regular", read):
            with self.assertRaises(collect.Refusal) as context:
                self.scenario.report()
        self.assertTrue(context.exception.written)

    def test_existing_evidence_and_unrelated_files_are_preserved(self):
        unrelated = self.scenario.shared / "ilibrary-m12-stage1-report.txt"
        unrelated.write_text("stage 1 evidence\n")
        self.scenario.export_records()
        before = {path: path.read_bytes() for path in (unrelated, *(self.scenario.workspace / "records").iterdir(),
                                                        *self.scenario.export.iterdir())}
        self.scenario.prepare(["passed", "passed", "unavailable", "passed"])
        self.scenario.report()
        for path, data in before.items():
            self.assertEqual(path.read_bytes(), data)
        names = sorted(path.name for path in self.scenario.shared.iterdir())
        self.assertEqual(names, sorted([collect.EXPORT_DIRECTORY_NAME, collect.REPORT_NAME, collect.SUMMARY_NAME,
                                        "ilibrary-m12-stage1-report.txt"]))


class PrivacyTests(CollectorTestCase):
    def test_outputs_hold_only_fixed_fields_and_no_private_values(self):
        self.scenario.export_records()
        self.scenario.prepare(["passed", "passed", "unavailable", "passed"])
        self.scenario.report()
        for text in (self.summary_text(), self.report_text()):
            self.assertTrue(text.isascii())
            for private in (self.directory.name, str(self.scenario.home), collect.TEST_USER, "maintainer",
                            str(os.getpid()), "identifier-map", "outcome-record"):
                self.assertNotIn(private, text)

    def test_the_command_line_accepts_only_its_two_steps(self):
        for arguments in ([], ["prepare", "extra"], ["--report"], ["collect"], ["report", "/tmp/x"]):
            with self.subTest(arguments=arguments), mock.patch("sys.stderr"):
                self.assertEqual(collect.main(arguments, environment=self.scenario.environment([])), 2)

    def test_a_refusal_through_the_command_line_writes_nothing_and_says_so(self):
        environment = self.scenario.environment(["no"], user="maintainer")
        with mock.patch("sys.stderr") as stderr:
            self.assertEqual(collect.main(["report"], environment=environment), 1)
        written = "".join(call.args[0] for call in stderr.write.call_args_list)
        self.assertIn("nothing was written", written)


if __name__ == "__main__":
    unittest.main()
