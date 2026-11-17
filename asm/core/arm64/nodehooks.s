/*
 * The node's work on one fork, ARM64: decode SSZ bytes with the fork's types, then call the
 * fork's fork choice functions. lantern_node_run (node.s, in the common object) calls these
 * exports for the fork of the block or message. Requirements: docs/reference/node.md.
 */

/* The node reads the slot of a state of any fork at NODE_STATE_SLOT. */
.if BeaconState_slot - NODE_STATE_SLOT
.error "BeaconState_slot is not NODE_STATE_SLOT"
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

/* (data, scratch, root, result): hash_tree_root of the message of the SignedBeaconBlock in data. */
SPEC_FUNCTION node_block_root
    ENTER 0
    mov     x20, x0
    mov     x21, x1
    mov     x22, x2
    mov     x23, x3
    ldr     x28, [x21]                      /* the scratch size, restored on return */
    str     xzr, [x23]
    ADDRESS x0, lantern_type_SignedBeaconBlock
    mov     x1, x20
    mov     x2, x21
    bl      node_decode
    cmp     x0, #1
    b.eq    8f
    b.hi    9f
    mov     x24, x1
    PART    x1, x9, x24, SignedBeaconBlock_message
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
