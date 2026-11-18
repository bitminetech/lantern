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

/* Call lantern_<fork>_<name> for the fork in t6 (FORK_PHASE0 to FORK_FULU). Uses t5. */
.macro FORK_CALL name
    li      t5, FORK_ALTAIR
    bgeu    t6, t5, 81f
    CALL_GLOBAL lantern_phase0_\name
    j       89f
81: li      t5, FORK_BELLATRIX
    bgeu    t6, t5, 82f
    CALL_GLOBAL lantern_altair_\name
    j       89f
82: li      t5, FORK_CAPELLA
    bgeu    t6, t5, 83f
    CALL_GLOBAL lantern_bellatrix_\name
    j       89f
83: li      t5, FORK_DENEB
    bgeu    t6, t5, 84f
    CALL_GLOBAL lantern_capella_\name
    j       89f
84: li      t5, FORK_ELECTRA
    bgeu    t6, t5, 85f
    CALL_GLOBAL lantern_deneb_\name
    j       89f
85: li      t5, FORK_FULU
    bgeu    t6, t5, 86f
    CALL_GLOBAL lantern_electra_\name
    j       89f
86: CALL_GLOBAL lantern_fulu_\name
89:
.endm

/* dst = 32 bytes at src, a 4-aligned address. Uses a6, a7. */
.macro COPY32W dst, src
    lw      a6, 0(\src)
    lw      a7, 4(\src)
    sw      a6, 0(\dst)
    sw      a7, 4(\dst)
    lw      a6, 8(\src)
    lw      a7, 12(\src)
    sw      a6, 8(\dst)
    sw      a7, 12(\dst)
    lw      a6, 16(\src)
    lw      a7, 20(\src)
    sw      a6, 16(\dst)
    sw      a7, 20(\dst)
    lw      a6, 24(\src)
    lw      a7, 28(\src)
    sw      a6, 24(\dst)
    sw      a7, 28(\dst)
.endm

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
    ld      t0, NodeRoom_p2p_out(a0)        # a ByteList
    addi    t1, t0, 24 + 7
    bltu    t1, t0, 9f
    andi    t1, t1, -8
    add     t0, t3, t1
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
    sd      t0, Node_\part(a0)
    sd      zero, (Node_\part + 8)(a0)
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
    sd      t0, Node_p2p_out(a0)            # one ByteList, empty
    li      t1, 1
    sd      t1, (Node_p2p_out + 8)(a0)
    ld      t1, NodeRoom_p2p_out(a1)
    addi    t1, t1, 24 + 7
    andi    t1, t1, -8
    add     t2, a0, t0
    sd      t1, 0(t2)
    li      t1, 24
    sd      t1, 8(t2)
    sd      zero, 16(t2)
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
    addi    t0, s6, Node_genesis_validators_root
    addi    t1, s3, NodeAnchor_genesis_validators_root
    COPY32  t0, t1
    addi    a0, s6, Node_config
    mv      a1, s2
    li      a2, CONFIG_SIZE
    call    lantern_copy
    mv      a0, s6
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
    li      a0, LANTERN_OK
9:  LEAVE 16
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_node_init

/* Copy the entries of the part at ref of the node s1, of width bytes each, into the node s3. */
.macro NODE_COPY_PART ref, width
    PART    a1, a2, s1, \ref
    sd      a2, ((\ref) + 8)(s3)
    li      t0, \width
    mul     a2, a2, t0
    ld      a0, (\ref)(s3)
    add     a0, s3, a0
    call    lantern_copy
.endm

/* Branch to 8f when the room s2 field is below the entries of the part at ref of the node s1. Uses t0, t1. */
.macro NODE_COPY_ROOM field, ref
    ld      t0, NodeRoom_\field(s2)
    ld      t1, ((\ref) + 8)(s1)
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
    ld      t0, NodeRoom_p2p_out(s2)        # the queued bytes fit
    ld      t1, Node_p2p_out(s1)
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
    NODE_COPY_PART Node_blocks, NodeBlock__mem      # the entries of each part
    NODE_COPY_PART Node_checkpoints, NodeCheckpoint__mem
    NODE_COPY_PART Node_pow_blocks, POW_BLOCK_BYTES
    NODE_COPY_PART Node_peers, NodePeer__mem
    NODE_COPY_PART Node_messages, NodeMessage__mem
    NODE_COPY_PART Node_blobs, NodeBlob__mem
    ld      a1, Node_p2p_out(s1)            # the queued bytes
    add     a1, s1, a1
    ld      a2, 16(a1)
    ld      a0, Node_p2p_out(s3)
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
    ld      t0, 8(s6)
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

