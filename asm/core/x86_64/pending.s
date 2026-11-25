/*
 * Phase0's epoch accounting by PendingAttestation, x86-64: the matching attestations, their
 * unslashed attesting indices and balance, the attestation deltas, and the epoch steps that
 * read them. Requirements: docs/reference/epoch-processing.md.
 *
 * A list of matching attestations is an IndexList of the offsets of PendingAttestation values
 * from the start of the state, in the order of the state's list.
 */

/* The IndexList of the matching attestations of one epoch, at the end of a function's scratch. */
.set PENDING_REFS_BYTES, LIST_FIXED + 8 * MAX_ATTESTATIONS * SLOTS_PER_EPOCH

/* rax = get_base_reward of a validator of effective balance eb, with the square root of the total active balance in sqrt. Uses rdx. */
.macro BASE_REWARD eb, sqrt
    imul    $BASE_REWARD_FACTOR, \eb, %rax
    xor     %edx, %edx
    div     \sqrt
    shr     $2, %rax                        # // BASE_REWARDS_PER_EPOCH, which is 4
.endm
.if BASE_REWARDS_PER_EPOCH != 4
.error "BASE_REWARD divides by BASE_REWARDS_PER_EPOCH with a shift by 2"
.endif

/* Take the refs list from the end of scratch s: refs = its last PENDING_REFS_BYTES, tot = the bytes before. */
.macro TAKE_REFS refs, s, tot
    mov     (\s), \tot
    sub     $PENDING_REFS_BYTES, \tot
    lea     (\s,\tot), \refs
    movq    $PENDING_REFS_BYTES, (\refs)
    mov     \tot, (\s)
.endm

/* ---------------------------------------------------------------- Matching attestations */

/* rbx state, rbp out, r12 epoch. Locals: L previous epoch, L+8 current epoch. */
SPEC_FUNCTION get_matching_source_attestations
    ENTER 16
    mov     %rdi, %rbx
    mov     (%rsi), %r12
    mov     %rdx, %rbp
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_current_epoch
    cmp     (L + 8)(%rsp), %r12             # the current epoch's list when epoch is current
    jne     1f
    mov     $BeaconState_current_epoch_attestations, %ecx
    jmp     2f
1:  cmp     L(%rsp), %r12                   # assert epoch in (previous, current)
    jne     8f
    mov     $BeaconState_previous_epoch_attestations, %ecx
2:  mov     (%rbx,%rcx), %rdx               # the part's offset
    mov     8(%rbx,%rcx), %rsi              # its count
    lea     LIST_FIXED(,%rsi,8), %rax
    cmp     %rax, LIST_SIZE(%rbp)
    jb      9f
    movq    $LIST_FIXED, LIST_OFFSET(%rbp)
    mov     %rsi, LIST_COUNT(%rbp)
    lea     LIST_FIXED(%rbp), %rdi
3:  test    %rsi, %rsi
    jz      4f
    mov     %rdx, (%rdi)
    add     $8, %rdi
    add     (%rbx,%rdx), %rdx               # the next value starts after this one's size
    dec     %rsi
    jmp     3b
4:  xor     %eax, %eax
    LEAVE 16
8:  mov     $LANTERN_INVALID_PARTICIPATION_EPOCH, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END get_matching_source_attestations

/* Keep the refs of out rbp for which the 32 bytes at offset off of the attestation equal the root at L. Uses rax, rcx, rdx, rsi, rdi, r8. */
.macro KEEP_MATCHING off
    lea     LIST_FIXED(%rbp), %rsi
    mov     %rsi, %rdi
    mov     LIST_COUNT(%rbp), %rcx
    lea     (%rsi,%rcx,8), %rdx
91: cmp     %rdx, %rsi
    jae     93f
    mov     (%rsi), %rax
    add     $8, %rsi
    lea     (\off)(%rbx,%rax), %rcx
    lea     L(%rsp), %r8
    NE32    %rcx, %r8, 91b
    mov     %rax, (%rdi)
    add     $8, %rdi
    jmp     91b
93: sub     %rbp, %rdi
    sub     $LIST_FIXED, %rdi
    shr     $3, %rdi
    mov     %rdi, LIST_COUNT(%rbp)
.endm

/* rbx state, rbp out, r12 epoch. Locals: L the epoch's block root (32). */
SPEC_FUNCTION get_matching_target_attestations
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %r12
    mov     %rdx, %rbp
    call    lantern_get_matching_source_attestations
    test    %rax, %rax
    jnz     7f
    cmpq    $0, LIST_COUNT(%rbp)            # the spec reads the root inside the comprehension: none for no attestation
    je      8f
    mov     %rbx, %rdi                      # a.data.target.root == get_block_root(state, epoch)
    mov     %r12, %rsi
    lea     L(%rsp), %rdx
    call    lantern_get_block_root
    test    %rax, %rax
    jnz     7f
    KEEP_MATCHING (PendingAttestation_data + AttestationData_target + Checkpoint_root)
