/*
 * The node's work on one fork, RISC-V: decode SSZ bytes with the fork's types, then call the
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
 * (data, scratch, root, result, blobs): hash_tree_root of the message of the SignedBeaconBlock in
 * data, and the length of its body's blob_kzg_commitments (0 before deneb). s2 data, s3 scratch,
 * s4 root, s5 result, s6 blobs, s10 the scratch size, restored on return.
 */
SPEC_FUNCTION node_block_root
    ENTER 0
    mv      s2, a0
    mv      s3, a1
    mv      s4, a2
    mv      s5, a3
    mv      s6, a4
    ld      s10, 0(s3)
    sd      zero, 0(s5)
    sd      zero, 0(s6)
    ADDRESS a0, lantern_type_SignedBeaconBlock
    mv      a1, s2
    mv      a2, s3
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 9f
    PART    t0, t1, a1, SignedBeaconBlock_message
.if FORK >= FORK_DENEB
    PART    t2, t3, t0, BeaconBlock_body
    LDQ     t3, t2, BeaconBlockBody_blob_kzg_commitments + 8
    sd      t3, 0(s6)
.endif
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
 * (data, scratch, root) -> status: hash_tree_root of the AttestationData at data, its 128 SSZ
 * bytes, into root, from a copy on the stack, 8-aligned. scratch for ssz_hash_tree_root.
 * Locals: scratch, root, the copy.
 */
SPEC_FUNCTION node_data_root
    FRAME 144
    sd      a1, 0(sp)
    sd      a2, 8(sp)
    mv      a1, a0
    addi    a0, sp, 16
    li      a2, 128
    call    lantern_copy
    ADDRESS a0, lantern_type_AttestationData
    addi    a1, sp, 16
    ld      a2, 0(sp)
    ld      a3, 8(sp)
    CALL_GLOBAL ssz_hash_tree_root
    li      t0, SSZ_BUFFER_TOO_SMALL
    bne     a0, t0, 1f
    li      a0, LANTERN_BUFFER_TOO_SMALL
1:  UNFRAME 144
SPEC_END node_data_root
.if AttestationData__mem != 128 || AttestationData__ssz != 128
.error "node_data_root: an AttestationData value is its 128 SSZ bytes"
.endif

/*
 * (data, scratch, out): the SignedBeaconBlockHeader of the SignedBeaconBlock in data: the message's
 * slot, proposer_index, parent_root, state_root, hash_tree_root of its body, and the signature.
 * s2 data, s3 scratch, s4 out, s5 the block, s6 its message, s10 the scratch size, restored.
 */
SPEC_FUNCTION node_block_header
    ENTER 0
    mv      s2, a0
    mv      s3, a1
    mv      s4, a2
    ld      s10, 0(s3)
    ADDRESS a0, lantern_type_SignedBeaconBlock
    mv      a1, s2
    mv      a2, s3
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 9f
    mv      s5, a1
    PART    s6, t1, s5, SignedBeaconBlock_message
    LDQ     t0, s6, BeaconBlock_slot
    sd      t0, 0(s4)
    LDQ     t0, s6, BeaconBlock_proposer_index
    sd      t0, 8(s4)
    addi    a0, s4, 16
    ADDQ    a1, s6, BeaconBlock_parent_root
    li      a2, 32
    call    lantern_copy
    addi    a0, s4, 48
    ADDQ    a1, s6, BeaconBlock_state_root
    li      a2, 32
    call    lantern_copy
    addi    a0, s4, 112
    ADDQ    a1, s5, SignedBeaconBlock_signature
    li      a2, 96
    call    lantern_copy
    PART    a1, t1, s6, BeaconBlock_body    # body_root
    ADDRESS a0, lantern_type_BeaconBlockBody
    mv      a2, s3
    addi    a3, s4, 80
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 8f
    li      a0, LANTERN_OK
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    j       99f
9:  li      a0, LANTERN_INVALID_ENCODING
99: sd      s10, 0(s3)
    LEAVE 0
SPEC_END node_block_header

/* (state, out): the previous_justified, current_justified and finalized checkpoints of the state. */
SPEC_FUNCTION node_state_checkpoints
    FRAME 0
    mv      t0, a0
    mv      a0, a1
    ADDQ    a1, t0, BeaconState_previous_justified_checkpoint
    li      a2, 3 * 40
    call    lantern_copy
    li      a0, LANTERN_OK
    UNFRAME 0
SPEC_END node_state_checkpoints

/*
 * (state, config, scratch, out): lantern_node_proposers (node.md): the dependent root of the epoch
 * of the state's slot, then its proposers. s1 state, s2 config, s3 scratch, s4 out, s5 the scratch
 * size, restored. Locals: L the epoch, L+8 the slot - 1, L+16 the latest_block_header (112).
 */
SPEC_FUNCTION node_proposers
    ENTER 128
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      s5, 0(s3)
    LDQ     t0, s1, BeaconState_slot
    li      a0, LANTERN_INVALID_SLOT
    andi    t1, t0, SLOTS_PER_EPOCH - 1
    bnez    t1, 99f
    NEED_SCRATCH s3, s1, 2, 8f
    LDQ     t0, s1, BeaconState_slot
    srli    t1, t0, LOG2_SLOTS_PER_EPOCH
    sd      t1, L(sp)
    beqz    t0, 2f
    addi    t0, t0, -1                      # get_block_root_at_slot(state, slot - 1)
    sd      t0, (L + 8)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 8)
    mv      a2, s4
    call    lantern_get_block_root_at_slot
    bnez    a0, 99f
    j       3f
2:  addi    a0, sp, (L + 16)                # slot 0: hash_tree_root of the latest_block_header, its state_root the state's when zero
    ADDQ    a1, s1, BeaconState_latest_block_header
    li      a2, BeaconBlockHeader__mem
    call    lantern_copy
    ld      t0, (L + 16 + BeaconBlockHeader_state_root)(sp)
    ld      t1, (L + 16 + BeaconBlockHeader_state_root + 8)(sp)
    or      t0, t0, t1
    ld      t1, (L + 16 + BeaconBlockHeader_state_root + 16)(sp)
    or      t0, t0, t1
    ld      t1, (L + 16 + BeaconBlockHeader_state_root + 24)(sp)
    or      t0, t0, t1
    bnez    t0, 21f
    mv      a0, s1
    LDQ     a1, s2, CONFIG_STATE_CACHE
    mv      a2, s3
    addi    a3, sp, (L + 16 + BeaconBlockHeader_state_root)
    call    lantern_state_root
    bnez    a0, 99f
21: ADDRESS a0, lantern_type_BeaconBlockHeader
    addi    a1, sp, (L + 16)
    mv      a2, s3
    mv      a3, s4
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 8f
3:
.if FORK >= FORK_FULU
    addi    a0, s4, 32                      # the proposers: the first SLOTS_PER_EPOCH of proposer_lookahead
    ADDQ    a1, s1, BeaconState_proposer_lookahead
    li      a2, 8 * SLOTS_PER_EPOCH
    call    lantern_copy
    LDQ     t2, s1, BeaconState_validators + 8  # each names a validator
    li      t0, 0
    li      a0, LANTERN_INVALID_VALIDATOR_INDEX
4:  slli    t1, t0, 3
    add     t1, t1, s4
    ld      t1, 32(t1)
    bgeu    t1, t2, 99f
    addi    t0, t0, 1
    li      t1, SLOTS_PER_EPOCH
    bltu    t0, t1, 4b
    li      a0, LANTERN_OK
.else
    mv      a0, s1                          # the proposers: get_beacon_proposer_indices of the epoch
    addi    a1, sp, L
    mv      a2, s3
    addi    a3, s4, 32
    call    lantern_get_beacon_proposer_indices
.endif
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
99: sd      s5, 0(s3)
    LEAVE 128
SPEC_END node_proposers

/*
 * (state, config, scratch, out): lantern_node_event_roots (node.md): the block root, the state root,
 * and the previous and current duty dependent roots of a block's post-state. s1 state, s2 config,
 * s3 scratch, s4 out, s5 the scratch size, restored, s6 which dependent root, s7 its place.
 * Locals: L a slot, L+8 the latest_block_header (112).
 */
SPEC_FUNCTION node_event_roots
    ENTER 128
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      s5, 0(s3)
    NEED_SCRATCH s3, s1, 2, 8f
    # the header, its state_root the state's when zero
    addi    a0, sp, (L + 8)
    ADDQ    a1, s1, BeaconState_latest_block_header
    li      a2, BeaconBlockHeader__mem
    call    lantern_copy
    ld      t0, (L + 8 + BeaconBlockHeader_state_root)(sp)
    ld      t1, (L + 8 + BeaconBlockHeader_state_root + 8)(sp)
    or      t0, t0, t1
    ld      t1, (L + 8 + BeaconBlockHeader_state_root + 16)(sp)
    or      t0, t0, t1
    ld      t1, (L + 8 + BeaconBlockHeader_state_root + 24)(sp)
    or      t0, t0, t1
    bnez    t0, 1f
    mv      a0, s1
    LDQ     a1, s2, CONFIG_STATE_CACHE
    mv      a2, s3
    addi    a3, sp, (L + 8 + BeaconBlockHeader_state_root)
    call    lantern_state_root
    bnez    a0, 99f
1:  addi    t0, s4, 32
    addi    t1, sp, (L + 8 + BeaconBlockHeader_state_root)
    COPY32  t0, t1
    # the block root
    ADDRESS a0, lantern_type_BeaconBlockHeader
    addi    a1, sp, (L + 8)
    mv      a2, s3
    mv      a3, s4
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 8f
    li      s6, 0
    # each dependent root: of the epoch before the state's (0), then of its epoch (1)
2:  LDQ     t0, s1, BeaconState_slot
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    add     t0, t0, s6
    slli    t1, s6, 5
    add     s7, s4, t1
    addi    s7, s7, 64
    li      t1, 2
    bltu    t0, t1, 3f
    addi    t0, t0, -1
    slli    t0, t0, LOG2_SLOTS_PER_EPOCH
    addi    t0, t0, -1
    sd      t0, L(sp)
    j       31f
    # on underflow, the genesis block root
3:  LDQ     t0, s1, BeaconState_slot
    beqz    t0, 32f
    sd      zero, L(sp)
31: mv      a0, s1
    addi    a1, sp, L
    mv      a2, s7
    call    lantern_get_block_root_at_slot
    bnez    a0, 99f
    j       4f
32: COPY32  s7, s4
4:  addi    s6, s6, 1
    li      t0, 2
    bltu    s6, t0, 2b
    li      a0, LANTERN_OK
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
99: sd      s5, 0(s3)
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
 * (state, config, index, scratch, out) -> a0: the AttestationData of the state's slot, its 128 SSZ
 * bytes in out (node.md, lantern_node_attestation_data). s1 the state, s2 the index, s3 out.
 * Locals: L lantern_node_event_roots's out (128).
 */
SPEC_FUNCTION node_attestation_data
    ENTER 128
    mv      s1, a0
    mv      s2, a2
    mv      s3, a4
    mv      a2, a3
    addi    a3, sp, L
    call    lantern_node_event_roots
    bnez    a0, 9f
    LDQ     t0, s1, BeaconState_slot        # slot, index
    sd      t0, 0(s3)
.if FORK >= FORK_ELECTRA
    li      s2, 0
.endif
    sd      s2, 8(s3)
    addi    a0, s3, 16                      # beacon_block_root
    addi    a1, sp, L
    li      a2, 32
    call    lantern_copy
    addi    a0, s3, 48                      # source: current_justified_checkpoint
    ADDQ    a1, s1, BeaconState_current_justified_checkpoint
    li      a2, 40
    call    lantern_copy
    LDQ     t0, s1, BeaconState_slot        # target: the epoch, and its boundary block's root
    srli    t1, t0, LOG2_SLOTS_PER_EPOCH
    sd      t1, 88(s3)
    slli    t1, t1, LOG2_SLOTS_PER_EPOCH
    addi    a1, sp, L
    beq     t1, t0, 1f
    li      t2, SLOTS_PER_HISTORICAL_ROOT - 1
    and     t1, t1, t2
    slli    t1, t1, 5
    ADDQ    a1, s1, BeaconState_block_roots
    add     a1, a1, t1
1:  addi    a0, s3, 96
    li      a2, 32
    call    lantern_copy
    li      a0, LANTERN_OK
9:  LEAVE 128
SPEC_END node_attestation_data

/*
 * (state, config, ids, scratch, out) -> a0: the committee assignments of the ids in the epoch of
 * the state at its first slot (node.md, lantern_node_attester_duties). s1 the state, s2 the config,
 * s3 the items, s4 scratch, s5 out, s6 the items' count, s7 a bit for each validator an item names
 * and s8 a committee's list, both at the end of scratch, s9 a member's place. Locals: L the epoch,
 * L+8 the committees at a slot, L+16 the validators, L+24 the scratch's size, L+32 a slot, L+40 a
 * committee index, L+64 lantern_node_event_roots's out (128).
 */
SPEC_FUNCTION node_attester_duties
    ENTER 192
    mv      s1, a0
    mv      s2, a1
    ld      t0, 8(a2)
    add     s3, a2, t0
    ld      s6, 16(a2)
    srli    s6, s6, 6
    mv      s4, a3
    mv      s5, a4
    LDQ     t0, s1, BeaconState_slot        # the first slot of an epoch
    andi    t1, t0, SLOTS_PER_EPOCH - 1
    bnez    t1, 95f
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    sd      t0, (L + 0)(sp)
    ld      t0, 0(s4)
    sd      t0, (L + 24)(sp)
    mv      a0, s1                          # the dependent root: the previous duty dependent root
    mv      a1, s2
    mv      a2, s4
    addi    a3, sp, L + 64
    call    lantern_node_event_roots
    bnez    a0, 99f
    mv      a0, s5
    addi    a1, sp, L + 128
    li      a2, 32
    call    lantern_copy
    mv      a0, s1                          # the committees at a slot
    addi    a1, sp, L + 0
    LDQ     a2, s2, CONFIG_COMMITTEE_CACHE
    mv      a3, s4
    addi    a4, sp, L + 8
    call    lantern_get_committee_count_per_slot
    bnez    a0, 99f
    ld      t0, (L + 8)(sp)
    sd      t0, 32(s5)
    addi    a0, s5, 40                      # no assignment yet
    li      t0, 48
    mul     a1, s6, t0
    call    lantern_zero
    LDQ     t0, s1, BeaconState_validators + 8  # the bits and a committee's list at the end of scratch, S(2) before them
    sd      t0, (L + 16)(sp)
    addi    t1, t0, 63
    srli    t1, t1, 6
    slli    t1, t1, 3
    ld      t2, (L + 8)(sp)
    li      t3, SLOTS_PER_EPOCH
    mul     t2, t2, t3
    divu    t2, t0, t2
    addi    t2, t2, 1
    slli    t2, t2, 3
    addi    t2, t2, LIST_FIXED
    add     t3, t1, t2
    slli    t4, t0, 3
    addi    t4, t4, LIST_FIXED
    slli    t4, t4, 1
    li      t5, LANTERN_SCRATCH_FIXED
    add     t4, t4, t5
    add     t4, t4, t3
    ld      t5, 0(s4)
    bltu    t5, t4, 97f
    sub     t5, t5, t3
    sd      t5, 0(s4)
    add     s7, s4, t5
    add     s8, s7, t1
    sd      t2, 0(s8)
    li      t4, LIST_FIXED
    sd      t4, LIST_OFFSET(s8)
    sd      zero, LIST_COUNT(s8)
    mv      a0, s7
    mv      a1, t1
    call    lantern_zero
    li      t0, 0                           # a bit for each item's index
1:  bgeu    t0, s6, 2f
    slli    t1, t0, 6
    add     t1, s3, t1
    ld      t1, 8(t1)
    ld      t2, (L + 16)(sp)
    bgeu    t1, t2, 11f
    srli    t2, t1, 6
    slli    t2, t2, 3
    add     t2, s7, t2
    ld      t3, 0(t2)
    li      t4, 1
    sll     t4, t4, t1
    or      t3, t3, t4
    sd      t3, 0(t2)
11: addi    t0, t0, 1
    j       1b
2:  ld      t0, (L + 0)(sp)                 # each committee of each slot of the epoch
    slli    t0, t0, LOG2_SLOTS_PER_EPOCH
    sd      t0, (L + 32)(sp)
3:  sd      zero, (L + 40)(sp)
4:  mv      a0, s1
    addi    a1, sp, L + 32
    addi    a2, sp, L + 40
    LDQ     a3, s2, CONFIG_COMMITTEE_CACHE
    mv      a4, s4
    mv      a5, s8
    call    lantern_get_beacon_committee
    bnez    a0, 98f
    li      s9, 0
5:  ld      t0, LIST_COUNT(s8)
    bgeu    s9, t0, 7f
    slli    t1, s9, 3
    add     t1, s8, t1
    ld      t1, LIST_FIXED(t1)              # a member an item names: each such item's assignment
    srli    t2, t1, 6
    slli    t2, t2, 3
    add     t2, s7, t2
    ld      t2, 0(t2)
    srl     t2, t2, t1
    andi    t2, t2, 1
    beqz    t2, 6f
    li      t3, 0
51: bgeu    t3, s6, 6f
    slli    t4, t3, 6
    add     t4, s3, t4
    ld      t4, 8(t4)
    bne     t4, t1, 52f
    li      t4, 48
    mul     t4, t3, t4
    add     t4, s5, t4
    addi    t4, t4, 40
    li      t5, 1
    sd      t5, 0(t4)
    ld      t5, (L + 32)(sp)
    sd      t5, 8(t4)
    ld      t5, (L + 40)(sp)
    sd      t5, 16(t4)
    sd      t0, 24(t4)
    sd      s9, 32(t4)
    sd      t1, 40(t4)
52: addi    t3, t3, 1
    j       51b
6:  addi    s9, s9, 1
    j       5b
7:  ld      t0, (L + 40)(sp)                # the next committee, then the next slot
    addi    t0, t0, 1
    sd      t0, (L + 40)(sp)
    ld      t1, (L + 8)(sp)
    bltu    t0, t1, 4b
    ld      t0, (L + 32)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 32)(sp)
    andi    t1, t0, SLOTS_PER_EPOCH - 1
    bnez    t1, 3b
    li      a0, LANTERN_OK
98: ld      t0, (L + 24)(sp)
    sd      t0, 0(s4)
99: LEAVE 192
95: li      a0, LANTERN_INVALID_SLOT
    LEAVE 192
97: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 192
SPEC_END node_attester_duties

/*
 * (state, out) -> a0: the block number and hash of the state's latest_execution_payload_header
 * (node.md, lantern_node_payload_parent).
 */
SPEC_FUNCTION node_payload_parent
    ENTER 0
.if FORK < FORK_BELLATRIX
    li      a0, LANTERN_INVALID_EVENT
.else
    mv      s1, a1
    li      t0, BeaconState_latest_execution_payload_header    # the header value in its part
    add     t0, a0, t0
    ld      t0, 0(t0)
    add     s2, a0, t0
    li      t0, ExecutionPayloadHeader_block_number
    add     t0, s2, t0
    ld      t1, 0(t0)
    sd      t1, 0(s1)
    li      t0, ExecutionPayloadHeader_block_hash
    add     a1, s2, t0
    addi    a0, s1, 8
    li      a2, 32
    call    lantern_copy
    li      a0, LANTERN_OK
.endif
    LEAVE 0
SPEC_END node_payload_parent

/*
 * (ssz, scratch, out) -> a0: the block root of a sidecar's SSZ bytes, hash_tree_root of its
 * signed_block_header.message (node.md, lantern_node_sidecar_root). s1 the bytes, s2 their count.
 */
SPEC_FUNCTION node_sidecar_root
    ENTER 112
.if FORK < FORK_DENEB
    li      a0, LANTERN_INVALID_EVENT
    LEAVE 112
.else
    ld      t0, 8(a0)
    add     s1, a0, t0
    ld      s2, 16(a0)
    mv      s3, a1
    mv      s4, a2
.if FORK < FORK_FULU
    li      t0, PUB_BLOB_SIDECAR            # a BlobSidecar: its fixed size; the header after the index, blob, commitment and proof
    bne     s2, t0, 8f
    li      t0, 8 + PUB_BLOB_BYTES + 96
    add     a1, s1, t0
.else
    li      t0, PUB_COLUMN_FIXED            # a DataColumnSidecar: the header after the index and three offsets
    bltu    s2, t0, 8f
    addi    a1, s1, 20
.endif
    mv      a0, sp                          # the header at an aligned place: SSZ bytes have no alignment
    li      a2, BeaconBlockHeader__mem
    call    lantern_copy
    ADDRESS a0, lantern_type_BeaconBlockHeader
    mv      a1, sp
    mv      a2, s3
    mv      a3, s4
    CALL_GLOBAL ssz_hash_tree_root
    LEAVE 112
8:  li      a0, LANTERN_INVALID_ENCODING
    LEAVE 112
.endif
SPEC_END node_sidecar_root

/* Set the byte of each index of a phase0 epoch list of PendingAttestation values: of the part at ref of the state. */
.macro LIVE_PENDING ref
    li      t0, \ref
    add     t0, s1, t0
    ld      t1, 0(t0)                       # the part's offset and count
    ld      t2, 8(t0)
    sd      t1, (L + 16)(sp)
    sd      t2, (L + 24)(sp)
71: ld      t1, (L + 16)(sp)
    ld      t2, (L + 24)(sp)
    beqz    t2, 74f
    add     t0, s1, t1
    ld      t3, 0(t0)                       # the next value starts after this one's size
    add     t3, t1, t3
    sd      t3, (L + 16)(sp)
    addi    t2, t2, -1
    sd      t2, (L + 24)(sp)
    SCRATCH_GIVE s4, s10, 2, s9             # the bytes and the indices at the end, S(4) before them
    mv      a0, s1
    add     a1, s1, t1
    ld      a2, (L + 32)(sp)
    mv      a3, s4
    SCRATCH_LIST a4, s4, s10, 1, s9
    call    lantern_get_attesting_indices
    sd      s10, 0(s4)
    bnez    a0, 99f
    SCRATCH_LIST t0, s4, s10, 1, s9
    ld      t1, LIST_COUNT(t0)
    addi    t0, t0, LIST_FIXED
    li      t6, 1
72: beqz    t1, 71b
    ld      t2, 0(t0)
    add     t2, s8, t2
    sb      t6, 0(t2)
    addi    t0, t0, 8
    addi    t1, t1, -1
    j       72b
74:
.endm

/* Set the byte of each validator whose participation flags, of the part at ref of the state, are not 0. */
.macro LIVE_FLAGS ref
    PART    t2, t3, s1, \ref
    bleu    t3, s9, 70f
    mv      t3, s9
70: li      t0, 0
    li      t6, 1
75: bgeu    t0, t3, 77f
    add     t1, t2, t0
    lbu     t1, 0(t1)
    beqz    t1, 76f
    add     t1, s8, t0
    sb      t6, 0(t1)
76: addi    t0, t0, 1
    j       75b
77:
.endm

/*
 * (state, config, seen, ids, epoch, scratch, out) -> a0: whether the validator of each item was
 * seen live in the epoch (node.md, lantern_node_liveness). s1 the state, s2 the seen, s3 the items,
 * s4 scratch, s5 out, s6 the items' count, s7 the epoch, s8 a byte for each validator (list 0 of
 * scratch), s9 the validator count, s10 the scratch's size. Locals: L the previous epoch, L+8 the
 * current epoch, L+16 the next value and the count left of an epoch list, L+32 the CommitteeCache.
 */
SPEC_FUNCTION node_liveness
    ENTER 48
    mv      s5, a6                          # out first: the macros below use a6 and a7
    mv      s1, a0
    LDQ     t0, a1, CONFIG_COMMITTEE_CACHE
    sd      t0, (L + 32)(sp)
    mv      s2, a2
    ld      t0, 8(a3)
    add     s3, a3, t0
    ld      s6, 16(a3)
    srli    s6, s6, 6
    mv      s7, a4
    mv      s4, a5
.if FORK == FORK_PHASE0
    NEED_SCRATCH s4, s1, 6, 98f
.else
    NEED_SCRATCH s4, s1, 1, 98f
.endif
    LDQ     s9, s1, BeaconState_validators + 8
    ld      s10, 0(s4)
    SCRATCH_LIST s8, s4, s10, 0, s9
    addi    s8, s8, LIST_FIXED              # a byte for each validator, 0
    mv      a0, s8
    mv      a1, s9
    call    lantern_zero
    mv      a0, s1
    addi    a1, sp, L + 0
    call    lantern_get_previous_epoch
    mv      a0, s1
    addi    a1, sp, L + 8
    call    lantern_get_current_epoch
    ld      t0, (L + 8)(sp)                 # in the beacon chain: the current epoch's list
    bne     s7, t0, 1f
.if FORK == FORK_PHASE0
    LIVE_PENDING BeaconState_current_epoch_attestations
.else
    LIVE_FLAGS BeaconState_current_epoch_participation
.endif
1:  ld      t0, (L + 0)(sp)                 # the previous epoch's list
    bne     s7, t0, 2f
.if FORK == FORK_PHASE0
    LIVE_PENDING BeaconState_previous_epoch_attestations
.else
    LIVE_FLAGS BeaconState_previous_epoch_participation
.endif
2:  PART    t2, t3, s2, Seen_keys           # on the network and from the API: the Seen's keys
    li      t6, 1
3:  beqz    t3, 6f
    ld      t0, 0(t2)                       # kind, a, b: the index
    ld      t1, 8(t2)
    ld      t4, 16(t2)
    addi    t2, t2, SeenKey__mem
    addi    t3, t3, -1
    bgeu    t4, s9, 3b
    li      t5, SEEN_ATTESTATION            # an epoch's keys
    beq     t0, t5, 4f
    li      t5, SEEN_AGGREGATOR_EPOCH
    beq     t0, t5, 4f
    li      t5, SEEN_PROPOSER_SLOT          # a slot's keys
    beq     t0, t5, 31f
    li      t5, SEEN_SYNC_MESSAGE
    beq     t0, t5, 31f
    li      t5, SEEN_SYNC_CONTRIBUTION
    bne     t0, t5, 3b
31: srli    t1, t1, LOG2_SLOTS_PER_EPOCH
4:  bne     t1, s7, 3b
    add     t5, s8, t4
    sb      t6, 0(t5)
    j       3b
6:  li      t0, 0                           # each item: the byte of its index
7:  bgeu    t0, s6, 8f
    slli    t1, t0, 6
    add     t1, s3, t1
    ld      t1, 8(t1)
    li      t2, 0
    bgeu    t1, s9, 79f
    add     t1, s8, t1
    lbu     t2, 0(t1)
