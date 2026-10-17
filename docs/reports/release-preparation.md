# Version 0.1.0 Release Preparation

## Scope

On October 17, 2026, the maintainer extended version 0.1.0 to npm, PyPI, and Homebrew installation and requested cleanup and a final review before publication. The source version is now `0.1.0`. The package layout and documentation follow iLyrics, with names qualified by the author's identifier: `@x96x64/ilibrary`, `x96x64-ilibrary`, and `x96x64/tap/ilibrary` respectively. All install the command `ilibrary`.

M5/M6 live results and M8 copy qualification are preserved in [Live Library Command Validation](library-command-validation.md) and [Library Copy Qualification](library-qualification.md). Release preparation did not access Music or modify the original media.

## Measured Verification

Local verification used macOS 27.0.1 on Apple silicon with Apple Swift 6.4. The initial package build used source commit `6c172f5`; the identity of each subsequent reviewed build is recorded in its `build-info.json` and `SHA256SUMS`.

| Check | Result |
| --- | --- |
| Swift public suite | All 154 tests passed |
| Swift formatting | Strict lint passed |
| Publication guard tests | All six tests passed without network access |
| Package identity and contents | Versions, names, hashes, licenses, descriptions, wheel records, and source contents passed |
| Executable consistency | Archive, npm package, and wheel contained identical bytes |
| Native binary | arm64, macOS 14 deployment target, ad hoc signature verified |
| Archive installation | Version, schema, and help checks passed |
| npm installation | Local archive installed offline into a temporary prefix; command checks passed |
| PyPI installation | Local wheel installed without an index into a temporary virtual environment; command checks passed |
| Homebrew formula | Actual formula built the archived source, installed into an isolated prefix, and passed its test block |
| Changed package or manifest | Both negative checks were refused |
| Documentation | Repository-relative Markdown links resolved |
| Workflow syntax | Both YAML files parsed successfully |

The Homebrew harness uses the installed Homebrew Ruby libraries without registering a keg or changing the existing tap. It does not claim to verify a public `brew install` download. The npm and pip checks likewise verify local package files, not published registry installations.

## Publication Controls

The new workflow has only a manual trigger, defaults to verification, and publishes existing reviewed assets. It checks the selected tag, full source commit, integration into `main`, GitHub prerelease state, and approved checksum manifest again before each publication. Ordinary source pushes and tag events do not publish registry packages.

No tag, release, package, or tap change was published during preparation. The GitHub repository had no `npm` or `pypi` environments when checked. Registry setup and account access remain unverified; the first npm publication may require the maintainer's sign-in. These are publication prerequisites, not failures of the local installation checks.

## Cleanup and Privacy Audit

Nine obsolete local branches, each verified as merged into `main`, were removed. `main`, the M8 evidence branch, and the active M9 branch were retained. Six corresponding obsolete remote branches remain scheduled for removal with the approved publication work; their history is already reachable from `main`.

The audit of 108 reachable commits before this report found no tracked audio or image files and no tracked `reference-private/`, `artifacts/`, or `.build/` paths. Exact comparisons against the private sample found no personal absolute path in historical blobs. One old normalization-test example matched an album title; the baseline tree had already replaced that example with a synthetic name before this work. Historical attribution and contents were preserved. New commits retain the human author and committer and include the Codex co-author trailer.

Private copies were removed after their checks; private catalogs and measurement records remain ignored. Generated build trees, obsolete validation outputs, temporary installations, and superseded candidate packages are cleanup targets. Retain the final seven distribution files, their sanitized verification records, and the requested document preview until the publication decision.

## Remaining Gates

- The maintainer's judgment on the M8 copy results and final publication approval.
- macOS and Linux CI for the new branch, which has not been pushed.
- Registry account setup, first publication, and actual installation through all three public channels.
- Developer ID signing, notarization, real Trash behavior, additional OS versions, and cloud matching remain unverified. The release notes retain these limitations.

The next action is final document and package review. After approval, integrate through a pull request, verify CI, create the experimental release from the reviewed final commit, publish the packages and formula, and record each actual outcome separately.
