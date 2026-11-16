/*
 * Withdrawals, RISC-V. Requirements: docs/reference/block-processing.md.
 */

.set WLIST_BYTES, LIST_FIXED + MAX_WITHDRAWALS_PER_PAYLOAD * Withdrawal__mem   /* a Withdrawals value */
.set SWEEP_BYTES, 16 + WLIST_BYTES                                              /* a WithdrawalsSweep */
.set SWEEP_SCRATCH, 8 + WLIST_BYTES                 /* scratch of get_pending_partial_withdrawals and of the sweep */
.set EXPECTED_SCRATCH, 8 + 2 * SWEEP_BYTES + WLIST_BYTES    /* scratch of get_expected_withdrawals */

.if Withdrawal__mem != 48
.error "the withdrawal code takes 48 bytes per Withdrawal"
.endif

/* ---------------------------------------------------------------- Credentials and eligibility */

LEAF lantern_has_eth1_withdrawal_credential
    lbu     a2, Validator_withdrawal_credentials(a0)
    addi    a2, a2, -ETH1_ADDRESS_WITHDRAWAL_PREFIX
    seqz    a2, a2
    sd      a2, 0(a1)
    RETURN_OK
END_FUNCTION lantern_has_eth1_withdrawal_credential

/* Locals: sp+0 validator, sp+8 out, sp+16 the eth1 flag. */
FUNCTION lantern_has_execution_withdrawal_credential
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    addi    a1, sp, 16
    call    lantern_has_eth1_withdrawal_credential
    ld      t0, 16(sp)
    bnez    t0, 1f
    ld      a0, 0(sp)
    ld      a1, 8(sp)
    call    lantern_has_compounding_withdrawal_credential
    UNFRAME 32
1:  ld      a1, 8(sp)
    sd      t0, 0(a1)
    li      a0, LANTERN_OK
    UNFRAME 32
END_FUNCTION lantern_has_execution_withdrawal_credential

/* Locals: sp+0 validator, sp+8 balance, sp+16 epoch, sp+24 out, sp+32 the credential flag. */
FUNCTION lantern_is_fully_withdrawable_validator
    FRAME 48
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    sd      a3, 24(sp)
    addi    a1, sp, 32
    call    lantern_has_execution_withdrawal_credential
    ld      a0, 0(sp)
    ld      a1, 8(sp)
    ld      a2, 16(sp)
    ld      a3, 24(sp)
    ld      t0, 32(sp)
    ld      t1, Validator_withdrawable_epoch(a0)
    ld      t2, 0(a2)
    bleu    t1, t2, 1f                      # withdrawable_epoch <= epoch
    li      t0, 0
1:  ld      t1, 0(a1)
    bnez    t1, 2f                          # and balance > 0
    li      t0, 0
2:  sd      t0, 0(a3)
    li      a0, LANTERN_OK
    UNFRAME 48
END_FUNCTION lantern_is_fully_withdrawable_validator

/* Locals: sp+0 validator, sp+8 balance, sp+16 out, sp+24 max effective balance, sp+32 the credential flag. */
FUNCTION lantern_is_partially_withdrawable_validator
    FRAME 48
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    addi    a1, sp, 24
    call    lantern_get_max_effective_balance
    ld      a0, 0(sp)
    addi    a1, sp, 32
    call    lantern_has_execution_withdrawal_credential
    ld      a0, 0(sp)
    ld      a1, 8(sp)
    ld      t0, 32(sp)                      # has_execution_withdrawal_credential
    ld      t1, 24(sp)                      # max_effective_balance
    ld      t2, Validator_effective_balance(a0)
    beq     t2, t1, 1f                      # has_max_effective_balance
    li      t0, 0
1:  ld      t2, 0(a1)
    bgtu    t2, t1, 2f                      # has_excess_balance
    li      t0, 0
2:  ld      a2, 16(sp)
    sd      t0, 0(a2)
    li      a0, LANTERN_OK
    UNFRAME 48
END_FUNCTION lantern_is_partially_withdrawable_validator

