#!/usr/bin/env python3
"""Stop hook that enforces the response format of AGENTS.md (Agent Responses, Decision 44).

The hook reads the documented Stop input from standard input and inspects only `last_assistant_message`.
A response that contains a Markdown heading, a list item, a table, bold emphasis, a decorative separator,
an emoji, a standalone title, or an unterminated code fence is blocked once with a corrective reason.
Content inside fenced code blocks and inline code spans is not inspected. The message is treated as untrusted
text: it is never executed, written to disk, or echoed in full.

When `stop_hook_active` is true, the turn is already a continuation caused by a Stop hook. The hook then never
blocks again; if the corrected response still violates the format, it reports the violation to the maintainer
through `systemMessage` and lets the turn end. Each response is therefore blocked at most once by this hook,
well within Claude Code's cap of eight consecutive continuations.

Exit status is always 0. Invalid input is ignored rather than blocked, so that a malformed event cannot
prevent a session from ending.
"""

import json
import re
import sys
import unicodedata

MAX_REPORTED = 8
EXCERPT_LENGTH = 48

FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
ATX_HEADING = re.compile(r"^ {0,3}#{1,6}(?:[ \t]|$)")
SETEXT_UNDERLINE = re.compile(r"^ {0,3}=+[ \t]*$")
SETEXT_DASHES = re.compile(r"^ {0,3}-+[ \t]*$")
THEMATIC_BREAK = re.compile(r"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$")
BOX_DRAWING_LINE = re.compile(r"^[ \t]*[─-╿▀-▟]{3,}[ \t]*$")
BULLET_ITEM = re.compile(r"^ {0,3}[-*+](?:[ \t]+(\S)|[ \t]*$)")
ORDERED_ITEM = re.compile(r"^ {0,3}(\d{1,9})[.)](?:[ \t]+\S|[ \t]*$)")
TASK_ITEM = re.compile(r"^ {0,3}(?:[-*+]|\d{1,9}[.)])[ \t]+\[[ xX]\]")
TABLE_DELIMITER = re.compile(r"^ {0,3}\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)+\|?[ \t]*$")
BLOCKQUOTE = re.compile(r"^ {0,3}>[ \t]?")
INLINE_CODE = re.compile(r"(`+)(?!`)(.+?)(?<!`)\1(?!`)", re.DOTALL)
BOLD_STARS = re.compile(r"\*\*(?=\S)(?:.*?\S)?\*\*")
BOLD_UNDERSCORES = re.compile(r"(?<![A-Za-z0-9_])__(?=\S)(.*?\S)__(?![A-Za-z0-9_])")
TITLE_END = re.compile(r"""[.!?:;,)\]}"'`’”]$""")

EMOJI_RANGES = (
    (0x1F000, 0x1FAFF),
    (0x2600, 0x27BF),
    (0x2B00, 0x2BFF),
    (0xFE0F, 0xFE0F),
)


def is_emoji(character):
    point = ord(character)
    return any(low <= point <= high for low, high in EMOJI_RANGES)


def excerpt(line):
    text = " ".join(line.split())
    return text if len(text) <= EXCERPT_LENGTH else text[: EXCERPT_LENGTH - 3] + "..."


def strip_blockquote(line):
    while True:
        match = BLOCKQUOTE.match(line)
        if not match:
            return line
        line = line[match.end():]


def split_prose(lines):
    """Returns (prose, problems): prose lines with their numbers, fenced lines replaced by None."""
    prose = []
    problems = []
    fence = None
    opened_at = 0
    for number, raw in enumerate(lines, 1):
        line = strip_blockquote(raw)
        match = FENCE.match(line)
        if fence is None:
            if match and not (match.group(1)[0] == "`" and "`" in match.group(2)):
                fence = match.group(1)
                opened_at = number
                prose.append((number, None))
                continue
            prose.append((number, line))
        else:
            if match and match.group(1)[0] == fence[0] and len(match.group(1)) >= len(fence) \
                    and match.group(2).strip() == "":
                fence = None
            prose.append((number, None))
    if fence is not None:
        problems.append((opened_at, "unterminated code fence", "close every fenced code block"))
    return prose, problems