79: add     t1, s5, t0
    sb      t2, 0(t1)
    addi    t0, t0, 1
    j       7b
8:  li      a0, LANTERN_OK
99: sd      s10, 0(s4)
    LEAVE 48
98: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END node_liveness

/* ---------------------------------------------------------------- Rewards (beacon-api.md, getBlockRewards) */

.if FORK >= FORK_ALTAIR
/*
 * (state a0, scratch a1) -> a0 status, a1 participant_reward, a2 proposer_reward of
 * process_sync_aggregate at the state (altair beacon-chain.md). Locals: 0 the total active
 * balance, 8 the base reward per increment, 16 the state, 24 the scratch.
 */
LOCAL_FUNCTION node_sync_values
    FRAME 32
    sd      a0, 16(sp)
    sd      a1, 24(sp)
    mv      a2, sp
    call    lantern_get_total_active_balance
    bnez    a0, 9f
    ld      a0, 16(sp)
    ld      a1, 24(sp)
    addi    a2, sp, 8
    call    lantern_get_base_reward_per_increment
    bnez    a0, 9f
    ld      t0, 0(sp)
    li      t1, EFFECTIVE_BALANCE_INCREMENT
    divu    t0, t0, t1                      # total_active_increments
    ld      t1, 8(sp)
    mul     t0, t0, t1                      # total_base_rewards
    li      t1, SYNC_REWARD_WEIGHT
    mul     t0, t0, t1
    srli    t0, t0, 6                       # // WEIGHT_DENOMINATOR
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH    # max_participant_rewards
    li      t1, SYNC_COMMITTEE_SIZE
    divu    a1, t0, t1                      # participant_reward
    li      t1, PROPOSER_WEIGHT
    mul     a2, a1, t1
    li      t1, WEIGHT_DENOMINATOR - PROPOSER_WEIGHT
    divu    a2, a2, t1                      # proposer_reward
    li      a0, LANTERN_OK
9:  UNFRAME 32
END_FUNCTION node_sync_values
.endif

.if FORK == FORK_PHASE0
.if BASE_REWARDS_PER_EPOCH != 4 || PROPOSER_REWARD_QUOTIENT != 8
.error "lantern_node_block_rewards divides by BASE_REWARDS_PER_EPOCH and PROPOSER_REWARD_QUOTIENT with shifts"
.endif
/*
 * Of the E st (k 1: early, its delays at s8 + 2n; k 2: late, at s8 + 3n): the square root of its
 * total active balance at root, and for each attestation of its previous_epoch_attestations each
 * attesting index below n takes the attestation's inclusion_delay when that is lower.
 */
.macro REWARD_LOWEST st, k, root
    beqz    \st, 39f
    SCRATCH_GIVE s4, s10, 2, s9
    mv      a0, \st
    mv      a1, s4
    addi    a2, sp, 120
    call    lantern_get_total_active_balance
    sd      s10, 0(s4)
    bnez    a0, 99f
    addi    a0, sp, 120
    addi    a1, sp, \root
    call    lantern_integer_squareroot
    li      t0, BeaconState_previous_epoch_attestations
    add     t0, \st, t0
    ld      t1, 0(t0)                       # the part's offset and count
    ld      t2, 8(t0)
    sd      t1, 16(sp)
    sd      t2, 24(sp)
32: ld      t1, 16(sp)
    ld      t2, 24(sp)
    beqz    t2, 39f
    add     t3, \st, t1
    ld      t0, 0(t3)                       # the next value starts after this one's size
    add     t0, t1, t0
    sd      t0, 16(sp)
    addi    t2, t2, -1
    sd      t2, 24(sp)
    sd      t3, 128(sp)
    SCRATCH_GIVE s4, s10, 2, s9
    mv      a0, \st
    mv      a1, t3
    ld      a2, 96(sp)
    mv      a3, s4
    SCRATCH_LIST a4, s4, s10, 1, s9
    call    lantern_get_attesting_indices
    sd      s10, 0(s4)
    bnez    a0, 99f
    ld      t3, 128(sp)
    ld      a5, PendingAttestation_inclusion_delay(t3)
    slli    t4, s9, 1
.if \k == 2
    add     t4, t4, s9
.endif
    add     t4, s8, t4
    SCRATCH_LIST t3, s4, s10, 1, s9
    ld      t2, LIST_COUNT(t3)
    addi    t3, t3, LIST_FIXED
33: beqz    t2, 32b
    ld      t0, 0(t3)
    addi    t3, t3, 8
    addi    t2, t2, -1
    bgeu    t0, s9, 33b
    add     t1, t4, t0
    lbu     t5, 0(t1)
    bgeu    a5, t5, 33b
    sb      a5, 0(t1)
    j       33b
39:
.endm
.endif

/*
 * (pre, block, early, late, config, scratch, out) -> a0: the proposer's rewards of the block on
 * its pre-state, part by part (node.md, lantern_node_block_rewards). s1 pre, s2 the body, s3
 * config, s4 scratch, s5 out, s6 early, s7 late, s8 the bytes of the validators (list 0: the
 * slashed marks at 0; from altair the copies of the previous and current participation at n and
 * 2n; in phase0 the rewarded marks at n, bit 0 for the epoch before the block's and bit 1 for its
 * own, and the lowest delays of early and late at 2n and 3n), s9 the validator count n, s10 the
 * scratch's size after the decoded block. Locals: 0 the scratch's size on entry, 8 the epoch, 16
 * the next entry of a list and 24 the count left, 32 the base reward per increment (phase0: the
 * square root of early's total active balance, 40 of late's), 48 the flags (FLAGS_BYTES), 96 the
 * CommitteeCache, 104 the inclusion delay, 120 a value, 128 the attestation, 136 its E, 144 its
 * lowest delays, 152 its bit.
 */
SPEC_FUNCTION node_block_rewards
    ENTER 160
    mv      s5, a6                          # out first: the macros below use a6 and a7
    mv      s1, a0
    mv      s6, a2
    mv      s7, a3
    mv      s3, a4
    mv      s4, a5
    ld      t0, 0(s4)
    sd      t0, 0(sp)
    LDQ     t0, s3, CONFIG_COMMITTEE_CACHE
    sd      t0, 96(sp)
    ADDRESS a0, lantern_type_SignedBeaconBlock
    mv      a2, s4
    call    node_decode                     # a1: the block
    li      t0, 1
    beq     a0, t0, 97f
    bgtu    a0, t0, 96f
    PART    t1, t2, a1, SignedBeaconBlock_message
    ld      t0, BeaconBlock_slot(t1)
    LDQ     t2, s1, BeaconState_slot
    bne     t0, t2, 95f
    PART    s2, t2, t1, BeaconBlock_body
    ld      t0, BeaconBlock_proposer_index(t1)
    sd      t0, 120(sp)
    ld      s10, 0(s4)
    NEED_SCRATCH s4, s1, 6, 97f
.if FORK == FORK_PHASE0
    beqz    s6, 1f
    NEED_SCRATCH s4, s6, 6, 97f
1:  beqz    s7, 2f
    NEED_SCRATCH s4, s7, 6, 97f
2:
.endif
    ld      t0, 120(sp)                     # out: the proposer, then 0
    sd      t0, 0(s5)
    sd      zero, 8(s5)
    sd      zero, 16(s5)
    sd      zero, 24(s5)
    sd      zero, 32(s5)
    sd      zero, 40(s5)
    LDQ     s9, s1, BeaconState_validators + 8
    SCRATCH_LIST s8, s4, s10, 0, s9
    addi    s8, s8, LIST_FIXED
    mv      a0, s8
    slli    a1, s9, 2
    call    lantern_zero
    mv      a0, s1
    addi    a1, sp, 8
    call    lantern_get_current_epoch
    PART    t1, t2, s2, BeaconBlockBody_proposer_slashings  # proposer_slashings: each whistleblower_reward
    PART    t3, t4, s1, BeaconState_validators
    li      t5, FORK_WHISTLEBLOWER_REWARD_QUOTIENT
3:  beqz    t2, 4f
    ld      t0, (ProposerSlashing_signed_header_1 + SignedBeaconBlockHeader_message + BeaconBlockHeader_proposer_index)(t1)
    bgeu    t0, s9, 96f
    slli    t6, t0, 7
    add     t6, t3, t6
    ld      t6, Validator_effective_balance(t6)
    divu    t6, t6, t5
    ld      a0, 32(s5)
    add     a0, a0, t6
    sd      a0, 32(s5)
    add     t6, s8, t0
    li      a0, 1
    sb      a0, 0(t6)
    li      t6, ProposerSlashing__mem
    add     t1, t1, t6
    addi    t2, t2, -1
    j       3b
4:  PART    t1, t2, s2, BeaconBlockBody_attester_slashings  # attester_slashings: those process_attester_slashing slashes
    sd      t1, 16(sp)
    sd      t2, 24(sp)
5:  ld      t1, 16(sp)
    ld      t2, 24(sp)
    beqz    t2, 10f
    ld      t0, 0(t1)
    add     t0, t1, t0
    sd      t0, 16(sp)
    addi    t2, t2, -1
    sd      t2, 24(sp)
    PART    t3, t4, t1, AttesterSlashing_attestation_1
    PART    a0, a1, t3, IndexedAttestation_attesting_indices
    slli    a1, a1, 3
    add     a1, a0, a1
    PART    t3, t4, t1, AttesterSlashing_attestation_2
    PART    a2, a3, t3, IndexedAttestation_attesting_indices
    slli    a3, a3, 3
    add     a3, a2, a3
    PART    a4, t4, s1, BeaconState_validators
    ld      a5, 8(sp)
6:  bgeu    a0, a1, 5b                      # the sorted intersection, by merge
    bgeu    a2, a3, 5b
    ld      t3, 0(a0)
    ld      t4, 0(a2)
    bltu    t3, t4, 61f
    bltu    t4, t3, 62f
    addi    a0, a0, 8
    addi    a2, a2, 8
    bgeu    t3, s9, 96f
    add     t5, s8, t3
    lbu     t6, 0(t5)                       # an earlier slashing of the body slashed it
    bnez    t6, 6b
    slli    t6, t3, 7                       # is_slashable_validator(validator, epoch)
    add     t6, a4, t6
    lbu     t0, Validator_slashed(t6)
    bnez    t0, 6b
    ld      t0, Validator_activation_epoch(t6)
    bltu    a5, t0, 6b
    ld      t0, Validator_withdrawable_epoch(t6)
    bgeu    a5, t0, 6b
    li      t0, 1
    sb      t0, 0(t5)
    ld      t6, Validator_effective_balance(t6)
    li      t0, FORK_WHISTLEBLOWER_REWARD_QUOTIENT
    divu    t6, t6, t0
    ld      t0, 40(s5)
    add     t0, t0, t6
    sd      t0, 40(s5)
    j       6b
61: addi    a0, a0, 8
    j       6b
62: addi    a2, a2, 8
    j       6b
10:
.if FORK >= FORK_ALTAIR
    SCRATCH_GIVE s4, s10, 2, s9             # sync_aggregate: the set bits times proposer_reward
    mv      a0, s1
    mv      a1, s4
    call    node_sync_values
    sd      s10, 0(s4)
    bnez    a0, 99f
    li      t0, BeaconBlockBody_sync_aggregate + SyncAggregate_sync_committee_bits
    add     t0, s2, t0
    li      t1, 0
    li      t2, SYNC_COMMITTEE_SIZE / 8
11: beqz    t2, 13f
    lbu     t3, 0(t0)
12: beqz    t3, 121f
    addi    t4, t3, -1
    and     t3, t3, t4
    addi    t1, t1, 1
    j       12b
121: addi   t0, t0, 1
    addi    t2, t2, -1
    j       11b
13: mul     t1, t1, a2
    sd      t1, 24(s5)
    PART    a1, a2, s1, BeaconState_previous_epoch_participation  # copies of the flags
    bleu    a2, s9, 14f
    mv      a2, s9
14: add     a0, s8, s9
    call    lantern_copy
    PART    a1, a2, s1, BeaconState_current_epoch_participation
    bleu    a2, s9, 15f
    mv      a2, s9
15: slli    a0, s9, 1
    add     a0, s8, a0
    call    lantern_copy
    SCRATCH_GIVE s4, s10, 2, s9
    mv      a0, s1
    mv      a1, s4
    addi    a2, sp, 32
    call    lantern_get_base_reward_per_increment
    sd      s10, 0(s4)
    bnez    a0, 99f
    PART    t1, t2, s2, BeaconBlockBody_attestations    # attestations: process_attestation's proposer_reward of each
    sd      t1, 16(sp)
    sd      t2, 24(sp)
20: ld      t1, 16(sp)
    ld      t2, 24(sp)
    beqz    t2, 90f
    sd      t1, 128(sp)
    ld      t0, 0(t1)
    add     t0, t1, t0
    sd      t0, 16(sp)
    addi    t2, t2, -1
    sd      t2, 24(sp)
    LDQ     t0, s1, BeaconState_slot
    ld      t3, (Attestation_data + AttestationData_slot)(t1)
    sub     t0, t0, t3
    sd      t0, 104(sp)
    li      t0, FLAGS_BYTES
    sd      t0, 48(sp)
    mv      a0, s1
    addi    a1, t1, Attestation_data
    addi    a2, sp, 104
    addi    a3, sp, 48
    call    lantern_get_attestation_participation_flag_indices
    bnez    a0, 99f
    SCRATCH_GIVE s4, s10, 2, s9
    mv      a0, s1
    ld      a1, 128(sp)
    ld      a2, 96(sp)
    mv      a3, s4
    SCRATCH_LIST a4, s4, s10, 1, s9
    call    lantern_get_attesting_indices
    sd      s10, 0(s4)
    bnez    a0, 99f
    ld      t1, 128(sp)                     # the copy of the target epoch's flags
    ld      t0, (Attestation_data + AttestationData_target + Checkpoint_epoch)(t1)
    ld      t2, 8(sp)
    add     a5, s8, s9
    bne     t0, t2, 21f
    add     a5, a5, s9
21: ld      t2, (48 + LIST_COUNT)(sp)      # the flags as bits
    addi    t3, sp, 48 + LIST_FIXED
    li      a3, 0
22: beqz    t2, 23f
    ld      t4, 0(t3)
    li      t5, 1
    sll     t5, t5, t4
    or      a3, a3, t5
    addi    t3, t3, 8
    addi    t2, t2, -1
    j       22b
23: SCRATCH_LIST t3, s4, s10, 1, s9
    ld      t2, LIST_COUNT(t3)
    addi    t3, t3, LIST_FIXED
    li      a4, 0                           # proposer_reward_numerator
    PART    a1, t4, s1, BeaconState_validators
    li      a2, EFFECTIVE_BALANCE_INCREMENT
24: beqz    t2, 29f
    ld      t4, 0(t3)
    addi    t3, t3, 8
    addi    t2, t2, -1
    bgeu    t4, s9, 96f
    add     t5, a5, t4
    lbu     t6, 0(t5)
    not     t0, t6
    and     t0, t0, a3                      # the flags it takes now
    beqz    t0, 24b
    or      t6, t6, t0
    sb      t6, 0(t5)
    slli    t5, t4, 7
    add     t5, a1, t5
    ld      t5, Validator_effective_balance(t5)
    divu    t5, t5, a2
    ld      t6, 32(sp)
    mul     t5, t5, t6                      # get_base_reward(state, index)
    li      t6, 0
    andi    t1, t0, 1 << TIMELY_SOURCE_FLAG_INDEX
    beqz    t1, 25f
    addi    t6, t6, TIMELY_SOURCE_WEIGHT
25: andi    t1, t0, 1 << TIMELY_TARGET_FLAG_INDEX
    beqz    t1, 26f
    addi    t6, t6, TIMELY_TARGET_WEIGHT
26: andi    t1, t0, 1 << TIMELY_HEAD_FLAG_INDEX
    beqz    t1, 27f
    addi    t6, t6, TIMELY_HEAD_WEIGHT
27: mul     t5, t5, t6
    add     a4, a4, t5
    j       24b
29: li      t0, (WEIGHT_DENOMINATOR - PROPOSER_WEIGHT) * WEIGHT_DENOMINATOR / PROPOSER_WEIGHT
    divu    a4, a4, t0
    ld      t0, 16(s5)
    add     t0, t0, a4
    sd      t0, 16(s5)
    j       20b
.else
    slli    t0, s9, 1                       # the lowest delays of early and late: none yet
    add     t0, s8, t0
    slli    t1, s9, 1
    li      t2, 255
30: beqz    t1, 31f
    sb      t2, 0(t0)
    addi    t0, t0, 1
    addi    t1, t1, -1
    j       30b
31: REWARD_LOWEST s6, 1, 32
    REWARD_LOWEST s7, 2, 40
    PART    t1, t2, s2, BeaconBlockBody_attestations    # attestations: the proposer rewards of get_inclusion_delay_deltas
    sd      t1, 16(sp)
    sd      t2, 24(sp)
40: ld      t1, 16(sp)
    ld      t2, 24(sp)
    beqz    t2, 90f
    sd      t1, 128(sp)
    ld      t0, 0(t1)
    add     t0, t1, t0
    sd      t0, 16(sp)
    addi    t2, t2, -1
    sd      t2, 24(sp)
    ld      t0, (Attestation_data + AttestationData_target + Checkpoint_epoch)(t1)
    ld      t2, 8(sp)
    beq     t0, t2, 41f
    addi    t3, t0, 1
    bne     t3, t2, 95f
    mv      t3, s6                          # the epoch before the block's: early
    slli    t4, s9, 1
    add     t4, s8, t4
    li      t5, 1
    j       42f
41: mv      t3, s7                          # the block's epoch: late
    slli    t4, s9, 1
    add     t4, t4, s9
    add     t4, s8, t4
    li      t5, 2
42: bnez    t3, 43f
    LDQ     t6, s3, CONFIG_ALTAIR_FORK_EPOCH    # no E: the epoch after the target's is altair's or later
    addi    t2, t0, 1
    bltu    t2, t6, 95f
    j       40b
43: addi    t2, t0, 2                       # E at the last slot of the epoch after the target's
    slli    t2, t2, LOG2_SLOTS_PER_EPOCH
    addi    t2, t2, -1
    LDQ     t6, t3, BeaconState_slot
    bne     t6, t2, 95f
    sd      t3, 136(sp)
    sd      t4, 144(sp)
    sd      t5, 152(sp)
    LDQ     t0, s1, BeaconState_slot
    ld      t2, (Attestation_data + AttestationData_slot)(t1)
    sub     t0, t0, t2
    sd      t0, 104(sp)
    SCRATCH_GIVE s4, s10, 2, s9
    mv      a0, s1
    mv      a1, t1
    ld      a2, 96(sp)
    mv      a3, s4
    SCRATCH_LIST a4, s4, s10, 1, s9
    call    lantern_get_attesting_indices
    sd      s10, 0(s4)
    bnez    a0, 99f
    ld      t5, 152(sp)
    ld      a5, 32(sp)                      # the square root of E's total active balance
    li      t0, 1
    beq     t5, t0, 45f
    ld      a5, 40(sp)
45: ld      t3, 136(sp)
    PART    a1, a2, t3, BeaconState_validators
    ld      a3, 144(sp)
    add     a4, s8, s9                      # the rewarded marks
    ld      t6, 104(sp)
    SCRATCH_LIST t3, s4, s10, 1, s9
    ld      t2, LIST_COUNT(t3)
    addi    t3, t3, LIST_FIXED
44: beqz    t2, 40b
    ld      t0, 0(t3)
    addi    t3, t3, 8
    addi    t2, t2, -1
    bgeu    t0, s9, 96f
    add     t1, a4, t0
    lbu     t4, 0(t1)
    and     a0, t4, t5
    bnez    a0, 44b
    or      t4, t4, t5
    sb      t4, 0(t1)
    bgeu    t0, a2, 96f
    slli    t1, t0, 7
    add     t1, a1, t1
    lbu     t4, Validator_slashed(t1)       # unslashed in E
    bnez    t4, 44b
    add     t4, a3, t0                      # and no attestation of E with a lower delay
    lbu     t4, 0(t4)
    bltu    t4, t6, 44b
    ld      t4, Validator_effective_balance(t1)
    li      a0, BASE_REWARD_FACTOR
    mul     t4, t4, a0
    divu    t4, t4, a5
    srli    t4, t4, 2                       # get_base_reward(E, index): // BASE_REWARDS_PER_EPOCH
    srli    t4, t4, 3                       # // PROPOSER_REWARD_QUOTIENT
    ld      a0, 16(s5)
    add     a0, a0, t4
    sd      a0, 16(s5)
    j       44b
.endif
90: ld      t0, 16(s5)                      # total
    ld      t1, 24(s5)
    add     t0, t0, t1
    ld      t1, 32(s5)
    add     t0, t0, t1
    ld      t1, 40(s5)
    add     t0, t0, t1
    sd      t0, 8(s5)
    li      a0, LANTERN_OK
99: ld      t0, 0(sp)
    sd      t0, 0(s4)
    LEAVE 160
95: li      a0, LANTERN_INVALID_SLOT
    j       99b
96: li      a0, LANTERN_INVALID_ENCODING
    j       99b
97: li      a0, LANTERN_BUFFER_TOO_SMALL
    j       99b
SPEC_END node_block_rewards

.if FORK >= FORK_ALTAIR
/*
 * a0 = the entry of the validator a0 among the a2 entries of 24 bytes at a1 (index, balance,
 * member), a new one with its balance in the state a3 and member 0 when there is none, a2 = the
 * count; a0 = 0 for an index past the validators. Uses a4-a7, t0.
 */
LOCAL_FUNCTION node_reward_entry
    UNWIND_END_PROLOGUE
    mv      a4, a1
    mv      a5, a2
1:  beqz    a5, 2f
    ld      a6, 0(a4)
    beq     a6, a0, 3f
    addi    a4, a4, 24
    addi    a5, a5, -1
    j       1b
2:  PART    a6, t0, a3, BeaconState_balances
    bgeu    a0, t0, 4f
    slli    t0, a0, 3
    add     t0, a6, t0
    ld      t0, 0(t0)
    sd      a0, 0(a4)
    sd      t0, 8(a4)
    sd      zero, 16(a4)
    addi    a2, a2, 1
3:  mv      a0, a4
    ret
4:  li      a0, 0
    ret
END_FUNCTION node_reward_entry

.set SYNC_REWARD_EXTRA, 8 * SYNC_COMMITTEE_SIZE + SYNC_TABLE_BYTES + 24   /* the places, the table of find_pubkeys and its 3 words */
.if 24 * (SYNC_COMMITTEE_SIZE + 1) > SYNC_TABLE_BYTES
.error "lantern_node_sync_rewards keeps its entries where the table of find_pubkeys was"
.endif

/*
 * (pre, block, scratch, out) -> a0: the balance changes of the block's sync aggregate on its
 * pre-state (node.md, lantern_node_sync_rewards). s1 pre, s2 the bits, s3 out, s4 scratch, s5 the
 * places' validator indices (at the end of scratch, before the decoded block), s6 the hash table of
 * find_pubkeys, then the entries of node_reward_entry, s7 their count, s8 participant_reward, s9
 * proposer_reward, s10 the proposer. Locals: 0 the scratch's size on entry, 8 the proposer rewards
 * it took, 16 the place.
 */
SPEC_FUNCTION node_sync_rewards
    ENTER 32
    mv      s1, a0
    mv      s4, a2
    mv      s3, a3
    ld      t0, 0(s4)
    sd      t0, 0(sp)
    ld      t0, 0(s3)
    li      t1, 24 + 16 * SYNC_COMMITTEE_SIZE
    bltu    t0, t1, 97f
    ADDRESS a0, lantern_type_SignedBeaconBlock
    mv      a2, s4
    call    node_decode                     # a1: the block
    li      t0, 1
    beq     a0, t0, 97f
    bgtu    a0, t0, 96f
    PART    t1, t2, a1, SignedBeaconBlock_message
    ld      t0, BeaconBlock_slot(t1)
    LDQ     t2, s1, BeaconState_slot
    bne     t0, t2, 95f
    ld      s10, BeaconBlock_proposer_index(t1)
    PART    s2, t2, t1, BeaconBlock_body
    li      t0, BeaconBlockBody_sync_aggregate + SyncAggregate_sync_committee_bits
    add     s2, s2, t0
    NEED_SCRATCH_B s4, s1, 1, SYNC_REWARD_EXTRA, 97f
    ld      t0, 0(s4)                       # the places, then the table, at the end
    li      t1, 8 * SYNC_COMMITTEE_SIZE
    sub     t0, t0, t1
    add     s5, s4, t0
    li      t1, SYNC_TABLE_BYTES + 24
    sub     t0, t0, t1
    add     s6, s4, t0
    sd      t0, 0(s4)                       # what callees get
    mv      a0, s1                          # committee_indices, as process_sync_aggregate finds them
    li      a1, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    add     a1, s1, a1
    mv      a2, s5
    mv      a3, s6
    call    find_pubkeys
    bnez    a0, 96f
    mv      a0, s1
    mv      a1, s4
    call    node_sync_values
    bnez    a0, 99f
    mv      s8, a1
    mv      s9, a2
    sd      zero, 8(sp)
    sd      zero, 16(sp)
    li      s7, 0
1:  ld      t0, 16(sp)                      # each place, in order
    li      t1, SYNC_COMMITTEE_SIZE
    bgeu    t0, t1, 5f
    slli    t1, t0, 3
    add     t1, s5, t1
    ld      a0, 0(t1)
    mv      a1, s6
    mv      a2, s7
    mv      a3, s1
    call    node_reward_entry
    mv      s7, a2
    beqz    a0, 96f
    li      t0, 1
    sd      t0, 16(a0)                      # a member
    ld      t0, 16(sp)
    srli    t1, t0, 3
    add     t1, s2, t1
    lbu     t1, 0(t1)
    andi    t2, t0, 7
    srl     t1, t1, t2
    andi    t1, t1, 1
    beqz    t1, 3f
    ld      t0, 8(a0)                       # the participant takes participant_reward, the proposer proposer_reward
    add     t0, t0, s8
    sd      t0, 8(a0)
    mv      a0, s10
    mv      a1, s6
    mv      a2, s7
    mv      a3, s1
    call    node_reward_entry
    mv      s7, a2
    beqz    a0, 96f
    ld      t0, 8(a0)
    add     t0, t0, s9
    sd      t0, 8(a0)
    ld      t0, 8(sp)
    add     t0, t0, s9
    sd      t0, 8(sp)
    j       4f
3:  ld      t0, 8(a0)                       # decrease_balance: down to 0 at the least
    bgeu    t0, s8, 31f
    li      t0, 0
    j       32f
