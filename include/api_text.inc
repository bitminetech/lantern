/*
 * The texts of the Beacon API answers (docs/reference/beacon-api.md, Common rules), in RODATA:
 * each label with its length in bytes as <label>_len, after api_texts. The same on every ISA.
 */
api_texts:
api_http:
    .ascii "HTTP/1.1 "
.set api_http_len, 9
api_sp:
    .ascii " "
.set api_sp_len, 1
api_crlf:
    .ascii "\r\n"
.set api_crlf_len, 2
api_type:
    .ascii "Content-Type: application/json\r\n"
.set api_type_len, 32
api_length:
    .ascii "Content-Length: "
.set api_length_len, 16
api_allow:
    .ascii "Allow: "
.set api_allow_len, 7
api_get:
    .ascii "GET"
.set api_get_len, 3
api_comma:
    .ascii ", "
.set api_comma_len, 2
api_post:
    .ascii "POST"
.set api_post_len, 4
api_close:
    .ascii "Connection: close\r\n"
.set api_close_len, 19
api_keep:
    .ascii "Connection: keep-alive\r\n"
.set api_keep_len, 24
api_none:
.set api_none_len, 0
api_r200:
    .ascii "OK"
.set api_r200_len, 2
api_r206:
    .ascii "Partial Content"
.set api_r206_len, 15
api_r400:
    .ascii "Bad Request"
.set api_r400_len, 11
api_r404:
    .ascii "Not Found"
.set api_r404_len, 9
api_r405:
    .ascii "Method Not Allowed"
.set api_r405_len, 18
api_r406:
    .ascii "Not Acceptable"
.set api_r406_len, 14
api_r413:
    .ascii "Content Too Large"
.set api_r413_len, 17
api_r414:
    .ascii "URI Too Long"
.set api_r414_len, 12
api_r415:
    .ascii "Unsupported Media Type"
.set api_r415_len, 22
api_r431:
    .ascii "Request Header Fields Too Large"
.set api_r431_len, 31
api_r500:
    .ascii "Internal Server Error"
.set api_r500_len, 21
api_r501:
    .ascii "Not Implemented"
.set api_r501_len, 15
api_r503:
    .ascii "Service Unavailable"
.set api_r503_len, 19
api_r505:
    .ascii "HTTP Version Not Supported"
.set api_r505_len, 26
api_m400:
    .ascii "BAD_REQUEST"
.set api_m400_len, 11
api_m404:
    .ascii "NOT_FOUND"
.set api_m404_len, 9
api_m405:
    .ascii "METHOD_NOT_ALLOWED"
.set api_m405_len, 18
api_m406:
    .ascii "NOT_ACCEPTABLE"
.set api_m406_len, 14
api_m413:
    .ascii "CONTENT_TOO_LARGE"
.set api_m413_len, 17
api_m414:
    .ascii "URI_TOO_LONG"
.set api_m414_len, 12
api_m415:
    .ascii "UNSUPPORTED_MEDIA_TYPE"
.set api_m415_len, 22
api_m431:
    .ascii "REQUEST_HEADER_FIELDS_TOO_LARGE"
.set api_m431_len, 31
api_m500:
    .ascii "INTERNAL_SERVER_ERROR"
.set api_m500_len, 21
api_m501:
    .ascii "NOT_IMPLEMENTED"
.set api_m501_len, 15
api_m503:
    .ascii "SERVICE_UNAVAILABLE"
.set api_m503_len, 19
api_m505:
    .ascii "HTTP_VERSION_NOT_SUPPORTED"
.set api_m505_len, 26
api_e_code:
    .ascii "{\"code\":"
.set api_e_code_len, 8
api_e_message:
    .ascii ",\"message\":\""
.set api_e_message_len, 12
api_e_end:
    .ascii "\"}"
.set api_e_end_len, 2
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
    .ascii ",\"finalized\":"
.set api_x_finalized_len, 13
api_x_data:
    .ascii ",\"data\":{"
.set api_x_data_len, 9
api_h_root:
    .ascii "\"root\":"
.set api_h_root_len, 7
api_h_canonical:
    .ascii ",\"canonical\":"
.set api_h_canonical_len, 13
api_h_slot:
    .ascii ",\"header\":{\"message\":{\"slot\":"
.set api_h_slot_len, 29
api_k_previous:
    .ascii "\"previous_version\":"
.set api_k_previous_len, 19
api_k_current:
    .ascii ",\"current_version\":"
.set api_k_current_len, 19
api_k_epoch:
    .ascii ",\"epoch\":"
.set api_k_epoch_len, 9
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
api_p_open:
    .ascii "{\"data\":{\""
.set api_p_open_len, 10
api_p_next:
    .ascii ",\""
.set api_p_next_len, 2
api_p_key:
    .ascii "\":"
.set api_p_key_len, 2
api_p_comma:
    .ascii ","
.set api_p_comma_len, 1
api_r_randao:
    .ascii "\"randao\":"
.set api_r_randao_len, 9
api_s_validators:
    .ascii "\"validators\":["
