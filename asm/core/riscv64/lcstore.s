# The light client store, RISC-V: in the common object. Requirements: docs/reference/light-client.md.

.set LC_SPP, SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD   # the slots of a sync committee period

# dst = the u64 at addr, which may be unaligned, read a byte at a time. Uses t5, t6.
.macro LCS_LD64 dst, addr
    li      \dst, 0
    li      t5, 7
71: add     t6, \addr, t5
    lbu     t6, 0(t6)
    slli    \dst, \dst, 8
    or      \dst, \dst, t6
    addi    t5, t5, -1
    bgez    t5, 71b
.endm

# t0 += the room field k of the store a0 times mem, for part a1 above k; else to 9f. Uses t1-t3.
.macro LC_PART_STEP k, mem
    li      t1, \k
    bgeu    t1, a1, 9f
    ld      t2, (LcStore_room + 8 * \k)(a0)
    li      t3, \mem
    mul     t2, t2, t3
    add     t0, t0, t2
.endm

# L0: a0 = the first entry or record of part a1 of the store a0. Uses t0-t3.
LOCAL_FUNCTION lantern_lc_part
    UNWIND_END_PROLOGUE
    li      t0, LC_STORE_FIXED
    LC_PART_STEP 0, LcBlock__mem
    LC_PART_STEP 1, LcFinalized__mem
    LC_PART_STEP 2, LcPeriod__mem
    LC_PART_STEP 3, LcBootstrap__mem
    LC_PART_STEP 4, LcHeader__mem
    LC_PART_STEP 5, LcCommittee__mem
9:  add     a0, a0, t0
    ret
END_FUNCTION lantern_lc_part

# L0: t3 = the bytes of an entry or record of part a1.
LOCAL_FUNCTION lantern_lc_mem
    UNWIND_END_PROLOGUE
    li      t3, LcBlock__mem
    beqz    a1, 1f
    li      t3, LcFinalized__mem
    addi    a7, a1, -LC_PART_FINALIZED
    beqz    a7, 1f
    li      t3, LcPeriod__mem
    addi    a7, a1, -LC_PART_PERIODS
    beqz    a7, 1f
    li      t3, LcBootstrap__mem
    addi    a7, a1, -LC_PART_BOOTSTRAPS
    beqz    a7, 1f
    li      t3, LcHeader__mem
    addi    a7, a1, -LC_PART_HEADERS
    beqz    a7, 1f
    li      t3, LcCommittee__mem
    addi    a7, a1, -LC_PART_COMMITTEES
    beqz    a7, 1f
    li      t3, LcUpdate__mem
1:  ret
END_FUNCTION lantern_lc_mem

# L1: a0 = entry or record a2 (an index) of part a1 of the store a0; a1-a5 kept. Uses t0-t4, a7.
LOCAL_FUNCTION lantern_lc_at
    FRAME 0
    call    lantern_lc_part
    call    lantern_lc_mem
    mul     t4, a2, t3
    add     a0, a0, t4
    UNFRAME 0
END_FUNCTION lantern_lc_at

# L1: a0 = record a2 (a reference, not 0) of part a1 of the store a0; a1-a5 kept. Uses t0-t4, a7.
LOCAL_FUNCTION lantern_lc_ref
    FRAME 0
    addi    a2, a2, -1
    call    lantern_lc_at
    addi    a2, a2, 1
    UNFRAME 0
END_FUNCTION lantern_lc_ref

# L1: a0 = the reference of a free record of part a1 of the store a0, now LC_USED; 0 with none. Uses t0-t4, a2-a4, a7.
LOCAL_FUNCTION lantern_lc_alloc
    FRAME 0
    mv      a4, a0
    call    lantern_lc_part
    call    lantern_lc_mem
    slli    t0, a1, 3
    add     t0, t0, a4
    ld      a3, LcStore_room(t0)
    li      a2, 0
1:  bgeu    a2, a3, 8f
    ld      t0, 0(a0)
    beqz    t0, 2f
    add     a0, a0, t3
    addi    a2, a2, 1
    j       1b
2:  li      t0, LC_USED
    sd      t0, 0(a0)
    addi    a0, a2, 1
    UNFRAME 0
8:  li      a0, 0
    UNFRAME 0
END_FUNCTION lantern_lc_alloc

# L1: a0 = the free records of part a1 of the store a0. Uses t0-t4, a2-a4, a7.
LOCAL_FUNCTION lantern_lc_free_count
    FRAME 0
    mv      a4, a0
    call    lantern_lc_part
    call    lantern_lc_mem
    slli    t0, a1, 3
    add     t0, t0, a4
    ld      a3, LcStore_room(t0)
    li      a2, 0
1:  beqz    a3, 2f
    ld      t0, 0(a0)
    seqz    t0, t0
    add     a2, a2, t0
    add     a0, a0, t3
    addi    a3, a3, -1
    j       1b
2:  mv      a0, a2
    UNFRAME 0
END_FUNCTION lantern_lc_free_count

# L1: record a2 (a reference, or 0 for none) of part a1 of the store a0 becomes LC_MARKED. Uses t0-t4, a7.
LOCAL_FUNCTION lantern_lc_mark
    FRAME 0
    beqz    a2, 1f
    call    lantern_lc_ref
    li      t0, LC_MARKED
    sd      t0, 0(a0)
1:  UNFRAME 0
END_FUNCTION lantern_lc_mark

# lantern_lc_mark of part for the field off of the entry s2, with the store s1.
.macro LC_MARK_FIELD part, off
    mv      a0, s1
    li      a1, \part
    ld      a2, \off(s2)
    call    lantern_lc_mark
.endm

# L1: the records of the store a0 that nothing refers to become LC_FREE (LcStore, Rules). s1 the
# store, s2 an entry or record, s3 the ones left, s4 the part, s5 its bytes.
LOCAL_FUNCTION lantern_lc_collect
    ENTER 0
    mv      s1, a0
    li      a1, LC_PART_BLOCKS              # the blocks' header, committees and best update
    call    lantern_lc_part
    mv      s2, a0
    ld      s3, LcStore_blocks(s1)
1:  beqz    s3, 2f
    LC_MARK_FIELD LC_PART_HEADERS, LcBlock_header
    LC_MARK_FIELD LC_PART_COMMITTEES, LcBlock_current_sync_committee
    LC_MARK_FIELD LC_PART_COMMITTEES, LcBlock_next_sync_committee
    LC_MARK_FIELD LC_PART_UPDATES, LcBlock_best
    addi    s2, s2, LcBlock__mem
    addi    s3, s3, -1
    j       1b
2:  mv      a0, s1                          # the bootstraps' header and committee
    li      a1, LC_PART_BOOTSTRAPS
    call    lantern_lc_part
    mv      s2, a0
    ld      s3, LcStore_bootstraps(s1)
3:  beqz    s3, 4f
    LC_MARK_FIELD LC_PART_HEADERS, LcBootstrap_header
    LC_MARK_FIELD LC_PART_COMMITTEES, LcBootstrap_sync_committee
    addi    s2, s2, LcBootstrap__mem
    addi    s3, s3, -1
    j       3b
4:  mv      a0, s1                          # the periods' updates, and latest
    li      a1, LC_PART_PERIODS
    call    lantern_lc_part
    mv      s2, a0
    ld      s3, LcStore_periods(s1)
5:  beqz    s3, 6f
    LC_MARK_FIELD LC_PART_UPDATES, LcPeriod_update
    addi    s2, s2, LcPeriod__mem
    addi    s3, s3, -1
    j       5b
6:  mv      s2, s1
    LC_MARK_FIELD LC_PART_UPDATES, LcStore_latest
    mv      a0, s1                          # each marked update's headers and committee
    li      a1, LC_PART_UPDATES
    call    lantern_lc_part
    mv      s2, a0
    ld      s3, (LcStore_room + LcRoom_updates)(s1)
7:  beqz    s3, 10f
    ld      t0, LcUpdate_state(s2)
    li      t1, LC_MARKED
    bne     t0, t1, 8f
    LC_MARK_FIELD LC_PART_HEADERS, LcUpdate_attested_header
    LC_MARK_FIELD LC_PART_HEADERS, LcUpdate_finalized_header
    LC_MARK_FIELD LC_PART_COMMITTEES, LcUpdate_next_sync_committee
