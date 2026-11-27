/*
 * Committees and attestations, RISC-V. Requirements: docs/reference/block-processing.md.
 */

.set CIDX_BYTES, LIST_FIXED + 8 * MAX_COMMITTEES_PER_SLOT     /* an IndexList of committee indices */
.set FLAGS_BYTES, LIST_FIXED + 8 * 3                            /* an IndexList of participation flags */
.set ATTEST_EXTRA, 2 * CIDX_BYTES + IndexedAttestation__fixed + 8

/* ---------------------------------------------------------------- Sorting */

/* Sift the entry at root down the heap of entries below end, at a0. Uses t0-t4. */
.macro SIFT root, end
97: slli    t0, \root, 1
    addi    t0, t0, 1                       # child = 2 * root + 1
    bgeu    t0, \end, 98f
    slli    t3, t0, 3
    add     t3, a0, t3
    ld      t2, 0(t3)
    addi    t1, t0, 1
    bgeu    t1, \end, 96f
    ld      t4, 8(t3)
    bleu    t4, t2, 96f                     # the larger child
    mv      t0, t1
    mv      t2, t4
96: slli    t3, \root, 3
    add     t3, a0, t3
    ld      t4, 0(t3)
    bgeu    t4, t2, 98f
    sd      t2, 0(t3)
    slli    t1, t0, 3
    add     t1, a0, t1
    sd      t4, 0(t1)
    mv      \root, t0
    j       97b
98:
.endm

/* Sort the a1 u64 entries at a0, ascending (heapsort). A leaf; uses a2-a4, t0-t4. */
LOCAL_FUNCTION lantern_sort_u64
    UNWIND_END_PROLOGUE
    li      t0, 2
    bltu    a1, t0, 9f
    srli    a2, a1, 1
1:  beqz    a2, 2f
    addi    a2, a2, -1
    mv      a3, a2
    SIFT    a3, a1
    j       1b
2:  mv      a4, a1
3:  addi    a4, a4, -1
    beqz    a4, 9f
    ld      t0, 0(a0)
    slli    t1, a4, 3
    add     t1, a0, t1
    ld      t2, 0(t1)
    sd      t2, 0(a0)
    sd      t0, 0(t1)
    li      a3, 0
    SIFT    a3, a4
    j       3b
9:  ret
END_FUNCTION lantern_sort_u64

/* ---------------------------------------------------------------- Committees */

.if FORK >= FORK_ELECTRA
SPEC_LEAF get_committee_indices
    li      a2, LIST_FIXED
    sd      a2, LIST_OFFSET(a1)
    addi    a2, a1, LIST_FIXED
    li      a3, 0                           # bit
    li      t0, MAX_COMMITTEES_PER_SLOT
1:  bgeu    a3, t0, 2f
    srli    a4, a3, 3
    add     a4, a0, a4
    lbu     a4, 0(a4)
    andi    a5, a3, 7
    srl     a4, a4, a5
    andi    a4, a4, 1
    beqz    a4, 3f
    sd      a3, 0(a2)
    addi    a2, a2, 8
3:  addi    a3, a3, 1
    j       1b
2:  addi    a3, a1, LIST_FIXED
    sub     a2, a2, a3
    srli    a2, a2, 3
    sd      a2, LIST_COUNT(a1)
    RETURN_OK
SPEC_END get_committee_indices
.endif

/*
 * The key of epoch a1 of state a0 at a2 (CommitteeEntry_seed onward): get_seed with
 * DOMAIN_BEACON_ATTESTER, the decision root, the genesis validators root. s1 state, s2 epoch,
 * s3 key. Locals: L epoch, L+8 domain type.
 */
LOCAL_FUNCTION lantern_committee_key
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    sd      s2, L(sp)
    li      t0, DOMAIN_BEACON_ATTESTER
    sw      t0, (L + 8)(sp)
    mv      a0, s1
    addi    a1, sp, L
    addi    a2, sp, (L + 8)
    mv      a3, s3
    call    lantern_get_seed
    bnez    a0, 7f
    sd      zero, 32(s3)                    # the decision root: the last slot of epoch E - 5
    sd      zero, 40(s3)
    sd      zero, 48(s3)
    sd      zero, 56(s3)
    li      t0, 0
    li      t1, 5
    bltu    s2, t1, 1f
    addi    t0, s2, -4
    slli    t0, t0, LOG2_SLOTS_PER_EPOCH
    addi    t0, t0, -1
1:  LDQ     t1, s1, BeaconState_slot        # get_block_root_at_slot: before the state's slot, in range
    bgeu    t0, t1, 2f
    li      t2, SLOTS_PER_HISTORICAL_ROOT
    add     t2, t0, t2
    bgtu    t1, t2, 2f
    li      t2, SLOTS_PER_HISTORICAL_ROOT - 1
    and     t0, t0, t2
    slli    t0, t0, 5
    ADDQ    t1, s1, BeaconState_block_roots
    add     t1, t1, t0
    addi    t2, s3, 32
    COPY32  t2, t1
2:  ADDQ    t1, s1, BeaconState_genesis_validators_root
    addi    t2, s3, 64
    COPY32  t2, t1
    li      a0, LANTERN_OK
7:  LEAVE 16
END_FUNCTION lantern_committee_key

/* a0 = the valid entry of cache a0 for epoch a1 and the key at a2, or 0. A leaf. */
LOCAL_FUNCTION lantern_committee_find
    UNWIND_END_PROLOGUE
    ld      t0, CommitteeCache_validators(a0)
    slli    t0, t0, 3
    addi    t0, t0, CommitteeEntry__mem + LIST_FIXED
    addi    t1, a0, CommitteeCache_entries
    li      t2, COMMITTEE_CACHE_ENTRIES
1:  ld      t3, CommitteeEntry_valid(t1)
    beqz    t3, 3f
    ld      t3, CommitteeEntry_epoch(t1)
    bne     t3, a1, 3f
    li      t3, 0                           # the 96 bytes of the key
    addi    t4, t1, CommitteeEntry_seed
2:  add     t5, t4, t3
    ld      t5, 0(t5)
    add     t6, a2, t3
    ld      t6, 0(t6)
    bne     t5, t6, 3f
    addi    t3, t3, 8
    li      t5, 96
    bltu    t3, t5, 2b
    mv      a0, t1
    ret
3:  add     t1, t1, t0
    addi    t2, t2, -1
    bnez    t2, 1b
    li      a0, 0
    ret
END_FUNCTION lantern_committee_find

SPEC_FUNCTION committee_cache_size
    FRAME 16
    ld      t0, 0(a0)
    slli    t0, t0, 3
    addi    t0, t0, CommitteeEntry__mem + LIST_FIXED
    li      t1, KEYSUM_BLOCK_BYTES          # and the entry's block of key sums
    add     t0, t0, t1
    li      t1, COMMITTEE_CACHE_ENTRIES
    mul     t0, t0, t1
    addi    t0, t0, COMMITTEE_CACHE_FIXED
    sd      t0, 0(a1)
    li      a0, LANTERN_OK
    UNFRAME 16
SPEC_END committee_cache_size

SPEC_FUNCTION committee_cache_init
    FRAME 16
    ld      t0, 0(a0)
    slli    t1, t0, 3
    addi    t1, t1, CommitteeEntry__mem + LIST_FIXED   # an entry and its list
    li      t2, COMMITTEE_CACHE_ENTRIES
    li      t3, KEYSUM_BLOCK_BYTES          # and its block of key sums
    add     t3, t1, t3
    mul     t3, t3, t2
    addi    t3, t3, COMMITTEE_CACHE_FIXED
    ld      t4, CommitteeCache_size(a1)
    bltu    t4, t3, 9f
    sd      t0, CommitteeCache_validators(a1)
    sd      zero, CommitteeCache_next(a1)
    addi    t3, a1, CommitteeCache_entries
1:  sd      zero, CommitteeEntry_valid(t3)
    add     t3, t3, t1
    addi    t2, t2, -1
    bnez    t2, 1b
    li      a0, LANTERN_OK
    UNFRAME 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    UNFRAME 16
SPEC_END committee_cache_init

SPEC_FUNCTION pubkey_cache_size
    FRAME 16
    ld      t0, 0(a0)
    li      t1, CRYPTO_BLS_ENTRY_BYTES
    mul     t0, t0, t1
    li      t1, CRYPTO_BLS_CACHE_FIXED + SIG_TABLE_BYTES   # and the SigTable before the entries
    add     t0, t0, t1
    sd      t0, 0(a1)
    li      a0, LANTERN_OK
    UNFRAME 16
SPEC_END pubkey_cache_size

# A BlsKeyCache of asm-crypto whose keys are those of a state's validators: key_stride Validator__mem.
SPEC_FUNCTION pubkey_cache_init
    FRAME 16
    ld      t0, 0(a0)
    li      t1, CRYPTO_BLS_ENTRY_BYTES
    mul     t2, t0, t1
    li      t3, CRYPTO_BLS_CACHE_FIXED + SIG_TABLE_BYTES
    add     t2, t2, t3
    ld      t3, 0(a1)                       # size
    bltu    t3, t2, 9f
    li      t2, Validator__mem
    sd      t2, CRYPTO_BLS_CACHE_KEY_STRIDE(a1)
    li      t2, CRYPTO_BLS_CACHE_FIXED + SIG_TABLE_BYTES
    sd      t2, CRYPTO_BLS_CACHE_OFFSET(a1)
    sd      t0, CRYPTO_BLS_CACHE_COUNT(a1)
    sd      zero, (PUBKEY_SIGS + SigTable_used)(a1)   # an empty SigTable
    li      t3, SIG_TABLE_BYTES - SigTable_entries
    sd      t3, (PUBKEY_SIGS + SigTable_room)(a1)
    add     t3, a1, t2                      # every entry empty
1:  beqz    t0, 2f
    sd      zero, CRYPTO_BLS_ENTRY_STATUS(t3)
    add     t3, t3, t1
    addi    t0, t0, -1
    j       1b
