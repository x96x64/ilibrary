# Decision F Live Comparison of check --library

## Purpose and Status

This procedure compares the read-only command `ilibrary check --library`, and `ilibrary check PATH --library`, between two executables on one new synthetic Music library in the separate macOS test user. The reference executable is built from `9821e686d169b7aee2448ceecf1f9cbe8654026f`, the merge of M11 into `main`, which reads the library one track and property at a time. The candidate executable is built from the Decision F commit recorded in the bundle's `SOURCES` file, the head of pull request #16 when the bundle was prepared. It reads the library in bulk, accepts the bulk result only when every cloud status is exactly `unknown`, and otherwise uses the per-track read (see [Decision F: Bulk Library Read for check --library](reports/decision-f-check-library.md)). Both executables report the version `ilibrary 0.1.0`; `SOURCES` and `SHA256SUMS` identify them, and the bundle is prepared with `sh scripts/validation/prepare-decision-f-comparison.sh --prepare` from a clean checkout of that commit (`--dry-run` creates nothing).

Nothing in this document is a result. The comparison is performed only by the maintainer and only after explicit authorization. A successful comparison shows that the two executables produced byte-identical results for this library, this Mac, and this state. It does not show equivalence for other libraries, sizes, or Music versions, and it cannot show equivalence for cloud statuses other than `unknown`: a test user without an Apple Account and without iCloud Music Library is expected to report only `unknown`, as in the M11 qualification. Equal results also do not show which reader the candidate used: the bulk result and the per-track fallback produce the same output when the readers agree, and nothing in the command's output distinguishes them. The comparison therefore shows that the candidate command's observable results equal the reference's under these conditions, not that its bulk path was exercised; elapsed times may suggest it but do not prove it. Elapsed times from 12 tracks are dominated by process start and script compilation and do not measure the performance of large libraries.

An earlier bundle, `ilibrary-decision-f-comparison.zip` (SHA-256 `f446ff7093e91b512c19e8edf45a1688c96b09997ce571fb9a602178c7578422`), was prepared for commit `6d04b20`, before the cloud-status guard. It was never transferred or run, it is preserved unchanged in the ignored folder `artifacts/decision-f-comparison-preparation/`, and it is superseded by the bundle that this procedure names; do not use it. A second bundle, `ilibrary-decision-f-comparison-v2.zip` (SHA-256 `90a6a78ab236e74954e9cc179d6dcbe55d3b0d6b98eba47ba43b3498057a55fb`), was prepared for commit `9643e64` before its CI had completed and before the comparison script enforced the expected exit statuses and findings. It was never transferred or run, it is preserved unchanged in `artifacts/decision-f-comparison-v2-preparation/`, and it is also superseded; do not use it.

## Scope and Stop Boundaries

The run uses only the 12 original synthetic tracks in this bundle (3 albums by 2 artists, 4 tracks each, distinct release dates). It uses the existing separate test user, whose name begins with `ilibrarytest` or `ilibrary-test`, with no Apple Account signed in and iCloud Music Library off. It creates one new library named `DecisionF-comparison-v3` and adds the synthetic albums with the reference executable's `add` command, which moves them into that library's media folder. Nothing else in Music is changed.

The run never touches the personal library, the usual user's files, any external drive, or Time Machine. It does not open, reuse, rename, empty, move, or delete any earlier library, bundle, folder, or report, including those of M10 and M11 (`M11-qualification`, `M11-qualification-v2`, `~/ilibrary-m11-qualification`, `~/ilibrary-m11-qualification-v2`, and the files in `/Users/Shared` whose names begin with `ilibrary-m11` or `ilibrary-m10`).

Stop at once, change nothing further, and keep the output when any of the following occurs: the user is not the test user; an Apple Account is signed in; a folder or file that this procedure creates already exists; a checksum fails; `doctor` names a media folder outside the new library; the `add` preview or addition refuses anything or reports an unexpected count; Music asks anything other than the Automation permission; `compare.sh` prints `STOP`; or any command fails in a way that this document does not list as expected. Do not repeat a comparison, rerun `add`, delete results, or try to repair the library. After a stop, Step 8 still produces the report.

