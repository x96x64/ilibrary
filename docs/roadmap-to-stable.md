# Roadmap to the Stable Release

## Current Status as of October 16, 2026

Milestone M0, the planning baseline, is complete. The repository contains the engineering constraints, the [Technical Planning Study](planning-study.md), the [Manual Library Curation](reports/manual-library-curation.md) findings, and a package skeleton without functionality. No release has been published, and the repository has not been pushed.

The next milestone is M1: the technical spikes S1 to S5 described in the planning study. Their results are to be recorded with evidence classifications in `reports/architecture-spike.md` and reviewed by the maintainer before M2 begins. Spikes must use copies or synthetic files, never the maintainer's library in place.

## Decisions in Force

1. (October 16, 2026.) The plan in the [Technical Planning Study](planning-study.md) is approved, including the catalog format `ilibrary-catalog-1`, title rules, and authoring with AI agents.
2. (October 16, 2026.) The software license is the Apache License, Version 2.0.
3. (October 16, 2026.) Version 0.1.0 is an experimental source release. Package names for npm and PyPI are decided before version 0.2.0.
4. (October 16, 2026.) Pushes, repository creation, tags, and releases require the maintainer's explicit approval, preceded by a documentation preview, a summary of principal changes, and its Japanese translation.

## Where Work Can Run

| Work | Requires the Maintainer's Mac | Cloud Session |
| --- | --- | --- |
| `MP4Core`, `CatalogCore`, documentation, repository organization | No | Yes |
| Conversion, Music automation, timestamps, and spikes S1 to S5 | Yes | No; verify through macOS CI where possible |
| Private reference files and library qualification | Yes: `reference-private/` is local and ignored | No |
| Releases, tags, publishing | Maintainer confirmation | Prepare only |

Cloud sessions run on Linux. Targets that import Apple frameworks cannot be built there.
