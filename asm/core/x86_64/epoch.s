/*
 * Epoch processing, x86-64. Requirements: docs/reference/epoch-processing.md.
 * v1: each function follows its spec steps and calls the spec functions it
 * names. A call whose result the loop cannot change is made once, before the loop.
 */

/* ---------------------------------------------------------------- Justification and finalization */

.if FORK >= FORK_ALTAIR
/*
 * A candidate of ARCHITECTURE.md section 9: get_unslashed_participating_indices,
 * get_total_active_balance and get_total_balance inlined in one pass over the validators.
 * rbx state, rbp config, then the validator count; r12 scratch, then previous_epoch_participation;
 * r13 result; r14 validator; r15 current_epoch_participation. Locals: L current epoch,
 * L+8 previous epoch, L+16 total active balance, L+24 previous target balance, L+32 current target balance.
 */
SPEC_FUNCTION process_justification_and_finalization
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 3, 9f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    cmpq    $(GENESIS_EPOCH + 1), L(%rsp)
    jbe     8f
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_previous_epoch
    PART    %r14, %rbp, %rbx, BeaconState_validators
    PART    %r12, %rax, %rbx, BeaconState_previous_epoch_participation
    PART    %r15, %rax, %rbx, BeaconState_current_epoch_participation
    mov     L(%rsp), %rsi                   # current
    mov     (L + 8)(%rsp), %rdi             # previous
    xor     %r8d, %r8d                      # total active balance
    xor     %r9d, %r9d                      # previous target balance
    xor     %r10d, %r10d                    # current target balance
    test    %rbp, %rbp
    jz      2f
1:  mov     Validator_activation_epoch(%r14), %rax
    mov     Validator_exit_epoch(%r14), %rcx
    mov     Validator_effective_balance(%r14), %rdx
    cmp     %rsi, %rax                      # is_active_validator(validator, current)
    ja      3f
    cmp     %rcx, %rsi
    jae     3f
    add     %rdx, %r8
    cmpb    $0, Validator_slashed(%r14)     # and not slashed, with the target flag
    jne     3f
    movzbl  (%r15), %r11d                   # current_epoch_participation[index]
    bt      $TIMELY_TARGET_FLAG_INDEX, %r11d
    sbb     %r11, %r11
    and     %rdx, %r11
    add     %r11, %r10
3:  cmp     %rdi, %rax                      # the same in the previous epoch
    ja      4f
    cmp     %rcx, %rdi
    jae     4f
    cmpb    $0, Validator_slashed(%r14)
    jne     4f
    movzbl  (%r12), %r11d                   # previous_epoch_participation[index]
    bt      $TIMELY_TARGET_FLAG_INDEX, %r11d
    sbb     %r11, %r11
    and     %rdx, %r11
    add     %r11, %r9
4:  add     $Validator__mem, %r14
    inc     %r12
    inc     %r15
    dec     %rbp
    jnz     1b
2:  mov     $EFFECTIVE_BALANCE_INCREMENT, %rcx    # get_total_balance: max(EFFECTIVE_BALANCE_INCREMENT, sum)
    cmp     %rcx, %r8
    cmovbe  %rcx, %r8
    cmp     %rcx, %r9
    cmovbe  %rcx, %r9
    cmp     %rcx, %r10
    cmovbe  %rcx, %r10
    mov     %r8, (L + 16)(%rsp)
    mov     %r9, (L + 24)(%rsp)
    mov     %r10, (L + 32)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    lea     (L + 32)(%rsp), %rcx
    mov     %r13, %r8
    call    lantern_weigh_justification_and_finalization
    LEAVE 48
8:  movq    $0, (%r13)
    xor     %eax, %eax
    LEAVE 48
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END process_justification_and_finalization
.endif

/* dst (40 bytes, a Checkpoint) = src. Uses xmm0, xmm1, r11. */
.macro COPY_CHECKPOINT dst, src
    movdqu  (\src), %xmm0
    movdqu  16(\src), %xmm1
    mov     32(\src), %r11
    movdqu  %xmm0, (\dst)
    movdqu  %xmm1, 16(\dst)
    mov     %r11, 32(\dst)
.endm

/*
 * rbx state, rbp total, r12 previous target balance, r13 current target balance,
 * r14 result, r15 justification bits.
 * Locals: L old previous justified (40), L+48 old current justified (40),
 * L+96 previous epoch, L+104 current epoch, L+112 root (32).
 */
