/*
 * Committees and attestations, RISC-V. Requirements: docs/reference/block-processing.md.
 */

.set CIDX_BYTES, LIST_FIXED + 8 * MAX_COMMITTEES_PER_SLOT     /* an IndexList of committee indices */
.set FLAGS_BYTES, LIST_FIXED + 8 * 3                            /* an IndexList of participation flags */
.set ATTEST_EXTRA, 2 * CIDX_BYTES + IndexedAttestation__fixed + 8

/* ---------------------------------------------------------------- Sorting */

/* Sift the entry at root down the heap of entries below end, at a0. Uses t0-t4. */
.macro SIFT root, end
97: slli    t0, \root, 1
    addi    t0, t0, 1                       # child = 2 * root + 1
    bgeu    t0, \end, 98f
    slli    t3, t0, 3
    add     t3, a0, t3
    ld      t2, 0(t3)
    addi    t1, t0, 1
    bgeu    t1, \end, 96f
    ld      t4, 8(t3)
    bleu    t4, t2, 96f                     # the larger child
    mv      t0, t1
    mv      t2, t4
96: slli    t3, \root, 3
    add     t3, a0, t3
    ld      t4, 0(t3)
    bgeu    t4, t2, 98f
    sd      t2, 0(t3)
    slli    t1, t0, 3
    add     t1, a0, t1
    sd      t4, 0(t1)
    mv      \root, t0
    j       97b
98:
.endm

/* L0: sort the a1 u64 entries at a0, ascending (heapsort). A leaf; uses a2-a4, t0-t4. */
LOCAL_FUNCTION sort_u64
    UNWIND_END_PROLOGUE
    li      t0, 2
    bltu    a1, t0, 9f
    srli    a2, a1, 1
1:  beqz    a2, 2f
    addi    a2, a2, -1
    mv      a3, a2
    SIFT    a3, a1
    j       1b
2:  mv      a4, a1
3:  addi    a4, a4, -1
    beqz    a4, 9f
    ld      t0, 0(a0)
    slli    t1, a4, 3
    add     t1, a0, t1
    ld      t2, 0(t1)
    sd      t2, 0(a0)
    sd      t0, 0(t1)
    li      a3, 0
    SIFT    a3, a4
    j       3b
9:  ret
END_FUNCTION sort_u64

/* ---------------------------------------------------------------- Committees */

.if FORK >= FORK_ELECTRA
SPEC_LEAF get_committee_indices
    li      a2, LIST_FIXED
    sd      a2, LIST_OFFSET(a1)
    addi    a2, a1, LIST_FIXED
    li      a3, 0                           # bit
    li      t0, MAX_COMMITTEES_PER_SLOT
1:  bgeu    a3, t0, 2f
    srli    a4, a3, 3
    add     a4, a0, a4
    lbu     a4, 0(a4)
    andi    a5, a3, 7
    srl     a4, a4, a5
    andi    a4, a4, 1
    beqz    a4, 3f
    sd      a3, 0(a2)
    addi    a2, a2, 8
3:  addi    a3, a3, 1
    j       1b
2:  addi    a3, a1, LIST_FIXED
    sub     a2, a2, a3
    srli    a2, a2, 3
    sd      a2, LIST_COUNT(a1)
    RETURN_OK
SPEC_END get_committee_indices
.endif

/* s1 state, s2 epoch, s3 scratch, s4 out, s5 list. */
SPEC_FUNCTION get_committee_count_per_slot
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH s3, s1, 1, 9f
    LDQ     t2, s1, BeaconState_validators + 8
    ld      t3, 0(s3)
    SCRATCH_LIST s5, s3, t3, 0, t2
    mv      a0, s1
    mv      a1, s2
    mv      a2, s5
    call    lantern_get_active_validator_indices
    bnez    a0, 7f
    ld      t0, LIST_COUNT(s5)
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    li      t1, TARGET_COMMITTEE_SIZE
    divu    t0, t0, t1
    li      t1, MAX_COMMITTEES_PER_SLOT
    bltu    t0, t1, 1f
    mv      t0, t1
1:  bnez    t0, 2f                          # max(1, ...)
    li      t0, 1
2:  sd      t0, 0(s4)
    li      a0, LANTERN_OK
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_committee_count_per_slot

/*
 * s1 indices, s2 seed, s3 i, s4 end, s5 scratch, s6 out entries, s7 scratch size.
 * Locals: L len(indices), L+8 i, L+16 shuffled.
 */
SPEC_FUNCTION compute_committee
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s5, a4
    ld      t0, LIST_COUNT(s1)              # n
    sd      t0, L(sp)
    ld      t1, 0(a2)                       # index
    ld      t2, 0(a3)                       # count
    beqz    t2, 8f
    mul     t3, t0, t1
    divu    s3, t3, t2                      # start = len(indices) * index // count
    addi    t1, t1, 1
    mul     t3, t0, t1
    divu    s4, t3, t2                      # end = len(indices) * (index + 1) // count
    sub     t3, s4, s3
    slli    t4, t3, 3
    addi    t4, t4, LIST_FIXED
    ld      t5, LIST_SIZE(a5)
    bltu    t5, t4, 9f
    li      t4, LIST_FIXED
    sd      t4, LIST_OFFSET(a5)
    sd      t3, LIST_COUNT(a5)
    addi    s6, a5, LIST_FIXED
    ld      s7, 0(s5)
