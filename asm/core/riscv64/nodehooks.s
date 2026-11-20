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
.if FORK >= FORK_ELECTRA
    ADDRESS a0, lantern_type_SingleAttestation
    li      t1, NODE_JSON_SINGLE_ATTESTATION
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
    j       98f
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
