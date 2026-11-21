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
 * (data, scratch, root) -> status: hash_tree_root of the AttestationData at data, its 128 SSZ
 * bytes, into root. scratch for ssz_hash_tree_root.
 */
SPEC_FUNCTION node_data_root
    FRAME 0
    mov     x3, x2
    mov     x2, x1
    mov     x1, x0
    ADDRESS x0, lantern_type_AttestationData
    CALL_GLOBAL ssz_hash_tree_root
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    mov     x9, #LANTERN_BUFFER_TOO_SMALL
    csel    x0, x9, x0, eq
    UNFRAME 0
SPEC_END node_data_root
.if AttestationData__mem != 128 || AttestationData__ssz != 128
.error "node_data_root: an AttestationData value is its 128 SSZ bytes"
.endif

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

/*
 * (state, out) -> status: the block number and hash of the state's latest_execution_payload_header
 * (node.md, lantern_node_payload_parent).
 */
SPEC_FUNCTION node_payload_parent
    ENTER 0
.if FORK < FORK_BELLATRIX
    mov     x0, #LANTERN_INVALID_EVENT
.else
    mov     x9, x1
    LDQ     x10, x0, BeaconState_latest_execution_payload_header   /* the header value in its part */
    add     x11, x0, x10
    MOVQ    x10, ExecutionPayloadHeader_block_number
    ldr     x10, [x11, x10]
    str     x10, [x9]
    MOVQ    x10, ExecutionPayloadHeader_block_hash
    add     x1, x11, x10
    add     x0, x9, #8
    mov     x2, #32
    bl      lantern_copy
    mov     x0, #LANTERN_OK
.endif
    LEAVE 0
SPEC_END node_payload_parent

/*
 * (ssz, scratch, out) -> status: the block root of a sidecar's SSZ bytes, hash_tree_root of its
 * signed_block_header.message (node.md, lantern_node_sidecar_root). x19 the bytes, x20 their count,
 * x21 scratch, x22 out.
 */
SPEC_FUNCTION node_sidecar_root
    ENTER 0
.if FORK < FORK_DENEB
    mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 0
