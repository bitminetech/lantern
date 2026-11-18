#!/bin/sh
# Build lantern for one Linux ISA: the core and shell objects, the dependency
# objects, the test runners for the mainnet and the minimal preset, the shell test, and the
# binary of each preset.
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

# The shell test (tests/shell/shell.c), with the shell object of this target from the library.
clang --target=$target $march -std=c11 -O2 -Wall -Wextra -Werror -static -fuse-ld=lld \
    "$root/tests/shell/shell.c" "$out/liblantern-minimal.a" -o "$out/shell-test"

# The binary, for an ISA whose core has the startup and loop (asm/core/<ISA>/app.s): the entry
# point, the library of the preset, the dependency objects and asm-libp2p's shell, statically
# linked with no C library.
if [ -e "$root/asm/core/$isa/app.s" ]; then
    as -I"$root/include/minimal" -I"$root/include" -I"$root/platform/linux" -I"$root/build/deps/asm-ssz/include" \
        -I"$root/build/deps/asm-crypto/include" -c "$root/asm/shell/linux/$isa/entry.s" -o "$out/entry.o"
    for preset in mainnet minimal; do
        clang --target=$target $march -static -nostdlib -fuse-ld=lld "$out/entry.o" "$out/liblantern-$preset.a" $deps \
            "$out/deps/libp2p-shell.o" -o "$out/lantern-$preset"
    done
fi