1:  bgeu    s3, s4, 2f
    sd      s3, (L + 8)(sp)
    sd      s7, 0(s5)
    addi    a0, sp, (L + 8)                 # indices[compute_shuffled_index(i, len(indices), seed)]
    addi    a1, sp, L
    mv      a2, s2
    mv      a3, s5
    addi    a4, sp, (L + 16)
    call    lantern_compute_shuffled_index
    bnez    a0, 7f
    ld      t0, (L + 16)(sp)
    slli    t0, t0, 3
    add     t0, s1, t0
    ld      t0, LIST_FIXED(t0)
    sd      t0, 0(s6)
    addi    s6, s6, 8
    addi    s3, s3, 1
    j       1b
2:  li      a0, LANTERN_OK
7:  LEAVE 32
8:  li      a0, LANTERN_INVALID_SHUFFLED_INDEX
    LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END compute_committee

/*
 * s1 state, s2 slot, s3 index pointer, s4 scratch, s5 out, s6 scratch size, s7 n, s8 list.
 * Locals: L epoch, L+8 committees per slot, L+16 domain type, L+24 seed (32), L+56 index, L+64 count.
 */
SPEC_FUNCTION get_beacon_committee
    ENTER 80
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH s4, s1, 2, 9f
    ld      s6, 0(s4)
    LDQ     s7, s1, BeaconState_validators + 8
    srli    t0, s2, LOG2_SLOTS_PER_EPOCH    # epoch = compute_epoch_at_slot(slot)
    sd      t0, L(sp)
    mv      a0, s1
    addi    a1, sp, L
    mv      a2, s4
    addi    a3, sp, (L + 8)
    call    lantern_get_committee_count_per_slot
    bnez    a0, 7f
    SCRATCH_LIST s8, s4, s6, 0, s7
    mv      a0, s1
    addi    a1, sp, L
    mv      a2, s8
    call    lantern_get_active_validator_indices
    bnez    a0, 7f
    li      t0, DOMAIN_BEACON_ATTESTER
    sw      t0, (L + 16)(sp)
    mv      a0, s1
    addi    a1, sp, L
    addi    a2, sp, (L + 16)
    addi    a3, sp, (L + 24)
    call    lantern_get_seed
    bnez    a0, 7f
    ld      t0, (L + 8)(sp)                 # index = (slot % SLOTS_PER_EPOCH) * committees_per_slot + index
    andi    t1, s2, (SLOTS_PER_EPOCH - 1)
    mul     t1, t1, t0
    ld      t2, 0(s3)
    add     t2, t1, t2
    bltu    t2, t1, 6f
    sd      t2, (L + 56)(sp)
    slli    t0, t0, LOG2_SLOTS_PER_EPOCH    # count = committees_per_slot * SLOTS_PER_EPOCH
    sd      t0, (L + 64)(sp)
    SCRATCH_GIVE s4, s6, 1, s7
    mv      a0, s8
    addi    a1, sp, (L + 24)
    addi    a2, sp, (L + 56)
    addi    a3, sp, (L + 64)
    mv      a4, s4
    mv      a5, s5
    call    lantern_compute_committee
7:  LEAVE 80
6:  li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 80
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
SPEC_END get_beacon_committee

.if FORK >= FORK_ELECTRA
/*
 * s1 state, s2 attestation, s3 scratch, s4 out, s5 scratch size, s6 n, s7 committee indices,
 * s8 committee, s9 committee offset, s10 committee index cursor.
 * Locals: L committee index, L+8 the scratch size the callee gets, L+16 bits, L+24 bit count, L+32 cursor end.
 */
SPEC_FUNCTION get_attesting_indices
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH_B s3, s1, 3, CIDX_BYTES, 9f
    LDQ     s6, s1, BeaconState_validators + 8
    slli    t0, s6, 3                       # out has room for every validator
    addi    t0, t0, LIST_FIXED
    ld      t1, LIST_SIZE(s4)
    bltu    t1, t0, 9f
    ld      s5, 0(s3)
    li      t0, CIDX_BYTES
    sub     t1, s5, t0
    add     s7, s3, t1                      # committee indices: the last CIDX_BYTES
    sd      t0, 0(s7)
    slli    t2, s6, 3
    addi    t2, t2, LIST_FIXED
    sub     t1, t1, t2
    add     s8, s3, t1                      # the committee: the L(n) before
    sd      t2, 0(s8)
    sd      t1, (L + 8)(sp)
    addi    a0, s2, Attestation_committee_bits
    mv      a1, s7
    call    lantern_get_committee_indices
    PART    t0, t1, s2, Attestation_aggregation_bits
    sd      t0, (L + 16)(sp)
    sd      t1, (L + 24)(sp)
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s4)
    sd      zero, LIST_COUNT(s4)
    li      s9, 0
    addi    s10, s7, LIST_FIXED
    ld      t0, LIST_COUNT(s7)
    slli    t0, t0, 3
    add     t0, s10, t0
    sd      t0, (L + 32)(sp)
1:  ld      t0, (L + 32)(sp)
    bgeu    s10, t0, 4f
    ld      t0, 0(s10)
    addi    s10, s10, 8
    sd      t0, L(sp)
    ld      t0, (L + 8)(sp)
    sd      t0, 0(s3)
    mv      a0, s1                          # committee = get_beacon_committee(state, data.slot, committee_index)
    addi    a1, s2, (Attestation_data + AttestationData_slot)
    addi    a2, sp, L
    mv      a3, s3
    mv      a4, s8
    call    lantern_get_beacon_committee
    bnez    a0, 7f
    ld      t0, LIST_COUNT(s8)
    addi    t1, s8, LIST_FIXED
    ld      t2, (L + 16)(sp)                # bits
    ld      t3, (L + 24)(sp)                # bit count
    ld      t4, LIST_COUNT(s4)
    slli    t5, t4, 3
    add     t5, s4, t5
    addi    t5, t5, LIST_FIXED
