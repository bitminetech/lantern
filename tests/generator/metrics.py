"""The metrics of lantern (docs/reference/metrics.md): one list of the categories, the structs that hold
the values, the label tables, the histogram bounds and the metric families.

From the lists:
- `python3 tests/generator/metrics.py include BEACON_METRICS` writes include/metrics.inc (the bits, the
  layouts, the constants) and include/metrics_table.inc (the texts and the table of families); the
  beacon families take their HELP text and type from metrics.md of ethereum/beacon-metrics at the
  pinned commit (BEACON_METRICS is its clone).
- text_cases(beacon_metrics) yields (name, parts) for lantern_metrics_text: "categories", each source's
  bytes, and the "text" that text() gives, the rules of docs/reference/metrics.md written here apart
  from the assembly.
"""

import pathlib
import random
import re
import struct
import sys

# ---------------------------------------------------------------- Categories

# (category, sub categories); a category with no sub category is one bit.
CATEGORIES = [
    ("beacon", []),
    ("network", ["peer", "discovery", "transport", "gossip", "reqresp"]),
    ("processing", ["block", "epoch", "state", "forkchoice", "availability", "gossip", "engine", "builder",
                    "lightclient", "history", "validator"]),
    ("node", ["resource", "sync", "health", "pool", "log", "api", "storage"]),
]
CATEGORY_FIRST_BIT = {"beacon": 0, "network": 1, "processing": 8, "node": 24}


def category_bits():
    """name: bit, for "beacon" and each "category.sub"."""
    bits = {}
    for cat, subs in CATEGORIES:
        if not subs:
            bits[cat] = CATEGORY_FIRST_BIT[cat]
        for i, sub in enumerate(subs):
            bits[f"{cat}.{sub}"] = CATEGORY_FIRST_BIT[cat] + i
    return bits


BITS = category_bits()


def category_mask(name):
    """The bits of a flag item: a category (all its sub categories) or category.sub."""
    if name in BITS:
        return 1 << BITS[name]
    return sum(1 << b for k, b in BITS.items() if k.startswith(name + "."))


# ---------------------------------------------------------------- Histograms

BUCKETS = 12  # entries of a Histogram: one for each bound, then one above the last
# name: (unit, bound texts in seconds). "us": the bounds are microseconds, the values microseconds.
# "ticks": the values are CPU counter ticks, and the bounds the Profile's ticks of these times.
BOUNDS = {
    "default": ("us", ["0.005", "0.01", "0.025", "0.05", "0.1", "0.25", "0.5", "1", "2.5", "5", "10"]),
    "kzg": ("us", ["0.002", "0.004", "0.008", "0.016", "0.032", "0.064", "0.128", "0.256", "0.512", "1.024"]),
    "delay": ("us", ["0.5", "1", "2", "3", "4", "6", "8", "12", "24"]),
    "ticks": ("ticks", ["0.000001", "0.000004", "0.000016", "0.000064", "0.000256", "0.001", "0.004", "0.016",
                        "0.064", "0.256", "1"]),
}
BOUND_ORDER = ["default", "kzg", "delay", "ticks"]
PROFILE_BOUNDS = len(BOUNDS["ticks"][1])

# ---------------------------------------------------------------- Labels

# id: (label name, values)
LABELS = {
    "status": ("status", ["pending", "active", "exited", "withdrawable"]),
}

# ---------------------------------------------------------------- Structs

