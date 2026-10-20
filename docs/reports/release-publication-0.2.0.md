# Version 0.2.0 Publication

## Scope and Release Identity

On October 20, 2026 (Asia/Tokyo), experimental version 0.2.0 was published through GitHub, PyPI, npm, and the Homebrew tap, each under the maintainer's explicit authorization. The installed command is `ilibrary` on every channel. npm uses `@x96_64/ilibrary`, PyPI uses `x96_64-ilibrary`, and Homebrew uses `x96x64/tap/ilibrary`. The [Version 0.1.0 Publication](release-publication.md) report remains the historical record of the previous release.

The annotated tag `v0.2.0` (tag object `3fde773ef9750697299686cb4c661dbef88fb4c4`) dereferences to the reviewed source commit `547e407327c85037d6bf72c427eead1ae8b8c362`, the merge of pull request #18. Post-merge CI run 39415534916 passed the macOS and Linux jobs on that commit. The seven release files were built once with `packaging/build.py` from a clean, detached checkout of that commit and passed `packaging/verify.py` with `--install`, the isolated Homebrew harness, and a confidentiality audit of the source archive. Their manifest `SHA256SUMS` has SHA-256 `bc57a4cf6833c5bed0921f03c497169fe2c448390e16343560b71fc4566c906c`. `build-info.json` records the same commit as source and packaging commit, macOS 14.0 as deployment target, ad hoc signing, and no notarization.

| File | SHA-256 |
| --- | --- |
| `ilibrary-0.2.0-macos-arm64.tar.gz` | `b8d18a430d8f8a913aacec337eb9a5c21add41c0429f1456423cc0e12696864c` |
| `x96_64-ilibrary-0.2.0.tgz` | `80e043d00ae058dc1c80ef25feacbba1190d4e1a52fcd22ca92a32ca4bed7725` |
| `x96_64_ilibrary-0.2.0-py3-none-macosx_14_0_arm64.whl` | `84fe95ff22a6fe0e1f6b7dbae8a417f9a23e756eb120cf9748cf865116d07ecf` |
| `ilibrary-0.2.0-source.tar.gz` | `04150bd2fd07e40970f1cf5e0aee46f73161e3954b0a5112945c5daf6bb2d58e` |
| `ilibrary.rb` | `a69cf6e28b29bbe05551452d6093d9784073b6346e4d2dc4b6b9e9bc552a7b9e` |
| `build-info.json` | `88f4b65e3ab31bb4a7353b4eadb465e416a6dbaba95acad8863812d714917bf0` |
| `SHA256SUMS` | `bc57a4cf6833c5bed0921f03c497169fe2c448390e16343560b71fc4566c906c` |

The binary archive, npm archive, and wheel contain the same executable, SHA-256 `df199cea5adb0dac9ae74acdb29e265c4a4b9096f6b72daa6a807d244e6b3787`.

## Channel Results

| Channel | Publication | Measured Verification |
| --- | --- | --- |
| GitHub | Release ID 418355956, published 2026-10-20T12:09:01Z (21:09:01 JST), regular release marked Latest | All seven assets were downloaded and matched the reviewed files byte for byte; the published body matched the approved body byte for byte. |
| Homebrew | Tap pull request [x96x64/homebrew-tap#5](https://github.com/x96x64/homebrew-tap/pull/5), merge commit `ce5827f2d527e93bb8df4b2e990b19f0a3b1b45f`, 2026-10-20T12:32:37Z | The public formula equals the release asset; its source URL serves the archive with the reviewed SHA-256. Installation from the public tap was not performed. |
| PyPI | `pypi` job 118633499774 of run 39424479301; file uploaded 2026-10-20T12:49:46Z (21:49:46 JST) | The public wheel matched the reviewed wheel byte for byte; an isolated installation passed version, schema, and help checks with the reviewed executable bytes. |
| npm | `npm` job 118644482491 of run 39427728491; version time 2026-10-20T13:11:00Z (22:11:00 JST) | The public tarball matched the reviewed archive byte for byte; an isolated installation passed version, schema, and help checks with the reviewed executable bytes. |

These checks ran on one Apple-silicon Mac with macOS 27.0.1. They did not query Music or read personal music files, and they did not change any global installation.

## GitHub Release

The tag was created at 21:08:47 JST and pushed alone without force; the release was created with `gh release create --verify-tag --latest` and the seven files named individually. Its body is `docs/releases/0.2.0.md` at the tagged commit without the archival first heading (SHA-256 `d451a211f68b8d4abba4e2c82b2da6e142796cdcd23abbf2976745170dcd66ad`).

The release was first titled with a feature-specific subtitle that the maintainer had not requested. Under the maintainer's authorization, only the title was then corrected to `iLibrary: v0.2.0, Catalog-Driven Music Libraries for Apple Music on macOS`. A comparison before and after the change showed the release ID, tag, target, draft and prerelease state, creation and publication times, body, and every asset identifier, size, digest, and upload time unchanged (measured). The source archive inside the tagged release retains the original heading of `docs/releases/0.2.0.md`; the heading was corrected afterwards in the development tree, and the immutable tag and assets were not changed. The permanent title convention is recorded in `AGENTS.md` and [Distribution](../distribution.md#release-titles).

## Registry Publication Workflow

The workflow `Publish Reviewed Packages` was dispatched three times for `v0.2.0` from `main`, each with commit `547e407327c85037d6bf72c427eead1ae8b8c362` and manifest digest `bc57a4cf…`, and only after confirming that no other run was pending and that the registries lacked 0.2.0. The GitHub environments `npm` and `pypi` required reviewer `x96x64` and allowed only `main`; the repository and both environments held no Actions secrets. The maintainer confirmed through the registry interfaces that the PyPI trusted publisher (owner `x96x64`, repository `ilibrary`, workflow `release.yml`, environment `pypi`) remained registered and registered the npm trusted publisher with the same owner, repository, and workflow and environment `npm`; these settings are not publicly readable.

Run 39422556251 (`publish=verify`) passed its verification job; the registry jobs were skipped.

Run 39424479301 (`publish=both`) passed verification, and the maintainer approved both deployments. The `pypi` job succeeded. The `npm` job failed after its release recheck and package verification had passed: npm resolved the unprefixed argument `dist/x96_64-ilibrary-0.2.0.tgz` as the GitHub repository shorthand `dist/x96_64-ilibrary-0.2.0.tgz`, ran `git ls-remote ssh://git@github.com/dist/x96_64-ilibrary-0.2.0.tgz.git`, and stopped with exit code 128 before any OIDC exchange or registry request. The npm registry was unchanged. The same parsing was reproduced locally with npm-package-arg 13.0.2: the unprefixed argument is type `git`, and `./dist/x96_64-ilibrary-0.2.0.tgz` is type `file` (measured). The command had not run before, because 0.1.0 was published through staged Web approval.

Pull request [#19](https://github.com/x96x64/ilibrary/pull/19) changed only that argument to `./dist/x96_64-ilibrary-${TAG#v}.tgz` and added a packaging test that requires the prefix; an independent Claude review found no blocking issue, and CI run 39426589001 passed. It was merged as `e74f9acee7d25e47c96582d5ffb85543ea6c0683` (parents `547e407` and `ea4bd05`), and post-merge CI run 39427165151 passed both jobs.

Run 39427728491 (`publish=npm`) was dispatched from `main` at `e74f9ac`; the `pypi` job was skipped. After the maintainer approved the `npm` deployment, the job used Node.js v24.22.0 and npm 11.19.1, published the downloaded tarball with the `latest` tag and public access, and recorded a signed provenance statement in the Sigstore transparency log (index 3337555050).

The package source is the tagged commit `547e407`, whereas the workflow that published npm is the later `main` commit `e74f9ac`. The workflow downloads the release assets and verifies them against the reviewed manifest before publishing, so the published bytes are those of the tagged release.

## Registry Evidence

The PyPI project lists 0.2.0 as its latest version, with the single file `x96_64_ilibrary-0.2.0-py3-none-macosx_14_0_arm64.whl` (683,767 bytes, `Requires-Python >=3.9`). Its PyPI publish attestation names the GitHub publisher `x96x64/ilibrary`, workflow `release.yml`, and environment `pypi`, with a subject digest equal to the reviewed wheel.

The npm package lists `0.0.0-stage`, `0.1.0`, and `0.2.0`, with `latest` at `0.2.0`. Version 0.2.0 declares `darwin` and `arm64`, license `Apache-2.0`, and repository `git+https://github.com/x96x64/ilibrary.git`; its publisher is recorded as GitHub Actions through a GitHub trusted publisher. Its integrity is `sha512-dj2X9Yk1T0AjHeXHyMb692Piv6dVS8LDwJlq6aUlJfjVokDF3YyapYeX1uvecAi8zuR4ZZ41iZQo/C8efAjFNA==`. The npm publish attestation and the SLSA provenance v1 attestation share a subject digest equal to the tarball and identify workflow `.github/workflows/release.yml` at `refs/heads/main` of `x96x64/ilibrary`, resolved commit `e74f9ac`, event `workflow_dispatch`, a GitHub-hosted runner, and run 39427728491. The package README inside the public tarball equals the reviewed package README.

The npm package page displayed the new version and README only some minutes after publication, as the publication notice anticipated; no republication or registry change was made.

## Publication Methods

PyPI used its trusted publisher for both 0.1.0 and 0.2.0. npm 0.1.0 used staged publication with maintainer Web approval; npm 0.2.0 used GitHub Actions trusted publishing through the `npm` job of `release.yml`, selected by the maintainer, and is the first successful use of that route for this project. No access token was created or stored. Sanitized local evidence, downloaded files, and isolated installations remain under ignored `artifacts/`.

## Remaining Limits

Version 0.2.0 remains experimental. `rebuild prepare` was qualified once on a synthetic library of 12 tracks on one Mac with macOS 27.0.1 and Music 1.7 and one external HFS+ backup drive; this does not guarantee recovery of a personal library or backup medium. The Decision F comparison showed equal results for one synthetic library of 12 tracks but did not establish which reader ran, its performance on larger libraries, or its behavior with cloud statuses other than `unknown`; the bulk reader is used only for a consistent result in which every cloud status is exactly `unknown`. iLibrary does not prevent cloud matching, and the staged rebuilding commands are not implemented.

Installation from the public Homebrew tap, Developer ID signing and notarization, Gatekeeper behavior for downloaded executables, bit-for-bit reproducibility, and execution on other macOS releases were not verified. The isolated installations show publication and installation on one Mac only.

Further milestones, including M12, additional live Music qualification, and any new publication, require the maintainer's explicit authorization.
