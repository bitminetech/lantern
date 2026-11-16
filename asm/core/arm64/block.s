/*
 * Block processing: the header, RANDAO, eth1 data and small helpers, ARM64.
 * Requirements: docs/reference/block-processing.md.
 */

LEAF lantern_get_beacon_proposer_index
    LDQ     x2, x0, BeaconState_slot
    and     x2, x2, #(SLOTS_PER_EPOCH - 1)
    ADDQ    x3, x0, BeaconState_proposer_lookahead
    ldr     x2, [x3, x2, lsl #3]
    str     x2, [x1]
    RETURN_OK
END_FUNCTION lantern_get_beacon_proposer_index

LEAF lantern_xor
    ldp     x3, x4, [x0]
    ldp     x5, x6, [x1]
    eor     x3, x3, x5
    eor     x4, x4, x6
    stp     x3, x4, [x2]
    ldp     x3, x4, [x0, #16]
    ldp     x5, x6, [x1, #16]
    eor     x3, x3, x5
    eor     x4, x4, x6
    stp     x3, x4, [x2, #16]
    RETURN_OK
END_FUNCTION lantern_xor

/* bits x0, length x1 (pointer to the bit count), out x2. */
LEAF lantern_get_set_bit_count
    ldr     x1, [x1]
    mov     x3, #0                          /* count */
    mov     x4, #0                          /* bit */
1:  cmp     x4, x1
    b.hs    2f
    lsr     x5, x4, #3
    ldrb    w5, [x0, x5]
    and     x6, x4, #7
    lsr     w5, w5, w6
    and     x5, x5, #1
    add     x3, x3, x5
    add     x4, x4, #1
    b       1b
2:  str     x3, [x2]
    RETURN_OK
END_FUNCTION lantern_get_set_bit_count

/*
 * x19 state, x20 block, x21 scratch, x22 result, x23 body.
 * Locals: L proposer index, L+8 latest header root, L+40 body root.
 */
FUNCTION lantern_process_block_header
    ENTER 80
    mov     x19, x0
    mov     x20, x1
    mov     x21, x3
    mov     x22, x4
    ldr     x9, [x20, #BeaconBlock_slot]
    LDQ     x10, x19, BeaconState_slot
    cmp     x9, x10                         /* assert block.slot == state.slot */
    mov     x0, #LANTERN_INVALID_BLOCK_SLOT
    b.ne    6f
    LDQ     x10, x19, BeaconState_latest_block_header + BeaconBlockHeader_slot
    cmp     x9, x10                         /* assert block.slot > state.latest_block_header.slot */
    mov     x0, #LANTERN_INVALID_BLOCK_OLDER
    b.ls    6f
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_beacon_proposer_index
    ldr     x9, [x20, #BeaconBlock_proposer_index]
    ldr     x10, [sp, #L]
    cmp     x9, x10                         /* assert block.proposer_index == get_beacon_proposer_index(state) */
    mov     x0, #LANTERN_INVALID_PROPOSER_INDEX
    b.ne    6f
    ADDRESS x0, lantern_type_BeaconBlockHeader
    ADDQ    x1, x19, BeaconState_latest_block_header
    mov     x2, x21
    add     x3, sp, #(L + 8)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    ldp     x9, x10, [x20, #BeaconBlock_parent_root]   /* assert block.parent_root == hash_tree_root(latest header) */
    ldp     x11, x12, [sp, #(L + 8)]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    1f
    ldp     x9, x10, [x20, #(BeaconBlock_parent_root + 16)]
    ldp     x11, x12, [sp, #(L + 24)]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.eq    2f
1:  mov     x0, #LANTERN_INVALID_PARENT_ROOT
    b       6f
2:  PART    x23, x9, x20, BeaconBlock_body
    ADDRESS x0, lantern_type_BeaconBlockBody
    mov     x1, x23
    mov     x2, x21
    add     x3, sp, #(L + 40)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    ADDQ    x9, x19, BeaconState_latest_block_header   /* the new latest_block_header */
    ldr     x10, [x20, #BeaconBlock_slot]
    str     x10, [x9, #BeaconBlockHeader_slot]
    ldr     x10, [x20, #BeaconBlock_proposer_index]
    str     x10, [x9, #BeaconBlockHeader_proposer_index]
    add     x10, x9, #BeaconBlockHeader_parent_root
    add     x11, x20, #BeaconBlock_parent_root
    COPY32  x10, x11
    stp     xzr, xzr, [x9, #BeaconBlockHeader_state_root]
    stp     xzr, xzr, [x9, #(BeaconBlockHeader_state_root + 16)]
    add     x10, x9, #BeaconBlockHeader_body_root
    add     x11, sp, #(L + 40)
    COPY32  x10, x11
    ldr     x9, [x20, #BeaconBlock_proposer_index]      /* assert not proposer.slashed */
    PART    x10, x11, x19, BeaconState_validators
    cmp     x9, x11
    mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    b.hs    6f
    add     x10, x10, x9, lsl #7
    ldrb    w10, [x10, #Validator_slashed]
    mov     x0, #LANTERN_INVALID_PROPOSER_SLASHED
    cbnz    w10, 6f
    str     xzr, [x22]
    mov     x0, #LANTERN_OK
7:  LEAVE 80
6:  str     x0, [x22]
    mov     x0, #LANTERN_OK
    LEAVE 80
END_FUNCTION lantern_process_block_header
