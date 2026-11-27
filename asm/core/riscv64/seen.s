/*
 * Sizing, making, growing and archiving Seen, RISC-V: it reads no fork's layouts.
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
    ld      t0, 0(a1)                       # every byte of the parts zero
    addi    a0, a1, SEEN_FIXED
    addi    a1, t0, -SEEN_FIXED
    call    lantern_zero
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
    call    lantern_seen_find_block
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

/*
 * The floors of store a1 (networking.md, lantern_seen_archive): a5 the first epoch kept, a6 the first
 * sync slot kept, a7 the finalized slot. A leaf; uses t0-t3.
 */
LOCAL_FUNCTION lantern_seen_floors
    UNWIND_END_PROLOGUE
    LDQ     t0, a1, Store_time_ms           # s: the current slot, 0 before genesis
    LDQ     t1, a1, Store_genesis_time_ms
    sub     t2, t0, t1
    bgeu    t0, t1, 1f
    li      t2, 0
1:  LDQ     t1, a1, (Store_config + CONFIG_SLOT_DURATION_MS)
    li      t0, 0
    beqz    t1, 2f
    divu    t0, t2, t1
2:  li      a6, 0                           # the first sync slot kept: s - 1
    beqz    t0, 3f
    addi    a6, t0, -1
3:  LDQ     t1, a1, (Store_config + CONFIG_ATTESTATION_PROPAGATION_SLOT_RANGE)
    li      a5, 0                           # the first epoch kept: e - 1, with e the epoch of s - range - 1
    bltu    t0, t1, 4f
    sub     t0, t0, t1
    beqz    t0, 4f
    addi    t0, t0, -1
    li      t1, SLOTS_PER_EPOCH
    divu    t0, t0, t1
    beqz    t0, 4f
    addi    a5, t0, -1
4:  LDQ     t0, a1, Store_finalized_checkpoint  # f: the first slot of the finalized epoch
    li      t1, SLOTS_PER_EPOCH
    mulhu   t2, t0, t1
    mul     a7, t0, t1
    beqz    t2, 5f
    li      a7, -1
5:  ret
END_FUNCTION lantern_seen_floors

/* dst = the bytes of an entry of HIST kind k: 16, 24, or HistBits__mem. Uses tmp. */
.macro HIST_ELEM dst, k, tmp
    li      \dst, 16
    li      \tmp, HIST_COLUMN
    bltu    \k, \tmp, 104f
    li      \dst, 24
    li      \tmp, HIST_AGGREGATE
    bltu    \k, \tmp, 104f
    li      \dst, HistBits__mem
104:
.endm

/* Branch to less when the first s4 words of the record at t4 are below those at t3, else to notless. Uses t0-t2. */
.macro SORT_LESS less, notless
    li      t2, 0
101: bgeu   t2, s4, \notless
    slli    t0, t2, 3
    add     t1, t4, t0
    ld      t1, 0(t1)
    add     t0, t3, t0
    ld      t0, 0(t0)
    bltu    t1, t0, \less
    bltu    t0, t1, \notless
    addi    t2, t2, 1
    j       101b
.endm

/* Swap the s3 words of the records at t4 and t3. Uses t0-t2, t5, t6. */
.macro SORT_SWAP
    li      t2, 0
102: bgeu   t2, s3, 103f
    slli    t0, t2, 3
    add     t1, t4, t0
    add     t0, t3, t0
    ld      t5, 0(t1)
    ld      t6, 0(t0)
    sd      t6, 0(t1)
    sd      t5, 0(t0)
    addi    t2, t2, 1
    j       102b
103:
.endm

/*
 * Sort the a1 records of a2 words at a0 by their first a3 words, unsigned and in word order: a heapsort.
 * s1 the records, s2 their count, s3 words, s4 key words, s5 record bytes, s6 the inner node or the end of
 * the heap, s7 0 while the heap is built, s8 the root, s9 the end, s10 a child.
 */
LOCAL_FUNCTION lantern_seen_sort
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    li      t0, 2
    bltu    s2, t0, 9f
    slli    s5, s3, 3
    srli    s6, s2, 1
    li      s7, 0
1:  beqz    s6, 2f                          # the heap: each inner node from the last
    addi    s6, s6, -1
    mv      s8, s6
    mv      s9, s2
    j       5f
2:  li      s7, 1                           # then the largest to the end, one at a time
    addi    s6, s2, -1
3:  beqz    s6, 9f
    mv      t4, s1
    mul     t3, s6, s5
    add     t3, s1, t3
    SORT_SWAP
    li      s8, 0
    mv      s9, s6
    addi    s6, s6, -1
    j       5f
