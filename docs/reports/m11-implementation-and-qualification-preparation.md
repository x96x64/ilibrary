# M11 Implementation and Qualification Preparation

## Purpose and Status

This report records the M11 implementation on the branch `m11-backup-inventory` and the preparation of the separate-media qualification. It covers the [M11 plan](../m11-plan.md), approved under Decision 41, from the start of implementation under Decision 43. M11 has not passed: its completion gate requires the maintainer-operated qualification described in [M11 Backup and Inventory Qualification](../m11-qualification.md), which has not been run. Findings are classified as measured, inferred, or unknown.

## Implemented Components

| Commit | Component | Decision |
| --- | --- | --- |
| `4ca2f57` | Dependency-free streaming SHA-256 in the Foundation-only `RebuildCore` target | A |
| `cf76157` | File inventory, copy verification, and the APFS and HFS+ timestamp policy | E |
| `09efe9d` | `export --strict`, including declared track and disc totals | Plan |
| `54a76aa` | Bulk Music reader and library snapshot, not yet used by any existing command | F |
| `94be36d` | Storage-device description and the physical-independence decision | C |
| `a6b383c` | Location and capacity validation, registration classification, and the recovery record | Plan |
| `7dda976` | Nanosecond date setting, exclusive restore copies, and mount observation | D, E |
| `12d37d1` | Lexical comparison of restoration paths | D |
| `1d26069` | `rebuild prepare` and `rebuild status`; `stage`, `clear`, `apply`, and `add` remain reserved | B to E |
| `7dfb24d` | `M11Probe`, a read-only comparison of the per-track and bulk Music readers | F |
| `3b06a07` | English qualification procedure, preparation script, and report collection | Plan |

`rebuild prepare` never modifies source files, the backup, or Music registrations. It refuses a backup whose physical disk, volume UUID, filesystem, or contents cannot be established, requires the maintainer's explicit confirmation of a separate device, keeps restored files, does not unmount the backup itself, and writes the recovery record only after the backup volume has disappeared.

## Verification

The following were measured on macOS 27.0.1 with Swift 6.4 at `1d26069` and later commits: the release build, `swift format lint --strict`, and every Swift test run passed (130 command tests, 105 `RebuildCore` tests, 31 `LibraryMac` tests, 11 `M11Probe` tests, and the existing suites). The SHA-256 matched the NIST vectors and CryptoKit. On disk images, APFS stored modification and creation times with nanoseconds, HFS+ stored them truncated to whole seconds, and setting the modification time before the creation time preserved both, whereas the reverse order lowered the creation time. The device description classified the system volume's physical disk, shared it between two temporary directories, and identified disk images. The collection script's 11 tests passed.

The following remain unmeasured: Linux compilation of the new portable code (no Linux environment was available; the Linux CI job includes `RebuildCoreTests`), the execution of the bulk reader's AppleScript against Music and its field-level equivalence with the per-track reader, the cloud status values that Music reports for local-only files (only an empty value and `unknown` are admitted), date preservation by a Finder copy to a real external drive, the device signals of a real USB or Thunderbolt drive, and the real disconnection wait. The change of `check --library` to the bulk reader under Decision F is deferred until the live equivalence is measured.

## Qualification Bundle

The bundle was prepared with `sh scripts/validation/prepare-m11-qualification.sh --prepare` at source commit `3b06a078cf8f0fda6774abec2926286065f3e4b7`. Its manifest format is `ilibrary-m11-qualification-1` with 18 files, including release builds of `ilibrary` and `M11Probe`, 12 synthetic tracks in 3 albums by 2 artists, the catalog, the procedure, and the collection script. The archive `ilibrary-m11-qualification.zip` is 1,280,058 bytes with SHA-256 `3978685ced21ab470b9601726faf0d8134436e31924eb44d422d945a5248ed4e`. The extracted bundle passed its own check, and its procedure equals the repository document. The archive and its checksum file were copied to the shared folder without overwriting, compared byte for byte, and verified there (all measured). The prepared files remain under the ignored `artifacts/m11-qualification-preparation/`.

## Next Step

The maintainer runs the procedure in the separate test user with an external APFS or HFS+ drive and returns `/Users/Shared/ilibrary-m11-qualification-report.txt`. The assessment then evaluates the reader equivalence, the cloud status values, the backup verification and dates, the device-independence refusal and acceptance, the restoration, the disconnection, and the recovery record against the M11 gate.
