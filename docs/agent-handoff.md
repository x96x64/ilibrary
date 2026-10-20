# Agent Handoff

## Purpose

This document contains a general-purpose prompt for resuming work in Codex or Claude Code from the repository alone. It applies at any milestone. The prompt is written in formal English, as required by [AGENTS.md](../AGENTS.md), which defines the rules it refers to; dedicated maintainer procedures remain in Japanese. Recommended models and effort levels are listed in the [roadmap](roadmap-to-stable.md#recommended-models-and-effort).

## Prompt

```text
The working directory is ~/ilibrary. The history preceding this conversation is recorded in the repository.

1. Read AGENTS.md, docs/planning-study.md, and docs/roadmap-to-stable.md, particularly Current Status and Decisions in Force, and determine the current state with git log and git status.
2. Identify the next milestone named in Current Status. Before beginning work, state its scope, its completion criteria (gates), and whether it requires the maintainer's Mac. Continue within scope already approved without requesting repeated confirmation. Version 0.1.0 has been published and its installation verified. The separate-user validation of M5 and M6 and the copy validation of M8 are recorded in reports. Existing publication approvals apply only to the completed 0.1.0 release; any new push or publication requires explicit approval. Before an approved push, continue to present actual-file previews, a summary, verification results, and the privacy check, in English only. If work remains in progress, resume from that point.
3. Work on a milestone branch and follow AGENTS.md. Commits use Conventional Commits as in iLyrics, formal English, and small units; append Co-authored-by: Codex <codex@openai.com> to commits to which Codex materially contributed. Documentation headings use MLA title case. Classify evidence as measured, inferred, or unknown, and do not record unverified matters as fact.
4. Do not access the maintainer's real library (~/Music/Music/Media.localized/Music) or Apple Music library without the maintainer's explicit instruction. Validate with copies or synthetic files. Keep real music files, Apple Account details, and personal paths only under reference-private/, and exclude them from published material.
5. Version 0.1.0 is published, and the maintainer's local verification is complete; confirm on GitHub the corrected release body and the Latest display. Do not repeat completed publication or validation, and obtain separate approval for any new publication route or version. Do not republish a published version or move an existing tag. Before each push, present in English a preview of the changed documentation, a summary of the principal changes, and the verification results; add no Japanese translation (Decision 42).
6. At each checkpoint, update and commit the Current Status of docs/roadmap-to-stable.md, so that work can continue after returning to Claude Code.
7. Write all replies in precise, formal English, in separated paragraphs without headings or lists. When confirmation is indispensable, use plain language and describe the alternatives and a recommendation. docs/test-library-validation.md describes how to switch to the separate user and report results. Do not operate Music or the maintainer's music files as the ordinary user.
8. Conclude with a report in formal English that states the work performed, the verification results, and the remaining issues; the next task and whether it requires the maintainer; the recommended model and effort for the next task, for Claude Code and for Codex, using GPT model names for Codex and never ultra; and the prompt for the next session.
```

## Use in Claude Code

The same prompt applies in Claude Code. Replace the Codex attribution in item 3 with `Co-Authored-By: Claude <noreply@anthropic.com>`, optionally preceded by the model name, as defined in AGENTS.md.

## Next Session for M11

```text
Read AGENTS.md, docs/planning-study.md, docs/roadmap-to-stable.md (Current Status and Decisions in Force, especially Decisions 41 to 43), docs/stable-release-plan.md, docs/m11-plan.md, docs/m11-qualification.md, and docs/reports/m11-implementation-and-qualification-preparation.md in ~/ilibrary, and check git status and git log on the local branch m11-backup-inventory.
M11 implementation is complete and the qualification bundle (source 3b06a07, ZIP SHA-256 3978685ced21ab470b9601726faf0d8134436e31924eb44d422d945a5248ed4e) is in /Users/Shared/. M11 has not passed. The maintainer personally runs docs/m11-qualification.md in the separate test user with an external APFS or HFS+ drive.
If /Users/Shared/ilibrary-m11-qualification-report.txt has been received, preserve it byte for byte under a new directory in reference-private/, record its SHA-256, compare it with the frozen source 3b06a07, and assess the reader equivalence, the observed cloud status values, the strict export, the backup verification and dates, the refusal of the internal copy, the restoration, the disconnection, and the recovery record against the M11 gate, distinguishing measured, inferred, and unknown findings, in a new report. Only after live equivalence is established may the separately reviewed check --library change under Decision F be implemented. If no report has been received, perform no new preparation or run.
Run no probe and make no Music call. Do not operate the real library, private audio, or any drive; do not remove registrations, rebuild a library, or evacuate originals. Do not push, merge, tag, or publish beyond the recorded approvals. Write every response, and require delegated subagents to write every response, entirely in English without Japanese translations (Decision 42). Update and commit Current Status and this handoff, and before any approved push present actual-file previews, a summary, and verification results in English only.
The recommended configuration for M11 is Claude Opus 5.5 at high in Claude Code and GPT-6-Astra at high in Codex, as in the milestone table.
```

## Recommended Models and Effort

For M10 feasibility and the subsequent registration-removal and recovery work, use Claude Opus 5.5 with xhigh in Claude Code or GPT-6-Astra with xhigh in Codex. The maintainer selected this effort before starting M10; it follows the M5 safety rationale. Use the milestone table for later work. Do not use ultra.
