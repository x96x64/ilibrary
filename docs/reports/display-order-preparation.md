# Display-Order Validation Preparation

## Scope and Evidence

On October 17, 2026, the maintainer authorized preparation of M10 display-order validation under Decision 33, reuse of existing results, and one consolidated reporting procedure. The agent must stop before operations in the separate macOS user. The prepared sources and Japanese procedure are fixed at `3b7e2fe1783cc838aa178147f3e1c7e28f3d72d5`. This is a guarded synthetic probe, not a product `rebuild` implementation.

The [timestamp assessment](rebuild-timestamp-gate.md) and [plan revision](display-order-plan-revision.md) remain unchanged. The measured one-second difference does not fail the revised requirement. Actual Recently Added order and its persistence remain unknown until the maintainer supplies observations.

## Reuse and New Cases

The `small-existing` case checks the fixed version 2 manifest, source commit, original report, saved final registrations, current exact identities and locations, and file/library metadata. It restores the previous synthetic backup into a new directory and reconstructs edited copies for byte and file-date comparison with the current files. It does not repeat evacuation or registration removal. The completed addition is repeated only after its journal is verified as fully added with no remaining source files. Later observations are dated and distinguished from the original run.

Four new isolated cases cover 300 tracks in release order and eight tracks each in `artist`, `artist-desc`, and `artist-release` order. Two synthetic artists with deliberately different name and release-date ordering make the three latter modes distinguishable. Each fresh case starts empty and removes only registrations created by that same run after backup restoration and evacuation verification. IDs, metadata, locations, evacuated files, and the backup are rechecked before every removal. An unexpected registration or file change stops further deletion.

The probe verifies the selected case's exact media folder, refuses the ordinary user before Music access, prevents continuation past an earlier safety stop, and refuses rerunning recorded cases. The new archive does not modify the prior bundle or its evidence. Its dry run creates nothing and does not query Music.

## Observations and Reporting

Addition and expected display lists are fixed before mutation. Recently Added is checked twice, before and after a verified Music quit and relaunch. Japanese numbered choices distinguish the expected order, a different order, and an unknown result. A difference can include the observed album-number sequence, including duplicates or omissions. Every album must be inspected, including cards requiring scrolling.

Timestamp diagnostics retain exact seconds, distinct counts, total and per-album spans, and seconds shared by different albums. Equality does not determine success. The aggregate distinguishes all five cases, incomplete observations, failures, stops, and unrun cases, and requires observed tie and non-tie coverage before declaring synthetic display qualification complete. Human GUI observation and a same-disk backup simulation remain explicitly separate from automatic GUI detection and independent physical backup qualification.

The [Japanese procedure](../rebuild-display-validation.md) covers switching users, selecting the existing small library, creating four named new libraries, answering each prompt, and returning one sanitized report. A completed display mismatch may be followed by the next isolated case; a safety stop prevents further cases. Reports omit personal paths and persistent IDs. Detailed records remain under the test bundle's `reference-private/` directory.

## Local Verification

**Measured:** all sixty-one synthetic probe tests passed: thirty new display-probe tests and thirty-one existing probe tests. Coverage includes a complete substituted small-case reuse without repeated addition or deletion, all four fresh ordering modes, timestamp differences reaching both GUI prompts, missing and differing observations, changed legacy state, unexpected registrations, changed backups or evacuated files, empty-GUI refusal, interruptions, journal restrictions, prior-stop enforcement, and consolidated reporting. These substitute Music and do not measure live behavior.

**Measured:** the release build, generation of 324 synthetic files, both catalogs for each new case, manifest checks, ZIP CRC checks, executable permissions, and refusal from the ordinary user passed. The build emitted the existing warnings about absent Command Line Tools search directories and completed successfully. The archive excludes private records. Its report command correctly lists all five live cases as unrun.

**Measured:** offline native checks restored backups of six and 300 generated files, compared bytes and creation and modification dates, reconstructed matching edited copies, and verified unchanged original copies and backup images. All four fixture order lists also matched the actual `CatalogCore` ordering implementation compiled for this check. Music calls were explicitly disabled in the offline exercise. These checks establish preparation behavior on this Mac, not live display behavior or independent physical backup protection.

## Transfer and Stop Boundary

The new archive is `artifacts/m10-display-preparation/ilibrary-m10-display.zip`; its SHA-256 is `e27697fff4c3cd8af28f0d28d5cab5adf044a78d8b82aba208e8e22f9c1cbe8a`. It and its checksum file were copied to the shared transfer directory without overwriting existing data, and the copies matched. The prior version 2 archive still has SHA-256 `88357de676c877ca6d329920ab93f6a8f37eb242922ce43a171e1da9e67563bd` (measured).

Preparation stops here, before the maintainer switches to the test user and selects Music libraries. No Music query, personal-library access, live registration operation, push, or publication occurred. M10 remains incomplete. The next task is evaluation of the single returned report; failures and unverified conditions must remain distinct, and no product implementation begins before the applicable gate is met.