# struct: [(field, type, count)]; types u64, i64, hist (a Histogram), bytes16. Every field 8-aligned.
STRUCTS = {
    "MetricsState": [
        ("present", "u64", 1), ("slot", "u64", 1), ("finalized_epoch", "u64", 1),
        ("current_justified_epoch", "u64", 1), ("previous_justified_epoch", "u64", 1),
        ("active_validators", "u64", 1), ("deposit_count", "u64", 1), ("finalized_root", "i64", 1),
        ("previous_justified_root", "i64", 1), ("current_validators", "u64", 4), ("previous_validators", "u64", 4),
        ("current_live", "u64", 1), ("previous_live", "u64", 1), ("electra", "u64", 1),
        ("pending_deposits", "u64", 1), ("pending_partial_withdrawals", "u64", 1),
        ("pending_consolidations", "u64", 1), ("state_root_present", "u64", 1), ("state_root", "i64", 1),
    ],
    "MetricsNode": [
        ("peers", "u64", 1), ("fulu", "u64", 1), ("custody_groups", "u64", 1), ("pending_exits", "u64", 1),
        ("local_validators", "u64", 1), ("orphaned_blocks", "u64", 1), ("sync_state", "u64", 1),
        ("head_block_id", "u64", 1), ("head_state_id", "u64", 1),
    ],
    "NodeMetrics": [
        ("reorgs", "u64", 1), ("column_requests", "u64", 1), ("column_successes", "u64", 1),
        ("reconstructed_columns", "u64", 1), ("aggregates_received", "u64", 1),
        ("attestations_received", "u64", 1), ("attester_slashings_received", "u64", 1),
        ("blocks_proposed", "u64", 1), ("attestations_published", "u64", 1), ("gossip_blocks_imported", "u64", 1),
        ("validation_failures", "u64", 1), ("api_requests", "u64", 1), ("api_successes", "u64", 1),
        ("attestation_delay", "hist", 1), ("block_delay", "hist", 1),
    ],
    "AppMetrics": [
        ("gossip_verification", "hist", 1), ("reconstruction", "hist", 1), ("computation", "hist", 1),
        ("kzg_batch", "hist", 1),
    ],
    "MetricsProcess": [("cpu_us", "u64", 1), ("max_fds", "u64", 1)],
    "Profile": [("ticks_per_second", "u64", 1), ("bounds", "u64", PROFILE_BOUNDS)],
}
TYPE_SIZE = {"u64": 8, "i64": 8, "hist": 16 + 8 * BUCKETS, "bytes16": 16}
# The source of each family: its index is METRIC_SRC_*, its place in MetricsSources.
SOURCES = ["state", "node", "counters", "app", "process", "gossip", "profile"]
SOURCE_STRUCT = {"state": "MetricsState", "node": "MetricsNode", "counters": "NodeMetrics", "app": "AppMetrics",
                 "process": "MetricsProcess", "profile": "Profile"}


def layout(name):
    """field: (offset, type, count), and the size."""
    out, at = {}, 0
    for field, typ, count in STRUCTS[name]:
        out[field] = (at, typ, count)
        at += TYPE_SIZE[typ] * count
    return out, at


# ---------------------------------------------------------------- Families

# Kinds: u64, root (signed), seconds (microseconds as seconds), array (u64 by labels), hist (a Histogram
# of a bound set), array_hist (Histograms by labels), gossip_main, gossip_sent, gossip_mesh (asm-libp2p's
# gossipsub topics).
KINDS = ["u64", "root", "seconds", "array", "hist", "array_hist", "gossip_main", "gossip_sent", "gossip_mesh"]
CONDS = [None, "state", "electra", "fulu", "state_root", "max_fds", "profile"]


def F(name, mtype, cat, src, field, kind, labels=(), bounds=None, cond=None, help=None):
    return {"name": name, "type": mtype, "cat": cat, "src": src, "field": field, "kind": kind,
            "labels": list(labels), "bounds": bounds, "cond": cond, "help": help}


