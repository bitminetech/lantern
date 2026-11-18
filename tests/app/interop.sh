#!/bin/sh
# The lantern binary beside another consensus client on one Docker network, from one genesis
# (tests/app/network.py: mainnet preset, fulu at epoch 0, 64 validators). Passes when each Beacon
# API shows the other node as a connected peer, and still does two slots later.
# Usage: tests/app/interop.sh CLIENT BINARY WORK_DIR [SECONDS]
#   CLIENT: lighthouse, prysm, teku, nimbus, lodestar or grandine, at the image pinned below. Its
#   command line follows its launcher in ethpandaops/ethereum-package (src/cl/<client>/).
#   BINARY: lantern-mainnet for Linux on the ISA of this machine.
#   WORK_DIR: outside this repo; it keeps the generator's environment (as tests/generator/run.sh)
#   and the network directory.
#   SECONDS: the longest wait for the connection (default 180).
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
client=$1
binary=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
mkdir -p "$3"
work=$(cd "$3" && pwd)
secs=${4:-180}
net=lantern-interop
peer=172.30.0.10                            # the client; lantern is 172.30.0.11
engine="http://127.0.0.1:8551"              # no execution engine runs: the clients only peer
env=
# Keys of the pinned config that prysm's strict YAML parse does not know: with them it falls back to
# its built-in mainnet config. prysm-config.yaml is config.yaml without them.
prysm_unknown="EIP8321_FORK_VERSION|EIP8321_FORK_EPOCH|EIP8198_FORK_VERSION|EIP8198_FORK_EPOCH|INCLUSION_LIST_DUE_BPS|SLOT_DURATION_MS_EIP8198|MAX_REQUEST_INCLUSION_LIST|MIN_SLOTS_FOR_INCLUSION_LISTS_REQUESTS|MAX_TRANSACTIONS_BYTES_PER_INCLUSION_LIST|MIN_BLOB_DATA_RETENTION_MS"
case $client in
  lighthouse)
    image=sigp/lighthouse:v8.1.3@sha256:44aa773dcf274122c32cc41c4dae7124ed3cab5c267ee82174c6dfd9c688da96
    set -- lighthouse bn --testnet-dir /net --datadir /tmp/data --execution-endpoint $engine --execution-jwt /net/jwt.hex \
        --enr-address $peer --port 9000 --http --http-address 0.0.0.0 --http-port 5052 --disable-upnp --target-peers 4 \
        --allow-insecure-genesis-sync --enable-private-discovery --disable-peer-scoring ;;
  prysm)
    image=offchainlabs/prysm-beacon-chain:v7.3.1@sha256:ad79198a2968b2442c80b7279f2613b61d882913ed372feb057ea624ba205e29
    set -- --accept-terms-of-use=true --datadir=/tmp/data --chain-config-file=/net/prysm-config.yaml --genesis-state=/net/genesis.ssz \
        --contract-deployment-block=0 --p2p-host-ip=$peer --p2p-tcp-port=9000 --p2p-udp-port=9000 --p2p-quic-port=9001 \
        --p2p-static-id=true --p2p-colocation-whitelist=0.0.0.0/0,::/0 --min-sync-peers=0 --http-host=0.0.0.0 --http-port=5052 \
        --execution-endpoint=$engine --jwt-secret=/net/jwt.hex ;;
  teku)
    image=consensys/teku:26.10.3@sha256:4560398cf9a0b208a4a4a12ebc2051d820b67df51092a54154031dacc57f2ac6
    set -- --network=/net/config.yaml --genesis-state=/net/genesis.ssz --data-path=/tmp/data --p2p-enabled=true \
        --p2p-advertised-ip=$peer --p2p-port=9000 --p2p-discovery-site-local-addresses-enabled=true --p2p-peer-lower-bound=1 \
        --rest-api-enabled=true --rest-api-interface=0.0.0.0 --rest-api-port=5052 --rest-api-host-allowlist=* \
        --ee-endpoint=$engine --ee-jwt-secret-file=/net/jwt.hex --ignore-weak-subjectivity-period-enabled=true ;;
  nimbus)
    image=statusim/nimbus-eth2:multiarch-v26.10.2@sha256:53a51bf89ce48e0b615c90726e018ad96ed242001d7d8cbc8aa33ff25188845a
    set -- --non-interactive=true --network=/net --data-dir=/tmp/data --tcp-port=9000 --udp-port=9000 --nat=extip:$peer \
        --enr-auto-update=false --rest --rest-address=0.0.0.0 --rest-port=5052 --web3-url=$engine --jwt-secret=/net/jwt.hex ;;
  lodestar)
    image=chainsafe/lodestar:v1.51.0@sha256:88e897f8adf1ec9ea8dcaed8178db9170ea9d0dff82d218b707af9bc0a8a5974
    set -- beacon --paramsFile=/net/config.yaml --genesisStateFile=/net/genesis.ssz --dataDir=/tmp/data \
        --eth1.depositContractDeployBlock=0 --port=9000 --discoveryPort=9000 --discv5=true --nat=true --enr.ip=$peer \
        --enr.tcp=9000 --enr.udp=9000 --rest=true --rest.address=0.0.0.0 --rest.port=5052 --rest.namespace=* \
        --execution.urls=$engine --jwt-secret=/net/jwt.hex ;;
  grandine)
    image=sifrai/grandine:2.0.6@sha256:9373496ebecc42e67c754c18eb762d73f48539af978de83ef59709da3375cd57
    set -- --network=custom --configuration-directory=/net --data-dir=/tmp/data --http-address=0.0.0.0 --http-port=5052 \
        --libp2p-port=9000 --discovery-port=9000 --disable-enr-auto-update --enr-address=$peer --enr-tcp-port=9000 \
        --enr-udp-port=9000 --enable-private-discovery --eth1-rpc-urls=$engine --jwt-secret=/net/jwt.hex
    env="-e GRANDINE_LOG=eth2_libp2p=trace,p2p=debug,libp2p_swarm=debug,libp2p_noise=debug,libp2p_yamux=debug,multistream_select=debug" ;;
  *) echo "unknown client: $client" >&2; exit 2 ;;