8:  addi    s2, s2, LcUpdate__mem
    addi    s3, s3, -1
    j       7b
10: li      s4, LC_PART_HEADERS             # the sweep: LC_USED goes, LC_MARKED stays
11: mv      a0, s1
    mv      a1, s4
    call    lantern_lc_part
    call    lantern_lc_mem
    mv      s2, a0
    mv      s5, t3
    slli    t0, s4, 3
    add     t0, t0, s1
    ld      s3, LcStore_room(t0)
12: beqz    s3, 14f
    ld      t0, 0(s2)
    addi    t0, t0, -LC_MARKED
    seqz    t0, t0                          # LC_MARKED: LC_USED; else LC_FREE
    sd      t0, 0(s2)
    add     s2, s2, s5
    addi    s3, s3, -1
    j       12b
14: addi    s4, s4, 1
    li      t0, LC_PART_UPDATES
    bgeu    t0, s4, 11b
    LEAVE 0
END_FUNCTION lantern_lc_collect

# L1: a0 = LANTERN_OK when the store a0 has a1 free headers, a2 committees and a3 updates, once the
# records nothing refers to are freed; else LANTERN_BUFFER_TOO_SMALL. s1 the store, s2-s4 the
# needs, s5 1 once collected, s6 the part.
LOCAL_FUNCTION lantern_lc_reserve
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    li      s5, 0
1:  li      s6, LC_PART_HEADERS
2:  mv      a0, s1
    mv      a1, s6
    call    lantern_lc_free_count
    mv      t0, s2
    li      t1, LC_PART_COMMITTEES
    bltu    s6, t1, 21f
    mv      t0, s3
    beq     s6, t1, 21f
    mv      t0, s4
21: bgeu    a0, t0, 3f
    bnez    s5, 9f
    mv      a0, s1
    call    lantern_lc_collect
    li      s5, 1
    j       1b
3:  addi    s6, s6, 1
    li      t0, LC_PART_UPDATES
    bgeu    t0, s6, 2b
    li      a0, LANTERN_OK
    LEAVE 0
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_lc_reserve

# L1: a0 = the index plus 1 of the LcBlock of the root at a1 in the store a0, or 0. Uses t0-t3, a1, a3-a7.
LOCAL_FUNCTION lantern_lc_find_block
    FRAME 0
    ld      a3, LcStore_blocks(a0)
    mv      a4, a1
    li      a1, LC_PART_BLOCKS
    call    lantern_lc_part
    li      a5, 0
1:  bgeu    a5, a3, 3f
    NE32    a0, a4, 2f
    addi    a0, a5, 1
    UNFRAME 0
2:  addi    a0, a0, LcBlock__mem
    addi    a5, a5, 1
    j       1b
3:  li      a0, 0
    UNFRAME 0
END_FUNCTION lantern_lc_find_block

# L1: a0 = the entry (index plus 1) of the highest slot at most a2 along the parents from entry a1
# of the store a0, or 0. Uses t0-t4, a1-a5, a7.
LOCAL_FUNCTION lantern_lc_ancestor
    FRAME 0
    mv      a4, a0
    mv      a5, a2
    mv      a2, a1
    li      a1, LC_PART_BLOCKS
1:  beqz    a2, 3f
    mv      a0, a4
    call    lantern_lc_ref
    ld      t0, LcBlock_slot(a0)
    bgeu    a5, t0, 2f
    ld      a2, LcBlock_parent(a0)
    j       1b
2:  mv      a0, a2
    UNFRAME 0
3:  li      a0, 0
    UNFRAME 0
END_FUNCTION lantern_lc_ancestor

# L1: a0 = the LcFinalized of the highest slot at most a1 and at least historical_tail_slot in the store a0, or 0. Uses t0-t3, a1-a5.
LOCAL_FUNCTION lantern_lc_finalized_at
    FRAME 0
    ld      a3, LcStore_finalized(a0)
    ld      a4, LcStore_historical_tail_slot(a0)
    mv      a5, a1
    li      a1, LC_PART_FINALIZED
    call    lantern_lc_part
    li      t0, LcFinalized__mem
    mul     t0, t0, a3
    add     a0, a0, t0
1:  beqz    a3, 3f
    addi    a0, a0, -LcFinalized__mem
    addi    a3, a3, -1
    ld      t0, LcFinalized_slot(a0)
    bltu    a5, t0, 1b
    bltu    t0, a4, 3f
    UNFRAME 0
3:  li      a0, 0
    UNFRAME 0
END_FUNCTION lantern_lc_finalized_at

# L0: a0 = the set bits of the sync_committee_bits at a0. Uses t0-t3.
LOCAL_FUNCTION lantern_lc_participants
    UNWIND_END_PROLOGUE
    li      t1, SYNC_COMMITTEE_SIZE / 8
    li      t2, 0
1:  lbu     t0, 0(a0)
2:  beqz    t0, 3f
    addi    t3, t0, -1
    and     t0, t0, t3
    addi    t2, t2, 1
    j       2b
3:  addi    a0, a0, 1
    addi    t1, t1, -1
    bnez    t1, 1b
    mv      a0, t2
    ret
END_FUNCTION lantern_lc_participants

# t0 = the roots of a sync committee branch, t1 of a finality branch, of the fork t0.
.macro LC_COUNTS
    sltiu   t1, t0, FORK_ELECTRA
    xori    t1, t1, 1
    addi    t0, t1, 5
    addi    t1, t1, 6
.endm

# L0: a0 = 1 when the a2 bytes at a0 and a1 are equal, a2 a multiple of 8, both 8-aligned; else 0. Uses t0, t1.
LOCAL_FUNCTION lantern_lc_equal
    UNWIND_END_PROLOGUE
1:  beqz    a2, 2f
    ld      t0, 0(a0)
    ld      t1, 0(a1)
    addi    a0, a0, 8
    addi    a1, a1, 8
    addi    a2, a2, -8
    beq     t0, t1, 1b
    li      a0, 0
    ret
2:  li      a0, 1
    ret
END_FUNCTION lantern_lc_equal

# L1: a0 = an LcCommittee reference of the sync committee bytes a1 in the store a0: a2 or a3 (each
# a reference or 0) when its bytes are equal, else a new record. s1 the store, s2 the bytes, s3
# and s4 the candidates, s5 the reference. The bytes are 8-aligned, as in a state's value.
LOCAL_FUNCTION lantern_lc_committee
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, s3
1:  beqz    s5, 2f
    mv      a0, s1
    li      a1, LC_PART_COMMITTEES
    mv      a2, s5
    call    lantern_lc_ref
    addi    a0, a0, LcCommittee_committee
    mv      a1, s2
    li      a2, LC_COMMITTEE
    call    lantern_lc_equal
    bnez    a0, 4f
2:  beq     s5, s4, 3f
    mv      s5, s4
    j       1b
3:  mv      a0, s1
    li      a1, LC_PART_COMMITTEES
    call    lantern_lc_alloc
    mv      s5, a0
    mv      a0, s1
    li      a1, LC_PART_COMMITTEES
    mv      a2, s5
    call    lantern_lc_ref
    addi    a0, a0, LcCommittee_committee
    mv      a1, s2
    li      a2, LC_COMMITTEE
    call    lantern_copy
4:  mv      a0, s5
    LEAVE 0
END_FUNCTION lantern_lc_committee

# L1: hash_tree_root of the BeaconBlockHeader at a0 (its 112 SSZ bytes, 8-aligned) at a1. s1 the
# header, s2 out, s3 the 8 chunks, s4 the pairs of the level, s5 the pair. Locals: L a ByteList,
# L + 32 a digest, L + 64 the chunks.
LOCAL_FUNCTION lantern_lc_beacon_root
    ENTER 320
    mv      s1, a0
    mv      s2, a1
    addi    s3, sp, (L + 64)
    mv      a0, s3
    li      a1, 256
    call    lantern_zero
    ld      t0, 0(s1)                       # slot, proposer_index, then the three roots
    sd      t0, 0(s3)
    ld      t0, 8(s1)
    sd      t0, 32(s3)
    addi    a0, s3, 64
    addi    a1, s1, 16
    li      a2, 96
    call    lantern_copy
    li      s4, 4
