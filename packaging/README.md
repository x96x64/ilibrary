# iLibrary

[![Release](https://img.shields.io/github/v/release/x96x64/ilibrary?include_prereleases)](https://github.com/x96x64/ilibrary/releases)
[![npm](https://img.shields.io/npm/v/%40x96_64%2Filibrary)](https://www.npmjs.com/package/@x96_64/ilibrary)
[![PyPI](https://img.shields.io/pypi/v/x96_64-ilibrary)](https://pypi.org/project/x96_64-ilibrary/)
[![Homebrew](https://img.shields.io/badge/Homebrew-x96x64%2Ftap-FBB040?logo=homebrew&logoColor=white)](https://github.com/x96x64/homebrew-tap)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://github.com/x96x64/ilibrary#requirements)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](https://github.com/x96x64/ilibrary/blob/main/LICENSE)

iLibrary prepares downloaded music for a local Apple Music library. It converts lossless downloads to Apple Lossless, applies a JSON catalog without re-encoding, arranges filenames and dates, and adds albums in a controlled order.

Version 0.1.0 is experimental. Start with copies and a separate test library. iLibrary is not affiliated with, endorsed by, or sponsored by Apple.

## Requirements

- macOS 14 or later on Apple silicon.
- npm or Python 3.9 or later for the corresponding installer. Neither is required by the installed native executable.
- Homebrew installations build from source and require Swift 6 from Xcode or the Command Line Tools.
- Music and Automation permission for library commands; no subscription is required for local processing.

The minimum OS is the deployment target; local qualification used macOS 27.0.1. Packaged binaries are ad hoc-signed, without Developer ID signing or notarization.

## Installation

Choose one channel; all install the same command, `ilibrary`.

### npm

```bash
npm install -g @x96_64/ilibrary@0.1.0
ilibrary --version
```

### PyPI

Install in an isolated environment to avoid changing system Python:

```bash
python3 -m venv .venv-ilibrary
.venv-ilibrary/bin/python -m pip install x96_64-ilibrary==0.1.0
.venv-ilibrary/bin/ilibrary --version
source .venv-ilibrary/bin/activate
```

### Homebrew

```bash
brew install x96x64/tap/ilibrary
ilibrary --version
```

### Updating and Uninstalling

Read the [changelog](https://github.com/x96x64/ilibrary/blob/main/CHANGELOG.md) before updating. Use `npm update -g @x96_64/ilibrary`, `python -m pip install --upgrade x96_64-ilibrary` in the chosen environment, or `brew upgrade ilibrary`, respectively. Packages on npm and PyPI have different names because PyPI does not support npm scopes; neither package is named simply `ilibrary`.

Remove the corresponding installation with `npm uninstall -g @x96_64/ilibrary`, `python -m pip uninstall x96_64-ilibrary`, or `brew uninstall ilibrary`. Removing the executable does not undo file or library changes. Retain catalogs and addition journals needed for recovery.

## Quick Start

Use selected copies in `./downloads` and a new `./staging` directory. Each write has a preview:

```bash
ilibrary import ./downloads -o ./staging --dry-run
ilibrary import ./downloads -o ./staging
ilibrary export ./staging -o catalog.json --artwork covers --dry-run
ilibrary export ./staging -o catalog.json --artwork covers
ilibrary prompt catalog.json > prompt.md
# Complete and review the catalog before applying it.
ilibrary validate catalog.json ./staging
ilibrary apply catalog.json ./staging --rename --timestamps --dry-run
ilibrary apply catalog.json ./staging --rename --timestamps
ilibrary check ./staging
```

For addition to Music, first follow [Test Library Validation](https://github.com/x96x64/ilibrary/blob/main/docs/test-library-validation.md) in a separate macOS user. `add` moves selected sources, stops at an existing matching track, confirms each album, and retains a resumption journal.

## Commands

| Commands | Purpose |
| --- | --- |
| `import` | Convert FLAC, WAV, and AIFF; copy M4A purchases and remove purchase fields |
| `export`, `prompt`, `schema` | Draft a catalog and obtain its authoring instructions and schema |
| `validate`, `apply` | Match a catalog to files, then apply tags, names, and dates |
| `timestamps` | Set release dates without creating missing paths |
| `add` | Move and add albums to Music in release or artist order |
| `check`, `doctor` | Diagnose files, library differences, and the environment |

Use `ilibrary help COMMAND` for options. Every mutating command offers `--dry-run`, lists its plan, and verifies its writes. A batch is not a transaction; earlier completed files can remain after a later failure.

## Verification and Limits

The public suite uses synthetic audio and substitute library adapters. The maintainer separately reported twelve successful live command checks in a test user. Qualification of 301 personal-file copies found no file diagnostic and left originals unchanged. Those results do not establish behavior on every OS version or in a cloud library.

Conversion supports integer mono and stereo PCM. Protected audio is refused. Real Trash operations remain untested. iLibrary reports cloud status but does not claim to prevent Apple Music matching. It does not download recordings or include commercial audio or artwork. Catalogs, prompts, output, and journals can contain private data; review them before sharing.

## Documentation and Support

- [README](https://github.com/x96x64/ilibrary#readme)
- [Command-Line Interface](https://github.com/x96x64/ilibrary/blob/main/docs/command-line-interface.md)
- [Library Operations and Recovery](https://github.com/x96x64/ilibrary/blob/main/docs/library-operations.md)
- [Distribution](https://github.com/x96x64/ilibrary/blob/main/docs/distribution.md)
- [Support](https://github.com/x96x64/ilibrary/blob/main/SUPPORT.md)
- [Current Status](https://github.com/x96x64/ilibrary/blob/main/docs/roadmap-to-stable.md)

## License

iLibrary is licensed under the [Apache License, Version 2.0](https://github.com/x96x64/ilibrary/blob/main/LICENSE).
