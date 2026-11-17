/*
 * The node's work on one fork, RISC-V: decode SSZ bytes with the fork's types, then call the
 * fork's fork choice functions. lantern_node_run (node.s, in the common object) calls these
 * exports for the fork of the block or message. Requirements: docs/reference/node.md.
 */

/* The node reads the slot of a state of any fork at NODE_STATE_SLOT. */
.if BeaconState_slot - NODE_STATE_SLOT
.error "BeaconState_slot is not NODE_STATE_SLOT"
.endif

/*
 * Decode the ByteList a1 as the type a0 into the end of the scratch a2, whose size field then
 * shrinks by the value's room: a0 = 0, 1 (scratch too small) or 2 (not an encoding of the
 * type); a1 = the value. The caller restores the size field. s1 type, s2 bytes, s3 scratch,
 * s4 the value's room, s5 the value. Locals: L the size.
 */
LOCAL_FUNCTION node_decode
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    addi    a3, sp, L
    CALL_GLOBAL ssz_deserialize_size
    beqz    a0, 1f
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    j       9f
1:  ld      t0, L(sp)                       # the value at the end of scratch
    addi    s4, t0, 7
    andi    s4, s4, -8
    ld      s5, 0(s3)
    addi    t1, s4, 8
    bltu    s5, t1, 8f
    sub     s5, s5, s4
    sd      s5, 0(s3)
    add     s5, s3, s5
    sd      t0, 0(s5)
    mv      a0, s1
    mv      a1, s2
    mv      a2, s3
    mv      a3, s5
    CALL_GLOBAL ssz_deserialize
    beqz    a0, 2f
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    j       9f
2:  mv      a1, s5
    li      a0, 0
    LEAVE 16
8:  li      a0, 1
    LEAVE 16
9:  li      a0, 2
    LEAVE 16
END_FUNCTION node_decode

.if FORK == FORK_BELLATRIX
/* a0 = the PowBlock of the node a0 whose block_hash is the 32 bytes at a1, or 0. Uses t0-t2, a6, a7. */
LOCAL_FUNCTION node_pow_block
    UNWIND_END_PROLOGUE
    PART    t0, t1, a0, Node_pow_blocks
1:  beqz    t1, 3f
    addi    t2, t0, PowBlock_block_hash
    NE32    t2, a1, 2f
    mv      a0, t0
    ret
2:  addi    t0, t0, POW_BLOCK_BYTES
    addi    t1, t1, -1
    j       1b
3:  li      a0, 0
    ret
END_FUNCTION node_pow_block
.endif

/*
 * (store, node, data, state, options, scratch, result): on_block of the SignedBeaconBlock in
 * data. Bellatrix: the pow_block and pow_parent of options from the PowBlocks of the node.
 * s1 store, s2 data then the block, s3 state, s4 options, s5 scratch, s6 result, s7 node,
 * s10 the scratch size, restored on return.
 */
SPEC_FUNCTION node_import
    ENTER 0
    mv      s1, a0
    mv      s7, a1
    mv      s2, a2
    mv      s3, a3
    mv      s4, a4
    mv      s5, a5
    mv      s6, a6
    ld      s10, 0(s5)
    sd      zero, 0(s6)
    ADDRESS a0, lantern_type_SignedBeaconBlock
    mv      a1, s2
    mv      a2, s5
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 9f
    mv      s2, a1
.if FORK == FORK_BELLATRIX
    PART    t0, t1, s2, SignedBeaconBlock_message      # get_pow_block(payload.parent_hash) and its parent
    PART    t2, t1, t0, BeaconBlock_body
    PART    t0, t1, t2, BeaconBlockBody_execution_payload
    mv      a0, s7
    ADDQ    a1, t0, ExecutionPayload_parent_hash
    call    node_pow_block
    sd      a0, BlockOptions_pow_block(s4)
    beqz    a0, 1f
    addi    a1, a0, PowBlock_parent_hash
    mv      a0, s7
    call    node_pow_block
