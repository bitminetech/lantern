#!/bin/sh
# Fetch the dependencies that the README pins into build/deps/.
# Runs inside the image from platform/linux/Dockerfile, from the repo root.
# Every library goes into one binary, so each library's own pins of the others
# must be the pins here.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
fetch() {
    dir=$root/build/deps/$1
    if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$2" ]; then
        rm -rf "$dir"
        git init -q "$dir"
        git -C "$dir" fetch -q --depth 1 "https://github.com/bitminetech/$1" "$2"
        git -C "$dir" checkout -q FETCH_HEAD
    fi
}
fetch asm-ssz 3c8c9b405efe432bc0153aa3d0a9a5d31e6d3328       # README Dependencies
fetch asm-crypto e7e0731e379102ad15b927f1558c93b0cb1c93d4    # README Dependencies
fetch asm-snappy b84f65a17f51dead69d22a7f6c5a16f7b2975d2a    # README Dependencies
fetch asm-libp2p 84d113b76577806c9e76eb4b820be16282157b8a    # README Dependencies
fetch asm-quic 533cdb8a777a68b5397324cf73f41ff185e76b21      # README Dependencies
fetch asm-discv5 ba3529f0b1ca6b9ee276c1a3c1cb8d942c865da5    # README Dependencies
fetch asm-rlp 40cca377a1621ed660a73724192a4a0b2c059a84       # README Dependencies

# Each library's pin of another must match ours.
check() {
    theirs=$(sed -n "s/^.*fetch $2 \([0-9a-f]\{40\}\).*/\1/p; s/^$3=\([0-9a-f]\{40\}\).*/\1/p" \
        "$root/build/deps/$1/platform/deps.sh" | head -n 1)
    ours=$(sed -n "s/^fetch $2 \([0-9a-f]\{40\}\).*/\1/p" "$root/platform/deps.sh")
    if [ "$theirs" != "$ours" ]; then
        echo "deps.sh: $1 pins $2 at $theirs, lantern pins $ours" >&2
        exit 1
    fi
}
check asm-ssz asm-crypto commit
check asm-libp2p asm-crypto crypto
check asm-libp2p asm-quic quic
check asm-quic asm-crypto crypto
check asm-discv5 asm-crypto commit
check asm-discv5 asm-rlp commit
