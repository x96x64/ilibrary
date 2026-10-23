# Distribution

## Channels

iLibrary is distributed through three channels that install the same command, `ilibrary`. The npm and PyPI names include the author because the name `ilibrary` was already taken on both registries.

| Channel | Package or Formula | Contents |
| --- | --- | --- |
| Homebrew | `x96x64/tap/ilibrary` | A formula that builds the source archive with Swift 6 |
| npm | `@x96_64/ilibrary` | The prebuilt native executable |
| PyPI | `x96_64-ilibrary` | The prebuilt native executable in a platform wheel |

PyPI normalizes the project name for lookup, so its URL may read `x96-64-ilibrary`. No JavaScript or Python code runs when the installed executable is invoked, and installation neither starts a background service nor changes a Music library. Removing a package removes the executable; it does not undo earlier operations on music files, and catalogs and journals remain the user's recovery records. Use one channel per shell to avoid running an older executable that appears earlier in `PATH`.

## Release Files

Every release attaches the same seven files to its GitHub release. The binary archive, npm archive, and wheel contain identical executable bytes, the Apache license, and the package description. The source archive contains the tracked files of one clean commit and excludes build products, private reference files, and Git internals; the Homebrew formula builds that archive and pins its checksum.

```text
ilibrary-X.Y.Z-macos-arm64.tar.gz
x96_64-ilibrary-X.Y.Z.tgz
x96_64_ilibrary-X.Y.Z-py3-none-macosx_14_0_arm64.whl
ilibrary-X.Y.Z-source.tar.gz
ilibrary.rb
build-info.json
SHA256SUMS
```

All binaries target macOS 14 or later on Apple silicon. The wheel requires Python 3.9 or later for installation, and npm declares `darwin` and `arm64`. The executable is signed ad hoc; Developer ID signing and notarization are not provided, and the packages must not be described as notarized. Linux is supported only for development and tests, and no Linux package is distributed.

## Building and Verifying Packages

From a clean, committed checkout on Apple silicon with Swift 6, Python 3.9 or later, and npm available, build into a directory that does not yet exist and verify the result:

```bash
python3 packaging/build.py artifacts/release-X.Y.Z
python3 packaging/verify.py artifacts/release-X.Y.Z \
  --version X.Y.Z --commit "$(git rev-parse HEAD)" --install
python3 -m unittest discover -s packaging -p 'test_*.py'
```

The builder compiles the current source, checks its version and architecture, strips local symbols, signs the executable ad hoc, and writes the release files with `build-info.json` and `SHA256SUMS`. The verifier checks hashes, package identities, archive contents, licenses, descriptions, wheel records, and the equality of the executable bytes; with `--install`, it also installs the archive, npm package, and wheel into temporary directories from local files and checks the signature, architecture, deployment target, version, schema, and help. The macOS CI job runs the same build and verification on every pull request without publishing anything.

To exercise the Homebrew formula and its test block without changing the public tap, extract the verified source archive and run `brew ruby packaging/verify_homebrew.rb artifacts/release-X.Y.Z/ilibrary.rb SOURCE_DIRECTORY artifacts/homebrew-verification` with a last directory that does not exist. A metadata-only correction uses `packaging/repackage.py`, which regenerates descriptions, identities, and checksums from a later packaging commit while keeping the tagged executable and source archive byte for byte; existing registry versions are never replaced.

## Package Description

The repository [README](../README.md) is the canonical description of the product. [`packaging/README.md`](../packaging/README.md) is its condensed derivative and the only description shipped to npm and PyPI: the builder copies it into the binary archive and the npm package and embeds it in the wheel metadata, and the verifier requires the three copies to be identical.

The derivative keeps the README's order of major sections, its terminology, the installation channels in the order Homebrew, npm, and PyPI, and its installation, signing, cloud-matching, and limitation statements. It omits material that serves repository readers, such as the architecture, contributing, and star history sections, and refers to the README instead. Every link is absolute, because the registries do not resolve repository-relative links. The two documents are reviewed together at every release; a published version's description is never changed, and a revised description appears only with a later version.

## Release Titles

Every GitHub release of iLibrary uses exactly this title, with only `X.Y.Z` replaced by the version number:

```text
iLibrary: vX.Y.Z, Catalog-Driven Music Libraries for Apple Music on macOS
```

The release body consists of an introductory paragraph, an important notice, the version's changelog section, installation and upgrading, and a link to the changelog; `packaging/release_notes.py` generates it. New capabilities are described in the body and in [CHANGELOG.md](../CHANGELOG.md), never in the title.

## Publication

A version is released from a commit on `main` whose CI has passed, whose source version is the new version, and whose changelog section carries the release date. The `Publish Reviewed Packages` workflow, started manually on `main` with the choice `release`, the tag `vX.Y.Z`, and the full commit, then does the rest on a GitHub macOS runner. It checks that neither the tag nor a release exists yet, builds and verifies the seven release files from that exact commit with `packaging/build.py` and `packaging/verify.py --install`, and creates the tag and the GitHub release with the title above, a body generated by `packaging/release_notes.py` from the changelog section, and the files. The run summary records the SHA-256 of `SHA256SUMS`. The Homebrew formula from the release is then committed to `Formula/ilibrary.rb` in the [`x96x64/homebrew-tap`](https://github.com/x96x64/homebrew-tap) repository.

Registry publication runs through the same workflow with the choice `npm`, `pypi`, or `both`, the tag, the commit, and the SHA-256 of the release's `SHA256SUMS`. It has no push or tag trigger. Before each registry job, it rechecks that the tag points at the commit, that the commit is on `main`, that the GitHub release is published, and that the downloaded files match the manifest. The choice `verify` only performs these checks.

The `npm` and `pypi` jobs run in GitHub environments of the same names, which require the approval of `x96x64` and allow only `main`. Both registries use trusted publishing through GitHub Actions OIDC, configured for owner `x96x64`, repository `ilibrary`, workflow `release.yml`, and the matching environment, so no registry token is stored. After publication, installation through each channel is checked and its result recorded; a prepared package is not a published one.

## References

- [npm Trusted Publishing](https://docs.npmjs.com/trusted-publishers/)
- [PyPI Trusted Publishers](https://docs.pypi.org/trusted-publishers/)
- [Python Package Name Normalization](https://packaging.python.org/en/latest/specifications/name-normalization/)
- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [iLyrics Distribution](https://github.com/x96x64/ilyrics/blob/main/docs/distribution.md)
