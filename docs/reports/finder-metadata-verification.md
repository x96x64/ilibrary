# Finder Metadata and Bundle Verification

## Supplied Inventory and Cause

On October 17, 2026, the maintainer supplied the read-only inventory of the retained M10 v2 bundle. Its format is `ilibrary-m10-bundle-inventory-1`, and a byte-identical copy is retained under ignored `reference-private/m10-display-inventory-2026-10-17/`. The inventory report's SHA-256 is `e529747b427b903448e59f3394e8ad0ba7c0d04be5ea96a920d725a4aaefab12`.

**Measured, supplied inventory:** the original manifest identity matches, all 314 expected files are present, and the only additional regular file is `.DS_Store`. There are no missing or nonregular entries, required-content mismatches, or unreadable expected files. The additional file's contents and the process that created it were not examined. Its basename is the conventional Finder folder-metadata name.

**Confirmed by source inspection and local reproduction:** the old verifier included this additional file in its exact path-set comparison, producing the refusal recorded in [Display-Order Version 2 Results](display-order-v2-results.md). The same refusal was reproduced with a copy of the original prepared bundle and a synthetic `.DS_Store`. This identifies the inventory-check defect without attributing a setup error to the maintainer. The successful content comparison concerns the retained verification bundle, not the current Music library or its backup image.

## Limited Correction

Commit `f6511d56250504d82f1c55c1039905838615ebbc` excludes only regular files named exactly `.DS_Store` from bundle input enumeration. It neither reads their contents nor deletes or rewrites them. Both the display bundle and the retained-bundle verifier use this enumeration. Preparation also excludes these files from its generated manifest.

Required files still undergo inventory and SHA-256 verification. Other extra files, missing inputs, changed required bytes, symbolic links, and nonregular entries are refused. A directory named `.DS_Store` is also refused. Private result directories are pruned before traversal. File-list differences are recorded with paths only in the private diagnostic log, while the refusal reports missing and additional counts.

The original bundle, its manifest, historical results, and previously transferred archives remain unchanged. Media-folder, test-user, registration-identity, backup, removal, and completed-journal guards remain in force. No product command or Swift source changed.

## Verification

**Measured locally:** all seventy-three probe tests passed. Six new tests cover preservation of regular `.DS_Store` files, refusal of other additions and missing entries with private diagnostics, refusal of links and nonregular metadata-name entries, required-content checks in the current bundle, and missing or altered legacy inputs. Existing small-case simulations now construct a full legacy manifest and use the actual retained-bundle verifier rather than replacing it. The localized-media reuse test includes `.DS_Store` and retains all old bytes while performing no new registration addition or removal. Music, GUI responses, and native backup operations remain substituted in these tests.

An offline copy of the original prepared bundle reproduces the historical refusal with a synthetic `.DS_Store`. The corrected verifier accepts the same copy and preserves every file's bytes and modification date. A copy of the new display bundle also verifies with this metadata file present and reports all five cases as unrun. These tests use generated fixtures; they do not operate the test user's library.

The release build completed, 324 synthetic files and eight catalogs were prepared and validated, and the archive's file bytes, CRC, and executable permissions were verified. Bundled scripts and the Japanese procedure match their committed sources. The product executable is byte-identical to display-v2. No new live Music or independent PCM measurement is claimed.

## Replacement Handoff

The replacement is `ilibrary-m10-display-v3`, source commit `f6511d5`. Its archive SHA-256 is `39e80493dc54f093428f1bdf3f62edfbe91b86abc0f1a15ea15fd913bf1b5adc`. The ZIP and checksum were transferred to the shared directory under new names without overwriting prior files; both copies matched.

Follow the [updated Japanese procedure](../rebuild-display-validation.md) in the existing test user. Preserve `.DS_Store`, every earlier bundle, all stopped records, and the old six-track small library. The replacement revalidates small and supplies its missing observations without repeating evacuation or registration removal. The four other cases remain unrun and require separate initially empty synthetic libraries. The completed [inventory diagnostic](../rebuild-bundle-diagnostics.md) must not be repeated.

The agent stops before test-user operations. The next evidence is one `ilibrary-m10-display-v3-report.txt`, including stopped or unrun cases if necessary. Do not bypass a new stop, promise successful qualification, or remove old records to resume a command.

## Remaining Qualification

M10 remains incomplete. This result establishes the retained inputs' integrity and resolves the file-list refusal. Actual Recently Added order, persistence after relaunch, repeat safety, final preservation, and the four fresh cases remain unverified. The earlier one-second addition-date difference is permitted under Decision 33 but supplies no missing GUI evidence.

Automatic GUI emptiness detection and independent physical backup qualification retain their separate limits. No Music query, personal-library operation, push, publication, or M11 implementation occurred during this assessment and correction. Current Status and the handoff record identify the replacement and pending result.