SPEC_FUNCTION weigh_justification_and_finalization
    ENTER 160
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     (%rdx), %r12
    mov     (%rcx), %r13
    mov     %r8, %r14
    mov     %rbx, %rdi
    lea     (L + 96)(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     %rbx, %rdi
    lea     (L + 104)(%rsp), %rsi
    call    lantern_get_current_epoch
    lea     BeaconState_previous_justified_checkpoint(%rbx), %rax  # keep the old checkpoints
    lea     L(%rsp), %rcx
    COPY_CHECKPOINT %rcx, %rax
    lea     BeaconState_current_justified_checkpoint(%rbx), %rax
    lea     (L + 48)(%rsp), %rcx
    COPY_CHECKPOINT %rcx, %rax
    lea     BeaconState_previous_justified_checkpoint(%rbx), %rdx  # previous = current
    COPY_CHECKPOINT %rdx, %rcx
    movzbl  BeaconState_justification_bits(%rbx), %r15d             # bits[1:] = bits[:3]; bits[0] = False
    shl     $1, %r15d
    and     $0xf, %r15d
    lea     (%r12,%r12,2), %rax             # previous_epoch_target_balance * 3 >= total * 2
    lea     (%rbp,%rbp), %rcx
    cmp     %rcx, %rax
    jb      1f
    mov     %rbx, %rdi
    lea     (L + 96)(%rsp), %rsi
    lea     (L + 112)(%rsp), %rdx
    call    lantern_get_block_root
    CHECK_STATUS %r14, 6f, 6f
    lea     BeaconState_current_justified_checkpoint(%rbx), %rax
    mov     (L + 96)(%rsp), %rcx
    mov     %rcx, Checkpoint_epoch(%rax)
    lea     Checkpoint_root(%rax), %rax
    lea     (L + 112)(%rsp), %rcx
    COPY32  %rax, %rcx
    or      $2, %r15d
1:  lea     (%r13,%r13,2), %rax             # current_epoch_target_balance * 3 >= total * 2
    lea     (%rbp,%rbp), %rcx
    cmp     %rcx, %rax
    jb      2f
    mov     %rbx, %rdi
    lea     (L + 104)(%rsp), %rsi
    lea     (L + 112)(%rsp), %rdx
    call    lantern_get_block_root
    CHECK_STATUS %r14, 6f, 6f
    lea     BeaconState_current_justified_checkpoint(%rbx), %rax
    mov     (L + 104)(%rsp), %rcx
    mov     %rcx, Checkpoint_epoch(%rax)
    lea     Checkpoint_root(%rax), %rax
    lea     (L + 112)(%rsp), %rcx
    COPY32  %rax, %rcx
    or      $1, %r15d
2:  mov     %r15b, BeaconState_justification_bits(%rbx)
    xor     %ecx, %ecx                      # the checkpoint to finalize: 0 none
    mov     L(%rsp), %rax                   # old previous justified epoch
    mov     (L + 48)(%rsp), %rdx            # old current justified epoch
    mov     (L + 104)(%rsp), %rsi           # current epoch
    mov     %r15d, %edi                     # bits[1:4] and old_previous + 3 == current
    and     $0xe, %edi
    cmp     $0xe, %edi
    jne     3f
    lea     3(%rax), %rdi
    cmp     %rsi, %rdi
    jne     3f
    lea     L(%rsp), %rcx
3:  mov     %r15d, %edi                     # bits[1:3] and old_previous + 2 == current
    and     $0x6, %edi
    cmp     $0x6, %edi
    jne     4f
    lea     2(%rax), %rdi
    cmp     %rsi, %rdi
    jne     4f
    lea     L(%rsp), %rcx
4:  mov     %r15d, %edi                     # bits[0:3] and old_current + 2 == current
    and     $0x7, %edi
    cmp     $0x7, %edi
    jne     5f
    lea     2(%rdx), %rdi
    cmp     %rsi, %rdi
    jne     5f
    lea     (L + 48)(%rsp), %rcx
5:  mov     %r15d, %edi                     # bits[0:2] and old_current + 1 == current
    and     $0x3, %edi
    cmp     $0x3, %edi
    jne     55f
    lea     1(%rdx), %rdi
    cmp     %rsi, %rdi
    jne     55f
    lea     (L + 48)(%rsp), %rcx
55: test    %rcx, %rcx
    jz      56f
    lea     BeaconState_finalized_checkpoint(%rbx), %rax
    COPY_CHECKPOINT %rax, %rcx
56: movq    $0, (%r14)
6:  xor     %eax, %eax
    LEAVE 160
SPEC_END weigh_justification_and_finalization

/* ---------------------------------------------------------------- Inactivity */

.if FORK >= FORK_ALTAIR
/*
 * A candidate of ARCHITECTURE.md section 9: get_eligible_validator_indices and
 * get_unslashed_participating_indices inlined in one pass over the validators.
 * rbx state, rbp config, r12 scratch, then previous_epoch_participation; r13 result;
 * r14 validator; r15 inactivity_scores. Locals: L current epoch, L+8 previous epoch, L+16 leak.
 */
SPEC_FUNCTION process_inactivity_updates
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 3, 9f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    cmpq    $GENESIS_EPOCH, L(%rsp)
    je      8f
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    call    lantern_is_in_inactivity_leak
    mov     (L + 8)(%rsp), %rdi             # previous epoch, and it + 1
    lea     1(%rdi), %rsi
    mov     CONFIG_INACTIVITY_SCORE_BIAS(%rbp), %r8
    mov     CONFIG_INACTIVITY_SCORE_RECOVERY_RATE(%rbp), %r9
    mov     (L + 16)(%rsp), %r10            # leak
    PART    %r14, %rcx, %rbx, BeaconState_validators
    PART    %r12, %rax, %rbx, BeaconState_previous_epoch_participation
    PART    %r15, %rax, %rbx, BeaconState_inactivity_scores
    test    %rcx, %rcx
    jz      8f
1:  mov     Validator_activation_epoch(%r14), %rax
    mov     Validator_exit_epoch(%r14), %rdx
    movzbl  (%r12), %r11d                   # previous_epoch_participation[index]
    cmp     %rdi, %rax                      # is_active_validator(validator, previous)
    ja      2f
    cmp     %rdx, %rdi
    jae     2f
    cmpb    $0, Validator_slashed(%r14)
    je      3f
    xor     %r11d, %r11d                    # slashed: not in the unslashed participating set
    jmp     3f
2:  cmpb    $0, Validator_slashed(%r14)     # get_eligible_validator_indices: or slashed and
    je      7f
    cmp     Validator_withdrawable_epoch(%r14), %rsi    # previous_epoch + 1 < withdrawable_epoch
    jae     7f
    xor     %r11d, %r11d
3:  mov     (%r15), %rax                    # inactivity_scores[index]
    bt      $TIMELY_TARGET_FLAG_INDEX, %r11d
    jnc     4f
    xor     %edx, %edx                      # -= min(1, score): saturating_sub(score, 1)
    sub     $1, %rax
    cmovb   %rdx, %rax
    jmp     5f
4:  add     %r8, %rax                       # += INACTIVITY_SCORE_BIAS
5:  test    %r10, %r10
    jnz     6f
    xor     %edx, %edx                      # saturating_sub(score, INACTIVITY_SCORE_RECOVERY_RATE)
    sub     %r9, %rax
    cmovb   %rdx, %rax
6:  mov     %rax, (%r15)
7:  add     $Validator__mem, %r14
    inc     %r12
    add     $8, %r15
    dec     %rcx
    jnz     1b
8:  movq    $0, (%r13)
    xor     %eax, %eax
    LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
SPEC_END process_inactivity_updates
.endif

/* ---------------------------------------------------------------- Rewards and penalties */

/* Write count n to an output IndexList and zero its n entries. list rdi, n rsi. */
LOCAL_FUNCTION lantern_zero_deltas
    UNWIND_END_PROLOGUE
    movq    $LIST_FIXED, LIST_OFFSET(%rdi)
    mov     %rsi, LIST_COUNT(%rdi)
    add     $LIST_FIXED, %rdi
    shl     $3, %rsi
    jmp     lantern_zero
END_FUNCTION lantern_zero_deltas

.if FORK >= FORK_ALTAIR
/*
 * rbx state, rbp flag index, r12 scratch, r13 rewards, r14 penalties, r15 eligible cursor,
 * S7 participating list then its cursor, S8 eligible list.
 * Locals: L previous epoch, L+8 participating balance, L+16 total active, L+24 leak,
 * L+32 eligible end, L+40 participating end, L+48 base reward, L+72 index, L+80 weight,
 * L+88 the scratch size on entry, L+96 base reward per increment.
 */
SPEC_FUNCTION get_flag_index_deltas
    ENTER 112
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    NEED_SCRATCH %r12, %rbx, 3, 9f
    mov     (BeaconState_validators + 8)(%rbx), %rax
    lea     LIST_FIXED(,%rax,8), %rcx       # each output has room for every validator
    cmp     %rcx, LIST_SIZE(%r13)
    jb      9f
    cmp     %rcx, LIST_SIZE(%r14)
    jb      9f
    mov     %r13, %rdi
    mov     %rax, %rsi
    call    lantern_zero_deltas
    mov     %r14, %rdi
    mov     (BeaconState_validators + 8)(%rbx), %rsi
    call    lantern_zero_deltas
    mov     (%r12), %rax
    mov     %rax, (L + 88)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     (L + 88)(%rsp), %rax
    SCRATCH_LIST %rdx, %r12, %rax, 0, %rcx
    mov     %rdx, S7(%rsp)
    SCRATCH_LIST %rdx, %r12, %rax, 1, %rcx
    mov     %rdx, S8(%rsp)
    SCRATCH_GIVE %r12, %rax, 2, %rcx
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    lea     L(%rsp), %rdx
    mov     %r12, %rcx
    mov     S7(%rsp), %r8
    call    lantern_get_unslashed_participating_indices
    test    %rax, %rax
    jnz     8f
    mov     (%rbp), %rax                    # weight = PARTICIPATION_FLAG_WEIGHTS[flag_index]
    mov     $TIMELY_SOURCE_WEIGHT, %ecx     # the source and head weights are equal
    mov     $TIMELY_TARGET_WEIGHT, %edx
    cmp     $TIMELY_TARGET_FLAG_INDEX, %rax
    cmove   %rdx, %rcx
    mov     %rcx, (L + 80)(%rsp)
    mov     %rbx, %rdi
    mov     S7(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_get_total_balance
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    SCRATCH_GIVE %r12, (L+88)(%rsp), 2, %rcx
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     8f
    mov     %rbx, %rdi
    mov     S8(%rsp), %rsi
    call    lantern_get_eligible_validator_indices
    test    %rax, %rax
    jnz     8f
    mov     %rbx, %rdi
    lea     (L + 24)(%rsp), %rsi
    call    lantern_is_in_inactivity_leak
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    SCRATCH_GIVE %r12, (L+88)(%rsp), 2, %rcx
    mov     %rbx, %rdi                      # get_base_reward's factor, once for every index
    mov     %r12, %rsi
    lea     (L + 96)(%rsp), %rdx
    call    lantern_get_base_reward_per_increment
    test    %rax, %rax
    jnz     8f
    mov     S8(%rsp), %rax
    lea     LIST_FIXED(%rax), %r15
    mov     LIST_COUNT(%rax), %rcx
    lea     (%r15,%rcx,8), %rcx
    mov     %rcx, (L + 32)(%rsp)
    mov     S7(%rsp), %rax
    lea     LIST_FIXED(%rax), %rdx
    mov     LIST_COUNT(%rax), %rcx
    lea     (%rdx,%rcx,8), %rcx
    mov     %rcx, (L + 40)(%rsp)
    mov     %rdx, S7(%rsp)
2:  cmp     (L + 32)(%rsp), %r15
    jae     7f
    mov     (%r15), %rax
    add     $8, %r15
    mov     %rax, (L + 72)(%rsp)
    PART    %rcx, %rdx, %rbx, BeaconState_validators
    shl     $7, %rax                        # base_reward = get_base_reward(state, index):
    mov     Validator_effective_balance(%rcx,%rax), %rax
    xor     %edx, %edx
    mov     $EFFECTIVE_BALANCE_INCREMENT, %ecx
    div     %rcx                            # increments * base_reward_per_increment
    imul    (L + 96)(%rsp), %rax
    mov     %rax, (L + 48)(%rsp)
    mov     (L + 72)(%rsp), %rax
    mov     S7(%rsp), %rcx
    IN_SORTED %rax, %rcx, (L+40)(%rsp), %rdx
    mov     %rcx, S7(%rsp)
    test    %rdx, %rdx
    jz      3f
    cmpq    $0, (L + 24)(%rsp)              # participating: a reward unless leaking
    jne     2b
    MOVQ    %rsi, EFFECTIVE_BALANCE_INCREMENT
    mov     (L + 8)(%rsp), %rax
    xor     %edx, %edx
    div     %rsi                            # unslashed_participating_increments
    mov     %rax, %rdi
    imul    (L + 48)(%rsp), %rdi
    imul    (L + 80)(%rsp), %rdi            # reward_numerator
    mov     (L + 16)(%rsp), %rax
    xor     %edx, %edx
    div     %rsi                            # active_increments
    imul    $WEIGHT_DENOMINATOR, %rax, %rsi # reward_denominator
    mov     %rdi, %rax
    xor     %edx, %edx
    div     %rsi
    mov     (L + 72)(%rsp), %rcx
    add     %rax, LIST_FIXED(%r13,%rcx,8)
    jmp     2b
3:  cmpq    $TIMELY_HEAD_FLAG_INDEX, (%rbp) # not participating: a penalty unless the flag is head
    je      2b
    mov     (L + 48)(%rsp), %rax
    imul    (L + 80)(%rsp), %rax
    shr     $6, %rax                        # // WEIGHT_DENOMINATOR, which is 64
    mov     (L + 72)(%rsp), %rcx
    add     %rax, LIST_FIXED(%r14,%rcx,8)
    jmp     2b
7:  xor     %eax, %eax
8:  LEAVE 112
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 112
SPEC_END get_flag_index_deltas
.endif

.if FORK >= FORK_ALTAIR
/*
 * rbx state, rbp config, r12 scratch, r13 rewards, r14 penalties, r15 eligible cursor,
 * S7 participating list then its cursor, S8 eligible list.
 * Locals: L previous epoch, L+8 flag index, L+24 eligible end, L+32 participating end, L+40 the scratch size.
 */
SPEC_FUNCTION get_inactivity_penalty_deltas
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    NEED_SCRATCH %r12, %rbx, 3, 9f
    mov     (BeaconState_validators + 8)(%rbx), %rax
    lea     LIST_FIXED(,%rax,8), %rcx
    cmp     %rcx, LIST_SIZE(%r13)
    jb      9f
    cmp     %rcx, LIST_SIZE(%r14)
    jb      9f
    mov     %r13, %rdi
    mov     %rax, %rsi
    call    lantern_zero_deltas
    mov     %r14, %rdi
    mov     (BeaconState_validators + 8)(%rbx), %rsi
    call    lantern_zero_deltas
    mov     (%r12), %rax
    mov     %rax, (L + 40)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     (L + 40)(%rsp), %rax
    SCRATCH_LIST %rdx, %r12, %rax, 0, %rcx
    mov     %rdx, S7(%rsp)
    SCRATCH_LIST %rdx, %r12, %rax, 1, %rcx
    mov     %rdx, S8(%rsp)
    SCRATCH_GIVE %r12, %rax, 2, %rcx
    movq    $TIMELY_TARGET_FLAG_INDEX, (L + 8)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    lea     L(%rsp), %rdx
    mov     %r12, %rcx
    mov     S7(%rsp), %r8
    call    lantern_get_unslashed_participating_indices
    test    %rax, %rax
    jnz     8f
    mov     %rbx, %rdi
    mov     S8(%rsp), %rsi
    call    lantern_get_eligible_validator_indices
    test    %rax, %rax
    jnz     8f
    mov     S8(%rsp), %rax
    lea     LIST_FIXED(%rax), %r15
    mov     LIST_COUNT(%rax), %rcx
    lea     (%r15,%rcx,8), %rcx
    mov     %rcx, (L + 24)(%rsp)
    mov     S7(%rsp), %rax
    lea     LIST_FIXED(%rax), %rdx
    mov     LIST_COUNT(%rax), %rcx
    lea     (%rdx,%rcx,8), %rcx
    mov     %rcx, (L + 32)(%rsp)
    mov     %rdx, S7(%rsp)
1:  cmp     (L + 24)(%rsp), %r15
    jae     7f
    mov     (%r15), %rax
    add     $8, %r15
    mov     S7(%rsp), %rcx
    IN_SORTED %rax, %rcx, (L+32)(%rsp), %rdx
    mov     %rcx, S7(%rsp)
    test    %rdx, %rdx
    jnz     1b
    mov     BeaconState_validators(%rbx), %rcx
    add     %rbx, %rcx
    mov     %rax, %rdx
    shl     $7, %rdx
    mov     Validator_effective_balance(%rcx,%rdx), %rsi
    mov     BeaconState_inactivity_scores(%rbx), %rcx
    add     %rbx, %rcx
    imul    (%rcx,%rax,8), %rsi             # penalty_numerator
    mov     CONFIG_INACTIVITY_SCORE_BIAS(%rbp), %rcx
    imul    $FORK_INACTIVITY_PENALTY_QUOTIENT, %rcx, %rcx  # penalty_denominator
    mov     %rax, %rdi
    mov     %rsi, %rax
    xor     %edx, %edx
    div     %rcx
    add     %rax, LIST_FIXED(%r14,%rdi,8)
    jmp     1b
7:  xor     %eax, %eax
8:  LEAVE 64
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
SPEC_END get_inactivity_penalty_deltas
.endif

.if FORK >= FORK_ALTAIR
/*
 * A candidate of ARCHITECTURE.md section 9: get_flag_index_deltas and
 * get_inactivity_penalty_deltas inlined in two passes over the validators, with no lists.
 * Pass 1 sums the total active balance and each flag's unslashed participating balance;
 * pass 2 changes each eligible validator's balance by its deltas, in the spec's order.
 * rbx state, then balances; rbp config, then the validator count; r12 participation;
 * r13 result; r14 validator; r15 index. Locals: L current epoch, L+8 previous epoch,
 * L+16 total active balance, L+24 its square root, L+32 leak, L+40 previous epoch + 1,
 * L+48 EFFECTIVE_BALANCE_INCREMENT, L+56 to L+72 weight * unslashed_participating_increments
 * of the source, target and head flags, L+80 active_increments * WEIGHT_DENOMINATOR,
 * L+88 the inactivity penalty denominator, L+96 base reward per increment.
 */
SPEC_FUNCTION process_rewards_and_penalties
    ENTER 112
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 11, 9f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    cmpq    $GENESIS_EPOCH, L(%rsp)
    je      8f
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     CONFIG_INACTIVITY_SCORE_BIAS(%rbp), %rax
    imul    $FORK_INACTIVITY_PENALTY_QUOTIENT, %rax, %rax   # penalty_denominator
    mov     %rax, (L + 88)(%rsp)
    movq    $EFFECTIVE_BALANCE_INCREMENT, (L + 48)(%rsp)
    mov     L(%rsp), %rsi                   # current
    mov     (L + 8)(%rsp), %rdi             # previous
    PART    %r14, %rbp, %rbx, BeaconState_validators
    PART    %r12, %rax, %rbx, BeaconState_previous_epoch_participation
    xor     %r8d, %r8d                      # total active balance
    xor     %r9d, %r9d                      # the source, target and head balances
    xor     %r10d, %r10d
    xor     %r11d, %r11d
    test    %rbp, %rbp
    jz      2f
1:  mov     Validator_activation_epoch(%r14), %rax
    mov     Validator_exit_epoch(%r14), %rcx
    mov     Validator_effective_balance(%r14), %rdx
    cmp     %rsi, %rax                      # is_active_validator(validator, current)
    ja      3f
    cmp     %rcx, %rsi
    jae     3f
    add     %rdx, %r8
3:  cmp     %rdi, %rax                      # active in previous and not slashed: its flags count
    ja      4f
    cmp     %rcx, %rdi
    jae     4f
    cmpb    $0, Validator_slashed(%r14)
    jne     4f
    movzbl  (%r12), %r15d                   # previous_epoch_participation[index]
    bt      $TIMELY_SOURCE_FLAG_INDEX, %r15d
    sbb     %rax, %rax
    and     %rdx, %rax
    add     %rax, %r9
    bt      $TIMELY_TARGET_FLAG_INDEX, %r15d
    sbb     %rax, %rax
    and     %rdx, %rax
    add     %rax, %r10
    bt      $TIMELY_HEAD_FLAG_INDEX, %r15d
    sbb     %rax, %rax
    and     %rdx, %rax
    add     %rax, %r11
4:  add     $Validator__mem, %r14
    inc     %r12
    dec     %rbp
    jnz     1b
2:  mov     $EFFECTIVE_BALANCE_INCREMENT, %rcx    # get_total_balance: max(EFFECTIVE_BALANCE_INCREMENT, sum)
    cmp     %rcx, %r8
    cmovbe  %rcx, %r8
    cmp     %rcx, %r9
    cmovbe  %rcx, %r9
    cmp     %rcx, %r10
    cmovbe  %rcx, %r10
    cmp     %rcx, %r11
    cmovbe  %rcx, %r11
    mov     %r8, (L + 16)(%rsp)
    mov     %r9, %rax                       # weight * unslashed_participating_increments
    xor     %edx, %edx
    div     %rcx
    imul    $TIMELY_SOURCE_WEIGHT, %rax, %rax
    mov     %rax, (L + 56)(%rsp)
    mov     %r10, %rax
    xor     %edx, %edx
    div     %rcx
    imul    $TIMELY_TARGET_WEIGHT, %rax, %rax
    mov     %rax, (L + 64)(%rsp)
    mov     %r11, %rax
    xor     %edx, %edx
    div     %rcx
    imul    $TIMELY_HEAD_WEIGHT, %rax, %rax
    mov     %rax, (L + 72)(%rsp)
    mov     %r8, %rax                       # active_increments * WEIGHT_DENOMINATOR
    xor     %edx, %edx
    div     %rcx
    imul    $WEIGHT_DENOMINATOR, %rax, %rax
    mov     %rax, (L + 80)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 32)(%rsp), %rsi
    call    lantern_is_in_inactivity_leak
    lea     (L + 16)(%rsp), %rdi            # get_base_reward_per_increment
    lea     (L + 24)(%rsp), %rsi
    call    lantern_integer_squareroot
    MOVQ    %rax, EFFECTIVE_BALANCE_INCREMENT * BASE_REWARD_FACTOR
    xor     %edx, %edx
    divq    (L + 24)(%rsp)
    mov     %rax, (L + 96)(%rsp)
    mov     (L + 8)(%rsp), %rdi             # previous epoch, and it + 1
    lea     1(%rdi), %rax
    mov     %rax, (L + 40)(%rsp)
    PART    %r14, %rbp, %rbx, BeaconState_validators
    PART    %r12, %rax, %rbx, BeaconState_previous_epoch_participation
    PART    %rsi, %rax, %rbx, BeaconState_inactivity_scores
    PART    %rax, %rcx, %rbx, BeaconState_balances
    mov     %rax, %rbx
    xor     %r15d, %r15d
    test    %rbp, %rbp
    jz      8f
5:  mov     Validator_activation_epoch(%r14), %rax
    mov     Validator_exit_epoch(%r14), %rcx
    movzbl  (%r12,%r15), %r8d               # previous_epoch_participation[index]
    cmp     %rdi, %rax                      # is_active_validator(validator, previous)
    ja      6f
    cmp     %rcx, %rdi
    jae     6f
    cmpb    $0, Validator_slashed(%r14)
    je      10f
    xor     %r8d, %r8d                      # slashed: in no unslashed participating set
    jmp     10f
6:  cmpb    $0, Validator_slashed(%r14)     # get_eligible_validator_indices: or slashed and
    je      7f
    mov     (L + 40)(%rsp), %rax            # previous_epoch + 1 < withdrawable_epoch
    cmp     Validator_withdrawable_epoch(%r14), %rax
    jae     7f
    xor     %r8d, %r8d
10: mov     Validator_effective_balance(%r14), %r9
    mov     %r9, %rax                       # base_reward = get_base_reward(state, index)
    xor     %edx, %edx
    divq    (L + 48)(%rsp)
    imul    (L + 96)(%rsp), %rax
    mov     %rax, %r10
    mov     (%rbx,%r15,8), %r11             # balances[index]
    xor     %ecx, %ecx
    bt      $TIMELY_SOURCE_FLAG_INDEX, %r8d
    jnc     11f
    cmpq    $0, (L + 32)(%rsp)              # participating: a reward unless leaking
    jne     12f
    mov     %r10, %rax
    imul    (L + 56)(%rsp), %rax
    xor     %edx, %edx
    divq    (L + 80)(%rsp)
    add     %rax, %r11
    jmp     12f
11: imul    $TIMELY_SOURCE_WEIGHT, %r10, %rax   # not participating: decrease_balance by the penalty
    shr     $6, %rax                        # // WEIGHT_DENOMINATOR, which is 64
    sub     %rax, %r11
    cmovb   %rcx, %r11
12: bt      $TIMELY_TARGET_FLAG_INDEX, %r8d
    jnc     13f
    cmpq    $0, (L + 32)(%rsp)
    jne     14f
    mov     %r10, %rax
    imul    (L + 64)(%rsp), %rax
    xor     %edx, %edx
    divq    (L + 80)(%rsp)
    add     %rax, %r11
    jmp     14f
13: imul    $TIMELY_TARGET_WEIGHT, %r10, %rax
    shr     $6, %rax
    sub     %rax, %r11
    cmovb   %rcx, %r11
14: bt      $TIMELY_HEAD_FLAG_INDEX, %r8d   # no head penalty
    jnc     15f
    cmpq    $0, (L + 32)(%rsp)
    jne     15f
    mov     %r10, %rax
    imul    (L + 72)(%rsp), %rax
    xor     %edx, %edx
    divq    (L + 80)(%rsp)
    add     %rax, %r11
15: bt      $TIMELY_TARGET_FLAG_INDEX, %r8d # get_inactivity_penalty_deltas
    jc      16f
    mov     %r9, %rax
    imul    (%rsi,%r15,8), %rax             # penalty_numerator
    xor     %edx, %edx
    divq    (L + 88)(%rsp)
    xor     %ecx, %ecx
    sub     %rax, %r11
    cmovb   %rcx, %r11
16: mov     %r11, (%rbx,%r15,8)
7:  add     $Validator__mem, %r14
    inc     %r15
    cmp     %rbp, %r15
    jb      5b
8:  movq    $0, (%r13)
    xor     %eax, %eax
    LEAVE 112
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 112
SPEC_END process_rewards_and_penalties
.endif

/* ---------------------------------------------------------------- Registry */

.if FORK >= FORK_ELECTRA
/*
 * rbx state, rbp config, r12 scratch, r13 result, r14 validator, r15 index, S7 validator count.
 * Locals: L current epoch, L+8 activation epoch, L+16 predicate, L+24 index.
 */
SPEC_FUNCTION process_registry_updates
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 1, 9f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    lea     L(%rsp), %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_compute_activation_exit_epoch
    mov     (BeaconState_validators + 8)(%rbx), %rax
    mov     %rax, S7(%rsp)
    xor     %r15d, %r15d
1:  cmp     S7(%rsp), %r15
    jae     8f
    mov     BeaconState_validators(%rbx), %r14
    add     %rbx, %r14
    mov     %r15, %rax
    shl     $7, %rax
    add     %rax, %r14
    mov     %r14, %rdi
    lea     (L + 16)(%rsp), %rsi
    call    lantern_is_eligible_for_activation_queue
    cmpq    $0, (L + 16)(%rsp)
    je      2f
    mov     L(%rsp), %rax                   # activation_eligibility_epoch = current_epoch + 1
    inc     %rax
    mov     %rax, Validator_activation_eligibility_epoch(%r14)
    jmp     4f
2:  mov     %r14, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_is_active_validator
    cmpq    $0, (L + 16)(%rsp)
    je      3f
    mov     CONFIG_EJECTION_BALANCE(%rbp), %rax
    cmp     %rax, Validator_effective_balance(%r14)
    ja      3f
    mov     %r15, (L + 24)(%rsp)            # initiate_validator_exit(state, index)
    mov     %rbx, %rdi
    lea     (L + 24)(%rsp), %rsi
    mov     %rbp, %rdx
    mov     %r12, %rcx
    mov     %r13, %r8
    call    lantern_initiate_validator_exit
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r13)
    jne     7f
    jmp     4f