1:  li      s5, 0
2:  slli    t0, s5, 6
    addi    t0, t0, 64                      # the pair's offset from the ByteList at L
    addi    t1, t0, 64
    sd      t1, L(sp)
    sd      t0, (L + 8)(sp)
    li      t1, 64
    sd      t1, (L + 16)(sp)
    addi    a0, sp, L
    addi    a1, sp, (L + 32)
    CALL_GLOBAL crypto_sha256
    slli    t0, s5, 5
    add     t0, t0, s3
    addi    t1, sp, (L + 32)
    COPY32  t0, t1
    addi    s5, s5, 1
    bltu    s5, s4, 2b
    srli    s4, s4, 1
    bnez    s4, 1b
    COPY32  s2, s3
    LEAVE 320
END_FUNCTION lantern_lc_beacon_root

# L1: a0 = a new LcHeader of the fork a1 in the store a0 (reserved before), the empty header of the
# fork: lantern_upgrade_lc_header of 112 zero bytes from altair. s1 the store, s2 the fork, s3 the
# reference. Locals: L the ByteList of the zero bytes.
LOCAL_FUNCTION lantern_lc_empty_header
    ENTER 144
    mv      s1, a0
    mv      s2, a1
    addi    a0, sp, L
    li      a1, 144
    call    lantern_zero
    li      t0, 136
    sd      t0, L(sp)
    li      t0, 24
    sd      t0, (L + 8)(sp)
    li      t0, 112
    sd      t0, (L + 16)(sp)
    mv      a0, s1
    li      a1, LC_PART_HEADERS
    call    lantern_lc_alloc
    mv      s3, a0
    mv      a0, s1
    li      a1, LC_PART_HEADERS
    mv      a2, s3
    call    lantern_lc_ref
    sd      s2, LcHeader_fork(a0)
    li      t0, 24 + LC_HEADER_ROOM
    sd      t0, LcHeader_header(a0)
    addi    a2, a0, LcHeader_header
    addi    a0, sp, L
    li      a1, FORK_ALTAIR
    mv      t6, s2
    FORK_CALL upgrade_lc_header
    mv      a0, s3
    LEAVE 144
END_FUNCTION lantern_lc_empty_header

# L1: a0 = a new LcUpdate (reserved before, with one LcHeader) in the store a0: the update of entry
# a1 (light-client.md, The update of an entry) with the signature slot a2, the sync aggregate at a3
# and the LcCommittee a4 (0: a finality update). s1 the store, s2 the entry's reference, s3 the
# signature slot, s4 the aggregate, s5 the committee, s6 the entry, s7 the update's reference, s8
# the update, s9 its fork, s10 a finalized entry or header.
LOCAL_FUNCTION lantern_lc_make_update
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    li      a1, LC_PART_BLOCKS
    mv      a2, s2
    call    lantern_lc_ref
    mv      s6, a0
    mv      a0, s1
    li      a1, LC_PART_UPDATES
    call    lantern_lc_alloc
    mv      s7, a0
    mv      a0, s1
    li      a1, LC_PART_UPDATES
    mv      a2, s7
    call    lantern_lc_ref
    mv      s8, a0
    mv      a0, s1
    li      a1, LC_PART_HEADERS
    ld      a2, LcBlock_header(s6)
    call    lantern_lc_ref
    ld      s9, LcHeader_fork(a0)
    sd      s9, LcUpdate_fork(s8)
    ld      t0, LcBlock_header(s6)
    sd      t0, LcUpdate_attested_header(s8)
    sd      s5, LcUpdate_next_sync_committee(s8)
    sd      s3, LcUpdate_signature_slot(s8)
    addi    a0, s8, LcUpdate_next_branch
    addi    a1, s6, LcBlock_next_branch
    li      a2, 192
    call    lantern_copy
    addi    a0, s8, LcUpdate_sync_aggregate
    mv      a1, s4
    li      a2, LC_AGGREGATE
    call    lantern_copy
    mv      a0, s1                          # the finalized block: the LcFinalized at the entry's finalized_slot
    ld      a1, LcBlock_finalized_slot(s6)
    call    lantern_lc_finalized_at
    beqz    a0, 5f
    mv      s10, a0
    ld      t0, LcFinalized_slot(s10)
    sd      t0, LcBlock_finalized_slot(s6)
    beqz    t0, 4f                          # GENESIS_SLOT: the empty header, the branch
    mv      a0, s1
    addi    a1, s10, LcFinalized_root
    call    lantern_lc_find_block
    beqz    a0, 5f
    mv      a2, a0
    mv      a0, s1
    li      a1, LC_PART_BLOCKS
    call    lantern_lc_ref
    ld      a2, LcBlock_header(a0)
    sd      a2, LcUpdate_finalized_header(s8)
    mv      a0, s1
    li      a1, LC_PART_HEADERS
    call    lantern_lc_ref
    mv      s10, a0
    ld      t0, LcHeader_fork(s10)
    beq     t0, s9, 3f
    mv      a0, s1                          # of an earlier fork: upgraded, in a new record
    li      a1, LC_PART_HEADERS
    call    lantern_lc_alloc
    sd      a0, LcUpdate_finalized_header(s8)
    mv      a2, a0
    mv      a0, s1
    li      a1, LC_PART_HEADERS
    call    lantern_lc_ref
    sd      s9, LcHeader_fork(a0)
    li      t0, 24 + LC_HEADER_ROOM
    sd      t0, LcHeader_header(a0)
    addi    a2, a0, LcHeader_header
    addi    a0, s10, LcHeader_header
    ld      a1, LcHeader_fork(s10)
    mv      t6, s9
    FORK_CALL upgrade_lc_header
3:  addi    a0, s8, LcUpdate_finality_branch
    addi    a1, s6, LcBlock_finality_branch
    li      a2, 224
    call    lantern_copy
    j       7f
4:  addi    a0, s8, LcUpdate_finality_branch
    addi    a1, s6, LcBlock_finality_branch
    li      a2, 224
    call    lantern_copy
    j       6f
5:  addi    a0, s8, LcUpdate_finality_branch  # no finalized block: the empty header, a zero branch
    li      a1, 224
    call    lantern_zero
6:  mv      a0, s1
    mv      a1, s9
    call    lantern_lc_empty_header
    sd      a0, LcUpdate_finalized_header(s8)
7:  mv      a0, s7
    LEAVE 0
END_FUNCTION lantern_lc_make_update

# L1, lantern_lc_better's: the LcParts a2 of the LcUpdate a1 of the fork a3 in the store a0, the branches at
# their counts. s1 the store, s2 the update, s3 the parts, s4 the fork.
LOCAL_FUNCTION lantern_lc_better_parts
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    li      a1, LC_PART_HEADERS
    ld      a2, LcUpdate_attested_header(s2)
    call    lantern_lc_ref
    addi    a0, a0, LcHeader_header
    sd      a0, LcParts_header(s3)
    mv      a0, s1
    li      a1, LC_PART_HEADERS
    ld      a2, LcUpdate_finalized_header(s2)
    call    lantern_lc_ref
    addi    a0, a0, LcHeader_header
    sd      a0, LcParts_finalized_header(s3)
    mv      a0, s1
    li      a1, LC_PART_COMMITTEES
    ld      a2, LcUpdate_next_sync_committee(s2)
    call    lantern_lc_ref
    addi    a0, a0, LcCommittee_committee
    sd      a0, LcParts_sync_committee(s3)
    addi    t0, s2, LcUpdate_next_branch
    sd      t0, LcParts_branch(s3)
    addi    t0, s2, LcUpdate_finality_branch
    sd      t0, LcParts_finality_branch(s3)
    addi    t0, s2, LcUpdate_sync_aggregate
    sd      t0, LcParts_sync_aggregate(s3)
    ld      t0, LcUpdate_signature_slot(s2)
    sd      t0, LcParts_signature_slot(s3)
    mv      t0, s4
    LC_COUNTS
    sd      t0, LcParts_branch_count(s3)
    sd      t1, LcParts_finality_count(s3)
    LEAVE 0
END_FUNCTION lantern_lc_better_parts