.else
    ldr     x9, [x0, #8]
    add     x19, x0, x9
    ldr     x20, [x0, #16]
    mov     x21, x1
    mov     x22, x2
.if FORK < FORK_FULU
    MOVQ    x9, PUB_BLOB_SIDECAR            /* a BlobSidecar: its fixed size; the header after the index, blob, commitment and proof */
    cmp     x20, x9
    b.ne    8f
    MOVQ    x9, 8 + PUB_BLOB_BYTES + 96
    add     x1, x19, x9
.else
    cmp     x20, #PUB_COLUMN_FIXED          /* a DataColumnSidecar: the header after the index and three offsets */
    b.lo    8f
    add     x1, x19, #20
.endif
    ADDRESS x0, lantern_type_BeaconBlockHeader
    mov     x2, x21
    mov     x3, x22
    CALL_GLOBAL ssz_hash_tree_root
    LEAVE 0
8:  mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 0
.endif
SPEC_END node_sidecar_root

/* Set the byte of each index of a phase0 epoch list of PendingAttestation values: of the part at ref of the state. */
.macro LIVE_PENDING ref
    MOVQ    x9, \ref
    add     x9, x19, x9
    ldp     x12, x13, [x9]                  /* the part's offset and count */
    stp     x12, x13, [sp, #(L + 16)]
71: ldp     x12, x13, [sp, #(L + 16)]
    cbz     x13, 74f
    ldr     x15, [x19, x12]                 /* the next value starts after this one's size */
    add     x14, x12, x15
    sub     x13, x13, #1
    stp     x14, x13, [sp, #(L + 16)]
    SCRATCH_GIVE x22, x28, 2, x27           /* the bytes and the indices at the end, S(4) before them */
    mov     x0, x19
    add     x1, x19, x12
    ldr     x2, [sp, #(L + 32)]
    mov     x3, x22
    SCRATCH_LIST x4, x22, x28, 1, x27
    bl      lantern_get_attesting_indices
    str     x28, [x22]
    cbnz    x0, 99f
    SCRATCH_LIST x9, x22, x28, 1, x27
    ldr     x10, [x9, #LIST_COUNT]
    add     x9, x9, #LIST_FIXED
    mov     w12, #1
72: cbz     x10, 71b
    ldr     x11, [x9], #8
    strb    w12, [x26, x11]
    sub     x10, x10, #1
    b       72b
74:
.endm

/* Set the byte of each validator whose participation flags, of the part at ref of the state, are not 0. */
.macro LIVE_FLAGS ref
    PART    x9, x10, x19, \ref
    cmp     x10, x27
    csel    x10, x10, x27, lo
    mov     x11, #0
    mov     w13, #1
75: cmp     x11, x10
    b.hs    77f
    ldrb    w12, [x9, x11]
    cbz     w12, 76f
    strb    w13, [x26, x11]
76: add     x11, x11, #1
    b       75b
77:
.endm

/*
 * (state, config, seen, ids, epoch, scratch, out) -> status: whether the validator of each item was
 * seen live in the epoch (node.md, lantern_node_liveness). x19 the state, x20 the seen, x21 the items,
 * x22 scratch, x23 out, x24 the items' count, x25 the epoch, x26 a byte for each validator (list 0
 * of scratch), x27 the validator count, x28 the scratch's size. Locals: L the previous epoch, L+8 the
 * current epoch, L+16 the next value and the count left of an epoch list, L+32 the CommitteeCache.
 */
SPEC_FUNCTION node_liveness
    ENTER 48
    mov     x19, x0
    LDQ     x9, x1, CONFIG_COMMITTEE_CACHE
    str     x9, [sp, #(L + 32)]
    mov     x20, x2
    ldr     x9, [x3, #8]
    add     x21, x3, x9
    ldr     x24, [x3, #16]
    lsr     x24, x24, #6
    mov     x25, x4
    mov     x22, x5
    mov     x23, x6
.if FORK == FORK_PHASE0
    NEED_SCRATCH x22, x19, 6, 98f
.else
    NEED_SCRATCH x22, x19, 1, 98f
.endif
    LDQ     x27, x19, BeaconState_validators + 8
    ldr     x28, [x22]
    SCRATCH_LIST x26, x22, x28, 0, x27
    add     x26, x26, #LIST_FIXED           /* a byte for each validator, 0 */
    mov     x0, x26
    mov     x1, x27
    bl      lantern_zero
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_previous_epoch
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_current_epoch
    ldr     x9, [sp, #(L + 8)]              /* in the beacon chain: the current epoch's list */
    cmp     x25, x9
    b.ne    1f
.if FORK == FORK_PHASE0
    LIVE_PENDING BeaconState_current_epoch_attestations
.else
    LIVE_FLAGS BeaconState_current_epoch_participation
.endif
1:  ldr     x9, [sp, #L]                    /* the previous epoch's list */
    cmp     x25, x9
    b.ne    2f
.if FORK == FORK_PHASE0
    LIVE_PENDING BeaconState_previous_epoch_attestations
.else
    LIVE_FLAGS BeaconState_previous_epoch_participation
.endif
2:  PART    x9, x10, x20, Seen_keys         /* on the network and from the API: the Seen's keys */
    mov     w13, #1
3:  cbz     x10, 6f
    ldp     x11, x12, [x9]                  /* kind, a */
    ldr     x14, [x9, #16]                  /* b: the index */
    add     x9, x9, #SeenKey__mem
    sub     x10, x10, #1
    cmp     x14, x27
    b.hs    3b
    cmp     x11, #SEEN_ATTESTATION          /* an epoch's keys */
    ccmp    x11, #SEEN_AGGREGATOR_EPOCH, #4, ne
    b.eq    4f
    cmp     x11, #SEEN_PROPOSER_SLOT        /* a slot's keys */
    ccmp    x11, #SEEN_SYNC_MESSAGE, #4, ne
    ccmp    x11, #SEEN_SYNC_CONTRIBUTION, #4, ne
    b.ne    3b
    lsr     x12, x12, #LOG2_SLOTS_PER_EPOCH
4:  cmp     x12, x25
    b.ne    3b
    strb    w13, [x26, x14]
    b       3b
6:  mov     x9, #0                          /* each item: the byte of its index */
7:  cmp     x9, x24
    b.hs    8f
    lsl     x10, x9, #6
    add     x10, x21, x10
    ldr     x10, [x10, #8]
    mov     w11, #0
    cmp     x10, x27
    b.hs    79f
    ldrb    w11, [x26, x10]
79: strb    w11, [x23, x9]
    add     x9, x9, #1
    b       7b
8:  mov     x0, #LANTERN_OK
99: str     x28, [x22]
    LEAVE 48
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END node_liveness

/* ---------------------------------------------------------------- Rewards (beacon-api.md, getBlockRewards) */

/* Add reg to the u64 at off of out (x23). Uses tmp. */
.macro OUT_ADD off, reg, tmp
    ldr     \tmp, [x23, #\off]
    add     \tmp, \tmp, \reg
    str     \tmp, [x23, #\off]
.endm

.if FORK >= FORK_ALTAIR
/*
 * L1: (state x0, scratch x1) -> x0 status, x1 participant_reward, x2 proposer_reward of
 * process_sync_aggregate at the state (altair beacon-chain.md). Locals: sp+16 the total active
 * balance, sp+24 the base reward per increment, sp+32 the state, sp+40 the scratch.
 */
LOCAL_FUNCTION node_sync_values
    FRAME 32
    stp     x0, x1, [sp, #32]
    add     x2, sp, #16
    bl      lantern_get_total_active_balance
    cbnz    x0, 9f
    ldp     x0, x1, [sp, #32]
    add     x2, sp, #24
    bl      lantern_get_base_reward_per_increment
    cbnz    x0, 9f
    ldr     x9, [sp, #16]
    MOVQ    x10, EFFECTIVE_BALANCE_INCREMENT
    udiv    x9, x9, x10                     /* total_active_increments */
    ldr     x10, [sp, #24]
    mul     x9, x9, x10                     /* total_base_rewards */
    mov     x10, #SYNC_REWARD_WEIGHT
    mul     x9, x9, x10
    lsr     x9, x9, #6                      /* // WEIGHT_DENOMINATOR */
    lsr     x9, x9, #LOG2_SLOTS_PER_EPOCH   /* max_participant_rewards */
    mov     x10, #SYNC_COMMITTEE_SIZE
    udiv    x1, x9, x10                     /* participant_reward */
    mov     x10, #PROPOSER_WEIGHT
    mul     x2, x1, x10
    mov     x10, #(WEIGHT_DENOMINATOR - PROPOSER_WEIGHT)
    udiv    x2, x2, x10                     /* proposer_reward */
    mov     x0, #LANTERN_OK
9:  UNFRAME 32
END_FUNCTION node_sync_values
.endif

.if FORK == FORK_PHASE0
.if BASE_REWARDS_PER_EPOCH != 4
.error "lantern_node_block_rewards divides by BASE_REWARDS_PER_EPOCH with a shift by 2"
.endif
/*
 * Of the E st (k 1: early, its delays at x26 + 2n; k 2: late, at x26 + 3n): the square root of its
 * total active balance at root, and for each attestation of its previous_epoch_attestations each
 * attesting index below n takes the attestation's inclusion_delay when that is lower.
 */
.macro REWARD_LOWEST st, k, root
    cbz     \st, 39f
    SCRATCH_GIVE x22, x28, 2, x27
    mov     x0, \st
    mov     x1, x22
    add     x2, sp, #(L + 120)
    bl      lantern_get_total_active_balance
    str     x28, [x22]
    cbnz    x0, 99f
    add     x0, sp, #(L + 120)
    add     x1, sp, #\root
    bl      lantern_integer_squareroot
    MOVQ    x9, BeaconState_previous_epoch_attestations
    add     x9, \st, x9
    ldp     x12, x13, [x9]                  /* the part's offset and count */
    stp     x12, x13, [sp, #(L + 16)]
32: ldp     x12, x13, [sp, #(L + 16)]
    cbz     x13, 39f
    ldr     x15, [\st, x12]                /* the next value starts after this one's size */
    add     x14, x12, x15
    sub     x13, x13, #1
    stp     x14, x13, [sp, #(L + 16)]
    add     x9, \st, x12
    str     x9, [sp, #(L + 128)]
    SCRATCH_GIVE x22, x28, 2, x27
    mov     x0, \st
    mov     x1, x9
    ldr     x2, [sp, #(L + 96)]
    mov     x3, x22
    SCRATCH_LIST x4, x22, x28, 1, x27
    bl      lantern_get_attesting_indices
    str     x28, [x22]
    cbnz    x0, 99f
    ldr     x9, [sp, #(L + 128)]
    ldr     x11, [x9, #PendingAttestation_inclusion_delay]
.if \k == 1
    add     x12, x26, x27, lsl #1
.else
    add     x12, x27, x27, lsl #1
    add     x12, x26, x12
.endif
    SCRATCH_LIST x9, x22, x28, 1, x27
    ldr     x10, [x9, #LIST_COUNT]
    add     x9, x9, #LIST_FIXED
33: cbz     x10, 32b
    ldr     x13, [x9], #8
    sub     x10, x10, #1
    cmp     x13, x27
    b.hs    33b
    ldrb    w14, [x12, x13]
    cmp     x11, x14
    b.hs    33b
    strb    w11, [x12, x13]
    b       33b
39:
.endm
.endif

/*
 * (pre, block, early, late, config, scratch, out) -> status: the proposer's rewards of the block on
 * its pre-state, part by part (node.md, lantern_node_block_rewards). x19 pre, x20 the body, x21
 * config, x22 scratch, x23 out, x24 early, x25 late, x26 the bytes of the validators (list 0: the
 * slashed marks at 0; from altair the copies of the previous and current participation at n and 2n;
 * in phase0 the rewarded marks at n, bit 0 for the epoch before the block's and bit 1 for its own,
 * and the lowest delays of early and late at 2n and 3n), x27 the validator count n, x28 the
 * scratch's size after the decoded block. Locals: L the scratch's size on entry, L+8 the epoch,
 * L+16 the next entry of a list and L+24 the count left, L+32 the base reward per increment
 * (phase0: the square root of early's total active balance, L+40 of late's), L+48 the flags
 * (FLAGS_BYTES), L+96 the CommitteeCache, L+104 the inclusion delay, L+120 a value, L+128 the
 * attestation, L+136 its E, L+144 its lowest delays, L+152 its bit.
 */
SPEC_FUNCTION node_block_rewards
    ENTER 160
    mov     x19, x0
    mov     x24, x2
    mov     x25, x3
    mov     x21, x4
    mov     x22, x5
    mov     x23, x6
    ldr     x9, [x22]
    str     x9, [sp, #L]
    ldr     x9, [x21, #CONFIG_COMMITTEE_CACHE]
    str     x9, [sp, #(L + 96)]
    ADDRESS x0, lantern_type_SignedBeaconBlock
    mov     x2, x22
    bl      node_decode
    cmp     x0, #1
    b.eq    97f
    b.hi    96f
    PART    x9, x10, x1, SignedBeaconBlock_message
    ldr     x10, [x9, #BeaconBlock_slot]
    LDQ     x11, x19, BeaconState_slot
    cmp     x10, x11
    b.ne    95f
    PART    x20, x10, x9, BeaconBlock_body
    ldr     x10, [x9, #BeaconBlock_proposer_index]
    str     x10, [sp, #(L + 120)]
    ldr     x28, [x22]
    NEED_SCRATCH x22, x19, 6, 97f
.if FORK == FORK_PHASE0
    cbz     x24, 1f
    NEED_SCRATCH x22, x24, 6, 97f
1:  cbz     x25, 2f
    NEED_SCRATCH x22, x25, 6, 97f
2:
.endif
    ldr     x10, [sp, #(L + 120)]
    stp     x10, xzr, [x23]
    stp     xzr, xzr, [x23, #16]
    stp     xzr, xzr, [x23, #32]
    LDQ     x27, x19, BeaconState_validators + 8
    SCRATCH_LIST x26, x22, x28, 0, x27
    add     x26, x26, #LIST_FIXED
    mov     x0, x26
    lsl     x1, x27, #2
    bl      lantern_zero
    mov     x0, x19
    add     x1, sp, #(L + 8)
    bl      lantern_get_current_epoch
    PART    x9, x10, x20, BeaconBlockBody_proposer_slashings    /* proposer_slashings: each whistleblower_reward */
    PART    x12, x13, x19, BeaconState_validators
3:  cbz     x10, 4f
    ldr     x11, [x9, #(ProposerSlashing_signed_header_1 + SignedBeaconBlockHeader_message + BeaconBlockHeader_proposer_index)]
    cmp     x11, x27
    b.hs    96f
    add     x14, x12, x11, lsl #7
    ldr     x14, [x14, #Validator_effective_balance]
    MOVQ    x15, FORK_WHISTLEBLOWER_REWARD_QUOTIENT
    udiv    x14, x14, x15
    OUT_ADD 32, x14, x15
    mov     w14, #1
    strb    w14, [x26, x11]
    MOVQ    x14, ProposerSlashing__mem
    add     x9, x9, x14
    sub     x10, x10, #1
    b       3b
4:  PART    x9, x10, x20, BeaconBlockBody_attester_slashings    /* attester_slashings: those process_attester_slashing slashes */
    stp     x9, x10, [sp, #(L + 16)]
5:  ldp     x9, x10, [sp, #(L + 16)]
    cbz     x10, 10f
    ldr     x11, [x9]
    add     x11, x9, x11
    sub     x10, x10, #1
    stp     x11, x10, [sp, #(L + 16)]
    PART    x0, x1, x9, AttesterSlashing_attestation_1
    PART    x2, x3, x9, AttesterSlashing_attestation_2
    PART    x4, x5, x0, IndexedAttestation_attesting_indices
    add     x5, x4, x5, lsl #3
    PART    x6, x7, x2, IndexedAttestation_attesting_indices
    add     x7, x6, x7, lsl #3
    PART    x8, x1, x19, BeaconState_validators
    ldr     x11, [sp, #(L + 8)]
6:  cmp     x4, x5                          /* the sorted intersection, by merge */
    b.hs    5b
    cmp     x6, x7
    b.hs    5b
    ldr     x12, [x4]
    ldr     x13, [x6]
    cmp     x12, x13
    b.lo    61f
    b.hi    62f
    add     x4, x4, #8
    add     x6, x6, #8
    cmp     x12, x27
    b.hs    96f
    ldrb    w13, [x26, x12]                 /* an earlier slashing of the body slashed it */
    cbnz    w13, 6b
    add     x13, x8, x12, lsl #7            /* is_slashable_validator(validator, epoch) */
    ldrb    w14, [x13, #Validator_slashed]
    cbnz    w14, 6b
    ldr     x14, [x13, #Validator_activation_epoch]
    cmp     x14, x11
    b.hi    6b
    ldr     x14, [x13, #Validator_withdrawable_epoch]
    cmp     x11, x14
    b.hs    6b
    mov     w14, #1
    strb    w14, [x26, x12]
    ldr     x14, [x13, #Validator_effective_balance]
    MOVQ    x13, FORK_WHISTLEBLOWER_REWARD_QUOTIENT
    udiv    x14, x14, x13
    OUT_ADD 40, x14, x13
    b       6b
61: add     x4, x4, #8
    b       6b
62: add     x6, x6, #8
    b       6b
10:
.if FORK >= FORK_ALTAIR
    SCRATCH_GIVE x22, x28, 2, x27           /* sync_aggregate: the set bits times proposer_reward */
    mov     x0, x19
    mov     x1, x22
    bl      node_sync_values
    str     x28, [x22]
    cbnz    x0, 99f
    MOVQ    x9, BeaconBlockBody_sync_aggregate + SyncAggregate_sync_committee_bits
    add     x9, x20, x9
    mov     x10, #0
    mov     x11, #(SYNC_COMMITTEE_SIZE / 8)
11: cbz     x11, 13f
    ldrb    w12, [x9], #1
12: cbz     x12, 121f
    sub     x13, x12, #1
    and     x12, x12, x13
    add     x10, x10, #1
    b       12b
121: sub    x11, x11, #1
    b       11b
13: mul     x10, x10, x2
    str     x10, [x23, #24]
    PART    x1, x2, x19, BeaconState_previous_epoch_participation  /* copies of the flags */
    cmp     x2, x27
    csel    x2, x2, x27, lo
    add     x0, x26, x27
    bl      lantern_copy
    PART    x1, x2, x19, BeaconState_current_epoch_participation
    cmp     x2, x27
    csel    x2, x2, x27, lo
    add     x0, x26, x27, lsl #1
    bl      lantern_copy
    SCRATCH_GIVE x22, x28, 2, x27
    mov     x0, x19
    mov     x1, x22
    add     x2, sp, #(L + 32)
    bl      lantern_get_base_reward_per_increment
    str     x28, [x22]
    cbnz    x0, 99f
    PART    x9, x10, x20, BeaconBlockBody_attestations  /* attestations: process_attestation's proposer_reward of each */
    stp     x9, x10, [sp, #(L + 16)]
20: ldp     x9, x10, [sp, #(L + 16)]
    cbz     x10, 90f
    str     x9, [sp, #(L + 128)]
    ldr     x11, [x9]
    add     x11, x9, x11
    sub     x10, x10, #1
    stp     x11, x10, [sp, #(L + 16)]
    LDQ     x11, x19, BeaconState_slot
    ldr     x12, [x9, #(Attestation_data + AttestationData_slot)]
    sub     x11, x11, x12
    str     x11, [sp, #(L + 104)]
    MOVQ    x11, FLAGS_BYTES
    str     x11, [sp, #(L + 48)]
    mov     x0, x19
    add     x1, x9, #Attestation_data
    add     x2, sp, #(L + 104)
    add     x3, sp, #(L + 48)
    bl      lantern_get_attestation_participation_flag_indices
    cbnz    x0, 99f
    SCRATCH_GIVE x22, x28, 2, x27
    mov     x0, x19
    ldr     x1, [sp, #(L + 128)]
    ldr     x2, [sp, #(L + 96)]
    mov     x3, x22
    SCRATCH_LIST x4, x22, x28, 1, x27
    bl      lantern_get_attesting_indices
    str     x28, [x22]
    cbnz    x0, 99f
    ldr     x9, [sp, #(L + 128)]            /* the copy of the target epoch's flags */
    ldr     x10, [x9, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
    ldr     x11, [sp, #(L + 8)]
    add     x12, x26, x27, lsl #1
    add     x13, x26, x27
    cmp     x10, x11
    csel    x12, x12, x13, eq
    ldr     x2, [sp, #(L + 48 + LIST_COUNT)]    /* the flags as bits */
    add     x3, sp, #(L + 48 + LIST_FIXED)
    mov     x1, #0
21: cbz     x2, 22f
    ldr     x4, [x3], #8
    mov     x5, #1
    lsl     x5, x5, x4
    orr     x1, x1, x5
    sub     x2, x2, #1
    b       21b
22: SCRATCH_LIST x9, x22, x28, 1, x27
    ldr     x10, [x9, #LIST_COUNT]
    add     x9, x9, #LIST_FIXED
    mov     x13, #0                         /* proposer_reward_numerator */
    PART    x14, x15, x19, BeaconState_validators
23: cbz     x10, 29f
    ldr     x2, [x9], #8
    sub     x10, x10, #1
    cmp     x2, x27
    b.hs    96f
    ldrb    w3, [x12, x2]
    bic     x4, x1, x3                      /* the flags it takes now */
    cbz     x4, 23b
    orr     w3, w3, w4
    strb    w3, [x12, x2]
    add     x5, x14, x2, lsl #7
    ldr     x5, [x5, #Validator_effective_balance]
    MOVQ    x6, EFFECTIVE_BALANCE_INCREMENT
    udiv    x5, x5, x6
    ldr     x6, [sp, #(L + 32)]
    mul     x5, x5, x6                      /* get_base_reward(state, index) */
    mov     x6, #0
    tbz     x4, #TIMELY_SOURCE_FLAG_INDEX, 24f
    add     x6, x6, #TIMELY_SOURCE_WEIGHT
24: tbz     x4, #TIMELY_TARGET_FLAG_INDEX, 25f
    add     x6, x6, #TIMELY_TARGET_WEIGHT
25: tbz     x4, #TIMELY_HEAD_FLAG_INDEX, 26f
    add     x6, x6, #TIMELY_HEAD_WEIGHT
26: mul     x5, x5, x6
    add     x13, x13, x5
    b       23b
29: mov     x6, #((WEIGHT_DENOMINATOR - PROPOSER_WEIGHT) * WEIGHT_DENOMINATOR / PROPOSER_WEIGHT)
    udiv    x13, x13, x6
    OUT_ADD 16, x13, x6
    b       20b
.else
    add     x9, x26, x27, lsl #1            /* the lowest delays of early and late: none yet */
    lsl     x10, x27, #1
    mov     w11, #255
30: cbz     x10, 31f
    strb    w11, [x9], #1
    sub     x10, x10, #1
    b       30b
31: REWARD_LOWEST x24, 1, (L + 32)
    REWARD_LOWEST x25, 2, (L + 40)
    PART    x9, x10, x20, BeaconBlockBody_attestations  /* attestations: the proposer rewards of get_inclusion_delay_deltas */
    stp     x9, x10, [sp, #(L + 16)]
40: ldp     x9, x10, [sp, #(L + 16)]
    cbz     x10, 90f
    str     x9, [sp, #(L + 128)]
    ldr     x11, [x9]
    add     x11, x9, x11
    sub     x10, x10, #1
    stp     x11, x10, [sp, #(L + 16)]
    ldr     x10, [x9, #(Attestation_data + AttestationData_target + Checkpoint_epoch)]
    ldr     x11, [sp, #(L + 8)]
    cmp     x10, x11
    b.eq    41f
    add     x12, x10, #1
    cmp     x12, x11
    b.ne    95f
    mov     x13, x24                        /* the epoch before the block's: early */
    add     x14, x26, x27, lsl #1
    mov     x15, #1
    b       42f
41: mov     x13, x25                        /* the block's epoch: late */
    add     x14, x27, x27, lsl #1
    add     x14, x26, x14
    mov     x15, #2
42: cbnz    x13, 43f
    ldr     x12, [x21, #CONFIG_ALTAIR_FORK_EPOCH]   /* no E: the epoch after the target's is altair's or later */
    add     x11, x10, #1
    cmp     x12, x11
    b.hi    95f
    b       40b
43: LDQ     x11, x13, BeaconState_slot      /* E at the last slot of the epoch after the target's */
    add     x12, x10, #2
    lsl     x12, x12, #LOG2_SLOTS_PER_EPOCH
    sub     x12, x12, #1
    cmp     x11, x12
    b.ne    95f
    stp     x13, x14, [sp, #(L + 136)]
    str     x15, [sp, #(L + 152)]
    LDQ     x11, x19, BeaconState_slot
    ldr     x12, [x9, #(Attestation_data + AttestationData_slot)]
    sub     x11, x11, x12
    str     x11, [sp, #(L + 104)]
    SCRATCH_GIVE x22, x28, 2, x27
    mov     x0, x19
    mov     x1, x9
    ldr     x2, [sp, #(L + 96)]
    mov     x3, x22
    SCRATCH_LIST x4, x22, x28, 1, x27
    bl      lantern_get_attesting_indices
    str     x28, [x22]
    cbnz    x0, 99f
    ldr     x15, [sp, #(L + 152)]
    ldr     x5, [sp, #(L + 32)]
    ldr     x6, [sp, #(L + 40)]
    cmp     x15, #1
    csel    x5, x5, x6, eq                  /* the square root of E's total active balance */
    ldp     x13, x14, [sp, #(L + 136)]
    PART    x7, x8, x13, BeaconState_validators
    ldr     x11, [sp, #(L + 104)]
    SCRATCH_LIST x9, x22, x28, 1, x27
    ldr     x10, [x9, #LIST_COUNT]
    add     x9, x9, #LIST_FIXED
    add     x12, x26, x27                   /* the rewarded marks */
44: cbz     x10, 40b
    ldr     x1, [x9], #8
    sub     x10, x10, #1
    cmp     x1, x27
    b.hs    96f
    ldrb    w2, [x12, x1]
    tst     x2, x15
    b.ne    44b
    orr     w2, w2, w15
    strb    w2, [x12, x1]
    cmp     x1, x8
    b.hs    96f
    add     x3, x7, x1, lsl #7
    ldrb    w4, [x3, #Validator_slashed]    /* unslashed in E */
    cbnz    w4, 44b
    ldrb    w4, [x14, x1]                   /* and no attestation of E with a lower delay */
    cmp     x4, x11
    b.lo    44b
    ldr     x3, [x3, #Validator_effective_balance]
    mov     x4, #BASE_REWARD_FACTOR
    mul     x3, x3, x4
    udiv    x3, x3, x5
    lsr     x3, x3, #2                      /* get_base_reward(E, index): // BASE_REWARDS_PER_EPOCH, which is 4 */
    mov     x4, #PROPOSER_REWARD_QUOTIENT
    udiv    x3, x3, x4
    OUT_ADD 16, x3, x4
    b       44b
.endif
90: ldp     x9, x10, [x23, #16]             /* total */
    ldp     x11, x12, [x23, #32]
    add     x9, x9, x10
    add     x9, x9, x11
    add     x9, x9, x12
    str     x9, [x23, #8]
    mov     x0, #LANTERN_OK
99: ldr     x9, [sp, #L]
    str     x9, [x22]
    LEAVE 160
95: mov     x0, #LANTERN_INVALID_SLOT
    b       99b
96: mov     x0, #LANTERN_INVALID_ENCODING
    b       99b
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       99b
SPEC_END node_block_rewards

.if FORK >= FORK_ALTAIR
/*
 * L0: the entry of the validator x0 among the x2 entries of 24 bytes at x1 (index, balance, member),
 * a new one with its balance in the state x3 and member 0 when there is none: x0 = the entry, x2 =
 * the count; x0 = 0 for an index past the validators. Uses x4-x7, x16.
 */
LOCAL_FUNCTION node_reward_entry
    UNWIND_END_PROLOGUE
    mov     x4, x1
    mov     x5, x2
1:  cbz     x5, 2f
    ldr     x6, [x4]
    cmp     x6, x0
    b.eq    3f
    add     x4, x4, #24
    sub     x5, x5, #1
    b       1b
2:  PART    x6, x7, x3, BeaconState_balances
    cmp     x0, x7
    b.hs    4f
    ldr     x6, [x6, x0, lsl #3]
    stp     x0, x6, [x4]
    str     xzr, [x4, #16]
    add     x2, x2, #1
3:  mov     x0, x4
    ret
4:  mov     x0, #0
    ret
END_FUNCTION node_reward_entry

.set SYNC_REWARD_EXTRA, 8 * SYNC_COMMITTEE_SIZE + SYNC_TABLE_BYTES + 24   /* the places, the table of find_pubkeys and its 3 words */
.if 24 * (SYNC_COMMITTEE_SIZE + 1) > SYNC_TABLE_BYTES
.error "lantern_node_sync_rewards keeps its entries where the table of find_pubkeys was"
.endif

/*
 * (pre, block, scratch, out) -> status: the balance changes of the block's sync aggregate on its
 * pre-state (node.md, lantern_node_sync_rewards). x19 pre, x20 the bits, x21 out, x22 scratch, x23
 * the places' validator indices (at the end of scratch, before the decoded block), x24 the hash
 * table of find_pubkeys, then the entries of node_reward_entry, x25 their count, x26
 * participant_reward, x27 proposer_reward, x28 the proposer. Locals: L the scratch's size on entry,
 * L+8 the proposer rewards it took.
 */
SPEC_FUNCTION node_sync_rewards
    ENTER 16
    mov     x19, x0
    mov     x22, x2
    mov     x21, x3
    ldr     x9, [x22]
    str     x9, [sp, #L]
    ldr     x9, [x21]
    MOVQ    x10, 24 + 16 * SYNC_COMMITTEE_SIZE
    cmp     x9, x10
    b.lo    97f
    ADDRESS x0, lantern_type_SignedBeaconBlock
    mov     x2, x22
    bl      node_decode
    cmp     x0, #1
    b.eq    97f
    b.hi    96f
    PART    x9, x10, x1, SignedBeaconBlock_message
    ldr     x10, [x9, #BeaconBlock_slot]
    LDQ     x11, x19, BeaconState_slot
    cmp     x10, x11
    b.ne    95f
    ldr     x28, [x9, #BeaconBlock_proposer_index]
    PART    x20, x10, x9, BeaconBlock_body
    MOVQ    x10, BeaconBlockBody_sync_aggregate + SyncAggregate_sync_committee_bits
    add     x20, x20, x10
    NEED_SCRATCH_B x22, x19, 1, SYNC_REWARD_EXTRA, 97f
    ldr     x9, [x22]                       /* the places, then the table, at the end */
    MOVQ    x10, 8 * SYNC_COMMITTEE_SIZE
    sub     x9, x9, x10
    add     x23, x22, x9
    MOVQ    x10, SYNC_TABLE_BYTES + 24
    sub     x9, x9, x10
    add     x24, x22, x9
    str     x9, [x22]                       /* what callees get */
    mov     x0, x19                         /* committee_indices, as process_sync_aggregate finds them */
    MOVQ    x1, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    add     x1, x19, x1
    mov     x2, x23
    mov     x3, x24
    bl      find_pubkeys
    cbnz    x0, 96f
    mov     x0, x19
    mov     x1, x22
    bl      node_sync_values
    cbnz    x0, 99f
    mov     x26, x1
    mov     x27, x2
    str     xzr, [sp, #(L + 8)]
    mov     x25, #0
    mov     x9, #0                          /* each place, in order */
1:  cmp     x9, #SYNC_COMMITTEE_SIZE
    b.hs    5f
    ldr     x0, [x23, x9, lsl #3]
    mov     x1, x24
    mov     x2, x25
    mov     x3, x19
    bl      node_reward_entry
    mov     x25, x2
    cbz     x0, 96f
    mov     x10, #1
    str     x10, [x0, #16]                  /* a member */
    lsr     x10, x9, #3
    ldrb    w10, [x20, x10]
    and     x11, x9, #7
    lsr     w10, w10, w11
    tbz     w10, #0, 3f
    ldr     x10, [x0, #8]                   /* the participant takes participant_reward, the proposer proposer_reward */
    add     x10, x10, x26
    str     x10, [x0, #8]
    mov     x0, x28
    mov     x1, x24
    mov     x2, x25
    mov     x3, x19
    bl      node_reward_entry
    mov     x25, x2
    cbz     x0, 96f
    ldr     x10, [x0, #8]
    add     x10, x10, x27
    str     x10, [x0, #8]
    ldr     x10, [sp, #(L + 8)]
    add     x10, x10, x27
    str     x10, [sp, #(L + 8)]
    b       4f
3:  ldr     x10, [x0, #8]                   /* decrease_balance: down to 0 at the least */
    subs    x10, x10, x26
    csel    x10, x10, xzr, hs
    str     x10, [x0, #8]
4:  add     x9, x9, #1
    b       1b
5:  PART    x8, x7, x19, BeaconState_balances   /* the members in index order: the lowest after the last */
    mov     x0, #0                          /* 1 once one is written */
    mov     x1, #0                          /* the last written */
    add     x2, x21, #24
6:  mov     x3, #-1
    mov     x4, #0
    mov     x5, x24
    mov     x6, x25
7:  cbz     x6, 9f
    ldr     x7, [x5]
    ldr     x9, [x5, #16]
    cbz     x9, 8f
    cbz     x0, 71f
    cmp     x7, x1
    b.ls    8f
71: cmp     x7, x3
    b.hs    8f
    mov     x3, x7
    mov     x4, x5
8:  add     x5, x5, #24
    sub     x6, x6, #1
    b       7b
9:  cbz     x4, 11f
    ldr     x5, [x8, x3, lsl #3]
    ldr     x7, [x4, #8]
    sub     x7, x7, x5                      /* after less before */
    cmp     x3, x28
    b.ne    10f
    ldr     x9, [sp, #(L + 8)]              /* the proposer: less the proposer rewards */
    sub     x7, x7, x9
10: stp     x3, x7, [x2], #16
    mov     x0, #1
    mov     x1, x3
    b       6b
11: sub     x3, x2, x21
    sub     x3, x3, #24
    mov     x4, #24
    stp     x4, x3, [x21, #8]
    mov     x0, #LANTERN_OK
99: ldr     x9, [sp, #L]
    str     x9, [x22]
    LEAVE 16
95: mov     x0, #LANTERN_INVALID_SLOT
    b       99b
96: mov     x0, #LANTERN_INVALID_ENCODING
    b       99b
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       99b
SPEC_END node_sync_rewards
.else
/* (pre, block, scratch, out) -> LANTERN_NO_STATE_ANSWER: phase0 has no sync committee (node.md, lantern_node_sync_rewards). */
SPEC_FUNCTION node_sync_rewards
    FRAME 0
    mov     x0, #LANTERN_NO_STATE_ANSWER
    UNFRAME 0
SPEC_END node_sync_rewards
.endif

/* ---------------------------------------------------------------- Attestation rewards (beacon-api.md, getAttestationsRewards) */

.if FORK >= FORK_ALTAIR
/* The participating balance of the flag at the previous epoch into out + off: get_total_balance of the unslashed participating indices. */
.macro TOTALS_FLAG flag, epoch, base, off
    mov     x9, #\flag
    str     x9, [sp, #(L + 8)]
    SCRATCH_GIVE x21, x25, 1, x24
    mov     x0, x19
    add     x1, sp, #(L + 8)
    mov     x2, \epoch
    mov     x3, x21
    mov     x4, x26
    bl      lantern_get_unslashed_participating_indices
    str     x25, [x21]
    cbnz    x0, 99f
    mov     x0, x19
    mov     x1, x26
    add     x2, \base, \off
    bl      lantern_get_total_balance
.endm
.else
/* The attesting balance of the attestations of getter at the epoch into the u64 at addr: lantern_get_attesting_balance. */
.macro TOTALS_PENDING getter, epoch, base, off
    mov     x0, x19
    mov     x1, \epoch
    mov     x2, x26
    bl      \getter
    cbnz    x0, 99f
    str     x27, [x21]
    mov     x0, x19
    mov     x1, x26
    mov     x2, x21
    add     x3, \base, \off
    bl      lantern_get_attesting_balance
    cbnz    x0, 99f
.endm
.endif

/*
 * (state, config, mode, scratch, out) -> status: the totals of the attestation rewards of the
 * previous epoch (node.md, lantern_node_reward_totals). x19 state, x20 config, x21 scratch, x22
 * out, x23 mode, x24 the validator count, x25 the scratch's size, x26 a list of indices (phase0:
 * the matching attestations), x27 (phase0) the scratch's size before them. Locals: L the current
 * epoch, L+8 a flag, L+16 the current epoch's target balance.
 */
SPEC_FUNCTION node_reward_totals
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x23, x2
    mov     x21, x3
    mov     x22, x4
.if FORK == FORK_PHASE0
    NEED_SCRATCH_B x21, x19, 6, PENDING_REFS_BYTES, 9f
.else
    NEED_SCRATCH x21, x19, 3, 9f
.endif
    ldr     x25, [x21]
    LDQ     x24, x19, BeaconState_validators + 8
    str     xzr, [sp, #(L + 16)]
    mov     x0, x19
    mov     x1, x22
    bl      lantern_get_previous_epoch
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    str     x23, [x22, #64]
    ldr     x9, [x20, #CONFIG_INACTIVITY_SCORE_BIAS]
    ldr     x10, [x20, #CONFIG_INACTIVITY_SCORE_RECOVERY_RATE]
    stp     x9, x10, [x22, #80]
    MOVQ    x9, MAX_EFFECTIVE_BALANCE       /* the largest effective balance of the fork of the previous epoch */
.if FORK >= FORK_ELECTRA
    MOVQ    x9, MAX_EFFECTIVE_BALANCE_ELECTRA
.if FORK == FORK_ELECTRA
    LDQ     x10, x19, BeaconState_fork + Fork_epoch     /* before the state's fork: deneb's */
    ldr     x11, [x22]
    cmp     x11, x10
    b.hs    1f
    MOVQ    x9, MAX_EFFECTIVE_BALANCE
1:
.endif
.endif
    str     x9, [x22, #72]
    mov     x0, x19
    mov     x1, x21
    add     x2, x22, #24
    bl      lantern_get_total_active_balance
    cbnz    x0, 99f
.if FORK == FORK_PHASE0
    add     x0, x22, #24
    add     x1, x22, #32
    bl      lantern_integer_squareroot
    TAKE_REFS x26, x21, x27
    TOTALS_PENDING lantern_get_matching_source_attestations, x22, x22, #40
    TOTALS_PENDING lantern_get_matching_target_attestations, x22, x22, #48
    TOTALS_PENDING lantern_get_matching_head_attestations, x22, x22, #56
    cbz     x23, 5f
    ldr     x9, [sp, #L]
    cmp     x9, #(GENESIS_EPOCH + 1)
    b.ls    5f
    add     x10, sp, #L
    TOTALS_PENDING lantern_get_matching_target_attestations, x10, sp, #(L + 16)
.else
    mov     x0, x19
    mov     x1, x21
    add     x2, x22, #32
    bl      lantern_get_base_reward_per_increment
    cbnz    x0, 99f
    SCRATCH_LIST x26, x21, x25, 0, x24
    TOTALS_FLAG TIMELY_SOURCE_FLAG_INDEX, x22, x22, #40
    TOTALS_FLAG TIMELY_TARGET_FLAG_INDEX, x22, x22, #48
    TOTALS_FLAG TIMELY_HEAD_FLAG_INDEX, x22, x22, #56
    cbz     x23, 5f
    ldr     x9, [sp, #L]
    cmp     x9, #(GENESIS_EPOCH + 1)
    b.ls    5f
    add     x10, sp, #L
    TOTALS_FLAG TIMELY_TARGET_FLAG_INDEX, x10, sp, #(L + 16)
.endif
5:  LDQ     x12, x19, BeaconState_finalized_checkpoint + Checkpoint_epoch
    cbz     x23, 6f                         /* mode 1: the finalized epoch weigh_justification_and_finalization would leave */
    ldr     x13, [sp, #L]
    cmp     x13, #(GENESIS_EPOCH + 1)
    b.ls    6f
    ADDQ    x9, x19, BeaconState_justification_bits
    ldrb    w14, [x9]
    lsl     w14, w14, #1
    and     w14, w14, #0xf
    ldr     x10, [x22, #24]
    lsl     x10, x10, #1                    /* total * 2 */
    mov     x9, #3
    ldr     x11, [x22, #48]
    mul     x11, x11, x9
    cmp     x11, x10
    b.lo    51f
    orr     w14, w14, #2
51: ldr     x11, [sp, #(L + 16)]
    mul     x11, x11, x9
    cmp     x11, x10
    b.lo    52f
    orr     w14, w14, #1
52: LDQ     x9, x19, BeaconState_previous_justified_checkpoint + Checkpoint_epoch
    LDQ     x10, x19, BeaconState_current_justified_checkpoint + Checkpoint_epoch
    and     w11, w14, #0xe                  /* the four rules in spec order: bits[1:4], bits[1:3], bits[0:3], bits[0:2] */
    cmp     w11, #0xe
    b.ne    53f
    add     x15, x9, #3
    cmp     x15, x13
    csel    x12, x9, x12, eq
53: and     w11, w14, #0x6
    cmp     w11, #0x6
    b.ne    54f
    add     x15, x9, #2
    cmp     x15, x13
    csel    x12, x9, x12, eq
54: and     w11, w14, #0x7
    cmp     w11, #0x7
    b.ne    55f
    add     x15, x10, #2
    cmp     x15, x13
    csel    x12, x10, x12, eq
55: and     w11, w14, #0x3
    cmp     w11, #0x3
    b.ne    6f
    add     x15, x10, #1
    cmp     x15, x13
    csel    x12, x10, x12, eq
6:  ldr     x9, [x22]                       /* get_finality_delay, and the leak */
    sub     x9, x9, x12
    str     x9, [x22, #8]
    cmp     x9, #MIN_EPOCHS_TO_INACTIVITY_PENALTY
    cset    x9, hi
    str     x9, [x22, #16]
    mov     x0, #LANTERN_OK
99: str     x25, [x21]
    LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END node_reward_totals

.if FORK == FORK_PHASE0
/* The vote's item at ioff: base_reward in a leak, else base_reward * its attesting increments // the active increments. */
.macro IDEAL_VOTE boff, ioff
    ldr     x10, [x0, #\boff]
    udiv    x10, x10, x3
    mul     x10, x6, x10
    udiv    x10, x10, x4
    cmp     x5, #0
    csel    x10, x6, x10, ne
    str     x10, [x2, #\ioff]
.endm
.else
/* The flag's item at ioff: 0 in a leak, else base_reward * weight * its increments // (active_increments * WEIGHT_DENOMINATOR). */
.macro IDEAL_FLAG boff, weight, ioff
    ldr     x10, [x0, #\boff]
    udiv    x10, x10, x3
    mov     x11, #\weight
    mul     x11, x6, x11
    mul     x10, x11, x10
    udiv    x10, x10, x4
    cmp     x5, #0
    csel    x10, xzr, x10, ne
    str     x10, [x2, #\ioff]
.endm
.endif

/*
 * (totals, effective_balance, out) -> status: the item of a validator of the effective balance that
 * voted for all three in time (node.md, lantern_node_ideal_reward). A leaf: uses x3-x11.
 */
SPEC_FUNCTION node_ideal_reward
    UNWIND_END_PROLOGUE
    MOVQ    x3, EFFECTIVE_BALANCE_INCREMENT
    ldr     x4, [x0, #24]
    udiv    x4, x4, x3                      /* the active increments */
    ldr     x5, [x0, #16]                   /* the leak */
    str     x1, [x2, #40]
.if FORK == FORK_PHASE0
    mov     x6, #BASE_REWARD_FACTOR         /* get_base_reward */
    mul     x6, x1, x6
    ldr     x7, [x0, #32]
    udiv    x6, x6, x7
    lsr     x6, x6, #2
    lsr     x7, x6, #3                      /* get_proposer_reward: // PROPOSER_REWARD_QUOTIENT */
    IDEAL_VOTE 56, 0
    IDEAL_VOTE 48, 8
    IDEAL_VOTE 40, 16
    sub     x9, x6, x7                      /* inclusion_delay at a delay of 1 */
    str     x9, [x2, #24]
    lsl     x9, x6, #2                      /* inactivity in a leak: -(BASE_REWARDS_PER_EPOCH * base_reward - the proposer's) */
    sub     x9, x9, x7
    neg     x9, x9
    cmp     x5, #0
    csel    x9, x9, xzr, ne
    str     x9, [x2, #32]
.else
    udiv    x6, x1, x3                      /* base_reward: increments * get_base_reward_per_increment */
    ldr     x7, [x0, #32]
    mul     x6, x6, x7
    lsl     x4, x4, #6
    IDEAL_FLAG 56, TIMELY_HEAD_WEIGHT, 0
    IDEAL_FLAG 48, TIMELY_TARGET_WEIGHT, 8
    IDEAL_FLAG 40, TIMELY_SOURCE_WEIGHT, 16
    stp     xzr, xzr, [x2, #24]
.endif
    mov     x0, #LANTERN_OK
    ret
SPEC_END node_ideal_reward

.if FORK == FORK_PHASE0
/* Each validator of the window among the attesting indices of the attestations of getter: its status byte takes bit; with lowest 1, its delay byte the lowest inclusion_delay. */
.macro WINDOW_MARK getter, bit, lowest
    mov     x0, x19
    mov     x1, x21
    mov     x2, x26
    bl      \getter
    cbnz    x0, 99f
    add     x9, x26, #LIST_FIXED
    ldr     x10, [x26, #LIST_COUNT]
    stp     x9, x10, [sp, #(L + 16)]
71: ldp     x9, x10, [sp, #(L + 16)]
    cbz     x10, 79f
    ldr     x11, [x9], #8
    sub     x10, x10, #1
    stp     x9, x10, [sp, #(L + 16)]
    add     x1, x19, x11
    str     x1, [sp, #(L + 32)]
    SCRATCH_GIVE x24, x28, 2, x27
    mov     x0, x19
    mov     x2, x20
    mov     x3, x24
    SCRATCH_LIST x4, x24, x28, 1, x27
    bl      lantern_get_attesting_indices
    str     x28, [x24]
    cbnz    x0, 99f
    ldr     x9, [sp, #(L + 32)]
    ldr     x12, [x9, #PendingAttestation_inclusion_delay]
    SCRATCH_LIST x9, x24, x28, 1, x27
    ldr     x10, [x9, #LIST_COUNT]
    add     x9, x9, #LIST_FIXED
    ldr     x13, [sp, #(L + 40)]            /* the status bytes */
72: cbz     x10, 71b
    ldr     x11, [x9], #8
    sub     x10, x10, #1
    subs    x11, x11, x22
    b.lo    72b
    cmp     x11, x23
    b.hs    72b
    add     x14, x13, x11, lsl #1
    ldrb    w15, [x14]
    orr     w15, w15, #\bit
    strb    w15, [x14]
.if \lowest
    ldrb    w15, [x14, #1]
    cmp     x12, x15
    b.hs    72b
    strb    w12, [x14, #1]
.endif
    b       72b
79:
.endm

/* The vote's item at ioff: an attester, base_reward in a leak, else base_reward * its attesting increments // the active increments; another, -base_reward. */
.macro WINDOW_VOTE bit, boff, ioff
    tbz     x5, #\bit, 91f
    cbnz    x7, 92f
    ldr     x8, [x21, #\boff]
    udiv    x8, x8, x1
    mul     x8, x2, x8
    udiv    x8, x8, x6
    str     x8, [x11, #\ioff]
    b       93f
92: str     x2, [x11, #\ioff]
    b       93f
91: neg     x8, x2
    str     x8, [x11, #\ioff]
93:
.endm
.else
/* The flag's item at ioff: participating, 0 in a leak, else base_reward * weight * its increments // (active_increments * WEIGHT_DENOMINATOR); not, with penal, -(base_reward * weight // WEIGHT_DENOMINATOR). */
.macro REWARD_FLAG bit, weight, boff, ioff, penal
    tbz     x5, #\bit, 91f
    cbnz    x7, 92f
    ldr     x8, [x21, #\boff]
    udiv    x8, x8, x1
    mov     x13, #\weight
    mul     x13, x2, x13
    mul     x13, x13, x8
    udiv    x13, x13, x6
    str     x13, [x11, #\ioff]
    b       92f
91:
.if \penal
    mov     x13, #\weight
    mul     x13, x2, x13
    lsr     x13, x13, #6
    neg     x13, x13
    str     x13, [x11, #\ioff]
.endif
92:
.endm
.endif

/*
 * (state, config, totals, first, count, scratch, out) -> status: the attestation rewards of the
 * validators first to first + count - 1 (node.md, lantern_node_attestation_rewards). x19 state,
 * x20 the CommitteeCache, x21 totals, x22 first, x23 count, x24 scratch, x25 out, x26 the
 * validators (phase0: first the matching attestations), x27 the validator count, x28 the scratch's
 * size. Locals: L and L+8 the previous epoch's participation (from altair) and its count, L+16 and
 * L+24 the inactivity scores and their count (phase0: a list's cursor and count), L+32 an
 * attestation, L+40 (phase0) a status and a delay byte for each validator of the window.
 */
SPEC_FUNCTION node_attestation_rewards
    ENTER 48
    mov     x19, x0
    ldr     x20, [x1, #CONFIG_COMMITTEE_CACHE]
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    LDQ     x27, x19, BeaconState_validators + 8
    adds    x9, x22, x23
    b.cs    96f
    cmp     x9, x27
    b.hi    96f
    ldr     x28, [x24]
.if FORK == FORK_PHASE0
    NEED_SCRATCH_B x24, x19, 6, PENDING_REFS_BYTES, 97f
    TAKE_REFS x26, x24, x28                 /* x28: the scratch's size before the matching attestations */
    SCRATCH_LIST x9, x24, x28, 0, x27       /* the window's bytes: no vote, no delay */
    add     x9, x9, #LIST_FIXED
    str     x9, [sp, #(L + 40)]
    mov     x10, x23
    mov     w11, #0xff00
1:  cbz     x10, 2f
    strh    w11, [x9], #2
    sub     x10, x10, #1
    b       1b
2:  WINDOW_MARK lantern_get_matching_source_attestations, 1, 1
    WINDOW_MARK lantern_get_matching_target_attestations, 2, 0
    WINDOW_MARK lantern_get_matching_head_attestations, 4, 0
.else
    NEED_SCRATCH x24, x19, 1, 97f
    PART    x9, x10, x19, BeaconState_previous_epoch_participation
    stp     x9, x10, [sp, #L]
    PART    x9, x10, x19, BeaconState_inactivity_scores
    stp     x9, x10, [sp, #(L + 16)]
.endif
    PART    x26, x9, x19, BeaconState_validators
    MOVQ    x1, EFFECTIVE_BALANCE_INCREMENT
    ldr     x6, [x21, #24]
    udiv    x6, x6, x1                      /* the active increments */
.if FORK >= FORK_ALTAIR
    lsl     x6, x6, #6                      /* * WEIGHT_DENOMINATOR */
.endif
    ldr     x7, [x21, #16]                  /* the leak */
    mov     x9, #0
3:  cmp     x9, x23
    b.hs    8f
    add     x10, x22, x9
    mov     x11, #48
    madd    x11, x9, x11, x25               /* the item: 0 */
    stp     xzr, xzr, [x11]
    stp     xzr, xzr, [x11, #16]
    stp     xzr, xzr, [x11, #32]
    add     x12, x26, x10, lsl #7
    ldr     x14, [x21]                      /* eligible: active in the previous epoch, or slashed and not yet withdrawable */
    ldr     x15, [x12, #Validator_activation_epoch]
    cmp     x15, x14
    b.hi    4f
    ldr     x15, [x12, #Validator_exit_epoch]
    cmp     x14, x15
    b.lo    5f
4:  ldrb    w15, [x12, #Validator_slashed]
    cbz     w15, 7f
    ldr     x15, [x12, #Validator_withdrawable_epoch]
    add     x0, x14, #1
    cmp     x0, x15
    b.hs    7f
5:  mov     x0, #1
    str     x0, [x11, #40]
    ldr     x0, [x12, #Validator_effective_balance]
.if FORK == FORK_PHASE0
    mov     x2, #BASE_REWARD_FACTOR         /* get_base_reward */
    mul     x2, x0, x2
    ldr     x3, [x21, #32]
    udiv    x2, x2, x3
    lsr     x2, x2, #2
    ldr     x3, [sp, #(L + 40)]
    add     x3, x3, x9, lsl #1
    ldrb    w5, [x3]                        /* the window's status: 1 source, 2 target, 4 head */
    ldrb    w4, [x3, #1]                    /* the lowest delay */
    ldrb    w15, [x12, #Validator_slashed]
    cmp     w15, #0
    csel    x5, x5, xzr, eq                 /* unslashed attesters only */
    WINDOW_VOTE 0, 40, 16
    WINDOW_VOTE 1, 48, 8
    WINDOW_VOTE 2, 56, 0
    lsr     x3, x2, #3                      /* get_proposer_reward */
    tbz     x5, #0, 61f
    sub     x8, x2, x3                      /* inclusion_delay: the attester's part, // its lowest delay */
    udiv    x8, x8, x4
    str     x8, [x11, #24]
61: cbz     x7, 7f                          /* inactivity, in a leak */
    lsl     x8, x2, #2
    sub     x8, x8, x3
    tbnz    x5, #1, 62f
    ldr     x13, [x21, #8]                  /* not a target attester: effective_balance * finality_delay // INACTIVITY_PENALTY_QUOTIENT */
    mul     x13, x0, x13
    MOVQ    x15, INACTIVITY_PENALTY_QUOTIENT
    udiv    x13, x13, x15
    add     x8, x8, x13
62: neg     x8, x8
    str     x8, [x11, #32]
.else
    udiv    x2, x0, x1                      /* base_reward */
    ldr     x3, [x21, #32]
    mul     x2, x2, x3
    ldp     x3, x4, [sp, #L]                /* the flags, of an unslashed validator */
    mov     x5, #0
    cmp     x10, x4
    b.hs    51f
    ldrb    w5, [x3, x10]
51: ldrb    w15, [x12, #Validator_slashed]
    cmp     w15, #0
    csel    x5, x5, xzr, eq
    REWARD_FLAG TIMELY_SOURCE_FLAG_INDEX, TIMELY_SOURCE_WEIGHT, 40, 16, 1
    REWARD_FLAG TIMELY_TARGET_FLAG_INDEX, TIMELY_TARGET_WEIGHT, 48, 8, 1
    REWARD_FLAG TIMELY_HEAD_FLAG_INDEX, TIMELY_HEAD_WEIGHT, 56, 0, 0
    tbnz    x5, #TIMELY_TARGET_FLAG_INDEX, 7f   /* inactivity: not a timely target */
    ldp     x3, x4, [sp, #(L + 16)]
    mov     x8, #0
    cmp     x10, x4
    b.hs    52f
    ldr     x8, [x3, x10, lsl #3]
52: ldr     x13, [x21, #64]                 /* mode 1: its score as process_inactivity_updates leaves it */
    cbz     x13, 53f
    ldr     x13, [x21, #80]
    add     x8, x8, x13
    cbnz    x7, 53f
    ldr     x13, [x21, #88]
    cmp     x8, x13
    csel    x13, x8, x13, lo
    sub     x8, x8, x13
53: mul     x8, x0, x8
    ldr     x13, [x21, #80]
    MOVQ    x3, FORK_INACTIVITY_PENALTY_QUOTIENT
    mul     x13, x13, x3
    udiv    x8, x8, x13
    neg     x8, x8
    str     x8, [x11, #32]
.endif
7:  add     x9, x9, #1
    b       3b
8:  mov     x0, #LANTERN_OK
99:
.if FORK == FORK_PHASE0
    MOVQ    x10, PENDING_REFS_BYTES          /* the scratch's size on entry */
    add     x10, x28, x10
    str     x10, [x24]
.else
    str     x28, [x24]
.endif
    LEAVE 48
96: mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 48
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END node_attestation_rewards

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
    ADDRESS x0, lantern_type_SignedAggregateAndProof
    cmp     x9, #NODE_JSON_AGGREGATE_AND_PROOF
    b.eq    9f
.if FORK >= FORK_ALTAIR
    ADDRESS x0, lantern_type_SyncCommitteeMessage
    cmp     x9, #NODE_JSON_SYNC_COMMITTEE_MESSAGE
    b.eq    9f
    ADDRESS x0, lantern_type_SyncCommitteeContribution
    cmp     x9, #NODE_JSON_SYNC_CONTRIBUTION
    b.eq    9f
    ADDRESS x0, lantern_type_SignedContributionAndProof
    cmp     x9, #NODE_JSON_CONTRIBUTION_AND_PROOF
    b.eq    9f
    ADDRESS x0, lantern_type_SyncCommitteeSubscription
    cmp     x9, #NODE_JSON_SYNC_SUBSCRIPTION
    b.eq    9f
    ADDRESS x0, lantern_type_LightClientBootstrap
    cmp     x9, #NODE_JSON_LC_BOOTSTRAP
    b.eq    9f
    ADDRESS x0, lantern_type_LightClientUpdate
    cmp     x9, #NODE_JSON_LC_UPDATE
    b.eq    9f
    ADDRESS x0, lantern_type_LightClientFinalityUpdate
    cmp     x9, #NODE_JSON_LC_FINALITY_UPDATE
    b.eq    9f
    ADDRESS x0, lantern_type_LightClientOptimisticUpdate
    cmp     x9, #NODE_JSON_LC_OPTIMISTIC_UPDATE
    b.eq    9f
.endif
    ADDRESS x0, lantern_type_BeaconCommitteeSubscription
    cmp     x9, #NODE_JSON_COMMITTEE_SUBSCRIPTION
    b.eq    9f
    ADDRESS x0, lantern_type_ProposerPreparation
    cmp     x9, #NODE_JSON_PROPOSER_PREPARATION
    b.eq    9f
    ADDRESS x0, lantern_type_BeaconBlock
    cmp     x9, #NODE_JSON_BEACON_BLOCK
    b.eq    9f
.if FORK >= FORK_DENEB
    ADDRESS x0, lantern_type_BlockContents
    cmp     x9, #NODE_JSON_BLOCK_CONTENTS
    b.eq    9f
.endif
.if FORK >= FORK_BELLATRIX
    ADDRESS x0, lantern_type_SignedBlindedBeaconBlock
.else
    ADDRESS x0, lantern_type_SignedBeaconBlock
.endif
    cmp     x9, #NODE_JSON_BLINDED_BLOCK
    b.eq    9f
.if FORK >= FORK_ELECTRA
    ADDRESS x0, lantern_type_SingleAttestation
    cmp     x9, #NODE_JSON_SINGLE_ATTESTATION
    b.eq    9f
.endif
.if FORK >= FORK_DENEB && FORK < FORK_FULU
    ADDRESS x0, lantern_type_BlobSidecar
    cmp     x9, #NODE_JSON_BLOB_SIDECAR
    b.eq    9f
.endif
.if FORK >= FORK_FULU
    ADDRESS x0, lantern_type_DataColumnSidecar
    cmp     x9, #NODE_JSON_DATA_COLUMN_SIDECAR
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

/*
 * (store, scratch, out) -> status: get_weight of each node of the store, in node order, a u64 a
 * node at out, as lantern_get_head computes them all at once (node.md, lantern_node_weights).
 * x19 store, x20 scratch, x21 out, x22 node count, x23 the flags at the end of scratch.
 */
SPEC_FUNCTION node_weights
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    NEED_BALANCES x19, 8f
    LDQ     x22, x19, Store_blocks + 8
    ldr     x9, [x20]
    lsl     x10, x22, #3
    MOVQ    x11, LANTERN_SCRATCH_FIXED
    add     x11, x11, x10
    cmp     x9, x11
    b.lo    9f
    sub     x9, x9, x10
    add     x23, x20, x9
    mov     x0, x23
    mov     x1, x10
    bl      lantern_zero
    mov     x0, x19
    mov     x1, x21
    mov     x2, x23
    bl      weights
    cbnz    x0, 7f
    mov     x9, #0                          /* a sum past 2^64 - 1 */
1:  cmp     x9, x22
    b.hs    7f
    ldr     x10, [x23, x9, lsl #3]
    add     x9, x9, #1
    tst     x10, #F_OVERFLOW
    b.eq    1b
    mov     x0, #LANTERN_INVALID_OVERFLOW
7:  LEAVE 0
8:  mov     x0, #LANTERN_NEED_JUSTIFIED_STATE
    LEAVE 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END node_weights
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

/* lantern_node_blinded_block: the end of the offsets in a body's fixed part, the last of them that of the last variable field */
.if FORK >= FORK_BELLATRIX
.if FORK >= FORK_ELECTRA
.set BLINDED_BODY_OFFSETS_END, BeaconBlockBody_execution_requests__ssz + 4
.elseif FORK >= FORK_DENEB
.set BLINDED_BODY_OFFSETS_END, BeaconBlockBody_blob_kzg_commitments__ssz + 4
.elseif FORK >= FORK_CAPELLA
.set BLINDED_BODY_OFFSETS_END, BeaconBlockBody_bls_to_execution_changes__ssz + 4
.else
.set BLINDED_BODY_OFFSETS_END, BeaconBlockBody_execution_payload__ssz + 4
.endif
.endif

/*
 * (block, scratch, out) -> status: the SSZ bytes of the SignedBlindedBeaconBlock of the
 * SignedBeaconBlock in the ByteList block, in the ByteList out (node.md,
 * lantern_node_blinded_block); before bellatrix the bytes of block. x19 the block's bytes, x20
 * their count, x21 the body's place in them, x22 out, x23 scratch, x24 the payload's place, x25
 * the payload's value, x26 the header's value, x27 the scratch's size after the decoded block,
 * x28 the payload's end. Locals: L the scratch's size, L+8 the header's SSZ ByteList, L+16 block,
 * L+24 the header's bytes less the payload's.
 */
SPEC_FUNCTION node_blinded_block
    ENTER 32
    str     x0, [sp, #(L + 16)]
    ldr     x9, [x0, #8]
    add     x19, x0, x9
    ldr     x20, [x0, #16]
    mov     x22, x2
    mov     x23, x1
    ldr     x9, [x23]
    str     x9, [sp, #L]
.if FORK < FORK_BELLATRIX
    ldr     x9, [x22]                       /* before bellatrix: the block's bytes */
    add     x10, x20, #24
    cmp     x10, x9
    b.hi    8f
    mov     x9, #24
    stp     x9, x20, [x22, #8]
    add     x0, x22, #24
    mov     x1, x19
    mov     x2, x20
    bl      lantern_copy
    b       7f
.else
    cmp     x20, #100                       /* the message at the offset at byte 0, its body at the offset in it */
    b.lo    91f
    ldr     w9, [x19]
    add     x10, x9, #84
    cmp     x10, x20
    b.hi    91f
    add     x10, x19, x9
    ldr     w11, [x10, #BeaconBlock_body__ssz]
    add     x21, x9, x11
    MOVQ    x10, BLINDED_BODY_OFFSETS_END
    add     x10, x21, x10
    cmp     x10, x20
    b.hi    91f
    add     x10, x19, x21                   /* the payload: from its offset to the next field's, else to the end */
    ldr     w11, [x10, #BeaconBlockBody_execution_payload__ssz]
    add     x24, x21, x11
.if FORK >= FORK_CAPELLA
    ldr     w12, [x10, #BeaconBlockBody_bls_to_execution_changes__ssz]
    add     x28, x21, x12
.else
    mov     x28, x20
.endif
    cmp     x24, x28
    b.hi    91f
    cmp     x28, x20
    b.hi    91f
    ADDRESS x0, lantern_type_SignedBeaconBlock  /* the decoded block's payload */
    ldr     x1, [sp, #(L + 16)]
    mov     x2, x23
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    91f
    PART    x9, x10, x1, SignedBeaconBlock_message
    PART    x11, x10, x9, BeaconBlock_body
    PART    x25, x10, x11, BeaconBlockBody_execution_payload
    ldr     x27, [x23]                      /* its header, as process_execution_payload builds it */
    TX_BYTES x11, x25, x12
    MOVQ    x9, LANTERN_SCRATCH_FIXED + HEADER_ROOM + 24 + PAYLOAD_WLIST_BYTES + 1024
    add     x9, x9, x11
    cmp     x27, x9
    b.lo    8f
    MOVQ    x9, HEADER_ROOM
    sub     x9, x27, x9
    add     x26, x23, x9
    mov     x0, x26
    bl      build_payload_header
    cbnz    x0, 6f
    MOVQ    x9, HEADER_ROOM + 1024          /* its SSZ bytes, in a ByteList of 1024 bytes below it */
    sub     x9, x27, x9
    add     x3, x23, x9
    mov     x10, #1024
    str     x10, [x3]
    str     x3, [sp, #(L + 8)]
    str     x9, [x23]
    ADDRESS x0, lantern_type_ExecutionPayloadHeader
    mov     x1, x26
    mov     x2, x23
    CALL_GLOBAL ssz_serialize
    cbnz    x0, 6f
    ldr     x9, [sp, #(L + 8)]              /* out: the block's bytes to the payload, the header's, the block's after the payload */
    ldr     x13, [x9, #16]
    sub     x14, x28, x24
    sub     x15, x13, x14
    str     x15, [sp, #(L + 24)]
    add     x10, x20, x15
    ldr     x11, [x22]
    add     x12, x10, #24
    cmp     x12, x11
    b.hi    8f
    mov     x11, #24
    stp     x11, x10, [x22, #8]
    add     x0, x22, #24
    mov     x1, x19
    mov     x2, x24
    bl      lantern_copy
    ldr     x9, [sp, #(L + 8)]
    add     x0, x22, #24
    add     x0, x0, x24
    ldr     x10, [x9, #8]
    add     x1, x9, x10
    ldr     x2, [x9, #16]
    bl      lantern_copy
    ldr     x9, [sp, #(L + 8)]
    ldr     x9, [x9, #16]
    add     x0, x22, #24
    add     x0, x0, x24
    add     x0, x0, x9
    add     x1, x19, x28
    sub     x2, x20, x28
    bl      lantern_copy
.if FORK >= FORK_CAPELLA
    ldr     x15, [sp, #(L + 24)]            /* the offsets after the payload's grow by the header's bytes less the payload's */
    add     x10, x22, #24
    add     x10, x10, x21
    ldr     w11, [x10, #BeaconBlockBody_bls_to_execution_changes__ssz]
    add     w11, w11, w15
    str     w11, [x10, #BeaconBlockBody_bls_to_execution_changes__ssz]
.if FORK >= FORK_DENEB
    ldr     w11, [x10, #BeaconBlockBody_blob_kzg_commitments__ssz]
    add     w11, w11, w15
    str     w11, [x10, #BeaconBlockBody_blob_kzg_commitments__ssz]
.endif
.if FORK >= FORK_ELECTRA
    ldr     w11, [x10, #BeaconBlockBody_execution_requests__ssz]
    add     w11, w11, w15
    str     w11, [x10, #BeaconBlockBody_execution_requests__ssz]
.endif
.endif
.endif
7:  ldr     x9, [sp, #L]
    str     x9, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 32
6:  cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    8f
91: ldr     x9, [sp, #L]
    str     x9, [x23]
    mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 32
8:  ldr     x9, [sp, #L]
    str     x9, [x23]
    mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END node_blinded_block

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
    cbnz    x0, 98f
    ldr     x9, [x22]                       /* a valid message: its slot and its subnet's bit */
    cbnz    x9, 99f
    ldr     x9, [x20, #SyncCommitteeMessage_slot]
    ldr     x10, [x19, #NodeGossip_subnet]
    mov     x11, #1
    lsl     x10, x11, x10
    stp     x9, x10, [x23]
    stp     xzr, xzr, [x23, #16]
    b       99f
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

/*
 * (state, request, scratch, out): node.md, lantern_node_produce_check. x19 state, x20 request, x21
 * scratch, x22 out, x23 the scratch size, x24 the proposer's Validator. Locals: L epoch, L+8 the
 * proposer, L+16 domain type, L+24 domain (32), L+56 the signing root after a ByteList header (56).
 */
SPEC_FUNCTION node_produce_check
    ENTER 112
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
.if FORK >= FORK_FULU
    NEED_SCRATCH x21, x19, 0, 9f
.else
    NEED_SCRATCH x21, x19, 2, 9f                /* get_beacon_proposer_index takes S(2) */
.endif
    ldr     x23, [x21]
    mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    mov     x0, x19
.if FORK >= FORK_FULU
    add     x1, sp, #(L + 8)
    bl      lantern_get_beacon_proposer_index
.else
    mov     x1, x21
    add     x2, sp, #(L + 8)
    bl      lantern_get_beacon_proposer_index
    str     x23, [x21]
.endif
    cbnz    x0, 7f
    ldr     x9, [sp, #(L + 8)]
    str     x9, [x22]
    ldr     x9, [x20, #128]                 /* skip_randao_verification: the point at infinity */
    cbz     x9, 1f
    ldrb    w9, [x20]
    cmp     w9, #0xc0
    b.ne    5f
    mov     x10, #1
2:  ldrb    w9, [x20, x10]
    cbnz    w9, 5f
    add     x10, x10, #1
    cmp     x10, #96
    b.lo    2b
    b       3f
1:  ldr     x9, [sp, #(L + 8)]              /* else the check of process_randao, no mix */
    PART    x24, x10, x19, BeaconState_validators
    cmp     x9, x10
    mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    b.hs    7f
    add     x24, x24, x9, lsl #7
    mov     w9, #DOMAIN_RANDAO
    str     w9, [sp, #(L + 16)]
    mov     x0, x19
    add     x1, sp, #(L + 16)
    add     x2, sp, #L
    mov     x3, x21
    add     x4, sp, #(L + 24)
    bl      lantern_get_domain
    cbnz    x0, 7f
    ADDRESS x0, lantern_type_Uint64
    add     x1, sp, #L
    add     x2, sp, #(L + 24)
    mov     x3, x21
    add     x4, sp, #(L + 80)
    bl      lantern_compute_signing_root
    cbnz    x0, 7f
    add     x0, x24, #Validator_pubkey
    mov     x1, x20
    add     x2, sp, #(L + 56)
    mov     x3, x21
    bl      verify_root_signature
    cbnz    x0, 7f
    cbz     x1, 5f
3:
.if FORK < FORK_ELECTRA
    LDQ     x9, x19, BeaconState_eth1_data + Eth1Data_deposit_count     /* deposits the block would need */
    LDQ     x10, x19, BeaconState_eth1_deposit_index
    cmp     x9, x10
    b.hi    6f
.elseif FORK == FORK_ELECTRA
    LDQ     x9, x19, BeaconState_eth1_data + Eth1Data_deposit_count     /* get_eth1_pending_deposit_count */
    LDQ     x11, x19, BeaconState_deposit_requests_start_index
    cmp     x9, x11
    csel    x9, x9, x11, lo
    LDQ     x10, x19, BeaconState_eth1_deposit_index
    cmp     x10, x9
    b.lo    6f
.endif
    mov     x0, #LANTERN_OK
7:  LEAVE 112
5:  mov     x0, #LANTERN_INVALID_RANDAO_REVEAL
    LEAVE 112
6:  mov     x0, #LANTERN_INVALID_DEPOSITS
    LEAVE 112
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 112
SPEC_END node_produce_check

.if FORK >= FORK_BELLATRIX
/* (json, scratch, out, fault): node.md, lantern_node_payload_result. */
SPEC_FUNCTION node_payload_result
    FRAME 0
    mov     x4, x3
    mov     x3, x2
    mov     x2, x1
    mov     x1, x0
.if FORK == FORK_BELLATRIX
    ADDRESS x0, lantern_type_ExecutionPayload
.else
    ADDRESS x0, lantern_type_GetPayloadResult
.endif
    CALL_GLOBAL lantern_engine_json_decode
    UNFRAME 0
SPEC_END node_payload_result
.endif

/*
 * (state, entry, draft, arg, scratch): node.md, lantern_node_produce_fold. x19 state, x20 the
 * entry's bytes, x21 their count, x22 the draft, x23 arg, x24 scratch, x25 the topic, x26 the
 * entry's fork, x27 an aggregate, x28 the place. Locals: L data, L+8 signature, L+16 length,
 * L+24 the committee index, L+32 the list of two signatures, L+40 the parent root (32).
 */
SPEC_FUNCTION node_produce_fold
    ENTER 96
    mov     x19, x0
    ldp     x9, x21, [x1, #8]
    add     x20, x1, x9
    ldr     x9, [x2, #8]
    add     x22, x2, x9
    mov     x23, x3
    mov     x24, x4
    and     x25, x23, #0xff
    ubfx    x26, x23, #8, #8
    cmp     x25, #GOSSIP_BEACON_ATTESTATION
    b.eq    100f
.if FORK >= FORK_ALTAIR
    cmp     x25, #GOSSIP_SYNC_COMMITTEE
    b.eq    200f
.endif
    mov     x10, #MAX_VOLUNTARY_EXITS       /* an operation: a record, while its kind has room */
    cmp     x25, #GOSSIP_VOLUNTARY_EXIT
    b.eq    1f
    mov     x10, #MAX_PROPOSER_SLASHINGS
    cmp     x25, #GOSSIP_PROPOSER_SLASHING
    b.eq    1f
.if FORK >= FORK_CAPELLA
    mov     x10, #MAX_BLS_TO_EXECUTION_CHANGES
    cmp     x25, #GOSSIP_BLS_TO_EXECUTION_CHANGE
    b.eq    1f
.endif
    cmp     x25, #GOSSIP_ATTESTER_SLASHING
    b.ne    8f
    cmp     x26, #FORK_ELECTRA              /* an attester slashing of the fork's type */
.if FORK >= FORK_ELECTRA
    b.lo    8f
    mov     x10, #MAX_ATTESTER_SLASHINGS_ELECTRA
.else
    b.hs    8f
    mov     x10, #MAX_ATTESTER_SLASHINGS
.endif
1:  ldr     x11, [x22, #ProduceDraft_ops]
    ADDQ    x12, x22, PRODUCE_DRAFT_OPS
    add     x13, x12, x11                   /* the end of the records */
    mov     x14, #0
2:  cmp     x12, x13                        /* the records of the topic */
    b.hs    3f
    ldp     x9, x15, [x12]
    cmp     x9, x25
    cinc    x14, x14, eq
    add     x15, x15, #(16 + 7)
    and     x15, x15, #~7
    add     x12, x12, x15
    b       2b
3:  cmp     x14, x10
    b.hs    8f
    cmp     x25, #GOSSIP_ATTESTER_SLASHING  /* the clashes, with the kinds folded before */
    b.ne    4f
    mov     x0, x20
    mov     x1, x21
    ADDQ    x2, x22, PRODUCE_DRAFT_OPS
    mov     x3, x13
    bl      produce_takes_slashing
    cbz     x0, 8f
4:  cmp     x25, #GOSSIP_VOLUNTARY_EXIT
    b.ne    5f
    ldr     x0, [x20, #8]
    ADDQ    x1, x22, PRODUCE_DRAFT_OPS
    ldr     x2, [x22, #ProduceDraft_ops]
    add     x2, x1, x2
    bl      produce_slashed
    cbnz    x0, 8f
5:  ldr     x11, [x22, #ProduceDraft_ops]
    ADDQ    x12, x22, PRODUCE_DRAFT_OPS
    add     x13, x12, x11
    add     x9, x21, #(16 + 7)
    and     x9, x9, #~7
    add     x10, x11, x9
    MOVQ    x14, PRODUCE_DRAFT_OPS_ROOM
    cmp     x10, x14
    b.hi    8f
    stp     x25, x21, [x13]
    str     x10, [x22, #ProduceDraft_ops]
    add     x0, x13, #16
    mov     x1, x20
    mov     x2, x21
    bl      lantern_copy
    mov     x0, #LANTERN_OK
    LEAVE 96
8:  mov     x0, #LANTERN_INVALID_ENCODING   /* left out */
    LEAVE 96
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 96

    /* An attestation of the fork's type: its data, signature, committee, length and place. */
100: cmp    x26, #FORK_ELECTRA
.if FORK >= FORK_ELECTRA
    b.lo    8b
    cmp     x21, #240                       /* a SingleAttestation: committee_index 0, data at 16, signature at 144 */
    b.ne    8b
    add     x9, x20, #16
    add     x10, x20, #144
    stp     x9, x10, [sp, #L]
    ldr     x9, [x20]
    str     x9, [sp, #(L + 24)]
    lsr     x9, x23, #16                    /* member: the place, + 2^16 x the length */
    and     x28, x9, #0xffff
    lsr     x9, x9, #16
    str     x9, [sp, #(L + 16)]
    ldr     x9, [x20, #(16 + 8)]            /* data.index 0 */
    cbnz    x9, 8b
.else
    b.hs    8b
    cmp     x21, #(228 + 1)                 /* an Attestation: offset 228, data at 4, signature at 132, its bits */
    b.lo    8b
    MOVQ    x11, 228 + MAX_VALIDATORS_PER_COMMITTEE / 8 + 1
    cmp     x21, x11
    b.hi    8b
    ldr     w11, [x20]
    cmp     x11, #228
    b.ne    8b
    add     x9, x20, #4
    add     x10, x20, #132
    stp     x9, x10, [sp, #L]
    ldr     x9, [x20, #(4 + 8)]
    str     x9, [sp, #(L + 24)]
    add     x1, x20, #228
    sub     x2, x21, #229                   /* the last byte: its highest bit is the length's */
    ldrb    w3, [x1, x2]
    cbz     w3, 8b
    clz     w3, w3
    mov     w4, #31
    sub     w3, w4, w3
    add     x14, x3, x2, lsl #3
    str     x14, [sp, #(L + 16)]
    mov     x28, #0                         /* the place: the first bit set */
101: cmp    x28, x14
    b.hs    8b
    lsr     x3, x28, #3
    ldrb    w3, [x1, x3]
    and     x4, x28, #7
    lsr     w3, w3, w4
    tbnz    w3, #0, 102f
    add     x28, x28, #1
    b       101b
102:
.endif
    ldr     x14, [sp, #(L + 16)]
    MOVQ    x9, MAX_VALIDATORS_PER_COMMITTEE
    cmp     x14, x9
    b.hi    8b
    cmp     x28, x14
    b.hs    8b
    ldr     x12, [sp, #L]                   /* process_attestation's checks of slot, target and source */
    ldr     x13, [x12]                      /* data.slot */
    ldr     x14, [x12, #88]                 /* target.epoch */
    LDQ     x15, x19, BeaconState_slot
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x10, x15, x9                    /* the current epoch */
    udiv    x11, x13, x9
    cmp     x11, x14
    b.ne    8b
    cmp     x14, x10
    b.eq    103f
    sub     x11, x10, #1
    cbz     x10, 8b
    cmp     x14, x11
    b.ne    8b
103: add    x11, x13, #MIN_ATTESTATION_INCLUSION_DELAY
    cmp     x11, x15
    b.hi    8b
.if FORK < FORK_DENEB
    add     x11, x13, #SLOTS_PER_EPOCH
    cmp     x15, x11
    b.hi    8b
.endif
    ADDQ    x11, x19, BeaconState_current_justified_checkpoint
    cmp     x14, x10
    b.eq    104f
    ADDQ    x11, x19, BeaconState_previous_justified_checkpoint
104: add    x12, x12, #48                   /* source: epoch, root */
    ldr     x13, [x12]
    ldr     x9, [x11]
    cmp     x13, x9
    b.ne    8b
    ldp     x13, x9, [x12, #8]
    ldp     x10, x15, [x11, #8]
    cmp     x13, x10
    ccmp    x9, x15, #0, eq
    b.ne    8b
    ldp     x13, x9, [x12, #24]
    ldp     x10, x15, [x11, #24]
    cmp     x13, x10
    ccmp    x9, x15, #0, eq
    b.ne    8b
    ADDQ    x27, x22, PRODUCE_DRAFT_AGGREGATES  /* its aggregate: of the same data and committee */
    ldr     x10, [x22, #ProduceDraft_aggregates]
    mov     x11, #0
105: cmp    x11, x10
    b.hs    110f
    ldr     x9, [x27, #DraftAggregate_committee_index]
    ldr     x12, [sp, #(L + 24)]
    cmp     x9, x12
    b.ne    107f
    ldr     x1, [sp, #L]
    mov     x2, #0
106: ldr    x9, [x27, x2]
    ldr     x12, [x1, x2]
    cmp     x9, x12
    b.ne    107f
    add     x2, x2, #8
    cmp     x2, #128
    b.lo    106b
    b       120f
107: add    x27, x27, #DraftAggregate__mem
    add     x11, x11, #1
    b       105b
110: MOVQ   x9, PRODUCE_DRAFT_AGGREGATE_COUNT  /* a new aggregate: its data, committee, length, order, signature */
    cmp     x10, x9
    b.hs    8b
    add     x9, x10, #1
    str     x9, [x22, #ProduceDraft_aggregates]
    mov     x0, x27
    ldr     x1, [sp, #L]
    mov     x2, #128
    bl      lantern_copy
    ldr     x9, [sp, #(L + 24)]
    str     x9, [x27, #DraftAggregate_committee_index]
    ldr     x9, [sp, #(L + 16)]
    str     x9, [x27, #DraftAggregate_length]
    ldr     x9, [x22, #ProduceDraft_aggregates]
    sub     x9, x9, #1
    str     x9, [x27, #DraftAggregate_order]
    ADDQ    x0, x27, DraftAggregate_signature
    ldr     x1, [sp, #(L + 8)]
    mov     x2, #96
    bl      lantern_copy
    b       130f
120: ldr    x9, [x27, #DraftAggregate_length]  /* the same length, a place not taken, the signatures added */
    ldr     x10, [sp, #(L + 16)]
    cmp     x9, x10
    b.ne    8b
    add     x11, x27, #DraftAggregate_bits
    lsr     x12, x28, #3
    ldrb    w12, [x11, x12]
    and     x13, x28, #7
    lsr     w12, w12, w13
    tbnz    w12, #0, 8b
    ADDQ    x0, x27, DraftAggregate_signature
    ldr     x1, [sp, #(L + 8)]
    mov     x2, x24
    bl      produce_add_signature
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    9b
    cbnz    x0, 8b
130: add    x11, x27, #DraftAggregate_bits     /* its place's bit */
    lsr     x12, x28, #3
    ldrb    w13, [x11, x12]
    and     x14, x28, #7
    mov     x10, #1
    lsl     x10, x10, x14
    orr     w13, w13, w10
    strb    w13, [x11, x12]
    mov     x0, #LANTERN_OK
    LEAVE 96

.if FORK >= FORK_ALTAIR
    /*
     * A SyncCommitteeMessage of the state's slot - 1 and the block's parent root: each place of its
     * validator's public key in the state's current_sync_committee not set yet, its signature added.
     */
200: cmp    x21, #144
    b.ne    8b
    ldr     x9, [x20]
    add     x9, x9, #1
    LDQ     x10, x19, BeaconState_slot
    cmp     x9, x10
    b.ne    8b
    ADDRESS x0, lantern_type_BeaconBlockHeader  /* the parent root: hash_tree_root(state.latest_block_header) */
    ADDQ    x1, x19, BeaconState_latest_block_header
    mov     x2, x24
    add     x3, sp, #(L + 40)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 9b
    ldp     x9, x10, [x20, #8]
    ldp     x11, x12, [sp, #(L + 40)]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    8b
    ldp     x9, x10, [x20, #24]
    ldp     x11, x12, [sp, #(L + 56)]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    8b
    ldr     x9, [x20, #40]                  /* its validator's public key */
    PART    x10, x11, x19, BeaconState_validators
    cmp     x9, x11
    b.hs    8b
    add     x27, x10, x9, lsl #7
    add     x27, x27, #Validator_pubkey
    ADDQ    x26, x19, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    mov     x28, #0
201: cmp    x28, #SYNC_COMMITTEE_SIZE
    b.hs    209f
    mov     x10, #48
    madd    x10, x28, x10, x26
    mov     x11, #0
202: ldr    x12, [x10, x11]
    ldr     x13, [x27, x11]
    cmp     x12, x13
    b.ne    208f
    add     x11, x11, #8
    cmp     x11, #48
    b.lo    202b
    add     x11, x22, #ProduceDraft_sync_bits   /* a place: set, the signature added */
    lsr     x12, x28, #3
    ldrb    w13, [x11, x12]
    and     x14, x28, #7
    lsr     w15, w13, w14
    tbnz    w15, #0, 208f
    mov     x10, #1
    lsl     x10, x10, x14
    orr     w13, w13, w10
    strb    w13, [x11, x12]
    ldr     x9, [x22, #ProduceDraft_sync_set]
    cbnz    x9, 203f
    mov     x9, #1
    str     x9, [x22, #ProduceDraft_sync_set]
    ADDQ    x0, x22, ProduceDraft_sync_signature
    add     x1, x20, #48
    mov     x2, #96
    bl      lantern_copy
    b       208f
203: ADDQ   x0, x22, ProduceDraft_sync_signature
    add     x1, x20, #48
    mov     x2, x24
    bl      produce_add_signature
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    9b
208: add    x28, x28, #1
    b       201b
209: mov    x0, #LANTERN_OK
    LEAVE 96
.endif
SPEC_END node_produce_fold

/*
 * L1: the signature x1 added to the aggregate x0 with crypto_bls_aggregate, through a list of the
 * two at the end of scratch x2: x0 = LANTERN_OK, a status of crypto_bls_aggregate, or
 * LANTERN_BUFFER_TOO_SMALL. Locals: L the aggregate, L+8 the signature, L+16 the list.
 */
LOCAL_FUNCTION produce_add_signature
    FRAME 32
    stp     x0, x1, [sp, #16]
    ldr     x10, [x2]
    cmp     x10, #(24 + 2 * 96 + 8)
    b.lo    9f
    sub     x10, x10, #(24 + 2 * 96)
    and     x10, x10, #~7
    add     x10, x2, x10
    str     x10, [sp, #32]
    mov     x11, #(24 + 2 * 96)
    mov     x12, #24
    stp     x11, x12, [x10]
    mov     x11, #2
    str     x11, [x10, #16]
    add     x0, x10, #24
    ldr     x1, [sp, #16]
    mov     x2, #96
    bl      lantern_copy
    ldr     x10, [sp, #32]
    add     x0, x10, #(24 + 96)
    ldr     x1, [sp, #24]
    mov     x2, #96
    bl      lantern_copy
    ldr     x0, [sp, #32]
    ldr     x1, [sp, #16]
    CALL_GLOBAL crypto_bls_aggregate
    UNFRAME 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 32
END_FUNCTION produce_add_signature

/* ---------------------------------------------------------------- produceBlockV3: the block */

.if Eth1Data_block_hash != 40 || Eth1Data__mem != 72
.error "node_produce_block copies Eth1Data as its 72 SSZ bytes"
.endif
.set PB_FIXED, 84                               /* BeaconBlock: slot, proposer_index, parent_root, state_root, the body's offset */
.set PB_SYNC, 220                               /* the body's offsets: proposer_slashings at 200 to voluntary_exits at 216 */
.if FORK >= FORK_ALTAIR
.set PB_PAYLOAD, PB_SYNC + SYNC_COMMITTEE_SIZE / 8 + 96
.else
.set PB_PAYLOAD, PB_SYNC
.endif
.if FORK >= FORK_BELLATRIX
.set PB_BLS, PB_PAYLOAD + 4
.else
.set PB_BLS, PB_PAYLOAD
.endif
.if FORK >= FORK_CAPELLA
.set PB_COMMITMENTS, PB_BLS + 4
.else
.set PB_COMMITMENTS, PB_BLS
.endif
.if FORK >= FORK_DENEB
.set PB_REQUESTS, PB_COMMITMENTS + 4
.else
.set PB_REQUESTS, PB_COMMITMENTS
.endif
.if FORK >= FORK_ELECTRA
.set PB_BODY_FIXED, PB_REQUESTS + 4
.set PB_MAX_ATTESTATIONS, MAX_ATTESTATIONS_ELECTRA
.else
.set PB_BODY_FIXED, PB_REQUESTS
.set PB_MAX_ATTESTATIONS, MAX_ATTESTATIONS
.endif

/* The offset of the body's field at pos: the write position x24 from the body x26. Uses x9. */
.macro PB_OFFSET pos
    sub     x9, x24, x26
    str     w9, [x26, #\pos]
.endm

/*
 * (state, draft, params, scratch, out): node.md, lantern_node_produce_block. x19 state, x20 the
 * draft, x21 params, x22 scratch, x23 out, x24 the write position, x25 the block, x26 the body,
 * x27 and x28 work. Locals: L proposer, L+8 the result's bytes, L+16 their count, L+24 the
 * payload, L+32 its count, L+40 the bundle, L+48 its count, L+56 balance before, L+64 1, L+72 a
 * Result, L+80 the scratch size, L+88 a ByteList view of the request lists (electra), L+256 24
 * bytes kept aside.
 */
SPEC_FUNCTION node_produce_block
    ENTER 288
    mov     x19, x0
    ldr     x9, [x1, #8]
    add     x20, x1, x9
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x9, [x22]
    str     x9, [sp, #(L + 80)]
    ldr     x9, [x21]                       /* execution_valid 1, + 2 with skip_randao_verification */
    ldr     x9, [x9, #128]
    lsl     x9, x9, #1
    orr     x9, x9, #1
    str     x9, [sp, #(L + 64)]
    ldp     x9, x10, [x23]                  /* out: the block from offset 24, as large as its room */
    mov     x11, #24
    str     x11, [x23, #8]
    str     xzr, [x23, #16]
    add     x25, x23, #24
    mov     x0, x19                         /* the proposer */
.if FORK >= FORK_FULU
    add     x1, sp, #L
    bl      lantern_get_beacon_proposer_index
.else
    mov     x1, x22
    add     x2, sp, #L
    bl      lantern_get_beacon_proposer_index
    ldr     x9, [sp, #(L + 80)]
    str     x9, [x22]
.endif
    cbnz    x0, 99f
    ldr     x9, [sp, #L]                    /* its balance before */
    PART    x10, x11, x19, BeaconState_balances
    cmp     x9, x11
    b.hs    97f
    ldr     x10, [x10, x9, lsl #3]
    str     x10, [sp, #(L + 56)]
    stp     xzr, xzr, [sp, #(L + 8)]        /* the engine's result: the payload, and from deneb the bundle */
    stp     xzr, xzr, [sp, #(L + 24)]
    stp     xzr, xzr, [sp, #(L + 40)]
    ldr     x1, [x21, #16]
    cbz     x1, 5f
    ldp     x9, x10, [x1, #8]
    add     x9, x1, x9
    stp     x9, x10, [sp, #(L + 8)]
.if FORK == FORK_BELLATRIX
    stp     x9, x10, [sp, #(L + 24)]        /* the result is the payload */
.else
    cmp     x10, #(4 + 32)                  /* GetPayloadResult: the payload's offset, block_value at 4 */
    b.lo    96f
    ldr     w11, [x9]
.if FORK >= FORK_DENEB
    ldr     w12, [x9, #36]                  /* blobs_bundle's offset */
.else
    mov     x12, x10
.endif
    cmp     x11, x12
    b.hi    96f
    cmp     x12, x10
    b.hi    96f
    add     x13, x9, x11
    sub     x14, x12, x11
    stp     x13, x14, [sp, #(L + 24)]
.if FORK >= FORK_DENEB
.if FORK >= FORK_ELECTRA
    ldr     w13, [x9, #41]                  /* execution_requests' offset: the bundle up to it */
.else
    mov     x13, x10
.endif
    cmp     x12, x13
    b.hi    96f
    cmp     x13, x10
    b.hi    96f
    add     x14, x9, x12
    sub     x15, x13, x12
    stp     x14, x15, [sp, #(L + 40)]
.endif
.endif
5:  ldp     x9, x10, [x23]                  /* room: the fixed parts of the block and the body */
    MOVQ    x11, PB_FIXED + PB_BODY_FIXED + 24
    cmp     x9, x11
    b.lo    98f
    ldr     x9, [x19, #BeaconState_slot]
    str     x9, [x25]
    ldr     x9, [sp, #L]
    str     x9, [x25, #8]
    ADDRESS x0, lantern_type_BeaconBlockHeader  /* parent_root: hash_tree_root(state.latest_block_header) */
    ADDQ    x1, x19, BeaconState_latest_block_header
    mov     x2, x22
    add     x3, x25, #16
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 99f
    stp     xzr, xzr, [x25, #48]            /* state_root, written last */
    stp     xzr, xzr, [x25, #64]
    mov     w9, #PB_FIXED
    str     w9, [x25, #80]
    add     x26, x25, #PB_FIXED
    ldr     x9, [x21]                       /* randao_reveal, eth1_data (an empty eth1 chain's vote), graffiti */
    mov     x0, x26
    mov     x1, x9
    mov     x2, #96
    bl      lantern_copy
    add     x0, x26, #96
    ADDQ    x1, x19, BeaconState_eth1_data
    mov     x2, #72
    bl      lantern_copy
    add     x0, x26, #168
    ldr     x9, [x21]
    add     x1, x9, #96
    mov     x2, #32
    bl      lantern_copy
.if FORK >= FORK_ALTAIR
    add     x0, x26, #PB_SYNC               /* the draft's sync aggregate; with none, no bit and the point at infinity */
    add     x1, x20, #ProduceDraft_sync_bits
    mov     x2, #(SYNC_COMMITTEE_SIZE / 8 + 96)
    bl      lantern_copy
    ldr     x9, [x20, #ProduceDraft_sync_set]
    cbnz    x9, 6f
    add     x0, x26, #(PB_SYNC + SYNC_COMMITTEE_SIZE / 8)
    mov     x1, #96
    bl      lantern_zero
    mov     w9, #0xc0
    strb    w9, [x26, #(PB_SYNC + SYNC_COMMITTEE_SIZE / 8)]
6:
.endif
    add     x24, x26, #PB_BODY_FIXED
    /* proposer_slashings, attester_slashings: the draft's records, which the folds kept free of clashes */
    PB_OFFSET 200
    mov     x0, #GOSSIP_PROPOSER_SLASHING
    mov     x1, x24
    bl      produce_records
    mov     x24, x1
    cbnz    x0, 98f
    PB_OFFSET 204
    mov     x0, x24
    bl      produce_attester_slashings
    mov     x24, x1
    cbnz    x0, 98f
    /* attestations: the draft's aggregates */
    PB_OFFSET 208
    add     x0, sp, #L
    mov     x1, x24
    bl      produce_attestations
    mov     x24, x1
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    98f
    cbnz    x0, 99f
    /* deposits: none; voluntary_exits */
    PB_OFFSET 212
    PB_OFFSET 216
    mov     x0, #GOSSIP_VOLUNTARY_EXIT
    mov     x1, x24
    bl      produce_records
    mov     x24, x1
    cbnz    x0, 98f
.if FORK >= FORK_BELLATRIX
    PB_OFFSET PB_PAYLOAD                    /* the payload, the empty one before the merge */
    ldp     x1, x2, [sp, #(L + 24)]
    cbnz    x1, 7f
.if FORK == FORK_BELLATRIX
    mov     x0, x24                         /* ExecutionPayload.empty(): the offsets of extra_data and transactions at 508 */
    mov     x1, #508
    bl      produce_room
    cbnz    x0, 98f
    mov     x0, x24
    mov     x1, #508
    bl      lantern_zero
    mov     w9, #508
    str     w9, [x24, #436]
    str     w9, [x24, #504]
    add     x24, x24, #508
    b       71f
.else
    b       96f
.endif
7:  mov     x1, x2
    mov     x0, x24
    bl      produce_room
    cbnz    x0, 98f
    mov     x0, x24
    ldp     x1, x2, [sp, #(L + 24)]
    add     x24, x24, x2
    bl      lantern_copy
71:
.endif
.if FORK >= FORK_CAPELLA
    PB_OFFSET PB_BLS
    mov     x0, #GOSSIP_BLS_TO_EXECUTION_CHANGE
    mov     x1, x24
    bl      produce_records
    mov     x24, x1
    cbnz    x0, 98f
.endif
.if FORK >= FORK_DENEB
    PB_OFFSET PB_COMMITMENTS                /* the bundle's commitments */
    ldp     x9, x10, [sp, #(L + 40)]
    cmp     x10, #12
    b.lo    96f
    ldp     w11, w12, [x9]
    cmp     x11, x12
    b.hi    96f
    cmp     x12, x10
    b.hi    96f
    sub     x0, x12, x11
    add     x1, x9, x11
    str     x1, [sp, #(L + 8)]
    str     x0, [sp, #(L + 16)]
    mov     x1, x0
    mov     x0, x24
    bl      produce_room
    cbnz    x0, 98f
    mov     x0, x24
    ldp     x1, x2, [sp, #(L + 8)]
    add     x24, x24, x2
    bl      lantern_copy
.endif
.if FORK >= FORK_ELECTRA
    PB_OFFSET PB_REQUESTS                   /* lantern_get_execution_requests of the result's request lists */
    ldr     x9, [x21, #16]
    ldp     x10, x11, [x9, #8]
    add     x10, x9, x10
    ldr     w12, [x10, #41]
    cmp     x12, x11
    b.hi    96f
    add     x13, sp, #(L + 112)             /* a ByteList view of them in the locals */
    mov     x14, x12                        /* its offset: from the view to the list */
    add     x15, x10, x12
    sub     x14, x15, x13
    sub     x15, x11, x12
    add     x16, x14, x15
    stp     x16, x14, [x13, #-24]
    str     x15, [x13, #-8]
    ldr     x9, [x23]                       /* the requests' room: the rest of out, as a ByteList at the write position less 24 */
    sub     x9, x9, #24
    add     x10, x23, x9
    ldp     x11, x12, [x24, #-24]
    stp     x11, x12, [sp, #(L + 256)]
    ldr     x11, [x24, #-8]
    str     x11, [sp, #(L + 272)]
    sub     x0, x24, #24
    sub     x9, x10, x0
    mov     x11, #24
    stp     x9, x11, [x0]
    str     xzr, [x0, #16]
    sub     x0, x13, #24
    sub     x1, x24, #24
    bl      lantern_get_execution_requests
    ldr     x12, [x24, #-8]                 /* the bytes written; the 24 bytes before them back */
    ldp     x9, x10, [sp, #(L + 256)]
    stp     x9, x10, [x24, #-24]
    ldr     x9, [sp, #(L + 272)]
    str     x9, [x24, #-8]
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    98f
    cbnz    x0, 96f
    add     x24, x24, x12
.endif
    sub     x9, x24, x25                    /* the block's bytes */
    str     x9, [x23, #16]
    ADDRESS x0, lantern_type_BeaconBlock    /* the state root: process_block of the decoded block, then the state's root */
    mov     x1, x23
    mov     x2, x22
    bl      node_decode
    cmp     x0, #1
    b.eq    98f
    b.hi    96f
    mov     x0, x19
    add     x2, sp, #(L + 64)
    ldr     x3, [x21, #8]
    mov     x4, x22
    add     x5, sp, #(L + 72)
    bl      lantern_process_block
    ldr     x9, [sp, #(L + 80)]
    str     x9, [x22]
    cbnz    x0, 99f
    ldr     x0, [sp, #(L + 72)]
    cbnz    x0, 99f
    mov     x0, x19
    mov     x1, #0
    mov     x2, x22
    add     x3, x25, #48
    bl      lantern_state_root
    cbnz    x0, 99f
    ldr     x9, [sp, #L]                    /* consensus_block_value: the balance after less before, plus the proposer's withdrawals */
    PART    x10, x11, x19, BeaconState_balances
    ldr     x10, [x10, x9, lsl #3]
    ldr     x11, [sp, #(L + 56)]
    sub     x12, x10, x11
.if FORK >= FORK_CAPELLA
    ldp     x13, x14, [sp, #(L + 24)]       /* the payload's withdrawals: from the offset at 508, 44 bytes each */
    cbz     x13, 81f
    ldr     w15, [x13, #508]
    cmp     x15, x14
    b.hi    81f
80: add     x16, x15, #44
    cmp     x16, x14
    b.hi    81f
    add     x16, x13, x15
    ldr     x10, [x16, #8]
    cmp     x10, x9
    b.ne    801f
    ldr     x10, [x16, #36]
    add     x12, x12, x10
801: add    x15, x15, #44
    b       80b
81:
.endif
    cmp     x12, #0
    csel    x12, xzr, x12, lt
    ldr     x9, [x21, #32]
    str     x12, [x9]
    ldr     x9, [x21, #24]                  /* execution_payload_value: the result's block_value, else 0 */
    stp     xzr, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
.if FORK >= FORK_CAPELLA
    ldr     x1, [sp, #(L + 8)]
    cbz     x1, 82f
    ldr     x9, [x21, #16]
    ldp     x10, x11, [x9, #8]
    add     x1, x9, x10
    add     x1, x1, #4
    ldr     x0, [x21, #24]
    mov     x2, #32
    bl      lantern_copy
82:
.endif
.if FORK >= FORK_DENEB
    add     x0, sp, #L                      /* BlockContents: the block, the bundle's proofs and blobs */
    bl      produce_contents
    cbnz    x0, 98f
.endif
    mov     x0, #LANTERN_OK
99: LEAVE 288
96: mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 288
97: mov     x0, #LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 288
98: ldr     x9, [sp, #(L + 80)]
    str     x9, [x22]
    mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 288
SPEC_END node_produce_block

/* L0: x0 = 0 when x1 bytes from x0 fit in the ByteList x23, else 1. Uses x16, x17. */
LOCAL_FUNCTION produce_room
    UNWIND_END_PROLOGUE
    ldr     x16, [x23]
    add     x16, x23, x16
    add     x17, x0, x1
    cmp     x17, x16
    cset    x0, hi
    ret
END_FUNCTION produce_room

/*
 * L0: (index x0, record x1) -> x0 = 1 when the index is in both attestations of the attester
 * slashing whose SSZ bytes follow the draft record x1, else 0. Uses x7, x9-x15.
 */
LOCAL_FUNCTION produce_in_slashing
    UNWIND_END_PROLOGUE
    ldr     x9, [x1, #8]                    /* its length */
    add     x1, x1, #16
    cmp     x9, #8
    b.lo    9f
    ldp     w10, w11, [x1]                  /* the attestations: [o1, o2), then [o2, end) */
    mov     x12, x10
    mov     x13, x11
    mov     x7, #0
1:  cmp     x12, x13
    b.hs    9f
    add     x14, x1, x12
    ldr     w15, [x14]                      /* its indices, from its offset */
    add     x15, x12, x15
2:  add     x14, x15, #8
    cmp     x14, x13
    b.hi    9f
    ldr     x14, [x1, x15]
    cmp     x14, x0
    b.eq    3f
    add     x15, x15, #8
    b       2b
3:  cbnz    x7, 4f                          /* in the first: then the second */
    mov     x7, #1
    mov     x12, x11
    mov     x13, x9
    b       1b
4:  mov     x0, #1
    ret
9:  mov     x0, #0
    ret
END_FUNCTION produce_in_slashing

/*
 * L2: (topic x0, write position x1) -> x0 = 0, or 1 for a short out; x1 = the write position. The
 * SSZ bytes of the draft's records of the topic in their order, back to back. x21 a record, x22
 * the records' end, x25 the topic, x27 the position.
 */
LOCAL_FUNCTION produce_records
    ENTER 0
    mov     x25, x0
    mov     x27, x1
    ldr     x9, [x20, #ProduceDraft_ops]
    ADDQ    x21, x20, PRODUCE_DRAFT_OPS
    add     x22, x21, x9
1:  cmp     x21, x22
    b.hs    8f
    ldp     x9, x1, [x21]
    cmp     x9, x25
    b.ne    5f
    mov     x0, x27
    bl      produce_room
    cbnz    x0, 9f
    mov     x0, x27
    add     x1, x21, #16
    ldr     x2, [x21, #8]
    add     x27, x27, x2
    bl      lantern_copy
5:  ldr     x10, [x21, #8]
    add     x10, x10, #(16 + 7)
    and     x10, x10, #~7
    add     x21, x21, x10
    b       1b
8:  mov     x0, #0
    mov     x1, x27
    LEAVE 0
9:  mov     x0, #1
    mov     x1, x27
    LEAVE 0
END_FUNCTION produce_records

/*
 * L2: (write position x0) -> x0 = 0, or 1 for a short out; x1 = the write position. The draft's
 * attester slashing records as an SSZ list: their offsets, then their bytes. x21 a record, x22 the
 * end, x25 their count, x26 the next offset, x27 the position, x28 the next offset's place.
 */
LOCAL_FUNCTION produce_attester_slashings
    ENTER 0
    mov     x27, x0
    ldr     x9, [x20, #ProduceDraft_ops]
    ADDQ    x21, x20, PRODUCE_DRAFT_OPS
    add     x22, x21, x9
    mov     x25, #0
    mov     x9, x21
1:  cmp     x9, x22
    b.hs    2f
    ldp     x10, x11, [x9]
    cmp     x10, #GOSSIP_ATTESTER_SLASHING
    cinc    x25, x25, eq
    add     x11, x11, #(16 + 7)
    and     x11, x11, #~7
    add     x9, x9, x11
    b       1b
2:  lsl     x26, x25, #2                    /* the offsets, the first slashing after them */
    mov     x0, x27
    mov     x1, x26
    bl      produce_room
    cbnz    x0, 9f
    mov     x28, x27
    add     x27, x27, x26
3:  cmp     x21, x22
    b.hs    8f
    ldp     x9, x10, [x21]
    cmp     x9, #GOSSIP_ATTESTER_SLASHING
    b.ne    4f
    str     w26, [x28], #4
    add     x26, x26, x10
    mov     x0, x27
    mov     x1, x10
    bl      produce_room
    cbnz    x0, 9f
    mov     x0, x27
    add     x1, x21, #16
    ldr     x2, [x21, #8]
    add     x27, x27, x2
    bl      lantern_copy
4:  ldr     x10, [x21, #8]
    add     x10, x10, #(16 + 7)
    and     x10, x10, #~7
    add     x21, x21, x10
    b       3b
8:  mov     x0, #0
    mov     x1, x27
    LEAVE 0
9:  mov     x0, #1
    mov     x1, x27
    LEAVE 0
END_FUNCTION produce_attester_slashings

/*
 * L1: (index x0, records x1, their end x2) -> x0 = 1 when a proposer slashing record of [x1, x2)
 * has the index as its proposer, or an attester slashing record has it in both attestations;
 * else 0. x19 the index, x20 a record, x21 the end.
 */
LOCAL_FUNCTION produce_slashed
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
1:  cmp     x20, x21
    b.hs    8f
    ldr     x9, [x20]
    cmp     x9, #GOSSIP_PROPOSER_SLASHING
    b.ne    2f
    ldr     x10, [x20, #(16 + 8)]           /* signed_header_1.message.proposer_index */
    cmp     x10, x19
    b.eq    9f
    b       3f
2:  cmp     x9, #GOSSIP_ATTESTER_SLASHING
    b.ne    3f
    mov     x0, x19
    mov     x1, x20
    bl      produce_in_slashing
    cbnz    x0, 9f
3:  ldr     x10, [x20, #8]
    add     x10, x10, #(16 + 7)
    and     x10, x10, #~7
    add     x20, x20, x10
    b       1b
8:  mov     x0, #0
    LEAVE 0
9:  mov     x0, #1
    LEAVE 0
END_FUNCTION produce_slashed

/*
 * L0: (the attester slashing's bytes x0, their count x1, records x2, their end x3) -> x0 = 1 when
 * an index is in both attestations (whose indices are sorted, as is_valid_indexed_attestation
 * holds them) and no proposer slashing record of [x2, x3) has it as its proposer; else 0. x4 a
 * place in the first list, x5 its end, x6 a place in the second, x7 its end. Uses x9-x13.
 */
LOCAL_FUNCTION produce_takes_slashing
    UNWIND_END_PROLOGUE
    cmp     x1, #8
    b.lo    8f
    ldp     w9, w10, [x0]                   /* the attestations: [o1, o2), [o2, count) */
    cmp     x9, x10
    b.hi    8f
    cmp     x10, x1
    b.hi    8f
    add     x11, x9, #228
    cmp     x11, x10
    b.hi    8f
    add     x11, x10, #228
    cmp     x11, x1
    b.hi    8f
    ldr     w11, [x0, x9]                   /* each one's indices: from its offset to its end */
    add     x4, x9, x11
    mov     x5, x10
    ldr     w11, [x0, x10]
    add     x6, x10, x11
    mov     x7, x1
1:  add     x9, x4, #8
    cmp     x9, x5
    b.hi    8f
    add     x9, x6, #8
    cmp     x9, x7
    b.hi    8f
    ldr     x9, [x0, x4]
    ldr     x10, [x0, x6]
    cmp     x9, x10
    b.lo    2f
    b.hi    3f
    mov     x11, x2                         /* in both: a proposer slashing's proposer? */
4:  cmp     x11, x3
    b.hs    9f
    ldp     x12, x13, [x11]
    cmp     x12, #GOSSIP_PROPOSER_SLASHING
    b.ne    5f
    ldr     x12, [x11, #(16 + 8)]
    cmp     x12, x9
    b.eq    6f
5:  add     x13, x13, #(16 + 7)
    and     x13, x13, #~7
    add     x11, x11, x13
    b       4b
6:  add     x6, x6, #8
2:  add     x4, x4, #8
    b       1b
3:  add     x6, x6, #8
    b       1b
8:  mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION produce_takes_slashing

.set PB_COMMITTEE_BITS, (MAX_COMMITTEES_PER_SLOT + 7) / 8
/* An Attestation's fixed bytes: the bits' offset, data, signature, and from electra committee_bits */
.if FORK >= FORK_ELECTRA
.set PB_ATT_COMMITTEE, PB_COMMITTEE_BITS
.else
.set PB_ATT_COMMITTEE, 0
.endif
.set PB_ATT_FIXED, 228 + PB_ATT_COMMITTEE

/* L0: x0 = 1 when the 128 bytes at x0 and x1 are equal, else 0. Uses x9-x12. */
LOCAL_FUNCTION produce_same_data
    UNWIND_END_PROLOGUE
    mov     x9, #0
1:  ldr     x10, [x0, x9]
    ldr     x11, [x1, x9]
    cmp     x10, x11
    b.ne    2f
    add     x9, x9, #8
    cmp     x9, #128
    b.lo    1b
    mov     x0, #1
    ret
2:  mov     x0, #0
    ret
END_FUNCTION produce_same_data

/*
 * L2: (the block's locals x0, write position x1) -> x0 = 0, 1 for a short out or scratch, or a
 * status of crypto_bls_aggregate; x1 = the write position. The draft's aggregates chosen by
 * data.slot descending, then order, at most the fork's limit; before electra an Attestation of
 * each, from electra one Attestation for each data of the aggregates of every committee
 * (compute_on_chain_aggregate). The list: offsets, then the attestations. x21 the aggregates, x25
 * their count, x26 the chosen indices (in scratch, after a flag byte for each aggregate), x27 the
 * position, x28 the chosen count. Locals: L the scratch size, L+8 an index, L+16 the bits' cursor.
 */
LOCAL_FUNCTION produce_attestations
    ENTER 32
    mov     x27, x1
    ldr     x25, [x20, #ProduceDraft_aggregates]
    ADDQ    x21, x20, PRODUCE_DRAFT_AGGREGATES
    ldr     x9, [x22]                       /* the flags and the chosen at the end of scratch */
    str     x9, [sp, #L]
    add     x10, x25, #(8 * PB_MAX_ATTESTATIONS + 7)
    and     x10, x10, #~7
    add     x11, x10, #1024
    cmp     x9, x11
    b.lo    97f
    sub     x9, x9, x10
    str     x9, [x22]
    add     x26, x22, x9
    mov     x0, x26
    mov     x1, x25
    bl      lantern_zero
    add     x26, x26, x25                   /* the chosen indices after the flags */
    add     x26, x26, #7
    and     x26, x26, #~7
    mov     x28, #0
1:  cmp     x28, #PB_MAX_ATTESTATIONS       /* the next: of the highest slot, then the lowest order */
    b.hs    3f
    mov     x10, #-1
    mov     x11, #0
    mov     x12, #0                         /* the best's slot */
2:  cmp     x11, x25
    b.hs    21f
    sub     x13, x26, x25                   /* its flag: the flags end where the chosen start, rounded */
    ldr     x9, [sp, #L]
    ldr     x14, [x22]
    add     x14, x22, x14                   /* the flags */
    ldrb    w15, [x14, x11]
    cbnz    w15, 22f
    mov     x13, #DraftAggregate__mem
    madd    x13, x11, x13, x21
    ldr     x14, [x13]                      /* data.slot */
    cmn     x10, #1
    b.eq    23f
    cmp     x14, x12
    b.ls    22f
23: mov     x10, x11
    mov     x12, x14
22: add     x11, x11, #1
    b       2b
21: cmn     x10, #1
    b.eq    3f
    str     x10, [x26, x28, lsl #3]
    add     x28, x28, #1
    ldr     x14, [x22]                      /* chosen: its flag, from electra those of its data too */
    add     x14, x22, x14
    mov     w15, #1
    strb    w15, [x14, x10]
.if FORK >= FORK_ELECTRA
    mov     x13, #DraftAggregate__mem
    madd    x0, x10, x13, x21
    str     x0, [sp, #(L + 8)]
    mov     x11, #0
24: cmp     x11, x25
    b.hs    1b
    mov     x13, #DraftAggregate__mem
    madd    x1, x11, x13, x21
    ldr     x0, [sp, #(L + 8)]
    str     x11, [sp, #(L + 16)]
    bl      produce_same_data
    ldr     x11, [sp, #(L + 16)]
    cbz     x0, 25f
    ldr     x14, [x22]
    add     x14, x22, x14
    mov     w15, #1
    strb    w15, [x14, x11]
25: add     x11, x11, #1
    b       24b
.else
    b       1b
.endif
3:  lsl     x9, x28, #2                     /* the offsets: the size of each attestation */
    mov     x0, x27
    mov     x1, x9
    bl      produce_room
    cbnz    x0, 98f
    mov     x10, x9
    mov     x11, #0
4:  cmp     x11, x28
    b.hs    5f
    str     w10, [x27, x11, lsl #2]
    ldr     x12, [x26, x11, lsl #3]
    mov     x0, x12
    bl      produce_att_bits
    add     x13, x0, #(8 + 7)               /* the bits: as many as the length, and the end bit */
    lsr     x13, x13, #3
    add     x10, x10, x13
    add     x10, x10, #(PB_ATT_FIXED)
    add     x11, x11, #1
    b       4b
5:  add     x27, x27, x9
    mov     x11, #0
6:  cmp     x11, x28                        /* each attestation */
    b.hs    8f
    str     x11, [sp, #(L + 16)]
    ldr     x12, [x26, x11, lsl #3]
    mov     x13, #DraftAggregate__mem
    madd    x24, x12, x13, x21              /* the chosen aggregate (the caller keeps its own position) */
    mov     x0, x12
    bl      produce_att_bits
    add     x13, x0, #(8 + 7)
    lsr     x13, x13, #3
    add     x1, x13, #(PB_ATT_FIXED)
    mov     x0, x27
    bl      produce_room
    cbnz    x0, 98f
    mov     w9, #(PB_ATT_FIXED)
    str     w9, [x27]
    add     x0, x27, #4                     /* data */
    mov     x1, x24
    mov     x2, #128
    bl      lantern_copy
    add     x0, x27, #132                   /* signature: the first's */
    ADDQ    x1, x24, DraftAggregate_signature
    mov     x2, #96
    bl      lantern_copy
    add     x0, x27, #228                   /* from electra the committee bits; the aggregation bits, zero */
    ldr     x0, [sp, #(L + 16)]
    ldr     x0, [x26, x0, lsl #3]
    bl      produce_att_bits
    add     x1, x0, #(8 + 7)
    lsr     x1, x1, #3
    add     x1, x1, #(PB_ATT_COMMITTEE)
    add     x0, x27, #228
    bl      lantern_zero
    str     xzr, [sp, #(L + 8)]             /* the bits' cursor */
.if FORK >= FORK_ELECTRA
    mov     x11, #0                         /* each committee in order: its aggregate of the data */
61: cmp     x11, #MAX_COMMITTEES_PER_SLOT
    b.hs    7f
    mov     x12, #0
62: cmp     x12, x25
    b.hs    66f
    mov     x13, #DraftAggregate__mem
    madd    x13, x12, x13, x21
    ldr     x14, [x13, #DraftAggregate_committee_index]
    cmp     x14, x11
    b.ne    65f
    stp     x11, x12, [sp, #(L + 16)]
    mov     x0, x24
    mov     x1, x13
    bl      produce_same_data
    ldp     x11, x12, [sp, #(L + 16)]
    cbz     x0, 65f
    mov     x13, #DraftAggregate__mem
    madd    x13, x12, x13, x21
    lsr     x9, x11, #3                     /* its committee's bit */
    and     x10, x11, #7
    add     x14, x27, #228
    ldrb    w15, [x14, x9]
    mov     w16, #1
    lsl     w16, w16, w10
    orr     w15, w15, w16
    strb    w15, [x14, x9]
    cmp     x13, x24                        /* its signature, after the first's */
    b.eq    63f
    stp     x11, x12, [sp, #(L + 16)]
    add     x0, x27, #132
    ADDQ    x1, x13, DraftAggregate_signature
    mov     x2, x22
    bl      produce_add_signature
    mov     x9, x0
    ldp     x11, x12, [sp, #(L + 16)]
    cmp     x9, #LANTERN_BUFFER_TOO_SMALL
    b.eq    97f
    cbnz    x9, 96f
    mov     x13, #DraftAggregate__mem
    madd    x13, x12, x13, x21
63: add     x0, x27, #(228 + PB_COMMITTEE_BITS)  /* its bits at the cursor */
    mov     x1, x13
    ldr     x2, [sp, #(L + 8)]
    bl      produce_copy_bits
    str     x0, [sp, #(L + 8)]
    b       66f
65: add     x12, x12, #1
    b       62b
66: add     x11, x11, #1
    b       61b
.else
    add     x0, x27, #228
    mov     x1, x24
    mov     x2, #0
    bl      produce_copy_bits
    str     x0, [sp, #(L + 8)]
.endif
7:  ldr     x9, [sp, #(L + 8)]              /* the end bit */
    add     x10, x27, #(PB_ATT_FIXED)
    lsr     x11, x9, #3
    and     x12, x9, #7
    ldrb    w13, [x10, x11]
    mov     w14, #1
    lsl     w14, w14, w12
    orr     w13, w13, w14
    strb    w13, [x10, x11]
    add     x11, x11, #1
    add     x27, x10, x11
    ldr     x11, [sp, #(L + 16)]
    add     x11, x11, #1
    b       6b
8:  ldr     x9, [sp, #L]
    str     x9, [x22]
    mov     x0, #0
    mov     x1, x27
    LEAVE 32
96: ldr     x10, [sp, #L]
    str     x10, [x22]
    mov     x0, x9
    mov     x1, x27
    LEAVE 32
97: ldr     x9, [sp, #L]
    str     x9, [x22]
98: mov     x0, #1
    mov     x1, x27
    LEAVE 32
END_FUNCTION produce_attestations

/*
 * L0: (index x0) -> x0: the aggregation bits of the attestation of the draft's aggregate x0, x21
 * the aggregates, x25 their count: its length; from electra the lengths of the aggregates of its
 * data. Uses x1-x4, x13-x15: its callers keep x9-x12.
 */
LOCAL_FUNCTION produce_att_bits
    UNWIND_END_PROLOGUE
    mov     x13, #DraftAggregate__mem
    madd    x14, x0, x13, x21
.if FORK >= FORK_ELECTRA
    mov     x0, #0
    mov     x15, #0
1:  cmp     x15, x25
    b.hs    3f
    madd    x1, x15, x13, x21
    mov     x2, #0
2:  ldr     x3, [x14, x2]
    ldr     x4, [x1, x2]
    cmp     x3, x4
    b.ne    4f
    add     x2, x2, #8
    cmp     x2, #128
    b.lo    2b
    ldr     x3, [x1, #DraftAggregate_length]
    add     x0, x0, x3
4:  add     x15, x15, #1
    b       1b
3:  ret
.else
    ldr     x0, [x14, #DraftAggregate_length]
    ret
.endif
END_FUNCTION produce_att_bits

/* L0: (bits x0, aggregate x1, cursor x2) -> x0: the aggregate's length bits set at bit x2 of x0 on; the cursor after them. Uses x9-x15. */
LOCAL_FUNCTION produce_copy_bits
    UNWIND_END_PROLOGUE
    ldr     x9, [x1, #DraftAggregate_length]
    add     x10, x1, #DraftAggregate_bits
    mov     x11, #0
1:  cmp     x11, x9
    b.hs    2f
    lsr     x12, x11, #3
    ldrb    w12, [x10, x12]
    and     x13, x11, #7
    lsr     w12, w12, w13
    tbz     w12, #0, 3f
    add     x13, x2, x11
    lsr     x14, x13, #3
    and     x15, x13, #7
    ldrb    w12, [x0, x14]
    mov     w13, #1
    lsl     w13, w13, w15
    orr     w12, w12, w13
    strb    w12, [x0, x14]
3:  add     x11, x11, #1
    b       1b
2:  add     x0, x2, x9
    ret
END_FUNCTION produce_copy_bits

.if FORK >= FORK_DENEB
/*
 * L1: (the block's locals x0) -> x0 = 0, or 1 for a short out: out x23 holds the block from offset
 * 24; it becomes the BlockContents: the block moved 12 bytes on, the three offsets, the bundle's
 * proofs and blobs (the bundle at locals + 40, its bytes at + 48). Uses x1-x15.
 */
LOCAL_FUNCTION produce_contents
    FRAME 32
    ldp     x9, x10, [x0, #40]              /* the bundle: its offsets of commitments, proofs, blobs */
    cmp     x10, #12
    b.lo    9f
    ldp     w11, w12, [x9, #4]
    cmp     x11, x12
    b.hi    9f
    cmp     x12, x10
    b.hi    9f
    sub     x13, x12, x11                   /* the proofs' bytes, then the blobs' */
    sub     x14, x10, x12
    ldr     x15, [x23, #16]                 /* the block's */
    add     x1, x15, #12
    add     x1, x1, x13
    add     x1, x1, x14
    ldr     x2, [x23]
    sub     x2, x2, #24
    cmp     x1, x2
    b.hi    9f
    str     x1, [x23, #16]
    add     x3, x23, #24                    /* the block on by 12, from its end */
    mov     x4, x15
1:  cbz     x4, 2f
    sub     x4, x4, #1
    ldrb    w5, [x3, x4]
    add     x6, x4, #12
    strb    w5, [x3, x6]
    b       1b
2:  mov     w5, #12
    str     w5, [x3]
    add     w5, w5, w15
    str     w5, [x3, #4]
    add     w5, w5, w13
    str     w5, [x3, #8]
    add     x0, x3, #12                     /* the proofs, then the blobs */
    add     x0, x0, x15
    add     x1, x9, x11
    mov     x2, x13
    stp     x0, x13, [sp, #16]
    stp     x9, x12, [sp, #32]
    bl      lantern_copy
    ldp     x0, x13, [sp, #16]
    add     x0, x0, x13
    ldp     x9, x12, [sp, #32]
    add     x1, x9, x12
    ldr     x10, [x23, #16]
    sub     x10, x10, #12
    ldr     x11, [x23, #16]
    mov     x2, x0
    add     x2, x23, #24
    add     x2, x2, x11
    sub     x2, x2, x0
    bl      lantern_copy
    mov     x0, #0
    UNFRAME 32
9:  mov     x0, #1
    UNFRAME 32
END_FUNCTION produce_contents
.endif

/* ---------------------------------------------------------------- publishBlockV2 */


/*
 * (body, json, scratch, out, facts): node.md, lantern_node_publish_decode. x19 body, x20 json,
 * x21 scratch, x22 out, x23 facts, x24 the type, x25 the value's bytes, x26 their count, x27 the
 * scratch size. Locals: L a JsonFault (128).
 */
SPEC_FUNCTION node_publish_decode
    ENTER 128
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x27, [x21]
.if FORK >= FORK_DENEB
    ADDRESS x24, lantern_type_SignedBlockContents
.else
    ADDRESS x24, lantern_type_SignedBeaconBlock
.endif
    mov     x9, #24
    str     x9, [x22, #8]
    str     xzr, [x22, #16]
    cbz     x20, 1f
    mov     x0, x24                         /* JSON: its SSZ bytes */
    mov     x1, x19
    mov     x2, x21
    mov     x3, x22
    add     x4, sp, #L
    CALL_GLOBAL lantern_json_decode
    str     x27, [x21]
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    9f
    cbnz    x0, 8f
    b       2f
1:  ldp     x9, x10, [x19, #8]              /* SSZ: the bytes as they are */
    ldr     x11, [x22]
    add     x12, x10, #24
    cmp     x12, x11
    b.hi    9f
    str     x10, [x22, #16]
    add     x0, x22, #24
    add     x1, x19, x9
    mov     x2, x10
    bl      lantern_copy
2:  mov     x0, x24                         /* a value of the type */
    mov     x1, x22
    mov     x2, x21
    bl      node_decode
    str     x27, [x21]
    cmp     x0, #1
    b.eq    9f
    cbnz    x0, 8f
    add     x25, x22, #24
    ldr     x26, [x22, #16]
.if FORK >= FORK_DENEB
    ldp     w9, w10, [x25]                  /* SignedBlockContents: the block [o0, o1), kzg_proofs [o1, o2), blobs [o2, n) */
    ldr     w11, [x25, #8]
    ldr     w12, [x25, x9]                  /* the block's message, its body: offsets checked by the decode */
    add     x12, x9, x12
    add     x13, x25, x12
    ldr     w14, [x13, #80]
    add     x12, x12, x14                   /* the body's place */
    add     x13, x25, x12
    ldr     w14, [x13, #PB_COMMITMENTS]     /* blob_kzg_commitments: [c0, c1) of the body */
.if FORK >= FORK_ELECTRA
    ldr     w15, [x13, #PB_REQUESTS]
.else
    sub     x15, x10, x12
.endif
    sub     x15, x15, x14
    mov     x16, #48
    udiv    x15, x15, x16                   /* the blob count */
    sub     x14, x11, x10                   /* the proofs' count */
    udiv    x14, x14, x16
.if FORK >= FORK_FULU
    mov     x16, #CELLS_PER_EXT_BLOB
    mul     x16, x15, x16
    cmp     x14, x16
.else
    cmp     x14, x15
.endif
    b.ne    8f
    sub     x14, x26, x11                   /* the blobs' count */
    MOVQ    x16, PUB_BLOB_BYTES
    udiv    x14, x14, x16
    cmp     x14, x15
    b.ne    8f
    str     x15, [x23, #8]
    sub     x26, x10, x9                    /* the signed block to the front */
    str     x26, [x22, #16]
    mov     x0, x25
    add     x1, x25, x9
    mov     x2, x26
    bl      lantern_copy
.else
    str     xzr, [x23, #8]
.endif
    ldr     w9, [x25]                       /* facts: the slot, the blob count, 0 */
    ldr     x9, [x25, x9]
    str     x9, [x23]
    str     xzr, [x23, #16]
    mov     x0, #LANTERN_OK
    LEAVE 128
8:  mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 128
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 128
SPEC_END node_publish_decode

/*
 * (gossip, block, sidecars, level, scratch): node.md, lantern_node_publish_check. x19 gossip,
 * x20 block, x21 sidecars, x22 level, x23 scratch, x24 a sidecar, x25 their end, x26 the scratch
 * size. Locals: L a Result, L+8 a root (32), L+40 an index, L+48 execution_valid 1, L+64 the
 * counts of seen's parts (40).
 */
SPEC_FUNCTION node_publish_check
    ENTER 112
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ldr     x26, [x23]
    ldr     x9, [x19, #NodeGossip_seen]     /* the counts of seen's parts, for a check that fails */
    ldr     x10, [x9, #(Seen_keys + 8)]
    ldr     x11, [x9, #(Seen_bits + 8)]
    stp     x10, x11, [sp, #(L + 64)]
    ldr     x10, [x9, #(Seen_blocks + 8)]
    ldr     x11, [x9, #(Seen_headers + 8)]
    stp     x10, x11, [sp, #(L + 80)]
    ldr     x10, [x9, #Seen_header_bytes]
    str     x10, [sp, #(L + 96)]
    mov     x9, #GOSSIP_BEACON_BLOCK        /* the beacon_block topic's checks */
    str     x9, [x19, #NodeGossip_topic]
    str     xzr, [x19, #NodeGossip_subnet]
    mov     x0, x19
    mov     x1, x20
    mov     x2, x23
    bl      publish_gossip
    cbnz    x0, 9f
.if FORK >= FORK_DENEB
    cbz     x21, 5f                         /* each sidecar's, on its subnet */
    ldp     x9, x10, [x21, #8]
    add     x24, x21, x9
    add     x25, x24, x10
1:  cmp     x24, x25
    b.hs    5f
    ldr     x9, [x24, #8]
    ldr     x10, [x24, x9]                  /* its index, at byte 0 of its bytes */
    ldr     x11, [x19, #NodeGossip_config]
.if FORK >= FORK_FULU
    mov     x12, #GOSSIP_DATA_COLUMN_SIDECAR
    ldr     x13, [x11, #CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT]
.elseif FORK >= FORK_ELECTRA
    mov     x12, #GOSSIP_BLOB_SIDECAR
    LDQ     x13, x11, CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA
.else
    mov     x12, #GOSSIP_BLOB_SIDECAR
    LDQ     x13, x11, CONFIG_BLOB_SIDECAR_SUBNET_COUNT
.endif
    cbz     x13, 8f
    udiv    x14, x10, x13
    msub    x14, x14, x13, x10
    stp     x12, x14, [x19, #NodeGossip_topic]
    mov     x0, x19
    mov     x1, x24
    mov     x2, x23
    bl      publish_gossip
    cbnz    x0, 9f
    ldr     x9, [x24]
    add     x24, x24, x9
    b       1b
5:
.endif
    cmp     x22, #2                         /* consensus: process_block on the parent's post-state at the slot */
    b.lo    7f
    ADDRESS x0, lantern_type_SignedBeaconBlock
    mov     x1, x20
    mov     x2, x23
    bl      node_decode
    cmp     x0, #1
    b.eq    6f
    cbnz    x0, 8f
    ldr     x9, [x1, #SignedBeaconBlock_message]
    add     x20, x1, x9                     /* the block, decoded */
    mov     x9, #1
    str     x9, [sp, #(L + 48)]
    ldr     x0, [x19, #NodeGossip_proposer]
    mov     x1, x20
    add     x2, sp, #(L + 48)
    ldr     x3, [x19, #NodeGossip_config]
    mov     x4, x23
    add     x5, sp, #L
    bl      lantern_process_block
    cbnz    x0, 4f
    ldr     x0, [sp, #L]
    cbnz    x0, 4f
    ldr     x0, [x19, #NodeGossip_proposer]
    ldr     x1, [x19, #NodeGossip_config]
    ldr     x1, [x1, #CONFIG_STATE_CACHE]
    mov     x2, x23
    add     x3, sp, #(L + 8)
    bl      lantern_state_root
    cbnz    x0, 4f
    ADDQ    x9, x20, BeaconBlock_state_root
    add     x10, sp, #(L + 8)
    ldp     x11, x12, [x9]
    ldp     x13, x14, [x10]
    cmp     x11, x13
    ccmp    x12, x14, #0, eq
    b.ne    3f
    ldp     x11, x12, [x9, #16]
    ldp     x13, x14, [x10, #16]
    cmp     x11, x13
    ccmp    x12, x14, #0, eq
    b.eq    7f
3:  mov     x0, #LANTERN_INVALID_STATE_ROOT
4:  str     x26, [x23]
    b       9f
7:  str     x26, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 112
6:  str     x26, [x23]
    mov     x0, #LANTERN_BUFFER_TOO_SMALL
    b       9f
8:  str     x26, [x23]
    mov     x0, #LANTERN_INVALID_ENCODING
9:  ldr     x9, [x19, #NodeGossip_seen]     /* a check that fails, or no room: seen as it was */
    ldp     x10, x11, [sp, #(L + 64)]
    str     x10, [x9, #(Seen_keys + 8)]
    str     x11, [x9, #(Seen_bits + 8)]
    ldp     x10, x11, [sp, #(L + 80)]
    str     x10, [x9, #(Seen_blocks + 8)]
    str     x11, [x9, #(Seen_headers + 8)]
    ldr     x10, [sp, #(L + 96)]
    str     x10, [x9, #Seen_header_bytes]
    LEAVE 112
SPEC_END node_publish_check

/*
 * L1: (gossip x0, data x1, scratch x2) -> x0: LANTERN_OK when lantern_node_gossip of the data
 * holds, else its status or its result. Locals: a Result, a root (32), an index.
 */
LOCAL_FUNCTION publish_gossip
    FRAME 48
    add     x3, sp, #16
    add     x4, sp, #24
    add     x5, sp, #56
    bl      lantern_node_gossip
    cbnz    x0, 9f
    ldr     x0, [sp, #16]
9:  UNFRAME 48
END_FUNCTION publish_gossip

.if FORK >= FORK_DENEB

/*
 * (body, json, scratch, out): node.md, lantern_node_publish_sidecars. x19 body, x20 json, x21
 * scratch, x22 out, x23 the SignedBlockContents value, x24 its block's body, x25 the blob count,
 * x26 a sidecar, x27 a counter, x28 the scratch size. Locals: L the signed header (208), L+208 a
 * GeneralizedIndex, L+216 a JsonFault (128), then a Branch of the commitments' list (24 + 128),
 * L+368 the KzgScratch, L+376 the cells, L+384 the stride.
 */
SPEC_FUNCTION node_publish_sidecars
    ENTER 400
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldr     x28, [x21]
    ldr     x9, [x19, #16]                  /* the SSZ bytes at the end of scratch: 24 + the body's length */
    add     x9, x9, #(24 + 7)
    and     x9, x9, #~7
    add     x10, x9, #64
    cmp     x10, x28
    b.hs    8f
    sub     x10, x28, x9
    str     x10, [x21]
    add     x23, x21, x10
    mov     x11, #24
    stp     x9, x11, [x23]
    str     xzr, [x23, #16]
    cbz     x20, 1f
    ADDRESS x0, lantern_type_SignedBlockContents    /* JSON: its SSZ bytes */
    mov     x1, x19
    mov     x2, x21
    mov     x3, x23
    add     x4, sp, #(L + 216)
    CALL_GLOBAL lantern_json_decode
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    8f
    cbnz    x0, 9f
    b       2f
1:  ldp     x9, x10, [x19, #8]              /* SSZ: the bytes as they are */
    str     x10, [x23, #16]
    add     x0, x23, #24
    add     x1, x19, x9
    mov     x2, x10
    bl      lantern_copy
2:  ADDRESS x0, lantern_type_SignedBlockContents    /* its value */
    mov     x1, x23
    mov     x2, x21
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    9f
    mov     x23, x1
    PART    x9, x10, x23, SignedBlockContents_signed_block  /* compute_signed_block_header */
    PART    x11, x10, x9, SignedBeaconBlock_message
    ldr     x12, [x11, #BeaconBlock_slot]
    ldr     x13, [x11, #BeaconBlock_proposer_index]
    stp     x12, x13, [sp, #L]
    PART    x24, x10, x11, BeaconBlock_body
    add     x0, sp, #(L + 16)
    add     x1, x11, #BeaconBlock_parent_root
    COPY32  x0, x1
    add     x0, sp, #(L + 48)
    add     x1, x11, #BeaconBlock_state_root
    COPY32  x0, x1
    add     x0, sp, #(L + 112)
    add     x1, x9, #SignedBeaconBlock_signature
    mov     x2, #96
    bl      lantern_copy
    ADDRESS x0, lantern_type_BeaconBlockBody
    mov     x1, x24
    mov     x2, x21
    add     x3, sp, #(L + 80)
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 8f
    PART    x9, x25, x24, BeaconBlockBody_blob_kzg_commitments
.if FORK >= FORK_FULU
    MOVQ    x9, PUB_CELL_BYTES + 96         /* the stride: a ByteList of a column sidecar of the count */
    MOVQ    x10, PUB_COLUMN_FIXED + 24 + 7
    madd    x9, x25, x9, x10
    and     x9, x9, #~7
    str     x9, [sp, #(L + 384)]
    mov     x10, #NUMBER_OF_COLUMNS
    mul     x10, x9, x10
    add     x10, x10, #24
    ldr     x11, [x22]
    cmp     x10, x11
    b.hi    8f
    mov     x9, #PUB_COMMITMENTS_GINDEX     /* the commitments' branch, the same for each column */
    str     x9, [sp, #(L + 208)]
    mov     x9, #(24 + 32 * KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH)
    str     x9, [sp, #(L + 216)]
    ADDRESS x0, lantern_type_BeaconBlockBody
    mov     x1, x24
    add     x2, sp, #(L + 208)
    mov     x3, x21
    add     x4, sp, #(L + 216)
    CALL_GLOBAL ssz_build_proof
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    8f
    cbnz    x0, 9f
    mov     x27, #0                         /* each column: its fixed part, the commitments and its proofs */
    add     x26, x22, #24
3:  cmp     x27, #NUMBER_OF_COLUMNS
    b.hs    4f
    ldr     x9, [sp, #(L + 384)]
    MOVQ    x10, PUB_CELL_BYTES + 96
    MOVQ    x11, PUB_COLUMN_FIXED
    madd    x10, x25, x10, x11              /* its length */
    mov     x11, #24
    stp     x9, x11, [x26]
    str     x10, [x26, #16]
    str     x27, [x26, #24]                 /* index */
    MOVQ    x9, PUB_COLUMN_FIXED            /* the offsets of column, kzg_commitments, kzg_proofs */
    str     w9, [x26, #(24 + 8)]
    MOVQ    x10, PUB_CELL_BYTES
    madd    x9, x25, x10, x9
    str     w9, [x26, #(24 + 12)]
    mov     x10, #48
    madd    x9, x25, x10, x9
    str     w9, [x26, #(24 + 16)]
    add     x0, x26, #(24 + 20)             /* signed_block_header */
    add     x1, sp, #L
    mov     x2, #PUB_HEADER_BYTES
    bl      lantern_copy
    add     x0, x26, #(24 + 20 + PUB_HEADER_BYTES)  /* kzg_commitments_inclusion_proof */
    add     x1, sp, #(L + 216 + 24)
    mov     x2, #(32 * KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH)
    bl      lantern_copy
    ldr     w9, [x26, #(24 + 12)]           /* kzg_commitments: the body's */
    add     x0, x26, #24
    add     x0, x0, x9
    PART    x1, x9, x24, BeaconBlockBody_blob_kzg_commitments
    mov     x10, #48
    mul     x2, x25, x10
    bl      lantern_copy
    mov     x13, #0                         /* kzg_proofs: proof c of each blob */
31: cmp     x13, x25
    b.hs    32f
    ldr     w9, [x26, #(24 + 16)]
    add     x0, x26, #24
    add     x0, x0, x9
    mov     x10, #48
    madd    x0, x13, x10, x0
    PART    x1, x9, x23, SignedBlockContents_kzg_proofs
    mov     x10, #CELLS_PER_EXT_BLOB
    madd    x10, x13, x10, x27
    mov     x11, #48
    madd    x1, x10, x11, x1
    ldp     x9, x10, [x1]
    stp     x9, x10, [x0]
    ldp     x9, x10, [x1, #16]
    stp     x9, x10, [x0, #16]
    ldp     x9, x10, [x1, #32]
    stp     x9, x10, [x0, #32]
    add     x13, x13, #1
    b       31b
32: ldr     x9, [sp, #(L + 384)]
    add     x26, x26, x9
    add     x27, x27, #1
    b       3b
4:  ldr     x9, [x21]                       /* the cells of each blob: a KzgScratch and the cells at the end of scratch */
    MOVQ    x10, CRYPTO_KZG_SCRATCH + CELLS_PER_EXT_BLOB * PUB_CELL_BYTES + 64
    cmp     x9, x10
    b.lo    8f
    sub     x9, x9, x10
    str     x9, [x21]
    add     x9, x21, x9
    add     x9, x9, #63
    and     x9, x9, #~63
    MOVQ    x10, CRYPTO_KZG_SCRATCH
    str     x10, [x9]
    str     x9, [sp, #(L + 368)]
    add     x9, x9, x10
    str     x9, [sp, #(L + 376)]
    mov     x27, #0                         /* blob b: its cells, then cell c to column c's place b */
5:  cmp     x27, x25
    b.hs    7f
    PART    x0, x9, x23, SignedBlockContents_blobs
    MOVQ    x10, PUB_BLOB_BYTES
    madd    x0, x27, x10, x0
    ldr     x1, [sp, #(L + 368)]
    ldr     x2, [sp, #(L + 376)]
    CALL_GLOBAL crypto_kzg_compute_cells
    cmp     x0, #CRYPTO_BUFFER_TOO_SMALL
    b.eq    8f
    cbnz    x0, 9f
    mov     x26, #0
6:  cmp     x26, #NUMBER_OF_COLUMNS
    b.hs    61f
    ldr     x9, [sp, #(L + 384)]
    add     x0, x22, #24
    madd    x0, x26, x9, x0
    MOVQ    x9, PUB_COLUMN_FIXED + 24
    add     x0, x0, x9
    MOVQ    x9, PUB_CELL_BYTES
    madd    x0, x27, x9, x0
    ldr     x1, [sp, #(L + 376)]
    madd    x1, x26, x9, x1
    mov     x2, x9
    bl      lantern_copy
    add     x26, x26, #1
    b       6b
61: add     x27, x27, #1
    b       5b
7:  ldr     x9, [sp, #(L + 384)]
    mov     x10, #NUMBER_OF_COLUMNS
    mul     x9, x9, x10
    str     x9, [x22, #16]
.else
    MOVQ    x9, PUB_BLOB_SIDECAR + 24       /* a BlobSidecar for each blob */
    mul     x9, x25, x9
    add     x9, x9, #24
    ldr     x10, [x22]
    cmp     x9, x10
    b.hi    8f
    mov     x27, #0
    add     x26, x22, #24
3:  cmp     x27, x25
    b.hs    7f
    MOVQ    x9, PUB_BLOB_SIDECAR + 24
    mov     x10, #24
    stp     x9, x10, [x26]
    MOVQ    x9, PUB_BLOB_SIDECAR
    str     x9, [x26, #16]
    str     x27, [x26, #24]                 /* index */
    add     x0, x26, #(24 + 8)              /* blob */
    PART    x1, x9, x23, SignedBlockContents_blobs
    MOVQ    x2, PUB_BLOB_BYTES
    madd    x1, x27, x2, x1
    bl      lantern_copy
    ADDQ    x0, x26, 24 + 8 + PUB_BLOB_BYTES    /* kzg_commitment */
    PART    x1, x9, x24, BeaconBlockBody_blob_kzg_commitments
    mov     x2, #48
    madd    x1, x27, x2, x1
    bl      lantern_copy
    ADDQ    x0, x26, 24 + 8 + PUB_BLOB_BYTES + 48   /* kzg_proof */
    PART    x1, x9, x23, SignedBlockContents_kzg_proofs
    mov     x2, #48
    madd    x1, x27, x2, x1
    bl      lantern_copy
    MOVQ    x9, PUB_COMMITMENTS_GINDEX << 13    /* the inclusion proof, its Branch header in the header's place */
    add     x9, x9, x27
    str     x9, [sp, #(L + 208)]
    ADDQ    x4, x26, 24 + 8 + PUB_BLOB_BYTES + 96 + PUB_HEADER_BYTES - 24
    mov     x9, #(24 + 32 * KZG_COMMITMENT_INCLUSION_PROOF_DEPTH)
    str     x9, [x4]
    ADDRESS x0, lantern_type_BeaconBlockBody
    mov     x1, x24
    add     x2, sp, #(L + 208)
    mov     x3, x21
    CALL_GLOBAL ssz_build_proof
    cmp     x0, #SSZ_BUFFER_TOO_SMALL
    b.eq    8f
    cbnz    x0, 9f
    ADDQ    x0, x26, 24 + 8 + PUB_BLOB_BYTES + 96   /* signed_block_header, over the Branch header */
    add     x1, sp, #L
    mov     x2, #PUB_HEADER_BYTES
    bl      lantern_copy
    MOVQ    x9, PUB_BLOB_SIDECAR + 24
    add     x26, x26, x9
    add     x27, x27, #1
    b       3b
7:  MOVQ    x9, PUB_BLOB_SIDECAR + 24
    mul     x9, x25, x9
    str     x9, [x22, #16]
.endif
    str     x28, [x21]
    mov     x0, #LANTERN_OK
    LEAVE 400
8:  str     x28, [x21]
    mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 400
9:  str     x28, [x21]
    mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 400
SPEC_END node_publish_sidecars
.endif