8:  xor     %eax, %eax
7:  LEAVE 32
SPEC_END get_matching_target_attestations

/* rbx state, rbp out, r12 epoch, r13 cursor, r14 kept, r15 end, S7 the attestation's ref. Locals: L root (32). */
SPEC_FUNCTION get_matching_head_attestations
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %r12
    mov     %rdx, %rbp
    call    lantern_get_matching_target_attestations
    test    %rax, %rax
    jnz     7f
    lea     LIST_FIXED(%rbp), %r13
    mov     %r13, %r14
    mov     LIST_COUNT(%rbp), %rcx
    lea     (%r13,%rcx,8), %r15
1:  cmp     %r15, %r13
    jae     3f
    mov     (%r13), %rax
    add     $8, %r13
    mov     %rax, S7(%rsp)
    mov     %rbx, %rdi                      # a.data.beacon_block_root == get_block_root_at_slot(state, a.data.slot)
    lea     (PendingAttestation_data + AttestationData_slot)(%rbx,%rax), %rsi
    lea     L(%rsp), %rdx
    call    lantern_get_block_root_at_slot
    test    %rax, %rax
    jnz     7f
    mov     S7(%rsp), %rax
    lea     (PendingAttestation_data + AttestationData_beacon_block_root)(%rbx,%rax), %rcx
    lea     L(%rsp), %rdx
    NE32    %rcx, %rdx, 1b
    mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    add     $8, %r14
    jmp     1b
3:  mov     %r14, %rax
    sub     %rbp, %rax
    sub     $LIST_FIXED, %rax
    shr     $3, %rax
    mov     %rax, LIST_COUNT(%rbp)
    xor     %eax, %eax
7:  LEAVE 32
SPEC_END get_matching_head_attestations

/* ---------------------------------------------------------------- Attesting indices and balance */

/*
 * rbx state, rbp attestations, r12 scratch, r13 out, r14 scratch size, r15 n, S7 a byte per
 * validator, S8 one attestation's attesting indices, S9 cursor, S10 end.
 * Scratch: list 0 the bytes, list 1 the attesting indices, then get_attesting_indices's S(3).
 */
SPEC_FUNCTION get_unslashed_attesting_indices
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 5, 9f
    mov     (BeaconState_validators + 8)(%rbx), %r15
    lea     LIST_FIXED(,%r15,8), %rax       # out has room for every validator
    cmp     %rax, LIST_SIZE(%r13)
    jb      9f
    mov     (%r12), %r14
    SCRATCH_LIST %rax, %r12, %r14, 0, %r15
    mov     %rax, S7(%rsp)
    SCRATCH_LIST %rax, %r12, %r14, 1, %r15
    mov     %rax, S8(%rsp)
    mov     S7(%rsp), %rdi
    add     $LIST_FIXED, %rdi
    mov     %r15, %rsi
    call    lantern_zero
    lea     LIST_FIXED(%rbp), %rax
    mov     %rax, S9(%rsp)
    mov     LIST_COUNT(%rbp), %rcx
    lea     (%rax,%rcx,8), %rax
    mov     %rax, S10(%rsp)
1:  mov     S9(%rsp), %rax                  # output = union of get_attesting_indices(state, a)
    cmp     S10(%rsp), %rax
    jae     3f
    mov     (%rax), %rcx
    add     $8, %rax
    mov     %rax, S9(%rsp)
    SCRATCH_GIVE %r12, %r14, 2, %r15
    mov     %rbx, %rdi
    lea     (%rbx,%rcx), %rsi
    mov     %r12, %rcx
    mov     S8(%rsp), %r8
    xor     %rdx, %rdx
    call    lantern_get_attesting_indices
    test    %rax, %rax
    jnz     7f
    mov     S8(%rsp), %rsi
    mov     LIST_COUNT(%rsi), %rcx
    add     $LIST_FIXED, %rsi
    mov     S7(%rsp), %rdi
    add     $LIST_FIXED, %rdi
2:  test    %rcx, %rcx
    jz      1b
    mov     (%rsi), %rax
    add     $8, %rsi
    movb    $1, (%rdi,%rax)
    dec     %rcx
    jmp     2b
3:  movq    $LIST_FIXED, LIST_OFFSET(%r13)  # the set, ascending, without the slashed
    PART    %r8, %rax, %rbx, BeaconState_validators
    mov     S7(%rsp), %rsi
    add     $LIST_FIXED, %rsi
    lea     LIST_FIXED(%r13), %rdi
    xor     %ecx, %ecx
    xor     %edx, %edx
