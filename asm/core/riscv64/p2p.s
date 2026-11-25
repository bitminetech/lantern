/*
 * P2p helpers, RISC-V: fork versions and digests, subnets, sizes, the ENR values and the
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
    ld      a3, 0(a0)
    li      a4, (16 * FORK)
1:  beqz    a4, 2f
    add     a5, a1, a4
    ld      a5, 0(a5)
    bgeu    a3, a5, 3f
    addi    a4, a4, -16
    j       1b
3:  addi    a4, a4, -8
2:  add     a5, a1, a4
    lw      a5, 0(a5)
    sw      a5, 0(a2)
    RETURN_OK
SPEC_END compute_fork_version

/*
 * s1 genesis_validators_root, s2 epoch, s3 config, s4 scratch, s5 out, s6 the base digest.
 * Locals: L the version, L+16 a root, L+48 the blob parameters.
 */
SPEC_FUNCTION compute_fork_digest
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      a0, s2                          # fork_version = compute_fork_version(epoch)
    mv      a1, s3
    addi    a2, sp, L
    call    lantern_compute_fork_version
    addi    a0, sp, L                       # compute_fork_data_root(fork_version, genesis_validators_root)
    mv      a1, s1
    mv      a2, s4
    addi    a3, sp, L + 16
    call    lantern_compute_fork_data_root
    bnez    a0, 9f
    lw      s6, (L + 16)(sp)
.if FORK >= FORK_FULU
    ld      t0, 0(s2)                       # from FULU_FORK_EPOCH on: xor with the blob parameters' hash
    LDQ     t1, s3, CONFIG_FULU_FORK_EPOCH
    bltu    t0, t1, 1f
    mv      a0, s2
    mv      a1, s3
    addi    a2, sp, L + 48                  # (epoch, max_blobs_per_block): the 16 bytes the spec hashes
    call    lantern_get_blob_parameters
    addi    a0, sp, L + 48
    li      a1, 16
    addi    a2, sp, L + 16
    call    lantern_sha256_short
    lw      t0, (L + 16)(sp)
    xor     s6, s6, t0
1:
.endif
    sw      s6, 0(s5)
    li      a0, LANTERN_OK
9:  LEAVE 64
SPEC_END compute_fork_digest

SPEC_LEAF compute_attestation_subnet_prefix_bits
    LDQ     a2, a0, CONFIG_ATTESTATION_SUBNET_EXTRA_BITS
    addi    a3, a2, CEILLOG2_ATTESTATION_SUBNET_COUNT
    bltu    a3, a2, 9f
    sd      a3, 0(a1)
    RETURN_OK
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_attestation_subnet_prefix_bits

SPEC_LEAF compute_min_epochs_for_block_requests
    LDQ     a2, a0, CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY
    LDQ     a3, a0, CONFIG_CHURN_LIMIT_QUOTIENT
    srli    a3, a3, 1
    add     a3, a2, a3
    bltu    a3, a2, 9f
    sd      a3, 0(a1)
    RETURN_OK
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_min_epochs_for_block_requests

/* L0: a0 = 32 + a0 + a0 // 6, and a1 = 1 on overflow, else 0. Uses t0, t1. */
LOCAL_FUNCTION lantern_compressed_len
    UNWIND_END_PROLOGUE
    li      t0, 6
    divu    t0, a0, t0
    addi    t1, a0, 32
    li      a1, 1
    bltu    t1, a0, 1f
    add     a0, t1, t0
    sltu    a1, a0, t1
1:  ret
END_FUNCTION lantern_compressed_len

SPEC_FUNCTION max_compressed_len
    FRAME 16
    sd      a1, F(sp)
    ld      a0, 0(a0)
    call    lantern_compressed_len
    bnez    a1, 9f
    ld      a1, F(sp)
    sd      a0, 0(a1)
    li      a0, LANTERN_OK
    UNFRAME 16
9:  li      a0, LANTERN_INVALID_OVERFLOW
    UNFRAME 16
SPEC_END max_compressed_len

SPEC_FUNCTION max_message_size
    FRAME 16
    sd      a1, F(sp)
    LDQ     a0, a0, CONFIG_MAX_PAYLOAD_SIZE
    call    lantern_compressed_len                  # max_compressed_len(MAX_PAYLOAD_SIZE) + 1024
    bnez    a1, 9f
    addi    t0, a0, 1024
    bltu    t0, a0, 9f
    li      t1, 1024 * 1024
    bgeu    t0, t1, 1f
    mv      t0, t1
