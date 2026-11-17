/*
 * Exits, credential changes and execution layer requests, x86-64.
 * Requirements: docs/reference/block-processing.md.
 */

/* Append the PendingDeposit at rsi to state rdi; rax = LANTERN_BUFFER_TOO_SMALL when it has no room. */
LOCAL_FUNCTION append_pending_deposit
    UNWIND_END_PROLOGUE
    mov     BeaconState_pending_deposits(%rdi), %rax
    mov     (BeaconState_pending_deposits + 8)(%rdi), %rcx
    mov     BeaconState_pending_partial_withdrawals(%rdi), %rdx
    sub     %rax, %rdx
    lea     1(%rcx), %r8
    imul    $PendingDeposit__mem, %r8, %r9
    cmp     %rdx, %r9
    ja      9f
    mov     %r8, (BeaconState_pending_deposits + 8)(%rdi)
    imul    $PendingDeposit__mem, %rcx, %rcx
    add     %rcx, %rax
    add     %rax, %rdi
    mov     $PendingDeposit__mem, %edx
    jmp     lantern_copy
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    ret
END_FUNCTION append_pending_deposit

/* ---------------------------------------------------------------- Voluntary exits and credential changes */

/*
 * rbx state, rbp signed exit, r12 config, r13 scratch, r14 result, r15 validator.
 * Locals: L epoch, L+8 predicate, L+16 domain type, L+24 domain (32), L+56 signing root as a ByteList (24 + 32), L+112 pending.
 */
