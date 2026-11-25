/*
 * Phase0's epoch accounting by PendingAttestation, ARM64: the matching attestations, their
 * unslashed attesting indices and balance, the attestation deltas, and the epoch steps that
 * read them. Requirements: docs/reference/epoch-processing.md.
 *
 * A list of matching attestations is an IndexList of the offsets of PendingAttestation values
 * from the start of the state, in the order of the state's list.
 */

/* The IndexList of the matching attestations of one epoch, at the end of a function's scratch. */
.set PENDING_REFS_BYTES, LIST_FIXED + 8 * MAX_ATTESTATIONS * SLOTS_PER_EPOCH

/* dst = get_base_reward of a validator of effective balance eb, with the square root of the total active balance in sqrt. Uses x16. */
.macro BASE_REWARD dst, eb, sqrt
    mov     x16, #BASE_REWARD_FACTOR
    mul     \dst, \eb, x16
    udiv    \dst, \dst, \sqrt
    lsr     \dst, \dst, #2                  /* // BASE_REWARDS_PER_EPOCH, which is 4 */
.endm
.if BASE_REWARDS_PER_EPOCH != 4
.error "BASE_REWARD divides by BASE_REWARDS_PER_EPOCH with a shift by 2"
.endif

/* Take the refs list from the end of scratch s: refs = its last PENDING_REFS_BYTES, tot = the bytes before. Uses x9. */
.macro TAKE_REFS refs, s, tot
    ldr     \tot, [\s]
    MOVQ    x9, PENDING_REFS_BYTES
    sub     \tot, \tot, x9
    add     \refs, \s, \tot
    str     x9, [\refs]
    str     \tot, [\s]
.endm

/* ---------------------------------------------------------------- Matching attestations */

