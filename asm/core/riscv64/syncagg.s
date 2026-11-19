/*
 * The sync aggregate, RISC-V. Requirements: docs/reference/block-processing.md.
 */

.set G1_POINT_BYTES, 144                                        /* asm-crypto G1Point: X, Y, Z */
.set SYNC_KEYS_LIST, 24 + 48 * SYNC_COMMITTEE_SIZE              /* a BlsPublicKeyList of the committee */
.set SYNC_AGG_EXTRA, SYNC_KEYS_LIST + SYNC_INDICES_BYTES + 3 * G1_POINT_BYTES + 48
.set SYNC_TABLE_SLOTS, 2 * SYNC_COMMITTEE_SIZE                  /* find_pubkeys: slots of (fingerprint, member + 1) */
.set SYNC_TABLE_BYTES, 16 * SYNC_TABLE_SLOTS
.if SYNC_TABLE_SLOTS & (SYNC_TABLE_SLOTS - 1)
.error "find_pubkeys takes a slot number by a mask: SYNC_COMMITTEE_SIZE must be a power of 2"
.endif
.if SYNC_TABLE_BYTES + 24 > SYNC_KEYS_LIST
.error "the hash table of find_pubkeys and its 3 words do not fit where the keys were"
.endif

/* Append the 48-byte key at register key to the BlsPublicKeyList at register list. Uses t4, t5. */
.macro KEYS_APPEND list, key
    ld      t4, 16(\list)
    addi    t5, t4, 1
    sd      t5, 16(\list)
    li      t5, 48
    mul     t4, t4, t5
    add     t4, t4, \list
    addi    t4, t4, 24
    ld      t5, 0(\key)
    sd      t5, 0(t4)
    ld      t5, 8(\key)
    sd      t5, 8(t4)
    ld      t5, 16(\key)
    sd      t5, 16(t4)
    ld      t5, 24(\key)
    sd      t5, 24(t4)
    ld      t5, 32(\key)
    sd      t5, 32(t4)
    ld      t5, 40(\key)
    sd      t5, 40(t4)
.endm

/* t0 = bit s10 of the sync committee bits of aggregate s2. Uses t1. */
.macro SYNC_BIT
    srli    t0, s10, 3
    add     t0, s2, t0
    lbu     t0, SyncAggregate_sync_committee_bits(t0)
    andi    t1, s10, 7
    srl     t0, t0, t1
    andi    t0, t0, 1
.endm

/* t0 = the address of current_sync_committee.pubkeys[s10] of state s1. Uses t1. */
.macro SYNC_KEY
    li      t0, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    add     t0, s1, t0
    li      t1, 48
    mul     t1, s10, t1
    add     t0, t0, t1
.endm

/*
 * s1 state, s2 sync aggregate, s3 config, s4 scratch, s5 result, s6 scratch size,
 * s7 keys, s8 committee indices, s9 bit count, s10 i.
 * Locals: L SYNC_COMMITTEE_SIZE, L+8 previous slot, L+16 epoch, L+24 domain type, L+32 domain (32),
 * L+64 signing root as a ByteList (56), L+120 block root (32), L+152 valid, L+160 total active balance,
 * L+168 base reward per increment, L+176 participant reward, L+184 proposer reward, L+192 proposer, L+200 the one,
 * L+208 1 when s7 is the participants' indices for crypto_bls_fast_aggregate_verify_cached, else 0.
 */
SPEC_FUNCTION process_sync_aggregate
    ENTER 224
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
.if FORK >= FORK_FULU
    NEED_SCRATCH_B s4, s1, 1, SYNC_AGG_EXTRA, 9f
.else
    NEED_SCRATCH_B s4, s1, 2, SYNC_AGG_EXTRA, 9f    # get_beacon_proposer_index takes S(2)
