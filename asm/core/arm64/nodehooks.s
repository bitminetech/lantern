/*
 * The node's work on one fork, ARM64: decode SSZ bytes with the fork's types, then call the
 * fork's fork choice functions. lantern_node_run (node.s, in the common object) calls these
 * exports for the fork of the block or message. Requirements: docs/reference/node.md.
 */

/* The node reads the slot of a state of any fork at NODE_STATE_SLOT. */
.if BeaconState_slot - NODE_STATE_SLOT
.error "BeaconState_slot is not NODE_STATE_SLOT"
.endif
.if BeaconState_current_justified_checkpoint - BeaconState_previous_justified_checkpoint - 40 || BeaconState_finalized_checkpoint - BeaconState_current_justified_checkpoint - 40
.error "the checkpoints of BeaconState do not follow each other"
.endif
.if BeaconState_latest_block_header - NODE_STATE_HEADER || BeaconBlock_state_root - NODE_BLOCK_STATE_ROOT
.error "BeaconState_latest_block_header or BeaconBlock_state_root is not the common offset"
.endif
.if BeaconState_genesis_validators_root - NODE_STATE_GVR
.error "BeaconState_genesis_validators_root is not NODE_STATE_GVR"
.endif

/*
 * L0: decode the ByteList x1 as the type x0 into the end of the scratch x2, whose size field
 * then shrinks by the value's room: x0 = 0, 1 (scratch too small) or 2 (not an encoding of
 * the type); x1 = the value. The caller restores the size field. Locals: L the size.
 */
LOCAL_FUNCTION node_decode
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    add     x3, sp, #L
    CALL_GLOBAL ssz_deserialize_size
    cbz     x0, 1f
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    8f
    b       9f
