/*
 * Networking rules, RISC-V. Requirements: docs/reference/networking.md.
 */

.if FORK >= FORK_FULU
/*
 * s1 out entries, s2 NUMBER_OF_CUSTODY_GROUPS, s3 custody_group_count, s4 groups found, s5 out.
 * Locals: L current_id (32), L+32 the digest (32).
 */
SPEC_FUNCTION get_custody_groups
    ENTER 64
    ld      s2, CONFIG_NUMBER_OF_CUSTODY_GROUPS(a2)
    ld      s3, 0(a1)
    mv      s5, a3
    bltu    s2, s3, 8f                      # assert custody_group_count <= NUMBER_OF_CUSTODY_GROUPS
    ld      t0, 0(s5)                       # room for custody_group_count entries
    li      t1, LIST_FIXED
    bltu    t0, t1, 9f
    sub     t0, t0, t1
    srli    t0, t0, 3
    bltu    t0, s3, 9f
    addi    t0, sp, L                       # current_id = node_id
    COPY32  t0, a0
    addi    s1, s5, LIST_FIXED
    bne     s3, s2, 2f
    li      t0, 0                           # every group: 0 to NUMBER_OF_CUSTODY_GROUPS - 1
    mv      t1, s1
    beqz    s3, 6f
1:  sd      t0, 0(t1)
    addi    t1, t1, 8
    addi    t0, t0, 1
    bltu    t0, s3, 1b
    j       6f
2:  li      s4, 0
3:  bgeu    s4, s3, 6f                      # while len(custody_groups) < custody_group_count
    addi    a0, sp, L                       # sha256(uint_to_bytes(current_id))
    li      a1, 32
    addi    a2, sp, L + 32
    call    lantern_sha256_short
    ld      t0, (L + 32)(sp)                # bytes_to_uint64(digest[0:8]) % NUMBER_OF_CUSTODY_GROUPS
    remu    t0, t0, s2
    li      t1, 0                           # the first entry not below the group
4:  bgeu    t1, s4, 5f
    slli    t2, t1, 3
    add     t2, s1, t2
    ld      t3, 0(t2)
    beq     t3, t0, 55f                     # already in custody_groups
    bgeu    t3, t0, 5f
    addi    t1, t1, 1
    j       4b
5:  slli    t2, s4, 3                       # move the entries from t1 up by one
    add     t2, s1, t2
    slli    t3, t1, 3
    add     t3, s1, t3
51: bgeu    t3, t2, 52f
    ld      t4, -8(t2)
    sd      t4, 0(t2)
    addi    t2, t2, -8
    j       51b
52: sd      t0, 0(t3)
    addi    s4, s4, 1
55: ld      t0, (L + 0)(sp)                 # current_id += 1, wrapping from UINT256_MAX to 0
    addi    t0, t0, 1
    sd      t0, (L + 0)(sp)
    seqz    t1, t0                          # the carry
    ld      t0, (L + 8)(sp)
    add     t0, t0, t1
    sd      t0, (L + 8)(sp)
    seqz    t2, t0
    and     t1, t1, t2
    ld      t0, (L + 16)(sp)
    add     t0, t0, t1
    sd      t0, (L + 16)(sp)
    seqz    t2, t0
    and     t1, t1, t2
    ld      t0, (L + 24)(sp)
    add     t0, t0, t1
    sd      t0, (L + 24)(sp)
    j       3b
6:  li      t0, LIST_FIXED
    sd      t0, 8(s5)                       # offset 24, count
    sd      s3, 16(s5)
    li      a0, LANTERN_OK
    LEAVE 64
8:  li      a0, LANTERN_INVALID_CUSTODY_GROUP
    LEAVE 64
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END get_custody_groups

SPEC_LEAF compute_columns_for_custody_group
    ld      t0, CONFIG_NUMBER_OF_CUSTODY_GROUPS(a1)
    ld      t1, 0(a0)
    bgeu    t1, t0, 8f                      # assert custody_group < NUMBER_OF_CUSTODY_GROUPS
    li      t2, NUMBER_OF_COLUMNS           # columns_per_group
    divu    t2, t2, t0
    ld      t3, 0(a2)
    li      t4, LIST_FIXED
    bltu    t3, t4, 9f
    sub     t3, t3, t4
    srli    t3, t3, 3
    bltu    t3, t2, 9f
    sd      t4, 8(a2)
    sd      t2, 16(a2)
    addi    t3, a2, LIST_FIXED
    beqz    t2, 2f
1:  sd      t1, 0(t3)                       # NUMBER_OF_CUSTODY_GROUPS * index + custody_group
    addi    t3, t3, 8
    add     t1, t1, t0
    addi    t2, t2, -1
    bnez    t2, 1b
2:  li      a0, LANTERN_OK
    ret
8:  li      a0, LANTERN_INVALID_CUSTODY_GROUP
    ret
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    ret
SPEC_END compute_columns_for_custody_group
.endif

/* ---------------------------------------------------------------- Seen */

.if SeenKey__mem != 32 || SeenBits__mem != 320 || SeenBlock__mem != 40 || SEEN_BITS_BYTES * 8 < MAX_VALIDATORS_PER_COMMITTEE || SEEN_BITS_BYTES * 8 < SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT
.error "the gossip code assumes the Seen layouts of include/lantern.inc"
.endif

/* a0 = 1 when seen a0 holds the SeenKey (a1 kind, a2 a, a3 b, a4 c), else 0. A leaf; uses a5, t0-t2. */
LOCAL_FUNCTION lantern_seen_find_key
    UNWIND_END_PROLOGUE
    PART    a5, t0, a0, Seen_keys
1:  beqz    t0, 3f
    ld      t1, 0(a5)
    bne     t1, a1, 2f
    ld      t1, 8(a5)
    bne     t1, a2, 2f
    ld      t1, 16(a5)
    bne     t1, a3, 2f
    ld      t1, 24(a5)
    beq     t1, a4, 4f
2:  addi    a5, a5, SeenKey__mem
    addi    t0, t0, -1
    j       1b
3:  li      a0, 0
    ret
4:  li      a0, 1
    ret
END_FUNCTION lantern_seen_find_key

/* a0 = the free SeenKey entries of seen a0. A leaf; uses a1, a2. */
LOCAL_FUNCTION lantern_seen_key_room
    UNWIND_END_PROLOGUE
    ld      a1, Seen_keys(a0)
    ld      a2, Seen_bits(a0)
    sub     a2, a2, a1
    srli    a2, a2, 5
    ld      a1, (Seen_keys + 8)(a0)
    sub     a0, a2, a1
    ret
END_FUNCTION lantern_seen_key_room

/* Append the SeenKey (a1 kind, a2 a, a3 b, a4 c) to seen a0, which has room. A leaf; uses a5, t0. */
LOCAL_FUNCTION lantern_seen_add_key
    UNWIND_END_PROLOGUE
    PART    a5, t0, a0, Seen_keys
    slli    t1, t0, 5
    add     a5, a5, t1
    sd      a1, 0(a5)
    sd      a2, 8(a5)
    sd      a3, 16(a5)
    sd      a4, 24(a5)
    addi    t0, t0, 1
    sd      t0, (Seen_keys + 8)(a0)
    ret
END_FUNCTION lantern_seen_add_key

/* a0 = the free SeenBits entries of seen a0. A leaf; uses a1-a3. */
LOCAL_FUNCTION lantern_seen_bits_room
    UNWIND_END_PROLOGUE
    ld      a1, Seen_bits(a0)
    ld      a2, Seen_blocks(a0)
    sub     a2, a2, a1
    li      a3, SeenBits__mem
    divu    a2, a2, a3
    ld      a1, (Seen_bits + 8)(a0)
    sub     a0, a2, a1
    ret
END_FUNCTION lantern_seen_bits_room

/*
 * is_non_strict_superset of the SeenBits of key (a1 kind, root at a2, a3 a, a4 b) in seen a0,
 * for the a6 bits at a5: a0 = 1 when one of them has every bit of a5 set. A leaf; uses a7, t0-t6.
 */
LOCAL_FUNCTION lantern_seen_superset
    UNWIND_END_PROLOGUE
    PART    t0, t1, a0, Seen_bits
    addi    t2, a6, 7
    srli    t2, t2, 3                       # bytes of the bits
1:  beqz    t1, 8f
    ld      t3, SeenBits_kind(t0)
    bne     t3, a1, 5f
    ld      t3, SeenBits_a(t0)
    bne     t3, a3, 5f
    ld      t3, SeenBits_b(t0)
    bne     t3, a4, 5f
    ld      t3, SeenBits_length(t0)         # a bitfield of another length: skipped
    bne     t3, a6, 5f
    li      t3, 0                           # the root, 4 bytes at a time
11: li      t4, 32
    bgeu    t3, t4, 12f
    add     t4, t0, t3
    lwu     t4, SeenBits_root(t4)
    add     t5, a2, t3
    lwu     t5, 0(t5)
    bne     t4, t5, 5f
    addi    t3, t3, 4
    j       11b
12: li      t3, 0
2:  bgeu    t3, t2, 9f
    add     t4, t0, t3
    lbu     t4, SeenBits_bits(t4)
    add     t5, a5, t3
    lbu     t5, 0(t5)
    not     t6, t4                          # a bit of the new bits outside the prior
    and     t6, t6, t5
    bnez    t6, 5f
    addi    t3, t3, 1
    j       2b
5:  addi    t0, t0, SeenBits__mem
    addi    t1, t1, -1
    j       1b
8:  li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION lantern_seen_superset

/*
 * Append the SeenBits of key (a1 kind, root at a2, a3 a, a4 b) and the a6 bits at a5 to seen a0,
 * which has room. Locals: sp+0 entry, sp+8 bits, sp+16 length.
 */
LOCAL_FUNCTION lantern_seen_add_bits
    FRAME 32
    PART    t0, t1, a0, Seen_bits
    li      t2, SeenBits__mem
    mul     t2, t1, t2
    add     t0, t0, t2
    addi    t1, t1, 1
    sd      t1, (Seen_bits + 8)(a0)
    sd      a1, SeenBits_kind(t0)
    li      t3, 0                           # the root, 4 bytes at a time
1:  li      t4, 32
    bgeu    t3, t4, 2f
    add     t4, a2, t3
    lwu     t4, 0(t4)
    add     t5, t0, t3
    sw      t4, SeenBits_root(t5)
    addi    t3, t3, 4
    j       1b
2:  sd      a3, SeenBits_a(t0)
    sd      a4, SeenBits_b(t0)
    sd      a6, SeenBits_length(t0)
    sd      t0, 0(sp)
    sd      a5, 8(sp)
    sd      a6, 16(sp)
    addi    a0, t0, SeenBits_bits
    li      a1, SEEN_BITS_BYTES
    call    lantern_zero
    ld      a0, 0(sp)
    addi    a0, a0, SeenBits_bits
    ld      a1, 8(sp)
    ld      a2, 16(sp)
    addi    a2, a2, 7
    srli    a2, a2, 3
    call    lantern_copy
    UNFRAME 32
END_FUNCTION lantern_seen_add_bits

/* a0 = the SeenHeader of block root a1 in seen a0, or 0. A leaf; uses a2-a4, t0, t1. */
LOCAL_FUNCTION lantern_seen_find_header
    UNWIND_END_PROLOGUE
    PART    a2, a3, a0, Seen_headers
1:  beqz    a3, 3f
    li      t0, 0                           # the block root, 4 bytes at a time
11: li      t1, 32
    bgeu    t0, t1, 4f
    add     t1, a2, t0
    lwu     t1, SeenHeader_block_root(t1)
    add     a4, a1, t0
    lwu     a4, 0(a4)
    bne     t1, a4, 2f
    addi    t0, t0, 4
    j       11b
2:  ld      t0, SeenHeader_header(a2)       # the next entry: 64 + the header value's size
    add     a2, a2, t0
    addi    a2, a2, SeenHeader_header
    addi    a3, a3, -1
    j       1b
3:  li      a0, 0
    ret
4:  mv      a0, a2
    ret
END_FUNCTION lantern_seen_find_header

/* ---------------------------------------------------------------- Gossip helpers */

/* dst = compute_time_at_slot_ms(genesis_time_ms of store st, slot), UINT64_MAX when it does not fit. Uses a6, a7. */
.macro SLOT_TIME dst, st, slot
    ld      a6, (Store_config + CONFIG_SLOT_DURATION_MS)(\st)
    mulhu   a7, \slot, a6
    mul     \dst, \slot, a6
    bnez    a7, 98f
    ld      a6, Store_genesis_time_ms(\st)
    add     \dst, \dst, a6
    bgeu    \dst, a6, 99f
98: li      \dst, -1
99:
.endm

/* dst = t + MAXIMUM_GOSSIP_CLOCK_DISPARITY of store st, UINT64_MAX when it does not fit. Uses a6. dst is not t. */
.macro WITH_DISPARITY dst, st, t
    ld      a6, (Store_config + CONFIG_MAXIMUM_GOSSIP_CLOCK_DISPARITY)(\st)
    add     \dst, \t, a6
    bgeu    \dst, a6, 99f
    li      \dst, -1
99:
.endm

/* a0 = lantern_is_future_slot(store a0, slot a1, current_time_ms a2). A leaf; uses a3, a4, a6, a7. */
LOCAL_FUNCTION lantern_is_future_slot
    UNWIND_END_PROLOGUE
    SLOT_TIME a3, a0, a1
    WITH_DISPARITY a4, a0, a2
    sltu    a0, a4, a3
    ret
END_FUNCTION lantern_is_future_slot

/* a0 = lantern_is_within_slot_range(store a0, slot a1, slot_range a2, current_time_ms a3). A leaf; uses a4, a5, t0, a6, a7. */
LOCAL_FUNCTION lantern_is_within_slot_range
    UNWIND_END_PROLOGUE
    SLOT_TIME a4, a0, a1                    # current_time_ms + MAXIMUM_GOSSIP_CLOCK_DISPARITY < start_time_ms
    WITH_DISPARITY a5, a0, a3
    bltu    a5, a4, 8f
    add     t0, a1, a2                      # end_time_ms = time of slot + slot_range + 1
    bltu    t0, a1, 9f
    addi    t0, t0, 1
    beqz    t0, 9f
    SLOT_TIME a4, a0, t0
    WITH_DISPARITY a5, a0, a4               # end_time_ms + MAXIMUM_GOSSIP_CLOCK_DISPARITY < current_time_ms
    bltu    a5, a3, 8f
9:  li      a0, 1
    ret
8:  li      a0, 0
    ret
END_FUNCTION lantern_is_within_slot_range

/* a0 = lantern_is_current_or_previous_epoch(store a0, epoch a1, current_time_ms a2). s1 store, s2 epoch, s3 time. */
LOCAL_FUNCTION lantern_is_current_or_previous_epoch
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    srli    t0, s2, (64 - LOG2_SLOTS_PER_EPOCH)     # is_within_epoch(epoch): the start slot fits
    bnez    t0, 1f
    slli    a1, s2, LOG2_SLOTS_PER_EPOCH
    li      a2, SLOTS_PER_EPOCH - 1
    mv      a3, s3
    call    lantern_is_within_slot_range
    bnez    a0, 7f
1:  addi    t0, s2, 1                       # is_within_epoch(epoch + 1)
    beqz    t0, 6f
    srli    t1, t0, (64 - LOG2_SLOTS_PER_EPOCH)
    bnez    t1, 6f
    mv      a0, s1
    slli    a1, t0, LOG2_SLOTS_PER_EPOCH
    li      a2, SLOTS_PER_EPOCH - 1
    mv      a3, s3
    call    lantern_is_within_slot_range
    j       7f
