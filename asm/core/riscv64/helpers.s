/*
 * Beacon chain helpers, RISC-V. Requirements: docs/reference/helpers.md.
 * v1: each function follows its spec steps and calls the spec functions it names.
 */

/* ---------------------------------------------------------------- Math */

LEAF lantern_integer_squareroot
    ld      a2, 0(a0)                       # n
    li      a3, -1
    bne     a2, a3, 1f
    li      a3, UINT64_MAX_SQRT             # n == UINT64_MAX
    sd      a3, 0(a1)
    RETURN_OK
1:  mv      a3, a2                          # x = n
    addi    a4, a2, 1
    srli    a4, a4, 1                       # y = (x + 1) // 2
2:  bgeu    a4, a3, 3f                      # while y < x
    mv      a3, a4                          # x = y; x >= 1 here
    divu    a5, a2, a3
    add     a5, a3, a5
    srli    a4, a5, 1                       # y = (x + n // x) // 2
    j       2b
3:  sd      a3, 0(a1)
    RETURN_OK
END_FUNCTION lantern_integer_squareroot

LEAF lantern_saturating_sub
    ld      a3, 0(a0)
    ld      a4, 0(a1)
    li      a5, 0
    bleu    a3, a4, 1f                      # a > b ? a - b : 0
    sub     a5, a3, a4
1:  sd      a5, 0(a2)
    RETURN_OK
END_FUNCTION lantern_saturating_sub

/* ---------------------------------------------------------------- Predicates */

LEAF lantern_is_active_validator
    ld      a3, 0(a1)                       # epoch
    ld      a4, Validator_activation_epoch(a0)
    ld      a5, Validator_exit_epoch(a0)
    li      a6, 0
    bltu    a3, a4, 1f                      # activation_epoch <= epoch
    sltu    a6, a3, a5                      # and epoch < exit_epoch
1:  sd      a6, 0(a2)
    RETURN_OK
END_FUNCTION lantern_is_active_validator

LEAF lantern_is_eligible_for_activation_queue
    ld      a2, Validator_activation_eligibility_epoch(a0)
    ld      a3, Validator_effective_balance(a0)
    li      a4, MIN_ACTIVATION_BALANCE
    li      a5, 0
    li      a6, -1
    bne     a2, a6, 1f                      # activation_eligibility_epoch == FAR_FUTURE_EPOCH
    bltu    a3, a4, 1f                      # and effective_balance >= MIN_ACTIVATION_BALANCE
    li      a5, 1
1:  sd      a5, 0(a1)
    RETURN_OK
END_FUNCTION lantern_is_eligible_for_activation_queue

LEAF lantern_is_eligible_for_activation
    LDQ     a3, a0, BeaconState_finalized_checkpoint + Checkpoint_epoch
    ld      a4, Validator_activation_eligibility_epoch(a1)
    ld      a5, Validator_activation_epoch(a1)
    li      a6, 0
    bltu    a3, a4, 1f                      # activation_eligibility_epoch <= finalized epoch
    addi    a5, a5, 1
    seqz    a6, a5                          # and activation_epoch == FAR_FUTURE_EPOCH
1:  sd      a6, 0(a2)
    RETURN_OK
END_FUNCTION lantern_is_eligible_for_activation

LEAF lantern_is_slashable_validator
    ld      a3, 0(a1)                       # epoch
    lbu     a4, Validator_slashed(a0)
    ld      a5, Validator_activation_epoch(a0)
    ld      a6, Validator_withdrawable_epoch(a0)
    li      t0, 0
    bnez    a4, 1f                          # not slashed
    bltu    a3, a5, 1f                      # and activation_epoch <= epoch
    sltu    t0, a3, a6                      # and epoch < withdrawable_epoch
1:  sd      t0, 0(a2)
    RETURN_OK
END_FUNCTION lantern_is_slashable_validator

LEAF lantern_is_compounding_withdrawal_credential
    lbu     a2, 0(a0)
    addi    a2, a2, -COMPOUNDING_WITHDRAWAL_PREFIX
    seqz    a2, a2
    sd      a2, 0(a1)
    RETURN_OK
