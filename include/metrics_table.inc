/*
 * The metric table (docs/reference/metrics.md), in RODATA: the texts, the label tables, the bound
 * sets and one entry for each family. Written by tests/generator/metrics.py from its lists; the
 * beacon families' HELP texts are the Usage texts of ethereum/beacon-metrics 0af554b. The same on
 * every ISA.
 */
metrics_texts:
mt_s0:
    .ascii "libp2p_peers"
.set mt_s0_len, 12
mt_s1:
    .ascii "Tracks the total number of libp2p peers"
.set mt_s1_len, 39
mt_s2:
    .ascii "beacon_head_slot"
.set mt_s2_len, 16
mt_s3:
    .ascii "Latest slot of the beacon chain"
.set mt_s3_len, 31
mt_s4:
    .ascii "beacon_finalized_epoch"
.set mt_s4_len, 22
mt_s5:
    .ascii "Current finalized epoch"
.set mt_s5_len, 23
mt_s6:
    .ascii "beacon_current_justified_epoch"
.set mt_s6_len, 30
mt_s7:
    .ascii "Current justified epoch"
.set mt_s7_len, 23
mt_s8:
    .ascii "beacon_previous_justified_epoch"
.set mt_s8_len, 31
mt_s9:
    .ascii "Current previously justified epoch"
.set mt_s9_len, 34
mt_s10:
    .ascii "beacon_current_active_validators"
.set mt_s10_len, 32
mt_s11:
    .ascii "Current total active validators"
.set mt_s11_len, 31
mt_s12:
    .ascii "beacon_reorgs_total"
.set mt_s12_len, 19
mt_s13:
    .ascii "Total number of chain reorganizations"
.set mt_s13_len, 37
mt_s14:
    .ascii "beacon_processed_deposits_total"
.set mt_s14_len, 31
mt_s15:
    .ascii "Total number of deposits processed"
.set mt_s15_len, 34
mt_s16:
    .ascii "beacon_data_column_sidecar_processing_requests_total"
.set mt_s16_len, 52
mt_s17:
    .ascii "Number of data column sidecars submitted for processing"
.set mt_s17_len, 55
mt_s18:
    .ascii "beacon_data_column_sidecar_processing_successes_total"
.set mt_s18_len, 53
mt_s19:
    .ascii "Number of data column sidecars verified for gossip"
.set mt_s19_len, 50
mt_s20:
    .ascii "beacon_data_column_sidecar_gossip_verification_seconds"
.set mt_s20_len, 54
mt_s21:
    .ascii "Full runtime of data column sidecars gossip verification"
.set mt_s21_len, 56
mt_s22:
    .ascii "beacon_data_availability_reconstructed_columns_total"
.set mt_s22_len, 52
mt_s23:
    .ascii "Total count of reconstructed columns"
.set mt_s23_len, 36
mt_s24:
    .ascii "beacon_data_availability_reconstruction_time_seconds"
.set mt_s24_len, 52
mt_s25:
    .ascii "Time taken to reconstruct columns"
.set mt_s25_len, 33
mt_s26:
    .ascii "beacon_data_column_sidecar_computation_seconds"
.set mt_s26_len, 46
mt_s27:
    .ascii "Time taken to compute data column sidecar, including cells, proofs and inclusion proof"
.set mt_s27_len, 86
mt_s28:
    .ascii "beacon_kzg_verification_data_column_batch_seconds"
.set mt_s28_len, 49
mt_s29:
    .ascii "Runtime of batched data column kzg verification"
.set mt_s29_len, 47
mt_s30:
    .ascii "beacon_custody_groups"
.set mt_s30_len, 21
mt_s31:
    .ascii "Total number of custody groups within a node"
.set mt_s31_len, 44
mt_s32:
    .ascii "beacon_current_validators"
.set mt_s32_len, 25
mt_s33:
    .ascii "Number of status=\"pending|active|exited|withdrawable\" validators in current epoch"
.set mt_s33_len, 81
mt_s34:
    .ascii "beacon_previous_validators"
.set mt_s34_len, 26
mt_s35:
    .ascii "Number of status=\"pending|active|exited|withdrawable\" validators in previous epoch"