.set api_s_validators_len, 14
api_s_aggregates:
    .ascii "],\"validator_aggregates\":["
.set api_s_aggregates_len, 26
api_s_end:
    .ascii "]}}"
.set api_s_end_len, 3
api_p_lbracket:
    .ascii "["
.set api_p_lbracket_len, 1
api_p_rbracket:
    .ascii "]"
.set api_p_rbracket_len, 1
api_p_epoch:
    .ascii "{\"EPOCH\":"
.set api_p_epoch_len, 9
api_p_max:
    .ascii ",\"MAX_BLOBS_PER_BLOCK\":"
.set api_p_max_len, 23
api_o_open:
    .ascii "{\"data\":["
.set api_o_open_len, 9
api_o_entry:
    .ascii "{\"previous_version\":"
.set api_o_entry_len, 20
api_o_end:
    .ascii "]}"
.set api_o_end_len, 2
api_d_chain:
    .ascii "{\"data\":{\"chain_id\":"
.set api_d_chain_len, 20
api_d_address:
    .ascii ",\"address\":"
.set api_d_address_len, 11
api_v_index:
    .ascii "{\"index\":"
.set api_v_index_len, 9
api_v_balance:
    .ascii ",\"balance\":"
.set api_v_balance_len, 11
api_v_status:
    .ascii ",\"status\":\""
.set api_v_status_len, 11
api_v_validator:
    .ascii "\",\"validator\":{\"pubkey\":"
.set api_v_validator_len, 24
api_v_credentials:
    .ascii ",\"withdrawal_credentials\":"
.set api_v_credentials_len, 26
api_v_effective:
    .ascii ",\"effective_balance\":"
.set api_v_effective_len, 21
api_v_slashed:
    .ascii ",\"slashed\":"
.set api_v_slashed_len, 11
api_v_eligibility:
    .ascii ",\"activation_eligibility_epoch\":"
.set api_v_eligibility_len, 32
api_v_activation:
    .ascii ",\"activation_epoch\":"
.set api_v_activation_len, 20
api_v_exit:
    .ascii ",\"exit_epoch\":"
.set api_v_exit_len, 14
api_v_withdrawable:
    .ascii ",\"withdrawable_epoch\":"
.set api_v_withdrawable_len, 22
api_v_pubkey:
    .ascii ",\"pubkey\":"
.set api_v_pubkey_len, 10
api_v_data:
    .ascii ",\"data\":"
.set api_v_data_len, 8
api_v_open:
    .ascii "{\"execution_optimistic\":"
.set api_v_open_len, 24
api_v_list:
    .ascii ",\"data\":["
.set api_v_list_len, 9
api_v_end:
    .ascii "]}"
.set api_v_end_len, 2
api_c_slot:
    .ascii ",\"slot\":"
.set api_c_slot_len, 8
api_c_validators:
    .ascii ",\"validators\":["
.set api_c_validators_len, 15
api_u_root:
    .ascii "{\"dependent_root\":"
.set api_u_root_len, 18
api_u_optimistic:
    .ascii ",\"execution_optimistic\":"
.set api_u_optimistic_len, 24
api_u_pubkey:
    .ascii "{\"pubkey\":"
.set api_u_pubkey_len, 10
api_u_index:
    .ascii ",\"validator_index\":"
.set api_u_index_len, 19
api_ev_head:                            /* eventstream (beacon-api.md) */
    .ascii "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n"
.set api_ev_head_len, 75
api_ev_chunked:
    .ascii "Transfer-Encoding: chunked\r\n"
.set api_ev_chunked_len, 28
api_ev_close:
    .ascii "Connection: close\r\n"
.set api_ev_close_len, 19
api_ev_event:
    .ascii "event: "
.set api_ev_event_len, 7
api_ev_t_head:
    .ascii "head"
.set api_ev_t_head_len, 4
api_ev_t_block:
    .ascii "block"
.set api_ev_t_block_len, 5
api_ev_t_finalized:
    .ascii "finalized_checkpoint"
.set api_ev_t_finalized_len, 20
api_ev_data:
    .ascii "\ndata: "
.set api_ev_data_len, 7
api_ev_slot:
    .ascii "{\"slot\":"
.set api_ev_slot_len, 8
api_ev_block:
    .ascii ",\"block\":"
.set api_ev_block_len, 9
api_ev_block1:
    .ascii "{\"block\":"
.set api_ev_block1_len, 9
api_ev_state:
    .ascii ",\"state\":"
.set api_ev_state_len, 9
api_ev_transition:
    .ascii ",\"epoch_transition\":"
.set api_ev_transition_len, 20
api_ev_previous:
    .ascii ",\"previous_duty_dependent_root\":"
.set api_ev_previous_len, 32
api_ev_current:
    .ascii ",\"current_duty_dependent_root\":"
.set api_ev_current_len, 31
api_ev_end:
    .ascii "}\n\n"