4:  beqz    s7, 1b
    j       3b
5:  slli    s10, s8, 1                      # sift down from s8, below s9
    addi    s10, s10, 1
    bgeu    s10, s9, 4b
    addi    t0, s10, 1
    bgeu    t0, s9, 6f
    mul     t4, s10, s5
    add     t4, s1, t4
    add     t3, t4, s5
    SORT_LESS 7f, 6f
7:  addi    s10, s10, 1
6:  mul     t4, s8, s5
    add     t4, s1, t4
    mul     t3, s10, s5
    add     t3, s1, t3
    SORT_LESS 8f, 4b
8:  SORT_SWAP
    mv      s8, s10
    j       5b
9:  LEAVE 0
END_FUNCTION lantern_seen_sort

/* The chunk at c takes epoch e into its range. Uses t6. */
.macro CHUNK_EPOCH c, e
    ld      t6, SeenChunk_epoch_lo(\c)
    bgeu    \e, t6, 105f
    sd      \e, SeenChunk_epoch_lo(\c)
105: ld     t6, SeenChunk_epoch_hi(\c)
    bleu    \e, t6, 106f
    sd      \e, SeenChunk_epoch_hi(\c)
106:
.endm

/*
 * (seen, store, out): networking.md. s1 seen, s2 store, s3 out, s4 the first epoch kept, s5 the first sync
 * slot kept, s6 the finalized slot, s7 the write cursor, s8 the HIST kind, s9 the chunk, s10 its entries.
 * Locals: L the entries of each of the five kinds, L+40 the bytes of the bits, L+48 an entry's bytes.
 */
FUNCTION lantern_seen_archive
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    call    lantern_seen_floors
    mv      s4, a5
    mv      s5, a6
    mv      s6, a7
    sd      zero, L(sp)
    sd      zero, (L + 8)(sp)
    sd      zero, (L + 16)(sp)
    sd      zero, (L + 24)(sp)
    sd      zero, (L + 32)(sp)
    sd      zero, (L + 40)(sp)
    PART    t3, t4, s1, Seen_keys           # the entries that go: counts
1:  beqz    t4, 2f
    ld      t0, 0(t3)
    ld      t1, 8(t3)
    li      t5, HIST_ATTESTATION
    li      t2, SEEN_ATTESTATION
    beq     t0, t2, 11f
    li      t5, HIST_AGGREGATOR
    li      t2, SEEN_AGGREGATOR_EPOCH
    beq     t0, t2, 11f
    li      t5, HIST_COLUMN
    li      t2, SEEN_DATA_COLUMN
    beq     t0, t2, 12f
    li      t5, HIST_BLOB
    li      t2, SEEN_BLOB_SIDECAR
    beq     t0, t2, 12f
    j       13f
11: bgeu    t1, s4, 13f                     # an epoch before the first kept
    j       14f
12: bgeu    t1, s6, 13f                     # a slot before the finalized slot
14: slli    t5, t5, 3
    add     t5, sp, t5
    ld      t6, L(t5)
    addi    t6, t6, 1
    sd      t6, L(t5)
13: addi    t3, t3, SeenKey__mem
    addi    t4, t4, -1
    j       1b
2:  PART    t3, t4, s1, Seen_bits
21: beqz    t4, 3f
    ld      t0, SeenBits_kind(t3)
    li      t2, SEEN_AGGREGATE
    bne     t0, t2, 23f
    ld      t1, SeenBits_b(t3)
    bgeu    t1, s4, 23f
    ld      t6, (L + 32)(sp)
    addi    t6, t6, 1
    sd      t6, (L + 32)(sp)
    ld      t1, SeenBits_length(t3)         # its bits: whole words
    addi    t1, t1, 63
    srli    t1, t1, 6
    slli    t1, t1, 3
    ld      t6, (L + 40)(sp)
    add     t6, t6, t1
    sd      t6, (L + 40)(sp)
23: addi    t3, t3, SeenBits__mem
    addi    t4, t4, -1
    j       21b
3:  li      s7, 0                           # the bytes the chunks need
    li      s8, 0
31: slli    t0, s8, 3
    add     t0, sp, t0
    ld      t1, L(t0)
    beqz    t1, 32f
    HIST_ELEM t2, s8, t3
    mul     t1, t1, t2
    add     s7, s7, t1
    addi    s7, s7, SEEN_CHUNK_FIXED
