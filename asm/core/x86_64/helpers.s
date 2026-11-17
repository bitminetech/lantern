/*
 * Beacon chain helpers, x86-64. Requirements: docs/reference/helpers.md.
 * v1: each function follows its spec steps and calls the spec functions it names.
 */

/* ---------------------------------------------------------------- Math */

SPEC_LEAF integer_squareroot
    mov     (%rdi), %r8                     # n
    cmp     $-1, %r8
    jne     1f
    MOVQ    %rax, UINT64_MAX_SQRT           # n == UINT64_MAX
    mov     %rax, (%rsi)
    RETURN_OK
1:  mov     %r8, %rcx                       # x = n
    mov     %r8, %r9
    add     $1, %r9
    shr     $1, %r9                         # y = (x + 1) // 2
2:  cmp     %rcx, %r9                       # while y < x
    jae     3f
    mov     %r9, %rcx                       # x = y; x >= 1 here
    mov     %r8, %rax
    xor     %edx, %edx
    div     %rcx
    add     %rcx, %rax
    shr     $1, %rax                        # y = (x + n // x) // 2
    mov     %rax, %r9
    jmp     2b
3:  mov     %rcx, (%rsi)
    RETURN_OK
SPEC_END integer_squareroot

SPEC_LEAF saturating_sub
    mov     (%rdi), %rax
    sub     (%rsi), %rax                    # a > b ? a - b : 0
    jae     1f
    xor     %eax, %eax
1:  mov     %rax, (%rdx)
    RETURN_OK
SPEC_END saturating_sub

/* ---------------------------------------------------------------- Predicates */

SPEC_LEAF is_active_validator
    mov     (%rsi), %rcx                    # epoch
    xor     %eax, %eax
    cmp     Validator_activation_epoch(%rdi), %rcx  # activation_epoch <= epoch
    jb      1f
    cmp     Validator_exit_epoch(%rdi), %rcx        # and epoch < exit_epoch
    setb    %al
1:  mov     %rax, (%rdx)
    RETURN_OK
SPEC_END is_active_validator

SPEC_LEAF is_eligible_for_activation_queue
    xor     %eax, %eax
    cmpq    $-1, Validator_activation_eligibility_epoch(%rdi)  # activation_eligibility_epoch == FAR_FUTURE_EPOCH
    jne     1f
    MOVQ    %rcx, MIN_ACTIVATION_BALANCE
    cmp     %rcx, Validator_effective_balance(%rdi)    # and effective_balance >= MIN_ACTIVATION_BALANCE
    jb      1f
    mov     $1, %eax
1:  mov     %rax, (%rsi)
    RETURN_OK
SPEC_END is_eligible_for_activation_queue

SPEC_LEAF is_eligible_for_activation
    mov     (BeaconState_finalized_checkpoint + Checkpoint_epoch)(%rdi), %rcx
    xor     %eax, %eax
    cmp     %rcx, Validator_activation_eligibility_epoch(%rsi) # activation_eligibility_epoch <= finalized epoch
    ja      1f
    cmpq    $-1, Validator_activation_epoch(%rsi)          # and activation_epoch == FAR_FUTURE_EPOCH
    sete    %al
1:  mov     %rax, (%rdx)
    RETURN_OK
SPEC_END is_eligible_for_activation

SPEC_LEAF is_slashable_validator
    mov     (%rsi), %rcx                    # epoch
    xor     %eax, %eax
    cmpb    $0, Validator_slashed(%rdi)     # not slashed
    jne     1f
    cmp     Validator_activation_epoch(%rdi), %rcx      # and activation_epoch <= epoch
    jb      1f
    cmp     Validator_withdrawable_epoch(%rdi), %rcx    # and epoch < withdrawable_epoch
    setb    %al
1:  mov     %rax, (%rdx)
    RETURN_OK
SPEC_END is_slashable_validator

SPEC_LEAF is_compounding_withdrawal_credential
    xor     %eax, %eax
    cmpb    $COMPOUNDING_WITHDRAWAL_PREFIX, (%rdi)
    sete    %al
    mov     %rax, (%rsi)
    RETURN_OK
