/*
 * The sync aggregate, ARM64. Requirements: docs/reference/block-processing.md.
 */

.set G1_POINT_BYTES, 144                                        /* asm-crypto G1Point: X, Y, Z */
.set SYNC_KEYS_LIST, 24 + 48 * SYNC_COMMITTEE_SIZE              /* a BlsPublicKeyList of the committee */
.set SYNC_AGG_EXTRA, SYNC_KEYS_LIST + SYNC_INDICES_BYTES + 3 * G1_POINT_BYTES + 48
.set SYNC_TABLE_SLOTS, 2 * SYNC_COMMITTEE_SIZE                  /* lantern_find_pubkeys: slots of (fingerprint, member + 1) */
.set SYNC_TABLE_BYTES, 16 * SYNC_TABLE_SLOTS
.if SYNC_TABLE_SLOTS & (SYNC_TABLE_SLOTS - 1)
.error "find_pubkeys takes a slot number by a mask: SYNC_COMMITTEE_SIZE must be a power of 2"
.endif
.if SYNC_TABLE_BYTES + 24 > SYNC_KEYS_LIST
.error "the hash table of find_pubkeys and its 3 words do not fit where the keys were"
.endif

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
 * L+168 base reward per increment, L+176 participant reward, L+184 proposer reward, L+192 proposer, L+200 the one,
 * L+208 1 when x25 is the participants' indices for crypto_bls_fast_aggregate_verify_cached, else 0.
 */
SPEC_FUNCTION process_sync_aggregate
    ENTER 224
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
.if FORK >= FORK_FULU
    NEED_SCRATCH_B x22, x19, 1, SYNC_AGG_EXTRA, 9f
.else
    NEED_SCRATCH_B x22, x19, 2, SYNC_AGG_EXTRA, 9f    /* get_beacon_proposer_index takes S(2) */
