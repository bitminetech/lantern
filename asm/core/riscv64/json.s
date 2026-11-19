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

/*
 * ---------------------------------------------------------------- lantern_json_decode
 *
 * s1 the JSON's first byte, s2 its end, s3 the field tables in scratch (512 bytes a level), s4
 * where the encoding goes, s5 the bytes of the encoding so far, s6 1 when the bytes are written (0
 * counts them), s7 the type's nodes, s8 its fields, s9 the names after the fields, s10 the
 * JsonFault, whose path the levels fill as they go down.
 */

/* a0 = the first byte at or after a0 that is no white space. Uses t0. */
LOCAL_FUNCTION jd_ws
    UNWIND_END_PROLOGUE
1:  bgeu    a0, s2, 9f
    lbu     t0, 0(a0)
    addi    t0, t0, -0x20
    beqz    t0, 2f
    addi    t0, t0, 0x20 - 0x09
    beqz    t0, 2f
    addi    t0, t0, 0x09 - 0x0a
    beqz    t0, 2f
    addi    t0, t0, 0x0a - 0x0d
    bnez    t0, 9f
2:  addi    a0, a0, 1
    j       1b
9:  ret
END_FUNCTION jd_ws

/* The fault a0 at the byte a1 (the end when past it), at depth a2: a1 = 1. Uses t0. */
LOCAL_FUNCTION jd_fault
    UNWIND_END_PROLOGUE
    bleu    a1, s2, 1f
    mv      a1, s2
1:  sub     t0, a1, s1
    sd      a0, JsonFault_kind(s10)
    sd      t0, JsonFault_offset(s10)
    sd      a2, JsonFault_depth(s10)
    li      a1, 1
    ret
END_FUNCTION jd_fault

/*
 * The string at a0 (its quote): a0 = after its closing quote, a3 its first byte, a4 its end,
 * a1 = 0; a \ or a byte below 0x20, or the end, is a fault at depth a2 (a1 = 1). Uses t0, t1.
 */
LOCAL_FUNCTION jd_string
    FRAME 0
    addi    a3, a0, 1
    mv      a4, a3
1:  bgeu    a4, s2, 8f
    lbu     t0, 0(a4)
    li      t1, 0x22
    beq     t0, t1, 2f
    li      t1, 0x5c
    beq     t0, t1, 8f
    li      t1, 0x20
    bltu    t0, t1, 8f
    addi    a4, a4, 1
    j       1b
2:  addi    a0, a4, 1
    li      a1, 0
    UNFRAME 0
8:  li      a0, JSON_FAULT_SYNTAX
    mv      a1, a4
    call    jd_fault
    UNFRAME 0
END_FUNCTION jd_string

/* dst = 1 when the byte at reg is a decimal digit, below the end; else 0. Uses t0. */
.macro JD_DIGIT dst, at
    li      \dst, 0
    bgeu    \at, s2, 77f
    lbu     t0, 0(\at)
    addi    t0, t0, -0x30
    sltiu   \dst, t0, 10
77:
.endm

/* The number at a0 (RFC 8259 section 6): a0 = after it, a1 = 0; else a fault at depth a2. Uses t0, t1. */
LOCAL_FUNCTION jd_number
    FRAME 0
    bgeu    a0, s2, 8f
    lbu     t0, 0(a0)
    li      t1, 0x2d                        # -
    bne     t0, t1, 1f
    addi    a0, a0, 1
1:  bgeu    a0, s2, 8f
    lbu     t0, 0(a0)
    li      t1, 0x30
    bne     t0, t1, 2f
    addi    a0, a0, 1
    j       3f
2:  addi    t0, t0, -0x31
    li      t1, 8
    bgtu    t0, t1, 8f
21: addi    a0, a0, 1
    JD_DIGIT t1, a0
    bnez    t1, 21b
3:  bgeu    a0, s2, 9f                      # a fraction
    lbu     t0, 0(a0)
    li      t1, 0x2e
    bne     t0, t1, 4f
    addi    a0, a0, 1
    JD_DIGIT t1, a0
    beqz    t1, 8f
31: addi    a0, a0, 1
    JD_DIGIT t1, a0
    bnez    t1, 31b
