"""Regression tests for decision-f-compare.sh, run on a disposable copy against stub executables.

No real ilibrary executable and no Music are involved: the copy of the tracked script has only its user-name
and root guard lines replaced and its account export command pointed at a stub that prints synthetic preference
text; the real plutil reads only that text. The stubs print controlled doctor and check output.
"""

import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / "decision-f-compare.sh"

USER_GUARD = "[[ $user == ilibrarytest* || $user == ilibrary-test* ]] || stop"
ROOT_GUARD = "[[ $(id -u) != 0 ]] || stop 'the command runs as root'"
EXPORT_LINE = 'account=$(/usr/bin/defaults export MobileMeAccounts - 2>"$export_error_file")'

PLIST_HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n'
              '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
              '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n')


def plist(body):
    return PLIST_HEAD + body + "\n</plist>\n"


EMPTY_DICT = plist("<dict/>")
EMPTY_ARRAY = plist("<dict><key>Accounts</key><array/></dict>")
STRING_ACCOUNT = "<dict><key>AccountID</key><string>synthetic@example.invalid</string></dict>"
DEFAULTS_STUB = """#!/bin/sh
d=$(dirname "$0")
echo "$0 $*" >> "$d/defaults.log"
cat "$d/defaults.out"
cat "$d/defaults.err" >&2
exit "$(cat "$d/defaults.code")"
"""

UNCHANGED_OUT = "Checked 12 files against the Music library\nNo problems found.\n"
REMOVED_NAME = "03 Synthetic Track.m4a"


def removal_out(name=REMOVED_NAME):
    return ("Checked 12 files against the Music library\n"
            f"Music/Artist/Album/{name}: a library track whose file is missing\n"
            "1 problem(s) found.\n")


STUB = """#!/bin/sh
d=$(dirname "$0")
echo "$0 $*" >> "@LOG@"
if [ "$1" = doctor ]; then
    cat "$d/doctor.out"
    exit "$(cat "$d/doctor.code")"
fi
if [ "$2" = --library ]; then mode=library; else mode=path; fi
n=1
if [ -f "$d/count-$mode" ]; then n=$(( $(cat "$d/count-$mode") + 1 )); fi
echo "$n" > "$d/count-$mode"
f="$d/$mode.$n"
[ -f "$f.out" ] || f="$d/$mode"
if [ -f "$d/$mode.kill" ]; then kill -9 $$; fi
if [ -f "$f.out" ]; then cat "$f.out"; fi
if [ -f "$f.err" ]; then cat "$f.err" >&2; fi
if [ -f "$f.code" ]; then exit "$(cat "$f.code")"; fi
exit 0
"""


