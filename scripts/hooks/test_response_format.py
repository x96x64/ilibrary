import json
import subprocess
import sys
import unittest
from pathlib import Path

import response_format as hook

SCRIPT = Path(__file__).with_name("response_format.py")

# A fragment of the noncompliant M11 preparation report of October 20, 2026, with its original list syntax.
M11_REPORT_FRAGMENT = """\
Time Machine is the main gap: the procedure does not mention it, and the code does not protect against it.

- **Best choice:** a drive, or a volume on a drive, that is not a Time Machine destination.
- **Ejection timing:** if Time Machine starts a backup while the drive is connected, the eject in Step 11 \
may be blocked until it finishes.

Follow the procedure in `docs/m11-qualification.md` exactly.

1. Eject the drive while still in your usual user, log out completely rather than switching users.
2. In Steps 1 to 6, verify and extract the bundle, restore the synthetic dates, and create a new library.
"""

COMPLIANT = """\
The branch `m11-backup-inventory` is clean at `c8649fe`, with fourteen unpublished commits above `main`. The \
bundle in `/Users/Shared` matches its recorded SHA-256, and its procedure is byte-identical to the repository \
copy. The re-examined device checks refuse a backup on the same whole disk, and the *restoration* directory \
must be completely empty; a well-known side effect of Finder is a hidden `.DS_Store` file.
Read-only commands such as `diskutil info` and `tmutil destinationinfo` report the volume's role.

The validator was run with the following command, which printed nothing and exited with status 0:

```sh
printf '%s' '{"last_assistant_message": "- item"}' | python3 scripts/hooks/response_format.py
# - this comment and the list below are literal code
1. not a list
| a | b |
| --- | --- |
**not bold**
```

M11 remains awaiting the maintainer-operated qualification. The next action is the maintainer's separate-user \
run, which requires the maintainer and is not authorized for an agent; no push or publication is authorized.
"""


def rules(message):
    return [rule for _, rule, _ in hook.find_violations(message)]


def run(stdin):
    return subprocess.run(
        [sys.executable, "-I", str(SCRIPT)], input=stdin, capture_output=True, text=True, timeout=30)


class RejectionTests(unittest.TestCase):
    def test_actual_m11_report_fragment(self):
        found = rules(M11_REPORT_FRAGMENT)
        self.assertEqual(found.count("bullet list item"), 2)
        self.assertEqual(found.count("numbered list item"), 2)
        self.assertEqual(found.count("bold emphasis"), 2)

    def test_headings(self):
        self.assertEqual(rules("# Summary\n\nText follows here."), ["Markdown heading"])
        self.assertEqual(rules("### Verification\nText."), ["Markdown heading"])
        self.assertEqual(rules("Summary\n=======\n\nText."), ["Markdown heading (setext underline)"])
        self.assertEqual(rules("Summary\n---\n\nText."), ["Markdown heading (setext underline)"])

    def test_numbered_lists(self):
        self.assertEqual(rules("1. First.\n2. Second."), ["numbered list item"] * 2)
        self.assertEqual(rules("Steps follow.\n1) First."), ["numbered list item"])
        self.assertEqual(rules("Steps follow.\n\n3. Third."), ["numbered list item"])

    def test_bullets_and_checklists(self):
        self.assertEqual(rules("* one\n+ two"), ["bullet list item"] * 2)
        self.assertEqual(rules("Intro text.\n- item"), ["bullet list item"])
        self.assertEqual(rules("- [ ] open\n- [x] done"), ["checklist item"] * 2)
        self.assertEqual(rules("> - quoted item"), ["bullet list item"])

    def test_tables(self):
        self.assertIn("Markdown table", rules("| Gate | Evidence |\n| --- | :---: |\n| a | b |"))
        self.assertIn("Markdown table", rules("Gate | Evidence\n--- | ---\na | b"))

    def test_bold(self):
        self.assertEqual(rules("This is **important** text."), ["bold emphasis"])
        self.assertEqual(rules("This is __very important__ text."), ["bold emphasis"])
        self.assertEqual(rules("This is ***both*** at once."), ["bold emphasis"])

    def test_decorative_elements(self):
        self.assertEqual(rules("Text.\n\n---\n\nMore text."), ["decorative separator"])
        self.assertEqual(rules("Text.\n\n* * *\n\nMore text."), ["decorative separator"])
        self.assertEqual(rules("Text.\n\n────\n\nMore text."), ["decorative separator"])
        self.assertEqual(rules("All checks passed ✅ today."), ["emoji or pictograph"])

    def test_standalone_title(self):
        self.assertEqual(rules("Verification Results\n\nThe tests passed."), ["standalone title"])

    def test_unterminated_fence(self):
        self.assertEqual(rules("Text.\n\n```sh\nls\n"), ["unterminated code fence"])


