/*
 * The req/resp method names of REQRESP_* (include/lantern.inc), as read only data for
 * lantern_reqresp_protocol_parse and lantern_reqresp_protocol_id. Every ISA's reqresp.s
 * ends with REQRESP_PROTOCOL_DATA. The suffix /ssz_snappy is gossip_suffix of
 * include/gossip_topics.inc, in the same common object.
 *
 * reqresp_names: one 16 byte entry for each method from REQRESP_STATUS on: the offset of its
 * name from reqresp_name_bytes, then its length plus 256 times the mask of its versions
 * (bit v for version v).
 */
.macro REQRESP_PROTOCOL_DATA
    RODATA
reqresp_prefix:
    .ascii  "/eth2/beacon_chain/req/"
reqresp_name_bytes:
reqresp_name_1:
    .ascii  "status"
reqresp_name_2:
    .ascii  "goodbye"
reqresp_name_3:
    .ascii  "beacon_blocks_by_range"
reqresp_name_4:
    .ascii  "beacon_blocks_by_root"
reqresp_name_5:
    .ascii  "ping"
reqresp_name_6:
    .ascii  "metadata"
reqresp_name_7:
    .ascii  "blob_sidecars_by_range"
reqresp_name_8:
    .ascii  "blob_sidecars_by_root"
reqresp_name_9:
    .ascii  "data_column_sidecars_by_range"
reqresp_name_10:
    .ascii  "data_column_sidecars_by_root"
reqresp_name_11:
    .ascii  "beacon_blocks_by_head"
reqresp_name_12:
    .ascii  "light_client_bootstrap"
reqresp_name_13:
    .ascii  "light_client_updates_by_range"
reqresp_name_14:
    .ascii  "light_client_finality_update"
reqresp_name_15:
    .ascii  "light_client_optimistic_update"
reqresp_name_end:
    .p2align 3
reqresp_names:
    .quad   reqresp_name_1 - reqresp_name_bytes, 6 + 256 * 0x6
    .quad   reqresp_name_2 - reqresp_name_bytes, 7 + 256 * 0x2
    .quad   reqresp_name_3 - reqresp_name_bytes, 22 + 256 * 0x6
    .quad   reqresp_name_4 - reqresp_name_bytes, 21 + 256 * 0x6
    .quad   reqresp_name_5 - reqresp_name_bytes, 4 + 256 * 0x2
    .quad   reqresp_name_6 - reqresp_name_bytes, 8 + 256 * 0xe
    .quad   reqresp_name_7 - reqresp_name_bytes, 22 + 256 * 0x2
    .quad   reqresp_name_8 - reqresp_name_bytes, 21 + 256 * 0x2
    .quad   reqresp_name_9 - reqresp_name_bytes, 29 + 256 * 0x2
    .quad   reqresp_name_10 - reqresp_name_bytes, 28 + 256 * 0x2
    .quad   reqresp_name_11 - reqresp_name_bytes, 21 + 256 * 0x2
    .quad   reqresp_name_12 - reqresp_name_bytes, 22 + 256 * 0x2
    .quad   reqresp_name_13 - reqresp_name_bytes, 29 + 256 * 0x2
    .quad   reqresp_name_14 - reqresp_name_bytes, 28 + 256 * 0x2
    .quad   reqresp_name_15 - reqresp_name_bytes, 30 + 256 * 0x2
.if (reqresp_name_2 - reqresp_name_1 != 6) || (reqresp_name_3 - reqresp_name_2 != 7) || (reqresp_name_4 - reqresp_name_3 != 22) || (reqresp_name_5 - reqresp_name_4 != 21) || (reqresp_name_6 - reqresp_name_5 != 4) || (reqresp_name_7 - reqresp_name_6 != 8) || (reqresp_name_8 - reqresp_name_7 != 22) || (reqresp_name_9 - reqresp_name_8 != 21) || (reqresp_name_10 - reqresp_name_9 != 29) || (reqresp_name_11 - reqresp_name_10 != 28) || (reqresp_name_12 - reqresp_name_11 != 21) || (reqresp_name_13 - reqresp_name_12 != 22) || (reqresp_name_14 - reqresp_name_13 != 29) || (reqresp_name_15 - reqresp_name_14 != 28) || (reqresp_name_end - reqresp_name_15 != 30) || (REQRESP_METHODS != 15)
.error "a req/resp name length in reqresp_names is wrong"
.endif
.endm
