/*
 * The index of the stored history, RISC-V: in the common object. Requirements: docs/reference/db.md.
 */

# (room, size): DB_FIXED + the room of each part; roots a power of two. A leaf; uses t0-t3.
FUNCTION lantern_db_size
    UNWIND_END_PROLOGUE
    ld      t0, DbRoom_roots(a0)
    beqz    t0, 9f
    addi    t1, t0, -1
    and     t1, t1, t0
    bnez    t1, 9f
    srli    t1, t0, 61
    bnez    t1, 9f
    slli    t2, t0, 3
    ld      t0, DbRoom_slots(a0)
    li      t1, DbSlot__mem
    mulhu   t3, t0, t1
    bnez    t3, 9f
    mul     t0, t0, t1
    add     t3, t2, t0
    bltu    t3, t2, 9f
    addi    t2, t3, DB_FIXED
    bltu    t2, t3, 9f
    sd      t2, 0(a1)
    li      a0, LANTERN_OK
    ret
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_db_size

# The parts of the Db a0 for the room a1: slots at DB_FIXED, then roots; their counts the capacities. Uses t0, t1.
LOCAL_FUNCTION db_layout
    UNWIND_END_PROLOGUE
    ld      t0, DbRoom_slots(a1)
    li      t1, DB_FIXED
    sd      t1, Db_slots(a0)
    sd      t0, (Db_slots + 8)(a0)
    li      t1, DbSlot__mem
    mul     t0, t0, t1
    addi    t0, t0, DB_FIXED
    sd      t0, Db_roots(a0)
    ld      t0, DbRoom_roots(a1)
    sd      t0, (Db_roots + 8)(a0)
    ret
END_FUNCTION db_layout

# The root at a1 goes in the root table of the Db a0 with the value a2, at the first free entry from its first 8 bytes. Uses t0-t3.
LOCAL_FUNCTION db_insert
    UNWIND_END_PROLOGUE
    ld      t0, Db_roots(a0)
    add     t0, a0, t0
    ld      t1, (Db_roots + 8)(a0)
    addi    t1, t1, -1
    ld      t2, 0(a1)
    and     t2, t2, t1
1:  slli    t3, t2, 3
    add     t3, t0, t3
    ld      t3, 0(t3)
    beqz    t3, 2f
    addi    t2, t2, 1
    and     t2, t2, t1
    j       1b
2:  slli    t3, t2, 3
    add     t3, t0, t3
    sd      a2, 0(t3)
    ret
END_FUNCTION db_insert

# a0 = the entry index (slot - first_slot) of the block of the root at a1 in the Db a0, or 2^64 - 1. Uses t0-t6, a2, a6, a7.
LOCAL_FUNCTION db_find
    UNWIND_END_PROLOGUE
    ld      t0, Db_roots(a0)
    add     t0, a0, t0
    ld      t4, (Db_roots + 8)(a0)          # at most the capacity of probes
    addi    t1, t4, -1
    ld      t5, Db_slots(a0)
    add     t5, a0, t5
    ld      t2, 0(a1)
    and     t2, t2, t1
1:  beqz    t4, 3f
    slli    t3, t2, 3
    add     t3, t0, t3
    ld      t3, 0(t3)
    beqz    t3, 3f
    addi    t3, t3, -1
    li      t6, DbSlot__mem
    mul     a2, t3, t6
    add     a2, a2, t5
    NE32    a2, a1, 2f
    mv      a0, t3
    ret
2:  addi    t2, t2, 1
    and     t2, t2, t1
    addi    t4, t4, -1
    j       1b
3:  li      a0, -1
    ret
END_FUNCTION db_find

# The root table of the Db a0 again from its entries: zeroed, then the root of each block; blocks
# their count. s1 db, s2 an entry, s3 its index, s4 the entries in use.
LOCAL_FUNCTION db_rehash
    ENTER 0
    mv      s1, a0
    ld      t0, Db_roots(s1)
    add     a0, s1, t0
    ld      a1, (Db_roots + 8)(s1)
    slli    a1, a1, 3
    call    lantern_zero
    sd      zero, Db_blocks(s1)
    ld      t0, Db_first_slot(s1)
    ld      s4, Db_end_slot(s1)
    sub     s4, s4, t0
    ld      s2, Db_slots(s1)
    add     s2, s1, s2
    li      s3, 0
1:  bgeu    s3, s4, 9f
    ld      t0, DbSlot_block(s2)
    beqz    t0, 2f
    mv      a0, s1
    mv      a1, s2
    addi    a2, s3, 1
    call    db_insert
    ld      t0, Db_blocks(s1)
    addi    t0, t0, 1
    sd      t0, Db_blocks(s1)
2:  addi    s2, s2, DbSlot__mem
    addi    s3, s3, 1
    j       1b
9:  LEAVE 0
END_FUNCTION db_rehash

# (room, slot, db): no records; first_slot and end_slot the slot. s1 room, s2 the slot, s3 db. Locals: L the size.
FUNCTION lantern_db_init
    ENTER 16
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    addi    a1, sp, L
    call    lantern_db_size
    bnez    a0, 9f
    ld      t0, 0(s3)
    ld      t1, L(sp)
    bltu    t0, t1, 8f
    addi    a0, s3, 8
    addi    a1, t1, -8
    call    lantern_zero
    sd      s2, Db_first_slot(s3)
    sd      s2, Db_end_slot(s3)
    mv      a0, s3
    mv      a1, s1
    call    db_layout
    li      a0, LANTERN_OK
9:  LEAVE 16
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_db_init

# (db, room, out): the index in out with the capacities of room. s1 db, s2 room, s3 out, s4 the
# entries in use. Locals: L the size.
FUNCTION lantern_db_copy
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      a0, s2
    addi    a1, sp, L
    call    lantern_db_size
    bnez    a0, 9f
    ld      t0, 0(s3)
    ld      t1, L(sp)
    bltu    t0, t1, 8f
    ld      t0, Db_first_slot(s1)
    ld      s4, Db_end_slot(s1)
    sub     s4, s4, t0
    ld      t0, DbRoom_slots(s2)            # room for the entries in use, and the table at most half full
    bltu    t0, s4, 8f
    ld      t0, DbRoom_roots(s2)
    ld      t1, Db_blocks(s1)
    slli    t1, t1, 1
    bltu    t0, t1, 8f
    addi    a0, s3, 8
    ld      a1, L(sp)
    addi    a1, a1, -8
    call    lantern_zero
    ld      t0, Db_first_slot(s1)
    sd      t0, Db_first_slot(s3)
    ld      t0, Db_end_slot(s1)
    sd      t0, Db_end_slot(s3)
    mv      a0, s3
    mv      a1, s2
    call    db_layout
    ld      t0, Db_slots(s3)                # the entries in use, then each root again
    add     a0, s3, t0
    ld      t0, Db_slots(s1)
    add     a1, s1, t0
    li      t0, DbSlot__mem
    mul     a2, s4, t0
    call    lantern_copy
    mv      a0, s3
    call    db_rehash
    li      a0, LANTERN_OK
9:  LEAVE 16
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_db_copy

# (db, record, offset): one record at an offset of its segment into the index; nothing changes on a
# status. s1 db, s2 the record, s3 the offset, s4 the entry index, s5 the entry.
FUNCTION lantern_db_add
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    ld      s3, 0(a2)
    andi    t0, s3, 7                       # an offset of a multiple of 8, below DB_OFFSET_MAX
    bnez    t0, 7f
    srli    t0, s3, 44
    bnez    t0, 7f
    ld      t0, DbRecord_length(s2)         # length at most DB_RECORD_MAX
    li      t1, 1
    slli    t1, t1, 32
    bgtu    t0, t1, 7f
    addi    t0, t0, 24                      # its ByteList header: size 24 + length, offset 24
    ld      t1, DbRecord_bytes(s2)
    bne     t0, t1, 7f
    ld      t0, (DbRecord_bytes + 8)(s2)
    li      t1, 24
    bne     t0, t1, 7f
    ld      s4, DbRecord_slot(s2)           # a slot from first_slot, in the room
    ld      t0, Db_first_slot(s1)
    bltu    s4, t0, 7f
    sub     s4, s4, t0
    ld      t0, (Db_slots + 8)(s1)
    bgeu    s4, t0, 8f
    ld      s5, Db_slots(s1)
    add     s5, s1, s5
    li      t0, DbSlot__mem
    mul     t0, s4, t0
    add     s5, s5, t0
    ld      t0, DbRecord_kind(s2)
    li      t1, DB_BLOCK
    beq     t0, t1, 1f
    li      t1, DB_STATE
    beq     t0, t1, 5f
    li      t1, DB_STATE_DIFF
    beq     t0, t1, 5f
    li      t1, DB_BLOB_SIDECAR
    beq     t0, t1, 4f
    li      t1, DB_COLUMN_SIDECAR
    bne     t0, t1, 7f
4:  ld      t0, DbSlot_block(s5)            # a sidecar: of a slot with a block, an index below DB_SIDECAR_INDICES
    beqz    t0, 7f
    ld      t3, DbRecord_index(s2)
    li      t1, DB_SIDECAR_INDICES
    bgeu    t3, t1, 7f
    ld      t4, DbRecord_length(s2)         # its size: 64 + length rounded up to 8
    addi    t4, t4, DbRecord__mem + 7
    andi    t4, t4, -8
    ld      t0, DbSlot_sidecars(s5)
    beqz    t0, 2f
    ld      t1, DbSlot_sidecar_end(s5)      # after the slot's sidecars, of their size, with a higher index
    bne     t1, s3, 7f
    sub     t1, t1, t0
    addi    t1, t1, 1                       # the bytes of the slot's sidecars
    ld      t2, DbSlot_sidecar_count(s5)
    mul     t2, t2, t4
    bne     t2, t1, 7f
    ld      t1, DbSlot_sidecar_last(s5)
    bleu    t3, t1, 7f
    j       3f
2:  addi    t0, s3, 1
    sd      t0, DbSlot_sidecars(s5)
3:  ld      t0, DbSlot_sidecar_count(s5)
    addi    t0, t0, 1
    sd      t0, DbSlot_sidecar_count(s5)
    add     t0, t4, s3
    sd      t0, DbSlot_sidecar_end(s5)
    sd      t3, DbSlot_sidecar_last(s5)
    srli    t0, t3, 3                       # its bit in indices
    add     t0, t0, s5
    lbu     t1, DbSlot_indices(t0)
    andi    t2, t3, 7
    li      t5, 1
    sll     t5, t5, t2
    or      t1, t1, t5
    sb      t1, DbSlot_indices(t0)
    j       9f
1:  ld      t0, DbSlot_block(s5)            # a block: none in its slot, its root in no other
    bnez    t0, 7f
    mv      a0, s1
    addi    a1, s2, DbRecord_root
    call    db_find
    li      t0, -1
    bne     a0, t0, 7f
    ld      t0, Db_blocks(s1)               # the table at most half full
    addi    t0, t0, 1
    slli    t0, t0, 1
    ld      t1, (Db_roots + 8)(s1)
    bgtu    t0, t1, 8f
    addi    t0, s2, DbRecord_root
    COPY32  s5, t0
    addi    t0, s3, 1
    sd      t0, DbSlot_block(s5)
    mv      a0, s1
    addi    a1, s2, DbRecord_root
    addi    a2, s4, 1
    call    db_insert
    ld      t0, Db_blocks(s1)
    addi    t0, t0, 1
    sd      t0, Db_blocks(s1)
    ld      t0, DbRecord_slot(s2)           # end_slot past it
    addi    t0, t0, 1
    ld      t1, Db_end_slot(s1)
    bleu    t0, t1, 9f
    sd      t0, Db_end_slot(s1)
    j       9f
5:  ld      t1, DbRecord_index(s2)          # a state: index 0, its slot's block of its root, no state yet
    bnez    t1, 7f
    ld      t1, DbSlot_block(s5)
    beqz    t1, 7f
    ld      t1, DbSlot_state(s5)
    bnez    t1, 7f
    seqz    t1, s3                          # DB_STATE at offset 0, DB_STATE_DIFF above it
    addi    t2, t0, -DB_STATE
    seqz    t2, t2
    bne     t1, t2, 7f
    li      t2, 0
51: add     t3, s5, t2
    ld      t1, DbSlot_root(t3)
    add     t3, s2, t2
    ld      t4, DbRecord_root(t3)
    bne     t1, t4, 7f
    addi    t2, t2, 8
    li      t3, 32
    bltu    t2, t3, 51b
    addi    t1, s3, 1
    sd      t1, DbSlot_state(s5)
9:  li      a0, LANTERN_OK
    LEAVE 0
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
7:  li      a0, LANTERN_INVALID_RECORD
    LEAVE 0
END_FUNCTION lantern_db_add

# (db, segment, segment_kind, bytes, valid): each whole record of a segment's bytes into the index,
# until one does not fit or is rejected. s1 db, s2 the segment, s3 the sidecars flag, s4 the
# bytes, s5 their count, s6 valid, s7 the position, s8 the segment's first slot, s9 a record.
# Locals: L the record's size, L+8 its offset.
FUNCTION lantern_db_scan
    ENTER 16
    mv      s1, a0
    ld      s2, 0(a1)
    ld      s3, 0(a2)
    ld      t0, 8(a3)
    add     s4, a3, t0
    ld      s5, 16(a3)
    mv      s6, a4
    li      s7, 0
    li      t0, DB_SEGMENT_SLOTS
    mulhu   t1, s2, t0
    bnez    t1, 9f
    mul     s8, s2, t0
1:  sub     t0, s5, s7                      # its header and its size inside the bytes
    li      t1, DbRecord__mem
    bltu    t0, t1, 9f
    add     s9, s4, s7
    ld      t1, DbRecord_length(s9)
    li      t2, 1
    slli    t2, t2, 32
    bgtu    t1, t2, 9f
    addi    t1, t1, DbRecord__mem + 7
    andi    t1, t1, -8
    bgtu    t1, t0, 9f
    sd      t1, L(sp)
    ld      t0, DbRecord_slot(s9)           # a slot of the segment
    bltu    t0, s8, 9f
    sub     t0, t0, s8
    li      t1, DB_SEGMENT_SLOTS
    bgeu    t0, t1, 9f
    ld      t0, DbRecord_kind(s9)           # the kind of its segment: kind / 2, 0 blocks, 1 sidecars, 2 states
    srli    t0, t0, 1
    bne     t0, s3, 9f
    sd      s7, (L + 8)(sp)
    mv      a0, s1
    mv      a1, s9
    addi    a2, sp, L + 8
    call    lantern_db_add
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    bnez    a0, 9f
    ld      t0, L(sp)
    add     s7, s7, t0
    j       1b
8:  sd      s7, 0(s6)
    li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
9:  sd      s7, 0(s6)
    li      a0, LANTERN_OK
    LEAVE 16
END_FUNCTION lantern_db_scan

# (db, root, slot): the slot of the root's block, or 2^64 - 1. Locals: 0 db, 8 slot.
FUNCTION lantern_db_find_root
    FRAME 16
    sd      a0, 0(sp)
    sd      a2, 8(sp)
    call    db_find
    li      t0, -1
    beq     a0, t0, 1f
    ld      t0, 0(sp)
    ld      t0, Db_first_slot(t0)
    add     a0, a0, t0
1:  ld      t0, 8(sp)
    sd      a0, 0(t0)
    li      a0, LANTERN_OK
    UNFRAME 16
END_FUNCTION lantern_db_find_root

# (db, slot): first_slot the slot, at most end_slot; the kept entries to the front, the root table
# again. A slot not after first_slot changes nothing. s1 db, s2 the new first slot, s3 first_slot,
# s4 end_slot, s5 the entries dropped, s6 those kept, s7 the entries.
FUNCTION lantern_db_prune
    ENTER 0
    mv      s1, a0
    ld      s2, 0(a1)
    ld      s3, Db_first_slot(s1)
    ld      s4, Db_end_slot(s1)
    bleu    s2, s3, 9f
    bleu    s2, s4, 1f
    mv      s2, s4
1:  sub     s5, s2, s3
    sub     s6, s4, s2
    ld      s7, Db_slots(s1)
    add     s7, s1, s7
    li      t0, DbSlot__mem
    mv      a0, s7
    mul     a1, s5, t0
    add     a1, a1, s7
    mul     a2, s6, t0
    call    lantern_copy
    li      t0, DbSlot__mem
    mul     a0, s6, t0
    add     a0, a0, s7
    mul     a1, s5, t0
    call    lantern_zero
    sd      s2, Db_first_slot(s1)
    mv      a0, s1
    call    db_rehash
9:  li      a0, LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_db_prune

/*
 * (db, slot): the sidecars of the slots from first_slot below the slot and end_slot leave the index:
 * each DbSlot keeps its root and block, and its sidecar fields become 0. s1 db, s2 an entry, s3 the
 * entries left.
 */
FUNCTION lantern_db_drop_sidecars
    ENTER 0
    mv      s1, a0
    ld      t0, 0(a1)
    ld      t1, Db_end_slot(s1)
    bleu    t0, t1, 1f
    mv      t0, t1
1:  ld      t1, Db_first_slot(s1)
    bleu    t0, t1, 9f
    sub     s3, t0, t1
    ld      s2, Db_slots(s1)
    add     s2, s1, s2
2:  beqz    s3, 9f
    addi    a0, s2, DbSlot_sidecars
    li      a1, DbSlot_state - DbSlot_sidecars
    call    lantern_zero
    addi    s2, s2, DbSlot__mem
    addi    s3, s3, -1
    j       2b
9:  li      a0, LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_db_drop_sidecars

# L0: a0 = the u64 of the a1 bytes at a0 (as a signed count: 8 or more a whole word, 0 or less none), zero above them. Uses t0-t3.
LOCAL_FUNCTION db_word
    UNWIND_END_PROLOGUE
    li      t0, 8
    blt     a1, t0, 1f
    ld      a0, 0(a0)
    ret
1:  mv      t1, a0
    li      a0, 0
    blez    a1, 3f
    li      t0, 0
2:  add     t2, t1, t0
    lbu     t2, 0(t2)
    slli    t3, t0, 3
    sll     t2, t2, t3
    or      a0, a0, t2
    addi    t0, t0, 1
    bltu    t0, a1, 2b
3:  ret
END_FUNCTION db_word

# L1: a0 = 1 when word a0 of the state differs from the patch's start, else 0 (db.md, the state
# diffs). Reads s1 the base's bytes, s2 min(their count, the state's), s3 the state's bytes, s4
# their count. Uses a1, t0-t6.
LOCAL_FUNCTION db_differ
    FRAME 0
    slli    t5, a0, 3
    addi    t4, t5, 8
    bgtu    t4, s2, 1f
    add     t4, s3, t5
    ld      t6, 0(t4)
    add     t4, s1, t5
    ld      t4, 0(t4)
    j       2f
1:  add     a0, s3, t5
    sub     a1, s4, t5
    call    db_word
    mv      t6, a0
    add     a0, s1, t5
    sub     a1, s2, t5
    call    db_word
    mv      t4, a0
2:  sub     a0, t6, t4
    snez    a0, a0
    UNFRAME 0
END_FUNCTION db_differ

# (base, state, out, size): the diff of the state's bytes against the base's (db.md, the state
# diffs): a pass that counts, then one that writes. s1 the base's bytes, s2 min(their count, the
# state's), s3 the state's bytes, s4 their count, s5 its words, s6 the diff's bytes (0 while
# counting), s7 the diff's length so far, s8 the word, s9 a run's first word, s10 its last.
# Locals: L out, L+8 size, L+16 the first equal word after a group, then a word, L+24 a place.
FUNCTION lantern_db_state_diff
    ENTER 32
    sd      a2, L(sp)
    sd      a3, (L + 8)(sp)
    ld      t0, 8(a0)
    add     s1, a0, t0
    ld      s2, 16(a0)
    ld      t0, 8(a1)
    add     s3, a1, t0
    ld      s4, 16(a1)
    bleu    s2, s4, 1f
    mv      s2, s4
1:  addi    s5, s4, 7
    srli    s5, s5, 3
    li      s6, 0
10: li      s7, 8                           # the length, then the runs
    beqz    s6, 11f
    sd      s4, 0(s6)
11: li      s8, 0
12: bgeu    s8, s5, 30f
    mv      a0, s8
    call    db_differ
    bnez    a0, 13f
    addi    s8, s8, 1
    j       12b
13: mv      s9, s8                          # a group from this word
    mv      s10, s8
    addi    s8, s8, 1
14: bgeu    s8, s5, 20f
    mv      a0, s8
    call    db_differ
    beqz    a0, 15f
    mv      s10, s8
    addi    s8, s8, 1
    j       14b
15: sd      s8, (L + 16)(sp)                # equal words: past them
16: addi    s8, s8, 1
    bgeu    s8, s5, 20f
    mv      a0, s8
    call    db_differ
    beqz    a0, 16b
    ld      t0, (L + 16)(sp)                # at most 2 equal words between: the group goes on
    sub     t0, s8, t0
    li      t1, 2
    bgtu    t0, t1, 20f
    mv      s10, s8
    addi    s8, s8, 1
    j       14b
20: slli    t0, s9, 3                       # the run: offset, count, the words; then on from s8
    addi    t1, s10, 1
    slli    t1, t1, 3
    bleu    t1, s4, 201f
    mv      t1, s4
201: sub    t1, t1, t0
    addi    t2, t1, 7
    andi    t2, t2, -8
    addi    t3, s7, 16
    add     s7, t3, t2
    beqz    s6, 12b
    add     t3, s6, t3
    sd      t0, -16(t3)
    sd      t1, -8(t3)
    sd      t3, (L + 24)(sp)
    sd      s9, (L + 16)(sp)
21: ld      t0, (L + 16)(sp)
    bgtu    t0, s10, 12b
    slli    t0, t0, 3
    add     a0, s3, t0
    sub     a1, s4, t0
    call    db_word
    ld      t3, (L + 24)(sp)
    sd      a0, 0(t3)
    addi    t3, t3, 8
    sd      t3, (L + 24)(sp)
    ld      t0, (L + 16)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 16)(sp)
    j       21b
30: bnez    s6, 9f
    ld      t0, L(sp)                       # counted: the size, then the room
    ld      t1, (L + 8)(sp)
    addi    t2, s7, 24
    sd      t2, 0(t1)
    ld      t3, 0(t0)
    bltu    t3, t2, 8f
    li      t3, 24
    sd      t3, 8(t0)
    sd      s7, 16(t0)
    addi    s6, t0, 24
    j       10b
9:  li      a0, LANTERN_OK
    LEAVE 32
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION lantern_db_state_diff

# (base, diff, out, size): the state's bytes from the base's and the diff (db.md, the state
# diffs). s1 the base's bytes, s2 min(their count, length), s3 the diff's bytes, s4 their count,
# s5 length, s6 the out bytes, s7 the position in the diff, s8 the end of the run before.
FUNCTION lantern_db_state_patch
    ENTER 0
    ld      t0, 8(a1)
    add     s3, a1, t0
    ld      s4, 16(a1)
    li      t0, 8
    bltu    s4, t0, 7f
    ld      s5, 0(s3)
    addi    t0, s5, 24
    bltu    t0, s5, 7f
    sd      t0, 0(a3)
    ld      t1, 0(a2)
    bltu    t1, t0, 8f
    li      t1, 24
    sd      t1, 8(a2)
    sd      s5, 16(a2)
    addi    s6, a2, 24
    ld      t0, 8(a0)
    add     s1, a0, t0
    ld      s2, 16(a0)
    bleu    s2, s5, 1f
    mv      s2, s5
1:  li      t0, 0                           # the base's bytes to min(their count, length)
2:  addi    t1, t0, 8
    bgtu    t1, s2, 3f
    add     t2, s1, t0
    ld      t3, 0(t2)
    add     t2, s6, t0
    sd      t3, 0(t2)
    mv      t0, t1
    j       2b
3:  bgeu    t0, s2, 4f
    add     t2, s1, t0
    lbu     t3, 0(t2)
    add     t2, s6, t0
    sb      t3, 0(t2)
    addi    t0, t0, 1
    j       3b
4:  bgeu    t0, s5, 5f                      # zero bytes to length: to a multiple of 8, words, the rest
    andi    t1, t0, 7
    beqz    t1, 41f
    add     t2, s6, t0
    sb      zero, 0(t2)
    addi    t0, t0, 1
    j       4b
41: addi    t1, t0, 8
    bgtu    t1, s5, 42f
    add     t2, s6, t0
    sd      zero, 0(t2)
    mv      t0, t1
    j       41b
42: bgeu    t0, s5, 5f
    add     t2, s6, t0
    sb      zero, 0(t2)
    addi    t0, t0, 1
    j       42b
5:  li      s7, 8
    li      s8, 0
6:  bgeu    s7, s4, 9f                      # the runs end the diff's bytes
    sub     t0, s4, s7
    li      t1, 16
    bltu    t0, t1, 7f
    add     t2, s3, s7
    ld      t3, 0(t2)                       # offset, count
    ld      t4, 8(t2)
    beqz    t4, 7f
    andi    t1, t3, 7
    bnez    t1, 7f
    bltu    t3, s8, 7f
    bgtu    t4, s5, 7f
    sub     t1, s5, t4
    bgtu    t3, t1, 7f
    addi    t5, t4, 7
    andi    t5, t5, -8
    addi    t0, t0, -16
    bgtu    t5, t0, 7f
    addi    t2, t2, 16
    mv      t1, t4                          # zero padding
61: bgeu    t1, t5, 62f
    add     t6, t2, t1
    lbu     t6, 0(t6)
    bnez    t6, 7f
    addi    t1, t1, 1
    j       61b
62: add     t6, s6, t3                      # its bytes at its offset
    li      t1, 0
63: addi    t0, t1, 8
    bgtu    t0, t4, 64f
    add     a4, t2, t1
    ld      a4, 0(a4)
    add     a5, t6, t1
    sd      a4, 0(a5)
    mv      t1, t0
    j       63b
64: bgeu    t1, t4, 65f
    add     a4, t2, t1
    lbu     a4, 0(a4)
    add     a5, t6, t1
    sb      a4, 0(a5)
    addi    t1, t1, 1
    j       64b
65: add     s8, t3, t4
    addi    s7, s7, 16
    add     s7, s7, t5
    j       6b
9:  li      a0, LANTERN_OK
    LEAVE 0
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
7:  li      a0, LANTERN_INVALID_ENCODING
    LEAVE 0
END_FUNCTION lantern_db_state_patch
