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
"$root/platform/macos/link-runner.sh" $isa "$root/build/macos-$isa"
echo "== macos $isa"
"$root/tests/runner/run.sh" "$root/build/macos-$isa" "$vectors" "$@"
