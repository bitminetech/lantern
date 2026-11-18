#!/bin/sh
# Build lantern for one Windows ISA: the core and shell objects, the dependency
# objects, the test runner, the shell test and the binary, for the mainnet and the minimal preset.
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

# The shell test (tests/shell/shell.c), with the shell object of this target from the library.
/opt/llvm-mingw/bin/$mingw-clang $march -std=c11 -O2 -Wall -Wextra -Werror -static \
    "$root/tests/shell/shell.c" "$out/liblantern-minimal.a" -o "$out/shell-test.exe"

# The binary, for an ISA whose core has the startup and loop (asm/core/<ISA>/app.s): the entry
# point, the library of the preset, the dependency objects and asm-libp2p's shell, with kernel32,
# shell32, ws2_32 and bcrypt, and no C runtime.
if [ -e "$root/asm/core/$isa/app.s" ]; then
    as -I"$root/include/minimal" -I"$root/include" -I"$root/platform/windows" -I"$root/asm/core/$isa" \
        -I"$root/build/deps/asm-ssz/include" -I"$root/build/deps/asm-crypto/include" \
        -c "$root/asm/shell/windows/$isa/entry.s" -o "$out/entry.o"
    for preset in mainnet minimal; do
        /opt/llvm-mingw/bin/$mingw-clang $march -nostdlib -Wl,--entry=mainCRTStartup -Wl,--subsystem,console \
            "$out/entry.o" "$out/liblantern-$preset.a" $deps "$out/deps/libp2p-shell.o" \
            -lkernel32 -lshell32 -lws2_32 -lbcrypt -o "$out/lantern-$preset.exe"
    done
fi