2:  li      a0, LANTERN_OK
    UNFRAME 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    UNFRAME 16
SPEC_END pubkey_cache_init

/* s1 state, s2 epoch pointer, s3 scratch, s4 out, s5 list, s6 cache. Locals: L the key (96). */
SPEC_FUNCTION get_committee_count_per_slot
    ENTER 96
    mv      s1, a0
    mv      s2, a1
    mv      s6, a2
    mv      s3, a3
    mv      s4, a4
    NEED_SCRATCH s3, s1, 1, 9f
    beqz    s6, 3f
    mv      a0, s1                          # an entry of the cache: its count
    ld      a1, 0(s2)
    addi    a2, sp, L
    call    lantern_committee_key
    bnez    a0, 3f
    mv      a0, s6
    ld      a1, 0(s2)
    addi    a2, sp, L
    call    lantern_committee_find
    beqz    a0, 3f
    ld      t0, CommitteeEntry_count(a0)
    j       4f
3:  LDQ     t2, s1, BeaconState_validators + 8
    ld      t3, 0(s3)
    SCRATCH_LIST s5, s3, t3, 0, t2
    mv      a0, s1
    mv      a1, s2
    mv      a2, s5
    call    lantern_get_active_validator_indices
    bnez    a0, 7f
    ld      t0, LIST_COUNT(s5)
4:  srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    li      t1, TARGET_COMMITTEE_SIZE
    divu    t0, t0, t1
    li      t1, MAX_COMMITTEES_PER_SLOT
    bltu    t0, t1, 1f
    mv      t0, t1
1:  bnez    t0, 2f                          # max(1, ...)
    li      t0, 1
2:  sd      t0, 0(s4)
    li      a0, LANTERN_OK
7:  LEAVE 96
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 96
SPEC_END get_committee_count_per_slot

/*
 * s1 indices, s2 seed, s3 i, s4 end, s5 scratch, s6 out entries, s7 scratch size.
 * Locals: L len(indices), L+8 i, L+16 shuffled.
 */
SPEC_FUNCTION compute_committee
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s5, a4
    ld      t0, LIST_COUNT(s1)              # n
    sd      t0, L(sp)
    ld      t1, 0(a2)                       # index
    ld      t2, 0(a3)                       # count
    beqz    t2, 8f
    mul     t3, t0, t1
    divu    s3, t3, t2                      # start = len(indices) * index // count
    addi    t1, t1, 1
    mul     t3, t0, t1
    divu    s4, t3, t2                      # end = len(indices) * (index + 1) // count
    sub     t3, s4, s3
    slli    t4, t3, 3
    addi    t4, t4, LIST_FIXED
    ld      t5, LIST_SIZE(a5)
    bltu    t5, t4, 9f
    li      t4, LIST_FIXED
    sd      t4, LIST_OFFSET(a5)
    sd      t3, LIST_COUNT(a5)
    addi    s6, a5, LIST_FIXED
    ld      s7, 0(s5)
1:  bgeu    s3, s4, 2f
    sd      s3, (L + 8)(sp)
    sd      s7, 0(s5)
    addi    a0, sp, (L + 8)                 # indices[compute_shuffled_index(i, len(indices), seed)]
    addi    a1, sp, L
    mv      a2, s2
    mv      a3, s5
    addi    a4, sp, (L + 16)
    call    lantern_compute_shuffled_index
    bnez    a0, 7f
    ld      t0, (L + 16)(sp)
    slli    t0, t0, 3
    add     t0, s1, t0
    ld      t0, LIST_FIXED(t0)
    sd      t0, 0(s6)
    addi    s6, s6, 8
    addi    s3, s3, 1
    j       1b
2:  li      a0, LANTERN_OK
7:  LEAVE 32
8:  li      a0, LANTERN_INVALID_SHUFFLED_INDEX
    LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END compute_committee

/*
 * s1 state, s2 slot, s3 index pointer, s4 scratch, s5 out, s6 scratch size, s7 n, s8 list,
 * s9 cache, s10 the entry. Locals: L epoch, L+8 committees per slot, L+16 domain type,
 * L+24 seed (32), L+56 index, L+64 count, L+72 the entry's key (96).
 */
SPEC_FUNCTION get_beacon_committee
    ENTER 176
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    mv      s9, a3
    mv      s4, a4
    mv      s5, a5
    NEED_SCRATCH s4, s1, 2, 9f
    ld      s6, 0(s4)
    LDQ     s7, s1, BeaconState_validators + 8
    srli    t0, s2, LOG2_SLOTS_PER_EPOCH    # epoch = compute_epoch_at_slot(slot)
    sd      t0, L(sp)
    mv      a0, s1
    addi    a1, sp, L
    mv      a2, s9
    mv      a3, s4
    addi    a4, sp, (L + 8)
    call    lantern_get_committee_count_per_slot
    bnez    a0, 7f
    beqz    s9, 20f
    mv      a0, s1                          # the cache's entry of the epoch
    ld      a1, L(sp)
    addi    a2, sp, (L + 72)
    call    lantern_committee_key
    bnez    a0, 20f
    mv      a0, s9
    ld      a1, L(sp)
    addi    a2, sp, (L + 72)
    call    lantern_committee_find
    mv      s10, a0
    bnez    s10, 30f
    SCRATCH_LIST s8, s4, s6, 0, s7          # a new entry: the active validators, shuffled
    mv      a0, s1
    addi    a1, sp, L
    mv      a2, s8
    call    lantern_get_active_validator_indices
    bnez    a0, 7f
    ld      t0, LIST_COUNT(s8)
    ld      t1, CommitteeCache_validators(s9)
    bgtu    t0, t1, 21f
    ld      t2, CommitteeCache_next(s9)
    slli    t3, t1, 3
    addi    t3, t3, CommitteeEntry__mem + LIST_FIXED
    mul     t4, t2, t3
    add     s10, s9, t4
    addi    s10, s10, CommitteeCache_entries
    li      t4, COMMITTEE_CACHE_ENTRIES     # its block of key sums: each status 0
    mul     t4, t4, t3
    add     t4, t4, s9
    addi    t4, t4, CommitteeCache_entries
    li      t5, KEYSUM_BLOCK_BYTES
    mul     t5, t5, t2
    add     t4, t4, t5
    li      t5, SLOTS_PER_EPOCH * MAX_COMMITTEES_PER_SLOT
13: sd      zero, KeySum_status(t4)
    addi    t4, t4, KeySum__mem
    addi    t5, t5, -1
    bnez    t5, 13b
    addi    t2, t2, 1
    li      t4, COMMITTEE_CACHE_ENTRIES
    bltu    t2, t4, 10f
    li      t2, 0
10: sd      t2, CommitteeCache_next(s9)
    sd      zero, CommitteeEntry_valid(s10)
    sd      t0, CommitteeEntry_count(s10)
    slli    t3, t1, 3
    addi    t3, t3, LIST_FIXED
    sd      t3, (CommitteeEntry__mem + LIST_SIZE)(s10)
    SCRATCH_GIVE s4, s6, 1, s7
    addi    a0, s10, CommitteeEntry_count
    addi    a1, sp, (L + 72)
    mv      a2, s4
    addi    a3, s10, CommitteeEntry__mem
    call    lantern_compute_shuffled_permutation
    bnez    a0, 7f
    addi    t0, s10, CommitteeEntry__mem + LIST_FIXED   # entry i = indices[permutation[i]]
    addi    t1, s8, LIST_FIXED
    ld      t2, CommitteeEntry_count(s10)
    li      t3, 0
11: bgeu    t3, t2, 12f
    slli    t4, t3, 3
    add     t4, t0, t4
    ld      t5, 0(t4)
    slli    t5, t5, 3
    add     t5, t1, t5
    ld      t5, 0(t5)
    sd      t5, 0(t4)
    addi    t3, t3, 1
    j       11b
12: ld      t0, L(sp)
    sd      t0, CommitteeEntry_epoch(s10)
    addi    t0, s10, CommitteeEntry_seed
    addi    t1, sp, (L + 72)
    COPY32  t0, t1
    addi    t0, t0, 32
    addi    t1, t1, 32
    COPY32  t0, t1
    addi    t0, t0, 32
    addi    t1, t1, 32
    COPY32  t0, t1
    li      t0, 1
    sd      t0, CommitteeEntry_valid(s10)
30: ld      t0, (L + 8)(sp)                 # the slice of the entry: index, count, start, end
    andi    t1, s2, (SLOTS_PER_EPOCH - 1)
    mul     t1, t1, t0
    ld      t2, 0(s3)
    add     t2, t1, t2
    bltu    t2, t1, 6f
    slli    t0, t0, LOG2_SLOTS_PER_EPOCH
    ld      t3, CommitteeEntry_count(s10)
    mul     t4, t3, t2
    divu    t4, t4, t0
    addi    t2, t2, 1
    mul     t5, t3, t2
    divu    t5, t5, t0
    sub     t6, t5, t4
    beqz    t6, 31f
    bgtu    t5, t3, 5f                      # past the list: compute_shuffled_index raises
31: slli    t0, t6, 3
    addi    t0, t0, LIST_FIXED
    ld      t1, LIST_SIZE(s5)
    bltu    t1, t0, 9f
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s5)
    sd      t6, LIST_COUNT(s5)
    addi    t0, s10, CommitteeEntry__mem + LIST_FIXED
    slli    t1, t4, 3
    add     t0, t0, t1
    addi    t1, s5, LIST_FIXED
32: beqz    t6, 33f
    ld      t2, 0(t0)
    sd      t2, 0(t1)
    addi    t0, t0, 8
    addi    t1, t1, 8
    addi    t6, t6, -1
    j       32b
33: li      a0, LANTERN_OK
    LEAVE 176
20: SCRATCH_LIST s8, s4, s6, 0, s7          # no cache
    mv      a0, s1
    addi    a1, sp, L
    mv      a2, s8
    call    lantern_get_active_validator_indices
    bnez    a0, 7f
