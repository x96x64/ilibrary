# Release Presentation and Maintainer Verification

## Scope and Decision

On October 17, 2026, the maintainer requested a release-name entry in the repository's Releases sidebar and completion of local checks before changing external release presentation. This report records the subsequent maintainer-reported checks and the authorized presentation update. It does not supersede the historical publication or documentation-conformance reports except for the current display state.

Version 0.1.0 remains experimental. Its regular GitHub release classification and Latest marker concern discovery, not interface stability, notarization, or broader compatibility. No version, source tag, package, or registry identity was changed.

## Maintainer Verification

The maintainer supplied successful npm installation, version, command help, schema output, and synthetic-catalog validation results (measured, maintainer-reported).

An additional local procedure exported a catalog from one selected album containing ten M4A files, created independent copies under ignored `reference-private/`, checked correspondence, and previewed movement. The planned tag-change count was zero. The maintainer then reported these successful checks (measured, maintainer-reported):

- All ten copies moved into the catalog-derived directory arrangement.
- Copied file bytes, creation dates, and modification dates remained identical after movement.
- The repeated preview planned no additional move.
- Original bytes, names, creation dates, and modification dates remained identical to the initial snapshot.
- No Music automation or library registration was performed.

Catalogs, source paths, snapshots, and detailed logs remain private. The temporary local procedure is retained under ignored `artifacts/`; it verifies the published executable checksum before use and refuses movement when the preview contains a tag change. An input-handling correction accepts quoted and shell-escaped folder paths without executing shell input. Synthetic checks confirmed copy movement, dry-run behavior, and refusal before movement when tag changes were planned. This run is not a new lossless-decoding or live Music-registration measurement.

## Measured Release State

The existing GitHub release was updated in place to `prerelease: false` and explicitly marked as Latest. Its body now matches `docs/releases/0.1.0.md` after omission of the archival first heading, following the reviewed iLyrics structure. The public Latest endpoint returned `v0.1.0` with the same release identifier (measured).

All seven release asset identifiers, names, sizes, and GitHub-reported digests matched the saved pre-update state (measured). The reviewed manifest remains `70181ee11f14f0174fa236fb12613bfde9a16fa5de50acfcde048c09b70ccc17`; source remains `e9c33ae` and recorded packaging remains `55ffea5`. No asset was uploaded, replaced, or deleted during this presentation change.

## Publication Controls

The publication guard previously required GitHub's prerelease classification. It now accepts either published display classification for an experimental `v0.x.y` tag, so the authorized Latest presentation does not invalidate verification. Drafts, mismatched release tags, moved source tags, unintegrated source commits, and invalid identifiers remain refused. The separate package verifier retains the reviewed manifest and package-content checks. Twelve guard tests passed locally (measured), including acceptance of the regular experimental release and refusal of drafts and mismatched tags in both classifications.

The existing npm version was not republished. Its publication used npm Web approval rather than the GitHub `npm` job, so no corresponding GitHub deployment was created. An additional GitHub Packages distribution was not requested. Trusted publishing remains optional setup before a future GitHub-driven npm version.

## Next Work

The historical outlook to version 1.0.0 has been retrieved and presented. The maintainer selected GPT-6-Astra for a new plan and requested a stop immediately before planning. A subsequent workflow clarification concerns staging and reinserting already registered albums among existing albums. Version 0.1.0 refuses matching existing registrations and does not implement this operation. The requirement is retained for planning without a new implementation or personal-library operation.