.set mt_s35_len, 82
mt_s36:
    .ascii "beacon_current_live_validators"
.set mt_s36_len, 30
mt_s37:
    .ascii "Number of active validators that successfully included attestation on chain for current epoch"
.set mt_s37_len, 93
mt_s38:
    .ascii "beacon_previous_live_validators"
.set mt_s38_len, 31
mt_s39:
    .ascii "Number of active validators that successfully included attestation on chain for previous epoch"
.set mt_s39_len, 94
mt_s40:
    .ascii "beacon_pending_deposits"
.set mt_s40_len, 23
mt_s41:
    .ascii "Number of pending deposits in the current state"
.set mt_s41_len, 47
mt_s42:
    .ascii "beacon_pending_partial_withdrawals"
.set mt_s42_len, 34
mt_s43:
    .ascii "Number of pending partial withdrawals in the current state"
.set mt_s43_len, 58
mt_s44:
    .ascii "beacon_pending_consolidations"
.set mt_s44_len, 29
mt_s45:
    .ascii "Number of pending consolidations in the current state"
.set mt_s45_len, 53
mt_s46:
    .ascii "beacon_pending_exits"
.set mt_s46_len, 20
mt_s47:
    .ascii "Number of pending voluntary exits in local operation pool"
.set mt_s47_len, 57
mt_s48:
    .ascii "beacon_previous_epoch_orphaned_blocks"
.set mt_s48_len, 37
mt_s49:
    .ascii "Number of blocks orphaned in the previous epoch"
.set mt_s49_len, 47
mt_s50:
    .ascii "gossipsub_mesh_peers_per_main_topic"
.set mt_s50_len, 35
mt_s51:
    .ascii "Number of peers per gossipsub topic"
.set mt_s51_len, 35
mt_s52:
    .ascii "beacon_attestation_delay_count"
.set mt_s52_len, 30
mt_s53:
    .ascii "Attestation delay count, bucket size yet to be decided"
.set mt_s53_len, 54
mt_s54:
    .ascii "local_validator_count"
.set mt_s54_len, 21
mt_s55:
    .ascii "Count of the number of local validators"
.set mt_s55_len, 39
mt_s56:
    .ascii "beacon_head_state_finalized_root"
.set mt_s56_len, 32
mt_s57:
    .ascii "Current finalized root*"
.set mt_s57_len, 23
mt_s58:
    .ascii "beacon_previous_justified_root"
.set mt_s58_len, 30
mt_s59:
    .ascii "Current previously justified root*"
.set mt_s59_len, 34
mt_s60:
    .ascii "beacon_aggregates_received_total"
.set mt_s60_len, 32
mt_s61:
    .ascii "Total number of aggregates received"
.set mt_s61_len, 35
mt_s62:
    .ascii "beacon_block_delay_count"
.set mt_s62_len, 24
mt_s63:
    .ascii "Block delay count, bucket size yet to be decided"
.set mt_s63_len, 48
mt_s64:
    .ascii "beacon_attestor_slashing_received_total"
.set mt_s64_len, 39
mt_s65:
    .ascii "Total number of attestor slashing received"
.set mt_s65_len, 42
mt_s66:
    .ascii "beacon_block_proposed_total"
.set mt_s66_len, 27
mt_s67:
    .ascii "Total number of blocks proposed"
.set mt_s67_len, 31
mt_s68:
    .ascii "beacon_attestations_published_total"
.set mt_s68_len, 35
mt_s69:
    .ascii "Total number of attestations proposed"
.set mt_s69_len, 37
mt_s70:
    .ascii "beacon_processor_gossip_block_imported_total"
.set mt_s70_len, 44
mt_s71:
    .ascii "Total number of imported blocks"
.set mt_s71_len, 31
mt_s72:
    .ascii "libp2p_pubsub_validation_failure_total"
.set mt_s72_len, 38
mt_s73:
    .ascii "Number of pubsub validation messages failed"
.set mt_s73_len, 43
mt_s74:
    .ascii "beacon_head_state_root"
.set mt_s74_len, 22
mt_s75:
    .ascii "Head state root"
