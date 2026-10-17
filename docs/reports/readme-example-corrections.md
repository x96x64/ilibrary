# README Example and Badge Corrections

## Scope

On October 17, 2026, the maintainer requested three README corrections during M10: the placeholder `Title.m4a` in file-name examples was to become `Song.m4a`, the Michael Jackson catalog illustration was to use *Bad* instead of *Thriller*, and the PyPI badge, which displayed "package or version not found" on GitHub, was to show the published version. The maintainer also requested a survey of other illustrative file names. The corrections were integrated into `main` through pull requests #11 and #12 with the maintainer's explicit approval. No package, release, or tag changed.

## README Corrections

The *Bad* illustration had been committed earlier as `363f8e8` under Decision 31, but only on the unpublished M10 branch; `main` still showed *Thriller*. It was cherry-picked onto `main` as `3f066e0`. The README example names `Album Artist/Album/NN Title.m4a`, `NN Title.m4a`, and `D-NN Title.m4a` became `Album Artist/Album/NN Song.m4a`, `NN Song.m4a`, and `D-NN Song.m4a` in `1dc80e0`; the same change is `0c9157f` on the M10 branch. Pull request #11 contained only these two README commits; both CI jobs passed, and it was merged at `c46f885`. The naming rule, command help, implementation, and tests are unchanged.

The catalog excerpt passes `ilibrary validate` against the current schema, and no *Thriller* or "Billie Jean" value remains. The release date of 1987-08-31 agrees with public sources; the composer and the copyright line `℗ 1987 MJJ Productions, Inc.` are the local tag values recorded in Decision 31. An exact public source for the copyright line was not found. The alias `Bad (Remastered)` remains explicitly illustrative.

## Other Illustrative Names

The survey covered every README, user guide, command reference, installation section, catalog example, and directory illustration. Only the root README contained `Title.m4a`. The following were reported to the maintainer and left unchanged, as the instruction limited replacement to the README:

| Location | Text | Classification |
| --- | --- | --- |
| `docs/command-line-interface.md` | `PATH/Album Artist/Album/NN Title.m4a`, `D-NN Title.m4a` | User reference; now differs from the README wording |
| `Sources/ilibrary/ApplyCommand.swift` | `NN Title.m4a` in `apply --help` | Implementation text; protected |
| `Sources/CatalogCore/Naming.swift` | `NN Title.m4a`, `D-NN Title.m4a` in comments | Technical notation; protected |
| `docs/planning-study.md` | `NN-Title_ID.flac`, title-rule examples with real titles, and `Example Album` | Approved historical baseline; preserved |
| `docs/reports/manual-library-curation.md` | `NN Title.m4a` | Historical report; preserved |
| Tests and validation scripts | `01 First Song.m4a`, `01 Purchased Song.m4a`, `1-01 Opening.m4a` | Synthetic fixtures; protected |

The real-title examples in the planning study entered with the planning baseline `aedc1d6`; their selection basis is not recorded (origin unknown). The user guides use only `./staging`, `catalog.json`, and `covers`.

## PyPI Badge

| Classification | Finding |
| --- | --- |
| Measured | The PyPI JSON API returns project `x96-64-ilibrary`, version 0.1.0, for both `x96_64-ilibrary` and `x96-64-ilibrary`; the wheel was uploaded at 01:32:45 UTC. |
| Measured | Shields.io returned `pypi: v0.1.0` at 11:44 and 12:05 UTC for the underscore, hyphen, capitalized, and percent-encoded spellings. For a nonexistent package it returns HTTP 200 with "package or version not found". |
| Measured | Shields.io and GitHub's image proxy send `cache-control: max-age=43200, s-maxage=43200`. The proxy's Tokyo edge returned `pypi: v0.1.0` for the original URL. |
| Measured | All README copies and both registry descriptions used the same badge URL. |
| Inferred | An error image obtained before publication remained in the maintainer's browser cache under the unchanged proxy URL. |

The proxy URL is derived from the image URL, so a cached error persists until it expires. Commit `2ad5269` requests the badge as `https://img.shields.io/pypi/v/x96-64-ilibrary`, the normalized project name, which produces a new proxy URL. The badge remains dynamic, and its link is unchanged. Pull request #12 contained only that README line; both CI jobs passed, and it was merged at `f5457b1`. After the merge, the README on GitHub referenced a new proxy URL that returned `pypi: v0.1.0` from an uncached edge, and both jobs of main CI run 39031397078 passed (measured). The package README retains the original spelling; the published registry descriptions cannot change without a new release.

## Consequences

The M10 branch and its local commits were preserved throughout. Its README equals `main` except for the badge line, so later integration requires no conflict resolution. The remote branches `readme-examples` and `readme-pypi-badge` remain until their removal is approved.