32: addi    s8, s8, 1
    li      t0, HIST_KINDS
    bltu    s8, t0, 31b
    ld      t0, (L + 40)(sp)
    add     s7, s7, t0
    ld      t0, 0(s3)                       # out has room for them
    ld      t1, 8(s3)
    ld      t2, 16(s3)
    bltu    t0, t1, 98f
    sub     t0, t0, t1
    bltu    t0, t2, 98f
    sub     t0, t0, t2
    bltu    t0, s7, 98f
    add     s7, s3, t1
    add     s7, s7, t2
    li      s8, 0                           # each kind's chunk
4:  slli    t0, s8, 3
    add     t0, sp, t0
    ld      s10, L(t0)
    beqz    s10, 49f
    mv      s9, s7
    sd      s8, SeenChunk_kind(s9)
    li      t0, -1
    sd      t0, SeenChunk_epoch_lo(s9)
    sd      zero, SeenChunk_epoch_hi(s9)
    sd      s10, SeenChunk_count(s9)
    addi    a2, s9, SEEN_CHUNK_FIXED        # a2 the entry written
    HIST_ELEM t2, s8, t3
    sd      t2, (L + 48)(sp)
    li      t0, HIST_AGGREGATE
    beq     s8, t0, 45f
    li      a3, SEEN_ATTESTATION            # a3 the SEEN kind
    li      t0, HIST_AGGREGATOR
    bltu    s8, t0, 40f
    li      a3, SEEN_AGGREGATOR_EPOCH
    beq     s8, t0, 40f
    li      a3, SEEN_DATA_COLUMN
    li      t0, HIST_COLUMN
    beq     s8, t0, 40f
    li      a3, SEEN_BLOB_SIDECAR
40: PART    t3, t4, s1, Seen_keys
41: beqz    t4, 47f
    ld      t0, 0(t3)
    bne     t0, a3, 44f
    ld      t1, 8(t3)
    li      t0, HIST_COLUMN
    bgeu    s8, t0, 42f
    bgeu    t1, s4, 44f                     # (epoch, index)
    mv      t5, t1
    ld      t0, 16(t3)
    sd      t1, 0(a2)
    sd      t0, 8(a2)
    addi    a2, a2, 16
    j       43f
42: bgeu    t1, s6, 44f                     # (slot, proposer index, index)
    ld      t0, 16(t3)
    sd      t1, 0(a2)
    sd      t0, 8(a2)
    ld      t0, 24(t3)
    sd      t0, 16(a2)
    addi    a2, a2, 24
    li      t0, SLOTS_PER_EPOCH
    divu    t5, t1, t0
43: CHUNK_EPOCH s9, t5
44: addi    t3, t3, SeenKey__mem
    addi    t4, t4, -1
    j       41b
45: li      t0, HistBits__mem               # the bits follow the HistBits
    mul     t0, s10, t0
    add     a4, a2, t0                      # a4 the bits written
    PART    t3, t4, s1, Seen_bits
451: beqz   t4, 46f
    ld      t0, SeenBits_kind(t3)
    li      t1, SEEN_AGGREGATE
    bne     t0, t1, 454f
    ld      t5, SeenBits_b(t3)
    bgeu    t5, s4, 454f
    addi    t0, t3, SeenBits_root
    COPY32  a2, t0
    ld      t0, SeenBits_a(t3)
    sd      t0, HistBits_a(a2)
    sd      t5, HistBits_epoch(a2)
    ld      t0, SeenBits_length(t3)
    sd      t0, HistBits_length(a2)
    sub     t1, a4, s9
    sd      t1, HistBits_bits(a2)
    addi    a2, a2, HistBits__mem
    addi    t0, t0, 63
    srli    t0, t0, 6
    addi    t1, t3, SeenBits_bits
452: beqz   t0, 453f
    ld      t2, 0(t1)
    sd      t2, 0(a4)
    addi    t1, t1, 8
    addi    a4, a4, 8
    addi    t0, t0, -1
    j       452b
453: CHUNK_EPOCH s9, t5
454: addi   t3, t3, SeenBits__mem
    addi    t4, t4, -1
    j       451b
46: mv      s7, a4                          # the chunk's end: after the bits
    j       48f
47: mv      s7, a2                          # or after the entries
48: sub     t0, s7, s9
    sd      t0, SeenChunk_bytes(s9)
    addi    a0, s9, SEEN_CHUNK_FIXED        # the entries sorted
    mv      a1, s10
    ld      a2, (L + 48)(sp)
    srli    a2, a2, 3
    mv      a3, a2
    li      t0, HIST_AGGREGATE
    bne     s8, t0, 481f
    li      a3, 6                           # the root, a and the epoch