/* An action of kind a0 with the two ids a1 and a2 (STATE_COPY: source, new; the FREE kinds: a1). Uses t0-t2. */
LOCAL_FUNCTION node_ids
    UNWIND_END_PROLOGUE
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
    ld      s8, NodeBlock_state_id(a1)
    call    node_new_id
    mv      s7, a0
    li      a0, NODE_ACT_STATE_COPY
    mv      a1, s8
    mv      a2, s7
    call    node_ids
    PART    t0, t1, s1, Node_checkpoints    # the entry
    li      t2, NodeCheckpoint__mem
    mul     t2, t1, t2
    add     t0, t0, t2
    sd      s3, NodeCheckpoint_epoch(t0)
    addi    t2, t0, NodeCheckpoint_root
    COPY32  t2, s4
    sd      s7, NodeCheckpoint_state_id(t0)
    addi    t2, t1, 1
    sd      t2, (Node_checkpoints + 8)(s1)
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
 * The import of the block of index a0 when its parent has a post-state: a copy of it and an
 * IMPORT_BLOCK work; a block whose parent is invalid becomes invalid. s3 index, s4 entry,
 * s8 the parent's state id.
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
    ld      s8, NodeBlock_state_id(a1)
    call    node_new_id
    sd      a0, NodeBlock_state_id(s4)
    mv      a2, a0
    li      a0, NODE_ACT_STATE_COPY
    mv      a1, s8
    call    node_ids
    li      t0, NODE_BLOCK_IMPORTING
    sd      t0, NodeBlock_status(s4)
    li      a0, NODE_WORK_IMPORT_BLOCK
    ld      a1, NodeBlock_state_id(s4)
    li      a2, 0
    ld      a3, NodeBlock_data_id(s4)
    mv      a4, s3
    li      a5, 0
    call    node_work
    LEAVE 0
8:  li      t0, NODE_BLOCK_INVALID
    sd      t0, NodeBlock_status(s4)
9:  LEAVE 0
END_FUNCTION node_try_import

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

/* a0 = 1 when the node holds a NODE_BLOB_VALID entry of the root at a0 (8-aligned) and the index a1, else 0. Uses t0-t3, a6, a7. */
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
    li      a0, 1
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

/*
 * The block of index a0, from the network, waits for its blobs: NODE_BLOCK_BLOBS while it needs
 * blobs the node does not hold; else data_available 1, NODE_BLOCK_WAITING and its import. It
 * needs blobs when its fork is deneb or electra, its blob count is 1 to the fork's limit and
 * NODE_BLOB_MAX, and its epoch is from max(the store's epoch - MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS,
 * DENEB_FORK_EPOCH) on. s3 the index, s4 the entry, s7 the count.
 */
LOCAL_FUNCTION node_await
    ENTER 0
    mv      s3, a0
    PART    s4, t0, s1, Node_blocks
    li      t0, NodeBlock__mem
    mul     t0, s3, t0
    add     s4, s4, t0
    ld      s7, NodeBlock_blobs(s4)
    beqz    s7, 5f
    li      t0, NODE_BLOB_MAX
    bgtu    s7, t0, 5f
    ld      a0, NodeBlock_slot(s4)
    addi    a1, s1, Node_config
    call    node_fork
    LDQ     t1, s1, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK
    li      t0, FORK_DENEB
    beq     a0, t0, 2f
    li      t0, FORK_ELECTRA
    bne     a0, t0, 5f
    LDQ     t1, s1, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
2:  bgtu    s7, t1, 5f
    mv      a0, s2                          # the blob window
    call    node_store_slot
    li      t0, SLOTS_PER_EPOCH
    divu    a0, a0, t0
    LDQ     t1, s1, Node_config + CONFIG_MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS
    sub     t2, a0, t1
    sltu    t3, a0, t1
    addi    t3, t3, -1
    and     a0, t2, t3
    LDQ     t1, s1, Node_config + 16 * FORK_DENEB
    bgeu    a0, t1, 3f
    mv      a0, t1
3:  ld      t2, NodeBlock_slot(s4)
    li      t0, SLOTS_PER_EPOCH
    divu    t2, t2, t0
    bltu    t2, a0, 5f
    mv      a0, s4
    mv      a1, s7
    call    node_blobs_held
    bnez    a0, 5f
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
    COPY32  t0, t1
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
    PART    t0, t1, s1, Node_blocks
    sd      t1, (L + 40)(sp)
    li      t2, NodeBlock__mem
    mul     t2, t1, t2
    add     t0, t0, t2
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
    addi    t1, t1, 1
    sd      t1, (Node_blocks + 8)(s1)
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
    bne     t0, t1, 50f
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
50: ld      t0, NodeAction_work_kind(s3)    # WORK_DONE
    ld      t1, NodeEvent_result(s3)
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
    li      t0, NODE_BLOCK_IMPORTED         # imported: then its waiting children
    sd      t0, NodeBlock_status(s4)
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
62: li      t2, NODE_WORK_SERVE             # SERVE: the chunk to its stream, then the next block or the close
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
    ld      t0, NodeMessage_topic(s4)
    li      t1, GOSSIP_ATTESTER_SLASHING
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
    PART    t0, t1, s1, Node_blocks
    sd      t1, (L + 40)(sp)
    li      t2, NodeBlock__mem
    mul     t2, t1, t2
    add     t0, t0, t2
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
    addi    t1, t1, 1
    sd      t1, (Node_blocks + 8)(s1)
    mv      a0, s4
    call    node_drop_message
    ld      a0, (L + 40)(sp)
    call    node_await
    LEAVE 48
