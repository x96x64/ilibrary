# Documentation Review

## Scope

Milestone M7 reviews the current documentation against the implemented commands. The README follows the iLyrics structure for installation, quick start, usage, internals, troubleshooting, rights, limitations, and contribution guidance. Unsupported package installation and unmeasured performance claims are omitted.

New documents cover interrupted operations and privacy, contribution requirements, and support reports. The Japanese handoff preserves authorization through M7 and the restriction on personal-library operations. The separate-user procedure explains setup, execution, failures, result reporting, and return to the usual user.

## Evidence and Corrections

- **Measured:** the source build and all ten subcommand help pages were checked against the documented command inventory. Local Markdown file targets and heading anchors were checked, and changed English headings were reviewed for MLA title case. Literal command names retain their capitalization.
- **Measured:** all 154 synthetic tests and strict formatting passed locally. The catalog end-to-end script passed 21 checks, and the import script passed 30. Preparation-only validation generated and checked the synthetic Music-command inputs without querying Music. The environment was macOS 27.0.1 on Apple silicon with Apple Swift 6.4.
- **Measured:** source inspection showed that `timestamps --dry-run --script FILE` writes the explicitly requested script while leaving file dates unchanged. The reference now states that exception; omitting `--script` creates no file. On Linux, script generation requires `--dry-run`.
- **Measured:** the M6 automated review reported one mixed-format scan defect. Commit `2eabaf3` adds a regression case and reports unsupported library formats as unexamined. A separate validation-script correction confines the media destination to the test user's own Music folder and checks the restored final state.
- **Inferred:** the revised workflow makes the distinction between tested file operations, substitute-library tests, and live qualification explicit. A documentation review cannot establish application behavior.
- **Unknown:** actual `add`, `check --library`, and permission recovery in a separate user remain unverified. The public test suite and earlier S3 measurements do not close that gate. No personal library, private audio, Apple Account, or real Trash was used in this work.

## Outcome

The documentation review gate is satisfied. Source installation and all implemented commands have current instructions; recovery and report privacy are documented; completed historical reports remain unchanged. M5's live test-library gate is explicitly pending, and M6's deliberate-fault gate is supported by synthetic tests with live adapter confirmation outstanding. M8 personal-library qualification and M9 release work are not started. Integration and CI evidence are recorded in [Current Status](../roadmap-to-stable.md).