END_FUNCTION lantern_is_compounding_withdrawal_credential

FUNCTION lantern_has_compounding_withdrawal_credential
    FRAME 0
    addi    a0, a0, Validator_withdrawal_credentials
    call    lantern_is_compounding_withdrawal_credential
    UNFRAME 0
END_FUNCTION lantern_has_compounding_withdrawal_credential

FUNCTION lantern_get_max_effective_balance
    FRAME 16
    sd      a1, 0(sp)                       # out
    addi    a1, sp, 8
    call    lantern_has_compounding_withdrawal_credential
    ld      a2, 8(sp)
    li      a3, MAX_EFFECTIVE_BALANCE_ELECTRA
    bnez    a2, 1f
    li      a3, MIN_ACTIVATION_BALANCE
1:  ld      a1, 0(sp)
    sd      a3, 0(a1)
    li      a0, LANTERN_OK
    UNFRAME 16
END_FUNCTION lantern_get_max_effective_balance

/* ---------------------------------------------------------------- Misc */

LEAF lantern_compute_epoch_at_slot
    ld      a2, 0(a0)
    srli    a2, a2, LOG2_SLOTS_PER_EPOCH
    sd      a2, 0(a1)
    RETURN_OK
END_FUNCTION lantern_compute_epoch_at_slot

LEAF lantern_compute_start_slot_at_epoch
    ld      a2, 0(a0)
    srli    a3, a2, (64 - LOG2_SLOTS_PER_EPOCH)
    bnez    a3, 1f                          # epoch * SLOTS_PER_EPOCH leaves the Uint64 range
    slli    a2, a2, LOG2_SLOTS_PER_EPOCH
    sd      a2, 0(a1)
    RETURN_OK
1:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_compute_start_slot_at_epoch

LEAF lantern_compute_activation_exit_epoch
    ld      a2, 0(a0)
    addi    a3, a2, (1 + MAX_SEED_LOOKAHEAD)
    bltu    a3, a2, 1f
    sd      a3, 0(a1)
    RETURN_OK
1:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_compute_activation_exit_epoch

/* ---------------------------------------------------------------- Accessors */

FUNCTION lantern_get_current_epoch
    FRAME 0
    ADDQ    a0, a0, BeaconState_slot
    call    lantern_compute_epoch_at_slot
    UNFRAME 0
END_FUNCTION lantern_get_current_epoch

FUNCTION lantern_get_previous_epoch
    FRAME 32
    sd      a1, 0(sp)                       # out
    addi    a1, sp, 8
    call    lantern_get_current_epoch
    li      t0, 1
    sd      t0, 16(sp)
    addi    a0, sp, 8                       # saturating_sub(current, 1)
    addi    a1, sp, 16
    ld      a2, 0(sp)
    call    lantern_saturating_sub
    UNFRAME 32
END_FUNCTION lantern_get_previous_epoch

LEAF lantern_get_block_root_at_slot
    ld      a4, 0(a1)                       # slot
    LDQ     a5, a0, BeaconState_slot
    bgeu    a4, a5, 1f                      # slot < state.slot
    sub     a6, a5, a4                      # state.slot <= slot + SLOTS_PER_HISTORICAL_ROOT
    li      a3, SLOTS_PER_HISTORICAL_ROOT
    bgtu    a6, a3, 1f
    li      a3, (SLOTS_PER_HISTORICAL_ROOT - 1)
    and     a4, a4, a3
    ADDQ    a5, a0, BeaconState_block_roots
    slli    a4, a4, 5
    add     a5, a5, a4
    COPY32  a2, a5
    RETURN_OK
1:  li      a0, LANTERN_INVALID_BLOCK_ROOT_SLOT
    ret
END_FUNCTION lantern_get_block_root_at_slot