642: li     t1, GOSSIP_BLOB_SIDECAR         # a new valid sidecar keeps the bytes
    bne     t0, t1, 65f
    addi    a0, s3, NodeEvent_root
    ld      a1, NodeEvent_index(s3)
    call    node_blob_held
    bnez    a0, 65f
    PART    t0, t1, s1, Node_blobs
    li      t2, NodeBlob__mem
    mul     t2, t1, t2
    add     t0, t0, t2
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
    addi    t1, t1, 1
    sd      t1, (Node_blobs + 8)(s1)
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
75: li      t2, NODE_WORK_SYNC_BLOCK        # SYNC_BLOCK: the root of a block of a response
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
    LEAVE 48
77: li      t2, NODE_WORK_BLOB              # BLOB: a sidecar of a response, checked
    bne     t0, t2, 70f
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
    addi    a0, s3, NodeEvent_root          # valid, and not held yet: the entry takes the root
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
 * The request of the stream entry a0, when its bytes are all there: Status, Ping and MetaData
 * get their answer, Goodbye a close; other methods get ResourceUnavailable. s3 entry, s4 method,
 * s7 the request's size, s8 the scratch size, s9 the payload, s10 a peer or a slot.
 * Locals: L a ChunkHeader, L+48 consumed or an epoch, L+56 a length or a fork digest, L+64 eof
 * or a payload (96).
 */
LOCAL_FUNCTION node_request
    ENTER 176
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
    ld      t0, (L + ChunkHeader_length)(sp)        # by root
    andi    t0, t0, 31
    bnez    t0, 90f
    call    node_max_blocks
    slli    a0, a0, 5
    ld      t0, (L + ChunkHeader_length)(sp)
    bgtu    t0, a0, 90f
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
    li      t0, REQRESP_GOODBYE
    bne     s4, t0, 10f
    li      a0, LIBP2P_EVENT_STREAM_CLOSE   # Goodbye: a close
    ld      a1, NodeStream_handle(s3)
    call    node_out_handle
    mv      a0, s3
    call    node_drop_stream
    LEAVE 176
10: li      t0, REQRESP_PING
    bne     s4, t0, 20f
    ld      t0, Node_metadata_seq(s1)       # Ping: our seq_number
    sd      t0, (L + 64)(sp)
    mv      a0, s3
    li      a1, 0
    addi    a2, sp, L + 64
    li      a3, 8
    call    node_respond
    LEAVE 176
20: ld      a0, NodeStream_peer(s3)         # Status: the peer's, then ours
    mv      a1, s9
    mv      a2, s7
    call    node_peer_status
    mv      a0, s2                          # ForkDigest of the store's epoch
    call    node_store_slot
    mv      s10, a0
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    li      t0, SLOTS_PER_EPOCH
    divu    t0, s10, t0
    sd      t0, (L + 48)(sp)
    addi    a0, s1, Node_genesis_validators_root
    addi    a1, sp, L + 48
    addi    a2, s1, Node_config
    mv      a3, s5
    addi    a4, sp, L + 56
    FORK_CALL compute_fork_digest
    addi    a0, sp, L + 64
    addi    a1, sp, L + 56
    li      a2, 4
    call    lantern_copy
    addi    a0, sp, L + 64 + 4              # finalized_root, finalized_epoch
    addi    a1, s2, Store_finalized_checkpoint + 8
    li      a2, 32
    call    lantern_copy
    addi    a0, sp, L + 64 + 36
    addi    a1, s2, Store_finalized_checkpoint
    li      a2, 8
    call    lantern_copy
    addi    a0, sp, L + 64 + 44             # head_root, head_slot
    addi    a1, s1, Node_head_root
    li      a2, 32
    call    lantern_copy
    addi    a0, s1, Node_head_root
    call    node_find_block
    li      t1, 0
    li      t0, -1
    beq     a0, t0, 23f
    ld      t1, NodeBlock_slot(a1)
23: sd      t1, (L + 56)(sp)
    addi    a0, sp, L + 64 + 76
    addi    a1, sp, L + 56
    li      a2, 8
    call    lantern_copy
    addi    a0, sp, L + 64 + 84             # earliest_available_slot: Status v2
    addi    a1, s1, Node_earliest_slot
    li      a2, 8
    call    lantern_copy
    mv      a0, s3
    li      a1, 0
    addi    a2, sp, L + 64
    mv      a3, s7
    call    node_respond
    LEAVE 176
50: addi    a0, sp, L + 64                  # MetaData: seq_number, attnets, syncnets, custody_group_count
    li      a1, 32
    call    lantern_zero
    ld      t0, Node_metadata_seq(s1)
    sd      t0, (L + 64)(sp)
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
    LEAVE 176
60: ld      s7, 0(s9)                       # BlocksByRange: start_slot, count
    ld      s10, 8(s9)
    ld      t0, Node_earliest_slot(s1)
    bltu    s7, t0, 92b
    call    node_max_blocks                 # at most the limit, and the room of the list
    bleu    s10, a0, 65f
    mv      s10, a0