SPEC_END is_compounding_withdrawal_credential

SPEC_LEAF has_compounding_withdrawal_credential
    add     $Validator_withdrawal_credentials, %rdi
    jmp     lantern_is_compounding_withdrawal_credential
SPEC_END has_compounding_withdrawal_credential

/* Locals: rsp+0 out, rsp+8 the compounding flag. */
SPEC_FUNCTION get_max_effective_balance
    FRAME 16
    mov     %rsi, 0(%rsp)
    lea     8(%rsp), %rsi
    call    lantern_has_compounding_withdrawal_credential
    MOVQ    %rax, MIN_ACTIVATION_BALANCE
    cmpq    $0, 8(%rsp)
    je      1f
    MOVQ    %rax, MAX_EFFECTIVE_BALANCE_ELECTRA
1:  mov     0(%rsp), %rsi
    mov     %rax, (%rsi)
    xor     %eax, %eax
    UNFRAME 16
SPEC_END get_max_effective_balance

/* ---------------------------------------------------------------- Misc */

SPEC_LEAF compute_epoch_at_slot
    mov     (%rdi), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, (%rsi)
    RETURN_OK
SPEC_END compute_epoch_at_slot

SPEC_LEAF compute_start_slot_at_epoch
    mov     (%rdi), %rax
    mov     %rax, %rcx
    shr     $(64 - LOG2_SLOTS_PER_EPOCH), %rcx
    jnz     1f                              # epoch * SLOTS_PER_EPOCH leaves the Uint64 range
    shl     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, (%rsi)
    RETURN_OK
1:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END compute_start_slot_at_epoch

SPEC_LEAF compute_activation_exit_epoch
    mov     (%rdi), %rax
    add     $(1 + MAX_SEED_LOOKAHEAD), %rax
    jc      1f
    mov     %rax, (%rsi)
    RETURN_OK
1:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END compute_activation_exit_epoch

/* ---------------------------------------------------------------- Accessors */

SPEC_LEAF get_current_epoch
    add     $BeaconState_slot, %rdi
    jmp     lantern_compute_epoch_at_slot
SPEC_END get_current_epoch

/* Locals: rsp+0 out, rsp+8 current epoch, rsp+16 the constant 1. */
SPEC_FUNCTION get_previous_epoch
    FRAME 32
    mov     %rsi, 0(%rsp)
    lea     8(%rsp), %rsi
    call    lantern_get_current_epoch
    movq    $1, 16(%rsp)
    lea     8(%rsp), %rdi                   # saturating_sub(current, 1)
    lea     16(%rsp), %rsi
    mov     0(%rsp), %rdx
    call    lantern_saturating_sub
    UNFRAME 32
SPEC_END get_previous_epoch

SPEC_LEAF get_block_root_at_slot
    mov     (%rsi), %rcx                    # slot
    mov     BeaconState_slot(%rdi), %r8
    cmp     %r8, %rcx                       # slot < state.slot
    jae     1f
    mov     %r8, %r9                        # state.slot <= slot + SLOTS_PER_HISTORICAL_ROOT
    sub     %rcx, %r9
    cmp     $SLOTS_PER_HISTORICAL_ROOT, %r9
    ja      1f
    and     $(SLOTS_PER_HISTORICAL_ROOT - 1), %rcx
    shl     $5, %rcx
    lea     BeaconState_block_roots(%rdi,%rcx), %rax
    COPY32  %rdx, %rax
    RETURN_OK
1:  mov     $LANTERN_INVALID_BLOCK_ROOT_SLOT, %eax
    ret
SPEC_END get_block_root_at_slot

/* Locals: rsp+0 state, rsp+8 out, rsp+16 the start slot. */
SPEC_FUNCTION get_block_root
    FRAME 32
    mov     %rdi, 0(%rsp)
    mov     %rdx, 8(%rsp)
    mov     %rsi, %rdi
    lea     16(%rsp), %rsi
    call    lantern_compute_start_slot_at_epoch
    test    %rax, %rax
    jnz     1f
    mov     0(%rsp), %rdi
    lea     16(%rsp), %rsi
    mov     8(%rsp), %rdx
    call    lantern_get_block_root_at_slot