6:  li      a0, 0
7:  LEAVE 0
END_FUNCTION lantern_is_current_or_previous_epoch

/*
 * a0 = lantern_is_future_epoch(store a0, epoch a1, current_time_ms a2); true when the time with
 * disparity is before genesis, where the spec's subtraction raises. A leaf; uses a3, a4, a6.
 */
LOCAL_FUNCTION lantern_is_future_epoch
    UNWIND_END_PROLOGUE
    WITH_DISPARITY a3, a0, a2
    ld      a4, Store_genesis_time_ms(a0)
    bltu    a3, a4, 9f
    sub     a3, a3, a4
    ld      a4, (Store_config + CONFIG_SLOT_DURATION_MS)(a0)
    divu    a3, a3, a4                      # current_slot
    srli    a3, a3, LOG2_SLOTS_PER_EPOCH
    sltu    a0, a3, a1
    ret
9:  li      a0, 1
    ret
END_FUNCTION lantern_is_future_epoch

/* a0 = compute_start_slot_at_epoch(finalized epoch of store a0), UINT64_MAX when it does not fit. A leaf; uses a1. */
LOCAL_FUNCTION lantern_finalized_slot
    UNWIND_END_PROLOGUE
    ld      a0, (Store_finalized_checkpoint + Checkpoint_epoch)(a0)
    srli    a1, a0, (64 - LOG2_SLOTS_PER_EPOCH)
    bnez    a1, 9f
    slli    a0, a0, LOG2_SLOTS_PER_EPOCH
    ret
9:  li      a0, -1
    ret
END_FUNCTION lantern_finalized_slot

/*
 * a0 = status, a1 = 1 when get_checkpoint_block(store a0, node a1, epoch a2) is the root at a3, else 0.
 * Locals: sp+0 store, sp+8 root.
 */
LOCAL_FUNCTION lantern_checkpoint_is
    FRAME 16
    sd      a0, 0(sp)
    sd      a3, 8(sp)
    call    lantern_checkpoint_block
    bnez    a0, 7f
    ld      a0, 0(sp)
    ld      a3, 8(sp)
    NODE    t0, a0, a1
    li      a1, 0
    NE32    t0, a3, 6f
    li      a1, 1
6:  li      a0, LANTERN_OK
7:  UNFRAME 16
END_FUNCTION lantern_checkpoint_is

/* lantern_checkpoint_is of the store's finalized checkpoint for node a1 of store a0. */
LOCAL_FUNCTION lantern_finalized_is_ancestor
    UNWIND_END_PROLOGUE
    ld      a2, (Store_finalized_checkpoint + Checkpoint_epoch)(a0)
    addi    a3, a0, (Store_finalized_checkpoint + Checkpoint_root)
    j       lantern_checkpoint_is
END_FUNCTION lantern_finalized_is_ancestor

/*
 * a0 = status, a1 = bls.Verify(public key a3, compute_signing_root(object a2 of type a1, domain a0), signature a4),
 * with scratch a5. Locals: sp+0 the root buffer (56: a ByteList header, then the root), sp+56 key, sp+64 signature,
 * sp+72 scratch.
 */
LOCAL_FUNCTION lantern_verify_with_domain
    FRAME 80
    sd      a3, 56(sp)
    sd      a4, 64(sp)
    sd      a5, 72(sp)
    mv      t0, a0
    mv      a0, a1
    mv      a1, a2
    mv      a2, t0
    mv      a3, a5
    addi    a4, sp, 24
    call    lantern_compute_signing_root
    bnez    a0, 7f
    ld      a0, 56(sp)
    ld      a1, 64(sp)
    mv      a2, sp
    ld      a3, 72(sp)
    call    lantern_verify_root_signature
7:  UNFRAME 80
END_FUNCTION lantern_verify_with_domain

/*
 * lantern_verify_with_domain with get_domain(state a0, domain type a1, epoch a2): object a4 of type a3,
 * public key a5, signature a6, scratch a7. Locals: sp+0 domain type, sp+8 epoch, sp+16 domain (32),
 * sp+48 type, object, key, signature, scratch.
 */
LOCAL_FUNCTION lantern_verify_signed
    FRAME 96
    sw      a1, 0(sp)
    sd      a2, 8(sp)
    sd      a3, 48(sp)
    sd      a4, 56(sp)
    sd      a5, 64(sp)
    sd      a6, 72(sp)
    sd      a7, 80(sp)
    mv      a1, sp
    addi    a2, sp, 8
    mv      a3, a7
    addi    a4, sp, 16
    call    lantern_get_domain
    bnez    a0, 7f
    addi    a0, sp, 16
    ld      a1, 48(sp)
    ld      a2, 56(sp)
    ld      a3, 64(sp)
    ld      a4, 72(sp)
    ld      a5, 80(sp)
    call    lantern_verify_with_domain
7:  UNFRAME 96
END_FUNCTION lantern_verify_signed

/* dst = &state.validators[idx] of state st; branch to fail when idx is not below the count. Uses a6, a7. */
.macro VALIDATOR_AT dst, st, idx, fail
    PART    \dst, a6, \st, BeaconState_validators
    bgeu    \idx, a6, \fail
    slli    a6, \idx, 7
    add     \dst, \dst, a6
.endm

/*
 * The block of the root at a2, from store a0 and seen a1: a0 = its node or NODE_NONE, a1 = 2 for a node
 * of the store, 1 for a block of seen, 0 when unknown, a2 = its payload status. Locals: store, seen, root.
 */
LOCAL_FUNCTION lantern_block_lookup
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    mv      a1, a2
    call    lantern_find_node
    li      t0, -1
    beq     a0, t0, 1f
    ld      t1, 0(sp)
    NODE    t2, t1, a0
    ld      a2, BlockNode_payload_status(t2)
    li      a1, 2
    UNFRAME 32
1:  ld      a0, 8(sp)
    ld      a1, 16(sp)
    call    lantern_seen_find_block
    beqz    a0, 2f
    ld      a2, SeenBlock_payload_status(a0)
    li      a0, -1
    li      a1, 1
    UNFRAME 32
2:  li      a0, -1
    li      a1, 0
    li      a2, PAYLOAD_STATUS_NOT_VALIDATED
    UNFRAME 32
END_FUNCTION lantern_block_lookup

/* ---------------------------------------------------------------- Gossip: operations */

/*
 * s1 seen, s2 store, s3 signed exit, s4 current_time_ms, s5 head state, s6 scratch, s7 result,
 * s8 validator, s9 validator index. Locals: L current epoch, L+8 predicate, L+16 domain type, L+24 domain (32).
 */
SPEC_FUNCTION validate_voluntary_exit_gossip
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(a3)
    mv      s5, a4
    mv      s6, a5
    mv      s7, a6
    sd      zero, 0(s7)
    NEED_SCRATCH s6, s5, 0, 9f
    ld      s9, (SignedVoluntaryExit_message + VoluntaryExit_validator_index)(s3)
    mv      a0, s1                          # [IGNORE] the first valid exit for the validator
    li      a1, SEEN_VOLUNTARY_EXIT
    mv      a2, s9
    li      a3, 0
    li      a4, 0
    call    lantern_seen_find_key
    bnez    a0, 4f
    mv      a0, s2                          # [IGNORE] the exit epoch is not in the future
    ld      a1, (SignedVoluntaryExit_message + VoluntaryExit_epoch)(s3)
    mv      a2, s4
    call    lantern_is_future_epoch
    bnez    a0, 4f
    VALIDATOR_AT s8, s5, s9, 5f             # [REJECT] the validator index is valid
    mv      a0, s5
    addi    a1, sp, L
    call    lantern_get_current_epoch
    ld      t0, Validator_exit_epoch(s8)    # [IGNORE] the validator has not initiated exit
    li      t1, -1
    bne     t0, t1, 4f
    mv      a0, s8                          # [REJECT] the validator is active
    addi    a1, sp, L
    addi    a2, sp, L + 8
    call    lantern_is_active_validator
    ld      t0, (L + 8)(sp)
    beqz    t0, 5f
    ld      t0, Validator_activation_epoch(s8)  # [REJECT] active for SHARD_COMMITTEE_PERIOD
    ld      t1, (Store_config + CONFIG_SHARD_COMMITTEE_PERIOD)(s2)
    add     t1, t0, t1
    bltu    t1, t0, 3f
    ld      t2, L(sp)
    bltu    t2, t1, 5f
.if FORK >= FORK_DENEB
    li      t0, DOMAIN_VOLUNTARY_EXIT       # [REJECT] the signature: compute_domain(DOMAIN_VOLUNTARY_EXIT, CAPELLA_FORK_VERSION, gvr)
    sw      t0, (L + 16)(sp)
    addi    a0, sp, L + 16
    addi    a1, s2, Store_config + CONFIG_CAPELLA_FORK_VERSION
    ADDQ    a2, s5, BeaconState_genesis_validators_root
    mv      a3, s6
    addi    a4, sp, L + 24
    call    lantern_compute_domain
    bnez    a0, 7f
    addi    a0, sp, L + 24
    ADDRESS a1, lantern_type_VoluntaryExit
    addi    a2, s3, SignedVoluntaryExit_message
    addi    a3, s8, Validator_pubkey
    addi    a4, s3, SignedVoluntaryExit_signature
    mv      a5, s6
    call    lantern_verify_with_domain
.else
    mv      a0, s5                          # [REJECT] the signature: get_domain(state, DOMAIN_VOLUNTARY_EXIT, voluntary_exit.epoch)
    li      a1, DOMAIN_VOLUNTARY_EXIT
    ld      a2, (SignedVoluntaryExit_message + VoluntaryExit_epoch)(s3)
    ADDRESS a3, lantern_type_VoluntaryExit
    addi    a4, s3, SignedVoluntaryExit_message
    addi    a5, s8, Validator_pubkey
    addi    a6, s3, SignedVoluntaryExit_signature
    mv      a7, s6
    call    lantern_verify_signed
.endif
    bnez    a0, 7f
    beqz    a1, 5f
    mv      a0, s1                          # seen.voluntary_exit_indices.add(validator_index)
    call    lantern_seen_key_room
    beqz    a0, 9f
    mv      a0, s1
    li      a1, SEEN_VOLUNTARY_EXIT
    mv      a2, s9
    li      a3, 0
    li      a4, 0
    call    lantern_seen_add_key
    j       8f
3:  li      a0, LANTERN_INVALID_OVERFLOW
    j       6f
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s7)
8:  li      a0, LANTERN_OK
7:  LEAVE 64
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END validate_voluntary_exit_gossip

/*
 * s1 seen, s2 store, s3 proposer slashing, s5 head state, s6 scratch, s7 result, s8 validator,
 * s9 proposer index, s10 signed header. Locals: L current epoch, L+8 predicate.
 */
SPEC_FUNCTION validate_proposer_slashing_gossip
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s5, a3
    mv      s6, a4
    mv      s7, a5
    sd      zero, 0(s7)
    NEED_SCRATCH s6, s5, 0, 9f
    ld      s9, (ProposerSlashing_signed_header_1 + SignedBeaconBlockHeader_message + BeaconBlockHeader_proposer_index)(s3)
    mv      a0, s1                          # [IGNORE] the first valid slashing for this proposer
    li      a1, SEEN_PROPOSER_SLASHING
    mv      a2, s9
    li      a3, 0
    li      a4, 0
    call    lantern_seen_find_key
    bnez    a0, 4f
    addi    t0, s3, ProposerSlashing_signed_header_1 + SignedBeaconBlockHeader_message
    addi    t1, s3, ProposerSlashing_signed_header_2 + SignedBeaconBlockHeader_message
    ld      t2, BeaconBlockHeader_slot(t0)  # [REJECT] the header slots match
    ld      t3, BeaconBlockHeader_slot(t1)
    bne     t2, t3, 5f
    ld      t2, BeaconBlockHeader_proposer_index(t0)    # [REJECT] the proposer indices match
    ld      t3, BeaconBlockHeader_proposer_index(t1)
    bne     t2, t3, 5f
    li      t2, 0                           # [REJECT] the headers are different
1:  li      t3, BeaconBlockHeader__mem
    bgeu    t2, t3, 5f
    add     t3, t0, t2
    ld      t3, 0(t3)
    add     t4, t1, t2
    ld      t4, 0(t4)
    bne     t3, t4, 2f
    addi    t2, t2, 8
    j       1b
2:  VALIDATOR_AT s8, s5, s9, 5f             # [REJECT] the proposer index is valid
    mv      a0, s5
    addi    a1, sp, L
    call    lantern_get_current_epoch
    mv      a0, s8                          # [REJECT] the proposer is slashable
    addi    a1, sp, L
    addi    a2, sp, L + 8
    call    lantern_is_slashable_validator
    ld      t0, (L + 8)(sp)
    beqz    t0, 5f
    addi    s10, s3, ProposerSlashing_signed_header_1   # [REJECT] the two signatures are valid
21: mv      a0, s5
    li      a1, DOMAIN_BEACON_PROPOSER
    ld      a2, (SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(s10)
    srli    a2, a2, LOG2_SLOTS_PER_EPOCH
    ADDRESS a3, lantern_type_BeaconBlockHeader
    addi    a4, s10, SignedBeaconBlockHeader_message
    addi    a5, s8, Validator_pubkey
    addi    a6, s10, SignedBeaconBlockHeader_signature
    mv      a7, s6
    call    lantern_verify_signed
    bnez    a0, 7f
    beqz    a1, 5f
    addi    t0, s3, ProposerSlashing_signed_header_2
    beq     s10, t0, 22f
    mv      s10, t0
    j       21b
22: mv      a0, s1                          # seen.proposer_slashing_indices.add(proposer_index)
    call    lantern_seen_key_room
    beqz    a0, 9f
    mv      a0, s1
    li      a1, SEEN_PROPOSER_SLASHING
    mv      a2, s9
    li      a3, 0
    li      a4, 0
    call    lantern_seen_add_key
    j       8f
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s7)
8:  li      a0, LANTERN_OK
7:  LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END validate_proposer_slashing_gossip

.if FORK >= FORK_CAPELLA
/*
 * s1 seen, s2 store, s3 signed change, s4 current_time_ms, s5 head state, s6 scratch, s7 result,
 * s8 validator, s9 validator index. Locals: L digest (32), L+32 domain type, L+40 domain (32).
 */