65: add     t0, s7, s10                     # the end slot
    bgeu    t0, s7, 66f
    li      t0, -1
66: mv      s10, t0
    li      s8, 0                           # the canonical blocks of the range, from the head down
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
    addi    s9, a1, NodeBlock_parent_root
    bgeu    t0, s10, 61b
    ld      t1, NodeBlock_data_id(a1)
    beqz    t1, 61b
    slli    t2, s8, 3
    add     t2, t2, s3
    sd      t1, NodeStream_request(t2)
    addi    s8, s8, 1
    j       61b
63: addi    t0, s3, NodeStream_request      # in slot order
    slli    t1, s8, 3
    add     t1, t0, t1
    addi    t1, t1, -8
64: bgeu    t0, t1, 77f
    ld      t2, 0(t0)
    ld      t3, 0(t1)
    sd      t3, 0(t0)
    sd      t2, 0(t1)
    addi    t0, t0, 8
    addi    t1, t1, -8
    j       64b
70: srli    s7, s7, 5                       # BlocksByRoot: the blocks the node has, in the request's order
    li      s8, 0
71: beqz    s7, 77f
    mv      a0, s9
    call    node_find_block
    addi    s9, s9, 32
    addi    s7, s7, -1
    li      t0, -1
    beq     a0, t0, 71b
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 71b
    ld      t1, NodeBlock_data_id(a1)
    beqz    t1, 71b
    slli    t2, s8, 3
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
    LEAVE 176
78: li      a0, LIBP2P_EVENT_STREAM_CLOSE   # no block: an empty answer
    ld      a1, NodeStream_handle(s3)
    call    node_out_handle
    mv      a0, s3
    call    node_drop_stream
    LEAVE 176
80: ld      t0, NodeStream_state(s3)        # more bytes come, unless the peer closed
    li      t1, NODE_STREAM_EOF
    beq     t0, t1, 90f
    LEAVE 176
90: li      a1, 1                           # InvalidRequest
91: mv      a0, s3
    mv      a2, sp
    li      a3, 0
    call    node_respond
99: LEAVE 176
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
    ld      a5, NodeStream_version(s3)
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

/* The gossip topic a0 with the subnet a1 at the node's ForkDigest: a SUBSCRIBE event. s3 the topic's length. Locals: L a GossipTopic, L+24 a ByteList of the topic. */
LOCAL_FUNCTION node_sub
    ENTER 176
    ld      t0, Node_fork_digest(s1)
    sd      t0, (L + GossipTopic_fork_digest)(sp)
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
    li      t0, LIBP2P_EVENT_SUBSCRIBE
    sd      t0, 8(a0)
    sd      s3, 16(a0)
    addi    a0, a0, 24
    addi    a1, sp, L + 48
    mv      a2, s3
    call    lantern_copy
9:  LEAVE 176
END_FUNCTION node_sub

