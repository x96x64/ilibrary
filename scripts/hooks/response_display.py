#!/usr/bin/env python3
"""MessageDisplay hook that withholds prohibited response formatting from the screen (AGENTS.md, Decision 44).

The hook is a preventive, display-only companion of the Stop hook `response_format.py`. For each batch of
newly completed lines it withholds lines that the Stop hook would classify as headings, separators, list
items, tables, or HTML table, list, heading, or rule markup, replaces each contiguous run of them with one
notice line, removes bold markers and emoji, and withholds the second and later lines of a run of
label-and-value or lettered lines. Fenced code blocks and inline code spans are never altered. The transcript
and the model keep the original text; the hook only changes what is displayed.

Between batches of one message the hook keeps only a small structural state (fence marker, previous-line
flags, list and run flags, and whether a notice is open) in a JSON file named after the message identifier
inside a private per-user directory of the temporary directory. It never stores, logs, or executes message
text. Any malformed input or error produces no output and exit status 0, so that the original is displayed.
"""

import json
import os
import re
import stat
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import response_format as rf  # noqa: E402

NOTICE = ("[Formatting that the project response policy prohibits was withheld from display; "
          "the full text remains in the transcript.]")
UUID = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
LINE = re.compile(r"[^\n]*\n|[^\n]+")
STALE_SECONDS = 3600
SENTINEL = "\x00"
LIST_RULES = ("bullet list item", "bullet list item (glyph)", "numbered list item", "checklist item")
HTML_BOLD = "bold emphasis (HTML)"
HTML_STRUCTURES = tuple(pattern for pattern, rule in rf.HTML_TAGS if rule != HTML_BOLD)
HTML_BOLD_TAG = next(pattern for pattern, rule in rf.HTML_TAGS if rule == HTML_BOLD)


def initial_state():
    return {"fence": None, "prev": False, "prev_pipe": False, "prev_lead_pipe": False, "in_list": False,
            "run_kind": None, "notice": False}


def valid_state(state):
    if not isinstance(state, dict):
        return None
    base = initial_state()
    for key, default in base.items():
        value = state.get(key, default)
        if key == "fence":
            if value is not None and not (isinstance(value, str) and re.fullmatch(r"`{3,}|~{3,}", value)):
                return None
        elif key == "run_kind":
            if value not in (None, "label-and-value list", "lettered list item"):
                return None
        elif not isinstance(value, bool):
            return None
        base[key] = value
    return base


def classify(line, state):
    """Returns (rule, withheld) for a prose line outside a fence, using the Stop hook's rules."""
    previous = state["prev"]
    interrupts = previous and not state["in_list"]
    rule = None
    if rf.ATX_HEADING.match(line):
        rule = "Markdown heading"
    elif (rf.SETEXT_UNDERLINE.match(line) or rf.SETEXT_DASHES.match(line)) and previous:
        rule = "Markdown heading (setext underline)"
    elif rf.THEMATIC_BREAK.match(line) or rf.BOX_DRAWING_LINE.match(line):
        rule = "decorative separator"
    elif rf.TABLE_DELIMITER.match(line) and previous and state["prev_pipe"]:
        rule = "Markdown table"
    elif rf.SINGLE_COLUMN_DELIMITER.match(line) and previous and state["prev_lead_pipe"]:
        rule = "Markdown table"
    elif rf.TASK_ITEM.match(line):
        rule = "checklist item"
    elif rf.GLYPH_BULLET.match(line):
        rule = "bullet list item (glyph)"
    else:
        bullet = rf.BULLET_ITEM.match(line)
        ordered = rf.ORDERED_ITEM.match(line)
        if bullet and not (interrupts and bullet.group(1) is None):
            rule = "bullet list item"
        elif ordered and (not interrupts or ordered.group(1) == "1"):
            rule = "numbered list item"
    withheld = rule is not None
    if not withheld:
        stripped = line.strip()
        if stripped.startswith("|") and stripped.endswith("|") and stripped.count("|") >= 2:
            withheld = True
        else:
            bare = rf.INLINE_CODE.sub(" ", line)
            withheld = any(pattern.search(bare) for pattern in HTML_STRUCTURES)
    return rule, withheld


def clean(line):
    """Removes bold markers and emoji outside inline code spans from one line."""
    if SENTINEL in line:
        return line
    spans = []

    def hide(match):
        spans.append(match.group(0))
        return SENTINEL + str(len(spans) - 1) + SENTINEL

    text = rf.INLINE_CODE.sub(hide, line)
    text = rf.BOLD_STARS.sub(lambda match: match.group(0)[2:-2], text)
    text = rf.BOLD_UNDERSCORES.sub(lambda match: match.group(1), text)
    text = HTML_BOLD_TAG.sub("", text)
    text = "".join(character for character in text if not rf.is_emoji(character))
    return re.sub(SENTINEL + r"(\d+)" + SENTINEL, lambda match: spans[int(match.group(1))], text)