.set mt_s75_len, 15
mt_s76:
    .ascii "beacon_attestations_received_total"
.set mt_s76_len, 34
mt_s77:
    .ascii "Total number of attestations received"
.set mt_s77_len, 37
mt_s78:
    .ascii "beacon_http_api_requests_total"
.set mt_s78_len, 30
mt_s79:
    .ascii "Total number of requests to the HTTP API endpoint"
.set mt_s79_len, 49
mt_s80:
    .ascii "beacon_http_api_successes_total"
.set mt_s80_len, 31
mt_s81:
    .ascii "Total number of successful requests to the HTTP API endpoint"
.set mt_s81_len, 60
mt_s82:
    .ascii "beacon_sync_state"
.set mt_s82_len, 17
mt_s83:
    .ascii "Beacon sync state, 0 for not syncing, 1 for synced, 2 for syncing"
.set mt_s83_len, 65
mt_s84:
    .ascii "process_cpu_seconds_total"
.set mt_s84_len, 25
mt_s85:
    .ascii "Total CPU time in seconds"
.set mt_s85_len, 25
mt_s86:
    .ascii "process_max_fds"
.set mt_s86_len, 15
mt_s87:
    .ascii "Maximum number of file descriptors"
.set mt_s87_len, 34
mt_s88:
    .ascii "gossipsub_topic_msg_sent_bytes"
.set mt_s88_len, 30
mt_s89:
    .ascii "Total size of publish messages sent via RPC. Labels: topic, partial"
.set mt_s89_len, 67
mt_s90:
    .ascii "gossipsub_mesh_peer_counts"
.set mt_s90_len, 26
mt_s91:
    .ascii "Number of partial-message capable peers in mesh. Labels: topic, supports_partial"
.set mt_s91_len, 80
mt_s92:
    .ascii "status"
.set mt_s92_len, 6
mt_s93:
    .ascii "pending"
.set mt_s93_len, 7
mt_s94:
    .ascii "active"
.set mt_s94_len, 6
mt_s95:
    .ascii "exited"
.set mt_s95_len, 6
mt_s96:
    .ascii "withdrawable"
.set mt_s96_len, 12
mt_s97:
    .ascii "0.005"
.set mt_s97_len, 5
mt_s98:
    .ascii "0.01"
.set mt_s98_len, 4
mt_s99:
    .ascii "0.025"
.set mt_s99_len, 5
mt_s100:
    .ascii "0.05"
.set mt_s100_len, 4
mt_s101:
    .ascii "0.1"
.set mt_s101_len, 3
mt_s102:
    .ascii "0.25"
.set mt_s102_len, 4
mt_s103:
    .ascii "0.5"
.set mt_s103_len, 3
mt_s104:
    .ascii "1"
.set mt_s104_len, 1
mt_s105:
    .ascii "2.5"
.set mt_s105_len, 3
mt_s106:
    .ascii "5"
.set mt_s106_len, 1
mt_s107:
    .ascii "10"
.set mt_s107_len, 2
mt_s108:
    .ascii "0.002"
.set mt_s108_len, 5
mt_s109:
    .ascii "0.004"
.set mt_s109_len, 5
mt_s110:
    .ascii "0.008"
.set mt_s110_len, 5
mt_s111:
    .ascii "0.016"
.set mt_s111_len, 5
mt_s112:
    .ascii "0.032"
.set mt_s112_len, 5
mt_s113:
    .ascii "0.064"
.set mt_s113_len, 5
mt_s114:
    .ascii "0.128"
.set mt_s114_len, 5
mt_s115:
    .ascii "0.256"
.set mt_s115_len, 5
mt_s116:
    .ascii "0.512"
.set mt_s116_len, 5
mt_s117:
    .ascii "1.024"
.set mt_s117_len, 5
mt_s118:
    .ascii "2"
.set mt_s118_len, 1
mt_s119:
    .ascii "3"
.set mt_s119_len, 1
mt_s120:
    .ascii "4"
.set mt_s120_len, 1
mt_s121:
    .ascii "6"
.set mt_s121_len, 1
mt_s122:
    .ascii "8"