481: call   lantern_seen_sort
49: addi    s8, s8, 1
    li      t0, HIST_KINDS
    bltu    s8, t0, 4b
    ld      t0, 8(s3)                       # out's length
    add     t0, s3, t0
    sub     t0, s7, t0
    sd      t0, 16(s3)
    PART    t3, t4, s1, Seen_keys           # the keys that stay, moved down; zero after them
    mv      a2, t3
5:  beqz    t4, 59f
    ld      t0, 0(t3)
    ld      t1, 8(t3)
    li      t2, SEEN_ATTESTATION
    beq     t0, t2, 51f
    li      t2, SEEN_AGGREGATOR_EPOCH
    beq     t0, t2, 51f
    li      t2, SEEN_DATA_COLUMN
    beq     t0, t2, 52f
    li      t2, SEEN_BLOB_SIDECAR
    beq     t0, t2, 52f
    li      t2, SEEN_PROPOSER_SLOT
    beq     t0, t2, 53f
    li      t2, SEEN_SYNC_CONTRIBUTION
    beq     t0, t2, 54f
    li      t2, SEEN_SYNC_MESSAGE
    bne     t0, t2, 55f
54: bltu    t1, s5, 56f                     # a sync slot: kept from s - 1
    j       55f
51: bltu    t1, s4, 56f                     # archived: an epoch before the first kept
    j       55f
52: bltu    t1, s6, 56f                     # archived: a slot before the finalized slot
    j       55f
53: bgeu    s6, t1, 56f                     # a proposer slot at or below f: dropped
55: beq     t3, a2, 57f
    ld      t0, 0(t3)
    ld      t1, 8(t3)
    ld      t2, 16(t3)
    ld      t5, 24(t3)
    sd      t0, 0(a2)
    sd      t1, 8(a2)
    sd      t2, 16(a2)
    sd      t5, 24(a2)
57: addi    a2, a2, SeenKey__mem
56: addi    t3, t3, SeenKey__mem
    addi    t4, t4, -1
    j       5b
59: ld      t0, Seen_keys(s1)
    add     t0, s1, t0
    sub     t1, a2, t0
    srli    t1, t1, 5
    ld      t2, (Seen_keys + 8)(s1)
    sd      t1, (Seen_keys + 8)(s1)
    sub     a1, t2, t1
    slli    a1, a1, 5
    mv      a0, a2
    call    lantern_zero
    PART    t3, t4, s1, Seen_bits           # the bits that stay, moved down; zero after them
    mv      a2, t3
6:  beqz    t4, 69f
    ld      t0, SeenBits_kind(t3)
    li      t2, SEEN_AGGREGATE
    bne     t0, t2, 61f
    ld      t1, SeenBits_b(t3)              # archived: a target epoch before the first kept
    bltu    t1, s4, 66f
    j       65f
61: li      t2, SEEN_CONTRIBUTION
    bne     t0, t2, 65f
    ld      t1, SeenBits_a(t3)              # a contribution: its slot kept from s - 1
    bltu    t1, s5, 66f
65: beq     t3, a2, 67f
    li      t5, 0
64: add     t0, t3, t5
    ld      t1, 0(t0)
    ld      t2, 8(t0)
    add     t0, a2, t5
    sd      t1, 0(t0)
    sd      t2, 8(t0)
    addi    t5, t5, 16
    li      t0, SeenBits__mem
    bltu    t5, t0, 64b
67: addi    a2, a2, SeenBits__mem
66: addi    t3, t3, SeenBits__mem
    addi    t4, t4, -1
    j       6b
69: ld      t0, Seen_bits(s1)
    add     t0, s1, t0
    sub     t1, a2, t0
    li      t2, SeenBits__mem
    divu    t1, t1, t2
    ld      t3, (Seen_bits + 8)(s1)
    sd      t1, (Seen_bits + 8)(s1)
    sub     a1, t3, t1
    mul     a1, a1, t2
    mv      a0, a2
    call    lantern_zero
    li      a0, LANTERN_OK
    LEAVE 64
98: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_seen_archive

/*
 * a0 = the first entry of HIST kind a1 whose first a3 words equal the a3 words at a2, in the chunk of epoch
 * a4 of history a0, and a1 its chunk; or a0 = 0. A leaf; uses t0-t6, a5-a7.
 */
