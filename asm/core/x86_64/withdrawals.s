/*
 * Withdrawals, x86-64. Requirements: docs/reference/block-processing.md.
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
    xor     %eax, %eax
    cmpb    $ETH1_ADDRESS_WITHDRAWAL_PREFIX, Validator_withdrawal_credentials(%rdi)
    sete    %al
    mov     %rax, (%rsi)
    RETURN_OK
END_FUNCTION lantern_has_eth1_withdrawal_credential

/* Locals: rsp+0 validator, rsp+8 out, rsp+16 the eth1 flag. */
FUNCTION lantern_has_execution_withdrawal_credential
    FRAME 32
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    lea     16(%rsp), %rsi
    call    lantern_has_eth1_withdrawal_credential
    mov     16(%rsp), %rax
    test    %rax, %rax
    jnz     1f
    mov     0(%rsp), %rdi
    mov     8(%rsp), %rsi
    call    lantern_has_compounding_withdrawal_credential
    UNFRAME 32
1:  mov     8(%rsp), %rsi
    mov     %rax, (%rsi)
    xor     %eax, %eax
    UNFRAME 32
END_FUNCTION lantern_has_execution_withdrawal_credential

/* Locals: rsp+0 validator, rsp+8 balance, rsp+16 epoch, rsp+24 out, rsp+32 the credential flag. */
FUNCTION lantern_is_fully_withdrawable_validator
    FRAME 48
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    mov     %rcx, 24(%rsp)
    lea     32(%rsp), %rsi
    call    lantern_has_execution_withdrawal_credential
    mov     0(%rsp), %rdi
    mov     32(%rsp), %rax
    mov     16(%rsp), %rdx
    mov     (%rdx), %rdx
    xor     %ecx, %ecx
    cmp     %rdx, Validator_withdrawable_epoch(%rdi)   # withdrawable_epoch <= epoch
    cmova   %rcx, %rax
    mov     8(%rsp), %rsi
    cmpq    $0, (%rsi)                      # and balance > 0
    cmove   %rcx, %rax
    mov     24(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
    UNFRAME 48
END_FUNCTION lantern_is_fully_withdrawable_validator

/* Locals: rsp+0 validator, rsp+8 balance, rsp+16 out, rsp+24 max effective balance, rsp+32 the credential flag. */
FUNCTION lantern_is_partially_withdrawable_validator
    FRAME 48
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    lea     24(%rsp), %rsi
    call    lantern_get_max_effective_balance
    mov     0(%rsp), %rdi
    lea     32(%rsp), %rsi
    call    lantern_has_execution_withdrawal_credential
    mov     0(%rsp), %rdi
    mov     8(%rsp), %rsi
    mov     32(%rsp), %rax                  # has_execution_withdrawal_credential
    mov     24(%rsp), %rdx                  # max_effective_balance
    xor     %ecx, %ecx
    cmp     %rdx, Validator_effective_balance(%rdi)    # has_max_effective_balance
    cmovne  %rcx, %rax
    cmp     %rdx, (%rsi)                    # has_excess_balance
    cmovbe  %rcx, %rax
    mov     16(%rsp), %rdx
    mov     %rax, (%rdx)
    xor     %eax, %eax
    UNFRAME 48
END_FUNCTION lantern_is_partially_withdrawable_validator

LEAF lantern_is_eligible_for_partial_withdrawals
    xor     %eax, %eax
    cmpq    $-1, Validator_exit_epoch(%rdi) # exit_epoch == FAR_FUTURE_EPOCH
    jne     1f
    MOVQ    %rcx, MIN_ACTIVATION_BALANCE
    cmp     %rcx, Validator_effective_balance(%rdi)    # and effective_balance >= MIN_ACTIVATION_BALANCE
    jb      1f
    cmp     %rcx, (%rsi)                    # and balance > MIN_ACTIVATION_BALANCE
    seta    %al
1:  mov     %rax, (%rdx)
    RETURN_OK
END_FUNCTION lantern_is_eligible_for_partial_withdrawals

LEAF lantern_get_pending_balance_to_withdraw
    mov     (%rsi), %rsi
    PART    %r8, %rcx, %rdi, BeaconState_pending_partial_withdrawals
    xor     %eax, %eax
1:  test    %rcx, %rcx
    jz      3f
    cmp     PendingPartialWithdrawal_validator_index(%r8), %rsi
    jne     2f
    add     PendingPartialWithdrawal_amount(%r8), %rax
    jc      4f
2:  add     $PendingPartialWithdrawal__mem, %r8
    dec     %rcx
    jmp     1b
3:  mov     %rax, (%rdx)
    RETURN_OK
4:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
END_FUNCTION lantern_get_pending_balance_to_withdraw

/* ---------------------------------------------------------------- Expected withdrawals */

LEAF lantern_get_balance_after_withdrawals
    mov     (%rsi), %rsi                    # validator_index
    mov     LIST_COUNT(%rdx), %r8
    lea     LIST_FIXED(%rdx), %r9
    xor     %eax, %eax                      # withdrawn
1:  test    %r8, %r8
    jz      3f
    cmp     Withdrawal_validator_index(%r9), %rsi
    jne     2f
    add     Withdrawal_amount(%r9), %rax
    jc      4f
2:  add     $Withdrawal__mem, %r9
    dec     %r8
    jmp     1b
3:  mov     BeaconState_balances(%rdi), %r8
    add     %rdi, %r8
    mov     (%r8,%rsi,8), %r8
    sub     %rax, %r8                       # state.balances[validator_index] - withdrawn
    jb      4f
    mov     %r8, (%rcx)
    RETURN_OK
4:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
END_FUNCTION lantern_get_balance_after_withdrawals

/*
 * The list all = prior + new, for get_balance_after_withdrawals: rdi = all (a Withdrawals value),
 * rsi = prior, rdx = new. Uses rax, rcx, rdi, rsi, r8. A leaf.
 */
LOCAL_FUNCTION concat_withdrawals
    UNWIND_END_PROLOGUE
    movq    $LIST_FIXED, LIST_OFFSET(%rdi)
    mov     LIST_COUNT(%rsi), %rax
    mov     LIST_COUNT(%rdx), %r8
    lea     (%rax,%r8), %rcx
    mov     %rcx, LIST_COUNT(%rdi)
    add     $LIST_FIXED, %rdi
    add     $LIST_FIXED, %rsi
    imul    $(Withdrawal__mem / 8), %rax, %rcx
    rep movsq
    lea     LIST_FIXED(%rdx), %rsi
    imul    $(Withdrawal__mem / 8), %r8, %rcx
    rep movsq
    ret
END_FUNCTION concat_withdrawals

/*
 * Append Withdrawal(index, validator_index, address of validator, amount) to Withdrawals rdi.
 * rsi index, rdx validator index, rcx validator, r8 amount.
 */
LOCAL_FUNCTION append_withdrawal
    UNWIND_END_PROLOGUE
    mov     LIST_COUNT(%rdi), %rax
    lea     1(%rax), %r9
    mov     %r9, LIST_COUNT(%rdi)
    imul    $Withdrawal__mem, %rax, %rax
    lea     LIST_FIXED(%rdi,%rax), %rax
    mov     %rsi, Withdrawal_index(%rax)
    mov     %rdx, Withdrawal_validator_index(%rax)
    movdqu  (Validator_withdrawal_credentials + 12)(%rcx), %xmm0   # address = withdrawal_credentials[12:]
    movdqu  %xmm0, Withdrawal_address(%rax)
    mov     (Validator_withdrawal_credentials + 28)(%rcx), %r9d
    mov     %r9d, (Withdrawal_address + 16)(%rax)
    movl    $0, (Withdrawal_address + 20)(%rax)                     # padding
    mov     %r8, Withdrawal_amount(%rax)
    ret
END_FUNCTION append_withdrawal

/*
 * rbx state, rbp withdrawal index, r12 prior, r13 out, r14 entry, r15 entries left,
 * S7 all, S8 limit, S9 processed. Locals: L epoch, L+8 validator index, L+16 balance, L+24 eligible.
 */
FUNCTION lantern_get_pending_partial_withdrawals
    ENTER 32
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    mov     %r8, %r13
    mov     (%rcx), %rax
    cmp     $SWEEP_SCRATCH, %rax
    jb      9f
    sub     $WLIST_BYTES, %rax
    add     %rcx, %rax
    mov     %rax, S7(%rsp)                  # all_withdrawals, at the end of scratch
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     LIST_COUNT(%r12), %rax          # withdrawals_limit
    lea     MAX_PENDING_PARTIALS_PER_WITHDRAWALS_SWEEP(%rax), %rcx
    mov     $(MAX_WITHDRAWALS_PER_PAYLOAD - 1), %edx
    cmp     %rdx, %rcx
    cmovae  %rdx, %rcx
    mov     %rcx, S8(%rsp)
    cmp     %rcx, %rax                      # assert len(prior_withdrawals) <= withdrawals_limit
    ja      8f
    movq    $WLIST_BYTES, (16 + LIST_SIZE)(%r13)    # withdrawals = []
    movq    $LIST_FIXED, (16 + LIST_OFFSET)(%r13)
    movq    $0, (16 + LIST_COUNT)(%r13)
    movq    $0, S9(%rsp)
    PART    %r14, %r15, %rbx, BeaconState_pending_partial_withdrawals
2:  test    %r15, %r15
    jz      5f
    mov     S7(%rsp), %rdi                  # all_withdrawals = prior_withdrawals + withdrawals
    mov     %r12, %rsi
    lea     16(%r13), %rdx
    call    concat_withdrawals
    mov     PendingPartialWithdrawal_withdrawable_epoch(%r14), %rax
    cmp     L(%rsp), %rax                   # not is_withdrawable
    ja      5f
    mov     S7(%rsp), %rax
    mov     LIST_COUNT(%rax), %rax
    cmp     S8(%rsp), %rax                  # or has_reached_limit
    jae     5f
    mov     PendingPartialWithdrawal_validator_index(%r14), %rax
    cmp     (BeaconState_validators + 8)(%rbx), %rax    # validator = state.validators[validator_index]
    jae     6f
    mov     %rax, (L + 8)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    mov     S7(%rsp), %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_get_balance_after_withdrawals
    test    %rax, %rax
    jnz     7f
    VALIDATOR %rdi, %rbx, (L+8)(%rsp)
    lea     (L + 16)(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    call    lantern_is_eligible_for_partial_withdrawals
    cmpq    $0, (L + 24)(%rsp)
    je      3f
    MOVQ    %rax, MIN_ACTIVATION_BALANCE    # min(balance - MIN_ACTIVATION_BALANCE, withdrawal.amount)
    mov     (L + 16)(%rsp), %r8
    sub     %rax, %r8
    mov     PendingPartialWithdrawal_amount(%r14), %rax
    cmp     %rax, %r8
    cmovae  %rax, %r8
    mov     (L + 8)(%rsp), %rdx
    VALIDATOR %rcx, %rbx, %rdx
    lea     16(%r13), %rdi
    mov     %rbp, %rsi
    call    append_withdrawal
    inc     %rbp
3:  incq    S9(%rsp)
    add     $PendingPartialWithdrawal__mem, %r14
    dec     %r15
    jmp     2b
5:  mov     %rbp, (%r13)
    mov     S9(%rsp), %rax
    mov     %rax, 8(%r13)
    xor     %eax, %eax
7:  LEAVE 32
6:  mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax
    LEAVE 32
8:  mov     $LANTERN_INVALID_WITHDRAWALS_LIMIT, %eax
    LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
END_FUNCTION lantern_get_pending_partial_withdrawals

/*
 * rbx state, rbp withdrawal index, r12 prior, r13 out, r14 validator index, r15 sweep left,
 * S7 all, S8 validator count, S9 processed.
 * Locals: L epoch, L+8 validator index, L+16 balance, L+24 predicate, L+32 max effective balance.
 */
FUNCTION lantern_get_validators_sweep_withdrawals
    ENTER 48
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    mov     %r8, %r13
    mov     (%rcx), %rax
    cmp     $SWEEP_SCRATCH, %rax
    jb      9f
    sub     $WLIST_BYTES, %rax
    add     %rcx, %rax
    mov     %rax, S7(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     (BeaconState_validators + 8)(%rbx), %rax
    mov     %rax, S8(%rsp)
    MOVQ    %r15, MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP
    cmp     %r15, %rax                      # validators_limit
    cmovb   %rax, %r15
    cmpq    $MAX_WITHDRAWALS_PER_PAYLOAD, LIST_COUNT(%r12)  # assert len(prior_withdrawals) < withdrawals_limit
    jae     8f
    movq    $WLIST_BYTES, (16 + LIST_SIZE)(%r13)
    movq    $LIST_FIXED, (16 + LIST_OFFSET)(%r13)
    movq    $0, (16 + LIST_COUNT)(%r13)
    movq    $0, S9(%rsp)
    mov     BeaconState_next_withdrawal_validator_index(%rbx), %r14
2:  test    %r15, %r15
    jz      5f
    mov     S7(%rsp), %rdi
    mov     %r12, %rsi
    lea     16(%r13), %rdx
    call    concat_withdrawals
    mov     S7(%rsp), %rax
    cmpq    $MAX_WITHDRAWALS_PER_PAYLOAD, LIST_COUNT(%rax)  # has_reached_limit
    jae     5f
    cmp     S8(%rsp), %r14
    jae     6f
    mov     %r14, (L + 8)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    mov     S7(%rsp), %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_get_balance_after_withdrawals
    test    %rax, %rax
    jnz     7f
    VALIDATOR %rdi, %rbx, %r14
    lea     (L + 16)(%rsp), %rsi
    lea     L(%rsp), %rdx
    lea     (L + 24)(%rsp), %rcx
    call    lantern_is_fully_withdrawable_validator
    cmpq    $0, (L + 24)(%rsp)
    je      3f
    mov     (L + 16)(%rsp), %r8             # amount = balance
    jmp     4f
3:  VALIDATOR %rdi, %rbx, %r14
    lea     (L + 16)(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    call    lantern_is_partially_withdrawable_validator
    cmpq    $0, (L + 24)(%rsp)
    je      41f
    VALIDATOR %rdi, %rbx, %r14
    lea     (L + 32)(%rsp), %rsi
    call    lantern_get_max_effective_balance
    mov     (L + 16)(%rsp), %r8             # amount = balance - get_max_effective_balance(validator)
    sub     (L + 32)(%rsp), %r8
4:  VALIDATOR %rcx, %rbx, %r14
    lea     16(%r13), %rdi
    mov     %rbp, %rsi
    mov     %r14, %rdx
    call    append_withdrawal
    inc     %rbp
41: inc     %r14                            # validator_index = (validator_index + 1) % len(state.validators)
    cmp     S8(%rsp), %r14
    jb      42f
    xor     %r14d, %r14d
42: incq    S9(%rsp)
    dec     %r15
    jmp     2b
5:  mov     %rbp, (%r13)
    mov     S9(%rsp), %rax
    mov     %rax, 8(%r13)
    xor     %eax, %eax
7:  LEAVE 48
6:  mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax
    LEAVE 48
8:  mov     $LANTERN_INVALID_WITHDRAWALS_LIMIT, %eax
    LEAVE 48
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
END_FUNCTION lantern_get_validators_sweep_withdrawals

/* rbx state, rbp scratch, r12 out, r13 scratch size, r14 the partial sweep, r15 the validator sweep. Locals: L withdrawal index. */
FUNCTION lantern_get_expected_withdrawals
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rbp), %r13
    cmp     $EXPECTED_SCRATCH, %r13
    jb      9f
    mov     %r13, %rax
    sub     $SWEEP_BYTES, %rax
    lea     (%rbp,%rax), %r14
    sub     $SWEEP_BYTES, %rax
    lea     (%rbp,%rax), %r15
    movq    $WLIST_BYTES, (16 + LIST_SIZE)(%r12)    # withdrawals = []
    movq    $LIST_FIXED, (16 + LIST_OFFSET)(%r12)
    movq    $0, (16 + LIST_COUNT)(%r12)
    mov     BeaconState_next_withdrawal_index(%rbx), %rax
    mov     %rax, L(%rsp)
    lea     -(2 * SWEEP_BYTES)(%r13), %rax
    mov     %rax, (%rbp)
    mov     %rbx, %rdi                      # get_pending_partial_withdrawals(state, withdrawal_index, withdrawals)
    lea     L(%rsp), %rsi
    lea     16(%r12), %rdx
    mov     %rbp, %rcx
    mov     %r14, %r8
    call    lantern_get_pending_partial_withdrawals
    test    %rax, %rax
    jnz     7f
    lea     16(%r12), %rdi                  # withdrawals.extend(partial_withdrawals)
    lea     16(%r12), %rsi
    lea     16(%r14), %rdx
    call    concat_withdrawals
    lea     -(2 * SWEEP_BYTES)(%r13), %rax
    mov     %rax, (%rbp)
    mov     %rbx, %rdi                      # get_validators_sweep_withdrawals(state, withdrawal_index, withdrawals)
    mov     %r14, %rsi
    lea     16(%r12), %rdx
    mov     %rbp, %rcx
    mov     %r15, %r8
    call    lantern_get_validators_sweep_withdrawals
    test    %rax, %rax
    jnz     7f
    lea     16(%r12), %rdi
    lea     16(%r12), %rsi
    lea     16(%r15), %rdx
    call    concat_withdrawals
    mov     8(%r14), %rax
    mov     %rax, (%r12)                    # processed_partial_withdrawals_count
    mov     8(%r15), %rax
    mov     %rax, 8(%r12)                   # processed_sweep_withdrawals_count
    xor     %eax, %eax
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION lantern_get_expected_withdrawals

/* ---------------------------------------------------------------- Applying withdrawals */

/* rbx state, rbp entry, r12 entries left. */
FUNCTION lantern_apply_withdrawals
    ENTER 16
    mov     %rdi, %rbx
    lea     LIST_FIXED(%rsi), %rbp
    mov     LIST_COUNT(%rsi), %r12
1:  test    %r12, %r12
    jz      2f
    mov     %rbx, %rdi
    lea     Withdrawal_validator_index(%rbp), %rsi
    lea     Withdrawal_amount(%rbp), %rdx
    call    lantern_decrease_balance
    add     $Withdrawal__mem, %rbp
    dec     %r12
    jmp     1b
2:  xor     %eax, %eax
    LEAVE 16
END_FUNCTION lantern_apply_withdrawals

LEAF lantern_update_next_withdrawal_index
    mov     LIST_COUNT(%rsi), %rax
    test    %rax, %rax
    jz      1f
    dec     %rax
    imul    $Withdrawal__mem, %rax, %rax
    mov     (LIST_FIXED + Withdrawal_index)(%rsi,%rax), %rax
    inc     %rax
    mov     %rax, BeaconState_next_withdrawal_index(%rdi)
1:  RETURN_OK
END_FUNCTION lantern_update_next_withdrawal_index

LEAF lantern_update_pending_partial_withdrawals
    mov     (%rsi), %rax
    test    %rax, %rax
    jz      1f
    PART    %r8, %rcx, %rdi, BeaconState_pending_partial_withdrawals
    sub     %rax, %rcx
    mov     %rcx, (BeaconState_pending_partial_withdrawals + 8)(%rdi)
    imul    $PendingPartialWithdrawal__mem, %rax, %rsi
    add     %r8, %rsi
    imul    $PendingPartialWithdrawal__mem, %rcx, %rdx
    mov     %r8, %rdi
    jmp     lantern_copy
1:  RETURN_OK
END_FUNCTION lantern_update_pending_partial_withdrawals

LEAF lantern_update_next_withdrawal_validator_index
    mov     LIST_COUNT(%rsi), %rax
    cmp     $MAX_WITHDRAWALS_PER_PAYLOAD, %rax
    jne     1f
    dec     %rax                            # (withdrawals[-1].validator_index + 1) % len(state.validators)
    imul    $Withdrawal__mem, %rax, %rax
    mov     (LIST_FIXED + Withdrawal_validator_index)(%rsi,%rax), %rax
    inc     %rax
    jmp     2f
1:  mov     BeaconState_next_withdrawal_validator_index(%rdi), %rax
    add     $MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP, %rax
2:  xor     %edx, %edx
    divq    (BeaconState_validators + 8)(%rdi)
    mov     %rdx, BeaconState_next_withdrawal_validator_index(%rdi)
    RETURN_OK
END_FUNCTION lantern_update_next_withdrawal_validator_index

/* ---------------------------------------------------------------- process_withdrawals */

/* rbx state, rbp payload, r12 scratch, r13 result, r14 expected, r15 scratch size. */
FUNCTION lantern_process_withdrawals
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     (%r12), %r15
    cmp     $(EXPECTED_SCRATCH + SWEEP_BYTES), %r15
    jb      9f
    lea     -SWEEP_BYTES(%r15), %rax
    lea     (%r12,%rax), %r14
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # expected = get_expected_withdrawals(state)
    mov     %r12, %rsi
    mov     %r14, %rdx
    call    lantern_get_expected_withdrawals
    CHECK_STATUS %r13, 7f, 8f
    PART    %rsi, %rcx, %rbp, ExecutionPayload_withdrawals  # assert list(payload.withdrawals) == expected.withdrawals
    cmp     (16 + LIST_COUNT)(%r14), %rcx
    jne     6f
    lea     (16 + LIST_FIXED)(%r14), %rdx
1:  test    %rcx, %rcx
    jz      2f
    mov     Withdrawal_index(%rsi), %rax
    cmp     Withdrawal_index(%rdx), %rax
    jne     6f
    mov     Withdrawal_validator_index(%rsi), %rax
    cmp     Withdrawal_validator_index(%rdx), %rax
    jne     6f
    mov     Withdrawal_address(%rsi), %rax  # address: 20 bytes
    cmp     Withdrawal_address(%rdx), %rax
    jne     6f
    mov     (Withdrawal_address + 8)(%rsi), %rax
    cmp     (Withdrawal_address + 8)(%rdx), %rax
    jne     6f
    mov     (Withdrawal_address + 16)(%rsi), %eax
    cmp     (Withdrawal_address + 16)(%rdx), %eax
    jne     6f
    mov     Withdrawal_amount(%rsi), %rax
    cmp     Withdrawal_amount(%rdx), %rax
    jne     6f
    add     $Withdrawal__mem, %rsi
    add     $Withdrawal__mem, %rdx
    dec     %rcx
    jmp     1b
2:  mov     %rbx, %rdi
    lea     16(%r14), %rsi
    call    lantern_apply_withdrawals
    mov     %rbx, %rdi
    lea     16(%r14), %rsi
    call    lantern_update_next_withdrawal_index
    mov     %rbx, %rdi
    mov     %r14, %rsi                      # processed_partial_withdrawals_count
    call    lantern_update_pending_partial_withdrawals
    mov     %rbx, %rdi
    lea     16(%r14), %rsi
    call    lantern_update_next_withdrawal_validator_index
    movq    $0, (%r13)
8:  xor     %eax, %eax
7:  LEAVE 16
6:  movq    $LANTERN_INVALID_WITHDRAWALS, (%r13)
    xor     %eax, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION lantern_process_withdrawals