SPEC_FUNCTION process_voluntary_exit
    ENTER 128
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    NEED_SCRATCH %r13, %rbx, 1, 9f
    mov     (SignedVoluntaryExit_message + VoluntaryExit_validator_index)(%rbp), %rcx
    mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax  # state.validators[voluntary_exit.validator_index]
    cmp     (BeaconState_validators + 8)(%rbx), %rcx
    jae     6f
    VALIDATOR %r15, %rbx, %rcx
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     %r15, %rdi                      # assert is_active_validator(validator, current epoch)
    lea     L(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_is_active_validator
    mov     $LANTERN_INVALID_VOLUNTARY_EXIT, %eax
    cmpq    $0, (L + 8)(%rsp)
    je      6f
    cmpq    $-1, Validator_exit_epoch(%r15) # assert validator.exit_epoch == FAR_FUTURE_EPOCH
    jne     6f
    mov     L(%rsp), %rcx                   # assert current epoch >= voluntary_exit.epoch
    cmp     (SignedVoluntaryExit_message + VoluntaryExit_epoch)(%rbp), %rcx
    jb      6f
    mov     Validator_activation_epoch(%r15), %rdx  # assert current epoch >= activation_epoch + SHARD_COMMITTEE_PERIOD
    add     CONFIG_SHARD_COMMITTEE_PERIOD(%r12), %rdx
    jc      5f
    cmp     %rdx, %rcx
    jb      6f
    mov     %rbx, %rdi                      # assert get_pending_balance_to_withdraw(state, index) == 0
    lea     (SignedVoluntaryExit_message + VoluntaryExit_validator_index)(%rbp), %rsi
    lea     (L + 112)(%rsp), %rdx
    call    lantern_get_pending_balance_to_withdraw
    CHECK_STATUS %r14, 7f, 8f
    mov     $LANTERN_INVALID_VOLUNTARY_EXIT, %eax
    cmpq    $0, (L + 112)(%rsp)
    jne     6f
    movl    $DOMAIN_VOLUNTARY_EXIT, (L + 16)(%rsp)  # domain = compute_domain(DOMAIN_VOLUNTARY_EXIT, CAPELLA_FORK_VERSION, gvr)
    lea     (L + 16)(%rsp), %rdi
    lea     CONFIG_CAPELLA_FORK_VERSION(%r12), %rsi
    lea     BeaconState_genesis_validators_root(%rbx), %rdx
    mov     %r13, %rcx
    lea     (L + 24)(%rsp), %r8
    call    lantern_compute_domain
    test    %rax, %rax
    jnz     7f
    ADDRESS %rdi, lantern_type_VoluntaryExit
    lea     SignedVoluntaryExit_message(%rbp), %rsi
    lea     (L + 24)(%rsp), %rdx
    mov     %r13, %rcx
    lea     (L + 80)(%rsp), %r8
    call    lantern_compute_signing_root
    test    %rax, %rax
    jnz     7f
    lea     Validator_pubkey(%r15), %rdi    # bls.Verify(validator.pubkey, signing_root, signature)
    lea     SignedVoluntaryExit_signature(%rbp), %rsi
    lea     (L + 56)(%rsp), %rdx
    mov     %r13, %rcx
    call    verify_root_signature
    test    %rax, %rax
    jnz     7f
    mov     $LANTERN_INVALID_VOLUNTARY_EXIT, %eax
    test    %rdx, %rdx
    jz      6f
    mov     %rbx, %rdi                      # initiate_validator_exit(state, voluntary_exit.validator_index)
    lea     (SignedVoluntaryExit_message + VoluntaryExit_validator_index)(%rbp), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    lantern_initiate_validator_exit
    jmp     7f
8:  xor     %eax, %eax
7:  LEAVE 128
5:  mov     $LANTERN_INVALID_OVERFLOW, %eax
6:  mov     %rax, (%r14)
    xor     %eax, %eax
    LEAVE 128
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 128
SPEC_END process_voluntary_exit

/*
 * L0: verify a BLS signature over a signing root. rdi public key, rsi signature,
 * rdx a 56-byte buffer whose last 32 bytes hold the root (its first 24 become a
 * ByteList header), rcx scratch. Returns rax status, rdx valid. Locals: rsp+0 valid.
 */
LOCAL_FUNCTION verify_root_signature
    FRAME 16
    movq    $56, (%rdx)
    movq    $24, 8(%rdx)
    movq    $32, 16(%rdx)
    mov     %rsi, %rax
    mov     %rdx, %rsi
    mov     %rax, %rdx
    mov     %rsp, %r8
    CALL_GLOBAL crypto_bls_verify           # bls.Verify(public_key, signing_root, signature)
    mov     0(%rsp), %rdx
    UNFRAME 16
END_FUNCTION verify_root_signature

/*
 * rbx state, rbp signed change, r12 config, r13 scratch, r14 result, r15 validator.
 * Locals: L digest (32), L+56 ByteList header (24), L+80 signing root (32),
 * L+112 domain type, L+128 domain (32).
 */
SPEC_FUNCTION process_bls_to_execution_change
    ENTER 176
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    NEED_SCRATCH %r13, %rbx, 0, 9f
    mov     (SignedBLSToExecutionChange_message + BLSToExecutionChange_validator_index)(%rbp), %rcx
    mov     $LANTERN_INVALID_BLS_CHANGE, %eax   # assert address_change.validator_index < len(state.validators)
    cmp     (BeaconState_validators + 8)(%rbx), %rcx
    jae     6f
    VALIDATOR %r15, %rbx, %rcx
    cmpb    $BLS_WITHDRAWAL_PREFIX, Validator_withdrawal_credentials(%r15)  # assert prefix == BLS_WITHDRAWAL_PREFIX
    jne     6f
    lea     (SignedBLSToExecutionChange_message + BLSToExecutionChange_from_bls_pubkey)(%rbp), %rdi
    mov     $48, %esi
    lea     L(%rsp), %rdx
    call    sha256_short                    # assert withdrawal_credentials[1:] == sha256(from_bls_pubkey)[1:]
    movb    $BLS_WITHDRAWAL_PREFIX, L(%rsp) # the digest with its first byte set to the prefix just checked
    lea     Validator_withdrawal_credentials(%r15), %rcx
    lea     L(%rsp), %rdx
    mov     $LANTERN_INVALID_BLS_CHANGE, %eax
    NE32    %rcx, %rdx, 6f
    movl    $DOMAIN_BLS_TO_EXECUTION_CHANGE, (L + 112)(%rsp)   # compute_domain(DOMAIN_BLS_TO_EXECUTION_CHANGE, GENESIS_FORK_VERSION, gvr)
    lea     (L + 112)(%rsp), %rdi
    lea     CONFIG_GENESIS_FORK_VERSION(%r12), %rsi
    lea     BeaconState_genesis_validators_root(%rbx), %rdx
    mov     %r13, %rcx
    lea     (L + 128)(%rsp), %r8
    call    lantern_compute_domain
    test    %rax, %rax
    jnz     7f
    ADDRESS %rdi, lantern_type_BLSToExecutionChange
    lea     SignedBLSToExecutionChange_message(%rbp), %rsi
    lea     (L + 128)(%rsp), %rdx
    mov     %r13, %rcx
    lea     (L + 80)(%rsp), %r8
    call    lantern_compute_signing_root
    test    %rax, %rax
    jnz     7f
    lea     (SignedBLSToExecutionChange_message + BLSToExecutionChange_from_bls_pubkey)(%rbp), %rdi
    lea     SignedBLSToExecutionChange_signature(%rbp), %rsi
    lea     (L + 56)(%rsp), %rdx
    mov     %r13, %rcx
    call    verify_root_signature
    test    %rax, %rax
    jnz     7f
    mov     $LANTERN_INVALID_BLS_CHANGE, %eax
    test    %rdx, %rdx
    jz      6f
    lea     Validator_withdrawal_credentials(%r15), %rcx    # 0x01, 11 zero bytes, to_execution_address
    movq    $ETH1_ADDRESS_WITHDRAWAL_PREFIX, (%rcx)
    movl    $0, 8(%rcx)
    lea     (SignedBLSToExecutionChange_message + BLSToExecutionChange_to_execution_address)(%rbp), %rdx
    movdqu  (%rdx), %xmm0
    movdqu  %xmm0, 12(%rcx)
    mov     16(%rdx), %eax
    mov     %eax, 28(%rcx)
    movq    $0, (%r14)
    xor     %eax, %eax
7:  LEAVE 176
6:  mov     %rax, (%r14)
    xor     %eax, %eax
    LEAVE 176
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 176
SPEC_END process_bls_to_execution_change

/* ---------------------------------------------------------------- Execution layer requests */

/* rbx state, rbp result. Locals: L the PendingDeposit. */
SPEC_FUNCTION process_deposit_request
    ENTER 192
    mov     %rdi, %rbx
    mov     %r8, %rbp
    lea     L(%rsp), %rdi                   # PendingDeposit(pubkey, withdrawal_credentials, amount, signature, slot=state.slot)
    mov     $(DepositRequest_signature + 96), %edx
    call    lantern_copy
    mov     BeaconState_slot(%rbx), %rax
    mov     %rax, (L + PendingDeposit_slot)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    append_pending_deposit
    test    %rax, %rax
    jnz     7f
    movq    $0, (%rbp)
7:  LEAVE 192
SPEC_END process_deposit_request

.if (DepositRequest_pubkey != PendingDeposit_pubkey) || (DepositRequest_withdrawal_credentials != PendingDeposit_withdrawal_credentials) || (DepositRequest_amount != PendingDeposit_amount) || (DepositRequest_signature != PendingDeposit_signature) || (PendingDeposit_slot != DepositRequest_signature + 96) || (PendingDeposit__mem > 192)
.error "process_deposit_request copies a DepositRequest's first fields into a PendingDeposit"
.endif

/* Branch to label when the 20 bytes at addr differ from credentials[12:] of validator. Uses r11. */
.macro DIFF_ADDRESS addr, validator, label
    mov     (\addr), %r11
    cmp     (Validator_withdrawal_credentials + 12)(\validator), %r11
    jne     \label
    mov     8(\addr), %r11
    cmp     (Validator_withdrawal_credentials + 20)(\validator), %r11
    jne     \label
    mov     16(\addr), %r11d
    cmp     (Validator_withdrawal_credentials + 28)(\validator), %r11d
    jne     \label
.endm

/* Branch to label when the 48 bytes at a and at b differ. Uses xmm0-xmm2, r11. */
.macro NE48 a, b, label
    NE32    \a, \b, \label
    mov     32(\a), %r11
    cmp     32(\b), %r11
    jne     \label
    mov     40(\a), %r11
    cmp     40(\b), %r11
    jne     \label
.endm

/* Branch to fail when state rbx has no room for one more pending deposit. */
.macro DEPOSIT_ROOM fail
    mov     BeaconState_pending_deposits(%rbx), %rax
    mov     (BeaconState_pending_deposits + 8)(%rbx), %rcx
    mov     BeaconState_pending_partial_withdrawals(%rbx), %rdx
    sub     %rax, %rdx
    inc     %rcx
    imul    $PendingDeposit__mem, %rcx, %rcx
    cmp     %rdx, %rcx
    ja      \fail
.endm

/*
 * rbx state, rbp request, r12 config, r13 scratch, r14 result, r15 validator,
 * S8 amount, S9 pending balance. Locals: L epoch, L+8 predicate, L+16 index, L+24 pending,
 * L+32 to_withdraw, L+40 exit queue epoch.
 */
SPEC_FUNCTION process_withdrawal_request
    ENTER 80
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    NEED_SCRATCH %r13, %rbx, 1, 9f
    mov     BeaconState_pending_partial_withdrawals(%rbx), %rax    # room for one pending partial withdrawal
    mov     (BeaconState_pending_partial_withdrawals + 8)(%rbx), %rcx
    mov     BeaconState_pending_consolidations(%rbx), %rdx
    sub     %rax, %rdx
    inc     %rcx
    imul    $PendingPartialWithdrawal__mem, %rcx, %rcx
    cmp     %rdx, %rcx
    ja      9f
    movq    $0, (%r14)
    mov     WithdrawalRequest_amount(%rbp), %rax
    mov     %rax, S8(%rsp)
    MOVQ    %rcx, PENDING_PARTIAL_WITHDRAWALS_LIMIT
    cmp     %rcx, (BeaconState_pending_partial_withdrawals + 8)(%rbx)  # queue full, and not a full exit
    jne     1f
    cmp     $FULL_EXIT_REQUEST_AMOUNT, %rax
    jne     8f
1:  mov     %rbx, %rdi
    lea     WithdrawalRequest_validator_pubkey(%rbp), %rsi
    call    find_pubkey
    cmp     $-1, %rax
    je      8f
    mov     %rax, (L + 16)(%rsp)
    VALIDATOR %r15, %rbx, %rax
    mov     %r15, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_has_execution_withdrawal_credential
    cmpq    $0, (L + 8)(%rsp)
    je      8f
    lea     WithdrawalRequest_source_address(%rbp), %rax
    DIFF_ADDRESS %rax, %r15, 8f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     %r15, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_is_active_validator
    cmpq    $0, (L + 8)(%rsp)
    je      8f
    cmpq    $-1, Validator_exit_epoch(%r15)
    jne     8f
    mov     Validator_activation_epoch(%r15), %rax
    add     CONFIG_SHARD_COMMITTEE_PERIOD(%r12), %rax
    jc      5f
    cmp     %rax, L(%rsp)
    jb      8f
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    call    lantern_get_pending_balance_to_withdraw
    CHECK_STATUS %r14, 7f, 8f
    mov     (L + 24)(%rsp), %rax
    mov     %rax, S9(%rsp)
    cmpq    $0, S8(%rsp)
    jne     2f
    test    %rax, %rax                      # a full exit, when nothing is pending
    jnz     8f
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    lantern_initiate_validator_exit
    jmp     7f
2:  mov     %r15, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_has_compounding_withdrawal_credential
    cmpq    $0, (L + 8)(%rsp)
    je      8f
    MOVQ    %rcx, MIN_ACTIVATION_BALANCE
    cmp     %rcx, Validator_effective_balance(%r15)    # has_sufficient_effective_balance
    jb      8f
    mov     BeaconState_balances(%rbx), %rdx
    add     %rbx, %rdx
    mov     (L + 16)(%rsp), %rax
    mov     (%rdx,%rax,8), %rdx             # balance
    add     S9(%rsp), %rcx                  # has_excess_balance: balance > MIN_ACTIVATION_BALANCE + pending
    jc      5f
    cmp     %rcx, %rdx
    jbe     8f
    sub     %rcx, %rdx                      # to_withdraw = min(balance - MIN_ACTIVATION_BALANCE - pending, amount)
    mov     S8(%rsp), %rax
    cmp     %rax, %rdx
    cmovae  %rax, %rdx
    mov     %rdx, (L + 32)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 32)(%rsp), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    lea     (L + 40)(%rsp), %r8
    mov     %r14, %r9
    call    lantern_compute_exit_epoch_and_update_churn
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r14)
    jne     8f
    mov     (L + 40)(%rsp), %rax            # withdrawable_epoch = exit_queue_epoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY
    add     CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY(%r12), %rax
    jc      5f
    PART    %rdx, %rcx, %rbx, BeaconState_pending_partial_withdrawals
    imul    $PendingPartialWithdrawal__mem, %rcx, %rsi
    add     %rsi, %rdx
    mov     (L + 16)(%rsp), %rsi
    mov     %rsi, PendingPartialWithdrawal_validator_index(%rdx)
    mov     (L + 32)(%rsp), %rsi
    mov     %rsi, PendingPartialWithdrawal_amount(%rdx)
    mov     %rax, PendingPartialWithdrawal_withdrawable_epoch(%rdx)
    inc     %rcx
    mov     %rcx, (BeaconState_pending_partial_withdrawals + 8)(%rbx)
