"""The same Beacon API reads of lantern and of another client of the same chain, compared.

Usage: python3 tests/app/differential.py LANTERN_URL PEER_URL CLIENT

The block: the peer's finalized block (getBlockHeader of finalized), root R, its state root S, and
the finalized epoch E. The duties: of the epoch N of the peer's head slot - 2, N + 1 and E. The
rewards: of the block B of the peer's chain at or below its head slot - 4, and of the attestations
of epoch N - 2; both nodes keep their states. Each read names R, S, E, N or B, so both nodes answer
of the same chain. The check of a read:
- the peer answers 200, or the read is skipped;
- lantern answers 200;
- JSON: the same `data`, `version` and `dependent_root`; `execution_optimistic` and `finalized`
  depend on each node's view and are not compared. Hex strings compare with no regard to letter
  case (an address may be in EIP-55 form), the `validator_sync_committee_indices` of a duty as a
  set, and the forks of getForkSchedule at FAR_FUTURE_EPOCH not at all (forks a node knows of
  before they are scheduled).
- getSpec: the same value of each key both nodes give, numbers as numbers (`2` and `0x02`), but
  for the keys of QUIRKS.
- SSZ: the same bytes.
Prints a PASS, FAIL or SKIP line for each read, and exits 1 when one fails.
"""

import json
import sys
import urllib.error
import urllib.request

lantern, peer, client = sys.argv[1].rstrip("/"), sys.argv[2].rstrip("/"), sys.argv[3]

# getSpec keys whose value a client gives otherwise than the network's config.yaml: lodestar gives
# SECONDS_PER_SLOT 12 on a network of 6-second slots (its SLOT_DURATION_MS is the network's).
QUIRKS = {"lodestar": {"SECONDS_PER_SLOT"}}
FAR_FUTURE_EPOCH = "18446744073709551615"


def normal(value, key=None):
    """value with hex strings in lower case and a duty's sync committee indices sorted."""
    if isinstance(value, dict):
        return {k: normal(v, k) for k, v in value.items()}
    if isinstance(value, list):
        items = [normal(v) for v in value]
        if key == "validator_sync_committee_indices":
            items.sort(key=int)
        return items
    if isinstance(value, str) and value.startswith("0x"):
        return value.lower()
    return value


def number(value):
    """value as an int when it is a decimal or 0x number of 8 bytes or fewer, else value in lower case."""
    try:
        return int(value, 16) if value.lower().startswith("0x") and len(value) <= 18 else int(value)
    except (ValueError, AttributeError):
        return value.lower() if isinstance(value, str) else value