LEAF lantern_is_eligible_for_partial_withdrawals
    ld      a3, Validator_exit_epoch(a0)
    ld      a4, Validator_effective_balance(a0)
    ld      a5, 0(a1)
    li      a6, MIN_ACTIVATION_BALANCE
    li      t0, 0
    addi    a3, a3, 1                       # exit_epoch == FAR_FUTURE_EPOCH
    bnez    a3, 1f
    bltu    a4, a6, 1f                      # and effective_balance >= MIN_ACTIVATION_BALANCE
    sltu    t0, a6, a5                      # and balance > MIN_ACTIVATION_BALANCE
1:  sd      t0, 0(a2)
    RETURN_OK
END_FUNCTION lantern_is_eligible_for_partial_withdrawals

LEAF lantern_get_pending_balance_to_withdraw
    ld      a3, 0(a1)
    PART    a4, a5, a0, BeaconState_pending_partial_withdrawals
    li      a6, 0
1:  beqz    a5, 3f
    ld      t0, PendingPartialWithdrawal_validator_index(a4)
    bne     t0, a3, 2f
    ld      t0, PendingPartialWithdrawal_amount(a4)
    add     t1, a6, t0
    bltu    t1, a6, 4f
    mv      a6, t1
2:  addi    a4, a4, PendingPartialWithdrawal__mem
    addi    a5, a5, -1
    j       1b
3:  sd      a6, 0(a2)
    RETURN_OK
4:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_get_pending_balance_to_withdraw

/* ---------------------------------------------------------------- Expected withdrawals */

LEAF lantern_get_balance_after_withdrawals
    ld      a4, 0(a1)                       # validator_index
    ld      a5, LIST_COUNT(a2)
    addi    a6, a2, LIST_FIXED
    li      t0, 0                           # withdrawn
1:  beqz    a5, 3f
    ld      t1, Withdrawal_validator_index(a6)
    bne     t1, a4, 2f
    ld      t1, Withdrawal_amount(a6)
    add     t2, t0, t1
    bltu    t2, t0, 4f
    mv      t0, t2
2:  addi    a6, a6, Withdrawal__mem
    addi    a5, a5, -1
    j       1b
3:  PART    t1, t2, a0, BeaconState_balances
    slli    t2, a4, 3
    add     t1, t1, t2
    ld      t1, 0(t1)
    bltu    t1, t0, 4f                      # state.balances[validator_index] - withdrawn
    sub     t1, t1, t0
    sd      t1, 0(a3)
    RETURN_OK
4:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_get_balance_after_withdrawals

/*
 * The list all = prior + new, for get_balance_after_withdrawals: a0 = all (a Withdrawals value),
 * a1 = prior, a2 = new. Uses a0-a3, t0-t3. A leaf.
 */
LOCAL_FUNCTION concat_withdrawals
    UNWIND_END_PROLOGUE
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(a0)
    ld      t0, LIST_COUNT(a1)
    ld      t1, LIST_COUNT(a2)
    add     t2, t0, t1
    sd      t2, LIST_COUNT(a0)
    addi    a3, a0, LIST_FIXED
    addi    a1, a1, LIST_FIXED
    li      t3, (Withdrawal__mem / 8)
    mul     t0, t0, t3
    beqz    t0, 2f
1:  ld      t2, 0(a1)
    addi    a1, a1, 8
    sd      t2, 0(a3)
    addi    a3, a3, 8
    addi    t0, t0, -1
    bnez    t0, 1b
2:  addi    a2, a2, LIST_FIXED
    mul     t1, t1, t3
    beqz    t1, 4f
3:  ld      t2, 0(a2)
    addi    a2, a2, 8
    sd      t2, 0(a3)
    addi    a3, a3, 8
    addi    t1, t1, -1
    bnez    t1, 3b
4:  ret
END_FUNCTION concat_withdrawals

/*
 * Append Withdrawal(index, validator_index, address of validator, amount) to Withdrawals a0.
 * a1 index, a2 validator index, a3 validator, a4 amount. The address is 4-aligned in the credentials.
 */
