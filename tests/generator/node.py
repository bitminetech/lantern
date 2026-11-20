"""Cases of lantern's node core over libp2p (docs/reference/node.md), made with the pinned spec.

The spec functions run in the fork's spec module that run.sh generates from consensus-specs
v1.7.0-beta.4 (aa16bb4). The answers follow p2p-interface.md of phase0, altair and fulu, the
Req/Resp domain: Status, Ping and MetaData of a node at its anchor, from get_forkchoice_store.

cases(fork, preset) yields (handler, name, parts). The parts of a "p2p" case:
- "anchor_state", "anchor_block": the SSZ bytes of the node's anchor;
- "status": the SSZ bytes of the Status the node answers (StatusV2 in fulu);
- "metadata": the SSZ bytes of the MetaData the node answers, of the fork's version;
- "status_version", "metadata_version": the protocol versions of those requests.

The config of every case: each fork up to the case's fork at epoch 0, each later fork at
2^64 - 1, as the runner gives the node.

blob_cases(fork, preset, cases) yields the "blobs" cases of deneb and electra from the spec's
fork_choice on_block cases: for each case whose block steps have blobs, one of the same name
whose part of each such block file is the list of the SSZ bytes of get_blob_sidecars (deneb
validator.md) of the block and the step's blobs and proofs. A step with fewer proofs or
commitments than blobs gives the sidecars of the indices that have all three.
"""

import os
import pathlib

from p2p import FORKS, U64, module, run
from reqresp import message_types

ANCHOR_EPOCH = 2


def schedule(fork):
    config = {}
    for i, name in enumerate(FORKS[1:], start=1):
        config[f"{name.upper()}_FORK_EPOCH"] = 0 if i <= FORKS.index(fork) else U64
    return config


# Validators of each status but active_ongoing at ANCHOR_EPOCH, for the API cases: activation_eligibility_epoch,
# activation_epoch, exit_epoch, withdrawable_epoch, slashed, effective balance in increments (None: FAR_FUTURE_EPOCH).
STATUS_VALIDATORS = [
    (None, None, None, None, False, 1),   # pending_initialized
    (1, None, None, None, False, 32),     # pending_queued
    (0, 0, 5, 300, False, 32),            # active_exiting
    (0, 0, 5, 300, True, 31),             # active_slashed
    (0, 0, 1, 300, False, 32),            # exited_unslashed
    (0, 0, 1, 300, True, 30),             # exited_slashed
    (0, 0, 0, 1, False, 32),              # withdrawal_possible
    (0, 0, 0, 1, False, 0),               # withdrawal_done
]


def anchor(spec, fork, statuses=False, epoch=ANCHOR_EPOCH):
    """A state at the first slot of the epoch (ANCHOR_EPOCH) with 8 validators (and those of
    STATUS_VALIDATORS after them with statuses), and its block."""
    slot = spec.Slot(epoch * spec.SLOTS_PER_EPOCH)
    version = spec.config.GENESIS_FORK_VERSION if fork == "phase0" else getattr(spec.config, f"{fork.upper()}_FORK_VERSION")
    state = spec.BeaconState(
        genesis_time=1_600_000_000,
        genesis_validators_root=spec.Root(bytes(range(32, 64))),
        slot=slot,
        fork=spec.Fork(previous_version=version, current_version=version, epoch=0),
        latest_block_header=spec.BeaconBlockHeader(slot=slot, body_root=spec.hash_tree_root(spec.BeaconBlockBody())),
    )
    for i in range(8):
        state.validators.append(
            spec.Validator(
                pubkey=spec.BLSPubkey(bytes([i + 1]) * 48),
                withdrawal_credentials=spec.Bytes32(bytes([i]) * 32),
                effective_balance=spec.MAX_EFFECTIVE_BALANCE,
                activation_eligibility_epoch=0,
                activation_epoch=0,
                exit_epoch=spec.FAR_FUTURE_EPOCH,
                withdrawable_epoch=spec.FAR_FUTURE_EPOCH,
            )
        )
        state.balances.append(spec.MAX_EFFECTIVE_BALANCE)
        if fork != "phase0":
            state.previous_epoch_participation.append(0)
            state.current_epoch_participation.append(0)
            state.inactivity_scores.append(0)
    far = spec.FAR_FUTURE_EPOCH
    for k, (eligible, active, exit_, withdrawable, slashed, inc) in enumerate(STATUS_VALIDATORS if statuses else []):
        i = 8 + k
        state.validators.append(
            spec.Validator(
                pubkey=spec.BLSPubkey(bytes([i + 1]) * 48),
                withdrawal_credentials=spec.Bytes32(bytes([i]) * 32),
                effective_balance=inc * spec.EFFECTIVE_BALANCE_INCREMENT,
                slashed=slashed,
                activation_eligibility_epoch=far if eligible is None else eligible,
                activation_epoch=far if active is None else active,
                exit_epoch=far if exit_ in (None,) else exit_,
                withdrawable_epoch=far if withdrawable is None else withdrawable,
            )
        )
        state.balances.append(inc * spec.EFFECTIVE_BALANCE_INCREMENT + 1000 * i)
        if fork != "phase0":
            state.previous_epoch_participation.append(0)
            state.current_epoch_participation.append(0)
            state.inactivity_scores.append(0)
    if fork == "fulu":  # as at genesis and at the fork (fulu fork.md)
        state.proposer_lookahead = spec.initialize_proposer_lookahead(state)
    block = spec.BeaconBlock(slot=slot, state_root=spec.hash_tree_root(state))
    return state, block


def answers(spec, fork, state, block):
    store = spec.get_forkchoice_store(state, block)
    epoch = spec.get_current_store_epoch(store)
    digest = spec.compute_fork_digest(state.genesis_validators_root, epoch)
    head = spec.get_head(store)
    head = getattr(head, "root", head)  # a ForkChoiceNode from altair on, a Root before
    fields = dict(
        fork_digest=digest,
        finalized_root=store.finalized_checkpoint.root,
        finalized_epoch=store.finalized_checkpoint.epoch,
        head_root=head,
        head_slot=store.blocks[head].slot,
    )
    t = message_types(spec, fork)
    if fork == "fulu":
        status = t["StatusV2"](earliest_available_slot=block.slot, **fields)
        metadata = t["MetaDataV3"](seq_number=0, custody_group_count=spec.config.CUSTODY_REQUIREMENT)
    else:
        status = t["Status"](**fields)
        metadata = t["MetaDataV2"](seq_number=0)
    return bytes(status.encode_bytes()), bytes(metadata.encode_bytes())


def cases(fork, preset):
    if fork == "phase0":  # the node runs altair to fulu, as the fork choice cases do
        return
    spec = module(fork, preset)
    state, block = run(spec, schedule(fork), lambda: anchor(spec, fork))
    status, metadata = run(spec, schedule(fork), lambda: answers(spec, fork, state, block))
    yield "api", "anchor_epoch_2", api_cases(fork, preset)
    late = int(spec.EPOCHS_PER_HISTORICAL_VECTOR) + 6  # the lowest epochs of getEpochCommittees
    yield "api", f"anchor_epoch_{late}", api_cases(fork, preset, epoch=late)
    yield "api", "anchor_epoch_0", api_cases(fork, preset, epoch=0)
    yield "p2p", "anchor_epoch_2", {
        "anchor_state": bytes(state.encode_bytes()),
        "anchor_block": bytes(block.encode_bytes()),
        "status": status,
        "metadata": metadata,
        "status_version": 2 if fork == "fulu" else 1,
        "metadata_version": 3 if fork == "fulu" else 2,
    }


def blob_cases(fork, preset, cases):
    """cases: (name, parts) of the spec's fork_choice on_block cases of the fork."""
    if fork not in ("deneb", "electra"):
        return
    spec = module(fork, preset)
    blobs_type = spec.Blobs  # List[Blob, MAX_BLOB_COMMITMENTS_PER_BLOCK]: a blobs file of the fork choice format
    for name, parts in cases:
        out = {}
        for step in parts["steps"]:
            if "block" not in step or "blobs" not in step:
                continue
            block = spec.SignedBeaconBlock.decode_bytes(parts[step["block"]])
            blobs = list(blobs_type.decode_bytes(parts[step["blobs"]]))
            proofs = [spec.KZGProof(bytes.fromhex(p[2:])) for p in step.get("proofs") or []]
            n = min(len(blobs), len(proofs), len(block.message.body.blob_kzg_commitments))
            sidecars = spec.get_blob_sidecars(block, blobs[:n], proofs[:n])
            out[step["block"]] = [bytes(sidecar.encode_bytes()) for sidecar in sidecars]
        if out:
            yield "blobs", name, out


# ---------------------------------------------------------------- The Beacon API (beacon-api.md, Common rules)

REASONS = {200: b"OK", 206: b"Partial Content", 400: b"Bad Request", 404: b"Not Found", 405: b"Method Not Allowed",
           406: b"Not Acceptable", 413: b"Content Too Large", 414: b"URI Too Long", 415: b"Unsupported Media Type",
           431: b"Request Header Fields Too Large", 500: b"Internal Server Error", 501: b"Not Implemented",
           503: b"Service Unavailable", 505: b"HTTP Version Not Supported"}
MESSAGES = {400: b"BAD_REQUEST", 404: b"NOT_FOUND", 405: b"METHOD_NOT_ALLOWED", 406: b"NOT_ACCEPTABLE",
            413: b"CONTENT_TOO_LARGE", 414: b"URI_TOO_LONG", 415: b"UNSUPPORTED_MEDIA_TYPE",
            431: b"REQUEST_HEADER_FIELDS_TOO_LARGE", 500: b"INTERNAL_SERVER_ERROR", 501: b"NOT_IMPLEMENTED",
            503: b"SERVICE_UNAVAILABLE", 505: b"HTTP_VERSION_NOT_SUPPORTED"}
METHODS = {1: b"GET", 2: b"POST", 3: b"DELETE"}
ALLOW = {1: b"GET", 2: b"POST", 3: b"GET, POST"}
VALIDATOR_OPS = ("getStateValidators", "postStateValidators", "getStateValidator", "getStateValidatorBalances",
                 "postStateValidatorBalances", "postStateValidatorIdentities")
ANSWERED = ("getHealth", "getNetworkIdentity", "getNodeVersion", "getSyncingStatus", "getPeerCount", "getGenesis",
            "getBlockHeader", "getStateFinalityCheckpoints", "getBlockV2", "getStateV2", "getBlockRoot", "getStateRoot",
            "getStateFork", "getSpec", "getForkSchedule", "getDepositContract", "getEpochCommittees",
            "getProposerDuties") + VALIDATOR_OPS
IDENTITY = (b"16Uiu2HAmPLe7Mzm8TsYUubgCAW1aJoeFScxrLj8ppHFivPo97bUZ",
            b"enr:-Iu4QLm7bZGdAhVwRqZ6Zf3LlnqKsBTnZGOByHQhPMQJ3pV4F3t8L9i5yJOZ0X0hiZ6q4D5V0jB7l8J3ZtYw1JDH9C4BgmlkgnY0gmlwhAoAAAGJc2VjcDI1NmsxoQPKY0yuDUmstAHYpMa2_oxVtw0RW_QAdpzBQA8yWM0xOIN0Y3CCIyg",
            b"/ip4/10.0.0.1/tcp/9000/p2p/16Uiu2HAmPLe7Mzm8TsYUubgCAW1aJoeFScxrLj8ppHFivPo97bUZ",
            b"/ip4/10.0.0.1/udp/9000/p2p/16Uiu2HAmPLe7Mzm8TsYUubgCAW1aJoeFScxrLj8ppHFivPo97bUZ",
            b"lantern/v0.1.0")
ROOMS = (64, 512, 128, 128, 64)
SLOTS_AHEAD = 5  # the tick is this many slots past the anchor's


def identity_bytes():
    out = b""
    for text, room in zip(IDENTITY, ROOMS):
        assert len(text) <= room and all(0x21 <= c <= 0x7e and c not in b'"\\' for c in text)
        out += len(text).to_bytes(8, "little") + text + bytes(room - len(text))
    assert len(out) == 936
    return out


def response(code, body=b"", close=False, keep_alive=False, allow=0, reason=True):
    out = b"HTTP/1.1 %d " % code + (REASONS[code] if reason else b"") + b"\r\n"
    if body:
        out += b"Content-Type: application/json\r\n"
    out += b"Content-Length: %d\r\n" % len(body)
    if code == 405:
        out += b"Allow: " + ALLOW[allow] + b"\r\n"
    if close:
        out += b"Connection: close\r\n"
    elif keep_alive:
        out += b"Connection: keep-alive\r\n"
    return out + b"\r\n" + body


def streamed(fork, body, ssz=False, close=False, keep_alive=False):
    """A streamed answer (beacon-api.md, Common rules) in its form with Content-Length; with fork None, no
    Eth-Consensus-Version."""
    out = b"HTTP/1.1 200 OK\r\nContent-Type: " + (b"application/octet-stream" if ssz else b"application/json") + b"\r\n"
    if fork is not None:
        out += b"Eth-Consensus-Version: " + fork.encode() + b"\r\n"
    out += b"Content-Length: %d\r\n" % len(body)
    if close:
        out += b"Connection: close\r\n"
    elif keep_alive:
        out += b"Connection: keep-alive\r\n"
    return out + b"\r\n" + body


def error(code, **kw):
    return response(code, b'{"code":%d,"message":"' % code + MESSAGES[code] + b'"}', **kw)


def q(v):
    return b'"%d"' % v


def qhex(b):
    return b'"0x' + bytes(b).hex().encode() + b'"'


def flag(v):
    return b"true" if v else b"false"


def http(req, version=b"HTTP/1.1", connection=b"", extra=b""):
    """The bytes of a request dict of api_route: its method, target and headers."""
    target = req["path"] + (b"?" + req["query"] if req["query"] else b"")
    out = METHODS[req["method"]] + b" " + target + b" " + version + b"\r\nHost: lantern\r\n"
    for name, key in ((b"Accept", "accept"), (b"Content-Type", "content_type"), (b"Eth-Consensus-Version", "consensus_version")):
        if req[key]:
            out += name + b": " + req[key] + b"\r\n"
    if connection:
        out += b"Connection: " + connection + b"\r\n"
    return out + extra + b"\r\n"


def constants(path):
    """The names of the rows of the Constants tables of a beacon-chain.md, in order."""
    names, on = [], False
    for line in path.read_text().split("\n"):
        if line.startswith("## "):
            on = line.strip() == "## Constants"
        elif on and line.startswith("|") and not line.startswith("| Name") and not set(line) <= set("|-: "):
            names.append(line.strip("|").split("|")[0].strip().strip("`"))
    return names


def config_bodies(fork, preset):
    """The bodies of getSpec, getForkSchedule and getDepositContract (beacon-api.md, Common rules): the
    pinned config with the fork epochs of schedule(fork), the presets, and the constants of the fulu
    module. The config keys and their kinds: CONFIG_KEYS of include/lantern.inc (config.md)."""
    import re
    from ruamel.yaml import YAML
    root = pathlib.Path(os.environ["CONSENSUS_SPECS"])
    inc = (pathlib.Path(__file__).resolve().parents[2] / "include" / "lantern.inc").read_text()
    kinds = {}
    for line in re.search(r"\.macro CONFIG_KEYS m\n(.*?)\.endm", inc, re.S).group(1).splitlines():
        name, _, kind = [x.strip() for x in line.strip()[2:].split(",")]
        kinds[name] = kind
    text = (root / "configs" / f"{preset}.yaml").read_text()
    config = dict(YAML(typ="safe").load(text))
    config.update(schedule(fork))
    sizes = {"CONFIG_KIND_VERSION": 4, "CONFIG_KIND_HASH32": 32, "CONFIG_KIND_ADDRESS": 20}

    def value(name):
        v, kind = config[name], kinds[name]
        if kind in sizes:
            return qhex(int(v).to_bytes(sizes[kind], "big"))
        if kind == "CONFIG_KIND_TEXT":
            return b'"' + str(v).encode() + b'"'
        return q(int(v))

    pairs = []
    for name in re.findall(r"^([A-Z_0-9]+):", text, re.M):
        if name == "SLOT_DURATION_MS":
            pairs.append((b"SECONDS_PER_SLOT", q(int(config[name]) // 1000)))
        if name == "BLOB_SCHEDULE":
            pairs.append((b"BLOB_SCHEDULE", b"[" + b",".join(b'{"EPOCH":' + q(e["EPOCH"]) + b',"MAX_BLOBS_PER_BLOCK":' +
                                                            q(e["MAX_BLOBS_PER_BLOCK"]) + b"}" for e in config[name] or []) + b"]"))
        elif name in kinds:
            pairs.append((name.encode(), value(name)))
    assert len(pairs) == len(kinds) + 2
    for f in FORKS:
        for name, v in YAML(typ="safe").load((root / "presets" / preset / f"{f}.yaml").read_text()).items():
            assert isinstance(v, int)
            pairs.append((name.encode(), q(v)))
    last = module("fulu", preset)
    for f in FORKS:
        for name in constants(root / "specs" / f / "beacon-chain.md"):
            v = getattr(last, name)
            if isinstance(v, bytes):
                out = qhex(v)
            elif isinstance(v, str):
                out = b'"' + v.encode() + b'"'
            elif isinstance(v, list):
                out = b"[" + b",".join(q(int(x)) for x in v) + b"]"
            else:
                out = q(int(v))
            pairs.append((name.encode(), out))
    assert len({k for k, _ in pairs}) == len(pairs)
    spec_body = b'{"data":{' + b",".join(b'"' + k + b'":' + v for k, v in pairs) + b"}}"
    version = int(config["GENESIS_FORK_VERSION"]).to_bytes(4, "big")
    forks = [(version, version, 0)]
    for f in FORKS[1:]:
        epoch = int(config[f"{f.upper()}_FORK_EPOCH"])
        if epoch != U64:
            current = int(config[f"{f.upper()}_FORK_VERSION"]).to_bytes(4, "big")
            forks.append((forks[-1][1], current, epoch))
    schedule_body = b'{"data":[' + b",".join(b'{"previous_version":' + qhex(p) + b',"current_version":' + qhex(c) +
                                             b',"epoch":' + q(e) + b"}" for p, c, e in forks) + b"]}"
    deposit_body = (b'{"data":{"chain_id":' + q(int(config["DEPOSIT_CHAIN_ID"])) + b',"address":' +
                    value("DEPOSIT_CONTRACT_ADDRESS") + b"}}")
    return {"getSpec": spec_body, "getForkSchedule": schedule_body, "getDepositContract": deposit_body}


def api_values(spec, fork, state, block):
    """The values of beacon-api.md for the node at its anchor."""
    store = spec.get_forkchoice_store(state, block)
    root = spec.hash_tree_root(block)
    state_root = spec.hash_tree_root(state)
    header = state.latest_block_header.copy()
    if header.state_root == spec.Bytes32():
        header.state_root = state_root
    assert spec.hash_tree_root(header) == root
    from json_codec import to_json
    states = {int(block.slot): state}  # the anchor state processed to each slot to the store's
    for slot in range(int(block.slot) + 1, int(block.slot) + SLOTS_AHEAD + 1):
        s = state.copy()
        spec.process_slots(s, slot)
        states[slot] = s
    return dict(fork=fork, finalized=store.finalized_checkpoint.root == root, state_ssz=bytes(state.encode_bytes()),
                state_json=to_json(state).encode(), states=states, spec=spec,
                state_roots=[bytes(spec.hash_tree_root(states[s])) for s in (int(block.slot), int(block.slot) + 1)],
                finalized_slot=int(store.finalized_checkpoint.epoch) * int(spec.SLOTS_PER_EPOCH),
                checkpoint_slots={1: int(block.slot), 3: int(store.finalized_checkpoint.epoch) * int(spec.SLOTS_PER_EPOCH),
                                  4: int(store.justified_checkpoint.epoch) * int(spec.SLOTS_PER_EPOCH)},
                genesis_time=int(store.genesis_time_ms) // 1000, gvr=bytes(state.genesis_validators_root),
                genesis_version=bytes(spec.config.GENESIS_FORK_VERSION), root=bytes(root), slot=int(block.slot),
                header=header, cgc=int(spec.config.CUSTODY_REQUIREMENT) if fork == "fulu" else None,
                checkpoints=[state.previous_justified_checkpoint, state.current_justified_checkpoint, state.finalized_checkpoint])


def status_of(spec, val, epoch):
    """The status of a validator at an epoch (beacon-api.md, Common rules)."""
    if val.withdrawable_epoch <= epoch:
        return "withdrawal_done" if val.effective_balance == 0 else "withdrawal_possible"
    if val.exit_epoch <= epoch:
        return "exited_slashed" if val.slashed else "exited_unslashed"
    if val.activation_epoch <= epoch:
        if val.exit_epoch < spec.FAR_FUTURE_EPOCH:
            return "active_slashed" if val.slashed else "active_exiting"
        return "active_ongoing"
    return "pending_initialized" if val.activation_eligibility_epoch == spec.FAR_FUTURE_EPOCH else "pending_queued"


def ref_matches(state, ref):
    """The indices of a ValidatorRef's validators in a state."""
    import struct
    kind, index = struct.unpack_from("<QQ", ref)
    if kind == 1:
        return [index] if index < len(state.validators) else []
    return [i for i, val in enumerate(state.validators) if bytes(val.pubkey) == bytes(ref[16:64])]


def validator_item(spec, state, i, name):
    import api_route
    from json_codec import to_json
    val, epoch = state.validators[i], spec.compute_epoch_at_slot(state.slot)
    if name in ("getStateValidatorBalances", "postStateValidatorBalances"):
        return b'{"index":' + q(i) + b',"balance":' + q(state.balances[i]) + b"}"
    if name == "postStateValidatorIdentities":
        return b'{"index":' + q(i) + b',"pubkey":' + qhex(val.pubkey) + b',"activation_epoch":' + q(val.activation_epoch) + b"}"
    return (b'{"index":' + q(i) + b',"balance":' + q(state.balances[i]) + b',"status":"' +
            status_of(spec, val, epoch).encode() + b'","validator":' + to_json(val).encode() + b"}")


def validators_answer(v, name, route, s, values, kw):
    """The answer of a validator operation for the state s."""
    import api_route
    import struct
    spec = v["spec"]
    if name == "getStateValidator":
        found = ref_matches(s, route.validator)
        if not found:
            return error(404, **kw)
        return response(200, values + b',"data":' + validator_item(spec, s, found[0], name) + b"}", **kw)
    picked = sorted({i for r in route.refs for i in ref_matches(s, r)}) if route.refs else range(len(s.validators))
    epoch = spec.compute_epoch_at_slot(s.slot)
    if route.statuses:
        picked = [i for i in picked
                  if route.statuses >> api_route.STATUSES.index(status_of(spec, s.validators[i], epoch)) & 1]
    if name == "postStateValidatorIdentities" and route.response == 2:
        body = b"".join(struct.pack("<Q", i) + bytes(s.validators[i].pubkey) + struct.pack("<Q", s.validators[i].activation_epoch)
                        for i in picked)
        return streamed(None, body, ssz=True, **kw)
    body = values + b',"data":[' + b",".join(validator_item(spec, s, i, name) for i in picked) + b"]}"
    return streamed(None, body, **kw)


def committees_answer(v, route, s, values, kw):
    """The answer of getEpochCommittees for the state s (beacon-api.md, Common rules)."""
    import api_route
    spec = v["spec"]
    state_epoch = int(spec.get_current_epoch(s))
    given = lambda name: route.present >> api_route.P[name] & 1
    epoch = route.epoch if given("epoch") else state_epoch
    lowest = max(state_epoch + 1 - int(spec.EPOCHS_PER_HISTORICAL_VECTOR), 0)
    if epoch > state_epoch + 1 or max(epoch - int(spec.MIN_SEED_LOOKAHEAD) - 1, 0) < lowest:
        return error(400, **kw)
    if given("slot") and spec.compute_epoch_at_slot(route.slot) != epoch:
        return error(400, **kw)
    count = int(spec.get_committee_count_per_slot(s, epoch))
    if given("index") and route.index >= count:
        return error(400, **kw)
    first = epoch * int(spec.SLOTS_PER_EPOCH)
    slots = [route.slot] if given("slot") else range(first, first + int(spec.SLOTS_PER_EPOCH))
    indices = [route.index] if given("index") else range(count)
    items = [b'{"index":' + q(i) + b',"slot":' + q(slot) + b',"validators":[' +
             b",".join(q(m) for m in spec.get_beacon_committee(s, spec.Slot(slot), spec.CommitteeIndex(i))) + b"]}"
             for slot in slots for i in indices]
    return streamed(None, values + b',"data":[' + b",".join(items) + b"]}", **kw)


def duties_answer(v, route, kw, syncing):
    """The answer of getProposerDuties (beacon-api.md, Common rules)."""
    spec = v["spec"]
    if syncing:
        return error(503, **kw)
    spe = int(spec.SLOTS_PER_EPOCH)
    store_slot = v["slot"] + SLOTS_AHEAD
    epoch = route.epoch
    if epoch > store_slot // spe + 1:
        return error(400, **kw)
    first = epoch * spe
    if first > store_slot:  # the next epoch: the head's post-state brought to its first slot
        s = v["states"][v["slot"]].copy()
        spec.process_slots(s, first)
    elif first in v["states"]:
        s = v["states"][first]
    else:
        return error(404, **kw)
    items = []
    for slot in range(first, first + spe):
        at = s.copy()
        at.slot = slot
        i = int(spec.get_beacon_proposer_index(at))
        items.append(b'{"pubkey":' + qhex(s.validators[i].pubkey) + b',"validator_index":' + q(i) + b',"slot":' + q(slot) + b"}")
    root = v["root"] if first == 0 else bytes(spec.get_block_root_at_slot(s, first - 1))
    return response(200, b'{"dependent_root":' + qhex(root) + b',"execution_optimistic":false,"data":[' +
                    b",".join(items) + b"]}", **kw)


def answer(v, name, route, offline, close, keep_alive, syncing=False):
    """The response of an operation the node answers, with the route's ApiRoute."""
    kw = dict(close=close, keep_alive=keep_alive)
    if name == "getProposerDuties":
        return duties_answer(v, route, kw, syncing)
    current = v["slot"] + SLOTS_AHEAD
    if name == "getHealth":
        if not offline:
            return response(200, **kw)
        if route.syncing_status:
            return response(route.syncing_status, reason=False, **kw)
        return response(206, **kw)
    if name == "getNodeVersion":
        return response(200, b'{"data":{"version":"' + IDENTITY[4] + b'"}}', **kw)
    if name == "getNetworkIdentity":
        meta = b'{"seq_number":"0","attnets":"0x0000000000000000","syncnets":"0x00"'
        if v["cgc"] is not None:
            meta += b',"custody_group_count":' + q(v["cgc"])
        body = (b'{"data":{"peer_id":"' + IDENTITY[0] + b'","enr":"' + IDENTITY[1] + b'","p2p_addresses":["' + IDENTITY[2] +
                b'"],"discovery_addresses":["' + IDENTITY[3] + b'"],"metadata":' + meta + b"}}}")
        return response(200, body, **kw)
    if name == "getSyncingStatus":
        body = (b'{"data":{"head_slot":' + q(v["slot"]) + b',"sync_distance":' + q(current - v["slot"]) +
                b',"is_syncing":false,"is_optimistic":false,"el_offline":' + flag(offline) + b"}}")
        return response(200, body, **kw)
    if name == "getPeerCount":
        return response(200, b'{"data":{"disconnected":"0","connecting":"0","connected":"0","disconnecting":"0"}}', **kw)
    if name in ("getSpec", "getForkSchedule", "getDepositContract"):
        return response(200, v["config_bodies"][name], **kw)
    if name == "getGenesis":
        body = (b'{"data":{"genesis_time":' + q(v["genesis_time"]) + b',"genesis_validators_root":' + qhex(v["gvr"]) +
                b',"genesis_fork_version":' + qhex(v["genesis_version"]) + b"}}")
        return response(200, body, **kw)
    if name in ("getBlockHeader", "getBlockRoot", "getBlockV2"):
        # The chain is the anchor alone: head, finalized, its slot and its root name it.
        found = (route.id_kind in (1, 3) or (route.id_kind == 5 and route.id_slot == v["slot"]) or
                 (route.id_kind == 2 and v["slot"] == 0) or (route.id_kind == 6 and route.id_root == v["root"]))
        if not found or name == "getBlockV2":  # the anchor block's bytes are not the node's
            return error(404, **kw)
        values = b'{"execution_optimistic":false,"finalized":true,"data":{"root":' + qhex(v["root"])
        if name == "getBlockRoot":
            return response(200, values + b"}}", **kw)
        h = v["header"]
        body = (values + b',"canonical":true,"header":{"message":{"slot":' + q(h.slot) + b',"proposer_index":' + q(h.proposer_index) +
                b',"parent_root":' + qhex(h.parent_root) + b',"state_root":' + qhex(h.state_root) + b',"body_root":' +
                qhex(h.body_root) + b'},"signature":' + qhex(bytes(96)) + b"}}}")
        return response(200, body, **kw)
    if name in ("getStateRoot", "getStateFork", "getStateFinalityCheckpoints", "getStateV2", "getEpochCommittees") + VALIDATOR_OPS:
        if route.id_kind in v["checkpoint_slots"]:
            slot = v["checkpoint_slots"][route.id_kind]
        elif route.id_kind == 5 or (route.id_kind == 2):
            slot = route.id_slot if route.id_kind == 5 else 0
        else:  # a state root: the head state's own, else the highest slot of its state_roots below it
            spec, head = v["spec"], v["states"][v["slot"]]
            n, slot = int(spec.SLOTS_PER_HISTORICAL_ROOT), None
            if bytes(spec.hash_tree_root(head)) == route.id_root:
                slot = v["slot"]
            else:
                for s in range(v["slot"] - 1, max(0, v["slot"] - n) - 1, -1):
                    if bytes(head.state_roots[s % n]) == route.id_root:
                        slot = s
                        break
            if slot is None:
                return error(404, **kw)
        if slot not in v["states"]:
            return error(404, **kw)
        s, spec = v["states"][slot], v["spec"]
        values = b'{"execution_optimistic":false,"finalized":' + flag(slot <= v["finalized_slot"])
        if name in VALIDATOR_OPS:
            return validators_answer(v, name, route, s, values, kw)
        if name == "getEpochCommittees":
            return committees_answer(v, route, s, values, kw)
        if name == "getStateRoot":
            return response(200, values + b',"data":{"root":' + qhex(spec.hash_tree_root(s)) + b"}}", **kw)
        if name == "getStateFork":
            f = s.fork
            return response(200, values + b',"data":{"previous_version":' + qhex(f.previous_version) + b',"current_version":' +
                            qhex(f.current_version) + b',"epoch":' + q(f.epoch) + b"}}", **kw)
        if name == "getStateFinalityCheckpoints":
            c = [s.previous_justified_checkpoint, s.current_justified_checkpoint, s.finalized_checkpoint]
            body = (values + b',"data":{"previous_justified":{"epoch":' + q(c[0].epoch) +
                    b',"root":' + qhex(c[0].root) + b'},"current_justified":{"epoch":' + q(c[1].epoch) + b',"root":' +
                    qhex(c[1].root) + b'},"finalized":{"epoch":' + q(c[2].epoch) + b',"root":' + qhex(c[2].root) + b"}}}")
            return response(200, body, **kw)
        if route.response == 2:
            return streamed(v["fork"], bytes(s.encode_bytes()), ssz=True, **kw)
        from json_codec import to_json
        body = (b'{"version":"' + v["fork"].encode() + b'",' + values[1:] + b',"data":' + to_json(s).encode() + b"}")
        return streamed(v["fork"], body, **kw)
    raise AssertionError(name)


class Route:
    """The fields of an ApiRoute the answers read, from api_route.route."""
    def __init__(self, out):
        import struct
        self.op = struct.unpack_from("<Q", out, 16)[0]
        self.response = struct.unpack_from("<Q", out, 48)[0]
        self.id_kind = struct.unpack_from("<Q", out, 72)[0]
        self.id_slot = struct.unpack_from("<Q", out, 80)[0]
        self.id_root = bytes(out[88:120])
        self.syncing_status = struct.unpack_from("<Q", out, 240)[0]
        self.validator = bytes(out[120:184])
        self.present = struct.unpack_from("<Q", out, 40)[0]
        self.epoch, self.slot, self.index = struct.unpack_from("<QQQ", out, 184)
        self.statuses = struct.unpack_from("<Q", out, 264)[0]
        at, count = struct.unpack_from("<QQ", out, 456)
        self.refs = [bytes(out[at + 64 * k:at + 64 * k + 64]) for k in range(count)]


def api_requests(spec, fork, v, kind="main"):
    """(name, request bytes, response, closes, offline, syncing) of each request of a node at its
    anchor; kind "late", those of getEpochCommittees at its lowest epochs; kind "genesis", those of
    getProposerDuties of an anchor at slot 0."""
    import api_route
    ops = api_route.operations(pathlib.Path(os.environ["BEACON_APIS"]))
    by_name = {op["name"]: op for op in ops}
    out = []

    def add(name, req, offline=False, version=b"HTTP/1.1", connection=b"", extra=b"", body=None, syncing=False):
        if body is not None:
            req = dict(req, body=body)
            extra += b"Content-Length: %d\r\n" % len(body)
        raw = http(req, version, connection, extra) + (body or b"")
        close = connection.lower() == b"close" or (version == b"HTTP/1.0" and connection.lower() != b"keep-alive")
        keep_alive = version == b"HTTP/1.0" and not close
        status, r = api_route.route(ops, req, 1 << 24)
        if status != api_route.OK:
            want = error(r.http, close=close, keep_alive=keep_alive, allow=r.allow)
        else:
            route = Route(r)
            opname = ops[route.op - 1]["name"]
            if opname in ANSWERED:
                want = answer(v, opname, route, offline, close, keep_alive, syncing)
            else:
                want = error(501, close=close, keep_alive=keep_alive)
        out.append((name, raw, want, close, offline, syncing))

    committees = by_name["getEpochCommittees"]
    duties = by_name["getProposerDuties"]
    epoch = v["slot"] // int(spec.SLOTS_PER_EPOCH)
    current = (v["slot"] + SLOTS_AHEAD) // int(spec.SLOTS_PER_EPOCH)
    if kind == "genesis":
        for e in range(0, 3):
            add(f"duties_{e}", api_route.base(duties, path_values={"epoch": b"%d" % e}))
        return out
    if kind == "late":  # the lowest epoch whose seed's RANDAO mix the state holds, and the one below
        lowest = epoch + 1 - int(spec.EPOCHS_PER_HISTORICAL_VECTOR) + int(spec.MIN_SEED_LOOKAHEAD) + 1
        for e in (epoch, lowest, lowest - 1):
            add(f"committees_epoch_{e}", api_route.base(committees, [("epoch", b"%d" % e)]))
        add("committees_low_slot", api_route.base(committees, [("epoch", b"%d" % lowest),
                                                              ("slot", b"%d" % (lowest * int(spec.SLOTS_PER_EPOCH) + 3))]))
        return out
    for op in ops:
        add(op["name"], api_route.base(op))
    for name in ANSWERED:
        add(f"{name}_offline", api_route.base(by_name[name]), offline=True)
    health = by_name["getHealth"]
    add("health_syncing_status", api_route.base(health, [("syncing_status", b"500")]))
    add("health_syncing_status_offline", api_route.base(health, [("syncing_status", b"299")]), offline=True)
    header = by_name["getBlockHeader"]
    add("header_head", api_route.base(header, path_values={"block_id": b"head"}))
    add("header_root", api_route.base(header, path_values={"block_id": qhex(v["root"])[1:-1]}))
    add("header_root_upper", api_route.base(header, path_values={"block_id": b"0x" + v["root"].hex().upper().encode()}))
    add("header_other_root", api_route.base(header, path_values={"block_id": b"0x" + bytes(32).hex().encode()}))
    for block_id in (b"genesis", b"finalized", b"16"):
        add(f"header_{block_id.decode()}", api_route.base(header, path_values={"block_id": block_id}))
    finality = by_name["getStateFinalityCheckpoints"]
    for state_id in (b"head", b"genesis", b"finalized", b"justified", b"0", b"0x" + bytes(32).hex().encode()):
        add(f"finality_{state_id.decode()[:10]}", api_route.base(finality, path_values={"state_id": state_id}))
    version = by_name["getNodeVersion"]
    add("close", api_route.base(version), connection=b"close")
    add("close_upper", api_route.base(version), connection=b"Close")
    add("keep_alive_11", api_route.base(version), connection=b"keep-alive")
    add("http10", api_route.base(version), version=b"HTTP/1.0")
    add("http10_keep_alive", api_route.base(version), version=b"HTTP/1.0", connection=b"keep-alive")
    add("http10_keep_alive_identity", api_route.base(by_name["getNetworkIdentity"]), version=b"HTTP/1.0", connection=b"keep-alive")
    add("http10_header_404", api_route.base(header, path_values={"block_id": b"genesis"}), version=b"HTTP/1.0")
    add("spec_http10", api_route.base(by_name["getSpec"]), version=b"HTTP/1.0")
    add("spec_close", api_route.base(by_name["getSpec"]), connection=b"close")
    add("fork_schedule_http10", api_route.base(by_name["getForkSchedule"]), version=b"HTTP/1.0")
    add("unknown_path", api_route.request(1, b"/eth/v1/node/bogus"))
    add("post_on_get", api_route.request(2, b"/eth/v1/node/version"))
    add("get_on_post", api_route.request(1, b"/eth/v1/validator/prepare_beacon_proposer"))
    add("delete_on_both", api_route.request(3, b"/eth/v1/beacon/states/head/validators"))
    add("delete_on_get_405_close", api_route.request(3, b"/eth/v1/node/health"), connection=b"close")
    block = by_name["getBlockV2"]
    add("accept_406", api_route.base(block, accept=b"text/html"))
    add("accept_ssz", api_route.base(block, accept=b"application/octet-stream"))
    add("bad_block_id_400", api_route.base(header, path_values={"block_id": b"0x12"}))
    state = by_name["getStateV2"]
    octet = b"application/octet-stream"
    add("state_head_json", api_route.base(state, path_values={"state_id": b"head"}))
    add("state_head_ssz", api_route.base(state, path_values={"state_id": b"head"}, accept=octet))
    add("state_head_json_http10", api_route.base(state, path_values={"state_id": b"head"}), version=b"HTTP/1.0")
    add("state_head_ssz_http10", api_route.base(state, path_values={"state_id": b"head"}, accept=octet), version=b"HTTP/1.0")
    add("state_head_ssz_http10_keep_alive", api_route.base(state, path_values={"state_id": b"head"}, accept=octet),
        version=b"HTTP/1.0", connection=b"keep-alive")
    add("state_head_json_close", api_route.base(state, path_values={"state_id": b"head"}), connection=b"close")
    for state_id in (b"genesis", b"finalized", b"0", qhex(v["root"])[1:-1]):
        add(f"state_{state_id.decode()[:10]}", api_route.base(state, path_values={"state_id": state_id}))
    for block_id in (b"head", qhex(v["root"])[1:-1], b"finalized"):
        add(f"block_{block_id.decode()[:10]}", api_route.base(block, path_values={"block_id": block_id}))
        add(f"block_{block_id.decode()[:10]}_ssz", api_route.base(block, path_values={"block_id": block_id}, accept=octet))
    root_id, other_root = qhex(v["root"])[1:-1], b"0x" + bytes(range(32)).hex().encode()
    for op in ("getBlockRoot", "getBlockHeader", "getBlockV2"):
        for block_id in (b"head", b"finalized", b"genesis", b"%d" % (v["slot"] - 1), b"%d" % v["slot"], b"%d" % (v["slot"] + 1),
                         root_id, other_root):
            add(f"lookup_{op}_{block_id.decode()[:12]}", api_route.base(by_name[op], path_values={"block_id": block_id}))
    for op in ("getStateRoot", "getStateFork", "getStateFinalityCheckpoints"):
        ids = [b"head", b"finalized", b"justified", b"genesis", other_root, qhex(v["state_roots"][0])[1:-1],
               qhex(v["state_roots"][1])[1:-1]]
        ids += [b"%d" % s for s in range(v["slot"], v["slot"] + SLOTS_AHEAD + 2)]
        for state_id in ids:
            add(f"lookup_{op}_{state_id.decode()[:12]}", api_route.base(by_name[op], path_values={"state_id": state_id}))
    for state_id in (b"finalized", b"%d" % (v["slot"] + 2)):
        add(f"lookup_getStateV2_{state_id.decode()}", api_route.base(state, path_values={"state_id": state_id}))
    validators = by_name["getStateValidators"]
    add("ids_65_414", api_route.base(validators, [("id", b",".join(str(i).encode() for i in range(65)))]))
    for e in range(epoch - 1, current + 3):
        add(f"duties_{e}", api_route.base(duties, path_values={"epoch": b"%d" % e}))
    add("duties_syncing", api_route.base(duties, path_values={"epoch": b"%d" % current}), syncing=True)
    first = epoch * int(spec.SLOTS_PER_EPOCH)
    for e in range(epoch - 1, epoch + 3):
        add(f"committees_epoch_{e}", api_route.base(committees, [("epoch", b"%d" % e)]))
    for k, items in enumerate([[("slot", b"%d" % (first + 1))], [("slot", b"%d" % (first - 1))], [("index", b"0")],
                               [("index", b"1")], [("slot", b"%d" % (first + 2)), ("index", b"0")],
                               [("epoch", b"%d" % (epoch + 1)), ("slot", b"%d" % (first + int(spec.SLOTS_PER_EPOCH))),
                                ("index", b"0")]]):
        add(f"committees_{k}", api_route.base(committees, items))
    add("committees_http10", api_route.base(committees), version=b"HTTP/1.0")
    for state_id in (b"finalized", b"%d" % (v["slot"] + 2), qhex(v["state_roots"][0])[1:-1]):
        add(f"committees_{state_id.decode()[:12]}", api_route.base(committees, path_values={"state_id": state_id}))

    def pk(i):
        return b"0x" + (bytes([i + 1]) * 48).hex().encode()

    add("validators_ids", api_route.base(validators, [("id", b"0,3,15,99,3," + pk(9) + b"," + pk(200))]))
    for k, s in enumerate(api_route.STATUSES + tuple(api_route.GROUPS)):
        add(f"validators_status_{s}", api_route.base(validators, [("status", s.encode())]))
    add("validators_ids_status", api_route.base(validators, [("id", b"10,11,12," + pk(13)), ("status", b"active,exited_slashed")]))
    for state_id in (b"finalized", b"%d" % (v["slot"] + 2), qhex(v["state_roots"][1])[1:-1], other_root):
        add(f"validators_{state_id.decode()[:12]}", api_route.base(validators, [("status", b"pending")],
                                                                    path_values={"state_id": state_id}))
    add("validators_http10", api_route.base(validators), version=b"HTTP/1.0")
    add("validators_close", api_route.base(validators), connection=b"close")
    post = by_name["postStateValidators"]
    for k, body in enumerate([b"{}", b'{"ids":["1","' + pk(12) + b'"],"statuses":["exited"]}', b'{"statuses":["withdrawal"]}',
                              b'{"ids":["' + pk(15) + b'","' + pk(15) + b'"]}', b'{"ids":["7"]}x']):
        add(f"post_validators_{k}", api_route.base(post), body=body)
    add("post_validators_root", api_route.base(post, path_values={"state_id": qhex(v["state_roots"][0])[1:-1]}),
        body=b'{"ids":["2","9"]}')
    one = by_name["getStateValidator"]
    for k, vid in enumerate([b"3", pk(14), b"99", pk(250), b"16"]):
        add(f"validator_{k}", api_route.base(one, path_values={"validator_id": vid}))
    add("validator_finalized", api_route.base(one, path_values={"validator_id": b"11", "state_id": b"finalized"}))
    add("validator_root", api_route.base(one, path_values={"validator_id": pk(10), "state_id": qhex(v["state_roots"][1])[1:-1]}))
    balances = by_name["getStateValidatorBalances"]
    add("balances_ids", api_route.base(balances, [("id", b"1,2,15,77," + pk(4))]))
    post_balances = by_name["postStateValidatorBalances"]
    for k, body in enumerate([b'["0","' + pk(5) + b'"]', b"[]", b"null"]):
        add(f"post_balances_{k}", api_route.base(post_balances), body=body)
    identities = by_name["postStateValidatorIdentities"]
    for k, body in enumerate([None, b'["8","9","' + pk(1) + b'"]']):
        add(f"identities_{k}", api_route.base(identities), body=body)
        add(f"identities_{k}_ssz", api_route.base(identities, accept=octet), body=body)
    publish = by_name["publishBlockV2"]
    add("content_type_415", api_route.base(publish, content_type=b"text/plain"), extra=b"Content-Length: 0\r\n")
    add("version_missing_400", dict(api_route.base(publish), consensus_version=b""))
    return out


def http_faults():
    """(name, request bytes, status) of requests lantern_http_request finds faulty."""
    host = b"Host: lantern\r\n"
    return [
        ("head_431", b"GET /eth/v1/node/version HTTP/1.1\r\n" + host + b"X: " + b"a" * 16400 + b"\r\n\r\n", 431),
        ("body_413", b"POST /eth/v1/beacon/pool/voluntary_exits HTTP/1.1\r\n" + host + b"Content-Length: 1048577\r\n\r\n", 413),
        ("line_400", b"GET  /eth/v1/node/version HTTP/1.1\r\n" + host + b"\r\n", 400),
        ("no_host_400", b"GET /eth/v1/node/version HTTP/1.1\r\n\r\n", 400),
        ("version_505", b"GET /eth/v1/node/version HTTP/2.0\r\n" + host + b"\r\n", 505),
        ("coding_501", b"POST /eth/v1/beacon/pool/voluntary_exits HTTP/1.1\r\n" + host + b"Transfer-Encoding: gzip\r\n\r\n", 501),
    ]


def api_cases(fork, preset, epoch=ANCHOR_EPOCH):
    """The api case of an anchor at the epoch; at epoch 0, the requests of getProposerDuties alone;
    at another epoch, those of getEpochCommittees at its lowest epochs alone."""
    spec = module(fork, preset)
    state, block = run(spec, schedule(fork), lambda: anchor(spec, fork, statuses=True, epoch=epoch))
    v = run(spec, schedule(fork), lambda: api_values(spec, fork, state, block))
    v["config_bodies"] = config_bodies(fork, preset)
    kind = "main" if epoch == ANCHOR_EPOCH else "genesis" if epoch == 0 else "late"
    reqs = run(spec, schedule(fork), lambda: api_requests(spec, fork, v, kind))
    if fork in ("altair",):  # no execution engine before bellatrix: el_offline stays false
        reqs = [r for r in reqs if not r[4]]
    names, raws, wants, closes, offline, syncing = [], [], [], [], [], []
    for name, raw, want, close, off, sync in sorted(reqs, key=lambda r: r[4]):
        names.append(name.encode())
        raws.append(raw)
        wants.append(want)
        closes.append(1 if close else 0)
        offline.append(off)
        syncing.append(1 if sync else 0)
    for name, raw, status in http_faults() if epoch == ANCHOR_EPOCH else []:
        names.append(name.encode())
        raws.append(raw)
        wants.append(error(status, close=True))
        closes.append(1)
        offline.append(offline[-1] if offline else False)
        syncing.append(0)
    first_offline = offline.index(True) if True in offline else len(names)
    slot_ms = int(spec.config.SLOT_DURATION_MS) if hasattr(spec.config, "SLOT_DURATION_MS") else int(spec.config.SECONDS_PER_SLOT) * 1000
    return {
        "anchor_state": bytes(state.encode_bytes()),
        "anchor_block": bytes(block.encode_bytes()),
        "identity": identity_bytes(),
        "time_ms": (v["genesis_time"] + 0) * 1000 + (v["slot"] + SLOTS_AHEAD) * slot_ms,
        "names": names,
        "requests": raws,
        "responses": wants,
        "closes": bytes(closes),
        "syncing": bytes(syncing),
        "offline": first_offline,
    }