3:  mov     %rbx, %rdi
    mov     %r14, %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_is_eligible_for_activation
    cmpq    $0, (L + 16)(%rsp)
    je      4f
    mov     (L + 8)(%rsp), %rax
    mov     %rax, Validator_activation_epoch(%r14)
4:  inc     %r15
    jmp     1b
8:  movq    $0, (%r13)
    xor     %eax, %eax
7:  LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
SPEC_END process_registry_updates

/* rbx state, rbp index, r12 config, r13 scratch, r14 validator, r15 result. Locals: L exit queue epoch. */
SPEC_FUNCTION initiate_validator_exit
    ENTER 16
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r15
    NEED_SCRATCH %r13, %rbx, 1, 9f
    movq    $0, (%r15)
    mov     BeaconState_validators(%rbx), %r14
    add     %rbx, %r14
    mov     %rbp, %rax
    shl     $7, %rax
    add     %rax, %r14
    cmpq    $-1, Validator_exit_epoch(%r14) # already exiting
    jne     8f
    mov     %rbx, %rdi
    lea     Validator_effective_balance(%r14), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    lea     L(%rsp), %r8
    mov     %r15, %r9
    call    lantern_compute_exit_epoch_and_update_churn
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r15)
    jne     8f
    mov     L(%rsp), %rax
    mov     %rax, Validator_exit_epoch(%r14)
    add     CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY(%r12), %rax  # exit_epoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY
    jc      6f
    mov     %rax, Validator_withdrawable_epoch(%r14)