4:  bgeu    a0, s2, 9f                      # an exponent
    lbu     t0, 0(a0)
    ori     t0, t0, 0x20
    li      t1, 0x65
    bne     t0, t1, 9f
    addi    a0, a0, 1
    bgeu    a0, s2, 8f
    lbu     t0, 0(a0)
    li      t1, 0x2b
    beq     t0, t1, 40f
    li      t1, 0x2d
    bne     t0, t1, 41f
40: addi    a0, a0, 1
41: JD_DIGIT t1, a0
    beqz    t1, 8f
42: addi    a0, a0, 1
    JD_DIGIT t1, a0
    bnez    t1, 42b
9:  li      a1, 0
    UNFRAME 0
8:  mv      a1, a0
    li      a0, JSON_FAULT_SYNTAX
    call    jd_fault
    UNFRAME 0
END_FUNCTION jd_number

/* a1 = 1 when the a2 bytes of text at a1 start at a0 below the end, else 0. Uses t0-t3. */
LOCAL_FUNCTION jd_literal
    UNWIND_END_PROLOGUE
    add     t0, a0, a2
    bgtu    t0, s2, 8f
    li      t0, 0
1:  bgeu    t0, a2, 9f
    add     t1, a0, t0
    lbu     t1, 0(t1)
    add     t2, a1, t0
    lbu     t2, 0(t2)
    bne     t1, t2, 8f
    addi    t0, t0, 1
    j       1b
9:  li      a1, 1
    ret
8:  li      a1, 0
    ret
END_FUNCTION jd_literal

/* '"name":' at a0, in a skipped object: a0 = its value's first byte, a1 = 0; else a fault at depth a2. Locals: a2. */
LOCAL_FUNCTION jd_key
    FRAME 16
    sd      a2, 0(sp)
    bgeu    a0, s2, 8f
    lbu     t0, 0(a0)
    li      t1, 0x22
    bne     t0, t1, 8f
    call    jd_string
    bnez    a1, 9f
    call    jd_ws
    bgeu    a0, s2, 8f
    lbu     t0, 0(a0)
    li      t1, 0x3a
    bne     t0, t1, 8f
    addi    a0, a0, 1
    li      a1, 0
    UNFRAME 16
8:  mv      a1, a0
    li      a0, JSON_FAULT_SYNTAX
    ld      a2, 0(sp)
    call    jd_fault
9:  UNFRAME 16
END_FUNCTION jd_key

/*
 * The value at a0, skipped with only the checks of the text, faults at depth a2: a0 = after it,
 * a1 = 0. Locals: the depth, the nesting (a bit each, 1 an object), its count.
 */
LOCAL_FUNCTION jd_skip
    FRAME 32
    sd      a2, 0(sp)
    sd      zero, 8(sp)
    sd      zero, 16(sp)
1:  call    jd_ws                           # a value
    ld      a2, 0(sp)
    bgeu    a0, s2, 80f
    lbu     t0, 0(a0)
    li      t1, 0x22
    bne     t0, t1, 2f
    call    jd_string
    bnez    a1, 99f
    j       10f
2:  li      t1, 0x2d
    beq     t0, t1, 21f
    addi    t1, t0, -0x30
    li      t2, 9
    bgtu    t1, t2, 3f
21: call    jd_number
    bnez    a1, 99f
    j       10f
3:  ADDRESS a1, api_true
    li      a2, 4
    call    jd_literal
    beqz    a1, 31f
    addi    a0, a0, 4
    j       10f
31: ADDRESS a1, api_false
    li      a2, 5
    call    jd_literal
    beqz    a1, 32f
    addi    a0, a0, 5
    j       10f
32: ADDRESS a1, jd_null
    li      a2, 4
    call    jd_literal
    beqz    a1, 33f
    addi    a0, a0, 4
    j       10f
33: ld      a2, 0(sp)
    lbu     t0, 0(a0)
    li      t1, 0x5b
    beq     t0, t1, 331f
    li      t1, 0x7b
    bne     t0, t1, 80f
331: ld     t2, 16(sp)                      # [ or {: one level more, at most 64
    li      t3, 64
    bgeu    t2, t3, 80f
    addi    t2, t2, 1
    sd      t2, 16(sp)
    ld      t2, 8(sp)
    slli    t2, t2, 1
    li      t1, 0x7b
    bne     t0, t1, 332f
    ori     t2, t2, 1