8:  xor     %eax, %eax
7:  LEAVE 80
5:  movq    $LANTERN_INVALID_OVERFLOW, (%r14)
    xor     %eax, %eax
    LEAVE 80
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 80
SPEC_END process_withdrawal_request

/* rbx state, rbp request, r12 out, r13 validator. Locals: L epoch, L+8 predicate. */
SPEC_FUNCTION is_valid_switch_to_compounding_request
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    movq    $0, (%r12)
    lea     ConsolidationRequest_source_pubkey(%rbp), %rax  # source_pubkey == target_pubkey
    lea     ConsolidationRequest_target_pubkey(%rbp), %rcx
    NE48    %rax, %rcx, 8f
    mov     %rbx, %rdi
    lea     ConsolidationRequest_source_pubkey(%rbp), %rsi
    call    find_pubkey
    cmp     $-1, %rax
    je      8f
    VALIDATOR %r13, %rbx, %rax
    lea     ConsolidationRequest_source_address(%rbp), %rax
    DIFF_ADDRESS %rax, %r13, 8f
    mov     %r13, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_has_eth1_withdrawal_credential
    cmpq    $0, (L + 8)(%rsp)
    je      8f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     %r13, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_is_active_validator
    cmpq    $0, (L + 8)(%rsp)
    je      8f
    cmpq    $-1, Validator_exit_epoch(%r13)
    jne     8f
    movq    $1, (%r12)
