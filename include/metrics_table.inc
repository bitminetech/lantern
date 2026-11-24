/*
 * The metric table of the beacon category (docs/reference/metrics.md), in RODATA after
 * metrics_texts: each metric's name, HELP text (beacon-metrics 0af554b, its Usage text without
 * Markdown marks) and type, and where its value is. The same on every ISA.
 */
metrics_texts:
mt_n0:
    .ascii "libp2p_peers"
.set mt_n0_len, 12
mt_h0:
    .ascii "Tracks the total number of libp2p peers"
.set mt_h0_len, 39
mt_n1:
    .ascii "beacon_head_slot"
.set mt_n1_len, 16
mt_h1:
    .ascii "Latest slot of the beacon chain"
.set mt_h1_len, 31
mt_n2:
    .ascii "beacon_finalized_epoch"
.set mt_n2_len, 22
mt_h2:
    .ascii "Current finalized epoch"
.set mt_h2_len, 23
mt_n3:
    .ascii "beacon_current_justified_epoch"
.set mt_n3_len, 30
mt_h3:
    .ascii "Current justified epoch"
.set mt_h3_len, 23
mt_n4:
    .ascii "beacon_previous_justified_epoch"
.set mt_n4_len, 31
mt_h4:
    .ascii "Current previously justified epoch"
.set mt_h4_len, 34
mt_n5:
    .ascii "beacon_current_active_validators"
.set mt_n5_len, 32
mt_h5:
    .ascii "Current total active validators"
.set mt_h5_len, 31
mt_n6:
    .ascii "beacon_reorgs_total"
.set mt_n6_len, 19
mt_h6:
    .ascii "Total number of chain reorganizations"
.set mt_h6_len, 37
mt_n7:
    .ascii "beacon_processed_deposits_total"
.set mt_n7_len, 31
mt_h7:
    .ascii "Total number of deposits processed"
.set mt_h7_len, 34
mt_n8:
    .ascii "beacon_data_column_sidecar_processing_requests_total"
.set mt_n8_len, 52
mt_h8:
    .ascii "Number of data column sidecars submitted for processing"
.set mt_h8_len, 55
mt_n9:
    .ascii "beacon_data_column_sidecar_processing_successes_total"
.set mt_n9_len, 53
mt_h9:
    .ascii "Number of data column sidecars verified for gossip"
.set mt_h9_len, 50
mt_n10:
    .ascii "beacon_data_column_sidecar_gossip_verification_seconds"
.set mt_n10_len, 54
mt_h10:
    .ascii "Full runtime of data column sidecars gossip verification"
.set mt_h10_len, 56
mt_n11:
    .ascii "beacon_data_availability_reconstructed_columns_total"
.set mt_n11_len, 52
mt_h11:
    .ascii "Total count of reconstructed columns"
.set mt_h11_len, 36
mt_n12:
    .ascii "beacon_data_availability_reconstruction_time_seconds"
.set mt_n12_len, 52
mt_h12:
    .ascii "Time taken to reconstruct columns"
.set mt_h12_len, 33
mt_n13:
    .ascii "beacon_data_column_sidecar_computation_seconds"
.set mt_n13_len, 46
mt_h13:
    .ascii "Time taken to compute data column sidecar, including cells, proofs and inclusion proof"
.set mt_h13_len, 86
mt_n14:
    .ascii "beacon_kzg_verification_data_column_batch_seconds"
.set mt_n14_len, 49
mt_h14:
    .ascii "Runtime of batched data column kzg verification"
.set mt_h14_len, 47
mt_n15:
    .ascii "beacon_custody_groups"
.set mt_n15_len, 21
mt_h15:
    .ascii "Total number of custody groups within a node"
.set mt_h15_len, 44
mt_n16:
    .ascii "beacon_current_validators"
.set mt_n16_len, 25
mt_h16:
    .ascii "Number of status=\"pending|active|exited|withdrawable\" validators in current epoch"
.set mt_h16_len, 81
mt_n17:
    .ascii "beacon_previous_validators"
