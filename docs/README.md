# Documentation

## User Documentation

- [Version 0.1.0 Release Notes](releases/0.1.0.md): experimental release description
- [Command-Line Interface](command-line-interface.md): commands, options, and exit status
- [Completing Catalogs with AI Agents](catalog-for-agents.md): the authoring workflow for agents and chats
- [Library Operations and Recovery](library-operations.md): previews, resumption, diagnostics, and private reports
- [Test Library Validation](test-library-validation.md): Japanese instructions for validating Music operations in a separate macOS user
- [Catalog JSON Schema](schema/ilibrary-catalog-1.schema.json): the catalog format
- [Support](../SUPPORT.md): reporting a problem without private data

## Maintainer Documentation

- [Roadmap to the Stable Release](roadmap-to-stable.md): current status, decisions in force, and where work can run
- [Plan for the Stable Release](stable-release-plan.md): revised M10–M15 sequence, preservation requirements, and actual display-order gates
- [Retained Rebuilding Bundle Diagnostics](rebuild-bundle-diagnostics.md): current Japanese read-only handoff after the display-v2 inventory stop
- [Rebuilding Display-Order Validation](rebuild-display-validation.md): retained M10 procedure; do not rerun while the inventory difference is unresolved
- [Rebuilding Feasibility Validation](rebuild-feasibility-validation.md): retained version 2 instructions; do not resume this superseded experiment
- [Saved Addition-Date Verification](rebuild-feasibility-date-check.md): completed read-only extraction of the stopped M10 run's saved timestamps
- [Contributing](../CONTRIBUTING.md): development and verification requirements
- [Distribution](distribution.md): package construction, installation verification, and publication
- [Package Publication Setup](package-publishing.md): Japanese Web setup and result reporting for npm and PyPI
- [Agent Handoff](agent-handoff.md): resuming work from repository records
- [Live Music Measurements](live-music-measurements.md): measuring Music in a separate macOS user

These procedures remain useful for maintenance and later releases. Temporary build products, previews, and machine-specific logs are excluded from Git.

## Historical Baseline

The approved study records the original design and evidence. Later decisions may supersede its implementation details; use the current guides above for supported behavior.

- [Technical Planning Study](planning-study.md): the approved plan, preserved as a historical record

## Engineering Reports

The reports below record findings and decisions in the order the work was done. They are historical records and are not revised afterwards.

- 2026-10-16 — [Manual Library Curation](reports/manual-library-curation.md)
- 2026-10-16 — [Architecture Spike](reports/architecture-spike.md)
- 2026-10-16 — [Core Targets](reports/core-targets.md)
- 2026-10-17 — [Catalog Commands](reports/catalog-commands.md)
- 2026-10-17 — [Import](reports/import.md)
- 2026-10-17 — [Music Behavior](reports/music-behavior.md)
- 2026-10-17 — [Ordered Addition](reports/ordered-addition.md)
- 2026-10-17 — [Ordered Addition Corrections](reports/ordered-addition-corrections.md)
- 2026-10-17 — [Library Checks and Diagnostics](reports/library-checks.md)
- 2026-10-17 — [Documentation Review](reports/documentation-review.md)
- 2026-10-17 — [Live Library Command Validation](reports/library-command-validation.md)
- 2026-10-17 — [Library Copy Qualification](reports/library-qualification.md)
- 2026-10-17 — [Version 0.1.0 Release Preparation](reports/release-preparation.md)
- 2026-10-17 — [Distribution Metadata Correction](reports/distribution-metadata-correction.md)
- 2026-10-17 — [Version 0.1.0 Publication](reports/release-publication.md)
- 2026-10-17 — [iLyrics Documentation Conformance](reports/documentation-conformance.md)
- 2026-10-17 — [Release Presentation and Maintainer Verification](reports/release-presentation.md)
- 2026-10-17 — [Rebuilding Feasibility Preparation](reports/rebuild-feasibility-preparation.md)
- 2026-10-17 — [Initial Rebuilding Feasibility Results](reports/rebuild-feasibility-results.md)
- 2026-10-17 — [Rebuilding Probe Revision](reports/rebuild-probe-revision.md)
- 2026-10-17 — [Version 2 Rebuilding Feasibility Results](reports/rebuild-feasibility-v2-results.md)
- 2026-10-17 — [Rebuilding Timestamp Gate Assessment](reports/rebuild-timestamp-gate.md)
- 2026-10-17 — [Display-Order Plan Revision](reports/display-order-plan-revision.md)
- 2026-10-17 — [Display-Order Validation Preparation](reports/display-order-preparation.md)
- 2026-10-17 — [Display-Order Validation Results](reports/display-order-results.md)
- 2026-10-17 — [Display-Probe Media-Path Correction](reports/display-media-path-correction.md)
- 2026-10-17 — [Display-Order Version 2 Results](reports/display-order-v2-results.md)
