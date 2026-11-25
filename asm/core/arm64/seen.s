/*
 * Sizing, making and growing Seen, ARM64: it reads no fork's layouts.
 * Requirements: docs/reference/networking.md.
 */

.if SeenKey__mem != 32 || SeenBits__mem != 320 || SeenBlock__mem != 40 || SEEN_BITS_BYTES * 8 < MAX_VALIDATORS_PER_COMMITTEE || SEEN_BITS_BYTES * 8 < SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT
.error "the gossip code assumes the Seen layouts of include/lantern.inc"
.endif

/* L0: copy the count entries of stride x3 of part x2 of seen x19 into out x21, and set the part's count. */
.macro SEEN_PART_COPY ref, stride
    PART    x1, x22, x19, \ref
    LDQ     x0, x21, \ref
    add     x0, x21, x0
    mov     x9, #\stride
    mul     x2, x22, x9
    bl      lantern_copy
    STQ     x22, x21, (\ref) + 8
.endm

LEAF lantern_seen_size
    ldp     x2, x3, [x0, #SeenRoom_keys]
    ldp     x4, x5, [x0, #SeenRoom_blocks]
    MOVQ    x6, SEEN_FIXED
    lsr     x7, x2, #59                     /* keys * 32 fits */
    cbnz    x7, 9f
    adds    x6, x6, x2, lsl #5
    b.cs    9f
    mov     x7, #SeenBits__mem
    umulh   x8, x3, x7
    cbnz    x8, 9f
    mul     x8, x3, x7
    adds    x6, x6, x8
    b.cs    9f
    mov     x7, #SeenBlock__mem
    umulh   x8, x4, x7
    cbnz    x8, 9f
    mul     x8, x4, x7
    adds    x6, x6, x8
    b.cs    9f
    adds    x6, x6, x5
    b.cs    9f
    str     x6, [x1]
    RETURN_OK
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_seen_size

/* Locals: sp+16 room, sp+24 seen, sp+32 size. */
FUNCTION lantern_seen_init
    FRAME 32
    stp     x0, x1, [sp, #16]
    add     x1, sp, #32
    bl      lantern_seen_size
    cbnz    x0, 9f
    ldp     x0, x1, [sp, #16]
    ldr     x9, [sp, #32]
    ldr     x10, [x1]
    cmp     x10, x9
    b.lo    9f
    MOVQ    x9, SEEN_FIXED                  /* each part empty, at the offsets of room's capacities */
    stp     x9, xzr, [x1, #Seen_keys]
    ldr     x10, [x0, #SeenRoom_keys]
    add     x9, x9, x10, lsl #5
    stp     x9, xzr, [x1, #Seen_bits]
    ldr     x10, [x0, #SeenRoom_bits]
    mov     x11, #SeenBits__mem
    madd    x9, x10, x11, x9
    stp     x9, xzr, [x1, #Seen_blocks]
    ldr     x10, [x0, #SeenRoom_blocks]
    mov     x11, #SeenBlock__mem
    madd    x9, x10, x11, x9
    stp     x9, xzr, [x1, #Seen_headers]
    str     xzr, [x1, #Seen_header_bytes]
    mov     x0, #LANTERN_OK
    UNFRAME 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 32
END_FUNCTION lantern_seen_init

/* x19 seen, x20 room, x21 out, x22 count. */
FUNCTION lantern_seen_copy
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x9, [x20, #SeenRoom_keys]       /* each capacity holds what seen holds */
    ldr     x10, [x19, #(Seen_keys + 8)]
    cmp     x9, x10
    b.lo    9f
    ldr     x9, [x20, #SeenRoom_bits]
    ldr     x10, [x19, #(Seen_bits + 8)]
    cmp     x9, x10
    b.lo    9f
    ldr     x9, [x20, #SeenRoom_blocks]
    ldr     x10, [x19, #(Seen_blocks + 8)]
    cmp     x9, x10
    b.lo    9f
    ldr     x9, [x20, #SeenRoom_header_bytes]
    ldr     x10, [x19, #Seen_header_bytes]
    cmp     x9, x10
    b.lo    9f
    mov     x0, x20
    mov     x1, x21
    bl      lantern_seen_init
    cbnz    x0, 7f
    SEEN_PART_COPY Seen_keys, SeenKey__mem
    SEEN_PART_COPY Seen_bits, SeenBits__mem
    SEEN_PART_COPY Seen_blocks, SeenBlock__mem
    SEEN_PART_COPY Seen_headers, 0
    LDQ     x1, x19, Seen_headers           /* the headers: their bytes in use */
    add     x1, x19, x1
    LDQ     x0, x21, Seen_headers
    add     x0, x21, x0
    ldr     x2, [x19, #Seen_header_bytes]
    str     x2, [x21, #Seen_header_bytes]
    bl      lantern_copy
    mov     x0, #LANTERN_OK
7:  LEAVE 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_seen_copy

/* Locals: sp+16 seen, sp+24 root, sp+32 payload_status. */
FUNCTION lantern_seen_add_block
    FRAME 32
    ldr     x2, [x2]
    stp     x0, x1, [sp, #16]
    str     x2, [sp, #32]
    bl      lantern_seen_find_block
    cbnz    x0, 2f
    ldp     x0, x1, [sp, #16]
    PART    x9, x10, x0, Seen_blocks        /* room for one more */
    ldr     x11, [x0, #Seen_headers]
    ldr     x12, [x0, #Seen_blocks]
    sub     x11, x11, x12
    mov     x12, #SeenBlock__mem
    udiv    x11, x11, x12
    cmp     x10, x11
    b.hs    9f
    madd    x9, x10, x12, x9
    add     x10, x10, #1
    str     x10, [x0, #(Seen_blocks + 8)]
    COPY32  x9, x1
    mov     x0, x9
2:  ldr     x2, [sp, #32]
    str     x2, [x0, #SeenBlock_payload_status]
    mov     x0, #LANTERN_OK
    UNFRAME 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 32
END_FUNCTION lantern_seen_add_block