332: sd     t2, 8(sp)
    addi    a0, a0, 1
    call    jd_ws
    ld      a2, 0(sp)
    bgeu    a0, s2, 80f
    lbu     t0, 0(a0)
    ld      t2, 8(sp)
    andi    t3, t2, 1
    li      t1, 0x5d
    beqz    t3, 333f
    li      t1, 0x7d
333: bne    t0, t1, 34f
    addi    a0, a0, 1                       # empty: closed at once
    j       12f
34: beqz    t3, 1b                          # an array: its first item; an object: its first key
    call    jd_key
    bnez    a1, 99f
    j       1b
10: ld      t2, 16(sp)                      # after a value: done at the top, else , or the close
    beqz    t2, 98f
    call    jd_ws
    ld      a2, 0(sp)
    bgeu    a0, s2, 80f
    lbu     t0, 0(a0)
    ld      t2, 8(sp)
    andi    t3, t2, 1
    li      t1, 0x2c
    bne     t0, t1, 11f
    addi    a0, a0, 1
    beqz    t3, 1b
    call    jd_ws
    ld      a2, 0(sp)
    call    jd_key
    bnez    a1, 99f
    j       1b
11: li      t1, 0x5d
    beqz    t3, 111f
    li      t1, 0x7d
111: bne    t0, t1, 80f
    addi    a0, a0, 1
12: ld      t2, 8(sp)                       # one level up
    srli    t2, t2, 1
    sd      t2, 8(sp)
    ld      t2, 16(sp)
    addi    t2, t2, -1
    sd      t2, 16(sp)
    j       10b
80: mv      a1, a0
    li      a0, JSON_FAULT_SYNTAX
    call    jd_fault
    j       99f
98: li      a1, 0
99: UNFRAME 32
END_FUNCTION jd_skip

/* The a1 bytes at a0 join the encoding, written when s6 is 1. Uses t0, t1. */
LOCAL_FUNCTION jd_out
    UNWIND_END_PROLOGUE
    beqz    s6, 2f
    add     t0, s4, s5
1:  beqz    a1, 3f
    lbu     t1, 0(a0)
    sb      t1, 0(t0)
    addi    a0, a0, 1
    addi    t0, t0, 1
    addi    a1, a1, -1
    addi    s5, s5, 1
    j       1b
2:  add     s5, s5, a1
3:  ret
END_FUNCTION jd_out

/* The 4-byte offset a0 at byte a1 of the encoding, when s6 is 1. Uses t0. */
LOCAL_FUNCTION jd_offset
    UNWIND_END_PROLOGUE
    beqz    s6, 9f
    add     t0, s4, a1
    sw      a0, 0(t0)
9:  ret
END_FUNCTION jd_offset

/* a0 = the value of the hex digit in a0, or 16 for another byte. Uses t0. */
LOCAL_FUNCTION jd_hexdigit
    UNWIND_END_PROLOGUE
    addi    t0, a0, -0x30
    sltiu   t1, t0, 10
    bnez    t1, 1f
    ori     t0, a0, 0x20
    addi    t0, t0, -0x61
    sltiu   t1, t0, 6
    beqz    t1, 2f
    addi    t0, t0, 10
1:  mv      a0, t0
    ret
2:  li      a0, 16
    ret
END_FUNCTION jd_hexdigit

/*
 * The value of the type node a0 at a1, at depth a2: its encoding joins at s5; a0 = after it,
 * a1 = 0, else a fault (a1 = 1). Locals: 0 node, 8 depth, 16 the value's first byte, 24 the end,
 * 32 an index, 40 the count, 48 the encoding's start, 56 its tail, 64 the field table, 72 the text
 * cursor or a name's start, 80 the kind's node entry, 88 a string's end, 96 an element node, 104
 * an item's size, 112 the bytes of a number (32), 144 a string's content start, 152 its end.
 */