2:  beqz    t0, 3f
    bgeu    s9, t3, 8f                      # aggregation_bits[committee_offset + index]
    srli    t6, s9, 3
    add     t6, t2, t6
    lbu     t6, 0(t6)
    andi    a6, s9, 7
    srl     t6, t6, a6
    ld      a6, 0(t1)
    addi    t1, t1, 8
    andi    t6, t6, 1
    beqz    t6, 25f
    sd      a6, 0(t5)
    addi    t5, t5, 8
    addi    t4, t4, 1
25: addi    s9, s9, 1
    addi    t0, t0, -1
    j       2b
3:  sd      t4, LIST_COUNT(s4)
    j       1b
4:  addi    a0, s4, LIST_FIXED              # a set: ascending
    ld      a1, LIST_COUNT(s4)
    call    sort_u64
    li      a0, LANTERN_OK
7:  LEAVE 48
8:  li      a0, LANTERN_INVALID_ATTESTATION
    LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END get_attesting_indices
.else
/*
 * Before electra: the committee of data.index. A PendingAttestation of phase0 has the same
 * aggregation_bits and data, so the function also takes one.
 * s1 state, s2 attestation, s3 scratch, s4 out, s5 scratch size, s6 n, s7 committee.
 */
.if FORK == FORK_PHASE0
.if (PendingAttestation_aggregation_bits != Attestation_aggregation_bits) || (PendingAttestation_data != Attestation_data)
.error "PendingAttestation does not start with the fields of Attestation"
.endif
.endif
SPEC_FUNCTION get_attesting_indices
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH s3, s1, 3, 9f
    LDQ     s6, s1, BeaconState_validators + 8
    slli    t0, s6, 3                       # out has room for every validator
    addi    t0, t0, LIST_FIXED
    ld      t1, LIST_SIZE(s4)
    bltu    t1, t0, 9f
    ld      s5, 0(s3)
    SCRATCH_LIST s7, s3, s5, 0, s6          # the committee: the last list
    SCRATCH_GIVE s3, s5, 1, s6
    mv      a0, s1                          # committee = get_beacon_committee(state, data.slot, data.index)
    addi    a1, s2, (Attestation_data + AttestationData_slot)
    addi    a2, s2, (Attestation_data + AttestationData_index)
    mv      a3, s3
    mv      a4, s7
    call    lantern_get_beacon_committee
    bnez    a0, 7f
    PART    t2, t3, s2, Attestation_aggregation_bits
    ld      t0, LIST_COUNT(s7)
    addi    t1, s7, LIST_FIXED
    li      t4, LIST_FIXED
    sd      t4, LIST_OFFSET(s4)
    li      t4, 0                           # the count
    addi    t5, s4, LIST_FIXED
    li      s8, 0                           # i
2:  bgeu    s8, t0, 3f
    bgeu    s8, t3, 8f                      # aggregation_bits[i]
    srli    t6, s8, 3
    add     t6, t2, t6
    lbu     t6, 0(t6)
    andi    a6, s8, 7
    srl     t6, t6, a6
    ld      a6, 0(t1)
    addi    t1, t1, 8
    andi    t6, t6, 1
    beqz    t6, 25f
    sd      a6, 0(t5)
    addi    t5, t5, 8
    addi    t4, t4, 1
25: addi    s8, s8, 1
    j       2b
3:  sd      t4, LIST_COUNT(s4)
    addi    a0, s4, LIST_FIXED              # a set: ascending
    mv      a1, t4
    call    sort_u64
    li      a0, LANTERN_OK
7:  LEAVE 16
8:  li      a0, LANTERN_INVALID_ATTESTATION
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_attesting_indices
.endif

/* s1 state, s2 attestation, s3 scratch, s4 out, s5 scratch size, s6 n, s7 the attesting list. */
SPEC_FUNCTION get_indexed_attestation
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH_B s3, s1, 4, CIDX_BYTES, 9f
    LDQ     s6, s1, BeaconState_validators + 8
    ld      s5, 0(s3)
    SCRATCH_LIST s7, s3, s5, 0, s6
    SCRATCH_GIVE s3, s5, 1, s6
    mv      a0, s1
    mv      a1, s2
    mv      a2, s3
    mv      a3, s7
    call    lantern_get_attesting_indices
    bnez    a0, 7f
    ld      t0, LIST_COUNT(s7)              # out: attesting_indices, data, signature
    slli    t1, t0, 3
    li      t2, IndexedAttestation__fixed
    add     t1, t1, t2
    ld      t3, 0(s4)
    bltu    t3, t1, 9f
    sd      t2, IndexedAttestation_attesting_indices(s4)
    sd      t0, (IndexedAttestation_attesting_indices + 8)(s4)
    add     a0, s4, t2
    addi    a1, s7, LIST_FIXED
    slli    a2, t0, 3
    call    lantern_copy
    addi    a0, s4, IndexedAttestation_data
    addi    a1, s2, Attestation_data
    li      a2, AttestationData__mem
    call    lantern_copy
    addi    a0, s4, IndexedAttestation_signature
    addi    a1, s2, Attestation_signature
    li      a2, 96
    call    lantern_copy
    li      a0, LANTERN_OK
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_indexed_attestation

/*
 * s1 state, s2 indexed attestation, s3 scratch, s4 out, s5 scratch size, s6 keys,
 * s7 indices, s8 count. Locals: L domain type, L+8 domain (32), L+40 message (24 + 32).
 */
