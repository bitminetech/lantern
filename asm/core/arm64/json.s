/*
 * The JSON of SSZ values, ARM64: in the common object. Requirements: docs/reference/beacon-api.md,
 * lantern_json_encode.
 *
 * x19 the type, x20 the value, x21 the cursor, x22 out, x23 where the next byte goes, x24 the end
 * of out's room, x25 the type's nodes, x26 its fields, x27 the names after the fields, x28 the top
 * level of the cursor.
 */

/*
 * The bytes x0 .. x0 + x1 of a token go out from the cursor's done bytes on, while out has
 * room: x0 = 0 when the token is whole (done 0), else 1 (done counts the bytes written). Uses
 * x9-x12.
 */
LOCAL_FUNCTION lantern_json_put
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
END_FUNCTION lantern_json_put

/*
 * The hex token of the byte or bit string of the level x28 (kind x0): its bytes from the
 * cursor's done bytes on, while out has room: x0 = 0 when whole, else 1. Uses x1-x7, x9-x15.
 */
LOCAL_FUNCTION lantern_json_hex
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
END_FUNCTION lantern_json_hex

/*
 * The token of the uint or Boolean of the level x28 (kind x0): x0 = 0 when whole, else 1.
 * Locals: the text, from its end, and the number's 32-bit words.
 */
LOCAL_FUNCTION lantern_json_number
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
9:  bl      lantern_json_put
    UNFRAME 128
END_FUNCTION lantern_json_number

/*
 * The level x28 for the type node x0 whose storage is at offset x1 of the value: inline when
 * x2 is 2^64 - 1 and the type is of fixed size; a value of its own with its size first when x2 is
 * 2^64 - 1 and the type is of variable size; else a PartRef at x1 whose offset counts from x2.
 * Uses x3-x7, x9-x12.
 */
LOCAL_FUNCTION lantern_json_open
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
END_FUNCTION lantern_json_open

/*
 * The next item of the compound level x28 at index item, one level deeper. Uses the lantern_json_open
 * registers.
 */
LOCAL_FUNCTION lantern_json_child
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
    bl      lantern_json_open
    UNFRAME 0
END_FUNCTION lantern_json_child

/*
 * x0 = the offset of the next variable field after field x1 of the container level x28 in an
 * SSZ encoding, or the level's end with none. Uses x9-x13.
 */
