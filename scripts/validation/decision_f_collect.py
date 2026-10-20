"""Combines the Decision F comparison results into one new, redacted report. Reads no Music state."""

import hashlib
import os
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
BUNDLE = Path(__file__).resolve().parent
sys.path.insert(0, str(BUNDLE))
from m11_collect import redact  # noqa: E402  (the redaction rules of the M11 collector, unchanged)

PHASES = ("unchanged", "after-removal")
SETUP_LOGS = ("bundle-check.log", "staging-dates.log", "validate-staging.log", "doctor.log", "add-dry-run.log",
              "add.log", "removed-file.txt")


def section(title, text):
    return f"== {title} ==\n{text.rstrip()}\n\n"


def main(arguments):
    if len(arguments) != 1:
        print("Usage: python3 df_collect.py /Users/Shared/ilibrary-decision-f-comparison-v4-report.txt", file=sys.stderr)
        return 2
    output = Path(arguments[0])
    homes = {str(Path.home()), os.path.realpath(str(Path.home()))}
    parts = [section("sources", (BUNDLE / "SOURCES").read_text())]
    check = subprocess.run(["/bin/sh", "-c", "grep -v '  staging/' SHA256SUMS | shasum -a 256 -c --quiet -"],
                           cwd=BUNDLE, capture_output=True, text=True)
    parts.append(section("bundle checksums (staging excluded)", "PASS" if check.returncode == 0 else
                         "FAIL\n" + check.stdout + check.stderr))
    results = BUNDLE / "results"
    for name in SETUP_LOGS:
        path = results / name
        parts.append(section(name, path.read_text(errors="replace") if path.is_file() else "NOT RUN"))
    for phase in PHASES:
        folder = results / phase
        if not folder.is_dir():
            parts.append(section(f"phase {phase}", "NOT RUN"))
            continue
        for path in sorted(folder.iterdir()):
            if path.is_file():
                parts.append(section(f"{phase}/{path.name}", path.read_text(errors="replace")))
    text = redact("".join(parts), homes)
    digest = hashlib.sha256(text.encode()).hexdigest()
    try:
        with open(output, "x", encoding="utf-8") as handle:
            handle.write(text)
    except FileExistsError:
        print(f"{output} exists; it is not overwritten.", file=sys.stderr)
        return 1
    print(f"Report written: {output} (SHA-256 {digest})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
