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
# log level (default info). LOG_DIR: a folder for the full logs of lantern and the other services. LANTERN_MAX_CPU: lantern's CPU limit in millicores (default no limit).
# LANTERN_DELAY: seconds before lantern starts (default 0). RESTART=1: 6-second slots, lantern with
# --data-dir /data --archive; after it follows, once its log shows finalized epoch 2 or later, lantern stops and
# starts again, and must log "restart at slot" and follow again; DOWNTIME: the seconds it stays stopped
# (default 0). CHECKPOINT=1: 6-second slots, lantern
# with --data-dir /data --archive (the backfill keeps its blocks there) starts from the client's finalized block
# and its post-state, must log "checkpoint at slot", and its
# "earliest slot" must fall below the checkpoint's slot (the backfill).
# FORK=1: 6-second slots, electra at genesis and fulu at epoch 1 (no BPO fork); lantern's head must
# reach the fork: slot 40 or later. ASSERTOOR=1: 6-second slots, SHARD_COMMITTEE_PERIOD 1 (exits from
# epoch 1), 130 validators in genesis (two that no validator client runs), and Assertoor with lantern
# as its one consensus endpoint (tests/kurtosis/main.star); after
# lantern follows, Assertoor's test "lantern" must end in success within SECONDS, and each of its tasks
# is printed. VC=1: 6-second slots, 128 validators in genesis, the first client runs keys 0 to 63, and
# the client's validator client runs keys 64 to 127 with lantern as its one beacon node, lantern on the
# second client's geth (tests/kurtosis/main.star); after lantern follows, the client's finalized epoch must
# reach 3 within SECONDS (the stake of keys 0 to 63 alone is half), and 4 or more of the client's
# block headers must have a proposer index of 64 or more (blocks lantern produced). CLIENT: lighthouse,
# prysm, teku, nimbus or lodestar. DIFF=1: 6-second slots; after lantern follows, once the client's
# finalized epoch is 2 or more and lantern's has reached it, tests/app/differential.py compares their
# reads of the client's finalized block. SYNC=1: 6-second slots, lantern with --supernode; 600 s after
# it starts, a geth and a lighthouse beacon node whose one boot node is lantern's multiaddr
# (tests/kurtosis/main.star); that lighthouse must sync from genesis to within 2 slots of the client's
# head, on a block of the client's chain, within SECONDS, with lantern its one peer at every check.
# With nimbus the 6-second slots are 12 seconds (ethereum-package's floor for it on the mainnet
# preset). With VC=1 the second client, which runs no validators, is a supernode.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
client=$1
image=${2:-lantern:local}
secs=${3:-900}
kurtosis=${KURTOSIS:-kurtosis}
enclave=lantern-devnet
. "$root/tests/app/clients.sh"
[ -n "$(client_image "$client")" ] || { echo "unknown client: $client" >&2; exit 2; }
vc=${VC:-0}
if [ "$vc" = 1 ]; then
    case $client in lighthouse|prysm|teku|nimbus|lodestar) ;; *) echo "VC=1: no validator client for $client" >&2; exit 2 ;; esac
fi
# VC=1: the first client runs keys 0 to 63; the second, with none, is the network's supernode (with
# fulu at genesis ethereum-package needs one, or a node of 128 validators).
first_count=
second_supernode=
[ "$vc" = 1 ] && first_count="    validator_count: 64" && second_supernode="    supernode: true"
# Short slots: 6 seconds, but 12 for nimbus (ethereum-package's floor for it on the mainnet preset).
slot_secs=6
[ "$client" = nimbus ] && slot_secs=12
work=$(mktemp -d)
cat > "$work/args.yaml" <<EOF
participants:
  - el_type: geth
    el_image: $geth_image
    cl_type: $client
    cl_image: $(client_image "$client")
    vc_image: $(validator_image "$client")
    cl_log_level: ${CL_LOG_LEVEL:-info}
