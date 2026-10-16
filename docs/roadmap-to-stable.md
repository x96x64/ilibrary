# Roadmap to the Stable Release

## Current Status as of October 16, 2026

Milestone M0, the planning baseline, is complete. Milestone M1, the technical spikes S1 to S5, is complete on the branch `m1-spikes` and awaits the maintainer's review of the [Architecture Spike](reports/architecture-spike.md) report, which is the gate to M2. The spike programs and scripts are in `scripts/spikes/`. No release has been published, and the repository has not been pushed.

The spikes used synthetic files and copies of the private references in `reference-private/`: one purchased iTunes Store file, nine Apple Lossless files and one FLAC file from mora, and a file cleaned during manual curation. S1, S2, S4, and S5 support the planned architecture with qualifications. S3 located Music's scripting interfaces and configuration keys but measured no live behavior, because no library that may be modified was available. Open items before later milestones:

1. The maintainer decides the six proposals in the report's section "Decisions Proposed for M2".
2. The maintainer decides the environment for the live S3 measurements; the report proposes a separate local macOS user without an Apple Account. These measurements are required before M5.
3. S5 rests on one purchased file. Further purchased files under `reference-private/` would strengthen it before M4.

After the review, the next milestone is M2: `MP4Core` and `CatalogCore` with synthetic tests.

## Decisions in Force

1. (October 16, 2026.) The plan in the [Technical Planning Study](planning-study.md) is approved, including the catalog format `ilibrary-catalog-1`, title rules, and authoring with AI agents.
2. (October 16, 2026.) The software license is the Apache License, Version 2.0.
3. (October 16, 2026.) Version 0.1.0 is an experimental source release. Package names for npm and PyPI are decided before version 0.2.0.
4. (October 16, 2026.) Pushes, repository creation, tags, and releases require the maintainer's explicit approval, preceded by a documentation preview, a summary of principal changes, and its Japanese translation.

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
