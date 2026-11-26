#!/bin/sh
# Build and run the state benchmarks for Linux on one ISA in the lantern-build image
# (bench/README.md). Usage: bench/run.sh ISA VALIDATORS  (from the repository, Docker running)
# VECTORS: the vector folder (default ~/.cache/lantern/vectors).
set -eu
isa=${1:-arm64}
n=${2:-1000000}
vectors=$(cd "${VECTORS:-$HOME/.cache/lantern/vectors}" && pwd)
cd "$(dirname "$0")/.."
docker run --rm -v "$PWD:/src" -v "$vectors:/vectors:ro" lantern-build sh -eu -c '
isa=$1; n=$2
platform/deps.sh >/dev/null
platform/linux/build.sh $isa build/stf-$isa >/dev/null
case "$isa" in
  x86_64)  target=x86_64-linux-gnu;  march="-march=x86-64"; q=qemu-x86_64 ;;
  arm64)   target=aarch64-linux-gnu; march="-march=armv8-a"; q= ;;
  riscv64) target=riscv64-linux-gnu; march="-march=rv64gc -mabi=lp64d"; q=qemu-riscv64 ;;
esac
[ "$isa" = "$(uname -m | sed s/aarch64/arm64/)" ] && q=
. platform/objects.sh
out=build/stf-$isa
deps=""
for name in $CRYPTO_OBJECTS; do deps="$deps $out/deps/crypto-$name.o"; done
deps="$deps $out/deps/ssz.o $out/deps/snappy.o $out/deps/libp2p.o $out/deps/quic.o $out/deps/discv5.o $out/deps/rlp.o"
clang --target=$target $march -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-function -static -fuse-ld=lld \
    -DPRESET=\"mainnet\" -DFORK=$(fork_number fulu) -DFORK_NAME=fulu bench/state.c -Iplatform/linux -Itests/runner \
    tests/runner/abi_$isa.s build/stf-$isa/liblantern-mainnet.a $deps -o build/stf-$isa/bench-state
$q build/stf-$isa/bench-state /vectors $n
# Then the same with asm-crypto'"'"'s sha variant (shell.md, The sha variant), on x86-64 and ARM64.
if [ -e $out/deps/crypto-sha256x.o ]; then
    sha=$(echo "$deps" | sed "s#crypto-sha256\.o#crypto-sha256x.o#")
    clang --target=$target $march -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-function -static -fuse-ld=lld \
        -DPRESET=\"mainnet\" -DFORK=$(fork_number fulu) -DFORK_NAME=fulu bench/state.c -Iplatform/linux -Itests/runner \
        tests/runner/abi_$isa.s build/stf-$isa/liblantern-mainnet.a $sha -o build/stf-$isa/bench-state-sha
    echo "== the sha variant"
    QEMU_CPU=max $q build/stf-$isa/bench-state-sha /vectors $n
fi' sh "$isa" "$n"