8:  xor     %eax, %eax
    LEAVE 16
SPEC_END is_valid_switch_to_compounding_request

/* rbx state, rbp index. Locals: L the PendingDeposit (PendingDeposit__mem). */
SPEC_FUNCTION queue_excess_active_balance
    ENTER 192
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     BeaconState_balances(%rbx), %rcx
    add     %rbx, %rcx
    lea     (%rcx,%rbp,8), %rcx             # &balances[index]
    MOVQ    %rdx, MIN_ACTIVATION_BALANCE
    mov     (%rcx), %rax
    cmp     %rdx, %rax
    jbe     8f
    mov     BeaconState_pending_deposits(%rbx), %r8     # room first: the state must not change on failure
    mov     (BeaconState_pending_deposits + 8)(%rbx), %r9
    mov     BeaconState_pending_partial_withdrawals(%rbx), %rsi
    sub     %r8, %rsi
    inc     %r9
    imul    $PendingDeposit__mem, %r9, %r9
    cmp     %rsi, %r9
    ja      9f
    sub     %rdx, %rax                      # excess_balance
    mov     %rax, (L + PendingDeposit_amount)(%rsp)
    mov     %rdx, (%rcx)                    # balances[index] = MIN_ACTIVATION_BALANCE
    VALIDATOR %rsi, %rbx, %rbp
    lea     (L + PendingDeposit_pubkey)(%rsp), %rdi
    add     $Validator_pubkey, %rsi
    mov     $(48 + 32), %edx                # pubkey and withdrawal_credentials
    call    lantern_copy
    lea     (L + PendingDeposit_signature)(%rsp), %rdi  # G2_POINT_AT_INFINITY
    mov     $96, %esi
    call    lantern_zero
    movb    $0xc0, (L + PendingDeposit_signature)(%rsp)
    movq    $GENESIS_SLOT, (L + PendingDeposit_slot)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    append_pending_deposit
    LEAVE 192
