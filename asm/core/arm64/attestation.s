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
LOCAL_FUNCTION sort_u64
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
END_FUNCTION sort_u64

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
LOCAL_FUNCTION committee_key
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
END_FUNCTION committee_key

/* L0: x0 = the valid entry of cache x0 for epoch x1 and the key at x2, or 0. A leaf. */
LOCAL_FUNCTION committee_find
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
END_FUNCTION committee_find

/* Locals: sp+16 size. */
SPEC_FUNCTION committee_cache_size
    FRAME 16
    ldr     x9, [x0]
    lsl     x9, x9, #3
    add     x9, x9, #(CommitteeEntry__mem + LIST_FIXED)
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
    mov     x11, #COMMITTEE_CACHE_ENTRIES
    mul     x11, x10, x11
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
    bl      committee_key
    cbnz    x0, 1f
    mov     x0, x24
    ldr     x1, [x20]
    add     x2, sp, #L
    bl      committee_find
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
    bl      committee_key
    cbnz    x0, 20f
    mov     x0, x27
    ldr     x1, [sp, #L]
    add     x2, sp, #(L + 72)
    bl      committee_find
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
    bl      sort_u64
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
    bl      sort_u64
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
 * x19 state, x20 indexed attestation, x21 scratch, x22 out, x23 scratch size, x24 keys,
 * x25 indices, x26 count. Locals: L domain type, L+8 domain (32), L+40 message (24 + 32).
 */
SPEC_FUNCTION is_valid_indexed_attestation
    ENTER 96
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
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
    mov     x9, #48                         /* pubkeys: a BlsPublicKeyList at the end of scratch */
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
    mov     x0, x24                         /* bls.FastAggregateVerify(pubkeys, signing_root, signature) */
    add     x1, sp, #(L + 40)
    add     x2, x20, #IndexedAttestation_signature
    mov     x3, x21
    mov     x4, x22
    CALL_GLOBAL crypto_bls_fast_aggregate_verify
7:  LEAVE 96
8:  mov     x0, #LANTERN_OK
    LEAVE 96
6:  mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 96
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 96
SPEC_END is_valid_indexed_attestation

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
    mov     x2, x22
    add     x3, sp, #(L + 24)
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
SPEC_FUNCTION process_attestation
    ENTER 192
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
    mov     x2, x22
    add     x3, sp, #(L + 40)
    bl      lantern_is_valid_indexed_attestation
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
    mov     x0, x19                         /* get_base_reward's factor, once for every index */
    mov     x1, x22
    add     x2, sp, #(L + 176)
    bl      lantern_get_base_reward_per_increment
    cbnz    x0, 7f
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
SPEC_END process_attestation
.endif
