/*
 * Sync committee selection, x86-64. Requirements: docs/reference/epoch-processing.md.
 */

.set SYNC_INDICES_BYTES, LIST_FIXED + 8 * SYNC_COMMITTEE_SIZE           /* an IndexList of the members */
.set SYNC_KEYS_BYTES, 24 + 48 * SYNC_COMMITTEE_SIZE                     /* a BlsPublicKeyList of the members */
.set SYNC_COMMITTEE_SCRATCH, SYNC_INDICES_BYTES + SYNC_KEYS_BYTES

/*
 * rbx state, rbp scratch, r12 out, r13 active list, r14 i, r15 members so far,
 * S7 validator count, S8 scratch size, S9 candidate.
 * Locals: L epoch, L+8 domain type, L+16 seed, L+48 message (seed, i // 16 from electra, i // 32 before), L+88 digest,
 * L+120 the entries of the permutation, L+136 active count.
 */
SPEC_FUNCTION get_next_sync_committee_indices
    ENTER 144
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    cmpq    $SYNC_INDICES_BYTES, LIST_SIZE(%r12)
    jb      9f
    NEED_SCRATCH %rbp, %rbx, 2, 9f
    mov     (BeaconState_validators + 8)(%rbx), %rax
    mov     %rax, S7(%rsp)
    mov     (%rbp), %rax
    mov     %rax, S8(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    incq    L(%rsp)                         # epoch = get_current_epoch(state) + 1
    mov     S7(%rsp), %rcx
    mov     S8(%rsp), %rdx
    SCRATCH_LIST %r13, %rbp, %rdx, 0, %rcx
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    mov     %r13, %rdx
    call    lantern_get_active_validator_indices
    test    %rax, %rax
    jnz     7f
    mov     LIST_COUNT(%r13), %rax
    test    %rax, %rax                      # i % active_validator_count divides by 0
    jz      8f
    mov     %rax, (L + 136)(%rsp)
    movl    $DOMAIN_SYNC_COMMITTEE, (L + 8)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_get_seed
    test    %rax, %rax
    jnz     7f
    lea     (L + 48)(%rsp), %rax
    lea     (L + 16)(%rsp), %rcx
    COPY32  %rax, %rcx
    mov     S7(%rsp), %rcx
    mov     S8(%rsp), %rdx
    SCRATCH_LIST %r14, %rbp, %rdx, 1, %rcx
    lea     LIST_FIXED(%r14), %rax
    mov     %rax, (L + 120)(%rsp)
    SCRATCH_GIVE %rbp, S8(%rsp), 2, %rcx
    lea     (L + 136)(%rsp), %rdi           # every compute_shuffled_index: one permutation of the active count
    lea     (L + 16)(%rsp), %rsi
    mov     %rbp, %rdx
    mov     %r14, %rcx
    call    lantern_compute_shuffled_permutation
    test    %rax, %rax
    jnz     7f
    movq    $LIST_FIXED, LIST_OFFSET(%r12)
    xor     %r15d, %r15d
    xor     %r14d, %r14d
1:  cmp     $SYNC_COMMITTEE_SIZE, %r15
    jae     3f
    mov     %r14, %rax
    xor     %edx, %edx
    divq    (L + 136)(%rsp)
    mov     (L + 120)(%rsp), %rax           # compute_shuffled_index(i % active_validator_count, ...)
    mov     (%rax,%rdx,8), %rax
    mov     LIST_FIXED(%r13,%rax,8), %rax   # candidate_index
    mov     %rax, S9(%rsp)
    mov     %r14, %rax
.if FORK >= FORK_ELECTRA
    shr     $4, %rax
.else
    shr     $5, %rax
.endif
    mov     %rax, (L + 80)(%rsp)
    lea     (L + 48)(%rsp), %rdi            # random_bytes = sha256(seed + uint_to_bytes(i // 16))
    mov     $40, %esi
    lea     (L + 88)(%rsp), %rdx
    call    sha256_short
    mov     %r14, %rax
.if FORK >= FORK_ELECTRA
    and     $15, %eax
    movzwl  (L + 88)(%rsp,%rax,2), %ecx     # random_value
.else
    and     $31, %eax
    movzbl  (L + 88)(%rsp,%rax), %ecx       # random_byte = sha256(seed + uint_to_bytes(i // 32))[i % 32]
.endif
    mov     S9(%rsp), %rax
    mov     BeaconState_validators(%rbx), %rdx
    add     %rbx, %rdx
    shl     $7, %rax
    mov     Validator_effective_balance(%rdx,%rax), %rax
.if FORK >= FORK_ELECTRA
    mov     $0xffff, %edx                   # MAX_RANDOM_VALUE
.else
    mov     $0xff, %edx                     # MAX_RANDOM_BYTE
.endif
    mul     %rdx
    test    %rdx, %rdx
    jnz     6f
.if FORK >= FORK_ELECTRA
    MOVQ    %rdx, MAX_EFFECTIVE_BALANCE_ELECTRA
.else
    MOVQ    %rdx, MAX_EFFECTIVE_BALANCE
.endif
    imul    %rcx, %rdx
    cmp     %rdx, %rax
    jb      2f
    mov     S9(%rsp), %rax
    mov     %rax, LIST_FIXED(%r12,%r15,8)
    inc     %r15
2:  inc     %r14
    jmp     1b
3:  mov     %r15, LIST_COUNT(%r12)
    xor     %eax, %eax
7:  LEAVE 144
6:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 144
8:  mov     $LANTERN_INVALID_NO_INDICES, %eax
    LEAVE 144
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 144
SPEC_END get_next_sync_committee_indices

/* rbx state, rbp scratch, r12 out, r13 scratch size, r14 indices, r15 keys. */
SPEC_FUNCTION get_next_sync_committee
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    NEED_SCRATCH_B %rbp, %rbx, 2, SYNC_COMMITTEE_SCRATCH, 9f
    mov     (%rbp), %r13
    mov     %r13, %rax
    sub     $SYNC_INDICES_BYTES, %rax
    lea     (%rbp,%rax), %r14
    movq    $SYNC_INDICES_BYTES, (%r14)
    mov     %r13, %rax
    sub     $SYNC_COMMITTEE_SCRATCH, %rax
    lea     (%rbp,%rax), %r15
    mov     %rax, (%rbp)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r14, %rdx
    call    lantern_get_next_sync_committee_indices
    test    %rax, %rax
    jnz     7f
    movq    $SYNC_KEYS_BYTES, (%r15)        # pubkeys = [state.validators[index].pubkey for index in indices]
    movq    $24, 8(%r15)
    movq    $SYNC_COMMITTEE_SIZE, 16(%r15)
    lea     LIST_FIXED(%r14), %rsi
    lea     24(%r15), %rdi
    lea     SyncCommittee_pubkeys(%r12), %r8
    mov     BeaconState_validators(%rbx), %r9
    add     %rbx, %r9
    xor     %ecx, %ecx
1:  cmp     $SYNC_COMMITTEE_SIZE, %rcx
    jae     2f
    mov     (%rsi,%rcx,8), %rax
    shl     $7, %rax
    add     %r9, %rax
    movdqu  Validator_pubkey(%rax), %xmm0
    movdqu  (Validator_pubkey + 16)(%rax), %xmm1
    movdqu  (Validator_pubkey + 32)(%rax), %xmm2
    movdqu  %xmm0, (%rdi)
    movdqu  %xmm1, 16(%rdi)
    movdqu  %xmm2, 32(%rdi)
    movdqu  %xmm0, (%r8)
    movdqu  %xmm1, 16(%r8)
    movdqu  %xmm2, 32(%r8)
    add     $48, %rdi
    add     $48, %r8
    inc     %rcx
    jmp     1b
2:  mov     %r15, %rdi                      # aggregate_pubkey = eth_aggregate_pubkeys(pubkeys)
    lea     SyncCommittee_aggregate_pubkey(%r12), %rsi
    CALL_GLOBAL crypto_bls_eth_aggregate_pubkeys
    test    %rax, %rax
    jz      7f
    mov     $LANTERN_INVALID_AGGREGATE_PUBKEYS, %eax
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END get_next_sync_committee

/* rbx state, rbp config, r12 scratch, r13 result, r14 scratch size, r15 new committee. Locals: L epoch. */
SPEC_FUNCTION process_sync_committee_updates
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    movq    $0, (%r13)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     L(%rsp), %rax
    inc     %rax
    test    $(EPOCHS_PER_SYNC_COMMITTEE_PERIOD - 1), %rax
    jnz     8f
    NEED_SCRATCH_B %r12, %rbx, 2, SYNC_COMMITTEE_SCRATCH + SyncCommittee__mem, 9f
    mov     (%r12), %r14
    mov     %r14, %rax
    sub     $SyncCommittee__mem, %rax
    lea     (%r12,%rax), %r15
    mov     %rax, (%r12)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %r15, %rdx
    call    lantern_get_next_sync_committee
    CHECK_STATUS %r13, 7f, 8f
    lea     BeaconState_current_sync_committee(%rbx), %rdi  # current = next; next = the new committee
    lea     BeaconState_next_sync_committee(%rbx), %rsi
    mov     $SyncCommittee__mem, %edx
    call    lantern_copy
    lea     BeaconState_next_sync_committee(%rbx), %rdi
    mov     %r15, %rsi
    mov     $SyncCommittee__mem, %edx
    call    lantern_copy
8:  xor     %eax, %eax
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END process_sync_committee_updates

.if EPOCHS_PER_SYNC_COMMITTEE_PERIOD & (EPOCHS_PER_SYNC_COMMITTEE_PERIOD - 1)
.error "EPOCHS_PER_SYNC_COMMITTEE_PERIOD is not a power of two"
.endif
