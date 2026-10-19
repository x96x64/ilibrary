# Agent Handoff

## Purpose

This document contains a general-purpose prompt for resuming work in Codex or Claude Code from the repository alone. It applies at any milestone. The prompt is written in formal English, as required by [AGENTS.md](../AGENTS.md), which defines the rules it refers to; dedicated maintainer procedures remain in Japanese. Recommended models and effort levels are listed in the [roadmap](roadmap-to-stable.md#recommended-models-and-effort).

## Prompt

```text
The working directory is ~/ilibrary. The history preceding this conversation is recorded in the repository.

1. Read AGENTS.md, docs/planning-study.md, and docs/roadmap-to-stable.md, particularly Current Status and Decisions in Force, and determine the current state with git log and git status.
2. Identify the next milestone named in Current Status. Before beginning work, state its scope, its completion criteria (gates), and whether it requires the maintainer's Mac. Continue within scope already approved without requesting repeated confirmation. Version 0.1.0 has been published and its installation verified. The separate-user validation of M5 and M6 and the copy validation of M8 are recorded in reports. Existing publication approvals apply only to the completed 0.1.0 release; any new push or publication requires explicit approval. Before an approved push, continue to present actual-file previews, a summary, and its Japanese translation. If work remains in progress, resume from that point.
3. Work on a milestone branch and follow AGENTS.md. Commits use Conventional Commits as in iLyrics, formal English, and small units; append Co-authored-by: Codex <codex@openai.com> to commits to which Codex materially contributed. Documentation headings use MLA title case. Classify evidence as measured, inferred, or unknown, and do not record unverified matters as fact.
4. Do not access the maintainer's real library (~/Music/Music/Media.localized/Music) or Apple Music library without the maintainer's explicit instruction. Validate with copies or synthetic files. Keep real music files, Apple Account details, and personal paths only under reference-private/, and exclude them from published material.
5. Version 0.1.0 is published, and the maintainer's local verification is complete; confirm on GitHub the corrected release body and the Latest display. Do not repeat completed publication or validation, and obtain separate approval for any new publication route or version. Do not republish a published version or move an existing tag. Before each push, present a preview of the changed documentation, a summary of the principal changes, and its Japanese translation.
6. At each checkpoint, update and commit the Current Status of docs/roadmap-to-stable.md, so that work can continue after returning to Claude Code.
7. Write all replies in precise, formal English, in separated paragraphs without headings or lists. When confirmation is indispensable, use plain language and describe the alternatives and a recommendation. docs/test-library-validation.md describes how to switch to the separate user and report results. Do not operate Music or the maintainer's music files as the ordinary user.
8. Conclude with a report in formal English that states the work performed, the verification results, and the remaining issues; the next task and whether it requires the maintainer; the recommended model and effort for the next task, for Claude Code and for Codex, using GPT model names for Codex and never ultra; and the prompt for the next session.
```

## Use in Claude Code

The same prompt applies in Claude Code. Replace the Codex attribution in item 3 with `Co-Authored-By: Claude <noreply@anthropic.com>`, optionally preceded by the model name, as defined in AGENTS.md.

## Next Session for M11

```text
Read AGENTS.md, docs/planning-study.md, docs/roadmap-to-stable.md, docs/stable-release-plan.md, and docs/reports/m10-separated-addition-qualification-results.md in ~/ilibrary, and check git status and git log.
The current branch is codex/m10-rebuild-feasibility, which is local and unpushed. The four-case version 2 qualification passed, and the consolidated report concludes that every recorded M10 completion-gate condition is met, with the interpretation of deterministic ties reserved to the maintainer. No decision accepting M10 or authorizing M11 has been recorded unless Decisions in Force in docs/roadmap-to-stable.md says so.
If the maintainer has accepted M10 and authorized M11 in the current conversation, record that decision with its date and scope in Decisions in Force, and plan M11 (0.2.0) within that scope: independent backup verification, complete inventory, evacuation plans, strict catalog export, and versioned recovery records, with the gate in docs/stable-release-plan.md. Otherwise make no product change.
Retain every earlier bundle, library, backup, journal, report, and record. Run no probe and make no Music call. Do not operate the real library or private audio, change gates or expected orders, investigate or change ilibrary check --library without separate explicit approval, or push, merge, tag, or publish without the maintainer's approval. Update and commit Current Status and this handoff, and before any approved push present actual-file previews with a summary and its Japanese translation.
The recommended configuration for M11 is Claude Opus 5.5 at high in Claude Code and GPT-6-Astra at high in Codex, as in the milestone table.
```

## Recommended Models and Effort

For M10 feasibility and the subsequent registration-removal and recovery work, use Claude Opus 5.5 with xhigh in Claude Code or GPT-6-Astra with xhigh in Codex. The maintainer selected this effort before starting M10; it follows the M5 safety rationale. Use the milestone table for later work. Do not use ultra.
