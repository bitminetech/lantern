/*
 * Withdrawals, ARM64. Requirements: docs/reference/block-processing.md.
 */

.set WLIST_BYTES, LIST_FIXED + MAX_WITHDRAWALS_PER_PAYLOAD * Withdrawal__mem   /* a Withdrawals value */
.set SWEEP_BYTES, 16 + WLIST_BYTES                                              /* a WithdrawalsSweep */
.set SWEEP_SCRATCH, 8 + WLIST_BYTES                 /* scratch of get_pending_partial_withdrawals and of the sweep */
.set EXPECTED_SCRATCH, 8 + 2 * SWEEP_BYTES + WLIST_BYTES    /* scratch of get_expected_withdrawals */

.if Withdrawal__mem != 48
.error "the withdrawal code takes 48 bytes per Withdrawal"
.endif

/* ---------------------------------------------------------------- Credentials and eligibility */

SPEC_LEAF has_eth1_withdrawal_credential
    ldrb    w2, [x0, #Validator_withdrawal_credentials]
    cmp     w2, #ETH1_ADDRESS_WITHDRAWAL_PREFIX
    cset    x2, eq
    str     x2, [x1]
    RETURN_OK
SPEC_END has_eth1_withdrawal_credential

.if FORK >= FORK_ELECTRA
SPEC_FUNCTION has_execution_withdrawal_credential
    FRAME 32
    stp     x0, x1, [sp, #16]
    add     x1, sp, #32
    bl      lantern_has_eth1_withdrawal_credential
    ldr     x9, [sp, #32]
    cbnz    x9, 1f
    ldp     x0, x1, [sp, #16]
    bl      lantern_has_compounding_withdrawal_credential
    UNFRAME 32
1:  ldr     x1, [sp, #24]
    str     x9, [x1]
    mov     x0, #LANTERN_OK
    UNFRAME 32
SPEC_END has_execution_withdrawal_credential
.endif

/* Before electra the two predicates take has_eth1_withdrawal_credential and MAX_EFFECTIVE_BALANCE. */
.if FORK >= FORK_ELECTRA
.macro WITHDRAWAL_CREDENTIAL
    bl      lantern_has_execution_withdrawal_credential
.endm
.else
.macro WITHDRAWAL_CREDENTIAL
    bl      lantern_has_eth1_withdrawal_credential
.endm
.endif

SPEC_FUNCTION is_fully_withdrawable_validator
    FRAME 48
    stp     x0, x1, [sp, #16]
    stp     x2, x3, [sp, #32]
    add     x1, sp, #48
    WITHDRAWAL_CREDENTIAL
    ldp     x0, x1, [sp, #16]
    ldp     x2, x3, [sp, #32]
    ldr     x9, [sp, #48]
    ldr     x10, [x0, #Validator_withdrawable_epoch]
    ldr     x11, [x2]
    cmp     x10, x11                        /* withdrawable_epoch <= epoch */
    csel    x9, x9, xzr, ls
    ldr     x10, [x1]
    cmp     x10, #0                         /* and balance > 0 */
    csel    x9, x9, xzr, ne
    str     x9, [x3]
    mov     x0, #LANTERN_OK
    UNFRAME 48
SPEC_END is_fully_withdrawable_validator

SPEC_FUNCTION is_partially_withdrawable_validator
    FRAME 48
    stp     x0, x1, [sp, #16]
    str     x2, [sp, #32]
.if FORK >= FORK_ELECTRA
    add     x1, sp, #40
    bl      lantern_get_max_effective_balance
.else
    MOVQ    x9, MAX_EFFECTIVE_BALANCE
    str     x9, [sp, #40]
.endif
    ldr     x0, [sp, #16]
    add     x1, sp, #48
    WITHDRAWAL_CREDENTIAL
    ldp     x0, x1, [sp, #16]
    ldr     x9, [sp, #48]                   /* has_execution_withdrawal_credential */
    ldr     x10, [sp, #40]                  /* max_effective_balance */
    ldr     x11, [x0, #Validator_effective_balance]
    cmp     x11, x10                        /* has_max_effective_balance */
    csel    x9, x9, xzr, eq
    ldr     x11, [x1]
    cmp     x11, x10                        /* has_excess_balance */
    csel    x9, x9, xzr, hi
    ldr     x2, [sp, #32]
    str     x9, [x2]
    mov     x0, #LANTERN_OK
    UNFRAME 48
SPEC_END is_partially_withdrawable_validator

.if FORK >= FORK_ELECTRA
SPEC_LEAF is_eligible_for_partial_withdrawals
    ldr     x3, [x0, #Validator_exit_epoch]
    ldr     x4, [x0, #Validator_effective_balance]
    ldr     x5, [x1]
    MOVQ    x6, MIN_ACTIVATION_BALANCE
    cmn     x3, #1                          /* exit_epoch == FAR_FUTURE_EPOCH */
    ccmp    x4, x6, #0, eq                  /* and effective_balance >= MIN_ACTIVATION_BALANCE */
    ccmp    x5, x6, #0, hs                  /* and balance > MIN_ACTIVATION_BALANCE */
    cset    x7, hi
    str     x7, [x2]
    RETURN_OK
SPEC_END is_eligible_for_partial_withdrawals

SPEC_LEAF get_pending_balance_to_withdraw
    ldr     x3, [x1]
    PART    x4, x5, x0, BeaconState_pending_partial_withdrawals
    mov     x6, #0
1:  cbz     x5, 3f
    ldr     x7, [x4, #PendingPartialWithdrawal_validator_index]
    cmp     x7, x3
    b.ne    2f
    ldr     x7, [x4, #PendingPartialWithdrawal_amount]
    adds    x6, x6, x7
    b.cs    4f
2:  add     x4, x4, #PendingPartialWithdrawal__mem
    sub     x5, x5, #1
    b       1b
3:  str     x6, [x2]
    RETURN_OK
4:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
SPEC_END get_pending_balance_to_withdraw
.endif

/* ---------------------------------------------------------------- Expected withdrawals */

SPEC_LEAF get_balance_after_withdrawals
    ldr     x4, [x1]                        /* validator_index */
    ldr     x5, [x2, #LIST_COUNT]
    add     x6, x2, #LIST_FIXED
    mov     x7, #0                          /* withdrawn */
1:  cbz     x5, 3f
    ldr     x8, [x6, #Withdrawal_validator_index]
    cmp     x8, x4
    b.ne    2f
    ldr     x8, [x6, #Withdrawal_amount]
    adds    x7, x7, x8
    b.cs    4f
2:  add     x6, x6, #Withdrawal__mem
    sub     x5, x5, #1
    b       1b
3:  PART    x8, x9, x0, BeaconState_balances
    ldr     x8, [x8, x4, lsl #3]
    subs    x8, x8, x7                      /* state.balances[validator_index] - withdrawn */
    b.lo    4f
    str     x8, [x3]
    RETURN_OK
4:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
SPEC_END get_balance_after_withdrawals

/*
 * The list all = prior + new, for get_balance_after_withdrawals: x0 = all (a Withdrawals value),
 * x1 = prior, x2 = new. Uses x0-x3, x9-x12. A leaf.
 */
LOCAL_FUNCTION lantern_concat_withdrawals
    UNWIND_END_PROLOGUE
    mov     x9, #LIST_FIXED
    str     x9, [x0, #LIST_OFFSET]
    ldr     x9, [x1, #LIST_COUNT]
    ldr     x10, [x2, #LIST_COUNT]
    add     x11, x9, x10
    str     x11, [x0, #LIST_COUNT]
    add     x3, x0, #LIST_FIXED
    add     x1, x1, #LIST_FIXED
    mov     x12, #(Withdrawal__mem / 8)
    mul     x9, x9, x12
    cbz     x9, 2f
1:  ldr     x11, [x1], #8
    str     x11, [x3], #8
    subs    x9, x9, #1
    b.ne    1b
2:  add     x2, x2, #LIST_FIXED
    mul     x10, x10, x12
    cbz     x10, 4f
3:  ldr     x11, [x2], #8
    str     x11, [x3], #8
    subs    x10, x10, #1
    b.ne    3b
4:  ret
END_FUNCTION lantern_concat_withdrawals

/* Append Withdrawal(index, validator_index, address of validator, amount) to Withdrawals x0. x1 index, x2 validator index, x3 validator, x4 amount. */
LOCAL_FUNCTION lantern_append_withdrawal
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #LIST_COUNT]
    add     x10, x9, #1
    str     x10, [x0, #LIST_COUNT]
    mov     x10, #Withdrawal__mem
    madd    x9, x9, x10, x0
    add     x9, x9, #LIST_FIXED
    str     x1, [x9, #Withdrawal_index]
    str     x2, [x9, #Withdrawal_validator_index]
    ldr     x10, [x3, #(Validator_withdrawal_credentials + 12)]   /* address = withdrawal_credentials[12:] */
    str     x10, [x9, #Withdrawal_address]
    ldr     x10, [x3, #(Validator_withdrawal_credentials + 20)]
    str     x10, [x9, #(Withdrawal_address + 8)]
    ldr     w10, [x3, #(Validator_withdrawal_credentials + 28)]
    str     w10, [x9, #(Withdrawal_address + 16)]
    str     wzr, [x9, #(Withdrawal_address + 20)]                 /* padding */
    str     x4, [x9, #Withdrawal_amount]
    ret
END_FUNCTION lantern_append_withdrawal

.if FORK >= FORK_ELECTRA
/*
 * x19 state, x20 withdrawal index, x21 prior, x22 scratch, x23 out, x24 all,
 * x25 limit, x26 entry, x27 entries left, x28 processed.
 * Locals: L epoch, L+8 validator index, L+16 balance, L+24 eligible.
 */
SPEC_FUNCTION get_pending_partial_withdrawals
    ENTER 32
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x9, [x22]
    MOVQ    x10, SWEEP_SCRATCH
    cmp     x9, x10
    b.lo    9f
    MOVQ    x10, WLIST_BYTES
    sub     x9, x9, x10
    add     x24, x22, x9                    /* all_withdrawals, at the end of scratch */
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [x21, #LIST_COUNT]          /* withdrawals_limit */
    add     x25, x9, #MAX_PENDING_PARTIALS_PER_WITHDRAWALS_SWEEP
    mov     x10, #(MAX_WITHDRAWALS_PER_PAYLOAD - 1)
    cmp     x25, x10
    csel    x25, x25, x10, lo
    cmp     x9, x25                         /* assert len(prior_withdrawals) <= withdrawals_limit */
    b.hi    8f
    add     x9, x23, #16                    /* withdrawals = [] */
    MOVQ    x10, WLIST_BYTES
    str     x10, [x9, #LIST_SIZE]
    mov     x10, #LIST_FIXED
    str     x10, [x9, #LIST_OFFSET]
    str     xzr, [x9, #LIST_COUNT]
    mov     x28, #0
    PART    x26, x27, x19, BeaconState_pending_partial_withdrawals
1:  cbz     x27, 5f
    mov     x0, x24                         /* all_withdrawals = prior_withdrawals + withdrawals */
    mov     x1, x21
    add     x2, x23, #16
    bl      lantern_concat_withdrawals
    ldr     x9, [x26, #PendingPartialWithdrawal_withdrawable_epoch]
    ldr     x10, [sp, #L]
    cmp     x9, x10                         /* not is_withdrawable */
    b.hi    5f
    ldr     x9, [x24, #LIST_COUNT]
    cmp     x9, x25                         /* or has_reached_limit */
    b.hs    5f
    ldr     x9, [x26, #PendingPartialWithdrawal_validator_index]
    LDQ     x10, x19, BeaconState_validators + 8
    cmp     x9, x10                         /* validator = state.validators[validator_index] */
    b.hs    6f
    str     x9, [sp, #(L + 8)]
    mov     x0, x19
    add     x1, sp, #(L + 8)
    mov     x2, x24
    add     x3, sp, #(L + 16)
    bl      lantern_get_balance_after_withdrawals
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 8)]
    PART    x0, x10, x19, BeaconState_validators
    add     x0, x0, x9, lsl #7
    add     x1, sp, #(L + 16)
    add     x2, sp, #(L + 24)
    bl      lantern_is_eligible_for_partial_withdrawals
    ldr     x9, [sp, #(L + 24)]
    cbz     x9, 2f
    ldr     x4, [sp, #(L + 16)]             /* min(balance - MIN_ACTIVATION_BALANCE, withdrawal.amount) */
    MOVQ    x9, MIN_ACTIVATION_BALANCE
    sub     x4, x4, x9
    ldr     x9, [x26, #PendingPartialWithdrawal_amount]
    cmp     x4, x9
    csel    x4, x4, x9, lo
    ldr     x2, [sp, #(L + 8)]
    PART    x3, x10, x19, BeaconState_validators
    add     x3, x3, x2, lsl #7
    add     x0, x23, #16
    mov     x1, x20
    bl      lantern_append_withdrawal
    add     x20, x20, #1
2:  add     x28, x28, #1
    add     x26, x26, #PendingPartialWithdrawal__mem
    sub     x27, x27, #1
    b       1b
5:  str     x20, [x23]
    str     x28, [x23, #8]
    mov     x0, #LANTERN_OK
7:  LEAVE 32
6:  mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 32
8:  mov     x0, #LANTERN_INVALID_WITHDRAWALS_LIMIT
    LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END get_pending_partial_withdrawals
.endif

/*
 * x19 state, x20 withdrawal index, x21 prior, x22 scratch, x23 out, x24 all,
 * x25 sweep left, x26 validator index, x27 validator count, x28 processed.
 * Locals: L epoch, L+8 validator index, L+16 balance, L+24 predicate, L+32 max effective balance.
 */
SPEC_FUNCTION get_validators_sweep_withdrawals
    ENTER 48
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x9, [x22]
    MOVQ    x10, SWEEP_SCRATCH
    cmp     x9, x10
    b.lo    9f
    MOVQ    x10, WLIST_BYTES
    sub     x9, x9, x10
    add     x24, x22, x9
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    LDQ     x27, x19, BeaconState_validators + 8
    MOVQ    x9, MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP
    cmp     x27, x9
    csel    x25, x27, x9, lo                /* validators_limit */
    ldr     x9, [x21, #LIST_COUNT]
    cmp     x9, #MAX_WITHDRAWALS_PER_PAYLOAD    /* assert len(prior_withdrawals) < withdrawals_limit */
    b.hs    8f
    add     x9, x23, #16
    MOVQ    x10, WLIST_BYTES
    str     x10, [x9, #LIST_SIZE]
    mov     x10, #LIST_FIXED
    str     x10, [x9, #LIST_OFFSET]
    str     xzr, [x9, #LIST_COUNT]
    mov     x28, #0
    LDQ     x26, x19, BeaconState_next_withdrawal_validator_index
1:  cbz     x25, 5f
    mov     x0, x24
    mov     x1, x21
    add     x2, x23, #16
    bl      lantern_concat_withdrawals
    ldr     x9, [x24, #LIST_COUNT]
    cmp     x9, #MAX_WITHDRAWALS_PER_PAYLOAD    /* has_reached_limit */
    b.hs    5f
    cmp     x26, x27
    b.hs    6f
    str     x26, [sp, #(L + 8)]
    mov     x0, x19
    add     x1, sp, #(L + 8)
    mov     x2, x24
    add     x3, sp, #(L + 16)
    bl      lantern_get_balance_after_withdrawals
    cbnz    x0, 7f
    PART    x0, x10, x19, BeaconState_validators
    add     x0, x0, x26, lsl #7
    add     x1, sp, #(L + 16)
    add     x2, sp, #L
    add     x3, sp, #(L + 24)
    bl      lantern_is_fully_withdrawable_validator
    ldr     x9, [sp, #(L + 24)]
    cbz     x9, 2f
    ldr     x4, [sp, #(L + 16)]             /* amount = balance */
    b       3f
2:  PART    x0, x10, x19, BeaconState_validators
    add     x0, x0, x26, lsl #7
    add     x1, sp, #(L + 16)
    add     x2, sp, #(L + 24)
    bl      lantern_is_partially_withdrawable_validator
    ldr     x9, [sp, #(L + 24)]
    cbz     x9, 4f
.if FORK >= FORK_ELECTRA
    PART    x0, x10, x19, BeaconState_validators
    add     x0, x0, x26, lsl #7
    add     x1, sp, #(L + 32)
    bl      lantern_get_max_effective_balance
    ldr     x4, [sp, #(L + 16)]             /* amount = balance - get_max_effective_balance(validator) */
    ldr     x9, [sp, #(L + 32)]
    sub     x4, x4, x9
.else
    ldr     x4, [sp, #(L + 16)]             /* amount = balance - MAX_EFFECTIVE_BALANCE */
    MOVQ    x9, MAX_EFFECTIVE_BALANCE
    sub     x4, x4, x9
.endif
3:  PART    x3, x10, x19, BeaconState_validators
    add     x3, x3, x26, lsl #7
    add     x0, x23, #16
    mov     x1, x20
    mov     x2, x26
    bl      lantern_append_withdrawal
    add     x20, x20, #1
4:  add     x26, x26, #1                    /* validator_index = (validator_index + 1) % len(state.validators) */
    cmp     x26, x27
    csel    x26, x26, xzr, lo
    add     x28, x28, #1
    sub     x25, x25, #1
    b       1b
5:  str     x20, [x23]
    str     x28, [x23, #8]
    mov     x0, #LANTERN_OK
7:  LEAVE 48
6:  mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 48
8:  mov     x0, #LANTERN_INVALID_WITHDRAWALS_LIMIT
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END get_validators_sweep_withdrawals

/* x19 state, x20 scratch, x21 out, x22 scratch size, x23 the partial sweep, x24 the validator sweep. Locals: L withdrawal index. */
SPEC_FUNCTION get_expected_withdrawals
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x20]
    MOVQ    x9, EXPECTED_SCRATCH
    cmp     x22, x9
    b.lo    9f
    MOVQ    x9, SWEEP_BYTES
    sub     x10, x22, x9
    add     x23, x20, x10
    sub     x10, x10, x9
    add     x24, x20, x10
    add     x9, x21, #16                    /* withdrawals = [] */
    MOVQ    x10, WLIST_BYTES
    str     x10, [x9, #LIST_SIZE]
    mov     x10, #LIST_FIXED
    str     x10, [x9, #LIST_OFFSET]
    str     xzr, [x9, #LIST_COUNT]
    LDQ     x9, x19, BeaconState_next_withdrawal_index
    str     x9, [sp, #L]
.if FORK >= FORK_ELECTRA
    MOVQ    x9, 2 * SWEEP_BYTES
    sub     x9, x22, x9
    str     x9, [x20]
    mov     x0, x19                         /* get_pending_partial_withdrawals(state, withdrawal_index, withdrawals) */
    add     x1, sp, #L
    add     x2, x21, #16
    mov     x3, x20
    mov     x4, x23
    bl      lantern_get_pending_partial_withdrawals
    cbnz    x0, 7f
    add     x0, x21, #16                    /* withdrawals.extend(partial_withdrawals) */
    add     x1, x21, #16
    add     x2, x23, #16
    bl      lantern_concat_withdrawals
.else
    str     xzr, [x23, #8]                  /* no partial withdrawals before electra */
.endif
    MOVQ    x9, 2 * SWEEP_BYTES
    sub     x9, x22, x9
    str     x9, [x20]
    mov     x0, x19                         /* get_validators_sweep_withdrawals(state, withdrawal_index, withdrawals) */
.if FORK >= FORK_ELECTRA
    mov     x1, x23
.else
    add     x1, sp, #L
.endif
    add     x2, x21, #16
    mov     x3, x20
    mov     x4, x24
    bl      lantern_get_validators_sweep_withdrawals
    cbnz    x0, 7f
    add     x0, x21, #16
    add     x1, x21, #16
    add     x2, x24, #16
    bl      lantern_concat_withdrawals
    ldr     x9, [x23, #8]
    str     x9, [x21]                       /* processed_partial_withdrawals_count */
    ldr     x9, [x24, #8]
    str     x9, [x21, #8]                   /* processed_sweep_withdrawals_count */
    mov     x0, #LANTERN_OK
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_expected_withdrawals

/* ---------------------------------------------------------------- Applying withdrawals */

/* x19 state, x20 entry, x21 entries left. */
SPEC_FUNCTION apply_withdrawals
    ENTER 16
    mov     x19, x0
    add     x20, x1, #LIST_FIXED
    ldr     x21, [x1, #LIST_COUNT]
1:  cbz     x21, 2f
    mov     x0, x19
    add     x1, x20, #Withdrawal_validator_index
    add     x2, x20, #Withdrawal_amount
    bl      lantern_decrease_balance
    add     x20, x20, #Withdrawal__mem
    sub     x21, x21, #1
    b       1b
2:  mov     x0, #LANTERN_OK
    LEAVE 16
SPEC_END apply_withdrawals

SPEC_LEAF update_next_withdrawal_index
    ldr     x2, [x1, #LIST_COUNT]
    cbz     x2, 1f
    sub     x2, x2, #1
    mov     x3, #Withdrawal__mem
    madd    x3, x2, x3, x1
    ldr     x3, [x3, #(LIST_FIXED + Withdrawal_index)]
    add     x3, x3, #1
    STQ     x3, x0, BeaconState_next_withdrawal_index
1:  RETURN_OK
SPEC_END update_next_withdrawal_index

.if FORK >= FORK_ELECTRA
SPEC_FUNCTION update_pending_partial_withdrawals
    FRAME 0
    ldr     x9, [x1]
    cbz     x9, 1f
    PART    x10, x11, x0, BeaconState_pending_partial_withdrawals
    sub     x11, x11, x9
    STQ     x11, x0, BeaconState_pending_partial_withdrawals + 8
    mov     x12, #PendingPartialWithdrawal__mem
    mov     x0, x10
    madd    x1, x9, x12, x10
    mul     x2, x11, x12
    bl      lantern_copy
1:  mov     x0, #LANTERN_OK
    UNFRAME 0
SPEC_END update_pending_partial_withdrawals
.endif

SPEC_LEAF update_next_withdrawal_validator_index
    LDQ     x4, x0, BeaconState_validators + 8
    ldr     x2, [x1, #LIST_COUNT]
    cmp     x2, #MAX_WITHDRAWALS_PER_PAYLOAD
    b.ne    1f
    sub     x2, x2, #1                      /* (withdrawals[-1].validator_index + 1) % len(state.validators) */
    mov     x3, #Withdrawal__mem
    madd    x3, x2, x3, x1
    ldr     x3, [x3, #(LIST_FIXED + Withdrawal_validator_index)]
    add     x3, x3, #1
    b       2f
1:  LDQ     x3, x0, BeaconState_next_withdrawal_validator_index
    MOVQ    x5, MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP
    add     x3, x3, x5
2:  udiv    x5, x3, x4
    msub    x3, x5, x4, x3
    STQ     x3, x0, BeaconState_next_withdrawal_validator_index
    RETURN_OK
SPEC_END update_next_withdrawal_validator_index

/* ---------------------------------------------------------------- process_withdrawals */

/* x19 state, x20 payload, x21 scratch, x22 result, x23 expected, x24 scratch size. */
SPEC_FUNCTION process_withdrawals
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x3
    mov     x22, x4
    ldr     x24, [x21]
    MOVQ    x9, EXPECTED_SCRATCH + SWEEP_BYTES
    cmp     x24, x9
    b.lo    9f
    MOVQ    x9, SWEEP_BYTES
    sub     x9, x24, x9
    add     x23, x21, x9
    str     x9, [x21]
    mov     x0, x19                         /* expected = get_expected_withdrawals(state) */
    mov     x1, x21
    mov     x2, x23
    bl      lantern_get_expected_withdrawals
    CHECK_STATUS x22, 7f, 8f
    PART    x9, x10, x20, ExecutionPayload_withdrawals  /* assert list(payload.withdrawals) == expected.withdrawals */
    ldr     x11, [x23, #(16 + LIST_COUNT)]
    cmp     x10, x11
    b.ne    6f
    add     x12, x23, #(16 + LIST_FIXED)
1:  cbz     x10, 2f
    ldp     x13, x14, [x9]                  /* index, validator_index */
    ldp     x15, x16, [x12]
    cmp     x13, x15
    ccmp    x14, x16, #0, eq
    b.ne    6f
    ldp     x13, x14, [x9, #Withdrawal_address]     /* address: 20 bytes */
    ldp     x15, x16, [x12, #Withdrawal_address]
    cmp     x13, x15
    ccmp    x14, x16, #0, eq
    b.ne    6f
    ldr     w13, [x9, #(Withdrawal_address + 16)]
    ldr     w15, [x12, #(Withdrawal_address + 16)]
    cmp     w13, w15
    b.ne    6f
    ldr     x13, [x9, #Withdrawal_amount]
    ldr     x15, [x12, #Withdrawal_amount]
    cmp     x13, x15
    b.ne    6f
    add     x9, x9, #Withdrawal__mem
    add     x12, x12, #Withdrawal__mem
    sub     x10, x10, #1
    b       1b
2:  mov     x0, x19
    add     x1, x23, #16
    bl      lantern_apply_withdrawals
    mov     x0, x19
    add     x1, x23, #16
    bl      lantern_update_next_withdrawal_index
.if FORK >= FORK_ELECTRA
    mov     x0, x19
    mov     x1, x23                         /* processed_partial_withdrawals_count */
    bl      lantern_update_pending_partial_withdrawals
.endif
    mov     x0, x19
    add     x1, x23, #16
    bl      lantern_update_next_withdrawal_validator_index
    str     xzr, [x22]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 16
6:  mov     x9, #LANTERN_INVALID_WITHDRAWALS
    str     x9, [x22]
    mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END process_withdrawals