def fetch(base, path, body=None, ssz=False):
    headers = {"Accept": "application/octet-stream" if ssz else "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(base + path, data=data, headers=headers, method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except Exception as error:
        return 0, str(error).encode()


head = json.loads(fetch(peer, "/eth/v1/beacon/headers/finalized")[1])["data"]
R = head["root"]
S = head["header"]["message"]["state_root"]
E = int(json.loads(fetch(peer, "/eth/v1/beacon/states/finalized/finality_checkpoints")[1])["data"]["finalized"]["epoch"])
validators = [str(i) for i in range(len(json.loads(fetch(peer, "/eth/v1/beacon/states/%s/validators" % S)[1])["data"]))]
spe = int(json.loads(fetch(peer, "/eth/v1/config/spec")[1])["data"]["SLOTS_PER_EPOCH"])
head_slot = int(json.loads(fetch(peer, "/eth/v1/beacon/headers/head")[1])["data"]["header"]["message"]["slot"])
N = max(head_slot - 2, 0) // spe
B = None
for slot in range(max(head_slot - 4, 0), max(head_slot - 36, -1), -1):
    status, body = fetch(peer, "/eth/v1/beacon/headers/%d" % slot)
    if status == 200:
        B = json.loads(body)["data"]["root"]
        break
print("finalized block %s, state %s, epoch %d, %d validators; duties of epoch %d; rewards of block %s and epoch %d"
      % (R, S, E, len(validators), N, B, N - 2))

READS = [
    ("getGenesis", "/eth/v1/beacon/genesis", None, False),
    ("getForkSchedule", "/eth/v1/config/fork_schedule", None, False),
    ("getDepositContract", "/eth/v1/config/deposit_contract", None, False),
    ("getSpec", "/eth/v1/config/spec", None, False),
    ("getBlockHeader", "/eth/v1/beacon/headers/" + R, None, False),
    ("getBlockV2", "/eth/v2/beacon/blocks/" + R, None, False),
    ("getBlockV2 SSZ", "/eth/v2/beacon/blocks/" + R, None, True),
    ("getBlockRoot", "/eth/v1/beacon/blocks/%s/root" % R, None, False),
    ("getBlockAttestationsV2", "/eth/v2/beacon/blocks/%s/attestations" % R, None, False),
    ("getBlobs", "/eth/v1/beacon/blobs/" + R, None, False),
    ("getStateRoot", "/eth/v1/beacon/states/%s/root" % S, None, False),
    ("getStateFork", "/eth/v1/beacon/states/%s/fork" % S, None, False),
    ("getStateFinalityCheckpoints", "/eth/v1/beacon/states/%s/finality_checkpoints" % S, None, False),
    ("getStateValidators", "/eth/v1/beacon/states/%s/validators" % S, None, False),
    ("postStateValidators", "/eth/v1/beacon/states/%s/validators" % S, {"ids": validators[:3]}, False),
    ("getStateValidatorBalances", "/eth/v1/beacon/states/%s/validator_balances" % S, None, False),
    ("getEpochCommittees", "/eth/v1/beacon/states/%s/committees" % S, None, False),
    ("getEpochSyncCommittees", "/eth/v1/beacon/states/%s/sync_committees" % S, None, False),
    ("getStateRandao", "/eth/v1/beacon/states/%s/randao" % S, None, False),
    ("getPendingDeposits", "/eth/v1/beacon/states/%s/pending_deposits" % S, None, False),
    ("getPendingPartialWithdrawals", "/eth/v1/beacon/states/%s/pending_partial_withdrawals" % S, None, False),
    ("getPendingConsolidations", "/eth/v1/beacon/states/%s/pending_consolidations" % S, None, False),
    ("getStateV2 SSZ", "/eth/v2/debug/beacon/states/" + S, None, True),
    ("getBlockRewards", "/eth/v1/beacon/rewards/blocks/%s" % B, None, False),
    ("getSyncCommitteeRewards", "/eth/v1/beacon/rewards/sync_committee/%s" % B, [], False),
    ("getAttestationsRewards", "/eth/v1/beacon/rewards/attestations/%d" % max(N - 2, 0), [], False),
    ("getProposerDuties", "/eth/v1/validator/duties/proposer/%d" % N, None, False),
    ("getProposerDuties of the next epoch", "/eth/v1/validator/duties/proposer/%d" % (N + 1), None, False),
    ("getAttesterDuties", "/eth/v1/validator/duties/attester/%d" % N, validators, False),
    ("getAttesterDuties of the next epoch", "/eth/v1/validator/duties/attester/%d" % (N + 1), validators, False),
    ("getSyncCommitteeDuties", "/eth/v1/validator/duties/sync/%d" % N, validators, False),
    ("getProposerDuties of the finalized epoch", "/eth/v1/validator/duties/proposer/%d" % E, None, False),
    ("getAttesterDuties of the finalized epoch", "/eth/v1/validator/duties/attester/%d" % E, validators, False),
    ("getLightClientBootstrap", "/eth/v1/beacon/light_client/bootstrap/" + R, None, False),
]

failed = 0
for name, path, body, ssz in READS:
    peer_status, peer_body = fetch(peer, path, body, ssz)
    if peer_status != 200:
        print("SKIP %s: the peer answers %d" % (name, peer_status))
        continue
    status, got = fetch(lantern, path, body, ssz)
    why = None
    if status != 200:
        why = "lantern answers %d: %s" % (status, got[:200].decode(errors="replace"))
    elif ssz:
        if got != peer_body:
            why = "the SSZ bytes differ (%d and %d bytes)" % (len(got), len(peer_body))
    else:
        mine, theirs = json.loads(got), json.loads(peer_body)
        if name == "getForkSchedule":
            for answer in (mine, theirs):
                answer["data"] = [f for f in answer["data"] if f.get("epoch") != FAR_FUTURE_EPOCH]
        if name == "getSpec":
            keys = sorted(set(mine["data"]) & set(theirs["data"]) - QUIRKS.get(client, set()))
            diff = [k for k in keys if number(mine["data"][k]) != number(theirs["data"][k])]
            if diff:
                why = "values differ: " + ", ".join("%s %s and %s" % (k, mine["data"][k], theirs["data"][k]) for k in diff[:5])
        elif normal(mine.get("dependent_root")) != normal(theirs.get("dependent_root")):
            why = "dependent_root %s and %s" % (mine.get("dependent_root"), theirs.get("dependent_root"))
        elif mine.get("version") != theirs.get("version"):
            why = "version %s and %s" % (mine.get("version"), theirs.get("version"))
        elif normal(mine.get("data")) != normal(theirs.get("data")):
            a, b = json.dumps(normal(mine.get("data")), sort_keys=True), json.dumps(normal(theirs.get("data")), sort_keys=True)
            at = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
            why = "data differs at character %d: %s and %s" % (at, a[max(0, at - 60):at + 60], b[max(0, at - 60):at + 60])
    if why:
        failed += 1
        print("FAIL %s: %s" % (name, why))
    else:
        print("PASS %s" % name)
sys.exit(1 if failed else 0)