# L1: a0 = 1 when lantern_is_better_update of the LcUpdate a1's fork gives 1 for it and the
# LcUpdate a2 upgraded to that fork, in the store a0 with the scratch a3 (LC_COMPARE_SCRATCH bytes,
# checked before); else 0. s1 the store, s2 the new update, s3 the old one's reference, s4 the
# scratch's buffers, s5 the new update's fork, s6 the old one's fork, s7 the old update. Locals: L
# the parts, L + 72 the answer.
LOCAL_FUNCTION lantern_lc_better
    ENTER 80
    mv      s1, a0
    mv      s3, a2
    addi    s4, a3, 8
    mv      a2, a1
    li      a1, LC_PART_UPDATES
    call    lantern_lc_ref
    mv      s2, a0
    ld      s5, LcUpdate_fork(s2)
    mv      a0, s1                          # the new update: buffer 1
    mv      a1, s2
    addi    a2, sp, L
    mv      a3, s5
    call    lantern_lc_better_parts
    li      t0, 24 + LC_UPDATE_ROOM
    sd      t0, 0(s4)
    li      a0, LC_OBJECT_UPDATE
    addi    a1, sp, L
    mv      a2, s4
    mv      t6, s5
    FORK_CALL lc_object
    bnez    a0, 9f
    mv      a0, s1                          # the old one, its headers upgraded: buffer 2
    li      a1, LC_PART_UPDATES
    mv      a2, s3
    call    lantern_lc_ref
    mv      s7, a0
    ld      s6, LcUpdate_fork(s7)
    mv      a0, s1
    mv      a1, s7
    addi    a2, sp, L
    mv      a3, s6
    call    lantern_lc_better_parts
    beq     s5, s6, 1f
    li      t0, 2 * (24 + LC_UPDATE_ROOM)   # the headers' buffers, after the two updates'
    add     a2, s4, t0
    li      t0, 24 + LC_HEADER_ROOM
    sd      t0, 0(a2)
    ld      a0, (L + LcParts_header)(sp)
    sd      a2, (L + LcParts_header)(sp)
    mv      a1, s6
    mv      t6, s5
    FORK_CALL upgrade_lc_header
    bnez    a0, 9f
    li      t0, 2 * (24 + LC_UPDATE_ROOM) + 24 + LC_HEADER_ROOM
    add     a2, s4, t0
    li      t0, 24 + LC_HEADER_ROOM
    sd      t0, 0(a2)
    ld      a0, (L + LcParts_finalized_header)(sp)
    sd      a2, (L + LcParts_finalized_header)(sp)
    mv      a1, s6
    mv      t6, s5
    FORK_CALL upgrade_lc_header
    bnez    a0, 9f
1:  li      t0, 24 + LC_UPDATE_ROOM
    add     a2, s4, t0
    sd      t0, 0(a2)
    li      a0, LC_OBJECT_UPDATE
    addi    a1, sp, L
    mv      t6, s5
    FORK_CALL lc_object
    bnez    a0, 9f
    mv      a0, s4
    li      t0, 24 + LC_UPDATE_ROOM
    add     a1, s4, t0
    addi    a2, sp, (L + 72)
    mv      t6, s5
    FORK_CALL is_better_update
    bnez    a0, 9f
    ld      a0, (L + 72)(sp)
    LEAVE 80
9:  li      a0, 0
    LEAVE 80
END_FUNCTION lantern_lc_better

# L1: a0 = status: the LcBlock of the block a3 (ByteList) with its post-state a2 in the store a0,
# the config a1, the StateCache a4 (or 0), the scratch a5; with a6 1 the anchor of
# lantern_lc_store_init, else lantern_lc_on_block. s1 the store, s2 config, s3 state, s4 block, s5
# cache, s6 scratch, s7 the new entry, s8 the block's fork, s9 the header's reference, s10 the
# parent entry. Locals: L the anchor flag, L + 8 the slot, L + 16 the header's bytes, L + 24 the
# root, L + 56 the parent's reference, L + 64 the update, L + 72 the header.
LOCAL_FUNCTION lantern_lc_add_block
    ENTER 80
    sd      a6, L(sp)
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    mv      a0, s1                          # the room first
    li      a1, 2
    li      a2, 2
    li      a3, 1
    call    lantern_lc_reserve
    bnez    a0, 98f
    ld      t0, LcStore_blocks(s1)
    ld      t1, (LcStore_room + LcRoom_blocks)(s1)
    bgeu    t0, t1, 98f
    ld      t0, 0(s6)
    li      t1, LC_COMPARE_SCRATCH
    bltu    t0, t1, 98f
    ld      a0, NODE_STATE_SLOT(s3)         # the anchor: the fork of the state's slot
    ld      t0, L(sp)
    bnez    t0, 5f
    ld      t0, 8(s4)                       # else the block's slot, for its fork
    add     t0, s4, t0
    ld      t1, 16(s4)
    li      t2, 4
    bltu    t1, t2, 96f
    lwu     t2, 0(t0)
    addi    t3, t2, 8
    bltu    t1, t3, 96f
    add     t0, t0, t2
    LCS_LD64 a0, t0
5:  mv      a1, s2
    call    lantern_node_fork
    mv      s8, a0
    mv      a0, s1                          # the header
    li      a1, LC_PART_HEADERS
    call    lantern_lc_alloc
    mv      s9, a0
    mv      a2, a0
    mv      a0, s1
    li      a1, LC_PART_HEADERS
    call    lantern_lc_ref
    sd      a0, (L + 72)(sp)
    mv      t0, s8
    li      t1, FORK_ALTAIR
    bgeu    t0, t1, 1f
    mv      t0, t1
1:  sd      t0, LcHeader_fork(a0)
    li      t0, 24 + LC_HEADER_ROOM
    sd      t0, LcHeader_header(a0)
    addi    a2, a0, LcHeader_header
    mv      a0, s4
    mv      a1, s6
    mv      t6, s8
    ld      t0, L(sp)
    bnez    t0, 6f
    FORK_CALL block_to_light_client_header
    j       7f
6:  FORK_CALL lc_anchor_header              # the anchor: of its block's value
7:  bnez    a0, 90f
    ld      t0, (L + 72)(sp)                # the root: of the header's beacon; the slot its slot
    addi    t0, t0, LcHeader_header
    ld      t1, 8(t0)
    add     a0, t0, t1
    sd      a0, (L + 16)(sp)
    ld      t1, 0(a0)
    sd      t1, (L + 8)(sp)
    addi    a1, sp, (L + 24)
    call    lantern_lc_beacon_root
    mv      a0, s1
    addi    a1, sp, (L + 24)
    call    lantern_lc_find_block
    bnez    a0, 95f
    mv      a0, s1                          # the entry, at the end of blocks
    li      a1, LC_PART_BLOCKS
    ld      a2, LcStore_blocks(s1)
    call    lantern_lc_at
    mv      s7, a0
    li      a1, LcBlock__mem
    call    lantern_zero
    addi    t0, sp, (L + 24)
    COPY32  s7, t0
    ld      t0, (L + 16)(sp)
    addi    t0, t0, 16
    addi    t1, s7, LcBlock_parent_root
    COPY32  t1, t0
    ld      t0, (L + 8)(sp)
    sd      t0, LcBlock_slot(s7)
    sd      s9, LcBlock_header(s7)
    mv      a0, s1
    addi    a1, s7, LcBlock_parent_root
    call    lantern_lc_find_block
    sd      a0, LcBlock_parent(s7)
    sd      a0, (L + 56)(sp)
    ld      t0, L(sp)                       # from altair, but the anchor: the body's sync_aggregate
    bnez    t0, 10f
    li      t0, FORK_ALTAIR
    bltu    s8, t0, 10f
    ld      t0, 8(s4)
    add     t0, s4, t0
    lwu     t1, 0(t0)
    add     t0, t0, t1
    lwu     t1, 80(t0)
    add     a1, t0, t1
    addi    a1, a1, 220
    addi    a0, s7, LcBlock_sync_aggregate
    li      a2, LC_AGGREGATE
    call    lantern_copy
10: ld      t0, L(sp)
    beqz    t0, 11f
    li      t0, FORK_ALTAIR                 # the anchor: data from altair
    bltu    s8, t0, 50f
    j       20f
