/*
 * Metrics (docs/reference/metrics.md): the category bits, the layouts of the values and the
 * constants of the table. Written by tests/generator/metrics.py from its lists; not by hand.
 */
.set METRIC_BIT_BEACON, 0
.set METRIC_BIT_NETWORK_PEER, 1
.set METRIC_BIT_NETWORK_DISCOVERY, 2
.set METRIC_BIT_NETWORK_TRANSPORT, 3
.set METRIC_BIT_NETWORK_GOSSIP, 4
.set METRIC_BIT_NETWORK_REQRESP, 5
.set METRIC_BIT_PROCESSING_BLOCK, 8
.set METRIC_BIT_PROCESSING_EPOCH, 9
.set METRIC_BIT_PROCESSING_STATE, 10
.set METRIC_BIT_PROCESSING_FORKCHOICE, 11
.set METRIC_BIT_PROCESSING_AVAILABILITY, 12
.set METRIC_BIT_PROCESSING_GOSSIP, 13
.set METRIC_BIT_PROCESSING_ENGINE, 14
.set METRIC_BIT_PROCESSING_BUILDER, 15
.set METRIC_BIT_PROCESSING_LIGHTCLIENT, 16
.set METRIC_BIT_PROCESSING_HISTORY, 17
.set METRIC_BIT_PROCESSING_VALIDATOR, 18
.set METRIC_BIT_NODE_RESOURCE, 24
.set METRIC_BIT_NODE_SYNC, 25
.set METRIC_BIT_NODE_HEALTH, 26
.set METRIC_BIT_NODE_POOL, 27
.set METRIC_BIT_NODE_LOG, 28
.set METRIC_BIT_NODE_API, 29
.set METRIC_BIT_NODE_STORAGE, 30
.set METRICS_BEACON, 1
.set METRICS_NETWORK, 62
.set METRICS_PROCESSING, 524032
.set METRICS_NODE, 2130706432
.set METRICS_ALL, 2131230527
/* The names of the --metrics flag (app.md): each one's bits, its length, the name in 24 bytes */
.macro METRIC_CATEGORY_NAMES
    .quad 1, 6
    .ascii "beacon"
    .space 24 - 6
    .quad 62, 7
    .ascii "network"
    .space 24 - 7
    .quad 2, 12
    .ascii "network.peer"
    .space 24 - 12
    .quad 4, 17
    .ascii "network.discovery"
    .space 24 - 17
    .quad 8, 17
    .ascii "network.transport"
    .space 24 - 17
    .quad 16, 14
    .ascii "network.gossip"
    .space 24 - 14
    .quad 32, 15
    .ascii "network.reqresp"
    .space 24 - 15
    .quad 524032, 10
    .ascii "processing"
    .space 24 - 10
    .quad 256, 16
    .ascii "processing.block"
    .space 24 - 16
    .quad 512, 16
    .ascii "processing.epoch"
    .space 24 - 16
    .quad 1024, 16
    .ascii "processing.state"
    .space 24 - 16
    .quad 2048, 21
    .ascii "processing.forkchoice"
    .space 24 - 21
    .quad 4096, 23
    .ascii "processing.availability"
    .space 24 - 23
    .quad 8192, 17
    .ascii "processing.gossip"
    .space 24 - 17
    .quad 16384, 17
    .ascii "processing.engine"
    .space 24 - 17
    .quad 32768, 18
    .ascii "processing.builder"
    .space 24 - 18
    .quad 65536, 22
    .ascii "processing.lightclient"
    .space 24 - 22
    .quad 131072, 18
    .ascii "processing.history"
    .space 24 - 18
    .quad 262144, 20
    .ascii "processing.validator"
    .space 24 - 20
    .quad 2130706432, 4
    .ascii "node"
    .space 24 - 4
    .quad 16777216, 13
    .ascii "node.resource"
    .space 24 - 13
    .quad 33554432, 9
    .ascii "node.sync"
    .space 24 - 9
    .quad 67108864, 11
    .ascii "node.health"
    .space 24 - 11
    .quad 134217728, 9
    .ascii "node.pool"
    .space 24 - 9
    .quad 268435456, 8
    .ascii "node.log"
    .space 24 - 8
    .quad 536870912, 8
    .ascii "node.api"
    .space 24 - 8
    .quad 1073741824, 12
    .ascii "node.storage"
    .space 24 - 12