4:  cmp     %r15, %rcx
    jae     5f
    cmpb    $0, (%rsi,%rcx)
    je      45f
    cmpb    $0, Validator_slashed(%r8)
    jne     45f
    mov     %rcx, (%rdi)
    add     $8, %rdi
    inc     %rdx
45: inc     %rcx
    add     $Validator__mem, %r8
    jmp     4b
5:  mov     %rdx, LIST_COUNT(%r13)
    xor     %eax, %eax
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END get_unslashed_attesting_indices

/* rbx state, rbp attestations, r12 scratch, r13 out, r14 scratch size, r15 the indices. Scratch: list 0, then S(5). */
SPEC_FUNCTION get_attesting_balance
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 6, 9f
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     (%r12), %r14
    SCRATCH_LIST %r15, %r12, %r14, 0, %rcx
    SCRATCH_GIVE %r12, %r14, 1, %rcx
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r15, %rcx
    call    lantern_get_unslashed_attesting_indices
    test    %rax, %rax
    jnz     7f
    mov     %rbx, %rdi                      # get_total_balance(state, get_unslashed_attesting_indices(...))
    mov     %r15, %rsi
    mov     %r13, %rdx
    call    lantern_get_total_balance
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END get_attesting_balance

/* ---------------------------------------------------------------- Rewards and penalties */

