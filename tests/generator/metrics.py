"""Cases of the metrics (docs/reference/metrics.md).

text_cases(beacon_metrics) yields (name, parts) for lantern_metrics_text: the values of each type as
bytes ("categories", "state", "node", "app", "process", "gossip") and the "text" they must give. The
names, HELP texts and types come from metrics.md of ethereum/beacon-metrics at the pinned commit;
the text from the rules of docs/reference/metrics.md, written here apart from the assembly.
"""

import pathlib
import random
import re
import struct

# The beacon category in its order (docs/reference/metrics.md, The beacon category): name, source,
# field (or the gossipsub kind), kind, condition.
BEACON = [
    ("libp2p_peers", "node", "peers", "u64", None),
    ("beacon_head_slot", "state", "slot", "u64", "state"),
    ("beacon_finalized_epoch", "state", "finalized_epoch", "u64", "state"),
    ("beacon_current_justified_epoch", "state", "current_justified_epoch", "u64", "state"),
    ("beacon_previous_justified_epoch", "state", "previous_justified_epoch", "u64", "state"),
    ("beacon_current_active_validators", "state", "active_validators", "u64", "state"),
    ("beacon_reorgs_total", "node", "reorgs", "u64", None),
    ("beacon_processed_deposits_total", "state", "deposit_count", "u64", "state"),
    ("beacon_data_column_sidecar_processing_requests_total", "node", "column_requests", "u64", None),
    ("beacon_data_column_sidecar_processing_successes_total", "node", "column_successes", "u64", None),
    ("beacon_data_column_sidecar_gossip_verification_seconds", "app", "gossip_verification", "default", None),
    ("beacon_data_availability_reconstructed_columns_total", "node", "reconstructed_columns", "u64", None),
    ("beacon_data_availability_reconstruction_time_seconds", "app", "reconstruction", "default", None),
    ("beacon_data_column_sidecar_computation_seconds", "app", "computation", "default", None),
    ("beacon_kzg_verification_data_column_batch_seconds", "app", "kzg_batch", "kzg", None),
    ("beacon_custody_groups", "node", "custody_groups", "u64", "fulu"),
    ("beacon_current_validators", "state", "current_validators", "status", "state"),
    ("beacon_previous_validators", "state", "previous_validators", "status", "state"),
    ("beacon_current_live_validators", "state", "current_live", "u64", "state"),
    ("beacon_previous_live_validators", "state", "previous_live", "u64", "state"),
    ("beacon_pending_deposits", "state", "pending_deposits", "u64", "electra"),
    ("beacon_pending_partial_withdrawals", "state", "pending_partial_withdrawals", "u64", "electra"),
    ("beacon_pending_consolidations", "state", "pending_consolidations", "u64", "electra"),
    ("beacon_pending_exits", "node", "pending_exits", "u64", None),
    ("beacon_previous_epoch_orphaned_blocks", "node", "orphaned_blocks", "u64", None),
    ("gossipsub_mesh_peers_per_main_topic", "gossip", "main", "gossip", None),
    ("beacon_attestation_delay_count", "node", "attestation_delay", "delay", None),
    ("local_validator_count", "node", "local_validators", "u64", None),
    ("beacon_head_state_finalized_root", "state", "finalized_root", "root", "state"),
    ("beacon_previous_justified_root", "state", "previous_justified_root", "root", "state"),
    ("beacon_aggregates_received_total", "node", "aggregates_received", "u64", None),
    ("beacon_block_delay_count", "node", "block_delay", "delay", None),
    ("beacon_attestor_slashing_received_total", "node", "attester_slashings_received", "u64", None),
    ("beacon_block_proposed_total", "node", "blocks_proposed", "u64", None),
    ("beacon_attestations_published_total", "node", "attestations_published", "u64", None),
    ("beacon_processor_gossip_block_imported_total", "node", "gossip_blocks_imported", "u64", None),
    ("libp2p_pubsub_validation_failure_total", "node", "validation_failures", "u64", None),
    ("beacon_head_state_root", "state", "state_root", "root", "state_root"),
    ("beacon_attestations_received_total", "node", "attestations_received", "u64", None),
    ("beacon_http_api_requests_total", "node", "api_requests", "u64", None),
    ("beacon_http_api_successes_total", "node", "api_successes", "u64", None),
    ("beacon_sync_state", "node", "sync_state", "u64", None),
    ("process_cpu_seconds_total", "process", "cpu_us", "seconds", None),
    ("process_max_fds", "process", "max_fds", "u64", "max_fds"),
    ("gossipsub_topic_msg_sent_bytes", "gossip", "sent", "gossip", None),
    ("gossipsub_mesh_peer_counts", "gossip", "mesh", "gossip", None),
]

