/*
 * P2p helpers, x86-64: fork versions and digests, subnets, sizes, the ENR values and the
 * gossip message-id. Requirements: docs/reference/networking.md.
 */

SSZ_DEPTH CEILLOG2_ATTESTATION_SUBNET_COUNT, ATTESTATION_SUBNET_COUNT
.if (1 << CEILLOG2_ATTESTATION_SUBNET_COUNT) != ATTESTATION_SUBNET_COUNT
.error "compute_subscribed_subnet takes the modulo of ATTESTATION_SUBNET_COUNT with a mask"
.endif
.if CONFIG_FULU_FORK_EPOCH != 96 || CONFIG_ALTAIR_FORK_VERSION != 8
.error "the fork version of fork k is at 16 * k - 8 of the config, its epoch at 16 * k"
.endif

/* Fork k's version, from its epoch on; GENESIS_FORK_VERSION before ALTAIR_FORK_EPOCH. */
SPEC_LEAF compute_fork_version
    mov     (%rdi), %rax
    mov     $(16 * FORK), %ecx
1:  test    %rcx, %rcx
    jz      2f
    cmp     (%rsi,%rcx), %rax
    jae     3f
    sub     $16, %rcx
    jmp     1b
3:  sub     $8, %rcx
2:  mov     (%rsi,%rcx), %eax
    mov     %eax, (%rdx)
    RETURN_OK
SPEC_END compute_fork_version

/*
 * rbx genesis_validators_root, rbp epoch, r12 config, r13 scratch, r14 out, r15 the base digest.
 * Locals: L the version, L+16 a root, L+48 the blob parameters.
 */
SPEC_FUNCTION compute_fork_digest
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %rbp, %rdi                      # fork_version = compute_fork_version(epoch)
    mov     %r12, %rsi
    lea     L(%rsp), %rdx
    call    lantern_compute_fork_version
    lea     L(%rsp), %rdi                   # compute_fork_data_root(fork_version, genesis_validators_root)
    mov     %rbx, %rsi
    mov     %r13, %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_compute_fork_data_root
    test    %rax, %rax
    jnz     9f
    mov     (L + 16)(%rsp), %r15d
.if FORK >= FORK_FULU
    mov     (%rbp), %rax                    # from FULU_FORK_EPOCH on: xor with the blob parameters' hash
    cmp     CONFIG_FULU_FORK_EPOCH(%r12), %rax
    jb      1f
    mov     %rbp, %rdi
    mov     %r12, %rsi
    lea     (L + 48)(%rsp), %rdx            # (epoch, max_blobs_per_block): the 16 bytes the spec hashes
    call    lantern_get_blob_parameters
    lea     (L + 48)(%rsp), %rdi
    mov     $16, %esi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_sha256_short
    xor     (L + 16)(%rsp), %r15d
1:
.endif
    mov     %r15d, (%r14)
    xor     %eax, %eax
9:  LEAVE 64
SPEC_END compute_fork_digest

SPEC_LEAF compute_attestation_subnet_prefix_bits
    mov     CONFIG_ATTESTATION_SUBNET_EXTRA_BITS(%rdi), %rax
    add     $CEILLOG2_ATTESTATION_SUBNET_COUNT, %rax
    jc      9f
    mov     %rax, (%rsi)
    RETURN_OK
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END compute_attestation_subnet_prefix_bits

SPEC_LEAF compute_min_epochs_for_block_requests
    mov     CONFIG_CHURN_LIMIT_QUOTIENT(%rdi), %rax
    shr     $1, %rax
    add     CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY(%rdi), %rax
    jc      9f
    mov     %rax, (%rsi)
    RETURN_OK
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END compute_min_epochs_for_block_requests

/* L0: rax = 32 + rax + rax // 6, with the carry flag set on overflow. Uses rcx, rdx, r8. */
LOCAL_FUNCTION lantern_compressed_len
    UNWIND_END_PROLOGUE
    mov     %rax, %r8
    xor     %edx, %edx
    mov     $6, %ecx
    div     %rcx
    add     $32, %r8
    jc      1f
    add     %r8, %rax
1:  ret
END_FUNCTION lantern_compressed_len

SPEC_LEAF max_compressed_len
    mov     (%rdi), %rax
    mov     %rsi, %rdi
    call    lantern_compressed_len
    jc      9f
    mov     %rax, (%rdi)
    RETURN_OK
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END max_compressed_len