.set mt_s122_len, 1
mt_s123:
    .ascii "12"
.set mt_s123_len, 2
mt_s124:
    .ascii "24"
.set mt_s124_len, 2
mt_s125:
    .ascii "0.000001"
.set mt_s125_len, 8
mt_s126:
    .ascii "0.000004"
.set mt_s126_len, 8
mt_s127:
    .ascii "0.000016"
.set mt_s127_len, 8
mt_s128:
    .ascii "0.000064"
.set mt_s128_len, 8
mt_s129:
    .ascii "0.000256"
.set mt_s129_len, 8
mt_s130:
    .ascii "0.001"
.set mt_s130_len, 5
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
    .ascii "_bucket"
.set mx_bucket_len, 7
mx_sum:
    .ascii "_sum"
.set mx_sum_len, 4
mx_count:
    .ascii "_count"
.set mx_count_len, 6
mx_inf:
    .ascii "+Inf"
.set mx_inf_len, 4
mx_le:
    .ascii "le"
.set mx_le_len, 2
mx_sp:
    .ascii " "
.set mx_sp_len, 1
mx_lf:
    .ascii "\n"
.set mx_lf_len, 1
mx_lbrace:
    .ascii "{"
.set mx_lbrace_len, 1
mx_rbrace:
    .ascii "}"
.set mx_rbrace_len, 1
mx_comma:
    .ascii ","
.set mx_comma_len, 1
mx_eq:
    .ascii "=\""
.set mx_eq_len, 2
mx_quote:
    .ascii "\""
.set mx_quote_len, 1
mx_topic:
    .ascii "topic"
.set mx_topic_len, 5
mx_partial:
    .ascii "partial"
.set mx_partial_len, 7
mx_supports:
    .ascii "supports_partial"
.set mx_supports_len, 16
mx_false:
    .ascii "false"
.set mx_false_len, 5
mx_true:
    .ascii "true"
.set mx_true_len, 4
mx_http:
    .ascii "HTTP/1.1 "
.set mx_http_len, 9
mx_ok_head:
    .ascii "200 OK\r\nContent-Type: text/plain; version=0.0.4; charset=utf-8\r\nContent-Length: "
.set mx_ok_head_len, 80
mx_close:
    .ascii "\r\nConnection: close\r\n\r\n"
.set mx_close_len, 23
mx_crlf:
    .ascii "\r\n"
.set mx_crlf_len, 2
mx_allow:
    .ascii "Allow: GET\r\n"
.set mx_allow_len, 12
mx_len0:
    .ascii "Content-Length: 0\r\nConnection: close\r\n\r\n"
.set mx_len0_len, 40
mx_path:
    .ascii "/metrics"
.set mx_path_len, 8
    .p2align 3
metrics_labels:                  /* by id from 1: name, name length, count, first value */
    .long mt_s92 - metrics_texts, mt_s92_len, 4, 0
metrics_label_values:            /* text offset, length */
    .long mt_s93 - metrics_texts, mt_s93_len
    .long mt_s94 - metrics_texts, mt_s94_len
    .long mt_s95 - metrics_texts, mt_s95_len
    .long mt_s96 - metrics_texts, mt_s96_len
    .p2align 3
metrics_bounds:                  /* by METRIC_BOUNDS_*: count, unit, first bound */
    .long 11, 0, 0, 0
    .long 10, 0, 11, 0
    .long 9, 0, 21, 0
    .long 11, 1, 30, 0