.endif
    sd      zero, 0(s5)
    ld      s6, 0(s4)
    li      t0, SYNC_KEYS_LIST              # own scratch at the end: keys, committee indices, points
    sub     t1, s6, t0
    add     s7, s4, t1
    sd      t0, 0(s7)
    li      t0, 24
    sd      t0, 8(s7)
    sd      zero, 16(s7)
    li      t0, SYNC_INDICES_BYTES
    sub     t1, t1, t0
    add     s8, s4, t1
    sd      t0, 0(s8)
    li      t0, SYNC_AGG_EXTRA
    sub     t0, s6, t0
    sd      t0, 0(s4)                       # what callees get
    li      t0, SYNC_COMMITTEE_SIZE
    sd      t0, L(sp)
    addi    a0, s2, SyncAggregate_sync_committee_bits
    addi    a1, sp, L
    addi    a2, sp, (L + 152)
    call    lantern_get_set_bit_count
    ld      s9, (L + 152)(sp)
    sd      zero, (L + 208)(sp)
    li      t1, SYNC_COMMITTEE_SIZE
    bne     s9, t1, 1f
    li      t0, BeaconState_current_sync_committee + SyncCommittee_aggregate_pubkey   # all signed: [aggregate_pubkey]
    add     t0, s1, t0
    KEYS_APPEND s7, t0
    j       4f
1:  ld      t0, CONFIG_PUBKEY_CACHE(s3)     # with a key cache, some signed: one cached check of their indices
    beqz    t0, 11f
    beqz    s9, 11f
    mv      a0, s1                          # committee_indices first: the participants' keys are those validators'
    li      a1, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    add     a1, s1, a1
    addi    a2, s8, LIST_FIXED
    mv      a3, s7                          # the hash table, where the keys go
    call    find_pubkeys
    mv      t0, a0
    li      a0, LANTERN_INVALID_SYNC_AGGREGATE
    bnez    t0, 6f
    li      t0, SYNC_KEYS_LIST              # the participants' indices: a BlsIndexList where the keys were
    sd      t0, 0(s7)
    li      t0, 24
    sd      t0, 8(s7)
    ld      t0, CONFIG_PUBKEY_CACHE(s3)
    ld      t4, CRYPTO_BLS_CACHE_COUNT(t0)
    addi    t5, s8, LIST_FIXED
    li      s10, 0
    li      t6, 0
12: li      t1, SYNC_COMMITTEE_SIZE
    bgeu    s10, t1, 13f
    SYNC_BIT
    beqz    t0, 121f
    slli    t1, s10, 3
    add     t1, t5, t1
    ld      t1, 0(t1)
    bgeu    t1, t4, 14f                     # an index past the cache: the spec's steps
    slli    t2, t6, 3
    add     t2, s7, t2
    sd      t1, 24(t2)
    addi    t6, t6, 1
121: addi   s10, s10, 1
    j       12b
13: sd      t6, 16(s7)
    li      t0, 1
    sd      t0, (L + 208)(sp)
    j       4f
14: sd      zero, 16(s7)
11: li      t1, (SYNC_COMMITTEE_SIZE / 2)
    bleu    s9, t1, 3f
    li      s10, 0                          # more than half: aggregate minus the non participants
2:  li      t1, SYNC_COMMITTEE_SIZE
    bgeu    s10, t1, 25f
    SYNC_BIT
    bnez    t0, 21f
    SYNC_KEY
    KEYS_APPEND s7, t0
21: addi    s10, s10, 1
    j       2b
25: li      t0, SYNC_AGG_EXTRA              # points: P1, P2, P3; then the non participant aggregate
    sub     t0, s6, t0
    add     s10, s4, t0                     # P1
    li      t0, SYNC_KEYS_LIST + SYNC_INDICES_BYTES + 48
    sub     t0, s6, t0
    add     s9, s4, t0                      # the non participant aggregate, 48 bytes
    mv      a0, s7
    mv      a1, s9
    CALL_GLOBAL crypto_bls_eth_aggregate_pubkeys
    bnez    a0, 5f
    li      t0, BeaconState_current_sync_committee + SyncCommittee_aggregate_pubkey
    add     a0, s1, t0                      # bls.bytes48_to_G1(aggregate_pubkey)
    mv      a1, s10
    CALL_GLOBAL crypto_bls_g1_decode
    bnez    a0, 5f
    mv      a0, s9                          # bls.bytes48_to_G1(non_participant_aggregate)
    addi    a1, s10, G1_POINT_BYTES
    CALL_GLOBAL crypto_bls_g1_decode
    bnez    a0, 5f
    addi    a0, s10, G1_POINT_BYTES         # bls.neg(...)
    addi    a1, s10, (2 * G1_POINT_BYTES)
    CALL_GLOBAL crypto_bls_g1_neg
    mv      a0, s10                         # bls.add(...)
    addi    a1, s10, (2 * G1_POINT_BYTES)
    addi    a2, s10, G1_POINT_BYTES
    CALL_GLOBAL crypto_bls_g1_add
    addi    a0, s10, G1_POINT_BYTES         # participant_pubkeys = [G1_to_bytes48(...)]
    mv      a1, s9
    CALL_GLOBAL crypto_bls_g1_compress
    sd      zero, 16(s7)
    KEYS_APPEND s7, s9
    j       4f