SPEC_FUNCTION is_valid_indexed_attestation
    ENTER 96
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    sd      zero, 0(s4)
    PART    s7, s8, s2, IndexedAttestation_attesting_indices
    beqz    s8, 8f                          # len(indices) == 0: False
    li      t0, 1                           # indices sorted and unique
1:  bgeu    t0, s8, 2f
    slli    t1, t0, 3
    add     t1, s7, t1
    ld      t2, -8(t1)
    ld      t3, 0(t1)
    bleu    t3, t2, 8f
    addi    t0, t0, 1
    j       1b
2:  addi    t0, s8, -1                      # the largest index names a validator
    slli    t0, t0, 3
    add     t0, s7, t0
    ld      t0, 0(t0)
    LDQ     t1, s1, BeaconState_validators + 8
    bgeu    t0, t1, 6f
    li      t0, 48                          # pubkeys: a BlsPublicKeyList at the end of scratch
    mul     t0, t0, s8
    addi    t0, t0, (24 + 7)
    andi    t0, t0, -8
    ld      s5, 0(s3)
    li      t1, LANTERN_SCRATCH_FIXED
    add     t1, t1, t0
    bltu    s5, t1, 9f
    sub     t1, s5, t0
    add     s6, s3, t1
    sd      t0, 0(s6)
    li      t2, 24
    sd      t2, 8(s6)
    sd      s8, 16(s6)
    sd      t1, 0(s3)
    addi    t2, s6, 24
    PART    t3, t4, s1, BeaconState_validators
    li      t0, 0
3:  bgeu    t0, s8, 4f
    slli    t1, t0, 3
    add     t1, s7, t1
    ld      t1, 0(t1)
    slli    t1, t1, 7
    add     t1, t3, t1
    .irp k, 0, 8, 16, 24, 32, 40
    ld      t4, (Validator_pubkey + \k)(t1)
    sd      t4, \k(t2)
    .endr
    addi    t2, t2, 48
    addi    t0, t0, 1
    j       3b
4:  li      t0, DOMAIN_BEACON_ATTESTER      # domain = get_domain(state, DOMAIN_BEACON_ATTESTER, data.target.epoch)
    sw      t0, L(sp)
    mv      a0, s1
    addi    a1, sp, L
    addi    a2, s2, (IndexedAttestation_data + AttestationData_target + Checkpoint_epoch)
    mv      a3, s3
    addi    a4, sp, (L + 8)
    call    lantern_get_domain
    bnez    a0, 7f
    ADDRESS a0, lantern_type_AttestationData
    addi    a1, s2, IndexedAttestation_data
    addi    a2, sp, (L + 8)
    mv      a3, s3
    addi    a4, sp, (L + 64)
    call    lantern_compute_signing_root
    bnez    a0, 7f
    li      t0, 56
    sd      t0, (L + 40)(sp)
    li      t0, 24
    sd      t0, (L + 48)(sp)
    li      t0, 32
    sd      t0, (L + 56)(sp)
    mv      a0, s6                          # bls.FastAggregateVerify(pubkeys, signing_root, signature)
    addi    a1, sp, (L + 40)
    addi    a2, s2, IndexedAttestation_signature
    mv      a3, s3
    mv      a4, s4
    CALL_GLOBAL crypto_bls_fast_aggregate_verify
7:  LEAVE 96
8:  li      a0, LANTERN_OK
    LEAVE 96
6:  li      a0, LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 96
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 96
SPEC_END is_valid_indexed_attestation

.if FORK >= FORK_ALTAIR
/*
 * s1 state, s2 data, s3 delay, s4 out, s5 matching source, s6 matching target, s7 matching head.
 * Locals: L current epoch, L+8 target root (32), L+40 head root (32), L+72 SLOTS_PER_EPOCH, L+80 its root.
 */
SPEC_FUNCTION get_attestation_participation_flag_indices
    ENTER 96
    mv      s1, a0
    mv      s2, a1
    ld      s3, 0(a2)
    mv      s4, a3
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, (AttestationData_target + Checkpoint_epoch)(s2)
    ld      t1, L(sp)
    ADDQ    t2, s1, BeaconState_current_justified_checkpoint
    beq     t0, t1, 1f                      # justified_checkpoint
    ADDQ    t2, s1, BeaconState_previous_justified_checkpoint
1:  ld      t3, Checkpoint_epoch(t2)        # is_matching_source = data.source == justified_checkpoint
    ld      t4, (AttestationData_source + Checkpoint_epoch)(s2)
    li      s5, 0
    bne     t3, t4, 11f
    addi    t0, s2, (AttestationData_source + Checkpoint_root)
    addi    t1, t2, Checkpoint_root
    NE32    t0, t1, 11f
    li      s5, 1
11: mv      a0, s1                          # target_root = get_block_root(state, data.target.epoch)
    addi    a1, s2, (AttestationData_target + Checkpoint_epoch)
    addi    a2, sp, (L + 8)
    call    lantern_get_block_root
    bnez    a0, 7f
    li      s6, 0
    addi    t0, s2, (AttestationData_target + Checkpoint_root)
    addi    t1, sp, (L + 8)
    NE32    t0, t1, 2f
    mv      s6, s5                          # is_matching_target = is_matching_source and target_root_matches