esac

# The network directory, with the pinned spec, and a JWT secret for the client; and the check of
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
    /out/.venv/bin/python tests/app/trusted_setup.py $spec --check
    rm -rf /out/net
    PYTHONPATH=$spec/tests/core/pyspec:$spec:/src/build/deps/asm-ssz/tests/generator CONSENSUS_SPECS=$spec \
        /out/.venv/bin/python tests/app/network.py /out/net mainnet fulu "$1" 64
    od -An -tx1 -N32 /dev/urandom | tr -d " \n" > /out/net/jwt.hex
    grep -v -E "^($2):" /out/net/config.yaml > /out/net/prysm-config.yaml
    chmod -R a+rX /out/net
' sh "$genesis" "$prysm_unknown"

cleanup() {
    docker rm -f lantern-interop-peer lantern-interop-lantern >/dev/null 2>&1 || true
    docker network rm $net >/dev/null 2>&1 || true
}
cleanup
trap cleanup EXIT
docker network create --subnet 172.30.0.0/24 $net >/dev/null
docker run -d --name lantern-interop-peer --network $net --ip $peer $env -v "$work/net:/net:ro" $image "$@" >/dev/null
api() { docker run --rm --network $net lantern-build curl -s --max-time 3 "http://$1:5052$2" || true; }

# The client's record, then lantern with it as its boot node.
enr=
waited=0
while [ -z "$enr" ] && [ $waited -lt 120 ]; do
    sleep 3; waited=$((waited + 3))
    enr=$(api $peer /eth/v1/node/identity | sed -n 's/.*"enr" *: *"\(enr:[^"]*\)".*/\1/p')
done
[ -n "$enr" ] || { echo "FAIL $client gave no record"; docker logs lantern-interop-peer 2>&1 | tail -30; exit 1; }
docker run -d --name lantern-interop-lantern --network $net --ip 172.30.0.11 -v "$binary:/lantern:ro" -v "$work/net:/net:ro" \
    lantern-build /lantern --network-dir /net --port 9000 --http-port 5052 --enr-address 172.30.0.11 --boot-nodes "$enr" >/dev/null

# Each node shows the other as connected; then again two slots later.
connected() {
    id=$(api 172.30.0.11 /eth/v1/node/identity | sed -n 's/.*"peer_id":"\([^"]*\)".*/\1/p')
    api 172.30.0.11 /eth/v1/node/peer_count | grep -q '"connected":"[1-9]' || return 1
    [ -n "$id" ] || return 1
    api $peer /eth/v1/node/peers | docker run --rm -i lantern-build python3 -c "
import json, sys
peers = json.load(sys.stdin).get('data', [])
sys.exit(0 if any(p.get('peer_id') == '$id' and p.get('state') == 'connected' for p in peers) else 1)"
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
docker logs lantern-interop-lantern 2>&1 | grep -v "record enr" | head -40
echo "== $client peers"
api $peer /eth/v1/node/peers
echo
if [ $status -eq 0 ]; then
    echo "PASS lantern and $client are connected peers"
else
    echo "FAIL lantern and $client are not connected peers"
    echo "== $client: its first lines, then its lines on genesis, the fork digest and peers"
    docker logs lantern-interop-peer > "$work/peer.log" 2>&1 || true
    head -60 "$work/peer.log"
    grep -i -E "genesis|digest|fork|goodbye|disconnect|peer|dial|status" "$work/peer.log" | grep -v -i "subscribed to" | tail -60
    id=$(api 172.30.0.11 /eth/v1/node/identity | sed -n 's/.*"peer_id":"\([^"]*\)".*/\1/p')
    echo "== $client: its lines on lantern ($id) and its address"
    [ -n "$id" ] && grep -E "$id|172\.30\.0\.11" "$work/peer.log" | head -80 || true
fi
exit $status
