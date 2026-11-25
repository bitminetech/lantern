/*
 * Beacon chain helpers, ARM64. Requirements: docs/reference/helpers.md.
 * v1: each function follows its spec steps and calls the spec functions it names.
 */

/* ---------------------------------------------------------------- Math */

SPEC_LEAF integer_squareroot
    ldr     x2, [x0]                        /* n */
    cmn     x2, #1
    b.ne    1f
    mov     x3, #UINT64_MAX_SQRT            /* n == UINT64_MAX */
    str     x3, [x1]
    RETURN_OK
1:  mov     x3, x2                          /* x = n */
    add     x4, x2, #1
    lsr     x4, x4, #1                      /* y = (x + 1) // 2 */
2:  cmp     x4, x3
    b.hs    3f                              /* while y < x */
    mov     x3, x4                          /* x = y; x >= 1 here */
    udiv    x5, x2, x3
    add     x5, x3, x5
    lsr     x4, x5, #1                      /* y = (x + n // x) // 2 */
    b       2b
3:  str     x3, [x1]
    RETURN_OK
SPEC_END integer_squareroot

SPEC_LEAF saturating_sub
    ldr     x3, [x0]
    ldr     x4, [x1]
    subs    x5, x3, x4
    csel    x5, x5, xzr, hi                 /* a > b ? a - b : 0 */
    str     x5, [x2]
    RETURN_OK
SPEC_END saturating_sub

/* ---------------------------------------------------------------- Predicates */