LOCAL_FUNCTION lantern_seen_history_find
    UNWIND_END_PROLOGUE
    beqz    a0, 9f
    ld      t0, SeenHistory_size(a0)
    ld      t1, SeenHistory_first_epoch(a0)
    bltu    a4, t1, 9f
    sub     t1, a4, t1
    ld      t2, SeenHistory_capacity(a0)
    bgeu    t1, t2, 9f
    li      t2, SEEN_HISTORY_ENTRY          # the epoch's entry, inside the file's bytes
    mul     t1, t1, t2
    addi    t1, t1, SEEN_HISTORY_FIXED
    slli    t2, a1, 3
    add     t1, t1, t2
    addi    t2, t1, 8
    bltu    t0, t2, 9f
    add     t1, a0, t1
    ld      t1, 0(t1)
    beqz    t1, 9f
    bgeu    t1, t0, 9f                      # the chunk, inside the file's bytes
    sub     t2, t0, t1
    li      t3, SEEN_CHUNK_FIXED
    bltu    t2, t3, 9f
    add     t6, a0, t1                      # t6 the chunk
    ld      t3, SeenChunk_bytes(t6)
    bltu    t2, t3, 9f
    ld      t2, SeenChunk_kind(t6)
    bne     t2, a1, 9f
    HIST_ELEM t5, a1, t2
    ld      t4, SeenChunk_count(t6)         # its entries, inside the chunk
    mulhu   t2, t4, t5
    bnez    t2, 9f
    mul     t2, t4, t5
    addi    t2, t2, SEEN_CHUNK_FIXED
    bltu    t3, t2, 9f
    mv      a1, t6
    addi    t6, t6, SEEN_CHUNK_FIXED
    li      a5, 0                           # the first entry not below the key
    mv      a6, t4
1:  bgeu    a5, a6, 3f
    add     a7, a5, a6
    srli    a7, a7, 1
    mul     t3, a7, t5
    add     t3, t6, t3
    li      t2, 0
2:  bgeu    t2, a3, 21f
    slli    t0, t2, 3
    add     t1, t3, t0
    ld      t1, 0(t1)
    add     t0, a2, t0
    ld      t0, 0(t0)
    bltu    t1, t0, 22f
    bltu    t0, t1, 21f
    addi    t2, t2, 1
    j       2b
22: addi    a5, a7, 1
    j       1b
21: mv      a6, a7
    j       1b
3:  bgeu    a5, t4, 9f
    mul     t3, a5, t5
    add     t3, t6, t3
    li      t2, 0
4:  bgeu    t2, a3, 5f
    slli    t0, t2, 3
    add     t1, t3, t0
    ld      t1, 0(t1)
    add     t0, a2, t0
    ld      t0, 0(t0)
    bne     t1, t0, 9f
    addi    t2, t2, 1
    j       4b
5:  mv      a0, t3
    ret
9:  li      a0, 0
    ret
END_FUNCTION lantern_seen_history_find

/*
 * (seen, history, recall, mark): networking.md. s1 seen, s2 history, s3 recall, s4 mark, s5 the items left,
 * s6 the item, s7 the entry, s8 the end of the chunk's entries, s9 the chunk, s10 0 while counting, 1 while
 * adding. Locals: L a key of 6 words, L+48 the keys to add, L+56 the bits.
 */
FUNCTION lantern_seen_recall
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      t0, (Seen_keys + 8)(s1)
    sd      t0, SeenMark_keys(s4)
    sd      zero, SeenMark_added_keys(s4)
    ld      t0, (Seen_bits + 8)(s1)
    sd      t0, SeenMark_bits(s4)
    sd      zero, SeenMark_added_bits(s4)
    sd      zero, (L + 48)(sp)
    sd      zero, (L + 56)(sp)
    li      s10, 0
0:  ld      s5, SeenRecall_count(s3)
    li      t0, SEEN_RECALL_MAX
    bltu    t0, s5, 99f
    addi    s6, s3, SeenRecall_items
1:  beqz    s5, 80f
    ld      t0, SeenRecallItem_kind(s6)
    li      t1, SEEN_RECALL_BITS
    beq     t0, t1, 20f
    ld      t1, SeenRecallItem_a(s6)
    ld      t2, SeenRecallItem_b(s6)
    ld      t3, SeenRecallItem_c(s6)
    sd      t1, L(sp)
    sd      t2, (L + 8)(sp)
    sd      t3, (L + 16)(sp)
    mv      a4, t1                          # the epoch of a
    li      a1, HIST_ATTESTATION
    li      a3, 2
    li      t4, SEEN_ATTESTATION
    beq     t0, t4, 10f
    li      a1, HIST_AGGREGATOR
    li      t4, SEEN_AGGREGATOR_EPOCH
    beq     t0, t4, 10f
    li      t4, SLOTS_PER_EPOCH             # or of the slot a
    divu    a4, t1, t4
    li      a1, HIST_COLUMN
    li      a3, 3
    li      t4, SEEN_DATA_COLUMN
    beq     t0, t4, 10f
    li      a1, HIST_BLOB
    li      t4, SEEN_BLOB_SIDECAR
    bne     t0, t4, 70f
