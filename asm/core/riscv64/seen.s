/*
 * Sizing, making and growing Seen, RISC-V: it reads no fork's layouts.
 * Requirements: docs/reference/networking.md.
 */

.if SeenKey__mem != 32 || SeenBits__mem != 320 || SeenBlock__mem != 40 || SEEN_BITS_BYTES * 8 < MAX_VALIDATORS_PER_COMMITTEE || SEEN_BITS_BYTES * 8 < SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT
.error "the gossip code assumes the Seen layouts of include/lantern.inc"
.endif

/* Copy the entries of stride bytes of part ref of seen s1 into out s3, and set the part's count. Uses s4. */
.macro SEEN_PART_COPY ref, stride
    PART    a1, s4, s1, \ref
    LDQ     a0, s3, \ref
    add     a0, s3, a0
    li      t0, \stride
    mul     a2, s4, t0
    call    lantern_copy
    STQ     s4, s3, (\ref) + 8
.endm

LEAF lantern_seen_size
    ld      t0, SeenRoom_keys(a0)
    ld      t1, SeenRoom_bits(a0)
    ld      t2, SeenRoom_blocks(a0)
    ld      t3, SeenRoom_header_bytes(a0)
    li      t4, SEEN_FIXED
    srli    t5, t0, 59                      # keys * 32 fits
    bnez    t5, 9f
    slli    t5, t0, 5
    add     t6, t4, t5
    bltu    t6, t4, 9f
    mv      t4, t6
    li      t5, SeenBits__mem
    mulhu   t6, t1, t5
    bnez    t6, 9f
    mul     t5, t1, t5
    add     t6, t4, t5
    bltu    t6, t4, 9f
    mv      t4, t6
    li      t5, SeenBlock__mem
    mulhu   t6, t2, t5
    bnez    t6, 9f
    mul     t5, t2, t5
    add     t6, t4, t5
    bltu    t6, t4, 9f
    add     t5, t6, t3
    bltu    t5, t6, 9f
    sd      t5, 0(a1)
    li      a0, LANTERN_OK
    ret
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_seen_size

/* Locals: sp+0 room, sp+8 seen, sp+16 size. */
FUNCTION lantern_seen_init
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    addi    a1, sp, 16
    call    lantern_seen_size
    bnez    a0, 9f
    ld      a0, 0(sp)
    ld      a1, 8(sp)
    ld      t0, 16(sp)
    ld      t1, 0(a1)
    bltu    t1, t0, 9f
    li      t0, SEEN_FIXED                  # each part empty, at the offsets of room's capacities
    sd      t0, Seen_keys(a1)
    sd      zero, (Seen_keys + 8)(a1)
    ld      t1, SeenRoom_keys(a0)
    slli    t1, t1, 5
    add     t0, t0, t1
    sd      t0, Seen_bits(a1)
    sd      zero, (Seen_bits + 8)(a1)
    ld      t1, SeenRoom_bits(a0)
    li      t2, SeenBits__mem
    mul     t1, t1, t2
    add     t0, t0, t1
    sd      t0, Seen_blocks(a1)
    sd      zero, (Seen_blocks + 8)(a1)
    ld      t1, SeenRoom_blocks(a0)
    li      t2, SeenBlock__mem
    mul     t1, t1, t2
    add     t0, t0, t1
    sd      t0, Seen_headers(a1)
    sd      zero, (Seen_headers + 8)(a1)
    sd      zero, Seen_header_bytes(a1)
    li      a0, LANTERN_OK
    UNFRAME 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    UNFRAME 32
END_FUNCTION lantern_seen_init

/* s1 seen, s2 room, s3 out, s4 count. */
FUNCTION lantern_seen_copy
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      t0, SeenRoom_keys(s2)           # each capacity holds what seen holds
    ld      t1, (Seen_keys + 8)(s1)
    bltu    t0, t1, 9f
    ld      t0, SeenRoom_bits(s2)
    ld      t1, (Seen_bits + 8)(s1)
    bltu    t0, t1, 9f
    ld      t0, SeenRoom_blocks(s2)
    ld      t1, (Seen_blocks + 8)(s1)
    bltu    t0, t1, 9f
    ld      t0, SeenRoom_header_bytes(s2)
    ld      t1, Seen_header_bytes(s1)
    bltu    t0, t1, 9f
    mv      a0, s2
    mv      a1, s3
    call    lantern_seen_init
    bnez    a0, 7f
    SEEN_PART_COPY Seen_keys, SeenKey__mem
    SEEN_PART_COPY Seen_bits, SeenBits__mem
    SEEN_PART_COPY Seen_blocks, SeenBlock__mem
    SEEN_PART_COPY Seen_headers, 0
    ld      a1, Seen_headers(s1)            # the headers: their bytes in use
    add     a1, s1, a1
    ld      a0, Seen_headers(s3)
    add     a0, s3, a0
    ld      a2, Seen_header_bytes(s1)
    sd      a2, Seen_header_bytes(s3)
    call    lantern_copy
    li      a0, LANTERN_OK
7:  LEAVE 0
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_seen_copy

/* Locals: sp+0 seen, sp+8 root, sp+16 payload_status. */
FUNCTION lantern_seen_add_block
    FRAME 32
    ld      a2, 0(a2)
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    call    seen_find_block
    bnez    a0, 2f
    ld      a0, 0(sp)
    ld      a1, 8(sp)
    PART    t0, t1, a0, Seen_blocks         # room for one more
    ld      t2, Seen_headers(a0)
    ld      t3, Seen_blocks(a0)
    sub     t2, t2, t3
    li      t3, SeenBlock__mem
    divu    t2, t2, t3
    bgeu    t1, t2, 9f
    mul     t2, t1, t3
    add     t0, t0, t2
    addi    t1, t1, 1
    sd      t1, (Seen_blocks + 8)(a0)
    COPY32  t0, a1
    mv      a0, t0
2:  ld      a2, 16(sp)
    sd      a2, SeenBlock_payload_status(a0)
    li      a0, LANTERN_OK
    UNFRAME 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    UNFRAME 32
END_FUNCTION lantern_seen_add_block
