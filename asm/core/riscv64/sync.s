/*
 * Sync committee selection, RISC-V. Requirements: docs/reference/epoch-processing.md.
 */

.set SYNC_INDICES_BYTES, LIST_FIXED + 8 * SYNC_COMMITTEE_SIZE           /* an IndexList of the members */
.set SYNC_KEYS_BYTES, 24 + 48 * SYNC_COMMITTEE_SIZE                     /* a BlsPublicKeyList of the members */
.set SYNC_COMMITTEE_SCRATCH, SYNC_INDICES_BYTES + SYNC_KEYS_BYTES

/*
 * s1 state, s2 scratch, s3 out, s4 validator count, s5 scratch size, s6 active list,
 * s7 active count, s8 i, s9 members so far, s10 candidate.
 * Locals: L epoch, L+8 domain type, L+16 seed, L+48 message (seed, i // 16), L+88 digest,
 * L+120 i % count, L+128 shuffled index, L+136 active count.
 */
FUNCTION lantern_get_next_sync_committee_indices
    ENTER 144
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      t0, LIST_SIZE(s3)
    li      t1, SYNC_INDICES_BYTES
    bltu    t0, t1, 9f
    NEED_SCRATCH s2, s1, 2, 9f
    LDQ     s4, s1, BeaconState_validators + 8
    ld      s5, 0(s2)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, L(sp)
    addi    t0, t0, 1                       # epoch = get_current_epoch(state) + 1
    sd      t0, L(sp)
    SCRATCH_LIST s6, s2, s5, 0, s4
    mv      a0, s1
    addi    a1, sp, L
    mv      a2, s6
    call    lantern_get_active_validator_indices
    bnez    a0, 7f
    ld      s7, LIST_COUNT(s6)
    beqz    s7, 8f                          # i % active_validator_count divides by 0
    sd      s7, (L + 136)(sp)
    li      t0, DOMAIN_SYNC_COMMITTEE
    sw      t0, (L + 8)(sp)
    mv      a0, s1
    addi    a1, sp, L
    addi    a2, sp, (L + 8)
    addi    a3, sp, (L + 16)
    call    lantern_get_seed
    bnez    a0, 7f
    addi    t0, sp, (L + 48)
    addi    t1, sp, (L + 16)
    COPY32  t0, t1
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s3)
    li      s9, 0
    li      s8, 0
1:  li      t0, SYNC_COMMITTEE_SIZE
    bgeu    s9, t0, 3f
    remu    t0, s8, s7
    sd      t0, (L + 120)(sp)
    SCRATCH_GIVE s2, s5, 1, s4
    addi    a0, sp, (L + 120)               # compute_shuffled_index(i % active_validator_count, ...)
    addi    a1, sp, (L + 136)
    addi    a2, sp, (L + 16)
    mv      a3, s2
    addi    a4, sp, (L + 128)
    call    lantern_compute_shuffled_index
    bnez    a0, 7f
    ld      t0, (L + 128)(sp)
    slli    t0, t0, 3
    add     t0, s6, t0
    ld      s10, LIST_FIXED(t0)             # candidate_index
    srli    t0, s8, 4
    sd      t0, (L + 80)(sp)
    addi    a0, sp, (L + 48)                # random_bytes = sha256(seed + uint_to_bytes(i // 16))
    li      a1, 40
    addi    a2, sp, (L + 88)
    call    sha256_short
    andi    t0, s8, 15
    slli    t0, t0, 1
    add     t0, sp, t0
    lhu     t0, (L + 88)(t0)                # random_value
    PART    t1, t2, s1, BeaconState_validators
    slli    t2, s10, 7
    add     t1, t1, t2
    ld      t1, Validator_effective_balance(t1)
    li      t2, 0xffff
    mulhu   t3, t1, t2
    bnez    t3, 6f
    mul     t1, t1, t2
    li      t2, MAX_EFFECTIVE_BALANCE_ELECTRA
    mul     t2, t2, t0
    bltu    t1, t2, 2f
    slli    t0, s9, 3
    add     t0, s3, t0
    sd      s10, LIST_FIXED(t0)
    addi    s9, s9, 1
2:  addi    s8, s8, 1
    j       1b
