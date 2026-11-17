/*
 * Epoch processing, x86-64. Requirements: docs/reference/epoch-processing.md.
 * v1: each function follows its spec steps and calls the spec functions it
 * names. A call whose result the loop cannot change is made once, before the loop.
 */

/* ---------------------------------------------------------------- Justification and finalization */

.if FORK >= FORK_ALTAIR
/*
 * rbx state, rbp config, r12 scratch, r13 result, r14 validator count, r15 previous list,
 * S7 current list. Locals: L current epoch, L+8 previous epoch, L+16 total active,
 * L+24 previous target balance, L+32 current target balance, L+40 flag index, L+48 the scratch size on entry.
 */
SPEC_FUNCTION process_justification_and_finalization
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 3, 9f
    mov     (BeaconState_validators + 8)(%rbx), %r14
    mov     (%r12), %rax
    mov     %rax, (L + 48)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    cmpq    $(GENESIS_EPOCH + 1), L(%rsp)
    jbe     8f
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_previous_epoch
    movq    $TIMELY_TARGET_FLAG_INDEX, (L + 40)(%rsp)
    mov     (L + 48)(%rsp), %rax
    SCRATCH_LIST %r15, %r12, %rax, 0, %r14
    SCRATCH_LIST %rcx, %r12, %rax, 1, %r14
    mov     %rcx, S7(%rsp)
    SCRATCH_GIVE %r12, %rax, 2, %r14
    mov     %rbx, %rdi                      # previous_indices
    lea     (L + 40)(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    mov     %r12, %rcx
    mov     %r15, %r8
    call    lantern_get_unslashed_participating_indices
    CHECK_STATUS %r13, 7f, 6f
    SCRATCH_GIVE %r12, (L+48)(%rsp), 2, %r14
    mov     %rbx, %rdi                      # current_indices
    lea     (L + 40)(%rsp), %rsi
    lea     L(%rsp), %rdx
    mov     %r12, %rcx
    mov     S7(%rsp), %r8
    call    lantern_get_unslashed_participating_indices
    CHECK_STATUS %r13, 7f, 6f
    SCRATCH_GIVE %r12, (L+48)(%rsp), 2, %r14
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     7f
    mov     %rbx, %rdi
    mov     %r15, %rsi
    lea     (L + 24)(%rsp), %rdx
    call    lantern_get_total_balance
    mov     %rbx, %rdi
    mov     S7(%rsp), %rsi
    lea     (L + 32)(%rsp), %rdx
    call    lantern_get_total_balance
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    lea     (L + 32)(%rsp), %rcx
    mov     %r13, %r8
    call    lantern_weigh_justification_and_finalization
7:  LEAVE 64
6:  xor     %eax, %eax
    LEAVE 64
8:  movq    $0, (%r13)
    xor     %eax, %eax
    LEAVE 64
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
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
 * rbx state, rbp config, r12 scratch, r13 result, r14 eligible cursor, r15 participating cursor,
 * S7 eligible list, S8 participating list, S9 score.
 * Locals: L epoch, L+8 previous epoch, L+16 flag index, L+24 in leak, L+32 eligible end,
 * L+40 participating end, L+56 the constant 1, L+64 the scratch size on entry.
 */
SPEC_FUNCTION process_inactivity_updates
    ENTER 80
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 3, 9f
    mov     (%r12), %rax
    mov     %rax, (L + 64)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    cmpq    $GENESIS_EPOCH, L(%rsp)
    je      8f
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     (L + 64)(%rsp), %rax
    SCRATCH_LIST %rdx, %r12, %rax, 0, %rcx
    mov     %rdx, S7(%rsp)
    SCRATCH_LIST %rdx, %r12, %rax, 1, %rcx
    mov     %rdx, S8(%rsp)
    mov     %rbx, %rdi
    mov     S7(%rsp), %rsi
    call    lantern_get_eligible_validator_indices
    test    %rax, %rax
    jnz     7f
    movq    $TIMELY_TARGET_FLAG_INDEX, (L + 16)(%rsp)
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    SCRATCH_GIVE %r12, (L+64)(%rsp), 2, %rcx
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    mov     %r12, %rcx
    mov     S8(%rsp), %r8
    call    lantern_get_unslashed_participating_indices
    CHECK_STATUS %r13, 7f, 6f
    mov     %rbx, %rdi
    lea     (L + 24)(%rsp), %rsi
    call    lantern_is_in_inactivity_leak
    movq    $1, (L + 56)(%rsp)
    mov     S7(%rsp), %rax
    lea     LIST_FIXED(%rax), %r14
    mov     LIST_COUNT(%rax), %rcx
    lea     (%r14,%rcx,8), %rcx
    mov     %rcx, (L + 32)(%rsp)
    mov     S8(%rsp), %rax
    lea     LIST_FIXED(%rax), %r15
    mov     LIST_COUNT(%rax), %rcx
    lea     (%r15,%rcx,8), %rcx
    mov     %rcx, (L + 40)(%rsp)
1:  cmp     (L + 32)(%rsp), %r14
    jae     8f
    mov     (%r14), %rax                    # index
    add     $8, %r14
    mov     BeaconState_inactivity_scores(%rbx), %rcx
    add     %rbx, %rcx
    lea     (%rcx,%rax,8), %rcx             # &state.inactivity_scores[index]
    mov     %rcx, S9(%rsp)
    IN_SORTED %rax, %r15, (L+40)(%rsp), %rdx
    test    %rdx, %rdx
    jz      2f
    mov     S9(%rsp), %rdi                  # saturating_sub(score, 1)
    lea     (L + 56)(%rsp), %rsi
    mov     %rdi, %rdx
    call    lantern_saturating_sub
    jmp     3f
2:  mov     S9(%rsp), %rcx                  # += INACTIVITY_SCORE_BIAS
    mov     CONFIG_INACTIVITY_SCORE_BIAS(%rbp), %rax
    add     %rax, (%rcx)
3:  cmpq    $0, (L + 24)(%rsp)
    jne     1b
    mov     S9(%rsp), %rdi                  # saturating_sub(score, INACTIVITY_SCORE_RECOVERY_RATE)
    lea     CONFIG_INACTIVITY_SCORE_RECOVERY_RATE(%rbp), %rsi
    mov     %rdi, %rdx
    call    lantern_saturating_sub
    jmp     1b
7:  LEAVE 80
6:  xor     %eax, %eax
    LEAVE 80
8:  movq    $0, (%r13)
    xor     %eax, %eax
    LEAVE 80
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 80
SPEC_END process_inactivity_updates
.endif

/* ---------------------------------------------------------------- Rewards and penalties */

/* Write count n to an output IndexList and zero its n entries. list rdi, n rsi. */
LOCAL_FUNCTION zero_deltas
    UNWIND_END_PROLOGUE
    movq    $LIST_FIXED, LIST_OFFSET(%rdi)
    mov     %rsi, LIST_COUNT(%rdi)
    add     $LIST_FIXED, %rdi
    shl     $3, %rsi
    jmp     lantern_zero
END_FUNCTION zero_deltas

.if FORK >= FORK_ALTAIR
/*
 * rbx state, rbp flag index, r12 scratch, r13 rewards, r14 penalties, r15 eligible cursor,
 * S7 participating list then its cursor, S8 eligible list.
 * Locals: L previous epoch, L+8 participating balance, L+16 total active, L+24 leak,
 * L+32 eligible end, L+40 participating end, L+48 base reward, L+72 index, L+80 weight,
 * L+88 the scratch size on entry.
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
    call    zero_deltas
    mov     %r14, %rdi
    mov     (BeaconState_validators + 8)(%rbx), %rsi
    call    zero_deltas
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
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    SCRATCH_GIVE %r12, (L+88)(%rsp), 2, %rcx
    mov     %rbx, %rdi                      # base_reward = get_base_reward(state, index)
    lea     (L + 72)(%rsp), %rsi
    mov     %r12, %rdx
    lea     (L + 48)(%rsp), %rcx
    call    lantern_get_base_reward
    test    %rax, %rax
    jnz     8f
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
    call    zero_deltas
    mov     %r14, %rdi
    mov     (BeaconState_validators + 8)(%rbx), %rsi
    call    zero_deltas
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
 * rbx state, rbp config, r12 scratch, r13 result, r14 delta pair, r15 index,
 * S7 the scratch size on entry. Scratch: lists 0 to 7 at its end. Locals: L epoch, L+8 flag index, L+16 index.
 */
SPEC_FUNCTION process_rewards_and_penalties
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 11, 9f
    mov     (%r12), %rax
    mov     %rax, S7(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    cmpq    $GENESIS_EPOCH, L(%rsp)
    je      8f
    xor     %r14d, %r14d                    # flag_deltas for each flag
1:  mov     %r14, (L + 8)(%rsp)
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     S7(%rsp), %rax
    lea     (%r14,%r14), %rdx
    SCRATCH_LIST_R %r8, %r12, %rax, %rdx, %rcx
    inc     %rdx
    SCRATCH_LIST_R %r9, %r12, %rax, %rdx, %rcx
    SCRATCH_GIVE %r12, %rax, 8, %rcx
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    mov     %r12, %rdx
    mov     %r8, %rcx
    mov     %r9, %r8
    call    lantern_get_flag_index_deltas
    CHECK_STATUS %r13, 7f, 6f
    inc     %r14
    cmp     $3, %r14
    jb      1b
    mov     (BeaconState_validators + 8)(%rbx), %rcx    # get_inactivity_penalty_deltas
    mov     S7(%rsp), %rax
    SCRATCH_LIST %r8, %r12, %rax, 6, %rcx
    SCRATCH_LIST %r9, %r12, %rax, 7, %rcx
    SCRATCH_GIVE %r12, %rax, 8, %rcx
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r8, %rcx
    mov     %r9, %r8
    call    lantern_get_inactivity_penalty_deltas
    CHECK_STATUS %r13, 7f, 6f
    xor     %r14d, %r14d                    # for rewards, penalties in deltas
2:  xor     %r15d, %r15d
3:  cmp     (BeaconState_validators + 8)(%rbx), %r15
    jae     4f
    mov     %r15, (L + 16)(%rsp)
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     S7(%rsp), %rax
    lea     (%r14,%r14), %rdx
    SCRATCH_LIST_R %r8, %r12, %rax, %rdx, %rcx
    lea     LIST_FIXED(%r8,%r15,8), %rdx
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    call    lantern_increase_balance
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     S7(%rsp), %rax
    lea     1(%r14,%r14), %rdx
    SCRATCH_LIST_R %r8, %r12, %rax, %rdx, %rcx
    lea     LIST_FIXED(%r8,%r15,8), %rdx
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    call    lantern_decrease_balance
    inc     %r15
    jmp     3b
4:  inc     %r14
    cmp     $4, %r14
    jb      2b
8:  movq    $0, (%r13)
6:  xor     %eax, %eax
7:  LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
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
    call    validator_room
    cmp     $MAX_PENDING_DEPOSITS_PER_EPOCH, %rax
    jb      9f
.endif
.if FORK == FORK_PHASE0
    mov     %rbx, %rdi                      # room for the current epoch's attestations in the previous list
    call    record_room
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