8:  xor     %eax, %eax
    LEAVE 192
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 192
SPEC_END queue_excess_active_balance

.if (Validator_withdrawal_credentials != Validator_pubkey + 48) || (PendingDeposit_withdrawal_credentials != PendingDeposit_pubkey + 48)
.error "lantern_queue_excess_active_balance copies pubkey and credentials together"
.endif

/* rbx state, rbp index pointer. */
SPEC_FUNCTION switch_to_compounding_validator
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    DEPOSIT_ROOM 9f                         # room for the excess deposit, before any change
    VALIDATOR %rax, %rbx, (%rbp)
    movb    $COMPOUNDING_WITHDRAWAL_PREFIX, Validator_withdrawal_credentials(%rax)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    call    lantern_queue_excess_active_balance
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END switch_to_compounding_validator

/*
 * rbx state, rbp balance, r12 config, r13 scratch, r14 out, r15 result, S7 earliest.
 * Locals: L current epoch, L+8 activation exit epoch, L+16 churn.
 */
SPEC_FUNCTION compute_consolidation_epoch_and_update_churn
    ENTER 32
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    NEED_SCRATCH %r13, %rbx, 1, 9f
    movq    $0, (%r15)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    lea     L(%rsp), %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_compute_activation_exit_epoch
    mov     BeaconState_earliest_consolidation_epoch(%rbx), %rax
    mov     (L + 8)(%rsp), %rcx
    cmp     %rcx, %rax
    cmovb   %rcx, %rax
    mov     %rax, S7(%rsp)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %r13, %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_get_consolidation_churn_limit
    test    %rax, %rax
    jnz     7f
    mov     S7(%rsp), %rsi                  # earliest_consolidation_epoch
    mov     (L + 16)(%rsp), %rdi            # per_epoch_consolidation_churn
    mov     BeaconState_consolidation_balance_to_consume(%rbx), %r8
    cmp     %rsi, BeaconState_earliest_consolidation_epoch(%rbx)
    jae     2f
    mov     %rdi, %r8
2:  cmp     %r8, %rbp
    jbe     3f
    test    %rdi, %rdi                      # the spec divides by the churn
    jz      6f
    mov     %rbp, %rax
    sub     %r8, %rax
    dec     %rax
    xor     %edx, %edx
    div     %rdi
    inc     %rax
    add     %rax, %rsi
    jc      6f
    mul     %rdi
    test    %rdx, %rdx
    jnz     6f
    add     %rax, %r8
    jc      6f
3:  sub     %rbp, %r8
    mov     %r8, BeaconState_consolidation_balance_to_consume(%rbx)
    mov     %rsi, BeaconState_earliest_consolidation_epoch(%rbx)
    mov     %rsi, (%r14)
    xor     %eax, %eax
7:  LEAVE 32
6:  movq    $LANTERN_INVALID_OVERFLOW, (%r15)
    xor     %eax, %eax
    LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
SPEC_END compute_consolidation_epoch_and_update_churn

/*
 * rbx state, rbp request, r12 config, r13 scratch, r14 result, r15 source,
 * S7 target, S8 source index, S9 target index. Locals: L predicate, L+8 epoch, L+16 churn,
 * L+24 pending, L+32 index, L+40 exit epoch.
 */
SPEC_FUNCTION process_consolidation_request
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    NEED_SCRATCH %r13, %rbx, 1, 9f
    DEPOSIT_ROOM 9f                         # room: one pending deposit or one pending consolidation
    mov     BeaconState_pending_consolidations(%rbx), %rax
    mov     (BeaconState_pending_consolidations + 8)(%rbx), %rcx
    mov     (%rbx), %rdx
    sub     %rax, %rdx
    inc     %rcx
    shl     $4, %rcx
    cmp     %rdx, %rcx
    ja      9f
    movq    $0, (%r14)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    lea     L(%rsp), %rdx
    call    lantern_is_valid_switch_to_compounding_request
    cmpq    $0, L(%rsp)
    je      1f
    mov     %rbx, %rdi                      # switch_to_compounding_validator(state, source_index)
    lea     ConsolidationRequest_source_pubkey(%rbp), %rsi
    call    find_pubkey
    mov     %rax, (L + 32)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 32)(%rsp), %rsi
    call    lantern_switch_to_compounding_validator
    jmp     7f
1:  lea     ConsolidationRequest_source_pubkey(%rbp), %rax  # source_pubkey == target_pubkey: return
    lea     ConsolidationRequest_target_pubkey(%rbp), %rcx
    NE48    %rax, %rcx, 2f
    jmp     8f
