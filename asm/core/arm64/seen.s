/*
 * Sizing, making, growing and pruning Seen, ARM64: it reads no fork's layouts.
 * Requirements: docs/reference/networking.md.
 */

.if SeenKey__mem != 32 || SeenBits__mem != 320 || SeenBlock__mem != 40 || SEEN_BITS_BYTES * 8 < MAX_VALIDATORS_PER_COMMITTEE || SEEN_BITS_BYTES * 8 < SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT
.error "the gossip code assumes the Seen layouts of include/lantern.inc"
.endif

/* Copy the count entries of stride x3 of part x2 of seen x19 into out x21, and set the part's count. */
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

/*
 * Drop the entries of past epochs and slots from seen x0, with the time and the finalized epoch of
 * store x1 (networking.md). A leaf; uses x2-x14. x8 the first epoch kept, x9 the first sync slot
 * kept, x10 the finalized slot; x4 the entry read, x6 the entry written, x5 the entries left.
 */
LEAF lantern_seen_prune
    ldr     x2, [x1, #Store_time_ms]        /* s: the current slot, 0 before genesis */
    ldr     x3, [x1, #Store_genesis_time_ms]
    subs    x2, x2, x3
    csel    x2, xzr, x2, lo
    ldr     x3, [x1, #(Store_config + CONFIG_SLOT_DURATION_MS)]
    udiv    x2, x2, x3
    subs    x9, x2, #1                      /* the first sync slot kept: s - 1 */
    csel    x9, xzr, x9, lo
    ldr     x3, [x1, #(Store_config + CONFIG_ATTESTATION_PROPAGATION_SLOT_RANGE)]
    subs    x2, x2, x3
    csel    x2, xzr, x2, lo
    subs    x2, x2, #1
    csel    x2, xzr, x2, lo
    mov     x3, #SLOTS_PER_EPOCH            /* e: the epoch of s - range - 1 */
    udiv    x2, x2, x3
    subs    x8, x2, #1                      /* the first epoch kept: e - 1 */
    csel    x8, xzr, x8, lo
    ldr     x2, [x1, #Store_finalized_checkpoint]   /* f: the first slot of the finalized epoch */
    umulh   x4, x2, x3
    mul     x10, x2, x3
    cmp     x4, #0
    csinv   x10, x10, xzr, eq
    PART    x4, x5, x0, Seen_keys           /* the keys */
    mov     x6, x4
10: cbz     x5, 19f
    ldp     x11, x12, [x4]
    cmp     x11, #SEEN_ATTESTATION
    b.eq    11f
    cmp     x11, #SEEN_AGGREGATOR_EPOCH
    b.eq    11f
    cmp     x11, #SEEN_PROPOSER_SLOT
    b.eq    12f
    cmp     x11, #SEEN_DATA_COLUMN
    b.eq    12f
    cmp     x11, #SEEN_BLOB_SIDECAR
    b.eq    12f
    cmp     x11, #SEEN_SYNC_CONTRIBUTION
    b.eq    13f
    cmp     x11, #SEEN_SYNC_MESSAGE
    b.ne    15f
13: cmp     x12, x9                         /* a sync slot: kept from s - 1 */
    b.lo    16f
    b       15f
11: cmp     x12, x8                         /* an epoch: kept from the first epoch kept */
    b.lo    16f
    b       15f
12: cmp     x12, x10                        /* a block's slot: kept above f */
    b.ls    16f
15: cmp     x4, x6                          /* kept: moved down over the dropped ones */
    b.eq    14f
    ldp     x11, x12, [x4]
    ldp     x13, x14, [x4, #16]
    stp     x11, x12, [x6]
    stp     x13, x14, [x6, #16]
14: add     x6, x6, #SeenKey__mem
16: add     x4, x4, #SeenKey__mem
    sub     x5, x5, #1
    b       10b
19: ldr     x11, [x0, #Seen_keys]           /* the count: the entries written */
    add     x11, x0, x11
    sub     x6, x6, x11
    lsr     x6, x6, #5
    str     x6, [x0, #(Seen_keys + 8)]
    PART    x4, x5, x0, Seen_bits           /* the bits */
    mov     x6, x4
20: cbz     x5, 29f
    ldr     x11, [x4, #SeenBits_kind]
    cmp     x11, #SEEN_AGGREGATE
    b.ne    21f
    ldr     x12, [x4, #SeenBits_b]          /* an aggregate: its target epoch kept from the first epoch kept */
    cmp     x12, x8
    b.lo    26f
    b       25f
21: cmp     x11, #SEEN_CONTRIBUTION
    b.ne    25f
    ldr     x12, [x4, #SeenBits_a]          /* a contribution: its slot kept from s - 1 */
    cmp     x12, x9
    b.lo    26f
25: cmp     x4, x6
    b.eq    23f
    mov     x7, #0
24: add     x13, x4, x7
    ldp     x11, x12, [x13]
    add     x14, x6, x7
    stp     x11, x12, [x14]
    add     x7, x7, #16
    cmp     x7, #SeenBits__mem
    b.lo    24b
23: add     x6, x6, #SeenBits__mem
26: add     x4, x4, #SeenBits__mem
    sub     x5, x5, #1
    b       20b
29: ldr     x11, [x0, #Seen_bits]
    add     x11, x0, x11
    sub     x6, x6, x11
    mov     x12, #SeenBits__mem
    udiv    x6, x6, x12
    str     x6, [x0, #(Seen_bits + 8)]
    mov     x0, #LANTERN_OK
    ret
END_FUNCTION lantern_seen_prune
