/*
 * Sizing, making, growing and pruning Seen, RISC-V: it reads no fork's layouts.
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
 * Drop the entries of past epochs and slots from seen a0, with the time and the finalized epoch of
 * store a1 (networking.md). A leaf; uses t0-t6, a2-a5. a2 the first epoch kept, a3 the first sync
 * slot kept, a4 the finalized slot; t3 the entry read, t5 the entry written, t4 the entries left.
 */
LEAF lantern_seen_prune
    LDQ     t0, a1, Store_time_ms           # s: the current slot, 0 before genesis
    LDQ     t1, a1, Store_genesis_time_ms
    sub     t2, t0, t1
    bgeu    t0, t1, 1f
    li      t2, 0
1:  LDQ     t1, a1, (Store_config + CONFIG_SLOT_DURATION_MS)
    li      t0, 0
    beqz    t1, 2f
    divu    t0, t2, t1
2:  li      a3, 0                           # the first sync slot kept: s - 1
    beqz    t0, 3f
    addi    a3, t0, -1
3:  LDQ     t1, a1, (Store_config + CONFIG_ATTESTATION_PROPAGATION_SLOT_RANGE)
    li      a2, 0                           # the first epoch kept: e - 1, with e the epoch of s - range - 1
    bltu    t0, t1, 4f
    sub     t0, t0, t1
    beqz    t0, 4f
    addi    t0, t0, -1
    li      t1, SLOTS_PER_EPOCH
    divu    t0, t0, t1
    beqz    t0, 4f
    addi    a2, t0, -1
4:  LDQ     t0, a1, Store_finalized_checkpoint  # f: the first slot of the finalized epoch
    li      t1, SLOTS_PER_EPOCH
    mulhu   t2, t0, t1
    mul     a4, t0, t1
    beqz    t2, 5f
    li      a4, -1
5:  PART    t3, t4, a0, Seen_keys           # the keys
    mv      t5, t3
10: beqz    t4, 19f
    ld      t0, SeenKey_kind(t3)
    ld      t1, SeenKey_a(t3)
    li      t2, SEEN_ATTESTATION
    beq     t0, t2, 11f
    li      t2, SEEN_AGGREGATOR_EPOCH
    beq     t0, t2, 11f
    li      t2, SEEN_PROPOSER_SLOT
    beq     t0, t2, 12f
    li      t2, SEEN_DATA_COLUMN
    beq     t0, t2, 12f
    li      t2, SEEN_BLOB_SIDECAR
    beq     t0, t2, 12f
    li      t2, SEEN_SYNC_CONTRIBUTION
    beq     t0, t2, 13f
    li      t2, SEEN_SYNC_MESSAGE
    bne     t0, t2, 15f
13: bltu    t1, a3, 16f                     # a sync slot: kept from s - 1
    j       15f
11: bltu    t1, a2, 16f                     # an epoch: kept from the first epoch kept
    j       15f
12: bgeu    a4, t1, 16f                     # a block's slot: kept above f
15: beq     t3, t5, 14f                     # kept: moved down over the dropped ones
    ld      t0, 0(t3)
    ld      t1, 8(t3)
    ld      t2, 16(t3)
    ld      t6, 24(t3)
    sd      t0, 0(t5)
    sd      t1, 8(t5)
    sd      t2, 16(t5)
    sd      t6, 24(t5)
14: addi    t5, t5, SeenKey__mem
16: addi    t3, t3, SeenKey__mem
    addi    t4, t4, -1
    j       10b
19: ld      t0, Seen_keys(a0)               # the count: the entries written
    add     t0, a0, t0
    sub     t5, t5, t0
    srli    t5, t5, 5
    sd      t5, (Seen_keys + 8)(a0)
    PART    t3, t4, a0, Seen_bits           # the bits
    mv      t5, t3
20: beqz    t4, 29f
    ld      t0, SeenBits_kind(t3)
    li      t2, SEEN_AGGREGATE
    bne     t0, t2, 21f
    ld      t1, SeenBits_b(t3)              # an aggregate: its target epoch kept from the first epoch kept
    bltu    t1, a2, 26f
    j       25f
21: li      t2, SEEN_CONTRIBUTION
    bne     t0, t2, 25f
    ld      t1, SeenBits_a(t3)              # a contribution: its slot kept from s - 1
    bltu    t1, a3, 26f
25: beq     t3, t5, 23f
    li      a5, 0
    li      t6, SeenBits__mem
24: add     t0, t3, a5
    ld      t1, 0(t0)
    ld      t2, 8(t0)
    add     t0, t5, a5
    sd      t1, 0(t0)
    sd      t2, 8(t0)
    addi    a5, a5, 16
    bltu    a5, t6, 24b
23: addi    t5, t5, SeenBits__mem
26: addi    t3, t3, SeenBits__mem
    addi    t4, t4, -1
    j       20b
29: ld      t0, Seen_bits(a0)
    add     t0, a0, t0
    sub     t5, t5, t0
    li      t1, SeenBits__mem
    divu    t5, t5, t1
    sd      t5, (Seen_bits + 8)(a0)
    li      a0, LANTERN_OK
    ret
END_FUNCTION lantern_seen_prune