FUNCTION lantern_get_block_root
    FRAME 32
    sd      a0, 0(sp)                       # state
    sd      a2, 8(sp)                       # out
    mv      a0, a1
    addi    a1, sp, 16
    call    lantern_compute_start_slot_at_epoch
    bnez    a0, 1f
    ld      a0, 0(sp)
    addi    a1, sp, 16
    ld      a2, 8(sp)
    call    lantern_get_block_root_at_slot
1:  UNFRAME 32
END_FUNCTION lantern_get_block_root

LEAF lantern_get_randao_mix
    ld      a3, 0(a1)
    li      a4, (EPOCHS_PER_HISTORICAL_VECTOR - 1)
    and     a3, a3, a4
    ADDQ    a4, a0, BeaconState_randao_mixes
    slli    a3, a3, 5
    add     a4, a4, a3
    COPY32  a2, a4
    RETURN_OK
END_FUNCTION lantern_get_randao_mix

/*
 * s1 state, s2 epoch, s3 out, s4 validator, s5 validators left, s6 index, s7 out entries;
 * locals: the is_active_validator result.
 */
FUNCTION lantern_get_active_validator_indices
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    PART    s4, s5, s1, BeaconState_validators
    ld      t0, LIST_SIZE(s3)               # room for every validator
    slli    t1, s5, 3
    addi    t1, t1, LIST_FIXED
    bltu    t0, t1, 9f
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s3)
    addi    s7, s3, LIST_FIXED
    li      s6, 0
1:  beqz    s5, 3f
    mv      a0, s4
    mv      a1, s2
    addi    a2, sp, L
    call    lantern_is_active_validator
    ld      t0, L(sp)
    beqz    t0, 2f
    sd      s6, 0(s7)
    addi    s7, s7, 8
2:  addi    s4, s4, Validator__mem
    addi    s6, s6, 1
    addi    s5, s5, -1
    j       1b
3:  addi    t0, s3, LIST_FIXED
    sub     t0, s7, t0
    srli    t0, t0, 3
    sd      t0, LIST_COUNT(s3)
    li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_get_active_validator_indices

LEAF lantern_get_total_balance
    PART    a3, a4, a0, BeaconState_validators
    ld      a5, LIST_COUNT(a1)
    addi    a6, a1, LIST_FIXED
    li      t0, 0                           # sum
1:  beqz    a5, 2f
    ld      t1, 0(a6)
    addi    a6, a6, 8
    slli    t1, t1, 7                       # Validator__mem is 128
    add     t1, a3, t1
    ld      t1, Validator_effective_balance(t1)
    add     t0, t0, t1
    addi    a5, a5, -1
    j       1b
2:  li      t1, EFFECTIVE_BALANCE_INCREMENT
    bgtu    t0, t1, 3f                      # max(EFFECTIVE_BALANCE_INCREMENT, sum)
    mv      t0, t1
3:  sd      t0, 0(a2)
    RETURN_OK
END_FUNCTION lantern_get_total_balance

/* s1 state, s2 scratch, s3 out; locals: the epoch. The index list is the scratch after its size. */
FUNCTION lantern_get_total_active_balance
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, 0(s2)                       # the list takes all of scratch but its size field
    addi    t0, t0, -8
    sd      t0, 8(s2)
    mv      a0, s1
    addi    a1, sp, L
    addi    a2, s2, 8
    call    lantern_get_active_validator_indices
    bnez    a0, 9f
    mv      a0, s1
    addi    a1, s2, 8
    mv      a2, s3
    call    lantern_get_total_balance
9:  LEAVE 16
END_FUNCTION lantern_get_total_active_balance

/* ---------------------------------------------------------------- Mutators */

LEAF lantern_increase_balance
    ld      a3, 0(a1)                       # index
    ld      a4, 0(a2)                       # delta
    PART    a5, a6, a0, BeaconState_balances
    slli    a3, a3, 3
    add     a5, a5, a3
    ld      a6, 0(a5)
    add     a6, a6, a4
    sd      a6, 0(a5)
    RETURN_OK
END_FUNCTION lantern_increase_balance

