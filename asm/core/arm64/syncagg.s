/*
 * The sync aggregate, ARM64. Requirements: docs/reference/block-processing.md.
 */

.set G1_POINT_BYTES, 144                                        /* asm-crypto G1Point: X, Y, Z */
.set SYNC_KEYS_LIST, 24 + 48 * SYNC_COMMITTEE_SIZE              /* a BlsPublicKeyList of the committee */
.set SYNC_AGG_EXTRA, SYNC_KEYS_LIST + SYNC_INDICES_BYTES + 3 * G1_POINT_BYTES + 48

/* Append the 48-byte key at register key to the BlsPublicKeyList at register list. Uses x13-x15, x17. */
.macro KEYS_APPEND list, key
    ldr     x13, [\list, #16]
    add     x14, x13, #1
    str     x14, [\list, #16]
    mov     x14, #48
    madd    x13, x13, x14, \list
    add     x13, x13, #24
    ldp     x15, x17, [\key]
    stp     x15, x17, [x13]
    ldp     x15, x17, [\key, #16]
    stp     x15, x17, [x13, #16]
    ldp     x15, x17, [\key, #32]
    stp     x15, x17, [x13, #32]
.endm

/*
 * x19 state, x20 sync aggregate, x21 config, x22 scratch, x23 result, x24 scratch size,
 * x25 keys, x26 committee indices, x27 bit count, x28 i.
 * Locals: L SYNC_COMMITTEE_SIZE, L+8 previous slot, L+16 epoch, L+24 domain type, L+32 domain (32),
 * L+64 signing root as a ByteList (56), L+120 block root (32), L+152 valid, L+160 total active balance,
 * L+168 base reward per increment, L+176 participant reward, L+184 proposer reward, L+192 proposer, L+200 the one.
 */
FUNCTION lantern_process_sync_aggregate
    ENTER 208
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    NEED_SCRATCH_B x22, x19, 1, SYNC_AGG_EXTRA, 9f
    str     xzr, [x23]
    ldr     x24, [x22]
    MOVQ    x9, SYNC_KEYS_LIST              /* own scratch at the end: keys, committee indices, points */
    sub     x10, x24, x9
    add     x25, x22, x10
    str     x9, [x25]
    mov     x9, #24
    str     x9, [x25, #8]
    str     xzr, [x25, #16]
    MOVQ    x9, SYNC_INDICES_BYTES
    sub     x10, x10, x9
    add     x26, x22, x10
    str     x9, [x26]
    MOVQ    x9, SYNC_AGG_EXTRA
    sub     x9, x24, x9
    str     x9, [x22]                       /* what callees get */
    mov     x9, #SYNC_COMMITTEE_SIZE
    str     x9, [sp, #L]
    add     x0, x20, #SyncAggregate_sync_committee_bits
    add     x1, sp, #L
    add     x2, sp, #(L + 152)
    bl      lantern_get_set_bit_count
    ldr     x27, [sp, #(L + 152)]
    MOVQ    x9, BeaconState_current_sync_committee
    add     x9, x19, x9
    cmp     x27, #SYNC_COMMITTEE_SIZE
    b.ne    1f
    MOVQ    x10, SyncCommittee_aggregate_pubkey     /* all signed: [aggregate_pubkey] */
    add     x10, x9, x10
    KEYS_APPEND x25, x10
    b       4f
1:  cmp     x27, #(SYNC_COMMITTEE_SIZE / 2)
    b.ls    3f
    mov     x28, #0                         /* more than half: aggregate minus the non participants */
2:  cmp     x28, #SYNC_COMMITTEE_SIZE
    b.hs    25f
    lsr     x10, x28, #3
    add     x11, x20, #SyncAggregate_sync_committee_bits
    ldrb    w10, [x11, x10]
    and     x11, x28, #7
    lsr     w10, w10, w11
    tbnz    w10, #0, 21f
    MOVQ    x10, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    add     x10, x19, x10
    mov     x11, #48
    madd    x10, x28, x11, x10
    KEYS_APPEND x25, x10
21: add     x28, x28, #1
    b       2b
25: MOVQ    x9, SYNC_AGG_EXTRA              /* points: P1, P2, P3; then the non participant aggregate */
    sub     x9, x24, x9
    add     x28, x22, x9                    /* P1 */
    MOVQ    x9, SYNC_KEYS_LIST + SYNC_INDICES_BYTES + 48
    sub     x9, x24, x9
    add     x27, x22, x9                    /* the non participant aggregate, 48 bytes */
    mov     x0, x25
    mov     x1, x27
    CALL_GLOBAL crypto_bls_eth_aggregate_pubkeys
    cbnz    x0, 5f
    MOVQ    x9, BeaconState_current_sync_committee + SyncCommittee_aggregate_pubkey
    add     x0, x19, x9                     /* bls.bytes48_to_G1(aggregate_pubkey) */
    mov     x1, x28
    CALL_GLOBAL crypto_bls_g1_decode
    cbnz    x0, 5f
    mov     x0, x27                         /* bls.bytes48_to_G1(non_participant_aggregate) */
    add     x1, x28, #G1_POINT_BYTES
    CALL_GLOBAL crypto_bls_g1_decode
    cbnz    x0, 5f
    add     x0, x28, #G1_POINT_BYTES        /* bls.neg(...) */
    add     x1, x28, #(2 * G1_POINT_BYTES)
    CALL_GLOBAL crypto_bls_g1_neg
    mov     x0, x28                         /* bls.add(...) */
    add     x1, x28, #(2 * G1_POINT_BYTES)
    add     x2, x28, #G1_POINT_BYTES
    CALL_GLOBAL crypto_bls_g1_add
    add     x0, x28, #G1_POINT_BYTES        /* participant_pubkeys = [G1_to_bytes48(...)] */
    mov     x1, x27
    CALL_GLOBAL crypto_bls_g1_compress
    str     xzr, [x25, #16]
    KEYS_APPEND x25, x27
    b       4f
3:  mov     x28, #0                         /* at most half: the participants */
31: cmp     x28, #SYNC_COMMITTEE_SIZE
    b.hs    4f
    lsr     x10, x28, #3
    add     x11, x20, #SyncAggregate_sync_committee_bits
    ldrb    w10, [x11, x10]
    and     x11, x28, #7
    lsr     w10, w10, w11
    tbz     w10, #0, 32f
    MOVQ    x10, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    add     x10, x19, x10
    mov     x11, #48
    madd    x10, x28, x11, x10
    KEYS_APPEND x25, x10
32: add     x28, x28, #1
    b       31b
4:  LDQ     x9, x19, BeaconState_slot       /* previous_slot = saturating_sub(state.slot, 1) */
    mov     x10, #1
    str     x10, [sp, #(L + 200)]
    ADDQ    x0, x19, BeaconState_slot
    add     x1, sp, #(L + 200)
    add     x2, sp, #(L + 8)
    bl      lantern_saturating_sub
    ldr     x9, [sp, #(L + 8)]
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    str     x9, [sp, #(L + 16)]
    mov     w9, #DOMAIN_SYNC_COMMITTEE
    str     w9, [sp, #(L + 24)]
    mov     x0, x19
    add     x1, sp, #(L + 24)
    add     x2, sp, #(L + 16)
    mov     x3, x22
    add     x4, sp, #(L + 32)
    bl      lantern_get_domain
    cbnz    x0, 7f
    mov     x0, x19                         /* get_block_root_at_slot(state, previous_slot) */
    add     x1, sp, #(L + 8)
    add     x2, sp, #(L + 120)
    bl      lantern_get_block_root_at_slot
    CHECK_STATUS x23, 7f, 8f
    ADDRESS x0, lantern_type_Bytes32
    add     x1, sp, #(L + 120)
    add     x2, sp, #(L + 32)
    mov     x3, x22
    add     x4, sp, #(L + 88)
    bl      lantern_compute_signing_root
    cbnz    x0, 7f
    mov     x9, #56
    str     x9, [sp, #(L + 64)]
    mov     x9, #24
    str     x9, [sp, #(L + 72)]
    mov     x9, #32
    str     x9, [sp, #(L + 80)]
    mov     x0, x25                         /* assert eth_fast_aggregate_verify(participant_pubkeys, signing_root, signature) */
    add     x1, sp, #(L + 64)
    add     x2, x20, #SyncAggregate_sync_committee_signature
    mov     x3, x22
    add     x4, sp, #(L + 152)
    CALL_GLOBAL crypto_bls_eth_fast_aggregate_verify
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 152)]
    mov     x0, #LANTERN_INVALID_SYNC_AGGREGATE
    cbz     x9, 6f
    mov     x28, #0                         /* committee_indices = [all_pubkeys.index(pubkey) for pubkey in committee] */
    add     x27, x26, #LIST_FIXED
41: cmp     x28, #SYNC_COMMITTEE_SIZE
    b.hs    42f
    MOVQ    x10, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    add     x10, x19, x10
    mov     x11, #48
    madd    x1, x28, x11, x10
    mov     x0, x19
    bl      find_pubkey
    mov     x9, x0
    mov     x0, #LANTERN_INVALID_SYNC_AGGREGATE
    cmn     x9, #1
    b.eq    6f
    str     x9, [x27, x28, lsl #3]
    add     x28, x28, #1
    b       41b
42: mov     x0, x19
    mov     x1, x22
    add     x2, sp, #(L + 160)
    bl      lantern_get_total_active_balance
    cbnz    x0, 7f
    MOVQ    x9, SYNC_AGG_EXTRA
    sub     x9, x24, x9
    str     x9, [x22]
    mov     x0, x19
    mov     x1, x22
    add     x2, sp, #(L + 168)
    bl      lantern_get_base_reward_per_increment
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 160)]
    MOVQ    x10, EFFECTIVE_BALANCE_INCREMENT
    udiv    x9, x9, x10                     /* total_active_increments */
    ldr     x10, [sp, #(L + 168)]
    mul     x9, x9, x10                     /* total_base_rewards */
    mov     x10, #SYNC_REWARD_WEIGHT
    mul     x9, x9, x10
    lsr     x9, x9, #6                      /* // WEIGHT_DENOMINATOR */
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH   /* max_participant_rewards */
    mov     x10, #SYNC_COMMITTEE_SIZE
    udiv    x9, x9, x10                     /* participant_reward */
    str     x9, [sp, #(L + 176)]
    mov     x10, #PROPOSER_WEIGHT
    mul     x9, x9, x10
    mov     x10, #(WEIGHT_DENOMINATOR - PROPOSER_WEIGHT)
    udiv    x9, x9, x10
    str     x9, [sp, #(L + 184)]
    mov     x28, #0
43: cmp     x28, #SYNC_COMMITTEE_SIZE
    b.hs    8f
    lsr     x10, x28, #3
    add     x11, x20, #SyncAggregate_sync_committee_bits
    ldrb    w10, [x11, x10]
    and     x11, x28, #7
    lsr     w10, w10, w11
    add     x1, x27, x28, lsl #3
    tbz     w10, #0, 44f
    mov     x0, x19                         /* increase_balance(state, participant_index, participant_reward) */
    add     x2, sp, #(L + 176)
    bl      lantern_increase_balance
    mov     x0, x19
    add     x1, sp, #(L + 192)
    bl      lantern_get_beacon_proposer_index
    mov     x0, x19                         /* increase_balance(state, proposer, proposer_reward) */
    add     x1, sp, #(L + 192)
    add     x2, sp, #(L + 184)
    bl      lantern_increase_balance
    b       45f
44: mov     x0, x19                         /* decrease_balance(state, participant_index, participant_reward) */
    add     x2, sp, #(L + 176)
    bl      lantern_decrease_balance
45: add     x28, x28, #1
    b       43b
8:  mov     x0, #LANTERN_OK
7:  LEAVE 208
5:  mov     x0, #LANTERN_INVALID_AGGREGATE_PUBKEYS
6:  str     x0, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 208
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 208
END_FUNCTION lantern_process_sync_aggregate

.if WEIGHT_DENOMINATOR != 64
.error "lantern_process_sync_aggregate divides by WEIGHT_DENOMINATOR with a shift by 6"
.endif