11: ld      t0, (L + 8)(sp)
    ld      t1, LcStore_tail_slot(s1)
    bltu    t0, t1, 50f
    ld      t0, (L + 56)(sp)
    beqz    t0, 94f
20: li      t0, 1                           # the data: branches, finalized_slot, committees
    sd      t0, LcBlock_data(s7)
    li      s10, 0
21: mv      a0, s3
    mv      a1, s10
    mv      a2, s5
    mv      a3, s6
    li      t0, 192
    mul     t0, t0, s10
    add     a4, s7, t0
    addi    a4, a4, LcBlock_current_branch
    mv      t6, s8
    FORK_CALL state_branch
    bnez    a0, 90f
    addi    s10, s10, 1
    li      t0, LC_BRANCH_FINALIZED_ROOT
    bgeu    t0, s10, 21b
    LDQ     t0, s3, NODE_STATE_FINALIZED
    li      t1, SLOTS_PER_EPOCH
    mul     t0, t0, t1
    sd      t0, LcBlock_finalized_slot(s7)
    li      a2, 0                           # the parent's committees, as candidates
    li      a3, 0
    ld      s10, (L + 56)(sp)
    beqz    s10, 22f
    mv      a0, s1
    li      a1, LC_PART_BLOCKS
    mv      a2, s10
    call    lantern_lc_ref
    mv      s10, a0
    ld      a2, LcBlock_current_sync_committee(s10)
    ld      a3, LcBlock_next_sync_committee(s10)
22: mv      a0, s1
    ADDQ    a1, s3, NODE_STATE_CURRENT_SYNC_COMMITTEE
    call    lantern_lc_committee
    sd      a0, LcBlock_current_sync_committee(s7)
    li      a2, 0
    beqz    s10, 23f
    ld      a2, LcBlock_next_sync_committee(s10)
23: ld      a3, LcBlock_current_sync_committee(s7)
    mv      a0, s1
    ADDQ    a1, s3, NODE_STATE_NEXT_SYNC_COMMITTEE
    call    lantern_lc_committee
    sd      a0, LcBlock_next_sync_committee(s7)
    ld      t0, L(sp)
    bnez    t0, 50f                         # the anchor: no best update, latest_signature_slot GENESIS_SLOT
    ld      t0, LcBlock_slot(s10)           # the attested block: the parent, s10
    ld      t1, LcStore_tail_slot(s1)
    bltu    t0, t1, 50f
    li      t1, LC_SPP
    divu    t2, t0, t1                      # t2 its period, t3 the block's
    ld      t3, (L + 8)(sp)
    divu    t3, t3, t1
    li      t4, 0
    bne     t2, t3, 24f
    ld      t4, LcBlock_best(s10)
24: sd      t4, LcBlock_best(s7)
    sub     t0, t2, t3
    snez    t0, t0
    sd      t0, (L + 64)(sp)                # 1 when the periods differ
    addi    a0, s7, LcBlock_sync_aggregate
    call    lantern_lc_participants
    ld      t0, (L + 8)(sp)
    li      t1, MIN_SYNC_COMMITTEE_PARTICIPANTS
    bgeu    a0, t1, 25f
    ld      t0, LcBlock_latest_signature_slot(s10)
25: sd      t0, LcBlock_latest_signature_slot(s7)
    bltu    a0, t1, 50f
    ld      t0, (L + 64)(sp)
    bnez    t0, 50f
    mv      a0, s1                          # the update; it becomes best when better
    ld      a1, (L + 56)(sp)
    ld      a2, (L + 8)(sp)
    addi    a3, s7, LcBlock_sync_aggregate
    ld      a4, LcBlock_next_sync_committee(s7)
    call    lantern_lc_make_update
    sd      a0, (L + 64)(sp)
    ld      a2, LcBlock_best(s7)
    beqz    a2, 40f
    mv      a1, a0
    mv      a0, s1
    mv      a3, s6
    call    lantern_lc_better
    beqz    a0, 50f
40: ld      t0, (L + 64)(sp)
    sd      t0, LcBlock_best(s7)
50: ld      t0, LcStore_blocks(s1)
    addi    t0, t0, 1
    sd      t0, LcStore_blocks(s1)
    li      a0, LANTERN_OK
    LEAVE 80
90: ld      t0, (L + 72)(sp)                # a status: the header's record is free again
    sd      zero, 0(t0)
    LEAVE 80
94: ld      t0, (L + 72)(sp)
    sd      zero, 0(t0)
    li      a0, LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 80
95: ld      t0, (L + 72)(sp)
    sd      zero, 0(t0)
    li      a0, LANTERN_INVALID_EVENT
    LEAVE 80
96: li      a0, LANTERN_INVALID_ENCODING
    LEAVE 80
98: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
END_FUNCTION lantern_lc_add_block

# L1: an LcBootstrap of the LcFinalized a1 in the store a0 (room checked before), when the store
# holds none of its root and holds its LcBlock with data. s1 the store, s2 the LcFinalized, s3 the
# bootstraps, s4 their count, s5 the index, s6 the entry.
LOCAL_FUNCTION lantern_lc_add_bootstrap
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    li      a1, LC_PART_BOOTSTRAPS
    call    lantern_lc_part
    mv      s3, a0
    ld      s4, LcStore_bootstraps(s1)
    li      s5, 0
    addi    t2, s2, LcFinalized_root
1:  bgeu    s5, s4, 2f
    li      t0, LcBootstrap__mem
    mul     t0, t0, s5
    add     t0, t0, s3
    NE32    t0, t2, 3f
    LEAVE 0
3:  addi    s5, s5, 1
    j       1b
2:  mv      a0, s1
    addi    a1, s2, LcFinalized_root
    call    lantern_lc_find_block
    beqz    a0, 9f
    mv      a2, a0
    mv      a0, s1
    li      a1, LC_PART_BLOCKS
    call    lantern_lc_ref
    mv      s6, a0
    ld      t0, LcBlock_data(s6)
    beqz    t0, 9f
    li      t0, LcBootstrap__mem
    mul     t0, t0, s4
    add     a0, t0, s3
    addi    t1, s2, LcFinalized_root
    COPY32  a0, t1
    ld      t0, LcFinalized_slot(s2)
    sd      t0, LcBootstrap_slot(a0)
    ld      t0, LcBlock_header(s6)
    sd      t0, LcBootstrap_header(a0)
    ld      t0, LcBlock_current_sync_committee(s6)
    sd      t0, LcBootstrap_sync_committee(a0)
    addi    a0, a0, LcBootstrap_branch
    addi    a1, s6, LcBlock_current_branch
    li      a2, 192
    call    lantern_copy
    addi    s4, s4, 1
    sd      s4, LcStore_bootstraps(s1)
9:  LEAVE 0
END_FUNCTION lantern_lc_add_bootstrap

# L1: the LcPeriod of period a1 in the store a0 refers to update a2 (room checked before); with a2
# 0, the period has none. s1 the store, s2 the period, s3 the update, s4 the periods, s5 their
# count, s6 the index.
LOCAL_FUNCTION lantern_lc_set_period
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    li      a1, LC_PART_PERIODS
    call    lantern_lc_part
    mv      s4, a0
    ld      s5, LcStore_periods(s1)
    li      s6, 0
1:  bgeu    s6, s5, 2f                      # the first entry of a period at least s2
    slli    t0, s6, 4
    add     t0, t0, s4
    ld      t0, 0(t0)
    bgeu    t0, s2, 2f
    addi    s6, s6, 1
    j       1b
2:  slli    t2, s6, 4
    add     t2, t2, s4
    bgeu    s6, s5, 4f
    ld      t0, LcPeriod_period(t2)
    bne     t0, s2, 4f
    beqz    s3, 3f
    sd      s3, LcPeriod_update(t2)         # the period's entry: the new update
    LEAVE 0
3:  addi    s5, s5, -1                      # none: its entry goes
    sd      s5, LcStore_periods(s1)
    mv      a0, t2
    addi    a1, t2, LcPeriod__mem
    sub     a2, s5, s6
    slli    a2, a2, 4
    call    lantern_copy
    LEAVE 0