metrics_bound_values:            /* microseconds (or the Profile's bound index), text offset, length */
    .quad 5000
    .long mt_s97 - metrics_texts, mt_s97_len
    .quad 10000
    .long mt_s98 - metrics_texts, mt_s98_len
    .quad 25000
    .long mt_s99 - metrics_texts, mt_s99_len
    .quad 50000
    .long mt_s100 - metrics_texts, mt_s100_len
    .quad 100000
    .long mt_s101 - metrics_texts, mt_s101_len
    .quad 250000
    .long mt_s102 - metrics_texts, mt_s102_len
    .quad 500000
    .long mt_s103 - metrics_texts, mt_s103_len
    .quad 1000000
    .long mt_s104 - metrics_texts, mt_s104_len
    .quad 2500000
    .long mt_s105 - metrics_texts, mt_s105_len
    .quad 5000000
    .long mt_s106 - metrics_texts, mt_s106_len
    .quad 10000000
    .long mt_s107 - metrics_texts, mt_s107_len
    .quad 2000
    .long mt_s108 - metrics_texts, mt_s108_len
    .quad 4000
    .long mt_s109 - metrics_texts, mt_s109_len
    .quad 8000
    .long mt_s110 - metrics_texts, mt_s110_len
    .quad 16000
    .long mt_s111 - metrics_texts, mt_s111_len
    .quad 32000
    .long mt_s112 - metrics_texts, mt_s112_len
    .quad 64000
    .long mt_s113 - metrics_texts, mt_s113_len
    .quad 128000
    .long mt_s114 - metrics_texts, mt_s114_len
    .quad 256000
    .long mt_s115 - metrics_texts, mt_s115_len
    .quad 512000
    .long mt_s116 - metrics_texts, mt_s116_len
    .quad 1024000
    .long mt_s117 - metrics_texts, mt_s117_len
    .quad 500000
    .long mt_s103 - metrics_texts, mt_s103_len
    .quad 1000000
    .long mt_s104 - metrics_texts, mt_s104_len
    .quad 2000000
    .long mt_s118 - metrics_texts, mt_s118_len
    .quad 3000000
    .long mt_s119 - metrics_texts, mt_s119_len
    .quad 4000000
    .long mt_s120 - metrics_texts, mt_s120_len
    .quad 6000000
    .long mt_s121 - metrics_texts, mt_s121_len
    .quad 8000000
    .long mt_s122 - metrics_texts, mt_s122_len
    .quad 12000000
    .long mt_s123 - metrics_texts, mt_s123_len
    .quad 24000000
    .long mt_s124 - metrics_texts, mt_s124_len
    .quad 0
    .long mt_s125 - metrics_texts, mt_s125_len
    .quad 1
    .long mt_s126 - metrics_texts, mt_s126_len
    .quad 2
    .long mt_s127 - metrics_texts, mt_s127_len
    .quad 3
    .long mt_s128 - metrics_texts, mt_s128_len
    .quad 4
    .long mt_s129 - metrics_texts, mt_s129_len
    .quad 5
    .long mt_s130 - metrics_texts, mt_s130_len
    .quad 6
    .long mt_s109 - metrics_texts, mt_s109_len
    .quad 7
    .long mt_s111 - metrics_texts, mt_s111_len
    .quad 8
    .long mt_s113 - metrics_texts, mt_s113_len
    .quad 9
    .long mt_s115 - metrics_texts, mt_s115_len
    .quad 10
    .long mt_s104 - metrics_texts, mt_s104_len
    .p2align 3
