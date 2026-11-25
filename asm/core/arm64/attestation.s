/*
 * Committees and attestations, ARM64. Requirements: docs/reference/block-processing.md.
 */

.set CIDX_BYTES, LIST_FIXED + 8 * MAX_COMMITTEES_PER_SLOT     /* an IndexList of committee indices */
.set FLAGS_BYTES, LIST_FIXED + 8 * 3                            /* an IndexList of participation flags */
.set ATTEST_EXTRA, 2 * CIDX_BYTES + IndexedAttestation__fixed + 8

/* ---------------------------------------------------------------- Sorting */

/* Sift the entry at root down the heap of entries below end, at x0. Uses x5-x8. */
.macro SIFT root, end
97: lsl     x5, \root, #1
    add     x5, x5, #1                      /* child = 2 * root + 1 */
    cmp     x5, \end
    b.hs    98f
    ldr     x7, [x0, x5, lsl #3]
    add     x6, x5, #1
    cmp     x6, \end
    b.hs    96f
    ldr     x8, [x0, x6, lsl #3]
    cmp     x8, x7                          /* the larger child */
    csel    x5, x6, x5, hi
    csel    x7, x8, x7, hi
96: ldr     x8, [x0, \root, lsl #3]
    cmp     x8, x7
    b.hs    98f
    str     x7, [x0, \root, lsl #3]
    str     x8, [x0, x5, lsl #3]
    mov     \root, x5
    b       97b
98:
.endm

/* L0: sort the x1 u64 entries at x0, ascending (heapsort). A leaf; uses x2-x8. */
LOCAL_FUNCTION lantern_sort_u64
    UNWIND_END_PROLOGUE
    cmp     x1, #2
    b.lo    9f
    lsr     x2, x1, #1
1:  cbz     x2, 2f
    sub     x2, x2, #1
    mov     x3, x2
    SIFT    x3, x1
    b       1b
2:  mov     x4, x1
3:  sub     x4, x4, #1
    cbz     x4, 9f
    ldr     x5, [x0]
    ldr     x6, [x0, x4, lsl #3]
    str     x6, [x0]
    str     x5, [x0, x4, lsl #3]
    mov     x3, #0
    SIFT    x3, x4
    b       3b
9:  ret
END_FUNCTION lantern_sort_u64

/* ---------------------------------------------------------------- Committees */

.if FORK >= FORK_ELECTRA
SPEC_LEAF get_committee_indices
    mov     x2, #LIST_FIXED
    str     x2, [x1, #LIST_OFFSET]
    add     x2, x1, #LIST_FIXED
    mov     x3, #0                          /* bit */
1:  cmp     x3, #MAX_COMMITTEES_PER_SLOT
    b.hs    2f
    lsr     x4, x3, #3
    ldrb    w4, [x0, x4]
    and     x5, x3, #7
    lsr     w4, w4, w5
    tbz     w4, #0, 3f
    str     x3, [x2], #8
3:  add     x3, x3, #1
    b       1b
2:  add     x3, x1, #LIST_FIXED
    sub     x2, x2, x3
    lsr     x2, x2, #3
    str     x2, [x1, #LIST_COUNT]
    RETURN_OK
SPEC_END get_committee_indices
.endif

/*
 * L0: the key of epoch x1 of state x0 at x2 (CommitteeEntry_seed onward): get_seed with
 * DOMAIN_BEACON_ATTESTER, the decision root, the genesis validators root. x19 state, x20 epoch,
 * x21 key. Locals: L epoch, L+8 domain type.
 */
LOCAL_FUNCTION lantern_committee_key
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    str     x20, [sp, #L]
    mov     w9, #DOMAIN_BEACON_ATTESTER
    str     w9, [sp, #(L + 8)]
    mov     x0, x19
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    mov     x3, x21
    bl      lantern_get_seed
    cbnz    x0, 7f
    add     x9, x21, #32                    /* the decision root: the last slot of epoch E - 5 */
    stp     xzr, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    mov     x10, #0
    cmp     x20, #5
    b.lo    1f
    sub     x10, x20, #4
    lsl     x10, x10, #LOG2_SLOTS_PER_EPOCH
    sub     x10, x10, #1
1:  LDQ     x11, x19, BeaconState_slot      /* get_block_root_at_slot: before the state's slot, in range */
    cmp     x10, x11
    b.hs    2f
    MOVQ    x12, SLOTS_PER_HISTORICAL_ROOT
    add     x12, x10, x12
    cmp     x11, x12
    b.hi    2f
    and     x10, x10, #(SLOTS_PER_HISTORICAL_ROOT - 1)
    ADDQ    x11, x19, BeaconState_block_roots
    add     x11, x11, x10, lsl #5
    COPY32  x9, x11
2:  add     x9, x21, #64
    ADDQ    x11, x19, BeaconState_genesis_validators_root
    COPY32  x9, x11
    mov     x0, #LANTERN_OK
7:  LEAVE 16
END_FUNCTION lantern_committee_key

/* L0: x0 = the valid entry of cache x0 for epoch x1 and the key at x2, or 0. A leaf. */
LOCAL_FUNCTION lantern_committee_find
    UNWIND_END_PROLOGUE
    ldr     x3, [x0, #CommitteeCache_validators]
    lsl     x3, x3, #3
    add     x3, x3, #(CommitteeEntry__mem + LIST_FIXED)
    add     x4, x0, #CommitteeCache_entries
    mov     x5, #COMMITTEE_CACHE_ENTRIES
1:  ldr     x6, [x4, #CommitteeEntry_valid]
    cbz     x6, 3f
    ldr     x6, [x4, #CommitteeEntry_epoch]
    cmp     x6, x1
    b.ne    3f
    mov     x6, #0                          /* the 96 bytes of the key */
    add     x7, x4, #CommitteeEntry_seed
2:  ldr     x8, [x7, x6]
    ldr     x9, [x2, x6]
    cmp     x8, x9
    b.ne    3f
    add     x6, x6, #8
    cmp     x6, #96
    b.lo    2b
    mov     x0, x4
    ret
3:  add     x4, x4, x3
    subs    x5, x5, #1
    b.ne    1b
    mov     x0, #0
    ret
END_FUNCTION lantern_committee_find

/* Locals: sp+16 size. */
SPEC_FUNCTION committee_cache_size
    FRAME 16
    ldr     x9, [x0]
    lsl     x9, x9, #3
    add     x9, x9, #(CommitteeEntry__mem + LIST_FIXED)
    MOVQ    x10, KEYSUM_BLOCK_BYTES         /* and the entry's block of key sums */
    add     x9, x9, x10
    mov     x10, #COMMITTEE_CACHE_ENTRIES
    mul     x9, x9, x10
    add     x9, x9, #COMMITTEE_CACHE_FIXED
    str     x9, [x1]
    mov     x0, #LANTERN_OK
    UNFRAME 16
SPEC_END committee_cache_size

SPEC_FUNCTION committee_cache_init
    FRAME 16
    ldr     x9, [x0]
    lsl     x10, x9, #3
    add     x10, x10, #(CommitteeEntry__mem + LIST_FIXED)   /* an entry and its list */
    MOVQ    x11, KEYSUM_BLOCK_BYTES         /* and its block of key sums */
    add     x11, x10, x11
    mov     x13, #COMMITTEE_CACHE_ENTRIES
    mul     x11, x11, x13
    add     x11, x11, #COMMITTEE_CACHE_FIXED
    ldr     x12, [x1, #CommitteeCache_size]
    cmp     x12, x11
    b.lo    9f
    str     x9, [x1, #CommitteeCache_validators]
    str     xzr, [x1, #CommitteeCache_next]
    add     x12, x1, #CommitteeCache_entries
    mov     x11, #COMMITTEE_CACHE_ENTRIES
1:  str     xzr, [x12, #CommitteeEntry_valid]
    add     x12, x12, x10
    subs    x11, x11, #1
    b.ne    1b
    mov     x0, #LANTERN_OK
    UNFRAME 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 16
SPEC_END committee_cache_init

SPEC_FUNCTION pubkey_cache_size
    FRAME 16
    ldr     x9, [x0]
    mov     x10, #CRYPTO_BLS_ENTRY_BYTES
    mul     x9, x9, x10
    add     x9, x9, #CRYPTO_BLS_CACHE_FIXED
    str     x9, [x1]
    mov     x0, #LANTERN_OK
    UNFRAME 16
SPEC_END pubkey_cache_size

/* A BlsKeyCache of asm-crypto whose keys are those of a state's validators: key_stride Validator__mem. */
SPEC_FUNCTION pubkey_cache_init
    FRAME 16
    ldr     x9, [x0]
    mov     x10, #CRYPTO_BLS_ENTRY_BYTES
    mul     x11, x9, x10
    add     x11, x11, #CRYPTO_BLS_CACHE_FIXED
    ldr     x12, [x1]                       /* size */
    cmp     x12, x11
    b.lo    9f
    mov     x11, #Validator__mem
    str     x11, [x1, #CRYPTO_BLS_CACHE_KEY_STRIDE]
    mov     x11, #CRYPTO_BLS_CACHE_FIXED
    str     x11, [x1, #CRYPTO_BLS_CACHE_OFFSET]
    str     x9, [x1, #CRYPTO_BLS_CACHE_COUNT]
    add     x12, x1, #CRYPTO_BLS_CACHE_FIXED   /* every entry empty */
1:  cbz     x9, 2f
    str     xzr, [x12, #CRYPTO_BLS_ENTRY_STATUS]
    add     x12, x12, x10
    sub     x9, x9, #1
    b       1b
2:  mov     x0, #LANTERN_OK
    UNFRAME 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 16
SPEC_END pubkey_cache_init

/* x19 state, x20 epoch pointer, x21 scratch, x22 out, x23 list, x24 cache. Locals: L the key (96). */
SPEC_FUNCTION get_committee_count_per_slot
    ENTER 96
    mov     x19, x0
    mov     x20, x1
    mov     x24, x2
    mov     x21, x3
    mov     x22, x4
    NEED_SCRATCH x21, x19, 1, 9f
    cbz     x24, 1f
    mov     x0, x19                         /* an entry of the cache: its count */
    ldr     x1, [x20]
    add     x2, sp, #L
    bl      lantern_committee_key
    cbnz    x0, 1f
    mov     x0, x24
    ldr     x1, [x20]
    add     x2, sp, #L
    bl      lantern_committee_find
    cbz     x0, 1f
    ldr     x9, [x0, #CommitteeEntry_count]
    b       2f
1:  LDQ     x9, x19, BeaconState_validators + 8
    ldr     x10, [x21]
    SCRATCH_LIST x23, x21, x10, 0, x9
    mov     x0, x19
    mov     x1, x20
    mov     x2, x23
    bl      lantern_get_active_validator_indices
    cbnz    x0, 7f
    ldr     x9, [x23, #LIST_COUNT]
2:  lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    mov     x10, #TARGET_COMMITTEE_SIZE
    udiv    x9, x9, x10
    mov     x10, #MAX_COMMITTEES_PER_SLOT
    cmp     x9, x10
    csel    x9, x9, x10, lo
    cmp     x9, #1
    csinc   x9, x9, xzr, hs                 /* max(1, ...) */
    str     x9, [x22]
    mov     x0, #LANTERN_OK
7:  LEAVE 96
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 96
SPEC_END get_committee_count_per_slot

/*
 * x19 indices, x20 seed, x21 i, x22 end, x23 scratch, x24 out entries, x25 scratch size.
 * Locals: L len(indices), L+8 i, L+16 shuffled.
 */
SPEC_FUNCTION compute_committee
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x23, x4
    ldr     x9, [x19, #LIST_COUNT]          /* n */
    str     x9, [sp, #L]
    ldr     x10, [x2]                       /* index */
    ldr     x11, [x3]                       /* count */
    cbz     x11, 8f
    mul     x12, x9, x10
    udiv    x21, x12, x11                   /* start = len(indices) * index // count */
    add     x10, x10, #1
    mul     x12, x9, x10
    udiv    x22, x12, x11                   /* end = len(indices) * (index + 1) // count */
    sub     x12, x22, x21
    lsl     x13, x12, #3
    add     x13, x13, #LIST_FIXED
    ldr     x14, [x5, #LIST_SIZE]
    cmp     x14, x13
    b.lo    9f
    mov     x13, #LIST_FIXED
    str     x13, [x5, #LIST_OFFSET]
    str     x12, [x5, #LIST_COUNT]
    add     x24, x5, #LIST_FIXED
    ldr     x25, [x23]
1:  cmp     x21, x22
    b.hs    2f
    str     x21, [sp, #(L + 8)]
    str     x25, [x23]
    add     x0, sp, #(L + 8)                /* indices[compute_shuffled_index(i, len(indices), seed)] */
    add     x1, sp, #L
    mov     x2, x20
    mov     x3, x23
    add     x4, sp, #(L + 16)
    bl      lantern_compute_shuffled_index
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 16)]
    add     x10, x19, #LIST_FIXED
    ldr     x9, [x10, x9, lsl #3]
    str     x9, [x24], #8
    add     x21, x21, #1
    b       1b
2:  mov     x0, #LANTERN_OK
7:  LEAVE 32
8:  mov     x0, #LANTERN_INVALID_SHUFFLED_INDEX
    LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END compute_committee

/*
 * x19 state, x20 slot, x21 index pointer, x22 scratch, x23 out, x24 scratch size, x25 n, x26 list,
 * x27 cache, x28 the entry. Locals: L epoch, L+8 committees per slot, L+16 domain type,
 * L+24 seed (32), L+56 index, L+64 count, L+72 the entry's key (96).
 */
SPEC_FUNCTION get_beacon_committee
    ENTER 176
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    mov     x27, x3
    mov     x22, x4
    mov     x23, x5
    NEED_SCRATCH x22, x19, 2, 9f
    ldr     x24, [x22]
    LDQ     x25, x19, BeaconState_validators + 8
    lsr     x9, x20, #LOG2_SLOTS_PER_EPOCH  /* epoch = compute_epoch_at_slot(slot) */
    str     x9, [sp, #L]
    mov     x0, x19
    add     x1, sp, #L
    mov     x2, x27
    mov     x3, x22
    add     x4, sp, #(L + 8)
    bl      lantern_get_committee_count_per_slot
    cbnz    x0, 7f
    cbz     x27, 20f
    mov     x0, x19                         /* the cache's entry of the epoch */
    ldr     x1, [sp, #L]
    add     x2, sp, #(L + 72)
    bl      lantern_committee_key
    cbnz    x0, 20f
    mov     x0, x27
    ldr     x1, [sp, #L]
    add     x2, sp, #(L + 72)
    bl      lantern_committee_find
    mov     x28, x0
    cbnz    x28, 30f
    SCRATCH_LIST x26, x22, x24, 0, x25      /* a new entry: the active validators, shuffled */
    mov     x0, x19
    add     x1, sp, #L
    mov     x2, x26
    bl      lantern_get_active_validator_indices
    cbnz    x0, 7f
    ldr     x9, [x26, #LIST_COUNT]
    ldr     x10, [x27, #CommitteeCache_validators]
    cmp     x9, x10
    b.hi    21f
    ldr     x11, [x27, #CommitteeCache_next]
    lsl     x12, x10, #3
    add     x12, x12, #(CommitteeEntry__mem + LIST_FIXED)
    madd    x28, x11, x12, x27
    add     x28, x28, #CommitteeCache_entries
    mov     x13, #COMMITTEE_CACHE_ENTRIES   /* its block of key sums: each status 0 */
    mul     x13, x13, x12
    add     x13, x13, x27
    add     x13, x13, #CommitteeCache_entries
    MOVQ    x14, KEYSUM_BLOCK_BYTES
    madd    x13, x11, x14, x13
    MOVQ    x14, SLOTS_PER_EPOCH * MAX_COMMITTEES_PER_SLOT
13: str     xzr, [x13, #KeySum_status]
    add     x13, x13, #KeySum__mem
    subs    x14, x14, #1
    b.ne    13b
    add     x11, x11, #1
    cmp     x11, #COMMITTEE_CACHE_ENTRIES
    csel    x11, x11, xzr, lo
    str     x11, [x27, #CommitteeCache_next]
    str     xzr, [x28, #CommitteeEntry_valid]
    str     x9, [x28, #CommitteeEntry_count]
    lsl     x13, x10, #3
    add     x13, x13, #LIST_FIXED
    str     x13, [x28, #(CommitteeEntry__mem + LIST_SIZE)]
    SCRATCH_GIVE x22, x24, 1, x25
    add     x0, x28, #CommitteeEntry_count
    add     x1, sp, #(L + 72)
    mov     x2, x22
    add     x3, x28, #CommitteeEntry__mem
    bl      lantern_compute_shuffled_permutation
    cbnz    x0, 7f
    add     x9, x28, #(CommitteeEntry__mem + LIST_FIXED)    /* entry i = indices[permutation[i]] */
    add     x10, x26, #LIST_FIXED
    ldr     x11, [x28, #CommitteeEntry_count]
    mov     x12, #0
11: cmp     x12, x11
    b.hs    12f
    ldr     x13, [x9, x12, lsl #3]
    ldr     x13, [x10, x13, lsl #3]
    str     x13, [x9, x12, lsl #3]
    add     x12, x12, #1
    b       11b
12: ldr     x9, [sp, #L]
    str     x9, [x28, #CommitteeEntry_epoch]
    add     x9, x28, #CommitteeEntry_seed
    add     x10, sp, #(L + 72)
    COPY32  x9, x10
    add     x9, x9, #32
    add     x10, x10, #32
    COPY32  x9, x10
    add     x9, x9, #32
    add     x10, x10, #32
    COPY32  x9, x10
    mov     x9, #1
    str     x9, [x28, #CommitteeEntry_valid]
30: ldr     x9, [sp, #(L + 8)]              /* the slice of the entry: index, count, start, end */
    and     x10, x20, #(SLOTS_PER_EPOCH - 1)
    mul     x10, x10, x9
    ldr     x11, [x21]
    adds    x10, x10, x11
    b.cs    6f
    lsl     x9, x9, #LOG2_SLOTS_PER_EPOCH
    ldr     x11, [x28, #CommitteeEntry_count]
    mul     x12, x11, x10
    udiv    x12, x12, x9
    add     x10, x10, #1
    mul     x13, x11, x10
    udiv    x13, x13, x9
    sub     x14, x13, x12
    cbz     x14, 31f
    cmp     x13, x11                        /* past the list: compute_shuffled_index raises */
    b.hi    5f
31: lsl     x15, x14, #3
    add     x15, x15, #LIST_FIXED
    ldr     x16, [x23, #LIST_SIZE]
    cmp     x16, x15
    b.lo    9f
    mov     x15, #LIST_FIXED
    str     x15, [x23, #LIST_OFFSET]
    str     x14, [x23, #LIST_COUNT]
    add     x15, x28, #(CommitteeEntry__mem + LIST_FIXED)
    add     x15, x15, x12, lsl #3
    add     x16, x23, #LIST_FIXED
32: cbz     x14, 33f
    ldr     x9, [x15], #8
    str     x9, [x16], #8
    sub     x14, x14, #1
    b       32b
33: mov     x0, #LANTERN_OK
    LEAVE 176
20: SCRATCH_LIST x26, x22, x24, 0, x25      /* no cache */
    mov     x0, x19
    add     x1, sp, #L
    mov     x2, x26
    bl      lantern_get_active_validator_indices
    cbnz    x0, 7f
21: mov     w9, #DOMAIN_BEACON_ATTESTER
    str     w9, [sp, #(L + 16)]
    mov     x0, x19
    add     x1, sp, #L
    add     x2, sp, #(L + 16)
    add     x3, sp, #(L + 24)
    bl      lantern_get_seed
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 8)]              /* index = (slot % SLOTS_PER_EPOCH) * committees_per_slot + index */
    and     x10, x20, #(SLOTS_PER_EPOCH - 1)
    mul     x10, x10, x9
    ldr     x11, [x21]
    adds    x10, x10, x11
    b.cs    6f
    str     x10, [sp, #(L + 56)]
    lsl     x9, x9, #LOG2_SLOTS_PER_EPOCH   /* count = committees_per_slot * SLOTS_PER_EPOCH */
    str     x9, [sp, #(L + 64)]
    SCRATCH_GIVE x22, x24, 1, x25
    mov     x0, x26
    add     x1, sp, #(L + 24)
    add     x2, sp, #(L + 56)
    add     x3, sp, #(L + 64)
    mov     x4, x22
    mov     x5, x23
    bl      lantern_compute_committee
7:  LEAVE 176
5:  mov     x0, #LANTERN_INVALID_SHUFFLED_INDEX
    LEAVE 176
6:  mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 176
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 176
SPEC_END get_beacon_committee

.if FORK >= FORK_ELECTRA
/*
 * x19 state, x20 attestation, x21 scratch, x22 out, x23 scratch size, x24 n, x25 committee indices,
 * x26 committee, x27 committee offset, x28 committee index cursor.
 * Locals: L committee index, L+8 the scratch size the callee gets, L+16 bits, L+24 bit count, L+32 cursor end,
 * L+40 the committee cache.
 */
SPEC_FUNCTION get_attesting_indices
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    str     x2, [sp, #(L + 40)]             /* the cache */
    mov     x21, x3
    mov     x22, x4
    NEED_SCRATCH_B x21, x19, 3, CIDX_BYTES, 9f
    LDQ     x24, x19, BeaconState_validators + 8
    lsl     x9, x24, #3                     /* out has room for every validator */
    add     x9, x9, #LIST_FIXED
    ldr     x10, [x22, #LIST_SIZE]
    cmp     x10, x9
    b.lo    9f
    ldr     x23, [x21]
    MOVQ    x9, CIDX_BYTES
    sub     x10, x23, x9
    add     x25, x21, x10                   /* committee indices: the last CIDX_BYTES */
    str     x9, [x25]
    lsl     x11, x24, #3
    add     x11, x11, #LIST_FIXED
    sub     x10, x10, x11
    add     x26, x21, x10                   /* the committee: the L(n) before */
    str     x11, [x26]
    str     x10, [sp, #(L + 8)]
    add     x0, x20, #Attestation_committee_bits
    mov     x1, x25
    bl      lantern_get_committee_indices
    PART    x9, x10, x20, Attestation_aggregation_bits
    str     x9, [sp, #(L + 16)]
    str     x10, [sp, #(L + 24)]
    mov     x9, #LIST_FIXED
    str     x9, [x22, #LIST_OFFSET]
    str     xzr, [x22, #LIST_COUNT]
    mov     x27, #0
    add     x28, x25, #LIST_FIXED
    ldr     x9, [x25, #LIST_COUNT]
    add     x9, x28, x9, lsl #3
    str     x9, [sp, #(L + 32)]
1:  ldr     x9, [sp, #(L + 32)]
    cmp     x28, x9
    b.hs    4f
    ldr     x9, [x28], #8
    str     x9, [sp, #L]
    ldr     x9, [sp, #(L + 8)]
    str     x9, [x21]
    mov     x0, x19                         /* committee = get_beacon_committee(state, data.slot, committee_index) */
    add     x1, x20, #(Attestation_data + AttestationData_slot)
    add     x2, sp, #L
    mov     x4, x21
    mov     x5, x26
    ldr     x3, [sp, #(L + 40)]
    bl      lantern_get_beacon_committee
    cbnz    x0, 7f
    ldr     x9, [x26, #LIST_COUNT]
    add     x10, x26, #LIST_FIXED
    ldr     x11, [sp, #(L + 16)]            /* bits */
    ldr     x12, [sp, #(L + 24)]            /* bit count */
    ldr     x13, [x22, #LIST_COUNT]
    add     x14, x22, #LIST_FIXED
    add     x14, x14, x13, lsl #3
2:  cbz     x9, 3f
    cmp     x27, x12                        /* aggregation_bits[committee_offset + index] */
    b.hs    8f
    lsr     x15, x27, #3
    ldrb    w15, [x11, x15]
    and     x16, x27, #7
    lsr     w15, w15, w16
    ldr     x16, [x10], #8
    tbz     w15, #0, 25f
    str     x16, [x14], #8
    add     x13, x13, #1
25: add     x27, x27, #1
    sub     x9, x9, #1
    b       2b
3:  str     x13, [x22, #LIST_COUNT]
    b       1b
4:  add     x0, x22, #LIST_FIXED            /* a set: ascending */
    ldr     x1, [x22, #LIST_COUNT]
    bl      lantern_sort_u64
    mov     x0, #LANTERN_OK
7:  LEAVE 48
8:  mov     x0, #LANTERN_INVALID_ATTESTATION
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END get_attesting_indices
.else
/*
 * Before electra: the committee of data.index. A PendingAttestation of phase0 has the same
 * aggregation_bits and data, so the function also takes one.
 * x19 state, x20 attestation, x21 scratch, x22 out, x23 scratch size, x24 n, x25 the committee cache,
 * x26 committee.
 */
.if FORK == FORK_PHASE0
.if (PendingAttestation_aggregation_bits != Attestation_aggregation_bits) || (PendingAttestation_data != Attestation_data)
.error "PendingAttestation does not start with the fields of Attestation"
.endif
.endif
SPEC_FUNCTION get_attesting_indices
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x25, x2
    mov     x21, x3
    mov     x22, x4
    NEED_SCRATCH x21, x19, 3, 9f
    LDQ     x24, x19, BeaconState_validators + 8
    lsl     x9, x24, #3                     /* out has room for every validator */
    add     x9, x9, #LIST_FIXED
    ldr     x10, [x22, #LIST_SIZE]
    cmp     x10, x9
    b.lo    9f
    ldr     x23, [x21]
    SCRATCH_LIST x26, x21, x23, 0, x24      /* the committee: the last list */
    SCRATCH_GIVE x21, x23, 1, x24
    mov     x0, x19                         /* committee = get_beacon_committee(state, data.slot, data.index) */
    add     x1, x20, #(Attestation_data + AttestationData_slot)
    add     x2, x20, #(Attestation_data + AttestationData_index)
    mov     x4, x21
    mov     x5, x26
    mov     x3, x25
    bl      lantern_get_beacon_committee
    cbnz    x0, 7f
    PART    x11, x12, x20, Attestation_aggregation_bits
    ldr     x9, [x26, #LIST_COUNT]
    add     x10, x26, #LIST_FIXED
    mov     x13, #LIST_FIXED
    str     x13, [x22, #LIST_OFFSET]
    mov     x13, #0                         /* the count */
    add     x14, x22, #LIST_FIXED
    mov     x27, #0                         /* i */
2:  cmp     x27, x9
    b.hs    3f
    cmp     x27, x12                        /* aggregation_bits[i] */
    b.hs    8f
    lsr     x15, x27, #3
    ldrb    w15, [x11, x15]
    and     x16, x27, #7
    lsr     w15, w15, w16
    ldr     x16, [x10], #8
    tbz     w15, #0, 25f
    str     x16, [x14], #8
    add     x13, x13, #1
25: add     x27, x27, #1
    b       2b
3:  str     x13, [x22, #LIST_COUNT]
    add     x0, x22, #LIST_FIXED            /* a set: ascending */
    mov     x1, x13
    bl      lantern_sort_u64
    mov     x0, #LANTERN_OK
7:  LEAVE 16
8:  mov     x0, #LANTERN_INVALID_ATTESTATION
    LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_attesting_indices
.endif

/*
 * x19 state, x20 attestation, x21 scratch, x22 out, x23 scratch size, x24 n, x25 the attesting list,
 * x26 the committee cache.
 */
SPEC_FUNCTION get_indexed_attestation
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x26, x2
    mov     x21, x3
    mov     x22, x4
    NEED_SCRATCH_B x21, x19, 4, CIDX_BYTES, 9f
    LDQ     x24, x19, BeaconState_validators + 8
    ldr     x23, [x21]
    SCRATCH_LIST x25, x21, x23, 0, x24
    SCRATCH_GIVE x21, x23, 1, x24
    mov     x0, x19
    mov     x1, x20
    mov     x3, x21
    mov     x4, x25
    mov     x2, x26
    bl      lantern_get_attesting_indices
    cbnz    x0, 7f
    ldr     x9, [x25, #LIST_COUNT]          /* out: attesting_indices, data, signature */
    lsl     x10, x9, #3
    MOVQ    x11, IndexedAttestation__fixed
    add     x10, x10, x11
    ldr     x12, [x22]
    cmp     x12, x10
    b.lo    9f
    str     x11, [x22, #IndexedAttestation_attesting_indices]
    str     x9, [x22, #(IndexedAttestation_attesting_indices + 8)]
    add     x0, x22, x11
    add     x1, x25, #LIST_FIXED
    lsl     x2, x9, #3
    bl      lantern_copy
    add     x0, x22, #IndexedAttestation_data
    add     x1, x20, #Attestation_data
    mov     x2, #AttestationData__mem
    bl      lantern_copy
    add     x0, x22, #IndexedAttestation_signature
    add     x1, x20, #Attestation_signature
    mov     x2, #96
    bl      lantern_copy
    mov     x0, #LANTERN_OK
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_indexed_attestation

/*
 * x19 state, x20 indexed attestation, x21 scratch, x22 out, x23 scratch size, x24 keys (a
 * BlsPublicKeyList), x25 indices, x26 count, x27 cache: 0 when it has no entry of the largest
 * index. Locals: L domain type, L+8 domain (32), L+40 message (24 + 32).
 */
.if IndexedAttestation_attesting_indices != CRYPTO_BLS_LIST_OFFSET
.error "an IndexedAttestation must read as a BlsIndexList of its attesting indices"
.endif
SPEC_LEAF is_valid_indexed_attestation
    mov     x5, #0
    mov     x6, #0
    b       lantern_indexed_attestation_valid
SPEC_END is_valid_indexed_attestation

/*
 * L0: is_valid_indexed_attestation with x5 the attestation that the indexed attestation x1
 * is get_indexed_attestation of, with the CommitteeCache x6 (each 0 or not); with both and a
 * PubkeyCache, the keys' sum may come from the cache's key sums (block-processing.md).
 * Locals as is_valid_indexed_attestation's, then L+96 the attestation, L+104 the committee
 * cache, L+112 the keys' sum (G1Point), L+256 its compressed form (48).
 */
LOCAL_FUNCTION lantern_indexed_attestation_valid
    ENTER 304
    mov     x19, x0
    mov     x20, x1
    mov     x27, x2
    mov     x21, x3
    mov     x22, x4
    stp     x5, x6, [sp, #(L + 96)]
    str     xzr, [x22]
    PART    x25, x26, x20, IndexedAttestation_attesting_indices
    cbz     x26, 8f                         /* len(indices) == 0: False */
    mov     x9, #1                          /* indices sorted and unique */
1:  cmp     x9, x26
    b.hs    2f
    sub     x10, x9, #1
    ldr     x11, [x25, x10, lsl #3]
    ldr     x12, [x25, x9, lsl #3]
    cmp     x12, x11
    b.ls    8f
    add     x9, x9, #1
    b       1b
2:  sub     x9, x26, #1                     /* the largest index names a validator */
    ldr     x9, [x25, x9, lsl #3]
    LDQ     x10, x19, BeaconState_validators + 8
    cmp     x9, x10
    b.hs    6f
    cbz     x27, 31f                        /* with a cache that has an entry of every index: no list of keys */
    ldr     x10, [x27, #CRYPTO_BLS_CACHE_COUNT]
    cmp     x9, x10
    b.lo    4f
    mov     x27, #0
31: mov     x9, #48                         /* pubkeys: a BlsPublicKeyList at the end of scratch */
    mul     x9, x9, x26
    add     x9, x9, #(24 + 7)
    and     x9, x9, #-8
    ldr     x23, [x21]
    MOVQ    x10, LANTERN_SCRATCH_FIXED
    add     x10, x10, x9
    cmp     x23, x10
    b.lo    9f
    sub     x10, x23, x9
    add     x24, x21, x10
    str     x9, [x24]
    mov     x11, #24
    str     x11, [x24, #8]
    str     x26, [x24, #16]
    str     x10, [x21]
    add     x11, x24, #24
    mov     x9, #0
3:  cmp     x9, x26
    b.hs    4f
    ldr     x12, [x25, x9, lsl #3]
    PART    x13, x14, x19, BeaconState_validators
    add     x13, x13, x12, lsl #7
    ldp     x14, x15, [x13, #Validator_pubkey]
    stp     x14, x15, [x11]
    ldp     x14, x15, [x13, #(Validator_pubkey + 16)]
    stp     x14, x15, [x11, #16]
    ldp     x14, x15, [x13, #(Validator_pubkey + 32)]
    stp     x14, x15, [x11, #32]
    add     x11, x11, #48
    add     x9, x9, #1
    b       3b
4:  mov     w9, #DOMAIN_BEACON_ATTESTER     /* domain = get_domain(state, DOMAIN_BEACON_ATTESTER, data.target.epoch) */
    str     w9, [sp, #L]
    mov     x0, x19
    add     x1, sp, #L
    add     x2, x20, #(IndexedAttestation_data + AttestationData_target + Checkpoint_epoch)
    mov     x3, x21
    add     x4, sp, #(L + 8)
    bl      lantern_get_domain
    cbnz    x0, 7f
    ADDRESS x0, lantern_type_AttestationData
    add     x1, x20, #IndexedAttestation_data
    add     x2, sp, #(L + 8)
    mov     x3, x21
    add     x4, sp, #(L + 64)
    bl      lantern_compute_signing_root
    cbnz    x0, 7f
    mov     x9, #56
    str     x9, [sp, #(L + 40)]
    mov     x9, #24
    str     x9, [sp, #(L + 48)]
    mov     x9, #32
    str     x9, [sp, #(L + 56)]
    cbnz    x27, 40f
    mov     x0, x24                         /* bls.FastAggregateVerify(pubkeys, signing_root, signature) */
    add     x1, sp, #(L + 40)
    add     x2, x20, #IndexedAttestation_signature
    mov     x3, x21
    mov     x4, x22
    CALL_GLOBAL crypto_bls_fast_aggregate_verify
7:  LEAVE 304
8:  mov     x0, #LANTERN_OK
    LEAVE 304
6:  mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 304
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 304
40: ldp     x9, x10, [sp, #(L + 96)]        /* the keys' sum from the committees' key sums */
    cbz     x9, 41f
    cbz     x10, 41f
    mov     x0, x19
    mov     x1, x9
    mov     x2, x10
    mov     x3, x27
    add     x4, sp, #(L + 112)
    add     x5, sp, #(L + 40)
    add     x6, x20, #IndexedAttestation_signature
    mov     x7, x21
    bl      lantern_attestation_key_sum
    cbz     x0, 41f
    add     x0, sp, #(L + 112)              /* bls.FastAggregateVerify: CoreVerify of point_to_pubkey(sum) */
    add     x1, sp, #(L + 256)
    CALL_GLOBAL crypto_bls_g1_compress
    add     x0, sp, #(L + 256)
    add     x1, sp, #(L + 40)
    add     x2, x20, #IndexedAttestation_signature
    mov     x3, x21
    mov     x4, x22
    CALL_GLOBAL crypto_bls_verify
    LEAVE 304
41: PART    x0, x9, x19, BeaconState_validators     /* the keys: the validators' pubkeys */
    add     x0, x0, #Validator_pubkey
    mov     x1, x20                         /* the indices: the indexed attestation, as a BlsIndexList */
    mov     x2, x27
    add     x3, sp, #(L + 40)
    add     x4, x20, #IndexedAttestation_signature
    mov     x5, x21
    mov     x6, x22
    CALL_GLOBAL crypto_bls_fast_aggregate_verify_cached
    LEAVE 304
END_FUNCTION lantern_indexed_attestation_valid

/* 1 in Montgomery form: 2^384 mod p of BLS12-381, the z of an affine point as a G1Point. */
    RODATA
    .p2align 3
keysum_one:
    .quad 0x760900000002fffd, 0xebf4000bc40c0002, 0x5f48985753c758ba
    .quad 0x77ce585370525745, 0x5c071a97a256ec6d, 0x15f65ec3fa80e493
    .text

/* The 144 bytes at src to dst. Uses x16, x17. */
.macro COPY144 dst, src
    .irp o, 0, 16, 32, 48, 64, 80, 96, 112, 128
    ldp     x16, x17, [\src, #\o]
    stp     x16, x17, [\dst, #\o]
    .endr
.endm

/* The point of PubkeyCache entry e as a G1Point at dst: its affine x and y, and z = 1. Uses x16, x17. */
.macro ENTRY_POINT dst, e
    .irp o, 0, 16, 32, 48, 64, 80
    ldp     x16, x17, [\e, #(CRYPTO_BLS_ENTRY_POINT + \o)]
    stp     x16, x17, [\dst, #\o]
    .endr
    ADDRESS x16, keysum_one
    .irp o, 0, 16, 32
    ldp     x14, x15, [x16, #\o]
    stp     x14, x15, [\dst, #(96 + \o)]
    .endr
.endm

/*
 * L0: x0 = the members of the x1 indices at x0 whose PubkeyCache x3 entries do not hold their
 * keys (state validators at x2), each also written at x4 when x4 is not 0; or -1 when a member
 * is at or past the cache's count, or its entry has status 2 and its key. A leaf.
 */
LOCAL_FUNCTION lantern_key_sum_scan
    UNWIND_END_PROLOGUE
    ldr     x5, [x3, #CRYPTO_BLS_CACHE_COUNT]
    ldr     x6, [x3, #CRYPTO_BLS_CACHE_OFFSET]
    add     x6, x3, x6
    mov     x7, #0
    mov     x8, #CRYPTO_BLS_ENTRY_BYTES
1:  cbz     x1, 5f
    ldr     x9, [x0], #8
    cmp     x9, x5
    b.hs    6f
    madd    x10, x9, x8, x6                 /* the entry */
    add     x11, x2, x9, lsl #7             /* the validator */
    ldr     x12, [x10, #CRYPTO_BLS_ENTRY_STATUS]
    cbz     x12, 3f
    .irp o, 0, 16, 32
    ldp     x13, x14, [x10, #(CRYPTO_BLS_ENTRY_KEY + \o)]
    ldp     x15, x16, [x11, #(Validator_pubkey + \o)]
    cmp     x13, x15
    ccmp    x14, x16, #0, eq
    b.ne    3f
    .endr
    cmp     x12, #1
    b.ne    6f
    b       4f
3:  add     x7, x7, #1                      /* not its key */
    cbz     x4, 4f
    str     x9, [x4], #8
4:  sub     x1, x1, #1
    b       1b
5:  mov     x0, x7
    ret
6:  mov     x0, #-1
    ret
END_FUNCTION lantern_key_sum_scan

/*
 * L0: makes the KeySum x0 of the x2 members at x1 (state validators at x3, PubkeyCache x4).
 * Members whose entries do not hold their keys: crypto_bls_fast_aggregate_verify_cached of
 * them first, with message x5, signature x6 and scratch x7 (its last bytes take their list),
 * to fill their entries. x0 = 1 when the KeySum has status 1, 2 when it has status 2, 0 when
 * a callee fails. x19 KeySum, x20 members, x21 count, x22 validators, x23 cache, x24 message,
 * x25 signature, x26 scratch, x27 i, x28 list. Out: sp the sum, sp+144 the next, sp+288 a key.
 * Locals: KSM_L the scratch size, KSM_L+8 valid.
 */
.set KSM_OUT, 432
.set KSM_L, KSM_OUT + L
LOCAL_FUNCTION lantern_key_sum_make
    ENTER_OUT 32, KSM_OUT
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    mov     x26, x7
    mov     x0, x20
    mov     x1, x21
    mov     x2, x22
    mov     x3, x23
    mov     x4, #0
    bl      lantern_key_sum_scan
    cmn     x0, #1
    b.eq    8f
    cbz     x0, 3f
    mov     x27, x0                         /* the list of those members at the end of scratch */
    ldr     x9, [x26]
    str     x9, [sp, #KSM_L]
    lsl     x10, x27, #3
    add     x10, x10, #LIST_FIXED
    sub     x11, x9, x10
    add     x28, x26, x11
    str     x11, [x26]
    str     x10, [x28, #LIST_SIZE]
    mov     x12, #LIST_FIXED
    str     x12, [x28, #LIST_OFFSET]
    str     x27, [x28, #LIST_COUNT]
    mov     x0, x20
    mov     x1, x21
    mov     x2, x22
    mov     x3, x23
    add     x4, x28, #LIST_FIXED
    bl      lantern_key_sum_scan
    add     x0, x22, #Validator_pubkey
    mov     x1, x28
    mov     x2, x23
    mov     x3, x24
    mov     x4, x25
    mov     x5, x26
    add     x6, sp, #(KSM_L + 8)
    CALL_GLOBAL crypto_bls_fast_aggregate_verify_cached
    ldr     x9, [sp, #KSM_L]
    str     x9, [x26]
    cbnz    x0, 9f
    mov     x0, x20
    mov     x1, x21
    mov     x2, x22
    mov     x3, x23
    mov     x4, #0
    bl      lantern_key_sum_scan
    cbnz    x0, 8f                          /* an entry still without its key: never tried again */
3:  .irp o, 0, 16, 32, 48, 64, 80, 96, 112, 128
    stp     xzr, xzr, [sp, #\o]             /* the point at infinity */
    .endr
    mov     x27, #0
4:  cmp     x27, x21
    b.hs    5f
    ldr     x9, [x20, x27, lsl #3]
    ldr     x10, [x23, #CRYPTO_BLS_CACHE_OFFSET]
    add     x10, x23, x10
    mov     x11, #CRYPTO_BLS_ENTRY_BYTES
    madd    x10, x9, x11, x10
    add     x12, sp, #288
    ENTRY_POINT x12, x10
    mov     x0, sp
    add     x1, sp, #288
    add     x2, sp, #144
    CALL_GLOBAL crypto_bls_g1_add
    add     x9, sp, #144
    COPY144 sp, x9
    add     x27, x27, #1
    b       4b
5:  add     x9, x19, #KeySum_point
    COPY144 x9, sp
    mov     x9, #1
    str     x9, [x19, #KeySum_status]
    mov     x0, #1
    LEAVE_OUT 32, KSM_OUT
8:  mov     x9, #2
    str     x9, [x19, #KeySum_status]
    mov     x0, #2
    LEAVE_OUT 32, KSM_OUT
9:  mov     x0, #0
    LEAVE_OUT 32, KSM_OUT
END_FUNCTION lantern_key_sum_make

/*
 * L0: the sum of the keys of the attesting validators of attestation x1 (state x0), from the
 * key sums of CommitteeCache x2 and the entries of PubkeyCache x3, at x4 (G1Point); x5 the
 * message, x6 the signature, x7 the scratch, for lantern_key_sum_make. x0 = 1 when x4 holds the sum,
 * else 0. x19 state, x20 attestation, x21 member i, x22 PubkeyCache, x23 validators, x24 the
 * entry, x25 committees of the epoch, x26 its active validators, x27 bits, x28 bit count.
 * Out: sp the sum, sp+144 the next, sp+288 a key, sp+432 its negation.
 * Locals at AKS_L: +0 epoch, +8 committee index, +16 committee offset, +24 the block of key sums,
 * +32 committees per slot, +40 out, +48 message, +56 signature, +64 scratch, +72 members,
 * +80 member count, +88 bits set, +96 the KeySum, +112 the entry's key (96), +208 the pass:
 * 0 counts the additions the key sums save, 1 adds; +216 that count.
 */
.set AKS_OUT, 576
.set AKS_L, AKS_OUT + L
LOCAL_FUNCTION lantern_attestation_key_sum
    ENTER_OUT 224, AKS_OUT
    mov     x19, x0
    mov     x20, x1
    mov     x24, x2
    mov     x22, x3
    str     x4, [sp, #(AKS_L + 40)]
    str     x5, [sp, #(AKS_L + 48)]
    str     x6, [sp, #(AKS_L + 56)]
    str     x7, [sp, #(AKS_L + 64)]
    ldr     x9, [x20, #(Attestation_data + AttestationData_slot)]
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    str     x9, [sp, #AKS_L]
    mov     x0, x19                         /* the entry of the epoch */
    mov     x1, x9
    add     x2, sp, #(AKS_L + 112)
    bl      lantern_committee_key
    cbnz    x0, 90f
    mov     x0, x24
    ldr     x1, [sp, #AKS_L]
    add     x2, sp, #(AKS_L + 112)
    bl      lantern_committee_find
    cbz     x0, 90f
    ldr     x10, [x24, #CommitteeCache_validators]  /* its block of key sums */
    lsl     x10, x10, #3
    add     x10, x10, #(CommitteeEntry__mem + LIST_FIXED)
    add     x11, x24, #CommitteeCache_entries
    sub     x12, x0, x11
    udiv    x12, x12, x10
    mov     x13, #COMMITTEE_CACHE_ENTRIES
    madd    x11, x13, x10, x11
    MOVQ    x13, KEYSUM_BLOCK_BYTES
    madd    x11, x12, x13, x11
    str     x11, [sp, #(AKS_L + 24)]
    mov     x24, x0
    ldr     x26, [x24, #CommitteeEntry_count]
    lsr     x9, x26, #LOG2_SLOTS_PER_EPOCH  /* get_committee_count_per_slot of the entry's count */
    mov     x10, #TARGET_COMMITTEE_SIZE
    udiv    x9, x9, x10
    mov     x10, #MAX_COMMITTEES_PER_SLOT
    cmp     x9, x10
    csel    x9, x9, x10, lo
    cmp     x9, #1
    csinc   x9, x9, xzr, hs
    str     x9, [sp, #(AKS_L + 32)]
    lsl     x25, x9, #LOG2_SLOTS_PER_EPOCH
    PART    x23, x9, x19, BeaconState_validators
    PART    x27, x28, x20, Attestation_aggregation_bits
    .irp o, 0, 16, 32, 48, 64, 80, 96, 112, 128
    stp     xzr, xzr, [sp, #\o]             /* the point at infinity */
    .endr
    str     xzr, [sp, #(AKS_L + 208)]
    str     xzr, [sp, #(AKS_L + 216)]
5:  str     xzr, [sp, #(AKS_L + 16)]
.if FORK >= FORK_ELECTRA
    str     xzr, [sp, #(AKS_L + 8)]         /* each committee of committee_bits, in order */
1:  ldr     x9, [sp, #(AKS_L + 8)]
    cmp     x9, #MAX_COMMITTEES_PER_SLOT
    b.hs    80f
    add     x10, x20, #Attestation_committee_bits
    lsr     x11, x9, #3
    ldrb    w11, [x10, x11]
    and     x12, x9, #7
    lsr     w11, w11, w12
    tbnz    w11, #0, 10f
2:  ldr     x9, [sp, #(AKS_L + 8)]
    add     x9, x9, #1
    str     x9, [sp, #(AKS_L + 8)]
    b       1b
.else
    ldr     x9, [x20, #(Attestation_data + AttestationData_index)]   /* the committee of data.index */
    str     x9, [sp, #(AKS_L + 8)]
.endif
10: ldr     x9, [sp, #(AKS_L + 8)]          /* the committee: its slice of the entry and its bits */
    ldr     x10, [sp, #(AKS_L + 32)]
    cmp     x9, x10
    b.hs    90f
    ldr     x11, [x20, #(Attestation_data + AttestationData_slot)]
    and     x11, x11, #(SLOTS_PER_EPOCH - 1)
    madd    x11, x11, x10, x9               /* k */
    ldr     x13, [sp, #(AKS_L + 24)]
    mov     x14, #KeySum__mem
    madd    x13, x11, x14, x13
    str     x13, [sp, #(AKS_L + 96)]
    mul     x12, x26, x11                   /* start */
    udiv    x12, x12, x25
    add     x13, x11, #1                    /* end */
    mul     x13, x26, x13
    udiv    x13, x13, x25
    cmp     x13, x26
    b.hi    90f
    sub     x14, x13, x12
    str     x14, [sp, #(AKS_L + 80)]
    add     x15, x24, #(CommitteeEntry__mem + LIST_FIXED)
    add     x15, x15, x12, lsl #3
    str     x15, [sp, #(AKS_L + 72)]
    ldr     x16, [sp, #(AKS_L + 16)]
    add     x17, x16, x14
    cmp     x17, x28
    b.hi    90f
    mov     x0, #0                          /* members with the bit */
    mov     x1, x16
11: cmp     x1, x17
    b.hs    12f
    lsr     x2, x1, #3
    ldrb    w2, [x27, x2]
    and     x3, x1, #7
    lsr     w2, w2, w3
    and     x2, x2, #1
    add     x0, x0, x2
    add     x1, x1, #1
    b       11b
12: str     x0, [sp, #(AKS_L + 88)]
    sub     x1, x14, x0
    ldr     x9, [sp, #(AKS_L + 208)]
    cbnz    x9, 13f
    cmp     x1, x0                          /* pass 0: present - absent - 1 saved with the KeySum */
    b.hs    40f
    sub     x9, x0, x1
    sub     x9, x9, #1
    ldr     x10, [sp, #(AKS_L + 216)]
    add     x10, x10, x9
    str     x10, [sp, #(AKS_L + 216)]
    b       40f
13: cmp     x1, x0
    b.hs    30f
    ldr     x9, [sp, #(AKS_L + 96)]         /* fewer without the bit: the KeySum, less their keys */
    ldr     x10, [x9, #KeySum_status]
    cmp     x10, #1
    b.eq    20f
    cbnz    x10, 90f
    mov     x0, x9
    ldr     x1, [sp, #(AKS_L + 72)]
    ldr     x2, [sp, #(AKS_L + 80)]
    mov     x3, x23
    mov     x4, x22
    ldr     x5, [sp, #(AKS_L + 48)]
    ldr     x6, [sp, #(AKS_L + 56)]
    ldr     x7, [sp, #(AKS_L + 64)]
    bl      lantern_key_sum_make
    cmp     x0, #1
    b.ne    90f
20: mov     x0, sp
    ldr     x1, [sp, #(AKS_L + 96)]
    add     x1, x1, #KeySum_point
    add     x2, sp, #144
    CALL_GLOBAL crypto_bls_g1_add
    add     x9, sp, #144
    COPY144 sp, x9
    mov     x21, #0
21: ldr     x9, [sp, #(AKS_L + 80)]
    cmp     x21, x9
    b.hs    40f
    ldr     x10, [sp, #(AKS_L + 16)]
    add     x10, x10, x21
    lsr     x11, x10, #3
    ldrb    w11, [x27, x11]
    and     x12, x10, #7
    lsr     w11, w11, w12
    tbnz    w11, #0, 22f
    bl      70f                             /* sp+288: the key of member x21 */
    cbz     x0, 90f
    add     x0, sp, #288
    add     x1, sp, #432
    CALL_GLOBAL crypto_bls_g1_neg
    mov     x0, sp
    add     x1, sp, #432
    add     x2, sp, #144
    CALL_GLOBAL crypto_bls_g1_add
    add     x9, sp, #144
    COPY144 sp, x9
22: add     x21, x21, #1
    b       21b
30: mov     x21, #0                         /* else the keys of the members with the bit */
31: ldr     x9, [sp, #(AKS_L + 80)]
    cmp     x21, x9
    b.hs    40f
    ldr     x10, [sp, #(AKS_L + 16)]
    add     x10, x10, x21
    lsr     x11, x10, #3
    ldrb    w11, [x27, x11]
    and     x12, x10, #7
    lsr     w11, w11, w12
    tbz     w11, #0, 32f
    bl      70f
    cbz     x0, 90f
    mov     x0, sp
    add     x1, sp, #288
    add     x2, sp, #144
    CALL_GLOBAL crypto_bls_g1_add
    add     x9, sp, #144
    COPY144 sp, x9
32: add     x21, x21, #1
    b       31b
40: ldr     x9, [sp, #(AKS_L + 16)]         /* committee_offset += len(committee) */
    ldr     x10, [sp, #(AKS_L + 80)]
    add     x9, x9, x10
    str     x9, [sp, #(AKS_L + 16)]
.if FORK >= FORK_ELECTRA
    b       2b
.endif
80: ldr     x9, [sp, #(AKS_L + 16)]         /* the bits: those of the committees, no more */
    cmp     x9, x28
    b.ne    90f
    ldr     x9, [sp, #(AKS_L + 208)]
    cbnz    x9, 81f
    ldr     x9, [sp, #(AKS_L + 216)]        /* pass 0 done: pass 1 when the key sums save enough */
    cmp     x9, #KEYSUM_MIN_SAVED
    b.lo    90f
    mov     x9, #1
    str     x9, [sp, #(AKS_L + 208)]
    b       5b
81: ldr     x9, [sp, #(AKS_L + 40)]
    COPY144 x9, sp
    mov     x0, #1
    LEAVE_OUT 224, AKS_OUT
90: mov     x0, #0
    LEAVE_OUT 224, AKS_OUT

/*
 * 70: within lantern_attestation_key_sum, by bl (sp unchanged): the key of member x21 of the committee as a
 * G1Point at sp+288, when its entry holds it; x0 = 1, else 0. Uses x9-x17.
 */
70:
    ldr     x9, [sp, #(AKS_L + 72)]
    ldr     x9, [x9, x21, lsl #3]           /* the validator index */
    ldr     x10, [x22, #CRYPTO_BLS_CACHE_COUNT]
    cmp     x9, x10
    b.hs    92f
    ldr     x10, [x22, #CRYPTO_BLS_CACHE_OFFSET]
    add     x10, x22, x10
    mov     x11, #CRYPTO_BLS_ENTRY_BYTES
    madd    x10, x9, x11, x10
    ldr     x11, [x10, #CRYPTO_BLS_ENTRY_STATUS]
    cmp     x11, #1
    b.ne    92f
    add     x11, x23, x9, lsl #7
    .irp o, 0, 16, 32
    ldp     x12, x13, [x10, #(CRYPTO_BLS_ENTRY_KEY + \o)]
    ldp     x14, x15, [x11, #(Validator_pubkey + \o)]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.ne    92f
    .endr
    add     x12, sp, #288
    ENTRY_POINT x12, x10
    mov     x0, #1
    ret
92: mov     x0, #0
    ret
END_FUNCTION lantern_attestation_key_sum

.if FORK >= FORK_ALTAIR
/*
 * x19 state, x20 data, x21 delay, x22 out, x23 matching source, x24 matching target, x25 matching head.
 * Locals: L current epoch, L+8 target root (32), L+40 head root (32), L+72 SLOTS_PER_EPOCH, L+80 its root.
 */
SPEC_FUNCTION get_attestation_participation_flag_indices
    ENTER 96
    mov     x19, x0
    mov     x20, x1
    ldr     x21, [x2]
    mov     x22, x3
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [x20, #(AttestationData_target + Checkpoint_epoch)]
    ldr     x10, [sp, #L]
    ADDQ    x11, x19, BeaconState_current_justified_checkpoint
    ADDQ    x12, x19, BeaconState_previous_justified_checkpoint
    cmp     x9, x10
    csel    x11, x11, x12, eq               /* justified_checkpoint */
    ldr     x12, [x11, #Checkpoint_epoch]   /* is_matching_source = data.source == justified_checkpoint */
    ldr     x13, [x20, #(AttestationData_source + Checkpoint_epoch)]
    mov     x23, #0
    cmp     x12, x13
    b.ne    1f
    add     x14, x20, #(AttestationData_source + Checkpoint_root)
    add     x15, x11, #Checkpoint_root
    NE32    x14, x15, 1f
    mov     x23, #1
1:  mov     x0, x19                         /* target_root = get_block_root(state, data.target.epoch) */
    add     x1, x20, #(AttestationData_target + Checkpoint_epoch)
    add     x2, sp, #(L + 8)
    bl      lantern_get_block_root
    cbnz    x0, 7f
    mov     x24, #0
    add     x14, x20, #(AttestationData_target + Checkpoint_root)
    add     x15, sp, #(L + 8)
    NE32    x14, x15, 2f
    mov     x24, x23                        /* is_matching_target = is_matching_source and target_root_matches */
2:  mov     x0, x19                         /* head_root = get_block_root_at_slot(state, data.slot) */
    add     x1, x20, #AttestationData_slot
    add     x2, sp, #(L + 40)
    bl      lantern_get_block_root_at_slot
    cbnz    x0, 7f
    mov     x25, #0
    add     x14, x20, #AttestationData_beacon_block_root
    add     x15, sp, #(L + 40)
    NE32    x14, x15, 3f
    mov     x25, x24
3:  mov     x0, #LANTERN_INVALID_SOURCE     /* assert is_matching_source */
    cbz     x23, 7f
    mov     x9, #SLOTS_PER_EPOCH
    str     x9, [sp, #(L + 72)]
    add     x0, sp, #(L + 72)
    add     x1, sp, #(L + 80)
    bl      lantern_integer_squareroot
    mov     x9, #LIST_FIXED
    str     x9, [x22, #LIST_OFFSET]
    add     x10, x22, #LIST_FIXED
    ldr     x11, [sp, #(L + 80)]
    cmp     x21, x11                        /* source within integer_squareroot(SLOTS_PER_EPOCH) */
    b.hi    4f
    mov     x12, #TIMELY_SOURCE_FLAG_INDEX
    str     x12, [x10], #8
4:  cbz     x24, 5f
.if FORK < FORK_DENEB
    cmp     x21, #SLOTS_PER_EPOCH           /* and inclusion_delay <= SLOTS_PER_EPOCH */
    b.hi    5f
.endif
    mov     x12, #TIMELY_TARGET_FLAG_INDEX
    str     x12, [x10], #8
5:  cbz     x25, 6f
    cmp     x21, #MIN_ATTESTATION_INCLUSION_DELAY
    b.ne    6f
    mov     x12, #TIMELY_HEAD_FLAG_INDEX
    str     x12, [x10], #8
6:  add     x11, x22, #LIST_FIXED
    sub     x10, x10, x11
    lsr     x10, x10, #3
    str     x10, [x22, #LIST_COUNT]
    mov     x0, #LANTERN_OK
7:  LEAVE 96
SPEC_END get_attestation_participation_flag_indices
.endif

.if FORK == FORK_PHASE0
/*
 * x19 state, x20 attestation, x21 config, x22 scratch, x23 result, x24 scratch size, x25 n,
 * x26 the PartRef offset of the list to append to, x27 the indexed attestation, x28 the committee.
 * Locals: L previous epoch, L+8 current epoch, L+16 committees per slot, L+24 valid,
 * L+32 proposer index, L+40 the scratch size callees get.
 */
SPEC_FUNCTION process_attestation
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    NEED_SCRATCH_B x22, x19, 10, ATTEST_EXTRA, 9f
    str     xzr, [x23]
    ldr     x24, [x22]
    LDQ     x25, x19, BeaconState_validators + 8
    lsl     x11, x25, #3                    /* own scratch at the end: the indexed attestation, the committee */
    add     x11, x11, #LIST_FIXED           /* L(n) */
    MOVQ    x12, IndexedAttestation__fixed + 8
    add     x12, x12, x11
    sub     x10, x24, x12
    add     x27, x22, x10
    str     x12, [x27]
    sub     x10, x10, x11
    add     x28, x22, x10
    str     x11, [x28]
    str     x10, [sp, #(L + 40)]
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_previous_epoch
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_current_epoch
    mov     x0, #LANTERN_INVALID_ATTESTATION
    ldr     x9, [x20, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
    ldp     x10, x11, [sp, #L]
    cmp     x9, x10                         /* assert data.target.epoch in (previous, current) */
    ccmp    x9, x11, #4, ne
    b.ne    6f
    ldr     x10, [x20, #(Attestation_data + AttestationData_slot)]
    lsr     x11, x10, #LOG2_SLOTS_PER_EPOCH /* assert data.target.epoch == compute_epoch_at_slot(data.slot) */
    cmp     x9, x11
    b.ne    6f
    adds    x11, x10, #MIN_ATTESTATION_INCLUSION_DELAY  /* assert data.slot + MIN_ATTESTATION_INCLUSION_DELAY <= state.slot */
    b.cs    5f
    LDQ     x12, x19, BeaconState_slot
    cmp     x11, x12
    b.hi    6f
    adds    x11, x10, #SLOTS_PER_EPOCH      /* assert state.slot <= data.slot + SLOTS_PER_EPOCH */
    b.cs    5f
    cmp     x12, x11
    b.hi    6f
    ldr     x9, [sp, #(L + 40)]
    str     x9, [x22]
    mov     x0, x19                         /* assert data.index < get_committee_count_per_slot(state, data.target.epoch) */
    add     x1, x20, #(Attestation_data + AttestationData_target + Checkpoint_epoch)
    mov     x3, x22
    add     x4, sp, #(L + 16)
    ldr     x2, [x21, #CONFIG_COMMITTEE_CACHE]
    bl      lantern_get_committee_count_per_slot
    cbnz    x0, 7f
    ldr     x9, [x20, #(Attestation_data + AttestationData_index)]
    ldr     x10, [sp, #(L + 16)]
    mov     x0, #LANTERN_INVALID_ATTESTATION
    cmp     x9, x10
    b.hs    6f
    ldr     x9, [sp, #(L + 40)]
    str     x9, [x22]
    mov     x0, x19                         /* committee = get_beacon_committee(state, data.slot, data.index) */
    add     x1, x20, #(Attestation_data + AttestationData_slot)
    add     x2, x20, #(Attestation_data + AttestationData_index)
    mov     x4, x22
    mov     x5, x28
    ldr     x3, [x21, #CONFIG_COMMITTEE_CACHE]
    bl      lantern_get_beacon_committee
    CHECK_STATUS x23, 7f, 8f
    LDQ     x9, x20, Attestation_aggregation_bits + 8
    ldr     x10, [x28, #LIST_COUNT]
    cmp     x9, x10                         /* assert len(attestation.aggregation_bits) == len(committee) */
    mov     x0, #LANTERN_INVALID_ATTESTATION
    b.ne    6f
    ldr     x9, [sp, #(L + 40)]
    str     x9, [x22]
    mov     x0, x19                         /* proposer_index = get_beacon_proposer_index(state) */
    mov     x1, x22
    add     x2, sp, #(L + 32)
    bl      lantern_get_beacon_proposer_index
    CHECK_STATUS x23, 7f, 8f
    ldr     x9, [x20, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
    ldr     x10, [sp, #(L + 8)]
    cmp     x9, x10
    b.ne    1f
    ADDQ    x11, x19, BeaconState_current_justified_checkpoint
    MOVQ    x26, BeaconState_current_epoch_attestations
    b       2f
1:  ADDQ    x11, x19, BeaconState_previous_justified_checkpoint
    MOVQ    x26, BeaconState_previous_epoch_attestations
2:  add     x10, x20, #(Attestation_data + AttestationData_source)
    ldr     x12, [x10, #Checkpoint_epoch]   /* assert data.source == the justified checkpoint of its epoch */
    ldr     x13, [x11, #Checkpoint_epoch]
    cmp     x12, x13
    mov     x0, #LANTERN_INVALID_ATTESTATION
    b.ne    6f
    add     x14, x10, #Checkpoint_root
    add     x15, x11, #Checkpoint_root
    NE32    x14, x15, 6f
    ldr     x9, [sp, #(L + 40)]
    str     x9, [x22]
    mov     x0, x19                         /* assert is_valid_indexed_attestation(state, get_indexed_attestation(...)) */
    mov     x1, x20
    mov     x3, x22
    mov     x4, x27
    ldr     x2, [x21, #CONFIG_COMMITTEE_CACHE]
    bl      lantern_get_indexed_attestation
    CHECK_STATUS x23, 7f, 8f
    ldr     x9, [sp, #(L + 40)]
    str     x9, [x22]
    mov     x0, x19
    mov     x1, x27
    mov     x3, x22
    add     x4, sp, #(L + 24)
    ldr     x2, [x21, #CONFIG_PUBKEY_CACHE]
    bl      lantern_is_valid_indexed_attestation
    CHECK_STATUS x23, 7f, 8f
    ldr     x9, [sp, #(L + 24)]
    mov     x0, #LANTERN_INVALID_ATTESTATION
    cbz     x9, 6f
    add     x9, x19, x26                    /* append the PendingAttestation: the end of the list's entries */
    ldr     x10, [x9]                       /* its offset */
    ldr     x11, [x9, #8]                   /* its count */
    add     x12, x19, x10
3:  cbz     x11, 4f
    ldr     x13, [x12]
    add     x12, x12, x13
    sub     x11, x11, #1
    b       3b
4:  MOVQ    x13, BeaconState_previous_epoch_attestations
    cmp     x26, x13
    b.ne    41f
    LDQ     x13, x19, BeaconState_current_epoch_attestations    /* the list ends where the next part starts */
    b       42f
41: ldr     x13, [x19]                      /* or at the end of the value */
42: add     x13, x19, x13
    LDQ     x14, x20, Attestation_aggregation_bits + 8
    add     x15, x14, #7
    lsr     x15, x15, #3                    /* the bytes of aggregation_bits */
    MOVQ    x16, PendingAttestation__fixed + 7
    add     x16, x16, x15
    and     x16, x16, #-8                   /* the PendingAttestation's size */
    add     x17, x12, x16
    cmp     x17, x13
    b.hi    9f                              /* no room: the state is unchanged */
    cbz     x15, 43f
    add     x9, x12, x16                    /* zero the padding after the bit bytes */
    stur    xzr, [x9, #-8]
43: str     x16, [x12]                      /* size; aggregation_bits at the end of the fixed part */
    mov     x17, #PendingAttestation__fixed
    str     x17, [x12, #PendingAttestation_aggregation_bits]
    str     x14, [x12, #(PendingAttestation_aggregation_bits + 8)]
    LDQ     x17, x19, BeaconState_slot      /* inclusion_delay = state.slot - data.slot */
    ldr     x9, [x20, #(Attestation_data + AttestationData_slot)]
    sub     x17, x17, x9
    str     x17, [x12, #PendingAttestation_inclusion_delay]
    ldr     x17, [sp, #(L + 32)]
    str     x17, [x12, #PendingAttestation_proposer_index]
    stp     x12, x15, [sp, #(L + 16)]       /* keep the value and the bit bytes */
    add     x0, x12, #PendingAttestation_data
    add     x1, x20, #Attestation_data
    mov     x2, #AttestationData__mem
    bl      lantern_copy
    ldp     x12, x2, [sp, #(L + 16)]
    add     x0, x12, #PendingAttestation__fixed
    PART    x1, x9, x20, Attestation_aggregation_bits
    bl      lantern_copy
    add     x9, x19, x26                    /* the count, last */
    ldr     x10, [x9, #8]
    add     x10, x10, #1
    str     x10, [x9, #8]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 48
5:  mov     x0, #LANTERN_INVALID_OVERFLOW
6:  str     x0, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END process_attestation
.else
/*
 * x19 state, x20 attestation, x21 config, x22 scratch, x23 result, x24 scratch size, x25 n,
 * x26 committee indices, x27 committee, x28 committee offset.
 * Locals: L previous epoch, L+8 current epoch, L+16 committees per slot, L+24 committee index,
 * L+32 inclusion delay, L+40 valid, L+48 flags (FLAGS_BYTES), L+96 proposer, L+104 base reward,
 * L+112 index, L+120 proposer reward numerator, L+128 flag, L+136 cursor end, L+144 the indexed
 * attestation, L+152 the attesting list, L+160 the scratch size callees get, L+168 participation,
 * L+176 base reward per increment.
 */
/* process_attestation of the spec: lantern_attestation_memo with a base reward factor of its own. */
SPEC_FUNCTION process_attestation
    ENTER 16
    str     xzr, [sp, #L]
    add     x5, sp, #L
    bl      lantern_attestation_memo
    LEAVE 16
SPEC_END process_attestation

/*
 * L0: process_attestation, with x5 the address of the block's get_base_reward_per_increment(state):
 * 0 until an attestation finds it, which stores it there. The operations of one block change no
 * effective balance and no active validator of the current epoch, so its attestations share it.
 */
LOCAL_FUNCTION lantern_attestation_memo
    ENTER 192
    str     x5, [sp, #(L + 184)]
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    NEED_SCRATCH_B x22, x19, 10, ATTEST_EXTRA, 9f
    str     xzr, [x23]
    ldr     x24, [x22]
    LDQ     x25, x19, BeaconState_validators + 8
    MOVQ    x9, CIDX_BYTES                  /* own scratch at the end: committee indices, committee, indexed attestation, attesting */
    sub     x10, x24, x9
    add     x26, x22, x10
    str     x9, [x26]
    lsl     x11, x25, #3
    add     x11, x11, #LIST_FIXED           /* L(n) */
    sub     x10, x10, x11
    add     x27, x22, x10
    str     x11, [x27]
    MOVQ    x12, IndexedAttestation__fixed + 8
    add     x12, x12, x11
    sub     x10, x10, x12
    add     x13, x22, x10
    str     x12, [x13]
    str     x13, [sp, #(L + 144)]
    sub     x10, x10, x11
    add     x13, x22, x10
    str     x11, [x13]
    str     x13, [sp, #(L + 152)]
    str     x10, [sp, #(L + 160)]
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_previous_epoch
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_current_epoch
    mov     x0, #LANTERN_INVALID_ATTESTATION
    ldr     x9, [x20, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
    ldp     x10, x11, [sp, #L]
    cmp     x9, x10                         /* assert data.target.epoch in (previous, current) */
    ccmp    x9, x11, #4, ne
    b.ne    6f
    ldr     x10, [x20, #(Attestation_data + AttestationData_slot)]
    lsr     x11, x10, #LOG2_SLOTS_PER_EPOCH /* assert data.target.epoch == compute_epoch_at_slot(data.slot) */
    cmp     x9, x11
    b.ne    6f
    adds    x11, x10, #MIN_ATTESTATION_INCLUSION_DELAY  /* assert data.slot + MIN_ATTESTATION_INCLUSION_DELAY <= state.slot */
    b.cs    5f
    LDQ     x12, x19, BeaconState_slot
    cmp     x11, x12
    b.hi    6f
.if FORK < FORK_DENEB
    adds    x11, x10, #SLOTS_PER_EPOCH      /* assert state.slot <= data.slot + SLOTS_PER_EPOCH */
    b.cs    5f
    cmp     x12, x11
    b.hi    6f
.endif
.if FORK >= FORK_ELECTRA
    ldr     x11, [x20, #(Attestation_data + AttestationData_index)]
    cbnz    x11, 6f                         /* assert data.index == 0 */
    add     x0, x20, #Attestation_committee_bits
    mov     x1, x26
    bl      lantern_get_committee_indices
    mov     x28, #0                         /* committee_offset */
    add     x9, x26, #LIST_FIXED
    ldr     x10, [x26, #LIST_COUNT]
    add     x10, x9, x10, lsl #3
    str     x10, [sp, #(L + 136)]
    str     x9, [sp, #(L + 112)]            /* the cursor over committee indices */
1:  ldr     x9, [sp, #(L + 112)]
    ldr     x10, [sp, #(L + 136)]
    cmp     x9, x10
    b.hs    3f
    ldr     x10, [x9], #8
    str     x9, [sp, #(L + 112)]
    str     x10, [sp, #(L + 24)]
    ldr     x9, [sp, #(L + 160)]
    str     x9, [x22]
    mov     x0, x19                         /* assert committee_index < get_committee_count_per_slot(...) */
    add     x1, x20, #(Attestation_data + AttestationData_target + Checkpoint_epoch)
    mov     x3, x22
    add     x4, sp, #(L + 16)
    ldr     x2, [x21, #CONFIG_COMMITTEE_CACHE]
    bl      lantern_get_committee_count_per_slot
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 24)]
    ldr     x10, [sp, #(L + 16)]
    mov     x0, #LANTERN_INVALID_ATTESTATION
    cmp     x9, x10
    b.hs    6f
    ldr     x9, [sp, #(L + 160)]
    str     x9, [x22]
    mov     x0, x19
    add     x1, x20, #(Attestation_data + AttestationData_slot)
    add     x2, sp, #(L + 24)
    mov     x4, x22
    mov     x5, x27
    ldr     x3, [x21, #CONFIG_COMMITTEE_CACHE]
    bl      lantern_get_beacon_committee
    CHECK_STATUS x23, 7f, 8f
    PART    x11, x12, x20, Attestation_aggregation_bits
    ldr     x9, [x27, #LIST_COUNT]
    mov     x13, #0                         /* committee_attesters */
2:  cbz     x9, 25f
    cmp     x28, x12                        /* aggregation_bits[committee_offset + index] */
    mov     x0, #LANTERN_INVALID_ATTESTATION
    b.hs    6f
    lsr     x14, x28, #3
    ldrb    w14, [x11, x14]
    and     x15, x28, #7
    lsr     w14, w14, w15
    and     x14, x14, #1
    add     x13, x13, x14
    add     x28, x28, #1
    sub     x9, x9, #1
    b       2b
25: mov     x0, #LANTERN_INVALID_ATTESTATION
    cbz     x13, 6f                         /* assert len(committee_attesters) > 0 */
    b       1b
3:  LDQ     x9, x20, Attestation_aggregation_bits + 8
    cmp     x9, x28                         /* assert len(attestation.aggregation_bits) == committee_offset */
    mov     x0, #LANTERN_INVALID_ATTESTATION
    b.ne    6f
.else
    ldr     x9, [sp, #(L + 160)]
    str     x9, [x22]
    mov     x0, x19                         /* assert data.index < get_committee_count_per_slot(state, data.target.epoch) */
    add     x1, x20, #(Attestation_data + AttestationData_target + Checkpoint_epoch)
    mov     x3, x22
    add     x4, sp, #(L + 16)
    ldr     x2, [x21, #CONFIG_COMMITTEE_CACHE]
    bl      lantern_get_committee_count_per_slot
    cbnz    x0, 7f
    ldr     x9, [x20, #(Attestation_data + AttestationData_index)]
    ldr     x10, [sp, #(L + 16)]
    mov     x0, #LANTERN_INVALID_ATTESTATION
    cmp     x9, x10
    b.hs    6f
    ldr     x9, [sp, #(L + 160)]
    str     x9, [x22]
    mov     x0, x19                         /* committee = get_beacon_committee(state, data.slot, data.index) */
    add     x1, x20, #(Attestation_data + AttestationData_slot)
    add     x2, x20, #(Attestation_data + AttestationData_index)
    mov     x4, x22
    mov     x5, x27
    ldr     x3, [x21, #CONFIG_COMMITTEE_CACHE]
    bl      lantern_get_beacon_committee
    CHECK_STATUS x23, 7f, 8f
    LDQ     x9, x20, Attestation_aggregation_bits + 8
    ldr     x10, [x27, #LIST_COUNT]
    cmp     x9, x10                         /* assert len(attestation.aggregation_bits) == len(committee) */
    mov     x0, #LANTERN_INVALID_ATTESTATION
    b.ne    6f
.endif
    LDQ     x9, x19, BeaconState_slot
    ldr     x10, [x20, #(Attestation_data + AttestationData_slot)]
    sub     x9, x9, x10
    str     x9, [sp, #(L + 32)]
    MOVQ    x9, FLAGS_BYTES
    str     x9, [sp, #(L + 48)]
    mov     x0, x19                         /* participation_flag_indices */
    add     x1, x20, #Attestation_data
    add     x2, sp, #(L + 32)
    add     x3, sp, #(L + 48)
    bl      lantern_get_attestation_participation_flag_indices
    CHECK_STATUS x23, 7f, 8f
    ldr     x9, [sp, #(L + 160)]
    str     x9, [x22]
    mov     x0, x19                         /* assert is_valid_indexed_attestation(state, get_indexed_attestation(...)) */
    mov     x1, x20
    mov     x3, x22
    ldr     x4, [sp, #(L + 144)]
    ldr     x2, [x21, #CONFIG_COMMITTEE_CACHE]
    bl      lantern_get_indexed_attestation
    CHECK_STATUS x23, 7f, 8f
    ldr     x9, [sp, #(L + 160)]
    str     x9, [x22]
    mov     x0, x19
    ldr     x1, [sp, #(L + 144)]
    mov     x3, x22
    add     x4, sp, #(L + 40)
    ldr     x2, [x21, #CONFIG_PUBKEY_CACHE]
    mov     x5, x20
    ldr     x6, [x21, #CONFIG_COMMITTEE_CACHE]
    bl      lantern_indexed_attestation_valid
    CHECK_STATUS x23, 7f, 8f
    ldr     x9, [sp, #(L + 40)]
    mov     x0, #LANTERN_INVALID_ATTESTATION
    cbz     x9, 6f
    ldr     x9, [x20, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
    ldr     x10, [sp, #(L + 8)]
    cmp     x9, x10
    b.ne    31f
    PART    x9, x10, x19, BeaconState_current_epoch_participation
    b       32f
31: PART    x9, x10, x19, BeaconState_previous_epoch_participation
32: str     x9, [sp, #(L + 168)]
    ldr     x9, [sp, #(L + 160)]
    str     x9, [x22]
    mov     x0, x19                         /* for index in get_attesting_indices(state, attestation) */
    mov     x1, x20
    mov     x3, x22
    ldr     x4, [sp, #(L + 152)]
    ldr     x2, [x21, #CONFIG_COMMITTEE_CACHE]
    bl      lantern_get_attesting_indices
    CHECK_STATUS x23, 7f, 8f
    ldr     x9, [sp, #(L + 160)]
    str     x9, [x22]
    ldr     x9, [sp, #(L + 184)]            /* get_base_reward's factor: once for every attestation of the block */
    ldr     x10, [x9]
    str     x10, [sp, #(L + 176)]
    cbnz    x10, 47f
    mov     x0, x19
    mov     x1, x22
    add     x2, sp, #(L + 176)
    bl      lantern_get_base_reward_per_increment
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 184)]
    ldr     x10, [sp, #(L + 176)]
    str     x10, [x9]
47:
    str     xzr, [sp, #(L + 120)]
    ldr     x26, [sp, #(L + 152)]           /* the attesting list; the committee indices are done */
    add     x27, x26, #LIST_FIXED
    ldr     x9, [x26, #LIST_COUNT]
    add     x9, x27, x9, lsl #3
    str     x9, [sp, #(L + 136)]
4:  ldr     x9, [sp, #(L + 136)]
    cmp     x27, x9
    b.hs    45f
    ldr     x9, [x27], #8
    str     x9, [sp, #(L + 112)]
    mov     x28, #0                         /* for flag_index, weight in enumerate(PARTICIPATION_FLAG_WEIGHTS) */
41: cmp     x28, #3
    b.hs    4b
    ldr     x10, [sp, #(L + 48 + LIST_COUNT)]   /* flag_index in participation_flag_indices */
    add     x11, sp, #(L + 48 + LIST_FIXED)
42: cbz     x10, 44f
    ldr     x12, [x11], #8
    cmp     x12, x28
    b.eq    43f
    sub     x10, x10, #1
    b       42b
43: str     x28, [sp, #(L + 128)]
    ldr     x9, [sp, #(L + 168)]            /* and not has_flag(epoch_participation[index], flag_index) */
    ldr     x10, [sp, #(L + 112)]
    add     x0, x9, x10
    add     x1, sp, #(L + 128)
    add     x2, sp, #(L + 40)
    bl      lantern_has_flag
    ldr     x9, [sp, #(L + 40)]
    cbnz    x9, 44f
    ldr     x9, [sp, #(L + 168)]            /* epoch_participation[index] = add_flag(...) */
    ldr     x10, [sp, #(L + 112)]
    add     x0, x9, x10
    add     x1, sp, #(L + 128)
    mov     x2, x0
    bl      lantern_add_flag
    ldr     x9, [sp, #(L + 112)]            /* proposer_reward_numerator += get_base_reward(state, index) * weight */
    PART    x10, x11, x19, BeaconState_validators
    add     x10, x10, x9, lsl #7
    ldr     x9, [x10, #Validator_effective_balance]
    MOVQ    x10, EFFECTIVE_BALANCE_INCREMENT
    udiv    x9, x9, x10                     /* increments * base_reward_per_increment */
    ldr     x10, [sp, #(L + 176)]
    mul     x9, x9, x10
    mov     x10, #TIMELY_TARGET_WEIGHT
    mov     x11, #TIMELY_SOURCE_WEIGHT
    cmp     x28, #TIMELY_TARGET_FLAG_INDEX
    csel    x10, x10, x11, eq
    mul     x9, x9, x10
    ldr     x10, [sp, #(L + 120)]
    adds    x10, x10, x9
    b.cs    5f
    str     x10, [sp, #(L + 120)]
44: add     x28, x28, #1
    b       41b
45: ldr     x9, [sp, #(L + 120)]            /* proposer_reward = numerator // proposer_reward_denominator */
    mov     x10, #((WEIGHT_DENOMINATOR - PROPOSER_WEIGHT) * WEIGHT_DENOMINATOR / PROPOSER_WEIGHT)
    udiv    x9, x9, x10
    str     x9, [sp, #(L + 120)]
.if FORK >= FORK_FULU
    mov     x0, x19
    add     x1, sp, #(L + 96)
    bl      lantern_get_beacon_proposer_index
.else
    ldr     x9, [sp, #(L + 160)]
    str     x9, [x22]
    mov     x0, x19
    mov     x1, x22
    add     x2, sp, #(L + 96)
    bl      lantern_get_beacon_proposer_index
    cbnz    x0, 7f
.endif
    mov     x0, x19
    add     x1, sp, #(L + 96)
    add     x2, sp, #(L + 120)
    bl      lantern_increase_balance
8:  mov     x0, #LANTERN_OK
7:  LEAVE 192
5:  mov     x0, #LANTERN_INVALID_OVERFLOW
6:  str     x0, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 192
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 192
END_FUNCTION lantern_attestation_memo
.endif
