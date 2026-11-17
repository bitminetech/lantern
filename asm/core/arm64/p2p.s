/*
 * P2p helpers, ARM64: fork versions and digests, subnets, sizes, the ENR values and the
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
    ldr     x3, [x0]
    mov     x4, #(16 * FORK)
1:  cbz     x4, 2f
    ldr     x5, [x1, x4]
    cmp     x3, x5
    b.hs    3f
    sub     x4, x4, #16
    b       1b
3:  sub     x4, x4, #8
2:  ldr     w5, [x1, x4]
    str     w5, [x2]
    RETURN_OK
SPEC_END compute_fork_version

/*
 * x19 genesis_validators_root, x20 epoch, x21 config, x22 scratch, x23 out, x24 the base digest.
 * Locals: L the version, L+16 a root, L+48 the blob parameters.
 */
SPEC_FUNCTION compute_fork_digest
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x0, x20                         /* fork_version = compute_fork_version(epoch) */
    mov     x1, x21
    add     x2, sp, #L
    bl      lantern_compute_fork_version
    add     x0, sp, #L                      /* compute_fork_data_root(fork_version, genesis_validators_root) */
    mov     x1, x19
    mov     x2, x22
    add     x3, sp, #(L + 16)
    bl      lantern_compute_fork_data_root
    cbnz    x0, 9f
    ldr     w24, [sp, #(L + 16)]
.if FORK >= FORK_FULU
    ldr     x9, [x20]                       /* from FULU_FORK_EPOCH on: xor with the blob parameters' hash */
    LDQ     x10, x21, CONFIG_FULU_FORK_EPOCH
    cmp     x9, x10
    b.lo    1f
    mov     x0, x20
    mov     x1, x21
    add     x2, sp, #(L + 48)               /* (epoch, max_blobs_per_block): the 16 bytes the spec hashes */
    bl      lantern_get_blob_parameters
    add     x0, sp, #(L + 48)
    mov     x1, #16
    add     x2, sp, #(L + 16)
    bl      sha256_short
    ldr     w9, [sp, #(L + 16)]
    eor     w24, w24, w9
1:
.endif
    str     w24, [x23]
    mov     x0, #LANTERN_OK
9:  LEAVE 64
SPEC_END compute_fork_digest

SPEC_LEAF compute_attestation_subnet_prefix_bits
    LDQ     x2, x0, CONFIG_ATTESTATION_SUBNET_EXTRA_BITS
    adds    x2, x2, #CEILLOG2_ATTESTATION_SUBNET_COUNT
    b.cs    9f
    str     x2, [x1]
    RETURN_OK
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_attestation_subnet_prefix_bits

SPEC_LEAF compute_min_epochs_for_block_requests
    LDQ     x2, x0, CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY
    LDQ     x3, x0, CONFIG_CHURN_LIMIT_QUOTIENT
    adds    x2, x2, x3, lsr #1
    b.cs    9f
    str     x2, [x1]
    RETURN_OK
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_min_epochs_for_block_requests

/* L0: x0 = 32 + x0 + x0 // 6, with the carry flag set on overflow. Uses x9, x10. */
LOCAL_FUNCTION compressed_len
    UNWIND_END_PROLOGUE
    mov     x9, #6
    udiv    x9, x0, x9
    adds    x0, x0, #32
    b.cs    1f
    adds    x0, x0, x9
1:  ret
END_FUNCTION compressed_len

SPEC_FUNCTION max_compressed_len
    FRAME 16
    str     x1, [sp, #16]
    ldr     x0, [x0]
    bl      compressed_len
    b.cs    9f
    ldr     x1, [sp, #16]
    str     x0, [x1]
    mov     x0, #LANTERN_OK
    UNFRAME 16
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    UNFRAME 16
SPEC_END max_compressed_len

SPEC_FUNCTION max_message_size
    FRAME 16
    str     x1, [sp, #16]
    LDQ     x0, x0, CONFIG_MAX_PAYLOAD_SIZE
    bl      compressed_len                  /* max_compressed_len(MAX_PAYLOAD_SIZE) + 1024 */
    b.cs    9f
    adds    x0, x0, #1024
    b.cs    9f
    mov     x9, #(1024 * 1024)
    cmp     x0, x9
    csel    x0, x0, x9, hs
    ldr     x1, [sp, #16]
    str     x0, [x1]
    mov     x0, #LANTERN_OK
    UNFRAME 16
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    UNFRAME 16
SPEC_END max_message_size

/*
 * x19 node_id, x20 epoch, x21 index, x22 config, x23 scratch, x24 out, x25 prefix_bits,
 * x26 EPOCHS_PER_SUBNET_SUBSCRIPTION.
 * Locals: L prefix_bits, then uint_to_bytes, L+8 the period, L+16 the seed, L+48 node_id_prefix,
 * L+56 1 << prefix_bits, L+64 the shuffled prefix.
 */
SPEC_FUNCTION compute_subscribed_subnet
    ENTER 80
    mov     x19, x0
    ldr     x20, [x1]
    ldr     x21, [x2]
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    mov     x0, x22                         /* prefix_bits = compute_attestation_subnet_prefix_bits() */
    add     x1, sp, #L
    bl      lantern_compute_attestation_subnet_prefix_bits
    cbnz    x0, 7f
    ldr     x25, [sp, #L]
    LDQ     x26, x22, CONFIG_EPOCHS_PER_SUBNET_SUBSCRIPTION
    cbz     x26, 9f                         /* node_id % 0 raises */
    mov     x9, #0                          /* node_offset = node_id % EPOCHS_PER_SUBNET_SUBSCRIPTION: 256 steps */
    mov     x10, #31                        /* byte, from the most significant */
1:  ldrb    w11, [x19, x10]
    mov     x12, #8
2:  lsr     x13, x9, #63                    /* r = 2r + the next bit, less the modulus when it is at least it */
    lsl     x9, x9, #1
    lsr     x14, x11, #7
    and     x11, x11, #0x7f
    lsl     x11, x11, #1
    orr     x9, x9, x14
    cbnz    x13, 3f
    cmp     x9, x26
    b.lo    4f
3:  sub     x9, x9, x26
4:  subs    x12, x12, #1
    b.ne    2b
    subs    x10, x10, #1
    b.hs    1b
    adds    x9, x20, x9                     /* (epoch + node_offset) // EPOCHS_PER_SUBNET_SUBSCRIPTION */
    b.cs    9f
    udiv    x9, x9, x26
    str     x9, [sp, #(L + 8)]
    add     x0, sp, #(L + 8)                /* permutation_seed = sha256(uint_to_bytes(...)) */
    mov     x1, #8
    add     x2, sp, #(L + 16)
    bl      sha256_short
    cmp     x25, #64                        /* Uint64(1 << prefix_bits) raises */
    b.hs    9f
    mov     x9, #0                          /* node_id_prefix = node_id >> (NODE_ID_BITS - prefix_bits) */
    cbz     x25, 5f
    ldr     x9, [x19, #24]
    mov     x10, #64
    sub     x10, x10, x25
    lsr     x9, x9, x10
5:  str     x9, [sp, #(L + 48)]
    mov     x9, #1
    lsl     x9, x9, x25
    str     x9, [sp, #(L + 56)]
    add     x0, sp, #(L + 48)               /* compute_shuffled_index(node_id_prefix, 1 << prefix_bits, seed) */
    add     x1, sp, #(L + 56)
    add     x2, sp, #(L + 16)
    mov     x3, x23
    add     x4, sp, #(L + 64)
    bl      lantern_compute_shuffled_index
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 64)]             /* (permutated_prefix + index) % ATTESTATION_SUBNET_COUNT */
    adds    x9, x9, x21
    b.cs    9f
    and     x9, x9, #(ATTESTATION_SUBNET_COUNT - 1)
    str     x9, [x24]
    mov     x0, #LANTERN_OK
7:  LEAVE 80
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 80
SPEC_END compute_subscribed_subnet

/* x19 node_id, x20 epoch, x21 config, x22 scratch, x23 out, x24 index, x25 SUBNETS_PER_NODE. Locals: L the index. */
SPEC_FUNCTION compute_subscribed_subnets
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    LDQ     x25, x21, CONFIG_SUBNETS_PER_NODE
    ldr     x9, [x23]                       /* room for SUBNETS_PER_NODE entries */
    subs    x9, x9, #LIST_FIXED
    b.lo    8f
    lsr     x9, x9, #3
    cmp     x9, x25
    b.lo    8f
    mov     x9, #LIST_FIXED
    str     x9, [x23, #8]
    mov     x24, #0
1:  cmp     x24, x25
    b.hs    2f
    str     x24, [sp, #L]
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #L
    mov     x3, x21
    mov     x4, x22
    add     x5, x23, #LIST_FIXED
    add     x5, x5, x24, lsl #3
    bl      lantern_compute_subscribed_subnet
    cbnz    x0, 9f
    add     x24, x24, #1
    b       1b
2:  str     x25, [x23, #16]
    mov     x0, #LANTERN_OK
9:  LEAVE 16
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END compute_subscribed_subnets

.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
SPEC_LEAF compute_max_request_blob_sidecars
    LDQ     x2, x0, CONFIG_MAX_REQUEST_BLOCKS_DENEB
.if FORK == FORK_ELECTRA
    LDQ     x3, x0, CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
.else
    LDQ     x3, x0, CONFIG_MAX_BLOBS_PER_BLOCK
.endif
    umulh   x4, x2, x3
    cbnz    x4, 9f
    mul     x2, x2, x3
    str     x2, [x1]
    RETURN_OK
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_max_request_blob_sidecars
.endif

.if FORK >= FORK_FULU
SPEC_LEAF compute_max_request_data_column_sidecars
    LDQ     x2, x0, CONFIG_MAX_REQUEST_BLOCKS_DENEB
    MOVQ    x3, NUMBER_OF_COLUMNS
    umulh   x4, x2, x3
    cbnz    x4, 9f
    mul     x2, x2, x3
    str     x2, [x1]
    RETURN_OK
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_max_request_data_column_sidecars
.endif

/*
 * L0: x0 = next_fork_epoch after epoch x0, config x1: the least fork epoch of altair up to this
 * fork above it, and from fulu on each BLOB_SCHEDULE epoch from FULU_FORK_EPOCH on; else
 * FAR_FUTURE_EPOCH. A leaf; uses x2-x7.
 */
LOCAL_FUNCTION next_fork_epoch
    UNWIND_END_PROLOGUE
    mov     x2, #FAR_FUTURE_EPOCH
    mov     x3, #(16 * FORK)
1:  cbz     x3, 2f
    ldr     x4, [x1, x3]
    cmp     x4, x0
    b.ls    3f
    cmp     x4, x2
    csel    x2, x4, x2, lo
3:  sub     x3, x3, #16
    b       1b
2:
.if FORK >= FORK_FULU
    LDQ     x5, x1, CONFIG_FULU_FORK_EPOCH
    LDQ     x3, x1, CONFIG_BLOB_SCHEDULE_COUNT
    cmp     x3, #CONFIG_BLOB_SCHEDULE_MAX
    mov     x6, #CONFIG_BLOB_SCHEDULE_MAX
    csel    x3, x3, x6, ls
    add     x6, x1, #CONFIG_BLOB_SCHEDULE
4:  cbz     x3, 5f
    ldr     x4, [x6], #16
    sub     x3, x3, #1
    cmp     x4, x5                          /* a BPO fork: from FULU_FORK_EPOCH on */
    b.lo    4b
    cmp     x4, x0
    b.ls    4b
    cmp     x4, x2
    csel    x2, x4, x2, lo
    b       4b
5:
.endif
    mov     x0, x2
    ret
END_FUNCTION next_fork_epoch

/* x19 genesis_validators_root, x20 current_epoch, x21 config, x22 scratch, x23 out. Locals: L an epoch. */
SPEC_FUNCTION compute_enr_fork_id
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x4, x23                         /* fork_digest */
    bl      lantern_compute_fork_digest
    cbnz    x0, 9f
    ldr     x0, [x20]
    mov     x1, x21
    bl      next_fork_epoch
    str     x0, [x23, #8]                   /* next_fork_epoch */
    ldr     x9, [x20]                       /* next_fork_version: at next_fork_epoch, or at current_epoch */
    cmn     x0, #1
    csel    x0, x9, x0, eq
    str     x0, [sp, #L]
    add     x0, sp, #L
    mov     x1, x21
    add     x2, x23, #4
    bl      lantern_compute_fork_version
9:  LEAVE 16
SPEC_END compute_enr_fork_id

.if FORK >= FORK_FULU
/* x19 genesis_validators_root, x21 config, x22 scratch, x23 out. Locals: L next_fork_epoch. */
SPEC_FUNCTION compute_next_fork_digest
    ENTER 16
    mov     x19, x0
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x0, [x1]
    mov     x1, x21
    bl      next_fork_epoch
    cmn     x0, #1
    b.eq    1f
    str     x0, [sp, #L]
    mov     x0, x19
    add     x1, sp, #L
    mov     x2, x21
    mov     x3, x22
    mov     x4, x23
    bl      lantern_compute_fork_digest
    LEAVE 16
1:  str     wzr, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 16
SPEC_END compute_next_fork_digest
.endif

/*
 * x19 topic, x20 data, x21 config, x22 scratch, x23 out, x24 prefix length, x25 where the
 * message starts in scratch, x26 its length, x27 the domain offset in the config.
 * Scratch: its size, a ByteList header for SHA-256 at +8, then from +32 the prefix and the
 * message, contiguous; a ByteList header for snappy_uncompress just before the message.
 * Locals: L the uncompressed length, L+8 the digest.
 */
SPEC_FUNCTION compute_message_id
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
.if FORK == FORK_PHASE0
    mov     x24, #4                         /* the domain */
.else
    ldr     x24, [x19, #16]                 /* the domain, uint_to_bytes(len(topic)), the topic */
    adds    x24, x24, #12
    b.cs    8f
.endif
    mov     x27, #CONFIG_MESSAGE_DOMAIN_INVALID_SNAPPY
    ldr     x26, [x20, #16]                 /* the message: the data, unless it decompresses */
    mov     x0, x20
    add     x1, sp, #L
    CALL_GLOBAL snappy_get_uncompressed_length
    cbnz    x0, 1f
    ldr     x9, [sp, #L]
    LDQ     x10, x21, CONFIG_MAX_PAYLOAD_SIZE
    cmp     x9, x10
    b.hi    1f
    cmp     x9, x26
    csel    x26, x9, x26, hi                /* the larger of the two, for the room check */
    mov     x27, #CONFIG_MESSAGE_DOMAIN_VALID_SNAPPY
1:  cmp     x24, #24                        /* the message starts at scratch + 32 + max(prefix, 24) */
    mov     x9, #24
    csel    x9, x24, x9, hi
    add     x9, x9, #32
    ldr     x10, [x22]                      /* room: 64 + the topic + the larger length */
    ldr     x11, [x19, #16]
    adds    x11, x11, #64
    b.cs    8f
    adds    x11, x11, x26
    b.cs    8f
    cmp     x10, x11
    b.lo    8f
    add     x25, x22, x9
    cmp     x27, #CONFIG_MESSAGE_DOMAIN_VALID_SNAPPY
    b.ne    2f
    sub     x0, x25, #24                    /* uncompress into a ByteList whose bytes start at x25 */
    sub     x9, x10, x9
    add     x9, x9, #24
    str     x9, [x0]
    mov     x1, x0
    mov     x0, x20
    CALL_GLOBAL snappy_uncompress
    ldr     x26, [sp, #L]
    cbz     x0, 3f
    mov     x27, #CONFIG_MESSAGE_DOMAIN_INVALID_SNAPPY  /* not a valid block: the raw data */
2:  mov     x0, x25
    ldr     x9, [x20, #8]
    add     x1, x20, x9
    ldr     x2, [x20, #16]
    mov     x26, x2
    bl      lantern_copy
3:  sub     x9, x25, x24                    /* the prefix, just before the message */
    ldr     w10, [x21, x27]
    str     w10, [x9]
.if FORK > FORK_PHASE0
    ldr     x2, [x19, #16]
    str     x2, [x9, #4]
    add     x0, x9, #12
    ldr     x10, [x19, #8]
    add     x1, x19, x10
    bl      lantern_copy
.endif
    add     x0, x22, #8                     /* sha256(prefix + message) */
    sub     x9, x25, x24
    sub     x9, x9, x0
    str     x9, [x0, #8]
    add     x9, x24, x26
    str     x9, [x0, #16]
    add     x1, sp, #(L + 8)
    CALL_GLOBAL crypto_sha256
    ldp     x9, x10, [sp, #(L + 8)]         /* its first 20 bytes */
    ldr     w11, [sp, #(L + 24)]
    stp     x9, x10, [x23]
    str     w11, [x23, #16]
    mov     x0, #LANTERN_OK
    LEAVE 48
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END compute_message_id