3:  li      s10, 0                          # at most half: the participants
31: li      t1, SYNC_COMMITTEE_SIZE
    bgeu    s10, t1, 4f
    SYNC_BIT
    beqz    t0, 32f
    SYNC_KEY
    KEYS_APPEND s7, t0
32: addi    s10, s10, 1
    j       31b
4:  li      t0, 1                           # previous_slot = saturating_sub(state.slot, 1)
    sd      t0, (L + 200)(sp)
    ADDQ    a0, s1, BeaconState_slot
    addi    a1, sp, (L + 200)
    addi    a2, sp, (L + 8)
    call    lantern_saturating_sub
    ld      t0, (L + 8)(sp)
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    sd      t0, (L + 16)(sp)
    li      t0, DOMAIN_SYNC_COMMITTEE
    sw      t0, (L + 24)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 24)
    addi    a2, sp, (L + 16)
    mv      a3, s4
    addi    a4, sp, (L + 32)
    call    lantern_get_domain
    bnez    a0, 7f
    mv      a0, s1                          # get_block_root_at_slot(state, previous_slot)
    addi    a1, sp, (L + 8)
    addi    a2, sp, (L + 120)
    call    lantern_get_block_root_at_slot
    CHECK_STATUS s5, 7f, 8f
    ADDRESS a0, lantern_type_Bytes32
    addi    a1, sp, (L + 120)
    addi    a2, sp, (L + 32)
    mv      a3, s4
    addi    a4, sp, (L + 88)
    call    lantern_compute_signing_root
    bnez    a0, 7f
    li      t0, 56
    sd      t0, (L + 64)(sp)
    li      t0, 24
    sd      t0, (L + 72)(sp)
    li      t0, 32
    sd      t0, (L + 80)(sp)
    ld      t0, (L + 208)(sp)
    bnez    t0, 46f
    mv      a0, s7                          # assert eth_fast_aggregate_verify(participant_pubkeys, signing_root, signature)
    addi    a1, sp, (L + 64)
    addi    a2, s2, SyncAggregate_sync_committee_signature
    mv      a3, s4
    addi    a4, sp, (L + 152)
    CALL_GLOBAL crypto_bls_eth_fast_aggregate_verify
    bnez    a0, 7f
    ld      t0, (L + 152)(sp)
    li      a0, LANTERN_INVALID_SYNC_AGGREGATE
    beqz    t0, 6f
    addi    s9, s8, LIST_FIXED              # committee_indices = [all_pubkeys.index(pubkey) for pubkey in committee]
    mv      a0, s1
    li      a1, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    add     a1, s1, a1
    mv      a2, s9
    mv      a3, s7                          # the hash table, where the keys were
    call    find_pubkeys
    mv      t0, a0
    li      a0, LANTERN_INVALID_SYNC_AGGREGATE
    bnez    t0, 6f
