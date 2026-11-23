#!/bin/sh
# Generate the lantern vectors inside the image from platform/linux/Dockerfile.
# Usage: tests/generator/run.sh OUT_DIR    (OUT_DIR must be outside this repo)
#
# OUT_DIR keeps the downloads (sources/), the consensus-specs and beacon-APIs clones
# and the Python environment (.venv/), so a second run downloads nothing again.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$1"
out=$(cd "$1" && pwd)
shift
case "$out/" in
  "$root"/*) echo "run.sh: $out is inside the repo; vectors are stored outside it" >&2; exit 2 ;;
esac

docker build -q -t lantern-build -f "$root/platform/linux/Dockerfile" "$root/platform/linux" >/dev/null
docker run --rm -v "$root:/src" -v "$out:/out" lantern-build sh -eu -c '
    platform/deps.sh
    commit=aa16bb4c156184e9548a997d53efaf2a228a6304    # consensus-specs v1.7.0-beta.4
    spec=/out/consensus-specs
    if [ "$(git -C $spec rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
        rm -rf $spec
        git init -q $spec
        git -C $spec fetch -q --depth 1 https://github.com/ethereum/consensus-specs $commit
        git -C $spec checkout -q FETCH_HEAD
    fi
    apis=/out/beacon-APIs
    commit=88fc9402c6a1821b6e9ae4e3b8ae0a22f1141203    # beacon-APIs v4.0.0
    if [ "$(git -C $apis rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
        rm -rf $apis
        git init -q $apis
        git -C $apis fetch -q --depth 1 https://github.com/ethereum/beacon-APIs $commit
        git -C $apis checkout -q FETCH_HEAD
    fi
    apis5=/out/beacon-APIs-v5
    commit=7911555e6a30c51f9b69bb168111a59f1ff8ee49    # beacon-APIs v5.0.0-beta.0: the validator client additions
    if [ "$(git -C $apis5 rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
        rm -rf $apis5
        git init -q $apis5
        git -C $apis5 fetch -q --depth 1 https://github.com/ethereum/beacon-APIs $commit
        git -C $apis5 checkout -q FETCH_HEAD
    fi
    [ -x /out/.venv/bin/python ] || python3 -m venv /out/.venv
    /out/.venv/bin/pip install -q --disable-pip-version-check -r tests/generator/requirements.txt
    [ -f $spec/tests/core/pyspec/eth_consensus_specs/fulu/mainnet.py ] || (cd $spec && /out/.venv/bin/python -m pysetup.generate_specs --all-forks)
    PYTHONPATH=$spec/tests/core/pyspec:$spec:/src/build/deps/asm-ssz/tests/generator CONSENSUS_SPECS=$spec BEACON_APIS=$apis BEACON_APIS_V5=$apis5 \
        /out/.venv/bin/python tests/generator/generate.py /out "$@"
' sh "$@"