21: li      t0, DOMAIN_BEACON_ATTESTER
    sw      t0, (L + 16)(sp)
    mv      a0, s1
    addi    a1, sp, L
    addi    a2, sp, (L + 16)
    addi    a3, sp, (L + 24)
    call    lantern_get_seed
    bnez    a0, 7f
    ld      t0, (L + 8)(sp)                 # index = (slot % SLOTS_PER_EPOCH) * committees_per_slot + index
    andi    t1, s2, (SLOTS_PER_EPOCH - 1)
    mul     t1, t1, t0
    ld      t2, 0(s3)
    add     t2, t1, t2
    bltu    t2, t1, 6f
    sd      t2, (L + 56)(sp)
    slli    t0, t0, LOG2_SLOTS_PER_EPOCH    # count = committees_per_slot * SLOTS_PER_EPOCH
    sd      t0, (L + 64)(sp)
    SCRATCH_GIVE s4, s6, 1, s7
    mv      a0, s8
    addi    a1, sp, (L + 24)
    addi    a2, sp, (L + 56)
    addi    a3, sp, (L + 64)
    mv      a4, s4
    mv      a5, s5
    call    lantern_compute_committee
7:  LEAVE 176
5:  li      a0, LANTERN_INVALID_SHUFFLED_INDEX
    LEAVE 176
6:  li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 176
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 176
SPEC_END get_beacon_committee

.if FORK >= FORK_ELECTRA
/*
 * s1 state, s2 attestation, s3 scratch, s4 out, s5 scratch size, s6 n, s7 committee indices,
 * s8 committee, s9 committee offset, s10 committee index cursor.
 * Locals: L committee index, L+8 the scratch size the callee gets, L+16 bits, L+24 bit count, L+32 cursor end.
 */
SPEC_FUNCTION get_attesting_indices
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    sd      a2, (L + 40)(sp)                # the committee cache
    mv      s3, a3
    mv      s4, a4
    NEED_SCRATCH_B s3, s1, 3, CIDX_BYTES, 9f
    LDQ     s6, s1, BeaconState_validators + 8
    slli    t0, s6, 3                       # out has room for every validator
    addi    t0, t0, LIST_FIXED
    ld      t1, LIST_SIZE(s4)
    bltu    t1, t0, 9f
    ld      s5, 0(s3)
    li      t0, CIDX_BYTES
    sub     t1, s5, t0
    add     s7, s3, t1                      # committee indices: the last CIDX_BYTES
    sd      t0, 0(s7)
    slli    t2, s6, 3
    addi    t2, t2, LIST_FIXED
    sub     t1, t1, t2
    add     s8, s3, t1                      # the committee: the L(n) before
    sd      t2, 0(s8)
    sd      t1, (L + 8)(sp)
    addi    a0, s2, Attestation_committee_bits
    mv      a1, s7
    call    lantern_get_committee_indices
    PART    t0, t1, s2, Attestation_aggregation_bits
    sd      t0, (L + 16)(sp)
    sd      t1, (L + 24)(sp)
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s4)
    sd      zero, LIST_COUNT(s4)
    li      s9, 0
    addi    s10, s7, LIST_FIXED
    ld      t0, LIST_COUNT(s7)
    slli    t0, t0, 3
    add     t0, s10, t0
    sd      t0, (L + 32)(sp)
1:  ld      t0, (L + 32)(sp)
    bgeu    s10, t0, 4f
    ld      t0, 0(s10)
    addi    s10, s10, 8
    sd      t0, L(sp)
    ld      t0, (L + 8)(sp)
    sd      t0, 0(s3)
    mv      a0, s1                          # committee = get_beacon_committee(state, data.slot, committee_index)
    addi    a1, s2, (Attestation_data + AttestationData_slot)
    addi    a2, sp, L
    mv      a4, s3
    mv      a5, s8
    ld      a3, (L + 40)(sp)
    call    lantern_get_beacon_committee
    bnez    a0, 7f
    ld      t0, LIST_COUNT(s8)
    addi    t1, s8, LIST_FIXED
    ld      t2, (L + 16)(sp)                # bits
    ld      t3, (L + 24)(sp)                # bit count
    ld      t4, LIST_COUNT(s4)
    slli    t5, t4, 3
    add     t5, s4, t5
    addi    t5, t5, LIST_FIXED
2:  beqz    t0, 3f
    bgeu    s9, t3, 8f                      # aggregation_bits[committee_offset + index]
    srli    t6, s9, 3
    add     t6, t2, t6
    lbu     t6, 0(t6)
    andi    a6, s9, 7
    srl     t6, t6, a6
    ld      a6, 0(t1)
    addi    t1, t1, 8
    andi    t6, t6, 1
    beqz    t6, 25f
    sd      a6, 0(t5)
    addi    t5, t5, 8
    addi    t4, t4, 1
25: addi    s9, s9, 1
    addi    t0, t0, -1
    j       2b
3:  sd      t4, LIST_COUNT(s4)
    j       1b
4:  addi    a0, s4, LIST_FIXED              # a set: ascending
    ld      a1, LIST_COUNT(s4)
    call    lantern_sort_u64
    li      a0, LANTERN_OK
7:  LEAVE 48
8:  li      a0, LANTERN_INVALID_ATTESTATION
    LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END get_attesting_indices
.else
/*
 * Before electra: the committee of data.index. A PendingAttestation of phase0 has the same
 * aggregation_bits and data, so the function also takes one.
 * s1 state, s2 attestation, s3 scratch, s4 out, s5 scratch size, s6 n, s7 committee.
 */
.if FORK == FORK_PHASE0
.if (PendingAttestation_aggregation_bits != Attestation_aggregation_bits) || (PendingAttestation_data != Attestation_data)
.error "PendingAttestation does not start with the fields of Attestation"
.endif
.endif
SPEC_FUNCTION get_attesting_indices
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s9, a2                          # the committee cache
    mv      s3, a3
    mv      s4, a4
    NEED_SCRATCH s3, s1, 3, 9f
    LDQ     s6, s1, BeaconState_validators + 8
    slli    t0, s6, 3                       # out has room for every validator
    addi    t0, t0, LIST_FIXED
    ld      t1, LIST_SIZE(s4)
    bltu    t1, t0, 9f
    ld      s5, 0(s3)
    SCRATCH_LIST s7, s3, s5, 0, s6          # the committee: the last list
    SCRATCH_GIVE s3, s5, 1, s6
    mv      a0, s1                          # committee = get_beacon_committee(state, data.slot, data.index)
    addi    a1, s2, (Attestation_data + AttestationData_slot)
    addi    a2, s2, (Attestation_data + AttestationData_index)
    mv      a4, s3
    mv      a5, s7
    mv      a3, s9
    call    lantern_get_beacon_committee
    bnez    a0, 7f
    PART    t2, t3, s2, Attestation_aggregation_bits
    ld      t0, LIST_COUNT(s7)
    addi    t1, s7, LIST_FIXED
    li      t4, LIST_FIXED
    sd      t4, LIST_OFFSET(s4)
    li      t4, 0                           # the count
    addi    t5, s4, LIST_FIXED
    li      s8, 0                           # i
2:  bgeu    s8, t0, 3f
    bgeu    s8, t3, 8f                      # aggregation_bits[i]
    srli    t6, s8, 3
    add     t6, t2, t6
    lbu     t6, 0(t6)
    andi    a6, s8, 7
    srl     t6, t6, a6
    ld      a6, 0(t1)
    addi    t1, t1, 8
    andi    t6, t6, 1
    beqz    t6, 25f
    sd      a6, 0(t5)
    addi    t5, t5, 8
    addi    t4, t4, 1
25: addi    s8, s8, 1
    j       2b
3:  sd      t4, LIST_COUNT(s4)
    addi    a0, s4, LIST_FIXED              # a set: ascending
    mv      a1, t4
    call    lantern_sort_u64
    li      a0, LANTERN_OK
7:  LEAVE 16
8:  li      a0, LANTERN_INVALID_ATTESTATION
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_attesting_indices
.endif

/* s1 state, s2 attestation, s3 scratch, s4 out, s5 scratch size, s6 n, s7 the attesting list. */
SPEC_FUNCTION get_indexed_attestation
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    sd      a2, L(sp)                       # the committee cache
    mv      s3, a3
    mv      s4, a4
    NEED_SCRATCH_B s3, s1, 4, CIDX_BYTES, 9f
    LDQ     s6, s1, BeaconState_validators + 8
    ld      s5, 0(s3)
    SCRATCH_LIST s7, s3, s5, 0, s6
    SCRATCH_GIVE s3, s5, 1, s6
    mv      a0, s1
    mv      a1, s2
    mv      a3, s3
    mv      a4, s7
    ld      a2, L(sp)
    call    lantern_get_attesting_indices
    bnez    a0, 7f
    ld      t0, LIST_COUNT(s7)              # out: attesting_indices, data, signature
    slli    t1, t0, 3
    li      t2, IndexedAttestation__fixed
    add     t1, t1, t2
    ld      t3, 0(s4)
    bltu    t3, t1, 9f
    sd      t2, IndexedAttestation_attesting_indices(s4)
    sd      t0, (IndexedAttestation_attesting_indices + 8)(s4)
    add     a0, s4, t2
    addi    a1, s7, LIST_FIXED
    slli    a2, t0, 3
    call    lantern_copy
    addi    a0, s4, IndexedAttestation_data
    addi    a1, s2, Attestation_data
    li      a2, AttestationData__mem
    call    lantern_copy
    addi    a0, s4, IndexedAttestation_signature
    addi    a1, s2, Attestation_signature
    li      a2, 96
    call    lantern_copy
    li      a0, LANTERN_OK
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_indexed_attestation

/*
 * s1 state, s2 indexed attestation, s3 scratch, s4 out, s5 scratch size, s6 keys (a
 * BlsPublicKeyList), s7 indices, s8 count, s9 cache: 0 when it has no entry of the largest index.
 * Locals: L domain type, L+8 domain (32), L+40 message (24 + 32).
 */
