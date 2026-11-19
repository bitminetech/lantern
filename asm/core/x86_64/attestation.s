/*
 * Committees and attestations, x86-64. Requirements: docs/reference/block-processing.md.
 */

.set CIDX_BYTES, LIST_FIXED + 8 * MAX_COMMITTEES_PER_SLOT     /* an IndexList of committee indices */
.set FLAGS_BYTES, LIST_FIXED + 8 * 3                            /* an IndexList of participation flags */
.set ATTEST_EXTRA, 2 * CIDX_BYTES + IndexedAttestation__fixed + 8

/* ---------------------------------------------------------------- Sorting */

/* Sift the entry at root down the heap of entries below end, at rdi. Uses rax, rcx, rdx, r8. */
.macro SIFT root, end
97: lea     1(\root,\root), %rax            # child = 2 * root + 1
    cmp     \end, %rax
    jae     98f
    mov     (%rdi,%rax,8), %rcx
    lea     1(%rax), %rdx
    cmp     \end, %rdx
    jae     96f
    mov     (%rdi,%rdx,8), %r8
    cmp     %rcx, %r8                       # the larger child
    jbe     96f
    mov     %rdx, %rax
    mov     %r8, %rcx
96: mov     (%rdi,\root,8), %r8
    cmp     %rcx, %r8
    jae     98f
    mov     %rcx, (%rdi,\root,8)
    mov     %r8, (%rdi,%rax,8)
    mov     %rax, \root
    jmp     97b
98:
.endm

/* L0: sort the rsi u64 entries at rdi, ascending (heapsort). A leaf; uses rax, rcx, rdx, r8-r11. */
LOCAL_FUNCTION sort_u64
    UNWIND_END_PROLOGUE
    cmp     $2, %rsi
    jb      9f
    mov     %rsi, %r9
    shr     $1, %r9
1:  test    %r9, %r9
    jz      2f
    dec     %r9
    mov     %r9, %r10
    SIFT    %r10, %rsi
    jmp     1b
2:  mov     %rsi, %r11
3:  dec     %r11
    jz      9f
    mov     (%rdi), %rax
    mov     (%rdi,%r11,8), %rcx
    mov     %rcx, (%rdi)
    mov     %rax, (%rdi,%r11,8)
    xor     %r10d, %r10d
    SIFT    %r10, %r11
    jmp     3b
9:  ret
END_FUNCTION sort_u64

/* ---------------------------------------------------------------- Committees */

.if FORK >= FORK_ELECTRA
SPEC_LEAF get_committee_indices
    movq    $LIST_FIXED, LIST_OFFSET(%rsi)
    lea     LIST_FIXED(%rsi), %rdx
    xor     %ecx, %ecx                      # bit
1:  cmp     $MAX_COMMITTEES_PER_SLOT, %rcx
    jae     2f
    bt      %rcx, (%rdi)
    jnc     3f
    mov     %rcx, (%rdx)
    add     $8, %rdx
3:  inc     %rcx
    jmp     1b
2:  lea     LIST_FIXED(%rsi), %rax
    sub     %rax, %rdx
    shr     $3, %rdx
    mov     %rdx, LIST_COUNT(%rsi)
    RETURN_OK
SPEC_END get_committee_indices
.endif

/*
 * L0: the key of epoch rsi of state rdi at rdx (CommitteeEntry_seed onward): get_seed with
 * DOMAIN_BEACON_ATTESTER, the decision root, the genesis validators root. rbx state, rbp epoch,
 * r12 key. Locals: L epoch, L+8 domain type.
 */
LOCAL_FUNCTION committee_key
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rbp, L(%rsp)
    movl    $DOMAIN_BEACON_ATTESTER, (L + 8)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    mov     %r12, %rcx
    call    lantern_get_seed
    test    %rax, %rax
    jnz     7f
    pxor    %xmm0, %xmm0                    # the decision root: the last slot of epoch E - 5
    movdqu  %xmm0, 32(%r12)
    movdqu  %xmm0, 48(%r12)
    xor     %eax, %eax
    cmp     $5, %rbp
    jb      1f
    lea     -4(%rbp), %rax
    shl     $LOG2_SLOTS_PER_EPOCH, %rax
    dec     %rax
1:  mov     BeaconState_slot(%rbx), %rcx    # get_block_root_at_slot: before the state's slot, in range
    cmp     %rcx, %rax
    jae     2f
    lea     SLOTS_PER_HISTORICAL_ROOT(%rax), %rdx
    cmp     %rdx, %rcx
    ja      2f
    and     $(SLOTS_PER_HISTORICAL_ROOT - 1), %eax
    shl     $5, %rax
    lea     BeaconState_block_roots(%rbx,%rax), %rsi
    lea     32(%r12), %rdi
    COPY32  %rdi, %rsi
2:  lea     BeaconState_genesis_validators_root(%rbx), %rsi
    lea     64(%r12), %rdi
    COPY32  %rdi, %rsi
    xor     %eax, %eax
7:  LEAVE 16
END_FUNCTION committee_key

/* L0: rax = the valid entry of cache rdi for epoch rsi and the key at rdx, or 0. A leaf. */
LOCAL_FUNCTION committee_find
    UNWIND_END_PROLOGUE
    mov     CommitteeCache_validators(%rdi), %rcx
    lea     (CommitteeEntry__mem + LIST_FIXED)(,%rcx,8), %rcx
    lea     CommitteeCache_entries(%rdi), %rax
    mov     $COMMITTEE_CACHE_ENTRIES, %r8d
1:  cmpq    $0, CommitteeEntry_valid(%rax)
    je      3f
    cmp     CommitteeEntry_epoch(%rax), %rsi
    jne     3f
    xor     %r9d, %r9d                      # the 96 bytes of the key
2:  mov     CommitteeEntry_seed(%rax,%r9), %r10
    cmp     (%rdx,%r9), %r10
    jne     3f
    add     $8, %r9
    cmp     $96, %r9
    jb      2b
    ret
3:  add     %rcx, %rax
    dec     %r8
    jnz     1b
    xor     %eax, %eax
    ret
END_FUNCTION committee_find

SPEC_FUNCTION committee_cache_size
    FRAME 16
    mov     (%rdi), %rax
    lea     (CommitteeEntry__mem + LIST_FIXED)(,%rax,8), %rax
    imul    $COMMITTEE_CACHE_ENTRIES, %rax, %rax
    add     $COMMITTEE_CACHE_FIXED, %rax
    mov     %rax, (%rsi)
    xor     %eax, %eax
    UNFRAME 16
SPEC_END committee_cache_size

SPEC_FUNCTION committee_cache_init
    FRAME 16
    mov     (%rdi), %rcx
    lea     (CommitteeEntry__mem + LIST_FIXED)(,%rcx,8), %rdx  # an entry and its list
    imul    $COMMITTEE_CACHE_ENTRIES, %rdx, %rax
    add     $COMMITTEE_CACHE_FIXED, %rax
    cmp     %rax, CommitteeCache_size(%rsi)
    jb      9f
    mov     %rcx, CommitteeCache_validators(%rsi)
    movq    $0, CommitteeCache_next(%rsi)
    lea     CommitteeCache_entries(%rsi), %rax
    mov     $COMMITTEE_CACHE_ENTRIES, %ecx
1:  movq    $0, CommitteeEntry_valid(%rax)
    add     %rdx, %rax
    dec     %rcx
    jnz     1b
    xor     %eax, %eax
    UNFRAME 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    UNFRAME 16
SPEC_END committee_cache_init

SPEC_FUNCTION pubkey_cache_size
    FRAME 16
    imul    $CRYPTO_BLS_ENTRY_BYTES, (%rdi), %rax
    add     $CRYPTO_BLS_CACHE_FIXED, %rax
    mov     %rax, (%rsi)
    xor     %eax, %eax
    UNFRAME 16