BOUNDS = {
    "default": ["0.005", "0.01", "0.025", "0.05", "0.1", "0.25", "0.5", "1", "2.5", "5", "10"],
    "kzg": ["0.002", "0.004", "0.008", "0.016", "0.032", "0.064", "0.128", "0.256", "0.512", "1.024"],
    "delay": ["0.5", "1", "2", "3", "4", "6", "8", "12", "24"],
}
STATUS = ["pending", "active", "exited", "withdrawable"]
BUCKETS = 12

STATE_FIELDS = ["present", "slot", "finalized_epoch", "current_justified_epoch", "previous_justified_epoch",
                "active_validators", "deposit_count", "finalized_root", "previous_justified_root"]
NODE_FIELDS = ["peers", "fulu", "custody_groups", "pending_exits", "local_validators", "orphaned_blocks", "sync_state",
               "head_block_id", "head_state_id"]
COUNTERS = ["reorgs", "column_requests", "column_successes", "reconstructed_columns", "aggregates_received",
            "attestations_received", "attester_slashings_received", "blocks_proposed", "attestations_published",
            "gossip_blocks_imported", "validation_failures", "api_requests", "api_successes"]


def spec_table(beacon_metrics):
    """name: (type, HELP text) from the tables of metrics.md: the Usage text without Markdown marks."""
    rows = {}
    for line in (pathlib.Path(beacon_metrics) / "metrics.md").read_text().split("\n"):
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in re.split(r"(?<!\\)\|", line)[1:-1]]
        if len(cells) < 3 or cells[0].startswith("-") or cells[0] == "Name":
            continue
        name = cells[0].strip("`").strip()
        rows.setdefault(name, (cells[1].strip().lower(), cells[2].replace("\\|", "|").replace("`", "").strip()))
    return rows


def histogram(values_us, bounds):
    """A Histogram value: count, sum_us, the buckets."""
    lim = [round(float(b) * 1000000) for b in bounds]
    buckets = [0] * BUCKETS
    for v in values_us:
        i = next((k for k, b in enumerate(lim) if v <= b), len(lim))
        buckets[i] += 1
    return {"count": len(values_us), "sum_us": sum(values_us), "buckets": buckets}


def hist_bytes(h):
    return struct.pack("<QQ", h["count"], h["sum_us"]) + b"".join(struct.pack("<Q", b) for b in h["buckets"])


def root_number(root):
    return int.from_bytes(root[24:32], "little", signed=True)


def state_bytes(s):
    out = struct.pack("<7Q", *(s[k] for k in STATE_FIELDS[:7]))
    out += struct.pack("<2q", s["finalized_root"], s["previous_justified_root"])
    out += struct.pack("<4Q", *s["current_validators"]) + struct.pack("<4Q", *s["previous_validators"])
    out += struct.pack("<6Q", s["current_live"], s["previous_live"], s["electra"], s["pending_deposits"],
                       s["pending_partial_withdrawals"], s["pending_consolidations"])
    out += struct.pack("<Qq", s["state_root_present"], s["state_root"])
    assert len(out) == 200
    return out


def node_bytes(n):
    out = struct.pack("<9Q", *(n[k] for k in NODE_FIELDS))
    out += b"".join(struct.pack("<Q", n[k]) for k in COUNTERS)
    out += hist_bytes(n["attestation_delay"]) + hist_bytes(n["block_delay"])
    assert len(out) == 400
    return out


