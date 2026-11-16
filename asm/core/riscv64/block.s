/*
 * Block processing: the header, RANDAO, eth1 data and small helpers, RISC-V.
 * Requirements: docs/reference/block-processing.md.
 */

LEAF lantern_get_beacon_proposer_index
    LDQ     a2, a0, BeaconState_slot
    andi    a2, a2, (SLOTS_PER_EPOCH - 1)
    ADDQ    a3, a0, BeaconState_proposer_lookahead
    slli    a2, a2, 3
    add     a3, a3, a2
    ld      a2, 0(a3)
    sd      a2, 0(a1)
    RETURN_OK
END_FUNCTION lantern_get_beacon_proposer_index

LEAF lantern_xor
    .irp k, 0, 8, 16, 24
    ld      a3, \k(a0)
    ld      a4, \k(a1)
    xor     a3, a3, a4
    sd      a3, \k(a2)
    .endr
    RETURN_OK
END_FUNCTION lantern_xor

/* bits a0, length a1 (pointer to the bit count), out a2. */
LEAF lantern_get_set_bit_count
    ld      a1, 0(a1)
    li      a3, 0                           # count
    li      a4, 0                           # bit
1:  bgeu    a4, a1, 2f
    srli    a5, a4, 3
    add     a5, a0, a5
    lbu     a5, 0(a5)
    andi    a6, a4, 7
    srl     a5, a5, a6
    andi    a5, a5, 1
    add     a3, a3, a5
    addi    a4, a4, 1
    j       1b
2:  sd      a3, 0(a2)
    RETURN_OK
END_FUNCTION lantern_get_set_bit_count

/*
 * s1 state, s2 block, s3 scratch, s4 result, s5 body.
 * Locals: L proposer index, L+8 latest header root, L+40 body root.
 */
FUNCTION lantern_process_block_header
    ENTER 80
    mv      s1, a0
    mv      s2, a1
    mv      s3, a3
    mv      s4, a4
    ld      t0, BeaconBlock_slot(s2)
    LDQ     t1, s1, BeaconState_slot
    li      a0, LANTERN_INVALID_BLOCK_SLOT  # assert block.slot == state.slot
    bne     t0, t1, 6f
    LDQ     t1, s1, BeaconState_latest_block_header + BeaconBlockHeader_slot
    li      a0, LANTERN_INVALID_BLOCK_OLDER # assert block.slot > state.latest_block_header.slot
    bleu    t0, t1, 6f
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_beacon_proposer_index
    ld      t0, BeaconBlock_proposer_index(s2)
    ld      t1, L(sp)
    li      a0, LANTERN_INVALID_PROPOSER_INDEX  # assert block.proposer_index == get_beacon_proposer_index(state)
    bne     t0, t1, 6f
    ADDRESS a0, lantern_type_BeaconBlockHeader
    ADDQ    a1, s1, BeaconState_latest_block_header
    mv      a2, s3
    addi    a3, sp, (L + 8)
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    addi    t0, s2, BeaconBlock_parent_root # assert block.parent_root == hash_tree_root(latest header)
    addi    t1, sp, (L + 8)
    li      a0, LANTERN_INVALID_PARENT_ROOT
    NE32    t0, t1, 6f
    PART    s5, t0, s2, BeaconBlock_body
    ADDRESS a0, lantern_type_BeaconBlockBody
    mv      a1, s5
    mv      a2, s3
    addi    a3, sp, (L + 40)
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    ADDQ    t0, s1, BeaconState_latest_block_header     # the new latest_block_header
    ld      t1, BeaconBlock_slot(s2)
    sd      t1, BeaconBlockHeader_slot(t0)
    ld      t1, BeaconBlock_proposer_index(s2)
    sd      t1, BeaconBlockHeader_proposer_index(t0)
    addi    t1, t0, BeaconBlockHeader_parent_root
    addi    t2, s2, BeaconBlock_parent_root
    COPY32  t1, t2
    .irp k, 0, 8, 16, 24
    sd      zero, (BeaconBlockHeader_state_root + \k)(t0)
    .endr
    addi    t1, t0, BeaconBlockHeader_body_root
    addi    t2, sp, (L + 40)
    COPY32  t1, t2
    ld      t0, BeaconBlock_proposer_index(s2)          # assert not proposer.slashed
    PART    t1, t2, s1, BeaconState_validators
    li      a0, LANTERN_INVALID_VALIDATOR_INDEX
    bgeu    t0, t2, 6f
    slli    t0, t0, 7
    add     t1, t1, t0
    lbu     t1, Validator_slashed(t1)
    li      a0, LANTERN_INVALID_PROPOSER_SLASHED
    bnez    t1, 6f
    sd      zero, 0(s4)
    li      a0, LANTERN_OK
7:  LEAVE 80
6:  sd      a0, 0(s4)
    li      a0, LANTERN_OK
    LEAVE 80
END_FUNCTION lantern_process_block_header