LOCAL_FUNCTION append_withdrawal
    UNWIND_END_PROLOGUE
    ld      t0, LIST_COUNT(a0)
    addi    t1, t0, 1
    sd      t1, LIST_COUNT(a0)
    li      t1, Withdrawal__mem
    mul     t0, t0, t1
    add     t0, t0, a0
    addi    t0, t0, LIST_FIXED
    sd      a1, Withdrawal_index(t0)
    sd      a2, Withdrawal_validator_index(t0)
    .irp k, 0, 4, 8, 12, 16                 # address = withdrawal_credentials[12:]
    lw      t1, (Validator_withdrawal_credentials + 12 + \k)(a3)
    sw      t1, (Withdrawal_address + \k)(t0)
    .endr
    sw      zero, (Withdrawal_address + 20)(t0)     # padding
    sd      a4, Withdrawal_amount(t0)
    ret
END_FUNCTION append_withdrawal

/*
 * s1 state, s2 withdrawal index, s3 prior, s4 scratch, s5 out, s6 all,
 * s7 limit, s8 entry, s9 entries left, s10 processed.
 * Locals: L epoch, L+8 validator index, L+16 balance, L+24 eligible.
 */
FUNCTION lantern_get_pending_partial_withdrawals
    ENTER 32
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      t0, 0(s4)
    li      t1, SWEEP_SCRATCH
    bltu    t0, t1, 9f
    li      t1, WLIST_BYTES
    sub     t0, t0, t1
    add     s6, s4, t0                      # all_withdrawals, at the end of scratch
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, LIST_COUNT(s3)              # withdrawals_limit
    addi    s7, t0, MAX_PENDING_PARTIALS_PER_WITHDRAWALS_SWEEP
    li      t1, (MAX_WITHDRAWALS_PER_PAYLOAD - 1)
    bltu    s7, t1, 1f
    mv      s7, t1
1:  bgtu    t0, s7, 8f                      # assert len(prior_withdrawals) <= withdrawals_limit
    addi    t0, s5, 16                      # withdrawals = []
    li      t1, WLIST_BYTES
    sd      t1, LIST_SIZE(t0)
    li      t1, LIST_FIXED
    sd      t1, LIST_OFFSET(t0)
    sd      zero, LIST_COUNT(t0)
    li      s10, 0
    PART    s8, s9, s1, BeaconState_pending_partial_withdrawals
2:  beqz    s9, 5f
    mv      a0, s6                          # all_withdrawals = prior_withdrawals + withdrawals
    mv      a1, s3
    addi    a2, s5, 16
    call    concat_withdrawals
    ld      t0, PendingPartialWithdrawal_withdrawable_epoch(s8)
    ld      t1, L(sp)
    bgtu    t0, t1, 5f                      # not is_withdrawable
    ld      t0, LIST_COUNT(s6)
    bgeu    t0, s7, 5f                      # or has_reached_limit
    ld      t0, PendingPartialWithdrawal_validator_index(s8)
    LDQ     t1, s1, BeaconState_validators + 8
    bgeu    t0, t1, 6f                      # validator = state.validators[validator_index]
    sd      t0, (L + 8)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 8)
    mv      a2, s6
    addi    a3, sp, (L + 16)
    call    lantern_get_balance_after_withdrawals
    bnez    a0, 7f
    ld      t0, (L + 8)(sp)
    PART    a0, t1, s1, BeaconState_validators
    slli    t0, t0, 7
    add     a0, a0, t0
    addi    a1, sp, (L + 16)
    addi    a2, sp, (L + 24)
    call    lantern_is_eligible_for_partial_withdrawals
    ld      t0, (L + 24)(sp)
    beqz    t0, 3f
    ld      a4, (L + 16)(sp)                # min(balance - MIN_ACTIVATION_BALANCE, withdrawal.amount)
    li      t0, MIN_ACTIVATION_BALANCE
    sub     a4, a4, t0
    ld      t0, PendingPartialWithdrawal_amount(s8)
    bltu    a4, t0, 21f
    mv      a4, t0
