/*
 * Epoch processing, RISC-V. Requirements: docs/reference/epoch-processing.md.
 * v1: each function follows its spec steps and calls the spec functions it
 * names. A call whose result the loop cannot change is made once, before the loop.
 */

/* ---------------------------------------------------------------- Justification and finalization */

/*
 * s1 state, s2 config, s3 scratch, s4 result, s5 validator count, s6 previous list, s7 current list, s8 scratch.
 * Locals: L current epoch, L+8 previous epoch, L+16 total active, L+24 previous target balance,
 * L+32 current target balance, L+40 flag index, L+48 the scratch size on entry.
 */
FUNCTION lantern_process_justification_and_finalization
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH s3, s1, 3, 9f
    LDQ     s5, s1, BeaconState_validators + 8
    ld      t0, 0(s3)
    sd      t0, (L + 48)(sp)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, L(sp)
    li      t1, (GENESIS_EPOCH + 1)
    bleu    t0, t1, 8f
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_get_previous_epoch
    li      t0, TIMELY_TARGET_FLAG_INDEX
    sd      t0, (L + 40)(sp)
    ld      t0, (L + 48)(sp)
    SCRATCH_LIST s6, s3, t0, 0, s5
    SCRATCH_LIST s7, s3, t0, 1, s5
    mv      s8, s3
    SCRATCH_GIVE s3, t0, 2, s5
    mv      a0, s1                          # previous_indices
    addi    a1, sp, (L + 40)
    addi    a2, sp, (L + 8)
    mv      a3, s8
    mv      a4, s6
    call    lantern_get_unslashed_participating_indices
    CHECK_STATUS s4, 7f, 6f
    ld      t0, (L + 48)(sp)
    SCRATCH_GIVE s3, t0, 2, s5
    mv      a0, s1                          # current_indices
    addi    a1, sp, (L + 40)
    addi    a2, sp, L
    mv      a3, s8
    mv      a4, s7
    call    lantern_get_unslashed_participating_indices
    CHECK_STATUS s4, 7f, 6f
    ld      t0, (L + 48)(sp)
    SCRATCH_GIVE s3, t0, 2, s5
    mv      a0, s1
    mv      a1, s8
    addi    a2, sp, (L + 16)
    call    lantern_get_total_active_balance
    bnez    a0, 7f
    mv      a0, s1
    mv      a1, s6
    addi    a2, sp, (L + 24)
    call    lantern_get_total_balance
    mv      a0, s1
    mv      a1, s7
    addi    a2, sp, (L + 32)
    call    lantern_get_total_balance
    mv      a0, s1
    addi    a1, sp, (L + 16)
    addi    a2, sp, (L + 24)
    addi    a3, sp, (L + 32)
    mv      a4, s4
    call    lantern_weigh_justification_and_finalization
7:  LEAVE 64
6:  li      a0, LANTERN_OK
    LEAVE 64
8:  sd      zero, 0(s4)
    li      a0, LANTERN_OK
    LEAVE 64
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_process_justification_and_finalization

/* dst (40 bytes, a Checkpoint) = src. Uses a6. */
.macro COPY_CHECKPOINT dst, src
    ld      a6, 0(\src)
    sd      a6, 0(\dst)
    ld      a6, 8(\src)
    sd      a6, 8(\dst)
    ld      a6, 16(\src)
    sd      a6, 16(\dst)
    ld      a6, 24(\src)
    sd      a6, 24(\dst)
    ld      a6, 32(\src)
    sd      a6, 32(\dst)
.endm

/*
 * s1 state, s2 total, s3 previous target balance, s4 current target balance,
 * s5 result, s6 justification bits, s7 current epoch, s8 previous epoch.
 * Locals: L old previous justified (40), L+48 old current justified (40),
 * L+96 previous epoch, L+104 current epoch, L+112 root (32).
 */
FUNCTION lantern_weigh_justification_and_finalization
    ENTER 160
    mv      s1, a0
    ld      s2, 0(a1)
    ld      s3, 0(a2)
    ld      s4, 0(a3)
    mv      s5, a4
    mv      a0, s1
    addi    a1, sp, (L + 96)
    call    lantern_get_previous_epoch
    mv      a0, s1
    addi    a1, sp, (L + 104)
    call    lantern_get_current_epoch
    ld      s8, (L + 96)(sp)
    ld      s7, (L + 104)(sp)
    ADDQ    t0, s1, BeaconState_previous_justified_checkpoint   # keep the old checkpoints
    addi    t1, sp, L
    COPY_CHECKPOINT t1, t0
    ADDQ    t0, s1, BeaconState_current_justified_checkpoint
    addi    t1, sp, (L + 48)
    COPY_CHECKPOINT t1, t0
    ADDQ    t0, s1, BeaconState_previous_justified_checkpoint   # previous = current
    COPY_CHECKPOINT t0, t1
    ADDQ    t0, s1, BeaconState_justification_bits              # bits[1:] = bits[:3]; bits[0] = False
    lbu     s6, 0(t0)
    slli    s6, s6, 1
    andi    s6, s6, 0xf
    li      t0, 3
    mul     t1, s3, t0                      # previous_epoch_target_balance * 3 >= total * 2
    slli    t2, s2, 1
    bltu    t1, t2, 1f
    mv      a0, s1
    addi    a1, sp, (L + 96)
    addi    a2, sp, (L + 112)
    call    lantern_get_block_root
    CHECK_STATUS s5, 6f, 6f
    ADDQ    t0, s1, BeaconState_current_justified_checkpoint
    sd      s8, Checkpoint_epoch(t0)
    addi    t0, t0, Checkpoint_root
    addi    t1, sp, (L + 112)
    COPY32  t0, t1
    ori     s6, s6, 2
1:  li      t0, 3
    mul     t1, s4, t0                      # current_epoch_target_balance * 3 >= total * 2
    slli    t2, s2, 1
    bltu    t1, t2, 2f
    mv      a0, s1
    addi    a1, sp, (L + 104)
    addi    a2, sp, (L + 112)
    call    lantern_get_block_root
    CHECK_STATUS s5, 6f, 6f
    ADDQ    t0, s1, BeaconState_current_justified_checkpoint
    sd      s7, Checkpoint_epoch(t0)
    addi    t0, t0, Checkpoint_root
    addi    t1, sp, (L + 112)
    COPY32  t0, t1
    ori     s6, s6, 1