/* x19 state, x20 out, x21 epoch. Locals: L previous epoch, L+8 current epoch. */
SPEC_FUNCTION get_matching_source_attestations
    ENTER 16
    mov     x19, x0
    ldr     x21, [x1]
    mov     x20, x2
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_previous_epoch
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_current_epoch
    ldp     x9, x10, [sp, #L]
    cmp     x21, x10                        /* the current epoch's list when epoch is current */
    b.ne    1f
    MOVQ    x11, BeaconState_current_epoch_attestations
    b       2f
1:  cmp     x21, x9                         /* assert epoch in (previous, current) */
    b.ne    8f
    MOVQ    x11, BeaconState_previous_epoch_attestations
2:  add     x11, x19, x11
    ldr     x12, [x11]                      /* the part's offset */
    ldr     x13, [x11, #8]                  /* its count */
    lsl     x14, x13, #3
    add     x14, x14, #LIST_FIXED
    ldr     x15, [x20, #LIST_SIZE]
    cmp     x15, x14
    b.lo    9f
    mov     x14, #LIST_FIXED
    str     x14, [x20, #LIST_OFFSET]
    str     x13, [x20, #LIST_COUNT]
    add     x14, x20, #LIST_FIXED
3:  cbz     x13, 4f
    str     x12, [x14], #8
    ldr     x15, [x19, x12]                 /* the next value starts after this one's size */
    add     x12, x12, x15
    sub     x13, x13, #1
    b       3b
4:  mov     x0, #LANTERN_OK
    LEAVE 16
8:  mov     x0, #LANTERN_INVALID_PARTICIPATION_EPOCH
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_matching_source_attestations

/* Keep the refs of out x21 for which the 32 bytes at offset off of the attestation equal the root at L. Uses x9-x15, x22-x24. */
.macro KEEP_MATCHING off
    add     x22, x21, #LIST_FIXED
    mov     x23, x22
    ldr     x9, [x21, #LIST_COUNT]
    add     x24, x22, x9, lsl #3
91: cmp     x22, x24
    b.hs    93f
    ldr     x9, [x22], #8
    add     x14, x19, x9
    add     x14, x14, #(\off)
    add     x15, sp, #L
    NE32    x14, x15, 91b
    str     x9, [x23], #8
    b       91b
93: sub     x9, x23, x21
    sub     x9, x9, #LIST_FIXED
    lsr     x9, x9, #3
    str     x9, [x21, #LIST_COUNT]
.endm

/* x19 state, x20 epoch, x21 out, x22-x24 the filter. Locals: L the epoch's block root (32). */
SPEC_FUNCTION get_matching_target_attestations
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    bl      lantern_get_matching_source_attestations
    cbnz    x0, 7f
    ldr     x9, [x21, #LIST_COUNT]          /* the spec reads the root inside the comprehension: none for no attestation */
    cbz     x9, 8f
    mov     x0, x19                         /* a.data.target.root == get_block_root(state, epoch) */
    mov     x1, x20
    add     x2, sp, #L
    bl      lantern_get_block_root
    cbnz    x0, 7f
    KEEP_MATCHING (PendingAttestation_data + AttestationData_target + Checkpoint_root)
8:  mov     x0, #LANTERN_OK
7:  LEAVE 32
SPEC_END get_matching_target_attestations

/* x19 state, x20 epoch, x21 out, x22 cursor, x23 kept, x24 end, x25 the attestation, x26 its ref. Locals: L root (32). */
SPEC_FUNCTION get_matching_head_attestations
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    bl      lantern_get_matching_target_attestations
    cbnz    x0, 7f
    add     x22, x21, #LIST_FIXED
    mov     x23, x22
    ldr     x9, [x21, #LIST_COUNT]
    add     x24, x22, x9, lsl #3
1:  cmp     x22, x24
    b.hs    3f
    ldr     x26, [x22], #8
    add     x25, x19, x26
    mov     x0, x19                         /* a.data.beacon_block_root == get_block_root_at_slot(state, a.data.slot) */
    add     x1, x25, #(PendingAttestation_data + AttestationData_slot)
    add     x2, sp, #L
    bl      lantern_get_block_root_at_slot
    cbnz    x0, 7f
    add     x14, x25, #(PendingAttestation_data + AttestationData_beacon_block_root)
    add     x15, sp, #L
    NE32    x14, x15, 1b
    str     x26, [x23], #8
    b       1b
3:  sub     x9, x23, x21
    sub     x9, x9, #LIST_FIXED
    lsr     x9, x9, #3
    str     x9, [x21, #LIST_COUNT]
    mov     x0, #LANTERN_OK
7:  LEAVE 32
SPEC_END get_matching_head_attestations

/* ---------------------------------------------------------------- Attesting indices and balance */

/*
 * x19 state, x20 attestations, x21 scratch, x22 out, x23 scratch size, x24 n, x25 a byte per
 * validator, x26 one attestation's attesting indices, x27 cursor, x28 end.
 * Scratch: list 0 the bytes, list 1 the attesting indices, then get_attesting_indices's S(3).
 */
SPEC_FUNCTION get_unslashed_attesting_indices
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH x21, x19, 5, 9f
    LDQ     x24, x19, BeaconState_validators + 8
    lsl     x9, x24, #3                     /* out has room for every validator */
    add     x9, x9, #LIST_FIXED
    ldr     x10, [x22, #LIST_SIZE]
    cmp     x10, x9
    b.lo    9f
    ldr     x23, [x21]
    SCRATCH_LIST x25, x21, x23, 0, x24
    SCRATCH_LIST x26, x21, x23, 1, x24
    add     x0, x25, #LIST_FIXED
    mov     x1, x24
    bl      lantern_zero
    add     x27, x20, #LIST_FIXED
    ldr     x9, [x20, #LIST_COUNT]
    add     x28, x27, x9, lsl #3
1:  cmp     x27, x28                        /* output = union of get_attesting_indices(state, a) */
    b.hs    3f
    ldr     x9, [x27], #8
    SCRATCH_GIVE x21, x23, 2, x24
    mov     x0, x19
    add     x1, x19, x9
    mov     x3, x21
    mov     x4, x26
    mov     x2, xzr
    bl      lantern_get_attesting_indices
    cbnz    x0, 7f
    ldr     x9, [x26, #LIST_COUNT]
    add     x10, x26, #LIST_FIXED
    add     x11, x25, #LIST_FIXED
    mov     w12, #1
2:  cbz     x9, 1b
    ldr     x13, [x10], #8
    strb    w12, [x11, x13]
    sub     x9, x9, #1
    b       2b
3:  mov     x9, #LIST_FIXED                 /* the set, ascending, without the slashed */
    str     x9, [x22, #LIST_OFFSET]
    PART    x10, x11, x19, BeaconState_validators
    add     x11, x25, #LIST_FIXED
    add     x12, x22, #LIST_FIXED
    mov     x13, #0
    mov     x14, #0
4:  cmp     x13, x24
    b.hs    5f
    ldrb    w15, [x11, x13]
    cbz     w15, 45f
    ldrb    w15, [x10, #Validator_slashed]
    cbnz    w15, 45f
    str     x13, [x12], #8
    add     x14, x14, #1
45: add     x13, x13, #1
    add     x10, x10, #Validator__mem
    b       4b
5:  str     x14, [x22, #LIST_COUNT]
    mov     x0, #LANTERN_OK
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_unslashed_attesting_indices

/* x19 state, x20 attestations, x21 scratch, x22 out, x23 scratch size, x24 n, x25 the indices. Scratch: list 0, then S(5). */
SPEC_FUNCTION get_attesting_balance
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH x21, x19, 6, 9f
    LDQ     x24, x19, BeaconState_validators + 8
    ldr     x23, [x21]
    SCRATCH_LIST x25, x21, x23, 0, x24
    SCRATCH_GIVE x21, x23, 1, x24
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    mov     x3, x25
    bl      lantern_get_unslashed_attesting_indices
    cbnz    x0, 7f
    mov     x0, x19                         /* get_total_balance(state, get_unslashed_attesting_indices(...)) */
    mov     x1, x25
    mov     x2, x22
    bl      lantern_get_total_balance
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_attesting_balance

/* ---------------------------------------------------------------- Rewards and penalties */

/* Locals: sp+16 out, sp+24 base reward. */
SPEC_FUNCTION get_proposer_reward
    FRAME 16
    str     x3, [sp, #16]
    add     x3, sp, #24
    bl      lantern_get_base_reward
    cbnz    x0, 1f
    ldr     x9, [sp, #24]
    mov     x10, #PROPOSER_REWARD_QUOTIENT
    udiv    x9, x9, x10
    ldr     x10, [sp, #16]
    str     x9, [x10]
1:  UNFRAME 16
SPEC_END get_proposer_reward

/*
 * x19 state, x20 attestations, x21 scratch, x22 rewards, x23 penalties, x24 n, x25 unslashed,
 * x26 eligible, x27 cursor over unslashed, x28 its end.
 * Locals: L total balance, L+8 its square root, L+16 attesting balance, L+24 in leak, L+32 scratch size.
 * Scratch: list 0 unslashed, list 1 eligible, then get_unslashed_attesting_indices's S(5).
 */
SPEC_FUNCTION get_attestation_component_deltas
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    NEED_SCRATCH x21, x19, 7, 9f
    LDQ     x24, x19, BeaconState_validators + 8
    ldr     x9, [x21]
    str     x9, [sp, #(L + 32)]
    mov     x0, x22
    mov     x1, x24
    bl      lantern_zero_deltas
    mov     x0, x23
    mov     x1, x24
    bl      lantern_zero_deltas
    ldr     x9, [sp, #(L + 32)]
    SCRATCH_LIST x25, x21, x9, 0, x24
    SCRATCH_LIST x26, x21, x9, 1, x24
    SCRATCH_GIVE x21, x9, 2, x24
    mov     x0, x19                         /* total_balance = get_total_active_balance(state) */
    mov     x1, x21
    add     x2, sp, #L
    bl      lantern_get_total_active_balance
    cbnz    x0, 7f
    add     x0, sp, #L
    add     x1, sp, #(L + 8)
    bl      lantern_integer_squareroot
    ldr     x9, [sp, #(L + 32)]
    SCRATCH_GIVE x21, x9, 2, x24
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    mov     x3, x25
    bl      lantern_get_unslashed_attesting_indices
    cbnz    x0, 7f
    mov     x0, x19                         /* attesting_balance = get_total_balance(state, unslashed_attesting_indices) */
    mov     x1, x25
    add     x2, sp, #(L + 16)
    bl      lantern_get_total_balance
    mov     x0, x19
    mov     x1, x26
    bl      lantern_get_eligible_validator_indices
    cbnz    x0, 7f
    mov     x0, x19
    add     x1, sp, #(L + 24)
    bl      lantern_is_in_inactivity_leak
    add     x27, x25, #LIST_FIXED
    ldr     x9, [x25, #LIST_COUNT]
    add     x28, x27, x9, lsl #3
    add     x9, x26, #LIST_FIXED            /* for index in get_eligible_validator_indices(state) */
    ldr     x10, [x26, #LIST_COUNT]
    add     x10, x9, x10, lsl #3
    PART    x11, x12, x19, BeaconState_validators
    ldr     x12, [sp, #(L + 8)]
    ldr     x13, [sp, #(L + 24)]
    MOVQ    x15, EFFECTIVE_BALANCE_INCREMENT
    ldr     x14, [sp, #L]
    udiv    x14, x14, x15                   /* total_balance // increment */
    ldr     x17, [sp, #(L + 16)]
    udiv    x17, x17, x15                   /* attesting_balance // increment */
    add     x2, x22, #LIST_FIXED
    add     x3, x23, #LIST_FIXED
1:  cmp     x9, x10
    b.hs    5f
    ldr     x4, [x9], #8
    add     x5, x11, x4, lsl #7
    ldr     x5, [x5, #Validator_effective_balance]
    BASE_REWARD x5, x5, x12
    IN_SORTED x4, x27, x28
    b.ne    3f
    mov     x6, x5                          /* in leak: the full base reward */
    cbnz    x13, 2f
    umulh   x6, x5, x17                     /* else base_reward * (attesting_balance // increment) // (total_balance // increment) */
    cbnz    x6, 8f
    mul     x6, x5, x17
    udiv    x6, x6, x14
2:  ldr     x7, [x2, x4, lsl #3]
    adds    x7, x7, x6
    b.cs    8f
    str     x7, [x2, x4, lsl #3]
    b       1b
3:  ldr     x7, [x3, x4, lsl #3]            /* not attesting: penalties[index] += base_reward */
    adds    x7, x7, x5
    b.cs    8f
    str     x7, [x3, x4, lsl #3]
    b       1b
5:  mov     x0, #LANTERN_OK
7:  LEAVE 48
8:  mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END get_attestation_component_deltas

/*
 * get_source_deltas, get_target_deltas, get_head_deltas: the component deltas of the matching
 * attestations of the previous epoch. x19 state, x20 scratch, x21 rewards, x22 penalties,
 * x23 refs, x24 scratch size without the refs. Locals: L previous epoch.
 * Scratch: the refs at the end, then get_attestation_component_deltas's S(7).
 */
.macro MATCHING_DELTAS matching
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH_B x20, x19, 7, PENDING_REFS_BYTES, 9f
    TAKE_REFS x23, x20, x24
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_previous_epoch
    mov     x0, x19
    add     x1, sp, #L
    mov     x2, x23
    bl      \matching
    cbnz    x0, 7f
    str     x24, [x20]
    mov     x0, x19
    mov     x1, x23
    mov     x2, x20
    mov     x3, x21
    mov     x4, x22
    bl      lantern_get_attestation_component_deltas
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
.endm

SPEC_FUNCTION get_source_deltas
    MATCHING_DELTAS lantern_get_matching_source_attestations
SPEC_END get_source_deltas

SPEC_FUNCTION get_target_deltas
    MATCHING_DELTAS lantern_get_matching_target_attestations
SPEC_END get_target_deltas

SPEC_FUNCTION get_head_deltas
    MATCHING_DELTAS lantern_get_matching_head_attestations
SPEC_END get_head_deltas

/*
 * x19 state, x20 scratch, x21 rewards, x22 penalties, x23 refs, x24 scratch size without the refs,
 * x25 n, x26 unslashed, x27 the earliest inclusion delay of each validator, x28 its proposer.
 * Locals: L previous epoch, L+8 total active balance, L+16 its square root, L+24 attesting list,
 * L+32 cursor, L+40 end, L+48 the attestation's ref.
 * Scratch: the refs at the end, then list 0 unslashed, 1 delays, 2 proposers, 3 attesting, then S(5).
 */
SPEC_FUNCTION get_inclusion_delay_deltas
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH_B x20, x19, 9, PENDING_REFS_BYTES, 9f
    LDQ     x25, x19, BeaconState_validators + 8
    mov     x0, x21
    mov     x1, x25
    bl      lantern_zero_deltas
    mov     x0, x22
    mov     x1, x25
    bl      lantern_zero_deltas
    TAKE_REFS x23, x20, x24
    SCRATCH_LIST x26, x20, x24, 0, x25
    SCRATCH_LIST x27, x20, x24, 1, x25
    SCRATCH_LIST x28, x20, x24, 2, x25
    SCRATCH_LIST x9, x20, x24, 3, x25
    str     x9, [sp, #(L + 24)]
    SCRATCH_GIVE x20, x24, 4, x25
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_previous_epoch
    mov     x0, x19                         /* matching_source_attestations */
    add     x1, sp, #L
    mov     x2, x23
    bl      lantern_get_matching_source_attestations
    cbnz    x0, 7f
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #(L + 8)
    bl      lantern_get_total_active_balance
    cbnz    x0, 7f
    add     x0, sp, #(L + 8)
    add     x1, sp, #(L + 16)
    bl      lantern_integer_squareroot
    SCRATCH_GIVE x20, x24, 4, x25
    mov     x0, x19
    mov     x1, x23
    mov     x2, x20
    mov     x3, x26
    bl      lantern_get_unslashed_attesting_indices
    cbnz    x0, 7f
    add     x9, x27, #LIST_FIXED            /* the earliest attestation of each validator: none yet */
    mov     x10, x25
    mov     x11, #-1
0:  cbz     x10, 1f
    str     x11, [x9], #8
    sub     x10, x10, #1
    b       0b
1:  add     x9, x23, #LIST_FIXED
    ldr     x10, [x23, #LIST_COUNT]
    add     x10, x9, x10, lsl #3
    stp     x9, x10, [sp, #(L + 32)]
2:  ldp     x9, x10, [sp, #(L + 32)]        /* in list order, so the first of the smallest delays wins, as min() does */
    cmp     x9, x10
    b.hs    4f
    ldr     x11, [x9], #8
    str     x9, [sp, #(L + 32)]
    str     x11, [sp, #(L + 48)]
    SCRATCH_GIVE x20, x24, 4, x25
    mov     x0, x19
    add     x1, x19, x11
    mov     x3, x20
    ldr     x4, [sp, #(L + 24)]
    mov     x2, xzr
    bl      lantern_get_attesting_indices
    cbnz    x0, 7f
    ldr     x11, [sp, #(L + 48)]
    add     x11, x19, x11
    ldr     x12, [x11, #PendingAttestation_inclusion_delay]
    ldr     x13, [x11, #PendingAttestation_proposer_index]
    ldr     x9, [sp, #(L + 24)]
    ldr     x10, [x9, #LIST_COUNT]
    add     x9, x9, #LIST_FIXED
    add     x14, x27, #LIST_FIXED
    add     x15, x28, #LIST_FIXED
3:  cbz     x10, 2b
    ldr     x16, [x9], #8
    ldr     x17, [x14, x16, lsl #3]
    cmp     x12, x17
    b.hs    31f
    str     x12, [x14, x16, lsl #3]
    str     x13, [x15, x16, lsl #3]
31: sub     x10, x10, #1
    b       3b
4:  add     x9, x26, #LIST_FIXED            /* for index in get_unslashed_attesting_indices(state, matching_source_attestations) */
    ldr     x10, [x26, #LIST_COUNT]
    add     x10, x9, x10, lsl #3
    PART    x11, x12, x19, BeaconState_validators
    ldr     x12, [sp, #(L + 16)]
    add     x2, x21, #LIST_FIXED
    add     x3, x27, #LIST_FIXED
    add     x4, x28, #LIST_FIXED
5:  cmp     x9, x10
    b.hs    6f
    ldr     x5, [x9], #8
    add     x6, x11, x5, lsl #7
    ldr     x6, [x6, #Validator_effective_balance]
    BASE_REWARD x6, x6, x12
    mov     x7, #PROPOSER_REWARD_QUOTIENT
    udiv    x7, x6, x7                      /* get_proposer_reward(state, index) */
    ldr     x13, [x4, x5, lsl #3]           /* rewards[attestation.proposer_index] += proposer_reward */
    ldr     x14, [x2, x13, lsl #3]
    adds    x14, x14, x7
    b.cs    8f
    str     x14, [x2, x13, lsl #3]
    sub     x6, x6, x7                      /* max_attester_reward // attestation.inclusion_delay */
    ldr     x13, [x3, x5, lsl #3]
    cbz     x13, 8f
    udiv    x6, x6, x13
    ldr     x14, [x2, x5, lsl #3]
    adds    x14, x14, x6
    b.cs    8f
    str     x14, [x2, x5, lsl #3]
    b       5b
6:  mov     x0, #LANTERN_OK
7:  LEAVE 64
8:  mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 64
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END get_inclusion_delay_deltas

/*
 * Phase0's version. x19 state, x20 scratch, x21 rewards, x22 penalties, x23 refs, then the cursor
 * over unslashed, x24 scratch size without the refs, then its end, x25 n, x26 unslashed, x27 eligible.
 * Locals: L previous epoch, L+8 total active balance, L+16 its square root, L+24 finality delay,
 * L+32 in leak.
 * Scratch: the refs at the end, then list 0 unslashed, 1 eligible, then S(5).
 */
SPEC_FUNCTION get_inactivity_penalty_deltas
    ENTER 48
    mov     x19, x0
    mov     x20, x2
    mov     x21, x3
    mov     x22, x4
    NEED_SCRATCH_B x20, x19, 7, PENDING_REFS_BYTES, 9f
    LDQ     x25, x19, BeaconState_validators + 8
    mov     x0, x21
    mov     x1, x25
    bl      lantern_zero_deltas
    mov     x0, x22
    mov     x1, x25
    bl      lantern_zero_deltas
    mov     x0, x19
    add     x1, sp, #(L + 32)
    bl      lantern_is_in_inactivity_leak
    ldr     x9, [sp, #(L + 32)]
    cbz     x9, 6f
    TAKE_REFS x23, x20, x24
    SCRATCH_LIST x26, x20, x24, 0, x25
    SCRATCH_LIST x27, x20, x24, 1, x25
    SCRATCH_GIVE x20, x24, 2, x25
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_previous_epoch
    mov     x0, x19                         /* matching_target_attestations */
    add     x1, sp, #L
    mov     x2, x23
    bl      lantern_get_matching_target_attestations
    cbnz    x0, 7f
    mov     x0, x19
    mov     x1, x23
    mov     x2, x20
    mov     x3, x26
    bl      lantern_get_unslashed_attesting_indices
    cbnz    x0, 7f
    SCRATCH_GIVE x20, x24, 2, x25
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #(L + 8)
    bl      lantern_get_total_active_balance
    cbnz    x0, 7f
    add     x0, sp, #(L + 8)
    add     x1, sp, #(L + 16)
    bl      lantern_integer_squareroot
    mov     x0, x19
    mov     x1, x27
    bl      lantern_get_eligible_validator_indices
    cbnz    x0, 7f
    mov     x0, x19
    add     x1, sp, #(L + 24)
    bl      lantern_get_finality_delay
    add     x23, x26, #LIST_FIXED           /* the cursor over matching_target_attesting_indices */
    ldr     x9, [x26, #LIST_COUNT]
    add     x24, x23, x9, lsl #3
    add     x9, x27, #LIST_FIXED            /* for index in get_eligible_validator_indices(state) */
    ldr     x10, [x27, #LIST_COUNT]
    add     x10, x9, x10, lsl #3
    PART    x11, x12, x19, BeaconState_validators
    ldr     x12, [sp, #(L + 16)]
    ldr     x13, [sp, #(L + 24)]
    MOVQ    x15, FORK_INACTIVITY_PENALTY_QUOTIENT
    add     x3, x22, #LIST_FIXED
1:  cmp     x9, x10
    b.hs    6f
    ldr     x4, [x9], #8
    add     x5, x11, x4, lsl #7
    ldr     x5, [x5, #Validator_effective_balance]
    BASE_REWARD x6, x5, x12
    mov     x7, #PROPOSER_REWARD_QUOTIENT
    udiv    x7, x6, x7
    lsl     x6, x6, #2                      /* BASE_REWARDS_PER_EPOCH * base_reward - get_proposer_reward(state, index) */
    sub     x6, x6, x7
    ldr     x7, [x3, x4, lsl #3]
    adds    x7, x7, x6
    b.cs    8f
    IN_SORTED x4, x23, x24
    b.eq    2f
    umulh   x6, x5, x13                     /* not a target attester: effective_balance * finality_delay // INACTIVITY_PENALTY_QUOTIENT */
    cbnz    x6, 8f
    mul     x6, x5, x13
    udiv    x6, x6, x15
    adds    x7, x7, x6
    b.cs    8f
2:  str     x7, [x3, x4, lsl #3]
    b       1b
6:  mov     x0, #LANTERN_OK
7:  LEAVE 48
8:  mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END get_inactivity_penalty_deltas

/* L0: add the n entries of list x1 to those of list x0. x0 = LANTERN_OK, or LANTERN_INVALID_OVERFLOW. A leaf. */
LOCAL_FUNCTION lantern_add_deltas
    UNWIND_END_PROLOGUE
    add     x0, x0, #LIST_FIXED
    add     x1, x1, #LIST_FIXED
1:  cbz     x2, 2f
    ldr     x9, [x0]
    ldr     x10, [x1], #8
    adds    x9, x9, x10
    b.cs    3f
    str     x9, [x0], #8
    sub     x2, x2, #1
    b       1b
2:  mov     x0, #LANTERN_OK
    ret
3:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_add_deltas

/* Add the component's rewards and penalties to the totals. */
.macro ADD_BOTH
    mov     x0, x21
    mov     x1, x25
    mov     x2, x24
    bl      lantern_add_deltas
    cbnz    x0, 7f
    mov     x0, x22
    mov     x1, x26
    mov     x2, x24
    bl      lantern_add_deltas
    cbnz    x0, 7f
.endm

/* One component: x0 = fn(state, scratch, component rewards, component penalties). */
.macro COMPONENT fn
    str     x23, [x20]
    mov     x0, x19
    mov     x1, x20
    mov     x2, x25
    mov     x3, x26
    bl      \fn
    cbnz    x0, 7f
.endm

/*
 * x19 state, x20 scratch, x21 rewards, x22 penalties, x23 the scratch size the components get,
 * x24 n, x25 component rewards, x26 component penalties, x27 config.
 * Scratch: list 0 component rewards, list 1 component penalties, then the components' S(9) + refs.
 */
SPEC_FUNCTION get_attestation_deltas
    ENTER 16
    mov     x19, x0
    mov     x27, x1
    mov     x20, x2
    mov     x21, x3
    mov     x22, x4
    NEED_SCRATCH_B x20, x19, 11, PENDING_REFS_BYTES, 9f
    LDQ     x24, x19, BeaconState_validators + 8
    mov     x0, x21
    mov     x1, x24
    bl      lantern_zero_deltas
    mov     x0, x22
    mov     x1, x24
    bl      lantern_zero_deltas
    ldr     x23, [x20]
    SCRATCH_LIST x25, x20, x23, 0, x24
    SCRATCH_LIST x26, x20, x23, 1, x24
    SCRATCH_GIVE x20, x23, 2, x24
    ldr     x23, [x20]
    COMPONENT lantern_get_source_deltas
    ADD_BOTH
    COMPONENT lantern_get_target_deltas
    ADD_BOTH
    COMPONENT lantern_get_head_deltas
    ADD_BOTH
    COMPONENT lantern_get_inclusion_delay_deltas
    mov     x0, x21                         /* inclusion delay: rewards only */
    mov     x1, x25
    mov     x2, x24
    bl      lantern_add_deltas
    cbnz    x0, 7f
    str     x23, [x20]                      /* inactivity: penalties only */
    mov     x0, x19
    mov     x1, x27
    mov     x2, x20
    mov     x3, x25
    mov     x4, x26
    bl      lantern_get_inactivity_penalty_deltas
    cbnz    x0, 7f
    mov     x0, x22
    mov     x1, x26
    mov     x2, x24
    bl      lantern_add_deltas
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_attestation_deltas

/*
 * x19 state, x20 config, x21 scratch, x22 result, x23 n, x24 rewards, x25 penalties, x26 index,
 * x27 scratch size. Locals: L epoch, L+8 index.
 * Scratch: list 0 rewards, list 1 penalties, then get_attestation_deltas's S(11) + refs.
 */
SPEC_FUNCTION process_rewards_and_penalties
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH_B x21, x19, 13, PENDING_REFS_BYTES, 9f
    str     xzr, [x22]
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #L]
    cmp     x9, #GENESIS_EPOCH
    b.eq    6f
    LDQ     x23, x19, BeaconState_validators + 8
    ldr     x27, [x21]
    SCRATCH_LIST x24, x21, x27, 0, x23
    SCRATCH_LIST x25, x21, x27, 1, x23
    SCRATCH_GIVE x21, x27, 2, x23
    mov     x0, x19                         /* rewards, penalties = get_attestation_deltas(state) */
    mov     x1, x20
    mov     x2, x21
    mov     x3, x24
    mov     x4, x25
    bl      lantern_get_attestation_deltas
    CHECK_STATUS x22, 7f, 6f
    mov     x26, #0
1:  cmp     x26, x23
    b.hs    6f
    str     x26, [sp, #(L + 8)]
    mov     x0, x19
    add     x1, sp, #(L + 8)
    add     x2, x24, #LIST_FIXED
    add     x2, x2, x26, lsl #3
    bl      lantern_increase_balance
    mov     x0, x19
    add     x1, sp, #(L + 8)
    add     x2, x25, #LIST_FIXED
    add     x2, x2, x26, lsl #3
    bl      lantern_decrease_balance
    add     x26, x26, #1
    b       1b
6:  mov     x0, #LANTERN_OK
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END process_rewards_and_penalties

/* ---------------------------------------------------------------- Justification and finalization */

/*
 * x19 state, x20 config, x21 scratch, x22 result, x23 refs, x24 scratch size without the refs.
 * Locals: L current epoch, L+8 previous epoch, L+16 total active balance, L+24 previous target
 * balance, L+32 current target balance.
 * Scratch: the refs at the end, then get_attesting_balance's S(6).
 */
SPEC_FUNCTION process_justification_and_finalization
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH_B x21, x19, 6, PENDING_REFS_BYTES, 9f
    str     xzr, [x22]
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #L]
    cmp     x9, #(GENESIS_EPOCH + 1)
    b.ls    6f
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_previous_epoch
    TAKE_REFS x23, x21, x24
    mov     x0, x19
    mov     x1, x21
    add     x2, sp, #(L + 16)
    bl      lantern_get_total_active_balance
    cbnz    x0, 7f
    mov     x0, x19                         /* previous_attestations = get_matching_target_attestations(state, previous_epoch) */
    add     x1, sp, #(L + 8)
    mov     x2, x23
    bl      lantern_get_matching_target_attestations
    CHECK_STATUS x22, 7f, 6f
    str     x24, [x21]
    mov     x0, x19
    mov     x1, x23
    mov     x2, x21
    add     x3, sp, #(L + 24)
    bl      lantern_get_attesting_balance
    CHECK_STATUS x22, 7f, 6f
    mov     x0, x19                         /* current_attestations */
    add     x1, sp, #L
    mov     x2, x23
    bl      lantern_get_matching_target_attestations
    CHECK_STATUS x22, 7f, 6f
    str     x24, [x21]
    mov     x0, x19
    mov     x1, x23
    mov     x2, x21
    add     x3, sp, #(L + 32)
    bl      lantern_get_attesting_balance
    CHECK_STATUS x22, 7f, 6f
    mov     x0, x19
    add     x1, sp, #(L + 16)
    add     x2, sp, #(L + 24)
    add     x3, sp, #(L + 32)
    mov     x4, x22
    bl      lantern_weigh_justification_and_finalization
7:  LEAVE 48
6:  mov     x0, #LANTERN_OK
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END process_justification_and_finalization

/* ---------------------------------------------------------------- Record updates */

/*
 * L0: x9 = the bytes of the entries of state x0's PendingAttestation list at PartRef offset x1,
 * x10 = their start. Uses x11, x12.
 */
.macro PENDING_BYTES
    ldr     x10, [x0, x1]
    add     x11, x1, #8
    ldr     x11, [x0, x11]
    add     x10, x0, x10
    mov     x9, #0
91: cbz     x11, 92f
    ldr     x12, [x10, x9]
    add     x9, x9, x12
    sub     x11, x11, #1
    b       91b
92:
.endm

/* L0: x0 = LANTERN_OK when state x0's previous_epoch_attestations can take the current ones, else LANTERN_BUFFER_TOO_SMALL. A leaf. */
LOCAL_FUNCTION lantern_record_room
    UNWIND_END_PROLOGUE
    MOVQ    x1, BeaconState_current_epoch_attestations
    PENDING_BYTES
    LDQ     x13, x0, BeaconState_current_epoch_attestations
    LDQ     x14, x0, BeaconState_previous_epoch_attestations
    sub     x13, x13, x14
    cmp     x9, x13
    b.hi    9f
    mov     x0, #LANTERN_OK
    ret
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    ret
END_FUNCTION lantern_record_room

/* x19 state, x20 result. */
SPEC_FUNCTION process_participation_record_updates
    ENTER 0
    mov     x19, x0
    mov     x20, x3
    bl      lantern_record_room                     /* previous_epoch_attestations = current_epoch_attestations */
    cbnz    x0, 7f
    mov     x0, x19
    MOVQ    x1, BeaconState_current_epoch_attestations
    PENDING_BYTES
    LDQ     x0, x19, BeaconState_previous_epoch_attestations
    add     x0, x19, x0
    mov     x1, x10
    mov     x2, x9
    bl      lantern_copy                    /* the previous list starts before the current one */
    LDQ     x9, x19, BeaconState_current_epoch_attestations + 8
    STQ     x9, x19, BeaconState_previous_epoch_attestations + 8
    STQ     xzr, x19, BeaconState_current_epoch_attestations + 8   /* current_epoch_attestations = [] */
    str     xzr, [x20]
    mov     x0, #LANTERN_OK
7:  LEAVE 0
SPEC_END process_participation_record_updates