31: sub     t0, t0, s8
32: sd      t0, 8(a0)
4:  ld      t0, 16(sp)
    addi    t0, t0, 1
    sd      t0, 16(sp)
    j       1b
5:  PART    a6, t0, s1, BeaconState_balances    # the members in index order: the lowest after the last
    li      a4, 0                           # 1 once one is written
    li      a5, 0                           # the last written
    addi    t6, s3, 24
6:  li      t0, -1
    li      t1, 0
    mv      t2, s6
    mv      t3, s7
7:  beqz    t3, 9f
    ld      t4, 0(t2)
    ld      t5, 16(t2)
    beqz    t5, 8f
    beqz    a4, 71f
    bleu    t4, a5, 8f
71: bgeu    t4, t0, 8f
    mv      t0, t4
    mv      t1, t2
8:  addi    t2, t2, 24
    addi    t3, t3, -1
    j       7b
9:  beqz    t1, 11f
    slli    t2, t0, 3
    add     t2, a6, t2
    ld      t2, 0(t2)
    ld      t3, 8(t1)
    sub     t3, t3, t2                      # after less before
    bne     t0, s10, 10f
    ld      t2, 8(sp)                       # the proposer: less the proposer rewards
    sub     t3, t3, t2
10: sd      t0, 0(t6)
    sd      t3, 8(t6)
    addi    t6, t6, 16
    li      a4, 1
    mv      a5, t0
    j       6b
11: sub     t0, t6, s3
    addi    t0, t0, -24
    li      t1, 24
    sd      t1, 8(s3)
    sd      t0, 16(s3)
    li      a0, LANTERN_OK
99: ld      t0, 0(sp)
    sd      t0, 0(s4)
    LEAVE 32
95: li      a0, LANTERN_INVALID_SLOT
    j       99b
96: li      a0, LANTERN_INVALID_ENCODING
    j       99b
97: li      a0, LANTERN_BUFFER_TOO_SMALL
    j       99b
SPEC_END node_sync_rewards
.else
/* (pre, block, scratch, out) -> LANTERN_NO_STATE_ANSWER: phase0 has no sync committee (node.md, lantern_node_sync_rewards). */
SPEC_FUNCTION node_sync_rewards
    FRAME 0
    li      a0, LANTERN_NO_STATE_ANSWER
    UNFRAME 0
SPEC_END node_sync_rewards
.endif

/* ---------------------------------------------------------------- Attestation rewards (beacon-api.md, getAttestationsRewards) */

.if FORK >= FORK_ALTAIR
/* The participating balance of the flag at the epoch (a pointer in epoch) into base + off: get_total_balance of the unslashed participating indices. */
.macro TOTALS_FLAG flag, epoch, base, off
    li      t0, \flag
    sd      t0, 8(sp)
    SCRATCH_GIVE s3, s7, 1, s6
    mv      a0, s1
    addi    a1, sp, 8
    mv      a2, \epoch
    mv      a3, s3
    mv      a4, s8
    call    lantern_get_unslashed_participating_indices
    sd      s7, 0(s3)
    bnez    a0, 99f
    mv      a0, s1
    mv      a1, s8
    addi    a2, \base, \off
    call    lantern_get_total_balance
.endm
.else
/* The attesting balance of the attestations of getter at the epoch (a pointer in epoch) into base + off: lantern_get_attesting_balance. */
.macro TOTALS_PENDING getter, epoch, base, off
    mv      a0, s1
    mv      a1, \epoch
    mv      a2, s8
    call    \getter
    bnez    a0, 99f
    sd      s9, 0(s3)
    mv      a0, s1
    mv      a1, s8
    mv      a2, s3
    addi    a3, \base, \off
    call    lantern_get_attesting_balance
    bnez    a0, 99f
.endm
.endif

/*
 * (state, config, mode, scratch, out) -> a0: the totals of the attestation rewards of the
 * previous epoch (node.md, lantern_node_reward_totals). s1 state, s2 config, s3 scratch, s4 out,
 * s5 mode, s6 the validator count, s7 the scratch's size, s8 a list of indices (phase0: the
 * matching attestations), s9 (phase0) the scratch's size before them. Locals: 0 the current
 * epoch, 8 a flag, 16 the current epoch's target balance.
 */
SPEC_FUNCTION node_reward_totals
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s5, a2
    mv      s3, a3
    mv      s4, a4
.if FORK == FORK_PHASE0
    NEED_SCRATCH_B s3, s1, 6, PENDING_REFS_BYTES, 9f
.else
    NEED_SCRATCH s3, s1, 3, 9f
.endif
    ld      s7, 0(s3)
    LDQ     s6, s1, BeaconState_validators + 8
    sd      zero, 16(sp)
    mv      a0, s1
    mv      a1, s4
    call    lantern_get_previous_epoch
    mv      a0, s1
    mv      a1, sp
    call    lantern_get_current_epoch
    sd      s5, 64(s4)
    LDQ     t0, s2, CONFIG_INACTIVITY_SCORE_BIAS
    LDQ     t1, s2, CONFIG_INACTIVITY_SCORE_RECOVERY_RATE
    sd      t0, 80(s4)
    sd      t1, 88(s4)
    li      t0, MAX_EFFECTIVE_BALANCE       # the largest effective balance of the fork of the previous epoch
.if FORK >= FORK_ELECTRA
    li      t0, MAX_EFFECTIVE_BALANCE_ELECTRA
.if FORK == FORK_ELECTRA
    LDQ     t1, s1, BeaconState_fork + Fork_epoch   # before the state's fork: deneb's
    ld      t2, 0(s4)
    bgeu    t2, t1, 1f
    li      t0, MAX_EFFECTIVE_BALANCE
1:
.endif
.endif
    sd      t0, 72(s4)
    mv      a0, s1
    mv      a1, s3
    addi    a2, s4, 24
    call    lantern_get_total_active_balance
    bnez    a0, 99f
.if FORK == FORK_PHASE0
    addi    a0, s4, 24
    addi    a1, s4, 32
    call    lantern_integer_squareroot
    TAKE_REFS s8, s3, s9
    TOTALS_PENDING lantern_get_matching_source_attestations, s4, s4, 40
    TOTALS_PENDING lantern_get_matching_target_attestations, s4, s4, 48
    TOTALS_PENDING lantern_get_matching_head_attestations, s4, s4, 56
    beqz    s5, 5f
    ld      t0, 0(sp)
    li      t1, GENESIS_EPOCH + 1
    bleu    t0, t1, 5f
    mv      t3, sp
    TOTALS_PENDING lantern_get_matching_target_attestations, t3, sp, 16
.else
    mv      a0, s1
    mv      a1, s3
    addi    a2, s4, 32
    call    lantern_get_base_reward_per_increment
    bnez    a0, 99f
    SCRATCH_LIST s8, s3, s7, 0, s6
    TOTALS_FLAG TIMELY_SOURCE_FLAG_INDEX, s4, s4, 40
    TOTALS_FLAG TIMELY_TARGET_FLAG_INDEX, s4, s4, 48
    TOTALS_FLAG TIMELY_HEAD_FLAG_INDEX, s4, s4, 56
    beqz    s5, 5f
    ld      t0, 0(sp)
    li      t1, GENESIS_EPOCH + 1
    bleu    t0, t1, 5f
    mv      t3, sp
    TOTALS_FLAG TIMELY_TARGET_FLAG_INDEX, t3, sp, 16
.endif
5:  LDQ     t2, s1, BeaconState_finalized_checkpoint + Checkpoint_epoch
    beqz    s5, 6f                          # mode 1: the finalized epoch weigh_justification_and_finalization would leave
    ld      t3, 0(sp)
    li      t0, GENESIS_EPOCH + 1
    bleu    t3, t0, 6f
    ADDQ    t0, s1, BeaconState_justification_bits
    lbu     t4, 0(t0)
    slli    t4, t4, 1
    andi    t4, t4, 0xf
    ld      t0, 24(s4)
    slli    t0, t0, 1                       # total * 2
    ld      t1, 48(s4)
    slli    t5, t1, 1
    add     t1, t1, t5
    bltu    t1, t0, 51f
    ori     t4, t4, 2
51: ld      t1, 16(sp)
    slli    t5, t1, 1
    add     t1, t1, t5
    bltu    t1, t0, 52f
    ori     t4, t4, 1
52: LDQ     a2, s1, BeaconState_previous_justified_checkpoint + Checkpoint_epoch
    LDQ     a3, s1, BeaconState_current_justified_checkpoint + Checkpoint_epoch
    andi    t0, t4, 0xe                     # the four rules in spec order: bits[1:4], bits[1:3], bits[0:3], bits[0:2]
    li      t1, 0xe
    bne     t0, t1, 53f
    addi    t1, a2, 3
    bne     t1, t3, 53f
    mv      t2, a2
53: andi    t0, t4, 0x6
    li      t1, 0x6
    bne     t0, t1, 54f
    addi    t1, a2, 2
    bne     t1, t3, 54f
    mv      t2, a2
54: andi    t0, t4, 0x7
    li      t1, 0x7
    bne     t0, t1, 55f
    addi    t1, a3, 2
    bne     t1, t3, 55f
    mv      t2, a3
55: andi    t0, t4, 0x3
    li      t1, 0x3
    bne     t0, t1, 6f
    addi    t1, a3, 1
    bne     t1, t3, 6f
    mv      t2, a3
6:  ld      t0, 0(s4)                       # get_finality_delay, and the leak
    sub     t0, t0, t2
    sd      t0, 8(s4)
    li      t1, MIN_EPOCHS_TO_INACTIVITY_PENALTY
    sltu    t1, t1, t0
    sd      t1, 16(s4)
    li      a0, LANTERN_OK
99: sd      s7, 0(s3)
    LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
SPEC_END node_reward_totals

.if FORK == FORK_PHASE0
/* The vote's item at ioff: base_reward in a leak, else base_reward * its attesting increments // the active increments. */
.macro IDEAL_VOTE boff, ioff
    ld      t2, \boff(a0)
    divu    t2, t2, a3
    mul     t2, t0, t2
    divu    t2, t2, a4
    beqz    a5, 1f
    mv      t2, t0
1:  sd      t2, \ioff(a2)
.endm
.else
/* The flag's item at ioff: 0 in a leak, else base_reward * weight * its increments // (active_increments * WEIGHT_DENOMINATOR). */
.macro IDEAL_FLAG boff, weight, ioff
    ld      t2, \boff(a0)
    divu    t2, t2, a3
    li      t3, \weight
    mul     t3, t0, t3
    mul     t2, t3, t2
    divu    t2, t2, a4
    beqz    a5, 1f
    li      t2, 0
1:  sd      t2, \ioff(a2)
.endm
.endif

/*
 * (totals, effective_balance, out) -> a0: the item of a validator of the effective balance that
 * voted for all three in time (node.md, lantern_node_ideal_reward). A leaf: uses a3-a5, t0-t3.
 */
SPEC_FUNCTION node_ideal_reward
    UNWIND_END_PROLOGUE
    li      a3, EFFECTIVE_BALANCE_INCREMENT
    ld      a4, 24(a0)
    divu    a4, a4, a3                      # the active increments
    ld      a5, 16(a0)                      # the leak
    sd      a1, 40(a2)
.if FORK == FORK_PHASE0
    li      t0, BASE_REWARD_FACTOR          # get_base_reward
    mul     t0, a1, t0
    ld      t1, 32(a0)
    divu    t0, t0, t1
    srli    t0, t0, 2
    srli    t1, t0, 3                       # get_proposer_reward: // PROPOSER_REWARD_QUOTIENT
    IDEAL_VOTE 56, 0
    IDEAL_VOTE 48, 8
    IDEAL_VOTE 40, 16
    sub     t2, t0, t1                      # inclusion_delay at a delay of 1
    sd      t2, 24(a2)
    slli    t2, t0, 2                       # inactivity in a leak: -(BASE_REWARDS_PER_EPOCH * base_reward - the proposer's)
    sub     t2, t2, t1
    neg     t2, t2
    bnez    a5, 1f
    li      t2, 0
1:  sd      t2, 32(a2)
.else
    divu    t0, a1, a3                      # base_reward: increments * get_base_reward_per_increment
    ld      t1, 32(a0)
    mul     t0, t0, t1
    slli    a4, a4, 6
    IDEAL_FLAG 56, TIMELY_HEAD_WEIGHT, 0
    IDEAL_FLAG 48, TIMELY_TARGET_WEIGHT, 8
    IDEAL_FLAG 40, TIMELY_SOURCE_WEIGHT, 16
    sd      zero, 24(a2)
    sd      zero, 32(a2)
.endif
    li      a0, LANTERN_OK
    ret
SPEC_END node_ideal_reward

.if FORK == FORK_PHASE0
/* Each validator of the window among the attesting indices of the attestations of getter: its status byte takes bit; with lowest 1, its delay byte the lowest inclusion_delay. */
.macro WINDOW_MARK getter, bit, lowest
    mv      a0, s1
    mv      a1, s3
    mv      a2, s8
    call    \getter
    bnez    a0, 99f
    addi    t0, s8, LIST_FIXED
    ld      t1, LIST_COUNT(s8)
    sd      t0, 16(sp)
    sd      t1, 24(sp)
71: ld      t0, 16(sp)
    ld      t1, 24(sp)
    beqz    t1, 79f
    ld      t2, 0(t0)
    addi    t0, t0, 8
    addi    t1, t1, -1
    sd      t0, 16(sp)
    sd      t1, 24(sp)
    add     a1, s1, t2
    sd      a1, 32(sp)
    SCRATCH_GIVE s6, s10, 2, s9
    mv      a0, s1
    ld      a1, 32(sp)
    mv      a2, s2
    mv      a3, s6
    SCRATCH_LIST a4, s6, s10, 1, s9
    call    lantern_get_attesting_indices
    sd      s10, 0(s6)
    bnez    a0, 99f
    ld      t0, 32(sp)
    ld      t4, PendingAttestation_inclusion_delay(t0)
    SCRATCH_LIST t0, s6, s10, 1, s9
    ld      t1, LIST_COUNT(t0)
    addi    t0, t0, LIST_FIXED
    ld      t3, 40(sp)                      # the status bytes
72: beqz    t1, 71b
    ld      t2, 0(t0)
    addi    t0, t0, 8
    addi    t1, t1, -1
    bltu    t2, s4, 72b
    sub     t2, t2, s4
    bgeu    t2, s5, 72b
    slli    t2, t2, 1
    add     t2, t3, t2
    lbu     a5, 0(t2)
    ori     a5, a5, \bit
    sb      a5, 0(t2)
.if \lowest
    lbu     a5, 1(t2)
    bgeu    t4, a5, 72b
    sb      t4, 1(t2)
.endif
    j       72b
79:
.endm

/* The vote's item at ioff: an attester, base_reward in a leak, else base_reward * its attesting increments // the active increments; another, -base_reward. */
.macro WINDOW_VOTE bit, boff, ioff
    andi    a7, a5, (1 << \bit)
    beqz    a7, 91f
    bnez    t5, 92f
    ld      t4, \boff(s3)
    divu    t4, t4, a1
    mul     t4, a2, t4
    divu    t4, t4, t6
    sd      t4, \ioff(t2)
    j       93f
92: sd      a2, \ioff(t2)
    j       93f
91: neg     t4, a2
    sd      t4, \ioff(t2)
93:
.endm
.else
/* The flag's item at ioff: participating, 0 in a leak, else base_reward * weight * its increments // (active_increments * WEIGHT_DENOMINATOR); not, with penal, -(base_reward * weight // WEIGHT_DENOMINATOR). */
.macro REWARD_FLAG bit, weight, boff, ioff, penal
    andi    a7, a5, (1 << \bit)
    beqz    a7, 91f
    bnez    t5, 92f
    ld      t4, \boff(s3)
    divu    t4, t4, a1
    li      a6, \weight
    mul     a6, a2, a6
    mul     a6, a6, t4
    divu    a6, a6, t6
    sd      a6, \ioff(t2)
    j       92f
91:
.if \penal
    li      a6, \weight
    mul     a6, a2, a6
    srli    a6, a6, 6
    neg     a6, a6
    sd      a6, \ioff(t2)
.endif
92:
.endm
.endif

/*
 * (state, config, totals, first, count, scratch, out) -> a0: the attestation rewards of the
 * validators first to first + count - 1 (node.md, lantern_node_attestation_rewards). s1 state, s2
 * the CommitteeCache, s3 totals, s4 first, s5 count, s6 scratch, s7 out, s8 the validators
 * (phase0: first the matching attestations), s9 the validator count, s10 the scratch's size. In
 * the loop: t0 the place in the window, t1 the validator, t2 its item, t3 its Validator, a0 its
 * effective balance, a1 EFFECTIVE_BALANCE_INCREMENT, a2 its base reward, a5 its flags, t5 the
 * leak, t6 the active increments (from altair * WEIGHT_DENOMINATOR). Locals: 0 and 8 the previous
 * epoch's participation (from altair) and its count, 16 and 24 the inactivity scores and their
 * count (phase0: a list's cursor and count), 32 an attestation, 40 (phase0) a status and a delay
 * byte for each validator of the window.
 */
SPEC_FUNCTION node_attestation_rewards
    ENTER 48
    mv      s7, a6                          # out first: the macros below use a6 and a7
    mv      s1, a0
    LDQ     s2, a1, CONFIG_COMMITTEE_CACHE
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    LDQ     s9, s1, BeaconState_validators + 8
    add     t0, s4, s5
    bltu    t0, s4, 96f
    bgtu    t0, s9, 96f
    ld      s10, 0(s6)
.if FORK == FORK_PHASE0
    NEED_SCRATCH_B s6, s1, 6, PENDING_REFS_BYTES, 97f
    TAKE_REFS s8, s6, s10                   # s10: the scratch's size before the matching attestations
    SCRATCH_LIST t0, s6, s10, 0, s9         # the window's bytes: no vote, no delay
    addi    t0, t0, LIST_FIXED
    sd      t0, 40(sp)
    mv      t1, s5
    li      t2, 0xff00
1:  beqz    t1, 2f
    sh      t2, 0(t0)
    addi    t0, t0, 2
    addi    t1, t1, -1
    j       1b
2:  WINDOW_MARK lantern_get_matching_source_attestations, 1, 1
    WINDOW_MARK lantern_get_matching_target_attestations, 2, 0
    WINDOW_MARK lantern_get_matching_head_attestations, 4, 0
.else
    NEED_SCRATCH s6, s1, 1, 97f
    PART    t0, t1, s1, BeaconState_previous_epoch_participation
    sd      t0, 0(sp)
    sd      t1, 8(sp)
    PART    t0, t1, s1, BeaconState_inactivity_scores
    sd      t0, 16(sp)
    sd      t1, 24(sp)
.endif
    PART    s8, t0, s1, BeaconState_validators
    li      a1, EFFECTIVE_BALANCE_INCREMENT
    ld      t6, 24(s3)
    divu    t6, t6, a1                      # the active increments
.if FORK >= FORK_ALTAIR
    slli    t6, t6, 6                       # * WEIGHT_DENOMINATOR
.endif
    ld      t5, 16(s3)                      # the leak
    li      t0, 0
3:  bgeu    t0, s5, 8f
    add     t1, s4, t0
    li      t2, 48
    mul     t2, t0, t2
    add     t2, t2, s7                      # the item: 0
    sd      zero, 0(t2)
    sd      zero, 8(t2)
    sd      zero, 16(t2)
    sd      zero, 24(t2)
    sd      zero, 32(t2)
    sd      zero, 40(t2)
    slli    t3, t1, 7
    add     t3, s8, t3
    ld      a6, 0(s3)                       # eligible: active in the previous epoch, or slashed and not yet withdrawable
    ld      a7, Validator_activation_epoch(t3)
    bgtu    a7, a6, 4f
    ld      a7, Validator_exit_epoch(t3)
    bltu    a6, a7, 5f
4:  lbu     a7, Validator_slashed(t3)
    beqz    a7, 7f
    ld      a7, Validator_withdrawable_epoch(t3)
    addi    a0, a6, 1
    bgeu    a0, a7, 7f
5:  li      a0, 1
    sd      a0, 40(t2)
    ld      a0, Validator_effective_balance(t3)
.if FORK == FORK_PHASE0
    li      a2, BASE_REWARD_FACTOR          # get_base_reward
    mul     a2, a0, a2
    ld      a3, 32(s3)
    divu    a2, a2, a3
    srli    a2, a2, 2
    ld      a3, 40(sp)
    slli    a4, t0, 1
    add     a3, a3, a4
    lbu     a5, 0(a3)                       # the window's status: 1 source, 2 target, 4 head
    lbu     a4, 1(a3)                       # the lowest delay
    lbu     a7, Validator_slashed(t3)       # unslashed attesters only
    beqz    a7, 55f
    li      a5, 0
55: WINDOW_VOTE 0, 40, 16
    WINDOW_VOTE 1, 48, 8
    WINDOW_VOTE 2, 56, 0
    srli    a3, a2, 3                       # get_proposer_reward
    andi    a7, a5, 1
    beqz    a7, 61f
    sub     t4, a2, a3                      # inclusion_delay: the attester's part, // its lowest delay
    divu    t4, t4, a4
    sd      t4, 24(t2)
61: beqz    t5, 7f                          # inactivity, in a leak
    slli    t4, a2, 2
    sub     t4, t4, a3
    andi    a7, a5, 2
    bnez    a7, 62f
    ld      a6, 8(s3)                       # not a target attester: effective_balance * finality_delay // INACTIVITY_PENALTY_QUOTIENT
    mul     a6, a0, a6
    li      a7, INACTIVITY_PENALTY_QUOTIENT
    divu    a6, a6, a7
    add     t4, t4, a6
62: neg     t4, t4
    sd      t4, 32(t2)
.else
    divu    a2, a0, a1                      # base_reward
    ld      a3, 32(s3)
    mul     a2, a2, a3
    ld      a3, 0(sp)                       # the flags, of an unslashed validator
    ld      a4, 8(sp)
    li      a5, 0
    bgeu    t1, a4, 51f
    add     a7, a3, t1
    lbu     a5, 0(a7)
51: lbu     a7, Validator_slashed(t3)
    beqz    a7, 52f
    li      a5, 0
52: REWARD_FLAG TIMELY_SOURCE_FLAG_INDEX, TIMELY_SOURCE_WEIGHT, 40, 16, 1
    REWARD_FLAG TIMELY_TARGET_FLAG_INDEX, TIMELY_TARGET_WEIGHT, 48, 8, 1
    REWARD_FLAG TIMELY_HEAD_FLAG_INDEX, TIMELY_HEAD_WEIGHT, 56, 0, 0
    andi    a7, a5, (1 << TIMELY_TARGET_FLAG_INDEX)   # inactivity: not a timely target
    bnez    a7, 7f
    ld      a3, 16(sp)
    ld      a4, 24(sp)
    li      t4, 0
    bgeu    t1, a4, 56f
    slli    a7, t1, 3
    add     a7, a3, a7
    ld      t4, 0(a7)
56: ld      a6, 64(s3)                      # mode 1: its score as process_inactivity_updates leaves it
    beqz    a6, 57f
    ld      a6, 80(s3)
    add     t4, t4, a6
    bnez    t5, 57f
    ld      a6, 88(s3)
    bgeu    t4, a6, 58f
    mv      a6, t4
58: sub     t4, t4, a6
57: mul     t4, a0, t4
    ld      a6, 80(s3)
    li      a7, FORK_INACTIVITY_PENALTY_QUOTIENT
    mul     a6, a6, a7
    divu    t4, t4, a6
    neg     t4, t4
    sd      t4, 32(t2)
.endif
7:  addi    t0, t0, 1
    j       3b
8:  li      a0, LANTERN_OK
99:
.if FORK == FORK_PHASE0
    li      a7, PENDING_REFS_BYTES          # the scratch's size on entry
    add     a7, s10, a7
    sd      a7, 0(s6)
.else
    sd      s10, 0(s6)
.endif
    LEAVE 48
96: li      a0, LANTERN_INVALID_ENCODING
    LEAVE 48
97: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END node_attestation_rewards

/* a0 = the fork's TypeDescriptor of the NODE_JSON_* kind t0, or 0. Uses t1. */
LOCAL_FUNCTION node_type_of_kind
    UNWIND_END_PROLOGUE
    ADDRESS a0, lantern_type_SignedBeaconBlock
    li      t1, NODE_JSON_BLOCK
    beq     t0, t1, 9f
    ADDRESS a0, lantern_type_BeaconState
    li      t1, NODE_JSON_STATE
    beq     t0, t1, 9f
    ADDRESS a0, lantern_type_SignedVoluntaryExit
    li      t1, NODE_JSON_EXIT
    beq     t0, t1, 9f
    ADDRESS a0, lantern_type_ProposerSlashing
    li      t1, NODE_JSON_PROPOSER_SLASHING
    beq     t0, t1, 9f
    ADDRESS a0, lantern_type_AttesterSlashing
    li      t1, NODE_JSON_ATTESTER_SLASHING
    beq     t0, t1, 9f
.if FORK >= FORK_CAPELLA
    ADDRESS a0, lantern_type_SignedBLSToExecutionChange
    li      t1, NODE_JSON_BLS_CHANGE
    beq     t0, t1, 9f
.endif
    ADDRESS a0, lantern_type_Attestation
    li      t1, NODE_JSON_ATTESTATION
    beq     t0, t1, 9f
    ADDRESS a0, lantern_type_Attestations
    li      t1, NODE_JSON_ATTESTATIONS
    beq     t0, t1, 9f
    ADDRESS a0, lantern_type_SignedAggregateAndProof
    li      t1, NODE_JSON_AGGREGATE_AND_PROOF
    beq     t0, t1, 9f
.if FORK >= FORK_ALTAIR
    ADDRESS a0, lantern_type_SyncCommitteeMessage
    li      t1, NODE_JSON_SYNC_COMMITTEE_MESSAGE
    beq     t0, t1, 9f
    ADDRESS a0, lantern_type_SyncCommitteeContribution
    li      t1, NODE_JSON_SYNC_CONTRIBUTION
    beq     t0, t1, 9f
    ADDRESS a0, lantern_type_SignedContributionAndProof
    li      t1, NODE_JSON_CONTRIBUTION_AND_PROOF
    beq     t0, t1, 9f
    ADDRESS a0, lantern_type_SyncCommitteeSubscription
    li      t1, NODE_JSON_SYNC_SUBSCRIPTION
    beq     t0, t1, 9f
.endif
    ADDRESS a0, lantern_type_BeaconCommitteeSubscription
    li      t1, NODE_JSON_COMMITTEE_SUBSCRIPTION
    beq     t0, t1, 9f
    ADDRESS a0, lantern_type_ProposerPreparation
    li      t1, NODE_JSON_PROPOSER_PREPARATION
    beq     t0, t1, 9f
    ADDRESS a0, lantern_type_BeaconBlock
    li      t1, NODE_JSON_BEACON_BLOCK
    beq     t0, t1, 9f
