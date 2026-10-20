import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path
from unittest import mock

import response_display as display

SCRIPT = Path(__file__).with_name("response_display.py")
NOTICE = display.NOTICE + "\n"

M11_NUMBERED = """\
1. The bulk and per-track readers agreed on all 16 fields of all 12 tracks, with no fallback.
2. The collector wrote the report atomically.
3. The volume identifiers were redacted.
4. The library was empty at the start.
5. The sample tracks used synthetic dates.
6. The report hash was recorded.
7. No personal library was touched.
"""


class TempDirectoryCase(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        patcher = mock.patch.object(tempfile, "tempdir", self.temporary.name)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.directory = os.path.join(self.temporary.name, f"ilibrary-response-display-{os.getuid()}")

    def event(self, delta, message_id, index=0, final=True):
        return {"hook_event_name": "MessageDisplay", "turn_id": "turn-1", "message_id": message_id,
                "index": index, "final": final, "delta": delta}

    def run_single(self, text):
        """Returns the displayed text for a single non-interactive call, or the original when unchanged."""
        result = display.handle(self.event(text, str(uuid.uuid4())))
        return text if result is None else result

    def stream(self, batches, message_id=None):
        message_id = message_id or str(uuid.uuid4())
        shown = []
        for number, batch in enumerate(batches):
            result = display.handle(self.event(batch, message_id, number, number == len(batches) - 1))
            shown.append(batch if result is None else result)
        return shown


class WithholdingTests(TempDirectoryCase):
    def test_numbered_list_of_findings_is_replaced_by_one_notice(self):
        self.assertEqual(self.run_single(M11_NUMBERED), NOTICE)

    def test_bullets_with_italic_labels(self):
        text = ("- *Stage and counts:* the stage is `prepared`, with 12 files totalling 335,604 bytes\n"
                "- *Readers:* both agreed\n")
        self.assertEqual(self.run_single(text), NOTICE)

    def test_plain_bullets(self):
        self.assertEqual(self.run_single("- the two Music readers agreed field by field\n* another\n+ third\n"),
                         NOTICE)

    def test_table_with_header_and_delimiter(self):
        text = "| Item | Value |\n| --- | --- |\n| Size | 12 |\n"
        self.assertEqual(self.run_single(text), NOTICE)

    def test_table_delimiter_without_outer_pipes(self):
        self.assertEqual(self.run_single("Item | Value\n--- | ---\n"), "Item | Value\n" + NOTICE)

    def test_html_markup_lines(self):
        for line in ("<table><tr><td>x</td></tr></table>", "<ul>", "  <li>item</li>", "<h2>Title</h2>", "<hr>"):
            self.assertEqual(self.run_single(line + "\n"), NOTICE, line)

    def test_bold_markers_are_removed(self):
        self.assertEqual(self.run_single("This is **important** and __also__ done.\n"),
                         "This is important and also done.\n")
        self.assertEqual(self.run_single("A <strong>strong</strong> and <b>bold</b> word.\n"),
                         "A strong and bold word.\n")

    def test_identifiers_with_underscores_are_preserved(self):
        text = "The names snake_case_name and a__b stay.\n"
        self.assertEqual(self.run_single(text), text)

    def test_bold_inside_inline_code_is_preserved(self):
        text = "Use `**kwargs` and `__init__` here.\n"
        self.assertEqual(self.run_single(text), text)
        self.assertEqual(self.run_single("**Run `a**b` now** please\n"), "Run `a**b` now please\n")

    def test_unicode_bullets_and_headings_and_separators(self):
        for line in ("• item", "# Heading", "## Heading", "---", "* * *", "────"):
            self.assertEqual(self.run_single("Intro.\n\n" + line + "\n"), "Intro.\n\n" + NOTICE, line)

    def test_setext_underline_after_prose(self):
        self.assertEqual(self.run_single("Some words\n=====\n"), "Some words\n" + NOTICE)

    def test_checklist_item(self):
        self.assertEqual(self.run_single("- [ ] task\n- [x] done\n"), NOTICE)

    def test_emoji_removed(self):
        self.assertEqual(self.run_single("Done \U0001F600 and ✅ finished.\n"), "Done  and  finished.\n")

    def test_label_lines_second_and_later_withheld(self):
        text = "Stage: prepared\nCount: 12\nBytes: 335\n"
        self.assertEqual(self.run_single(text), "Stage: prepared\n" + NOTICE)

    def test_single_label_line_passes(self):
        text = "Stage: prepared and nothing else\n"
        self.assertEqual(self.run_single(text), text)

    def test_label_run_spans_blank_lines(self):
        text = "Stage: prepared\n\nCount: 12\n\nBytes: 335\n"
        self.assertEqual(self.run_single(text), "Stage: prepared\n\n" + NOTICE + "\n")

    def test_loose_list_yields_one_notice(self):
        text = "The findings follow.\n\n- first finding.\n\n- second finding.\n\nThe report ends here.\n"
        self.assertEqual(self.run_single(text),
                         "The findings follow.\n\n" + NOTICE + "\n\nThe report ends here.\n")

    def test_lettered_items(self):
        self.assertEqual(self.run_single("a. first thing\nb. second thing\n"), "a. first thing\n" + NOTICE)

    def test_blockquote_prefix_is_classified_and_kept(self):
        self.assertEqual(self.run_single("> - item\n> Text **bold**\n"), NOTICE + "> Text bold\n")

    def test_line_endings_are_preserved(self):
        self.assertEqual(self.run_single("A **b**\r\nC **d**\r\n"), "A b\r\nC d\r\n")
        self.assertEqual(self.run_single("A **b**\r\n- x\r\n"), "A b\r\n" + NOTICE)


class PassingTests(TempDirectoryCase):
    def assertUnchanged(self, text):
        result = display.handle(self.event(text, str(uuid.uuid4())))
        self.assertIsNone(result, text)

    def test_long_prose_italics_code_urls_and_punctuation(self):
        self.assertUnchanged(
            "The branch `m11-backup-inventory` is clean, and the *restoration* directory must be empty; see "
            "https://example.com/a_b/c?x=1&y=2 for details (it is not required).\n\n"
            "A second paragraph, with \"quotes\", an em dash, and a figure of 3.5 percent.\n")

    def test_wrapped_number_continues_paragraph(self):
        self.assertUnchanged("Decision\n44. It applies.\n")

    def test_fenced_code_blocks_pass_unchanged(self):
        self.assertUnchanged("Run this:\n\n```sh\n- item\n1. one\n| a | b |\n| --- | --- |\n**bold**\n# c\n```\n\n"
                             "Then stop.\n")

    def test_tilde_fence_and_longer_closing_fence(self):
        self.assertUnchanged("~~~\n- x\n```\n- y\n~~~~\nDone.\n")

    def test_empty_delta(self):
        self.assertUnchanged("")


class StreamingTests(TempDirectoryCase):
    def test_fence_across_three_batches(self):
        batches = ["Intro text.\n```\n", "- item\n| a | b |\n**bold**\n", "```\n- real bullet\n"]
        shown = self.stream(batches)
        self.assertEqual(shown[0], batches[0])
        self.assertEqual(shown[1], batches[1])
        self.assertEqual(shown[2], "```\n" + NOTICE)

    def test_table_header_and_delimiter_in_separate_batches(self):
        shown = self.stream(["Item | Value\n", "--- | ---\n", "Text.\n"])
        self.assertEqual(shown, ["Item | Value\n", NOTICE, "Text.\n"])

    def test_withheld_run_spanning_batches_has_one_notice(self):
        shown = self.stream(["1. one\n2. two\n", "3. three\n", "4. four\n"])
        self.assertEqual(shown, [NOTICE, "", ""])

    def test_notice_repeats_after_displayed_line(self):
        shown = self.stream(["- a\n", "Prose line.\n", "- b\n"])
        self.assertEqual(shown, [NOTICE, "Prose line.\n", NOTICE])

    def test_numbered_item_interruption_state_across_batches(self):
        self.assertEqual(self.stream(["Decision\n", "44. It applies.\n"]), ["Decision\n", "44. It applies.\n"])
        self.assertEqual(self.stream(["- a\n", "2. b\n"]), [NOTICE, ""])

    def test_label_run_across_batches(self):
        self.assertEqual(self.stream(["Stage: one\n", "Count: two\n", "Bytes: three\n"]),
                         ["Stage: one\n", NOTICE, ""])

    def test_empty_final_delta(self):
        shown = self.stream(["- a\n", ""])
        self.assertEqual(shown, [NOTICE, ""])
        self.assertEqual(os.listdir(self.directory), [])

    def test_final_batch_ending_mid_line(self):
        shown = self.stream(["Text.\n", "- last item without newline"])
        self.assertEqual(shown, ["Text.\n", NOTICE])
        shown = self.stream(["Text.\n", "End **bold"])
        self.assertEqual(shown, ["Text.\n", "End **bold"])

    def test_two_interleaved_messages(self):
        first, second = str(uuid.uuid4()), str(uuid.uuid4())
        self.assertIsNone(display.handle(self.event("```\n", first, 0, False)))
        self.assertEqual(display.handle(self.event("- a\n", second, 0, False)), NOTICE)
        self.assertIsNone(display.handle(self.event("- inside fence\n", first, 1, False)))
        self.assertEqual(display.handle(self.event("- b\n", second, 1, False)), "")
        self.assertIsNone(display.handle(self.event("```\n", first, 2, True)))
        self.assertEqual(display.handle(self.event("", second, 2, True)), None)

    def test_state_removed_after_final(self):
        message_id = str(uuid.uuid4())
        display.handle(self.event("- a\n", message_id, 0, False))
        self.assertEqual(os.listdir(self.directory), [message_id + ".json"])
        display.handle(self.event("- b\n", message_id, 1, True))
        self.assertEqual(os.listdir(self.directory), [])

    def test_state_contains_no_message_text(self):
        message_id = str(uuid.uuid4())
        display.handle(self.event("secret words here\n- hidden item\n", message_id, 0, False))
        content = Path(self.directory, message_id + ".json").read_text()
        self.assertNotIn("secret", content)
        self.assertNotIn("hidden", content)
        self.assertEqual(os.stat(self.directory).st_mode & 0o777, 0o700)

    def test_stale_state_removed_on_first_batch(self):
        old = Path(self.directory)
        old.mkdir(mode=0o700)
        stale = old / (str(uuid.uuid4()) + ".json")
        fresh = old / (str(uuid.uuid4()) + ".json")
        stale.write_text("{}")
        fresh.write_text("{}")
        past = time.time() - 7200
        os.utime(stale, (past, past))
        display.handle(self.event("Text.\n", str(uuid.uuid4()), 0, False))
        self.assertFalse(stale.exists())
        self.assertTrue(fresh.exists())

    def test_first_batch_ignores_leftover_state(self):
        message_id = str(uuid.uuid4())
        display.handle(self.event("```\n", message_id, 0, False))
        self.assertEqual(display.handle(self.event("- a\n", message_id, 0, True)), NOTICE)


class RobustnessTests(TempDirectoryCase):
    def test_malformed_events_are_ignored(self):
        good = self.event("- a\n", str(uuid.uuid4()))
        self.assertEqual(display.handle(good), NOTICE)
        for key, value in (("hook_event_name", "Stop"), ("delta", 5), ("delta", None), ("message_id", 3),
                           ("index", "0"), ("index", True), ("index", -1), ("final", "yes"), ("final", 1)):
            bad = dict(good)
            bad[key] = value
            self.assertIsNone(display.handle(bad), (key, value))
        for key in ("hook_event_name", "delta", "message_id", "index", "final"):
            bad = dict(good)
            del bad[key]
            self.assertIsNone(display.handle(bad), key)
        for bad in (None, [], "text", 5):
            self.assertIsNone(display.handle(bad))

    def test_invalid_message_id_is_processed_statelessly(self):
        for message_id in ("../../etc/passwd", "not-a-uuid", "", "a" * 36, str(uuid.uuid4()) + "/x"):
            self.assertEqual(display.handle(self.event("- a\n", message_id, 0, False)), NOTICE)
            self.assertFalse(os.path.exists(self.directory) and os.listdir(self.directory), message_id)
        self.assertFalse(os.path.exists(os.path.join(self.temporary.name, "etc")))

    def test_symbolic_link_directory_is_refused(self):
        target = os.path.join(self.temporary.name, "elsewhere")
        os.mkdir(target)
        os.symlink(target, self.directory)
        message_id = str(uuid.uuid4())
        self.assertEqual(display.handle(self.event("```\n", message_id, 0, False)), None)
        self.assertEqual(display.handle(self.event("- a\n", message_id, 1, False)), NOTICE)
        self.assertEqual(os.listdir(target), [])

    def test_symbolic_link_state_file_is_refused(self):
        message_id = str(uuid.uuid4())
        display.handle(self.event("Text.\n", message_id, 0, False))
        target = os.path.join(self.temporary.name, "target.json")
        Path(target).write_text(json.dumps({"fence": "```"}))
        path = os.path.join(self.directory, message_id + ".json")
        os.unlink(path)
        os.symlink(target, path)
        self.assertEqual(display.handle(self.event("- a\n", message_id, 1, False)), NOTICE)

    def test_corrupt_state_file_is_ignored(self):
        message_id = str(uuid.uuid4())
        display.handle(self.event("Text.\n", message_id, 0, False))
        Path(self.directory, message_id + ".json").write_text('{"fence": 5}')
        self.assertEqual(display.handle(self.event("- a\n", message_id, 1, False)), NOTICE)

    def test_group_writable_directory_is_refused(self):
        os.mkdir(self.directory, 0o700)
        os.chmod(self.directory, 0o777)
        message_id = str(uuid.uuid4())
        self.assertIsNone(display.handle(self.event("```\n", message_id, 0, False)))
        self.assertEqual(display.handle(self.event("- a\n", message_id, 1, False)), NOTICE)
        self.assertEqual(os.listdir(self.directory), [])


class SubprocessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)

    def run_hook(self, payload, raw=None):
        environment = {key: value for key, value in os.environ.items() if key != "PYTHONPATH"}
        environment["TMPDIR"] = self.temporary.name
        data = raw if raw is not None else json.dumps(payload)
        return subprocess.run([sys.executable, "-I", str(SCRIPT)], input=data, capture_output=True, text=True,
                              env=environment, check=False, cwd=self.temporary.name)

    def payload(self, delta, index=0, final=True, message_id=None):
        return {"hook_event_name": "MessageDisplay", "turn_id": "t", "message_id": message_id or str(uuid.uuid4()),
                "index": index, "final": final, "delta": delta}

    def test_replacement_json(self):
        result = self.run_hook(self.payload("Intro.\n" + M11_NUMBERED + "A **bold** end.\n"))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, "")
        output = json.loads(result.stdout)
        self.assertEqual(output["hookSpecificOutput"]["hookEventName"], "MessageDisplay")
        self.assertEqual(output["hookSpecificOutput"]["displayContent"], "Intro.\n" + NOTICE + "A bold end.\n")

    def test_unchanged_message_prints_nothing(self):
        result = self.run_hook(self.payload("Plain prose, with *italics* and `code`.\n"))
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

    def test_streaming_through_state_directory(self):
        message_id = str(uuid.uuid4())
        first = self.run_hook(self.payload("```\n- a\n", 0, False, message_id))
        self.assertEqual(first.stdout, "")
        second = self.run_hook(self.payload("```\n- b\n", 1, True, message_id))
        self.assertEqual(json.loads(second.stdout)["hookSpecificOutput"]["displayContent"], "```\n" + NOTICE)
        self.assertEqual(second.stderr, "")
        directory = os.path.join(self.temporary.name, f"ilibrary-response-display-{os.getuid()}")
        self.assertEqual(os.listdir(directory), [])

    def test_malformed_input_prints_nothing(self):
        for raw in ("not json", "", "[]", "{}", json.dumps({"hook_event_name": "MessageDisplay"}), "\xff\xfe"):
            result = self.run_hook(None, raw=raw)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""), raw)

    def test_works_without_script_directory_on_path(self):
        result = self.run_hook(self.payload("- a\n"))
        self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]["displayContent"], NOTICE)


if __name__ == "__main__":
    unittest.main()