# The beacon category (ethereum/beacon-metrics), in its order; type and HELP from metrics.md.
BEACON = [
    F("libp2p_peers", None, "beacon", "node", "peers", "u64"),
    F("beacon_head_slot", None, "beacon", "state", "slot", "u64", cond="state"),
    F("beacon_finalized_epoch", None, "beacon", "state", "finalized_epoch", "u64", cond="state"),
    F("beacon_current_justified_epoch", None, "beacon", "state", "current_justified_epoch", "u64", cond="state"),
    F("beacon_previous_justified_epoch", None, "beacon", "state", "previous_justified_epoch", "u64", cond="state"),
    F("beacon_current_active_validators", None, "beacon", "state", "active_validators", "u64", cond="state"),
    F("beacon_reorgs_total", None, "beacon", "counters", "reorgs", "u64"),
    F("beacon_processed_deposits_total", None, "beacon", "state", "deposit_count", "u64", cond="state"),
    F("beacon_data_column_sidecar_processing_requests_total", None, "beacon", "counters", "column_requests", "u64"),
    F("beacon_data_column_sidecar_processing_successes_total", None, "beacon", "counters", "column_successes", "u64"),
    F("beacon_data_column_sidecar_gossip_verification_seconds", None, "beacon", "app", "gossip_verification", "hist",
      bounds="default"),
    F("beacon_data_availability_reconstructed_columns_total", None, "beacon", "counters", "reconstructed_columns",
      "u64"),
    F("beacon_data_availability_reconstruction_time_seconds", None, "beacon", "app", "reconstruction", "hist",
      bounds="default"),
    F("beacon_data_column_sidecar_computation_seconds", None, "beacon", "app", "computation", "hist", bounds="default"),
    F("beacon_kzg_verification_data_column_batch_seconds", None, "beacon", "app", "kzg_batch", "hist", bounds="kzg"),
    F("beacon_custody_groups", None, "beacon", "node", "custody_groups", "u64", cond="fulu"),
    F("beacon_current_validators", None, "beacon", "state", "current_validators", "array", labels=["status"],
      cond="state"),
    F("beacon_previous_validators", None, "beacon", "state", "previous_validators", "array", labels=["status"],
      cond="state"),
    F("beacon_current_live_validators", None, "beacon", "state", "current_live", "u64", cond="state"),
    F("beacon_previous_live_validators", None, "beacon", "state", "previous_live", "u64", cond="state"),
    F("beacon_pending_deposits", None, "beacon", "state", "pending_deposits", "u64", cond="electra"),
    F("beacon_pending_partial_withdrawals", None, "beacon", "state", "pending_partial_withdrawals", "u64",
      cond="electra"),
    F("beacon_pending_consolidations", None, "beacon", "state", "pending_consolidations", "u64", cond="electra"),
    F("beacon_pending_exits", None, "beacon", "node", "pending_exits", "u64"),
    F("beacon_previous_epoch_orphaned_blocks", None, "beacon", "node", "orphaned_blocks", "u64"),
    F("gossipsub_mesh_peers_per_main_topic", None, "beacon", "gossip", None, "gossip_main"),
    F("beacon_attestation_delay_count", None, "beacon", "counters", "attestation_delay", "hist", bounds="delay"),
    F("local_validator_count", None, "beacon", "node", "local_validators", "u64"),
    F("beacon_head_state_finalized_root", None, "beacon", "state", "finalized_root", "root", cond="state"),
    F("beacon_previous_justified_root", None, "beacon", "state", "previous_justified_root", "root", cond="state"),
    F("beacon_aggregates_received_total", None, "beacon", "counters", "aggregates_received", "u64"),
    F("beacon_block_delay_count", None, "beacon", "counters", "block_delay", "hist", bounds="delay"),
    F("beacon_attestor_slashing_received_total", None, "beacon", "counters", "attester_slashings_received", "u64"),
    F("beacon_block_proposed_total", None, "beacon", "counters", "blocks_proposed", "u64"),
    F("beacon_attestations_published_total", None, "beacon", "counters", "attestations_published", "u64"),
    F("beacon_processor_gossip_block_imported_total", None, "beacon", "counters", "gossip_blocks_imported", "u64"),
    F("libp2p_pubsub_validation_failure_total", None, "beacon", "counters", "validation_failures", "u64"),
    F("beacon_head_state_root", None, "beacon", "state", "state_root", "root", cond="state_root"),
    F("beacon_attestations_received_total", None, "beacon", "counters", "attestations_received", "u64"),
    F("beacon_http_api_requests_total", None, "beacon", "counters", "api_requests", "u64"),
    F("beacon_http_api_successes_total", None, "beacon", "counters", "api_successes", "u64"),
    F("beacon_sync_state", None, "beacon", "node", "sync_state", "u64"),
    F("process_cpu_seconds_total", None, "beacon", "process", "cpu_us", "seconds"),
    F("process_max_fds", None, "beacon", "process", "max_fds", "u64", cond="max_fds"),
    F("gossipsub_topic_msg_sent_bytes", None, "beacon", "gossip", None, "gossip_sent"),
    F("gossipsub_mesh_peer_counts", None, "beacon", "gossip", None, "gossip_mesh"),
]