10: PART    t4, t5, s1, Seen_keys           # seen holds it already: nothing to add
11: beqz    t5, 12f
    ld      t6, 0(t4)
    bne     t6, t0, 13f
    ld      t6, 8(t4)
    bne     t6, t1, 13f
    ld      t6, 16(t4)
    bne     t6, t2, 13f
    ld      t6, 24(t4)
    beq     t6, t3, 70f
13: addi    t4, t4, SeenKey__mem
    addi    t5, t5, -1
    j       11b
12: mv      a0, s2
    addi    a2, sp, L
    call    lantern_seen_history_find
    beqz    a0, 70f
    bnez    s10, 14f
    ld      t0, (L + 48)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 48)(sp)
    j       70f
14: PART    t4, t5, s1, Seen_keys           # the key, after the others
    slli    t0, t5, 5
    add     t4, t4, t0
    ld      t0, SeenRecallItem_kind(s6)
    sd      t0, 0(t4)
    ld      t0, SeenRecallItem_a(s6)
    sd      t0, 8(t4)
    ld      t0, SeenRecallItem_b(s6)
    sd      t0, 16(t4)
    ld      t0, SeenRecallItem_c(s6)
    sd      t0, 24(t4)
    addi    t5, t5, 1
    sd      t5, (Seen_keys + 8)(s1)
    ld      t0, SeenMark_added_keys(s4)
    addi    t0, t0, 1
    sd      t0, SeenMark_added_keys(s4)
    j       70f
20: addi    t0, s6, SeenRecallItem_root     # bits: none of (root, a, epoch) in seen
    addi    t1, sp, L
    COPY32  t1, t0
    ld      t0, SeenRecallItem_a(s6)
    sd      t0, (L + 32)(sp)
    ld      t1, SeenRecallItem_b(s6)
    sd      t1, (L + 40)(sp)
    PART    t4, t5, s1, Seen_bits
21: beqz    t5, 22f
    ld      t6, SeenBits_kind(t4)
    li      t2, SEEN_AGGREGATE
    bne     t6, t2, 23f
    ld      t6, SeenBits_a(t4)
    bne     t6, t0, 23f
    ld      t6, SeenBits_b(t4)
    bne     t6, t1, 23f
    addi    t2, t4, SeenBits_root
    addi    t3, sp, L
    NE32    t2, t3, 23f
    j       70f
23: addi    t4, t4, SeenBits__mem
    addi    t5, t5, -1
    j       21b
22: mv      a0, s2
    li      a1, HIST_AGGREGATE
    addi    a2, sp, L
    li      a3, 6
    ld      a4, (L + 40)(sp)
    call    lantern_seen_history_find
    beqz    a0, 70f
    mv      s7, a0
    mv      s9, a1
    ld      t0, SeenChunk_count(s9)
    li      t1, HistBits__mem
    mul     t0, t0, t1
    addi    s8, s9, SEEN_CHUNK_FIXED
    add     s8, s8, t0
24: bgeu    s7, s8, 70f                     # each entry of the key
    li      t2, 0
25: li      t0, 6
    bgeu    t2, t0, 26f
    slli    t0, t2, 3
    add     t1, s7, t0
    ld      t1, 0(t1)
    add     t0, sp, t0
    ld      t0, L(t0)
    bne     t1, t0, 70f
    addi    t2, t2, 1
    j       25b
26: ld      t3, HistBits_length(s7)         # its bits inside the chunk, at most SEEN_BITS_BYTES
    li      t0, SEEN_BITS_BYTES * 8
    bltu    t0, t3, 29f
    ld      t4, HistBits_bits(s7)
    addi    t5, t3, 63
    srli    t5, t5, 6
    slli    t5, t5, 3
    ld      t0, SeenChunk_bytes(s9)
    bgeu    t4, t0, 29f
    sub     t0, t0, t4
    bltu    t0, t5, 29f
    bnez    s10, 27f
    ld      t0, (L + 56)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 56)(sp)
    j       29f
27: PART    t0, t1, s1, Seen_bits           # the SeenBits, after the others
    li      t2, SeenBits__mem
    mul     t2, t1, t2
    add     t0, t0, t2
    li      t2, SEEN_AGGREGATE
    sd      t2, SeenBits_kind(t0)
    addi    t2, t0, SeenBits_root
    COPY32  t2, s7
    ld      t2, HistBits_a(s7)
    sd      t2, SeenBits_a(t0)
    ld      t2, HistBits_epoch(s7)
    sd      t2, SeenBits_b(t0)
    sd      t3, SeenBits_length(t0)
    add     t4, s9, t4
    addi    t0, t0, SeenBits_bits
