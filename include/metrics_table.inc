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
    .ascii "lantern_network_peer_connected"
.set mt_s92_len, 30
mt_s93:
    .ascii "Connected peers"
.set mt_s93_len, 15
mt_s94:
    .ascii "lantern_network_peer_direction"
.set mt_s94_len, 30
mt_s95:
    .ascii "Connected peers by the direction of their connection"
.set mt_s95_len, 52
mt_s96:
    .ascii "lantern_network_peer_dialing"
.set mt_s96_len, 28
mt_s97:
    .ascii "Dials of the node not yet connected or failed"
.set mt_s97_len, 45
mt_s98:
    .ascii "lantern_network_peer_connections_total"
.set mt_s98_len, 38
mt_s99:
    .ascii "Connections made, by direction"
.set mt_s99_len, 30
mt_s100:
    .ascii "lantern_network_peer_dial_failures_total"
.set mt_s100_len, 40
mt_s101:
    .ascii "Dials that failed"
.set mt_s101_len, 17
mt_s102:
    .ascii "lantern_network_peer_disconnections_total"
.set mt_s102_len, 41
mt_s103:
    .ascii "Connections that closed"
.set mt_s103_len, 23
mt_s104:
    .ascii "lantern_network_discovery_records_total"
.set mt_s104_len, 39
mt_s105:
    .ascii "Node records discv5 found and gave to the node"
.set mt_s105_len, 46
mt_s106:
    .ascii "lantern_network_discovery_lookups_total"
.set mt_s106_len, 39
mt_s107:
    .ascii "Lookups the node asked discv5 for"
.set mt_s107_len, 33
mt_s108:
    .ascii "lantern_network_discovery_datagrams_received_total"
.set mt_s108_len, 50
mt_s109:
    .ascii "UDP datagrams discv5 received"
.set mt_s109_len, 29
mt_s110:
    .ascii "lantern_network_discovery_datagrams_sent_total"
.set mt_s110_len, 46
mt_s111:
    .ascii "UDP datagrams discv5 sent"
.set mt_s111_len, 25
mt_s112:
    .ascii "lantern_network_discovery_step_failures_total"
.set mt_s112_len, 45
mt_s113:
    .ascii "discv5 steps that failed"
.set mt_s113_len, 24
mt_s114:
    .ascii "lantern_network_transport_received_bytes_total"
.set mt_s114_len, 46
mt_s115:
    .ascii "Bytes received on libp2p connections"
.set mt_s115_len, 36
mt_s116:
    .ascii "lantern_network_transport_sent_bytes_total"
.set mt_s116_len, 42
mt_s117:
    .ascii "Bytes sent on libp2p connections"
.set mt_s117_len, 32
mt_s118:
    .ascii "lantern_network_gossip_messages_total"
.set mt_s118_len, 37
mt_s119:
    .ascii "Gossip messages validated, by topic and result"
.set mt_s119_len, 46
mt_s120:
    .ascii "lantern_network_gossip_messages_held"
.set mt_s120_len, 36
mt_s121:
    .ascii "Gossip messages the node holds"
.set mt_s121_len, 30
mt_s122:
    .ascii "lantern_network_reqresp_served_total"
.set mt_s122_len, 36
mt_s123:
    .ascii "Requests of peers the node served, by method"
.set mt_s123_len, 44
mt_s124:
    .ascii "lantern_network_reqresp_streams_open"
.set mt_s124_len, 36
mt_s125:
    .ascii "Request streams open"
.set mt_s125_len, 20
mt_s126:
    .ascii "lantern_processing_block_work_seconds"
.set mt_s126_len, 37
mt_s127:
    .ascii "Run time of each node work of the block stage, by work kind"
.set mt_s127_len, 59
mt_s128:
    .ascii "lantern_processing_block_work_failures_total"
.set mt_s128_len, 44
mt_s129:
    .ascii "Node works of the block stage whose result was not LANTERN_OK, by work kind"
.set mt_s129_len, 75
mt_s130:
    .ascii "lantern_processing_state_work_seconds"
.set mt_s130_len, 37
mt_s131:
    .ascii "Run time of each node work of the state stage, by work kind"
.set mt_s131_len, 59
mt_s132:
    .ascii "lantern_processing_state_work_failures_total"
.set mt_s132_len, 44
mt_s133:
    .ascii "Node works of the state stage whose result was not LANTERN_OK, by work kind"
.set mt_s133_len, 75
mt_s134:
    .ascii "lantern_processing_forkchoice_work_seconds"
.set mt_s134_len, 42
mt_s135:
    .ascii "Run time of each node work of the forkchoice stage, by work kind"
.set mt_s135_len, 64
mt_s136:
    .ascii "lantern_processing_forkchoice_work_failures_total"
.set mt_s136_len, 49
mt_s137:
    .ascii "Node works of the forkchoice stage whose result was not LANTERN_OK, by work kind"
.set mt_s137_len, 80
mt_s138:
    .ascii "lantern_processing_availability_work_seconds"
.set mt_s138_len, 44
mt_s139:
    .ascii "Run time of each node work of the availability stage, by work kind"
.set mt_s139_len, 66
mt_s140:
    .ascii "lantern_processing_availability_work_failures_total"
.set mt_s140_len, 51
mt_s141:
    .ascii "Node works of the availability stage whose result was not LANTERN_OK, by work kind"
.set mt_s141_len, 82
mt_s142:
    .ascii "lantern_processing_gossip_work_seconds"
.set mt_s142_len, 38
mt_s143:
    .ascii "Run time of each node work of the gossip stage, by work kind"
.set mt_s143_len, 60
mt_s144:
    .ascii "lantern_processing_gossip_work_failures_total"
.set mt_s144_len, 45
mt_s145:
    .ascii "Node works of the gossip stage whose result was not LANTERN_OK, by work kind"
.set mt_s145_len, 76
mt_s146:
    .ascii "lantern_processing_engine_work_seconds"
.set mt_s146_len, 38
mt_s147:
    .ascii "Run time of each node work of the engine stage, by work kind"
.set mt_s147_len, 60
mt_s148:
    .ascii "lantern_processing_engine_work_failures_total"
.set mt_s148_len, 45
mt_s149:
    .ascii "Node works of the engine stage whose result was not LANTERN_OK, by work kind"
.set mt_s149_len, 76
mt_s150:
    .ascii "lantern_processing_builder_work_seconds"
.set mt_s150_len, 39
mt_s151:
    .ascii "Run time of each node work of the builder stage, by work kind"
.set mt_s151_len, 61
mt_s152:
    .ascii "lantern_processing_builder_work_failures_total"
.set mt_s152_len, 46
mt_s153:
    .ascii "Node works of the builder stage whose result was not LANTERN_OK, by work kind"
.set mt_s153_len, 77
mt_s154:
    .ascii "lantern_processing_lightclient_work_seconds"
.set mt_s154_len, 43
mt_s155:
    .ascii "Run time of each node work of the lightclient stage, by work kind"
.set mt_s155_len, 65
mt_s156:
    .ascii "lantern_processing_lightclient_work_failures_total"
