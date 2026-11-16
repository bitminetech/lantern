#!/bin/sh
# Link the test runner on a Mac against the objects that build.sh made.
# Usage: platform/macos/link-runner.sh ISA OUT_DIR    (ISA: x86_64 or arm64)
# The runner is test code in C. It uses the host Xcode clang and macOS SDK.
set -eu
isa=$1
out=$2
root=$(cd "$(dirname "$0")/../.." && pwd)

case "$isa" in
  x86_64) arch=x86_64 ;;
  arm64)  arch=arm64 ;;
  *) echo "unknown ISA: $isa" >&2; exit 2 ;;
esac

deps=$(sed "s#^#$out/#" "$out/deps.txt")
deps_off=$(sed "s#^#$out/#" "$out/deps-off.txt")
# runner-<preset>, and runner-<preset>-bls-off for the cases made with signature checks off.
for preset in mainnet minimal; do
    clang -arch $arch -mmacosx-version-min=11.0 -std=c11 -O2 -Wall -Wextra -Werror -DPRESET=\"$preset\" \
        "$root/tests/runner/runner.c" -I"$root/platform/macos" -I"$root/tests/runner" \
        "$root/tests/runner/abi_$isa.s" "$out/liblantern-$preset.a" $deps -o "$out/runner-$preset"
    clang -arch $arch -mmacosx-version-min=11.0 -std=c11 -O2 -Wall -Wextra -Werror -DPRESET=\"$preset\" -DBLS_OFF \
        "$root/tests/runner/runner.c" "$root/tests/runner/bls_off.c" -I"$root/platform/macos" -I"$root/tests/runner" \
        "$root/tests/runner/abi_$isa.s" "$out/liblantern-$preset.a" $deps_off -o "$out/runner-$preset-bls-off"
done