def app_bytes(a):
    out = b"".join(hist_bytes(a[k]) for k in ("gossip_verification", "reconstruction", "computation", "kzg_batch"))
    assert len(out) == 448
    return out


def gossip_bytes(topics):
    """A MetricsGossip: size, the part's offset and count, then the GossipTopic entries."""
    entries = b""
    for t in topics:
        name = t["name"].encode()
        entries += struct.pack("<Q", len(name)) + name.ljust(64, b"\0")
        entries += struct.pack("<5Q", t["subnet"], t["mesh"], t["mesh_partial"], t["sent"], t["sent_partial"])
    return struct.pack("<3Q", 24 + len(entries), 24, len(topics)) + entries


def seconds(us):
    return f"{us // 1000000}.{us % 1000000:06d}"


def text(table, categories, s, n, a, p, topics):
    """The text of docs/reference/metrics.md, lantern_metrics_text."""
    if not categories & 1:
        return ""
    out = []
    for name, src, field, kind, cond in BEACON:
        if cond == "state" and not s["present"]:
            continue
        if cond == "electra" and not (s["present"] and s["electra"]):
            continue
        if cond == "fulu" and not n["fulu"]:
            continue
        if cond == "state_root" and not (s["present"] and s["state_root_present"]):
            continue
        if cond == "max_fds" and not p["max_fds"]:
            continue
        if src == "gossip" and not [t for t in topics if field != "main" or not t["subnet"]]:
            continue
        mtype, help_text = table[name]
        out.append(f"# HELP {name} {help_text}\n# TYPE {name} {mtype}\n")
        value = {"state": s, "node": n, "app": a, "process": p}.get(src, {}).get(field)
        if kind == "u64":
            out.append(f"{name} {value}\n")
        elif kind == "root":
            out.append(f"{name} {value}\n")
        elif kind == "seconds":
            out.append(f"{name} {seconds(value)}\n")
        elif kind == "status":
            for st, v in zip(STATUS, value):
                out.append(f'{name}{{status="{st}"}} {v}\n')
        elif kind in BOUNDS:
            total = 0
            for b, c in zip(BOUNDS[kind], value["buckets"]):
                total += c
                out.append(f'{name}_bucket{{le="{b}"}} {total}\n')
            out.append(f'{name}_bucket{{le="+Inf"}} {value["count"]}\n')
            out.append(f"{name}_sum {seconds(value['sum_us'])}\n{name}_count {value['count']}\n")
        elif field == "main":
            for t in topics:
                if not t["subnet"]:
                    out.append(f'{name}{{topic="{t["name"]}"}} {t["mesh"]}\n')
        elif field == "sent":
            for t in topics:
                out.append(f'{name}{{topic="{t["name"]}",partial="false"}} {t["sent"]}\n')
                out.append(f'{name}{{topic="{t["name"]}",partial="true"}} {t["sent_partial"]}\n')
        else:
            for t in topics:
                out.append(f'{name}{{topic="{t["name"]}",supports_partial="false"}} {t["mesh"] - t["mesh_partial"]}\n')
                out.append(f'{name}{{topic="{t["name"]}",supports_partial="true"}} {t["mesh_partial"]}\n')
    return "".join(out)