2:  ADDQ    t0, s1, BeaconState_justification_bits
    sb      s6, 0(t0)
    li      t3, 0                           # the checkpoint to finalize: 0 none
    ld      t0, L(sp)                       # old previous justified epoch
    ld      t1, (L + 48)(sp)                # old current justified epoch
    andi    t2, s6, 0xe                     # bits[1:4] and old_previous + 3 == current
    li      t4, 0xe
    bne     t2, t4, 3f
    addi    t4, t0, 3
    bne     t4, s7, 3f
    addi    t3, sp, L
3:  andi    t2, s6, 0x6                     # bits[1:3] and old_previous + 2 == current
    li      t4, 0x6
    bne     t2, t4, 4f
    addi    t4, t0, 2
    bne     t4, s7, 4f
    addi    t3, sp, L
4:  andi    t2, s6, 0x7                     # bits[0:3] and old_current + 2 == current
    li      t4, 0x7
    bne     t2, t4, 5f
    addi    t4, t1, 2
    bne     t4, s7, 5f
    addi    t3, sp, (L + 48)
5:  andi    t2, s6, 0x3                     # bits[0:2] and old_current + 1 == current
    li      t4, 0x3
    bne     t2, t4, 55f
    addi    t4, t1, 1
    bne     t4, s7, 55f
    addi    t3, sp, (L + 48)
55: beqz    t3, 56f
    ADDQ    t0, s1, BeaconState_finalized_checkpoint
    COPY_CHECKPOINT t0, t3
56: sd      zero, 0(s5)
6:  li      a0, LANTERN_OK
    LEAVE 160
END_FUNCTION lantern_weigh_justification_and_finalization

/* ---------------------------------------------------------------- Inactivity */

/*
 * s1 state, s2 config, s3 scratch, s4 result, s5 validator count, s6 eligible list,
 * s7 participating list, s8 score, s9 eligible cursor, s10 participating cursor.
 * Locals: L epoch, L+8 previous epoch, L+16 flag index, L+24 in leak, L+32 eligible end,
 * L+40 participating end, L+56 the constant 1, L+64 the scratch size on entry.
 */
FUNCTION lantern_process_inactivity_updates
    ENTER 80
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH s3, s1, 3, 9f
    LDQ     s5, s1, BeaconState_validators + 8
    ld      t0, 0(s3)
    sd      t0, (L + 64)(sp)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, L(sp)
    li      t1, GENESIS_EPOCH
    beq     t0, t1, 8f
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_get_previous_epoch
    ld      t0, (L + 64)(sp)
    SCRATCH_LIST s6, s3, t0, 0, s5
    SCRATCH_LIST s7, s3, t0, 1, s5
    mv      a0, s1
    mv      a1, s6
    call    lantern_get_eligible_validator_indices
    bnez    a0, 7f
    li      t0, TIMELY_TARGET_FLAG_INDEX
    sd      t0, (L + 16)(sp)
    ld      t0, (L + 64)(sp)
    SCRATCH_GIVE s3, t0, 2, s5
    mv      a0, s1
    addi    a1, sp, (L + 16)
    addi    a2, sp, (L + 8)
    mv      a3, s3
    mv      a4, s7
    call    lantern_get_unslashed_participating_indices
    CHECK_STATUS s4, 7f, 6f
    mv      a0, s1
    addi    a1, sp, (L + 24)
    call    lantern_is_in_inactivity_leak
    li      t0, 1
    sd      t0, (L + 56)(sp)
    addi    s9, s6, LIST_FIXED
    ld      t0, LIST_COUNT(s6)
    slli    t0, t0, 3
    add     t0, s9, t0
    sd      t0, (L + 32)(sp)
    addi    s10, s7, LIST_FIXED
    ld      t0, LIST_COUNT(s7)
    slli    t0, t0, 3
    add     t0, s10, t0
    sd      t0, (L + 40)(sp)
1:  ld      t0, (L + 32)(sp)
    bgeu    s9, t0, 8f
    ld      t2, 0(s9)                       # index
    addi    s9, s9, 8
    PART    s8, t4, s1, BeaconState_inactivity_scores
    slli    t3, t2, 3
    add     s8, s8, t3                      # &state.inactivity_scores[index]
    ld      t4, (L + 40)(sp)
    IN_SORTED t2, s10, t4, t5
    beqz    t5, 2f
    mv      a0, s8                          # saturating_sub(score, 1)
    addi    a1, sp, (L + 56)
    mv      a2, s8
    call    lantern_saturating_sub
    j       3f
2:  ld      t0, 0(s8)                       # += INACTIVITY_SCORE_BIAS
    ld      t1, CONFIG_INACTIVITY_SCORE_BIAS(s2)
    add     t0, t0, t1
    sd      t0, 0(s8)
3:  ld      t0, (L + 24)(sp)
    bnez    t0, 1b
    mv      a0, s8                          # saturating_sub(score, INACTIVITY_SCORE_RECOVERY_RATE)
    addi    a1, s2, CONFIG_INACTIVITY_SCORE_RECOVERY_RATE
    mv      a2, s8
    call    lantern_saturating_sub
    j       1b
7:  LEAVE 80
6:  li      a0, LANTERN_OK
    LEAVE 80
8:  sd      zero, 0(s4)
    li      a0, LANTERN_OK
    LEAVE 80
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
END_FUNCTION lantern_process_inactivity_updates

/* ---------------------------------------------------------------- Rewards and penalties */

/* Write count n to an output IndexList and zero its n entries. list a0, n a1. */
LOCAL_FUNCTION zero_deltas
    UNWIND_END_PROLOGUE
    li      a2, LIST_FIXED
    sd      a2, LIST_OFFSET(a0)
    sd      a1, LIST_COUNT(a0)
    addi    a0, a0, LIST_FIXED
    slli    a1, a1, 3
    tail    lantern_zero
END_FUNCTION zero_deltas

