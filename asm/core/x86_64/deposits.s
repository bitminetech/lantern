/*
 * Deposits applied in epoch processing, x86-64. Requirements: docs/reference/epoch-processing.md.
 */

.if (PendingDeposit_pubkey != DepositData_pubkey) || (PendingDeposit_withdrawal_credentials != DepositData_withdrawal_credentials) || (PendingDeposit_amount != DepositData_amount) || (PendingDeposit_signature != DepositData_signature)
.error "PendingDeposit does not start with the DepositData layout"
.endif
.if (DepositMessage_pubkey != DepositData_pubkey) || (DepositMessage_withdrawal_credentials != DepositData_withdrawal_credentials) || (DepositMessage_amount != DepositData_amount)
.error "DepositData does not start with the DepositMessage layout"
.endif

/* The five lists that grow with each validator, as PartSpecs: PartRef, next PartRef, stride. */
.macro VALIDATOR_LISTS m
    \m part_validators, BeaconState_validators, BeaconState_balances, Validator__mem
    \m part_balances, BeaconState_balances, BeaconState_previous_epoch_participation, 8
    \m part_previous_epoch_participation, BeaconState_previous_epoch_participation, BeaconState_current_epoch_participation, 1
    \m part_current_epoch_participation, BeaconState_current_epoch_participation, BeaconState_inactivity_scores, 1
    \m part_inactivity_scores, BeaconState_inactivity_scores, BeaconState_latest_execution_payload_header, 8
.endm

.macro PART_SPEC label, ref, next, stride
\label:
    .quad \ref, \next, \stride
.endm

    RODATA
    .p2align 3
VALIDATOR_LISTS PART_SPEC

/* r9 = min(r9, free entries of one list of state rdi). Uses rax, rcx, rdx. */
.macro LIST_ROOM label, ref, next, stride
    mov     (\next)(%rdi), %rax
    sub     (\ref)(%rdi), %rax
    .if \stride == 128
    shr     $7, %rax
    .elseif \stride == 8
    shr     $3, %rax
    .elseif \stride > 1
    mov     $(\stride), %ecx
    xor     %edx, %edx
    div     %rcx
    .endif
    sub     ((\ref) + 8)(%rdi), %rax
    cmp     %r9, %rax
    cmovb   %rax, %r9
.endm

/* L0: rax = the fewest free entries in the five validator lists of state rdi. */
LOCAL_FUNCTION validator_room
    UNWIND_END_PROLOGUE
    mov     $-1, %r9
    VALIDATOR_LISTS LIST_ROOM
    mov     %r9, %rax
    ret
END_FUNCTION validator_room

/*
 * L0: rax = the index of the validator of state rdi with the 48-byte public key at rsi, or -1.
 * The first 8 bytes reject most keys; then all 48 are compared. Uses rcx, rdx, r8, r9, xmm0-xmm4.
 */
LOCAL_FUNCTION find_pubkey
    UNWIND_END_PROLOGUE
    PART    %rcx, %rdx, %rdi, BeaconState_validators
    mov     (%rsi), %r8
    movdqu  (%rsi), %xmm0
    movdqu  16(%rsi), %xmm1
    movdqu  32(%rsi), %xmm2
    xor     %eax, %eax
1:  cmp     %rdx, %rax
    jae     3f
    cmp     Validator_pubkey(%rcx), %r8
    jne     2f
    movdqu  Validator_pubkey(%rcx), %xmm3
    pcmpeqb %xmm0, %xmm3
    movdqu  (Validator_pubkey + 16)(%rcx), %xmm4
    pcmpeqb %xmm1, %xmm4
    pand    %xmm4, %xmm3
    movdqu  (Validator_pubkey + 32)(%rcx), %xmm4
    pcmpeqb %xmm2, %xmm4
    pand    %xmm4, %xmm3
    pmovmskb %xmm3, %r9d
    cmp     $0xffff, %r9d
    je      4f
2:  add     $Validator__mem, %rcx
    inc     %rax
    jmp     1b
3:  mov     $-1, %rax
4:  ret
END_FUNCTION find_pubkey

/*
 * rbx deposit, rbp config, r12 scratch, r13 out. Locals: L domain type, L+8 zero root,
 * L+40 domain, L+72 the signing root as a ByteList (header 24, then 32 bytes).
 */
