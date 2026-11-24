#!/bin/sh
# Build lantern for the supported targets into build/<os>-<isa>/, with the test
# runners for Linux and Windows.
# Usage: platform/build-all.sh [TARGET ...]
# A TARGET is linux-x86_64, linux-arm64, linux-riscv64, windows-x86_64,
# windows-arm64, macos-x86_64 or macos-arm64; with none, all 7.
# Runs inside the image from platform/linux/Dockerfile, from the repo root.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
targets="$*"
[ -n "$targets" ] || targets="linux-x86_64 linux-arm64 linux-riscv64 windows-x86_64 macos-x86_64 windows-arm64 macos-arm64"
for target in $targets; do
    case $target in
        linux-x86_64|linux-arm64|linux-riscv64|windows-x86_64|windows-arm64|macos-x86_64|macos-arm64) ;;
        *) echo "build-all.sh: $target is no target" >&2; exit 2 ;;
    esac
done
platform/deps.sh
for target in $targets; do
    platform/${target%%-*}/build.sh ${target#*-} build/$target
done
