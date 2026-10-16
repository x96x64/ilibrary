# iLibrary Engineering Constraints

## Project Identity and Documentation

Use `iLibrary` as the canonical product name and `ilibrary` for the executable, repository, and suitable lowercase technical identifiers. Work in this repository; do not create a nested project directory. Preserve the planning-baseline commit.

Use MLA headline-style title case permanently for all English documentation titles, section headings, and subsection headings, including README, contributor guidance, architecture documents, command references, and future documentation. Preserve literal capitalization of iLibrary, iLyrics, Apple product names, APIs, frameworks, languages, commands, filenames, options, packages, and code identifiers.

Model the README and command-line interface on established, widely used tools such as ripgrep, fd, bat, GitHub CLI, Git, FFmpeg, and yt-dlp, and on the sibling project iLyrics. The interface is a command-based CLI with verb subcommands; do not introduce an interactive text user interface. Keep commits atomic and conventional so that history remains reviewable; perform broad cleanup through ordinary commits in a dedicated milestone.

## Evidence and Architecture

Read `docs/planning-study.md` before architectural changes. Preserve its decisions, evidence classifications, and go/no-go criteria. The study is a historical baseline, not an instruction to implement its entire roadmap. Validate architectural recommendations with working evidence, and classify findings as measured, inferred, or unknown. Never represent unmeasured Apple Music or iCloud Music Library behavior as measured fact; in particular, iLibrary documents procedures that reduce cloud matching and detects its result, but must not claim to prevent it.

Keep domain logic in Foundation-only targets (`MP4Core`, `CatalogCore`) that build and test on Linux. Confine AppKit, AudioToolbox, AVFoundation, ScriptingBridge, and Apple Events to `…Mac` targets. Do not depend on external tools such as AtomicParsley, exiftool, or FFmpeg at run time; they may be used only as independent references during verification. Do not add package dependencies without an explicit decision.

## Library Safety

iLibrary modifies user-owned music files and an Apple Music library. Every mutating command must offer `--dry-run`, must state what it will change before changing it, and must verify its result afterwards.

- Never delete an original file unless the user requests deletion and the replacement has been verified: decoded duration, codec, and, for lossless conversion, decoded PCM equality.
- Check free space before conversions. Treat truncated or partially written outputs as failures, and never count them as complete.
- Move files into the Music media folder instead of copying them, and add them album by album. Stop when the library already contains a matching track; do not remove library entries automatically.
- Address Music tracks by persistent ID, one operation per call. Do not rename tracks while iterating over a track collection; property changes during iteration have applied to unrelated tracks.
- Changing an album name in Music triggers automatic folder organization that can split an album across folders and break file references. Write tags to files, arrange folders, and then add or relink tracks explicitly.
- Music caches metadata independently of files. After editing files, compare the file and the library and report every difference.
- Never create a filesystem entry as a side effect of setting timestamps. A timestamp operation on a missing path must do nothing and report the path.
- Leave source files that the user did not select, such as original WAV rips, untouched.

## Scope and Rights

Do not incorporate proprietary Apple assets, private frameworks, store artwork, commercial recordings, credentials, Apple Account identifiers, or private library data. Public fixtures, examples, and tests must use original synthetic albums and generated audio. Protected audio (`.m4p`) is out of scope. iLibrary does not download audio. The software license is the Apache License, Version 2.0, decided on October 16, 2026.

## Verification and History

Test box parsing and rewriting, chunk-offset relocation, catalog matching, naming, ordering, title rules, and date handling with synthetic inputs. Validate conversions by decoding and comparing PCM, not by byte equality of encoded files. Keep generated outputs and machine-specific logs out of Git. Record sanitized hardware and toolchain context without hostnames, serial numbers, device identifiers, Apple Account details, or personal paths. Review staged changes before concise conventional commits. Review all history, ignored files, and untracked files before publication. Publish only under the repository name `ilibrary`.

Keep real purchased or downloaded files, library exports, and copyright-bearing derivatives under ignored `reference-private/`. Confirm ignore behavior before processing and audit every staged change before committing or pushing. Reference validation must report unavailable inputs explicitly; the public suite must work without private files, network access, an Apple Music subscription, or a populated Music library.

## Archival Writing

All project documentation, engineering reports, commit messages, and completion reports must use precise, grammatical, formal English suitable for an archival engineering record. Describe technical changes, evidence, uncertainty, and consequences without conversational framing, promotional language, agent-centric narration, or unsupported claims. Preserve completed planning and architecture reports as historical records, and record subsequent findings in new reports.

## Commits

Follow [Conventional Commits](https://www.conventionalcommits.org/) as in iLyrics: `type(scope): subject`, with a lowercase, imperative, specific subject without a trailing period, intelligible independently of the development conversation. Use a body only to record rationale and consequences. Keep the human author and committer identities.

## Commit Attribution

When Codex materially contributes to a commit, append `Co-authored-by: Codex <codex@openai.com>` after a blank line in the commit message. When Claude materially contributes, append `Co-Authored-By: Claude <noreply@anthropic.com>` under the same conditions; a model-specific display name such as `Claude Opus 5.5` may precede the address. Include both trailers when both agents contributed materially. Apply these trailers only when the contribution is supported by the work performed; do not add them to unrelated or unassisted commits, and do not create artificial commits to influence contributor statistics. Follow GitHub's [co-author trailer format](https://docs.github.com/en/pull-requests/how-tos/commit-changes/creating-a-commit-with-multiple-authors).

Historical attribution changes require explicit approval, a verified recoverable backup, preservation of original authors, committers, dates, messages, change sequence, and repository contents except for the approved attribution metadata, and an explicitly approved lease-protected remote update.

## Agent Handoff

This file governs Claude Code, Codex, and other agents equally; `CLAUDE.md` imports it. Keep project state in the repository rather than in conversations: at the end of each milestone, update the Current Status of `docs/roadmap-to-stable.md` and commit it, so that any agent can resume from the repository alone. Cloud sessions run on Linux and can build and test only the Foundation-only targets; verify macOS-only changes through macOS CI or on the maintainer's Mac. Releases, tags, repository creation, pushes, and publication require the maintainer's explicit approval in the current conversation. Before each push, present a preview of the changed documentation, a summary of the principal changes, and its Japanese translation.

Every reply to the maintainer, including every handoff, next-session prompt, and milestone completion report, must end by stating a recommended model and reasoning effort for the next task, for Claude Code and for Codex. Recommend only models and effort levels confirmed to be available. Prefer the effort of the milestone table in `docs/roadmap-to-stable.md`, and explain any deviation. Do not recommend Codex's `ultra` effort, whose automatic task delegation conflicts with the scope controls of this file.