47: mv      a0, s1
    mv      a1, s4
    addi    a2, sp, (L + 160)
    call    lantern_get_total_active_balance
    bnez    a0, 7f
    li      t0, SYNC_AGG_EXTRA
    sub     t0, s6, t0
    sd      t0, 0(s4)
    mv      a0, s1
    mv      a1, s4
    addi    a2, sp, (L + 168)
    call    lantern_get_base_reward_per_increment
    bnez    a0, 7f
    ld      t0, (L + 160)(sp)
    li      t1, EFFECTIVE_BALANCE_INCREMENT
    divu    t0, t0, t1                      # total_active_increments
    ld      t1, (L + 168)(sp)
    mul     t0, t0, t1                      # total_base_rewards
    li      t1, SYNC_REWARD_WEIGHT
    mul     t0, t0, t1
    srli    t0, t0, 6                       # // WEIGHT_DENOMINATOR
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH    # max_participant_rewards
    li      t1, SYNC_COMMITTEE_SIZE
    divu    t0, t0, t1                      # participant_reward
    sd      t0, (L + 176)(sp)
    li      t1, PROPOSER_WEIGHT
    mul     t0, t0, t1
    li      t1, (WEIGHT_DENOMINATOR - PROPOSER_WEIGHT)
    divu    t0, t0, t1
    sd      t0, (L + 184)(sp)
    mv      a0, s1                          # get_beacon_proposer_index(state): the loop changes only balances
.if FORK >= FORK_FULU
    addi    a1, sp, (L + 192)
.else
    li      t0, SYNC_AGG_EXTRA
    sub     t0, s6, t0
    sd      t0, 0(s4)
    mv      a1, s4
    addi    a2, sp, (L + 192)
.endif
    call    lantern_get_beacon_proposer_index
    bnez    a0, 7f
    li      s10, 0
43: li      t1, SYNC_COMMITTEE_SIZE
    bgeu    s10, t1, 8f
    SYNC_BIT
    slli    a1, s10, 3
    add     a1, s9, a1
    beqz    t0, 44f
    mv      a0, s1                          # increase_balance(state, participant_index, participant_reward)
    addi    a2, sp, (L + 176)
    call    lantern_increase_balance
    mv      a0, s1                          # increase_balance(state, proposer, proposer_reward)
    addi    a1, sp, (L + 192)
    addi    a2, sp, (L + 184)
    call    lantern_increase_balance
    j       45f
44: mv      a0, s1                          # decrease_balance(state, participant_index, participant_reward)
    addi    a2, sp, (L + 176)
    call    lantern_decrease_balance
45: addi    s10, s10, 1
    j       43b
8:  li      a0, LANTERN_OK
7:  LEAVE 224
5:  li      a0, LANTERN_INVALID_AGGREGATE_PUBKEYS
6:  sd      a0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 224
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 224
46: PART    a0, t0, s1, BeaconState_validators      # eth_fast_aggregate_verify of at least one key, through the cache
    addi    a0, a0, Validator_pubkey
    mv      a1, s7
    ld      a2, CONFIG_PUBKEY_CACHE(s3)
    addi    a3, sp, (L + 64)
    addi    a4, s2, SyncAggregate_sync_committee_signature
    mv      a5, s4
    addi    a6, sp, (L + 152)
    CALL_GLOBAL crypto_bls_fast_aggregate_verify_cached
    bnez    a0, 7b
    ld      t0, (L + 152)(sp)
    li      a0, LANTERN_INVALID_SYNC_AGGREGATE
    beqz    t0, 6b
    addi    s9, s8, LIST_FIXED              # committee_indices, found before
    j       47b
SPEC_END process_sync_aggregate

.if WEIGHT_DENOMINATOR != 64
.error "lantern_process_sync_aggregate divides by WEIGHT_DENOMINATOR with a shift by 6"
.endif

/*
 * L0: all_pubkeys.index(pubkey) of state a0 for each of the SYNC_COMMITTEE_SIZE 48-byte keys at
 * a1, written to the u64 entries at a2: the first validator with the key. One pass over the
 * validators, with the distinct keys in a hash table at a3 (SYNC_TABLE_BYTES): a slot holds the
 * key's bytes 8 to 15, then its member + 1, or 0 when empty. While the pass runs, an entry holds
 * -1 for a key not found yet, or 1 << 63 | j for a key that is that of member j < k. The keys
 * may be unaligned. a0 = 0, or -1 when a key is missing. Uses a4-a7, t0-t6.
 */
