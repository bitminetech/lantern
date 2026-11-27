/*
 * Sizing, making, growing and archiving Seen, ARM64: it reads no fork's layouts.
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

/* dst = the slots of the index of a Seen of keys keys: the smallest power of two at or above 2 * keys. Uses t. */
.macro SEEN_SLOTS dst, keys, t
    lsl     \t, \keys, #1
    mov     \dst, #1
100: cmp    \dst, \t
    b.hs    101f
    lsl     \dst, \dst, #1
    b       100b
101:
.endm

LEAF lantern_seen_size
    ldp     x2, x3, [x0, #SeenRoom_keys]
    ldp     x4, x5, [x0, #SeenRoom_blocks]
    MOVQ    x6, SEEN_FIXED
    lsr     x7, x2, #31                     /* below SEEN_KEYS_MAX: the index, 4 bytes a slot, whole words */
    cbnz    x7, 9f
    SEEN_SLOTS x7, x2, x8
    lsl     x7, x7, #2
    add     x7, x7, #7
    and     x7, x7, #-8
    add     x6, x6, x7
    add     x6, x6, x2, lsl #5              /* keys * 32 */
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
    ldr     x10, [x0, #SeenRoom_keys]       /* each part empty, at the offsets of room's capacities: the index */
    SEEN_SLOTS x11, x10, x12
    MOVQ    x9, SEEN_FIXED
    stp     x9, x11, [x1, #Seen_index]
    lsl     x11, x11, #2
    add     x11, x11, #(SEEN_FIXED + 7)
    and     x9, x11, #-8
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
    ldr     x9, [x1]                        /* every byte of the parts zero */
    sub     x9, x9, #SEEN_FIXED
    add     x0, x1, #SEEN_FIXED
    mov     x1, x9
    bl      lantern_zero
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
    mov     x0, x21                         /* the index of its keys */
    bl      lantern_seen_index
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
 * The floors of store x1 (networking.md, lantern_seen_archive): x8 the first epoch kept, x9 the first
 * sync slot kept, x10 the finalized slot. A leaf; uses x2-x4.
 */
LOCAL_FUNCTION lantern_seen_floors
    UNWIND_END_PROLOGUE
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
    ret
END_FUNCTION lantern_seen_floors

/* dst = the bytes of an entry of HIST kind k: 16, 24, or HistBits__mem. */
.macro HIST_ELEM dst, k
    mov     \dst, #16
    cmp     \k, #HIST_COLUMN
    b.lo    104f
    mov     \dst, #24
    cmp     \k, #HIST_AGGREGATE
    b.lo    104f
    mov     \dst, #HistBits__mem
104:
.endm

/* Branch to less when the first x3 words of the record at a are below those at b, else to notless. Uses x11-x13. */
.macro SORT_LESS a, b, less, notless
    mov     x12, #0
101: cmp    x12, x3
    b.hs    \notless
    ldr     x11, [\a, x12, lsl #3]
    ldr     x13, [\b, x12, lsl #3]
    cmp     x11, x13
    b.lo    \less
    b.hi    \notless
    add     x12, x12, #1
    b       101b
.endm

/* Swap the x2 words of the records at a and b. Uses x11-x13. */
.macro SORT_SWAP a, b
    mov     x12, #0
102: cmp    x12, x2
    b.hs    103f
    ldr     x11, [\a, x12, lsl #3]
    ldr     x13, [\b, x12, lsl #3]
    str     x13, [\a, x12, lsl #3]
    str     x11, [\b, x12, lsl #3]
    add     x12, x12, #1
    b       102b
103:
.endm

/*
 * Sort the x1 records of x2 words at x0 by their first x3 words, unsigned and in word order: a heapsort.
 * A leaf; uses x4-x15. x15 the record bytes, x14 0 while the heap is built, x5 the root, x6 the end,
 * x8 a child.
 */
LOCAL_FUNCTION lantern_seen_sort
    UNWIND_END_PROLOGUE
    cmp     x1, #2
    b.lo    9f
    lsl     x15, x2, #3
    lsr     x4, x1, #1
    mov     x14, #0
1:  cbz     x4, 2f                          /* the heap: each inner node from the last */
    sub     x4, x4, #1
    mov     x5, x4
    mov     x6, x1
    b       5f
2:  mov     x14, #1                         /* then the largest to the end, one at a time */
    sub     x7, x1, #1
3:  cbz     x7, 9f
    mov     x9, x0
    madd    x10, x7, x15, x0
    SORT_SWAP x9, x10
    mov     x5, #0
    mov     x6, x7
    sub     x7, x7, #1
    b       5f
4:  cbz     x14, 1b
    b       3b
5:  lsl     x8, x5, #1                      /* sift down from x5, below x6 */
    add     x8, x8, #1
    cmp     x8, x6
    b.hs    4b
    add     x9, x8, #1
    cmp     x9, x6
    b.hs    6f
    madd    x9, x8, x15, x0
    add     x10, x9, x15
    SORT_LESS x9, x10, 7f, 6f
7:  add     x8, x8, #1
6:  madd    x9, x5, x15, x0
    madd    x10, x8, x15, x0
    SORT_LESS x9, x10, 8f, 4b
8:  SORT_SWAP x9, x10
    mov     x5, x8
    b       5b
9:  ret
END_FUNCTION lantern_seen_sort

/* The chunk at c takes epoch e into its range. Uses x15. */
.macro CHUNK_EPOCH c, e
    ldr     x15, [\c, #SeenChunk_epoch_lo]
    cmp     \e, x15
    csel    x15, \e, x15, lo
    str     x15, [\c, #SeenChunk_epoch_lo]
    ldr     x15, [\c, #SeenChunk_epoch_hi]
    cmp     \e, x15
    csel    x15, \e, x15, hi
    str     x15, [\c, #SeenChunk_epoch_hi]
.endm

/*
 * (seen, store, out): networking.md. x19 seen, x20 store, x21 out, x22 the first epoch kept, x23 the
 * first sync slot kept, x24 the finalized slot, x25 the write cursor, x26 the HIST kind, x27 the chunk,
 * x28 its entries. Locals: L the entries of each of the five kinds, L+40 the bytes of the bits.
 */
FUNCTION lantern_seen_archive
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    bl      lantern_seen_floors
    mov     x22, x8
    mov     x23, x9
    mov     x24, x10
    stp     xzr, xzr, [sp, #L]
    stp     xzr, xzr, [sp, #(L + 16)]
    stp     xzr, xzr, [sp, #(L + 32)]
    PART    x4, x5, x19, Seen_keys          /* the entries that go: counts */
1:  cbz     x5, 2f
    ldp     x11, x12, [x4]
    mov     x13, #HIST_ATTESTATION
    cmp     x11, #SEEN_ATTESTATION
    b.eq    11f
    mov     x13, #HIST_AGGREGATOR
    cmp     x11, #SEEN_AGGREGATOR_EPOCH
    b.eq    11f
    mov     x13, #HIST_COLUMN
    cmp     x11, #SEEN_DATA_COLUMN
    b.eq    12f
    mov     x13, #HIST_BLOB
    cmp     x11, #SEEN_BLOB_SIDECAR
    b.eq    12f
    b       13f
11: cmp     x12, x22                        /* an epoch before the first kept */
    b.hs    13f
    b       14f
12: cmp     x12, x24                        /* a slot before the finalized slot */
    b.hs    13f
14: add     x14, sp, #L
    ldr     x15, [x14, x13, lsl #3]
    add     x15, x15, #1
    str     x15, [x14, x13, lsl #3]
13: add     x4, x4, #SeenKey__mem
    sub     x5, x5, #1
    b       1b
2:  PART    x4, x5, x19, Seen_bits
21: cbz     x5, 3f
    ldr     x11, [x4, #SeenBits_kind]
    cmp     x11, #SEEN_AGGREGATE
    b.ne    23f
    ldr     x12, [x4, #SeenBits_b]
    cmp     x12, x22
    b.hs    23f
    ldr     x15, [sp, #(L + 32)]
    add     x15, x15, #1
    str     x15, [sp, #(L + 32)]
    ldr     x12, [x4, #SeenBits_length]     /* its bits: whole words */
    add     x12, x12, #63
    lsr     x12, x12, #6
    ldr     x15, [sp, #(L + 40)]
    add     x15, x15, x12, lsl #3
    str     x15, [sp, #(L + 40)]
23: add     x4, x4, #SeenBits__mem
    sub     x5, x5, #1
    b       21b
3:  mov     x25, #0                         /* the bytes the chunks need */
    mov     x26, #0
31: add     x14, sp, #L
    ldr     x15, [x14, x26, lsl #3]
    cbz     x15, 32f
    HIST_ELEM x16, x26
    madd    x25, x15, x16, x25
    add     x25, x25, #SEEN_CHUNK_FIXED
32: add     x26, x26, #1
    cmp     x26, #HIST_KINDS
    b.lo    31b
    ldr     x16, [sp, #(L + 40)]
    add     x25, x25, x16
    ldr     x11, [x21]                      /* out has room for them */
    ldp     x12, x13, [x21, #8]
    sub     x11, x11, x12
    subs    x11, x11, x13
    b.lo    98f
    cmp     x11, x25
    b.lo    98f
    add     x25, x21, x12
    add     x25, x25, x13
    mov     x26, #0                         /* each kind's chunk */
4:  add     x14, sp, #L
    ldr     x28, [x14, x26, lsl #3]
    cbz     x28, 49f
    mov     x27, x25
    str     x26, [x27, #SeenChunk_kind]
    mov     x15, #-1
    stp     x15, xzr, [x27, #SeenChunk_epoch_lo]
    str     x28, [x27, #SeenChunk_count]
    add     x6, x27, #SEEN_CHUNK_FIXED
    HIST_ELEM x7, x26
    cmp     x26, #HIST_AGGREGATE
    b.eq    45f
    mov     x13, #SEEN_ATTESTATION
    cmp     x26, #HIST_AGGREGATOR
    b.lo    40f
    mov     x13, #SEEN_AGGREGATOR_EPOCH
    b.eq    40f
    mov     x13, #SEEN_DATA_COLUMN
    cmp     x26, #HIST_COLUMN
    b.eq    40f
    mov     x13, #SEEN_BLOB_SIDECAR
40: PART    x4, x5, x19, Seen_keys
41: cbz     x5, 47f
    ldp     x11, x12, [x4]
    cmp     x11, x13
    b.ne    44f
    cmp     x26, #HIST_COLUMN
    b.hs    42f
    cmp     x12, x22                        /* (epoch, index) */
    b.hs    44f
    mov     x14, x12
    ldr     x15, [x4, #16]
    stp     x12, x15, [x6], #16
    b       43f
42: cmp     x12, x24                        /* (slot, proposer index, index) */
    b.hs    44f
    mov     x15, #SLOTS_PER_EPOCH
    udiv    x14, x12, x15
    ldp     x15, x16, [x4, #16]
    stp     x12, x15, [x6], #16
    str     x16, [x6], #8
43: CHUNK_EPOCH x27, x14
44: add     x4, x4, #SeenKey__mem
    sub     x5, x5, #1
    b       41b
45: madd    x9, x28, x7, x6                 /* the bits follow the HistBits */
    PART    x4, x5, x19, Seen_bits
451: cbz    x5, 46f
    ldr     x11, [x4, #SeenBits_kind]
    cmp     x11, #SEEN_AGGREGATE
    b.ne    454f
    ldr     x14, [x4, #SeenBits_b]
    cmp     x14, x22
    b.hs    454f
    add     x15, x4, #SeenBits_root
    COPY32  x6, x15
    ldr     x15, [x4, #SeenBits_a]
    stp     x15, x14, [x6, #HistBits_a]
    ldr     x15, [x4, #SeenBits_length]
    sub     x16, x9, x27
    stp     x15, x16, [x6, #HistBits_length]
    add     x6, x6, #HistBits__mem
    add     x15, x15, #63
    lsr     x15, x15, #6
    add     x16, x4, #SeenBits_bits
452: cbz    x15, 453f
    ldr     x17, [x16], #8
    str     x17, [x9], #8
    sub     x15, x15, #1
    b       452b
453: CHUNK_EPOCH x27, x14
454: add    x4, x4, #SeenBits__mem
    sub     x5, x5, #1
    b       451b
46: mov     x25, x9                         /* the chunk's end: after the bits */
    b       48f
47: mov     x25, x6                         /* or after the entries */
48: sub     x9, x25, x27
    str     x9, [x27, #SeenChunk_bytes]
    add     x0, x27, #SEEN_CHUNK_FIXED      /* the entries sorted */
    mov     x1, x28
    lsr     x2, x7, #3
    mov     x3, x2
    cmp     x26, #HIST_AGGREGATE
    b.ne    481f
    mov     x3, #6                          /* the root, a and the epoch */
481: bl     lantern_seen_sort
49: add     x26, x26, #1
    cmp     x26, #HIST_KINDS
    b.lo    4b
    ldr     x11, [x21, #8]                  /* out's length */
    add     x11, x21, x11
    sub     x11, x25, x11
    str     x11, [x21, #16]
    PART    x4, x5, x19, Seen_keys          /* the keys that stay, moved down; zero after them */
    mov     x6, x4
5:  cbz     x5, 59f
    ldp     x11, x12, [x4]
    cmp     x11, #SEEN_ATTESTATION
    b.eq    51f
    cmp     x11, #SEEN_AGGREGATOR_EPOCH
    b.eq    51f
    cmp     x11, #SEEN_DATA_COLUMN
    b.eq    52f
    cmp     x11, #SEEN_BLOB_SIDECAR
    b.eq    52f
    cmp     x11, #SEEN_PROPOSER_SLOT
    b.eq    53f
    cmp     x11, #SEEN_SYNC_CONTRIBUTION
    b.eq    54f
    cmp     x11, #SEEN_SYNC_MESSAGE
    b.ne    55f
54: cmp     x12, x23                        /* a sync slot: kept from s - 1 */
    b.lo    56f
    b       55f
51: cmp     x12, x22                        /* archived: an epoch before the first kept */
    b.lo    56f
    b       55f
52: cmp     x12, x24                        /* archived: a slot before the finalized slot */
    b.lo    56f
    b       55f
53: cmp     x12, x24                        /* a proposer slot at or below f: dropped */
    b.ls    56f
55: cmp     x4, x6
    b.eq    57f
    ldp     x11, x12, [x4]
    ldp     x13, x14, [x4, #16]
    stp     x11, x12, [x6]
    stp     x13, x14, [x6, #16]
57: add     x6, x6, #SeenKey__mem
56: add     x4, x4, #SeenKey__mem
    sub     x5, x5, #1
    b       5b
59: ldr     x11, [x19, #Seen_keys]
    add     x11, x19, x11
    sub     x12, x6, x11
    ldr     x13, [x19, #(Seen_keys + 8)]
    lsr     x12, x12, #5
    str     x12, [x19, #(Seen_keys + 8)]
    sub     x1, x13, x12
    lsl     x1, x1, #5
    mov     x0, x6
    bl      lantern_zero
    mov     x0, x19                         /* the index of the keys that stay */
    bl      lantern_seen_index
    PART    x4, x5, x19, Seen_bits          /* the bits that stay, moved down; zero after them */
    mov     x6, x4
6:  cbz     x5, 69f
    ldr     x11, [x4, #SeenBits_kind]
    cmp     x11, #SEEN_AGGREGATE
    b.ne    61f
    ldr     x12, [x4, #SeenBits_b]          /* archived: a target epoch before the first kept */
    cmp     x12, x22
    b.lo    66f
    b       65f
61: cmp     x11, #SEEN_CONTRIBUTION
    b.ne    65f
    ldr     x12, [x4, #SeenBits_a]          /* a contribution: its slot kept from s - 1 */
    cmp     x12, x23
    b.lo    66f
65: cmp     x4, x6
    b.eq    67f
    mov     x7, #0
64: add     x13, x4, x7
    ldp     x11, x12, [x13]
    add     x14, x6, x7
    stp     x11, x12, [x14]
    add     x7, x7, #16
    cmp     x7, #SeenBits__mem
    b.lo    64b
67: add     x6, x6, #SeenBits__mem
66: add     x4, x4, #SeenBits__mem
    sub     x5, x5, #1
    b       6b
69: ldr     x11, [x19, #Seen_bits]
    add     x11, x19, x11
    sub     x12, x6, x11
    mov     x13, #SeenBits__mem
    udiv    x12, x12, x13
    ldr     x14, [x19, #(Seen_bits + 8)]
    str     x12, [x19, #(Seen_bits + 8)]
    sub     x1, x14, x12
    mul     x1, x1, x13
    mov     x0, x6
    bl      lantern_zero
    mov     x0, #LANTERN_OK
    LEAVE 48
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
END_FUNCTION lantern_seen_archive

/*
 * x0 = the first entry of HIST kind x1 whose first x3 words equal the x3 words at x2, in the chunk of
 * epoch x4 of history x0, and x1 its chunk; or x0 = 0. A leaf; uses x5-x15.
 */
LOCAL_FUNCTION lantern_seen_history_find
    UNWIND_END_PROLOGUE
    cbz     x0, 9f
    ldr     x7, [x0, #SeenHistory_size]
    ldr     x5, [x0, #SeenHistory_first_epoch]
    subs    x6, x4, x5
    b.lo    9f
    ldr     x5, [x0, #SeenHistory_capacity]
    cmp     x6, x5
    b.hs    9f
    mov     x5, #SEEN_HISTORY_ENTRY         /* the epoch's entry, inside the file's bytes */
    mul     x6, x6, x5
    add     x6, x6, #SEEN_HISTORY_FIXED
    add     x6, x6, x1, lsl #3
    add     x5, x6, #8
    cmp     x5, x7
    b.hi    9f
    ldr     x6, [x0, x6]
    cbz     x6, 9f
    cmp     x6, x7                          /* the chunk, inside the file's bytes */
    b.hs    9f
    sub     x5, x7, x6
    cmp     x5, #SEEN_CHUNK_FIXED
    b.lo    9f
    add     x8, x0, x6
    ldr     x9, [x8, #SeenChunk_bytes]
    cmp     x9, x5
    b.hi    9f
    ldr     x10, [x8, #SeenChunk_kind]
    cmp     x10, x1
    b.ne    9f
    HIST_ELEM x10, x1
    ldr     x11, [x8, #SeenChunk_count]     /* its entries, inside the chunk */
    umulh   x12, x11, x10
    cbnz    x12, 9f
    mul     x12, x11, x10
    add     x12, x12, #SEEN_CHUNK_FIXED
    cmp     x12, x9
    b.hi    9f
    mov     x1, x8
    add     x8, x8, #SEEN_CHUNK_FIXED
    mov     x12, #0                         /* the first entry not below the key */
    mov     x13, x11
1:  cmp     x12, x13
    b.hs    3f
    add     x14, x12, x13
    lsr     x14, x14, #1
    madd    x15, x14, x10, x8
    mov     x5, #0
2:  cmp     x5, x3
    b.hs    21f
    ldr     x6, [x15, x5, lsl #3]
    ldr     x7, [x2, x5, lsl #3]
    cmp     x6, x7
    b.lo    22f
    b.hi    21f
    add     x5, x5, #1
    b       2b
22: add     x12, x14, #1
    b       1b
21: mov     x13, x14
    b       1b
3:  cmp     x12, x11
    b.hs    9f
    madd    x15, x12, x10, x8
    mov     x5, #0
4:  cmp     x5, x3
    b.hs    5f
    ldr     x6, [x15, x5, lsl #3]
    ldr     x7, [x2, x5, lsl #3]
    cmp     x6, x7
    b.ne    9f
    add     x5, x5, #1
    b       4b
5:  mov     x0, x15
    ret
9:  mov     x0, #0
    ret
END_FUNCTION lantern_seen_history_find

/*
 * (seen, history, recall, mark): networking.md. x19 seen, x20 history, x21 recall, x22 mark, x23 the
 * items left, x24 the item, x25 the entry, x26 the end of the chunk's entries, x27 the chunk, x28 0
 * while counting, 1 while adding. Locals: L a key of 6 words, L+48 the keys to add, L+56 the bits.
 */
FUNCTION lantern_seen_recall
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldr     x9, [x19, #(Seen_keys + 8)]
    stp     x9, xzr, [x22, #SeenMark_keys]
    ldr     x9, [x19, #(Seen_bits + 8)]
    stp     x9, xzr, [x22, #SeenMark_bits]
    stp     xzr, xzr, [sp, #(L + 48)]
    mov     x28, #0
0:  ldr     x23, [x21, #SeenRecall_count]
    cmp     x23, #SEEN_RECALL_MAX
    b.hi    99f
    add     x24, x21, #SeenRecall_items
1:  cbz     x23, 80f
    ldr     x9, [x24, #SeenRecallItem_kind]
    cmp     x9, #SEEN_RECALL_BITS
    b.eq    20f
    ldp     x10, x11, [x24, #SeenRecallItem_a]
    ldr     x12, [x24, #SeenRecallItem_c]
    stp     x10, x11, [sp, #L]
    str     x12, [sp, #(L + 16)]
    mov     x4, x10                         /* the epoch of a */
    mov     x1, #HIST_ATTESTATION
    mov     x3, #2
    cmp     x9, #SEEN_ATTESTATION
    b.eq    10f
    mov     x1, #HIST_AGGREGATOR
    cmp     x9, #SEEN_AGGREGATOR_EPOCH
    b.eq    10f
    mov     x13, #SLOTS_PER_EPOCH           /* or of the slot a */
    udiv    x4, x10, x13
    mov     x1, #HIST_COLUMN
    mov     x3, #3
    cmp     x9, #SEEN_DATA_COLUMN
    b.eq    10f
    mov     x1, #HIST_BLOB
    cmp     x9, #SEEN_BLOB_SIDECAR
    b.ne    70f
10: stp     x1, x3, [sp, #(L + 24)]         /* seen holds it already: nothing to add */
    str     x4, [sp, #(L + 40)]
    mov     x0, x19
    mov     x1, x9
    mov     x2, x10
    mov     x3, x11
    mov     x4, x12
    bl      lantern_seen_find_key
    cbnz    x0, 70f
    ldp     x1, x3, [sp, #(L + 24)]
    ldr     x4, [sp, #(L + 40)]
12: mov     x0, x20
    add     x2, sp, #L
    bl      lantern_seen_history_find
    cbz     x0, 70f
    cbnz    x28, 13f
    ldr     x9, [sp, #(L + 48)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 48)]
    b       70f
13: mov     x0, x19                         /* the key, after the others, and in the index */
    ldr     x1, [x24, #SeenRecallItem_kind]
    ldp     x2, x3, [x24, #SeenRecallItem_a]
    ldr     x4, [x24, #SeenRecallItem_c]
    bl      lantern_seen_add_key
    ldr     x9, [x22, #SeenMark_added_keys]
    add     x9, x9, #1
    str     x9, [x22, #SeenMark_added_keys]
    b       70f
20: add     x9, x24, #SeenRecallItem_root   /* bits: none of (root, a, epoch) in seen */
    add     x10, sp, #L
    COPY32  x10, x9
    ldp     x10, x11, [x24, #SeenRecallItem_a]
    stp     x10, x11, [sp, #(L + 32)]
    PART    x13, x14, x19, Seen_bits
21: cbz     x14, 22f
    ldr     x15, [x13, #SeenBits_kind]
    cmp     x15, #SEEN_AGGREGATE
    b.ne    23f
    ldp     x15, x16, [x13, #SeenBits_a]
    cmp     x15, x10
    ccmp    x16, x11, #0, eq
    b.ne    23f
    add     x15, x13, #SeenBits_root
    add     x16, sp, #L
    ldp     x2, x3, [x15]
    ldp     x4, x5, [x16]
    cmp     x2, x4
    ccmp    x3, x5, #0, eq
    b.ne    23f
    ldp     x2, x3, [x15, #16]
    ldp     x4, x5, [x16, #16]
    cmp     x2, x4
    ccmp    x3, x5, #0, eq
    b.eq    70f
23: add     x13, x13, #SeenBits__mem
    sub     x14, x14, #1
    b       21b
22: mov     x0, x20
    mov     x1, #HIST_AGGREGATE
    add     x2, sp, #L
    mov     x3, #6
    mov     x4, x11
    bl      lantern_seen_history_find
    cbz     x0, 70f
    mov     x25, x0
    mov     x27, x1
    ldr     x9, [x27, #SeenChunk_count]
    mov     x10, #HistBits__mem
    add     x26, x27, #SEEN_CHUNK_FIXED
    madd    x26, x9, x10, x26
24: cmp     x25, x26                        /* each entry of the key */
    b.hs    70f
    add     x9, sp, #L
    mov     x5, #0
25: cmp     x5, #6
    b.hs    26f
    ldr     x6, [x25, x5, lsl #3]
    ldr     x7, [x9, x5, lsl #3]
    cmp     x6, x7
    b.ne    70f
    add     x5, x5, #1
    b       25b
26: ldp     x6, x7, [x25, #HistBits_length] /* its bits inside the chunk, at most SEEN_BITS_BYTES */
    cmp     x6, #(SEEN_BITS_BYTES * 8)
    b.hi    29f
    add     x8, x6, #63
    lsr     x8, x8, #6
    lsl     x8, x8, #3
    ldr     x9, [x27, #SeenChunk_bytes]
    cmp     x7, x9
    b.hs    29f
    sub     x9, x9, x7
    cmp     x8, x9
    b.hi    29f
    cbnz    x28, 27f
    ldr     x9, [sp, #(L + 56)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 56)]
    b       29f
27: PART    x13, x14, x19, Seen_bits        /* the SeenBits, after the others */
    mov     x15, #SeenBits__mem
    madd    x13, x14, x15, x13
    mov     x15, #SEEN_AGGREGATE
    str     x15, [x13, #SeenBits_kind]
    add     x15, x13, #SeenBits_root
    COPY32  x15, x25
    ldp     x15, x16, [x25, #HistBits_a]
    stp     x15, x16, [x13, #SeenBits_a]
    str     x6, [x13, #SeenBits_length]
    add     x15, x13, #SeenBits_bits
    add     x16, x27, x7
28: cbz     x8, 281f
    ldr     x17, [x16], #8
    str     x17, [x15], #8
    sub     x8, x8, #8
    b       28b
281: add    x14, x14, #1
    str     x14, [x19, #(Seen_bits + 8)]
    ldr     x9, [x22, #SeenMark_added_bits]
    add     x9, x9, #1
    str     x9, [x22, #SeenMark_added_bits]
29: add     x25, x25, #HistBits__mem
    b       24b
70: add     x24, x24, #SeenRecallItem__mem
    sub     x23, x23, #1
    b       1b
80: cbnz    x28, 90f                        /* counted: room for them, then add them */
    ldr     x9, [x19, #Seen_bits]
    ldr     x10, [x19, #Seen_keys]
    sub     x9, x9, x10
    lsr     x9, x9, #5
    ldr     x10, [x19, #(Seen_keys + 8)]
    sub     x9, x9, x10
    ldr     x10, [sp, #(L + 48)]
    cmp     x9, x10
    b.lo    98f
    ldr     x9, [x19, #Seen_blocks]
    ldr     x10, [x19, #Seen_bits]
    sub     x9, x9, x10
    mov     x10, #SeenBits__mem
    udiv    x9, x9, x10
    ldr     x10, [x19, #(Seen_bits + 8)]
    sub     x9, x9, x10
    ldr     x10, [sp, #(L + 56)]
    cmp     x9, x10
    b.lo    98f
    mov     x28, #1
    b       0b
90: mov     x0, #LANTERN_OK
    LEAVE 64
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
99: mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 64
END_FUNCTION lantern_seen_recall

/* (seen, mark): networking.md. A leaf; uses x2-x10. */
LEAF lantern_seen_forget
    ldp     x2, x3, [x1, #SeenMark_keys]    /* the keys it added: those after them move down, zero after */
    cbz     x3, 2f
    PART    x4, x5, x0, Seen_keys
    add     x6, x4, x2, lsl #5
    add     x7, x6, x3, lsl #5
    sub     x8, x5, x2
    sub     x8, x8, x3
1:  cbz     x8, 11f
    ldp     x9, x10, [x7], #16
    stp     x9, x10, [x6], #16
    ldp     x9, x10, [x7], #16
    stp     x9, x10, [x6], #16
    sub     x8, x8, #1
    b       1b
11: sub     x5, x5, x3
    str     x5, [x0, #(Seen_keys + 8)]
12: stp     xzr, xzr, [x6], #16
    stp     xzr, xzr, [x6], #16
    subs    x3, x3, #1
    b.ne    12b
2:  ldp     x2, x3, [x1, #SeenMark_bits]    /* the same for the bits */
    cbz     x3, 9f
    PART    x4, x5, x0, Seen_bits
    mov     x9, #SeenBits__mem
    madd    x6, x2, x9, x4
    madd    x7, x3, x9, x6
    sub     x8, x5, x2
    sub     x8, x8, x3
    mul     x8, x8, x9
3:  cbz     x8, 31f
    ldp     x9, x10, [x7], #16
    stp     x9, x10, [x6], #16
    sub     x8, x8, #16
    b       3b
31: sub     x5, x5, x3
    str     x5, [x0, #(Seen_bits + 8)]
    mov     x9, #SeenBits__mem
    mul     x8, x3, x9
32: stp     xzr, xzr, [x6], #16
    subs    x8, x8, #16
    b.ne    32b
9:  ldr     x2, [x1, #SeenMark_added_keys]  /* keys removed: the index of those left */
    cbnz    x2, lantern_seen_index
    RETURN_OK
END_FUNCTION lantern_seen_forget

/* Part ref of seen x19 takes the count at x20 + at; zero the bytes of the entries past it, of size bytes each. */
.macro SEEN_RESTORE ref, at, size
    ldr     x9, [x20, #\at]
    ldr     x10, [x19, #((\ref) + 8)]
    str     x9, [x19, #((\ref) + 8)]
    subs    x1, x10, x9
    b.ls    107f
    mov     x11, #(\size)
    mul     x1, x1, x11
    ldr     x0, [x19, #(\ref)]
    add     x0, x19, x0
    madd    x0, x9, x11, x0
    bl      lantern_zero
107:
.endm

/* (seen, counts): networking.md. x19 seen, x20 counts. */
FUNCTION lantern_seen_restore
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    ldr     x21, [x19, #(Seen_keys + 8)]    /* keys removed: the index of those left */
    SEEN_RESTORE Seen_keys, 0, SeenKey__mem
    ldr     x9, [x20]
    cmp     x9, x21
    b.eq    1f
    mov     x0, x19
    bl      lantern_seen_index
1:
    SEEN_RESTORE Seen_bits, 8, SeenBits__mem
    SEEN_RESTORE Seen_blocks, 16, SeenBlock__mem
    ldr     x9, [x20, #24]                  /* the headers: their count, and zero after their bytes */
    str     x9, [x19, #(Seen_headers + 8)]
    ldr     x9, [x20, #32]
    ldr     x10, [x19, #Seen_header_bytes]
    str     x9, [x19, #Seen_header_bytes]
    subs    x1, x10, x9
    b.ls    9f
    ldr     x0, [x19, #Seen_headers]
    add     x0, x19, x0
    add     x0, x0, x9
    bl      lantern_zero
9:  mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_seen_restore

/*
 * (a, b, out): networking.md. x19 a, x20 b, x21 out, x22 the entry bytes, x23 the words compared,
 * x24 the merged chunk, x25 a's next entry, x26 a's entries left, x27 b's next entry, x28 b's entries
 * left, x6 the next entry written, x9 the next word of bits.
 */
FUNCTION lantern_seen_chunk_merge
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x9, [x19, #SeenChunk_bytes]     /* the merged chunk's bytes */
    ldr     x10, [x20, #SeenChunk_bytes]
    add     x9, x9, x10
    sub     x9, x9, #SEEN_CHUNK_FIXED
    ldr     x11, [x21]                      /* out has room for them */
    ldp     x12, x13, [x21, #8]
    sub     x11, x11, x12
    subs    x11, x11, x13
    b.lo    98f
    cmp     x11, x9
    b.lo    98f
    add     x24, x21, x12
    add     x24, x24, x13
    add     x13, x13, x9
    str     x13, [x21, #16]
    str     x9, [x24, #SeenChunk_bytes]
    ldr     x10, [x19, #SeenChunk_kind]
    str     x10, [x24, #SeenChunk_kind]
    HIST_ELEM x22, x10
    lsr     x23, x22, #3
    cmp     x10, #HIST_AGGREGATE
    b.ne    1f
    mov     x23, #6                         /* the root, a and the epoch */
1:  ldp     x11, x12, [x19, #SeenChunk_epoch_lo]
    ldp     x13, x14, [x20, #SeenChunk_epoch_lo]
    cmp     x11, x13
    csel    x11, x11, x13, lo
    cmp     x12, x14
    csel    x12, x12, x14, hi
    stp     x11, x12, [x24, #SeenChunk_epoch_lo]
    ldr     x26, [x19, #SeenChunk_count]
    ldr     x28, [x20, #SeenChunk_count]
    add     x11, x26, x28
    str     x11, [x24, #SeenChunk_count]
    add     x25, x19, #SEEN_CHUNK_FIXED
    add     x27, x20, #SEEN_CHUNK_FIXED
    add     x6, x24, #SEEN_CHUNK_FIXED
    madd    x9, x11, x22, x6                /* the bits follow the entries */
    mov     x3, x23
2:  cbnz    x26, 21f                        /* the lower entry next; a's first when equal */
    cbz     x28, 8f
    b       31f
21: cbz     x28, 30f
    SORT_LESS x27, x25, 31f, 30f
30: mov     x4, x25
    mov     x5, x19
    add     x25, x25, x22
    sub     x26, x26, #1
    b       3f
31: mov     x4, x27
    mov     x5, x20
    add     x27, x27, x22
    sub     x28, x28, #1
3:  mov     x12, #0                         /* the entry */
32: ldr     x11, [x4, x12]
    str     x11, [x6, x12]
    add     x12, x12, #8
    cmp     x12, x22
    b.lo    32b
    cmp     x10, #HIST_AGGREGATE
    b.ne    35f
    ldr     x12, [x4, #HistBits_length]     /* and its bits, at their new offset */
    add     x12, x12, #63
    lsr     x12, x12, #6
    ldr     x13, [x4, #HistBits_bits]
    add     x13, x5, x13
    sub     x14, x9, x24
    str     x14, [x6, #HistBits_bits]
33: cbz     x12, 35f
    ldr     x11, [x13], #8
    str     x11, [x9], #8
    sub     x12, x12, #1
    b       33b
35: add     x6, x6, x22
    b       2b
8:  mov     x0, #LANTERN_OK
    LEAVE 0
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_seen_chunk_merge
