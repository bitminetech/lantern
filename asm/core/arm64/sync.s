/*
 * Sync committee selection, ARM64. Requirements: docs/reference/epoch-processing.md.
 */

.set SYNC_INDICES_BYTES, LIST_FIXED + 8 * SYNC_COMMITTEE_SIZE           /* an IndexList of the members */
.set SYNC_KEYS_BYTES, 24 + 48 * SYNC_COMMITTEE_SIZE                     /* a BlsPublicKeyList of the members */
.set SYNC_COMMITTEE_SCRATCH, SYNC_INDICES_BYTES + SYNC_KEYS_BYTES

/*
 * x19 state, x20 scratch, x21 out, x22 validator count, x23 scratch size, x24 active list,
 * x25 active count, x26 i, x27 members so far, x28 candidate.
 * Locals: L epoch, L+8 domain type, L+16 seed, L+48 message (seed, i // 16 from electra, i // 32 before), L+88 digest,
 * L+120 the entries of the permutation, L+136 active count.
 */
SPEC_FUNCTION get_next_sync_committee_indices
    ENTER 144
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x9, [x21, #LIST_SIZE]
    MOVQ    x10, SYNC_INDICES_BYTES
    cmp     x9, x10
    b.lo    9f
    NEED_SCRATCH x20, x19, 2, 9f
    LDQ     x22, x19, BeaconState_validators + 8
    ldr     x23, [x20]
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #L]
    add     x9, x9, #1                      /* epoch = get_current_epoch(state) + 1 */
    str     x9, [sp, #L]
    SCRATCH_LIST x24, x20, x23, 0, x22
    mov     x0, x19
    add     x1, sp, #L
    mov     x2, x24
    bl      lantern_get_active_validator_indices
    cbnz    x0, 7f
    ldr     x25, [x24, #LIST_COUNT]
    cbz     x25, 8f                         /* i % active_validator_count divides by 0 */
    str     x25, [sp, #(L + 136)]
    mov     w9, #DOMAIN_SYNC_COMMITTEE
    str     w9, [sp, #(L + 8)]
    mov     x0, x19
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    add     x3, sp, #(L + 16)
    bl      lantern_get_seed
    cbnz    x0, 7f
    add     x9, sp, #(L + 48)
    add     x10, sp, #(L + 16)
    COPY32  x9, x10
    SCRATCH_LIST x9, x20, x23, 1, x22
    add     x10, x9, #LIST_FIXED
    str     x10, [sp, #(L + 120)]
    SCRATCH_GIVE x20, x23, 2, x22
    add     x0, sp, #(L + 136)              /* every compute_shuffled_index: one permutation of the active count */
    add     x1, sp, #(L + 16)
    mov     x2, x20
    mov     x3, x9
    bl      lantern_compute_shuffled_permutation
    cbnz    x0, 7f
    mov     x9, #LIST_FIXED
    str     x9, [x21, #LIST_OFFSET]
    mov     x27, #0
    mov     x26, #0
1:  cmp     x27, #SYNC_COMMITTEE_SIZE
    b.hs    3f
    udiv    x9, x26, x25
    msub    x9, x9, x25, x26
    ldr     x10, [sp, #(L + 120)]           /* compute_shuffled_index(i % active_validator_count, ...) */
    ldr     x9, [x10, x9, lsl #3]
    add     x10, x24, #LIST_FIXED
    ldr     x28, [x10, x9, lsl #3]          /* candidate_index */
.if FORK >= FORK_ELECTRA
    lsr     x9, x26, #4
.else
    lsr     x9, x26, #5
.endif
    str     x9, [sp, #(L + 80)]
    add     x0, sp, #(L + 48)               /* random_bytes = sha256(seed + uint_to_bytes(i // 16)) */
    mov     x1, #40
    add     x2, sp, #(L + 88)
    bl      lantern_sha256_short
.if FORK >= FORK_ELECTRA
    and     x9, x26, #15
    lsl     x9, x9, #1
    add     x10, sp, #(L + 88)
    ldrh    w9, [x10, x9]                   /* random_value */
.else
    and     x9, x26, #31
    add     x10, sp, #(L + 88)
    ldrb    w9, [x10, x9]                   /* random_byte = sha256(seed + uint_to_bytes(i // 32))[i % 32] */
.endif
    PART    x10, x11, x19, BeaconState_validators
    add     x10, x10, x28, lsl #7
    ldr     x10, [x10, #Validator_effective_balance]
.if FORK >= FORK_ELECTRA
    mov     x11, #0xffff                    /* MAX_RANDOM_VALUE */
.else
    mov     x11, #0xff                      /* MAX_RANDOM_BYTE */
.endif
    umulh   x12, x10, x11
    cbnz    x12, 6f
    mul     x10, x10, x11
.if FORK >= FORK_ELECTRA
    MOVQ    x11, MAX_EFFECTIVE_BALANCE_ELECTRA
.else
    MOVQ    x11, MAX_EFFECTIVE_BALANCE
.endif
    mul     x11, x11, x9
    cmp     x10, x11
    b.lo    2f
    add     x10, x21, #LIST_FIXED
    str     x28, [x10, x27, lsl #3]
    add     x27, x27, #1
2:  add     x26, x26, #1
    b       1b
3:  str     x27, [x21, #LIST_COUNT]
    mov     x0, #LANTERN_OK
7:  LEAVE 144
6:  mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 144
8:  mov     x0, #LANTERN_INVALID_NO_INDICES
    LEAVE 144
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 144
SPEC_END get_next_sync_committee_indices

/* x19 state, x20 scratch, x21 out, x22 scratch size, x23 member, x24 indices, x25 keys. */
SPEC_FUNCTION get_next_sync_committee
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    NEED_SCRATCH_B x20, x19, 2, SYNC_COMMITTEE_SCRATCH, 9f
    ldr     x22, [x20]
    MOVQ    x9, SYNC_INDICES_BYTES
    sub     x10, x22, x9
    add     x24, x20, x10
    str     x9, [x24]
    MOVQ    x9, SYNC_COMMITTEE_SCRATCH
    sub     x10, x22, x9
    add     x25, x20, x10
    str     x10, [x20]
    mov     x0, x19
    mov     x1, x20
    mov     x2, x24
    bl      lantern_get_next_sync_committee_indices
    cbnz    x0, 7f
    MOVQ    x9, SYNC_KEYS_BYTES             /* pubkeys = [state.validators[index].pubkey for index in indices] */
    str     x9, [x25]
    mov     x9, #24
    str     x9, [x25, #8]
    mov     x9, #SYNC_COMMITTEE_SIZE
    str     x9, [x25, #16]
    add     x10, x24, #LIST_FIXED
    add     x11, x25, #24
    add     x12, x21, #SyncCommittee_pubkeys
    mov     x23, #0
1:  cmp     x23, #SYNC_COMMITTEE_SIZE
    b.hs    2f
    ldr     x13, [x10, x23, lsl #3]
    PART    x14, x15, x19, BeaconState_validators
    add     x14, x14, x13, lsl #7
    ldp     x15, x13, [x14, #Validator_pubkey]
    stp     x15, x13, [x11]
    stp     x15, x13, [x12]
    ldp     x15, x13, [x14, #(Validator_pubkey + 16)]
    stp     x15, x13, [x11, #16]
    stp     x15, x13, [x12, #16]
    ldp     x15, x13, [x14, #(Validator_pubkey + 32)]
    stp     x15, x13, [x11, #32]
    stp     x15, x13, [x12, #32]
    add     x11, x11, #48
    add     x12, x12, #48
    add     x23, x23, #1
    b       1b
2:  mov     x0, x25                         /* aggregate_pubkey = eth_aggregate_pubkeys(pubkeys) */
    MOVQ    x9, SyncCommittee_aggregate_pubkey
    add     x1, x21, x9
    CALL_GLOBAL crypto_bls_eth_aggregate_pubkeys
    cbz     x0, 7f
    mov     x0, #LANTERN_INVALID_AGGREGATE_PUBKEYS
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_next_sync_committee

/* x19 state, x20 config, x21 scratch, x22 result, x23 scratch size, x24 new committee. Locals: L epoch. */
SPEC_FUNCTION process_sync_committee_updates
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    str     xzr, [x22]
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #L]
    add     x9, x9, #1
    and     x9, x9, #(EPOCHS_PER_SYNC_COMMITTEE_PERIOD - 1)
    cbnz    x9, 8f
    NEED_SCRATCH_B x21, x19, 2, SYNC_COMMITTEE_SCRATCH + SyncCommittee__mem, 9f
    ldr     x23, [x21]
    MOVQ    x9, SyncCommittee__mem
    sub     x10, x23, x9
    add     x24, x21, x10
    str     x10, [x21]
    mov     x0, x19
    mov     x1, x21
    mov     x2, x24
    bl      lantern_get_next_sync_committee
    CHECK_STATUS x22, 7f, 8f
    ADDQ    x0, x19, BeaconState_current_sync_committee   /* current = next; next = the new committee */
    ADDQ    x1, x19, BeaconState_next_sync_committee
    MOVQ    x2, SyncCommittee__mem
    bl      lantern_copy
    ADDQ    x0, x19, BeaconState_next_sync_committee
    mov     x1, x24
    MOVQ    x2, SyncCommittee__mem
    bl      lantern_copy
8:  mov     x0, #LANTERN_OK
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END process_sync_committee_updates

.if EPOCHS_PER_SYNC_COMMITTEE_PERIOD & (EPOCHS_PER_SYNC_COMMITTEE_PERIOD - 1)
.error "EPOCHS_PER_SYNC_COMMITTEE_PERIOD is not a power of two"
.endif
