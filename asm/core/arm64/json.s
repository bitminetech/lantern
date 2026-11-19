/*
 * The JSON of SSZ values, ARM64: in the common object. Requirements: docs/reference/beacon-api.md,
 * lantern_json_encode.
 *
 * x19 the type, x20 the value, x21 the cursor, x22 out, x23 where the next byte goes, x24 the end
 * of out's room, x25 the type's nodes, x26 its fields, x27 the names after the fields, x28 the top
 * level of the cursor.
 */

/*
 * L0: the bytes x0 .. x0 + x1 of a token go out from the cursor's done bytes on, while out has
 * room: x0 = 0 when the token is whole (done 0), else 1 (done counts the bytes written). Uses
 * x9-x12.
 */
LOCAL_FUNCTION json_put
    UNWIND_END_PROLOGUE
    ldr     x9, [x21, #JsonCursor_done]
1:  cmp     x9, x1
    b.hs    2f
    cmp     x23, x24
    b.hs    3f
    ldrb    w10, [x0, x9]
    strb    w10, [x23], #1
    add     x9, x9, #1
    b       1b
2:  str     xzr, [x21, #JsonCursor_done]
    mov     x0, #0
    ret
3:  str     x9, [x21, #JsonCursor_done]
    mov     x0, #1
    ret
END_FUNCTION json_put

/*
 * L0: the hex token of the byte or bit string of the level x28 (kind x0): its bytes from the
 * cursor's done bytes on, while out has room: x0 = 0 when whole, else 1. Uses x1-x7, x9-x15.
 */
LOCAL_FUNCTION json_hex
    UNWIND_END_PROLOGUE
    ldr     x2, [x28, #JsonLevel_base]      /* the bytes */
    add     x2, x20, x2
    ldr     x3, [x28, #JsonLevel_count]
    mov     x4, x3                          /* the SSZ bytes: x4; the bit list's bits: x3 */
    cmp     x0, #SSZ_KIND_BIT_VECTOR
    b.ne    1f
    add     x4, x3, #7
    lsr     x4, x4, #3
1:  cmp     x0, #SSZ_KIND_BIT_LIST
    b.ne    2f
    lsr     x4, x3, #3
    add     x4, x4, #1
2:  lsl     x5, x4, #1                      /* the token's bytes: 4 + 2 per byte */
    add     x5, x5, #4
    ldr     x9, [x21, #JsonCursor_done]
    ADDRESS x7, api_hex
3:  cmp     x9, x5
    b.hs    8f
    cmp     x23, x24
    b.hs    9f
    mov     w10, #0x22                      /* " at either end, then 0x */
    cbz     x9, 7f
    sub     x11, x5, #1
    cmp     x9, x11
    b.eq    7f
    mov     w10, #0x30
    cmp     x9, #1
    b.eq    7f
    mov     w10, #0x78
    cmp     x9, #2
    b.eq    7f
    sub     x11, x9, #3                     /* a digit: byte x11 / 2 */
    lsr     x12, x11, #1
    mov     x13, #0
    cmp     x0, #SSZ_KIND_BIT_LIST
    b.ne    5f
    add     x14, x3, #7                     /* a bit list: its bytes, then the delimiter bit */
    lsr     x14, x14, #3
    cmp     x12, x14
    b.hs    4f
    ldrb    w13, [x2, x12]
4:  lsr     x14, x3, #3
    cmp     x12, x14
    b.ne    6f
    and     x15, x3, #7
    mov     x14, #1
    lsl     x14, x14, x15
    orr     x13, x13, x14
    b       6f
5:  ldrb    w13, [x2, x12]
6:  tst     x11, #1
    lsr     x14, x13, #4
    and     x15, x13, #15
    csel    x14, x15, x14, ne
    ldrb    w10, [x7, x14]
7:  strb    w10, [x23], #1
    add     x9, x9, #1
    b       3b
8:  str     xzr, [x21, #JsonCursor_done]
    mov     x0, #0
    ret
9:  str     x9, [x21, #JsonCursor_done]
    mov     x0, #1
    ret
END_FUNCTION json_hex

/*
 * L1: the token of the uint or Boolean of the level x28 (kind x0): x0 = 0 when whole, else 1.
 * Locals: the text, from its end, and the number's 32-bit words.
 */
LOCAL_FUNCTION json_number
    FRAME 128
    ldr     x2, [x28, #JsonLevel_base]
    add     x2, x20, x2
    cmp     x0, #SSZ_KIND_BOOLEAN
    b.ne    1f
    ldrb    w9, [x2]
    ADDRESS x0, api_true
    mov     x1, #api_true_len
    cbnz    w9, 9f
    ADDRESS x0, api_false
    mov     x1, #api_false_len
    b       9f
1:  add     x9, sp, #(16 + 120)             /* the closing quote, then the digits backwards */
    mov     w10, #0x22
    strb    w10, [x9, #-1]!
    ldr     x3, [x28, #JsonLevel_count]     /* the width */
    cmp     x3, #8
    b.hi    4f
    ldr     x4, [x2]                        /* up to 8 bytes: one u64 */
    cmp     x3, #8
    b.eq    2f
    and     x4, x4, #0xff
2:  mov     x10, #10
3:  udiv    x11, x4, x10
    msub    x12, x11, x10, x4
    add     x12, x12, #0x30
    strb    w12, [x9, #-1]!
    mov     x4, x11
    cbnz    x4, 3b
    b       8f
4:  ldp     x10, x11, [x2]                  /* 32 bytes: eight 32-bit words at sp + 16 */
    stp     x10, x11, [sp, #16]
    ldp     x10, x11, [x2, #16]
    stp     x10, x11, [sp, #32]
5:  mov     x4, #0                          /* divide by 10, from the top word down */
    mov     x5, #7
    mov     x6, #0                          /* any word not zero */
    mov     x10, #10
6:  add     x7, sp, #16
    ldr     w11, [x7, x5, lsl #2]
    orr     x11, x11, x4, lsl #32
    udiv    x12, x11, x10
    msub    x4, x12, x10, x11
    str     w12, [x7, x5, lsl #2]
    orr     x6, x6, x12
    subs    x5, x5, #1
    b.hs    6b
    add     x4, x4, #0x30
    strb    w4, [x9, #-1]!
    cbnz    x6, 5b
8:  mov     w10, #0x22
    strb    w10, [x9, #-1]!
    mov     x0, x9
    add     x1, sp, #(16 + 120)
    sub     x1, x1, x9
9:  bl      json_put
    UNFRAME 128
END_FUNCTION json_number

/*
 * L0: the level x28 for the type node x0 whose storage is at offset x1 of the value: inline when
 * x2 is 2^64 - 1 and the type is of fixed size; a value of its own with its size first when x2 is
 * 2^64 - 1 and the type is of variable size; else a PartRef at x1 whose offset counts from x2.
 * Uses x3-x7, x9-x12.
 */
LOCAL_FUNCTION json_open
    UNWIND_END_PROLOGUE
    mov     x3, #SSZ_NODE_STRIDE
    madd    x3, x0, x3, x25
    stp     x0, xzr, [x28, #JsonLevel_node]     /* node, step 0 */
    str     xzr, [x28, #JsonLevel_item]
    ldr     x4, [x3, #SSZ_NODE_KIND]
    ldr     x5, [x3, #SSZ_NODE_LENGTH]
    str     x5, [x28, #JsonLevel_count]     /* the width, the length, the field count */
    str     x1, [x28, #JsonLevel_base]
    ldr     x6, [x3, #SSZ_NODE_SSZ_SIZE]
    cbnz    x6, 9f                          /* fixed size: inline */
    cmp     x4, #SSZ_KIND_CONTAINER
    b.ne    2f
    cmn     x2, #1                          /* a container: its own value, or the part of a PartRef */
    b.eq    9f
    add     x7, x20, x1
    ldr     x7, [x7]
    add     x7, x2, x7
    str     x7, [x28, #JsonLevel_base]
    b       9f
2:  add     x7, x20, x1                     /* a list or bit list or byte list: its PartRef */
    mov     x9, x2
    cmn     x2, #1
    b.ne    3f
    mov     x9, x1                          /* its own value: the PartRef at byte 8 */
    add     x7, x7, #8
3:  ldp     x10, x11, [x7]
    add     x10, x9, x10
    stp     x11, x10, [x28, #JsonLevel_count]   /* count, base */
    str     x10, [x28, #JsonLevel_next]
9:  ret
END_FUNCTION json_open

/*
 * L1: the next item of the compound level x28 at index item, one level deeper. Uses the json_open
 * registers.
 */
LOCAL_FUNCTION json_child
    FRAME 0
    ldr     x9, [x28, #JsonLevel_node]
    mov     x10, #SSZ_NODE_STRIDE
    madd    x9, x9, x10, x25
    ldr     x10, [x9, #SSZ_NODE_KIND]
    ldr     x11, [x28, #JsonLevel_item]
    ldr     x12, [x28, #JsonLevel_base]
    cmp     x10, #SSZ_KIND_CONTAINER
    b.ne    2f
    ldr     x10, [x9, #SSZ_NODE_ELEMENT]    /* a field: inline, or a PartRef from the container */
    add     x10, x10, x11
    add     x10, x26, x10, lsl #5
    ldr     x0, [x10, #SSZ_FIELD_NODE]
    ldr     x1, [x10, #SSZ_FIELD_MEM_OFFSET]
    add     x1, x12, x1
    ldr     x3, [x10, #SSZ_FIELD_FLAGS]
    mov     x2, #-1
    tst     x3, #SSZ_FIELD_VARIABLE
    csel    x2, x12, x2, ne
    b       5f
2:  ldr     x0, [x9, #SSZ_NODE_ELEMENT]     /* an item: at its stride, or the next value of its own */
    mov     x10, #SSZ_NODE_STRIDE
    madd    x10, x0, x10, x25
    ldr     x3, [x10, #SSZ_NODE_SSZ_SIZE]
    mov     x2, #-1
    cbz     x3, 3f
    ldr     x3, [x10, #SSZ_NODE_MEM_SIZE]
    madd    x1, x11, x3, x12
    b       5f
3:  ldr     x1, [x28, #JsonLevel_next]
    add     x3, x20, x1
    ldr     x3, [x3]
    add     x3, x1, x3
    str     x3, [x28, #JsonLevel_next]
5:  ldr     x9, [x21, #JsonCursor_depth]
    add     x9, x9, #1
    str     x9, [x21, #JsonCursor_depth]
    add     x28, x28, #JSON_LEVEL_SIZE
    bl      json_open
    UNFRAME 0
END_FUNCTION json_child

/* (type, value, cursor, out): docs/reference/beacon-api.md. Locals: L a token of punctuation or a name. */
FUNCTION lantern_json_encode
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldp     x9, x10, [x22, #8]              /* out: its offset, its count, its room */
    add     x23, x22, x9
    add     x23, x23, x10
    ldr     x11, [x22]
    add     x24, x22, x11
    cmp     x23, x24
    b.hs    97f
    ldr     x9, [x21, #JsonCursor_whole]
    cbnz    x9, 90f
    ldr     x9, [x19, #8]                   /* the nodes, the fields, the names after them */
    add     x25, x19, x9
    ldr     x9, [x19, #24]
    add     x26, x19, x9
    ldr     x9, [x19, #32]
    add     x27, x26, x9, lsl #5
    ldr     x9, [x21, #JsonCursor_depth]
    cbnz    x9, 1f
    mov     x9, #1                          /* the root: inline, or a value of its own */
    str     x9, [x21, #JsonCursor_depth]
    str     xzr, [x21, #JsonCursor_done]
    add     x28, x21, #JsonCursor_levels
    ldr     x0, [x19, #40]
    mov     x1, #0
    mov     x2, #-1
    bl      json_open
1:  ldr     x9, [x21, #JsonCursor_depth]
    sub     x9, x9, #1
    mov     x10, #JSON_LEVEL_SIZE
    add     x28, x21, #JsonCursor_levels
    madd    x28, x9, x10, x28
10: ldr     x9, [x28, #JsonLevel_node]      /* the top level */
    mov     x10, #SSZ_NODE_STRIDE
    madd    x9, x9, x10, x25
    ldr     x0, [x9, #SSZ_NODE_KIND]
    cmp     x0, #SSZ_KIND_UINT
    ccmp    x0, #SSZ_KIND_BOOLEAN, #4, ne
    b.ne    11f
    bl      json_number
    cbnz    x0, 91f
    b       50f
11: cmp     x0, #SSZ_KIND_VECTOR
    b.hs    20f
    bl      json_hex                        /* a byte or bit string */
    cbnz    x0, 91f
    b       50f
20: ldr     x9, [x28, #JsonLevel_step]      /* a list, vector or container */
    mov     w10, #0x5b                      /* [ ] or { } */
    mov     w11, #0x5d
    cmp     x0, #SSZ_KIND_CONTAINER
    b.ne    21f
    mov     w10, #0x7b
    mov     w11, #0x7d
21: cbnz    x9, 22f
    strb    w10, [sp, #L]                   /* step 0: the opening */
    add     x0, sp, #L
    mov     x1, #1
    bl      json_put
    cbnz    x0, 91f
    mov     x9, #1
    str     x9, [x28, #JsonLevel_step]
    b       10b
22: cmp     x9, #1
    b.ne    25f
    ldr     x12, [x28, #JsonLevel_item]     /* step 1: the closing after the last item, or , */
    ldr     x13, [x28, #JsonLevel_count]
    cmp     x12, x13
    b.lo    23f
    strb    w11, [sp, #L]
    add     x0, sp, #L
    mov     x1, #1
    bl      json_put
    cbnz    x0, 91f
    b       50f
23: cbz     x12, 24f
    mov     w10, #0x2c
    strb    w10, [sp, #L]
    add     x0, sp, #L
    mov     x1, #1
    bl      json_put
    cbnz    x0, 91f
24: mov     x9, #2
    str     x9, [x28, #JsonLevel_step]
    b       10b
25: cmp     x0, #SSZ_KIND_CONTAINER         /* step 2: a field's "name":, then the item, deeper */
    b.ne    27f
    ldr     x9, [x28, #JsonLevel_node]
    mov     x10, #SSZ_NODE_STRIDE
    madd    x9, x9, x10, x25
    ldr     x9, [x9, #SSZ_NODE_ELEMENT]
    ldr     x10, [x28, #JsonLevel_item]
    add     x9, x9, x10
    add     x9, x27, x9, lsl #5
    mov     w10, #0x22
    strb    w10, [sp, #L]
    mov     x10, #0
26: cmp     x10, #32
    b.hs    261f
    ldrb    w11, [x9, x10]
    cbz     w11, 261f
    add     x12, sp, #(L + 1)
    strb    w11, [x12, x10]
    add     x10, x10, #1
    b       26b
261: add    x12, sp, #(L + 1)
    add     x12, x12, x10
    mov     w11, #0x22
    strb    w11, [x12]
    mov     w11, #0x3a
    strb    w11, [x12, #1]
    add     x0, sp, #L
    add     x1, x10, #3
    bl      json_put
    cbnz    x0, 91f
27: mov     x9, #3
    str     x9, [x28, #JsonLevel_step]
    ldr     x9, [x21, #JsonCursor_depth]
    cmp     x9, #JSON_LEVELS
    b.hs    97f
    bl      json_child
    b       10b
50: ldr     x9, [x21, #JsonCursor_depth]    /* the level is whole: up one, the next item there */
    subs    x9, x9, #1
    str     x9, [x21, #JsonCursor_depth]
    b.eq    80f
    sub     x28, x28, #JSON_LEVEL_SIZE
    ldr     x10, [x28, #JsonLevel_item]
    add     x10, x10, #1
    mov     x11, #1
    stp     x11, x10, [x28, #JsonLevel_step]
    b       10b
80: mov     x9, #1                          /* the JSON is whole */
    str     x9, [x21, #JsonCursor_whole]
90: ldr     x9, [x22, #8]
    add     x9, x22, x9
    sub     x9, x23, x9
    str     x9, [x22, #16]
    mov     x0, #LANTERN_OK
    LEAVE 48
91: ldr     x9, [x22, #8]
    add     x9, x22, x9
    sub     x9, x23, x9
    str     x9, [x22, #16]
    mov     x0, #LANTERN_JSON_MORE
    LEAVE 48
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
END_FUNCTION lantern_json_encode