$first_count
  - el_type: geth
    el_image: $geth_image
    cl_type: $client
    cl_image: $(client_image "$client")
    vc_image: $(validator_image "$client")
    cl_log_level: ${CL_LOG_LEVEL:-info}
    validator_count: 0
$second_supernode
additional_services: []
lantern_image: $image
lantern_max_cpu: ${LANTERN_MAX_CPU:-0}
lantern_delay: ${LANTERN_DELAY:-0}
EOF
if [ "${RESTART:-0}" = 1 ] || [ "${CHECKPOINT:-0}" = 1 ] || [ "${FORK:-0}" = 1 ] || [ "${ASSERTOOR:-0}" = 1 ] || [ "$vc" = 1 ] || [ "${DIFF:-0}" = 1 ] || [ "${SYNC:-0}" = 1 ]; then
    printf 'network_params:\n  seconds_per_slot: %s\n' "$slot_secs" >> "$work/args.yaml"
fi
# Assertoor: exits at once (shard_committee_period 1), and two validators of the mnemonic past the
# first client's 128 that no validator client runs (preregistered_validator_count 130), whose
# attestations only Assertoor signs, through lantern's submitPoolAttestationsV2.
if [ "${ASSERTOOR:-0}" = 1 ]; then printf '  shard_committee_period: 1\n  preregistered_validator_count: 130\n' >> "$work/args.yaml"; fi
# VC=1: keys 64 to 127, which only lantern's validator client runs.
if [ "$vc" = 1 ]; then printf '  preregistered_validator_count: 128\n' >> "$work/args.yaml"; fi
min_slot=8
if [ "${FORK:-0}" = 1 ]; then
    printf '  electra_fork_epoch: 0\n  fulu_fork_epoch: 1\n' >> "$work/args.yaml"
    for n in 1 2 3 4 5; do printf '  bpo_%s_epoch: 18446744073709551615\n' $n >> "$work/args.yaml"; done
    min_slot=40
fi
if [ "${RESTART:-0}" = 1 ] || [ "${CHECKPOINT:-0}" = 1 ]; then printf 'lantern_data_dir: /data\n' >> "$work/args.yaml"; fi
if [ "${CHECKPOINT:-0}" = 1 ]; then printf 'lantern_checkpoint: true\n' >> "$work/args.yaml"; fi
if [ "${ASSERTOOR:-0}" = 1 ]; then printf 'lantern_assertoor: true\n' >> "$work/args.yaml"; fi
if [ "${SYNC:-0}" = 1 ]; then
    printf 'lantern_sync: true\nlantern_sync_el_image: %s\nlantern_sync_cl_image: %s\n' "$geth_image" "$(client_image lighthouse)" >> "$work/args.yaml"
fi
if [ "$vc" = 1 ]; then printf 'lantern_vc: %s\nlantern_vc_image: %s\n' "$client" "$(validator_image "$client")" >> "$work/args.yaml"; fi