/*
 * s1 state, s2 flag index, s3 scratch, s4 rewards, s5 penalties, s6 validator count,
 * s7 participating list, s8 eligible list, s9 eligible cursor, s10 participating cursor.
 * Locals: L previous epoch, L+8 participating balance, L+16 total active, L+24 leak,
 * L+32 eligible end, L+40 participating end, L+48 base reward, L+56 scratch,
 * L+72 index, L+80 weight, L+88 the scratch size on entry.
 */
FUNCTION lantern_get_flag_index_deltas
    ENTER 112
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH s3, s1, 3, 9f
    LDQ     s6, s1, BeaconState_validators + 8
    slli    t0, s6, 3                       # each output has room for every validator
    addi    t0, t0, LIST_FIXED
    ld      t1, LIST_SIZE(s4)
    bltu    t1, t0, 9f
    ld      t1, LIST_SIZE(s5)
    bltu    t1, t0, 9f
    mv      a0, s4
    mv      a1, s6
    call    zero_deltas
    mv      a0, s5
    mv      a1, s6
    call    zero_deltas
    ld      t0, 0(s3)
    sd      t0, (L + 88)(sp)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_previous_epoch
    ld      t0, (L + 88)(sp)
    SCRATCH_LIST s7, s3, t0, 0, s6
    SCRATCH_LIST s8, s3, t0, 1, s6
    sd      s3, (L + 56)(sp)
    SCRATCH_GIVE s3, t0, 2, s6
    mv      a0, s1
    mv      a1, s2
    addi    a2, sp, L
    mv      a3, s3
    mv      a4, s7
    call    lantern_get_unslashed_participating_indices
    bnez    a0, 8f
    ld      t0, 0(s2)                       # weight = PARTICIPATION_FLAG_WEIGHTS[flag_index]
    li      t1, TIMELY_SOURCE_WEIGHT        # the source and head weights are equal
    li      t2, TIMELY_TARGET_FLAG_INDEX
    bne     t0, t2, 1f
    li      t1, TIMELY_TARGET_WEIGHT
1:  sd      t1, (L + 80)(sp)
    mv      a0, s1
    mv      a1, s7
    addi    a2, sp, (L + 8)
    call    lantern_get_total_balance
    ld      t0, (L + 88)(sp)
    SCRATCH_GIVE s3, t0, 2, s6
    mv      a0, s1
    ld      a1, (L + 56)(sp)
    addi    a2, sp, (L + 16)
    call    lantern_get_total_active_balance
    bnez    a0, 8f
    mv      a0, s1
    mv      a1, s8
    call    lantern_get_eligible_validator_indices
    bnez    a0, 8f
    mv      a0, s1
    addi    a1, sp, (L + 24)
    call    lantern_is_in_inactivity_leak
    addi    s9, s8, LIST_FIXED
    ld      t0, LIST_COUNT(s8)
    slli    t0, t0, 3
    add     t0, s9, t0
    sd      t0, (L + 32)(sp)
    addi    s10, s7, LIST_FIXED
    ld      t0, LIST_COUNT(s7)
    slli    t0, t0, 3
    add     t0, s10, t0
    sd      t0, (L + 40)(sp)
2:  ld      t0, (L + 32)(sp)
    bgeu    s9, t0, 7f
    ld      t2, 0(s9)
    addi    s9, s9, 8
    sd      t2, (L + 72)(sp)
    ld      t0, (L + 88)(sp)
    SCRATCH_GIVE s3, t0, 2, s6
    mv      a0, s1                          # base_reward = get_base_reward(state, index)
    addi    a1, sp, (L + 72)
    ld      a2, (L + 56)(sp)
    addi    a3, sp, (L + 48)
    call    lantern_get_base_reward
    bnez    a0, 8f
    ld      t2, (L + 72)(sp)
    ld      t4, (L + 40)(sp)
    IN_SORTED t2, s10, t4, t5
    beqz    t5, 3f
    ld      t0, (L + 24)(sp)                # participating: a reward unless leaking
    bnez    t0, 2b
    ld      t0, (L + 48)(sp)
    ld      t1, (L + 80)(sp)
    mul     t0, t0, t1
    ld      t1, (L + 8)(sp)
    li      t3, EFFECTIVE_BALANCE_INCREMENT
    divu    t1, t1, t3                      # unslashed_participating_increments
    mul     t0, t0, t1
    ld      t1, (L + 16)(sp)
    divu    t1, t1, t3                      # active_increments
    li      t3, WEIGHT_DENOMINATOR
    mul     t1, t1, t3
    divu    t0, t0, t1
    slli    t1, t2, 3
    add     t1, s4, t1
    ld      t3, LIST_FIXED(t1)
    add     t3, t3, t0
    sd      t3, LIST_FIXED(t1)
    j       2b
3:  ld      t0, 0(s2)                       # not participating: a penalty unless the flag is head
    li      t1, TIMELY_HEAD_FLAG_INDEX
    beq     t0, t1, 2b
    ld      t0, (L + 48)(sp)
    ld      t1, (L + 80)(sp)
    mul     t0, t0, t1
    srli    t0, t0, 6                       # // WEIGHT_DENOMINATOR, which is 64
    slli    t1, t2, 3
    add     t1, s5, t1
    ld      t3, LIST_FIXED(t1)
    add     t3, t3, t0
    sd      t3, LIST_FIXED(t1)
    j       2b
7:  li      a0, LANTERN_OK
8:  LEAVE 112
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 112
END_FUNCTION lantern_get_flag_index_deltas

/*
 * s1 state, s2 config, s3 scratch, s4 rewards, s5 penalties, s6 validator count,
 * s7 participating list, s8 eligible list, s9 eligible cursor, s10 participating cursor.
 * Locals: L previous epoch, L+8 flag index, L+24 eligible end, L+32 participating end, L+40 the scratch size.
 */
