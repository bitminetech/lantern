/*
 * Shuffling, seeds and proposer selection, RISC-V. Requirements: docs/reference/helpers.md.
 */

/* L0: digest a2 = sha256 of the a1 bytes at a0; a1 is at most 96. */
LOCAL_FUNCTION lantern_sha256_short
    FRAME 128
    addi    t0, a1, 24                      # a ByteList: size, offset 24, count, then the bytes
    sd      t0, 0(sp)
    li      t0, 24
    sd      t0, 8(sp)
    sd      a1, 16(sp)
    addi    t1, sp, 24
    beqz    a1, 2f
1:  lbu     t2, 0(a0)
    addi    a0, a0, 1
    sb      t2, 0(t1)
    addi    t1, t1, 1
    addi    a1, a1, -1
    bnez    a1, 1b
2:  mv      a0, sp
    mv      a1, a2
    CALL_GLOBAL crypto_sha256
    li      a0, LANTERN_OK
    UNFRAME 128
END_FUNCTION lantern_sha256_short

/*
 * s1 index count, s2 seed, s3 scratch, s4 out, s5 entries, s6 round, s7 pivot,
 * s8 buckets, s9 bucket hashes, s10 bucket. Locals: L the message (seed, round, bucket), L+40 the digest.
 */
SPEC_FUNCTION compute_shuffled_permutation
    ENTER 80
    ld      s1, 0(a0)
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    beqz    s1, 8f                          # the spec divides by index_count
    addi    s8, s1, 255
    srli    s8, s8, 8                       # buckets
    slli    t0, s8, 5
    addi    t0, t0, 8
    ld      t1, 0(s3)
    bltu    t1, t0, 9f
    slli    t0, s1, 3
    addi    t0, t0, LIST_FIXED
    ld      t1, LIST_SIZE(s4)
    bltu    t1, t0, 9f
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s4)
    sd      s1, LIST_COUNT(s4)
    addi    s5, s4, LIST_FIXED
    li      t0, 0                           # indices = [0, 1, ..., index_count - 1]
    mv      t1, s5
1:  sd      t0, 0(t1)
    addi    t1, t1, 8
    addi    t0, t0, 1
    bltu    t0, s1, 1b
    addi    s9, s3, 8
    addi    t0, sp, L                       # the message starts with the seed
    COPY32  t0, s2
    li      s6, 0
2:  li      t0, SHUFFLE_ROUND_COUNT
    bgeu    s6, t0, 7f
    sb      s6, (L + 32)(sp)                # round_bytes
    addi    a0, sp, L                       # pivot = bytes_to_uint64(sha256(seed + round_bytes)[0:8]) % index_count
    li      a1, 33
    addi    a2, sp, (L + 40)
    call    lantern_sha256_short
    ld      t0, (L + 40)(sp)
    remu    s7, t0, s1
    li      s10, 0                          # the source of each bucket of positions
3:  bgeu    s10, s8, 4f
    sb      s10, (L + 33)(sp)               # uint_to_bytes(Uint32(position_bucket))
    srli    t0, s10, 8
    sb      t0, (L + 34)(sp)
    srli    t0, s10, 16
    sb      t0, (L + 35)(sp)
    srli    t0, s10, 24
    sb      t0, (L + 36)(sp)
    addi    a0, sp, L
    li      a1, 37
    slli    a2, s10, 5
    add     a2, s9, a2
    call    lantern_sha256_short
    addi    s10, s10, 1
    j       3b
4:  li      t0, 0                           # for i in range(index_count)
    mv      t6, s5
5:  ld      t1, 0(t6)                       # indices[i]
    add     t2, s7, s1
    sub     t2, t2, t1                      # flip = (pivot + index_count - indices[i]) % index_count
    bltu    t2, s1, 6f
    sub     t2, t2, s1
6:  mv      t3, t1                          # position = max(indices[i], flip)
    bgtu    t1, t2, 61f
    mv      t3, t2
61: srli    t4, t3, 3                       # source[(position % 256) // 8] of its bucket
    add     t4, s9, t4
    lbu     t4, 0(t4)
    andi    t3, t3, 7
    srl     t4, t4, t3
    andi    t4, t4, 1
    beqz    t4, 62f
    mv      t1, t2                          # indices[i] = flip if bit else indices[i]