1:  ld      a1, F(sp)
    sd      t0, 0(a1)
    li      a0, LANTERN_OK
    UNFRAME 16
9:  li      a0, LANTERN_INVALID_OVERFLOW
    UNFRAME 16
SPEC_END max_message_size

/*
 * s1 node_id, s2 epoch, s3 index, s4 config, s5 scratch, s6 out, s7 prefix_bits,
 * s8 EPOCHS_PER_SUBNET_SUBSCRIPTION.
 * Locals: L prefix_bits, L+8 the period, L+16 the seed, L+48 node_id_prefix,
 * L+56 1 << prefix_bits, L+64 the shuffled prefix.
 */
SPEC_FUNCTION compute_subscribed_subnet
    ENTER 80
    mv      s1, a0
    ld      s2, 0(a1)
    ld      s3, 0(a2)
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    mv      a0, s4                          # prefix_bits = compute_attestation_subnet_prefix_bits()
    addi    a1, sp, L
    call    lantern_compute_attestation_subnet_prefix_bits
    bnez    a0, 7f
    ld      s7, L(sp)
    LDQ     s8, s4, CONFIG_EPOCHS_PER_SUBNET_SUBSCRIPTION
    beqz    s8, 9f                          # node_id % 0 raises
    li      t0, 0                           # node_offset = node_id % EPOCHS_PER_SUBNET_SUBSCRIPTION: 256 steps
    li      t1, 31                          # byte, from the most significant
1:  add     t2, s1, t1
    lbu     t2, 0(t2)
    li      t3, 8
2:  srli    t4, t0, 63                      # r = 2r + the next bit, less the modulus when it is at least it
    slli    t0, t0, 1
    srli    t5, t2, 7
    andi    t2, t2, 0x7f
    slli    t2, t2, 1
    or      t0, t0, t5
    bnez    t4, 3f
    bltu    t0, s8, 4f
3:  sub     t0, t0, s8
4:  addi    t3, t3, -1
    bnez    t3, 2b
    addi    t1, t1, -1
    bgez    t1, 1b
    add     t0, s2, t0                      # (epoch + node_offset) // EPOCHS_PER_SUBNET_SUBSCRIPTION
    bltu    t0, s2, 9f
    divu    t0, t0, s8
    sd      t0, (L + 8)(sp)
    addi    a0, sp, L + 8                   # permutation_seed = sha256(uint_to_bytes(...))
    li      a1, 8
    addi    a2, sp, L + 16
    call    lantern_sha256_short
    li      t0, 64                          # Uint64(1 << prefix_bits) raises
    bgeu    s7, t0, 9f
    li      t1, 0                           # node_id_prefix = node_id >> (NODE_ID_BITS - prefix_bits)
    beqz    s7, 5f
    ld      t1, 24(s1)
    sub     t2, t0, s7
    srl     t1, t1, t2
5:  sd      t1, (L + 48)(sp)
    li      t1, 1
    sll     t1, t1, s7
    sd      t1, (L + 56)(sp)
    addi    a0, sp, L + 48                  # compute_shuffled_index(node_id_prefix, 1 << prefix_bits, seed)
    addi    a1, sp, L + 56
    addi    a2, sp, L + 16
    mv      a3, s5
    addi    a4, sp, L + 64
    call    lantern_compute_shuffled_index
    bnez    a0, 7f
    ld      t0, (L + 64)(sp)                # (permutated_prefix + index) % ATTESTATION_SUBNET_COUNT
    add     t1, t0, s3
    bltu    t1, t0, 9f
    andi    t1, t1, ATTESTATION_SUBNET_COUNT - 1
    sd      t1, 0(s6)
    li      a0, LANTERN_OK
7:  LEAVE 80
9:  li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 80
SPEC_END compute_subscribed_subnet

/* s1 node_id, s2 epoch, s3 config, s4 scratch, s5 out, s6 index, s7 SUBNETS_PER_NODE. Locals: L the index. */
SPEC_FUNCTION compute_subscribed_subnets
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    LDQ     s7, s3, CONFIG_SUBNETS_PER_NODE
    ld      t0, 0(s5)                       # room for SUBNETS_PER_NODE entries
    li      t1, LIST_FIXED
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    srli    t0, t0, 3
    bltu    t0, s7, 8f
    sd      t1, 8(s5)
    li      s6, 0
