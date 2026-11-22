/*
 * Shuffling, seeds and proposer selection, x86-64. Requirements: docs/reference/helpers.md.
 */

/* L0: digest rdx = sha256 of the rsi bytes at rdi; rsi is at most 96. Locals: a ByteList (24 + 96). */
LOCAL_FUNCTION sha256_short
    FRAME 128
    lea     24(%rsi), %rax                  # a ByteList: size, offset 24, count, then the bytes
    mov     %rax, 0(%rsp)
    movq    $24, 8(%rsp)
    mov     %rsi, 16(%rsp)
    mov     %rdx, %r8
    mov     %rsi, %rcx
    mov     %rdi, %rsi
    lea     24(%rsp), %rdi
    rep movsb
    mov     %rsp, %rdi
    mov     %r8, %rsi
    CALL_GLOBAL crypto_sha256
    xor     %eax, %eax
    UNFRAME 128
END_FUNCTION sha256_short

/*
 * rbx index count, rbp seed, r12 bucket hashes, r13 entries, r14 round, r15 pivot,
 * S7 buckets, S8 bucket. Locals: L the message (seed, round, bucket), L+40 the digest.
 */
SPEC_FUNCTION compute_shuffled_permutation
    ENTER 80
    mov     (%rdi), %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    test    %rbx, %rbx                      # the spec divides by index_count
    jz      8f
    lea     255(%rbx), %rax
    shr     $8, %rax
    mov     %rax, S7(%rsp)                  # buckets
    shl     $5, %rax
    add     $8, %rax
    cmp     %rax, (%r12)
    jb      9f
    lea     LIST_FIXED(,%rbx,8), %rax
    cmp     %rax, LIST_SIZE(%r13)
    jb      9f
    movq    $LIST_FIXED, LIST_OFFSET(%r13)
    mov     %rbx, LIST_COUNT(%r13)
    add     $LIST_FIXED, %r13
    xor     %eax, %eax                      # indices = [0, 1, ..., index_count - 1]
1:  mov     %rax, (%r13,%rax,8)
    inc     %rax
    cmp     %rbx, %rax
    jb      1b
    add     $8, %r12
    lea     L(%rsp), %rax                   # the message starts with the seed
    COPY32  %rax, %rbp
    xor     %r14d, %r14d
2:  cmp     $SHUFFLE_ROUND_COUNT, %r14
    jae     7f
    mov     %r14b, (L + 32)(%rsp)           # round_bytes
    lea     L(%rsp), %rdi                   # pivot = bytes_to_uint64(sha256(seed + round_bytes)[0:8]) % index_count
    mov     $33, %esi
    lea     (L + 40)(%rsp), %rdx
    call    sha256_short
    mov     (L + 40)(%rsp), %rax
    xor     %edx, %edx
    div     %rbx
    mov     %rdx, %r15
    movq    $0, S8(%rsp)                    # the source of each bucket of positions
3:  mov     S8(%rsp), %rax
    cmp     S7(%rsp), %rax
    jae     4f
    mov     %eax, (L + 33)(%rsp)            # uint_to_bytes(Uint32(position_bucket))
    lea     L(%rsp), %rdi
    mov     $37, %esi
    shl     $5, %rax
    lea     (%r12,%rax), %rdx
    call    sha256_short
    incq    S8(%rsp)
    jmp     3b
4:  xor     %r8d, %r8d                      # for i in range(index_count)
5:  mov     (%r13,%r8,8), %rsi              # indices[i]
    lea     (%r15,%rbx), %rdi
    sub     %rsi, %rdi                      # flip = (pivot + index_count - indices[i]) % index_count
    mov     %rdi, %rax
    sub     %rbx, %rax
    cmp     %rbx, %rdi
    cmovae  %rax, %rdi
    mov     %rdi, %rax                      # position = max(indices[i], flip)
    cmp     %rdi, %rsi
    cmova   %rsi, %rax
    mov     %rax, %rcx                      # source[(position % 256) // 8] of its bucket
    shr     $3, %rax
    movzbl  (%r12,%rax), %eax
    and     $7, %ecx
    shr     %cl, %eax
    test    $1, %al
    cmovnz  %rdi, %rsi                      # indices[i] = flip if bit else indices[i]
    mov     %rsi, (%r13,%r8,8)
    inc     %r8
    cmp     %rbx, %r8
    jb      5b
    inc     %r14
    jmp     2b