.set mt_s156_len, 50
mt_s157:
    .ascii "Node works of the lightclient stage whose result was not LANTERN_OK, by work kind"
.set mt_s157_len, 81
mt_s158:
    .ascii "lantern_processing_history_work_seconds"
.set mt_s158_len, 39
mt_s159:
    .ascii "Run time of each node work of the history stage, by work kind"
.set mt_s159_len, 61
mt_s160:
    .ascii "lantern_processing_history_work_failures_total"
.set mt_s160_len, 46
mt_s161:
    .ascii "Node works of the history stage whose result was not LANTERN_OK, by work kind"
.set mt_s161_len, 77
mt_s162:
    .ascii "lantern_processing_validator_work_seconds"
.set mt_s162_len, 41
mt_s163:
    .ascii "Run time of each node work of the validator stage, by work kind"
.set mt_s163_len, 63
mt_s164:
    .ascii "lantern_processing_validator_work_failures_total"
.set mt_s164_len, 48
mt_s165:
    .ascii "Node works of the validator stage whose result was not LANTERN_OK, by work kind"
.set mt_s165_len, 79
mt_s166:
    .ascii "lantern_processing_epoch_transitions_total"
.set mt_s166_len, 42
mt_s167:
    .ascii "Slot processing works that crossed an epoch boundary"
.set mt_s167_len, 52
mt_s168:
    .ascii "lantern_processing_epoch_slots_seconds"
.set mt_s168_len, 38
mt_s169:
    .ascii "Run time of each slot processing work that crossed an epoch boundary"
.set mt_s169_len, 68
mt_s170:
    .ascii "lantern_processing_gossip_validation_seconds"
.set mt_s170_len, 44
mt_s171:
    .ascii "Run time of each gossip validation, by topic"
.set mt_s171_len, 44
mt_s172:
    .ascii "lantern_node_resource_cpu_seconds_total"
.set mt_s172_len, 39
mt_s173:
    .ascii "User and system CPU time"
.set mt_s173_len, 24
mt_s174:
    .ascii "lantern_node_resource_max_resident_memory_bytes"
.set mt_s174_len, 47
mt_s175:
    .ascii "Highest resident memory since the start"
.set mt_s175_len, 39
mt_s176:
    .ascii "lantern_node_resource_max_fds"
.set mt_s176_len, 29
mt_s177:
    .ascii "The soft limit of open files"
.set mt_s177_len, 28
mt_s178:
    .ascii "lantern_node_resource_buffers"
.set mt_s178_len, 29
mt_s179:
    .ascii "Buffers the app holds for the node"
.set mt_s179_len, 34
mt_s180:
    .ascii "lantern_node_resource_buffer_bytes"
.set mt_s180_len, 34
mt_s181:
    .ascii "Bytes of those buffers"
.set mt_s181_len, 22
mt_s182:
    .ascii "lantern_node_resource_start_time_seconds"
.set mt_s182_len, 40
mt_s183:
    .ascii "Unix time of the start"
.set mt_s183_len, 22
mt_s184:
    .ascii "lantern_node_sync_head_slot"
.set mt_s184_len, 27
mt_s185:
    .ascii "Slot of the head block"
.set mt_s185_len, 22
mt_s186:
    .ascii "lantern_node_sync_store_slot"
.set mt_s186_len, 28
mt_s187:
    .ascii "Slot of the store's time"
.set mt_s187_len, 24
mt_s188:
    .ascii "lantern_node_sync_distance"
.set mt_s188_len, 26
mt_s189:
    .ascii "Slots from the head to the store's slot"
.set mt_s189_len, 39
mt_s190:
    .ascii "lantern_node_sync_state"
.set mt_s190_len, 23
mt_s191:
    .ascii "0 behind and not syncing, 1 synced, 2 syncing"
.set mt_s191_len, 45
mt_s192:
    .ascii "lantern_node_sync_earliest_slot"
.set mt_s192_len, 31
mt_s193:
    .ascii "First slot whose blocks the node serves"
.set mt_s193_len, 39
mt_s194:
    .ascii "lantern_node_sync_backfill_slot"
.set mt_s194_len, 31
mt_s195:
    .ascii "Slot below which the backfill looks for blocks"
.set mt_s195_len, 46
mt_s196:
    .ascii "lantern_node_sync_finalized_epoch"
.set mt_s196_len, 33
mt_s197:
    .ascii "The store's finalized epoch"
.set mt_s197_len, 27
mt_s198:
    .ascii "lantern_node_sync_justified_epoch"
.set mt_s198_len, 33
mt_s199:
    .ascii "The store's justified epoch"
.set mt_s199_len, 27
mt_s200:
    .ascii "lantern_node_health_uptime_seconds"
.set mt_s200_len, 34
mt_s201:
    .ascii "Time since the start"
.set mt_s201_len, 20
mt_s202:
    .ascii "lantern_node_health_execution_engine"
.set mt_s202_len, 36
mt_s203:
    .ascii "Connection to the execution engine: 0 none, 1 dialing, 2 open"
.set mt_s203_len, 61
mt_s204:
    .ascii "lantern_node_health_step_seconds"
.set mt_s204_len, 32
mt_s205:
    .ascii "Run time of each node step"
.set mt_s205_len, 26
mt_s206:
    .ascii "lantern_node_pool_operations"
.set mt_s206_len, 28
mt_s207:
    .ascii "Operations in the pool, by topic"
.set mt_s207_len, 32
mt_s208:
    .ascii "lantern_node_pool_proposers"
.set mt_s208_len, 27
mt_s209:
    .ascii "Validators with a fee recipient from prepareBeaconProposer"
.set mt_s209_len, 58
mt_s210:
    .ascii "lantern_node_log_lines_total"
.set mt_s210_len, 28
mt_s211:
    .ascii "Log lines written, by level"
.set mt_s211_len, 27
mt_s212:
    .ascii "lantern_node_api_requests_total"
.set mt_s212_len, 31
mt_s213:
    .ascii "Beacon API requests"
.set mt_s213_len, 19
mt_s214:
    .ascii "lantern_node_api_answers_total"
.set mt_s214_len, 30
mt_s215:
    .ascii "Beacon API answers, by status class"
.set mt_s215_len, 35
mt_s216:
    .ascii "lantern_node_api_connections_open"
.set mt_s216_len, 33
mt_s217:
    .ascii "Beacon API connections open"
.set mt_s217_len, 27
mt_s218:
    .ascii "lantern_node_storage_records_total"
.set mt_s218_len, 34
mt_s219:
    .ascii "Records appended to the history's segment files, by kind"
.set mt_s219_len, 56
mt_s220:
    .ascii "lantern_node_storage_record_bytes_total"
.set mt_s220_len, 39
mt_s221:
    .ascii "Bytes of those records"
.set mt_s221_len, 22
mt_s222:
    .ascii "lantern_node_storage_anchors_total"
.set mt_s222_len, 34
mt_s223:
    .ascii "Anchor states written for a restart"
.set mt_s223_len, 35
mt_s224:
    .ascii "lantern_node_storage_segments_dropped_total"
.set mt_s224_len, 43
mt_s225:
    .ascii "Segment files deleted"