.if FORK >= FORK_DENEB
    ADDRESS a0, lantern_type_BlockContents
    li      t1, NODE_JSON_BLOCK_CONTENTS
    beq     t0, t1, 9f
.endif
.if FORK >= FORK_BELLATRIX
    ADDRESS a0, lantern_type_SignedBlindedBeaconBlock
.else
    ADDRESS a0, lantern_type_SignedBeaconBlock
.endif
    li      t1, NODE_JSON_BLINDED_BLOCK
    beq     t0, t1, 9f
.if FORK >= FORK_ELECTRA
    ADDRESS a0, lantern_type_SingleAttestation
    li      t1, NODE_JSON_SINGLE_ATTESTATION
    beq     t0, t1, 9f
.endif
.if FORK >= FORK_DENEB && FORK < FORK_FULU
    ADDRESS a0, lantern_type_BlobSidecar
    li      t1, NODE_JSON_BLOB_SIDECAR
    beq     t0, t1, 9f
.endif
.if FORK >= FORK_FULU
    ADDRESS a0, lantern_type_DataColumnSidecar
    li      t1, NODE_JSON_DATA_COLUMN_SIDECAR
    beq     t0, t1, 9f
.endif
    li      a0, 0
9:  ret
END_FUNCTION node_type_of_kind

/* (kind, ssz, cursor, out): lantern_json_encode_ssz with the fork's type of the NODE_JSON_* kind. */
SPEC_FUNCTION node_json
    FRAME 0
    mv      t0, a0
    call    node_type_of_kind
    beqz    a0, 8f
    CALL_GLOBAL lantern_json_encode_ssz
    UNFRAME 0
8:  li      a0, LANTERN_INVALID_EVENT
    UNFRAME 0
SPEC_END node_json

/*
 * (kind, json, scratch, out, fault): lantern_json_decode with the fork's type of the NODE_JSON_*
 * kind (node.md, NODE_WORK_API_SUBMIT); LANTERN_INVALID_JSON for a kind of no type in the fork.
 */
SPEC_FUNCTION node_json_decode
    FRAME 0
    mv      t0, a0
    call    node_type_of_kind
    beqz    a0, 8f
    CALL_GLOBAL lantern_json_decode
    UNFRAME 0
8:  li      a0, LANTERN_INVALID_JSON
    UNFRAME 0
SPEC_END node_json_decode

/* The u32 \val at \addr, a byte at a time: the place may not be aligned. Uses \tmp. */
.macro NODE_STORE_U32 val, addr, tmp
    sb      \val, 0(\addr)
    srli    \tmp, \val, 8
    sb      \tmp, 1(\addr)
    srli    \tmp, \val, 16
    sb      \tmp, 2(\addr)
    srli    \tmp, \val, 24
    sb      \tmp, 3(\addr)
.endm

/* t2 = the SSZ size of the type of the field record t0 of the TypeDescriptor s1. Uses t1, t3. */
.macro NODE_FIELD_SIZE
    ld      t1, SSZ_FIELD_NODE(t0)
    li      t3, SSZ_NODE_STRIDE
    mul     t1, t1, t3
    ld      t3, SSZ_DESC_NODES_OFFSET(s1)
    add     t1, t1, t3
    add     t1, s1, t1
    ld      t2, SSZ_NODE_SSZ_SIZE(t1)
.endm

/* t0 = the field record s4 of the TypeDescriptor s1. Uses t1. */
.macro NODE_FIELD
    ld      t0, SSZ_DESC_FIELDS_OFFSET(s1)
    add     t0, s1, t0
    slli    t1, s4, 5
    add     t0, t0, t1
.endm

/*
 * a0 = the bytes of the SSZ default value of the type node a1 of the TypeDescriptor a0, written
 * at a2: zero bytes for a fixed size type, none for a list, the byte 1 for a bitlist, and for a
 * variable container or vector its fixed part with the offsets, then each variable part. s1 the
 * descriptor, s2 the node, s3 out, s4 a field or element, s5 their end, s6 the bytes, s7 the
 * first field or an index, s8 a size or a place in the fixed part.
 */
LOCAL_FUNCTION node_ssz_default
    ENTER 0
    mv      s1, a0
    mv      s3, a2
    ld      t0, SSZ_DESC_NODES_OFFSET(s1)
    add     t0, s1, t0
    li      t1, SSZ_NODE_STRIDE
    mul     t1, a1, t1
    add     s2, t0, t1
    ld      s6, SSZ_NODE_SSZ_SIZE(s2)
    beqz    s6, 1f
    mv      a0, s3                          # a fixed size type: zero bytes
    mv      a1, s6
    call    lantern_zero
    j       9f
1:  ld      t0, SSZ_NODE_KIND(s2)
    li      t1, SSZ_KIND_BIT_LIST
    bne     t0, t1, 2f
    li      t1, 1                           # a bitlist: its delimiter bit
    sb      t1, 0(s3)
    li      s6, 1
    j       9f
2:  li      t1, SSZ_KIND_CONTAINER
    beq     t0, t1, 5f
    li      t1, SSZ_KIND_VECTOR
    beq     t0, t1, 3f
    li      s6, 0                           # a list: empty
    j       9f
3:  ld      s5, SSZ_NODE_LENGTH(s2)         # a vector of variable elements: N offsets, then each element
    ld      s4, SSZ_NODE_ELEMENT(s2)
    slli    s6, s5, 2
    li      s7, 0
4:  bgeu    s7, s5, 9f
    slli    t0, s7, 2
    add     t0, s3, t0
    NODE_STORE_U32 s6, t0, t1
    mv      a0, s1
    mv      a1, s4
    add     a2, s3, s6
    call    node_ssz_default
    add     s6, s6, a0
    addi    s7, s7, 1
    j       4b
5:  ld      s7, SSZ_NODE_ELEMENT(s2)        # a variable container: the fixed part
    ld      s5, SSZ_NODE_LENGTH(s2)
    add     s5, s7, s5
    mv      s4, s7
    li      s6, 0
6:  bgeu    s4, s5, 7f
    NODE_FIELD
    ld      t1, SSZ_FIELD_FLAGS(t0)
    andi    t1, t1, SSZ_FIELD_VARIABLE
    li      t2, 4                           # a variable field: its offset, written below
    bnez    t1, 61f
    NODE_FIELD_SIZE
    mv      s8, t2
    add     a0, s3, s6
    mv      a1, t2
    call    lantern_zero
    mv      t2, s8
61: add     s6, s6, t2
    addi    s4, s4, 1
    j       6b
7:  mv      s4, s7                          # then each variable field, after its offset
    li      s8, 0
71: bgeu    s4, s5, 9f
    NODE_FIELD
    ld      t1, SSZ_FIELD_FLAGS(t0)
    andi    t1, t1, SSZ_FIELD_VARIABLE
    bnez    t1, 72f
    NODE_FIELD_SIZE
    add     s8, s8, t2
    j       73f
72: add     t1, s3, s8
    NODE_STORE_U32 s6, t1, t2
    addi    s8, s8, 4
    mv      a0, s1
    ld      a1, SSZ_FIELD_NODE(t0)
    add     a2, s3, s6
    call    node_ssz_default
    add     s6, s6, a0
73: addi    s4, s4, 1
    j       71b
9:  mv      a0, s6
    LEAVE 0
END_FUNCTION node_ssz_default

/*
 * (data, room, scratch, state, block): the anchor state and block of the genesis state in data.
 * s1 data, s2 room, s3 scratch, s4 state, s5 block, s6 the decoded state, then the block's SSZ
 * ByteList, s7 the default body's bytes, s8 the scratch size, restored on return. Locals: L
 * SizeBounds or a size, L+16 a root.
 */
SPEC_FUNCTION node_anchor
    ENTER 48
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      s8, 0(s3)
    ADDRESS a0, lantern_type_BeaconState    # the state, decoded at the end of scratch, then copied with room
    mv      a1, s1
    mv      a2, s3
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 7f
    mv      s6, a1
    mv      a0, s6
    mv      a1, s2
    addi    a2, sp, L
    call    lantern_beacon_state_copy_size
    ld      t0, L(sp)
    ld      t1, 0(s4)
    bltu    t1, t0, 8f
    mv      a0, s6
    mv      a1, s2
    mv      a2, s4
    call    lantern_beacon_state_copy
    bnez    a0, 8f
    sd      s8, 0(s3)
    ADDRESS a0, lantern_type_BeaconBlockBody    # the default body's bytes: the least SSZ size of the type
    addi    a1, sp, L
    CALL_GLOBAL lantern_ssz_size_bounds
    ld      s7, L(sp)
    addi    t0, s7, 24 + 84 + 7             # the block's SSZ bytes, a ByteList at the end of scratch
    andi    t0, t0, -8
    addi    t1, t0, 8
    bltu    s8, t1, 8f
    sub     t1, s8, t0
    sd      t1, 0(s3)
    add     s6, s3, t1
    sd      t0, 0(s6)
    li      t1, 24
    sd      t1, 8(s6)
    addi    t1, s7, 84
    sd      t1, 16(s6)
    ADDQ    t2, s4, BeaconState_latest_block_header
    ld      t1, BeaconBlockHeader_slot(t2)
    sd      t1, 24(s6)
    ld      t1, BeaconBlockHeader_proposer_index(t2)
    sd      t1, 32(s6)
    addi    a0, s6, 40
    addi    a1, t2, BeaconBlockHeader_parent_root
    li      a2, 32
    call    lantern_copy
    ADDQ    a1, s4, BeaconState_latest_block_header + BeaconBlockHeader_state_root
    ld      t0, 0(a1)                       # state_root: the header's, or hash_tree_root of the state
    ld      t1, 8(a1)
    or      t0, t0, t1
    ld      t1, 16(a1)
    or      t0, t0, t1
    ld      t1, 24(a1)
    or      t0, t0, t1
    beqz    t0, 1f
    addi    a0, s6, 72
    li      a2, 32
    call    lantern_copy
    j       2f
1:  ADDRESS a0, lantern_type_BeaconState
    mv      a1, s4
    mv      a2, s3
    addi    a3, s6, 72
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 8f
2:  li      t0, 84                          # the body's offset, then the default body
    sw      t0, (24 + 80)(s6)
    ADDRESS a0, lantern_type_BeaconBlockBody
    ld      a1, SSZ_DESC_ROOT(a0)
    addi    a2, s6, 24 + 84
    call    node_ssz_default
    ADDRESS a0, lantern_type_BeaconBlock
    mv      a1, s6
    mv      a2, s3
    mv      a3, s5
    CALL_GLOBAL ssz_deserialize
    bnez    a0, 8f
    PART    a1, t0, s5, BeaconBlock_body    # the default body must be the header's
    ADDRESS a0, lantern_type_BeaconBlockBody
    mv      a2, s3
    addi    a3, sp, L + 16
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 8f
    ADDQ    t0, s4, BeaconState_latest_block_header + BeaconBlockHeader_body_root
    addi    t1, sp, L + 16
    li      t2, 0
    li      t5, 32
3:  add     t3, t0, t2
    ld      t3, 0(t3)
    add     t4, t1, t2
    ld      t4, 0(t4)
    bne     t3, t4, 6f
    addi    t2, t2, 8
    bltu    t2, t5, 3b
    li      a0, LANTERN_OK
    j       99f
6:  li      a0, LANTERN_INVALID_ANCHOR
    j       99f
7:  li      a0, LANTERN_INVALID_ENCODING
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
99: sd      s8, 0(s3)
    LEAVE 48
SPEC_END node_anchor

/*
 * (data, room, scratch, state, block): the anchor of a start from the node's own history: data
 * holds two ByteLists, the second at the first multiple of 8 after the first: the SSZ bytes of a
 * BeaconState, then those of the message of its block, with the state's slot and root. state:
 * the state with room; block: the message. s1 data's bytes, s2 room, s3 scratch, s4 state, s5
 * block, s6 the decoded state, then the block's ByteList, s7 their count, s8 the scratch size,
 * restored on return, s10 the block's place. Locals: L a size, L+16 a root.
 */
SPEC_FUNCTION node_anchor_block
    ENTER 48
    ld      t0, 8(a0)
    add     s1, a0, t0
    ld      s7, 16(a0)
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      s8, 0(s3)
    li      t0, 24                          # the state's ByteList: offset 24, size 24 + count, inside
    bltu    s7, t0, 7f
    ld      t1, 8(s1)
    bne     t1, t0, 7f
    ld      t1, 16(s1)
    bgtu    t1, s7, 7f
    addi    t1, t1, 24
    ld      t2, 0(s1)
    bne     t1, t2, 7f
    bgtu    t1, s7, 7f
    addi    s10, t1, 7
    andi    s10, s10, -8
    ADDRESS a0, lantern_type_BeaconState    # decoded, then copied with room
    mv      a1, s1
    mv      a2, s3
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 7f
    mv      s6, a1
    mv      a0, s6
    mv      a1, s2
    addi    a2, sp, L
    call    lantern_beacon_state_copy_size
    ld      t0, L(sp)
    ld      t1, 0(s4)
    bltu    t1, t0, 8f
    mv      a0, s6
    mv      a1, s2
    mv      a2, s4
    call    lantern_beacon_state_copy
    bnez    a0, 8f
    sd      s8, 0(s3)
    addi    t0, s10, 24                     # the block's ByteList, the same way
    bgtu    t0, s7, 7f
    add     s6, s1, s10
    sub     t3, s7, s10
    ld      t1, 8(s6)
    li      t0, 24
    bne     t1, t0, 7f
    ld      t1, 16(s6)
    bgtu    t1, t3, 7f
    addi    t1, t1, 24
    ld      t2, 0(s6)
    bne     t1, t2, 7f
    bgtu    t1, t3, 7f
    ADDRESS a0, lantern_type_BeaconBlock
    mv      a1, s6
    mv      a2, s3
    mv      a3, s5
    CALL_GLOBAL ssz_deserialize
    sd      s8, 0(s3)
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    bnez    a0, 7f
    ld      t0, BeaconBlock_slot(s5)        # its slot and state_root are the state's
    ld      t1, NODE_STATE_SLOT(s4)
    bne     t0, t1, 6f
    ADDRESS a0, lantern_type_BeaconState
    mv      a1, s4
    mv      a2, s3
    addi    a3, sp, L + 16
    CALL_GLOBAL ssz_hash_tree_root
    sd      s8, 0(s3)
    bnez    a0, 8f
    li      t2, 0
3:  add     t0, s5, t2
    ld      t0, BeaconBlock_state_root(t0)
    add     t1, sp, t2
    ld      t1, (L + 16)(t1)
    bne     t0, t1, 6f
    addi    t2, t2, 8
    li      t3, 32
    bltu    t2, t3, 3b
    li      a0, LANTERN_OK
    j       99f
6:  li      a0, LANTERN_INVALID_ANCHOR
    j       99f
7:  li      a0, LANTERN_INVALID_ENCODING
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
99: sd      s8, 0(s3)
    LEAVE 48
SPEC_END node_anchor_block

/*
 * (state, scratch, out, size): size: the bytes of a ByteList of the state's SSZ bytes, 24 + their
 * count; out: that ByteList, when its size field holds at least size. s1 state, s2 scratch, s3
 * out, s4 size, s5 the scratch size, restored on return.
 */
SPEC_FUNCTION node_state_bytes
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      s5, 0(s2)
    ADDRESS a0, lantern_type_BeaconState
    mv      a1, s1
    mv      a2, s2
    mv      a3, s4
    CALL_GLOBAL ssz_serialize_size
    sd      s5, 0(s2)
    bnez    a0, 8f
    ld      t0, 0(s4)
    ld      t1, 0(s3)
    bltu    t1, t0, 8f
    ADDRESS a0, lantern_type_BeaconState
    mv      a1, s1
    mv      a2, s2
    mv      a3, s3
    CALL_GLOBAL ssz_serialize
    sd      s5, 0(s2)
    bnez    a0, 8f
    li      a0, LANTERN_OK
    LEAVE 0
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END node_state_bytes

/* (pre, room, config, scratch, out): upgrade_to_<fork> of the object's fork; phase0 has none. */
SPEC_FUNCTION node_upgrade
    ENTER 0
.if FORK == FORK_ALTAIR
    call    lantern_upgrade_to_altair
.elseif FORK == FORK_BELLATRIX
    call    lantern_upgrade_to_bellatrix
.elseif FORK == FORK_CAPELLA
    call    lantern_upgrade_to_capella
.elseif FORK == FORK_DENEB
    call    lantern_upgrade_to_deneb
.elseif FORK == FORK_ELECTRA
    call    lantern_upgrade_to_electra
.elseif FORK == FORK_FULU
    call    lantern_upgrade_to_fulu
.else
    li      a0, LANTERN_INVALID_SLOT
.endif
    LEAVE 0
SPEC_END node_upgrade

/*
 * (data, state, config, scratch, result): the post-state again of a block the node imported:
 * state_transition of the SignedBeaconBlock in data with validate_result 0 and slots_done 1.
 * s1 data, s2 state, s3 config, s4 scratch, s5 result, s10 the scratch size. Locals: L
 * TransitionOptions.
 */
SPEC_FUNCTION node_replay
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      s10, 0(s4)
    sd      zero, 0(s5)
    ADDRESS a0, lantern_type_SignedBeaconBlock
    mv      a1, s1
    mv      a2, s4
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 9f
    sd      zero, L(sp)                     # validate_result 0, execution_valid 1, slots_done 1
    sd      t0, (L + 8)(sp)
    sd      t0, (L + 16)(sp)
    mv      a0, s2
    addi    a2, sp, L
    mv      a3, s3
    mv      a4, s4
    mv      a5, s5
    call    lantern_state_transition
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    j       99f
9:  li      t0, LANTERN_INVALID_ENCODING
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
99: sd      s10, 0(s4)
    LEAVE 32
SPEC_END node_replay

/*
 * (data, state, config, root, scratch, result): the proposer signature of the block in data, of
 * any fork, with the validators of state and the fork version of the block's epoch (node.md,
 * lantern_node_backfill). s1 data, s2 state, s3 config, s4 root, s5 scratch, s6 result, s7 the
 * block's bytes, s8 the validator. Locals: L the epoch, L+8 the fork version, L+16 the domain type,
 * L+24 a ByteList header, L+48 the signing root, L+80 the root, L+112 the domain.
 */
SPEC_FUNCTION node_backfill
    ENTER 144
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    ld      t0, 16(s1)
    li      t1, 100 + 84
    bltu    t0, t1, 7f
    ld      t0, 8(s1)
    add     s7, s1, t0
    LDU64   t0, s7, 100, t1                 # the genesis block has no proposer
    beqz    t0, 5f
    LDU64   t2, s7, 108, t1
    PART    t3, t4, s2, BeaconState_validators
    bgeu    t2, t4, 6f
    slli    t2, t2, 7
    add     s8, t3, t2
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    sd      t0, L(sp)
    addi    a0, sp, L                       # compute_fork_version(the block's epoch)
    mv      a1, s3
    addi    a2, sp, L + 8
    call    lantern_compute_fork_version
    li      t0, DOMAIN_BEACON_PROPOSER
    sw      t0, (L + 16)(sp)
    addi    a0, sp, L + 16
    addi    a1, sp, L + 8
    ADDQ    a2, s2, BeaconState_genesis_validators_root
    mv      a3, s5
    addi    a4, sp, L + 112
    call    lantern_compute_domain
    bnez    a0, 99f
    addi    t0, sp, L + 80                  # compute_signing_root: hash_tree_root(SigningData(root, domain))
    COPY32  t0, s4
    addi    a0, sp, L + 80
    li      a1, 64
    addi    a2, sp, L + 48
    call    sha256_short
    addi    a0, s8, Validator_pubkey
    addi    a1, s7, 4
    addi    a2, sp, L + 24
    mv      a3, s5
    call    verify_root_signature
    bnez    a0, 99f
    beqz    a1, 8f
5:  sd      zero, 0(s6)                     # LANTERN_VALID
    li      a0, LANTERN_OK
    j       99f
6:  li      t0, LANTERN_INVALID_PROPOSER_INDEX
    j       9f
7:  li      t0, LANTERN_INVALID_ENCODING
    j       9f
8:  li      t0, LANTERN_INVALID_BLOCK_SIGNATURE
9:  sd      t0, 0(s6)
    li      a0, LANTERN_OK
99: LEAVE 144
SPEC_END node_backfill

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

/*
 * (state a0, epoch a1, out a2) -> a0: get_randao_mix of the epoch (2^64 - 1: the state's epoch)
 * when the state holds it, from the state's epoch - EPOCHS_PER_HISTORICAL_VECTOR + 1 to its epoch;
 * else LANTERN_NO_STATE_ANSWER (node.md, lantern_node_randao).
 */
SPEC_FUNCTION node_randao
    FRAME 0
    LDQ     t0, a0, BeaconState_slot
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    li      t1, -1
    bne     a1, t1, 1f
    mv      a1, t0
1:  bgtu    a1, t0, 8f
    sub     t1, t0, a1
    li      t2, EPOCHS_PER_HISTORICAL_VECTOR
    bgeu    t1, t2, 8f
    addi    t2, t2, -1
    and     t1, a1, t2
    slli    t1, t1, 5
    ADDQ    t0, a0, BeaconState_randao_mixes
    add     a1, t0, t1
    mv      a0, a2
    li      a2, 32
    call    lantern_copy
    li      a0, LANTERN_OK
    UNFRAME 0
8:  li      a0, LANTERN_NO_STATE_ANSWER
    UNFRAME 0
SPEC_END node_randao

/*
 * (store, scratch, out) -> status: get_weight of each node of the store, in node order, a u64 a
 * node at out, as lantern_get_head computes them all at once (node.md, lantern_node_weights).
 * s1 store, s2 scratch, s3 out, s4 node count, s5 the flags at the end of scratch.
 */
SPEC_FUNCTION node_weights
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    NEED_BALANCES s1, 8f
    ld      s4, (Store_blocks + 8)(s1)
    ld      t0, 0(s2)
    slli    t1, s4, 3
    li      t2, LANTERN_SCRATCH_FIXED
    add     t2, t2, t1
    bltu    t0, t2, 9f
    sub     t0, t0, t1
    add     s5, s2, t0
    mv      a0, s5
    mv      a1, t1
    call    lantern_zero
    mv      a0, s1
    mv      a1, s3
    mv      a2, s5
    call    weights
    bnez    a0, 7f
    li      t0, 0                           # a sum past 2^64 - 1
1:  bgeu    t0, s4, 7f
    slli    t1, t0, 3
    add     t1, s5, t1
    ld      t1, 0(t1)
    addi    t0, t0, 1
    andi    t1, t1, F_OVERFLOW
    beqz    t1, 1b
    li      a0, LANTERN_INVALID_OVERFLOW
7:  LEAVE 0
8:  li      a0, LANTERN_NEED_JUSTIFIED_STATE
    LEAVE 0
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END node_weights
.if EPOCHS_PER_HISTORICAL_VECTOR & (EPOCHS_PER_HISTORICAL_VECTOR - 1)
.error "lantern_node_randao takes EPOCHS_PER_HISTORICAL_VECTOR as a power of two"
.endif

/*
 * (state a0, epoch a1, scratch a2, out a3) -> a0: the index of each member of the state's sync
 * committee of the epoch (2^64 - 1: the state's epoch), current_sync_committee for the period of
 * the state's epoch, next_sync_committee for the next, by find_pubkeys with its table at the end
 * of scratch (node.md, lantern_node_sync_committee). Before altair, or another period:
 * LANTERN_NO_STATE_ANSWER.
 */
SPEC_FUNCTION node_sync_committee
    FRAME 0
.if FORK >= FORK_ALTAIR
    LDQ     t0, a0, BeaconState_slot
    srli    t0, t0, LOG2_SLOTS_PER_EPOCH
    li      t1, -1
    bne     a1, t1, 1f
    mv      a1, t0
1:  li      t2, EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    divu    t0, t0, t2
    divu    t1, a1, t2
    li      t3, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    beq     t1, t0, 2f
    addi    t0, t0, 1
    bne     t1, t0, 8f
    li      t3, BeaconState_next_sync_committee + SyncCommittee_pubkeys
2:  ld      t0, 0(a2)                       # the key table at the end of scratch
    li      t1, SYNC_TABLE_BYTES + 24
    bltu    t0, t1, 9f
    sub     t0, t0, t1
    add     t4, a2, t0
    add     a1, a0, t3
    mv      a2, a3
    mv      a3, t4
    call    find_pubkeys
    bnez    a0, 7f
    li      a0, LANTERN_OK
    UNFRAME 0
7:  li      a0, LANTERN_INVALID_ENCODING
    UNFRAME 0
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    UNFRAME 0
8:
.endif
    li      a0, LANTERN_NO_STATE_ANSWER
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
 * (block a0, scratch a1, out a2) -> a0: the SSZ bytes of the SignedBlindedBeaconBlock of the
 * SignedBeaconBlock in the ByteList block, in the ByteList out (node.md,
 * lantern_node_blinded_block); before bellatrix the bytes of block. s1 the block's bytes, s2 their
 * count, s3 out, s4 the body's place in them, s5 scratch, s6 the payload's place, s7 the payload's
 * value, s8 the payload's end, s9 the scratch's size after the decoded block (s5, s7 and s9 as
 * build_payload_header takes them). Locals: L the scratch's size, L+8 the header's SSZ ByteList,
 * L+16 block, L+24 the header's bytes less the payload's, L+40 the header's value.
 */
SPEC_FUNCTION node_blinded_block
    ENTER 48
    sd      a0, (L + 16)(sp)
    ld      t0, 8(a0)
    add     s1, a0, t0
    ld      s2, 16(a0)
    mv      s3, a2
    mv      s5, a1
    ld      t0, 0(s5)
    sd      t0, L(sp)
.if FORK < FORK_BELLATRIX
    ld      t0, 0(s3)                       # before bellatrix: the block's bytes
    addi    t1, s2, 24
    bgtu    t1, t0, 8f
    li      t0, 24
    sd      t0, 8(s3)
    sd      s2, 16(s3)
    addi    a0, s3, 24
    mv      a1, s1
    mv      a2, s2
    call    lantern_copy
    j       7f
.else
    li      t0, 100                         # the message at the offset at byte 0, its body at the offset in it
    bltu    s2, t0, 91f
    lwu     t0, 0(s1)
    addi    t1, t0, 84
    bgtu    t1, s2, 91f
    add     t1, s1, t0
    lwu     t2, BeaconBlock_body__ssz(t1)
    add     s4, t0, t2
    li      t1, BLINDED_BODY_OFFSETS_END
    add     t1, s4, t1
    bgtu    t1, s2, 91f
    add     t1, s1, s4                      # the payload: from its offset to the next field's, else to the end
    lwu     t2, BeaconBlockBody_execution_payload__ssz(t1)
    add     s6, s4, t2
