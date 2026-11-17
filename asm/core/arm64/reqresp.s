/*
 * Req/resp encoding, ARM64: in the common object. Requirements: docs/reference/req-resp.md.
 */

/* (id, out): the method and version of /eth2/beacon_chain/req/<name>/<version>/ssz_snappy. */
FUNCTION lantern_reqresp_protocol_parse
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #8]
    add     x2, x0, x9                      /* the bytes */
    ldr     x3, [x0, #16]
    cmp     x3, #(23 + 1 + 1 + 1 + 11)
    b.lo    9f
    ADDRESS x9, reqresp_prefix              /* the prefix */
    mov     x10, #0
1:  ldrb    w11, [x2, x10]
    ldrb    w12, [x9, x10]
    cmp     w11, w12
    b.ne    9f
    add     x10, x10, #1
    cmp     x10, #23
    b.lo    1b
    ADDRESS x9, gossip_suffix               /* /ssz_snappy at the end */
    sub     x10, x3, #11
    add     x10, x2, x10
    mov     x11, #0
2:  ldrb    w12, [x10, x11]
    ldrb    w13, [x9, x11]
    cmp     w12, w13
    b.ne    9f
    add     x11, x11, #1
    cmp     x11, #11
    b.lo    2b
    add     x4, x2, #23                     /* name / version: the version is one digit, 1 to 9 */
    sub     x5, x3, #(23 + 11 + 2)          /* the name's length */
    add     x10, x4, x5
    ldrb    w11, [x10]
    cmp     w11, #'/'
    b.ne    9f
    ldrb    w6, [x10, #1]
    sub     w6, w6, #'1'
    cmp     w6, #9
    b.hs    9f
    add     x6, x6, #1                      /* the version */
    mov     x7, #1                          /* each method in turn */
3:  sub     x9, x7, #1
    ADDRESS x10, reqresp_names
    add     x9, x10, x9, lsl #4
    ldr     x10, [x9, #8]
    and     x11, x10, #0xff                 /* the name's length */
    cmp     x11, x5
    b.ne    5f
    ldr     x12, [x9]
    ADDRESS x13, reqresp_name_bytes
    add     x12, x13, x12
    mov     x13, #0
4:  ldrb    w14, [x4, x13]
    ldrb    w15, [x12, x13]
    cmp     w14, w15
    b.ne    5f
    add     x13, x13, #1
    cmp     x13, x5
    b.lo    4b
    lsr     x10, x10, #8                    /* the method has the version */
    lsr     x10, x10, x6
    tbz     x10, #0, 9f
    stp     x7, x6, [x1]
    mov     x0, #LANTERN_OK
    ret
5:  add     x7, x7, #1
    cmp     x7, #REQRESP_METHODS
    b.ls    3b
9:  mov     x0, #LANTERN_INVALID_PROTOCOL
    ret
END_FUNCTION lantern_reqresp_protocol_parse

/* (protocol, out): /eth2/beacon_chain/req/ + name + / + version + /ssz_snappy. */
FUNCTION lantern_reqresp_protocol_id
    UNWIND_END_PROLOGUE
    ldp     x2, x3, [x0]                    /* method, version */
    sub     x9, x2, #1
    cmp     x9, #REQRESP_METHODS
    b.hs    9f
    cmp     x3, #10
    b.hs    9f
    ADDRESS x10, reqresp_names
    add     x9, x10, x9, lsl #4
    ldr     x10, [x9, #8]
    lsr     x11, x10, #8
    lsr     x11, x11, x3
    tbz     x11, #0, 9f
    and     x10, x10, #0xff
    add     x11, x10, #(23 + 2 + 11)        /* the ID's length */
    ldr     x12, [x1]
    subs    x12, x12, #24
    b.lo    8f
    cmp     x12, x11
    b.lo    8f
    mov     x12, #24
    stp     x12, x11, [x1, #8]
    add     x4, x1, #24
    ADDRESS x12, reqresp_prefix
    mov     x13, #23
1:  ldrb    w14, [x12], #1
    strb    w14, [x4], #1
    subs    x13, x13, #1
    b.ne    1b
    ldr     x12, [x9]
    ADDRESS x13, reqresp_name_bytes
    add     x12, x13, x12
2:  ldrb    w14, [x12], #1
    strb    w14, [x4], #1
    subs    x10, x10, #1
    b.ne    2b
    mov     w14, #'/'
    strb    w14, [x4], #1
    add     w14, w3, #'0'
    strb    w14, [x4], #1
    ADDRESS x12, gossip_suffix
    mov     x13, #11
3:  ldrb    w14, [x12], #1
    strb    w14, [x4], #1
    subs    x13, x13, #1
    b.ne    3b
    mov     x0, #LANTERN_OK
    ret
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    ret
9:  mov     x0, #LANTERN_INVALID_PROTOCOL
    ret
END_FUNCTION lantern_reqresp_protocol_id

/* L0: x0 = the chunk bound of x0 payload bytes: 25 + n + 8 * ceil(n / 65536); carry set on overflow. Uses x9. */
LOCAL_FUNCTION chunk_bound
    UNWIND_END_PROLOGUE
    lsr     x9, x0, #16
    tst     x0, #0xffff
    cinc    x9, x9, ne
    adds    x0, x0, #25
    b.cs    1f
    adds    x0, x0, x9, lsl #3
1:  ret
END_FUNCTION chunk_bound

FUNCTION lantern_reqresp_chunk_size
    FRAME 16
    str     x1, [sp, #16]
    ldr     x0, [x0]
    bl      chunk_bound
    b.cs    9f
    ldr     x1, [sp, #16]
    str     x0, [x1]
    mov     x0, #LANTERN_OK
    UNFRAME 16
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    UNFRAME 16
END_FUNCTION lantern_reqresp_chunk_size

/*
 * x19 header, x20 payload, x21 scratch, x22 out, x23 the payload's length, x24 the chunk bound,
 * x25 the header's length, x26 where the chunk starts, x27 the frames' ByteList in scratch.
 */
FUNCTION lantern_reqresp_write_chunk
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldr     x23, [x20, #16]
    mov     x0, x23
    bl      chunk_bound
    b.cs    8f
    mov     x24, x0
    ldp     x9, x10, [x22, #8]              /* room in out: size - offset - count */
    ldr     x11, [x22]
    subs    x11, x11, x9
    b.lo    8f
    subs    x11, x11, x10
    b.lo    8f
    cmp     x11, x24
    b.lo    8f
    MOVQ    x9, SNAPPY_SCRATCH_FRAME + 24   /* scratch: asm-snappy's, then the frames */
    adds    x9, x9, x24
    b.cs    8f
    ldr     x10, [x21]
    cmp     x10, x9
    b.lo    8f
    ldp     x9, x10, [x22, #8]
    add     x26, x22, x9
    add     x26, x26, x10
    mov     x25, #0                         /* the result byte and the context bytes of a response */
    ldr     x9, [x19, #ChunkHeader_kind]
    cbz     x9, 2f
    ldr     x9, [x19, #ChunkHeader_result]
    strb    w9, [x26], #1
    mov     x25, #1
    cbnz    x9, 2f
    ldr     x10, [x19, #ChunkHeader_context_length]
    cbz     x10, 2f
    ldr     x10, [x19, #ChunkHeader_context]
    mov     x11, #4
1:  strb    w10, [x26], #1
    lsr     x10, x10, #8
    subs    x11, x11, #1
    b.ne    1b
    add     x25, x25, #4
2:  mov     x9, x23                         /* the length as the shortest unsigned varint */
3:  cmp     x9, #0x80
    b.lo    4f
    orr     w10, w9, #0x80
    strb    w10, [x26], #1
    lsr     x9, x9, #7
    add     x25, x25, #1
    b       3b
4:  strb    w9, [x26], #1
    add     x25, x25, #1
    cbz     x23, 6f                         /* an empty payload has no frame */
    MOVQ    x9, SNAPPY_SCRATCH_FRAME
    add     x27, x21, x9
    ldr     x10, [x21]
    sub     x10, x10, x9
    str     x10, [x27]                      /* the frames' ByteList: the rest of scratch */
    str     x9, [x21]                       /* asm-snappy's scratch: its first bytes */
    mov     x0, x20
    mov     x1, x21
    mov     x2, x27
    CALL_GLOBAL snappy_frame_compress
    cbnz    x0, 8f
    mov     x0, x26                         /* the frames after the header */
    ldp     x9, x2, [x27, #8]
    add     x1, x27, x9
    add     x25, x25, x2
    bl      lantern_copy
6:  ldr     x9, [x22, #16]
    add     x9, x9, x25
    str     x9, [x22, #16]
    mov     x0, #LANTERN_OK
    LEAVE 0
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_reqresp_write_chunk

/* (input, header): x2 the bytes, x3 their count, x4 the position, x5 result, x6 context, x7 length. */
FUNCTION lantern_reqresp_read_header
    UNWIND_END_PROLOGUE
    ldp     x9, x3, [x0, #8]
    add     x2, x0, x9
    mov     x4, #0
    mov     x5, #0
    mov     x6, #0
    ldr     x9, [x1, #ChunkHeader_kind]
    cbz     x9, 2f
    cbz     x3, 7f                          /* the result byte */
    ldrb    w5, [x2]
    mov     x4, #1
    cbnz    x5, 2f
    ldr     x9, [x1, #ChunkHeader_context_length]
    cbz     x9, 2f
    cmp     x3, #5                          /* the context bytes */
    b.lo    7f
    ldrb    w6, [x2, #1]
    ldrb    w9, [x2, #2]
    orr     x6, x6, x9, lsl #8
    ldrb    w9, [x2, #3]
    orr     x6, x6, x9, lsl #16
    ldrb    w9, [x2, #4]
    orr     x6, x6, x9, lsl #24
    mov     x4, #5
2:  mov     x7, #0                          /* the varint: at most 10 bytes, at most 2^64 - 1 */
    mov     x8, #0                          /* its shift */
3:  cmp     x4, x3
    b.hs    7f
    ldrb    w9, [x2, x4]
    add     x4, x4, #1
    cmp     x8, #63
    b.eq    5f
    and     x10, x9, #0x7f
    lsl     x10, x10, x8
    orr     x7, x7, x10
    tbz     w9, #7, 6f
    add     x8, x8, #7
    b       3b
5:  cmp     x9, #1                          /* the tenth byte gives bit 63 only */
    b.hi    8f
    orr     x7, x7, x9, lsl #63
6:  str     x5, [x1, #ChunkHeader_result]
    str     x6, [x1, #ChunkHeader_context]
    str     x7, [x1, #ChunkHeader_length]
    str     x4, [x1, #ChunkHeader_header_bytes]
    mov     x0, #LANTERN_OK
    ret
7:  mov     x0, #LANTERN_REQRESP_MORE
    ret
8:  mov     x0, #LANTERN_INVALID_CHUNK
    ret
END_FUNCTION lantern_reqresp_read_header

/*
 * x19 input, x20 start, x21 length, x22 eof, x23 scratch, x24 out, x25 consumed,
 * x26 the bytes after start, x27 max_compressed_len(length), x28 the bytes read.
 * Locals: L the length, for asm-snappy.
 */
FUNCTION lantern_reqresp_read_payload
    ENTER 16
    mov     x19, x0
    ldr     x20, [x1]
    ldr     x21, [x2]
    ldr     x22, [x3]
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    str     x21, [sp, #L]
    ldr     x9, [x24]                       /* out has room for length bytes */
    subs    x9, x9, #24
    b.lo    8f
    cmp     x9, x21
    b.lo    8f
    ldr     x26, [x19, #16]
    subs    x26, x26, x20
    b.lo    9f                              /* start after the end of input */
    mov     x9, #6                          /* max_compressed_len(length) = 32 + n + n // 6, 2^64 - 1 on overflow */
    udiv    x9, x21, x9
    adds    x27, x21, #32
    b.cs    1f
    adds    x27, x27, x9
    b.cc    2f
1:  mov     x27, #-1
2:  cmp     x26, x27
    csel    x28, x26, x27, lo
    add     x9, x28, #(24 + 7)              /* scratch: a ByteList of those bytes */
    and     x9, x9, #~7
    cmp     x9, x28
    b.lo    8f
    ldr     x10, [x23]
    cmp     x10, x9
    b.lo    8f
    mov     x9, #24
    stp     x9, x28, [x23, #8]
    add     x0, x23, #24
    ldr     x9, [x19, #8]
    add     x1, x19, x9
    add     x1, x1, x20
    mov     x2, x28
    bl      lantern_copy
    mov     x0, x23
    add     x1, sp, #L
    mov     x2, x24
    mov     x3, x25
    CALL_GLOBAL snappy_frame_uncompress
    cbz     x0, 7f
    cmp     x0, #SNAPPY_BUFFER_TOO_SMALL
    b.eq    8f
    cmp     x0, #SNAPPY_TRUNCATED           /* truncated within the bound, with more bytes to come */
    b.ne    9f
    cmp     x26, x27
    b.hs    9f
    cbnz    x22, 9f
    mov     x0, #LANTERN_REQRESP_MORE
7:  LEAVE 16
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
9:  mov     x0, #LANTERN_INVALID_CHUNK
    LEAVE 16
END_FUNCTION lantern_reqresp_read_payload

/* L0: (x0 descriptor, x1 node) -> x0 min, x1 max, saturating at 2^64 - 1. x19 descriptor, x20 node, x21-x24 work. */
LOCAL_FUNCTION size_bounds
    ENTER 0
    mov     x19, x0
    ldr     x9, [x19, #SSZ_DESC_NODES_OFFSET]
    add     x20, x19, x9
    mov     x9, #SSZ_NODE_STRIDE
    madd    x20, x1, x9, x20
    ldr     x0, [x20, #SSZ_NODE_SSZ_SIZE]   /* a fixed size type */
    mov     x1, x0
    cbnz    x0, 9f
    ldr     x9, [x20, #SSZ_NODE_KIND]
    ldr     x21, [x20, #SSZ_NODE_LENGTH]
    cmp     x9, #SSZ_KIND_BIT_LIST
    b.ne    1f
    mov     x0, #1
    lsr     x1, x21, #3
    add     x1, x1, #1
    b       9f
1:  cmp     x9, #SSZ_KIND_BYTE_LIST
    b.ne    2f
    mov     x0, #0
    mov     x1, x21
    b       9f
2:  cmp     x9, #SSZ_KIND_CONTAINER
    b.eq    5f
    ldr     x22, [x20, #SSZ_NODE_ELEMENT]   /* a list or a vector: its element */
    mov     x0, x19
    mov     x1, x22
    bl      size_bounds
    ldr     x9, [x19, #SSZ_DESC_NODES_OFFSET]
    add     x10, x19, x9
    mov     x9, #SSZ_NODE_STRIDE
    madd    x10, x22, x9, x10
    ldr     x10, [x10, #SSZ_NODE_SSZ_SIZE]
    ldr     x9, [x20, #SSZ_NODE_KIND]
    cmp     x9, #SSZ_KIND_LIST
    b.ne    3f
    cbnz    x10, 4f                         /* a list: limit * (max, plus 4 for a variable element) */
    adds    x1, x1, #4
    csinv   x1, x1, xzr, cc
4:  umulh   x9, x21, x1
    mul     x1, x21, x1
    cmp     x9, #0
    csinv   x1, x1, xzr, eq
    mov     x0, #0
    b       9f
3:  adds    x0, x0, #4                      /* a vector of variable elements: length * (4 + bound) */
    csinv   x0, x0, xzr, cc
    umulh   x9, x21, x0
    mul     x0, x21, x0
    cmp     x9, #0
    csinv   x0, x0, xzr, eq
    adds    x1, x1, #4
    csinv   x1, x1, xzr, cc
    umulh   x9, x21, x1
    mul     x1, x21, x1
    cmp     x9, #0
    csinv   x1, x1, xzr, eq
    b       9f
5:  ldr     x22, [x20, #SSZ_NODE_ELEMENT]   /* a variable container: each field */
    add     x21, x22, x21
    mov     x23, #0
    mov     x24, #0
6:  cmp     x22, x21
    b.hs    8f
    ldr     x9, [x19, #SSZ_DESC_FIELDS_OFFSET]
    add     x9, x19, x9
    add     x9, x9, x22, lsl #5
    ldr     x1, [x9, #SSZ_FIELD_NODE]
    ldr     x10, [x9, #SSZ_FIELD_FLAGS]
    tbz     x10, #0, 7f
    mov     x0, x19
    bl      size_bounds                     /* a variable field: its offset and its bounds */
    adds    x0, x0, #4
    csinv   x0, x0, xzr, cc
    adds    x1, x1, #4
    csinv   x1, x1, xzr, cc
    b       10f
7:  ldr     x9, [x19, #SSZ_DESC_NODES_OFFSET]
    add     x10, x19, x9
    mov     x9, #SSZ_NODE_STRIDE
    madd    x10, x1, x9, x10
    ldr     x0, [x10, #SSZ_NODE_SSZ_SIZE]
    mov     x1, x0
10: adds    x23, x23, x0
    csinv   x23, x23, xzr, cc
    adds    x24, x24, x1
    csinv   x24, x24, xzr, cc
    add     x22, x22, #1
    b       6b
8:  mov     x0, x23
    mov     x1, x24
9:  LEAVE 0
END_FUNCTION size_bounds

FUNCTION lantern_ssz_size_bounds
    FRAME 16
    str     x1, [sp, #16]
    ldr     x1, [x0, #SSZ_DESC_ROOT]
    bl      size_bounds
    ldr     x9, [sp, #16]
    stp     x0, x1, [x9]
    mov     x0, #LANTERN_OK
    UNFRAME 16
END_FUNCTION lantern_ssz_size_bounds

REQRESP_PROTOCOL_DATA
