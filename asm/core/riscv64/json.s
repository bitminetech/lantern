/*
 * The JSON of SSZ values, RISC-V: in the common object. Requirements: docs/reference/beacon-api.md,
 * lantern_json_encode.
 *
 * s1 the type, s2 the value, s3 the cursor, s4 out, s5 where the next byte goes, s6 the end of
 * out's room, s7 the type's nodes, s8 its fields, s9 the names after the fields, s10 the top level
 * of the cursor.
 */

/*
 * The bytes a0 .. a0 + a1 of a token go out from the cursor's done bytes on, while out has room:
 * a0 = 0 when the token is whole (done 0), else 1 (done counts the bytes written). Uses t0, t1.
 */
LOCAL_FUNCTION json_put
    UNWIND_END_PROLOGUE
    ld      t0, JsonCursor_done(s3)
1:  bgeu    t0, a1, 2f
    bgeu    s5, s6, 3f
    add     t1, a0, t0
    lbu     t1, 0(t1)
    sb      t1, 0(s5)
    addi    s5, s5, 1
    addi    t0, t0, 1
    j       1b
2:  sd      zero, JsonCursor_done(s3)
    li      a0, 0
    ret
3:  sd      t0, JsonCursor_done(s3)
    li      a0, 1
    ret
END_FUNCTION json_put

/*
 * The hex token of the byte or bit string of the level s10 (kind a0): its bytes from the cursor's
 * done bytes on, while out has room: a0 = 0 when whole, else 1. Uses t0-t6, a1-a5.
 */
LOCAL_FUNCTION json_hex
    UNWIND_END_PROLOGUE
    ld      a2, JsonLevel_base(s10)         # the bytes
    add     a2, s2, a2
    ld      a3, JsonLevel_count(s10)        # the bit list's bits
    mv      a4, a3                          # the SSZ bytes
    li      t0, SSZ_KIND_BIT_VECTOR
    bne     a0, t0, 1f
    addi    a4, a3, 7
    srli    a4, a4, 3
1:  li      t0, SSZ_KIND_BIT_LIST
    bne     a0, t0, 2f
    srli    a4, a3, 3
    addi    a4, a4, 1
2:  slli    a5, a4, 1                       # the token's bytes: 4 + 2 per byte
    addi    a5, a5, 4
    ld      t0, JsonCursor_done(s3)
    ADDRESS a1, api_hex
3:  bgeu    t0, a5, 8f
    bgeu    s5, s6, 9f
    li      t1, 0x22                        # " at either end, then 0x
    beqz    t0, 7f
    addi    t2, a5, -1
    beq     t0, t2, 7f
    li      t1, 0x30
    li      t2, 1
    beq     t0, t2, 7f
    li      t1, 0x78
    li      t2, 2
    beq     t0, t2, 7f
    addi    t2, t0, -3                      # a digit: byte t2 / 2
    srli    t3, t2, 1
    li      t4, 0
    li      t5, SSZ_KIND_BIT_LIST
    bne     a0, t5, 5f
    addi    t5, a3, 7                       # a bit list: its bytes, then the delimiter bit
    srli    t5, t5, 3
    bgeu    t3, t5, 4f
    add     t5, a2, t3
    lbu     t4, 0(t5)
4:  srli    t5, a3, 3
    bne     t3, t5, 6f
    andi    t5, a3, 7
    li      t6, 1
    sll     t6, t6, t5
    or      t4, t4, t6
    j       6f
5:  add     t5, a2, t3
    lbu     t4, 0(t5)
6:  andi    t5, t2, 1
    bnez    t5, 61f
    srli    t4, t4, 4
61: andi    t4, t4, 15
    add     t4, a1, t4
    lbu     t1, 0(t4)
7:  sb      t1, 0(s5)
    addi    s5, s5, 1
    addi    t0, t0, 1
    j       3b
8:  sd      zero, JsonCursor_done(s3)
    li      a0, 0
    ret
9:  sd      t0, JsonCursor_done(s3)
    li      a0, 1
    ret
END_FUNCTION json_hex

/*
 * The token of the uint or Boolean of the level s10 (kind a0): a0 = 0 when whole, else 1.
 * Locals: the number's 32-bit words at 0, the text from its end at 120.
 */
