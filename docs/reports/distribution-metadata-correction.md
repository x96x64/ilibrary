# Distribution Metadata Correction

## Scope and Decision

On October 17, 2026, the maintainer selected npm `@x96_64/ilibrary` and PyPI `x96_64-ilibrary` after npm sign-in confirmed the username `x96_64` (measured). These replace the original preparation names before any registry publication. GitHub ownership remains `x96x64`; Homebrew remains `x96x64/tap/ilibrary`. The command remains `ilibrary`.

PyPI normalizes underscores and hyphens for lookup; its normalized project name is `x96-64-ilibrary`. The previous pending publisher for `x96x64-ilibrary` does not authorize the new project. The maintainer reported successful registration for the new name. The Japanese publication procedure records its exact fields.

## Preserved Release Identity

The GitHub prerelease was already published from source `e9c33aed61508678ba941f8d672af6b901ef5cdb`, integrated by pull request #7 at `a1df7f4`. The annotated `v0.1.0` tag remains at that source commit. Both jobs of CI runs 38989392530 and 38989741298 passed (measured).

The reviewed original checksum manifest has SHA-256 `49e1df4e4e46976892ae3d98f37e77bbf72b4fa5d32c02a8b5f22dffa96406ea`. Downloaded GitHub assets matched that manifest (measured). The correction must preserve:

| Item | SHA-256 |
| --- | --- |
| Native executable | `c3dcfa2b5a230dcb2568176f3aef36db00fd7fc1734ee565bcd07ac1fdac214b` |
| Original source archive | `7bf0b4a4af208c9ac0941f5bc46c97f78e8af6ff6a56532e83f6fbaef5c68368` |
| Homebrew formula | `3f7832eda0a9f66e0545e5857c49a97c5b5977b468d699863fbd11ee69a97cef` |

No program rebuild, source-archive change, tag movement, or history rewrite is part of this correction. The immutable source archive retains the original packaging names; current installation instructions supersede those names.

## Correction Procedure

`packaging/repackage.py` checks the original reviewed manifest and every original file before creating a new directory. It carries the exact native executable into the binary archive, npm package, and wheel, regenerates their descriptions and registry identities, and copies the original source archive and formula unchanged. `build-info.json` retains `source_commit` and records the distinct `packaging_commit` and original manifest digest. The new `SHA256SUMS` covers all corrected assets.

The verifier checks the corrected names, metadata, descriptions, wheel records, and identical executable bytes. Temporary installations check version, schema, help, signature, architecture, and deployment target without accessing Music. New guard tests refuse changed original bytes, an unreviewed manifest, and unsafe manifest paths. All eight publication-guard tests passed locally (measured).

## Publication State and Limits

Corrected packages were generated from packaging commit `55ffea5c50b7a98f45af11c544e1a32350169d9f`. Their manifest SHA-256 is `70181ee11f14f0174fa236fb12613bfde9a16fa5de50acfcde048c09b70ccc17`. Archive, npm, and pip installation checks passed, including signature, architecture, deployment target, version, schema, and help (measured). The preserved executable, source archive, and formula matched the hashes above (measured). Replacement of GitHub metadata assets and registry publication remain pending. Existing npm or PyPI versions are never overwritten. The corrected assets identify their packaging commit in the public manifest; the release notes will explain the correction. Final availability and installation results belong in Current Status.

Homebrew tap pull request #1 was merged at `ce35762` (measured). Its formula uses the unchanged source archive. Installation from the public Homebrew tap succeeded, and `brew test` passed version, schema, and help checks (measured). A pending publisher does not reserve a PyPI name, and registry publication is not established by local installation checks.

## References

- [Python Package Name Normalization](https://packaging.python.org/en/latest/specifications/name-normalization/)
- [Creating a PyPI Project with a Trusted Publisher](https://docs.pypi.org/trusted-publishers/creating-a-project-through-oidc/)
- [Version 0.1.0 Release Preparation](release-preparation.md)
- [Distribution](../distribution.md)
