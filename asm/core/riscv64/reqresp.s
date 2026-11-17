/*
 * Req/resp encoding, RISC-V: in the common object. Requirements: docs/reference/req-resp.md.
 */

/* (id, out): the method and version of /eth2/beacon_chain/req/<name>/<version>/ssz_snappy. */
FUNCTION lantern_reqresp_protocol_parse
    ld      t0, 8(a0)
    add     a2, a0, t0                      # the bytes
    ld      a3, 16(a0)
    li      t0, 23 + 1 + 1 + 1 + 11
    bltu    a3, t0, 9f
    ADDRESS t0, reqresp_prefix              # the prefix
    li      t1, 0
1:  add     t2, a2, t1
    lbu     t2, 0(t2)
    add     t3, t0, t1
    lbu     t3, 0(t3)
    bne     t2, t3, 9f
    addi    t1, t1, 1
    li      t3, 23
    bltu    t1, t3, 1b
    ADDRESS t0, gossip_suffix               # /ssz_snappy at the end
    add     t1, a2, a3
    addi    t1, t1, -11
    li      t2, 0
2:  add     t3, t1, t2
    lbu     t3, 0(t3)
    add     t4, t0, t2
    lbu     t4, 0(t4)
    bne     t3, t4, 9f
    addi    t2, t2, 1
    li      t3, 11
    bltu    t2, t3, 2b
    addi    a4, a2, 23                      # name / version: the version is one digit, 1 to 9
    addi    a5, a3, -(23 + 11 + 2)          # the name's length
    add     t0, a4, a5
    lbu     t1, 0(t0)
    li      t2, '/'
    bne     t1, t2, 9f
    lbu     a6, 1(t0)
    addi    a6, a6, -'1'
    li      t2, 9
    bgeu    a6, t2, 9f
    addi    a6, a6, 1                       # the version
    li      a7, 1                           # each method in turn
3:  addi    t0, a7, -1
    slli    t0, t0, 4
    ADDRESS t1, reqresp_names
    add     t0, t0, t1
    ld      t1, 8(t0)
    andi    t2, t1, 0xff                    # the name's length
    bne     t2, a5, 5f
    ld      t2, 0(t0)
    ADDRESS t3, reqresp_name_bytes
    add     t2, t2, t3
    li      t3, 0
4:  add     t4, a4, t3
    lbu     t4, 0(t4)
    add     t5, t2, t3
    lbu     t5, 0(t5)
    bne     t4, t5, 5f
    addi    t3, t3, 1
    bltu    t3, a5, 4b
    srli    t1, t1, 8                       # the method has the version
    srl     t1, t1, a6
    andi    t1, t1, 1
    beqz    t1, 9f
    sd      a7, 0(a1)
    sd      a6, 8(a1)
    li      a0, LANTERN_OK
    ret
5:  addi    a7, a7, 1
    li      t0, REQRESP_METHODS
    bleu    a7, t0, 3b
9:  li      a0, LANTERN_INVALID_PROTOCOL
    ret
END_FUNCTION lantern_reqresp_protocol_parse

/* (protocol, out): /eth2/beacon_chain/req/ + name + / + version + /ssz_snappy. */
FUNCTION lantern_reqresp_protocol_id
    ld      a2, 0(a0)                       # method
    ld      a3, 8(a0)                       # version
    addi    t0, a2, -1
    li      t1, REQRESP_METHODS
    bgeu    t0, t1, 9f
    li      t1, 10
    bgeu    a3, t1, 9f
    slli    t0, t0, 4
    ADDRESS t1, reqresp_names
    add     a4, t0, t1                      # the entry
    ld      t0, 8(a4)
    srli    t1, t0, 8
    srl     t1, t1, a3
    andi    t1, t1, 1
    beqz    t1, 9f
    andi    a5, t0, 0xff                    # the name's length
    addi    a6, a5, 23 + 2 + 11             # the ID's length
    ld      t0, 0(a1)
    li      t1, 24
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    bltu    t0, a6, 8f
    sd      t1, 8(a1)
    sd      a6, 16(a1)
    addi    a7, a1, 24
    ADDRESS t0, reqresp_prefix
    li      t1, 23
1:  lbu     t2, 0(t0)
    sb      t2, 0(a7)
    addi    t0, t0, 1
    addi    a7, a7, 1
    addi    t1, t1, -1
    bnez    t1, 1b
    ld      t0, 0(a4)
    ADDRESS t1, reqresp_name_bytes
    add     t0, t0, t1
2:  lbu     t2, 0(t0)
    sb      t2, 0(a7)
    addi    t0, t0, 1
    addi    a7, a7, 1
    addi    a5, a5, -1
    bnez    a5, 2b
    li      t2, '/'
    sb      t2, 0(a7)
    addi    t2, a3, '0'
    sb      t2, 1(a7)
    addi    a7, a7, 2
    ADDRESS t0, gossip_suffix
    li      t1, 11