FUNCTION lantern_is_valid_deposit_signature
    ENTER 128
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    movl    $DOMAIN_DEPOSIT, L(%rsp)
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, (L + 8)(%rsp)
    movdqu  %xmm0, (L + 24)(%rsp)
    lea     L(%rsp), %rdi                   # domain = compute_domain(DOMAIN_DEPOSIT)
    lea     CONFIG_GENESIS_FORK_VERSION(%rbp), %rsi
    lea     (L + 8)(%rsp), %rdx
    mov     %r12, %rcx
    lea     (L + 40)(%rsp), %r8
    call    lantern_compute_domain
    test    %rax, %rax
    jnz     7f
    ADDRESS %rdi, lantern_type_DepositMessage   # signing_root = compute_signing_root(deposit_message, domain)
    mov     %rbx, %rsi
    lea     (L + 40)(%rsp), %rdx
    mov     %r12, %rcx
    lea     (L + 96)(%rsp), %r8
    call    lantern_compute_signing_root
    test    %rax, %rax
    jnz     7f
    movq    $56, (L + 72)(%rsp)
    movq    $24, (L + 80)(%rsp)
    movq    $32, (L + 88)(%rsp)
    lea     DepositData_pubkey(%rbx), %rdi  # bls.Verify(pubkey, signing_root, signature)
    lea     (L + 72)(%rsp), %rsi
    lea     DepositData_signature(%rbx), %rdx
    mov     %r12, %rcx
    mov     %r13, %r8
    CALL_GLOBAL crypto_bls_verify
7:  LEAVE 128
END_FUNCTION lantern_is_valid_deposit_signature

/* rbx out, rbp amount. Locals: L max effective balance. */
FUNCTION lantern_get_validator_from_deposit
    ENTER 16
    mov     %rcx, %rbx
    mov     %rdx, %rbp
    movdqu  (%rdi), %xmm0
    movdqu  %xmm0, Validator_pubkey(%rbx)
    movdqu  16(%rdi), %xmm0
    movdqu  %xmm0, (Validator_pubkey + 16)(%rbx)
    movdqu  32(%rdi), %xmm0
    movdqu  %xmm0, (Validator_pubkey + 32)(%rbx)
    lea     Validator_withdrawal_credentials(%rbx), %rax
    COPY32  %rax, %rsi
    movq    $0, Validator_effective_balance(%rbx)
    movq    $0, Validator_slashed(%rbx)     # slashed, and the padding after it
    movq    $-1, Validator_activation_eligibility_epoch(%rbx)
    movq    $-1, Validator_activation_epoch(%rbx)
    movq    $-1, Validator_exit_epoch(%rbx)
    movq    $-1, Validator_withdrawable_epoch(%rbx)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_max_effective_balance
    mov     (%rbp), %rax
    MOVQ    %rcx, EFFECTIVE_BALANCE_INCREMENT
    xor     %edx, %edx
    div     %rcx
    imul    %rcx, %rax                      # amount - amount % EFFECTIVE_BALANCE_INCREMENT
    cmp     L(%rsp), %rax
    jb      1f
    mov     L(%rsp), %rax
1:  mov     %rax, Validator_effective_balance(%rbx)
    xor     %eax, %eax
    LEAVE 16
END_FUNCTION lantern_get_validator_from_deposit

.if Validator_slashed != 88 || Validator_activation_eligibility_epoch != 96
.error "lantern_get_validator_from_deposit zeroes slashed and its padding with one 8-byte store"
.endif
.if FAR_FUTURE_EPOCH != 0xffffffffffffffff
.error "lantern_get_validator_from_deposit writes FAR_FUTURE_EPOCH as -1"
.endif

LEAF lantern_get_index_for_new_validator
    mov     (BeaconState_validators + 8)(%rdi), %rax
    mov     %rax, (%rsi)
    RETURN_OK
END_FUNCTION lantern_get_index_for_new_validator

/* rbx state, rbp value, r12 stride. */
FUNCTION lantern_set_or_append_list
    ENTER 16
    mov     %rdi, %rbx
    mov     %rcx, %rbp
    mov     (%rdx), %rdx                    # index
    mov     (%rsi), %r8                     # ref
    mov     8(%rsi), %r9                    # next
    mov     16(%rsi), %r12                  # stride
    mov     (%rbx,%r8), %rax                # part offset
    mov     8(%rbx,%r8), %rcx               # count
    cmp     %rcx, %rdx
    jne     1f
    mov     (%rbx), %rsi                    # append: the part ends where the next starts
    test    %r9, %r9
    jz      2f
    mov     (%rbx,%r9), %rsi
2:  sub     %rax, %rsi
    lea     1(%rcx), %rdi
    imul    %r12, %rdi
    cmp     %rsi, %rdi
    ja      9f
    lea     1(%rcx), %rdi
    mov     %rdi, 8(%rbx,%r8)