7:  xor     %eax, %eax
    LEAVE 80
8:  mov     $LANTERN_INVALID_SHUFFLED_INDEX, %eax
    LEAVE 80
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 80
SPEC_END compute_shuffled_permutation

/*
 * rbx index, rbp index count, r12 round, r13 flip, r14 out, r15 position.
 * Locals: L the message (seed, round, bucket), L+40 the digest.
 */
SPEC_FUNCTION compute_shuffled_index
    ENTER 80
    mov     (%rdi), %rbx
    mov     (%rsi), %rbp
    mov     %r8, %r14
    cmp     %rbp, %rbx                      # assert index < index_count
    jae     8f
    lea     L(%rsp), %rax                   # the message starts with the seed
    COPY32  %rax, %rdx
    xor     %r12d, %r12d
1:  cmp     $SHUFFLE_ROUND_COUNT, %r12
    jae     3f
    mov     %r12b, (L + 32)(%rsp)           # round_bytes
    lea     L(%rsp), %rdi                   # pivot = bytes_to_uint64(sha256(seed + round_bytes)[0:8]) % index_count
    mov     $33, %esi
    lea     (L + 40)(%rsp), %rdx
    call    sha256_short
    mov     (L + 40)(%rsp), %rax
    xor     %edx, %edx
    div     %rbp
    lea     (%rdx,%rbp), %r13
    sub     %rbx, %r13                      # flip = (pivot + index_count - index) % index_count
    mov     %r13, %rax
    sub     %rbp, %rax
    cmp     %rbp, %r13
    cmovae  %rax, %r13
    mov     %r13, %r15                      # position = max(index, flip)
    cmp     %r13, %rbx
    cmova   %rbx, %r15
    mov     %r15, %rax
    shr     $8, %rax
    mov     %eax, (L + 33)(%rsp)            # uint_to_bytes(uint32(position // 256))
    lea     L(%rsp), %rdi                   # source = sha256(seed + round_bytes + position_bytes)
    mov     $37, %esi
    lea     (L + 40)(%rsp), %rdx
    call    sha256_short
    mov     %r15, %rax                      # source[(position % 256) // 8]
    shr     $3, %rax
    and     $31, %eax
    movzbl  (L + 40)(%rsp,%rax), %eax
    mov     %r15, %rcx
    and     $7, %ecx
    shr     %cl, %eax
    test    $1, %al
    cmovnz  %r13, %rbx                      # index = flip if bit else index
    inc     %r12
    jmp     1b
3:  mov     %rbx, (%r14)
    xor     %eax, %eax
    LEAVE 80
8:  mov     $LANTERN_INVALID_SHUFFLED_INDEX, %eax
    LEAVE 80
SPEC_END compute_shuffled_index

/* Locals: rsp+0 the message (domain type 4, epoch 8, mix 32), rsp+48 the mix epoch, rsp+56 out. */
SPEC_FUNCTION get_seed
    FRAME 64
    mov     (%rsi), %rax
    MOVQ    %r8, EPOCHS_PER_HISTORICAL_VECTOR - MIN_SEED_LOOKAHEAD - 1
    add     %rax, %r8                       # epoch + EPOCHS_PER_HISTORICAL_VECTOR - MIN_SEED_LOOKAHEAD - 1
    jc      8f
    mov     %r8, 48(%rsp)
    mov     %rcx, 56(%rsp)
    mov     (%rdx), %r9d
    mov     %r9d, 0(%rsp)                   # domain_type
    mov     %rax, 4(%rsp)                   # uint_to_bytes(epoch)
    lea     48(%rsp), %rsi
    lea     12(%rsp), %rdx
    call    lantern_get_randao_mix
    mov     %rsp, %rdi
    mov     $44, %esi
    mov     56(%rsp), %rdx
    call    sha256_short
    UNFRAME 64
8:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    UNFRAME 64
SPEC_END get_seed