SPEC_FUNCTION validate_bls_to_execution_change_gossip
    ENTER 80
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(a3)
    mv      s5, a4
    mv      s6, a5
    mv      s7, a6
    sd      zero, 0(s7)
    NEED_SCRATCH s6, s5, 0, 9f
    ld      s9, (SignedBLSToExecutionChange_message + BLSToExecutionChange_validator_index)(s3)
    mv      a0, s1                          # [IGNORE] the first valid change for the validator
    li      a1, SEEN_BLS_CHANGE
    mv      a2, s9
    li      a3, 0
    li      a4, 0
    call    lantern_seen_find_key
    bnez    a0, 4f
    mv      a0, s2                          # [IGNORE] the current epoch is at or after CAPELLA_FORK_EPOCH
    ld      a1, (Store_config + CONFIG_CAPELLA_FORK_EPOCH)(s2)
    mv      a2, s4
    call    lantern_is_future_epoch
    bnez    a0, 4f
    VALIDATOR_AT s8, s5, s9, 5f             # [REJECT] the validator index is valid
    lbu     t0, Validator_withdrawal_credentials(s8)    # [REJECT] BLS withdrawal credentials
    li      t1, BLS_WITHDRAWAL_PREFIX
    bne     t0, t1, 5f
    addi    a0, s3, SignedBLSToExecutionChange_message + BLSToExecutionChange_from_bls_pubkey
    li      a1, 48
    addi    a2, sp, L
    call    lantern_sha256_short                    # [REJECT] withdrawal_credentials[1:] == sha256(pubkey)[1:]
    li      t0, BLS_WITHDRAWAL_PREFIX
    sb      t0, L(sp)
    addi    t0, s8, Validator_withdrawal_credentials
    addi    t1, sp, L
    NE32    t0, t1, 5f
    li      t0, DOMAIN_BLS_TO_EXECUTION_CHANGE  # [REJECT] the signature: compute_domain(type, GENESIS_FORK_VERSION, gvr)
    sw      t0, (L + 32)(sp)
    addi    a0, sp, L + 32
    addi    a1, s2, Store_config + CONFIG_GENESIS_FORK_VERSION
    ADDQ    a2, s5, BeaconState_genesis_validators_root
    mv      a3, s6
    addi    a4, sp, L + 40
    call    lantern_compute_domain
    bnez    a0, 7f
    addi    a0, sp, L + 40
    ADDRESS a1, lantern_type_BLSToExecutionChange
    addi    a2, s3, SignedBLSToExecutionChange_message
    addi    a3, s3, SignedBLSToExecutionChange_message + BLSToExecutionChange_from_bls_pubkey
    addi    a4, s3, SignedBLSToExecutionChange_signature
    mv      a5, s6
    call    lantern_verify_with_domain
    bnez    a0, 7f
    beqz    a1, 5f
    mv      a0, s1                          # seen.bls_to_execution_change_indices.add(validator_index)
    call    lantern_seen_key_room
    beqz    a0, 9f
    mv      a0, s1
    li      a1, SEEN_BLS_CHANGE
    mv      a2, s9
    li      a3, 0
    li      a4, 0
    call    lantern_seen_add_key
    j       8f
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s7)
8:  li      a0, LANTERN_OK
7:  LEAVE 80
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
SPEC_END validate_bls_to_execution_change_gossip
.endif

/* ---------------------------------------------------------------- Gossip: attestations */

.if FORK >= FORK_ELECTRA
/*
 * s1 seen, s2 store, s3 single attestation, s4 current_time_ms, s5 head state, s6 scratch, s7 result,
 * s8 subnet_id, s9 scratch size, s10 validator count.
 * Locals: L committees_per_slot, L+8 committee list, L+16 block node.
 */
SPEC_FUNCTION validate_beacon_attestation_gossip
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(a3)
    ld      s8, 0(a4)
    mv      s5, a5
    mv      s6, a6
    mv      s7, a7
    sd      zero, 0(s7)
    NEED_SCRATCH s6, s5, 3, 9f
    ld      s9, 0(s6)
    LDQ     s10, s5, BeaconState_validators + 8
    mv      a0, s1                          # [IGNORE] no attestation seen for (target epoch, attester)
    li      a1, SEEN_ATTESTATION
    ld      a2, (SingleAttestation_data + AttestationData_target + Checkpoint_epoch)(s3)
    ld      a3, SingleAttestation_attester_index(s3)
    li      a4, 0
    call    lantern_seen_find_key
    bnez    a0, 4f
    ld      t0, (SingleAttestation_data + AttestationData_index)(s3)   # [REJECT] data.index is zero
    bnez    t0, 5f
    mv      a0, s2                          # [IGNORE] the block voted for has been seen; [REJECT] it passed validation
    mv      a1, s1
    addi    a2, s3, SingleAttestation_data + AttestationData_beacon_block_root
    call    lantern_block_lookup
    beqz    a1, 4f
    li      t0, 2
    bne     a1, t0, 5f
    sd      a0, (L + 16)(sp)
    sd      s9, 0(s6)                       # [REJECT] the committee index is in range
    mv      a0, s5
    addi    a1, s3, SingleAttestation_data + AttestationData_target + Checkpoint_epoch
    mv      a3, s6
    addi    a4, sp, L
    ld      a2, (Store_config + CONFIG_COMMITTEE_CACHE)(s2)
    call    lantern_get_committee_count_per_slot
    CHECK_STATUS s7, 7f, 8f
    ld      t0, L(sp)
    ld      t1, SingleAttestation_committee_index(s3)
    bgeu    t1, t0, 5f
    ld      t2, (SingleAttestation_data + AttestationData_slot)(s3)    # [REJECT] the subnet: compute_subnet_for_attestation
    andi    t2, t2, SLOTS_PER_EPOCH - 1
    mul     t2, t2, t0
    add     t2, t2, t1
    andi    t2, t2, ATTESTATION_SUBNET_COUNT - 1
    bne     t2, s8, 5f
    mv      a0, s2                          # [IGNORE] not from a future slot
    ld      a1, (SingleAttestation_data + AttestationData_slot)(s3)
    mv      a2, s4
    call    lantern_is_future_slot
    bnez    a0, 4f
    mv      a0, s2                          # [IGNORE] the current or previous epoch
    ld      a1, (SingleAttestation_data + AttestationData_slot)(s3)
    srli    a1, a1, LOG2_SLOTS_PER_EPOCH
    mv      a2, s4
    call    lantern_is_current_or_previous_epoch
    beqz    a0, 4f
    ld      t0, (SingleAttestation_data + AttestationData_slot)(s3)    # [REJECT] the epoch matches the target
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    ld      t1, (SingleAttestation_data + AttestationData_target + Checkpoint_epoch)(s3)
    bne     t0, t1, 5f
    SCRATCH_LIST t0, s6, s9, 0, s10         # committee = get_beacon_committee(state, data.slot, committee_index)
    sd      t0, (L + 8)(sp)
    SCRATCH_GIVE s6, s9, 1, s10
    mv      a0, s5
    addi    a1, s3, SingleAttestation_data + AttestationData_slot
    addi    a2, s3, SingleAttestation_committee_index
    mv      a4, s6
    ld      a5, (L + 8)(sp)
    ld      a3, (Store_config + CONFIG_COMMITTEE_CACHE)(s2)
    call    lantern_get_beacon_committee
    CHECK_STATUS s7, 7f, 8f
    ld      t0, (L + 8)(sp)                 # [REJECT] the attester is in the committee
    ld      t1, LIST_COUNT(t0)
    addi    t0, t0, LIST_FIXED
    ld      t2, SingleAttestation_attester_index(s3)
1:  beqz    t1, 5f
    ld      t3, 0(t0)
    addi    t0, t0, 8
    beq     t3, t2, 2f
    addi    t1, t1, -1
    j       1b
2:  VALIDATOR_AT t0, s5, t2, 5f             # [REJECT] the signature
    SCRATCH_GIVE s6, s9, 1, s10
    mv      a0, s5
    li      a1, DOMAIN_BEACON_ATTESTER
    ld      a2, (SingleAttestation_data + AttestationData_target + Checkpoint_epoch)(s3)
    ADDRESS a3, lantern_type_AttestationData
    addi    a4, s3, SingleAttestation_data
    addi    a5, t0, Validator_pubkey
    addi    a6, s3, SingleAttestation_signature
    mv      a7, s6
    call    lantern_verify_signed
    bnez    a0, 7f
    beqz    a1, 5f
    mv      a0, s2                          # [REJECT] the target block is an ancestor of the LMD vote block
    ld      a1, (L + 16)(sp)
    ld      a2, (SingleAttestation_data + AttestationData_target + Checkpoint_epoch)(s3)
    addi    a3, s3, SingleAttestation_data + AttestationData_target + Checkpoint_root
    call    lantern_checkpoint_is
    CHECK_STATUS s7, 7f, 8f
    beqz    a1, 5f
    mv      a0, s2                          # [IGNORE] the finalized checkpoint is an ancestor of the block
    ld      a1, (L + 16)(sp)
    call    lantern_finalized_is_ancestor
    CHECK_STATUS s7, 7f, 8f
    beqz    a1, 4f
    mv      a0, s1                          # seen.attestation_validator_epochs.add(...)
    call    lantern_seen_key_room
    beqz    a0, 9f
    mv      a0, s1
    li      a1, SEEN_ATTESTATION
    ld      a2, (SingleAttestation_data + AttestationData_target + Checkpoint_epoch)(s3)
    ld      a3, SingleAttestation_attester_index(s3)
    li      a4, 0
    call    lantern_seen_add_key
    j       8f
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s7)
8:  li      a0, LANTERN_OK
7:  LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END validate_beacon_attestation_gossip
.else
/*
 * s1 seen, s2 store, s3 attestation, s4 current_time_ms, s5 head state, s6 scratch, s7 result,
 * s8 subnet_id, s9 scratch size, s10 validator count.
 * Locals: L committees_per_slot, L+8 committee list, L+16 block node, L+24 participant index, L+32 bit length.
 */
SPEC_FUNCTION validate_beacon_attestation_gossip
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(a3)
    ld      s8, 0(a4)
    mv      s5, a5
    mv      s6, a6
    mv      s7, a7
    sd      zero, 0(s7)
    NEED_SCRATCH s6, s5, 3, 9f
    ld      s9, 0(s6)
    LDQ     s10, s5, BeaconState_validators + 8
    mv      a0, s2                          # [IGNORE] the block voted for has been seen; [REJECT] it passed validation
    mv      a1, s1
    addi    a2, s3, Attestation_data + AttestationData_beacon_block_root
    call    lantern_block_lookup
    beqz    a1, 4f
    li      t0, 2
    bne     a1, t0, 5f
    sd      a0, (L + 16)(sp)
    sd      s9, 0(s6)                       # [REJECT] the committee index is in range
    mv      a0, s5
    addi    a1, s3, Attestation_data + AttestationData_target + Checkpoint_epoch
    mv      a3, s6
    addi    a4, sp, L
    ld      a2, (Store_config + CONFIG_COMMITTEE_CACHE)(s2)
    call    lantern_get_committee_count_per_slot
    CHECK_STATUS s7, 7f, 8f
    ld      t0, L(sp)
    ld      t1, (Attestation_data + AttestationData_index)(s3)
    bgeu    t1, t0, 5f
    ld      t2, (Attestation_data + AttestationData_slot)(s3)    # [REJECT] the subnet: compute_subnet_for_attestation
    andi    t2, t2, SLOTS_PER_EPOCH - 1
    mul     t2, t2, t0
    add     t2, t2, t1
    andi    t2, t2, ATTESTATION_SUBNET_COUNT - 1
    bne     t2, s8, 5f
.if FORK >= FORK_DENEB
    mv      a0, s2                          # [IGNORE] not from a future slot
    ld      a1, (Attestation_data + AttestationData_slot)(s3)
    mv      a2, s4
    call    lantern_is_future_slot
    bnez    a0, 4f
    mv      a0, s2                          # [IGNORE] the current or previous epoch
    ld      a1, (Attestation_data + AttestationData_slot)(s3)
    srli    a1, a1, LOG2_SLOTS_PER_EPOCH
    mv      a2, s4
    call    lantern_is_current_or_previous_epoch
    beqz    a0, 4f
.else
    mv      a0, s2                          # [IGNORE] the slot is within ATTESTATION_PROPAGATION_SLOT_RANGE
    ld      a1, (Attestation_data + AttestationData_slot)(s3)
    LDQ     a2, s2, Store_config + CONFIG_ATTESTATION_PROPAGATION_SLOT_RANGE
    mv      a3, s4
    call    lantern_is_within_slot_range
    beqz    a0, 4f
.endif
    ld      t0, (Attestation_data + AttestationData_slot)(s3)    # [REJECT] the epoch matches the target
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    ld      t1, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s3)
    bne     t0, t1, 5f
    PART    a0, t0, s3, Attestation_aggregation_bits    # [REJECT] unaggregated: exactly one bit set
    sd      t0, (L + 32)(sp)
    addi    a1, sp, L + 32
    addi    a2, sp, L + 24
    call    lantern_get_set_bit_count
    ld      t0, (L + 24)(sp)
    li      t1, 1
    bne     t0, t1, 5f
    SCRATCH_LIST t0, s6, s9, 0, s10         # committee = get_beacon_committee(state, data.slot, committee_index)
    sd      t0, (L + 8)(sp)
    SCRATCH_GIVE s6, s9, 1, s10
    mv      a0, s5
    addi    a1, s3, Attestation_data + AttestationData_slot
    addi    a2, s3, Attestation_data + AttestationData_index
    mv      a4, s6
    ld      a5, (L + 8)(sp)
    ld      a3, (Store_config + CONFIG_COMMITTEE_CACHE)(s2)
    call    lantern_get_beacon_committee
    CHECK_STATUS s7, 7f, 8f
    ld      t0, (L + 8)(sp)                 # [REJECT] len(aggregation_bits) == len(committee)
    ld      t1, LIST_COUNT(t0)
    ld      t2, (L + 32)(sp)
    bne     t1, t2, 5f
    PART    t1, t2, s3, Attestation_aggregation_bits    # participant_index: the committee member of the set bit
    li      t3, 0
1:  srli    t4, t3, 3
    add     t4, t1, t4
    lbu     t4, 0(t4)
    andi    t5, t3, 7
    srl     t4, t4, t5
    andi    t4, t4, 1
    bnez    t4, 2f
    addi    t3, t3, 1
    j       1b
2:  slli    t3, t3, 3
    add     t3, t0, t3
    ld      t3, LIST_FIXED(t3)
    sd      t3, (L + 24)(sp)
    mv      a0, s1                          # [IGNORE] no attestation seen for (target epoch, participant)
    li      a1, SEEN_ATTESTATION
    ld      a2, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s3)
    mv      a3, t3
    li      a4, 0
    call    lantern_seen_find_key
    bnez    a0, 4f
    ld      t2, (L + 24)(sp)                # [REJECT] the signature: is_valid_indexed_attestation of the one attester
    VALIDATOR_AT t0, s5, t2, 5f
    SCRATCH_GIVE s6, s9, 1, s10
    mv      a0, s5
    li      a1, DOMAIN_BEACON_ATTESTER
    ld      a2, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s3)
    ADDRESS a3, lantern_type_AttestationData
    addi    a4, s3, Attestation_data
    addi    a5, t0, Validator_pubkey
    addi    a6, s3, Attestation_signature
    mv      a7, s6
    call    lantern_verify_signed
    bnez    a0, 7f
    beqz    a1, 5f
    mv      a0, s2                          # [REJECT] the target block is an ancestor of the LMD vote block
    ld      a1, (L + 16)(sp)
    ld      a2, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s3)
    addi    a3, s3, Attestation_data + AttestationData_target + Checkpoint_root
    call    lantern_checkpoint_is
    CHECK_STATUS s7, 7f, 8f
    beqz    a1, 5f
    mv      a0, s2                          # [IGNORE] the finalized checkpoint is an ancestor of the block
    ld      a1, (L + 16)(sp)
    call    lantern_finalized_is_ancestor
    CHECK_STATUS s7, 7f, 8f
    beqz    a1, 4f
    mv      a0, s1                          # seen.attestation_validator_epochs.add(...)
    call    lantern_seen_key_room
    beqz    a0, 9f
    mv      a0, s1
    li      a1, SEEN_ATTESTATION
    ld      a2, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s3)
    ld      a3, (L + 24)(sp)
    li      a4, 0
    call    lantern_seen_add_key
    j       8f
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s7)
8:  li      a0, LANTERN_OK
7:  sd      s9, 0(s6)
    LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END validate_beacon_attestation_gossip
.endif

