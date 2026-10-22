#!/usr/bin/env python3
"""Produce the sanitized session report of the M12 stages 2 to 5 qualification (guide M12-S2S5-ENUI-v4).

The collector has two steps, each one reviewed command, and never addresses Music, Apple Events, Accessibility,
the user interface, an account setting, or the network.

    python3 -I m12_session_collect.py prepare    (in the test user, after R-9 and before its logout)
    python3 -I m12_session_collect.py report     (in the personal account, after R-12)

`prepare` asks for four operator attestations with closed answers, measures the probe executable's SHA-256 and
compares each exported survey record with its private original byte for byte, and publishes a fixed-key summary
that states that the logout and return have not yet occurred. It reads only the test user's copy of the probe,
the two private survey records, and their two exported copies. `report` asks for the operator's confirmation of
the return, accepts only a summary of the exact form that `prepare` writes, owned by the test user, verifies that
the exported copies still match it, reads the macOS version from the system version file, and publishes the
final report. Neither step reads the identifier mappings, the process-outcome record, shell history, or
diagnostics, and neither publishes a process identifier, an account name, a private path, or free text.

A collector that finishes has produced its output under this validation contract. It does not independently show
that a Music observation, a Terminal check, a trust result, the removal of the Accessibility entry, or the logout
occurred; those remain the operator's attestations. Each output is created exclusively under a temporary name,
linked to its final name, which fails rather than replacing anything, read back, and only then reported.
"""

import datetime
import hashlib
import os
import plistlib
import pwd
import re
import secrets
import stat
import sys
from pathlib import Path

GUIDE = "M12-S2S5-ENUI-v4"
SUMMARY_FORMAT = "ilibrary-m12-session-summary-1"
REPORT_FORMAT = "ilibrary-m12-session-report-1"
TEST_USER = "ilibrarytestm12"
TEST_USER_PATTERN = re.compile(r"^(ilibrarytest|ilibrary-test)[A-Za-z0-9_-]*$")
EXECUTABLE_SHA256 = "a564cebbec7e1c1b32a1f2cd4afb2b5f311604ff94cde5f5bf55db9d4f87bb79"
RECORDS = ("songs-1.json", "recently-added-1.json")
EXPORT_FAILURES = ("R-3", "R-4", "R-5", "R-6", "R-7")
CLOUD_OPTIONS = ("unavailable", "off")
SHARED = Path("/Users/Shared")
SUMMARY_NAME = "ilibrary-m12-session-2-5-v4-summary.txt"
REPORT_NAME = "ilibrary-m12-session-2-5-v4-report.txt"
EXPORT_DIRECTORY_NAME = "ilibrary-m12-survey-records-v4"
SYSTEM_VERSION = Path("/System/Library/CoreServices/SystemVersion.plist")
MAXIMUM_SUMMARY_BYTES = 4096
MAXIMUM_RECORD_BYTES = 64 << 20
HEX64 = re.compile(r"^[0-9a-f]{64}$")
DATE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
VERSION = re.compile(r"^[0-9]{1,3}(\.[0-9]{1,3}){0,2}$")
BUILD = re.compile(r"^[0-9A-Za-z]{1,16}$")
SUMMARY_KEYS = (
    "format", "guide", "phase", "return", "prepared-date", "executable-sha256", "survey-portion",
    "revocation", "cloud-option", "export", "export-checks-passed", "usable-records", "songs-1-sha256",
    "recently-added-1-sha256",
)
USABLE_VALUES = ("both", "songs-1.json", "recently-added-1.json", "none")


class Refusal(Exception):
    """A reason, in fixed text that repeats no private value, why the step did not complete. `written` is true
    only when a final file exists that did not pass its read-back check; it is then left in place for review."""

    def __init__(self, message, written=False):
        super().__init__(message)
        self.written = written


class Environment:
    """The fixed locations and the process identity; tests substitute temporary directories and identities."""

    def __init__(self, shared=SHARED, home=None, user=None, uid=None, owner_name=None, system_version=SYSTEM_VERSION,
                 ask=input, today=None):
        entry = pwd.getpwuid(os.getuid())
        self.shared = Path(shared)
        self.home = Path(home if home is not None else entry.pw_dir)
        self.user = user if user is not None else entry.pw_name
        self.uid = uid if uid is not None else os.getuid()
        self.owner_name = owner_name or (lambda owner: pwd.getpwuid(owner).pw_name)
        self.system_version = Path(system_version)
        self.ask = ask
        self.today = today or (lambda: datetime.date.today().isoformat())

    @property
    def summary(self):
        return self.shared / SUMMARY_NAME

    @property
    def report(self):
        return self.shared / REPORT_NAME

    @property
    def export_directory(self):
        return self.shared / EXPORT_DIRECTORY_NAME


