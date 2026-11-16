#!/bin/sh
# Build every target in Docker, then run the vectors for the three Linux ISAs.
# Usage: tests/runner/docker.sh VECTOR_DIR [FILE ...]
#
# Outputs go to build/<os>-<isa>/. Linux ISAs other than the build host's own
# run under QEMU user mode. With no FILE, every .bin file in VECTOR_DIR runs.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
vectors=$(cd "$1" && pwd)
shift
image=lantern-build

docker build -q -t "$image" -f "$root/platform/linux/Dockerfile" "$root/platform/linux" >/dev/null
docker run --rm -v "$root:/src" -v "$vectors:/vectors:ro" "$image" sh -eu -c '
    platform/build-all.sh
    files="$*"
    [ -n "$files" ] || files=$(cd /vectors && ls *.bin)
    host=$(uname -m)
    status=0
    for isa in x86_64 arm64 riscv64; do
        case $isa in
          x86_64)  machine=x86_64;  qemu=qemu-x86_64 ;;
          arm64)   machine=aarch64; qemu=qemu-aarch64 ;;
          riscv64) machine=riscv64; qemu=qemu-riscv64 ;;
        esac
        [ "$machine" = "$host" ] && qemu=""
        for preset in mainnet minimal; do
            echo "== linux $isa $preset${qemu:+ (under $qemu)}"
            $qemu build/linux-$isa/runner-$preset /vectors $files || status=1
            echo "== linux $isa $preset, signatures off${qemu:+ (under $qemu)}"
            $qemu build/linux-$isa/runner-$preset-bls-off /vectors $files || status=1
        done
    done
    exit $status
' sh "$@"