class AcceptanceTests(unittest.TestCase):
    def test_compliant_prose_with_italic_code_and_fence(self):
        self.assertEqual(hook.find_violations(COMPLIANT), [])

    def test_hyphens_identifiers_and_operators(self):
        text = (
            "The well-known --dry-run option and -1 exit codes, the `__init__` method, snake_case names, "
            "and a ** b with *emphasis* or _emphasis_ are ordinary prose.\n"
            "-x is a flag, and 2026-10-20 is a date written at the start of a wrapped line."
        )
        self.assertEqual(hook.find_violations(text), [])

    def test_wrapped_number_continuing_a_paragraph(self):
        self.assertEqual(hook.find_violations("This was recorded under Decision\n44. It applies to all."), [])

    def test_inline_code_hides_syntax(self):
        self.assertEqual(hook.find_violations("A heading is written as `# Title` and bold as `**x**`."), [])

    def test_quoted_examples(self):
        text = 'The prohibited forms include "- item", "1. step", and the pipe in "a | b" within a sentence.'
        self.assertEqual(hook.find_violations(text), [])

    def test_tilde_fence_and_longer_fence(self):
        text = "Output follows.\n\n~~~\n## literal\n~~~\n\n````\n```\n- inner\n```\n````\n\nThe end of the report."
        self.assertEqual(hook.find_violations(text), [])

    def test_multiline_paragraphs(self):
        text = "A paragraph that\nspans several lines\nwithout any list.\n\nA second paragraph that\nalso spans lines."
        self.assertEqual(hook.find_violations(text), [])


class DecisionTests(unittest.TestCase):
    def test_block_on_first_violation(self):
        result = hook.decide({"stop_hook_active": False, "last_assistant_message": M11_REPORT_FRAGMENT})
        self.assertEqual(result["decision"], "block")
        self.assertIn("Decision 44", result["reason"])
        self.assertIn("bullet list item", result["reason"])

    def test_no_second_block_during_continuation(self):
        result = hook.decide({"stop_hook_active": True, "last_assistant_message": M11_REPORT_FRAGMENT})
        self.assertNotIn("decision", result)
        self.assertIn("not blocked again", result["systemMessage"])

    def test_compliant_continuation_is_silent(self):
        self.assertIsNone(hook.decide({"stop_hook_active": True, "last_assistant_message": COMPLIANT}))

    def test_empty_and_missing_fields(self):
        self.assertIsNone(hook.decide({}))
        self.assertIsNone(hook.decide({"last_assistant_message": ""}))
        self.assertIsNone(hook.decide({"last_assistant_message": "   \n"}))
        self.assertIsNone(hook.decide({"last_assistant_message": None}))
        self.assertIsNone(hook.decide([]))

    def test_reason_is_bounded(self):
        message = "\n".join(f"- item {index}" for index in range(50))
        reason = hook.decide({"last_assistant_message": message})["reason"]
        self.assertIn("and 42 more", reason)
        self.assertNotIn("item 49", reason)


class ProcessTests(unittest.TestCase):
    """Runs the script as Claude Code does, with the documented Stop input on standard input."""

    def event(self, message, active=False):
        return json.dumps({
            "session_id": "synthetic", "transcript_path": "/nonexistent/transcript.jsonl", "cwd": "/tmp",
            "permission_mode": "default", "hook_event_name": "Stop", "stop_hook_active": active,
            "last_assistant_message": message,
        })

    def test_blocks_noncompliant_response(self):
        completed = run(self.event(M11_REPORT_FRAGMENT))
        self.assertEqual(completed.returncode, 0)
        output = json.loads(completed.stdout)
        self.assertEqual(output["decision"], "block")
        self.assertTrue(output["reason"])
        self.assertEqual(completed.stderr, "")

    def test_allows_compliant_response(self):
        completed = run(self.event(COMPLIANT))
        self.assertEqual((completed.returncode, completed.stdout, completed.stderr), (0, "", ""))

    def test_continuation_does_not_block(self):
        completed = run(self.event(M11_REPORT_FRAGMENT, active=True))
        self.assertEqual(completed.returncode, 0)
        self.assertNotIn("decision", json.loads(completed.stdout))

    def test_malformed_and_missing_input(self):
        for stdin in ("", "not json", "[]", json.dumps({"hook_event_name": "Stop"})):
            completed = run(stdin)
            self.assertEqual((completed.returncode, completed.stdout), (0, ""), stdin)

    def test_message_is_not_executed(self):
        marker = Path("/tmp/ilibrary-response-format-marker-should-not-exist")
        message = f"$(touch {marker}) `touch {marker}`\n\n```sh\ntouch {marker}\n```\n\nText ends here."
        run(self.event(message))
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
