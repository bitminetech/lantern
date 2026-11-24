/*
 * Metrics (docs/reference/metrics.md): the category bits and the layouts of the values.
 */
.set METRICS_BEACON, 1                  /* the bit of the beacon category */

.set MetricsState_present, 0            /* MetricsState: 1 when the values are a state's */
.set MetricsState_slot, 8
.set MetricsState_finalized_epoch, 16
.set MetricsState_current_justified_epoch, 24
.set MetricsState_previous_justified_epoch, 32
.set MetricsState_active_validators, 40
.set MetricsState_deposit_count, 48
.set MetricsState_finalized_root, 56     /* a root as a number: bytes 24 to 32, little-endian, signed */
.set MetricsState_previous_justified_root, 64
.set MetricsState_current_validators, 72 /* u64 x 4: pending, active, exited, withdrawable */
.set MetricsState_previous_validators, 104
.set MetricsState_current_live, 136
.set MetricsState_previous_live, 144
.set MetricsState_electra, 152           /* 1 from electra */
.set MetricsState_pending_deposits, 160
.set MetricsState_pending_partial_withdrawals, 168
.set MetricsState_pending_consolidations, 176
.set MetricsState_state_root_present, 184  /* 1 when the head block's bytes gave state_root */
.set MetricsState_state_root, 192        /* the head state's root as a number */
.set MetricsState__mem, 200

.set Histogram_count, 0                 /* Histogram: the values */
.set Histogram_sum_us, 8                /* their sum in microseconds */
.set Histogram_buckets, 16              /* u64 x HISTOGRAM_BUCKETS: entry i above bound i - 1 and at most bound i; then above the last */
.set HISTOGRAM_BUCKETS, 12
.set Histogram__mem, 112

.set NodeMetrics_reorgs, 0              /* NodeMetrics: the node step's counters */
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
.set NodeMetrics_attestation_delay, 104 /* Histogram, delay bounds */
.set NodeMetrics_block_delay, 216       /* Histogram, delay bounds */
.set NodeMetrics__mem, 328

.set MetricsNode_peers, 0               /* MetricsNode */
.set MetricsNode_fulu, 8                /* 1 from fulu */
.set MetricsNode_custody_groups, 16
.set MetricsNode_pending_exits, 24
.set MetricsNode_local_validators, 32
.set MetricsNode_orphaned_blocks, 40
.set MetricsNode_sync_state, 48
.set MetricsNode_head_block_id, 56       /* BufferId of the head's SignedBeaconBlock bytes, or 0 */
.set MetricsNode_head_state_id, 64       /* BufferId of the head's post-state, or 0 */
.set MetricsNode_counters, 72           /* a copy of the node's NodeMetrics */
.set MetricsNode__mem, 72 + NodeMetrics__mem

.set AppMetrics_gossip_verification, 0  /* AppMetrics: Histograms */
.set AppMetrics_reconstruction, 112
.set AppMetrics_computation, 224
.set AppMetrics_kzg_batch, 336
.set AppMetrics__mem, 448

.set MetricsProcess_cpu_us, 0           /* MetricsProcess */
.set MetricsProcess_max_fds, 8          /* 0 for none */
.set MetricsProcess__mem, 16

.set MetricsGossip_topics, 8            /* MetricsGossip: a value with one part of GossipTopic entries */
.set MetricsGossip__fixed, 24
.set GossipTopic_name_length, 0         /* GossipTopic */
.set GossipTopic_name, 8                /* 64 bytes */
.set GOSSIP_TOPIC_NAME_MAX, 64
.set GossipTopic_subnet, 72             /* 1 for a topic of a subnet */
.set GossipTopic_mesh_peers, 80
.set GossipTopic_mesh_partial_peers, 88
.set GossipTopic_sent_bytes, 96
.set GossipTopic_sent_partial_bytes, 104
.set GossipTopic__mem, 112

/* An entry of the metric table (include/metrics_table.inc): offsets from metrics_texts, and u32 fields. */
.set MetricEntry_name, 0
.set MetricEntry_name_len, 4
.set MetricEntry_help, 8
.set MetricEntry_help_len, 12
.set MetricEntry_type, 16               /* METRIC_TYPE_* */
.set MetricEntry_source, 20             /* METRIC_SRC_* */
.set MetricEntry_offset, 24             /* the value's offset in its source */
.set MetricEntry_kind, 28               /* u16 METRIC_KIND_* */
.set MetricEntry_cond, 30               /* u16 METRIC_COND_* */
.set MetricEntry__mem, 32
.set METRIC_TYPE_GAUGE, 0
.set METRIC_TYPE_COUNTER, 1
.set METRIC_TYPE_HISTOGRAM, 2
.set METRIC_SRC_STATE, 0
.set METRIC_SRC_NODE, 1
.set METRIC_SRC_APP, 2
.set METRIC_SRC_PROCESS, 3
.set METRIC_SRC_GOSSIP, 4
.set METRIC_KIND_U64, 0                 /* a decimal */
.set METRIC_KIND_ROOT, 1                /* a signed decimal */
.set METRIC_KIND_STATUS, 2              /* four samples by status */
.set METRIC_KIND_HIST_DEFAULT, 3        /* a histogram of the default bounds */
.set METRIC_KIND_HIST_KZG, 4            /* of the KZG bounds */
.set METRIC_KIND_HIST_DELAY, 5          /* of the delay bounds */
.set METRIC_KIND_SECONDS, 6             /* microseconds as seconds */
.set METRIC_KIND_GOSSIP_MAIN, 7         /* mesh_peers of each topic with no subnet */
.set METRIC_KIND_GOSSIP_SENT, 8         /* sent bytes of each topic, partial false and true */
.set METRIC_KIND_GOSSIP_MESH, 9         /* mesh peers of each topic, supports_partial false and true */
.set METRIC_COND_NONE, 0
.set METRIC_COND_STATE, 1               /* MetricsState.present */
.set METRIC_COND_ELECTRA, 2             /* and MetricsState.electra */
.set METRIC_COND_FULU, 3                /* MetricsNode.fulu */
.set METRIC_COND_STATE_ROOT, 4          /* MetricsState.present and state_root_present */
.set METRIC_COND_MAX_FDS, 5             /* MetricsProcess.max_fds above 0 */
.set METRIC_COUNT, 46                   /* the beacon category's metrics */