LOCAL_FUNCTION json_number
    FRAME 128
    ld      a2, JsonLevel_base(s10)
    add     a2, s2, a2
    li      t0, SSZ_KIND_BOOLEAN
    bne     a0, t0, 1f
    lbu     t0, 0(a2)
    ADDRESS a0, api_true
    li      a1, api_true_len
    bnez    t0, 9f
    ADDRESS a0, api_false
    li      a1, api_false_len
    j       9f
1:  addi    t2, sp, 120                     # the closing quote, then the digits backwards
    li      t0, 0x22
    addi    t2, t2, -1
    sb      t0, 0(t2)
    ld      a3, JsonLevel_count(s10)        # the width
    li      t0, 8
    bgtu    a3, t0, 4f
    ld      a4, 0(a2)                       # up to 8 bytes: one u64
    beq     a3, t0, 2f
    andi    a4, a4, 0xff
2:  li      t3, 10
3:  remu    t4, a4, t3
    divu    a4, a4, t3
    addi    t4, t4, 0x30
    addi    t2, t2, -1
    sb      t4, 0(t2)
    bnez    a4, 3b
    j       8f
4:  ld      t0, 0(a2)                       # 32 bytes: eight 32-bit words at 0
    sd      t0, 0(sp)
    ld      t0, 8(a2)
    sd      t0, 8(sp)
    ld      t0, 16(a2)
    sd      t0, 16(sp)
    ld      t0, 24(a2)
    sd      t0, 24(sp)
5:  li      t4, 0                           # divide by 10, from the top word down
    li      t5, 28
    li      t6, 0                           # any word not zero
    li      t3, 10
6:  add     t0, sp, t5
    lwu     t1, 0(t0)
    slli    t4, t4, 32
    or      t1, t1, t4
    divu    a5, t1, t3
    remu    t4, t1, t3
    sw      a5, 0(t0)
    or      t6, t6, a5
    addi    t5, t5, -4
    bgez    t5, 6b
    addi    t4, t4, 0x30
    addi    t2, t2, -1
    sb      t4, 0(t2)
    bnez    t6, 5b
8:  li      t0, 0x22
    addi    t2, t2, -1
    sb      t0, 0(t2)
    mv      a0, t2
    addi    a1, sp, 120
    sub     a1, a1, t2
9:  call    json_put
    UNFRAME 128
END_FUNCTION json_number

/*
 * The level s10 for the type node a0 whose storage is at offset a1 of the value: inline when a2
 * is 2^64 - 1 and the type is of fixed size; a value of its own with its size first when a2 is
 * 2^64 - 1 and the type is of variable size; else a PartRef at a1 whose offset counts from a2.
 * Uses t0-t4.
 */
LOCAL_FUNCTION json_open
    UNWIND_END_PROLOGUE
    li      t0, SSZ_NODE_STRIDE
    mul     t0, a0, t0
    add     t0, s7, t0
    sd      a0, JsonLevel_node(s10)
    sd      zero, JsonLevel_step(s10)
    sd      zero, JsonLevel_item(s10)
    ld      t1, SSZ_NODE_LENGTH(t0)
    sd      t1, JsonLevel_count(s10)        # the width, the length, the field count
    sd      a1, JsonLevel_base(s10)
    ld      t1, SSZ_NODE_SSZ_SIZE(t0)
    bnez    t1, 9f                          # fixed size: inline
    ld      t1, SSZ_NODE_KIND(t0)
    li      t2, SSZ_KIND_CONTAINER
    bne     t1, t2, 2f
    li      t2, -1                          # a container: its own value, or the part of a PartRef
    beq     a2, t2, 9f
    add     t3, s2, a1
    ld      t3, 0(t3)
    add     t3, a2, t3
    sd      t3, JsonLevel_base(s10)
    j       9f
2:  add     t3, s2, a1                      # a list or bit list or byte list: its PartRef
    mv      t4, a2
    li      t2, -1
    bne     a2, t2, 3f
    mv      t4, a1                          # its own value: the PartRef at byte 8
    addi    t3, t3, 8