def values(rng, present, electra, fulu, state_root, max_fds, ntopics):
    """Values of each type, random but fixed by rng."""
    big = lambda: rng.choice([0, 1, 9, 10, 255, 1 << 32, (1 << 64) - 1, rng.getrandbits(64)])
    root = lambda: root_number(rng.randbytes(32))
    s = {"present": present, "slot": big(), "finalized_epoch": big(), "current_justified_epoch": big(),
         "previous_justified_epoch": big(), "active_validators": big(), "deposit_count": big(),
         "finalized_root": rng.choice([root(), -(1 << 63), -1, 0, (1 << 63) - 1]), "previous_justified_root": root(),
         "current_validators": [big() for _ in range(4)], "previous_validators": [big() for _ in range(4)],
         "current_live": big(), "previous_live": big(), "electra": electra, "pending_deposits": big(),
         "pending_partial_withdrawals": big(), "pending_consolidations": big(), "state_root_present": state_root,
         "state_root": root()}
    delay_us = lambda k: [rng.choice([0, 1, 499999, 500000, 500001, 3000000, 24000000, 24000001, rng.randrange(30000000)])
                          for _ in range(k)]
    run_us = lambda k: [rng.choice([0, 5000, 5001, 10000000, 10000001, rng.randrange(2000), rng.randrange(20000000)])
                        for _ in range(k)]
    n = {"peers": rng.randrange(100), "fulu": fulu, "custody_groups": rng.randrange(129),
         "pending_exits": rng.randrange(5000), "local_validators": rng.randrange(5000),
         "orphaned_blocks": rng.randrange(40), "sync_state": rng.randrange(3), "head_block_id": big(),
         "head_state_id": big(), "attestation_delay": histogram(delay_us(rng.randrange(20)), BOUNDS["delay"]),
         "block_delay": histogram(delay_us(rng.randrange(20)), BOUNDS["delay"])}
    for k in COUNTERS:
        n[k] = big()
    a = {"gossip_verification": histogram(run_us(rng.randrange(30)), BOUNDS["default"]),
         "reconstruction": histogram(run_us(rng.randrange(5)), BOUNDS["default"]),
         "computation": histogram(run_us(rng.randrange(5)), BOUNDS["default"]),
         "kzg_batch": histogram([rng.choice([1999, 2000, 2001, 1024000, 1024001, rng.randrange(3000000)])
                                 for _ in range(rng.randrange(30))], BOUNDS["kzg"])}
    p = {"cpu_us": big() >> 4, "max_fds": max_fds}
    names = ["beacon_block", "beacon_aggregate_and_proof", "voluntary_exit", "beacon_attestation_7",
             "data_column_sidecar_127", "sync_committee_3", "bls_to_execution_change"]
    topics = []
    for i in range(ntopics):
        base = names[i % len(names)]
        mesh = rng.randrange(13)
        topics.append({"name": f"/eth2/{rng.getrandbits(32):08x}/{base}/ssz_snappy", "subnet": int(base[-1].isdigit()),
                       "mesh": mesh, "mesh_partial": rng.randrange(mesh + 1), "sent": big(), "sent_partial": big()})
    return s, n, a, p, topics


def text_cases(beacon_metrics):
    table = spec_table(beacon_metrics)
    for name, _, _, _, _ in BEACON:
        assert name in table, name
    rng = random.Random(7805)
    specs = [
        ("no_category", 0, 1, 1, 1, 1, 1024, 3),
        ("every_metric", 1, 1, 1, 1, 1, 1048576, 7),
        ("no_state_no_fulu_no_root_no_fds_no_topics", 1, 0, 0, 0, 0, 0, 0),
        ("before_electra", 1, 1, 0, 1, 1, 4096, 2),
        ("subnet_topics_only", 1, 1, 1, 0, 0, 65536, 0),
        ("many_topics", 1, 1, 1, 1, 1, 1024, 60),
    ]
    for name, categories, present, electra, fulu, state_root, max_fds, ntopics in specs:
        s, n, a, p, topics = values(rng, present, electra, fulu, state_root, max_fds, ntopics)
        if name == "subnet_topics_only":
            topics = [{"name": f"/eth2/01020304/beacon_attestation_{k}/ssz_snappy", "subnet": 1, "mesh": k, "mesh_partial": 0,
                       "sent": k * 1000, "sent_partial": 0} for k in range(3)]
        yield name, {"categories": categories, "state": state_bytes(s), "node": node_bytes(n), "app": app_bytes(a),
                     "process": struct.pack("<2Q", p["cpu_us"], p["max_fds"]), "gossip": gossip_bytes(topics),
                     "text": text(table, categories, s, n, a, p, topics).encode()}