FUNCTION lantern_get_inactivity_penalty_deltas
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH s3, s1, 3, 9f
    LDQ     s6, s1, BeaconState_validators + 8
    slli    t0, s6, 3
    addi    t0, t0, LIST_FIXED
    ld      t1, LIST_SIZE(s4)
    bltu    t1, t0, 9f
    ld      t1, LIST_SIZE(s5)
    bltu    t1, t0, 9f
    mv      a0, s4
    mv      a1, s6
    call    zero_deltas
    mv      a0, s5
    mv      a1, s6
    call    zero_deltas
    ld      t0, 0(s3)
    sd      t0, (L + 40)(sp)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_previous_epoch
    ld      t0, (L + 40)(sp)
    SCRATCH_LIST s7, s3, t0, 0, s6
    SCRATCH_LIST s8, s3, t0, 1, s6
    SCRATCH_GIVE s3, t0, 2, s6
    li      t0, TIMELY_TARGET_FLAG_INDEX
    sd      t0, (L + 8)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 8)
    addi    a2, sp, L
    mv      a3, s3
    mv      a4, s7
    call    lantern_get_unslashed_participating_indices
    bnez    a0, 8f
    mv      a0, s1
    mv      a1, s8
    call    lantern_get_eligible_validator_indices
    bnez    a0, 8f
    addi    s9, s8, LIST_FIXED
    ld      t0, LIST_COUNT(s8)
    slli    t0, t0, 3
    add     t0, s9, t0
    sd      t0, (L + 24)(sp)
    addi    s10, s7, LIST_FIXED
    ld      t0, LIST_COUNT(s7)
    slli    t0, t0, 3
    add     t0, s10, t0
    sd      t0, (L + 32)(sp)
1:  ld      t0, (L + 24)(sp)
    bgeu    s9, t0, 7f
    ld      t2, 0(s9)
    addi    s9, s9, 8
    ld      t4, (L + 32)(sp)
    IN_SORTED t2, s10, t4, t5
    bnez    t5, 1b
    PART    t0, t1, s1, BeaconState_validators
    slli    t1, t2, 7
    add     t0, t0, t1
    ld      t0, Validator_effective_balance(t0)
    PART    t1, t3, s1, BeaconState_inactivity_scores
    slli    t3, t2, 3
    add     t1, t1, t3
    ld      t1, 0(t1)
    mul     t0, t0, t1                      # penalty_numerator
    ld      t1, CONFIG_INACTIVITY_SCORE_BIAS(s2)
    li      t3, INACTIVITY_PENALTY_QUOTIENT_BELLATRIX
    mul     t1, t1, t3                      # penalty_denominator
    divu    t0, t0, t1
    slli    t1, t2, 3
    add     t1, s5, t1
    ld      t3, LIST_FIXED(t1)
    add     t3, t3, t0
    sd      t3, LIST_FIXED(t1)
    j       1b
7:  li      a0, LANTERN_OK
8:  LEAVE 64
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_get_inactivity_penalty_deltas

/*
 * s1 state, s2 config, s3 scratch, s4 result, s5 validator count, s6 delta pair, s7 index,
 * s8 the scratch size on entry. Scratch: lists 0 to 7 at its end. Locals: L epoch, L+8 flag index, L+16 index.
 */
FUNCTION lantern_process_rewards_and_penalties
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH s3, s1, 11, 9f
    LDQ     s5, s1, BeaconState_validators + 8
    ld      s8, 0(s3)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, L(sp)
    li      t1, GENESIS_EPOCH
    beq     t0, t1, 8f
    li      s6, 0                           # flag_deltas for each flag
1:  sd      s6, (L + 8)(sp)
    slli    t0, s6, 1
    SCRATCH_LIST_R t1, s3, s8, t0, s5
    addi    t0, t0, 1
    SCRATCH_LIST_R t2, s3, s8, t0, s5
    SCRATCH_GIVE s3, s8, 8, s5
    mv      a0, s1
    addi    a1, sp, (L + 8)
    mv      a2, s3
    mv      a3, t1
    mv      a4, t2
    call    lantern_get_flag_index_deltas
    CHECK_STATUS s4, 7f, 6f
    addi    s6, s6, 1
    li      t0, 3
    bltu    s6, t0, 1b
    SCRATCH_LIST t1, s3, s8, 6, s5          # get_inactivity_penalty_deltas
    SCRATCH_LIST t2, s3, s8, 7, s5
    SCRATCH_GIVE s3, s8, 8, s5
    mv      a0, s1
    mv      a1, s2
    mv      a2, s3
    mv      a3, t1
    mv      a4, t2
    call    lantern_get_inactivity_penalty_deltas
    CHECK_STATUS s4, 7f, 6f
    li      s6, 0                           # for rewards, penalties in deltas
2:  li      s7, 0
3:  bgeu    s7, s5, 4f
    sd      s7, (L + 16)(sp)
    slli    t0, s6, 1
    SCRATCH_LIST_R t1, s3, s8, t0, s5
    addi    a2, t1, LIST_FIXED
    slli    t0, s7, 3
    add     a2, a2, t0
    mv      a0, s1
    addi    a1, sp, (L + 16)
    call    lantern_increase_balance
    slli    t0, s6, 1
    addi    t0, t0, 1
    SCRATCH_LIST_R t1, s3, s8, t0, s5
    addi    a2, t1, LIST_FIXED
    slli    t0, s7, 3
    add     a2, a2, t0
    mv      a0, s1
    addi    a1, sp, (L + 16)
    call    lantern_decrease_balance
    addi    s7, s7, 1
    j       3b
4:  addi    s6, s6, 1
    li      t0, 4
    bltu    s6, t0, 2b
8:  sd      zero, 0(s4)
6:  li      a0, LANTERN_OK
7:  LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION lantern_process_rewards_and_penalties

/* ---------------------------------------------------------------- Registry */

/*
 * s1 state, s2 config, s3 scratch, s4 result, s5 validator, s6 index, s7 validator count.
 * Locals: L current epoch, L+8 activation epoch, L+16 predicate, L+24 index.
 */
FUNCTION lantern_process_registry_updates
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH s3, s1, 1, 9f
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    addi    a0, sp, L
    addi    a1, sp, (L + 8)
    call    lantern_compute_activation_exit_epoch
    LDQ     s7, s1, BeaconState_validators + 8
    li      s6, 0
1:  bgeu    s6, s7, 8f
    PART    s5, t0, s1, BeaconState_validators
    slli    t0, s6, 7
    add     s5, s5, t0
    mv      a0, s5
    addi    a1, sp, (L + 16)
    call    lantern_is_eligible_for_activation_queue
    ld      t0, (L + 16)(sp)
    beqz    t0, 2f
    ld      t0, L(sp)                       # activation_eligibility_epoch = current_epoch + 1
    addi    t0, t0, 1
    sd      t0, Validator_activation_eligibility_epoch(s5)
    j       4f
