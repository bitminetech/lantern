#!/bin/sh
# Run the vectors for macOS on this Mac, against the objects that
# tests/runner/docker.sh built with the pinned LLVM.
# Usage: tests/runner/macos.sh VECTOR_DIR [FILE ...]
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
vectors=$1
shift
case "$(uname -m)" in
  arm64)  isa=arm64 ;;
  x86_64) isa=x86_64 ;;
  *) echo "unsupported Mac: $(uname -m)" >&2; exit 2 ;;
esac
files="$*"
[ -n "$files" ] || files=$(cd "$vectors" && ls *.bin)
"$root/platform/macos/link-runner.sh" $isa "$root/build/macos-$isa"
status=0
for preset in mainnet minimal; do
    echo "== macos $isa $preset"
    "$root/build/macos-$isa/runner-$preset" "$vectors" $files || status=1
    echo "== macos $isa $preset, signatures off"
    "$root/build/macos-$isa/runner-$preset-bls-off" "$vectors" $files || status=1
done
exit $status
