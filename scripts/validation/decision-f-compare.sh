#!/bin/zsh
# Decision F comparison: runs `check --library` and `check PATH --library` with the reference executable, the
# candidate executable, and the reference executable again, against one unchanged synthetic library, and
# compares exit status, standard output, and standard error byte for byte. It changes nothing in Music or in
# the library; it writes only a new folder results/<phase> in this bundle. Elapsed times go to separate files.
# Equal results do not show which reader the candidate used: its bulk read is accepted only when every cloud
# status is unknown, and it falls back to the per-track reader otherwise, with no visible difference.
set -u
setopt pipefail
zmodload zsh/datetime

stop() { print -u2 "STOP: $1"; exit 1 }

bundle=${0:A:h}
phase=${1:-}
target=${2:-}
case $phase in
    unchanged|after-removal) ;;
    *) print -u2 'Usage: compare.sh unchanged|after-removal "$MEDIA/Music"'; exit 2 ;;
esac
[[ -n $target ]] || { print -u2 'Usage: compare.sh unchanged|after-removal "$MEDIA/Music"'; exit 2 }

# Preflight: the separate test user, not privileged, with no Apple Account, as the M11 probe requires.
user=$(id -un)
[[ $user == ilibrarytest* || $user == ilibrary-test* ]] || stop "the user $user is not the separate test user"
[[ $(id -u) != 0 ]] || stop 'the command runs as root'
account=$(/usr/bin/defaults export MobileMeAccounts - 2>&1)
account_status=$?
if (( account_status == 0 )); then
    accounts=$(print -r -- "$account" | /usr/bin/plutil -extract Accounts json -o - - 2>/dev/null)
    [[ -z $accounts || $accounts == '[]' ]] || stop 'an Apple Account is signed in'
elif [[ $account != *"does not exist"* && $account != *"not found"* ]]; then
    stop 'the account preference could not be read'
fi

# The executables, scripts, and procedure must match the bundle checksums; the staging files may have moved.
cd "$bundle" || stop 'the bundle folder is not accessible'
grep -v '  staging/' SHA256SUMS | shasum -a 256 -c --quiet - || stop 'a bundle file differs from SHA256SUMS'

# The library must be the new DecisionF-comparison-v2 library, and the target its media Music folder.
doctor=$(bin/reference/ilibrary doctor 2>&1)
media=$(print -r -- "$doctor" | sed -n 's/^.*media folder: //p' | head -n 1)
[[ -n $media && -d $media ]] || stop 'doctor did not report an existing media folder'
[[ $media == */DecisionF-comparison-v2/* ]] || stop "the media folder $media is not inside the DecisionF-comparison-v2 library"
[[ ${target:A} == ${media:A}/Music ]] || stop "the target must be exactly $media/Music"
[[ -d $target ]] || stop "the target $target does not exist"

results=$bundle/results/$phase
[[ ! -e $results ]] || stop "results/$phase already exists; it is not overwritten"
mkdir -p "$results" || stop 'the results folder could not be created'
print -r -- "$doctor" >"$results/doctor.log"
{
    print "phase $phase"
    print "user check passed; no Apple Account signed in"
    print "media folder $media"
    print "target $target"
    cat SOURCES
    shasum -a 256 bin/reference/ilibrary bin/candidate/ilibrary
} >"$results/preflight.log"

# One run: the command's own output streams go to their files; the elapsed time is measured by this shell
# and written to a separate file, so that timing never enters the captured output.
run() {
    local label=$1 executable=$2
    shift 2
    local started=$EPOCHREALTIME
    "$bundle/bin/$executable/ilibrary" "$@" >"$results/$label.stdout" 2>"$results/$label.stderr"
    local code=$?
    local finished=$EPOCHREALTIME
    print -r -- $code >"$results/$label.status"
    printf '%s %.3f\n' "$label" $(( finished - started )) >>"$results/times.txt"
}

for mode in library path; do
    if [[ $mode == library ]]; then arguments=(check --library); else arguments=(check "$target" --library); fi
    print "Running $mode with reference, candidate, and reference again; do not use Music until this finishes."
    run "$mode-reference-1" reference "${arguments[@]}"
    run "$mode-candidate" candidate "${arguments[@]}"
    run "$mode-reference-2" reference "${arguments[@]}"
done

verdict=PASS
for mode in library path; do
    for stream in status stdout stderr; do
        if cmp -s "$results/$mode-reference-1.$stream" "$results/$mode-reference-2.$stream"; then
            print "$mode $stream: reference runs agree" >>"$results/summary.txt"
        else
            print "$mode $stream: REFERENCE RUNS DIFFER (the library state or Music changed)" >>"$results/summary.txt"
            verdict=STOP
        fi
        if cmp -s "$results/$mode-reference-1.$stream" "$results/$mode-candidate.$stream"; then
            print "$mode $stream: candidate identical to reference" >>"$results/summary.txt"
        else
            print "$mode $stream: CANDIDATE DIFFERS FROM REFERENCE" >>"$results/summary.txt"
            verdict=STOP
        fi
    done
    print "$mode exit status: $(<"$results/$mode-reference-1.status") (reference), $(<"$results/$mode-candidate.status") (candidate)" >>"$results/summary.txt"
done
print "verdict: $verdict" >>"$results/summary.txt"
cat "$results/summary.txt"
cat "$results/times.txt"
[[ $verdict == PASS ]] || stop 'see results/'"$phase"'/summary.txt; do not repeat the comparison'
print "The comparison for phase $phase completed. Music and the library were not changed by this script."
