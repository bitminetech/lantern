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


def flag_names():
    """The names the --metrics flag takes, in order: each category, then each of its sub categories."""
    for cat, subs in CATEGORIES:
        yield cat
        for sub in subs:
            yield f"{cat}.{sub}"


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
    "work": ("us", ["0.00001", "0.0001", "0.0005", "0.001", "0.005", "0.01", "0.05", "0.1", "0.5", "1", "5"]),
    "ticks": ("ticks", ["0.000001", "0.000004", "0.000016", "0.000064", "0.000256", "0.001", "0.004", "0.016",
                        "0.064", "0.256", "1"]),
}
BOUND_ORDER = ["default", "kzg", "delay", "ticks", "work"]
PROFILE_BOUNDS = len(BOUNDS["ticks"][1])

# ---------------------------------------------------------------- Labels

# id: (label name, values)
TOPICS = ["other", "beacon_block", "beacon_aggregate_and_proof", "beacon_attestation", "voluntary_exit",
          "proposer_slashing", "attester_slashing", "sync_committee_contribution_and_proof", "sync_committee",
          "bls_to_execution_change", "blob_sidecar", "data_column_sidecar", "light_client_finality_update",
          "light_client_optimistic_update"]  # by GOSSIP_*: 0 a topic of no name
METHODS = ["other", "status", "goodbye", "beacon_blocks_by_range", "beacon_blocks_by_root", "ping", "metadata",
           "blob_sidecars_by_range", "blob_sidecars_by_root", "data_column_sidecars_by_range",
           "data_column_sidecars_by_root", "beacon_blocks_by_head", "light_client_bootstrap",
           "light_client_updates_by_range", "light_client_finality_update", "light_client_optimistic_update"]  # by REQRESP_*
# NODE_WORK_* kinds by number (node.md), and the processing sub category of each.
WORKS = ["none", "import_block", "justified_state", "target_state", "attestation", "attester_slashing", "serve",
         "gossip", "sync_block", "blob", "new_payload", "forkchoice", "slots", "upgrade", "replay", "backfill",
         "block_attestation", "block_slashing", "gossip_vote", "api_encode", "api_chunk", "api_lookup", "api_event",
         "api_submit", "pool_check", "prepare_payload", "produce_check", "get_payload", "produce_fold", "produce_block",
         "publish_decode", "publish_sidecars", "publish_check", "publish_sidecar", "lc_block", "lc_head", "lc_serve",
         "lc_gossip", "lc_publish", "produce_bid", "eth1_check", "produce_eth1", "archive_load", "custody",
         "reconstruct"]
WORK_SUB = {
    "block": ["import_block", "sync_block", "block_attestation", "block_slashing", "replay"],
    "state": ["justified_state", "target_state", "slots", "upgrade"],
    "forkchoice": ["attestation", "attester_slashing", "gossip_vote"],
    "availability": ["blob", "reconstruct", "custody"],
    "gossip": ["gossip"],
    "engine": ["new_payload", "forkchoice", "prepare_payload", "get_payload", "eth1_check"],
    "builder": ["produce_bid"],
    "lightclient": ["lc_block", "lc_head", "lc_serve", "lc_gossip", "lc_publish"],
    "history": ["backfill", "archive_load", "serve"],
    "validator": ["api_encode", "api_chunk", "api_lookup", "api_event", "api_submit", "pool_check", "produce_check",
                  "produce_fold", "produce_block", "publish_decode", "publish_sidecars", "publish_check",
                  "publish_sidecar", "produce_eth1"],
}
WORK_ORDER = [w for sub in WORK_SUB.values() for w in sub]  # the slots of AppMetrics work_seconds and work_failures
assert sorted(WORK_ORDER) == sorted(WORKS[1:])
WORK_SLOT = {w: i for i, w in enumerate(WORK_ORDER)}

LABELS = {
    "status": ("status", ["pending", "active", "exited", "withdrawable"]),
    "topic": ("topic", TOPICS),
    "result": ("result", ["accept", "ignore", "reject"]),
    "method": ("method", METHODS),
    "direction": ("direction", ["inbound", "outbound"]),
    "level": ("level", ["error", "warn", "info", "debug"]),  # by the level of app_log_rank
    "class": ("class", ["2xx", "3xx", "4xx", "5xx"]),
    "kind": ("kind", ["block", "sidecar", "state"]),
}
for _sub, _works in WORK_SUB.items():
    LABELS["work_" + _sub] = ("work", _works)