1:  UNFRAME 32
SPEC_END get_block_root

SPEC_LEAF get_randao_mix
    mov     (%rsi), %rcx
    and     $(EPOCHS_PER_HISTORICAL_VECTOR - 1), %rcx
    shl     $5, %rcx
    lea     BeaconState_randao_mixes(%rdi,%rcx), %rax
    COPY32  %rdx, %rax
    RETURN_OK
SPEC_END get_randao_mix

/*
 * rbx state, rbp epoch, r12 out, r13 validator, r14 index, r15 out entries, S7 validator count.
 * Locals: the is_active_validator result.
 */
SPEC_FUNCTION get_active_validator_indices
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    PART    %r13, %rax, %rbx, BeaconState_validators
    mov     %rax, S7(%rsp)
    lea     LIST_FIXED(,%rax,8), %rcx       # room for every validator
    cmp     %rcx, LIST_SIZE(%r12)
    jb      9f
    movq    $LIST_FIXED, LIST_OFFSET(%r12)
    lea     LIST_FIXED(%r12), %r15
    xor     %r14d, %r14d
1:  cmp     S7(%rsp), %r14
    jae     3f
    mov     %r13, %rdi
    mov     %rbp, %rsi
    lea     L(%rsp), %rdx
    call    lantern_is_active_validator
    cmpq    $0, L(%rsp)
    je      2f
    mov     %r14, (%r15)
    add     $8, %r15
2:  add     $Validator__mem, %r13
    inc     %r14
    jmp     1b
3:  lea     LIST_FIXED(%r12), %rax
    sub     %rax, %r15
    shr     $3, %r15
    mov     %r15, LIST_COUNT(%r12)
    xor     %eax, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END get_active_validator_indices

SPEC_LEAF get_total_balance
    PART    %r8, %r9, %rdi, BeaconState_validators
    mov     LIST_COUNT(%rsi), %rcx
    lea     LIST_FIXED(%rsi), %rsi
    xor     %eax, %eax                      # sum
1:  test    %rcx, %rcx
    jz      2f
    mov     (%rsi), %r9
    add     $8, %rsi
    shl     $7, %r9                         # Validator__mem is 128
    add     Validator_effective_balance(%r8,%r9), %rax
    dec     %rcx
    jmp     1b
2:  MOVQ    %r9, EFFECTIVE_BALANCE_INCREMENT
    cmp     %r9, %rax                       # max(EFFECTIVE_BALANCE_INCREMENT, sum)
    ja      3f
    mov     %r9, %rax
3:  mov     %rax, (%rdx)
    RETURN_OK
SPEC_END get_total_balance