1:  bgeu    s6, s7, 2f
    sd      s6, L(sp)
    mv      a0, s1
    mv      a1, s2
    addi    a2, sp, L
    mv      a3, s3
    mv      a4, s4
    slli    a5, s6, 3
    add     a5, a5, s5
    addi    a5, a5, LIST_FIXED
    call    lantern_compute_subscribed_subnet
    bnez    a0, 9f
    addi    s6, s6, 1
    j       1b
2:  sd      s7, 16(s5)
    li      a0, LANTERN_OK
9:  LEAVE 16
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END compute_subscribed_subnets

.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
SPEC_LEAF compute_max_request_blob_sidecars
    LDQ     a2, a0, CONFIG_MAX_REQUEST_BLOCKS_DENEB
.if FORK == FORK_ELECTRA
    LDQ     a3, a0, CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
.else
    LDQ     a3, a0, CONFIG_MAX_BLOBS_PER_BLOCK
.endif
    mulhu   a4, a2, a3
    bnez    a4, 9f
    mul     a2, a2, a3
    sd      a2, 0(a1)
    RETURN_OK
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_max_request_blob_sidecars
.endif

.if FORK >= FORK_FULU
SPEC_LEAF compute_max_request_data_column_sidecars
    LDQ     a2, a0, CONFIG_MAX_REQUEST_BLOCKS_DENEB
    li      a3, NUMBER_OF_COLUMNS
    mulhu   a4, a2, a3
    bnez    a4, 9f
    mul     a2, a2, a3
    sd      a2, 0(a1)
    RETURN_OK
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_max_request_data_column_sidecars
.endif

/*
 * L0: a0 = next_fork_epoch after epoch a0, config a1: the least fork epoch of altair up to this
 * fork above it, and from fulu on each BLOB_SCHEDULE epoch from FULU_FORK_EPOCH on; else
 * FAR_FUTURE_EPOCH. A leaf; uses a2-a5, t0, t1.
 */
LOCAL_FUNCTION lantern_next_fork_epoch
    UNWIND_END_PROLOGUE
    li      a2, -1
    li      a3, (16 * FORK)
1:  beqz    a3, 2f
    add     a4, a1, a3
    ld      a4, 0(a4)
    bgeu    a0, a4, 3f
    bgeu    a4, a2, 3f
    mv      a2, a4
3:  addi    a3, a3, -16
    j       1b
2:
.if FORK >= FORK_FULU
    LDQ     a5, a1, CONFIG_FULU_FORK_EPOCH
    LDQ     a3, a1, CONFIG_BLOB_SCHEDULE_COUNT
    li      t0, CONFIG_BLOB_SCHEDULE_MAX
    bleu    a3, t0, 4f
    mv      a3, t0
4:  addi    t1, a1, CONFIG_BLOB_SCHEDULE
5:  beqz    a3, 6f
    ld      a4, 0(t1)
    addi    t1, t1, 16
    addi    a3, a3, -1
    bltu    a4, a5, 5b                      # a BPO fork: from FULU_FORK_EPOCH on
    bgeu    a0, a4, 5b
    bgeu    a4, a2, 5b
    mv      a2, a4
    j       5b
6:
.endif
    mv      a0, a2
    ret
END_FUNCTION lantern_next_fork_epoch

/* s1 genesis_validators_root, s2 current_epoch, s3 config, s4 scratch, s5 out. Locals: L an epoch. */
SPEC_FUNCTION compute_enr_fork_id
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    call    lantern_compute_fork_digest     # fork_digest: the same five arguments
    bnez    a0, 9f
    ld      a0, 0(s2)
    mv      a1, s3
    call    lantern_next_fork_epoch
    sd      a0, 8(s5)                       # next_fork_epoch
    li      t0, -1                          # next_fork_version: at next_fork_epoch, or at current_epoch
    bne     a0, t0, 1f
    ld      a0, 0(s2)
1:  sd      a0, L(sp)
    addi    a0, sp, L
    mv      a1, s3
    addi    a2, s5, 4
    call    lantern_compute_fork_version
9:  LEAVE 16
SPEC_END compute_enr_fork_id

.if FORK >= FORK_FULU
/* s1 genesis_validators_root, s3 config, s4 scratch, s5 out. Locals: L next_fork_epoch. */
SPEC_FUNCTION compute_next_fork_digest
    ENTER 16
    mv      s1, a0
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      a0, 0(a1)
    mv      a1, s3
    call    lantern_next_fork_epoch
    li      t0, -1
    beq     a0, t0, 1f
    sd      a0, L(sp)
    mv      a0, s1
    addi    a1, sp, L
    mv      a2, s3
    mv      a3, s4
    mv      a4, s5
    call    lantern_compute_fork_digest
    LEAVE 16
