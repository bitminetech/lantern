#!/bin/sh
# Build lantern for one macOS ISA: the core and shell objects and the
# dependency objects, for the mainnet and the minimal preset.
# Usage: platform/macos/build.sh ISA OUT_DIR    (ISA: x86_64 or arm64)
# Runs inside the image from platform/linux/Dockerfile, after platform/deps.sh, so
# the objects use the pinned LLVM. link-runner.sh links the runner on a Mac.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)

case "$isa" in
  x86_64) target=x86_64-apple-macos11 ;;
  arm64)  target=arm64-apple-macos11 ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

as() { clang --target=$target "$@"; }
. "$root/platform/objects.sh"
build_objects macos "$out"
echo $deps | tr ' ' '\n' | sed "s#^$out/##" > "$out/deps.txt"
echo $deps_off | tr ' ' '\n' | sed "s#^$out/##" > "$out/deps-off.txt"

# The entry point of the binary (asm/shell/macos/<ISA>/entry.s), for an ISA whose core has the
# startup and loop (asm/core/<ISA>/app.s). link-runner.sh links the binary on a Mac.
if [ -e "$root/asm/core/$isa/app.s" ]; then
    as -I"$root/include/minimal" -I"$root/include" -I"$root/platform/macos" -I"$root/asm/core/$isa" \
        -I"$root/build/deps/asm-ssz/include" -I"$root/build/deps/asm-crypto/include" \
        -c "$root/asm/shell/macos/$isa/entry.s" -o "$out/entry.o"
fi
