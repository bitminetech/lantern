#!/bin/sh
# The lantern binary beside lighthouse on one Docker network, from one genesis (tests/app/network.py:
# mainnet preset, fulu at epoch 0, 64 validators). Passes when each Beacon API shows the other
# node as a connected peer, and still does two slots later.
# Usage: tests/app/interop.sh BINARY WORK_DIR [SECONDS]
#   BINARY: lantern-mainnet for Linux on the ISA of this machine.
#   WORK_DIR: outside this repo; it keeps the generator's environment (as tests/generator/run.sh)
#   and the network directory.
#   SECONDS: the longest wait for the connection (default 120).
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
binary=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
mkdir -p "$2"
work=$(cd "$2" && pwd)
secs=${3:-120}
lighthouse=sigp/lighthouse:v8.1.3@sha256:44aa773dcf274122c32cc41c4dae7124ed3cab5c267ee82174c6dfd9c688da96
net=lantern-interop

# The network directory, with the pinned spec, and a JWT secret for lighthouse; and the check of
# include/trusted_setup_4096.bin against the pinned spec.
docker build -q -t lantern-build -f "$root/platform/linux/Dockerfile" "$root/platform/linux" >/dev/null
genesis=$(( $(date +%s) + 30 ))
docker run --rm -v "$root:/src" -v "$work:/out" lantern-build sh -eu -c '
    platform/deps.sh
    commit=aa16bb4c156184e9548a997d53efaf2a228a6304    # consensus-specs v1.7.0-beta.4
    spec=/out/consensus-specs
    if [ "$(git -C $spec rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
        rm -rf $spec
        git init -q $spec
        git -C $spec fetch -q --depth 1 https://github.com/ethereum/consensus-specs $commit
        git -C $spec checkout -q FETCH_HEAD
    fi
    [ -x /out/.venv/bin/python ] || python3 -m venv /out/.venv
    /out/.venv/bin/pip install -q --disable-pip-version-check -r tests/generator/requirements.txt
    [ -f $spec/tests/core/pyspec/eth_consensus_specs/fulu/mainnet.py ] || (cd $spec && /out/.venv/bin/python -m pysetup.generate_specs --all-forks)
    PYTHONPATH=$spec/tests/core/pyspec:$spec:/src/build/deps/asm-ssz/tests/generator CONSENSUS_SPECS=$spec \
        /out/.venv/bin/python tests/app/network.py /out/net mainnet fulu "$1" 64
    /out/.venv/bin/python tests/app/trusted_setup.py $spec --check
    od -An -tx1 -N32 /dev/urandom | tr -d " \n" > /out/net/jwt.hex
' sh "$genesis"

cleanup() {
    docker rm -f lantern-interop-lh lantern-interop-ln >/dev/null 2>&1 || true
    docker network rm $net >/dev/null 2>&1 || true
}
cleanup
trap cleanup EXIT
docker network create --subnet 172.30.0.0/24 $net >/dev/null
docker run -d --name lantern-interop-lh --network $net --ip 172.30.0.10 -v "$work/net:/net" $lighthouse lighthouse bn \
    --testnet-dir /net --datadir /tmp/lh --execution-endpoint http://127.0.0.1:8551 --execution-jwt /net/jwt.hex \
    --enr-address 172.30.0.10 --port 9000 --http --http-address 0.0.0.0 --disable-upnp --target-peers 4 \
    --allow-insecure-genesis-sync --enable-private-discovery --disable-peer-scoring >/dev/null
api() { docker run --rm --network $net lantern-build curl -s --max-time 3 "http://$1:5052$2" || true; }

# Lighthouse's record, then lantern with it as its boot node.
enr=
waited=0
while [ -z "$enr" ] && [ $waited -lt 60 ]; do
    sleep 3; waited=$((waited + 3))
    enr=$(api 172.30.0.10 /eth/v1/node/identity | sed -n 's/.*"enr":"\(enr:[^"]*\)".*/\1/p')
done
[ -n "$enr" ] || { echo "FAIL lighthouse gave no record"; docker logs lantern-interop-lh 2>&1 | tail -20; exit 1; }
docker run -d --name lantern-interop-ln --network $net --ip 172.30.0.11 -v "$binary:/lantern:ro" -v "$work/net:/net:ro" \
    lantern-build /lantern --network-dir /net --port 9000 --http-port 5052 --enr-address 172.30.0.11 --boot-nodes "$enr" >/dev/null

# Each node shows the other as connected; then again two slots later.
connected() {
    id=$(api 172.30.0.11 /eth/v1/node/identity | sed -n 's/.*"peer_id":"\([^"]*\)".*/\1/p')
    api 172.30.0.11 /eth/v1/node/peer_count | grep -q '"connected":"[1-9]' || return 1
    [ -n "$id" ] && api 172.30.0.10 /eth/v1/node/peers | grep -q "\"peer_id\":\"$id\"[^}]*\"state\":\"connected\""
}
status=1
waited=0
while [ $waited -lt "$secs" ]; do
    sleep 5; waited=$((waited + 5))
    if connected; then
        sleep 24
        connected && status=0
        break
    fi
done
echo "== lantern"
docker logs lantern-interop-ln 2>&1 | grep -v "record enr" | head -20
echo "== lighthouse peers"
api 172.30.0.10 /eth/v1/node/peers
echo
if [ $status -eq 0 ]; then echo "PASS lantern and lighthouse are connected peers"; else echo "FAIL lantern and lighthouse are not connected peers"; docker logs lantern-interop-lh 2>&1 | tail -30; fi
exit $status
