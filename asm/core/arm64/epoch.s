/*
 * Epoch processing, ARM64. Requirements: docs/reference/epoch-processing.md.
 * v1: each function follows its spec steps and calls the spec functions it
 * names. A call whose result the loop cannot change is made once, before the loop.
 */

/* ---------------------------------------------------------------- Justification and finalization */

.if FORK >= FORK_ALTAIR
/*
 * A candidate of ARCHITECTURE.md section 9: get_unslashed_participating_indices,
 * get_total_active_balance and get_total_balance inlined in one pass over the validators.
 * x19 state, x20 config, x21 scratch, x22 result. Locals: L current epoch, L+8 previous
 * epoch, L+16 total active balance, L+24 previous target balance, L+32 current target balance.
 */
SPEC_FUNCTION process_justification_and_finalization
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH x21, x19, 3, 9f
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #L]
    cmp     x9, #(GENESIS_EPOCH + 1)
    b.ls    8f
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_previous_epoch
    PART    x0, x1, x19, BeaconState_validators
    PART    x2, x9, x19, BeaconState_previous_epoch_participation
    PART    x3, x9, x19, BeaconState_current_epoch_participation
    ldp     x8, x7, [sp, #L]                /* current, previous */
    mov     x4, #0                          /* total active balance */
    mov     x5, #0                          /* previous target balance */
    mov     x6, #0                          /* current target balance */
    cbz     x1, 2f
1:  ldr     x9, [x0, #Validator_activation_epoch]
    ldr     x10, [x0, #Validator_exit_epoch]
    ldr     x11, [x0, #Validator_effective_balance]
    ldrb    w12, [x0, #Validator_slashed]
    ldrb    w13, [x2], #1                   /* previous_epoch_participation[index] */
    ldrb    w14, [x3], #1                   /* current_epoch_participation[index] */
    cmp     x9, x8                          /* is_active_validator(validator, current) */
    ccmp    x8, x10, #2, ls
    csel    x15, x11, xzr, lo
    add     x4, x4, x15
    ccmp    w12, #0, #0, lo                 /* and not slashed, with the target flag */
    csel    w14, w14, wzr, eq
    tst     w14, #(1 << TIMELY_TARGET_FLAG_INDEX)
    csel    x15, x11, xzr, ne
    add     x6, x6, x15
    cmp     x9, x7                          /* the same in the previous epoch */
    ccmp    x7, x10, #2, ls
    ccmp    w12, #0, #0, lo
    csel    w13, w13, wzr, eq
    tst     w13, #(1 << TIMELY_TARGET_FLAG_INDEX)
    csel    x15, x11, xzr, ne
    add     x5, x5, x15
    add     x0, x0, #Validator__mem
    subs    x1, x1, #1
    b.ne    1b
2:  MOVQ    x9, EFFECTIVE_BALANCE_INCREMENT /* get_total_balance: max(EFFECTIVE_BALANCE_INCREMENT, sum) */
    cmp     x4, x9
    csel    x4, x4, x9, hi
    cmp     x5, x9
    csel    x5, x5, x9, hi
    cmp     x6, x9
    csel    x6, x6, x9, hi
    stp     x4, x5, [sp, #(L + 16)]
    str     x6, [sp, #(L + 32)]
    mov     x0, x19
    add     x1, sp, #(L + 16)
    add     x2, sp, #(L + 24)
    add     x3, sp, #(L + 32)
    mov     x4, x22
    bl      lantern_weigh_justification_and_finalization
    LEAVE 48
8:  str     xzr, [x22]
    mov     x0, #LANTERN_OK
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END process_justification_and_finalization
.endif

/*
 * x19 state, x20 total, x21 previous target balance, x22 current target balance,
 * x23 result, x24 justification bits, x25 current epoch, x26 previous epoch.
 * Locals: L old previous justified (40), L+48 old current justified (40),
 * L+96 previous epoch, L+104 current epoch, L+112 root (32).
 */
SPEC_FUNCTION weigh_justification_and_finalization
    ENTER 160
    mov     x19, x0
    ldr     x20, [x1]
    ldr     x21, [x2]
    ldr     x22, [x3]
    mov     x23, x4
    mov     x0, x19
    add     x1, sp, #(L + 96)
    bl      lantern_get_previous_epoch
    mov     x0, x19
    add     x1, sp, #(L + 104)
    bl      lantern_get_current_epoch
    ldr     x26, [sp, #(L + 96)]
    ldr     x25, [sp, #(L + 104)]
    /* Keep the old checkpoints; previous_justified_checkpoint = current_justified_checkpoint. */
    ADDQ    x9, x19, BeaconState_previous_justified_checkpoint
    add     x10, sp, #L
    ldp     x11, x12, [x9]
    stp     x11, x12, [x10]
    ldp     x11, x12, [x9, #16]
    stp     x11, x12, [x10, #16]
    ldr     x11, [x9, #32]
    str     x11, [x10, #32]
    ADDQ    x9, x19, BeaconState_current_justified_checkpoint
    add     x10, sp, #(L + 48)
    ldp     x11, x12, [x9]
    stp     x11, x12, [x10]
    ldp     x11, x12, [x9, #16]
    stp     x11, x12, [x10, #16]
    ldr     x11, [x9, #32]
    str     x11, [x10, #32]
    ADDQ    x9, x19, BeaconState_previous_justified_checkpoint
    add     x10, sp, #(L + 48)
    ldp     x11, x12, [x10]
    stp     x11, x12, [x9]
    ldp     x11, x12, [x10, #16]
    stp     x11, x12, [x9, #16]
    ldr     x11, [x10, #32]
    str     x11, [x9, #32]
    /* justification_bits[1:] = justification_bits[:3]; justification_bits[0] = False */
    ADDQ    x9, x19, BeaconState_justification_bits
    ldrb    w24, [x9]
    lsl     w24, w24, #1
    and     w24, w24, #0xf
    mov     x9, #3
    mul     x10, x21, x9                    /* previous_epoch_target_balance * 3 >= total * 2 */
    lsl     x11, x20, #1
    cmp     x10, x11
    b.lo    1f
    mov     x0, x19
    add     x1, sp, #(L + 96)
    add     x2, sp, #(L + 112)
    bl      lantern_get_block_root
    CHECK_STATUS x23, 6f, 6f
    ADDQ    x9, x19, BeaconState_current_justified_checkpoint
    str     x26, [x9, #Checkpoint_epoch]
    add     x9, x9, #Checkpoint_root
    add     x10, sp, #(L + 112)
    COPY32  x9, x10
    orr     w24, w24, #2
1:  mov     x9, #3
    mul     x10, x22, x9                    /* current_epoch_target_balance * 3 >= total * 2 */
    lsl     x11, x20, #1
    cmp     x10, x11
    b.lo    2f
    mov     x0, x19
    add     x1, sp, #(L + 104)
    add     x2, sp, #(L + 112)
    bl      lantern_get_block_root
    CHECK_STATUS x23, 6f, 6f
    ADDQ    x9, x19, BeaconState_current_justified_checkpoint
    str     x25, [x9, #Checkpoint_epoch]
    add     x9, x9, #Checkpoint_root
    add     x10, sp, #(L + 112)
    COPY32  x9, x10
    orr     w24, w24, #1
2:  ADDQ    x9, x19, BeaconState_justification_bits
    strb    w24, [x9]
    /* The four finality rules, in spec order; a later rule overrides an earlier one. */
    mov     x12, #0                         /* the checkpoint to finalize: 0 none */
    ldr     x9, [sp, #L]                    /* old previous justified epoch */
    ldr     x10, [sp, #(L + 48)]            /* old current justified epoch */
    and     w11, w24, #0xe                  /* bits[1:4] and old_previous + 3 == current */
    cmp     w11, #0xe
    b.ne    3f
    add     x13, x9, #3
    cmp     x13, x25
    b.ne    3f
    add     x12, sp, #L
3:  and     w11, w24, #0x6                  /* bits[1:3] and old_previous + 2 == current */
    cmp     w11, #0x6
    b.ne    4f
    add     x13, x9, #2
    cmp     x13, x25
    b.ne    4f
    add     x12, sp, #L
4:  and     w11, w24, #0x7                  /* bits[0:3] and old_current + 2 == current */
    cmp     w11, #0x7
    b.ne    5f
    add     x13, x10, #2
    cmp     x13, x25
    b.ne    5f
    add     x12, sp, #(L + 48)
5:  and     w11, w24, #0x3                  /* bits[0:2] and old_current + 1 == current */
    cmp     w11, #0x3
    b.ne    55f
    add     x13, x10, #1
    cmp     x13, x25
    b.ne    55f
    add     x12, sp, #(L + 48)
55: cbz     x12, 56f
    ADDQ    x9, x19, BeaconState_finalized_checkpoint
    ldp     x10, x11, [x12]
    stp     x10, x11, [x9]
    ldp     x10, x11, [x12, #16]
    stp     x10, x11, [x9, #16]
    ldr     x10, [x12, #32]
    str     x10, [x9, #32]
56: str     xzr, [x23]
6:  mov     x0, #LANTERN_OK
    LEAVE 160
SPEC_END weigh_justification_and_finalization

/* ---------------------------------------------------------------- Inactivity */

.if FORK >= FORK_ALTAIR
/*
 * A candidate of ARCHITECTURE.md section 9: get_eligible_validator_indices and
 * get_unslashed_participating_indices inlined in one pass over the validators.
 * x19 state, x20 config, x21 scratch, x22 result. Locals: L current epoch, L+8 previous epoch, L+16 leak.
 */
SPEC_FUNCTION process_inactivity_updates
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH x21, x19, 3, 9f
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #L]
    cmp     x9, #GENESIS_EPOCH
    b.eq    8f
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_previous_epoch
    mov     x0, x19
    add     x1, sp, #(L + 16)
    bl      lantern_is_in_inactivity_leak
    ldr     x4, [sp, #(L + 16)]             /* leak */
    ldr     x5, [sp, #(L + 8)]              /* previous epoch, and it + 1 */
    add     x6, x5, #1
    ldr     x7, [x20, #CONFIG_INACTIVITY_SCORE_BIAS]
    ldr     x8, [x20, #CONFIG_INACTIVITY_SCORE_RECOVERY_RATE]
    PART    x0, x1, x19, BeaconState_validators
    PART    x2, x9, x19, BeaconState_previous_epoch_participation
    PART    x3, x9, x19, BeaconState_inactivity_scores
    cbz     x1, 8f
1:  ldr     x9, [x0, #Validator_activation_epoch]
    ldr     x10, [x0, #Validator_exit_epoch]
    ldrb    w11, [x2], #1                   /* previous_epoch_participation[index] */
    ldrb    w12, [x0, #Validator_slashed]
    cmp     x9, x5                          /* is_active_validator(validator, previous) */
    ccmp    x5, x10, #2, ls
    b.lo    2f
    cbz     w12, 7f                         /* get_eligible_validator_indices: or slashed and */
    ldr     x10, [x0, #Validator_withdrawable_epoch]
    cmp     x6, x10                         /* previous_epoch + 1 < withdrawable_epoch */
    b.hs    7f
2:  cmp     w12, #0                         /* slashed (each one not active in previous is): */
    csel    w11, w11, wzr, eq               /* not in the unslashed participating set */
    ldr     x13, [x3]                       /* inactivity_scores[index] */
    tbz     w11, #TIMELY_TARGET_FLAG_INDEX, 3f
    subs    x14, x13, #1                    /* -= min(1, score): saturating_sub(score, 1) */
    csel    x13, x14, xzr, hi
    b       4f
3:  add     x13, x13, x7                    /* += INACTIVITY_SCORE_BIAS */
4:  cbnz    x4, 5f
    subs    x14, x13, x8                    /* saturating_sub(score, INACTIVITY_SCORE_RECOVERY_RATE) */
    csel    x13, x14, xzr, hi
5:  str     x13, [x3]
7:  add     x0, x0, #Validator__mem
    add     x3, x3, #8
    subs    x1, x1, #1
    b.ne    1b
8:  str     xzr, [x22]
    mov     x0, #LANTERN_OK
    LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END process_inactivity_updates
.endif

/* ---------------------------------------------------------------- Rewards and penalties */

/* Write count n to an output IndexList and zero its n entries. list x0, n x1. Uses x0-x3. */
LOCAL_FUNCTION zero_deltas
    UNWIND_END_PROLOGUE
    mov     x2, #LIST_FIXED
    str     x2, [x0, #LIST_OFFSET]
    str     x1, [x0, #LIST_COUNT]
    add     x0, x0, #LIST_FIXED
    lsl     x1, x1, #3
    b       lantern_zero
END_FUNCTION zero_deltas

.if FORK >= FORK_ALTAIR
/*
 * x19 state, x20 flag index, x21 scratch, x22 rewards, x23 penalties, x24 validator count,
 * x25 participating list, x26 eligible list, x27 eligible cursor, x28 participating cursor.
 * Locals: L previous epoch, L+8 participating balance, L+16 total active, L+24 leak,
 * L+32 eligible end, L+40 participating end, L+48 base reward, L+56 sub scratch,
 * L+64 callee result, L+72 index, L+80 weight, L+88 scratch size, L+96 base reward per increment.
 */
SPEC_FUNCTION get_flag_index_deltas
    ENTER 112
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    NEED_SCRATCH x21, x19, 3, 9f
    LDQ     x24, x19, BeaconState_validators + 8
    lsl     x9, x24, #3                     /* each output has room for every validator */
    add     x9, x9, #LIST_FIXED
    ldr     x10, [x22, #LIST_SIZE]
    cmp     x10, x9
    b.lo    9f
    ldr     x10, [x23, #LIST_SIZE]
    cmp     x10, x9
    b.lo    9f
    mov     x0, x22
    mov     x1, x24
    bl      zero_deltas
    mov     x0, x23
    mov     x1, x24
    bl      zero_deltas
    ldr     x9, [x21]
    str     x9, [sp, #(L + 88)]             /* the scratch size on entry */
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_previous_epoch
    ldr     x9, [sp, #(L + 88)]
    SCRATCH_LIST x25, x21, x9, 0, x24
    SCRATCH_LIST x26, x21, x9, 1, x24
    str     x21, [sp, #(L + 56)]
    SCRATCH_GIVE x21, x9, 2, x24
    mov     x9, x21
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #L
    mov     x3, x9
    mov     x4, x25
    bl      lantern_get_unslashed_participating_indices
    cbnz    x0, 8f
    ldr     x9, [x20]                       /* weight = PARTICIPATION_FLAG_WEIGHTS[flag_index] */
    mov     x10, #TIMELY_TARGET_WEIGHT
    mov     x11, #TIMELY_SOURCE_WEIGHT      /* the source and head weights are equal */
    cmp     x9, #TIMELY_TARGET_FLAG_INDEX
    csel    x10, x10, x11, eq
    str     x10, [sp, #(L + 80)]
    mov     x0, x19
    mov     x1, x25
    add     x2, sp, #(L + 8)
    bl      lantern_get_total_balance
    ldr     x9, [sp, #(L + 88)]
    SCRATCH_GIVE x21, x9, 2, x24
    mov     x0, x19
    ldr     x1, [sp, #(L + 56)]
    add     x2, sp, #(L + 16)
    bl      lantern_get_total_active_balance
    cbnz    x0, 8f
    mov     x0, x19
    mov     x1, x26
    bl      lantern_get_eligible_validator_indices
    cbnz    x0, 8f
    mov     x0, x19
    add     x1, sp, #(L + 24)
    bl      lantern_is_in_inactivity_leak
    ldr     x9, [sp, #(L + 88)]
    SCRATCH_GIVE x21, x9, 2, x24
    mov     x0, x19                         /* get_base_reward's factor, once for every index */
    ldr     x1, [sp, #(L + 56)]
    add     x2, sp, #(L + 96)
    bl      lantern_get_base_reward_per_increment
    cbnz    x0, 8f
    add     x27, x26, #LIST_FIXED
    ldr     x9, [x26, #LIST_COUNT]
    add     x9, x27, x9, lsl #3
    str     x9, [sp, #(L + 32)]
    add     x28, x25, #LIST_FIXED
    ldr     x9, [x25, #LIST_COUNT]
    add     x9, x28, x9, lsl #3
    str     x9, [sp, #(L + 40)]
1:  ldr     x9, [sp, #(L + 32)]
    cmp     x27, x9
    b.hs    7f
    ldr     x11, [x27], #8
    str     x11, [sp, #(L + 72)]
    PART    x9, x10, x19, BeaconState_validators
    add     x9, x9, x11, lsl #7             /* base_reward = get_base_reward(state, index): */
    ldr     x9, [x9, #Validator_effective_balance]
    MOVQ    x10, EFFECTIVE_BALANCE_INCREMENT
    udiv    x9, x9, x10                     /* increments * base_reward_per_increment */
    ldr     x10, [sp, #(L + 96)]
    mul     x9, x9, x10
    str     x9, [sp, #(L + 48)]
    ldr     x13, [sp, #(L + 40)]
    IN_SORTED x11, x28, x13
    b.ne    2f
    ldr     x9, [sp, #(L + 24)]             /* participating: a reward unless leaking */
    cbnz    x9, 1b
    ldr     x9, [sp, #(L + 48)]
    ldr     x10, [sp, #(L + 80)]
    mul     x9, x9, x10
    ldr     x10, [sp, #(L + 8)]
    MOVQ    x12, EFFECTIVE_BALANCE_INCREMENT
    udiv    x10, x10, x12                   /* unslashed_participating_increments */
    mul     x9, x9, x10
    ldr     x10, [sp, #(L + 16)]
    udiv    x10, x10, x12                   /* active_increments */
    mov     x12, #WEIGHT_DENOMINATOR
    mul     x10, x10, x12
    udiv    x9, x9, x10
    add     x10, x22, #LIST_FIXED
    add     x10, x10, x11, lsl #3
    ldr     x12, [x10]
    add     x12, x12, x9
    str     x12, [x10]
    b       1b
2:  ldr     x9, [x20]                       /* not participating: a penalty unless the flag is head */
    cmp     x9, #TIMELY_HEAD_FLAG_INDEX
    b.eq    1b
    ldr     x9, [sp, #(L + 48)]
    ldr     x10, [sp, #(L + 80)]
    mul     x9, x9, x10
    lsr     x9, x9, #6                      /* // WEIGHT_DENOMINATOR, which is 64 */
    add     x10, x23, #LIST_FIXED
    add     x10, x10, x11, lsl #3
    ldr     x12, [x10]
    add     x12, x12, x9
    str     x12, [x10]
    b       1b
7:  mov     x0, #LANTERN_OK
8:  LEAVE 112
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 112
SPEC_END get_flag_index_deltas
.endif

.if TIMELY_SOURCE_WEIGHT != TIMELY_HEAD_WEIGHT
.error "lantern_get_flag_index_deltas takes one weight for the source and head flags"
.endif

.if WEIGHT_DENOMINATOR != 64
.error "lantern_get_flag_index_deltas divides by WEIGHT_DENOMINATOR with a shift by 6"
.endif

.if FORK >= FORK_ALTAIR
/*
 * x19 state, x20 config, x21 scratch, x22 rewards, x23 penalties, x24 validator count,
 * x25 participating list, x26 eligible list, x27 eligible cursor, x28 participating cursor.
 * Locals: L previous epoch, L+8 flag index, L+16 callee result, L+24 eligible end, L+32 participating end.
 */
SPEC_FUNCTION get_inactivity_penalty_deltas
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    NEED_SCRATCH x21, x19, 3, 9f
    LDQ     x24, x19, BeaconState_validators + 8
    lsl     x9, x24, #3
    add     x9, x9, #LIST_FIXED
    ldr     x10, [x22, #LIST_SIZE]
    cmp     x10, x9
    b.lo    9f
    ldr     x10, [x23, #LIST_SIZE]
    cmp     x10, x9
    b.lo    9f
    mov     x0, x22
    mov     x1, x24
    bl      zero_deltas
    mov     x0, x23
    mov     x1, x24
    bl      zero_deltas
    ldr     x9, [x21]
    str     x9, [sp, #(L + 40)]             /* the scratch size on entry */
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_previous_epoch
    ldr     x9, [sp, #(L + 40)]
    SCRATCH_LIST x25, x21, x9, 0, x24
    SCRATCH_LIST x26, x21, x9, 1, x24
    SCRATCH_GIVE x21, x9, 2, x24
    mov     x3, x21
    mov     x9, #TIMELY_TARGET_FLAG_INDEX
    str     x9, [sp, #(L + 8)]
    mov     x0, x19
    add     x1, sp, #(L + 8)
    add     x2, sp, #L
    mov     x4, x25
    bl      lantern_get_unslashed_participating_indices
    cbnz    x0, 8f
    mov     x0, x19
    mov     x1, x26
    bl      lantern_get_eligible_validator_indices
    cbnz    x0, 8f
    add     x27, x26, #LIST_FIXED
    ldr     x9, [x26, #LIST_COUNT]
    add     x9, x27, x9, lsl #3
    str     x9, [sp, #(L + 24)]
    add     x28, x25, #LIST_FIXED
    ldr     x9, [x25, #LIST_COUNT]
    add     x9, x28, x9, lsl #3
    str     x9, [sp, #(L + 32)]
1:  ldr     x9, [sp, #(L + 24)]
    cmp     x27, x9
    b.hs    7f
    ldr     x11, [x27], #8
    ldr     x13, [sp, #(L + 32)]
    IN_SORTED x11, x28, x13
    b.eq    1b
    PART    x9, x10, x19, BeaconState_validators
    add     x9, x9, x11, lsl #7
    ldr     x9, [x9, #Validator_effective_balance]
    PART    x10, x12, x19, BeaconState_inactivity_scores
    ldr     x10, [x10, x11, lsl #3]
    mul     x9, x9, x10                     /* penalty_numerator */
    ldr     x10, [x20, #CONFIG_INACTIVITY_SCORE_BIAS]
    MOVQ    x12, FORK_INACTIVITY_PENALTY_QUOTIENT
    mul     x10, x10, x12                   /* penalty_denominator */
    udiv    x9, x9, x10
    add     x10, x23, #LIST_FIXED
    add     x10, x10, x11, lsl #3
    ldr     x12, [x10]
    add     x12, x12, x9
    str     x12, [x10]
    b       1b
7:  mov     x0, #LANTERN_OK
8:  LEAVE 64
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END get_inactivity_penalty_deltas
.endif

.if FORK >= FORK_ALTAIR
/*
 * A candidate of ARCHITECTURE.md section 9: get_flag_index_deltas and
 * get_inactivity_penalty_deltas inlined in two passes over the validators, with no lists.
 * Pass 1 sums the total active balance and each flag's unslashed participating balance;
 * pass 2 changes each eligible validator's balance by its deltas, in the spec's order.
 * x19 state, x20 config, x21 scratch, x22 result, x23 EFFECTIVE_BALANCE_INCREMENT,
 * x24-x26 weight * unslashed_participating_increments of the source, target and head
 * flags, x27 the inactivity penalty denominator, x28 leak. Locals: L current epoch,
 * L+8 previous epoch, L+16 total active balance, L+24 its square root, L+32 leak.
 */
SPEC_FUNCTION process_rewards_and_penalties
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH x21, x19, 11, 9f
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #L]
    cmp     x9, #GENESIS_EPOCH
    b.eq    8f
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_previous_epoch
    MOVQ    x23, EFFECTIVE_BALANCE_INCREMENT
    ldp     x8, x7, [sp, #L]                /* current, previous */
    PART    x0, x1, x19, BeaconState_validators
    PART    x2, x9, x19, BeaconState_previous_epoch_participation
    mov     x3, #0                          /* total active balance */
    mov     x4, #0                          /* the source, target and head balances */
    mov     x5, #0
    mov     x6, #0
    cbz     x1, 2f
1:  ldr     x9, [x0, #Validator_activation_epoch]
    ldr     x10, [x0, #Validator_exit_epoch]
    ldr     x11, [x0, #Validator_effective_balance]
    ldrb    w12, [x0, #Validator_slashed]
    ldrb    w13, [x2], #1                   /* previous_epoch_participation[index] */
    cmp     x9, x8                          /* is_active_validator(validator, current) */
    ccmp    x8, x10, #2, ls
    csel    x14, x11, xzr, lo
    add     x3, x3, x14
    cmp     x9, x7                          /* active in previous and not slashed: its flags count */
    ccmp    x7, x10, #2, ls
    ccmp    w12, #0, #0, lo
    csel    w13, w13, wzr, eq
    tst     w13, #(1 << TIMELY_SOURCE_FLAG_INDEX)
    csel    x14, x11, xzr, ne
    add     x4, x4, x14
    tst     w13, #(1 << TIMELY_TARGET_FLAG_INDEX)
    csel    x14, x11, xzr, ne
    add     x5, x5, x14
    tst     w13, #(1 << TIMELY_HEAD_FLAG_INDEX)
    csel    x14, x11, xzr, ne
    add     x6, x6, x14
    add     x0, x0, #Validator__mem
    subs    x1, x1, #1
    b.ne    1b
2:  cmp     x3, x23                         /* get_total_balance: max(EFFECTIVE_BALANCE_INCREMENT, sum) */
    csel    x3, x3, x23, hi
    cmp     x4, x23
    csel    x4, x4, x23, hi
    cmp     x5, x23
    csel    x5, x5, x23, hi
    cmp     x6, x23
    csel    x6, x6, x23, hi
    str     x3, [sp, #(L + 16)]
    udiv    x9, x4, x23                     /* weight * unslashed_participating_increments */
    mov     x10, #TIMELY_SOURCE_WEIGHT
    mul     x24, x9, x10
    udiv    x9, x5, x23
    mov     x10, #TIMELY_TARGET_WEIGHT
    mul     x25, x9, x10
    udiv    x9, x6, x23
    mov     x10, #TIMELY_HEAD_WEIGHT
    mul     x26, x9, x10
    ldr     x9, [x20, #CONFIG_INACTIVITY_SCORE_BIAS]
    MOVQ    x10, FORK_INACTIVITY_PENALTY_QUOTIENT
    mul     x27, x9, x10                    /* penalty_denominator */
    mov     x0, x19
    add     x1, sp, #(L + 32)
    bl      lantern_is_in_inactivity_leak
    ldr     x28, [sp, #(L + 32)]
    add     x0, sp, #(L + 16)               /* get_base_reward_per_increment */
    add     x1, sp, #(L + 24)
    bl      lantern_integer_squareroot
    ldr     x9, [sp, #(L + 24)]
    MOVQ    x7, EFFECTIVE_BALANCE_INCREMENT * BASE_REWARD_FACTOR
    udiv    x7, x7, x9
    ldr     x9, [sp, #(L + 16)]             /* active_increments * WEIGHT_DENOMINATOR */
    udiv    x8, x9, x23
    mov     x9, #WEIGHT_DENOMINATOR
    mul     x8, x8, x9
    ldr     x5, [sp, #(L + 8)]              /* previous epoch, and it + 1 */
    add     x6, x5, #1
    PART    x0, x1, x19, BeaconState_validators
    PART    x2, x9, x19, BeaconState_previous_epoch_participation
    PART    x3, x9, x19, BeaconState_balances
    PART    x4, x9, x19, BeaconState_inactivity_scores
    cbz     x1, 8f
3:  ldr     x9, [x0, #Validator_activation_epoch]
    ldr     x10, [x0, #Validator_exit_epoch]
    ldrb    w11, [x2], #1                   /* previous_epoch_participation[index] */
    ldrb    w12, [x0, #Validator_slashed]
    cmp     x9, x5                          /* is_active_validator(validator, previous) */
    ccmp    x5, x10, #2, ls
    b.lo    4f
    cbz     w12, 7f                         /* get_eligible_validator_indices: or slashed and */
    ldr     x10, [x0, #Validator_withdrawable_epoch]
    cmp     x6, x10                         /* previous_epoch + 1 < withdrawable_epoch */
    b.hs    7f
4:  cmp     w12, #0                         /* slashed (each one not active in previous is): */
    csel    w11, w11, wzr, eq               /* in no unslashed participating set */
    ldr     x13, [x0, #Validator_effective_balance]
    udiv    x14, x13, x23                   /* base_reward = get_base_reward(state, index) */
    mul     x14, x14, x7
    ldr     x15, [x3]                       /* balances[index] */
    tbz     w11, #TIMELY_SOURCE_FLAG_INDEX, 10f
    cbnz    x28, 11f                        /* participating: a reward unless leaking */
    mul     x9, x14, x24
    udiv    x9, x9, x8
    add     x15, x15, x9
    b       11f
10: mov     x9, #TIMELY_SOURCE_WEIGHT       /* not participating: decrease_balance by the penalty */
    mul     x9, x14, x9
    lsr     x9, x9, #6                      /* // WEIGHT_DENOMINATOR, which is 64 */
    subs    x10, x15, x9
    csel    x15, x10, xzr, hi
11: tbz     w11, #TIMELY_TARGET_FLAG_INDEX, 12f
    cbnz    x28, 13f
    mul     x9, x14, x25
    udiv    x9, x9, x8
    add     x15, x15, x9
    b       13f
12: mov     x9, #TIMELY_TARGET_WEIGHT
    mul     x9, x14, x9
    lsr     x9, x9, #6
    subs    x10, x15, x9
    csel    x15, x10, xzr, hi
13: tbz     w11, #TIMELY_HEAD_FLAG_INDEX, 14f   /* no head penalty */
    cbnz    x28, 14f
    mul     x9, x14, x26
    udiv    x9, x9, x8
    add     x15, x15, x9
14: tbnz    w11, #TIMELY_TARGET_FLAG_INDEX, 15f /* get_inactivity_penalty_deltas */
    ldr     x9, [x4]
    mul     x9, x13, x9                     /* penalty_numerator */
    udiv    x9, x9, x27
    subs    x10, x15, x9
    csel    x15, x10, xzr, hi
15: str     x15, [x3]
7:  add     x0, x0, #Validator__mem
    add     x3, x3, #8
    add     x4, x4, #8
    subs    x1, x1, #1
    b.ne    3b
8:  str     xzr, [x22]
    mov     x0, #LANTERN_OK
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END process_rewards_and_penalties
.endif

/* ---------------------------------------------------------------- Registry */

.if FORK >= FORK_ELECTRA
/*
 * x19 state, x20 config, x21 scratch, x22 result, x23 validator, x24 index,
 * x25 validator count. Locals: L current epoch, L+8 activation epoch, L+16 predicate, L+24 index.
 */
SPEC_FUNCTION process_registry_updates
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH x21, x19, 1, 9f
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    add     x0, sp, #L
    add     x1, sp, #(L + 8)
    bl      lantern_compute_activation_exit_epoch
    LDQ     x25, x19, BeaconState_validators + 8
    mov     x24, #0
1:  cmp     x24, x25
    b.hs    8f
    PART    x23, x9, x19, BeaconState_validators
    add     x23, x23, x24, lsl #7
    mov     x0, x23
    add     x1, sp, #(L + 16)
    bl      lantern_is_eligible_for_activation_queue
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 2f
    ldr     x9, [sp, #L]                    /* activation_eligibility_epoch = current_epoch + 1 */
    add     x9, x9, #1
    str     x9, [x23, #Validator_activation_eligibility_epoch]
    b       4f
2:  mov     x0, x23
    add     x1, sp, #L
    add     x2, sp, #(L + 16)
    bl      lantern_is_active_validator
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 3f
    ldr     x9, [x23, #Validator_effective_balance]
    ldr     x10, [x20, #CONFIG_EJECTION_BALANCE]
    cmp     x9, x10
    b.hi    3f
    str     x24, [sp, #(L + 24)]            /* initiate_validator_exit(state, index) */
    mov     x0, x19
    add     x1, sp, #(L + 24)
    mov     x2, x20
    mov     x3, x21
    mov     x4, x22
    bl      lantern_initiate_validator_exit
    cbnz    x0, 7f
    ldr     x9, [x22]
    cbnz    x9, 7f
    b       4f
3:  mov     x0, x19
    mov     x1, x23
    add     x2, sp, #(L + 16)
    bl      lantern_is_eligible_for_activation
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 4f
    ldr     x9, [sp, #(L + 8)]
    str     x9, [x23, #Validator_activation_epoch]
4:  add     x24, x24, #1
    b       1b
8:  str     xzr, [x22]
    mov     x0, #LANTERN_OK
7:  LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END process_registry_updates

/* x19 state, x20 index, x21 config, x22 scratch, x23 validator, x24 result. Locals: L exit queue epoch. */
SPEC_FUNCTION initiate_validator_exit
    ENTER 16
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    mov     x22, x3
    mov     x24, x4
    NEED_SCRATCH x22, x19, 1, 9f
    str     xzr, [x24]
    PART    x23, x9, x19, BeaconState_validators
    add     x23, x23, x20, lsl #7
    ldr     x9, [x23, #Validator_exit_epoch]
    cmn     x9, #1
    b.ne    8f                              /* already exiting */
    mov     x0, x19
    add     x1, x23, #Validator_effective_balance
    mov     x2, x21
    mov     x3, x22
    add     x4, sp, #L
    mov     x5, x24
    bl      lantern_compute_exit_epoch_and_update_churn
    cbnz    x0, 7f
    ldr     x9, [x24]
    cbnz    x9, 8f
    ldr     x9, [sp, #L]
    str     x9, [x23, #Validator_exit_epoch]
    ldr     x10, [x21, #CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY]
    adds    x9, x9, x10                     /* exit_epoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY */
    b.cs    6f
    str     x9, [x23, #Validator_withdrawable_epoch]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 16
6:  mov     x9, #LANTERN_INVALID_OVERFLOW
    str     x9, [x24]
    mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END initiate_validator_exit
.else
/*
 * Before electra. x19 state, x20 config, x21 scratch, x22 result, x23 validator, x24 index,
 * x25 validator count, x26 activations left, x27 the queue's next validator, x28 its key.
 * Locals: L current epoch, L+8 activation epoch, L+16 predicate, L+24 index, L+32 churn limit.
 */
SPEC_FUNCTION process_registry_updates
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    str     xzr, [x22]
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    add     x0, sp, #L
    add     x1, sp, #(L + 8)
    bl      lantern_compute_activation_exit_epoch
    LDQ     x25, x19, BeaconState_validators + 8
    mov     x24, #0
1:  cmp     x24, x25                        /* for index, validator in enumerate(state.validators) */
    b.hs    4f
    PART    x23, x9, x19, BeaconState_validators
    add     x23, x23, x24, lsl #7
    mov     x0, x23
    add     x1, sp, #(L + 16)
    bl      lantern_is_eligible_for_activation_queue
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 2f
    ldr     x9, [sp, #L]                    /* activation_eligibility_epoch = current_epoch + 1 */
    add     x9, x9, #1
    str     x9, [x23, #Validator_activation_eligibility_epoch]
2:  mov     x0, x23
    add     x1, sp, #L
    add     x2, sp, #(L + 16)
    bl      lantern_is_active_validator
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 3f
    ldr     x9, [x23, #Validator_effective_balance]
    ldr     x10, [x20, #CONFIG_EJECTION_BALANCE]
    cmp     x9, x10
    b.hi    3f
    str     x24, [sp, #(L + 24)]            /* initiate_validator_exit(state, index) */
    mov     x0, x19
    add     x1, sp, #(L + 24)
    mov     x2, x20
    mov     x3, x21
    mov     x4, x22
    bl      lantern_initiate_validator_exit
    cbnz    x0, 7f
    ldr     x9, [x22]
    cbnz    x9, 7f
3:  add     x24, x24, #1
    b       1b
4:  mov     x0, x19                         /* the churn limit */
    mov     x1, x20
    add     x2, sp, #(L + 32)
.if FORK == FORK_DENEB
    bl      lantern_get_validator_activation_churn_limit
.else
    bl      lantern_get_validator_churn_limit
.endif
    ldr     x26, [sp, #(L + 32)]
5:  cbz     x26, 8f                         /* the queue, by (activation_eligibility_epoch, index): */
    mov     x27, #-1                        /* take its first validator, which activation then leaves out */
    mov     x28, #-1
    mov     x24, #0
51: cmp     x24, x25
    b.hs    54f
    PART    x23, x9, x19, BeaconState_validators
    add     x23, x23, x24, lsl #7
    mov     x0, x19
    mov     x1, x23
    add     x2, sp, #(L + 16)
    bl      lantern_is_eligible_for_activation
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 53f
    ldr     x9, [x23, #Validator_activation_eligibility_epoch]
    cmp     x9, x28                         /* the lowest epoch; in index order, the first wins a tie */
    b.hs    53f
    mov     x28, x9
    mov     x27, x24
53: add     x24, x24, #1
    b       51b
54: cmn     x27, #1
    b.eq    8f                              /* the queue is empty */
    PART    x23, x9, x19, BeaconState_validators
    add     x23, x23, x27, lsl #7
    ldr     x9, [sp, #(L + 8)]              /* activation_epoch = compute_activation_exit_epoch(get_current_epoch(state)) */
    str     x9, [x23, #Validator_activation_epoch]
    sub     x26, x26, #1
    b       5b
8:  str     xzr, [x22]
    mov     x0, #LANTERN_OK
7:  LEAVE 48
SPEC_END process_registry_updates

/* Before electra. Locals: none. Uses x0-x6, x9-x12. A leaf. */
SPEC_LEAF get_validator_churn_limit
    LDQ     x3, x0, BeaconState_slot
    lsr     x3, x3, #LOG2_SLOTS_PER_EPOCH   /* the current epoch */
    PART    x4, x5, x0, BeaconState_validators
    mov     x6, #0                          /* len(get_active_validator_indices(state, get_current_epoch(state))) */
1:  cbz     x5, 2f
    ldr     x9, [x4, #Validator_activation_epoch]
    ldr     x10, [x4, #Validator_exit_epoch]
    cmp     x9, x3
    ccmp    x3, x10, #2, ls
    cinc    x6, x6, lo
    add     x4, x4, #Validator__mem
    sub     x5, x5, #1
    b       1b
2:  ldr     x9, [x1, #CONFIG_CHURN_LIMIT_QUOTIENT]
    udiv    x6, x6, x9
    ldr     x9, [x1, #CONFIG_MIN_PER_EPOCH_CHURN_LIMIT]
    cmp     x6, x9
    csel    x6, x6, x9, hi                  /* max(MIN_PER_EPOCH_CHURN_LIMIT, ...) */
    str     x6, [x2]
    RETURN_OK
SPEC_END get_validator_churn_limit

.if FORK == FORK_DENEB
/* Locals: sp+16 config, sp+24 out, sp+32 churn limit. */
SPEC_FUNCTION get_validator_activation_churn_limit
    FRAME 32
    stp     x1, x2, [sp, #16]
    add     x2, sp, #32
    bl      lantern_get_validator_churn_limit
    ldp     x1, x2, [sp, #16]
    ldr     x9, [sp, #32]
    ldr     x10, [x1, #CONFIG_MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT]
    cmp     x9, x10
    csel    x9, x9, x10, lo                 /* min(MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT, get_validator_churn_limit(state)) */
    str     x9, [x2]
    mov     x0, #LANTERN_OK
    UNFRAME 32
SPEC_END get_validator_activation_churn_limit
.endif

/*
 * Before electra. x19 state, x20 index, x21 config, x23 validator, x24 result.
 * Locals: L current epoch, L+8 exit queue epoch, L+16 churn limit.
 */
SPEC_FUNCTION initiate_validator_exit
    ENTER 32
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    mov     x24, x4
    str     xzr, [x24]
    PART    x23, x9, x19, BeaconState_validators
    add     x23, x23, x20, lsl #7
    ldr     x9, [x23, #Validator_exit_epoch]
    cmn     x9, #1
    b.ne    8f                              /* already exiting */
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    add     x0, sp, #L
    add     x1, sp, #(L + 8)
    bl      lantern_compute_activation_exit_epoch
    cbnz    x0, 6f
    ldr     x9, [sp, #(L + 8)]              /* exit_queue_epoch = max(exit_epochs + [compute_activation_exit_epoch(...)]) */
    PART    x10, x11, x19, BeaconState_validators
1:  cbz     x11, 2f
    ldr     x12, [x10, #Validator_exit_epoch]
    cmn     x12, #1
    b.eq    11f
    cmp     x12, x9
    csel    x9, x12, x9, hi
11: add     x10, x10, #Validator__mem
    sub     x11, x11, #1
    b       1b
2:  PART    x10, x11, x19, BeaconState_validators
    mov     x12, #0                         /* exit_queue_churn = len([v for v in validators if v.exit_epoch == exit_queue_epoch]) */
3:  cbz     x11, 4f
    ldr     x13, [x10, #Validator_exit_epoch]
    cmp     x13, x9
    cinc    x12, x12, eq
    add     x10, x10, #Validator__mem
    sub     x11, x11, #1
    b       3b
4:  str     x9, [sp, #(L + 8)]
    str     x12, [sp, #L]
    mov     x0, x19
    mov     x1, x21
    add     x2, sp, #(L + 16)
    bl      lantern_get_validator_churn_limit
    ldr     x9, [sp, #(L + 8)]
    ldr     x12, [sp, #L]
    ldr     x13, [sp, #(L + 16)]
    cmp     x12, x13                        /* if exit_queue_churn >= get_validator_churn_limit(state): exit_queue_epoch += 1 */
    b.lo    5f
    adds    x9, x9, #1
    b.cs    6f
5:  str     x9, [x23, #Validator_exit_epoch]
    ldr     x10, [x21, #CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY]
    adds    x9, x9, x10                     /* exit_epoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY */
    b.cs    6f
    str     x9, [x23, #Validator_withdrawable_epoch]
8:  mov     x0, #LANTERN_OK
    LEAVE 32
6:  mov     x9, #LANTERN_INVALID_OVERFLOW
    str     x9, [x24]
    mov     x0, #LANTERN_OK
    LEAVE 32
SPEC_END initiate_validator_exit
.endif

.if FORK >= FORK_ELECTRA
/*
 * x19 state, x20 exit balance, x21 config, x22 scratch, x23 out, x24 earliest exit epoch,
 * x25 per epoch churn, x26 exit balance to consume, x27 result.
 * Locals: L current epoch, L+8 activation exit epoch, L+16 churn.
 */
SPEC_FUNCTION compute_exit_epoch_and_update_churn
    ENTER 32
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x27, x5
    NEED_SCRATCH x22, x19, 1, 9f
    str     xzr, [x27]
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    add     x0, sp, #L
    add     x1, sp, #(L + 8)
    bl      lantern_compute_activation_exit_epoch
    LDQ     x9, x19, BeaconState_earliest_exit_epoch
    ldr     x10, [sp, #(L + 8)]
    cmp     x9, x10
    csel    x24, x9, x10, hi                /* max(state.earliest_exit_epoch, activation exit epoch) */
    mov     x0, x19
    mov     x1, x21
    mov     x2, x22
    add     x3, sp, #(L + 16)
    bl      lantern_get_activation_exit_churn_limit
    cbnz    x0, 7f
    ldr     x25, [sp, #(L + 16)]
    LDQ     x9, x19, BeaconState_earliest_exit_epoch
    LDQ     x26, x19, BeaconState_exit_balance_to_consume
    cmp     x9, x24
    csel    x26, x25, x26, lo               /* a new earliest epoch starts with a full churn */
    cmp     x20, x26
    b.ls    1f
    sub     x9, x20, x26                    /* balance_to_process */
    sub     x9, x9, #1
    udiv    x9, x9, x25
    add     x9, x9, #1                      /* additional_epochs */
    adds    x24, x24, x9
    b.cs    6f
    mul     x10, x9, x25                    /* additional_epochs * per_epoch_churn, checked */
    umulh   x11, x9, x25
    cbnz    x11, 6f
    adds    x26, x26, x10
    b.cs    6f
1:  sub     x26, x26, x20
    STQ     x26, x19, BeaconState_exit_balance_to_consume
    STQ     x24, x19, BeaconState_earliest_exit_epoch
    str     x24, [x23]
    mov     x0, #LANTERN_OK
7:  LEAVE 32
6:  mov     x9, #LANTERN_INVALID_OVERFLOW
    str     x9, [x27]
    mov     x0, #LANTERN_OK
    LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END compute_exit_epoch_and_update_churn
.endif

.if FORK >= FORK_ELECTRA
SPEC_FUNCTION get_balance_churn_limit
    FRAME 32
    stp     x1, x3, [sp, #16]               /* config, out */
    mov     x1, x2
    add     x2, sp, #32
    bl      lantern_get_total_active_balance
    cbnz    x0, 1f
    ldp     x1, x3, [sp, #16]
    ldr     x9, [sp, #32]
    ldr     x10, [x1, #CONFIG_CHURN_LIMIT_QUOTIENT]
    udiv    x9, x9, x10
    ldr     x10, [x1, #CONFIG_MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA]
    cmp     x9, x10
    csel    x9, x9, x10, hi                 /* churn = max(MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA, total // quotient) */
    MOVQ    x10, EFFECTIVE_BALANCE_INCREMENT
    udiv    x11, x9, x10
    mul     x9, x11, x10                    /* churn - churn % EFFECTIVE_BALANCE_INCREMENT */
    str     x9, [x3]
    mov     x0, #LANTERN_OK
1:  UNFRAME 32
SPEC_END get_balance_churn_limit
.endif

.if FORK >= FORK_ELECTRA
SPEC_FUNCTION get_activation_exit_churn_limit
    FRAME 32
    stp     x0, x1, [sp, #16]
    str     x3, [sp, #32]
    add     x3, sp, #40
    bl      lantern_get_balance_churn_limit
    cbnz    x0, 1f
    ldp     x0, x1, [sp, #16]
    ldr     x9, [sp, #40]
    ldr     x10, [x1, #CONFIG_MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT]
    cmp     x9, x10
    csel    x9, x9, x10, lo
    ldr     x3, [sp, #32]
    str     x9, [x3]
    mov     x0, #LANTERN_OK
1:  UNFRAME 32
SPEC_END get_activation_exit_churn_limit
.endif

.if FORK >= FORK_ELECTRA
SPEC_FUNCTION get_consolidation_churn_limit
    FRAME 48
    stp     x0, x1, [sp, #16]
    stp     x2, x3, [sp, #32]
    add     x3, sp, #48
    bl      lantern_get_balance_churn_limit
    cbnz    x0, 1f
    ldp     x0, x1, [sp, #16]
    ldr     x2, [sp, #32]
    add     x3, sp, #56
    bl      lantern_get_activation_exit_churn_limit
    cbnz    x0, 1f
    ldp     x9, x10, [sp, #48]
    sub     x9, x9, x10
    ldr     x3, [sp, #40]
    str     x9, [x3]
    mov     x0, #LANTERN_OK
1:  UNFRAME 48
SPEC_END get_consolidation_churn_limit
.endif

/* ---------------------------------------------------------------- Slashings */

/*
 * x19 state, x20 config, x21 scratch, x22 result, x23 epoch, x24 penalty per increment,
 * x25 index, x26 validator count. Locals: L epoch, L+8 total balance, L+16 index, L+24 penalty.
 */
SPEC_FUNCTION process_slashings
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH x21, x19, 1, 9f
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x23, [sp, #L]
    mov     x0, x19
    mov     x1, x21
    add     x2, sp, #(L + 8)
    bl      lantern_get_total_active_balance
    cbnz    x0, 7f
    ADDQ    x9, x19, BeaconState_slashings  /* sum(state.slashings) */
    MOVQ    x10, EPOCHS_PER_SLASHINGS_VECTOR
    mov     x11, #0
1:  ldr     x12, [x9], #8
    add     x11, x11, x12
    subs    x10, x10, #1
    b.ne    1b
    mov     x12, #FORK_PROPORTIONAL_SLASHING_MULTIPLIER
    mul     x11, x11, x12
    ldr     x12, [sp, #(L + 8)]
    cmp     x11, x12
    csel    x11, x11, x12, lo               /* adjusted_total_slashing_balance */
.if FORK >= FORK_ELECTRA
    MOVQ    x13, EFFECTIVE_BALANCE_INCREMENT
    udiv    x12, x12, x13
    udiv    x24, x11, x12                   /* penalty_per_effective_balance_increment */
.else
    mov     x24, x11
.endif
    LDQ     x26, x19, BeaconState_validators + 8
    mov     x25, #0
2:  cmp     x25, x26
    b.hs    8f
    PART    x9, x10, x19, BeaconState_validators
    add     x9, x9, x25, lsl #7
    ldrb    w10, [x9, #Validator_slashed]
    cbz     w10, 3f
    MOVQ    x10, EPOCHS_PER_SLASHINGS_VECTOR / 2
    add     x10, x23, x10
    ldr     x11, [x9, #Validator_withdrawable_epoch]
    cmp     x10, x11
    b.ne    3f
    ldr     x10, [x9, #Validator_effective_balance]
    MOVQ    x13, EFFECTIVE_BALANCE_INCREMENT
    udiv    x10, x10, x13
    mul     x10, x24, x10
.if FORK < FORK_ELECTRA
    ldr     x11, [sp, #(L + 8)]             /* penalty_numerator // total_balance * increment */
    udiv    x10, x10, x11
    mul     x10, x10, x13
.endif
    str     x10, [sp, #(L + 24)]
    str     x25, [sp, #(L + 16)]
    mov     x0, x19
    add     x1, sp, #(L + 16)
    add     x2, sp, #(L + 24)
    bl      lantern_decrease_balance
3:  add     x25, x25, #1
    b       2b
8:  str     xzr, [x22]
    mov     x0, #LANTERN_OK
7:  LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END process_slashings

/* ---------------------------------------------------------------- Eth1 data, consolidations */

SPEC_FUNCTION process_eth1_data_reset
    FRAME 32
    stp     x0, x3, [sp, #16]
    add     x1, sp, #32
    bl      lantern_get_current_epoch
    ldp     x0, x3, [sp, #16]
    ldr     x9, [sp, #32]
    add     x9, x9, #1                      /* next_epoch % EPOCHS_PER_ETH1_VOTING_PERIOD == 0 */
    mov     x10, #EPOCHS_PER_ETH1_VOTING_PERIOD
    udiv    x11, x9, x10
    msub    x11, x11, x10, x9
    cbnz    x11, 1f
    STQ     xzr, x0, BeaconState_eth1_data_votes + 8
1:  str     xzr, [x3]
    mov     x0, #LANTERN_OK
    UNFRAME 32
SPEC_END process_eth1_data_reset

.if FORK >= FORK_ELECTRA
/*
 * x19 state, x20 result, x21 next epoch, x22 consolidation, x23 consolidations left,
 * x24 processed. Locals: L epoch, L+8 source index, L+16 target index, L+24 balance.
 */
SPEC_FUNCTION process_pending_consolidations
    ENTER 32
    mov     x19, x0
    mov     x20, x3
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x21, [sp, #L]
    add     x21, x21, #1
    PART    x22, x23, x19, BeaconState_pending_consolidations
    mov     x24, #0
1:  cbz     x23, 4f
    ldr     x9, [x22, #PendingConsolidation_source_index]
    PART    x10, x11, x19, BeaconState_validators
    add     x10, x10, x9, lsl #7            /* source_validator */
    ldrb    w11, [x10, #Validator_slashed]
    cbnz    w11, 3f
    ldr     x11, [x10, #Validator_withdrawable_epoch]
    cmp     x11, x21
    b.hi    4f
    PART    x12, x13, x19, BeaconState_balances
    ldr     x12, [x12, x9, lsl #3]
    ldr     x11, [x10, #Validator_effective_balance]
    cmp     x12, x11
    csel    x12, x12, x11, lo               /* source_effective_balance */
    str     x12, [sp, #(L + 24)]
    str     x9, [sp, #(L + 8)]
    ldr     x9, [x22, #PendingConsolidation_target_index]
    str     x9, [sp, #(L + 16)]
    mov     x0, x19
    add     x1, sp, #(L + 8)
    add     x2, sp, #(L + 24)
    bl      lantern_decrease_balance
    mov     x0, x19
    add     x1, sp, #(L + 16)
    add     x2, sp, #(L + 24)
    bl      lantern_increase_balance
3:  add     x24, x24, #1
    add     x22, x22, #PendingConsolidation__mem
    sub     x23, x23, #1
    b       1b
4:  cbz     x24, 5f                         /* pending_consolidations = pending_consolidations[processed:] */
    PART    x0, x9, x19, BeaconState_pending_consolidations
    sub     x9, x9, x24
    STQ     x9, x19, BeaconState_pending_consolidations + 8
    add     x1, x0, x24, lsl #4             /* PendingConsolidation__mem is 16 */
    lsl     x2, x9, #4
    bl      lantern_copy
5:  str     xzr, [x20]
    mov     x0, #LANTERN_OK
    LEAVE 32
SPEC_END process_pending_consolidations
.endif

.if FORK >= FORK_ELECTRA
.if PendingConsolidation__mem != 16
.error "lantern_process_pending_consolidations shifts by 4 for PendingConsolidation"
.endif
.endif

/* ---------------------------------------------------------------- Effective balances */

/*
 * x19 state, x20 result, x21 validator, x22 index, x23 validator count.
 * Locals: L max effective balance.
 */
SPEC_FUNCTION process_effective_balance_updates
    ENTER 16
    mov     x19, x0
    mov     x20, x3
    LDQ     x23, x19, BeaconState_validators + 8
    mov     x22, #0
1:  cmp     x22, x23
    b.hs    3f
    PART    x21, x9, x19, BeaconState_validators
    add     x21, x21, x22, lsl #7
.if FORK >= FORK_ELECTRA
    mov     x0, x21
    add     x1, sp, #L
    bl      lantern_get_max_effective_balance
.else
    MOVQ    x9, MAX_EFFECTIVE_BALANCE
    str     x9, [sp, #L]
.endif
    PART    x9, x10, x19, BeaconState_balances
    ldr     x9, [x9, x22, lsl #3]           /* balance */
    ldr     x10, [x21, #Validator_effective_balance]
    MOVQ    x11, (EFFECTIVE_BALANCE_INCREMENT / HYSTERESIS_QUOTIENT) * HYSTERESIS_DOWNWARD_MULTIPLIER
    add     x11, x9, x11
    cmp     x11, x10                        /* balance + DOWNWARD_THRESHOLD < effective_balance */
    b.lo    2f
    MOVQ    x11, (EFFECTIVE_BALANCE_INCREMENT / HYSTERESIS_QUOTIENT) * HYSTERESIS_UPWARD_MULTIPLIER
    add     x11, x10, x11
    cmp     x11, x9                         /* or effective_balance + UPWARD_THRESHOLD < balance */
    b.hs    25f
2:  MOVQ    x12, EFFECTIVE_BALANCE_INCREMENT
    udiv    x13, x9, x12
    mul     x13, x13, x12                   /* balance - balance % EFFECTIVE_BALANCE_INCREMENT */
    ldr     x12, [sp, #L]
    cmp     x13, x12
    csel    x13, x13, x12, lo
    str     x13, [x21, #Validator_effective_balance]
25: add     x22, x22, #1
    b       1b
3:  str     xzr, [x20]
    mov     x0, #LANTERN_OK
    LEAVE 16
SPEC_END process_effective_balance_updates

/* ---------------------------------------------------------------- Resets and rotations */

SPEC_FUNCTION process_slashings_reset
    FRAME 32
    stp     x0, x3, [sp, #16]
    add     x1, sp, #32
    bl      lantern_get_current_epoch
    ldp     x0, x3, [sp, #16]
    ldr     x9, [sp, #32]
    add     x9, x9, #1
    and     x9, x9, #(EPOCHS_PER_SLASHINGS_VECTOR - 1)
    ADDQ    x10, x0, BeaconState_slashings
    str     xzr, [x10, x9, lsl #3]
    str     xzr, [x3]
    mov     x0, #LANTERN_OK
    UNFRAME 32
SPEC_END process_slashings_reset

SPEC_FUNCTION process_randao_mixes_reset
    FRAME 32
    stp     x0, x3, [sp, #16]
    add     x1, sp, #32
    bl      lantern_get_current_epoch
    ldr     x0, [sp, #16]
    ldr     x9, [sp, #32]
    add     x9, x9, #1                      /* randao_mixes[next % EPOCHS_PER_HISTORICAL_VECTOR] */
    and     x9, x9, #(EPOCHS_PER_HISTORICAL_VECTOR - 1)
    ADDQ    x2, x0, BeaconState_randao_mixes
    add     x2, x2, x9, lsl #5
    add     x1, sp, #32
    bl      lantern_get_randao_mix
    ldr     x3, [sp, #24]
    str     xzr, [x3]
    mov     x0, #LANTERN_OK
    UNFRAME 32
SPEC_END process_randao_mixes_reset

.if FORK <= FORK_BELLATRIX
.if BeaconState_state_roots != BeaconState_block_roots + BlockRoots__mem
.error "the state's block_roots and state_roots are not laid out as one HistoricalBatch"
.endif
/* x19 state, x20 scratch, x21 result, x22 the new entry. Locals: L epoch. */
SPEC_FUNCTION process_historical_roots_update
    ENTER 16
    mov     x19, x0
    mov     x20, x2
    mov     x21, x3
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #L]                    /* if next_epoch % (SLOTS_PER_HISTORICAL_ROOT // SLOTS_PER_EPOCH) == 0 */
    add     x9, x9, #1
    and     x9, x9, #(SLOTS_PER_HISTORICAL_ROOT / SLOTS_PER_EPOCH - 1)
    cbnz    x9, 8f
    ldr     x9, [x20]                       /* scratch for the root */
    MOVQ    x10, SSZ_SCR_WORK + HistoricalBatch__work
    cmp     x9, x10
    b.lo    9f
    LDQ     x9, x19, BeaconState_historical_roots
    LDQ     x10, x19, BeaconState_historical_roots + 8
    LDQ     x11, x19, BeaconState_eth1_data_votes       /* the next part starts at its room's end */
    sub     x11, x11, x9
    add     x12, x10, #1
    lsl     x12, x12, #5
    cmp     x11, x12
    b.lo    9f
    add     x22, x19, x9
    add     x22, x22, x10, lsl #5
    ADDRESS x0, lantern_type_HistoricalBatch    /* historical_roots.append(hash_tree_root(HistoricalBatch(block_roots, state_roots))) */
    ADDQ    x1, x19, BeaconState_block_roots
    mov     x2, x20
    mov     x3, x22
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    LDQ     x10, x19, BeaconState_historical_roots + 8
    add     x10, x10, #1
    STQ     x10, x19, BeaconState_historical_roots + 8
8:  str     xzr, [x21]
    mov     x0, #LANTERN_OK
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END process_historical_roots_update
.endif

.if FORK >= FORK_CAPELLA
/* x19 state, x20 scratch, x21 result, x22 the new summary. Locals: L epoch. */
SPEC_FUNCTION process_historical_summaries_update
    ENTER 16
    mov     x19, x0
    mov     x20, x2
    mov     x21, x3
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #L]
    add     x9, x9, #1
    and     x9, x9, #(SLOTS_PER_HISTORICAL_ROOT / SLOTS_PER_EPOCH - 1)
    cbnz    x9, 8f
    ldr     x9, [x20]                       /* scratch for the roots */
    MOVQ    x10, SSZ_SCR_WORK + BlockRoots__work
    cmp     x9, x10
    b.lo    9f
    LDQ     x9, x19, BeaconState_historical_summaries
    LDQ     x10, x19, BeaconState_historical_summaries + 8
.if FORK >= FORK_ELECTRA
    LDQ     x11, x19, BeaconState_pending_deposits      /* the next part starts its room's end */
.else
    ldr     x11, [x19]                      /* the last part ends at the end of the value */
.endif
    sub     x11, x11, x9
    add     x12, x10, #1
    lsl     x12, x12, #6                    /* HistoricalSummary__mem is 64 */
    cmp     x11, x12
    b.lo    9f
    add     x22, x19, x9
    add     x22, x22, x10, lsl #6
    ADDRESS x0, lantern_type_BlockRoots     /* block_summary_root = hash_tree_root(state.block_roots) */
    ADDQ    x1, x19, BeaconState_block_roots
    mov     x2, x20
    add     x3, x22, #HistoricalSummary_block_summary_root
    CALL_GLOBAL ssz_hash_tree_root
    ADDRESS x0, lantern_type_BlockRoots     /* state_summary_root = hash_tree_root(state.state_roots) */
    ADDQ    x1, x19, BeaconState_state_roots
    mov     x2, x20
    add     x3, x22, #HistoricalSummary_state_summary_root
    CALL_GLOBAL ssz_hash_tree_root
    LDQ     x10, x19, BeaconState_historical_summaries + 8
    add     x10, x10, #1
    STQ     x10, x19, BeaconState_historical_summaries + 8
8:  str     xzr, [x21]
    mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END process_historical_summaries_update
.endif

.if FORK >= FORK_CAPELLA
.if HistoricalSummary__mem != 64
.error "lantern_process_historical_summaries_update shifts by 6 for HistoricalSummary"
.endif
.endif

.if FORK >= FORK_ALTAIR
/* x19 state, x20 result. previous_epoch_participation = current; current = zeros, one per validator. */
SPEC_FUNCTION process_participation_flag_updates
    ENTER 16
    mov     x19, x0
    mov     x20, x3
    PART    x1, x9, x19, BeaconState_current_epoch_participation
    PART    x0, x10, x19, BeaconState_previous_epoch_participation
    STQ     x9, x19, BeaconState_previous_epoch_participation + 8
    mov     x2, x9
    bl      lantern_copy
    LDQ     x9, x19, BeaconState_validators + 8
    STQ     x9, x19, BeaconState_current_epoch_participation + 8
    PART    x0, x10, x19, BeaconState_current_epoch_participation
    mov     x1, x9
    bl      lantern_zero
    str     xzr, [x20]
    mov     x0, #LANTERN_OK
    LEAVE 16
SPEC_END process_participation_flag_updates
.endif

/* ---------------------------------------------------------------- Proposer lookahead */

.set LOOKAHEAD_LOCALS, (8 * SLOTS_PER_EPOCH + 8 + 15) / 16 * 16

.if FORK >= FORK_FULU
/* x19 state, x20 config, x21 scratch, x22 result. Locals: L the last epoch's proposers, then the epoch. */
SPEC_FUNCTION process_proposer_lookahead
    ENTER LOOKAHEAD_LOCALS
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH x21, x19, 2, 9f
    str     xzr, [x22]
    mov     x0, x19
    add     x1, sp, #(L + 8 * SLOTS_PER_EPOCH)
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #(L + 8 * SLOTS_PER_EPOCH)]
    add     x9, x9, #(MIN_SEED_LOOKAHEAD + 1)
    str     x9, [sp, #(L + 8 * SLOTS_PER_EPOCH)]
    mov     x0, x19                         /* get_beacon_proposer_indices(state, current + MIN_SEED_LOOKAHEAD + 1) */
    add     x1, sp, #(L + 8 * SLOTS_PER_EPOCH)
    mov     x2, x21
    add     x3, sp, #L
    bl      lantern_get_beacon_proposer_indices
    CHECK_STATUS x22, 7f, 8f
    ADDQ    x0, x19, BeaconState_proposer_lookahead   /* proposer_lookahead[:last_epoch_start] = proposer_lookahead[SLOTS_PER_EPOCH:] */
    ADDQ    x1, x19, BeaconState_proposer_lookahead + 8 * SLOTS_PER_EPOCH
    MOVQ    x2, 8 * SLOTS_PER_EPOCH * MIN_SEED_LOOKAHEAD
    bl      lantern_copy
    ADDQ    x0, x19, BeaconState_proposer_lookahead + 8 * SLOTS_PER_EPOCH * MIN_SEED_LOOKAHEAD
    add     x1, sp, #L
    MOVQ    x2, 8 * SLOTS_PER_EPOCH
    bl      lantern_copy
8:  mov     x0, #LANTERN_OK
7:  LEAVE LOOKAHEAD_LOCALS
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE LOOKAHEAD_LOCALS
SPEC_END process_proposer_lookahead
.endif

/* ---------------------------------------------------------------- The epoch */

.if FORK >= FORK_ELECTRA
.set EPOCH_LISTS, 11
.set EPOCH_EXTRA, SYNC_COMMITTEE_SCRATCH + SyncCommittee__mem + POSTPONE_BYTES
.elseif FORK >= FORK_ALTAIR
.set EPOCH_LISTS, 11
.set EPOCH_EXTRA, SYNC_COMMITTEE_SCRATCH + SyncCommittee__mem
.else
.set EPOCH_LISTS, 13
.set EPOCH_EXTRA, PENDING_REFS_BYTES
.endif

/* One step: stop at a failed status or a failed check. x19-x22 hold the arguments, x23 the scratch size. */
.macro EPOCH_STEP fn
    str     x23, [x21]
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    mov     x3, x22
    bl      \fn
    cbnz    x0, 7f
    ldr     x9, [x22]
    cbnz    x9, 8f
.endm

/* x19 state, x20 config, x21 scratch, x22 result, x23 scratch size. Locals: L epoch. */
SPEC_FUNCTION process_epoch
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH_B x21, x19, EPOCH_LISTS, EPOCH_EXTRA, 9f
.if FORK >= FORK_ELECTRA
    mov     x0, x19                         /* room for the deposits of the epoch */
    bl      validator_room
    cmp     x0, #MAX_PENDING_DEPOSITS_PER_EPOCH
    b.lo    9f
.endif
.if FORK == FORK_PHASE0
    mov     x0, x19                         /* room for the current epoch's attestations in the previous list */
    bl      record_room
    cbnz    x0, 9f
.endif
    mov     x0, x19                         /* and for a historical batch root or summary when one is due */
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #L]
    add     x9, x9, #1
    and     x9, x9, #(SLOTS_PER_HISTORICAL_ROOT / SLOTS_PER_EPOCH - 1)
    cbnz    x9, 1f
.if FORK >= FORK_CAPELLA
    LDQ     x9, x19, BeaconState_historical_summaries
    LDQ     x10, x19, BeaconState_historical_summaries + 8
.if FORK >= FORK_ELECTRA
    LDQ     x11, x19, BeaconState_pending_deposits
.else
    ldr     x11, [x19]                      /* the last part ends at the end of the value */
.endif
    sub     x11, x11, x9
    add     x12, x10, #1
    lsl     x12, x12, #6
.else
    LDQ     x9, x19, BeaconState_historical_roots
    LDQ     x10, x19, BeaconState_historical_roots + 8
    LDQ     x11, x19, BeaconState_eth1_data_votes
    sub     x11, x11, x9
    add     x12, x10, #1
    lsl     x12, x12, #5
.endif
    cmp     x11, x12
    b.lo    9f
1:  ldr     x23, [x21]
    EPOCH_STEP lantern_process_justification_and_finalization
.if FORK >= FORK_ALTAIR
    EPOCH_STEP lantern_process_inactivity_updates
.endif
    EPOCH_STEP lantern_process_rewards_and_penalties
    EPOCH_STEP lantern_process_registry_updates
    EPOCH_STEP lantern_process_slashings
    EPOCH_STEP lantern_process_eth1_data_reset
.if FORK >= FORK_ELECTRA
    EPOCH_STEP lantern_process_pending_deposits
    EPOCH_STEP lantern_process_pending_consolidations
.endif
    EPOCH_STEP lantern_process_effective_balance_updates
    EPOCH_STEP lantern_process_slashings_reset
    EPOCH_STEP lantern_process_randao_mixes_reset
.if FORK >= FORK_CAPELLA
    EPOCH_STEP lantern_process_historical_summaries_update
.else
    EPOCH_STEP lantern_process_historical_roots_update
.endif
.if FORK >= FORK_ALTAIR
    EPOCH_STEP lantern_process_participation_flag_updates
    EPOCH_STEP lantern_process_sync_committee_updates
.else
    EPOCH_STEP lantern_process_participation_record_updates
.endif
.if FORK >= FORK_FULU
    EPOCH_STEP lantern_process_proposer_lookahead
.endif
8:  mov     x0, #LANTERN_OK
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END process_epoch
