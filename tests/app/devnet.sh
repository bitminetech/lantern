#!/bin/sh
# A devnet of two geth and CLIENT nodes, the first with all the validators (ethpandaops/
# ethereum-package through tests/kurtosis/; with one lighthouse node it sets --target-peers=0), and the
# lantern binary following it. Passes when lantern's head is at slot 8 or
# later, is a block of the client's chain, and is within 2 slots of the client's head, at two
# checks a slot apart.
# Usage: tests/app/devnet.sh CLIENT [IMAGE] [SECONDS]
#   CLIENT: lighthouse, prysm, teku, nimbus, lodestar or grandine, at its image of tests/app/clients.sh.
#   IMAGE: the lantern image of platform/docker/Dockerfile (default lantern:local).
#   SECONDS: the longest wait for lantern to follow, after the devnet starts (default 900).
# KURTOSIS: the kurtosis CLI (default kurtosis). KEEP=1 keeps the enclave. CL_LOG_LEVEL: the client's
# log level (default info). LANTERN_MAX_CPU: lantern's CPU limit in millicores (default no limit).
# LANTERN_DELAY: seconds before lantern starts (default 0).
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
client=$1
image=${2:-lantern:local}
secs=${3:-900}
kurtosis=${KURTOSIS:-kurtosis}
enclave=lantern-devnet
. "$root/tests/app/clients.sh"
[ -n "$(client_image "$client")" ] || { echo "unknown client: $client" >&2; exit 2; }
work=$(mktemp -d)
cat > "$work/args.yaml" <<EOF
participants:
  - el_type: geth
    el_image: $geth_image
    cl_type: $client
    cl_image: $(client_image "$client")
    vc_image: $(validator_image "$client")
    cl_log_level: ${CL_LOG_LEVEL:-info}
  - el_type: geth
    el_image: $geth_image
    cl_type: $client
    cl_image: $(client_image "$client")
    vc_image: $(validator_image "$client")
    cl_log_level: ${CL_LOG_LEVEL:-info}
    validator_count: 0
additional_services: []
lantern_image: $image
lantern_max_cpu: ${LANTERN_MAX_CPU:-0}
lantern_delay: ${LANTERN_DELAY:-0}
EOF

cleanup() {
    echo "== lantern"
    $kurtosis service logs -a $enclave lantern > "$work/lantern.log" 2>&1 || true
    grep -v "record enr" "$work/lantern.log" | grep -v "lantern: slot" | head -40 || true
    grep "lantern: slot" "$work/lantern.log" | tail -10 || true
    [ "${KEEP:-0}" = 1 ] || $kurtosis enclave rm -f $enclave >/dev/null 2>&1 || true
    rm -rf "$work"
}
$kurtosis enclave rm -f $enclave >/dev/null 2>&1 || true
trap cleanup EXIT
if ! $kurtosis run --enclave $enclave "$root/tests/kurtosis" --args-file "$work/args.yaml" > "$work/run.log" 2>&1; then
    echo "FAIL the devnet did not start"
    tail -60 "$work/run.log"
    exit 1
fi
url() { echo "http://$($kurtosis port print $enclave "$1" http | sed 's#^[a-z]*://##')"; }
peer_service=$($kurtosis enclave inspect $enclave | grep -o "cl-1-$client-[a-z]*" | head -1)
lantern=$(url lantern)
peer=$(url "$peer_service")
echo "lantern $lantern, $peer_service $peer"

# The slot and root of a node's head, or nothing.
node_head() {
    curl -s --max-time 3 "$1/eth/v1/beacon/headers/head" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)["data"]
    print(d["header"]["message"]["slot"], d["root"])
except Exception:
    pass'
}
follows() {
    set -- $(node_head "$lantern") $(node_head "$peer")
    [ $# -eq 4 ] || return 1
    echo "lantern slot $1 $2, $client slot $3"
    [ "$1" -ge 8 ] && [ $(($3 - $1)) -le 2 ] || return 1
    [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$peer/eth/v1/beacon/headers/$2")" = 200 ]
}
status=1
waited=0
while [ $waited -lt "$secs" ]; do
    sleep 12; waited=$((waited + 12))
    if follows; then
        sleep 12
        follows && { status=0; break; }
    fi
done
if [ $status -eq 0 ]; then echo "PASS lantern follows the chain of $client"; else echo "FAIL lantern does not follow the chain of $client"; fi
exit $status
