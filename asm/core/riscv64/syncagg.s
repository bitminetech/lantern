/*
 * The sync aggregate, RISC-V. Requirements: docs/reference/block-processing.md.
 */

.set G1_POINT_BYTES, 144                                        /* asm-crypto G1Point: X, Y, Z */
.set SYNC_KEYS_LIST, 24 + 48 * SYNC_COMMITTEE_SIZE              /* a BlsPublicKeyList of the committee */
.set SYNC_AGG_EXTRA, SYNC_KEYS_LIST + SYNC_INDICES_BYTES + 3 * G1_POINT_BYTES + 48

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
 * L+168 base reward per increment, L+176 participant reward, L+184 proposer reward, L+192 proposer, L+200 the one.
 */
FUNCTION lantern_process_sync_aggregate
    ENTER 208
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH_B s4, s1, 1, SYNC_AGG_EXTRA, 9f
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
    li      t1, SYNC_COMMITTEE_SIZE
    bne     s9, t1, 1f
    li      t0, BeaconState_current_sync_committee + SyncCommittee_aggregate_pubkey   # all signed: [aggregate_pubkey]
    add     t0, s1, t0
    KEYS_APPEND s7, t0
    j       4f
1:  li      t1, (SYNC_COMMITTEE_SIZE / 2)
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
    li      s10, 0                          # committee_indices = [all_pubkeys.index(pubkey) for pubkey in committee]
    addi    s9, s8, LIST_FIXED
41: li      t1, SYNC_COMMITTEE_SIZE
    bgeu    s10, t1, 42f
    SYNC_KEY
    mv      a1, t0
    mv      a0, s1
    call    find_pubkey
    mv      t0, a0
    li      a0, LANTERN_INVALID_SYNC_AGGREGATE
    li      t1, -1
    beq     t0, t1, 6f
    slli    t1, s10, 3
    add     t1, s9, t1
    sd      t0, 0(t1)
    addi    s10, s10, 1
    j       41b
42: mv      a0, s1
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
    mv      a0, s1
    addi    a1, sp, (L + 192)
    call    lantern_get_beacon_proposer_index
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
7:  LEAVE 208
5:  li      a0, LANTERN_INVALID_AGGREGATE_PUBKEYS
6:  sd      a0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 208
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 208
END_FUNCTION lantern_process_sync_aggregate

.if WEIGHT_DENOMINATOR != 64
.error "lantern_process_sync_aggregate divides by WEIGHT_DENOMINATOR with a shift by 6"
.endif