## Step 0: Transfer the Archive (Usual User)

The preparation produced `ilibrary-decision-f-comparison-v3.zip` and `ilibrary-decision-f-comparison-v3.zip.sha256` in the ignored folder `artifacts/decision-f-comparison-v3-preparation/` of the repository. In the usual user, copy both to `/Users/Shared` without overwriting, and check the copy:

```sh
cd ~/ilibrary/artifacts/decision-f-comparison-v3-preparation &&
cp -n ilibrary-decision-f-comparison-v3.zip ilibrary-decision-f-comparison-v3.zip.sha256 /Users/Shared/ &&
cd /Users/Shared && shasum -a 256 -c ilibrary-decision-f-comparison-v3.zip.sha256
```

If either file already exists in `/Users/Shared`, `cp -n` leaves it unchanged; then stop and compare the checksums instead of replacing anything.

## Step 1: Verify and Extract the Bundle (Test User)

Log out of the usual user completely, log in as the test user, and open Terminal (zsh). Music is not touched in this step.

```sh
cd /Users/Shared &&
shasum -a 256 -c ilibrary-decision-f-comparison-v3.zip.sha256 &&
cd ~ &&
test ! -e ilibrary-decision-f-comparison-v3 &&
unzip -q /Users/Shared/ilibrary-decision-f-comparison-v3.zip &&
cd ~/ilibrary-decision-f-comparison-v3 &&
mkdir results &&
set -o pipefail &&
shasum -a 256 -c SHA256SUMS 2>&1 | tee results/bundle-check.log
```

Every line ends with `OK`. Every later command is run from `~/ilibrary-decision-f-comparison-v3` in a Terminal window in which `set -o pipefail` has been run once.

## Step 2: Restore the Synthetic Dates

Archive extraction does not restore creation dates. This step affects only files in the bundle.

```sh
bin/reference/ilibrary timestamps catalog.json staging --dry-run 2>&1 | tee results/staging-dates.log &&
bin/reference/ilibrary timestamps catalog.json staging 2>&1 | tee -a results/staging-dates.log &&
bin/reference/ilibrary validate catalog.json staging 2>&1 | tee results/validate-staging.log
```

The validation reports 12 matched files and exits with status 0.

## Step 3: Create a New Library

1. Quit Music.
2. Hold the Option key while opening Music, and choose Create Library.
3. Save it in the Music folder of the test user's home under the name `DecisionF-comparison-v3`. If a library of this name exists, stop.
4. Open Settings, then Files, and confirm that the media location is inside the new library's folder. If it is not, choose an empty `Media` folder inside the new library; do not move or change any earlier folder.
5. Confirm that no Apple Account is signed in, that iCloud Music Library (Sync Library) is off, and that Songs shows no tracks. Leave Music open.

## Step 4: Check the Environment

```sh
bin/reference/ilibrary doctor 2>&1 | tee results/doctor.log
```

The output must end with `No problems found.` and name, on a line marked `ok`, the media folder, which must lie inside the `DecisionF-comparison-v3` library folder. A note that the Automation permission is not decided yet or cannot be determined is not a problem; continue. A line marked `problem`, or a media folder outside the new library, means stop; the comparison script applies the same rule and refuses to run when `doctor` reports a problem. Then:

```sh
MEDIA="<the media folder path printed by doctor>"
test -d "$MEDIA" && ls -A "$MEDIA"
```

The media folder must not yet hold a `Music` folder with files in it. If it does, stop.

## Step 5: Add the Synthetic Albums

```sh
bin/reference/ilibrary add staging --order release --dry-run 2>&1 | tee results/add-dry-run.log
```

The preview lists 3 albums and 12 planned moves and states that nothing is changed. macOS may ask whether Terminal may control Music; allow it. If the preview names an existing track or refuses anything, stop. Otherwise run once:

```sh
bin/reference/ilibrary add staging --order release 2>&1 | tee results/add.log
```

The expected result is 3 albums and 12 tracks added, with exit status 0, and Songs shows 12 tracks. Do not edit, play, rename, or delete anything in Music, and do not rerun the command.

## Step 6: Compare the Unchanged Library

Leave Music open and untouched, and do not use the computer for anything else while the script runs.

