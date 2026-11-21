/*
 * The light client store, ARM64: in the common object. Requirements: docs/reference/light-client.md.
 */

.set LC_SPP, SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD   /* the slots of a sync committee period */

/* x0 += the room x10 field k times mem, for part x1 above k; else to 9f. Uses x11, x12. */
.macro LC_PART_STEP k, mem
    cmp     x1, #\k
    b.ls    9f
    ldr     x11, [x10, #(8 * \k)]
    MOVQ    x12, \mem
    madd    x9, x11, x12, x9
.endm

/* L0: x0 = the first entry or record of part x1 of the store x0. Uses x9-x12. */
LOCAL_FUNCTION lc_part
    UNWIND_END_PROLOGUE
    MOVQ    x9, LC_STORE_FIXED
    add     x10, x0, #LcStore_room
    LC_PART_STEP 0, LcBlock__mem
    LC_PART_STEP 1, LcFinalized__mem
    LC_PART_STEP 2, LcPeriod__mem
    LC_PART_STEP 3, LcBootstrap__mem
    LC_PART_STEP 4, LcHeader__mem
    LC_PART_STEP 5, LcCommittee__mem
9:  add     x0, x0, x9
    ret
END_FUNCTION lc_part

/* L0: x12 = the bytes of an entry or record of part x1. */
LOCAL_FUNCTION lc_mem
    UNWIND_END_PROLOGUE
    MOVQ    x12, LcBlock__mem
    cbz     x1, 1f
    mov     x12, #LcFinalized__mem
    cmp     x1, #LC_PART_FINALIZED
    b.eq    1f
    mov     x12, #LcPeriod__mem
    cmp     x1, #LC_PART_PERIODS
    b.eq    1f
    mov     x12, #LcBootstrap__mem
    cmp     x1, #LC_PART_BOOTSTRAPS
    b.eq    1f
    MOVQ    x12, LcHeader__mem
    cmp     x1, #LC_PART_HEADERS
    b.eq    1f
    MOVQ    x12, LcCommittee__mem
    cmp     x1, #LC_PART_COMMITTEES
    b.eq    1f
    MOVQ    x12, LcUpdate__mem
1:  ret
END_FUNCTION lc_mem

/* L1: x0 = entry or record x2 (an index) of part x1 of the store x0; x1, x2 kept. Uses x9-x12. */
LOCAL_FUNCTION lc_at
    FRAME 0
    bl      lc_part
    bl      lc_mem
    madd    x0, x2, x12, x0
    UNFRAME 0
END_FUNCTION lc_at

/* L1: x0 = record x2 (a reference, not 0) of part x1 of the store x0. Uses x9-x12. */
LOCAL_FUNCTION lc_ref
    FRAME 0
    sub     x2, x2, #1
    bl      lc_at
    add     x2, x2, #1
    UNFRAME 0
END_FUNCTION lc_ref

/* L1: x0 = the reference of a free record of part x1 of the store x0, now LC_USED; 0 with none. Uses x9-x13. */
LOCAL_FUNCTION lc_alloc
    FRAME 0
    mov     x13, x0
    bl      lc_part
    bl      lc_mem
    add     x9, x13, #LcStore_room
    ldr     x10, [x9, x1, lsl #3]
    mov     x11, #0
1:  cmp     x11, x10
    b.hs    8f
    ldr     x9, [x0]
    cbz     x9, 2f
    add     x0, x0, x12
    add     x11, x11, #1
    b       1b
2:  mov     x9, #LC_USED
    str     x9, [x0]
    add     x0, x11, #1
    UNFRAME 0
8:  mov     x0, #0
    UNFRAME 0
END_FUNCTION lc_alloc

/* L1: x0 = the free records of part x1 of the store x0. Uses x9-x14. */
LOCAL_FUNCTION lc_free_count
    FRAME 0
    mov     x13, x0
    bl      lc_part
    bl      lc_mem
    add     x9, x13, #LcStore_room
    ldr     x10, [x9, x1, lsl #3]
    mov     x14, #0
1:  cbz     x10, 2f
    ldr     x9, [x0]
    cmp     x9, #LC_FREE
    cinc    x14, x14, eq
    add     x0, x0, x12
    sub     x10, x10, #1
    b       1b
2:  mov     x0, x14
    UNFRAME 0
END_FUNCTION lc_free_count

/* L1: record x2 (a reference, or 0 for none) of part x1 of the store x0 becomes LC_MARKED. Uses x9-x12. */
LOCAL_FUNCTION lc_mark
    FRAME 0
    cbz     x2, 1f
    bl      lc_ref
    mov     x9, #LC_MARKED
    str     x9, [x0]
1:  UNFRAME 0
END_FUNCTION lc_mark

/*
 * L1: the records of the store x0 that nothing refers to become LC_FREE (LcStore, Rules). x19 the
 * store, x20 an entry or record, x21 the ones left, x22 the part.
 */
LOCAL_FUNCTION lc_collect
    ENTER 0
    mov     x19, x0
    mov     x1, #LC_PART_BLOCKS             /* the blocks' header, committees and best update */
    bl      lc_part
    mov     x20, x0
    ldr     x21, [x19, #LcStore_blocks]
1:  cbz     x21, 2f
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    ldr     x2, [x20, #LcBlock_header]
    bl      lc_mark
    mov     x0, x19
    mov     x1, #LC_PART_COMMITTEES
    ldr     x2, [x20, #LcBlock_current_sync_committee]
    bl      lc_mark
    mov     x0, x19
    mov     x1, #LC_PART_COMMITTEES
    ldr     x2, [x20, #LcBlock_next_sync_committee]
    bl      lc_mark
    mov     x0, x19
    mov     x1, #LC_PART_UPDATES
    ldr     x2, [x20, #LcBlock_best]
    bl      lc_mark
    add     x20, x20, #LcBlock__mem
    sub     x21, x21, #1
    b       1b
2:  mov     x0, x19                         /* the bootstraps' header and committee */
    mov     x1, #LC_PART_BOOTSTRAPS
    bl      lc_part
    mov     x20, x0
    ldr     x21, [x19, #LcStore_bootstraps]
3:  cbz     x21, 4f
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    ldr     x2, [x20, #LcBootstrap_header]
    bl      lc_mark
    mov     x0, x19
    mov     x1, #LC_PART_COMMITTEES
    ldr     x2, [x20, #LcBootstrap_sync_committee]
    bl      lc_mark
    add     x20, x20, #LcBootstrap__mem
    sub     x21, x21, #1
    b       3b
4:  mov     x0, x19                         /* the periods' updates, and latest */
    mov     x1, #LC_PART_PERIODS
    bl      lc_part
    mov     x20, x0
    ldr     x21, [x19, #LcStore_periods]
5:  cbz     x21, 6f
    mov     x0, x19
    mov     x1, #LC_PART_UPDATES
    ldr     x2, [x20, #LcPeriod_update]
    bl      lc_mark
    add     x20, x20, #LcPeriod__mem
    sub     x21, x21, #1
    b       5b
6:  mov     x0, x19
    mov     x1, #LC_PART_UPDATES
    ldr     x2, [x19, #LcStore_latest]
    bl      lc_mark
    mov     x0, x19                         /* each marked update's headers and committee */
    mov     x1, #LC_PART_UPDATES
    bl      lc_part
    mov     x20, x0
    ldr     x21, [x19, #(LcStore_room + LcRoom_updates)]
7:  cbz     x21, 10f
    ldr     x9, [x20, #LcUpdate_state]
    cmp     x9, #LC_MARKED
    b.ne    8f
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    ldr     x2, [x20, #LcUpdate_attested_header]
    bl      lc_mark
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    ldr     x2, [x20, #LcUpdate_finalized_header]
    bl      lc_mark
    mov     x0, x19
    mov     x1, #LC_PART_COMMITTEES
    ldr     x2, [x20, #LcUpdate_next_sync_committee]
    bl      lc_mark
8:  MOVQ    x9, LcUpdate__mem
    add     x20, x20, x9
    sub     x21, x21, #1
    b       7b
10: mov     x22, #LC_PART_HEADERS           /* the sweep: LC_USED goes, LC_MARKED stays */
11: mov     x0, x19
    mov     x1, x22
    bl      lc_part
    bl      lc_mem
    mov     x20, x0
    add     x9, x19, #LcStore_room
    ldr     x21, [x9, x22, lsl #3]
12: cbz     x21, 14f
    ldr     x9, [x20]
    cmp     x9, #LC_MARKED
    cset    x9, eq                          /* LC_MARKED: LC_USED; else LC_FREE */
    str     x9, [x20]
    add     x20, x20, x12
    sub     x21, x21, #1
    b       12b
14: add     x22, x22, #1
    cmp     x22, #LC_PART_UPDATES
    b.ls    11b
    LEAVE 0
END_FUNCTION lc_collect

/*
 * L1: x0 = LANTERN_OK when the store x0 has x1 free headers, x2 committees and x3 updates, once
 * the records nothing refers to are freed; else LANTERN_BUFFER_TOO_SMALL. x19 the store, x20-x22
 * the needs, x23 1 once collected, x24 the part.
 */
LOCAL_FUNCTION lc_reserve
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, #0
1:  mov     x24, #LC_PART_HEADERS
2:  mov     x0, x19
    mov     x1, x24
    bl      lc_free_count
    cmp     x24, #LC_PART_COMMITTEES
    csel    x9, x20, x21, lo
    csel    x9, x22, x9, hi
    cmp     x0, x9
    b.hs    3f
    cbnz    x23, 9f
    mov     x0, x19
    bl      lc_collect
    mov     x23, #1
    b       1b
3:  add     x24, x24, #1
    cmp     x24, #LC_PART_UPDATES
    b.ls    2b
    mov     x0, #LANTERN_OK
    LEAVE 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lc_reserve

/* L1: x0 = the index plus 1 of the LcBlock of the root at x1 in the store x0, or 0. Uses x8-x15. */
LOCAL_FUNCTION lc_find_block
    FRAME 0
    ldr     x14, [x0, #LcStore_blocks]
    mov     x15, x1
    mov     x1, #LC_PART_BLOCKS
    bl      lc_part
    mov     x8, #0
1:  cmp     x8, x14
    b.hs    3f
    NE32    x0, x15, 2f
    add     x0, x8, #1
    UNFRAME 0
2:  add     x0, x0, #LcBlock__mem
    add     x8, x8, #1
    b       1b
3:  mov     x0, #0
    UNFRAME 0
END_FUNCTION lc_find_block

/*
 * L1: x0 = the entry (index plus 1) of the highest slot at most x2 along the parents from entry x1
 * of the store x0, or 0. Uses x8-x15.
 */
LOCAL_FUNCTION lc_ancestor
    FRAME 0
    mov     x14, x0
    mov     x15, x2
    mov     x8, x1
1:  cbz     x8, 3f
    mov     x0, x14
    mov     x1, #LC_PART_BLOCKS
    mov     x2, x8
    bl      lc_ref
    ldr     x9, [x0, #LcBlock_slot]
    cmp     x9, x15
    b.ls    2f
    ldr     x8, [x0, #LcBlock_parent]
    b       1b
2:  mov     x0, x8
    UNFRAME 0
3:  mov     x0, #0
    UNFRAME 0
END_FUNCTION lc_ancestor

/* L1: x0 = the LcFinalized of the highest slot at most x1 and at least historical_tail_slot in the store x0, or 0. Uses x9-x15. */
LOCAL_FUNCTION lc_finalized_at
    FRAME 0
    ldr     x13, [x0, #LcStore_finalized]
    ldr     x14, [x0, #LcStore_historical_tail_slot]
    mov     x15, x1
    mov     x1, #LC_PART_FINALIZED
    bl      lc_part
    mov     x9, #LcFinalized__mem
    madd    x0, x13, x9, x0
1:  cbz     x13, 3f
    sub     x0, x0, #LcFinalized__mem
    sub     x13, x13, #1
    ldr     x10, [x0, #LcFinalized_slot]
    cmp     x10, x15
    b.hi    1b
    cmp     x10, x14
    b.lo    3f
    UNFRAME 0
3:  mov     x0, #0
    UNFRAME 0
END_FUNCTION lc_finalized_at

/* L0: x0 = the set bits of the sync_committee_bits at x0. Uses x9-x11, v0. */
LOCAL_FUNCTION lc_participants
    UNWIND_END_PROLOGUE
    mov     x10, #(SYNC_COMMITTEE_SIZE / 8)
    mov     x11, #0
1:  ldrb    w9, [x0], #1
    fmov    s0, w9
    cnt     v0.8b, v0.8b
    umov    w9, v0.b[0]
    add     x11, x11, x9
    subs    x10, x10, #1
    b.ne    1b
    mov     x0, x11
    ret
END_FUNCTION lc_participants

/* x9 = the roots of a sync committee branch, x10 of a finality branch, of the fork x9. */
.macro LC_COUNTS
    cmp     x9, #FORK_ELECTRA
    mov     x9, #5
    mov     x10, #6
    cinc    x9, x9, hs
    cinc    x10, x10, hs
.endm

/* L0: x0 = 1 when the x2 bytes at x0 and x1 are equal, x2 a multiple of 8; else 0. Uses x9, x10. */
LOCAL_FUNCTION lc_equal
    UNWIND_END_PROLOGUE
1:  cbz     x2, 2f
    ldr     x9, [x0], #8
    ldr     x10, [x1], #8
    sub     x2, x2, #8
    cmp     x9, x10
    b.eq    1b
    mov     x0, #0
    ret
2:  mov     x0, #1
    ret
END_FUNCTION lc_equal

/*
 * L1: x0 = an LcCommittee reference of the sync committee bytes x1 in the store x0: x2 or x3 (each
 * a reference or 0) when its bytes are equal, else a new record. x19 the store, x20 the bytes, x21
 * and x22 the candidates, x23 the reference.
 */
LOCAL_FUNCTION lc_committee
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x21
1:  cbz     x23, 2f
    mov     x0, x19
    mov     x1, #LC_PART_COMMITTEES
    mov     x2, x23
    bl      lc_ref
    add     x0, x0, #LcCommittee_committee
    mov     x1, x20
    MOVQ    x2, LC_COMMITTEE
    bl      lc_equal
    cbnz    x0, 4f
2:  cmp     x23, x22
    b.eq    3f
    mov     x23, x22
    b       1b
3:  mov     x0, x19
    mov     x1, #LC_PART_COMMITTEES
    bl      lc_alloc
    mov     x23, x0
    mov     x1, #LC_PART_COMMITTEES
    mov     x2, x23
    mov     x0, x19
    bl      lc_ref
    add     x0, x0, #LcCommittee_committee
    mov     x1, x20
    MOVQ    x2, LC_COMMITTEE
    bl      lantern_copy
4:  mov     x0, x23
    LEAVE 0
END_FUNCTION lc_committee

/*
 * L1: hash_tree_root of the BeaconBlockHeader at x0 (its 112 SSZ bytes) at x1. x19 the header, x20
 * out, x21 the 8 chunks, x22 the pairs of the level, x23 the pair. Locals: L a ByteList, L + 32 a
 * digest, L + 64 the chunks.
 */
LOCAL_FUNCTION lc_beacon_root
    ENTER 320
    mov     x19, x0
    mov     x20, x1
    add     x21, sp, #(L + 64)
    mov     x0, x21
    mov     x1, #256
    bl      lantern_zero
    ldr     x9, [x19]                       /* slot, proposer_index, then the three roots */
    str     x9, [x21]
    ldr     x9, [x19, #8]
    str     x9, [x21, #32]
    add     x0, x21, #64
    add     x1, x19, #16
    mov     x2, #96
    bl      lantern_copy
    mov     x22, #4
1:  mov     x23, #0
2:  add     x9, sp, #L
    add     x10, x21, x23, lsl #6
    sub     x10, x10, x9
    mov     x11, #64
    add     x12, x10, x11
    stp     x12, x10, [x9]
    str     x11, [x9, #16]
    add     x0, sp, #L
    add     x1, sp, #(L + 32)
    CALL_GLOBAL crypto_sha256
    add     x9, x21, x23, lsl #5
    add     x10, sp, #(L + 32)
    COPY32  x9, x10
    add     x23, x23, #1
    cmp     x23, x22
    b.lo    2b
    lsr     x22, x22, #1
    cbnz    x22, 1b
    COPY32  x20, x21
    LEAVE 320
END_FUNCTION lc_beacon_root

/*
 * L1: x0 = a new LcHeader of the fork x1 in the store x0 (reserved before), the empty header of the
 * fork: lantern_upgrade_lc_header of 112 zero bytes from altair. x19 the store, x20 the fork, x21
 * the reference. Locals: L the ByteList of the zero bytes.
 */
LOCAL_FUNCTION lc_empty_header
    ENTER 144
    mov     x19, x0
    mov     x20, x1
    add     x0, sp, #L
    mov     x1, #144
    bl      lantern_zero
    mov     x9, #136
    mov     x10, #24
    mov     x11, #112
    stp     x9, x10, [sp, #L]
    str     x11, [sp, #(L + 16)]
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    bl      lc_alloc
    mov     x21, x0
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    mov     x2, x21
    bl      lc_ref
    str     x20, [x0, #LcHeader_fork]
    MOVQ    x9, 24 + LC_HEADER_ROOM
    str     x9, [x0, #LcHeader_header]
    add     x2, x0, #LcHeader_header
    add     x0, sp, #L
    mov     x1, #FORK_ALTAIR
    mov     x15, x20
    FORK_CALL upgrade_lc_header
    mov     x0, x21
    LEAVE 144
END_FUNCTION lc_empty_header

/*
 * L1: x0 = a new LcUpdate (reserved before, with one LcHeader) in the store x0: the update of entry
 * x1 (light-client.md, The update of an entry) with the signature slot x2, the sync aggregate at
 * x3 and the LcCommittee x4 (0: a finality update). x19 the store, x20 the entry's reference, x21
 * the signature slot, x22 the aggregate, x23 the committee, x24 the entry, x25 the update's
 * reference, x26 the update, x27 its fork, x28 a finalized entry or header.
 */
LOCAL_FUNCTION lc_make_update
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x1, #LC_PART_BLOCKS
    mov     x2, x20
    bl      lc_ref
    mov     x24, x0
    mov     x0, x19
    mov     x1, #LC_PART_UPDATES
    bl      lc_alloc
    mov     x25, x0
    mov     x0, x19
    mov     x1, #LC_PART_UPDATES
    mov     x2, x25
    bl      lc_ref
    mov     x26, x0
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    ldr     x2, [x24, #LcBlock_header]
    bl      lc_ref
    ldr     x27, [x0, #LcHeader_fork]
    str     x27, [x26, #LcUpdate_fork]
    ldr     x9, [x24, #LcBlock_header]
    str     x9, [x26, #LcUpdate_attested_header]
    str     x23, [x26, #LcUpdate_next_sync_committee]
    str     x21, [x26, #LcUpdate_signature_slot]
    add     x0, x26, #LcUpdate_next_branch
    add     x1, x24, #LcBlock_next_branch
    mov     x2, #192
    bl      lantern_copy
    add     x0, x26, #LcUpdate_sync_aggregate
    mov     x1, x22
    mov     x2, #LC_AGGREGATE
    bl      lantern_copy
    mov     x0, x19                         /* the finalized block: the LcFinalized at the entry's finalized_slot */
    ldr     x1, [x24, #LcBlock_finalized_slot]
    bl      lc_finalized_at
    cbz     x0, 5f
    mov     x28, x0
    ldr     x9, [x28, #LcFinalized_slot]
    str     x9, [x24, #LcBlock_finalized_slot]
    cbz     x9, 4f                          /* GENESIS_SLOT: the empty header, the branch */
    mov     x0, x19
    add     x1, x28, #LcFinalized_root
    bl      lc_find_block
    cbz     x0, 5f
    mov     x2, x0
    mov     x0, x19
    mov     x1, #LC_PART_BLOCKS
    bl      lc_ref
    ldr     x9, [x0, #LcBlock_header]
    str     x9, [x26, #LcUpdate_finalized_header]
    mov     x2, x9
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    bl      lc_ref
    mov     x28, x0
    ldr     x9, [x28, #LcHeader_fork]
    cmp     x9, x27
    b.eq    3f
    mov     x0, x19                         /* of an earlier fork: upgraded, in a new record */
    mov     x1, #LC_PART_HEADERS
    bl      lc_alloc
    str     x0, [x26, #LcUpdate_finalized_header]
    mov     x2, x0
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    bl      lc_ref
    str     x27, [x0, #LcHeader_fork]
    MOVQ    x9, 24 + LC_HEADER_ROOM
    str     x9, [x0, #LcHeader_header]
    add     x2, x0, #LcHeader_header
    add     x0, x28, #LcHeader_header
    ldr     x1, [x28, #LcHeader_fork]
    mov     x15, x27
    FORK_CALL upgrade_lc_header
3:  add     x0, x26, #LcUpdate_finality_branch
    add     x1, x24, #LcBlock_finality_branch
    mov     x2, #224
    bl      lantern_copy
    b       7f
4:  add     x0, x26, #LcUpdate_finality_branch
    add     x1, x24, #LcBlock_finality_branch
    mov     x2, #224
    bl      lantern_copy
    b       6f
5:  add     x0, x26, #LcUpdate_finality_branch  /* no finalized block: the empty header, a zero branch */
    mov     x1, #224
    bl      lantern_zero
6:  mov     x0, x19
    mov     x1, x27
    bl      lc_empty_header
    str     x0, [x26, #LcUpdate_finalized_header]
7:  mov     x0, x25
    LEAVE 0
END_FUNCTION lc_make_update

/*
 * L1: x0 = 1 when lantern_is_better_update of the LcUpdate x1's fork gives 1 for it and the LcUpdate
 * x2 upgraded to that fork, in the store x0 with the scratch x3 (LC_COMPARE_SCRATCH bytes, checked
 * before); else 0. x19 the store, x20 the new update, x21 the old, x22 the scratch's buffers, x23
 * the new update's fork, x24 the fork of the update in the parts, x25 an update, x26 the parts.
 * Locals: L the parts, L + 72 the answer.
 */
LOCAL_FUNCTION lc_better
    ENTER 80
    mov     x19, x0
    mov     x21, x2
    add     x22, x3, #8
    add     x26, sp, #L
    mov     x2, x1
    mov     x1, #LC_PART_UPDATES
    bl      lc_ref
    mov     x20, x0
    ldr     x23, [x20, #LcUpdate_fork]
    mov     x25, x20                        /* the new update: buffer 1 */
    mov     x24, x23
    bl      lc_better_parts
    MOVQ    x9, 24 + LC_UPDATE_ROOM
    str     x9, [x22]
    mov     x0, #LC_OBJECT_UPDATE
    mov     x1, x26
    mov     x2, x22
    mov     x15, x23
    FORK_CALL lc_object
    cbnz    x0, 9f
    mov     x0, x19                         /* the old one, its headers upgraded: buffer 2 */
    mov     x1, #LC_PART_UPDATES
    mov     x2, x21
    bl      lc_ref
    mov     x25, x0
    ldr     x24, [x25, #LcUpdate_fork]
    bl      lc_better_parts
    cmp     x24, x23
    b.eq    1f
    MOVQ    x9, 2 * (24 + LC_UPDATE_ROOM)   /* the headers' buffers, after the two updates' */
    add     x2, x22, x9
    mov     x10, #(24 + LC_HEADER_ROOM)
    str     x10, [x2]
    ldr     x0, [x26, #LcParts_header]
    str     x2, [x26, #LcParts_header]
    mov     x1, x24
    mov     x15, x23
    FORK_CALL upgrade_lc_header
    cbnz    x0, 9f
    MOVQ    x9, 2 * (24 + LC_UPDATE_ROOM) + 24 + LC_HEADER_ROOM
    add     x2, x22, x9
    mov     x10, #(24 + LC_HEADER_ROOM)
    str     x10, [x2]
    ldr     x0, [x26, #LcParts_finalized_header]
    str     x2, [x26, #LcParts_finalized_header]
    mov     x1, x24
    mov     x15, x23
    FORK_CALL upgrade_lc_header
    cbnz    x0, 9f
1:  MOVQ    x9, 24 + LC_UPDATE_ROOM
    add     x2, x22, x9
    str     x9, [x2]
    mov     x0, #LC_OBJECT_UPDATE
    mov     x1, x26
    mov     x15, x23
    FORK_CALL lc_object
    cbnz    x0, 9f
    mov     x0, x22
    MOVQ    x9, 24 + LC_UPDATE_ROOM
    add     x1, x22, x9
    add     x2, sp, #(L + 72)
    mov     x15, x23
    FORK_CALL is_better_update
    cbnz    x0, 9f
    ldr     x0, [sp, #(L + 72)]
    LEAVE 80
9:  mov     x0, #0
    LEAVE 80
END_FUNCTION lc_better

/* L1, lc_better's: the LcParts x26 of the LcUpdate x25 of the fork x24 in the store x19, the branches at their counts. Uses x0-x2, x9-x12. */
LOCAL_FUNCTION lc_better_parts
    FRAME 0
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    ldr     x2, [x25, #LcUpdate_attested_header]
    bl      lc_ref
    add     x0, x0, #LcHeader_header
    str     x0, [x26, #LcParts_header]
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    ldr     x2, [x25, #LcUpdate_finalized_header]
    bl      lc_ref
    add     x0, x0, #LcHeader_header
    str     x0, [x26, #LcParts_finalized_header]
    mov     x0, x19
    mov     x1, #LC_PART_COMMITTEES
    ldr     x2, [x25, #LcUpdate_next_sync_committee]
    bl      lc_ref
    add     x0, x0, #LcCommittee_committee
    str     x0, [x26, #LcParts_sync_committee]
    add     x0, x25, #LcUpdate_next_branch
    str     x0, [x26, #LcParts_branch]
    add     x0, x25, #LcUpdate_finality_branch
    str     x0, [x26, #LcParts_finality_branch]
    add     x0, x25, #LcUpdate_sync_aggregate
    str     x0, [x26, #LcParts_sync_aggregate]
    ldr     x0, [x25, #LcUpdate_signature_slot]
    str     x0, [x26, #LcParts_signature_slot]
    mov     x9, x24
    LC_COUNTS
    str     x9, [x26, #LcParts_branch_count]
    str     x10, [x26, #LcParts_finality_count]
    UNFRAME 0
END_FUNCTION lc_better_parts

/*
 * L1: x0 = status: the LcBlock of the block x3 (ByteList) with its post-state x2 in the store x0,
 * the config x1, the StateCache x4 (or 0), the scratch x5; with x6 1 the anchor of
 * lantern_lc_store_init, else lantern_lc_on_block. x19 the store, x20 config, x21 state, x22
 * block, x23 cache, x24 scratch, x25 the new entry, x26 the block's fork, x27 the header's
 * reference, x28 the parent entry. Locals: L the anchor flag, L + 8 the slot, L + 16 the header's
 * bytes, L + 24 the root, L + 56 the parent's reference, L + 64 the update, L + 72 the header.
 */
LOCAL_FUNCTION lc_add_block
    ENTER 80
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    str     x6, [sp, #L]
    mov     x0, x19                         /* the room first */
    mov     x1, #2
    mov     x2, #2
    mov     x3, #1
    bl      lc_reserve
    cbnz    x0, 98f
    ldr     x9, [x19, #LcStore_blocks]
    ldr     x10, [x19, #(LcStore_room + LcRoom_blocks)]
    cmp     x9, x10
    b.hs    98f
    ldr     x9, [x24]
    MOVQ    x10, LC_COMPARE_SCRATCH
    cmp     x9, x10
    b.lo    98f
    ldr     x0, [x21, #NODE_STATE_SLOT]     /* the anchor: the fork of the state's slot */
    ldr     x9, [sp, #L]
    cbnz    x9, 5f
    ldr     x9, [x22, #8]                   /* else the block's slot, for its fork */
    add     x9, x22, x9
    ldr     x10, [x22, #16]
    cmp     x10, #4
    b.lo    96f
    ldr     w11, [x9]
    add     x12, x11, #8
    cmp     x12, x10
    b.hi    96f
    ldr     x0, [x9, x11]
5:  mov     x1, x20
    bl      node_fork
    mov     x26, x0
    mov     x0, x19                         /* the header */
    mov     x1, #LC_PART_HEADERS
    bl      lc_alloc
    mov     x27, x0
    mov     x2, x0
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    bl      lc_ref
    str     x0, [sp, #(L + 72)]
    mov     x9, #FORK_ALTAIR
    cmp     x26, x9
    csel    x9, x26, x9, hs
    str     x9, [x0, #LcHeader_fork]
    MOVQ    x9, 24 + LC_HEADER_ROOM
    str     x9, [x0, #LcHeader_header]
    add     x2, x0, #LcHeader_header
    mov     x0, x22
    mov     x1, x24
    mov     x15, x26
    ldr     x9, [sp, #L]
    cbnz    x9, 6f
    FORK_CALL block_to_light_client_header
    b       7f
6:  FORK_CALL lc_anchor_header              /* the anchor: of its block's value */
7:  cbnz    x0, 90f
    ldr     x9, [sp, #(L + 72)]             /* the root: of the header's beacon; the slot its slot */
    add     x9, x9, #LcHeader_header
    ldr     x10, [x9, #8]
    add     x0, x9, x10
    str     x0, [sp, #(L + 16)]
    ldr     x9, [x0]
    str     x9, [sp, #(L + 8)]
    add     x1, sp, #(L + 24)
    bl      lc_beacon_root
    mov     x0, x19
    add     x1, sp, #(L + 24)
    bl      lc_find_block
    cbnz    x0, 95f
    mov     x0, x19                         /* the entry, at the end of blocks */
    mov     x1, #LC_PART_BLOCKS
    ldr     x2, [x19, #LcStore_blocks]
    bl      lc_at
    mov     x25, x0
    MOVQ    x1, LcBlock__mem
    bl      lantern_zero
    add     x9, x25, #LcBlock_root
    add     x10, sp, #(L + 24)
    COPY32  x9, x10
    ldr     x10, [sp, #(L + 16)]
    add     x10, x10, #16
    add     x9, x25, #LcBlock_parent_root
    COPY32  x9, x10
    ldr     x9, [sp, #(L + 8)]
    str     x9, [x25, #LcBlock_slot]
    str     x27, [x25, #LcBlock_header]
    mov     x0, x19
    add     x1, x25, #LcBlock_parent_root
    bl      lc_find_block
    str     x0, [x25, #LcBlock_parent]
    str     x0, [sp, #(L + 56)]
    ldr     x9, [sp, #L]                    /* from altair, but the anchor: the body's sync_aggregate */
    cbnz    x9, 10f
    cmp     x26, #FORK_ALTAIR
    b.lo    10f
    ldr     x9, [x22, #8]
    add     x9, x22, x9
    ldr     w10, [x9]
    add     x10, x9, x10
    ldr     w11, [x10, #80]
    add     x1, x10, x11
    add     x1, x1, #220
    add     x0, x25, #LcBlock_sync_aggregate
    mov     x2, #LC_AGGREGATE
    bl      lantern_copy
10: ldr     x9, [sp, #L]
    cbz     x9, 11f
    cmp     x26, #FORK_ALTAIR               /* the anchor: data from altair */
    b.lo    50f
    b       20f
11: ldr     x9, [sp, #(L + 8)]
    ldr     x10, [x19, #LcStore_tail_slot]
    cmp     x9, x10
    b.lo    50f
    ldr     x9, [sp, #(L + 56)]
    cbz     x9, 94f
20: mov     x9, #1                          /* the data: branches, finalized_slot, committees */
    str     x9, [x25, #LcBlock_data]
    mov     x28, #0
21: mov     x0, x21
    mov     x1, x28
    mov     x2, x23
    mov     x3, x24
    add     x4, x25, #LcBlock_current_branch
    mov     x9, #192
    madd    x4, x28, x9, x4
    mov     x15, x26
    FORK_CALL state_branch
    cbnz    x0, 90f
    add     x28, x28, #1
    cmp     x28, #LC_BRANCH_FINALIZED_ROOT
    b.ls    21b
    LDQ     x9, x21, NODE_STATE_FINALIZED
    mov     x10, #SLOTS_PER_EPOCH
    mul     x9, x9, x10
    str     x9, [x25, #LcBlock_finalized_slot]
    mov     x2, #0                          /* the parent's committees, as candidates */
    mov     x3, #0
    ldr     x28, [sp, #(L + 56)]
    cbz     x28, 22f
    mov     x0, x19
    mov     x1, #LC_PART_BLOCKS
    mov     x2, x28
    bl      lc_ref
    mov     x28, x0
    ldr     x2, [x28, #LcBlock_current_sync_committee]
    ldr     x3, [x28, #LcBlock_next_sync_committee]
22: mov     x0, x19
    ADDQ    x1, x21, NODE_STATE_CURRENT_SYNC_COMMITTEE
    bl      lc_committee
    str     x0, [x25, #LcBlock_current_sync_committee]
    mov     x2, #0
    cbz     x28, 23f
    ldr     x2, [x28, #LcBlock_next_sync_committee]
23: ldr     x3, [x25, #LcBlock_current_sync_committee]
    mov     x0, x19
    ADDQ    x1, x21, NODE_STATE_NEXT_SYNC_COMMITTEE
    bl      lc_committee
    str     x0, [x25, #LcBlock_next_sync_committee]
    ldr     x9, [sp, #L]
    cbnz    x9, 50f                         /* the anchor: no best update, latest_signature_slot GENESIS_SLOT */
    ldr     x9, [x28, #LcBlock_slot]        /* the attested block: the parent, x28 */
    ldr     x10, [x19, #LcStore_tail_slot]
    cmp     x9, x10
    b.lo    50f
    MOVQ    x10, LC_SPP
    udiv    x11, x9, x10                    /* x11 its period, x12 the block's */
    ldr     x12, [sp, #(L + 8)]
    udiv    x12, x12, x10
    mov     x13, #0
    cmp     x11, x12
    b.ne    24f
    ldr     x13, [x28, #LcBlock_best]
24: str     x13, [x25, #LcBlock_best]
    cmp     x11, x12
    cset    x27, ne                         /* x27: 1 when the periods differ */
    add     x0, x25, #LcBlock_sync_aggregate
    bl      lc_participants
    ldr     x9, [sp, #(L + 8)]
    cmp     x0, #MIN_SYNC_COMMITTEE_PARTICIPANTS
    b.hs    25f
    ldr     x9, [x28, #LcBlock_latest_signature_slot]
25: str     x9, [x25, #LcBlock_latest_signature_slot]
    b.lo    50f
    cbnz    x27, 50f
    mov     x0, x19                         /* the update; it becomes best when better */
    ldr     x1, [sp, #(L + 56)]
    ldr     x2, [sp, #(L + 8)]
    add     x3, x25, #LcBlock_sync_aggregate
    ldr     x4, [x25, #LcBlock_next_sync_committee]
    bl      lc_make_update
    str     x0, [sp, #(L + 64)]
    ldr     x2, [x25, #LcBlock_best]
    cbz     x2, 40f
    mov     x1, x0
    mov     x0, x19
    mov     x3, x24
    bl      lc_better
    cbz     x0, 50f
40: ldr     x9, [sp, #(L + 64)]
    str     x9, [x25, #LcBlock_best]
50: ldr     x9, [x19, #LcStore_blocks]
    add     x9, x9, #1
    str     x9, [x19, #LcStore_blocks]
    mov     x0, #LANTERN_OK
    LEAVE 80
90: ldr     x9, [sp, #(L + 72)]             /* a status: the header's record is free again */
    str     xzr, [x9]
    LEAVE 80
94: ldr     x9, [sp, #(L + 72)]
    str     xzr, [x9]
    mov     x0, #LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 80
95: ldr     x9, [sp, #(L + 72)]
    str     xzr, [x9]
    mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 80
96: mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 80
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
END_FUNCTION lc_add_block

/*
 * L1: an LcBootstrap of the LcFinalized x1 in the store x0 (room checked before), when the store
 * holds none of its root and holds its LcBlock with data. x19 the store, x20 the LcFinalized, x21
 * the bootstraps, x22 their count, x23 the entry.
 */
LOCAL_FUNCTION lc_add_bootstrap
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x1, #LC_PART_BOOTSTRAPS
    bl      lc_part
    mov     x21, x0
    ldr     x22, [x19, #LcStore_bootstraps]
    mov     x23, #0
    add     x15, x20, #LcFinalized_root
1:  cmp     x23, x22
    b.hs    2f
    mov     x9, #LcBootstrap__mem
    madd    x9, x23, x9, x21
    NE32    x9, x15, 3f
    LEAVE 0
3:  add     x23, x23, #1
    b       1b
2:  mov     x0, x19
    add     x1, x20, #LcFinalized_root
    bl      lc_find_block
    cbz     x0, 9f
    mov     x2, x0
    mov     x0, x19
    mov     x1, #LC_PART_BLOCKS
    bl      lc_ref
    mov     x23, x0
    ldr     x9, [x23, #LcBlock_data]
    cbz     x9, 9f
    mov     x9, #LcBootstrap__mem
    madd    x0, x22, x9, x21
    add     x10, x20, #LcFinalized_root
    COPY32  x0, x10
    ldr     x9, [x20, #LcFinalized_slot]
    str     x9, [x0, #LcBootstrap_slot]
    ldr     x9, [x23, #LcBlock_header]
    str     x9, [x0, #LcBootstrap_header]
    ldr     x9, [x23, #LcBlock_current_sync_committee]
    str     x9, [x0, #LcBootstrap_sync_committee]
    add     x0, x0, #LcBootstrap_branch
    add     x1, x23, #LcBlock_current_branch
    mov     x2, #192
    bl      lantern_copy
    add     x22, x22, #1
    str     x22, [x19, #LcStore_bootstraps]
9:  LEAVE 0
END_FUNCTION lc_add_bootstrap

/*
 * L1: the LcPeriod of period x1 in the store x0 refers to update x2 (room checked before); with x2
 * 0, the period has none. x19 the store, x20 the period, x21 the update, x22 the periods, x23 their
 * count, x24 the index.
 */
LOCAL_FUNCTION lc_set_period
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x1, #LC_PART_PERIODS
    bl      lc_part
    mov     x22, x0
    ldr     x23, [x19, #LcStore_periods]
    mov     x24, #0
1:  cmp     x24, x23                        /* the first entry of a period at least x20 */
    b.hs    2f
    lsl     x9, x24, #4
    ldr     x9, [x22, x9]
    cmp     x9, x20
    b.hs    2f
    add     x24, x24, #1
    b       1b
2:  add     x10, x22, x24, lsl #4
    cmp     x24, x23
    b.hs    4f
    ldr     x9, [x10, #LcPeriod_period]
    cmp     x9, x20
    b.ne    4f
    cbz     x21, 3f
    str     x21, [x10, #LcPeriod_update]    /* the period's entry: the new update */
    LEAVE 0
3:  sub     x23, x23, #1                    /* none: its entry goes */
    str     x23, [x19, #LcStore_periods]
    mov     x0, x10
    add     x1, x10, #LcPeriod__mem
    sub     x2, x23, x24
    lsl     x2, x2, #4
    bl      lantern_copy
    LEAVE 0
4:  cbz     x21, 9f                         /* a new entry at x24: the later ones up by one */
    mov     x9, x23
5:  cmp     x9, x24
    b.ls    6f
    add     x11, x22, x9, lsl #4
    ldp     x12, x13, [x11, #-16]
    stp     x12, x13, [x11]
    sub     x9, x9, #1
    b       5b
6:  stp     x20, x21, [x10]
    add     x23, x23, #1
    str     x23, [x19, #LcStore_periods]
9:  LEAVE 0
END_FUNCTION lc_set_period

/*
 * L1: the LcBlock entries of slots below x1 in the store x0 go, with the scratch x2 (8 bytes for
 * each entry, checked before) for their new indices. x19 the store, x20 the slot, x21 the indices,
 * x22 the entries, x23 their count, x24 the index, x25 the kept ones.
 */
LOCAL_FUNCTION lc_prune
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    add     x21, x2, #8
    mov     x1, #LC_PART_BLOCKS
    bl      lc_part
    mov     x22, x0
    ldr     x23, [x19, #LcStore_blocks]
    mov     x24, #0
    mov     x25, #0
1:  cmp     x24, x23                        /* each entry's new index plus 1, or 0; its parent's */
    b.hs    3f
    MOVQ    x9, LcBlock__mem
    madd    x10, x24, x9, x22
    ldr     x11, [x10, #LcBlock_slot]
    mov     x12, #0
    cmp     x11, x20
    b.lo    2f
    add     x25, x25, #1
    mov     x12, x25
    ldr     x13, [x10, #LcBlock_parent]
    cbz     x13, 2f
    sub     x13, x13, #1
    ldr     x13, [x21, x13, lsl #3]
    str     x13, [x10, #LcBlock_parent]
2:  str     x12, [x21, x24, lsl #3]
    add     x24, x24, #1
    b       1b
3:  mov     x24, #0                         /* the kept ones down to their new places */
4:  cmp     x24, x23
    b.hs    6f
    ldr     x12, [x21, x24, lsl #3]
    sub     x12, x12, #1
    cmp     x12, x24
    b.hs    5f                              /* gone (0 - 1), or in place */
    MOVQ    x9, LcBlock__mem
    madd    x0, x12, x9, x22
    madd    x1, x24, x9, x22
    mov     x2, x9
    bl      lantern_copy
5:  add     x24, x24, #1
    b       4b
6:  str     x25, [x19, #LcStore_blocks]
    LEAVE 0
END_FUNCTION lc_prune


/* (room, size) -> status: LC_STORE_FIXED plus each capacity times its bytes (light-client.md). */
FUNCTION lantern_lc_store_size
    FRAME 0
    mov     x13, x0
    mov     x14, x1
    MOVQ    x2, LC_STORE_FIXED
    mov     x1, #0
1:  ldr     x4, [x13, x1, lsl #3]
    bl      lc_mem
    umulh   x9, x4, x12
    cbnz    x9, 9f
    mul     x4, x4, x12
    adds    x2, x2, x4
    b.cs    9f
    add     x1, x1, #1
    cmp     x1, #LC_PART_UPDATES
    b.ls    1b
    str     x2, [x14]
    mov     x0, #LANTERN_OK
    UNFRAME 0
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    UNFRAME 0
END_FUNCTION lantern_lc_store_size

/* x9 = x9 times SLOTS_PER_EPOCH, 2^64 - 1 when it overflows. Uses x10, x11. */
.macro LC_EPOCH_SLOT
    mov     x10, #SLOTS_PER_EPOCH
    umulh   x11, x9, x10
    mul     x9, x9, x10
    cmp     x11, #0
    csinv   x9, x9, xzr, eq
.endm

/*
 * (room, config, state, block, scratch, lc) -> status: an LcStore at an anchor (light-client.md).
 * x19 room, x20 config, x21 state, x22 block, x23 scratch, x24 lc, x25 the anchor's entry, x26
 * its LcFinalized. Locals: L the size.
 */
FUNCTION lantern_lc_store_init
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    add     x1, sp, #L
    bl      lantern_lc_store_size
    cbnz    x0, 99f
    ldr     x9, [sp, #L]
    ldr     x10, [x24]
    cmp     x10, x9
    b.lo    98f
    mov     x25, #0                         /* 2 of each at least */
1:  ldr     x9, [x19, x25, lsl #3]
    cmp     x9, #2
    b.lo    98f
    add     x25, x25, #1
    cmp     x25, #LC_PART_UPDATES
    b.ls    1b
    add     x0, x24, #8                     /* every field 0, every record LC_FREE */
    ldr     x1, [sp, #L]
    sub     x1, x1, #8
    bl      lantern_zero
    add     x0, x24, #LcStore_room
    mov     x1, x19
    mov     x2, #LcRoom__mem
    bl      lantern_copy
    ldr     x12, [x21, #NODE_STATE_SLOT]
    str     x12, [x24, #LcStore_historical_tail_slot]
    ldr     x9, [x20, #CONFIG_ALTAIR_FORK_EPOCH]
    LC_EPOCH_SLOT
    cmp     x12, x9
    csel    x9, x12, x9, hs
    str     x9, [x24, #LcStore_tail_slot]
    LDQ     x9, x21, NODE_STATE_FINALIZED
    str     x9, [x24, #LcStore_latest_finalized_epoch]
    LC_EPOCH_SLOT
    str     x9, [x24, #LcStore_latest_finalized_slot]
    add     x9, x24, #LcStore_latest_finalized_root
    ADDQ    x10, x21, NODE_STATE_FINALIZED + 8
    COPY32  x9, x10
    mov     x0, x24                         /* the anchor's entry, its LcFinalized and bootstrap */
    mov     x1, x20
    mov     x2, x21
    mov     x3, x22
    mov     x4, #0
    mov     x5, x23
    mov     x6, #1
    bl      lc_add_block
    cbnz    x0, 99f
    mov     x0, x24
    mov     x1, #LC_PART_BLOCKS
    mov     x2, #0
    bl      lc_at
    mov     x25, x0
    mov     x0, x24
    mov     x1, #LC_PART_FINALIZED
    bl      lc_part
    mov     x26, x0
    ldr     x9, [x25, #LcBlock_slot]
    str     x9, [x26, #LcFinalized_slot]
    add     x9, x26, #LcFinalized_root
    COPY32  x9, x25
    mov     x9, #1
    str     x9, [x24, #LcStore_finalized]
    mov     x0, x24
    mov     x1, x26
    bl      lc_add_bootstrap
    mov     x0, #LANTERN_OK
    LEAVE 16
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
99: LEAVE 16
END_FUNCTION lantern_lc_store_init

/*
 * (lc, room, out) -> status: the store in a new buffer (light-client.md). x19 lc, x20 room, x21
 * out, x22 the part, x23 its source, x24 its target, x25 an entry's bytes, x26 the old records'
 * bytes. Locals: L the size.
 */
FUNCTION lantern_lc_store_copy
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x0, x20
    add     x1, sp, #L
    bl      lantern_lc_store_size
    cbnz    x0, 99f
    ldr     x9, [sp, #L]
    ldr     x10, [x21]
    cmp     x10, x9
    b.lo    98f
    mov     x22, #0
1:  ldr     x9, [x20, x22, lsl #3]
    add     x10, x19, #LcStore_room
    ldr     x10, [x10, x22, lsl #3]
    cmp     x9, x10
    b.lo    98f
    add     x22, x22, #1
    cmp     x22, #LC_PART_UPDATES
    b.ls    1b
    add     x0, x21, #8                     /* the fixed fields, then the new room */
    add     x1, x19, #8
    mov     x2, #(LC_STORE_FIXED - 8)
    bl      lantern_copy
    add     x0, x21, #LcStore_room
    mov     x1, x20
    mov     x2, #LcRoom__mem
    bl      lantern_copy
    mov     x22, #0
2:  mov     x0, x19
    mov     x1, x22
    bl      lc_part
    mov     x23, x0
    mov     x0, x21
    mov     x1, x22
    bl      lc_part
    mov     x24, x0
    bl      lc_mem
    mov     x25, x12
    cmp     x22, #LC_PART_BOOTSTRAPS
    b.hi    3f
    add     x9, x19, #LcStore_blocks        /* an entry part: its entries */
    ldr     x9, [x9, x22, lsl #3]
    mul     x2, x9, x25
    mov     x0, x24
    mov     x1, x23
    bl      lantern_copy
    b       4f
3:  add     x9, x19, #LcStore_room          /* a record part: its records, the new ones LC_FREE */
    ldr     x9, [x9, x22, lsl #3]
    mul     x26, x9, x25
    mov     x0, x24
    mov     x1, x23
    mov     x2, x26
    bl      lantern_copy
    ldr     x9, [x20, x22, lsl #3]
    mul     x1, x9, x25
    sub     x1, x1, x26
    add     x0, x24, x26
    bl      lantern_zero
4:  add     x22, x22, #1
    cmp     x22, #LC_PART_UPDATES
    b.ls    2b
    mov     x0, #LANTERN_OK
    LEAVE 16
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
99: LEAVE 16
END_FUNCTION lantern_lc_store_copy

/* (lc, config, state, block, cache, scratch) -> status: lantern_lc_on_block (light-client.md). */
FUNCTION lantern_lc_on_block
    FRAME 0
    mov     x6, #0
    bl      lc_add_block
    UNFRAME 0
END_FUNCTION lantern_lc_on_block

/*
 * (lc, config, head, checkpoint, scratch) -> status: lantern_lc_on_head (light-client.md). x19 lc,
 * x20 config, x21 head, x22 checkpoint, x23 scratch, x24 the head's entry (a reference), x25 the
 * checkpoint's entry when it is new, else 0, x26 an entry, x27 and x28 a period, an entry or an
 * index. Locals: L low_slot, L + 8 the new LcFinalized, L + 16 the boundary slot, L + 24 the low
 * slot of the bootstraps, L + 32 the slot the new LcFinalized are above, L + 40 an entry, L + 48
 * an update or a slot.
 */
FUNCTION lantern_lc_on_head
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x0, x19
    mov     x1, x21
    bl      lc_find_block
    cbz     x0, 94f
    mov     x24, x0
    mov     x25, #0
    ldr     x9, [x22]
    cbz     x9, 1f
    mov     x0, x19
    add     x1, x22, #8
    bl      lc_find_block
    cbz     x0, 94f
    mov     x2, x0
    mov     x0, x19
    mov     x1, #LC_PART_BLOCKS
    bl      lc_ref
    ldr     x9, [x0, #LcBlock_slot]
    ldr     x10, [x19, #LcStore_latest_finalized_slot]
    cmp     x9, x10
    b.ls    1f
    mov     x25, x2
1:  mov     x0, x19                         /* the room: records, scratch, periods, finalized, bootstraps */
    mov     x1, #1
    mov     x2, #0
    mov     x3, #1
    bl      lc_reserve
    cbnz    x0, 98f
    ldr     x9, [x19, #LcStore_blocks]
    lsl     x9, x9, #3
    add     x9, x9, #8
    ldr     x10, [x23]
    cmp     x10, x9
    b.lo    98f
    mov     x0, x19
    mov     x1, #LC_PART_BLOCKS
    mov     x2, x24
    bl      lc_ref
    mov     x26, x0
    ldr     x9, [x19, #LcStore_tail_slot]
    ldr     x10, [x19, #LcStore_latest_finalized_slot]
    cmp     x9, x10
    csel    x9, x9, x10, hs
    str     x9, [sp, #L]
    ldr     x11, [x26, #LcBlock_slot]
    ldr     x12, [x19, #LcStore_tail_slot]
    mov     x13, #0
    cmp     x11, x12
    b.lo    2f
    MOVQ    x14, LC_SPP
    udiv    x11, x11, x14
    udiv    x12, x9, x14
    cmp     x11, x12
    b.lo    2f
    sub     x13, x11, x12
    add     x13, x13, #1
2:  ldr     x9, [x19, #LcStore_periods]
    add     x9, x9, x13
    ldr     x10, [x19, #(LcStore_room + LcRoom_periods)]
    cmp     x9, x10
    b.hi    98f
    str     xzr, [sp, #(L + 8)]
    cbz     x25, 4f
    ldr     x27, [x19, #LcStore_latest_finalized_slot]   /* above it and the last LcFinalized */
    ldr     x2, [x19, #LcStore_finalized]
    cbz     x2, 21f
    sub     x2, x2, #1
    mov     x0, x19
    mov     x1, #LC_PART_FINALIZED
    bl      lc_at
    ldr     x9, [x0, #LcFinalized_slot]
    cmp     x9, x27
    csel    x27, x9, x27, hi
21: str     x27, [sp, #(L + 32)]
    mov     x28, x25
3:  cbz     x28, 31f
    mov     x0, x19
    mov     x1, #LC_PART_BLOCKS
    mov     x2, x28
    bl      lc_ref
    ldr     x9, [x0, #LcBlock_slot]
    cmp     x9, x27
    b.ls    31f
    ldr     x9, [sp, #(L + 8)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 8)]
    ldr     x28, [x0, #LcBlock_parent]
    b       3b
31: ldr     x9, [sp, #(L + 8)]
    ldr     x10, [x19, #LcStore_finalized]
    add     x10, x10, x9
    ldr     x11, [x19, #(LcStore_room + LcRoom_finalized)]
    cmp     x10, x11
    b.hi    98f
    ldr     x10, [x19, #LcStore_bootstraps]
    add     x10, x10, x9
    ldr     x11, [x19, #(LcStore_room + LcRoom_bootstraps)]
    cmp     x10, x11
    b.hi    98f
4:  ldr     x9, [x26, #LcBlock_slot]        /* the head */
    ldr     x10, [x19, #LcStore_tail_slot]
    cmp     x9, x10
    b.lo    30f
    MOVQ    x10, LC_SPP
    udiv    x27, x9, x10
    ldr     x11, [sp, #L]
    udiv    x28, x11, x10
    cmp     x27, x28
    b.lo    10f
    str     x24, [sp, #(L + 40)]
5:  add     x9, x27, #1                     /* period x27: the entry at its last slot */
    MOVQ    x10, LC_SPP
    mul     x2, x9, x10
    sub     x2, x2, #1
    mov     x0, x19
    ldr     x1, [sp, #(L + 40)]
    bl      lc_ancestor
    cbz     x0, 10f
    str     x0, [sp, #(L + 40)]
    mov     x2, x0
    mov     x0, x19
    mov     x1, #LC_PART_BLOCKS
    bl      lc_ref
    ldr     x9, [x0, #LcBlock_slot]
    ldr     x10, [sp, #L]
    cmp     x9, x10
    b.lo    10f
    ldr     x2, [x0, #LcBlock_best]
    cbz     x2, 7f
    str     x2, [sp, #(L + 48)]
    mov     x0, x19
    mov     x1, #LC_PART_UPDATES
    bl      lc_ref
    add     x0, x0, #LcUpdate_sync_aggregate
    bl      lc_participants
    ldr     x2, [sp, #(L + 48)]
    cmp     x0, #MIN_SYNC_COMMITTEE_PARTICIPANTS
    b.hs    7f
    mov     x2, #0
7:  mov     x0, x19
    mov     x1, x27
    bl      lc_set_period
    cmp     x27, x28
    b.eq    10f
    sub     x27, x27, #1
    b       5b
10: ldr     x9, [x26, #LcBlock_latest_signature_slot]   /* latest: S at it, A before S */
    str     x9, [sp, #(L + 48)]
    ldr     x10, [sp, #L]
    cmp     x9, x10
    b.ls    12f
    mov     x0, x19
    mov     x1, x24
    mov     x2, x9
    bl      lc_ancestor
    cbz     x0, 12f
    str     x0, [sp, #(L + 40)]
    mov     x2, x0
    mov     x0, x19
    mov     x1, #LC_PART_BLOCKS
    bl      lc_ref
    mov     x27, x0
    ldr     x9, [x27, #LcBlock_slot]
    ldr     x10, [sp, #L]
    cmp     x9, x10
    b.ls    12f
    sub     x2, x9, #1
    mov     x0, x19
    ldr     x1, [sp, #(L + 40)]
    bl      lc_ancestor
    cbz     x0, 12f
    mov     x28, x0
    mov     x2, x0
    mov     x0, x19
    mov     x1, #LC_PART_BLOCKS
    bl      lc_ref
    ldr     x9, [x0, #LcBlock_slot]
    ldr     x10, [sp, #L]
    cmp     x9, x10
    b.lo    12f
    mov     x0, x19
    mov     x1, x28
    ldr     x2, [sp, #(L + 48)]
    add     x3, x27, #LcBlock_sync_aggregate
    mov     x4, #0
    bl      lc_make_update
    str     x0, [x19, #LcStore_latest]
    b       30f
12: str     xzr, [x19, #LcStore_latest]
30: cbz     x25, 60f                        /* the checkpoint: its LcFinalized from the top down */
    ldr     x9, [x19, #LcStore_finalized]
    ldr     x10, [sp, #(L + 8)]
    add     x9, x9, x10
    str     x9, [x19, #LcStore_finalized]
    sub     x28, x9, #1
    mov     x26, x25
32: ldr     x9, [sp, #(L + 8)]
    cbz     x9, 33f
    sub     x9, x9, #1
    str     x9, [sp, #(L + 8)]
    mov     x0, x19
    mov     x1, #LC_PART_BLOCKS
    mov     x2, x26
    bl      lc_ref
    mov     x24, x0
    mov     x0, x19
    mov     x1, #LC_PART_FINALIZED
    mov     x2, x28
    bl      lc_at
    ldr     x9, [x24, #LcBlock_slot]
    str     x9, [x0, #LcFinalized_slot]
    add     x9, x0, #LcFinalized_root
    COPY32  x9, x24
    sub     x28, x28, #1
    ldr     x26, [x24, #LcBlock_parent]
    b       32b
33: mov     x0, x19
    mov     x1, #LC_PART_BLOCKS
    mov     x2, x25
    bl      lc_ref
    mov     x26, x0
    ldr     x9, [x22]
    str     x9, [x19, #LcStore_latest_finalized_epoch]
    ldr     x27, [x19, #LcStore_latest_finalized_slot]
    ldr     x9, [x26, #LcBlock_slot]
    str     x9, [x19, #LcStore_latest_finalized_slot]
    add     x10, x19, #LcStore_latest_finalized_root
    COPY32  x10, x26
    ldr     x10, [x19, #LcStore_tail_slot]  /* the bootstraps of the new epoch boundary blocks */
    cmp     x9, x10
    b.lo    50f
    add     x11, x27, #1
    cmp     x11, x10
    csel    x11, x11, x10, hs
    str     x11, [sp, #(L + 24)]
    str     x9, [sp, #(L + 16)]
40: ldr     x1, [sp, #(L + 16)]
    ldr     x10, [sp, #(L + 24)]
    cmp     x1, x10
    b.lo    50f
    mov     x0, x19
    bl      lc_finalized_at
    cbz     x0, 50f
    mov     x28, x0
    ldr     x9, [x28, #LcFinalized_slot]
    ldr     x10, [sp, #(L + 24)]
    cmp     x9, x10
    b.lo    41f
    mov     x0, x19
    mov     x1, x28
    bl      lc_add_bootstrap
41: ldr     x9, [x28, #LcFinalized_slot]
    add     x9, x9, #(SLOTS_PER_EPOCH - 1)
    mov     x10, #SLOTS_PER_EPOCH
    udiv    x9, x9, x10
    mul     x9, x9, x10
    cmp     x9, x10
    b.lo    50f
    sub     x9, x9, x10
    str     x9, [sp, #(L + 16)]
    b       40b
50: mov     x0, x19                         /* the entries below the checkpoint's go */
    ldr     x1, [x26, #LcBlock_slot]
    mov     x2, x23
    bl      lc_prune
60: mov     x0, #LANTERN_OK
    LEAVE 64
94: mov     x0, #LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 64
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_lc_on_head

/*
 * (lc, kind, key, out, fork) -> status: lantern_lc_read (light-client.md). x19 lc, x20 kind, x21
 * key, x22 out, x23 fork, x24 the bootstrap or update, x25 a count, x26 its fork. Locals: L the
 * parts.
 */
FUNCTION lantern_lc_read
    ENTER 80
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    cmp     x20, #LC_OBJECT_OPTIMISTIC_UPDATE
    b.hi    97f
    cbnz    x20, 10f
    mov     x1, #LC_PART_BOOTSTRAPS         /* the bootstrap of the root */
    bl      lc_part
    mov     x24, x0
    ldr     x25, [x19, #LcStore_bootstraps]
1:  cbz     x25, 93f
    NE32    x24, x21, 2f
    b       3f
2:  add     x24, x24, #LcBootstrap__mem
    sub     x25, x25, #1
    b       1b
3:  mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    ldr     x2, [x24, #LcBootstrap_header]
    bl      lc_ref
    ldr     x26, [x0, #LcHeader_fork]
    add     x0, x0, #LcHeader_header
    str     x0, [sp, #(L + LcParts_header)]
    mov     x0, x19
    mov     x1, #LC_PART_COMMITTEES
    ldr     x2, [x24, #LcBootstrap_sync_committee]
    bl      lc_ref
    add     x0, x0, #LcCommittee_committee
    str     x0, [sp, #(L + LcParts_sync_committee)]
    add     x0, x24, #LcBootstrap_branch
    str     x0, [sp, #(L + LcParts_branch)]
    mov     x9, x26
    LC_COUNTS
    str     x9, [sp, #(L + LcParts_branch_count)]
    b       30f
10: cmp     x20, #LC_OBJECT_UPDATE
    b.ne    20f
    mov     x0, x19                         /* the period's update */
    mov     x1, #LC_PART_PERIODS
    bl      lc_part
    ldr     x25, [x19, #LcStore_periods]
11: cbz     x25, 93f
    ldr     x9, [x0, #LcPeriod_period]
    cmp     x9, x21
    b.eq    12f
    add     x0, x0, #LcPeriod__mem
    sub     x25, x25, #1
    b       11b
12: ldr     x2, [x0, #LcPeriod_update]
    b       21f
20: ldr     x2, [x19, #LcStore_latest]      /* the latest finality update */
    cbz     x2, 93f
21: mov     x0, x19
    mov     x1, #LC_PART_UPDATES
    bl      lc_ref
    mov     x24, x0
    ldr     x26, [x24, #LcUpdate_fork]
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    ldr     x2, [x24, #LcUpdate_attested_header]
    bl      lc_ref
    add     x0, x0, #LcHeader_header
    str     x0, [sp, #(L + LcParts_header)]
    mov     x0, x19
    mov     x1, #LC_PART_HEADERS
    ldr     x2, [x24, #LcUpdate_finalized_header]
    bl      lc_ref
    add     x0, x0, #LcHeader_header
    str     x0, [sp, #(L + LcParts_finalized_header)]
    str     xzr, [sp, #(L + LcParts_sync_committee)]
    ldr     x2, [x24, #LcUpdate_next_sync_committee]
    cbz     x2, 22f
    mov     x0, x19
    mov     x1, #LC_PART_COMMITTEES
    bl      lc_ref
    add     x0, x0, #LcCommittee_committee
    str     x0, [sp, #(L + LcParts_sync_committee)]
22: add     x0, x24, #LcUpdate_next_branch
    str     x0, [sp, #(L + LcParts_branch)]
    add     x0, x24, #LcUpdate_finality_branch
    str     x0, [sp, #(L + LcParts_finality_branch)]
    add     x0, x24, #LcUpdate_sync_aggregate
    str     x0, [sp, #(L + LcParts_sync_aggregate)]
    ldr     x0, [x24, #LcUpdate_signature_slot]
    str     x0, [sp, #(L + LcParts_signature_slot)]
    mov     x9, x26
    LC_COUNTS
    str     x9, [sp, #(L + LcParts_branch_count)]
    str     x10, [sp, #(L + LcParts_finality_count)]
30: mov     x0, x20
    add     x1, sp, #L
    mov     x2, x22
    mov     x15, x26
    FORK_CALL lc_object
    cbnz    x0, 99f
    str     x26, [x23]
    LEAVE 80
93: mov     x0, #LANTERN_NO_STATE_ANSWER
    LEAVE 80
97: mov     x0, #LANTERN_INVALID_EVENT
99: LEAVE 80
END_FUNCTION lantern_lc_read