/*
 * s1 seen, s2 store, s3 signed aggregate and proof, s4 current_time_ms, s5 head state, s6 scratch,
 * s7 result, s8 aggregate, s9 scratch size, s10 validator count.
 * Locals: L committee index, L+8 committee count, L+16 data root (32), L+48 block node, L+56 committee list,
 * L+64 attesting list, L+72 indexed attestation, L+80 front size, L+88 valid, L+96 digest (32),
 * L+128 aggregate and proof, L+136 target epoch.
 */
SPEC_FUNCTION validate_beacon_aggregate_and_proof_gossip
    ENTER 144
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(a3)
    mv      s5, a4
    mv      s6, a5
    mv      s7, a6
    sd      zero, 0(s7)
    NEED_SCRATCH_B s6, s5, 10, IndexedAttestation__fixed + 8, 9f
    ld      s9, 0(s6)
    LDQ     s10, s5, BeaconState_validators + 8
    slli    t1, s10, 3                      # own scratch at the end: committee, attesting indices, indexed attestation
    addi    t1, t1, LIST_FIXED              # L(n)
    sub     t2, s9, t1
    add     t0, s6, t2
    sd      t1, 0(t0)
    sd      t0, (L + 56)(sp)
    sub     t2, t2, t1
    add     t0, s6, t2
    sd      t1, 0(t0)
    sd      t0, (L + 64)(sp)
    li      t3, IndexedAttestation__fixed + 8
    add     t3, t3, t1
    sub     t2, t2, t3
    add     t0, s6, t2
    sd      t3, 0(t0)
    sd      t0, (L + 72)(sp)
    sd      t2, (L + 80)(sp)
    sd      t2, 0(s6)
    PART    t0, t1, s3, SignedAggregateAndProof_message
    sd      t0, (L + 128)(sp)
    PART    s8, t1, t0, AggregateAndProof_aggregate
    ld      t0, (Attestation_data + AttestationData_target + Checkpoint_epoch)(s8)
    sd      t0, (L + 136)(sp)
.if FORK >= FORK_ELECTRA
    ld      t0, (Attestation_data + AttestationData_index)(s8)     # [REJECT] data.index is zero
    bnez    t0, 5f
    li      t0, 0                           # [REJECT] exactly one committee in committee_bits
    li      t1, 0
    addi    t4, s8, Attestation_committee_bits
1:  li      t2, MAX_COMMITTEES_PER_SLOT
    bgeu    t0, t2, 2f
    srli    t2, t0, 3
    add     t2, t4, t2
    lbu     t2, 0(t2)
    andi    t3, t0, 7
    srl     t2, t2, t3
    andi    t2, t2, 1
    beqz    t2, 11f
    sd      t0, L(sp)
    addi    t1, t1, 1
11: addi    t0, t0, 1
    j       1b
2:  li      t2, 1
    bne     t1, t2, 5f
.else
    ld      t0, (Attestation_data + AttestationData_index)(s8)     # index = aggregate.data.index
    sd      t0, L(sp)
.endif
    ADDRESS a0, lantern_type_AttestationData    # [IGNORE] no seen aggregate with a superset of the bits
    addi    a1, s8, Attestation_data
    mv      a2, s6
    addi    a3, sp, L + 16
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    ld      t0, (L + 80)(sp)
    sd      t0, 0(s6)
    PART    a5, a6, s8, Attestation_aggregation_bits
    mv      a0, s1
    li      a1, SEEN_AGGREGATE
    addi    a2, sp, L + 16
.if FORK >= FORK_ELECTRA
    ld      a3, L(sp)                       # the key: (data root, committee index)
.else
    li      a3, 0                           # the key: the data root
.endif
    ld      a4, (L + 136)(sp)               # b: the target epoch, for lantern_seen_prune
    call    lantern_seen_superset
    bnez    a0, 4f
    mv      a0, s1                          # [IGNORE] the first valid aggregate for (target epoch, aggregator)
    li      a1, SEEN_AGGREGATOR_EPOCH
    ld      a2, (L + 136)(sp)
    ld      a3, (L + 128)(sp)
    ld      a3, AggregateAndProof_aggregator_index(a3)
    li      a4, 0
    call    lantern_seen_find_key
    bnez    a0, 4f
    mv      a0, s2                          # [IGNORE] the block voted for has been seen; [REJECT] it passed validation
    mv      a1, s1
    addi    a2, s8, Attestation_data + AttestationData_beacon_block_root
    call    lantern_block_lookup
    beqz    a1, 4f
    li      t0, 2
    bne     a1, t0, 5f
    sd      a0, (L + 48)(sp)
    mv      a0, s5                          # [REJECT] the committee index is in range
    addi    a1, sp, L + 136
    mv      a3, s6
    addi    a4, sp, L + 8
    ld      a2, (Store_config + CONFIG_COMMITTEE_CACHE)(s2)
    call    lantern_get_committee_count_per_slot
    CHECK_STATUS s7, 7f, 8f
    ld      t0, L(sp)
    ld      t1, (L + 8)(sp)
    bgeu    t0, t1, 5f
.if FORK >= FORK_DENEB
    mv      a0, s2                          # [IGNORE] not from a future slot
    ld      a1, (Attestation_data + AttestationData_slot)(s8)
    mv      a2, s4
    call    lantern_is_future_slot
    bnez    a0, 4f
    mv      a0, s2                          # [IGNORE] the current or previous epoch
    ld      a1, (Attestation_data + AttestationData_slot)(s8)
    srli    a1, a1, LOG2_SLOTS_PER_EPOCH
    mv      a2, s4
    call    lantern_is_current_or_previous_epoch
    beqz    a0, 4f
.else
    mv      a0, s2                          # [IGNORE] the slot is within ATTESTATION_PROPAGATION_SLOT_RANGE
    ld      a1, (Attestation_data + AttestationData_slot)(s8)
    LDQ     a2, s2, Store_config + CONFIG_ATTESTATION_PROPAGATION_SLOT_RANGE
    mv      a3, s4
    call    lantern_is_within_slot_range
    beqz    a0, 4f
.endif
    ld      t0, (Attestation_data + AttestationData_slot)(s8)  # [REJECT] the epoch matches the target
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    ld      t1, (L + 136)(sp)
    bne     t0, t1, 5f
    ld      t0, (L + 80)(sp)                # committee = get_beacon_committee(state, data.slot, index)
    sd      t0, 0(s6)
    mv      a0, s5
    addi    a1, s8, Attestation_data + AttestationData_slot
    addi    a2, sp, L
    mv      a4, s6
    ld      a5, (L + 56)(sp)
    ld      a3, (Store_config + CONFIG_COMMITTEE_CACHE)(s2)
    call    lantern_get_beacon_committee
    CHECK_STATUS s7, 7f, 8f
    ld      t0, (L + 56)(sp)                # [REJECT] len(aggregation_bits) == len(committee)
    ld      t0, LIST_COUNT(t0)
    ld      t1, (Attestation_aggregation_bits + 8)(s8)
    bne     t0, t1, 5f
    ld      t0, (L + 80)(sp)                # [REJECT] the aggregate has participants: get_attesting_indices
    sd      t0, 0(s6)
    mv      a0, s5
    mv      a1, s8
    mv      a3, s6
    ld      a4, (L + 64)(sp)
    ld      a2, (Store_config + CONFIG_COMMITTEE_CACHE)(s2)
    call    lantern_get_attesting_indices
    CHECK_STATUS s7, 7f, 8f
    ld      t0, (L + 64)(sp)
    ld      t0, LIST_COUNT(t0)
    beqz    t0, 5f
    ld      a0, (L + 128)(sp)               # [REJECT] is_aggregator(state, slot, index, selection_proof)
    addi    a0, a0, AggregateAndProof_selection_proof
    li      a1, 96
    addi    a2, sp, L + 96
    call    lantern_sha256_short
    ld      t0, (L + 56)(sp)
    ld      t0, LIST_COUNT(t0)
    srli    t0, t0, 4                       # len(committee) // TARGET_AGGREGATORS_PER_COMMITTEE, at least 1
    bnez    t0, 21f
    li      t0, 1
21: ld      t1, (L + 96)(sp)
    remu    t1, t1, t0
    bnez    t1, 5f
    ld      t0, (L + 56)(sp)                # [REJECT] the aggregator is in the committee
    ld      t1, LIST_COUNT(t0)
    addi    t0, t0, LIST_FIXED
    ld      t2, (L + 128)(sp)
    ld      t2, AggregateAndProof_aggregator_index(t2)
22: beqz    t1, 5f
    ld      t3, 0(t0)
    addi    t0, t0, 8
    beq     t3, t2, 23f
    addi    t1, t1, -1
    j       22b
23: ld      t0, (L + 80)(sp)                # [REJECT] the selection proof signature
    sd      t0, 0(s6)
    VALIDATOR_AT t0, s5, t2, 5f
    sd      t0, (L + 88)(sp)
    mv      a0, s5
    li      a1, DOMAIN_SELECTION_PROOF
    ld      a2, (L + 136)(sp)
    ADDRESS a3, lantern_type_Uint64
    addi    a4, s8, Attestation_data + AttestationData_slot
    addi    a5, t0, Validator_pubkey
    ld      a6, (L + 128)(sp)
    addi    a6, a6, AggregateAndProof_selection_proof
    mv      a7, s6
    call    lantern_verify_signed
    bnez    a0, 7f
    beqz    a1, 5f
    ld      t0, (L + 80)(sp)                # [REJECT] the aggregator signature
    sd      t0, 0(s6)
    mv      a0, s5
    li      a1, DOMAIN_AGGREGATE_AND_PROOF
    ld      a2, (L + 136)(sp)
    ADDRESS a3, lantern_type_AggregateAndProof
    ld      a4, (L + 128)(sp)
    ld      a5, (L + 88)(sp)
    addi    a5, a5, Validator_pubkey
    addi    a6, s3, SignedAggregateAndProof_signature
    mv      a7, s6
    call    lantern_verify_signed
    bnez    a0, 7f
    beqz    a1, 5f
    ld      t0, (L + 80)(sp)                # [REJECT] the aggregate signature: is_valid_indexed_attestation(get_indexed_attestation)
    sd      t0, 0(s6)
    mv      a0, s5
    mv      a1, s8
    mv      a3, s6
    ld      a4, (L + 72)(sp)
    ld      a2, (Store_config + CONFIG_COMMITTEE_CACHE)(s2)
    call    lantern_get_indexed_attestation
    CHECK_STATUS s7, 7f, 8f
    ld      t0, (L + 80)(sp)
    sd      t0, 0(s6)
    mv      a0, s5
    ld      a1, (L + 72)(sp)
    mv      a3, s6
    addi    a4, sp, L + 88
    ld      a2, (Store_config + CONFIG_PUBKEY_CACHE)(s2)
    mv      a5, s8                          # with the aggregate and its CommitteeCache: key sums
    ld      a6, (Store_config + CONFIG_COMMITTEE_CACHE)(s2)
    call    lantern_indexed_attestation_valid
    CHECK_STATUS s7, 7f, 8f
    ld      t0, (L + 88)(sp)
    beqz    t0, 5f
    mv      a0, s2                          # [REJECT] the target block is an ancestor of the LMD vote block
    ld      a1, (L + 48)(sp)
    ld      a2, (L + 136)(sp)
    addi    a3, s8, Attestation_data + AttestationData_target + Checkpoint_root
    call    lantern_checkpoint_is
    CHECK_STATUS s7, 7f, 8f
    beqz    a1, 5f
    mv      a0, s2                          # [IGNORE] the finalized checkpoint is an ancestor of the block
    ld      a1, (L + 48)(sp)
    call    lantern_finalized_is_ancestor
    CHECK_STATUS s7, 7f, 8f
    beqz    a1, 4f
    mv      a0, s1                          # seen: the aggregator epoch and the bits of the data root
    call    lantern_seen_key_room
    beqz    a0, 9f
    mv      a0, s1
    call    lantern_seen_bits_room
    beqz    a0, 9f
    mv      a0, s1
    li      a1, SEEN_AGGREGATOR_EPOCH
    ld      a2, (L + 136)(sp)
    ld      a3, (L + 128)(sp)
    ld      a3, AggregateAndProof_aggregator_index(a3)
    li      a4, 0
    call    lantern_seen_add_key
    PART    a5, a6, s8, Attestation_aggregation_bits
    mv      a0, s1
    li      a1, SEEN_AGGREGATE
    addi    a2, sp, L + 16
.if FORK >= FORK_ELECTRA
    ld      a3, L(sp)                       # the key: (data root, committee index)
.else
    li      a3, 0                           # the key: the data root
.endif
    ld      a4, (L + 136)(sp)               # b: the target epoch, for lantern_seen_prune
    call    lantern_seen_add_bits
    j       8f
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s7)
8:  li      a0, LANTERN_OK
7:  LEAVE 144
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 144
SPEC_END validate_beacon_aggregate_and_proof_gossip

/* ---------------------------------------------------------------- Gossip: sync committee */

.if FORK >= FORK_ALTAIR
.set SYNC_SUBCOMMITTEE_SIZE, SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT
.set SYNC_SUB_KEYS, 24 + 48 * SYNC_SUBCOMMITTEE_SIZE    /* a BlsPublicKeyList of one subcommittee */
.if (SYNC_SUBCOMMITTEE_SIZE / TARGET_AGGREGATORS_PER_SYNC_SUBCOMMITTEE) > 1
.set SYNC_AGGREGATOR_MODULO, SYNC_SUBCOMMITTEE_SIZE / TARGET_AGGREGATORS_PER_SYNC_SUBCOMMITTEE
.else
.set SYNC_AGGREGATOR_MODULO, 1
.endif

/*
 * dst = the sync committee of state st for its next slot: current_sync_committee when the period of the
 * current epoch is that of the next slot's epoch, else next_sync_committee. Uses t0-t3, a7.
 */
.macro SYNC_COMMITTEE_OF dst, st
    LDQ     t0, \st, BeaconState_slot
    srli    t1, t0, LOG2_SLOTS_PER_EPOCH
    addi    t2, t0, 1
    srli    t2, t2, LOG2_SLOTS_PER_EPOCH
    li      t3, EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    divu    t1, t1, t3
    divu    t2, t2, t3
    li      t3, BeaconState_current_sync_committee
    beq     t1, t2, 98f
    li      t3, BeaconState_next_sync_committee
98: add     \dst, \st, t3
.endm

/*
 * s1 seen, s2 store, s3 message, s4 current_time_ms, s5 head state, s6 scratch, s7 result,
 * s8 subnet_id, s9 validator, s10 i.
 */
SPEC_FUNCTION validate_sync_committee_message_gossip
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(a3)
    ld      s8, 0(a4)
    mv      s5, a5
    mv      s6, a6
    mv      s7, a7
    sd      zero, 0(s7)
    NEED_SCRATCH s6, s5, 0, 9f
    mv      a0, s1                          # [IGNORE] the first valid message for (slot, validator, subnet)
    li      a1, SEEN_SYNC_MESSAGE
    ld      a2, SyncCommitteeMessage_slot(s3)
    ld      a3, SyncCommitteeMessage_validator_index(s3)
    mv      a4, s8
    call    lantern_seen_find_key
    bnez    a0, 4f
    mv      a0, s2                          # [IGNORE] is_current_slot
    ld      a1, SyncCommitteeMessage_slot(s3)
    li      a2, 0
    mv      a3, s4
    call    lantern_is_within_slot_range
    beqz    a0, 4f
    ld      t4, SyncCommitteeMessage_validator_index(s3)   # [REJECT] the validator index is valid
    VALIDATOR_AT s9, s5, t4, 5f
    SYNC_COMMITTEE_OF t5, s5                # [REJECT] subnet_id in compute_subnets_for_sync_committee
    addi    t5, t5, SyncCommittee_pubkeys
    addi    t6, s9, Validator_pubkey
    li      s10, 0