SPEC_LEAF max_message_size
    mov     CONFIG_MAX_PAYLOAD_SIZE(%rdi), %rax
    mov     %rsi, %rdi
    call    lantern_compressed_len                  # max_compressed_len(MAX_PAYLOAD_SIZE) + 1024
    jc      9f
    add     $1024, %rax
    jc      9f
    mov     $(1024 * 1024), %ecx
    cmp     %rcx, %rax
    cmovb   %rcx, %rax
    mov     %rax, (%rdi)
    RETURN_OK
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END max_message_size

/*
 * rbx node_id, rbp epoch, r12 index, r13 config, r14 scratch, r15 out, S7 prefix_bits,
 * S8 EPOCHS_PER_SUBNET_SUBSCRIPTION.
 * Locals: L prefix_bits, L+8 the period, L+16 the seed, L+48 node_id_prefix,
 * L+56 1 << prefix_bits, L+64 the shuffled prefix.
 */
SPEC_FUNCTION compute_subscribed_subnet
    ENTER 80
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     (%rdx), %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    mov     %r13, %rdi                      # prefix_bits = compute_attestation_subnet_prefix_bits()
    lea     L(%rsp), %rsi
    call    lantern_compute_attestation_subnet_prefix_bits
    test    %rax, %rax
    jnz     7f
    mov     L(%rsp), %rax
    mov     %rax, S7(%rsp)
    mov     CONFIG_EPOCHS_PER_SUBNET_SUBSCRIPTION(%r13), %r8
    test    %r8, %r8                        # node_id % 0 raises
    jz      9f
    mov     %r8, S8(%rsp)
    xor     %edx, %edx                      # node_offset = node_id % EPOCHS_PER_SUBNET_SUBSCRIPTION
    mov     24(%rbx), %rax
    div     %r8
    mov     16(%rbx), %rax
    div     %r8
    mov     8(%rbx), %rax
    div     %r8
    mov     (%rbx), %rax
    div     %r8
    add     %rbp, %rdx                      # (epoch + node_offset) // EPOCHS_PER_SUBNET_SUBSCRIPTION
    jc      9f
    mov     %rdx, %rax
    xor     %edx, %edx
    div     %r8
    mov     %rax, (L + 8)(%rsp)
    lea     (L + 8)(%rsp), %rdi             # permutation_seed = sha256(uint_to_bytes(...))
    mov     $8, %esi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_sha256_short
    mov     S7(%rsp), %rcx
    cmp     $64, %rcx                       # Uint64(1 << prefix_bits) raises
    jae     9f
    xor     %eax, %eax                      # node_id_prefix = node_id >> (NODE_ID_BITS - prefix_bits)
    test    %rcx, %rcx
    jz      5f
    mov     24(%rbx), %rax
    neg     %cl
    add     $64, %cl
    shr     %cl, %rax
5:  mov     %rax, (L + 48)(%rsp)
    mov     S7(%rsp), %rcx
    mov     $1, %eax
    shl     %cl, %rax
    mov     %rax, (L + 56)(%rsp)
    lea     (L + 48)(%rsp), %rdi            # compute_shuffled_index(node_id_prefix, 1 << prefix_bits, seed)
    lea     (L + 56)(%rsp), %rsi
    lea     (L + 16)(%rsp), %rdx
    mov     %r14, %rcx
    lea     (L + 64)(%rsp), %r8
    call    lantern_compute_shuffled_index
    test    %rax, %rax
    jnz     7f
    mov     (L + 64)(%rsp), %rax            # (permutated_prefix + index) % ATTESTATION_SUBNET_COUNT
    add     %r12, %rax
    jc      9f
    and     $(ATTESTATION_SUBNET_COUNT - 1), %eax
    mov     %rax, (%r15)
    xor     %eax, %eax
7:  LEAVE 80
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 80
SPEC_END compute_subscribed_subnet

/* rbx node_id, rbp epoch, r12 config, r13 scratch, r14 out, r15 index, S7 SUBNETS_PER_NODE. Locals: L the index. */
SPEC_FUNCTION compute_subscribed_subnets
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     CONFIG_SUBNETS_PER_NODE(%r12), %rax
    mov     %rax, S7(%rsp)
    mov     (%r14), %rcx                    # room for SUBNETS_PER_NODE entries
    sub     $LIST_FIXED, %rcx
    jb      8f
    shr     $3, %rcx
    cmp     %rax, %rcx
    jb      8f
    movq    $LIST_FIXED, 8(%r14)
    xor     %r15d, %r15d