3:  ld      t1, 0(t3)
    ld      t2, 8(t3)
    add     t1, t4, t1
    sd      t2, JsonLevel_count(s10)
    sd      t1, JsonLevel_base(s10)
    sd      t1, JsonLevel_next(s10)
9:  ret
END_FUNCTION json_open

/* The next item of the compound level s10 at index item, one level deeper. */
LOCAL_FUNCTION json_child
    FRAME 0
    ld      t0, JsonLevel_node(s10)
    li      t1, SSZ_NODE_STRIDE
    mul     t0, t0, t1
    add     t0, s7, t0
    ld      t1, SSZ_NODE_KIND(t0)
    ld      t2, JsonLevel_item(s10)
    ld      t3, JsonLevel_base(s10)
    li      t4, SSZ_KIND_CONTAINER
    bne     t1, t4, 2f
    ld      t4, SSZ_NODE_ELEMENT(t0)        # a field: inline, or a PartRef from the container
    add     t4, t4, t2
    slli    t4, t4, 5
    add     t4, s8, t4
    ld      a0, SSZ_FIELD_NODE(t4)
    ld      a1, SSZ_FIELD_MEM_OFFSET(t4)
    add     a1, t3, a1
    ld      t5, SSZ_FIELD_FLAGS(t4)
    andi    t5, t5, SSZ_FIELD_VARIABLE
    li      a2, -1
    beqz    t5, 5f
    mv      a2, t3
    j       5f
2:  ld      a0, SSZ_NODE_ELEMENT(t0)        # an item: at its stride, or the next value of its own
    li      t4, SSZ_NODE_STRIDE
    mul     t4, a0, t4
    add     t4, s7, t4
    li      a2, -1
    ld      t5, SSZ_NODE_SSZ_SIZE(t4)
    beqz    t5, 3f
    ld      t5, SSZ_NODE_MEM_SIZE(t4)
    mul     a1, t2, t5
    add     a1, t3, a1
    j       5f
3:  ld      a1, JsonLevel_next(s10)
    add     t5, s2, a1
    ld      t5, 0(t5)
    add     t5, a1, t5
    sd      t5, JsonLevel_next(s10)
5:  ld      t0, JsonCursor_depth(s3)
    addi    t0, t0, 1
    sd      t0, JsonCursor_depth(s3)
    addi    s10, s10, JSON_LEVEL_SIZE
    call    json_open
    UNFRAME 0
END_FUNCTION json_child

/* (type, value, cursor, out): docs/reference/beacon-api.md. Locals: L a token of punctuation or a name, L+40 the kind. */
FUNCTION lantern_json_encode
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      t0, 8(s4)                       # out: its offset, its count, its room
    ld      t1, 16(s4)
    add     s5, s4, t0
    add     s5, s5, t1
    ld      t0, 0(s4)
    add     s6, s4, t0
    bgeu    s5, s6, 97f
    ld      t0, JsonCursor_whole(s3)
    bnez    t0, 90f
    ld      t0, 8(s1)                       # the nodes, the fields, the names after them
    add     s7, s1, t0
    ld      t0, 24(s1)
    add     s8, s1, t0
    ld      t0, 32(s1)
    slli    t0, t0, 5
    add     s9, s8, t0
    ld      t0, JsonCursor_depth(s3)
    bnez    t0, 1f
    li      t0, 1                           # the root: inline, or a value of its own
    sd      t0, JsonCursor_depth(s3)
    sd      zero, JsonCursor_done(s3)
    addi    s10, s3, JsonCursor_levels
    ld      a0, 40(s1)
    li      a1, 0
    li      a2, -1
    call    json_open
1:  ld      t0, JsonCursor_depth(s3)
    addi    t0, t0, -1
    li      t1, JSON_LEVEL_SIZE
    mul     t0, t0, t1
    addi    s10, s3, JsonCursor_levels
    add     s10, s10, t0
10: ld      t0, JsonLevel_node(s10)         # the top level
    li      t1, SSZ_NODE_STRIDE
    mul     t0, t0, t1
    add     t0, s7, t0
    ld      a0, SSZ_NODE_KIND(t0)
    li      t1, SSZ_KIND_BOOLEAN
    bgtu    a0, t1, 11f
    call    json_number
    bnez    a0, 91f
    j       50f