/* rbx state, rbp scratch, r12 out; locals: the epoch. The index list is the scratch after its size. */
SPEC_FUNCTION get_total_active_balance
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     (%rbp), %rax                    # the list takes all of scratch but its size field
    sub     $8, %rax
    mov     %rax, 8(%rbp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    lea     8(%rbp), %rdx
    call    lantern_get_active_validator_indices
    test    %rax, %rax
    jnz     9f
    mov     %rbx, %rdi
    lea     8(%rbp), %rsi
    mov     %r12, %rdx
    call    lantern_get_total_balance
9:  LEAVE 16
SPEC_END get_total_active_balance

/* ---------------------------------------------------------------- Mutators */

SPEC_LEAF increase_balance
    mov     (%rsi), %rcx                    # index
    mov     (%rdx), %rax                    # delta
    mov     BeaconState_balances(%rdi), %r8
    add     %rdi, %r8
    add     %rax, (%r8,%rcx,8)
    RETURN_OK
SPEC_END increase_balance

SPEC_LEAF decrease_balance
    mov     (%rsi), %rcx                    # index
    mov     BeaconState_balances(%rdi), %r8
    add     %rdi, %r8
    lea     (%r8,%rcx,8), %rdi              # balances[index] = saturating_sub(balances[index], delta)
    mov     %rdx, %rsi
    mov     %rdi, %rdx
    jmp     lantern_saturating_sub
SPEC_END decrease_balance

/* ---------------------------------------------------------------- Participation flags and rewards */

SPEC_LEAF has_flag
    movzbl  (%rdi), %eax
    mov     (%rsi), %rcx
    shr     %cl, %eax
    and     $1, %eax
    mov     %rax, (%rdx)
    RETURN_OK
SPEC_END has_flag

SPEC_LEAF add_flag
    movzbl  (%rdi), %eax
    mov     (%rsi), %rcx
    mov     $1, %r8d
    shl     %cl, %r8d
    or      %r8d, %eax
    mov     %al, (%rdx)
    RETURN_OK
SPEC_END add_flag

/* Locals: rsp+0 state, rsp+8 out, rsp+16 previous epoch. */
SPEC_FUNCTION get_finality_delay
    FRAME 32
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    lea     16(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     0(%rsp), %rdi
    mov     16(%rsp), %rax
    sub     (BeaconState_finalized_checkpoint + Checkpoint_epoch)(%rdi), %rax
    mov     8(%rsp), %rsi
    mov     %rax, (%rsi)
    xor     %eax, %eax
    UNFRAME 32
SPEC_END get_finality_delay

/* Locals: rsp+0 out, rsp+8 the finality delay. */
SPEC_FUNCTION is_in_inactivity_leak
    FRAME 16
    mov     %rsi, 0(%rsp)
    lea     8(%rsp), %rsi
    call    lantern_get_finality_delay
    xor     %eax, %eax
    cmpq    $MIN_EPOCHS_TO_INACTIVITY_PENALTY, 8(%rsp)
    seta    %al
    mov     0(%rsp), %rsi
    mov     %rax, (%rsi)
    xor     %eax, %eax
    UNFRAME 16
SPEC_END is_in_inactivity_leak

/*
 * rbx state, rbp out, r12 validator, r13 validator count, r14 index, r15 out entries.
 * Locals: previous epoch at L, is_active_validator result at L + 8.
 */
SPEC_FUNCTION get_eligible_validator_indices
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    PART    %r12, %r13, %rbx, BeaconState_validators
    lea     LIST_FIXED(,%r13,8), %rax
    cmp     %rax, LIST_SIZE(%rbp)
    jb      9f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_previous_epoch
    movq    $LIST_FIXED, LIST_OFFSET(%rbp)
    lea     LIST_FIXED(%rbp), %r15
    xor     %r14d, %r14d
1:  cmp     %r13, %r14
    jae     4f
    mov     %r12, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_is_active_validator
    cmpq    $0, (L + 8)(%rsp)
    jne     2f
    cmpb    $0, Validator_slashed(%r12)     # or slashed and previous_epoch + 1 < withdrawable_epoch
    je      3f
    mov     L(%rsp), %rax
    inc     %rax
    cmp     Validator_withdrawable_epoch(%r12), %rax
    jae     3f
2:  mov     %r14, (%r15)
    add     $8, %r15
3:  add     $Validator__mem, %r12
    inc     %r14
    jmp     1b
4:  lea     LIST_FIXED(%rbp), %rax
    sub     %rax, %r15
    shr     $3, %r15
    mov     %r15, LIST_COUNT(%rbp)
    xor     %eax, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END get_eligible_validator_indices

/*
 * rbx state, rbp flag_index, r12 epoch then the active list cursor, r13 scratch then the
 * entries left, r14 out, r15 epoch_participation, S7 out entries.
 * Locals: previous epoch at L, current epoch at L + 8, has_flag result at L + 16, index at L + 24.
 */
SPEC_FUNCTION get_unslashed_participating_indices
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     (BeaconState_validators + 8)(%rbx), %rax
    lea     LIST_FIXED(,%rax,8), %rax       # out and scratch need room for every validator
    cmp     %rax, LIST_SIZE(%r14)
    jb      9f
    add     $8, %rax
    cmp     %rax, (%r13)
    jb      9f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     (%r12), %rax
    cmp     (L + 8)(%rsp), %rax             # assert epoch in (previous, current)
    je      1f
    cmp     L(%rsp), %rax
    je      2f
    mov     $LANTERN_INVALID_PARTICIPATION_EPOCH, %eax
    LEAVE 32
1:  PART    %r15, %rax, %rbx, BeaconState_current_epoch_participation
    jmp     3f
2:  PART    %r15, %rax, %rbx, BeaconState_previous_epoch_participation
3:  mov     (%r13), %rax                    # active_validator_indices: the scratch after its size
    sub     $8, %rax
    mov     %rax, 8(%r13)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     8(%r13), %rdx
    call    lantern_get_active_validator_indices
    test    %rax, %rax
    jnz     8f
    lea     (8 + LIST_FIXED)(%r13), %r12
    mov     (8 + LIST_COUNT)(%r13), %r13
    movq    $LIST_FIXED, LIST_OFFSET(%r14)
    lea     LIST_FIXED(%r14), %rax
    mov     %rax, S7(%rsp)
4:  test    %r13, %r13
    jz      6f
    mov     (%r12), %rax                    # index
    add     $8, %r12
    mov     %rax, (L + 24)(%rsp)
    lea     (%r15,%rax), %rdi
    mov     %rbp, %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_has_flag
    cmpq    $0, (L + 16)(%rsp)
    je      5f
    mov     (L + 24)(%rsp), %rax            # and not state.validators[index].slashed
    mov     BeaconState_validators(%rbx), %rcx
    add     %rbx, %rcx
    mov     %rax, %rdx
    shl     $7, %rdx
    cmpb    $0, Validator_slashed(%rcx,%rdx)
    jne     5f
    mov     S7(%rsp), %rcx
    mov     %rax, (%rcx)
    add     $8, %rcx
    mov     %rcx, S7(%rsp)
5:  dec     %r13
    jmp     4b
6:  mov     S7(%rsp), %rcx
    lea     LIST_FIXED(%r14), %rax
    sub     %rax, %rcx
    shr     $3, %rcx
    mov     %rcx, LIST_COUNT(%r14)
    xor     %eax, %eax
8:  LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
SPEC_END get_unslashed_participating_indices

/* Locals: rsp+0 out, rsp+8 total active balance, rsp+16 its square root. */
SPEC_FUNCTION get_base_reward_per_increment
    FRAME 32
    mov     %rdx, 0(%rsp)
    lea     8(%rsp), %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     1f
    lea     8(%rsp), %rdi
    lea     16(%rsp), %rsi
    call    lantern_integer_squareroot
    MOVQ    %rax, EFFECTIVE_BALANCE_INCREMENT * BASE_REWARD_FACTOR
    xor     %edx, %edx
    divq    16(%rsp)
    mov     0(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
1:  UNFRAME 32
SPEC_END get_base_reward_per_increment

/* Locals: rsp+0 state, rsp+8 index, rsp+16 out, rsp+24 base reward per increment. */
SPEC_FUNCTION get_base_reward
    FRAME 32
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rcx, 16(%rsp)
    mov     %rdx, %rsi
    lea     24(%rsp), %rdx
    call    lantern_get_base_reward_per_increment
    test    %rax, %rax
    jnz     1f
    mov     0(%rsp), %rdi
    mov     8(%rsp), %rsi
    mov     (%rsi), %rsi
    mov     BeaconState_validators(%rdi), %rcx
    add     %rdi, %rcx
    shl     $7, %rsi
    mov     Validator_effective_balance(%rcx,%rsi), %rax
    MOVQ    %rcx, EFFECTIVE_BALANCE_INCREMENT
    xor     %edx, %edx
    div     %rcx                            # increments
    imul    24(%rsp), %rax
    mov     16(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
1:  UNFRAME 32
SPEC_END get_base_reward