LOCAL_FUNCTION jd_value
    FRAME 160
    sd      a0, 0(sp)
    sd      a2, 8(sp)
    mv      a0, a1
    call    jd_ws
    sd      a0, 16(sp)
    ld      a2, 8(sp)
    bgeu    a0, s2, 880f
    ld      t0, 0(sp)
    li      t1, SSZ_NODE_STRIDE
    mul     t0, t0, t1
    add     t0, s7, t0
    sd      t0, 80(sp)
    ld      t1, SSZ_NODE_KIND(t0)
    lbu     t2, 0(a0)
    li      t3, SSZ_KIND_CONTAINER
    beq     t1, t3, 100f
    li      t3, SSZ_KIND_VECTOR
    bgeu    t1, t3, 200f
    li      t3, SSZ_KIND_BOOLEAN
    beq     t1, t3, 300f
    li      t3, 0x22                        # a uint, a byte or bit string: a string
    bne     t2, t3, 870f
    call    jd_string
    bnez    a1, 899f
    sd      a0, 24(sp)
    sd      a3, 144(sp)
    sd      a4, 152(sp)
    sub     a5, a4, a3                      # the content's bytes
    ld      t0, 80(sp)
    ld      t1, SSZ_NODE_KIND(t0)
    li      t2, SSZ_KIND_UINT
    bne     t1, t2, 400f
    beqz    a5, 860f                        # uint: 1 to 78 digits, below 2^(8 width)
    li      t2, 78
    bgtu    a5, t2, 860f
    sd      zero, 112(sp)
    sd      zero, 120(sp)
    sd      zero, 128(sp)
    sd      zero, 136(sp)
1:  bgeu    a3, a4, 3f
    lbu     t2, 0(a3)
    addi    a3, a3, 1
    addi    t2, t2, -0x30
    li      t3, 9
    bgtu    t2, t3, 860f
    li      t3, 0                           # the 256-bit number times 10, plus the digit
    mv      t4, t2
2:  slli    t5, t3, 3
    add     t5, sp, t5
    ld      t6, 112(t5)
    li      a6, 10
    mul     a7, t6, a6
    mulhu   t6, t6, a6
    add     a7, a7, t4
    sltu    t4, a7, t4
    add     t4, t6, t4
    sd      a7, 112(t5)
    addi    t3, t3, 1
    li      t5, 4
    bltu    t3, t5, 2b
    bnez    t4, 860f
    j       1b
3:  ld      t0, 80(sp)
    ld      t1, SSZ_NODE_LENGTH(t0)         # the width: bytes past it zero
    mv      t2, t1
4:  li      t3, 32
    bgeu    t2, t3, 5f
    add     t3, sp, t2
    lbu     t3, 112(t3)
    bnez    t3, 860f
    addi    t2, t2, 1
    j       4b
5:  addi    a0, sp, 112
    mv      a1, t1
    call    jd_out
    ld      a0, 24(sp)
    li      a1, 0
    UNFRAME 160
400: li     t2, 2                           # a byte or bit string: 0x and pairs of hex digits
    bltu    a5, t2, 850f
    lbu     t2, 0(a3)
    li      t3, 0x30
    bne     t2, t3, 850f
    lbu     t2, 1(a3)
    li      t3, 0x78
    bne     t2, t3, 850f
    andi    t2, a5, 1
    bnez    t2, 850f
    addi    a3, a3, 2                       # every digit hex
41: ld      a4, 152(sp)
    bgeu    a3, a4, 42f
    lbu     a0, 0(a3)
    addi    a3, a3, 1
    call    jd_hexdigit
    li      t2, 16
    bgeu    a0, t2, 850f
    j       41b
42: ld      a3, 144(sp)
    ld      a4, 152(sp)
    sub     a5, a4, a3
    addi    a5, a5, -2
    srli    a5, a5, 1                       # the bytes
    sd      a5, 40(sp)
    ld      t0, 80(sp)
    ld      t1, SSZ_NODE_KIND(t0)
    ld      t2, SSZ_NODE_LENGTH(t0)
    li      t3, SSZ_KIND_BYTE_VECTOR
    bne     t1, t3, 43f
    bne     a5, t2, 850f
    j       47f
43: li      t3, SSZ_KIND_BYTE_LIST
    bne     t1, t3, 44f
    bgtu    a5, t2, 850f
    j       47f