cleanup() {
    echo "== lantern"
    $kurtosis service logs -a $enclave lantern > "$work/lantern.log" 2>&1 || true
    grep -v "record enr" "$work/lantern.log" | grep -v " INFO  slot " | head -40 || true
    echo "== lantern, its last lines but the slot and block lines"
    grep -v "record enr" "$work/lantern.log" | grep -v " INFO  slot \| INFO  block " | tail -30 || true
    grep " INFO  slot " "$work/lantern.log" | tail -10 || true
    grep -E " (WARN|ERROR) " "$work/lantern.log" | tail -20 || true
    if [ "${ASSERTOOR:-0}" = 1 ]; then
        echo "== assertoor"
        $kurtosis service logs -a $enclave assertoor 2>&1 | grep -i "error\|fail\|warn" | tail -40 || true
    fi
    if [ "${SYNC:-0}" = 1 ]; then
        echo "== sync-cl"
        $kurtosis service logs -a $enclave sync-cl 2>&1 | grep -i "error\|crit\|warn" | tail -30 || true
        $kurtosis service logs -a $enclave sync-cl 2>&1 | tail -15 || true
    fi
    if [ "$vc" = 1 ]; then
        echo "== lantern-vc"
        $kurtosis service logs -a $enclave lantern-vc 2>&1 | grep -i "error\|fail\|warn\|crit" | tail -40 || true
        $kurtosis service logs -a $enclave lantern-vc 2>&1 | tail -15 || true
    fi
    if [ -n "${LOG_DIR:-}" ]; then
        mkdir -p "$LOG_DIR"
        cp "$work/lantern.log" "$work/args.yaml" "$LOG_DIR/" 2>/dev/null || true
        for service in ${peer_service:-} lantern-vc sync-cl assertoor; do
            $kurtosis service logs -a $enclave "$service" > "$LOG_DIR/$service.log" 2>&1 || rm -f "$LOG_DIR/$service.log"
        done
    fi
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
if [ $status -eq 0 ] && [ "${CHECKPOINT:-0}" = 1 ]; then
    # the backfill: lantern's earliest slot falls below the checkpoint's slot as lighthouse's blocks join its history
    cp=$($kurtosis service logs -a $enclave lantern 2>/dev/null | grep -o "checkpoint at slot [0-9]*" | head -1 | grep -o "[0-9]*$")
    status=1
    waited=0
    while [ $waited -lt "$secs" ]; do
        e=$($kurtosis service logs -a $enclave lantern 2>/dev/null | grep -o "earliest slot [0-9]*" | tail -1 | grep -o "[0-9]*$" || true)
        echo "lantern earliest slot ${e:-none}, checkpoint slot $cp"
        [ -n "$e" ] && [ "$e" -lt "$cp" ] && { status=0; break; }
        sleep 12; waited=$((waited + 12))
    done
    if [ $status -eq 0 ]; then echo "PASS lantern backfills below the checkpoint"; else echo "FAIL lantern does not backfill below the checkpoint"; fi
fi
if [ $status -eq 0 ] && [ "${ASSERTOOR:-0}" = 1 ]; then
    # Assertoor's test "lantern": its last run, until it ends; then each task's result
    assertoor=$(url assertoor)
    status=1
    waited=0
    run=
    while [ $waited -lt "$secs" ]; do
        got=$(curl -s --max-time 5 "$assertoor/api/v1/test_runs" | python3 -c '
import json, sys
try:
    runs = [r for r in json.load(sys.stdin)["data"] if r["test_id"] == "lantern"]
    print(runs[-1]["run_id"], runs[-1]["status"])
except Exception:
    pass')
        echo "assertoor test lantern: ${got:-no run yet}"
        run=${got%% *}
        case "$got" in
          *" success") status=0; break ;;
          *" failure"|*" aborted"|*" skipped") break ;;
        esac
        sleep 30; waited=$((waited + 30))
    done
    if [ -n "$run" ]; then
        curl -s --max-time 10 "$assertoor/api/v1/test_run/$run" | python3 -c '
import json, sys
try:
    for t in json.load(sys.stdin)["data"]["tasks"]:
        print("  task", t["index"], t["name"], "-", t["title"] + ":", t["status"], t["result"], t.get("result_error", ""))
except Exception as e:
    print("  no task list:", e)'
    fi
    if [ $status -eq 0 ]; then echo "PASS Assertoor's checks over lantern"; else echo "FAIL Assertoor's checks over lantern"; fi
fi
# The finalized epoch of the Beacon API at $1, or nothing.
finalized_epoch() {
    curl -s --max-time 5 "$1/eth/v1/beacon/states/head/finality_checkpoints" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["data"]["finalized"]["epoch"])
