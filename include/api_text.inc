/*
 * The text of lantern_api_answer (docs/reference/beacon-api.md), in RODATA: each label with its
 * length in bytes as <label>_len. The same on every ISA.
 */
api_crlf:
    .ascii "\r\n"
.set api_crlf_len, 2
api_end_head:
    .ascii "\r\n\r\n"
.set api_end_head_len, 4
api_http:
    .ascii "HTTP/1.1 "
.set api_http_len, 9
api_r200:
    .ascii " OK"
.set api_r200_len, 3
api_r206:
    .ascii " Partial Content"
.set api_r206_len, 16
api_r400:
    .ascii " Bad Request"
.set api_r400_len, 12
api_r404:
    .ascii " Not Found"
.set api_r404_len, 10
api_r405:
    .ascii " Method Not Allowed"
.set api_r405_len, 19
api_rnone:
    .ascii " "
.set api_rnone_len, 1
api_type:
    .ascii "\r\nContent-Type: application/json"
.set api_type_len, 32
api_length:
    .ascii "\r\nContent-Length: "
.set api_length_len, 18
api_close:
    .ascii "\r\nConnection: close\r\n\r\n"
.set api_close_len, 23
api_get:
    .ascii "GET"
.set api_get_len, 3
api_version_prefix:
    .ascii " HTTP/1."
.set api_version_prefix_len, 8
api_p_health:
    .ascii "/eth/v1/node/health"
.set api_p_health_len, 19
api_p_identity:
    .ascii "/eth/v1/node/identity"
.set api_p_identity_len, 21
api_p_version:
    .ascii "/eth/v1/node/version"
.set api_p_version_len, 20
api_p_syncing:
    .ascii "/eth/v1/node/syncing"
.set api_p_syncing_len, 20
api_p_peer_count:
    .ascii "/eth/v1/node/peer_count"
.set api_p_peer_count_len, 23
api_p_genesis:
    .ascii "/eth/v1/beacon/genesis"
.set api_p_genesis_len, 22
api_p_headers:
    .ascii "/eth/v1/beacon/headers/"
.set api_p_headers_len, 23
api_p_finality:
    .ascii "/eth/v1/beacon/states/head/finality_checkpoints"
.set api_p_finality_len, 47
api_q_status:
    .ascii "syncing_status="
.set api_q_status_len, 15
api_head:
    .ascii "head"
.set api_head_len, 4
api_e_code:
    .ascii "{\"code\":"
.set api_e_code_len, 8
api_e_message:
    .ascii ",\"message\":\""
.set api_e_message_len, 12
api_e_end:
    .ascii "\"}"
.set api_e_end_len, 2
api_m400:
    .ascii "BAD_REQUEST"
.set api_m400_len, 11
api_m404:
    .ascii "NOT_FOUND"
.set api_m404_len, 9
api_m405:
    .ascii "METHOD_NOT_ALLOWED"
.set api_m405_len, 18
api_quote:
    .ascii "\""
.set api_quote_len, 1
api_0x:
    .ascii "0x"
.set api_0x_len, 2
api_true:
    .ascii "true"
.set api_true_len, 4
api_false:
    .ascii "false"
.set api_false_len, 5
api_i_peer_id:
    .ascii "{\"data\":{\"peer_id\":"
.set api_i_peer_id_len, 19
api_i_enr:
    .ascii ",\"enr\":"
.set api_i_enr_len, 7
api_i_p2p:
    .ascii ",\"p2p_addresses\":["
.set api_i_p2p_len, 18
api_i_discovery:
    .ascii "],\"discovery_addresses\":["
.set api_i_discovery_len, 25
api_i_seq:
    .ascii "],\"metadata\":{\"seq_number\":"
.set api_i_seq_len, 27
api_i_attnets:
    .ascii ",\"attnets\":"
.set api_i_attnets_len, 11
api_i_syncnets:
    .ascii ",\"syncnets\":"
.set api_i_syncnets_len, 12
api_i_cgc:
    .ascii ",\"custody_group_count\":"
.set api_i_cgc_len, 23
api_end3:
    .ascii "}}}"
.set api_end3_len, 3
api_end2:
    .ascii "}}"
.set api_end2_len, 2
api_end1:
    .ascii "}"
.set api_end1_len, 1
api_v_version:
    .ascii "{\"data\":{\"version\":"
.set api_v_version_len, 19
api_s_head:
    .ascii "{\"data\":{\"head_slot\":"
.set api_s_head_len, 21
api_s_distance:
    .ascii ",\"sync_distance\":"
.set api_s_distance_len, 17
api_s_syncing:
    .ascii ",\"is_syncing\":"
.set api_s_syncing_len, 14
api_s_optimistic:
    .ascii ",\"is_optimistic\":"
.set api_s_optimistic_len, 17
api_s_offline:
    .ascii ",\"el_offline\":"
.set api_s_offline_len, 14
api_c_connected:
    .ascii "{\"data\":{\"disconnected\":\"0\",\"connecting\":\"0\",\"connected\":"
.set api_c_connected_len, 57
api_c_end:
    .ascii ",\"disconnecting\":\"0\"}}"
.set api_c_end_len, 22
api_g_time:
    .ascii "{\"data\":{\"genesis_time\":"
.set api_g_time_len, 24
api_g_root:
    .ascii ",\"genesis_validators_root\":"
.set api_g_root_len, 27
api_g_version:
    .ascii ",\"genesis_fork_version\":"
.set api_g_version_len, 24
api_x_optimistic:
    .ascii "{\"execution_optimistic\":"
.set api_x_optimistic_len, 24
api_x_finalized:
    .ascii ",\"finalized\":false,\"data\":{"
.set api_x_finalized_len, 27
api_h_root:
    .ascii "\"root\":"
.set api_h_root_len, 7
api_h_slot:
    .ascii ",\"canonical\":true,\"header\":{\"message\":{\"slot\":"
.set api_h_slot_len, 46
api_h_proposer:
    .ascii ",\"proposer_index\":"
.set api_h_proposer_len, 18
api_h_parent:
    .ascii ",\"parent_root\":"
.set api_h_parent_len, 15
api_h_state:
    .ascii ",\"state_root\":"
.set api_h_state_len, 14
api_h_body:
    .ascii ",\"body_root\":"
.set api_h_body_len, 13
api_h_signature:
    .ascii "},\"signature\":"
.set api_h_signature_len, 14
api_f_previous:
    .ascii "\"previous_justified\":"
.set api_f_previous_len, 21
api_f_current:
    .ascii ",\"current_justified\":"
.set api_f_current_len, 21
api_f_finalized:
    .ascii ",\"finalized\":"
.set api_f_finalized_len, 13
api_f_epoch:
    .ascii "{\"epoch\":"
.set api_f_epoch_len, 9
api_f_root:
    .ascii ",\"root\":"
.set api_f_root_len, 8
api_hex:
    .ascii "0123456789abcdef"
.set api_hex_len, 16
