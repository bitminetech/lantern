/*
 * Shuffling, seeds and proposer selection, ARM64. Requirements: docs/reference/helpers.md.
 */

/* L0: digest x2 = sha256 of the x1 bytes at x0; x1 is at most 96. */
LOCAL_FUNCTION sha256_short
    FRAME 128
    add     x9, sp, #16                     /* a ByteList: size, offset 24, count, then the bytes */
    add     x10, x1, #24
    str     x10, [x9]
    mov     x10, #24
    str     x10, [x9, #8]
    str     x1, [x9, #16]
    add     x10, x9, #24
    cbz     x1, 2f
1:  ldrb    w11, [x0], #1
    strb    w11, [x10], #1
    subs    x1, x1, #1
    b.ne    1b
2:  add     x0, sp, #16
    mov     x1, x2
    CALL_GLOBAL crypto_sha256
    mov     x0, #LANTERN_OK
    UNFRAME 128
END_FUNCTION sha256_short

/*
 * x19 index count, x20 seed, x21 scratch, x22 out, x23 entries, x24 round, x25 pivot,
 * x26 buckets, x27 bucket hashes. Locals: L the message (seed, round, bucket), L+40 the digest.
 */
SPEC_FUNCTION compute_shuffled_permutation
    ENTER 80
    ldr     x19, [x0]
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    cbz     x19, 8f                         /* the spec divides by index_count */
    add     x26, x19, #255
    lsr     x26, x26, #8                    /* buckets */
    lsl     x9, x26, #5
    add     x9, x9, #8
    ldr     x10, [x21]
    cmp     x10, x9
    b.lo    9f
    lsl     x9, x19, #3
    add     x9, x9, #LIST_FIXED
    ldr     x10, [x22, #LIST_SIZE]
    cmp     x10, x9
    b.lo    9f
    mov     x9, #LIST_FIXED
    str     x9, [x22, #LIST_OFFSET]
    str     x19, [x22, #LIST_COUNT]
    add     x23, x22, #LIST_FIXED
    mov     x9, #0                          /* indices = [0, 1, ..., index_count - 1] */
1:  str     x9, [x23, x9, lsl #3]
    add     x9, x9, #1
    cmp     x9, x19
    b.lo    1b
    add     x27, x21, #8
    add     x9, sp, #L                      /* the message starts with the seed */
    COPY32  x9, x20
    mov     x24, #0
2:  cmp     x24, #SHUFFLE_ROUND_COUNT
    b.hs    7f
    strb    w24, [sp, #(L + 32)]            /* round_bytes */
    add     x0, sp, #L                      /* pivot = bytes_to_uint64(sha256(seed + round_bytes)[0:8]) % index_count */
    mov     x1, #33
    add     x2, sp, #(L + 40)
    bl      sha256_short
    ldr     x9, [sp, #(L + 40)]
    udiv    x10, x9, x19
    msub    x25, x10, x19, x9
    mov     x28, #0                         /* the source of each bucket of positions */
3:  cmp     x28, x26
    b.hs    4f
    str     w28, [sp, #(L + 33)]            /* uint_to_bytes(Uint32(position_bucket)) */
    add     x0, sp, #L
    mov     x1, #37
    add     x2, x27, x28, lsl #5
    bl      sha256_short
    add     x28, x28, #1
    b       3b
4:  mov     x9, #0                          /* for i in range(index_count) */
5:  ldr     x10, [x23, x9, lsl #3]          /* indices[i] */
    add     x11, x25, x19
    sub     x11, x11, x10                   /* flip = (pivot + index_count - indices[i]) % index_count */
    cmp     x11, x19
    b.lo    6f
    sub     x11, x11, x19
6:  cmp     x10, x11
    csel    x12, x10, x11, hi               /* position = max(indices[i], flip) */
    lsr     x13, x12, #3                    /* source[(position % 256) // 8] of its bucket */
    ldrb    w13, [x27, x13]
    and     x12, x12, #7
    lsr     w13, w13, w12
    tst     w13, #1
    csel    x10, x11, x10, ne               /* indices[i] = flip if bit else indices[i] */
    str     x10, [x23, x9, lsl #3]
    add     x9, x9, #1
    cmp     x9, x19
    b.lo    5b
    add     x24, x24, #1
    b       2b
7:  mov     x0, #LANTERN_OK
    LEAVE 80
8:  mov     x0, #LANTERN_INVALID_SHUFFLED_INDEX
    LEAVE 80
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
SPEC_END compute_shuffled_permutation

/* x19 index, x20 count pointer, x21 seed, x22 scratch, x23 out, x24 list. */
SPEC_FUNCTION compute_shuffled_index
    ENTER 16
    ldr     x19, [x0]
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x9, [x20]
    cmp     x19, x9                         /* assert index < index_count */
    b.hs    8f
    lsl     x10, x9, #3                     /* the permutation's list: L(index_count), at the end of scratch */
    add     x10, x10, #LIST_FIXED
    add     x11, x9, #255
    lsr     x11, x11, #8
    lsl     x11, x11, #5
    add     x11, x11, #8
    add     x11, x11, x10                   /* and the callee's 8 + 32 * buckets */
    ldr     x12, [x22]
    cmp     x12, x11
    b.lo    9f
    sub     x12, x12, x10
    add     x24, x22, x12
    str     x10, [x24]
    str     x12, [x22]
    mov     x0, x20
    mov     x1, x21
    mov     x2, x22
    mov     x3, x24
    bl      lantern_compute_shuffled_permutation
    cbnz    x0, 7f
    add     x9, x24, #LIST_FIXED
    ldr     x9, [x9, x19, lsl #3]
    str     x9, [x23]
    mov     x0, #LANTERN_OK
7:  LEAVE 16
8:  mov     x0, #LANTERN_INVALID_SHUFFLED_INDEX
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END compute_shuffled_index

/* Locals: sp+16 the message (domain type 4, epoch 8, mix 32), sp+64 the mix epoch, sp+72 out. */
SPEC_FUNCTION get_seed
    FRAME 64
    ldr     x9, [x1]
    MOVQ    x10, EPOCHS_PER_HISTORICAL_VECTOR - MIN_SEED_LOOKAHEAD - 1
    adds    x10, x9, x10                    /* epoch + EPOCHS_PER_HISTORICAL_VECTOR - MIN_SEED_LOOKAHEAD - 1 */
    b.cs    8f
    str     x10, [sp, #64]
    str     x3, [sp, #72]
    ldr     w10, [x2]
    str     w10, [sp, #16]                  /* domain_type */
    str     x9, [sp, #20]                   /* uint_to_bytes(epoch) */
    add     x1, sp, #64
    add     x2, sp, #28
    bl      lantern_get_randao_mix
    add     x0, sp, #16
    mov     x1, #44
    ldr     x2, [sp, #72]
    bl      sha256_short
    UNFRAME 64
8:  mov     x0, #LANTERN_INVALID_OVERFLOW
    UNFRAME 64
SPEC_END get_seed

/*
 * x19 state, x20 indices, x21 seed, x22 scratch, x23 out, x24 i, x25 total, x26 scratch size.
 * Locals: L i % total, L+8 total, L+16 shuffled, L+24 message (seed, i // 16, or i // 32
 * before electra), L+64 digest.
 */
SPEC_FUNCTION compute_proposer_index
    ENTER 96
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x25, [x20, #LIST_COUNT]
    cbz     x25, 8f                         /* assert len(indices) > 0 */
    str     x25, [sp, #(L + 8)]
    ldr     x26, [x22]
    add     x9, sp, #(L + 24)
    COPY32  x9, x21
    mov     x24, #0
1:  udiv    x9, x24, x25
    msub    x9, x9, x25, x24
    str     x9, [sp, #L]
    str     x26, [x22]
    add     x0, sp, #L                      /* compute_shuffled_index(i % total, total, seed) */
    add     x1, sp, #(L + 8)
    mov     x2, x21
    mov     x3, x22
    add     x4, sp, #(L + 16)
    bl      lantern_compute_shuffled_index
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 16)]
    add     x10, x20, #LIST_FIXED
    ldr     x27, [x10, x9, lsl #3]          /* candidate_index */
.if FORK >= FORK_ELECTRA
    lsr     x9, x24, #4                     /* random_bytes = sha256(seed + uint_to_bytes(i // 16)) */
    str     x9, [sp, #(L + 56)]
    add     x0, sp, #(L + 24)
    mov     x1, #40
    add     x2, sp, #(L + 64)
    bl      sha256_short
    and     x9, x24, #15
    lsl     x9, x9, #1
    add     x10, sp, #(L + 64)
    ldrh    w9, [x10, x9]                   /* random_value */
    PART    x10, x11, x19, BeaconState_validators
    add     x10, x10, x27, lsl #7
    ldr     x10, [x10, #Validator_effective_balance]
    mov     x11, #0xffff
    umulh   x12, x10, x11
    cbnz    x12, 6f
    mul     x10, x10, x11                   /* effective_balance * MAX_RANDOM_VALUE */
    MOVQ    x11, MAX_EFFECTIVE_BALANCE_ELECTRA
    mul     x11, x11, x9                    /* MAX_EFFECTIVE_BALANCE_ELECTRA * random_value fits */
    cmp     x10, x11
    b.hs    2f
.else
    lsr     x9, x24, #5                     /* sha256(seed + uint_to_bytes(i // 32)) */
    str     x9, [sp, #(L + 56)]
    add     x0, sp, #(L + 24)
    mov     x1, #40
    add     x2, sp, #(L + 64)
    bl      sha256_short
    and     x9, x24, #31
    add     x10, sp, #(L + 64)
    ldrb    w9, [x10, x9]                   /* random_byte */
    PART    x10, x11, x19, BeaconState_validators
    add     x10, x10, x27, lsl #7
    ldr     x10, [x10, #Validator_effective_balance]
    mov     x11, #0xff
    umulh   x12, x10, x11
    cbnz    x12, 6f
    mul     x10, x10, x11                   /* effective_balance * MAX_RANDOM_BYTE */
    MOVQ    x11, MAX_EFFECTIVE_BALANCE
    mul     x11, x11, x9                    /* MAX_EFFECTIVE_BALANCE * random_byte fits */
    cmp     x10, x11
    b.hs    2f
.endif
    add     x24, x24, #1
    b       1b
2:  str     x27, [x23]
    mov     x0, #LANTERN_OK
7:  LEAVE 96
6:  mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 96
8:  mov     x0, #LANTERN_INVALID_NO_INDICES
    LEAVE 96
SPEC_END compute_proposer_index

.if FORK >= FORK_FULU
/*
 * x19 state, x20 seed, x21 indices, x22 scratch, x23 out, x24 slot index, x25 start slot,
 * x26 scratch size. Locals: L start slot, L+8 the message (seed, slot), L+48 the slot seed.
 */
SPEC_FUNCTION compute_proposer_indices
    ENTER 80
    mov     x19, x0
    mov     x20, x2
    mov     x21, x3
    mov     x22, x4
    mov     x23, x5
    mov     x0, x1
    add     x1, sp, #L
    bl      lantern_compute_start_slot_at_epoch
    cbnz    x0, 7f
    ldr     x25, [sp, #L]
    ldr     x26, [x22]
    add     x9, sp, #(L + 8)
    COPY32  x9, x20
    mov     x24, #0
1:  cmp     x24, #SLOTS_PER_EPOCH
    b.hs    2f
    adds    x9, x25, x24                    /* uint_to_bytes(start_slot + index) */
    b.cs    6f
    str     x9, [sp, #(L + 40)]
    add     x0, sp, #(L + 8)
    mov     x1, #40
    add     x2, sp, #(L + 48)
    bl      sha256_short
    str     x26, [x22]
    mov     x0, x19
    mov     x1, x21
    add     x2, sp, #(L + 48)
    mov     x3, x22
    add     x4, x23, x24, lsl #3
    bl      lantern_compute_proposer_index
    cbnz    x0, 7f
    add     x24, x24, #1
    b       1b
2:  mov     x0, #LANTERN_OK
7:  LEAVE 80
6:  mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 80
SPEC_END compute_proposer_indices
.endif

.if FORK >= FORK_FULU
/*
 * x19 state, x20 epoch, x21 scratch, x22 out, x23 validator count, x24 scratch size, x25 active list.
 * Locals: L domain type, L+8 seed.
 */
SPEC_FUNCTION get_beacon_proposer_indices
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    NEED_SCRATCH x21, x19, 2, 9f
    LDQ     x23, x19, BeaconState_validators + 8
    ldr     x24, [x21]
    SCRATCH_LIST x25, x21, x24, 0, x23
    mov     x0, x19
    mov     x1, x20
    mov     x2, x25
    bl      lantern_get_active_validator_indices
    cbnz    x0, 7f
    mov     w9, #DOMAIN_BEACON_PROPOSER
    str     w9, [sp, #L]
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #L
    add     x3, sp, #(L + 8)
    bl      lantern_get_seed
    cbnz    x0, 7f
    SCRATCH_GIVE x21, x24, 1, x23
    mov     x0, x19
    mov     x1, x20
    add     x2, sp, #(L + 8)
    mov     x3, x25
    mov     x4, x21
    mov     x5, x22
    bl      lantern_compute_proposer_indices
7:  LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END get_beacon_proposer_indices
.endif

/* ---------------------------------------------------------------- Domains and signing roots */

/* Locals: sp+16 the ForkData value: current_version (4), genesis_validators_root (32). */
SPEC_FUNCTION compute_fork_data_root
    FRAME 48
    ldr     w9, [x0]
    str     w9, [sp, #(16 + ForkData_current_version)]
    add     x9, sp, #(16 + ForkData_genesis_validators_root)
    COPY32  x9, x1
    add     x1, sp, #16                     /* hash_tree_root(ForkData(...)): scratch x2, out x3 */
    ADDRESS x0, lantern_type_ForkData
    CALL_GLOBAL ssz_hash_tree_root
    UNFRAME 48
SPEC_END compute_fork_data_root

/* Locals: sp+16 domain type pointer, sp+24 out, sp+32 the fork data root. */
SPEC_FUNCTION compute_domain
    FRAME 48
    stp     x0, x4, [sp, #16]
    mov     x0, x1
    mov     x1, x2
    mov     x2, x3
    add     x3, sp, #32
    bl      lantern_compute_fork_data_root
    cbnz    x0, 1f
    ldp     x9, x10, [sp, #16]
    ldr     w11, [x9]
    str     w11, [x10]                      /* domain_type + fork_data_root[:28] */
    add     x11, sp, #32
    ldr     x12, [x11]
    str     x12, [x10, #4]
    ldr     x12, [x11, #8]
    str     x12, [x10, #12]
    ldr     x12, [x11, #16]
    str     x12, [x10, #20]
    ldr     w12, [x11, #24]
    str     w12, [x10, #28]
    mov     x0, #LANTERN_OK
1:  UNFRAME 48
SPEC_END compute_domain

SPEC_FUNCTION get_domain
    FRAME 0
    ldr     x9, [x2]
    LDQ     x10, x0, BeaconState_fork + Fork_epoch
    ADDQ    x11, x0, BeaconState_fork + Fork_previous_version
    ADDQ    x12, x0, BeaconState_fork + Fork_current_version
    cmp     x9, x10
    csel    x11, x11, x12, lo               /* previous_version before the fork epoch */
    mov     x2, x1
    mov     x1, x11
    mov     x9, x0
    mov     x0, x2
    ADDQ    x2, x9, BeaconState_genesis_validators_root
    bl      lantern_compute_domain
    UNFRAME 0
SPEC_END get_domain

/* Locals: sp+16 the SigningData value (object_root, domain), sp+80 domain, sp+88 scratch, sp+96 out. */
SPEC_FUNCTION compute_signing_root
    FRAME 96
    str     x2, [sp, #80]
    stp     x3, x4, [sp, #88]
    mov     x2, x3
    add     x3, sp, #(16 + SigningData_object_root)
    CALL_GLOBAL ssz_hash_tree_root          /* hash_tree_root(ssz_object) */
    cbnz    x0, 1f
    ldr     x9, [sp, #80]
    add     x10, sp, #(16 + SigningData_domain)
    COPY32  x10, x9
    ADDRESS x0, lantern_type_SigningData
    add     x1, sp, #16
    ldp     x2, x3, [sp, #88]
    CALL_GLOBAL ssz_hash_tree_root
1:  UNFRAME 96
SPEC_END compute_signing_root