2:  mv      a0, s5
    addi    a1, sp, L
    addi    a2, sp, (L + 16)
    call    lantern_is_active_validator
    ld      t0, (L + 16)(sp)
    beqz    t0, 3f
    ld      t0, Validator_effective_balance(s5)
    ld      t1, CONFIG_EJECTION_BALANCE(s2)
    bgtu    t0, t1, 3f
    sd      s6, (L + 24)(sp)                # initiate_validator_exit(state, index)
    mv      a0, s1
    addi    a1, sp, (L + 24)
    mv      a2, s2
    mv      a3, s3
    mv      a4, s4
    call    lantern_initiate_validator_exit
    bnez    a0, 7f
    ld      t0, 0(s4)
    bnez    t0, 7f
    j       4f
3:  mv      a0, s1
    mv      a1, s5
    addi    a2, sp, (L + 16)
    call    lantern_is_eligible_for_activation
    ld      t0, (L + 16)(sp)
    beqz    t0, 4f
    ld      t0, (L + 8)(sp)
    sd      t0, Validator_activation_epoch(s5)
4:  addi    s6, s6, 1
    j       1b
8:  sd      zero, 0(s4)
    li      a0, LANTERN_OK
7:  LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION lantern_process_registry_updates

/* s1 state, s2 index, s3 config, s4 scratch, s5 validator, s6 result. Locals: L exit queue epoch. */
FUNCTION lantern_initiate_validator_exit
    ENTER 16
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    mv      s4, a3
    mv      s6, a4
    NEED_SCRATCH s4, s1, 1, 9f
    sd      zero, 0(s6)
    PART    s5, t0, s1, BeaconState_validators
    slli    t0, s2, 7
    add     s5, s5, t0
    ld      t0, Validator_exit_epoch(s5)
    li      t1, -1
    bne     t0, t1, 8f                      # already exiting
    mv      a0, s1
    addi    a1, s5, Validator_effective_balance
    mv      a2, s3
    mv      a3, s4
    addi    a4, sp, L
    mv      a5, s6
    call    lantern_compute_exit_epoch_and_update_churn
    bnez    a0, 7f
    ld      t0, 0(s6)
    bnez    t0, 8f
    ld      t0, L(sp)
    sd      t0, Validator_exit_epoch(s5)
    ld      t1, CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY(s3)
    add     t1, t0, t1                      # exit_epoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY
    bltu    t1, t0, 6f
    sd      t1, Validator_withdrawable_epoch(s5)
8:  li      a0, LANTERN_OK
7:  LEAVE 16
6:  li      t0, LANTERN_INVALID_OVERFLOW
    sd      t0, 0(s6)
    li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_initiate_validator_exit

/*
 * s1 state, s2 exit balance, s3 config, s4 scratch, s5 out, s6 earliest exit epoch,
 * s7 per epoch churn, s8 exit balance to consume, s9 result.
 * Locals: L current epoch, L+8 activation exit epoch, L+16 churn.
 */
FUNCTION lantern_compute_exit_epoch_and_update_churn
    ENTER 32
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s9, a5
    NEED_SCRATCH s4, s1, 1, 9f
    sd      zero, 0(s9)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    addi    a0, sp, L
    addi    a1, sp, (L + 8)
    call    lantern_compute_activation_exit_epoch
    LDQ     t0, s1, BeaconState_earliest_exit_epoch
    ld      t1, (L + 8)(sp)
    mv      s6, t0                          # max(state.earliest_exit_epoch, activation exit epoch)
    bgtu    t0, t1, 1f
    mv      s6, t1
1:  mv      a0, s1
    mv      a1, s3
    mv      a2, s4
    addi    a3, sp, (L + 16)
    call    lantern_get_activation_exit_churn_limit
    bnez    a0, 7f
    ld      s7, (L + 16)(sp)
    LDQ     t0, s1, BeaconState_earliest_exit_epoch
    LDQ     s8, s1, BeaconState_exit_balance_to_consume
    bgeu    t0, s6, 2f                      # a new earliest epoch starts with a full churn
    mv      s8, s7
2:  bleu    s2, s8, 3f
    sub     t0, s2, s8                      # balance_to_process
    addi    t0, t0, -1
    divu    t0, t0, s7
    addi    t0, t0, 1                       # additional_epochs
    add     t1, s6, t0
    bltu    t1, s6, 6f
    mv      s6, t1
    mul     t1, t0, s7                      # additional_epochs * per_epoch_churn, checked
    mulhu   t2, t0, s7
    bnez    t2, 6f
    add     t2, s8, t1
    bltu    t2, s8, 6f
    mv      s8, t2
3:  sub     s8, s8, s2
    STQ     s8, s1, BeaconState_exit_balance_to_consume
    STQ     s6, s1, BeaconState_earliest_exit_epoch
    sd      s6, 0(s5)
    li      a0, LANTERN_OK
7:  LEAVE 32
6:  li      t0, LANTERN_INVALID_OVERFLOW
    sd      t0, 0(s9)
    li      a0, LANTERN_OK
    LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION lantern_compute_exit_epoch_and_update_churn

FUNCTION lantern_get_balance_churn_limit
    FRAME 32
    sd      a1, 0(sp)                       # config
    sd      a3, 8(sp)                       # out
    mv      a1, a2
    addi    a2, sp, 16
    call    lantern_get_total_active_balance
    bnez    a0, 1f
    ld      a1, 0(sp)
    ld      a3, 8(sp)
    ld      t0, 16(sp)
    ld      t1, CONFIG_CHURN_LIMIT_QUOTIENT(a1)
    divu    t0, t0, t1
    ld      t1, CONFIG_MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA(a1)
    bgtu    t0, t1, 2f                      # churn = max(MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA, total // quotient)
    mv      t0, t1
2:  li      t1, EFFECTIVE_BALANCE_INCREMENT
    divu    t2, t0, t1
    mul     t0, t2, t1                      # churn - churn % EFFECTIVE_BALANCE_INCREMENT
    sd      t0, 0(a3)
    li      a0, LANTERN_OK
1:  UNFRAME 32
END_FUNCTION lantern_get_balance_churn_limit