28: beqz    t5, 281f
    ld      t2, 0(t4)
    sd      t2, 0(t0)
    addi    t4, t4, 8
    addi    t0, t0, 8
    addi    t5, t5, -8
    j       28b
281: addi   t1, t1, 1
    sd      t1, (Seen_bits + 8)(s1)
    ld      t0, SeenMark_added_bits(s4)
    addi    t0, t0, 1
    sd      t0, SeenMark_added_bits(s4)
29: addi    s7, s7, HistBits__mem
    j       24b
70: addi    s6, s6, SeenRecallItem__mem
    addi    s5, s5, -1
    j       1b
80: bnez    s10, 90f                        # counted: room for them, then add them
    ld      t0, Seen_bits(s1)
    ld      t1, Seen_keys(s1)
    sub     t0, t0, t1
    srli    t0, t0, 5
    ld      t1, (Seen_keys + 8)(s1)
    sub     t0, t0, t1
    ld      t1, (L + 48)(sp)
    bltu    t0, t1, 98f
    ld      t0, Seen_blocks(s1)
    ld      t1, Seen_bits(s1)
    sub     t0, t0, t1
    li      t1, SeenBits__mem
    divu    t0, t0, t1
    ld      t1, (Seen_bits + 8)(s1)
    sub     t0, t0, t1
    ld      t1, (L + 56)(sp)
    bltu    t0, t1, 98f
    li      s10, 1
    j       0b
90: li      a0, LANTERN_OK
    LEAVE 64
98: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
99: li      a0, LANTERN_INVALID_EVENT
    LEAVE 64
END_FUNCTION lantern_seen_recall

/* (seen, mark): networking.md. A leaf; uses t0-t6, a2-a5. */
LEAF lantern_seen_forget
    ld      t0, SeenMark_keys(a1)           # the keys it added: those after them move down, zero after
    ld      t1, SeenMark_added_keys(a1)
    beqz    t1, 2f
    PART    t2, t3, a0, Seen_keys
    slli    t4, t0, 5
    add     t2, t2, t4                      # the first added
    slli    t4, t1, 5
    add     t5, t2, t4                      # the first after them
    sub     t6, t3, t0
    sub     t6, t6, t1
    slli    t6, t6, 5
1:  beqz    t6, 11f
    ld      a2, 0(t5)
    sd      a2, 0(t2)
    addi    t5, t5, 8
    addi    t2, t2, 8
    addi    t6, t6, -8
    j       1b
11: sub     t3, t3, t1
    sd      t3, (Seen_keys + 8)(a0)
12: sd      zero, 0(t2)
    addi    t2, t2, 8
    addi    t4, t4, -8
    bnez    t4, 12b
2:  ld      t0, SeenMark_bits(a1)           # the same for the bits
    ld      t1, SeenMark_added_bits(a1)
    beqz    t1, 9f
    PART    t2, t3, a0, Seen_bits
    li      a3, SeenBits__mem
    mul     t4, t0, a3
    add     t2, t2, t4
    mul     t4, t1, a3
    add     t5, t2, t4
    sub     t6, t3, t0
    sub     t6, t6, t1
    mul     t6, t6, a3
3:  beqz    t6, 31f
    ld      a2, 0(t5)
    sd      a2, 0(t2)
    addi    t5, t5, 8
    addi    t2, t2, 8
    addi    t6, t6, -8
    j       3b
31: sub     t3, t3, t1
    sd      t3, (Seen_bits + 8)(a0)
32: sd      zero, 0(t2)
    addi    t2, t2, 8
    addi    t4, t4, -8
    bnez    t4, 32b
9:  li      a0, LANTERN_OK
    ret
END_FUNCTION lantern_seen_forget

/* Part ref of seen s1 takes the count at s2 + at; zero the bytes of the entries past it, of size bytes each. */
.macro SEEN_RESTORE ref, at, size
    ld      t0, \at(s2)
    ld      t1, ((\ref) + 8)(s1)
    sd      t0, ((\ref) + 8)(s1)
    bgeu    t0, t1, 107f
    sub     a1, t1, t0
    li      t2, (\size)
    mul     a1, a1, t2
    mul     t0, t0, t2
    ld      a0, (\ref)(s1)
    add     a0, s1, a0
    add     a0, a0, t0
    call    lantern_zero
107:
.endm