2:  mv      a0, s1                          # head_root = get_block_root_at_slot(state, data.slot)
    addi    a1, s2, AttestationData_slot
    addi    a2, sp, (L + 40)
    call    lantern_get_block_root_at_slot
    bnez    a0, 7f
    li      s7, 0
    addi    t0, s2, AttestationData_beacon_block_root
    addi    t1, sp, (L + 40)
    NE32    t0, t1, 3f
    mv      s7, s6
3:  li      a0, LANTERN_INVALID_SOURCE      # assert is_matching_source
    beqz    s5, 7f
    li      t0, SLOTS_PER_EPOCH
    sd      t0, (L + 72)(sp)
    addi    a0, sp, (L + 72)
    addi    a1, sp, (L + 80)
    call    lantern_integer_squareroot
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s4)
    addi    t1, s4, LIST_FIXED
    ld      t2, (L + 80)(sp)
    bgtu    s3, t2, 4f                      # source within integer_squareroot(SLOTS_PER_EPOCH)
    li      t3, TIMELY_SOURCE_FLAG_INDEX
    sd      t3, 0(t1)
    addi    t1, t1, 8
4:  beqz    s6, 5f
.if FORK < FORK_DENEB
    li      t3, SLOTS_PER_EPOCH             # and inclusion_delay <= SLOTS_PER_EPOCH
    bgtu    s3, t3, 5f
.endif
    li      t3, TIMELY_TARGET_FLAG_INDEX
    sd      t3, 0(t1)
    addi    t1, t1, 8
5:  beqz    s7, 6f
    li      t3, MIN_ATTESTATION_INCLUSION_DELAY
    bne     s3, t3, 6f
    li      t3, TIMELY_HEAD_FLAG_INDEX
    sd      t3, 0(t1)
    addi    t1, t1, 8
6:  addi    t2, s4, LIST_FIXED
    sub     t1, t1, t2
    srli    t1, t1, 3
    sd      t1, LIST_COUNT(s4)
    li      a0, LANTERN_OK
7:  LEAVE 96
SPEC_END get_attestation_participation_flag_indices
.endif

.if FORK == FORK_PHASE0
/*
 * s1 state, s2 attestation, s3 config, s4 scratch, s5 result, s6 scratch size,
 * s8 the PartRef offset of the list to append to, s9 the indexed attestation, s10 the committee.
 * Locals: L previous epoch, L+8 current epoch, L+16 committees per slot, L+24 valid,
 * L+32 proposer index, L+40 the scratch size callees get, L+48 the new value, L+56 its bit bytes.
 */
SPEC_FUNCTION process_attestation
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH_B s4, s1, 10, ATTEST_EXTRA, 9f
    sd      zero, 0(s5)
    ld      s6, 0(s4)
    LDQ     t1, s1, BeaconState_validators + 8
    slli    t1, t1, 3
    addi    t1, t1, LIST_FIXED              # own scratch at the end: the indexed attestation, the committee
    li      t2, IndexedAttestation__fixed + 8
    add     t2, t2, t1
    sub     t0, s6, t2
    add     s9, s4, t0
    sd      t2, 0(s9)
    sub     t0, t0, t1
    add     s10, s4, t0
    sd      t1, 0(s10)
    sd      t0, (L + 40)(sp)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_previous_epoch
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_get_current_epoch
    li      a0, LANTERN_INVALID_ATTESTATION
    ld      t0, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s2)
    ld      t1, L(sp)                       # assert data.target.epoch in (previous, current)
    beq     t0, t1, 1f
    ld      t1, (L + 8)(sp)
    bne     t0, t1, 6f
1:  ld      t2, (Attestation_data + AttestationData_slot)(s2)
    srli    t3, t2, LOG2_SLOTS_PER_EPOCH    # assert data.target.epoch == compute_epoch_at_slot(data.slot)
    bne     t3, t0, 6f
    addi    t3, t2, MIN_ATTESTATION_INCLUSION_DELAY     # assert data.slot + MIN_ATTESTATION_INCLUSION_DELAY <= state.slot
    bltu    t3, t2, 5f
    LDQ     t4, s1, BeaconState_slot
    bltu    t4, t3, 6f
    addi    t3, t2, SLOTS_PER_EPOCH         # assert state.slot <= data.slot + SLOTS_PER_EPOCH
    bltu    t3, t2, 5f
    bltu    t3, t4, 6f
    ld      t0, (L + 40)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # assert data.index < get_committee_count_per_slot(state, data.target.epoch)
    addi    a1, s2, (Attestation_data + AttestationData_target + Checkpoint_epoch)
    mv      a2, s4
    addi    a3, sp, (L + 16)
    call    lantern_get_committee_count_per_slot
    bnez    a0, 7f
    li      a0, LANTERN_INVALID_ATTESTATION
    ld      t0, (Attestation_data + AttestationData_index)(s2)
    ld      t1, (L + 16)(sp)
    bgeu    t0, t1, 6f
    ld      t0, (L + 40)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # committee = get_beacon_committee(state, data.slot, data.index)
    addi    a1, s2, (Attestation_data + AttestationData_slot)
    addi    a2, s2, (Attestation_data + AttestationData_index)
    mv      a3, s4
    mv      a4, s10
    call    lantern_get_beacon_committee
    CHECK_STATUS s5, 7f, 8f
    ld      t0, LIST_COUNT(s10)
    LDQ     t1, s2, Attestation_aggregation_bits + 8
    li      a0, LANTERN_INVALID_ATTESTATION
    bne     t0, t1, 6f                      # assert len(attestation.aggregation_bits) == len(committee)
    ld      t0, (L + 40)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # proposer_index = get_beacon_proposer_index(state)
    mv      a1, s4
    addi    a2, sp, (L + 32)
    call    lantern_get_beacon_proposer_index
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s2)
    ld      t1, (L + 8)(sp)
    bne     t0, t1, 1f
    ADDQ    t1, s1, BeaconState_current_justified_checkpoint
    li      s8, BeaconState_current_epoch_attestations
    j       2f