62: sd      t1, 0(t6)
    addi    t6, t6, 8
    addi    t0, t0, 1
    bltu    t0, s1, 5b
    addi    s6, s6, 1
    j       2b
7:  li      a0, LANTERN_OK
    LEAVE 80
8:  li      a0, LANTERN_INVALID_SHUFFLED_INDEX
    LEAVE 80
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
SPEC_END compute_shuffled_permutation

/*
 * s1 index, s2 index count, s3 round, s4 flip, s5 out, s6 position.
 * Locals: L the message (seed, round, bucket), L+40 the digest.
 */
SPEC_FUNCTION compute_shuffled_index
    ENTER 80
    ld      s1, 0(a0)
    ld      s2, 0(a1)
    mv      s5, a4
    bgeu    s1, s2, 8f                      # assert index < index_count
    addi    t0, sp, L                       # the message starts with the seed
    COPY32  t0, a2
    li      s3, 0
1:  li      t0, SHUFFLE_ROUND_COUNT
    bgeu    s3, t0, 3f
    sb      s3, (L + 32)(sp)                # round_bytes
    addi    a0, sp, L                       # pivot = bytes_to_uint64(sha256(seed + round_bytes)[0:8]) % index_count
    li      a1, 33
    addi    a2, sp, (L + 40)
    call    lantern_sha256_short
    ld      t0, (L + 40)(sp)
    remu    t0, t0, s2
    add     s4, t0, s2
    sub     s4, s4, s1                      # flip = (pivot + index_count - index) % index_count
    bltu    s4, s2, 2f
    sub     s4, s4, s2
2:  mv      s6, s1                          # position = max(index, flip)
    bgtu    s1, s4, 21f
    mv      s6, s4
21: srli    t0, s6, 8                       # uint_to_bytes(uint32(position // 256))
    sb      t0, (L + 33)(sp)
    srli    t1, t0, 8
    sb      t1, (L + 34)(sp)
    srli    t1, t0, 16
    sb      t1, (L + 35)(sp)
    srli    t1, t0, 24
    sb      t1, (L + 36)(sp)
    addi    a0, sp, L                       # source = sha256(seed + round_bytes + position_bytes)
    li      a1, 37
    addi    a2, sp, (L + 40)
    call    lantern_sha256_short
    srli    t0, s6, 3                       # source[(position % 256) // 8]
    andi    t0, t0, 31
    add     t0, sp, t0
    lbu     t0, (L + 40)(t0)
    andi    t1, s6, 7
    srl     t0, t0, t1
    andi    t0, t0, 1
    beqz    t0, 22f
    mv      s1, s4                          # index = flip if bit else index
22: addi    s3, s3, 1
    j       1b
3:  sd      s1, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 80
8:  li      a0, LANTERN_INVALID_SHUFFLED_INDEX
    LEAVE 80
SPEC_END compute_shuffled_index

/*
 * Locals: sp+0 the message (domain type 4, epoch 8, mix 32), sp+48 the mix epoch, sp+56 out,
 * sp+64 the mix. The message's epoch and mix are 4-aligned, so they are written a word at a time.
 */
SPEC_FUNCTION get_seed
    FRAME 96
    ld      t0, 0(a1)
    li      t1, EPOCHS_PER_HISTORICAL_VECTOR - MIN_SEED_LOOKAHEAD - 1
    add     t1, t0, t1                      # epoch + EPOCHS_PER_HISTORICAL_VECTOR - MIN_SEED_LOOKAHEAD - 1
    bltu    t1, t0, 8f
    sd      t1, 48(sp)
    sd      a3, 56(sp)
    lw      t1, 0(a2)
    sw      t1, 0(sp)                       # domain_type
    sw      t0, 4(sp)                       # uint_to_bytes(epoch)
    srli    t0, t0, 32
    sw      t0, 8(sp)
    addi    a1, sp, 48
    addi    a2, sp, 64
    call    lantern_get_randao_mix
    .irp k, 0, 4, 8, 12, 16, 20, 24, 28
    lw      t0, (64 + \k)(sp)
    sw      t0, (12 + \k)(sp)
    .endr
    mv      a0, sp
    li      a1, 44
    ld      a2, 56(sp)
    call    lantern_sha256_short
    UNFRAME 96