1:  imul    %r12, %rdx
    add     %rax, %rdx
    lea     (%rbx,%rdx), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    lantern_copy
    xor     %eax, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION lantern_set_or_append_list

/*
 * rbx state, rbp pubkey, r12 withdrawal credentials, r13 amount.
 * Locals: L the validator (128), L+128 index, L+136 zero.
 */
FUNCTION lantern_add_validator_to_registry
    ENTER 144
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    call    validator_room
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    lea     (L + 128)(%rsp), %rsi
    call    lantern_get_index_for_new_validator
    mov     %rbp, %rdi
    mov     %r12, %rsi
    mov     %r13, %rdx
    lea     L(%rsp), %rcx
    call    lantern_get_validator_from_deposit
    movq    $0, (L + 136)(%rsp)
    mov     %rbx, %rdi
    ADDRESS %rsi, part_validators
    lea     (L + 128)(%rsp), %rdx
    lea     L(%rsp), %rcx
    call    lantern_set_or_append_list
    mov     %rbx, %rdi
    ADDRESS %rsi, part_balances
    lea     (L + 128)(%rsp), %rdx
    mov     %r13, %rcx
    call    lantern_set_or_append_list
    mov     %rbx, %rdi
    ADDRESS %rsi, part_previous_epoch_participation
    lea     (L + 128)(%rsp), %rdx
    lea     (L + 136)(%rsp), %rcx
    call    lantern_set_or_append_list
    mov     %rbx, %rdi
    ADDRESS %rsi, part_current_epoch_participation
    lea     (L + 128)(%rsp), %rdx
    lea     (L + 136)(%rsp), %rcx
    call    lantern_set_or_append_list
    mov     %rbx, %rdi
    ADDRESS %rsi, part_inactivity_scores
    lea     (L + 128)(%rsp), %rdx
    lea     (L + 136)(%rsp), %rcx
    call    lantern_set_or_append_list
    xor     %eax, %eax
    LEAVE 144
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 144
END_FUNCTION lantern_add_validator_to_registry

/* rbx state, rbp deposit, r12 config, r13 scratch. Locals: L valid, L+8 index. */
FUNCTION lantern_apply_pending_deposit
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    lea     PendingDeposit_pubkey(%rbp), %rsi
    call    find_pubkey
    cmp     $-1, %rax
    jne     1f
    mov     %rbp, %rdi                      # a new public key: a validator when the signature is valid
    mov     %r12, %rsi
    mov     %r13, %rdx
    lea     L(%rsp), %rcx
    call    lantern_is_valid_deposit_signature
    test    %rax, %rax
    jnz     7f
    cmpq    $0, L(%rsp)
    je      8f
    mov     %rbx, %rdi
    lea     PendingDeposit_pubkey(%rbp), %rsi
    lea     PendingDeposit_withdrawal_credentials(%rbp), %rdx
    lea     PendingDeposit_amount(%rbp), %rcx
    call    lantern_add_validator_to_registry
    jmp     7f
1:  mov     %rax, (L + 8)(%rsp)             # increase_balance(state, validator_index, deposit.amount)
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    lea     PendingDeposit_amount(%rbp), %rdx
    call    lantern_increase_balance
8:  xor     %eax, %eax
7:  LEAVE 16
END_FUNCTION lantern_apply_pending_deposit

.set POSTPONE_BYTES, MAX_PENDING_DEPOSITS_PER_EPOCH * PendingDeposit__mem

/*
 * rbx state, rbp config, r12 scratch, r13 result, r14 next deposit index, r15 processed,
 * S7 available, S8 postponed, S9 postponed count, S10 scratch size.
 * Locals: L current epoch, L+8 next epoch, L+16 churn, L+24 reached, L+32 finalized slot,
 * L+40 the deposit (PendingDeposit__mem bytes), L+232 the entries kept.
 */
FUNCTION lantern_process_pending_deposits
    ENTER 240
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH_B %r12, %rbx, 1, POSTPONE_BYTES, 9f
    mov     %rbx, %rdi
    call    validator_room
    cmp     $MAX_PENDING_DEPOSITS_PER_EPOCH, %rax
    jb      9f
    movq    $0, (%r13)
    mov     (%r12), %rax
    mov     %rax, S10(%rsp)
    sub     $POSTPONE_BYTES, %rax
    lea     (%r12,%rax), %rcx
    mov     %rcx, S8(%rsp)                  # deposits_to_postpone: at the end of scratch
    mov     %rax, (%r12)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     L(%rsp), %rax
    inc     %rax
    mov     %rax, (L + 8)(%rsp)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_get_activation_exit_churn_limit
    test    %rax, %rax
    jnz     7f
    mov     BeaconState_deposit_balance_to_consume(%rbx), %rax
    add     (L + 16)(%rsp), %rax
    jc      6f
    mov     %rax, S7(%rsp)                  # available_for_processing
    xor     %r15d, %r15d
    xor     %r14d, %r14d
    movq    $0, S9(%rsp)
    movq    $0, (L + 24)(%rsp)
    lea     (BeaconState_finalized_checkpoint + Checkpoint_epoch)(%rbx), %rdi
    lea     (L + 32)(%rsp), %rsi
    call    lantern_compute_start_slot_at_epoch
    test    %rax, %rax                      # the finalized slot leaves the Uint64 range
    jnz     6f