1:  ADDQ    t1, s1, BeaconState_previous_justified_checkpoint
    li      s8, BeaconState_previous_epoch_attestations
2:  addi    t0, s2, (Attestation_data + AttestationData_source)
    li      a0, LANTERN_INVALID_ATTESTATION
    ld      t2, Checkpoint_epoch(t0)        # assert data.source == the justified checkpoint of its epoch
    ld      t3, Checkpoint_epoch(t1)
    bne     t2, t3, 6f
    addi    t0, t0, Checkpoint_root
    addi    t1, t1, Checkpoint_root
    NE32    t0, t1, 6f
    ld      t0, (L + 40)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # assert is_valid_indexed_attestation(state, get_indexed_attestation(...))
    mv      a1, s2
    mv      a2, s4
    mv      a3, s9
    call    lantern_get_indexed_attestation
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 40)(sp)
    sd      t0, 0(s4)
    mv      a0, s1
    mv      a1, s9
    mv      a2, s4
    addi    a3, sp, (L + 24)
    call    lantern_is_valid_indexed_attestation
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 24)(sp)
    li      a0, LANTERN_INVALID_ATTESTATION
    beqz    t0, 6f
    add     t0, s1, s8                      # append the PendingAttestation: the end of the list's entries
    ld      t1, 0(t0)
    ld      t2, 8(t0)
    add     t3, s1, t1
3:  beqz    t2, 4f
    ld      t4, 0(t3)
    add     t3, t3, t4
    addi    t2, t2, -1
    j       3b
4:  li      t4, BeaconState_previous_epoch_attestations
    bne     s8, t4, 41f
    LDQ     t5, s1, BeaconState_current_epoch_attestations  # the list ends where the next part starts
    j       42f
41: ld      t5, 0(s1)                       # or at the end of the value
42: add     t5, s1, t5
    LDQ     t6, s2, Attestation_aggregation_bits + 8
    addi    t2, t6, 7
    srli    t2, t2, 3                       # the bytes of aggregation_bits
    li      t4, PendingAttestation__fixed + 7
    add     t4, t4, t2
    andi    t4, t4, -8                      # the PendingAttestation's size
    add     t1, t3, t4
    bltu    t5, t1, 9f                      # no room: the state is unchanged
    beqz    t2, 43f
    add     t1, t3, t4                      # zero the padding after the bit bytes
    sd      zero, -8(t1)
43: sd      t4, 0(t3)                       # size; aggregation_bits at the end of the fixed part
    li      t1, PendingAttestation__fixed
    sd      t1, PendingAttestation_aggregation_bits(t3)
    sd      t6, (PendingAttestation_aggregation_bits + 8)(t3)
    LDQ     t1, s1, BeaconState_slot        # inclusion_delay = state.slot - data.slot
    ld      t0, (Attestation_data + AttestationData_slot)(s2)
    sub     t1, t1, t0
    sd      t1, PendingAttestation_inclusion_delay(t3)
    ld      t1, (L + 32)(sp)
    sd      t1, PendingAttestation_proposer_index(t3)
    sd      t3, (L + 48)(sp)
    sd      t2, (L + 56)(sp)
    addi    a0, t3, PendingAttestation_data
    addi    a1, s2, Attestation_data
    li      a2, AttestationData__mem
    call    lantern_copy
    ld      a0, (L + 48)(sp)
    addi    a0, a0, PendingAttestation__fixed
    PART    a1, t0, s2, Attestation_aggregation_bits
    ld      a2, (L + 56)(sp)
    call    lantern_copy
    add     t0, s1, s8                      # the count, last
    ld      t1, 8(t0)
    addi    t1, t1, 1
    sd      t1, 8(t0)
8:  li      a0, LANTERN_OK
7:  LEAVE 64
5:  li      a0, LANTERN_INVALID_OVERFLOW
6:  sd      a0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 64
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END process_attestation
.else
/*
 * s1 state, s2 attestation, s3 config, s4 scratch, s5 result, s6 scratch size, s7 n,
 * s8 committee indices, s9 committee, s10 committee offset.
 * Locals: L previous epoch, L+8 current epoch, L+16 committees per slot, L+24 committee index,
 * L+32 inclusion delay, L+40 valid, L+48 flags (FLAGS_BYTES), L+96 proposer, L+104 base reward,
 * L+112 index, L+120 proposer reward numerator, L+128 flag, L+136 cursor end, L+144 the indexed
 * attestation, L+152 the attesting list, L+160 the scratch size callees get, L+168 participation,
 * L+176 base reward per increment.
 */
SPEC_FUNCTION process_attestation
    ENTER 192
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH_B s4, s1, 10, ATTEST_EXTRA, 9f
    sd      zero, 0(s5)
    ld      s6, 0(s4)
    LDQ     s7, s1, BeaconState_validators + 8
    li      t0, CIDX_BYTES                  # own scratch at the end: committee indices, committee, indexed attestation, attesting
    sub     t1, s6, t0
    add     s8, s4, t1
    sd      t0, 0(s8)
    slli    t2, s7, 3
    addi    t2, t2, LIST_FIXED              # L(n)
    sub     t1, t1, t2
    add     s9, s4, t1
    sd      t2, 0(s9)
    li      t3, IndexedAttestation__fixed + 8
    add     t3, t3, t2
    sub     t1, t1, t3
    add     t4, s4, t1
    sd      t3, 0(t4)
    sd      t4, (L + 144)(sp)
    sub     t1, t1, t2
    add     t4, s4, t1
    sd      t2, 0(t4)
    sd      t4, (L + 152)(sp)
    sd      t1, (L + 160)(sp)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_previous_epoch
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_get_current_epoch
    li      a0, LANTERN_INVALID_ATTESTATION
    ld      t0, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s2)
    ld      t1, L(sp)
    ld      t2, (L + 8)(sp)
    beq     t0, t1, 10f                     # assert data.target.epoch in (previous, current)
    bne     t0, t2, 6f
