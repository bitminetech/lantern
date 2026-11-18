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
# LANTERN_DELAY: seconds before lantern starts (default 0). RESTART=1: 6-second slots, lantern with
# --data-dir /data; after it follows, once its log shows finalized epoch 2 or later, lantern stops and
# starts again, and must log "restart at slot" and follow again. CHECKPOINT=1: 6-second slots, lantern
# starts from the client's finalized block and its post-state, and must log "checkpoint at slot".
# FORK=1: 6-second slots, electra at genesis and fulu at epoch 1; lantern's head must reach the
# fork: slot 40 or later.
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
if [ "${RESTART:-0}" = 1 ] || [ "${CHECKPOINT:-0}" = 1 ] || [ "${FORK:-0}" = 1 ]; then
    printf 'network_params:\n  seconds_per_slot: 6\n' >> "$work/args.yaml"
fi
min_slot=8
if [ "${FORK:-0}" = 1 ]; then
    printf '  electra_fork_epoch: 0\n  fulu_fork_epoch: 1\n' >> "$work/args.yaml"
    min_slot=40
fi
if [ "${RESTART:-0}" = 1 ]; then printf 'lantern_data_dir: /data\n' >> "$work/args.yaml"; fi
if [ "${CHECKPOINT:-0}" = 1 ]; then printf 'lantern_checkpoint: true\n' >> "$work/args.yaml"; fi

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
    [ "$1" -ge "$min_slot" ] && [ $(($3 - $1)) -le 2 ] || return 1
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
if [ $status -eq 0 ] && [ "${CHECKPOINT:-0}" = 1 ]; then
    if $kurtosis service logs -a $enclave lantern 2>/dev/null | grep "checkpoint at slot"; then
        echo "PASS lantern starts from the checkpoint"
    else
        echo "FAIL lantern does not start from the checkpoint"; status=1
    fi
fi
[ $status -eq 0 ] && [ "${RESTART:-0}" = 1 ] || exit $status

# RESTART=1: once lantern has written its history at a finalized epoch, it stops and starts again.
log() { $kurtosis service logs -a $enclave lantern 2>/dev/null; }
finalized() { log | grep -o "finalized epoch [0-9]*" | tail -1 | grep -o "[0-9]*$" || true; }
status=1
waited=0
while [ $waited -lt "$secs" ]; do
    sleep 12; waited=$((waited + 12))
    f=$(finalized)
    echo "lantern finalized epoch ${f:-none}"
    [ -n "$f" ] && [ "$f" -ge 2 ] && { status=0; break; }
done
[ $status -eq 0 ] || { echo "FAIL lantern does not reach finalized epoch 2"; exit 1; }
sleep 12
$kurtosis service stop $enclave lantern
$kurtosis service start $enclave lantern
lantern=$(url lantern)
status=1
waited=0
while [ $waited -lt "$secs" ]; do
    sleep 12; waited=$((waited + 12))
    log | grep -q "restart at slot" || continue
    if follows; then
        sleep 12
        follows && { status=0; break; }
    fi
done
log | grep "restart at slot\|cannot write\|status" | head -10 || true
if [ $status -eq 0 ]; then echo "PASS lantern restarts from its history and follows again"; else echo "FAIL lantern does not restart from its history and follow"; fi
exit $status