/* (seen, counts): networking.md. s1 seen, s2 counts. */
FUNCTION lantern_seen_restore
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    SEEN_RESTORE Seen_keys, 0, SeenKey__mem
    SEEN_RESTORE Seen_bits, 8, SeenBits__mem
    SEEN_RESTORE Seen_blocks, 16, SeenBlock__mem
    ld      t0, 24(s2)                      # the headers: their count, and zero after their bytes
    sd      t0, (Seen_headers + 8)(s1)
    ld      t0, 32(s2)
    ld      t1, Seen_header_bytes(s1)
    sd      t0, Seen_header_bytes(s1)
    bgeu    t0, t1, 9f
    sub     a1, t1, t0
    ld      a0, Seen_headers(s1)
    add     a0, s1, a0
    add     a0, a0, t0
    call    lantern_zero
9:  li      a0, LANTERN_OK
    LEAVE 0
END_FUNCTION lantern_seen_restore

/*
 * (a, b, out): networking.md. s1 a, s2 b, s3 the merged chunk, s4 the words compared, s5 the entry
 * bytes, s6 the kind, s7 a's next entry, s8 a's entries left, s9 b's next entry, s10 b's entries left,
 * a3 the next entry written, a4 the next word of bits, a5 the chunk of the entry taken.
 */
FUNCTION lantern_seen_chunk_merge
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    ld      t0, SeenChunk_bytes(s1)         # the merged chunk's bytes
    ld      t1, SeenChunk_bytes(s2)
    add     t0, t0, t1
    addi    t0, t0, -SEEN_CHUNK_FIXED
    ld      t1, 0(a2)                       # out has room for them
    ld      t2, 8(a2)
    ld      t3, 16(a2)
    bltu    t1, t2, 98f
    sub     t1, t1, t2
    bltu    t1, t3, 98f
    sub     t1, t1, t3
    bltu    t1, t0, 98f
    add     s3, a2, t2
    add     s3, s3, t3
    add     t3, t3, t0
    sd      t3, 16(a2)
    sd      t0, SeenChunk_bytes(s3)
    ld      s6, SeenChunk_kind(s1)
    sd      s6, SeenChunk_kind(s3)
    HIST_ELEM s5, s6, t0
    srli    s4, s5, 3
    li      t0, HIST_AGGREGATE
    bne     s6, t0, 1f
    li      s4, 6                           # the root, a and the epoch
1:  ld      t0, SeenChunk_epoch_lo(s1)
    ld      t1, SeenChunk_epoch_lo(s2)
    bltu    t0, t1, 11f
    mv      t0, t1
11: sd      t0, SeenChunk_epoch_lo(s3)
    ld      t0, SeenChunk_epoch_hi(s1)
    ld      t1, SeenChunk_epoch_hi(s2)
    bgeu    t0, t1, 12f
    mv      t0, t1
12: sd      t0, SeenChunk_epoch_hi(s3)
    ld      s8, SeenChunk_count(s1)
    ld      s10, SeenChunk_count(s2)
    add     t0, s8, s10
    sd      t0, SeenChunk_count(s3)
    addi    s7, s1, SEEN_CHUNK_FIXED
    addi    s9, s2, SEEN_CHUNK_FIXED
    addi    a3, s3, SEEN_CHUNK_FIXED
    mul     t0, t0, s5                      # the bits follow the entries
    add     a4, a3, t0
2:  bnez    s8, 21f                         # the lower entry next; a's first when equal
    beqz    s10, 8f
    j       31f
21: beqz    s10, 30f
    mv      t4, s9
    mv      t3, s7
    SORT_LESS 31f, 30f
30: mv      a0, s7
    mv      a5, s1
    add     s7, s7, s5
    addi    s8, s8, -1
    j       3f
31: mv      a0, s9
    mv      a5, s2
    add     s9, s9, s5
    addi    s10, s10, -1
3:  li      t0, 0                           # the entry
32: add     t1, a0, t0
    ld      t2, 0(t1)
    add     t1, a3, t0
    sd      t2, 0(t1)
    addi    t0, t0, 8
    bltu    t0, s5, 32b
    li      t0, HIST_AGGREGATE
    bne     s6, t0, 35f
    ld      t0, HistBits_length(a0)         # and its bits, at their new offset
    addi    t0, t0, 63
    srli    t0, t0, 6
    ld      t1, HistBits_bits(a0)
    add     t1, a5, t1
    sub     t2, a4, s3
    sd      t2, HistBits_bits(a3)
33: beqz    t0, 35f
    ld      t2, 0(t1)
    sd      t2, 0(a4)
    addi    t1, t1, 8
    addi    a4, a4, 8
    addi    t0, t0, -1
    j       33b
35: add     a3, a3, s5
    j       2b
8:  li      a0, LANTERN_OK
    LEAVE 0
98: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_seen_chunk_merge