44: li      a5, 0                           # the last byte, for the bit kinds
    ld      t3, 40(sp)
    beqz    t3, 45f
    lbu     a0, -2(a4)
    call    jd_hexdigit
    slli    a5, a0, 4
    ld      a4, 152(sp)
    lbu     a0, -1(a4)
    call    jd_hexdigit
    or      a5, a5, a0
45: ld      t0, 80(sp)
    ld      t1, SSZ_NODE_KIND(t0)
    ld      t2, SSZ_NODE_LENGTH(t0)
    ld      t4, 40(sp)
    li      t3, SSZ_KIND_BIT_VECTOR
    bne     t1, t3, 46f
    addi    t3, t2, 7                       # a bit vector: its bytes, the bits past N zero
    srli    t3, t3, 3
    bne     t4, t3, 850f
    andi    t3, t2, 7
    beqz    t3, 47f
    srl     a5, a5, t3
    bnez    a5, 850f
    j       47f
46: beqz    t4, 850f                        # a bit list: the last byte not zero, at most N bits
    beqz    a5, 850f
    li      t3, -1                          # the delimiter's bit
461: addi   t3, t3, 1
    srl     t5, a5, t3
    li      t6, 1
    bne     t5, t6, 461b
    addi    t4, t4, -1
    slli    t4, t4, 3
    add     t3, t3, t4
    bgtu    t3, t2, 850f
47: ld      a3, 144(sp)                     # the bytes join the encoding
    addi    a3, a3, 2
    sd      a3, 32(sp)
48: ld      a3, 32(sp)
    ld      a4, 152(sp)
    bgeu    a3, a4, 49f
    lbu     a0, 0(a3)
    call    jd_hexdigit
    slli    t3, a0, 4
    sb      t3, 112(sp)
    ld      a3, 32(sp)
    lbu     a0, 1(a3)
    call    jd_hexdigit
    lbu     t3, 112(sp)
    or      t3, t3, a0
    sb      t3, 112(sp)
    addi    a0, sp, 112
    li      a1, 1
    call    jd_out
    ld      a3, 32(sp)
    addi    a3, a3, 2
    sd      a3, 32(sp)
    j       48b
49: ld      a0, 24(sp)
    li      a1, 0
    UNFRAME 160
300: ADDRESS a1, api_true                   # Boolean: true or false
    li      a2, 4
    call    jd_literal
    li      t3, 1
    bnez    a1, 301f
    ld      a0, 16(sp)
    ADDRESS a1, api_false
    li      a2, 5
    call    jd_literal
    beqz    a1, 870f
    li      t3, 0
301: sb     t3, 112(sp)
    ld      a0, 16(sp)
    lbu     t0, 0(a0)
    li      t1, 0x74
    li      t2, 5
    bne     t0, t1, 302f
    li      t2, 4
302: add    a0, a0, t2
    sd      a0, 24(sp)
    addi    a0, sp, 112
    li      a1, 1
    call    jd_out
    ld      a0, 24(sp)
    li      a1, 0
    UNFRAME 160
100: li     t3, 0x7b                        # a container: an object
    bne     t2, t3, 870f
    ld      t0, 8(sp)                       # its field table: zero
    slli    t0, t0, 9
    add     t0, s3, t0
    sd      t0, 64(sp)
    mv      a0, t0
    li      a1, 512
    call    lantern_zero
    ld      a0, 16(sp)
    addi    a0, a0, 1
    call    jd_ws
    ld      a2, 8(sp)
    bgeu    a0, s2, 880f
    lbu     t0, 0(a0)
    li      t1, 0x7d
    bne     t0, t1, 110f
    addi    a0, a0, 1
    sd      a0, 24(sp)
    j       130f
110: sd     a0, 72(sp)                      # a member: its name, a field not seen yet
    ld      a2, 8(sp)
    lbu     t0, 0(a0)
    li      t1, 0x22
    bne     t0, t1, 880f
    call    jd_string
    bnez    a1, 899f
    sd      a0, 88(sp)
    ld      t0, 80(sp)
    ld      t1, SSZ_NODE_LENGTH(t0)
    ld      t2, SSZ_NODE_ELEMENT(t0)
    li      t3, 0
111: bgeu   t3, t1, 890f
    add     t4, t2, t3
    slli    t4, t4, 5
    add     t4, s9, t4                      # the name of field t3
    sub     t5, a4, a3
    li      t6, 32
    bgtu    t5, t6, 114f
    li      a5, 0