/*
 * rbx state, rbp indices, r12 seed, r13 scratch, r14 out, r15 i, S7 the index, S8 scratch size,
 * S9 candidate, S10 the round. Locals: L the position, L+8 total, L+16 the flip, L+24 message
 * (seed, i // 16), L+64 digest, L+96 the shuffle's message (seed, round, position // 256), L+136
 * its digest, L+168 the pivot of each round. compute_shuffled_index inline: the pivots of the
 * seed once, then for each candidate one digest a round; the random bytes once for each 16
 * candidates (32 before electra). The same values as the spec's steps.
 */
SPEC_FUNCTION compute_proposer_index
    ENTER 896
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     LIST_COUNT(%rbp), %rax
    test    %rax, %rax                      # assert len(indices) > 0
    jz      8f
    mov     %rax, (L + 8)(%rsp)
    mov     (%r13), %rax
    mov     %rax, S8(%rsp)
    lea     (L + 24)(%rsp), %rax
    COPY32  %rax, %r12
    lea     (L + 96)(%rsp), %rax            # the pivots: bytes_to_uint64(sha256(seed + round_bytes)[0:8]) % total
    COPY32  %rax, %r12
    movq    $0, S10(%rsp)
0:  mov     S10(%rsp), %rax
    mov     %al, (L + 128)(%rsp)
    lea     (L + 96)(%rsp), %rdi
    mov     $33, %esi
    lea     (L + 136)(%rsp), %rdx
    call    sha256_short
    mov     (L + 136)(%rsp), %rax
    xor     %edx, %edx
    divq    (L + 8)(%rsp)
    mov     S10(%rsp), %rcx
    mov     %rdx, (L + 168)(%rsp,%rcx,8)
    inc     %rcx
    mov     %rcx, S10(%rsp)
    cmp     $SHUFFLE_ROUND_COUNT, %rcx
    jb      0b
    xor     %r15d, %r15d
1:  mov     %r15, %rax                      # compute_shuffled_index(i % total, total, seed)
    xor     %edx, %edx
    divq    (L + 8)(%rsp)
    mov     %rdx, S7(%rsp)
    movq    $0, S10(%rsp)
11: mov     S10(%rsp), %rcx
    mov     (L + 168)(%rsp,%rcx,8), %rax    # flip = (pivot + total - index) % total
    add     (L + 8)(%rsp), %rax
    sub     S7(%rsp), %rax
    cmp     (L + 8)(%rsp), %rax
    jb      12f
    sub     (L + 8)(%rsp), %rax
12: mov     %rax, (L + 16)(%rsp)
    mov     S7(%rsp), %rdx                  # position = max(index, flip)
    cmp     %rax, %rdx
    cmova   %rdx, %rax
    mov     %rax, L(%rsp)
    mov     %cl, (L + 128)(%rsp)
    mov     %rax, %rdx
    shr     $8, %rdx
    mov     %edx, (L + 129)(%rsp)           # uint_to_bytes(uint32(position // 256))
    lea     (L + 96)(%rsp), %rdi            # source = sha256(seed + round_bytes + position_bytes)
    mov     $37, %esi
    lea     (L + 136)(%rsp), %rdx
    call    sha256_short
    mov     L(%rsp), %rax
    mov     %rax, %rcx                      # source[(position % 256) // 8]
    shr     $3, %rcx
    and     $31, %ecx
    movzbl  (L + 136)(%rsp,%rcx), %edx
    mov     %eax, %ecx
    and     $7, %ecx
    shr     %cl, %edx
    test    $1, %dl
    jz      13f
    mov     (L + 16)(%rsp), %rax            # index = flip if bit else index
    mov     %rax, S7(%rsp)
13: mov     S10(%rsp), %rcx
    inc     %rcx
    mov     %rcx, S10(%rsp)
    cmp     $SHUFFLE_ROUND_COUNT, %rcx
    jb      11b
    mov     S7(%rsp), %rax
    mov     LIST_FIXED(%rbp,%rax,8), %rax   # candidate_index
    mov     %rax, S9(%rsp)
.if FORK >= FORK_ELECTRA
    test    $15, %r15                       # random_bytes = sha256(seed + uint_to_bytes(i // 16)), new each 16
    jnz     14f
    mov     %r15, %rax
    shr     $4, %rax
    mov     %rax, (L + 56)(%rsp)
    lea     (L + 24)(%rsp), %rdi
    mov     $40, %esi
    lea     (L + 64)(%rsp), %rdx
    call    sha256_short