8:  xor     %eax, %eax
7:  LEAVE 16
6:  movq    $LANTERN_INVALID_OVERFLOW, (%r15)
    xor     %eax, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END initiate_validator_exit
.else
/*
 * Before electra. rbx state, rbp config, r12 scratch, r13 result, r14 validator, r15 index,
 * S7 validator count, S8 activations left, S9 the queue's next validator, S10 its key.
 * Locals: L current epoch, L+8 activation epoch, L+16 predicate, L+24 index, L+32 churn limit.
 */
SPEC_FUNCTION process_registry_updates
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    movq    $0, (%r13)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    lea     L(%rsp), %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_compute_activation_exit_epoch
    mov     (BeaconState_validators + 8)(%rbx), %rax
    mov     %rax, S7(%rsp)
    xor     %r15d, %r15d
1:  cmp     S7(%rsp), %r15                  # for index, validator in enumerate(state.validators)
    jae     4f
    VALIDATOR %r14, %rbx, %r15
    mov     %r14, %rdi
    lea     (L + 16)(%rsp), %rsi
    call    lantern_is_eligible_for_activation_queue
    cmpq    $0, (L + 16)(%rsp)
    je      2f
    mov     L(%rsp), %rax                   # activation_eligibility_epoch = current_epoch + 1
    inc     %rax
    mov     %rax, Validator_activation_eligibility_epoch(%r14)