.set mt_s225_len, 21
mt_s226:
    .ascii "lantern_node_storage_write_failures_total"
.set mt_s226_len, 41
mt_s227:
    .ascii "Writes to the data directory that failed"
.set mt_s227_len, 40
mt_s228:
    .ascii "status"
.set mt_s228_len, 6
mt_s229:
    .ascii "pending"
.set mt_s229_len, 7
mt_s230:
    .ascii "active"
.set mt_s230_len, 6
mt_s231:
    .ascii "exited"
.set mt_s231_len, 6
mt_s232:
    .ascii "withdrawable"
.set mt_s232_len, 12
mt_s233:
    .ascii "topic"
.set mt_s233_len, 5
mt_s234:
    .ascii "other"
.set mt_s234_len, 5
mt_s235:
    .ascii "beacon_block"
.set mt_s235_len, 12
mt_s236:
    .ascii "beacon_aggregate_and_proof"
.set mt_s236_len, 26
mt_s237:
    .ascii "beacon_attestation"
.set mt_s237_len, 18
mt_s238:
    .ascii "voluntary_exit"
.set mt_s238_len, 14
mt_s239:
    .ascii "proposer_slashing"
.set mt_s239_len, 17
mt_s240:
    .ascii "attester_slashing"
.set mt_s240_len, 17
mt_s241:
    .ascii "sync_committee_contribution_and_proof"
.set mt_s241_len, 37
mt_s242:
    .ascii "sync_committee"
.set mt_s242_len, 14
mt_s243:
    .ascii "bls_to_execution_change"
.set mt_s243_len, 23
mt_s244:
    .ascii "blob_sidecar"
.set mt_s244_len, 12
mt_s245:
    .ascii "data_column_sidecar"
.set mt_s245_len, 19
mt_s246:
    .ascii "light_client_finality_update"
.set mt_s246_len, 28
mt_s247:
    .ascii "light_client_optimistic_update"
.set mt_s247_len, 30
mt_s248:
    .ascii "result"
.set mt_s248_len, 6
mt_s249:
    .ascii "accept"
.set mt_s249_len, 6
mt_s250:
    .ascii "ignore"
.set mt_s250_len, 6
mt_s251:
    .ascii "reject"
.set mt_s251_len, 6
mt_s252:
    .ascii "method"
.set mt_s252_len, 6
mt_s253:
    .ascii "goodbye"
.set mt_s253_len, 7
mt_s254:
    .ascii "beacon_blocks_by_range"
.set mt_s254_len, 22
mt_s255:
    .ascii "beacon_blocks_by_root"
.set mt_s255_len, 21
mt_s256:
    .ascii "ping"
.set mt_s256_len, 4
mt_s257:
    .ascii "metadata"
.set mt_s257_len, 8
mt_s258:
    .ascii "blob_sidecars_by_range"
.set mt_s258_len, 22
mt_s259:
    .ascii "blob_sidecars_by_root"
.set mt_s259_len, 21
mt_s260:
    .ascii "data_column_sidecars_by_range"
.set mt_s260_len, 29
mt_s261:
    .ascii "data_column_sidecars_by_root"
.set mt_s261_len, 28
mt_s262:
    .ascii "beacon_blocks_by_head"
.set mt_s262_len, 21
mt_s263:
    .ascii "light_client_bootstrap"
.set mt_s263_len, 22
mt_s264:
    .ascii "light_client_updates_by_range"
.set mt_s264_len, 29
mt_s265:
    .ascii "direction"
.set mt_s265_len, 9
mt_s266:
    .ascii "inbound"
.set mt_s266_len, 7
mt_s267:
    .ascii "outbound"
.set mt_s267_len, 8
mt_s268:
    .ascii "level"
.set mt_s268_len, 5
mt_s269:
    .ascii "error"
.set mt_s269_len, 5
mt_s270:
    .ascii "warn"
.set mt_s270_len, 4
mt_s271:
    .ascii "info"
.set mt_s271_len, 4
mt_s272:
    .ascii "debug"
.set mt_s272_len, 5
mt_s273:
    .ascii "class"
.set mt_s273_len, 5
mt_s274:
    .ascii "2xx"
.set mt_s274_len, 3
mt_s275:
    .ascii "3xx"
.set mt_s275_len, 3
mt_s276:
    .ascii "4xx"
.set mt_s276_len, 3
mt_s277:
    .ascii "5xx"
.set mt_s277_len, 3
mt_s278:
    .ascii "kind"
.set mt_s278_len, 4
mt_s279:
    .ascii "block"
.set mt_s279_len, 5
mt_s280:
    .ascii "sidecar"
.set mt_s280_len, 7
mt_s281:
    .ascii "state"
.set mt_s281_len, 5
mt_s282:
    .ascii "work"
.set mt_s282_len, 4
mt_s283:
    .ascii "import_block"
.set mt_s283_len, 12
mt_s284:
    .ascii "sync_block"
.set mt_s284_len, 10
mt_s285:
    .ascii "block_attestation"
.set mt_s285_len, 17
mt_s286:
    .ascii "block_slashing"
.set mt_s286_len, 14
mt_s287:
    .ascii "replay"
.set mt_s287_len, 6
mt_s288:
    .ascii "justified_state"
.set mt_s288_len, 15
mt_s289:
    .ascii "target_state"
.set mt_s289_len, 12
mt_s290:
    .ascii "slots"
.set mt_s290_len, 5
mt_s291:
    .ascii "upgrade"
.set mt_s291_len, 7
mt_s292:
    .ascii "attestation"
.set mt_s292_len, 11
mt_s293:
    .ascii "gossip_vote"
.set mt_s293_len, 11
mt_s294:
    .ascii "blob"
.set mt_s294_len, 4
mt_s295:
    .ascii "reconstruct"
.set mt_s295_len, 11
mt_s296:
    .ascii "custody"
.set mt_s296_len, 7
mt_s297:
    .ascii "gossip"
.set mt_s297_len, 6
mt_s298:
    .ascii "new_payload"
.set mt_s298_len, 11
mt_s299:
    .ascii "forkchoice"
.set mt_s299_len, 10
mt_s300:
    .ascii "prepare_payload"
.set mt_s300_len, 15
mt_s301:
    .ascii "get_payload"
.set mt_s301_len, 11
mt_s302:
    .ascii "eth1_check"
.set mt_s302_len, 10
mt_s303:
    .ascii "produce_bid"
.set mt_s303_len, 11
mt_s304:
    .ascii "lc_block"
.set mt_s304_len, 8
mt_s305:
    .ascii "lc_head"
.set mt_s305_len, 7
mt_s306:
    .ascii "lc_serve"
.set mt_s306_len, 8
mt_s307:
    .ascii "lc_gossip"
.set mt_s307_len, 9
mt_s308:
    .ascii "lc_publish"
.set mt_s308_len, 10
mt_s309:
    .ascii "backfill"
.set mt_s309_len, 8
mt_s310:
    .ascii "archive_load"
.set mt_s310_len, 12
mt_s311:
    .ascii "serve"
.set mt_s311_len, 5
mt_s312:
    .ascii "api_encode"