def read_regular(path, limit, owner_uid=None):
    """The bytes of a regular file opened without following a link, within `limit` bytes, optionally owned by
    `owner_uid`; None when it is absent, a link, another kind of object, too large, or otherwise unreadable."""
    try:
        descriptor = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return None
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            return None
        if owner_uid is not None and info.st_uid != owner_uid:
            return None
        chunks, total = [], 0
        while True:
            chunk = os.read(descriptor, 1 << 20)
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                return None
            chunks.append(chunk)
        return b"".join(chunks)
    finally:
        os.close(descriptor)


def publish(path, data):
    """Creates `path` with exactly `data` and mode 0644, never replacing an existing object, and reads it back.

    The data is written to a new temporary file in the same directory, created exclusively, and flushed; the
    temporary file is then linked to the final name, which fails if any object, a link included, has that name.
    After a failure the temporary file is removed; an interruption can leave only a file whose name ends in
    `.partial`, never a final name."""
    if os.path.lexists(str(path)):
        raise Refusal(f"{path.name} already exists; nothing is ever replaced")
    temporary = path.with_name(f".{path.name}.{secrets.token_hex(8)}.partial")
    descriptor = os.open(str(temporary), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        try:
            os.fchmod(descriptor, 0o644)
            view = memoryview(data)
            while view:
                written = os.write(descriptor, view)
                if written <= 0:
                    raise OSError("short write")
                view = view[written:]
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        try:
            os.link(str(temporary), str(path), follow_symlinks=False)
        except FileExistsError:
            raise Refusal(f"{path.name} appeared while it was being written; it was not replaced")
    except OSError as error:
        raise Refusal(f"{path.name} could not be written ({error.__class__.__name__})")
    finally:
        try:
            os.unlink(str(temporary))
        except OSError:
            pass
    if read_regular(path, max(len(data), 1)) != data or stat.S_IMODE(os.lstat(str(path)).st_mode) != 0o644:
        raise Refusal(f"{path.name} was written but does not read back as written with mode 0644", written=True)
    return hashlib.sha256(data).hexdigest()


def ask_exact(environment, prompt, allowed):
    try:
        answer = environment.ask(prompt)
    except EOFError:
        answer = ""
    if answer not in allowed:
        raise Refusal("the answer to '" + prompt.split(" (")[0] + "' was not one of the permitted words")
    return answer


def prepare(environment):
    """Writes the intermediate summary in the test user."""
    if environment.user != TEST_USER or environment.uid == 0:
        raise Refusal("prepare runs only in the test user, never as root")
    if os.path.lexists(str(environment.summary)):
        raise Refusal(f"{SUMMARY_NAME} already exists; nothing is ever replaced")
    workspace = environment.home / "ilibrary-m12"
    executable = read_regular(workspace / "bin" / "GUIProbeMac", MAXIMUM_RECORD_BYTES, environment.uid)
    if executable is None or hashlib.sha256(executable).hexdigest() != EXECUTABLE_SHA256:
        raise Refusal("the test user's GUIProbeMac does not have the SHA-256 recorded in the guide")
    ask_exact(environment, "Survey portion S0-1 to S5-19 (type passed): ", ("passed",))
    ask_exact(environment, "Accessibility revocation R-1 and R-2 (type passed): ", ("passed",))
    cloud = ask_exact(environment, "Cloud library option recorded at S2-5 (type unavailable or off): ", CLOUD_OPTIONS)
    export = ask_exact(
        environment, "Evidence export R-3 to R-7 (type passed, or the first failed check R-3, R-4, R-5, R-6, or R-7): ",
        ("passed",) + EXPORT_FAILURES)
    digests = {}
    if export in ("passed", "R-7"):
        directory = environment.export_directory
        try:
            info = os.lstat(str(directory))
            directory_valid = (stat.S_ISDIR(info.st_mode) and info.st_uid == environment.uid
                               and stat.S_IMODE(info.st_mode) == 0o755)
        except OSError:
            directory_valid = False
        for name in RECORDS:
            original = read_regular(workspace / "records" / name, MAXIMUM_RECORD_BYTES, environment.uid)
            copy = read_regular(directory / name, MAXIMUM_RECORD_BYTES, environment.uid) if directory_valid else None
            try:
                copy_mode = stat.S_IMODE(os.lstat(str(directory / name)).st_mode)
            except OSError:
                copy_mode = None
            if original is not None and copy is not None and copy == original and copy_mode == 0o644:
                digests[name] = hashlib.sha256(copy).hexdigest()
        if export == "passed" and len(digests) != len(RECORDS):
            raise Refusal("the export was attested as passed, but not every exported copy equals its original")
    if len(digests) == 2:
        usable = "both"
    elif len(digests) == 1:
        usable = next(iter(digests))
    else:
        usable = "none"
    values = {
        "format": SUMMARY_FORMAT, "guide": GUIDE, "phase": "prepared-in-test-user-before-logout",
        "return": "not-yet-performed", "prepared-date": environment.today(),
        "executable-sha256": EXECUTABLE_SHA256, "survey-portion": "passed-78-of-78",
        "revocation": "passed-2-of-2", "cloud-option": cloud,
        "export": "passed" if export == "passed" else "failed-at-" + export,
        "export-checks-passed": "5" if export == "passed" else "0", "usable-records": usable,
        "songs-1-sha256": digests.get("songs-1.json", "none"),
        "recently-added-1-sha256": digests.get("recently-added-1.json", "none"),
    }
    text = "".join(f"{key}={values[key]}\n" for key in SUMMARY_KEYS)
    parse_summary(text.encode("ascii"))
    return publish(environment.summary, text.encode("ascii"))


def parse_summary(data):
    """The summary's values, accepted only in the exact form and order that `prepare` writes."""
    if len(data) > MAXIMUM_SUMMARY_BYTES:
        raise Refusal("the summary is too large")
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError:
        raise Refusal("the summary is not ASCII text")
    if not text.endswith("\n") or "\r" in text:
        raise Refusal("the summary does not have the expected line form")
    lines = text[:-1].split("\n")
    if len(lines) != len(SUMMARY_KEYS):
        raise Refusal("the summary does not have exactly the expected fields")
    values = {}
    for key, line in zip(SUMMARY_KEYS, lines):
        if not line.startswith(key + "="):
            raise Refusal("the summary's fields are not the expected ones in the expected order")
        values[key] = line[len(key) + 1:]
    fixed = {
        "format": SUMMARY_FORMAT, "guide": GUIDE, "phase": "prepared-in-test-user-before-logout",
        "return": "not-yet-performed", "executable-sha256": EXECUTABLE_SHA256,
        "survey-portion": "passed-78-of-78", "revocation": "passed-2-of-2",
    }
    for key, expected in fixed.items():
        if values[key] != expected:
            raise Refusal(f"the summary's field '{key}' does not have its required value")
    if not DATE.match(values["prepared-date"]):
        raise Refusal("the summary's field 'prepared-date' is not a date")
    try:
        datetime.date.fromisoformat(values["prepared-date"])
    except ValueError:
        raise Refusal("the summary's field 'prepared-date' is not a date")
    if values["cloud-option"] not in CLOUD_OPTIONS:
        raise Refusal("the summary's field 'cloud-option' is not a permitted value")
    if values["export"] not in ("passed",) + tuple("failed-at-" + check for check in EXPORT_FAILURES):
        raise Refusal("the summary's field 'export' is not a permitted value")
    if values["usable-records"] not in USABLE_VALUES:
        raise Refusal("the summary's field 'usable-records' is not a permitted value")
    for key in ("songs-1-sha256", "recently-added-1-sha256"):
        if values[key] != "none" and not HEX64.match(values[key]):
            raise Refusal(f"the summary's field '{key}' is not a digest")
    usable = {name for name in RECORDS if values[name.replace(".json", "") + "-sha256"] != "none"}
    expected_usable = {"both": set(RECORDS), "none": set()}.get(values["usable-records"], {values["usable-records"]})
    if usable != expected_usable:
        raise Refusal("the summary's usable records and digests contradict each other")
    passed = values["export"] == "passed"
    if values["export-checks-passed"] != ("5" if passed else "0"):
        raise Refusal("the summary's export count contradicts its export result")
    if passed and usable != set(RECORDS):
        raise Refusal("the summary reports a passed export without both usable records")
    if values["export"] in ("failed-at-R-3", "failed-at-R-4", "failed-at-R-5", "failed-at-R-6") and usable:
        raise Refusal("the summary lists a usable record for an export that failed before R-7")
    return values


def macos_version(environment):
    data = read_regular(environment.system_version, 1 << 16)
    try:
        info = plistlib.loads(data) if data is not None else {}
    except Exception:
        info = {}
    version, build = info.get("ProductVersion"), info.get("ProductBuildVersion")
    if not isinstance(version, str) or not VERSION.match(version) or not isinstance(build, str) or not BUILD.match(build):
        raise Refusal("the macOS version could not be read from the system version file")
    return f"{version} ({build})"


def render(values, date, macos):
    passed = values["export"] == "passed"
    failure = values["export"][len("failed-at-"):] if not passed else None
    usable = values["usable-records"]
    usable_text = {"both": "both records", "none": "NONE USABLE"}.get(usable, f"{usable} only")
    lines = [
        "M12 STAGES 2-5: " + ("ALL 90 CHECKS PASSED" if passed else
                              "SURVEY, REVOCATION, AND RETURN PASSED; EVIDENCE EXPORT FAILED"),
        f"GUIDE: {GUIDE}",
        f"REPORT FORMAT: {REPORT_FORMAT}",
        f"DATE: {date}",
        f"SUMMARY PREPARED IN TEST USER ON: {values['prepared-date']}",
        f"MACOS (READ BY THE COLLECTOR IN THE PERSONAL ACCOUNT): {macos}",
        f"EXECUTABLE SHA-256 MEASURED IN TEST USER: {values['executable-sha256']}",
        "SURVEY PORTION, S0-1 TO S5-19: 78/78 PASSED (OPERATOR ATTESTED)",
        "ACCESSIBILITY REVOCATION, R-1 AND R-2: 2/2 PASSED (OPERATOR ATTESTED)",
        "EVIDENCE EXPORT, R-3 TO R-7: " + ("5/5 PASSED (OPERATOR ATTESTED)" if passed else
                                           f"FAILED AT {failure} (THE FIVE EXPORT CHECKS ARE COUNTED AS FAILED)"),
        "RETURN, R-8 TO R-12: 5/5 PASSED (OPERATOR CONFIRMED IN THE PERSONAL ACCOUNT)",
        "REQUIRED CHECKS PASSED: " + ("90/90" if passed else "85/90"),
        "CLOUD LIBRARY OPTION: " + ("unavailable (OPERATOR OBSERVED; NOT AN OBSERVED DISABLED SETTING)"
                                    if values["cloud-option"] == "unavailable" else "off (OPERATOR OBSERVED)"),
        f"EXPORTED RECORDS IN /Users/Shared/{EXPORT_DIRECTORY_NAME}: {usable_text}",
    ]
    for name in RECORDS:
        digest = values[name.replace(".json", "") + "-sha256"]
        if digest != "none":
            lines.append(f"EXPORTED RECORD SHA-256 (EQUAL TO ITS ORIGINAL; CHECKED AGAIN AT REPORT TIME): {name} {digest}")
    lines += [
        "GUI EMPTINESS: NOT QUALIFIED (structural survey only)",
        "COLLECTOR SCOPE: the collector measured the executable digest and compared the exported copies; it did not "
        "observe Music, Accessibility, Terminal, or the logout, which rest on the operator's attestations",
    ]
    return "".join(line + "\n" for line in lines)


def report(environment):
    """Writes the final report in the personal account."""
    if environment.uid == 0 or TEST_USER_PATTERN.match(environment.user):
        raise Refusal("report runs only in the personal account after the return, never as root")
    if os.path.lexists(str(environment.report)):
        raise Refusal(f"{REPORT_NAME} already exists; nothing is ever replaced")
    ask_exact(environment, "Return R-8 to R-12 completed, and this is the personal account (type completed): ",
              ("completed",))
    summary = environment.summary
    try:
        info = os.lstat(str(summary))
    except OSError:
        raise Refusal(f"{SUMMARY_NAME} is missing")
    if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o644:
        raise Refusal(f"{SUMMARY_NAME} is not a regular file with mode 0644")
    try:
        owner = environment.owner_name(info.st_uid)
    except KeyError:
        owner = None
    if owner != TEST_USER:
        raise Refusal(f"{SUMMARY_NAME} was not created by the test user")
    data = read_regular(summary, MAXIMUM_SUMMARY_BYTES, info.st_uid)
    if data is None:
        raise Refusal(f"{SUMMARY_NAME} could not be read as a regular file")
    values = parse_summary(data)
    for name in RECORDS:
        digest = values[name.replace(".json", "") + "-sha256"]
        if digest == "none":
            continue
        path = environment.export_directory / name
        try:
            copy_info = os.lstat(str(path))
        except OSError:
            raise Refusal(f"the exported copy {name} is missing")
        copy = read_regular(path, MAXIMUM_RECORD_BYTES, copy_info.st_uid)
        if (copy is None or stat.S_IMODE(copy_info.st_mode) != 0o644 or environment.owner_name(copy_info.st_uid)
                != TEST_USER or hashlib.sha256(copy).hexdigest() != digest):
            raise Refusal(f"the exported copy {name} no longer matches the summary")
    text = render(values, environment.today(), macos_version(environment))
    return publish(environment.report, text.encode("ascii"))


def main(arguments, environment=None):
    if arguments not in (["prepare"], ["report"]):
        print("usage: python3 -I m12_session_collect.py prepare | report", file=sys.stderr)
        return 2
    environment = environment or Environment()
    try:
        if arguments == ["prepare"]:
            digest = prepare(environment)
            print(f"m12_session_collect: summary written: {environment.summary} (SHA-256 {digest})")
        else:
            digest = report(environment)
            print(f"m12_session_collect: report written: {environment.report} (SHA-256 {digest})")
    except Refusal as refusal:
        outcome = "the file is left in place for review" if refusal.written else "nothing was written"
        print(f"m12_session_collect: refused: {refusal}; {outcome}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