.set mt_n17_len, 26
mt_h17:
    .ascii "Number of status=\"pending|active|exited|withdrawable\" validators in previous epoch"
.set mt_h17_len, 82
mt_n18:
    .ascii "beacon_current_live_validators"
.set mt_n18_len, 30
mt_h18:
    .ascii "Number of active validators that successfully included attestation on chain for current epoch"
.set mt_h18_len, 93
mt_n19:
    .ascii "beacon_previous_live_validators"
.set mt_n19_len, 31
mt_h19:
    .ascii "Number of active validators that successfully included attestation on chain for previous epoch"
.set mt_h19_len, 94
mt_n20:
    .ascii "beacon_pending_deposits"
.set mt_n20_len, 23
mt_h20:
    .ascii "Number of pending deposits in the current state"
.set mt_h20_len, 47
mt_n21:
    .ascii "beacon_pending_partial_withdrawals"
.set mt_n21_len, 34
mt_h21:
    .ascii "Number of pending partial withdrawals in the current state"
.set mt_h21_len, 58
mt_n22:
    .ascii "beacon_pending_consolidations"
.set mt_n22_len, 29
mt_h22:
    .ascii "Number of pending consolidations in the current state"
.set mt_h22_len, 53
mt_n23:
    .ascii "beacon_pending_exits"
.set mt_n23_len, 20
mt_h23:
    .ascii "Number of pending voluntary exits in local operation pool"
.set mt_h23_len, 57
mt_n24:
    .ascii "beacon_previous_epoch_orphaned_blocks"
.set mt_n24_len, 37
mt_h24:
    .ascii "Number of blocks orphaned in the previous epoch"
.set mt_h24_len, 47
mt_n25:
    .ascii "gossipsub_mesh_peers_per_main_topic"
.set mt_n25_len, 35
mt_h25:
    .ascii "Number of peers per gossipsub topic"
.set mt_h25_len, 35
mt_n26:
    .ascii "beacon_attestation_delay_count"
.set mt_n26_len, 30
mt_h26:
    .ascii "Attestation delay count, bucket size yet to be decided"
.set mt_h26_len, 54
mt_n27:
    .ascii "local_validator_count"
.set mt_n27_len, 21
mt_h27:
    .ascii "Count of the number of local validators"
.set mt_h27_len, 39
mt_n28:
    .ascii "beacon_head_state_finalized_root"
.set mt_n28_len, 32
mt_h28:
    .ascii "Current finalized root*"
.set mt_h28_len, 23
mt_n29:
    .ascii "beacon_previous_justified_root"
.set mt_n29_len, 30
mt_h29:
    .ascii "Current previously justified root*"
.set mt_h29_len, 34
mt_n30:
    .ascii "beacon_aggregates_received_total"
.set mt_n30_len, 32
mt_h30:
    .ascii "Total number of aggregates received"
.set mt_h30_len, 35
mt_n31:
    .ascii "beacon_block_delay_count"
.set mt_n31_len, 24
mt_h31:
    .ascii "Block delay count, bucket size yet to be decided"
.set mt_h31_len, 48
mt_n32:
    .ascii "beacon_attestor_slashing_received_total"
.set mt_n32_len, 39
mt_h32:
    .ascii "Total number of attestor slashing received"
.set mt_h32_len, 42
mt_n33:
    .ascii "beacon_block_proposed_total"
.set mt_n33_len, 27
mt_h33:
    .ascii "Total number of blocks proposed"
.set mt_h33_len, 31
mt_n34:
    .ascii "beacon_attestations_published_total"
.set mt_n34_len, 35
mt_h34:
    .ascii "Total number of attestations proposed"
.set mt_h34_len, 37
mt_n35:
    .ascii "beacon_processor_gossip_block_imported_total"
.set mt_n35_len, 44
mt_h35:
    .ascii "Total number of imported blocks"
.set mt_h35_len, 31
mt_n36:
    .ascii "libp2p_pubsub_validation_failure_total"
.set mt_n36_len, 38
mt_h36:
    .ascii "Number of pubsub validation messages failed"
