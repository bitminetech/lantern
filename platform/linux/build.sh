#!/bin/sh
# Build lantern for one Linux ISA: the core and shell objects, the dependency
# objects, and the test runner, for the mainnet and the minimal preset.
# Usage: platform/linux/build.sh ISA OUT_DIR    (ISA: x86_64, arm64 or riscv64)
# Runs inside the image from platform/linux/Dockerfile, after platform/deps.sh.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)

case "$isa" in
  x86_64)  target=x86_64-linux-gnu;  march="-march=x86-64" ;;
  arm64)   target=aarch64-linux-gnu; march="-march=armv8-a" ;;
  riscv64) target=riscv64-linux-gnu; march="-march=rv64gc -mabi=lp64d" ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

as() { clang --target=$target $march "$@"; }
. "$root/platform/objects.sh"
build_objects linux "$out"

# Test runners (C), linked statically so QEMU user mode needs no target libraries:
# runner-<preset>-<fork>, and runner-<preset>-<fork>-bls-off for the cases made with signature checks off.
for preset in mainnet minimal; do
    for fork in $FORKS; do
        flags="-std=c11 -O2 -Wall -Wextra -Werror -static -fuse-ld=lld -DPRESET=\"$preset\" -DFORK=$(fork_number $fork) -DFORK_NAME=$fork"
        clang --target=$target $march $flags \
            "$root/tests/runner/runner.c" -I"$root/platform/linux" -I"$root/tests/runner" \
            "$root/tests/runner/abi_$isa.s" "$out/liblantern-$preset.a" $deps -o "$out/runner-$preset-$fork"
        clang --target=$target $march $flags -DBLS_OFF \
            "$root/tests/runner/runner.c" "$root/tests/runner/bls_off.c" -I"$root/platform/linux" -I"$root/tests/runner" \
            "$root/tests/runner/abi_$isa.s" "$out/liblantern-$preset.a" $deps_off -o "$out/runner-$preset-$fork-bls-off"
    done
done