2:  MOVQ    %rcx, PENDING_CONSOLIDATIONS_LIMIT
    cmp     %rcx, (BeaconState_pending_consolidations + 8)(%rbx)
    je      8f
    mov     %rbx, %rdi                      # get_consolidation_churn_limit(state) <= MIN_ACTIVATION_BALANCE: return
    mov     %r12, %rsi
    mov     %r13, %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_get_consolidation_churn_limit
    test    %rax, %rax
    jnz     7f
    MOVQ    %rcx, MIN_ACTIVATION_BALANCE
    cmp     %rcx, (L + 16)(%rsp)
    jbe     8f
    mov     %rbx, %rdi
    lea     ConsolidationRequest_source_pubkey(%rbp), %rsi
    call    find_pubkey
    cmp     $-1, %rax
    je      8f
    mov     %rax, S8(%rsp)
    mov     %rbx, %rdi
    lea     ConsolidationRequest_target_pubkey(%rbp), %rsi
    call    find_pubkey
    cmp     $-1, %rax
    je      8f
    mov     %rax, S9(%rsp)
    VALIDATOR %rcx, %rbx, %rax
    mov     %rcx, S7(%rsp)
    VALIDATOR %r15, %rbx, S8(%rsp)
    mov     %r15, %rdi
    lea     L(%rsp), %rsi
    call    lantern_has_execution_withdrawal_credential
    cmpq    $0, L(%rsp)
    je      8f
    lea     ConsolidationRequest_source_address(%rbp), %rax
    DIFF_ADDRESS %rax, %r15, 8f
    mov     S7(%rsp), %rdi
    lea     L(%rsp), %rsi
    call    lantern_has_compounding_withdrawal_credential
    cmpq    $0, L(%rsp)
    je      8f
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     %r15, %rdi
    lea     (L + 8)(%rsp), %rsi
    lea     L(%rsp), %rdx
    call    lantern_is_active_validator
    cmpq    $0, L(%rsp)
    je      8f
    mov     S7(%rsp), %rdi
    lea     (L + 8)(%rsp), %rsi
    lea     L(%rsp), %rdx
    call    lantern_is_active_validator
    cmpq    $0, L(%rsp)
    je      8f
    cmpq    $-1, Validator_exit_epoch(%r15)
    jne     8f
    mov     S7(%rsp), %rax
    cmpq    $-1, Validator_exit_epoch(%rax)
    jne     8f
    mov     Validator_activation_epoch(%r15), %rax
    add     CONFIG_SHARD_COMMITTEE_PERIOD(%r12), %rax
    jc      5f
    cmp     %rax, (L + 8)(%rsp)
    jb      8f
    mov     S8(%rsp), %rax
    mov     %rax, (L + 32)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 32)(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    call    lantern_get_pending_balance_to_withdraw
    CHECK_STATUS %r14, 7f, 8f
    cmpq    $0, (L + 24)(%rsp)
    jne     8f
    mov     %rbx, %rdi                      # source.exit_epoch = compute_consolidation_epoch_and_update_churn(...)
    lea     Validator_effective_balance(%r15), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    lea     (L + 40)(%rsp), %r8
    mov     %r14, %r9
    call    lantern_compute_consolidation_epoch_and_update_churn
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r14)
    jne     8f
    mov     (L + 40)(%rsp), %rax
    mov     %rax, Validator_exit_epoch(%r15)
    add     CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY(%r12), %rax
    jc      5f
    mov     %rax, Validator_withdrawable_epoch(%r15)
    PART    %rdx, %rcx, %rbx, BeaconState_pending_consolidations
    mov     %rcx, %rax
    shl     $4, %rax
    add     %rax, %rdx
    mov     S8(%rsp), %rax
    mov     %rax, PendingConsolidation_source_index(%rdx)
    mov     S9(%rsp), %rax
    mov     %rax, PendingConsolidation_target_index(%rdx)
    inc     %rcx
    mov     %rcx, (BeaconState_pending_consolidations + 8)(%rbx)
8:  xor     %eax, %eax
7:  LEAVE 48
5:  movq    $LANTERN_INVALID_OVERFLOW, (%r14)
    xor     %eax, %eax
    LEAVE 48
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END process_consolidation_request