14: mov     %r15, %rax
    and     $15, %eax
    movzwl  (L + 64)(%rsp,%rax,2), %ecx     # random_value
    mov     S9(%rsp), %rax
    mov     BeaconState_validators(%rbx), %rdx
    add     %rbx, %rdx
    shl     $7, %rax
    mov     Validator_effective_balance(%rdx,%rax), %rax
    mov     $0xffff, %edx
    mul     %rdx                            # effective_balance * MAX_RANDOM_VALUE
    test    %rdx, %rdx
    jnz     6f
    MOVQ    %rdx, MAX_EFFECTIVE_BALANCE_ELECTRA
    imul    %rcx, %rdx                      # MAX_EFFECTIVE_BALANCE_ELECTRA * random_value fits
.else
    test    $31, %r15                       # sha256(seed + uint_to_bytes(i // 32)), new each 32
    jnz     15f
    mov     %r15, %rax
    shr     $5, %rax
    mov     %rax, (L + 56)(%rsp)
    lea     (L + 24)(%rsp), %rdi
    mov     $40, %esi
    lea     (L + 64)(%rsp), %rdx
    call    sha256_short
15: mov     %r15, %rax
    and     $31, %eax
    movzbl  (L + 64)(%rsp,%rax), %ecx       # random_byte
    mov     S9(%rsp), %rax
    mov     BeaconState_validators(%rbx), %rdx
    add     %rbx, %rdx
    shl     $7, %rax
    mov     Validator_effective_balance(%rdx,%rax), %rax
    mov     $0xff, %edx
    mul     %rdx                            # effective_balance * MAX_RANDOM_BYTE
    test    %rdx, %rdx
    jnz     6f
    MOVQ    %rdx, MAX_EFFECTIVE_BALANCE
    imul    %rcx, %rdx                      # MAX_EFFECTIVE_BALANCE * random_byte fits
.endif
    cmp     %rdx, %rax
    jae     2f
    inc     %r15
    jmp     1b
2:  mov     S9(%rsp), %rax
    mov     %rax, (%r14)
    xor     %eax, %eax
7:  LEAVE 896
6:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 896
8:  mov     $LANTERN_INVALID_NO_INDICES, %eax
    LEAVE 896
SPEC_END compute_proposer_index

/* Every fork: fulu's spec function, and lantern_node_proposers before fulu (node.md). */
/*
 * rbx state, rbp seed, r12 indices, r13 scratch, r14 out, r15 slot index, S8 scratch size.
 * Locals: L start slot, L+8 the message (seed, slot), L+48 the slot seed.
 */
SPEC_FUNCTION compute_proposer_indices
    ENTER 80
    mov     %rdi, %rbx
    mov     %rdx, %rbp
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     %r9, %r14
    mov     %rsi, %rdi
    lea     L(%rsp), %rsi
    call    lantern_compute_start_slot_at_epoch
    test    %rax, %rax
    jnz     7f
    mov     (%r13), %rax
    mov     %rax, S8(%rsp)
    lea     (L + 8)(%rsp), %rax
    COPY32  %rax, %rbp
    xor     %r15d, %r15d
1:  cmp     $SLOTS_PER_EPOCH, %r15
    jae     2f
    mov     L(%rsp), %rax                   # uint_to_bytes(start_slot + index)
    add     %r15, %rax
    jc      6f
    mov     %rax, (L + 40)(%rsp)
    lea     (L + 8)(%rsp), %rdi
    mov     $40, %esi
    lea     (L + 48)(%rsp), %rdx
    call    sha256_short
    mov     S8(%rsp), %rax
    mov     %rax, (%r13)
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     (L + 48)(%rsp), %rdx
    mov     %r13, %rcx
    lea     (%r14,%r15,8), %r8
    call    lantern_compute_proposer_index
    test    %rax, %rax
    jnz     7f
    inc     %r15
    jmp     1b
2:  xor     %eax, %eax
7:  LEAVE 80
6:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 80
SPEC_END compute_proposer_indices

/* Every fork: fulu's spec function, and lantern_node_proposers before fulu (node.md). */
/*
 * rbx state, rbp epoch, r12 scratch, r13 out, r14 validator count, r15 scratch size, S7 active list.
 * Locals: L domain type, L+8 seed.
 */
