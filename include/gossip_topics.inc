/*
 * The gossip topic names of GOSSIP_* (include/lantern.inc), as read only data for
 * lantern_gossip_topic and lantern_gossip_topic_parse. Every ISA's topics.s ends with
 * GOSSIP_TOPIC_DATA.
 *
 * gossip_names: one 16 byte entry for each name from GOSSIP_BEACON_BLOCK on: the offset of
 * its bytes from gossip_name_bytes, then its length, plus 2^63 for a topic with a subnet.
 */
.macro GOSSIP_TOPIC_DATA
    RODATA
gossip_prefix:
    .ascii  "/eth2/"
gossip_suffix:
    .ascii  "/ssz_snappy"
gossip_name_bytes:
gossip_name_1:
    .ascii  "beacon_block"
gossip_name_2:
    .ascii  "beacon_aggregate_and_proof"
gossip_name_3:
    .ascii  "beacon_attestation"
gossip_name_4:
    .ascii  "voluntary_exit"
gossip_name_5:
    .ascii  "proposer_slashing"
gossip_name_6:
    .ascii  "attester_slashing"
gossip_name_7:
    .ascii  "sync_committee_contribution_and_proof"
gossip_name_8:
    .ascii  "sync_committee"
gossip_name_9:
    .ascii  "bls_to_execution_change"
gossip_name_10:
    .ascii  "blob_sidecar"
gossip_name_11:
    .ascii  "data_column_sidecar"
gossip_name_end:
    .p2align 3
gossip_names:
    .quad   gossip_name_1 - gossip_name_bytes, 12
    .quad   gossip_name_2 - gossip_name_bytes, 26
    .quad   gossip_name_3 - gossip_name_bytes, 18 + 0x8000000000000000
    .quad   gossip_name_4 - gossip_name_bytes, 14
    .quad   gossip_name_5 - gossip_name_bytes, 17
    .quad   gossip_name_6 - gossip_name_bytes, 17
    .quad   gossip_name_7 - gossip_name_bytes, 37
    .quad   gossip_name_8 - gossip_name_bytes, 14 + 0x8000000000000000
    .quad   gossip_name_9 - gossip_name_bytes, 23
    .quad   gossip_name_10 - gossip_name_bytes, 12 + 0x8000000000000000
    .quad   gossip_name_11 - gossip_name_bytes, 19 + 0x8000000000000000
.if (gossip_name_2 - gossip_name_1 != 12) || (gossip_name_3 - gossip_name_2 != 26) || (gossip_name_4 - gossip_name_3 != 18) || (gossip_name_5 - gossip_name_4 != 14) || (gossip_name_6 - gossip_name_5 != 17) || (gossip_name_7 - gossip_name_6 != 17) || (gossip_name_8 - gossip_name_7 != 37) || (gossip_name_9 - gossip_name_8 != 14) || (gossip_name_10 - gossip_name_9 != 23) || (gossip_name_11 - gossip_name_10 != 12) || (gossip_name_end - gossip_name_11 != 19) || (GOSSIP_NAMES != 11)
.error "a gossip name length in gossip_names is wrong"
.endif
.endm