1:  PART    %rsi, %rcx, %rbx, BeaconState_pending_deposits
    cmp     %rcx, %r14                      # for deposit in state.pending_deposits
    jae     4f
    imul    $PendingDeposit__mem, %r14, %rax
    add     %rax, %rsi
    mov     PendingDeposit_slot(%rsi), %rax
    cmp     (L + 32)(%rsp), %rax            # a deposit not yet finalized
    ja      4f
    cmp     $MAX_PENDING_DEPOSITS_PER_EPOCH, %r14
    jae     4f
    lea     (L + 40)(%rsp), %rdi            # a copy of the deposit, apart from the state
    mov     $PendingDeposit__mem, %edx
    call    lantern_copy
    mov     %rbx, %rdi
    lea     (L + 40 + PendingDeposit_pubkey)(%rsp), %rsi
    call    find_pubkey
    cmp     $-1, %rax
    je      3f                              # not exited, not withdrawn
    mov     BeaconState_validators(%rbx), %rcx
    add     %rbx, %rcx
    shl     $7, %rax
    add     %rax, %rcx
    mov     Validator_withdrawable_epoch(%rcx), %rax
    cmp     (L + 8)(%rsp), %rax
    jb      2f                              # withdrawn: apply
    cmpq    $-1, Validator_exit_epoch(%rcx)
    je      3f
    imul    $PendingDeposit__mem, S9(%rsp), %rdi    # exited: postpone
    add     S8(%rsp), %rdi
    lea     (L + 40)(%rsp), %rsi
    mov     $PendingDeposit__mem, %edx
    call    lantern_copy
    incq    S9(%rsp)
    jmp     25f
3:  mov     (L + 40 + PendingDeposit_amount)(%rsp), %rax
    add     %r15, %rax                      # is_churn_limit_reached = processed_amount + deposit.amount > available
    jc      6f
    cmp     S7(%rsp), %rax
    ja      35f
    mov     %rax, %r15
2:  mov     S10(%rsp), %rax
    sub     $POSTPONE_BYTES, %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi
    lea     (L + 40)(%rsp), %rsi
    mov     %rbp, %rdx
    mov     %r12, %rcx
    call    lantern_apply_pending_deposit
    test    %rax, %rax
    jnz     7f
25: inc     %r14
    jmp     1b
35: movq    $1, (L + 24)(%rsp)
4:  PART    %rdi, %rcx, %rbx, BeaconState_pending_deposits  # pending_deposits[next_deposit_index:] + deposits_to_postpone
    sub     %r14, %rcx
    mov     %rcx, (L + 232)(%rsp)           # the entries kept
    imul    $PendingDeposit__mem, %rcx, %rdx
    imul    $PendingDeposit__mem, %r14, %rsi
    add     %rdi, %rsi
    call    lantern_copy
    PART    %rdi, %rcx, %rbx, BeaconState_pending_deposits
    imul    $PendingDeposit__mem, (L + 232)(%rsp), %rax
    add     %rax, %rdi
    mov     S8(%rsp), %rsi
    imul    $PendingDeposit__mem, S9(%rsp), %rdx
    call    lantern_copy
    mov     (L + 232)(%rsp), %rax
    add     S9(%rsp), %rax
    mov     %rax, (BeaconState_pending_deposits + 8)(%rbx)
    xor     %eax, %eax                      # deposit_balance_to_consume
    cmpq    $0, (L + 24)(%rsp)
    je      45f
    mov     S7(%rsp), %rax                  # available_for_processing - processed_amount
    sub     %r15, %rax
45: mov     %rax, BeaconState_deposit_balance_to_consume(%rbx)
    jmp     8f
6:  movq    $LANTERN_INVALID_OVERFLOW, (%r13)
8:  xor     %eax, %eax
7:  LEAVE 240
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 240
END_FUNCTION lantern_process_pending_deposits