1:  cmp     S7(%rsp), %r15
    jae     2f
    mov     %r15, L(%rsp)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    lea     L(%rsp), %rdx
    mov     %r12, %rcx
    mov     %r13, %r8
    lea     LIST_FIXED(%r14,%r15,8), %r9
    call    lantern_compute_subscribed_subnet
    test    %rax, %rax
    jnz     9f
    inc     %r15
    jmp     1b
2:  mov     S7(%rsp), %rax
    mov     %rax, 16(%r14)
    xor     %eax, %eax
9:  LEAVE 16
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END compute_subscribed_subnets

.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
SPEC_LEAF compute_max_request_blob_sidecars
    mov     CONFIG_MAX_REQUEST_BLOCKS_DENEB(%rdi), %rax
.if FORK == FORK_ELECTRA
    mulq    CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA(%rdi)
.else
    mulq    CONFIG_MAX_BLOBS_PER_BLOCK(%rdi)
.endif
    jc      9f
    mov     %rax, (%rsi)
    RETURN_OK
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END compute_max_request_blob_sidecars
.endif

.if FORK >= FORK_FULU
SPEC_LEAF compute_max_request_data_column_sidecars
    mov     CONFIG_MAX_REQUEST_BLOCKS_DENEB(%rdi), %rax
    mov     $NUMBER_OF_COLUMNS, %ecx
    mul     %rcx
    jc      9f
    mov     %rax, (%rsi)
    RETURN_OK
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END compute_max_request_data_column_sidecars
.endif

/*
 * L0: rax = next_fork_epoch after epoch rdi, config rsi: the least fork epoch of altair up to
 * this fork above it, and from fulu on each BLOB_SCHEDULE epoch from FULU_FORK_EPOCH on; else
 * FAR_FUTURE_EPOCH. A leaf; uses rcx, rdx, r8, r9.
 */
LOCAL_FUNCTION lantern_next_fork_epoch
    UNWIND_END_PROLOGUE
    mov     $-1, %rax
    mov     $(16 * FORK), %ecx
1:  test    %rcx, %rcx
    jz      2f
    mov     (%rsi,%rcx), %rdx
    cmp     %rdi, %rdx
    jbe     3f
    cmp     %rax, %rdx
    cmovb   %rdx, %rax
3:  sub     $16, %rcx
    jmp     1b
2:
.if FORK >= FORK_FULU
    mov     CONFIG_FULU_FORK_EPOCH(%rsi), %r8
    mov     CONFIG_BLOB_SCHEDULE_COUNT(%rsi), %rcx
    mov     $CONFIG_BLOB_SCHEDULE_MAX, %edx
    cmp     %rdx, %rcx
    cmova   %rdx, %rcx
    lea     CONFIG_BLOB_SCHEDULE(%rsi), %r9
4:  test    %rcx, %rcx
    jz      5f
    mov     (%r9), %rdx
    add     $16, %r9
    dec     %rcx
    cmp     %r8, %rdx                       # a BPO fork: from FULU_FORK_EPOCH on
    jb      4b
    cmp     %rdi, %rdx
    jbe     4b
    cmp     %rax, %rdx
    cmovb   %rdx, %rax
    jmp     4b
5:
.endif
    ret
END_FUNCTION lantern_next_fork_epoch

/* rbx genesis_validators_root, rbp current_epoch, r12 config, r13 scratch, r14 out. Locals: L an epoch. */
SPEC_FUNCTION compute_enr_fork_id
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    call    lantern_compute_fork_digest     # fork_digest: the same five arguments
    test    %rax, %rax
    jnz     9f
    mov     (%rbp), %rdi
    mov     %r12, %rsi
    call    lantern_next_fork_epoch
    mov     %rax, 8(%r14)                   # next_fork_epoch
    cmp     $-1, %rax                       # next_fork_version: at next_fork_epoch, or at current_epoch
    cmove   (%rbp), %rax
    mov     %rax, L(%rsp)
    lea     L(%rsp), %rdi
    mov     %r12, %rsi
    lea     4(%r14), %rdx
    call    lantern_compute_fork_version
9:  LEAVE 16
SPEC_END compute_enr_fork_id

.if FORK >= FORK_FULU
/* rbx genesis_validators_root, r12 config, r13 scratch, r14 out. Locals: L next_fork_epoch. */
SPEC_FUNCTION compute_next_fork_digest
    ENTER 16
    mov     %rdi, %rbx
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     (%rsi), %rdi
    mov     %r12, %rsi
    call    lantern_next_fork_epoch
    cmp     $-1, %rax
    je      1f
    mov     %rax, L(%rsp)
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    call    lantern_compute_fork_digest
    LEAVE 16
