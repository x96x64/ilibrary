# iLyrics Documentation Conformance

## Scope and Reference

On October 17, 2026, the maintainer requested a review of iLibrary's documentation against iLyrics after identifying an independently designed release-note structure. The review covers the 34 existing Markdown files: 19 outside the reports directory and 15 completed reports. The planning baseline is among the 19 documents and remains preserved. This report is the additional review record.

The reference checkout was clean at iLyrics commit `15cc5da4375cf6a9cf1fe6e5f41400509069327e`. Published iLyrics v0.2.0 and v1.3.2 release bodies were also read. Their common structure is introductory prose, an important notice, Highlights, Installing and Upgrading, and a closing changelog link (measured). iLibrary's original six-section release-note structure did not follow that reference.

## Document Review

The comparisons below measure headings, ordering, links, and recorded status. The suitability of product-specific adaptations is an engineering judgment, not a measurement of software behavior.

| iLibrary Document | iLyrics Reference | Assessment and Action |
| --- | --- | --- |
| `README.md` | `README.md` | Fourteen shared top-level sections retain the same order. The important notice and `pip` heading were aligned. Star History remains between Contributing and Acknowledgments. Catalog and Music sections describe iLibrary's own workflow. |
| `packaging/README.md` | `packaging/README.md` | The source template now uses the same seven top-level sections: Features, Requirements, Installation, Usage, Rights, Links, and License. Existing safety and recovery information is retained. |
| `docs/releases/0.1.0.md` | Published v0.2.0 and v1.3.2 bodies | Replaced the independent structure with the shared release-note sequence. The archival file title must be omitted when updating the GitHub body because GitHub displays the release title separately. The external body update awaits the maintainer's checks. |
| `SUPPORT.md` | `SUPPORT.md` | Aligned Supported Versions, Supported Platforms, Getting Help, and Out of Scope; retained interruption guidance and private-report restrictions. No support promise was copied from the stable product. |
| `docs/distribution.md` | `docs/distribution.md` | Aligned Status, Release Archive, Channels, Publication, and Maintainer Actions. Existing checksum, source-identity, signing, and publication-control details remain subordinate sections. |
| `docs/command-line-interface.md` | `docs/command-line-interface.md` | Aligned Status and Synopsis, added Rights, and retained per-command reference sections for the ten iLibrary commands. A flat option table would not describe their different write plans and refusals adequately. |
| `CHANGELOG.md` | `CHANGELOG.md` | Both use dated versions, an Unreleased section, and categorized changes. Existing released entries are preserved. |
| `docs/README.md` | `docs/README.md` | Both distinguish current guidance, historical planning, and engineering reports. User and maintainer guidance remain separated under the maintainer's subsequent cleanup instruction. |
| `AGENTS.md` | `AGENTS.md` | Shared identity, evidence, rights, archival-writing, and attribution rules are retained. Library-safety rules and handoff requirements are explicit iLibrary constraints. |
| `CLAUDE.md` | Engineering constraints | Imports `AGENTS.md`, so the same constraints govern both agents. |
| `CONTRIBUTING.md` | Engineering constraints and development guidance | Retains formal English, proportional verification, conventional commits, human identities, and evidence classification. iLyrics has no corresponding tracked contributor file. |
| `docs/planning-study.md` | Historical planning baseline | Preserved unchanged; later decisions supersede historical implementation details explicitly. |
| `docs/roadmap-to-stable.md` | `docs/roadmap-to-stable.md` | Retains current status, decisions, work-location constraints, and completed evidence. Milestone numbering and model recommendations follow the approved iLibrary plan. |
| `docs/agent-handoff.md` | Roadmap and engineering constraints | Retains the required Japanese prompt, current authorization boundaries, and next-session state. No equivalent iLyrics document requires identical headings. |
| `docs/catalog-for-agents.md` | Workflow and review guidance | Product-specific catalog procedure retains validation, reviewed changes, and evidence requirements; rendering terminology is not applicable. |
| `docs/library-operations.md` | Workflow and review guidance | Product-specific safety and recovery instructions remain current and link measured results separately from unknown behavior. |
| `docs/live-music-measurements.md` | Verification procedures | Corrected obsolete prose saying the Music probe remained unmeasured; linked the completed probe and separate command-validation reports. |
| `docs/test-library-validation.md` | Verification procedures | Corrected the obsolete pending-gate wording; preserved the Japanese separate-user procedure for a justified future rerun. |
| `docs/package-publishing.md` | Distribution maintainer actions | Retains detailed Japanese account steps, npm Web approval, and GitHub approval instructions requested by the maintainer. |
| Fifteen earlier engineering reports | Historical engineering reports | Preserved unchanged. Their historical states are not rewritten as current claims. |

## Verification and Package Identity

All local Markdown links and anchors passed the review. The four common structures for release notes, support, distribution, and the package template match the reference section sequences. Historical reports and the planning baseline were unchanged from checkpoint `34bf8ed` (measured).

The existing corrected 0.1.0 packages identify packaging commit `55ffea5`, whose README must remain their reference even after the current template changes. Verification previously compared that README with the current working template. It now reads the exact recorded Git commit, and the publication workflow retrieves the necessary history. A synthetic temporary Git repository tests that later README edits do not replace the recorded description; invalid commit identifiers are refused. All ten publication-guard tests passed locally (measured).

The seven existing release assets still matched manifest SHA-256 `70181ee11f14f0174fa236fb12613bfde9a16fa5de50acfcde048c09b70ccc17`. Archive, npm, and pip temporary installations passed with the historical README after the template changes (measured). No executable, tag, registry version, or Music library was changed by this documentation review.

## Publication Boundaries and Remaining Differences

The public npm and PyPI descriptions were read and still use the reviewed 0.1.0 package README structure (measured). The revised source template applies to the next package build; the already published assets retain their approved bytes. A later registry release requires separate authorization.

The GitHub release exists publicly and is marked as a prerelease. Its unauthenticated tag endpoint returned 200, while the latest-release endpoint returned 404 (measured). GitHub does not select prereleases as Latest. iLyrics v0.2.0 was a regular release; this classification difference remains explicit rather than being silently changed during a documentation correction. The maintainer subsequently requested a release-name entry in the repository's Releases sidebar. External release presentation changes remain deferred until the requested local verification instructions have been supplied and the maintainer has checked them.

iLibrary-specific command, catalog, library-safety, and Japanese maintainer sections remain intentional adaptations. Structural agreement does not establish identical product behavior, support coverage, or verification results.

## References

- [iLyrics v0.2.0](https://github.com/x96x64/ilyrics/releases/tag/v0.2.0)
- [iLyrics v1.3.2](https://github.com/x96x64/ilyrics/releases/tag/v1.3.2)
- [iLyrics Documentation at the Reviewed Commit](https://github.com/x96x64/ilyrics/tree/15cc5da4375cf6a9cf1fe6e5f41400509069327e/docs)
- [GitHub Release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