3:  lbu     t2, 0(t0)
    sb      t2, 0(a7)
    addi    t0, t0, 1
    addi    a7, a7, 1
    addi    t1, t1, -1
    bnez    t1, 3b
    li      a0, LANTERN_OK
    ret
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    ret
9:  li      a0, LANTERN_INVALID_PROTOCOL
    ret
END_FUNCTION lantern_reqresp_protocol_id

/* L0: a0 = the chunk bound of a0 payload bytes: 25 + n + 8 * ceil(n / 65536); a1 = 1 on overflow, else 0. Uses t0, t1. */
LOCAL_FUNCTION chunk_bound
    UNWIND_END_PROLOGUE
    srli    t0, a0, 16
    slli    t1, a0, 48
    snez    t1, t1
    add     t0, t0, t1
    slli    t0, t0, 3
    addi    t1, a0, 25
    li      a1, 1
    bltu    t1, a0, 1f
    add     a0, t1, t0
    sltu    a1, a0, t1
1:  ret
END_FUNCTION chunk_bound

FUNCTION lantern_reqresp_chunk_size
    FRAME 16
    sd      a1, F(sp)
    ld      a0, 0(a0)
    call    chunk_bound
    bnez    a1, 9f
    ld      a1, F(sp)
    sd      a0, 0(a1)
    li      a0, LANTERN_OK
    UNFRAME 16
9:  li      a0, LANTERN_INVALID_OVERFLOW
    UNFRAME 16
END_FUNCTION lantern_reqresp_chunk_size

/*
 * s1 header, s2 payload, s3 scratch, s4 out, s5 the payload's length, s6 the header's length,
 * s7 where the chunk starts, s8 the frames' ByteList in scratch.
 */
FUNCTION lantern_reqresp_write_chunk
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      s5, 16(s2)
    mv      a0, s5
    call    chunk_bound
    bnez    a1, 8f
    ld      t0, 0(s4)                       # room in out: size - offset - count
    ld      t1, 8(s4)
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    ld      t1, 16(s4)
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    bltu    t0, a0, 8f
    li      t1, SNAPPY_SCRATCH_FRAME + 24   # scratch: asm-snappy's, then the frames
    add     t2, a0, t1
    bltu    t2, a0, 8f
    ld      t0, 0(s3)
    bltu    t0, t2, 8f
    ld      t0, 8(s4)
    ld      t1, 16(s4)
    add     s7, s4, t0
    add     s7, s7, t1                      # where the chunk starts
    li      s6, 0                           # the result byte and the context bytes of a response
    ld      t0, ChunkHeader_kind(s1)
    beqz    t0, 2f
    ld      t0, ChunkHeader_result(s1)
    sb      t0, 0(s7)
    addi    s7, s7, 1
    li      s6, 1
    bnez    t0, 2f
    ld      t1, ChunkHeader_context_length(s1)
    beqz    t1, 2f
    ld      t1, ChunkHeader_context(s1)
    li      t2, 4
1:  sb      t1, 0(s7)
    srli    t1, t1, 8
    addi    s7, s7, 1
    addi    t2, t2, -1
    bnez    t2, 1b
    addi    s6, s6, 4
2:  mv      t0, s5                          # the length as the shortest unsigned varint
    li      t2, 0x80
3:  bltu    t0, t2, 4f
    ori     t1, t0, 0x80
    sb      t1, 0(s7)
    srli    t0, t0, 7
    addi    s7, s7, 1
    addi    s6, s6, 1
    j       3b
4:  sb      t0, 0(s7)
    addi    s7, s7, 1
    addi    s6, s6, 1
    beqz    s5, 6f                          # an empty payload has no frame
    li      t0, SNAPPY_SCRATCH_FRAME
    add     s8, s3, t0
    ld      t1, 0(s3)
    sub     t1, t1, t0
    sd      t1, 0(s8)                       # the frames' ByteList: the rest of scratch
    sd      t0, 0(s3)                       # asm-snappy's scratch: its first bytes
    mv      a0, s2
    mv      a1, s3
    mv      a2, s8
    CALL_GLOBAL snappy_frame_compress
    bnez    a0, 8f
    mv      a0, s7                          # the frames after the header
    ld      t0, 8(s8)
    add     a1, s8, t0
    ld      a2, 16(s8)
    add     s6, s6, a2
    call    lantern_copy
6:  ld      t0, 16(s4)
    add     t0, t0, s6
    sd      t0, 16(s4)
    li      a0, LANTERN_OK
    LEAVE 0
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_reqresp_write_chunk

