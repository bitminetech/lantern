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


def anchor(spec, fork):
    """A state at the first slot of epoch ANCHOR_EPOCH with 8 validators, and its block."""
    slot = spec.Slot(ANCHOR_EPOCH * spec.SLOTS_PER_EPOCH)
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
           505: b"HTTP Version Not Supported"}
MESSAGES = {400: b"BAD_REQUEST", 404: b"NOT_FOUND", 405: b"METHOD_NOT_ALLOWED", 406: b"NOT_ACCEPTABLE",
            413: b"CONTENT_TOO_LARGE", 414: b"URI_TOO_LONG", 415: b"UNSUPPORTED_MEDIA_TYPE",
            431: b"REQUEST_HEADER_FIELDS_TOO_LARGE", 500: b"INTERNAL_SERVER_ERROR", 501: b"NOT_IMPLEMENTED",
            505: b"HTTP_VERSION_NOT_SUPPORTED"}
METHODS = {1: b"GET", 2: b"POST", 3: b"DELETE"}
ALLOW = {1: b"GET", 2: b"POST", 3: b"GET, POST"}
ANSWERED = ("getHealth", "getNetworkIdentity", "getNodeVersion", "getSyncingStatus", "getPeerCount", "getGenesis",
            "getBlockHeader", "getStateFinalityCheckpoints", "getBlockV2", "getStateV2", "getBlockRoot", "getStateRoot",
            "getStateFork")
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
    """A streamed answer (beacon-api.md, Common rules) in its form with Content-Length."""
    out = b"HTTP/1.1 200 OK\r\nContent-Type: " + (b"application/octet-stream" if ssz else b"application/json") + b"\r\n"
    out += b"Eth-Consensus-Version: " + fork.encode() + b"\r\nContent-Length: %d\r\n" % len(body)
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


def answer(v, name, route, offline, close, keep_alive):
    """The response of an operation the node answers, with the route's ApiRoute."""
    kw = dict(close=close, keep_alive=keep_alive)
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
    if name in ("getStateRoot", "getStateFork", "getStateFinalityCheckpoints", "getStateV2"):
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


def api_requests(spec, fork, v):
    """(name, request bytes, response, closes, offline) of each request of a node at its anchor."""
    import api_route
    ops = api_route.operations(pathlib.Path(os.environ["BEACON_APIS"]))
    by_name = {op["name"]: op for op in ops}
    out = []

    def add(name, req, offline=False, version=b"HTTP/1.1", connection=b"", extra=b""):
        raw = http(req, version, connection, extra)
        close = connection.lower() == b"close" or (version == b"HTTP/1.0" and connection.lower() != b"keep-alive")
        keep_alive = version == b"HTTP/1.0" and not close
        status, r = api_route.route(ops, req, 1 << 24)
        if status != api_route.OK:
            want = error(r.http, close=close, keep_alive=keep_alive, allow=r.allow)
        else:
            route = Route(r)
            opname = ops[route.op - 1]["name"]
            if opname in ANSWERED:
                want = answer(v, opname, route, offline, close, keep_alive)
            else:
                want = error(501, close=close, keep_alive=keep_alive)
        out.append((name, raw, want, close, offline))

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


def api_cases(fork, preset):
    spec = module(fork, preset)
    state, block = run(spec, schedule(fork), lambda: anchor(spec, fork))
    v = run(spec, schedule(fork), lambda: api_values(spec, fork, state, block))
    reqs = run(spec, schedule(fork), lambda: api_requests(spec, fork, v))
    if fork in ("altair",):  # no execution engine before bellatrix: el_offline stays false
        reqs = [r for r in reqs if not r[4]]
    names, raws, wants, closes, offline = [], [], [], [], []
    for name, raw, want, close, off in sorted(reqs, key=lambda r: r[4]):
        names.append(name.encode())
        raws.append(raw)
        wants.append(want)
        closes.append(1 if close else 0)
        offline.append(off)
    for name, raw, status in http_faults():
        names.append(name.encode())
        raws.append(raw)
        wants.append(error(status, close=True))
        closes.append(1)
        offline.append(offline[-1] if offline else False)
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
        "offline": first_offline,
    }