21: ld      a2, (L + 8)(sp)
    PART    a3, t1, s1, BeaconState_validators
    slli    t0, a2, 7
    add     a3, a3, t0
    addi    a0, s5, 16
    mv      a1, s2
    call    append_withdrawal
    addi    s2, s2, 1
3:  addi    s10, s10, 1
    addi    s8, s8, PendingPartialWithdrawal__mem
    addi    s9, s9, -1
    j       2b
5:  sd      s2, 0(s5)
    sd      s10, 8(s5)
    li      a0, LANTERN_OK
7:  LEAVE 32
6:  li      a0, LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 32
8:  li      a0, LANTERN_INVALID_WITHDRAWALS_LIMIT
    LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION lantern_get_pending_partial_withdrawals

/*
 * s1 state, s2 withdrawal index, s3 prior, s4 scratch, s5 out, s6 all,
 * s7 sweep left, s8 validator index, s9 validator count, s10 processed.
 * Locals: L epoch, L+8 validator index, L+16 balance, L+24 predicate, L+32 max effective balance.
 */
FUNCTION lantern_get_validators_sweep_withdrawals
    ENTER 48
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      t0, 0(s4)
    li      t1, SWEEP_SCRATCH
    bltu    t0, t1, 9f
    li      t1, WLIST_BYTES
    sub     t0, t0, t1
    add     s6, s4, t0
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    LDQ     s9, s1, BeaconState_validators + 8
    li      t0, MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP
    mv      s7, s9                          # validators_limit
    bltu    s9, t0, 1f
    mv      s7, t0
1:  ld      t0, LIST_COUNT(s3)
    li      t1, MAX_WITHDRAWALS_PER_PAYLOAD
    bgeu    t0, t1, 8f                      # assert len(prior_withdrawals) < withdrawals_limit
    addi    t0, s5, 16
    li      t1, WLIST_BYTES
    sd      t1, LIST_SIZE(t0)
    li      t1, LIST_FIXED
    sd      t1, LIST_OFFSET(t0)
    sd      zero, LIST_COUNT(t0)
    li      s10, 0
    LDQ     s8, s1, BeaconState_next_withdrawal_validator_index
2:  beqz    s7, 5f
    mv      a0, s6
    mv      a1, s3
    addi    a2, s5, 16
    call    concat_withdrawals
    ld      t0, LIST_COUNT(s6)
    li      t1, MAX_WITHDRAWALS_PER_PAYLOAD
    bgeu    t0, t1, 5f                      # has_reached_limit
    bgeu    s8, s9, 6f
    sd      s8, (L + 8)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 8)
    mv      a2, s6
    addi    a3, sp, (L + 16)
    call    lantern_get_balance_after_withdrawals
    bnez    a0, 7f
    PART    a0, t0, s1, BeaconState_validators
    slli    t0, s8, 7
    add     a0, a0, t0
    addi    a1, sp, (L + 16)
    addi    a2, sp, L
    addi    a3, sp, (L + 24)
    call    lantern_is_fully_withdrawable_validator
    ld      t0, (L + 24)(sp)
    beqz    t0, 3f
    ld      a4, (L + 16)(sp)                # amount = balance
    j       4f
3:  PART    a0, t0, s1, BeaconState_validators
    slli    t0, s8, 7
    add     a0, a0, t0
    addi    a1, sp, (L + 16)
    addi    a2, sp, (L + 24)
    call    lantern_is_partially_withdrawable_validator
    ld      t0, (L + 24)(sp)
    beqz    t0, 41f
    PART    a0, t0, s1, BeaconState_validators
    slli    t0, s8, 7
    add     a0, a0, t0
    addi    a1, sp, (L + 32)
    call    lantern_get_max_effective_balance
    ld      a4, (L + 16)(sp)                # amount = balance - get_max_effective_balance(validator)
    ld      t0, (L + 32)(sp)
    sub     a4, a4, t0
4:  PART    a3, t0, s1, BeaconState_validators
    slli    t0, s8, 7
    add     a3, a3, t0
    addi    a0, s5, 16
    mv      a1, s2
    mv      a2, s8
    call    append_withdrawal
    addi    s2, s2, 1
