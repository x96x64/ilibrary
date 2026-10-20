# Agent Handoff

## Purpose

This document contains a general-purpose prompt for resuming work in Codex or Claude Code from the repository alone. It applies at any milestone. The prompt is written in formal English, as required by [AGENTS.md](../AGENTS.md), which defines the rules it refers to, including the response policy of its Agent Responses section (Decision 44). That policy governs every response of every session and subagent without further reminders. Existing Japanese maintainer procedures are preserved, and new maintainer procedures are written in English (Decision 43).

## Prompt

```text
The working directory is ~/ilibrary. The history preceding this conversation is recorded in the repository.

1. Read AGENTS.md, docs/planning-study.md, and docs/roadmap-to-stable.md, particularly Current Status and Decisions in Force, and determine the current state with git log and git status.
2. Identify the next milestone named in Current Status. Before beginning work, state its scope, its completion criteria (gates), and whether it requires the maintainer's Mac. Continue within scope already approved without requesting repeated confirmation. Version 0.1.0 has been published and its installation verified. The separate-user validation of M5 and M6 and the copy validation of M8 are recorded in reports. Existing publication approvals apply only to the completed 0.1.0 release; any new push or publication requires explicit approval. Before an approved push, continue to present actual-file previews, a summary, verification results, and the privacy check, in English only. If work remains in progress, resume from that point.
3. Work on a milestone branch and follow AGENTS.md. Commits use Conventional Commits as in iLyrics, formal English, and small units; append Co-authored-by: Codex <codex@openai.com> to commits to which Codex materially contributed. Documentation headings use MLA title case. Classify evidence as measured, inferred, or unknown, and do not record unverified matters as fact.
4. Do not access the maintainer's real library (~/Music/Music/Media.localized/Music) or Apple Music library without the maintainer's explicit instruction. Validate with copies or synthetic files. Keep real music files, Apple Account details, and personal paths only under reference-private/, and exclude them from published material.
5. Version 0.1.0 is published, and the maintainer's local verification is complete; confirm on GitHub the corrected release body and the Latest display. Do not repeat completed publication or validation, and obtain separate approval for any new publication route or version. Do not republish a published version or move an existing tag. Before each push, present in English a preview of the changed documentation, a summary of the principal changes, and the verification results; add no Japanese translation (Decision 42).
6. At each checkpoint, update and commit the Current Status of docs/roadmap-to-stable.md, so that work can continue after returning to Claude Code.
7. Follow the Agent Responses section of AGENTS.md in every response: English only, continuous prose in developed paragraphs, and no headings, lists, tables, bold formatting, or decorative elements; review each response for compliance before sending it, and require the same of delegated subagents. When confirmation is indispensable, use plain language and describe the alternatives and a recommendation in prose. docs/test-library-validation.md describes how to switch to the separate user and report results. Do not operate Music or the maintainer's music files as the ordinary user.
8. Conclude with a report that states the work performed, the verification results, and the remaining issues, and that ends with a paragraph giving the current milestone, its verified progress, the next concrete action, and whether that action requires the maintainer. Do not add a model or reasoning-effort recommendation unless the maintainer requests one. Keep this document's next-session prompt current.
```

## Use in Claude Code

The same prompt applies in Claude Code. Replace the Codex attribution in item 3 with `Co-Authored-By: Claude <noreply@anthropic.com>`, optionally preceded by the model name, as defined in AGENTS.md.

## Current State for the Next Session

As of the commit that introduced Decision 44, M11 is the active milestone on the local, unpublished branch `m11-backup-inventory`, which was created from `main` after the M10 merge `f91c8ff`. The branch tip that preceded the policy change was `5b10caf`, with 13 commits above `main`; a new session must confirm the actual branch, HEAD, working tree, and unpublished commits with Git rather than relying on this paragraph. The M11 plan is approved under Decision 41 with its safeguards, and Decisions 42 to 44 govern response language, procedure language, and response format. The implementation, its macOS tests, the English qualification procedure `docs/m11-qualification.md`, and the bundle `/Users/Shared/ilibrary-m11-qualification.zip` prepared at source `3b06a078cf8f0fda6774abec2926286065f3e4b7` are complete and are recorded in `docs/reports/m11-implementation-and-qualification-preparation.md`; they must not be repeated or recreated.

A response of the October 20, 2026, M11 preparation session violated the response policy with bullet lists, numbered lists, and bold emphasis, although the session's loaded context contained `CLAUDE.md` and the imported `AGENTS.md`. The commit that introduced this paragraph adds a project Stop hook (`.claude/settings.json` and `scripts/hooks/response_format.py`) that checks the final message of each Claude Code turn; its coverage and limits are stated in the Agent Responses section of AGENTS.md. It changes no policy, decision, or M11 material.

M11 has not passed. Linux compilation of the new code, the live execution and field-level equivalence of the bulk Music reader, the cloud status values that Music reports for local files, Finder date preservation and restoration on a real external APFS or HFS+ drive, the device signals of a real external drive, the refusal of an internal-disk backup in practice, and the real disconnection wait are unmeasured; passing synthetic tests do not establish them. The `check --library` change under Decision F remains unimplemented until live equivalence is established. The next action is the maintainer's separate-user run of the qualification procedure, which produces `/Users/Shared/ilibrary-m11-qualification-report.txt`; agents perform no Music operation, no live qualification, and no operation on the backup device.

## Next Session for M11

```text
Read AGENTS.md (especially Agent Responses), docs/roadmap-to-stable.md (Current Status and Decisions 41 to 44), docs/stable-release-plan.md, docs/m11-plan.md, docs/m11-qualification.md, docs/reports/m11-implementation-and-qualification-preparation.md, and this document's Current State section in ~/ilibrary. Confirm the actual branch, HEAD, working tree, and unpublished commits with git status and git log before acting, and preserve all existing work and evidence.
If /Users/Shared/ilibrary-m11-qualification-report.txt has been received, preserve it byte for byte under a new directory in reference-private/, record its size and SHA-256, compare it with the frozen source 3b06a07, and assess the reader equivalence, the observed cloud status values, the strict export, the backup verification and dates, the refusal of the internal copy, the restoration, the disconnection, and the recovery record against the M11 gate in a new report, distinguishing measured, inferred, and unknown findings. Only after live equivalence is established may the separately reviewed check --library change under Decision F be implemented. If no report has been received, perform no new preparation or run, and state that the maintainer's qualification is the next action.
Run no probe and make no Music call. Do not operate the real library, private audio, a test library, or any drive; do not remove registrations, rebuild a library, or evacuate originals. Do not push, merge, tag, or publish without the maintainer's approval. Every response follows the Agent Responses section of AGENTS.md. Update and commit Current Status and this handoff at each checkpoint, and before any approved push present actual-file previews, a summary, and verification results in English prose.
```

## Model and Effort Guidance

Responses and handoffs do not recommend a model or reasoning effort unless the maintainer requests one (Decision 44). The milestone table in the [roadmap](roadmap-to-stable.md#recommended-models-and-effort) remains reference information for configuring a session, and the model configuration of a delegated agent is part of its definition rather than of any response.