.endm
.set HISTOGRAM_BUCKETS, 12
.set Histogram_count, 0
.set Histogram_sum, 8
.set Histogram_buckets, 16
.set Histogram__mem, 112
.set PROFILE_BOUNDS, 11
.set MetricsState_present, 0
.set MetricsState_slot, 8
.set MetricsState_finalized_epoch, 16
.set MetricsState_current_justified_epoch, 24
.set MetricsState_previous_justified_epoch, 32
.set MetricsState_active_validators, 40
.set MetricsState_deposit_count, 48
.set MetricsState_finalized_root, 56
.set MetricsState_previous_justified_root, 64
.set MetricsState_current_validators, 72
.set MetricsState_previous_validators, 104
.set MetricsState_current_live, 136
.set MetricsState_previous_live, 144
.set MetricsState_electra, 152
.set MetricsState_pending_deposits, 160
.set MetricsState_pending_partial_withdrawals, 168
.set MetricsState_pending_consolidations, 176
.set MetricsState_state_root_present, 184
.set MetricsState_state_root, 192
.set MetricsState__mem, 200
.set MetricsNode_peers, 0
.set MetricsNode_fulu, 8
.set MetricsNode_custody_groups, 16
.set MetricsNode_pending_exits, 24
.set MetricsNode_local_validators, 32
.set MetricsNode_orphaned_blocks, 40
.set MetricsNode_sync_state, 48
.set MetricsNode_head_block_id, 56
.set MetricsNode_head_state_id, 64
.set MetricsNode__mem, 72
.set NodeMetrics_reorgs, 0
.set NodeMetrics_column_requests, 8
.set NodeMetrics_column_successes, 16
.set NodeMetrics_reconstructed_columns, 24
.set NodeMetrics_aggregates_received, 32
.set NodeMetrics_attestations_received, 40
.set NodeMetrics_attester_slashings_received, 48
.set NodeMetrics_blocks_proposed, 56
.set NodeMetrics_attestations_published, 64
.set NodeMetrics_gossip_blocks_imported, 72
.set NodeMetrics_validation_failures, 80
.set NodeMetrics_api_requests, 88
.set NodeMetrics_api_successes, 96
.set NodeMetrics_attestation_delay, 104
.set NodeMetrics_block_delay, 216
.set NodeMetrics__mem, 328
.set AppMetrics_gossip_verification, 0
.set AppMetrics_reconstruction, 112
.set AppMetrics_computation, 224
.set AppMetrics_kzg_batch, 336
.set AppMetrics__mem, 448
.set MetricsProcess_cpu_us, 0
.set MetricsProcess_max_fds, 8
.set MetricsProcess__mem, 16
.set Profile_ticks_per_second, 0
.set Profile_bounds, 8
.set Profile__mem, 96
/* MetricsSources: the address of each source, by METRIC_SRC_*; 0 for a source not given */
.set MetricsSources_state, 0
.set METRIC_SRC_STATE, 0
.set MetricsSources_node, 8
.set METRIC_SRC_NODE, 1
.set MetricsSources_counters, 16
.set METRIC_SRC_COUNTERS, 2
.set MetricsSources_app, 24
.set METRIC_SRC_APP, 3
.set MetricsSources_process, 32
.set METRIC_SRC_PROCESS, 4
.set MetricsSources_gossip, 40
.set METRIC_SRC_GOSSIP, 5
.set MetricsSources_profile, 48
.set METRIC_SRC_PROFILE, 6
.set MetricsSources__mem, 56
.set MetricsGossip_topics, 8
.set MetricsGossip__fixed, 24
.set GossipTopic_name_length, 0
.set GossipTopic_name, 8
.set GOSSIP_TOPIC_NAME_MAX, 64
.set GossipTopic_subnet, 72
.set GossipTopic_mesh_peers, 80
.set GossipTopic_mesh_partial_peers, 88
.set GossipTopic_sent_bytes, 96
.set GossipTopic_sent_partial_bytes, 104
.set GossipTopic__mem, 112
/* An entry of the table (include/metrics_table.inc): text offsets from metrics_texts, and fields */
.set MetricEntry_name, 0
.set MetricEntry_name_len, 4
.set MetricEntry_help, 8
.set MetricEntry_help_len, 12
.set MetricEntry_type, 16
.set MetricEntry_source, 20
.set MetricEntry_offset, 24
.set MetricEntry_kind, 28
.set MetricEntry_cond, 30
.set MetricEntry_bit, 32
.set MetricEntry_label1, 36
.set MetricEntry_label2, 38
.set MetricEntry_bounds, 40
.set MetricEntry_count, 44
.set MetricEntry__mem, 48
/* A label table (metrics_labels): its name, its values from metrics_label_values */
.set MetricLabel_name, 0
.set MetricLabel_name_len, 4
.set MetricLabel_count, 8
.set MetricLabel_first, 12
.set MetricLabel__mem, 16
/* A bound set (metrics_bounds): its unit and bounds from metrics_bound_values */
.set MetricBounds_count, 0
.set MetricBounds_unit, 4
.set MetricBounds_first, 8
.set MetricBounds__mem, 16
.set MetricBound_value, 0
.set MetricBound_text, 8
.set MetricBound_text_len, 12
.set MetricBound__mem, 16
.set METRIC_UNIT_US, 0
.set METRIC_UNIT_TICKS, 1
.set METRIC_TYPE_GAUGE, 0
.set METRIC_TYPE_COUNTER, 1
.set METRIC_TYPE_HISTOGRAM, 2
.set METRIC_KIND_U64, 0
.set METRIC_KIND_ROOT, 1
.set METRIC_KIND_SECONDS, 2
.set METRIC_KIND_ARRAY, 3
.set METRIC_KIND_HIST, 4
.set METRIC_KIND_ARRAY_HIST, 5
.set METRIC_KIND_GOSSIP_MAIN, 6
.set METRIC_KIND_GOSSIP_SENT, 7
.set METRIC_KIND_GOSSIP_MESH, 8
.set METRIC_COND_NONE, 0
.set METRIC_COND_STATE, 1
.set METRIC_COND_ELECTRA, 2
.set METRIC_COND_FULU, 3
.set METRIC_COND_STATE_ROOT, 4
.set METRIC_COND_MAX_FDS, 5
.set METRIC_COND_PROFILE, 6
.set METRIC_BOUNDS_DEFAULT, 0
.set METRIC_BOUNDS_KZG, 1
.set METRIC_BOUNDS_DELAY, 2
.set METRIC_BOUNDS_TICKS, 3
.set METRIC_COUNT, 46