1:  ldr     x22, [sp, #L]                   /* the value at the end of scratch */
    add     x23, x22, #7
    and     x23, x23, #~7
    ldr     x24, [x21]
    add     x9, x23, #8
    cmp     x24, x9
    b.lo    8f
    sub     x24, x24, x23
    add     x25, x21, x24
    str     x22, [x25]
    str     x24, [x21]
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    mov     x3, x25
    CALL_GLOBAL ssz_deserialize
    cbz     x0, 2f
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    8f
    b       9f
2:  mov     x1, x25
    mov     x0, #0
    LEAVE 16
8:  mov     x0, #1
    LEAVE 16
9:  mov     x0, #2
    LEAVE 16
END_FUNCTION node_decode

.if FORK == FORK_BELLATRIX
/* L0: x0 = the PowBlock of the node x0 whose block_hash is the 32 bytes at x1, or 0. Uses x9-x13. */
LOCAL_FUNCTION node_pow_block
    UNWIND_END_PROLOGUE
    PART    x9, x10, x0, Node_pow_blocks
1:  cbz     x10, 3f
    ldp     x11, x12, [x9, #PowBlock_block_hash]
    ldp     x13, x14, [x1]
    cmp     x11, x13
    ccmp    x12, x14, #0, eq
    b.ne    2f
    ldp     x11, x12, [x9, #(PowBlock_block_hash + 16)]
    ldp     x13, x14, [x1, #16]
    cmp     x11, x13
    ccmp    x12, x14, #0, eq
    b.ne    2f
    mov     x0, x9
    ret
2:  add     x9, x9, #POW_BLOCK_BYTES
    sub     x10, x10, #1
    b       1b
3:  mov     x0, #0
    ret
END_FUNCTION node_pow_block
.endif

/*
 * (store, node, data, state, options, scratch, result): on_block of the SignedBeaconBlock in
 * data. Bellatrix: the pow_block and pow_parent of options from the PowBlocks of the node.
 */
SPEC_FUNCTION node_import
    ENTER 0
    mov     x19, x0
    mov     x25, x1
    mov     x20, x2
    mov     x21, x3
    mov     x22, x4
    mov     x23, x5
    mov     x24, x6
    ldr     x28, [x23]                      /* the scratch size, restored on return */
    str     xzr, [x24]
    ADDRESS x0, lantern_type_SignedBeaconBlock
    mov     x1, x20
    mov     x2, x23
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    9f
    mov     x20, x1
.if FORK == FORK_BELLATRIX
    PART    x9, x10, x20, SignedBeaconBlock_message      /* get_pow_block(payload.parent_hash) and its parent */
    PART    x11, x10, x9, BeaconBlock_body
    PART    x9, x10, x11, BeaconBlockBody_execution_payload
    mov     x0, x25
    add     x1, x9, #ExecutionPayload_parent_hash
    bl      node_pow_block
    str     x0, [x22, #BlockOptions_pow_block]
    mov     x1, x0
    cbz     x1, 1f
    mov     x0, x25
    add     x1, x1, #PowBlock_parent_hash
    bl      node_pow_block
1:  str     x0, [x22, #BlockOptions_pow_parent]
.endif
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    mov     x3, x22
    mov     x4, x23
    mov     x5, x24
    bl      lantern_on_block
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       99f
9:  mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x24]
    mov     x0, #LANTERN_OK
99: str     x28, [x23]
    LEAVE 0
SPEC_END node_import

/*
 * (data, scratch, root, result, blobs): hash_tree_root of the message of the SignedBeaconBlock in
 * data, and the length of its body's blob_kzg_commitments (0 before deneb).
 */
SPEC_FUNCTION node_block_root
    ENTER 0
    mov     x20, x0
    mov     x21, x1
    mov     x22, x2
    mov     x23, x3
    mov     x25, x4
    ldr     x28, [x21]                      /* the scratch size, restored on return */
    str     xzr, [x23]
    str     xzr, [x25]
    ADDRESS x0, lantern_type_SignedBeaconBlock
    mov     x1, x20
    mov     x2, x21
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    9f
    mov     x24, x1
    PART    x1, x9, x24, SignedBeaconBlock_message
.if FORK >= FORK_DENEB
    PART    x9, x10, x1, BeaconBlock_body
    LDQ     x10, x9, BeaconBlockBody_blob_kzg_commitments + 8
    str     x10, [x25]
.endif
    ADDRESS x0, lantern_type_BeaconBlock
    mov     x2, x21
    mov     x3, x22
    CALL_GLOBAL ssz_hash_tree_root
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    8f
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       99f
9:  mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x23]
    mov     x0, #LANTERN_OK
99: str     x28, [x21]
    LEAVE 0
SPEC_END node_block_root

/*
 * (data, scratch, out): the SignedBeaconBlockHeader of the SignedBeaconBlock in data: the message's
 * slot, proposer_index, parent_root, state_root, hash_tree_root of its body, and the signature.
 * x20 data, x21 scratch, x22 out, x24 the block, x25 its message, x28 the scratch size, restored.
 */
SPEC_FUNCTION node_block_header
    ENTER 0
    mov     x20, x0
    mov     x21, x1
    mov     x22, x2
    ldr     x28, [x21]
    ADDRESS x0, lantern_type_SignedBeaconBlock
    mov     x1, x20
    mov     x2, x21
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    9f
    mov     x24, x1
    PART    x25, x9, x24, SignedBeaconBlock_message
    ldr     x9, [x25, #BeaconBlock_slot]
    ldr     x10, [x25, #BeaconBlock_proposer_index]
    stp     x9, x10, [x22]
    add     x0, x22, #16
    add     x1, x25, #BeaconBlock_parent_root
    mov     x2, #32
    bl      lantern_copy
    add     x0, x22, #48
    add     x1, x25, #BeaconBlock_state_root
    mov     x2, #32
    bl      lantern_copy
    add     x0, x22, #112
    add     x1, x24, #SignedBeaconBlock_signature
    mov     x2, #96
    bl      lantern_copy
    PART    x1, x9, x25, BeaconBlock_body   /* body_root */
    ADDRESS x0, lantern_type_BeaconBlockBody
    mov     x2, x21
    add     x3, x22, #80
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 8f
    mov     x0, #LANTERN_OK
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       99f
9:  mov     x0, #LANTERN_INVALID_ENCODING
99: str     x28, [x21]
    LEAVE 0
SPEC_END node_block_header

/* (state, out): the previous_justified, current_justified and finalized checkpoints of the state. */
SPEC_FUNCTION node_state_checkpoints
    FRAME 16
    str     x1, [sp, #16]
    mov     x2, #(3 * 40)
    mov     x9, x0
    mov     x0, x1
    ADDQ    x1, x9, BeaconState_previous_justified_checkpoint
    bl      lantern_copy
    mov     x0, #LANTERN_OK
    UNFRAME 16
SPEC_END node_state_checkpoints

/*
 * (state, config, scratch, out): lantern_node_proposers (node.md): the dependent root of the epoch
 * of the state's slot, then its proposers. x19 state, x20 config, x21 scratch, x22 out, x28 the
 * scratch size, restored. Locals: L the epoch, L+8 the slot - 1, L+16 the latest_block_header (112).
 */
SPEC_FUNCTION node_proposers
    ENTER 128
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldr     x28, [x21]
    LDQ     x9, x19, BeaconState_slot
    mov     x0, #LANTERN_INVALID_SLOT
    tst     x9, #(SLOTS_PER_EPOCH - 1)
    b.ne    99f
    NEED_SCRATCH x21, x19, 2, 8f
    LDQ     x9, x19, BeaconState_slot
    lsr     x10, x9, #LOG2_SLOTS_PER_EPOCH
    str     x10, [sp, #L]
    cbz     x9, 2f
    sub     x9, x9, #1                      /* get_block_root_at_slot(state, slot - 1) */
    str     x9, [sp, #(L + 8)]
    mov     x0, x19
    add     x1, sp, #(L + 8)
    mov     x2, x22
    bl      lantern_get_block_root_at_slot
    cbnz    x0, 99f
    b       3f
2:  add     x0, sp, #(L + 16)               /* slot 0: hash_tree_root of the latest_block_header, its state_root the state's when zero */
    ADDQ    x1, x19, BeaconState_latest_block_header
    mov     x2, #BeaconBlockHeader__mem
    bl      lantern_copy
    ldp     x9, x10, [sp, #(L + 16 + BeaconBlockHeader_state_root)]
    ldp     x11, x12, [sp, #(L + 16 + BeaconBlockHeader_state_root + 16)]
    orr     x9, x9, x10
    orr     x11, x11, x12
    orr     x9, x9, x11
    cbnz    x9, 21f
    mov     x0, x19
    LDQ     x1, x20, CONFIG_STATE_CACHE
    mov     x2, x21
    add     x3, sp, #(L + 16 + BeaconBlockHeader_state_root)
    bl      lantern_state_root
    cbnz    x0, 99f
21: ADDRESS x0, lantern_type_BeaconBlockHeader
    add     x1, sp, #(L + 16)
    mov     x2, x21
    mov     x3, x22
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 8f
3:
.if FORK >= FORK_FULU
    add     x0, x22, #32                    /* the proposers: the first SLOTS_PER_EPOCH of proposer_lookahead */
    ADDQ    x1, x19, BeaconState_proposer_lookahead
    mov     x2, #(8 * SLOTS_PER_EPOCH)
    bl      lantern_copy
    LDQ     x10, x19, BeaconState_validators + 8    /* each names a validator */
    mov     x9, #0
4:  add     x11, x22, #32
    ldr     x11, [x11, x9, lsl #3]
    mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    cmp     x11, x10
    b.hs    99f
    add     x9, x9, #1
    cmp     x9, #SLOTS_PER_EPOCH
    b.lo    4b
    mov     x0, #LANTERN_OK
.else
    mov     x0, x19                         /* the proposers: get_beacon_proposer_indices of the epoch */
    add     x1, sp, #L
    mov     x2, x21
    add     x3, x22, #32
    bl      lantern_get_beacon_proposer_indices
.endif
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
99: str     x28, [x21]
    LEAVE 128
SPEC_END node_proposers

/*
 * (state, config, scratch, out): lantern_node_event_roots (node.md): the block root, the state root,
 * and the previous and current duty dependent roots of a block's post-state. x19 state, x20 config,
 * x21 scratch, x22 out, x23 which dependent root, x24 its place, x28 the scratch size, restored.
 * Locals: L a slot, L+8 the latest_block_header (112).
 */
SPEC_FUNCTION node_event_roots
    ENTER 128
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldr     x28, [x21]
    NEED_SCRATCH x21, x19, 2, 8f
    add     x0, sp, #(L + 8)                /* the header, its state_root the state's when zero */
    ADDQ    x1, x19, BeaconState_latest_block_header
    mov     x2, #BeaconBlockHeader__mem
    bl      lantern_copy
    ldp     x9, x10, [sp, #(L + 8 + BeaconBlockHeader_state_root)]
    ldp     x11, x12, [sp, #(L + 8 + BeaconBlockHeader_state_root + 16)]
    orr     x9, x9, x10
    orr     x11, x11, x12
    orr     x9, x9, x11
    cbnz    x9, 1f
    mov     x0, x19
    LDQ     x1, x20, CONFIG_STATE_CACHE
    mov     x2, x21
    add     x3, sp, #(L + 8 + BeaconBlockHeader_state_root)
    bl      lantern_state_root
    cbnz    x0, 99f
1:  add     x0, x22, #32
    add     x1, sp, #(L + 8 + BeaconBlockHeader_state_root)
    mov     x2, #32
    bl      lantern_copy
    ADDRESS x0, lantern_type_BeaconBlockHeader  /* the block root */
    add     x1, sp, #(L + 8)
    mov     x2, x21
    mov     x3, x22
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 8f
    mov     x23, #0                         /* each dependent root: of the epoch before the state's (0), then of its epoch (1) */
2:  LDQ     x9, x19, BeaconState_slot
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    add     x9, x9, x23
    add     x24, x22, #64
    add     x24, x24, x23, lsl #5
    cmp     x9, #2                          /* get_block_root_at_slot(state, compute_start_slot_at_epoch(e) - 1), e = x9 - 1 */
    b.lo    3f
    sub     x9, x9, #1
    lsl     x9, x9, #LOG2_SLOTS_PER_EPOCH
    sub     x9, x9, #1
    str     x9, [sp, #L]
    mov     x0, x19
    add     x1, sp, #L
    mov     x2, x24
    bl      lantern_get_block_root_at_slot
    cbnz    x0, 99f
    b       4f
3:  LDQ     x9, x19, BeaconState_slot       /* on underflow, the genesis block root */
    cbz     x9, 31f
    str     xzr, [sp, #L]
    mov     x0, x19
    add     x1, sp, #L
    mov     x2, x24
    bl      lantern_get_block_root_at_slot
    cbnz    x0, 99f
    b       4f
31: mov     x0, x24
    mov     x1, x22
    mov     x2, #32
    bl      lantern_copy
4:  add     x23, x23, #1
    cmp     x23, #2
    b.lo    2b
    mov     x0, #LANTERN_OK
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
99: str     x28, [x21]
    LEAVE 128
SPEC_END node_event_roots

.if BeaconState_state_roots != NODE_STATE_STATE_ROOTS || BeaconState_fork != NODE_STATE_FORK
.error "nodehooks: NODE_STATE_STATE_ROOTS or NODE_STATE_FORK is not the state's"
.endif
.if BeaconState_validators != NODE_STATE_VALIDATORS || BeaconState_balances != NODE_STATE_BALANCES || Validator__mem != NODE_VALIDATOR_MEM
.error "nodehooks: NODE_STATE_VALIDATORS, NODE_STATE_BALANCES or NODE_VALIDATOR_MEM is not the state's"
.endif
.if Validator_withdrawal_credentials != NODE_VALIDATOR_CREDENTIALS || Validator_effective_balance != NODE_VALIDATOR_EFFECTIVE_BALANCE || Validator_slashed != NODE_VALIDATOR_SLASHED
.error "nodehooks: a NODE_VALIDATOR_* offset is not the Validator's"
.endif
.if Validator_activation_eligibility_epoch != NODE_VALIDATOR_ELIGIBILITY || Validator_activation_epoch != NODE_VALIDATOR_ACTIVATION || Validator_exit_epoch != NODE_VALIDATOR_EXIT || Validator_withdrawable_epoch != NODE_VALIDATOR_WITHDRAWABLE
.error "nodehooks: a NODE_VALIDATOR_* epoch offset is not the Validator's"
.endif

/*
 * (state, config, index, scratch, out) -> status: the AttestationData of the state's slot, its 128
 * SSZ bytes in out (node.md, lantern_node_attestation_data). x19 the state, x20 the index, x21 out.
 * Locals: L lantern_node_event_roots's out (128).
 */
SPEC_FUNCTION node_attestation_data
    ENTER 128
    mov     x19, x0
    mov     x20, x2
    mov     x21, x4
    mov     x2, x3
    add     x3, sp, #L
    bl      lantern_node_event_roots
    cbnz    x0, 9f
    LDQ     x9, x19, BeaconState_slot       /* slot, index */
    str     x9, [x21]
.if FORK >= FORK_ELECTRA
    mov     x20, #0
.endif
    str     x20, [x21, #8]
    add     x0, x21, #16                    /* beacon_block_root */
    add     x1, sp, #L
    mov     x2, #32
    bl      lantern_copy
    add     x0, x21, #48                    /* source: current_justified_checkpoint */
    ADDQ    x1, x19, BeaconState_current_justified_checkpoint
    mov     x2, #40
    bl      lantern_copy
    LDQ     x9, x19, BeaconState_slot       /* target: the epoch, and its boundary block's root */
    lsr     x10, x9, #LOG2_SLOTS_PER_EPOCH
    str     x10, [x21, #88]
    lsl     x11, x10, #LOG2_SLOTS_PER_EPOCH
    add     x1, sp, #L
    cmp     x11, x9
    b.eq    1f
    and     x11, x11, #(SLOTS_PER_HISTORICAL_ROOT - 1)
    ADDQ    x1, x19, BeaconState_block_roots
    add     x1, x1, x11, lsl #5
1:  add     x0, x21, #96
    mov     x2, #32
    bl      lantern_copy
    mov     x0, #LANTERN_OK
9:  LEAVE 128
SPEC_END node_attestation_data

/*
 * (state, config, ids, scratch, out) -> status: the committee assignments of the ids in the epoch
 * of the state at its first slot (node.md, lantern_node_attester_duties). x19 the state, x20 the
 * config, x21 the items, x22 scratch, x23 out, x24 the items' count, x25 a bit for each validator an
 * item names, x26 a committee's list, both at the end of scratch, x27 a member's place. Locals: L the
 * epoch, L+8 the committees at a slot, L+16 the validators, L+24 the scratch's size, L+32 a slot,
 * L+40 a committee index, L+64 lantern_node_event_roots's out (128).
 */
SPEC_FUNCTION node_attester_duties
    ENTER 192
    mov     x19, x0
    mov     x20, x1
    ldr     x9, [x2, #8]
    add     x21, x2, x9
    ldr     x24, [x2, #16]
    lsr     x24, x24, #6
    mov     x22, x3
    mov     x23, x4
    LDQ     x9, x19, BeaconState_slot       /* the first slot of an epoch */
    tst     x9, #(SLOTS_PER_EPOCH - 1)
    b.ne    95f
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    str     x9, [sp, #L]
    ldr     x9, [x22]
    str     x9, [sp, #(L + 24)]
    mov     x0, x19                         /* the dependent root: the previous duty dependent root */
    mov     x1, x20
    mov     x2, x22
    add     x3, sp, #(L + 64)
    bl      lantern_node_event_roots
    cbnz    x0, 99f
    mov     x0, x23
    add     x1, sp, #(L + 64 + 64)
    mov     x2, #32
    bl      lantern_copy
    mov     x0, x19                         /* the committees at a slot */
    add     x1, sp, #L
    LDQ     x2, x20, CONFIG_COMMITTEE_CACHE
    mov     x3, x22
    add     x4, sp, #(L + 8)
    bl      lantern_get_committee_count_per_slot
    cbnz    x0, 99f
    ldr     x9, [sp, #(L + 8)]
    str     x9, [x23, #32]
    add     x0, x23, #40                    /* no assignment yet */
    mov     x9, #48
    mul     x1, x24, x9
    bl      lantern_zero
    LDQ     x9, x19, BeaconState_validators + 8 /* the bits and a committee's list at the end of scratch, S(2) before them */
    str     x9, [sp, #(L + 16)]
    add     x10, x9, #63
    lsr     x10, x10, #6
    lsl     x10, x10, #3
    ldr     x11, [sp, #(L + 8)]
    mov     x12, #SLOTS_PER_EPOCH
    mul     x11, x11, x12
    udiv    x11, x9, x11
    add     x11, x11, #1
    lsl     x11, x11, #3
    add     x11, x11, #LIST_FIXED
    add     x12, x10, x11
    lsl     x13, x9, #3
    add     x13, x13, #LIST_FIXED
    lsl     x13, x13, #1
    MOVQ    x14, LANTERN_SCRATCH_FIXED
    add     x13, x13, x14
    add     x13, x13, x12
    ldr     x14, [x22]
    cmp     x14, x13
    b.lo    97f
    sub     x14, x14, x12
    str     x14, [x22]
    add     x25, x22, x14
    add     x26, x25, x10
    str     x11, [x26]
    mov     x9, #LIST_FIXED
    stp     x9, xzr, [x26, #LIST_OFFSET]
    mov     x0, x25
    mov     x1, x10
    bl      lantern_zero
    mov     x9, #0                          /* a bit for each item's index */
1:  cmp     x9, x24
    b.hs    2f
    add     x10, x21, x9, lsl #6
    ldr     x10, [x10, #8]
    ldr     x11, [sp, #(L + 16)]
    cmp     x10, x11
    b.hs    11f
    lsr     x11, x10, #6
    ldr     x12, [x25, x11, lsl #3]
    mov     x13, #1
    lsl     x13, x13, x10
    orr     x12, x12, x13
    str     x12, [x25, x11, lsl #3]
11: add     x9, x9, #1
    b       1b
2:  ldr     x9, [sp, #L]                    /* each committee of each slot of the epoch */
    lsl     x9, x9, #LOG2_SLOTS_PER_EPOCH
    str     x9, [sp, #(L + 32)]
3:  str     xzr, [sp, #(L + 40)]
4:  mov     x0, x19
    add     x1, sp, #(L + 32)
    add     x2, sp, #(L + 40)
    LDQ     x3, x20, CONFIG_COMMITTEE_CACHE
    mov     x4, x22
    mov     x5, x26
    bl      lantern_get_beacon_committee
    cbnz    x0, 98f
    mov     x27, #0
5:  ldr     x9, [x26, #LIST_COUNT]
    cmp     x27, x9
    b.hs    7f
    add     x10, x26, #LIST_FIXED
    ldr     x10, [x10, x27, lsl #3]         /* a member an item names: each such item's assignment */
    lsr     x11, x10, #6
    ldr     x12, [x25, x11, lsl #3]
    lsr     x12, x12, x10
    tbz     x12, #0, 6f
    mov     x11, #0
51: cmp     x11, x24
    b.hs    6f
    add     x12, x21, x11, lsl #6
    ldr     x12, [x12, #8]
    cmp     x12, x10
    b.ne    52f
    mov     x13, #48
    madd    x13, x11, x13, x23
    add     x13, x13, #40
    mov     x14, #1
    ldr     x15, [sp, #(L + 32)]
    stp     x14, x15, [x13]
    ldr     x14, [sp, #(L + 40)]
    ldr     x15, [x26, #LIST_COUNT]
    stp     x14, x15, [x13, #16]
    stp     x27, x10, [x13, #32]
52: add     x11, x11, #1
    b       51b
6:  add     x27, x27, #1
    b       5b
7:  ldr     x9, [sp, #(L + 40)]             /* the next committee, then the next slot */
    add     x9, x9, #1
    str     x9, [sp, #(L + 40)]
    ldr     x10, [sp, #(L + 8)]
    cmp     x9, x10
    b.lo    4b
    ldr     x9, [sp, #(L + 32)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 32)]
    tst     x9, #(SLOTS_PER_EPOCH - 1)
    b.ne    3b
    mov     x0, #LANTERN_OK
98: ldr     x9, [sp, #(L + 24)]
    str     x9, [x22]
99: LEAVE 192
95: mov     x0, #LANTERN_INVALID_SLOT
    LEAVE 192
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 192
SPEC_END node_attester_duties

/* L0: x0 = the fork's TypeDescriptor of the NODE_JSON_* kind x9, or 0. Uses x0. */
LOCAL_FUNCTION node_type_of_kind
    UNWIND_END_PROLOGUE
    ADDRESS x0, lantern_type_SignedBeaconBlock
    cmp     x9, #NODE_JSON_BLOCK
    b.eq    9f
    ADDRESS x0, lantern_type_BeaconState
    cmp     x9, #NODE_JSON_STATE
    b.eq    9f
    ADDRESS x0, lantern_type_SignedVoluntaryExit
    cmp     x9, #NODE_JSON_EXIT
    b.eq    9f
    ADDRESS x0, lantern_type_ProposerSlashing
    cmp     x9, #NODE_JSON_PROPOSER_SLASHING
    b.eq    9f
    ADDRESS x0, lantern_type_AttesterSlashing
    cmp     x9, #NODE_JSON_ATTESTER_SLASHING
    b.eq    9f
.if FORK >= FORK_CAPELLA
    ADDRESS x0, lantern_type_SignedBLSToExecutionChange
    cmp     x9, #NODE_JSON_BLS_CHANGE
    b.eq    9f
.endif
    ADDRESS x0, lantern_type_Attestation
    cmp     x9, #NODE_JSON_ATTESTATION
    b.eq    9f
    ADDRESS x0, lantern_type_Attestations
    cmp     x9, #NODE_JSON_ATTESTATIONS
    b.eq    9f
.if FORK >= FORK_ELECTRA
    ADDRESS x0, lantern_type_SingleAttestation
    cmp     x9, #NODE_JSON_SINGLE_ATTESTATION
    b.eq    9f
.endif
    mov     x0, #0
9:  ret
END_FUNCTION node_type_of_kind

/* (kind, ssz, cursor, out): lantern_json_encode_ssz with the fork's type of the NODE_JSON_* kind. */
SPEC_FUNCTION node_json
    FRAME 0
    mov     x9, x0
    bl      node_type_of_kind
    cbz     x0, 8f
    CALL_GLOBAL lantern_json_encode_ssz
    UNFRAME 0
8:  mov     x0, #LANTERN_INVALID_EVENT
    UNFRAME 0
SPEC_END node_json

/*
 * (kind, json, scratch, out, fault): lantern_json_decode with the fork's type of the NODE_JSON_*
 * kind (node.md, NODE_WORK_API_SUBMIT); LANTERN_INVALID_JSON for a kind of no type in the fork.
 */
SPEC_FUNCTION node_json_decode
    FRAME 0
    mov     x9, x0
    bl      node_type_of_kind
    cbz     x0, 8f
    CALL_GLOBAL lantern_json_decode
    UNFRAME 0
8:  mov     x0, #LANTERN_INVALID_JSON
    UNFRAME 0
SPEC_END node_json_decode

/*
 * L0: x0 = the bytes of the SSZ default value of the type node x1 of the TypeDescriptor x0, written
 * at x2: zero bytes for a fixed size type, none for a list, the byte 1 for a bitlist, and for a
 * variable container or vector its fixed part with the offsets, then each variable part. x19 the
 * descriptor, x20 the node, x21 out, x22 a field or element, x23 their end, x24 the bytes, x25
 * the first field or an index, x26 a place in the fixed part.
 */
LOCAL_FUNCTION node_ssz_default
    ENTER 0
    mov     x19, x0
    mov     x21, x2
    ldr     x9, [x19, #SSZ_DESC_NODES_OFFSET]
    add     x9, x19, x9
    mov     x10, #SSZ_NODE_STRIDE
    madd    x20, x1, x10, x9
    ldr     x24, [x20, #SSZ_NODE_SSZ_SIZE]
    cbz     x24, 1f
    mov     x0, x21                         /* a fixed size type: zero bytes */
    mov     x1, x24
    bl      lantern_zero
    b       9f
1:  ldr     x9, [x20, #SSZ_NODE_KIND]
    cmp     x9, #SSZ_KIND_BIT_LIST
    b.ne    2f
    mov     w10, #1                         /* a bitlist: its delimiter bit */
    strb    w10, [x21]
    mov     x24, #1
    b       9f
2:  cmp     x9, #SSZ_KIND_CONTAINER
    b.eq    5f
    cmp     x9, #SSZ_KIND_VECTOR
    b.eq    3f
    mov     x24, #0                         /* a list: empty */
    b       9f
3:  ldr     x23, [x20, #SSZ_NODE_LENGTH]    /* a vector of variable elements: N offsets, then each element */
    ldr     x22, [x20, #SSZ_NODE_ELEMENT]
    lsl     x24, x23, #2
    mov     x25, #0
4:  cmp     x25, x23
    b.hs    9f
    str     w24, [x21, x25, lsl #2]
    mov     x0, x19
    mov     x1, x22
    add     x2, x21, x24
    bl      node_ssz_default
    add     x24, x24, x0
    add     x25, x25, #1
    b       4b
5:  ldr     x25, [x20, #SSZ_NODE_ELEMENT]   /* a variable container: the fixed part */
    ldr     x23, [x20, #SSZ_NODE_LENGTH]
    add     x23, x25, x23
    mov     x22, x25
    mov     x24, #0
6:  cmp     x22, x23
    b.hs    7f
    ldr     x9, [x19, #SSZ_DESC_FIELDS_OFFSET]
    add     x9, x19, x9
    add     x9, x9, x22, lsl #5
    ldr     x1, [x9, #SSZ_FIELD_NODE]
    ldr     x10, [x9, #SSZ_FIELD_FLAGS]
    mov     x11, #4                         /* a variable field: its offset, written below */
    tbnz    x10, #0, 61f
    ldr     x9, [x19, #SSZ_DESC_NODES_OFFSET]
    add     x9, x19, x9
    mov     x10, #SSZ_NODE_STRIDE
    madd    x9, x1, x10, x9
    ldr     x11, [x9, #SSZ_NODE_SSZ_SIZE]
    add     x0, x21, x24
    mov     x1, x11
    bl      lantern_zero
    ldr     x9, [x19, #SSZ_DESC_NODES_OFFSET]   /* its size again: lantern_zero took x1 */
    add     x9, x19, x9
    ldr     x10, [x19, #SSZ_DESC_FIELDS_OFFSET]
    add     x10, x19, x10
    add     x10, x10, x22, lsl #5
    ldr     x1, [x10, #SSZ_FIELD_NODE]
    mov     x10, #SSZ_NODE_STRIDE
    madd    x9, x1, x10, x9
    ldr     x11, [x9, #SSZ_NODE_SSZ_SIZE]
61: add     x24, x24, x11
    add     x22, x22, #1
    b       6b
7:  mov     x22, x25                        /* then each variable field, after its offset */
    mov     x26, #0
71: cmp     x22, x23
    b.hs    9f
    ldr     x9, [x19, #SSZ_DESC_FIELDS_OFFSET]
    add     x9, x19, x9
    add     x9, x9, x22, lsl #5
    ldr     x1, [x9, #SSZ_FIELD_NODE]
    ldr     x10, [x9, #SSZ_FIELD_FLAGS]
    tbnz    x10, #0, 72f
    ldr     x9, [x19, #SSZ_DESC_NODES_OFFSET]
    add     x9, x19, x9
    mov     x10, #SSZ_NODE_STRIDE
    madd    x9, x1, x10, x9
    ldr     x11, [x9, #SSZ_NODE_SSZ_SIZE]
    add     x26, x26, x11
    b       73f
72: str     w24, [x21, x26]
    add     x26, x26, #4
    mov     x0, x19
    add     x2, x21, x24
    bl      node_ssz_default
    add     x24, x24, x0
73: add     x22, x22, #1
    b       71b
9:  mov     x0, x24
    LEAVE 0
END_FUNCTION node_ssz_default

/*
 * (data, room, scratch, state, block): the anchor state and block of the genesis state in data.
 * x19 data, x20 room, x21 scratch, x22 state, x23 block, x24 the decoded state, then the
 * block's SSZ ByteList, x25 the default body's bytes, x28 the scratch size, restored on return.
 * Locals: L SizeBounds or a size, L+16 a root.
 */
SPEC_FUNCTION node_anchor
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x28, [x21]
    ADDRESS x0, lantern_type_BeaconState    /* the state, decoded at the end of scratch, then copied with room */
    mov     x1, x19
    mov     x2, x21
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    7f
    mov     x24, x1
    mov     x0, x24
    mov     x1, x20
    add     x2, sp, #L
    bl      lantern_beacon_state_copy_size
    ldr     x9, [sp, #L]
    ldr     x10, [x22]
    cmp     x10, x9
    b.lo    8f
    mov     x0, x24
    mov     x1, x20
    mov     x2, x22
    bl      lantern_beacon_state_copy
    cbnz    x0, 8f
    str     x28, [x21]
    ADDRESS x0, lantern_type_BeaconBlockBody    /* the default body's bytes: the least SSZ size of the type */
    add     x1, sp, #L
    CALL_GLOBAL lantern_ssz_size_bounds
    ldr     x25, [sp, #L]
    add     x9, x25, #(24 + 84 + 7)         /* the block's SSZ bytes, a ByteList at the end of scratch */
    and     x9, x9, #~7
    add     x10, x9, #8
    cmp     x28, x10
    b.lo    8f
    sub     x10, x28, x9
    str     x10, [x21]
    add     x24, x21, x10
    mov     x11, #24
    stp     x9, x11, [x24]
    add     x11, x25, #84
    str     x11, [x24, #16]
    ADDQ    x9, x22, BeaconState_latest_block_header
    ldr     x10, [x9, #BeaconBlockHeader_slot]
    ldr     x11, [x9, #BeaconBlockHeader_proposer_index]
    stp     x10, x11, [x24, #24]
    add     x0, x24, #40
    add     x1, x9, #BeaconBlockHeader_parent_root
    mov     x2, #32
    bl      lantern_copy
    ADDQ    x1, x22, BeaconState_latest_block_header + BeaconBlockHeader_state_root
    ldp     x10, x11, [x1]                  /* state_root: the header's, or hash_tree_root of the state */
    ldp     x12, x13, [x1, #16]
    orr     x10, x10, x11
    orr     x12, x12, x13
    orr     x10, x10, x12
    cbz     x10, 1f
    add     x0, x24, #72
    mov     x2, #32
    bl      lantern_copy
    b       2f
1:  ADDRESS x0, lantern_type_BeaconState
    mov     x1, x22
    mov     x2, x21
    add     x3, x24, #72
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 8f
2:  mov     w9, #84                         /* the body's offset, then the default body */
    str     w9, [x24, #(24 + 80)]
    ADDRESS x0, lantern_type_BeaconBlockBody
    ldr     x1, [x0, #SSZ_DESC_ROOT]
    add     x2, x24, #(24 + 84)
    bl      node_ssz_default
    ADDRESS x0, lantern_type_BeaconBlock
    mov     x1, x24
    mov     x2, x21
    mov     x3, x23
    CALL_GLOBAL ssz_deserialize
    cbnz    x0, 8f
    PART    x1, x9, x23, BeaconBlock_body   /* the default body must be the header's */
    ADDRESS x0, lantern_type_BeaconBlockBody
    mov     x2, x21
    add     x3, sp, #(L + 16)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 8f
    ADDQ    x9, x22, BeaconState_latest_block_header + BeaconBlockHeader_body_root
    add     x10, sp, #(L + 16)
    mov     x11, #0
3:  ldr     x12, [x9, x11]
    ldr     x13, [x10, x11]
    cmp     x12, x13
    b.ne    6f
    add     x11, x11, #8
    cmp     x11, #32
    b.lo    3b
    mov     x0, #LANTERN_OK
    b       99f
6:  mov     x0, #LANTERN_INVALID_ANCHOR
    b       99f
7:  mov     x0, #LANTERN_INVALID_ENCODING
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
99: str     x28, [x21]
    LEAVE 48
SPEC_END node_anchor

/*
 * (data, room, scratch, state, block): the anchor of a start from the node's own history: data
 * holds two ByteLists, the second at the first multiple of 8 after the first: the SSZ bytes of a
 * BeaconState, then those of the message of its block, with the state's slot and root. state:
 * the state with room; block: the message. x20 room, x21 scratch, x22 state, x23 block, x24 the
 * decoded state, then the block's ByteList, x25 data's bytes, x26 their count, x27 the block's
 * place, x28 the scratch size, restored on return. Locals: L a size, L+16 a root.
 */
SPEC_FUNCTION node_anchor_block
    ENTER 48
    ldr     x9, [x0, #8]
    add     x25, x0, x9
    ldr     x26, [x0, #16]
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x28, [x21]
    cmp     x26, #24                        /* the state's ByteList: offset 24, size 24 + count, inside */
    b.lo    7f
    ldp     x9, x10, [x25]
    ldr     x11, [x25, #16]
    cmp     x10, #24
    b.ne    7f
    cmp     x11, x26
    b.hi    7f
    add     x12, x11, #24
    cmp     x9, x12
    b.ne    7f
    cmp     x9, x26
    b.hi    7f
    add     x27, x9, #7
    and     x27, x27, #~7
    ADDRESS x0, lantern_type_BeaconState    /* decoded, then copied with room */
    mov     x1, x25
    mov     x2, x21
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    7f
    mov     x24, x1
    mov     x0, x24
    mov     x1, x20
    add     x2, sp, #L
    bl      lantern_beacon_state_copy_size
    ldr     x9, [sp, #L]
    ldr     x10, [x22]
    cmp     x10, x9
    b.lo    8f
    mov     x0, x24
    mov     x1, x20
    mov     x2, x22
    bl      lantern_beacon_state_copy
    cbnz    x0, 8f
    str     x28, [x21]
    add     x9, x27, #24                    /* the block's ByteList, the same way */
    cmp     x9, x26
    b.hi    7f
    add     x24, x25, x27
    ldp     x9, x10, [x24]
    ldr     x11, [x24, #16]
    cmp     x10, #24
    b.ne    7f
    sub     x13, x26, x27
    cmp     x11, x13
    b.hi    7f
    add     x12, x11, #24
    cmp     x9, x12
    b.ne    7f
    cmp     x9, x13
    b.hi    7f
    ADDRESS x0, lantern_type_BeaconBlock
    mov     x1, x24
    mov     x2, x21
    mov     x3, x23
    CALL_GLOBAL ssz_deserialize
    str     x28, [x21]
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    8f
    cbnz    x0, 7f
    ldr     x9, [x23, #BeaconBlock_slot]    /* its slot and state_root are the state's */
    ldr     x10, [x22, #NODE_STATE_SLOT]
    cmp     x9, x10
    b.ne    6f
    ADDRESS x0, lantern_type_BeaconState
    mov     x1, x22
    mov     x2, x21
    add     x3, sp, #(L + 16)
    CALL_GLOBAL ssz_hash_tree_root
    str     x28, [x21]
    cbnz    x0, 8f
    add     x9, x23, #BeaconBlock_state_root
    add     x10, sp, #(L + 16)
    mov     x11, #0
3:  ldr     x12, [x9, x11]
    ldr     x13, [x10, x11]
    cmp     x12, x13
    b.ne    6f
    add     x11, x11, #8
    cmp     x11, #32
    b.lo    3b
    mov     x0, #LANTERN_OK
    b       99f
6:  mov     x0, #LANTERN_INVALID_ANCHOR
    b       99f
7:  mov     x0, #LANTERN_INVALID_ENCODING
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
99: str     x28, [x21]
    LEAVE 48
SPEC_END node_anchor_block

/*
 * (state, scratch, out, size): size: the bytes of a ByteList of the state's SSZ bytes, 24 + their
 * count; out: that ByteList, when its size field holds at least size. x19 state, x20 scratch,
 * x21 out, x22 size, x28 the scratch size, restored on return.
 */
SPEC_FUNCTION node_state_bytes
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldr     x28, [x20]
    ADDRESS x0, lantern_type_BeaconState
    mov     x1, x19
    mov     x2, x20
    mov     x3, x22
    CALL_GLOBAL ssz_serialize_size
    str     x28, [x20]
    cbnz    x0, 8f
    ldr     x9, [x22]
    ldr     x10, [x21]
    cmp     x10, x9
    b.lo    8f
    ADDRESS x0, lantern_type_BeaconState
    mov     x1, x19
    mov     x2, x20
    mov     x3, x21
    CALL_GLOBAL ssz_serialize
    str     x28, [x20]
    cbnz    x0, 8f
    mov     x0, #LANTERN_OK
    LEAVE 0
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END node_state_bytes

/* (pre, room, config, scratch, out): upgrade_to_<fork> of the object's fork; phase0 has none. */
SPEC_FUNCTION node_upgrade
    ENTER 0
.if FORK == FORK_ALTAIR
    bl      lantern_upgrade_to_altair
.elseif FORK == FORK_BELLATRIX
    bl      lantern_upgrade_to_bellatrix
.elseif FORK == FORK_CAPELLA
    bl      lantern_upgrade_to_capella
.elseif FORK == FORK_DENEB
    bl      lantern_upgrade_to_deneb
.elseif FORK == FORK_ELECTRA
    bl      lantern_upgrade_to_electra
.elseif FORK == FORK_FULU
    bl      lantern_upgrade_to_fulu
.else
    mov     x0, #LANTERN_INVALID_SLOT
.endif
    LEAVE 0
SPEC_END node_upgrade

/*
 * (data, state, config, scratch, result): the post-state again of a block the node imported:
 * state_transition of the SignedBeaconBlock in data with validate_result 0 and slots_done 1.
 * x19 data, x20 state, x21 config, x22 scratch, x23 result, x24 the block, x28 the scratch size.
 * Locals: L TransitionOptions.
 */
SPEC_FUNCTION node_replay
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x28, [x22]
    str     xzr, [x23]
    ADDRESS x0, lantern_type_SignedBeaconBlock
    mov     x1, x19
    mov     x2, x22
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    9f
    mov     x24, x1
    mov     x9, #1                          /* validate_result 0, execution_valid 1, slots_done 1 */
    stp     xzr, x9, [sp, #L]
    str     x9, [sp, #(L + 16)]
    mov     x0, x20
    mov     x1, x24
    add     x2, sp, #L
    mov     x3, x21
    mov     x4, x22
    mov     x5, x23
    bl      lantern_state_transition
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       99f
9:  mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x23]
    mov     x0, #LANTERN_OK
99: str     x28, [x22]
    LEAVE 32
SPEC_END node_replay

/*
 * (data, state, config, root, scratch, result): the proposer signature of the block in data, of
 * any fork, with the validators of state and the fork version of the block's epoch (node.md,
 * lantern_node_backfill). x20 data, x21 state, x22 config, x23 root, x24 scratch, x25 result, x26
 * the block's bytes. Locals: L the epoch, L+8 the fork version, L+16 the domain type, L+24 a
 * ByteList header, L+48 the signing root, L+80 the root, L+112 the domain.
 */
SPEC_FUNCTION node_backfill
    ENTER 144
    mov     x20, x0
    mov     x21, x1
    mov     x22, x2
    mov     x23, x3
    mov     x24, x4
    mov     x25, x5
    ldr     x9, [x20, #16]
    cmp     x9, #(100 + 84)
    b.lo    7f
    ldr     x9, [x20, #8]
    add     x26, x20, x9
    ldr     x10, [x26, #100]                /* the genesis block has no proposer */
    cbz     x10, 5f
    ldr     x11, [x26, #108]
    PART    x12, x13, x21, BeaconState_validators
    cmp     x11, x13
    b.hs    6f
    add     x27, x12, x11, lsl #7
    lsr     x10, x10, #LOG2_SLOTS_PER_EPOCH
    str     x10, [sp, #L]
    add     x0, sp, #L                      /* compute_fork_version(the block's epoch) */
    mov     x1, x22
    add     x2, sp, #(L + 8)
    bl      lantern_compute_fork_version
    mov     w9, #DOMAIN_BEACON_PROPOSER
    str     w9, [sp, #(L + 16)]
    add     x0, sp, #(L + 16)
    add     x1, sp, #(L + 8)
    ADDQ    x2, x21, BeaconState_genesis_validators_root
    mov     x3, x24
    add     x4, sp, #(L + 112)
    bl      lantern_compute_domain
    cbnz    x0, 99f
    add     x9, sp, #(L + 80)               /* compute_signing_root: hash_tree_root(SigningData(root, domain)) */
    COPY32  x9, x23
    add     x0, sp, #(L + 80)
    mov     x1, #64
    add     x2, sp, #(L + 48)
    bl      sha256_short
    add     x0, x27, #Validator_pubkey
    add     x1, x26, #4
    add     x2, sp, #(L + 24)
    mov     x3, x24
    bl      verify_root_signature
    cbnz    x0, 99f
    cbz     x1, 8f
5:  str     xzr, [x25]                      /* LANTERN_VALID */
    mov     x0, #LANTERN_OK
    b       99f
6:  mov     x9, #LANTERN_INVALID_PROPOSER_INDEX
    b       9f
7:  mov     x9, #LANTERN_INVALID_ENCODING
    b       9f
8:  mov     x9, #LANTERN_INVALID_BLOCK_SIGNATURE
9:  str     x9, [x25]
    mov     x0, #LANTERN_OK
99: LEAVE 144
SPEC_END node_backfill

/*
 * (store, data, is_from_block, state, scratch, result, target): validate_on_attestation of the
 * Attestation in data; with no target checkpoint state (state 0) the result is
 * LANTERN_NEED_TARGET_STATE and target holds the target checkpoint, else on_attestation.
 */
SPEC_FUNCTION node_attestation
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    ldr     x28, [x23]                      /* the scratch size, restored on return */
    str     xzr, [x24]
    ADDRESS x0, lantern_type_Attestation
    mov     x1, x20
    mov     x2, x23
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    9f
    mov     x26, x1
    mov     x0, x19
    mov     x2, x21
    bl      lantern_validate_on_attestation
    cbz     x0, 1f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    8f
    str     x0, [x24]                       /* a failed check */
    mov     x0, #LANTERN_OK
    b       99f
1:  cbnz    x22, 2f
    add     x9, x26, #(Attestation_data + AttestationData_target)
    ldr     x10, [x9, #Checkpoint_epoch]
    str     x10, [x25]
    add     x9, x9, #Checkpoint_root
    add     x10, x25, #8
    COPY32  x10, x9
    mov     x9, #LANTERN_NEED_TARGET_STATE
    str     x9, [x24]
    mov     x0, #LANTERN_OK
    b       99f
2:  mov     x0, x19
    mov     x1, x26
    mov     x2, x21
    mov     x3, x22
    mov     x4, x23
    mov     x5, x24
    bl      lantern_on_attestation
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       99f
9:  mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x24]
    mov     x0, #LANTERN_OK
99: str     x28, [x23]
    LEAVE 0
SPEC_END node_attestation

/* (store, data, state, scratch, result): on_attester_slashing of the AttesterSlashing in data. */
SPEC_FUNCTION node_attester_slashing
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x28, [x22]                      /* the scratch size, restored on return */
    str     xzr, [x23]
    ADDRESS x0, lantern_type_AttesterSlashing
    mov     x1, x20
    mov     x2, x22
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    9f
    mov     x0, x19
    mov     x2, x21
    mov     x3, x22
    mov     x4, x23
    bl      lantern_on_attester_slashing
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       99f
9:  mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x23]
    mov     x0, #LANTERN_OK
99: str     x28, [x22]
    LEAVE 0
SPEC_END node_attester_slashing

/*
 * (state, epoch, out) -> status: get_randao_mix of the epoch (2^64 - 1: the state's epoch) when
 * the state holds it, from the state's epoch - EPOCHS_PER_HISTORICAL_VECTOR + 1 to its epoch;
 * else LANTERN_NO_STATE_ANSWER (node.md, lantern_node_randao).
 */
SPEC_FUNCTION node_randao
    FRAME 0
    LDQ     x9, x0, BeaconState_slot
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    cmn     x1, #1
    csel    x1, x9, x1, eq
    cmp     x1, x9
    b.hi    8f
    sub     x10, x9, x1
    MOVQ    x11, EPOCHS_PER_HISTORICAL_VECTOR
    cmp     x10, x11
    b.hs    8f
    sub     x11, x11, #1
    and     x10, x1, x11
    ADDQ    x9, x0, BeaconState_randao_mixes
    add     x1, x9, x10, lsl #5
    mov     x0, x2
    mov     x2, #32
    bl      lantern_copy
    mov     x0, #LANTERN_OK
    UNFRAME 0
8:  mov     x0, #LANTERN_NO_STATE_ANSWER
    UNFRAME 0
SPEC_END node_randao
.if EPOCHS_PER_HISTORICAL_VECTOR & (EPOCHS_PER_HISTORICAL_VECTOR - 1)
.error "lantern_node_randao takes EPOCHS_PER_HISTORICAL_VECTOR as a power of two"
.endif

/*
 * (state, epoch, scratch, out) -> status: the index of each member of the state's sync committee
 * of the epoch (2^64 - 1: the state's epoch), current_sync_committee for the period of the
 * state's epoch, next_sync_committee for the next, by find_pubkeys with its table at the end of
 * scratch (node.md, lantern_node_sync_committee). Before altair, or another period:
 * LANTERN_NO_STATE_ANSWER.
 */
SPEC_FUNCTION node_sync_committee
    FRAME 0
.if FORK >= FORK_ALTAIR
    LDQ     x9, x0, BeaconState_slot
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH
    cmn     x1, #1
    csel    x1, x9, x1, eq
    MOVQ    x10, EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    udiv    x9, x9, x10
    udiv    x11, x1, x10
    MOVQ    x12, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    cmp     x11, x9
    b.eq    1f
    add     x9, x9, #1
    cmp     x11, x9
    b.ne    8f
    MOVQ    x12, BeaconState_next_sync_committee + SyncCommittee_pubkeys
1:  ldr     x9, [x2]                        /* the key table at the end of scratch */
    MOVQ    x10, SYNC_TABLE_BYTES + 24
    subs    x10, x9, x10
    b.lo    9f
    add     x13, x2, x10
    add     x1, x0, x12
    mov     x2, x3
    mov     x3, x13
    bl      find_pubkeys
    cbnz    x0, 7f
    mov     x0, #LANTERN_OK
    UNFRAME 0
7:  mov     x0, #LANTERN_INVALID_ENCODING
    UNFRAME 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 0
8:
.endif
    mov     x0, #LANTERN_NO_STATE_ANSWER
    UNFRAME 0
SPEC_END node_sync_committee

/*
 * (state, kind, out) -> status: the address of the first item, the count and the bytes of an item
 * of the state's pending_deposits (kind 0), pending_partial_withdrawals (1) or
 * pending_consolidations (2); before electra LANTERN_NO_STATE_ANSWER (node.md, lantern_node_pending).
 */
SPEC_FUNCTION node_pending
    FRAME 0
.if FORK >= FORK_ELECTRA
    cmp     x1, #1
    b.eq    1f
    b.hi    2f
    PART    x9, x10, x0, BeaconState_pending_deposits
    mov     x11, #PendingDeposit__mem
    b       5f
1:  PART    x9, x10, x0, BeaconState_pending_partial_withdrawals
    mov     x11, #PendingPartialWithdrawal__mem
    b       5f
2:  cmp     x1, #2
    b.ne    8f
    PART    x9, x10, x0, BeaconState_pending_consolidations
    mov     x11, #PendingConsolidation__mem
5:  stp     x9, x10, [x2]
    str     x11, [x2, #16]
    mov     x0, #LANTERN_OK
    UNFRAME 0
8:
.endif
    mov     x0, #LANTERN_NO_STATE_ANSWER
    UNFRAME 0
SPEC_END node_pending
.if FORK >= FORK_ELECTRA
.if PendingDeposit__mem != 192 || PendingPartialWithdrawal__mem != 24 || PendingConsolidation__mem != 16
.error "lantern_node_pending: an item is its SSZ encoding"
.endif
.endif

/*
 * (state, out) -> status: the state's proposer_lookahead, (MIN_SEED_LOOKAHEAD + 1) *
 * SLOTS_PER_EPOCH u64; before fulu LANTERN_NO_STATE_ANSWER (node.md, lantern_node_proposer_lookahead).
 */
SPEC_FUNCTION node_proposer_lookahead
    FRAME 0
.if FORK >= FORK_FULU
    mov     x9, x1
    ADDQ    x1, x0, BeaconState_proposer_lookahead
    mov     x0, x9
    mov     x2, #(8 * API_LOOKAHEAD_SLOTS)
    bl      lantern_copy
    mov     x0, #LANTERN_OK
.else
    mov     x0, #LANTERN_NO_STATE_ANSWER
.endif
    UNFRAME 0
SPEC_END node_proposer_lookahead

/*
 * L1: x0 = a status: in the root x23 of lantern_node_gossip for the valid beacon_attestation x20,
 * its data.slot, its committee index, its member and 0 (node.md): from electra, the member is the
 * place of attester_index in lantern_get_beacon_committee of the head state x19.head, + 2^16 times
 * the committee's length, the committee a list at the end of the scratch x21; before electra, 0.
 * x24 the list, x25 the scratch's size. Locals: L the slot, L+8 the index.
 */
LOCAL_FUNCTION node_gossip_member
    ENTER 16
.if FORK >= FORK_ELECTRA
    ldr     x9, [x20, #(SingleAttestation_data + AttestationData_slot)]
    ldr     x10, [x20, #SingleAttestation_committee_index]
.else
    ldr     x9, [x20, #(Attestation_data + AttestationData_slot)]
    ldr     x10, [x20, #(Attestation_data + AttestationData_index)]
.endif
    stp     x9, x10, [x23]
    stp     xzr, xzr, [x23, #16]
.if FORK >= FORK_ELECTRA
    stp     x9, x10, [sp, #L]
    ldr     x25, [x21]                      /* the committee's list at the end of scratch */
    MOVQ    x11, LIST_FIXED + 8 * MAX_VALIDATORS_PER_COMMITTEE
    subs    x12, x25, x11
    b.lo    8f
    str     x12, [x21]
    add     x24, x21, x12
    str     x11, [x24]
    mov     x9, #LIST_FIXED
    stp     x9, xzr, [x24, #LIST_OFFSET]
    ldr     x0, [x19, #NodeGossip_head]
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    ldr     x3, [x19, #NodeGossip_config]
    ldr     x3, [x3, #CONFIG_COMMITTEE_CACHE]
    mov     x4, x21
    mov     x5, x24
    bl      lantern_get_beacon_committee
    str     x25, [x21]
    cbnz    x0, 9f
    ldr     x9, [x24, #LIST_OFFSET]         /* the attester's place */
    add     x9, x24, x9
    ldr     x10, [x24, #LIST_COUNT]
    ldr     x11, [x20, #SingleAttestation_attester_index]
    mov     x12, #0
1:  cmp     x12, x10
    b.hs    7f
    ldr     x13, [x9, x12, lsl #3]
    cmp     x13, x11
    b.eq    2f
    add     x12, x12, #1
    b       1b
2:  orr     x12, x12, x10, lsl #16
    str     x12, [x23, #16]
.endif
7:  mov     x0, #LANTERN_OK
9:  LEAVE 16
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION node_gossip_member

/*
 * (args, data, scratch, result, root, index): the gossip validation of the topic args.topic for
 * the message in data, decoded with the fork's type. For beacon_block, blob_sidecar and
 * data_column_sidecar the proposer state first gets process_slots to the message's slot. A valid
 * beacon_block gives its root and blob count; a valid blob_sidecar the root of its block header
 * and its index. x19 args, x20 the message, x21 scratch, x22 result, x23 root, x24 the topic,
 * x25 the slot, x26 the proposer state, x27 index, x28 the scratch size, restored on return.
 * Locals: (16 + L) a slot and a result. The two arguments past the eighth go at sp.
 */
SPEC_FUNCTION node_gossip
    ENTER_OUT 16, 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x27, x5
    ldr     x28, [x21]
    str     xzr, [x22]
    str     xzr, [x27]
    ldr     x24, [x19, #NodeGossip_topic]
    ADDRESS x0, lantern_type_SignedBeaconBlock     /* the type of the topic */
    cmp     x24, #GOSSIP_BEACON_BLOCK
    b.eq    1f
    ADDRESS x0, lantern_type_SignedAggregateAndProof
    cmp     x24, #GOSSIP_BEACON_AGGREGATE_AND_PROOF
    b.eq    1f
.if FORK >= FORK_ELECTRA
    ADDRESS x0, lantern_type_SingleAttestation
.else
    ADDRESS x0, lantern_type_Attestation
.endif
    cmp     x24, #GOSSIP_BEACON_ATTESTATION
    b.eq    1f
    ADDRESS x0, lantern_type_SignedVoluntaryExit
    cmp     x24, #GOSSIP_VOLUNTARY_EXIT
    b.eq    1f
    ADDRESS x0, lantern_type_ProposerSlashing
    cmp     x24, #GOSSIP_PROPOSER_SLASHING
    b.eq    1f
    ADDRESS x0, lantern_type_AttesterSlashing
    cmp     x24, #GOSSIP_ATTESTER_SLASHING
    b.eq    1f
.if FORK >= FORK_ALTAIR
    ADDRESS x0, lantern_type_SignedContributionAndProof
    cmp     x24, #GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF
    b.eq    1f
    ADDRESS x0, lantern_type_SyncCommitteeMessage
    cmp     x24, #GOSSIP_SYNC_COMMITTEE
    b.eq    1f
.endif
.if FORK >= FORK_CAPELLA
    ADDRESS x0, lantern_type_SignedBLSToExecutionChange
    cmp     x24, #GOSSIP_BLS_TO_EXECUTION_CHANGE
    b.eq    1f
.endif
.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    ADDRESS x0, lantern_type_BlobSidecar
    cmp     x24, #GOSSIP_BLOB_SIDECAR
    b.eq    1f
.endif
.if FORK >= FORK_FULU
    ADDRESS x0, lantern_type_DataColumnSidecar
    cmp     x24, #GOSSIP_DATA_COLUMN_SIDECAR
    b.eq    1f
.endif
    mov     x9, #LANTERN_GOSSIP_IGNORE      /* a topic of no type in this fork */
    str     x9, [x22]
    mov     x0, #LANTERN_OK
    b       99f
1:  mov     x1, x20
    mov     x2, x21
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    7f
    mov     x20, x1
    ldr     x26, [x19, #NodeGossip_proposer]        /* the proposer state at the message's slot */
    cbz     x26, 20f
    cmp     x24, #GOSSIP_BEACON_BLOCK
    b.ne    11f
    PART    x9, x10, x20, SignedBeaconBlock_message
    ldr     x25, [x9, #BeaconBlock_slot]
    b       14f
11:
.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    cmp     x24, #GOSSIP_BLOB_SIDECAR
    b.ne    12f
    LDQ     x25, x20, BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot
    b       14f
12:
.endif
.if FORK >= FORK_FULU
    cmp     x24, #GOSSIP_DATA_COLUMN_SIDECAR
    b.ne    13f
    LDQ     x25, x20, DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot
    b       14f
13:
.endif
    b       20f
14: ldr     x9, [x26, #NODE_STATE_SLOT]
    cmp     x9, x25
    b.hs    20f
    str     x25, [sp, #(16 + L)]
    mov     x0, x26
    add     x1, sp, #(16 + L)
    ldr     x2, [x19, #NodeGossip_config]
    mov     x3, x21
    add     x4, sp, #(16 + L + 8)
    bl      lantern_process_slots
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    8f
    cbnz    x0, 99f
    ldr     x9, [sp, #(16 + L + 8)]
    cbz     x9, 20f
    mov     x9, #LANTERN_GOSSIP_IGNORE      /* the slots do not run: no answer of the spec */
    str     x9, [x22]
    b       99f
20: ldr     x0, [x19, #NodeGossip_seen]     /* the check of the topic */
    ldr     x1, [x19, #NodeGossip_store]
    mov     x2, x20
    add     x3, x19, #NodeGossip_time_ms
    ldr     x9, [x19, #NodeGossip_head]
    cbnz    x26, 21f
    mov     x26, x9
21: cmp     x24, #GOSSIP_BEACON_BLOCK
    b.ne    30f
    mov     x4, x9
    mov     x5, x26
.if FORK == FORK_BELLATRIX
    ldr     x6, [x19, #NodeGossip_justified]
    cbnz    x6, 22f
    mov     x6, x9
22: mov     x7, x21
    str     x22, [sp]
.else
    mov     x6, x21
    mov     x7, x22
.endif
    bl      lantern_validate_beacon_block_gossip
    cbnz    x0, 98f
    ldr     x9, [x22]                       /* a valid block: its root and blob count */
    cbnz    x9, 99f
    PART    x1, x9, x20, SignedBeaconBlock_message
.if FORK >= FORK_DENEB
    PART    x9, x10, x1, BeaconBlock_body
    LDQ     x10, x9, BeaconBlockBody_blob_kzg_commitments + 8
    str     x10, [x27]
.endif
    ADDRESS x0, lantern_type_BeaconBlock
    mov     x2, x21
    mov     x3, x23
    CALL_GLOBAL ssz_hash_tree_root
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    8f
    b       99f
30: cmp     x24, #GOSSIP_BEACON_AGGREGATE_AND_PROOF
    b.ne    31f
    mov     x4, x9
    mov     x5, x21
    mov     x6, x22
    bl      lantern_validate_beacon_aggregate_and_proof_gossip
    b       98f
31: cmp     x24, #GOSSIP_BEACON_ATTESTATION
    b.ne    32f
    add     x4, x19, #NodeGossip_subnet
    mov     x5, x9
    mov     x6, x21
    mov     x7, x22
    bl      lantern_validate_beacon_attestation_gossip
    cbnz    x0, 98f
    ldr     x9, [x22]                       /* a valid attestation: its slot, committee index and member */
    cbnz    x9, 99f
    bl      node_gossip_member
    b       98f
32: cmp     x24, #GOSSIP_VOLUNTARY_EXIT
    b.ne    33f
    mov     x4, x9
    mov     x5, x21
    mov     x6, x22
    bl      lantern_validate_voluntary_exit_gossip
    b       98f
33: cmp     x24, #GOSSIP_PROPOSER_SLASHING
    b.ne    34f
    mov     x3, x9
    mov     x4, x21
    mov     x5, x22
    bl      lantern_validate_proposer_slashing_gossip
    b       98f
34: cmp     x24, #GOSSIP_ATTESTER_SLASHING
    b.ne    35f
    mov     x3, x9
    mov     x4, x21
    mov     x5, x22
    bl      lantern_validate_attester_slashing_gossip
    b       98f
35:
.if FORK >= FORK_ALTAIR
    cmp     x24, #GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF
    b.ne    36f
    mov     x4, x9
    mov     x5, x21
    mov     x6, x22
    bl      lantern_validate_sync_committee_contribution_and_proof_gossip
    b       98f
36: cmp     x24, #GOSSIP_SYNC_COMMITTEE
    b.ne    37f
    add     x4, x19, #NodeGossip_subnet
    mov     x5, x9
    mov     x6, x21
    mov     x7, x22
    bl      lantern_validate_sync_committee_message_gossip
    b       98f
37:
.endif
.if FORK >= FORK_CAPELLA
    cmp     x24, #GOSSIP_BLS_TO_EXECUTION_CHANGE
    b.ne    38f
    mov     x4, x9
    mov     x5, x21
    mov     x6, x22
    bl      lantern_validate_bls_to_execution_change_gossip
    b       98f
38:
.endif
.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    cmp     x24, #GOSSIP_BLOB_SIDECAR
    b.ne    39f
    add     x4, x19, #NodeGossip_subnet
    mov     x5, x9
    mov     x6, x26
    ldr     x7, [x19, #NodeGossip_settings]
    stp     x21, x22, [sp]
    bl      lantern_validate_blob_sidecar_gossip
    cbnz    x0, 98f
    ldr     x9, [x22]                       /* a valid sidecar: the root of its block header, its index */
    cbnz    x9, 99f
    ldr     x9, [x20, #BlobSidecar_index]
    str     x9, [x27]
    ADDRESS x0, lantern_type_BeaconBlockHeader
    ADDQ    x1, x20, BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message
    mov     x2, x21
    mov     x3, x23
    CALL_GLOBAL ssz_hash_tree_root
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    8f
    b       99f
39:
.endif
.if FORK >= FORK_FULU
    cmp     x24, #GOSSIP_DATA_COLUMN_SIDECAR
    b.ne    40f
    add     x4, x19, #NodeGossip_subnet
    mov     x5, x9
    mov     x6, x26
    ldr     x7, [x19, #NodeGossip_settings]
    stp     x21, x22, [sp]
    bl      lantern_validate_data_column_sidecar_gossip
    cbnz    x0, 98f
    ldr     x9, [x22]                       /* a valid sidecar: the root of its block header, its index */
    cbnz    x9, 99f
    ldr     x9, [x20, #DataColumnSidecar_index]
    str     x9, [x27]
    ADDRESS x0, lantern_type_BeaconBlockHeader
    ADDQ    x1, x20, DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message
    mov     x2, x21
    mov     x3, x23
    CALL_GLOBAL ssz_hash_tree_root
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    8f
    b       99f
40:
.endif
    mov     x9, #LANTERN_GOSSIP_IGNORE
    str     x9, [x22]
    mov     x0, #LANTERN_OK
    b       99f
98: cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    8f
    b       99f
7:  mov     x9, #LANTERN_GOSSIP_REJECT      /* no SSZ encoding of the type */
    str     x9, [x22]
    mov     x0, #LANTERN_OK
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
99: str     x28, [x21]
    LEAVE_OUT 16, 16
SPEC_END node_gossip

.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
/*
 * (data, config, settings, scratch, result, root): the checks a reader of a blob sidecar response
 * makes: the index below the fork's limit, verify_blob_sidecar_inclusion_proof and
 * verify_blob_kzg_proof; then hash_tree_root of its block header. x19 config, x20 the sidecar,
 * x21 scratch, x22 result, x23 root, x24 settings, x28 the scratch size, restored on return.
 * Locals: L an out.
 */
SPEC_FUNCTION node_blob_sidecar
    ENTER 16
    mov     x20, x0
    mov     x19, x1
    mov     x24, x2
    mov     x21, x3
    mov     x22, x4
    mov     x23, x5
    ldr     x28, [x21]
    str     xzr, [x22]
    ADDRESS x0, lantern_type_BlobSidecar
    mov     x1, x20
    mov     x2, x21
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    9f
    mov     x20, x1
    ldr     x9, [x20, #BlobSidecar_index]   /* the index is below the blob limit */
.if FORK == FORK_ELECTRA
    LDQ     x10, x19, CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
.else
    LDQ     x10, x19, CONFIG_MAX_BLOBS_PER_BLOCK
.endif
    cmp     x9, x10
    b.hs    6f
    mov     x0, x20                         /* verify_blob_sidecar_inclusion_proof */
    add     x1, sp, #L
    bl      lantern_verify_blob_sidecar_inclusion_proof
    cbnz    x0, 99f
    ldr     x9, [sp, #L]
    cbz     x9, 6f
    mov     x0, x24                         /* verify_blob_kzg_proof(blob, kzg_commitment, kzg_proof) */
    ADDQ    x1, x20, BlobSidecar_blob
    ADDQ    x2, x20, BlobSidecar_kzg_commitment
    ADDQ    x3, x20, BlobSidecar_kzg_proof
    mov     x4, x21
    add     x5, sp, #L
    CALL_GLOBAL crypto_kzg_verify_blob_kzg_proof
    cmp     x0, #CRYPTO_BUFFER_TOO_SMALL
    b.eq    8f
    cbnz    x0, 6f                          /* an input that does not decode */
    ldr     x9, [sp, #L]
    cbz     x9, 6f
    ADDRESS x0, lantern_type_BeaconBlockHeader
    ADDQ    x1, x20, BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message
    mov     x2, x21
    mov     x3, x23
    CALL_GLOBAL ssz_hash_tree_root
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    8f
    b       99f
6:  mov     x9, #LANTERN_INVALID_BLOB_SIDECAR
    str     x9, [x22]
    mov     x0, #LANTERN_OK
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       99f
9:  mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x22]
    mov     x0, #LANTERN_OK
99: str     x28, [x21]
    LEAVE 16
SPEC_END node_blob_sidecar
.endif

.if FORK >= FORK_FULU
/*
 * (data, config, settings, scratch, result, root): the checks a reader of a column sidecar
 * response makes: verify_data_column_sidecar, verify_data_column_sidecar_inclusion_proof and
 * verify_data_column_sidecar_kzg_proofs; then hash_tree_root of its block header. x19 config,
 * x20 the sidecar, x21 scratch, x22 result, x23 root, x24 settings, x28 the scratch size,
 * restored on return. Locals: L an out.
 */
SPEC_FUNCTION node_column_sidecar
    ENTER 16
    mov     x20, x0
    mov     x19, x1
    mov     x24, x2
    mov     x21, x3
    mov     x22, x4
    mov     x23, x5
    ldr     x28, [x21]
    str     xzr, [x22]
    ADDRESS x0, lantern_type_DataColumnSidecar
    mov     x1, x20
    mov     x2, x21
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    9f
    mov     x20, x1
    mov     x0, x20                         /* verify_data_column_sidecar */
    mov     x1, x19
    add     x2, sp, #L
    bl      lantern_verify_data_column_sidecar
    cbnz    x0, 99f
    ldr     x9, [sp, #L]
    cbz     x9, 6f
    mov     x0, x20                         /* verify_data_column_sidecar_inclusion_proof */
    mov     x1, x21
    add     x2, sp, #L
    bl      lantern_verify_data_column_sidecar_inclusion_proof
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    8f
    cbnz    x0, 99f
    ldr     x9, [sp, #L]
    cbz     x9, 6f
    mov     x0, x20                         /* verify_data_column_sidecar_kzg_proofs */
    mov     x1, x24
    mov     x2, x21
    add     x3, sp, #L
    bl      lantern_verify_data_column_sidecar_kzg_proofs
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    8f
    cbnz    x0, 99f
    ldr     x9, [sp, #L]
    cbz     x9, 6f
    ADDRESS x0, lantern_type_BeaconBlockHeader
    ADDQ    x1, x20, DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message
    mov     x2, x21
    mov     x3, x23
    CALL_GLOBAL ssz_hash_tree_root
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    8f
    b       99f
6:  mov     x9, #LANTERN_INVALID_COLUMN_SIDECAR
    str     x9, [x22]
    mov     x0, #LANTERN_OK
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       99f
9:  mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x22]
    mov     x0, #LANTERN_OK
99: str     x28, [x21]
    LEAVE 16
SPEC_END node_column_sidecar
.endif

.if FORK >= FORK_BELLATRIX
/*
 * (data, node, id, scratch, out, result): the HTTP request of engine_newPayload for the
 * SignedBeaconBlock in data: the JSON of lantern_engine_new_payload, the JWT of the node's secret
 * at time_ms / 1000, lantern_http_post to the node's engine_host. A payload whose block_hash and
 * parent_hash are zero gives LANTERN_NO_PAYLOAD. x19 node, x20 the block, x21 scratch, x22 out,
 * x23 result, x24 id, x25 the JSON, x26 the token, x27 the host, x28 the scratch size, restored on
 * return. Locals: L the time in seconds, L+8 the JSON's size.
 */
SPEC_FUNCTION node_new_payload
    ENTER 16
    mov     x20, x0
    mov     x19, x1
    mov     x24, x2
    mov     x21, x3
    mov     x22, x4
    mov     x23, x5
    ldr     x28, [x21]
    str     xzr, [x23]
    ADDRESS x0, lantern_type_SignedBeaconBlock
    mov     x1, x20
    mov     x2, x21
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    9f
    PART    x20, x9, x1, SignedBeaconBlock_message
    PART    x11, x10, x20, BeaconBlock_body
    PART    x9, x10, x11, BeaconBlockBody_execution_payload
    ADDQ    x12, x9, ExecutionPayload_block_hash    /* no payload: zero block_hash and parent_hash */
    ldp     x10, x11, [x12]
    ldp     x13, x14, [x12, #16]
    orr     x10, x10, x11
    orr     x13, x13, x14
    orr     x10, x10, x13
    ADDQ    x12, x9, ExecutionPayload_parent_hash
    ldp     x11, x13, [x12]
    orr     x10, x10, x11
    orr     x10, x10, x13
    ldp     x11, x13, [x12, #16]
    orr     x10, x10, x11
    orr     x10, x10, x13
    cbnz    x10, 1f
    mov     x9, #LANTERN_NO_PAYLOAD
    str     x9, [x23]
    mov     x0, #LANTERN_OK
    b       99f
1:  mov     x0, x20                         /* the JSON's room, then the three lists at the end of scratch */
    add     x1, sp, #(L + 8)
    bl      lantern_engine_new_payload_size
    cbnz    x0, 99f
    ldr     x9, [sp, #(L + 8)]
    add     x9, x9, #(24 + 7)
    and     x9, x9, #~7
    add     x10, x9, #(280 + 88)
    ldr     x11, [x21]
    add     x12, x10, #4096
    cmp     x11, x12
    b.lo    8f
    sub     x11, x11, x10
    str     x11, [x21]
    add     x25, x21, x11
    add     x26, x25, x9
    add     x27, x26, #280
    mov     x12, #24
    stp     x9, x12, [x25]
    str     xzr, [x25, #16]
    mov     x9, #280
    stp     x9, x12, [x26]
    str     xzr, [x26, #16]
    mov     x9, #88
    stp     x9, x12, [x27]
    ldr     x2, [x19, #Node_engine_host_len]
    str     x2, [x27, #16]
    add     x0, x27, #24
    add     x1, x19, #Node_engine_host
    bl      lantern_copy
    mov     x0, x20                         /* the JSON */
    mov     x1, x24
    mov     x2, x21
    mov     x3, x25
    bl      lantern_engine_new_payload
    cbnz    x0, 99f
    ldr     x9, [x19, #Node_time_ms]        /* the JWT */
    mov     x10, #1000
    udiv    x9, x9, x10
    str     x9, [sp, #L]
    add     x0, x19, #Node_jwt_secret
    add     x1, sp, #L
    mov     x2, x21
    mov     x3, x26
    CALL_GLOBAL lantern_jwt_token
    cbnz    x0, 99f
    mov     x0, x27                         /* the HTTP request */
    mov     x1, x26
    mov     x2, x25
    mov     x3, x22
    CALL_GLOBAL lantern_http_post
    b       99f
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       99f
9:  mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x23]
    mov     x0, #LANTERN_OK
99: str     x28, [x21]
    LEAVE 16
SPEC_END node_new_payload
.endif