SPEC_END pubkey_cache_size

# A BlsKeyCache of asm-crypto whose keys are those of a state's validators: key_stride Validator__mem.
SPEC_FUNCTION pubkey_cache_init
    FRAME 16
    mov     (%rdi), %rcx
    imul    $CRYPTO_BLS_ENTRY_BYTES, %rcx, %rax
    add     $CRYPTO_BLS_CACHE_FIXED, %rax
    cmp     %rax, (%rsi)
    jb      9f
    movq    $Validator__mem, CRYPTO_BLS_CACHE_KEY_STRIDE(%rsi)
    movq    $CRYPTO_BLS_CACHE_FIXED, CRYPTO_BLS_CACHE_OFFSET(%rsi)
    mov     %rcx, CRYPTO_BLS_CACHE_COUNT(%rsi)
    lea     CRYPTO_BLS_CACHE_FIXED(%rsi), %rax  # every entry empty
1:  test    %rcx, %rcx
    jz      2f
    movq    $0, CRYPTO_BLS_ENTRY_STATUS(%rax)
    add     $CRYPTO_BLS_ENTRY_BYTES, %rax
    dec     %rcx
    jmp     1b
2:  xor     %eax, %eax
    UNFRAME 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    UNFRAME 16
SPEC_END pubkey_cache_init

/* rbx state, rbp epoch pointer, r12 scratch, r13 out, r14 list, r15 cache. Locals: L the key (96). */
SPEC_FUNCTION get_committee_count_per_slot
    ENTER 96
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r15
    mov     %rcx, %r12
    mov     %r8, %r13
    NEED_SCRATCH %r12, %rbx, 1, 9f
    test    %r15, %r15
    jz      1f
    mov     %rbx, %rdi                      # an entry of the cache: its count
    mov     (%rbp), %rsi
    lea     L(%rsp), %rdx
    call    committee_key
    test    %rax, %rax
    jnz     1f
    mov     %r15, %rdi
    mov     (%rbp), %rsi
    lea     L(%rsp), %rdx
    call    committee_find
    test    %rax, %rax
    jz      1f
    mov     CommitteeEntry_count(%rax), %rax
    jmp     2f
1:  mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     (%r12), %rax
    SCRATCH_LIST %r14, %r12, %rax, 0, %rcx
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r14, %rdx
    call    lantern_get_active_validator_indices
    test    %rax, %rax
    jnz     7f
    mov     LIST_COUNT(%r14), %rax
2:  shr     $LOG2_SLOTS_PER_EPOCH, %rax
    xor     %edx, %edx
    mov     $TARGET_COMMITTEE_SIZE, %ecx
    div     %rcx
    mov     $MAX_COMMITTEES_PER_SLOT, %ecx
    cmp     %rcx, %rax
    cmovae  %rcx, %rax
    mov     $1, %ecx                        # max(1, ...)
    test    %rax, %rax
    cmovz   %rcx, %rax
    mov     %rax, (%r13)
    xor     %eax, %eax
7:  LEAVE 96
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 96
SPEC_END get_committee_count_per_slot

/*
 * rbx indices, rbp seed, r12 i, r13 end, r14 scratch, r15 out entries, S7 scratch size.
 * Locals: L len(indices), L+8 i, L+16 shuffled.
 */
SPEC_FUNCTION compute_committee
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %r8, %r14
    mov     LIST_COUNT(%rbx), %rax          # n
    mov     %rax, L(%rsp)
    mov     (%rdx), %rsi                    # index
    mov     (%rcx), %rcx                    # count
    test    %rcx, %rcx
    jz      8f
    mov     %rax, %r8
    mul     %rsi
    div     %rcx
    mov     %rax, %r12                      # start = len(indices) * index // count
    lea     1(%rsi), %rax
    mul     %r8
    div     %rcx
    mov     %rax, %r13                      # end = len(indices) * (index + 1) // count
    mov     %r13, %rax
    sub     %r12, %rax
    lea     LIST_FIXED(,%rax,8), %rdx
    cmp     %rdx, LIST_SIZE(%r9)
    jb      9f
    movq    $LIST_FIXED, LIST_OFFSET(%r9)
    mov     %rax, LIST_COUNT(%r9)
    lea     LIST_FIXED(%r9), %r15
    mov     (%r14), %rax
    mov     %rax, S7(%rsp)
1:  cmp     %r13, %r12
    jae     2f
    mov     %r12, (L + 8)(%rsp)
    mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    lea     (L + 8)(%rsp), %rdi             # indices[compute_shuffled_index(i, len(indices), seed)]
    lea     L(%rsp), %rsi
    mov     %rbp, %rdx
    mov     %r14, %rcx
    lea     (L + 16)(%rsp), %r8
    call    lantern_compute_shuffled_index
    test    %rax, %rax
    jnz     7f
    mov     (L + 16)(%rsp), %rax
    mov     LIST_FIXED(%rbx,%rax,8), %rax
    mov     %rax, (%r15)
    add     $8, %r15
    inc     %r12
    jmp     1b
2:  xor     %eax, %eax
7:  LEAVE 32
8:  mov     $LANTERN_INVALID_SHUFFLED_INDEX, %eax
    LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
SPEC_END compute_committee

/*
 * rbx state, rbp slot, r12 index pointer, r13 scratch, r14 out, r15 scratch size, S7 n, S8 list,
 * S9 cache, S10 the entry. Locals: L epoch, L+8 committees per slot, L+16 domain type,
 * L+24 seed (32), L+56 index, L+64 count, L+72 the entry's key (96).
 */
