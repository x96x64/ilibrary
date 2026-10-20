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
- [Plan for M11](m11-plan.md): proposed backup, inventory, strict export, and recovery-record work for 0.2.0, with the decisions required before implementation
- [M11 Backup and Inventory Qualification](m11-qualification.md): English procedure for the maintainer-operated bulk-reader, external-drive backup, restoration, and disconnection measurements of M11; M11 has not passed until its report is assessed
- [Separated Addition Qualification, Version 2](rebuild-qualification-v2-validation.md): Japanese procedure for the scale and three artist-order cases under Decision 36 with new libraries `M10-separated-v2-<case>`
- [Separated Addition Qualification, First Run](rebuild-qualification-validation.md): completed Japanese first-run procedure; the scale case stopped in registration removal; retained for the record and not to be continued
- [Rebuilding Addition Timing Validation](rebuild-timing-validation.md): completed Japanese version 2 timing procedure; its small case passed; retained for the record
- [Stopped Timing Probe Diagnostics](rebuild-timing-diagnostics.md): completed file-only media inventory of the stopped first timing run; retained for the record
- [Rebuilding Display-Order Validation](rebuild-display-validation.md): retained Japanese display-v3 procedure; further execution is paused after the small-case display failure
- [Retained Rebuilding Bundle Diagnostics](rebuild-bundle-diagnostics.md): completed read-only inventory diagnostic; retained for the record
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
- 2026-10-17 — [Finder Metadata and Bundle Verification](reports/finder-metadata-verification.md)
- 2026-10-17 — [Display-Order Version 3 Results](reports/display-order-v3-results.md)
- 2026-10-17 — [Separated Addition Timing Preparation](reports/addition-timing-preparation.md)
- 2026-10-17 — [Separated Addition Timing Results](reports/addition-timing-results.md)
- 2026-10-17 — [Timing Media Scaffolding Correction](reports/timing-media-scaffolding.md)
- 2026-10-17 — [Separated Addition Timing Version 2 Results](reports/addition-timing-v2-results.md)
- 2026-10-17 — [README Example and Badge Corrections](reports/readme-example-corrections.md)
- 2026-10-17 — [Separated Addition Qualification Preparation](reports/separated-addition-qualification-preparation.md)
- 2026-10-19 — [Separated Addition Qualification Results](reports/separated-addition-qualification-results.md)
- 2026-10-19 — [Removal Performance Revision](reports/removal-performance-revision.md)
- 2026-10-19 — [Separated Addition Qualification, Version 2 Results](reports/separated-addition-qualification-v2-results.md)
- 2026-10-20 — [M10 Separated Addition Qualification Results](reports/m10-separated-addition-qualification-results.md)
- 2026-10-20 — [M11 Implementation and Qualification Preparation](reports/m11-implementation-and-qualification-preparation.md)
- 2026-10-20 — [M11 Qualification Results, First Run](reports/m11-qualification-results.md)