11: li      t1, SSZ_KIND_VECTOR
    bgeu    a0, t1, 20f
    call    json_hex                        # a byte or bit string
    bnez    a0, 91f
    j       50f
20: sd      a0, (L + 40)(sp)                # a list, vector or container
    ld      t0, JsonLevel_step(s10)
    li      t2, 0x5b                        # [ ] or { }
    li      t3, 0x5d
    li      t1, SSZ_KIND_CONTAINER
    bne     a0, t1, 21f
    li      t2, 0x7b
    li      t3, 0x7d
21: bnez    t0, 22f
    sb      t2, (L + 0)(sp)                 # step 0: the opening
    addi    a0, sp, L
    li      a1, 1
    call    json_put
    bnez    a0, 91f
    li      t0, 1
    sd      t0, JsonLevel_step(s10)
    j       10b
22: li      t1, 1
    bne     t0, t1, 25f
    ld      t4, JsonLevel_item(s10)         # step 1: the closing after the last item, or ,
    ld      t5, JsonLevel_count(s10)
    bltu    t4, t5, 23f
    sb      t3, (L + 0)(sp)
    addi    a0, sp, L
    li      a1, 1
    call    json_put
    bnez    a0, 91f
    j       50f
23: beqz    t4, 24f
    li      t1, 0x2c
    sb      t1, (L + 0)(sp)
    addi    a0, sp, L
    li      a1, 1
    call    json_put
    bnez    a0, 91f
24: li      t0, 2
    sd      t0, JsonLevel_step(s10)
    j       10b
25: ld      t0, (L + 40)(sp)                # step 2: a field's "name":, then the item, deeper
    li      t1, SSZ_KIND_CONTAINER
    bne     t0, t1, 27f
    ld      t0, JsonLevel_node(s10)
    li      t1, SSZ_NODE_STRIDE
    mul     t0, t0, t1
    add     t0, s7, t0
    ld      t0, SSZ_NODE_ELEMENT(t0)
    ld      t1, JsonLevel_item(s10)
    add     t0, t0, t1
    slli    t0, t0, 5
    add     t0, s9, t0
    li      t1, 0x22
    sb      t1, (L + 0)(sp)
    li      t2, 0
26: li      t3, 32
    bgeu    t2, t3, 261f
    add     t3, t0, t2
    lbu     t3, 0(t3)
    beqz    t3, 261f
    add     t4, sp, t2
    sb      t3, (L + 1)(t4)
    addi    t2, t2, 1
    j       26b
261: add    t4, sp, t2
    li      t3, 0x22
    sb      t3, (L + 1)(t4)
    li      t3, 0x3a
    sb      t3, (L + 2)(t4)
    addi    a0, sp, L
    addi    a1, t2, 3
    call    json_put
    bnez    a0, 91f
27: li      t0, 3
    sd      t0, JsonLevel_step(s10)
    ld      t0, JsonCursor_depth(s3)
    li      t1, JSON_LEVELS
    bgeu    t0, t1, 97f
    call    json_child
    j       10b
50: ld      t0, JsonCursor_depth(s3)        # the level is whole: up one, the next item there
    addi    t0, t0, -1
    sd      t0, JsonCursor_depth(s3)
    beqz    t0, 80f
    addi    s10, s10, -JSON_LEVEL_SIZE
    ld      t1, JsonLevel_item(s10)
    addi    t1, t1, 1
    sd      t1, JsonLevel_item(s10)
    li      t1, 1
    sd      t1, JsonLevel_step(s10)
    j       10b
80: li      t0, 1                           # the JSON is whole
    sd      t0, JsonCursor_whole(s3)
90: ld      t0, 8(s4)
    add     t0, s4, t0
    sub     t0, s5, t0
    sd      t0, 16(s4)
    li      a0, LANTERN_OK
    LEAVE 48
91: ld      t0, 8(s4)
    add     t0, s4, t0
    sub     t0, s5, t0
    sd      t0, 16(s4)
    li      a0, LANTERN_JSON_MORE
    LEAVE 48
97: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
END_FUNCTION lantern_json_encode