2:  mov     %r14, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_is_active_validator
    cmpq    $0, (L + 16)(%rsp)
    je      3f
    mov     CONFIG_EJECTION_BALANCE(%rbp), %rax
    cmp     %rax, Validator_effective_balance(%r14)
    ja      3f
    mov     %r15, (L + 24)(%rsp)            # initiate_validator_exit(state, index)
    mov     %rbx, %rdi
    lea     (L + 24)(%rsp), %rsi
    mov     %rbp, %rdx
    mov     %r12, %rcx
    mov     %r13, %r8
    call    lantern_initiate_validator_exit
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r13)
    jne     7f
3:  inc     %r15
    jmp     1b
4:  mov     %rbx, %rdi                      # the churn limit
    mov     %rbp, %rsi
    lea     (L + 32)(%rsp), %rdx
.if FORK == FORK_DENEB
    call    lantern_get_validator_activation_churn_limit
.else
    call    lantern_get_validator_churn_limit
.endif
    mov     (L + 32)(%rsp), %rax
    mov     %rax, S8(%rsp)
5:  cmpq    $0, S8(%rsp)                    # the queue, by (activation_eligibility_epoch, index):
    je      8f
    movq    $-1, S9(%rsp)                   # take its first validator, which activation then leaves out
    movq    $-1, S10(%rsp)
    xor     %r15d, %r15d
51: cmp     S7(%rsp), %r15
    jae     54f
    VALIDATOR %r14, %rbx, %r15
    mov     %rbx, %rdi
    mov     %r14, %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_is_eligible_for_activation
    cmpq    $0, (L + 16)(%rsp)
    je      53f
    mov     Validator_activation_eligibility_epoch(%r14), %rax
    cmp     S10(%rsp), %rax                 # the lowest epoch; in index order, the first wins a tie
    jae     53f
    mov     %rax, S10(%rsp)
    mov     %r15, S9(%rsp)
53: inc     %r15
    jmp     51b
54: mov     S9(%rsp), %rax
    cmp     $-1, %rax
    je      8f                              # the queue is empty
    VALIDATOR %r14, %rbx, %rax
    mov     (L + 8)(%rsp), %rax             # activation_epoch = compute_activation_exit_epoch(get_current_epoch(state))
    mov     %rax, Validator_activation_epoch(%r14)
    decq    S8(%rsp)
    jmp     5b
8:  movq    $0, (%r13)
    xor     %eax, %eax
7:  LEAVE 48
SPEC_END process_registry_updates

/* Before electra. A leaf. */
SPEC_LEAF get_validator_churn_limit
    mov     BeaconState_slot(%rdi), %r8
    shr     $LOG2_SLOTS_PER_EPOCH, %r8      # the current epoch
    PART    %r9, %rcx, %rdi, BeaconState_validators
    xor     %eax, %eax                      # len(get_active_validator_indices(state, get_current_epoch(state)))
1:  test    %rcx, %rcx
    jz      3f
    cmp     %r8, Validator_activation_epoch(%r9)
    ja      2f
    cmp     Validator_exit_epoch(%r9), %r8
    jae     2f
    inc     %rax
2:  add     $Validator__mem, %r9
    dec     %rcx
    jmp     1b
3:  mov     %rdx, %r9
    xor     %edx, %edx
    divq    CONFIG_CHURN_LIMIT_QUOTIENT(%rsi)
    mov     CONFIG_MIN_PER_EPOCH_CHURN_LIMIT(%rsi), %rcx
    cmp     %rcx, %rax                      # max(MIN_PER_EPOCH_CHURN_LIMIT, ...)
    cmovb   %rcx, %rax
    mov     %rax, (%r9)
    RETURN_OK
SPEC_END get_validator_churn_limit