def find_violations(message):
    """Returns a list of (line number, rule, excerpt) for every format violation in the message."""
    lines = message.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    prose, fence_problems = split_prose(lines)
    violations = [(number, rule, detail) for number, rule, detail in fence_problems]

    previous = None  # the previous prose line, or None after a blank line, a fence, or the start
    in_list = False
    paragraph = []
    paragraphs = []
    structural = set()
    for number, line in prose:
        if line is None or line.strip() == "":
            if paragraph:
                paragraphs.append(paragraph)
            paragraph = []
            previous = None
            in_list = False
            continue
        interrupts = previous is not None and not in_list
        rule = None
        if ATX_HEADING.match(line):
            rule = "Markdown heading"
        elif (SETEXT_UNDERLINE.match(line) or SETEXT_DASHES.match(line)) and previous is not None:
            rule = "Markdown heading (setext underline)"
        elif THEMATIC_BREAK.match(line):
            rule = "decorative separator"
        elif BOX_DRAWING_LINE.match(line):
            rule = "decorative separator"
        elif TABLE_DELIMITER.match(line) and previous is not None and "|" in previous:
            rule = "Markdown table"
        elif TASK_ITEM.match(line):
            rule = "checklist item"
        else:
            bullet = BULLET_ITEM.match(line)
            ordered = ORDERED_ITEM.match(line)
            if bullet and not (interrupts and bullet.group(1) is None):
                rule = "bullet list item"
            elif ordered and (not interrupts or ordered.group(1) == "1"):
                rule = "numbered list item"
        if rule in ("bullet list item", "numbered list item", "checklist item"):
            in_list = True
        if rule:
            violations.append((number, rule, excerpt(line)))
            structural.add(number)
        paragraph.append((number, line))
        previous = line
    if paragraph:
        paragraphs.append(paragraph)

    for block in paragraphs:
        text = "\n".join(line for _, line in block)
        bare = INLINE_CODE.sub(" ", text)
        for pattern in (BOLD_STARS, BOLD_UNDERSCORES):
            for match in pattern.finditer(bare):
                offset = bare.count("\n", 0, match.start())
                violations.append((block[min(offset, len(block) - 1)][0], "bold emphasis", excerpt(match.group(0))))
        for number, line in block:
            spans = INLINE_CODE.sub(" ", line)
            emoji = next((character for character in spans if is_emoji(character)), None)
            if emoji is not None:
                name = unicodedata.name(emoji, "U+%04X" % ord(emoji))
                violations.append((number, "emoji or pictograph", name))
        if len(block) == 1 and block[0][0] not in structural:
            number, line = block[0]
            words = line.split()
            stripped = line.strip()
            if 1 <= len(words) <= 8 and not TITLE_END.search(stripped) and not stripped.startswith("`") \
                    and any(character.isalpha() for character in stripped):
                violations.append((number, "standalone title", excerpt(line)))

    violations.sort(key=lambda item: item[0])
    return violations


CORRECTION = (
    "The response violates the maintainer-facing response policy of AGENTS.md (Agent Responses, Decision 44). "
    "Rewrite the complete response in formal English as continuous prose in developed paragraphs, without "
    "headings, standalone titles, bullet or numbered lists, checklists, tables, decorative separators, emojis, "
    "or bold formatting; italic text, inline code, and fenced code blocks for literal commands or output remain "
    "permitted. Retain all substantive content, including the closing paragraph on the current milestone, the "
    "next action, and its authorization. The noncompliant text has already been displayed, so deliver the "
    "corrected response in full rather than a description of the correction. Violations found: "
)


def describe(violations):
    shown = [f"line {number}: {rule} ({detail})" for number, rule, detail in violations[:MAX_REPORTED]]
    more = len(violations) - len(shown)
    if more > 0:
        shown.append(f"and {more} more")
    return "; ".join(shown) + "."


def decide(event):
    """Returns the JSON object to print for a Stop event, or None to allow the stop silently."""
    if not isinstance(event, dict):
        return None
    message = event.get("last_assistant_message")
    if not isinstance(message, str) or not message.strip():
        return None
    violations = find_violations(message)
    if not violations:
        return None
    if event.get("stop_hook_active") is True:
        return {
            "systemMessage": "Response-format validator: the corrected response still violates the AGENTS.md "
            "response policy and was not blocked again, to avoid a continuation loop. " + describe(violations)
        }
    return {"decision": "block", "reason": CORRECTION + describe(violations)}


def main():
    try:
        event = json.loads(sys.stdin.read())
    except (ValueError, UnicodeDecodeError):
        return 0
    result = decide(event)
    if result is not None:
        sys.stdout.write(json.dumps(result))
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
