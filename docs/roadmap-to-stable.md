# Roadmap to the Stable Release

## Current Status as of October 17, 2026

Milestones M0 to M2 are complete and published in [x96x64/ilibrary](https://github.com/x96x64/ilibrary); the M2 CI gate was satisfied by [CI run 38886543086](https://github.com/x96x64/ilibrary/actions/runs/38886543086) and the later run 38887532717 (measured). No release has been published.

Milestone M3 is complete. [Pull request #1](https://github.com/x96x64/ilibrary/pull/1) from `m3-catalog-commands` was merged into `main` on October 17, 2026, at merge commit `13ef7a0`. M3 adds the commands `export` (with `--dry-run`), `prompt`, `schema`, `validate`, `apply` (with `--dry-run`, `--rename`, and `--timestamps`), and `timestamps` (with `--dry-run` and `--script`), and the macOS-only target `LibraryMac` for file dates; see [Catalog Commands](reports/catalog-commands.md), the [Command-Line Interface](command-line-interface.md) reference, and [Completing Catalogs with AI Agents](catalog-for-agents.md).

- **Local verification (measured).** On the maintainer's Mac, all 103 tests and the formatting check passed for the merged code, and `scripts/validation/catalog-commands.sh` passed all 21 checks. Export and reapplication of synthetic library copies changed no byte, name, or date, which satisfies the M3 gate for synthetic copies. Only synthetic files were used (Decision 16).
- **Continuous integration (measured).** For `ea01487`, the head that was merged, [CI run 38977103566](https://github.com/x96x64/ilibrary/actions/runs/38977103566) passed both jobs: the macOS job ran the release build, all tests, and the formatting check, and the Linux job ran the Core and command tests. Earlier heads of the pull request also passed, including `2e37aaa`, on which the command tests passed on Linux for the first time.
- **Reviews.** Two automated Codex reviews, of `2e37aaa` and `6731ff0`, reported six findings in total, four classified P1 and two P2; among them, `--rename` could leave its directory through a name `..`. A review of the corrected code found a seventh, an underestimate of the free space that rewrites with added artwork need. All seven were corrected with tests before merging, as recorded in the Catalog Commands report, and all six review threads were answered and resolved. No automated review was requested for the final corrections, as the maintainer decided.

Milestone M4 is implemented on the branch `m4-import` and has not been pushed. It adds the macOS-only target `ConversionMac` and the command `import` (with `--from`, `--delete-originals`, and `--dry-run`); see [Import](reports/import.md) and the [Command-Line Interface](command-line-interface.md) reference.

- **Local verification (measured).** On the maintainer's Mac, all 120 tests and the formatting check passed, `scripts/validation/import.sh` passed all 30 checks, and `scripts/validation/catalog-commands.sh` passed all 21 checks. Copies of one mora FLAC file and one purchased iTunes Store file, processed inside `reference-private/work/` with the maintainer's approval, passed all 8 checks of `scripts/reference_validation/validate-import.sh`; the originals were unchanged and the copies were removed.
- **Continuous integration.** Not yet run for this branch.
- **Pull request and merge.** Not yet opened; pushing the branch and opening a pull request await the maintainer's approval (Decision 13).

Open items:

1. The live S3 measurements are performed when needed, at the latest before M5, in a separate local macOS user without an Apple Account, which the maintainer creates.
2. S5 rests on one purchased file. Further purchased files under `reference-private/` would strengthen it.
3. The private FLAC file contains nine fields outside the standard set; `import` drops them, and their contents were not examined.
4. The maintainer reviews the refusal of `enca` sample entries, which extends Decision 12 to ISO Common Encryption.
5. The maintainer reviews the design choices recorded in the Catalog Commands and Import reports.
6. Whether real libraries contain values that a catalog cannot represent, such as gaps in track numbers or year-only dates, is unknown until a catalog is exported from one.
7. Moves to the real Trash through `FileManager.trashItem` are untested; the tests use a substitute Trash.

After M4 is merged, the next milestone is M5: `add` with the four orders and resumption, which changes the Music library and requires the live S3 measurements first.

## Decisions in Force

1. (October 16, 2026.) The plan in the [Technical Planning Study](planning-study.md) is approved, including the catalog format `ilibrary-catalog-1`, title rules, and authoring with AI agents.
2. (October 16, 2026.) The software license is the Apache License, Version 2.0.
3. (October 16, 2026.) Version 0.1.0 is an experimental source release. Package names for npm and PyPI are decided before version 0.2.0.
4. (October 16, 2026.) Pushes, repository creation, tags, and releases require the maintainer's explicit approval, preceded by a documentation preview, a summary of principal changes, and its Japanese translation.
5. (October 16, 2026.) MP4Core rebuilds `moov` as proposed in the spike report. In version 0.1.0, files that require chunk offsets beyond 32 bits are refused rather than converted to `co64`.
6. (October 16, 2026.) The Foundation-only FLAC metadata reader is a separate target, `FLACCore`.
7. (October 16, 2026.) Version 0.1.0 converts mono and stereo only and refuses floating-point PCM. Conversions are verified by PCM digests, declared and decoded frame counts, and WAV and AIFF chunk lengths; stream copies are verified by media-data and sample-table equality.
8. (October 16, 2026.) Free space is checked against the plain available capacity of the destination volume.
9. (October 16, 2026.) Timestamp operations refuse missing paths and symbolic links, run after all writes and moves, and set folders after their contents.
10. (October 16, 2026.) Purchase metadata is removed by the atom list and the sample-entry allowlist of the spike report, with all padding zeroed. `iTunSMPB` and `stik` are retained, and `xid ` is removed.
11. (October 16, 2026.) At the end of M2, the agent proposes creating the GitHub repository `x96x64/ilibrary` as a public repository and pushing `main`, so that continuous integration runs on macOS; About text and topics follow the planning study. Before that push, the README is expanded to the structure of the iLyrics README, describing implemented behavior as implemented and planned behavior as planned. Repository creation and the push require the maintainer's approval in the session that performs them.
12. (October 16, 2026.) Only encrypted audio is refused: `drms` sample entries and `.m4p` files. Purchaser information in files that are not encrypted is removed, not refused.
13. (October 16, 2026.) For this first publication, `m2-core` is merged into `main` before `main` is pushed. From M3 onward, milestone branches are pushed and merged into `main` through pull requests, as in iLyrics.
14. (October 17, 2026.) `export --artwork DIR` writes each embedded cover in its original JPEG or PNG format, without re-encoding, instead of converting it to PNG as the planning study proposed. This supersedes that detail of the study.
15. (October 17, 2026.) The dates of an artist folder are set only when the catalog gives the artist a `folderDate`; otherwise the folder is left unchanged.
16. (October 17, 2026.) M3 is verified with synthetic files only. Private reference files are not used unless the maintainer instructs otherwise.
17. (October 17, 2026.) `import --delete-originals` moves originals to the Trash, never deleting them permanently, and only after every output of the import has been verified.
18. (October 17, 2026.) `import` keeps the relative structure of each source: the files under a source directory keep their paths relative to it under the output folder, and a source file is placed directly in it.
19. (October 17, 2026.) `import` carries FLAC tags by an allowlist of standard fields and the front cover, and drops every other field without examining or reporting its contents. For M4, copies of one mora FLAC file and one purchased iTunes Store file under `reference-private/work/` may be used for an additional validation.

## Recommended Models and Effort

Recorded on October 16, 2026, from the models available to the maintainer: Claude Opus 5.5 and Claude Sonnet 5.5 in Claude Code, and GPT-6-Astra and GPT-6.1-Sol in Codex. Revise this table when the available models change.

| Milestone | Claude Code | Codex |
| --- | --- | --- |
| M1 Spikes | Claude Opus 5.5, high | GPT-6-Astra, high |
| M2 Core targets | Claude Opus 5.5, high | GPT-6.1-Sol, high |
| M3 Catalog commands | Claude Opus 5.5, high | GPT-6.1-Sol, high |
| M4 Import | Claude Opus 5.5, high | GPT-6-Astra, high |
| M5 Ordered addition to Music | Claude Opus 5.5, xhigh | GPT-6-Astra, xhigh |
| M6 `check` and `doctor` | Claude Sonnet 5.5, high | GPT-6.1-Sol, medium |
| M7 Documentation | Claude Opus 5.5, high | GPT-6-Astra, high |
| M8 Library qualification | Claude Opus 5.5, high | GPT-6-Astra, high |
| M9 Release preparation | Claude Opus 5.5, high | GPT-6.1-Sol, high |

M5 receives the highest effort because it changes the maintainer's Music library, where earlier manual operations affected unrelated tracks.

## Where Work Can Run

| Work | Requires the Maintainer's Mac | Cloud Session |
| --- | --- | --- |
| `MP4Core`, `CatalogCore`, documentation, repository organization | No | Yes |
| Conversion, Music automation, timestamps, and spikes S1 to S5 | Yes | No; verify through macOS CI where possible |
| Private reference files and library qualification | Yes: `reference-private/` is local and ignored | No |
| Releases, tags, publishing | Maintainer confirmation | Prepare only |

Cloud sessions run on Linux. Targets that import Apple frameworks cannot be built there.