.if FORK >= FORK_CAPELLA
    lwu     t2, BeaconBlockBody_bls_to_execution_changes__ssz(t1)
    add     s8, s4, t2
.else
    mv      s8, s2
.endif
    bgtu    s6, s8, 91f
    bgtu    s8, s2, 91f
    ADDRESS a0, lantern_type_SignedBeaconBlock  # the decoded block's payload
    ld      a1, (L + 16)(sp)
    mv      a2, s5
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 91f
    PART    t1, t2, a1, SignedBeaconBlock_message
    PART    t3, t2, t1, BeaconBlock_body
    PART    s7, t2, t3, BeaconBlockBody_execution_payload
    ld      s9, 0(s5)                       # its header, as process_execution_payload builds it
    TX_BYTES t1, s7, t2
    li      t2, LANTERN_SCRATCH_FIXED + HEADER_ROOM + 24 + PAYLOAD_WLIST_BYTES + 1024
    add     t1, t1, t2
    bltu    s9, t1, 8f
    li      t0, HEADER_ROOM
    sub     t0, s9, t0
    add     a0, s5, t0
    sd      a0, (L + 40)(sp)
    call    build_payload_header
    bnez    a0, 6f
    ld      t0, (L + 40)(sp)                # its SSZ bytes, in a ByteList of 1024 bytes below it
    sub     t0, t0, s5
    addi    t0, t0, -1024
    add     a3, s5, t0
    li      t1, 1024
    sd      t1, 0(a3)
    sd      a3, (L + 8)(sp)
    sd      t0, 0(s5)
    ADDRESS a0, lantern_type_ExecutionPayloadHeader
    ld      a1, (L + 40)(sp)
    mv      a2, s5
    CALL_GLOBAL ssz_serialize
    bnez    a0, 6f
    ld      t0, (L + 8)(sp)                 # out: the block's bytes to the payload, the header's, the block's after the payload
    ld      t1, 16(t0)
    sub     t2, s8, s6
    sub     t3, t1, t2
    sd      t3, (L + 24)(sp)
    add     t4, s2, t3
    ld      t5, 0(s3)
    addi    t6, t4, 24
    bgtu    t6, t5, 8f
    li      t5, 24
    sd      t5, 8(s3)
    sd      t4, 16(s3)
    addi    a0, s3, 24
    mv      a1, s1
    mv      a2, s6
    call    lantern_copy
    ld      t0, (L + 8)(sp)
    addi    a0, s3, 24
    add     a0, a0, s6
    ld      t1, 8(t0)
    add     a1, t0, t1
    ld      a2, 16(t0)
    call    lantern_copy
    ld      t0, (L + 8)(sp)
    ld      t0, 16(t0)
    addi    a0, s3, 24
    add     a0, a0, s6
    add     a0, a0, t0
    add     a1, s1, s8
    sub     a2, s2, s8
    call    lantern_copy
.if FORK >= FORK_CAPELLA
    ld      t3, (L + 24)(sp)                # the offsets after the payload's grow by the header's bytes less the payload's
    addi    t0, s3, 24
    add     t0, t0, s4
    lwu     t1, BeaconBlockBody_bls_to_execution_changes__ssz(t0)
    addw    t1, t1, t3
    sw      t1, BeaconBlockBody_bls_to_execution_changes__ssz(t0)
.if FORK >= FORK_DENEB
    lwu     t1, BeaconBlockBody_blob_kzg_commitments__ssz(t0)
    addw    t1, t1, t3
    sw      t1, BeaconBlockBody_blob_kzg_commitments__ssz(t0)
.endif
.if FORK >= FORK_ELECTRA
    lwu     t1, BeaconBlockBody_execution_requests__ssz(t0)
    addw    t1, t1, t3
    sw      t1, BeaconBlockBody_execution_requests__ssz(t0)
.endif
.endif
.endif
7:  ld      t0, L(sp)
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 48
6:  li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
91: ld      t0, L(sp)
    sd      t0, 0(s5)
    li      a0, LANTERN_INVALID_ENCODING
    LEAVE 48
8:  ld      t0, L(sp)
    sd      t0, 0(s5)
    li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END node_blinded_block

/*
 * (state a0, kind a1, out a2) -> a0: the address of the first item, the count and the bytes of an
 * item of the state's pending_deposits (kind 0), pending_partial_withdrawals (1) or
 * pending_consolidations (2); before electra LANTERN_NO_STATE_ANSWER (node.md, lantern_node_pending).
 */
SPEC_FUNCTION node_pending
    FRAME 0
.if FORK >= FORK_ELECTRA
    li      t0, 1
    beq     a1, t0, 1f
    bgtu    a1, t0, 2f
    PART    t1, t2, a0, BeaconState_pending_deposits
    li      t3, PendingDeposit__mem
    j       5f
1:  PART    t1, t2, a0, BeaconState_pending_partial_withdrawals
    li      t3, PendingPartialWithdrawal__mem
    j       5f
2:  li      t0, 2
    bne     a1, t0, 8f
    PART    t1, t2, a0, BeaconState_pending_consolidations
    li      t3, PendingConsolidation__mem
5:  sd      t1, 0(a2)
    sd      t2, 8(a2)
    sd      t3, 16(a2)
    li      a0, LANTERN_OK
    UNFRAME 0
8:
.endif
    li      a0, LANTERN_NO_STATE_ANSWER
    UNFRAME 0
SPEC_END node_pending
.if FORK >= FORK_ELECTRA
.if PendingDeposit__mem != 192 || PendingPartialWithdrawal__mem != 24 || PendingConsolidation__mem != 16
.error "lantern_node_pending: an item is its SSZ encoding"
.endif
.endif

/*
 * (state a0, out a1) -> a0: the state's proposer_lookahead, (MIN_SEED_LOOKAHEAD + 1) *
 * SLOTS_PER_EPOCH u64; before fulu LANTERN_NO_STATE_ANSWER (node.md, lantern_node_proposer_lookahead).
 */
SPEC_FUNCTION node_proposer_lookahead
    FRAME 0
.if FORK >= FORK_FULU
    mv      t0, a1
    ADDQ    a1, a0, BeaconState_proposer_lookahead
    mv      a0, t0
    li      a2, 8 * API_LOOKAHEAD_SLOTS
    call    lantern_copy
    li      a0, LANTERN_OK
.else
    li      a0, LANTERN_NO_STATE_ANSWER
.endif
    UNFRAME 0
SPEC_END node_proposer_lookahead

/*
 * a0 = a status: in the root s5 of lantern_node_gossip for the valid beacon_attestation s2, its
 * data.slot, its committee index, its member and 0 (node.md): from electra, the member is the
 * place of attester_index in lantern_get_beacon_committee of the head state of the args s1, +
 * 2^16 times the committee's length, the committee a list at the end of the scratch s3; before
 * electra, 0. s7 the list, s8 the scratch's size. Locals: L the slot, L+8 the index.
 */
LOCAL_FUNCTION node_gossip_member
    ENTER 16
.if FORK >= FORK_ELECTRA
    ld      t0, (SingleAttestation_data + AttestationData_slot)(s2)
    ld      t1, SingleAttestation_committee_index(s2)
.else
    ld      t0, (Attestation_data + AttestationData_slot)(s2)
    ld      t1, (Attestation_data + AttestationData_index)(s2)
.endif
    sd      t0, 0(s5)
    sd      t1, 8(s5)
    sd      zero, 16(s5)
    sd      zero, 24(s5)
.if FORK >= FORK_ELECTRA
    sd      t0, L(sp)
    sd      t1, (L + 8)(sp)
    ld      s8, 0(s3)                       # the committee's list at the end of scratch
    li      t2, LIST_FIXED + 8 * MAX_VALIDATORS_PER_COMMITTEE
    bltu    s8, t2, 8f
    sub     t3, s8, t2
    sd      t3, 0(s3)
    add     s7, s3, t3
    sd      t2, 0(s7)
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s7)
    sd      zero, LIST_COUNT(s7)
    ld      a0, NodeGossip_head(s1)
    addi    a1, sp, L
    addi    a2, sp, L + 8
    ld      a3, NodeGossip_config(s1)
    ld      a3, CONFIG_COMMITTEE_CACHE(a3)
    mv      a4, s3
    mv      a5, s7
    call    lantern_get_beacon_committee
    sd      s8, 0(s3)
    bnez    a0, 9f
    ld      t0, LIST_OFFSET(s7)             # the attester's place
    add     t0, s7, t0
    ld      t1, LIST_COUNT(s7)
    ld      t2, SingleAttestation_attester_index(s2)
    li      t3, 0
1:  bgeu    t3, t1, 7f
    slli    t4, t3, 3
    add     t4, t0, t4
    ld      t4, 0(t4)
    beq     t4, t2, 2f
    addi    t3, t3, 1
    j       1b
2:  slli    t1, t1, 16
    or      t3, t3, t1
    sd      t3, 16(s5)
.endif
7:  li      a0, LANTERN_OK
9:  LEAVE 16
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION node_gossip_member

/*
 * (args, data, scratch, result, root, index): the gossip validation of the topic args.topic for
 * the message in data, decoded with the fork's type. For beacon_block, blob_sidecar and
 * data_column_sidecar the proposer state first gets process_slots to the message's slot. A valid
 * beacon_block gives its root and blob count; a valid blob_sidecar the root of its block header
 * and its index. s1 args, s2 the message, s3 scratch, s4 result, s5 root, s6 the topic, s7 the
 * slot, s8 the proposer state, s9 index, s10 the scratch size, restored on return.
 * Locals: L the arguments past the eighth, L+16 a slot, L+24 a result.
 */
SPEC_FUNCTION node_gossip
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s9, a5
    ld      s10, 0(s3)
    sd      zero, 0(s4)
    sd      zero, 0(s9)
    ld      s6, NodeGossip_topic(s1)
    ADDRESS a0, lantern_type_SignedBeaconBlock     # the type of the topic
    li      t0, GOSSIP_BEACON_BLOCK
    beq     s6, t0, 1f
    ADDRESS a0, lantern_type_SignedAggregateAndProof
    li      t0, GOSSIP_BEACON_AGGREGATE_AND_PROOF
    beq     s6, t0, 1f
.if FORK >= FORK_ELECTRA
    ADDRESS a0, lantern_type_SingleAttestation
.else
    ADDRESS a0, lantern_type_Attestation
.endif
    li      t0, GOSSIP_BEACON_ATTESTATION
    beq     s6, t0, 1f
    ADDRESS a0, lantern_type_SignedVoluntaryExit
    li      t0, GOSSIP_VOLUNTARY_EXIT
    beq     s6, t0, 1f
    ADDRESS a0, lantern_type_ProposerSlashing
    li      t0, GOSSIP_PROPOSER_SLASHING
    beq     s6, t0, 1f
    ADDRESS a0, lantern_type_AttesterSlashing
    li      t0, GOSSIP_ATTESTER_SLASHING
    beq     s6, t0, 1f
.if FORK >= FORK_ALTAIR
    ADDRESS a0, lantern_type_SignedContributionAndProof
    li      t0, GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF
    beq     s6, t0, 1f
    ADDRESS a0, lantern_type_SyncCommitteeMessage
    li      t0, GOSSIP_SYNC_COMMITTEE
    beq     s6, t0, 1f
.endif
.if FORK >= FORK_CAPELLA
    ADDRESS a0, lantern_type_SignedBLSToExecutionChange
    li      t0, GOSSIP_BLS_TO_EXECUTION_CHANGE
    beq     s6, t0, 1f
.endif
.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    ADDRESS a0, lantern_type_BlobSidecar
    li      t0, GOSSIP_BLOB_SIDECAR
    beq     s6, t0, 1f
.endif
.if FORK >= FORK_FULU
    ADDRESS a0, lantern_type_DataColumnSidecar
    li      t0, GOSSIP_DATA_COLUMN_SIDECAR
    beq     s6, t0, 1f
.endif
    li      t0, LANTERN_GOSSIP_IGNORE       # a topic of no type in this fork
    sd      t0, 0(s4)
    li      a0, LANTERN_OK
    j       99f
1:  mv      a1, s2
    mv      a2, s3
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 7f
    mv      s2, a1
    ld      s8, NodeGossip_proposer(s1)     # the proposer state at the message's slot
    beqz    s8, 20f
    li      t0, GOSSIP_BEACON_BLOCK
    bne     s6, t0, 11f
    PART    t0, t1, s2, SignedBeaconBlock_message
    ld      s7, BeaconBlock_slot(t0)
    j       14f
11:
.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    li      t0, GOSSIP_BLOB_SIDECAR
    bne     s6, t0, 12f
    LDQ     s7, s2, BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot
    j       14f
12:
.endif
.if FORK >= FORK_FULU
    li      t0, GOSSIP_DATA_COLUMN_SIDECAR
    bne     s6, t0, 13f
    LDQ     s7, s2, DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot
    j       14f
13:
.endif
    j       20f
14: ld      t0, NODE_STATE_SLOT(s8)
    bgeu    t0, s7, 20f
    sd      s7, (L + 16)(sp)
    mv      a0, s8
    addi    a1, sp, L + 16
    ld      a2, NodeGossip_config(s1)
    mv      a3, s3
    addi    a4, sp, L + 24
    call    lantern_process_slots
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    bnez    a0, 99f
    ld      t0, (L + 24)(sp)
    beqz    t0, 20f
    li      t0, LANTERN_GOSSIP_IGNORE       # the slots do not run: no answer of the spec
    sd      t0, 0(s4)
    j       99f
20: ld      a0, NodeGossip_seen(s1)         # the check of the topic
    ld      a1, NodeGossip_store(s1)
    mv      a2, s2
    addi    a3, s1, NodeGossip_time_ms
    ld      t2, NodeGossip_head(s1)
    bnez    s8, 21f
    mv      s8, t2
21: li      t0, GOSSIP_BEACON_BLOCK
    bne     s6, t0, 30f
    mv      a4, t2
    mv      a5, s8
.if FORK == FORK_BELLATRIX
    ld      a6, NodeGossip_justified(s1)
    bnez    a6, 22f
    mv      a6, t2
22: mv      a7, s3
    sd      s4, L(sp)
.else
    mv      a6, s3
    mv      a7, s4
.endif
    call    lantern_validate_beacon_block_gossip
    bnez    a0, 98f
    ld      t0, 0(s4)                       # a valid block: its root and blob count
    bnez    t0, 99f
    PART    a1, t0, s2, SignedBeaconBlock_message
.if FORK >= FORK_DENEB
    PART    t0, t1, a1, BeaconBlock_body
    LDQ     t1, t0, BeaconBlockBody_blob_kzg_commitments + 8
    sd      t1, 0(s9)
.endif
    ADDRESS a0, lantern_type_BeaconBlock
    mv      a2, s3
    mv      a3, s5
    CALL_GLOBAL ssz_hash_tree_root
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    j       99f
30: li      t0, GOSSIP_BEACON_AGGREGATE_AND_PROOF
    bne     s6, t0, 31f
    mv      a4, t2
    mv      a5, s3
    mv      a6, s4
    call    lantern_validate_beacon_aggregate_and_proof_gossip
    j       98f
31: li      t0, GOSSIP_BEACON_ATTESTATION
    bne     s6, t0, 32f
    addi    a4, s1, NodeGossip_subnet
    mv      a5, t2
    mv      a6, s3
    mv      a7, s4
    call    lantern_validate_beacon_attestation_gossip
    bnez    a0, 98f
    ld      t0, 0(s4)                       # a valid attestation: its slot, committee index and member
    bnez    t0, 99f
    call    node_gossip_member
    j       98f
32: li      t0, GOSSIP_VOLUNTARY_EXIT
    bne     s6, t0, 33f
    mv      a4, t2
    mv      a5, s3
    mv      a6, s4
    call    lantern_validate_voluntary_exit_gossip
    j       98f
33: li      t0, GOSSIP_PROPOSER_SLASHING
    bne     s6, t0, 34f
    mv      a3, t2
    mv      a4, s3
    mv      a5, s4
    call    lantern_validate_proposer_slashing_gossip
    j       98f
34: li      t0, GOSSIP_ATTESTER_SLASHING
    bne     s6, t0, 35f
    mv      a3, t2
    mv      a4, s3
    mv      a5, s4
    call    lantern_validate_attester_slashing_gossip
    j       98f
35:
.if FORK >= FORK_ALTAIR
    li      t0, GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF
    bne     s6, t0, 36f
    mv      a4, t2
    mv      a5, s3
    mv      a6, s4
    call    lantern_validate_sync_committee_contribution_and_proof_gossip
    j       98f
36: li      t0, GOSSIP_SYNC_COMMITTEE
    bne     s6, t0, 37f
    addi    a4, s1, NodeGossip_subnet
    mv      a5, t2
    mv      a6, s3
    mv      a7, s4
    call    lantern_validate_sync_committee_message_gossip
    bnez    a0, 98f
    ld      t0, 0(s4)                       # a valid message: its slot and its subnet's bit
    bnez    t0, 99f
    ld      t0, SyncCommitteeMessage_slot(s2)
    sd      t0, 0(s5)
    ld      t1, NodeGossip_subnet(s1)
    li      t0, 1
    sll     t0, t0, t1
    sd      t0, 8(s5)
    sd      zero, 16(s5)
    sd      zero, 24(s5)
    j       99f
37:
.endif
.if FORK >= FORK_CAPELLA
    li      t0, GOSSIP_BLS_TO_EXECUTION_CHANGE
    bne     s6, t0, 38f
    mv      a4, t2
    mv      a5, s3
    mv      a6, s4
    call    lantern_validate_bls_to_execution_change_gossip
    j       98f
38:
.endif
.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
    li      t0, GOSSIP_BLOB_SIDECAR
    bne     s6, t0, 39f
    addi    a4, s1, NodeGossip_subnet
    mv      a5, t2
    mv      a6, s8
    ld      a7, NodeGossip_settings(s1)
    sd      s3, L(sp)
    sd      s4, (L + 8)(sp)
    call    lantern_validate_blob_sidecar_gossip
    bnez    a0, 98f
    ld      t0, 0(s4)                       # a valid sidecar: the root of its block header, its index
    bnez    t0, 99f
    ld      t0, BlobSidecar_index(s2)
    sd      t0, 0(s9)
    ADDRESS a0, lantern_type_BeaconBlockHeader
    ADDQ    a1, s2, BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message
    mv      a2, s3
    mv      a3, s5
    CALL_GLOBAL ssz_hash_tree_root
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    j       99f
39:
.endif
.if FORK >= FORK_FULU
    li      t0, GOSSIP_DATA_COLUMN_SIDECAR
    bne     s6, t0, 40f
    addi    a4, s1, NodeGossip_subnet
    mv      a5, t2
    mv      a6, s8
    ld      a7, NodeGossip_settings(s1)
    sd      s3, L(sp)
    sd      s4, (L + 8)(sp)
    call    lantern_validate_data_column_sidecar_gossip
    bnez    a0, 98f
    ld      t0, 0(s4)                       # a valid sidecar: the root of its block header, its index
    bnez    t0, 99f
    ld      t0, DataColumnSidecar_index(s2)
    sd      t0, 0(s9)
    ADDRESS a0, lantern_type_BeaconBlockHeader
    ADDQ    a1, s2, DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message
    mv      a2, s3
    mv      a3, s5
    CALL_GLOBAL ssz_hash_tree_root
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    j       99f
40:
.endif
    li      t0, LANTERN_GOSSIP_IGNORE
    sd      t0, 0(s4)
    li      a0, LANTERN_OK
    j       99f
98: li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    j       99f
7:  li      t0, LANTERN_GOSSIP_REJECT       # no SSZ encoding of the type
    sd      t0, 0(s4)
    li      a0, LANTERN_OK
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
99: sd      s10, 0(s3)
    LEAVE 32
SPEC_END node_gossip

.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
/*
 * (data, config, settings, scratch, result, root): the checks a reader of a blob sidecar response
 * makes: the index below the fork's limit, verify_blob_sidecar_inclusion_proof and
 * verify_blob_kzg_proof; then hash_tree_root of its block header. s1 config, s2 the sidecar,
 * s3 scratch, s4 result, s5 root, s6 settings, s10 the scratch size, restored on return.
 * Locals: L an out.
 */
SPEC_FUNCTION node_blob_sidecar
    ENTER 16
    mv      s2, a0
    mv      s1, a1
    mv      s6, a2
    mv      s3, a3
    mv      s4, a4
    mv      s5, a5
    ld      s10, 0(s3)
    sd      zero, 0(s4)
    ADDRESS a0, lantern_type_BlobSidecar
    mv      a1, s2
    mv      a2, s3
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 9f
    mv      s2, a1
    ld      t0, BlobSidecar_index(s2)       # the index is below the blob limit
.if FORK == FORK_ELECTRA
    LDQ     t1, s1, CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
.else
    LDQ     t1, s1, CONFIG_MAX_BLOBS_PER_BLOCK
.endif
    bgeu    t0, t1, 6f
    mv      a0, s2                          # verify_blob_sidecar_inclusion_proof
    addi    a1, sp, L
    call    lantern_verify_blob_sidecar_inclusion_proof
    bnez    a0, 99f
    ld      t0, L(sp)
    beqz    t0, 6f
    mv      a0, s6                          # verify_blob_kzg_proof(blob, kzg_commitment, kzg_proof)
    ADDQ    a1, s2, BlobSidecar_blob
    ADDQ    a2, s2, BlobSidecar_kzg_commitment
    ADDQ    a3, s2, BlobSidecar_kzg_proof
    mv      a4, s3
    addi    a5, sp, L
    CALL_GLOBAL crypto_kzg_verify_blob_kzg_proof
    li      t0, CRYPTO_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    bnez    a0, 6f                          # an input that does not decode
    ld      t0, L(sp)
    beqz    t0, 6f
    ADDRESS a0, lantern_type_BeaconBlockHeader
    ADDQ    a1, s2, BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message
    mv      a2, s3
    mv      a3, s5
    CALL_GLOBAL ssz_hash_tree_root
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    j       99f
6:  li      t0, LANTERN_INVALID_BLOB_SIDECAR
    sd      t0, 0(s4)
    li      a0, LANTERN_OK
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    j       99f
9:  li      t0, LANTERN_INVALID_ENCODING
    sd      t0, 0(s4)
    li      a0, LANTERN_OK
99: sd      s10, 0(s3)
    LEAVE 16
SPEC_END node_blob_sidecar
.endif

.if FORK >= FORK_FULU
/*
 * (data, config, settings, scratch, result, root): the checks a reader of a column sidecar
 * response makes: verify_data_column_sidecar, verify_data_column_sidecar_inclusion_proof and
 * verify_data_column_sidecar_kzg_proofs; then hash_tree_root of its block header. s1 config,
 * s2 the sidecar, s3 scratch, s4 result, s5 root, s6 settings, s10 the scratch size, restored on
 * return. Locals: L an out.
 */
SPEC_FUNCTION node_column_sidecar
    ENTER 16
    mv      s2, a0
    mv      s1, a1
    mv      s6, a2
    mv      s3, a3
    mv      s4, a4
    mv      s5, a5
    ld      s10, 0(s3)
    sd      zero, 0(s4)
    ADDRESS a0, lantern_type_DataColumnSidecar
    mv      a1, s2
    mv      a2, s3
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 9f
    mv      s2, a1
    mv      a0, s2                          # verify_data_column_sidecar
    mv      a1, s1
    addi    a2, sp, L
    call    lantern_verify_data_column_sidecar
    bnez    a0, 99f
    ld      t0, L(sp)
    beqz    t0, 6f
    mv      a0, s2                          # verify_data_column_sidecar_inclusion_proof
    mv      a1, s3
    addi    a2, sp, L
    call    lantern_verify_data_column_sidecar_inclusion_proof
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    bnez    a0, 99f
    ld      t0, L(sp)
    beqz    t0, 6f
    mv      a0, s2                          # verify_data_column_sidecar_kzg_proofs
    mv      a1, s6
    mv      a2, s3
    addi    a3, sp, L
    call    lantern_verify_data_column_sidecar_kzg_proofs
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    bnez    a0, 99f
    ld      t0, L(sp)
    beqz    t0, 6f
    ADDRESS a0, lantern_type_BeaconBlockHeader
    ADDQ    a1, s2, DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message
    mv      a2, s3
    mv      a3, s5
    CALL_GLOBAL ssz_hash_tree_root
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    j       99f
6:  li      t0, LANTERN_INVALID_COLUMN_SIDECAR
    sd      t0, 0(s4)
    li      a0, LANTERN_OK
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    j       99f
9:  li      t0, LANTERN_INVALID_ENCODING
    sd      t0, 0(s4)
    li      a0, LANTERN_OK
99: sd      s10, 0(s3)
    LEAVE 16
SPEC_END node_column_sidecar
.endif

.if FORK >= FORK_BELLATRIX
/*
 * (data, node, id, scratch, out, result): the HTTP request of engine_newPayload for the
 * SignedBeaconBlock in data: the JSON of lantern_engine_new_payload, the JWT of the node's secret
 * at time_ms / 1000, lantern_http_post to the node's engine_host. A payload whose block_hash and
 * parent_hash are zero gives LANTERN_NO_PAYLOAD. s1 node, s2 the block, s3 scratch, s4 out,
 * s5 result, s6 id, s7 the JSON, s8 the token, s9 the host, s10 the scratch size, restored on
 * return. Locals: L the time in seconds, L+8 the JSON's size.
 */
SPEC_FUNCTION node_new_payload
    ENTER 16
    mv      s2, a0
    mv      s1, a1
    mv      s6, a2
    mv      s3, a3
    mv      s4, a4
    mv      s5, a5
    ld      s10, 0(s3)
    sd      zero, 0(s5)
    ADDRESS a0, lantern_type_SignedBeaconBlock
    mv      a1, s2
    mv      a2, s3
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bgtu    a0, t0, 9f
    PART    s2, t0, a1, SignedBeaconBlock_message
    PART    t1, t0, s2, BeaconBlock_body
    PART    t2, t0, t1, BeaconBlockBody_execution_payload
    ADDQ    t3, t2, ExecutionPayload_block_hash     # no payload: zero block_hash and parent_hash
    ld      t0, 0(t3)
    ld      t1, 8(t3)
    or      t0, t0, t1
    ld      t1, 16(t3)
    or      t0, t0, t1
    ld      t1, 24(t3)
    or      t0, t0, t1
    ADDQ    t3, t2, ExecutionPayload_parent_hash
    ld      t1, 0(t3)
    or      t0, t0, t1
    ld      t1, 8(t3)
    or      t0, t0, t1
    ld      t1, 16(t3)
    or      t0, t0, t1
    ld      t1, 24(t3)
    or      t0, t0, t1
    bnez    t0, 1f
    li      t0, LANTERN_NO_PAYLOAD
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
    j       99f
1:  mv      a0, s2                          # the JSON's room, then the three lists at the end of scratch
    addi    a1, sp, L + 8
    call    lantern_engine_new_payload_size
    bnez    a0, 99f
    ld      t0, (L + 8)(sp)
    addi    t0, t0, 24 + 7
    andi    t0, t0, -8
    addi    t1, t0, 280 + 88
    ld      t2, 0(s3)
    li      t3, 4096
    add     t3, t3, t1
    bltu    t2, t3, 8f
    sub     t2, t2, t1
    sd      t2, 0(s3)
    add     s7, s3, t2
    add     s8, s7, t0
    addi    s9, s8, 280
    li      t3, 24
    sd      t0, 0(s7)
    sd      t3, 8(s7)
    sd      zero, 16(s7)
    li      t0, 280
    sd      t0, 0(s8)
    sd      t3, 8(s8)
    sd      zero, 16(s8)
    li      t0, 88
    sd      t0, 0(s9)
    sd      t3, 8(s9)
    ld      a2, Node_engine_host_len(s1)
    sd      a2, 16(s9)
    addi    a0, s9, 24
    addi    a1, s1, Node_engine_host
    call    lantern_copy
    mv      a0, s2                          # the JSON
    mv      a1, s6
    mv      a2, s3
    mv      a3, s7
    call    lantern_engine_new_payload
    bnez    a0, 99f
    ld      t0, Node_time_ms(s1)            # the JWT
    li      t1, 1000
    divu    t0, t0, t1
    sd      t0, L(sp)
    addi    a0, s1, Node_jwt_secret
    addi    a1, sp, L
    mv      a2, s3
    mv      a3, s8
    CALL_GLOBAL lantern_jwt_token
    bnez    a0, 99f
    mv      a0, s9                          # the HTTP request
    mv      a1, s8
    mv      a2, s7
    mv      a3, s4
    CALL_GLOBAL lantern_http_post
    j       99f
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    j       99f
9:  li      t0, LANTERN_INVALID_ENCODING
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
99: sd      s10, 0(s3)
    LEAVE 16
SPEC_END node_new_payload
.endif

/* SSZ bytes have no alignment: these read and write their integers a byte at a time. */
/* reg = the u32 at base + off. Uses tmp. */
.macro LWB reg, base, off, tmp
    lbu     \reg, (\off)(\base)
    lbu     \tmp, ((\off) + 1)(\base)
    slli    \tmp, \tmp, 8
    or      \reg, \reg, \tmp
    lbu     \tmp, ((\off) + 2)(\base)
    slli    \tmp, \tmp, 16
    or      \reg, \reg, \tmp
    lbu     \tmp, ((\off) + 3)(\base)
    slli    \tmp, \tmp, 24
    or      \reg, \reg, \tmp
.endm
/* reg = the u64 at base + off. Uses tmp, tmp2. */
.macro LDB reg, base, off, tmp, tmp2
    LWB     \reg, \base, \off, \tmp
    LWB     \tmp2, \base, (\off) + 4, \tmp
    slli    \tmp2, \tmp2, 32
    or      \reg, \reg, \tmp2
.endm
/* The u32 reg at base + off. Uses tmp. */
.macro SWB reg, base, off, tmp
    sb      \reg, (\off)(\base)
    srli    \tmp, \reg, 8
    sb      \tmp, ((\off) + 1)(\base)
    srli    \tmp, \reg, 16
    sb      \tmp, ((\off) + 2)(\base)
    srli    \tmp, \reg, 24
    sb      \tmp, ((\off) + 3)(\base)
.endm

/*
 * (state, request, scratch, out): node.md, lantern_node_produce_check. s1 state, s2 request, s3
 * scratch, s4 out, s5 the scratch size, s6 the proposer's Validator. Locals: L epoch, L+8 the
 * proposer, L+16 domain type, L+24 domain (32), L+56 the signing root after a ByteList header (56).
 */
SPEC_FUNCTION node_produce_check
    ENTER 112
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
.if FORK >= FORK_FULU
    NEED_SCRATCH s3, s1, 0, 9f
.else
    NEED_SCRATCH s3, s1, 2, 9f                  # get_beacon_proposer_index takes S(2)
.endif
    ld      s5, 0(s3)
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    mv      a0, s1
.if FORK >= FORK_FULU
    addi    a1, sp, (L + 8)
    call    lantern_get_beacon_proposer_index
.else
    mv      a1, s3
    addi    a2, sp, (L + 8)
    call    lantern_get_beacon_proposer_index
    sd      s5, 0(s3)
.endif
    bnez    a0, 7f
    ld      t0, (L + 8)(sp)
    sd      t0, 0(s4)
    ld      t0, 128(s2)                     # skip_randao_verification: the point at infinity
    beqz    t0, 1f
    lbu     t0, 0(s2)
    li      t1, 0xc0
    bne     t0, t1, 5f
    li      t1, 1
2:  add     t2, s2, t1
    lbu     t0, 0(t2)
    bnez    t0, 5f
    addi    t1, t1, 1
    li      t2, 96
    bltu    t1, t2, 2b
    j       3f
1:  ld      t0, (L + 8)(sp)                 # else the check of process_randao, no mix
    PART    s6, t1, s1, BeaconState_validators
    li      a0, LANTERN_INVALID_VALIDATOR_INDEX
    bgeu    t0, t1, 7f
    slli    t0, t0, 7
    add     s6, s6, t0
    li      t0, DOMAIN_RANDAO
    sw      t0, (L + 16)(sp)
    mv      a0, s1
    addi    a1, sp, (L + 16)
    addi    a2, sp, L
    mv      a3, s3
    addi    a4, sp, (L + 24)
    call    lantern_get_domain
    bnez    a0, 7f
    ADDRESS a0, lantern_type_Uint64
    addi    a1, sp, L
    addi    a2, sp, (L + 24)
    mv      a3, s3
    addi    a4, sp, (L + 80)
    call    lantern_compute_signing_root
    bnez    a0, 7f
    addi    a0, s6, Validator_pubkey
    mv      a1, s2
    addi    a2, sp, (L + 56)
    mv      a3, s3
    call    verify_root_signature
    bnez    a0, 7f
    beqz    a1, 5f
3:
.if FORK < FORK_ELECTRA
    LDQ     t0, s1, BeaconState_eth1_data + Eth1Data_deposit_count     # deposits the block would need
    LDQ     t1, s1, BeaconState_eth1_deposit_index
    bgtu    t0, t1, 6f
.elseif FORK == FORK_ELECTRA
    LDQ     t0, s1, BeaconState_eth1_data + Eth1Data_deposit_count     # get_eth1_pending_deposit_count
    LDQ     t2, s1, BeaconState_deposit_requests_start_index
    bltu    t0, t2, 31f
    mv      t0, t2
31: LDQ     t1, s1, BeaconState_eth1_deposit_index
    bltu    t1, t0, 6f
.endif
    li      a0, LANTERN_OK
7:  LEAVE 112
5:  li      a0, LANTERN_INVALID_RANDAO_REVEAL
    LEAVE 112
6:  li      a0, LANTERN_INVALID_DEPOSITS
    LEAVE 112
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 112
SPEC_END node_produce_check

.if FORK >= FORK_BELLATRIX
/* (json, scratch, out, fault): node.md, lantern_node_payload_result. */
SPEC_FUNCTION node_payload_result
    FRAME 0
    mv      a4, a3
    mv      a3, a2
    mv      a2, a1
    mv      a1, a0
.if FORK == FORK_BELLATRIX
    ADDRESS a0, lantern_type_ExecutionPayload
.else
    ADDRESS a0, lantern_type_GetPayloadResult
.endif
    CALL_GLOBAL lantern_engine_json_decode
    UNFRAME 0
SPEC_END node_payload_result
.endif

/*
 * (state, entry, draft, arg, scratch): node.md, lantern_node_produce_fold. s1 state, s2 the
 * entry's bytes, s3 their count, s4 the draft, s5 arg, s6 scratch, s7 the topic, s8 the entry's
 * fork, s9 an aggregate, s10 the place. Locals: L data, L+8 signature, L+16 length, L+24 the
 * committee index, L+40 the parent root (32). An Attestation's data is 4-aligned only.
 */
SPEC_FUNCTION node_produce_fold
    ENTER 96
    mv      s1, a0
    ld      t0, 8(a1)
    ld      s3, 16(a1)
    add     s2, a1, t0
    ld      t0, 8(a2)
    add     s4, a2, t0
    mv      s5, a3
    mv      s6, a4
    andi    s7, s5, 0xff
    srli    s8, s5, 8
    andi    s8, s8, 0xff
    li      t0, GOSSIP_BEACON_ATTESTATION
    beq     s7, t0, 100f
.if FORK >= FORK_ALTAIR
    li      t0, GOSSIP_SYNC_COMMITTEE
    beq     s7, t0, 200f
.endif
    li      t2, MAX_VOLUNTARY_EXITS         # an operation: a record, while its kind has room
    li      t0, GOSSIP_VOLUNTARY_EXIT
    beq     s7, t0, 1f
    li      t2, MAX_PROPOSER_SLASHINGS
    li      t0, GOSSIP_PROPOSER_SLASHING
    beq     s7, t0, 1f
.if FORK >= FORK_CAPELLA
    li      t2, MAX_BLS_TO_EXECUTION_CHANGES
    li      t0, GOSSIP_BLS_TO_EXECUTION_CHANGE
    beq     s7, t0, 1f
.endif
    li      t0, GOSSIP_ATTESTER_SLASHING
    bne     s7, t0, 8f
    li      t0, FORK_ELECTRA                # an attester slashing of the fork's type
.if FORK >= FORK_ELECTRA
    bltu    s8, t0, 8f
    li      t2, MAX_ATTESTER_SLASHINGS_ELECTRA
.else
    bgeu    s8, t0, 8f
    li      t2, MAX_ATTESTER_SLASHINGS
.endif
1:  ld      t3, ProduceDraft_ops(s4)
    ADDQ    t4, s4, PRODUCE_DRAFT_OPS
    add     t5, t4, t3                      # the end of the records
    li      t1, 0
2:  bgeu    t4, t5, 3f                      # the records of the topic
    ld      t0, 0(t4)
    bne     t0, s7, 21f
    addi    t1, t1, 1
21: ld      t0, 8(t4)
    addi    t0, t0, (16 + 7)
    andi    t0, t0, -8
    add     t4, t4, t0
    j       2b
3:  bgeu    t1, t2, 8f
    li      t0, GOSSIP_ATTESTER_SLASHING    # the clashes, with the kinds folded before
    bne     s7, t0, 4f
    mv      a0, s2
    mv      a1, s3
    ADDQ    a2, s4, PRODUCE_DRAFT_OPS
    mv      a3, t5
    call    produce_takes_slashing
    beqz    a0, 8f
4:  li      t0, GOSSIP_VOLUNTARY_EXIT
    bne     s7, t0, 5f
    ld      a0, 8(s2)
    ADDQ    a1, s4, PRODUCE_DRAFT_OPS
    ld      a2, ProduceDraft_ops(s4)
    add     a2, a1, a2
    call    produce_slashed
    bnez    a0, 8f
5:  ld      t3, ProduceDraft_ops(s4)
    ADDQ    t4, s4, PRODUCE_DRAFT_OPS
    add     t5, t4, t3                      # the record's place
    addi    t0, s3, (16 + 7)
    andi    t0, t0, -8
    add     t0, t3, t0
    li      t1, PRODUCE_DRAFT_OPS_ROOM
    bgtu    t0, t1, 8f
    sd      s7, 0(t5)
    sd      s3, 8(t5)
    sd      t0, ProduceDraft_ops(s4)
    addi    a0, t5, 16
    mv      a1, s2
    mv      a2, s3
    call    lantern_copy
    li      a0, LANTERN_OK
    LEAVE 96
8:  li      a0, LANTERN_INVALID_ENCODING    # left out
    LEAVE 96
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 96

    /* An attestation of the fork's type: its data, signature, committee, length and place. */
100: li     t0, FORK_ELECTRA
.if FORK >= FORK_ELECTRA
    bltu    s8, t0, 8b
    li      t0, 240                         # a SingleAttestation: committee_index 0, data at 16, signature at 144
    bne     s3, t0, 8b
    addi    t0, s2, 16
    sd      t0, L(sp)
    addi    t0, s2, 144
    sd      t0, (L + 8)(sp)
    ld      t0, 0(s2)
    sd      t0, (L + 24)(sp)
    srli    t0, s5, 16                      # member: the place, + 2^16 x the length
    slli    s10, t0, 48
    srli    s10, s10, 48
    srli    t0, t0, 16
    sd      t0, (L + 16)(sp)
    ld      t0, (16 + 8)(s2)                # data.index 0
    bnez    t0, 8b
.else
    bgeu    s8, t0, 8b
    li      t0, (228 + 1)                   # an Attestation: offset 228, data at 4, signature at 132, its bits
    bltu    s3, t0, 8b
    li      t0, (228 + MAX_VALIDATORS_PER_COMMITTEE / 8 + 1)
    bgtu    s3, t0, 8b
    lwu     t0, 0(s2)
    li      t1, 228
    bne     t0, t1, 8b
    addi    t0, s2, 4
    sd      t0, L(sp)
    addi    t0, s2, 132
    sd      t0, (L + 8)(sp)
    LDU64   t0, s2, (4 + 8), t1
    sd      t0, (L + 24)(sp)
    addi    t1, s2, 228                     # the bits
    addi    t2, s3, -229                    # the last byte: its highest bit is the length's
    add     t0, t1, t2
    lbu     t3, 0(t0)
    beqz    t3, 8b
    li      t4, -1
109: beqz   t3, 108f
    srli    t3, t3, 1
    addi    t4, t4, 1
    j       109b
108: slli   t2, t2, 3
    add     t4, t4, t2
    sd      t4, (L + 16)(sp)
    li      s10, 0                          # the place: the first bit set
101: bgeu   s10, t4, 8b
    srli    t0, s10, 3
    add     t0, t1, t0
    lbu     t0, 0(t0)
    andi    t2, s10, 7
    srl     t0, t0, t2
    andi    t0, t0, 1
    bnez    t0, 102f
    addi    s10, s10, 1
    j       101b
102:
.endif
    ld      t4, (L + 16)(sp)
    li      t0, MAX_VALIDATORS_PER_COMMITTEE
    bgtu    t4, t0, 8b
    bgeu    s10, t4, 8b
    ld      t1, L(sp)                       # process_attestation's checks of slot, target and source
    LDU64   t2, t1, 0, t0                   # data.slot
    LDU64   t3, t1, 88, t0                  # target.epoch
    LDQ     t4, s1, BeaconState_slot
    li      t0, SLOTS_PER_EPOCH
    divu    t5, t4, t0                      # the current epoch
    divu    t6, t2, t0
    bne     t6, t3, 8b
    beq     t3, t5, 103f
    beqz    t5, 8b
    addi    t6, t5, -1
    bne     t3, t6, 8b
103: addi   t6, t2, MIN_ATTESTATION_INCLUSION_DELAY
    bgtu    t6, t4, 8b
.if FORK < FORK_DENEB
    addi    t6, t2, SLOTS_PER_EPOCH
    bgtu    t4, t6, 8b
.endif
    ADDQ    t6, s1, BeaconState_current_justified_checkpoint
    beq     t3, t5, 104f
    ADDQ    t6, s1, BeaconState_previous_justified_checkpoint
104: addi   t1, t1, 48                      # source: epoch, root
    LDU64   t0, t1, 0, t2
    ld      t2, 0(t6)
    bne     t0, t2, 8b
    addi    t1, t1, 8
    addi    t6, t6, 8
    NE32W   t1, t6, 8b
    ADDQ    s9, s4, PRODUCE_DRAFT_AGGREGATES  # its aggregate: of the same data and committee
    ld      t2, ProduceDraft_aggregates(s4)
    li      t3, 0
105: bgeu   t3, t2, 110f
    ld      t0, DraftAggregate_committee_index(s9)
    ld      t1, (L + 24)(sp)
    bne     t0, t1, 107f
    ld      t4, L(sp)
    li      t5, 0
106: add    t0, s9, t5
    lwu     t0, 0(t0)
    add     t1, t4, t5
    lwu     t1, 0(t1)
    bne     t0, t1, 107f
    addi    t5, t5, 4
    li      t0, 128
    bltu    t5, t0, 106b
    j       120f
107: li     t0, DraftAggregate__mem
    add     s9, s9, t0
    addi    t3, t3, 1
    j       105b
110: li     t0, PRODUCE_DRAFT_AGGREGATE_COUNT  # a new aggregate: its data, committee, length, order, signature
    bgeu    t2, t0, 8b
    addi    t0, t2, 1
    sd      t0, ProduceDraft_aggregates(s4)
    mv      a0, s9
    ld      a1, L(sp)
    li      a2, 128
    call    lantern_copy
    ld      t0, (L + 24)(sp)
    sd      t0, DraftAggregate_committee_index(s9)
    ld      t0, (L + 16)(sp)
    sd      t0, DraftAggregate_length(s9)
    ld      t0, ProduceDraft_aggregates(s4)
    addi    t0, t0, -1
    sd      t0, DraftAggregate_order(s9)
    ADDQ    a0, s9, DraftAggregate_signature
    ld      a1, (L + 8)(sp)
    li      a2, 96
    call    lantern_copy
    j       130f
120: ld     t0, DraftAggregate_length(s9)   # the same length, a place not taken, the signatures added
    ld      t1, (L + 16)(sp)
    bne     t0, t1, 8b
    ADDQ    t1, s9, DraftAggregate_bits
    srli    t2, s10, 3
    add     t2, t1, t2
    lbu     t2, 0(t2)
    andi    t3, s10, 7
    srl     t2, t2, t3
    andi    t2, t2, 1
    bnez    t2, 8b
    ADDQ    a0, s9, DraftAggregate_signature
    ld      a1, (L + 8)(sp)
    mv      a2, s6
    call    produce_add_signature
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 9b
    bnez    a0, 8b
130: ADDQ   t1, s9, DraftAggregate_bits     # its place's bit
    srli    t2, s10, 3
    add     t2, t1, t2
    lbu     t3, 0(t2)
    andi    t4, s10, 7
    li      t5, 1
    sll     t5, t5, t4
    or      t3, t3, t5
    sb      t3, 0(t2)
    li      a0, LANTERN_OK
    LEAVE 96

.if FORK >= FORK_ALTAIR
    /*
     * A SyncCommitteeMessage of the state's slot - 1 and the block's parent root: each place of its
     * validator's public key in the state's current_sync_committee not set yet, its signature added.
     */
200: li     t0, 144
    bne     s3, t0, 8b
    ld      t0, 0(s2)
    addi    t0, t0, 1
    LDQ     t1, s1, BeaconState_slot
    bne     t0, t1, 8b
    ADDRESS a0, lantern_type_BeaconBlockHeader  # the parent root: hash_tree_root(state.latest_block_header)
    ADDQ    a1, s1, BeaconState_latest_block_header
    mv      a2, s6
    addi    a3, sp, (L + 40)
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 9b
    addi    t0, s2, 8
    addi    t1, sp, (L + 40)
    NE32    t0, t1, 8b
    ld      t0, 40(s2)                      # its validator's public key
    PART    t1, t2, s1, BeaconState_validators
    bgeu    t0, t2, 8b
    slli    t0, t0, 7
    add     s9, t1, t0
    ADDQ    s9, s9, Validator_pubkey
    ADDQ    s8, s1, BeaconState_current_sync_committee + SyncCommittee_pubkeys
    li      s10, 0
201: li     t0, SYNC_COMMITTEE_SIZE
    bgeu    s10, t0, 209f
    li      t0, 48
    mul     t1, s10, t0
    add     t1, t1, s8
    li      t2, 0
202: add    t3, t1, t2
    ld      t3, 0(t3)
    add     t4, s9, t2
    ld      t4, 0(t4)
    bne     t3, t4, 208f
    addi    t2, t2, 8
    li      t0, 48
    bltu    t2, t0, 202b
    addi    t1, s4, ProduceDraft_sync_bits  # a place: set, the signature added
    srli    t2, s10, 3
    add     t2, t1, t2
    lbu     t3, 0(t2)
    andi    t4, s10, 7
    srl     t5, t3, t4
    andi    t5, t5, 1
    bnez    t5, 208f
    li      t5, 1
    sll     t5, t5, t4
    or      t3, t3, t5
    sb      t3, 0(t2)
    ld      t0, ProduceDraft_sync_set(s4)
    bnez    t0, 203f
    li      t0, 1
    sd      t0, ProduceDraft_sync_set(s4)
    ADDQ    a0, s4, ProduceDraft_sync_signature
    addi    a1, s2, 48
    li      a2, 96
    call    lantern_copy
    j       208f
203: ADDQ   a0, s4, ProduceDraft_sync_signature
    addi    a1, s2, 48
    mv      a2, s6
    call    produce_add_signature
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 9b
208: addi   s10, s10, 1
    j       201b
209: li     a0, LANTERN_OK
    LEAVE 96
.endif
SPEC_END node_produce_fold

/*
 * L1: the signature a1 added to the aggregate a0 with crypto_bls_aggregate, through a list of the
 * two at the end of scratch a2: a0 = LANTERN_OK, a status of crypto_bls_aggregate, or
 * LANTERN_BUFFER_TOO_SMALL. Locals: F the aggregate, F+8 the signature, F+16 the list.
 */
LOCAL_FUNCTION produce_add_signature
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    ld      t0, 0(a2)
    li      t1, (24 + 2 * 96 + 8)
    bltu    t0, t1, 9f
    addi    t0, t0, -(24 + 2 * 96)
    andi    t0, t0, -8
    add     t0, a2, t0
    sd      t0, 16(sp)
    li      t1, (24 + 2 * 96)
    sd      t1, 0(t0)
    li      t1, 24
    sd      t1, 8(t0)
    li      t1, 2
    sd      t1, 16(t0)
    addi    a0, t0, 24
    ld      a1, 0(sp)
    li      a2, 96
    call    lantern_copy
    ld      t0, 16(sp)
    addi    a0, t0, (24 + 96)
    ld      a1, 8(sp)
    li      a2, 96
    call    lantern_copy
    ld      a0, 16(sp)
    ld      a1, 0(sp)
    CALL_GLOBAL crypto_bls_aggregate
    UNFRAME 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
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

/* The offset of the body's field at pos: the write position s6 from the body s8. Uses t0. */
.macro PB_OFFSET pos
    sub     t0, s6, s8
    sw      t0, (\pos)(s8)
.endm

/*
 * (state, draft, params, scratch, out): node.md, lantern_node_produce_block. s1 state, s2 the
 * draft, s3 params, s4 scratch, s5 out, s6 the write position, s7 the block, s8 the body. Locals:
 * L proposer, L+8 the result's bytes, L+16 their count, L+24 the payload, L+32 its count, L+40
 * the bundle, L+48 its count, L+56 balance before, L+64 1, L+72 a Result, L+80 the scratch size,
 * L+88 a ByteList view of the request lists (electra), L+256 24 bytes kept aside. The engine's
 * result and the block's parts after the attestations have no alignment.
 */
SPEC_FUNCTION node_produce_block
    ENTER 288
    mv      s1, a0
    ld      t0, 8(a1)
    add     s2, a1, t0
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      t0, 0(s4)
    sd      t0, (L + 80)(sp)
    ld      t0, 0(s3)                       # execution_valid 1, + 2 with skip_randao_verification
    ld      t0, 128(t0)
    slli    t0, t0, 1
    ori     t0, t0, 1
    sd      t0, (L + 64)(sp)
    li      t0, 24                          # out: the block from offset 24, as large as its room
    sd      t0, 8(s5)
    sd      zero, 16(s5)
    addi    s7, s5, 24
    mv      a0, s1                          # the proposer
.if FORK >= FORK_FULU
    addi    a1, sp, L
    call    lantern_get_beacon_proposer_index
.else
    mv      a1, s4
    addi    a2, sp, L
    call    lantern_get_beacon_proposer_index
    ld      t0, (L + 80)(sp)
    sd      t0, 0(s4)
.endif
    bnez    a0, 99f
    ld      t0, L(sp)                       # its balance before
    PART    t1, t2, s1, BeaconState_balances
    bgeu    t0, t2, 97f
    slli    t0, t0, 3
    add     t0, t1, t0
    ld      t0, 0(t0)
    sd      t0, (L + 56)(sp)
    sd      zero, (L + 8)(sp)               # the engine's result: the payload, and from deneb the bundle
    sd      zero, (L + 16)(sp)
    sd      zero, (L + 24)(sp)
    sd      zero, (L + 32)(sp)
    sd      zero, (L + 40)(sp)
    sd      zero, (L + 48)(sp)
    ld      a1, 16(s3)
    beqz    a1, 5f
    ld      t0, 8(a1)
    ld      t1, 16(a1)
    add     t0, a1, t0
    sd      t0, (L + 8)(sp)
    sd      t1, (L + 16)(sp)
.if FORK == FORK_BELLATRIX
    sd      t0, (L + 24)(sp)                # the result is the payload
    sd      t1, (L + 32)(sp)
.else
    li      t2, (4 + 32)                    # GetPayloadResult: the payload's offset, block_value at 4
    bltu    t1, t2, 96f
    lwu     t2, 0(t0)
.if FORK >= FORK_DENEB
    lwu     t3, 36(t0)                      # blobs_bundle's offset
.else
    mv      t3, t1
.endif
    bgtu    t2, t3, 96f
    bgtu    t3, t1, 96f
    add     t4, t0, t2
    sub     t5, t3, t2
    sd      t4, (L + 24)(sp)
    sd      t5, (L + 32)(sp)
.if FORK >= FORK_DENEB
.if FORK >= FORK_ELECTRA
    LWB     t4, t0, 41, t5                  # execution_requests' offset: the bundle up to it
.else
    mv      t4, t1
.endif
    bgtu    t3, t4, 96f
    bgtu    t4, t1, 96f
    add     t5, t0, t3
    sub     t6, t4, t3
    sd      t5, (L + 40)(sp)
    sd      t6, (L + 48)(sp)
