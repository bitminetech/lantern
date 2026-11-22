/*
 * Networking rules, ARM64. Requirements: docs/reference/networking.md.
 */

.if FORK >= FORK_FULU
/*
 * x19 out entries, x20 NUMBER_OF_CUSTODY_GROUPS, x21 custody_group_count, x22 groups found, x23 out.
 * Locals: L current_id (32), L+32 the digest (32).
 */
SPEC_FUNCTION get_custody_groups
    ENTER 64
    ldr     x20, [x2, #CONFIG_NUMBER_OF_CUSTODY_GROUPS]
    ldr     x21, [x1]
    mov     x23, x3
    cmp     x21, x20                        /* assert custody_group_count <= NUMBER_OF_CUSTODY_GROUPS */
    b.hi    8f
    ldr     x9, [x23]                       /* room for custody_group_count entries */
    subs    x9, x9, #LIST_FIXED
    b.lo    9f
    lsr     x9, x9, #3
    cmp     x21, x9
    b.hi    9f
    add     x9, sp, #L                      /* current_id = node_id */
    COPY32  x9, x0
    add     x19, x23, #LIST_FIXED
    cmp     x21, x20
    b.ne    2f
    mov     x9, #0                          /* every group: 0 to NUMBER_OF_CUSTODY_GROUPS - 1 */
    cbz     x21, 6f
1:  str     x9, [x19, x9, lsl #3]
    add     x9, x9, #1
    cmp     x9, x21
    b.lo    1b
    b       6f
2:  mov     x22, #0
3:  cmp     x22, x21                        /* while len(custody_groups) < custody_group_count */
    b.hs    6f
    add     x0, sp, #L                      /* sha256(uint_to_bytes(current_id)) */
    mov     x1, #32
    add     x2, sp, #(L + 32)
    bl      sha256_short
    ldr     x9, [sp, #(L + 32)]             /* bytes_to_uint64(digest[0:8]) % NUMBER_OF_CUSTODY_GROUPS */
    udiv    x10, x9, x20
    msub    x9, x10, x20, x9
    mov     x10, #0                         /* the first entry not below the group */
4:  cmp     x10, x22
    b.hs    5f
    ldr     x11, [x19, x10, lsl #3]
    cmp     x11, x9
    b.hs    41f
    add     x10, x10, #1
    b       4b
41: b.eq    55f                             /* already in custody_groups */
5:  mov     x11, x22                        /* move the entries from x10 up by one */
51: cmp     x11, x10
    b.ls    52f
    sub     x12, x11, #1
    ldr     x13, [x19, x12, lsl #3]
    str     x13, [x19, x11, lsl #3]
    mov     x11, x12
    b       51b
52: str     x9, [x19, x10, lsl #3]
    add     x22, x22, #1
55: ldp     x9, x10, [sp, #L]               /* current_id += 1, wrapping from UINT256_MAX to 0 */
    ldp     x11, x12, [sp, #(L + 16)]
    adds    x9, x9, #1
    adcs    x10, x10, xzr
    adcs    x11, x11, xzr
    adc     x12, x12, xzr
    stp     x9, x10, [sp, #L]
    stp     x11, x12, [sp, #(L + 16)]
    b       3b
6:  mov     x9, #LIST_FIXED
    stp     x9, x21, [x23, #8]              /* offset 24, count */
    mov     x0, #LANTERN_OK
    LEAVE 64
8:  mov     x0, #LANTERN_INVALID_CUSTODY_GROUP
    LEAVE 64
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END get_custody_groups

SPEC_LEAF compute_columns_for_custody_group
    ldr     x9, [x1, #CONFIG_NUMBER_OF_CUSTODY_GROUPS]
    ldr     x10, [x0]
    cmp     x10, x9                         /* assert custody_group < NUMBER_OF_CUSTODY_GROUPS */
    b.hs    8f
    MOVQ    x11, NUMBER_OF_COLUMNS          /* columns_per_group */
    udiv    x11, x11, x9
    ldr     x12, [x2]
    subs    x12, x12, #LIST_FIXED
    b.lo    9f
    lsr     x12, x12, #3
    cmp     x11, x12
    b.hi    9f
    mov     x12, #LIST_FIXED
    stp     x12, x11, [x2, #8]
    add     x12, x2, #LIST_FIXED
    cbz     x11, 2f
1:  str     x10, [x12], #8                  /* NUMBER_OF_CUSTODY_GROUPS * index + custody_group */
    add     x10, x10, x9
    subs    x11, x11, #1
    b.ne    1b
2:  RETURN_OK
8:  mov     x0, #LANTERN_INVALID_CUSTODY_GROUP
    ret
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    ret
SPEC_END compute_columns_for_custody_group
.endif

/* ---------------------------------------------------------------- Seen */

.if SeenKey__mem != 32 || SeenBits__mem != 320 || SeenBlock__mem != 40 || SEEN_BITS_BYTES * 8 < MAX_VALIDATORS_PER_COMMITTEE || SEEN_BITS_BYTES * 8 < SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT
.error "the gossip code assumes the Seen layouts of include/lantern.inc"
.endif

/* L0: x0 = 1 when seen x0 holds the SeenKey (x1 kind, x2 a, x3 b, x4 c), else 0. A leaf; uses x5-x8. */
LOCAL_FUNCTION seen_find_key
    UNWIND_END_PROLOGUE
    PART    x5, x6, x0, Seen_keys
1:  cbz     x6, 3f
    ldp     x7, x8, [x5]
    cmp     x7, x1
    ccmp    x8, x2, #0, eq
    b.ne    2f
    ldp     x7, x8, [x5, #16]
    cmp     x7, x3
    ccmp    x8, x4, #0, eq
    b.eq    4f
2:  add     x5, x5, #SeenKey__mem
    sub     x6, x6, #1
    b       1b
3:  mov     x0, #0
    ret
4:  mov     x0, #1
    ret
END_FUNCTION seen_find_key

/* L0: x0 = the free SeenKey entries of seen x0. A leaf; uses x1-x2. */
LOCAL_FUNCTION seen_key_room
    UNWIND_END_PROLOGUE
    ldr     x1, [x0, #Seen_keys]
    ldr     x2, [x0, #Seen_bits]
    sub     x2, x2, x1
    lsr     x2, x2, #5
    ldr     x1, [x0, #(Seen_keys + 8)]
    sub     x0, x2, x1
    ret
END_FUNCTION seen_key_room

/* L0: append the SeenKey (x1 kind, x2 a, x3 b, x4 c) to seen x0, which has room. A leaf; uses x5, x6. */
LOCAL_FUNCTION seen_add_key
    UNWIND_END_PROLOGUE
    PART    x5, x6, x0, Seen_keys
    add     x5, x5, x6, lsl #5
    stp     x1, x2, [x5]
    stp     x3, x4, [x5, #16]
    add     x6, x6, #1
    str     x6, [x0, #(Seen_keys + 8)]
    ret
END_FUNCTION seen_add_key

/* L0: x0 = the free SeenBits entries of seen x0. A leaf; uses x1-x3. */
LOCAL_FUNCTION seen_bits_room
    UNWIND_END_PROLOGUE
    ldr     x1, [x0, #Seen_bits]
    ldr     x2, [x0, #Seen_blocks]
    sub     x2, x2, x1
    mov     x3, #SeenBits__mem
    udiv    x2, x2, x3
    ldr     x1, [x0, #(Seen_bits + 8)]
    sub     x0, x2, x1
    ret
END_FUNCTION seen_bits_room

/*
 * L0: is_non_strict_superset of the SeenBits of key (x1 kind, root at x2, x3 a, x4 b) in seen x0,
 * for the x6 bits at x5: x0 = 1 when one of them has every bit of x5 set. A leaf; uses x7-x13.
 */
LOCAL_FUNCTION seen_superset
    UNWIND_END_PROLOGUE
    PART    x7, x8, x0, Seen_bits
    add     x9, x6, #7
    lsr     x9, x9, #3                      /* bytes of the bits */
1:  cbz     x8, 8f
    ldr     x10, [x7, #SeenBits_kind]
    cmp     x10, x1
    b.ne    5f
    ldp     x10, x11, [x7, #SeenBits_a]
    cmp     x10, x3
    ccmp    x11, x4, #0, eq
    b.ne    5f
    ldr     x10, [x7, #SeenBits_length]     /* a bitfield of another length: skipped */
    cmp     x10, x6
    b.ne    5f
    ldp     x10, x11, [x7, #SeenBits_root]
    ldp     x12, x13, [x2]
    cmp     x10, x12
    ccmp    x11, x13, #0, eq
    b.ne    5f
    ldp     x10, x11, [x7, #(SeenBits_root + 16)]
    ldp     x12, x13, [x2, #16]
    cmp     x10, x12
    ccmp    x11, x13, #0, eq
    b.ne    5f
    mov     x10, #0
2:  cmp     x10, x9
    b.hs    9f
    add     x11, x7, #SeenBits_bits
    ldrb    w12, [x11, x10]
    ldrb    w13, [x5, x10]
    bics    wzr, w13, w12                   /* a bit of the new bits outside the prior */
    b.ne    5f
    add     x10, x10, #1
    b       2b
5:  add     x7, x7, #SeenBits__mem
    sub     x8, x8, #1
    b       1b
8:  mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION seen_superset

/* L0: append the SeenBits of key (x1 kind, root at x2, x3 a, x4 b) and the x6 bits at x5 to seen x0, which has room. */
LOCAL_FUNCTION seen_add_bits
    FRAME 32
    PART    x7, x8, x0, Seen_bits
    mov     x9, #SeenBits__mem
    madd    x7, x8, x9, x7
    add     x8, x8, #1
    str     x8, [x0, #(Seen_bits + 8)]
    str     x1, [x7, #SeenBits_kind]
    add     x9, x7, #SeenBits_root
    COPY32  x9, x2
    stp     x3, x4, [x7, #SeenBits_a]
    str     x6, [x7, #SeenBits_length]
    str     x7, [sp, #16]
    stp     x5, x6, [sp, #24]
    add     x0, x7, #SeenBits_bits
    mov     x1, #SEEN_BITS_BYTES
    bl      lantern_zero
    ldr     x0, [sp, #16]
    add     x0, x0, #SeenBits_bits
    ldp     x1, x2, [sp, #24]
    add     x2, x2, #7
    lsr     x2, x2, #3
    bl      lantern_copy
    UNFRAME 32
END_FUNCTION seen_add_bits

/* L0: x0 = the SeenHeader of block root x1 in seen x0, or 0. A leaf; uses x2-x10. */
LOCAL_FUNCTION seen_find_header
    UNWIND_END_PROLOGUE
    PART    x2, x3, x0, Seen_headers
    ldp     x4, x5, [x1]
    ldp     x6, x7, [x1, #16]
1:  cbz     x3, 3f
    ldp     x8, x9, [x2, #SeenHeader_block_root]
    cmp     x8, x4
    ccmp    x9, x5, #0, eq
    b.ne    2f
    ldp     x8, x9, [x2, #(SeenHeader_block_root + 16)]
    cmp     x8, x6
    ccmp    x9, x7, #0, eq
    b.eq    4f
2:  ldr     x10, [x2, #SeenHeader_header]   /* the next entry: 64 + the header value's size */
    add     x2, x2, x10
    add     x2, x2, #SeenHeader_header
    sub     x3, x3, #1
    b       1b
3:  mov     x0, #0
    ret
4:  mov     x0, x2
    ret
END_FUNCTION seen_find_header

/* ---------------------------------------------------------------- Gossip helpers */

/* dst = compute_time_at_slot_ms(genesis_time_ms of store st, slot), UINT64_MAX when it does not fit. Uses x16, x17. */
.macro SLOT_TIME dst, st, slot
    LDQ     x16, \st, Store_config + CONFIG_SLOT_DURATION_MS
    umulh   x17, \slot, x16
    mul     \dst, \slot, x16
    cbnz    x17, 98f
    ldr     x16, [\st, #Store_genesis_time_ms]
    adds    \dst, \dst, x16
    b.cc    99f
98: mov     \dst, #-1
99:
.endm

/* dst = t + MAXIMUM_GOSSIP_CLOCK_DISPARITY of store st, UINT64_MAX when it does not fit. Uses x16. */
.macro WITH_DISPARITY dst, st, t
    LDQ     x16, \st, Store_config + CONFIG_MAXIMUM_GOSSIP_CLOCK_DISPARITY
    adds    \dst, \t, x16
    csinv   \dst, \dst, xzr, cc
.endm

/* L0: x0 = is_future_slot(store x0, slot x1, current_time_ms x2). A leaf; uses x3, x4, x16, x17. */
LOCAL_FUNCTION is_future_slot
    UNWIND_END_PROLOGUE
    SLOT_TIME x3, x0, x1
    WITH_DISPARITY x4, x0, x2
    cmp     x4, x3
    cset    x0, lo
    ret
END_FUNCTION is_future_slot

/* L0: x0 = is_within_slot_range(store x0, slot x1, slot_range x2, current_time_ms x3). A leaf; uses x4-x6, x16, x17. */
LOCAL_FUNCTION is_within_slot_range
    UNWIND_END_PROLOGUE
    SLOT_TIME x4, x0, x1                    /* current_time_ms + MAXIMUM_GOSSIP_CLOCK_DISPARITY < start_time_ms */
    WITH_DISPARITY x5, x0, x3
    cmp     x5, x4
    b.lo    8f
    adds    x6, x1, x2                      /* end_time_ms = time of slot + slot_range + 1 */
    b.cs    9f
    adds    x6, x6, #1
    b.cs    9f
    SLOT_TIME x4, x0, x6
    WITH_DISPARITY x4, x0, x4               /* end_time_ms + MAXIMUM_GOSSIP_CLOCK_DISPARITY < current_time_ms */
    cmp     x4, x3
    b.lo    8f
9:  mov     x0, #1
    ret
8:  mov     x0, #0
    ret
END_FUNCTION is_within_slot_range

/* L0: x0 = is_current_or_previous_epoch(store x0, epoch x1, current_time_ms x2). x19 store, x20 epoch, x21 time. */
LOCAL_FUNCTION is_current_or_previous_epoch
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    lsr     x9, x20, #(64 - LOG2_SLOTS_PER_EPOCH)   /* is_within_epoch(epoch): the start slot fits */
    cbnz    x9, 1f
    lsl     x1, x20, #LOG2_SLOTS_PER_EPOCH
    mov     x2, #(SLOTS_PER_EPOCH - 1)
    mov     x3, x21
    bl      is_within_slot_range
    cbnz    x0, 7f
1:  adds    x9, x20, #1                     /* is_within_epoch(epoch + 1) */
    b.cs    6f
    lsr     x10, x9, #(64 - LOG2_SLOTS_PER_EPOCH)
    cbnz    x10, 6f
    mov     x0, x19
    lsl     x1, x9, #LOG2_SLOTS_PER_EPOCH
    mov     x2, #(SLOTS_PER_EPOCH - 1)
    mov     x3, x21
    bl      is_within_slot_range
    b       7f
6:  mov     x0, #0
7:  LEAVE 0
END_FUNCTION is_current_or_previous_epoch

/*
 * L0: x0 = is_future_epoch(store x0, epoch x1, current_time_ms x2); true when the time with
 * disparity is before genesis, where the spec's subtraction raises. A leaf; uses x3, x4, x16.
 */
LOCAL_FUNCTION is_future_epoch
    UNWIND_END_PROLOGUE
    WITH_DISPARITY x3, x0, x2
    ldr     x4, [x0, #Store_genesis_time_ms]
    subs    x3, x3, x4
    b.lo    9f
    LDQ     x4, x0, Store_config + CONFIG_SLOT_DURATION_MS
    udiv    x3, x3, x4                      /* current_slot */
    lsr     x3, x3, #LOG2_SLOTS_PER_EPOCH
    cmp     x3, x1
    cset    x0, lo
    ret
9:  mov     x0, #1
    ret
END_FUNCTION is_future_epoch

/* L0: x0 = compute_start_slot_at_epoch(finalized epoch of store x0), UINT64_MAX when it does not fit. A leaf; uses x1. */
LOCAL_FUNCTION finalized_slot
    UNWIND_END_PROLOGUE
    ldr     x0, [x0, #(Store_finalized_checkpoint + Checkpoint_epoch)]
    lsr     x1, x0, #(64 - LOG2_SLOTS_PER_EPOCH)
    cbnz    x1, 9f
    lsl     x0, x0, #LOG2_SLOTS_PER_EPOCH
    ret
9:  mov     x0, #-1
    ret
END_FUNCTION finalized_slot

/*
 * L0: x0 = status, x1 = 1 when get_checkpoint_block(store x0, node x1, epoch x2) is the root at x3, else 0.
 * Locals: sp+16 store, sp+24 root.
 */
LOCAL_FUNCTION checkpoint_is
    FRAME 16
    stp     x0, x3, [sp, #16]
    bl      checkpoint_block
    cbnz    x0, 7f
    ldp     x0, x3, [sp, #16]
    NODE    x14, x0, x1
    mov     x1, #0
    NE32    x14, x3, 6f
    mov     x1, #1
6:  mov     x0, #LANTERN_OK
7:  UNFRAME 16
END_FUNCTION checkpoint_is

/* L0: checkpoint_is of the store's finalized checkpoint for node x1 of store x0. */
LOCAL_FUNCTION finalized_is_ancestor
    UNWIND_END_PROLOGUE
    ldr     x2, [x0, #(Store_finalized_checkpoint + Checkpoint_epoch)]
    add     x3, x0, #(Store_finalized_checkpoint + Checkpoint_root)
    b       checkpoint_is
END_FUNCTION finalized_is_ancestor

/*
 * L0: x0 = status, x1 = bls.Verify(public key x3, compute_signing_root(object x2 of type x1, domain x0), signature x4),
 * with scratch x5. Locals: sp+16 the root buffer (56: a ByteList header, then the root), sp+72 key, sp+80 signature,
 * sp+88 scratch.
 */
LOCAL_FUNCTION verify_with_domain
    FRAME 80
    stp     x3, x4, [sp, #72]
    str     x5, [sp, #88]
    mov     x9, x0
    mov     x0, x1
    mov     x1, x2
    mov     x2, x9
    mov     x3, x5
    add     x4, sp, #(16 + 24)
    bl      lantern_compute_signing_root
    cbnz    x0, 7f
    ldp     x0, x1, [sp, #72]
    add     x2, sp, #16
    ldr     x3, [sp, #88]
    bl      verify_root_signature
7:  UNFRAME 80
END_FUNCTION verify_with_domain

/*
 * L0: verify_with_domain with get_domain(state x0, domain type x1, epoch x2): object x4 of type x3,
 * public key x5, signature x6, scratch x7. Locals: sp+16 domain type, sp+24 epoch, sp+32 domain (32),
 * sp+64 type, object, key, signature, scratch.
 */
LOCAL_FUNCTION verify_signed
    FRAME 96
    str     w1, [sp, #16]
    str     x2, [sp, #24]
    stp     x3, x4, [sp, #64]
    stp     x5, x6, [sp, #80]
    str     x7, [sp, #96]
    add     x1, sp, #16
    add     x2, sp, #24
    mov     x3, x7
    add     x4, sp, #32
    bl      lantern_get_domain
    cbnz    x0, 7f
    add     x0, sp, #32
    ldp     x1, x2, [sp, #64]
    ldp     x3, x4, [sp, #80]
    ldr     x5, [sp, #96]
    bl      verify_with_domain
7:  UNFRAME 96
END_FUNCTION verify_signed

/* dst = &state.validators[idx] of state st; branch to fail when idx is not below the count. Uses x16, x17. */
.macro VALIDATOR_AT dst, st, idx, fail
    PART    \dst, x17, \st, BeaconState_validators
    cmp     \idx, x17
    b.hs    \fail
    add     \dst, \dst, \idx, lsl #7
.endm

/* ---------------------------------------------------------------- Gossip: operations */

/*
 * x19 seen, x20 store, x21 signed exit, x22 current_time_ms, x23 head state, x24 scratch, x25 result,
 * x26 validator, x27 validator index. Locals: L current epoch, L+8 predicate, L+16 domain type, L+24 domain (32).
 */
SPEC_FUNCTION validate_voluntary_exit_gossip
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x3]
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    str     xzr, [x25]
    NEED_SCRATCH x24, x23, 0, 9f
    ldr     x27, [x21, #(SignedVoluntaryExit_message + VoluntaryExit_validator_index)]
    mov     x0, x19                         /* [IGNORE] the first valid exit for the validator */
    mov     x1, #SEEN_VOLUNTARY_EXIT
    mov     x2, x27
    mov     x3, #0
    mov     x4, #0
    bl      seen_find_key
    cbnz    x0, 4f
    mov     x0, x20                         /* [IGNORE] the exit epoch is not in the future */
    ldr     x1, [x21, #(SignedVoluntaryExit_message + VoluntaryExit_epoch)]
    mov     x2, x22
    bl      is_future_epoch
    cbnz    x0, 4f
    VALIDATOR_AT x26, x23, x27, 5f          /* [REJECT] the validator index is valid */
    mov     x0, x23
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    ldr     x9, [x26, #Validator_exit_epoch]    /* [IGNORE] the validator has not initiated exit */
    cmn     x9, #1
    b.ne    4f
    mov     x0, x26                         /* [REJECT] the validator is active */
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    bl      lantern_is_active_validator
    ldr     x9, [sp, #(L + 8)]
    cbz     x9, 5f
    ldr     x9, [x26, #Validator_activation_epoch]  /* [REJECT] active for SHARD_COMMITTEE_PERIOD */
    LDQ     x10, x20, Store_config + CONFIG_SHARD_COMMITTEE_PERIOD
    adds    x9, x9, x10
    b.cs    3f
    ldr     x10, [sp, #L]
    cmp     x10, x9
    b.lo    5f
.if FORK >= FORK_DENEB
    mov     w9, #DOMAIN_VOLUNTARY_EXIT      /* [REJECT] the signature: compute_domain(DOMAIN_VOLUNTARY_EXIT, CAPELLA_FORK_VERSION, gvr) */
    str     w9, [sp, #(L + 16)]
    add     x0, sp, #(L + 16)
    ADDQ    x1, x20, Store_config + CONFIG_CAPELLA_FORK_VERSION
    ADDQ    x2, x23, BeaconState_genesis_validators_root
    mov     x3, x24
    add     x4, sp, #(L + 24)
    bl      lantern_compute_domain
    cbnz    x0, 7f
    add     x0, sp, #(L + 24)
    ADDRESS x1, lantern_type_VoluntaryExit
    add     x2, x21, #SignedVoluntaryExit_message
    add     x3, x26, #Validator_pubkey
    add     x4, x21, #SignedVoluntaryExit_signature
    mov     x5, x24
    bl      verify_with_domain
.else
    mov     x0, x23                         /* [REJECT] the signature: get_domain(state, DOMAIN_VOLUNTARY_EXIT, voluntary_exit.epoch) */
    mov     w1, #DOMAIN_VOLUNTARY_EXIT
    ldr     x2, [x21, #(SignedVoluntaryExit_message + VoluntaryExit_epoch)]
    ADDRESS x3, lantern_type_VoluntaryExit
    add     x4, x21, #SignedVoluntaryExit_message
    add     x5, x26, #Validator_pubkey
    add     x6, x21, #SignedVoluntaryExit_signature
    mov     x7, x24
    bl      verify_signed
.endif
    cbnz    x0, 7f
    cbz     x1, 5f
    mov     x0, x19                         /* seen.voluntary_exit_indices.add(validator_index) */
    bl      seen_key_room
    cbz     x0, 9f
    mov     x0, x19
    mov     x1, #SEEN_VOLUNTARY_EXIT
    mov     x2, x27
    mov     x3, #0
    mov     x4, #0
    bl      seen_add_key
    mov     x0, #LANTERN_OK
    b       7f
3:  mov     x0, #LANTERN_INVALID_OVERFLOW
    b       6f
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x25]
    mov     x0, #LANTERN_OK
7:  LEAVE 64
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
SPEC_END validate_voluntary_exit_gossip

/*
 * x19 seen, x20 store, x21 proposer slashing, x23 head state, x24 scratch, x25 result, x26 validator,
 * x27 proposer index, x28 signed header. Locals: L current epoch, L+8 predicate.
 */
SPEC_FUNCTION validate_proposer_slashing_gossip
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x23, x3
    mov     x24, x4
    mov     x25, x5
    str     xzr, [x25]
    NEED_SCRATCH x24, x23, 0, 9f
    ldr     x27, [x21, #(ProposerSlashing_signed_header_1 + SignedBeaconBlockHeader_message + BeaconBlockHeader_proposer_index)]
    mov     x0, x19                         /* [IGNORE] the first valid slashing for this proposer */
    mov     x1, #SEEN_PROPOSER_SLASHING
    mov     x2, x27
    mov     x3, #0
    mov     x4, #0
    bl      seen_find_key
    cbnz    x0, 4f
    add     x9, x21, #(ProposerSlashing_signed_header_1 + SignedBeaconBlockHeader_message)
    add     x10, x21, #(ProposerSlashing_signed_header_2 + SignedBeaconBlockHeader_message)
    ldr     x11, [x9, #BeaconBlockHeader_slot]  /* [REJECT] the header slots match */
    ldr     x12, [x10, #BeaconBlockHeader_slot]
    cmp     x11, x12
    b.ne    5f
    ldr     x11, [x9, #BeaconBlockHeader_proposer_index]    /* [REJECT] the proposer indices match */
    ldr     x12, [x10, #BeaconBlockHeader_proposer_index]
    cmp     x11, x12
    b.ne    5f
    mov     x11, #0                         /* [REJECT] the headers are different */
1:  cmp     x11, #BeaconBlockHeader__mem
    b.hs    5f
    ldr     x12, [x9, x11]
    ldr     x13, [x10, x11]
    cmp     x12, x13
    b.ne    2f
    add     x11, x11, #8
    b       1b
2:  VALIDATOR_AT x26, x23, x27, 5f          /* [REJECT] the proposer index is valid */
    mov     x0, x23
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    mov     x0, x26                         /* [REJECT] the proposer is slashable */
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    bl      lantern_is_slashable_validator
    ldr     x9, [sp, #(L + 8)]
    cbz     x9, 5f
    add     x28, x21, #ProposerSlashing_signed_header_1     /* [REJECT] the two signatures are valid */
21: mov     x0, x23
    mov     w1, #DOMAIN_BEACON_PROPOSER
    ldr     x2, [x28, #(SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)]
    lsr     x2, x2, #LOG2_SLOTS_PER_EPOCH
    ADDRESS x3, lantern_type_BeaconBlockHeader
    add     x4, x28, #SignedBeaconBlockHeader_message
    add     x5, x26, #Validator_pubkey
    add     x6, x28, #SignedBeaconBlockHeader_signature
    mov     x7, x24
    bl      verify_signed
    cbnz    x0, 7f
    cbz     x1, 5f
    add     x9, x21, #ProposerSlashing_signed_header_2
    cmp     x28, x9
    mov     x28, x9
    b.ne    21b
    mov     x0, x19                         /* seen.proposer_slashing_indices.add(proposer_index) */
    bl      seen_key_room
    cbz     x0, 9f
    mov     x0, x19
    mov     x1, #SEEN_PROPOSER_SLASHING
    mov     x2, x27
    mov     x3, #0
    mov     x4, #0
    bl      seen_add_key
    mov     x0, #LANTERN_OK
    b       7f
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x25]
    mov     x0, #LANTERN_OK
7:  LEAVE 16
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END validate_proposer_slashing_gossip

.if FORK >= FORK_CAPELLA
/*
 * x19 seen, x20 store, x21 signed change, x22 current_time_ms, x23 head state, x24 scratch, x25 result,
 * x26 validator, x27 validator index. Locals: L digest (32), L+32 domain type, L+40 domain (32).
 */
SPEC_FUNCTION validate_bls_to_execution_change_gossip
    ENTER 80
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x3]
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    str     xzr, [x25]
    NEED_SCRATCH x24, x23, 0, 9f
    ldr     x27, [x21, #(SignedBLSToExecutionChange_message + BLSToExecutionChange_validator_index)]
    mov     x0, x19                         /* [IGNORE] the first valid change for the validator */
    mov     x1, #SEEN_BLS_CHANGE
    mov     x2, x27
    mov     x3, #0
    mov     x4, #0
    bl      seen_find_key
    cbnz    x0, 4f
    mov     x0, x20                         /* [IGNORE] the current epoch is at or after CAPELLA_FORK_EPOCH */
    LDQ     x1, x20, Store_config + CONFIG_CAPELLA_FORK_EPOCH
    mov     x2, x22
    bl      is_future_epoch
    cbnz    x0, 4f
    VALIDATOR_AT x26, x23, x27, 5f          /* [REJECT] the validator index is valid */
    ldrb    w9, [x26, #Validator_withdrawal_credentials]    /* [REJECT] BLS withdrawal credentials */
    cmp     w9, #BLS_WITHDRAWAL_PREFIX
    b.ne    5f
    add     x0, x21, #(SignedBLSToExecutionChange_message + BLSToExecutionChange_from_bls_pubkey)
    mov     x1, #48
    add     x2, sp, #L
    bl      sha256_short                    /* [REJECT] withdrawal_credentials[1:] == sha256(pubkey)[1:] */
    mov     w9, #BLS_WITHDRAWAL_PREFIX
    strb    w9, [sp, #L]
    add     x14, x26, #Validator_withdrawal_credentials
    add     x15, sp, #L
    NE32    x14, x15, 5f
    mov     w9, #DOMAIN_BLS_TO_EXECUTION_CHANGE     /* [REJECT] the signature: compute_domain(type, GENESIS_FORK_VERSION, gvr) */
    str     w9, [sp, #(L + 32)]
    add     x0, sp, #(L + 32)
    ADDQ    x1, x20, Store_config + CONFIG_GENESIS_FORK_VERSION
    ADDQ    x2, x23, BeaconState_genesis_validators_root
    mov     x3, x24
    add     x4, sp, #(L + 40)
    bl      lantern_compute_domain
    cbnz    x0, 7f
    add     x0, sp, #(L + 40)
    ADDRESS x1, lantern_type_BLSToExecutionChange
    add     x2, x21, #SignedBLSToExecutionChange_message
    add     x3, x21, #(SignedBLSToExecutionChange_message + BLSToExecutionChange_from_bls_pubkey)
    add     x4, x21, #SignedBLSToExecutionChange_signature
    mov     x5, x24
    bl      verify_with_domain
    cbnz    x0, 7f
    cbz     x1, 5f
    mov     x0, x19                         /* seen.bls_to_execution_change_indices.add(validator_index) */
    bl      seen_key_room
    cbz     x0, 9f
    mov     x0, x19
    mov     x1, #SEEN_BLS_CHANGE
    mov     x2, x27
    mov     x3, #0
    mov     x4, #0
    bl      seen_add_key
    mov     x0, #LANTERN_OK
    b       7f
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x25]
    mov     x0, #LANTERN_OK
7:  LEAVE 80
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
SPEC_END validate_bls_to_execution_change_gossip
.endif

/*
 * L0: the block of the root at x2, from store x0 and seen x1: x0 = its node or NODE_NONE, x1 = 2 for a node
 * of the store, 1 for a block of seen, 0 when unknown, x2 = its payload status. Locals: store, seen, root.
 */
LOCAL_FUNCTION block_lookup
    FRAME 32
    stp     x0, x1, [sp, #16]
    str     x2, [sp, #32]
    mov     x1, x2
    bl      find_node
    cmn     x0, #1
    b.eq    1f
    ldr     x9, [sp, #16]
    NODE    x10, x9, x0
    ldr     x2, [x10, #BlockNode_payload_status]
    mov     x1, #2
    UNFRAME 32
1:  ldr     x0, [sp, #24]
    ldr     x1, [sp, #32]
    bl      seen_find_block
    cbz     x0, 2f
    ldr     x2, [x0, #SeenBlock_payload_status]
    mov     x0, #-1
    mov     x1, #1
    UNFRAME 32
2:  mov     x0, #-1
    mov     x1, #0
    mov     x2, #PAYLOAD_STATUS_NOT_VALIDATED
    UNFRAME 32
END_FUNCTION block_lookup

/* ---------------------------------------------------------------- Gossip: attestations */

.if FORK >= FORK_ELECTRA
/*
 * x19 seen, x20 store, x21 single attestation, x22 current_time_ms, x23 head state, x24 scratch, x25 result,
 * x26 subnet_id, x27 scratch size, x28 validator count.
 * Locals: L committees_per_slot, L+8 committee list, L+16 block node.
 */
SPEC_FUNCTION validate_beacon_attestation_gossip
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x3]
    ldr     x26, [x4]
    mov     x23, x5
    mov     x24, x6
    mov     x25, x7
    str     xzr, [x25]
    NEED_SCRATCH x24, x23, 3, 9f
    ldr     x27, [x24]
    LDQ     x28, x23, BeaconState_validators + 8
    mov     x0, x19                         /* [IGNORE] no attestation seen for (target epoch, attester) */
    mov     x1, #SEEN_ATTESTATION
    ldr     x2, [x21, #(SingleAttestation_data + AttestationData_target + Checkpoint_epoch)]
    ldr     x3, [x21, #SingleAttestation_attester_index]
    mov     x4, #0
    bl      seen_find_key
    cbnz    x0, 4f
    ldr     x9, [x21, #(SingleAttestation_data + AttestationData_index)]   /* [REJECT] data.index is zero */
    cbnz    x9, 5f
    mov     x0, x20                         /* [IGNORE] the block voted for has been seen; [REJECT] it passed validation */
    mov     x1, x19
    add     x2, x21, #(SingleAttestation_data + AttestationData_beacon_block_root)
    bl      block_lookup
    cbz     x1, 4f
    cmp     x1, #2
    b.ne    5f
    str     x0, [sp, #(L + 16)]
    str     x27, [x24]                      /* [REJECT] the committee index is in range */
    mov     x0, x23
    add     x1, x21, #(SingleAttestation_data + AttestationData_target + Checkpoint_epoch)
    mov     x3, x24
    add     x4, sp, #L
    ldr     x2, [x20, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      lantern_get_committee_count_per_slot
    CHECK_STATUS x25, 7f, 8f
    ldr     x9, [sp, #L]
    ldr     x10, [x21, #SingleAttestation_committee_index]
    cmp     x10, x9
    b.hs    5f
    ldr     x11, [x21, #(SingleAttestation_data + AttestationData_slot)]    /* [REJECT] the subnet: compute_subnet_for_attestation */
    and     x11, x11, #(SLOTS_PER_EPOCH - 1)
    madd    x11, x9, x11, x10
    and     x11, x11, #(ATTESTATION_SUBNET_COUNT - 1)
    cmp     x11, x26
    b.ne    5f
    mov     x0, x20                         /* [IGNORE] not from a future slot */
    ldr     x1, [x21, #(SingleAttestation_data + AttestationData_slot)]
    mov     x2, x22
    bl      is_future_slot
    cbnz    x0, 4f
    mov     x0, x20                         /* [IGNORE] the current or previous epoch */
    ldr     x1, [x21, #(SingleAttestation_data + AttestationData_slot)]
    lsr     x1, x1, #LOG2_SLOTS_PER_EPOCH
    mov     x2, x22
    bl      is_current_or_previous_epoch
    cbz     x0, 4f
    ldr     x9, [x21, #(SingleAttestation_data + AttestationData_slot)]    /* [REJECT] the epoch matches the target */
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    ldr     x10, [x21, #(SingleAttestation_data + AttestationData_target + Checkpoint_epoch)]
    cmp     x9, x10
    b.ne    5f
    SCRATCH_LIST x9, x24, x27, 0, x28       /* committee = get_beacon_committee(state, data.slot, committee_index) */
    str     x9, [sp, #(L + 8)]
    SCRATCH_GIVE x24, x27, 1, x28
    mov     x0, x23
    add     x1, x21, #(SingleAttestation_data + AttestationData_slot)
    add     x2, x21, #SingleAttestation_committee_index
    mov     x4, x24
    ldr     x5, [sp, #(L + 8)]
    ldr     x3, [x20, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      lantern_get_beacon_committee
    CHECK_STATUS x25, 7f, 8f
    ldr     x9, [sp, #(L + 8)]              /* [REJECT] the attester is in the committee */
    ldr     x10, [x9, #LIST_COUNT]
    add     x9, x9, #LIST_FIXED
    ldr     x11, [x21, #SingleAttestation_attester_index]
1:  cbz     x10, 5f
    ldr     x12, [x9], #8
    cmp     x12, x11
    b.eq    2f
    sub     x10, x10, #1
    b       1b
2:  VALIDATOR_AT x9, x23, x11, 5f           /* [REJECT] the signature */
    SCRATCH_GIVE x24, x27, 1, x28
    mov     x0, x23
    mov     w1, #DOMAIN_BEACON_ATTESTER
    ldr     x2, [x21, #(SingleAttestation_data + AttestationData_target + Checkpoint_epoch)]
    ADDRESS x3, lantern_type_AttestationData
    add     x4, x21, #SingleAttestation_data
    add     x5, x9, #Validator_pubkey
    add     x6, x21, #SingleAttestation_signature
    mov     x7, x24
    bl      verify_signed
    cbnz    x0, 7f
    cbz     x1, 5f
    mov     x0, x20                         /* [REJECT] the target block is an ancestor of the LMD vote block */
    ldr     x1, [sp, #(L + 16)]
    ldr     x2, [x21, #(SingleAttestation_data + AttestationData_target + Checkpoint_epoch)]
    add     x3, x21, #(SingleAttestation_data + AttestationData_target + Checkpoint_root)
    bl      checkpoint_is
    CHECK_STATUS x25, 7f, 8f
    cbz     x1, 5f
    mov     x0, x20                         /* [IGNORE] the finalized checkpoint is an ancestor of the block */
    ldr     x1, [sp, #(L + 16)]
    bl      finalized_is_ancestor
    CHECK_STATUS x25, 7f, 8f
    cbz     x1, 4f
    mov     x0, x19                         /* seen.attestation_validator_epochs.add(...) */
    bl      seen_key_room
    cbz     x0, 9f
    mov     x0, x19
    mov     x1, #SEEN_ATTESTATION
    ldr     x2, [x21, #(SingleAttestation_data + AttestationData_target + Checkpoint_epoch)]
    ldr     x3, [x21, #SingleAttestation_attester_index]
    mov     x4, #0
    bl      seen_add_key
    b       8f
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x25]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END validate_beacon_attestation_gossip
.else
/*
 * x19 seen, x20 store, x21 attestation, x22 current_time_ms, x23 head state, x24 scratch, x25 result,
 * x26 subnet_id, x27 scratch size, x28 validator count.
 * Locals: L committees_per_slot, L+8 committee list, L+16 block node, L+24 participant index, L+32 bit length.
 */
SPEC_FUNCTION validate_beacon_attestation_gossip
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x3]
    ldr     x26, [x4]
    mov     x23, x5
    mov     x24, x6
    mov     x25, x7
    str     xzr, [x25]
    NEED_SCRATCH x24, x23, 3, 9f
    ldr     x27, [x24]
    LDQ     x28, x23, BeaconState_validators + 8
    mov     x0, x20                         /* [IGNORE] the block voted for has been seen; [REJECT] it passed validation */
    mov     x1, x19
    add     x2, x21, #(Attestation_data + AttestationData_beacon_block_root)
    bl      block_lookup
    cbz     x1, 4f
    cmp     x1, #2
    b.ne    5f
    str     x0, [sp, #(L + 16)]
    str     x27, [x24]                      /* [REJECT] the committee index is in range */
    mov     x0, x23
    add     x1, x21, #(Attestation_data + AttestationData_target + Checkpoint_epoch)
    mov     x3, x24
    add     x4, sp, #L
    ldr     x2, [x20, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      lantern_get_committee_count_per_slot
    CHECK_STATUS x25, 7f, 8f
    ldr     x9, [sp, #L]
    ldr     x10, [x21, #(Attestation_data + AttestationData_index)]
    cmp     x10, x9
    b.hs    5f
    ldr     x11, [x21, #(Attestation_data + AttestationData_slot)]    /* [REJECT] the subnet: compute_subnet_for_attestation */
    and     x11, x11, #(SLOTS_PER_EPOCH - 1)
    madd    x11, x9, x11, x10
    and     x11, x11, #(ATTESTATION_SUBNET_COUNT - 1)
    cmp     x11, x26
    b.ne    5f
.if FORK >= FORK_DENEB
    mov     x0, x20                         /* [IGNORE] not from a future slot */
    ldr     x1, [x21, #(Attestation_data + AttestationData_slot)]
    mov     x2, x22
    bl      is_future_slot
    cbnz    x0, 4f
    mov     x0, x20                         /* [IGNORE] the current or previous epoch */
    ldr     x1, [x21, #(Attestation_data + AttestationData_slot)]
    lsr     x1, x1, #LOG2_SLOTS_PER_EPOCH
    mov     x2, x22
    bl      is_current_or_previous_epoch
    cbz     x0, 4f
.else
    mov     x0, x20                         /* [IGNORE] the slot is within ATTESTATION_PROPAGATION_SLOT_RANGE */
    ldr     x1, [x21, #(Attestation_data + AttestationData_slot)]
    LDQ     x2, x20, Store_config + CONFIG_ATTESTATION_PROPAGATION_SLOT_RANGE
    mov     x3, x22
    bl      is_within_slot_range
    cbz     x0, 4f
.endif
    ldr     x9, [x21, #(Attestation_data + AttestationData_slot)]    /* [REJECT] the epoch matches the target */
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    ldr     x10, [x21, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
    cmp     x9, x10
    b.ne    5f
    PART    x0, x9, x21, Attestation_aggregation_bits   /* [REJECT] unaggregated: exactly one bit set */
    str     x9, [sp, #(L + 32)]
    add     x1, sp, #(L + 32)
    add     x2, sp, #(L + 24)
    bl      lantern_get_set_bit_count
    ldr     x9, [sp, #(L + 24)]
    cmp     x9, #1
    b.ne    5f
    SCRATCH_LIST x9, x24, x27, 0, x28       /* committee = get_beacon_committee(state, data.slot, committee_index) */
    str     x9, [sp, #(L + 8)]
    SCRATCH_GIVE x24, x27, 1, x28
    mov     x0, x23
    add     x1, x21, #(Attestation_data + AttestationData_slot)
    add     x2, x21, #(Attestation_data + AttestationData_index)
    mov     x4, x24
    ldr     x5, [sp, #(L + 8)]
    ldr     x3, [x20, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      lantern_get_beacon_committee
    CHECK_STATUS x25, 7f, 8f
    ldr     x9, [sp, #(L + 8)]              /* [REJECT] len(aggregation_bits) == len(committee) */
    ldr     x10, [x9, #LIST_COUNT]
    ldr     x11, [sp, #(L + 32)]
    cmp     x10, x11
    b.ne    5f
    PART    x12, x13, x21, Attestation_aggregation_bits   /* participant_index: the committee member of the set bit */
    mov     x14, #0
1:  lsr     x15, x14, #3
    ldrb    w15, [x12, x15]
    and     x16, x14, #7
    lsr     w15, w15, w16
    tbnz    w15, #0, 2f
    add     x14, x14, #1
    b       1b
2:  add     x9, x9, #LIST_FIXED
    ldr     x11, [x9, x14, lsl #3]
    str     x11, [sp, #(L + 24)]
    mov     x0, x19                         /* [IGNORE] no attestation seen for (target epoch, participant) */
    mov     x1, #SEEN_ATTESTATION
    ldr     x2, [x21, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
    mov     x3, x11
    mov     x4, #0
    bl      seen_find_key
    cbnz    x0, 4f
    ldr     x11, [sp, #(L + 24)]            /* [REJECT] the signature: is_valid_indexed_attestation of the one attester */
    VALIDATOR_AT x9, x23, x11, 5f
    SCRATCH_GIVE x24, x27, 1, x28
    mov     x0, x23
    mov     w1, #DOMAIN_BEACON_ATTESTER
    ldr     x2, [x21, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
    ADDRESS x3, lantern_type_AttestationData
    add     x4, x21, #Attestation_data
    add     x5, x9, #Validator_pubkey
    add     x6, x21, #Attestation_signature
    mov     x7, x24
    bl      verify_signed
    cbnz    x0, 7f
    cbz     x1, 5f
    mov     x0, x20                         /* [REJECT] the target block is an ancestor of the LMD vote block */
    ldr     x1, [sp, #(L + 16)]
    ldr     x2, [x21, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
    add     x3, x21, #(Attestation_data + AttestationData_target + Checkpoint_root)
    bl      checkpoint_is
    CHECK_STATUS x25, 7f, 8f
    cbz     x1, 5f
    mov     x0, x20                         /* [IGNORE] the finalized checkpoint is an ancestor of the block */
    ldr     x1, [sp, #(L + 16)]
    bl      finalized_is_ancestor
    CHECK_STATUS x25, 7f, 8f
    cbz     x1, 4f
    mov     x0, x19                         /* seen.attestation_validator_epochs.add(...) */
    bl      seen_key_room
    cbz     x0, 9f
    mov     x0, x19
    mov     x1, #SEEN_ATTESTATION
    ldr     x2, [x21, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
    ldr     x3, [sp, #(L + 24)]
    mov     x4, #0
    bl      seen_add_key
    b       8f
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x25]
8:  mov     x0, #LANTERN_OK
7:  str     x27, [x24]
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END validate_beacon_attestation_gossip
.endif

/*
 * x19 seen, x20 store, x21 signed aggregate and proof, x22 current_time_ms, x23 head state, x24 scratch,
 * x25 result, x26 aggregate, x27 scratch size, x28 validator count.
 * Locals: L committee index, L+8 committee count, L+16 data root (32), L+48 block node, L+56 committee list,
 * L+64 attesting list, L+72 indexed attestation, L+80 front size, L+88 valid, L+96 digest (32),
 * L+128 aggregate and proof, L+136 target epoch.
 */
SPEC_FUNCTION validate_beacon_aggregate_and_proof_gossip
    ENTER 144
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x3]
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    str     xzr, [x25]
    NEED_SCRATCH_B x24, x23, 10, IndexedAttestation__fixed + 8, 9f
    ldr     x27, [x24]
    LDQ     x28, x23, BeaconState_validators + 8
    lsl     x11, x28, #3                    /* own scratch at the end: committee, attesting indices, indexed attestation */
    add     x11, x11, #LIST_FIXED           /* L(n) */
    sub     x10, x27, x11
    add     x9, x24, x10
    str     x11, [x9]
    str     x9, [sp, #(L + 56)]
    sub     x10, x10, x11
    add     x9, x24, x10
    str     x11, [x9]
    str     x9, [sp, #(L + 64)]
    MOVQ    x12, IndexedAttestation__fixed + 8
    add     x12, x12, x11
    sub     x10, x10, x12
    add     x9, x24, x10
    str     x12, [x9]
    str     x9, [sp, #(L + 72)]
    str     x10, [sp, #(L + 80)]
    str     x10, [x24]
    PART    x9, x10, x21, SignedAggregateAndProof_message
    str     x9, [sp, #(L + 128)]
    PART    x26, x10, x9, AggregateAndProof_aggregate
    ldr     x9, [x26, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
    str     x9, [sp, #(L + 136)]
.if FORK >= FORK_ELECTRA
    ldr     x9, [x26, #(Attestation_data + AttestationData_index)]     /* [REJECT] data.index is zero */
    cbnz    x9, 5f
    mov     x9, #0                          /* [REJECT] exactly one committee in committee_bits */
    mov     x10, #0
    add     x13, x26, #Attestation_committee_bits
1:  cmp     x9, #MAX_COMMITTEES_PER_SLOT
    b.hs    2f
    lsr     x11, x9, #3
    ldrb    w11, [x13, x11]
    and     x12, x9, #7
    lsr     w11, w11, w12
    tbz     w11, #0, 11f
    str     x9, [sp, #L]
    add     x10, x10, #1
11: add     x9, x9, #1
    b       1b
2:  cmp     x10, #1
    b.ne    5f
.else
    ldr     x9, [x26, #(Attestation_data + AttestationData_index)]     /* index = aggregate.data.index */
    str     x9, [sp, #L]
.endif
    ADDRESS x0, lantern_type_AttestationData    /* [IGNORE] no seen aggregate with a superset of the bits */
    add     x1, x26, #Attestation_data
    mov     x2, x24
    add     x3, sp, #(L + 16)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 80)]
    str     x9, [x24]
    PART    x5, x6, x26, Attestation_aggregation_bits
    mov     x0, x19
    mov     x1, #SEEN_AGGREGATE
    add     x2, sp, #(L + 16)
.if FORK >= FORK_ELECTRA
    ldr     x3, [sp, #L]                    /* the key: (data root, committee index) */
.else
    mov     x3, #0                          /* the key: the data root */
.endif
    mov     x4, #0
    bl      seen_superset
    cbnz    x0, 4f
    mov     x0, x19                         /* [IGNORE] the first valid aggregate for (target epoch, aggregator) */
    mov     x1, #SEEN_AGGREGATOR_EPOCH
    ldr     x2, [sp, #(L + 136)]
    ldr     x3, [sp, #(L + 128)]
    ldr     x3, [x3, #AggregateAndProof_aggregator_index]
    mov     x4, #0
    bl      seen_find_key
    cbnz    x0, 4f
    mov     x0, x20                         /* [IGNORE] the block voted for has been seen; [REJECT] it passed validation */
    mov     x1, x19
    add     x2, x26, #(Attestation_data + AttestationData_beacon_block_root)
    bl      block_lookup
    cbz     x1, 4f
    cmp     x1, #2
    b.ne    5f
    str     x0, [sp, #(L + 48)]
    mov     x0, x23                         /* [REJECT] the committee index is in range */
    add     x1, sp, #(L + 136)
    mov     x3, x24
    add     x4, sp, #(L + 8)
    ldr     x2, [x20, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      lantern_get_committee_count_per_slot
    CHECK_STATUS x25, 7f, 8f
    ldp     x9, x10, [sp, #L]
    cmp     x9, x10
    b.hs    5f
.if FORK >= FORK_DENEB
    mov     x0, x20                         /* [IGNORE] not from a future slot */
    ldr     x1, [x26, #(Attestation_data + AttestationData_slot)]
    mov     x2, x22
    bl      is_future_slot
    cbnz    x0, 4f
    mov     x0, x20                         /* [IGNORE] the current or previous epoch */
    ldr     x1, [x26, #(Attestation_data + AttestationData_slot)]
    lsr     x1, x1, #LOG2_SLOTS_PER_EPOCH
    mov     x2, x22
    bl      is_current_or_previous_epoch
    cbz     x0, 4f
.else
    mov     x0, x20                         /* [IGNORE] the slot is within ATTESTATION_PROPAGATION_SLOT_RANGE */
    ldr     x1, [x26, #(Attestation_data + AttestationData_slot)]
    LDQ     x2, x20, Store_config + CONFIG_ATTESTATION_PROPAGATION_SLOT_RANGE
    mov     x3, x22
    bl      is_within_slot_range
    cbz     x0, 4f
.endif
    ldr     x9, [x26, #(Attestation_data + AttestationData_slot)]  /* [REJECT] the epoch matches the target */
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    ldr     x10, [sp, #(L + 136)]
    cmp     x9, x10
    b.ne    5f
    ldr     x9, [sp, #(L + 80)]             /* committee = get_beacon_committee(state, data.slot, index) */
    str     x9, [x24]
    mov     x0, x23
    add     x1, x26, #(Attestation_data + AttestationData_slot)
    add     x2, sp, #L
    mov     x4, x24
    ldr     x5, [sp, #(L + 56)]
    ldr     x3, [x20, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      lantern_get_beacon_committee
    CHECK_STATUS x25, 7f, 8f
    ldr     x9, [sp, #(L + 56)]             /* [REJECT] len(aggregation_bits) == len(committee) */
    ldr     x9, [x9, #LIST_COUNT]
    LDQ     x10, x26, Attestation_aggregation_bits + 8
    cmp     x9, x10
    b.ne    5f
    ldr     x9, [sp, #(L + 80)]             /* [REJECT] the aggregate has participants: get_attesting_indices */
    str     x9, [x24]
    mov     x0, x23
    mov     x1, x26
    mov     x3, x24
    ldr     x4, [sp, #(L + 64)]
    ldr     x2, [x20, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      lantern_get_attesting_indices
    CHECK_STATUS x25, 7f, 8f
    ldr     x9, [sp, #(L + 64)]
    ldr     x9, [x9, #LIST_COUNT]
    cbz     x9, 5f
    ldr     x0, [sp, #(L + 128)]            /* [REJECT] is_aggregator(state, slot, index, selection_proof) */
    add     x0, x0, #AggregateAndProof_selection_proof
    mov     x1, #96
    add     x2, sp, #(L + 96)
    bl      sha256_short
    ldr     x9, [sp, #(L + 56)]
    ldr     x9, [x9, #LIST_COUNT]
    lsr     x9, x9, #4                      /* len(committee) // TARGET_AGGREGATORS_PER_COMMITTEE, at least 1 */
    cmp     x9, #1
    csinc   x9, x9, xzr, hs
    ldr     x10, [sp, #(L + 96)]
    udiv    x11, x10, x9
    msub    x11, x11, x9, x10
    cbnz    x11, 5f
    ldr     x9, [sp, #(L + 56)]             /* [REJECT] the aggregator is in the committee */
    ldr     x10, [x9, #LIST_COUNT]
    add     x9, x9, #LIST_FIXED
    ldr     x11, [sp, #(L + 128)]
    ldr     x11, [x11, #AggregateAndProof_aggregator_index]
21: cbz     x10, 5f
    ldr     x12, [x9], #8
    cmp     x12, x11
    b.eq    22f
    sub     x10, x10, #1
    b       21b
22: ldr     x9, [sp, #(L + 80)]             /* [REJECT] the selection proof signature */
    str     x9, [x24]
    VALIDATOR_AT x9, x23, x11, 5f
    str     x9, [sp, #(L + 88)]
    mov     x0, x23
    mov     w1, #DOMAIN_SELECTION_PROOF
    ldr     x2, [sp, #(L + 136)]
    ADDRESS x3, lantern_type_Uint64
    add     x4, x26, #(Attestation_data + AttestationData_slot)
    add     x5, x9, #Validator_pubkey
    ldr     x6, [sp, #(L + 128)]
    add     x6, x6, #AggregateAndProof_selection_proof
    mov     x7, x24
    bl      verify_signed
    cbnz    x0, 7f
    cbz     x1, 5f
    ldr     x9, [sp, #(L + 80)]             /* [REJECT] the aggregator signature */
    str     x9, [x24]
    mov     x0, x23
    mov     w1, #DOMAIN_AGGREGATE_AND_PROOF
    ldr     x2, [sp, #(L + 136)]
    ADDRESS x3, lantern_type_AggregateAndProof
    ldr     x4, [sp, #(L + 128)]
    ldr     x5, [sp, #(L + 88)]
    add     x5, x5, #Validator_pubkey
    add     x6, x21, #SignedAggregateAndProof_signature
    mov     x7, x24
    bl      verify_signed
    cbnz    x0, 7f
    cbz     x1, 5f
    ldr     x9, [sp, #(L + 80)]             /* [REJECT] the aggregate signature: is_valid_indexed_attestation(get_indexed_attestation) */
    str     x9, [x24]
    mov     x0, x23
    mov     x1, x26
    mov     x3, x24
    ldr     x4, [sp, #(L + 72)]
    ldr     x2, [x20, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      lantern_get_indexed_attestation
    CHECK_STATUS x25, 7f, 8f
    ldr     x9, [sp, #(L + 80)]
    str     x9, [x24]
    mov     x0, x23
    ldr     x1, [sp, #(L + 72)]
    mov     x3, x24
    add     x4, sp, #(L + 88)
    ldr     x2, [x20, #(Store_config + CONFIG_PUBKEY_CACHE)]
    mov     x5, x26                         /* with the aggregate and its CommitteeCache: key sums */
    ldr     x6, [x20, #(Store_config + CONFIG_COMMITTEE_CACHE)]
    bl      indexed_attestation_valid
    CHECK_STATUS x25, 7f, 8f
    ldr     x9, [sp, #(L + 88)]
    cbz     x9, 5f
    mov     x0, x20                         /* [REJECT] the target block is an ancestor of the LMD vote block */
    ldr     x1, [sp, #(L + 48)]
    ldr     x2, [sp, #(L + 136)]
    add     x3, x26, #(Attestation_data + AttestationData_target + Checkpoint_root)
    bl      checkpoint_is
    CHECK_STATUS x25, 7f, 8f
    cbz     x1, 5f
    mov     x0, x20                         /* [IGNORE] the finalized checkpoint is an ancestor of the block */
    ldr     x1, [sp, #(L + 48)]
    bl      finalized_is_ancestor
    CHECK_STATUS x25, 7f, 8f
    cbz     x1, 4f
    mov     x0, x19                         /* seen: the aggregator epoch and the bits of the data root */
    bl      seen_key_room
    cbz     x0, 9f
    mov     x0, x19
    bl      seen_bits_room
    cbz     x0, 9f
    mov     x0, x19
    mov     x1, #SEEN_AGGREGATOR_EPOCH
    ldr     x2, [sp, #(L + 136)]
    ldr     x3, [sp, #(L + 128)]
    ldr     x3, [x3, #AggregateAndProof_aggregator_index]
    mov     x4, #0
    bl      seen_add_key
    PART    x5, x6, x26, Attestation_aggregation_bits
    mov     x0, x19
    mov     x1, #SEEN_AGGREGATE
    add     x2, sp, #(L + 16)
.if FORK >= FORK_ELECTRA
    ldr     x3, [sp, #L]
.else
    mov     x3, #0
.endif
    mov     x4, #0
    bl      seen_add_bits
    b       8f
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x25]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 144
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
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
 * current epoch is that of the next slot's epoch, else next_sync_committee. Uses x9-x14, x16.
 */
.macro SYNC_COMMITTEE_OF dst, st
    LDQ     x9, \st, BeaconState_slot
    lsr     x10, x9, #LOG2_SLOTS_PER_EPOCH
    add     x11, x9, #1
    lsr     x11, x11, #LOG2_SLOTS_PER_EPOCH
    MOVQ    x12, EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    udiv    x10, x10, x12
    udiv    x11, x11, x12
    MOVQ    x13, BeaconState_current_sync_committee
    MOVQ    x14, BeaconState_next_sync_committee
    cmp     x10, x11
    csel    x13, x13, x14, eq
    add     \dst, \st, x13
.endm

/* Branch to label when the 48 bytes at a and b are equal. Uses x10-x13. */
.macro EQ48 a, b, label
    ldp     x10, x11, [\a]
    ldp     x12, x13, [\b]
    cmp     x10, x12
    ccmp    x11, x13, #0, eq
    b.ne    97f
    ldp     x10, x11, [\a, #16]
    ldp     x12, x13, [\b, #16]
    cmp     x10, x12
    ccmp    x11, x13, #0, eq
    b.ne    97f
    ldp     x10, x11, [\a, #32]
    ldp     x12, x13, [\b, #32]
    cmp     x10, x12
    ccmp    x11, x13, #0, eq
    b.eq    \label
97:
.endm

/*
 * x19 seen, x20 store, x21 message, x22 current_time_ms, x23 head state, x24 scratch, x25 result,
 * x26 subnet_id, x27 validator, x28 i.
 */
SPEC_FUNCTION validate_sync_committee_message_gossip
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x3]
    ldr     x26, [x4]
    mov     x23, x5
    mov     x24, x6
    mov     x25, x7
    str     xzr, [x25]
    NEED_SCRATCH x24, x23, 0, 9f
    mov     x0, x19                         /* [IGNORE] the first valid message for (slot, validator, subnet) */
    mov     x1, #SEEN_SYNC_MESSAGE
    ldr     x2, [x21, #SyncCommitteeMessage_slot]
    ldr     x3, [x21, #SyncCommitteeMessage_validator_index]
    mov     x4, x26
    bl      seen_find_key
    cbnz    x0, 4f
    mov     x0, x20                         /* [IGNORE] is_current_slot */
    ldr     x1, [x21, #SyncCommitteeMessage_slot]
    mov     x2, #0
    mov     x3, x22
    bl      is_within_slot_range
    cbz     x0, 4f
    ldr     x9, [x21, #SyncCommitteeMessage_validator_index]   /* [REJECT] the validator index is valid */
    VALIDATOR_AT x27, x23, x9, 5f
    SYNC_COMMITTEE_OF x15, x23              /* [REJECT] subnet_id in compute_subnets_for_sync_committee */
    add     x15, x15, #SyncCommittee_pubkeys
    add     x14, x27, #Validator_pubkey
    mov     x28, #0
1:  cmp     x28, #SYNC_COMMITTEE_SIZE
    b.hs    5f
    mov     x9, #48
    madd    x9, x28, x9, x15
    EQ48    x9, x14, 2f
    b       3f
2:  mov     x9, #SYNC_SUBCOMMITTEE_SIZE
    udiv    x9, x28, x9
    cmp     x9, x26
    b.eq    31f
3:  add     x28, x28, #1
    b       1b
31: mov     x0, x23                         /* [REJECT] the signature */
    mov     w1, #DOMAIN_SYNC_COMMITTEE
    ldr     x2, [x21, #SyncCommitteeMessage_slot]
    lsr     x2, x2, #LOG2_SLOTS_PER_EPOCH
    ADDRESS x3, lantern_type_Bytes32
    add     x4, x21, #SyncCommitteeMessage_beacon_block_root
    add     x5, x27, #Validator_pubkey
    add     x6, x21, #SyncCommitteeMessage_signature
    mov     x7, x24
    bl      verify_signed
    cbnz    x0, 7f
    cbz     x1, 5f
    mov     x0, x19                         /* seen.sync_message_validator_slots.add(...) */
    bl      seen_key_room
    cbz     x0, 9f
    mov     x0, x19
    mov     x1, #SEEN_SYNC_MESSAGE
    ldr     x2, [x21, #SyncCommitteeMessage_slot]
    ldr     x3, [x21, #SyncCommitteeMessage_validator_index]
    mov     x4, x26
    bl      seen_add_key
    b       8f
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x25]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END validate_sync_committee_message_gossip

/*
 * x19 seen, x20 store, x21 signed contribution and proof, x22 current_time_ms, x23 head state, x24 scratch,
 * x25 result, x26 contribution, x27 aggregator validator, x28 subcommittee pubkeys.
 * Locals: L selection data (16), L+16 digest (32), L+48 key list, L+56 front size, L+64 domain type,
 * L+72 epoch, L+80 domain (32), L+112 the signing root buffer (56), L+168 valid.
 */
SPEC_FUNCTION validate_sync_committee_contribution_and_proof_gossip
    ENTER 176
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x3]
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    str     xzr, [x25]
    NEED_SCRATCH_B x24, x23, 1, SYNC_SUB_KEYS, 9f
    ldr     x9, [x24]                       /* own scratch at the end: the participant keys */
    MOVQ    x10, SYNC_SUB_KEYS
    sub     x11, x9, x10
    add     x12, x24, x11
    str     x10, [x12]
    mov     x10, #24
    str     x10, [x12, #8]
    str     xzr, [x12, #16]
    str     x12, [sp, #(L + 48)]
    str     x11, [sp, #(L + 56)]
    str     x11, [x24]
    add     x26, x21, #(SignedContributionAndProof_message + ContributionAndProof_contribution)
    mov     x0, x19                         /* [IGNORE] no seen contribution with a superset of the bits */
    mov     x1, #SEEN_CONTRIBUTION
    add     x2, x26, #SyncCommitteeContribution_beacon_block_root
    ldr     x3, [x26, #SyncCommitteeContribution_slot]
    ldr     x4, [x26, #SyncCommitteeContribution_subcommittee_index]
    add     x5, x26, #SyncCommitteeContribution_aggregation_bits
    mov     x6, #SYNC_SUBCOMMITTEE_SIZE
    bl      seen_superset
    cbnz    x0, 4f
    mov     x0, x19                         /* [IGNORE] the first valid contribution of (slot, aggregator, subcommittee) */
    mov     x1, #SEEN_SYNC_CONTRIBUTION
    ldr     x2, [x26, #SyncCommitteeContribution_slot]
    ldr     x3, [x21, #(SignedContributionAndProof_message + ContributionAndProof_aggregator_index)]
    ldr     x4, [x26, #SyncCommitteeContribution_subcommittee_index]
    bl      seen_find_key
    cbnz    x0, 4f
    mov     x0, x20                         /* [IGNORE] is_current_slot */
    ldr     x1, [x26, #SyncCommitteeContribution_slot]
    mov     x2, #0
    mov     x3, x22
    bl      is_within_slot_range
    cbz     x0, 4f
    ldr     x9, [x26, #SyncCommitteeContribution_subcommittee_index]   /* [REJECT] the subcommittee index is in range */
    cmp     x9, #SYNC_COMMITTEE_SUBNET_COUNT
    b.hs    5f
    mov     x9, #0                          /* [REJECT] the contribution has participants */
    mov     x10, #0
1:  cmp     x9, #(SYNC_SUBCOMMITTEE_SIZE / 8)
    b.hs    2f
    add     x11, x26, #SyncCommitteeContribution_aggregation_bits
    ldrb    w11, [x11, x9]
    orr     x10, x10, x11
    add     x9, x9, #1
    b       1b
2:  cbz     x10, 5f
    add     x0, x21, #(SignedContributionAndProof_message + ContributionAndProof_selection_proof)
    mov     x1, #96                         /* [REJECT] is_sync_committee_aggregator(selection_proof) */
    add     x2, sp, #(L + 16)
    bl      sha256_short
    ldr     x9, [sp, #(L + 16)]
    mov     x10, #SYNC_AGGREGATOR_MODULO
    udiv    x11, x9, x10
    msub    x11, x11, x10, x9
    cbnz    x11, 5f
    ldr     x9, [x21, #(SignedContributionAndProof_message + ContributionAndProof_aggregator_index)]
    VALIDATOR_AT x27, x23, x9, 5f           /* [REJECT] the aggregator index is valid */
    SYNC_COMMITTEE_OF x28, x23              /* [REJECT] the aggregator is in get_sync_subcommittee_pubkeys */
    ldr     x9, [x26, #SyncCommitteeContribution_subcommittee_index]
    MOVQ    x10, 48 * SYNC_SUBCOMMITTEE_SIZE
    madd    x28, x9, x10, x28
    add     x28, x28, #SyncCommittee_pubkeys
    add     x14, x27, #Validator_pubkey
    mov     x15, #0
3:  cmp     x15, #SYNC_SUBCOMMITTEE_SIZE
    b.hs    5f
    mov     x9, #48
    madd    x9, x15, x9, x28
    EQ48    x9, x14, 31f
    add     x15, x15, #1
    b       3b
31: ldr     x9, [x26, #SyncCommitteeContribution_slot]  /* [REJECT] the selection proof signs SyncAggregatorSelectionData */
    ldr     x10, [x26, #SyncCommitteeContribution_subcommittee_index]
    stp     x9, x10, [sp, #L]
    mov     x0, x23
    mov     w1, #DOMAIN_SYNC_COMMITTEE_SELECTION_PROOF
    lsr     x2, x9, #LOG2_SLOTS_PER_EPOCH
    ADDRESS x3, lantern_type_SyncAggregatorSelectionData
    add     x4, sp, #L
    add     x5, x27, #Validator_pubkey
    add     x6, x21, #(SignedContributionAndProof_message + ContributionAndProof_selection_proof)
    mov     x7, x24
    bl      verify_signed
    cbnz    x0, 7f
    cbz     x1, 5f
    ldr     x9, [sp, #(L + 56)]             /* [REJECT] the aggregator signature */
    str     x9, [x24]
    mov     x0, x23
    mov     w1, #DOMAIN_CONTRIBUTION_AND_PROOF
    ldr     x2, [x26, #SyncCommitteeContribution_slot]
    lsr     x2, x2, #LOG2_SLOTS_PER_EPOCH
    ADDRESS x3, lantern_type_ContributionAndProof
    add     x4, x21, #SignedContributionAndProof_message
    add     x5, x27, #Validator_pubkey
    add     x6, x21, #SignedContributionAndProof_signature
    mov     x7, x24
    bl      verify_signed
    cbnz    x0, 7f
    cbz     x1, 5f
    mov     x22, #0                         /* participant_pubkeys: the keys of the set bits */
45: cmp     x22, #SYNC_SUBCOMMITTEE_SIZE
    b.hs    42f
    lsr     x9, x22, #3
    add     x10, x26, #SyncCommitteeContribution_aggregation_bits
    ldrb    w9, [x10, x9]
    and     x10, x22, #7
    lsr     w9, w9, w10
    tbz     w9, #0, 41f
    mov     x9, #48
    madd    x9, x22, x9, x28
    ldr     x12, [sp, #(L + 48)]
    KEYS_APPEND x12, x9
41: add     x22, x22, #1
    b       45b
42: mov     w9, #DOMAIN_SYNC_COMMITTEE      /* [REJECT] eth_fast_aggregate_verify over the beacon_block_root */
    str     w9, [sp, #(L + 64)]
    ldr     x9, [x26, #SyncCommitteeContribution_slot]
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    str     x9, [sp, #(L + 72)]
    ldr     x9, [sp, #(L + 56)]
    str     x9, [x24]
    mov     x0, x23
    add     x1, sp, #(L + 64)
    add     x2, sp, #(L + 72)
    mov     x3, x24
    add     x4, sp, #(L + 80)
    bl      lantern_get_domain
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 56)]
    str     x9, [x24]
    ADDRESS x0, lantern_type_Bytes32
    add     x1, x26, #SyncCommitteeContribution_beacon_block_root
    add     x2, sp, #(L + 80)
    mov     x3, x24
    add     x4, sp, #(L + 112 + 24)
    bl      lantern_compute_signing_root
    cbnz    x0, 7f
    mov     x9, #56
    str     x9, [sp, #(L + 112)]
    mov     x9, #24
    str     x9, [sp, #(L + 120)]
    mov     x9, #32
    str     x9, [sp, #(L + 128)]
    ldr     x9, [sp, #(L + 56)]
    str     x9, [x24]
    ldr     x0, [sp, #(L + 48)]
    add     x1, sp, #(L + 112)
    add     x2, x26, #SyncCommitteeContribution_signature
    mov     x3, x24
    add     x4, sp, #(L + 168)
    CALL_GLOBAL crypto_bls_eth_fast_aggregate_verify
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 168)]
    cbz     x9, 5f
    mov     x0, x19                         /* seen: the aggregator slot and the bits of the contribution */
    bl      seen_key_room
    cbz     x0, 9f
    mov     x0, x19
    bl      seen_bits_room
    cbz     x0, 9f
    mov     x0, x19
    mov     x1, #SEEN_SYNC_CONTRIBUTION
    ldr     x2, [x26, #SyncCommitteeContribution_slot]
    ldr     x3, [x21, #(SignedContributionAndProof_message + ContributionAndProof_aggregator_index)]
    ldr     x4, [x26, #SyncCommitteeContribution_subcommittee_index]
    bl      seen_add_key
    mov     x0, x19
    mov     x1, #SEEN_CONTRIBUTION
    add     x2, x26, #SyncCommitteeContribution_beacon_block_root
    ldr     x3, [x26, #SyncCommitteeContribution_slot]
    ldr     x4, [x26, #SyncCommitteeContribution_subcommittee_index]
    add     x5, x26, #SyncCommitteeContribution_aggregation_bits
    mov     x6, #SYNC_SUBCOMMITTEE_SIZE
    bl      seen_add_bits
    b       8f
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x25]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 176
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 176
SPEC_END validate_sync_committee_contribution_and_proof_gossip
.endif

/*
 * (state, validator_index, out) -> status: compute_subnets_for_sync_committee of the state for the
 * validator (altair validator.md), bit i of the u64 out for subnet i; 0 for an index past the
 * validators, and before altair.
 */
SPEC_LEAF node_sync_subnets
    str     xzr, [x2]
.if FORK >= FORK_ALTAIR
    SYNC_COMMITTEE_OF x15, x0
    add     x15, x15, #SyncCommittee_pubkeys
    VALIDATOR_AT x14, x0, x1, 9f
    add     x14, x14, #Validator_pubkey
    mov     x3, #0
    mov     x4, #0
1:  cmp     x4, #SYNC_COMMITTEE_SIZE
    b.hs    8f
    mov     x9, #48
    madd    x9, x4, x9, x15
    EQ48    x9, x14, 2f
    b       3f
2:  mov     x9, #SYNC_SUBCOMMITTEE_SIZE
    udiv    x9, x4, x9
    mov     x10, #1
    lsl     x10, x10, x9
    orr     x3, x3, x10
3:  add     x4, x4, #1
    b       1b
8:  str     x3, [x2]
.endif
9:  mov     x0, #LANTERN_OK
    ret
SPEC_END node_sync_subnets

/*
 * (state, validator_index, out) -> status: the places of the validator's public key in the sync
 * committee that compute_subnets_for_sync_committee reads (altair validator.md): bit p of the
 * SYNC_COMMITTEE_SIZE / 8 bytes at out for place p; none for an index past the validators, and
 * before altair.
 */
SPEC_LEAF node_sync_positions
    mov     x9, #0
1:  cmp     x9, #(SYNC_COMMITTEE_SIZE / 8)
    b.hs    2f
    strb    wzr, [x2, x9]
    add     x9, x9, #1
    b       1b
2:
.if FORK >= FORK_ALTAIR
    SYNC_COMMITTEE_OF x15, x0
    add     x15, x15, #SyncCommittee_pubkeys
    VALIDATOR_AT x14, x0, x1, 9f
    add     x14, x14, #Validator_pubkey
    mov     x4, #0
3:  cmp     x4, #SYNC_COMMITTEE_SIZE
    b.hs    9f
    mov     x9, #48
    madd    x9, x4, x9, x15
    EQ48    x9, x14, 4f
    b       5f
4:  lsr     x9, x4, #3
    and     x10, x4, #7
    mov     x11, #1
    lsl     x11, x11, x10
    ldrb    w10, [x2, x9]
    orr     w10, w10, w11
    strb    w10, [x2, x9]
5:  add     x4, x4, #1
    b       3b
.endif
9:  mov     x0, #LANTERN_OK
    ret
SPEC_END node_sync_positions

/* ---------------------------------------------------------------- Gossip: attester slashings */

/*
 * x19 seen, x20 store, x21 attester slashing, x22 i, x23 head state, x24 scratch, x25 result,
 * x26 attestation 1, x27 attestation 2, x28 intersection list.
 * Locals: L front size, L+8 list 1, L+16 list 2, L+24 new indices, L+32 current epoch, L+40 predicate.
 */
SPEC_FUNCTION validate_attester_slashing_gossip
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x23, x3
    mov     x24, x4
    mov     x25, x5
    str     xzr, [x25]
    PART    x26, x9, x21, AttesterSlashing_attestation_1
    PART    x27, x9, x21, AttesterSlashing_attestation_2
    LDQ     x9, x26, IndexedAttestation_attesting_indices + 8   /* own scratch at the end: two sorted copies, the intersection */
    LDQ     x10, x27, IndexedAttestation_attesting_indices + 8
    cmp     x9, x10
    csel    x11, x9, x10, lo
    add     x12, x9, x10
    add     x12, x12, x11
    lsl     x12, x12, #3
    add     x12, x12, #(3 * LIST_FIXED)     /* their bytes */
    LDQ     x13, x23, BeaconState_validators + 8
    lsl     x13, x13, #3
    add     x13, x13, #LIST_FIXED
    mov     x14, #7
    mul     x13, x13, x14
    MOVQ    x14, LANTERN_SCRATCH_FIXED
    add     x13, x13, x14                   /* S(7) for is_valid_indexed_attestation */
    add     x13, x13, x12
    ldr     x14, [x24]
    cmp     x14, x13
    b.lo    9f
    sub     x14, x14, x12
    str     x14, [sp, #L]
    add     x15, x24, x14                   /* list 1 */
    lsl     x13, x9, #3
    add     x13, x13, #LIST_FIXED
    str     x13, [x15]
    str     x15, [sp, #(L + 8)]
    add     x15, x15, x13                   /* list 2 */
    lsl     x13, x10, #3
    add     x13, x13, #LIST_FIXED
    str     x13, [x15]
    str     x15, [sp, #(L + 16)]
    add     x28, x15, x13                   /* the intersection */
    lsl     x13, x11, #3
    add     x13, x13, #LIST_FIXED
    str     x13, [x28]
    ldr     x0, [sp, #(L + 8)]              /* sorted copies of both attesting index lists */
    PART    x1, x2, x26, IndexedAttestation_attesting_indices
    str     x2, [x0, #LIST_COUNT]
    add     x0, x0, #LIST_FIXED
    lsl     x2, x2, #3
    bl      lantern_copy
    ldr     x0, [sp, #(L + 16)]
    PART    x1, x2, x27, IndexedAttestation_attesting_indices
    str     x2, [x0, #LIST_COUNT]
    add     x0, x0, #LIST_FIXED
    lsl     x2, x2, #3
    bl      lantern_copy
    ldr     x0, [sp, #(L + 8)]
    ldr     x1, [x0, #LIST_COUNT]
    add     x0, x0, #LIST_FIXED
    bl      sort_u64
    ldr     x0, [sp, #(L + 16)]
    ldr     x1, [x0, #LIST_COUNT]
    add     x0, x0, #LIST_FIXED
    bl      sort_u64
    ldr     x9, [sp, #(L + 8)]              /* slashable_indices = their intersection, each index once */
    ldr     x10, [x9, #LIST_COUNT]
    add     x9, x9, #LIST_FIXED
    ldr     x11, [sp, #(L + 16)]
    ldr     x12, [x11, #LIST_COUNT]
    add     x11, x11, #LIST_FIXED
    add     x13, x28, #LIST_FIXED
    mov     x14, #0                         /* its count */
1:  cbz     x10, 3f
    cbz     x12, 3f
    ldr     x15, [x9]
    ldr     x16, [x11]
    cmp     x15, x16
    b.lo    11f
    b.hi    12f
    cbz     x14, 13f
    sub     x17, x14, #1
    ldr     x17, [x13, x17, lsl #3]
    cmp     x17, x15
    b.eq    14f
13: str     x15, [x13, x14, lsl #3]
    add     x14, x14, #1
14: add     x9, x9, #8
    sub     x10, x10, #1
12: add     x11, x11, #8
    sub     x12, x12, #1
    b       1b
11: add     x9, x9, #8
    sub     x10, x10, #1
    b       1b
3:  str     x14, [x28, #LIST_COUNT]
    mov     x22, #0                         /* [IGNORE] an index of the intersection not yet seen */
    str     xzr, [sp, #(L + 24)]
2:  ldr     x9, [x28, #LIST_COUNT]
    cmp     x22, x9
    b.hs    21f
    mov     x0, x19
    mov     x1, #SEEN_ATTESTER_SLASHING
    add     x2, x28, #LIST_FIXED
    ldr     x2, [x2, x22, lsl #3]
    mov     x3, #0
    mov     x4, #0
    bl      seen_find_key
    ldr     x9, [sp, #(L + 24)]
    cmp     x0, #0
    cinc    x9, x9, eq
    str     x9, [sp, #(L + 24)]
    add     x22, x22, #1
    b       2b
21: ldr     x9, [sp, #(L + 24)]
    cbz     x9, 4f
    add     x0, x26, #IndexedAttestation_data   /* [REJECT] the data is slashable */
    add     x1, x27, #IndexedAttestation_data
    add     x2, sp, #(L + 40)
    bl      lantern_is_slashable_attestation_data
    ldr     x9, [sp, #(L + 40)]
    cbz     x9, 5f
    mov     x22, x26                        /* [REJECT] each attestation: valid indices, is_valid_indexed_attestation */
22: PART    x9, x10, x22, IndexedAttestation_attesting_indices
    LDQ     x11, x23, BeaconState_validators + 8
23: cbz     x10, 24f
    ldr     x12, [x9], #8
    cmp     x12, x11
    b.hs    5f
    sub     x10, x10, #1
    b       23b
24: ldr     x9, [sp, #L]
    str     x9, [x24]
    mov     x0, x23
    mov     x1, x22
    mov     x3, x24
    add     x4, sp, #(L + 40)
    ldr     x2, [x20, #(Store_config + CONFIG_PUBKEY_CACHE)]
    bl      lantern_is_valid_indexed_attestation
    CHECK_STATUS x25, 7f, 8f
    ldr     x9, [sp, #(L + 40)]
    cbz     x9, 5f
    cmp     x22, x27
    mov     x22, x27
    b.ne    22b
    mov     x0, x23                         /* [REJECT] a validator of the intersection is slashable */
    add     x1, sp, #(L + 32)
    bl      lantern_get_current_epoch
    mov     x22, #0
25: ldr     x9, [x28, #LIST_COUNT]
    cmp     x22, x9
    b.hs    5f
    add     x9, x28, #LIST_FIXED
    ldr     x9, [x9, x22, lsl #3]
    VALIDATOR_AT x0, x23, x9, 5f
    add     x1, sp, #(L + 32)
    add     x2, sp, #(L + 40)
    bl      lantern_is_slashable_validator
    ldr     x9, [sp, #(L + 40)]
    add     x22, x22, #1
    cbz     x9, 25b
    mov     x0, x19                         /* seen.attester_slashing_indices.update(slashable_indices) */
    bl      seen_key_room
    ldr     x9, [sp, #(L + 24)]
    cmp     x0, x9
    b.lo    9f
    mov     x22, #0
26: ldr     x9, [x28, #LIST_COUNT]
    cmp     x22, x9
    b.hs    8f
    mov     x0, x19
    mov     x1, #SEEN_ATTESTER_SLASHING
    add     x2, x28, #LIST_FIXED
    ldr     x2, [x2, x22, lsl #3]
    mov     x3, #0
    mov     x4, #0
    bl      seen_find_key
    cbnz    x0, 27f
    mov     x0, x19
    mov     x1, #SEEN_ATTESTER_SLASHING
    add     x2, x28, #LIST_FIXED
    ldr     x2, [x2, x22, lsl #3]
    mov     x3, #0
    mov     x4, #0
    bl      seen_add_key
27: add     x22, x22, #1
    b       26b
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x25]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END validate_attester_slashing_gossip

/* ---------------------------------------------------------------- Gossip: blocks and columns */

/*
 * x19 seen, x20 store, x21 signed block, x22 current_time_ms, x23 head state, x24 proposer state,
 * x25 scratch, x26 result, x27 block, x28 parent node.
 * Locals: L blob parameters (16), L+16 expected proposer, L+24 epoch, L+32 time, L+40 parent payload status,
 * L+48 a predicate, L+56 bellatrix: the justified checkpoint state.
 */
.macro BEACON_BLOCK_GOSSIP name, blinded, msg, sig, type, payload, timestamp, commitments
SPEC_FUNCTION \name
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x3]
    mov     x23, x4
    mov     x24, x5
.if FORK == FORK_BELLATRIX
    str     x6, [sp, #(L + 56)]             /* bellatrix: (seen, store, block, now, head, proposer, justified state, scratch, result) */
    mov     x25, x7
    ldr     x26, [sp, #(96 + 64)]           /* the ninth argument */
.else
    mov     x25, x6
    mov     x26, x7
.endif
    str     xzr, [x26]
.if FORK >= FORK_FULU
    NEED_SCRATCH x25, x23, 0, 9f
.else
    NEED_SCRATCH x25, x24, 2, 9f            /* get_beacon_proposer_index of the proposer state takes S(2) */
.endif
    PART    x27, x9, x21, \msg
    mov     x0, x19                         /* [IGNORE] the first block for (slot, proposer) */
    mov     x1, #SEEN_PROPOSER_SLOT
    ldr     x2, [x27, #BeaconBlock_slot]
    ldr     x3, [x27, #BeaconBlock_proposer_index]
    mov     x4, #0
    bl      seen_find_key
    cbnz    x0, 4f
    mov     x0, x20                         /* [IGNORE] not from a future slot */
    ldr     x1, [x27, #BeaconBlock_slot]
    mov     x2, x22
    bl      is_future_slot
    cbnz    x0, 4f
    mov     x0, x20                         /* [IGNORE] after the finalized slot */
    bl      finalized_slot
    ldr     x9, [x27, #BeaconBlock_slot]
    cmp     x9, x0
    b.ls    4f
    mov     x0, x20                         /* [IGNORE] the parent has been seen */
    mov     x1, x19
    add     x2, x27, #BeaconBlock_parent_root
    bl      block_lookup
    cbz     x1, 4f
    mov     x28, x0
    cmp     x1, #2
    b.eq    1f
.if FORK >= FORK_CAPELLA
    cmp     x2, #PAYLOAD_STATUS_NOT_VALIDATED   /* no post-state: [REJECT] with an optimistic payload, else [IGNORE] */
    b.eq    5f
    b       4f
.elseif FORK == FORK_BELLATRIX
    str     x2, [sp, #(L + 40)]
.if \blinded == 0
    ldr     x0, [sp, #(L + 56)]             /* no post-state: is_execution_enabled(justified checkpoint state, block.body) */
    PART    x1, x9, x27, BeaconBlock_body
    add     x2, sp, #(L + 48)
    bl      lantern_is_execution_enabled
    ldr     x9, [sp, #(L + 48)]
    cbz     x9, 5f                          /* [REJECT] the parent failed validation, execution not enabled */
.endif
    ldr     x2, [sp, #(L + 40)]
    cmp     x2, #PAYLOAD_STATUS_NOT_VALIDATED   /* [REJECT] with an optimistic payload, else [IGNORE] */
    b.eq    5f
    b       4f
.else
    b       5f                              /* [REJECT] the parent failed validation */
.endif
1:
.if FORK >= FORK_CAPELLA
    cmp     x2, #PAYLOAD_STATUS_INVALIDATED     /* [IGNORE] the parent's payload is invalid */
    b.eq    4f
.elseif FORK == FORK_BELLATRIX
    str     x2, [sp, #(L + 40)]             /* parent_payload_status, for the payload checks */
.endif
    ldr     x9, [x27, #BeaconBlock_proposer_index]  /* [REJECT] the proposer index is valid */
    VALIDATOR_AT x10, x23, x9, 5f
    mov     x0, x23                         /* [REJECT] the proposer signature */
    mov     w1, #DOMAIN_BEACON_PROPOSER
    ldr     x2, [x27, #BeaconBlock_slot]
    lsr     x2, x2, #LOG2_SLOTS_PER_EPOCH
    ADDRESS x3, \type
    mov     x4, x27
    add     x5, x10, #Validator_pubkey
    add     x6, x21, #\sig
    mov     x7, x25
    bl      verify_signed
    cbnz    x0, 7f
    cbz     x1, 5f
.if FORK == FORK_BELLATRIX && \blinded == 0
    mov     x0, x23                         /* if is_execution_enabled(state, block.body): */
    PART    x1, x9, x27, BeaconBlock_body
    add     x2, sp, #(L + 48)
    bl      lantern_is_execution_enabled
    ldr     x9, [sp, #(L + 48)]
    cbz     x9, 2f
.endif
.if FORK >= FORK_BELLATRIX
    ADDQ    x0, x23, BeaconState_genesis_time   /* [REJECT] the payload timestamp is compute_time_at_slot */
    add     x1, x27, #BeaconBlock_slot
    add     x2, x20, #Store_config
    add     x3, sp, #(L + 32)
    bl      lantern_compute_time_at_slot
    CHECK_STATUS x26, 7f, 8f
    PART    x9, x10, x27, BeaconBlock_body
    PART    x11, x10, x9, \payload
    ldr     x11, [x11, #\timestamp]
    ldr     x12, [sp, #(L + 32)]
    cmp     x11, x12
    b.ne    5f
.endif
.if FORK == FORK_BELLATRIX
    ldr     x2, [sp, #(L + 40)]             /* [IGNORE] the parent passed validation but its payload is invalid */
    cmp     x2, #PAYLOAD_STATUS_INVALIDATED
    b.eq    4f
2:
.endif
    NODE    x9, x20, x28                    /* [REJECT] a higher slot than the parent */
    ldr     x9, [x9, #BlockNode_slot]
    ldr     x10, [x27, #BeaconBlock_slot]
    cmp     x10, x9
    b.ls    5f
    mov     x0, x20                         /* [REJECT] the finalized checkpoint is an ancestor */
    mov     x1, x28
    bl      finalized_is_ancestor
    CHECK_STATUS x26, 7f, 8f
    cbz     x1, 5f
.if FORK >= FORK_FULU
    ldr     x9, [x27, #BeaconBlock_slot]    /* [REJECT] at most max_blobs_per_block commitments */
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    str     x9, [sp, #(L + 24)]
    add     x0, sp, #(L + 24)
    add     x1, x20, #Store_config
    add     x2, sp, #L
    bl      lantern_get_blob_parameters
    ldr     x11, [sp, #(L + 8)]
.elseif FORK == FORK_ELECTRA
    LDQ     x11, x20, Store_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA     /* [REJECT] at most MAX_BLOBS_PER_BLOCK_ELECTRA commitments */
.elseif FORK == FORK_DENEB
    LDQ     x11, x20, Store_config + CONFIG_MAX_BLOBS_PER_BLOCK             /* [REJECT] at most MAX_BLOBS_PER_BLOCK commitments */
.endif
.if FORK >= FORK_DENEB
    PART    x9, x10, x27, BeaconBlock_body
    LDQ     x10, x9, \commitments + 8
    cmp     x10, x11
    b.hi    5f
.endif
    mov     x0, x24                         /* [REJECT] the expected proposer of the parent state at the slot */
.if FORK >= FORK_FULU
    add     x1, sp, #(L + 16)
.else
    mov     x1, x25
    add     x2, sp, #(L + 16)
.endif
    bl      lantern_get_beacon_proposer_index
    CHECK_STATUS x26, 7f, 8f
    ldr     x9, [sp, #(L + 16)]
    ldr     x10, [x27, #BeaconBlock_proposer_index]
    cmp     x9, x10
    b.ne    5f
    mov     x0, x19                         /* seen.proposer_slots.add(...) */
    bl      seen_key_room
    cbz     x0, 9f
    mov     x0, x19
    mov     x1, #SEEN_PROPOSER_SLOT
    ldr     x2, [x27, #BeaconBlock_slot]
    ldr     x3, [x27, #BeaconBlock_proposer_index]
    mov     x4, #0
    bl      seen_add_key
    b       8f
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x26]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 64
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
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
    mov     x0, #LANTERN_INVALID_EVENT
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
    ldr     x9, [x1, #CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT]
    cbz     x9, 9f
    ldr     x10, [x0]
    udiv    x11, x10, x9
    msub    x11, x11, x9, x10
    str     x11, [x2]
    RETURN_OK
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_subnet_for_data_column_sidecar

/*
 * L0: x0 = status, x1 = is_valid_merkle_branch(hash_tree_root of the x2 commitments at x1, the branch at x3,
 * KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH, BLOB_KZG_COMMITMENTS_SUBTREE_INDEX, the root at x4), with scratch x0.
 * The list is hashed from a standalone copy at the end of scratch.
 * x19 scratch, x20 branch, x21 root, x22 i. Locals: L value (32), L+32 the two halves (64).
 */
LOCAL_FUNCTION commitments_in_body
    ENTER 96
    mov     x19, x0
    mov     x20, x3
    mov     x21, x4
    mov     x9, #48                         /* the list: size, offset 24, count, the commitments */
    mul     x9, x2, x9
    add     x9, x9, #LIST_FIXED
    add     x9, x9, #7
    and     x9, x9, #-8
    MOVQ    x10, LANTERN_SCRATCH_FIXED
    add     x10, x10, x9
    ldr     x11, [x19]
    cmp     x11, x10
    b.lo    9f
    sub     x11, x11, x9
    add     x12, x19, x11
    str     x11, [x19]                      /* asm-ssz's scratch: the front */
    str     x9, [x12]
    mov     x10, #LIST_FIXED
    stp     x10, x2, [x12, #8]
    add     x0, x12, #LIST_FIXED
    str     x12, [sp, #(L + 32)]
    mov     x9, #48
    mul     x2, x2, x9
    bl      lantern_copy
    ADDRESS x0, lantern_type_BlobKZGCommitments     /* value = hash_tree_root(kzg_commitments) */
    ldr     x1, [sp, #(L + 32)]
    mov     x2, x19
    add     x3, sp, #L
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    mov     x22, #0
1:  cmp     x22, #KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH
    b.hs    3f
    add     x9, x20, x22, lsl #5            /* branch[i] */
    mov     x10, #BLOB_KZG_COMMITMENTS_SUBTREE_INDEX
    lsr     x10, x10, x22
    add     x11, sp, #(L + 32)
    add     x12, sp, #L
    tbz     x10, #0, 2f
    COPY32  x11, x9                         /* index bit set: hash(branch[i] + value) */
    add     x11, x11, #32
    COPY32  x11, x12
    b       21f
2:  COPY32  x11, x12                        /* else hash(value + branch[i]) */
    add     x11, x11, #32
    COPY32  x11, x9
21: add     x0, sp, #(L + 32)
    mov     x1, #64
    add     x2, sp, #L
    bl      sha256_short
    add     x22, x22, #1
    b       1b
3:  add     x14, sp, #L                     /* value == root */
    mov     x1, #0
    NE32    x14, x21, 6f
    mov     x1, #1
6:  mov     x0, #LANTERN_OK
7:  LEAVE 96
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 96
END_FUNCTION commitments_in_body

/* Locals: sp+16 out. */
SPEC_FUNCTION verify_data_column_sidecar_inclusion_proof
    FRAME 16
    str     x2, [sp, #16]
    str     xzr, [x2]
    mov     x9, x0
    mov     x0, x1
    PART    x1, x2, x9, DataColumnSidecar_kzg_commitments
    add     x3, x9, #DataColumnSidecar_kzg_commitments_inclusion_proof
    add     x4, x9, #(DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_body_root)
    bl      commitments_in_body
    cbnz    x0, 7f
    ldr     x9, [sp, #16]
    str     x1, [x9]
7:  UNFRAME 16
SPEC_END verify_data_column_sidecar_inclusion_proof

/* Locals: sp+16 out. */
SPEC_FUNCTION verify_partial_data_column_header_inclusion_proof
    FRAME 16
    str     x2, [sp, #16]
    str     xzr, [x2]
    mov     x9, x0
    mov     x0, x1
    PART    x1, x2, x9, PartialDataColumnHeader_kzg_commitments
    add     x3, x9, #PartialDataColumnHeader_kzg_commitments_inclusion_proof
    add     x4, x9, #(PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_body_root)
    bl      commitments_in_body
    cbnz    x0, 7f
    ldr     x9, [sp, #16]
    str     x1, [x9]
7:  UNFRAME 16
SPEC_END verify_partial_data_column_header_inclusion_proof

/* dst = the set bits of the BitList at PartRef ref of value v. Uses x9-x13. */
.macro BIT_COUNT dst, v, ref
    PART    x9, x10, \v, \ref
    mov     \dst, #0
    mov     x11, #0
96: cmp     x11, x10
    b.hs    97f
    lsr     x12, x11, #3
    ldrb    w12, [x9, x12]
    and     x13, x11, #7
    lsr     w12, w12, w13
    and     x12, x12, #1
    add     \dst, \dst, x12
    add     x11, x11, #1
    b       96b
97:
.endm

/*
 * x19 sidecar, x20 settings, x21 scratch, x22 out, x23 n, x24 commitments, x25 cell indices,
 * x26 cells, x27 proofs, x28 scratch size left. Locals: L valid, L+8 header, L+16 column index.
 */
SPEC_FUNCTION verify_partial_data_column_sidecar_kzg_proofs
    ENTER 32
    mov     x19, x0
    str     x1, [sp, #(L + 8)]
    ldr     x9, [x2]
    str     x9, [sp, #(L + 16)]
    mov     x20, x3
    mov     x21, x4
    mov     x22, x5
    str     xzr, [x22]
    BIT_COUNT x23, x19, PartialDataColumnSidecar_cells_present_bitmap  /* blob_indices: the set bits */
    LDQ     x9, x19, PartialDataColumnSidecar_partial_column + 8   /* one cell and one proof per index, as the batch asserts */
    cmp     x9, x23
    b.ne    8f
    LDQ     x9, x19, PartialDataColumnSidecar_kzg_proofs + 8
    cmp     x9, x23
    b.ne    8f
    MOVQ    x9, DA_SCRATCH_PER_BLOB
    umulh   x10, x23, x9
    cbnz    x10, 9f
    mul     x9, x23, x9
    MOVQ    x10, DA_SCRATCH_FIXED
    adds    x9, x9, x10
    b.cs    9f
    ldr     x28, [x21]
    cmp     x28, x9
    b.lo    9f
    DA_LIST x24, 48                         /* commitments_bytes = [all_commitments[index] for index in blob_indices] */
    DA_LIST x25, 8                          /* cell_indices = [column_index] * len(blob_indices) */
    DA_LIST x26, CRYPTO_KZG_CELL_SIZE       /* cells = sidecar.partial_column */
    DA_LIST x27, 48                         /* proofs_bytes = sidecar.kzg_proofs */
    ldr     x9, [sp, #(L + 8)]
    PART    x13, x14, x9, PartialDataColumnHeader_kzg_commitments
    PART    x9, x10, x19, PartialDataColumnSidecar_cells_present_bitmap
    add     x15, x24, #LIST_FIXED
    mov     x11, #0
1:  cmp     x11, x10
    b.hs    2f
    lsr     x12, x11, #3
    ldrb    w12, [x9, x12]
    and     x16, x11, #7
    lsr     w12, w12, w16
    tbz     w12, #0, 11f
    cmp     x11, x14                        /* an index past the commitments: the spec's indexing raises */
    b.hs    8f
    mov     x12, #48
    madd    x12, x11, x12, x13
    ldp     x16, x17, [x12]
    stp     x16, x17, [x15]
    ldp     x16, x17, [x12, #16]
    stp     x16, x17, [x15, #16]
    ldp     x16, x17, [x12, #32]
    stp     x16, x17, [x15, #32]
    add     x15, x15, #48
11: add     x11, x11, #1
    b       1b
2:  ldr     x9, [sp, #(L + 16)]
    add     x10, x25, #LIST_FIXED
    mov     x11, x23
3:  cbz     x11, 4f
    str     x9, [x10], #8
    sub     x11, x11, #1
    b       3b
4:  add     x0, x26, #LIST_FIXED
    PART    x1, x2, x19, PartialDataColumnSidecar_partial_column
    lsl     x2, x2, #11
    bl      lantern_copy
    add     x0, x27, #LIST_FIXED
    PART    x1, x2, x19, PartialDataColumnSidecar_kzg_proofs
    mov     x9, #48
    mul     x2, x2, x9
    bl      lantern_copy
    str     x28, [x21]                      /* asm-crypto's scratch: the front */
    mov     x0, x20
    mov     x1, x24
    mov     x2, x25
    mov     x3, x26
    mov     x4, x27
    mov     x5, x21
    add     x6, sp, #L
    CALL_GLOBAL crypto_kzg_verify_cell_kzg_proof_batch
    cmp     x0, #CRYPTO_BUFFER_TOO_SMALL
    b.eq    9f
    cbnz    x0, 8f                          /* an input that does not decode: the spec raises */
    ldr     x9, [sp, #L]
    str     x9, [x22]
8:  mov     x0, #LANTERN_OK
    LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END verify_partial_data_column_sidecar_kzg_proofs

.endif

.if FORK >= FORK_DENEB
/*
 * L0: the checks of a block header shared by the sidecar topics, from is_future_slot to the finalized ancestor:
 * x0 = status, x1 = LANTERN_VALID, LANTERN_GOSSIP_IGNORE or LANTERN_GOSSIP_REJECT, x2 = the parent node.
 * Takes x19 seen, x20 store, x22 current_time_ms, x23 head state, x25 scratch, and x0 the SignedBeaconBlockHeader.
 * x19-x28 are the caller's and stay unchanged. Locals: sp+16 header, sp+24 parent node.
 */
LOCAL_FUNCTION header_checks
    FRAME 16
    str     x0, [sp, #16]
    mov     x0, x20                         /* [IGNORE] not from a future slot */
    ldr     x9, [sp, #16]
    ldr     x1, [x9, #(SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)]
    mov     x2, x22
    bl      is_future_slot
    cbnz    x0, 4f
    mov     x0, x20                         /* [IGNORE] after the finalized slot */
    bl      finalized_slot
    ldr     x9, [sp, #16]
    ldr     x9, [x9, #(SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)]
    cmp     x9, x0
    b.ls    4f
    mov     x0, x20                         /* [IGNORE] the parent has been seen; [REJECT] it passed validation */
    mov     x1, x19
    ldr     x2, [sp, #16]
    add     x2, x2, #(SignedBeaconBlockHeader_message + BeaconBlockHeader_parent_root)
    bl      block_lookup
    cbz     x1, 4f
    cmp     x1, #2
    b.ne    5f
    str     x0, [sp, #24]
    ldr     x9, [sp, #16]                   /* [REJECT] the proposer index is valid */
    ldr     x9, [x9, #(SignedBeaconBlockHeader_message + BeaconBlockHeader_proposer_index)]
    VALIDATOR_AT x10, x23, x9, 5f
    mov     x0, x23                         /* [REJECT] the proposer signature of the header */
    mov     w1, #DOMAIN_BEACON_PROPOSER
    ldr     x4, [sp, #16]
    ldr     x2, [x4, #(SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)]
    lsr     x2, x2, #LOG2_SLOTS_PER_EPOCH
    ADDRESS x3, lantern_type_BeaconBlockHeader
    add     x5, x10, #Validator_pubkey
    add     x6, x4, #SignedBeaconBlockHeader_signature
    add     x4, x4, #SignedBeaconBlockHeader_message
    mov     x7, x25
    bl      verify_signed
    cbnz    x0, 7f
    cbz     x1, 5f
    ldr     x9, [sp, #24]                   /* [REJECT] a higher slot than the parent */
    NODE    x9, x20, x9
    ldr     x9, [x9, #BlockNode_slot]
    ldr     x10, [sp, #16]
    ldr     x10, [x10, #(SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)]
    cmp     x10, x9
    b.ls    5f
    mov     x0, x20                         /* [REJECT] the finalized checkpoint is an ancestor */
    ldr     x1, [sp, #24]
    bl      finalized_is_ancestor
    cbnz    x0, 6f
    cbz     x1, 5f
    mov     x1, #LANTERN_VALID
    b       8f
4:  mov     x1, #LANTERN_GOSSIP_IGNORE
    b       8f
5:  mov     x1, #LANTERN_GOSSIP_REJECT
8:  ldr     x2, [sp, #24]
    mov     x0, #LANTERN_OK
7:  UNFRAME 16
6:  cmp     x0, #LANTERN_BUFFER_TOO_SMALL   /* a spec failure: its code as the outcome */
    b.eq    7b
    mov     x1, x0
    b       8b
END_FUNCTION header_checks
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
    LDQ     x4, x1, BLOB_SUBNETS
    cbz     x4, 9f
    ldr     x3, [x0]
    udiv    x5, x3, x4
    msub    x5, x5, x4, x3
    str     x5, [x2]
    RETURN_OK
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
SPEC_END compute_subnet_for_blob_sidecar

/*
 * (sidecar, out): is_valid_merkle_branch of hash_tree_root(kzg_commitment) at the subtree index of
 * blob_kzg_commitments[index] against the header's body_root. x19 sidecar, x20 out.
 * Locals: L the commitment as two chunks (64), L+64 its root (32), L+96 depth, L+104 index.
 */
SPEC_FUNCTION verify_blob_sidecar_inclusion_proof
    ENTER 112
    mov     x19, x0
    mov     x20, x1
    add     x0, sp, #L
    mov     x1, #64
    bl      lantern_zero
    add     x0, sp, #L
    ADDQ    x1, x19, BlobSidecar_kzg_commitment
    mov     x2, #48
    bl      lantern_copy
    add     x0, sp, #L                      /* hash_tree_root(Bytes48): its two chunks */
    mov     x1, #64
    add     x2, sp, #(L + 64)
    bl      sha256_short
    mov     x9, #KZG_COMMITMENT_INCLUSION_PROOF_DEPTH
    str     x9, [sp, #(L + 96)]
    ldr     x9, [x19, #BlobSidecar_index]   /* field 11 of the body, the list's data root, then the index */
    MOVQ    x10, 11 << (KZG_COMMITMENT_INCLUSION_PROOF_DEPTH - 4)
    add     x9, x9, x10
    str     x9, [sp, #(L + 104)]
    add     x0, sp, #(L + 64)
    ADDQ    x1, x19, BlobSidecar_kzg_commitment_inclusion_proof
    add     x2, sp, #(L + 96)
    add     x3, sp, #(L + 104)
    ADDQ    x4, x19, BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_body_root
    mov     x5, x20
    bl      lantern_is_valid_merkle_branch
    LEAVE 112
SPEC_END verify_blob_sidecar_inclusion_proof
.if (1 << (KZG_COMMITMENT_INCLUSION_PROOF_DEPTH - 5)) != MAX_BLOB_COMMITMENTS_PER_BLOCK
.error "verify_blob_sidecar_inclusion_proof assumes a body of 16 leaves and a list of MAX_BLOB_COMMITMENTS_PER_BLOCK"
.endif

/*
 * x19 seen, x20 store, x21 sidecar, x22 current_time_ms, x23 head state, x24 proposer state, x25 scratch,
 * x26 result, x27 the block header, x28 scratch size.
 * Locals: L subnet_id, L+8 settings, L+16 out, L+24 expected proposer.
 */
SPEC_FUNCTION validate_blob_sidecar_gossip
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x3]
    ldr     x9, [x4]
    str     x9, [sp, #L]
    mov     x23, x5
    mov     x24, x6
    str     x7, [sp, #(L + 8)]
    ldr     x25, [sp, #(96 + 32)]           /* the ninth and tenth arguments */
    ldr     x26, [sp, #(96 + 32 + 8)]
    str     xzr, [x26]
    NEED_SCRATCH x25, x24, 2, 9f            /* get_beacon_proposer_index of the proposer state takes S(2) */
    ldr     x28, [x25]
    ADDQ    x27, x21, BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message
    mov     x0, x19                         /* [IGNORE] the first sidecar for (slot, proposer, index) */
    mov     x1, #SEEN_BLOB_SIDECAR
    ldr     x2, [x27, #BeaconBlockHeader_slot]
    ldr     x3, [x27, #BeaconBlockHeader_proposer_index]
    ldr     x4, [x21, #BlobSidecar_index]
    bl      seen_find_key
    cbnz    x0, 4f
    ldr     x9, [x21, #BlobSidecar_index]   /* [REJECT] the index is below the blob limit */
    LDQ     x10, x20, Store_config + BLOB_LIMIT
    cmp     x9, x10
    b.hs    5f
    add     x0, x21, #BlobSidecar_index     /* [REJECT] the subnet: compute_subnet_for_blob_sidecar */
    add     x1, x20, #Store_config
    add     x2, sp, #(L + 16)
    bl      lantern_compute_subnet_for_blob_sidecar
    CHECK_STATUS x26, 7f, 8f
    ldr     x9, [sp, #L]
    ldr     x10, [sp, #(L + 16)]
    cmp     x9, x10
    b.ne    5f
    ADDQ    x0, x21, BlobSidecar_signed_block_header    /* the header checks, through the finalized ancestor */
    bl      header_checks
    cbnz    x0, 7f
    cbz     x1, 1f
    mov     x0, x1
    b       6f
1:  mov     x0, x21                         /* [REJECT] verify_blob_sidecar_inclusion_proof */
    add     x1, sp, #(L + 16)
    bl      lantern_verify_blob_sidecar_inclusion_proof
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 5f
    str     x28, [x25]                      /* [REJECT] verify_blob_kzg_proof(blob, kzg_commitment, kzg_proof) */
    ldr     x0, [sp, #(L + 8)]
    ADDQ    x1, x21, BlobSidecar_blob
    ADDQ    x2, x21, BlobSidecar_kzg_commitment
    ADDQ    x3, x21, BlobSidecar_kzg_proof
    mov     x4, x25
    add     x5, sp, #(L + 16)
    CALL_GLOBAL crypto_kzg_verify_blob_kzg_proof
    cmp     x0, #CRYPTO_BUFFER_TOO_SMALL
    b.eq    9f
    cbnz    x0, 5f                          /* an input that does not decode: the spec's exception */
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 5f
    str     x28, [x25]                      /* [REJECT] the expected proposer of the parent state at the slot */
    mov     x0, x24
    mov     x1, x25
    add     x2, sp, #(L + 24)
    bl      lantern_get_beacon_proposer_index
    CHECK_STATUS x26, 7f, 8f
    ldr     x9, [sp, #(L + 24)]
    ldr     x10, [x27, #BeaconBlockHeader_proposer_index]
    cmp     x9, x10
    b.ne    5f
    mov     x0, x19                         /* seen.blob_sidecar_tuples.add(...) */
    bl      seen_key_room
    cbz     x0, 9f
    mov     x0, x19
    mov     x1, #SEEN_BLOB_SIDECAR
    ldr     x2, [x27, #BeaconBlockHeader_slot]
    ldr     x3, [x27, #BeaconBlockHeader_proposer_index]
    ldr     x4, [x21, #BlobSidecar_index]
    bl      seen_add_key
    b       8f
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x26]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END validate_blob_sidecar_gossip
.endif

.if FORK >= FORK_FULU

/*
 * x19 seen, x20 store, x21 sidecar, x22 current_time_ms, x23 head state, x24 proposer state, x25 scratch,
 * x26 result, x27 the block header, x28 parent node.
 * Locals: L subnet_id, L+8 settings, L+16 out, L+24 expected proposer.
 */
SPEC_FUNCTION validate_data_column_sidecar_gossip
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x3]
    ldr     x9, [x4]
    str     x9, [sp, #L]
    mov     x23, x5
    mov     x24, x6
    str     x7, [sp, #(L + 8)]
    ldr     x25, [sp, #(96 + 32)]           /* the ninth and tenth arguments */
    ldr     x26, [sp, #(96 + 32 + 8)]
    str     xzr, [x26]
    NEED_SCRATCH x25, x23, 0, 9f
    add     x27, x21, #(DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message)
    mov     x0, x19                         /* [IGNORE] the first sidecar for (slot, proposer, index) */
    mov     x1, #SEEN_DATA_COLUMN
    ldr     x2, [x27, #BeaconBlockHeader_slot]
    ldr     x3, [x27, #BeaconBlockHeader_proposer_index]
    ldr     x4, [x21, #DataColumnSidecar_index]
    bl      seen_find_key
    cbnz    x0, 4f
    mov     x0, x21                         /* [REJECT] verify_data_column_sidecar */
    add     x1, x20, #Store_config
    add     x2, sp, #(L + 16)
    bl      lantern_verify_data_column_sidecar
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 5f
    add     x0, x21, #DataColumnSidecar_index   /* [REJECT] the subnet: compute_subnet_for_data_column_sidecar */
    add     x1, x20, #Store_config
    add     x2, sp, #(L + 16)
    bl      lantern_compute_subnet_for_data_column_sidecar
    CHECK_STATUS x26, 7f, 8f
    ldp     x9, x10, [sp, #L]
    ldr     x10, [sp, #(L + 16)]
    cmp     x9, x10
    b.ne    5f
    add     x0, x21, #DataColumnSidecar_signed_block_header     /* the header checks, through the finalized ancestor */
    bl      header_checks
    cbnz    x0, 7f
    mov     x28, x2
    cbz     x1, 1f
    mov     x0, x1
    b       6f
1:  mov     x0, x21                         /* [REJECT] verify_data_column_sidecar_inclusion_proof */
    mov     x1, x25
    add     x2, sp, #(L + 16)
    bl      lantern_verify_data_column_sidecar_inclusion_proof
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 5f
    mov     x0, x21                         /* [REJECT] verify_data_column_sidecar_kzg_proofs */
    ldr     x1, [sp, #(L + 8)]
    mov     x2, x25
    add     x3, sp, #(L + 16)
    bl      lantern_verify_data_column_sidecar_kzg_proofs
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 5f
    mov     x0, x24                         /* [REJECT] the expected proposer of the parent state at the slot */
    add     x1, sp, #(L + 24)
    bl      lantern_get_beacon_proposer_index
    CHECK_STATUS x26, 7f, 8f
    ldr     x9, [sp, #(L + 24)]
    ldr     x10, [x27, #BeaconBlockHeader_proposer_index]
    cmp     x9, x10
    b.ne    5f
    mov     x0, x19                         /* seen.data_column_sidecar_tuples.add(...) */
    bl      seen_key_room
    cbz     x0, 9f
    mov     x0, x19
    mov     x1, #SEEN_DATA_COLUMN
    ldr     x2, [x27, #BeaconBlockHeader_slot]
    ldr     x3, [x27, #BeaconBlockHeader_proposer_index]
    ldr     x4, [x21, #DataColumnSidecar_index]
    bl      seen_add_key
    b       8f
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x26]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END validate_data_column_sidecar_gossip

/*
 * x19 seen, x20 store, x21 sidecar, x22 current_time_ms, x23 head state, x24 proposer state, x25 scratch,
 * x26 result, x27 the header value, or 0, x28 the cells present.
 * Locals: L group_id, L+8 column_index, L+16 settings, L+24 out, L+32 header root (32),
 * L+64 expected proposer, L+72 the block header root (32).
 */
SPEC_FUNCTION validate_partial_data_column_sidecar_gossip
    ENTER 112
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x3]
    str     x4, [sp, #L]
    ldr     x9, [x5]
    str     x9, [sp, #(L + 8)]
    mov     x23, x6
    mov     x24, x7
    ldr     x9, [sp, #(96 + 112)]           /* the ninth to eleventh arguments */
    str     x9, [sp, #(L + 16)]
    ldr     x25, [sp, #(96 + 112 + 8)]
    ldr     x26, [sp, #(96 + 112 + 16)]
    str     xzr, [x26]
    NEED_SCRATCH x25, x23, 0, 9f
    mov     x27, #0                         /* has_header: the optional header holds one */
    LDQ     x9, x21, PartialDataColumnSidecar_header + 8
    cbz     x9, 1f
    LDQ     x27, x21, PartialDataColumnSidecar_header
    add     x27, x21, x27
1:  BIT_COUNT x28, x21, PartialDataColumnSidecar_cells_present_bitmap
    orr     x9, x28, x27                    /* [REJECT] a header and/or cells are present */
    cbz     x9, 5f
    LDQ     x9, x21, PartialDataColumnSidecar_partial_column + 8   /* [REJECT] one cell per set bit */
    cmp     x9, x28
    b.ne    5f
    LDQ     x9, x21, PartialDataColumnSidecar_kzg_proofs + 8   /* [REJECT] one proof per set bit */
    cmp     x9, x28
    b.ne    5f
    cbz     x27, 3f
    ADDRESS x0, lantern_type_PartialDataColumnHeader    /* [REJECT] the header equals a prior validated header */
    mov     x1, x27
    mov     x2, x25
    add     x3, sp, #(L + 32)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    mov     x0, x19
    ldr     x1, [sp, #L]
    bl      seen_find_header
    cbz     x0, 2f
    add     x14, x0, #SeenHeader_header_root
    add     x15, sp, #(L + 32)
    NE32    x14, x15, 5f
2:  ADDRESS x0, lantern_type_BeaconBlockHeader          /* [REJECT] the block header's root is the group id */
    add     x1, x27, #(PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message)
    mov     x2, x25
    add     x3, sp, #(L + 72)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    add     x14, sp, #(L + 72)
    ldr     x15, [sp, #L]
    NE32    x14, x15, 5f
    LDQ     x9, x27, PartialDataColumnHeader_kzg_commitments + 8   /* [REJECT] the header has commitments */
    cbz     x9, 5f
    add     x0, x27, #PartialDataColumnHeader_signed_block_header  /* the header checks, through the finalized ancestor */
    bl      header_checks
    cbnz    x0, 7f
    cbz     x1, 21f
    mov     x0, x1
    b       6f
21: mov     x0, x27                         /* [REJECT] verify_partial_data_column_header_inclusion_proof */
    mov     x1, x25
    add     x2, sp, #(L + 24)
    bl      lantern_verify_partial_data_column_header_inclusion_proof
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 24)]
    cbz     x9, 5f
    mov     x0, x24                         /* [REJECT] the expected proposer of the parent state at the slot */
    add     x1, sp, #(L + 64)
    bl      lantern_get_beacon_proposer_index
    CHECK_STATUS x26, 7f, 8f
    ldr     x9, [sp, #(L + 64)]
    ldr     x10, [x27, #(PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_proposer_index)]
    cmp     x9, x10
    b.ne    5f
    mov     x0, x19                         /* seen.partial_data_column_headers[group_id.beacon_block_root] = header */
    ldr     x1, [sp, #L]
    bl      seen_find_header
    cbnz    x0, 3f
    ldr     x9, [x27]                       /* room for 64 + the header value */
    add     x9, x9, #SeenHeader_header
    ldr     x10, [x19]
    ldr     x11, [x19, #Seen_headers]
    sub     x10, x10, x11
    ldr     x12, [x19, #Seen_header_bytes]
    sub     x10, x10, x12
    cmp     x10, x9
    b.lo    9f
    add     x13, x11, x12
    add     x13, x19, x13
    add     x12, x12, x9
    str     x12, [x19, #Seen_header_bytes]
    ldr     x12, [x19, #(Seen_headers + 8)]
    add     x12, x12, #1
    str     x12, [x19, #(Seen_headers + 8)]
    ldr     x14, [sp, #L]
    COPY32  x13, x14
    add     x14, x13, #SeenHeader_header_root
    add     x15, sp, #(L + 32)
    COPY32  x14, x15
    add     x0, x13, #SeenHeader_header
    mov     x1, x27
    ldr     x2, [x27]
    bl      lantern_copy
3:  cbz     x28, 8f                         /* has_cells */
    mov     x0, x19                         /* [IGNORE] a valid header for the group has been seen */
    ldr     x1, [sp, #L]
    bl      seen_find_header
    cbz     x0, 4f
    add     x27, x0, #SeenHeader_header
    mov     x0, x20                         /* [IGNORE] its slot is not in the future */
    ldr     x1, [x27, #(PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)]
    mov     x2, x22
    bl      is_future_slot
    cbnz    x0, 4f
    mov     x0, x20                         /* [IGNORE] its slot is after the finalized slot */
    bl      finalized_slot
    ldr     x9, [x27, #(PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)]
    cmp     x9, x0
    b.ls    4f
    LDQ     x9, x21, PartialDataColumnSidecar_cells_present_bitmap + 8     /* [REJECT] one bit per commitment */
    LDQ     x10, x27, PartialDataColumnHeader_kzg_commitments + 8
    cmp     x9, x10
    b.ne    5f
    mov     x0, x21                         /* [REJECT] verify_partial_data_column_sidecar_kzg_proofs */
    mov     x1, x27
    add     x2, sp, #(L + 8)
    ldr     x3, [sp, #(L + 16)]
    mov     x4, x25
    add     x5, sp, #(L + 24)
    bl      lantern_verify_partial_data_column_sidecar_kzg_proofs
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 24)]
    cbz     x9, 5f
    b       8f
4:  mov     x0, #LANTERN_GOSSIP_IGNORE
    b       6f
5:  mov     x0, #LANTERN_GOSSIP_REJECT
6:  str     x0, [x26]
8:  mov     x0, #LANTERN_OK
7:  LEAVE 112
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 112
SPEC_END validate_partial_data_column_sidecar_gossip
.endif