```sh
zsh compare.sh unchanged "$MEDIA/Music" 2>&1 | tee results/compare-unchanged.log
```

The script refuses to run for another user, with a signed-in Apple Account, with a bundle file that differs from `SHA256SUMS`, with a media folder outside `DecisionF-comparison-v3`, with any target other than `$MEDIA/Music`, or when `results/unchanged` exists. It then runs `check --library` and `check "$MEDIA/Music" --library` with the reference executable, the candidate executable, and the reference executable again, and saves each run's exit status, standard output, and standard error in separate files under `results/unchanged`. Elapsed times are measured by the shell and written only to `results/unchanged/times.txt`. The script then checks every run against the outcome that this phase requires: an exit status of 0, empty standard error, a line `Checked N files against the Music library`, and `No problems found.` as the last line. It compares the two reference runs and the reference and candidate runs byte for byte, records every violation in `results/unchanged/summary.txt`, and ends with `verdict: PASS` only when every condition holds, or with `STOP`. Identical failures of both executables therefore cannot pass.

The expected observation for the unchanged library, which has not yet been observed, is `verdict: PASS`. A difference between the two reference runs means that the library or Music changed during the comparison; a difference between the reference and candidate runs is a Decision F finding; a rejected run, for example because of an error from Music, is listed with its reason. After any `STOP`, change nothing, do not repeat the comparison, and continue with Step 8.

## Step 7 (Optional): Compare After Removing One Synthetic File

This step is separate from Step 6 and may be omitted. It is performed only after Step 6 ended with `verdict: PASS`. In the Finder, open `$MEDIA/Music`, find the folder that holds the album `Decision F Album 02` (by `iLibrary Decision F Synthetic Artist B`), and move exactly one track file of that album to the Trash. Do not empty the Trash and do not change anything in Music. Record the file name of the moved file only, without its folder, for example `03 Decision F Song 02-03.m4a`:

```sh
test ! -e results/removed-file.txt && print -r -- "<the file name of the moved file>" > results/removed-file.txt
zsh compare.sh after-removal "$MEDIA/Music" 2>&1 | tee results/compare-after-removal.log
```

The script refuses this phase before any run unless `results/removed-file.txt` holds exactly one non-empty line. It requires for every run an exit status of 1, empty standard error, a line `Checked N files against the Music library`, a finding `a library track whose file is missing` on a line that contains the recorded file name, and a last line `N problem(s) found.` with a positive N, together with the same byte-for-byte agreement as in Step 6. The expected observation is `verdict: PASS`. The synthetic library is then intentionally inconsistent and is not used for anything else.

## Step 8: Produce One Report

Run the following once, whether the comparison passed, stopped, or was interrupted. It reads the saved files only, writes one new file, and refuses to overwrite an existing report.

```sh
python3 -I df_collect.py /Users/Shared/ilibrary-decision-f-comparison-v3-report.txt
```

The report contains the source commits, the bundle check, the setup logs, and every saved output, status, summary, and time. The redaction rules of the M11 collector apply: the test user's home directory becomes `~`, every `/Volumes/<name>` prefix becomes `/Volumes/BACKUP`, every volume UUID becomes `<uuid>`, and every 16-digit hexadecimal persistent identifier becomes `<id>`. Read the report once before sending it. Return to the usual user and send only this sentence:

> Please assess the Decision F live comparison: /Users/Shared/ilibrary-decision-f-comparison-v3-report.txt

Do not send the library, the audio files, or the bundle. Keep the library `DecisionF-comparison-v3`, the bundle folder, and its `results` folder; do not delete them.

## Evidence Limits

The comparison establishes, at most, byte-identical command results of the two executables for this library state, with cloud status `unknown`, on this Mac and Music version. It does not establish that the candidate's bulk path, rather than its per-track fallback, produced the result, the rendering of other cloud statuses by the bulk read (which the candidate's guard sends to the per-track reader instead), the behavior of larger or personal libraries, the frequency of the per-track fallback, or the performance of either reader. A `PASS` from the script means that no difference was observed; acceptance of the live behavior and any merge of pull request #16 remain the maintainer's decisions.