metrics_table:
    .long mt_s0 - metrics_texts, mt_s0_len, mt_s1 - metrics_texts, mt_s1_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_peers
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s2 - metrics_texts, mt_s2_len, mt_s3 - metrics_texts, mt_s3_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_slot
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s4 - metrics_texts, mt_s4_len, mt_s5 - metrics_texts, mt_s5_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_finalized_epoch
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s6 - metrics_texts, mt_s6_len, mt_s7 - metrics_texts, mt_s7_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_current_justified_epoch
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s8 - metrics_texts, mt_s8_len, mt_s9 - metrics_texts, mt_s9_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_previous_justified_epoch
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s10 - metrics_texts, mt_s10_len, mt_s11 - metrics_texts, mt_s11_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_active_validators
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s12 - metrics_texts, mt_s12_len, mt_s13 - metrics_texts, mt_s13_len, METRIC_TYPE_COUNTER, METRIC_SRC_COUNTERS, NodeMetrics_reorgs
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s14 - metrics_texts, mt_s14_len, mt_s15 - metrics_texts, mt_s15_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_deposit_count
    .short METRIC_KIND_U64, METRIC_COND_STATE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s16 - metrics_texts, mt_s16_len, mt_s17 - metrics_texts, mt_s17_len, METRIC_TYPE_COUNTER, METRIC_SRC_COUNTERS, NodeMetrics_column_requests
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s18 - metrics_texts, mt_s18_len, mt_s19 - metrics_texts, mt_s19_len, METRIC_TYPE_COUNTER, METRIC_SRC_COUNTERS, NodeMetrics_column_successes
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s20 - metrics_texts, mt_s20_len, mt_s21 - metrics_texts, mt_s21_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_gossip_verification
    .short METRIC_KIND_HIST, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long METRIC_BOUNDS_DEFAULT, 1
    .long mt_s22 - metrics_texts, mt_s22_len, mt_s23 - metrics_texts, mt_s23_len, METRIC_TYPE_COUNTER, METRIC_SRC_COUNTERS, NodeMetrics_reconstructed_columns
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s24 - metrics_texts, mt_s24_len, mt_s25 - metrics_texts, mt_s25_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_reconstruction
    .short METRIC_KIND_HIST, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long METRIC_BOUNDS_DEFAULT, 1
    .long mt_s26 - metrics_texts, mt_s26_len, mt_s27 - metrics_texts, mt_s27_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_computation
    .short METRIC_KIND_HIST, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long METRIC_BOUNDS_DEFAULT, 1
    .long mt_s28 - metrics_texts, mt_s28_len, mt_s29 - metrics_texts, mt_s29_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_kzg_batch
    .short METRIC_KIND_HIST, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long METRIC_BOUNDS_KZG, 1
    .long mt_s30 - metrics_texts, mt_s30_len, mt_s31 - metrics_texts, mt_s31_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_custody_groups
    .short METRIC_KIND_U64, METRIC_COND_FULU
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s32 - metrics_texts, mt_s32_len, mt_s33 - metrics_texts, mt_s33_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_current_validators
    .short METRIC_KIND_ARRAY, METRIC_COND_STATE
    .long METRIC_BIT_BEACON
    .short 1, 0
    .long 0, 4
    .long mt_s34 - metrics_texts, mt_s34_len, mt_s35 - metrics_texts, mt_s35_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_previous_validators
    .short METRIC_KIND_ARRAY, METRIC_COND_STATE
    .long METRIC_BIT_BEACON
    .short 1, 0
    .long 0, 4
    .long mt_s36 - metrics_texts, mt_s36_len, mt_s37 - metrics_texts, mt_s37_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_current_live
    .short METRIC_KIND_U64, METRIC_COND_ALTAIR
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s38 - metrics_texts, mt_s38_len, mt_s39 - metrics_texts, mt_s39_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_previous_live
    .short METRIC_KIND_U64, METRIC_COND_ALTAIR
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s40 - metrics_texts, mt_s40_len, mt_s41 - metrics_texts, mt_s41_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_pending_deposits
    .short METRIC_KIND_U64, METRIC_COND_ELECTRA
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s42 - metrics_texts, mt_s42_len, mt_s43 - metrics_texts, mt_s43_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_pending_partial_withdrawals
    .short METRIC_KIND_U64, METRIC_COND_ELECTRA
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s44 - metrics_texts, mt_s44_len, mt_s45 - metrics_texts, mt_s45_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_pending_consolidations
    .short METRIC_KIND_U64, METRIC_COND_ELECTRA
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s46 - metrics_texts, mt_s46_len, mt_s47 - metrics_texts, mt_s47_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_pending_exits
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s48 - metrics_texts, mt_s48_len, mt_s49 - metrics_texts, mt_s49_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_orphaned_blocks
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s50 - metrics_texts, mt_s50_len, mt_s51 - metrics_texts, mt_s51_len, METRIC_TYPE_GAUGE, METRIC_SRC_GOSSIP, 0
    .short METRIC_KIND_GOSSIP_MAIN, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s52 - metrics_texts, mt_s52_len, mt_s53 - metrics_texts, mt_s53_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_COUNTERS, NodeMetrics_attestation_delay
    .short METRIC_KIND_HIST, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long METRIC_BOUNDS_DELAY, 1
    .long mt_s54 - metrics_texts, mt_s54_len, mt_s55 - metrics_texts, mt_s55_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_local_validators
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s56 - metrics_texts, mt_s56_len, mt_s57 - metrics_texts, mt_s57_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_finalized_root
    .short METRIC_KIND_ROOT, METRIC_COND_STATE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s58 - metrics_texts, mt_s58_len, mt_s59 - metrics_texts, mt_s59_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_previous_justified_root
    .short METRIC_KIND_ROOT, METRIC_COND_STATE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s60 - metrics_texts, mt_s60_len, mt_s61 - metrics_texts, mt_s61_len, METRIC_TYPE_GAUGE, METRIC_SRC_COUNTERS, NodeMetrics_aggregates_received
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s62 - metrics_texts, mt_s62_len, mt_s63 - metrics_texts, mt_s63_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_COUNTERS, NodeMetrics_block_delay
    .short METRIC_KIND_HIST, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long METRIC_BOUNDS_DELAY, 1
    .long mt_s64 - metrics_texts, mt_s64_len, mt_s65 - metrics_texts, mt_s65_len, METRIC_TYPE_GAUGE, METRIC_SRC_COUNTERS, NodeMetrics_attester_slashings_received
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s66 - metrics_texts, mt_s66_len, mt_s67 - metrics_texts, mt_s67_len, METRIC_TYPE_GAUGE, METRIC_SRC_COUNTERS, NodeMetrics_blocks_proposed
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s68 - metrics_texts, mt_s68_len, mt_s69 - metrics_texts, mt_s69_len, METRIC_TYPE_GAUGE, METRIC_SRC_COUNTERS, NodeMetrics_attestations_published
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s70 - metrics_texts, mt_s70_len, mt_s71 - metrics_texts, mt_s71_len, METRIC_TYPE_GAUGE, METRIC_SRC_COUNTERS, NodeMetrics_gossip_blocks_imported
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s72 - metrics_texts, mt_s72_len, mt_s73 - metrics_texts, mt_s73_len, METRIC_TYPE_GAUGE, METRIC_SRC_COUNTERS, NodeMetrics_validation_failures
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s74 - metrics_texts, mt_s74_len, mt_s75 - metrics_texts, mt_s75_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_state_root
    .short METRIC_KIND_ROOT, METRIC_COND_STATE_ROOT
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s76 - metrics_texts, mt_s76_len, mt_s77 - metrics_texts, mt_s77_len, METRIC_TYPE_GAUGE, METRIC_SRC_COUNTERS, NodeMetrics_attestations_received
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s78 - metrics_texts, mt_s78_len, mt_s79 - metrics_texts, mt_s79_len, METRIC_TYPE_GAUGE, METRIC_SRC_COUNTERS, NodeMetrics_api_requests
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s80 - metrics_texts, mt_s80_len, mt_s81 - metrics_texts, mt_s81_len, METRIC_TYPE_GAUGE, METRIC_SRC_COUNTERS, NodeMetrics_api_successes
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s82 - metrics_texts, mt_s82_len, mt_s83 - metrics_texts, mt_s83_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_sync_state
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s84 - metrics_texts, mt_s84_len, mt_s85 - metrics_texts, mt_s85_len, METRIC_TYPE_GAUGE, METRIC_SRC_PROCESS, MetricsProcess_cpu_us
    .short METRIC_KIND_SECONDS, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s86 - metrics_texts, mt_s86_len, mt_s87 - metrics_texts, mt_s87_len, METRIC_TYPE_GAUGE, METRIC_SRC_PROCESS, MetricsProcess_max_fds
    .short METRIC_KIND_U64, METRIC_COND_MAX_FDS
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s88 - metrics_texts, mt_s88_len, mt_s89 - metrics_texts, mt_s89_len, METRIC_TYPE_COUNTER, METRIC_SRC_GOSSIP, 0
    .short METRIC_KIND_GOSSIP_SENT, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s90 - metrics_texts, mt_s90_len, mt_s91 - metrics_texts, mt_s91_len, METRIC_TYPE_GAUGE, METRIC_SRC_GOSSIP, 0
    .short METRIC_KIND_GOSSIP_MESH, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
metrics_table_end:
