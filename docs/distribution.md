# Distribution

## Status and Names

Version 0.1.0 is an experimental release prepared for review. Nothing in the preparation process publishes a package. Current publication and CI results belong in [Current Status](roadmap-to-stable.md).

| Channel | Package or Formula | Installed Command |
| --- | --- | --- |
| npm | `@x96x64/ilibrary` | `ilibrary` |
| PyPI | `x96x64-ilibrary` | `ilibrary` |
| Homebrew | `x96x64/tap/ilibrary` | `ilibrary` |

The npm and PyPI names `ilibrary` were already occupied. The proposed names above returned no existing package from the public registry APIs on October 17, 2026 (measured); this is not a reservation or proof of publishing permission. PyPI accepts letters, digits, periods, underscores, and hyphens, but not npm's scope syntax. See the [Python package naming specification](https://packaging.python.org/en/latest/specifications/name-normalization/).

## Package Contents

The packaging approach follows [iLyrics](https://github.com/x96x64/ilyrics): a native executable in the npm archive and platform wheel, a package README with absolute links, and a source-building Homebrew formula. No JavaScript or Python component runs when invoking the installed executable. No additional Swift package dependency is introduced.

The binary archive, npm archive, and wheel contain identical executable bytes, the Apache license, and the same package description. The source archive contains tracked files from one clean commit. It excludes build products, private reference files, local logs, and Git internals. The Homebrew formula builds that source archive; its checksum is generated from the actual archive, without requiring a tag or release to exist during preparation.

All distributed binaries target macOS 14 or later on Apple silicon. The wheel is `py3-none-macosx_14_0_arm64`, with Python 3.9 or later required for installation. npm declares `darwin` and `arm64`. Homebrew requires macOS Sonoma or later, Apple silicon, and a Swift 6 toolchain. Linux support remains limited to portable development and tests; no Linux package is distributed.

## Installation, Updates, and Removal

The [package README](../packaging/README.md) contains the complete installation, update, and removal instructions shared by npm and PyPI. The repository [README](../README.md#installation) also includes Homebrew and source installation. Use only one channel for a given shell to avoid running an older executable earlier in `PATH`.

The packages do not install a background service, download audio, or change a Music library during installation. Removing a package removes the executable; it does not undo earlier operations on music files. Catalogs and addition journals remain user-owned recovery records.

## Building and Verifying Packages

From a clean, committed checkout on Apple silicon with Swift 6, Python 3.9 or later, and npm available:

```bash
python3 packaging/build.py artifacts/release-0.1.0
python3 packaging/verify.py artifacts/release-0.1.0 \
  --version 0.1.0 --commit "$(git rev-parse HEAD)" --install
python3 -m unittest discover -s packaging -p 'test_*.py'
```

The output directory must not already exist. The builder compiles the current source, checks its version and architecture, strips local symbols, signs the staged executable ad hoc, and creates:

- `ilibrary-0.1.0-macos-arm64.tar.gz`
- `x96x64-ilibrary-0.1.0.tgz`, containing npm package `@x96x64/ilibrary`
- `x96x64_ilibrary-0.1.0-py3-none-macosx_14_0_arm64.whl`
- `ilibrary-0.1.0-source.tar.gz`
- `ilibrary.rb`, for the existing `x96x64/homebrew-tap` repository
- `build-info.json`, with the source commit and sanitized build context
- `SHA256SUMS`, covering the preceding six files

Verification checks hashes, package identities, archive contents, licenses, descriptions, wheel records, and equality of executable bytes. `--install` additionally checks the signature, architecture, deployment target, version, schema, and help after installing the archive, npm package, and wheel into temporary directories. Installation uses local files without consulting a registry and never queries Music. The temporary installations are removed afterwards.

The macOS CI job builds and installs packages; both CI jobs test the publication guards. CI packaging does not publish. Homebrew formula validation and its source build are recorded separately in the release preparation report.

## Signing and Compatibility

The packaged executable is ad hoc-signed. Developer ID signing, notarization, and Gatekeeper behavior for browser downloads are unverified. Do not describe these packages as notarized or instruct users to disable Gatekeeper. Source installation remains available. Local testing on macOS 27.0.1 does not establish runtime compatibility with every release since macOS 14.

## Publication Procedure

Publication requires the maintainer's final confirmation after document previews, section summaries and Japanese translations, verification, and cleanup. The release title is `iLibrary: v0.1.0, Catalog-Driven Music Libraries for Apple Music on macOS`; GitHub marks it as a prerelease. npm uses the `latest` distribution tag and PyPI uses numeric version `0.1.0`, so both package descriptions prominently identify it as experimental.

1. Integrate the reviewed branch through a pull request and confirm CI. Finalize the changelog date and publication wording only when their state is known.
2. Build and verify the final clean commit. Retain its full commit ID and the SHA-256 of `SHA256SUMS`; if any source changes, rebuild and verify the packages. Present material documentation changes before pushing.
3. After approval, create `v0.1.0` at that exact commit and a GitHub prerelease using [the release notes](releases/0.1.0.md). Upload exactly the seven files above, without replacing existing assets or versions.
4. Configure the registry publisher identities described below. Run `Publish Reviewed Packages` on `main` with the tag, exact commit, and reviewed manifest digest. Its default `verify` choice only validates the release. Select a registry only for an approved publication.
5. Publish the generated formula as `Formula/ilibrary.rb` in the existing Homebrew tap through a reviewed change. Keep existing formulas and tap documentation intact; add the iLibrary installation entry.
6. Verify installation through each public channel, record the actual results and any unavailable channel, and update Current Status. A prepared package is not a published or publicly installable package.

The workflow rechecks the tag's commit, integration into `main`, GitHub prerelease state, and reviewed manifest immediately before each registry publication. It does not create tags, releases, assets, or Homebrew commits. It has no push or tag trigger. A changed tag, unintegrated commit, draft release, or mismatched package is refused.

## Registry Setup

GitHub environments `npm` and `pypi` should require maintainer approval. No such environments existed in this repository when checked on October 17, 2026 (measured). Their creation and the registries' account settings remain part of the approved publication step; no credentials belong in the repository.

For PyPI, configure a [pending trusted publisher](https://docs.pypi.org/trusted-publishers/creating-a-project-through-oidc/) for project `x96x64-ilibrary`, owner `x96x64`, repository `ilibrary`, workflow `release.yml`, and environment `pypi`. This allows first publication without storing a PyPI token in GitHub.

For npm, [trusted publishing](https://docs.npmjs.com/trusted-publishers/) is configured in an existing package's settings, with owner `x96x64`, repository `ilibrary`, workflow `release.yml`, and environment `npm`. First publication may require the maintainer's npm sign-in and two-factor authentication. If needed, publish only the reviewed local archive with `npm publish PATH_TO_REVIEWED_TGZ --access public --tag latest`, then configure trusted publishing for subsequent versions. Do not copy credentials into a document, command argument, or chat. Registry account access and actual permission to publish remain unverified until exercised.

## References

- [iLyrics Distribution](https://github.com/x96x64/ilyrics/blob/main/docs/distribution.md)
- [npm Trusted Publishing](https://docs.npmjs.com/trusted-publishers/)
- [PyPI Trusted Publishers](https://docs.pypi.org/trusted-publishers/)
- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