class Bundle:
    """A disposable bundle: script copy, stubs, library folders, checksums, and results."""

    def __init__(self, root, phase="unchanged", out=None, err="", code=0, removed=None,
                 export_out=EMPTY_DICT, export_err="", export_code=0):
        self.root = Path(root)
        self.phase = phase
        self.bundle = self.root / "bundle"
        self.media = self.root / "DecisionF-comparison-v4" / "Media"
        self.target = self.media / "Music"
        self.target.mkdir(parents=True)
        (self.bundle / "results").mkdir(parents=True)
        (self.bundle / "SOURCES").write_text("synthetic sources\n")
        self.log = self.root / "invocations.log"
        self.log.write_text("")
        stubs = self.root / "stubs"
        stubs.mkdir()
        defaults = stubs / "defaults"
        defaults.write_text(DEFAULTS_STUB)
        defaults.chmod(0o755)
        (stubs / "defaults.out").write_text(export_out)
        (stubs / "defaults.err").write_text(export_err)
        (stubs / "defaults.code").write_text(str(export_code))
        text = SCRIPT.read_text()
        for guard in (USER_GUARD, ROOT_GUARD, EXPORT_LINE):
            assert guard in text, f"the tracked script no longer contains the guard line {guard!r}"
        lines = []
        for line in text.split("\n"):
            if line.startswith(USER_GUARD) or line == ROOT_GUARD:
                line = "true"
            elif line == EXPORT_LINE:
                line = line.replace("/usr/bin/defaults", str(defaults))
            lines.append(line)
        (self.bundle / "decision-f-compare.sh").write_text("\n".join(lines))
        if out is None:
            out = UNCHANGED_OUT if phase == "unchanged" else removal_out()
        if phase == "after-removal" and code == 0 and out != UNCHANGED_OUT:
            code = 1
        for exe in ("reference", "candidate"):
            folder = self.bundle / "bin" / exe
            folder.mkdir(parents=True)
            stub = folder / "ilibrary"
            stub.write_text(STUB.replace("@LOG@", str(self.log)))
            stub.chmod(0o755)
            self.write(exe, "doctor.out", f"ok     version: synthetic\nok     media folder: {self.media}\n")
            self.write(exe, "doctor.code", "0")
            for mode in ("library", "path"):
                self.write(exe, f"{mode}.out", out)
                self.write(exe, f"{mode}.err", err)
                self.write(exe, f"{mode}.code", str(code))
        if removed is not None:
            (self.bundle / "results" / "removed-file.txt").write_text(removed)
        elif phase == "after-removal":
            (self.bundle / "results" / "removed-file.txt").write_text(REMOVED_NAME + "\n")

    def write(self, exe, name, content):
        (self.bundle / "bin" / exe / name).write_text(content)

    def seal(self):
        entries = []
        for path in sorted(self.bundle.rglob("*")):
            relative = path.relative_to(self.bundle)
            if path.is_file() and relative.parts[0] != "results" and not relative.name == "SHA256SUMS":
                entries.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {relative}")
        (self.bundle / "SHA256SUMS").write_text("\n".join(entries) + "\n")

    def run(self):
        self.seal()
        return subprocess.run(["zsh", str(self.bundle / "decision-f-compare.sh"), self.phase, str(self.target)],
                              cwd=self.bundle, capture_output=True, text=True, timeout=120)

    @property
    def results(self):
        return self.bundle / "results" / self.phase

    def summary(self):
        return (self.results / "summary.txt").read_text()


class CompareScriptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.temporary, ignore_errors=True)

    def bundle(self, **options):
        return Bundle(self.temporary, **options)

    def assertCompleted(self, bundle, result, verdict):
        self.assertTrue((bundle.results / "summary.txt").is_file(), result.stderr)
        self.assertIn(f"verdict: {verdict}", bundle.summary())
        self.assertEqual(result.returncode, 0 if verdict == "PASS" else 1, result.stdout + result.stderr)
        self.assertTrue((bundle.results / "times.txt").is_file())
        files = list(bundle.results.glob("*-*.stdout")) + list(bundle.results.glob("*-*.stderr"))
        self.assertEqual(len(files), 12)
        for path in files:
            self.assertIsNone(re.search(r"\d+\.\d{3}\b", path.read_text()), path.name)

    def assertStoppedBeforeRuns(self, bundle, result):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("STOP", result.stderr)
        self.assertFalse(bundle.results.exists())
        for exe in ("reference", "candidate"):
            self.assertEqual(list((bundle.bundle / "bin" / exe).glob("count-*")), [])

    def assertAccountRejected(self, **export):
        bundle = self.bundle(**export)
        result = bundle.run()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stderr, r"STOP: .*[Aa]ccount")
        self.assertFalse((bundle.bundle / "results" / "unchanged").exists())
        self.assertEqual(bundle.log.read_text(), "")
        export_log = next(bundle.root.rglob("defaults.log"))
        self.assertEqual(len(export_log.read_text().splitlines()), 1)
        return result

    def test_account_export_rejections_stop_before_any_executable_runs(self):
        cases = {
            "non-empty array of string dictionaries": dict(export_out=plist(
                f"<dict><key>Accounts</key><array>{STRING_ACCOUNT}</array></dict>")),
            "entry with a date value": dict(export_out=plist(
                "<dict><key>Accounts</key><array><dict><key>When</key>"
                "<date>2020-01-01T00:00:00Z</date></dict></array></dict>")),
            "entry with a data value": dict(export_out=plist(
                "<dict><key>Accounts</key><array><dict><key>Blob</key>"
                "<data>AAEC</data></dict></array></dict>")),
            "Accounts of type string": dict(export_out=plist(
                "<dict><key>Accounts</key><string>x</string></dict>")),
            "Accounts of type dictionary": dict(export_out=plist(
                "<dict><key>Accounts</key><dict/></dict>")),
            "non-empty domain without Accounts": dict(export_out=plist(
                "<dict><key>Other</key><string>x</string></dict>")),
            "top-level array": dict(export_out=plist("<array/>")),
            "malformed text": dict(export_out="this is not a property list\n"),
            "warning line before valid text": dict(export_out="warning: something\n" + EMPTY_ARRAY),
            "empty array with standard error": dict(export_out=EMPTY_ARRAY, export_err="a warning\n"),
            "nonzero status with empty dictionary": dict(export_out=EMPTY_DICT, export_code=1),
            "nonzero status with does-not-exist message": dict(
                export_out="", export_err="Domain MobileMeAccounts does not exist\n", export_code=1),
            "empty output with status zero": dict(export_out=""),
        }
        for name, export in cases.items():
            with self.subTest(case=name):
                shutil.rmtree(self.temporary)
                Path(self.temporary).mkdir()
                self.assertAccountRejected(**export)

    def test_absent_account_domain_is_accepted(self):
        bundle = self.bundle(export_out=EMPTY_DICT)
        result = bundle.run()
        self.assertCompleted(bundle, result, "PASS")

    def test_empty_accounts_array_is_accepted(self):
        bundle = self.bundle(export_out=EMPTY_ARRAY)
        result = bundle.run()
        self.assertCompleted(bundle, result, "PASS")

    def test_unchanged_success_passes(self):
        bundle = self.bundle()
        result = bundle.run()
        self.assertCompleted(bundle, result, "PASS")
        self.assertNotIn("REJECTED", bundle.summary())

    def test_identical_failures_stop_in_both_phases(self):
        for phase in ("unchanged", "after-removal"):
            with self.subTest(phase=phase):
                shutil.rmtree(self.temporary)
                Path(self.temporary).mkdir()
                bundle = self.bundle(phase=phase, out="", err="ilibrary: error: the library could not be read\n",
                                     code=1)
                result = bundle.run()
                self.assertCompleted(bundle, result, "STOP")
                self.assertIn("REJECTED", bundle.summary())

    def test_unexpected_nonzero_status_stops_when_output_is_identical(self):
        bundle = self.bundle(code=1)
        result = bundle.run()
        self.assertCompleted(bundle, result, "STOP")
        self.assertIn("exit status is 1, expected 0", bundle.summary())

    def test_candidate_stdout_difference_stops(self):
        bundle = self.bundle()
        bundle.write("candidate", "library.out", UNCHANGED_OUT.replace("12", "11"))
        result = bundle.run()
        self.assertCompleted(bundle, result, "STOP")
        self.assertIn("library stdout: CANDIDATE DIFFERS FROM REFERENCE", bundle.summary())

    def test_second_reference_run_difference_stops(self):
        bundle = self.bundle()
        bundle.write("reference", "path.2.out", UNCHANGED_OUT.replace("12", "13"))
        result = bundle.run()
        self.assertCompleted(bundle, result, "STOP")
        self.assertIn("path stdout: REFERENCE RUNS DIFFER", bundle.summary())

    def test_identical_nonempty_stderr_stops(self):
        bundle = self.bundle(err="a warning\n")
        result = bundle.run()
        self.assertCompleted(bundle, result, "STOP")
        self.assertIn("standard error is not empty", bundle.summary())

    def test_after_removal_expected_outcome_passes(self):
        bundle = self.bundle(phase="after-removal")
        result = bundle.run()
        self.assertCompleted(bundle, result, "PASS")

    def test_after_removal_without_missing_file_finding_stops(self):
        bundle = self.bundle(phase="after-removal",
                             out="Checked 12 files against the Music library\n1 problem(s) found.\n", code=1)
        result = bundle.run()
        self.assertCompleted(bundle, result, "STOP")
        self.assertIn("no missing-file finding", bundle.summary())

    def test_after_removal_naming_a_different_file_stops(self):
        bundle = self.bundle(phase="after-removal", out=removal_out("07 Other Track.m4a"), code=1)
        result = bundle.run()
        self.assertCompleted(bundle, result, "STOP")
        self.assertIn("no missing-file finding naming", bundle.summary())

    def test_after_removal_with_status_zero_stops(self):
        bundle = self.bundle(phase="after-removal", out=removal_out(), code=0)
        for exe in ("reference", "candidate"):
            for mode in ("library", "path"):
                bundle.write(exe, f"{mode}.code", "0")
        result = bundle.run()
        self.assertCompleted(bundle, result, "STOP")
        self.assertIn("exit status is 0, expected 1", bundle.summary())

    def test_after_removal_without_removed_file_stops_before_runs(self):
        bundle = self.bundle(phase="after-removal")
        (bundle.bundle / "results" / "removed-file.txt").unlink()
        result = bundle.run()
        self.assertStoppedBeforeRuns(bundle, result)
        self.assertIn("removed-file.txt", result.stderr)

    def test_after_removal_with_empty_removed_file_stops_before_runs(self):
        for content in ("", "\n"):
            with self.subTest(content=content):
                bundle = self.bundle(phase="after-removal", removed=content)
                result = bundle.run()
                self.assertStoppedBeforeRuns(bundle, result)
                shutil.rmtree(self.temporary)
                Path(self.temporary).mkdir()

    def test_doctor_failure_status_stops_before_runs(self):
        bundle = self.bundle()
        bundle.write("reference", "doctor.code", "1")
        result = bundle.run()
        self.assertStoppedBeforeRuns(bundle, result)
        self.assertIn("doctor exited with status 1", result.stderr)

    def test_problem_media_folder_line_stops_before_runs(self):
        bundle = self.bundle()
        bundle.write("reference", "doctor.out",
                     f"problem media folder: {bundle.media} does not exist\n")
        result = bundle.run()
        self.assertStoppedBeforeRuns(bundle, result)
        self.assertIn("doctor did not report an existing media folder", result.stderr)

    def test_existing_results_folder_is_refused_unmodified(self):
        bundle = self.bundle()
        existing = bundle.results
        existing.mkdir(parents=True)
        (existing / "marker.txt").write_text("keep\n")
        result = bundle.run()
        self.assertEqual(result.returncode, 1)
        self.assertIn("already exists", result.stderr)
        self.assertEqual([path.name for path in existing.iterdir()], ["marker.txt"])
        self.assertEqual((existing / "marker.txt").read_text(), "keep\n")

    def test_run_killed_by_a_signal_stops(self):
        bundle = self.bundle()
        bundle.write("candidate", "library.kill", "")
        result = bundle.run()
        self.assertCompleted(bundle, result, "STOP")
        self.assertIn("library-candidate: REJECTED", bundle.summary())

    def test_run_that_writes_nothing_stops(self):
        bundle = self.bundle()
        for exe in ("reference", "candidate"):
            for mode in ("library", "path"):
                (bundle.bundle / "bin" / exe / f"{mode}.out").unlink()
        result = bundle.run()
        self.assertCompleted(bundle, result, "STOP")
        self.assertIn("no \"Checked N files", bundle.summary())


if __name__ == "__main__":
    unittest.main()