.set api_ev_end_len, 3
api_v_statuses:                         /* the names of the statuses, API_STATUS_* order: 24 bytes each, the length first */
    .byte 19
    .ascii "pending_initialized"
    .space 4
    .byte 14
    .ascii "pending_queued"
    .space 9
    .byte 14
    .ascii "active_ongoing"
    .space 9
    .byte 14
    .ascii "active_exiting"
    .space 9
    .byte 14
    .ascii "active_slashed"
    .space 9
    .byte 16
    .ascii "exited_unslashed"
    .space 7
    .byte 14
    .ascii "exited_slashed"
    .space 9
    .byte 19
    .ascii "withdrawal_possible"
    .space 4
    .byte 15
    .ascii "withdrawal_done"
    .space 8
api_hex:
    .ascii "0123456789abcdef"
.set api_hex_len, 16
api_ok:
    .ascii "HTTP/1.1 200 OK\r\n"
.set api_ok_len, 17
api_octet:
    .ascii "Content-Type: application/octet-stream\r\n"
.set api_octet_len, 40
api_version:
    .ascii "Eth-Consensus-Version: "
.set api_version_len, 23
api_chunked:
    .ascii "Transfer-Encoding: chunked\r\n"
.set api_chunked_len, 28
api_j_version:
    .ascii "{\"version\":\""
.set api_j_version_len, 12
api_j_optimistic:
    .ascii "\",\"execution_optimistic\":"
.set api_j_optimistic_len, 25
api_j_data:
    .ascii ",\"data\":"
.set api_j_data_len, 8
api_last_chunk:
    .ascii "0\r\n\r\n"
.set api_last_chunk_len, 5
api_p_data:
    .ascii "{\"data\":["
.set api_p_data_len, 9
api_p_version:
    .ascii "\",\"data\":["
.set api_p_version_len, 10
api_a_slot:
    .ascii "{\"data\":{\"slot\":"
.set api_a_slot_len, 16
api_a_index:
    .ascii ",\"index\":"
.set api_a_index_len, 9
api_a_root:
    .ascii ",\"beacon_block_root\":"
.set api_a_root_len, 21
api_a_source:
    .ascii ",\"source\":"
.set api_a_source_len, 10
api_a_target:
    .ascii ",\"target\":"
.set api_a_target_len, 10
api_t_committee_index:
    .ascii ",\"committee_index\":"
.set api_t_committee_index_len, 19
api_t_committee_length:
    .ascii ",\"committee_length\":"
.set api_t_committee_length_len, 20
api_t_committees_at_slot:
    .ascii ",\"committees_at_slot\":"
.set api_t_committees_at_slot_len, 22
api_t_validator_committee_index:
    .ascii ",\"validator_committee_index\":"
.set api_t_validator_committee_index_len, 29
api_f_list:
    .ascii "\",\"failures\":["
.set api_f_list_len, 14
api_f_index:
    .ascii "{\"index\":"
.set api_f_index_len, 9
api_f_reject:
    .ascii ",\"message\":\"REJECT\"}"
.set api_f_reject_len, 20

/* The name of each fork, FORK_PHASE0 to FORK_FULU: 16 bytes each, its length, then its bytes. */
.macro API_FORK name
77: .byte 78f - 77b - 1
    .ascii "\name"
78: .space 16 - (78b - 77b)
.endm
api_forks:
    API_FORK phase0
    API_FORK altair
    API_FORK bellatrix
    API_FORK capella
    API_FORK deneb
    API_FORK electra
    API_FORK fulu
.set API_HEAD_ROOM, 168                     /* a streamed answer's head and a chunk's size line, at most */

/* Each status: its code, then its reason phrase and its error message, each an offset from api_texts and a length. */
.macro API_CODE code, reason, message
    .quad \code, \reason - api_texts, \reason\()_len, \message - api_texts, \message\()_len
.endm
    .p2align 3
api_codes:
    API_CODE 200, api_r200, api_none
    API_CODE 206, api_r206, api_none
    API_CODE 400, api_r400, api_m400
    API_CODE 404, api_r404, api_m404
    API_CODE 405, api_r405, api_m405
    API_CODE 406, api_r406, api_m406
    API_CODE 413, api_r413, api_m413
    API_CODE 414, api_r414, api_m414
    API_CODE 415, api_r415, api_m415
    API_CODE 431, api_r431, api_m431
    API_CODE 500, api_r500, api_m500
    API_CODE 501, api_r501, api_m501
    API_CODE 503, api_r503, api_m503
    API_CODE 505, api_r505, api_m505
api_codes_end:
.set API_CODE_ENTRY, 40
.set API_BODY_ERROR, 255                    /* the body kind of an error; else 0 for none or an API_OP_* */
.set API_R_CLOSE, 1                         /* the flags of api_respond; the allow bits from bit 8 */
.set API_R_KEEP, 2
.set API_R_NO_REASON, 4
.set API_R_SSZ, 8                           /* the body is SSZ: Content-Type: application/octet-stream */
.set API_R_VERSION, 16                      /* Eth-Consensus-Version of the view's fork */
