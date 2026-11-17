#!/bin/sh
# Build lantern for one Windows ISA: the core and shell objects, the dependency
# objects, and the test runner, for the mainnet and the minimal preset.
# Usage: platform/windows/build.sh ISA OUT_DIR    (ISA: x86_64 or arm64)
# Runs inside the image from platform/linux/Dockerfile, after platform/deps.sh.
# The objects use the pinned LLVM; the runner uses llvm-mingw for the Windows C runtime.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)

case "$isa" in
  x86_64) target=x86_64-w64-windows-gnu;  march="-march=x86-64"; mingw=x86_64-w64-mingw32 ;;
  arm64)  target=aarch64-w64-windows-gnu; march="-march=armv8-a"; mingw=aarch64-w64-mingw32 ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

as() { clang --target=$target $march "$@"; }
. "$root/platform/objects.sh"
build_objects windows "$out"

# runner-<preset>-<fork>.exe, and runner-<preset>-<fork>-bls-off.exe for the cases made with signature checks off.
for preset in mainnet minimal; do
    for fork in $FORKS; do
        flags="-std=c11 -O2 -Wall -Wextra -Werror -static -DPRESET=\"$preset\" -DFORK=$(fork_number $fork) -DFORK_NAME=$fork"
        /opt/llvm-mingw/bin/$mingw-clang $march $flags \
            "$root/tests/runner/runner.c" -I"$root/platform/windows" -I"$root/tests/runner" \
            "$root/tests/runner/abi_$isa.s" "$out/liblantern-$preset.a" $deps -o "$out/runner-$preset-$fork.exe"
        /opt/llvm-mingw/bin/$mingw-clang $march $flags -DBLS_OFF \
            "$root/tests/runner/runner.c" "$root/tests/runner/bls_off.c" -I"$root/platform/windows" -I"$root/tests/runner" \
            "$root/tests/runner/abi_$isa.s" "$out/liblantern-$preset.a" $deps_off -o "$out/runner-$preset-$fork-bls-off.exe"
    done
done