.if IndexedAttestation_attesting_indices != CRYPTO_BLS_LIST_OFFSET
.error "an IndexedAttestation must read as a BlsIndexList of its attesting indices"
.endif
SPEC_LEAF is_valid_indexed_attestation
    li      a5, 0
    li      a6, 0
    j       lantern_indexed_attestation_valid
SPEC_END is_valid_indexed_attestation

/*
 * is_valid_indexed_attestation with a5 the attestation that the indexed attestation a1
 * is get_indexed_attestation of, with the CommitteeCache a6 (each 0 or not); with both and a
 * PubkeyCache, the keys' sum may come from the cache's key sums (block-processing.md).
 * Locals as is_valid_indexed_attestation's, then L+96 the attestation, L+104 the committee
 * cache, L+112 the keys' sum (G1Point), L+256 its compressed form (48).
 */
LOCAL_FUNCTION lantern_indexed_attestation_valid
    ENTER 304
    sd      a5, (L + 96)(sp)
    sd      a6, (L + 104)(sp)
    mv      s1, a0
    mv      s2, a1
    mv      s9, a2
    mv      s3, a3
    mv      s4, a4
    sd      zero, 0(s4)
    PART    s7, s8, s2, IndexedAttestation_attesting_indices
    beqz    s8, 8f                          # len(indices) == 0: False
    li      t0, 1                           # indices sorted and unique
1:  bgeu    t0, s8, 2f
    slli    t1, t0, 3
    add     t1, s7, t1
    ld      t2, -8(t1)
    ld      t3, 0(t1)
    bleu    t3, t2, 8f
    addi    t0, t0, 1
    j       1b
2:  addi    t0, s8, -1                      # the largest index names a validator
    slli    t0, t0, 3
    add     t0, s7, t0
    ld      t0, 0(t0)
    LDQ     t1, s1, BeaconState_validators + 8
    bgeu    t0, t1, 6f
    beqz    s9, 31f                         # with a cache that has an entry of every index: no list of keys
    ld      t1, CRYPTO_BLS_CACHE_COUNT(s9)
    bltu    t0, t1, 4f
    li      s9, 0
31: li      t0, 48                          # pubkeys: a BlsPublicKeyList at the end of scratch
    mul     t0, t0, s8
    addi    t0, t0, (24 + 7)
    andi    t0, t0, -8
    ld      s5, 0(s3)
    li      t1, LANTERN_SCRATCH_FIXED
    add     t1, t1, t0
    bltu    s5, t1, 9f
    sub     t1, s5, t0
    add     s6, s3, t1
    sd      t0, 0(s6)
    li      t2, 24
    sd      t2, 8(s6)
    sd      s8, 16(s6)
    sd      t1, 0(s3)
    addi    t2, s6, 24
    PART    t3, t4, s1, BeaconState_validators
    li      t0, 0
3:  bgeu    t0, s8, 4f
    slli    t1, t0, 3
    add     t1, s7, t1
    ld      t1, 0(t1)
    slli    t1, t1, 7
    add     t1, t3, t1
    .irp k, 0, 8, 16, 24, 32, 40
    ld      t4, (Validator_pubkey + \k)(t1)
    sd      t4, \k(t2)
    .endr
    addi    t2, t2, 48
    addi    t0, t0, 1
    j       3b
4:  li      t0, DOMAIN_BEACON_ATTESTER      # domain = get_domain(state, DOMAIN_BEACON_ATTESTER, data.target.epoch)
    sw      t0, L(sp)
    mv      a0, s1
    addi    a1, sp, L
    addi    a2, s2, (IndexedAttestation_data + AttestationData_target + Checkpoint_epoch)
    mv      a3, s3
    addi    a4, sp, (L + 8)
    call    lantern_get_domain
    bnez    a0, 7f
    ADDRESS a0, lantern_type_AttestationData
    addi    a1, s2, IndexedAttestation_data
    addi    a2, sp, (L + 8)
    mv      a3, s3
    addi    a4, sp, (L + 64)
    call    lantern_compute_signing_root
    bnez    a0, 7f
    li      t0, 56
    sd      t0, (L + 40)(sp)
    li      t0, 24
    sd      t0, (L + 48)(sp)
    li      t0, 32
    sd      t0, (L + 56)(sp)
    bnez    s9, 40f
    mv      a0, s6                          # bls.FastAggregateVerify(pubkeys, signing_root, signature)
    addi    a1, sp, (L + 40)
    addi    a2, s2, IndexedAttestation_signature
    mv      a3, s3
    mv      a4, s4
    CALL_GLOBAL crypto_bls_fast_aggregate_verify
7:  LEAVE 304
8:  li      a0, LANTERN_OK
    LEAVE 304
6:  li      a0, LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 304
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 304
40: ld      t0, (L + 96)(sp)                # the keys' sum from the committees' key sums
    beqz    t0, 41f
    ld      t1, (L + 104)(sp)
    beqz    t1, 41f
    mv      a0, s1
    mv      a1, t0
    mv      a2, t1
    mv      a3, s9
    addi    a4, sp, (L + 112)
    addi    a5, sp, (L + 40)
    addi    a6, s2, IndexedAttestation_signature
    mv      a7, s3
    call    lantern_attestation_key_sum
    beqz    a0, 41f
    addi    a0, sp, (L + 112)               # bls.FastAggregateVerify: CoreVerify of point_to_pubkey(sum)
    addi    a1, sp, (L + 256)
    CALL_GLOBAL crypto_bls_g1_compress
    addi    a0, sp, (L + 256)
    addi    a1, sp, (L + 40)
    addi    a2, s2, IndexedAttestation_signature
    mv      a3, s3
    mv      a4, s4
    CALL_GLOBAL crypto_bls_verify
    LEAVE 304
41: PART    a0, t0, s1, BeaconState_validators      # the keys: the validators' pubkeys
    addi    a0, a0, Validator_pubkey
    mv      a1, s2                          # the indices: the indexed attestation, as a BlsIndexList
    mv      a2, s9
    addi    a3, sp, (L + 40)
    addi    a4, s2, IndexedAttestation_signature
    mv      a5, s3
    mv      a6, s4
    CALL_GLOBAL crypto_bls_fast_aggregate_verify_cached
    LEAVE 304
END_FUNCTION lantern_indexed_attestation_valid

# 1 in Montgomery form: 2^384 mod p of BLS12-381, the z of an affine point as a G1Point.
    RODATA
    .p2align 3
keysum_one:
    .quad 0x760900000002fffd, 0xebf4000bc40c0002, 0x5f48985753c758ba
    .quad 0x77ce585370525745, 0x5c071a97a256ec6d, 0x15f65ec3fa80e493
    .text

/* The 144 bytes at soff(sbase) to doff(dbase). Uses t5, t6. */
.macro COPY144 doff, dbase, soff, sbase
    .irp o, 0, 16, 32, 48, 64, 80, 96, 112, 128
    ld      t5, (\soff + \o)(\sbase)
    ld      t6, (\soff + \o + 8)(\sbase)
    sd      t5, (\doff + \o)(\dbase)
    sd      t6, (\doff + \o + 8)(\dbase)
    .endr
.endm

/* The point of PubkeyCache entry e as a G1Point at doff(dbase): its affine x and y, and z = 1. Uses t4-t6. */
.macro ENTRY_POINT doff, dbase, e
    .irp o, 0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88
    ld      t5, (CRYPTO_BLS_ENTRY_POINT + \o)(\e)
    sd      t5, (\doff + \o)(\dbase)
    .endr
    ADDRESS t4, keysum_one
    .irp o, 0, 8, 16, 24, 32, 40
    ld      t5, \o(t4)
    sd      t5, (\doff + 96 + \o)(\dbase)
    .endr
.endm

/* Bit b of the bits at base into dst: 0 or 1. Uses tmp. */
.macro BIT dst, base, b, tmp
    srli    \dst, \b, 3
    add     \dst, \dst, \base
    lbu     \dst, 0(\dst)
    andi    \tmp, \b, 7
    srl     \dst, \dst, \tmp
    andi    \dst, \dst, 1
.endm

/*
 * a0 = the members of the a1 indices at a0 whose PubkeyCache a3 entries do not hold their
 * keys (state validators at a2), each also written at a4 when a4 is not 0; or -1 when a member
 * is at or past the cache's count, or its entry has status 2 and its key. A leaf.
 */
LOCAL_FUNCTION lantern_key_sum_scan
    UNWIND_END_PROLOGUE
    ld      a5, CRYPTO_BLS_CACHE_COUNT(a3)
    ld      a6, CRYPTO_BLS_CACHE_OFFSET(a3)
    add     a6, a3, a6
    li      a7, 0
    li      t6, CRYPTO_BLS_ENTRY_BYTES
1:  beqz    a1, 5f
    ld      t0, 0(a0)
    addi    a0, a0, 8
    bgeu    t0, a5, 6f
    mul     t1, t0, t6                      # the entry
    add     t1, t1, a6
    slli    t2, t0, 7                       # the validator
    add     t2, t2, a2
    ld      t3, CRYPTO_BLS_ENTRY_STATUS(t1)
    beqz    t3, 3f
    .irp o, 0, 8, 16, 24, 32, 40
    ld      t4, (CRYPTO_BLS_ENTRY_KEY + \o)(t1)
    ld      t5, (Validator_pubkey + \o)(t2)
    bne     t4, t5, 3f
    .endr
    li      t4, 1
    bne     t3, t4, 6f
    j       4f
3:  addi    a7, a7, 1                       # not its key
    beqz    a4, 4f
    sd      t0, 0(a4)
    addi    a4, a4, 8
4:  addi    a1, a1, -1
    j       1b
5:  mv      a0, a7
    ret
6:  li      a0, -1
    ret
END_FUNCTION lantern_key_sum_scan