1:  movl    $0, (%r14)
    xor     %eax, %eax
    LEAVE 16
SPEC_END compute_next_fork_digest
.endif

/*
 * rbx topic, rbp data, r12 config, r13 scratch, r14 out, r15 prefix length, S7 where the
 * message starts in scratch, S8 its length, S9 the domain offset in the config.
 * Scratch: its size, a ByteList header for SHA-256 at +8, then from +32 the prefix and the
 * message, contiguous; a ByteList header for snappy_uncompress just before the message.
 * Locals: L the uncompressed length, L+8 the digest.
 */
SPEC_FUNCTION compute_message_id
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
.if FORK == FORK_PHASE0
    mov     $4, %r15d                       # the domain
.else
    mov     16(%rbx), %r15                  # the domain, uint_to_bytes(len(topic)), the topic
    add     $12, %r15
    jc      8f
.endif
    movq    $CONFIG_MESSAGE_DOMAIN_INVALID_SNAPPY, S9(%rsp)
    mov     16(%rbp), %rax                  # the message: the data, unless it decompresses
    mov     %rax, S8(%rsp)
    mov     %rbp, %rdi
    lea     L(%rsp), %rsi
    CALL_GLOBAL snappy_get_uncompressed_length
    test    %rax, %rax
    jnz     1f
    mov     L(%rsp), %rax
    cmp     CONFIG_MAX_PAYLOAD_SIZE(%r12), %rax
    ja      1f
    cmp     S8(%rsp), %rax                  # the larger of the two, for the room check
    jbe     0f
    mov     %rax, S8(%rsp)
0:  movq    $CONFIG_MESSAGE_DOMAIN_VALID_SNAPPY, S9(%rsp)
1:  mov     $24, %eax                       # the message starts at scratch + 32 + max(prefix, 24)
    cmp     %rax, %r15
    cmova   %r15, %rax
    add     $32, %rax
    mov     16(%rbx), %rcx                  # room: 64 + the topic + the larger length
    add     $64, %rcx
    jc      8f
    add     S8(%rsp), %rcx
    jc      8f
    cmp     %rcx, (%r13)
    jb      8f
    lea     (%r13,%rax), %rcx
    mov     %rcx, S7(%rsp)
    cmpq    $CONFIG_MESSAGE_DOMAIN_VALID_SNAPPY, S9(%rsp)
    jne     2f
    lea     -24(%rcx), %rsi                 # uncompress into a ByteList whose bytes start at S7
    mov     (%r13), %rdx
    sub     %rax, %rdx
    add     $24, %rdx
    mov     %rdx, (%rsi)
    mov     %rbp, %rdi
    CALL_GLOBAL snappy_uncompress
    mov     L(%rsp), %rcx
    mov     %rcx, S8(%rsp)
    test    %rax, %rax
    jz      3f
    movq    $CONFIG_MESSAGE_DOMAIN_INVALID_SNAPPY, S9(%rsp)   # not a valid block: the raw data
2:  mov     S7(%rsp), %rdi
    mov     8(%rbp), %rsi
    add     %rbp, %rsi
    mov     16(%rbp), %rdx
    mov     %rdx, S8(%rsp)
    call    lantern_copy
3:  mov     S7(%rsp), %rdi                  # the prefix, just before the message
    sub     %r15, %rdi
    mov     S9(%rsp), %rcx
    mov     (%r12,%rcx), %eax
    mov     %eax, (%rdi)
.if FORK > FORK_PHASE0
    mov     16(%rbx), %rdx
    mov     %rdx, 4(%rdi)
    add     $12, %rdi
    mov     8(%rbx), %rsi
    add     %rbx, %rsi
    call    lantern_copy
.endif
    lea     8(%r13), %rdi                   # sha256(prefix + message)
    mov     S7(%rsp), %rax
    sub     %r15, %rax
    sub     %rdi, %rax
    mov     %rax, 8(%rdi)
    mov     S8(%rsp), %rax
    add     %r15, %rax
    mov     %rax, 16(%rdi)
    lea     (L + 8)(%rsp), %rsi
    CALL_GLOBAL crypto_sha256
    mov     (L + 8)(%rsp), %rax             # its first 20 bytes
    mov     %rax, (%r14)
    mov     (L + 16)(%rsp), %rax
    mov     %rax, 8(%r14)
    mov     (L + 24)(%rsp), %eax
    mov     %eax, 16(%r14)
    xor     %eax, %eax
    LEAVE 48
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END compute_message_id