41: addi    s8, s8, 1                       # validator_index = (validator_index + 1) % len(state.validators)
    bltu    s8, s9, 42f
    li      s8, 0
42: addi    s10, s10, 1
    addi    s7, s7, -1
    j       2b
5:  sd      s2, 0(s5)
    sd      s10, 8(s5)
    li      a0, LANTERN_OK
7:  LEAVE 48
6:  li      a0, LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 48
8:  li      a0, LANTERN_INVALID_WITHDRAWALS_LIMIT
    LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
END_FUNCTION lantern_get_validators_sweep_withdrawals

/* s1 state, s2 scratch, s3 out, s4 scratch size, s5 the partial sweep, s6 the validator sweep. Locals: L withdrawal index. */
FUNCTION lantern_get_expected_withdrawals
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(s2)
    li      t0, EXPECTED_SCRATCH
    bltu    s4, t0, 9f
    li      t0, SWEEP_BYTES
    sub     t1, s4, t0
    add     s5, s2, t1
    sub     t1, t1, t0
    add     s6, s2, t1
    addi    t0, s3, 16                      # withdrawals = []
    li      t1, WLIST_BYTES
    sd      t1, LIST_SIZE(t0)
    li      t1, LIST_FIXED
    sd      t1, LIST_OFFSET(t0)
    sd      zero, LIST_COUNT(t0)
    LDQ     t0, s1, BeaconState_next_withdrawal_index
    sd      t0, L(sp)
    li      t0, 2 * SWEEP_BYTES
    sub     t0, s4, t0
    sd      t0, 0(s2)
    mv      a0, s1                          # get_pending_partial_withdrawals(state, withdrawal_index, withdrawals)
    addi    a1, sp, L
    addi    a2, s3, 16
    mv      a3, s2
    mv      a4, s5
    call    lantern_get_pending_partial_withdrawals
    bnez    a0, 7f
    addi    a0, s3, 16                      # withdrawals.extend(partial_withdrawals)
    addi    a1, s3, 16
    addi    a2, s5, 16
    call    concat_withdrawals
    li      t0, 2 * SWEEP_BYTES
    sub     t0, s4, t0
    sd      t0, 0(s2)
    mv      a0, s1                          # get_validators_sweep_withdrawals(state, withdrawal_index, withdrawals)
    mv      a1, s5
    addi    a2, s3, 16
    mv      a3, s2
    mv      a4, s6
    call    lantern_get_validators_sweep_withdrawals
    bnez    a0, 7f
    addi    a0, s3, 16
    addi    a1, s3, 16
    addi    a2, s6, 16
    call    concat_withdrawals
    ld      t0, 8(s5)
    sd      t0, 0(s3)                       # processed_partial_withdrawals_count
    ld      t0, 8(s6)
    sd      t0, 8(s3)                       # processed_sweep_withdrawals_count
    li      a0, LANTERN_OK
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_get_expected_withdrawals

/* ---------------------------------------------------------------- Applying withdrawals */

/* s1 state, s2 entry, s3 entries left. */
FUNCTION lantern_apply_withdrawals
    ENTER 16
    mv      s1, a0
    addi    s2, a1, LIST_FIXED
    ld      s3, LIST_COUNT(a1)
1:  beqz    s3, 2f
    mv      a0, s1
    addi    a1, s2, Withdrawal_validator_index
    addi    a2, s2, Withdrawal_amount
    call    lantern_decrease_balance
    addi    s2, s2, Withdrawal__mem
    addi    s3, s3, -1
    j       1b
2:  li      a0, LANTERN_OK
    LEAVE 16
END_FUNCTION lantern_apply_withdrawals

LEAF lantern_update_next_withdrawal_index
    ld      a2, LIST_COUNT(a1)
    beqz    a2, 1f
    addi    a2, a2, -1
    li      a3, Withdrawal__mem
    mul     a3, a2, a3
    add     a3, a3, a1
    ld      a3, (LIST_FIXED + Withdrawal_index)(a3)
    addi    a3, a3, 1
    STQ     a3, a0, BeaconState_next_withdrawal_index
1:  RETURN_OK
END_FUNCTION lantern_update_next_withdrawal_index