LOCAL_FUNCTION find_pubkeys
    UNWIND_END_PROLOGUE
    li      t0, SYNC_TABLE_BYTES            # the table: empty
    add     t0, a3, t0
    mv      t1, a3
1:  sd      zero, 0(t1)
    sd      zero, 8(t1)
    addi    t1, t1, 16
    bltu    t1, t0, 1b
    li      a4, 0                           # k
    li      a5, 0                           # distinct keys not found yet
2:  li      t0, SYNC_COMMITTEE_SIZE
    bgeu    a4, t0, 6f
    li      t0, 48
    mul     a6, a4, t0
    add     a6, a1, a6                      # key k
    LDU64   a7, a6, 8, t0                   # its fingerprint
    andi    t1, a7, SYNC_TABLE_SLOTS - 1
3:  slli    t2, t1, 4
    add     t2, a3, t2                      # the slot
    ld      t3, 8(t2)
    beqz    t3, 5f
    ld      t4, 0(t2)
    bne     t4, a7, 4f
    addi    t4, t3, -1                      # the same fingerprint: the key of member j
    li      t5, 48
    mul     t4, t4, t5
    add     t4, a1, t4
    .irp off, 0, 8, 16, 24, 32, 40
    LDU64   t5, t4, \off, t0
    LDU64   t6, a6, \off, t0
    bne     t5, t6, 4f
    .endr
    addi    t3, t3, -1                      # the key of member j: 1 << 63 | j
    li      t5, 1
    slli    t5, t5, 63
    or      t3, t3, t5
    slli    t5, a4, 3
    add     t5, a2, t5
    sd      t3, 0(t5)
    j       55f
4:  addi    t1, t1, 1
    andi    t1, t1, SYNC_TABLE_SLOTS - 1
    j       3b
5:  sd      a7, 0(t2)                       # a new key
    addi    t3, a4, 1
    sd      t3, 8(t2)
    slli    t5, a4, 3
    add     t5, a2, t5
    li      t3, -1
    sd      t3, 0(t5)
    addi    a5, a5, 1
55: addi    a4, a4, 1
    j       2b
6:  PART    t0, t1, a0, BeaconState_validators
    li      a4, 0                           # i
7:  beqz    a5, 10f
    bgeu    a4, t1, 10f
    ld      a7, (Validator_pubkey + 8)(t0)
    andi    t2, a7, SYNC_TABLE_SLOTS - 1
8:  slli    t3, t2, 4
    add     t3, a3, t3
    ld      t4, 8(t3)
    beqz    t4, 95f
    ld      t5, 0(t3)
    bne     t5, a7, 9f
    addi    a6, t4, -1                      # the same fingerprint: compare the whole key
    li      t5, 48
    mul     t5, a6, t5
    add     t5, a1, t5
    .irp off, 0, 8, 16, 24, 32, 40
    LDU64   t6, t5, \off, a0
    ld      t3, (Validator_pubkey + \off)(t0)
    bne     t3, t6, 9f
    .endr
    slli    t5, a6, 3                       # the first validator with the key: its index
    add     t5, a2, t5
    ld      t6, 0(t5)
    li      t3, -1
    bne     t6, t3, 95f
    sd      a4, 0(t5)
    addi    a5, a5, -1
    j       95f
9:  addi    t2, t2, 1
    andi    t2, t2, SYNC_TABLE_SLOTS - 1
    j       8b
95: addi    t0, t0, Validator__mem
    addi    a4, a4, 1
    j       7b
10: li      a4, 0                           # each repeated key takes the index of its first member
    li      a6, -1
11: li      t0, SYNC_COMMITTEE_SIZE
    bgeu    a4, t0, 13f
    slli    t1, a4, 3
    add     t1, a2, t1
    ld      t2, 0(t1)
    beq     t2, a6, 12f
    bgez    t2, 115f
    slli    t2, t2, 1
    srli    t2, t2, 1
    slli    t2, t2, 3
    add     t2, a2, t2
    ld      t2, 0(t2)
    beq     t2, a6, 12f
    sd      t2, 0(t1)
115: addi   a4, a4, 1
    j       11b
12: li      a0, -1
    ret
13: li      a0, 0
    ret
END_FUNCTION find_pubkeys