1:  li      t0, SYNC_COMMITTEE_SIZE
    bgeu    s10, t0, 5f
    li      t0, 48
    mul     t0, s10, t0
    add     t0, t5, t0
    NE48W   t0, t6, 3f
    li      t0, SYNC_SUBCOMMITTEE_SIZE
    divu    t0, s10, t0
    beq     t0, s8, 31f
3:  addi    s10, s10, 1
    j       1b
31: mv      a0, s5                          # [REJECT] the signature
    li      a1, DOMAIN_SYNC_COMMITTEE
    ld      a2, SyncCommitteeMessage_slot(s3)
    srli    a2, a2, LOG2_SLOTS_PER_EPOCH
    ADDRESS a3, lantern_type_Bytes32
    addi    a4, s3, SyncCommitteeMessage_beacon_block_root
    addi    a5, s9, Validator_pubkey
    addi    a6, s3, SyncCommitteeMessage_signature
    mv      a7, s6
    call    lantern_verify_signed
    bnez    a0, 7f
    beqz    a1, 5f
    mv      a0, s1                          # seen.sync_message_validator_slots.add(...)
    call    lantern_seen_key_room
    beqz    a0, 9f
    mv      a0, s1
    li      a1, SEEN_SYNC_MESSAGE
    ld      a2, SyncCommitteeMessage_slot(s3)
    ld      a3, SyncCommitteeMessage_validator_index(s3)
    mv      a4, s8
    call    lantern_seen_add_key
    j       8f
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s7)
8:  li      a0, LANTERN_OK
7:  LEAVE 0
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END validate_sync_committee_message_gossip

/*
 * s1 seen, s2 store, s3 signed contribution and proof, s4 current_time_ms, s5 head state, s6 scratch,
 * s7 result, s8 contribution, s9 aggregator validator, s10 subcommittee pubkeys.
 * Locals: L selection data (16), L+16 digest (32), L+48 key list, L+56 front size, L+64 domain type,
 * L+72 epoch, L+80 domain (32), L+112 the signing root buffer (56), L+168 valid.
 */
SPEC_FUNCTION validate_sync_committee_contribution_and_proof_gossip
    ENTER 176
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(a3)
    mv      s5, a4
    mv      s6, a5
    mv      s7, a6
    sd      zero, 0(s7)
    NEED_SCRATCH_B s6, s5, 1, SYNC_SUB_KEYS, 9f
    ld      t0, 0(s6)                       # own scratch at the end: the participant keys
    li      t1, SYNC_SUB_KEYS
    sub     t2, t0, t1
    add     t3, s6, t2
    sd      t1, 0(t3)
    li      t1, 24
    sd      t1, 8(t3)
    sd      zero, 16(t3)
    sd      t3, (L + 48)(sp)
    sd      t2, (L + 56)(sp)
    sd      t2, 0(s6)
    addi    s8, s3, SignedContributionAndProof_message + ContributionAndProof_contribution
    mv      a0, s1                          # [IGNORE] no seen contribution with a superset of the bits
    li      a1, SEEN_CONTRIBUTION
    addi    a2, s8, SyncCommitteeContribution_beacon_block_root
    ld      a3, SyncCommitteeContribution_slot(s8)
    ld      a4, SyncCommitteeContribution_subcommittee_index(s8)
    addi    a5, s8, SyncCommitteeContribution_aggregation_bits
    li      a6, SYNC_SUBCOMMITTEE_SIZE
    call    lantern_seen_superset
    bnez    a0, 4f
    mv      a0, s1                          # [IGNORE] the first valid contribution of (slot, aggregator, subcommittee)
    li      a1, SEEN_SYNC_CONTRIBUTION
    ld      a2, SyncCommitteeContribution_slot(s8)
    ld      a3, (SignedContributionAndProof_message + ContributionAndProof_aggregator_index)(s3)
    ld      a4, SyncCommitteeContribution_subcommittee_index(s8)
    call    lantern_seen_find_key
    bnez    a0, 4f
    mv      a0, s2                          # [IGNORE] is_current_slot
    ld      a1, SyncCommitteeContribution_slot(s8)
    li      a2, 0
    mv      a3, s4
    call    lantern_is_within_slot_range
    beqz    a0, 4f
    ld      t0, SyncCommitteeContribution_subcommittee_index(s8)   # [REJECT] the subcommittee index is in range
    li      t1, SYNC_COMMITTEE_SUBNET_COUNT
    bgeu    t0, t1, 5f
    li      t0, 0                           # [REJECT] the contribution has participants
    li      t1, 0
1:  li      t2, SYNC_SUBCOMMITTEE_SIZE / 8
    bgeu    t0, t2, 2f
    add     t2, s8, t0
    lbu     t2, SyncCommitteeContribution_aggregation_bits(t2)
    or      t1, t1, t2
    addi    t0, t0, 1
    j       1b
2:  beqz    t1, 5f
    addi    a0, s3, SignedContributionAndProof_message + ContributionAndProof_selection_proof
    li      a1, 96                          # [REJECT] is_sync_committee_aggregator(selection_proof)
    addi    a2, sp, L + 16
    call    lantern_sha256_short
    ld      t0, (L + 16)(sp)
    li      t1, SYNC_AGGREGATOR_MODULO
    remu    t0, t0, t1
    bnez    t0, 5f
    ld      t4, (SignedContributionAndProof_message + ContributionAndProof_aggregator_index)(s3)
    VALIDATOR_AT s9, s5, t4, 5f             # [REJECT] the aggregator index is valid
    SYNC_COMMITTEE_OF s10, s5               # [REJECT] the aggregator is in get_sync_subcommittee_pubkeys
    ld      t0, SyncCommitteeContribution_subcommittee_index(s8)
    li      t1, 48 * SYNC_SUBCOMMITTEE_SIZE
    mul     t0, t0, t1
    add     s10, s10, t0
    addi    s10, s10, SyncCommittee_pubkeys
    addi    t6, s9, Validator_pubkey
    li      t5, 0
3:  li      t0, SYNC_SUBCOMMITTEE_SIZE
    bgeu    t5, t0, 5f
    li      t0, 48
    mul     t0, t5, t0
    add     t0, s10, t0
    NE48W   t0, t6, 32f
    j       31f
32: addi    t5, t5, 1
    j       3b
31: ld      t0, SyncCommitteeContribution_slot(s8)  # [REJECT] the selection proof signs SyncAggregatorSelectionData
    ld      t1, SyncCommitteeContribution_subcommittee_index(s8)
    sd      t0, L(sp)
    sd      t1, (L + 8)(sp)
    mv      a0, s5
    li      a1, DOMAIN_SYNC_COMMITTEE_SELECTION_PROOF
    srli    a2, t0, LOG2_SLOTS_PER_EPOCH
    ADDRESS a3, lantern_type_SyncAggregatorSelectionData
    addi    a4, sp, L
    addi    a5, s9, Validator_pubkey
    addi    a6, s3, SignedContributionAndProof_message + ContributionAndProof_selection_proof
    mv      a7, s6
    call    lantern_verify_signed
    bnez    a0, 7f
    beqz    a1, 5f
    ld      t0, (L + 56)(sp)                # [REJECT] the aggregator signature
    sd      t0, 0(s6)
    mv      a0, s5
    li      a1, DOMAIN_CONTRIBUTION_AND_PROOF
    ld      a2, SyncCommitteeContribution_slot(s8)
    srli    a2, a2, LOG2_SLOTS_PER_EPOCH
    ADDRESS a3, lantern_type_ContributionAndProof
    addi    a4, s3, SignedContributionAndProof_message
    addi    a5, s9, Validator_pubkey
    addi    a6, s3, SignedContributionAndProof_signature
    mv      a7, s6
    call    lantern_verify_signed
    bnez    a0, 7f
    beqz    a1, 5f
    li      s4, 0                           # participant_pubkeys: the keys of the set bits
45: li      t0, SYNC_SUBCOMMITTEE_SIZE
    bgeu    s4, t0, 42f
    srli    t0, s4, 3
    add     t0, s8, t0
    lbu     t0, SyncCommitteeContribution_aggregation_bits(t0)
    andi    t1, s4, 7
    srl     t0, t0, t1
    andi    t0, t0, 1
    beqz    t0, 41f
    li      t0, 48
    mul     t0, s4, t0
    add     t0, s10, t0
    ld      t2, (L + 48)(sp)
    KEYS_APPEND t2, t0
41: addi    s4, s4, 1
    j       45b
42: li      t0, DOMAIN_SYNC_COMMITTEE       # [REJECT] eth_fast_aggregate_verify over the beacon_block_root
    sw      t0, (L + 64)(sp)
    ld      t0, SyncCommitteeContribution_slot(s8)
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    sd      t0, (L + 72)(sp)
    ld      t0, (L + 56)(sp)
    sd      t0, 0(s6)
    mv      a0, s5
    addi    a1, sp, L + 64
    addi    a2, sp, L + 72
    mv      a3, s6
    addi    a4, sp, L + 80
    call    lantern_get_domain
    bnez    a0, 7f
    ld      t0, (L + 56)(sp)
    sd      t0, 0(s6)
    ADDRESS a0, lantern_type_Bytes32
    addi    a1, s8, SyncCommitteeContribution_beacon_block_root
    addi    a2, sp, L + 80
    mv      a3, s6
    addi    a4, sp, L + 112 + 24
    call    lantern_compute_signing_root
    bnez    a0, 7f
    li      t0, 56
    sd      t0, (L + 112)(sp)
    li      t0, 24
    sd      t0, (L + 120)(sp)
    li      t0, 32
    sd      t0, (L + 128)(sp)
    ld      t0, (L + 56)(sp)
    sd      t0, 0(s6)
    ld      a0, (L + 48)(sp)
    addi    a1, sp, L + 112
    addi    a2, s8, SyncCommitteeContribution_signature
    mv      a3, s6
    addi    a4, sp, L + 168
    CALL_GLOBAL crypto_bls_eth_fast_aggregate_verify
    bnez    a0, 7f
    ld      t0, (L + 168)(sp)
    beqz    t0, 5f
    mv      a0, s1                          # seen: the aggregator slot and the bits of the contribution
    call    lantern_seen_key_room
    beqz    a0, 9f
    mv      a0, s1
    call    lantern_seen_bits_room
    beqz    a0, 9f
    mv      a0, s1
    li      a1, SEEN_SYNC_CONTRIBUTION
    ld      a2, SyncCommitteeContribution_slot(s8)
    ld      a3, (SignedContributionAndProof_message + ContributionAndProof_aggregator_index)(s3)
    ld      a4, SyncCommitteeContribution_subcommittee_index(s8)
    call    lantern_seen_add_key
    mv      a0, s1
    li      a1, SEEN_CONTRIBUTION
    addi    a2, s8, SyncCommitteeContribution_beacon_block_root
    ld      a3, SyncCommitteeContribution_slot(s8)
    ld      a4, SyncCommitteeContribution_subcommittee_index(s8)
    addi    a5, s8, SyncCommitteeContribution_aggregation_bits
    li      a6, SYNC_SUBCOMMITTEE_SIZE
    call    lantern_seen_add_bits
    j       8f
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s7)
8:  li      a0, LANTERN_OK
7:  LEAVE 176
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 176
SPEC_END validate_sync_committee_contribution_and_proof_gossip
.endif

/*
 * (state a0, validator_index a1, out a2) -> a0: compute_subnets_for_sync_committee of the state
 * for the validator (altair validator.md), bit i of the u64 out for subnet i; 0 for an index past
 * the validators, and before altair.
 */
SPEC_LEAF node_sync_subnets
    sd      zero, 0(a2)
.if FORK >= FORK_ALTAIR
    SYNC_COMMITTEE_OF t5, a0
    addi    t5, t5, SyncCommittee_pubkeys
    VALIDATOR_AT t6, a0, a1, 9f
    addi    t6, t6, Validator_pubkey
    li      a3, 0
    li      a4, 0
1:  li      t0, SYNC_COMMITTEE_SIZE
    bgeu    a4, t0, 8f
    li      t0, 48
    mul     t0, a4, t0
    add     t0, t5, t0
    NE48W   t0, t6, 3f
    li      t0, SYNC_SUBCOMMITTEE_SIZE
    divu    t0, a4, t0
    li      t1, 1
    sll     t1, t1, t0
    or      a3, a3, t1
3:  addi    a4, a4, 1
    j       1b
8:  sd      a3, 0(a2)
.endif
9:  li      a0, LANTERN_OK
    ret
SPEC_END node_sync_subnets

/*
 * (state a0, validator_index a1, out a2) -> a0: the places of the validator's public key in the
 * sync committee that compute_subnets_for_sync_committee reads (altair validator.md): bit p of
 * the SYNC_COMMITTEE_SIZE / 8 bytes at out for place p; none for an index past the validators,
 * and before altair.
 */
SPEC_LEAF node_sync_positions
    li      t0, 0
1:  li      t1, SYNC_COMMITTEE_SIZE / 8
    bgeu    t0, t1, 2f
    add     t1, a2, t0
    sb      zero, 0(t1)
    addi    t0, t0, 1
    j       1b
2:
.if FORK >= FORK_ALTAIR
    SYNC_COMMITTEE_OF t5, a0
    addi    t5, t5, SyncCommittee_pubkeys
    VALIDATOR_AT t6, a0, a1, 9f
    addi    t6, t6, Validator_pubkey
    li      a4, 0
3:  li      t0, SYNC_COMMITTEE_SIZE
    bgeu    a4, t0, 9f
    li      t0, 48
    mul     t0, a4, t0
    add     t0, t5, t0
    NE48W   t0, t6, 4f
    srli    t0, a4, 3
    add     t0, a2, t0
    lbu     t1, 0(t0)
    andi    t2, a4, 7
    li      t3, 1
    sll     t3, t3, t2
    or      t1, t1, t3
    sb      t1, 0(t0)
4:  addi    a4, a4, 1
    j       3b
.endif
9:  li      a0, LANTERN_OK
    ret
SPEC_END node_sync_positions

/* ---------------------------------------------------------------- Gossip: attester slashings */

/*
 * s1 seen, s2 store, s3 attester slashing, s4 i, s5 head state, s6 scratch, s7 result,
 * s8 attestation 1, s9 attestation 2, s10 intersection list.
 * Locals: L front size, L+8 list 1, L+16 list 2, L+24 new indices, L+32 current epoch, L+40 predicate.
 */
SPEC_FUNCTION validate_attester_slashing_gossip
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s5, a3
    mv      s6, a4
    mv      s7, a5
    sd      zero, 0(s7)
    PART    s8, t0, s3, AttesterSlashing_attestation_1
    PART    s9, t0, s3, AttesterSlashing_attestation_2
    ld      t0, (IndexedAttestation_attesting_indices + 8)(s8)     # own scratch at the end: two sorted copies, the intersection
    ld      t1, (IndexedAttestation_attesting_indices + 8)(s9)
    mv      t2, t0
    bltu    t0, t1, 1f
    mv      t2, t1