1:  sd      a0, BlockOptions_pow_parent(s4)
.endif
    mv      a0, s1
    mv      a1, s2
    mv      a2, s3
    mv      a3, s4
    mv      a4, s5
    mv      a5, s6
    call    lantern_on_block
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    j       99f
9:  li      t0, LANTERN_INVALID_ENCODING
    sd      t0, 0(s6)
    li      a0, LANTERN_OK
99: sd      s10, 0(s5)
    LEAVE 0
SPEC_END node_import

/*
 * (data, scratch, root, result): hash_tree_root of the message of the SignedBeaconBlock in data.
 * s2 data, s3 scratch, s4 root, s5 result, s10 the scratch size, restored on return.
 */
SPEC_FUNCTION node_block_root
    ENTER 0
    mv      s2, a0
    mv      s3, a1
    mv      s4, a2
    mv      s5, a3
    ld      s10, 0(s3)
    sd      zero, 0(s5)
    ADDRESS a0, lantern_type_SignedBeaconBlock
    mv      a1, s2
    mv      a2, s3
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 9f
    PART    t0, t1, a1, SignedBeaconBlock_message
    mv      a1, t0
    ADDRESS a0, lantern_type_BeaconBlock
    mv      a2, s3
    mv      a3, s4
    CALL_GLOBAL ssz_hash_tree_root
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    j       99f
9:  li      t0, LANTERN_INVALID_ENCODING
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
99: sd      s10, 0(s3)
    LEAVE 0
SPEC_END node_block_root

/*
 * (store, data, is_from_block, state, scratch, result, target): validate_on_attestation of the
 * Attestation in data; with no target checkpoint state (state 0) the result is
 * LANTERN_NEED_TARGET_STATE and target holds the target checkpoint, else on_attestation.
 * s1 store, s2 data, s3 is_from_block, s4 state, s5 scratch, s6 result, s7 target, s8 the
 * attestation, s10 the scratch size, restored on return.
 */
SPEC_FUNCTION node_attestation
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    mv      s7, a6
    ld      s10, 0(s5)
    sd      zero, 0(s6)
    ADDRESS a0, lantern_type_Attestation
    mv      a1, s2
    mv      a2, s5
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 9f
    mv      s8, a1
    mv      a0, s1
    mv      a2, s3
    call    lantern_validate_on_attestation
    beqz    a0, 1f
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    sd      a0, 0(s6)                       # a failed check
    li      a0, LANTERN_OK
    j       99f
1:  bnez    s4, 2f
    ADDQ    t0, s8, Attestation_data + AttestationData_target
    ld      t1, Checkpoint_epoch(t0)
    sd      t1, 0(s7)
    addi    t0, t0, Checkpoint_root
    addi    t1, s7, 8
    COPY32  t1, t0
    li      t0, LANTERN_NEED_TARGET_STATE
    sd      t0, 0(s6)
    li      a0, LANTERN_OK
    j       99f
2:  mv      a0, s1
    mv      a1, s8
    mv      a2, s3
    mv      a3, s4
    mv      a4, s5
    mv      a5, s6
    call    lantern_on_attestation
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    j       99f
9:  li      t0, LANTERN_INVALID_ENCODING
    sd      t0, 0(s6)
    li      a0, LANTERN_OK
99: sd      s10, 0(s5)
    LEAVE 0
SPEC_END node_attestation

/*
 * (store, data, state, scratch, result): on_attester_slashing of the AttesterSlashing in data.
 * s1 store, s2 data, s3 state, s4 scratch, s5 result, s10 the scratch size, restored on return.
 */
SPEC_FUNCTION node_attester_slashing
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      s10, 0(s4)
    sd      zero, 0(s5)
    ADDRESS a0, lantern_type_AttesterSlashing
    mv      a1, s2
    mv      a2, s4
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 9f
    mv      a0, s1
    mv      a2, s3
    mv      a3, s4
    mv      a4, s5
    call    lantern_on_attester_slashing
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    j       99f
9:  li      t0, LANTERN_INVALID_ENCODING
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
99: sd      s10, 0(s4)
    LEAVE 0
SPEC_END node_attester_slashing