/*
 * Makes the KeySum a0 of the a2 members at a1 (state validators at a3, PubkeyCache a4).
 * Members whose entries do not hold their keys: crypto_bls_fast_aggregate_verify_cached of
 * them first, with message a5, signature a6 and scratch a7 (its last bytes take their list),
 * to fill their entries. a0 = 1 when the KeySum has status 1, 2 when it has status 2, 0 when
 * a callee fails. s1 KeySum, s2 members, s3 count, s4 validators, s5 cache, s6 message,
 * s7 signature, s8 scratch, s9 list, s10 i. Locals: L the scratch size, L+8 valid,
 * L+48 the sum, L+192 the next, L+336 a key.
 */
LOCAL_FUNCTION lantern_key_sum_make
    ENTER 480
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    mv      s7, a6
    mv      s8, a7
    mv      a0, s2
    mv      a1, s3
    mv      a2, s4
    mv      a3, s5
    li      a4, 0
    call    lantern_key_sum_scan
    li      t0, -1
    beq     a0, t0, 8f
    beqz    a0, 3f
    ld      t1, 0(s8)                       # the list of those members at the end of scratch
    sd      t1, L(sp)
    slli    t2, a0, 3
    addi    t2, t2, LIST_FIXED
    sub     t3, t1, t2
    add     s9, s8, t3
    sd      t3, 0(s8)
    sd      t2, LIST_SIZE(s9)
    li      t4, LIST_FIXED
    sd      t4, LIST_OFFSET(s9)
    sd      a0, LIST_COUNT(s9)
    mv      a0, s2
    mv      a1, s3
    mv      a2, s4
    mv      a3, s5
    addi    a4, s9, LIST_FIXED
    call    lantern_key_sum_scan
    addi    a0, s4, Validator_pubkey
    mv      a1, s9
    mv      a2, s5
    mv      a3, s6
    mv      a4, s7
    mv      a5, s8
    addi    a6, sp, (L + 8)
    CALL_GLOBAL crypto_bls_fast_aggregate_verify_cached
    ld      t1, L(sp)
    sd      t1, 0(s8)
    bnez    a0, 9f
    mv      a0, s2
    mv      a1, s3
    mv      a2, s4
    mv      a3, s5
    li      a4, 0
    call    lantern_key_sum_scan
    bnez    a0, 8f                          # an entry still without its key: never tried again
3:  .irp o, 0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 120, 128, 136
    sd      zero, (L + 48 + \o)(sp)         # the point at infinity
    .endr
    li      s10, 0
4:  bgeu    s10, s3, 5f
    slli    t0, s10, 3
    add     t0, t0, s2
    ld      t0, 0(t0)
    li      t1, CRYPTO_BLS_ENTRY_BYTES
    mul     t1, t0, t1
    ld      t2, CRYPTO_BLS_CACHE_OFFSET(s5)
    add     t1, t1, t2
    add     t1, t1, s5
    ENTRY_POINT (L + 336), sp, t1
    addi    a0, sp, (L + 48)
    addi    a1, sp, (L + 336)
    addi    a2, sp, (L + 192)
    CALL_GLOBAL crypto_bls_g1_add
    COPY144 (L + 48), sp, (L + 192), sp
    addi    s10, s10, 1
    j       4b
5:  COPY144 KeySum_point, s1, (L + 48), sp
    li      t0, 1
    sd      t0, KeySum_status(s1)
    li      a0, 1
    LEAVE 480
8:  li      t0, 2
    sd      t0, KeySum_status(s1)
    li      a0, 2
    LEAVE 480
9:  li      a0, 0
    LEAVE 480
END_FUNCTION lantern_key_sum_make

/* Within lantern_attestation_key_sum: the key of member s10 at L+528 when its entry holds it, else to fail. */
.macro MEMBER_POINT fail
    ld      t0, (L + 72)(sp)
    slli    t1, s10, 3
    add     t0, t0, t1
    ld      t0, 0(t0)                       # the validator index
    ld      t1, CRYPTO_BLS_CACHE_COUNT(s3)
    bgeu    t0, t1, \fail
    li      t1, CRYPTO_BLS_ENTRY_BYTES
    mul     t1, t0, t1
    ld      t2, CRYPTO_BLS_CACHE_OFFSET(s3)
    add     t1, t1, t2
    add     t1, t1, s3
    ld      t2, CRYPTO_BLS_ENTRY_STATUS(t1)
    li      t3, 1
    bne     t2, t3, \fail
    slli    t0, t0, 7
    add     t0, t0, s4
    .irp o, 0, 8, 16, 24, 32, 40
    ld      t2, (CRYPTO_BLS_ENTRY_KEY + \o)(t1)
    ld      t3, (Validator_pubkey + \o)(t0)
    bne     t2, t3, \fail
    .endr
    ENTRY_POINT (L + 528), sp, t1
.endm

/*
 * The sum of the keys of the attesting validators of attestation a1 (state a0), from the
 * key sums of CommitteeCache a2 and the entries of PubkeyCache a3, at a4 (G1Point); a5 the
 * message, a6 the signature, a7 the scratch, for lantern_key_sum_make. a0 = 1 when a4 holds the sum,
 * else 0. s1 state, s2 attestation, s3 PubkeyCache, s4 validators, s5 the entry, s6 committees
 * of the epoch, s7 its active validators, s8 bits, s9 bit count, s10 member i.
 * Locals: L epoch, +8 committee index, +16 committee offset, +24 the block of key sums,
 * +32 committees per slot, +40 out, +48 message, +56 signature, +64 scratch, +72 members,
 * +80 member count, +88 bits set, +96 the KeySum, +104 the committee cache, +112 the entry's
 * key (96), +240 the sum, +384 the next, +528 a key, +672 its negation, +816 the pass: 0 counts
 * the additions the key sums save, 1 adds; +824 that count.
 */
LOCAL_FUNCTION lantern_attestation_key_sum
    ENTER 832
    mv      s1, a0
    mv      s2, a1
    sd      a2, (L + 104)(sp)
    mv      s3, a3
    sd      a4, (L + 40)(sp)
    sd      a5, (L + 48)(sp)
    sd      a6, (L + 56)(sp)
    sd      a7, (L + 64)(sp)
    ld      t0, (Attestation_data + AttestationData_slot)(s2)
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    sd      t0, L(sp)
    mv      a0, s1                          # the entry of the epoch
    mv      a1, t0
    addi    a2, sp, (L + 112)
    call    lantern_committee_key
    bnez    a0, 90f
    ld      a0, (L + 104)(sp)
    ld      a1, L(sp)
    addi    a2, sp, (L + 112)
    call    lantern_committee_find
    beqz    a0, 90f
    mv      s5, a0
    ld      t0, (L + 104)(sp)               # its block of key sums
    ld      t1, CommitteeCache_validators(t0)
    slli    t1, t1, 3
    addi    t1, t1, CommitteeEntry__mem + LIST_FIXED
    addi    t2, t0, CommitteeCache_entries
    sub     t3, s5, t2
    divu    t3, t3, t1
    li      t4, COMMITTEE_CACHE_ENTRIES
    mul     t4, t4, t1
    add     t2, t2, t4
    li      t4, KEYSUM_BLOCK_BYTES
    mul     t3, t3, t4
    add     t2, t2, t3
    sd      t2, (L + 24)(sp)
    ld      s7, CommitteeEntry_count(s5)
    srli    t0, s7, LOG2_SLOTS_PER_EPOCH    # get_committee_count_per_slot of the entry's count
    li      t1, TARGET_COMMITTEE_SIZE
    divu    t0, t0, t1
    li      t1, MAX_COMMITTEES_PER_SLOT
    bltu    t0, t1, 3f
    mv      t0, t1
3:  bnez    t0, 4f
    li      t0, 1
4:  sd      t0, (L + 32)(sp)
    slli    s6, t0, LOG2_SLOTS_PER_EPOCH
    PART    s4, t0, s1, BeaconState_validators
    PART    s8, s9, s2, Attestation_aggregation_bits
    .irp o, 0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 120, 128, 136
    sd      zero, (L + 240 + \o)(sp)        # the point at infinity
    .endr
    sd      zero, (L + 816)(sp)
    sd      zero, (L + 824)(sp)
5:  sd      zero, (L + 16)(sp)
.if FORK >= FORK_ELECTRA
    sd      zero, (L + 8)(sp)               # each committee of committee_bits, in order
1:  ld      t0, (L + 8)(sp)
    li      t1, MAX_COMMITTEES_PER_SLOT
    bgeu    t0, t1, 80f
    addi    t2, s2, Attestation_committee_bits
    BIT     t3, t2, t0, t4
    bnez    t3, 10f
2:  ld      t0, (L + 8)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 8)(sp)
    j       1b
.else
    ld      t0, (Attestation_data + AttestationData_index)(s2)   # the committee of data.index
    sd      t0, (L + 8)(sp)
.endif
10: ld      t0, (L + 8)(sp)                 # the committee: its slice of the entry and its bits
    ld      t1, (L + 32)(sp)
    bgeu    t0, t1, 90f
    ld      t2, (Attestation_data + AttestationData_slot)(s2)
    andi    t2, t2, (SLOTS_PER_EPOCH - 1)
    mul     t2, t2, t1
    add     t2, t2, t0                      # k
    li      t3, KeySum__mem
    mul     t3, t2, t3
    ld      t4, (L + 24)(sp)
    add     t3, t3, t4
    sd      t3, (L + 96)(sp)
    mul     t3, s7, t2                      # start
    divu    t3, t3, s6
    addi    t4, t2, 1                       # end
    mul     t4, s7, t4
    divu    t4, t4, s6
    bgtu    t4, s7, 90f
    sub     t5, t4, t3
    sd      t5, (L + 80)(sp)
    slli    t3, t3, 3
    add     t3, t3, s5
    addi    t3, t3, CommitteeEntry__mem + LIST_FIXED
    sd      t3, (L + 72)(sp)
    ld      t0, (L + 16)(sp)
    add     t1, t0, t5
    bgtu    t1, s9, 90f
    li      t2, 0                           # members with the bit