.endif
.endif
5:  ld      t0, 0(s5)                       # room: the fixed parts of the block and the body
    li      t1, (PB_FIXED + PB_BODY_FIXED + 24)
    bltu    t0, t1, 98f
    LDQ     t0, s1, BeaconState_slot
    sd      t0, 0(s7)
    ld      t0, L(sp)
    sd      t0, 8(s7)
    ADDRESS a0, lantern_type_BeaconBlockHeader  # parent_root: hash_tree_root(state.latest_block_header)
    ADDQ    a1, s1, BeaconState_latest_block_header
    mv      a2, s4
    addi    a3, s7, 16
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 99f
    sd      zero, 48(s7)                    # state_root, written last
    sd      zero, 56(s7)
    sd      zero, 64(s7)
    sd      zero, 72(s7)
    li      t0, PB_FIXED
    sw      t0, 80(s7)
    addi    s8, s7, PB_FIXED
    mv      a0, s8                          # randao_reveal, eth1_data (an empty eth1 chain's vote), graffiti
    ld      a1, 0(s3)
    li      a2, 96
    call    lantern_copy
    addi    a0, s8, 96
    ADDQ    a1, s1, BeaconState_eth1_data
    li      a2, 72
    call    lantern_copy
    addi    a0, s8, 168
    ld      a1, 0(s3)
    addi    a1, a1, 96
    li      a2, 32
    call    lantern_copy
.if FORK >= FORK_ALTAIR
    addi    a0, s8, PB_SYNC                 # the draft's sync aggregate; with none, no bit and the point at infinity
    addi    a1, s2, ProduceDraft_sync_bits
    li      a2, (SYNC_COMMITTEE_SIZE / 8 + 96)
    call    lantern_copy
    ld      t0, ProduceDraft_sync_set(s2)
    bnez    t0, 6f
    addi    a0, s8, (PB_SYNC + SYNC_COMMITTEE_SIZE / 8)
    li      a1, 96
    call    lantern_zero
    li      t0, 0xc0
    sb      t0, (PB_SYNC + SYNC_COMMITTEE_SIZE / 8)(s8)
6:
.endif
    addi    s6, s8, PB_BODY_FIXED
    /* proposer_slashings, attester_slashings: the draft's records, which the folds kept free of clashes */
    PB_OFFSET 200
    li      a0, GOSSIP_PROPOSER_SLASHING
    mv      a1, s6
    call    produce_records
    mv      s6, a1
    bnez    a0, 98f
    PB_OFFSET 204
    mv      a0, s6
    call    produce_attester_slashings
    mv      s6, a1
    bnez    a0, 98f
    /* attestations: the draft's aggregates */
    PB_OFFSET 208
    addi    a0, sp, L
    mv      a1, s6
    call    produce_attestations
    mv      s6, a1
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 98f
    bnez    a0, 99f
    /* deposits: none; voluntary_exits */
    PB_OFFSET 212
    PB_OFFSET 216
    li      a0, GOSSIP_VOLUNTARY_EXIT
    mv      a1, s6
    call    produce_records
    mv      s6, a1
    bnez    a0, 98f
.if FORK >= FORK_BELLATRIX
    PB_OFFSET PB_PAYLOAD                    /* the payload, the empty one before the merge */
    ld      t0, (L + 24)(sp)
    bnez    t0, 7f
.if FORK == FORK_BELLATRIX
    mv      a0, s6                          # ExecutionPayload.empty(): the offsets of extra_data and transactions at 508
    li      a1, 508
    call    produce_room
    bnez    a0, 98f
    mv      a0, s6
    li      a1, 508
    call    lantern_zero
    li      t0, 508
    SWB     t0, s6, 436, t1
    SWB     t0, s6, 504, t1
    addi    s6, s6, 508
    j       71f
.else
    j       96f
.endif
7:  mv      a0, s6
    ld      a1, (L + 32)(sp)
    call    produce_room
    bnez    a0, 98f
    mv      a0, s6
    ld      a1, (L + 24)(sp)
    ld      a2, (L + 32)(sp)
    add     s6, s6, a2
    call    lantern_copy
71:
.endif
.if FORK >= FORK_CAPELLA
    PB_OFFSET PB_BLS
    li      a0, GOSSIP_BLS_TO_EXECUTION_CHANGE
    mv      a1, s6
    call    produce_records
    mv      s6, a1
    bnez    a0, 98f
.endif
.if FORK >= FORK_DENEB
    PB_OFFSET PB_COMMITMENTS                /* the bundle's commitments */
    ld      t0, (L + 40)(sp)
    ld      t1, (L + 48)(sp)
    li      t2, 12
    bltu    t1, t2, 96f
    LWB     t2, t0, 0, t4
    LWB     t3, t0, 4, t4
    bgtu    t2, t3, 96f
    bgtu    t3, t1, 96f
    add     t4, t0, t2
    sub     t5, t3, t2
    sd      t4, (L + 8)(sp)
    sd      t5, (L + 16)(sp)
    mv      a0, s6
    mv      a1, t5
    call    produce_room
    bnez    a0, 98f
    mv      a0, s6
    ld      a1, (L + 8)(sp)
    ld      a2, (L + 16)(sp)
    add     s6, s6, a2
    call    lantern_copy
.endif
.if FORK >= FORK_ELECTRA
    PB_OFFSET PB_REQUESTS                   /* lantern_get_execution_requests of the result's request lists */
    ld      t0, 16(s3)
    ld      t1, 8(t0)
    ld      t2, 16(t0)                      # the count
    add     t1, t0, t1                      # the result's bytes
    LWB     t3, t1, 41, t4
    bgtu    t3, t2, 96f
    addi    t4, sp, (L + 112)               # a ByteList view of them in the locals
    add     t5, t1, t3
    sub     t5, t5, t4                      # its offset: from the view to the lists
    sub     t6, t2, t3                      # their count
    sd      t5, -16(t4)
    sd      t6, -8(t4)
    add     t5, t5, t6
    sd      t5, -24(t4)
    ld      t0, -24(s6)                     # the requests' room: the rest of out, as a ByteList at the write position less 24
    sd      t0, (L + 256)(sp)
    ld      t0, -16(s6)
    sd      t0, (L + 264)(sp)
    ld      t0, -8(s6)
    sd      t0, (L + 272)(sp)
    ld      t0, 0(s5)
    add     t0, s5, t0
    addi    t0, t0, -24
    addi    a1, s6, -24
    sub     t0, t0, a1
    sd      t0, 0(a1)
    li      t0, 24
    sd      t0, 8(a1)
    sd      zero, 16(a1)
    addi    a0, sp, (L + 88)
    call    lantern_get_execution_requests
    ld      t1, -8(s6)                      # the bytes written; the 24 bytes before them back
    ld      t0, (L + 256)(sp)
    sd      t0, -24(s6)
    ld      t0, (L + 264)(sp)
    sd      t0, -16(s6)
    ld      t0, (L + 272)(sp)
    sd      t0, -8(s6)
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 98f
    bnez    a0, 96f
    add     s6, s6, t1
.endif
    sub     t0, s6, s7                      # the block's bytes
    sd      t0, 16(s5)
    ADDRESS a0, lantern_type_BeaconBlock    # the state root: process_block of the decoded block, then the state's root
    mv      a1, s5
    mv      a2, s4
    call    node_decode
    li      t0, 1
    beq     a0, t0, 98f
    bgtu    a0, t0, 96f
    mv      a0, s1
    addi    a2, sp, (L + 64)
    ld      a3, 8(s3)
    mv      a4, s4
    addi    a5, sp, (L + 72)
    call    lantern_process_block
    ld      t0, (L + 80)(sp)
    sd      t0, 0(s4)
    bnez    a0, 99f
    ld      a0, (L + 72)(sp)
    bnez    a0, 99f
    mv      a0, s1
    li      a1, 0
    mv      a2, s4
    addi    a3, s7, 48
    call    lantern_state_root
    bnez    a0, 99f
    ld      t0, L(sp)                       # consensus_block_value: the balance after less before, plus the proposer's withdrawals
    PART    t1, t2, s1, BeaconState_balances
    slli    t2, t0, 3
    add     t1, t1, t2
    ld      t1, 0(t1)
    ld      t2, (L + 56)(sp)
    sub     t3, t1, t2
.if FORK >= FORK_CAPELLA
    ld      t4, (L + 24)(sp)                # the payload's withdrawals: from the offset at 508, 44 bytes each
    beqz    t4, 81f
    ld      t5, (L + 32)(sp)
    LWB     t6, t4, 508, t1
    bgtu    t6, t5, 81f
80: addi    t1, t6, 44
    bgtu    t1, t5, 81f
    add     a2, t4, t6
    LDB     a3, a2, 8, t1, a4
    bne     a3, t0, 801f
    LDB     a3, a2, 36, t1, a4
    add     t3, t3, a3
801: addi   t6, t6, 44
    j       80b
81:
.endif
    bgez    t3, 82f
    li      t3, 0
82: ld      t0, 32(s3)
    sd      t3, 0(t0)
    ld      a0, 24(s3)                      # execution_payload_value: the result's block_value, else 0
    sd      zero, 0(a0)
    sd      zero, 8(a0)
    sd      zero, 16(a0)
    sd      zero, 24(a0)
.if FORK >= FORK_CAPELLA
    ld      t0, (L + 8)(sp)
    beqz    t0, 83f
    ld      t0, 16(s3)
    ld      t1, 8(t0)
    add     a1, t0, t1
    addi    a1, a1, 4
    li      a2, 32
    call    lantern_copy
83:
.endif
.if FORK >= FORK_DENEB
    addi    a0, sp, L                       # BlockContents: the block, the bundle's proofs and blobs
    call    produce_contents
    bnez    a0, 98f
.endif
    li      a0, LANTERN_OK
99: LEAVE 288
96: li      a0, LANTERN_INVALID_ENCODING
    LEAVE 288
97: li      a0, LANTERN_INVALID_VALIDATOR_INDEX
    LEAVE 288
98: ld      t0, (L + 80)(sp)
    sd      t0, 0(s4)
    li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 288
SPEC_END node_produce_block

/* L0: a0 = 0 when a1 bytes from a0 fit in the ByteList s5, else 1. Uses t5, t6. */
LOCAL_FUNCTION produce_room
    UNWIND_END_PROLOGUE
    ld      t5, 0(s5)
    add     t5, s5, t5
    add     t6, a0, a1
    sltu    a0, t5, t6
    ret
END_FUNCTION produce_room

/*
 * L0: (index a0, record a1) -> a0 = 1 when the index is in both attestations of the attester
 * slashing whose SSZ bytes follow the draft record a1, else 0. Its indices are 4-aligned. Uses
 * a1-a5, t0-t4.
 */
LOCAL_FUNCTION produce_in_slashing
    UNWIND_END_PROLOGUE
    ld      t0, 8(a1)                       # its length
    addi    a1, a1, 16
    li      t1, 8
    bltu    t0, t1, 9f
    lwu     t1, 0(a1)                       # the attestations: [o1, o2), then [o2, end)
    lwu     t2, 4(a1)
    mv      a2, t1
    mv      a3, t2
    li      a5, 0
1:  bgeu    a2, a3, 9f
    add     t3, a1, a2
    lwu     t3, 0(t3)                       # its indices, from its offset
    add     a4, a2, t3
2:  addi    t3, a4, 8
    bgtu    t3, a3, 9f
    add     t3, a1, a4
    LDU64   t4, t3, 0, t3
    beq     t4, a0, 3f
    addi    a4, a4, 8
    j       2b
3:  bnez    a5, 4f                          # in the first: then the second
    li      a5, 1
    mv      a2, t2
    mv      a3, t0
    j       1b
4:  li      a0, 1
    ret
9:  li      a0, 0
    ret
END_FUNCTION produce_in_slashing

/*
 * L2: (topic a0, write position a1) -> a0 = 0, or 1 for a short out; a1 = the write position. The
 * SSZ bytes of the draft's records of the topic in their order, back to back. s3 a record, s4 the
 * records' end, s7 the topic, s9 the position.
 */
LOCAL_FUNCTION produce_records
    ENTER 0
    mv      s7, a0
    mv      s9, a1
    ld      t0, ProduceDraft_ops(s2)
    ADDQ    s3, s2, PRODUCE_DRAFT_OPS
    add     s4, s3, t0
1:  bgeu    s3, s4, 8f
    ld      t0, 0(s3)
    bne     t0, s7, 5f
    mv      a0, s9
    ld      a1, 8(s3)
    call    produce_room
    bnez    a0, 9f
    mv      a0, s9
    addi    a1, s3, 16
    ld      a2, 8(s3)
    add     s9, s9, a2
    call    lantern_copy
5:  ld      t0, 8(s3)
    addi    t0, t0, (16 + 7)
    andi    t0, t0, -8
    add     s3, s3, t0
    j       1b
8:  li      a0, 0
    mv      a1, s9
    LEAVE 0
9:  li      a0, 1
    mv      a1, s9
    LEAVE 0
END_FUNCTION produce_records

/*
 * L2: (write position a0) -> a0 = 0, or 1 for a short out; a1 = the write position. The draft's
 * attester slashing records as an SSZ list: their offsets, then their bytes. s3 a record, s4 the
 * end, s7 their count, s8 the next offset, s9 the position, s10 the next offset's place.
 */
LOCAL_FUNCTION produce_attester_slashings
    ENTER 0
    mv      s9, a0
    ld      t0, ProduceDraft_ops(s2)
    ADDQ    s3, s2, PRODUCE_DRAFT_OPS
    add     s4, s3, t0
    li      s7, 0
    mv      t1, s3
1:  bgeu    t1, s4, 2f
    ld      t0, 0(t1)
    li      t2, GOSSIP_ATTESTER_SLASHING
    bne     t0, t2, 11f
    addi    s7, s7, 1
11: ld      t0, 8(t1)
    addi    t0, t0, (16 + 7)
    andi    t0, t0, -8
    add     t1, t1, t0
    j       1b
2:  slli    s8, s7, 2                       # the offsets, the first slashing after them
    mv      a0, s9
    mv      a1, s8
    call    produce_room
    bnez    a0, 9f
    mv      s10, s9
    add     s9, s9, s8
3:  bgeu    s3, s4, 8f
    ld      t0, 0(s3)
    li      t2, GOSSIP_ATTESTER_SLASHING
    bne     t0, t2, 4f
    sw      s8, 0(s10)
    addi    s10, s10, 4
    ld      t0, 8(s3)
    add     s8, s8, t0
    mv      a0, s9
    mv      a1, t0
    call    produce_room
    bnez    a0, 9f
    mv      a0, s9
    addi    a1, s3, 16
    ld      a2, 8(s3)
    add     s9, s9, a2
    call    lantern_copy
4:  ld      t0, 8(s3)
    addi    t0, t0, (16 + 7)
    andi    t0, t0, -8
    add     s3, s3, t0
    j       3b
8:  li      a0, 0
    mv      a1, s9
    LEAVE 0
9:  li      a0, 1
    mv      a1, s9
    LEAVE 0
END_FUNCTION produce_attester_slashings

/*
 * L1: (index a0, records a1, their end a2) -> a0 = 1 when a proposer slashing record of [a1, a2)
 * has the index as its proposer, or an attester slashing record has it in both attestations;
 * else 0. s1 the index, s2 a record, s3 the end.
 */
LOCAL_FUNCTION produce_slashed
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
1:  bgeu    s2, s3, 8f
    ld      t0, 0(s2)
    li      t1, GOSSIP_PROPOSER_SLASHING
    bne     t0, t1, 2f
    ld      t1, (16 + 8)(s2)                # signed_header_1.message.proposer_index
    beq     t1, s1, 9f
    j       3f
2:  li      t1, GOSSIP_ATTESTER_SLASHING
    bne     t0, t1, 3f
    mv      a0, s1
    mv      a1, s2
    call    produce_in_slashing
    bnez    a0, 9f
3:  ld      t0, 8(s2)
    addi    t0, t0, (16 + 7)
    andi    t0, t0, -8
    add     s2, s2, t0
    j       1b
8:  li      a0, 0
    LEAVE 0
9:  li      a0, 1
    LEAVE 0
END_FUNCTION produce_slashed

/*
 * L0: (the attester slashing's bytes a0, their count a1, records a2, their end a3) -> a0 = 1 when
 * an index is in both attestations (whose indices are sorted, as is_valid_indexed_attestation
 * holds them) and no proposer slashing record of [a2, a3) has it as its proposer; else 0. a4 a
 * place in the first list, a5 its end, t5 a place in the second, a1 its end. Uses t0-t6.
 */
LOCAL_FUNCTION produce_takes_slashing
    UNWIND_END_PROLOGUE
    li      t0, 8
    bltu    a1, t0, 8f
    lwu     t0, 0(a0)                       # the attestations: [o1, o2), [o2, count)
    lwu     t1, 4(a0)
    bgtu    t0, t1, 8f
    bgtu    t1, a1, 8f
    addi    t2, t0, 228
    bgtu    t2, t1, 8f
    addi    t2, t1, 228
    bgtu    t2, a1, 8f
    add     t2, a0, t0                      # each one's indices: from its offset to its end
    lwu     t2, 0(t2)
    add     a4, t0, t2
    mv      a5, t1
    add     t2, a0, t1
    lwu     t2, 0(t2)
    add     t5, t1, t2
1:  addi    t0, a4, 8
    bgtu    t0, a5, 8f
    addi    t0, t5, 8
    bgtu    t0, a1, 8f
    add     t0, a0, a4
    LDU64   t2, t0, 0, t0
    add     t0, a0, t5
    LDU64   t3, t0, 0, t0
    bltu    t2, t3, 2f
    bgtu    t2, t3, 3f
    mv      t4, a2                          # in both: a proposer slashing's proposer?
4:  bgeu    t4, a3, 9f
    ld      t0, 0(t4)
    li      t1, GOSSIP_PROPOSER_SLASHING
    bne     t0, t1, 5f
    ld      t0, (16 + 8)(t4)
    beq     t0, t2, 6f
5:  ld      t0, 8(t4)
    addi    t0, t0, (16 + 7)
    andi    t0, t0, -8
    add     t4, t4, t0
    j       4b
6:  addi    t5, t5, 8
2:  addi    a4, a4, 8
    j       1b
3:  addi    t5, t5, 8
    j       1b
8:  li      a0, 0
    ret
9:  li      a0, 1
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

/* L0: a0 = 1 when the 128 bytes at a0 and a1 (each 8-aligned) are equal, else 0. Uses t0-t2. */
LOCAL_FUNCTION produce_same_data
    UNWIND_END_PROLOGUE
    li      t0, 0
1:  add     t1, a0, t0
    ld      t1, 0(t1)
    add     t2, a1, t0
    ld      t2, 0(t2)
    bne     t1, t2, 2f
    addi    t0, t0, 8
    li      t1, 128
    bltu    t0, t1, 1b
    li      a0, 1
    ret
2:  li      a0, 0
    ret
END_FUNCTION produce_same_data

/*
 * L2: (the block's locals a0, write position a1) -> a0 = 0, 1 for a short out or scratch, or a
 * status of crypto_bls_aggregate; a1 = the write position. The draft's aggregates chosen by
 * data.slot descending, then order, at most the fork's limit; before electra an Attestation of
 * each, from electra one Attestation for each data of the aggregates of every committee
 * (compute_on_chain_aggregate). The list: offsets, then the attestations. s1 an aggregate, s3 the
 * aggregates, s4 scratch, s6 the chosen aggregate, s7 their count, s8 the chosen indices (in
 * scratch, after a flag byte for each aggregate), s9 the position, s10 the chosen count. Locals:
 * L the scratch size, L+8 an index, L+16 the bits' cursor, L+24 a committee.
 */
LOCAL_FUNCTION produce_attestations
    ENTER 32
    mv      s9, a1
    ld      s7, ProduceDraft_aggregates(s2)
    ADDQ    s3, s2, PRODUCE_DRAFT_AGGREGATES
    ld      t0, 0(s4)                       # the flags and the chosen at the end of scratch
    sd      t0, L(sp)
    li      t1, (8 * PB_MAX_ATTESTATIONS + 7)
    add     t1, s7, t1
    andi    t1, t1, -8
    addi    t2, t1, 1024
    bltu    t0, t2, 97f
    sub     t0, t0, t1
    sd      t0, 0(s4)
    add     s8, s4, t0
    mv      a0, s8
    mv      a1, s7
    call    lantern_zero
    add     s8, s8, s7                      # the chosen indices after the flags
    addi    s8, s8, 7
    andi    s8, s8, -8
    li      s10, 0
1:  li      t0, PB_MAX_ATTESTATIONS         # the next: of the highest slot, then the lowest order
    bgeu    s10, t0, 3f
    li      t1, -1
    li      t2, 0
    li      t3, 0                           # the best's slot
    ld      t4, 0(s4)
    add     t4, s4, t4                      # the flags
2:  bgeu    t2, s7, 21f
    add     t5, t4, t2
    lbu     t5, 0(t5)
    bnez    t5, 22f
    li      t5, DraftAggregate__mem
    mul     t5, t2, t5
    add     t5, s3, t5
    ld      t5, 0(t5)                       # data.slot
    li      t6, -1
    beq     t1, t6, 23f
    bleu    t5, t3, 22f
23: mv      t1, t2
    mv      t3, t5
22: addi    t2, t2, 1
    j       2b
21: li      t6, -1
    beq     t1, t6, 3f
    slli    t5, s10, 3
    add     t5, s8, t5
    sd      t1, 0(t5)
    addi    s10, s10, 1
    add     t5, t4, t1                      # chosen: its flag, from electra those of its data too
    li      t6, 1
    sb      t6, 0(t5)
.if FORK >= FORK_ELECTRA
    li      t5, DraftAggregate__mem
    mul     t5, t1, t5
    add     t5, s3, t5
    sd      t5, (L + 8)(sp)
    li      t2, 0
24: bgeu    t2, s7, 1b
    li      t5, DraftAggregate__mem
    mul     a1, t2, t5
    add     a1, s3, a1
    ld      a0, (L + 8)(sp)
    sd      t2, (L + 16)(sp)
    call    produce_same_data
    ld      t2, (L + 16)(sp)
    beqz    a0, 25f
    ld      t4, 0(s4)
    add     t4, s4, t4
    add     t4, t4, t2
    li      t5, 1
    sb      t5, 0(t4)
25: addi    t2, t2, 1
    j       24b
.else
    j       1b
.endif
3:  slli    t0, s10, 2                      # the offsets: the size of each attestation
    sd      t0, (L + 24)(sp)
    mv      a0, s9
    mv      a1, t0
    call    produce_room
    bnez    a0, 98f
    ld      t0, (L + 24)(sp)
    sd      t0, (L + 16)(sp)                # the next offset
    sd      zero, (L + 8)(sp)
4:  ld      t1, (L + 8)(sp)
    bgeu    t1, s10, 5f
    ld      t0, (L + 16)(sp)
    slli    t2, t1, 2
    add     t2, s9, t2
    sw      t0, 0(t2)
    slli    t2, t1, 3
    add     t2, s8, t2
    ld      a0, 0(t2)
    call    produce_att_bits
    addi    a0, a0, (8 + 7)                 # the bits: as many as the length, and the end bit
    srli    a0, a0, 3
    addi    a0, a0, PB_ATT_FIXED
    ld      t0, (L + 16)(sp)
    add     t0, t0, a0
    sd      t0, (L + 16)(sp)
    ld      t1, (L + 8)(sp)
    addi    t1, t1, 1
    sd      t1, (L + 8)(sp)
    j       4b
5:  ld      t0, (L + 24)(sp)
    add     s9, s9, t0
    sd      zero, (L + 8)(sp)
6:  ld      t1, (L + 8)(sp)                 # each attestation
    bgeu    t1, s10, 8f
    slli    t2, t1, 3
    add     t2, s8, t2
    ld      a0, 0(t2)
    li      t0, DraftAggregate__mem
    mul     s6, a0, t0
    add     s6, s3, s6                      # the chosen aggregate
    call    produce_att_bits
    addi    a0, a0, (8 + 7)
    srli    a0, a0, 3
    addi    a1, a0, PB_ATT_FIXED
    mv      a0, s9
    call    produce_room
    bnez    a0, 98f
    li      t0, PB_ATT_FIXED                # its place has no alignment
    SWB     t0, s9, 0, t1
    addi    a0, s9, 4                       # data
    mv      a1, s6
    li      a2, 128
    call    lantern_copy
    addi    a0, s9, 132                     # signature: the first's
    ADDQ    a1, s6, DraftAggregate_signature
    li      a2, 96
    call    lantern_copy
    ld      t1, (L + 8)(sp)                 # from electra the committee bits; the aggregation bits, zero
    slli    t2, t1, 3
    add     t2, s8, t2
    ld      a0, 0(t2)
    call    produce_att_bits
    addi    a1, a0, (8 + 7)
    srli    a1, a1, 3
    addi    a1, a1, PB_ATT_COMMITTEE
    addi    a0, s9, 228
    call    lantern_zero
    sd      zero, (L + 16)(sp)              # the bits' cursor
.if FORK >= FORK_ELECTRA
    sd      zero, (L + 24)(sp)              # each committee in order: its aggregate of the data
61: ld      t0, (L + 24)(sp)
    li      t1, MAX_COMMITTEES_PER_SLOT
    bgeu    t0, t1, 7f
    li      s1, 0
62: bgeu    s1, s7, 66f
    li      t0, DraftAggregate__mem
    mul     a1, s1, t0
    add     a1, s3, a1
    ld      t0, DraftAggregate_committee_index(a1)
    ld      t1, (L + 24)(sp)
    bne     t0, t1, 65f
    mv      a0, s6
    call    produce_same_data
    beqz    a0, 65f
    li      t0, DraftAggregate__mem
    mul     a1, s1, t0
    add     a1, s3, a1
    ld      t1, (L + 24)(sp)                # its committee's bit
    srli    t2, t1, 3
    add     t2, s9, t2
    addi    t2, t2, 228
    lbu     t3, 0(t2)
    andi    t4, t1, 7
    li      t5, 1
    sll     t5, t5, t4
    or      t3, t3, t5
    sb      t3, 0(t2)
    beq     a1, s6, 63f                     # its signature, after the first's
    mv      s1, a1
    addi    a0, s9, 132
    ADDQ    a1, s1, DraftAggregate_signature
    mv      a2, s4
    call    produce_add_signature
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 97f
    bnez    a0, 96f
    mv      a1, s1
63: addi    a0, s9, (228 + PB_COMMITTEE_BITS)  # its bits at the cursor
    ld      a2, (L + 16)(sp)
    call    produce_copy_bits
    sd      a0, (L + 16)(sp)
    j       66f
65: addi    s1, s1, 1
    j       62b
66: ld      t0, (L + 24)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 24)(sp)
    j       61b
.else
    addi    a0, s9, 228
    mv      a1, s6
    li      a2, 0
    call    produce_copy_bits
    sd      a0, (L + 16)(sp)
.endif
7:  ld      t0, (L + 16)(sp)                # the end bit
    addi    t1, s9, PB_ATT_FIXED
    srli    t2, t0, 3
    add     t2, t1, t2
    andi    t3, t0, 7
    li      t4, 1
    sll     t4, t4, t3
    lbu     t3, 0(t2)
    or      t3, t3, t4
    sb      t3, 0(t2)
    addi    s9, t2, 1
    ld      t1, (L + 8)(sp)
    addi    t1, t1, 1
    sd      t1, (L + 8)(sp)
    j       6b
8:  ld      t0, L(sp)
    sd      t0, 0(s4)
    li      a0, 0
    mv      a1, s9
    LEAVE 32
96: ld      t0, L(sp)
    sd      t0, 0(s4)
    mv      a1, s9
    LEAVE 32
97: ld      t0, L(sp)
    sd      t0, 0(s4)
98: li      a0, 1
    mv      a1, s9
    LEAVE 32
END_FUNCTION produce_attestations

/*
 * L0: (index a0) -> a0: the aggregation bits of the attestation of the draft's aggregate a0, s3
 * the aggregates, s7 their count: its length; from electra the lengths of the aggregates of its
 * data. Uses a1, t0-t5.
 */
LOCAL_FUNCTION produce_att_bits
    UNWIND_END_PROLOGUE
    li      t0, DraftAggregate__mem
    mul     t1, a0, t0
    add     t1, s3, t1
.if FORK >= FORK_ELECTRA
    li      a0, 0
    li      t2, 0
1:  bgeu    t2, s7, 3f
    mul     a1, t2, t0
    add     a1, s3, a1
    li      t3, 0
2:  add     t4, t1, t3
    ld      t4, 0(t4)
    add     t5, a1, t3
    ld      t5, 0(t5)
    bne     t4, t5, 4f
    addi    t3, t3, 8
    li      t4, 128
    bltu    t3, t4, 2b
    ld      t4, DraftAggregate_length(a1)
    add     a0, a0, t4
4:  addi    t2, t2, 1
    j       1b
3:  ret
.else
    ld      a0, DraftAggregate_length(t1)
    ret
.endif
END_FUNCTION produce_att_bits

/* L0: (bits a0, aggregate a1, cursor a2) -> a0: the aggregate's length bits set at bit a2 of a0 on; the cursor after them. Uses a3, t0-t4. */
LOCAL_FUNCTION produce_copy_bits
    UNWIND_END_PROLOGUE
    ld      t0, DraftAggregate_length(a1)
    addi    t1, a1, DraftAggregate_bits
    li      t2, 0
1:  bgeu    t2, t0, 2f
    srli    t3, t2, 3
    add     t3, t1, t3
    lbu     t3, 0(t3)
    andi    t4, t2, 7
    srl     t3, t3, t4
    andi    t3, t3, 1
    beqz    t3, 3f
    add     t3, a2, t2                      # its bit at the cursor
    srli    t4, t3, 3
    add     t4, a0, t4
    andi    t3, t3, 7
    li      a3, 1
    sll     a3, a3, t3
    lbu     t3, 0(t4)
    or      t3, t3, a3
    sb      t3, 0(t4)
3:  addi    t2, t2, 1
    j       1b
2:  add     a0, a2, t0
    ret
END_FUNCTION produce_copy_bits

.if FORK >= FORK_DENEB
/*
 * L1: (the block's locals a0) -> a0 = 0, or 1 for a short out: out s5 holds the block from offset
 * 24; it becomes the BlockContents: the block moved 12 bytes on, the three offsets, the bundle's
 * proofs and blobs (the bundle at locals + 40, its bytes at + 48, of no alignment). Locals: F the
 * bundle, F+8 the blobs' offset, F+16 the proofs' bytes, F+24 the blobs' bytes.
 */
LOCAL_FUNCTION produce_contents
    FRAME 32
    ld      t0, 40(a0)                      # the bundle: its offsets of commitments, proofs, blobs
    ld      t1, 48(a0)
    li      t2, 12
    bltu    t1, t2, 9f
    LWB     t2, t0, 4, t4
    LWB     t3, t0, 8, t4
    bgtu    t2, t3, 9f
    bgtu    t3, t1, 9f
    sd      t0, 0(sp)
    sd      t3, 8(sp)
    sub     t4, t3, t2                      # the proofs' bytes, then the blobs'
    sd      t4, 16(sp)
    sub     t5, t1, t3
    sd      t5, 24(sp)
    ld      t6, 16(s5)                      # the block's
    addi    a1, t6, 12
    add     a1, a1, t4
    add     a1, a1, t5
    ld      a2, 0(s5)
    addi    a2, a2, -24
    bgtu    a1, a2, 9f
    sd      a1, 16(s5)
    addi    a3, s5, 24                      # the block on by 12, from its end
    mv      a4, t6
1:  beqz    a4, 2f
    addi    a4, a4, -1
    add     a5, a3, a4
    lbu     t1, 0(a5)
    sb      t1, 12(a5)
    j       1b
2:  li      t1, 12
    sw      t1, 0(a3)
    addi    t1, t6, 12
    sw      t1, 4(a3)
    add     t1, t1, t4
    sw      t1, 8(a3)
    addi    a0, a3, 12                      # the proofs, then the blobs
    add     a0, a0, t6
    ld      a1, 0(sp)
    add     a1, a1, t2
    mv      a2, t4
    call    lantern_copy
    ld      t0, 16(s5)
    add     a0, s5, t0
    addi    a0, a0, 24
    ld      t1, 24(sp)
    sub     a0, a0, t1
    ld      a1, 0(sp)
    ld      t1, 8(sp)
    add     a1, a1, t1
    ld      a2, 24(sp)
    call    lantern_copy
    li      a0, 0
    UNFRAME 32
9:  li      a0, 1
    UNFRAME 32
END_FUNCTION produce_contents
.endif

/* ---------------------------------------------------------------- publishBlockV2 */


/*
 * (body, json, scratch, out, facts): node.md, lantern_node_publish_decode. s1 body, s2 json, s3
 * scratch, s4 out, s5 facts, s6 the type, s7 the value's bytes, s8 their count, s9 the scratch
 * size. SSZ offsets have no alignment: byte loads. Locals: L a JsonFault (128).
 */
SPEC_FUNCTION node_publish_decode
    ENTER 128
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      s9, 0(s3)
.if FORK >= FORK_DENEB
    ADDRESS s6, lantern_type_SignedBlockContents
.else
    ADDRESS s6, lantern_type_SignedBeaconBlock
.endif
    li      t0, 24
    sd      t0, 8(s4)
    sd      zero, 16(s4)
    beqz    s2, 1f
    mv      a0, s6                          # JSON: its SSZ bytes
    mv      a1, s1
    mv      a2, s3
    mv      a3, s4
    addi    a4, sp, L
    CALL_GLOBAL lantern_json_decode
    sd      s9, 0(s3)
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 9f
    bnez    a0, 8f
    j       2f
1:  ld      t0, 8(s1)                       # SSZ: the bytes as they are
    ld      t1, 16(s1)
    ld      t2, 0(s4)
    addi    t3, t1, 24
    bltu    t2, t3, 9f
    sd      t1, 16(s4)
    addi    a0, s4, 24
    add     a1, s1, t0
    mv      a2, t1
    call    lantern_copy
2:  mv      a0, s6                          # a value of the type
    mv      a1, s4
    mv      a2, s3
    call    node_decode
    sd      s9, 0(s3)
    li      t0, 1
    beq     a0, t0, 9f
    bnez    a0, 8f
    addi    s7, s4, 24
    ld      s8, 16(s4)
.if FORK >= FORK_DENEB
    LWB     t0, s7, 0, t6                   # SignedBlockContents: the block [o0, o1), kzg_proofs [o1, o2), blobs [o2, n)
    LWB     t1, s7, 4, t6
    LWB     t2, s7, 8, t6
    add     t3, s7, t0
    LWB     t4, t3, 0, t6                   # the block's message, its body: offsets checked by the decode
    add     t4, t0, t4
    add     t3, s7, t4
    LWB     t5, t3, 80, t6
    add     t4, t4, t5                      # the body's place
    add     t3, s7, t4
    LWB     t5, t3, PB_COMMITMENTS, t6      # blob_kzg_commitments: [c0, c1) of the body
.if FORK >= FORK_ELECTRA
    LWB     a5, t3, PB_REQUESTS, t6
.else
    sub     a5, t1, t4
.endif
    sub     a5, a5, t5
    li      t6, 48
    divu    a5, a5, t6                      # the blob count
    sub     t5, t2, t1                      # the proofs' count
    divu    t5, t5, t6
.if FORK >= FORK_FULU
    li      t6, CELLS_PER_EXT_BLOB
    mul     t6, a5, t6
    bne     t5, t6, 8f
.else
    bne     t5, a5, 8f
.endif
    sub     t5, s8, t2                      # the blobs' count
    li      t6, PUB_BLOB_BYTES
    divu    t5, t5, t6
    bne     t5, a5, 8f
    sd      a5, 8(s5)
    sub     s8, t1, t0                      # the signed block to the front
    sd      s8, 16(s4)
    mv      a0, s7
    add     a1, s7, t0
    mv      a2, s8
    call    lantern_copy
.else
    sd      zero, 8(s5)
.endif
    LWB     t0, s7, 0, t6                   # facts: the slot, the blob count, 0
    add     t0, s7, t0
    LDB     t1, t0, 0, t6, t2
    sd      t1, 0(s5)
    sd      zero, 16(s5)
    li      a0, LANTERN_OK
    LEAVE 128
8:  li      a0, LANTERN_INVALID_ENCODING
    LEAVE 128
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 128
SPEC_END node_publish_decode

/*
 * (gossip, block, sidecars, level, scratch): node.md, lantern_node_publish_check. s1 gossip, s2
 * block, s3 sidecars, s4 level, s5 scratch, s6 a sidecar, s7 their end, s8 the scratch size.
 * Locals: L a Result, L+8 a root (32), L+48 execution_valid 1, L+64 the counts of seen's parts (40).
 */
SPEC_FUNCTION node_publish_check
    ENTER 112
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ld      s8, 0(s5)
    ld      t0, NodeGossip_seen(s1)         # the counts of seen's parts, for a check that fails
    ld      t1, (Seen_keys + 8)(t0)
    sd      t1, (L + 64)(sp)
    ld      t1, (Seen_bits + 8)(t0)
    sd      t1, (L + 72)(sp)
    ld      t1, (Seen_blocks + 8)(t0)
    sd      t1, (L + 80)(sp)
    ld      t1, (Seen_headers + 8)(t0)
    sd      t1, (L + 88)(sp)
    ld      t1, Seen_header_bytes(t0)
    sd      t1, (L + 96)(sp)
    li      t0, GOSSIP_BEACON_BLOCK         # the beacon_block topic's checks
    sd      t0, NodeGossip_topic(s1)
    sd      zero, NodeGossip_subnet(s1)
    mv      a0, s1
    mv      a1, s2
    mv      a2, s5
    call    publish_gossip
    bnez    a0, 99f
.if FORK >= FORK_DENEB
    beqz    s3, 5f                          # each sidecar's, on its subnet
    ld      t0, 8(s3)
    add     s6, s3, t0
    ld      t0, 16(s3)
    add     s7, s6, t0
1:  bgeu    s6, s7, 5f
    ld      t0, 8(s6)
    add     t0, s6, t0
    LDB     t1, t0, 0, t2, t3               # its index, at byte 0 of its bytes
    ld      t2, NodeGossip_config(s1)
.if FORK >= FORK_FULU
    li      t4, GOSSIP_DATA_COLUMN_SIDECAR
    LDQ     t3, t2, CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT
.elseif FORK >= FORK_ELECTRA
    li      t4, GOSSIP_BLOB_SIDECAR
    LDQ     t3, t2, CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA
.else
    li      t4, GOSSIP_BLOB_SIDECAR
    LDQ     t3, t2, CONFIG_BLOB_SIDECAR_SUBNET_COUNT
.endif
    beqz    t3, 8f
    remu    t1, t1, t3
    sd      t4, NodeGossip_topic(s1)
    sd      t1, NodeGossip_subnet(s1)
    mv      a0, s1
    mv      a1, s6
    mv      a2, s5
    call    publish_gossip
    bnez    a0, 99f
    ld      t0, 0(s6)
    add     s6, s6, t0
    j       1b
5:
.endif
    li      t0, 2                           # consensus: process_block on the parent's post-state at the slot
    bltu    s4, t0, 7f
    ADDRESS a0, lantern_type_SignedBeaconBlock
    mv      a1, s2
    mv      a2, s5
    call    node_decode
    li      t0, 1
    beq     a0, t0, 6f
    bnez    a0, 8f
    LDQ     t0, a1, SignedBeaconBlock_message
    add     s2, a1, t0                      # the block, decoded
    li      t0, 1
    sd      t0, (L + 48)(sp)
    ld      a0, NodeGossip_proposer(s1)
    mv      a1, s2
    addi    a2, sp, (L + 48)
    ld      a3, NodeGossip_config(s1)
    mv      a4, s5
    addi    a5, sp, L
    call    lantern_process_block
    bnez    a0, 4f
    ld      a0, L(sp)
    bnez    a0, 4f
    ld      a0, NodeGossip_proposer(s1)
    ld      a1, NodeGossip_config(s1)
    LDQ     a1, a1, CONFIG_STATE_CACHE
    mv      a2, s5
    addi    a3, sp, (L + 8)
    call    lantern_state_root
    bnez    a0, 4f
    ADDQ    t0, s2, BeaconBlock_state_root
    addi    t1, sp, (L + 8)
    NE32    t0, t1, 3f
    j       7f
3:  li      a0, LANTERN_INVALID_STATE_ROOT
4:  sd      s8, 0(s5)
    j       99f
7:  sd      s8, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 112
6:  sd      s8, 0(s5)
    li      a0, LANTERN_BUFFER_TOO_SMALL
    j       99f
8:  sd      s8, 0(s5)
    li      a0, LANTERN_INVALID_ENCODING
99: ld      t0, NodeGossip_seen(s1)         # a check that fails, or no room: seen as it was
    ld      t1, (L + 64)(sp)
    sd      t1, (Seen_keys + 8)(t0)
    ld      t1, (L + 72)(sp)
    sd      t1, (Seen_bits + 8)(t0)
    ld      t1, (L + 80)(sp)
    sd      t1, (Seen_blocks + 8)(t0)
    ld      t1, (L + 88)(sp)
    sd      t1, (Seen_headers + 8)(t0)
    ld      t1, (L + 96)(sp)
    sd      t1, Seen_header_bytes(t0)
    LEAVE 112
SPEC_END node_publish_check

/*
 * L1: (gossip a0, data a1, scratch a2) -> a0: LANTERN_OK when lantern_node_gossip of the data
 * holds, else its status or its result. Locals: a Result, a root (32), an index.
 */
LOCAL_FUNCTION publish_gossip
    FRAME 48
    mv      a3, sp
    addi    a4, sp, 8
    addi    a5, sp, 40
    call    lantern_node_gossip
    bnez    a0, 9f
    ld      a0, 0(sp)
9:  UNFRAME 48
END_FUNCTION publish_gossip

.if FORK >= FORK_DENEB
/*
 * (body, json, scratch, out): node.md, lantern_node_publish_sidecars. s1 body, s2 json, s3 scratch,
 * s4 out, s5 the SignedBlockContents value, s6 its block's body, s7 the blob count, s8 a sidecar or
 * a column, s9 the scratch size, s10 the stride, s2 a counter after the decode (ENTER keeps s1-s10). SSZ positions in a sidecar are not
 * all 8-aligned: lantern_copy writes them. Locals: L the signed header (208), L+208 a
 * GeneralizedIndex, L+216 a JsonFault (128), then a Branch of the commitments' list (24 + 128),
 * L+368 the KzgScratch, L+376 the cells, L+384 a blob's place.
 */
SPEC_FUNCTION node_publish_sidecars
    ENTER 400
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      s9, 0(s3)
    ld      t0, 16(s1)                      # the SSZ bytes at the end of scratch: 24 + the body's length
    addi    t0, t0, 24 + 7
    andi    t0, t0, -8
    addi    t1, t0, 64
    bgeu    t1, s9, 8f
    sub     t1, s9, t0
    sd      t1, 0(s3)
    add     s5, s3, t1
    sd      t0, 0(s5)
    li      t1, 24
    sd      t1, 8(s5)
    sd      zero, 16(s5)
    beqz    s2, 1f
    ADDRESS a0, lantern_type_SignedBlockContents    # JSON: its SSZ bytes
    mv      a1, s1
    mv      a2, s3
    mv      a3, s5
    addi    a4, sp, (L + 216)
    CALL_GLOBAL lantern_json_decode
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    bnez    a0, 9f
    j       2f
1:  ld      t0, 8(s1)                       # SSZ: the bytes as they are
    ld      a2, 16(s1)
    sd      a2, 16(s5)
    addi    a0, s5, 24
    add     a1, s1, t0
    call    lantern_copy
2:  ADDRESS a0, lantern_type_SignedBlockContents    # its value
    mv      a1, s5
    mv      a2, s3
    call    node_decode
    li      t0, 1
    beq     a0, t0, 8f
    bnez    a0, 9f
    mv      s5, a1
    PART    t0, t1, s5, SignedBlockContents_signed_block    # compute_signed_block_header
    PART    t2, t1, t0, SignedBeaconBlock_message
    ld      t1, BeaconBlock_slot(t2)
    sd      t1, L(sp)
    ld      t1, BeaconBlock_proposer_index(t2)
    sd      t1, (L + 8)(sp)
    PART    s6, t1, t2, BeaconBlock_body
    addi    a0, sp, (L + 16)
    ADDQ    a1, t2, BeaconBlock_parent_root
    COPY32  a0, a1
    addi    a0, sp, (L + 48)
    ADDQ    a1, t2, BeaconBlock_state_root
    COPY32  a0, a1
    addi    a0, sp, (L + 112)
    ADDQ    a1, t0, SignedBeaconBlock_signature
    li      a2, 96
    call    lantern_copy
    ADDRESS a0, lantern_type_BeaconBlockBody
    mv      a1, s6
    mv      a2, s3
    addi    a3, sp, (L + 80)
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 8f
    LDQ     s7, s6, BeaconBlockBody_blob_kzg_commitments + 8   # the blob count
.if FORK >= FORK_FULU
    li      t0, PUB_CELL_BYTES + 96         # the stride: a ByteList of a column sidecar of the count
    mul     t0, s7, t0
    li      t1, PUB_COLUMN_FIXED + 24 + 7
    add     t0, t0, t1
    andi    s10, t0, -8
    li      t0, NUMBER_OF_COLUMNS
    mul     t0, s10, t0
    addi    t0, t0, 24
    ld      t1, 0(s4)
    bltu    t1, t0, 8f
    li      t0, PUB_COMMITMENTS_GINDEX      # the commitments' branch, the same for each column
    sd      t0, (L + 208)(sp)
    li      t0, 24 + 32 * KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH
    sd      t0, (L + 216)(sp)
    ADDRESS a0, lantern_type_BeaconBlockBody
    mv      a1, s6
    addi    a2, sp, (L + 208)
    mv      a3, s3
    addi    a4, sp, (L + 216)
    CALL_GLOBAL ssz_build_proof
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    bnez    a0, 9f
    li      s2, 0                          # each column: its fixed part, the commitments and its proofs
3:  li      t0, NUMBER_OF_COLUMNS
    bgeu    s2, t0, 4f
    mul     t0, s2, s10
    add     s8, s4, t0
    addi    s8, s8, 24
    sd      s10, 0(s8)
    li      t0, 24
    sd      t0, 8(s8)
    li      t0, PUB_CELL_BYTES + 96
    mul     t0, s7, t0
    li      t1, PUB_COLUMN_FIXED
    add     t0, t0, t1
    sd      t0, 16(s8)
    sd      s2, 24(s8)                     # index
    li      t0, PUB_COLUMN_FIXED            # the offsets of column, kzg_commitments, kzg_proofs
    sw      t0, 32(s8)
    li      t1, PUB_CELL_BYTES
    mul     t1, s7, t1
    add     t0, t0, t1
    sw      t0, 36(s8)
    li      t1, 48
    mul     t1, s7, t1
    add     t0, t0, t1
    sw      t0, 40(s8)
    addi    a0, s8, 44                      # signed_block_header
    addi    a1, sp, L
    li      a2, PUB_HEADER_BYTES
    call    lantern_copy
    addi    a0, s8, 44 + PUB_HEADER_BYTES   # kzg_commitments_inclusion_proof
    addi    a1, sp, (L + 216 + 24)
    li      a2, 32 * KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH
    call    lantern_copy
    lwu     t0, 36(s8)                      # kzg_commitments: the body's
    add     a0, s8, t0
    addi    a0, a0, 24
    PART    a1, t1, s6, BeaconBlockBody_blob_kzg_commitments
    li      t1, 48
    mul     a2, s7, t1
    call    lantern_copy
    sd      zero, (L + 384)(sp)             # kzg_proofs: proof c of each blob
31: ld      t0, (L + 384)(sp)
    bgeu    t0, s7, 32f
    lwu     t1, 40(s8)
    add     a0, s8, t1
    addi    a0, a0, 24
    li      t2, 48
    mul     t3, t0, t2
    add     a0, a0, t3
    PART    a1, t1, s5, SignedBlockContents_kzg_proofs
    li      t2, CELLS_PER_EXT_BLOB
    mul     t3, t0, t2
    add     t3, t3, s2
    li      t2, 48
    mul     t3, t3, t2
    add     a1, a1, t3
    li      a2, 48
    call    lantern_copy
    ld      t0, (L + 384)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 384)(sp)
    j       31b
32: addi    s2, s2, 1
    j       3b
4:  ld      t0, 0(s3)                       # the cells of each blob: a KzgScratch and the cells at the end of scratch
    li      t1, CRYPTO_KZG_SCRATCH + CELLS_PER_EXT_BLOB * PUB_CELL_BYTES + 64
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    sd      t0, 0(s3)
    add     t0, s3, t0
    addi    t0, t0, 63
    andi    t0, t0, -64
    li      t1, CRYPTO_KZG_SCRATCH
    sd      t1, 0(t0)
    sd      t0, (L + 368)(sp)
    add     t0, t0, t1
    sd      t0, (L + 376)(sp)
    li      s2, 0                          # blob b: its cells, then cell c to column c's place b
5:  bgeu    s2, s7, 7f
    PART    a0, t1, s5, SignedBlockContents_blobs
    li      t0, PUB_BLOB_BYTES
    mul     t0, s2, t0
    add     a0, a0, t0
    ld      a1, (L + 368)(sp)
    ld      a2, (L + 376)(sp)
    CALL_GLOBAL crypto_kzg_compute_cells
    li      t0, CRYPTO_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    bnez    a0, 9f
    li      s8, 0
6:  li      t0, NUMBER_OF_COLUMNS
    bgeu    s8, t0, 61f
    mul     t0, s8, s10
    add     a0, s4, t0
    li      t1, 24 + 24 + PUB_COLUMN_FIXED
    add     a0, a0, t1
    li      t1, PUB_CELL_BYTES
    mul     t2, s2, t1
    add     a0, a0, t2
    mul     t2, s8, t1
    ld      a1, (L + 376)(sp)
    add     a1, a1, t2
    li      a2, PUB_CELL_BYTES
    call    lantern_copy
    addi    s8, s8, 1
    j       6b
61: addi    s2, s2, 1
    j       5b
7:  li      t0, NUMBER_OF_COLUMNS
    mul     t0, s10, t0
    sd      t0, 16(s4)
.else
    li      t0, PUB_BLOB_SIDECAR + 24       # a BlobSidecar for each blob
    mul     t0, s7, t0
    addi    t0, t0, 24
    ld      t1, 0(s4)
    bltu    t1, t0, 8f
    li      s2, 0
3:  bgeu    s2, s7, 7f
    li      t0, PUB_BLOB_SIDECAR + 24
    mul     t0, s2, t0
    add     s8, s4, t0
    addi    s8, s8, 24
    li      t0, PUB_BLOB_SIDECAR + 24
    sd      t0, 0(s8)
    li      t0, 24
    sd      t0, 8(s8)
    li      t0, PUB_BLOB_SIDECAR
    sd      t0, 16(s8)
    sd      s2, 24(s8)                     # index
    addi    a0, s8, 32                      # blob
    PART    a1, t1, s5, SignedBlockContents_blobs
    li      t0, PUB_BLOB_BYTES
    mul     t0, s2, t0
    add     a1, a1, t0
    li      a2, PUB_BLOB_BYTES
    call    lantern_copy
    ADDQ    a0, s8, 32 + PUB_BLOB_BYTES     # kzg_commitment
    PART    a1, t1, s6, BeaconBlockBody_blob_kzg_commitments
    li      t0, 48
    mul     t0, s2, t0
    add     a1, a1, t0
    li      a2, 48
    call    lantern_copy
    ADDQ    a0, s8, 32 + PUB_BLOB_BYTES + 48    # kzg_proof
    PART    a1, t1, s5, SignedBlockContents_kzg_proofs
    li      t0, 48
    mul     t0, s2, t0
    add     a1, a1, t0
    li      a2, 48
    call    lantern_copy
    li      t0, PUB_COMMITMENTS_GINDEX << 13    # the inclusion proof, its Branch header in the header's place
    add     t0, t0, s2
    sd      t0, (L + 208)(sp)
    ADDQ    a4, s8, 32 + PUB_BLOB_BYTES + 96 + PUB_HEADER_BYTES - 24
    li      t0, 24 + 32 * KZG_COMMITMENT_INCLUSION_PROOF_DEPTH
    sd      t0, 0(a4)
    ADDRESS a0, lantern_type_BeaconBlockBody
    mv      a1, s6
    addi    a2, sp, (L + 208)
    mv      a3, s3
    CALL_GLOBAL ssz_build_proof
    li      t0, SSZ_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    bnez    a0, 9f
    ADDQ    a0, s8, 32 + PUB_BLOB_BYTES + 96    # signed_block_header, over the Branch header
    addi    a1, sp, L
    li      a2, PUB_HEADER_BYTES
    call    lantern_copy
    addi    s2, s2, 1
    j       3b
7:  li      t0, PUB_BLOB_SIDECAR + 24
    mul     t0, s7, t0
    sd      t0, 16(s4)
.endif
    sd      s9, 0(s3)
    li      a0, LANTERN_OK
    LEAVE 400
8:  sd      s9, 0(s3)
    li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 400
9:  sd      s9, 0(s3)
    li      a0, LANTERN_INVALID_ENCODING
    LEAVE 400
SPEC_END node_publish_sidecars
.endif