10: ld      t1, (Attestation_data + AttestationData_slot)(s2)
    srli    t2, t1, LOG2_SLOTS_PER_EPOCH    # assert data.target.epoch == compute_epoch_at_slot(data.slot)
    bne     t0, t2, 6f
    addi    t2, t1, MIN_ATTESTATION_INCLUSION_DELAY     # assert data.slot + MIN_ATTESTATION_INCLUSION_DELAY <= state.slot
    bltu    t2, t1, 5f
    LDQ     t3, s1, BeaconState_slot
    bgtu    t2, t3, 6f
.if FORK < FORK_DENEB
    addi    t2, t1, SLOTS_PER_EPOCH         # assert state.slot <= data.slot + SLOTS_PER_EPOCH
    bltu    t2, t1, 5f
    bgtu    t3, t2, 6f
.endif
.if FORK >= FORK_ELECTRA
    ld      t2, (Attestation_data + AttestationData_index)(s2)
    bnez    t2, 6f                          # assert data.index == 0
    addi    a0, s2, Attestation_committee_bits
    mv      a1, s8
    call    lantern_get_committee_indices
    li      s10, 0                          # committee_offset
    addi    t0, s8, LIST_FIXED
    ld      t1, LIST_COUNT(s8)
    slli    t1, t1, 3
    add     t1, t0, t1
    sd      t1, (L + 136)(sp)
    sd      t0, (L + 112)(sp)               # the cursor over committee indices
1:  ld      t0, (L + 112)(sp)
    ld      t1, (L + 136)(sp)
    bgeu    t0, t1, 3f
    ld      t1, 0(t0)
    addi    t0, t0, 8
    sd      t0, (L + 112)(sp)
    sd      t1, (L + 24)(sp)
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # assert committee_index < get_committee_count_per_slot(...)
    addi    a1, s2, (Attestation_data + AttestationData_target + Checkpoint_epoch)
    mv      a2, s4
    addi    a3, sp, (L + 16)
    call    lantern_get_committee_count_per_slot
    bnez    a0, 7f
    ld      t0, (L + 24)(sp)
    ld      t1, (L + 16)(sp)
    li      a0, LANTERN_INVALID_ATTESTATION
    bgeu    t0, t1, 6f
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1
    addi    a1, s2, (Attestation_data + AttestationData_slot)
    addi    a2, sp, (L + 24)
    mv      a3, s4
    mv      a4, s9
    call    lantern_get_beacon_committee
    CHECK_STATUS s5, 7f, 8f
    PART    t1, t2, s2, Attestation_aggregation_bits
    ld      t0, LIST_COUNT(s9)
    li      t3, 0                           # committee_attesters
2:  beqz    t0, 25f
    li      a0, LANTERN_INVALID_ATTESTATION # aggregation_bits[committee_offset + index]
    bgeu    s10, t2, 6f
    srli    t4, s10, 3
    add     t4, t1, t4
    lbu     t4, 0(t4)
    andi    t5, s10, 7
    srl     t4, t4, t5
    andi    t4, t4, 1
    add     t3, t3, t4
    addi    s10, s10, 1
    addi    t0, t0, -1
    j       2b
25: li      a0, LANTERN_INVALID_ATTESTATION
    beqz    t3, 6f                          # assert len(committee_attesters) > 0
    j       1b
3:  LDQ     t0, s2, Attestation_aggregation_bits + 8
    li      a0, LANTERN_INVALID_ATTESTATION # assert len(attestation.aggregation_bits) == committee_offset
    bne     t0, s10, 6f
.else
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # assert data.index < get_committee_count_per_slot(state, data.target.epoch)
    addi    a1, s2, (Attestation_data + AttestationData_target + Checkpoint_epoch)
    mv      a2, s4
    addi    a3, sp, (L + 16)
    call    lantern_get_committee_count_per_slot
    bnez    a0, 7f
    ld      t0, (Attestation_data + AttestationData_index)(s2)
    ld      t1, (L + 16)(sp)
    li      a0, LANTERN_INVALID_ATTESTATION
    bgeu    t0, t1, 6f
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # committee = get_beacon_committee(state, data.slot, data.index)
    addi    a1, s2, (Attestation_data + AttestationData_slot)
    addi    a2, s2, (Attestation_data + AttestationData_index)
    mv      a3, s4
    mv      a4, s9
    call    lantern_get_beacon_committee
    CHECK_STATUS s5, 7f, 8f
    LDQ     t0, s2, Attestation_aggregation_bits + 8
    ld      t1, LIST_COUNT(s9)
    li      a0, LANTERN_INVALID_ATTESTATION # assert len(attestation.aggregation_bits) == len(committee)
    bne     t0, t1, 6f