112: bgeu   a5, t5, 113f
    add     t6, a3, a5
    lbu     t6, 0(t6)
    add     a6, t4, a5
    lbu     a6, 0(a6)
    bne     t6, a6, 114f
    addi    a5, a5, 1
    j       112b
113: li     t6, 32
    beq     t5, t6, 115f
    add     t6, t4, t5
    lbu     t6, 0(t6)
    beqz    t6, 115f
114: addi   t3, t3, 1
    j       111b
115: ld     t0, 64(sp)                      # field t3: seen before?
    slli    t1, t3, 3
    add     t1, t0, t1
    ld      t1, 0(t1)
    bnez    t1, 890f
    sd      t3, 32(sp)
    ld      a0, 88(sp)
    call    jd_ws
    ld      a2, 8(sp)
    bgeu    a0, s2, 880f
    lbu     t0, 0(a0)
    li      t1, 0x3a
    bne     t0, t1, 880f
    addi    a0, a0, 1
    call    jd_ws
    ld      t0, 64(sp)                      # its value: kept, then skipped one level down
    ld      t3, 32(sp)
    slli    t1, t3, 3
    add     t1, t0, t1
    sub     t2, a0, s1
    addi    t2, t2, 1
    sd      t2, 0(t1)
    ld      a2, 8(sp)
    slli    t1, a2, 3
    add     t1, s10, t1
    sd      t3, JsonFault_path(t1)
    addi    a2, a2, 1
    call    jd_skip
    bnez    a1, 899f
    call    jd_ws
    ld      a2, 8(sp)
    bgeu    a0, s2, 880f
    lbu     t0, 0(a0)
    li      t1, 0x2c
    bne     t0, t1, 116f
    addi    a0, a0, 1
    call    jd_ws
    ld      a2, 8(sp)
    bgeu    a0, s2, 880f
    j       110b
116: li     t1, 0x7d
    bne     t0, t1, 880f
    addi    a0, a0, 1
    sd      a0, 24(sp)
130: ld     t0, 80(sp)                      # each field given
    ld      t1, SSZ_NODE_LENGTH(t0)
    ld      t2, 64(sp)
    li      t3, 0
131: bgeu   t3, t1, 132f
    slli    t4, t3, 3
    add     t4, t2, t4
    ld      t4, 0(t4)
    beqz    t4, 840f
    addi    t3, t3, 1
    j       131b
132: ld     t2, SSZ_NODE_ELEMENT(t0)        # the fixed part: each field's bytes, or 4
    li      t3, 0
    li      t4, 0
133: bgeu   t3, t1, 134f
    add     t5, t2, t3
    slli    t5, t5, 5
    add     t5, s8, t5
    ld      t6, SSZ_FIELD_FLAGS(t5)
    andi    t6, t6, SSZ_FIELD_VARIABLE
    li      a5, 4
    bnez    t6, 1331f
    ld      t6, SSZ_FIELD_NODE(t5)
    li      a6, SSZ_NODE_STRIDE
    mul     t6, t6, a6
    add     t6, s7, t6
    ld      a5, SSZ_NODE_SSZ_SIZE(t6)
1331: add   t4, t4, a5
    addi    t3, t3, 1
    j       133b
134: sd     s5, 48(sp)                      # start; the tail after the fixed part
    add     t4, s5, t4
    sd      t4, 56(sp)
    sd      zero, 32(sp)
135: ld     t0, 80(sp)                      # each field, in order
    ld      t1, SSZ_NODE_LENGTH(t0)
    ld      t3, 32(sp)
    bgeu    t3, t1, 139f
    ld      t2, SSZ_NODE_ELEMENT(t0)
    add     t5, t2, t3
    slli    t5, t5, 5
    add     t5, s8, t5
    sd      t5, 72(sp)
    ld      t4, 48(sp)
    ld      t6, SSZ_FIELD_SSZ_OFFSET(t5)
    add     t4, t4, t6                      # where the field, or its offset, goes
    ld      t6, SSZ_FIELD_FLAGS(t5)
    andi    t6, t6, SSZ_FIELD_VARIABLE
    beqz    t6, 136f
    ld      a0, 56(sp)                      # variable: its offset, then its bytes at the tail
    ld      t6, 48(sp)
    sub     a0, a0, t6
    mv      a1, t4
    call    jd_offset
    ld      s5, 56(sp)
    j       137f