/* Locals: rsp+0 out, rsp+8 base reward. */
SPEC_FUNCTION get_proposer_reward
    FRAME 16
    mov     %rcx, 0(%rsp)
    lea     8(%rsp), %rcx
    call    lantern_get_base_reward
    test    %rax, %rax
    jnz     1f
    mov     8(%rsp), %rax
    mov     $PROPOSER_REWARD_QUOTIENT, %ecx
    xor     %edx, %edx
    div     %rcx
    mov     0(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
1:  UNFRAME 16
SPEC_END get_proposer_reward

/*
 * rbx state, rbp attestations then the cursor over unslashed, r12 scratch then its end,
 * r13 rewards, r14 penalties, r15 n then the end of eligible, S7 unslashed, S8 eligible.
 * Locals: L total balance (then in increments), L+8 its square root, L+16 attesting balance
 * (then in increments), L+24 in leak, L+32 scratch size.
 * Scratch: list 0 unslashed, list 1 eligible, then get_unslashed_attesting_indices's S(5).
 */
SPEC_FUNCTION get_attestation_component_deltas
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    NEED_SCRATCH %r12, %rbx, 7, 9f
    mov     (BeaconState_validators + 8)(%rbx), %r15
    mov     (%r12), %rax
    mov     %rax, (L + 32)(%rsp)
    mov     %r13, %rdi
    mov     %r15, %rsi
    call    lantern_zero_deltas
    mov     %r14, %rdi
    mov     %r15, %rsi
    call    lantern_zero_deltas
    mov     (L + 32)(%rsp), %rcx
    SCRATCH_LIST %rax, %r12, %rcx, 0, %r15
    mov     %rax, S7(%rsp)
    SCRATCH_LIST %rax, %r12, %rcx, 1, %r15
    mov     %rax, S8(%rsp)
    SCRATCH_GIVE %r12, %rcx, 2, %r15
    mov     %rbx, %rdi                      # total_balance = get_total_active_balance(state)
    mov     %r12, %rsi
    lea     L(%rsp), %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     7f
    lea     L(%rsp), %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_integer_squareroot
    mov     (L + 32)(%rsp), %rcx
    SCRATCH_GIVE %r12, %rcx, 2, %r15
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     S7(%rsp), %rcx
    call    lantern_get_unslashed_attesting_indices
    test    %rax, %rax
    jnz     7f
    mov     %rbx, %rdi                      # attesting_balance = get_total_balance(state, unslashed_attesting_indices)
    mov     S7(%rsp), %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_get_total_balance
    mov     %rbx, %rdi
    mov     S8(%rsp), %rsi
    call    lantern_get_eligible_validator_indices
    test    %rax, %rax
    jnz     7f
    mov     %rbx, %rdi
    lea     (L + 24)(%rsp), %rsi
    call    lantern_is_in_inactivity_leak
    MOVQ    %rcx, EFFECTIVE_BALANCE_INCREMENT
    mov     L(%rsp), %rax
    xor     %edx, %edx
    div     %rcx
    mov     %rax, L(%rsp)                   # total_balance // increment
    mov     (L + 16)(%rsp), %rax
    xor     %edx, %edx
    div     %rcx
    mov     %rax, (L + 16)(%rsp)            # attesting_balance // increment
    mov     S7(%rsp), %rbp
    mov     LIST_COUNT(%rbp), %rcx
    add     $LIST_FIXED, %rbp
    lea     (%rbp,%rcx,8), %r12
    mov     S8(%rsp), %rsi                  # for index in get_eligible_validator_indices(state)
    mov     LIST_COUNT(%rsi), %rcx
    add     $LIST_FIXED, %rsi
    lea     (%rsi,%rcx,8), %r15
    PART    %r8, %rcx, %rbx, BeaconState_validators
    mov     (L + 8)(%rsp), %r9
1:  cmp     %r15, %rsi
    jae     5f
    mov     (%rsi), %rdi
    add     $8, %rsi
    mov     %rdi, %rax
    shl     $7, %rax
    mov     Validator_effective_balance(%r8,%rax), %rcx
    BASE_REWARD %rcx, %r9
    mov     %rax, %rcx                      # base_reward
    IN_SORTED %rdi, %rbp, %r12, %rdx
    test    %rdx, %rdx
    jz      3f
    mov     %rcx, %rax                      # in leak: the full base reward
    cmpq    $0, (L + 24)(%rsp)
    jne     2f
    mulq    (L + 16)(%rsp)                  # else base_reward * (attesting_balance // increment) // (total_balance // increment)
    test    %rdx, %rdx
    jnz     8f
    divq    L(%rsp)
2:  lea     LIST_FIXED(%r13,%rdi,8), %r10
    add     %rax, (%r10)
    jc      8f
    jmp     1b
3:  lea     LIST_FIXED(%r14,%rdi,8), %r10   # not attesting: penalties[index] += base_reward
    add     %rcx, (%r10)
    jc      8f
    jmp     1b
5:  xor     %eax, %eax
7:  LEAVE 48
8:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 48
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END get_attestation_component_deltas

/*
 * get_source_deltas, get_target_deltas, get_head_deltas: the component deltas of the matching
 * attestations of the previous epoch. rbx state, rbp scratch, r12 rewards, r13 penalties,
 * r14 refs, r15 scratch size without the refs. Locals: L previous epoch.
 * Scratch: the refs at the end, then get_attestation_component_deltas's S(7).
 */
.macro MATCHING_DELTAS matching
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH_B %rbp, %rbx, 7, PENDING_REFS_BYTES, 9f
    TAKE_REFS %r14, %rbp, %r15
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    mov     %r14, %rdx
    call    \matching
    test    %rax, %rax
    jnz     7f
    mov     %r15, (%rbp)
    mov     %rbx, %rdi
    mov     %r14, %rsi
    mov     %rbp, %rdx
    mov     %r12, %rcx
    mov     %r13, %r8
    call    lantern_get_attestation_component_deltas
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
.endm

SPEC_FUNCTION get_source_deltas
    MATCHING_DELTAS lantern_get_matching_source_attestations
SPEC_END get_source_deltas

SPEC_FUNCTION get_target_deltas
    MATCHING_DELTAS lantern_get_matching_target_attestations
SPEC_END get_target_deltas

SPEC_FUNCTION get_head_deltas
    MATCHING_DELTAS lantern_get_matching_head_attestations
SPEC_END get_head_deltas

/*
 * rbx state, rbp scratch, r12 rewards, r13 penalties, r14 refs then the validators,
 * r15 scratch size without the refs then the end of unslashed, S7 unslashed, S8 the earliest
 * inclusion delay of each validator, S9 its proposer, S10 attesting.
 * Locals: L previous epoch, L+8 total active balance, L+16 its square root, L+24 n,
 * L+32 cursor, L+40 end, L+48 the attestation's ref.
 * Scratch: the refs at the end, then list 0 unslashed, 1 delays, 2 proposers, 3 attesting, then S(5).
 */
SPEC_FUNCTION get_inclusion_delay_deltas
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH_B %rbp, %rbx, 9, PENDING_REFS_BYTES, 9f
    mov     (BeaconState_validators + 8)(%rbx), %rax
    mov     %rax, (L + 24)(%rsp)
    mov     %r12, %rdi
    mov     (L + 24)(%rsp), %rsi
    call    lantern_zero_deltas
    mov     %r13, %rdi
    mov     (L + 24)(%rsp), %rsi
    call    lantern_zero_deltas
    TAKE_REFS %r14, %rbp, %r15
    mov     (L + 24)(%rsp), %rcx
    SCRATCH_LIST %rax, %rbp, %r15, 0, %rcx
    mov     %rax, S7(%rsp)
    SCRATCH_LIST %rax, %rbp, %r15, 1, %rcx
    mov     %rax, S8(%rsp)
    SCRATCH_LIST %rax, %rbp, %r15, 2, %rcx
    mov     %rax, S9(%rsp)
    SCRATCH_LIST %rax, %rbp, %r15, 3, %rcx
    mov     %rax, S10(%rsp)
    SCRATCH_GIVE %rbp, %r15, 4, %rcx
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     %rbx, %rdi                      # matching_source_attestations
    lea     L(%rsp), %rsi
    mov     %r14, %rdx
    call    lantern_get_matching_source_attestations
    test    %rax, %rax
    jnz     7f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     7f
    lea     (L + 8)(%rsp), %rdi
    lea     (L + 16)(%rsp), %rsi
    call    lantern_integer_squareroot
    mov     (L + 24)(%rsp), %rcx
    SCRATCH_GIVE %rbp, %r15, 4, %rcx
    mov     %rbx, %rdi
    mov     %r14, %rsi
    mov     %rbp, %rdx
    mov     S7(%rsp), %rcx
    call    lantern_get_unslashed_attesting_indices
    test    %rax, %rax
    jnz     7f
    mov     S8(%rsp), %rdi                  # the earliest attestation of each validator: none yet
    add     $LIST_FIXED, %rdi
    mov     (L + 24)(%rsp), %rcx
0:  test    %rcx, %rcx
    jz      1f
    movq    $-1, (%rdi)
    add     $8, %rdi
    dec     %rcx
    jmp     0b
1:  lea     LIST_FIXED(%r14), %rax
    mov     %rax, (L + 32)(%rsp)
    mov     LIST_COUNT(%r14), %rcx
    lea     (%rax,%rcx,8), %rax
    mov     %rax, (L + 40)(%rsp)
2:  mov     (L + 32)(%rsp), %rax            # in list order, so the first of the smallest delays wins, as min() does
    cmp     (L + 40)(%rsp), %rax
    jae     4f
    mov     (%rax), %rcx
    add     $8, %rax
    mov     %rax, (L + 32)(%rsp)
    mov     %rcx, (L + 48)(%rsp)
    mov     (L + 24)(%rsp), %rdx
    SCRATCH_GIVE %rbp, %r15, 4, %rdx
    mov     %rbx, %rdi
    lea     (%rbx,%rcx), %rsi
    mov     %rbp, %rcx
    mov     S10(%rsp), %r8
    xor     %rdx, %rdx
    call    lantern_get_attesting_indices
    test    %rax, %rax
    jnz     7f
    mov     (L + 48)(%rsp), %rax
    mov     PendingAttestation_inclusion_delay(%rbx,%rax), %r8
    mov     PendingAttestation_proposer_index(%rbx,%rax), %r9
    mov     S10(%rsp), %rsi
    mov     LIST_COUNT(%rsi), %rcx
    add     $LIST_FIXED, %rsi
    mov     S8(%rsp), %rdi
    add     $LIST_FIXED, %rdi
    mov     S9(%rsp), %rdx
    add     $LIST_FIXED, %rdx
3:  test    %rcx, %rcx
    jz      2b
    mov     (%rsi), %rax
    add     $8, %rsi
    cmp     (%rdi,%rax,8), %r8
    jae     31f
    mov     %r8, (%rdi,%rax,8)
    mov     %r9, (%rdx,%rax,8)
31: dec     %rcx
    jmp     3b
4:  mov     S7(%rsp), %rsi                  # for index in get_unslashed_attesting_indices(state, matching_source_attestations)
    mov     LIST_COUNT(%rsi), %rcx
    add     $LIST_FIXED, %rsi
    lea     (%rsi,%rcx,8), %r15
    PART    %r14, %rax, %rbx, BeaconState_validators
    mov     S8(%rsp), %rbp
    add     $LIST_FIXED, %rbp
    mov     S9(%rsp), %r8
    add     $LIST_FIXED, %r8
    mov     (L + 16)(%rsp), %r9
5:  cmp     %r15, %rsi
    jae     6f
    mov     (%rsi), %rdi
    add     $8, %rsi
    mov     %rdi, %rax
    shl     $7, %rax
    mov     Validator_effective_balance(%r14,%rax), %rax
    BASE_REWARD %rax, %r9
    mov     %rax, %rcx                      # base_reward
    mov     $PROPOSER_REWARD_QUOTIENT, %r10d
    xor     %edx, %edx
    div     %r10                            # get_proposer_reward(state, index)
    mov     (%r8,%rdi,8), %rdx              # rewards[attestation.proposer_index] += proposer_reward
    add     %rax, LIST_FIXED(%r12,%rdx,8)
    jc      8f
    sub     %rax, %rcx                      # max_attester_reward // attestation.inclusion_delay
    mov     (%rbp,%rdi,8), %r10
    test    %r10, %r10
    jz      8f
    mov     %rcx, %rax
    xor     %edx, %edx
    div     %r10
    add     %rax, LIST_FIXED(%r12,%rdi,8)
    jc      8f
    jmp     5b
6:  xor     %eax, %eax
7:  LEAVE 64
8:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 64
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
SPEC_END get_inclusion_delay_deltas

/*
 * Phase0's version. rbx state, rbp scratch then the end of eligible, r12 rewards, r13 penalties,
 * r14 refs then the cursor over unslashed, r15 scratch size without the refs then its end,
 * S7 unslashed, S8 eligible, S9 n.
 * Locals: L previous epoch, L+8 total active balance, L+16 its square root, L+24 finality delay,
 * L+32 in leak.
 * Scratch: the refs at the end, then list 0 unslashed, 1 eligible, then S(5).
 */
SPEC_FUNCTION get_inactivity_penalty_deltas
    ENTER 48
    mov     %rdi, %rbx
    mov     %rdx, %rbp
    mov     %rcx, %r12
    mov     %r8, %r13
    NEED_SCRATCH_B %rbp, %rbx, 7, PENDING_REFS_BYTES, 9f
    mov     (BeaconState_validators + 8)(%rbx), %rax
    mov     %rax, S9(%rsp)
    mov     %r12, %rdi
    mov     S9(%rsp), %rsi
    call    lantern_zero_deltas
    mov     %r13, %rdi
    mov     S9(%rsp), %rsi
    call    lantern_zero_deltas
    mov     %rbx, %rdi
    lea     (L + 32)(%rsp), %rsi
    call    lantern_is_in_inactivity_leak
    cmpq    $0, (L + 32)(%rsp)
    je      6f
    TAKE_REFS %r14, %rbp, %r15
    mov     S9(%rsp), %rcx
    SCRATCH_LIST %rax, %rbp, %r15, 0, %rcx
    mov     %rax, S7(%rsp)
    SCRATCH_LIST %rax, %rbp, %r15, 1, %rcx
    mov     %rax, S8(%rsp)
    SCRATCH_GIVE %rbp, %r15, 2, %rcx
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     %rbx, %rdi                      # matching_target_attestations
    lea     L(%rsp), %rsi
    mov     %r14, %rdx
    call    lantern_get_matching_target_attestations
    test    %rax, %rax
    jnz     7f
    mov     %rbx, %rdi
    mov     %r14, %rsi
    mov     %rbp, %rdx
    mov     S7(%rsp), %rcx
    call    lantern_get_unslashed_attesting_indices
    test    %rax, %rax
    jnz     7f
    mov     S9(%rsp), %rcx
    SCRATCH_GIVE %rbp, %r15, 2, %rcx
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     7f
    lea     (L + 8)(%rsp), %rdi
    lea     (L + 16)(%rsp), %rsi
    call    lantern_integer_squareroot
    mov     %rbx, %rdi
    mov     S8(%rsp), %rsi
    call    lantern_get_eligible_validator_indices
    test    %rax, %rax
    jnz     7f
    mov     %rbx, %rdi
    lea     (L + 24)(%rsp), %rsi
    call    lantern_get_finality_delay
    mov     S7(%rsp), %r14                  # the cursor over matching_target_attesting_indices
    mov     LIST_COUNT(%r14), %rcx
    add     $LIST_FIXED, %r14
    lea     (%r14,%rcx,8), %r15
    mov     S8(%rsp), %rsi                  # for index in get_eligible_validator_indices(state)
    mov     LIST_COUNT(%rsi), %rcx
    add     $LIST_FIXED, %rsi
    lea     (%rsi,%rcx,8), %rbp
    PART    %r8, %rax, %rbx, BeaconState_validators
    mov     (L + 16)(%rsp), %r9
1:  cmp     %rbp, %rsi
    jae     6f
    mov     (%rsi), %rdi
    add     $8, %rsi
    mov     %rdi, %rax
    shl     $7, %rax
    mov     Validator_effective_balance(%r8,%rax), %rcx
    BASE_REWARD %rcx, %r9
    lea     (,%rax,4), %r10                 # BASE_REWARDS_PER_EPOCH * base_reward - get_proposer_reward(state, index)
    mov     $PROPOSER_REWARD_QUOTIENT, %r11d
    xor     %edx, %edx
    div     %r11
    sub     %rax, %r10
    add     %r10, LIST_FIXED(%r13,%rdi,8)
    jc      8f
    IN_SORTED %rdi, %r14, %r15, %rdx
    test    %rdx, %rdx
    jnz     1b
    mov     %rcx, %rax                      # not a target attester: effective_balance * finality_delay // INACTIVITY_PENALTY_QUOTIENT
    mulq    (L + 24)(%rsp)
    test    %rdx, %rdx
    jnz     8f
    MOVQ    %r10, FORK_INACTIVITY_PENALTY_QUOTIENT
    div     %r10
    add     %rax, LIST_FIXED(%r13,%rdi,8)
    jc      8f
    jmp     1b
6:  xor     %eax, %eax
7:  LEAVE 48
8:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 48
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END get_inactivity_penalty_deltas

/* L0: add the n entries (rdx) of list rsi to those of list rdi. rax = LANTERN_OK, or LANTERN_INVALID_OVERFLOW. A leaf. */
LOCAL_FUNCTION lantern_add_deltas
    UNWIND_END_PROLOGUE
    add     $LIST_FIXED, %rdi
    add     $LIST_FIXED, %rsi
1:  test    %rdx, %rdx
    jz      2f
    mov     (%rsi), %rax
    add     %rax, (%rdi)
    jc      3f
    add     $8, %rsi
    add     $8, %rdi
    dec     %rdx
    jmp     1b
2:  xor     %eax, %eax
    ret
3:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
END_FUNCTION lantern_add_deltas

/* Add the component's rewards and penalties to the totals. */
.macro ADD_BOTH
    mov     %r12, %rdi
    mov     S7(%rsp), %rsi
    mov     %r15, %rdx
    call    lantern_add_deltas
    test    %rax, %rax
    jnz     7f
    mov     %r13, %rdi
    mov     S8(%rsp), %rsi
    mov     %r15, %rdx
    call    lantern_add_deltas
    test    %rax, %rax
    jnz     7f
.endm

/* One component: rax = fn(state, scratch, component rewards, component penalties). */
.macro COMPONENT fn
    mov     %r14, (%rbp)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     S7(%rsp), %rdx
    mov     S8(%rsp), %rcx
    call    \fn
    test    %rax, %rax
    jnz     7f
.endm

/*
 * rbx state, rbp scratch, r12 rewards, r13 penalties, r14 the scratch size the components get,
 * r15 n, S7 component rewards, S8 component penalties, S9 config.
 * Scratch: list 0 component rewards, list 1 component penalties, then the components' S(9) + refs.
 */
SPEC_FUNCTION get_attestation_deltas
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, S9(%rsp)
    mov     %rdx, %rbp
    mov     %rcx, %r12
    mov     %r8, %r13
    NEED_SCRATCH_B %rbp, %rbx, 11, PENDING_REFS_BYTES, 9f
    mov     (BeaconState_validators + 8)(%rbx), %r15
    mov     %r12, %rdi
    mov     %r15, %rsi
    call    lantern_zero_deltas
    mov     %r13, %rdi
    mov     %r15, %rsi
    call    lantern_zero_deltas
    mov     (%rbp), %r14
    SCRATCH_LIST %rax, %rbp, %r14, 0, %r15
    mov     %rax, S7(%rsp)
    SCRATCH_LIST %rax, %rbp, %r14, 1, %r15
    mov     %rax, S8(%rsp)
    SCRATCH_GIVE %rbp, %r14, 2, %r15
    mov     (%rbp), %r14
    COMPONENT lantern_get_source_deltas
    ADD_BOTH
    COMPONENT lantern_get_target_deltas
    ADD_BOTH
    COMPONENT lantern_get_head_deltas
    ADD_BOTH
    COMPONENT lantern_get_inclusion_delay_deltas
    mov     %r12, %rdi                      # inclusion delay: rewards only
    mov     S7(%rsp), %rsi
    mov     %r15, %rdx
    call    lantern_add_deltas
    test    %rax, %rax
    jnz     7f
    mov     %r14, (%rbp)                    # inactivity: penalties only
    mov     %rbx, %rdi
    mov     S9(%rsp), %rsi
    mov     %rbp, %rdx
    mov     S7(%rsp), %rcx
    mov     S8(%rsp), %r8
    call    lantern_get_inactivity_penalty_deltas
    test    %rax, %rax
    jnz     7f
    mov     %r13, %rdi
    mov     S8(%rsp), %rsi
    mov     %r15, %rdx
    call    lantern_add_deltas
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END get_attestation_deltas

/*
 * rbx state, rbp config, r12 scratch, r13 result, r14 rewards, r15 penalties, S7 n, S8 index.
 * Locals: L epoch, L+8 index.
 * Scratch: list 0 rewards, list 1 penalties, then get_attestation_deltas's S(11) + refs.
 */
SPEC_FUNCTION process_rewards_and_penalties
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH_B %r12, %rbx, 13, PENDING_REFS_BYTES, 9f
    movq    $0, (%r13)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    cmpq    $GENESIS_EPOCH, L(%rsp)
    je      6f
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     %rcx, S7(%rsp)
    mov     (%r12), %rax
    SCRATCH_LIST %r14, %r12, %rax, 0, %rcx
    SCRATCH_LIST %r15, %r12, %rax, 1, %rcx
    SCRATCH_GIVE %r12, %rax, 2, %rcx
    mov     %rbx, %rdi                      # rewards, penalties = get_attestation_deltas(state)
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r14, %rcx
    mov     %r15, %r8
    call    lantern_get_attestation_deltas
    CHECK_STATUS %r13, 7f, 6f
    movq    $0, S8(%rsp)
1:  mov     S8(%rsp), %rax
    cmp     S7(%rsp), %rax
    jae     6f
    mov     %rax, (L + 8)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    lea     LIST_FIXED(%r14,%rax,8), %rdx
    call    lantern_increase_balance
    mov     (L + 8)(%rsp), %rax
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    lea     LIST_FIXED(%r15,%rax,8), %rdx
    call    lantern_decrease_balance
    incq    S8(%rsp)
    jmp     1b
6:  xor     %eax, %eax
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END process_rewards_and_penalties

/* ---------------------------------------------------------------- Justification and finalization */

/*
 * rbx state, rbp config, r12 scratch, r13 result, r14 refs, r15 scratch size without the refs.
 * Locals: L current epoch, L+8 previous epoch, L+16 total active balance, L+24 previous target
 * balance, L+32 current target balance.
 * Scratch: the refs at the end, then get_attesting_balance's S(6).
 */
SPEC_FUNCTION process_justification_and_finalization
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH_B %r12, %rbx, 6, PENDING_REFS_BYTES, 9f
    movq    $0, (%r13)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    cmpq    $(GENESIS_EPOCH + 1), L(%rsp)
    jbe     6f
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_previous_epoch
    TAKE_REFS %r14, %r12, %r15
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_get_total_active_balance
    test    %rax, %rax
    jnz     7f
    mov     %rbx, %rdi                      # previous_attestations = get_matching_target_attestations(state, previous_epoch)
    lea     (L + 8)(%rsp), %rsi
    mov     %r14, %rdx
    call    lantern_get_matching_target_attestations
    CHECK_STATUS %r13, 7f, 6f
    mov     %r15, (%r12)
    mov     %rbx, %rdi
    mov     %r14, %rsi
    mov     %r12, %rdx
    lea     (L + 24)(%rsp), %rcx
    call    lantern_get_attesting_balance
    CHECK_STATUS %r13, 7f, 6f
    mov     %rbx, %rdi                      # current_attestations
    lea     L(%rsp), %rsi
    mov     %r14, %rdx
    call    lantern_get_matching_target_attestations
    CHECK_STATUS %r13, 7f, 6f
    mov     %r15, (%r12)
    mov     %rbx, %rdi
    mov     %r14, %rsi
    mov     %r12, %rdx
    lea     (L + 32)(%rsp), %rcx
    call    lantern_get_attesting_balance
    CHECK_STATUS %r13, 7f, 6f
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    lea     (L + 24)(%rsp), %rdx
    lea     (L + 32)(%rsp), %rcx
    mov     %r13, %r8
    call    lantern_weigh_justification_and_finalization
7:  LEAVE 48
6:  xor     %eax, %eax
    LEAVE 48
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END process_justification_and_finalization

/* ---------------------------------------------------------------- Record updates */

/*
 * L0: rax = LANTERN_OK when state rdi's previous_epoch_attestations can take the current ones,
 * else LANTERN_BUFFER_TOO_SMALL. A leaf. Uses rcx, rdx, rsi, r8.
 */
LOCAL_FUNCTION lantern_record_room
    UNWIND_END_PROLOGUE
    mov     BeaconState_current_epoch_attestations(%rdi), %rcx
    mov     (BeaconState_current_epoch_attestations + 8)(%rdi), %rdx
    lea     (%rdi,%rcx), %rsi
    xor     %eax, %eax
1:  test    %rdx, %rdx
    jz      2f
    mov     (%rsi,%rax), %r8
    add     %r8, %rax
    dec     %rdx
    jmp     1b
2:  sub     BeaconState_previous_epoch_attestations(%rdi), %rcx
    cmp     %rcx, %rax
    ja      9f
    xor     %eax, %eax
    ret
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    ret
END_FUNCTION lantern_record_room

/* rbx state, rbp result. */
SPEC_FUNCTION process_participation_record_updates
    ENTER 0
    mov     %rdi, %rbx
    mov     %rcx, %rbp
    call    lantern_record_room                     # previous_epoch_attestations = current_epoch_attestations
    test    %rax, %rax
    jnz     7f
    mov     BeaconState_current_epoch_attestations(%rbx), %rcx
    mov     (BeaconState_current_epoch_attestations + 8)(%rbx), %rdx
    lea     (%rbx,%rcx), %rsi
    xor     %eax, %eax
1:  test    %rdx, %rdx
    jz      2f
    add     (%rsi,%rax), %rax
    dec     %rdx
    jmp     1b
2:  mov     BeaconState_previous_epoch_attestations(%rbx), %rdi
    add     %rbx, %rdi
    mov     %rax, %rdx
    call    lantern_copy                    # the previous list starts before the current one
    mov     (BeaconState_current_epoch_attestations + 8)(%rbx), %rax
    mov     %rax, (BeaconState_previous_epoch_attestations + 8)(%rbx)
    movq    $0, (BeaconState_current_epoch_attestations + 8)(%rbx)  # current_epoch_attestations = []
    movq    $0, (%rbp)
    xor     %eax, %eax
7:  LEAVE 0
SPEC_END process_participation_record_updates