FAMILIES = BEACON


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


def families(beacon_metrics):
    """FAMILIES with each type and HELP text filled in."""
    table = spec_table(beacon_metrics)
    out = []
    for f in FAMILIES:
        f = dict(f)
        if f["cat"] == "beacon":
            assert f["name"] in table, f["name"]
            f["type"], f["help"] = table[f["name"]]
        assert f["type"] in ("gauge", "counter", "histogram") and f["help"], f["name"]
        out.append(f)
    return out


# ---------------------------------------------------------------- The text

def seconds(us):
    return f"{us // 1000000}.{us % 1000000:06d}"


def label_combos(f):
    """The label pairs of each element of an array family, in element order."""
    combos = [[]]
    for lid in f["labels"]:
        name, values = LABELS[lid]
        combos = [c + [(name, v)] for c in combos for v in values]
    return combos


def braces(pairs):
    return "{" + ",".join(f'{k}="{v}"' for k, v in pairs) + "}" if pairs else ""


def hist_lines(name, pairs, h, bounds, tps):
    unit, texts = BOUNDS[bounds]
    out, total = [], 0
    for b, c in zip(texts, h["buckets"]):
        total += c
        out.append(f"{name}_bucket{braces(pairs + [('le', b)])} {total}\n")
    out.append(f"{name}_bucket{braces(pairs + [('le', '+Inf')])} {h['count']}\n")
    us = h["sum"] if unit == "us" else (h["sum"] * 1000000 // tps if tps else 0)
    out.append(f"{name}_sum{braces(pairs)} {seconds(us)}\n{name}_count{braces(pairs)} {h['count']}\n")
    return out


def text(fams, categories, src, topics):
    """The text of docs/reference/metrics.md, lantern_metrics_text: src maps each source to its values
    (dicts by field, or None for a source not given)."""
    out = []
    s, n, p, prof = src["state"], src["node"], src["process"], src["profile"]
    for f in fams:
        if not categories >> BITS[f["cat"]] & 1:
            continue
        if f["src"] != "gossip" and src[f["src"]] is None:
            continue
        c = f["cond"]
        if c == "state" and not (s and s["present"]):
            continue
        if c == "electra" and not (s and s["present"] and s["electra"]):
            continue
        if c == "fulu" and not (n and n["fulu"]):
            continue
        if c == "state_root" and not (s and s["present"] and s["state_root_present"]):
            continue
        if c == "max_fds" and not (p and p["max_fds"]):
            continue
        if c == "profile" and not (prof and prof["ticks_per_second"]):
            continue
        name, kind = f["name"], f["kind"]
        if kind.startswith("gossip") and not [t for t in topics if kind != "gossip_main" or not t["subnet"]]:
            continue
        out.append(f"# HELP {name} {f['help']}\n# TYPE {name} {f['type']}\n")
        v = src[f["src"]][f["field"]] if f["field"] else None
        tps = prof["ticks_per_second"] if prof else 0
        if kind == "u64" or kind == "root":
            out.append(f"{name} {v}\n")
        elif kind == "seconds":
            out.append(f"{name} {seconds(v)}\n")
        elif kind == "array":
            for pairs, x in zip(label_combos(f), v):
                out.append(f"{name}{braces(pairs)} {x}\n")
        elif kind == "hist":
            out += hist_lines(name, [], v, f["bounds"], tps)
        elif kind == "array_hist":
            for pairs, h in zip(label_combos(f), v):
                out += hist_lines(name, pairs, h, f["bounds"], tps)
        elif kind == "gossip_main":
            for t in topics:
                if not t["subnet"]:
                    out.append(f'{name}{{topic="{t["name"]}"}} {t["mesh"]}\n')
        elif kind == "gossip_sent":
            for t in topics:
                out.append(f'{name}{{topic="{t["name"]}",partial="false"}} {t["sent"]}\n')
                out.append(f'{name}{{topic="{t["name"]}",partial="true"}} {t["sent_partial"]}\n')
        else:
            for t in topics:
                out.append(f'{name}{{topic="{t["name"]}",supports_partial="false"}} {t["mesh"] - t["mesh_partial"]}\n')
                out.append(f'{name}{{topic="{t["name"]}",supports_partial="true"}} {t["mesh_partial"]}\n')
    return "".join(out)


# ---------------------------------------------------------------- Bytes of the sources

def hist_bytes(h):
    return struct.pack("<QQ", h["count"], h["sum"]) + b"".join(struct.pack("<Q", b) for b in h["buckets"])


def struct_bytes(name, values):
    lay, size = layout(name)
    out = b""
    for field, typ, count in STRUCTS[name]:
        v = values[field]
        vs = v if count > 1 else [v]
        for x in vs:
            if typ == "u64":
                out += struct.pack("<Q", x)
            elif typ == "i64":
                out += struct.pack("<q", x)
            elif typ == "hist":
                out += hist_bytes(x)
            else:
                out += bytes(x)
    assert len(out) == size, name
    return out


def gossip_bytes(topics):
    """A MetricsGossip: size, the part's offset and count, then the GossipTopic entries."""
    entries = b""
    for t in topics:
        name = t["name"].encode()
        entries += struct.pack("<Q", len(name)) + name.ljust(64, b"\0")
        entries += struct.pack("<5Q", t["subnet"], t["mesh"], t["mesh_partial"], t["sent"], t["sent_partial"])
    return struct.pack("<3Q", 24 + len(entries), 24, len(topics)) + entries


def histogram(rng, unit, bounds, k, tps=0):
    """A Histogram of k values: microseconds, or ticks of the Profile's bounds."""
    if unit == "us":
        lim = [round(float(b) * 1000000) for b in BOUNDS[bounds][1]]
    else:
        lim = profile_bounds(tps)
    vals = [rng.choice([0, 1, lim[0], lim[0] + 1, lim[-1], lim[-1] + 1, rng.randrange(lim[-1] * 2 + 2)]) for _ in range(k)]
    buckets = [0] * BUCKETS
    for x in vals:
        buckets[next((i for i, b in enumerate(lim) if x <= b), len(lim))] += 1
    return {"count": len(vals), "sum": sum(vals), "buckets": buckets}


def profile_bounds(tps):
    """The tick bounds the app writes into the Profile: each bound's seconds times the tick rate."""
    return [round(float(b) * tps) for b in BOUNDS["ticks"][1]]


def values(rng, name, fams, conds, tps):
    """Random values of a struct, with the condition fields of conds; histograms of the bounds their
    families use."""
    big = lambda: rng.choice([0, 1, 9, 10, 255, 1 << 32, (1 << 64) - 1, rng.getrandbits(64)])
    bounds_of = {f["field"]: f["bounds"] for f in fams if f["src"] != "gossip" and SOURCE_STRUCT[f["src"]] == name}
    out = {}
    for field, typ, count in STRUCTS[name]:
        def one():
            if typ == "u64":
                return big()
            if typ == "i64":
                return rng.choice([-(1 << 63), -1, 0, (1 << 63) - 1, int.from_bytes(rng.randbytes(8), "little", signed=True)])
            if typ == "hist":
                b = bounds_of.get(field, "default")
                return histogram(rng, BOUNDS[b][0], b, rng.randrange(30), tps)
            return list(rng.randbytes(16))
        out[field] = [one() for _ in range(count)] if count > 1 else one()
    for k, v in conds.items():
        if k in out:
            out[k] = v
    return out


def text_cases(beacon_metrics):
    fams = families(beacon_metrics)
    rng = random.Random(7805)
    all_bits = sum(1 << b for b in BITS.values())
    specs = [  # name, categories, state present, electra, fulu, state_root, max_fds, topics, sources left out
        ("no_category", 0, 1, 1, 1, 1, 1024, 3, ()),
        ("every_metric", all_bits, 1, 1, 1, 1, 1048576, 7, ()),
        ("beacon_only", category_mask("beacon"), 1, 1, 1, 1, 4096, 5, ()),
        ("no_state_no_fulu_no_root_no_fds_no_topics", all_bits, 0, 0, 0, 0, 0, 0, ()),
        ("before_electra", all_bits, 1, 0, 1, 1, 4096, 2, ()),
        ("subnet_topics_only", all_bits, 1, 1, 0, 0, 65536, 0, ()),
        ("many_topics", all_bits, 1, 1, 1, 1, 1024, 60, ()),
        ("no_state_source", all_bits, 1, 1, 1, 1, 1024, 3, ("state",)),
        ("no_app_no_profile", all_bits, 1, 1, 1, 1, 1024, 3, ("app", "profile")),
    ]
    for name, cats, present, electra, fulu, state_root, max_fds, ntopics, left_out in specs:
        tps = rng.choice([1000000000, 2399999999, 24000000])
        src = {
            "state": values(rng, "MetricsState", fams, {"present": present, "electra": electra,
                                                        "state_root_present": state_root}, tps),
            "node": values(rng, "MetricsNode", fams, {"fulu": fulu}, tps),
            "counters": values(rng, "NodeMetrics", fams, {}, tps),
            "app": values(rng, "AppMetrics", fams, {}, tps),
            "process": values(rng, "MetricsProcess", fams, {"max_fds": max_fds}, tps),
            "profile": values(rng, "Profile", fams, {"ticks_per_second": tps, "bounds": profile_bounds(tps)}, tps),
        }
        for k in left_out:
            src[k] = None
        names = ["beacon_block", "beacon_aggregate_and_proof", "voluntary_exit", "beacon_attestation_7",
                 "data_column_sidecar_127", "sync_committee_3", "bls_to_execution_change"]
        topics = []
        for i in range(ntopics):
            base = names[i % len(names)]
            mesh = rng.randrange(13)
            topics.append({"name": f"/eth2/{rng.getrandbits(32):08x}/{base}/ssz_snappy", "subnet": int(base[-1].isdigit()),
                           "mesh": mesh, "mesh_partial": rng.randrange(mesh + 1), "sent": rng.getrandbits(64),
                           "sent_partial": rng.getrandbits(64)})
        if name == "subnet_topics_only":
            topics = [{"name": f"/eth2/01020304/beacon_attestation_{k}/ssz_snappy", "subnet": 1, "mesh": k,
                       "mesh_partial": 0, "sent": k * 1000, "sent_partial": 0} for k in range(3)]
        parts = {"categories": cats}
        for k in SOURCES:
            if k == "gossip":
                parts[k] = gossip_bytes(topics)
            elif src[k] is None:
                parts[k] = b""
            else:
                parts[k] = struct_bytes(SOURCE_STRUCT[k], src[k])
        parts["text"] = text(fams, cats, src, topics).encode()
        yield name, parts


# ---------------------------------------------------------------- The include files

def asm_string(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def write_metrics_inc(path):
    out = ["/*",
           " * Metrics (docs/reference/metrics.md): the category bits, the layouts of the values and the",
           " * constants of the table. Written by tests/generator/metrics.py from its lists; not by hand.",
           " */"]
    for name, bit in BITS.items():
        out.append(f".set METRIC_BIT_{name.replace('.', '_').upper()}, {bit}")
    for cat, subs in CATEGORIES:
        out.append(f".set METRICS_{cat.upper()}, {category_mask(cat)}")
    out.append(f".set METRICS_ALL, {sum(1 << b for b in BITS.values())}")
    out.append(f".set HISTOGRAM_BUCKETS, {BUCKETS}")
    out += [".set Histogram_count, 0", ".set Histogram_sum, 8", ".set Histogram_buckets, 16",
            f".set Histogram__mem, {TYPE_SIZE['hist']}", f".set PROFILE_BOUNDS, {PROFILE_BOUNDS}"]
    for s in STRUCTS:
        lay, size = layout(s)
        for field, (off, typ, count) in lay.items():
            out.append(f".set {s}_{field}, {off}")
        out.append(f".set {s}__mem, {size}")
    out.append("/* MetricsSources: the address of each source, by METRIC_SRC_*; 0 for a source not given */")
    for i, k in enumerate(SOURCES):
        out.append(f".set MetricsSources_{k}, {8 * i}")
        out.append(f".set METRIC_SRC_{k.upper()}, {i}")
    out.append(f".set MetricsSources__mem, {8 * len(SOURCES)}")
    out += [".set MetricsGossip_topics, 8", ".set MetricsGossip__fixed, 24", ".set GossipTopic_name_length, 0",
            ".set GossipTopic_name, 8", ".set GOSSIP_TOPIC_NAME_MAX, 64", ".set GossipTopic_subnet, 72",
            ".set GossipTopic_mesh_peers, 80", ".set GossipTopic_mesh_partial_peers, 88",
            ".set GossipTopic_sent_bytes, 96", ".set GossipTopic_sent_partial_bytes, 104", ".set GossipTopic__mem, 112"]
    out += ["/* An entry of the table (include/metrics_table.inc): text offsets from metrics_texts, and fields */",
            ".set MetricEntry_name, 0", ".set MetricEntry_name_len, 4", ".set MetricEntry_help, 8",
            ".set MetricEntry_help_len, 12", ".set MetricEntry_type, 16", ".set MetricEntry_source, 20",
            ".set MetricEntry_offset, 24", ".set MetricEntry_kind, 28", ".set MetricEntry_cond, 30",
            ".set MetricEntry_bit, 32", ".set MetricEntry_label1, 36", ".set MetricEntry_label2, 38",
            ".set MetricEntry_bounds, 40", ".set MetricEntry_count, 44", ".set MetricEntry__mem, 48",
            "/* A label table (metrics_labels): its name, its values from metrics_label_values */",
            ".set MetricLabel_name, 0", ".set MetricLabel_name_len, 4", ".set MetricLabel_count, 8",
            ".set MetricLabel_first, 12", ".set MetricLabel__mem, 16",
            "/* A bound set (metrics_bounds): its unit and bounds from metrics_bound_values */",
            ".set MetricBounds_count, 0", ".set MetricBounds_unit, 4", ".set MetricBounds_first, 8",
            ".set MetricBounds__mem, 16", ".set MetricBound_value, 0", ".set MetricBound_text, 8",
            ".set MetricBound_text_len, 12", ".set MetricBound__mem, 16",
            ".set METRIC_UNIT_US, 0", ".set METRIC_UNIT_TICKS, 1",
            ".set METRIC_TYPE_GAUGE, 0", ".set METRIC_TYPE_COUNTER, 1", ".set METRIC_TYPE_HISTOGRAM, 2"]
    for i, k in enumerate(KINDS):
        out.append(f".set METRIC_KIND_{k.upper()}, {i}")
    for i, c in enumerate(CONDS):
        out.append(f".set METRIC_COND_{(c or 'none').upper()}, {i}")
    for i, b in enumerate(BOUND_ORDER):
        out.append(f".set METRIC_BOUNDS_{b.upper()}, {i}")
    out.append(f".set METRIC_COUNT, {len(FAMILIES)}")
    pathlib.Path(path).write_text("\n".join(out) + "\n")


def write_table_inc(path, beacon_metrics):
    fams = families(beacon_metrics)
    texts, index = [], {}

    def text_id(s):
        if s not in index:
            index[s] = f"mt_s{len(index)}"
            texts.append((index[s], s))
        return index[s]

    label_ids = {lid: i + 1 for i, lid in enumerate(LABELS)}
    out = ["/*",
           " * The metric table (docs/reference/metrics.md), in RODATA: the texts, the label tables, the bound",
           " * sets and one entry for each family. Written by tests/generator/metrics.py from its lists; the",
           " * beacon families' HELP texts are the Usage texts of ethereum/beacon-metrics 0af554b. The same on",
           " * every ISA.",
           " */"]
    rows = []
    for f in fams:
        rows.append((f, text_id(f["name"]), text_id(f["help"])))
    lab_rows = []
    value_rows = []
    for lid, (lname, vals) in LABELS.items():
        lab_rows.append((text_id(lname), len(vals), len(value_rows)))
        for v in vals:
            value_rows.append(text_id(v))
    bound_rows, bound_values = [], []
    for b in BOUND_ORDER:
        unit, bts = BOUNDS[b]
        bound_rows.append((len(bts), 0 if unit == "us" else 1, len(bound_values)))
        for i, t in enumerate(bts):
            bound_values.append((round(float(t) * 1000000) if unit == "us" else i, text_id(t)))
    fixed = {"mx_help": "# HELP ", "mx_type": "# TYPE ", "mx_gauge": " gauge\n", "mx_counter": " counter\n",
             "mx_histogram": " histogram\n", "mx_bucket": "_bucket", "mx_sum": "_sum", "mx_count": "_count",
             "mx_inf": "+Inf", "mx_le": "le", "mx_sp": " ", "mx_lf": "\n", "mx_lbrace": "{", "mx_rbrace": "}",
             "mx_comma": ",", "mx_eq": "=\"", "mx_quote": "\"", "mx_topic": "topic",
             "mx_partial": "partial", "mx_supports": "supports_partial", "mx_false": "false", "mx_true": "true"}
    out.append("metrics_texts:")
    for lab, s in texts:
        out.append(f"{lab}:")
        out.append(f'    .ascii "{asm_string(s)}"')
        out.append(f".set {lab}_len, {len(s.encode())}")
    for lab, s in fixed.items():
        out.append(f"{lab}:")
        out.append(f'    .ascii "{asm_string(s)}"')
        out.append(f".set {lab}_len, {len(s.encode())}")
    out.append("    .p2align 3")
    out.append("metrics_labels:                  /* by id from 1: name, name length, count, first value */")
    for name_id, count, first in lab_rows:
        out.append(f"    .long {name_id} - metrics_texts, {name_id}_len, {count}, {first}")
    out.append("metrics_label_values:            /* text offset, length */")
    for vid in value_rows:
        out.append(f"    .long {vid} - metrics_texts, {vid}_len")
    out.append("    .p2align 3")
    out.append("metrics_bounds:                  /* by METRIC_BOUNDS_*: count, unit, first bound */")
    for count, unit, first in bound_rows:
        out.append(f"    .long {count}, {unit}, {first}, 0")
    out.append("metrics_bound_values:            /* microseconds (or the Profile's bound index), text offset, length */")
    for value, tid in bound_values:
        out.append(f"    .quad {value}")
        out.append(f"    .long {tid} - metrics_texts, {tid}_len")
    out.append("    .p2align 3")
    out.append("metrics_table:")
    types = {"gauge": "GAUGE", "counter": "COUNTER", "histogram": "HISTOGRAM"}
    for f, nid, hid in rows:
        src = f["src"]
        off = "0" if f["field"] is None else f"{SOURCE_STRUCT[src]}_{f['field']}"
        labs = [label_ids[x] for x in f["labels"]] + [0, 0]
        count = 1
        for x in f["labels"]:
            count *= len(LABELS[x][1])
        bounds = f"METRIC_BOUNDS_{f['bounds'].upper()}" if f["bounds"] else "0"
        out.append(f"    .long {nid} - metrics_texts, {nid}_len, {hid} - metrics_texts, {hid}_len, "
                   f"METRIC_TYPE_{types[f['type']]}, METRIC_SRC_{src.upper()}, {off}")
        out.append(f"    .short METRIC_KIND_{f['kind'].upper()}, METRIC_COND_{(f['cond'] or 'none').upper()}")
        out.append(f"    .long METRIC_BIT_{f['cat'].replace('.', '_').upper()}")
        out.append(f"    .short {labs[0]}, {labs[1]}")
        out.append(f"    .long {bounds}, {count}")
    out.append("metrics_table_end:")
    pathlib.Path(path).write_text("\n".join(out) + "\n")


if __name__ == "__main__" and len(sys.argv) == 3 and sys.argv[1] == "include":
    root = pathlib.Path(__file__).resolve().parents[2]
    write_metrics_inc(root / "include" / "metrics.inc")
    write_table_inc(root / "include" / "metrics_table.inc", sys.argv[2])