136: mv     s5, t4
137: ld     a2, 8(sp)                       # the field's value, one level down
    ld      t3, 32(sp)
    slli    t1, a2, 3
    add     t1, s10, t1
    sd      t3, JsonFault_path(t1)
    addi    a2, a2, 1
    ld      t0, 64(sp)
    slli    t1, t3, 3
    add     t1, t0, t1
    ld      a1, 0(t1)
    addi    a1, a1, -1
    add     a1, s1, a1
    ld      t5, 72(sp)
    ld      a0, SSZ_FIELD_NODE(t5)
    call    jd_value
    bnez    a1, 899f
    ld      t5, 72(sp)
    ld      t6, SSZ_FIELD_FLAGS(t5)
    andi    t6, t6, SSZ_FIELD_VARIABLE
    beqz    t6, 138f
    sd      s5, 56(sp)
138: ld     t3, 32(sp)
    addi    t3, t3, 1
    sd      t3, 32(sp)
    j       135b
139: ld     s5, 56(sp)
    ld      a0, 24(sp)
    li      a1, 0
    UNFRAME 160
200: li     t3, 0x5b                        # a list or vector: an array, its items counted
    bne     t2, t3, 870f
    ld      a0, 16(sp)
    addi    a0, a0, 1
    call    jd_ws
    ld      a2, 8(sp)
    bgeu    a0, s2, 880f
    sd      zero, 40(sp)
    lbu     t0, 0(a0)
    li      t1, 0x5d
    bne     t0, t1, 210f
    addi    a0, a0, 1
    sd      a0, 24(sp)
    j       220f
210: ld     a2, 8(sp)                       # an item, skipped one level down
    ld      t3, 40(sp)
    slli    t1, a2, 3
    add     t1, s10, t1
    sd      t3, JsonFault_path(t1)
    addi    a2, a2, 1
    call    jd_skip
    bnez    a1, 899f
    ld      t3, 40(sp)
    addi    t3, t3, 1
    sd      t3, 40(sp)
    call    jd_ws
    ld      a2, 8(sp)
    bgeu    a0, s2, 880f
    lbu     t0, 0(a0)
    li      t1, 0x2c
    bne     t0, t1, 211f
    addi    a0, a0, 1
    call    jd_ws
    j       210b
211: li     t1, 0x5d
    bne     t0, t1, 880f
    addi    a0, a0, 1
    sd      a0, 24(sp)
220: ld     t0, 80(sp)                      # the count: N for a vector, at most N for a list
    ld      t1, SSZ_NODE_KIND(t0)
    ld      t2, SSZ_NODE_LENGTH(t0)
    ld      t3, 40(sp)
    bgtu    t3, t2, 830f
    li      t4, SSZ_KIND_VECTOR
    bne     t1, t4, 221f
    bne     t3, t2, 830f
221: ld     t4, SSZ_NODE_ELEMENT(t0)        # the items: fixed in a row, or 4-byte offsets first
    sd      t4, 96(sp)
    li      t5, SSZ_NODE_STRIDE
    mul     t4, t4, t5
    add     t4, s7, t4
    ld      t4, SSZ_NODE_SSZ_SIZE(t4)
    sd      t4, 104(sp)
    sd      s5, 48(sp)
    mv      t5, s5
    bnez    t4, 2211f
    slli    t5, t3, 2
    add     t5, s5, t5
2211: sd    t5, 56(sp)
    ld      a0, 16(sp)
    addi    a0, a0, 1
    call    jd_ws
    sd      a0, 72(sp)
    sd      zero, 32(sp)
222: ld     t3, 32(sp)
    ld      t1, 40(sp)
    bgeu    t3, t1, 229f
    ld      t4, 104(sp)
    bnez    t4, 223f
    ld      t5, 48(sp)                      # variable: its offset, then its bytes at the tail
    ld      t6, 56(sp)
    sub     a0, t6, t5
    slli    a1, t3, 2
    add     a1, t5, a1
    call    jd_offset
    ld      s5, 56(sp)