.set mt_s312_len, 10
mt_s313:
    .ascii "api_chunk"
.set mt_s313_len, 9
mt_s314:
    .ascii "api_lookup"
.set mt_s314_len, 10
mt_s315:
    .ascii "api_event"
.set mt_s315_len, 9
mt_s316:
    .ascii "api_submit"
.set mt_s316_len, 10
mt_s317:
    .ascii "pool_check"
.set mt_s317_len, 10
mt_s318:
    .ascii "produce_check"
.set mt_s318_len, 13
mt_s319:
    .ascii "produce_fold"
.set mt_s319_len, 12
mt_s320:
    .ascii "produce_block"
.set mt_s320_len, 13
mt_s321:
    .ascii "publish_decode"
.set mt_s321_len, 14
mt_s322:
    .ascii "publish_sidecars"
.set mt_s322_len, 16
mt_s323:
    .ascii "publish_check"
.set mt_s323_len, 13
mt_s324:
    .ascii "publish_sidecar"
.set mt_s324_len, 15
mt_s325:
    .ascii "produce_eth1"
.set mt_s325_len, 12
mt_s326:
    .ascii "0.005"
.set mt_s326_len, 5
mt_s327:
    .ascii "0.01"
.set mt_s327_len, 4
mt_s328:
    .ascii "0.025"
.set mt_s328_len, 5
mt_s329:
    .ascii "0.05"
.set mt_s329_len, 4
mt_s330:
    .ascii "0.1"
.set mt_s330_len, 3
mt_s331:
    .ascii "0.25"
.set mt_s331_len, 4
mt_s332:
    .ascii "0.5"
.set mt_s332_len, 3
mt_s333:
    .ascii "1"
.set mt_s333_len, 1
mt_s334:
    .ascii "2.5"
.set mt_s334_len, 3
mt_s335:
    .ascii "5"
.set mt_s335_len, 1
mt_s336:
    .ascii "10"
.set mt_s336_len, 2
mt_s337:
    .ascii "0.002"
.set mt_s337_len, 5
mt_s338:
    .ascii "0.004"
.set mt_s338_len, 5
mt_s339:
    .ascii "0.008"
.set mt_s339_len, 5
mt_s340:
    .ascii "0.016"
.set mt_s340_len, 5
mt_s341:
    .ascii "0.032"
.set mt_s341_len, 5
mt_s342:
    .ascii "0.064"
.set mt_s342_len, 5
mt_s343:
    .ascii "0.128"
.set mt_s343_len, 5
mt_s344:
    .ascii "0.256"
.set mt_s344_len, 5
mt_s345:
    .ascii "0.512"
.set mt_s345_len, 5
mt_s346:
    .ascii "1.024"
.set mt_s346_len, 5
mt_s347:
    .ascii "2"
.set mt_s347_len, 1
mt_s348:
    .ascii "3"
.set mt_s348_len, 1
mt_s349:
    .ascii "4"
.set mt_s349_len, 1
mt_s350:
    .ascii "6"
.set mt_s350_len, 1
mt_s351:
    .ascii "8"
.set mt_s351_len, 1
mt_s352:
    .ascii "12"
.set mt_s352_len, 2
mt_s353:
    .ascii "24"
.set mt_s353_len, 2
mt_s354:
    .ascii "0.000001"
.set mt_s354_len, 8
mt_s355:
    .ascii "0.000004"
.set mt_s355_len, 8
mt_s356:
    .ascii "0.000016"
.set mt_s356_len, 8
mt_s357:
    .ascii "0.000064"
.set mt_s357_len, 8
mt_s358:
    .ascii "0.000256"
.set mt_s358_len, 8
mt_s359:
    .ascii "0.001"
.set mt_s359_len, 5
mt_s360:
    .ascii "0.00001"
.set mt_s360_len, 7
mt_s361:
    .ascii "0.0001"
.set mt_s361_len, 6
mt_s362:
    .ascii "0.0005"
.set mt_s362_len, 6
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
    .long mt_s228 - metrics_texts, mt_s228_len, 4, 0
    .long mt_s233 - metrics_texts, mt_s233_len, 14, 4
    .long mt_s248 - metrics_texts, mt_s248_len, 3, 18
    .long mt_s252 - metrics_texts, mt_s252_len, 16, 21
    .long mt_s265 - metrics_texts, mt_s265_len, 2, 37
    .long mt_s268 - metrics_texts, mt_s268_len, 4, 39
    .long mt_s273 - metrics_texts, mt_s273_len, 4, 43
    .long mt_s278 - metrics_texts, mt_s278_len, 3, 47
    .long mt_s282 - metrics_texts, mt_s282_len, 5, 50
    .long mt_s282 - metrics_texts, mt_s282_len, 4, 55
    .long mt_s282 - metrics_texts, mt_s282_len, 3, 59
    .long mt_s282 - metrics_texts, mt_s282_len, 3, 62
    .long mt_s282 - metrics_texts, mt_s282_len, 1, 65
    .long mt_s282 - metrics_texts, mt_s282_len, 5, 66
    .long mt_s282 - metrics_texts, mt_s282_len, 1, 71
    .long mt_s282 - metrics_texts, mt_s282_len, 5, 72
    .long mt_s282 - metrics_texts, mt_s282_len, 3, 77
    .long mt_s282 - metrics_texts, mt_s282_len, 14, 80