/* (input, header): a2 the bytes, a3 their count, a4 the position, a5 result, a6 context, a7 length, t6 shift. */
FUNCTION lantern_reqresp_read_header
    ld      t0, 8(a0)
    add     a2, a0, t0
    ld      a3, 16(a0)
    li      a4, 0
    li      a5, 0
    li      a6, 0
    ld      t0, ChunkHeader_kind(a1)
    beqz    t0, 2f
    beqz    a3, 7f                          # the result byte
    lbu     a5, 0(a2)
    li      a4, 1
    bnez    a5, 2f
    ld      t0, ChunkHeader_context_length(a1)
    beqz    t0, 2f
    li      t0, 5                           # the context bytes
    bltu    a3, t0, 7f
    lbu     a6, 1(a2)
    lbu     t0, 2(a2)
    slli    t0, t0, 8
    or      a6, a6, t0
    lbu     t0, 3(a2)
    slli    t0, t0, 16
    or      a6, a6, t0
    lbu     t0, 4(a2)
    slli    t0, t0, 24
    or      a6, a6, t0
    li      a4, 5
2:  li      a7, 0                           # the varint: at most 10 bytes, at most 2^64 - 1
    li      t6, 0
3:  bgeu    a4, a3, 7f
    add     t0, a2, a4
    lbu     t0, 0(t0)
    addi    a4, a4, 1
    li      t1, 63
    beq     t6, t1, 5f
    andi    t1, t0, 0x7f
    sll     t1, t1, t6
    or      a7, a7, t1
    andi    t1, t0, 0x80
    beqz    t1, 6f
    addi    t6, t6, 7
    j       3b
5:  li      t1, 1                           # the tenth byte gives bit 63 only
    bltu    t1, t0, 8f
    slli    t0, t0, 63
    or      a7, a7, t0
6:  sd      a5, ChunkHeader_result(a1)
    sd      a6, ChunkHeader_context(a1)
    sd      a7, ChunkHeader_length(a1)
    sd      a4, ChunkHeader_header_bytes(a1)
    li      a0, LANTERN_OK
    ret
7:  li      a0, LANTERN_REQRESP_MORE
    ret
8:  li      a0, LANTERN_INVALID_CHUNK
    ret
END_FUNCTION lantern_reqresp_read_header

/*
 * s1 input, s2 start, s3 length, s4 eof, s5 scratch, s6 out, s7 consumed,
 * s8 the bytes after start, s9 max_compressed_len(length). Locals: L the length, for asm-snappy.
 */
FUNCTION lantern_reqresp_read_payload
    ENTER 16
    mv      s1, a0
    ld      s2, 0(a1)
    ld      s3, 0(a2)
    ld      s4, 0(a3)
    mv      s5, a4
    mv      s6, a5
    mv      s7, a6
    sd      s3, L(sp)
    ld      t0, 0(s6)                       # out has room for length bytes
    li      t1, 24
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    bltu    t0, s3, 8f
    ld      t0, 16(s1)
    bltu    t0, s2, 9f                      # start after the end of input
    sub     s8, t0, s2
    li      t0, 6                           # max_compressed_len(length), 2^64 - 1 on overflow
    divu    t0, s3, t0
    addi    t1, s3, 32
    bltu    t1, s3, 1f
    add     s9, t1, t0
    bgeu    s9, t1, 2f
1:  li      s9, -1
2:  mv      a2, s8                          # the bytes read: the fewer of the two
    bltu    a2, s9, 3f
    mv      a2, s9
3:  addi    t0, a2, 24 + 7                  # scratch: a ByteList of those bytes
    andi    t0, t0, -8
    bltu    t0, a2, 8f
    ld      t1, 0(s5)
    bltu    t1, t0, 8f
    li      t0, 24
    sd      t0, 8(s5)
    sd      a2, 16(s5)
    addi    a0, s5, 24
    ld      t0, 8(s1)
    add     a1, s1, t0
    add     a1, a1, s2
    call    lantern_copy
    mv      a0, s5
    addi    a1, sp, L
    mv      a2, s6
    mv      a3, s7
    CALL_GLOBAL snappy_frame_uncompress
    beqz    a0, 7f
    li      t0, SNAPPY_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    li      t0, SNAPPY_TRUNCATED            # truncated within the bound, with more bytes to come
    bne     a0, t0, 9f
    bgeu    s8, s9, 9f
    bnez    s4, 9f
    li      a0, LANTERN_REQRESP_MORE
7:  LEAVE 16
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
9:  li      a0, LANTERN_INVALID_CHUNK
    LEAVE 16
END_FUNCTION lantern_reqresp_read_payload

/* dst = dst + src, or 2^64 - 1 on overflow. Uses t5. */
.macro SAT_ADD dst, src
    add     t5, \dst, \src
    bgeu    t5, \dst, 91f
    li      t5, -1