SPEC_FUNCTION get_beacon_proposer_indices
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    NEED_SCRATCH %r12, %rbx, 2, 9f
    mov     (BeaconState_validators + 8)(%rbx), %r14
    mov     (%r12), %r15
    SCRATCH_LIST %rax, %r12, %r15, 0, %r14
    mov     %rax, S7(%rsp)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %rax, %rdx
    call    lantern_get_active_validator_indices
    test    %rax, %rax
    jnz     7f
    movl    $DOMAIN_BEACON_PROPOSER, L(%rsp)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    lea     L(%rsp), %rdx
    lea     (L + 8)(%rsp), %rcx
    call    lantern_get_seed
    test    %rax, %rax
    jnz     7f
    SCRATCH_GIVE %r12, %r15, 1, %r14
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    lea     (L + 8)(%rsp), %rdx
    mov     S7(%rsp), %rcx
    mov     %r12, %r8
    mov     %r13, %r9
    call    lantern_compute_proposer_indices
7:  LEAVE 48
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END get_beacon_proposer_indices

/* ---------------------------------------------------------------- Domains and signing roots */

/* Locals: rsp+0 the ForkData value: current_version (4), genesis_validators_root (32). */
SPEC_FUNCTION compute_fork_data_root
    FRAME 48
    mov     (%rdi), %eax
    mov     %eax, ForkData_current_version(%rsp)
    lea     ForkData_genesis_validators_root(%rsp), %rax
    COPY32  %rax, %rsi
    mov     %rsp, %rsi                      # hash_tree_root(ForkData(...)): scratch rdx, out rcx
    ADDRESS %rdi, lantern_type_ForkData
    CALL_GLOBAL ssz_hash_tree_root
    UNFRAME 48
SPEC_END compute_fork_data_root

/* Locals: rsp+0 domain type pointer, rsp+8 out, rsp+16 the fork data root. */
SPEC_FUNCTION compute_domain
    FRAME 48
    mov     %rdi, 0(%rsp)
    mov     %r8, 8(%rsp)
    mov     %rsi, %rdi
    mov     %rdx, %rsi
    mov     %rcx, %rdx
    lea     16(%rsp), %rcx
    call    lantern_compute_fork_data_root
    test    %rax, %rax
    jnz     1f
    mov     0(%rsp), %rax
    mov     8(%rsp), %rcx
    mov     (%rax), %eax
    mov     %eax, (%rcx)                    # domain_type + fork_data_root[:28]
    movdqu  16(%rsp), %xmm0
    movdqu  %xmm0, 4(%rcx)
    mov     32(%rsp), %rax
    mov     %rax, 20(%rcx)
    mov     40(%rsp), %eax
    mov     %eax, 28(%rcx)
    xor     %eax, %eax
1:  UNFRAME 48
SPEC_END compute_domain

SPEC_LEAF get_domain
    mov     (%rdx), %rax
    lea     (BeaconState_fork + Fork_previous_version)(%rdi), %r9
    lea     (BeaconState_fork + Fork_current_version)(%rdi), %r10
    cmp     (BeaconState_fork + Fork_epoch)(%rdi), %rax
    cmovae  %r10, %r9                       # previous_version before the fork epoch
    lea     BeaconState_genesis_validators_root(%rdi), %rdx
    mov     %rsi, %rdi
    mov     %r9, %rsi
    jmp     lantern_compute_domain
SPEC_END get_domain

/* Locals: rsp+0 the SigningData value (object_root, domain), rsp+64 domain, rsp+72 scratch, rsp+80 out. */
SPEC_FUNCTION compute_signing_root
    FRAME 96
    mov     %rdx, 64(%rsp)
    mov     %rcx, 72(%rsp)
    mov     %r8, 80(%rsp)
    mov     %rcx, %rdx
    lea     SigningData_object_root(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root          # hash_tree_root(ssz_object)
    test    %rax, %rax
    jnz     1f
    mov     64(%rsp), %rax
    lea     SigningData_domain(%rsp), %rcx
    COPY32  %rcx, %rax
    ADDRESS %rdi, lantern_type_SigningData
    mov     %rsp, %rsi
    mov     72(%rsp), %rdx
    mov     80(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
1:  UNFRAME 96
SPEC_END compute_signing_root