FUNCTION lantern_decrease_balance
    FRAME 0
    ld      a3, 0(a1)                       # index
    PART    a4, a5, a0, BeaconState_balances
    slli    a3, a3, 3
    add     a0, a4, a3                      # balances[index] = saturating_sub(balances[index], delta)
    mv      a1, a2
    mv      a2, a0
    call    lantern_saturating_sub
    UNFRAME 0
END_FUNCTION lantern_decrease_balance

/* ---------------------------------------------------------------- Participation flags and rewards */

LEAF lantern_has_flag
    lbu     a3, 0(a0)
    ld      a4, 0(a1)
    srl     a3, a3, a4
    andi    a3, a3, 1
    sd      a3, 0(a2)
    RETURN_OK
END_FUNCTION lantern_has_flag

LEAF lantern_add_flag
    lbu     a3, 0(a0)
    ld      a4, 0(a1)
    li      a5, 1
    sll     a5, a5, a4
    or      a3, a3, a5
    sb      a3, 0(a2)
    RETURN_OK
END_FUNCTION lantern_add_flag

FUNCTION lantern_get_finality_delay
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    addi    a1, sp, 16
    call    lantern_get_previous_epoch
    ld      a0, 0(sp)
    ld      a1, 8(sp)
    ld      a2, 16(sp)
    LDQ     a3, a0, BeaconState_finalized_checkpoint + Checkpoint_epoch
    sub     a2, a2, a3
    sd      a2, 0(a1)
    li      a0, LANTERN_OK
    UNFRAME 32
END_FUNCTION lantern_get_finality_delay

FUNCTION lantern_is_in_inactivity_leak
    FRAME 16
    sd      a1, 0(sp)
    addi    a1, sp, 8
    call    lantern_get_finality_delay
    ld      a2, 8(sp)
    li      a3, MIN_EPOCHS_TO_INACTIVITY_PENALTY
    sltu    a2, a3, a2
    ld      a1, 0(sp)
    sd      a2, 0(a1)
    li      a0, LANTERN_OK
    UNFRAME 16
END_FUNCTION lantern_is_in_inactivity_leak

/*
 * s1 state, s2 out, s3 validator, s4 validators left, s5 index, s6 out entries,
 * s7 previous epoch; locals: previous epoch at L, is_active_validator result at L + 8.
 */
FUNCTION lantern_get_eligible_validator_indices
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    PART    s3, s4, s1, BeaconState_validators
    ld      t0, LIST_SIZE(s2)
    slli    t1, s4, 3
    addi    t1, t1, LIST_FIXED
    bltu    t0, t1, 9f
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_previous_epoch
    ld      s7, L(sp)
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s2)
    addi    s6, s2, LIST_FIXED
    li      s5, 0
1:  beqz    s4, 4f
    mv      a0, s3
    addi    a1, sp, L
    addi    a2, sp, (L + 8)
    call    lantern_is_active_validator
    ld      t0, (L + 8)(sp)
    bnez    t0, 2f
    lbu     t0, Validator_slashed(s3)       # or slashed and previous_epoch + 1 < withdrawable_epoch
    beqz    t0, 3f
    ld      t1, Validator_withdrawable_epoch(s3)
    addi    t2, s7, 1
    bgeu    t2, t1, 3f
2:  sd      s5, 0(s6)
    addi    s6, s6, 8
3:  addi    s3, s3, Validator__mem
    addi    s5, s5, 1
    addi    s4, s4, -1
    j       1b
4:  addi    t0, s2, LIST_FIXED
    sub     t0, s6, t0
    srli    t0, t0, 3
    sd      t0, LIST_COUNT(s2)
    li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_get_eligible_validator_indices

/*
 * s1 state, s2 flag_index, s3 epoch, s4 scratch, s5 out,
 * s7 epoch_participation, s8 active list entries, s9 entries left, s10 out entries.
 * Locals: previous epoch at L, current epoch at L + 8, has_flag result at L + 16, index at L + 24.
 */