.endif
    LDQ     t0, s1, BeaconState_slot
    ld      t1, (Attestation_data + AttestationData_slot)(s2)
    sub     t0, t0, t1
    sd      t0, (L + 32)(sp)
    li      t0, FLAGS_BYTES
    sd      t0, (L + 48)(sp)
    mv      a0, s1                          # participation_flag_indices
    addi    a1, s2, Attestation_data
    addi    a2, sp, (L + 32)
    addi    a3, sp, (L + 48)
    call    lantern_get_attestation_participation_flag_indices
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # assert is_valid_indexed_attestation(state, get_indexed_attestation(...))
    mv      a1, s2
    mv      a2, s4
    ld      a3, (L + 144)(sp)
    call    lantern_get_indexed_attestation
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1
    ld      a1, (L + 144)(sp)
    mv      a2, s4
    addi    a3, sp, (L + 40)
    call    lantern_is_valid_indexed_attestation
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 40)(sp)
    li      a0, LANTERN_INVALID_ATTESTATION
    beqz    t0, 6f
    ld      t0, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s2)
    ld      t1, (L + 8)(sp)
    bne     t0, t1, 31f
    PART    t0, t1, s1, BeaconState_current_epoch_participation
    j       32f
31: PART    t0, t1, s1, BeaconState_previous_epoch_participation
32: sd      t0, (L + 168)(sp)
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # for index in get_attesting_indices(state, attestation)
    mv      a1, s2
    mv      a2, s4
    ld      a3, (L + 152)(sp)
    call    lantern_get_attesting_indices
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # get_base_reward's factor, once for every index
    mv      a1, s4
    addi    a2, sp, (L + 176)
    call    lantern_get_base_reward_per_increment
    bnez    a0, 7f
    sd      zero, (L + 120)(sp)
    ld      s8, (L + 152)(sp)               # the attesting list; the committee indices are done
    addi    s9, s8, LIST_FIXED
    ld      t0, LIST_COUNT(s8)
    slli    t0, t0, 3
    add     t0, s9, t0
    sd      t0, (L + 136)(sp)
4:  ld      t0, (L + 136)(sp)
    bgeu    s9, t0, 45f
    ld      t0, 0(s9)
    addi    s9, s9, 8
    sd      t0, (L + 112)(sp)
    li      s10, 0                          # for flag_index, weight in enumerate(PARTICIPATION_FLAG_WEIGHTS)
41: li      t0, 3
    bgeu    s10, t0, 4b
    ld      t0, (L + 48 + LIST_COUNT)(sp)   # flag_index in participation_flag_indices
    addi    t1, sp, (L + 48 + LIST_FIXED)
42: beqz    t0, 44f
    ld      t2, 0(t1)
    addi    t1, t1, 8
    beq     t2, s10, 43f
    addi    t0, t0, -1
    j       42b
43: sd      s10, (L + 128)(sp)
    ld      t0, (L + 168)(sp)               # and not has_flag(epoch_participation[index], flag_index)
    ld      t1, (L + 112)(sp)
    add     a0, t0, t1
    addi    a1, sp, (L + 128)
    addi    a2, sp, (L + 40)
    call    lantern_has_flag
    ld      t0, (L + 40)(sp)
    bnez    t0, 44f
    ld      t0, (L + 168)(sp)               # epoch_participation[index] = add_flag(...)
    ld      t1, (L + 112)(sp)
    add     a0, t0, t1
    addi    a1, sp, (L + 128)
    mv      a2, a0
    call    lantern_add_flag
    PART    t0, t1, s1, BeaconState_validators
    ld      t2, (L + 112)(sp)               # proposer_reward_numerator += get_base_reward(state, index) * weight
    slli    t2, t2, 7
    add     t0, t0, t2
    ld      t0, Validator_effective_balance(t0)
    li      t1, EFFECTIVE_BALANCE_INCREMENT
    divu    t0, t0, t1                      # increments * base_reward_per_increment
    ld      t1, (L + 176)(sp)
    mul     t0, t0, t1
    li      t1, TIMELY_SOURCE_WEIGHT        # the source and head weights are equal
    li      t2, TIMELY_TARGET_FLAG_INDEX
    bne     s10, t2, 46f
    li      t1, TIMELY_TARGET_WEIGHT
46: mul     t0, t0, t1
    ld      t1, (L + 120)(sp)
    add     t1, t1, t0
    bltu    t1, t0, 5f
    sd      t1, (L + 120)(sp)
44: addi    s10, s10, 1
    j       41b
45: ld      t0, (L + 120)(sp)               # proposer_reward = numerator // proposer_reward_denominator
    li      t1, ((WEIGHT_DENOMINATOR - PROPOSER_WEIGHT) * WEIGHT_DENOMINATOR / PROPOSER_WEIGHT)
    divu    t0, t0, t1
    sd      t0, (L + 120)(sp)
.if FORK >= FORK_FULU
    mv      a0, s1
    addi    a1, sp, (L + 96)
    call    lantern_get_beacon_proposer_index
.else
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1
    mv      a1, s4
    addi    a2, sp, (L + 96)
    call    lantern_get_beacon_proposer_index
    bnez    a0, 7f
.endif
    mv      a0, s1
    addi    a1, sp, (L + 96)
    addi    a2, sp, (L + 120)
    call    lantern_increase_balance
8:  li      a0, LANTERN_OK
7:  LEAVE 192
5:  li      a0, LANTERN_INVALID_OVERFLOW
6:  sd      a0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 192
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 192
SPEC_END process_attestation
.endif

.if TIMELY_SOURCE_WEIGHT != TIMELY_HEAD_WEIGHT
.error "lantern_process_attestation takes the source weight for the head flag"
.endif