1:  sw      zero, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 16
SPEC_END compute_next_fork_digest
.endif

/*
 * s1 topic, s2 data, s3 config, s4 scratch, s5 out, s6 prefix length, s7 where the message
 * starts in scratch, s8 its length, s9 the domain offset in the config.
 * Scratch: its size, a ByteList header for SHA-256 at +8, then from +32 the prefix and the
 * message, contiguous; a ByteList header for snappy_uncompress just before the message.
 * Locals: L the uncompressed length, L+8 the digest.
 */
SPEC_FUNCTION compute_message_id
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
.if FORK == FORK_PHASE0
    li      s6, 4                           # the domain
.else
    ld      t0, 16(s1)                      # the domain, uint_to_bytes(len(topic)), the topic
    addi    s6, t0, 12
    bltu    s6, t0, 8f
.endif
    li      s9, CONFIG_MESSAGE_DOMAIN_INVALID_SNAPPY
    ld      s8, 16(s2)                      # the message: the data, unless it decompresses
    mv      a0, s2
    addi    a1, sp, L
    CALL_GLOBAL snappy_get_uncompressed_length
    bnez    a0, 1f
    ld      t0, L(sp)
    LDQ     t1, s3, CONFIG_MAX_PAYLOAD_SIZE
    bltu    t1, t0, 1f
    bgeu    s8, t0, 0f                      # the larger of the two, for the room check
    mv      s8, t0
0:  li      s9, CONFIG_MESSAGE_DOMAIN_VALID_SNAPPY
1:  li      t0, 24                          # the message starts at scratch + 32 + max(prefix, 24)
    bgeu    t0, s6, 2f
    mv      t0, s6
2:  addi    t0, t0, 32
    ld      t1, 0(s4)                       # room: 64 + the topic + the larger length
    ld      t2, 16(s1)
    addi    t3, t2, 64
    bltu    t3, t2, 8f
    add     t2, t3, s8
    bltu    t2, t3, 8f
    bltu    t1, t2, 8f
    add     s7, s4, t0
    li      t2, CONFIG_MESSAGE_DOMAIN_VALID_SNAPPY
    bne     s9, t2, 3f
    addi    a1, s7, -24                     # uncompress into a ByteList whose bytes start at s7
    sub     t1, t1, t0
    addi    t1, t1, 24
    sd      t1, 0(a1)
    mv      a0, s2
    CALL_GLOBAL snappy_uncompress
    ld      s8, L(sp)
    beqz    a0, 4f
    li      s9, CONFIG_MESSAGE_DOMAIN_INVALID_SNAPPY    # not a valid block: the raw data
3:  mv      a0, s7
    ld      t0, 8(s2)
    add     a1, s2, t0
    ld      a2, 16(s2)
    mv      s8, a2
    call    lantern_copy
4:  sub     t0, s7, s6                      # the prefix, just before the message
    add     t1, s3, s9
    lw      t1, 0(t1)
    sb      t1, 0(t0)
    srli    t1, t1, 8
    sb      t1, 1(t0)
    srli    t1, t1, 8
    sb      t1, 2(t0)
    srli    t1, t1, 8
    sb      t1, 3(t0)
.if FORK > FORK_PHASE0
    ld      t1, 16(s1)                      # uint_to_bytes(len(topic)), a byte at a time
    li      t2, 8
5:  sb      t1, 4(t0)
    srli    t1, t1, 8
    addi    t0, t0, 1
    addi    t2, t2, -1
    bnez    t2, 5b
    sub     a0, s7, s6
    addi    a0, a0, 12
    ld      t0, 8(s1)
    add     a1, s1, t0
    ld      a2, 16(s1)
    call    lantern_copy
.endif
    addi    a0, s4, 8                       # sha256(prefix + message)
    sub     t0, s7, s6
    sub     t0, t0, a0
    sd      t0, 8(a0)
    add     t0, s6, s8
    sd      t0, 16(a0)
    addi    a1, sp, L + 8
    CALL_GLOBAL crypto_sha256
    mv      a0, s5                          # its first 20 bytes
    addi    a1, sp, L + 8
    li      a2, 20
    call    lantern_copy
    li      a0, LANTERN_OK
    LEAVE 48
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END compute_message_id