# ---------------------------------------------------------------- Structs

# struct: [(field, type, count)]; types u64, i64, hist (a Histogram), bytes16. Every field 8-aligned.
STRUCTS = {
    "MetricsState": [
        ("present", "u64", 1), ("slot", "u64", 1), ("finalized_epoch", "u64", 1),
        ("current_justified_epoch", "u64", 1), ("previous_justified_epoch", "u64", 1),
        ("active_validators", "u64", 1), ("deposit_count", "u64", 1), ("finalized_root", "i64", 1),
        ("previous_justified_root", "i64", 1), ("current_validators", "u64", 4), ("previous_validators", "u64", 4),
        ("current_live", "u64", 1), ("previous_live", "u64", 1), ("altair", "u64", 1), ("electra", "u64", 1),
        ("pending_deposits", "u64", 1), ("pending_partial_withdrawals", "u64", 1),
        ("pending_consolidations", "u64", 1), ("state_root_present", "u64", 1), ("state_root", "i64", 1),
    ],
    "MetricsNode": [
        ("peers", "u64", 1), ("fulu", "u64", 1), ("custody_groups", "u64", 1), ("pending_exits", "u64", 1),
        ("local_validators", "u64", 1), ("orphaned_blocks", "u64", 1), ("sync_state", "u64", 1),
        ("head_block_id", "u64", 1), ("head_state_id", "u64", 1), ("peer_directions", "u64", 2),
        ("dialing", "u64", 1), ("head_slot", "u64", 1), ("store_slot", "u64", 1), ("distance", "u64", 1),
        ("earliest_slot", "u64", 1), ("backfill_slot", "u64", 1), ("finalized_epoch", "u64", 1),
        ("justified_epoch", "u64", 1), ("messages", "u64", 1), ("streams", "u64", 1), ("pool", "u64", len(TOPICS)),
    ],
    "NodeMetrics": [("reorgs", "u64", 1), ("attestations_published", "u64", 1)],
    "AppMetrics": [
        ("gossip_verification", "hist", 1), ("reconstruction", "hist", 1), ("computation", "hist", 1),
        ("kzg_batch", "hist", 1), ("attestation_delay", "hist", 1), ("block_delay", "hist", 1),
        ("column_requests", "u64", 1), ("column_successes", "u64", 1), ("reconstructed_columns", "u64", 1),
        ("aggregates_received", "u64", 1), ("attestations_received", "u64", 1),
        ("attester_slashings_received", "u64", 1), ("blocks_proposed", "u64", 1),
        ("gossip_blocks_imported", "u64", 1), ("validation_failures", "u64", 1), ("api_requests", "u64", 1),
        ("api_successes", "u64", 1), ("connections", "u64", 2), ("dial_failures", "u64", 1), ("closed", "u64", 1),
        ("records", "u64", 1), ("lookups", "u64", 1), ("dv_in", "u64", 1), ("dv_out", "u64", 1),
        ("dv_failures", "u64", 1), ("rx_bytes", "u64", 1), ("tx_bytes", "u64", 1),
        ("gossip_results", "u64", 3 * len(TOPICS)), ("served", "u64", len(METHODS)),
        ("work_seconds", "hist", len(WORK_ORDER)), ("work_failures", "u64", len(WORK_ORDER)),
        ("epoch_transitions", "u64", 1), ("epoch_seconds", "hist", 1), ("gossip_seconds", "hist", len(TOPICS)),
        ("step_seconds", "hist", 1), ("log_lines", "u64", 4), ("api_classes", "u64", 4), ("db_records", "u64", 3),
        ("db_bytes", "u64", 3), ("db_anchors", "u64", 1), ("db_drops", "u64", 1), ("db_failures", "u64", 1),
    ],
    "MetricsProcess": [("cpu_us", "u64", 1), ("max_fds", "u64", 1), ("max_rss_bytes", "u64", 1), ("buffers", "u64", 1),
                       ("buffer_bytes", "u64", 1), ("start_s", "u64", 1), ("uptime_us", "u64", 1),
                       ("engine", "u64", 1), ("api_open", "u64", 1)],
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
CONDS = [None, "state", "electra", "fulu", "state_root", "max_fds", "profile", "altair"]


def F(name, mtype, cat, src, field, kind, labels=(), bounds=None, cond=None, help=None, index=0):
    """A family; index: its first element in the field's array."""
    return {"name": name, "type": mtype, "cat": cat, "src": src, "field": field, "kind": kind,
            "labels": list(labels), "bounds": bounds, "cond": cond, "help": help, "index": index}


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
    F("beacon_data_column_sidecar_processing_requests_total", None, "beacon", "app", "column_requests", "u64"),
    F("beacon_data_column_sidecar_processing_successes_total", None, "beacon", "app", "column_successes", "u64"),
    F("beacon_data_column_sidecar_gossip_verification_seconds", None, "beacon", "app", "gossip_verification", "hist",
      bounds="default"),
    F("beacon_data_availability_reconstructed_columns_total", None, "beacon", "app", "reconstructed_columns",
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
    F("beacon_current_live_validators", None, "beacon", "state", "current_live", "u64", cond="altair"),
    F("beacon_previous_live_validators", None, "beacon", "state", "previous_live", "u64", cond="altair"),
    F("beacon_pending_deposits", None, "beacon", "state", "pending_deposits", "u64", cond="electra"),
    F("beacon_pending_partial_withdrawals", None, "beacon", "state", "pending_partial_withdrawals", "u64",
      cond="electra"),
    F("beacon_pending_consolidations", None, "beacon", "state", "pending_consolidations", "u64", cond="electra"),
    F("beacon_pending_exits", None, "beacon", "node", "pending_exits", "u64"),
    F("beacon_previous_epoch_orphaned_blocks", None, "beacon", "node", "orphaned_blocks", "u64"),
    F("gossipsub_mesh_peers_per_main_topic", None, "beacon", "gossip", None, "gossip_main"),
    F("beacon_attestation_delay_count", None, "beacon", "app", "attestation_delay", "hist", bounds="delay"),
    F("local_validator_count", None, "beacon", "node", "local_validators", "u64"),
    F("beacon_head_state_finalized_root", None, "beacon", "state", "finalized_root", "root", cond="state"),
    F("beacon_previous_justified_root", None, "beacon", "state", "previous_justified_root", "root", cond="state"),
    F("beacon_aggregates_received_total", None, "beacon", "app", "aggregates_received", "u64"),
    F("beacon_block_delay_count", None, "beacon", "app", "block_delay", "hist", bounds="delay"),
    F("beacon_attestor_slashing_received_total", None, "beacon", "app", "attester_slashings_received", "u64"),
    F("beacon_block_proposed_total", None, "beacon", "app", "blocks_proposed", "u64"),
    F("beacon_attestations_published_total", None, "beacon", "counters", "attestations_published", "u64"),
    F("beacon_processor_gossip_block_imported_total", None, "beacon", "app", "gossip_blocks_imported", "u64"),
    F("libp2p_pubsub_validation_failure_total", None, "beacon", "app", "validation_failures", "u64"),
    F("beacon_head_state_root", None, "beacon", "state", "state_root", "root", cond="state_root"),
    F("beacon_attestations_received_total", None, "beacon", "app", "attestations_received", "u64"),
    F("beacon_http_api_requests_total", None, "beacon", "app", "api_requests", "u64"),
    F("beacon_http_api_successes_total", None, "beacon", "app", "api_successes", "u64"),
    F("beacon_sync_state", None, "beacon", "node", "sync_state", "u64"),
    F("process_cpu_seconds_total", None, "beacon", "process", "cpu_us", "seconds"),
    F("process_max_fds", None, "beacon", "process", "max_fds", "u64", cond="max_fds"),
    F("gossipsub_topic_msg_sent_bytes", None, "beacon", "gossip", None, "gossip_sent"),
    F("gossipsub_mesh_peer_counts", None, "beacon", "gossip", None, "gossip_mesh"),
]

def _work_families():
    out = []
    for sub, works in WORK_SUB.items():
        out.append(F(f"lantern_processing_{sub}_work_seconds", "histogram", f"processing.{sub}", "app", "work_seconds",
                     "array_hist", labels=["work_" + sub], bounds="work", index=WORK_SLOT[works[0]],
                     help=f"Run time of each node work of the {sub} stage, by work kind"))
        out.append(F(f"lantern_processing_{sub}_work_failures_total", "counter", f"processing.{sub}", "app",
                     "work_failures", "array", labels=["work_" + sub], index=WORK_SLOT[works[0]],
                     help=f"Node works of the {sub} stage whose result was not LANTERN_OK, by work kind"))
    return out


NETWORK = [
    F("lantern_network_peer_connected", "gauge", "network.peer", "node", "peers", "u64",
      help="Connected peers"),
    F("lantern_network_peer_direction", "gauge", "network.peer", "node", "peer_directions", "array", labels=["direction"],
      help="Connected peers by the direction of their connection"),
    F("lantern_network_peer_dialing", "gauge", "network.peer", "node", "dialing", "u64",
      help="Dials of the node not yet connected or failed"),
    F("lantern_network_peer_connections_total", "counter", "network.peer", "app", "connections", "array",
      labels=["direction"], help="Connections made, by direction"),
    F("lantern_network_peer_dial_failures_total", "counter", "network.peer", "app", "dial_failures", "u64",
      help="Dials that failed"),
    F("lantern_network_peer_disconnections_total", "counter", "network.peer", "app", "closed", "u64",
      help="Connections that closed"),
    F("lantern_network_discovery_records_total", "counter", "network.discovery", "app", "records", "u64",
      help="Node records discv5 found and gave to the node"),
    F("lantern_network_discovery_lookups_total", "counter", "network.discovery", "app", "lookups", "u64",
      help="Lookups the node asked discv5 for"),
    F("lantern_network_discovery_datagrams_received_total", "counter", "network.discovery", "app", "dv_in", "u64",
      help="UDP datagrams discv5 received"),
    F("lantern_network_discovery_datagrams_sent_total", "counter", "network.discovery", "app", "dv_out", "u64",
      help="UDP datagrams discv5 sent"),
    F("lantern_network_discovery_step_failures_total", "counter", "network.discovery", "app", "dv_failures", "u64",
      help="discv5 steps that failed"),
    F("lantern_network_transport_received_bytes_total", "counter", "network.transport", "app", "rx_bytes", "u64",
      help="Bytes received on libp2p connections"),
    F("lantern_network_transport_sent_bytes_total", "counter", "network.transport", "app", "tx_bytes", "u64",
      help="Bytes sent on libp2p connections"),
    F("lantern_network_gossip_messages_total", "counter", "network.gossip", "app", "gossip_results", "array",
      labels=["topic", "result"], help="Gossip messages validated, by topic and result"),
    F("lantern_network_gossip_messages_held", "gauge", "network.gossip", "node", "messages", "u64",
      help="Gossip messages the node holds"),
    F("lantern_network_reqresp_served_total", "counter", "network.reqresp", "app", "served", "array", labels=["method"],
      help="Requests of peers the node served, by method"),
    F("lantern_network_reqresp_streams_open", "gauge", "network.reqresp", "node", "streams", "u64",
      help="Request streams open"),
]

PROCESSING = _work_families() + [
    F("lantern_processing_epoch_transitions_total", "counter", "processing.epoch", "app", "epoch_transitions", "u64",
      help="Slot processing works that crossed an epoch boundary"),
    F("lantern_processing_epoch_slots_seconds", "histogram", "processing.epoch", "app", "epoch_seconds", "hist",
      bounds="work", help="Run time of each slot processing work that crossed an epoch boundary"),
    F("lantern_processing_gossip_validation_seconds", "histogram", "processing.gossip", "app", "gossip_seconds",
      "array_hist", labels=["topic"], bounds="work", help="Run time of each gossip validation, by topic"),
]

NODE = [
    F("lantern_node_resource_cpu_seconds_total", "counter", "node.resource", "process", "cpu_us", "seconds",
      help="User and system CPU time"),
    F("lantern_node_resource_max_resident_memory_bytes", "gauge", "node.resource", "process", "max_rss_bytes", "u64",
      help="Highest resident memory since the start"),
    F("lantern_node_resource_max_fds", "gauge", "node.resource", "process", "max_fds", "u64", cond="max_fds",
      help="The soft limit of open files"),
    F("lantern_node_resource_buffers", "gauge", "node.resource", "process", "buffers", "u64",
      help="Buffers the app holds for the node"),
    F("lantern_node_resource_buffer_bytes", "gauge", "node.resource", "process", "buffer_bytes", "u64",
      help="Bytes of those buffers"),
    F("lantern_node_resource_start_time_seconds", "gauge", "node.resource", "process", "start_s", "u64",
      help="Unix time of the start"),
    F("lantern_node_sync_head_slot", "gauge", "node.sync", "node", "head_slot", "u64", help="Slot of the head block"),
    F("lantern_node_sync_store_slot", "gauge", "node.sync", "node", "store_slot", "u64", help="Slot of the store's time"),
    F("lantern_node_sync_distance", "gauge", "node.sync", "node", "distance", "u64",
      help="Slots from the head to the store's slot"),
    F("lantern_node_sync_state", "gauge", "node.sync", "node", "sync_state", "u64",
      help="0 behind and not syncing, 1 synced, 2 syncing"),
    F("lantern_node_sync_earliest_slot", "gauge", "node.sync", "node", "earliest_slot", "u64",
      help="First slot whose blocks the node serves"),
    F("lantern_node_sync_backfill_slot", "gauge", "node.sync", "node", "backfill_slot", "u64",
      help="Slot below which the backfill looks for blocks"),
    F("lantern_node_sync_finalized_epoch", "gauge", "node.sync", "node", "finalized_epoch", "u64",
      help="The store's finalized epoch"),
    F("lantern_node_sync_justified_epoch", "gauge", "node.sync", "node", "justified_epoch", "u64",
      help="The store's justified epoch"),
    F("lantern_node_health_uptime_seconds", "gauge", "node.health", "process", "uptime_us", "seconds",
      help="Time since the start"),
    F("lantern_node_health_execution_engine", "gauge", "node.health", "process", "engine", "u64",
      help="Connection to the execution engine: 0 none, 1 dialing, 2 open"),
    F("lantern_node_health_step_seconds", "histogram", "node.health", "app", "step_seconds", "hist", bounds="work",
      help="Run time of each node step"),
    F("lantern_node_pool_operations", "gauge", "node.pool", "node", "pool", "array", labels=["topic"],
      help="Operations in the pool, by topic"),
    F("lantern_node_pool_proposers", "gauge", "node.pool", "node", "local_validators", "u64",
      help="Validators with a fee recipient from prepareBeaconProposer"),
    F("lantern_node_log_lines_total", "counter", "node.log", "app", "log_lines", "array", labels=["level"],
      help="Log lines written, by level"),
    F("lantern_node_api_requests_total", "counter", "node.api", "app", "api_requests", "u64",
      help="Beacon API requests"),
    F("lantern_node_api_answers_total", "counter", "node.api", "app", "api_classes", "array", labels=["class"],
      help="Beacon API answers, by status class"),
    F("lantern_node_api_connections_open", "gauge", "node.api", "process", "api_open", "u64",
      help="Beacon API connections open"),
    F("lantern_node_storage_records_total", "counter", "node.storage", "app", "db_records", "array", labels=["kind"],
      help="Records appended to the history's segment files, by kind"),
    F("lantern_node_storage_record_bytes_total", "counter", "node.storage", "app", "db_bytes", "array", labels=["kind"],
      help="Bytes of those records"),
    F("lantern_node_storage_anchors_total", "counter", "node.storage", "app", "db_anchors", "u64",
      help="Anchor states written for a restart"),
    F("lantern_node_storage_segments_dropped_total", "counter", "node.storage", "app", "db_drops", "u64",
      help="Segment files deleted"),
    F("lantern_node_storage_write_failures_total", "counter", "node.storage", "app", "db_failures", "u64",
      help="Writes to the data directory that failed"),
]

FAMILIES = BEACON + NETWORK + PROCESSING + NODE


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
        if c == "altair" and not (s and s["present"] and s["altair"]):
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
        if isinstance(v, list) and f["kind"] in ("array", "array_hist"):
            n = 1
            for x in f["labels"]:
                n *= len(LABELS[x][1])
            v = v[f["index"]:f["index"] + n]
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
        ("phase0", all_bits, 1, 0, 0, 1, 4096, 2, ()),
        ("subnet_topics_only", all_bits, 1, 1, 0, 0, 65536, 0, ()),
        ("many_topics", all_bits, 1, 1, 1, 1, 1024, 60, ()),
        ("no_state_source", all_bits, 1, 1, 1, 1, 1024, 3, ("state",)),
        ("no_app_no_profile", all_bits, 1, 1, 1, 1, 1024, 3, ("app", "profile")),
    ]
    for name, cats, present, electra, fulu, state_root, max_fds, ntopics, left_out in specs:
        altair = int(name != "phase0")
        tps = rng.choice([1000000000, 2399999999, 24000000])
        src = {
            "state": values(rng, "MetricsState", fams, {"present": present, "electra": electra, "altair": altair,
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


# ---------------------------------------------------------------- lantern_metrics_answer

OK_HEAD = "200 OK\r\nContent-Type: text/plain; version=0.0.4; charset=utf-8\r\nContent-Length: "
CLOSE = "\r\nConnection: close\r\n\r\n"
REASONS = {400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 413: "Content Too Large",
           431: "Request Header Fields Too Large", 501: "Not Implemented", 505: "HTTP Version Not Supported"}
ANSWER_MORE = 53  # LANTERN_HTTP_MORE


def answer(status, body):
    """The answer of docs/reference/metrics.md, lantern_metrics_answer: its head, then the text for 200."""
    if status == 200:
        return f"HTTP/1.1 {OK_HEAD}{len(body)}{CLOSE}".encode() + body
    allow = "Allow: GET\r\n" if status == 405 else ""
    return f"HTTP/1.1 {status} {REASONS[status]}\r\n{allow}Content-Length: 0{CLOSE}".encode()


def answer_cases(beacon_metrics):
    """Requests (the status each must give written out here) over the sources of a text case."""
    cases = dict(text_cases(beacon_metrics))
    parts0, parts1 = cases["every_metric"], cases["beacon_only"]
    get = b"GET /metrics HTTP/1.1\r\nHost: 127.0.0.1:8008\r\n\r\n"
    prom = (b"GET /metrics HTTP/1.1\r\nHost: 10.0.0.2:8008\r\nUser-Agent: Prometheus/3.5.0\r\n"
            b"Accept: application/openmetrics-text;version=1.0.0;q=0.5,text/plain;version=0.0.4;q=0.4,*/*;q=0.1\r\n"
            b"Accept-Encoding: gzip\r\nX-Prometheus-Scrape-Timeout-Seconds: 10\r\n\r\n")
    reqs = [  # name, request, status (0 for LANTERN_HTTP_MORE), sources
        ("get", get, 200, parts0),
        ("prometheus", prom, 200, parts0),
        ("beacon_only", get, 200, parts1),
        ("query", b"GET /metrics?x=1 HTTP/1.1\r\nHost: h\r\n\r\n", 200, parts0),
        ("http_1_0", b"GET /metrics HTTP/1.0\r\n\r\n", 200, parts0),
        ("empty_lines_first", b"\r\n\r\nGET /metrics HTTP/1.1\r\nHost: h\r\n\r\n", 200, parts0),
        ("two_requests", get + get, 200, parts0),
        ("no_category", get, 200, dict(parts0, categories=0)),
        ("root", b"GET / HTTP/1.1\r\nHost: h\r\n\r\n", 404, parts0),
        ("shorter_path", b"GET /metric HTTP/1.1\r\nHost: h\r\n\r\n", 404, parts0),
        ("longer_path", b"GET /metricsx HTTP/1.1\r\nHost: h\r\n\r\n", 404, parts0),
        ("upper_path", b"GET /Metrics HTTP/1.1\r\nHost: h\r\n\r\n", 404, parts0),
        ("post", b"POST /metrics HTTP/1.1\r\nHost: h\r\nContent-Length: 0\r\n\r\n", 405, parts0),
        ("head", b"HEAD /metrics HTTP/1.1\r\nHost: h\r\n\r\n", 405, parts0),
        ("no_host", b"GET /metrics HTTP/1.1\r\n\r\n", 400, parts0),
        ("version_2", b"GET /metrics HTTP/2.0\r\nHost: h\r\n\r\n", 505, parts0),
        ("body", b"POST /metrics HTTP/1.1\r\nHost: h\r\nContent-Length: 5\r\n\r\nhello", 413, parts0),
        ("coding", b"GET /metrics HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: gzip\r\n\r\n", 501, parts0),
        ("head_too_long", b"GET /metrics HTTP/1.1\r\nHost: h\r\nX-Pad: " + b"a" * 4096, 431, parts0),
        ("part_of_a_head", get[:-2], 0, parts0),
        ("no_bytes", b"", 0, parts0),
    ]
    for name, req, status, parts in reqs:
        out = dict((k, v) for k, v in parts.items() if k != "text")
        out["bytes"] = req
        out["status"] = 0 if status else ANSWER_MORE
        body = parts["text"] if parts["categories"] else b""
        out["answer"] = answer(status, body) if status else b""
        yield name, out


# ---------------------------------------------------------------- lantern_metrics_observe

def observe_cases():
    """Each microsecond bound set: a Histogram with random counts, then values about its bounds (and
    0, and 2^64 - 1 for a sum that wraps) one at a time, and the Histogram after each."""
    rng = random.Random(7806)
    for b in BOUND_ORDER:
        unit, texts = BOUNDS[b]
        if unit != "us":
            continue
        lim = [round(float(t) * 1000000) for t in texts]
        for k in range(3):
            h = {"count": rng.getrandbits(32), "sum": rng.getrandbits(63), "buckets": [rng.getrandbits(20) for _ in range(BUCKETS)]}
            start = hist_bytes(h)
            vals = [rng.choice([0, 1, lim[0], lim[0] + 1, lim[-1], lim[-1] + 1, (1 << 64) - 1] + [x + d for x in lim for d in (-1, 0, 1)])
                    for _ in range(40)]
            outs = b""
            for v in vals:
                h["count"] = (h["count"] + 1) % (1 << 64)
                h["sum"] = (h["sum"] + v) % (1 << 64)
                h["buckets"][next((i for i, x in enumerate(lim) if v <= x), len(lim))] += 1
                outs += hist_bytes(h)
            yield f"{b}/{k}", {"bounds": BOUND_ORDER.index(b), "histogram": start,
                               "values": b"".join(struct.pack("<Q", v) for v in vals), "out": outs}


# ---------------------------------------------------------------- lantern_<fork>_metrics_state

FORKS = ("phase0", "altair", "bellatrix", "capella", "deneb", "electra", "fulu")


def signed_root(root):
    """A root as a number (beacon-metrics): bytes 24 to 32, little endian, signed."""
    return int.from_bytes(bytes(root)[24:32], "little", signed=True)


def state_values(spec, fork, state, block):
    """MetricsState of docs/reference/metrics.md, lantern_metrics_state, from the spec's functions."""
    cur, prev = spec.get_current_epoch(state), spec.get_previous_epoch(state)

    def status(v, e):
        if v.activation_epoch > e:
            return 0  # pending
        if spec.is_active_validator(v, e):
            return 1  # active
        return 2 if v.withdrawable_epoch > e else 3  # exited, withdrawable

    cv, pv = [0] * 4, [0] * 4
    clive = plive = 0
    for i, v in enumerate(state.validators):
        cv[status(v, cur)] += 1
        pv[status(v, prev)] += 1
        if fork != "phase0":
            clive += int(spec.is_active_validator(v, cur) and state.current_epoch_participation[i] != 0)
            plive += int(spec.is_active_validator(v, prev) and state.previous_epoch_participation[i] != 0)
    electra = FORKS.index(fork) >= FORKS.index("electra")
    out = {
        "present": 1, "slot": int(state.slot), "finalized_epoch": int(state.finalized_checkpoint.epoch),
        "current_justified_epoch": int(state.current_justified_checkpoint.epoch),
        "previous_justified_epoch": int(state.previous_justified_checkpoint.epoch),
        "active_validators": len(spec.get_active_validator_indices(state, cur)),
        "deposit_count": int(state.eth1_data.deposit_count),
        "finalized_root": signed_root(state.finalized_checkpoint.root),
        "previous_justified_root": signed_root(state.previous_justified_checkpoint.root),
        "current_validators": cv, "previous_validators": pv, "current_live": clive, "previous_live": plive,
        "altair": int(fork != "phase0"), "electra": int(electra),
        "pending_deposits": len(state.pending_deposits) if electra else 0,
        "pending_partial_withdrawals": len(state.pending_partial_withdrawals) if electra else 0,
        "pending_consolidations": len(state.pending_consolidations) if electra else 0,
        "state_root_present": int(len(block) >= 180),
        "state_root": int.from_bytes(block[172:180], "little", signed=True) if len(block) >= 180 else 0,
    }
    return struct_bytes("MetricsState", out)


def state_cases(fork, preset):
    """States of random validators about their epochs, checkpoints and lists, with blocks of each kind."""
    spec = __import__(f"eth_consensus_specs.{fork}.{preset}", fromlist=["*"])
    rng = random.Random(f"metrics-state-{fork}-{preset}")
    far = int(spec.FAR_FUTURE_EPOCH)
    electra = FORKS.index(fork) >= FORKS.index("electra")
    shapes = [("genesis", 0, 0), ("one_validator", 1, 3), ("epoch_one", 40, 1), ("many", 300, 7),
              ("far_epoch", 120, 1 << 30), ("odd", 97, 12)]
    for name, n, epoch in shapes:
        for blk in ("anchor", "short", "block"):
            state = spec.BeaconState()
            state.slot = epoch * int(spec.SLOTS_PER_EPOCH) + rng.randrange(int(spec.SLOTS_PER_EPOCH))
            near = [0, max(epoch - 1, 0), epoch, epoch + 1, epoch + 2, far]
            for i in range(n):
                a, x, w = sorted(rng.choice(near) for _ in range(3))
                if rng.random() < 0.1:
                    a, x, w = rng.choice(near), rng.choice(near), rng.choice(near)  # out of order
                state.validators.append(spec.Validator(pubkey=spec.BLSPubkey(rng.randbytes(48)), activation_epoch=a,
                                                       exit_epoch=x, withdrawable_epoch=w,
                                                       effective_balance=spec.MAX_EFFECTIVE_BALANCE))
                state.balances.append(spec.MAX_EFFECTIVE_BALANCE)
                if fork != "phase0":
                    state.previous_epoch_participation.append(rng.choice([0, 0, 1, 2, 4, 7]))
                    state.current_epoch_participation.append(rng.choice([0, 0, 1, 2, 4, 7]))
                    state.inactivity_scores.append(0)
            state.finalized_checkpoint = spec.Checkpoint(epoch=max(epoch - 2, 0), root=spec.Root(rng.randbytes(32)))
            state.current_justified_checkpoint = spec.Checkpoint(epoch=epoch, root=spec.Root(rng.randbytes(32)))
            state.previous_justified_checkpoint = spec.Checkpoint(epoch=max(epoch - 1, 0), root=spec.Root(rng.randbytes(32)))
            state.eth1_data.deposit_count = rng.choice([0, n, rng.getrandbits(64)])
            if electra:
                for _ in range(rng.randrange(4)):
                    state.pending_deposits.append(spec.PendingDeposit(amount=rng.getrandbits(32)))
                for _ in range(rng.randrange(4)):
                    state.pending_partial_withdrawals.append(spec.PendingPartialWithdrawal(amount=rng.getrandbits(32)))
                for _ in range(rng.randrange(4)):
                    state.pending_consolidations.append(spec.PendingConsolidation(source_index=rng.randrange(1 << 20)))
            if blk == "anchor":
                block = b""
            elif blk == "short":
                block = rng.randbytes(179)
            else:
                msg = spec.BeaconBlock(slot=state.slot, state_root=spec.Root(rng.randbytes(32)))
                block = spec.SignedBeaconBlock(message=msg).encode_bytes()
            yield f"{name}/{blk}", {"state": state.encode_bytes(), "block": block,
                                    "out": state_values(spec, fork, state, block)}


# ---------------------------------------------------------------- The include files

def asm_string(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")


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
    out.append("/* The names of the --metrics flag (app.md): each one's bits, its length, the name in 24 bytes */")
    out.append("/* The slot of each NODE_WORK_* kind in AppMetrics work_seconds and work_failures, by kind */")
    out.append(".macro METRIC_WORK_SLOTS")
    out.append("    .byte " + ", ".join(str(WORK_SLOT.get(w, 0)) for w in WORKS))
    out.append(".endm")
    out.append(".macro METRIC_CATEGORY_NAMES")
    for name in flag_names():
        assert len(name) <= 24
        out += [f"    .quad {category_mask(name)}, {len(name)}", f'    .ascii "{name}"', f"    .space 24 - {len(name)}"]
    out.append(".endm")
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
    out.append(".set METRICS_HEAD_MAX, 4096                 /* lantern_metrics_answer: HttpLimits head_max */")
    out.append(".set METRICS_HEAD_ROOM, 256                 /* out bytes before the text's ByteList */")
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
             "mx_partial": "partial", "mx_supports": "supports_partial", "mx_false": "false", "mx_true": "true",
             "mx_http": "HTTP/1.1 ", "mx_ok_head": OK_HEAD, "mx_close": CLOSE, "mx_crlf": "\r\n",
             "mx_allow": "Allow: GET\r\n", "mx_len0": "Content-Length: 0" + CLOSE, "mx_path": "/metrics"}
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
        if f["index"]:
            typ = layout(SOURCE_STRUCT[src])[0][f["field"]][1]
            off += f" + {f['index'] * TYPE_SIZE[typ]}"
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