except Exception:
    pass'
}
if [ $status -eq 0 ] && [ "${DIFF:-0}" = 1 ]; then
    status=1
    waited=0
    while [ $waited -lt "$secs" ]; do
        p=$(finalized_epoch "$peer"); l=$(finalized_epoch "$lantern")
        echo "$client finalized epoch ${p:-none}, lantern ${l:-none}"
        [ -n "$p" ] && [ -n "$l" ] && [ "$p" -ge 2 ] && [ "$l" -ge "$p" ] && { status=0; break; }
        sleep 30; waited=$((waited + 30))
    done
    if [ $status -eq 0 ]; then
        python3 "$root/tests/app/differential.py" "$lantern" "$peer" "$client" || status=1
        if [ $status -eq 0 ]; then echo "PASS lantern's reads agree with $client's"; else echo "FAIL lantern's reads differ from $client's"; fi
    else
        echo "FAIL no finalized epoch 2 on both nodes"
    fi
fi
if [ $status -eq 0 ] && [ "${SYNC:-0}" = 1 ]; then
    # the lighthouse that syncs from lantern alone: its peers, its head against the client's
    lantern_id=$(curl -s --max-time 5 "$lantern/eth/v1/node/identity" | python3 -c 'import json, sys; print(json.load(sys.stdin)["data"]["peer_id"])')
    status=1
    waited=0
    while [ $waited -lt "$secs" ]; do
        sync=$(url sync-cl 2>/dev/null || true)
        if [ -n "$sync" ]; then
            others=$(curl -s --max-time 5 "$sync/eth/v1/node/peers?state=connected" | python3 -c '
import json, sys
try:
    print(" ".join(p["peer_id"] for p in json.load(sys.stdin)["data"] if p["peer_id"] != sys.argv[1]))
except Exception:
    pass' "$lantern_id")
            [ -z "$others" ] || { echo "FAIL the syncing lighthouse has peers other than lantern: $others"; break; }
            set -- $(node_head "$sync") $(node_head "$peer")
            if [ $# -eq 4 ]; then
                echo "syncing lighthouse slot $1, $client slot $3"
                if [ $(($3 - $1)) -le 2 ] && [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$peer/eth/v1/beacon/headers/$2")" = 200 ]; then
                    status=0; break
                fi
            fi
        fi
        sleep 30; waited=$((waited + 30))
    done
    if [ $status -eq 0 ]; then echo "PASS lighthouse syncs from lantern alone"; else echo "FAIL lighthouse does not sync from lantern alone"; fi
fi
if [ $status -eq 0 ] && [ "$vc" = 1 ]; then
    # finality, which needs the attestations of lantern's validators; then the blocks they proposed
    status=1
    waited=0
    while [ $waited -lt "$secs" ]; do
        f=$(finalized_epoch "$peer")
        echo "$client finalized epoch ${f:-none}"
        [ -n "$f" ] && [ "$f" -ge 3 ] && { status=0; break; }
        sleep 30; waited=$((waited + 30))
    done
    if [ $status -eq 0 ]; then echo "PASS finality with the validators of lantern's validator client"; else echo "FAIL no finality with the validators of lantern's validator client"; fi
    if [ $status -eq 0 ]; then
        n=$(python3 - "$peer" <<'PY' || true
import json, sys, urllib.request
peer = sys.argv[1]
head = int(json.load(urllib.request.urlopen(peer + "/eth/v1/beacon/headers/head", timeout=10))["data"]["header"]["message"]["slot"])
count = 0
for slot in range(1, head + 1):
    try:
        d = json.load(urllib.request.urlopen(peer + "/eth/v1/beacon/headers/" + str(slot), timeout=10))["data"]
    except Exception:
        continue
    if int(d["header"]["message"]["proposer_index"]) >= 64:
        count += 1
print(count)
PY
)
        echo "blocks of lantern's validators: $n"
        [ "${n:-0}" -ge 4 ] || status=1
        if [ $status -eq 0 ]; then echo "PASS blocks produced through lantern"; else echo "FAIL too few blocks produced through lantern"; fi
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
sleep "${DOWNTIME:-0}"
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
if [ $status -eq 0 ]; then echo "PASS lantern restarts from its history after ${DOWNTIME:-0} s down and follows again"; else echo "FAIL lantern does not restart from its history and follow"; fi
exit $status