FUNCTION lantern_get_activation_exit_churn_limit
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a3, 16(sp)
    addi    a3, sp, 24
    call    lantern_get_balance_churn_limit
    bnez    a0, 1f
    ld      a1, 8(sp)
    ld      t0, 24(sp)
    ld      t1, CONFIG_MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT(a1)
    bltu    t0, t1, 2f
    mv      t0, t1
2:  ld      a3, 16(sp)
    sd      t0, 0(a3)
    li      a0, LANTERN_OK
1:  UNFRAME 32
END_FUNCTION lantern_get_activation_exit_churn_limit

FUNCTION lantern_get_consolidation_churn_limit
    FRAME 48
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    sd      a3, 24(sp)
    addi    a3, sp, 32
    call    lantern_get_balance_churn_limit
    bnez    a0, 1f
    ld      a0, 0(sp)
    ld      a1, 8(sp)
    ld      a2, 16(sp)
    addi    a3, sp, 40
    call    lantern_get_activation_exit_churn_limit
    bnez    a0, 1f
    ld      t0, 32(sp)
    ld      t1, 40(sp)
    sub     t0, t0, t1
    ld      a3, 24(sp)
    sd      t0, 0(a3)
    li      a0, LANTERN_OK
1:  UNFRAME 48
END_FUNCTION lantern_get_consolidation_churn_limit

/* ---------------------------------------------------------------- Slashings */

/*
 * s1 state, s2 config, s3 scratch, s4 result, s5 epoch, s6 penalty per increment,
 * s7 index, s8 validator count. Locals: L epoch, L+8 total balance, L+16 index, L+24 penalty.
 */
FUNCTION lantern_process_slashings
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH s3, s1, 1, 9f
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      s5, L(sp)
    mv      a0, s1
    mv      a1, s3
    addi    a2, sp, (L + 8)
    call    lantern_get_total_active_balance
    bnez    a0, 7f
    ADDQ    t0, s1, BeaconState_slashings   # sum(state.slashings)
    li      t1, EPOCHS_PER_SLASHINGS_VECTOR
    li      t2, 0
1:  ld      t3, 0(t0)
    addi    t0, t0, 8
    add     t2, t2, t3
    addi    t1, t1, -1
    bnez    t1, 1b
    li      t3, PROPORTIONAL_SLASHING_MULTIPLIER_BELLATRIX
    mul     t2, t2, t3
    ld      t3, (L + 8)(sp)
    bltu    t2, t3, 11f                     # adjusted_total_slashing_balance
    mv      t2, t3
11: li      t4, EFFECTIVE_BALANCE_INCREMENT
    divu    t3, t3, t4
    divu    s6, t2, t3                      # penalty_per_effective_balance_increment
    LDQ     s8, s1, BeaconState_validators + 8
    li      s7, 0
2:  bgeu    s7, s8, 8f
    PART    t0, t1, s1, BeaconState_validators
    slli    t1, s7, 7
    add     t0, t0, t1
    lbu     t1, Validator_slashed(t0)
    beqz    t1, 3f
    li      t1, EPOCHS_PER_SLASHINGS_VECTOR / 2
    add     t1, s5, t1
    ld      t2, Validator_withdrawable_epoch(t0)
    bne     t1, t2, 3f
    ld      t1, Validator_effective_balance(t0)
    li      t4, EFFECTIVE_BALANCE_INCREMENT
    divu    t1, t1, t4
    mul     t1, s6, t1
    sd      t1, (L + 24)(sp)
    sd      s7, (L + 16)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 16)
    addi    a2, sp, (L + 24)
    call    lantern_decrease_balance
3:  addi    s7, s7, 1
    j       2b
8:  sd      zero, 0(s4)
    li      a0, LANTERN_OK
7:  LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION lantern_process_slashings

/* ---------------------------------------------------------------- Eth1 data, consolidations */

FUNCTION lantern_process_eth1_data_reset
    FRAME 32
    sd      a0, 0(sp)
    sd      a3, 8(sp)
    addi    a1, sp, 16
    call    lantern_get_current_epoch
    ld      a0, 0(sp)
    ld      a3, 8(sp)
    ld      t0, 16(sp)
    addi    t0, t0, 1                       # next_epoch % EPOCHS_PER_ETH1_VOTING_PERIOD == 0
    li      t1, EPOCHS_PER_ETH1_VOTING_PERIOD
    remu    t2, t0, t1
    bnez    t2, 1f
    STQ     zero, a0, BeaconState_eth1_data_votes + 8
1:  sd      zero, 0(a3)
    li      a0, LANTERN_OK
    UNFRAME 32
END_FUNCTION lantern_process_eth1_data_reset

/*
 * s1 state, s2 result, s3 next epoch, s4 consolidation, s5 consolidations left, s6 processed.
 * Locals: L epoch, L+8 source index, L+16 target index, L+24 balance.
 */
FUNCTION lantern_process_pending_consolidations
    ENTER 32
    mv      s1, a0
    mv      s2, a3
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      s3, L(sp)
    addi    s3, s3, 1
    PART    s4, s5, s1, BeaconState_pending_consolidations
    li      s6, 0
1:  beqz    s5, 4f
    ld      t0, PendingConsolidation_source_index(s4)
    PART    t1, t2, s1, BeaconState_validators
    slli    t2, t0, 7
    add     t1, t1, t2                      # source_validator
    lbu     t2, Validator_slashed(t1)
    bnez    t2, 3f
    ld      t2, Validator_withdrawable_epoch(t1)
    bgtu    t2, s3, 4f
    PART    t3, t4, s1, BeaconState_balances
    slli    t4, t0, 3
    add     t3, t3, t4
    ld      t3, 0(t3)
    ld      t2, Validator_effective_balance(t1)
    bltu    t3, t2, 2f                      # source_effective_balance
    mv      t3, t2
2:  sd      t3, (L + 24)(sp)
    sd      t0, (L + 8)(sp)
    ld      t0, PendingConsolidation_target_index(s4)
    sd      t0, (L + 16)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 8)
    addi    a2, sp, (L + 24)
    call    lantern_decrease_balance
    mv      a0, s1
    addi    a1, sp, (L + 16)
    addi    a2, sp, (L + 24)
    call    lantern_increase_balance