1:  add     t3, t0, t1
    add     t3, t3, t2
    slli    t3, t3, 3
    addi    t3, t3, 3 * LIST_FIXED          # their bytes
    LDQ     t4, s5, BeaconState_validators + 8
    slli    t4, t4, 3
    addi    t4, t4, LIST_FIXED
    li      t5, 7
    mul     t4, t4, t5
    li      t5, LANTERN_SCRATCH_FIXED
    add     t4, t4, t5                      # S(7) for is_valid_indexed_attestation
    add     t4, t4, t3
    ld      t5, 0(s6)
    bltu    t5, t4, 9f
    sub     t5, t5, t3
    sd      t5, L(sp)
    add     t6, s6, t5                      # list 1
    slli    t4, t0, 3
    addi    t4, t4, LIST_FIXED
    sd      t4, 0(t6)
    sd      t6, (L + 8)(sp)
    add     t6, t6, t4                      # list 2
    slli    t4, t1, 3
    addi    t4, t4, LIST_FIXED
    sd      t4, 0(t6)
    sd      t6, (L + 16)(sp)
    add     s10, t6, t4                     # the intersection
    slli    t4, t2, 3
    addi    t4, t4, LIST_FIXED
    sd      t4, 0(s10)
    ld      a0, (L + 8)(sp)                 # sorted copies of both attesting index lists
    PART    a1, a2, s8, IndexedAttestation_attesting_indices
    sd      a2, LIST_COUNT(a0)
    addi    a0, a0, LIST_FIXED
    slli    a2, a2, 3
    call    lantern_copy
    ld      a0, (L + 16)(sp)
    PART    a1, a2, s9, IndexedAttestation_attesting_indices
    sd      a2, LIST_COUNT(a0)
    addi    a0, a0, LIST_FIXED
    slli    a2, a2, 3
    call    lantern_copy
    ld      a0, (L + 8)(sp)
    ld      a1, LIST_COUNT(a0)
    addi    a0, a0, LIST_FIXED
    call    lantern_sort_u64
    ld      a0, (L + 16)(sp)
    ld      a1, LIST_COUNT(a0)
    addi    a0, a0, LIST_FIXED
    call    lantern_sort_u64
    ld      t0, (L + 8)(sp)                 # slashable_indices = their intersection, each index once
    ld      t1, LIST_COUNT(t0)
    addi    t0, t0, LIST_FIXED
    ld      t2, (L + 16)(sp)
    ld      t3, LIST_COUNT(t2)
    addi    t2, t2, LIST_FIXED
    addi    t4, s10, LIST_FIXED
    li      t5, 0                           # its count
11: beqz    t1, 3f
    beqz    t3, 3f
    ld      a0, 0(t0)
    ld      a1, 0(t2)
    bltu    a0, a1, 12f
    bltu    a1, a0, 13f
    beqz    t5, 14f
    addi    a2, t5, -1
    slli    a2, a2, 3
    add     a2, t4, a2
    ld      a2, 0(a2)
    beq     a2, a0, 15f
14: slli    a2, t5, 3
    add     a2, t4, a2
    sd      a0, 0(a2)
    addi    t5, t5, 1
15: addi    t0, t0, 8
    addi    t1, t1, -1
13: addi    t2, t2, 8
    addi    t3, t3, -1
    j       11b
12: addi    t0, t0, 8
    addi    t1, t1, -1
    j       11b
3:  sd      t5, LIST_COUNT(s10)
    li      s4, 0                           # [IGNORE] an index of the intersection not yet seen
    sd      zero, (L + 24)(sp)
2:  ld      t0, LIST_COUNT(s10)
    bgeu    s4, t0, 21f
    mv      a0, s1
    li      a1, SEEN_ATTESTER_SLASHING
    slli    a2, s4, 3
    add     a2, s10, a2
    ld      a2, LIST_FIXED(a2)
    li      a3, 0
    li      a4, 0
    call    lantern_seen_find_key
    ld      t0, (L + 24)(sp)
    seqz    a0, a0
    add     t0, t0, a0
    sd      t0, (L + 24)(sp)
    addi    s4, s4, 1
    j       2b
21: ld      t0, (L + 24)(sp)
    beqz    t0, 4f
    addi    a0, s8, IndexedAttestation_data     # [REJECT] the data is slashable
    addi    a1, s9, IndexedAttestation_data
    addi    a2, sp, L + 40
    call    lantern_is_slashable_attestation_data
    ld      t0, (L + 40)(sp)
    beqz    t0, 5f
    mv      s4, s8                          # [REJECT] each attestation: valid indices, is_valid_indexed_attestation
22: PART    t0, t1, s4, IndexedAttestation_attesting_indices
    LDQ     t2, s5, BeaconState_validators + 8
23: beqz    t1, 24f
    ld      t3, 0(t0)
    addi    t0, t0, 8
    bgeu    t3, t2, 5f
    addi    t1, t1, -1
    j       23b
24: ld      t0, L(sp)
    sd      t0, 0(s6)
    mv      a0, s5
    mv      a1, s4
    mv      a3, s6
    addi    a4, sp, L + 40
    ld      a2, (Store_config + CONFIG_PUBKEY_CACHE)(s2)
    call    lantern_is_valid_indexed_attestation
    CHECK_STATUS s7, 7f, 8f
    ld      t0, (L + 40)(sp)
    beqz    t0, 5f
    beq     s4, s9, 25f
    mv      s4, s9
    j       22b
25: mv      a0, s5                          # [REJECT] a validator of the intersection is slashable
    addi    a1, sp, L + 32
    call    lantern_get_current_epoch
    li      s4, 0
26: ld      t0, LIST_COUNT(s10)
    bgeu    s4, t0, 5f
    slli    t0, s4, 3
    add     t0, s10, t0
    ld      t0, LIST_FIXED(t0)
    VALIDATOR_AT a0, s5, t0, 5f
    addi    a1, sp, L + 32
    addi    a2, sp, L + 40
    call    lantern_is_slashable_validator
    ld      t0, (L + 40)(sp)
    addi    s4, s4, 1
    beqz    t0, 26b
    mv      a0, s1                          # seen.attester_slashing_indices.update(slashable_indices)
    call    lantern_seen_key_room
    ld      t0, (L + 24)(sp)
    bltu    a0, t0, 9f
    li      s4, 0
27: ld      t0, LIST_COUNT(s10)
    bgeu    s4, t0, 8f
    mv      a0, s1
    li      a1, SEEN_ATTESTER_SLASHING
    slli    a2, s4, 3
    add     a2, s10, a2
    ld      a2, LIST_FIXED(a2)
    li      a3, 0
    li      a4, 0
    call    lantern_seen_find_key
    bnez    a0, 28f
    mv      a0, s1
    li      a1, SEEN_ATTESTER_SLASHING
    slli    a2, s4, 3
    add     a2, s10, a2
    ld      a2, LIST_FIXED(a2)
    li      a3, 0
    li      a4, 0
    call    lantern_seen_add_key
28: addi    s4, s4, 1
    j       27b
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s7)
8:  li      a0, LANTERN_OK
7:  LEAVE 48
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END validate_attester_slashing_gossip

/* ---------------------------------------------------------------- Gossip: blocks and columns */

/*
 * s1 seen, s2 store, s3 signed block, s4 current_time_ms, s5 head state, s6 proposer state,
 * s7 scratch, s8 result, s9 block, s10 parent node.
 * Locals: L blob parameters (16), L+16 expected proposer, L+24 epoch, L+32 time, L+40 parent payload status,
 * L+48 a predicate, L+56 bellatrix: the justified checkpoint state.
 */
.macro BEACON_BLOCK_GOSSIP name, blinded, msg, sig, type, payload, timestamp, commitments
SPEC_FUNCTION \name
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(a3)
    mv      s5, a4
    mv      s6, a5
.if FORK == FORK_BELLATRIX
    sd      a6, (L + 56)(sp)                # bellatrix: (seen, store, block, now, head, proposer, justified state, scratch, result)
    mv      s7, a7
    ld      s8, (64 + 96)(sp)               # the ninth argument
.else
    mv      s7, a6
    mv      s8, a7
.endif
    sd      zero, 0(s8)
.if FORK >= FORK_FULU
    NEED_SCRATCH s7, s5, 0, 9f
.else
    NEED_SCRATCH s7, s6, 2, 9f              # get_beacon_proposer_index of the proposer state takes S(2)
.endif
    PART    s9, t0, s3, \msg
    mv      a0, s1                          # [IGNORE] the first block for (slot, proposer)
    li      a1, SEEN_PROPOSER_SLOT
    ld      a2, BeaconBlock_slot(s9)
    ld      a3, BeaconBlock_proposer_index(s9)
    li      a4, 0
    call    lantern_seen_find_key
    bnez    a0, 4f
    mv      a0, s2                          # [IGNORE] not from a future slot
    ld      a1, BeaconBlock_slot(s9)
    mv      a2, s4
    call    lantern_is_future_slot
    bnez    a0, 4f
    mv      a0, s2                          # [IGNORE] after the finalized slot
    call    lantern_finalized_slot
    ld      t0, BeaconBlock_slot(s9)
    bgeu    a0, t0, 4f
    mv      a0, s2                          # [IGNORE] the parent has been seen
    mv      a1, s1
    addi    a2, s9, BeaconBlock_parent_root
    call    lantern_block_lookup
    beqz    a1, 4f
    mv      s10, a0
    li      t0, 2
    beq     a1, t0, 1f
.if FORK >= FORK_CAPELLA
    li      t0, PAYLOAD_STATUS_NOT_VALIDATED    # no post-state: [REJECT] with an optimistic payload, else [IGNORE]
    beq     a2, t0, 5f
    j       4f
.elseif FORK == FORK_BELLATRIX
    sd      a2, (L + 40)(sp)
.if \blinded == 0
    ld      a0, (L + 56)(sp)                # no post-state: is_execution_enabled(justified checkpoint state, block.body)
    PART    a1, t0, s9, BeaconBlock_body
    addi    a2, sp, L + 48
    call    lantern_is_execution_enabled
    ld      t0, (L + 48)(sp)
    beqz    t0, 5f                          # [REJECT] the parent failed validation, execution not enabled
.endif
    ld      a2, (L + 40)(sp)
    li      t0, PAYLOAD_STATUS_NOT_VALIDATED    # [REJECT] with an optimistic payload, else [IGNORE]
    beq     a2, t0, 5f
    j       4f
.else
    j       5f                              # [REJECT] the parent failed validation
.endif
1:
.if FORK >= FORK_CAPELLA
    li      t0, PAYLOAD_STATUS_INVALIDATED      # [IGNORE] the parent's payload is invalid
    beq     a2, t0, 4f
.elseif FORK == FORK_BELLATRIX
    sd      a2, (L + 40)(sp)                # parent_payload_status, for the payload checks
.endif
    ld      t1, BeaconBlock_proposer_index(s9)  # [REJECT] the proposer index is valid
    VALIDATOR_AT t2, s5, t1, 5f
    mv      a0, s5                          # [REJECT] the proposer signature
    li      a1, DOMAIN_BEACON_PROPOSER
    ld      a2, BeaconBlock_slot(s9)
    srli    a2, a2, LOG2_SLOTS_PER_EPOCH
    ADDRESS a3, \type
    mv      a4, s9
    addi    a5, t2, Validator_pubkey
    addi    a6, s3, \sig
    mv      a7, s7
    call    lantern_verify_signed
    bnez    a0, 7f
    beqz    a1, 5f
.if FORK == FORK_BELLATRIX && \blinded == 0
    mv      a0, s5                          # if is_execution_enabled(state, block.body):
    PART    a1, t0, s9, BeaconBlock_body
    addi    a2, sp, L + 48
    call    lantern_is_execution_enabled
    ld      t0, (L + 48)(sp)
    beqz    t0, 2f
.endif
.if FORK >= FORK_BELLATRIX
    ADDQ    a0, s5, BeaconState_genesis_time    # [REJECT] the payload timestamp is compute_time_at_slot
    addi    a1, s9, BeaconBlock_slot
    addi    a2, s2, Store_config
    addi    a3, sp, L + 32
    call    lantern_compute_time_at_slot
    CHECK_STATUS s8, 7f, 8f
    PART    t0, t1, s9, BeaconBlock_body
    PART    t2, t1, t0, \payload
    ld      t2, \timestamp(t2)
    ld      t3, (L + 32)(sp)
    bne     t2, t3, 5f
.endif
.if FORK == FORK_BELLATRIX
    ld      a2, (L + 40)(sp)                # [IGNORE] the parent passed validation but its payload is invalid
    li      t0, PAYLOAD_STATUS_INVALIDATED
    beq     a2, t0, 4f
2:
.endif
    NODE    t0, s2, s10                     # [REJECT] a higher slot than the parent
    ld      t0, BlockNode_slot(t0)
    ld      t1, BeaconBlock_slot(s9)
    bgeu    t0, t1, 5f
    mv      a0, s2                          # [REJECT] the finalized checkpoint is an ancestor
    mv      a1, s10
    call    lantern_finalized_is_ancestor
    CHECK_STATUS s8, 7f, 8f
    beqz    a1, 5f
.if FORK >= FORK_FULU
    ld      t0, BeaconBlock_slot(s9)        # [REJECT] at most max_blobs_per_block commitments
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    sd      t0, (L + 24)(sp)
    addi    a0, sp, L + 24
    addi    a1, s2, Store_config
    addi    a2, sp, L
    call    lantern_get_blob_parameters
    ld      t2, (L + 8)(sp)
.elseif FORK == FORK_ELECTRA
    LDQ     t2, s2, Store_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA      # [REJECT] at most MAX_BLOBS_PER_BLOCK_ELECTRA commitments
.elseif FORK == FORK_DENEB
    LDQ     t2, s2, Store_config + CONFIG_MAX_BLOBS_PER_BLOCK              # [REJECT] at most MAX_BLOBS_PER_BLOCK commitments
.endif
.if FORK >= FORK_DENEB
    PART    t0, t1, s9, BeaconBlock_body
    LDQ     t1, t0, \commitments + 8
    bltu    t2, t1, 5f
.endif
    mv      a0, s6                          # [REJECT] the expected proposer of the parent state at the slot
.if FORK >= FORK_FULU
    addi    a1, sp, L + 16
.else
    mv      a1, s7
    addi    a2, sp, L + 16
.endif
    call    lantern_get_beacon_proposer_index
    CHECK_STATUS s8, 7f, 8f
    ld      t0, (L + 16)(sp)
    ld      t1, BeaconBlock_proposer_index(s9)
    bne     t0, t1, 5f
    mv      a0, s1                          # seen.proposer_slots.add(...)
    call    lantern_seen_key_room
    beqz    a0, 9f
    mv      a0, s1
    li      a1, SEEN_PROPOSER_SLOT
    ld      a2, BeaconBlock_slot(s9)
    ld      a3, BeaconBlock_proposer_index(s9)
    li      a4, 0
    call    lantern_seen_add_key
    j       8f
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s8)
8:  li      a0, LANTERN_OK
7:  LEAVE 64
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END \name
.endm

BEACON_BLOCK_GOSSIP validate_beacon_block_gossip, 0, SignedBeaconBlock_message, SignedBeaconBlock_signature, lantern_type_BeaconBlock, BeaconBlockBody_execution_payload, ExecutionPayload_timestamp, BeaconBlockBody_blob_kzg_commitments

/*
 * The same checks of a SignedBlindedBeaconBlock (networking.md, lantern_validate_blinded_block_gossip):
 * its header's timestamp, its commitments, the root of its BlindedBeaconBlock; execution is enabled.
 */