91: mv      \dst, t5
.endm

/* dst = dst * src, or 2^64 - 1 on overflow. Uses t5. */
.macro SAT_MUL dst, src
    mulhu   t5, \dst, \src
    mul     \dst, \dst, \src
    beqz    t5, 92f
    li      \dst, -1
92:
.endm

/*
 * L0: (a0 descriptor, a1 node) -> a0 min, a1 max, saturating at 2^64 - 1.
 * s1 descriptor, s2 node, s3 length or the last field, s4 element or field, s5 min, s6 max.
 */
LOCAL_FUNCTION size_bounds
    ENTER 0
    mv      s1, a0
    li      t0, SSZ_NODE_STRIDE
    mul     s2, a1, t0
    ld      t0, SSZ_DESC_NODES_OFFSET(s1)
    add     s2, s2, t0
    add     s2, s2, s1
    ld      a0, SSZ_NODE_SSZ_SIZE(s2)       # a fixed size type
    mv      a1, a0
    bnez    a0, 9f
    ld      s3, SSZ_NODE_LENGTH(s2)
    ld      t0, SSZ_NODE_KIND(s2)
    li      t1, SSZ_KIND_BIT_LIST
    bne     t0, t1, 1f
    li      a0, 1
    srli    a1, s3, 3
    addi    a1, a1, 1
    j       9f
1:  li      t1, SSZ_KIND_BYTE_LIST
    bne     t0, t1, 2f
    li      a0, 0
    mv      a1, s3
    j       9f
2:  li      t1, SSZ_KIND_CONTAINER
    beq     t0, t1, 5f
    ld      s4, SSZ_NODE_ELEMENT(s2)        # a list or a vector: its element
    mv      a0, s1
    mv      a1, s4
    call    size_bounds
    mv      s5, a0
    mv      s6, a1
    li      t0, SSZ_NODE_STRIDE
    mul     t0, s4, t0
    ld      t1, SSZ_DESC_NODES_OFFSET(s1)
    add     t0, t0, t1
    add     t0, t0, s1
    ld      s4, SSZ_NODE_SSZ_SIZE(t0)       # the element's fixed size, or 0
    ld      t0, SSZ_NODE_KIND(s2)
    li      t1, SSZ_KIND_LIST
    bne     t0, t1, 3f
    bnez    s4, 4f                          # a list: limit * (max, plus 4 for a variable element)
    li      t0, 4
    SAT_ADD s6, t0
4:  SAT_MUL s6, s3
    li      a0, 0
    mv      a1, s6
    j       9f
3:  li      t0, 4                           # a vector of variable elements: length * (4 + bound)
    SAT_ADD s5, t0
    SAT_MUL s5, s3
    SAT_ADD s6, t0
    SAT_MUL s6, s3
    mv      a0, s5
    mv      a1, s6
    j       9f
5:  ld      s4, SSZ_NODE_ELEMENT(s2)        # a variable container: each field
    add     s3, s4, s3
    li      s5, 0
    li      s6, 0
6:  bgeu    s4, s3, 8f
    slli    t0, s4, 5
    ld      t1, SSZ_DESC_FIELDS_OFFSET(s1)
    add     t0, t0, t1
    add     t0, t0, s1
    ld      a1, SSZ_FIELD_NODE(t0)
    ld      t1, SSZ_FIELD_FLAGS(t0)
    andi    t1, t1, SSZ_FIELD_VARIABLE
    beqz    t1, 7f
    mv      a0, s1
    call    size_bounds                     # a variable field: its offset and its bounds
    li      t0, 4
    SAT_ADD a0, t0
    SAT_ADD a1, t0
    SAT_ADD s5, a0
    SAT_ADD s6, a1
    addi    s4, s4, 1
    j       6b
7:  li      t0, SSZ_NODE_STRIDE             # a fixed field
    mul     t0, a1, t0
    ld      t1, SSZ_DESC_NODES_OFFSET(s1)
    add     t0, t0, t1
    add     t0, t0, s1
    ld      t0, SSZ_NODE_SSZ_SIZE(t0)
    SAT_ADD s5, t0
    SAT_ADD s6, t0
    addi    s4, s4, 1
    j       6b
8:  mv      a0, s5
    mv      a1, s6
9:  LEAVE 0
END_FUNCTION size_bounds

FUNCTION lantern_ssz_size_bounds
    FRAME 16
    sd      a1, F(sp)
    ld      a1, SSZ_DESC_ROOT(a0)
    call    size_bounds
    ld      t0, F(sp)
    sd      a0, 0(t0)
    sd      a1, 8(t0)
    li      a0, LANTERN_OK
    UNFRAME 16
END_FUNCTION lantern_ssz_size_bounds

REQRESP_PROTOCOL_DATA