3:  addi    s6, s6, 1
    addi    s4, s4, PendingConsolidation__mem
    addi    s5, s5, -1
    j       1b
4:  beqz    s6, 5f                          # pending_consolidations = pending_consolidations[processed:]
    PART    a0, t0, s1, BeaconState_pending_consolidations
    sub     t0, t0, s6
    STQ     t0, s1, BeaconState_pending_consolidations + 8
    slli    t1, s6, 4                       # PendingConsolidation__mem is 16
    add     a1, a0, t1
    slli    a2, t0, 4
    call    lantern_copy
5:  sd      zero, 0(s2)
    li      a0, LANTERN_OK
    LEAVE 32
END_FUNCTION lantern_process_pending_consolidations

/* ---------------------------------------------------------------- Effective balances */

/* s1 state, s2 result, s3 validator, s4 index, s5 validator count. Locals: L max effective balance. */
FUNCTION lantern_process_effective_balance_updates
    ENTER 16
    mv      s1, a0
    mv      s2, a3
    LDQ     s5, s1, BeaconState_validators + 8
    li      s4, 0
1:  bgeu    s4, s5, 3f
    PART    s3, t0, s1, BeaconState_validators
    slli    t0, s4, 7
    add     s3, s3, t0
    mv      a0, s3
    addi    a1, sp, L
    call    lantern_get_max_effective_balance
    PART    t0, t1, s1, BeaconState_balances
    slli    t1, s4, 3
    add     t0, t0, t1
    ld      t0, 0(t0)                       # balance
    ld      t1, Validator_effective_balance(s3)
    li      t2, (EFFECTIVE_BALANCE_INCREMENT / HYSTERESIS_QUOTIENT) * HYSTERESIS_DOWNWARD_MULTIPLIER
    add     t2, t0, t2
    bltu    t2, t1, 2f                      # balance + DOWNWARD_THRESHOLD < effective_balance
    li      t2, (EFFECTIVE_BALANCE_INCREMENT / HYSTERESIS_QUOTIENT) * HYSTERESIS_UPWARD_MULTIPLIER
    add     t2, t1, t2
    bgeu    t2, t0, 25f                     # or effective_balance + UPWARD_THRESHOLD < balance
2:  li      t3, EFFECTIVE_BALANCE_INCREMENT
    divu    t4, t0, t3
    mul     t4, t4, t3                      # balance - balance % EFFECTIVE_BALANCE_INCREMENT
    ld      t3, L(sp)
    bltu    t4, t3, 21f
    mv      t4, t3
21: sd      t4, Validator_effective_balance(s3)
25: addi    s4, s4, 1
    j       1b
3:  sd      zero, 0(s2)
    li      a0, LANTERN_OK
    LEAVE 16
END_FUNCTION lantern_process_effective_balance_updates

/* ---------------------------------------------------------------- Resets and rotations */

FUNCTION lantern_process_slashings_reset
    FRAME 32
    sd      a0, 0(sp)
    sd      a3, 8(sp)
    addi    a1, sp, 16
    call    lantern_get_current_epoch
    ld      a0, 0(sp)
    ld      a3, 8(sp)
    ld      t0, 16(sp)
    addi    t0, t0, 1
    li      t1, (EPOCHS_PER_SLASHINGS_VECTOR - 1)
    and     t0, t0, t1
    ADDQ    t1, a0, BeaconState_slashings
    slli    t0, t0, 3
    add     t1, t1, t0
    sd      zero, 0(t1)
    sd      zero, 0(a3)
    li      a0, LANTERN_OK
    UNFRAME 32
END_FUNCTION lantern_process_slashings_reset

FUNCTION lantern_process_randao_mixes_reset
    FRAME 32
    sd      a0, 0(sp)
    sd      a3, 8(sp)
    addi    a1, sp, 16
    call    lantern_get_current_epoch
    ld      a0, 0(sp)
    ld      t0, 16(sp)
    addi    t0, t0, 1                       # randao_mixes[next % EPOCHS_PER_HISTORICAL_VECTOR]
    li      t1, (EPOCHS_PER_HISTORICAL_VECTOR - 1)
    and     t0, t0, t1
    ADDQ    a2, a0, BeaconState_randao_mixes
    slli    t0, t0, 5
    add     a2, a2, t0
    addi    a1, sp, 16
    call    lantern_get_randao_mix
    ld      a3, 8(sp)
    sd      zero, 0(a3)
    li      a0, LANTERN_OK
    UNFRAME 32
END_FUNCTION lantern_process_randao_mixes_reset

/* s1 state, s2 scratch, s3 result, s4 the new summary. Locals: L epoch. */
FUNCTION lantern_process_historical_summaries_update
    ENTER 16
    mv      s1, a0
    mv      s2, a2
    mv      s3, a3
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, L(sp)
    addi    t0, t0, 1
    li      t1, (SLOTS_PER_HISTORICAL_ROOT / SLOTS_PER_EPOCH - 1)
    and     t0, t0, t1
    bnez    t0, 8f
    ld      t0, 0(s2)                       # scratch for the roots
    li      t1, SSZ_SCR_WORK + BlockRoots__work
    bltu    t0, t1, 9f
    LDQ     t0, s1, BeaconState_historical_summaries
    LDQ     t1, s1, BeaconState_historical_summaries + 8
    LDQ     t2, s1, BeaconState_pending_deposits        # the next part starts its room's end
    sub     t2, t2, t0
    addi    t3, t1, 1
    slli    t3, t3, 6                       # HistoricalSummary__mem is 64
    bltu    t2, t3, 9f
    add     s4, s1, t0
    slli    t1, t1, 6
    add     s4, s4, t1
    ADDRESS a0, lantern_type_BlockRoots     # block_summary_root = hash_tree_root(state.block_roots)
    ADDQ    a1, s1, BeaconState_block_roots
    mv      a2, s2
    addi    a3, s4, HistoricalSummary_block_summary_root
    CALL_GLOBAL ssz_hash_tree_root
    ADDRESS a0, lantern_type_BlockRoots     # state_summary_root = hash_tree_root(state.state_roots)
    ADDQ    a1, s1, BeaconState_state_roots
    mv      a2, s2
    addi    a3, s4, HistoricalSummary_state_summary_root
    CALL_GLOBAL ssz_hash_tree_root
    LDQ     t1, s1, BeaconState_historical_summaries + 8
    addi    t1, t1, 1
    STQ     t1, s1, BeaconState_historical_summaries + 8