FUNCTION lantern_update_pending_partial_withdrawals
    FRAME 0
    ld      t0, 0(a1)
    beqz    t0, 1f
    PART    t1, t2, a0, BeaconState_pending_partial_withdrawals
    sub     t2, t2, t0
    STQ     t2, a0, BeaconState_pending_partial_withdrawals + 8
    li      t3, PendingPartialWithdrawal__mem
    mv      a0, t1
    mul     a1, t0, t3
    add     a1, a1, t1
    mul     a2, t2, t3
    call    lantern_copy
1:  li      a0, LANTERN_OK
    UNFRAME 0
END_FUNCTION lantern_update_pending_partial_withdrawals

LEAF lantern_update_next_withdrawal_validator_index
    LDQ     a4, a0, BeaconState_validators + 8
    ld      a2, LIST_COUNT(a1)
    li      a5, MAX_WITHDRAWALS_PER_PAYLOAD
    bne     a2, a5, 1f
    addi    a2, a2, -1                      # (withdrawals[-1].validator_index + 1) % len(state.validators)
    li      a3, Withdrawal__mem
    mul     a3, a2, a3
    add     a3, a3, a1
    ld      a3, (LIST_FIXED + Withdrawal_validator_index)(a3)
    addi    a3, a3, 1
    j       2f
1:  LDQ     a3, a0, BeaconState_next_withdrawal_validator_index
    li      a5, MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP
    add     a3, a3, a5
2:  remu    a3, a3, a4
    STQ     a3, a0, BeaconState_next_withdrawal_validator_index
    RETURN_OK
END_FUNCTION lantern_update_next_withdrawal_validator_index

/* ---------------------------------------------------------------- process_withdrawals */

/* s1 state, s2 payload, s3 scratch, s4 result, s5 expected, s6 scratch size. */
FUNCTION lantern_process_withdrawals
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a3
    mv      s4, a4
    ld      s6, 0(s3)
    li      t0, EXPECTED_SCRATCH + SWEEP_BYTES
    bltu    s6, t0, 9f
    li      t0, SWEEP_BYTES
    sub     t0, s6, t0
    add     s5, s3, t0
    sd      t0, 0(s3)
    mv      a0, s1                          # expected = get_expected_withdrawals(state)
    mv      a1, s3
    mv      a2, s5
    call    lantern_get_expected_withdrawals
    CHECK_STATUS s4, 7f, 8f
    PART    t0, t1, s2, ExecutionPayload_withdrawals   # assert list(payload.withdrawals) == expected.withdrawals
    ld      t2, (16 + LIST_COUNT)(s5)
    bne     t1, t2, 6f
    addi    t2, s5, (16 + LIST_FIXED)
1:  beqz    t1, 2f
    .irp off, Withdrawal_index, Withdrawal_validator_index, Withdrawal_address, (Withdrawal_address+8), Withdrawal_amount
    ld      t3, (\off)(t0)
    ld      t4, (\off)(t2)
    bne     t3, t4, 6f
    .endr
    lwu     t3, (Withdrawal_address + 16)(t0)  # the last 4 bytes of the address
    lwu     t4, (Withdrawal_address + 16)(t2)
    bne     t3, t4, 6f
    addi    t0, t0, Withdrawal__mem
    addi    t2, t2, Withdrawal__mem
    addi    t1, t1, -1
    j       1b
2:  mv      a0, s1
    addi    a1, s5, 16
    call    lantern_apply_withdrawals
    mv      a0, s1
    addi    a1, s5, 16
    call    lantern_update_next_withdrawal_index
    mv      a0, s1
    mv      a1, s5                          # processed_partial_withdrawals_count
    call    lantern_update_pending_partial_withdrawals
    mv      a0, s1
    addi    a1, s5, 16
    call    lantern_update_next_withdrawal_validator_index
    sd      zero, 0(s4)
8:  li      a0, LANTERN_OK
7:  LEAVE 16
6:  li      t0, LANTERN_INVALID_WITHDRAWALS
    sd      t0, 0(s4)
    li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_process_withdrawals