metrics_label_values:            /* text offset, length */
    .long mt_s229 - metrics_texts, mt_s229_len
    .long mt_s230 - metrics_texts, mt_s230_len
    .long mt_s231 - metrics_texts, mt_s231_len
    .long mt_s232 - metrics_texts, mt_s232_len
    .long mt_s234 - metrics_texts, mt_s234_len
    .long mt_s235 - metrics_texts, mt_s235_len
    .long mt_s236 - metrics_texts, mt_s236_len
    .long mt_s237 - metrics_texts, mt_s237_len
    .long mt_s238 - metrics_texts, mt_s238_len
    .long mt_s239 - metrics_texts, mt_s239_len
    .long mt_s240 - metrics_texts, mt_s240_len
    .long mt_s241 - metrics_texts, mt_s241_len
    .long mt_s242 - metrics_texts, mt_s242_len
    .long mt_s243 - metrics_texts, mt_s243_len
    .long mt_s244 - metrics_texts, mt_s244_len
    .long mt_s245 - metrics_texts, mt_s245_len
    .long mt_s246 - metrics_texts, mt_s246_len
    .long mt_s247 - metrics_texts, mt_s247_len
    .long mt_s249 - metrics_texts, mt_s249_len
    .long mt_s250 - metrics_texts, mt_s250_len
    .long mt_s251 - metrics_texts, mt_s251_len
    .long mt_s234 - metrics_texts, mt_s234_len
    .long mt_s228 - metrics_texts, mt_s228_len
    .long mt_s253 - metrics_texts, mt_s253_len
    .long mt_s254 - metrics_texts, mt_s254_len
    .long mt_s255 - metrics_texts, mt_s255_len
    .long mt_s256 - metrics_texts, mt_s256_len
    .long mt_s257 - metrics_texts, mt_s257_len
    .long mt_s258 - metrics_texts, mt_s258_len
    .long mt_s259 - metrics_texts, mt_s259_len
    .long mt_s260 - metrics_texts, mt_s260_len
    .long mt_s261 - metrics_texts, mt_s261_len
    .long mt_s262 - metrics_texts, mt_s262_len
    .long mt_s263 - metrics_texts, mt_s263_len
    .long mt_s264 - metrics_texts, mt_s264_len
    .long mt_s246 - metrics_texts, mt_s246_len
    .long mt_s247 - metrics_texts, mt_s247_len
    .long mt_s266 - metrics_texts, mt_s266_len
    .long mt_s267 - metrics_texts, mt_s267_len
    .long mt_s269 - metrics_texts, mt_s269_len
    .long mt_s270 - metrics_texts, mt_s270_len
    .long mt_s271 - metrics_texts, mt_s271_len
    .long mt_s272 - metrics_texts, mt_s272_len
    .long mt_s274 - metrics_texts, mt_s274_len
    .long mt_s275 - metrics_texts, mt_s275_len
    .long mt_s276 - metrics_texts, mt_s276_len
    .long mt_s277 - metrics_texts, mt_s277_len
    .long mt_s279 - metrics_texts, mt_s279_len
    .long mt_s280 - metrics_texts, mt_s280_len
    .long mt_s281 - metrics_texts, mt_s281_len
    .long mt_s283 - metrics_texts, mt_s283_len
    .long mt_s284 - metrics_texts, mt_s284_len
    .long mt_s285 - metrics_texts, mt_s285_len
    .long mt_s286 - metrics_texts, mt_s286_len
    .long mt_s287 - metrics_texts, mt_s287_len
    .long mt_s288 - metrics_texts, mt_s288_len
    .long mt_s289 - metrics_texts, mt_s289_len
    .long mt_s290 - metrics_texts, mt_s290_len
    .long mt_s291 - metrics_texts, mt_s291_len
    .long mt_s292 - metrics_texts, mt_s292_len
    .long mt_s240 - metrics_texts, mt_s240_len
    .long mt_s293 - metrics_texts, mt_s293_len
    .long mt_s294 - metrics_texts, mt_s294_len
    .long mt_s295 - metrics_texts, mt_s295_len
    .long mt_s296 - metrics_texts, mt_s296_len
    .long mt_s297 - metrics_texts, mt_s297_len
    .long mt_s298 - metrics_texts, mt_s298_len
    .long mt_s299 - metrics_texts, mt_s299_len
    .long mt_s300 - metrics_texts, mt_s300_len
    .long mt_s301 - metrics_texts, mt_s301_len
    .long mt_s302 - metrics_texts, mt_s302_len
    .long mt_s303 - metrics_texts, mt_s303_len
    .long mt_s304 - metrics_texts, mt_s304_len
    .long mt_s305 - metrics_texts, mt_s305_len
    .long mt_s306 - metrics_texts, mt_s306_len
    .long mt_s307 - metrics_texts, mt_s307_len
    .long mt_s308 - metrics_texts, mt_s308_len
    .long mt_s309 - metrics_texts, mt_s309_len
    .long mt_s310 - metrics_texts, mt_s310_len
    .long mt_s311 - metrics_texts, mt_s311_len
    .long mt_s312 - metrics_texts, mt_s312_len
    .long mt_s313 - metrics_texts, mt_s313_len
    .long mt_s314 - metrics_texts, mt_s314_len
    .long mt_s315 - metrics_texts, mt_s315_len
    .long mt_s316 - metrics_texts, mt_s316_len
    .long mt_s317 - metrics_texts, mt_s317_len
    .long mt_s318 - metrics_texts, mt_s318_len
    .long mt_s319 - metrics_texts, mt_s319_len
    .long mt_s320 - metrics_texts, mt_s320_len
    .long mt_s321 - metrics_texts, mt_s321_len
    .long mt_s322 - metrics_texts, mt_s322_len
    .long mt_s323 - metrics_texts, mt_s323_len
    .long mt_s324 - metrics_texts, mt_s324_len
    .long mt_s325 - metrics_texts, mt_s325_len
    .p2align 3
metrics_bounds:                  /* by METRIC_BOUNDS_*: count, unit, first bound */
    .long 11, 0, 0, 0
    .long 10, 0, 11, 0
    .long 9, 0, 21, 0
    .long 11, 1, 30, 0
    .long 11, 0, 41, 0
