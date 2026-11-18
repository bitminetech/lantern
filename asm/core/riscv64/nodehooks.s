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
    j       98f
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
