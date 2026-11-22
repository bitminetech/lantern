#!/bin/sh
# Run the runners of one target over vector files: one process for each
# runner and file, as many at once as the machine has cores.
# Usage: tests/runner/run.sh RUNNER_DIR VECTOR_DIR [FILE ...]
#
# RUNNER_DIR holds runner-<preset>-<fork> and runner-<preset>-<fork>-bls-off, and on
# x86-64 and ARM64 the same with -sha, built with asm-crypto's sha variant (README,
# Target profile). A file <preset>-<fork>-*.bin goes to the runners of its preset and fork;
# other files are left out. With no FILE, every .bin file in VECTOR_DIR runs.
# QEMU is the command that runs the runners for an ISA other than the host's.
# JOBS is the number of processes at once, the number of cores when unset.
# tests/runner/run.ps1 does the same on Windows.
#
# For each runner it prints the file lines in name order, the largest stack of
# each function over its processes, a FUNCTION line for each function (PASS when
# every process that called it passed, else FAIL), and the totals. The status is 0 only when
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
# longest processes start early.
forks="phase0 altair bellatrix capella deneb electra fulu"
for file in $(cd "$vectors" && ls -S $files); do
    preset=${file%%-*}
    rest=${file#*-}
    runner=runner-$preset-${rest%%-*}
    [ -e "$runners/$runner" ] || continue
    echo "$runner $file"
    echo "$runner-bls-off $file"
    if [ -e "$runners/$runner-sha" ]; then
        echo "$runner-sha $file"
        echo "$runner-bls-off-sha $file"
    fi
done > "$logs/work"

# Each process writes runner.file.log, and its exit status as the last line.
xargs -n 2 -P "$jobs" sh -c '
    $QEMU "$1/$4" "$2" "$5" > "$3/$4.$5.log" 2>&1 && code=0 || code=$?
    echo "EXIT $code" >> "$3/$4.$5.log"
' sh "$runners" "$vectors" "$logs" < "$logs/work" || true

status=0
for runner in $(for preset in mainnet minimal; do for fork in $forks; do
                    echo runner-$preset-$fork runner-$preset-$fork-bls-off \
                         runner-$preset-$fork-sha runner-$preset-$fork-bls-off-sha; done; done); do
    set -- "$logs/$runner".*.log
    [ -e "$1" ] || continue
    echo "== $runner${QEMU:+ (under $QEMU)}"
    awk '
        FNR == 1 { ncalled = 0; ok = 0 }
        /^STACK / {
            if (!($2 in peak)) order[++n] = $2
            if (!($2 in peak) || $3 + 0 > peak[$2]) peak[$2] = $3 + 0
            if (index($0, "ABI FAULT")) fault[$2] = 1
            called[++ncalled] = $2
            next
        }
        /^(PASS|FAIL): [0-9]+ passed, [0-9]+ failed$/ {
            passed += $2; failed += $4; totals[FILENAME] = 1; ok = ($1 == "PASS:" && $4 == 0); next
        }
        /^EXIT / {
            if (!(FILENAME in totals)) {
                name = FILENAME; sub(/.*\//, "", name); sub(/\.log$/, "", name)
                print "FAIL " name ": the process ended with status " $2 " and no totals"
                failed++
            }
            if ($2 != 0) ok = 0
            for (i = 1; i <= ncalled; i++) if (!ok) bad[called[i]] = 1    # a function passes only in processes that pass
            next
        }
        { print }
        END {
            for (i = 1; i <= n; i++) printf "STACK %s %d bytes%s\n", order[i], peak[order[i]], fault[order[i]] ? " ABI FAULT" : ""
            for (i = 1; i <= n; i++) printf "FUNCTION %s %s\n", order[i], bad[order[i]] ? "FAIL" : "PASS"
            printf "%s: %d passed, %d failed\n", failed ? "FAIL" : "PASS", passed, failed
            exit failed ? 1 : 0
        }
    ' "$@" || status=1
done
exit $status