SPEC_FUNCTION get_beacon_committee
    ENTER 176
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    mov     %rcx, S9(%rsp)
    mov     %r8, %r13
    mov     %r9, %r14
    NEED_SCRATCH %r13, %rbx, 2, 9f
    mov     (%r13), %r15
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     %rcx, S7(%rsp)
    mov     %rbp, %rax                      # epoch = compute_epoch_at_slot(slot)
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, L(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    mov     S9(%rsp), %rdx
    mov     %r13, %rcx
    lea     (L + 8)(%rsp), %r8
    call    lantern_get_committee_count_per_slot
    test    %rax, %rax
    jnz     7f
    cmpq    $0, S9(%rsp)
    je      20f
    mov     %rbx, %rdi                      # the cache's entry of the epoch
    mov     L(%rsp), %rsi
    lea     (L + 72)(%rsp), %rdx
    call    committee_key
    test    %rax, %rax
    jnz     20f
    mov     S9(%rsp), %rdi
    mov     L(%rsp), %rsi
    lea     (L + 72)(%rsp), %rdx
    call    committee_find
    mov     %rax, S10(%rsp)
    test    %rax, %rax
    jnz     30f
    mov     S7(%rsp), %rcx                  # a new entry: the active validators, shuffled
    SCRATCH_LIST %rax, %r13, %r15, 0, %rcx
    mov     %rax, S8(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    mov     %rax, %rdx
    call    lantern_get_active_validator_indices
    test    %rax, %rax
    jnz     7f
    mov     S8(%rsp), %rax
    mov     LIST_COUNT(%rax), %rcx
    mov     S9(%rsp), %rdi
    mov     CommitteeCache_validators(%rdi), %rdx
    cmp     %rdx, %rcx
    ja      21f
    lea     (CommitteeEntry__mem + LIST_FIXED)(,%rdx,8), %r8
    mov     CommitteeCache_next(%rdi), %rax
    lea     1(%rax), %r9
    imul    %r8, %rax
    lea     CommitteeCache_entries(%rdi,%rax), %rax
    mov     %rax, S10(%rsp)
    xor     %r10d, %r10d
    cmp     $COMMITTEE_CACHE_ENTRIES, %r9
    cmovae  %r10, %r9
    mov     %r9, CommitteeCache_next(%rdi)
    movq    $0, CommitteeEntry_valid(%rax)
    mov     %rcx, CommitteeEntry_count(%rax)
    lea     LIST_FIXED(,%rdx,8), %rdx
    mov     %rdx, (CommitteeEntry__mem + LIST_SIZE)(%rax)
    mov     S7(%rsp), %rcx
    SCRATCH_GIVE %r13, %r15, 1, %rcx
    mov     S10(%rsp), %rax
    lea     CommitteeEntry_count(%rax), %rdi
    lea     (L + 72)(%rsp), %rsi
    mov     %r13, %rdx
    lea     CommitteeEntry__mem(%rax), %rcx
    call    lantern_compute_shuffled_permutation
    test    %rax, %rax
    jnz     7f
    mov     S10(%rsp), %rax                 # entry i = indices[permutation[i]]
    lea     (CommitteeEntry__mem + LIST_FIXED)(%rax), %rdi
    mov     S8(%rsp), %rsi
    add     $LIST_FIXED, %rsi
    mov     CommitteeEntry_count(%rax), %rcx
    xor     %edx, %edx
11: cmp     %rcx, %rdx
    jae     12f
    mov     (%rdi,%rdx,8), %r8
    mov     (%rsi,%r8,8), %r8
    mov     %r8, (%rdi,%rdx,8)
    inc     %rdx
    jmp     11b
12: mov     L(%rsp), %rcx
    mov     %rcx, CommitteeEntry_epoch(%rax)
    lea     CommitteeEntry_seed(%rax), %rdi
    lea     (L + 72)(%rsp), %rsi
    COPY32  %rdi, %rsi
    add     $32, %rdi
    add     $32, %rsi
    COPY32  %rdi, %rsi
    add     $32, %rdi
    add     $32, %rsi
    COPY32  %rdi, %rsi
    movq    $1, CommitteeEntry_valid(%rax)
30: mov     (L + 8)(%rsp), %rcx             # the slice of the entry: index, count, start, end
    mov     %rbp, %rax
    and     $(SLOTS_PER_EPOCH - 1), %eax
    imul    %rcx, %rax
    add     (%r12), %rax
    jc      6f
    mov     %rax, %r8
    shl     $LOG2_SLOTS_PER_EPOCH, %rcx
    mov     %rcx, %r9
    mov     S10(%rsp), %rsi
    mov     CommitteeEntry_count(%rsi), %r10
    mov     %r10, %rax
    mul     %r8
    div     %r9
    mov     %rax, %rdi                      # start
    lea     1(%r8), %rax
    mul     %r10
    div     %r9
    mov     %rax, %rcx
    sub     %rdi, %rcx                      # the members
    jz      31f
    cmp     %r10, %rax                      # past the list: compute_shuffled_index raises
    ja      5f
31: lea     LIST_FIXED(,%rcx,8), %rax
    cmp     %rax, LIST_SIZE(%r14)
    jb      9f
    movq    $LIST_FIXED, LIST_OFFSET(%r14)
    mov     %rcx, LIST_COUNT(%r14)
    lea     (CommitteeEntry__mem + LIST_FIXED)(%rsi,%rdi,8), %rsi
    lea     LIST_FIXED(%r14), %rdi
    rep movsq
    xor     %eax, %eax
    LEAVE 176
20: mov     S7(%rsp), %rcx                  # no cache
    SCRATCH_LIST %rax, %r13, %r15, 0, %rcx
    mov     %rax, S8(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    mov     %rax, %rdx
    call    lantern_get_active_validator_indices
    test    %rax, %rax
    jnz     7f
21: movl    $DOMAIN_BEACON_ATTESTER, (L + 16)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 16)(%rsp), %rdx
    lea     (L + 24)(%rsp), %rcx
    call    lantern_get_seed
    test    %rax, %rax
    jnz     7f
    mov     (L + 8)(%rsp), %rcx             # index = (slot % SLOTS_PER_EPOCH) * committees_per_slot + index
    mov     %rbp, %rax
    and     $(SLOTS_PER_EPOCH - 1), %eax
    imul    %rcx, %rax
    add     (%r12), %rax
    jc      6f
    mov     %rax, (L + 56)(%rsp)
    shl     $LOG2_SLOTS_PER_EPOCH, %rcx     # count = committees_per_slot * SLOTS_PER_EPOCH
    mov     %rcx, (L + 64)(%rsp)
    mov     S7(%rsp), %rcx
    SCRATCH_GIVE %r13, %r15, 1, %rcx
    mov     S8(%rsp), %rdi
    lea     (L + 24)(%rsp), %rsi
    lea     (L + 56)(%rsp), %rdx
    lea     (L + 64)(%rsp), %rcx
    mov     %r13, %r8
    mov     %r14, %r9
    call    lantern_compute_committee
7:  LEAVE 176
5:  mov     $LANTERN_INVALID_SHUFFLED_INDEX, %eax
    LEAVE 176
6:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 176
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 176
SPEC_END get_beacon_committee

.if FORK >= FORK_ELECTRA
/*
 * rbx state, rbp attestation, r12 scratch, r13 out, r14 committee offset, r15 committee index cursor,
 * S7 committee, S8 committee indices.
 * Locals: L committee index, L+8 the scratch size the callee gets, L+16 bits, L+24 bit count, L+32 cursor end.
 */
SPEC_FUNCTION get_attesting_indices
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, (L + 40)(%rsp)            # the committee cache
    mov     %rcx, %r12
    mov     %r8, %r13
    NEED_SCRATCH_B %r12, %rbx, 3, CIDX_BYTES, 9f
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    lea     LIST_FIXED(,%rcx,8), %rax       # out has room for every validator
    cmp     %rax, LIST_SIZE(%r13)
    jb      9f
    mov     (%r12), %rdx
    sub     $CIDX_BYTES, %rdx
    lea     (%r12,%rdx), %rsi               # committee indices: the last CIDX_BYTES
    movq    $CIDX_BYTES, (%rsi)
    mov     %rsi, S8(%rsp)
    sub     %rax, %rdx
    lea     (%r12,%rdx), %rsi               # the committee: the L(n) before
    mov     %rax, (%rsi)
    mov     %rsi, S7(%rsp)
    mov     %rdx, (L + 8)(%rsp)
    lea     Attestation_committee_bits(%rbp), %rdi
    mov     S8(%rsp), %rsi
    call    lantern_get_committee_indices
    PART    %rax, %rcx, %rbp, Attestation_aggregation_bits
    mov     %rax, (L + 16)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
    movq    $LIST_FIXED, LIST_OFFSET(%r13)
    movq    $0, LIST_COUNT(%r13)
    xor     %r14d, %r14d
    mov     S8(%rsp), %rax
    lea     LIST_FIXED(%rax), %r15
    mov     LIST_COUNT(%rax), %rcx
    lea     (%r15,%rcx,8), %rcx
    mov     %rcx, (L + 32)(%rsp)
1:  cmp     (L + 32)(%rsp), %r15
    jae     4f
    mov     (%r15), %rax
    add     $8, %r15
    mov     %rax, L(%rsp)
    mov     (L + 8)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # committee = get_beacon_committee(state, data.slot, committee_index)
    lea     (Attestation_data + AttestationData_slot)(%rbp), %rsi
    lea     L(%rsp), %rdx
    mov     %r12, %r8
    mov     S7(%rsp), %r9
    mov     (L + 40)(%rsp), %rcx
    call    lantern_get_beacon_committee
    test    %rax, %rax
    jnz     7f
    mov     S7(%rsp), %rsi
    mov     LIST_COUNT(%rsi), %rcx          # members left
    add     $LIST_FIXED, %rsi
    mov     (L + 16)(%rsp), %rdi            # bits
    mov     (L + 24)(%rsp), %r8             # bit count
    mov     LIST_COUNT(%r13), %r9
    lea     LIST_FIXED(%r13,%r9,8), %rdx
2:  test    %rcx, %rcx
    jz      3f
    cmp     %r8, %r14                       # aggregation_bits[committee_offset + index]
    jae     8f
    mov     (%rsi), %rax
    add     $8, %rsi
    bt      %r14, (%rdi)
    jnc     25f
    mov     %rax, (%rdx)
    add     $8, %rdx
    inc     %r9
25: inc     %r14
    dec     %rcx
    jmp     2b
3:  mov     %r9, LIST_COUNT(%r13)
    jmp     1b
4:  lea     LIST_FIXED(%r13), %rdi          # a set: ascending
    mov     LIST_COUNT(%r13), %rsi
    call    sort_u64
    xor     %eax, %eax
7:  LEAVE 48
8:  mov     $LANTERN_INVALID_ATTESTATION, %eax
    LEAVE 48
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END get_attesting_indices
.else
/*
 * Before electra: the committee of data.index. A PendingAttestation of phase0 has the same
 * aggregation_bits and data, so the function also takes one.
 * rbx state, rbp attestation, r12 scratch, r13 out, r14 scratch size then i, r15 committee.
 */
.if FORK == FORK_PHASE0
.if (PendingAttestation_aggregation_bits != Attestation_aggregation_bits) || (PendingAttestation_data != Attestation_data)
.error "PendingAttestation does not start with the fields of Attestation"
.endif
.endif
SPEC_FUNCTION get_attesting_indices
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, L(%rsp)                   # the committee cache
    mov     %rcx, %r12
    mov     %r8, %r13
    NEED_SCRATCH %r12, %rbx, 3, 9f
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    lea     LIST_FIXED(,%rcx,8), %rax       # out has room for every validator
    cmp     %rax, LIST_SIZE(%r13)
    jb      9f
    mov     (%r12), %r14
    SCRATCH_LIST %r15, %r12, %r14, 0, %rcx  # the committee: the last list
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    SCRATCH_GIVE %r12, %r14, 1, %rcx
    mov     %rbx, %rdi                      # committee = get_beacon_committee(state, data.slot, data.index)
    lea     (Attestation_data + AttestationData_slot)(%rbp), %rsi
    lea     (Attestation_data + AttestationData_index)(%rbp), %rdx
    mov     %r12, %r8
    mov     %r15, %r9
    mov     L(%rsp), %rcx
    call    lantern_get_beacon_committee
    test    %rax, %rax
    jnz     7f
    PART    %rdi, %r8, %rbp, Attestation_aggregation_bits
    mov     LIST_COUNT(%r15), %rcx
    lea     LIST_FIXED(%r15), %rsi
    movq    $LIST_FIXED, LIST_OFFSET(%r13)
    xor     %r9d, %r9d                      # the count
    lea     LIST_FIXED(%r13), %rdx
    xor     %r14d, %r14d                    # i
2:  cmp     %rcx, %r14
    jae     3f
    cmp     %r8, %r14                       # aggregation_bits[i]
    jae     8f
    mov     (%rsi), %rax
    add     $8, %rsi
    bt      %r14, (%rdi)
    jnc     25f
    mov     %rax, (%rdx)
    add     $8, %rdx
    inc     %r9
25: inc     %r14
    jmp     2b
3:  mov     %r9, LIST_COUNT(%r13)
    lea     LIST_FIXED(%r13), %rdi          # a set: ascending
    mov     %r9, %rsi
    call    sort_u64
    xor     %eax, %eax
7:  LEAVE 16
8:  mov     $LANTERN_INVALID_ATTESTATION, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END get_attesting_indices
.endif

/* rbx state, rbp attestation, r12 scratch, r13 out, r14 scratch size, r15 the attesting list. */
SPEC_FUNCTION get_indexed_attestation
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, L(%rsp)                   # the committee cache
    mov     %rcx, %r12
    mov     %r8, %r13
    NEED_SCRATCH_B %r12, %rbx, 4, CIDX_BYTES, 9f
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    mov     (%r12), %r14
    SCRATCH_LIST %r15, %r12, %r14, 0, %rcx
    SCRATCH_GIVE %r12, %r14, 1, %rcx
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rcx
    mov     %r15, %r8
    mov     L(%rsp), %rdx
    call    lantern_get_attesting_indices
    test    %rax, %rax
    jnz     7f
    mov     LIST_COUNT(%r15), %rcx          # out: attesting_indices, data, signature
    lea     IndexedAttestation__fixed(,%rcx,8), %rax
    cmp     %rax, (%r13)
    jb      9f
    movq    $IndexedAttestation__fixed, IndexedAttestation_attesting_indices(%r13)
    mov     %rcx, (IndexedAttestation_attesting_indices + 8)(%r13)
    lea     IndexedAttestation__fixed(%r13), %rdi
    lea     LIST_FIXED(%r15), %rsi
    lea     (,%rcx,8), %rdx
    call    lantern_copy
    lea     IndexedAttestation_data(%r13), %rdi
    lea     Attestation_data(%rbp), %rsi
    mov     $AttestationData__mem, %edx
    call    lantern_copy
    lea     IndexedAttestation_signature(%r13), %rdi
    lea     Attestation_signature(%rbp), %rsi
    mov     $96, %edx
    call    lantern_copy
    xor     %eax, %eax
7:  LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END get_indexed_attestation

/*
 * rbx state, rbp indexed attestation, r12 scratch, r13 out, r14 indices, r15 count, S7 keys (a
 * BlsPublicKeyList), then the 7th argument of the cached check; S8 cache: 0 when it has no entry
 * of the largest index. Locals: L domain type, L+8 domain (32), L+40 message (24 + 32).
 */
.if IndexedAttestation_attesting_indices != CRYPTO_BLS_LIST_OFFSET
.error "an IndexedAttestation must read as a BlsIndexList of its attesting indices"
.endif
SPEC_FUNCTION is_valid_indexed_attestation
    ENTER 160
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, S8(%rsp)
    mov     %rcx, %r12
    mov     %r8, %r13
    movq    $0, (%r13)
    PART    %r14, %r15, %rbp, IndexedAttestation_attesting_indices
    test    %r15, %r15                      # len(indices) == 0: False
    jz      8f
    mov     $1, %eax                        # indices sorted and unique
1:  cmp     %r15, %rax
    jae     2f
    mov     -8(%r14,%rax,8), %rcx
    cmp     %rcx, (%r14,%rax,8)
    jbe     8f
    inc     %rax
    jmp     1b
2:  mov     -8(%r14,%r15,8), %rax           # the largest index names a validator
    cmp     (BeaconState_validators + 8)(%rbx), %rax
    jae     6f
    mov     S8(%rsp), %rcx                  # with a cache that has an entry of every index: no list of keys
    test    %rcx, %rcx
    jz      31f
    cmp     CRYPTO_BLS_CACHE_COUNT(%rcx), %rax
    jb      4f
    movq    $0, S8(%rsp)
31: imul    $48, %r15, %rax                 # pubkeys: a BlsPublicKeyList at the end of scratch
    add     $(24 + 7), %rax
    and     $-8, %rax
    mov     (%r12), %rcx
    MOVQ    %rdx, LANTERN_SCRATCH_FIXED
    add     %rax, %rdx
    cmp     %rdx, %rcx
    jb      9f
    sub     %rax, %rcx
    lea     (%r12,%rcx), %rdx
    mov     %rdx, S7(%rsp)
    mov     %rax, (%rdx)
    movq    $24, 8(%rdx)
    mov     %r15, 16(%rdx)
    mov     %rcx, (%r12)
    lea     24(%rdx), %rdi
    mov     BeaconState_validators(%rbx), %r8
    add     %rbx, %r8
    xor     %ecx, %ecx
3:  cmp     %r15, %rcx
    jae     4f
    mov     (%r14,%rcx,8), %rax
    shl     $7, %rax
    add     %r8, %rax
    movdqu  Validator_pubkey(%rax), %xmm0
    movdqu  (Validator_pubkey + 16)(%rax), %xmm1
    movdqu  (Validator_pubkey + 32)(%rax), %xmm2
    movdqu  %xmm0, (%rdi)
    movdqu  %xmm1, 16(%rdi)
    movdqu  %xmm2, 32(%rdi)
    add     $48, %rdi
    inc     %rcx
    jmp     3b
4:  movl    $DOMAIN_BEACON_ATTESTER, L(%rsp)    # domain = get_domain(state, DOMAIN_BEACON_ATTESTER, data.target.epoch)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    lea     (IndexedAttestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rdx
    mov     %r12, %rcx
    lea     (L + 8)(%rsp), %r8
    call    lantern_get_domain
    test    %rax, %rax
    jnz     7f
    ADDRESS %rdi, lantern_type_AttestationData
    lea     IndexedAttestation_data(%rbp), %rsi
    lea     (L + 8)(%rsp), %rdx
    mov     %r12, %rcx
    lea     (L + 64)(%rsp), %r8
    call    lantern_compute_signing_root
    test    %rax, %rax
    jnz     7f
    movq    $56, (L + 40)(%rsp)
    movq    $24, (L + 48)(%rsp)
    movq    $32, (L + 56)(%rsp)
    cmpq    $0, S8(%rsp)
    jne     40f
    mov     S7(%rsp), %rdi                  # bls.FastAggregateVerify(pubkeys, signing_root, signature)
    lea     (L + 40)(%rsp), %rsi
    lea     IndexedAttestation_signature(%rbp), %rdx
    mov     %r12, %rcx
    mov     %r13, %r8
    CALL_GLOBAL crypto_bls_fast_aggregate_verify
7:  LEAVE 160
8:  xor     %eax, %eax
    LEAVE 160
6:  mov     $LANTERN_INVALID_VALIDATOR_INDEX, %eax
    LEAVE 160
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 160
40: mov     BeaconState_validators(%rbx), %rdi  # the keys: the validators' pubkeys
    add     %rbx, %rdi
    add     $Validator_pubkey, %rdi
    mov     %rbp, %rsi                      # the indices: the indexed attestation, as a BlsIndexList
    mov     S8(%rsp), %rdx
    lea     (L + 40)(%rsp), %rcx
    lea     IndexedAttestation_signature(%rbp), %r8
    mov     %r12, %r9
    mov     %r13, S7(%rsp)                  # valid: the 7th argument, at the stack pointer
    CALL_GLOBAL crypto_bls_fast_aggregate_verify_cached
    LEAVE 160
SPEC_END is_valid_indexed_attestation

.if FORK >= FORK_ALTAIR
/*
 * rbx state, rbp data, r12 delay, r13 out, r14 matching source, r15 matching target, S7 matching head.
 * Locals: L current epoch, L+8 target root (32), L+40 head root (32), L+72 SLOTS_PER_EPOCH, L+80 its root.
 */
SPEC_FUNCTION get_attestation_participation_flag_indices
    ENTER 96
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     (%rdx), %r12
    mov     %rcx, %r13
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     (AttestationData_target + Checkpoint_epoch)(%rbp), %rax
    lea     BeaconState_current_justified_checkpoint(%rbx), %rcx
    lea     BeaconState_previous_justified_checkpoint(%rbx), %rdx
    cmp     L(%rsp), %rax                   # justified_checkpoint
    cmovne  %rdx, %rcx
    xor     %r14d, %r14d                    # is_matching_source = data.source == justified_checkpoint
    mov     Checkpoint_epoch(%rcx), %rax
    cmp     (AttestationData_source + Checkpoint_epoch)(%rbp), %rax
    jne     1f
    lea     (AttestationData_source + Checkpoint_root)(%rbp), %rax
    add     $Checkpoint_root, %rcx
    NE32    %rax, %rcx, 1f
    mov     $1, %r14d
1:  mov     %rbx, %rdi                      # target_root = get_block_root(state, data.target.epoch)
    lea     (AttestationData_target + Checkpoint_epoch)(%rbp), %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_get_block_root
    test    %rax, %rax
    jnz     7f
    xor     %r15d, %r15d
    lea     (AttestationData_target + Checkpoint_root)(%rbp), %rax
    lea     (L + 8)(%rsp), %rcx
    NE32    %rax, %rcx, 2f
    mov     %r14, %r15                      # is_matching_target = is_matching_source and target_root_matches
2:  mov     %rbx, %rdi                      # head_root = get_block_root_at_slot(state, data.slot)
    lea     AttestationData_slot(%rbp), %rsi
    lea     (L + 40)(%rsp), %rdx
    call    lantern_get_block_root_at_slot
    test    %rax, %rax
    jnz     7f
    movq    $0, S7(%rsp)
    lea     AttestationData_beacon_block_root(%rbp), %rax
    lea     (L + 40)(%rsp), %rcx
    NE32    %rax, %rcx, 3f
    mov     %r15, S7(%rsp)
3:  mov     $LANTERN_INVALID_SOURCE, %eax   # assert is_matching_source
    test    %r14, %r14
    jz      7f
    movq    $SLOTS_PER_EPOCH, (L + 72)(%rsp)
    lea     (L + 72)(%rsp), %rdi
    lea     (L + 80)(%rsp), %rsi
    call    lantern_integer_squareroot
    movq    $LIST_FIXED, LIST_OFFSET(%r13)
    lea     LIST_FIXED(%r13), %rcx
    cmp     (L + 80)(%rsp), %r12            # source within integer_squareroot(SLOTS_PER_EPOCH)
    ja      4f
    movq    $TIMELY_SOURCE_FLAG_INDEX, (%rcx)
    add     $8, %rcx
4:  test    %r15, %r15
    jz      5f
.if FORK < FORK_DENEB
    cmp     $SLOTS_PER_EPOCH, %r12          # and inclusion_delay <= SLOTS_PER_EPOCH
    ja      5f
.endif
    movq    $TIMELY_TARGET_FLAG_INDEX, (%rcx)
    add     $8, %rcx
5:  cmpq    $0, S7(%rsp)
    je      6f
    cmp     $MIN_ATTESTATION_INCLUSION_DELAY, %r12
    jne     6f
    movq    $TIMELY_HEAD_FLAG_INDEX, (%rcx)
    add     $8, %rcx
6:  lea     LIST_FIXED(%r13), %rax
    sub     %rax, %rcx
    shr     $3, %rcx
    mov     %rcx, LIST_COUNT(%r13)
    xor     %eax, %eax
7:  LEAVE 96
SPEC_END get_attestation_participation_flag_indices
.endif

.if FORK == FORK_PHASE0
/*
 * rbx state, rbp attestation, r12 config, r13 scratch, r14 result, r15 scratch size,
 * S8 the PartRef offset of the list to append to, S9 the indexed attestation, S10 the committee.
 * Locals: L previous epoch, L+8 current epoch, L+16 committees per slot, L+24 valid,
 * L+32 proposer index, L+40 the scratch size callees get, L+48 the new value, L+56 its bit bytes.
 */
SPEC_FUNCTION process_attestation
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    NEED_SCRATCH_B %r13, %rbx, 10, ATTEST_EXTRA, 9f
    movq    $0, (%r14)
    mov     (%r13), %r15
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    lea     LIST_FIXED(,%rcx,8), %rcx       # own scratch at the end: the indexed attestation, the committee
    lea     (IndexedAttestation__fixed + 8)(%rcx), %rdx
    mov     %r15, %rax
    sub     %rdx, %rax
    lea     (%r13,%rax), %rsi
    mov     %rdx, (%rsi)
    mov     %rsi, S9(%rsp)
    sub     %rcx, %rax
    lea     (%r13,%rax), %rsi
    mov     %rcx, (%rsi)
    mov     %rsi, S10(%rsp)
    mov     %rax, (L + 40)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rcx
    cmp     L(%rsp), %rcx                   # assert data.target.epoch in (previous, current)
    je      1f
    cmp     (L + 8)(%rsp), %rcx
    jne     6f
1:  mov     (Attestation_data + AttestationData_slot)(%rbp), %rdx
    mov     %rdx, %rsi                      # assert data.target.epoch == compute_epoch_at_slot(data.slot)
    shr     $LOG2_SLOTS_PER_EPOCH, %rsi
    cmp     %rsi, %rcx
    jne     6f
    mov     %rdx, %rsi                      # assert data.slot + MIN_ATTESTATION_INCLUSION_DELAY <= state.slot
    add     $MIN_ATTESTATION_INCLUSION_DELAY, %rsi
    jc      5f
    cmp     BeaconState_slot(%rbx), %rsi
    ja      6f
    mov     %rdx, %rsi                      # assert state.slot <= data.slot + SLOTS_PER_EPOCH
    add     $SLOTS_PER_EPOCH, %rsi
    jc      5f
    cmp     %rsi, BeaconState_slot(%rbx)
    ja      6f
    mov     (L + 40)(%rsp), %rax
    mov     %rax, (%r13)
    mov     %rbx, %rdi                      # assert data.index < get_committee_count_per_slot(state, data.target.epoch)
    lea     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rsi
    mov     %r13, %rcx
    lea     (L + 16)(%rsp), %r8
    mov     CONFIG_COMMITTEE_CACHE(%r12), %rdx
    call    lantern_get_committee_count_per_slot
    test    %rax, %rax
    jnz     7f
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    mov     (Attestation_data + AttestationData_index)(%rbp), %rcx
    cmp     (L + 16)(%rsp), %rcx
    jae     6f
    mov     (L + 40)(%rsp), %rax
    mov     %rax, (%r13)
    mov     %rbx, %rdi                      # committee = get_beacon_committee(state, data.slot, data.index)
    lea     (Attestation_data + AttestationData_slot)(%rbp), %rsi
    lea     (Attestation_data + AttestationData_index)(%rbp), %rdx
    mov     %r13, %r8
    mov     S10(%rsp), %r9
    mov     CONFIG_COMMITTEE_CACHE(%r12), %rcx
    call    lantern_get_beacon_committee
    CHECK_STATUS %r14, 7f, 8f
    mov     S10(%rsp), %rcx
    mov     LIST_COUNT(%rcx), %rcx
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    cmp     (Attestation_aggregation_bits + 8)(%rbp), %rcx  # assert len(attestation.aggregation_bits) == len(committee)
    jne     6f
    mov     (L + 40)(%rsp), %rax
    mov     %rax, (%r13)
    mov     %rbx, %rdi                      # proposer_index = get_beacon_proposer_index(state)
    mov     %r13, %rsi
    lea     (L + 32)(%rsp), %rdx
    call    lantern_get_beacon_proposer_index
    CHECK_STATUS %r14, 7f, 8f
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rcx
    cmp     (L + 8)(%rsp), %rcx
    jne     1f
    lea     BeaconState_current_justified_checkpoint(%rbx), %rsi
    movq    $BeaconState_current_epoch_attestations, S8(%rsp)
    jmp     2f
1:  lea     BeaconState_previous_justified_checkpoint(%rbx), %rsi
    movq    $BeaconState_previous_epoch_attestations, S8(%rsp)
2:  lea     (Attestation_data + AttestationData_source)(%rbp), %rdi
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    mov     Checkpoint_epoch(%rdi), %rcx    # assert data.source == the justified checkpoint of its epoch
    cmp     Checkpoint_epoch(%rsi), %rcx
    jne     6f
    add     $Checkpoint_root, %rdi
    add     $Checkpoint_root, %rsi
    NE32    %rdi, %rsi, 6f
    mov     (L + 40)(%rsp), %rax
    mov     %rax, (%r13)
    mov     %rbx, %rdi                      # assert is_valid_indexed_attestation(state, get_indexed_attestation(...))
    mov     %rbp, %rsi
    mov     %r13, %rcx
    mov     S9(%rsp), %r8
    mov     CONFIG_COMMITTEE_CACHE(%r12), %rdx
    call    lantern_get_indexed_attestation
    CHECK_STATUS %r14, 7f, 8f
    mov     (L + 40)(%rsp), %rax
    mov     %rax, (%r13)
    mov     %rbx, %rdi
    mov     S9(%rsp), %rsi
    mov     %r13, %rcx
    lea     (L + 24)(%rsp), %r8
    mov     CONFIG_PUBKEY_CACHE(%r12), %rdx
    call    lantern_is_valid_indexed_attestation
    CHECK_STATUS %r14, 7f, 8f
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    cmpq    $0, (L + 24)(%rsp)
    je      6f
    mov     S8(%rsp), %rcx                  # append the PendingAttestation: the end of the list's entries
    mov     (%rbx,%rcx), %rdx
    mov     8(%rbx,%rcx), %r8
    lea     (%rbx,%rdx), %rdi
3:  test    %r8, %r8
    jz      4f
    add     (%rdi), %rdi
    dec     %r8
    jmp     3b
4:  cmp     $BeaconState_previous_epoch_attestations, %rcx
    jne     41f
    mov     BeaconState_current_epoch_attestations(%rbx), %rsi  # the list ends where the next part starts
    jmp     42f
41: mov     (%rbx), %rsi                    # or at the end of the value
42: add     %rbx, %rsi
    mov     (Attestation_aggregation_bits + 8)(%rbp), %r9
    lea     7(%r9), %rdx
    shr     $3, %rdx                        # the bytes of aggregation_bits
    lea     (PendingAttestation__fixed + 7)(%rdx), %rax
    and     $-8, %rax                       # the PendingAttestation's size
    lea     (%rdi,%rax), %r8
    cmp     %rsi, %r8
    ja      9f                              # no room: the state is unchanged
    test    %rdx, %rdx
    jz      43f
    movq    $0, -8(%rdi,%rax)               # zero the padding after the bit bytes
43: mov     %rax, (%rdi)                    # size; aggregation_bits at the end of the fixed part
    movq    $PendingAttestation__fixed, PendingAttestation_aggregation_bits(%rdi)
    mov     %r9, (PendingAttestation_aggregation_bits + 8)(%rdi)
    mov     BeaconState_slot(%rbx), %r8     # inclusion_delay = state.slot - data.slot
    sub     (Attestation_data + AttestationData_slot)(%rbp), %r8
    mov     %r8, PendingAttestation_inclusion_delay(%rdi)
    mov     (L + 32)(%rsp), %r8
    mov     %r8, PendingAttestation_proposer_index(%rdi)
    mov     %rdi, (L + 48)(%rsp)
    mov     %rdx, (L + 56)(%rsp)
    lea     PendingAttestation_data(%rdi), %rdi
    lea     Attestation_data(%rbp), %rsi
    mov     $AttestationData__mem, %edx
    call    lantern_copy
    mov     (L + 48)(%rsp), %rdi
    add     $PendingAttestation__fixed, %rdi
    PART    %rsi, %rax, %rbp, Attestation_aggregation_bits
    mov     (L + 56)(%rsp), %rdx
    call    lantern_copy
    mov     S8(%rsp), %rcx                  # the count, last
    incq    8(%rbx,%rcx)
8:  xor     %eax, %eax
7:  LEAVE 64
5:  mov     $LANTERN_INVALID_OVERFLOW, %eax
6:  mov     %rax, (%r14)
    xor     %eax, %eax
    LEAVE 64
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
SPEC_END process_attestation
.else
/*
 * rbx state, rbp attestation, r12 scratch, r13 result, r14 committee offset then the flag index,
 * r15 committee then the attesting cursor, S7 committee indices.
 * Locals: L previous epoch, L+8 current epoch, L+16 committees per slot, L+24 committee index,
 * L+32 inclusion delay, L+40 valid, L+48 flags (FLAGS_BYTES), L+96 proposer, L+104 base reward,
 * L+112 index or cursor, L+120 proposer reward numerator, L+128 flag, L+136 cursor end, L+144 the indexed
 * attestation, L+152 the attesting list, L+160 the scratch size callees get, L+168 participation,
 * L+176 base reward per increment.
 */
/* process_attestation of the spec: attestation_memo with a base reward factor of its own. */
SPEC_FUNCTION process_attestation
    ENTER 16
    movq    $0, L(%rsp)
    lea     L(%rsp), %r9
    call    attestation_memo
    LEAVE 16
SPEC_END process_attestation

/*
 * L0: process_attestation, with r9 the address of the block's get_base_reward_per_increment(state):
 * 0 until an attestation finds it, which stores it there. The operations of one block change no
 * effective balance and no active validator of the current epoch, so its attestations share it.
 * L+192: that address.
 */
LOCAL_FUNCTION attestation_memo
    ENTER 208
    mov     %r9, (L + 192)(%rsp)
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, (L + 184)(%rsp)           # config
    mov     %rcx, %r12
    mov     %r8, %r13
    NEED_SCRATCH_B %r12, %rbx, 10, ATTEST_EXTRA, 9f
    movq    $0, (%r13)
    mov     (%r12), %rdx                    # own scratch at the end: committee indices, committee, indexed attestation, attesting
    mov     (BeaconState_validators + 8)(%rbx), %rcx
    sub     $CIDX_BYTES, %rdx
    lea     (%r12,%rdx), %rax
    movq    $CIDX_BYTES, (%rax)
    mov     %rax, S7(%rsp)
    lea     LIST_FIXED(,%rcx,8), %rsi       # L(n)
    sub     %rsi, %rdx
    lea     (%r12,%rdx), %r15
    mov     %rsi, (%r15)
    lea     (IndexedAttestation__fixed + 8)(%rsi), %rdi
    sub     %rdi, %rdx
    lea     (%r12,%rdx), %rax
    mov     %rdi, (%rax)
    mov     %rax, (L + 144)(%rsp)
    sub     %rsi, %rdx
    lea     (%r12,%rdx), %rax
    mov     %rsi, (%rax)
    mov     %rax, (L + 152)(%rsp)
    mov     %rdx, (L + 160)(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_previous_epoch
    mov     %rbx, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rcx
    cmp     L(%rsp), %rcx                   # assert data.target.epoch in (previous, current)
    je      10f
    cmp     (L + 8)(%rsp), %rcx
    jne     6f
10: mov     (Attestation_data + AttestationData_slot)(%rbp), %rdx
    mov     %rdx, %rsi                      # assert data.target.epoch == compute_epoch_at_slot(data.slot)
    shr     $LOG2_SLOTS_PER_EPOCH, %rsi
    cmp     %rsi, %rcx
    jne     6f
    add     $MIN_ATTESTATION_INCLUSION_DELAY, %rdx  # assert data.slot + MIN_ATTESTATION_INCLUSION_DELAY <= state.slot
    jc      5f
    cmp     BeaconState_slot(%rbx), %rdx
    ja      6f
.if FORK < FORK_DENEB
    mov     (Attestation_data + AttestationData_slot)(%rbp), %rdx   # assert state.slot <= data.slot + SLOTS_PER_EPOCH
    add     $SLOTS_PER_EPOCH, %rdx
    jc      5f
    cmp     BeaconState_slot(%rbx), %rdx
    jb      6f
.endif
.if FORK >= FORK_ELECTRA
    cmpq    $0, (Attestation_data + AttestationData_index)(%rbp)  # assert data.index == 0
    jne     6f
    lea     Attestation_committee_bits(%rbp), %rdi
    mov     S7(%rsp), %rsi
    call    lantern_get_committee_indices
    xor     %r14d, %r14d                    # committee_offset
    mov     S7(%rsp), %rax
    lea     LIST_FIXED(%rax), %rcx
    mov     LIST_COUNT(%rax), %rdx
    lea     (%rcx,%rdx,8), %rdx
    mov     %rdx, (L + 136)(%rsp)
    mov     %rcx, (L + 112)(%rsp)           # the cursor over committee indices
1:  mov     (L + 112)(%rsp), %rax
    cmp     (L + 136)(%rsp), %rax
    jae     3f
    mov     (%rax), %rcx
    add     $8, %rax
    mov     %rax, (L + 112)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # assert committee_index < get_committee_count_per_slot(...)
    lea     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rsi
    mov     %r12, %rcx
    lea     (L + 16)(%rsp), %r8
    mov     (L + 184)(%rsp), %rdx
    mov     CONFIG_COMMITTEE_CACHE(%rdx), %rdx
    call    lantern_get_committee_count_per_slot
    test    %rax, %rax
    jnz     7f
    mov     (L + 24)(%rsp), %rcx
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    cmp     (L + 16)(%rsp), %rcx
    jae     6f
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi
    lea     (Attestation_data + AttestationData_slot)(%rbp), %rsi
    lea     (L + 24)(%rsp), %rdx
    mov     %r12, %r8
    mov     %r15, %r9
    mov     (L + 184)(%rsp), %rcx
    mov     CONFIG_COMMITTEE_CACHE(%rcx), %rcx
    call    lantern_get_beacon_committee
    CHECK_STATUS %r13, 7f, 8f
    PART    %rsi, %rdx, %rbp, Attestation_aggregation_bits
    mov     LIST_COUNT(%r15), %rcx
    xor     %r8d, %r8d                      # committee_attesters
2:  test    %rcx, %rcx
    jz      25f
    mov     $LANTERN_INVALID_ATTESTATION, %eax  # aggregation_bits[committee_offset + index]
    cmp     %rdx, %r14
    jae     6f
    bt      %r14, (%rsi)
    adc     $0, %r8
    inc     %r14
    dec     %rcx
    jmp     2b
25: mov     $LANTERN_INVALID_ATTESTATION, %eax
    test    %r8, %r8                        # assert len(committee_attesters) > 0
    jz      6f
    jmp     1b
3:  mov     $LANTERN_INVALID_ATTESTATION, %eax  # assert len(attestation.aggregation_bits) == committee_offset
    cmp     (Attestation_aggregation_bits + 8)(%rbp), %r14
    jne     6f
.else
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # assert data.index < get_committee_count_per_slot(state, data.target.epoch)
    lea     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rsi
    mov     %r12, %rcx
    lea     (L + 16)(%rsp), %r8
    mov     (L + 184)(%rsp), %rdx
    mov     CONFIG_COMMITTEE_CACHE(%rdx), %rdx
    call    lantern_get_committee_count_per_slot
    test    %rax, %rax
    jnz     7f
    mov     (Attestation_data + AttestationData_index)(%rbp), %rcx
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    cmp     (L + 16)(%rsp), %rcx
    jae     6f
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # committee = get_beacon_committee(state, data.slot, data.index)
    lea     (Attestation_data + AttestationData_slot)(%rbp), %rsi
    lea     (Attestation_data + AttestationData_index)(%rbp), %rdx
    mov     %r12, %r8
    mov     %r15, %r9
    mov     (L + 184)(%rsp), %rcx
    mov     CONFIG_COMMITTEE_CACHE(%rcx), %rcx
    call    lantern_get_beacon_committee
    CHECK_STATUS %r13, 7f, 8f
    mov     $LANTERN_INVALID_ATTESTATION, %eax  # assert len(attestation.aggregation_bits) == len(committee)
    mov     LIST_COUNT(%r15), %rcx
    cmp     (Attestation_aggregation_bits + 8)(%rbp), %rcx
    jne     6f
.endif
    mov     BeaconState_slot(%rbx), %rax
    sub     (Attestation_data + AttestationData_slot)(%rbp), %rax
    mov     %rax, (L + 32)(%rsp)
    movq    $FLAGS_BYTES, (L + 48)(%rsp)
    mov     %rbx, %rdi                      # participation_flag_indices
    lea     Attestation_data(%rbp), %rsi
    lea     (L + 32)(%rsp), %rdx
    lea     (L + 48)(%rsp), %rcx
    call    lantern_get_attestation_participation_flag_indices
    CHECK_STATUS %r13, 7f, 8f
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # assert is_valid_indexed_attestation(state, get_indexed_attestation(...))
    mov     %rbp, %rsi
    mov     %r12, %rcx
    mov     (L + 144)(%rsp), %r8
    mov     (L + 184)(%rsp), %rdx
    mov     CONFIG_COMMITTEE_CACHE(%rdx), %rdx
    call    lantern_get_indexed_attestation
    CHECK_STATUS %r13, 7f, 8f
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi
    mov     (L + 144)(%rsp), %rsi
    mov     %r12, %rcx
    lea     (L + 40)(%rsp), %r8
    mov     (L + 184)(%rsp), %rdx
    mov     CONFIG_PUBKEY_CACHE(%rdx), %rdx
    call    lantern_is_valid_indexed_attestation
    CHECK_STATUS %r13, 7f, 8f
    mov     $LANTERN_INVALID_ATTESTATION, %eax
    cmpq    $0, (L + 40)(%rsp)
    je      6f
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rbp), %rax
    cmp     (L + 8)(%rsp), %rax
    jne     31f
    PART    %rax, %rcx, %rbx, BeaconState_current_epoch_participation
    jmp     32f
31: PART    %rax, %rcx, %rbx, BeaconState_previous_epoch_participation
32: mov     %rax, (L + 168)(%rsp)
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi                      # for index in get_attesting_indices(state, attestation)
    mov     %rbp, %rsi
    mov     %r12, %rcx
    mov     (L + 152)(%rsp), %r8
    mov     (L + 184)(%rsp), %rdx
    mov     CONFIG_COMMITTEE_CACHE(%rdx), %rdx
    call    lantern_get_attesting_indices
    CHECK_STATUS %r13, 7f, 8f
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     (L + 192)(%rsp), %rax           # get_base_reward's factor: once for every attestation of the block
    mov     (%rax), %rax
    mov     %rax, (L + 176)(%rsp)
    test    %rax, %rax
    jnz     47f
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     (L + 176)(%rsp), %rdx
    call    lantern_get_base_reward_per_increment
    test    %rax, %rax
    jnz     7f
    mov     (L + 192)(%rsp), %rax
    mov     (L + 176)(%rsp), %rcx
    mov     %rcx, (%rax)
47:
    movq    $0, (L + 120)(%rsp)
    mov     (L + 152)(%rsp), %rax           # the attesting list; the committee indices are done
    lea     LIST_FIXED(%rax), %r15
    mov     LIST_COUNT(%rax), %rcx
    lea     (%r15,%rcx,8), %rcx
    mov     %rcx, (L + 136)(%rsp)
4:  cmp     (L + 136)(%rsp), %r15
    jae     45f
    mov     (%r15), %rax
    add     $8, %r15
    mov     %rax, (L + 112)(%rsp)
    xor     %r14d, %r14d                    # for flag_index, weight in enumerate(PARTICIPATION_FLAG_WEIGHTS)
41: cmp     $3, %r14
    jae     4b
    mov     (L + 48 + LIST_COUNT)(%rsp), %rcx   # flag_index in participation_flag_indices
    lea     (L + 48 + LIST_FIXED)(%rsp), %rdx
42: test    %rcx, %rcx
    jz      44f
    cmp     (%rdx), %r14
    je      43f
    add     $8, %rdx
    dec     %rcx
    jmp     42b
43: mov     %r14, (L + 128)(%rsp)
    mov     (L + 168)(%rsp), %rdi           # and not has_flag(epoch_participation[index], flag_index)
    add     (L + 112)(%rsp), %rdi
    lea     (L + 128)(%rsp), %rsi
    lea     (L + 40)(%rsp), %rdx
    call    lantern_has_flag
    cmpq    $0, (L + 40)(%rsp)
    jne     44f
    mov     (L + 168)(%rsp), %rdi           # epoch_participation[index] = add_flag(...)
    add     (L + 112)(%rsp), %rdi
    lea     (L + 128)(%rsp), %rsi
    mov     %rdi, %rdx
    call    lantern_add_flag
    PART    %rcx, %rdx, %rbx, BeaconState_validators
    mov     (L + 112)(%rsp), %rax           # proposer_reward_numerator += get_base_reward(state, index) * weight
    shl     $7, %rax
    mov     Validator_effective_balance(%rcx,%rax), %rax
    xor     %edx, %edx
    mov     $EFFECTIVE_BALANCE_INCREMENT, %ecx
    div     %rcx                            # increments * base_reward_per_increment
    imul    (L + 176)(%rsp), %rax
    mov     %rax, (L + 104)(%rsp)
    mov     $TIMELY_SOURCE_WEIGHT, %eax     # the source and head weights are equal
    mov     $TIMELY_TARGET_WEIGHT, %ecx
    cmp     $TIMELY_TARGET_FLAG_INDEX, %r14
    cmove   %rcx, %rax
    imul    (L + 104)(%rsp), %rax
    add     %rax, (L + 120)(%rsp)
    jc      5f
44: inc     %r14
    jmp     41b
45: mov     (L + 120)(%rsp), %rax           # proposer_reward = numerator // proposer_reward_denominator
    mov     $((WEIGHT_DENOMINATOR - PROPOSER_WEIGHT) * WEIGHT_DENOMINATOR / PROPOSER_WEIGHT), %ecx
    xor     %edx, %edx
    div     %rcx
    mov     %rax, (L + 120)(%rsp)
.if FORK >= FORK_FULU
    mov     %rbx, %rdi
    lea     (L + 96)(%rsp), %rsi
    call    lantern_get_beacon_proposer_index
.else
    mov     (L + 160)(%rsp), %rax
    mov     %rax, (%r12)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     (L + 96)(%rsp), %rdx
    call    lantern_get_beacon_proposer_index
    test    %rax, %rax
    jnz     7f
.endif
    mov     %rbx, %rdi
    lea     (L + 96)(%rsp), %rsi
    lea     (L + 120)(%rsp), %rdx
    call    lantern_increase_balance
8:  xor     %eax, %eax
7:  LEAVE 208
5:  mov     $LANTERN_INVALID_OVERFLOW, %eax
6:  mov     %rax, (%r13)
    xor     %eax, %eax
    LEAVE 208
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 208
END_FUNCTION attestation_memo
.endif

.if TIMELY_SOURCE_WEIGHT != TIMELY_HEAD_WEIGHT
.error "lantern_process_attestation takes the source weight for the head flag"
.endif
