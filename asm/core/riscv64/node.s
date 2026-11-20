/*
 * The node core, RISC-V: in the common object. Requirements: docs/reference/node.md.
 * The SSZ bytes inside events start 8-aligned, so their u64 and root fields at 4 mod 8 are
 * read as words.
 */

.set NODE_ROOT_ENTRY, 40                # lantern_node_step: a flag, then the root of a BLOCK event

/* reg = the node s1's ByteList of the libp2p events it queued. */
.macro P2P_OUT reg
    ld      \reg, Node_p2p_out(s1)
    add     \reg, s1, \reg
.endm

.set NODE_BLOB_HEADER, 8 + 32 * FIELD_ELEMENTS_PER_BLOB + 48 + 48   # the signed_block_header in a BlobSidecar's SSZ bytes
.set NODE_BLOB_BYTES, NODE_BLOB_HEADER + 208 + 32 * KZG_COMMITMENT_INCLUSION_PROOF_DEPTH  # the SSZ size of a BlobSidecar
.set NODE_COLUMN_HEADER, 20             # the signed_block_header in a DataColumnSidecar's SSZ bytes
.set NODE_COLUMN_FIXED, NODE_COLUMN_HEADER + 208 + 32 * KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH  # the least SSZ size of a DataColumnSidecar
.set NODE_COLUMN_BYTES, NODE_COLUMN_FIXED + MAX_BLOB_COMMITMENTS_PER_BLOCK * (BYTES_PER_FIELD_ELEMENT * FIELD_ELEMENTS_PER_CELL + 96)  # the most
.set NODE_METADATA_V3, 25               # the SSZ size of a MetaData v3
.set NODE_CUSTODY_LIST, LIST_FIXED + 8 * 128    # an IndexList of 128 custody groups
.set NODE_CUSTODY_LOCALS, 16 + NODE_CUSTODY_LIST + 8
.if NUMBER_OF_COLUMNS > 128
.error "Node_columns and NodePeer_custody hold 128 columns"
.endif

/* a0 = the fork of the slot a0 with the config a1: the last fork whose epoch is at most the slot's. Uses t0-t2. */
LOCAL_FUNCTION node_fork
    UNWIND_END_PROLOGUE
    li      t0, SLOTS_PER_EPOCH
    divu    t0, a0, t0
    li      t1, 16 * FORK_FULU
1:  beqz    t1, 2f
    add     t2, a1, t1
    ld      t2, 0(t2)
    bgeu    t0, t2, 2f
    addi    t1, t1, -16
    j       1b
2:  srli    a0, t1, 4
    ret
END_FUNCTION node_fork

/* a0 = the current slot of the store a0: (time_ms - genesis_time_ms) // SLOT_DURATION_MS, 0 before genesis. Uses t0-t2, a7. */
LOCAL_FUNCTION node_store_slot
    UNWIND_END_PROLOGUE
    ld      t0, Store_time_ms(a0)
    ld      t1, Store_genesis_time_ms(a0)
    sub     t2, t0, t1
    sltu    t0, t0, t1
    addi    t0, t0, -1
    and     t0, t2, t0
    LDQ     t1, a0, Store_config + CONFIG_SLOT_DURATION_MS
    li      a0, 0
    beqz    t1, 1f
    divu    a0, t0, t1
1:  ret
END_FUNCTION node_store_slot

/* t3 += the room a0 field times width; to 9f on overflow. Uses t0-t2. */
.macro NODE_SIZE_ADD field, width
    ld      t0, NodeRoom_\field(a0)
    li      t1, \width
    mulhu   t2, t0, t1
    bnez    t2, 9f
    mul     t0, t0, t1
    add     t0, t3, t0
    bltu    t0, t3, 9f
    mv      t3, t0
.endm

/* (room, size): NODE_FIXED + the room of each part. Uses t0-t3. */
FUNCTION lantern_node_size
    UNWIND_END_PROLOGUE
    ld      t0, NodeRoom_request_bytes(a0)  # the bytes of a stream
    srli    t1, t0, 32
    bnez    t1, 9f
    addi    t0, t0, NodeStream__fixed + 7
    andi    t1, t0, -8
    ld      t0, NodeRoom_streams(a0)
    mulhu   t2, t0, t1
    bnez    t2, 9f
    mul     t3, t0, t1
    NODE_SIZE_ADD blocks, NodeBlock__mem
    NODE_SIZE_ADD checkpoints, NodeCheckpoint__mem
    NODE_SIZE_ADD pow_blocks, POW_BLOCK_BYTES
    NODE_SIZE_ADD peers, NodePeer__mem
    NODE_SIZE_ADD messages, NodeMessage__mem
    NODE_SIZE_ADD blobs, NodeBlob__mem
    NODE_SIZE_ADD api_streams, NodeApi__mem
    NODE_SIZE_ADD pool, NodePool__mem
    NODE_SIZE_ADD proposers, NodeProposer__mem
    ld      t0, NodeRoom_p2p_out(a0)        # a ByteList
    addi    t1, t0, 24 + 7
    bltu    t1, t0, 9f
    andi    t1, t1, -8
    add     t0, t3, t1
    bltu    t0, t3, 9f
    mv      t3, t0
    ld      t0, NodeRoom_engine_bytes(a0)   # a ByteList
    addi    t1, t0, 24 + 7
    bltu    t1, t0, 9f
    andi    t1, t1, -8
    add     t0, t3, t1
    bltu    t0, t3, 9f
    mv      t3, t0
    ld      t0, NodeRoom_db_roots(a0)       # the Db: DB_FIXED, its slots, a power of two of roots
    beqz    t0, 9f
    addi    t1, t0, -1
    and     t1, t1, t0
    bnez    t1, 9f
    srli    t1, t0, 60
    bnez    t1, 9f
    slli    t0, t0, 3
    add     t0, t3, t0
    bltu    t0, t3, 9f
    mv      t3, t0
    NODE_SIZE_ADD db_slots, DbSlot__mem
    addi    t0, t3, DB_FIXED
    bltu    t0, t3, 9f
    mv      t3, t0
    li      t1, NODE_FIXED
    add     t0, t3, t1
    bltu    t0, t3, 9f
    sd      t0, 0(a1)
    li      a0, LANTERN_OK
    ret
9:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_node_size

/* The next part of the node a0 at t0; t0 += the room a1 field times width. Uses t1, t2. */
.macro NODE_PART part, field, width
    STQ     t0, a0, Node_\part
    STQ     zero, a0, Node_\part + 8
    ld      t1, NodeRoom_\field(a1)
    li      t2, \width
    mul     t1, t1, t2
    add     t0, t0, t1
.endm

/* Lay out the parts of the node a0 for the room a1 at NODE_FIXED, with no entries. Uses t0-t3. */
LOCAL_FUNCTION node_layout
    UNWIND_END_PROLOGUE
    ld      t3, NodeRoom_request_bytes(a1)
    addi    t3, t3, NodeStream__fixed + 7
    andi    t3, t3, -8
    sd      t3, Node_stream_bytes(a0)
    li      t0, NODE_FIXED
    NODE_PART blocks, blocks, NodeBlock__mem
    NODE_PART checkpoints, checkpoints, NodeCheckpoint__mem
    NODE_PART pow_blocks, pow_blocks, POW_BLOCK_BYTES
    NODE_PART peers, peers, NodePeer__mem
    sd      t0, Node_streams(a0)
    sd      zero, (Node_streams + 8)(a0)
    ld      t1, NodeRoom_streams(a1)
    mul     t1, t1, t3
    add     t0, t0, t1
    NODE_PART messages, messages, NodeMessage__mem
    NODE_PART blobs, blobs, NodeBlob__mem
    NODE_PART api, api_streams, NodeApi__mem
    NODE_PART pool, pool, NodePool__mem
    NODE_PART proposers, proposers, NodeProposer__mem
    sd      t0, Node_p2p_out(a0)            # one ByteList, empty
    li      t1, 1
    sd      t1, (Node_p2p_out + 8)(a0)
    ld      t1, NodeRoom_p2p_out(a1)
    addi    t1, t1, 24 + 7
    andi    t1, t1, -8
    add     t2, a0, t0
    sd      t1, 0(t2)
    add     t0, t0, t1
    li      t1, 24
    sd      t1, 8(t2)
    sd      zero, 16(t2)
    sd      t0, Node_engine_in(a0)          # one ByteList, empty
    li      t1, 1
    sd      t1, (Node_engine_in + 8)(a0)
    ld      t1, NodeRoom_engine_bytes(a1)
    addi    t1, t1, 24 + 7
    andi    t1, t1, -8
    add     t2, a0, t0
    sd      t1, 0(t2)
    li      t1, 24
    sd      t1, 8(t2)
    sd      zero, 16(t2)
    ld      t1, NodeRoom_engine_bytes(a1)
    addi    t1, t1, 24 + 7
    andi    t1, t1, -8
    add     t0, t0, t1
    sd      t0, Node_db(a0)                 # one Db, its size set
    li      t1, 1
    sd      t1, (Node_db + 8)(a0)
    ld      t1, NodeRoom_db_slots(a1)
    li      t2, DbSlot__mem
    mul     t1, t1, t2
    ld      t2, NodeRoom_db_roots(a1)
    slli    t2, t2, 3
    add     t1, t1, t2
    addi    t1, t1, DB_FIXED
    add     t2, a0, t0
    sd      t1, 0(t2)
    ret
END_FUNCTION node_layout

/*
 * (room, config, anchor, flags, node): a node whose one block is the anchor, imported, with
 * post-state id 1, and whose one checkpoint is (anchor epoch, anchor root) at state id 1.
 * s1 room, s2 config, s3 anchor, s4 anchor slot, s5 flags, s6 node. Locals: L the size.
 */
FUNCTION lantern_node_init
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, NodeAnchor_slot(s3)
    ld      s5, 0(a3)
    mv      s6, a4
    addi    a1, sp, L
    call    lantern_node_size
    bnez    a0, 9f
    ld      t0, 0(s6)
    ld      t1, L(sp)
    bltu    t0, t1, 8f
    ld      t0, NodeRoom_blocks(s1)         # room for the anchor
    beqz    t0, 8f
    ld      t0, NodeRoom_checkpoints(s1)
    beqz    t0, 8f
    addi    a0, s6, 8                       # the fixed fields: zero, then set
    li      a1, NODE_FIXED - 8
    call    lantern_zero
    li      t0, 2
    sd      t0, Node_next_id(s6)
    li      t0, 1
    sd      t0, Node_anchor_state_id(s6)
    sd      s5, Node_flags(s6)
    sd      s4, Node_earliest_slot(s6)
    addi    t0, s6, Node_head_root
    COPY32  t0, s3
    ADDQ    t0, s6, Node_event_head         # the events: the anchor's head and finalized epoch
    COPY32  t0, s3
    STQ     s4, s6, Node_event_slot
    li      t0, SLOTS_PER_EPOCH
    divu    t0, s4, t0
    STQ     t0, s6, Node_event_epoch
    addi    t0, s6, Node_genesis_validators_root
    addi    t1, s3, NodeAnchor_genesis_validators_root
    COPY32  t0, t1
    addi    t0, s6, Node_node_id
    addi    t1, s3, NodeAnchor_node_id
    COPY32  t0, t1
    addi    a0, s6, Node_config
    mv      a1, s2
    li      a2, CONFIG_SIZE
    call    lantern_copy
    LDQ     t0, s2, CONFIG_SAMPLES_PER_SLOT # the columns: of max(SAMPLES_PER_SLOT, CUSTODY_REQUIREMENT) groups
    LDQ     t1, s2, CONFIG_CUSTODY_REQUIREMENT
    mv      a1, t0
    bgeu    t0, t1, 2f
    mv      a1, t1
2:  addi    a0, s3, NodeAnchor_node_id
    mv      a2, s2
    addi    a3, s6, Node_columns
    call    node_custody_columns
    bnez    a0, 9f
    andi    t0, s5, NODE_FLAG_ENGINE        # the secret, the host, the first id, and a forkchoiceUpdated due
    beqz    t0, 1f
    ld      a2, NodeAnchor_engine_host_len(s3)
    li      t0, NODE_ENGINE_HOST_MAX
    bgtu    a2, t0, 7f
    sd      a2, Node_engine_host_len(s6)
    addi    a0, s6, Node_engine_host
    addi    a1, s3, NodeAnchor_engine_host
    call    lantern_copy
    addi    t0, s6, Node_jwt_secret
    addi    t1, s3, NodeAnchor_jwt_secret
    COPY32  t0, t1
    li      t0, 1
    sd      t0, Node_engine_id(s6)
    ori     t0, s5, NODE_FLAG_FCU
    sd      t0, Node_flags(s6)
1:  mv      a0, s6
    mv      a1, s1
    call    node_layout
    PART    a0, t1, s6, Node_blocks         # the anchor block
    li      a1, NodeBlock__mem
    call    lantern_zero
    PART    t0, t1, s6, Node_blocks
    COPY32  t0, s3
    sd      s4, NodeBlock_slot(t0)
    li      t1, 1
    sd      t1, NodeBlock_state_id(t0)
    li      t1, NODE_BLOCK_IMPORTED
    sd      t1, NodeBlock_status(t0)
    li      t1, 1
    sd      t1, NodeBlock_data_available(t0)
    sd      t1, (Node_blocks + 8)(s6)
    PART    t0, t1, s6, Node_checkpoints    # the anchor checkpoint
    li      t1, SLOTS_PER_EPOCH
    divu    t1, s4, t1
    sd      t1, NodeCheckpoint_epoch(t0)
    addi    t1, t0, NodeCheckpoint_root
    COPY32  t1, s3
    li      t1, 1
    sd      t1, NodeCheckpoint_state_id(t0)
    sd      t1, (Node_checkpoints + 8)(s6)
    ld      t1, NodeAnchor_history_slot(s3) # the Db: from the segment of history_slot, or of the anchor; its archive after the anchor
    mv      t0, s4
    bgeu    t1, t0, 601f
    mv      t0, t1
601: LDQ    t2, s2, CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY   # compute_min_epochs_for_block_requests
    LDQ     t3, s2, CONFIG_CHURN_LIMIT_QUOTIENT
    srli    t3, t3, 1
    add     t2, t2, t3
    bgeu    t2, t3, 602f
    li      t2, -1
602: li     t3, SLOTS_PER_EPOCH
    divu    t4, s4, t3
    li      t5, 0
    bltu    t4, t2, 603f
    sub     t5, t4, t2
    mul     t5, t5, t3
603: bgeu   t5, t0, 604f
    mv      t0, t5
604: li     t1, -DB_SEGMENT_SLOTS
    and     t0, t0, t1
    sd      t0, L(sp)
    addi    a0, s1, NodeRoom_db_slots
    addi    a1, sp, L
    ld      a2, Node_db(s6)
    add     a2, s6, a2
    call    lantern_db_init
    bnez    a0, 9f
    ld      t0, L(sp)                       # the Db's first slot: no sidecar dropped yet
    sd      t0, Node_sidecar_floor(s6)
    addi    t0, s4, 1
    sd      t0, Node_db_next_slot(s6)
    li      t0, -1
    sd      t0, Node_db_block_segment(s6)
    sd      t0, Node_db_sidecar_segment(s6)
    sd      t0, Node_backfill_segment(s6)   # the backfill: from the anchor's block down
    sd      t0, Node_backfill_sidecar_segment(s6)
    sd      t0, Node_backfill_start(s6)
    addi    t0, s4, 1
    sd      t0, Node_backfill_slot(s6)
    sd      t0, Node_backfill_next(s6)
    addi    t0, s6, Node_backfill_root
    COPY32  t0, s3
    li      a0, LANTERN_OK
9:  LEAVE 16
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
7:  li      a0, LANTERN_INVALID_EVENT
    LEAVE 16
END_FUNCTION lantern_node_init

/* Copy the entries of the part at ref of the node s1, of width bytes each, into the node s3. */
.macro NODE_COPY_PART ref, width
    PART    a1, a2, s1, \ref
    STQ     a2, s3, (\ref) + 8
    li      t0, \width
    mul     a2, a2, t0
    LDQ     a0, s3, (\ref)
    add     a0, s3, a0
    call    lantern_copy
.endm

/* Branch to 8f when the room s2 field is below the entries of the part at ref of the node s1. Uses t0, t1. */
.macro NODE_COPY_ROOM field, ref
    ld      t0, NodeRoom_\field(s2)
    LDQ     t1, s1, (\ref) + 8
    bltu    t0, t1, 8f
.endm

/*
 * (node, room, out): the node in out, with the capacities of room. s1 node, s2 room, s3 out,
 * s4 a stream, s7 the streams left, s8 the old stream bytes, s9 the new stream. Locals: L the size.
 */
FUNCTION lantern_node_copy
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      a0, s2
    addi    a1, sp, L
    call    lantern_node_size
    bnez    a0, 9f
    ld      t0, 0(s3)
    ld      t1, L(sp)
    bltu    t0, t1, 8f
    NODE_COPY_ROOM blocks, Node_blocks      # each capacity holds the entries
    NODE_COPY_ROOM checkpoints, Node_checkpoints
    NODE_COPY_ROOM pow_blocks, Node_pow_blocks
    NODE_COPY_ROOM peers, Node_peers
    NODE_COPY_ROOM streams, Node_streams
    NODE_COPY_ROOM messages, Node_messages
    NODE_COPY_ROOM blobs, Node_blobs
    NODE_COPY_ROOM api_streams, Node_api
    NODE_COPY_ROOM pool, Node_pool
    NODE_COPY_ROOM proposers, Node_proposers
    ld      t0, NodeRoom_p2p_out(s2)        # the queued bytes fit
    ld      t1, Node_p2p_out(s1)
    add     t1, s1, t1
    ld      t1, 16(t1)
    bltu    t0, t1, 8f
    ld      t0, NodeRoom_engine_bytes(s2)   # the execution engine's bytes fit
    ld      t1, Node_engine_in(s1)
    add     t1, s1, t1
    ld      t1, 16(t1)
    bltu    t0, t1, 8f
    ld      s8, Node_stream_bytes(s1)       # a stream's request bytes fit
    ld      t0, NodeRoom_request_bytes(s2)
    addi    t0, t0, NodeStream__fixed + 7
    andi    t0, t0, -8
    bltu    t0, s8, 8f
    addi    a0, s3, 8                       # the fixed fields
    addi    a1, s1, 8
    li      a2, NODE_FIXED - 8
    call    lantern_copy
    mv      a0, s3
    mv      a1, s2
    call    node_layout
    ld      a0, Node_db(s1)                 # the Db, at its new room
    add     a0, s1, a0
    addi    a1, s2, NodeRoom_db_slots
    ld      a2, Node_db(s3)
    add     a2, s3, a2
    call    lantern_db_copy
    bnez    a0, 8f
    NODE_COPY_PART Node_blocks, NodeBlock__mem      # the entries of each part
    NODE_COPY_PART Node_checkpoints, NodeCheckpoint__mem
    NODE_COPY_PART Node_pow_blocks, POW_BLOCK_BYTES
    NODE_COPY_PART Node_peers, NodePeer__mem
    NODE_COPY_PART Node_messages, NodeMessage__mem
    NODE_COPY_PART Node_blobs, NodeBlob__mem
    NODE_COPY_PART Node_api, NodeApi__mem
    NODE_COPY_PART Node_pool, NodePool__mem
    NODE_COPY_PART Node_proposers, NodeProposer__mem
    ld      a1, Node_p2p_out(s1)            # the queued bytes
    add     a1, s1, a1
    ld      a2, 16(a1)
    ld      a0, Node_p2p_out(s3)
    add     a0, s3, a0
    sd      a2, 16(a0)
    addi    a0, a0, 24
    addi    a1, a1, 24
    call    lantern_copy
    ld      a1, Node_engine_in(s1)          # the execution engine's bytes
    add     a1, s1, a1
    ld      a2, 16(a1)
    ld      a0, Node_engine_in(s3)
    add     a0, s3, a0
    sd      a2, 16(a0)
    addi    a0, a0, 24
    addi    a1, a1, 24
    call    lantern_copy
    PART    s4, s7, s1, Node_streams        # each stream, with the request room of the new stride
    sd      s7, (Node_streams + 8)(s3)
    ld      t0, Node_streams(s3)
    add     s9, s3, t0
1:  beqz    s7, 2f
    mv      a0, s9
    mv      a1, s4
    mv      a2, s8
    call    lantern_copy
    ld      t0, Node_stream_bytes(s3)
    addi    t1, t0, -NodeStream_list
    sd      t1, NodeStream_list(s9)
    add     s9, s9, t0
    add     s4, s4, s8
    addi    s7, s7, -1
    j       1b
2:  li      a0, LANTERN_OK
9:  LEAVE 16
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_node_copy

/*
 * The step's helpers read the node from s1, the store from s2, the scratch from s5 and the
 * actions from s6. An action is added at the end of the actions' bytes, whose room the step
 * checks first.
 */

/* a0 = a new action of kind a0 and a1 bytes, its size and kind written. Uses t0-t2. */
LOCAL_FUNCTION node_act
    UNWIND_END_PROLOGUE
    ld      t0, 8(s6)
    ld      t1, 16(s6)
    add     t2, s6, t0
    add     t2, t2, t1
    add     t1, t1, a1
    sd      t1, 16(s6)
    sd      a1, 0(t2)
    sd      a0, 8(t2)
    mv      a0, t2
    ret
END_FUNCTION node_act

/* a0 = a new BufferId. Uses t0. */
LOCAL_FUNCTION node_new_id
    UNWIND_END_PROLOGUE
    ld      a0, Node_next_id(s1)
    addi    t0, a0, 1
    sd      t0, Node_next_id(s1)
    ret
END_FUNCTION node_new_id

/* a0 = the index of the block whose root is at a0 (8-aligned), or 2^64 - 1; a1 = its entry. Uses t0-t2, a6, a7. */
LOCAL_FUNCTION node_find_block
    UNWIND_END_PROLOGUE
    PART    t0, t1, s1, Node_blocks
    li      t2, 0
1:  bgeu    t2, t1, 3f
    NE32    t0, a0, 2f
    mv      a0, t2
    mv      a1, t0
    ret
2:  addi    t0, t0, NodeBlock__mem
    addi    t2, t2, 1
    j       1b
3:  li      a0, -1
    ret
END_FUNCTION node_find_block

/* a0 = the index of the checkpoint (epoch a0, root at a1, 4-aligned), or 2^64 - 1; a1 = its entry. Uses t0-t3, a6, a7. */
LOCAL_FUNCTION node_find_checkpoint
    UNWIND_END_PROLOGUE
    PART    t0, t1, s1, Node_checkpoints
    li      t2, 0
1:  bgeu    t2, t1, 3f
    ld      t3, NodeCheckpoint_epoch(t0)
    bne     t3, a0, 2f
    addi    t3, t0, NodeCheckpoint_root
    NE32W   t3, a1, 2f
    mv      a0, t2
    mv      a1, t0
    ret
2:  addi    t0, t0, NodeCheckpoint__mem
    addi    t2, t2, 1
    j       1b
3:  li      a0, -1
    ret
END_FUNCTION node_find_checkpoint

/* a0 = a WORK action: kind a0, state_a a1, state_b a2, data a3, target a4, arg a5; state_c 0. Uses t0-t2. */
LOCAL_FUNCTION node_work
    UNWIND_END_PROLOGUE
    li      t0, NODE_WORK_BLOCK_ATTESTATION     # a block's vote: event_votes takes 1 more
    beq     a0, t0, 1f
    li      t0, NODE_WORK_BLOCK_SLASHING
    bne     a0, t0, 2f
1:  LDQ     t0, s1, Node_event_votes
    addi    t0, t0, 1
    STQ     t0, s1, Node_event_votes
2:  ld      t0, 8(s6)
    ld      t1, 16(s6)
    add     t2, s6, t0
    add     t2, t2, t1
    addi    t1, t1, NODE_ACT_WORK_SIZE
    sd      t1, 16(s6)
    li      t0, NODE_ACT_WORK_SIZE
    sd      t0, 0(t2)
    li      t0, NODE_ACT_WORK
    sd      t0, 8(t2)
    sd      a0, NodeAction_work_kind(t2)
    sd      a1, NodeAction_state_a(t2)
    sd      a2, NodeAction_state_b(t2)
    sd      zero, NodeAction_state_c(t2)
    sd      a3, NodeAction_data(t2)
    sd      a4, NodeAction_target(t2)
    sd      a5, NodeAction_arg(t2)
    mv      a0, t2
    ret
END_FUNCTION node_work

/* An action of kind a0 with the two ids a1 and a2 (STATE_COPY: source, new; the FREE kinds: a1). Uses t0-t2, a7. */
LOCAL_FUNCTION node_ids
    UNWIND_END_PROLOGUE
    li      t0, NODE_ACT_STATE_FREE         # a STATE_FREE of the state a validator stream reads goes to the entry: API_STREAM_OWN_STATE
    bne     a0, t0, 5f
    PART    t0, t1, s1, Node_api
4:  beqz    t1, 3f
    ld      t2, NodeApi_connection(t0)
    beqz    t2, 41f
    ld      t2, NodeApi_state(t0)
    bne     t2, a1, 41f
    ld      t2, NodeApi_flags(t0)
    srli    a7, t2, 12
    andi    a7, a7, 1
    bnez    a7, 41f                         # API_STREAM_OWN_STATE: its own state already
    li      a7, API_STREAM_OWN_STATE
    or      t2, t2, a7
    sd      t2, NodeApi_flags(t0)
    ret
41: addi    t0, t0, NodeApi__mem
    addi    t1, t1, -1
    j       4b
5:  li      t0, NODE_ACT_BYTES_FREE         # a BYTES_FREE of bytes a NodeApi entry sends goes to the entry: API_STREAM_OWN
    bne     a0, t0, 3f
    PART    t0, t1, s1, Node_pool           # bytes a pool entry keeps stay
6:  beqz    t1, 7f
    ld      t2, NodePool_topic(t0)
    beqz    t2, 61f
    ld      t2, NodePool_data_id(t0)
    bne     t2, a1, 61f
    ret
61: addi    t0, t0, NodePool__mem
    addi    t1, t1, -1
    j       6b
7:  PART    t0, t1, s1, Node_api
1:  beqz    t1, 3f
    ld      t2, NodeApi_connection(t0)
    beqz    t2, 2f
    ld      t2, NodeApi_op(t0)              # a produceBlockV3 in its folds: the pool bytes of its fold in flight
    li      a7, API_OP_PRODUCE_BLOCK_V3
    bne     t2, a7, 11f
    ld      t2, NodeApi_member(t0)
    li      a7, NODE_PRODUCE_FOLD
    bne     t2, a7, 2f
    ld      t2, NodeApi_root(t0)
    bne     t2, a1, 2f
    ld      t2, NodeApi_flags(t0)
    li      a7, API_STREAM_PRODUCE_OWN
    or      t2, t2, a7
    sd      t2, NodeApi_flags(t0)
    ret
11: ld      t2, NodeApi_data(t0)
    bne     t2, a1, 2f
    ld      t2, NodeApi_flags(t0)
    andi    a7, t2, API_STREAM_OWN
    bnez    a7, 2f                          # API_STREAM_OWN: its own bytes already
    ori     t2, t2, API_STREAM_OWN
    sd      t2, NodeApi_flags(t0)
    ret
2:  addi    t0, t0, NodeApi__mem
    addi    t1, t1, -1
    j       1b
3:
    ld      t0, 8(s6)
    ld      t1, 16(s6)
    add     t2, s6, t0
    add     t2, t2, t1
    addi    t1, t1, 32
    sd      t1, 16(s6)
    li      t0, 32
    sd      t0, 0(t2)
    sd      a0, 8(t2)
    sd      a1, 16(t2)
    sd      a2, 24(t2)
    ret
END_FUNCTION node_ids

/* ------------------------------------------------------------ the pool (node.md) */

/*
 * a0 = 1 when the bytes a1 (a2 bytes) of the topic a0, of the fork a3, join the pool: a
 * voluntary_exit, proposer_slashing, attester_slashing, bls_to_execution_change or
 * beacon_attestation (with its slot a4, committee index a5 and member a6), in the first free
 * entry, for an attestation one below 3/4 of the pool's capacity; else 0. Uses t0-t4, a7.
 */
LOCAL_FUNCTION node_pool_add
    UNWIND_END_PROLOGUE
    li      t0, GOSSIP_VOLUNTARY_EXIT
    beq     a0, t0, 1f
    li      t0, GOSSIP_PROPOSER_SLASHING
    beq     a0, t0, 1f
    li      t0, GOSSIP_ATTESTER_SLASHING
    beq     a0, t0, 1f
    li      t0, GOSSIP_BEACON_ATTESTATION
    beq     a0, t0, 1f
    li      t0, GOSSIP_SYNC_COMMITTEE
    beq     a0, t0, 1f
    li      t0, GOSSIP_BLS_TO_EXECUTION_CHANGE
    bne     a0, t0, 8f
1:  ld      t4, Node_p2p_out(s1)            # the capacity, for an attestation or a sync message 3/4 of it
    LDQ     t3, s1, Node_pool
    sub     t4, t4, t3
    li      a7, NodePool__mem
    divu    t4, t4, a7
    li      t0, GOSSIP_BEACON_ATTESTATION
    beq     a0, t0, 12f
    li      t0, GOSSIP_SYNC_COMMITTEE
    bne     a0, t0, 11f
12: slli    t3, t4, 1
    add     t4, t4, t3
    srli    t4, t4, 2
11: PART    t0, t1, s1, Node_pool
    li      t2, 0
2:  bgeu    t2, t1, 3f
    bgeu    t2, t4, 8f
    ld      t3, NodePool_topic(t0)
    beqz    t3, 4f
    addi    t0, t0, NodePool__mem
    addi    t2, t2, 1
    j       2b
3:  bgeu    t1, t4, 8f                      # past the count: one more within the capacity
    addi    t1, t1, 1
    STQ     t1, s1, Node_pool + 8
4:  sd      a0, NodePool_topic(t0)
    li      t3, NODE_POOL_KEPT
    sd      t3, NodePool_state(t0)
    sd      a1, NodePool_data_id(t0)
    sd      a2, NodePool_length(t0)
    sd      a3, NodePool_fork(t0)
    sd      zero, NodePool_slot(t0)
    sd      zero, NodePool_index(t0)
    sd      zero, NodePool_member(t0)
    li      t3, GOSSIP_BEACON_ATTESTATION   # an attestation's or a sync message's slot, index and member
    beq     a0, t3, 6f
    li      t3, GOSSIP_SYNC_COMMITTEE
    bne     a0, t3, 5f
6:  sd      a4, NodePool_slot(t0)
    sd      a5, NodePool_index(t0)
    sd      a6, NodePool_member(t0)
5:  li      a0, 1
    ret
8:  li      a0, 0
    ret
END_FUNCTION node_pool_add

/*
 * The pool entry a0 goes: it is free (topic 0), the pool's count drops past the free entries at
 * its end, and its bytes get a NODE_ACT_BYTES_FREE.
 */
LOCAL_FUNCTION node_pool_drop
    FRAME 0
    ld      a1, NodePool_data_id(a0)
    sd      zero, NodePool_topic(a0)
    PART    t0, t1, s1, Node_pool
1:  beqz    t1, 2f
    addi    t2, t1, -1
    li      t3, NodePool__mem
    mul     t3, t2, t3
    add     t3, t0, t3
    ld      t3, NodePool_topic(t3)
    bnez    t3, 2f
    mv      t1, t2
    j       1b
2:  STQ     t1, s1, Node_pool + 8
    li      a0, NODE_ACT_BYTES_FREE
    li      a2, 0
    call    node_ids
    UNFRAME 0
END_FUNCTION node_pool_drop

/*
 * At a new head, each attestation of the pool whose slot's epoch + 1 is below the epoch of the
 * store s2's slot goes, and each sync committee message whose slot + 1 is below that slot; then
 * each other entry in NODE_POOL_KEPT gets a NODE_WORK_POOL_CHECK with the head's post-state a0,
 * and takes NODE_POOL_CHECKING; with a0 = 0, none. Locals: the state, the index, the epoch, the
 * slot.
 */
LOCAL_FUNCTION node_pool_checks
    FRAME 32
    sd      a0, 0(sp)
    mv      a0, s2
    call    node_store_slot
    sd      a0, 24(sp)
    li      t0, SLOTS_PER_EPOCH
    divu    t0, a0, t0
    sd      t0, 16(sp)
    sd      zero, 8(sp)
5:  ld      a4, 8(sp)
    PART    t0, t1, s1, Node_pool
    bgeu    a4, t1, 6f
    li      t2, NodePool__mem
    mul     t2, a4, t2
    add     a0, t0, t2
    ld      t2, NodePool_topic(a0)
    li      t3, GOSSIP_SYNC_COMMITTEE       # a sync message: its slot + 1 below the store's slot
    bne     t2, t3, 71f
    ld      t2, NodePool_slot(a0)
    addi    t2, t2, 1
    ld      t3, 24(sp)
    bgeu    t2, t3, 7f
    call    node_pool_drop
    j       7f
71: li      t3, GOSSIP_BEACON_ATTESTATION
    bne     t2, t3, 7f
    ld      t2, NodePool_slot(a0)
    li      t3, SLOTS_PER_EPOCH
    divu    t2, t2, t3
    addi    t2, t2, 1
    ld      t3, 16(sp)
    bgeu    t2, t3, 7f
    call    node_pool_drop
7:  ld      t0, 8(sp)
    addi    t0, t0, 1
    sd      t0, 8(sp)
    j       5b
6:  ld      t0, 0(sp)
    beqz    t0, 9f
    sd      zero, 8(sp)
1:  ld      a4, 8(sp)
    PART    t0, t1, s1, Node_pool
    bgeu    a4, t1, 9f
    li      t2, NodePool__mem
    mul     t2, a4, t2
    add     t0, t0, t2
    ld      t2, NodePool_topic(t0)
    beqz    t2, 2f
    li      t3, GOSSIP_BEACON_ATTESTATION
    beq     t2, t3, 2f
    li      t3, GOSSIP_SYNC_COMMITTEE
    beq     t2, t3, 2f
    ld      t2, NodePool_state(t0)
    li      t3, NODE_POOL_KEPT
    bne     t2, t3, 2f
    li      t3, NODE_POOL_CHECKING
    sd      t3, NodePool_state(t0)
    li      a0, NODE_WORK_POOL_CHECK
    ld      a1, 0(sp)
    li      a2, 0
    ld      a3, NodePool_data_id(t0)
    ld      a5, NodePool_topic(t0)
    call    node_work
2:  ld      t0, 8(sp)
    addi    t0, t0, 1
    sd      t0, 8(sp)
    j       1b
9:  UNFRAME 32
END_FUNCTION node_pool_checks

/*
 * The NODE_EV_WORK_DONE a0 of a NODE_WORK_POOL_CHECK, of the entry at index target in
 * NODE_POOL_CHECKING with its bytes: LANTERN_VALID, it takes NODE_POOL_KEPT; else it goes.
 */
LOCAL_FUNCTION node_pool_check_done
    FRAME 0
    ld      t2, NodeAction_target(a0)
    PART    t0, t1, s1, Node_pool
    bgeu    t2, t1, 9f
    li      t1, NodePool__mem
    mul     t2, t2, t1
    add     t0, t0, t2
    ld      t1, NodePool_topic(t0)
    beqz    t1, 9f
    ld      t1, NodePool_state(t0)
    li      t2, NODE_POOL_CHECKING
    bne     t1, t2, 9f
    ld      t1, NodePool_data_id(t0)
    ld      t2, NodeAction_data(a0)
    bne     t1, t2, 9f
    ld      t1, NodeEvent_result(a0)
    bnez    t1, 1f
    li      t1, NODE_POOL_KEPT
    sd      t1, NodePool_state(t0)
    j       9f
1:  mv      a0, t0
    call    node_pool_drop
9:  UNFRAME 0
END_FUNCTION node_pool_check_done

/* a0 = the slot of the block of the store's finalized root, or 2^64 - 1 when the node keeps none. Uses t0-t2, a6, a7. */
LOCAL_FUNCTION node_f_slot
    FRAME 0
    addi    a0, s2, Store_finalized_checkpoint + 8
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 1f
    ld      a0, NodeBlock_slot(a1)
1:  UNFRAME 0
END_FUNCTION node_f_slot

/*
 * a0 = the post-state again of the imported block entry a0 above F's slot, or 0 (node.md): the path
 * up to its nearest ancestor with a post-state, a copy of that post-state, then for each block of the
 * path from the ancestor's child, in slot order, the copy across the fork boundaries to its slot and
 * a REPLAY work; the block takes the copy as its post-state. The path is a list at the end of
 * scratch, at most 8 bytes for each NodeBlock entry. s3 the block, s4 the list, s7 its count, s8 the
 * copy, s9 the ancestor's post-state, s10 the copy's slot. Locals: L the scratch size, L+8 an entry.
 */
LOCAL_FUNCTION node_rebuild
    ENTER 16
    mv      s3, a0
    ld      t0, 0(s5)
    sd      t0, L(sp)
    ld      t1, (Node_blocks + 8)(s1)
    slli    t1, t1, 3
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    sd      t0, 0(s5)
    add     s4, s5, t0
    li      s7, 0
    mv      a0, s3
1:  ld      t0, NodeBlock_data_id(a0)       # each block of the path keeps its bytes
    beqz    t0, 7f
    ld      t1, (Node_blocks + 8)(s1)
    bgeu    s7, t1, 7f
    slli    t2, s7, 3
    add     t2, s4, t2
    sd      a0, 0(t2)
    addi    s7, s7, 1
    addi    a0, a0, NodeBlock_parent_root
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 7f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 7f
    ld      s9, NodeBlock_state_id(a1)
    mv      a0, a1
    beqz    s9, 1b
    ld      s10, NodeBlock_slot(a1)         # the ancestor: a copy of its post-state
    call    node_new_id
    mv      s8, a0
    li      a0, NODE_ACT_STATE_COPY
    mv      a1, s9
    mv      a2, s8
    call    node_ids
2:  beqz    s7, 3f                          # each block, from the ancestor's child
    addi    s7, s7, -1
    slli    t2, s7, 3
    add     t2, s4, t2
    ld      t0, 0(t2)
    sd      t0, (L + 8)(sp)
    mv      a0, s8
    mv      a1, s9
    mv      a2, s10
    ld      a3, NodeBlock_slot(t0)
    call    node_cross
    mv      s8, a0
    ld      t0, (L + 8)(sp)
    ld      s10, NodeBlock_slot(t0)
    li      a0, NODE_WORK_REPLAY
    mv      a1, s8
    li      a2, 0
    ld      a3, NodeBlock_data_id(t0)
    li      a4, 0
    li      a5, 0
    call    node_work
    j       2b
3:  sd      s8, NodeBlock_state_id(s3)
    ld      t0, L(sp)
    sd      t0, 0(s5)
    mv      a0, s8
    LEAVE 16
7:  ld      t0, L(sp)
    sd      t0, 0(s5)
8:  li      a0, 0
    LEAVE 16
END_FUNCTION node_rebuild

/*
 * The post-states the node can rebuild go (node.md): each imported block above F's slot with a
 * post-state, other than the head and the justified root, whose slot is not the first of its epoch
 * and is NODE_STATE_KEEP_SLOTS or more before the store's, with an imported child and every imported
 * child of its epoch (with NODE_FLAG_FEW_STATES, no slot or epoch rule): a STATE_FREE, and state_id
 * 0. Then a head with no post-state above F's slot gets it again. s3 the entry, s4 the entries left,
 * s7 the store's slot, s8 F's slot, s9 a child, s10 the children. Locals: L the entries left to
 * look at.
 */
LOCAL_FUNCTION node_shed
    ENTER 16
    call    node_f_slot
    mv      s8, a0
    li      t0, -1
    beq     s8, t0, 9f
    mv      a0, s2
    call    node_store_slot
    mv      s7, a0
    PART    s3, s4, s1, Node_blocks
1:  beqz    s4, 7f
    ld      t0, NodeBlock_status(s3)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 6f
    ld      t0, NodeBlock_state_id(s3)
    beqz    t0, 6f
    ld      t0, NodeBlock_slot(s3)
    bleu    t0, s8, 6f
    ld      t1, Node_flags(s1)
    li      t2, NODE_FLAG_FEW_STATES
    and     t1, t1, t2
    bnez    t1, 11f
    andi    t1, t0, SLOTS_PER_EPOCH - 1
    beqz    t1, 6f
    addi    t1, t0, NODE_STATE_KEEP_SLOTS
    bgeu    t1, s7, 6f
11: addi    t3, s1, Node_head_root
    NE32    s3, t3, 2f
    j       6f
2:  addi    t3, s2, Store_justified_checkpoint + 8
    NE32    s3, t3, 3f
    j       6f
3:  PART    s9, t0, s1, Node_blocks         # its imported children: one at least, all of its epoch
    sd      t0, L(sp)
    li      s10, 0
4:  ld      t0, L(sp)
    beqz    t0, 5f
    addi    t0, t0, -1
    sd      t0, L(sp)
    ld      t0, NodeBlock_status(s9)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 41f
    addi    t3, s9, NodeBlock_parent_root
    NE32    t3, s3, 41f
    addi    s10, s10, 1
    ld      t1, Node_flags(s1)
    li      t2, NODE_FLAG_FEW_STATES
    and     t1, t1, t2
    bnez    t1, 41f
    ld      t0, NodeBlock_slot(s9)
    ld      t1, NodeBlock_slot(s3)
    li      t2, SLOTS_PER_EPOCH
    divu    t0, t0, t2
    divu    t1, t1, t2
    bne     t0, t1, 6f
41: addi    s9, s9, NodeBlock__mem
    j       4b
5:  beqz    s10, 6f
    li      a0, NODE_ACT_STATE_FREE
    ld      a1, NodeBlock_state_id(s3)
    li      a2, 0
    call    node_ids
    sd      zero, NodeBlock_state_id(s3)
6:  addi    s3, s3, NodeBlock__mem
    addi    s4, s4, -1
    j       1b
7:  addi    a0, s1, Node_head_root          # a head with no post-state above F's slot: it again
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 9f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 9f
    ld      t0, NodeBlock_state_id(a1)
    bnez    t0, 9f
    ld      t0, NodeBlock_slot(a1)
    bleu    t0, s8, 9f
    mv      a0, a1
    call    node_rebuild
9:  LEAVE 16
END_FUNCTION node_shed

/*
 * a0 = the id of the last copy: the copy a0 of the state of id a1, at slot a2, crosses each fork
 * boundary up to the fork of slot a3 (node.md): for each, a SLOTS work to the next fork's first
 * slot when the copy is before it, a copy of the state a1 as the upgrade's buffer, an UPGRADE work
 * and a STATE_FREE of the copy before. s3 the copy's slot, s4 the upgrade's buffer, s7 the copy,
 * s8 the state a1, s9 the fork, s10 the last fork.
 */
LOCAL_FUNCTION node_cross
    ENTER 0
    mv      s7, a0
    mv      s8, a1
    mv      s3, a2
    mv      a0, a3
    addi    a1, s1, Node_config
    call    node_fork
    mv      s10, a0
    mv      a0, s3
    addi    a1, s1, Node_config
    call    node_fork
    mv      s9, a0
1:  bgeu    s9, s10, 9f
    addi    s9, s9, 1
    slli    t0, s9, 4                       # the next fork's first slot
    add     t0, s1, t0
    ld      t0, Node_config(t0)
    li      t1, SLOTS_PER_EPOCH
    mul     t0, t0, t1
    bgeu    s3, t0, 2f
    mv      s3, t0
    li      a0, NODE_WORK_SLOTS
    mv      a1, s7
    li      a2, 0
    li      a3, 0
    li      a4, 0
    mv      a5, s3
    call    node_work
2:  call    node_new_id                     # the upgrade's buffer: a copy of the state
    mv      s4, a0
    li      a0, NODE_ACT_STATE_COPY
    mv      a1, s8
    mv      a2, s4
    call    node_ids
    li      a0, NODE_WORK_UPGRADE
    mv      a1, s7
    mv      a2, s4
    li      a3, 0
    li      a4, 0
    mv      a5, s9
    call    node_work
    li      a0, NODE_ACT_STATE_FREE
    mv      a1, s7
    li      a2, 0
    call    node_ids
    mv      s7, s4
    j       1b
9:  mv      a0, s7
    LEAVE 0
END_FUNCTION node_cross

/*
 * a0 = the state id of the checkpoint state of (epoch a0, root at a1, 8-aligned), or 0 when the
 * root's block has no post-state: a new checkpoint is a copy of that post-state and a
 * TARGET_STATE work. s3 epoch, s4 root, s7 the new id, s8 the block's state id.
 */
LOCAL_FUNCTION node_checkpoint_state
    ENTER 0
    mv      s3, a0
    mv      s4, a1
    call    node_find_checkpoint
    li      t0, -1
    beq     a0, t0, 1f
    ld      a0, NodeCheckpoint_state_id(a1)
    LEAVE 0
1:  mv      a0, s4                          # the root's block, imported
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 9f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 9f
    ld      s8, NodeBlock_state_id(a1)      # no post-state: above F's slot, rebuilt first; an ancestor of F keeps none
    bnez    s8, 2f
    mv      s10, a1
    call    node_f_slot
    ld      t0, NodeBlock_slot(s10)
    bleu    t0, a0, 9f
    mv      a0, s10
    call    node_rebuild
    mv      s8, a0
    beqz    s8, 9f
    mv      a1, s10
2:  ld      s9, NodeBlock_slot(a1)
    call    node_new_id
    mv      s7, a0
    li      a0, NODE_ACT_STATE_COPY
    mv      a1, s8
    mv      a2, s7
    call    node_ids
    mv      a0, s7                          # across the forks to the epoch's first slot
    mv      a1, s8
    mv      a2, s9
    li      t0, SLOTS_PER_EPOCH
    mul     a3, s3, t0
    call    node_cross
    mv      s7, a0
    call    node_new_checkpoint             # the entry
    mv      t1, a0
    sd      s3, NodeCheckpoint_epoch(t0)
    addi    t2, t0, NodeCheckpoint_root
    COPY32  t2, s4
    sd      s7, NodeCheckpoint_state_id(t0)
    li      a0, NODE_WORK_TARGET_STATE
    mv      a1, s7
    li      a2, 0
    li      a3, 0
    mv      a4, t1
    mv      a5, s3
    call    node_work
    mv      a0, s7
    LEAVE 0
9:  li      a0, 0
    LEAVE 0
END_FUNCTION node_checkpoint_state

/* A JUSTIFIED_STATE work for store.justified_checkpoint, unless one is queued. */
LOCAL_FUNCTION node_justified
    ENTER 0
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_JUSTIFIED_PENDING
    bnez    t0, 9f
    LDQ     a0, s2, Store_justified_checkpoint      # a Checkpoint: the epoch, then the root at 8
    ADDQ    a1, s2, Store_justified_checkpoint + 8
    call    node_checkpoint_state
    beqz    a0, 9f
    mv      a1, a0
    li      a0, NODE_WORK_JUSTIFIED_STATE
    li      a2, 0
    li      a3, 0
    li      a4, 0
    li      a5, 0
    call    node_work
    ld      t0, Node_flags(s1)
    ori     t0, t0, NODE_FLAG_JUSTIFIED_PENDING
    sd      t0, Node_flags(s1)
9:  LEAVE 0
END_FUNCTION node_justified

/*
 * The import of the block of index a0 when its parent has a post-state; a block whose parent is
 * invalid becomes invalid. With NODE_FLAG_ENGINE a block of bellatrix or later takes
 * NODE_BLOCK_PAYLOAD instead: its import waits for engine_newPayload. s3 index, s4 entry.
 */
LOCAL_FUNCTION node_try_import
    ENTER 0
    mv      s3, a0
    PART    s4, t0, s1, Node_blocks
    li      t0, NodeBlock__mem
    mul     t0, s3, t0
    add     s4, s4, t0
    addi    a0, s4, NodeBlock_parent_root
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 9f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_INVALID
    beq     t0, t1, 8f
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 9f
    ld      t0, NodeBlock_state_id(a1)      # no post-state: above F's slot, rebuilt at the import; else an ancestor of F, no descendant of it
    bnez    t0, 2f
    ld      s8, NodeBlock_slot(a1)
    call    node_f_slot
    bleu    s8, a0, 8f
2:  ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_ENGINE
    beqz    t0, 1f
    ld      a0, NodeBlock_slot(s4)
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_BELLATRIX
    bltu    a0, t0, 1f
    li      t0, NODE_BLOCK_PAYLOAD
    sd      t0, NodeBlock_status(s4)
    sd      zero, NodeBlock_retry(s4)
    LEAVE 0
1:  ld      t0, Node_flags(s1)              # VALID, or NOT_VALIDATED with NODE_FLAG_OPTIMISTIC
    andi    t0, t0, NODE_FLAG_OPTIMISTIC
    li      a1, PAYLOAD_STATUS_VALID
    beqz    t0, 2f
    li      a1, PAYLOAD_STATUS_NOT_VALIDATED
2:  mv      a0, s3
    call    node_import_now
    LEAVE 0
8:  li      t0, NODE_BLOCK_INVALID
    sd      t0, NodeBlock_status(s4)
9:  LEAVE 0
END_FUNCTION node_try_import

/*
 * The import of the block of index a0, whose parent is imported, with the payload status a1: a
 * copy of the parent's post-state and an IMPORT_BLOCK work. s3 index, s4 entry, s8 the parent's
 * state id.
 */
LOCAL_FUNCTION node_import_now
    ENTER 0
    mv      s3, a0
    PART    s4, t0, s1, Node_blocks
    li      t0, NodeBlock__mem
    mul     t0, s3, t0
    add     s4, s4, t0
    sd      a1, NodeBlock_payload_status(s4)
    addi    a0, s4, NodeBlock_parent_root
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 9f
    ld      s8, NodeBlock_state_id(a1)      # no post-state above F's slot: rebuilt first
    bnez    s8, 2f
    mv      s10, a1
    call    node_f_slot
    ld      t0, NodeBlock_slot(s10)
    bleu    t0, a0, 8f
    mv      a0, s10
    call    node_rebuild
    mv      s8, a0
    beqz    s8, 8f
    mv      a1, s10
2:  ld      s9, NodeBlock_slot(a1)
    call    node_new_id
    sd      a0, NodeBlock_state_id(s4)
    mv      a2, a0
    li      a0, NODE_ACT_STATE_COPY
    mv      a1, s8
    call    node_ids
    ld      a0, NodeBlock_state_id(s4)      # across the forks from the parent's slot to the block's
    mv      a1, s8
    mv      a2, s9
    ld      a3, NodeBlock_slot(s4)
    call    node_cross
    sd      a0, NodeBlock_state_id(s4)
    li      t0, NODE_BLOCK_IMPORTING
    sd      t0, NodeBlock_status(s4)
    li      a0, NODE_WORK_IMPORT_BLOCK
    ld      a1, NodeBlock_state_id(s4)
    li      a2, 0
    ld      a3, NodeBlock_data_id(s4)
    mv      a4, s3
    li      a5, 0
    call    node_work
9:  LEAVE 0
8:  li      t0, NODE_BLOCK_INVALID          # its parent is an ancestor of the finalized block
    sd      t0, NodeBlock_status(s4)
    li      a0, NODE_ACT_BYTES_FREE
    ld      a1, NodeBlock_data_id(s4)
    li      a2, 0
    call    node_ids
    sd      zero, NodeBlock_data_id(s4)
    LEAVE 0
END_FUNCTION node_import_now

/* a0 = the index of the store's node whose root is at a0 (8-aligned), or 2^64 - 1; a1 = its entry. Uses t0-t2, a6, a7. */
LOCAL_FUNCTION node_store_find
    UNWIND_END_PROLOGUE
    PART    t0, t1, s2, Store_blocks
    li      t2, 0
1:  bgeu    t2, t1, 3f
    NE32    t0, a0, 2f
    mv      a0, t2
    mv      a1, t0
    ret
2:  addi    t0, t0, BlockNode__mem
    addi    t2, t2, 1
    j       1b
3:  li      a0, -1
    ret
END_FUNCTION node_store_find

/*
 * With NODE_FLAG_ENGINE, the next engine call when none is in flight and the store's slot is at
 * least engine_wait: a NEW_PAYLOAD work for the first block in NODE_BLOCK_PAYLOAD whose retry is
 * at most the slot, else with NODE_FLAG_FCU from bellatrix on a FORKCHOICE work. s3 an entry,
 * s4 the count, s7 the slot, s8 the index.
 */
LOCAL_FUNCTION node_engine_next
    ENTER 0
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_ENGINE
    beqz    t0, 9f
    ld      t0, Node_engine_method(s1)
    bnez    t0, 9f
    mv      a0, s2
    call    node_store_slot
    mv      s7, a0
    ld      t0, Node_engine_wait(s1)
    bltu    s7, t0, 9f
    call    node_produce_engine             # a produceBlockV3 waiting for its payload goes first
    bnez    a0, 9f
    PART    s3, s4, s1, Node_blocks
    li      s8, 0
1:  bgeu    s8, s4, 3f
    ld      t0, NodeBlock_status(s3)
    li      t1, NODE_BLOCK_PAYLOAD
    bne     t0, t1, 2f
    ld      t0, NodeBlock_retry(s3)
    bgtu    t0, s7, 2f
    li      t0, NODE_BLOCK_EXECUTING
    sd      t0, NodeBlock_status(s3)
    li      t0, ENGINE_METHOD_NEW_PAYLOAD
    sd      t0, Node_engine_method(s1)
    sd      s8, Node_engine_target(s1)
    ld      a5, Node_engine_id(s1)
    addi    t0, a5, 1
    sd      t0, Node_engine_id(s1)
    li      a0, NODE_WORK_NEW_PAYLOAD
    li      a1, 0
    li      a2, 0
    ld      a3, NodeBlock_data_id(s3)
    mv      a4, s8
    call    node_work
    LEAVE 0
2:  addi    s3, s3, NodeBlock__mem
    addi    s8, s8, 1
    j       1b
3:  mv      a0, s7                          # a payload's preparation, when it is due
    call    node_prepare
    bnez    a0, 9f
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_FCU
    beqz    t0, 9f
    mv      a0, s7
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_BELLATRIX
    bltu    a0, t0, 9f
    ld      t0, Node_flags(s1)
    andi    t0, t0, ~NODE_FLAG_FCU
    sd      t0, Node_flags(s1)
    li      t0, ENGINE_METHOD_FORKCHOICE_UPDATED
    sd      t0, Node_engine_method(s1)
    sd      zero, Node_engine_target(s1)
    ld      a5, Node_engine_id(s1)
    addi    t0, a5, 1
    sd      t0, Node_engine_id(s1)
    li      a0, NODE_WORK_FORKCHOICE
    li      a1, 0
    li      a2, 0
    li      a3, 0
    li      a4, 0
    call    node_work
9:  LEAVE 0
END_FUNCTION node_engine_next

/*
 * The preparation of a payload for slot a0 + 1, a0 the store's slot, when it is due (node.md,
 * Payload preparation): a copy of the head's post-state at that slot, a PREPARE_PAYLOAD work of
 * it with the next engine id, and the copy's STATE_FREE. a0 = 1 when it went, else 0. s3 the
 * head's entry, s4 the copy, s7 the store's slot, s8 the slot, s9 the copy's slot, s10 a fork.
 */
LOCAL_FUNCTION node_prepare
    ENTER 0
    mv      s7, a0
    addi    s8, a0, 1
    mv      a0, s8
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_BELLATRIX
    bltu    a0, t0, 8f
    li      t0, SLOTS_PER_EPOCH             # a proposers entry past the store's epoch
    divu    t1, s7, t0
    PART    t2, t3, s1, Node_proposers
1:  beqz    t3, 8f
    ld      t4, NodeProposer_until_epoch(t2)
    bgtu    t4, t1, 2f
    addi    t2, t2, NodeProposer__mem
    addi    t3, t3, -1
    j       1b
2:  addi    a0, s1, Node_head_root          # the head's block, with its post-state
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 8f
    mv      s3, a1
    ld      t0, NodeBlock_state_id(s3)
    beqz    t0, 8f
    ld      t0, NodeBlock_slot(s3)          # a head of the slot, or the slot's attestation due time
    beq     t0, s7, 3f
    ld      t0, (Node_config + CONFIG_SLOT_DURATION_MS)(s1)
    ld      t1, (Node_config + CONFIG_ATTESTATION_DUE_BPS)(s1)
    mul     t2, s7, t0
    mul     t1, t0, t1
    li      t3, 10000
    divu    t1, t1, t3
    add     t2, t2, t1
    ld      t3, Store_genesis_time_ms(s2)
    add     t2, t2, t3
    ld      t0, Node_time_ms(s1)
    bltu    t0, t2, 8f
3:  LDQ     t0, s1, Node_payload_slot       # not this slot on this head yet
    bne     t0, s8, 4f
    ADDQ    t0, s1, Node_payload_root
    addi    t1, s1, Node_head_root
    NE32    t0, t1, 4f
    j       8f
4:  mv      a0, s8
    li      a1, 0
    call    node_prepare_go
    LEAVE 0
8:  li      a0, 0
    LEAVE 0
END_FUNCTION node_prepare

/*
 * L1: with no engine call in flight, the call of the first produceBlockV3 entry in
 * NODE_PRODUCE_PAYLOAD (node.md, Block production): a GET_PAYLOAD of payload_id when the payload
 * of its slot on the head is NODE_PAYLOAD_READY; else a forced preparation of its slot, once (a
 * second that ends with no payloadId: 500). a0 = 1 when a call went. s3 an entry, s4 its index,
 * s7 the count.
 */
LOCAL_FUNCTION node_produce_engine
    ENTER 0
    PART    s3, s7, s1, Node_api
    li      s4, 0
1:  bgeu    s4, s7, 8f
    ld      t0, NodeApi_connection(s3)
    beqz    t0, 2f
    ld      t0, NodeApi_op(s3)
    li      t1, API_OP_PRODUCE_BLOCK_V3
    bne     t0, t1, 2f
    ld      t0, NodeApi_member(s3)
    li      t1, NODE_PRODUCE_PAYLOAD
    beq     t0, t1, 3f
2:  addi    s3, s3, NodeApi__mem
    addi    s4, s4, 1
    j       1b
3:  LDQ     t0, s1, Node_payload_slot       # the payload of its slot on the head
    ld      t1, NodeApi_slot(s3)
    bne     t0, t1, 6f
    ADDQ    t0, s1, Node_payload_root
    addi    t1, s1, Node_head_root
    NE32    t0, t1, 6f
    LDQ     t0, s1, Node_payload_status
    li      t1, NODE_PAYLOAD_READY
    beq     t0, t1, 4f
    ld      t0, NodeApi_flags(s3)           # no payloadId: a preparation of its own, else 500
    li      t1, API_STREAM_PRODUCE_FORCED
    and     t0, t0, t1
    beqz    t0, 6f
    mv      a0, s3
    li      a1, 500
    call    node_produce_fail
    li      a0, 0
    LEAVE 0
4:  ld      t0, NodeApi_flags(s3)           # busy with its getPayload
    ori     t0, t0, API_STREAM_BUSY
    sd      t0, NodeApi_flags(s3)
    li      t0, ENGINE_METHOD_GET_PAYLOAD
    sd      t0, Node_engine_method(s1)
    sd      s4, Node_engine_target(s1)
    ld      a5, Node_engine_id(s1)
    addi    t0, a5, 1
    sd      t0, Node_engine_id(s1)
    li      a0, NODE_WORK_GET_PAYLOAD
    li      a1, 0
    li      a2, 0
    li      a3, 0
    mv      a4, s4
    call    node_work
    li      a0, 1
    LEAVE 0
6:  ld      t0, NodeApi_flags(s3)
    li      t1, API_STREAM_PRODUCE_FORCED
    or      t0, t0, t1
    sd      t0, NodeApi_flags(s3)
    ld      a0, NodeApi_slot(s3)
    li      a1, 1
    call    node_prepare_go
    bnez    a0, 7f
    mv      a0, s3
    li      a1, 500
    call    node_produce_fail
    li      a0, 0
    LEAVE 0
7:  li      a0, 1
    LEAVE 0
8:  li      a0, 0
    LEAVE 0
END_FUNCTION node_produce_engine

/*
 * L1: the preparation of a payload for slot a0 on the head (node.md, Payload preparation), forced
 * with a1 = 1 (a fee recipient of zero bytes when the proposer has none): a copy of the head's
 * post-state at that slot, a PREPARE_PAYLOAD work of it with the next engine id and a1 as its
 * target, and the copy's STATE_FREE; it is the call in flight. a0 = 1 when it went, 0 with no head
 * post-state. s3 the head's entry, s4 the copy, s7 forced, s8 the slot, s9 the copy's slot, s10 a
 * fork.
 */
LOCAL_FUNCTION node_prepare_go
    ENTER 0
    mv      s8, a0
    mv      s7, a1
    addi    a0, s1, Node_head_root
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 8f
    mv      s3, a1
    ld      t0, NodeBlock_state_id(s3)
    beqz    t0, 8f
    STQ     s8, s1, Node_payload_slot
    ADDQ    t0, s1, Node_payload_root
    addi    t1, s1, Node_head_root
    COPY32  t0, t1
    li      t0, NODE_PAYLOAD_PREPARING
    STQ     t0, s1, Node_payload_status
    li      t0, ENGINE_METHOD_FORKCHOICE_UPDATED
    sd      t0, Node_engine_method(s1)
    li      t0, 1
    sd      t0, Node_engine_target(s1)
    call    node_new_id                     # the copy, across the fork boundaries to the slot
    mv      s4, a0
    mv      a2, a0
    li      a0, NODE_ACT_STATE_COPY
    ld      a1, NodeBlock_state_id(s3)
    call    node_ids
    mv      a0, s4
    ld      a1, NodeBlock_state_id(s3)
    ld      a2, NodeBlock_slot(s3)
    mv      a3, s8
    call    node_cross
    mv      s4, a0
    ld      s9, NodeBlock_slot(s3)          # its slot: the first of the slot's fork, when it crossed one
    mv      a0, s9
    addi    a1, s1, Node_config
    call    node_fork
    mv      s10, a0
    mv      a0, s8
    addi    a1, s1, Node_config
    call    node_fork
    bleu    a0, s10, 5f
    slli    t0, a0, 4
    add     t0, s1, t0
    ld      t0, Node_config(t0)
    li      t1, SLOTS_PER_EPOCH
    mul     t0, t0, t1
    bleu    t0, s9, 5f
    mv      s9, t0
5:  bleu    s8, s9, 6f
    li      a0, NODE_WORK_SLOTS
    mv      a1, s4
    li      a2, 0
    li      a3, 0
    li      a4, 0
    mv      a5, s8
    call    node_work
6:  ld      a5, Node_engine_id(s1)          # the work, of the call's id
    addi    t0, a5, 1
    sd      t0, Node_engine_id(s1)
    li      a0, NODE_WORK_PREPARE_PAYLOAD
    mv      a1, s4
    li      a2, 0
    li      a3, 0
    mv      a4, s7
    call    node_work
    li      a0, NODE_ACT_STATE_FREE
    mv      a1, s4
    li      a2, 0
    call    node_ids
    li      a0, 1
    LEAVE 0
8:  li      a0, 0
    LEAVE 0
END_FUNCTION node_prepare_go

/*
 * The engine call in flight failed: an engine_newPayload's block takes NODE_BLOCK_PAYLOAD with
 * retry the store's slot + 1, an engine_forkchoiceUpdated sets NODE_FLAG_FCU again; engine_wait
 * becomes the slot + 1 and the call ends.
 */
LOCAL_FUNCTION node_engine_failed
    ENTER 0
    mv      a0, s2
    call    node_store_slot
    addi    a0, a0, 1
    sd      a0, Node_engine_wait(s1)
    ld      t0, Node_engine_method(s1)
    sd      zero, Node_engine_method(s1)
    li      t1, ENGINE_METHOD_FORKCHOICE_UPDATED
    bne     t0, t1, 1f
    ld      t0, Node_flags(s1)
    ori     t0, t0, NODE_FLAG_FCU
    sd      t0, Node_flags(s1)
    ld      t0, Node_engine_target(s1)      # a preparation's: again
    beqz    t0, 9f
    STQ     zero, s1, Node_payload_slot
    STQ     zero, s1, Node_payload_status
    LEAVE 0
1:  li      t1, ENGINE_METHOD_GET_PAYLOAD   # a getPayload's entry: 500
    bne     t0, t1, 2f
    ld      a0, Node_engine_target(s1)
    call    node_produce_fail_at
    LEAVE 0
2:  li      t1, ENGINE_METHOD_NEW_PAYLOAD
    bne     t0, t1, 9f
    ld      a0, Node_engine_target(s1)
    call    node_payload_retry
9:  LEAVE 0
END_FUNCTION node_engine_failed

/* L1: the produceBlockV3 entry at index a0, while it waits for its payload: 500. */
LOCAL_FUNCTION node_produce_fail_at
    FRAME 0
    PART    t0, t1, s1, Node_api
    bgeu    a0, t1, 9f
    li      t1, NodeApi__mem
    mul     a0, a0, t1
    add     a0, t0, a0
    ld      t1, NodeApi_connection(a0)
    beqz    t1, 9f
    ld      t1, NodeApi_op(a0)
    li      t2, API_OP_PRODUCE_BLOCK_V3
    bne     t1, t2, 9f
    ld      t1, NodeApi_member(a0)
    li      t2, NODE_PRODUCE_PAYLOAD
    bne     t1, t2, 9f
    li      a1, 500
    call    node_produce_fail
9:  UNFRAME 0
END_FUNCTION node_produce_fail_at

/*
 * L2: the engine_getPayload body a0 (a ByteList in scratch s5, which stays short) with its
 * EngineResponse a1, for the produceBlockV3 entry at engine_target in NODE_PRODUCE_PAYLOAD: its
 * result decoded by lantern_node_payload_result into a BYTES_PUT action, whose id the entry keeps
 * as filter_index before its fold; a result that does not decode: 500, and the action goes. s3
 * the body, s4 the entry, s7 the action, s8 its size. Locals: L a JsonFault (128).
 */
LOCAL_FUNCTION node_produce_payload
    ENTER 128
    mv      s3, a0
    ld      t0, Node_engine_target(s1)
    PART    s4, t1, s1, Node_api
    bgeu    t0, t1, 9f
    li      t1, NodeApi__mem
    mul     t0, t0, t1
    add     s4, s4, t0
    ld      t0, NodeApi_connection(s4)
    beqz    t0, 9f
    ld      t0, NodeApi_op(s4)
    li      t1, API_OP_PRODUCE_BLOCK_V3
    bne     t0, t1, 9f
    ld      t0, NodeApi_member(s4)
    li      t1, NODE_PRODUCE_PAYLOAD
    bne     t0, t1, 9f
    ld      t0, NodeApi_flags(s4)           # its call is done; the connection closed meanwhile: the entry ends
    andi    t0, t0, ~API_STREAM_BUSY
    sd      t0, NodeApi_flags(s4)
    andi    t0, t0, API_STREAM_GONE
    beqz    t0, 1f
    mv      a0, s4
    call    node_produce_release
    mv      a0, s4
    call    node_api_end
    LEAVE 128
1:  ld      t0, EngineResponse_result_offset(a1)    # the body becomes the result's bytes
    ld      t1, EngineResponse_result_length(a1)
    ld      t2, 8(s3)
    add     t2, t2, t0
    sd      t2, 8(s3)
    sd      t1, 16(s3)
    li      t0, (48 + 1024 + 7)             # the action: room for the SSZ bytes, at most the text's + 1024
    add     s8, t1, t0
    andi    s8, s8, -8
    li      a0, NODE_ACT_BYTES_PUT
    mv      a1, s8
    call    node_act
    mv      s7, a0
    call    node_new_id
    sd      a0, 16(s7)
    addi    t0, s8, -24
    sd      t0, 24(s7)
    li      t0, 24
    sd      t0, 32(s7)
    sd      zero, 40(s7)
    ld      a0, NodeApi_slot(s4)
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s3
    mv      a1, s5
    addi    a2, s7, 24
    addi    a3, sp, L
    FORK_CALL_BELLATRIX node_payload_result
    bnez    a0, 8f
    ld      t0, 16(s7)                      # the entry keeps the result, then folds
    sd      t0, NodeApi_filter_index(s4)
    li      t0, NODE_PRODUCE_FOLD
    sd      t0, NodeApi_member(s4)
    sd      zero, NodeApi_filter_slot(s4)
    mv      a0, s4
    call    node_produce_next
    LEAVE 128
8:  ld      t0, 16(s6)                      # no result: the action goes, and 500
    sub     t0, t0, s8
    sd      t0, 16(s6)
    mv      a0, s4
    li      a1, 500
    call    node_produce_fail
9:  LEAVE 128
END_FUNCTION node_produce_payload

/* The block of index a0, if NODE_BLOCK_EXECUTING, takes NODE_BLOCK_PAYLOAD with retry the store's slot + 1. s3 the entry. */
LOCAL_FUNCTION node_payload_retry
    ENTER 0
    PART    s3, t0, s1, Node_blocks
    bgeu    a0, t0, 9f
    li      t0, NodeBlock__mem
    mul     t0, a0, t0
    add     s3, s3, t0
    ld      t0, NodeBlock_status(s3)
    li      t1, NODE_BLOCK_EXECUTING
    bne     t0, t1, 9f
    li      t0, NODE_BLOCK_PAYLOAD
    sd      t0, NodeBlock_status(s3)
    mv      a0, s2
    call    node_store_slot
    addi    a0, a0, 1
    sd      a0, NodeBlock_retry(s3)
9:  LEAVE 0
END_FUNCTION node_payload_retry

/*
 * latestValidHash (optimistic-sync.md) from the store's node a0: up its chain by parent, each node
 * whose block_hash is not the hash at a1 gets store_payload_status INVALIDATED, until the node
 * with that hash; a zero hash stops at the first zero block_hash. With a1 0 (null), or a hash the
 * chain does not have, only the node a2 (2^64 - 1 for none) gets it. s3 a node, s4 the hash, s7
 * the node found, s8 the node a2. Locals: L a node, L+8 a status, L+16 a result.
 */
LOCAL_FUNCTION node_lvh
    ENTER 32
    mv      s3, a0
    mv      s4, a1
    mv      s8, a2
    beqz    s4, 5f
    mv      s7, s3                          # the node of the hash, up the chain
1:  PART    t0, t1, s2, Store_blocks
    bgeu    s7, t1, 5f
    li      t1, BlockNode__mem
    mul     t1, s7, t1
    add     t0, t0, t1
    addi    t1, t0, BlockNode_block_hash
    NE32    t1, s4, 2f
    j       3f
2:  ld      s7, BlockNode_parent(t0)
    j       1b
3:  beq     s3, s7, 9f                      # found at s7: each node from s3 below it
    sd      s3, L(sp)
    li      t0, PAYLOAD_STATUS_INVALIDATED
    sd      t0, (L + 8)(sp)
    mv      a0, s2
    addi    a1, sp, L
    addi    a2, sp, L + 8
    addi    a3, sp, L + 16
    call    lantern_store_payload_status
    PART    t0, t1, s2, Store_blocks
    li      t1, BlockNode__mem
    mul     t1, s3, t1
    add     t0, t0, t1
    ld      s3, BlockNode_parent(t0)
    j       3b
5:  li      t0, -1                          # null, or not found: the node in question
    beq     s8, t0, 9f
    sd      s8, L(sp)
    li      t0, PAYLOAD_STATUS_INVALIDATED
    sd      t0, (L + 8)(sp)
    mv      a0, s2
    addi    a1, sp, L
    addi    a2, sp, L + 8
    addi    a3, sp, L + 16
    call    lantern_store_payload_status
9:  LEAVE 32
END_FUNCTION node_lvh

/* The first a1 bytes of the ByteList a0 (engine_in) leave it. */
LOCAL_FUNCTION node_engine_consume
    FRAME 0
    ld      t0, 16(a0)
    sub     a2, t0, a1
    sd      a2, 16(a0)
    addi    a0, a0, 24
    add     a1, a0, a1
    call    lantern_copy
    UNFRAME 0
END_FUNCTION node_engine_consume

/*
 * The bytes of engine_in: a whole HTTP response of the call in flight ends it. s3 engine_in, s4
 * the method, s7 the scratch size, restored on return, s8 the body's ByteList, s9 a block entry.
 * Locals: L an HttpResponse (16), L+16 eof, L+24 the method, L+32 an EngineResponse (112), L+144 a
 * node, L+152 a status.
 */
LOCAL_FUNCTION node_engine_read
    ENTER 160
    ld      s3, Node_engine_in(s1)
    add     s3, s1, s3
    ld      s4, Node_engine_method(s1)
    beqz    s4, 8f                          # no call in flight: the bytes go
    ld      s7, 0(s5)
    ld      t0, 16(s3)                      # the body's ByteList at the end of scratch, as long as the bytes
    addi    t0, t0, 24 + 7
    andi    t0, t0, -8
    bltu    s7, t0, 7f
    sub     t1, s7, t0
    sd      t1, 0(s5)
    add     s8, s5, t1
    sd      t0, 0(s8)
    li      t0, 24
    sd      t0, 8(s8)
    sd      zero, 16(s8)
    sd      zero, (L + 16)(sp)
    mv      a0, s3
    addi    a1, sp, L + 16
    mv      a2, s8
    addi    a3, sp, L
    call    lantern_http_parse_response
    li      t0, LANTERN_HTTP_MORE
    beq     a0, t0, 6f
    bnez    a0, 7f
    ld      t0, Node_flags(s1)              # a whole response: the engine is online
    andi    t0, t0, ~NODE_FLAG_EL_OFFLINE
    sd      t0, Node_flags(s1)
    ld      t0, L(sp)
    li      t1, 200
    bne     t0, t1, 70f
    sd      s4, (L + 24)(sp)
    mv      a0, s8
    addi    a1, sp, L + 24
    addi    a2, sp, L + 32
    call    lantern_engine_parse_response
    bnez    a0, 70f
    ld      t0, (L + 32 + EngineResponse_error)(sp)
    bnez    t0, 70f
    ld      t0, Node_engine_id(s1)
    addi    t0, t0, -1
    ld      t1, (L + 32 + EngineResponse_id)(sp)
    bne     t0, t1, 70f
    mv      a0, s3
    ld      a1, (L + 8)(sp)
    call    node_engine_consume
    li      t0, ENGINE_METHOD_GET_PAYLOAD   # engine_getPayload: its result, decoded with the body still in scratch
    bne     s4, t0, 44f
    mv      a0, s8
    addi    a1, sp, (L + 32)
    call    node_produce_payload
    sd      s7, 0(s5)
    sd      zero, Node_engine_method(s1)
    j       9f
44: sd      s7, 0(s5)
    sd      zero, Node_engine_method(s1)    # the call ends
    ld      s10, (L + 32 + EngineResponse_status)(sp)
    li      t0, ENGINE_METHOD_NEW_PAYLOAD
    bne     s4, t0, 40f
    ld      a0, Node_engine_target(s1)      # engine_newPayload: its block
    PART    s9, t0, s1, Node_blocks
    bgeu    a0, t0, 9f
    li      t0, NodeBlock__mem
    mul     t0, a0, t0
    add     s9, s9, t0
    ld      t0, NodeBlock_status(s9)
    li      t1, NODE_BLOCK_EXECUTING
    bne     t0, t1, 9f
    li      t0, ENGINE_STATUS_VALID
    bne     s10, t0, 20f
    li      a1, PAYLOAD_STATUS_VALID        # VALID: the import
    call    node_import_now
    j       9f
20: li      t0, ENGINE_STATUS_SYNCING
    beq     s10, t0, 21f
    li      t0, ENGINE_STATUS_ACCEPTED
    bne     s10, t0, 30f
21: addi    a0, s9, NodeBlock_parent_root   # SYNCING, ACCEPTED: optimistic when a candidate
    call    node_store_find
    li      t0, -1
    beq     a0, t0, 23f
    ld      t0, BlockNode_block_hash(a1)
    ld      t1, (BlockNode_block_hash + 8)(a1)
    or      t0, t0, t1
    ld      t1, (BlockNode_block_hash + 16)(a1)
    or      t0, t0, t1
    ld      t1, (BlockNode_block_hash + 24)(a1)
    or      t0, t0, t1
    bnez    t0, 22f
23: mv      a0, s2
    call    node_store_slot
    ld      t0, NodeBlock_slot(s9)
    li      t1, SAFE_SLOTS_TO_IMPORT_OPTIMISTICALLY
    add     t0, t0, t1
    bleu    t0, a0, 22f
    ld      a0, Node_engine_target(s1)      # no candidate: again in a later slot
    call    node_payload_retry
    j       9f
22: ld      a0, Node_engine_target(s1)
    li      a1, PAYLOAD_STATUS_NOT_VALIDATED
    call    node_import_now
    j       9f
30: li      t0, NODE_BLOCK_INVALID          # INVALID, INVALID_BLOCK_HASH: the block is invalid, latestValidHash from its parent
    sd      t0, NodeBlock_status(s9)
    li      a0, NODE_ACT_BYTES_FREE
    ld      a1, NodeBlock_data_id(s9)
    li      a2, 0
    call    node_ids
    sd      zero, NodeBlock_data_id(s9)
    addi    a0, s9, NodeBlock_parent_root
    call    node_store_find
    li      t0, -1
    beq     a0, t0, 9f
    ld      t0, (L + 32 + EngineResponse_has_latest_valid_hash)(sp)
    li      a1, 0
    beqz    t0, 31f
    addi    a1, sp, L + 32 + EngineResponse_latest_valid_hash
31: li      a2, -1
    call    node_lvh
    j       9f
40: ld      t0, Node_engine_target(s1)      # engine_forkchoiceUpdated of a preparation: its payloadId
    beqz    t0, 42f
    ld      t0, (L + 32 + EngineResponse_has_payload_id)(sp)
    li      t1, NODE_PAYLOAD_NONE
    beqz    t0, 43f
    ld      t2, (L + 32 + EngineResponse_payload_id)(sp)
    STQ     t2, s1, Node_payload_id
    li      t1, NODE_PAYLOAD_READY
43: STQ     t1, s1, Node_payload_status
42: addi    a0, s1, Node_head_root          # engine_forkchoiceUpdated: of the head
    call    node_store_find
    li      t0, -1
    beq     a0, t0, 9f
    sd      a0, (L + 144)(sp)
    li      t0, ENGINE_STATUS_VALID
    bne     s10, t0, 41f
    li      t0, PAYLOAD_STATUS_VALID
    sd      t0, (L + 152)(sp)
    mv      a0, s2
    addi    a1, sp, L + 144
    addi    a2, sp, L + 152
    addi    a3, sp, L + 16
    call    lantern_store_payload_status
    j       9f
41: li      t0, ENGINE_STATUS_INVALID
    beq     s10, t0, 42f
    li      t0, ENGINE_STATUS_INVALID_BLOCK_HASH
    bne     s10, t0, 9f
42: ld      a0, (L + 144)(sp)
    mv      a2, a0
    ld      t0, (L + 32 + EngineResponse_has_latest_valid_hash)(sp)
    li      a1, 0
    beqz    t0, 43f
    addi    a1, sp, L + 32 + EngineResponse_latest_valid_hash
43: call    node_lvh
9:  LEAVE 160
6:  sd      s7, 0(s5)                       # part of a response: more bytes
    LEAVE 160
70: mv      a0, s3                          # a failed call, its response read
    ld      a1, (L + 8)(sp)
    call    node_engine_consume
7:  sd      s7, 0(s5)
    call    node_engine_failed
8:  ld      t0, Node_engine_in(s1)          # the bytes left go
    add     t0, s1, t0
    sd      zero, 16(t0)
    LEAVE 160
END_FUNCTION node_engine_read

/* The import of each waiting block whose parent is the block of the entry a0. s3 the root, s4 index. */
LOCAL_FUNCTION node_children
    ENTER 0
    mv      s3, a0
    li      s4, 0
1:  ld      t0, (Node_blocks + 8)(s1)
    bgeu    s4, t0, 9f
    PART    t0, t1, s1, Node_blocks
    li      t1, NodeBlock__mem
    mul     t1, s4, t1
    add     t0, t0, t1
    ld      t1, NodeBlock_status(t0)
    li      t2, NODE_BLOCK_WAITING
    bne     t1, t2, 2f
    addi    t1, t0, NodeBlock_parent_root
    NE32    t1, s3, 2f
    mv      a0, s4
    call    node_try_import
2:  addi    s4, s4, 1
    j       1b
9:  LEAVE 0
END_FUNCTION node_children

/* a0 = the index, t0 = the zeroed entry, of a NODE_BLOCK_FREE block or a new one at the end. Uses t1, t2. */
LOCAL_FUNCTION node_new_block
    UNWIND_END_PROLOGUE
    PART    t0, t1, s1, Node_blocks
    li      a0, 0
1:  bgeu    a0, t1, 2f
    ld      t2, NodeBlock_status(t0)
    addi    t2, t2, -NODE_BLOCK_FREE
    beqz    t2, 3f
    addi    t0, t0, NodeBlock__mem
    addi    a0, a0, 1
    j       1b
2:  addi    t1, t1, 1
    sd      t1, (Node_blocks + 8)(s1)
3:  mv      t1, t0
    li      t2, NodeBlock__mem / 8
4:  sd      zero, 0(t1)
    addi    t1, t1, 8
    addi    t2, t2, -1
    bnez    t2, 4b
    ret
END_FUNCTION node_new_block

/* a0 = the index, t0 = the zeroed entry, of a NODE_BLOB_FREE sidecar or a new one at the end. Uses t1, t2. */
LOCAL_FUNCTION node_new_blob
    UNWIND_END_PROLOGUE
    PART    t0, t1, s1, Node_blobs
    li      a0, 0
1:  bgeu    a0, t1, 2f
    ld      t2, NodeBlob_status(t0)
    addi    t2, t2, -NODE_BLOB_FREE
    beqz    t2, 3f
    addi    t0, t0, NodeBlob__mem
    addi    a0, a0, 1
    j       1b
2:  addi    t1, t1, 1
    sd      t1, (Node_blobs + 8)(s1)
3:  mv      t1, t0
    li      t2, NodeBlob__mem / 8
4:  sd      zero, 0(t1)
    addi    t1, t1, 8
    addi    t2, t2, -1
    bnez    t2, 4b
    ret
END_FUNCTION node_new_blob

/* a0 = the index, t0 = the zeroed entry, of a free checkpoint (epoch 2^64 - 1) or a new one at the end. Uses t1, t2. */
LOCAL_FUNCTION node_new_checkpoint
    UNWIND_END_PROLOGUE
    PART    t0, t1, s1, Node_checkpoints
    li      a0, 0
1:  bgeu    a0, t1, 2f
    ld      t2, NodeCheckpoint_epoch(t0)
    addi    t2, t2, 1
    beqz    t2, 3f
    addi    t0, t0, NodeCheckpoint__mem
    addi    a0, a0, 1
    j       1b
2:  addi    t1, t1, 1
    sd      t1, (Node_checkpoints + 8)(s1)
3:  mv      t1, t0
    li      t2, NodeCheckpoint__mem / 8
4:  sd      zero, 0(t1)
    addi    t1, t1, 8
    addi    t2, t2, -1
    bnez    t2, 4b
    ret
END_FUNCTION node_new_checkpoint

/* a0 = 1 when a stream that serves lists the BufferId a0 at or after its next, else 0. Uses t0-t4. */
LOCAL_FUNCTION node_serving
    UNWIND_END_PROLOGUE
    beqz    a0, 9f
    PART    t0, t1, s1, Node_streams
1:  beqz    t1, 9f
    ld      t2, NodeStream_state(t0)
    li      t3, NODE_STREAM_SERVE
    beq     t2, t3, 2f
    li      t3, NODE_STREAM_SERVING
    bne     t2, t3, 4f
2:  ld      t2, NodeStream_next(t0)
    ld      t3, (NodeStream_list + 16)(t0)
    srli    t3, t3, 3
3:  bgeu    t2, t3, 4f
    slli    t4, t2, 3
    add     t4, t0, t4
    ld      t4, NodeStream_request(t4)
    beq     t4, a0, 8f
    addi    t2, t2, 1
    j       3b
4:  ld      t2, Node_stream_bytes(s1)
    add     t0, t0, t2
    addi    t1, t1, -1
    j       1b
8:  li      a0, 1
    ret
9:  li      a0, 0
    ret
END_FUNCTION node_serving

/*
 * At a new finalized epoch of the store, lantern_store_prune; then the node keeps the finalized
 * block, the blocks of the store, and the bytes and sidecars of the finalized block's ancestors.
 * Their states go, and so do the other branches, the invalid and waiting blocks at or below the
 * finalized slot, and the checkpoints below the finalized epoch. Bytes a stream sends stay until
 * a later prune. s3 the finalized block, s4 its slot, s7 i, s8 an entry.
 */
LOCAL_FUNCTION node_prune
    ENTER 0
    ld      t0, Store_finalized_checkpoint(s2)
    ld      t1, Node_pruned_epoch(s1)
    bleu    t0, t1, 99f
    mv      a0, s2
    mv      a1, s5
    call    lantern_store_prune
    bnez    a0, 99f
    ld      t0, Store_finalized_checkpoint(s2)
    sd      t0, Node_pruned_epoch(s1)
    addi    a0, s2, Store_finalized_checkpoint + 8
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 99f
    mv      s3, a1
    ld      s4, NodeBlock_slot(s3)
    ld      t0, NodeBlock_status(s3)        # F with no post-state: it again first, while its ancestors keep theirs
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 5f
    ld      t0, NodeBlock_state_id(s3)
    bnez    t0, 5f
    mv      a0, s3
    call    node_rebuild
5:  addi    a0, s3, NodeBlock_parent_root   # its ancestors: their states go
1:  call    node_find_block
    li      t0, -1
    beq     a0, t0, 2f
    mv      s8, a1
    ld      t0, NodeBlock_status(s8)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 2f
    ld      a1, NodeBlock_state_id(s8)      # each, through those with none
    beqz    a1, 4f
    li      a0, NODE_ACT_STATE_FREE
    li      a2, 0
    call    node_ids
    sd      zero, NodeBlock_state_id(s8)
4:  addi    a0, s8, NodeBlock_parent_root
    j       1b
2:  mv      a0, s3                          # with NODE_FLAG_DB, the archive
    call    node_archive
    li      s7, 0                           # each other block
3:  ld      t0, (Node_blocks + 8)(s1)
    bgeu    s7, t0, 20f
    PART    s8, t0, s1, Node_blocks
    li      t0, NodeBlock__mem
    mul     t0, s7, t0
    add     s8, s8, t0
    beq     s8, s3, 19f
    ld      t0, NodeBlock_status(s8)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 10f
    ld      t0, NodeBlock_state_id(s8)
    bnez    t0, 12f
    ld      t0, NodeBlock_slot(s8)          # none above the finalized slot: a descendant, or another branch
    bgtu    t0, s4, 12f
    ld      t0, Node_flags(s1)              # an ancestor: its bytes stay, but those in the Db go
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 19f
    ld      t0, NodeBlock_slot(s8)
    ld      t1, Node_db_next_slot(s1)
    bgeu    t0, t1, 19f
    ld      a0, NodeBlock_data_id(s8)
    call    node_serving
    bnez    a0, 19f
    j       15f
12: mv      a0, s8
    call    node_store_find                 # a descendant: in the store
    li      t0, -1
    bne     a0, t0, 19f
    ld      a0, NodeBlock_data_id(s8)       # another branch: its state and bytes go
    call    node_serving
    bnez    a0, 19f
    ld      a1, NodeBlock_state_id(s8)
    beqz    a1, 15f
    li      a0, NODE_ACT_STATE_FREE
    li      a2, 0
    call    node_ids
    j       15f
10: li      t1, NODE_BLOCK_INVALID          # invalid or waiting, at or below the finalized slot
    beq     t0, t1, 11f
    li      t1, NODE_BLOCK_WAITING
    beq     t0, t1, 11f
    li      t1, NODE_BLOCK_BLOBS
    beq     t0, t1, 11f
    li      t1, NODE_BLOCK_PAYLOAD
    bne     t0, t1, 19f
11: ld      t0, NodeBlock_slot(s8)
    bgtu    t0, s4, 19f
    ld      a0, NodeBlock_data_id(s8)
    call    node_serving
    bnez    a0, 19f
15: ld      a1, NodeBlock_data_id(s8)       # the bytes go, and the entry is free
    beqz    a1, 16f
    li      a0, NODE_ACT_BYTES_FREE
    li      a2, 0
    call    node_ids
16: li      t0, -1
    sd      t0, 0(s8)
    sd      t0, 8(s8)
    sd      t0, 16(s8)
    sd      t0, 24(s8)
    sd      t0, 32(s8)
    sd      t0, 40(s8)
    sd      t0, 48(s8)
    sd      t0, 56(s8)
    sd      t0, NodeBlock_slot(s8)
    sd      zero, NodeBlock_data_id(s8)
    sd      zero, NodeBlock_state_id(s8)
    li      t0, NODE_BLOCK_FREE
    sd      t0, NodeBlock_status(s8)
19: addi    s7, s7, 1
    j       3b
20: li      s7, 0                           # each sidecar: invalid, or at or below the finalized slot and of no kept block
21: ld      t0, (Node_blobs + 8)(s1)
    bgeu    s7, t0, 30f
    PART    s8, t0, s1, Node_blobs
    slli    t0, s7, 6
    add     s8, s8, t0
    ld      t0, NodeBlob_status(s8)
    li      t1, NODE_BLOB_INVALID
    beq     t0, t1, 26f
    li      t1, NODE_BLOB_VALID
    bne     t0, t1, 29f
    ld      t0, NodeBlob_slot(s8)
    bgtu    t0, s4, 29f
    mv      a0, s8
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 25f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_BACKFILL         # of a block of the backfill: it stays for it
    beq     t0, t1, 29f
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 25f
    ld      t0, Node_flags(s1)              # of a kept block: but those in the Db go
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 29f
    ld      t0, NodeBlob_slot(s8)
    ld      t1, Node_db_next_slot(s1)
    bgeu    t0, t1, 29f
25: ld      a0, NodeBlob_data_id(s8)
    call    node_serving
    bnez    a0, 29f
    li      a0, NODE_ACT_BYTES_FREE
    ld      a1, NodeBlob_data_id(s8)
    li      a2, 0
    call    node_ids
26: li      t0, -1
    sd      t0, 0(s8)
    sd      t0, 8(s8)
    sd      t0, 16(s8)
    sd      t0, 24(s8)
    sd      t0, NodeBlob_slot(s8)
    sd      zero, NodeBlob_data_id(s8)
    li      t0, NODE_BLOB_FREE
    sd      t0, NodeBlob_status(s8)
29: addi    s7, s7, 1
    j       21b
30: li      s7, 0                           # each checkpoint below the finalized epoch: its state goes; the anchor's goes with the anchor block
31: ld      t0, (Node_checkpoints + 8)(s1)
    bgeu    s7, t0, 99f
    PART    s8, t0, s1, Node_checkpoints
    li      t0, NodeCheckpoint__mem
    mul     t0, s7, t0
    add     s8, s8, t0
    ld      t0, NodeCheckpoint_epoch(s8)
    ld      t1, Store_finalized_checkpoint(s2)
    bgeu    t0, t1, 39f
    ld      a1, NodeCheckpoint_state_id(s8)
    ld      t0, Node_anchor_state_id(s1)
    beq     a1, t0, 32f
    beqz    a1, 32f
    li      a0, NODE_ACT_STATE_FREE
    li      a2, 0
    call    node_ids
32: li      t0, -1
    sd      t0, NodeCheckpoint_epoch(s8)
    sd      t0, NodeCheckpoint_root(s8)
    sd      t0, (NodeCheckpoint_root + 8)(s8)
    sd      t0, (NodeCheckpoint_root + 16)(s8)
    sd      t0, (NodeCheckpoint_root + 24)(s8)
    sd      zero, NodeCheckpoint_state_id(s8)
39: addi    s7, s7, 1
    j       31b
99: LEAVE 0
END_FUNCTION node_prune

/* dst = the DbSlot of slot slot in the node's Db; to fail outside first_slot to end_slot. Uses t0, t1. */
.macro DB_SLOT dst, slot, fail
    ld      t0, Node_db(s1)
    add     t0, s1, t0
    ld      t1, Db_end_slot(t0)
    bgeu    \slot, t1, \fail
    ld      t1, Db_first_slot(t0)
    bltu    \slot, t1, \fail
    sub     t1, \slot, t1
    li      \dst, DbSlot__mem
    mul     t1, t1, \dst
    ld      \dst, Db_slots(t0)
    add     \dst, \dst, t1
    add     \dst, t0, \dst
.endm

/* a0 = the DbSlot of slot a0 in the node's Db when it holds a block of that slot, else 0. Uses t0-t3. */
LOCAL_FUNCTION node_db_slot
    UNWIND_END_PROLOGUE
    DB_SLOT t3, a0, 9f
    ld      t0, DbSlot_block(t3)
    beqz    t0, 9f
    mv      a0, t3
    ret
9:  li      a0, 0
    ret
END_FUNCTION node_db_slot

/* a0 = the NODE_DB_REF of the Db record of the block of slot a0, or 0. Uses t0-t3. */
LOCAL_FUNCTION node_db_block
    UNWIND_END_PROLOGUE
    DB_SLOT t2, a0, 9f
    ld      t3, DbSlot_block(t2)
    beqz    t3, 9f
    addi    t3, t3, -1
    srli    t0, a0, DB_SEGMENT_SHIFT
    slli    t0, t0, 48
    or      a0, t3, t0
    li      t0, 1
    slli    t0, t0, 63
    or      a0, a0, t0
    ret
9:  li      a0, 0
    ret
END_FUNCTION node_db_block

/*
 * a0 = the NODE_DB_REF of the Db record of the sidecar of index a1 of slot a0, or 0: at the
 * slot's first sidecar record, plus its size times the slot's indices below a1. Uses t0-t6.
 */
LOCAL_FUNCTION node_db_sidecar
    UNWIND_END_PROLOGUE
    li      t0, DB_SIDECAR_INDICES
    bgeu    a1, t0, 9f
    DB_SLOT t2, a0, 9f
    ld      t3, DbSlot_indices(t2)
    ld      t4, (DbSlot_indices + 8)(t2)
    li      t0, 64
    bgeu    a1, t0, 1f
    srl     t5, t3, a1
    andi    t5, t5, 1
    beqz    t5, 9f
    li      t5, 1
    sll     t5, t5, a1
    addi    t5, t5, -1
    and     t3, t3, t5
    li      t4, 0
    j       2f
1:  addi    t6, a1, -64
    srl     t5, t4, t6
    andi    t5, t5, 1
    beqz    t5, 9f
    li      t5, 1
    sll     t5, t5, t6
    addi    t5, t5, -1
    and     t4, t4, t5
2:  li      t6, 0                           # the indices below it
3:  beqz    t3, 4f
    addi    t5, t3, -1
    and     t3, t3, t5
    addi    t6, t6, 1
    j       3b
4:  beqz    t4, 5f
    addi    t5, t4, -1
    and     t4, t4, t5
    addi    t6, t6, 1
    j       4b
5:  ld      t3, DbSlot_sidecars(t2)
    addi    t3, t3, -1
    ld      t4, DbSlot_sidecar_end(t2)
    sub     t4, t4, t3
    ld      t5, DbSlot_sidecar_count(t2)
    divu    t4, t4, t5
    mul     t4, t4, t6
    add     t3, t3, t4
    srli    t0, a0, DB_SEGMENT_SHIFT
    slli    t0, t0, 48
    or      a0, t3, t0
    li      t0, 3
    slli    t0, t0, 62
    or      a0, a0, t0
    ret
9:  li      a0, 0
    ret
END_FUNCTION node_db_sidecar

/* A DB_APPEND action: sidecars a0, BufferId a1, segment a2, offset a3, the DbRecord at a4 (8-aligned). Uses t0-t3. */
LOCAL_FUNCTION node_db_append
    UNWIND_END_PROLOGUE
    ld      t0, 8(s6)
    ld      t1, 16(s6)
    add     t2, s6, t0
    add     t2, t2, t1
    addi    t1, t1, NODE_ACT_DB_APPEND_SIZE
    sd      t1, 16(s6)
    li      t0, NODE_ACT_DB_APPEND_SIZE
    sd      t0, 0(t2)
    li      t0, NODE_ACT_DB_APPEND
    sd      t0, 8(t2)
    sd      a1, 16(t2)
    sd      a2, 24(t2)
    sd      a0, 32(t2)
    sd      a3, 40(t2)
    li      t1, 0
1:  add     t0, a4, t1
    ld      t0, 0(t0)
    add     t3, t2, t1
    sd      t0, 48(t3)
    addi    t1, t1, 8
    li      t0, DbRecord__mem
    bltu    t1, t0, 1b
    ret
END_FUNCTION node_db_append

/*
 * L0: a0 = the end of the block segment a0: db_block_end for db_block_segment, else backfill_end
 * for backfill_segment, else 0, a new segment. Uses t1 only.
 */
LOCAL_FUNCTION node_seg_end
    UNWIND_END_PROLOGUE
    ld      t1, Node_db_block_segment(s1)
    bne     a0, t1, 1f
    ld      a0, Node_db_block_end(s1)
    ret
1:  ld      t1, Node_backfill_segment(s1)
    bne     a0, t1, 2f
    ld      a0, Node_backfill_end(s1)
    ret
2:  li      a0, 0
    ret
END_FUNCTION node_seg_end

/* L0: the NodeBlock entry a0 is free: its bytes go (a BYTES_FREE), root and parent_root all 0xff bytes. Locals: sp+0 the entry. */
LOCAL_FUNCTION node_free_block
    FRAME 16
    sd      a0, 0(sp)
    ld      a1, NodeBlock_data_id(a0)
    beqz    a1, 1f
    li      a0, NODE_ACT_BYTES_FREE
    li      a2, 0
    call    node_ids
1:  ld      a0, 0(sp)
    li      t0, -1
    sd      t0, 0(a0)
    sd      t0, 8(a0)
    sd      t0, 16(a0)
    sd      t0, 24(a0)
    sd      t0, 32(a0)
    sd      t0, 40(a0)
    sd      t0, 48(a0)
    sd      t0, 56(a0)
    sd      t0, NodeBlock_slot(a0)
    sd      zero, NodeBlock_data_id(a0)
    sd      zero, NodeBlock_state_id(a0)
    li      t0, NODE_BLOCK_FREE
    sd      t0, NodeBlock_status(a0)
    UNFRAME 16
END_FUNCTION node_free_block

/*
 * With NODE_FLAG_DB, the backfill's blocks join the Db (node.md): while a block in
 * NODE_BLOCK_BACKFILL has the root backfill_root and a slot below backfill_slot, its record at the
 * end of the segment of its slot and a DB_APPEND; backfill_slot and backfill_root follow; the entry
 * is free. Then, with no backfill stream and no block in NODE_BLOCK_BF_CHECKING, the blocks left in
 * NODE_BLOCK_BACKFILL go, and the last request is weighed. s3 an entry, s4 the entries left, s7
 * its segment. Locals: L a DbRecord (80), L+80 the offset.
 */
LOCAL_FUNCTION node_backfill_link
    ENTER 96
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 99f
1:  PART    s3, s4, s1, Node_blocks         # the next block of the chain
2:  beqz    s4, 20f
    ld      t0, NodeBlock_status(s3)
    li      t1, NODE_BLOCK_BACKFILL
    bne     t0, t1, 3f
    ld      t0, NodeBlock_slot(s3)
    ld      t1, Node_backfill_slot(s1)
    bgeu    t0, t1, 3f
    addi    t2, s1, Node_backfill_root
    NE32    s3, t2, 3f
    j       4f
3:  addi    s3, s3, NodeBlock__mem
    addi    s4, s4, -1
    j       2b
4:  mv      a0, s3                          # its sidecars first: else it waits, and the link ends
    call    node_lacks_sidecars
    bnez    a0, 20f
    li      t0, DB_BLOCK                    # its record
    sd      t0, L(sp)
    ld      t0, NodeBlock_slot(s3)
    sd      t0, (L + 8)(sp)
    sd      zero, (L + 16)(sp)
    addi    t1, sp, L + 24
    COPY32  t1, s3
    ld      t0, NodeBlock_length(s3)
    sd      t0, (L + 72)(sp)
    addi    t1, t0, 24
    sd      t1, (L + 56)(sp)
    li      t1, 24
    sd      t1, (L + 64)(sp)
    ld      s7, NodeBlock_slot(s3)
    srli    s7, s7, DB_SEGMENT_SHIFT
    mv      a0, s7
    call    node_seg_end
    sd      a0, (L + 80)(sp)
    ld      a0, Node_db(s1)
    add     a0, s1, a0
    addi    a1, sp, L
    addi    a2, sp, L + 80
    call    lantern_db_add
    bnez    a0, 99f                         # no room, or refused: until the next step
    li      a0, 0
    ld      a1, NodeBlock_data_id(s3)
    mv      a2, s7
    ld      a3, (L + 80)(sp)
    addi    a4, sp, L
    call    node_db_append
    ld      t0, (L + 72)(sp)                # the segment's new end, for each writer of it
    addi    t0, t0, DbRecord__mem + 7
    andi    t0, t0, -8
    ld      t1, (L + 80)(sp)
    add     t1, t1, t0
    sd      s7, Node_backfill_segment(s1)
    sd      t1, Node_backfill_end(s1)
    ld      t2, Node_db_block_segment(s1)
    bne     t2, s7, 5f
    sd      t1, Node_db_block_end(s1)
5:  mv      a0, s3                          # its sidecars
    li      a1, 1
    call    node_db_sidecars
    ld      t0, NodeBlock_slot(s3)
    sd      t0, Node_backfill_slot(s1)
    ld      t1, Node_earliest_slot(s1)
    bgeu    t0, t1, 51f
    sd      t0, Node_earliest_slot(s1)
51:
    addi    t1, s1, Node_backfill_root
    addi    t2, s3, NodeBlock_parent_root
    COPY32  t1, t2
    mv      a0, s3
    call    node_free_block
    j       1b
20: ld      t0, Node_backfill_handle(s1)    # no stream and no check left: the rest are of no chain
    bnez    t0, 99f
    PART    s3, s4, s1, Node_blocks
21: beqz    s4, 22f
    ld      t0, NodeBlock_status(s3)
    li      t1, NODE_BLOCK_BF_CHECKING
    beq     t0, t1, 99f
    addi    s3, s3, NodeBlock__mem
    addi    s4, s4, -1
    j       21b
22: PART    s3, s4, s1, Node_blobs          # and no sidecar check below backfill_slot
    ld      t2, Node_backfill_slot(s1)
221: beqz   s4, 223f
    ld      t0, NodeBlob_status(s3)
    li      t1, NODE_BLOB_VERIFYING
    bne     t0, t1, 222f
    ld      t0, NodeBlob_slot(s3)
    bltu    t0, t2, 99f
222: addi   s3, s3, NodeBlob__mem
    addi    s4, s4, -1
    j       221b
223: ld     s4, (Node_streams + 8)(s1)      # and no sidecar request of the node open
    ld      s3, Node_streams(s1)
    add     s3, s1, s3
224: beqz   s4, 23f
    ld      t0, NodeStream_state(s3)
    li      t1, NODE_STREAM_OPENING
    bltu    t0, t1, 225f
    ld      t0, NodeStream_method(s3)
    li      t1, REQRESP_BLOB_SIDECARS_BY_RANGE
    beq     t0, t1, 99f
    li      t1, REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE
    beq     t0, t1, 99f
225: ld     t0, Node_stream_bytes(s1)
    add     s3, s3, t0
    addi    s4, s4, -1
    j       224b
23: PART    s3, s4, s1, Node_blocks
24: beqz    s4, 26f
    ld      t0, NodeBlock_status(s3)
    li      t1, NODE_BLOCK_BACKFILL
    bne     t0, t1, 25f
    mv      a0, s3
    call    node_free_block
25: addi    s3, s3, NodeBlock__mem
    addi    s4, s4, -1
    j       24b
26: ld      t0, Node_backfill_start(s1)     # the last request, weighed
    li      t1, -1
    beq     t0, t1, 99f
    ld      t0, Node_backfill_slot(s1)
    ld      t1, Node_backfill_next(s1)
    bgeu    t0, t1, 27f
    sd      t0, Node_backfill_next(s1)      # blocks joined: on from the lowest
    j       29f
27: ld      t0, Node_backfill_got(s1)
    bnez    t0, 28f
    call    node_serve_slot                 # no block in the range: the range below
    ld      t0, Node_backfill_start(s1)
    bleu    t0, a0, 28f
    sd      t0, Node_backfill_next(s1)
    j       29f
28: ld      t0, Node_backfill_slot(s1)      # else again later, from the next peer
    sd      t0, Node_backfill_next(s1)
    ld      t0, Node_time_ms(s1)
    li      t1, NODE_STATUS_MS
    add     t0, t0, t1
    sd      t0, Node_backfill_ms(s1)
    ld      t0, Node_backfill_peer(s1)
    addi    t0, t0, 1
    sd      t0, Node_backfill_peer(s1)
29: li      t0, -1
    sd      t0, Node_backfill_start(s1)
99: LEAVE 96
END_FUNCTION node_backfill_link

/*
 * With NODE_FLAG_DB, after the sync's requests: the backfill's BeaconBlocksByRange (node.md) of the
 * slots below backfill_next, to a peer from backfill_peer on, when no request is open or unweighed,
 * from backfill_ms on, while backfill_next is above the target and the streams part has room for
 * three entries. s2 the store. s3 the peers part, s4 the peers, s7 the target, then a peer, s8 the
 * start slot, s9 the first index, s10 the peers checked. Locals: L the request (24), L+24 the index,
 * L+32 the fork, L+48 the pass: 1 for peers of any earliest_slot.
 */
LOCAL_FUNCTION node_backfill_ask
    ENTER 64
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 99f
    ld      t0, Node_backfill_handle(s1)
    bnez    t0, 99f
    ld      t0, Node_backfill_start(s1)
    li      t1, -1
    bne     t0, t1, 99f
    ld      t0, (Node_backfill_root)(s1)
    ld      t1, (Node_backfill_root + 8)(s1)
    or      t0, t0, t1
    ld      t1, (Node_backfill_root + 16)(s1)
    or      t0, t0, t1
    ld      t1, (Node_backfill_root + 24)(s1)
    or      t0, t0, t1
    beqz    t0, 99f
    ld      t0, Node_backfill_ms(s1)
    ld      t1, Node_time_ms(s1)
    bltu    t1, t0, 99f
    ld      t1, (Node_streams + 8)(s1)      # room for it and two more
    ld      t2, Node_messages(s1)
    ld      t3, Node_streams(s1)
    sub     t2, t2, t3
    ld      t3, Node_stream_bytes(s1)
    divu    t2, t2, t3
    addi    t1, t1, 3
    bgtu    t1, t2, 99f
    call    node_serve_slot                 # the target
    mv      s7, a0
    ld      t0, Node_backfill_next(s1)
    bleu    t0, s7, 99f
    li      t1, NODE_SYNC_BATCH
    li      s8, 0
    bltu    t0, t1, 31f
    sub     s8, t0, t1
31: bgeu    s8, s7, 32f
    mv      s8, s7
32: PART    s3, s4, s1, Node_peers          # the first peer from backfill_peer
    beqz    s4, 99f
    ld      t0, Node_backfill_peer(s1)
    remu    s9, t0, s4
    li      s10, 0
    sd      zero, (L + 48)(sp)              # first the peers whose earliest_slot is at most the start
4:  bltu    s10, s4, 40f
    ld      t0, (L + 48)(sp)                # with none, a peer of any earliest_slot
    bnez    t0, 99f
    li      t0, 1
    sd      t0, (L + 48)(sp)
    li      s10, 0
40: add     t0, s9, s10
    remu    t0, t0, s4
    sd      t0, (L + 24)(sp)
    addi    s10, s10, 1
    li      t1, NodePeer__mem
    mul     t1, t0, t1
    add     s7, s3, t1
    ld      t0, NodePeer_flags(s7)
    andi    t0, t0, 1                       # NODE_PEER_STATUS
    beqz    t0, 4b
    ld      t0, NodePeer_fork_digest(s7)
    ld      t1, Node_fork_digest(s1)
    bne     t0, t1, 4b
    ld      t0, NodePeer_earliest_slot(s7)
    bleu    t0, s8, 42f
    ld      t0, (L + 48)(sp)                # above the start in the first pass: the next peer
    beqz    t0, 4b
42:
    ld      t0, NodePeer_flags(s7)          # from fulu, its MetaData read: its custody
    andi    t0, t0, NODE_PEER_METADATA
    bnez    t0, 41f
    mv      a0, s2
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_FULU
    bgeu    a0, t0, 4b
41:
    sd      s8, L(sp)                       # start, count, step 1
    ld      t0, Node_backfill_next(s1)
    sub     t0, t0, s8
    sd      t0, (L + 8)(sp)
    li      t0, 1
    sd      t0, (L + 16)(sp)
    mv      a0, s2                          # the fork of the store's slot: the sidecar requests of the range first
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    sd      a0, (L + 32)(sp)
    mv      a3, a0
    mv      a0, s7
    ld      a1, L(sp)
    ld      a2, (L + 8)(sp)
    call    node_sidecar_ask
    bnez    a0, 99f
    li      a1, 1                           # version 2 from altair on
    ld      a0, (L + 32)(sp)
    li      t0, FORK_ALTAIR
    bltu    a0, t0, 5f
    li      a1, 2
5:  li      a0, REQRESP_BEACON_BLOCKS_BY_RANGE
    ld      a2, NodePeer_handle(s7)
    addi    a3, sp, L
    li      a4, 24
    call    node_open
    beqz    a0, 99f
    ld      t0, NodeStream_handle(a0)
    sd      t0, Node_backfill_handle(s1)
    sd      s8, Node_backfill_start(s1)
    sd      zero, Node_backfill_got(s1)
    ld      t0, (L + 24)(sp)
    sd      t0, Node_backfill_peer(s1)
99: LEAVE 64
END_FUNCTION node_backfill_ask

/* reg = the u32 at off(base), little endian, byte by byte: SSZ offsets need not be aligned. Uses tmp. */
.macro LD32B reg, base, off, tmp
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

/*
 * L0: the list of the body of the SignedBeaconBlock in the ByteList a0: a1 0 attester_slashings,
 * 1 attestations (offsets at bytes 204 and 208 of the body in every fork). a0 = its count, or
 * 2^64 - 1 when the bytes do not hold it; for an index a2 below the count, a1 the item's SSZ bytes
 * and a2 their length, else 0 and 0. Uses t0-t6, a3-a5.
 */
LOCAL_FUNCTION node_body_item
    UNWIND_END_PROLOGUE
    ld      t0, 16(a0)                      # the length
    ld      t1, 8(a0)
    add     t1, a0, t1                      # the bytes
    li      t2, 100 + 84
    bltu    t0, t2, 9f
    LD32B   t2, t1, 0, t6                   # the message
    bgtu    t2, t0, 9f
    add     t1, t1, t2
    sub     t0, t0, t2
    li      t2, 88
    bltu    t0, t2, 9f
    LD32B   t2, t1, 80, t6                  # the body: its offset at 80
    bgtu    t2, t0, 9f
    add     t1, t1, t2
    sub     t0, t0, t2
    li      t2, 216
    bltu    t0, t2, 9f
    slli    t3, a1, 2
    add     t3, t1, t3
    LD32B   t4, t3, 204, t6                 # the list: from its offset to the next field's
    LD32B   t5, t3, 208, t6
    bgtu    t4, t5, 9f
    bgtu    t5, t0, 9f
    sub     t5, t5, t4                      # the list's bytes
    add     t1, t1, t4
    beqz    t5, 7f
    li      t2, 4
    bltu    t5, t2, 9f
    LD32B   t2, t1, 0, t6                   # its first offset: 4 times the count
    andi    t3, t2, 3
    bnez    t3, 9f
    bgtu    t2, t5, 9f
    srli    a0, t2, 2
    beqz    a0, 9f
    bgeu    a2, a0, 8f
    slli    t3, a2, 2
    add     t3, t1, t3
    LD32B   t4, t3, 0, t6
    addi    t2, a2, 1
    mv      a3, t5
    bgeu    t2, a0, 1f
    LD32B   a3, t3, 4, t6
1:  bgtu    t4, a3, 9f
    bgtu    a3, t5, 9f
    add     a1, t1, t4
    sub     a2, a3, t4
    ret
7:  li      a0, 0
8:  li      a1, 0
    li      a2, 0
    ret
9:  li      a0, -1
    li      a1, 0
    li      a2, 0
    ret
END_FUNCTION node_body_item

/*
 * The votes of the imported block entry a0 (node.md): a BLOCK_ATTESTATION of each of its a1
 * attestations, then a BLOCK_SLASHING of each of its a2 attester slashings with the post-state of
 * the justified root; at most NODE_VOTES_MAX in all. s3 the entry, s4 the index, s7 the
 * attestations, s8 the slashings, s9 the justified state.
 */
LOCAL_FUNCTION node_votes
    ENTER 0
    mv      s3, a0
    li      t0, 128
    mv      s7, a1
    bleu    s7, t0, 1f
    mv      s7, t0
1:  li      t0, 2
    mv      s8, a2
    bleu    s8, t0, 2f
    mv      s8, t0
2:  li      s4, 0
3:  bgeu    s4, s7, 4f
    li      a0, NODE_WORK_BLOCK_ATTESTATION
    li      a1, 0
    li      a2, 0
    ld      a3, NodeBlock_data_id(s3)
    li      a4, 0
    mv      a5, s4
    call    node_work
    addi    s4, s4, 1
    j       3b
4:  beqz    s8, 9f
    addi    a0, s2, Store_justified_checkpoint + 8
    call    node_find_block
    li      s9, 0
    li      t0, -1
    beq     a0, t0, 5f
    ld      s9, NodeBlock_state_id(a1)
5:  li      s4, 0
6:  bgeu    s4, s8, 9f
    li      a0, NODE_WORK_BLOCK_SLASHING
    mv      a1, s9
    li      a2, 0
    ld      a3, NodeBlock_data_id(s3)
    li      a4, 0
    mv      a5, s4
    call    node_work
    addi    s4, s4, 1
    j       6b
9:  LEAVE 0
END_FUNCTION node_votes

/*
 * L0: the aggregate of the SignedAggregateAndProof in the ByteList a0: a0 = 0 and a1 its SSZ bytes,
 * a2 their length; a0 = 2^64 - 1 when the bytes do not hold it. The message's offset is at byte 0,
 * the aggregate's at byte 8 of the message; the aggregate runs to the end. Uses t0-t3, t6.
 */
LOCAL_FUNCTION node_aggregate
    UNWIND_END_PROLOGUE
    ld      t0, 16(a0)
    ld      t1, 8(a0)
    add     t1, a0, t1
    li      t2, 4
    bltu    t0, t2, 9f
    LD32B   t2, t1, 0, t6                   # the message
    bgtu    t2, t0, 9f
    add     t1, t1, t2
    sub     t0, t0, t2
    li      t2, 12
    bltu    t0, t2, 9f
    LD32B   t2, t1, 8, t6                   # the aggregate
    bgtu    t2, t0, 9f
    add     a1, t1, t2
    sub     a2, t0, t2
    li      a0, 0
    ret
9:  li      a0, -1
    li      a1, 0
    li      a2, 0
    ret
END_FUNCTION node_aggregate

/*
 * After the head (node.md): each NodeMessage in NODE_MESSAGE_VOTE whose slot is below the store's
 * gets a GOSSIP_VOTE work and takes NODE_MESSAGE_VOTING, while the actions have room for it and
 * 4096 bytes. a0 = 1 when an entry is left waiting, else 0. s3 an entry, s4 the entries left, s7
 * the store's slot, s8 left waiting.
 */
LOCAL_FUNCTION node_vote_due
    ENTER 0
    li      s8, 0
    mv      a0, s2
    call    node_store_slot
    mv      s7, a0
    PART    s3, s4, s1, Node_messages
1:  beqz    s4, 9f
    ld      t0, NodeMessage_state(s3)
    li      t1, NODE_MESSAGE_VOTE
    bne     t0, t1, 2f
    ld      t0, NodeMessage_slot(s3)
    bgeu    t0, s7, 2f
    li      a0, NODE_ACT_WORK_SIZE
    call    node_room
    bnez    a0, 3f
    li      s8, 1
    j       9f
3:  li      a0, NODE_WORK_GOSSIP_VOTE
    li      a1, 0
    li      a2, 0
    ld      a3, NodeMessage_data_id(s3)
    ld      a4, NodeMessage_handle(s3)
    li      a5, 0
    call    node_work
    li      t0, NODE_MESSAGE_VOTING
    sd      t0, NodeMessage_state(s3)
2:  addi    s3, s3, NodeMessage__mem
    addi    s4, s4, -1
    j       1b
9:  mv      a0, s8
    LEAVE 0
END_FUNCTION node_vote_due

/*
 * L0: a0 = the end of the sidecar segment a0: db_sidecar_end for db_sidecar_segment, else
 * backfill_sidecar_end for backfill_sidecar_segment, else 0, a new segment. Uses t1 only.
 */
LOCAL_FUNCTION node_side_end
    UNWIND_END_PROLOGUE
    ld      t1, Node_db_sidecar_segment(s1)
    bne     a0, t1, 1f
    ld      a0, Node_db_sidecar_end(s1)
    ret
1:  ld      t1, Node_backfill_sidecar_segment(s1)
    bne     a0, t1, 2f
    ld      a0, Node_backfill_sidecar_end(s1)
    ret
2:  li      a0, 0
    ret
END_FUNCTION node_side_end

/*
 * Each NODE_BLOB_VALID sidecar of the block entry a0, by index, to the Db (node.md): its record at
 * the end of the sidecar segment of the block's slot and a DB_APPEND; the writer a1 (0 the archive,
 * 1 the backfill) takes that segment, and each end of it the record's end; its bytes and entry go
 * unless a stream sends them. A record lantern_db_add refuses stays for the prune. s8 the block, s9
 * the index, s10 its slot. Locals: L a DbRecord (80), L+80 the offset, L+88 the sidecar, L+96 the
 * writer, L+104 the segment.
 */
LOCAL_FUNCTION node_db_sidecars
    ENTER 112
    mv      s8, a0
    ld      s10, NodeBlock_slot(s8)
    sd      a1, (L + 96)(sp)
    ld      t0, Node_sidecar_floor(s1)      # below sidecar_floor: no record
    bltu    s10, t0, 9f
    li      s9, 0
4:  li      t0, DB_SIDECAR_INDICES
    bgeu    s9, t0, 9f
    mv      a0, s8
    mv      a1, s9
    call    node_blob_held
    beqz    a0, 19f
    sd      a0, (L + 88)(sp)
    mv      a0, s10                         # a column sidecar from fulu on, else a blob sidecar
    addi    a1, s1, Node_config
    call    node_fork
    li      t1, DB_BLOB_SIDECAR
    li      t0, FORK_FULU
    bltu    a0, t0, 41f
    li      t1, DB_COLUMN_SIDECAR
41: sd      t1, L(sp)
    sd      s10, (L + 8)(sp)
    sd      s9, (L + 16)(sp)
    ld      t0, (L + 88)(sp)
    ld      t0, NodeBlob_length(t0)
    sd      t0, (L + 72)(sp)
    addi    t0, t0, 24
    sd      t0, (L + 56)(sp)
    li      t0, 24
    sd      t0, (L + DbRecord_bytes + 8)(sp)
    srli    a0, s10, DB_SEGMENT_SHIFT       # its segment, and its offset at the segment's end
    sd      a0, (L + 104)(sp)
    call    node_side_end
    sd      a0, (L + 80)(sp)
    ld      a0, Node_db(s1)
    add     a0, s1, a0
    addi    a1, sp, L
    addi    a2, sp, L + 80
    call    lantern_db_add
    bnez    a0, 19f                         # refused: the entry stays for the prune
    li      a0, 1
    ld      t0, (L + 88)(sp)
    ld      a1, NodeBlob_data_id(t0)
    ld      a2, (L + 104)(sp)
    ld      a3, (L + 80)(sp)
    addi    a4, sp, L
    call    node_db_append
    ld      t0, (L + 72)(sp)                # the segment's new end: the writer's segment, each end of it
    addi    t0, t0, DbRecord__mem + 7
    andi    t0, t0, -8
    ld      t1, (L + 80)(sp)
    add     t1, t1, t0
    ld      t2, (L + 104)(sp)
    ld      t3, (L + 96)(sp)
    bnez    t3, 1f
    sd      t2, Node_db_sidecar_segment(s1)
    j       2f
1:  sd      t2, Node_backfill_sidecar_segment(s1)
2:  ld      t3, Node_db_sidecar_segment(s1)
    bne     t3, t2, 3f
    sd      t1, Node_db_sidecar_end(s1)
3:  ld      t3, Node_backfill_sidecar_segment(s1)
    bne     t3, t2, 5f
    sd      t1, Node_backfill_sidecar_end(s1)
5:  ld      t0, (L + 88)(sp)                # its bytes and entry go, unless a stream sends them
    ld      a0, NodeBlob_data_id(t0)
    call    node_serving
    bnez    a0, 19f
    li      a0, NODE_ACT_BYTES_FREE
    ld      t0, (L + 88)(sp)
    ld      a1, NodeBlob_data_id(t0)
    li      a2, 0
    call    node_ids
    ld      t1, (L + 88)(sp)
    li      t0, -1
    sd      t0, 0(t1)
    sd      t0, 8(t1)
    sd      t0, 16(t1)
    sd      t0, 24(t1)
    sd      t0, NodeBlob_slot(t1)
    sd      zero, NodeBlob_data_id(t1)
    li      t0, NODE_BLOB_FREE
    sd      t0, NodeBlob_status(t1)
19: addi    s9, s9, 1
    j       4b
9:  LEAVE 112
END_FUNCTION node_db_sidecars

/*
 * With NODE_FLAG_DB, the sidecars the node no longer serves go (node.md): the drop slot, the first
 * slot of the earlier of the blob window's and the column window's first epochs, at most the Db's
 * end_slot, down to a multiple of DB_SEGMENT_SLOTS, at most 16 segments above sidecar_floor; a
 * DB_DROP of each sidecar segment below it from sidecar_floor's, lantern_db_drop_sidecars, and
 * sidecar_floor takes it. s3 the drop slot, s4 a segment. Locals: L the slot.
 */
LOCAL_FUNCTION node_drop_sidecars
    ENTER 16
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 9f
    LDQ     a0, s1, Node_config + CONFIG_MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS
    li      a1, FORK_DENEB
    call    node_window
    mv      s3, a0
    LDQ     a0, s1, Node_config + CONFIG_MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS
    li      a1, FORK_FULU
    call    node_window
    bgeu    a0, s3, 1f
    mv      s3, a0
1:  li      t0, SLOTS_PER_EPOCH
    mulhu   t1, s3, t0
    mul     s3, s3, t0
    beqz    t1, 2f
    li      s3, -1
2:  ld      t0, Node_db(s1)
    add     t0, s1, t0
    ld      t1, Db_end_slot(t0)
    bleu    s3, t1, 3f
    mv      s3, t1
3:  li      t0, -DB_SEGMENT_SLOTS
    and     s3, s3, t0
    ld      t1, Node_sidecar_floor(s1)
    bleu    s3, t1, 9f
    li      t0, 16 * DB_SEGMENT_SLOTS       # at most 16 segments a step
    add     t0, t1, t0
    bleu    s3, t0, 4f
    mv      s3, t0
4:  srli    s4, t1, DB_SEGMENT_SHIFT
5:  slli    t0, s4, DB_SEGMENT_SHIFT        # each sidecar segment below the drop slot
    bgeu    t0, s3, 6f
    li      a0, NODE_ACT_DB_DROP
    li      a1, NODE_ACT_DB_DROP_SIZE
    call    node_act
    sd      s4, 16(a0)
    li      t0, 1
    sd      t0, 24(a0)
    addi    s4, s4, 1
    j       5b
6:  sd      s3, L(sp)
    ld      a0, Node_db(s1)
    add     a0, s1, a0
    addi    a1, sp, L
    call    lantern_db_drop_sidecars
    sd      s3, Node_sidecar_floor(s1)
    srli    t0, s3, DB_SEGMENT_SHIFT        # a writer's segment below it: none
    li      t2, -1
    ld      t1, Node_db_sidecar_segment(s1)
    bgeu    t1, t0, 7f
    sd      t2, Node_db_sidecar_segment(s1)
7:  ld      t1, Node_backfill_sidecar_segment(s1)
    bgeu    t1, t0, 9f
    sd      t2, Node_backfill_sidecar_segment(s1)
9:  LEAVE 16
END_FUNCTION node_drop_sidecars

/*
 * With NODE_FLAG_DB, the canonical blocks from db_next_slot to the finalized block a0 and their
 * sidecars go to the Db, in slot order: a record of each in the index and in a DB_APPEND action,
 * then their bytes and entries go, but the finalized block's entry and bytes a stream sends. A
 * record the Db refuses stops the archive until a later prune. s3 the finalized block, s4 the
 * chain (an entry address for each, at the end of scratch), s7 its count, s8 a block, s9 an
 * index, s10 the slot. Locals: L a DbRecord, L+64 an offset, L+72 a sidecar entry.
 */
LOCAL_FUNCTION node_archive
    ENTER 96
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 99f
    mv      s3, a0
    ld      t0, 0(s5)                       # the chain at the end of scratch
    ld      t1, (Node_blocks + 8)(s1)
    slli    t1, t1, 3
    sub     t0, t0, t1
    add     s4, s5, t0
    li      s7, 0
    mv      a1, s3                          # from the finalized block down to db_next_slot
1:  ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 2f
    ld      t0, NodeBlock_slot(a1)
    ld      t1, Node_db_next_slot(s1)
    bltu    t0, t1, 2f
    slli    t0, s7, 3
    add     t0, s4, t0
    sd      a1, 0(t0)
    addi    s7, s7, 1
    ld      t0, (Node_blocks + 8)(s1)
    bgeu    s7, t0, 2f
    addi    a0, a1, NodeBlock_parent_root
    call    node_find_block
    li      t0, -1
    bne     a0, t0, 1b
2:  beqz    s7, 99f                         # then from the lowest slot
    addi    s7, s7, -1
    slli    t0, s7, 3
    add     t0, s4, t0
    ld      s8, 0(t0)
    ld      s10, NodeBlock_slot(s8)
    ld      t0, NodeBlock_data_id(s8)
    beqz    t0, 30f                         # no bytes: the anchor
    ld      a0, Node_db(s1)                 # a block the Db holds already, as after a restart: no record
    add     a0, s1, a0
    mv      a1, s8
    addi    a2, sp, L + 80
    call    lantern_db_find_root
    ld      t0, (L + 80)(sp)
    li      t1, -1
    bne     t0, t1, 40f
    li      t0, DB_BLOCK                    # the block's record
    sd      t0, L(sp)
    sd      s10, (L + 8)(sp)
    sd      zero, (L + 16)(sp)
    addi    t0, sp, L + 24
    COPY32  t0, s8
    ld      t0, NodeBlock_length(s8)
    sd      t0, (L + 72)(sp)
    addi    t0, t0, 24
    sd      t0, (L + 56)(sp)
    li      t0, 24
    sd      t0, (L + DbRecord_bytes + 8)(sp)
    srli    t0, s10, DB_SEGMENT_SHIFT       # its segment, and its offset at the segment's end
    ld      t1, Node_db_block_segment(s1)
    beq     t0, t1, 3f
    mv      a0, t0
    call    node_seg_end
    sd      t0, Node_db_block_segment(s1)
    sd      a0, Node_db_block_end(s1)
3:  ld      t0, Node_db_block_end(s1)
    sd      t0, (L + 80)(sp)
    ld      a0, Node_db(s1)
    add     a0, s1, a0
    addi    a1, sp, L
    addi    a2, sp, L + 80
    call    lantern_db_add
    bnez    a0, 99f
    li      a0, 0
    ld      a1, NodeBlock_data_id(s8)
    ld      a2, Node_db_block_segment(s1)
    ld      a3, (L + 80)(sp)
    addi    a4, sp, L
    call    node_db_append
    ld      t0, (L + 72)(sp)
    addi    t0, t0, DbRecord__mem + 7
    andi    t0, t0, -8
    ld      t1, Node_db_block_end(s1)
    add     t1, t1, t0
    sd      t1, Node_db_block_end(s1)
    ld      t2, Node_backfill_segment(s1)   # the backfill's end too, of the same segment
    ld      t3, Node_db_block_segment(s1)
    bne     t2, t3, 42f
    sd      t1, Node_backfill_end(s1)
42: mv      a0, s8                          # each sidecar the node holds, by index
    li      a1, 0
    call    node_db_sidecars
20: bne     s8, s3, 21f                     # the finalized block: its state and bytes to the shell, for a restart
    ld      t0, 8(s6)
    ld      t1, 16(s6)
    add     t2, s6, t0
    add     t2, t2, t1
    addi    t1, t1, NODE_ACT_DB_STATE_SIZE
    sd      t1, 16(s6)
    li      t0, NODE_ACT_DB_STATE_SIZE
    sd      t0, 0(t2)
    li      t0, NODE_ACT_DB_STATE
    sd      t0, 8(t2)
    ld      t0, NodeBlock_state_id(s8)
    sd      t0, 16(t2)
    ld      t0, NodeBlock_data_id(s8)
    sd      t0, 24(t2)
    sd      s10, 32(t2)
21: ld      a0, NodeBlock_data_id(s8)       # the block's bytes go, unless a stream sends them
    call    node_serving
    bnez    a0, 30f
    li      a0, NODE_ACT_BYTES_FREE
    ld      a1, NodeBlock_data_id(s8)
    li      a2, 0
    call    node_ids
    sd      zero, NodeBlock_data_id(s8)
    beq     s8, s3, 30f                     # and its entry, but the finalized block's
    li      t0, -1
    sd      t0, 0(s8)
    sd      t0, 8(s8)
    sd      t0, 16(s8)
    sd      t0, 24(s8)
    sd      t0, 32(s8)
    sd      t0, 40(s8)
    sd      t0, 48(s8)
    sd      t0, 56(s8)
    sd      t0, NodeBlock_slot(s8)
    sd      zero, NodeBlock_state_id(s8)
    li      t0, NODE_BLOCK_FREE
    sd      t0, NodeBlock_status(s8)
30: addi    t0, s10, 1
    sd      t0, Node_db_next_slot(s1)
    j       2b
40: li      s9, 0                           # in the Db: the sidecars the node holds of it go
41: li      t0, DB_SIDECAR_INDICES
    bgeu    s9, t0, 20b
    mv      a0, s8
    mv      a1, s9
    addi    s9, s9, 1
    call    node_blob_held
    beqz    a0, 41b
    sd      a0, (L + 88)(sp)
    ld      a0, NodeBlob_data_id(a0)
    call    node_serving
    bnez    a0, 41b
    li      a0, NODE_ACT_BYTES_FREE
    ld      t0, (L + 88)(sp)
    ld      a1, NodeBlob_data_id(t0)
    li      a2, 0
    call    node_ids
    ld      t1, (L + 88)(sp)
    li      t0, -1
    sd      t0, 0(t1)
    sd      t0, 8(t1)
    sd      t0, 16(t1)
    sd      t0, 24(t1)
    sd      t0, NodeBlob_slot(t1)
    sd      zero, NodeBlob_data_id(t1)
    li      t0, NODE_BLOB_FREE
    sd      t0, NodeBlob_status(t1)
    j       41b
99: LEAVE 96
END_FUNCTION node_archive

/*
 * (node, segment, sidecars, bytes, valid): lantern_db_scan of a segment's bytes into the node's
 * Db; then the segment is the one of its kind to append to, at valid, unless the current one is
 * higher; db_next_slot is at least the Db's end_slot, and earliest_slot the Db's first block when
 * that is lower. s1 node, s2 sidecars, s3 segment, s4 valid.
 */
FUNCTION lantern_node_db_scan
    ENTER 0
    mv      s1, a0
    ld      s3, 0(a1)
    ld      s2, 0(a2)
    mv      s4, a4
    mv      s5, a3
    ld      a0, Node_db(s1)
    add     a0, s1, a0
    call    lantern_db_scan
    bnez    a0, 9f
    beqz    s2, 14f                         # a sidecar segment: the backfill's, when it has none
    ld      t0, Node_backfill_sidecar_segment(s1)
    li      t1, -1
    bne     t0, t1, 10f
    sd      s3, Node_backfill_sidecar_segment(s1)
    ld      t0, 0(s4)
    sd      t0, Node_backfill_sidecar_end(s1)
    j       10f
14:                                         # a block segment: the backfill's, when it has none; its lowest block
    ld      t0, Node_backfill_segment(s1)
    li      t1, -1
    bne     t0, t1, 11f
    sd      s3, Node_backfill_segment(s1)
    ld      t0, 0(s4)
    sd      t0, Node_backfill_end(s1)
11: ld      t0, 8(s5)
    add     s6, s5, t0
    ld      t0, 0(s4)
    add     s7, s6, t0                      # the end of the records added
12: addi    t0, s6, DbRecord__mem
    bgtu    t0, s7, 10f
    ld      t0, DbRecord_slot(s6)
    ld      t1, Node_backfill_slot(s1)
    bgeu    t0, t1, 13f
    sd      t0, Node_backfill_slot(s1)
    sd      t0, Node_backfill_next(s1)
    addi    t2, s1, Node_backfill_root
    addi    t3, s6, DbRecord__mem + 116
    COPY32W t2, t3
13: ld      t0, DbRecord_length(s6)
    addi    t0, t0, DbRecord__mem + 7
    andi    t0, t0, -8
    add     s6, s6, t0
    j       12b
10:
    li      t0, Node_db_block_segment
    beqz    s2, 1f
    li      t0, Node_db_sidecar_segment
1:  add     t0, s1, t0
    ld      t1, 0(t0)
    li      t2, -1
    beq     t1, t2, 2f
    bltu    s3, t1, 3f
2:  sd      s3, 0(t0)
    ld      t1, 0(s4)
    sd      t1, 8(t0)
3:  ld      t3, Node_db(s1)
    add     t3, s1, t3
    ld      t0, Db_end_slot(t3)
    ld      t1, Node_db_next_slot(s1)
    bleu    t0, t1, 4f
    sd      t0, Node_db_next_slot(s1)
4:  ld      t0, Db_first_slot(t3)           # the first block below earliest_slot
    ld      t1, Node_earliest_slot(s1)
    ld      t2, Db_end_slot(t3)
    bleu    t1, t2, 41f
    mv      t1, t2
41: ld      t4, Db_slots(t3)
    add     t4, t3, t4
5:  bgeu    t0, t1, 8f
    ld      t5, DbSlot_block(t4)
    bnez    t5, 6f
    addi    t4, t4, DbSlot__mem
    addi    t0, t0, 1
    j       5b
6:  sd      t0, Node_earliest_slot(s1)
8:  li      a0, LANTERN_OK
9:  LEAVE 0
END_FUNCTION lantern_node_db_scan

/* A BYTES_PUT action of the ByteList a0 with a new id: a0 = the id. s3 the ByteList, s4 the id. */
LOCAL_FUNCTION node_put
    ENTER 0
    mv      s3, a0
    call    node_new_id
    mv      s4, a0
    ld      a1, 16(s3)                      # the header, 16 id, then a ByteList: size, offset 24, count, bytes
    addi    a1, a1, 48 + 7
    andi    a1, a1, -8
    li      a0, NODE_ACT_BYTES_PUT
    call    node_act
    sd      s4, 16(a0)
    ld      t0, 0(a0)
    addi    t0, t0, -24
    sd      t0, 24(a0)
    li      t0, 24
    sd      t0, 32(a0)
    ld      a2, 16(s3)
    sd      a2, 40(a0)
    addi    a0, a0, 48
    ld      t0, 8(s3)
    add     a1, s3, t0
    call    lantern_copy
    mv      a0, s4
    LEAVE 0
END_FUNCTION node_put

/* a0 = the node's NODE_BLOB_VALID entry of the root at a0 (8-aligned) and the index a1, or 0. Uses t0-t3, a6, a7. */
LOCAL_FUNCTION node_blob_held
    UNWIND_END_PROLOGUE
    PART    t0, t1, s1, Node_blobs
1:  beqz    t1, 3f
    ld      t2, NodeBlob_status(t0)
    li      t3, NODE_BLOB_VALID
    bne     t2, t3, 2f
    ld      t2, NodeBlob_index(t0)
    bne     t2, a1, 2f
    NE32    t0, a0, 2f
    mv      a0, t0
    ret
2:  addi    t0, t0, NodeBlob__mem
    addi    t1, t1, -1
    j       1b
3:  li      a0, 0
    ret
END_FUNCTION node_blob_held

/*
 * a0 = 1 when the node holds a NODE_BLOB_VALID entry of the root at a0 (8-aligned) for each index
 * below a1 (1 to NODE_BLOB_MAX), else 0. Uses t0-t4, a6, a7.
 */
LOCAL_FUNCTION node_blobs_held
    UNWIND_END_PROLOGUE
    PART    t0, t1, s1, Node_blobs
    li      t4, 0                           # a bit for each index held
1:  beqz    t1, 3f
    ld      t2, NodeBlob_status(t0)
    li      t3, NODE_BLOB_VALID
    bne     t2, t3, 2f
    ld      t2, NodeBlob_index(t0)
    bgeu    t2, a1, 2f
    NE32    t0, a0, 2f
    li      t3, 1
    sll     t3, t3, t2
    or      t4, t4, t3
2:  addi    t0, t0, NodeBlob__mem
    addi    t1, t1, -1
    j       1b
3:  li      t2, 64                          # every index below a1
    sub     t2, t2, a1
    li      t3, -1
    srl     t3, t3, t2
    sub     t3, t3, t4
    seqz    a0, t3
    ret
END_FUNCTION node_blobs_held

/* a0 = 1 when the node s1 samples the column a0, else 0. A leaf; uses t0, t1. */
LOCAL_FUNCTION node_sampled
    UNWIND_END_PROLOGUE
    li      t0, 128
    bgeu    a0, t0, 1f
    srli    t0, a0, 3
    add     t0, t0, s1
    lbu     t0, Node_columns(t0)
    andi    t1, a0, 7
    srl     t0, t0, t1
    andi    a0, t0, 1
    ret
1:  li      a0, 0
    ret
END_FUNCTION node_sampled

/* a0 = the columns the node s1 samples: the bits of Node_columns. A leaf; uses t0, t1. */
LOCAL_FUNCTION node_column_count
    UNWIND_END_PROLOGUE
    li      a0, 0
    ld      t0, Node_columns(s1)
1:  beqz    t0, 2f
    addi    t1, t0, -1
    and     t0, t0, t1
    addi    a0, a0, 1
    j       1b
2:  ld      t0, (Node_columns + 8)(s1)
3:  beqz    t0, 4f
    addi    t1, t0, -1
    and     t0, t0, t1
    addi    a0, a0, 1
    j       3b
4:  ret
END_FUNCTION node_column_count

/*
 * a0 = 1 when the node holds a NODE_BLOB_VALID entry of the root at a0 for each column it
 * samples, else 0. A leaf; uses t0-t6, a6, a7.
 */
LOCAL_FUNCTION node_columns_held
    UNWIND_END_PROLOGUE
    PART    t0, t1, s1, Node_blobs
    li      t4, 0                           # a bit for each column held: t4 below 64, t5 from 64
    li      t5, 0
1:  beqz    t1, 3f
    ld      t2, NodeBlob_status(t0)
    li      t3, NODE_BLOB_VALID
    bne     t2, t3, 2f
    ld      t2, NodeBlob_index(t0)
    li      t3, 128
    bgeu    t2, t3, 2f
    NE32    t0, a0, 2f
    li      t3, 1
    sll     t3, t3, t2
    li      t6, 64
    bgeu    t2, t6, 21f
    or      t4, t4, t3
    j       2f
21: or      t5, t5, t3
2:  addi    t0, t0, NodeBlob__mem
    addi    t1, t1, -1
    j       1b
3:  ld      t2, Node_columns(s1)            # each sampled column held
    not     t4, t4
    and     t2, t2, t4
    ld      t3, (Node_columns + 8)(s1)
    not     t5, t5
    and     t3, t3, t5
    or      t2, t2, t3
    seqz    a0, t2
    ret
END_FUNCTION node_columns_held

/*
 * a0 = the first epoch of a sidecar window: max(the epoch of the store s2 - a0, the epoch of the
 * fork a1 in the node s1's config). Locals: 0 a0, 8 a1.
 */
LOCAL_FUNCTION node_window
    FRAME 16
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    mv      a0, s2
    call    node_store_slot
    li      t0, SLOTS_PER_EPOCH
    divu    a0, a0, t0
    ld      t1, 0(sp)
    sub     t2, a0, t1
    sltu    t3, a0, t1
    addi    t3, t3, -1
    and     a0, t2, t3
    ld      t1, 8(sp)
    slli    t1, t1, 4
    add     t1, t1, s1
    ld      t1, Node_config(t1)
    bgeu    a0, t1, 1f
    mv      a0, t1
1:  UNFRAME 16
END_FUNCTION node_window

/*
 * The columns of the groups of get_custody_groups(the NodeID at a0, a1 groups) of the config a2,
 * as bits in the 16 bytes at a3: a0 = 0, or LANTERN_INVALID_CUSTODY_GROUP and no bits (a count
 * above NUMBER_OF_CUSTODY_GROUPS or 128). s1 config, s2 out, s3 a group, s4 the groups left, s5
 * NUMBER_OF_CUSTODY_GROUPS. Locals: L the count, L+16 an IndexList.
 */
LOCAL_FUNCTION node_custody_columns
    ENTER NODE_CUSTODY_LOCALS
    mv      s1, a2
    mv      s2, a3
    sd      zero, 0(s2)
    sd      zero, 8(s2)
    sd      a1, L(sp)
    li      t0, 128
    bgtu    a1, t0, 8f
    li      t0, NODE_CUSTODY_LIST
    sd      t0, (L + 16)(sp)
    addi    a1, sp, L
    mv      a2, s1
    addi    a3, sp, L + 16
    CALL_GLOBAL lantern_fulu_get_custody_groups
    bnez    a0, 8f
    ld      s4, (L + 16 + 16)(sp)
    addi    s3, sp, L + 16 + LIST_FIXED
    LDQ     s5, s1, CONFIG_NUMBER_OF_CUSTODY_GROUPS
1:  beqz    s4, 9f
    ld      t1, 0(s3)                       # a group g: the columns N * i + g, i below NUMBER_OF_COLUMNS // N
    addi    s3, s3, 8
    li      t2, NUMBER_OF_COLUMNS
    divu    t2, t2, s5
2:  beqz    t2, 3f
    srli    t3, t1, 3
    add     t3, t3, s2
    lbu     t4, 0(t3)
    andi    t5, t1, 7
    li      t6, 1
    sll     t6, t6, t5
    or      t4, t4, t6
    sb      t4, 0(t3)
    add     t1, t1, s5
    addi    t2, t2, -1
    j       2b
3:  addi    s4, s4, -1
    j       1b
9:  li      a0, LANTERN_OK
    LEAVE NODE_CUSTODY_LOCALS
8:  sd      zero, 0(s2)
    sd      zero, 8(s2)
    li      a0, LANTERN_INVALID_CUSTODY_GROUP
    LEAVE NODE_CUSTODY_LOCALS
END_FUNCTION node_custody_columns

/*
 * The peer a0 takes NODE_PEER_METADATA, and as custody the columns of the groups of
 * get_custody_groups(its node ID, a1 groups) when its peer ID holds a secp256k1 key that
 * decompresses; else no custody. s3 the peer, s4 the count. Locals: L the point (64), L+64 a
 * ByteList of the point (88), L+152 the digest (32), L+184 the NodeID (32).
 */
LOCAL_FUNCTION node_peer_custody
    ENTER 224
    mv      s3, a0
    mv      s4, a1
    ld      t0, NodePeer_flags(s3)
    ori     t0, t0, NODE_PEER_METADATA
    sd      t0, NodePeer_flags(s3)
    sd      zero, NodePeer_custody(s3)
    sd      zero, (NodePeer_custody + 8)(s3)
    ld      t0, NodePeer_id_len(s3)         # 0x00 0x25 0x08 0x02 0x12 0x21, then the key
    li      t1, 39
    bne     t0, t1, 9f
    ld      t0, NodePeer_id(s3)
    slli    t0, t0, 16
    li      t1, 0x211202082500 << 16
    bne     t0, t1, 9f
    addi    a0, s3, NodePeer_id + 6
    addi    a1, sp, L
    CALL_GLOBAL crypto_secp256k1_decompress
    bnez    a0, 9f
    li      t0, 24 + 64                     # keccak256(x || y)
    sd      t0, (L + 64)(sp)
    li      t0, 24
    sd      t0, (L + 72)(sp)
    li      t0, 64
    sd      t0, (L + 80)(sp)
    addi    a0, sp, L + 88
    addi    a1, sp, L
    li      a2, 64
    call    lantern_copy
    addi    a0, sp, L + 64
    addi    a1, sp, L + 152
    CALL_GLOBAL crypto_keccak256
    bnez    a0, 9f
    addi    t0, sp, L + 152                 # the NodeID: the digest's bytes in reverse order
    addi    t1, sp, L + 184 + 31
    li      t2, 32
1:  lbu     t3, 0(t0)
    sb      t3, 0(t1)
    addi    t0, t0, 1
    addi    t1, t1, -1
    addi    t2, t2, -1
    bnez    t2, 1b
    addi    a0, sp, L + 184
    mv      a1, s4
    addi    a2, s1, Node_config
    addi    a3, s3, NodePeer_custody
    call    node_custody_columns
9:  LEAVE 224
END_FUNCTION node_peer_custody

/* L0: a0 = 1 when the block entry a0 needs blobs or columns it does not hold (node.md), else 0. s4 the entry, s7 its blob count. */
LOCAL_FUNCTION node_lacks_sidecars
    ENTER 0
    mv      s4, a0
    ld      s7, NodeBlock_blobs(s4)
    beqz    s7, 5f
    ld      a0, NodeBlock_slot(s4)
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_FULU
    bgeu    a0, t0, 6f
    li      t0, NODE_BLOB_MAX
    bgtu    s7, t0, 5f
    LDQ     t1, s1, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK
    li      t0, FORK_DENEB
    beq     a0, t0, 2f
    li      t0, FORK_ELECTRA
    bne     a0, t0, 5f
    LDQ     t1, s1, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
2:  bgtu    s7, t1, 5f
    LDQ     a0, s1, Node_config + CONFIG_MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS   # the blob window
    li      a1, FORK_DENEB
    call    node_window
    ld      t2, NodeBlock_slot(s4)
    li      t0, SLOTS_PER_EPOCH
    divu    t2, t2, t0
    bltu    t2, a0, 5f
    mv      a0, s4
    mv      a1, s7
    call    node_blobs_held
    bnez    a0, 5f
4:  li      a0, 1
    LEAVE 0
6:  LDQ     a0, s1, Node_config + CONFIG_MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS   # the column window
    li      a1, FORK_FULU
    call    node_window
    ld      t2, NodeBlock_slot(s4)
    li      t0, SLOTS_PER_EPOCH
    divu    t2, t2, t0
    bltu    t2, a0, 5f
    mv      a0, s4
    call    node_columns_held
    beqz    a0, 4b
5:  li      a0, 0
    LEAVE 0
END_FUNCTION node_lacks_sidecars

/*
 * The block of index a0, from the network, waits for its blobs or columns: NODE_BLOCK_BLOBS
 * while it needs sidecars the node does not hold; else data_available 1, NODE_BLOCK_WAITING and
 * its import. Deneb and electra: it needs blobs when its blob count is 1 to the fork's limit and
 * NODE_BLOB_MAX and its epoch is in the blob window. Fulu: it needs columns when its blob count is
 * above 0 and its epoch is in the column window. s3 the index, s4 the entry, s7 the count.
 */
LOCAL_FUNCTION node_await
    ENTER 0
    mv      s3, a0
    PART    s4, t0, s1, Node_blocks
    li      t0, NodeBlock__mem
    mul     t0, s3, t0
    add     s4, s4, t0
    mv      a0, s4
    call    node_lacks_sidecars
    beqz    a0, 5f
    li      t0, NODE_BLOCK_BLOBS
    sd      t0, NodeBlock_status(s4)
    LEAVE 0
5:  li      t0, 1
    sd      t0, NodeBlock_data_available(s4)
    li      t0, NODE_BLOCK_WAITING
    sd      t0, NodeBlock_status(s4)
    mv      a0, s3
    call    node_try_import
    LEAVE 0
END_FUNCTION node_await

/* A blob of the root at a0 became NODE_BLOB_VALID: the block of that root in NODE_BLOCK_BLOBS waits for its blobs again. */
LOCAL_FUNCTION node_blob_added
    FRAME 0
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 9f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_BLOBS
    bne     t0, t1, 9f
    call    node_await
9:  UNFRAME 0
END_FUNCTION node_blob_added

/* The head: the root of get_head of the fork of the store's slot into the node, or a JUSTIFIED_STATE work. Locals: L the node. */
LOCAL_FUNCTION node_head
    ENTER 16
    mv      a0, s2
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s2
    mv      a1, s5
    addi    a2, sp, L
    FORK_CALL get_head
    li      t0, LANTERN_NEED_JUSTIFIED_STATE
    bne     a0, t0, 1f
    call    node_justified
    LEAVE 16
1:  bnez    a0, 9f
    ld      t0, L(sp)
    PART    t1, t2, s2, Store_blocks
    bgeu    t0, t2, 9f
    li      t2, BlockNode__mem
    mul     t0, t0, t2
    add     t1, t1, t0
    addi    t0, s1, Node_head_root
    NE32    t0, t1, 2f                      # a new head with NODE_FLAG_ENGINE: a forkchoiceUpdated is due
    j       3f
2:  ld      t2, Node_flags(s1)
    andi    t3, t2, NODE_FLAG_ENGINE
    beqz    t3, 3f
    ori     t2, t2, NODE_FLAG_FCU
    sd      t2, Node_flags(s1)
3:  COPY32  t0, t1
9:  LEAVE 16
END_FUNCTION node_head

/*
 * The event a0. s3 the event, s4 its ByteList, s7 its bytes, s8 a BufferId, s9 the root entry
 * a1 of the step's first pass for a BLOCK event. Locals: L+32 a result, L+40 the index.
 */
LOCAL_FUNCTION node_event
    ENTER 48
    mv      s3, a0
    mv      s9, a1
    ld      t0, 8(s3)
    li      t1, NODE_EV_TICK
    bne     t0, t1, 10f
    ld      t0, 16(s3)                      # TICK: on_tick of the fork of the new slot
    sd      t0, Node_time_ms(s1)
    ld      t1, Store_genesis_time_ms(s2)
    sub     t2, t0, t1
    sltu    t0, t0, t1
    addi    t0, t0, -1
    and     t0, t2, t0
    LDQ     t1, s2, Store_config + CONFIG_SLOT_DURATION_MS
    li      a0, 0
    beqz    t1, 1f
    divu    a0, t0, t1
1:  addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s2
    addi    a1, s3, 16
    addi    a2, sp, L + 32
    FORK_CALL on_tick
    LEAVE 48
10: li      t1, NODE_EV_BLOCK
    bne     t0, t1, 20f
    ld      t0, 0(s9)                       # BLOCK: its root entry from the step's first pass
    bnez    t0, 19f
    addi    a0, s9, 8                       # a known block: nothing
    call    node_find_block
    li      t0, -1
    bne     a0, t0, 19f
    addi    s4, s3, NodeEvent_bytes         # its bytes, then its entry
    ld      t0, 8(s4)
    add     s7, s4, t0
    mv      a0, s4
    call    node_put
    mv      s8, a0
    call    node_new_block
    sd      a0, (L + 40)(sp)
    addi    t2, s9, 8
    COPY32  t0, t2
    addi    t2, t0, NodeBlock_parent_root   # the message's parent_root
    addi    t3, s7, 116
    COPY32W t2, t3
    LDU64   t2, s7, 100, t3                 # the message's slot
    sd      t2, NodeBlock_slot(t0)
    sd      s8, NodeBlock_data_id(t0)
    sd      zero, NodeBlock_state_id(t0)
    li      t2, NODE_BLOCK_WAITING
    sd      t2, NodeBlock_status(t0)
    ld      t2, 16(s3)
    sd      t2, NodeBlock_data_available(t0)
    sd      zero, NodeBlock_result(t0)
    sd      zero, NodeBlock_blobs(t0)
    ld      t2, 16(s4)
    sd      t2, NodeBlock_length(t0)
    ld      a0, (L + 40)(sp)
    call    node_try_import
19: LEAVE 48
20: li      t1, NODE_EV_ATTESTATION
    bne     t0, t1, 30f
    addi    s4, s3, NodeEvent_bytes         # ATTESTATION: its target checkpoint state, if made
    ld      t0, 16(s4)
    li      t1, 4 + 128 + 96
    bltu    t0, t1, 29f
    mv      a0, s4
    call    node_put
    mv      s8, a0
    ld      t0, 8(s4)
    add     s7, s4, t0
    LDU64   a0, s7, 92, t0                  # data.target: the epoch, then the root
    addi    a1, s7, 100
    call    node_find_checkpoint
    li      t0, -1
    li      t1, 0
    beq     a0, t0, 21f
    ld      t1, NodeCheckpoint_state_id(a1)
21: mv      a1, t1
    li      a0, NODE_WORK_ATTESTATION
    li      a2, 0
    mv      a3, s8
    li      a4, 0
    ld      a5, 16(s3)                      # is_from_block
    call    node_work
29: LEAVE 48
30: li      t1, NODE_EV_ATTESTER_SLASHING
    bne     t0, t1, 40f
    ADDQ    a0, s2, Store_justified_checkpoint + 8      # the justified root's post-state
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 39f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 39f
    ld      s7, NodeBlock_state_id(a1)
    addi    a0, s3, NodeEvent_bytes
    call    node_put
    mv      a3, a0
    li      a0, NODE_WORK_ATTESTER_SLASHING
    mv      a1, s7
    li      a2, 0
    li      a4, 0
    li      a5, 0
    call    node_work
39: LEAVE 48
40: li      t1, NODE_EV_POW_BLOCK
    bne     t0, t1, 45f
    addi    s4, s3, NodeEvent_bytes         # POW_BLOCK: a PowBlock of the node
    ld      t0, 16(s4)
    li      t1, POW_BLOCK_BYTES
    bne     t0, t1, 49f
    PART    t0, t1, s1, Node_pow_blocks
    li      t2, POW_BLOCK_BYTES
    mul     t2, t1, t2
    add     a0, t0, t2
    addi    t1, t1, 1
    sd      t1, (Node_pow_blocks + 8)(s1)
    ld      t0, 8(s4)
    add     a1, s4, t0
    li      a2, POW_BLOCK_BYTES
    call    lantern_copy
49: LEAVE 48
45: li      t1, NODE_EV_ENGINE
    bne     t0, t1, 47f
    ld      t0, 16(s3)
    beqz    t0, 46f
    ld      t0, Node_flags(s1)              # ENGINE 1: the connection failed; the engine is offline
    ori     t0, t0, NODE_FLAG_EL_OFFLINE
    sd      t0, Node_flags(s1)
    call    node_engine_failed
    ld      t0, Node_engine_in(s1)
    add     t0, s1, t0
    sd      zero, 16(t0)
    LEAVE 48
46: addi    s4, s3, NodeEvent_bytes         # ENGINE 0: its bytes join engine_in
    ld      s7, Node_engine_in(s1)
    add     s7, s1, s7
    ld      t0, 16(s7)
    addi    a0, s7, 24
    add     a0, a0, t0
    ld      t1, 8(s4)
    add     a1, s4, t1
    ld      a2, 16(s4)
    add     t0, t0, a2
    sd      t0, 16(s7)
    call    lantern_copy
    call    node_engine_read
    LEAVE 48
47: li      t1, NODE_EV_ENR
    bne     t0, t1, 471f
    mv      a0, s3                          # ENR: a record discv5 found
    call    node_enr
    LEAVE 48
471: li     t1, NODE_EV_API
    bne     t0, t1, 472f
    mv      a0, s3                          # API: the answer to a request
    call    node_api_event
    LEAVE 48
472: li     t1, NODE_EV_API_IDENTITY
    bne     t0, t1, 473f
    ADDQ    a0, s1, Node_api_identity       # API_IDENTITY: the node keeps the texts
    ld      t0, (NodeEvent_bytes + 8)(s3)
    addi    a1, s3, NodeEvent_bytes
    add     a1, a1, t0
    li      a2, API_IDENTITY_SIZE
    call    lantern_copy
    LEAVE 48
473: li     t1, NODE_EV_API_SENT
    bne     t0, t1, 474f
    ld      a0, 16(s3)                      # API_SENT: the next chunk of the connection's stream
    call    node_api_sent
    LEAVE 48
474: li     t1, NODE_EV_API_CLOSED
    bne     t0, t1, 50f
    ld      a0, 16(s3)                      # API_CLOSED: the connection's stream ends
    call    node_api_closed
    LEAVE 48
50: ld      t0, NodeAction_work_kind(s3)    # WORK_DONE
    li      t2, NODE_WORK_BLOCK_ATTESTATION     # a block's vote done: event_votes takes 1 off
    beq     t0, t2, 501f
    li      t2, NODE_WORK_BLOCK_SLASHING
    bne     t0, t2, 502f
501: LDQ    t2, s1, Node_event_votes
    addi    t2, t2, -1
    STQ     t2, s1, Node_event_votes
502: ld     t1, NodeEvent_result(s3)
    li      t2, NODE_WORK_IMPORT_BLOCK
    bne     t0, t2, 60f
    ld      a0, NodeAction_target(s3)
    PART    s4, t2, s1, Node_blocks
    bgeu    a0, t2, 59f
    li      t2, NodeBlock__mem
    mul     t2, a0, t2
    add     s4, s4, t2
    sd      t1, NodeBlock_result(s4)
    li      t2, LANTERN_NEED_JUSTIFIED_STATE
    bne     t1, t2, 51f
    call    node_justified                  # the justified state, then the same import again
    ld      a0, NodeAction_work_kind(s3)
    ld      a1, NodeAction_state_a(s3)
    ld      a2, NodeAction_state_b(s3)
    ld      a3, NodeAction_data(s3)
    ld      a4, NodeAction_target(s3)
    ld      a5, NodeAction_arg(s3)
    call    node_work
    ld      t0, NodeAction_state_c(s3)
    sd      t0, NodeAction_state_c(a0)
    LEAVE 48
51: bnez    t1, 52f
    li      t0, NODE_BLOCK_IMPORTED         # imported: the block event, its votes, then its waiting children
    sd      t0, NodeBlock_status(s4)
    mv      a0, s4
    call    node_api_block_event
    mv      a0, s4
    ld      a1, NodeEvent_index(s3)
    ld      a2, NodeEvent_root(s3)
    call    node_votes
    mv      a0, s4
    call    node_children
    LEAVE 48
52: li      t0, NODE_BLOCK_INVALID          # invalid: its state copy is freed
    sd      t0, NodeBlock_status(s4)
    li      a0, NODE_ACT_STATE_FREE
    ld      a1, NodeBlock_state_id(s4)
    li      a2, 0
    call    node_ids
    sd      zero, NodeBlock_state_id(s4)
59: LEAVE 48
60: li      t2, NODE_WORK_JUSTIFIED_STATE
    bne     t0, t2, 61f
    ld      t0, Node_flags(s1)
    andi    t0, t0, ~NODE_FLAG_JUSTIFIED_PENDING
    sd      t0, Node_flags(s1)
    LEAVE 48
61: li      t2, NODE_WORK_ATTESTATION
    bne     t0, t2, 62f
    li      t2, LANTERN_NEED_TARGET_STATE
    bne     t1, t2, 70f
    ld      a0, NodeEvent_checkpoint(s3)    # the target state, then the same attestation again
    addi    a1, s3, NodeEvent_checkpoint + 8
    call    node_checkpoint_state
    beqz    a0, 71f
    mv      a1, a0
    li      a0, NODE_WORK_ATTESTATION
    ld      a2, NodeAction_state_b(s3)
    ld      a3, NodeAction_data(s3)
    ld      a4, NodeAction_target(s3)
    ld      a5, NodeAction_arg(s3)
    call    node_work
    LEAVE 48
62: li      t2, NODE_WORK_BLOCK_ATTESTATION # BLOCK_ATTESTATION: with NEED_TARGET_STATE, the target state, then again
    bne     t0, t2, 622f
    li      t2, LANTERN_NEED_TARGET_STATE
    bne     t1, t2, 79f
    ld      a0, NodeEvent_checkpoint(s3)
    addi    a1, s3, NodeEvent_checkpoint + 8
    call    node_checkpoint_state
    beqz    a0, 79f
    mv      a1, a0
    li      a0, NODE_WORK_BLOCK_ATTESTATION
    ld      a2, NodeAction_state_b(s3)
    ld      a3, NodeAction_data(s3)
    ld      a4, NodeAction_target(s3)
    ld      a5, NodeAction_arg(s3)
    call    node_work
    LEAVE 48
622: li     t2, NODE_WORK_GOSSIP_VOTE       # GOSSIP_VOTE: the target state; a future slot waits; else the entry goes
    bne     t0, t2, 623f
    li      t2, LANTERN_NEED_TARGET_STATE
    bne     t1, t2, 6221f
    ld      a0, NodeEvent_checkpoint(s3)
    addi    a1, s3, NodeEvent_checkpoint + 8
    call    node_checkpoint_state
    beqz    a0, 6221f
    mv      a1, a0
    li      a0, NODE_WORK_GOSSIP_VOTE
    ld      a2, NodeAction_state_b(s3)
    ld      a3, NodeAction_data(s3)
    ld      a4, NodeAction_target(s3)
    ld      a5, NodeAction_arg(s3)
    call    node_work
    LEAVE 48
6221: ld    a0, NodeAction_target(s3)
    call    node_find_message
    li      t0, -1
    beq     a0, t0, 79f
    mv      s4, a1
    ld      t1, NodeEvent_result(s3)
    li      t2, LANTERN_INVALID_FUTURE_SLOT
    bne     t1, t2, 6222f
    li      t0, NODE_MESSAGE_VOTE
    sd      t0, NodeMessage_state(s4)
    LEAVE 48
6222: li    a0, NODE_ACT_BYTES_FREE
    ld      a1, NodeMessage_data_id(s4)
    li      a2, 0
    call    node_ids
    mv      a0, s4
    call    node_drop_message
    LEAVE 48
623: li     t2, NODE_WORK_SERVE             # SERVE: the chunk to its stream, then the next block or the close
    bne     t0, t2, 63f
    ld      a0, NodeAction_target(s3)
    call    node_find_stream
    li      t0, -1
    beq     a0, t0, 69f
    mv      s4, a1
    ld      t0, NodeEvent_result(s3)
    bnez    t0, 68f
    ld      s7, (NodeEvent_chunk + 16)(s3)
    addi    a0, s7, 32 + 7
    andi    a0, a0, -8
    sd      a0, (L + 32)(sp)
    call    node_out
    beqz    a0, 68f
    ld      t0, (L + 32)(sp)
    li      t1, LIBP2P_EVENT_STREAM_WRITE
    sd      t0, 0(a0)
    sd      t1, 8(a0)
    ld      t1, NodeStream_handle(s4)
    sd      t1, 16(a0)
    sd      s7, 24(a0)
    addi    a0, a0, 32
    addi    a1, s3, NodeEvent_chunk + 24
    mv      a2, s7
    call    lantern_copy
    ld      t0, NodeStream_next(s4)
    addi    t0, t0, 1
    sd      t0, NodeStream_next(s4)
    ld      t1, (NodeStream_list + 16)(s4)
    srli    t1, t1, 3
    bgeu    t0, t1, 67f
    li      t0, NODE_STREAM_SERVE
    sd      t0, NodeStream_state(s4)
    LEAVE 48
67: li      a0, LIBP2P_EVENT_STREAM_CLOSE
    ld      a1, NodeStream_handle(s4)
    call    node_out_handle
    mv      a0, s4
    call    node_drop_stream
69: LEAVE 48
68: li      a0, LIBP2P_EVENT_STREAM_RESET   # no chunk, or no room for it: a reset
    ld      a1, NodeStream_handle(s4)
    call    node_out_handle
    mv      a0, s4
    call    node_drop_stream
    LEAVE 48
63: li      t2, NODE_WORK_GOSSIP            # GOSSIP: the VALIDATION, then a valid block to import
    bne     t0, t2, 75f
    li      s7, LIBP2P_ACCEPT
    beqz    t1, 631f
    li      s7, LIBP2P_IGNORE
    li      t2, LANTERN_GOSSIP_REJECT
    bne     t1, t2, 631f
    li      s7, LIBP2P_REJECT
631: ld     a0, NodeAction_target(s3)
    mv      a1, s7
    call    node_validation
    ld      a1, NodeAction_state_b(s3)      # the proposer state
    beqz    a1, 64f
    li      a0, NODE_ACT_STATE_FREE
    li      a2, 0
    call    node_ids
64: ld      a0, NodeAction_target(s3)
    call    node_find_message
    li      t0, -1
    beq     a0, t0, 66f
    mv      s4, a1
    li      t0, LIBP2P_ACCEPT
    bne     s7, t0, 65f
    mv      a0, s2                          # an operation of the pool keeps its bytes there too
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    mv      a3, a0
    ld      a0, NodeMessage_topic(s4)
    ld      a1, NodeAction_data(s3)
    ld      a2, NodeMessage_length(s4)
    ld      a4, NodeEvent_root(s3)          # an attestation: its slot, committee index and member
    ld      a5, (NodeEvent_root + 8)(s3)
    ld      a6, (NodeEvent_root + 16)(s3)
    call    node_pool_add
    beqz    a0, 639f
    ld      t0, NodeMessage_topic(s4)
    li      t1, GOSSIP_ATTESTER_SLASHING
    beq     t0, t1, 639f
    mv      a0, s4
    call    node_drop_message
    LEAVE 48
639: ld     t0, NodeMessage_topic(s4)
    li      t1, GOSSIP_BEACON_AGGREGATE_AND_PROOF
    bne     t0, t1, 640f
    ld      t1, Node_blobs(s1)              # a valid aggregate: kept for its vote, with half the part free
    ld      t2, Node_messages(s1)
    sub     t1, t1, t2
    li      t2, NodeMessage__mem
    divu    t1, t1, t2
    ld      t2, (Node_messages + 8)(s1)
    slli    t2, t2, 1
    bgeu    t2, t1, 65f
    li      t0, NODE_MESSAGE_VOTE
    sd      t0, NodeMessage_state(s4)
    LEAVE 48
640: li     t1, GOSSIP_ATTESTER_SLASHING
    bne     t0, t1, 641f
    ld      a1, NodeAction_state_c(s3)      # a valid attester slashing keeps the bytes: on_attester_slashing with the justified root's state
    beqz    a1, 65f
    li      a0, NODE_WORK_ATTESTER_SLASHING
    li      a2, 0
    ld      a3, NodeAction_data(s3)
    li      a4, 0
    li      a5, 0
    call    node_work
    mv      a0, s4
    call    node_drop_message
    LEAVE 48
641: li     t1, GOSSIP_BEACON_BLOCK
    bne     t0, t1, 642f
    addi    a0, s3, NodeEvent_root          # a new block keeps the bytes
    call    node_find_block
    li      t0, -1
    bne     a0, t0, 65f
    call    node_new_block
    sd      a0, (L + 40)(sp)
    addi    t2, s3, NodeEvent_root
    COPY32  t0, t2
    addi    t2, t0, NodeBlock_parent_root
    addi    t3, s4, NodeMessage_parent_root
    COPY32  t2, t3
    ld      t2, NodeMessage_slot(s4)
    sd      t2, NodeBlock_slot(t0)
    ld      t2, NodeAction_data(s3)
    sd      t2, NodeBlock_data_id(t0)
    sd      zero, NodeBlock_state_id(t0)
    li      t2, NODE_BLOCK_WAITING
    sd      t2, NodeBlock_status(t0)
    sd      zero, NodeBlock_data_available(t0)
    sd      zero, NodeBlock_result(t0)
    ld      t2, NodeEvent_index(s3)
    sd      t2, NodeBlock_blobs(t0)
    ld      t2, NodeMessage_length(s4)
    sd      t2, NodeBlock_length(t0)
    mv      a0, s4
    call    node_drop_message
    ld      a0, (L + 40)(sp)
    call    node_await
    LEAVE 48
642: li     t1, GOSSIP_BLOB_SIDECAR         # a new valid sidecar keeps the bytes
    beq     t0, t1, 643f
    li      t1, GOSSIP_DATA_COLUMN_SIDECAR  # a column sidecar: of a column the node samples
    bne     t0, t1, 65f
    ld      a0, NodeEvent_index(s3)
    call    node_sampled
    beqz    a0, 65f
643: addi   a0, s3, NodeEvent_root
    ld      a1, NodeEvent_index(s3)
    call    node_blob_held
    bnez    a0, 65f
    call    node_new_blob
    addi    t2, s3, NodeEvent_root
    COPY32  t0, t2
    ld      t2, NodeEvent_index(s3)
    sd      t2, NodeBlob_index(t0)
    ld      t2, NodeMessage_slot(s4)
    sd      t2, NodeBlob_slot(t0)
    ld      t2, NodeAction_data(s3)
    sd      t2, NodeBlob_data_id(t0)
    li      t2, NODE_BLOB_VALID
    sd      t2, NodeBlob_status(t0)
    ld      t2, NodeMessage_length(s4)
    sd      t2, NodeBlob_length(t0)
    mv      a0, s4
    call    node_drop_message
    addi    a0, s3, NodeEvent_root
    call    node_blob_added
    LEAVE 48
65: mv      a0, s4
    call    node_drop_message
66: li      a0, NODE_ACT_BYTES_FREE         # else its bytes go
    ld      a1, NodeAction_data(s3)
    li      a2, 0
    call    node_ids
    LEAVE 48
75: li      t2, NODE_WORK_BACKFILL          # BACKFILL: a block of the backfill, checked
    bne     t0, t2, 751f
    ld      a0, NodeAction_target(s3)
    PART    t2, t3, s1, Node_blocks
    bgeu    a0, t3, 79f
    li      t3, NodeBlock__mem
    mul     t3, a0, t3
    add     s4, t2, t3
    ld      t2, NodeBlock_status(s4)
    li      t3, NODE_BLOCK_BF_CHECKING
    bne     t2, t3, 79f
    bnez    t1, 76f
    addi    t0, s3, NodeEvent_root
    COPY32  s4, t0
    ld      t0, NodeEvent_index(s3)
    sd      t0, NodeBlock_blobs(s4)
    li      t0, NODE_BLOCK_BACKFILL
    sd      t0, NodeBlock_status(s4)
    LEAVE 48
751: li     t2, NODE_WORK_SYNC_BLOCK        # SYNC_BLOCK: the root of a block of a response
    bne     t0, t2, 77f
    ld      a0, NodeAction_target(s3)
    PART    t2, t3, s1, Node_blocks
    bgeu    a0, t3, 79f
    sd      a0, (L + 40)(sp)
    li      t3, NodeBlock__mem
    mul     t3, a0, t3
    add     s4, t2, t3
    ld      t2, NodeBlock_status(s4)
    li      t3, NODE_BLOCK_HASHING
    bne     t2, t3, 79f
    bnez    t1, 76f
    addi    a0, s3, NodeEvent_root          # a new root: the block waits for its parent
    call    node_find_block
    li      t0, -1
    bne     a0, t0, 76f
    addi    t0, s3, NodeEvent_root          # the block waits for its blobs, then its parent
    COPY32  s4, t0
    ld      t0, NodeEvent_index(s3)
    sd      t0, NodeBlock_blobs(s4)
    sd      zero, NodeBlock_data_available(s4)
    ld      a0, (L + 40)(sp)
    call    node_await
    LEAVE 48
76: li      t0, NODE_BLOCK_INVALID          # not a block, or a known root: invalid, its bytes go
    sd      t0, NodeBlock_status(s4)
    li      a0, NODE_ACT_BYTES_FREE
    ld      a1, NodeBlock_data_id(s4)
    li      a2, 0
    call    node_ids
    sd      zero, NodeBlock_data_id(s4)
    LEAVE 48
77: li      t2, NODE_WORK_BLOB              # BLOB: a sidecar of a response, checked
    bne     t0, t2, 85f
    ld      a0, NodeAction_target(s3)
    PART    t2, t3, s1, Node_blobs
    bgeu    a0, t3, 79f
    li      t3, NodeBlob__mem
    mul     t3, a0, t3
    add     s4, t2, t3
    ld      t2, NodeBlob_status(s4)
    li      t3, NODE_BLOB_VERIFYING
    bne     t2, t3, 79f
    bnez    t1, 78f
    ld      a0, NodeBlob_slot(s4)           # fulu: a column the node samples
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_FULU
    bltu    a0, t0, 771f
    ld      a0, NodeBlob_index(s4)
    call    node_sampled
    beqz    a0, 78f
771: addi   a0, s3, NodeEvent_root          # valid, and not held yet: the entry takes the root
    ld      a1, NodeBlob_index(s4)
    call    node_blob_held
    bnez    a0, 78f
    addi    t0, s3, NodeEvent_root
    COPY32  s4, t0
    li      t0, NODE_BLOB_VALID
    sd      t0, NodeBlob_status(s4)
    mv      a0, s4
    call    node_blob_added
    LEAVE 48
78: li      t0, NODE_BLOB_INVALID           # not valid, or held: its bytes go
    sd      t0, NodeBlob_status(s4)
    li      a0, NODE_ACT_BYTES_FREE
    ld      a1, NodeBlob_data_id(s4)
    li      a2, 0
    call    node_ids
    sd      zero, NodeBlob_data_id(s4)
    LEAVE 48
85: li      t2, NODE_WORK_NEW_PAYLOAD       # NEW_PAYLOAD, FORKCHOICE, PREPARE_PAYLOAD: the request to the execution engine
    beq     t0, t2, 86f
    li      t2, NODE_WORK_FORKCHOICE
    beq     t0, t2, 86f
    li      t2, NODE_WORK_PREPARE_PAYLOAD
    beq     t0, t2, 86f
    li      t2, NODE_WORK_GET_PAYLOAD
    bne     t0, t2, 701f
86: bnez    t1, 87f
    li      t2, NODE_WORK_PREPARE_PAYLOAD   # a preparation: its proposer; its call updates the fork choice too
    bne     t0, t2, 851f
    ld      t2, Node_flags(s1)
    andi    t2, t2, ~NODE_FLAG_FCU
    sd      t2, Node_flags(s1)
    ld      t2, NodeEvent_index(s3)
    STQ     t2, s1, Node_payload_proposer
    li      t2, NODE_PAYLOAD_SENT
    STQ     t2, s1, Node_payload_status
851: ld     s7, (NodeEvent_chunk + 16)(s3)
    addi    a1, s7, 48 + 7
    andi    a1, a1, -8
    li      a0, NODE_ACT_ENGINE
    call    node_act
    sd      zero, 16(a0)
    ld      t0, 0(a0)
    addi    t0, t0, -24
    sd      t0, 24(a0)
    li      t0, 24
    sd      t0, 32(a0)
    sd      s7, 40(a0)
    addi    a0, a0, 48
    addi    a1, s3, NodeEvent_chunk + 24
    mv      a2, s7
    call    lantern_copy
    LEAVE 48
87: sd      zero, Node_engine_method(s1)    # no request: the call ends
    ld      t0, NodeAction_work_kind(s3)
    li      t2, NODE_WORK_PREPARE_PAYLOAD
    bne     t0, t2, 870f
    STQ     zero, s1, Node_payload_status
    LEAVE 48
870: li     t2, NODE_WORK_GET_PAYLOAD
    bne     t0, t2, 871f
    ld      a0, NodeAction_target(s3)
    call    node_produce_fail_at
    LEAVE 48
871: li     t2, NODE_WORK_NEW_PAYLOAD
    bne     t0, t2, 79f
    ld      a0, NodeAction_target(s3)
    PART    s4, t2, s1, Node_blocks
    bgeu    a0, t2, 79f
    li      t2, NodeBlock__mem
    mul     t2, a0, t2
    add     s4, s4, t2
    ld      t2, NodeBlock_status(s4)
    li      t3, NODE_BLOCK_EXECUTING
    bne     t2, t3, 79f
    li      t2, LANTERN_NO_PAYLOAD
    bne     t1, t2, 88f
    li      a1, PAYLOAD_STATUS_VALID        # no payload: the import
    call    node_import_now
    LEAVE 48
88: li      t0, NODE_BLOCK_INVALID
    sd      t0, NodeBlock_status(s4)
    li      a0, NODE_ACT_BYTES_FREE
    ld      a1, NodeBlock_data_id(s4)
    li      a2, 0
    call    node_ids
    sd      zero, NodeBlock_data_id(s4)
    LEAVE 48
701: li     t2, NODE_WORK_API_ENCODE        # API_ENCODE: the response to its connection
    bne     t0, t2, 702f
    mv      a0, s3
    call    node_api_done
    LEAVE 48
702: li     t2, NODE_WORK_API_CHUNK         # API_CHUNK: the chunk to its connection
    bne     t0, t2, 703f
    mv      a0, s3
    call    node_api_chunk_done
    LEAVE 48
703: li     t2, NODE_WORK_API_LOOKUP        # API_LOOKUP: the answer for the slot it found
    bne     t0, t2, 704f
    mv      a0, s3
    call    node_api_lookup_done
    LEAVE 48
704: li     t2, NODE_WORK_API_EVENT         # API_EVENT: the text to the streams of its topic
    bne     t0, t2, 705f
    mv      a0, s3
    call    node_api_event_done
    LEAVE 48
705: li     t2, NODE_WORK_API_SUBMIT        # API_SUBMIT: the operations to the pool and out, then the answer
    bne     t0, t2, 706f
    mv      a0, s3
    call    node_api_submit_done
    LEAVE 48
706: li     t2, NODE_WORK_POOL_CHECK        # POOL_CHECK: the entry stays, or goes
    bne     t0, t2, 707f
    mv      a0, s3
    call    node_pool_check_done
    LEAVE 48
707: li     t2, NODE_WORK_PRODUCE_CHECK     # the works of block production: their entry goes on
    beq     t0, t2, 708f
    li      t2, NODE_WORK_PRODUCE_FOLD
    beq     t0, t2, 708f
    li      t2, NODE_WORK_PRODUCE_BLOCK
    bne     t0, t2, 709f
708: mv     a0, s3
    call    node_produce_done
    LEAVE 48
709: addi   t2, t0, -NODE_WORK_PUBLISH_DECODE   # the works of block publishing: their entry goes on
    li      t1, NODE_WORK_PUBLISH_SIDECAR - NODE_WORK_PUBLISH_DECODE
    bgtu    t2, t1, 70f
    mv      a0, s3
    call    node_publish_done
    LEAVE 48
70: li      t2, NODE_WORK_ATTESTATION       # done with an attestation or a slashing: free its bytes
    beq     t0, t2, 71f
    li      t2, NODE_WORK_ATTESTER_SLASHING
    bne     t0, t2, 79f
71: li      a0, NODE_ACT_BYTES_FREE
    ld      a1, NodeAction_data(s3)
    li      a2, 0
    call    node_ids
79: LEAVE 48
END_FUNCTION node_event

/* ------------------------------------------------------------ libp2p */

/* a0 = room for an event of a0 bytes at the end of the node's queued libp2p events, its size written, or 0. Uses t0-t3. */
LOCAL_FUNCTION node_out
    UNWIND_END_PROLOGUE
    P2P_OUT t0
    ld      t1, 16(t0)
    ld      t2, 0(t0)
    addi    t2, t2, -24
    sub     t2, t2, t1
    bltu    t2, a0, 1f
    addi    t3, t0, 24
    add     t3, t3, t1
    add     t1, t1, a0
    sd      t1, 16(t0)
    sd      a0, 0(t3)
    mv      a0, t3
    ret
1:  li      a0, 0
    ret
END_FUNCTION node_out

/* A queued libp2p event of kind a0 with the handle a1: DISCONNECT, STREAM_CLOSE or STREAM_RESET. */
LOCAL_FUNCTION node_out_handle
    FRAME 16
    sd      a0, F(sp)
    sd      a1, (F + 8)(sp)
    li      a0, 24
    call    node_out
    beqz    a0, 1f
    ld      t0, F(sp)
    sd      t0, 8(a0)
    ld      t0, (F + 8)(sp)
    sd      t0, 16(a0)
1:  UNFRAME 16
END_FUNCTION node_out_handle

/* Drops the first a0 queued libp2p events, which libp2p took. */
LOCAL_FUNCTION node_out_consume
    FRAME 0
    P2P_OUT t4
    ld      t1, 16(t4)
    addi    t0, t4, 24
    li      t2, 0
1:  beqz    a0, 2f
    bgeu    t2, t1, 2f
    add     t3, t0, t2
    ld      t3, 0(t3)
    add     t2, t2, t3
    addi    a0, a0, -1
    j       1b
2:  sub     a2, t1, t2
    sd      a2, 16(t4)
    mv      a0, t0
    add     a1, t0, t2
    call    lantern_copy
    UNFRAME 0
END_FUNCTION node_out_consume

/* a0 = the index of the peer of libp2p handle a0, or 2^64 - 1; a1 = its entry. Uses t0-t2. */
LOCAL_FUNCTION node_find_peer
    UNWIND_END_PROLOGUE
    PART    a1, t1, s1, Node_peers
    li      t0, 0
1:  bgeu    t0, t1, 2f
    ld      t2, NodePeer_handle(a1)
    beq     t2, a0, 3f
    addi    a1, a1, NodePeer__mem
    addi    t0, t0, 1
    j       1b
2:  li      a0, -1
    ret
3:  mv      a0, t0
    ret
END_FUNCTION node_find_peer

/* a0 = the index of the stream of libp2p handle a0, or 2^64 - 1; a1 = its entry. Uses t0-t3. */
LOCAL_FUNCTION node_find_stream
    UNWIND_END_PROLOGUE
    PART    a1, t1, s1, Node_streams
    ld      t3, Node_stream_bytes(s1)
    li      t0, 0
1:  bgeu    t0, t1, 2f
    ld      t2, NodeStream_handle(a1)
    beq     t2, a0, 3f
    add     a1, a1, t3
    addi    t0, t0, 1
    j       1b
2:  li      a0, -1
    ret
3:  mv      a0, t0
    ret
END_FUNCTION node_find_stream

/* Removes the stream entry a0: the last entry takes its place. */
LOCAL_FUNCTION node_drop_stream
    FRAME 0
    PART    t0, t1, s1, Node_streams
    ld      t2, Node_stream_bytes(s1)
    addi    t1, t1, -1
    sd      t1, (Node_streams + 8)(s1)
    mul     t3, t1, t2
    add     a1, t0, t3
    beq     a1, a0, 1f
    mv      a2, t2
    call    lantern_copy
1:  UNFRAME 0
END_FUNCTION node_drop_stream

/* Removes the peer entry a0 and its streams. s3 the entry, s4 its handle. */
LOCAL_FUNCTION node_drop_peer
    ENTER 0
    mv      s3, a0
    ld      s4, NodePeer_handle(s3)
1:  PART    a0, t1, s1, Node_streams        # its streams
    ld      t2, Node_stream_bytes(s1)
2:  beqz    t1, 3f
    ld      t3, NodeStream_peer(a0)
    bne     t3, s4, 21f
    call    node_end_stream
    j       1b
21: add     a0, a0, t2
    addi    t1, t1, -1
    j       2b
3:  PART    t0, t1, s1, Node_peers          # the entry: the last takes its place
    addi    t1, t1, -1
    sd      t1, (Node_peers + 8)(s1)
    li      t2, NodePeer__mem
    mul     t2, t1, t2
    add     a1, t0, t2
    beq     a1, s3, 9f
    mv      a0, s3
    li      a2, NodePeer__mem
    call    lantern_copy
9:  LEAVE 0
END_FUNCTION node_drop_peer

/*
 * a0 = the method of protocol index a0 of lantern_node_protocols, or 0; a1 = its version.
 * The protocols go by method, then by version. Uses t0-t4.
 */
LOCAL_FUNCTION node_protocol
    UNWIND_END_PROLOGUE
    ADDRESS t0, reqresp_names
    li      t1, 1
1:  li      t4, REQRESP_METHODS
    bgtu    t1, t4, 8f
    ld      t2, 8(t0)
    srli    t2, t2, 8                       # the mask of its versions
    li      t3, 1
2:  li      t4, 8
    bgeu    t3, t4, 4f
    srl     t4, t2, t3
    andi    t4, t4, 1
    beqz    t4, 3f
    beqz    a0, 5f
    addi    a0, a0, -1
3:  addi    t3, t3, 1
    j       2b
4:  addi    t1, t1, 1
    addi    t0, t0, 16
    j       1b
5:  mv      a0, t1
    mv      a1, t3
    ret
8:  li      a0, 0
    li      a1, 0
    ret
END_FUNCTION node_protocol

/*
 * A response of one chunk on the stream entry a0, result a1, payload a2 of a3 bytes: a
 * STREAM_WRITE and a STREAM_CLOSE, or a STREAM_RESET when the node has no room; then the entry
 * goes. s3 entry, s4 result, s7 payload, s8 its bytes then the chunk's, s9 the scratch size,
 * s10 the chunk's ByteList. Locals: L a ChunkHeader, L+48 a size, L+56 the payload's ByteList.
 */
LOCAL_FUNCTION node_respond
    ENTER 64
    mv      s3, a0
    mv      s4, a1
    mv      s7, a2
    mv      s8, a3
    sd      s8, (L + 48)(sp)
    addi    a0, sp, L + 48
    addi    a1, sp, L + 48
    call    lantern_reqresp_chunk_size
    ld      s9, 0(s5)                       # the chunk, then the payload, at the end of scratch
    addi    t0, s8, 24 + 7
    andi    t0, t0, -8
    ld      t1, (L + 48)(sp)
    addi    t1, t1, 24 + 7
    andi    t1, t1, -8
    add     t2, t0, t1
    bltu    s9, t2, 8f
    sub     t3, s9, t2
    sd      t3, 0(s5)
    add     s10, s5, t3
    add     t4, s10, t1
    li      t5, 24
    sd      t1, 0(s10)
    sd      t5, 8(s10)
    sd      zero, 16(s10)
    sd      t0, 0(t4)
    sd      t5, 8(t4)
    sd      s8, 16(t4)
    sd      t4, (L + 56)(sp)
    addi    a0, t4, 24
    mv      a1, s7
    mv      a2, s8
    call    lantern_copy
    li      t0, CHUNK_RESPONSE
    sd      t0, (L + ChunkHeader_kind)(sp)
    sd      zero, (L + ChunkHeader_context_length)(sp)
    sd      s4, (L + ChunkHeader_result)(sp)
    addi    a0, sp, L
    ld      a1, (L + 56)(sp)
    mv      a2, s5
    mv      a3, s10
    call    lantern_reqresp_write_chunk
    bnez    a0, 8f
    ld      s8, 16(s10)                     # a STREAM_WRITE of the chunk, then a STREAM_CLOSE
    addi    t0, s8, 32 + 7
    andi    t0, t0, -8
    sd      t0, (L + 48)(sp)
    addi    a0, t0, 24
    call    node_out
    beqz    a0, 8f
    ld      t0, (L + 48)(sp)
    li      t1, LIBP2P_EVENT_STREAM_WRITE
    sd      t0, 0(a0)
    sd      t1, 8(a0)
    ld      t1, NodeStream_handle(s3)
    sd      t1, 16(a0)
    sd      s8, 24(a0)
    add     t2, a0, t0
    li      t3, 24
    sd      t3, 0(t2)
    li      t3, LIBP2P_EVENT_STREAM_CLOSE
    sd      t3, 8(t2)
    sd      t1, 16(t2)
    addi    a0, a0, 32
    ld      t0, 8(s10)
    add     a1, s10, t0
    mv      a2, s8
    call    lantern_copy
    j       9f
8:  li      a0, LIBP2P_EVENT_STREAM_RESET
    ld      a1, NodeStream_handle(s3)
    call    node_out_handle
9:  sd      s9, 0(s5)
    mv      a0, s3
    call    node_drop_stream
    LEAVE 64
END_FUNCTION node_respond

/*
 * a0 = the first slot of the epochs a node must serve blocks of: max(0, the store's epoch -
 * compute_min_epochs_for_block_requests) * SLOTS_PER_EPOCH. Apart from node_request, as FORK_CALL
 * takes the labels 81 to 89. s3 the epoch. Locals: L the epochs.
 */
LOCAL_FUNCTION node_serve_slot
    ENTER 16
    mv      a0, s2
    call    node_store_slot
    li      t0, SLOTS_PER_EPOCH
    divu    s3, a0, t0
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    li      t0, -1                          # no sum: every epoch
    sd      t0, L(sp)
    addi    a0, s1, Node_config
    addi    a1, sp, L
    FORK_CALL compute_min_epochs_for_block_requests
    ld      t0, L(sp)
    sub     t1, s3, t0
    bgeu    s3, t0, 1f
    li      t1, 0
1:  li      t0, SLOTS_PER_EPOCH
    mul     a0, t1, t0
    LEAVE 16
END_FUNCTION node_serve_slot

/*
 * The request of the stream entry a0, when its bytes are all there: Status, Ping and MetaData
 * get their answer, Goodbye a close; other methods get ResourceUnavailable. s3 entry, s4 method,
 * s7 the request's size, s8 the scratch size, s9 the payload, s10 a peer or a slot.
 * Locals: L a ChunkHeader, L+48 consumed or an epoch, L+56 a length or a fork digest, L+64 eof
 * or a payload (96).
 */
LOCAL_FUNCTION node_request
    ENTER 208
    mv      s3, a0
    ld      t0, NodeStream_state(s3)        # a request already answered: nothing
    li      t1, NODE_STREAM_EOF
    bgtu    t0, t1, 99f
    ld      s4, NodeStream_method(s3)
    li      t0, REQRESP_METADATA            # MetaData: no request bytes
    beq     s4, t0, 50f
    ld      t1, NodeStream_version(s3)      # the SSZ size of the request
    li      s7, 84
    li      t0, REQRESP_STATUS
    bne     s4, t0, 1f
    li      t0, 2
    bltu    t1, t0, 3f
    li      s7, 92
    j       3f
1:  li      s7, 8
    li      t0, REQRESP_GOODBYE
    beq     s4, t0, 3f
    li      t0, REQRESP_PING
    beq     s4, t0, 3f
    li      s7, 24
    li      t0, REQRESP_BEACON_BLOCKS_BY_RANGE
    beq     s4, t0, 3f
    li      s7, 0                           # by root: a multiple of 32 bytes, at most the request limit
    li      t0, REQRESP_BEACON_BLOCKS_BY_ROOT
    beq     s4, t0, 3f
    li      s7, 16                          # blob sidecars, from deneb on: by range 16 bytes, by root a multiple of 40
    li      t0, REQRESP_BLOB_SIDECARS_BY_RANGE
    beq     s4, t0, 2f
    li      s7, 0
    li      t0, REQRESP_BLOB_SIDECARS_BY_ROOT
    beq     s4, t0, 2f
    li      t0, REQRESP_BEACON_BLOCKS_BY_HEAD   # blocks by head, from fulu on: 40 bytes
    bne     s4, t0, 211f
    li      s7, 40
    j       21f
211: li     t0, REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE   # column sidecars, from fulu on: sizes below
    beq     s4, t0, 21f
    li      t0, REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT
    bne     s4, t0, 92f
21: mv      a0, s2
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_FULU
    bgeu    a0, t0, 3f
    j       92f
2:  mv      a0, s2
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_DENEB
    bgeu    a0, t0, 3f
92: li      a1, 3                           # ResourceUnavailable
    j       91f
3:  sd      zero, (L + ChunkHeader_kind)(sp)        # CHUNK_REQUEST
    sd      zero, (L + ChunkHeader_context_length)(sp)
    addi    a0, s3, NodeStream_list
    addi    a1, sp, L
    call    lantern_reqresp_read_header
    li      t0, LANTERN_REQRESP_MORE
    beq     a0, t0, 80f
    bnez    a0, 90f
    bnez    s7, 4f
    li      t0, REQRESP_BLOB_SIDECARS_BY_ROOT
    beq     s4, t0, 5f
    li      t0, REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE
    beq     s4, t0, 81f
    li      t0, REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT
    beq     s4, t0, 82f
    ld      t0, (L + ChunkHeader_length)(sp)        # by root
    andi    t0, t0, 31
    bnez    t0, 90f
    call    node_max_blocks
    slli    a0, a0, 5
    ld      t0, (L + ChunkHeader_length)(sp)
    bgtu    t0, a0, 90f
    mv      s7, t0
    j       4f
5:  ld      t0, (L + ChunkHeader_length)(sp)        # blob identifiers
    li      t1, 40
    remu    t2, t0, t1
    bnez    t2, 90f
    divu    t0, t0, t1
    sd      t0, (L + 72)(sp)
    call    node_max_blobs
    ld      t0, (L + 72)(sp)
    bgtu    t0, a0, 90f
    ld      s7, (L + ChunkHeader_length)(sp)
    j       4f
81: ld      t0, (L + ChunkHeader_length)(sp)        # column sidecars by range: 20 bytes, then 8 for each column
    li      t1, 20
    bltu    t0, t1, 90f
    sub     t1, t0, t1
    andi    t2, t1, 7
    bnez    t2, 90f
    li      t2, 8 * NUMBER_OF_COLUMNS
    bgtu    t1, t2, 90f
    mv      s7, t0
    j       4f
82: ld      t0, (L + ChunkHeader_length)(sp)        # by root: at most that many identifiers
    li      t1, 4 * REQUEST_BLOCKS_LIMIT_DENEB + REQUEST_BLOCKS_LIMIT_DENEB * (36 + 8 * NUMBER_OF_COLUMNS)
    bgtu    t0, t1, 90f
    mv      s7, t0
4:  ld      t0, (L + ChunkHeader_length)(sp)
    bne     t0, s7, 90f
    ld      s8, 0(s5)                       # the payload's ByteList at the end of scratch
    addi    t1, s7, 24 + 7
    andi    t1, t1, -8
    sub     t0, s8, t1
    sd      t0, 0(s5)
    add     s9, s5, t0
    sd      t1, 0(s9)
    li      t1, 24
    sd      t1, 8(s9)
    sd      zero, 16(s9)
    sd      s7, (L + 56)(sp)                # length and eof, by address
    ld      t0, NodeStream_state(s3)
    addi    t0, t0, -NODE_STREAM_EOF
    seqz    t0, t0
    sd      t0, (L + 64)(sp)
    addi    a0, s3, NodeStream_list
    addi    a1, sp, L + ChunkHeader_header_bytes
    addi    a2, sp, L + 56
    addi    a3, sp, L + 64
    mv      a4, s5
    mv      a5, s9
    addi    a6, sp, L + 48
    call    lantern_reqresp_read_payload
    sd      s8, 0(s5)
    li      t0, LANTERN_REQRESP_MORE
    beq     a0, t0, 80f
    bnez    a0, 90f
    addi    s9, s9, 24                      # the SSZ bytes
    li      t0, REQRESP_BEACON_BLOCKS_BY_RANGE
    beq     s4, t0, 60f
    li      t0, REQRESP_BEACON_BLOCKS_BY_ROOT
    beq     s4, t0, 70f
    li      t0, REQRESP_BLOB_SIDECARS_BY_RANGE
    beq     s4, t0, 165f
    li      t0, REQRESP_BLOB_SIDECARS_BY_ROOT
    beq     s4, t0, 175f
    li      t0, REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE
    beq     s4, t0, 83f
    li      t0, REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT
    beq     s4, t0, 86f
    li      t0, REQRESP_BEACON_BLOCKS_BY_HEAD
    beq     s4, t0, 94f
    li      t0, REQRESP_GOODBYE
    bne     s4, t0, 10f
    li      a0, LIBP2P_EVENT_STREAM_CLOSE   # Goodbye: a close
    ld      a1, NodeStream_handle(s3)
    call    node_out_handle
    mv      a0, s3
    call    node_drop_stream
    LEAVE 208
10: li      t0, REQRESP_PING
    bne     s4, t0, 20f
    ld      t0, Node_metadata_seq(s1)       # Ping: our seq_number
    sd      t0, (L + 64)(sp)
    mv      a0, s3
    li      a1, 0
    addi    a2, sp, L + 64
    li      a3, 8
    call    node_respond
    LEAVE 208
20: ld      a0, NodeStream_peer(s3)         # Status: the peer's, then ours
    mv      a1, s9
    mv      a2, s7
    call    node_peer_status
    addi    a0, sp, L + 64
    call    node_status_bytes
    mv      a0, s3
    li      a1, 0
    addi    a2, sp, L + 64
    mv      a3, s7
    call    node_respond
    LEAVE 208
50: addi    a0, sp, L + 64                  # MetaData: seq_number, attnets, syncnets, custody_group_count
    li      a1, 32
    call    lantern_zero
    ld      t0, Node_metadata_seq(s1)
    sd      t0, (L + 64)(sp)
    ld      t0, Node_attnets(s1)
    sd      t0, (L + 72)(sp)
    LDQ     t0, s1, Node_syncnets
    sb      t0, (L + 80)(sp)
    LDQ     t0, s1, Node_config + CONFIG_CUSTODY_REQUIREMENT
    sd      t0, (L + 56)(sp)
    addi    a0, sp, L + 64 + 17
    addi    a1, sp, L + 56
    li      a2, 8
    call    lantern_copy
    ld      t0, NodeStream_version(s3)
    li      a3, 16
    li      t1, 2
    bltu    t0, t1, 51f
    li      a3, 17
    beq     t0, t1, 51f
    li      a3, 25
51: mv      a0, s3
    li      a1, 0
    addi    a2, sp, L + 64
    call    node_respond
    LEAVE 208
60: ld      s7, 0(s9)                       # BlocksByRange: start_slot, count
    ld      s10, 8(s9)
    ld      t0, Node_earliest_slot(s1)      # from the lower of earliest_slot and backfill_slot
    ld      t1, Node_backfill_slot(s1)
    bleu    t0, t1, 601f
    mv      t0, t1
601: bltu   s7, t0, 92b
    call    node_max_blocks                 # at most the limit, and the room of the list
    bleu    s10, a0, 65f
    mv      s10, a0
65: add     t0, s7, s10                     # the end slot
    bgeu    t0, s7, 66f
    li      t0, -1
66: mv      s10, t0
    li      s8, 0                           # the blocks of the Db in the range, in slot order
    sd      s7, (L + 144)(sp)
600: ld     a0, (L + 144)(sp)
    ld      t0, Node_db_next_slot(s1)
    bgeu    a0, t0, 601f
    bgeu    a0, s10, 601f
    addi    t0, a0, 1
    sd      t0, (L + 144)(sp)
    call    node_db_block
    beqz    a0, 600b
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      a0, NodeStream_request(t2)
    addi    s8, s8, 1
    j       600b
601: sd     s8, (L + 136)(sp)               # then the canonical blocks of the range from the head down, reversed
    addi    s9, s1, Node_head_root
61: mv      a0, s9
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 63f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 63f
    ld      t0, NodeBlock_slot(a1)
    bltu    t0, s7, 63f
    ld      t1, Node_db_next_slot(s1)
    bltu    t0, t1, 63f
    addi    s9, a1, NodeBlock_parent_root
    bgeu    t0, s10, 61b
    ld      t1, NodeBlock_data_id(a1)
    beqz    t1, 61b
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      t1, NodeStream_request(t2)
    addi    s8, s8, 1
    j       61b
63: addi    t0, s3, NodeStream_request      # in slot order: the part from the head, reversed
    slli    t1, s8, 3
    add     t1, t0, t1
    addi    t1, t1, -8
    ld      t2, (L + 136)(sp)
    slli    t2, t2, 3
    add     t0, t0, t2
64: bgeu    t0, t1, 77f
    ld      t2, 0(t0)
    ld      t3, 0(t1)
    sd      t3, 0(t0)
    sd      t2, 0(t1)
    addi    t0, t0, 8
    addi    t1, t1, -8
    j       64b
165: ld     s7, 0(s9)                       # BlobSidecarsByRange: start_slot, count
    ld      s10, 8(s9)
    ld      t0, Node_earliest_slot(s1)
    bltu    s7, t0, 92b
    LDQ     t0, s1, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK    # the indices of a block
    LDQ     t1, s1, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
    bgeu    t0, t1, 1650f
    mv      t0, t1
1650: li     t1, NODE_BLOB_MAX
    bleu    t0, t1, 1651f
    mv      t0, t1
1651: beqz   t0, 78f
    sd      t0, (L + 72)(sp)
    call    node_max_blobs                  # at most the limit: the slots whose sidecars it can hold
    ld      t0, (L + 72)(sp)
    divu    t0, a0, t0
    bleu    s10, t0, 1652f
    mv      s10, t0
1652: add    t0, s7, s10                     # the end slot
    bgeu    t0, s7, 1653f
    li      t0, -1
1653: mv     s10, t0
    li      s8, 0                           # the sidecars of the Db in the range, of deneb or electra, in (slot, index) order
    sd      s7, (L + 144)(sp)
650: ld     a0, (L + 144)(sp)
    ld      t0, Node_db_next_slot(s1)
    bgeu    a0, t0, 653f
    bgeu    a0, s10, 653f
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_DENEB
    beq     a0, t0, 654f
    li      t0, FORK_ELECTRA
    bne     a0, t0, 652f
654: sd     zero, (L + 152)(sp)
651: ld     a1, (L + 152)(sp)
    ld      t0, (L + 72)(sp)
    bgeu    a1, t0, 652f
    addi    t0, a1, 1
    sd      t0, (L + 152)(sp)
    ld      a0, (L + 144)(sp)
    call    node_db_sidecar
    beqz    a0, 651b
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      a0, NodeStream_request(t2)
    addi    s8, s8, 1
    j       651b
652: ld     t0, (L + 144)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 144)(sp)
    j       650b
653: sd     s8, (L + 136)(sp)               # then those of the canonical blocks from the head down, reversed
    addi    s9, s1, Node_head_root
166: mv     a0, s9
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 63b
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 63b
    ld      t0, NodeBlock_slot(a1)
    bltu    t0, s7, 63b
    ld      t1, Node_db_next_slot(s1)
    bltu    t0, t1, 63b
    addi    s9, a1, NodeBlock_parent_root
    bgeu    t0, s10, 166b
    sd      a1, (L + 64)(sp)                # its indices, from the last, of a block of deneb or electra
    mv      a0, t0
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_DENEB
    beq     a0, t0, 1661f
    li      t0, FORK_ELECTRA
    bne     a0, t0, 166b
1661: ld    t0, (L + 72)(sp)
    sd      t0, (L + 80)(sp)
167: ld     a1, (L + 80)(sp)
    beqz    a1, 166b
    addi    a1, a1, -1
    sd      a1, (L + 80)(sp)
    ld      a0, (L + 64)(sp)
    call    node_blob_held
    beqz    a0, 167b
    ld      t1, NodeBlob_data_id(a0)
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      t1, NodeStream_request(t2)
    addi    s8, s8, 1
    j       167b
175: li     t0, 40                          # BlobSidecarsByRoot: the sidecars the node holds, in the request's order
    divu    s7, s7, t0
    li      s8, 0
176: beqz   s7, 77f
    mv      a0, s9
    ld      a1, 32(s9)
    addi    s9, s9, 40
    addi    s7, s7, -1
    call    node_blob_held
    beqz    a0, 1762f
    sd      a0, (L + 72)(sp)
    ld      t0, NodeBlob_data_id(a0)
    sd      t0, (L + 64)(sp)
    ld      a0, NodeBlob_slot(a0)           # a sidecar of deneb or electra
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_DENEB
    beq     a0, t0, 1761f
    li      t0, FORK_ELECTRA
    bne     a0, t0, 176b
1761: ld    a0, (L + 72)(sp)
    call    node_find_block                 # not of an invalid block
    li      t0, -1
    beq     a0, t0, 174f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_INVALID
    beq     t0, t1, 176b
174: ld     t1, (L + 64)(sp)
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      t1, NodeStream_request(t2)
    addi    s8, s8, 1
    j       176b
1762: ld    a0, Node_db(s1)                 # else the Db's sidecar of the root and index, of deneb or electra
    add     a0, s1, a0
    addi    a1, s9, -40
    addi    a2, sp, L + 160
    call    lantern_db_find_root
    ld      a0, (L + 160)(sp)
    li      t0, -1
    beq     a0, t0, 176b
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_DENEB
    beq     a0, t0, 1763f
    li      t0, FORK_ELECTRA
    bne     a0, t0, 176b
1763: ld    a0, (L + 160)(sp)
    ld      a1, -8(s9)
    call    node_db_sidecar
    beqz    a0, 176b
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      a0, NodeStream_request(t2)
    addi    s8, s8, 1
    j       176b
70: srli    s7, s7, 5                       # BlocksByRoot: the blocks the node has, in the request's order
    li      s8, 0
71: beqz    s7, 77f
    mv      a0, s9
    call    node_find_block
    addi    s9, s9, 32
    addi    s7, s7, -1
    li      t0, -1
    beq     a0, t0, 711f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 71b
    ld      t1, NodeBlock_data_id(a1)
    bnez    t1, 712f
711: ld     a0, Node_db(s1)                 # else the Db's block of the root
    add     a0, s1, a0
    addi    a1, s9, -32
    addi    a2, sp, L + 160
    call    lantern_db_find_root
    ld      a0, (L + 160)(sp)
    li      t0, -1
    beq     a0, t0, 71b
    call    node_db_block
    beqz    a0, 71b
    mv      t1, a0
712: slli   t2, s8, 3
    add     t2, t2, s3
    sd      t1, NodeStream_request(t2)
    addi    s8, s8, 1
    j       71b
77: beqz    s8, 78f                         # the list, then a SERVE work for each block in turn
    slli    t0, s8, 3
    sd      t0, (NodeStream_list + 16)(s3)
    sd      zero, NodeStream_next(s3)
    li      t0, NODE_STREAM_SERVE
    sd      t0, NodeStream_state(s3)
    LEAVE 208
78: li      a0, LIBP2P_EVENT_STREAM_CLOSE   # no block: an empty answer
    ld      a1, NodeStream_handle(s3)
    call    node_out_handle
    mv      a0, s3
    call    node_drop_stream
    LEAVE 208
94: ld      t0, 32(s9)                      # BlocksByHead: the ancestry of beacon_root, from it, in descending slot order
    sd      t0, (L + 184)(sp)
    call    node_max_blocks                 # at most count, the limit, and the room of the list
    ld      t0, (L + 184)(sp)
    bgeu    a0, t0, 941f
    sd      a0, (L + 184)(sp)
941: call   node_serve_slot                 # the first slot of the epochs the node serves: L+176
    sd      a0, (L + 176)(sp)
    li      s8, 0
    mv      a0, s9
    call    node_find_block
    li      t0, -1
    bne     a0, t0, 95f
    mv      a0, s9                          # a root the node does not keep: the Db's
    j       97f
95: ld      t0, (L + 184)(sp)               # the node's imported blocks, by parent_root
    bgeu    s8, t0, 77b
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 77b
    ld      t1, NodeBlock_data_id(a1)
    beqz    t1, 96f
    ld      t0, NodeBlock_slot(a1)
    ld      t2, (L + 176)(sp)
    bltu    t0, t2, 77b
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      t1, NodeStream_request(t2)
    addi    s8, s8, 1
    addi    a0, a1, NodeBlock_parent_root
    sd      a0, (L + 192)(sp)
    call    node_find_block
    li      t0, -1
    bne     a0, t0, 95b
    ld      a0, (L + 192)(sp)               # a parent the node does not keep: the Db's
    j       97f
96: mv      a0, a1                          # a block with no bytes: its record in the Db, or none
97: mv      a1, a0                          # the Db's blocks from the root at a0, in descending slot order
    ld      a0, Node_db(s1)
    add     a0, s1, a0
    addi    a2, sp, L + 160
    call    lantern_db_find_root
    ld      s10, (L + 160)(sp)
    li      t0, -1
    beq     s10, t0, 77b
98: ld      t0, (L + 184)(sp)
    bgeu    s8, t0, 77b
    ld      t0, (L + 176)(sp)
    bltu    s10, t0, 77b
    mv      a0, s10
    call    node_db_block
    beqz    a0, 981f
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      a0, NodeStream_request(t2)
    addi    s8, s8, 1
981: ld     t0, Node_db(s1)
    add     t0, s1, t0
    ld      t0, Db_first_slot(t0)
    bleu    s10, t0, 77b
    addi    s10, s10, -1
    j       98b
83: lwu     t0, 16(s9)                      # DataColumnSidecarsByRange: the offset 20, then the columns
    li      t1, 20
    bne     t0, t1, 90f
    sd      zero, (L + 80)(sp)              # the columns asked, then of those the ones sampled
    sd      zero, (L + 88)(sp)
    addi    t2, s7, -20
    srli    t2, t2, 3
    addi    t3, s9, 20
84: beqz    t2, 841f
    LDU64   t0, t3, 0, t4
    addi    t3, t3, 8
    li      t1, NUMBER_OF_COLUMNS
    bgeu    t0, t1, 90f
    srli    t1, t0, 6
    slli    t1, t1, 3
    add     t1, t1, sp
    ld      t4, (L + 80)(t1)
    li      t5, 1
    sll     t5, t5, t0
    or      t4, t4, t5
    sd      t4, (L + 80)(t1)
    addi    t2, t2, -1
    j       84b
841: ld     t0, (L + 80)(sp)
    ld      t1, Node_columns(s1)
    and     t0, t0, t1
    sd      t0, (L + 80)(sp)
    ld      t2, (L + 88)(sp)
    ld      t1, (Node_columns + 8)(s1)
    and     t2, t2, t1
    sd      t2, (L + 88)(sp)
    li      t3, 0                           # their count: the sidecars of a block
842: beqz   t0, 843f
    addi    t1, t0, -1
    and     t0, t0, t1
    addi    t3, t3, 1
    j       842b
843: beqz   t2, 844f
    addi    t1, t2, -1
    and     t2, t2, t1
    addi    t3, t3, 1
    j       843b
844: beqz   t3, 78b
    sd      t3, (L + 72)(sp)
    ld      s7, 0(s9)                       # start_slot, count
    ld      s10, 8(s9)
    ld      t0, Node_earliest_slot(s1)
    bltu    s7, t0, 92b
    call    node_max_columns                # at most the limit: the slots whose sidecars it can hold
    ld      t0, (L + 72)(sp)
    divu    t0, a0, t0
    bleu    s10, t0, 845f
    mv      s10, t0
845: add    t0, s7, s10                     # the end slot
    bgeu    t0, s7, 846f
    li      t0, -1
846: mv     s10, t0
    li      s8, 0                           # the sidecars of the Db in the range, of fulu or later, in (slot, column) order
    sd      s7, (L + 144)(sp)
854: ld     a0, (L + 144)(sp)
    ld      t0, Node_db_next_slot(s1)
    bgeu    a0, t0, 857f
    bgeu    a0, s10, 857f
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_FULU
    bltu    a0, t0, 856f
    sd      zero, (L + 152)(sp)
855: ld     a1, (L + 152)(sp)
    li      t0, 128
    bgeu    a1, t0, 856f
    addi    t0, a1, 1
    sd      t0, (L + 152)(sp)
    srli    t0, a1, 6
    slli    t0, t0, 3
    add     t0, t0, sp
    ld      t0, (L + 80)(t0)
    srl     t0, t0, a1
    andi    t0, t0, 1
    beqz    t0, 855b
    ld      a0, (L + 144)(sp)
    call    node_db_sidecar
    beqz    a0, 855b
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      a0, NodeStream_request(t2)
    addi    s8, s8, 1
    j       855b
856: ld     t0, (L + 144)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 144)(sp)
    j       854b
857: sd     s8, (L + 136)(sp)               # then those of the canonical blocks from the head down, reversed
    addi    s9, s1, Node_head_root
85: mv      a0, s9
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 63b
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 63b
    ld      t0, NodeBlock_slot(a1)
    bltu    t0, s7, 63b
    ld      t1, Node_db_next_slot(s1)
    bltu    t0, t1, 63b
    addi    s9, a1, NodeBlock_parent_root
    bgeu    t0, s10, 85b
    sd      a1, (L + 64)(sp)                # its columns, from the last, of a block of fulu or later
    mv      a0, t0
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_FULU
    bltu    a0, t0, 85b
    li      t0, 128
    sd      t0, (L + 96)(sp)
851: ld     a1, (L + 96)(sp)
    beqz    a1, 85b
    addi    a1, a1, -1
    sd      a1, (L + 96)(sp)
    srli    t0, a1, 6
    slli    t0, t0, 3
    add     t0, t0, sp
    ld      t0, (L + 80)(t0)
    srl     t0, t0, a1
    andi    t0, t0, 1
    beqz    t0, 851b
    ld      a0, (L + 64)(sp)
    call    node_blob_held
    beqz    a0, 851b
    ld      t1, NodeBlob_data_id(a0)
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      t1, NodeStream_request(t2)
    addi    s8, s8, 1
    j       851b
86: beqz    s7, 78b                         # DataColumnSidecarsByRoot: the identifiers' offsets, then each
    lwu     t0, 0(s9)
    andi    t1, t0, 3
    bnez    t1, 90f
    bgtu    t0, s7, 90f
    srli    s10, t0, 2
    beqz    s10, 90f
    li      t1, REQUEST_BLOCKS_LIMIT_DENEB
    bgtu    s10, t1, 90f
    li      s8, 0                           # first check each identifier, and count the columns
    li      t2, 0
87: bgeu    t2, s10, 871f
    slli    t3, t2, 2
    add     t3, t3, s9
    lwu     t0, 0(t3)
    andi    t1, t0, 3                       # offsets of a valid list are multiples of 4
    bnez    t1, 90f
    addi    t4, t2, 1
    mv      t1, s7
    bgeu    t4, s10, 872f
    lwu     t1, 4(t3)
872: bltu   t1, t0, 90f
    bgtu    t1, s7, 90f
    sub     t5, t1, t0                      # block_root, the offset 36, 8 bytes for each column
    li      t6, 36
    bltu    t5, t6, 90f
    sub     t5, t5, t6
    andi    t6, t5, 7
    bnez    t6, 90f
    add     t6, s9, t0
    lwu     a2, 32(t6)
    li      a3, 36
    bne     a2, a3, 90f
    srli    t5, t5, 3
    li      a3, NUMBER_OF_COLUMNS
    bgtu    t5, a3, 90f
    add     s8, s8, t5
    addi    t6, t6, 36
873: beqz   t5, 874f
    LDU64   a2, t6, 0, a3
    li      a4, NUMBER_OF_COLUMNS
    bgeu    a2, a4, 90f
    addi    t6, t6, 8
    addi    t5, t5, -1
    j       873b
874: mv     t2, t4
    j       87b
871: call   node_max_columns                # at most the limit of columns in all
    bgtu    s8, a0, 90f
    li      s8, 0                           # then the sidecars the node holds, in the request's order
    sd      zero, (L + 96)(sp)
88: ld      t2, (L + 96)(sp)
    bgeu    t2, s10, 77b
    slli    t3, t2, 2
    add     t3, t3, s9
    lwu     t0, 0(t3)
    addi    t2, t2, 1
    sd      t2, (L + 96)(sp)
    mv      t1, s7
    bgeu    t2, s10, 881f
    lwu     t1, 4(t3)
881: sub    t1, t1, t0                      # its columns
    addi    t1, t1, -36
    srli    t1, t1, 3
    sd      t1, (L + 112)(sp)
    add     t4, s9, t0                      # its root, copied to L+128, 8-aligned
    addi    t5, sp, L + 128
    li      t6, 8
882: lwu    a2, 0(t4)
    sw      a2, 0(t5)
    addi    t4, t4, 4
    addi    t5, t5, 4
    addi    t6, t6, -1
    bnez    t6, 882b
    addi    t5, sp, L + 128
    sd      t5, (L + 64)(sp)
    addi    t4, t4, 4
    sd      t4, (L + 104)(sp)
89: ld      t1, (L + 112)(sp)
    beqz    t1, 88b
    addi    t1, t1, -1
    sd      t1, (L + 112)(sp)
    ld      t4, (L + 104)(sp)
    LDU64   a1, t4, 0, t5
    addi    t4, t4, 8
    sd      t4, (L + 104)(sp)
    sd      a1, (L + 168)(sp)
    ld      a0, (L + 64)(sp)
    call    node_blob_held
    beqz    a0, 892f
    sd      a0, (L + 120)(sp)
    ld      a0, NodeBlob_slot(a0)           # a sidecar of fulu or later
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_FULU
    bltu    a0, t0, 89b
    ld      a0, (L + 64)(sp)                # not of an invalid block
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 891f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_INVALID
    beq     t0, t1, 89b
891: ld     t0, (L + 120)(sp)
    ld      t1, NodeBlob_data_id(t0)
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      t1, NodeStream_request(t2)
    addi    s8, s8, 1
    j       89b
892: ld     t0, (L + 64)(sp)                # else the Db's column of the root, of fulu or later: the root 8-aligned first
    addi    t1, sp, L + 176
    COPY32W t1, t0
    ld      a0, Node_db(s1)
    add     a0, s1, a0
    addi    a1, sp, L + 176
    addi    a2, sp, L + 160
    call    lantern_db_find_root
    ld      a0, (L + 160)(sp)
    li      t0, -1
    beq     a0, t0, 89b
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_FULU
    bltu    a0, t0, 89b
    ld      a0, (L + 160)(sp)
    ld      a1, (L + 168)(sp)
    call    node_db_sidecar
    beqz    a0, 89b
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      a0, NodeStream_request(t2)
    addi    s8, s8, 1
    j       89b
80: ld      t0, NodeStream_state(s3)        # more bytes come, unless the peer closed
    li      t1, NODE_STREAM_EOF
    beq     t0, t1, 90f
    LEAVE 208
90: li      a1, 1                           # InvalidRequest
91: mv      a0, s3
    mv      a2, sp
    li      a3, 0
    call    node_respond
99: LEAVE 208
END_FUNCTION node_request

/*
 * a0 = the blocks one request may name: MAX_REQUEST_BLOCKS_DENEB from deneb on, else
 * MAX_REQUEST_BLOCKS, of the fork of the store's slot; at most the BufferIds a stream's list
 * holds. Uses t0-t3, a7.
 */
LOCAL_FUNCTION node_max_blocks
    FRAME 0
    mv      a0, s2
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, REQUEST_BLOCKS_LIMIT
    li      t1, FORK_DENEB
    bltu    a0, t1, 1f
    li      t0, REQUEST_BLOCKS_LIMIT_DENEB
1:  ld      t1, Node_stream_bytes(s1)
    addi    t1, t1, -NodeStream__fixed
    srli    t1, t1, 3
    mv      a0, t0
    bleu    t0, t1, 2f
    mv      a0, t1
2:  UNFRAME 0
END_FUNCTION node_max_blocks

/*
 * a0 = the blob sidecars one response may hold: MAX_REQUEST_BLOCKS_DENEB times
 * MAX_BLOBS_PER_BLOCK (deneb) or MAX_BLOBS_PER_BLOCK_ELECTRA (electra and later) of the fork of
 * the store's slot; at most the BufferIds a stream's list holds. Uses t0-t2, a7.
 */
LOCAL_FUNCTION node_max_blobs
    FRAME 0
    mv      a0, s2
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    LDQ     t0, s1, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK
    li      t1, FORK_ELECTRA
    bltu    a0, t1, 1f
    LDQ     t0, s1, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
1:  li      t1, REQUEST_BLOCKS_LIMIT_DENEB
    mulhu   t2, t0, t1
    mul     a0, t0, t1
    beqz    t2, 2f
    li      a0, -1
2:  ld      t0, Node_stream_bytes(s1)
    addi    t0, t0, -NodeStream__fixed
    srli    t0, t0, 3
    bleu    a0, t0, 3f
    mv      a0, t0
3:  UNFRAME 0
END_FUNCTION node_max_blobs

/*
 * a0 = the column sidecars one response may hold: compute_max_request_data_column_sidecars,
 * MAX_REQUEST_BLOCKS_DENEB times NUMBER_OF_COLUMNS; at most the BufferIds a stream's list holds.
 * A leaf; uses t0, t1.
 */
LOCAL_FUNCTION node_max_columns
    UNWIND_END_PROLOGUE
    li      a0, REQUEST_BLOCKS_LIMIT_DENEB * NUMBER_OF_COLUMNS
    ld      t0, Node_stream_bytes(s1)
    addi    t0, t0, -NodeStream__fixed
    srli    t0, t0, 3
    bleu    a0, t0, 1f
    mv      a0, t0
1:  ret
END_FUNCTION node_max_columns

/*
 * a0 = 1 when a stream waits for room for its SERVE work, else 0: a SERVE work of the next
 * block of each stream in NODE_STREAM_SERVE, while the actions have room for it and 4096 bytes.
 * s3 a stream, s4 the streams left.
 */
LOCAL_FUNCTION node_serve
    ENTER 0
    PART    s3, s4, s1, Node_streams
1:  beqz    s4, 8f
    ld      t0, NodeStream_state(s3)
    li      t1, NODE_STREAM_SERVE
    bne     t0, t1, 2f
    ld      t0, 0(s6)
    ld      t1, 8(s6)
    ld      t2, 16(s6)
    sub     t0, t0, t1
    sub     t0, t0, t2
    li      t1, NODE_ACT_WORK_SIZE + 4096
    bltu    t0, t1, 9f
    li      t0, NODE_STREAM_SERVING
    sd      t0, NodeStream_state(s3)
    ld      t0, NodeStream_next(s3)
    slli    t0, t0, 3
    add     t0, t0, s3
    ld      a3, NodeStream_request(t0)
    li      a0, NODE_WORK_SERVE
    li      a1, 0
    li      a2, 0
    ld      a4, NodeStream_handle(s3)
    ld      a5, NodeStream_method(s3)       # arg: the version + 256 * the method
    slli    a5, a5, 8
    ld      t0, NodeStream_version(s3)
    add     a5, a5, t0
    call    node_work
2:  ld      t0, Node_stream_bytes(s1)
    add     s3, s3, t0
    addi    s4, s4, -1
    j       1b
8:  li      a0, 0
    LEAVE 0
9:  li      a0, 1
    LEAVE 0
END_FUNCTION node_serve

/* ------------------------------------------------------------ gossip */

/* a0 = the index of the message of libp2p handle a0, or 2^64 - 1; a1 = its entry. Uses t0-t2, a7. */
LOCAL_FUNCTION node_find_message
    UNWIND_END_PROLOGUE
    PART    a1, t1, s1, Node_messages
    li      t0, 0
1:  bgeu    t0, t1, 2f
    ld      t2, NodeMessage_handle(a1)
    beq     t2, a0, 3f
    addi    a1, a1, NodeMessage__mem
    addi    t0, t0, 1
    j       1b
2:  li      a0, -1
    ret
3:  mv      a0, t0
    ret
END_FUNCTION node_find_message

/* Removes the message entry a0: the last entry takes its place. */
LOCAL_FUNCTION node_drop_message
    FRAME 0
    PART    t0, t1, s1, Node_messages
    addi    t1, t1, -1
    sd      t1, (Node_messages + 8)(s1)
    li      t2, NodeMessage__mem
    mul     t1, t1, t2
    add     a1, t0, t1
    beq     a1, a0, 1f
    li      a2, NodeMessage__mem
    call    lantern_copy
1:  UNFRAME 0
END_FUNCTION node_drop_message

/* a0 = 1 when the actions have room for a0 bytes and 4096 more, else 0. Uses t0-t3. */
LOCAL_FUNCTION node_room
    UNWIND_END_PROLOGUE
    ld      t0, 0(s6)
    ld      t1, 8(s6)
    ld      t2, 16(s6)
    sub     t0, t0, t1
    sub     t0, t0, t2
    li      t3, 4096
    add     t3, a0, t3
    sltu    a0, t0, t3
    xori    a0, a0, 1
    ret
END_FUNCTION node_room

/* A VALIDATION of the libp2p message handle a0 with the result a1. */
LOCAL_FUNCTION node_validation
    FRAME 16
    sd      a0, F(sp)
    sd      a1, (F + 8)(sp)
    li      a0, LIBP2P_EV_VALIDATION_SIZE
    call    node_out
    beqz    a0, 1f
    li      t0, LIBP2P_EVENT_VALIDATION
    sd      t0, 8(a0)
    ld      t0, F(sp)
    sd      t0, 16(a0)
    ld      t0, (F + 8)(sp)
    sd      t0, 24(a0)
1:  UNFRAME 16
END_FUNCTION node_validation

/* The gossip topic a0 with the subnet a1 at the ForkDigest a2: an event of kind a3 (SUBSCRIBE or UNSUBSCRIBE). s3 the topic's length, s4 the kind. Locals: L a GossipTopic, L+24 a ByteList of the topic. */
LOCAL_FUNCTION node_sub
    ENTER 176
    mv      s4, a3
    sd      a2, (L + GossipTopic_fork_digest)(sp)
    sd      a0, (L + GossipTopic_name)(sp)
    sd      a1, (L + GossipTopic_subnet_id)(sp)
    li      t0, 24 + 128
    sd      t0, (L + 24)(sp)
    li      t0, 24
    sd      t0, (L + 32)(sp)
    sd      zero, (L + 40)(sp)
    addi    a0, sp, L
    addi    a1, sp, L + 24
    call    lantern_gossip_topic
    bnez    a0, 9f
    ld      s3, (L + 40)(sp)
    addi    a0, s3, 24 + 7
    andi    a0, a0, -8
    call    node_out
    beqz    a0, 9f
    sd      s4, 8(a0)
    sd      s3, 16(a0)
    addi    a0, a0, 24
    addi    a1, sp, L + 48
    mv      a2, s3
    call    lantern_copy
9:  LEAVE 176
END_FUNCTION node_sub

/*
 * The node's Status at a0 (92 bytes: v2; v1 is its first 84): compute_fork_digest of the store's
 * epoch, the store's finalized checkpoint, head_root and its slot, and earliest_slot. s3 out, s4
 * the slot. Locals: L an epoch, L+8 a ForkDigest, L+16 a slot.
 */
LOCAL_FUNCTION node_status_bytes
    ENTER 32
    mv      s3, a0
    mv      a0, s2
    call    node_store_slot
    mv      s4, a0
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    li      t0, SLOTS_PER_EPOCH
    divu    t0, s4, t0
    sd      t0, L(sp)
    sd      zero, (L + 8)(sp)
    addi    a0, s1, Node_genesis_validators_root
    addi    a1, sp, L
    addi    a2, s1, Node_config
    mv      a3, s5
    addi    a4, sp, L + 8
    FORK_CALL compute_fork_digest
    mv      a0, s3                          # fork_digest
    addi    a1, sp, L + 8
    li      a2, 4
    call    lantern_copy
    addi    a0, s3, 4                       # finalized_root, finalized_epoch
    addi    a1, s2, Store_finalized_checkpoint + 8
    li      a2, 32
    call    lantern_copy
    addi    a0, s3, 36
    addi    a1, s2, Store_finalized_checkpoint
    li      a2, 8
    call    lantern_copy
    ld      t0, Store_finalized_checkpoint(s2)  # the genesis finalized checkpoint: a zero root
    bnez    t0, 2f
    addi    a0, s3, 4
    li      a1, 32
    call    lantern_zero
2:  addi    a0, s3, 44                      # head_root, head_slot
    addi    a1, s1, Node_head_root
    li      a2, 32
    call    lantern_copy
    addi    a0, s1, Node_head_root
    call    node_find_block
    li      t1, 0
    li      t0, -1
    beq     a0, t0, 1f
    ld      t1, NodeBlock_slot(a1)
1:  sd      t1, (L + 16)(sp)
    addi    a0, s3, 76
    addi    a1, sp, L + 16
    li      a2, 8
    call    lantern_copy
    addi    a0, s3, 84                      # earliest_available_slot: Status v2
    addi    a1, s1, Node_earliest_slot
    li      a2, 8
    call    lantern_copy
    LEAVE 32
END_FUNCTION node_status_bytes

/* A SET_ENTRY event at s7 of the size, the key (its length and bytes, little end first) and the value length. Uses t0. */
.macro ENR_ENTRY size, key_len, key, value_len
    li      t0, \size
    sd      t0, 0(s7)
    li      t0, DISCV5_EVENT_SET_ENTRY
    sd      t0, 8(s7)
    li      t0, \key_len
    sd      t0, 16(s7)
    li      t0, \key
    sd      t0, 24(s7)
    sd      zero, 32(s7)
    li      t0, \value_len
    sd      t0, 40(s7)
    sd      zero, 48(s7)
.endm

/*
 * With NODE_FLAG_DISCV5, the node's record entries for the epoch at a0 of the fork a1: a
 * NODE_ACT_DISCV5 of SET_ENTRY events: eth2, attnets, from altair syncnets, from fulu cgc and nfd.
 * s3 the fork, s4 the action, s7 the next event. Locals: L the epoch.
 */
.set NODE_ENR_ACTION, 48 + 64 + 56 * 4
LOCAL_FUNCTION node_enr_entries
    ENTER 16
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_DISCV5
    beqz    t0, 9f
    ld      t0, 0(a0)
    sd      t0, L(sp)
    mv      s3, a1
    li      a0, NODE_ACT_DISCV5
    li      a1, NODE_ENR_ACTION
    call    node_act
    mv      s4, a0
    sd      zero, 16(s4)
    li      t0, NODE_ENR_ACTION - 24
    sd      t0, 24(s4)
    li      t0, 24
    sd      t0, 32(s4)
    addi    s7, s4, 48
    ENR_ENTRY 64, 4, 0x32687465, 16         # eth2: the ENRForkID of the epoch
    addi    a0, s1, Node_genesis_validators_root
    addi    a1, sp, L
    addi    a2, s1, Node_config
    mv      a3, s5
    addi    a4, s7, 48
    mv      t6, s3
    FORK_CALL compute_enr_fork_id
    addi    s7, s7, 64
    ENR_ENTRY 56, 7, 0x007374656e747461, 8  # attnets: the bits of the node's subnets
    ld      t0, Node_attnets(s1)
    sd      t0, 48(s7)
    addi    s7, s7, 56
    li      t0, FORK_ALTAIR
    bltu    s3, t0, 8f
    ENR_ENTRY 56, 8, 0x7374656e636e7973, 1  # syncnets: the bits of the sync subnets the node keeps
    LDQ     t0, s1, Node_syncnets
    sd      t0, 48(s7)
    addi    s7, s7, 56
    li      t0, FORK_FULU
    bltu    s3, t0, 8f
    ENR_ENTRY 56, 3, 0x636763, 0            # cgc: CUSTODY_REQUIREMENT, big-endian, no leading zero byte
    LDQ     t1, s1, Node_config + CONFIG_CUSTODY_REQUIREMENT
    li      t2, 0                           # n bytes: 8 - its leading zero bytes
    mv      t3, t1
1:  beqz    t3, 2f
    addi    t2, t2, 1
    srli    t3, t3, 8
    j       1b
2:  sd      t2, 40(s7)
    beqz    t2, 3f
    li      t3, 0                           # its bytes from the highest
    li      t4, 0
    slli    t5, t2, 3
4:  addi    t5, t5, -8
    srl     a0, t1, t5
    andi    a0, a0, 0xff
    sll     a0, a0, t4
    or      t3, t3, a0
    addi    t4, t4, 8
    bnez    t5, 4b
    sd      t3, 48(s7)
3:  addi    s7, s7, 56
    ENR_ENTRY 56, 3, 0x64666e, 4            # nfd: the next fork digest
    addi    a0, s1, Node_genesis_validators_root
    addi    a1, sp, L
    addi    a2, s1, Node_config
    mv      a3, s5
    addi    a4, s7, 48
    CALL_GLOBAL lantern_fulu_compute_next_fork_digest
    addi    s7, s7, 56
8:  addi    t0, s4, 48                      # the events' bytes
    sub     t0, s7, t0
    sd      t0, 40(s4)
9:  LEAVE 16
END_FUNCTION node_enr_entries

/*
 * a0 = the value of the byte string pair whose key is the a3 (at most 8) bytes of a2, little end
 * first, of the Enr a0 of the record bytes at a1, or 0; a1 = its length. Uses t0-t6.
 */
LOCAL_FUNCTION node_enr_pair
    UNWIND_END_PROLOGUE
    ld      t0, DISCV5_ENR_COUNT(a0)
    addi    t1, a0, DISCV5_ENR_PAIRS
1:  beqz    t0, 3f
    lwu     t2, DISCV5_PAIR_KEY_LEN(t1)
    bne     t2, a3, 2f
    lwu     t3, DISCV5_PAIR_KEY_OFFSET(t1)
    add     t3, a1, t3
    li      t4, 0                           # the key's bytes as a number
    mv      t5, a3
4:  beqz    t5, 5f
    addi    t5, t5, -1
    slli    t4, t4, 8
    add     t6, t3, t5
    lbu     t6, 0(t6)
    or      t4, t4, t6
    j       4b
5:  bne     t4, a2, 2f
    lwu     t2, DISCV5_PAIR_VALUE_KIND(t1)
    li      t3, 1
    bne     t2, t3, 2f
    lwu     t2, DISCV5_PAIR_VALUE_OFFSET(t1)
    add     a0, a1, t2
    lwu     a1, DISCV5_PAIR_VALUE_LEN(t1)
    ret
2:  addi    t1, t1, DISCV5_PAIR_SIZE
    addi    t0, t0, -1
    j       1b
3:  li      a0, 0
    li      a1, 0
    ret
END_FUNCTION node_enr_pair

/*
 * The node record of the NODE_EV_ENR a0: a DIAL of its TCP address when it has an ip, a tcp pair
 * of 1 or 2 bytes, an eth2 pair of compute_fork_digest at the store's epoch, a peer ID no NodePeer
 * has, and room for a peer. s3 the record's ByteList, s4 the Enr, s7 the scratch size, restored on
 * return, s8 the port, s9 the DIAL. Locals: L the peer ID (39 bytes), L+48 the node's Status
 * (96), whose first 4 bytes are that digest.
 */
LOCAL_FUNCTION node_enr
    ENTER 144
    addi    s3, a0, NodeEvent_bytes
    ld      s7, 0(s5)
    li      t0, DISCV5_ENR_SIZE + DISCV5_ENR_SCRATCH    # the Enr and its scratch at the end of scratch
    bltu    s7, t0, 9f
    sub     t1, s7, t0
    sd      t1, 0(s5)
    add     s4, s5, t1
    li      t0, DISCV5_ENR_SIZE
    add     a1, s4, t0
    li      t0, DISCV5_ENR_SCRATCH
    sd      t0, 0(a1)
    mv      a0, s3
    mv      a2, s4
    CALL_GLOBAL discv5_enr_decode
    bnez    a0, 9f
    ld      t0, DISCV5_ENR_HAS(s4)          # an ip
    andi    t0, t0, 1
    beqz    t0, 9f
    mv      a0, s4                          # a tcp port of 1 or 2 bytes
    ld      a1, 8(s3)
    add     a1, s3, a1
    li      a2, 0x706374
    li      a3, 3
    call    node_enr_pair
    beqz    a0, 9f
    li      t0, 1
    bltu    a1, t0, 9f
    li      t0, 2
    bgtu    a1, t0, 9f
    lbu     s8, 0(a0)
    bne     a1, t0, 1f
    lbu     t1, 1(a0)
    slli    s8, s8, 8
    or      s8, s8, t1
1:  mv      a0, s4                          # an eth2 of the node's fork_digest
    ld      a1, 8(s3)
    add     a1, s3, a1
    li      a2, 0x32687465
    li      a3, 4
    call    node_enr_pair
    beqz    a0, 9f
    li      t0, 4
    bltu    a1, t0, 9f
    lbu     t0, 0(a0)
    lbu     t1, 1(a0)
    slli    t1, t1, 8
    or      t0, t0, t1
    lbu     t1, 2(a0)
    slli    t1, t1, 16
    or      t0, t0, t1
    lbu     t1, 3(a0)
    slli    t1, t1, 24
    or      t0, t0, t1
    sw      t0, L(sp)
    addi    a0, sp, L + 48
    call    node_status_bytes
    lwu     t0, L(sp)
    lwu     t1, (L + 48)(sp)
    bne     t0, t1, 9f
    li      t0, 0x0000211202082500          # the peer ID: identity multihash of the protobuf secp256k1 key
    sd      t0, L(sp)
    addi    a0, sp, L + 6
    addi    a1, s4, DISCV5_ENR_PUBKEY
    li      a2, 33
    call    lantern_copy
    PART    t0, t1, s1, Node_peers          # not a peer of the node
    li      t3, 39
2:  beqz    t1, 4f
    ld      t2, NodePeer_id_len(t0)
    bne     t2, t3, 3f
    li      t2, 0
5:  bgeu    t2, t3, 9f
    add     t4, t0, t2
    lbu     t4, NodePeer_id(t4)
    add     t5, sp, t2
    lbu     t5, L(t5)
    bne     t4, t5, 3f
    addi    t2, t2, 1
    j       5b
3:  addi    t0, t0, NodePeer__mem
    addi    t1, t1, -1
    j       2b
4:  ld      t0, (Node_peers + 8)(s1)        # room for a peer
    ld      t1, Node_dialing(s1)
    add     t0, t0, t1
    ld      t2, Node_streams(s1)
    ld      t3, Node_peers(s1)
    sub     t2, t2, t3
    li      t3, NodePeer__mem
    divu    t2, t2, t3
    bgeu    t0, t2, 9f
    li      a0, LIBP2P_EV_DIAL_SIZE         # the DIAL
    call    node_out
    beqz    a0, 9f
    mv      s9, a0
    li      t0, LIBP2P_EVENT_DIAL
    sd      t0, 8(s9)
    call    node_new_id
    li      t0, NODE_DIAL_TAG
    or      a0, a0, t0
    sd      a0, LIBP2P_EV_TAG(s9)
    li      t0, 4
    sd      t0, (LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_FAMILY)(s9)
    sd      s8, (LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_PORT)(s9)
    sd      zero, (LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_IP)(s9)
    sd      zero, (LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_IP + 8)(s9)
    lwu     t0, DISCV5_ENR_IP4(s4)
    sw      t0, (LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_IP)(s9)
    li      t0, 39
    sd      t0, LIBP2P_EV_DIAL_ID_LEN(s9)
    addi    a0, s9, LIBP2P_EV_DIAL_ID
    li      a1, 48
    call    lantern_zero
    addi    a0, s9, LIBP2P_EV_DIAL_ID
    addi    a1, sp, L
    li      a2, 39
    call    lantern_copy
    li      t0, LIBP2P_TCP
    sd      t0, LIBP2P_EV_DIAL_TRANSPORT(s9)
    sd      zero, (LIBP2P_EV_DIAL_TRANSPORT + 8)(s9)
    ld      t0, Node_dialing(s1)
    addi    t0, t0, 1
    sd      t0, Node_dialing(s1)
9:  sd      s7, 0(s5)
    LEAVE 144
END_FUNCTION node_enr

/*
 * With NODE_FLAG_DISCV5 and room for more peers, a NODE_ACT_DISCV5 of a LOOKUP whose target is
 * the 32 entropy bytes of the tick a0, when lookup_ms is 0 or NODE_LOOKUP_MS before time_ms.
 * s3 the tick, s4 the action.
 */
LOCAL_FUNCTION node_lookup
    ENTER 0
    mv      s3, a0
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_DISCV5
    beqz    t0, 9f
    ld      t0, (Node_peers + 8)(s1)
    ld      t1, Node_dialing(s1)
    add     t0, t0, t1
    ld      t2, Node_streams(s1)
    ld      t3, Node_peers(s1)
    sub     t2, t2, t3
    li      t3, NodePeer__mem
    divu    t2, t2, t3
    bgeu    t0, t2, 9f
    ld      t0, Node_lookup_ms(s1)
    beqz    t0, 1f
    ld      t1, Node_time_ms(s1)
    li      t2, NODE_LOOKUP_MS
    add     t0, t0, t2
    bltu    t1, t0, 9f
1:  li      a0, 96                          # the action: 16, 24 a ByteList, 48 the LOOKUP
    call    node_room
    beqz    a0, 9f
    li      a0, NODE_ACT_DISCV5
    li      a1, 96
    call    node_act
    mv      s4, a0
    sd      zero, 16(s4)
    li      t0, 72
    sd      t0, 24(s4)
    li      t0, 24
    sd      t0, 32(s4)
    li      t0, DISCV5_EV_LOOKUP_SIZE
    sd      t0, 40(s4)
    sd      t0, 48(s4)
    li      t0, DISCV5_EVENT_LOOKUP
    sd      t0, 56(s4)
    addi    a0, s4, 48 + DISCV5_EV_LOOKUP_TARGET
    addi    a1, s3, LIBP2P_TICK_ENTROPY
    li      a2, 32
    call    lantern_copy
    ld      t0, Node_time_ms(s1)            # 0 becomes 1
    seqz    t1, t0
    add     t0, t0, t1
    sd      t0, Node_lookup_ms(s1)
9:  LEAVE 0
END_FUNCTION node_lookup

/*
 * The gossip topics of the fork a0 at the ForkDigest a1: an event of kind a2 (SUBSCRIBE or
 * UNSUBSCRIBE) for each. s3 the fork, s4 a subnet, s7 the subnets. Locals: L the digest, L+8 the
 * kind.
 */
LOCAL_FUNCTION node_topics
    ENTER 16
    mv      s3, a0
    sd      a1, L(sp)
    sd      a2, (L + 8)(sp)
    .irp name, GOSSIP_BEACON_BLOCK, GOSSIP_BEACON_AGGREGATE_AND_PROOF, GOSSIP_VOLUNTARY_EXIT, GOSSIP_PROPOSER_SLASHING, GOSSIP_ATTESTER_SLASHING
    li      a0, \name
    li      a1, 0
    ld      a2, L(sp)
    ld      a3, (L + 8)(sp)
    call    node_sub
    .endr
    li      s4, 0                           # beacon_attestation of each subnet the node keeps
10: li      t0, ATTESTATION_SUBNET_COUNT
    bgeu    s4, t0, 12f
    LDQ     t0, s1, Node_subnets
    srl     t0, t0, s4
    andi    t0, t0, 1
    beqz    t0, 11f
    li      a0, GOSSIP_BEACON_ATTESTATION
    mv      a1, s4
    ld      a2, L(sp)
    ld      a3, (L + 8)(sp)
    call    node_sub
11: addi    s4, s4, 1
    j       10b
12:
    li      t0, FORK_ALTAIR
    bltu    s3, t0, 9f
    li      a0, GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF
    li      a1, 0
    ld      a2, L(sp)
    ld      a3, (L + 8)(sp)
    call    node_sub
    li      s4, 0                           # sync_committee of each sync subnet the node keeps
13: li      t0, SYNC_COMMITTEE_SUBNET_COUNT
    bgeu    s4, t0, 14f
    LDQ     t0, s1, Node_syncnets
    srl     t0, t0, s4
    andi    t0, t0, 1
    beqz    t0, 15f
    li      a0, GOSSIP_SYNC_COMMITTEE
    mv      a1, s4
    ld      a2, L(sp)
    ld      a3, (L + 8)(sp)
    call    node_sub
15: addi    s4, s4, 1
    j       13b
14: li      t0, FORK_CAPELLA
    bltu    s3, t0, 9f
    li      a0, GOSSIP_BLS_TO_EXECUTION_CHANGE
    li      a1, 0
    ld      a2, L(sp)
    ld      a3, (L + 8)(sp)
    call    node_sub
    li      t0, FORK_DENEB                  # deneb and electra: every blob sidecar subnet
    bltu    s3, t0, 9f
    li      t0, FORK_FULU
    bgeu    s3, t0, 4f
    LDQ     s7, s1, Node_config + CONFIG_BLOB_SIDECAR_SUBNET_COUNT
    li      t0, FORK_ELECTRA
    bltu    s3, t0, 2f
    LDQ     s7, s1, Node_config + CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA
2:  li      s4, 0
3:  bgeu    s4, s7, 9f
    li      a0, GOSSIP_BLOB_SIDECAR
    mv      a1, s4
    ld      a2, L(sp)
    ld      a3, (L + 8)(sp)
    call    node_sub
    addi    s4, s4, 1
    j       3b
4:  LDQ     s7, s1, Node_config + CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT   # fulu: the subnet of each column sampled, once
    beqz    s7, 9f
    li      s8, 0                           # the subnets subscribed: s8 below 64, s9 from 64
    li      s9, 0
    li      s4, 0
5:  li      t0, 128
    bgeu    s4, t0, 9f
    mv      a0, s4
    call    node_sampled
    beqz    a0, 7f
    remu    a1, s4, s7                      # compute_subnet_for_data_column_sidecar: column % DATA_COLUMN_SIDECAR_SUBNET_COUNT
    li      t0, 1
    sll     t0, t0, a1
    li      t1, 64
    bgeu    a1, t1, 6f
    and     t1, s8, t0
    bnez    t1, 7f
    or      s8, s8, t0
    j       61f
6:  and     t1, s9, t0
    bnez    t1, 7f
    or      s9, s9, t0
61: li      a0, GOSSIP_DATA_COLUMN_SIDECAR
    ld      a2, L(sp)
    ld      a3, (L + 8)(sp)
    call    node_sub
7:  addi    s4, s4, 1
    j       5b
9:  LEAVE 16
END_FUNCTION node_topics

/*
 * L0: a0 = the attestation subnets of the node at epoch a0 (node.md), bit i for subnet i:
 * lantern_compute_subscribed_subnet of the node ID for each index below SUBNETS_PER_NODE, of the
 * fork of the store's slot; 0 on a failure. Apart from node_subscribe, as FORK_CALL takes the
 * labels 81 to 89. s3 the index, s4 the subnets, s7 the fork. Locals: L the epoch, L+8 the index,
 * L+16 a subnet.
 */
LOCAL_FUNCTION node_attnets
    ENTER 32
    sd      a0, L(sp)
    mv      a0, s2
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    mv      s7, a0
    li      s4, 0
    li      s3, 0
1:  LDQ     t0, s1, Node_config + CONFIG_SUBNETS_PER_NODE
    bgeu    s3, t0, 9f
    li      t0, ATTESTATION_SUBNET_COUNT
    bgeu    s3, t0, 9f
    sd      s3, (L + 8)(sp)
    mv      t6, s7
    addi    a0, s1, Node_node_id
    addi    a1, sp, L
    addi    a2, sp, L + 8
    addi    a3, s1, Node_config
    mv      a4, s5
    addi    a5, sp, L + 16
    FORK_CALL compute_subscribed_subnet
    bnez    a0, 8f
    ld      t0, (L + 16)(sp)
    andi    t0, t0, ATTESTATION_SUBNET_COUNT - 1
    li      t1, 1
    sll     t1, t1, t0
    or      s4, s4, t1
    addi    s3, s3, 1
    j       1b
8:  li      s4, 0
9:  mv      a0, s4
    LEAVE 32
END_FUNCTION node_attnets

/* L0: attnets takes the subnets of epoch a0; a change adds 1 to metadata_seq. */
LOCAL_FUNCTION node_attnets_set
    FRAME 0
    call    node_attnets
    ld      t0, Node_attnets(s1)
    beq     a0, t0, 1f
    sd      a0, Node_attnets(s1)
    ld      t0, Node_metadata_seq(s1)
    addi    t0, t0, 1
    sd      t0, Node_metadata_seq(s1)
1:  UNFRAME 0
END_FUNCTION node_attnets_set

/*
 * L0: an event a1 (SUBSCRIBE or UNSUBSCRIBE) of the topic a2 (beacon_attestation or
 * sync_committee) of each subnet of a0, at fork_digest and at next_digest when it is not 0. s3 the
 * subnets, s4 the event, s5 the topic, s7 a subnet.
 */
LOCAL_FUNCTION node_subnet_topics
    ENTER 0
    mv      s3, a0
    mv      s4, a1
    mv      s5, a2
    li      s7, 0
1:  li      t0, 64
    bgeu    s7, t0, 9f
    srl     t0, s3, s7
    andi    t0, t0, 1
    beqz    t0, 3f
    mv      a0, s5
    mv      a1, s7
    ld      a2, Node_fork_digest(s1)
    mv      a3, s4
    call    node_sub
    ld      a2, Node_next_digest(s1)
    beqz    a2, 3f
    mv      a0, s5
    mv      a1, s7
    mv      a3, s4
    call    node_sub
3:  addi    s7, s7, 1
    j       1b
9:  LEAVE 0
END_FUNCTION node_subnet_topics

/*
 * L0: a0 = the beacon_attestation subnets the node keeps: those of attnets, and each whose
 * subnet_until is above the store s2's slot (an aggregator's subscription).
 */
LOCAL_FUNCTION node_subnets_want
    FRAME 0
    mv      a0, s2
    call    node_store_slot
    ld      t1, Node_attnets(s1)
    ADDQ    t2, s1, Node_subnet_until
    li      t3, 0
1:  li      t0, ATTESTATION_SUBNET_COUNT
    bgeu    t3, t0, 9f
    slli    t4, t3, 3
    add     t4, t2, t4
    ld      t4, 0(t4)
    bleu    t4, a0, 2f
    li      t5, 1
    sll     t5, t5, t3
    or      t1, t1, t5
2:  addi    t3, t3, 1
    j       1b
9:  mv      a0, t1
    UNFRAME 0
END_FUNCTION node_subnets_want

/* L0: a0 = the sync_committee subnets the node keeps: each whose sync_until is above the epoch of the store s2's slot. */
LOCAL_FUNCTION node_syncnets_want
    FRAME 0
    mv      a0, s2
    call    node_store_slot
    li      t0, SLOTS_PER_EPOCH
    divu    a0, a0, t0
    li      t1, 0
    ADDQ    t2, s1, Node_sync_until
    li      t3, 0
1:  li      t0, SYNC_COMMITTEE_SUBNET_COUNT
    bgeu    t3, t0, 9f
    slli    t4, t3, 3
    add     t4, t2, t4
    ld      t4, 0(t4)
    bleu    t4, a0, 2f
    li      t5, 1
    sll     t5, t5, t3
    or      t1, t1, t5
2:  addi    t3, t3, 1
    j       1b
9:  mv      a0, t1
    UNFRAME 0
END_FUNCTION node_syncnets_want

/*
 * The node's gossip topics (node.md; altair p2p-interface.md, Transitioning the gossip), one change
 * a step, when p2p_out has room: the topics of the fork of the store's epoch at its ForkDigest,
 * once for each digest, with the record entries; else those of the epoch NODE_SUBSCRIBE_AHEAD
 * later, when its digest differs; else, from NODE_SUBSCRIBE_AHEAD epochs after the digest changed,
 * the old digest's topics leave. s3 the epoch, s4 its fork, s7 its digest, s8 a fork, s9 a digest.
 * Locals: L an epoch, L+8 a ForkDigest.
 */
LOCAL_FUNCTION node_subscribe
    ENTER 16
    P2P_OUT t0
    ld      t1, 0(t0)
    ld      t2, 16(t0)
    addi    t1, t1, -24
    sub     t1, t1, t2
    li      t2, 64 * 128
    bltu    t1, t2, 9f
    li      a0, NODE_ENR_ACTION             # and the actions room for the record entries
    call    node_room
    beqz    a0, 9f
    mv      a0, s2
    call    node_store_slot
    li      t0, SLOTS_PER_EPOCH
    divu    s3, a0, t0
    sd      s3, L(sp)
    addi    a1, s1, Node_config
    call    node_fork
    mv      s4, a0
    mv      t6, a0
    sd      zero, (L + 8)(sp)
    addi    a0, s1, Node_genesis_validators_root
    addi    a1, sp, L
    addi    a2, s1, Node_config
    mv      a3, s5
    addi    a4, sp, L + 8
    FORK_CALL compute_fork_digest
    bnez    a0, 9f
    ld      s7, (L + 8)(sp)
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_SUBSCRIBED
    beqz    t0, 1f
    ld      t1, Node_fork_digest(s1)
    beq     s7, t1, 20f
    sd      t1, Node_old_digest(s1)         # a new digest: the old one's topics leave later
    addi    t0, s3, NODE_SUBSCRIBE_AHEAD
    sd      t0, Node_old_epoch(s1)
    li      a0, 0                           # of the fork of the epoch before
    beqz    s3, 11f
    addi    a0, s3, -1
    li      t0, SLOTS_PER_EPOCH
    mul     a0, a0, t0
11: addi    a1, s1, Node_config
    call    node_fork
    sd      a0, Node_old_fork(s1)
1:  sd      s7, Node_fork_digest(s1)
    ld      t0, Node_flags(s1)
    ori     t0, t0, NODE_FLAG_SUBSCRIBED
    sd      t0, Node_flags(s1)
    mv      a0, s3                          # the subnets of the epoch, then those the node keeps
    call    node_attnets_set
    call    node_subnets_want
    STQ     a0, s1, Node_subnets
    addi    a0, sp, L                       # the record entries of the new digest
    mv      a1, s4
    call    node_enr_entries
    ld      t0, Node_next_digest(s1)        # its topics, unless they are there ahead
    sd      zero, Node_next_digest(s1)
    beq     t0, s7, 9f
    mv      a0, s4
    mv      a1, s7
    li      a2, LIBP2P_EVENT_SUBSCRIBE
    call    node_topics
    j       9f
20: addi    t0, s3, NODE_SUBSCRIBE_AHEAD    # ahead: the topics of the digest of a later epoch
    sd      t0, L(sp)
    li      t1, SLOTS_PER_EPOCH
    mul     a0, t0, t1
    addi    a1, s1, Node_config
    call    node_fork
    mv      s8, a0
    mv      t6, a0
    sd      zero, (L + 8)(sp)
    addi    a0, s1, Node_genesis_validators_root
    addi    a1, sp, L
    addi    a2, s1, Node_config
    mv      a3, s5
    addi    a4, sp, L + 8
    FORK_CALL compute_fork_digest
    bnez    a0, 9f
    ld      s9, (L + 8)(sp)
    beq     s9, s7, 30f
    ld      t0, Node_next_digest(s1)
    beq     t0, s9, 30f
    sd      s9, Node_next_digest(s1)
    mv      a0, s8
    mv      a1, s9
    li      a2, LIBP2P_EVENT_SUBSCRIBE
    call    node_topics
    j       9f
30: mv      a0, s3                          # the subnets of the epoch, when they changed: attnets and the record
    call    node_attnets
    ld      s9, Node_attnets(s1)
    beq     a0, s9, 32f
    mv      a0, s3
    call    node_attnets_set
    sd      s3, L(sp)
    addi    a0, sp, L
    mv      a1, s4
    call    node_enr_entries
    j       9f
32: call    node_subnets_want               # the subnets the node keeps, when they changed
    LDQ     s9, s1, Node_subnets
    beq     a0, s9, 33f
    mv      s8, a0
    not     a0, s8                          # those that go, then those that come
    and     a0, a0, s9
    li      a1, LIBP2P_EVENT_UNSUBSCRIBE
    li      a2, GOSSIP_BEACON_ATTESTATION
    call    node_subnet_topics
    not     a0, s9
    and     a0, a0, s8
    li      a1, LIBP2P_EVENT_SUBSCRIBE
    li      a2, GOSSIP_BEACON_ATTESTATION
    call    node_subnet_topics
    STQ     s8, s1, Node_subnets
    j       9f
33: li      t0, FORK_ALTAIR                 # the sync subnets the node keeps, when they changed: the MetaData and the record
    bltu    s4, t0, 31f
    call    node_syncnets_want
    LDQ     s9, s1, Node_syncnets
    beq     a0, s9, 31f
    mv      s8, a0
    not     a0, s8
    and     a0, a0, s9
    li      a1, LIBP2P_EVENT_UNSUBSCRIBE
    li      a2, GOSSIP_SYNC_COMMITTEE
    call    node_subnet_topics
    not     a0, s9
    and     a0, a0, s8
    li      a1, LIBP2P_EVENT_SUBSCRIBE
    li      a2, GOSSIP_SYNC_COMMITTEE
    call    node_subnet_topics
    STQ     s8, s1, Node_syncnets
    ld      t0, Node_metadata_seq(s1)
    addi    t0, t0, 1
    sd      t0, Node_metadata_seq(s1)
    sd      s3, L(sp)
    addi    a0, sp, L
    mv      a1, s4
    call    node_enr_entries
    j       9f
31: ld      a1, Node_old_digest(s1)         # the old digest's topics leave
    beqz    a1, 9f
    ld      t0, Node_old_epoch(s1)
    bltu    s3, t0, 9f
    sd      zero, Node_old_digest(s1)
    ld      a0, Node_old_fork(s1)
    li      a2, LIBP2P_EVENT_UNSUBSCRIBE
    call    node_topics
9:  LEAVE 16
END_FUNCTION node_subscribe

/*
 * The MESSAGE a0 of libp2p, whose data is in the libp2p state a1: its MESSAGE_ID, then a
 * NodeMessage with its bytes, uncompressed, in a BYTES_PUT. s3 the notice, s4 the libp2p state,
 * s7 the entry, s8 the scratch size, restored on return, s9 the topic's ByteList, then the
 * bytes', s10 the data's ByteList. Locals: L a GossipTopic, L+24 the message-id, L+48 a length.
 */
LOCAL_FUNCTION node_message
    ENTER 64
    mv      s3, a0
    mv      s4, a1
    ld      s8, 0(s5)
    ld      t0, LIBP2P_ACT_MSG_TOPIC_LEN(s3)    # the topic's and the data's ByteLists at the end of scratch
    addi    t0, t0, 24 + 7
    andi    t0, t0, -8
    ld      t1, LIBP2P_ACT_MSG_DATA_LEN(s3)
    addi    t1, t1, 24 + 7
    andi    t1, t1, -8
    add     t2, t0, t1
    li      t3, LANTERN_SCRATCH_FIXED
    add     t3, t2, t3
    bltu    s8, t3, 99f
    sub     t3, s8, t2
    sd      t3, 0(s5)
    add     s9, s5, t3
    add     s10, s9, t0
    li      t3, 24
    sd      t0, 0(s9)
    sd      t3, 8(s9)
    ld      t0, LIBP2P_ACT_MSG_TOPIC_LEN(s3)
    sd      t0, 16(s9)
    sd      t1, 0(s10)
    sd      t3, 8(s10)
    ld      t1, LIBP2P_ACT_MSG_DATA_LEN(s3)
    sd      t1, 16(s10)
    addi    a0, s9, 24
    addi    a1, s3, LIBP2P_ACT_MSG_TOPIC
    mv      a2, t0
    call    lantern_copy
    addi    a0, s10, 24
    ld      t0, LIBP2P_ACT_MSG_DATA_OFF(s3)
    add     a1, s4, t0
    ld      a2, LIBP2P_ACT_MSG_DATA_LEN(s3)
    call    lantern_copy
    mv      a0, s9                          # the topic
    addi    a1, sp, L
    call    lantern_gossip_topic_parse
    beqz    a0, 1f
    sd      zero, (L + GossipTopic_name)(sp)
    sd      zero, (L + GossipTopic_subnet_id)(sp)
    ld      t0, Node_fork_digest(s1)        # a topic of no name: as of the node's ForkDigest
    sd      t0, (L + GossipTopic_fork_digest)(sp)
1:  mv      a0, s2                          # the message-id, of the fork of the store's slot
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s9
    mv      a1, s10
    addi    a2, s1, Node_config
    mv      a3, s5
    addi    a4, sp, L + 24
    FORK_CALL compute_message_id
    bnez    a0, 99f
    li      a0, LIBP2P_EV_MSG_ID_SIZE       # MESSAGE_ID
    call    node_out
    beqz    a0, 99f
    li      t0, LIBP2P_EVENT_MESSAGE_ID
    sd      t0, 8(a0)
    ld      t0, LIBP2P_ACT_HANDLE(s3)
    sd      t0, 16(a0)
    li      t0, 20
    sd      t0, 24(a0)
    addi    a0, a0, 32
    sd      zero, 0(a0)
    sd      zero, 8(a0)
    sd      zero, 16(a0)
    sd      zero, 24(a0)
    addi    a1, sp, L + 24
    li      a2, 20
    call    lantern_copy
    PART    t0, t1, s1, Node_messages       # the entry
    ld      t2, Node_blobs(s1)
    ld      t3, Node_messages(s1)
    sub     t2, t2, t3
    li      t3, NodeMessage__mem
    divu    t2, t2, t3
    bgeu    t1, t2, 99f
    mul     s7, t1, t3
    add     s7, s7, t0
    addi    t1, t1, 1
    sd      t1, (Node_messages + 8)(s1)
    mv      a0, s7
    li      a1, NodeMessage__mem
    call    lantern_zero
    ld      t0, LIBP2P_ACT_HANDLE(s3)
    sd      t0, NodeMessage_handle(s7)
    ld      t0, LIBP2P_ACT_MSG_PEER(s3)
    sd      t0, NodeMessage_peer(s7)
    ld      t0, (L + GossipTopic_name)(sp)
    sd      t0, NodeMessage_topic(s7)
    ld      t0, (L + GossipTopic_subnet_id)(sp)
    sd      t0, NodeMessage_subnet(s7)
    li      t0, NODE_MESSAGE_OTHER_DIGEST   # a topic of another ForkDigest: IGNORE, unread
    sd      t0, NodeMessage_state(s7)
    ld      t0, (L + GossipTopic_fork_digest)(sp)
    ld      t1, Node_fork_digest(s1)
    bne     t0, t1, 99f
    li      t0, NODE_MESSAGE_CORRUPT        # the bytes, uncompressed
    sd      t0, NodeMessage_state(s7)
    mv      a0, s10
    addi    a1, sp, L + 48
    CALL_GLOBAL snappy_get_uncompressed_length
    bnez    a0, 99f
    ld      t0, (L + 48)(sp)
    LDQ     t1, s1, Node_config + CONFIG_MAX_PAYLOAD_SIZE
    bgtu    t0, t1, 99f
    li      t1, NODE_MESSAGE_NO_ROOM
    sd      t1, NodeMessage_state(s7)
    addi    t0, t0, 24 + 7
    andi    t0, t0, -8
    ld      t1, 0(s5)
    bltu    t1, t0, 99f
    addi    a0, t0, 48                      # room for its BYTES_PUT
    call    node_room
    beqz    a0, 99f
    ld      t1, 0(s5)
    ld      t0, (L + 48)(sp)
    addi    t0, t0, 24 + 7
    andi    t0, t0, -8
    sub     t1, t1, t0
    sd      t1, 0(s5)
    add     s9, s5, t1
    sd      t0, 0(s9)
    li      t0, 24
    sd      t0, 8(s9)
    sd      zero, 16(s9)
    mv      a0, s10
    mv      a1, s9
    CALL_GLOBAL snappy_uncompress
    beqz    a0, 2f
    li      t0, NODE_MESSAGE_CORRUPT
    sd      t0, NodeMessage_state(s7)
    j       99f
2:  ld      t0, NodeMessage_topic(s7)       # the slot and parent root of a block or a block header
    ld      t1, 16(s9)
    addi    t2, s9, 24
    li      t3, GOSSIP_BEACON_BLOCK
    bne     t0, t3, 3f
    li      t3, 100 + 84
    bltu    t1, t3, 5f
    addi    t2, t2, 100
    j       4f
3:  li      t3, GOSSIP_BLOB_SIDECAR
    bne     t0, t3, 31f
    li      t3, NODE_BLOB_HEADER + 48
    bltu    t1, t3, 5f
    li      t3, NODE_BLOB_HEADER
    add     t2, t2, t3
    j       4f
31: li      t3, GOSSIP_DATA_COLUMN_SIDECAR
    bne     t0, t3, 32f
    li      t3, 20 + 48
    bltu    t1, t3, 5f
    addi    t2, t2, 20
4:  LDU64   t3, t2, 0, t4                   # 4-aligned
    sd      t3, NodeMessage_slot(s7)
    addi    a0, s7, NodeMessage_parent_root
    addi    a1, t2, 16
    li      a2, 32
    call    lantern_copy
    j       5f
32: li      t3, GOSSIP_BEACON_AGGREGATE_AND_PROOF   # an aggregate: the slot of its data
    bne     t0, t3, 5f
    mv      a0, s9
    call    node_aggregate
    li      t3, -1
    bnez    a0, 33f
    li      t0, 12
    bltu    a2, t0, 33f
    LD32B   t3, a1, 4, t6
    LD32B   t4, a1, 8, t6
    slli    t4, t4, 32
    or      t3, t3, t4
33: sd      t3, NodeMessage_slot(s7)
5:  mv      a0, s9                          # the bytes, kept by the shell
    call    node_put
    sd      a0, NodeMessage_data_id(s7)
    ld      t0, 16(s9)
    sd      t0, NodeMessage_length(s7)
    li      t0, NODE_MESSAGE_ID
    sd      t0, NodeMessage_state(s7)
99: sd      s8, 0(s5)
    LEAVE 64
END_FUNCTION node_message

/*
 * The MESSAGE_STATUS a0 of libp2p. NEW: a GOSSIP work with the head state, for a block or block
 * header a copy of its parent's post-state, and the state of the justified root; or a VALIDATION
 * when the node holds no bytes for it. Else its bytes and its entry go. s3 the notice, s4 the
 * entry, s7 the head state, s8 the proposer state, s9 the justified state.
 */
LOCAL_FUNCTION node_message_status
    ENTER 0
    mv      s3, a0
    ld      a0, LIBP2P_ACT_HANDLE(s3)
    call    node_find_message
    li      t0, -1
    beq     a0, t0, 99f
    mv      s4, a1
    ld      t0, LIBP2P_ACT_STATUS(s3)
    li      t1, LIBP2P_MSG_NEW
    bne     t0, t1, 80f
    ld      t0, NodeMessage_state(s4)
    li      t1, NODE_MESSAGE_ID
    beq     t0, t1, 1f
    li      a1, LIBP2P_IGNORE
    li      t1, NODE_MESSAGE_CORRUPT
    bne     t0, t1, 70f
    li      a1, LIBP2P_REJECT
70: ld      a0, NodeMessage_handle(s4)
    call    node_validation
    j       80f
1:  li      a0, NODE_ACT_WORK_SIZE + 32     # room for the work and a state copy
    call    node_room
    li      a1, LIBP2P_IGNORE
    beqz    a0, 70b
    li      s7, 0                           # the head state
    addi    a0, s1, Node_head_root
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 2f
    ld      s7, NodeBlock_state_id(a1)
2:  li      s8, 0                           # the proposer state: a copy of the parent's, when it comes before
    ld      t0, NodeMessage_topic(s4)
    li      t1, GOSSIP_BEACON_BLOCK
    beq     t0, t1, 21f
    li      t1, GOSSIP_BLOB_SIDECAR
    beq     t0, t1, 21f
    li      t1, GOSSIP_DATA_COLUMN_SIDECAR
    bne     t0, t1, 3f
21: addi    a0, s4, NodeMessage_parent_root
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 3f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 3f
    ld      t0, NodeBlock_slot(a1)
    ld      t1, NodeMessage_slot(s4)
    bleu    t1, t0, 3f
    ld      s9, NodeBlock_state_id(a1)
    bnez    s9, 22f
    mv      s10, a1                         # a parent with no post-state above F's slot: it again
    call    node_f_slot
    ld      t0, NodeBlock_slot(s10)
    bleu    t0, a0, 3f
    mv      a0, s10
    call    node_rebuild
    mv      s9, a0
    beqz    s9, 3f
    mv      a1, s10
22: ld      t0, NodeBlock_slot(a1)
    mv      a0, t0                          # of the same fork
    addi    a1, s1, Node_config
    call    node_fork
    mv      s10, a0
    ld      a0, NodeMessage_slot(s4)
    addi    a1, s1, Node_config
    call    node_fork
    bne     a0, s10, 3f
    call    node_new_id
    mv      s8, a0
    li      a0, NODE_ACT_STATE_COPY
    mv      a1, s9
    mv      a2, s8
    call    node_ids
3:  li      s9, 0                           # the state of the justified root
    ADDQ    a0, s2, Store_justified_checkpoint + 8
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 4f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 4f
    ld      s9, NodeBlock_state_id(a1)
4:  li      a0, NODE_WORK_GOSSIP
    mv      a1, s7
    mv      a2, s8
    ld      a3, NodeMessage_data_id(s4)
    ld      a4, NodeMessage_handle(s4)
    ld      a5, NodeMessage_subnet(s4)
    slli    a5, a5, 8
    ld      t0, NodeMessage_topic(s4)
    or      a5, a5, t0
    call    node_work
    sd      s9, NodeAction_state_c(a0)
    li      t0, NODE_MESSAGE_VALIDATING
    sd      t0, NodeMessage_state(s4)
    LEAVE 0
80: ld      a1, NodeMessage_data_id(s4)     # no work: its bytes and its entry go
    beqz    a1, 81f
    li      a0, 32
    call    node_room
    beqz    a0, 81f
    li      a0, NODE_ACT_BYTES_FREE
    ld      a1, NodeMessage_data_id(s4)
    li      a2, 0
    call    node_ids
81: mv      a0, s4
    call    node_drop_message
99: LEAVE 0
END_FUNCTION node_message_status

/* ------------------------------------------------------------ sync */

/*
 * The Status of a2 bytes at a1 (84, or 92 for v2) of the peer of handle a0, kept in its entry;
 * then the Status rules (phase0 p2p-interface.md): a fork_digest the node does not have, or a
 * finalized checkpoint of the node's finalized epoch or before that is not of the node's chain,
 * gives a DISCONNECT. s3 the bytes, then the peer's finalized epoch, s4 their size, then a slot, s7
 * the entry, s8 the Db. Locals: L the node's Status (92).
 */
LOCAL_FUNCTION node_peer_status
    ENTER 96
    mv      s3, a1
    mv      s4, a2
    call    node_find_peer
    li      t0, -1
    beq     a0, t0, 9f
    mv      s7, a1
    sd      zero, NodePeer_fork_digest(s7)
    addi    a0, s7, NodePeer_fork_digest
    mv      a1, s3
    li      a2, 4
    call    lantern_copy
    addi    a0, s7, NodePeer_finalized_root # finalized root and epoch, head root and slot
    addi    a1, s3, 4
    li      a2, 32 + 8 + 32 + 8
    call    lantern_copy
    sd      zero, NodePeer_earliest_slot(s7)
    li      t0, 92
    bne     s4, t0, 1f
    addi    a0, s7, NodePeer_earliest_slot
    addi    a1, s3, 84
    li      a2, 8
    call    lantern_copy
1:  ld      t0, NodePeer_flags(s7)
    ori     t0, t0, NODE_PEER_STATUS
    sd      t0, NodePeer_flags(s7)
    addi    a0, sp, L                       # its fork_digest: the node's of the store's epoch, or the one ahead or before around a fork
    call    node_status_bytes
    ld      t0, NodePeer_fork_digest(s7)
    lwu     t1, L(sp)
    beq     t0, t1, 2f
    ld      t1, Node_next_digest(s1)
    beq     t0, t1, 2f
    ld      t1, Node_old_digest(s1)
    bne     t0, t1, 8f
2:  ld      s3, NodePeer_finalized_epoch(s7)    # its finalized checkpoint: of GENESIS_EPOCH, or after the store's, as it is
    beqz    s3, 9f
    ld      t0, Store_finalized_checkpoint(s2)
    bgtu    s3, t0, 9f
    bltu    s3, t0, 3f
    addi    t2, s7, NodePeer_finalized_root     # the store's finalized epoch: its root
    addi    t3, s2, Store_finalized_checkpoint + 8
    NE32    t2, t3, 8f
    j       9f
3:  ld      s8, Node_db(s1)                 # before: the Db's last block at or before the epoch's first slot
    add     s8, s1, s8
    li      t0, SLOTS_PER_EPOCH
    mul     s4, s3, t0
    ld      t0, Db_end_slot(s8)
    beqz    t0, 9f
    addi    t0, t0, -1
    bleu    s4, t0, 4f
    mv      s4, t0
4:  ld      t1, Db_first_slot(s8)
    bltu    s4, t1, 9f
    sub     t2, s4, t1
    li      t3, DbSlot__mem
    mul     t2, t2, t3
    ld      t3, Db_slots(s8)
    add     t2, t2, t3
    add     t2, s8, t2
    ld      t3, DbSlot_block(t2)
    bnez    t3, 5f
    beqz    s4, 9f
    addi    s4, s4, -1
    j       4b
5:  addi    t3, s7, NodePeer_finalized_root
    NE32    t3, t2, 8f                      # DbSlot_root
    j       9f
8:  li      a0, LIBP2P_EVENT_DISCONNECT     # a DISCONNECT; it syncs nothing until it goes
    ld      a1, NodePeer_handle(s7)
    call    node_out_handle
    ld      t0, NodePeer_flags(s7)
    andi    t0, t0, ~NODE_PEER_STATUS
    sd      t0, NodePeer_flags(s7)
9:  LEAVE 96
END_FUNCTION node_peer_status

/* a0 = the index of the node's stream in NODE_STREAM_OPENING of tag a0, or 2^64 - 1; a1 = its entry. Uses t0-t4, a7. */
LOCAL_FUNCTION node_find_opening
    UNWIND_END_PROLOGUE
    PART    a1, t1, s1, Node_streams
    ld      t3, Node_stream_bytes(s1)
    li      t0, 0
1:  bgeu    t0, t1, 2f
    ld      t2, NodeStream_state(a1)
    li      t4, NODE_STREAM_OPENING
    bne     t2, t4, 11f
    ld      t2, NodeStream_handle(a1)
    beq     t2, a0, 3f
11: add     a1, a1, t3
    addi    t0, t0, 1
    j       1b
2:  li      a0, -1
    ret
3:  mv      a0, t0
    ret
END_FUNCTION node_find_opening

/* The stream entry a0 goes; the node's BeaconBlocksByRange request ends with it. */
LOCAL_FUNCTION node_end_stream
    FRAME 0
    ld      t1, Node_backfill_handle(s1)    # the backfill's stream: the backfill has none
    beqz    t1, 2f
    ld      t0, NodeStream_handle(a0)
    bne     t0, t1, 2f
    sd      zero, Node_backfill_handle(s1)
    j       1f
2:  ld      t0, NodeStream_state(a0)
    li      t1, NODE_STREAM_OPENING
    bltu    t0, t1, 1f
    ld      t0, NodeStream_method(a0)
    li      t1, REQRESP_BEACON_BLOCKS_BY_RANGE
    bne     t0, t1, 1f
    ld      t0, Node_flags(s1)
    andi    t0, t0, ~NODE_FLAG_SYNCING
    sd      t0, Node_flags(s1)
1:  call    node_drop_stream
    UNFRAME 0
END_FUNCTION node_end_stream

/*
 * A request of the node: method a0, version a1, to the peer of handle a2, its SSZ bytes at a3 of
 * a4 bytes: a NodeStream in NODE_STREAM_OPENING whose list holds the request chunk, and an
 * OPEN_STREAM of its protocol ID; a0 = the entry, or 0 when the streams part, scratch or p2p_out
 * has no room. s3 the entry, s4 the request's ByteList, then the OPEN_STREAM, s7 the scratch
 * size, restored on return, s8 the peer, s9 the bytes, s10 their size. Locals: L a ChunkHeader,
 * L+48 a ReqRespProtocol, L+64 a ByteList of the protocol ID (152), L+216 the tag.
 */
LOCAL_FUNCTION node_open
    ENTER 224
    sd      a0, (L + 48)(sp)
    sd      a1, (L + 56)(sp)
    mv      s8, a2
    mv      s9, a3
    mv      s10, a4
    ld      s7, 0(s5)
    ld      t0, Node_messages(s1)           # room for the entry
    ld      t1, Node_streams(s1)
    sub     t0, t0, t1
    ld      t2, Node_stream_bytes(s1)
    divu    t0, t0, t2
    ld      t3, (Node_streams + 8)(s1)
    bgeu    t3, t0, 8f
    mul     t3, t3, t2
    add     t3, t3, t1
    add     s3, s1, t3
    addi    t0, s10, 24 + 7                 # the request's ByteList at the end of scratch
    andi    t0, t0, -8
    bltu    s7, t0, 8f
    sub     t1, s7, t0
    sd      t1, 0(s5)
    add     s4, s5, t1
    sd      t0, 0(s4)
    li      t0, 24
    sd      t0, 8(s4)
    sd      s10, 16(s4)
    addi    a0, s4, 24
    mv      a1, s9
    mv      a2, s10
    call    lantern_copy
    mv      a0, s3                          # the entry, its list empty
    li      a1, NodeStream__fixed
    call    lantern_zero
    ld      t0, Node_stream_bytes(s1)
    addi    t0, t0, -NodeStream_list
    sd      t0, NodeStream_list(s3)
    li      t0, 24
    sd      t0, (NodeStream_list + 8)(s3)
    beqz    s10, 1f                         # no request bytes: an empty list
    li      t0, CHUNK_REQUEST               # the request chunk in the list
    sd      t0, (L + ChunkHeader_kind)(sp)
    sd      zero, (L + ChunkHeader_context_length)(sp)
    sd      zero, (L + ChunkHeader_result)(sp)
    addi    a0, sp, L
    mv      a1, s4
    mv      a2, s5
    addi    a3, s3, NodeStream_list
    call    lantern_reqresp_write_chunk
    bnez    a0, 8f
1:  li      t0, 24 + 128                    # the protocol ID
    sd      t0, (L + 64)(sp)
    li      t0, 24
    sd      t0, (L + 72)(sp)
    sd      zero, (L + 80)(sp)
    addi    a0, sp, L + 48
    addi    a1, sp, L + 64
    call    lantern_reqresp_protocol_id
    bnez    a0, 8f
    call    node_new_id                     # the tag
    li      t0, 1
    slli    t0, t0, 63
    or      a0, a0, t0
    sd      a0, (L + 216)(sp)
    li      a0, 40 + LIBP2P_PROTO_SIZE      # OPEN_STREAM
    call    node_out
    beqz    a0, 8f
    mv      s4, a0
    li      t0, LIBP2P_EVENT_OPEN_STREAM
    sd      t0, 8(s4)
    sd      s8, 16(s4)
    ld      t0, (L + 216)(sp)
    sd      t0, 24(s4)
    li      t0, 1
    sd      t0, 32(s4)
    ld      t0, (L + 80)(sp)
    sd      t0, 40(s4)
    addi    a0, s4, 48
    li      a1, 128
    call    lantern_zero
    addi    a0, s4, 48
    addi    a1, sp, L + 88
    ld      a2, (L + 80)(sp)
    call    lantern_copy
    ld      t0, (L + 216)(sp)               # the entry joins the part
    sd      t0, NodeStream_handle(s3)
    sd      s8, NodeStream_peer(s3)
    ld      t0, (L + 48)(sp)
    sd      t0, NodeStream_method(s3)
    ld      t0, (L + 56)(sp)
    sd      t0, NodeStream_version(s3)
    li      t0, NODE_STREAM_OPENING
    sd      t0, NodeStream_state(s3)
    ld      t0, (Node_streams + 8)(s1)
    addi    t0, t0, 1
    sd      t0, (Node_streams + 8)(s1)
    sd      s7, 0(s5)
    mv      a0, s3
    LEAVE 224
8:  sd      s7, 0(s5)
    li      a0, 0
    LEAVE 224
END_FUNCTION node_open

/*
 * a0 = 1 when the response bytes of the node's request stream a0 wait for room, else 0. Each
 * complete chunk is read: a Status goes to the peer's entry; a block becomes a NodeBlock in
 * NODE_BLOCK_HASHING, a BYTES_PUT of its bytes and a SYNC_BLOCK work of its root. After a Status,
 * after the last chunk and STREAM_EOF, after an error result, or on a bad chunk (with a
 * STREAM_RESET), the stream ends. s3 the entry, s4 the method, s7 the scratch size, restored on
 * return, s8 the payload's ByteList, s9 the SSZ size, s10 a block entry. Locals: L a ChunkHeader,
 * L+48 a length, then a block index, L+56 eof, L+64 the payload bytes read.
 */
LOCAL_FUNCTION node_response
    ENTER 80
    mv      s3, a0
    ld      s4, NodeStream_method(s3)
    ld      s7, 0(s5)
1:  ld      t0, (NodeStream_list + 16)(s3)
    bnez    t0, 2f
    ld      t0, NodeStream_next(s3)         # no bytes: the end after STREAM_EOF
    bnez    t0, 80f
    j       90f
2:  li      t0, CHUNK_RESPONSE              # blocks by range v2, blob and column sidecars: a ForkDigest context
    sd      t0, (L + ChunkHeader_kind)(sp)
    li      t0, 4
    li      t1, REQRESP_BLOB_SIDECARS_BY_RANGE
    beq     s4, t1, 3f
    li      t1, REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE
    beq     s4, t1, 3f
    li      t1, REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT
    beq     s4, t1, 3f
    li      t0, 0
    li      t1, REQRESP_BEACON_BLOCKS_BY_RANGE
    bne     s4, t1, 3f
    ld      t1, NodeStream_version(s3)
    li      t2, 2
    bltu    t1, t2, 3f
    li      t0, 4
3:  sd      t0, (L + ChunkHeader_context_length)(sp)
    addi    a0, s3, NodeStream_list
    addi    a1, sp, L
    call    lantern_reqresp_read_header
    li      t0, LANTERN_REQRESP_MORE
    beq     a0, t0, 5f
    bnez    a0, 85f
    ld      t0, (L + ChunkHeader_result)(sp)
    bnez    t0, 80f
    ld      s9, (L + ChunkHeader_length)(sp)
    li      t1, REQRESP_STATUS
    bne     s4, t1, 4f
    ld      t1, NodeStream_version(s3)
    li      t0, 84
    li      t2, 2
    bltu    t1, t2, 31f
    li      t0, 92
31: bne     s9, t0, 85f
    j       41f
4:  li      t0, REQRESP_METADATA            # MetaData v3
    bne     s4, t0, 43f
    li      t0, NODE_METADATA_V3
    bne     s9, t0, 85f
    j       41f
43: li      t0, REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE
    beq     s4, t0, 431f
    li      t0, REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT
    bne     s4, t0, 44f
431: li     t0, NODE_COLUMN_FIXED           # a column sidecar: room for its BYTES_PUT, its work, its entry
    bltu    s9, t0, 85f
    li      t0, NODE_COLUMN_BYTES
    bgtu    s9, t0, 85f
    addi    a0, s9, 48 + NODE_ACT_WORK_SIZE + 7
    j       45f
44: li      t0, REQRESP_BLOB_SIDECARS_BY_RANGE
    bne     s4, t0, 42f
    li      t0, NODE_BLOB_BYTES             # a blob sidecar: room for its BYTES_PUT, its work, its entry
    bne     s9, t0, 85f
    li      a0, NODE_BLOB_BYTES + 48 + NODE_ACT_WORK_SIZE + 7
45: call    node_room
    beqz    a0, 95f
    LDQ     t0, s1, Node_api                # the blobs' capacity: up to the api part
    ld      t1, Node_blobs(s1)
    sub     t0, t0, t1
    li      t1, NodeBlob__mem
    divu    t0, t0, t1
    ld      t1, (Node_blobs + 8)(s1)
    bgeu    t1, t0, 95f
    j       41f
42: li      t0, 100 + 84                    # a block: room for its BYTES_PUT, its work, its entry
    bltu    s9, t0, 85f
    LDQ     t0, s1, Node_config + CONFIG_MAX_PAYLOAD_SIZE
    bgtu    s9, t0, 85f
    addi    a0, s9, 48 + NODE_ACT_WORK_SIZE + 7
    call    node_room
    beqz    a0, 95f
    ld      t0, Node_checkpoints(s1)
    ld      t1, Node_blocks(s1)
    sub     t0, t0, t1
    li      t1, NodeBlock__mem
    divu    t0, t0, t1
    ld      t1, (Node_blocks + 8)(s1)
    bgeu    t1, t0, 95f
41: addi    t0, s9, 24 + 7                  # the payload's ByteList at the end of scratch
    andi    t0, t0, -8
    bltu    s7, t0, 85f
    sub     t1, s7, t0
    sd      t1, 0(s5)
    add     s8, s5, t1
    sd      t0, 0(s8)
    li      t0, 24
    sd      t0, 8(s8)
    sd      zero, 16(s8)
    sd      s9, (L + 48)(sp)                # length and eof, by address
    ld      t0, NodeStream_next(s3)
    sd      t0, (L + 56)(sp)
    addi    a0, s3, NodeStream_list
    addi    a1, sp, L + ChunkHeader_header_bytes
    addi    a2, sp, L + 48
    addi    a3, sp, L + 56
    mv      a4, s5
    mv      a5, s8
    addi    a6, sp, L + 64
    call    lantern_reqresp_read_payload
    li      t0, LANTERN_REQRESP_MORE
    beq     a0, t0, 5f
    bnez    a0, 85f
    li      t0, REQRESP_STATUS
    bne     s4, t0, 6f
    ld      a0, NodeStream_peer(s3)         # Status: the peer's
    addi    a1, s8, 24
    mv      a2, s9
    call    node_peer_status
    j       7f
6:  li      t0, REQRESP_METADATA
    bne     s4, t0, 62f
    ld      a0, NodeStream_peer(s3)         # MetaData: the peer's custody
    call    node_find_peer
    li      t0, -1
    beq     a0, t0, 7f
    mv      a0, a1
    addi    t0, s8, 24 + 17 + 7             # custody_group_count, at an odd offset: byte by byte
    li      a1, 0
    li      t1, 8
631: slli   a1, a1, 8
    lbu     t2, 0(t0)
    or      a1, a1, t2
    addi    t0, t0, -1
    addi    t1, t1, -1
    bnez    t1, 631b
    call    node_peer_custody
    j       7f
62: li      t0, REQRESP_BLOB_SIDECARS_BY_RANGE
    beq     s4, t0, 61f
    li      t0, REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE
    beq     s4, t0, 63f
    li      t0, REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT
    beq     s4, t0, 63f
    call    node_new_block                  # a block: its entry, its bytes, the work of its root
    sd      a0, (L + 48)(sp)
    mv      s10, t0
    addi    t0, s8, 24                      # the slot at 4 mod 8
    LDU64   t1, t0, 100, t2
    sd      t1, NodeBlock_slot(s10)
    addi    a0, s10, NodeBlock_parent_root
    addi    a1, s8, 24 + 116
    li      a2, 32
    call    lantern_copy
    li      t0, NODE_BLOCK_HASHING          # of the backfill's stream: NODE_BLOCK_BF_CHECKING
    ld      t1, NodeStream_handle(s3)
    ld      t2, Node_backfill_handle(s1)
    bne     t1, t2, 64f
    li      t0, NODE_BLOCK_BF_CHECKING
64: sd      t0, NodeBlock_status(s10)
    li      t0, 1
    sd      t0, NodeBlock_data_available(s10)
    mv      a0, s8
    call    node_put
    sd      a0, NodeBlock_data_id(s10)
    sd      a0, (L + 56)(sp)
    ld      t0, 16(s8)
    sd      t0, NodeBlock_length(s10)
    li      a0, NODE_WORK_SYNC_BLOCK
    li      a1, 0
    ld      t0, NodeBlock_status(s10)
    li      t1, NODE_BLOCK_BF_CHECKING
    bne     t0, t1, 641f
    ld      t0, Node_backfill_got(s1)
    addi    t0, t0, 1
    sd      t0, Node_backfill_got(s1)
    addi    a0, s2, Store_finalized_checkpoint + 8  # BACKFILL: with F's post-state
    call    node_find_block
    li      t0, -1
    li      a2, 0
    beq     a0, t0, 642f
    ld      a2, NodeBlock_state_id(a1)
642: mv     a1, a2
    li      a0, NODE_WORK_BACKFILL
641: li     a2, 0
    ld      a3, (L + 56)(sp)
    ld      a4, (L + 48)(sp)
    li      a5, 0
    call    node_work
    j       7f
61: call    node_new_blob                   # a blob sidecar: its entry, its bytes, the work of its checks
    sd      a0, (L + 48)(sp)
    mv      s10, t0
    ld      t0, 24(s8)                      # its index, and the slot of its block header
    sd      t0, NodeBlob_index(s10)
    LDQ     t0, s8, 24 + NODE_BLOB_HEADER
    sd      t0, NodeBlob_slot(s10)
    li      t0, NODE_BLOB_VERIFYING
    sd      t0, NodeBlob_status(s10)
    mv      a0, s8
    call    node_put
    sd      a0, NodeBlob_data_id(s10)
    ld      t0, 16(s8)
    sd      t0, NodeBlob_length(s10)
    mv      a3, a0
    li      a0, NODE_WORK_BLOB
    li      a1, 0
    li      a2, 0
    ld      a4, (L + 48)(sp)
    li      a5, 0
    call    node_work
    j       7f
63: call    node_new_blob                   # a column sidecar: its entry, its bytes, the work of its checks
    sd      a0, (L + 48)(sp)
    mv      s10, t0
    ld      t0, 24(s8)                      # its index, and the slot of its block header, 4-aligned
    sd      t0, NodeBlob_index(s10)
    LDU64   t0, s8, 24 + NODE_COLUMN_HEADER, t1
    sd      t0, NodeBlob_slot(s10)
    li      t0, NODE_BLOB_VERIFYING
    sd      t0, NodeBlob_status(s10)
    mv      a0, s8
    call    node_put
    sd      a0, NodeBlob_data_id(s10)
    ld      t0, 16(s8)
    sd      t0, NodeBlob_length(s10)
    mv      a3, a0
    li      a0, NODE_WORK_BLOB
    li      a1, 0
    li      a2, 0
    ld      a4, (L + 48)(sp)
    li      a5, 1
    call    node_work
7:  sd      s7, 0(s5)                       # the chunk leaves the list
    ld      t0, (L + ChunkHeader_header_bytes)(sp)
    ld      t1, (L + 64)(sp)
    add     t0, t0, t1
    ld      t1, (NodeStream_list + 16)(s3)
    sub     a2, t1, t0
    sd      a2, (NodeStream_list + 16)(s3)
    addi    a0, s3, NodeStream_request
    add     a1, a0, t0
    call    lantern_copy
    li      t0, REQRESP_STATUS              # Status and MetaData: one chunk
    beq     s4, t0, 80f
    li      t0, REQRESP_METADATA
    beq     s4, t0, 80f
    j       1b
5:  sd      s7, 0(s5)                       # part of a chunk: more bytes, or the end after STREAM_EOF
    ld      t0, NodeStream_next(s3)
    bnez    t0, 80f
90: li      a0, 0
    LEAVE 80
95: li      a0, 1
    LEAVE 80
85: sd      s7, 0(s5)                       # a bad chunk: a reset
    li      a0, LIBP2P_EVENT_STREAM_RESET
    ld      a1, NodeStream_handle(s3)
    call    node_out_handle
80: mv      a0, s3
    call    node_end_stream
    li      a0, 0
    LEAVE 80
END_FUNCTION node_response

/*
 * The sidecar requests of a range (node.md): a BlobSidecarsByRange v1 to the peer a0 of the slots of
 * a1, count a2, in the blob window whose fork is deneb or electra, then from fulu (a3 the fork of the
 * store's slot) the DataColumnSidecarsByRange v1 of the slots in the column window to the peers with
 * NODE_PEER_METADATA. a0 = 1 when a request has no room or the node cannot open it, else 0. Locals
 * as node_sync's: L the range, L+24 a request's range, L+40 the fork, L+48 the columns asked, L+64
 * count or send, L+72 the column requests, L+80 the peer. s3 a peer, s4 the peers left, s10 the
 * scratch size.
 */
LOCAL_FUNCTION node_sidecar_ask
    ENTER 96
    sd      a0, (L + 80)(sp)
    sd      a1, L(sp)
    sd      a2, (L + 8)(sp)
    sd      a3, (L + 40)(sp)
    mv      s3, a0
    LDQ     a0, s1, Node_config + CONFIG_MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS   # the blob window's first slot
    li      a1, FORK_DENEB
    call    node_window
    li      t0, SLOTS_PER_EPOCH
    mulhu   t1, a0, t0
    bnez    t1, 66f
    mul     a0, a0, t0
    ld      t2, L(sp)                       # the range from there, before fulu's first slot
    ld      t3, (L + 8)(sp)
    add     t3, t2, t3
    bgeu    t3, t2, 63f
    li      t3, -1
63: bgeu    t2, a0, 64f
    mv      t2, a0
64: LDQ     t1, s1, Node_config + 16 * FORK_FULU
    mulhu   t4, t1, t0
    bnez    t4, 65f
    mul     t1, t1, t0
    bleu    t3, t1, 65f
    mv      t3, t1
65: bgeu    t2, t3, 66f
    sub     t3, t3, t2
    sd      t2, (L + 24)(sp)
    sd      t3, (L + 32)(sp)
    ld      t0, (Node_streams + 8)(s1)      # room for it and the blocks' request
    ld      t1, Node_messages(s1)
    ld      t2, Node_streams(s1)
    sub     t1, t1, t2
    ld      t2, Node_stream_bytes(s1)
    divu    t1, t1, t2
    addi    t0, t0, 2
    bgtu    t0, t1, 9f
    li      a0, REQRESP_BLOB_SIDECARS_BY_RANGE
    li      a1, 1
    ld      a2, NodePeer_handle(s3)
    addi    a3, sp, L + 24
    li      a4, 16
    call    node_open
    beqz    a0, 9f
66: ld      t0, (L + 40)(sp)                # fulu: the column requests
    li      t1, FORK_FULU
    bltu    t0, t1, 71f
    LDQ     a0, s1, Node_config + CONFIG_MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS   # the column window's first slot
    li      a1, FORK_FULU
    call    node_window
    li      t0, SLOTS_PER_EPOCH
    mulhu   t1, a0, t0
    bnez    t1, 71f
    mul     a0, a0, t0
    ld      t2, L(sp)                       # the range from there
    ld      t3, (L + 8)(sp)
    add     t3, t2, t3
    bgeu    t3, t2, 67f
    li      t3, -1
67: bgeu    t2, a0, 68f
    mv      t2, a0
68: bgeu    t2, t3, 71f
    sub     t3, t3, t2
    sd      t2, (L + 24)(sp)
    sd      t3, (L + 32)(sp)
    ld      s10, 0(s5)                      # the request's bytes at the end of scratch
    li      t0, 24 + 8 * 128                # 8-aligned
    bltu    s10, t0, 9f
    sub     t0, s10, t0
    sd      t0, 0(s5)
    add     s9, s5, t0
    sd      zero, (L + 64)(sp)              # first count the requests, then send them
72: sd      zero, (L + 48)(sp)
    sd      zero, (L + 56)(sp)
    sd      zero, (L + 72)(sp)
    PART    s3, s4, s1, Node_peers
73: beqz    s4, 76f
    ld      t0, NodePeer_flags(s3)
    andi    t0, t0, NODE_PEER_METADATA
    beqz    t0, 75f
    ld      t0, Node_columns(s1)            # the sampled columns it custodies, not asked yet
    ld      t1, NodePeer_custody(s3)
    and     t0, t0, t1
    ld      t1, (L + 48)(sp)
    not     t1, t1
    and     t0, t0, t1
    ld      t2, (Node_columns + 8)(s1)
    ld      t1, (NodePeer_custody + 8)(s3)
    and     t2, t2, t1
    ld      t1, (L + 56)(sp)
    not     t1, t1
    and     t2, t2, t1
    or      t1, t0, t2
    beqz    t1, 75f
    ld      t1, (L + 48)(sp)
    or      t1, t1, t0
    sd      t1, (L + 48)(sp)
    ld      t1, (L + 56)(sp)
    or      t1, t1, t2
    sd      t1, (L + 56)(sp)
    ld      t1, (L + 72)(sp)
    addi    t1, t1, 1
    sd      t1, (L + 72)(sp)
    ld      t1, (L + 64)(sp)
    beqz    t1, 75f
    ld      t1, (L + 24)(sp)                # start_slot, count, the offset 20, the columns in ascending order
    sd      t1, 0(s9)
    ld      t1, (L + 32)(sp)
    sd      t1, 8(s9)
    li      t1, 20
    sw      t1, 16(s9)
    addi    t3, s9, 20
    li      t4, 0
74: li      t5, 128
    bgeu    t4, t5, 741f
    mv      t5, t0
    li      t6, 64
    bltu    t4, t6, 743f
    mv      t5, t2
743: srl    t5, t5, t4
    andi    t5, t5, 1
    beqz    t5, 742f
    sw      t4, 0(t3)                       # a column, 4-aligned: two words
    sw      zero, 4(t3)
    addi    t3, t3, 8
742: addi   t4, t4, 1
    j       74b
741: li     a0, REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE
    li      a1, 1
    ld      a2, NodePeer_handle(s3)
    mv      a3, s9
    sub     a4, t3, s9
    call    node_open
    beqz    a0, 78f
75: addi    s3, s3, NodePeer__mem
    addi    s4, s4, -1
    j       73b
76: ld      t0, (L + 64)(sp)
    bnez    t0, 77f
    ld      t0, (L + 72)(sp)                # room for the column requests and the blocks' request
    ld      t1, (Node_streams + 8)(s1)
    add     t0, t0, t1
    addi    t0, t0, 1
    ld      t1, Node_messages(s1)
    ld      t2, Node_streams(s1)
    sub     t1, t1, t2
    ld      t2, Node_stream_bytes(s1)
    divu    t1, t1, t2
    bgtu    t0, t1, 78f
    li      t0, 1
    sd      t0, (L + 64)(sp)
    j       72b
78: sd      s10, 0(s5)
    j       9f
77: sd      s10, 0(s5)
71: li      a0, 0
    LEAVE 96
9:  li      a0, 1
    LEAVE 96
END_FUNCTION node_sidecar_ask

/*
 * a0 = 1 when a response waits for room, else 0. The bytes of each response are read. From
 * fulu, each peer with a Status and no MetaData asked gets a GetMetaData v3. Then, with no
 * BeaconBlocksByRange of the node open, one to a peer of the node's ForkDigest (from fulu, with its
 * MetaData read) whose Status head_slot is at least the next slot: max(the head's slot + 1,
 * sync_slot), at most NODE_SYNC_BATCH slots. Before it, with room for two streams, a
 * BlobSidecarsByRange of the range's slots in the blob window before fulu; from fulu, a
 * DataColumnSidecarsByRange of the range's slots in the column window to each peer whose custody
 * holds sampled columns no earlier peer was asked for, with room for those and the blocks'
 * request. s3 a peer, s4 the streams or peers left, s7 the result, s8 the start slot, s9 a column
 * request at the end of scratch, s10 the scratch size. Locals: L the request (24), L+24 the blob
 * or column range (16), L+40 the fork of the store's slot, L+48 the columns asked (16), L+64 the
 * pass (0 counts, 1 sends), L+72 the column requests, L+80 the peer of the blocks.
 */
LOCAL_FUNCTION node_sync
    ENTER 96
    li      s7, 0
    ld      s4, (Node_streams + 8)(s1)      # the responses, from the last stream: an end moves the last
1:  beqz    s4, 3f
    addi    s4, s4, -1
    ld      t0, Node_stream_bytes(s1)
    mul     t0, t0, s4
    ld      t1, Node_streams(s1)
    add     t0, t0, t1
    add     a0, s1, t0
    ld      t0, NodeStream_state(a0)
    li      t1, NODE_STREAM_RESPONSE
    bne     t0, t1, 1b
    call    node_response
    or      s7, s7, a0
    j       1b
3:  mv      a0, s2                          # the fork of the store's slot
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    sd      a0, (L + 40)(sp)
    li      t0, FORK_FULU
    bltu    a0, t0, 31f
    PART    s3, s4, s1, Node_peers          # fulu: a GetMetaData v3 to each peer with a Status and none asked
30: beqz    s4, 31f
    ld      t0, NodePeer_flags(s3)
    andi    t1, t0, NODE_PEER_STATUS
    beqz    t1, 32f
    andi    t1, t0, NODE_PEER_METADATA | NODE_PEER_METADATA_ASKED
    bnez    t1, 32f
    ld      t0, (Node_streams + 8)(s1)      # room for it and two more
    ld      t1, Node_messages(s1)
    ld      t2, Node_streams(s1)
    sub     t1, t1, t2
    ld      t2, Node_stream_bytes(s1)
    divu    t1, t1, t2
    addi    t0, t0, 3
    bgtu    t0, t1, 31f
    li      a0, REQRESP_METADATA
    li      a1, 3
    ld      a2, NodePeer_handle(s3)
    li      a3, 0
    li      a4, 0
    call    node_open
    beqz    a0, 31f
    ld      t0, NodePeer_flags(s3)
    ori     t0, t0, NODE_PEER_METADATA_ASKED
    sd      t0, NodePeer_flags(s3)
32: addi    s3, s3, NodePeer__mem
    addi    s4, s4, -1
    j       30b
31: ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_SYNCING
    bnez    t0, 9f
    addi    a0, s1, Node_head_root
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 9f
    ld      s8, NodeBlock_slot(a1)
    addi    s8, s8, 1
    ld      t0, Node_sync_slot(s1)
    bleu    t0, s8, 33f
    mv      s8, t0
33: PART    s3, s4, s1, Node_peers          # a peer ahead
4:  beqz    s4, 90f
    ld      t0, NodePeer_flags(s3)
    andi    t1, t0, NODE_PEER_STATUS
    beqz    t1, 5f
    ld      t1, (L + 40)(sp)                # from fulu: its MetaData read
    li      t2, FORK_FULU
    bltu    t1, t2, 41f
    andi    t1, t0, NODE_PEER_METADATA
    beqz    t1, 5f
41: ld      t0, NodePeer_fork_digest(s3)
    ld      t1, Node_fork_digest(s1)
    bne     t0, t1, 5f
    ld      t0, NodePeer_head_slot(s3)
    bgeu    t0, s8, 6f
5:  addi    s3, s3, NodePeer__mem
    addi    s4, s4, -1
    j       4b
6:  sd      s3, (L + 80)(sp)
    sub     t0, t0, s8                      # the request: start_slot, count, step 1
    addi    t0, t0, 1
    li      t1, NODE_SYNC_BATCH
    bleu    t0, t1, 61f
    mv      t0, t1
61: sd      s8, L(sp)
    sd      t0, (L + 8)(sp)
    li      t0, 1
    sd      t0, (L + 16)(sp)
    ld      a0, (L + 80)(sp)                # the sidecar requests of the range
    ld      a1, L(sp)
    ld      a2, (L + 8)(sp)
    ld      a3, (L + 40)(sp)
    call    node_sidecar_ask
    bnez    a0, 9f
71: ld      s3, (L + 80)(sp)
    mv      a0, s2                          # version 2 from altair on
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    li      a1, 1
    li      t0, FORK_ALTAIR
    bltu    a0, t0, 7f
    li      a1, 2
7:  li      a0, REQRESP_BEACON_BLOCKS_BY_RANGE
    ld      a2, NodePeer_handle(s3)
    addi    a3, sp, L
    li      a4, 24
    call    node_open
    beqz    a0, 9f
    ld      t0, Node_flags(s1)
    ori     t0, t0, NODE_FLAG_SYNCING
    sd      t0, Node_flags(s1)
    ld      t0, L(sp)
    ld      t1, (L + 8)(sp)
    add     t0, t0, t1
    sd      t0, Node_sync_slot(s1)
    j       9f
90: mv      a0, s2                          # none: a fresh Status of a peer, when the store's slot is above the start
    call    node_store_slot
    bleu    a0, s8, 9f
    ld      t0, Node_status_ms(s1)          # at most each NODE_STATUS_MS
    beqz    t0, 91f
    li      t1, NODE_STATUS_MS
    add     t0, t0, t1
    ld      t1, Node_time_ms(s1)
    bltu    t1, t0, 9f
91: ld      t0, (Node_streams + 8)(s1)      # room for it
    ld      t1, Node_messages(s1)
    ld      t2, Node_streams(s1)
    sub     t1, t1, t2
    ld      t2, Node_stream_bytes(s1)
    divu    t1, t1, t2
    addi    t0, t0, 1
    bgtu    t0, t1, 9f
    PART    s3, s4, s1, Node_peers          # the first peer with a Status of the node's fork_digest
92: beqz    s4, 9f
    ld      t0, NodePeer_flags(s3)
    andi    t0, t0, NODE_PEER_STATUS
    beqz    t0, 93f
    ld      t0, NodePeer_fork_digest(s3)
    ld      t1, Node_fork_digest(s1)
    beq     t0, t1, 94f
93: addi    s3, s3, NodePeer__mem
    addi    s4, s4, -1
    j       92b
94: ld      s9, (L + 40)(sp)                # the fork of the store's slot: v2 from fulu
    addi    a0, sp, L
    call    node_status_bytes
    li      a1, 1
    li      a4, 84
    li      t0, FORK_FULU
    bltu    s9, t0, 95f
    li      a1, 2
    li      a4, 92
95: li      a0, REQRESP_STATUS
    ld      a2, NodePeer_handle(s3)
    addi    a3, sp, L
    call    node_open
    beqz    a0, 9f
    ld      t0, Node_time_ms(s1)
    sd      t0, Node_status_ms(s1)
9:  call    node_backfill_ask
    mv      a0, s7
    LEAVE 96
END_FUNCTION node_sync

/*
 * The libp2p application notice a0 of the libp2p state a1. s3 the notice, s4 an entry, s7 method,
 * s8 version. Locals: L a Status (96).
 */
LOCAL_FUNCTION node_notice
    ENTER 96
    mv      s3, a0
    ld      t0, LIBP2P_ACT_KIND(s3)
    li      t1, LIBP2P_ACTION_MESSAGE
    bne     t0, t1, 60f
    call    node_message                    # a0, a1 as given
    LEAVE 96
60: li      t1, LIBP2P_ACTION_MESSAGE_STATUS
    bne     t0, t1, 62f
    call    node_message_status
    LEAVE 96
62: li      t1, LIBP2P_ACTION_STREAM_OPENED
    bne     t0, t1, 63f
    ld      a0, LIBP2P_ACT_SO_TAG(s3)       # the node's request stream: the request, then the close of our side
    call    node_find_opening
    li      t0, -1
    beq     a0, t0, 69f
    mv      s4, a1
    ld      t0, LIBP2P_ACT_STREAM(s3)
    sd      t0, NodeStream_handle(s4)
    ld      t1, LIBP2P_ACT_SO_TAG(s3)       # the backfill's stream: its handle
    ld      t2, Node_backfill_handle(s1)
    bne     t1, t2, 621f
    sd      t0, Node_backfill_handle(s1)
621: li     t0, NODE_STREAM_RESPONSE
    sd      t0, NodeStream_state(s4)
    sd      zero, NodeStream_next(s4)
    ld      s8, (NodeStream_list + 16)(s4)
    beqz    s8, 66f                         # no request bytes: only the close
    addi    s7, s8, 32 + 7
    andi    s7, s7, -8
    addi    a0, s7, 24
    call    node_out
    beqz    a0, 68f
    sd      s7, 0(a0)
    li      t0, LIBP2P_EVENT_STREAM_WRITE
    sd      t0, 8(a0)
    ld      t0, NodeStream_handle(s4)
    sd      t0, 16(a0)
    sd      s8, 24(a0)
    add     t1, a0, s7
    li      t2, 24
    sd      t2, 0(t1)
    li      t2, LIBP2P_EVENT_STREAM_CLOSE
    sd      t2, 8(t1)
    sd      t0, 16(t1)
    addi    a0, a0, 32
    addi    a1, s4, NodeStream_request
    mv      a2, s8
    call    lantern_copy
    sd      zero, (NodeStream_list + 16)(s4)
69: LEAVE 96
66: li      a0, 24
    call    node_out
    beqz    a0, 68f
    li      t0, LIBP2P_EVENT_STREAM_CLOSE
    sd      t0, 8(a0)
    ld      t0, NodeStream_handle(s4)
    sd      t0, 16(a0)
    LEAVE 96
68: li      a0, LIBP2P_EVENT_STREAM_RESET   # no room: a reset
    ld      a1, NodeStream_handle(s4)
    call    node_out_handle
    mv      a0, s4
    call    node_end_stream
    LEAVE 96
63: li      t1, LIBP2P_ACTION_STREAM_FAILED
    bne     t0, t1, 61f
    ld      a0, LIBP2P_ACT_STREAM(s3)       # its tag
    call    node_find_opening
    li      t0, -1
    beq     a0, t0, 69b
    mv      a0, a1
    call    node_end_stream
    LEAVE 96
61: li      t1, LIBP2P_ACTION_PEER_CONNECTED
    bne     t0, t1, 64f
    ld      t1, LIBP2P_ACT_PC_TAG(s3)       # a dial of the node ends
    li      t2, NODE_DIAL_TAG
    and     t1, t1, t2
    beqz    t1, 65f
    ld      t1, Node_dialing(s1)
    beqz    t1, 65f
    addi    t1, t1, -1
    sd      t1, Node_dialing(s1)
65: ld      t2, Node_streams(s1)            # a new peer: its entry, or DISCONNECT when the table is full
    ld      t3, Node_peers(s1)
    sub     t2, t2, t3
    li      t3, NodePeer__mem
    divu    t2, t2, t3
    ld      t4, (Node_peers + 8)(s1)
    bltu    t4, t2, 1f
    li      a0, LIBP2P_EVENT_DISCONNECT
    ld      a1, LIBP2P_ACT_PEER(s3)
    call    node_out_handle
    LEAVE 96
1:  mul     s4, t4, t3
    ld      t5, Node_peers(s1)
    add     s4, s4, t5
    add     s4, s4, s1
    addi    t4, t4, 1
    sd      t4, (Node_peers + 8)(s1)
    mv      a0, s4
    li      a1, NodePeer__mem
    call    lantern_zero
    ld      t0, LIBP2P_ACT_PEER(s3)
    sd      t0, NodePeer_handle(s4)
    ld      t0, LIBP2P_ACT_PC_DIRECTION(s3)
    sd      t0, NodePeer_direction(s4)
    addi    a0, s4, NodePeer_address        # its connection's address and transport
    addi    a1, s3, LIBP2P_ACT_PC_ADDR
    li      a2, 32
    call    lantern_copy
    ld      t0, LIBP2P_ACT_PC_TRANSPORT(s3)
    sd      t0, NodePeer_transport(s4)
    ld      a2, LIBP2P_ACT_PC_ID_LEN(s3)
    li      t0, 48
    bleu    a2, t0, 2f
    li      a2, 48
2:  sd      a2, NodePeer_id_len(s4)
    addi    a0, s4, NodePeer_id
    addi    a1, s3, LIBP2P_ACT_PC_ID
    call    lantern_copy
    ld      t0, NodePeer_direction(s4)      # we dialled: our Status first (v2 from fulu, v1 before)
    li      t1, LIBP2P_OUTBOUND
    bne     t0, t1, 69b
    addi    a0, sp, L
    call    node_status_bytes
    mv      a0, s2
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    li      a1, 1
    li      a4, 84
    li      t0, FORK_FULU
    bltu    a0, t0, 3f
    li      a1, 2
    li      a4, 92
3:  li      a0, REQRESP_STATUS
    ld      a2, NodePeer_handle(s4)
    addi    a3, sp, L
    call    node_open
    LEAVE 96
64: li      t1, LIBP2P_ACTION_DIAL_FAILED
    bne     t0, t1, 10f
    ld      t1, LIBP2P_ACT_TAG(s3)          # a dial of the node ends
    li      t2, NODE_DIAL_TAG
    and     t1, t1, t2
    beqz    t1, 69b
    ld      t1, Node_dialing(s1)
    beqz    t1, 69b
    addi    t1, t1, -1
    sd      t1, Node_dialing(s1)
    LEAVE 96
10: li      t1, LIBP2P_ACTION_PEER_DISCONNECTED
    bne     t0, t1, 20f
    ld      a0, LIBP2P_ACT_PEER(s3)
    call    node_find_peer
    li      t0, -1
    beq     a0, t0, 19f
    mv      a0, a1
    call    node_drop_peer
19: LEAVE 96
20: li      t1, LIBP2P_ACTION_STREAM_INBOUND
    bne     t0, t1, 30f
    ld      a0, LIBP2P_ACT_SI_PROTOCOL(s3)  # a request stream: its entry, or a reset
    call    node_protocol
    beqz    a0, 28f
    mv      s7, a0
    mv      s8, a1
    ld      t0, Node_messages(s1)
    ld      t1, Node_streams(s1)
    sub     t0, t0, t1
    ld      t2, Node_stream_bytes(s1)
    divu    t0, t0, t2
    ld      t3, (Node_streams + 8)(s1)
    bgeu    t3, t0, 28f
    mul     t4, t3, t2
    add     s4, s1, t1
    add     s4, s4, t4
    addi    t3, t3, 1
    sd      t3, (Node_streams + 8)(s1)
    ld      t0, LIBP2P_ACT_STREAM(s3)
    sd      t0, NodeStream_handle(s4)
    ld      t0, LIBP2P_ACT_SI_PEER(s3)
    sd      t0, NodeStream_peer(s4)
    sd      s7, NodeStream_method(s4)
    sd      s8, NodeStream_version(s4)
    li      t0, NODE_STREAM_REQUEST
    sd      t0, NodeStream_state(s4)
    addi    t0, t2, -NodeStream_list
    sd      t0, NodeStream_list(s4)
    li      t0, 24
    sd      t0, (NodeStream_list + 8)(s4)
    sd      zero, (NodeStream_list + 16)(s4)
    mv      a0, s4
    call    node_request
    LEAVE 96
28: li      a0, LIBP2P_EVENT_STREAM_RESET
    ld      a1, LIBP2P_ACT_STREAM(s3)
    call    node_out_handle
    LEAVE 96
30: li      t1, LIBP2P_ACTION_STREAM_DATA
    bne     t0, t1, 40f
    ld      a0, LIBP2P_ACT_STREAM(s3)       # request bytes: kept, then read
    call    node_find_stream
    li      t0, -1
    beq     a0, t0, 39f
    mv      s4, a1
    ld      t0, (NodeStream_list + 16)(s4)
    ld      a2, LIBP2P_ACT_SD_COUNT(s3)
    ld      t1, NodeStream_list(s4)
    addi    t1, t1, -24
    sub     t1, t1, t0
    bgtu    a2, t1, 38f
    addi    a0, s4, NodeStream_request
    add     a0, a0, t0
    addi    a1, s3, LIBP2P_ACT_SD_DATA
    add     t0, t0, a2
    sd      t0, (NodeStream_list + 16)(s4)
    call    lantern_copy
    mv      a0, s4
    ld      t0, NodeStream_state(s4)
    li      t1, NODE_STREAM_RESPONSE
    bne     t0, t1, 37f
    call    node_response                   # response bytes of the node's request
    LEAVE 96
37: call    node_request
39: LEAVE 96
38: li      a0, LIBP2P_EVENT_STREAM_RESET   # more than the room: a reset
    ld      a1, NodeStream_handle(s4)
    call    node_out_handle
    mv      a0, s4
    call    node_end_stream
    LEAVE 96
40: li      t1, LIBP2P_ACTION_STREAM_EOF
    bne     t0, t1, 50f
    ld      a0, LIBP2P_ACT_STREAM(s3)
    call    node_find_stream
    li      t0, -1
    beq     a0, t0, 49f
    ld      t0, NodeStream_state(a1)
    li      t1, NODE_STREAM_RESPONSE
    bne     t0, t1, 41f
    li      t0, 1                           # the response is complete
    sd      t0, NodeStream_next(a1)
    mv      a0, a1
    call    node_response
    LEAVE 96
41: li      t1, NODE_STREAM_EOF             # while its request is read
    bgtu    t0, t1, 49f
    sd      t1, NodeStream_state(a1)
    mv      a0, a1
    call    node_request
49: LEAVE 96
50: li      t1, LIBP2P_ACTION_STREAM_RESET
    bne     t0, t1, 59f
    ld      a0, LIBP2P_ACT_STREAM(s3)
    call    node_find_stream
    li      t0, -1
    beq     a0, t0, 59f
    mv      a0, a1
    call    node_end_stream
59: LEAVE 96
END_FUNCTION node_notice

/* a0 = the WAKEUP time of the libp2p actions in the ByteList a0, after their application notices, of the libp2p state a1. s3 an action, s4 the end, s7 the time, s8 the state. */
LOCAL_FUNCTION node_p2p_notices
    ENTER 0
    mv      s8, a1
    ld      t0, 8(a0)
    add     s3, a0, t0
    ld      t0, 16(a0)
    add     s4, s3, t0
    li      s7, -1
1:  bgeu    s3, s4, 9f
    ld      t0, LIBP2P_ACT_KIND(s3)
    li      t1, LIBP2P_ACTION_WAKEUP
    bne     t0, t1, 2f
    ld      s7, LIBP2P_ACT_TIME(s3)
    j       3f
2:  li      t1, LIBP2P_ACTION_PEER_CONNECTED
    bltu    t0, t1, 3f
    li      t1, LIBP2P_ACTION_SEND_DATAGRAM
    bgeu    t0, t1, 3f
    mv      a0, s3
    mv      a1, s8
    call    node_notice
3:  ld      t0, 0(s3)
    add     s3, s3, t0
    j       1b
9:  mv      a0, s7
    LEAVE 0
END_FUNCTION node_p2p_notices

/* The libp2p events of the P2P events from a0 to a1 join the end of the node's queued events. s3, s4 the range, s7 the queue. */
LOCAL_FUNCTION node_p2p_append
    ENTER 0
    mv      s3, a0
    mv      s4, a1
    P2P_OUT s7
1:  bgeu    s3, s4, 9f
    ld      t0, 8(s3)
    li      t1, NODE_EV_P2P
    bne     t0, t1, 2f
    ld      a2, 16(s3)
    ld      t0, 16(s7)
    addi    a0, s7, 24
    add     a0, a0, t0
    add     t1, t0, a2
    sd      t1, 16(s7)
    addi    a1, s3, 16
    call    lantern_copy
2:  ld      t0, 0(s3)
    add     s3, s3, t0
    j       1b
9:  LEAVE 0
END_FUNCTION node_p2p_append

/*
 * Of the P2P events from a0 to a1, the first a2 were taken: a0 = the next P2P event, or a1;
 * a1 = the bytes of the libp2p events of the P2P events from there on. Uses t0-t2.
 */
LOCAL_FUNCTION node_p2p_left
    UNWIND_END_PROLOGUE
    mv      t0, a0
    mv      t1, a1
    mv      a0, a1
    li      a1, 0
1:  bgeu    t0, t1, 9f
    ld      t2, 8(t0)
    addi    t2, t2, -NODE_EV_P2P
    bnez    t2, 3f
    beqz    a2, 2f
    addi    a2, a2, -1
    j       3f
2:  bne     a0, t1, 21f
    mv      a0, t0
21: ld      t2, 16(t0)
    add     a1, a1, t2
3:  ld      t2, 0(t0)
    add     t0, t0, t2
    j       1b
9:  ret
END_FUNCTION node_p2p_left

/* a0 = the events in the first a0 bytes of the node's queue. Uses t0-t3. */
LOCAL_FUNCTION node_out_count
    UNWIND_END_PROLOGUE
    P2P_OUT t0
    addi    t0, t0, 24
    li      t1, 0
    li      t2, 0
1:  bgeu    t1, a0, 2f
    add     t3, t0, t1
    ld      t3, 0(t3)
    add     t1, t1, t3
    addi    t2, t2, 1
    j       1b
2:  mv      a0, t2
    ret
END_FUNCTION node_out_count

/*
 * libp2p_step of the state a0 with the tick a1, the event list a2 and the scratch a3, its
 * actions in a P2P_LIST action that takes the action room left less a4 bytes, its StepResult at
 * a5: a0 = 0 and a1 = the actions' ByteList; 1 when the room is short; or libp2p's status, with
 * no action added. s3 state, s4 tick, s7 list, s8 scratch, s9 result, s10 the action.
 */
LOCAL_FUNCTION node_p2p_round
    ENTER 0
    mv      s3, a0
    mv      s4, a1
    mv      s7, a2
    mv      s8, a3
    mv      s9, a5
    ld      t0, 0(s6)
    ld      t1, 8(s6)
    ld      t2, 16(s6)
    sub     t0, t0, t1
    sub     t0, t0, t2
    bltu    t0, a4, 8f
    sub     t0, t0, a4
    li      t3, LIBP2P_ACTIONS_MIN + 24 + 16
    bltu    t0, t3, 8f
    srli    t4, t0, 1                       # half of it, when that is enough: the rest for the notices
    bltu    t4, t3, 1f
    mv      t0, t4
1:  andi    t0, t0, -8
    add     s10, s6, t1
    add     s10, s10, t2
    sd      t0, 0(s10)
    li      t3, NODE_ACT_P2P_LIST
    sd      t3, 8(s10)
    addi    t3, t0, -16
    sd      t3, 16(s10)
    li      t3, 24
    sd      t3, 24(s10)
    sd      zero, 32(s10)
    mv      a0, s3
    mv      a1, s4
    mv      a2, s7
    mv      a3, s8
    addi    a4, s10, 16
    mv      a5, s9
    CALL_GLOBAL libp2p_step
    bnez    a0, 9f
    ld      t0, 32(s10)                     # the action holds the actions written
    addi    t0, t0, 24
    sd      t0, 16(s10)
    addi    t0, t0, 16
    sd      t0, 0(s10)
    ld      t1, 16(s6)
    add     t1, t1, t0
    sd      t1, 16(s6)
    addi    a1, s10, 16
    li      a0, 0
    LEAVE 0
8:  li      a0, 1
9:  LEAVE 0
END_FUNCTION node_p2p_round

/*
 * (out, count): the protocol IDs of the req/resp protocols the node answers, as libp2p
 * ProtocolEntry values in the ByteList out, by method then version; count = how many.
 * s1 out, s2 count, s3 the protocols, s4 an index, s5 an entry. Locals: L a ReqRespProtocol,
 * L+16 a ByteList of an ID.
 */
FUNCTION lantern_node_protocols
    ENTER 176
    mv      s1, a0
    mv      s2, a1
    li      s3, 0
1:  mv      a0, s3
    call    node_protocol
    beqz    a0, 2f
    addi    s3, s3, 1
    j       1b
2:  li      t0, LIBP2P_PROTO_SIZE
    mul     t0, s3, t0
    addi    t1, t0, 24
    ld      t2, 0(s1)
    bltu    t2, t1, 8f
    li      t1, 24
    sd      t1, 8(s1)
    sd      t0, 16(s1)
    sd      s3, 0(s2)
    li      s4, 0
    addi    s5, s1, 24
3:  bgeu    s4, s3, 7f
    mv      a0, s4
    call    node_protocol
    sd      a0, L(sp)
    sd      a1, (L + 8)(sp)
    mv      a0, s5
    li      a1, LIBP2P_PROTO_SIZE
    call    lantern_zero
    li      t0, 24 + 128
    sd      t0, (L + 16)(sp)
    li      t0, 24
    sd      t0, (L + 24)(sp)
    sd      zero, (L + 32)(sp)
    addi    a0, sp, L
    addi    a1, sp, L + 16
    call    lantern_reqresp_protocol_id
    ld      a2, (L + 32)(sp)
    sd      a2, 0(s5)
    addi    a0, s5, 8
    addi    a1, sp, L + 40
    call    lantern_copy
    addi    s5, s5, LIBP2P_PROTO_SIZE
    addi    s4, s4, 1
    j       3b
7:  li      a0, LANTERN_OK
    LEAVE 176
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 176
END_FUNCTION lantern_node_protocols

/*
 * The root entry at a1 of the BLOCK event a0: its first u64 is 0 and the root follows, or the
 * first u64 is not 0 when the bytes are no SignedBeaconBlock. a0 = the status. s3 the ByteList,
 * s4 the entry.
 */
LOCAL_FUNCTION node_block_entry
    ENTER 16
    addi    s3, a0, NodeEvent_bytes
    mv      s4, a1
    li      t0, 1
    sd      t0, 0(s4)
    ld      t0, 16(s3)
    li      t1, 100 + 84
    bltu    t0, t1, 9f
    ld      t0, 8(s3)
    add     t0, s3, t0
    LDU64   a0, t0, 100, t1                 # the slot of the message
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s3
    mv      a1, s5
    addi    a2, s4, 8
    mv      a3, s4
    addi    a4, sp, L                       # its blob count: not kept
    FORK_CALL node_block_root
    LEAVE 16
9:  li      a0, LANTERN_OK
    LEAVE 16
END_FUNCTION node_block_entry

/*
 * (node, store, p2p, tick, events, scratch, actions, result): s1 node, s2 store, s3 the events,
 * s4 their end, s5 scratch, s6 actions, s7 result, s8 the event count, s9 the BLOCK
 * and GOSSIP WORK_DONE events then an event, s10 the event bytes then a root entry at the end of scratch,
 * t5 the WORK_DONE events in the first pass. Locals: L the WORK_DONE events, L+8 the scratch
 * size, L+16 p2p, L+24 tick, L+32 the end of the events handled, L+40 the queue's free bytes the P2P events take, saved,
 * L+48 the libp2p scratch, L+56 the bytes of the P2P events, L+64 the P2P events, L+72 the
 * action room kept for the node, L+80 wakeup, L+88 libp2p's StepResult, L+96 libp2p's actions,
 * L+104 the libp2p steps, L+112 a stream waits, L+120 the GOSSIP WORK_DONE events, L+128 the bytes of
 * the ENGINE events, L+136 1 with an ENR event,
 * L+144 the POW_BLOCK events.
 */
FUNCTION lantern_node_step
    ENTER 208
    mv      s1, a0
    mv      s2, a1
    sd      a2, (L + 16)(sp)
    sd      a3, (L + 24)(sp)
    ld      t0, 8(a4)
    ld      t1, 16(a4)
    add     s3, a4, t0
    add     s4, s3, t1
    mv      s5, a5
    mv      s6, a6
    mv      s7, a7
    li      s8, 0                           # first: check every event, and count
    li      s9, 0
    li      s10, 0
    li      t5, 0
    sd      zero, (L + 56)(sp)
    sd      zero, (L + 64)(sp)
    sd      zero, (L + 120)(sp)
    sd      zero, (L + 128)(sp)
    sd      zero, (L + 136)(sp)
    sd      zero, (L + 144)(sp)
    sd      zero, (L + 184)(sp)              # API: the largest scratch, and the API events
    sd      zero, (L + 192)(sp)
    sd      zero, (L + 200)(sp)             # the p2p_out bytes of the pool POSTs' publishes
    mv      t0, s3
1:  bgeu    t0, s4, 5f
    sub     t1, s4, t0
    li      t2, 16
    bltu    t1, t2, 7f
    ld      t2, 0(t0)                       # size, kind
    ld      t3, 8(t0)
    li      t4, 16
    bltu    t2, t4, 7f
    andi    t4, t2, 7
    bnez    t4, 7f
    bgtu    t2, t1, 7f
    addi    t4, t3, -1
    li      t6, NODE_EV_LAST
    bgeu    t4, t6, 7f
    li      t4, NODE_EV_API_SENT            # API_SENT, API_CLOSED: the connection at 16
    bltu    t3, t4, 11f
    li      t4, 24
    bltu    t2, t4, 7f
    j       4f
11: li      t4, NODE_EV_TICK
    bne     t3, t4, 2f
    li      t4, 24
    bltu    t2, t4, 7f
    j       4f
2:  li      t4, NODE_EV_WORK_DONE
    bne     t3, t4, 21f
    li      t4, NODE_EV_WORK_DONE_SIZE
    bltu    t2, t4, 7f
    ld      t4, NodeAction_work_kind(t0)    # SERVE: a ByteList of the chunk inside
    li      t6, NODE_WORK_GOSSIP            # GOSSIP: a block or a blob it may add
    bne     t4, t6, 23f
    addi    s9, s9, 1
    ld      t6, (L + 120)(sp)
    addi    t6, t6, 1
    sd      t6, (L + 120)(sp)
23: li      t6, NODE_WORK_IMPORT_BLOCK      # a valid IMPORT_BLOCK: a work for each vote
    bne     t4, t6, 231f
    ld      t6, NodeEvent_result(t0)
    bnez    t6, 22f
    ld      t4, NodeEvent_index(t0)
    li      t6, 128
    bleu    t4, t6, 232f
    mv      t4, t6
232: ld     t6, NodeEvent_root(t0)
    li      t3, 2
    bleu    t6, t3, 233f
    mv      t6, t3
233: add    t4, t4, t6
    li      t3, NODE_ACT_WORK_SIZE
    mul     t4, t4, t3
    add     s10, s10, t4
    j       22f
231: addi   t6, t4, -NODE_WORK_PUBLISH_DECODE   # the works of a publish: an API answer; of LANTERN_VALID, bytes inside
    li      t3, NODE_WORK_PUBLISH_SIDECAR - NODE_WORK_PUBLISH_DECODE
    bgtu    t6, t3, 2312f
    ld      t6, (L + 192)(sp)
    addi    t6, t6, 1
    sd      t6, (L + 192)(sp)
    li      t6, NODE_WORK_PUBLISH_CHECK     # a block, or a blob, it may add
    bne     t4, t6, 2313f
    addi    s9, s9, 1
2313: li    t6, NODE_WORK_PUBLISH_SIDECAR
    bne     t4, t6, 2314f
    ld      t6, (L + 120)(sp)
    addi    t6, t6, 1
    sd      t6, (L + 120)(sp)
2314: ld    t6, NodeEvent_result(t0)
    bnez    t6, 22f
    li      t6, NODE_WORK_PUBLISH_SIDECARS
    beq     t4, t6, 22f
    li      t6, NodeEvent_chunk + 24        # its ByteList at NodeEvent_chunk
    bltu    t2, t6, 7f
    ld      t6, (NodeEvent_chunk + 8)(t0)
    li      t3, 24
    bne     t6, t3, 7f
    addi    t6, t2, -(NodeEvent_chunk + 24)
    ld      t3, (NodeEvent_chunk + 16)(t0)
    bgtu    t3, t6, 7f
    add     s10, s10, t2                    # its bytes of actions
    ld      t4, Node_flags(s1)              # subscribed: p2p_out for its publish, and scratch for it
    andi    t4, t4, NODE_FLAG_SUBSCRIBED
    beqz    t4, 22f
    slli    t4, t2, 1
    addi    t4, t4, 512
    ld      t6, (L + 200)(sp)
    add     t6, t6, t4
    sd      t6, (L + 200)(sp)
    li      t4, SNAPPY_SCRATCH_COMPRESS + 192
    add     t4, t4, t2
    ld      t6, (L + 184)(sp)
    bgeu    t6, t4, 22f
    sd      t4, (L + 184)(sp)
    j       22f
2312: li    t6, NODE_WORK_SERVE             # SERVE, and NEW_PAYLOAD or FORKCHOICE of LANTERN_VALID: a ByteList of the chunk inside
    beq     t4, t6, 25f
    li      t6, NODE_WORK_API_SUBMIT        # API_SUBMIT: an API answer; of LANTERN_VALID, its records inside
    bne     t4, t6, 2311f
    ld      t4, (L + 192)(sp)
    addi    t4, t4, 1
    sd      t4, (L + 192)(sp)
    ld      t6, NodeEvent_result(t0)
    bnez    t6, 22f
    mv      a0, t0
    mv      a1, t2
    call    node_submit_check
    bnez    a0, 7f
    add     s10, s10, t2                    # twice its bytes of actions
    ld      t4, Node_flags(s1)              # subscribed: p2p_out for its publishes, and scratch for one
    andi    t4, t4, NODE_FLAG_SUBSCRIBED
    beqz    t4, 22f
    ld      t4, NodeEvent_index(t0)
    slli    t4, t4, 9
    slli    t6, t2, 1
    add     t4, t4, t6
    ld      t6, (L + 200)(sp)
    add     t6, t6, t4
    sd      t6, (L + 200)(sp)
    li      t4, SNAPPY_SCRATCH_COMPRESS + 192
    add     t4, t4, t2
    ld      t6, (L + 184)(sp)
    bgeu    t6, t4, 22f
    sd      t4, (L + 184)(sp)
    j       22f
2311:
    li      t6, NODE_WORK_API_LOOKUP        # API_LOOKUP: an API answer's scratch and actions
    bne     t4, t6, 233f
    ld      t4, (L + 184)(sp)
    li      t6, NODE_API_SCRATCH
    bgeu    t4, t6, 234f
    sd      t6, (L + 184)(sp)
234: ld     t4, (L + 192)(sp)
    addi    t4, t4, 1
    sd      t4, (L + 192)(sp)
    j       22f
233: li     t6, NODE_WORK_API_CHUNK         # API_CHUNK of LANTERN_VALID: its ByteList at NodeEvent_api_bytes
    bne     t4, t6, 232f
    ld      t6, NodeEvent_result(t0)
    bnez    t6, 22f
    li      t4, NodeEvent_api_bytes + 24
    bltu    t2, t4, 7f
    ld      t4, (NodeEvent_api_bytes + 8)(t0)
    li      t6, 24
    bne     t4, t6, 7f
    ld      t4, (NodeEvent_api_bytes + 16)(t0)
    addi    t6, t2, -(NodeEvent_api_bytes + 24)
    bgtu    t4, t6, 7f
    j       22f
232: li     t6, NODE_WORK_API_ENCODE
    beq     t4, t6, 24f
    li      t6, NODE_WORK_NEW_PAYLOAD
    beq     t4, t6, 24f
    li      t6, NODE_WORK_FORKCHOICE
    bne     t4, t6, 22f
24: ld      t6, NodeEvent_result(t0)
    bnez    t6, 22f
25:
    li      t4, NodeEvent_chunk + 24
    bltu    t2, t4, 7f
    ld      t4, (NodeEvent_chunk + 8)(t0)
    li      t6, 24
    bne     t4, t6, 7f
    ld      t4, (NodeEvent_chunk + 16)(t0)
    addi    t6, t2, -(NodeEvent_chunk + 24)
    bgtu    t4, t6, 7f
22: addi    t5, t5, 1
    j       4f
21: li      t4, NODE_EV_ENGINE              # ENGINE: arg 0 with bytes, or 1; with NODE_FLAG_ENGINE
    bne     t3, t4, 211f
    ld      t4, Node_flags(s1)
    andi    t4, t4, NODE_FLAG_ENGINE
    beqz    t4, 7f
    li      t4, 24
    bltu    t2, t4, 7f
    ld      t4, 16(t0)
    li      t6, 1
    bgtu    t4, t6, 7f
    beq     t4, t6, 4f
    li      t4, 24 + 24
    bltu    t2, t4, 7f
    ld      t4, (24 + 8)(t0)
    li      t6, 24
    bne     t4, t6, 7f
    ld      t4, (24 + 16)(t0)
    addi    t6, t2, -(24 + 24)
    bgtu    t4, t6, 7f
    ld      t6, (L + 128)(sp)
    add     t6, t6, t4
    sd      t6, (L + 128)(sp)
    j       4f
211: li     t4, NODE_EV_P2P                 # a libp2p event inside, for a node with a libp2p state
    bne     t3, t4, 3f
    ld      t4, (L + 16)(sp)
    beqz    t4, 7f
    li      t4, 16 + 16
    bltu    t2, t4, 7f
    ld      t4, 16(t0)
    li      t6, 16
    bltu    t4, t6, 7f
    andi    t6, t4, 7
    bnez    t6, 7f
    addi    t6, t2, -16
    bgtu    t4, t6, 7f
    ld      t6, (L + 56)(sp)
    add     t6, t6, t4
    sd      t6, (L + 56)(sp)
    ld      t6, (L + 64)(sp)
    addi    t6, t6, 1
    sd      t6, (L + 64)(sp)
    j       4f
3:  li      t4, NODE_EV_PAYLOAD_STATUS      # the ByteList at 24: its bytes inside the event
    beq     t3, t4, 7f
    li      t4, 24 + 24
    bltu    t2, t4, 7f
    ld      t4, (24 + 8)(t0)
    li      t6, 24
    bne     t4, t6, 7f
    ld      t4, (24 + 16)(t0)
    addi    t6, t2, -(24 + 24)
    bgtu    t4, t6, 7f
    li      t4, NODE_EV_ENR                 # ENR: with p2p
    bne     t3, t4, 33f
    ld      t4, (L + 16)(sp)
    beqz    t4, 7f
    li      t4, 1
    sd      t4, (L + 136)(sp)
33: li      t4, NODE_EV_API                 # API, API_IDENTITY: their bytes keep their rules
    bltu    t3, t4, 34f
    sd      t0, (L + 160)(sp)
    sd      t2, (L + 168)(sp)
    sd      t5, (L + 176)(sp)
    mv      a0, t0
    call    node_api_check
    ld      t0, (L + 160)(sp)
    ld      t2, (L + 168)(sp)
    ld      t5, (L + 176)(sp)
    bnez    a0, 7f
    ld      t4, (L + 184)(sp)
    bgeu    t4, a1, 35f
    sd      a1, (L + 184)(sp)
35: ld      t3, 8(t0)
    li      t4, NODE_EV_API
    bne     t3, t4, 4f
    ld      t4, (L + 192)(sp)
    addi    t4, t4, 1
    sd      t4, (L + 192)(sp)
    ld      t4, (NodeEvent_bytes + 24 + HttpRequest_status)(t0)  # API: 16 bytes of actions for each byte of the body, its ids
    bnez    t4, 4f
    ld      t4, (NodeEvent_bytes + 24 + HttpRequest_body + 8)(t0)
    slli    t4, t4, 4
    add     s10, s10, t4
    j       4f
34: li      t4, NODE_EV_BLOCK
    beq     t3, t4, 31f
    li      t4, NODE_EV_POW_BLOCK
    bne     t3, t4, 4f
    ld      t4, (L + 144)(sp)               # POW_BLOCK: counted at L+144
    addi    t4, t4, 1
    sd      t4, (L + 144)(sp)
    j       4f
31: addi    s9, s9, 1
4:  addi    s8, s8, 1
    add     s10, s10, t2
    add     t0, t0, t2
    j       1b
5:  sd      t5, L(sp)
    call    node_column_count               # the columns sampled, for the blobs part
    sd      a0, (L + 152)(sp)
    call    node_api_publish_count          # an answer for each publishBlockV2 that waits
    ld      t0, (L + 192)(sp)
    add     t0, t0, a0
    sd      t0, (L + 192)(sp)
    call    node_api_event_count            # with event streams: NODE_API_SCRATCH of scratch, 1024 per event for each
    beqz    a0, 58f
    ld      t0, (L + 184)(sp)
    li      t1, NODE_API_SCRATCH
    bgeu    t0, t1, 58f
    sd      t1, (L + 184)(sp)
58: slli    t1, a0, 10
    addi    t1, t1, 512
    mul     t1, s8, t1                      # room: actions, node parts, scratch
    add     t1, t1, s10
    addi    t1, t1, 2 * NODE_ACT_WORK_SIZE
    LDQ     t2, s1, Node_pool + 8           # a POOL_CHECK for each pool entry
    li      t3, NODE_ACT_WORK_SIZE
    mul     t2, t2, t3
    add     t1, t1, t2
    ld      t2, (L + 192)(sp)               # 2048 for each API answer
    slli    t2, t2, 11
    add     t1, t1, t2
    ld      t2, (Node_blocks + 8)(s1)       # the prune's and the rebuilds' actions: 384 for each block, 160 for each blob, 32 for each checkpoint
    li      t3, 384
    mul     t2, t2, t3
    add     t1, t1, t2
    ld      t2, (Node_blobs + 8)(s1)
    li      t3, 160
    mul     t2, t2, t3
    add     t1, t1, t2
    ld      t2, (Node_checkpoints + 8)(s1)
    slli    t2, t2, 5
    add     t1, t1, t2
    li      t2, 2048                        # and 2048 free: the crossing of a fork boundary takes 208
    add     t1, t1, t2
    ld      t2, Node_engine_method(s1)      # a getPayload in flight: its result's bytes, as engine_in holds them, and 1072
    li      t3, ENGINE_METHOD_GET_PAYLOAD
    bne     t2, t3, 581f
    ld      t2, Node_engine_in(s1)
    add     t2, s1, t2
    ld      t2, 16(t2)
    add     t1, t1, t2
    addi    t1, t1, 1072
581: sd     t1, (L + 72)(sp)
    ld      t2, (L + 16)(sp)
    beqz    t2, 51f
    li      t2, LIBP2P_ACTIONS_MIN + 24 + 16
    add     t1, t1, t2
51: ld      t0, 0(s6)
    ld      t2, 8(s6)
    bltu    t0, t2, 81f
    sub     t0, t0, t2
    ld      t2, 16(s6)
    bltu    t0, t2, 81f
    sub     t0, t0, t2
    bltu    t0, t1, 81f
    ld      t0, Node_checkpoints(s1)        # blocks: one entry for each BLOCK event
    ld      t1, Node_blocks(s1)
    sub     t0, t0, t1
    li      t1, NodeBlock__mem
    divu    t0, t0, t1
    ld      t1, (Node_blocks + 8)(s1)
    sub     t0, t0, t1
    mv      t1, s9                          # with p2p, NODE_SYNC_BATCH more for the responses
    ld      t2, (L + 16)(sp)
    beqz    t2, 1f
    addi    t1, t1, NODE_SYNC_BATCH
1:  bltu    t0, t1, 85f
    LDQ     t0, s1, Node_api                # blobs: one for each GOSSIP WORK_DONE event, and with p2p a batch's sidecars
    ld      t1, Node_blobs(s1)
    sub     t0, t0, t1
    li      t1, NodeBlob__mem
    divu    t0, t0, t1
    ld      t1, (Node_blobs + 8)(s1)
    sub     t0, t0, t1
    ld      t1, (L + 120)(sp)
    ld      t2, (L + 16)(sp)
    beqz    t2, 549f
    LDQ     t2, s1, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK
    LDQ     t3, s1, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
    bgeu    t2, t3, 547f
    mv      t2, t3
547: ld     t3, (L + 152)(sp)
    bgeu    t2, t3, 548f
    mv      t2, t3
548: srli   t3, t2, 32
    bnez    t3, 86f
    li      t3, NODE_SYNC_BATCH
    mul     t2, t2, t3
    add     t1, t1, t2
549: bltu   t0, t1, 86f
    ld      t0, Node_engine_in(s1)          # engine_in: the bytes of the ENGINE events
    add     t0, s1, t0
    ld      t1, 0(t0)
    ld      t2, 16(t0)
    addi    t1, t1, -24
    sub     t1, t1, t2
    ld      t2, (L + 128)(sp)
    bltu    t1, t2, 87f
    ld      t0, Node_pow_blocks(s1)         # checkpoints: two for each WORK_DONE event, and two
    ld      t1, Node_checkpoints(s1)
    sub     t0, t0, t1
    li      t1, NodeCheckpoint__mem
    divu    t0, t0, t1
    ld      t1, (Node_checkpoints + 8)(s1)
    sub     t0, t0, t1
    slli    t1, t5, 1
    addi    t1, t1, 2
    bltu    t0, t1, 88f
    ld      t0, Node_flags(s1)              # with NODE_FLAG_DB at a new finalized epoch: the Db's room for the archive
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 56f
    ld      t2, Node_db(s1)
    add     t2, s1, t2
    ld      t0, Store_finalized_checkpoint(s2)
    ld      t1, Node_pruned_epoch(s1)
    bleu    t0, t1, 561f
    li      t1, SLOTS_PER_EPOCH             # the slots to the finalized checkpoint's
    mul     t0, t0, t1
    addi    t0, t0, 1
    ld      t1, Db_first_slot(t2)
    bltu    t0, t1, 561f
    sub     t0, t0, t1
    ld      t1, (Db_slots + 8)(t2)
    bltu    t1, t0, 93f
561: ld     t0, Db_blocks(t2)               # the roots, at each step for the backfill: twice the blocks
    ld      t1, (Node_blocks + 8)(s1)
    add     t0, t0, t1
    slli    t0, t0, 1
    ld      t1, (Db_roots + 8)(t2)
    bltu    t1, t0, 94f
    ld      t0, Node_backfill_start(s1)     # a backfill request open or unweighed: the slots below backfill_slot
    li      t1, -1
    beq     t0, t1, 56f
    ld      t0, Node_backfill_slot(s1)
    ld      t1, Db_first_slot(t2)
    bltu    t0, t1, 56f
    sub     t0, t0, t1
    ld      t1, (Db_slots + 8)(t2)
    bltu    t1, t0, 93f
56:
    ld      t0, (L + 192)(sp)               # api: an entry free for each API event
    beqz    t0, 57f
    call    node_api_free
    ld      t0, (L + 192)(sp)
    bltu    a0, t0, 95f
57:
    ld      t0, Node_peers(s1)              # pow blocks: one for each POW_BLOCK event
    ld      t1, Node_pow_blocks(s1)
    sub     t0, t0, t1
    li      t1, POW_BLOCK_BYTES
    divu    t0, t0, t1
    ld      t1, (Node_pow_blocks + 8)(s1)
    sub     t0, t0, t1
    ld      t1, (L + 144)(sp)
    bltu    t0, t1, 89f
    li      t3, NODE_ROOT_ENTRY             # scratch: the root entries, and with p2p the queue's bytes the P2P events take and libp2p's scratch, at its end
    mul     t3, s9, t3
    ld      t0, (L + 16)(sp)
    beqz    t0, 52f
    P2P_OUT t4                              # the queue has room for the P2P events
    ld      t0, 0(t4)
    ld      t1, 16(t4)
    addi    t0, t0, -24
    sub     t0, t0, t1
    ld      t1, (L + 56)(sp)
    ld      t2, (L + 200)(sp)               # and for the publishes of the pool POSTs
    add     t2, t2, t1
    bltu    t0, t2, 90f
    add     t3, t3, t1
    li      t0, LIBP2P_SCRATCH_SIZE
    add     t3, t3, t0
52: LDQ     t0, s2, Store_validators        # and what get_head needs
    LDQ     t1, s2, Store_blocks
    sub     t0, t0, t1
    slli    t0, t0, 4
    li      t1, BlockNode__mem
    divu    t0, t0, t1
    li      t1, LANTERN_SCRATCH_FIXED + 64
    add     t0, t0, t1
    add     t0, t0, t3
    ld      t1, (Node_blocks + 8)(s1)       # and the prune's chain of blocks
    slli    t1, t1, 3
    add     t0, t0, t1
    ld      t1, (L + 136)(sp)               # with an ENR event, the record's decoding
    beqz    t1, 55f
    li      t1, DISCV5_ENR_SIZE + DISCV5_ENR_SCRATCH
    add     t0, t0, t1
55: ld      t1, (L + 184)(sp)               # and the largest API answer's
    add     t0, t0, t1
    ld      t1, 0(s5)
    bltu    t1, t0, 83f
    sd      t1, (L + 8)(sp)
    sub     t1, t1, t3
    sd      t1, 0(s5)
    add     s10, s5, t1
    ld      t0, (L + 16)(sp)
    beqz    t0, 53f
    li      t0, NODE_ROOT_ENTRY             # the saved queue bytes, then libp2p's scratch
    mul     t0, s9, t0
    add     t0, s10, t0
    sd      t0, (L + 40)(sp)
    ld      t1, (L + 56)(sp)
    add     t0, t0, t1
    sd      t0, (L + 48)(sp)
    li      t1, LIBP2P_SCRATCH_SIZE
    sd      t1, 0(t0)
53: li      t0, NODE_SHORT_SCRATCH          # the root of each BLOCK event, before any change; its room: scratch
    sd      t0, NodeStepResult_short(s7)
    mv      s9, s3
11: bgeu    s9, s4, 13f
    ld      t0, 8(s9)
    li      t1, NODE_EV_BLOCK
    bne     t0, t1, 12f
    mv      a0, s9
    mv      a1, s10
    call    node_block_entry
    bnez    a0, 14f
    addi    s10, s10, NODE_ROOT_ENTRY
12: ld      t0, 0(s9)
    add     s9, s9, t0
    j       11b
13: sd      s4, (L + 32)(sp)                # libp2p: the queued events, then the P2P events
    li      t0, -1
    sd      t0, (L + 80)(sp)
    ld      t0, (L + 16)(sp)
    beqz    t0, 30f
    P2P_OUT s9                              # s9 the queue, s10 its bytes before the P2P events
    ld      s10, 16(s9)
    ld      a0, (L + 40)(sp)                # the free bytes of the queue the P2P events take, kept
    addi    a1, s9, 24
    add     a1, a1, s10
    ld      a2, (L + 56)(sp)
    call    lantern_copy
    mv      a0, s3
    mv      a1, s4
    call    node_p2p_append
    ld      a0, (L + 16)(sp)
    ld      a1, (L + 24)(sp)
    mv      a2, s9
    ld      a3, (L + 48)(sp)
    ld      a4, (L + 72)(sp)
    addi    a5, sp, L + 88
    call    node_p2p_round
    beqz    a0, 24f
    sd      a0, (L + 104)(sp)               # a status of libp2p: the queue as it was, and nothing else changed
    sd      s10, 16(s9)
    addi    a0, s9, 24
    add     a0, a0, s10
    ld      a1, (L + 40)(sp)
    ld      a2, (L + 56)(sp)
    call    lantern_copy
    ld      t0, (L + 104)(sp)
    li      t1, LIBP2P_BUFFER_TOO_SMALL
    li      a0, LANTERN_INVALID_EVENT
    bne     t0, t1, 14f
    li      a0, LANTERN_BUFFER_TOO_SMALL
    li      t0, NODE_SHORT_ACTIONS          # libp2p's room: actions
    sd      t0, NodeStepResult_short(s7)
    j       14f
24: sd      a1, (L + 96)(sp)                # from here on the step holds
    mv      a0, s10                         # the P2P events libp2p took: k less the queued ones
    call    node_out_count
    ld      t0, (L + 88)(sp)
    sub     a2, t0, a0
    bgeu    t0, a0, 25f
    li      a2, 0
25: mv      a0, s3
    mv      a1, s4
    call    node_p2p_left
    sd      a0, (L + 32)(sp)                # the step ends at the next one
    ld      t0, 16(s9)                      # the ones left go from the queue's end
    sub     t0, t0, a1
    sd      t0, 16(s9)
    ld      a0, (L + 88)(sp)                # the ones taken from its front
    call    node_out_consume
29: ld      a0, (L + 96)(sp)
    ld      a1, (L + 16)(sp)
    call    node_p2p_notices
    sd      a0, (L + 80)(sp)
30: call    node_prune                      # at a new finalized epoch, the prune; then each event, in order
    ld      t0, 0(s5)
    add     s10, s5, t0
    li      s8, 0
    mv      s9, s3
6:  ld      t0, (L + 32)(sp)
    bgeu    s9, t0, 9f
    addi    s8, s8, 1
    ld      t0, 8(s9)
    li      t1, NODE_EV_P2P
    beq     t0, t1, 15f
    mv      a0, s9
    mv      a1, s10
    call    node_event
    ld      t0, 8(s9)
    li      t1, NODE_EV_BLOCK
    bne     t0, t1, 15f
    addi    s10, s10, NODE_ROOT_ENTRY
15: ld      t0, 0(s9)
    add     s9, s9, t0
    j       6b
9:  call    node_head
    call    node_publish_poll               # the answers of the published blocks whose import ended
    call    node_engine_next
    call    node_shed                       # the post-states the node can rebuild go
    call    node_api_head_events            # the head and finalized_checkpoint events, at a quiet point
    call    node_backfill_link              # the backfill's blocks of the chain join the Db
    call    node_drop_sidecars              # the sidecars the node no longer serves go
    sd      zero, (L + 112)(sp)
    ld      t0, (L + 16)(sp)                # the next block of each stream that serves, then libp2p again
    beqz    t0, 40f
    call    node_subscribe
    call    node_serve
    sd      a0, (L + 112)(sp)
    call    node_vote_due                   # the votes of valid aggregates whose slot is past
    ld      t0, (L + 112)(sp)
    or      t0, t0, a0
    sd      t0, (L + 112)(sp)
    call    node_sync
    ld      t0, (L + 112)(sp)
    or      t0, t0, a0
    sd      t0, (L + 112)(sp)
    ld      a0, (L + 24)(sp)
    call    node_lookup
    sd      zero, (L + 104)(sp)
32: P2P_OUT a2
    ld      t0, 16(a2)
    beqz    t0, 40f
    ld      t1, (L + 104)(sp)
    li      t2, NODE_P2P_ROUNDS
    bgeu    t1, t2, 40f
    addi    t1, t1, 1
    sd      t1, (L + 104)(sp)
    ld      a0, (L + 16)(sp)
    ld      a1, (L + 24)(sp)
    ld      a3, (L + 48)(sp)
    li      a4, 4096
    addi    a5, sp, L + 88
    call    node_p2p_round
    bnez    a0, 40f
    sd      a1, (L + 96)(sp)
    ld      a0, (L + 88)(sp)
    call    node_out_consume
    ld      a0, (L + 96)(sp)
    ld      a1, (L + 16)(sp)
    call    node_p2p_notices
    sd      a0, (L + 80)(sp)
    j       32b
40: P2P_OUT t0                              # events left, or a stream that waits: the next step is due now
    ld      t0, 16(t0)
    ld      t1, (L + 112)(sp)
    or      t0, t0, t1
    beqz    t0, 41f
    ld      t1, (L + 24)(sp)
    ld      t1, LIBP2P_TICK_NOW(t1)
    sd      t1, (L + 80)(sp)
41: ld      t0, (L + 8)(sp)
    sd      t0, 0(s5)
    sd      s8, NodeStepResult_accepted(s7)
    ld      t0, (L + 80)(sp)
    sd      t0, NodeStepResult_wakeup(s7)
    li      a0, LANTERN_OK
    LEAVE 208
14: ld      t0, (L + 8)(sp)                 # a status before any change
    sd      t0, 0(s5)
    LEAVE 208
7:  li      a0, LANTERN_INVALID_EVENT
    LEAVE 208
81: li      t0, NODE_SHORT_ACTIONS          # the buffer with too little room
    j       84f
85: li      t0, NodeRoom_blocks             # a part of the node: the NodeRoom field of its capacity
    j       82f
86: li      t0, NodeRoom_blobs
    j       82f
87: li      t0, NodeRoom_engine_bytes
    j       82f
88: li      t0, NodeRoom_checkpoints
    j       82f
89: li      t0, NodeRoom_pow_blocks
    j       82f
93: li      t0, NodeRoom_db_slots
    j       82f
94: li      t0, NodeRoom_db_roots
    j       82f
95: li      t0, NodeRoom_api_streams
    j       82f
90: li      t0, NodeRoom_p2p_out
82: sd      t0, NodeStepResult_room(s7)
    li      t0, NODE_SHORT_NODE
    j       84f
83: li      t0, NODE_SHORT_SCRATCH
84: sd      t0, NodeStepResult_short(s7)
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 208
END_FUNCTION lantern_node_step

/*
 * (node, store, seen, work, state_a, state_b, state_c, data, settings, scratch, event): s1 node,
 * s2 store, s3 work, s4 state_a, s5 data, s6 scratch, s7 event, s8 the event's room, s10 1 for a SERVE of a blob method, s9 a
 * temporary. Locals: L the BlockOptions (32), or a chunk's size, a fork digest and a ChunkHeader
 * (64); L+64 seen, L+72 state_b, L+80 state_c, L+88 settings, L+96 a NodeGossip.
 */
# The StateRoom of an upgraded state (node.md, NODE_WORK_UPGRADE): as the binary's anchor has.
    RODATA
    .p2align 3
node_upgrade_room:
    .quad 1024, 2048, 64, 1024, 64, 64, 4, 4096

FUNCTION lantern_node_run
    ENTER 192
    mv      s1, a0
    mv      s2, a1
    mv      s3, a3
    mv      s4, a4
    sd      a2, (L + 64)(sp)                # seen, state_b, state_c, settings
    sd      a5, (L + 72)(sp)
    sd      a6, (L + 80)(sp)
    mv      s5, a7
    ld      t0, (192 + 96)(sp)               # the ninth to eleventh arguments
    sd      t0, (L + 88)(sp)
    ld      s6, (192 + 96 + 8)(sp)
    ld      s7, (192 + 96 + 16)(sp)
    ld      s8, 0(s7)                       # the event's room
    li      t0, NODE_EV_WORK_DONE_SIZE
    bltu    s8, t0, 7f
    li      t0, NODE_EV_WORK_DONE_SIZE      # the event: the work's fields, the result
    sd      t0, 0(s7)
    li      t0, NODE_EV_WORK_DONE
    sd      t0, 8(s7)
    .irp off, 16, 24, 32, 40, 48, 56, 64
    ld      t0, \off(s3)
    sd      t0, \off(s7)
    .endr
    addi    a0, s7, NodeEvent_result
    li      a1, NODE_EV_WORK_DONE_SIZE - NodeEvent_result
    call    lantern_zero
    ld      t0, NodeAction_work_kind(s3)
    li      t1, NODE_WORK_IMPORT_BLOCK
    bne     t0, t1, 10f
    ld      t0, Node_flags(s1)              # IMPORT_BLOCK: the options, then the fork's on_block
    andi    t0, t0, NODE_FLAG_OPTIMISTIC
    li      t1, PAYLOAD_STATUS_VALID
    beqz    t0, 1f
    li      t1, PAYLOAD_STATUS_NOT_VALIDATED
1:  sd      t1, (L + BlockOptions_payload_status)(sp)
    ld      t0, NodeAction_target(s3)
    PART    t1, t2, s1, Node_blocks
    li      t3, 0
    bgeu    t0, t2, 2f
    li      t2, NodeBlock__mem
    mul     t2, t0, t2
    add     t1, t1, t2
    ld      t3, NodeBlock_data_available(t1)
    ld      t2, Node_flags(s1)              # with NODE_FLAG_ENGINE, the block's: the engine's answer
    andi    t2, t2, NODE_FLAG_ENGINE
    beqz    t2, 2f
    ld      t2, NodeBlock_payload_status(t1)
    sd      t2, (L + BlockOptions_payload_status)(sp)
2:  sd      t3, (L + BlockOptions_data_available)(sp)
    sd      zero, (L + BlockOptions_pow_block)(sp)
    sd      zero, (L + BlockOptions_pow_parent)(sp)
    ld      t0, 16(s5)
    li      t1, 100 + 84
    bltu    t0, t1, 18f
    ld      t0, 8(s5)
    add     t0, s5, t0
    LDU64   a0, t0, 100, t1
    mv      s9, a0                          # the block's slot, then its fork
    addi    a1, s1, Node_config
    call    node_fork
    mv      s10, a0
    ld      a0, NODE_STATE_SLOT(s4)         # the state's slot of the block's fork
    addi    a1, s1, Node_config
    call    node_fork
    bne     a0, s10, 19f
    ld      a0, NODE_STATE_SLOT(s4)         # slots_done: the state at the block's slot, the first of its fork
    li      t3, 0
    bne     a0, s9, 11f
    beqz    a0, 11f
    addi    a0, a0, -1
    addi    a1, s1, Node_config
    call    node_fork
    sub     t3, a0, s10
    snez    t3, t3
11: sd      t3, (L + BlockOptions_slots_done)(sp)
    mv      t6, s10
    mv      a0, s2
    mv      a1, s1
    mv      a2, s5
    mv      a3, s4
    addi    a4, sp, L
    mv      a5, s6
    addi    a6, s7, NodeEvent_result
    FORK_CALL node_import
    li      t0, LANTERN_NEED_JUSTIFIED_STATE
    bne     a0, t0, 972f
    sd      a0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    LEAVE 192
972: bnez   a0, 973f                        # valid: the counts of its votes
    ld      t0, NodeEvent_result(s7)
    bnez    t0, 973f
    mv      a0, s5
    mv      a1, s7
    call    node_vote_counts
    li      a0, LANTERN_OK
973: LEAVE 192
18: li      t0, LANTERN_INVALID_ENCODING
    sd      t0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    LEAVE 192
19: li      t0, LANTERN_INVALID_SLOT
    sd      t0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    LEAVE 192
10: li      t1, NODE_WORK_JUSTIFIED_STATE
    bne     t0, t1, 20f
    ld      a0, NODE_STATE_SLOT(s4)         # JUSTIFIED_STATE: the fork of the state's slot
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s2
    mv      a1, s4
    FORK_CALL store_justified_checkpoint_state
    LEAVE 192
20: li      t1, NODE_WORK_TARGET_STATE
    bne     t0, t1, 30f
    ld      a0, NODE_STATE_SLOT(s4)         # TARGET_STATE: store_target_checkpoint_state of the checkpoint
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    ld      t0, NodeAction_target(s3)
    PART    a1, t1, s1, Node_checkpoints
    bgeu    t0, t1, 8f
    li      t1, NodeCheckpoint__mem
    mul     t1, t0, t1
    add     a1, a1, t1
    mv      a0, s4
    addi    a2, s1, Node_config
    mv      a3, s6
    addi    a4, s7, NodeEvent_result
    FORK_CALL store_target_checkpoint_state
    LEAVE 192
30: li      t1, NODE_WORK_ATTESTATION
    bne     t0, t1, 40f
    ld      t0, 16(s5)                      # ATTESTATION: the fork of its slot
    li      t1, 4 + 128 + 96
    bltu    t0, t1, 18b
    ld      t0, 8(s5)
    add     t0, s5, t0
    LDU64   a0, t0, 4, t1
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s2
    mv      a1, s5
    addi    a2, s3, NodeAction_arg
    mv      a3, s4
    mv      a4, s6
    addi    a5, s7, NodeEvent_result
    addi    a6, s7, NodeEvent_checkpoint
    FORK_CALL node_attestation
    LEAVE 192
40: li      t1, NODE_WORK_ATTESTER_SLASHING
    bne     t0, t1, 50f
    mv      a0, s2                          # ATTESTER_SLASHING: the fork of the store's slot
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    mv      s10, a0
    beqz    s4, 41f                         # a state of another fork: IGNORE
    ld      a0, NODE_STATE_SLOT(s4)
    addi    a1, s1, Node_config
    call    node_fork
    bne     a0, s10, 69f
41: mv      t6, s10
    mv      a0, s2
    mv      a1, s5
    mv      a2, s4
    mv      a3, s6
    addi    a4, s7, NodeEvent_result
    FORK_CALL node_attester_slashing
99: LEAVE 192
50: li      t1, NODE_WORK_SERVE
    bne     t0, t1, 60f
    ld      t0, NodeAction_arg(s3)          # SERVE: s10 1 for a blob method, 2 for a column method
    srli    t0, t0, 8
    addi    t1, t0, -REQRESP_BLOB_SIDECARS_BY_RANGE
    addi    t2, t0, -REQRESP_BLOB_SIDECARS_BY_ROOT
    seqz    t1, t1
    seqz    t2, t2
    or      s10, t1, t2
    addi    t1, t0, -REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE
    addi    t2, t0, -REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT
    seqz    t1, t1
    seqz    t2, t2
    or      t1, t1, t2
    slli    t1, t1, 1
    or      s10, s10, t1
    ld      t0, 16(s5)                      # the chunk of the block's or sidecar's bytes, with room for it
    li      t1, 100 + 84
    beqz    s10, 501f
    li      t1, NODE_BLOB_HEADER + 8
    li      t2, 1
    beq     s10, t2, 501f
    li      t1, NODE_COLUMN_HEADER + 8
501: bltu   t0, t1, 18b
    sd      t0, L(sp)
    addi    a0, sp, L
    addi    a1, sp, L
    call    lantern_reqresp_chunk_size
    ld      t0, L(sp)
    addi    t0, t0, NodeEvent_chunk + 24 + 7
    andi    t0, t0, -8
    bltu    s8, t0, 7f
    ld      t0, 8(s5)                       # the context: ForkDigest of the epoch of the block's or header's slot
    add     t0, s5, t0
    bnez    s10, 502f
    LDU64   s9, t0, 100, t1
    j       503f
502: li     t1, 2
    beq     s10, t1, 504f
    LDQ     s9, t0, NODE_BLOB_HEADER
    j       503f
504: LDU64  s9, t0, NODE_COLUMN_HEADER, t1
503: mv     a0, s9
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    li      t0, SLOTS_PER_EPOCH
    divu    t0, s9, t0
    sd      t0, L(sp)
    sd      zero, (L + 8)(sp)
    addi    a0, s1, Node_genesis_validators_root
    addi    a1, sp, L
    addi    a2, s1, Node_config
    mv      a3, s6
    addi    a4, sp, L + 8
    FORK_CALL compute_fork_digest
    bnez    a0, 99b
    li      t0, CHUNK_RESPONSE              # the header: blocks v1 have no context bytes
    sd      t0, (L + 16 + ChunkHeader_kind)(sp)
    ld      t0, NodeAction_arg(s3)
    srli    t3, t0, 8
    andi    t0, t0, 255
    li      t1, 2
    li      t2, 4
    bnez    s10, 51f
    li      t4, REQRESP_BEACON_BLOCKS_BY_HEAD   # blocks by head: a context too
    beq     t3, t4, 51f
    bgeu    t0, t1, 51f
    li      t2, 0
51: sd      t2, (L + 16 + ChunkHeader_context_length)(sp)
    sd      zero, (L + 16 + ChunkHeader_result)(sp)
    lwu     t0, (L + 8)(sp)
    sd      t0, (L + 16 + ChunkHeader_context)(sp)
    addi    s9, s7, NodeEvent_chunk         # the chunk's ByteList after the WORK_DONE fields
    addi    t0, s8, -NodeEvent_chunk
    sd      t0, 0(s9)
    li      t0, 24
    sd      t0, 8(s9)
    sd      zero, 16(s9)
    addi    a0, sp, L + 16
    mv      a1, s5
    mv      a2, s6
    mv      a3, s9
    call    lantern_reqresp_write_chunk
    bnez    a0, 99b
    ld      t0, 16(s9)                      # the sizes of the list and the event
    addi    t0, t0, 24 + 7
    andi    t0, t0, -8
    sd      t0, 0(s9)
    addi    t0, t0, NodeEvent_chunk
    sd      t0, 0(s7)
    li      a0, LANTERN_OK
    LEAVE 192
60: li      t1, NODE_WORK_GOSSIP
    bne     t0, t1, 70f
    mv      a0, s2                          # GOSSIP: the fork of the store's slot; a head state of another: IGNORE
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    mv      s10, a0
    beqz    s4, 61f
    ld      a0, NODE_STATE_SLOT(s4)
    addi    a1, s1, Node_config
    call    node_fork
    bne     a0, s10, 69f
61: ld      t0, (L + 64)(sp)                # the inputs of the fork's node_gossip
    sd      t0, (L + 96 + NodeGossip_seen)(sp)
    sd      s2, (L + 96 + NodeGossip_store)(sp)
    ld      t0, Node_time_ms(s1)
    sd      t0, (L + 96 + NodeGossip_time_ms)(sp)
    ld      t0, NodeAction_arg(s3)
    andi    t1, t0, 255
    srli    t0, t0, 8
    sd      t1, (L + 96 + NodeGossip_topic)(sp)
    sd      t0, (L + 96 + NodeGossip_subnet)(sp)
    sd      s4, (L + 96 + NodeGossip_head)(sp)
    ld      s9, (L + 72)(sp)                # the proposer and justified states, 0 when of another fork
    beqz    s9, 62f
    ld      a0, NODE_STATE_SLOT(s9)
    addi    a1, s1, Node_config
    call    node_fork
    beq     a0, s10, 62f
    li      s9, 0
62: sd      s9, (L + 96 + NodeGossip_proposer)(sp)
    ld      s9, (L + 80)(sp)
    beqz    s9, 63f
    ld      a0, NODE_STATE_SLOT(s9)
    addi    a1, s1, Node_config
    call    node_fork
    beq     a0, s10, 63f
    li      s9, 0
63: sd      s9, (L + 96 + NodeGossip_justified)(sp)
    ld      t0, (L + 88)(sp)
    sd      t0, (L + 96 + NodeGossip_settings)(sp)
    addi    t0, s1, Node_config
    sd      t0, (L + 96 + NodeGossip_config)(sp)
    mv      t6, s10
    addi    a0, sp, L + 96
    mv      a1, s5
    mv      a2, s6
    addi    a3, s7, NodeEvent_result
    addi    a4, s7, NodeEvent_root
    addi    a5, s7, NodeEvent_index
    FORK_CALL node_gossip
    LEAVE 192
69: li      t0, LANTERN_GOSSIP_IGNORE
    sd      t0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    LEAVE 192
70: li      t1, NODE_WORK_SYNC_BLOCK
    bne     t0, t1, 80f
    ld      t0, 16(s5)                      # SYNC_BLOCK: node_block_root of the fork of its slot
    li      t1, 100 + 84
    bltu    t0, t1, 18b
    ld      t0, 8(s5)
    add     t0, s5, t0
    LDU64   a0, t0, 100, t1
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s5
    mv      a1, s6
    addi    a2, s7, NodeEvent_root
    addi    a3, s7, NodeEvent_result
    addi    a4, s7, NodeEvent_index
    FORK_CALL node_block_root
    LEAVE 192
80: li      t1, NODE_WORK_BLOB
    bne     t0, t1, 82f
    ld      t0, NodeAction_arg(s3)
    bnez    t0, 88f
    ld      t0, 16(s5)                      # BLOB: node_blob_sidecar of the fork of its slot, deneb or electra
    li      t1, NODE_BLOB_HEADER + 8
    bltu    t0, t1, 18b
    ld      t0, 8(s5)
    add     t0, s5, t0
    LDQ     a0, t0, NODE_BLOB_HEADER
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s5
    addi    a1, s1, Node_config
    ld      a2, (L + 88)(sp)
    mv      a3, s6
    addi    a4, s7, NodeEvent_result
    addi    a5, s7, NodeEvent_root
    li      t0, FORK_DENEB
    bne     t6, t0, 81f
    CALL_GLOBAL lantern_deneb_node_blob_sidecar
    LEAVE 192
81: li      t0, FORK_ELECTRA
    bne     t6, t0, 18b
    CALL_GLOBAL lantern_electra_node_blob_sidecar
    LEAVE 192
88: ld      t0, 16(s5)                      # arg 1: node_column_sidecar, of a slot of fulu
    li      t1, NODE_COLUMN_HEADER + 8
    bltu    t0, t1, 18b
    ld      t0, 8(s5)
    add     t0, s5, t0
    LDU64   a0, t0, NODE_COLUMN_HEADER, t1
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_FULU
    bne     a0, t0, 18b
    mv      a0, s5
    addi    a1, s1, Node_config
    ld      a2, (L + 88)(sp)
    mv      a3, s6
    addi    a4, s7, NodeEvent_result
    addi    a5, s7, NodeEvent_root
    CALL_GLOBAL lantern_fulu_node_column_sidecar
    LEAVE 192
82: li      t1, NODE_WORK_NEW_PAYLOAD
    bne     t0, t1, 83f
    ld      t0, 16(s5)                      # NEW_PAYLOAD: node_new_payload of the fork of the block's slot
    li      t1, 100 + 84
    bltu    t0, t1, 18b
    ld      t0, 8(s5)
    add     t0, s5, t0
    LDU64   a0, t0, 100, t1
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    li      t0, FORK_BELLATRIX
    bltu    t6, t0, 86f
    li      t0, NodeEvent_chunk + 24
    bltu    s8, t0, 7f
    addi    s9, s7, NodeEvent_chunk         # the request's ByteList after the WORK_DONE fields
    addi    t0, s8, -NodeEvent_chunk
    sd      t0, 0(s9)
    li      t0, 24
    sd      t0, 8(s9)
    sd      zero, 16(s9)
    mv      a0, s5
    mv      a1, s1
    addi    a2, s3, NodeAction_arg
    mv      a3, s6
    mv      a4, s9
    addi    a5, s7, NodeEvent_result
    FORK_CALL_BELLATRIX node_new_payload
    bnez    a0, 99b
    ld      t0, NodeEvent_result(s7)
    bnez    t0, 99b
    j       84f
83: li      t1, NODE_WORK_FORKCHOICE
    bne     t0, t1, 830f
    mv      a0, s2                          # FORKCHOICE: of the fork of the store's slot
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    mv      s10, a0
    li      t0, FORK_BELLATRIX
    bltu    s10, t0, 86f
    addi    a0, s1, Node_head_root          # the ForkchoiceState at L+96: head, safe (justified), finalized
    call    node_store_find
    li      t0, -1
    beq     a0, t0, 87f
    addi    t0, sp, L + 96
    addi    t1, a1, BlockNode_block_hash
    COPY32  t0, t1
    addi    a0, s2, Store_justified_checkpoint + 8
    call    node_store_find
    li      t0, -1
    beq     a0, t0, 87f
    addi    t0, sp, L + 128
    addi    t1, a1, BlockNode_block_hash
    COPY32  t0, t1
    addi    a0, s2, Store_finalized_checkpoint + 8
    call    node_store_find
    li      t0, -1
    beq     a0, t0, 87f
    addi    t0, sp, L + 160
    addi    t1, a1, BlockNode_block_hash
    COPY32  t0, t1
    ld      t0, (L + 96)(sp)                # a head of no payload: no call
    ld      t1, (L + 104)(sp)
    or      t0, t0, t1
    ld      t1, (L + 112)(sp)
    or      t0, t0, t1
    ld      t1, (L + 120)(sp)
    or      t0, t0, t1
    beqz    t0, 86f
    li      s5, 0                           # no payload attributes
    ld      s9, 0(s6)
    # The request of the ForkchoiceState at L+96 and the attributes s5 (or 0), with s9 the
    # scratch's size to give back. At the end of scratch: the JSON (536, or FCU_JSON_ATTRIBUTES
    # with attributes), the token (280), the host (88); L+8 the JSON's room.
831: li     t0, NodeEvent_chunk + 24
    bltu    s8, t0, 832f
    li      t1, 536
    beqz    s5, 8311f
    li      t1, FCU_JSON_ATTRIBUTES
8311: sd    t1, (L + 8)(sp)
    addi    t2, t1, 368
    ld      t0, 0(s6)
    addi    t3, t2, 512
    bltu    t0, t3, 832f
    sub     t0, t0, t2
    sd      t0, 0(s6)
    add     s4, s6, t0
    li      t3, 24
    sd      t1, 0(s4)
    sd      t3, 8(s4)
    sd      zero, 16(s4)
    add     t4, s4, t1                      # the token, then the host
    li      t0, 280
    sd      t0, 0(t4)
    sd      t3, 8(t4)
    sd      zero, 16(t4)
    li      t0, 88
    sd      t0, 280(t4)
    sd      t3, 288(t4)
    ld      a2, Node_engine_host_len(s1)
    sd      a2, 296(t4)
    addi    a0, t4, 280 + 24
    addi    a1, s1, Node_engine_host
    call    lantern_copy
    addi    a0, sp, L + 96
    mv      a1, s5
    addi    a2, s3, NodeAction_arg
    mv      a3, s4
    mv      t6, s10
    FORK_CALL_BELLATRIX engine_forkchoice_updated
    bnez    a0, 85f
    ld      t0, Node_time_ms(s1)            # the JWT at the time in seconds
    li      t1, 1000
    divu    t0, t0, t1
    sd      t0, L(sp)
    addi    a0, s1, Node_jwt_secret
    addi    a1, sp, L
    mv      a2, s6
    ld      a3, (L + 8)(sp)
    add     a3, s4, a3
    call    lantern_jwt_token
    bnez    a0, 85f
    addi    a3, s7, NodeEvent_chunk         # the HTTP request after the WORK_DONE fields
    addi    t0, s8, -NodeEvent_chunk
    sd      t0, 0(a3)
    li      t0, 24
    sd      t0, 8(a3)
    sd      zero, 16(a3)
    ld      a1, (L + 8)(sp)
    add     a1, s4, a1
    addi    a0, a1, 280
    mv      a2, s4
    call    lantern_http_post
    bnez    a0, 85f
    sd      s9, 0(s6)
    addi    s9, s7, NodeEvent_chunk
84: ld      t0, 16(s9)                      # the sizes of the list and the event
    addi    t0, t0, 24 + 7
    andi    t0, t0, -8
    sd      t0, 0(s9)
    addi    t0, t0, NodeEvent_chunk
    sd      t0, 0(s7)
    li      a0, LANTERN_OK
    LEAVE 192
85: sd      s9, 0(s6)                       # a status, with the scratch's size back
    LEAVE 192
832: sd     s9, 0(s6)                       # too little room, with the scratch's size back
    li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 192
86: li      t0, LANTERN_NO_PAYLOAD
    sd      t0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    LEAVE 192
87: li      t0, LANTERN_INVALID_UNKNOWN_BLOCK
    sd      t0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    LEAVE 192
830: li     t1, NODE_WORK_PREPARE_PAYLOAD
    bne     t0, t1, 890f
    beqz    s4, 837f                        # PREPARE_PAYLOAD: of the fork of the state's slot
    ld      a0, NODE_STATE_SLOT(s4)
    addi    a1, s1, Node_config
    call    node_fork
    mv      s10, a0
    li      t0, FORK_BELLATRIX
    bltu    s10, t0, 836f
    mv      a0, s4                          # the proposer: (state, out) in fulu, (state, scratch, out) before
    addi    a2, sp, L + 16
    mv      a1, s6
    li      t0, FORK_FULU
    bltu    s10, t0, 8301f
    mv      a1, a2
8301: mv    t6, s10
    FORK_CALL get_beacon_proposer_index
    bnez    a0, 838f
    ld      t1, (L + 16)(sp)
    sd      t1, NodeEvent_index(s7)
    ld      t0, NODE_STATE_SLOT(s4)         # its fee recipient: an entry past the state's epoch
    li      t2, SLOTS_PER_EPOCH
    divu    t0, t0, t2
    PART    t2, t3, s1, Node_proposers
833: beqz   t3, 8335f
    ld      t4, NodeProposer_validator_index(t2)
    bne     t4, t1, 8331f
    ld      t4, NodeProposer_until_epoch(t2)
    bgtu    t4, t0, 834f
8331: addi  t2, t2, NodeProposer__mem
    addi    t3, t3, -1
    j       833b
834: sd     t2, (L + 24)(sp)
    j       8336f
8335: ld    t0, NodeAction_target(s3)       # forced: a fee recipient of zero bytes, at L+40
    beqz    t0, 836f
    sd      zero, (L + 40)(sp)
    sd      zero, (L + 48)(sp)
    sd      zero, (L + 56)(sp)
    addi    t0, sp, (L + 24)
    sd      t0, (L + 24)(sp)
8336:
    ADDQ    a0, s1, Node_payload_root       # the ForkchoiceState: the parent hash, safe (justified), finalized
    call    node_store_find
    li      t0, -1
    beq     a0, t0, 839f
    addi    t0, sp, L + 96
    addi    t1, a1, BlockNode_block_hash
    COPY32  t0, t1
    addi    a0, s2, Store_justified_checkpoint + 8
    call    node_store_find
    li      t0, -1
    beq     a0, t0, 839f
    addi    t0, sp, L + 128
    addi    t1, a1, BlockNode_block_hash
    COPY32  t0, t1
    addi    a0, s2, Store_finalized_checkpoint + 8
    call    node_store_find
    li      t0, -1
    beq     a0, t0, 839f
    addi    t0, sp, L + 160
    addi    t1, a1, BlockNode_block_hash
    COPY32  t0, t1
    ld      t0, (L + 96)(sp)                # a parent of no payload: no call
    ld      t1, (L + 104)(sp)
    or      t0, t0, t1
    ld      t1, (L + 112)(sp)
    or      t0, t0, t1
    ld      t1, (L + 120)(sp)
    or      t0, t0, t1
    beqz    t0, 836f
    ld      s9, 0(s6)                       # the attributes at the end of scratch
    li      t0, PAYLOAD_ATTRIBUTES_ROOM + 512
    bltu    s9, t0, 832b
    li      t0, PAYLOAD_ATTRIBUTES_ROOM
    sub     t0, s9, t0
    sd      t0, 0(s6)
    add     s5, s6, t0
    mv      a0, s4
    ld      a1, (L + 24)(sp)
    addi    a1, a1, NodeProposer_fee_recipient
    addi    a2, s1, Node_config
    mv      a3, s6
    mv      a4, s5
    mv      t6, s10
    FORK_CALL_BELLATRIX get_payload_attributes
    beqz    a0, 831b
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 835f
    sd      s9, 0(s6)
838: sd     a0, NodeEvent_result(s7)        # a failed check: the result
    li      a0, LANTERN_OK
    LEAVE 192
836: li     t0, LANTERN_NO_PAYLOAD
    sd      t0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    LEAVE 192
837: li     a0, LANTERN_INVALID_EVENT
    LEAVE 192
835: sd     s9, 0(s6)                       # a status, with the scratch's size back
    LEAVE 192
839: li     t0, LANTERN_INVALID_UNKNOWN_BLOCK
    sd      t0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    LEAVE 192
890: li     t1, NODE_WORK_PRODUCE_CHECK
    bne     t0, t1, 8410f
    beqz    s4, 837b                        # PRODUCE_CHECK: lantern_node_produce_check of the request in the entry's cursor
    ld      a0, NODE_STATE_SLOT(s4)
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    ld      t0, NodeAction_target(s3)
    PART    t1, t2, s1, Node_api
    bgeu    t0, t2, 837b
    li      t2, NodeApi__mem
    mul     t0, t0, t2
    add     a1, t1, t0
    addi    a1, a1, NodeApi_cursor
    mv      a0, s4
    mv      a2, s6
    addi    a3, s7, NodeEvent_index
    FORK_CALL node_produce_check
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8401f
    sd      a0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
8401: LEAVE 192
8410: li    t1, NODE_WORK_GET_PAYLOAD
    bne     t0, t1, 8420f
    ld      t0, NodeAction_target(s3)       # GET_PAYLOAD: engine_getPayload of the fork of the entry's slot
    PART    t1, t2, s1, Node_api
    bgeu    t0, t2, 837b
    li      t2, NodeApi__mem
    mul     t0, t0, t2
    add     t0, t1, t0
    ld      a0, NodeApi_slot(t0)
    addi    a1, s1, Node_config
    call    node_fork
    mv      s10, a0
    li      t0, NodeEvent_chunk + 24
    bltu    s8, t0, 8419f
    ld      s9, 0(s6)                       # at the end of scratch: the JSON (536), the token (280), the host (88)
    li      t0, 904 + 512
    bltu    s9, t0, 8419f
    addi    t0, s9, -904
    sd      t0, 0(s6)
    add     s4, s6, t0
    li      t1, 24
    li      t0, 536
    sd      t0, 0(s4)
    sd      t1, 8(s4)
    sd      zero, 16(s4)
    li      t0, 280
    sd      t0, 536(s4)
    sd      t1, (536 + 8)(s4)
    sd      zero, (536 + 16)(s4)
    li      t0, 88
    sd      t0, 816(s4)
    sd      t1, (816 + 8)(s4)
    ld      a2, Node_engine_host_len(s1)
    sd      a2, (816 + 16)(s4)
    addi    a0, s4, (816 + 24)
    addi    a1, s1, Node_engine_host
    call    lantern_copy
    ADDQ    a0, s1, Node_payload_id
    addi    a1, s3, NodeAction_arg
    mv      a2, s4
    mv      t6, s10
    FORK_CALL_BELLATRIX engine_get_payload
    bnez    a0, 8418f
    ld      t0, Node_time_ms(s1)            # the JWT at the time in seconds
    li      t1, 1000
    divu    t0, t0, t1
    sd      t0, L(sp)
    addi    a0, s1, Node_jwt_secret
    addi    a1, sp, L
    mv      a2, s6
    addi    a3, s4, 536
    call    lantern_jwt_token
    bnez    a0, 8418f
    addi    a3, s7, NodeEvent_chunk         # the HTTP request after the WORK_DONE fields
    addi    t0, s8, -NodeEvent_chunk
    sd      t0, 0(a3)
    li      t0, 24
    sd      t0, 8(a3)
    sd      zero, 16(a3)
    addi    a0, s4, 816
    addi    a1, s4, 536
    mv      a2, s4
    call    lantern_http_post
    bnez    a0, 8418f
    sd      s9, 0(s6)
    j       8441f
8418: sd    s9, 0(s6)                       # a status, with the scratch's size back
    LEAVE 192
8419: li    a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 192
8420: li    t1, NODE_WORK_PRODUCE_FOLD
    bne     t0, t1, 8430f
    beqz    s4, 837b                        # PRODUCE_FOLD: lantern_node_produce_fold of the pool entry in state_b, into the draft in place
    ld      t0, (L + 72)(sp)
    beqz    t0, 837b
    beqz    s5, 837b
    ld      a0, NODE_STATE_SLOT(s4)
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s4
    ld      a1, (L + 72)(sp)
    mv      a2, s5
    ld      a3, NodeAction_arg(s3)
    mv      a4, s6
    FORK_CALL node_produce_fold
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8449f
    sd      a0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    LEAVE 192
8430: li    t1, NODE_WORK_PRODUCE_BLOCK
    bne     t0, t1, 8450f
    beqz    s4, 837b                        # PRODUCE_BLOCK: lantern_node_produce_block, as a ByteList at NodeEvent_chunk
    beqz    s5, 837b
    li      t0, NodeEvent_chunk + 24
    bltu    s8, t0, 8419b
    addi    t0, s7, NodeEvent_chunk
    addi    t1, s8, -NodeEvent_chunk
    sd      t1, 0(t0)
    li      t1, 24
    sd      t1, 8(t0)
    sd      zero, 16(t0)
    ld      t0, NodeAction_target(s3)       # the request: the entry's cursor
    PART    t1, t2, s1, Node_api
    bgeu    t0, t2, 837b
    li      t2, NodeApi__mem
    mul     t0, t0, t2
    add     t0, t1, t0
    addi    t0, t0, NodeApi_cursor
    sd      t0, (L + 96)(sp)                # ProduceParams at L+96: request, config, result, values
    addi    t0, s1, Node_config
    sd      t0, (L + 104)(sp)
    ld      t0, (L + 72)(sp)
    sd      t0, (L + 112)(sp)
    addi    t0, s7, NodeEvent_root
    sd      t0, (L + 120)(sp)
    addi    t0, s7, NodeEvent_index
    sd      t0, (L + 128)(sp)
    ld      a0, NODE_STATE_SLOT(s4)
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s4
    mv      a1, s5
    addi    a2, sp, (L + 96)
    mv      a3, s6
    addi    a4, s7, NodeEvent_chunk
    FORK_CALL node_produce_block
8440: li    t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8449f
    beqz    a0, 8441f
    sd      a0, NodeEvent_result(s7)        # a failed check: the result, no bytes
    li      a0, LANTERN_OK
    LEAVE 192
8441: addi  t1, s7, NodeEvent_chunk         # the sizes of the list and the event
    ld      t0, 16(t1)
    addi    t0, t0, 24 + 7
    andi    t0, t0, -8
    sd      t0, 0(t1)
    addi    t0, t0, NodeEvent_chunk
    sd      t0, 0(s7)
    li      a0, LANTERN_OK
8449: LEAVE 192
8450: li    t1, NODE_WORK_PUBLISH_DECODE
    bne     t0, t1, 8460f
    beqz    s5, 837b                        # PUBLISH_DECODE: lantern_node_publish_decode, the block as a ByteList at NodeEvent_chunk
    li      t0, NodeEvent_chunk + 24
    bltu    s8, t0, 8419b
    addi    t0, s7, NodeEvent_chunk
    addi    t1, s8, -NodeEvent_chunk
    sd      t1, 0(t0)
    li      t1, 24
    sd      t1, 8(t0)
    sd      zero, 16(t0)
    ld      t0, NodeAction_arg(s3)
    andi    t6, t0, 255
    srli    t0, t0, 8
    andi    t0, t0, 1
    xori    a1, t0, 1                       # JSON without the SSZ bit
    mv      a0, s5
    mv      a2, s6
    addi    a3, s7, NodeEvent_chunk
    addi    a4, sp, (L + 96)                # facts: the slot, the blob count, 0
    FORK_CALL node_publish_decode
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8449b
    bnez    a0, 8458f
    ld      t0, (L + 96)(sp)
    sd      t0, NodeEvent_index(s7)
    ld      t0, (L + 104)(sp)
    sd      t0, NodeEvent_checkpoint(s7)
    ld      t0, NodeAction_arg(s3)          # its root
    andi    t6, t0, 255
    addi    a0, s7, NodeEvent_chunk
    mv      a1, s6
    addi    a2, s7, NodeEvent_root
    addi    a3, sp, (L + 112)
    addi    a4, sp, (L + 120)
    FORK_CALL node_block_root
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8449b
    bnez    a0, 8458f
    ld      a0, (L + 112)(sp)
    beqz    a0, 8441b
8458: sd    a0, NodeEvent_result(s7)        # a failed check: the result, no bytes
    li      a0, LANTERN_OK
    LEAVE 192
8460: li    t1, NODE_WORK_PUBLISH_CHECK
    bne     t0, t1, 8470f
    beqz    s4, 837b                        # PUBLISH_CHECK: lantern_node_publish_check, then the block's bytes at NodeEvent_chunk
    beqz    s5, 837b
    ld      t1, (L + 80)(sp)
    beqz    t1, 837b
    ld      t0, 16(s5)
    addi    t0, t0, NodeEvent_chunk + 24 + 7
    bltu    s8, t0, 8419b
    ld      t0, (L + 64)(sp)                # a NodeGossip at L+96: seen, store, time_ms, topic, subnet,
    sd      t0, (L + 96)(sp)                # head, proposer, justified, settings, config
    sd      s2, (L + 104)(sp)
    ld      t0, Node_time_ms(s1)
    sd      t0, (L + 112)(sp)
    sd      zero, (L + 120)(sp)
    sd      zero, (L + 128)(sp)
    sd      t1, (L + 136)(sp)
    sd      s4, (L + 144)(sp)
    sd      zero, (L + 152)(sp)
    ld      t0, (L + 88)(sp)
    sd      t0, (L + 160)(sp)
    addi    t0, s1, Node_config
    sd      t0, (L + 168)(sp)
    ld      a0, NODE_STATE_SLOT(s4)
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    addi    a0, sp, (L + 96)
    mv      a1, s5
    ld      a2, (L + 72)(sp)
    ld      a3, NodeAction_arg(s3)
    mv      a4, s6
    FORK_CALL node_publish_check
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8449b
    bnez    a0, 8458b
    addi    t0, s7, NodeEvent_chunk         # the block's bytes
    addi    t1, s8, -NodeEvent_chunk
    sd      t1, 0(t0)
    li      t1, 24
    sd      t1, 8(t0)
    ld      a2, 16(s5)
    sd      a2, 16(t0)
    addi    a0, t0, 24
    ld      t1, 8(s5)
    add     a1, s5, t1
    call    lantern_copy
    j       8441b
8470: li    t1, NODE_WORK_PUBLISH_SIDECARS
    bne     t0, t1, 8480f
    beqz    s5, 837b                        # PUBLISH_SIDECARS: lantern_node_publish_sidecars of the fork arg & 255, into state_b
    ld      a3, (L + 72)(sp)
    beqz    a3, 837b
    ld      t0, NodeAction_arg(s3)
    andi    t6, t0, 255
    srli    t0, t0, 8
    andi    t0, t0, 1
    xori    a1, t0, 1                       # JSON without the SSZ bit
    mv      a0, s5
    mv      a2, s6
    li      t1, FORK_DENEB
    bltu    t6, t1, 837b
    li      t1, FORK_ELECTRA
    bgeu    t6, t1, 8471f
    CALL_GLOBAL lantern_deneb_node_publish_sidecars
    j       8473f
8471: li    t1, FORK_FULU
    bgeu    t6, t1, 8472f
    CALL_GLOBAL lantern_electra_node_publish_sidecars
    j       8473f
8472: CALL_GLOBAL lantern_fulu_node_publish_sidecars
8473: li    t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8449b
    bnez    a0, 8458b
    LEAVE 192
8480: li    t1, NODE_WORK_PUBLISH_SIDECAR
    bne     t0, t1, 8490f
    ld      t2, (L + 72)(sp)                # PUBLISH_SIDECAR: the sidecar arg of state_b, as a ByteList at NodeEvent_chunk
    beqz    t2, 837b
    ld      t3, NodeAction_arg(s3)
    ld      t4, 8(t2)
    add     t4, t2, t4                      # the first sidecar's ByteList
    ld      t5, 16(t2)
    add     t5, t4, t5                      # their end
8481: bgeu  t4, t5, 8483f
    beqz    t3, 8482f
    ld      t0, 0(t4)
    add     t4, t4, t0
    addi    t3, t3, -1
    j       8481b
8482: ld    s9, 16(t4)                      # its length
    addi    t0, s9, NodeEvent_chunk + 24 + 7
    bltu    s8, t0, 8419b
    sd      t4, (L + 96)(sp)
    ld      t0, NodeAction_target(s3)       # its block's root and slot: the entry's
    PART    t1, t2, s1, Node_api
    bgeu    t0, t2, 837b
    li      t2, NodeApi__mem
    mul     t0, t0, t2
    add     t1, t1, t0
    addi    a0, s7, NodeEvent_root
    addi    a1, t1, NodeApi_root
    COPY32  a0, a1
    ld      t0, NodeApi_slot(t1)
    sd      t0, NodeEvent_checkpoint(s7)
    ld      t4, (L + 96)(sp)
    ld      t0, 8(t4)                       # its index: the u64 at byte 0 of its bytes
    add     t0, t4, t0
    ld      t0, 0(t0)
    sd      t0, NodeEvent_index(s7)
    addi    t0, s7, NodeEvent_chunk         # its bytes as a ByteList
    addi    t1, s8, -NodeEvent_chunk
    sd      t1, 0(t0)
    li      t1, 24
    sd      t1, 8(t0)
    sd      s9, 16(t0)
    addi    a0, t0, 24
    ld      t1, 8(t4)
    add     a1, t4, t1
    mv      a2, s9
    call    lantern_copy
    j       8441b
8483: li    a0, LANTERN_INVALID_EVENT       # past the last
    j       8458b
8490:
89: li      t1, NODE_WORK_SLOTS
    bne     t0, t1, 90f
    ld      a0, NODE_STATE_SLOT(s4)         # SLOTS: process_slots of the fork of the state's slot, to arg
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s4
    addi    a1, s3, NodeAction_arg
    addi    a2, s1, Node_config
    mv      a3, s6
    addi    a4, s7, NodeEvent_result
    FORK_CALL process_slots
    LEAVE 192
90: li      t1, NODE_WORK_UPGRADE
    bne     t0, t1, 97f
    ld      t6, NodeAction_arg(s3)          # UPGRADE: node_upgrade of the fork arg, of a state at its first slot
    li      t1, FORK_ALTAIR
    bltu    t6, t1, 19b
    li      t1, FORK_FULU
    bgtu    t6, t1, 19b
    slli    t1, t6, 4
    add     t1, s1, t1
    ld      t1, Node_config(t1)
    li      t2, SLOTS_PER_EPOCH
    mulhu   t3, t1, t2
    bnez    t3, 19b
    mul     t1, t1, t2
    ld      t2, NODE_STATE_SLOT(s4)
    bne     t1, t2, 19b
    mv      a0, s4
    ADDRESS a1, node_upgrade_room
    addi    a2, s1, Node_config
    mv      a3, s6
    ld      a4, (L + 72)(sp)
    FORK_CALL node_upgrade
    LEAVE 192
97: li      t1, NODE_WORK_REPLAY
    bne     t0, t1, 971f
    ld      t0, 16(s5)                      # REPLAY: node_replay of the fork of the block's slot, of a state of that fork
    li      t1, 100 + 84
    bltu    t0, t1, 18b
    ld      t0, 8(s5)
    add     t0, s5, t0
    LDU64   a0, t0, 100, t1
    addi    a1, s1, Node_config
    call    node_fork
    mv      s10, a0
    ld      a0, NODE_STATE_SLOT(s4)
    addi    a1, s1, Node_config
    call    node_fork
    bne     a0, s10, 19b
    mv      t6, s10
    mv      a0, s5
    mv      a1, s4
    addi    a2, s1, Node_config
    mv      a3, s6
    addi    a4, s7, NodeEvent_result
    FORK_CALL node_replay
    LEAVE 192
971: li     t1, NODE_WORK_BLOCK_ATTESTATION
    beq     t0, t1, 975f
    li      t1, NODE_WORK_GOSSIP_VOTE
    beq     t0, t1, 975f
    li      t1, NODE_WORK_BLOCK_SLASHING
    bne     t0, t1, 974f
975: mv     a0, t0                          # BLOCK_ATTESTATION, BLOCK_SLASHING
    call    node_run_vote
    LEAVE 192
974: li     t1, NODE_WORK_BACKFILL
    bne     t0, t1, 975f
    ld      t0, 16(s5)                      # BACKFILL: its root, then the signature with state_a
    li      t1, 100 + 84
    bltu    t0, t1, 18b
    beqz    s4, 19b
    mv      a0, s5
    mv      a1, s4
    mv      a2, s6
    mv      a3, s7
    call    node_run_backfill
    LEAVE 192
975: li     t1, NODE_WORK_API_ENCODE
    bne     t0, t1, 976f
    mv      a0, s1                          # API_ENCODE: the response of an answer
    mv      a1, s2
    mv      a2, s3
    mv      a3, s4
    mv      a4, s5
    mv      a5, s6
    mv      a6, s7
    mv      a7, s8
    call    node_api_run
    LEAVE 192
976: li     t1, NODE_WORK_API_CHUNK
    bne     t0, t1, 977f
    mv      a0, s1                          # API_CHUNK: the next chunk of a stream
    mv      a1, s3
    mv      a2, s5
    mv      a3, s6
    mv      a4, s7
    mv      a5, s8
    mv      a6, s4
    call    node_api_chunk_run
    LEAVE 192
977: li     t1, NODE_WORK_API_EVENT
    bne     t0, t1, 978f
    mv      a0, s1                          # API_EVENT: the text of an event
    mv      a1, s3
    mv      a2, s4
    mv      a3, s5
    mv      a4, s6
    mv      a5, s7
    mv      a6, s8
    call    node_api_event_run
    LEAVE 192
978: li     t1, NODE_WORK_API_SUBMIT
    bne     t0, t1, 979f
    mv      a0, s1                          # API_SUBMIT: the operations of a body, checked
    mv      a1, s2
    ld      a2, (L + 64)(sp)
    mv      a3, s3
    mv      a4, s4
    mv      a5, s5
    mv      a6, s6
    mv      a7, s7
    mv      t0, s8
    call    node_api_submit_run
    LEAVE 192
979: li     t1, NODE_WORK_POOL_CHECK
    bne     t0, t1, 9780f
    beqz    s4, 8f                          # POOL_CHECK: the gossip validation of the bytes, with an empty Seen
    beqz    s5, 8f
    ld      t0, NodeAction_arg(s3)
    li      t1, GOSSIP_VOLUNTARY_EXIT
    beq     t0, t1, 9785f
    li      t1, GOSSIP_PROPOSER_SLASHING
    beq     t0, t1, 9785f
    li      t1, GOSSIP_ATTESTER_SLASHING
    beq     t0, t1, 9785f
    li      t1, GOSSIP_BLS_TO_EXECUTION_CHANGE
    bne     t0, t1, 8f
9785: ld    t0, 16(s5)                      # its SeenRoom: a key for each 8 bytes, and 1
    srli    t0, t0, 3
    addi    t0, t0, 1
    sd      t0, (L + 16)(sp)
    sd      zero, (L + 24)(sp)
    sd      zero, (L + 32)(sp)
    sd      zero, (L + 40)(sp)
    addi    a0, sp, L + 16
    addi    a1, sp, L
    call    lantern_seen_size
    bnez    a0, 9781f
    ld      t0, 0(s6)                       # the Seen at the end of scratch, with LANTERN_SCRATCH_FIXED before it
    sd      t0, (L + 8)(sp)
    ld      t1, (L)(sp)
    bltu    t0, t1, 9781f
    sub     t0, t0, t1
    li      t2, LANTERN_SCRATCH_FIXED + 8
    bltu    t0, t2, 9781f
    andi    t0, t0, -8
    sd      t0, 0(s6)
    add     s9, s6, t0
    sd      t1, 0(s9)
    addi    a0, sp, L + 16
    mv      a1, s9
    call    lantern_seen_init
    bnez    a0, 9782f
    mv      a0, s2
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    mv      s10, a0
    ld      a0, NODE_STATE_SLOT(s4)         # a head state of another fork: IGNORE, as for gossip
    addi    a1, s1, Node_config
    call    node_fork
    bne     a0, s10, 9782f
    sd      s9, (L + 96 + NodeGossip_seen)(sp)
    sd      s2, (L + 96 + NodeGossip_store)(sp)
    ld      t0, Node_time_ms(s1)
    sd      t0, (L + 96 + NodeGossip_time_ms)(sp)
    ld      t0, NodeAction_arg(s3)
    sd      t0, (L + 96 + NodeGossip_topic)(sp)
    sd      zero, (L + 96 + NodeGossip_subnet)(sp)
    sd      s4, (L + 96 + NodeGossip_head)(sp)
    sd      zero, (L + 96 + NodeGossip_proposer)(sp)
    sd      zero, (L + 96 + NodeGossip_justified)(sp)
    sd      zero, (L + 96 + NodeGossip_settings)(sp)
    addi    t0, s1, Node_config
    sd      t0, (L + 96 + NodeGossip_config)(sp)
    mv      t6, s10
    addi    a0, sp, L + 96
    mv      a1, s5
    mv      a2, s6
    addi    a3, s7, NodeEvent_result
    addi    a4, s7, NodeEvent_root
    addi    a5, s7, NodeEvent_index
    FORK_CALL node_gossip
    ld      t0, (L + 8)(sp)                 # scratch whole again; a short one: IGNORE
    sd      t0, 0(s6)
    beqz    a0, 9783f
    li      t0, LANTERN_BUFFER_TOO_SMALL
    bne     a0, t0, 9784f
    j       9781f
9782: ld    t0, (L + 8)(sp)
    sd      t0, 0(s6)
9781: li    t0, LANTERN_GOSSIP_IGNORE
    sd      t0, NodeEvent_result(s7)
9783: li    a0, LANTERN_OK
9784: LEAVE 192
9780: ld    t0, NodeAction_work_kind(s3)
    li      t1, NODE_WORK_API_LOOKUP
    bne     t0, t1, 8f
    mv      a0, s1                          # API_LOOKUP: the slot of a state root
    mv      a1, s3
    mv      a2, s4
    mv      a3, s6
    mv      a4, s7
    call    node_api_lookup_run
    LEAVE 192
8:  li      a0, LANTERN_INVALID_EVENT
    LEAVE 192
7:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 192
END_FUNCTION lantern_node_run

/* L0: the counts of the votes of the block in data a0, at NodeEvent_index and NodeEvent_root of the event a1. Locals: sp+0 data, sp+8 event. */
LOCAL_FUNCTION node_vote_counts
    FRAME 16
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    li      a1, 1
    li      a2, -1
    call    node_body_item
    li      t0, -1
    bne     a0, t0, 1f
    li      a0, 0
1:  ld      t1, 8(sp)
    sd      a0, NodeEvent_index(t1)
    ld      a0, 0(sp)
    li      a1, 0
    li      a2, -1
    call    node_body_item
    li      t0, -1
    bne     a0, t0, 2f
    li      a0, 0
2:  ld      t1, 8(sp)
    sd      a0, NodeEvent_root(t1)
    UNFRAME 16
END_FUNCTION node_vote_counts

/*
 * L1: the BLOCK_ATTESTATION or BLOCK_SLASHING work a0 of lantern_node_run (node.md): the item at
 * index arg of the block's body, as a ByteList at the end of scratch, then node_attestation with
 * is_from_block 1 of the fork of its slot, or node_attester_slashing of the fork of the store's
 * slot. The run's s1 node, s2 store, s3 work, s4 state_a, s5 data, s6 scratch, s7 event. s8 the
 * kind, s9 the scratch size, s10 the ByteList. Locals: L is_from_block, L+8 a fork.
 */
LOCAL_FUNCTION node_run_vote
    ENTER 16
    mv      s8, a0
    ld      s9, 0(s6)
    li      t0, NODE_WORK_GOSSIP_VOTE
    bne     s8, t0, 1f
    mv      a0, s5                          # GOSSIP_VOTE: the aggregate
    call    node_aggregate
    bnez    a0, 7f
    j       2f
1:  li      t0, NODE_WORK_BLOCK_ATTESTATION
    sub     t0, s8, t0
    seqz    a1, t0
    mv      a0, s5
    ld      a2, NodeAction_arg(s3)
    call    node_body_item
2:  beqz    a2, 7f
    addi    t0, a2, 24 + 7                  # the ByteList at the end of scratch
    andi    t0, t0, -8
    bltu    s9, t0, 8f
    sub     t1, s9, t0
    sd      t1, 0(s6)
    add     s10, s6, t1
    sd      t0, 0(s10)
    li      t2, 24
    sd      t2, 8(s10)
    sd      a2, 16(s10)
    addi    a0, s10, 24
    call    lantern_copy
    li      t0, NODE_WORK_BLOCK_SLASHING
    beq     s8, t0, 3f
    ld      t0, 16(s10)                     # ATTESTATION: the fork of its slot
    li      t1, 4 + 128 + 96
    bltu    t0, t1, 61f
    LDU64   a0, s10, 24 + 4, t1
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    li      t0, NODE_WORK_BLOCK_ATTESTATION # is_from_block: 1 for a block's, 0 for an aggregate's
    sub     t0, s8, t0
    seqz    t0, t0
    sd      t0, L(sp)
    mv      a0, s2
    mv      a1, s10
    addi    a2, sp, L
    mv      a3, s4
    mv      a4, s6
    addi    a5, s7, NodeEvent_result
    addi    a6, s7, NodeEvent_checkpoint
    FORK_CALL node_attestation
    j       9f
3:  mv      a0, s2                          # SLASHING: the fork of the store's slot, a state of it
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    sd      a0, (L + 8)(sp)
    beqz    s4, 4f
    ld      a0, NODE_STATE_SLOT(s4)
    addi    a1, s1, Node_config
    call    node_fork
    ld      t0, (L + 8)(sp)
    bne     a0, t0, 62f
4:  ld      t6, (L + 8)(sp)
    mv      a0, s2
    mv      a1, s10
    mv      a2, s4
    mv      a3, s6
    addi    a4, s7, NodeEvent_result
    FORK_CALL node_attester_slashing
    j       9f
61: li      t0, LANTERN_INVALID_ENCODING
    sd      t0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    j       9f
62: li      t0, LANTERN_GOSSIP_IGNORE
    sd      t0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    j       9f
7:  li      t0, LANTERN_INVALID_ENCODING    # no such item
    sd      t0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    LEAVE 16
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
9:  sd      s9, 0(s6)
    LEAVE 16
END_FUNCTION node_run_vote

/*
 * L0: the BACKFILL work (node.md): node_block_root of the fork of the block's slot of data a0, its
 * root at NodeEvent_root of the event a3; then, for LANTERN_VALID, node_backfill of the fork of the
 * slot of the state a1, with scratch a2. s3 data, s4 state, s5 scratch, s6 event. Apart from
 * lantern_node_run, as FORK_CALL takes the labels 81 to 89.
 */
LOCAL_FUNCTION node_run_backfill
    ENTER 0
    mv      s3, a0
    mv      s4, a1
    mv      s5, a2
    mv      s6, a3
    ld      t0, 8(s3)
    add     t0, s3, t0
    LDU64   a0, t0, 100, t1
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s3
    mv      a1, s5
    addi    a2, s6, NodeEvent_root
    addi    a3, s6, NodeEvent_result
    addi    a4, s6, NodeEvent_index
    FORK_CALL node_block_root
    bnez    a0, 1f
    ld      t0, NodeEvent_result(s6)
    bnez    t0, 1f
    ld      a0, NODE_STATE_SLOT(s4)
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s3
    mv      a1, s4
    addi    a2, s1, Node_config
    addi    a3, s6, NodeEvent_root
    mv      a4, s5
    addi    a5, s6, NodeEvent_result
    FORK_CALL node_backfill
1:  LEAVE 0
END_FUNCTION node_run_backfill