.set mt_h36_len, 43
mt_n37:
    .ascii "beacon_head_state_root"
.set mt_n37_len, 22
mt_h37:
    .ascii "Head state root"
.set mt_h37_len, 15
mt_n38:
    .ascii "beacon_attestations_received_total"
.set mt_n38_len, 34
mt_h38:
    .ascii "Total number of attestations received"
.set mt_h38_len, 37
mt_n39:
    .ascii "beacon_http_api_requests_total"
.set mt_n39_len, 30
mt_h39:
    .ascii "Total number of requests to the HTTP API endpoint"
.set mt_h39_len, 49
mt_n40:
    .ascii "beacon_http_api_successes_total"
.set mt_n40_len, 31
mt_h40:
    .ascii "Total number of successful requests to the HTTP API endpoint"
.set mt_h40_len, 60
mt_n41:
    .ascii "beacon_sync_state"
.set mt_n41_len, 17
mt_h41:
    .ascii "Beacon sync state, 0 for not syncing, 1 for synced, 2 for syncing"
.set mt_h41_len, 65
mt_n42:
    .ascii "process_cpu_seconds_total"
.set mt_n42_len, 25
mt_h42:
    .ascii "Total CPU time in seconds"
.set mt_h42_len, 25
mt_n43:
    .ascii "process_max_fds"
.set mt_n43_len, 15
mt_h43:
    .ascii "Maximum number of file descriptors"
.set mt_h43_len, 34
mt_n44:
    .ascii "gossipsub_topic_msg_sent_bytes"
.set mt_n44_len, 30
mt_h44:
    .ascii "Total size of publish messages sent via RPC. Labels: topic, partial"
.set mt_h44_len, 67
mt_n45:
    .ascii "gossipsub_mesh_peer_counts"
.set mt_n45_len, 26
mt_h45:
    .ascii "Number of partial-message capable peers in mesh. Labels: topic, supports_partial"
.set mt_h45_len, 80
mx_help:
    .ascii "# HELP "
.set mx_help_len, 7
mx_type:
    .ascii "# TYPE "
.set mx_type_len, 7
mx_gauge:
    .ascii " gauge\n"
.set mx_gauge_len, 7
mx_counter:
    .ascii " counter\n"
.set mx_counter_len, 9
mx_histogram:
    .ascii " histogram\n"
.set mx_histogram_len, 11
mx_bucket:
    .ascii "_bucket{le=\""
.set mx_bucket_len, 12
mx_le_end:
    .ascii "\"} "
.set mx_le_end_len, 3
mx_inf:
    .ascii "+Inf"
.set mx_inf_len, 4
mx_sum:
    .ascii "_sum "
.set mx_sum_len, 5
mx_count:
    .ascii "_count "
.set mx_count_len, 7
mx_sp:
    .ascii " "
.set mx_sp_len, 1
mx_lf:
    .ascii "\n"
.set mx_lf_len, 1
mx_st_pending:
    .ascii "{status=\"pending\"} "
.set mx_st_pending_len, 19
mx_st_active:
    .ascii "{status=\"active\"} "
.set mx_st_active_len, 18
mx_st_exited:
    .ascii "{status=\"exited\"} "
.set mx_st_exited_len, 18
mx_st_withdrawable:
    .ascii "{status=\"withdrawable\"} "
.set mx_st_withdrawable_len, 24
mx_topic:
    .ascii "{topic=\""
.set mx_topic_len, 8
mx_partial_f:
    .ascii "\",partial=\"false\"} "
.set mx_partial_f_len, 19
mx_partial_t:
    .ascii "\",partial=\"true\"} "
.set mx_partial_t_len, 18
mx_supports_f:
    .ascii "\",supports_partial=\"false\"} "
.set mx_supports_f_len, 28
mx_supports_t:
    .ascii "\",supports_partial=\"true\"} "
.set mx_supports_t_len, 27
mx_topic_end:
    .ascii "\"} "
.set mx_topic_end_len, 3
mb_default0:
    .ascii "0.005"
mb_default1:
    .ascii "0.01"