.if FORK >= FORK_BELLATRIX
.if (SignedBlindedBeaconBlock_message != SignedBeaconBlock_message) || (BlindedBeaconBlock_slot != BeaconBlock_slot) || (BlindedBeaconBlock_proposer_index != BeaconBlock_proposer_index) || (BlindedBeaconBlock_parent_root != BeaconBlock_parent_root) || (BlindedBeaconBlock_body != BeaconBlock_body)
.error "the blinded block's fields are not those of the block"
.endif
BEACON_BLOCK_GOSSIP validate_blinded_block_gossip, 1, SignedBlindedBeaconBlock_message, SignedBlindedBeaconBlock_signature, lantern_type_BlindedBeaconBlock, BlindedBeaconBlockBody_execution_payload_header, ExecutionPayloadHeader_timestamp, BlindedBeaconBlockBody_blob_kzg_commitments
.else
/* Before bellatrix: no blinded block. */
SPEC_FUNCTION validate_blinded_block_gossip
    FRAME 0
    li      a0, LANTERN_INVALID_EVENT
    UNFRAME 0
SPEC_END validate_blinded_block_gossip
.endif

/* ---------------------------------------------------------------- Columns */

.if FORK >= FORK_FULU
/*
 * get_subtree_index(get_generalized_index(BeaconBlockBody, "blob_kzg_commitments")): field 11 of the 13 fields
 * of BeaconBlockBody, whose tree has 16 leaves, so the generalized index is 16 + 11 = 27 and the subtree index 11.
 */
.set BLOB_KZG_COMMITMENTS_SUBTREE_INDEX, 11
.if KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH != 4
.error "the subtree index of blob_kzg_commitments assumes a body of 13 fields"
.endif

SPEC_LEAF compute_subnet_for_data_column_sidecar
    ld      t0, CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT(a1)
    beqz    t0, 9f
    ld      t1, 0(a0)
    remu    t1, t1, t0
    sd      t1, 0(a2)
    li      a0, LANTERN_OK
    ret
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_subnet_for_data_column_sidecar

/*
 * a0 = status, a1 = is_valid_merkle_branch(hash_tree_root of the a2 commitments at a1, the branch at a3,
 * KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH, BLOB_KZG_COMMITMENTS_SUBTREE_INDEX, the root at a4), with scratch a0.
 * The list is hashed from a standalone copy at the end of scratch.
 * s1 scratch, s2 branch, s3 root, s4 i. Locals: L value (32), L+32 the two halves (64).
 */
LOCAL_FUNCTION lantern_commitments_in_body
    ENTER 96
    mv      s1, a0
    mv      s2, a3
    mv      s3, a4
    li      t0, 48                          # the list: size, offset 24, count, the commitments
    mul     t0, a2, t0
    addi    t0, t0, LIST_FIXED + 7
    andi    t0, t0, -8
    li      t1, LANTERN_SCRATCH_FIXED
    add     t1, t1, t0
    ld      t2, 0(s1)
    bltu    t2, t1, 9f
    sub     t2, t2, t0
    add     t3, s1, t2
    sd      t2, 0(s1)                       # asm-ssz's scratch: the front
    sd      t0, 0(t3)
    li      t1, LIST_FIXED
    sd      t1, 8(t3)
    sd      a2, 16(t3)
    addi    a0, t3, LIST_FIXED
    sd      t3, (L + 32)(sp)
    li      t0, 48
    mul     a2, a2, t0
    call    lantern_copy
    ADDRESS a0, lantern_type_BlobKZGCommitments     # value = hash_tree_root(kzg_commitments)
    ld      a1, (L + 32)(sp)
    mv      a2, s1
    addi    a3, sp, L
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    li      s4, 0
1:  li      t0, KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH
    bgeu    s4, t0, 3f
    slli    t0, s4, 5                       # branch[i]
    add     t0, s2, t0
    li      t1, BLOB_KZG_COMMITMENTS_SUBTREE_INDEX
    srl     t1, t1, s4
    andi    t1, t1, 1
    addi    t2, sp, L + 32
    addi    t3, sp, L
    beqz    t1, 2f
    COPY32  t2, t0                          # index bit set: hash(branch[i] + value)
    addi    t2, t2, 32
    COPY32  t2, t3
    j       21f
2:  COPY32  t2, t3                          # else hash(value + branch[i])
    addi    t2, t2, 32
    COPY32  t2, t0
21: addi    a0, sp, L + 32
    li      a1, 64
    addi    a2, sp, L
    call    lantern_sha256_short
    addi    s4, s4, 1
    j       1b
3:  addi    t0, sp, L                       # value == root
    li      a1, 0
    NE32    t0, s3, 6f
    li      a1, 1
6:  li      a0, LANTERN_OK
7:  LEAVE 96
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 96
END_FUNCTION lantern_commitments_in_body

/* Locals: sp+0 out. */
SPEC_FUNCTION verify_data_column_sidecar_inclusion_proof
    FRAME 16
    sd      a2, 0(sp)
    sd      zero, 0(a2)
    mv      t0, a0
    mv      a0, a1
    PART    a1, a2, t0, DataColumnSidecar_kzg_commitments
    addi    a3, t0, DataColumnSidecar_kzg_commitments_inclusion_proof
    addi    a4, t0, DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_body_root
    call    lantern_commitments_in_body
    bnez    a0, 7f
    ld      t0, 0(sp)
    sd      a1, 0(t0)
7:  UNFRAME 16
SPEC_END verify_data_column_sidecar_inclusion_proof

/* Locals: sp+0 out. */
SPEC_FUNCTION verify_partial_data_column_header_inclusion_proof
    FRAME 16
    sd      a2, 0(sp)
    sd      zero, 0(a2)
    mv      t0, a0
    mv      a0, a1
    PART    a1, a2, t0, PartialDataColumnHeader_kzg_commitments
    addi    a3, t0, PartialDataColumnHeader_kzg_commitments_inclusion_proof
    addi    a4, t0, PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_body_root
    call    lantern_commitments_in_body
    bnez    a0, 7f
    ld      t0, 0(sp)
    sd      a1, 0(t0)
7:  UNFRAME 16
SPEC_END verify_partial_data_column_header_inclusion_proof

/* dst = the set bits of the BitList at PartRef ref of value v. Uses t0-t4. */
.macro BIT_COUNT dst, v, ref
    PART    t0, t1, \v, \ref
    li      \dst, 0
    li      t2, 0
96: bgeu    t2, t1, 97f
    srli    t3, t2, 3
    add     t3, t0, t3
    lbu     t3, 0(t3)
    andi    t4, t2, 7
    srl     t3, t3, t4
    andi    t3, t3, 1
    add     \dst, \dst, t3
    addi    t2, t2, 1
    j       96b
97:
.endm

/*
 * s1 sidecar, s2 settings, s3 scratch, s4 out, s5 n, s6 commitments, s7 cell indices,
 * s8 cells, s9 proofs, s10 scratch size left. Locals: L valid, L+8 header, L+16 column index.
 */
SPEC_FUNCTION verify_partial_data_column_sidecar_kzg_proofs
    ENTER 32
    mv      s1, a0
    sd      a1, (L + 8)(sp)
    ld      t0, 0(a2)
    sd      t0, (L + 16)(sp)
    mv      s2, a3
    mv      s3, a4
    mv      s4, a5
    sd      zero, 0(s4)
    BIT_COUNT s5, s1, PartialDataColumnSidecar_cells_present_bitmap    # blob_indices: the set bits
    ld      t0, (PartialDataColumnSidecar_partial_column + 8)(s1)  # one cell and one proof per index, as the batch asserts
    bne     t0, s5, 8f
    ld      t0, (PartialDataColumnSidecar_kzg_proofs + 8)(s1)
    bne     t0, s5, 8f
    li      t0, DA_SCRATCH_PER_BLOB
    mulhu   t1, s5, t0
    bnez    t1, 9f
    mul     t0, s5, t0
    li      t1, DA_SCRATCH_FIXED
    add     t2, t0, t1
    bltu    t2, t1, 9f
    ld      s10, 0(s3)
    bltu    s10, t2, 9f
    DA_LIST s6, 48                        # commitments_bytes = [all_commitments[index] for index in blob_indices]
    DA_LIST s7, 8                         # cell_indices = [column_index] * len(blob_indices)
    DA_LIST s8, CRYPTO_KZG_CELL_SIZE      # cells = sidecar.partial_column
    DA_LIST s9, 48                        # proofs_bytes = sidecar.kzg_proofs
    ld      t0, (L + 8)(sp)
    PART    t5, t6, t0, PartialDataColumnHeader_kzg_commitments
    PART    t0, t1, s1, PartialDataColumnSidecar_cells_present_bitmap
    addi    a5, s6, LIST_FIXED
    li      t2, 0
1:  bgeu    t2, t1, 2f
    srli    t3, t2, 3
    add     t3, t0, t3
    lbu     t3, 0(t3)
    andi    t4, t2, 7
    srl     t3, t3, t4
    andi    t3, t3, 1
    beqz    t3, 11f
    bgeu    t2, t6, 8f                      # an index past the commitments: the spec's indexing raises
    li      t3, 48
    mul     t3, t2, t3
    add     t3, t5, t3
    li      t4, 0
12: li      a3, 48
    bgeu    t4, a3, 13f
    add     a3, t3, t4
    lwu     a3, 0(a3)
    add     a4, a5, t4
    sw      a3, 0(a4)
    addi    t4, t4, 4
    j       12b
13: addi    a5, a5, 48
11: addi    t2, t2, 1
    j       1b
2:  ld      t0, (L + 16)(sp)
    addi    t1, s7, LIST_FIXED
    mv      t2, s5
3:  beqz    t2, 4f
    sd      t0, 0(t1)
    addi    t1, t1, 8
    addi    t2, t2, -1
    j       3b
4:  addi    a0, s8, LIST_FIXED
    PART    a1, a2, s1, PartialDataColumnSidecar_partial_column
    slli    a2, a2, 11
    call    lantern_copy
    addi    a0, s9, LIST_FIXED
    PART    a1, a2, s1, PartialDataColumnSidecar_kzg_proofs
    li      t0, 48
    mul     a2, a2, t0
    call    lantern_copy
    sd      s10, 0(s3)                      # asm-crypto's scratch: the front
    mv      a0, s2
    mv      a1, s6
    mv      a2, s7
    mv      a3, s8
    mv      a4, s9
    mv      a5, s3
    addi    a6, sp, L
    CALL_GLOBAL crypto_kzg_verify_cell_kzg_proof_batch
    li      t0, CRYPTO_BUFFER_TOO_SMALL
    beq     a0, t0, 9f
    bnez    a0, 8f                          # an input that does not decode: the spec raises
    ld      t0, L(sp)
    sd      t0, 0(s4)
8:  li      a0, LANTERN_OK
    LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END verify_partial_data_column_sidecar_kzg_proofs

.endif

.if FORK >= FORK_DENEB
/*
 * The checks of a block header shared by the sidecar topics, from lantern_is_future_slot to the finalized ancestor:
 * a0 = status, a1 = LANTERN_VALID, LANTERN_GOSSIP_IGNORE or LANTERN_GOSSIP_REJECT, a2 = the parent node.
 * Takes s1 seen, s2 store, s4 current_time_ms, s5 head state, s7 scratch, and a0 the SignedBeaconBlockHeader.
 * s1-s10 are the caller's and stay unchanged. Locals: sp+0 header, sp+8 parent node.
 */
