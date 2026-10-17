# Live Library Command Validation

## Scope and Evidence

The maintainer reported the results of `scripts/validation/library-commands.sh` at 00:25 UTC on October 17, 2026, on macOS 27.0.1, using commit `f54659f`. The procedure ran in a separate macOS test user with synthetic albums. No private library was used and no library entries were deleted. These are measured, maintainer-reported results; they were not independently repeated in the maintainer's normal user.

## Results

All twelve reported checks passed, with zero failures:

1. `doctor` succeeded after Automation permission was granted.
2. The dry run retained every staging track.
3. Each input file produced one new library track.
4. Selected source files were moved.
5. Albums were added in release order and confirmed.
6. File and library metadata agreed.
7. Repeating the completed run was safe.
8. An existing track was refused.
9. The refused source remained in place.
10. An incorrect file date was detected.
11. A missing or relocated library file was detected.
12. Restored synthetic files and library records agreed.

## Gate Assessment

The reported run satisfies the remaining M5 live test-library gate and confirms the implemented M6 Music adapter for the cases above. The earlier S3 application probe and substitute-library tests remain separate evidence; this report closes the implementation checks they could not establish.

## Limits

The result does not measure iCloud matching, other macOS or Music versions, all recovery interruptions, or operations on a populated personal Music library. Real Trash operations remain untested. The report contains no persistent IDs, private metadata, or personal paths.