mb_default2:
    .ascii "0.025"
mb_default3:
    .ascii "0.05"
mb_default4:
    .ascii "0.1"
mb_default5:
    .ascii "0.25"
mb_default6:
    .ascii "0.5"
mb_default7:
    .ascii "1"
mb_default8:
    .ascii "2.5"
mb_default9:
    .ascii "5"
mb_default10:
    .ascii "10"
    .p2align 3
mb_default:                      /* count, then each bound: microseconds, text offset from metrics_texts, text length */
    .quad 11
    .quad 5000
    .long mb_default0 - metrics_texts, 5
    .quad 10000
    .long mb_default1 - metrics_texts, 4
    .quad 25000
    .long mb_default2 - metrics_texts, 5
    .quad 50000
    .long mb_default3 - metrics_texts, 4
    .quad 100000
    .long mb_default4 - metrics_texts, 3
    .quad 250000
    .long mb_default5 - metrics_texts, 4
    .quad 500000
    .long mb_default6 - metrics_texts, 3
    .quad 1000000
    .long mb_default7 - metrics_texts, 1
    .quad 2500000
    .long mb_default8 - metrics_texts, 3
    .quad 5000000
    .long mb_default9 - metrics_texts, 1
    .quad 10000000
    .long mb_default10 - metrics_texts, 2
mb_kzg0:
    .ascii "0.002"
mb_kzg1:
    .ascii "0.004"
mb_kzg2:
    .ascii "0.008"
mb_kzg3:
    .ascii "0.016"
mb_kzg4:
    .ascii "0.032"
mb_kzg5:
    .ascii "0.064"
mb_kzg6:
    .ascii "0.128"
mb_kzg7:
    .ascii "0.256"
mb_kzg8:
    .ascii "0.512"
mb_kzg9:
    .ascii "1.024"
    .p2align 3
mb_kzg:                      /* count, then each bound: microseconds, text offset from metrics_texts, text length */
    .quad 10
    .quad 2000
    .long mb_kzg0 - metrics_texts, 5
    .quad 4000
    .long mb_kzg1 - metrics_texts, 5
    .quad 8000
    .long mb_kzg2 - metrics_texts, 5
    .quad 16000
    .long mb_kzg3 - metrics_texts, 5
    .quad 32000
    .long mb_kzg4 - metrics_texts, 5
    .quad 64000
    .long mb_kzg5 - metrics_texts, 5
    .quad 128000
    .long mb_kzg6 - metrics_texts, 5
    .quad 256000
    .long mb_kzg7 - metrics_texts, 5
    .quad 512000
    .long mb_kzg8 - metrics_texts, 5
    .quad 1024000
    .long mb_kzg9 - metrics_texts, 5
mb_delay0:
    .ascii "0.5"
mb_delay1:
    .ascii "1"
mb_delay2:
    .ascii "2"
mb_delay3:
    .ascii "3"
mb_delay4:
    .ascii "4"
mb_delay5:
    .ascii "6"
mb_delay6:
    .ascii "8"
mb_delay7:
    .ascii "12"
mb_delay8:
    .ascii "24"
    .p2align 3
mb_delay:                      /* count, then each bound: microseconds, text offset from metrics_texts, text length */
    .quad 9
    .quad 500000
    .long mb_delay0 - metrics_texts, 3
    .quad 1000000
    .long mb_delay1 - metrics_texts, 1
    .quad 2000000
    .long mb_delay2 - metrics_texts, 1
    .quad 3000000
    .long mb_delay3 - metrics_texts, 1
    .quad 4000000
    .long mb_delay4 - metrics_texts, 1
    .quad 6000000
    .long mb_delay5 - metrics_texts, 1
    .quad 8000000
    .long mb_delay6 - metrics_texts, 1
    .quad 12000000
    .long mb_delay7 - metrics_texts, 2
    .quad 24000000
    .long mb_delay8 - metrics_texts, 2
    .p2align 3