11: bgeu    t0, t1, 12f
    BIT     t3, s8, t0, t4
    add     t2, t2, t3
    addi    t0, t0, 1
    j       11b
12: sd      t2, (L + 88)(sp)
    sub     t3, t5, t2
    ld      t0, (L + 816)(sp)
    bnez    t0, 13f
    bgeu    t3, t2, 40f                     # pass 0: present - absent - 1 saved with the KeySum
    sub     t0, t2, t3
    addi    t0, t0, -1
    ld      t1, (L + 824)(sp)
    add     t1, t1, t0
    sd      t1, (L + 824)(sp)
    j       40f
13: bgeu    t3, t2, 30f
    ld      a0, (L + 96)(sp)                # fewer without the bit: the KeySum, less their keys
    ld      t0, KeySum_status(a0)
    li      t1, 1
    beq     t0, t1, 20f
    bnez    t0, 90f
    ld      a1, (L + 72)(sp)
    ld      a2, (L + 80)(sp)
    mv      a3, s4
    mv      a4, s3
    ld      a5, (L + 48)(sp)
    ld      a6, (L + 56)(sp)
    ld      a7, (L + 64)(sp)
    call    lantern_key_sum_make
    li      t0, 1
    bne     a0, t0, 90f
20: addi    a0, sp, (L + 240)
    ld      a1, (L + 96)(sp)
    addi    a1, a1, KeySum_point
    addi    a2, sp, (L + 384)
    CALL_GLOBAL crypto_bls_g1_add
    COPY144 (L + 240), sp, (L + 384), sp
    li      s10, 0
21: ld      t0, (L + 80)(sp)
    bgeu    s10, t0, 40f
    ld      t0, (L + 16)(sp)
    add     t0, t0, s10
    BIT     t1, s8, t0, t2
    bnez    t1, 22f
    MEMBER_POINT 90f
    addi    a0, sp, (L + 528)
    addi    a1, sp, (L + 672)
    CALL_GLOBAL crypto_bls_g1_neg
    addi    a0, sp, (L + 240)
    addi    a1, sp, (L + 672)
    addi    a2, sp, (L + 384)
    CALL_GLOBAL crypto_bls_g1_add
    COPY144 (L + 240), sp, (L + 384), sp
22: addi    s10, s10, 1
    j       21b
30: li      s10, 0                          # else the keys of the members with the bit
31: ld      t0, (L + 80)(sp)
    bgeu    s10, t0, 40f
    ld      t0, (L + 16)(sp)
    add     t0, t0, s10
    BIT     t1, s8, t0, t2
    beqz    t1, 32f
    MEMBER_POINT 90f
    addi    a0, sp, (L + 240)
    addi    a1, sp, (L + 528)
    addi    a2, sp, (L + 384)
    CALL_GLOBAL crypto_bls_g1_add
    COPY144 (L + 240), sp, (L + 384), sp
32: addi    s10, s10, 1
    j       31b
40: ld      t0, (L + 16)(sp)                # committee_offset += len(committee)
    ld      t1, (L + 80)(sp)
    add     t0, t0, t1
    sd      t0, (L + 16)(sp)
.if FORK >= FORK_ELECTRA
    j       2b
.endif
80: ld      t0, (L + 16)(sp)                # the bits: those of the committees, no more
    bne     t0, s9, 90f
    ld      t0, (L + 816)(sp)
    bnez    t0, 81f
    ld      t0, (L + 824)(sp)               # pass 0 done: pass 1 when the key sums save enough
    li      t1, KEYSUM_MIN_SAVED
    bltu    t0, t1, 90f
    li      t0, 1
    sd      t0, (L + 816)(sp)
    j       5b
81: ld      t0, (L + 40)(sp)
    COPY144 0, t0, (L + 240), sp
    li      a0, 1
    LEAVE 832
90: li      a0, 0
    LEAVE 832
END_FUNCTION lantern_attestation_key_sum

.if FORK >= FORK_ALTAIR
/*
 * s1 state, s2 data, s3 delay, s4 out, s5 matching source, s6 matching target, s7 matching head.
 * Locals: L current epoch, L+8 target root (32), L+40 head root (32), L+72 SLOTS_PER_EPOCH, L+80 its root.
 */
SPEC_FUNCTION get_attestation_participation_flag_indices
    ENTER 96
    mv      s1, a0
    mv      s2, a1
    ld      s3, 0(a2)
    mv      s4, a3
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, (AttestationData_target + Checkpoint_epoch)(s2)
    ld      t1, L(sp)
    ADDQ    t2, s1, BeaconState_current_justified_checkpoint
    beq     t0, t1, 1f                      # justified_checkpoint
    ADDQ    t2, s1, BeaconState_previous_justified_checkpoint
1:  ld      t3, Checkpoint_epoch(t2)        # is_matching_source = data.source == justified_checkpoint
    ld      t4, (AttestationData_source + Checkpoint_epoch)(s2)
    li      s5, 0
    bne     t3, t4, 11f
    addi    t0, s2, (AttestationData_source + Checkpoint_root)
    addi    t1, t2, Checkpoint_root
    NE32    t0, t1, 11f
    li      s5, 1
11: mv      a0, s1                          # target_root = get_block_root(state, data.target.epoch)
    addi    a1, s2, (AttestationData_target + Checkpoint_epoch)
    addi    a2, sp, (L + 8)
    call    lantern_get_block_root
    bnez    a0, 7f
    li      s6, 0
    addi    t0, s2, (AttestationData_target + Checkpoint_root)
    addi    t1, sp, (L + 8)
    NE32    t0, t1, 2f
    mv      s6, s5                          # is_matching_target = is_matching_source and target_root_matches
2:  mv      a0, s1                          # head_root = get_block_root_at_slot(state, data.slot)
    addi    a1, s2, AttestationData_slot
    addi    a2, sp, (L + 40)
    call    lantern_get_block_root_at_slot
    bnez    a0, 7f
    li      s7, 0
    addi    t0, s2, AttestationData_beacon_block_root
    addi    t1, sp, (L + 40)
    NE32    t0, t1, 3f
    mv      s7, s6
3:  li      a0, LANTERN_INVALID_SOURCE      # assert is_matching_source
    beqz    s5, 7f
    li      t0, SLOTS_PER_EPOCH
    sd      t0, (L + 72)(sp)
    addi    a0, sp, (L + 72)
    addi    a1, sp, (L + 80)
    call    lantern_integer_squareroot
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s4)
    addi    t1, s4, LIST_FIXED
    ld      t2, (L + 80)(sp)
    bgtu    s3, t2, 4f                      # source within integer_squareroot(SLOTS_PER_EPOCH)
    li      t3, TIMELY_SOURCE_FLAG_INDEX
    sd      t3, 0(t1)
    addi    t1, t1, 8
4:  beqz    s6, 5f
.if FORK < FORK_DENEB
    li      t3, SLOTS_PER_EPOCH             # and inclusion_delay <= SLOTS_PER_EPOCH
    bgtu    s3, t3, 5f
.endif
    li      t3, TIMELY_TARGET_FLAG_INDEX
    sd      t3, 0(t1)
    addi    t1, t1, 8
5:  beqz    s7, 6f
    li      t3, MIN_ATTESTATION_INCLUSION_DELAY
    bne     s3, t3, 6f
    li      t3, TIMELY_HEAD_FLAG_INDEX
    sd      t3, 0(t1)
    addi    t1, t1, 8
6:  addi    t2, s4, LIST_FIXED
    sub     t1, t1, t2
    srli    t1, t1, 3
    sd      t1, LIST_COUNT(s4)
    li      a0, LANTERN_OK
7:  LEAVE 96
SPEC_END get_attestation_participation_flag_indices
.endif

.if FORK == FORK_PHASE0
/*
 * s1 state, s2 attestation, s3 config, s4 scratch, s5 result, s6 scratch size,
 * s8 the PartRef offset of the list to append to, s9 the indexed attestation, s10 the committee.
 * Locals: L previous epoch, L+8 current epoch, L+16 committees per slot, L+24 valid,
 * L+32 proposer index, L+40 the scratch size callees get, L+48 the new value, L+56 its bit bytes.
 */
SPEC_FUNCTION process_attestation
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH_B s4, s1, 10, ATTEST_EXTRA, 9f
    sd      zero, 0(s5)
    ld      s6, 0(s4)
    LDQ     t1, s1, BeaconState_validators + 8
    slli    t1, t1, 3
    addi    t1, t1, LIST_FIXED              # own scratch at the end: the indexed attestation, the committee
    li      t2, IndexedAttestation__fixed + 8
    add     t2, t2, t1
    sub     t0, s6, t2
    add     s9, s4, t0
    sd      t2, 0(s9)
    sub     t0, t0, t1
    add     s10, s4, t0
    sd      t1, 0(s10)
    sd      t0, (L + 40)(sp)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_previous_epoch
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_get_current_epoch
    li      a0, LANTERN_INVALID_ATTESTATION
    ld      t0, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s2)
    ld      t1, L(sp)                       # assert data.target.epoch in (previous, current)
    beq     t0, t1, 1f
    ld      t1, (L + 8)(sp)
    bne     t0, t1, 6f
1:  ld      t2, (Attestation_data + AttestationData_slot)(s2)
    srli    t3, t2, LOG2_SLOTS_PER_EPOCH    # assert data.target.epoch == compute_epoch_at_slot(data.slot)
    bne     t3, t0, 6f
    addi    t3, t2, MIN_ATTESTATION_INCLUSION_DELAY     # assert data.slot + MIN_ATTESTATION_INCLUSION_DELAY <= state.slot
    bltu    t3, t2, 5f
    LDQ     t4, s1, BeaconState_slot
    bltu    t4, t3, 6f
    addi    t3, t2, SLOTS_PER_EPOCH         # assert state.slot <= data.slot + SLOTS_PER_EPOCH
    bltu    t3, t2, 5f
    bltu    t3, t4, 6f
    ld      t0, (L + 40)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # assert data.index < get_committee_count_per_slot(state, data.target.epoch)
    addi    a1, s2, (Attestation_data + AttestationData_target + Checkpoint_epoch)
    mv      a3, s4
    addi    a4, sp, (L + 16)
    ld      a2, CONFIG_COMMITTEE_CACHE(s3)
    call    lantern_get_committee_count_per_slot
    bnez    a0, 7f
    li      a0, LANTERN_INVALID_ATTESTATION
    ld      t0, (Attestation_data + AttestationData_index)(s2)
    ld      t1, (L + 16)(sp)
    bgeu    t0, t1, 6f
    ld      t0, (L + 40)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # committee = get_beacon_committee(state, data.slot, data.index)
    addi    a1, s2, (Attestation_data + AttestationData_slot)
    addi    a2, s2, (Attestation_data + AttestationData_index)
    mv      a4, s4
    mv      a5, s10
    ld      a3, CONFIG_COMMITTEE_CACHE(s3)
    call    lantern_get_beacon_committee
    CHECK_STATUS s5, 7f, 8f
    ld      t0, LIST_COUNT(s10)
    LDQ     t1, s2, Attestation_aggregation_bits + 8
    li      a0, LANTERN_INVALID_ATTESTATION
    bne     t0, t1, 6f                      # assert len(attestation.aggregation_bits) == len(committee)
    ld      t0, (L + 40)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # proposer_index = get_beacon_proposer_index(state)
    mv      a1, s4
    addi    a2, sp, (L + 32)
    call    lantern_get_beacon_proposer_index
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s2)
    ld      t1, (L + 8)(sp)
    bne     t0, t1, 1f
    ADDQ    t1, s1, BeaconState_current_justified_checkpoint
    li      s8, BeaconState_current_epoch_attestations
    j       2f
1:  ADDQ    t1, s1, BeaconState_previous_justified_checkpoint
    li      s8, BeaconState_previous_epoch_attestations
2:  addi    t0, s2, (Attestation_data + AttestationData_source)
    li      a0, LANTERN_INVALID_ATTESTATION
    ld      t2, Checkpoint_epoch(t0)        # assert data.source == the justified checkpoint of its epoch
    ld      t3, Checkpoint_epoch(t1)
    bne     t2, t3, 6f
    addi    t0, t0, Checkpoint_root
    addi    t1, t1, Checkpoint_root
    NE32    t0, t1, 6f
    ld      t0, (L + 40)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # assert is_valid_indexed_attestation(state, get_indexed_attestation(...))
    mv      a1, s2
    mv      a3, s4
    mv      a4, s9
    ld      a2, CONFIG_COMMITTEE_CACHE(s3)
    call    lantern_get_indexed_attestation
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 40)(sp)
    sd      t0, 0(s4)
    mv      a0, s1
    mv      a1, s9
    mv      a3, s4
    addi    a4, sp, (L + 24)
    ld      a2, CONFIG_PUBKEY_CACHE(s3)
    call    lantern_is_valid_indexed_attestation
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 24)(sp)
    li      a0, LANTERN_INVALID_ATTESTATION
    beqz    t0, 6f
    add     t0, s1, s8                      # append the PendingAttestation: the end of the list's entries
    ld      t1, 0(t0)
    ld      t2, 8(t0)
    add     t3, s1, t1
3:  beqz    t2, 4f
    ld      t4, 0(t3)
    add     t3, t3, t4
    addi    t2, t2, -1
    j       3b
4:  li      t4, BeaconState_previous_epoch_attestations
    bne     s8, t4, 41f
    LDQ     t5, s1, BeaconState_current_epoch_attestations  # the list ends where the next part starts
    j       42f
41: ld      t5, 0(s1)                       # or at the end of the value
42: add     t5, s1, t5
    LDQ     t6, s2, Attestation_aggregation_bits + 8
    addi    t2, t6, 7
    srli    t2, t2, 3                       # the bytes of aggregation_bits
    li      t4, PendingAttestation__fixed + 7
    add     t4, t4, t2
    andi    t4, t4, -8                      # the PendingAttestation's size
    add     t1, t3, t4
    bltu    t5, t1, 9f                      # no room: the state is unchanged
    beqz    t2, 43f
    add     t1, t3, t4                      # zero the padding after the bit bytes
    sd      zero, -8(t1)
43: sd      t4, 0(t3)                       # size; aggregation_bits at the end of the fixed part
    li      t1, PendingAttestation__fixed
    sd      t1, PendingAttestation_aggregation_bits(t3)
    sd      t6, (PendingAttestation_aggregation_bits + 8)(t3)
    LDQ     t1, s1, BeaconState_slot        # inclusion_delay = state.slot - data.slot
    ld      t0, (Attestation_data + AttestationData_slot)(s2)
    sub     t1, t1, t0
    sd      t1, PendingAttestation_inclusion_delay(t3)
    ld      t1, (L + 32)(sp)
    sd      t1, PendingAttestation_proposer_index(t3)
    sd      t3, (L + 48)(sp)
    sd      t2, (L + 56)(sp)
    addi    a0, t3, PendingAttestation_data
    addi    a1, s2, Attestation_data
    li      a2, AttestationData__mem
    call    lantern_copy
    ld      a0, (L + 48)(sp)
    addi    a0, a0, PendingAttestation__fixed
    PART    a1, t0, s2, Attestation_aggregation_bits
    ld      a2, (L + 56)(sp)
    call    lantern_copy
    add     t0, s1, s8                      # the count, last
    ld      t1, 8(t0)
    addi    t1, t1, 1
    sd      t1, 8(t0)
8:  li      a0, LANTERN_OK
7:  LEAVE 64
5:  li      a0, LANTERN_INVALID_OVERFLOW
6:  sd      a0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 64
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END process_attestation
.else
/*
 * s1 state, s2 attestation, s3 config, s4 scratch, s5 result, s6 scratch size, s7 n,
 * s8 committee indices, s9 committee, s10 committee offset.
 * Locals: L previous epoch, L+8 current epoch, L+16 committees per slot, L+24 committee index,
 * L+32 inclusion delay, L+40 valid, L+48 flags (FLAGS_BYTES), L+96 proposer, L+104 base reward,
 * L+112 index, L+120 proposer reward numerator, L+128 flag, L+136 cursor end, L+144 the indexed
 * attestation, L+152 the attesting list, L+160 the scratch size callees get, L+168 participation,
 * L+176 base reward per increment.
 */
/* process_attestation of the spec: lantern_attestation_memo with a base reward factor of its own. */
SPEC_FUNCTION process_attestation
    ENTER 16
    sd      zero, L(sp)
    addi    a5, sp, L
    call    lantern_attestation_memo
    LEAVE 16
SPEC_END process_attestation

/*
 * process_attestation, with a5 the address of the block's get_base_reward_per_increment(state):
 * 0 until an attestation finds it, which stores it there. The operations of one block change no
 * effective balance and no active validator of the current epoch, so its attestations share it.
 */
LOCAL_FUNCTION lantern_attestation_memo
    ENTER 192
    sd      a5, (L + 184)(sp)
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    NEED_SCRATCH_B s4, s1, 10, ATTEST_EXTRA, 9f
    sd      zero, 0(s5)
    ld      s6, 0(s4)
    LDQ     s7, s1, BeaconState_validators + 8
    li      t0, CIDX_BYTES                  # own scratch at the end: committee indices, committee, indexed attestation, attesting
    sub     t1, s6, t0
    add     s8, s4, t1
    sd      t0, 0(s8)
    slli    t2, s7, 3
    addi    t2, t2, LIST_FIXED              # L(n)
    sub     t1, t1, t2
    add     s9, s4, t1
    sd      t2, 0(s9)
    li      t3, IndexedAttestation__fixed + 8
    add     t3, t3, t2
    sub     t1, t1, t3
    add     t4, s4, t1
    sd      t3, 0(t4)
    sd      t4, (L + 144)(sp)
    sub     t1, t1, t2
    add     t4, s4, t1
    sd      t2, 0(t4)
    sd      t4, (L + 152)(sp)
    sd      t1, (L + 160)(sp)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_previous_epoch
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_get_current_epoch
    li      a0, LANTERN_INVALID_ATTESTATION
    ld      t0, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s2)
    ld      t1, L(sp)
    ld      t2, (L + 8)(sp)
    beq     t0, t1, 10f                     # assert data.target.epoch in (previous, current)
    bne     t0, t2, 6f
10: ld      t1, (Attestation_data + AttestationData_slot)(s2)
    srli    t2, t1, LOG2_SLOTS_PER_EPOCH    # assert data.target.epoch == compute_epoch_at_slot(data.slot)
    bne     t0, t2, 6f
    addi    t2, t1, MIN_ATTESTATION_INCLUSION_DELAY     # assert data.slot + MIN_ATTESTATION_INCLUSION_DELAY <= state.slot
    bltu    t2, t1, 5f
    LDQ     t3, s1, BeaconState_slot
    bgtu    t2, t3, 6f
.if FORK < FORK_DENEB
    addi    t2, t1, SLOTS_PER_EPOCH         # assert state.slot <= data.slot + SLOTS_PER_EPOCH
    bltu    t2, t1, 5f
    bgtu    t3, t2, 6f
.endif
.if FORK >= FORK_ELECTRA
    ld      t2, (Attestation_data + AttestationData_index)(s2)
    bnez    t2, 6f                          # assert data.index == 0
    addi    a0, s2, Attestation_committee_bits
    mv      a1, s8
    call    lantern_get_committee_indices
    li      s10, 0                          # committee_offset
    addi    t0, s8, LIST_FIXED
    ld      t1, LIST_COUNT(s8)
    slli    t1, t1, 3
    add     t1, t0, t1
    sd      t1, (L + 136)(sp)
    sd      t0, (L + 112)(sp)               # the cursor over committee indices
1:  ld      t0, (L + 112)(sp)
    ld      t1, (L + 136)(sp)
    bgeu    t0, t1, 3f
    ld      t1, 0(t0)
    addi    t0, t0, 8
    sd      t0, (L + 112)(sp)
    sd      t1, (L + 24)(sp)
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # assert committee_index < get_committee_count_per_slot(...)
    addi    a1, s2, (Attestation_data + AttestationData_target + Checkpoint_epoch)
    mv      a3, s4
    addi    a4, sp, (L + 16)
    ld      a2, CONFIG_COMMITTEE_CACHE(s3)
    call    lantern_get_committee_count_per_slot
    bnez    a0, 7f
    ld      t0, (L + 24)(sp)
    ld      t1, (L + 16)(sp)
    li      a0, LANTERN_INVALID_ATTESTATION
    bgeu    t0, t1, 6f
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1
    addi    a1, s2, (Attestation_data + AttestationData_slot)
    addi    a2, sp, (L + 24)
    mv      a4, s4
    mv      a5, s9
    ld      a3, CONFIG_COMMITTEE_CACHE(s3)
    call    lantern_get_beacon_committee
    CHECK_STATUS s5, 7f, 8f
    PART    t1, t2, s2, Attestation_aggregation_bits
    ld      t0, LIST_COUNT(s9)
    li      t3, 0                           # committee_attesters
2:  beqz    t0, 25f
    li      a0, LANTERN_INVALID_ATTESTATION # aggregation_bits[committee_offset + index]
    bgeu    s10, t2, 6f
    srli    t4, s10, 3
    add     t4, t1, t4
    lbu     t4, 0(t4)
    andi    t5, s10, 7
    srl     t4, t4, t5
    andi    t4, t4, 1
    add     t3, t3, t4
    addi    s10, s10, 1
    addi    t0, t0, -1
    j       2b
25: li      a0, LANTERN_INVALID_ATTESTATION
    beqz    t3, 6f                          # assert len(committee_attesters) > 0
    j       1b
3:  LDQ     t0, s2, Attestation_aggregation_bits + 8
    li      a0, LANTERN_INVALID_ATTESTATION # assert len(attestation.aggregation_bits) == committee_offset
    bne     t0, s10, 6f
.else
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # assert data.index < get_committee_count_per_slot(state, data.target.epoch)
    addi    a1, s2, (Attestation_data + AttestationData_target + Checkpoint_epoch)
    mv      a3, s4
    addi    a4, sp, (L + 16)
    ld      a2, CONFIG_COMMITTEE_CACHE(s3)
    call    lantern_get_committee_count_per_slot
    bnez    a0, 7f
    ld      t0, (Attestation_data + AttestationData_index)(s2)
    ld      t1, (L + 16)(sp)
    li      a0, LANTERN_INVALID_ATTESTATION
    bgeu    t0, t1, 6f
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # committee = get_beacon_committee(state, data.slot, data.index)
    addi    a1, s2, (Attestation_data + AttestationData_slot)
    addi    a2, s2, (Attestation_data + AttestationData_index)
    mv      a4, s4
    mv      a5, s9
    ld      a3, CONFIG_COMMITTEE_CACHE(s3)
    call    lantern_get_beacon_committee
    CHECK_STATUS s5, 7f, 8f
    LDQ     t0, s2, Attestation_aggregation_bits + 8
    ld      t1, LIST_COUNT(s9)
    li      a0, LANTERN_INVALID_ATTESTATION # assert len(attestation.aggregation_bits) == len(committee)
    bne     t0, t1, 6f
.endif
    LDQ     t0, s1, BeaconState_slot
    ld      t1, (Attestation_data + AttestationData_slot)(s2)
    sub     t0, t0, t1
    sd      t0, (L + 32)(sp)
    li      t0, FLAGS_BYTES
    sd      t0, (L + 48)(sp)
    mv      a0, s1                          # participation_flag_indices
    addi    a1, s2, Attestation_data
    addi    a2, sp, (L + 32)
    addi    a3, sp, (L + 48)
    call    lantern_get_attestation_participation_flag_indices
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # assert is_valid_indexed_attestation(state, get_indexed_attestation(...))
    mv      a1, s2
    mv      a3, s4
    ld      a4, (L + 144)(sp)
    ld      a2, CONFIG_COMMITTEE_CACHE(s3)
    call    lantern_get_indexed_attestation
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1
    ld      a1, (L + 144)(sp)
    mv      a3, s4
    addi    a4, sp, (L + 40)
    ld      a2, CONFIG_PUBKEY_CACHE(s3)
    mv      a5, s2
    ld      a6, CONFIG_COMMITTEE_CACHE(s3)
    call    lantern_indexed_attestation_valid
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 40)(sp)
    li      a0, LANTERN_INVALID_ATTESTATION
    beqz    t0, 6f
    ld      t0, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s2)
    ld      t1, (L + 8)(sp)
    bne     t0, t1, 31f
    PART    t0, t1, s1, BeaconState_current_epoch_participation
    j       32f
31: PART    t0, t1, s1, BeaconState_previous_epoch_participation
32: sd      t0, (L + 168)(sp)
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1                          # for index in get_attesting_indices(state, attestation)
    mv      a1, s2
    mv      a3, s4
    ld      a4, (L + 152)(sp)
    ld      a2, CONFIG_COMMITTEE_CACHE(s3)
    call    lantern_get_attesting_indices
    CHECK_STATUS s5, 7f, 8f
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    ld      t0, (L + 184)(sp)               # get_base_reward's factor: once for every attestation of the block
    ld      t1, 0(t0)
    sd      t1, (L + 176)(sp)
    bnez    t1, 47f
    mv      a0, s1
    mv      a1, s4
    addi    a2, sp, (L + 176)
    call    lantern_get_base_reward_per_increment
    bnez    a0, 7f
    ld      t0, (L + 184)(sp)
    ld      t1, (L + 176)(sp)
    sd      t1, 0(t0)
47:
    sd      zero, (L + 120)(sp)
    ld      s8, (L + 152)(sp)               # the attesting list; the committee indices are done
    addi    s9, s8, LIST_FIXED
    ld      t0, LIST_COUNT(s8)
    slli    t0, t0, 3
    add     t0, s9, t0
    sd      t0, (L + 136)(sp)
4:  ld      t0, (L + 136)(sp)
    bgeu    s9, t0, 45f
    ld      t0, 0(s9)
    addi    s9, s9, 8
    sd      t0, (L + 112)(sp)
    li      s10, 0                          # for flag_index, weight in enumerate(PARTICIPATION_FLAG_WEIGHTS)
41: li      t0, 3
    bgeu    s10, t0, 4b
    ld      t0, (L + 48 + LIST_COUNT)(sp)   # flag_index in participation_flag_indices
    addi    t1, sp, (L + 48 + LIST_FIXED)
42: beqz    t0, 44f
    ld      t2, 0(t1)
    addi    t1, t1, 8
    beq     t2, s10, 43f
    addi    t0, t0, -1
    j       42b
43: sd      s10, (L + 128)(sp)
    ld      t0, (L + 168)(sp)               # and not has_flag(epoch_participation[index], flag_index)
    ld      t1, (L + 112)(sp)
    add     a0, t0, t1
    addi    a1, sp, (L + 128)
    addi    a2, sp, (L + 40)
    call    lantern_has_flag
    ld      t0, (L + 40)(sp)
    bnez    t0, 44f
    ld      t0, (L + 168)(sp)               # epoch_participation[index] = add_flag(...)
    ld      t1, (L + 112)(sp)
    add     a0, t0, t1
    addi    a1, sp, (L + 128)
    mv      a2, a0
    call    lantern_add_flag
    PART    t0, t1, s1, BeaconState_validators
    ld      t2, (L + 112)(sp)               # proposer_reward_numerator += get_base_reward(state, index) * weight
    slli    t2, t2, 7
    add     t0, t0, t2
    ld      t0, Validator_effective_balance(t0)
    li      t1, EFFECTIVE_BALANCE_INCREMENT
    divu    t0, t0, t1                      # increments * base_reward_per_increment
    ld      t1, (L + 176)(sp)
    mul     t0, t0, t1
    li      t1, TIMELY_SOURCE_WEIGHT        # the source and head weights are equal
    li      t2, TIMELY_TARGET_FLAG_INDEX
    bne     s10, t2, 46f
    li      t1, TIMELY_TARGET_WEIGHT
46: mul     t0, t0, t1
    ld      t1, (L + 120)(sp)
    add     t1, t1, t0
    bltu    t1, t0, 5f
    sd      t1, (L + 120)(sp)
44: addi    s10, s10, 1
    j       41b
45: ld      t0, (L + 120)(sp)               # proposer_reward = numerator // proposer_reward_denominator
    li      t1, ((WEIGHT_DENOMINATOR - PROPOSER_WEIGHT) * WEIGHT_DENOMINATOR / PROPOSER_WEIGHT)
    divu    t0, t0, t1
    sd      t0, (L + 120)(sp)
.if FORK >= FORK_FULU
    mv      a0, s1
    addi    a1, sp, (L + 96)
    call    lantern_get_beacon_proposer_index
.else
    ld      t0, (L + 160)(sp)
    sd      t0, 0(s4)
    mv      a0, s1
    mv      a1, s4
    addi    a2, sp, (L + 96)
    call    lantern_get_beacon_proposer_index
    bnez    a0, 7f
.endif
    mv      a0, s1
    addi    a1, sp, (L + 96)
    addi    a2, sp, (L + 120)
    call    lantern_increase_balance
8:  li      a0, LANTERN_OK
7:  LEAVE 192
5:  li      a0, LANTERN_INVALID_OVERFLOW
6:  sd      a0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 192
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 192
END_FUNCTION lantern_attestation_memo
.endif

.if TIMELY_SOURCE_WEIGHT != TIMELY_HEAD_WEIGHT
.error "lantern_process_attestation takes the source weight for the head flag"
.endif