3:  sd      s9, LIST_COUNT(s3)
    li      a0, LANTERN_OK
7:  LEAVE 144
6:  li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 144
8:  li      a0, LANTERN_INVALID_NO_INDICES
    LEAVE 144
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 144
END_FUNCTION lantern_get_next_sync_committee_indices

/* s1 state, s2 scratch, s3 out, s4 scratch size, s5 member, s6 indices, s7 keys. */
FUNCTION lantern_get_next_sync_committee
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    NEED_SCRATCH_B s2, s1, 2, SYNC_COMMITTEE_SCRATCH, 9f
    ld      s4, 0(s2)
    li      t0, SYNC_INDICES_BYTES
    sub     t1, s4, t0
    add     s6, s2, t1
    sd      t0, 0(s6)
    li      t0, SYNC_COMMITTEE_SCRATCH
    sub     t1, s4, t0
    add     s7, s2, t1
    sd      t1, 0(s2)
    mv      a0, s1
    mv      a1, s2
    mv      a2, s6
    call    lantern_get_next_sync_committee_indices
    bnez    a0, 7f
    li      t0, SYNC_KEYS_BYTES             # pubkeys = [state.validators[index].pubkey for index in indices]
    sd      t0, 0(s7)
    li      t0, 24
    sd      t0, 8(s7)
    li      t0, SYNC_COMMITTEE_SIZE
    sd      t0, 16(s7)
    addi    t0, s6, LIST_FIXED
    addi    t1, s7, 24
    addi    t2, s3, SyncCommittee_pubkeys
    PART    t3, t4, s1, BeaconState_validators
    li      s5, 0
1:  li      t4, SYNC_COMMITTEE_SIZE
    bgeu    s5, t4, 2f
    ld      t4, 0(t0)
    addi    t0, t0, 8
    slli    t4, t4, 7
    add     t4, t3, t4
    .irp k, 0, 8, 16, 24, 32, 40
    ld      t5, (Validator_pubkey + \k)(t4)
    sd      t5, \k(t1)
    sd      t5, \k(t2)
    .endr
    addi    t1, t1, 48
    addi    t2, t2, 48
    addi    s5, s5, 1
    j       1b
2:  mv      a0, s7                          # aggregate_pubkey = eth_aggregate_pubkeys(pubkeys)
    li      t0, SyncCommittee_aggregate_pubkey
    add     a1, s3, t0
    CALL_GLOBAL crypto_bls_eth_aggregate_pubkeys
    beqz    a0, 7f
    li      a0, LANTERN_INVALID_AGGREGATE_PUBKEYS
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_get_next_sync_committee

/* s1 state, s2 config, s3 scratch, s4 result, s5 scratch size, s6 new committee. Locals: L epoch. */
FUNCTION lantern_process_sync_committee_updates
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    sd      zero, 0(s4)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, L(sp)
    addi    t0, t0, 1
    li      t1, (EPOCHS_PER_SYNC_COMMITTEE_PERIOD - 1)
    and     t0, t0, t1
    bnez    t0, 8f
    NEED_SCRATCH_B s3, s1, 2, SYNC_COMMITTEE_SCRATCH + SyncCommittee__mem, 9f
    ld      s5, 0(s3)
    li      t0, SyncCommittee__mem
    sub     t1, s5, t0
    add     s6, s3, t1
    sd      t1, 0(s3)
    mv      a0, s1
    mv      a1, s3
    mv      a2, s6
    call    lantern_get_next_sync_committee
    CHECK_STATUS s4, 7f, 8f
    ADDQ    a0, s1, BeaconState_current_sync_committee  # current = next; next = the new committee
    ADDQ    a1, s1, BeaconState_next_sync_committee
    li      a2, SyncCommittee__mem
    call    lantern_copy
    ADDQ    a0, s1, BeaconState_next_sync_committee
    mv      a1, s6
    li      a2, SyncCommittee__mem
    call    lantern_copy
8:  li      a0, LANTERN_OK
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_process_sync_committee_updates

.if EPOCHS_PER_SYNC_COMMITTEE_PERIOD & (EPOCHS_PER_SYNC_COMMITTEE_PERIOD - 1)
.error "EPOCHS_PER_SYNC_COMMITTEE_PERIOD is not a power of two"
.endif