/*
 * The gossip topics of the fork of the store's epoch, at its ForkDigest: SUBSCRIBE events, once
 * for each digest, when p2p_out has room for them. s3 the fork, s4 a subnet, s7 the subnets.
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
    mv      a0, s2
    call    node_store_slot
    li      t0, SLOTS_PER_EPOCH
    divu    t0, a0, t0
    sd      t0, L(sp)
    addi    a1, s1, Node_config
    call    node_fork
    mv      s3, a0
    mv      t6, a0
    sd      zero, (L + 8)(sp)
    addi    a0, s1, Node_genesis_validators_root
    addi    a1, sp, L
    addi    a2, s1, Node_config
    mv      a3, s5
    addi    a4, sp, L + 8
    FORK_CALL compute_fork_digest
    bnez    a0, 9f
    ld      t0, Node_flags(s1)
    ld      t1, (L + 8)(sp)
    andi    t2, t0, NODE_FLAG_SUBSCRIBED
    beqz    t2, 1f
    ld      t2, Node_fork_digest(s1)
    beq     t1, t2, 9f
1:  sd      t1, Node_fork_digest(s1)
    ori     t0, t0, NODE_FLAG_SUBSCRIBED
    sd      t0, Node_flags(s1)
    .irp name, GOSSIP_BEACON_BLOCK, GOSSIP_BEACON_AGGREGATE_AND_PROOF, GOSSIP_VOLUNTARY_EXIT, GOSSIP_PROPOSER_SLASHING, GOSSIP_ATTESTER_SLASHING
    li      a0, \name
    li      a1, 0
    call    node_sub
    .endr
    li      t0, FORK_ALTAIR
    bltu    s3, t0, 9f
    li      a0, GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF
    li      a1, 0
    call    node_sub
    li      t0, FORK_CAPELLA
    bltu    s3, t0, 9f
    li      a0, GOSSIP_BLS_TO_EXECUTION_CHANGE
    li      a1, 0
    call    node_sub
    li      t0, FORK_DENEB                  # deneb and electra: every blob sidecar subnet
    bltu    s3, t0, 9f
    li      t0, FORK_FULU
    bgeu    s3, t0, 9f
    LDQ     s7, s1, Node_config + CONFIG_BLOB_SIDECAR_SUBNET_COUNT
    li      t0, FORK_ELECTRA
    bltu    s3, t0, 2f
    LDQ     s7, s1, Node_config + CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA
2:  li      s4, 0
3:  bgeu    s4, s7, 9f
    li      a0, GOSSIP_BLOB_SIDECAR
    mv      a1, s4
    call    node_sub
    addi    s4, s4, 1
    j       3b
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
    bne     t0, t3, 5f
    li      t3, 20 + 48
    bltu    t1, t3, 5f
    addi    t2, t2, 20
4:  LDU64   t3, t2, 0, t4                   # 4-aligned
    sd      t3, NodeMessage_slot(s7)
    addi    a0, s7, NodeMessage_parent_root
    addi    a1, t2, 16
    li      a2, 32
    call    lantern_copy
5:  mv      a0, s9                          # the bytes, kept by the shell
    call    node_put
    sd      a0, NodeMessage_data_id(s7)
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

/* The Status of a2 bytes at a1 (84, or 92 for v2) of the peer of handle a0, kept in its entry. s3 the bytes, s4 their size, s7 the entry. */
LOCAL_FUNCTION node_peer_status
    ENTER 0
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
9:  LEAVE 0
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
    ld      t0, NodeStream_state(a0)
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
    li      t0, 24 + 128                    # the protocol ID
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
2:  li      t0, CHUNK_RESPONSE              # blocks by range v2 and blob sidecars by range: a ForkDigest context
    sd      t0, (L + ChunkHeader_kind)(sp)
    li      t0, 4
    li      t1, REQRESP_BLOB_SIDECARS_BY_RANGE
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
4:  li      t0, REQRESP_BLOB_SIDECARS_BY_RANGE
    bne     s4, t0, 42f
    li      t0, NODE_BLOB_BYTES             # a blob sidecar: room for its BYTES_PUT, its work, its entry
    bne     s9, t0, 85f
    li      a0, NODE_BLOB_BYTES + 48 + NODE_ACT_WORK_SIZE + 7
    call    node_room
    beqz    a0, 95f
    ld      t0, Node_p2p_out(s1)
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
6:  li      t0, REQRESP_BLOB_SIDECARS_BY_RANGE
    beq     s4, t0, 61f
    PART    t0, t1, s1, Node_blocks         # a block: its entry, its bytes, the work of its root
    sd      t1, (L + 48)(sp)
    li      t2, NodeBlock__mem
    mul     t2, t1, t2
    add     s10, t0, t2
    addi    t1, t1, 1
    sd      t1, (Node_blocks + 8)(s1)
    mv      a0, s10
    li      a1, NodeBlock__mem
    call    lantern_zero
    addi    t0, s8, 24                      # the slot at 4 mod 8
    LDU64   t1, t0, 100, t2
    sd      t1, NodeBlock_slot(s10)
    addi    a0, s10, NodeBlock_parent_root
    addi    a1, s8, 24 + 116
    li      a2, 32
    call    lantern_copy
    li      t0, NODE_BLOCK_HASHING
    sd      t0, NodeBlock_status(s10)
    li      t0, 1
    sd      t0, NodeBlock_data_available(s10)
    mv      a0, s8
    call    node_put
    sd      a0, NodeBlock_data_id(s10)
    mv      a3, a0
    li      a0, NODE_WORK_SYNC_BLOCK
    li      a1, 0
    li      a2, 0
    ld      a4, (L + 48)(sp)
    li      a5, 0
    call    node_work
    j       7f