metrics_bound_values:            /* microseconds (or the Profile's bound index), text offset, length */
    .quad 5000
    .long mt_s326 - metrics_texts, mt_s326_len
    .quad 10000
    .long mt_s327 - metrics_texts, mt_s327_len
    .quad 25000
    .long mt_s328 - metrics_texts, mt_s328_len
    .quad 50000
    .long mt_s329 - metrics_texts, mt_s329_len
    .quad 100000
    .long mt_s330 - metrics_texts, mt_s330_len
    .quad 250000
    .long mt_s331 - metrics_texts, mt_s331_len
    .quad 500000
    .long mt_s332 - metrics_texts, mt_s332_len
    .quad 1000000
    .long mt_s333 - metrics_texts, mt_s333_len
    .quad 2500000
    .long mt_s334 - metrics_texts, mt_s334_len
    .quad 5000000
    .long mt_s335 - metrics_texts, mt_s335_len
    .quad 10000000
    .long mt_s336 - metrics_texts, mt_s336_len
    .quad 2000
    .long mt_s337 - metrics_texts, mt_s337_len
    .quad 4000
    .long mt_s338 - metrics_texts, mt_s338_len
    .quad 8000
    .long mt_s339 - metrics_texts, mt_s339_len
    .quad 16000
    .long mt_s340 - metrics_texts, mt_s340_len
    .quad 32000
    .long mt_s341 - metrics_texts, mt_s341_len
    .quad 64000
    .long mt_s342 - metrics_texts, mt_s342_len
    .quad 128000
    .long mt_s343 - metrics_texts, mt_s343_len
    .quad 256000
    .long mt_s344 - metrics_texts, mt_s344_len
    .quad 512000
    .long mt_s345 - metrics_texts, mt_s345_len
    .quad 1024000
    .long mt_s346 - metrics_texts, mt_s346_len
    .quad 500000
    .long mt_s332 - metrics_texts, mt_s332_len
    .quad 1000000
    .long mt_s333 - metrics_texts, mt_s333_len
    .quad 2000000
    .long mt_s347 - metrics_texts, mt_s347_len
    .quad 3000000
    .long mt_s348 - metrics_texts, mt_s348_len
    .quad 4000000
    .long mt_s349 - metrics_texts, mt_s349_len
    .quad 6000000
    .long mt_s350 - metrics_texts, mt_s350_len
    .quad 8000000
    .long mt_s351 - metrics_texts, mt_s351_len
    .quad 12000000
    .long mt_s352 - metrics_texts, mt_s352_len
    .quad 24000000
    .long mt_s353 - metrics_texts, mt_s353_len
    .quad 0
    .long mt_s354 - metrics_texts, mt_s354_len
    .quad 1
    .long mt_s355 - metrics_texts, mt_s355_len
    .quad 2
    .long mt_s356 - metrics_texts, mt_s356_len
    .quad 3
    .long mt_s357 - metrics_texts, mt_s357_len
    .quad 4
    .long mt_s358 - metrics_texts, mt_s358_len
    .quad 5
    .long mt_s359 - metrics_texts, mt_s359_len
    .quad 6
    .long mt_s338 - metrics_texts, mt_s338_len
    .quad 7
    .long mt_s340 - metrics_texts, mt_s340_len
    .quad 8
    .long mt_s342 - metrics_texts, mt_s342_len
    .quad 9
    .long mt_s344 - metrics_texts, mt_s344_len
    .quad 10
    .long mt_s333 - metrics_texts, mt_s333_len
    .quad 10
    .long mt_s360 - metrics_texts, mt_s360_len
    .quad 100
    .long mt_s361 - metrics_texts, mt_s361_len
    .quad 500
    .long mt_s362 - metrics_texts, mt_s362_len
    .quad 1000
    .long mt_s359 - metrics_texts, mt_s359_len
    .quad 5000
    .long mt_s326 - metrics_texts, mt_s326_len
    .quad 10000
    .long mt_s327 - metrics_texts, mt_s327_len
    .quad 50000
    .long mt_s329 - metrics_texts, mt_s329_len
    .quad 100000
    .long mt_s330 - metrics_texts, mt_s330_len
    .quad 500000
    .long mt_s332 - metrics_texts, mt_s332_len
    .quad 1000000
    .long mt_s333 - metrics_texts, mt_s333_len
    .quad 5000000
    .long mt_s335 - metrics_texts, mt_s335_len
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
    .long mt_s16 - metrics_texts, mt_s16_len, mt_s17 - metrics_texts, mt_s17_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_column_requests
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s18 - metrics_texts, mt_s18_len, mt_s19 - metrics_texts, mt_s19_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_column_successes
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s20 - metrics_texts, mt_s20_len, mt_s21 - metrics_texts, mt_s21_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_gossip_verification
    .short METRIC_KIND_HIST, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long METRIC_BOUNDS_DEFAULT, 1
    .long mt_s22 - metrics_texts, mt_s22_len, mt_s23 - metrics_texts, mt_s23_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_reconstructed_columns
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
    .long mt_s52 - metrics_texts, mt_s52_len, mt_s53 - metrics_texts, mt_s53_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_attestation_delay
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
    .long mt_s60 - metrics_texts, mt_s60_len, mt_s61 - metrics_texts, mt_s61_len, METRIC_TYPE_GAUGE, METRIC_SRC_APP, AppMetrics_aggregates_received
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s62 - metrics_texts, mt_s62_len, mt_s63 - metrics_texts, mt_s63_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_block_delay
    .short METRIC_KIND_HIST, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long METRIC_BOUNDS_DELAY, 1
    .long mt_s64 - metrics_texts, mt_s64_len, mt_s65 - metrics_texts, mt_s65_len, METRIC_TYPE_GAUGE, METRIC_SRC_APP, AppMetrics_attester_slashings_received
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s66 - metrics_texts, mt_s66_len, mt_s67 - metrics_texts, mt_s67_len, METRIC_TYPE_GAUGE, METRIC_SRC_APP, AppMetrics_blocks_proposed
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s68 - metrics_texts, mt_s68_len, mt_s69 - metrics_texts, mt_s69_len, METRIC_TYPE_GAUGE, METRIC_SRC_COUNTERS, NodeMetrics_attestations_published
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s70 - metrics_texts, mt_s70_len, mt_s71 - metrics_texts, mt_s71_len, METRIC_TYPE_GAUGE, METRIC_SRC_APP, AppMetrics_gossip_blocks_imported
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s72 - metrics_texts, mt_s72_len, mt_s73 - metrics_texts, mt_s73_len, METRIC_TYPE_GAUGE, METRIC_SRC_APP, AppMetrics_validation_failures
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s74 - metrics_texts, mt_s74_len, mt_s75 - metrics_texts, mt_s75_len, METRIC_TYPE_GAUGE, METRIC_SRC_STATE, MetricsState_state_root
    .short METRIC_KIND_ROOT, METRIC_COND_STATE_ROOT
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s76 - metrics_texts, mt_s76_len, mt_s77 - metrics_texts, mt_s77_len, METRIC_TYPE_GAUGE, METRIC_SRC_APP, AppMetrics_attestations_received
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s78 - metrics_texts, mt_s78_len, mt_s79 - metrics_texts, mt_s79_len, METRIC_TYPE_GAUGE, METRIC_SRC_APP, AppMetrics_api_requests
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_BEACON
    .short 0, 0
    .long 0, 1
    .long mt_s80 - metrics_texts, mt_s80_len, mt_s81 - metrics_texts, mt_s81_len, METRIC_TYPE_GAUGE, METRIC_SRC_APP, AppMetrics_api_successes
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
    .long mt_s92 - metrics_texts, mt_s92_len, mt_s93 - metrics_texts, mt_s93_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_peers
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_PEER
    .short 0, 0
    .long 0, 1
    .long mt_s94 - metrics_texts, mt_s94_len, mt_s95 - metrics_texts, mt_s95_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_peer_directions
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_PEER
    .short 5, 0
    .long 0, 2
    .long mt_s96 - metrics_texts, mt_s96_len, mt_s97 - metrics_texts, mt_s97_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_dialing
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_PEER
    .short 0, 0
    .long 0, 1
    .long mt_s98 - metrics_texts, mt_s98_len, mt_s99 - metrics_texts, mt_s99_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_connections
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_PEER
    .short 5, 0
    .long 0, 2
    .long mt_s100 - metrics_texts, mt_s100_len, mt_s101 - metrics_texts, mt_s101_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_dial_failures
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_PEER
    .short 0, 0
    .long 0, 1
    .long mt_s102 - metrics_texts, mt_s102_len, mt_s103 - metrics_texts, mt_s103_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_closed
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_PEER
    .short 0, 0
    .long 0, 1
    .long mt_s104 - metrics_texts, mt_s104_len, mt_s105 - metrics_texts, mt_s105_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_records
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_DISCOVERY
    .short 0, 0
    .long 0, 1
    .long mt_s106 - metrics_texts, mt_s106_len, mt_s107 - metrics_texts, mt_s107_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_lookups
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_DISCOVERY
    .short 0, 0
    .long 0, 1
    .long mt_s108 - metrics_texts, mt_s108_len, mt_s109 - metrics_texts, mt_s109_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_dv_in
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_DISCOVERY
    .short 0, 0
    .long 0, 1
    .long mt_s110 - metrics_texts, mt_s110_len, mt_s111 - metrics_texts, mt_s111_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_dv_out
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_DISCOVERY
    .short 0, 0
    .long 0, 1
    .long mt_s112 - metrics_texts, mt_s112_len, mt_s113 - metrics_texts, mt_s113_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_dv_failures
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_DISCOVERY
    .short 0, 0
    .long 0, 1
    .long mt_s114 - metrics_texts, mt_s114_len, mt_s115 - metrics_texts, mt_s115_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_rx_bytes
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_TRANSPORT
    .short 0, 0
    .long 0, 1
    .long mt_s116 - metrics_texts, mt_s116_len, mt_s117 - metrics_texts, mt_s117_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_tx_bytes
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_TRANSPORT
    .short 0, 0
    .long 0, 1
    .long mt_s118 - metrics_texts, mt_s118_len, mt_s119 - metrics_texts, mt_s119_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_gossip_results
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_GOSSIP
    .short 2, 3
    .long 0, 42
    .long mt_s120 - metrics_texts, mt_s120_len, mt_s121 - metrics_texts, mt_s121_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_messages
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_GOSSIP
    .short 0, 0
    .long 0, 1
    .long mt_s122 - metrics_texts, mt_s122_len, mt_s123 - metrics_texts, mt_s123_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_served
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_REQRESP
    .short 4, 0
    .long 0, 16
    .long mt_s124 - metrics_texts, mt_s124_len, mt_s125 - metrics_texts, mt_s125_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_streams
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NETWORK_REQRESP
    .short 0, 0
    .long 0, 1
    .long mt_s126 - metrics_texts, mt_s126_len, mt_s127 - metrics_texts, mt_s127_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_work_seconds
    .short METRIC_KIND_ARRAY_HIST, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_BLOCK
    .short 9, 0
    .long METRIC_BOUNDS_WORK, 5
    .long mt_s128 - metrics_texts, mt_s128_len, mt_s129 - metrics_texts, mt_s129_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_work_failures
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_BLOCK
    .short 9, 0
    .long 0, 5
    .long mt_s130 - metrics_texts, mt_s130_len, mt_s131 - metrics_texts, mt_s131_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_work_seconds + 560
    .short METRIC_KIND_ARRAY_HIST, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_STATE
    .short 10, 0
    .long METRIC_BOUNDS_WORK, 4
    .long mt_s132 - metrics_texts, mt_s132_len, mt_s133 - metrics_texts, mt_s133_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_work_failures + 40
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_STATE
    .short 10, 0
    .long 0, 4
    .long mt_s134 - metrics_texts, mt_s134_len, mt_s135 - metrics_texts, mt_s135_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_work_seconds + 1008
    .short METRIC_KIND_ARRAY_HIST, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_FORKCHOICE
    .short 11, 0
    .long METRIC_BOUNDS_WORK, 3
    .long mt_s136 - metrics_texts, mt_s136_len, mt_s137 - metrics_texts, mt_s137_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_work_failures + 72
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_FORKCHOICE
    .short 11, 0
    .long 0, 3
    .long mt_s138 - metrics_texts, mt_s138_len, mt_s139 - metrics_texts, mt_s139_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_work_seconds + 1344
    .short METRIC_KIND_ARRAY_HIST, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_AVAILABILITY
    .short 12, 0
    .long METRIC_BOUNDS_WORK, 3
    .long mt_s140 - metrics_texts, mt_s140_len, mt_s141 - metrics_texts, mt_s141_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_work_failures + 96
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_AVAILABILITY
    .short 12, 0
    .long 0, 3
    .long mt_s142 - metrics_texts, mt_s142_len, mt_s143 - metrics_texts, mt_s143_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_work_seconds + 1680
    .short METRIC_KIND_ARRAY_HIST, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_GOSSIP
    .short 13, 0
    .long METRIC_BOUNDS_WORK, 1
    .long mt_s144 - metrics_texts, mt_s144_len, mt_s145 - metrics_texts, mt_s145_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_work_failures + 120
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_GOSSIP
    .short 13, 0
    .long 0, 1
    .long mt_s146 - metrics_texts, mt_s146_len, mt_s147 - metrics_texts, mt_s147_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_work_seconds + 1792
    .short METRIC_KIND_ARRAY_HIST, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_ENGINE
    .short 14, 0
    .long METRIC_BOUNDS_WORK, 5
    .long mt_s148 - metrics_texts, mt_s148_len, mt_s149 - metrics_texts, mt_s149_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_work_failures + 128
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_ENGINE
    .short 14, 0
    .long 0, 5
    .long mt_s150 - metrics_texts, mt_s150_len, mt_s151 - metrics_texts, mt_s151_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_work_seconds + 2352
    .short METRIC_KIND_ARRAY_HIST, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_BUILDER
    .short 15, 0
    .long METRIC_BOUNDS_WORK, 1
    .long mt_s152 - metrics_texts, mt_s152_len, mt_s153 - metrics_texts, mt_s153_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_work_failures + 168
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_BUILDER
    .short 15, 0
    .long 0, 1
    .long mt_s154 - metrics_texts, mt_s154_len, mt_s155 - metrics_texts, mt_s155_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_work_seconds + 2464
    .short METRIC_KIND_ARRAY_HIST, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_LIGHTCLIENT
    .short 16, 0
    .long METRIC_BOUNDS_WORK, 5
    .long mt_s156 - metrics_texts, mt_s156_len, mt_s157 - metrics_texts, mt_s157_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_work_failures + 176
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_LIGHTCLIENT
    .short 16, 0
    .long 0, 5
    .long mt_s158 - metrics_texts, mt_s158_len, mt_s159 - metrics_texts, mt_s159_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_work_seconds + 3024
    .short METRIC_KIND_ARRAY_HIST, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_HISTORY
    .short 17, 0
    .long METRIC_BOUNDS_WORK, 3
    .long mt_s160 - metrics_texts, mt_s160_len, mt_s161 - metrics_texts, mt_s161_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_work_failures + 216
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_HISTORY
    .short 17, 0
    .long 0, 3
    .long mt_s162 - metrics_texts, mt_s162_len, mt_s163 - metrics_texts, mt_s163_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_work_seconds + 3360
    .short METRIC_KIND_ARRAY_HIST, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_VALIDATOR
    .short 18, 0
    .long METRIC_BOUNDS_WORK, 14
    .long mt_s164 - metrics_texts, mt_s164_len, mt_s165 - metrics_texts, mt_s165_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_work_failures + 240
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_VALIDATOR
    .short 18, 0
    .long 0, 14
    .long mt_s166 - metrics_texts, mt_s166_len, mt_s167 - metrics_texts, mt_s167_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_epoch_transitions
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_EPOCH
    .short 0, 0
    .long 0, 1
    .long mt_s168 - metrics_texts, mt_s168_len, mt_s169 - metrics_texts, mt_s169_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_epoch_seconds
    .short METRIC_KIND_HIST, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_EPOCH
    .short 0, 0
    .long METRIC_BOUNDS_WORK, 1
    .long mt_s170 - metrics_texts, mt_s170_len, mt_s171 - metrics_texts, mt_s171_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_gossip_seconds
    .short METRIC_KIND_ARRAY_HIST, METRIC_COND_NONE
    .long METRIC_BIT_PROCESSING_GOSSIP
    .short 2, 0
    .long METRIC_BOUNDS_WORK, 14
    .long mt_s172 - metrics_texts, mt_s172_len, mt_s173 - metrics_texts, mt_s173_len, METRIC_TYPE_COUNTER, METRIC_SRC_PROCESS, MetricsProcess_cpu_us
    .short METRIC_KIND_SECONDS, METRIC_COND_NONE
    .long METRIC_BIT_NODE_RESOURCE
    .short 0, 0
    .long 0, 1
    .long mt_s174 - metrics_texts, mt_s174_len, mt_s175 - metrics_texts, mt_s175_len, METRIC_TYPE_GAUGE, METRIC_SRC_PROCESS, MetricsProcess_max_rss_bytes
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_RESOURCE
    .short 0, 0
    .long 0, 1
    .long mt_s176 - metrics_texts, mt_s176_len, mt_s177 - metrics_texts, mt_s177_len, METRIC_TYPE_GAUGE, METRIC_SRC_PROCESS, MetricsProcess_max_fds
    .short METRIC_KIND_U64, METRIC_COND_MAX_FDS
    .long METRIC_BIT_NODE_RESOURCE
    .short 0, 0
    .long 0, 1
    .long mt_s178 - metrics_texts, mt_s178_len, mt_s179 - metrics_texts, mt_s179_len, METRIC_TYPE_GAUGE, METRIC_SRC_PROCESS, MetricsProcess_buffers
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_RESOURCE
    .short 0, 0
    .long 0, 1
    .long mt_s180 - metrics_texts, mt_s180_len, mt_s181 - metrics_texts, mt_s181_len, METRIC_TYPE_GAUGE, METRIC_SRC_PROCESS, MetricsProcess_buffer_bytes
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_RESOURCE
    .short 0, 0
    .long 0, 1
    .long mt_s182 - metrics_texts, mt_s182_len, mt_s183 - metrics_texts, mt_s183_len, METRIC_TYPE_GAUGE, METRIC_SRC_PROCESS, MetricsProcess_start_s
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_RESOURCE
    .short 0, 0
    .long 0, 1
    .long mt_s184 - metrics_texts, mt_s184_len, mt_s185 - metrics_texts, mt_s185_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_head_slot
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_SYNC
    .short 0, 0
    .long 0, 1
    .long mt_s186 - metrics_texts, mt_s186_len, mt_s187 - metrics_texts, mt_s187_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_store_slot
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_SYNC
    .short 0, 0
    .long 0, 1
    .long mt_s188 - metrics_texts, mt_s188_len, mt_s189 - metrics_texts, mt_s189_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_distance
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_SYNC
    .short 0, 0
    .long 0, 1
    .long mt_s190 - metrics_texts, mt_s190_len, mt_s191 - metrics_texts, mt_s191_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_sync_state
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_SYNC
    .short 0, 0
    .long 0, 1
    .long mt_s192 - metrics_texts, mt_s192_len, mt_s193 - metrics_texts, mt_s193_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_earliest_slot
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_SYNC
    .short 0, 0
    .long 0, 1
    .long mt_s194 - metrics_texts, mt_s194_len, mt_s195 - metrics_texts, mt_s195_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_backfill_slot
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_SYNC
    .short 0, 0
    .long 0, 1
    .long mt_s196 - metrics_texts, mt_s196_len, mt_s197 - metrics_texts, mt_s197_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_finalized_epoch
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_SYNC
    .short 0, 0
    .long 0, 1
    .long mt_s198 - metrics_texts, mt_s198_len, mt_s199 - metrics_texts, mt_s199_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_justified_epoch
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_SYNC
    .short 0, 0
    .long 0, 1
    .long mt_s200 - metrics_texts, mt_s200_len, mt_s201 - metrics_texts, mt_s201_len, METRIC_TYPE_GAUGE, METRIC_SRC_PROCESS, MetricsProcess_uptime_us
    .short METRIC_KIND_SECONDS, METRIC_COND_NONE
    .long METRIC_BIT_NODE_HEALTH
    .short 0, 0
    .long 0, 1
    .long mt_s202 - metrics_texts, mt_s202_len, mt_s203 - metrics_texts, mt_s203_len, METRIC_TYPE_GAUGE, METRIC_SRC_PROCESS, MetricsProcess_engine
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_HEALTH
    .short 0, 0
    .long 0, 1
    .long mt_s204 - metrics_texts, mt_s204_len, mt_s205 - metrics_texts, mt_s205_len, METRIC_TYPE_HISTOGRAM, METRIC_SRC_APP, AppMetrics_step_seconds
    .short METRIC_KIND_HIST, METRIC_COND_NONE
    .long METRIC_BIT_NODE_HEALTH
    .short 0, 0
    .long METRIC_BOUNDS_WORK, 1
    .long mt_s206 - metrics_texts, mt_s206_len, mt_s207 - metrics_texts, mt_s207_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_pool
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_NODE_POOL
    .short 2, 0
    .long 0, 14
    .long mt_s208 - metrics_texts, mt_s208_len, mt_s209 - metrics_texts, mt_s209_len, METRIC_TYPE_GAUGE, METRIC_SRC_NODE, MetricsNode_local_validators
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_POOL
    .short 0, 0
    .long 0, 1
    .long mt_s210 - metrics_texts, mt_s210_len, mt_s211 - metrics_texts, mt_s211_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_log_lines
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_NODE_LOG
    .short 6, 0
    .long 0, 4
    .long mt_s212 - metrics_texts, mt_s212_len, mt_s213 - metrics_texts, mt_s213_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_api_requests
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_API
    .short 0, 0
    .long 0, 1
    .long mt_s214 - metrics_texts, mt_s214_len, mt_s215 - metrics_texts, mt_s215_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_api_classes
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_NODE_API
    .short 7, 0
    .long 0, 4
    .long mt_s216 - metrics_texts, mt_s216_len, mt_s217 - metrics_texts, mt_s217_len, METRIC_TYPE_GAUGE, METRIC_SRC_PROCESS, MetricsProcess_api_open
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_API
    .short 0, 0
    .long 0, 1
    .long mt_s218 - metrics_texts, mt_s218_len, mt_s219 - metrics_texts, mt_s219_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_db_records
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_NODE_STORAGE
    .short 8, 0
    .long 0, 3
    .long mt_s220 - metrics_texts, mt_s220_len, mt_s221 - metrics_texts, mt_s221_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_db_bytes
    .short METRIC_KIND_ARRAY, METRIC_COND_NONE
    .long METRIC_BIT_NODE_STORAGE
    .short 8, 0
    .long 0, 3
    .long mt_s222 - metrics_texts, mt_s222_len, mt_s223 - metrics_texts, mt_s223_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_db_anchors
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_STORAGE
    .short 0, 0
    .long 0, 1
    .long mt_s224 - metrics_texts, mt_s224_len, mt_s225 - metrics_texts, mt_s225_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_db_drops
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_STORAGE
    .short 0, 0
    .long 0, 1
    .long mt_s226 - metrics_texts, mt_s226_len, mt_s227 - metrics_texts, mt_s227_len, METRIC_TYPE_COUNTER, METRIC_SRC_APP, AppMetrics_db_failures
    .short METRIC_KIND_U64, METRIC_COND_NONE
    .long METRIC_BIT_NODE_STORAGE
    .short 0, 0
    .long 0, 1
metrics_table_end:
