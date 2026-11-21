"""Cases of lantern's p2p helpers (docs/reference/networking.md), made with the pinned spec.

The spec functions run in the fork's spec module that run.sh generates from consensus-specs
v1.7.0-beta.4 (aa16bb4). The rules that the spec states only in prose follow its text, and
call the spec module for every value the text names:
- the ENR eth2 value and the ENR nfd value: the "eth2 field" and "Next fork digest" sections
  of phase0 and fulu p2p-interface.md;
- gossip topic strings: "Topics and messages" of phase0 p2p-interface.md;
- the gossip message-id: phase0 and altair p2p-interface.md.

cases(fork, preset) yields (handler, name, parts). A case's parts: "config", the values that
replace the preset's config; "input"; and "output", or None where the spec raises.
"""

import hashlib
import struct

import snappy

FORKS = ("phase0", "altair", "bellatrix", "capella", "deneb", "electra", "fulu")
U64 = (1 << 64) - 1
FAR_FUTURE_EPOCH = U64
ROOT = bytes(range(32))

# A config with every fork two epochs apart and two BPO forks after fulu.
SCHEDULE = {
    "ALTAIR_FORK_EPOCH": 2,
    "BELLATRIX_FORK_EPOCH": 4,
    "CAPELLA_FORK_EPOCH": 6,
    "DENEB_FORK_EPOCH": 8,
    "ELECTRA_FORK_EPOCH": 10,
    "FULU_FORK_EPOCH": 12,
    "BLOB_SCHEDULE": [{"EPOCH": 14, "MAX_BLOBS_PER_BLOCK": 12}, {"EPOCH": 17, "MAX_BLOBS_PER_BLOCK": 20}],
}
# Topic names (include/lantern.inc GOSSIP_*), and whether each has a subnet.
TOPICS = [
    ("beacon_block", False),
    ("beacon_aggregate_and_proof", False),
    ("beacon_attestation", True),
    ("voluntary_exit", False),
    ("proposer_slashing", False),
    ("attester_slashing", False),
    ("sync_committee_contribution_and_proof", False),
    ("sync_committee", True),
    ("bls_to_execution_change", False),
    ("blob_sidecar", True),
    ("data_column_sidecar", True),
    ("light_client_finality_update", False),
    ("light_client_optimistic_update", False),
]


def module(fork, preset):
    return __import__(f"eth_consensus_specs.{fork}.{preset}", fromlist=["*"])


def run(spec, config, f):
    """f() with the preset's config changed by config; None where the spec raises."""
    base = spec.config
    values = dict(base._asdict())
    for key, value in config.items():
        if key not in values:  # a value of a later fork, which this fork's spec does not read
            continue
        old = values[key]
        if key == "BLOB_SCHEDULE":  # each entry keeps the types of the preset's entries
            kind = type(old[0]) if old else dict
            value = tuple(kind({k: type(old[0][k])(v) if old else v for k, v in e.items()}) for e in value)
        else:  # the spec's own type, so its arithmetic raises as the spec's does
            value = type(old)(value)
        values[key] = value
    spec.config = base.__class__(**values)
    try:
        return f()
    except (AssertionError, ValueError, OverflowError, ZeroDivisionError, IndexError):
        return None
    finally:
        spec.config = base


def fork_epochs(spec, fork):
    """The fork epochs a client of the fork knows, and the BPO epochs of fulu."""
    names = FORKS[1 : FORKS.index(fork) + 1]
    epochs = [int(getattr(spec.config, f"{name.upper()}_FORK_EPOCH")) for name in names]
    if fork == "fulu":
        epochs += [int(e["EPOCH"]) for e in spec.config.BLOB_SCHEDULE if e["EPOCH"] >= spec.config.FULU_FORK_EPOCH]
    return epochs


def next_fork_epoch(spec, fork, epoch):
    return min([e for e in fork_epochs(spec, fork) if e > epoch], default=FAR_FUTURE_EPOCH)


def enr_fork_id(spec, fork, root, epoch):
    """phase0 and fulu p2p-interface.md, "eth2 field"."""
    digest = bytes(spec.compute_fork_digest(spec.Root(root), spec.Epoch(epoch)))
    nxt = next_fork_epoch(spec, fork, epoch)
    version = spec.compute_fork_version(spec.Epoch(epoch if nxt == FAR_FUTURE_EPOCH else nxt))
    return digest + bytes(version) + struct.pack("<Q", nxt)


def next_fork_digest(spec, fork, root, epoch):
    """fulu p2p-interface.md, "Next fork digest"."""
    nxt = next_fork_epoch(spec, fork, epoch)
    if nxt == FAR_FUTURE_EPOCH:
        return bytes(4)
    return bytes(spec.compute_fork_digest(spec.Root(root), spec.Epoch(nxt)))


def topic_string(digest, name, subnet):
    """phase0 p2p-interface.md, "Topics and messages": /eth2/ForkDigestValue/Name/Encoding."""
    text, has_subnet = TOPICS[name - 1]
    if has_subnet:
        text += f"_{subnet}"
    return f"/eth2/{digest.hex()}/{text}/ssz_snappy".encode()


def message_id(spec, fork, topic, data, max_payload):
    """phase0 and altair p2p-interface.md: the message-id. A decompression above
    MAX_PAYLOAD_SIZE counts as not valid (docs/reference/networking.md)."""
    try:
        raw = snappy.uncompress(data)
        valid = len(raw) <= max_payload
    except Exception:
        valid = False
    domain = bytes(spec.config.MESSAGE_DOMAIN_VALID_SNAPPY if valid else spec.config.MESSAGE_DOMAIN_INVALID_SNAPPY)
    prefix = b"" if fork == "phase0" else struct.pack("<Q", len(topic)) + topic
    return hashlib.sha256(domain + prefix + (raw if valid else data)).digest()[:20]


def cases(fork, preset):
    spec = module(fork, preset)
    configs = [("preset", {}), ("schedule", SCHEDULE)]
    epochs = [0, 1, 2, 3, 4, 7, 8, 10, 11, 12, 13, 14, 16, 17, 18, 411392, 412672, 419072, U64 - 1, U64]

    for cname, config in configs:
        for epoch in epochs:
            out = run(spec, config, lambda: bytes(spec.compute_fork_version(spec.Epoch(epoch))))
            yield "compute_fork_version", f"{cname}_{epoch}", {"config": config, "input": {"epoch": epoch}, "output": out}
            for rname, root in (("zero", bytes(32)), ("root", ROOT)):
                out = run(spec, config, lambda: bytes(spec.compute_fork_digest(spec.Root(root), spec.Epoch(epoch))))
                parts = {"config": config, "input": {"genesis_validators_root": root, "epoch": epoch}, "output": out}
                yield "compute_fork_digest", f"{cname}_{rname}_{epoch}", parts
                out = run(spec, config, lambda: enr_fork_id(spec, fork, root, epoch))
                parts = {"config": config, "input": {"genesis_validators_root": root, "current_epoch": epoch}, "output": out}
                yield "compute_enr_fork_id", f"{cname}_{rname}_{epoch}", parts
                if fork == "fulu":
                    out = run(spec, config, lambda: next_fork_digest(spec, fork, root, epoch))
                    yield "compute_next_fork_digest", f"{cname}_{rname}_{epoch}", dict(parts, output=out)

    for extra in (0, 1, 4, U64 - 6, U64 - 5):
        config = {"ATTESTATION_SUBNET_EXTRA_BITS": extra}
        out = run(spec, config, lambda: int(spec.compute_attestation_subnet_prefix_bits()))
        yield "compute_attestation_subnet_prefix_bits", f"extra_{extra}", {"config": config, "input": {}, "output": out}

    for delay, quotient in ((None, None), (0, 0), (5, 11), (U64 - 3, 6), (U64 - 3, 8), (U64, 1), (U64, 2)):
        config = {} if delay is None else {"MIN_VALIDATOR_WITHDRAWABILITY_DELAY": delay, "CHURN_LIMIT_QUOTIENT": quotient}
        out = run(spec, config, lambda: int(spec.compute_min_epochs_for_block_requests()))
        yield "compute_min_epochs_for_block_requests", f"{delay}_{quotient}", {"config": config, "input": {}, "output": out}

    top = (U64 - 32) * 6 // 7  # near the largest n whose length fits
    for n in [0, 1, 5, 6, 7, 12, 100, 65536, 10485760, U64] + list(range(top - 6, top + 7)):
        out = run(spec, {}, lambda: int(spec.max_compressed_len(spec.Uint64(n))))
        yield "max_compressed_len", f"n_{n}", {"config": {}, "input": {"n": n}, "output": out}

    for size in (None, 0, 100, 899000, 899100, 10485760, U64 - 2000, U64):
        config = {} if size is None else {"MAX_PAYLOAD_SIZE": size}
        out = run(spec, config, lambda: int(spec.max_message_size()))
        yield "max_message_size", f"size_{size}", {"config": config, "input": {}, "output": out}

    node_ids = [0, 1, 255, 1 << 255, (1 << 256) - 1, int.from_bytes(hashlib.sha256(b"node").digest(), "big")]
    subnet_configs = [
        ("preset", {}),
        ("period_1", {"EPOCHS_PER_SUBNET_SUBSCRIPTION": 1}),
        ("period_7", {"EPOCHS_PER_SUBNET_SUBSCRIPTION": 7}),
        ("period_max", {"EPOCHS_PER_SUBNET_SUBSCRIPTION": U64}),
        ("period_0", {"EPOCHS_PER_SUBNET_SUBSCRIPTION": 0}),
        ("extra_3", {"ATTESTATION_SUBNET_EXTRA_BITS": 3, "SUBNETS_PER_NODE": 3}),
        ("extra_58", {"ATTESTATION_SUBNET_EXTRA_BITS": 58}),
        ("nodes_0", {"SUBNETS_PER_NODE": 0}),
    ]
    for cname, config in subnet_configs:
        for k, node_id in enumerate(node_ids):
            for epoch in (0, 255, 256, 100000, U64 - 300, U64):
                for index in (0, 1, U64):
                    out = run(spec, config, lambda: int(spec.compute_subscribed_subnet(spec.NodeID(node_id), spec.Epoch(epoch), index)))
                    parts = {"config": config, "input": {"node_id": node_id, "epoch": epoch, "index": index}, "output": out}
                    yield "compute_subscribed_subnet", f"{cname}_{k}_{epoch}_{index}", parts
                out = run(spec, config, lambda: [int(s) for s in spec.compute_subscribed_subnets(spec.NodeID(node_id), spec.Epoch(epoch))])
                parts = {"config": config, "input": {"node_id": node_id, "epoch": epoch}, "output": out}
                yield "compute_subscribed_subnets", f"{cname}_{k}_{epoch}", parts

    if fork in ("deneb", "electra"):
        limit = "MAX_BLOBS_PER_BLOCK" if fork == "deneb" else "MAX_BLOBS_PER_BLOCK_ELECTRA"
        for blocks, blobs in ((None, None), (0, 9), (U64 // 9, 9), (U64 // 9 + 1, 9)):
            config = {} if blocks is None else {"MAX_REQUEST_BLOCKS_DENEB": blocks, limit: blobs}
            out = run(spec, config, lambda: int(spec.compute_max_request_blob_sidecars()))
            yield "compute_max_request_blob_sidecars", f"{blocks}_{blobs}", {"config": config, "input": {}, "output": out}
    if fork == "fulu":
        for blocks in (None, 0, U64 // spec.NUMBER_OF_COLUMNS, U64 // spec.NUMBER_OF_COLUMNS + 1):
            config = {} if blocks is None else {"MAX_REQUEST_BLOCKS_DENEB": blocks}
            out = run(spec, config, lambda: int(spec.compute_max_request_data_column_sidecars()))
            yield "compute_max_request_data_column_sidecars", f"{blocks}", {"config": config, "input": {}, "output": out}

    digests = [bytes(4), bytes.fromhex("446a7232"), bytes.fromhex("ff00a0b1")]
    for k, digest in enumerate(digests):
        for name in range(1, len(TOPICS) + 1):
            for subnet in (0, 7, 63, U64):
                string = topic_string(digest, name, subnet)
                parts = {"config": {}, "input": {"fork_digest": digest, "name": name, "subnet_id": subnet}, "output": string}
                yield "gossip_topic", f"{k}_{name}_{subnet}", parts
                if TOPICS[name - 1][1] or not subnet:
                    parse = {"fork_digest": digest, "name": name, "subnet_id": subnet}
                    yield "gossip_topic_parse", f"{k}_{name}_{subnet}", {"config": {}, "input": {"string": string}, "output": parse}
    for name in (0, len(TOPICS) + 1, U64):
        yield "gossip_topic", f"bad_name_{name}", {"config": {}, "input": {"fork_digest": bytes(4), "name": name, "subnet_id": 0}, "output": None}
    bad = [
        b"", b"/eth2/", b"/eth2/446a7232/beacon_block/ssz", b"/eth2/446a7232/beacon_block/ssz_snappy/",
        b"/eth2/446A7232/beacon_block/ssz_snappy", b"/eth2/446a723/beacon_block/ssz_snappy",
        b"/eth2/446a72320/beacon_block/ssz_snappy", b"/eth2/446a7232/beacon_blocks/ssz_snappy",
        b"/eth2/446a7232/beacon_block_1/ssz_snappy", b"/eth2/446a7232/beacon_attestation/ssz_snappy",
        b"/eth2/446a7232/beacon_attestation_/ssz_snappy", b"/eth2/446a7232/beacon_attestation_01/ssz_snappy",
        b"/eth2/446a7232/beacon_attestation_18446744073709551616/ssz_snappy",
        b"/eth2/446a7232/beacon_attestation_1a/ssz_snappy", b"/eth2/446a7232/sync_committee/ssz_snappy",
        b"/eth2/446a7232/light_client_finality_updates/ssz_snappy", b"eth2/446a7232/beacon_block/ssz_snappy",
        b"/eth2/446a7232/beacon_block/ssz_snappy\x00", b"/eth2/446a7232//ssz_snappy", b"/eth2/g46a7232/beacon_block/ssz_snappy",
    ]
    for k, string in enumerate(bad):
        yield "gossip_topic_parse", f"bad_{k}", {"config": {}, "input": {"string": string}, "output": None}

    topics = [b"", topic_string(bytes.fromhex("446a7232"), 1, 0), b"x" * 300]
    payloads = [b"", b"a", bytes(range(256)) * 40, hashlib.sha256(b"payload").digest() * 3000]
    datas = [snappy.compress(p) for p in payloads] + [b"", b"\x00", b"\xff\xff\xff\xff\xff\x01", bytes(range(1, 60))]
    for t, topic in enumerate(topics):
        for d, data in enumerate(datas):
            for size in (None, 16, 0):
                config = {} if size is None else {"MAX_PAYLOAD_SIZE": size}
                limit = spec.config.MAX_PAYLOAD_SIZE if size is None else size
                out = message_id(spec, fork, topic, data, limit)
                parts = {"config": config, "input": {"topic": topic, "data": data}, "output": out}
                yield "compute_message_id", f"{t}_{d}_{size}", parts
