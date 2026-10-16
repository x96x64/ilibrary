# iLibrary

[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org)

iLibrary prepares downloaded music for a local Apple Music library and adds it in a controlled order. It converts lossless downloads to Apple Lossless, applies metadata from a catalog file, removes iTunes Store purchase metadata without re-encoding, names files as the Music app does, and adds albums one at a time.

```bash
ilibrary apply catalog.json ~/Music/Staging
```

> [!IMPORTANT]
> iLibrary is in planning and has no released functionality. See the [Technical Planning Study](docs/planning-study.md) and the [roadmap](docs/roadmap-to-stable.md). iLibrary is not affiliated with, endorsed by, or sponsored by Apple.

## Requirements

- macOS 14 or later on Apple silicon
- A Swift 6 toolchain: Xcode 16 or the Command Line Tools 16 or later

## Contributing

Read [AGENTS.md](AGENTS.md) for the engineering constraints, including library safety and the rules for private reference material. Commits follow [Conventional Commits](https://www.conventionalcommits.org/).

## License

iLibrary is licensed under the [Apache License, Version 2.0](LICENSE).