LOCAL_FUNCTION lantern_header_checks
    FRAME 16
    sd      a0, 0(sp)
    mv      a0, s2                          # [IGNORE] not from a future slot
    ld      t0, 0(sp)
    ld      a1, (SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(t0)
    mv      a2, s4
    call    lantern_is_future_slot
    bnez    a0, 4f
    mv      a0, s2                          # [IGNORE] after the finalized slot
    call    lantern_finalized_slot
    ld      t0, 0(sp)
    ld      t0, (SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(t0)
    bgeu    a0, t0, 4f
    mv      a0, s2                          # [IGNORE] the parent has been seen; [REJECT] it passed validation
    mv      a1, s1
    ld      a2, 0(sp)
    addi    a2, a2, SignedBeaconBlockHeader_message + BeaconBlockHeader_parent_root
    call    lantern_block_lookup
    beqz    a1, 4f
    li      t0, 2
    bne     a1, t0, 5f
    sd      a0, 8(sp)
    ld      t0, 0(sp)                       # [REJECT] the proposer index is valid
    ld      t0, (SignedBeaconBlockHeader_message + BeaconBlockHeader_proposer_index)(t0)
    VALIDATOR_AT t1, s5, t0, 5f
    mv      a0, s5                          # [REJECT] the proposer signature of the header
    li      a1, DOMAIN_BEACON_PROPOSER
    ld      a4, 0(sp)
    ld      a2, (SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(a4)
    srli    a2, a2, LOG2_SLOTS_PER_EPOCH
    ADDRESS a3, lantern_type_BeaconBlockHeader
    addi    a5, t1, Validator_pubkey
    addi    a6, a4, SignedBeaconBlockHeader_signature
    addi    a4, a4, SignedBeaconBlockHeader_message
    mv      a7, s7
    call    lantern_verify_signed
    bnez    a0, 7f
    beqz    a1, 5f
    ld      t0, 8(sp)                       # [REJECT] a higher slot than the parent
    NODE    t0, s2, t0
    ld      t0, BlockNode_slot(t0)
    ld      t1, 0(sp)
    ld      t1, (SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(t1)
    bgeu    t0, t1, 5f
    mv      a0, s2                          # [REJECT] the finalized checkpoint is an ancestor
    ld      a1, 8(sp)
    call    lantern_finalized_is_ancestor
    bnez    a0, 6f
    beqz    a1, 5f
    li      a1, LANTERN_VALID
    j       8f
4:  li      a1, LANTERN_GOSSIP_IGNORE
    j       8f
5:  li      a1, LANTERN_GOSSIP_REJECT
8:  ld      a2, 8(sp)
    li      a0, LANTERN_OK
7:  UNFRAME 16
6:  li      t0, LANTERN_BUFFER_TOO_SMALL    # a spec failure: its code as the outcome
    beq     a0, t0, 7b
    mv      a1, a0
    j       8b
END_FUNCTION lantern_header_checks
.endif

/* ---------------------------------------------------------------- Blob sidecars */

.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
.if FORK == FORK_ELECTRA
.set BLOB_SUBNETS, CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA
.set BLOB_LIMIT, CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
.else
.set BLOB_SUBNETS, CONFIG_BLOB_SIDECAR_SUBNET_COUNT
.set BLOB_LIMIT, CONFIG_MAX_BLOBS_PER_BLOCK
.endif

/* (blob_index, config, out): blob_index % BLOB_SIDECAR_SUBNET_COUNT, _ELECTRA from electra on. */
SPEC_LEAF compute_subnet_for_blob_sidecar
    LDQ     a4, a1, BLOB_SUBNETS
    beqz    a4, 9f
    ld      a3, 0(a0)
    remu    a5, a3, a4
    sd      a5, 0(a2)
    RETURN_OK
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_subnet_for_blob_sidecar

/*
 * (sidecar, out): is_valid_merkle_branch of hash_tree_root(kzg_commitment) at the subtree index of
 * blob_kzg_commitments[index] against the header's body_root. s1 sidecar, s2 out.
 * Locals: L the commitment as two chunks (64), L+64 its root (32), L+96 depth, L+104 index.
 */
SPEC_FUNCTION verify_blob_sidecar_inclusion_proof
    ENTER 112
    mv      s1, a0
    mv      s2, a1
    addi    a0, sp, L
    li      a1, 64
    call    lantern_zero
    addi    a0, sp, L
    ADDQ    a1, s1, BlobSidecar_kzg_commitment
    li      a2, 48
    call    lantern_copy
    addi    a0, sp, L                       # hash_tree_root(Bytes48): its two chunks
    li      a1, 64
    addi    a2, sp, L + 64
    call    lantern_sha256_short
    li      t0, KZG_COMMITMENT_INCLUSION_PROOF_DEPTH
    sd      t0, (L + 96)(sp)
    ld      t0, BlobSidecar_index(s1)       # field 11 of the body, the list's data root, then the index
    li      t1, 11 << (KZG_COMMITMENT_INCLUSION_PROOF_DEPTH - 4)
    add     t0, t0, t1
    sd      t0, (L + 104)(sp)
    addi    a0, sp, L + 64
    ADDQ    a1, s1, BlobSidecar_kzg_commitment_inclusion_proof
    addi    a2, sp, L + 96
    addi    a3, sp, L + 104
    ADDQ    a4, s1, BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_body_root
    mv      a5, s2
    call    lantern_is_valid_merkle_branch
    LEAVE 112
SPEC_END verify_blob_sidecar_inclusion_proof
.if (1 << (KZG_COMMITMENT_INCLUSION_PROOF_DEPTH - 5)) != MAX_BLOB_COMMITMENTS_PER_BLOCK
.error "verify_blob_sidecar_inclusion_proof assumes a body of 16 leaves and a list of MAX_BLOB_COMMITMENTS_PER_BLOCK"
.endif

/*
 * s1 seen, s2 store, s3 sidecar, s4 current_time_ms, s5 head state, s6 proposer state, s7 scratch,
 * s8 result, s9 the block header, s10 scratch size.
 * Locals: L subnet_id, L+8 settings, L+16 out, L+24 expected proposer.
 */
SPEC_FUNCTION validate_blob_sidecar_gossip
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(a3)
    ld      t0, 0(a4)
    sd      t0, L(sp)
    mv      s5, a5
    mv      s6, a6
    sd      a7, (L + 8)(sp)
    ld      s7, (32 + 96)(sp)               # the ninth and tenth arguments
    ld      s8, (32 + 96 + 8)(sp)
    sd      zero, 0(s8)
    NEED_SCRATCH s7, s6, 2, 9f              # get_beacon_proposer_index of the proposer state takes S(2)
    ld      s10, 0(s7)
    ADDQ    s9, s3, BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message
    mv      a0, s1                          # [IGNORE] the first sidecar for (slot, proposer, index)
    li      a1, SEEN_BLOB_SIDECAR
    ld      a2, BeaconBlockHeader_slot(s9)
    ld      a3, BeaconBlockHeader_proposer_index(s9)
    ld      a4, BlobSidecar_index(s3)
    call    lantern_seen_find_key
    bnez    a0, 4f
    ld      t0, BlobSidecar_index(s3)       # [REJECT] the index is below the blob limit
    LDQ     t1, s2, Store_config + BLOB_LIMIT
    bgeu    t0, t1, 5f
    addi    a0, s3, BlobSidecar_index       # [REJECT] the subnet: compute_subnet_for_blob_sidecar
    addi    a1, s2, Store_config
    addi    a2, sp, L + 16
    call    lantern_compute_subnet_for_blob_sidecar
    CHECK_STATUS s8, 7f, 8f
    ld      t0, L(sp)
    ld      t1, (L + 16)(sp)
    bne     t0, t1, 5f
    ADDQ    a0, s3, BlobSidecar_signed_block_header     # the header checks, through the finalized ancestor
    call    lantern_header_checks
    bnez    a0, 7f
    beqz    a1, 1f
    mv      a0, a1
    j       6f
1:  mv      a0, s3                          # [REJECT] verify_blob_sidecar_inclusion_proof
    addi    a1, sp, L + 16
    call    lantern_verify_blob_sidecar_inclusion_proof
    bnez    a0, 7f
    ld      t0, (L + 16)(sp)
    beqz    t0, 5f
    sd      s10, 0(s7)                      # [REJECT] verify_blob_kzg_proof(blob, kzg_commitment, kzg_proof)
    ld      a0, (L + 8)(sp)
    ADDQ    a1, s3, BlobSidecar_blob
    ADDQ    a2, s3, BlobSidecar_kzg_commitment
    ADDQ    a3, s3, BlobSidecar_kzg_proof
    mv      a4, s7
    addi    a5, sp, L + 16
    CALL_GLOBAL crypto_kzg_verify_blob_kzg_proof
    li      t0, CRYPTO_BUFFER_TOO_SMALL
    beq     a0, t0, 9f
    bnez    a0, 5f                          # an input that does not decode: the spec's exception
    ld      t0, (L + 16)(sp)
    beqz    t0, 5f
    sd      s10, 0(s7)                      # [REJECT] the expected proposer of the parent state at the slot
    mv      a0, s6
    mv      a1, s7
    addi    a2, sp, L + 24
    call    lantern_get_beacon_proposer_index
    CHECK_STATUS s8, 7f, 8f
    ld      t0, (L + 24)(sp)
    ld      t1, BeaconBlockHeader_proposer_index(s9)
    bne     t0, t1, 5f
    mv      a0, s1                          # seen.blob_sidecar_tuples.add(...)
    call    lantern_seen_key_room
    beqz    a0, 9f
    mv      a0, s1
    li      a1, SEEN_BLOB_SIDECAR
    ld      a2, BeaconBlockHeader_slot(s9)
    ld      a3, BeaconBlockHeader_proposer_index(s9)
    ld      a4, BlobSidecar_index(s3)
    call    lantern_seen_add_key
    j       8f
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s8)
8:  li      a0, LANTERN_OK
7:  LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END validate_blob_sidecar_gossip
.endif

.if FORK >= FORK_FULU

/*
 * s1 seen, s2 store, s3 sidecar, s4 current_time_ms, s5 head state, s6 proposer state, s7 scratch,
 * s8 result, s9 the block header, s10 parent node.
 * Locals: L subnet_id, L+8 settings, L+16 out, L+24 expected proposer.
 */
SPEC_FUNCTION validate_data_column_sidecar_gossip
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(a3)
    ld      t0, 0(a4)
    sd      t0, L(sp)
    mv      s5, a5
    mv      s6, a6
    sd      a7, (L + 8)(sp)
    ld      s7, (32 + 96)(sp)               # the ninth and tenth arguments
    ld      s8, (32 + 96 + 8)(sp)
    sd      zero, 0(s8)
    NEED_SCRATCH s7, s5, 0, 9f
    addi    s9, s3, DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message
    mv      a0, s1                          # [IGNORE] the first sidecar for (slot, proposer, index)
    li      a1, SEEN_DATA_COLUMN
    ld      a2, BeaconBlockHeader_slot(s9)
    ld      a3, BeaconBlockHeader_proposer_index(s9)
    ld      a4, DataColumnSidecar_index(s3)
    call    lantern_seen_find_key
    bnez    a0, 4f
    mv      a0, s3                          # [REJECT] verify_data_column_sidecar
    addi    a1, s2, Store_config
    addi    a2, sp, L + 16
    call    lantern_verify_data_column_sidecar
    bnez    a0, 7f
    ld      t0, (L + 16)(sp)
    beqz    t0, 5f
    addi    a0, s3, DataColumnSidecar_index # [REJECT] the subnet: compute_subnet_for_data_column_sidecar
    addi    a1, s2, Store_config
    addi    a2, sp, L + 16
    call    lantern_compute_subnet_for_data_column_sidecar
    CHECK_STATUS s8, 7f, 8f
    ld      t0, L(sp)
    ld      t1, (L + 16)(sp)
    bne     t0, t1, 5f
    addi    a0, s3, DataColumnSidecar_signed_block_header   # the header checks, through the finalized ancestor
    call    lantern_header_checks
    bnez    a0, 7f
    mv      s10, a2
    beqz    a1, 1f
    mv      a0, a1
    j       6f
1:  mv      a0, s3                          # [REJECT] verify_data_column_sidecar_inclusion_proof
    mv      a1, s7
    addi    a2, sp, L + 16
    call    lantern_verify_data_column_sidecar_inclusion_proof
    bnez    a0, 7f
    ld      t0, (L + 16)(sp)
    beqz    t0, 5f
    mv      a0, s3                          # [REJECT] verify_data_column_sidecar_kzg_proofs
    ld      a1, (L + 8)(sp)
    mv      a2, s7
    addi    a3, sp, L + 16
    call    lantern_verify_data_column_sidecar_kzg_proofs
    bnez    a0, 7f
    ld      t0, (L + 16)(sp)
    beqz    t0, 5f
    mv      a0, s6                          # [REJECT] the expected proposer of the parent state at the slot
    addi    a1, sp, L + 24
    call    lantern_get_beacon_proposer_index
    CHECK_STATUS s8, 7f, 8f
    ld      t0, (L + 24)(sp)
    ld      t1, BeaconBlockHeader_proposer_index(s9)
    bne     t0, t1, 5f
    mv      a0, s1                          # seen.data_column_sidecar_tuples.add(...)
    call    lantern_seen_key_room
    beqz    a0, 9f
    mv      a0, s1
    li      a1, SEEN_DATA_COLUMN
    ld      a2, BeaconBlockHeader_slot(s9)
    ld      a3, BeaconBlockHeader_proposer_index(s9)
    ld      a4, DataColumnSidecar_index(s3)
    call    lantern_seen_add_key
    j       8f
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s8)
8:  li      a0, LANTERN_OK
7:  LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END validate_data_column_sidecar_gossip

/*
 * s1 seen, s2 store, s3 sidecar, s4 current_time_ms, s5 head state, s6 proposer state, s7 scratch,
 * s8 result, s9 the header value, or 0, s10 the cells present.
 * Locals: L group_id, L+8 column_index, L+16 settings, L+24 out, L+32 header root (32),
 * L+64 expected proposer, L+72 the block header root (32).
 */
SPEC_FUNCTION validate_partial_data_column_sidecar_gossip
    ENTER 112
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(a3)
    sd      a4, L(sp)
    ld      t0, 0(a5)
    sd      t0, (L + 8)(sp)
    mv      s5, a6
    mv      s6, a7
    ld      t0, (112 + 96)(sp)              # the ninth to eleventh arguments
    sd      t0, (L + 16)(sp)
    ld      s7, (112 + 96 + 8)(sp)
    ld      s8, (112 + 96 + 16)(sp)
    sd      zero, 0(s8)
    NEED_SCRATCH s7, s5, 0, 9f
    li      s9, 0                           # has_header: the optional header holds one
    ld      t0, (PartialDataColumnSidecar_header + 8)(s3)
    beqz    t0, 1f
    ld      s9, PartialDataColumnSidecar_header(s3)
    add     s9, s3, s9
1:  BIT_COUNT s10, s3, PartialDataColumnSidecar_cells_present_bitmap
    or      t0, s10, s9                     # [REJECT] a header and/or cells are present
    beqz    t0, 5f
    ld      t0, (PartialDataColumnSidecar_partial_column + 8)(s3)  # [REJECT] one cell per set bit
    bne     t0, s10, 5f
    ld      t0, (PartialDataColumnSidecar_kzg_proofs + 8)(s3)  # [REJECT] one proof per set bit
    bne     t0, s10, 5f
    beqz    s9, 3f
    ADDRESS a0, lantern_type_PartialDataColumnHeader    # [REJECT] the header equals a prior validated header
    mv      a1, s9
    mv      a2, s7
    addi    a3, sp, L + 32
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    mv      a0, s1
    ld      a1, L(sp)
    call    lantern_seen_find_header
    beqz    a0, 2f
    addi    t0, a0, SeenHeader_header_root
    addi    t1, sp, L + 32
    NE32    t0, t1, 5f
2:  ADDRESS a0, lantern_type_BeaconBlockHeader          # [REJECT] the block header's root is the group id
    addi    a1, s9, PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message
    mv      a2, s7
    addi    a3, sp, L + 72
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    addi    t0, sp, L + 72
    ld      t1, L(sp)
    NE32    t0, t1, 5f
    ld      t0, (PartialDataColumnHeader_kzg_commitments + 8)(s9)  # [REJECT] the header has commitments
    beqz    t0, 5f
    addi    a0, s9, PartialDataColumnHeader_signed_block_header    # the header checks, through the finalized ancestor
    call    lantern_header_checks
    bnez    a0, 7f
    beqz    a1, 21f
    mv      a0, a1
    j       6f
21: mv      a0, s9                          # [REJECT] verify_partial_data_column_header_inclusion_proof
    mv      a1, s7
    addi    a2, sp, L + 24
    call    lantern_verify_partial_data_column_header_inclusion_proof
    bnez    a0, 7f
    ld      t0, (L + 24)(sp)
    beqz    t0, 5f
    mv      a0, s6                          # [REJECT] the expected proposer of the parent state at the slot
    addi    a1, sp, L + 64
    call    lantern_get_beacon_proposer_index
    CHECK_STATUS s8, 7f, 8f
    ld      t0, (L + 64)(sp)
    ld      t1, (PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_proposer_index)(s9)
    bne     t0, t1, 5f
    mv      a0, s1                          # seen.partial_data_column_headers[group_id.beacon_block_root] = header
    ld      a1, L(sp)
    call    lantern_seen_find_header
    bnez    a0, 3f
    ld      t0, 0(s9)                       # room for 64 + the header value
    addi    t0, t0, SeenHeader_header
    ld      t1, 0(s1)
    ld      t2, Seen_headers(s1)
    sub     t1, t1, t2
    ld      t3, Seen_header_bytes(s1)
    sub     t1, t1, t3
    bltu    t1, t0, 9f
    add     t4, t2, t3
    add     t4, s1, t4
    add     t3, t3, t0
    sd      t3, Seen_header_bytes(s1)
    ld      t3, (Seen_headers + 8)(s1)
    addi    t3, t3, 1
    sd      t3, (Seen_headers + 8)(s1)
    ld      t5, L(sp)
    COPY32  t4, t5
    addi    t5, t4, SeenHeader_header_root
    addi    t6, sp, L + 32
    COPY32  t5, t6
    addi    a0, t4, SeenHeader_header
    mv      a1, s9
    ld      a2, 0(s9)
    call    lantern_copy
3:  beqz    s10, 8f                         # has_cells
    mv      a0, s1                          # [IGNORE] a valid header for the group has been seen
    ld      a1, L(sp)
    call    lantern_seen_find_header
    beqz    a0, 4f
    addi    s9, a0, SeenHeader_header
    mv      a0, s2                          # [IGNORE] its slot is not in the future
    ld      a1, (PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(s9)
    mv      a2, s4
    call    lantern_is_future_slot
    bnez    a0, 4f
    mv      a0, s2                          # [IGNORE] its slot is after the finalized slot
    call    lantern_finalized_slot
    ld      t0, (PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(s9)
    bgeu    a0, t0, 4f
    ld      t0, (PartialDataColumnSidecar_cells_present_bitmap + 8)(s3)    # [REJECT] one bit per commitment
    ld      t1, (PartialDataColumnHeader_kzg_commitments + 8)(s9)
    bne     t0, t1, 5f
    mv      a0, s3                          # [REJECT] verify_partial_data_column_sidecar_kzg_proofs
    mv      a1, s9
    addi    a2, sp, L + 8
    ld      a3, (L + 16)(sp)
    mv      a4, s7
    addi    a5, sp, L + 24
    call    lantern_verify_partial_data_column_sidecar_kzg_proofs
    bnez    a0, 7f
    ld      t0, (L + 24)(sp)
    beqz    t0, 5f
    j       8f
4:  li      a0, LANTERN_GOSSIP_IGNORE
    j       6f
5:  li      a0, LANTERN_GOSSIP_REJECT
6:  sd      a0, 0(s8)
8:  li      a0, LANTERN_OK
7:  LEAVE 112
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 112
SPEC_END validate_partial_data_column_sidecar_gossip
.endif