8:  sd      zero, 0(s3)
    li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_process_historical_summaries_update

/* s1 state, s2 result. previous_epoch_participation = current; current = zeros, one per validator. */
FUNCTION lantern_process_participation_flag_updates
    ENTER 16
    mv      s1, a0
    mv      s2, a3
    PART    a1, t0, s1, BeaconState_current_epoch_participation
    PART    a0, t1, s1, BeaconState_previous_epoch_participation
    STQ     t0, s1, BeaconState_previous_epoch_participation + 8
    mv      a2, t0
    call    lantern_copy
    LDQ     t0, s1, BeaconState_validators + 8
    STQ     t0, s1, BeaconState_current_epoch_participation + 8
    PART    a0, t1, s1, BeaconState_current_epoch_participation
    mv      a1, t0
    call    lantern_zero
    sd      zero, 0(s2)
    li      a0, LANTERN_OK
    LEAVE 16
END_FUNCTION lantern_process_participation_flag_updates

/* ---------------------------------------------------------------- Proposer lookahead */

.set LOOKAHEAD_LOCALS, (8 * SLOTS_PER_EPOCH + 8 + 15) / 16 * 16

/* s1 state, s2 config, s3 scratch, s4 result. Locals: L the last epoch's proposers, then the epoch. */
FUNCTION lantern_process_proposer_lookahead
    ENTER LOOKAHEAD_LOCALS
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH s3, s1, 2, 9f
    sd      zero, 0(s4)
    mv      a0, s1
    addi    a1, sp, (L + 8 * SLOTS_PER_EPOCH)
    call    lantern_get_current_epoch
    ld      t0, (L + 8 * SLOTS_PER_EPOCH)(sp)
    addi    t0, t0, (MIN_SEED_LOOKAHEAD + 1)
    sd      t0, (L + 8 * SLOTS_PER_EPOCH)(sp)
    mv      a0, s1                          # get_beacon_proposer_indices(state, current + MIN_SEED_LOOKAHEAD + 1)
    addi    a1, sp, (L + 8 * SLOTS_PER_EPOCH)
    mv      a2, s3
    addi    a3, sp, L
    call    lantern_get_beacon_proposer_indices
    CHECK_STATUS s4, 7f, 8f
    ADDQ    a0, s1, BeaconState_proposer_lookahead
    ADDQ    a1, s1, BeaconState_proposer_lookahead + 8 * SLOTS_PER_EPOCH
    li      a2, 8 * SLOTS_PER_EPOCH * MIN_SEED_LOOKAHEAD
    call    lantern_copy
    ADDQ    a0, s1, BeaconState_proposer_lookahead + 8 * SLOTS_PER_EPOCH * MIN_SEED_LOOKAHEAD
    addi    a1, sp, L
    li      a2, 8 * SLOTS_PER_EPOCH
    call    lantern_copy
8:  li      a0, LANTERN_OK
7:  LEAVE LOOKAHEAD_LOCALS
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE LOOKAHEAD_LOCALS
END_FUNCTION lantern_process_proposer_lookahead

/* ---------------------------------------------------------------- The epoch */

.set EPOCH_EXTRA, SYNC_COMMITTEE_SCRATCH + SyncCommittee__mem + POSTPONE_BYTES

/* One step: stop at a failed status or a failed check. s1-s4 hold the arguments, s5 the scratch size. */
.macro EPOCH_STEP fn
    sd      s5, 0(s3)
    mv      a0, s1
    mv      a1, s2
    mv      a2, s3
    mv      a3, s4
    call    \fn
    bnez    a0, 7f
    ld      t0, 0(s4)
    bnez    t0, 8f
.endm

/* s1 state, s2 config, s3 scratch, s4 result, s5 scratch size. Locals: L epoch. */
FUNCTION lantern_process_epoch
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH_B s3, s1, 11, EPOCH_EXTRA, 9f
    mv      a0, s1                          # room for the deposits of the epoch
    call    validator_room
    li      t0, MAX_PENDING_DEPOSITS_PER_EPOCH
    bltu    a0, t0, 9f
    mv      a0, s1                          # and for a historical summary when one is due
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, L(sp)
    addi    t0, t0, 1
    li      t1, (SLOTS_PER_HISTORICAL_ROOT / SLOTS_PER_EPOCH - 1)
    and     t0, t0, t1
    bnez    t0, 1f
    LDQ     t0, s1, BeaconState_historical_summaries
    LDQ     t1, s1, BeaconState_historical_summaries + 8
    LDQ     t2, s1, BeaconState_pending_deposits
    sub     t2, t2, t0
    addi    t3, t1, 1
    slli    t3, t3, 6
    bltu    t2, t3, 9f
1:  ld      s5, 0(s3)
    EPOCH_STEP lantern_process_justification_and_finalization
    EPOCH_STEP lantern_process_inactivity_updates
    EPOCH_STEP lantern_process_rewards_and_penalties
    EPOCH_STEP lantern_process_registry_updates
    EPOCH_STEP lantern_process_slashings
    EPOCH_STEP lantern_process_eth1_data_reset
    EPOCH_STEP lantern_process_pending_deposits
    EPOCH_STEP lantern_process_pending_consolidations
    EPOCH_STEP lantern_process_effective_balance_updates
    EPOCH_STEP lantern_process_slashings_reset
    EPOCH_STEP lantern_process_randao_mixes_reset
    EPOCH_STEP lantern_process_historical_summaries_update
    EPOCH_STEP lantern_process_participation_flag_updates
    EPOCH_STEP lantern_process_sync_committee_updates
    EPOCH_STEP lantern_process_proposer_lookahead
8:  li      a0, LANTERN_OK
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_process_epoch

.if PendingConsolidation__mem != 16
.error "lantern_process_pending_consolidations shifts by 4 for PendingConsolidation"
.endif

.if HistoricalSummary__mem != 64
.error "lantern_process_historical_summaries_update shifts by 6 for HistoricalSummary"
.endif