223: ld     a2, 8(sp)
    ld      t3, 32(sp)
    slli    t1, a2, 3
    add     t1, s10, t1
    sd      t3, JsonFault_path(t1)
    addi    a2, a2, 1
    ld      a0, 96(sp)
    ld      a1, 72(sp)
    call    jd_value
    bnez    a1, 899f
    ld      t4, 104(sp)
    bnez    t4, 224f
    sd      s5, 56(sp)
224: call   jd_ws                           # past the ,
    bgeu    a0, s2, 225f
    lbu     t0, 0(a0)
    li      t1, 0x2c
    bne     t0, t1, 225f
    addi    a0, a0, 1
    call    jd_ws
225: sd     a0, 72(sp)
    ld      t3, 32(sp)
    addi    t3, t3, 1
    sd      t3, 32(sp)
    j       222b
229: ld     t4, 104(sp)
    bnez    t4, 2291f
    ld      s5, 56(sp)
2291: ld    a0, 24(sp)
    li      a1, 0
    UNFRAME 160
830: li     a0, JSON_FAULT_LENGTH           # the faults of this level
    ld      a1, 16(sp)
    j       898f
840: li     a0, JSON_FAULT_MISSING
    ld      a1, 24(sp)
    addi    a1, a1, -1
    j       898f
850: li     a0, JSON_FAULT_HEX
    ld      a1, 16(sp)
    j       898f
860: li     a0, JSON_FAULT_NUMBER
    ld      a1, 16(sp)
    j       898f
870: li     a0, JSON_FAULT_TYPE
    ld      a1, 16(sp)
    j       898f
880: mv     a1, a0
    li      a0, JSON_FAULT_SYNTAX
    j       898f
890: li     a0, JSON_FAULT_FIELD
    ld      a1, 72(sp)
898: ld     a2, 8(sp)
    call    jd_fault
899: UNFRAME 160
END_FUNCTION jd_value

/* (type, json, scratch, out, fault): docs/reference/beacon-api.md. Locals: L out, L+8 the root. */
FUNCTION lantern_json_decode
    ENTER 16
    sd      a3, (L + 0)(sp)
    mv      s10, a4
    mv      s1, a0                          # the type, the text and scratch, a moment
    mv      s2, a1
    mv      s3, a2
    mv      a0, s10                         # the fault: zero
    li      a1, JSON_FAULT_SIZE
    call    lantern_zero
    ld      t0, 0(s3)
    li      t1, JSON_DECODE_SCRATCH
    bltu    t0, t1, 97f
    ld      t0, 8(s1)
    add     s7, s1, t0
    ld      t0, 24(s1)
    add     s8, s1, t0
    ld      t0, 32(s1)
    slli    t0, t0, 5
    add     s9, s8, t0
    ld      t0, 40(s1)
    sd      t0, (L + 8)(sp)
    ld      t0, 8(s2)                       # the text
    ld      t1, 16(s2)
    add     s1, s2, t0
    add     s2, s1, t1
    addi    s3, s3, 64                      # the field tables: 512 bytes a level
    li      s6, 0                           # first the count, with every check
    li      s5, 0
    ld      a0, (L + 8)(sp)
    mv      a1, s1
    li      a2, 0
    call    jd_value
    bnez    a1, 98f
    call    jd_ws
    bne     a0, s2, 96f
    ld      t0, (L + 0)(sp)                 # then the bytes, with room for them
    ld      t1, 0(t0)
    addi    t1, t1, -24
    bgtu    s5, t1, 95f
    addi    s4, t0, 24
    li      t1, 24
    sd      t1, 8(t0)
    sd      s5, 16(t0)
    li      s6, 1
    li      s5, 0
    ld      a0, (L + 8)(sp)
    mv      a1, s1
    li      a2, 0
    call    jd_value
    li      a0, LANTERN_OK
    LEAVE 16
95: sd      s5, JsonFault_size(s10)
97: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
96: mv      a1, a0
    li      a0, JSON_FAULT_SYNTAX
    li      a2, 0
    call    jd_fault
98: li      a0, LANTERN_INVALID_JSON
    LEAVE 16
END_FUNCTION lantern_json_decode

    RODATA
jd_null:
    .ascii "null"