61: PART    t0, t1, s1, Node_blobs          # a blob sidecar: its entry, its bytes, the work of its checks
    sd      t1, (L + 48)(sp)
    li      t2, NodeBlob__mem
    mul     t2, t1, t2
    add     s10, t0, t2
    addi    t1, t1, 1
    sd      t1, (Node_blobs + 8)(s1)
    mv      a0, s10
    li      a1, NodeBlob__mem
    call    lantern_zero
    ld      t0, 24(s8)                      # its index, and the slot of its block header
    sd      t0, NodeBlob_index(s10)
    LDQ     t0, s8, 24 + NODE_BLOB_HEADER
    sd      t0, NodeBlob_slot(s10)
    li      t0, NODE_BLOB_VERIFYING
    sd      t0, NodeBlob_status(s10)
    mv      a0, s8
    call    node_put
    sd      a0, NodeBlob_data_id(s10)
    mv      a3, a0
    li      a0, NODE_WORK_BLOB
    li      a1, 0
    li      a2, 0
    ld      a4, (L + 48)(sp)
    li      a5, 0
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
    li      t0, REQRESP_STATUS              # Status: one chunk
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
 * a0 = 1 when a response waits for room, else 0. The bytes of each response are read; then,
 * with no BeaconBlocksByRange of the node open, one to a peer of the node's ForkDigest whose
 * Status head_slot is at least the next slot: max(the head's slot + 1, sync_slot), at most
 * NODE_SYNC_BATCH slots. Before it, with room for two streams, a BlobSidecarsByRange of the
 * range's slots in the blob window before fulu. s3 a peer, s4 the streams or peers left, s7 the
 * result, s8 the start slot. Locals: L the request (24), L+24 the blob request (16).
 */
LOCAL_FUNCTION node_sync
    ENTER 48
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
3:  ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_SYNCING
    bnez    t0, 9f
    addi    a0, s1, Node_head_root
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 9f
    ld      s8, NodeBlock_slot(a1)
    addi    s8, s8, 1
    ld      t0, Node_sync_slot(s1)
    bleu    t0, s8, 31f
    mv      s8, t0
31: PART    s3, s4, s1, Node_peers          # a peer ahead
4:  beqz    s4, 9f
    ld      t0, NodePeer_flags(s3)
    andi    t0, t0, NODE_PEER_STATUS
    beqz    t0, 5f
    ld      t0, NodePeer_fork_digest(s3)
    ld      t1, Node_fork_digest(s1)
    bne     t0, t1, 5f
    ld      t0, NodePeer_head_slot(s3)
    bgeu    t0, s8, 6f
5:  addi    s3, s3, NodePeer__mem
    addi    s4, s4, -1
    j       4b
6:  sub     t0, t0, s8                      # the request: start_slot, count, step 1
    addi    t0, t0, 1
    li      t1, NODE_SYNC_BATCH
    bleu    t0, t1, 61f
    mv      t0, t1
61: sd      s8, L(sp)
    sd      t0, (L + 8)(sp)
    li      t0, 1
    sd      t0, (L + 16)(sp)
    mv      a0, s2                          # the blob window's first slot: of max(store epoch - MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS, DENEB_FORK_EPOCH)
    call    node_store_slot
    li      t0, SLOTS_PER_EPOCH
    divu    a0, a0, t0
    LDQ     t1, s1, Node_config + CONFIG_MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS
    sub     t2, a0, t1
    sltu    t3, a0, t1
    addi    t3, t3, -1
    and     a0, t2, t3
    LDQ     t1, s1, Node_config + 16 * FORK_DENEB
    bgeu    a0, t1, 62f
    mv      a0, t1
62: mulhu   t1, a0, t0
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
66: mv      a0, s2                          # version 2 from altair on
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
9:  mv      a0, s7
    LEAVE 48
END_FUNCTION node_sync

/* The libp2p application notice a0 of the libp2p state a1. s3 the notice, s4 an entry, s7 method, s8 version. */
LOCAL_FUNCTION node_notice
    ENTER 0
    mv      s3, a0
    ld      t0, LIBP2P_ACT_KIND(s3)
    li      t1, LIBP2P_ACTION_MESSAGE
    bne     t0, t1, 60f
    call    node_message                    # a0, a1 as given
    LEAVE 0
60: li      t1, LIBP2P_ACTION_MESSAGE_STATUS
    bne     t0, t1, 62f
    call    node_message_status
    LEAVE 0
62: li      t1, LIBP2P_ACTION_STREAM_OPENED
    bne     t0, t1, 63f
    ld      a0, LIBP2P_ACT_SO_TAG(s3)       # the node's request stream: the request, then the close of our side
    call    node_find_opening
    li      t0, -1
    beq     a0, t0, 69f
    mv      s4, a1
    ld      t0, LIBP2P_ACT_STREAM(s3)
    sd      t0, NodeStream_handle(s4)
    li      t0, NODE_STREAM_RESPONSE
    sd      t0, NodeStream_state(s4)
    sd      zero, NodeStream_next(s4)
    ld      s8, (NodeStream_list + 16)(s4)
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
69: LEAVE 0
68: li      a0, LIBP2P_EVENT_STREAM_RESET   # no room: a reset
    ld      a1, NodeStream_handle(s4)
    call    node_out_handle
    mv      a0, s4
    call    node_end_stream
    LEAVE 0
63: li      t1, LIBP2P_ACTION_STREAM_FAILED
    bne     t0, t1, 61f
    ld      a0, LIBP2P_ACT_STREAM(s3)       # its tag
    call    node_find_opening
    li      t0, -1
    beq     a0, t0, 69b
    mv      a0, a1
    call    node_end_stream
    LEAVE 0
61: li      t1, LIBP2P_ACTION_PEER_CONNECTED
    bne     t0, t1, 10f
    ld      t2, Node_streams(s1)            # a new peer: its entry, or DISCONNECT when the table is full
    ld      t3, Node_peers(s1)
    sub     t2, t2, t3
    li      t3, NodePeer__mem
    divu    t2, t2, t3
    ld      t4, (Node_peers + 8)(s1)
    bltu    t4, t2, 1f
    li      a0, LIBP2P_EVENT_DISCONNECT
    ld      a1, LIBP2P_ACT_PEER(s3)
    call    node_out_handle
    LEAVE 0
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
    ld      a2, LIBP2P_ACT_PC_ID_LEN(s3)
    li      t0, 48
    bleu    a2, t0, 2f
    li      a2, 48
2:  sd      a2, NodePeer_id_len(s4)
    addi    a0, s4, NodePeer_id
    addi    a1, s3, LIBP2P_ACT_PC_ID
    call    lantern_copy
    LEAVE 0
10: li      t1, LIBP2P_ACTION_PEER_DISCONNECTED
    bne     t0, t1, 20f
    ld      a0, LIBP2P_ACT_PEER(s3)
    call    node_find_peer
    li      t0, -1
    beq     a0, t0, 19f
    mv      a0, a1
    call    node_drop_peer
19: LEAVE 0
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
    LEAVE 0
28: li      a0, LIBP2P_EVENT_STREAM_RESET
    ld      a1, LIBP2P_ACT_STREAM(s3)
    call    node_out_handle
    LEAVE 0
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
    LEAVE 0
37: call    node_request
39: LEAVE 0
38: li      a0, LIBP2P_EVENT_STREAM_RESET   # more than the room: a reset
    ld      a1, NodeStream_handle(s4)
    call    node_out_handle
    mv      a0, s4
    call    node_end_stream
    LEAVE 0
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
    LEAVE 0
41: li      t1, NODE_STREAM_EOF             # while its request is read
    bgtu    t0, t1, 49f
    sd      t1, NodeStream_state(a1)
    mv      a0, a1
    call    node_request
49: LEAVE 0
50: li      t1, LIBP2P_ACTION_STREAM_RESET
    bne     t0, t1, 59f
    ld      a0, LIBP2P_ACT_STREAM(s3)
    call    node_find_stream
    li      t0, -1
    beq     a0, t0, 59f
    mv      a0, a1
    call    node_end_stream
59: LEAVE 0
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
 * s4 their end, s5 scratch, s6 actions, s7 result, s8 the event count, s9 the BLOCK,
 * POW_BLOCK and GOSSIP WORK_DONE events then an event, s10 the event bytes then a root entry at the end of scratch,
 * t5 the WORK_DONE events in the first pass. Locals: L the WORK_DONE events, L+8 the scratch
 * size, L+16 p2p, L+24 tick, L+32 the end of the events handled, L+40 the queue's free bytes the P2P events take, saved,
 * L+48 the libp2p scratch, L+56 the bytes of the P2P events, L+64 the P2P events, L+72 the
 * action room kept for the node, L+80 wakeup, L+88 libp2p's StepResult, L+96 libp2p's actions,
 * L+104 the libp2p steps, L+112 a stream waits, L+120 the GOSSIP WORK_DONE events.
 */
FUNCTION lantern_node_step
    ENTER 128
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
    li      t4, NODE_EV_TICK
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
23: li      t6, NODE_WORK_SERVE
    bne     t4, t6, 22f
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
21: li      t4, NODE_EV_P2P                 # a libp2p event inside, for a node with a libp2p state
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
    li      t4, NODE_EV_BLOCK
    beq     t3, t4, 31f
    li      t4, NODE_EV_POW_BLOCK
    bne     t3, t4, 4f
31: addi    s9, s9, 1
4:  addi    s8, s8, 1
    add     s10, s10, t2
    add     t0, t0, t2
    j       1b
5:  sd      t5, L(sp)
    li      t1, 512                         # room: actions, node parts, scratch
    mul     t1, s8, t1
    add     t1, t1, s10
    ld      t2, (Node_blocks + 8)(s1)
    li      t3, 128
    mul     t2, t2, t3
    add     t1, t1, t2
    addi    t1, t1, 512
    sd      t1, (L + 72)(sp)
    ld      t2, (L + 16)(sp)
    beqz    t2, 51f
    li      t2, LIBP2P_ACTIONS_MIN + 24 + 16
    add     t1, t1, t2
51: ld      t0, 0(s6)
    ld      t2, 8(s6)
    bltu    t0, t2, 8f
    sub     t0, t0, t2
    ld      t2, 16(s6)
    bltu    t0, t2, 8f
    sub     t0, t0, t2
    bltu    t0, t1, 8f
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
1:  bltu    t0, t1, 8f
    ld      t0, Node_p2p_out(s1)            # blobs: one for each GOSSIP WORK_DONE event, and with p2p a batch's sidecars
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
    bgeu    t2, t3, 548f
    mv      t2, t3
548: srli   t3, t2, 32
    bnez    t3, 8f
    li      t3, NODE_SYNC_BATCH
    mul     t2, t2, t3
    add     t1, t1, t2
549: bltu   t0, t1, 8f
    ld      t0, Node_pow_blocks(s1)         # checkpoints: two for each WORK_DONE event, and two
    ld      t1, Node_checkpoints(s1)
    sub     t0, t0, t1
    li      t1, NodeCheckpoint__mem
    divu    t0, t0, t1
    ld      t1, (Node_checkpoints + 8)(s1)
    sub     t0, t0, t1
    slli    t1, t5, 1
    addi    t1, t1, 2
    bltu    t0, t1, 8f
    ld      t0, Node_peers(s1)              # pow blocks: one for each POW_BLOCK event
    ld      t1, Node_pow_blocks(s1)
    sub     t0, t0, t1
    li      t1, POW_BLOCK_BYTES
    divu    t0, t0, t1
    ld      t1, (Node_pow_blocks + 8)(s1)
    sub     t0, t0, t1
    bltu    t0, s9, 8f
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
    bltu    t0, t1, 8f
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
    ld      t1, 0(s5)
    bltu    t1, t0, 8f
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
53: mv      s9, s3                          # the root of each BLOCK event, before any change
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
30: ld      t0, 0(s5)                       # then each event, in order
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
    sd      zero, (L + 112)(sp)
    ld      t0, (L + 16)(sp)                # the next block of each stream that serves, then libp2p again
    beqz    t0, 40f
    call    node_subscribe
    call    node_serve
    sd      a0, (L + 112)(sp)
    call    node_sync
    ld      t0, (L + 112)(sp)
    or      t0, t0, a0
    sd      t0, (L + 112)(sp)
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
    LEAVE 128
14: ld      t0, (L + 8)(sp)                 # a status before any change
    sd      t0, 0(s5)
    LEAVE 128
7:  li      a0, LANTERN_INVALID_EVENT
    LEAVE 128
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 128
END_FUNCTION lantern_node_step

/*
 * (node, store, seen, work, state_a, state_b, state_c, data, settings, scratch, event): s1 node,
 * s2 store, s3 work, s4 state_a, s5 data, s6 scratch, s7 event, s8 the event's room, s9 a
 * temporary. Locals: L the BlockOptions (32), or a chunk's size, a fork digest and a ChunkHeader
 * (64); L+64 seen, L+72 state_b, L+80 state_c, L+88 settings, L+96 a NodeGossip.
 */
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
2:  sd      t3, (L + BlockOptions_data_available)(sp)
    sd      zero, (L + BlockOptions_pow_block)(sp)
    sd      zero, (L + BlockOptions_pow_parent)(sp)
    ld      t0, 16(s5)
    li      t1, 100 + 84
    bltu    t0, t1, 18f
    ld      t0, 8(s5)
    add     t0, s5, t0
    LDU64   a0, t0, 100, t1
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s2
    mv      a1, s1
    mv      a2, s5
    mv      a3, s4
    addi    a4, sp, L
    mv      a5, s6
    addi    a6, s7, NodeEvent_result
    FORK_CALL node_import
    li      t0, LANTERN_NEED_JUSTIFIED_STATE
    bne     a0, t0, 99f
    sd      a0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    LEAVE 192
18: li      t0, LANTERN_INVALID_ENCODING
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
    mv      t6, a0
    mv      a0, s2
    mv      a1, s5
    mv      a2, s4
    mv      a3, s6
    addi    a4, s7, NodeEvent_result
    FORK_CALL node_attester_slashing
99: LEAVE 192
50: li      t1, NODE_WORK_SERVE
    bne     t0, t1, 60f
    ld      t0, 16(s5)                      # SERVE: the chunk of the block's bytes, with room for it
    li      t1, 100 + 84
    bltu    t0, t1, 18b
    sd      t0, L(sp)
    addi    a0, sp, L
    addi    a1, sp, L
    call    lantern_reqresp_chunk_size
    ld      t0, L(sp)
    addi    t0, t0, NodeEvent_chunk + 24 + 7
    andi    t0, t0, -8
    bltu    s8, t0, 7f
    ld      t0, 8(s5)                       # the context: ForkDigest of the block's epoch
    add     t0, s5, t0
    LDU64   s9, t0, 100, t1
    mv      a0, s9
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
    li      t0, CHUNK_RESPONSE              # the header: v1 has no context bytes
    sd      t0, (L + 16 + ChunkHeader_kind)(sp)
    ld      t0, NodeAction_arg(s3)
    li      t1, 2
    li      t2, 0
    bltu    t0, t1, 51f
    li      t2, 4
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
    ld      t0, (L + 64)(sp)                # GOSSIP: the inputs of the fork's node_gossip
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
    ld      t0, (L + 72)(sp)
    sd      t0, (L + 96 + NodeGossip_proposer)(sp)
    ld      t0, (L + 80)(sp)
    sd      t0, (L + 96 + NodeGossip_justified)(sp)
    ld      t0, (L + 88)(sp)
    sd      t0, (L + 96 + NodeGossip_settings)(sp)
    addi    t0, s1, Node_config
    sd      t0, (L + 96 + NodeGossip_config)(sp)
    mv      a0, s2
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    addi    a0, sp, L + 96
    mv      a1, s5
    mv      a2, s6
    addi    a3, s7, NodeEvent_result
    addi    a4, s7, NodeEvent_root
    addi    a5, s7, NodeEvent_index
    FORK_CALL node_gossip
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
    bne     t0, t1, 8f
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
8:  li      a0, LANTERN_INVALID_EVENT
    LEAVE 192
7:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 192
END_FUNCTION lantern_node_run