SPEC_LEAF is_active_validator
    ldr     x3, [x1]                        /* epoch */
    ldr     x4, [x0, #Validator_activation_epoch]
    ldr     x5, [x0, #Validator_exit_epoch]
    cmp     x4, x3                          /* activation_epoch <= epoch */
    ccmp    x3, x5, #2, ls                  /* and epoch < exit_epoch; else C set, so lo fails */
    cset    x6, lo
    str     x6, [x2]
    RETURN_OK
SPEC_END is_active_validator

SPEC_LEAF is_eligible_for_activation_queue
    ldr     x2, [x0, #Validator_activation_eligibility_epoch]
    ldr     x3, [x0, #Validator_effective_balance]
.if FORK >= FORK_ELECTRA
    MOVQ    x4, MIN_ACTIVATION_BALANCE
    cmn     x2, #1                          /* activation_eligibility_epoch == FAR_FUTURE_EPOCH */
    ccmp    x3, x4, #0, eq                  /* and effective_balance >= MIN_ACTIVATION_BALANCE */
    cset    x5, hs
.else
    MOVQ    x4, MAX_EFFECTIVE_BALANCE
    cmn     x2, #1                          /* activation_eligibility_epoch == FAR_FUTURE_EPOCH */
    ccmp    x3, x4, #0, eq                  /* and effective_balance == MAX_EFFECTIVE_BALANCE */
    cset    x5, eq
.endif
    str     x5, [x1]
    RETURN_OK
SPEC_END is_eligible_for_activation_queue

SPEC_LEAF is_eligible_for_activation
    LDQ     x3, x0, BeaconState_finalized_checkpoint + Checkpoint_epoch
    ldr     x4, [x1, #Validator_activation_eligibility_epoch]
    ldr     x5, [x1, #Validator_activation_epoch]
    cmp     x4, x3                          /* activation_eligibility_epoch <= finalized epoch */
    ccmn    x5, #1, #0, ls                  /* and activation_epoch == FAR_FUTURE_EPOCH */
    cset    x6, eq
    str     x6, [x2]
    RETURN_OK
SPEC_END is_eligible_for_activation

SPEC_LEAF is_slashable_validator
    ldr     x3, [x1]                        /* epoch */
    ldrb    w4, [x0, #Validator_slashed]
    ldr     x5, [x0, #Validator_activation_epoch]
    ldr     x6, [x0, #Validator_withdrawable_epoch]
    cmp     x5, x3                          /* activation_epoch <= epoch */
    ccmp    x3, x6, #2, ls                  /* and epoch < withdrawable_epoch */
    cset    x7, lo
    cmp     w4, #0                          /* and not slashed */
    csel    x7, x7, xzr, eq
    str     x7, [x2]
    RETURN_OK
SPEC_END is_slashable_validator

.if FORK >= FORK_ELECTRA
SPEC_LEAF is_compounding_withdrawal_credential
    ldrb    w2, [x0]
    cmp     w2, #COMPOUNDING_WITHDRAWAL_PREFIX
    cset    x3, eq
    str     x3, [x1]
    RETURN_OK
SPEC_END is_compounding_withdrawal_credential
.endif

.if FORK >= FORK_ELECTRA
SPEC_FUNCTION has_compounding_withdrawal_credential
    FRAME 0
    add     x0, x0, #Validator_withdrawal_credentials
    bl      lantern_is_compounding_withdrawal_credential
    UNFRAME 0
SPEC_END has_compounding_withdrawal_credential
.endif

.if FORK >= FORK_ELECTRA
SPEC_FUNCTION get_max_effective_balance
    FRAME 16
    str     x1, [sp, #16]                   /* out */
    add     x1, sp, #24
    bl      lantern_has_compounding_withdrawal_credential
    ldr     x2, [sp, #24]
    MOVQ    x3, MAX_EFFECTIVE_BALANCE_ELECTRA
    MOVQ    x4, MIN_ACTIVATION_BALANCE
    cmp     x2, #0
    csel    x3, x3, x4, ne
    ldr     x1, [sp, #16]
    str     x3, [x1]
    mov     x0, #LANTERN_OK
    UNFRAME 16
SPEC_END get_max_effective_balance
.endif

/* ---------------------------------------------------------------- Misc */

SPEC_LEAF compute_epoch_at_slot
    ldr     x2, [x0]
    lsr     x2, x2, #LOG2_SLOTS_PER_EPOCH
    str     x2, [x1]
    RETURN_OK
SPEC_END compute_epoch_at_slot

SPEC_LEAF compute_start_slot_at_epoch
    ldr     x2, [x0]
    lsr     x3, x2, #(64 - LOG2_SLOTS_PER_EPOCH)
    cbnz    x3, 1f                          /* epoch * SLOTS_PER_EPOCH leaves the Uint64 range */
    lsl     x2, x2, #LOG2_SLOTS_PER_EPOCH
    str     x2, [x1]
    RETURN_OK
1:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_start_slot_at_epoch

SPEC_LEAF compute_activation_exit_epoch
    ldr     x2, [x0]
    adds    x2, x2, #(1 + MAX_SEED_LOOKAHEAD)
    b.cs    1f
    str     x2, [x1]
    RETURN_OK
1:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_activation_exit_epoch

/*
 * x19 branch, x20 depth, x21 index, x22 root, x23 out, x24 i.
 * Locals: L value (32), L+32 the two halves (64).
 */
SPEC_FUNCTION is_valid_merkle_branch
    ENTER 96
    mov     x19, x1
    ldr     x20, [x2]
    ldr     x21, [x3]
    mov     x22, x4
    mov     x23, x5
    add     x9, sp, #L                      /* value = leaf */
    COPY32  x9, x0
    mov     x24, #0
1:  cmp     x24, x20
    b.hs    3f
    add     x9, x19, x24, lsl #5            /* branch[i] */
    lsr     x10, x21, x24                   /* index // (2**i) % 2; 0 once i reaches 64 */
    cmp     x24, #64
    csel    x10, x10, xzr, lo
    add     x11, sp, #(L + 32)
    add     x12, sp, #L
    tbz     x10, #0, 2f
    COPY32  x11, x9                         /* hash(branch[i] + value) */
    add     x11, x11, #32
    COPY32  x11, x12
    b       21f
2:  COPY32  x11, x12                        /* hash(value + branch[i]) */
    add     x11, x11, #32
    COPY32  x11, x9
21: add     x0, sp, #(L + 32)
    mov     x1, #64
    add     x2, sp, #L
    bl      lantern_sha256_short
    add     x24, x24, #1
    b       1b
3:  add     x14, sp, #L                     /* value == root */
    mov     x9, #0
    NE32    x14, x22, 4f
    mov     x9, #1
4:  str     x9, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 96
SPEC_END is_valid_merkle_branch

/* ---------------------------------------------------------------- Accessors */

SPEC_FUNCTION get_current_epoch
    FRAME 0
    ADDQ    x0, x0, BeaconState_slot
    bl      lantern_compute_epoch_at_slot
    UNFRAME 0
SPEC_END get_current_epoch

SPEC_FUNCTION get_previous_epoch
    FRAME 32
    str     x1, [sp, #16]                   /* out */
    add     x1, sp, #24
    bl      lantern_get_current_epoch
    mov     x9, #1
    str     x9, [sp, #32]
    add     x0, sp, #24                     /* saturating_sub(current, 1) */
    add     x1, sp, #32
    ldr     x2, [sp, #16]
    bl      lantern_saturating_sub
    UNFRAME 32
SPEC_END get_previous_epoch

SPEC_LEAF get_block_root_at_slot
    ldr     x4, [x1]                        /* slot */
    LDQ     x5, x0, BeaconState_slot
    cmp     x4, x5                          /* slot < state.slot */
    b.hs    1f
    sub     x6, x5, x4                      /* state.slot <= slot + SLOTS_PER_HISTORICAL_ROOT */
    cmp     x6, #SLOTS_PER_HISTORICAL_ROOT
    b.hi    1f
    and     x4, x4, #(SLOTS_PER_HISTORICAL_ROOT - 1)
    ADDQ    x5, x0, BeaconState_block_roots
    add     x5, x5, x4, lsl #5
    COPY32  x2, x5
    RETURN_OK
1:  mov     x0, #LANTERN_INVALID_BLOCK_ROOT_SLOT
    ret
SPEC_END get_block_root_at_slot

SPEC_FUNCTION get_block_root
    FRAME 32
    stp     x0, x2, [sp, #16]               /* state, out */
    mov     x0, x1
    add     x1, sp, #32
    bl      lantern_compute_start_slot_at_epoch
    cbnz    x0, 1f
    ldp     x0, x2, [sp, #16]
    add     x1, sp, #32
    bl      lantern_get_block_root_at_slot
1:  UNFRAME 32
SPEC_END get_block_root

SPEC_LEAF get_randao_mix
    ldr     x3, [x1]
    and     x3, x3, #(EPOCHS_PER_HISTORICAL_VECTOR - 1)
    ADDQ    x4, x0, BeaconState_randao_mixes
    add     x4, x4, x3, lsl #5
    COPY32  x2, x4
    RETURN_OK
SPEC_END get_randao_mix

/*
 * x19 state, x20 epoch, x21 out, x22 validator, x23 validators left,
 * x24 index, x25 out entries; locals: the is_active_validator result.
 */
SPEC_FUNCTION get_active_validator_indices
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    PART    x22, x23, x19, BeaconState_validators
    ldr     x9, [x21, #LIST_SIZE]           /* room for every validator */
    lsl     x10, x23, #3
    add     x10, x10, #LIST_FIXED
    cmp     x9, x10
    b.lo    9f
    mov     x9, #LIST_FIXED
    str     x9, [x21, #LIST_OFFSET]
    add     x25, x21, #LIST_FIXED
    mov     x24, #0
1:  cbz     x23, 3f
    mov     x0, x22
    mov     x1, x20
    add     x2, sp, #L
    bl      lantern_is_active_validator
    ldr     x9, [sp, #L]
    cbz     x9, 2f
    str     x24, [x25], #8
2:  add     x22, x22, #Validator__mem
    add     x24, x24, #1
    sub     x23, x23, #1
    b       1b
3:  add     x9, x21, #LIST_FIXED
    sub     x9, x25, x9
    lsr     x9, x9, #3
    str     x9, [x21, #LIST_COUNT]
    mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_active_validator_indices

SPEC_LEAF get_total_balance
    PART    x3, x4, x0, BeaconState_validators
    ldr     x5, [x1, #LIST_COUNT]
    add     x6, x1, #LIST_FIXED
    mov     x7, #0                          /* sum */
1:  cbz     x5, 2f
    ldr     x8, [x6], #8
    add     x8, x3, x8, lsl #7              /* Validator__mem is 128 */
    ldr     x8, [x8, #Validator_effective_balance]
    add     x7, x7, x8
    sub     x5, x5, #1
    b       1b
2:  MOVQ    x8, EFFECTIVE_BALANCE_INCREMENT
    cmp     x7, x8
    csel    x7, x7, x8, hi                  /* max(EFFECTIVE_BALANCE_INCREMENT, sum) */
    str     x7, [x2]
    RETURN_OK
SPEC_END get_total_balance

/*
 * A candidate of ARCHITECTURE.md section 9: get_active_validator_indices and get_total_balance
 * inlined in one pass over the validators, after v1's check that the index list would fit
 * in the scratch after its size field.
 * Locals: sp+16 out, sp+24 state, sp+32 scratch, sp+40 the epoch.
 */
SPEC_FUNCTION get_total_active_balance
    FRAME 32
    str     x2, [sp, #16]
    stp     x0, x1, [sp, #24]
    add     x1, sp, #40
    bl      lantern_get_current_epoch
    ldp     x0, x1, [sp, #24]
    ldr     x9, [x1]                        /* room for every validator in the scratch after its size */
    sub     x9, x9, #8
    PART    x3, x4, x0, BeaconState_validators
    lsl     x10, x4, #3
    add     x10, x10, #LIST_FIXED
    cmp     x9, x10
    b.lo    9f
    ldr     x8, [sp, #40]
    mov     x7, #0                          /* sum */
    cbz     x4, 2f
1:  ldr     x9, [x3, #Validator_activation_epoch]
    ldr     x10, [x3, #Validator_exit_epoch]
    ldr     x11, [x3, #Validator_effective_balance]
    cmp     x9, x8                          /* is_active_validator(validator, epoch) */
    ccmp    x8, x10, #2, ls
    csel    x11, x11, xzr, lo
    add     x7, x7, x11
    add     x3, x3, #Validator__mem
    subs    x4, x4, #1
    b.ne    1b
2:  MOVQ    x8, EFFECTIVE_BALANCE_INCREMENT
    cmp     x7, x8
    csel    x7, x7, x8, hi                  /* max(EFFECTIVE_BALANCE_INCREMENT, sum) */
    ldr     x2, [sp, #16]
    str     x7, [x2]
    mov     x0, #LANTERN_OK
    UNFRAME 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 32
SPEC_END get_total_active_balance

/* ---------------------------------------------------------------- Mutators */

SPEC_LEAF increase_balance
    ldr     x3, [x1]                        /* index */
    ldr     x4, [x2]                        /* delta */
    PART    x5, x6, x0, BeaconState_balances
    add     x5, x5, x3, lsl #3
    ldr     x6, [x5]
    add     x6, x6, x4
    str     x6, [x5]
    RETURN_OK
SPEC_END increase_balance

SPEC_FUNCTION decrease_balance
    FRAME 0
    ldr     x3, [x1]                        /* index */
    PART    x4, x5, x0, BeaconState_balances
    add     x0, x4, x3, lsl #3              /* balances[index] = saturating_sub(balances[index], delta) */
    mov     x1, x2
    mov     x2, x0
    bl      lantern_saturating_sub
    UNFRAME 0
SPEC_END decrease_balance

/* ---------------------------------------------------------------- Participation flags and rewards */

.if FORK >= FORK_ALTAIR
SPEC_LEAF has_flag
    ldrb    w3, [x0]
    ldr     x4, [x1]
    lsr     w3, w3, w4
    and     x3, x3, #1
    str     x3, [x2]
    RETURN_OK
SPEC_END has_flag
.endif

.if FORK >= FORK_ALTAIR
SPEC_LEAF add_flag
    ldrb    w3, [x0]
    ldr     x4, [x1]
    mov     w5, #1
    lsl     w5, w5, w4
    orr     w3, w3, w5
    strb    w3, [x2]
    RETURN_OK
SPEC_END add_flag
.endif

SPEC_FUNCTION get_finality_delay
    FRAME 32
    stp     x0, x1, [sp, #16]
    add     x1, sp, #32
    bl      lantern_get_previous_epoch
    ldp     x0, x1, [sp, #16]
    ldr     x2, [sp, #32]
    LDQ     x3, x0, BeaconState_finalized_checkpoint + Checkpoint_epoch
    sub     x2, x2, x3
    str     x2, [x1]
    mov     x0, #LANTERN_OK
    UNFRAME 32
SPEC_END get_finality_delay

SPEC_FUNCTION is_in_inactivity_leak
    FRAME 16
    str     x1, [sp, #16]
    add     x1, sp, #24
    bl      lantern_get_finality_delay
    ldr     x2, [sp, #24]
    cmp     x2, #MIN_EPOCHS_TO_INACTIVITY_PENALTY
    cset    x2, hi
    ldr     x1, [sp, #16]
    str     x2, [x1]
    mov     x0, #LANTERN_OK
    UNFRAME 16
SPEC_END is_in_inactivity_leak

/*
 * x19 state, x20 out, x21 validator, x22 validators left, x23 index, x24 out entries,
 * x25 previous epoch; locals: previous epoch at L, is_active_validator result at L + 8.
 */
SPEC_FUNCTION get_eligible_validator_indices
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    PART    x21, x22, x19, BeaconState_validators
    ldr     x9, [x20, #LIST_SIZE]
    lsl     x10, x22, #3
    add     x10, x10, #LIST_FIXED
    cmp     x9, x10
    b.lo    9f
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_previous_epoch
    ldr     x25, [sp, #L]
    mov     x9, #LIST_FIXED
    str     x9, [x20, #LIST_OFFSET]
    add     x24, x20, #LIST_FIXED
    mov     x23, #0
1:  cbz     x22, 4f
    mov     x0, x21
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    bl      lantern_is_active_validator
    ldr     x9, [sp, #(L + 8)]
    cbnz    x9, 2f
    ldrb    w9, [x21, #Validator_slashed]   /* or slashed and previous_epoch + 1 < withdrawable_epoch */
    cbz     w9, 3f
    ldr     x10, [x21, #Validator_withdrawable_epoch]
    add     x11, x25, #1
    cmp     x11, x10
    b.hs    3f
2:  str     x23, [x24], #8
3:  add     x21, x21, #Validator__mem
    add     x23, x23, #1
    sub     x22, x22, #1
    b       1b
4:  add     x9, x20, #LIST_FIXED
    sub     x9, x24, x9
    lsr     x9, x9, #3
    str     x9, [x20, #LIST_COUNT]
    mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_eligible_validator_indices

.if FORK >= FORK_ALTAIR
/*
 * x19 state, x20 flag_index, x21 epoch, x22 scratch, x23 out,
 * x25 epoch_participation, x26 active list entries, x27 entries left, x28 out entries.
 * Locals: previous epoch at L, current epoch at L + 8, has_flag result at L + 16.
 */
SPEC_FUNCTION get_unslashed_participating_indices
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    PART    x9, x10, x19, BeaconState_validators
    ldr     x11, [x23, #LIST_SIZE]          /* out and scratch need room for every validator */
    lsl     x12, x10, #3
    add     x12, x12, #LIST_FIXED
    cmp     x11, x12
    b.lo    9f
    ldr     x11, [x22]
    add     x12, x12, #8
    cmp     x11, x12
    b.lo    9f
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_previous_epoch
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_current_epoch
    ldr     x9, [x21]
    ldp     x10, x11, [sp, #L]              /* previous, current */
    cmp     x9, x11                         /* assert epoch in (previous, current) */
    b.eq    1f
    cmp     x9, x10
    b.eq    2f
    mov     x0, #LANTERN_INVALID_PARTICIPATION_EPOCH
    LEAVE 32
1:  PART    x25, x9, x19, BeaconState_current_epoch_participation
    b       3f
2:  PART    x25, x9, x19, BeaconState_previous_epoch_participation
3:  ldr     x9, [x22]                       /* active_validator_indices: the scratch after its size */
    sub     x9, x9, #8
    str     x9, [x22, #8]
    mov     x0, x19
    mov     x1, x21
    add     x2, x22, #8
    bl      lantern_get_active_validator_indices
    cbnz    x0, 8f
    ldr     x27, [x22, #(8 + LIST_COUNT)]
    add     x26, x22, #(8 + LIST_FIXED)
    mov     x9, #LIST_FIXED
    str     x9, [x23, #LIST_OFFSET]
    add     x28, x23, #LIST_FIXED
4:  cbz     x27, 6f
    ldr     x9, [x26], #8                   /* index */
    str     x9, [sp, #(L + 24)]
    add     x0, x25, x9
    mov     x1, x20
    add     x2, sp, #(L + 16)
    bl      lantern_has_flag
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 5f
    ldr     x9, [sp, #(L + 24)]             /* and not state.validators[index].slashed */
    PART    x10, x11, x19, BeaconState_validators
    add     x10, x10, x9, lsl #7
    ldrb    w10, [x10, #Validator_slashed]
    cbnz    w10, 5f
    str     x9, [x28], #8
5:  sub     x27, x27, #1
    b       4b
6:  add     x9, x23, #LIST_FIXED
    sub     x9, x28, x9
    lsr     x9, x9, #3
    str     x9, [x23, #LIST_COUNT]
    mov     x0, #LANTERN_OK
8:  LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END get_unslashed_participating_indices
.endif

.if FORK >= FORK_ALTAIR
SPEC_FUNCTION get_base_reward_per_increment
    FRAME 32
    str     x2, [sp, #16]                   /* out */
    add     x2, sp, #24
    bl      lantern_get_total_active_balance
    cbnz    x0, 1f
    add     x0, sp, #24
    add     x1, sp, #32
    bl      lantern_integer_squareroot
    ldr     x9, [sp, #32]
    MOVQ    x10, EFFECTIVE_BALANCE_INCREMENT * BASE_REWARD_FACTOR
    udiv    x10, x10, x9
    ldr     x11, [sp, #16]
    str     x10, [x11]
    mov     x0, #LANTERN_OK
1:  UNFRAME 32
SPEC_END get_base_reward_per_increment
.endif

.if FORK == FORK_PHASE0
/* Locals: sp+16 state, sp+24 index, sp+32 out, sp+40 total active balance, sp+48 its square root. */
SPEC_FUNCTION get_base_reward
    FRAME 48
    stp     x0, x1, [sp, #16]
    str     x3, [sp, #32]
    mov     x1, x2
    add     x2, sp, #40
    bl      lantern_get_total_active_balance
    cbnz    x0, 1f
    add     x0, sp, #40
    add     x1, sp, #48
    bl      lantern_integer_squareroot
    ldp     x0, x1, [sp, #16]
    ldr     x1, [x1]
    PART    x9, x10, x0, BeaconState_validators
    add     x9, x9, x1, lsl #7
    ldr     x9, [x9, #Validator_effective_balance]
    mov     x10, #BASE_REWARD_FACTOR        /* fits: effective_balance is at most MAX_EFFECTIVE_BALANCE */
    mul     x9, x9, x10
    ldr     x10, [sp, #48]
    udiv    x9, x9, x10                     /* // integer_squareroot(total_balance) */
    lsr     x9, x9, #2                      /* // BASE_REWARDS_PER_EPOCH, which is 4 */
    ldr     x12, [sp, #32]
    str     x9, [x12]
    mov     x0, #LANTERN_OK
1:  UNFRAME 48
SPEC_END get_base_reward
.else
SPEC_FUNCTION get_base_reward
    FRAME 32
    stp     x0, x1, [sp, #16]               /* state, index */
    str     x3, [sp, #32]                   /* out */
    mov     x1, x2
    add     x2, sp, #40
    bl      lantern_get_base_reward_per_increment
    cbnz    x0, 1f
    ldp     x0, x1, [sp, #16]
    ldr     x1, [x1]
    PART    x9, x10, x0, BeaconState_validators
    add     x9, x9, x1, lsl #7
    ldr     x9, [x9, #Validator_effective_balance]
    MOVQ    x10, EFFECTIVE_BALANCE_INCREMENT
    udiv    x9, x9, x10                     /* increments */
    ldr     x11, [sp, #40]
    mul     x9, x9, x11
    ldr     x12, [sp, #32]
    str     x9, [x12]
    mov     x0, #LANTERN_OK
1:  UNFRAME 32
SPEC_END get_base_reward
.endif