FUNCTION lantern_get_unslashed_participating_indices
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    PART    t0, t1, s1, BeaconState_validators
    ld      t2, LIST_SIZE(s5)               # out and scratch need room for every validator
    slli    t3, t1, 3
    addi    t3, t3, LIST_FIXED
    bltu    t2, t3, 9f
    ld      t2, 0(s4)
    addi    t3, t3, 8
    bltu    t2, t3, 9f
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_previous_epoch
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_get_current_epoch
    ld      t0, 0(s3)
    ld      t1, L(sp)                       # previous
    ld      t2, (L + 8)(sp)                 # current
    beq     t0, t2, 1f                      # assert epoch in (previous, current)
    beq     t0, t1, 2f
    li      a0, LANTERN_INVALID_PARTICIPATION_EPOCH
    LEAVE 32
1:  PART    s7, t0, s1, BeaconState_current_epoch_participation
    j       3f
2:  PART    s7, t0, s1, BeaconState_previous_epoch_participation
3:  ld      t0, 0(s4)                       # active_validator_indices: the scratch after its size
    addi    t0, t0, -8
    sd      t0, 8(s4)
    mv      a0, s1
    mv      a1, s3
    addi    a2, s4, 8
    call    lantern_get_active_validator_indices
    bnez    a0, 8f
    ld      s9, (8 + LIST_COUNT)(s4)
    addi    s8, s4, (8 + LIST_FIXED)
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s5)
    addi    s10, s5, LIST_FIXED
4:  beqz    s9, 6f
    ld      t0, 0(s8)                       # index
    addi    s8, s8, 8
    sd      t0, (L + 24)(sp)
    add     a0, s7, t0
    mv      a1, s2
    addi    a2, sp, (L + 16)
    call    lantern_has_flag
    ld      t0, (L + 16)(sp)
    beqz    t0, 5f
    ld      t0, (L + 24)(sp)                # and not state.validators[index].slashed
    PART    t1, t2, s1, BeaconState_validators
    slli    t2, t0, 7
    add     t1, t1, t2
    lbu     t1, Validator_slashed(t1)
    bnez    t1, 5f
    sd      t0, 0(s10)
    addi    s10, s10, 8
5:  addi    s9, s9, -1
    j       4b
6:  addi    t0, s5, LIST_FIXED
    sub     t0, s10, t0
    srli    t0, t0, 3
    sd      t0, LIST_COUNT(s5)
    li      a0, LANTERN_OK
8:  LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION lantern_get_unslashed_participating_indices

FUNCTION lantern_get_base_reward_per_increment
    FRAME 32
    sd      a2, 0(sp)                       # out
    addi    a2, sp, 8
    call    lantern_get_total_active_balance
    bnez    a0, 1f
    addi    a0, sp, 8
    addi    a1, sp, 16
    call    lantern_integer_squareroot
    ld      t0, 16(sp)
    li      t1, EFFECTIVE_BALANCE_INCREMENT * BASE_REWARD_FACTOR
    divu    t1, t1, t0
    ld      t2, 0(sp)
    sd      t1, 0(t2)
    li      a0, LANTERN_OK
1:  UNFRAME 32
END_FUNCTION lantern_get_base_reward_per_increment

FUNCTION lantern_get_base_reward
    FRAME 32
    sd      a0, 0(sp)                       # state
    sd      a1, 8(sp)                       # index
    sd      a3, 16(sp)                      # out
    mv      a1, a2
    addi    a2, sp, 24
    call    lantern_get_base_reward_per_increment
    bnez    a0, 1f
    ld      a0, 0(sp)
    ld      a1, 8(sp)
    ld      a1, 0(a1)
    PART    t0, t1, a0, BeaconState_validators
    slli    a1, a1, 7
    add     t0, t0, a1
    ld      t0, Validator_effective_balance(t0)
    li      t1, EFFECTIVE_BALANCE_INCREMENT
    divu    t0, t0, t1                      # increments
    ld      t2, 24(sp)
    mul     t0, t0, t2
    ld      t3, 16(sp)
    sd      t0, 0(t3)
    li      a0, LANTERN_OK
1:  UNFRAME 32
END_FUNCTION lantern_get_base_reward