8:  li      a0, LANTERN_INVALID_OVERFLOW
    UNFRAME 96
SPEC_END get_seed

/*
 * s1 state, s2 indices, s3 seed, s4 scratch, s5 out, s6 i, s7 total, s8 scratch size, s9 candidate,
 * s10 the index. Locals: L the position, L+8 total, L+16 the flip, L+24 message (seed, i // 16),
 * L+64 digest, L+96 the shuffle's message (seed, round, position // 256), L+136 its digest, L+168
 * the pivot of each round, L+888 the round. compute_shuffled_index inline: the pivots of the seed
 * once, then for each candidate one digest a round; the random bytes once for each 16 candidates
 * (32 before electra). The same values as the spec's steps.
 */
SPEC_FUNCTION compute_proposer_index
    ENTER 896
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      s7, LIST_COUNT(s2)
    beqz    s7, 8f                          # assert len(indices) > 0
    sd      s7, (L + 8)(sp)
    ld      s8, 0(s4)
    addi    t0, sp, (L + 24)
    COPY32  t0, s3
    addi    t0, sp, (L + 96)                # the pivots: bytes_to_uint64(sha256(seed + round_bytes)[0:8]) % total
    COPY32  t0, s3
    sd      zero, (L + 888)(sp)
0:  ld      t0, (L + 888)(sp)
    sb      t0, (L + 128)(sp)
    addi    a0, sp, (L + 96)
    li      a1, 33
    addi    a2, sp, (L + 136)
    call    lantern_sha256_short
    ld      t1, (L + 136)(sp)
    remu    t1, t1, s7
    ld      t0, (L + 888)(sp)
    slli    t2, t0, 3
    add     t2, sp, t2
    sd      t1, (L + 168)(t2)
    addi    t0, t0, 1
    sd      t0, (L + 888)(sp)
    li      t3, SHUFFLE_ROUND_COUNT
    bltu    t0, t3, 0b
    li      s6, 0
1:  remu    s10, s6, s7                     # compute_shuffled_index(i % total, total, seed)
    sd      zero, (L + 888)(sp)
11: ld      t0, (L + 888)(sp)
    slli    t2, t0, 3                       # flip = (pivot + total - index) % total
    add     t2, sp, t2
    ld      t1, (L + 168)(t2)
    add     t1, t1, s7
    sub     t1, t1, s10
    bltu    t1, s7, 12f
    sub     t1, t1, s7
12: sd      t1, (L + 16)(sp)
    mv      t2, t1                          # position = max(index, flip)
    bgeu    t1, s10, 121f
    mv      t2, s10
121: sd     t2, L(sp)
    sb      t0, (L + 128)(sp)
    srli    t3, t2, 8                       # uint_to_bytes(uint32(position // 256))
    sb      t3, (L + 129)(sp)
    srli    t4, t3, 8
    sb      t4, (L + 130)(sp)
    srli    t4, t3, 16
    sb      t4, (L + 131)(sp)
    srli    t4, t3, 24
    sb      t4, (L + 132)(sp)
    addi    a0, sp, (L + 96)                # source = sha256(seed + round_bytes + position_bytes)
    li      a1, 37
    addi    a2, sp, (L + 136)
    call    lantern_sha256_short
    ld      t2, L(sp)
    srli    t0, t2, 3                       # source[(position % 256) // 8]
    andi    t0, t0, 31
    add     t0, sp, t0
    lbu     t0, (L + 136)(t0)
    andi    t1, t2, 7
    srl     t0, t0, t1
    andi    t0, t0, 1
    beqz    t0, 13f
    ld      s10, (L + 16)(sp)               # index = flip if bit else index
13: ld      t0, (L + 888)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 888)(sp)
    li      t3, SHUFFLE_ROUND_COUNT
    bltu    t0, t3, 11b
    slli    t0, s10, 3
    add     t0, s2, t0
    ld      s9, LIST_FIXED(t0)              # candidate_index
.if FORK >= FORK_ELECTRA
    andi    t0, s6, 15                      # random_bytes = sha256(seed + uint_to_bytes(i // 16)), new each 16
    bnez    t0, 14f
    srli    t0, s6, 4
    sd      t0, (L + 56)(sp)
    addi    a0, sp, (L + 24)
    li      a1, 40
    addi    a2, sp, (L + 64)
    call    lantern_sha256_short
14: andi    t0, s6, 15
    slli    t0, t0, 1
    add     t0, sp, t0
    lhu     t0, (L + 64)(t0)                # random_value
    PART    t1, t2, s1, BeaconState_validators
    slli    t2, s9, 7
    add     t1, t1, t2
    ld      t1, Validator_effective_balance(t1)
    li      t2, 0xffff
    mulhu   t3, t1, t2
    bnez    t3, 6f
    mul     t1, t1, t2                      # effective_balance * MAX_RANDOM_VALUE
    li      t2, MAX_EFFECTIVE_BALANCE_ELECTRA
    mul     t2, t2, t0                      # MAX_EFFECTIVE_BALANCE_ELECTRA * random_value fits
.else
    andi    t0, s6, 31                      # sha256(seed + uint_to_bytes(i // 32)), new each 32
    bnez    t0, 15f
    srli    t0, s6, 5
    sd      t0, (L + 56)(sp)
    addi    a0, sp, (L + 24)
    li      a1, 40
    addi    a2, sp, (L + 64)
    call    lantern_sha256_short
15: andi    t0, s6, 31
    add     t0, sp, t0
    lbu     t0, (L + 64)(t0)                # random_byte
    PART    t1, t2, s1, BeaconState_validators
    slli    t2, s9, 7
    add     t1, t1, t2
    ld      t1, Validator_effective_balance(t1)
    li      t2, 0xff
    mulhu   t3, t1, t2
    bnez    t3, 6f
    mul     t1, t1, t2                      # effective_balance * MAX_RANDOM_BYTE
    li      t2, MAX_EFFECTIVE_BALANCE
    mul     t2, t2, t0                      # MAX_EFFECTIVE_BALANCE * random_byte fits
.endif
    bgeu    t1, t2, 2f
    addi    s6, s6, 1
    j       1b
2:  sd      s9, 0(s5)
    li      a0, LANTERN_OK
7:  LEAVE 896
6:  li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 896
8:  li      a0, LANTERN_INVALID_NO_INDICES
    LEAVE 896
SPEC_END compute_proposer_index

/* Every fork: fulu's spec function, and lantern_node_proposers before fulu (node.md). */
/*
 * s1 state, s2 seed, s3 indices, s4 scratch, s5 out, s6 slot index, s7 start slot,
 * s8 scratch size. Locals: L start slot, L+8 the message (seed, slot), L+48 the slot seed.
 */
SPEC_FUNCTION compute_proposer_indices
    ENTER 80
    mv      s1, a0
    mv      s2, a2
    mv      s3, a3
    mv      s4, a4
    mv      s5, a5
    mv      a0, a1
    addi    a1, sp, L
    call    lantern_compute_start_slot_at_epoch
    bnez    a0, 7f
    ld      s7, L(sp)
    ld      s8, 0(s4)
    addi    t0, sp, (L + 8)
    COPY32  t0, s2
    li      s6, 0
1:  li      t0, SLOTS_PER_EPOCH
    bgeu    s6, t0, 2f
    add     t0, s7, s6                      # uint_to_bytes(start_slot + index)
    bltu    t0, s7, 6f
    sd      t0, (L + 40)(sp)
    addi    a0, sp, (L + 8)
    li      a1, 40
    addi    a2, sp, (L + 48)
    call    lantern_sha256_short
    sd      s8, 0(s4)
    mv      a0, s1
    mv      a1, s3
    addi    a2, sp, (L + 48)
    mv      a3, s4
    slli    a4, s6, 3
    add     a4, s5, a4
    call    lantern_compute_proposer_index
    bnez    a0, 7f
    addi    s6, s6, 1
    j       1b
2:  li      a0, LANTERN_OK
7:  LEAVE 80
6:  li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 80
SPEC_END compute_proposer_indices

/* Every fork: fulu's spec function, and lantern_node_proposers before fulu (node.md). */
/*
 * s1 state, s2 epoch, s3 scratch, s4 out, s5 validator count, s6 scratch size, s7 active list.
 * Locals: L domain type, L+8 seed.
 */
SPEC_FUNCTION get_beacon_proposer_indices
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    NEED_SCRATCH s3, s1, 2, 9f
    LDQ     s5, s1, BeaconState_validators + 8
    ld      s6, 0(s3)
    SCRATCH_LIST s7, s3, s6, 0, s5
    mv      a0, s1
    mv      a1, s2
    mv      a2, s7
    call    lantern_get_active_validator_indices
    bnez    a0, 7f
    li      t0, DOMAIN_BEACON_PROPOSER
    sw      t0, L(sp)
    mv      a0, s1
    mv      a1, s2
    addi    a2, sp, L
    addi    a3, sp, (L + 8)
    call    lantern_get_seed
    bnez    a0, 7f
    SCRATCH_GIVE s3, s6, 1, s5
    mv      a0, s1
    mv      a1, s2
    addi    a2, sp, (L + 8)
    mv      a3, s7
    mv      a4, s3
    mv      a5, s4
    call    lantern_compute_proposer_indices
7:  LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END get_beacon_proposer_indices

/* ---------------------------------------------------------------- Domains and signing roots */

.if ForkData_current_version != 0 || ForkData_genesis_validators_root != 4
.error "lantern_compute_fork_data_root writes ForkData a word at a time"
.endif

/* Locals: sp+0 the ForkData value: current_version (4), genesis_validators_root (32). Both inputs are 4-aligned. */
SPEC_FUNCTION compute_fork_data_root
    FRAME 48
    lw      t0, 0(a0)
    sw      t0, 0(sp)
    .irp k, 0, 4, 8, 12, 16, 20, 24, 28
    lw      t0, \k(a1)
    sw      t0, (4 + \k)(sp)
    .endr
    mv      a1, sp                          # hash_tree_root(ForkData(...)): scratch a2, out a3
    ADDRESS a0, lantern_type_ForkData
    CALL_GLOBAL ssz_hash_tree_root
    UNFRAME 48
SPEC_END compute_fork_data_root

/* Locals: sp+0 domain type pointer, sp+8 out, sp+16 the fork data root. */
SPEC_FUNCTION compute_domain
    FRAME 48
    sd      a0, 0(sp)
    sd      a4, 8(sp)
    mv      a0, a1
    mv      a1, a2
    mv      a2, a3
    addi    a3, sp, 16
    call    lantern_compute_fork_data_root
    bnez    a0, 1f
    ld      t0, 0(sp)
    ld      t1, 8(sp)
    lw      t2, 0(t0)
    sw      t2, 0(t1)                       # domain_type + fork_data_root[:28]
    .irp k, 0, 4, 8, 12, 16, 20, 24
    lw      t2, (16 + \k)(sp)
    sw      t2, (4 + \k)(t1)
    .endr
    li      a0, LANTERN_OK
1:  UNFRAME 48
SPEC_END compute_domain

SPEC_FUNCTION get_domain
    FRAME 0
    ld      t0, 0(a2)
    LDQ     t1, a0, BeaconState_fork + Fork_epoch
    ADDQ    t2, a0, BeaconState_fork + Fork_previous_version
    bltu    t0, t1, 1f                      # previous_version before the fork epoch
    ADDQ    t2, a0, BeaconState_fork + Fork_current_version
1:  mv      t3, a0
    mv      a0, a1
    mv      a1, t2
    ADDQ    a2, t3, BeaconState_genesis_validators_root
    call    lantern_compute_domain
    UNFRAME 0
SPEC_END get_domain

/* Locals: sp+0 the SigningData value (object_root, domain), sp+64 domain, sp+72 scratch, sp+80 out. */
SPEC_FUNCTION compute_signing_root
    FRAME 96
    sd      a2, 64(sp)
    sd      a3, 72(sp)
    sd      a4, 80(sp)
    mv      a2, a3
    addi    a3, sp, SigningData_object_root
    CALL_GLOBAL ssz_hash_tree_root          # hash_tree_root(ssz_object)
    bnez    a0, 1f
    ld      t0, 64(sp)
    addi    t1, sp, SigningData_domain
    COPY32  t1, t0
    ADDRESS a0, lantern_type_SigningData
    mv      a1, sp
    ld      a2, 72(sp)
    ld      a3, 80(sp)
    CALL_GLOBAL ssz_hash_tree_root
1:  UNFRAME 96
SPEC_END compute_signing_root