4:  beqz    s3, 9f                          # a new entry at s6: the later ones up by one
    mv      t0, s5
5:  bgeu    s6, t0, 6f
    slli    t1, t0, 4
    add     t1, t1, s4
    ld      t3, -16(t1)
    ld      t4, -8(t1)
    sd      t3, 0(t1)
    sd      t4, 8(t1)
    addi    t0, t0, -1
    j       5b
6:  sd      s2, LcPeriod_period(t2)
    sd      s3, LcPeriod_update(t2)
    addi    s5, s5, 1
    sd      s5, LcStore_periods(s1)
9:  LEAVE 0
END_FUNCTION lantern_lc_set_period

# L1: the LcBlock entries of slots below a1 in the store a0 go, with the scratch a2 (8 bytes for
# each entry, checked before) for their new indices. s1 the store, s2 the slot, s3 the indices, s4
# the entries, s5 their count, s6 the index, s7 the kept ones.
LOCAL_FUNCTION lantern_lc_prune
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    addi    s3, a2, 8
    li      a1, LC_PART_BLOCKS
    call    lantern_lc_part
    mv      s4, a0
    ld      s5, LcStore_blocks(s1)
    li      s6, 0
    li      s7, 0
1:  bgeu    s6, s5, 3f                      # each entry's new index plus 1, or 0; its parent's
    li      t0, LcBlock__mem
    mul     t0, t0, s6
    add     t0, t0, s4
    ld      t1, LcBlock_slot(t0)
    li      t2, 0
    bltu    t1, s2, 2f
    addi    s7, s7, 1
    mv      t2, s7
    ld      t3, LcBlock_parent(t0)
    beqz    t3, 2f
    slli    t3, t3, 3
    add     t3, t3, s3
    ld      t3, -8(t3)
    sd      t3, LcBlock_parent(t0)
2:  slli    t3, s6, 3
    add     t3, t3, s3
    sd      t2, 0(t3)
    addi    s6, s6, 1
    j       1b
3:  li      s6, 0                           # the kept ones down to their new places
4:  bgeu    s6, s5, 6f
    slli    t0, s6, 3
    add     t0, t0, s3
    ld      t0, 0(t0)
    addi    t0, t0, -1
    bgeu    t0, s6, 5f                      # gone (0 - 1), or in place
    li      t1, LcBlock__mem
    mul     a0, t0, t1
    add     a0, a0, s4
    mul     a1, s6, t1
    add     a1, a1, s4
    mv      a2, t1
    call    lantern_copy
5:  addi    s6, s6, 1
    j       4b
6:  sd      s7, LcStore_blocks(s1)
    LEAVE 0
END_FUNCTION lantern_lc_prune

# (room, size) -> status: LC_STORE_FIXED plus each capacity times its bytes (light-client.md).
FUNCTION lantern_lc_store_size
    FRAME 0
    mv      a4, a0
    mv      a5, a1
    li      a2, LC_STORE_FIXED
    li      a1, 0
1:  slli    t0, a1, 3
    add     t0, t0, a4
    ld      t4, 0(t0)
    call    lantern_lc_mem
    mulhu   t0, t4, t3
    bnez    t0, 9f
    mul     t4, t4, t3
    add     t0, a2, t4
    bltu    t0, a2, 9f
    mv      a2, t0
    addi    a1, a1, 1
    li      t0, LC_PART_UPDATES
    bgeu    t0, a1, 1b
    sd      a2, 0(a5)
    li      a0, LANTERN_OK
    UNFRAME 0
9:  li      a0, LANTERN_INVALID_OVERFLOW
    UNFRAME 0
END_FUNCTION lantern_lc_store_size

# reg = reg times SLOTS_PER_EPOCH, 2^64 - 1 when it overflows. Uses t1, t2.
.macro LC_EPOCH_SLOT reg
    li      t1, SLOTS_PER_EPOCH
    mulhu   t2, \reg, t1
    mul     \reg, \reg, t1
    snez    t2, t2
    neg     t2, t2
    or      \reg, \reg, t2
.endm

# (room, config, state, block, scratch, lc) -> status: an LcStore at an anchor (light-client.md).
# s1 room, s2 config, s3 state, s4 block, s5 scratch, s6 lc, s7 the anchor's entry, s8 its
# LcFinalized. Locals: L the size.
FUNCTION lantern_lc_store_init
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    addi    a1, sp, L
    call    lantern_lc_store_size
    bnez    a0, 99f
    ld      t0, L(sp)
    ld      t1, 0(s6)
    bltu    t1, t0, 98f
    li      t0, 0                           # 2 of each at least
1:  slli    t1, t0, 3
    add     t1, t1, s1
    ld      t1, 0(t1)
    li      t2, 2
    bltu    t1, t2, 98f
    addi    t0, t0, 1
    li      t1, LC_PART_UPDATES
    bgeu    t1, t0, 1b
    addi    a0, s6, 8                       # every field 0, every record LC_FREE
    ld      a1, L(sp)
    addi    a1, a1, -8
    call    lantern_zero
    addi    a0, s6, LcStore_room
    mv      a1, s1
    li      a2, LcRoom__mem
    call    lantern_copy
    ld      t3, NODE_STATE_SLOT(s3)
    sd      t3, LcStore_historical_tail_slot(s6)
    ld      t0, CONFIG_ALTAIR_FORK_EPOCH(s2)
    LC_EPOCH_SLOT t0
    bgeu    t0, t3, 2f
    mv      t0, t3
2:  sd      t0, LcStore_tail_slot(s6)
    LDQ     t0, s3, NODE_STATE_FINALIZED
    sd      t0, LcStore_latest_finalized_epoch(s6)
    LC_EPOCH_SLOT t0
    sd      t0, LcStore_latest_finalized_slot(s6)
    addi    t0, s6, LcStore_latest_finalized_root
    ADDQ    t1, s3, NODE_STATE_FINALIZED + 8
    COPY32  t0, t1
    mv      a0, s6                          # the anchor's entry, its LcFinalized and bootstrap
    mv      a1, s2
    mv      a2, s3
    mv      a3, s4
    li      a4, 0
    mv      a5, s5
    li      a6, 1
    call    lantern_lc_add_block
    bnez    a0, 99f
    mv      a0, s6
    li      a1, LC_PART_BLOCKS
    li      a2, 0
    call    lantern_lc_at
    mv      s7, a0
    mv      a0, s6
    li      a1, LC_PART_FINALIZED
    call    lantern_lc_part
    mv      s8, a0
    ld      t0, LcBlock_slot(s7)
    sd      t0, LcFinalized_slot(s8)
    addi    t0, s8, LcFinalized_root
    COPY32  t0, s7
    li      t0, 1
    sd      t0, LcStore_finalized(s6)
    mv      a0, s6
    mv      a1, s8
    call    lantern_lc_add_bootstrap
    li      a0, LANTERN_OK
    LEAVE 16
98: li      a0, LANTERN_BUFFER_TOO_SMALL
99: LEAVE 16
END_FUNCTION lantern_lc_store_init

# (lc, room, out) -> status: the store in a new buffer (light-client.md). s1 lc, s2 room, s3 out,
# s4 the part, s5 its source, s6 its target, s7 an entry's bytes, s8 the old records' bytes.
# Locals: L the size.
FUNCTION lantern_lc_store_copy
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      a0, s2
    addi    a1, sp, L
    call    lantern_lc_store_size
    bnez    a0, 99f
    ld      t0, L(sp)
    ld      t1, 0(s3)
    bltu    t1, t0, 98f
    li      s4, 0
1:  slli    t0, s4, 3
    add     t1, t0, s2
    ld      t1, 0(t1)
    add     t2, t0, s1
    ld      t2, LcStore_room(t2)
    bltu    t1, t2, 98f
    addi    s4, s4, 1
    li      t0, LC_PART_UPDATES
    bgeu    t0, s4, 1b
    addi    a0, s3, 8                       # the fixed fields, then the new room
    addi    a1, s1, 8
    li      a2, LC_STORE_FIXED - 8
    call    lantern_copy
    addi    a0, s3, LcStore_room
    mv      a1, s2
    li      a2, LcRoom__mem
    call    lantern_copy
    li      s4, 0