.if FORK == FORK_DENEB
/* Locals: rsp+0 config, rsp+8 out, rsp+16 churn limit. */
SPEC_FUNCTION get_validator_activation_churn_limit
    FRAME 32
    mov     %rsi, 0(%rsp)
    mov     %rdx, 8(%rsp)
    lea     16(%rsp), %rdx
    call    lantern_get_validator_churn_limit
    mov     0(%rsp), %rsi
    mov     16(%rsp), %rax
    mov     CONFIG_MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT(%rsi), %rcx
    cmp     %rcx, %rax                      # min(MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT, get_validator_churn_limit(state))
    cmova   %rcx, %rax
    mov     8(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
    UNFRAME 32
SPEC_END get_validator_activation_churn_limit
.endif

/*
 * Before electra. rbx state, rbp index, r12 config, r14 validator, r15 result.
 * Locals: L current epoch, L+8 exit queue epoch, L+16 churn limit.
 */
SPEC_FUNCTION initiate_validator_exit
    ENTER 32
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    mov     %r8, %r15
    movq    $0, (%r15)
    VALIDATOR %r14, %rbx, %rbp
    cmpq    $-1, Validator_exit_epoch(%r14) # already exiting
    jne     8f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    lea     L(%rsp), %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_compute_activation_exit_epoch
    test    %rax, %rax
    jnz     6f
    mov     (L + 8)(%rsp), %rax             # exit_queue_epoch = max(exit_epochs + [compute_activation_exit_epoch(...)])
    PART    %r8, %rcx, %rbx, BeaconState_validators
1:  test    %rcx, %rcx
    jz      2f
    mov     Validator_exit_epoch(%r8), %rdx
    cmp     $-1, %rdx
    je      11f
    cmp     %rax, %rdx
    cmova   %rdx, %rax
11: add     $Validator__mem, %r8
    dec     %rcx
    jmp     1b
2:  PART    %r8, %rcx, %rbx, BeaconState_validators
    xor     %edx, %edx                      # exit_queue_churn = len([v for v in validators if v.exit_epoch == exit_queue_epoch])
3:  test    %rcx, %rcx
    jz      4f
    cmp     Validator_exit_epoch(%r8), %rax
    jne     31f
    inc     %rdx
31: add     $Validator__mem, %r8
    dec     %rcx
    jmp     3b
4:  mov     %rax, (L + 8)(%rsp)
    mov     %rdx, L(%rsp)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_get_validator_churn_limit
    mov     (L + 8)(%rsp), %rax
    mov     L(%rsp), %rdx
    cmp     (L + 16)(%rsp), %rdx            # if exit_queue_churn >= get_validator_churn_limit(state): exit_queue_epoch += 1
    jb      5f
    add     $1, %rax
    jc      6f
5:  mov     %rax, Validator_exit_epoch(%r14)
    add     CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY(%r12), %rax  # exit_epoch + MIN_VALIDATOR_WITHDRAWABILITY_DELAY
    jc      6f
    mov     %rax, Validator_withdrawable_epoch(%r14)
8:  xor     %eax, %eax
    LEAVE 32
6:  movq    $LANTERN_INVALID_OVERFLOW, (%r15)
    xor     %eax, %eax
    LEAVE 32
SPEC_END initiate_validator_exit
.endif

.if FORK >= FORK_ELECTRA
/*
 * rbx state, rbp exit balance, r12 config, r13 scratch, r14 out, r15 result, S7 earliest exit epoch.
 * Locals: L current epoch, L+8 activation exit epoch, L+16 churn.
 */
SPEC_FUNCTION compute_exit_epoch_and_update_churn
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
    mov     BeaconState_earliest_exit_epoch(%rbx), %rax
    mov     (L + 8)(%rsp), %rcx
    cmp     %rcx, %rax                      # max(state.earliest_exit_epoch, activation exit epoch)
    cmovb   %rcx, %rax
    mov     %rax, S7(%rsp)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %r13, %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_get_activation_exit_churn_limit
    test    %rax, %rax
    jnz     7f
    mov     S7(%rsp), %rsi                  # earliest_exit_epoch
    mov     (L + 16)(%rsp), %rdi            # per_epoch_churn
    mov     BeaconState_exit_balance_to_consume(%rbx), %r8
    cmp     %rsi, BeaconState_earliest_exit_epoch(%rbx)    # a new earliest epoch starts with a full churn
    jae     2f
    mov     %rdi, %r8
2:  cmp     %r8, %rbp
    jbe     3f
    mov     %rbp, %rax                      # balance_to_process
    sub     %r8, %rax
    dec     %rax
    xor     %edx, %edx
    div     %rdi
    inc     %rax                            # additional_epochs
    add     %rax, %rsi
    jc      6f
    mul     %rdi                            # additional_epochs * per_epoch_churn, checked
    test    %rdx, %rdx
    jnz     6f
    add     %rax, %r8
    jc      6f
3:  sub     %rbp, %r8
    mov     %r8, BeaconState_exit_balance_to_consume(%rbx)
    mov     %rsi, BeaconState_earliest_exit_epoch(%rbx)
    mov     %rsi, (%r14)
    xor     %eax, %eax
7:  LEAVE 32
6:  movq    $LANTERN_INVALID_OVERFLOW, (%r15)
    xor     %eax, %eax
    LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
SPEC_END compute_exit_epoch_and_update_churn
.endif

.if FORK >= FORK_ELECTRA
/* Locals: rsp+0 config, rsp+8 out, rsp+16 total active balance. */
SPEC_FUNCTION get_balance_churn_limit
    FRAME 32
    mov     %rsi, 0(%rsp)
    mov     %rcx, 8(%rsp)
    mov     %rdx, %rsi
    lea     16(%rsp), %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     1f
    mov     0(%rsp), %rsi
    mov     16(%rsp), %rax
    xor     %edx, %edx
    divq    CONFIG_CHURN_LIMIT_QUOTIENT(%rsi)
    mov     CONFIG_MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA(%rsi), %rcx
    cmp     %rcx, %rax                      # churn = max(MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA, total // quotient)
    cmovb   %rcx, %rax
    MOVQ    %rcx, EFFECTIVE_BALANCE_INCREMENT
    xor     %edx, %edx
    div     %rcx
    imul    %rcx, %rax                      # churn - churn % EFFECTIVE_BALANCE_INCREMENT
    mov     8(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
1:  UNFRAME 32
SPEC_END get_balance_churn_limit
.endif

.if FORK >= FORK_ELECTRA
/* Locals: rsp+0 config, rsp+8 out, rsp+16 the balance churn limit. */
SPEC_FUNCTION get_activation_exit_churn_limit
    FRAME 32
    mov     %rsi, 0(%rsp)
    mov     %rcx, 8(%rsp)
    lea     16(%rsp), %rcx
    call    lantern_get_balance_churn_limit
    test    %rax, %rax
    jnz     1f
    mov     0(%rsp), %rsi
    mov     16(%rsp), %rax
    mov     CONFIG_MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT(%rsi), %rcx
    cmp     %rcx, %rax
    cmovae  %rcx, %rax
    mov     8(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
1:  UNFRAME 32
SPEC_END get_activation_exit_churn_limit
.endif

.if FORK >= FORK_ELECTRA
/* Locals: rsp+0 state, rsp+8 config, rsp+16 scratch, rsp+24 out, rsp+32 balance churn, rsp+40 activation exit churn. */
SPEC_FUNCTION get_consolidation_churn_limit
    FRAME 48
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    mov     %rcx, 24(%rsp)
    lea     32(%rsp), %rcx
    call    lantern_get_balance_churn_limit
    test    %rax, %rax
    jnz     1f
    mov     0(%rsp), %rdi
    mov     8(%rsp), %rsi
    mov     16(%rsp), %rdx
    lea     40(%rsp), %rcx
    call    lantern_get_activation_exit_churn_limit
    test    %rax, %rax
    jnz     1f
    mov     32(%rsp), %rax
    sub     40(%rsp), %rax
    mov     24(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
1:  UNFRAME 48
SPEC_END get_consolidation_churn_limit
.endif

/* ---------------------------------------------------------------- Slashings */

/*
 * rbx state, rbp config, r12 scratch, r13 result, r14 index, r15 penalty per increment.
 * Locals: L epoch, L+8 total balance, L+16 index, L+24 penalty.
 */
SPEC_FUNCTION process_slashings
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 1, 9f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     7f
    lea     BeaconState_slashings(%rbx), %rcx   # sum(state.slashings)
    mov     $EPOCHS_PER_SLASHINGS_VECTOR, %edx
    xor     %eax, %eax
1:  add     (%rcx), %rax
    add     $8, %rcx
    dec     %rdx
    jnz     1b
    imul    $FORK_PROPORTIONAL_SLASHING_MULTIPLIER, %rax, %rax
    mov     (L + 8)(%rsp), %rcx
    cmp     %rcx, %rax                      # adjusted_total_slashing_balance
    cmovae  %rcx, %rax
.if FORK >= FORK_ELECTRA
    mov     %rax, %rsi
    mov     %rcx, %rax
    MOVQ    %rcx, EFFECTIVE_BALANCE_INCREMENT
    xor     %edx, %edx
    div     %rcx
    mov     %rax, %rcx
    mov     %rsi, %rax
    xor     %edx, %edx
    div     %rcx
.endif
    mov     %rax, %r15                      # penalty_per_effective_balance_increment; before electra the adjusted total
    xor     %r14d, %r14d
2:  cmp     (BeaconState_validators + 8)(%rbx), %r14
    jae     8f
    mov     BeaconState_validators(%rbx), %rcx
    add     %rbx, %rcx
    mov     %r14, %rax
    shl     $7, %rax
    add     %rax, %rcx
    cmpb    $0, Validator_slashed(%rcx)
    je      3f
    mov     L(%rsp), %rax
    add     $(EPOCHS_PER_SLASHINGS_VECTOR / 2), %rax
    cmp     Validator_withdrawable_epoch(%rcx), %rax
    jne     3f
    mov     Validator_effective_balance(%rcx), %rax
    MOVQ    %rcx, EFFECTIVE_BALANCE_INCREMENT
    xor     %edx, %edx
    div     %rcx
    imul    %r15, %rax
.if FORK < FORK_ELECTRA
    xor     %edx, %edx                      # penalty_numerator // total_balance * increment
    divq    (L + 8)(%rsp)
    imul    %rcx, %rax
.endif
    mov     %rax, (L + 24)(%rsp)
    mov     %r14, (L + 16)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    call    lantern_decrease_balance
3:  inc     %r14
    jmp     2b
8:  movq    $0, (%r13)
    xor     %eax, %eax
7:  LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
SPEC_END process_slashings

/* ---------------------------------------------------------------- Eth1 data, consolidations */

/* Locals: rsp+0 state, rsp+8 result, rsp+16 epoch. */
SPEC_FUNCTION process_eth1_data_reset
    FRAME 32
    mov     %rdi, 0(%rsp)
    mov     %rcx, 8(%rsp)
    lea     16(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     0(%rsp), %rdi
    mov     16(%rsp), %rax
    inc     %rax                            # next_epoch % EPOCHS_PER_ETH1_VOTING_PERIOD == 0
    xor     %edx, %edx
    mov     $EPOCHS_PER_ETH1_VOTING_PERIOD, %ecx
    div     %rcx
    test    %rdx, %rdx
    jnz     1f
    movq    $0, (BeaconState_eth1_data_votes + 8)(%rdi)
1:  mov     8(%rsp), %rcx
    movq    $0, (%rcx)
    xor     %eax, %eax
    UNFRAME 32
SPEC_END process_eth1_data_reset

.if FORK >= FORK_ELECTRA
/*
 * rbx state, rbp result, r12 next epoch, r13 consolidation, r14 consolidations left, r15 processed.
 * Locals: L epoch, L+8 source index, L+16 target index, L+24 balance.
 */
SPEC_FUNCTION process_pending_consolidations
    ENTER 32
    mov     %rdi, %rbx
    mov     %rcx, %rbp
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     L(%rsp), %r12
    inc     %r12
    PART    %r13, %r14, %rbx, BeaconState_pending_consolidations
    xor     %r15d, %r15d
1:  test    %r14, %r14
    jz      4f
    mov     PendingConsolidation_source_index(%r13), %rax
    mov     BeaconState_validators(%rbx), %rcx
    add     %rbx, %rcx
    mov     %rax, %rdx
    shl     $7, %rdx
    add     %rdx, %rcx                      # source_validator
    cmpb    $0, Validator_slashed(%rcx)
    jne     3f
    cmp     %r12, Validator_withdrawable_epoch(%rcx)
    ja      4f
    mov     BeaconState_balances(%rbx), %rdx
    add     %rbx, %rdx
    mov     (%rdx,%rax,8), %rdx
    mov     Validator_effective_balance(%rcx), %rcx
    cmp     %rcx, %rdx                      # source_effective_balance
    cmovae  %rcx, %rdx
    mov     %rdx, (L + 24)(%rsp)
    mov     %rax, (L + 8)(%rsp)
    mov     PendingConsolidation_target_index(%r13), %rax
    mov     %rax, (L + 16)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    call    lantern_decrease_balance
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    call    lantern_increase_balance
3:  inc     %r15
    add     $PendingConsolidation__mem, %r13
    dec     %r14
    jmp     1b
4:  test    %r15, %r15                      # pending_consolidations = pending_consolidations[processed:]
    jz      5f
    PART    %rdi, %rcx, %rbx, BeaconState_pending_consolidations
    sub     %r15, %rcx
    mov     %rcx, (BeaconState_pending_consolidations + 8)(%rbx)
    mov     %r15, %rsi
    shl     $4, %rsi                        # PendingConsolidation__mem is 16
    add     %rdi, %rsi
    mov     %rcx, %rdx
    shl     $4, %rdx
    call    lantern_copy
5:  movq    $0, (%rbp)
    xor     %eax, %eax
    LEAVE 32
SPEC_END process_pending_consolidations
.endif

.if FORK >= FORK_ELECTRA
.if PendingConsolidation__mem != 16
.error "lantern_process_pending_consolidations shifts by 4 for PendingConsolidation"
.endif
.endif

/* ---------------------------------------------------------------- Effective balances */

/* rbx state, rbp result, r12 validator, r13 index, r14 validator count. Locals: L max effective balance. */
SPEC_FUNCTION process_effective_balance_updates
    ENTER 16
    mov     %rdi, %rbx
    mov     %rcx, %rbp
    mov     (BeaconState_validators + 8)(%rbx), %r14
    xor     %r13d, %r13d
1:  cmp     %r14, %r13
    jae     3f
    mov     BeaconState_validators(%rbx), %r12
    add     %rbx, %r12
    mov     %r13, %rax
    shl     $7, %rax
    add     %rax, %r12
.if FORK >= FORK_ELECTRA
    mov     %r12, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_max_effective_balance
.else
    MOVQ    %rax, MAX_EFFECTIVE_BALANCE
    mov     %rax, L(%rsp)
.endif
    mov     BeaconState_balances(%rbx), %rcx
    add     %rbx, %rcx
    mov     (%rcx,%r13,8), %rax             # balance
    mov     Validator_effective_balance(%r12), %rcx
    MOVQ    %rdx, (EFFECTIVE_BALANCE_INCREMENT / HYSTERESIS_QUOTIENT) * HYSTERESIS_DOWNWARD_MULTIPLIER
    add     %rax, %rdx
    cmp     %rcx, %rdx                      # balance + DOWNWARD_THRESHOLD < effective_balance
    jb      2f
    MOVQ    %rdx, (EFFECTIVE_BALANCE_INCREMENT / HYSTERESIS_QUOTIENT) * HYSTERESIS_UPWARD_MULTIPLIER
    add     %rcx, %rdx
    cmp     %rax, %rdx                      # or effective_balance + UPWARD_THRESHOLD < balance
    jae     25f
2:  MOVQ    %rcx, EFFECTIVE_BALANCE_INCREMENT
    xor     %edx, %edx
    div     %rcx
    imul    %rcx, %rax                      # balance - balance % EFFECTIVE_BALANCE_INCREMENT
    cmp     L(%rsp), %rax
    jb      21f
    mov     L(%rsp), %rax
21: mov     %rax, Validator_effective_balance(%r12)
25: inc     %r13
    jmp     1b
3:  movq    $0, (%rbp)
    xor     %eax, %eax
    LEAVE 16
SPEC_END process_effective_balance_updates

/* ---------------------------------------------------------------- Resets and rotations */

/* Locals: rsp+0 state, rsp+8 result, rsp+16 epoch. */
SPEC_FUNCTION process_slashings_reset
    FRAME 32
    mov     %rdi, 0(%rsp)
    mov     %rcx, 8(%rsp)
    lea     16(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     0(%rsp), %rdi
    mov     16(%rsp), %rax
    inc     %rax
    and     $(EPOCHS_PER_SLASHINGS_VECTOR - 1), %eax
    movq    $0, BeaconState_slashings(%rdi,%rax,8)
    mov     8(%rsp), %rcx
    movq    $0, (%rcx)
    xor     %eax, %eax
    UNFRAME 32
SPEC_END process_slashings_reset

/* Locals: rsp+0 state, rsp+8 result, rsp+16 epoch. */
SPEC_FUNCTION process_randao_mixes_reset
    FRAME 32
    mov     %rdi, 0(%rsp)
    mov     %rcx, 8(%rsp)
    lea     16(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     0(%rsp), %rdi
    mov     16(%rsp), %rax
    inc     %rax                            # randao_mixes[next % EPOCHS_PER_HISTORICAL_VECTOR]
    and     $(EPOCHS_PER_HISTORICAL_VECTOR - 1), %eax
    shl     $5, %rax
    lea     BeaconState_randao_mixes(%rdi,%rax), %rdx
    lea     16(%rsp), %rsi
    call    lantern_get_randao_mix
    mov     8(%rsp), %rcx
    movq    $0, (%rcx)
    xor     %eax, %eax
    UNFRAME 32
SPEC_END process_randao_mixes_reset

.if FORK <= FORK_BELLATRIX
.if BeaconState_state_roots != BeaconState_block_roots + BlockRoots__mem
.error "the state's block_roots and state_roots are not laid out as one HistoricalBatch"
.endif
/* rbx state, rbp scratch, r12 result, r13 the new entry. Locals: L epoch. */
SPEC_FUNCTION process_historical_roots_update
    ENTER 16
    mov     %rdi, %rbx
    mov     %rdx, %rbp
    mov     %rcx, %r12
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     L(%rsp), %rax                   # if next_epoch % (SLOTS_PER_HISTORICAL_ROOT // SLOTS_PER_EPOCH) == 0
    inc     %rax
    test    $(SLOTS_PER_HISTORICAL_ROOT / SLOTS_PER_EPOCH - 1), %rax
    jnz     8f
    MOVQ    %rax, SSZ_SCR_WORK + HistoricalBatch__work  # scratch for the root
    cmp     %rax, (%rbp)
    jb      9f
    mov     BeaconState_historical_roots(%rbx), %rax
    mov     (BeaconState_historical_roots + 8)(%rbx), %rcx
    mov     BeaconState_eth1_data_votes(%rbx), %rdx     # the next part starts at its room's end
    sub     %rax, %rdx
    lea     1(%rcx), %rsi
    shl     $5, %rsi
    cmp     %rsi, %rdx
    jb      9f
    lea     (%rbx,%rax), %r13
    shl     $5, %rcx
    add     %rcx, %r13
    ADDRESS %rdi, lantern_type_HistoricalBatch  # historical_roots.append(hash_tree_root(HistoricalBatch(block_roots, state_roots)))
    lea     BeaconState_block_roots(%rbx), %rsi
    mov     %rbp, %rdx
    mov     %r13, %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    incq    (BeaconState_historical_roots + 8)(%rbx)
8:  movq    $0, (%r12)
    xor     %eax, %eax
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END process_historical_roots_update
.endif

.if FORK >= FORK_CAPELLA
/* rbx state, rbp scratch, r12 result, r13 the new summary. Locals: L epoch. */
SPEC_FUNCTION process_historical_summaries_update
    ENTER 16
    mov     %rdi, %rbx
    mov     %rdx, %rbp
    mov     %rcx, %r12
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     L(%rsp), %rax
    inc     %rax
    test    $(SLOTS_PER_HISTORICAL_ROOT / SLOTS_PER_EPOCH - 1), %rax
    jnz     8f
    MOVQ    %rax, SSZ_SCR_WORK + BlockRoots__work   # scratch for the roots
    cmp     %rax, (%rbp)
    jb      9f
    mov     BeaconState_historical_summaries(%rbx), %rax
    mov     (BeaconState_historical_summaries + 8)(%rbx), %rcx
.if FORK >= FORK_ELECTRA
    mov     BeaconState_pending_deposits(%rbx), %rdx    # the next part starts its room's end
.else
    mov     (%rbx), %rdx                    # the last part ends at the end of the value
.endif
    sub     %rax, %rdx
    lea     1(%rcx), %rsi
    shl     $6, %rsi                        # HistoricalSummary__mem is 64
    cmp     %rsi, %rdx
    jb      9f
    lea     (%rbx,%rax), %r13
    shl     $6, %rcx
    add     %rcx, %r13
    ADDRESS %rdi, lantern_type_BlockRoots   # block_summary_root = hash_tree_root(state.block_roots)
    lea     BeaconState_block_roots(%rbx), %rsi
    mov     %rbp, %rdx
    lea     HistoricalSummary_block_summary_root(%r13), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    ADDRESS %rdi, lantern_type_BlockRoots   # state_summary_root = hash_tree_root(state.state_roots)
    lea     BeaconState_state_roots(%rbx), %rsi
    mov     %rbp, %rdx
    lea     HistoricalSummary_state_summary_root(%r13), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    incq    (BeaconState_historical_summaries + 8)(%rbx)
8:  movq    $0, (%r12)
    xor     %eax, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END process_historical_summaries_update
.endif

.if FORK >= FORK_CAPELLA
.if HistoricalSummary__mem != 64
.error "lantern_process_historical_summaries_update shifts by 6 for HistoricalSummary"
.endif
.endif

.if FORK >= FORK_ALTAIR
/* rbx state, rbp result. previous_epoch_participation = current; current = zeros, one per validator. */
SPEC_FUNCTION process_participation_flag_updates
    ENTER 16
    mov     %rdi, %rbx
    mov     %rcx, %rbp
    PART    %rsi, %rdx, %rbx, BeaconState_current_epoch_participation
    PART    %rdi, %rcx, %rbx, BeaconState_previous_epoch_participation
    mov     %rdx, (BeaconState_previous_epoch_participation + 8)(%rbx)
    call    lantern_copy
    mov     (BeaconState_validators + 8)(%rbx), %rsi
    mov     %rsi, (BeaconState_current_epoch_participation + 8)(%rbx)
    PART    %rdi, %rcx, %rbx, BeaconState_current_epoch_participation
    call    lantern_zero
    movq    $0, (%rbp)
    xor     %eax, %eax
    LEAVE 16
SPEC_END process_participation_flag_updates
.endif

/* ---------------------------------------------------------------- Proposer lookahead */

.set LOOKAHEAD_LOCALS, (8 * SLOTS_PER_EPOCH + 8 + 15) / 16 * 16

.if FORK >= FORK_FULU
/* rbx state, rbp config, r12 scratch, r13 result. Locals: L the last epoch's proposers, then the epoch. */
SPEC_FUNCTION process_proposer_lookahead
    ENTER LOOKAHEAD_LOCALS
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 2, 9f
    movq    $0, (%r13)
    mov     %rbx, %rdi
    lea     (L + 8 * SLOTS_PER_EPOCH)(%rsp), %rsi
    call    lantern_get_current_epoch
    addq    $(MIN_SEED_LOOKAHEAD + 1), (L + 8 * SLOTS_PER_EPOCH)(%rsp)
    mov     %rbx, %rdi                      # get_beacon_proposer_indices(state, current + MIN_SEED_LOOKAHEAD + 1)
    lea     (L + 8 * SLOTS_PER_EPOCH)(%rsp), %rsi
    mov     %r12, %rdx
    lea     L(%rsp), %rcx
    call    lantern_get_beacon_proposer_indices
    CHECK_STATUS %r13, 7f, 8f
    lea     BeaconState_proposer_lookahead(%rbx), %rdi
    lea     (BeaconState_proposer_lookahead + 8 * SLOTS_PER_EPOCH)(%rbx), %rsi
    mov     $(8 * SLOTS_PER_EPOCH * MIN_SEED_LOOKAHEAD), %edx
    call    lantern_copy
    lea     (BeaconState_proposer_lookahead + 8 * SLOTS_PER_EPOCH * MIN_SEED_LOOKAHEAD)(%rbx), %rdi
    lea     L(%rsp), %rsi
    mov     $(8 * SLOTS_PER_EPOCH), %edx
    call    lantern_copy
8:  xor     %eax, %eax
7:  LEAVE LOOKAHEAD_LOCALS
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
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

/* One step: stop at a failed status or a failed check. rbx, rbp, r12, r13 hold the arguments, r14 the scratch size. */
.macro EPOCH_STEP fn
    mov     %r14, (%r12)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    call    \fn
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (%r13)
    jne     8f
.endm

/* rbx state, rbp config, r12 scratch, r13 result, r14 scratch size. Locals: L epoch. */
SPEC_FUNCTION process_epoch
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH_B %r12, %rbx, EPOCH_LISTS, EPOCH_EXTRA, 9f
.if FORK >= FORK_ELECTRA
    mov     %rbx, %rdi                      # room for the deposits of the epoch
    call    lantern_validator_room
    cmp     $MAX_PENDING_DEPOSITS_PER_EPOCH, %rax
    jb      9f
.endif
.if FORK == FORK_PHASE0
    mov     %rbx, %rdi                      # room for the current epoch's attestations in the previous list
    call    lantern_record_room
    test    %rax, %rax
    jnz     9f
.endif
    mov     %rbx, %rdi                      # and for a historical batch root or summary when one is due
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     L(%rsp), %rax
    inc     %rax
    test    $(SLOTS_PER_HISTORICAL_ROOT / SLOTS_PER_EPOCH - 1), %rax
    jnz     1f
.if FORK >= FORK_CAPELLA
    mov     BeaconState_historical_summaries(%rbx), %rax
    mov     (BeaconState_historical_summaries + 8)(%rbx), %rcx
.if FORK >= FORK_ELECTRA
    mov     BeaconState_pending_deposits(%rbx), %rdx
.else
    mov     (%rbx), %rdx                    # the last part ends at the end of the value
.endif
    sub     %rax, %rdx
    lea     1(%rcx), %rsi
    shl     $6, %rsi
.else
    mov     BeaconState_historical_roots(%rbx), %rax
    mov     (BeaconState_historical_roots + 8)(%rbx), %rcx
    mov     BeaconState_eth1_data_votes(%rbx), %rdx
    sub     %rax, %rdx
    lea     1(%rcx), %rsi
    shl     $5, %rsi
.endif
    cmp     %rsi, %rdx
    jb      9f
1:  mov     (%r12), %r14
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
8:  xor     %eax, %eax
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END process_epoch