LOCAL_FUNCTION lantern_jss_field_end
    UNWIND_END_PROLOGUE
    ldr     x9, [x28, #JsonLevel_node]
    mov     x10, #SSZ_NODE_STRIDE
    madd    x9, x9, x10, x25
    ldr     x10, [x9, #SSZ_NODE_LENGTH]
    ldr     x9, [x9, #SSZ_NODE_ELEMENT]
    ldr     x11, [x28, #JsonLevel_base]
1:  add     x1, x1, #1
    cmp     x1, x10
    b.hs    9f
    add     x12, x9, x1
    add     x12, x26, x12, lsl #5
    ldr     x13, [x12, #SSZ_FIELD_FLAGS]
    tbz     x13, #0, 1b
    ldr     x13, [x12, #SSZ_FIELD_SSZ_OFFSET]
    add     x13, x11, x13
    ldr     w0, [x20, x13]
    add     x0, x11, x0
    ret
9:  ldr     x0, [x28, #JsonLevel_next]
    ret
END_FUNCTION lantern_jss_field_end

/*
 * The level x28 for the type node x0 whose SSZ encoding is the bytes x1 to x2 of the
 * encoding: base and end (next), and the count of its items or bytes. Uses x3-x5, x9-x12.
 */
LOCAL_FUNCTION lantern_jss_open
    UNWIND_END_PROLOGUE
    mov     x3, #SSZ_NODE_STRIDE
    madd    x3, x0, x3, x25
    stp     x0, xzr, [x28, #JsonLevel_node]
    str     xzr, [x28, #JsonLevel_item]
    str     x1, [x28, #JsonLevel_base]
    str     x2, [x28, #JsonLevel_next]
    ldr     x4, [x3, #SSZ_NODE_KIND]
    ldr     x5, [x3, #SSZ_NODE_LENGTH]
    cmp     x4, #SSZ_KIND_BYTE_LIST         /* a byte or bit list: its bytes */
    ccmp    x4, #SSZ_KIND_BIT_LIST, #4, ne
    b.ne    1f
    sub     x5, x2, x1
    b       9f
1:  cmp     x4, #SSZ_KIND_LIST
    b.ne    9f
    ldr     x9, [x3, #SSZ_NODE_ELEMENT]     /* a list: its bytes over the item's size, or its first offset over 4 */
    mov     x10, #SSZ_NODE_STRIDE
    madd    x9, x9, x10, x25
    ldr     x10, [x9, #SSZ_NODE_SSZ_SIZE]
    sub     x11, x2, x1
    cbz     x10, 2f
    udiv    x5, x11, x10
    b       9f
2:  mov     x5, #0
    cbz     x11, 9f
    ldr     w5, [x20, x1]
    lsr     x5, x5, #2
9:  str     x5, [x28, #JsonLevel_count]
    ret
END_FUNCTION lantern_jss_open

/* The next item of the compound level x28 of an SSZ encoding at index item, one level deeper. */
LOCAL_FUNCTION lantern_jss_child
    FRAME 16
    ldr     x9, [x28, #JsonLevel_node]
    mov     x10, #SSZ_NODE_STRIDE
    madd    x9, x9, x10, x25
    ldr     x10, [x9, #SSZ_NODE_KIND]
    ldr     x11, [x28, #JsonLevel_item]
    ldr     x12, [x28, #JsonLevel_base]
    cmp     x10, #SSZ_KIND_CONTAINER
    b.ne    3f
    ldr     x10, [x9, #SSZ_NODE_ELEMENT]    /* a field: at its ssz_offset, or from its offset to the next */
    add     x10, x10, x11
    add     x10, x26, x10, lsl #5
    ldr     x0, [x10, #SSZ_FIELD_NODE]
    ldr     x13, [x10, #SSZ_FIELD_SSZ_OFFSET]
    add     x13, x12, x13
    ldr     x14, [x10, #SSZ_FIELD_FLAGS]
    tbnz    x14, #0, 2f
    mov     x1, x13
    mov     x14, #SSZ_NODE_STRIDE
    madd    x14, x0, x14, x25
    ldr     x14, [x14, #SSZ_NODE_SSZ_SIZE]
    add     x2, x13, x14
    b       5f
2:  ldr     w14, [x20, x13]
    add     x14, x12, x14
    str     x0, [sp, #16]
    str     x14, [sp, #24]
    mov     x1, x11
    bl      lantern_jss_field_end
    mov     x2, x0
    ldp     x0, x1, [sp, #16]
    b       5f
3:  ldr     x0, [x9, #SSZ_NODE_ELEMENT]     /* an item: at its index times its size, or from its offset to the next */
    mov     x14, #SSZ_NODE_STRIDE
    madd    x14, x0, x14, x25
    ldr     x14, [x14, #SSZ_NODE_SSZ_SIZE]
    cbz     x14, 4f
    madd    x1, x11, x14, x12
    add     x2, x1, x14
    b       5f
4:  add     x13, x12, x11, lsl #2
    ldr     w1, [x20, x13]
    add     x1, x12, x1
    ldr     x2, [x28, #JsonLevel_next]
    ldr     x15, [x28, #JsonLevel_count]
    add     x13, x11, #1
    cmp     x13, x15
    b.hs    5f
    add     x13, x12, x13, lsl #2
    ldr     w2, [x20, x13]
    add     x2, x12, x2
5:  ldr     x9, [x21, #JsonCursor_depth]
    add     x9, x9, #1
    str     x9, [x21, #JsonCursor_depth]
    add     x28, x28, #JSON_LEVEL_SIZE
    bl      lantern_jss_open
    UNFRAME 16
END_FUNCTION lantern_jss_child

/* (type, value, cursor, out): docs/reference/beacon-api.md. */
FUNCTION lantern_json_encode
    FRAME 0
    mov     x4, #0
    mov     x5, #0
    bl      lantern_json_main
    UNFRAME 0
END_FUNCTION lantern_json_encode

/* (type, ssz, cursor, out): docs/reference/beacon-api.md. */
FUNCTION lantern_json_encode_ssz
    FRAME 0
    ldp     x9, x5, [x1, #8]
    add     x1, x1, x9
    mov     x4, #1
    bl      lantern_json_main
    UNFRAME 0
END_FUNCTION lantern_json_encode_ssz

/*
 * (type, value or encoding, cursor, out, mode, the encoding's bytes): the JSON of a value
 * (mode 0) or of an encoding (mode 1). Locals: L a token of punctuation or a name, L+48 the mode,
 * L+56 the encoding's bytes.
 */
LOCAL_FUNCTION lantern_json_main
    ENTER 64
    stp     x4, x5, [sp, #(L + 48)]
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
    ldp     x9, x2, [sp, #(L + 48)]
    cbnz    x9, 2f
    mov     x2, #-1
    bl      lantern_json_open
    b       1f
2:  bl      lantern_jss_open
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
    bl      lantern_json_number
    cbnz    x0, 91f
    b       50f
11: cmp     x0, #SSZ_KIND_VECTOR
    b.hs    20f
    ldr     x9, [sp, #(L + 48)]             /* a byte or bit string; a bit list's encoding as its bytes */
    cmp     x0, #SSZ_KIND_BIT_LIST
    ccmp    x9, #0, #4, eq
    mov     x9, #SSZ_KIND_BYTE_LIST
    csel    x0, x9, x0, ne
    bl      lantern_json_hex
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
    bl      lantern_json_put
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
    bl      lantern_json_put
    cbnz    x0, 91f
    b       50f
23: cbz     x12, 24f
    mov     w10, #0x2c
    strb    w10, [sp, #L]
    add     x0, sp, #L
    mov     x1, #1
    bl      lantern_json_put
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
    bl      lantern_json_put
    cbnz    x0, 91f
27: mov     x9, #3
    str     x9, [x28, #JsonLevel_step]
    ldr     x9, [x21, #JsonCursor_depth]
    cmp     x9, #JSON_LEVELS
    b.hs    97f
    ldr     x9, [sp, #(L + 48)]
    cbnz    x9, 28f
    bl      lantern_json_child
    b       10b
28: bl      lantern_jss_child
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
    LEAVE 64
91: ldr     x9, [x22, #8]
    add     x9, x22, x9
    sub     x9, x23, x9
    str     x9, [x22, #16]
    mov     x0, #LANTERN_JSON_MORE
    LEAVE 64
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_json_main

/*
 * ---------------------------------------------------------------- lantern_json_decode
 *
 * x19 the JSON's first byte, x20 its end, x21 the field tables in scratch (512 bytes a level),
 * x22 where the encoding goes, x23 the bytes of the encoding so far, x24 1 when the bytes are
 * written (0 counts them), x25 the type's nodes, x26 its fields, x27 the names after the fields,
 * x28 the JsonFault, whose path the levels fill as they go down.
 */

/* x0 = the first byte at or after x0 that is no white space. Uses x9. */
LOCAL_FUNCTION lantern_jd_ws
    UNWIND_END_PROLOGUE
1:  cmp     x0, x20
    b.hs    9f
    ldrb    w9, [x0]
    cmp     w9, #0x20
    b.eq    2f
    cmp     w9, #0x09
    b.eq    2f
    cmp     w9, #0x0a
    b.eq    2f
    cmp     w9, #0x0d
    b.ne    9f
2:  add     x0, x0, #1
    b       1b
9:  ret
END_FUNCTION lantern_jd_ws

/* The fault x0 at the byte x1 (the end when past it), at depth x2: x1 = 1. Uses x9. */
LOCAL_FUNCTION lantern_jd_fault
    UNWIND_END_PROLOGUE
    cmp     x1, x20
    csel    x1, x20, x1, hi
    sub     x9, x1, x19
    stp     x0, x9, [x28, #JsonFault_kind]
    str     x2, [x28, #JsonFault_depth]
    mov     x1, #1
    ret
END_FUNCTION lantern_jd_fault

/*
 * The string at x0 (its quote): x0 = after its closing quote, x3 its first byte, x4 its end,
 * x1 = 0; a \ or a byte below 0x20, or the end, is a fault at depth x2 (x1 = 1). Uses x9.
 */
LOCAL_FUNCTION lantern_jd_string
    FRAME 0
    add     x3, x0, #1
    mov     x4, x3
1:  cmp     x4, x20
    b.hs    8f
    ldrb    w9, [x4]
    cmp     w9, #0x22
    b.eq    2f
    cmp     w9, #0x5c
    b.eq    8f
    cmp     w9, #0x20
    b.lo    8f
    add     x4, x4, #1
    b       1b
2:  add     x0, x4, #1
    mov     x1, #0
    UNFRAME 0
8:  mov     x0, #JSON_FAULT_SYNTAX
    mov     x1, x4
    bl      lantern_jd_fault
    UNFRAME 0
END_FUNCTION lantern_jd_string

/* x0 = 1 when the byte at x0 is a decimal digit, below the end; else 0. Uses x9. */
.macro JD_DIGIT dst, at
    mov     \dst, #0
    cmp     \at, x20
    b.hs    77f
    ldrb    w9, [\at]
    sub     w9, w9, #0x30
    cmp     w9, #9
    cset    \dst, ls
77:
.endm

/* The number at x0 (RFC 8259 section 6): x0 = after it, x1 = 0; else a fault at depth x2. Uses x3, x9, x10. */
LOCAL_FUNCTION lantern_jd_number
    FRAME 0
    cmp     x0, x20
    b.hs    8f
    ldrb    w9, [x0]
    cmp     w9, #0x2d                       /* - */
    b.ne    1f
    add     x0, x0, #1
1:  cmp     x0, x20
    b.hs    8f
    ldrb    w9, [x0]
    cmp     w9, #0x30
    b.ne    2f
    add     x0, x0, #1
    b       3f
2:  sub     w9, w9, #0x31
    cmp     w9, #8
    b.hi    8f
21: add     x0, x0, #1
    JD_DIGIT x10, x0
    cbnz    x10, 21b
3:  cmp     x0, x20                         /* a fraction */
    b.hs    9f
    ldrb    w9, [x0]
    cmp     w9, #0x2e
    b.ne    4f
    add     x0, x0, #1
    JD_DIGIT x10, x0
    cbz     x10, 8f
31: add     x0, x0, #1
    JD_DIGIT x10, x0
    cbnz    x10, 31b
4:  cmp     x0, x20                         /* an exponent */
    b.hs    9f
    ldrb    w9, [x0]
    orr     w9, w9, #0x20
    cmp     w9, #0x65
    b.ne    9f
    add     x0, x0, #1
    cmp     x0, x20
    b.hs    8f
    ldrb    w9, [x0]
    cmp     w9, #0x2b
    b.eq    40f
    cmp     w9, #0x2d
    b.ne    41f
40: add     x0, x0, #1
41: JD_DIGIT x10, x0
    cbz     x10, 8f
42: add     x0, x0, #1
    JD_DIGIT x10, x0
    cbnz    x10, 42b
9:  mov     x1, #0
    UNFRAME 0
8:  mov     x1, x0
    mov     x0, #JSON_FAULT_SYNTAX
    bl      lantern_jd_fault
    UNFRAME 0
END_FUNCTION lantern_jd_number

/* x1 = 1 when the x2 bytes of text at x1 start at x0 below the end, else 0. Uses x9-x12. */
LOCAL_FUNCTION lantern_jd_literal
    UNWIND_END_PROLOGUE
    add     x9, x0, x2
    cmp     x9, x20
    b.hi    8f
    mov     x9, #0
1:  cmp     x9, x2
    b.hs    9f
    ldrb    w10, [x0, x9]
    ldrb    w11, [x1, x9]
    cmp     w10, w11
    b.ne    8f
    add     x9, x9, #1
    b       1b
9:  mov     x1, #1
    ret
8:  mov     x1, #0
    ret
END_FUNCTION lantern_jd_literal

/*
 * '"name":' at x0, in a skipped object: x0 = its value's first byte, x1 = 0; else a fault at
 * depth x2. Locals: x2.
 */
LOCAL_FUNCTION lantern_jd_key
    FRAME 16
    str     x2, [sp, #16]
    cmp     x0, x20
    b.hs    8f
    ldrb    w9, [x0]
    cmp     w9, #0x22
    b.ne    8f
    bl      lantern_jd_string
    cbnz    x1, 9f
    bl      lantern_jd_ws
    cmp     x0, x20
    b.hs    8f
    ldrb    w9, [x0]
    cmp     w9, #0x3a
    b.ne    8f
    add     x0, x0, #1
    mov     x1, #0
    UNFRAME 16
8:  mov     x1, x0
    mov     x0, #JSON_FAULT_SYNTAX
    ldr     x2, [sp, #16]
    bl      lantern_jd_fault
9:  UNFRAME 16
END_FUNCTION lantern_jd_key

/*
 * The value at x0, skipped with only the checks of the text, faults at depth x2: x0 = after
 * it, x1 = 0. Locals: L the depth, L+8 the nesting, a bit each (1 an object), L+16 its count.
 */
LOCAL_FUNCTION lantern_jd_skip
    FRAME 32
    str     x2, [sp, #16]
    stp     xzr, xzr, [sp, #24]
1:  bl      lantern_jd_ws                           /* a value */
    ldr     x2, [sp, #16]
    cmp     x0, x20
    b.hs    80f
    ldrb    w9, [x0]
    cmp     w9, #0x22
    b.ne    2f
    bl      lantern_jd_string
    cbnz    x1, 99f
    b       10f
2:  cmp     w9, #0x2d
    b.eq    21f
    sub     w10, w9, #0x30
    cmp     w10, #9
    b.hi    3f
21: bl      lantern_jd_number
    cbnz    x1, 99f
    b       10f
3:  ADDRESS x1, api_true
    mov     x2, #4
    bl      lantern_jd_literal
    cbz     x1, 31f
    add     x0, x0, #4
    b       10f
31: ADDRESS x1, api_false
    mov     x2, #5
    bl      lantern_jd_literal
    cbz     x1, 32f
    add     x0, x0, #5
    b       10f
32: ADDRESS x1, jd_null
    mov     x2, #4
    bl      lantern_jd_literal
    cbz     x1, 33f
    add     x0, x0, #4
    b       10f
33: ldr     x2, [sp, #16]
    ldrb    w9, [x0]
    cmp     w9, #0x5b
    b.eq    331f
    cmp     w9, #0x7b
    b.ne    80f
331:
    ldp     x10, x11, [sp, #24]             /* [ or {: one level more, at most 64 */
    cmp     x11, #64
    b.hs    80f
    lsl     x10, x10, #1
    cmp     w9, #0x7b
    cinc    x10, x10, eq
    add     x11, x11, #1
    stp     x10, x11, [sp, #24]
    add     x0, x0, #1
    bl      lantern_jd_ws
    ldr     x2, [sp, #16]
    cmp     x0, x20
    b.hs    80f
    ldrb    w9, [x0]
    ldr     x10, [sp, #24]
    tst     x10, #1
    mov     w11, #0x5d
    mov     w12, #0x7d
    csel    w11, w12, w11, ne
    cmp     w9, w11
    b.ne    34f
    add     x0, x0, #1                      /* empty: closed at once */
    b       12f
34: tbz     x10, #0, 1b                     /* an array: its first item; an object: its first key */
    bl      lantern_jd_key
    cbnz    x1, 99f
    b       1b
10: ldr     x11, [sp, #32]                  /* after a value: done at the top, else , or the close */
    cbz     x11, 98f
    bl      lantern_jd_ws
    ldr     x2, [sp, #16]
    cmp     x0, x20
    b.hs    80f
    ldrb    w9, [x0]
    ldr     x10, [sp, #24]
    cmp     w9, #0x2c
    b.ne    11f
    add     x0, x0, #1
    tbz     x10, #0, 1b
    bl      lantern_jd_ws
    ldr     x2, [sp, #16]
    bl      lantern_jd_key
    cbnz    x1, 99f
    b       1b
11: tst     x10, #1
    mov     w11, #0x5d
    mov     w12, #0x7d
    csel    w11, w12, w11, ne
    cmp     w9, w11
    b.ne    80f
    add     x0, x0, #1
12: ldp     x10, x11, [sp, #24]             /* one level up */
    lsr     x10, x10, #1
    sub     x11, x11, #1
    stp     x10, x11, [sp, #24]
    b       10b
80: mov     x1, x0
    mov     x0, #JSON_FAULT_SYNTAX
    bl      lantern_jd_fault
    b       99f
98: mov     x1, #0
99: UNFRAME 32
END_FUNCTION lantern_jd_skip

/* The x1 bytes at x0 join the encoding, written when x24 is 1. Uses x0, x1, x9, x10. */
LOCAL_FUNCTION lantern_jd_out
    UNWIND_END_PROLOGUE
    cbz     x24, 2f
    add     x9, x22, x23
1:  cbz     x1, 2f
    ldrb    w10, [x0], #1
    strb    w10, [x9], #1
    sub     x1, x1, #1
    add     x23, x23, #1
    b       1b
2:  add     x23, x23, x1
    ret
END_FUNCTION lantern_jd_out

/* The 4-byte offset x0 at byte x1 of the encoding, when x24 is 1. Uses x9. */
LOCAL_FUNCTION lantern_jd_offset
    UNWIND_END_PROLOGUE
    cbz     x24, 9f
    add     x9, x22, x1
    str     w0, [x9]
9:  ret
END_FUNCTION lantern_jd_offset

/* x0 = the value of the hex digit in w0, or 16 for another byte. */
LOCAL_FUNCTION lantern_jd_hexdigit
    UNWIND_END_PROLOGUE
    sub     w9, w0, #0x30
    cmp     w9, #9
    b.ls    1f
    orr     w9, w0, #0x20
    sub     w9, w9, #0x61
    cmp     w9, #5
    b.hi    2f
    add     w9, w9, #10
1:  mov     x0, x9
    ret
2:  mov     x0, #16
    ret
END_FUNCTION lantern_jd_hexdigit

/*
 * The value of the type node x0 at x1, at depth x2: its encoding joins at x23; x0 = after it,
 * x1 = 0, else a fault (x1 = 1). Locals: L node, L+8 depth, L+16 the value's first byte, L+24 the
 * end, L+32 an index, L+40 the count, L+48 the encoding's start, L+56 its tail, L+64 the field
 * table, L+72 the text cursor, L+80 the kind's node entry, L+88 bytes of a number.
 */
LOCAL_FUNCTION lantern_jd_value
    FRAME 160
    stp     x0, x2, [sp, #16]
    mov     x0, x1
    bl      lantern_jd_ws
    str     x0, [sp, #32]
    ldr     x2, [sp, #24]
    cmp     x0, x20
    b.hs    880f
    ldr     x9, [sp, #16]
    mov     x10, #SSZ_NODE_STRIDE
    madd    x9, x9, x10, x25
    str     x9, [sp, #96]
    ldr     x10, [x9, #SSZ_NODE_KIND]
    ldrb    w11, [x0]
    cmp     x10, #SSZ_KIND_CONTAINER
    b.eq    100f
    cmp     x10, #SSZ_KIND_VECTOR
    b.hs    200f
    cmp     x10, #SSZ_KIND_BOOLEAN
    b.eq    300f
    cmp     w11, #0x22                      /* a uint, a byte or bit string: a string */
    b.ne    870f
    bl      lantern_jd_string
    cbnz    x1, 899f
    str     x0, [sp, #40]
    ldr     x9, [sp, #96]
    ldr     x10, [x9, #SSZ_NODE_KIND]
    sub     x5, x4, x3                      /* the content's bytes */
    cmp     x10, #SSZ_KIND_UINT
    b.ne    400f
    ldrb    w9, [x21, #-8]                  /* the Engine API: a QUANTITY */
    cbnz    w9, 150f
    cbz     x5, 860f                        /* uint: 1 to 78 digits, below 2^(8 width) */
    cmp     x5, #78
    b.hi    860f
    stp     xzr, xzr, [sp, #104]
    stp     xzr, xzr, [sp, #120]
1:  cmp     x3, x4
    b.hs    3f
    ldrb    w12, [x3], #1
    sub     w12, w12, #0x30
    cmp     w12, #9
    b.hi    860f
    mov     x13, #0                         /* the 256-bit number times 10, plus the digit */
    mov     x14, x12
    add     x15, sp, #104
2:  ldr     x6, [x15, x13, lsl #3]
    mov     x7, #10
    mul     x10, x6, x7
    umulh   x11, x6, x7
    adds    x10, x10, x14
    cinc    x11, x11, cs
    str     x10, [x15, x13, lsl #3]
    mov     x14, x11
    add     x13, x13, #1
    cmp     x13, #4
    b.lo    2b
    cbnz    x14, 860f
    b       1b
150: cmp    x5, #3                          /* QUANTITY: 0x, then 0 alone or hex digits from a non-zero one; its value below 2^256 */
    b.lo    860f
    ldrb    w12, [x3]
    cmp     w12, #0x30
    b.ne    860f
    ldrb    w12, [x3, #1]
    cmp     w12, #0x78
    b.ne    860f
    ldrb    w12, [x3, #2]
    cmp     w12, #0x30
    b.ne    151f
    cmp     x5, #3
    b.ne    860f
151: add    x3, x3, #2
    stp     xzr, xzr, [sp, #104]
    stp     xzr, xzr, [sp, #120]
152: cmp    x3, x4
    b.hs    3f
    ldrb    w0, [x3], #1
    bl      lantern_jd_hexdigit
    cmp     x0, #16
    b.hs    860f
    ldr     x10, [sp, #128]                 /* the 256-bit number times 16, plus the digit */
    lsr     x11, x10, #60
    cbnz    x11, 860f
    ldp     x11, x12, [sp, #104]
    ldr     x13, [sp, #120]
    extr    x10, x10, x13, #60
    extr    x13, x13, x12, #60
    extr    x12, x12, x11, #60
    lsl     x11, x11, #4
    orr     x11, x11, x0
    stp     x11, x12, [sp, #104]
    stp     x13, x10, [sp, #120]
    b       152b
3:  ldr     x9, [sp, #96]
    ldr     x10, [x9, #SSZ_NODE_LENGTH]     /* the width: bytes past it zero */
    add     x11, sp, #104
    mov     x12, x10
4:  cmp     x12, #32
    b.hs    5f
    ldrb    w13, [x11, x12]
    cbnz    w13, 860f
    add     x12, x12, #1
    b       4b
5:  mov     x0, x11
    mov     x1, x10
    bl      lantern_jd_out
    ldr     x0, [sp, #40]
    mov     x1, #0
    UNFRAME 160
400: cmp    x5, #2                          /* a byte or bit string: 0x and pairs of hex digits */
    b.lo    850f
    ldrb    w12, [x3]
    cmp     w12, #0x30
    b.ne    850f
    ldrb    w12, [x3, #1]
    cmp     w12, #0x78
    b.ne    850f
    tst     x5, #1
    b.ne    850f
    add     x6, x3, #2                      /* every digit hex */
41: cmp     x6, x4
    b.hs    42f
    ldrb    w0, [x6], #1
    bl      lantern_jd_hexdigit
    cmp     x0, #16
    b.hs    850f
    b       41b
42: sub     x5, x5, #2
    lsr     x5, x5, #1                      /* the bytes */
    ldr     x9, [sp, #96]
    ldr     x10, [x9, #SSZ_NODE_KIND]
    ldr     x11, [x9, #SSZ_NODE_LENGTH]
    cmp     x10, #SSZ_KIND_BYTE_VECTOR
    b.ne    43f
    cmp     x5, x11
    b.ne    850f
    b       47f
43: cmp     x10, #SSZ_KIND_BYTE_LIST
    b.ne    44f
    cmp     x5, x11
    b.hi    850f
    b       47f
44: sub     x12, x4, #2                     /* the last byte, for the bit kinds */
    mov     x13, #0
    cbz     x5, 45f
    ldrb    w0, [x12]
    bl      lantern_jd_hexdigit
    lsl     x13, x0, #4
    ldrb    w0, [x12, #1]
    bl      lantern_jd_hexdigit
    orr     x13, x13, x0
45: ldr     x9, [sp, #96]
    ldr     x10, [x9, #SSZ_NODE_KIND]
    ldr     x11, [x9, #SSZ_NODE_LENGTH]
    cmp     x10, #SSZ_KIND_BIT_VECTOR
    b.ne    46f
    add     x12, x11, #7                    /* a bit vector: its bytes, the bits past N zero */
    lsr     x12, x12, #3
    cmp     x5, x12
    b.ne    850f
    ands    x12, x11, #7
    b.eq    47f
    lsr     x13, x13, x12
    cbnz    x13, 850f
    b       47f
46: cbz     x5, 850f                        /* a bit list: the last byte not zero, at most N bits */
    cbz     x13, 850f
    clz     x12, x13
    mov     x14, #63
    sub     x12, x14, x12                   /* the delimiter's bit */
    sub     x14, x5, #1
    add     x12, x12, x14, lsl #3
    cmp     x12, x11
    b.hi    850f
47: add     x6, x3, #2                      /* the bytes join the encoding */
48: cmp     x6, x4
    b.hs    49f
    ldrb    w0, [x6]
    bl      lantern_jd_hexdigit
    lsl     x7, x0, #4
    ldrb    w0, [x6, #1]
    bl      lantern_jd_hexdigit
    orr     x7, x7, x0
    strb    w7, [sp, #104]
    add     x0, sp, #104
    mov     x1, #1
    bl      lantern_jd_out
    add     x6, x6, #2
    b       48b
49: ldr     x0, [sp, #40]
    mov     x1, #0
    UNFRAME 160
300: ADDRESS x1, api_true                   /* Boolean: true or false */
    mov     x2, #4
    bl      lantern_jd_literal
    mov     w12, #1
    cbnz    x1, 301f
    ldr     x0, [sp, #32]
    ADDRESS x1, api_false
    mov     x2, #5
    bl      lantern_jd_literal
    cbz     x1, 870f
    mov     w12, #0
301: strb   w12, [sp, #104]
    ldr     x0, [sp, #32]
    ldrb    w9, [x0]
    cmp     w9, #0x74
    mov     x10, #5
    mov     x11, #4
    csel    x10, x11, x10, eq
    add     x10, x0, x10
    str     x10, [sp, #40]
    add     x0, sp, #104
    mov     x1, #1
    bl      lantern_jd_out
    ldr     x0, [sp, #40]
    mov     x1, #0
    UNFRAME 160
100: cmp    w11, #0x7b                      /* a container: an object */
    b.ne    870f
    ldr     x9, [sp, #24]                   /* its field table: zero */
    add     x9, x21, x9, lsl #9
    str     x9, [sp, #80]
    mov     x0, x9
    mov     x1, #512
    bl      lantern_zero
    ldr     x0, [sp, #32]
    add     x0, x0, #1
    bl      lantern_jd_ws
    ldr     x2, [sp, #24]
    cmp     x0, x20
    b.hs    880f
    ldrb    w9, [x0]
    cmp     w9, #0x7d
    b.ne    110f
    add     x0, x0, #1
    str     x0, [sp, #40]
    b       130f
110: str    x0, [sp, #88]                   /* a member: its name, a field not seen yet */
    ldr     x2, [sp, #24]
    ldrb    w9, [x0]
    cmp     w9, #0x22
    b.ne    880f
    bl      lantern_jd_string
    cbnz    x1, 899f
    str     x0, [sp, #120]
    ldr     x9, [sp, #96]
    ldr     x10, [x9, #SSZ_NODE_LENGTH]
    ldr     x11, [x9, #SSZ_NODE_ELEMENT]
    mov     x12, #0
    ldrb    w9, [x21, #-8]                  /* the Engine API: camelCase names, others skipped */
    cbnz    w9, 117f
111: cmp    x12, x10
    b.hs    890f
    add     x13, x11, x12
    add     x13, x27, x13, lsl #5           /* the name of field x12 */
    sub     x14, x4, x3
    cmp     x14, #32
    b.hi    114f
    mov     x15, #0
112: cmp    x15, x14
    b.hs    113f
    ldrb    w6, [x3, x15]
    ldrb    w7, [x13, x15]
    cmp     w6, w7
    b.ne    114f
    add     x15, x15, #1
    b       112b
113: cmp    x14, #32
    b.eq    115f
    ldrb    w6, [x13, x14]
    cbz     w6, 115f
114: add    x12, x12, #1
    b       111b
115: ldr    x9, [sp, #80]                   /* field x12: seen before? */
    ldr     x10, [x9, x12, lsl #3]
    cbnz    x10, 890f
    str     x12, [sp, #48]
    ldr     x0, [sp, #120]
    bl      lantern_jd_ws
    ldr     x2, [sp, #24]
    cmp     x0, x20
    b.hs    880f
    ldrb    w9, [x0]
    cmp     w9, #0x3a
    b.ne    880f
    add     x0, x0, #1
    bl      lantern_jd_ws
    ldr     x9, [sp, #80]                   /* its value: kept, then skipped one level down */
    ldr     x12, [sp, #48]
    sub     x10, x0, x19
    add     x10, x10, #1
    str     x10, [x9, x12, lsl #3]
    ldr     x2, [sp, #24]
    add     x9, x28, #JsonFault_path
    str     x12, [x9, x2, lsl #3]
    add     x2, x2, #1
    bl      lantern_jd_skip
    cbnz    x1, 899f
119: bl     lantern_jd_ws
    ldr     x2, [sp, #24]
    cmp     x0, x20
    b.hs    880f
    ldrb    w9, [x0]
    cmp     w9, #0x2c
    b.ne    116f
    add     x0, x0, #1
    bl      lantern_jd_ws
    ldr     x2, [sp, #24]
    cmp     x0, x20
    b.hs    880f
    b       110b
116: cmp    w9, #0x7d
    b.ne    880f
    add     x0, x0, #1
    str     x0, [sp, #40]
    b       130f
117: cmp    x12, x10                        /* field x12's name, each _x as X: the member's name? */
    b.hs    118f
    add     x13, x11, x12
    add     x13, x27, x13, lsl #5
    mov     x14, x3
    mov     x15, #0
1171: cmp   x15, #32
    b.hs    1173f
    ldrb    w6, [x13, x15]
    cbz     w6, 1173f
    cmp     w6, #0x5f
    b.ne    1172f
    add     x15, x15, #1
    cmp     x15, #32
    b.hs    1174f
    ldrb    w6, [x13, x15]
    sub     w6, w6, #0x20
1172: cmp   x14, x4
    b.hs    1174f
    ldrb    w7, [x14], #1
    cmp     w6, w7
    b.ne    1174f
    add     x15, x15, #1
    b       1171b
1173: cmp   x14, x4
    b.eq    115b
1174: add   x12, x12, #1
    b       117b
118: ldr    x0, [sp, #120]                  /* a member of no field: its value skipped */
    bl      lantern_jd_ws
    ldr     x2, [sp, #24]
    cmp     x0, x20
    b.hs    880f
    ldrb    w9, [x0]
    cmp     w9, #0x3a
    b.ne    880f
    add     x0, x0, #1
    bl      lantern_jd_ws
    ldr     x2, [sp, #24]                   /* its faults at the path of the field count */
    ldr     x9, [sp, #96]
    ldr     x10, [x9, #SSZ_NODE_LENGTH]
    add     x9, x28, #JsonFault_path
    str     x10, [x9, x2, lsl #3]
    add     x2, x2, #1
    bl      lantern_jd_skip
    cbnz    x1, 899f
    b       119b
130: ldr    x9, [sp, #96]                   /* each field given */
    ldr     x10, [x9, #SSZ_NODE_LENGTH]
    ldr     x11, [sp, #80]
    mov     x12, #0
131: cmp    x12, x10
    b.hs    132f
    ldr     x13, [x11, x12, lsl #3]
    cbz     x13, 840f
    add     x12, x12, #1
    b       131b
132: ldr    x11, [x9, #SSZ_NODE_ELEMENT]    /* the fixed part: each field's bytes, or 4 */
    mov     x12, #0
    mov     x13, #0
133: cmp    x12, x10
    b.hs    134f
    add     x14, x11, x12
    add     x14, x26, x14, lsl #5
    ldr     x15, [x14, #SSZ_FIELD_FLAGS]
    mov     x6, #4
    tbnz    x15, #0, 1331f
    ldr     x15, [x14, #SSZ_FIELD_NODE]
    mov     x7, #SSZ_NODE_STRIDE
    madd    x15, x15, x7, x25
    ldr     x6, [x15, #SSZ_NODE_SSZ_SIZE]
1331: add   x13, x13, x6
    add     x12, x12, #1
    b       133b
134: str    x23, [sp, #64]                  /* start; the tail after the fixed part */
    add     x13, x23, x13
    str     x13, [sp, #72]
    str     xzr, [sp, #48]
135: ldr    x9, [sp, #96]                   /* each field, in order */
    ldr     x10, [x9, #SSZ_NODE_LENGTH]
    ldr     x12, [sp, #48]
    cmp     x12, x10
    b.hs    139f
    ldr     x11, [x9, #SSZ_NODE_ELEMENT]
    add     x14, x11, x12
    add     x14, x26, x14, lsl #5
    ldr     x13, [sp, #64]
    ldr     x15, [x14, #SSZ_FIELD_SSZ_OFFSET]
    add     x13, x13, x15                   /* where the field, or its offset, goes */
    ldr     x15, [x14, #SSZ_FIELD_FLAGS]
    tbz     x15, #0, 136f
    ldr     x6, [sp, #72]                   /* variable: its offset, then its bytes at the tail */
    ldr     x7, [sp, #64]
    sub     x0, x6, x7
    mov     x1, x13
    bl      lantern_jd_offset
    ldr     x23, [sp, #72]
    b       137f
136: mov    x23, x13
137: ldr    x2, [sp, #24]                   /* the field's value, one level down */
    add     x9, x28, #JsonFault_path
    str     x12, [x9, x2, lsl #3]
    add     x2, x2, #1
    ldr     x0, [x14, #SSZ_FIELD_NODE]
    ldr     x9, [sp, #80]
    ldr     x1, [x9, x12, lsl #3]
    sub     x1, x1, #1
    add     x1, x19, x1
    bl      lantern_jd_value
    cbnz    x1, 899f
    ldr     x9, [sp, #96]
    ldr     x11, [x9, #SSZ_NODE_ELEMENT]
    ldr     x12, [sp, #48]
    add     x14, x11, x12
    add     x14, x26, x14, lsl #5
    ldr     x15, [x14, #SSZ_FIELD_FLAGS]
    tbz     x15, #0, 138f
    str     x23, [sp, #72]
138: add    x12, x12, #1
    str     x12, [sp, #48]
    b       135b
139: ldr    x23, [sp, #72]
    ldr     x0, [sp, #40]
    mov     x1, #0
    UNFRAME 160
200: cmp    w11, #0x5b                      /* a list or vector: an array, its items counted */
    b.ne    870f
    ldr     x0, [sp, #32]
    add     x0, x0, #1
    bl      lantern_jd_ws
    ldr     x2, [sp, #24]
    cmp     x0, x20
    b.hs    880f
    str     xzr, [sp, #56]
    ldrb    w9, [x0]
    cmp     w9, #0x5d
    b.ne    210f
    add     x0, x0, #1
    str     x0, [sp, #40]
    b       220f
210: ldr    x2, [sp, #24]                   /* an item, skipped one level down */
    ldr     x12, [sp, #56]
    add     x9, x28, #JsonFault_path
    str     x12, [x9, x2, lsl #3]
    add     x2, x2, #1
    bl      lantern_jd_skip
    cbnz    x1, 899f
    ldr     x12, [sp, #56]
    add     x12, x12, #1
    str     x12, [sp, #56]
    bl      lantern_jd_ws
    ldr     x2, [sp, #24]
    cmp     x0, x20
    b.hs    880f
    ldrb    w9, [x0]
    cmp     w9, #0x2c
    b.ne    211f
    add     x0, x0, #1
    bl      lantern_jd_ws
    b       210b
211: cmp    w9, #0x5d
    b.ne    880f
    add     x0, x0, #1
    str     x0, [sp, #40]
220: ldr    x9, [sp, #96]                   /* the count: N for a vector, at most N for a list */
    ldr     x10, [x9, #SSZ_NODE_KIND]
    ldr     x11, [x9, #SSZ_NODE_LENGTH]
    ldr     x12, [sp, #56]
    cmp     x12, x11
    b.hi    830f
    cmp     x10, #SSZ_KIND_VECTOR
    b.ne    221f
    cmp     x12, x11
    b.ne    830f
221: ldr    x13, [x9, #SSZ_NODE_ELEMENT]    /* the items: fixed in a row, or 4-byte offsets first */
    str     x13, [sp, #112]
    mov     x7, #SSZ_NODE_STRIDE
    madd    x13, x13, x7, x25
    ldr     x13, [x13, #SSZ_NODE_SSZ_SIZE]
    str     x13, [sp, #104]
    str     x23, [sp, #64]
    add     x14, x23, x12, lsl #2
    cmp     x13, #0
    csel    x14, x23, x14, ne
    str     x14, [sp, #72]
    ldr     x0, [sp, #32]
    add     x0, x0, #1
    bl      lantern_jd_ws
    str     x0, [sp, #88]
    str     xzr, [sp, #48]
222: ldr    x12, [sp, #48]
    ldr     x11, [sp, #56]
    cmp     x12, x11
    b.hs    229f
    ldr     x13, [sp, #104]
    cbnz    x13, 223f
    ldp     x6, x7, [sp, #64]               /* variable: its offset, then its bytes at the tail */
    sub     x0, x7, x6
    add     x1, x6, x12, lsl #2
    bl      lantern_jd_offset
    ldr     x23, [sp, #72]
223: ldr    x2, [sp, #24]
    ldr     x12, [sp, #48]
    add     x9, x28, #JsonFault_path
    str     x12, [x9, x2, lsl #3]
    add     x2, x2, #1
    ldr     x0, [sp, #112]
    ldr     x1, [sp, #88]
    bl      lantern_jd_value
    cbnz    x1, 899f
    ldr     x13, [sp, #104]
    cbnz    x13, 224f
    str     x23, [sp, #72]
224: bl      lantern_jd_ws                          /* past the , */
    cmp     x0, x20
    b.hs    225f
    ldrb    w9, [x0]
    cmp     w9, #0x2c
    b.ne    225f
    add     x0, x0, #1
    bl      lantern_jd_ws
225: str    x0, [sp, #88]
    ldr     x12, [sp, #48]
    add     x12, x12, #1
    str     x12, [sp, #48]
    b       222b
229: ldr    x13, [sp, #104]
    cbnz    x13, 2291f
    ldr     x23, [sp, #72]
2291: ldr   x0, [sp, #40]
    mov     x1, #0
    UNFRAME 160
830: mov    x0, #JSON_FAULT_LENGTH          /* the faults of this level */
    ldr     x1, [sp, #32]
    b       898f
840: mov    x0, #JSON_FAULT_MISSING
    ldr     x1, [sp, #40]
    sub     x1, x1, #1
    b       898f
850: mov    x0, #JSON_FAULT_HEX
    ldr     x1, [sp, #32]
    b       898f
860: mov    x0, #JSON_FAULT_NUMBER
    ldr     x1, [sp, #32]
    b       898f
870: mov    x0, #JSON_FAULT_TYPE
    ldr     x1, [sp, #32]
    b       898f
880: mov    x1, x0
    mov     x0, #JSON_FAULT_SYNTAX
    b       898f
890: mov    x0, #JSON_FAULT_FIELD
    ldr     x1, [sp, #88]
898: ldr    x2, [sp, #24]
    bl      lantern_jd_fault
899: UNFRAME 160
END_FUNCTION lantern_jd_value

/* (type, json, scratch, out, fault): docs/reference/beacon-api.md. */
FUNCTION lantern_json_decode
    FRAME 0
    mov     x5, #0
    bl      lantern_json_decode_mode
    UNFRAME 0
END_FUNCTION lantern_json_decode

/* (type, json, scratch, out, fault): docs/reference/engine-api.md, the Engine API's JSON. */
FUNCTION lantern_engine_json_decode
    FRAME 0
    mov     x5, #1
    bl      lantern_json_decode_mode
    UNFRAME 0
END_FUNCTION lantern_engine_json_decode

/*
 * (type, json, scratch, out, fault, mode): lantern_json_decode for mode 0, of the Beacon API's
 * JSON; lantern_engine_json_decode for mode 1, of the Engine API's: the mode at byte 56 of scratch,
 * before the field tables. Locals: L out, L+8 the root node, L+16 the mode.
 */
LOCAL_FUNCTION lantern_json_decode_mode
    ENTER 32
    str     x3, [sp, #L]
    str     x5, [sp, #(L + 16)]
    mov     x28, x4
    mov     x19, x0                         /* the type, the text and scratch, a moment */
    mov     x20, x1
    mov     x21, x2
    mov     x0, x28                         /* the fault: zero */
    mov     x1, #JSON_FAULT_SIZE
    bl      lantern_zero
    mov     x9, x19
    mov     x1, x20
    mov     x2, x21
    ldr     x10, [x2]
    MOVQ    x11, JSON_DECODE_SCRATCH
    cmp     x10, x11
    b.lo    97f
    ldr     x10, [sp, #(L + 16)]
    strb    w10, [x2, #56]
    add     x21, x2, #64                    /* the field tables: 512 bytes a level */
    ldp     x10, x11, [x1, #8]
    add     x19, x1, x10
    add     x20, x19, x11
    ldr     x10, [x9, #8]
    add     x25, x9, x10
    ldr     x10, [x9, #24]
    add     x26, x9, x10
    ldr     x10, [x9, #32]
    add     x27, x26, x10, lsl #5
    ldr     x10, [x9, #40]
    str     x10, [sp, #(L + 8)]
    mov     x24, #0                         /* first the count, with every check */
    mov     x23, #0
    mov     x0, x10
    mov     x1, x19
    mov     x2, #0
    bl      lantern_jd_value
    cbnz    x1, 98f
    bl      lantern_jd_ws
    cmp     x0, x20
    b.ne    96f
    ldr     x9, [sp, #L]                    /* then the bytes, with room for them */
    ldr     x10, [x9]
    sub     x10, x10, #24
    cmp     x23, x10
    b.hi    95f
    add     x22, x9, #24
    mov     x10, #24
    stp     x10, x23, [x9, #8]
    mov     x24, #1
    mov     x23, #0
    ldr     x0, [sp, #(L + 8)]
    mov     x1, x19
    mov     x2, #0
    bl      lantern_jd_value
    mov     x0, #LANTERN_OK
    LEAVE 32
95: str     x23, [x28, #JsonFault_size]
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
96: mov     x1, x0
    mov     x0, #JSON_FAULT_SYNTAX
    mov     x2, #0
    bl      lantern_jd_fault
98: mov     x0, #LANTERN_INVALID_JSON
    LEAVE 32
END_FUNCTION lantern_json_decode_mode

    RODATA
jd_null:
    .ascii "null"