def process(delta, state):
    """Returns the text to display for one batch and updates the structural state in place."""
    output = []
    for raw in LINE.findall(delta):
        body = raw.rstrip("\n").rstrip("\r")
        ending = raw[len(body):]
        line = rf.strip_blockquote(body)
        match = rf.FENCE.match(line)
        if state["fence"] is not None:
            if match and match.group(1)[0] == state["fence"][0] and len(match.group(1)) >= len(state["fence"]) \
                    and match.group(2).strip() == "":
                state["fence"] = None
            output.append(raw)
            continue
        if match and not (match.group(1)[0] == "`" and "`" in match.group(2)):
            state.update(fence=match.group(1), prev=False, prev_pipe=False, prev_lead_pipe=False,
                         in_list=False, run_kind=None, notice=False)
            output.append(raw)
            continue
        if line.strip() == "":
            # An open notice stays open across blank lines, so that a loose list yields one notice.
            state.update(prev=False, prev_pipe=False, prev_lead_pipe=False, in_list=False)
            output.append(raw)
            continue
        rule, withheld = classify(line, state)
        candidate = None
        if not withheld:
            if rf.LABEL_LINE.match(line) and len(line.split()) < rf.LABEL_LINE_MAX_WORDS:
                candidate = "label-and-value list"
            elif rf.LETTERED_ITEM.match(line):
                candidate = "lettered list item"
            if candidate is not None and state["run_kind"] == candidate:
                withheld = True
        if rule in LIST_RULES:
            state["in_list"] = True
        state["run_kind"] = candidate
        state.update(prev=True, prev_pipe="|" in line, prev_lead_pipe=line.lstrip().startswith("|"))
        if withheld:
            if not state["notice"]:
                output.append(NOTICE + "\n")
                state["notice"] = True
            continue
        state["notice"] = False
        output.append(clean(body) + ending)
    return "".join(output)


def state_directory():
    """Returns the private state directory, or None when it cannot be used safely."""
    path = os.path.join(tempfile.gettempdir(), f"ilibrary-response-display-{os.getuid()}")
    try:
        os.lstat(path)
    except FileNotFoundError:
        os.mkdir(path, 0o700)
    info = os.lstat(path)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
        return None
    return path


def load_state(directory, message_id):
    try:
        descriptor = os.open(os.path.join(directory, message_id + ".json"), os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return None
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 4096:
            return None
        return valid_state(json.loads(os.read(descriptor, 4096).decode("utf-8")))
    except (OSError, ValueError):
        return None
    finally:
        os.close(descriptor)


def save_state(directory, message_id, state):
    temporary = os.path.join(directory, f".{message_id}.{os.getpid()}.tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(state, handle)
        os.replace(temporary, os.path.join(directory, message_id + ".json"))
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def remove_state(directory, message_id):
    try:
        os.unlink(os.path.join(directory, message_id + ".json"))
    except OSError:
        pass


def remove_stale(directory):
    cutoff = time.time() - STALE_SECONDS
    with os.scandir(directory) as entries:
        for entry in entries:
            try:
                if not (entry.name.endswith(".json") or entry.name.endswith(".tmp")):
                    continue
                info = entry.stat(follow_symlinks=False)
                if stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and info.st_mtime < cutoff:
                    os.unlink(entry.path)
            except OSError:
                continue


def handle(event):
    """Returns the replacement display text for a MessageDisplay event, or None to keep the original."""
    if not isinstance(event, dict) or event.get("hook_event_name") != "MessageDisplay":
        return None
    delta = event.get("delta")
    message_id = event.get("message_id")
    index = event.get("index")
    final = event.get("final")
    if not isinstance(delta, str) or not isinstance(message_id, str) or not isinstance(final, bool) \
            or isinstance(index, bool) or not isinstance(index, int) or index < 0:
        return None
    directory = None
    state = None
    if UUID.fullmatch(message_id):
        message_id = message_id.lower()
        try:
            directory = state_directory()
        except OSError:
            directory = None
        if directory is not None:
            if index == 0:
                try:
                    remove_stale(directory)
                except OSError:
                    pass
            else:
                state = load_state(directory, message_id)
    if state is None:
        state = initial_state()
    result = process(delta, state)
    if directory is not None:
        try:
            if final:
                remove_state(directory, message_id)
            else:
                save_state(directory, message_id, state)
        except OSError:
            pass
    return result if result != delta else None


def main():
    try:
        event = json.loads(sys.stdin.buffer.read().decode("utf-8"))
        result = handle(event)
        if result is not None:
            sys.stdout.write(json.dumps({"hookSpecificOutput": {"hookEventName": "MessageDisplay",
                                                                "displayContent": result}}))
            sys.stdout.write("\n")
    except BaseException:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
