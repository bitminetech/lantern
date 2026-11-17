#!/bin/sh
# Run the four runners of one target over vector files: one process for each
# runner and file, as many at once as the machine has cores.
# Usage: tests/runner/run.sh RUNNER_DIR VECTOR_DIR [FILE ...]
#
# RUNNER_DIR holds runner-<preset> and runner-<preset>-bls-off. With no FILE,
# every .bin file in VECTOR_DIR runs. QEMU is the command that runs the runners
# for an ISA other than the host's. JOBS is the number of processes at once,
# the number of cores when unset. tests/runner/run.ps1 does the same on Windows.
#
# For each runner it prints the file lines in name order, the largest stack of
# each function over its processes, and the totals. The status is 0 only when
# every case passes and every process ends with its totals.
set -eu
runners=$(cd "$1" && pwd)
vectors=$(cd "$2" && pwd)
shift 2
files="$*"
[ -n "$files" ] || files=$(cd "$vectors" && ls *.bin)
jobs=${JOBS:-$(getconf _NPROCESSORS_ONLN)}
QEMU=${QEMU:-}
export QEMU
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT

# One work line for each runner and file, the largest files first, so that the
# longest processes start early. A file goes to the runners of its preset.
for file in $(cd "$vectors" && ls -S $files); do
    preset=${file%%-*}
    echo "runner-$preset $file"
    echo "runner-$preset-bls-off $file"
done > "$logs/work"

# Each process writes runner.file.log, and its exit status as the last line.
xargs -n 2 -P "$jobs" sh -c '
    $QEMU "$1/$4" "$2" "$5" > "$3/$4.$5.log" 2>&1 && code=0 || code=$?
    echo "EXIT $code" >> "$3/$4.$5.log"
' sh "$runners" "$vectors" "$logs" < "$logs/work" || true

status=0
for runner in runner-mainnet runner-mainnet-bls-off runner-minimal runner-minimal-bls-off; do
    set -- "$logs/$runner".*.log
    [ -e "$1" ] || continue
    echo "== $runner${QEMU:+ (under $QEMU)}"
    awk '
        /^STACK / {
            if (!($2 in peak)) order[++n] = $2
            if (!($2 in peak) || $3 + 0 > peak[$2]) peak[$2] = $3 + 0
            if (index($0, "ABI FAULT")) fault[$2] = 1
            next
        }
        /^(PASS|FAIL): [0-9]+ passed, [0-9]+ failed$/ { passed += $2; failed += $4; totals[FILENAME] = 1; next }
        /^EXIT / {
            if (!(FILENAME in totals)) {
                name = FILENAME; sub(/.*\//, "", name); sub(/\.log$/, "", name)
                print "FAIL " name ": the process ended with status " $2 " and no totals"
                failed++
            }
            next
        }
        { print }
        END {
            for (i = 1; i <= n; i++) printf "STACK %s %d bytes%s\n", order[i], peak[order[i]], fault[order[i]] ? " ABI FAULT" : ""
            printf "%s: %d passed, %d failed\n", failed ? "FAIL" : "PASS", passed, failed
            exit failed ? 1 : 0
        }
    ' "$@" || status=1
done
exit $status