2:  mv      a0, s1
    mv      a1, s4
    call    lantern_lc_part
    mv      s5, a0
    mv      a0, s3
    call    lantern_lc_part
    mv      s6, a0
    call    lantern_lc_mem
    mv      s7, t3
    li      t0, LC_PART_BOOTSTRAPS
    bltu    t0, s4, 3f
    slli    t0, s4, 3                       # an entry part: its entries
    add     t0, t0, s1
    ld      a2, LcStore_blocks(t0)
    mul     a2, a2, s7
    mv      a0, s6
    mv      a1, s5
    call    lantern_copy
    j       4f
3:  slli    t0, s4, 3                       # a record part: its records, the new ones LC_FREE
    add     t0, t0, s1
    ld      s8, LcStore_room(t0)
    mul     s8, s8, s7
    mv      a0, s6
    mv      a1, s5
    mv      a2, s8
    call    lantern_copy
    slli    t0, s4, 3
    add     t0, t0, s2
    ld      a1, 0(t0)
    mul     a1, a1, s7
    sub     a1, a1, s8
    add     a0, s6, s8
    call    lantern_zero
4:  addi    s4, s4, 1
    li      t0, LC_PART_UPDATES
    bgeu    t0, s4, 2b
    li      a0, LANTERN_OK
    LEAVE 16
98: li      a0, LANTERN_BUFFER_TOO_SMALL
99: LEAVE 16
END_FUNCTION lantern_lc_store_copy

# (lc, config, state, block, cache, scratch) -> status: lantern_lc_on_block (light-client.md).
FUNCTION lantern_lc_on_block
    FRAME 0
    li      a6, 0
    call    lantern_lc_add_block
    UNFRAME 0
END_FUNCTION lantern_lc_on_block

# (lc, config, head, checkpoint, scratch) -> status: lantern_lc_on_head (light-client.md). s1 lc,
# s2 config, s3 head, s4 checkpoint, s5 scratch, s6 the head's entry (a reference), s7 the
# checkpoint's entry when it is new, else 0, s8 an entry, s9 and s10 a period, an entry or an
# index. Locals: L low_slot, L + 8 the new LcFinalized, L + 16 the boundary slot, L + 24 the low
# slot of the bootstraps, L + 32 the slot the new LcFinalized are above, L + 40 an entry, L + 48
# an update or a slot.
FUNCTION lantern_lc_on_head
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      a1, s3
    call    lantern_lc_find_block
    beqz    a0, 94f
    mv      s6, a0
    li      s7, 0
    ld      t0, 0(s4)
    beqz    t0, 1f
    mv      a0, s1
    addi    a1, s4, 8
    call    lantern_lc_find_block
    beqz    a0, 94f
    mv      a2, a0
    mv      a0, s1
    li      a1, LC_PART_BLOCKS
    call    lantern_lc_ref
    ld      t0, LcBlock_slot(a0)
    ld      t1, LcStore_latest_finalized_slot(s1)
    bgeu    t1, t0, 1f
    mv      s7, a2
1:  mv      a0, s1                          # the room: records, scratch, periods, finalized, bootstraps
    li      a1, 1
    li      a2, 0
    li      a3, 1
    call    lantern_lc_reserve
    bnez    a0, 98f
    ld      t0, LcStore_blocks(s1)
    slli    t0, t0, 3
    addi    t0, t0, 8
    ld      t1, 0(s5)
    bltu    t1, t0, 98f
    mv      a0, s1
    li      a1, LC_PART_BLOCKS
    mv      a2, s6
    call    lantern_lc_ref
    mv      s8, a0
    ld      t0, LcStore_tail_slot(s1)
    ld      t1, LcStore_latest_finalized_slot(s1)
    bgeu    t0, t1, 11f
    mv      t0, t1
11: sd      t0, L(sp)
    li      t4, 0
    ld      t1, LcBlock_slot(s8)
    ld      t2, LcStore_tail_slot(s1)
    bltu    t1, t2, 2f
    li      t3, LC_SPP
    divu    t1, t1, t3
    divu    t2, t0, t3
    bltu    t1, t2, 2f
    sub     t4, t1, t2
    addi    t4, t4, 1
2:  ld      t0, LcStore_periods(s1)
    add     t0, t0, t4
    ld      t1, (LcStore_room + LcRoom_periods)(s1)
    bltu    t1, t0, 98f
    sd      zero, (L + 8)(sp)
    beqz    s7, 4f
    ld      s9, LcStore_latest_finalized_slot(s1)   # above it and the last LcFinalized
    ld      a2, LcStore_finalized(s1)
    beqz    a2, 21f
    addi    a2, a2, -1
    mv      a0, s1
    li      a1, LC_PART_FINALIZED
    call    lantern_lc_at
    ld      t0, LcFinalized_slot(a0)
    bgeu    s9, t0, 21f
    mv      s9, t0
21: sd      s9, (L + 32)(sp)
    mv      s10, s7
3:  beqz    s10, 31f
    mv      a0, s1
    li      a1, LC_PART_BLOCKS
    mv      a2, s10
    call    lantern_lc_ref
    ld      t0, LcBlock_slot(a0)
    bgeu    s9, t0, 31f
    ld      t0, (L + 8)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 8)(sp)
    ld      s10, LcBlock_parent(a0)
    j       3b
31: ld      t2, (L + 8)(sp)
    ld      t0, LcStore_finalized(s1)
    add     t0, t0, t2
    ld      t1, (LcStore_room + LcRoom_finalized)(s1)
    bltu    t1, t0, 98f
    ld      t0, LcStore_bootstraps(s1)
    add     t0, t0, t2
    ld      t1, (LcStore_room + LcRoom_bootstraps)(s1)
    bltu    t1, t0, 98f
4:  ld      t0, LcBlock_slot(s8)            # the head
    ld      t1, LcStore_tail_slot(s1)
    bltu    t0, t1, 30f
    li      t1, LC_SPP
    divu    s9, t0, t1
    ld      t2, L(sp)
    divu    s10, t2, t1
    bltu    s9, s10, 10f
    sd      s6, (L + 40)(sp)
5:  addi    t0, s9, 1                       # period s9: the entry at its last slot
    li      t1, LC_SPP
    mul     a2, t0, t1
    addi    a2, a2, -1
    mv      a0, s1
    ld      a1, (L + 40)(sp)
    call    lantern_lc_ancestor
    beqz    a0, 10f
    sd      a0, (L + 40)(sp)
    mv      a2, a0
    mv      a0, s1
    li      a1, LC_PART_BLOCKS
    call    lantern_lc_ref
    ld      t0, LcBlock_slot(a0)
    ld      t1, L(sp)
    bltu    t0, t1, 10f
    ld      a2, LcBlock_best(a0)
    beqz    a2, 7f
    sd      a2, (L + 48)(sp)
    mv      a0, s1
    li      a1, LC_PART_UPDATES
    call    lantern_lc_ref
    addi    a0, a0, LcUpdate_sync_aggregate
    call    lantern_lc_participants
    ld      a2, (L + 48)(sp)
    li      t0, MIN_SYNC_COMMITTEE_PARTICIPANTS
    bgeu    a0, t0, 7f
    li      a2, 0
7:  mv      a0, s1
    mv      a1, s9
    call    lantern_lc_set_period
    beq     s9, s10, 10f
    addi    s9, s9, -1
    j       5b
10: ld      a2, LcBlock_latest_signature_slot(s8)   # latest: S at it, A before S
    sd      a2, (L + 48)(sp)
    ld      t0, L(sp)
    bgeu    t0, a2, 12f
    mv      a0, s1
    mv      a1, s6
    call    lantern_lc_ancestor
    beqz    a0, 12f
    sd      a0, (L + 40)(sp)
    mv      a2, a0
    mv      a0, s1
    li      a1, LC_PART_BLOCKS
    call    lantern_lc_ref
    mv      s9, a0
    ld      a2, LcBlock_slot(s9)
    ld      t0, L(sp)
    bgeu    t0, a2, 12f
    addi    a2, a2, -1
    mv      a0, s1
    ld      a1, (L + 40)(sp)
    call    lantern_lc_ancestor
    beqz    a0, 12f
    mv      s10, a0
    mv      a2, a0
    mv      a0, s1
    li      a1, LC_PART_BLOCKS
    call    lantern_lc_ref
    ld      t0, LcBlock_slot(a0)
    ld      t1, L(sp)
    bltu    t0, t1, 12f
    mv      a0, s1
    mv      a1, s10
    ld      a2, (L + 48)(sp)
    addi    a3, s9, LcBlock_sync_aggregate
    li      a4, 0
    call    lantern_lc_make_update
    sd      a0, LcStore_latest(s1)
    j       30f
