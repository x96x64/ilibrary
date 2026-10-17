# Version 0.1.0 Publication

## Scope and Release Identity

On October 17, 2026, experimental version 0.1.0 was published through GitHub, npm, PyPI, and Homebrew within the maintainer's explicit authorization. The installed command is `ilibrary` on every channel. npm uses `@x96_64/ilibrary`, PyPI uses `x96_64-ilibrary`, and Homebrew uses `x96x64/tap/ilibrary`.

The annotated `v0.1.0` tag retains reviewed source `e9c33aed61508678ba941f8d672af6b901ef5cdb`. Registry metadata was corrected from packaging commit `55ffea5c50b7a98f45af11c544e1a32350169d9f` without changing the executable, original source archive, formula, or source history. The corrected public manifest has SHA-256 `70181ee11f14f0174fa236fb12613bfde9a16fa5de50acfcde048c09b70ccc17`. The earlier preparation and correction reports remain historical records.

## Measured Verification

| Channel | Result |
| --- | --- |
| GitHub | All seven published release assets were downloaded and matched the reviewed corrected manifest. |
| npm | Web approval published version 0.1.0. Registry integrity matched the reviewed archive; an isolated installation from npm retained the reviewed executable bytes and passed version, schema, and help checks. |
| PyPI | GitHub publication run 38991144631 succeeded after maintainer approval. The public wheel checksum matched the reviewed wheel; an isolated installation from PyPI retained the reviewed executable bytes and passed version, schema, and help checks. |
| Homebrew | Tap pull request #1 was merged at `ce35762`. Installation from the public tap built the original source archive; formula tests and separate version, schema, and help checks passed. |

All temporary installations were removed. These checks did not query Music or read personal music files. Local release verification previously passed 154 Swift tests, strict formatting, and the updated eight publication-guard tests. Both macOS and Linux CI jobs passed for the reviewed source, metadata correction, and documentation checkpoint; Current Status links their runs.

## Publication Method and Account Controls

The initial direct npm attempt failed with 404 at the authentication completion endpoint; its cause remains unknown. A retry was canceled at the maintainer's request. The same reviewed archive was staged as `5cde04a5-0ede-487f-a953-c2c42678bd89`, with SHA-1 `60d85b4c9176b750aefd5db0b2dd3ef427ff7c38`, matching the reviewed archive. The maintainer completed Web approval, and the resulting public version passed the checks above. The npm-generated initial placeholder `0.0.0-stage` is part of its staged-publication procedure, not an iLibrary product release.

GitHub publication environments `npm` and `pypi` were created after specific approval. Both were read back and verified to require reviewer `x96x64` and permit only branch `main`. PyPI uses the registered trusted publisher. npm trusted publishing remains optional setup before a future GitHub-driven npm publication; no additional granular access token was configured for 0.1.0 publication.

An automated review of `1e4ee7a` incorrectly claimed that the human author and committer were absent. Local Git and the GitHub commit API both recorded `x96x64` for those identities and the supported Codex co-author trailer. The finding was rejected on measured evidence; attribution history was not rewritten.

## Cleanup and Retained Documentation

Duplicate release downloads, the generated build tree, temporary installations, and obsolete merged branches were removed. Final distribution files, original release provenance, sanitized verification records, and requested actual-file previews remain ignored under `artifacts/`. Private qualification records remain under ignored `reference-private/`.

The documentation index separates user guides, maintainer procedures, and historical records. Publication setup remains useful for later releases. The approved planning study and completed engineering reports remain preserved as required by the repository constraints; temporary products are not published as documentation.

## Remaining Limits and Next Work

Version 0.1.0 remains experimental. Cloud matching, real Trash operations, Developer ID signing and notarization, and execution across every macOS release since the deployment target remain unverified. Catalog representability of real-library track-number gaps and year-only dates remains an open item. Source and metadata commits differ as explicitly recorded above; current installation instructions supersede the original source archive's preparation names.

The publication gate is satisfied. Further feature work requires a proposed milestone based on feedback and unresolved limits. No additional Music or personal-library operation is authorized by publication completion.