.endif
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
    str     xzr, [sp, #(L + 208)]
    MOVQ    x9, BeaconState_current_sync_committee
    add     x9, x19, x9
    cmp     x27, #SYNC_COMMITTEE_SIZE
    b.ne    1f
    MOVQ    x10, SyncCommittee_aggregate_pubkey     /* all signed: [aggregate_pubkey] */
    add     x10, x9, x10
    KEYS_APPEND x25, x10
    b       4f
1:  ldr     x10, [x21, #CONFIG_PUBKEY_CACHE]    /* with a key cache, some signed: one cached check of their indices */
    cbz     x10, 11f
    cbz     x27, 11f
    mov     x0, x19                         /* committee_indices first: the participants' keys are those validators' */
    MOVQ    x1, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    add     x1, x19, x1
    add     x2, x26, #LIST_FIXED
    mov     x3, x25                         /* the hash table, where the keys go */
    bl      lantern_find_pubkeys
    mov     x9, x0
    mov     x0, #LANTERN_INVALID_SYNC_AGGREGATE
    cbnz    x9, 6f
    MOVQ    x9, SYNC_KEYS_LIST              /* the participants' indices: a BlsIndexList where the keys were */
    str     x9, [x25]
    mov     x9, #24
    str     x9, [x25, #8]
    ldr     x10, [x21, #CONFIG_PUBKEY_CACHE]
    ldr     x14, [x10, #CRYPTO_BLS_CACHE_COUNT]
    mov     x28, #0
    mov     x15, #0
12: cmp     x28, #SYNC_COMMITTEE_SIZE
    b.hs    13f
    lsr     x10, x28, #3
    add     x11, x20, #SyncAggregate_sync_committee_bits
    ldrb    w10, [x11, x10]
    and     x11, x28, #7
    lsr     w10, w10, w11
    tbz     w10, #0, 121f
    add     x12, x26, #LIST_FIXED
    ldr     x9, [x12, x28, lsl #3]
    cmp     x9, x14
    b.hs    14f                             /* an index past the cache: the spec's steps */
    add     x12, x25, #24
    str     x9, [x12, x15, lsl #3]
    add     x15, x15, #1
121: add    x28, x28, #1
    b       12b
13: str     x15, [x25, #16]
    mov     x9, #1
    str     x9, [sp, #(L + 208)]
    b       4f
14: str     xzr, [x25, #16]
11: cmp     x27, #(SYNC_COMMITTEE_SIZE / 2)
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
    ldr     x9, [sp, #(L + 208)]
    cbnz    x9, 46f
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
    add     x27, x26, #LIST_FIXED           /* committee_indices = [all_pubkeys.index(pubkey) for pubkey in committee] */
    mov     x0, x19
    MOVQ    x1, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    add     x1, x19, x1
    mov     x2, x27
    mov     x3, x25                         /* the hash table, where the keys were */
    bl      lantern_find_pubkeys
    mov     x9, x0
    mov     x0, #LANTERN_INVALID_SYNC_AGGREGATE
    cbnz    x9, 6f
47: mov     x0, x19
    mov     x1, x22
    add     x2, sp, #(L + 160)
    bl      lantern_get_total_active_balance
    cbnz    x0, 7f
    MOVQ    x9, SYNC_AGG_EXTRA
    sub     x9, x24, x9
    str     x9, [x22]
    add     x0, sp, #(L + 160)              /* get_base_reward_per_increment of the same total */
    add     x1, sp, #(L + 168)
    bl      lantern_integer_squareroot
    ldr     x9, [sp, #(L + 168)]
    MOVQ    x10, EFFECTIVE_BALANCE_INCREMENT * BASE_REWARD_FACTOR
    udiv    x10, x10, x9
    str     x10, [sp, #(L + 168)]
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
    mov     x0, x19                         /* get_beacon_proposer_index(state): the loop changes only balances */
.if FORK >= FORK_FULU
    add     x1, sp, #(L + 192)
.else
    MOVQ    x9, SYNC_AGG_EXTRA
    sub     x9, x24, x9
    str     x9, [x22]
    mov     x1, x22
    add     x2, sp, #(L + 192)
.endif
    bl      lantern_get_beacon_proposer_index
    cbnz    x0, 7f
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
7:  LEAVE 224
5:  mov     x0, #LANTERN_INVALID_AGGREGATE_PUBKEYS
6:  str     x0, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 224
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 224
46: PART    x0, x9, x19, BeaconState_validators     /* eth_fast_aggregate_verify of at least one key, through the cache */
    add     x0, x0, #Validator_pubkey
    mov     x1, x25
    ldr     x2, [x21, #CONFIG_PUBKEY_CACHE]
    add     x3, sp, #(L + 64)
    add     x4, x20, #SyncAggregate_sync_committee_signature
    mov     x5, x22
    add     x6, sp, #(L + 152)
    CALL_GLOBAL crypto_bls_fast_aggregate_verify_cached
    cbnz    x0, 7b
    ldr     x9, [sp, #(L + 152)]
    mov     x0, #LANTERN_INVALID_SYNC_AGGREGATE
    cbz     x9, 6b
    add     x27, x26, #LIST_FIXED           /* committee_indices, found before */
    b       47b
SPEC_END process_sync_aggregate

.if WEIGHT_DENOMINATOR != 64
.error "lantern_process_sync_aggregate divides by WEIGHT_DENOMINATOR with a shift by 6"
.endif

/*
 * all_pubkeys.index(pubkey) of state x0 for each of the SYNC_COMMITTEE_SIZE 48-byte keys at
 * x1, written to the u64 entries at x2: the first validator with the key. One pass over the
 * validators, with the distinct keys in a hash table at x3 (SYNC_TABLE_BYTES): a slot holds the
 * key's bytes 8 to 15, then its member + 1, or 0 when empty. While the pass runs, an entry holds
 * -1 for a key not found yet, or 1 << 63 | j for a key that is that of member j < k.
 * x0 = 0, or -1 when a key is missing. Uses x4-x7, x9-x17.
 */
LOCAL_FUNCTION lantern_find_pubkeys
    UNWIND_END_PROLOGUE
    mov     x9, x3                          /* the table: empty */
    MOVQ    x10, SYNC_TABLE_BYTES
    add     x10, x3, x10
1:  stp     xzr, xzr, [x9], #16
    cmp     x9, x10
    b.lo    1b
    mov     x11, #0                         /* k */
    mov     x15, #0                         /* distinct keys not found yet */
2:  cmp     x11, #SYNC_COMMITTEE_SIZE
    b.hs    6f
    mov     x12, #48
    madd    x12, x11, x12, x1               /* key k */
    ldr     x13, [x12, #8]                  /* its fingerprint */
    and     x14, x13, #(SYNC_TABLE_SLOTS - 1)
3:  add     x16, x3, x14, lsl #4            /* the slot */
    ldr     x17, [x16, #8]
    cbz     x17, 5f
    ldr     x9, [x16]
    cmp     x9, x13
    b.ne    4f
    sub     x9, x17, #1                     /* the same fingerprint: the key of member j */
    mov     x10, #48
    madd    x9, x9, x10, x1
    ldp     x4, x5, [x9]
    ldp     x6, x7, [x12]
    cmp     x4, x6
    ccmp    x5, x7, #0, eq
    b.ne    4f
    ldp     x4, x5, [x9, #16]
    ldp     x6, x7, [x12, #16]
    cmp     x4, x6
    ccmp    x5, x7, #0, eq
    b.ne    4f
    ldp     x4, x5, [x9, #32]
    ldp     x6, x7, [x12, #32]
    cmp     x4, x6
    ccmp    x5, x7, #0, eq
    b.ne    4f
    sub     x9, x17, #1                     /* the key of member j: 1 << 63 | j */
    orr     x9, x9, #0x8000000000000000
    str     x9, [x2, x11, lsl #3]
    b       55f
4:  add     x14, x14, #1
    and     x14, x14, #(SYNC_TABLE_SLOTS - 1)
    b       3b
5:  str     x13, [x16]                      /* a new key */
    add     x17, x11, #1
    str     x17, [x16, #8]
    mov     x9, #-1
    str     x9, [x2, x11, lsl #3]
    add     x15, x15, #1
55: add     x11, x11, #1
    b       2b
6:  PART    x9, x10, x0, BeaconState_validators
    mov     x11, #0                         /* i */
7:  cbz     x15, 10f
    cmp     x11, x10
    b.hs    10f
    ldr     x13, [x9, #(Validator_pubkey + 8)]
    and     x14, x13, #(SYNC_TABLE_SLOTS - 1)
8:  add     x16, x3, x14, lsl #4
    ldp     x4, x17, [x16]
    cbz     x17, 95f
    cmp     x4, x13
    b.ne    9f
    sub     x12, x17, #1                    /* the same fingerprint: compare the whole key */
    mov     x5, #48
    madd    x12, x12, x5, x1
    ldp     x4, x5, [x9, #Validator_pubkey]
    ldp     x6, x7, [x12]
    cmp     x4, x6
    ccmp    x5, x7, #0, eq
    b.ne    9f
    ldp     x4, x5, [x9, #(Validator_pubkey + 16)]
    ldp     x6, x7, [x12, #16]
    cmp     x4, x6
    ccmp    x5, x7, #0, eq
    b.ne    9f
    ldp     x4, x5, [x9, #(Validator_pubkey + 32)]
    ldp     x6, x7, [x12, #32]
    cmp     x4, x6
    ccmp    x5, x7, #0, eq
    b.ne    9f
    sub     x12, x17, #1                    /* the first validator with the key: its index */
    ldr     x4, [x2, x12, lsl #3]
    cmn     x4, #1
    b.ne    95f
    str     x11, [x2, x12, lsl #3]
    sub     x15, x15, #1
    b       95f
9:  add     x14, x14, #1
    and     x14, x14, #(SYNC_TABLE_SLOTS - 1)
    b       8b
95: add     x9, x9, #Validator__mem
    add     x11, x11, #1
    b       7b
10: mov     x11, #0                         /* each repeated key takes the index of its first member */
11: cmp     x11, #SYNC_COMMITTEE_SIZE
    b.hs    13f
    ldr     x4, [x2, x11, lsl #3]
    cmn     x4, #1
    b.eq    12f
    tbz     x4, #63, 115f
    and     x4, x4, #0x7fffffffffffffff
    ldr     x4, [x2, x4, lsl #3]
    cmn     x4, #1
    b.eq    12f
    str     x4, [x2, x11, lsl #3]
115: add    x11, x11, #1
    b       11b
12: mov     x0, #-1
    ret
13: mov     x0, #0
    ret
END_FUNCTION lantern_find_pubkeys