12: sd      zero, LcStore_latest(s1)
30: beqz    s7, 60f                         # the checkpoint: its LcFinalized from the top down
    ld      t0, LcStore_finalized(s1)
    ld      t1, (L + 8)(sp)
    add     t0, t0, t1
    sd      t0, LcStore_finalized(s1)
    addi    s10, t0, -1
    mv      s8, s7
32: ld      t0, (L + 8)(sp)
    beqz    t0, 33f
    addi    t0, t0, -1
    sd      t0, (L + 8)(sp)
    mv      a0, s1
    li      a1, LC_PART_BLOCKS
    mv      a2, s8
    call    lantern_lc_ref
    mv      s9, a0
    mv      a0, s1
    li      a1, LC_PART_FINALIZED
    mv      a2, s10
    call    lantern_lc_at
    ld      t0, LcBlock_slot(s9)
    sd      t0, LcFinalized_slot(a0)
    addi    t0, a0, LcFinalized_root
    COPY32  t0, s9
    addi    s10, s10, -1
    ld      s8, LcBlock_parent(s9)
    j       32b
33: mv      a0, s1
    li      a1, LC_PART_BLOCKS
    mv      a2, s7
    call    lantern_lc_ref
    mv      s8, a0
    ld      t0, 0(s4)
    sd      t0, LcStore_latest_finalized_epoch(s1)
    ld      s9, LcStore_latest_finalized_slot(s1)   # the old latest_finalized_slot
    ld      t2, LcBlock_slot(s8)
    sd      t2, LcStore_latest_finalized_slot(s1)
    addi    t0, s1, LcStore_latest_finalized_root
    COPY32  t0, s8
    ld      t1, LcStore_tail_slot(s1)       # the bootstraps of the new epoch boundary blocks
    bltu    t2, t1, 50f
    addi    t0, s9, 1
    bgeu    t0, t1, 34f
    mv      t0, t1
34: sd      t0, (L + 24)(sp)
    sd      t2, (L + 16)(sp)
40: ld      a1, (L + 16)(sp)
    ld      t0, (L + 24)(sp)
    bltu    a1, t0, 50f
    mv      a0, s1
    call    lantern_lc_finalized_at
    beqz    a0, 50f
    mv      s10, a0
    ld      t0, LcFinalized_slot(s10)
    ld      t1, (L + 24)(sp)
    bltu    t0, t1, 41f
    mv      a0, s1
    mv      a1, s10
    call    lantern_lc_add_bootstrap
41: ld      t0, LcFinalized_slot(s10)
    addi    t0, t0, SLOTS_PER_EPOCH - 1
    li      t1, SLOTS_PER_EPOCH
    divu    t0, t0, t1
    mul     t0, t0, t1
    bltu    t0, t1, 50f
    sub     t0, t0, t1
    sd      t0, (L + 16)(sp)
    j       40b
50: mv      a0, s1                          # the entries below the checkpoint's go
    ld      a1, LcBlock_slot(s8)
    mv      a2, s5
    call    lantern_lc_prune
60: li      a0, LANTERN_OK
    LEAVE 64
94: li      a0, LANTERN_INVALID_UNKNOWN_BLOCK
    LEAVE 64
98: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_lc_on_head

# (lc, kind, key, out, fork) -> status: lantern_lc_read (light-client.md). s1 lc, s2 kind, s3 key,
# s4 out, s5 fork, s6 the bootstrap or update, s7 a count, s8 its fork. Locals: L the parts.
FUNCTION lantern_lc_read
    ENTER 80
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    li      t0, LC_OBJECT_OPTIMISTIC_UPDATE
    bltu    t0, s2, 97f
    bnez    s2, 10f
    li      a1, LC_PART_BOOTSTRAPS          # the bootstrap of the root
    call    lantern_lc_part
    mv      s6, a0
    ld      s7, LcStore_bootstraps(s1)
1:  beqz    s7, 93f
    NE32    s6, s3, 2f
    j       3f
2:  addi    s6, s6, LcBootstrap__mem
    addi    s7, s7, -1
    j       1b
3:  mv      a0, s1
    li      a1, LC_PART_HEADERS
    ld      a2, LcBootstrap_header(s6)
    call    lantern_lc_ref
    ld      s8, LcHeader_fork(a0)
    addi    a0, a0, LcHeader_header
    sd      a0, (L + LcParts_header)(sp)
    mv      a0, s1
    li      a1, LC_PART_COMMITTEES
    ld      a2, LcBootstrap_sync_committee(s6)
    call    lantern_lc_ref
    addi    a0, a0, LcCommittee_committee
    sd      a0, (L + LcParts_sync_committee)(sp)
    addi    t0, s6, LcBootstrap_branch
    sd      t0, (L + LcParts_branch)(sp)
    mv      t0, s8
    LC_COUNTS
    sd      t0, (L + LcParts_branch_count)(sp)
    j       30f
10: li      t0, LC_OBJECT_UPDATE
    bne     s2, t0, 20f
    mv      a0, s1                          # the period's update
    li      a1, LC_PART_PERIODS
    call    lantern_lc_part
    ld      s7, LcStore_periods(s1)
11: beqz    s7, 93f
    ld      t0, LcPeriod_period(a0)
    beq     t0, s3, 12f
    addi    a0, a0, LcPeriod__mem
    addi    s7, s7, -1
    j       11b
12: ld      a2, LcPeriod_update(a0)
    j       21f
20: ld      a2, LcStore_latest(s1)          # the latest finality update
    beqz    a2, 93f
21: mv      a0, s1
    li      a1, LC_PART_UPDATES
    call    lantern_lc_ref
    mv      s6, a0
    ld      s8, LcUpdate_fork(s6)
    mv      a0, s1
    li      a1, LC_PART_HEADERS
    ld      a2, LcUpdate_attested_header(s6)
    call    lantern_lc_ref
    addi    a0, a0, LcHeader_header
    sd      a0, (L + LcParts_header)(sp)
    mv      a0, s1
    li      a1, LC_PART_HEADERS
    ld      a2, LcUpdate_finalized_header(s6)
    call    lantern_lc_ref
    addi    a0, a0, LcHeader_header
    sd      a0, (L + LcParts_finalized_header)(sp)
    sd      zero, (L + LcParts_sync_committee)(sp)
    ld      a2, LcUpdate_next_sync_committee(s6)
    beqz    a2, 22f
    mv      a0, s1
    li      a1, LC_PART_COMMITTEES
    call    lantern_lc_ref
    addi    a0, a0, LcCommittee_committee
    sd      a0, (L + LcParts_sync_committee)(sp)
22: addi    t0, s6, LcUpdate_next_branch
    sd      t0, (L + LcParts_branch)(sp)
    addi    t0, s6, LcUpdate_finality_branch
    sd      t0, (L + LcParts_finality_branch)(sp)
    addi    t0, s6, LcUpdate_sync_aggregate
    sd      t0, (L + LcParts_sync_aggregate)(sp)
    ld      t0, LcUpdate_signature_slot(s6)
    sd      t0, (L + LcParts_signature_slot)(sp)
    mv      t0, s8
    LC_COUNTS
    sd      t0, (L + LcParts_branch_count)(sp)
    sd      t1, (L + LcParts_finality_count)(sp)
30: mv      a0, s2
    addi    a1, sp, L
    mv      a2, s4
    mv      t6, s8
    FORK_CALL lc_object
    bnez    a0, 99f
    sd      s8, 0(s5)
    LEAVE 80
93: li      a0, LANTERN_NO_STATE_ANSWER
    LEAVE 80
97: li      a0, LANTERN_INVALID_EVENT
99: LEAVE 80
END_FUNCTION lantern_lc_read
