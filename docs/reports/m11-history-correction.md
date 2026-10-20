# M11 Unpublished History Correction

## Purpose and Status

This report records the correction of the unpublished local history of the branch `m11-backup-inventory` on October 20, 2026, under Decision 46. The pre-push review of the 27 commits ahead of `main` at `f91c8ff` found that commit `7dfb24d` had introduced a real local macOS account short name as a literal in `Tests/M11ProbeTests/ProbeLogicTests.swift`, where it served as an example of a user who is not the test user. The name occurred in no commit of `main`. The maintainer judged that a forward-only correction would leave the name permanently accessible through the published history and authorized a narrowly scoped rewrite of the unpublished range solely to replace that literal with a synthetic fixture. The name is not reproduced in this report or in any other tracked file.

M11 remains accepted under Decision 45. The correction changes no product source, no qualification procedure, script, or bundle, no recorded result, and no recorded SHA-256 identity.

## Preconditions and Preservation

Before the rewrite, the branch had no upstream configuration, the remote listed no M11 branch, no other local branch or worktree contained any commit of the range, and the working tree was clean (measured). The commits were unsigned, so no signature was lost.

The complete original branch history was preserved as a Git bundle under ignored `reference-private/m11-history-preservation-2026-10-20/`. `git bundle verify` reported a complete history with head `4fe41d3a254041e8806fe099bd70940f544d64a9`; a bare clone from the bundle contained the same 205 commits and root tree as the branch, and `git fsck` reported no error (measured). A private mapping of every original identifier to its rewritten identifier is kept beside the bundle. No remote backup branch was created, and the bundle is not published.

## Method

The rewrite was limited to the range `f91c8ff..m11-backup-inventory`. The fixture file existed in 17 of the 27 commits, in two distinct historical versions. For each version, a corrected blob was created by replacing the three occurrences of the quoted name with `"user"`, a synthetic name of the same length that does not match the test-user pattern; each corrected blob has the same size as its original, differs in exactly three lines, and contains no occurrence of the name (measured). `git filter-branch --index-filter` then replaced only those two blobs by an exact blob-identifier lookup and stopped on any unexpected blob. No other path, message, or metadata was filtered. The temporary `refs/original` reference created by `filter-branch` was deleted after verification; the original commits remain in the private bundle.

## Equivalence Verification

Every original commit was compared with its rewritten counterpart (measured). The ten commits from `0eb1f75` to `1d26069` precede the fixture and kept their identifiers. For each of the 17 rewritten commits, the commit message, the author and committer names, addresses, and dates, the encoding, and every header other than `tree` and `parent` are byte-identical; each rewritten parent is the image of the original parent; and `git diff` between the original and rewritten commit names only `Tests/M11ProbeTests/ProbeLogicTests.swift`, with exactly the three fixture lines changed. Except for the introducing commit, the patch identifier of every rewritten commit equals that of its original, so each commit introduces the same change as before. The final tree differs from the original final tree only in those three lines. The account name occurs in no tree and no commit message of the rewritten range (measured).

The supported co-author trailers are part of the unchanged messages and are retained. The messages also retain any original commit identifiers they cite.

## Local Verification

Product source, `Package.swift`, `scripts`, the CI workflow, and the Claude Code configuration are identical between the reviewed original head `4fe41d3` and the corrected branch, which additionally differs only in documentation (measured). On the corrected branch at `e808026`, on macOS 27.0.1 (arm64) with Apple Swift 6.4, the release build succeeded, `swift format lint --strict` reported no findings, `scripts/test.sh` passed 363 Swift tests in eight runs, including `ProbeLogicTests` with the corrected fixture, and the packaging (12), validation and collector (176), and response-format hook (85) Python suites passed; the package build and verification with temporary installations passed (measured). The verification run was delegated and its logs were reviewed by the coordinating agent.

## Qualification Provenance

The qualification bundles were built from the original local commits `3b06a078cf8f0fda6774abec2926286065f3e4b7` (first run) and `1de954cb96abd20f66fe58ae46c297b338615dee` (version 2), and their manifests, reports, and recorded SHA-256 values name or describe those commits. These records are historical and are not regenerated or edited. The original commits are not part of the published history; they exist only in the private bundle and the local object store.

The rewritten counterparts are `4beb2dbff8c0891142317d80dfe975f9af42eac1` and `260cddcc511846600fb06ebee608c8dd749ca9f1`. Each has a tree that is byte-identical to its original except for the fixture file, so `Sources`, `Package.swift`, `scripts`, `docs`, and every other path are identical (measured). The bundle preparation script builds the executables from `Sources` and `Package.swift`, copies the procedure and collector scripts, and does not include `Tests/M11ProbeTests` (measured from the script). The rewritten commits therefore contain the same qualification-relevant source as the qualified commits; they are not the commits used during the runs, and the bit-for-bit reproducibility of the bundled executables from them has not been measured.

## Identifier Mapping

Identifiers recorded in reports, decisions, handoff records, commit messages, and bundle manifests before this correction refer to the original local history. The published counterparts are as follows.

| Original | Rewritten | Subject |
| --- | --- | --- |
| `7dfb24d` | `9ca941c` | test(m11): add a read-only Music reader equivalence probe |
| `3b06a07` | `4beb2db` | test(m11): prepare the separate-media qualification bundle |
| `5b10caf` | `2b66311` | docs(m11): record the implementation and qualification preparation |
| `c8649fe` | `c27d685` | docs(agents): require prose-only responses without model recommendations |
| `334d11d` | `ec66afe` | build(agents): enforce the response format with a Claude Code Stop hook |
| `7942483` | `a770eda` | docs(m11): record the first qualification run and its snapshot stop |
| `45489b7` | `fbd704b` | fix(m11): read dates added without AppleScript real-to-text coercion |
| `9fd80f0` | `033d6c2` | test(m11): record the age range of snapshot dates added in the probe |
| `e842f45` | `af6fcdb` | test(m11): prepare the version 2 qualification procedure and bundle |
| `1de954c` | `260cddc` | fix(m11): build each bundled executable separately before packaging |
| `2095194` | `840741d` | docs(m11): record the date correction and version 2 preparation |
| `43fb220` | `f336896` | fix(agents): reject html and disguised lists in the response-format hook |
| `b0ab6a5` | `afc71a3` | docs(m11): assess the version 2 qualification report |
| `865060e` | `ef9c451` | docs(m11): record the version 2 assessment and desktop hook status |
| `0be5b4e` | `e728067` | fix(m11): redact volume UUIDs in the qualification report collector |
| `df4d558` | `8f8dd97` | docs(m11): record the acceptance of M11 under decision 45 |
| `4fe41d3` | `3b6cc9c` | build(agents): add a formal-prose output style and a display hook |

## Remaining Limitations

The original identifiers cited in existing records cannot be resolved in the published repository; this table is the public link between them. The original history, including the replaced name, remains in the private bundle and in local reflogs, which are not published. Whether the bundled executables could be rebuilt bit for bit from the rewritten commits is unknown. The correction was verified locally; CI on GitHub has not yet run on the rewritten branch.
