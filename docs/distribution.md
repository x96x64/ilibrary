# Distribution

## Status and Names

Version 0.1.0 is an experimental release. The GitHub prerelease is published; registry publication and installation verification are recorded separately. Current publication and CI results belong in [Current Status](roadmap-to-stable.md).

| Channel | Package or Formula | Installed Command |
| --- | --- | --- |
| npm | `@x96_64/ilibrary` | `ilibrary` |
| PyPI | `x96_64-ilibrary` | `ilibrary` |
| Homebrew | `x96x64/tap/ilibrary` | `ilibrary` |

The npm and PyPI names `ilibrary` were already occupied. The npm login was subsequently confirmed as `x96_64`; the maintainer selected that personal scope instead of creating an organization. The maintainer also selected `x96_64-ilibrary` on PyPI. Registry availability is checked before publication; a pending publisher neither reserves the name nor establishes successful publication. PyPI normalizes underscores and hyphens for lookup, so its project URL may show `x96-64-ilibrary` while the declared name is `x96_64-ilibrary`. PyPI accepts letters, digits, periods, underscores, and hyphens, but not npm's scope syntax. See the [Python package naming specification](https://packaging.python.org/en/latest/specifications/name-normalization/).

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
- `x96_64-ilibrary-0.1.0.tgz`, containing npm package `@x96_64/ilibrary`
- `x96_64_ilibrary-0.1.0-py3-none-macosx_14_0_arm64.whl`
- `ilibrary-0.1.0-source.tar.gz`
- `ilibrary.rb`, for the existing `x96x64/homebrew-tap` repository
- `build-info.json`, with the source commit and sanitized build context
- `SHA256SUMS`, covering the preceding six files

Verification checks hashes, package identities, archive contents, licenses, descriptions, wheel records, and equality of executable bytes. `--install` additionally checks the signature, architecture, deployment target, version, schema, and help after installing the archive, npm package, and wheel into temporary directories. Installation uses local files without consulting a registry and never queries Music. The temporary installations are removed afterwards.

The macOS CI job builds and installs packages; both CI jobs test the publication guards. CI packaging does not publish. To exercise Homebrew's actual formula and test block without registering an installation or changing the existing tap, extract the verified source archive into a temporary directory, then run:

```bash
brew ruby packaging/verify_homebrew.rb artifacts/release-0.1.0/ilibrary.rb \
  EXTRACTED_SOURCE_DIRECTORY artifacts/homebrew-verification
```

The last directory must not exist. This harness uses Homebrew's Ruby libraries with an isolated prefix. It verifies the source build and formula tests, but does not establish download or installation through the public tap. The release preparation report records those distinctions.

## Signing and Compatibility

The packaged executable is ad hoc-signed. Developer ID signing, notarization, and Gatekeeper behavior for browser downloads are unverified. Do not describe these packages as notarized or instruct users to disable Gatekeeper. Source installation remains available. Local testing on macOS 27.0.1 does not establish runtime compatibility with every release since macOS 14.

## Publication Procedure

Publication requires the maintainer's final confirmation after document previews, section summaries and Japanese translations, verification, and cleanup. The release title is `iLibrary: v0.1.0, Catalog-Driven Music Libraries for Apple Music on macOS`; GitHub marks it as a prerelease. npm uses the `latest` distribution tag and PyPI uses numeric version `0.1.0`, so both package descriptions prominently identify it as experimental.

1. Integrate the reviewed branch through a pull request and confirm CI. Finalize the changelog date and publication wording only when their state is known.
2. Build and verify the final clean commit. Retain its full commit ID and the SHA-256 of `SHA256SUMS`; if any source changes, rebuild and verify the packages. Present material documentation changes before pushing.
3. After approval, create `v0.1.0` at that exact commit and a GitHub prerelease using [the release notes](releases/0.1.0.md). Upload exactly the seven files above, without replacing existing registry versions. Any later release-description correction must follow the metadata procedure below.
4. Configure the registry publisher identities described below. Run `Publish Reviewed Packages` on `main` with the tag, exact commit, and reviewed manifest digest. Its default `verify` choice only validates the release. Select a registry only for an approved publication.
5. Publish the generated formula as `Formula/ilibrary.rb` in the existing Homebrew tap through a reviewed change. Keep existing formulas and tap documentation intact; add the iLibrary installation entry.
6. Verify installation through each public channel, record the actual results and any unavailable channel, and update Current Status. A prepared package is not a published or publicly installable package.

The workflow rechecks the tag's commit, integration into `main`, GitHub prerelease state, and reviewed manifest immediately before each registry publication. It does not create tags, releases, assets, or Homebrew commits. It has no push or tag trigger. A changed tag, unintegrated commit, draft release, or mismatched package is refused.

## Metadata Corrections

A metadata-only correction may use a later packaging commit while retaining the tagged executable and source archive. `build-info.json` records both `source_commit` and `packaging_commit`; no tag or source history is rewritten. The binary bytes and source-archive checksum must remain unchanged. The package descriptions, npm identity, wheel metadata, and checksums are regenerated together. Verification uses the corrected packaging checkout when the two commits differ. Run `python3 packaging/repackage.py ORIGINAL_DIRECTORY NEW_DIRECTORY --manifest-sha256 ORIGINAL_REVIEWED_DIGEST` from that clean checkout, then run the verifier against the original source commit with `--install`. The original files and checksum manifest are validated before any output is written. Existing registry versions are never replaced.

The npm and PyPI name corrections for 0.1.0 are recorded in [Distribution Metadata Correction](reports/distribution-metadata-correction.md). The immutable source archive records the original packaging names; use the current installation instructions for the corrected distribution names.

## Registry Setup

The Japanese [Package Publication Setup](package-publishing.md) procedure provides screen-by-screen instructions and the exact values for the maintainer.

GitHub environments `npm` and `pypi` should require maintainer approval. On October 17, 2026, both environments were created after explicit maintainer approval, each with `x96x64` as required reviewer and `main` as the sole allowed branch (measured). No credentials belong in the repository.

For PyPI, configure a [pending trusted publisher](https://docs.pypi.org/trusted-publishers/creating-a-project-through-oidc/) for project `x96_64-ilibrary`, owner `x96x64`, repository `ilibrary`, workflow `release.yml`, and environment `pypi`. This allows first publication without storing a PyPI token in GitHub.

For npm, [trusted publishing](https://docs.npmjs.com/trusted-publishers/) is configured in an existing package's settings, with owner `x96x64`, repository `ilibrary`, workflow `release.yml`, and environment `npm`. First publication may require the maintainer's npm sign-in and two-factor authentication. If needed, publish only the reviewed local archive with `npm publish PATH_TO_REVIEWED_TGZ --access public --tag latest`, then configure trusted publishing for subsequent versions. Do not copy credentials into a document, command argument, or chat. Registry account access and actual permission to publish remain unverified until exercised.

## References

- [iLyrics Distribution](https://github.com/x96x64/ilyrics/blob/main/docs/distribution.md)
- [npm Trusted Publishing](https://docs.npmjs.com/trusted-publishers/)
- [PyPI Trusted Publishers](https://docs.pypi.org/trusted-publishers/)
- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