metrics_table:
    .long mt_n0 - metrics_texts, mt_n0_len, mt_h0 - metrics_texts, mt_h0_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_peers
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n1 - metrics_texts, mt_n1_len, mt_h1 - metrics_texts, mt_h1_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_slot
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long mt_n2 - metrics_texts, mt_n2_len, mt_h2 - metrics_texts, mt_h2_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_finalized_epoch
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long mt_n3 - metrics_texts, mt_n3_len, mt_h3 - metrics_texts, mt_h3_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_current_justified_epoch
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long mt_n4 - metrics_texts, mt_n4_len, mt_h4 - metrics_texts, mt_h4_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_previous_justified_epoch
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long mt_n5 - metrics_texts, mt_n5_len, mt_h5 - metrics_texts, mt_h5_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_active_validators
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long mt_n6 - metrics_texts, mt_n6_len, mt_h6 - metrics_texts, mt_h6_len, METRIC_TYPE_COUNTER, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_reorgs
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n7 - metrics_texts, mt_n7_len, mt_h7 - metrics_texts, mt_h7_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_deposit_count
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long mt_n8 - metrics_texts, mt_n8_len, mt_h8 - metrics_texts, mt_h8_len, METRIC_TYPE_COUNTER, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_column_requests
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n9 - metrics_texts, mt_n9_len, mt_h9 - metrics_texts, mt_h9_len, METRIC_TYPE_COUNTER, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_column_successes
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n10 - metrics_texts, mt_n10_len, mt_h10 - metrics_texts, mt_h10_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_gossip_verification
    .short METRIC_KIND_HIST_DEFAULT, METRIC_COND_NONE
    .long mt_n11 - metrics_texts, mt_n11_len, mt_h11 - metrics_texts, mt_h11_len, METRIC_TYPE_COUNTER, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_reconstructed_columns
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n12 - metrics_texts, mt_n12_len, mt_h12 - metrics_texts, mt_h12_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_reconstruction
    .short METRIC_KIND_HIST_DEFAULT, METRIC_COND_NONE
    .long mt_n13 - metrics_texts, mt_n13_len, mt_h13 - metrics_texts, mt_h13_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_computation
    .short METRIC_KIND_HIST_DEFAULT, METRIC_COND_NONE
    .long mt_n14 - metrics_texts, mt_n14_len, mt_h14 - metrics_texts, mt_h14_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_kzg_batch
    .short METRIC_KIND_HIST_KZG, METRIC_COND_NONE
    .long mt_n15 - metrics_texts, mt_n15_len, mt_h15 - metrics_texts, mt_h15_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_custody_groups
    .short METRIC_KIND_U64, METRIC_COND_FULU
    .long mt_n16 - metrics_texts, mt_n16_len, mt_h16 - metrics_texts, mt_h16_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_current_validators
    .short METRIC_KIND_STATUS, METRIC_COND_STATE
    .long mt_n17 - metrics_texts, mt_n17_len, mt_h17 - metrics_texts, mt_h17_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_previous_validators
    .short METRIC_KIND_STATUS, METRIC_COND_STATE
    .long mt_n18 - metrics_texts, mt_n18_len, mt_h18 - metrics_texts, mt_h18_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_current_live
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long mt_n19 - metrics_texts, mt_n19_len, mt_h19 - metrics_texts, mt_h19_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_previous_live
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long mt_n20 - metrics_texts, mt_n20_len, mt_h20 - metrics_texts, mt_h20_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_pending_deposits
    .short METRIC_KIND_U64, METRIC_COND_ELECTRA
    .long mt_n21 - metrics_texts, mt_n21_len, mt_h21 - metrics_texts, mt_h21_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_pending_partial_withdrawals
    .short METRIC_KIND_U64, METRIC_COND_ELECTRA
    .long mt_n22 - metrics_texts, mt_n22_len, mt_h22 - metrics_texts, mt_h22_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_pending_consolidations
    .short METRIC_KIND_U64, METRIC_COND_ELECTRA
    .long mt_n23 - metrics_texts, mt_n23_len, mt_h23 - metrics_texts, mt_h23_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_pending_exits
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n24 - metrics_texts, mt_n24_len, mt_h24 - metrics_texts, mt_h24_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_orphaned_blocks
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n25 - metrics_texts, mt_n25_len, mt_h25 - metrics_texts, mt_h25_len, METRIC_TYPE_GAUGE, METRIC_SRC_GOSSIP, 0
    .short METRIC_KIND_GOSSIP_MAIN, METRIC_COND_NONE
    .long mt_n26 - metrics_texts, mt_n26_len, mt_h26 - metrics_texts, mt_h26_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_attestation_delay
    .short METRIC_KIND_HIST_DELAY, METRIC_COND_NONE
    .long mt_n27 - metrics_texts, mt_n27_len, mt_h27 - metrics_texts, mt_h27_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_local_validators
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n28 - metrics_texts, mt_n28_len, mt_h28 - metrics_texts, mt_h28_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_finalized_root
    .short METRIC_KIND_ROOT, METRIC_COND_STATE
    .long mt_n29 - metrics_texts, mt_n29_len, mt_h29 - metrics_texts, mt_h29_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_previous_justified_root
    .short METRIC_KIND_ROOT, METRIC_COND_STATE
    .long mt_n30 - metrics_texts, mt_n30_len, mt_h30 - metrics_texts, mt_h30_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_aggregates_received
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n31 - metrics_texts, mt_n31_len, mt_h31 - metrics_texts, mt_h31_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_block_delay
    .short METRIC_KIND_HIST_DELAY, METRIC_COND_NONE
    .long mt_n32 - metrics_texts, mt_n32_len, mt_h32 - metrics_texts, mt_h32_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_attester_slashings_received
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n33 - metrics_texts, mt_n33_len, mt_h33 - metrics_texts, mt_h33_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_blocks_proposed
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n34 - metrics_texts, mt_n34_len, mt_h34 - metrics_texts, mt_h34_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_attestations_published
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n35 - metrics_texts, mt_n35_len, mt_h35 - metrics_texts, mt_h35_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_gossip_blocks_imported
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n36 - metrics_texts, mt_n36_len, mt_h36 - metrics_texts, mt_h36_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_validation_failures
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n37 - metrics_texts, mt_n37_len, mt_h37 - metrics_texts, mt_h37_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_state_root
    .short METRIC_KIND_ROOT, METRIC_COND_STATE_ROOT
    .long mt_n38 - metrics_texts, mt_n38_len, mt_h38 - metrics_texts, mt_h38_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_attestations_received
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n39 - metrics_texts, mt_n39_len, mt_h39 - metrics_texts, mt_h39_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_api_requests
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n40 - metrics_texts, mt_n40_len, mt_h40 - metrics_texts, mt_h40_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_counters + NodeMetrics_api_successes
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n41 - metrics_texts, mt_n41_len, mt_h41 - metrics_texts, mt_h41_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_sync_state
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long mt_n42 - metrics_texts, mt_n42_len, mt_h42 - metrics_texts, mt_h42_len, METRIC_TYPE_GAUGE, METRIC_SRC_PROCESS, MetricsProcess_cpu_us
    .short METRIC_KIND_SECONDS, METRIC_COND_NONE
    .long mt_n43 - metrics_texts, mt_n43_len, mt_h43 - metrics_texts, mt_h43_len, METRIC_TYPE_GAUGE, METRIC_SRC_PROCESS, MetricsProcess_max_fds
    .short METRIC_KIND_U64, METRIC_COND_MAX_FDS
    .long mt_n44 - metrics_texts, mt_n44_len, mt_h44 - metrics_texts, mt_h44_len, METRIC_TYPE_COUNTER, METRIC_SRC_GOSSIP, 0
    .short METRIC_KIND_GOSSIP_SENT, METRIC_COND_NONE
    .long mt_n45 - metrics_texts, mt_n45_len, mt_h45 - metrics_texts, mt_h45_len, METRIC_TYPE_GAUGE, METRIC_SRC_GOSSIP, 0
    .short METRIC_KIND_GOSSIP_MESH, METRIC_COND_NONE
metrics_table_end:
