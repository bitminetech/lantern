/*
 * The index of the stored history, ARM64: in the common object. Requirements: docs/reference/db.md.
 */

/* (room, size): DB_FIXED + the room of each part; roots a power of two. A leaf; uses x9-x13. */
FUNCTION lantern_db_size
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #DbRoom_roots]
    cbz     x9, 9f
    sub     x10, x9, #1
    tst     x9, x10
    b.ne    9f
    lsr     x10, x9, #61
    cbnz    x10, 9f
    lsl     x12, x9, #3
    ldr     x10, [x0, #DbRoom_slots]
    mov     x11, #DbSlot__mem
    umulh   x13, x10, x11
    cbnz    x13, 9f
    mul     x10, x10, x11
    adds    x12, x12, x10
    b.cs    9f
    adds    x12, x12, #DB_FIXED
    b.cs    9f
    str     x12, [x1]
    mov     x0, #LANTERN_OK
    ret
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_db_size

/* L0: the parts of the Db x0 for the room x1: slots at DB_FIXED, then roots; their counts the capacities. Uses x9-x11. */
LOCAL_FUNCTION db_layout
    UNWIND_END_PROLOGUE
    ldr     x9, [x1, #DbRoom_slots]
    mov     x10, #DB_FIXED
    stp     x10, x9, [x0, #Db_slots]
    mov     x11, #DbSlot__mem
    madd    x10, x9, x11, x10
    ldr     x9, [x1, #DbRoom_roots]
    stp     x10, x9, [x0, #Db_roots]
    ret
END_FUNCTION db_layout

/* L0: the root at x1 goes in the root table of the Db x0 with the value x2, at the first free entry from its first 8 bytes. Uses x9-x12. */
LOCAL_FUNCTION db_insert
    UNWIND_END_PROLOGUE
    ldp     x9, x10, [x0, #Db_roots]
    add     x9, x0, x9
    sub     x10, x10, #1
    ldr     x11, [x1]
    and     x11, x11, x10
1:  ldr     x12, [x9, x11, lsl #3]
    cbz     x12, 2f
    add     x11, x11, #1
    and     x11, x11, x10
    b       1b
2:  str     x2, [x9, x11, lsl #3]
    ret
END_FUNCTION db_insert

/* L0: x0 = the entry index (slot - first_slot) of the block of the root at x1 in the Db x0, or 2^64 - 1. Uses x2, x3, x9-x17. */
LOCAL_FUNCTION db_find
    UNWIND_END_PROLOGUE
    ldp     x9, x10, [x0, #Db_roots]
    add     x9, x0, x9
    mov     x16, x10                        /* at most the capacity of probes */
    sub     x10, x10, #1
    ldr     x13, [x0, #Db_slots]
    add     x13, x0, x13
    ldr     x11, [x1]
    and     x11, x11, x10
1:  cbz     x16, 3f
    ldr     x12, [x9, x11, lsl #3]
    cbz     x12, 3f
    sub     x12, x12, #1
    mov     x14, #DbSlot__mem
    madd    x14, x12, x14, x13
    ldp     x15, x17, [x14]
    ldp     x2, x3, [x1]
    cmp     x15, x2
    ccmp    x17, x3, #0, eq
    b.ne    2f
    ldp     x15, x17, [x14, #16]
    ldp     x2, x3, [x1, #16]
    cmp     x15, x2
    ccmp    x17, x3, #0, eq
    b.ne    2f
    mov     x0, x12
    ret
2:  add     x11, x11, #1
    and     x11, x11, x10
    sub     x16, x16, #1
    b       1b
3:  mov     x0, #-1
    ret
END_FUNCTION db_find

/*
 * L1: the root table of the Db x0 again from its entries: zeroed, then the root of each block;
 * blocks their count. x19 db, x20 an entry, x21 its index, x22 the entries in use.
 */
LOCAL_FUNCTION db_rehash
    ENTER 0
    mov     x19, x0
    ldp     x9, x10, [x19, #Db_roots]
    add     x0, x19, x9
    lsl     x1, x10, #3
    bl      lantern_zero
    str     xzr, [x19, #Db_blocks]
    ldp     x9, x10, [x19, #Db_first_slot]
    sub     x22, x10, x9
    ldr     x20, [x19, #Db_slots]
    add     x20, x19, x20
    mov     x21, #0
1:  cmp     x21, x22
    b.hs    9f
    ldr     x9, [x20, #DbSlot_block]
    cbz     x9, 2f
    mov     x0, x19
    mov     x1, x20
    add     x2, x21, #1
    bl      db_insert
    ldr     x9, [x19, #Db_blocks]
    add     x9, x9, #1
    str     x9, [x19, #Db_blocks]
2:  add     x20, x20, #DbSlot__mem
    add     x21, x21, #1
    b       1b
9:  LEAVE 0
END_FUNCTION db_rehash

/* (room, slot, db): no records; first_slot and end_slot the slot. x19 room, x20 the slot, x21 db. Locals: L the size. */
FUNCTION lantern_db_init
    ENTER 16
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    add     x1, sp, #L
    bl      lantern_db_size
    cbnz    x0, 9f
    ldr     x9, [x21]
    ldr     x10, [sp, #L]
    cmp     x9, x10
    b.lo    8f
    add     x0, x21, #8
    sub     x1, x10, #8
    bl      lantern_zero
    stp     x20, x20, [x21, #Db_first_slot]
    mov     x0, x21
    mov     x1, x19
    bl      db_layout
    mov     x0, #LANTERN_OK
9:  LEAVE 16
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_db_init

/*
 * (db, room, out): the index in out with the capacities of room. x19 db, x20 room, x21 out,
 * x22 the entries in use. Locals: L the size.
 */
FUNCTION lantern_db_copy
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x0, x20
    add     x1, sp, #L
    bl      lantern_db_size
    cbnz    x0, 9f
    ldr     x9, [x21]
    ldr     x10, [sp, #L]
    cmp     x9, x10
    b.lo    8f
    ldp     x9, x10, [x19, #Db_first_slot]
    sub     x22, x10, x9
    ldr     x9, [x20, #DbRoom_slots]       /* room for the entries in use, and the table at most half full */
    cmp     x9, x22
    b.lo    8f
    ldr     x9, [x20, #DbRoom_roots]
    ldr     x10, [x19, #Db_blocks]
    lsl     x10, x10, #1
    cmp     x9, x10
    b.lo    8f
    add     x0, x21, #8
    ldr     x1, [sp, #L]
    sub     x1, x1, #8
    bl      lantern_zero
    ldp     x9, x10, [x19, #Db_first_slot]
    stp     x9, x10, [x21, #Db_first_slot]
    mov     x0, x21
    mov     x1, x20
    bl      db_layout
    ldr     x0, [x21, #Db_slots]            /* the entries in use, then each root again */
    add     x0, x21, x0
    ldr     x1, [x19, #Db_slots]
    add     x1, x19, x1
    mov     x9, #DbSlot__mem
    mul     x2, x22, x9
    bl      lantern_copy
    mov     x0, x21
    bl      db_rehash
    mov     x0, #LANTERN_OK
9:  LEAVE 16
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_db_copy

/*
 * (db, record, offset): one record at an offset of its segment into the index; nothing changes on
 * a status. x19 db, x20 the record, x21 the offset, x22 the entry index, x23 the entry.
 */
FUNCTION lantern_db_add
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    ldr     x21, [x2]
    tst     x21, #7                         /* an offset of a multiple of 8, below 2^48 */
    b.ne    7f
    lsr     x9, x21, #48
    cbnz    x9, 7f
    ldr     x9, [x20, #DbRecord_length]     /* length at most DB_RECORD_MAX */
    mov     x10, #1
    lsl     x10, x10, #32
    cmp     x9, x10
    b.hi    7f
    add     x9, x9, #24                     /* its ByteList header: size 24 + length, offset 24 */
    ldr     x10, [x20, #DbRecord_bytes]
    cmp     x9, x10
    b.ne    7f
    ldr     x10, [x20, #(DbRecord_bytes + 8)]
    cmp     x10, #24
    b.ne    7f
    ldr     x22, [x20, #DbRecord_slot]      /* a slot from first_slot, in the room */
    ldr     x9, [x19, #Db_first_slot]
    subs    x22, x22, x9
    b.lo    7f
    ldr     x9, [x19, #(Db_slots + 8)]
    cmp     x22, x9
    b.hs    8f
    ldr     x23, [x19, #Db_slots]
    add     x23, x19, x23
    mov     x9, #DbSlot__mem
    madd    x23, x22, x9, x23
    ldr     x9, [x20, #DbRecord_kind]
    cmp     x9, #DB_BLOCK
    b.eq    1f
    cmp     x9, #DB_BLOB_SIDECAR
    ccmp    x9, #DB_COLUMN_SIDECAR, #4, ne
    b.ne    7f
    ldr     x9, [x23, #DbSlot_block]        /* a sidecar: of a slot with a block, an index below DB_SIDECAR_INDICES */
    cbz     x9, 7f
    ldr     x11, [x20, #DbRecord_index]
    cmp     x11, #DB_SIDECAR_INDICES
    b.hs    7f
    ldr     x12, [x20, #DbRecord_length]    /* its size: 64 + length rounded up to 8 */
    add     x12, x12, #(DbRecord__mem + 7)
    and     x12, x12, #~7
    ldr     x9, [x23, #DbSlot_sidecars]
    cbz     x9, 2f
    ldr     x10, [x23, #DbSlot_sidecar_end] /* after the slot's sidecars, of their size, with a higher index */
    cmp     x10, x21
    b.ne    7f
    sub     x10, x10, x9
    add     x10, x10, #1                    /* the bytes of the slot's sidecars */
    ldr     x13, [x23, #DbSlot_sidecar_count]
    mul     x13, x13, x12
    cmp     x13, x10
    b.ne    7f
    ldr     x10, [x23, #DbSlot_sidecar_last]
    cmp     x11, x10
    b.ls    7f
    b       3f
2:  add     x9, x21, #1
    str     x9, [x23, #DbSlot_sidecars]
3:  ldr     x9, [x23, #DbSlot_sidecar_count]
    add     x9, x9, #1
    str     x9, [x23, #DbSlot_sidecar_count]
    add     x9, x12, x21
    str     x9, [x23, #DbSlot_sidecar_end]
    str     x11, [x23, #DbSlot_sidecar_last]
    lsr     x9, x11, #3                     /* its bit in indices */
    add     x9, x9, #DbSlot_indices
    ldrb    w10, [x23, x9]
    and     x13, x11, #7
    mov     x14, #1
    lsl     x14, x14, x13
    orr     x10, x10, x14
    strb    w10, [x23, x9]
    b       9f
1:  ldr     x9, [x23, #DbSlot_block]        /* a block: none in its slot, its root in no other */
    cbnz    x9, 7f
    mov     x0, x19
    add     x1, x20, #DbRecord_root
    bl      db_find
    cmn     x0, #1
    b.ne    7f
    ldr     x9, [x19, #Db_blocks]           /* the table at most half full */
    add     x9, x9, #1
    lsl     x9, x9, #1
    ldr     x10, [x19, #(Db_roots + 8)]
    cmp     x9, x10
    b.hi    8f
    add     x9, x20, #DbRecord_root
    COPY32  x23, x9
    add     x9, x21, #1
    str     x9, [x23, #DbSlot_block]
    mov     x0, x19
    add     x1, x20, #DbRecord_root
    add     x2, x22, #1
    bl      db_insert
    ldr     x9, [x19, #Db_blocks]
    add     x9, x9, #1
    str     x9, [x19, #Db_blocks]
    ldr     x9, [x20, #DbRecord_slot]       /* end_slot past it */
    add     x9, x9, #1
    ldr     x10, [x19, #Db_end_slot]
    cmp     x9, x10
    csel    x9, x9, x10, hi
    str     x9, [x19, #Db_end_slot]
9:  mov     x0, #LANTERN_OK
    LEAVE 0
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
7:  mov     x0, #LANTERN_INVALID_RECORD
    LEAVE 0
END_FUNCTION lantern_db_add

/*
 * (db, segment, sidecars, bytes, valid): each whole record of a segment's bytes into the index,
 * until one does not fit or is rejected. x19 db, x20 the segment, x21 the sidecars flag, x22 the
 * bytes, x23 their count, x24 valid, x25 the position, x26 the segment's first slot, x27 a record.
 * Locals: L the record's size, L+8 its offset.
 */
FUNCTION lantern_db_scan
    ENTER 16
    mov     x19, x0
    ldr     x20, [x1]
    ldr     x21, [x2]
    ldp     x9, x10, [x3, #8]
    add     x22, x3, x9
    mov     x23, x10
    mov     x24, x4
    mov     x25, #0
    MOVQ    x9, DB_SEGMENT_SLOTS
    umulh   x10, x20, x9
    cbnz    x10, 9f
    mul     x26, x20, x9
1:  sub     x9, x23, x25                    /* its header and its size inside the bytes */
    cmp     x9, #DbRecord__mem
    b.lo    9f
    add     x27, x22, x25
    ldr     x10, [x27, #DbRecord_length]
    mov     x11, #1
    lsl     x11, x11, #32
    cmp     x10, x11
    b.hi    9f
    add     x10, x10, #(DbRecord__mem + 7)
    and     x10, x10, #~7
    cmp     x10, x9
    b.hi    9f
    str     x10, [sp, #L]
    ldr     x11, [x27, #DbRecord_slot]      /* a slot of the segment */
    subs    x11, x11, x26
    b.lo    9f
    MOVQ    x12, DB_SEGMENT_SLOTS
    cmp     x11, x12
    b.hs    9f
    ldr     x11, [x27, #DbRecord_kind]      /* a block in a block segment, else a sidecar */
    cmp     x11, #DB_BLOCK
    cset    x11, ne
    cmp     x11, x21
    b.ne    9f
    str     x25, [sp, #(L + 8)]
    mov     x0, x19
    mov     x1, x27
    add     x2, sp, #(L + 8)
    bl      lantern_db_add
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    8f
    cbnz    x0, 9f
    ldr     x10, [sp, #L]
    add     x25, x25, x10
    b       1b
8:  str     x25, [x24]
    mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
9:  str     x25, [x24]
    mov     x0, #LANTERN_OK
    LEAVE 16
END_FUNCTION lantern_db_scan

/* (db, root, slot): the slot of the root's block, or 2^64 - 1. */
FUNCTION lantern_db_find_root
    FRAME 0
    mov     x6, x0
    mov     x7, x2
    bl      db_find
    cmn     x0, #1
    b.eq    1f
    ldr     x9, [x6, #Db_first_slot]
    add     x0, x0, x9
1:  str     x0, [x7]
    mov     x0, #LANTERN_OK
    UNFRAME 0
END_FUNCTION lantern_db_find_root

/*
 * (db, slot): first_slot the slot, at most end_slot; the kept entries to the front, the root table
 * again. A slot not after first_slot changes nothing. x19 db, x20 the new first slot, x21 first_slot,
 * x22 end_slot, x23 the entries dropped, x24 those kept, x25 the entries.
 */
FUNCTION lantern_db_prune
    ENTER 0
    mov     x19, x0
    ldr     x20, [x1]
    ldp     x21, x22, [x19, #Db_first_slot]
    cmp     x20, x21
    b.ls    9f
    cmp     x20, x22
    csel    x20, x20, x22, lo
    sub     x23, x20, x21
    sub     x24, x22, x20
    ldr     x25, [x19, #Db_slots]
    add     x25, x19, x25
    mov     x9, #DbSlot__mem
    mov     x0, x25
    madd    x1, x23, x9, x25
    mul     x2, x24, x9
    bl      lantern_copy
    mov     x9, #DbSlot__mem
    madd    x0, x24, x9, x25
    mul     x1, x23, x9
    bl      lantern_zero
    str     x20, [x19, #Db_first_slot]
    mov     x0, x19
    bl      db_rehash
9:  mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_db_prune

/*
 * (db, slot): the sidecars of the slots from first_slot below the slot and end_slot leave the index:
 * each DbSlot keeps its root and block, and its sidecar fields become 0. x19 db, x20 an entry, x21
 * the entries left.
 */
FUNCTION lantern_db_drop_sidecars
    ENTER 0
    mov     x19, x0
    ldr     x9, [x1]
    ldp     x10, x11, [x19, #Db_first_slot]
    cmp     x9, x11
    csel    x9, x9, x11, lo
    cmp     x9, x10
    b.ls    9f
    sub     x21, x9, x10
    ldr     x20, [x19, #Db_slots]
    add     x20, x19, x20
1:  cbz     x21, 9f
    add     x0, x20, #DbSlot_sidecars
    mov     x1, #(DbSlot__mem - DbSlot_sidecars)
    bl      lantern_zero
    add     x20, x20, #DbSlot__mem
    sub     x21, x21, #1
    b       1b
9:  mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_db_drop_sidecars
