/*
 * The node core, ARM64: in the common object. Requirements: docs/reference/node.md.
 */

.set NODE_ROOT_ENTRY, 40                /* lantern_node_step: a flag, then the root of a BLOCK event */
/* reg = the node x19's ByteList of the libp2p events it queued. */
.macro P2P_OUT reg
    ldr     \reg, [x19, #Node_p2p_out]
    add     \reg, x19, \reg
.endm

.set NODE_BLOB_HEADER, 8 + 32 * FIELD_ELEMENTS_PER_BLOB + 48 + 48   /* the signed_block_header in a BlobSidecar's SSZ bytes */
.set NODE_BLOB_BYTES, NODE_BLOB_HEADER + 208 + 32 * KZG_COMMITMENT_INCLUSION_PROOF_DEPTH  /* the SSZ size of a BlobSidecar */

/* L0: x0 = the fork of the slot x0 with the config x1: the last fork whose epoch is at most the slot's. Uses x9-x11. */
LOCAL_FUNCTION node_fork
    UNWIND_END_PROLOGUE
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x9, x0, x9
    mov     x10, #(16 * FORK_FULU)
1:  cbz     x10, 2f
    ldr     x11, [x1, x10]
    cmp     x9, x11
    b.hs    2f
    sub     x10, x10, #16
    b       1b
2:  lsr     x0, x10, #4
    ret
END_FUNCTION node_fork

/* L0: x0 = the current slot of the store x0: (time_ms - genesis_time_ms) // SLOT_DURATION_MS, 0 before genesis. Uses x9, x10. */
LOCAL_FUNCTION node_store_slot
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #Store_time_ms]
    ldr     x10, [x0, #Store_genesis_time_ms]
    subs    x9, x9, x10
    csel    x9, xzr, x9, lo
    LDQ     x10, x0, Store_config + CONFIG_SLOT_DURATION_MS
    mov     x0, #0
    cbz     x10, 1f
    udiv    x0, x9, x10
1:  ret
END_FUNCTION node_store_slot

/* x12 += the room x0 field times width; to 9f on overflow. Uses x10, x11, x13. */
.macro NODE_SIZE_ADD field, width
    ldr     x10, [x0, #NodeRoom_\field]
    mov     x11, #(\width)
    umulh   x13, x10, x11
    cbnz    x13, 9f
    mul     x10, x10, x11
    adds    x12, x12, x10
    b.cs    9f
.endm

/* (room, size): NODE_FIXED + the room of each part. Uses x9-x13. */
FUNCTION lantern_node_size
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #NodeRoom_request_bytes]       /* the bytes of a stream */
    lsr     x10, x9, #32
    cbnz    x10, 9f
    add     x9, x9, #(NodeStream__fixed + 7)
    and     x9, x9, #~7
    ldr     x10, [x0, #NodeRoom_streams]
    umulh   x13, x10, x9
    cbnz    x13, 9f
    mul     x12, x10, x9
    NODE_SIZE_ADD blocks, NodeBlock__mem
    NODE_SIZE_ADD checkpoints, NodeCheckpoint__mem
    NODE_SIZE_ADD pow_blocks, POW_BLOCK_BYTES
    NODE_SIZE_ADD peers, NodePeer__mem
    NODE_SIZE_ADD messages, NodeMessage__mem
    NODE_SIZE_ADD blobs, NodeBlob__mem
    ldr     x10, [x0, #NodeRoom_p2p_out] /* a ByteList */
    adds    x10, x10, #(24 + 7)
    b.cs    9f
    and     x10, x10, #~7
    adds    x12, x12, x10
    b.cs    9f
    ldr     x10, [x0, #NodeRoom_engine_bytes]   /* a ByteList */
    adds    x10, x10, #(24 + 7)
    b.cs    9f
    and     x10, x10, #~7
    adds    x12, x12, x10
    b.cs    9f
    MOVQ    x10, NODE_FIXED
    adds    x12, x12, x10
    b.cs    9f
    str     x12, [x1]
    mov     x0, #LANTERN_OK
    ret
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_node_size

/* x9 += the room x1 field times width, the next part of the node x0 at x9. Uses x10, x11. */
.macro NODE_PART part, field, width
    str     x9, [x0, #Node_\part]
    str     xzr, [x0, #(Node_\part + 8)]
    ldr     x10, [x1, #NodeRoom_\field]
    mov     x11, #(\width)
    madd    x9, x10, x11, x9
.endm

/* L0: lay out the parts of the node x0 for the room x1 at NODE_FIXED, with no entries. Uses x9-x12. */
LOCAL_FUNCTION node_layout
    UNWIND_END_PROLOGUE
    ldr     x12, [x1, #NodeRoom_request_bytes]
    add     x12, x12, #(NodeStream__fixed + 7)
    and     x12, x12, #~7
    str     x12, [x0, #Node_stream_bytes]
    MOVQ    x9, NODE_FIXED
    NODE_PART blocks, blocks, NodeBlock__mem
    NODE_PART checkpoints, checkpoints, NodeCheckpoint__mem
    NODE_PART pow_blocks, pow_blocks, POW_BLOCK_BYTES
    NODE_PART peers, peers, NodePeer__mem
    str     x9, [x0, #Node_streams]
    str     xzr, [x0, #(Node_streams + 8)]
    ldr     x10, [x1, #NodeRoom_streams]
    madd    x9, x10, x12, x9
    NODE_PART messages, messages, NodeMessage__mem
    NODE_PART blobs, blobs, NodeBlob__mem
    str     x9, [x0, #Node_p2p_out]         /* one ByteList, empty */
    mov     x10, #1
    str     x10, [x0, #(Node_p2p_out + 8)]
    ldr     x10, [x1, #NodeRoom_p2p_out]
    add     x10, x10, #(24 + 7)
    and     x10, x10, #~7
    add     x11, x0, x9
    mov     x12, #24
    stp     x10, x12, [x11]
    str     xzr, [x11, #16]
    add     x9, x9, x10
    str     x9, [x0, #Node_engine_in]       /* one ByteList, empty */
    mov     x10, #1
    str     x10, [x0, #(Node_engine_in + 8)]
    ldr     x10, [x1, #NodeRoom_engine_bytes]
    add     x10, x10, #(24 + 7)
    and     x10, x10, #~7
    add     x11, x0, x9
    stp     x10, x12, [x11]
    str     xzr, [x11, #16]
    ret
END_FUNCTION node_layout

/*
 * (room, config, anchor, flags, node): a node whose one block is the anchor, imported, with
 * post-state id 1, and whose one checkpoint is (anchor epoch, anchor root) at state id 1.
 * x19 room, x20 config, x21 anchor, x22 anchor slot, x23 flags, x24 node. Locals: L the size.
 */
FUNCTION lantern_node_init
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x21, #NodeAnchor_slot]
    ldr     x23, [x3]
    mov     x24, x4
    add     x1, sp, #L
    bl      lantern_node_size
    cbnz    x0, 9f
    ldr     x9, [x24]
    ldr     x10, [sp, #L]
    cmp     x9, x10
    b.lo    8f
    ldr     x9, [x19, #NodeRoom_blocks]     /* room for the anchor */
    cbz     x9, 8f
    ldr     x9, [x19, #NodeRoom_checkpoints]
    cbz     x9, 8f
    add     x0, x24, #8                     /* the fixed fields: zero, then set */
    MOVQ    x1, NODE_FIXED - 8
    bl      lantern_zero
    mov     x9, #2
    str     x9, [x24, #Node_next_id]
    mov     x9, #1
    str     x9, [x24, #Node_anchor_state_id]
    str     x23, [x24, #Node_flags]
    str     x22, [x24, #Node_earliest_slot]
    add     x9, x24, #Node_head_root
    COPY32  x9, x21
    add     x9, x24, #Node_genesis_validators_root
    add     x10, x21, #NodeAnchor_genesis_validators_root
    COPY32  x9, x10
    add     x0, x24, #Node_config
    mov     x1, x20
    MOVQ    x2, CONFIG_SIZE
    bl      lantern_copy
    tbz     x23, #4, 1f                     /* NODE_FLAG_ENGINE: the secret, the host, the first id */
    ldr     x2, [x21, #NodeAnchor_engine_host_len]
    cmp     x2, #NODE_ENGINE_HOST_MAX
    b.hi    7f
    str     x2, [x24, #Node_engine_host_len]
    add     x0, x24, #Node_engine_host
    add     x1, x21, #NodeAnchor_engine_host
    bl      lantern_copy
    add     x9, x24, #Node_jwt_secret
    add     x10, x21, #NodeAnchor_jwt_secret
    COPY32  x9, x10
    mov     x9, #1
    str     x9, [x24, #Node_engine_id]
    orr     x9, x23, #NODE_FLAG_FCU         /* the anchor's head goes to the engine first */
    str     x9, [x24, #Node_flags]
1:  mov     x0, x24
    mov     x1, x19
    bl      node_layout
    PART    x9, x10, x24, Node_blocks       /* the anchor block */
    mov     x0, x9
    mov     x1, #NodeBlock__mem
    bl      lantern_zero
    PART    x9, x10, x24, Node_blocks
    COPY32  x9, x21
    str     x22, [x9, #NodeBlock_slot]
    mov     x10, #1
    str     x10, [x9, #NodeBlock_state_id]
    mov     x10, #NODE_BLOCK_IMPORTED
    str     x10, [x9, #NodeBlock_status]
    mov     x10, #1
    str     x10, [x9, #NodeBlock_data_available]
    mov     x10, #1
    str     x10, [x24, #(Node_blocks + 8)]
    PART    x9, x10, x24, Node_checkpoints  /* the anchor checkpoint */
    mov     x10, #SLOTS_PER_EPOCH
    udiv    x10, x22, x10
    str     x10, [x9, #NodeCheckpoint_epoch]
    add     x10, x9, #NodeCheckpoint_root
    COPY32  x10, x21
    mov     x10, #1
    str     x10, [x9, #NodeCheckpoint_state_id]
    str     x10, [x24, #(Node_checkpoints + 8)]
    mov     x0, #LANTERN_OK
9:  LEAVE 16
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
7:  mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 16
END_FUNCTION lantern_node_init

/* The node x21 gets the entries of the part at ref of the node x19, of width bytes each. */
.macro NODE_COPY_PART ref, width
    PART    x1, x2, x19, \ref
    str     x2, [x21, #((\ref) + 8)]
    mov     x9, #(\width)
    mul     x2, x2, x9
    ldr     x9, [x21, #(\ref)]
    add     x0, x21, x9
    bl      lantern_copy
.endm

/* Branch to 8f when the room x20 field is below the entries of the part at ref of the node x19. Uses x9, x10. */
.macro NODE_COPY_ROOM field, ref
    ldr     x9, [x20, #NodeRoom_\field]
    ldr     x10, [x19, #((\ref) + 8)]
    cmp     x9, x10
    b.lo    8f
.endm

/*
 * (node, room, out): the node in out, with the capacities of room. x19 node, x20 room, x21 out,
 * x22 a stream, x23 the streams left, x24 the old stream bytes. Locals: L the size.
 */
FUNCTION lantern_node_copy
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x0, x20
    add     x1, sp, #L
    bl      lantern_node_size
    cbnz    x0, 9f
    ldr     x9, [x21]
    ldr     x10, [sp, #L]
    cmp     x9, x10
    b.lo    8f
    NODE_COPY_ROOM blocks, Node_blocks      /* each capacity holds the entries */
    NODE_COPY_ROOM checkpoints, Node_checkpoints
    NODE_COPY_ROOM pow_blocks, Node_pow_blocks
    NODE_COPY_ROOM peers, Node_peers
    NODE_COPY_ROOM streams, Node_streams
    NODE_COPY_ROOM messages, Node_messages
    NODE_COPY_ROOM blobs, Node_blobs
    ldr     x9, [x20, #NodeRoom_p2p_out]    /* the queued bytes fit */
    ldr     x10, [x19, #Node_p2p_out]
    add     x10, x19, x10
    ldr     x10, [x10, #16]
    cmp     x9, x10
    b.lo    8f
    ldr     x9, [x20, #NodeRoom_engine_bytes]   /* the execution engine's bytes fit */
    ldr     x10, [x19, #Node_engine_in]
    add     x10, x19, x10
    ldr     x10, [x10, #16]
    cmp     x9, x10
    b.lo    8f
    ldr     x24, [x19, #Node_stream_bytes]  /* a stream's request bytes fit */
    ldr     x9, [x20, #NodeRoom_request_bytes]
    add     x9, x9, #(NodeStream__fixed + 7)
    and     x9, x9, #~7
    cmp     x9, x24
    b.lo    8f
    add     x0, x21, #8                     /* the fixed fields */
    add     x1, x19, #8
    MOVQ    x2, NODE_FIXED - 8
    bl      lantern_copy
    mov     x0, x21
    mov     x1, x20
    bl      node_layout
    NODE_COPY_PART Node_blocks, NodeBlock__mem      /* the entries of each part */
    NODE_COPY_PART Node_checkpoints, NodeCheckpoint__mem
    NODE_COPY_PART Node_pow_blocks, POW_BLOCK_BYTES
    NODE_COPY_PART Node_peers, NodePeer__mem
    NODE_COPY_PART Node_messages, NodeMessage__mem
    NODE_COPY_PART Node_blobs, NodeBlob__mem
    ldr     x1, [x19, #Node_p2p_out]        /* the queued bytes */
    add     x1, x19, x1
    ldr     x2, [x1, #16]
    ldr     x0, [x21, #Node_p2p_out]
    add     x0, x21, x0
    str     x2, [x0, #16]
    add     x0, x0, #24
    add     x1, x1, #24
    bl      lantern_copy
    ldr     x1, [x19, #Node_engine_in]      /* the execution engine's bytes */
    add     x1, x19, x1
    ldr     x2, [x1, #16]
    ldr     x0, [x21, #Node_engine_in]
    add     x0, x21, x0
    str     x2, [x0, #16]
    add     x0, x0, #24
    add     x1, x1, #24
    bl      lantern_copy
    PART    x22, x23, x19, Node_streams     /* each stream, with the request room of the new stride */
    str     x23, [x21, #(Node_streams + 8)]
    ldr     x25, [x21, #Node_streams]
    add     x25, x21, x25
1:  cbz     x23, 2f
    mov     x0, x25
    mov     x1, x22
    mov     x2, x24
    bl      lantern_copy
    ldr     x9, [x21, #Node_stream_bytes]
    sub     x10, x9, #NodeStream_list
    str     x10, [x25, #NodeStream_list]
    add     x25, x25, x9
    add     x22, x22, x24
    sub     x23, x23, #1
    b       1b
2:  mov     x0, #LANTERN_OK
9:  LEAVE 16
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_node_copy

/*
 * The step's helpers read the node from x19, the store from x20, the scratch from x23 and the
 * actions from x24. An action is added at the end of the actions' bytes, whose room the step
 * checks first.
 */

/* L0: x0 = a new action of kind x0 and x1 bytes, its size and kind written. Uses x9-x11. */
LOCAL_FUNCTION node_act
    UNWIND_END_PROLOGUE
    ldp     x9, x10, [x24, #8]
    add     x11, x24, x9
    add     x11, x11, x10
    add     x10, x10, x1
    str     x10, [x24, #16]
    stp     x1, x0, [x11]
    mov     x0, x11
    ret
END_FUNCTION node_act

/* L0: x0 = a new BufferId. Uses x9. */
LOCAL_FUNCTION node_new_id
    UNWIND_END_PROLOGUE
    ldr     x0, [x19, #Node_next_id]
    add     x9, x0, #1
    str     x9, [x19, #Node_next_id]
    ret
END_FUNCTION node_new_id

/* L0: x0 = the index of the block whose root is at x0, or 2^64 - 1; x1 = its entry. Uses x9-x15. */
LOCAL_FUNCTION node_find_block
    UNWIND_END_PROLOGUE
    PART    x9, x10, x19, Node_blocks
    mov     x11, #0
1:  cmp     x11, x10
    b.hs    3f
    ldp     x12, x13, [x9]
    ldp     x14, x15, [x0]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.ne    2f
    ldp     x12, x13, [x9, #16]
    ldp     x14, x15, [x0, #16]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.eq    4f
2:  add     x9, x9, #NodeBlock__mem
    add     x11, x11, #1
    b       1b
3:  mov     x0, #-1
    ret
4:  mov     x0, x11
    mov     x1, x9
    ret
END_FUNCTION node_find_block

/* L0: x0 = the index of the checkpoint (epoch x0, root at x1), or 2^64 - 1; x1 = its entry. Uses x9-x16. */
LOCAL_FUNCTION node_find_checkpoint
    UNWIND_END_PROLOGUE
    PART    x9, x10, x19, Node_checkpoints
    mov     x11, #0
1:  cmp     x11, x10
    b.hs    3f
    ldr     x12, [x9, #NodeCheckpoint_epoch]
    cmp     x12, x0
    b.ne    2f
    ldp     x12, x13, [x9, #NodeCheckpoint_root]
    ldp     x14, x15, [x1]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.ne    2f
    ldp     x12, x13, [x9, #(NodeCheckpoint_root + 16)]
    ldp     x14, x15, [x1, #16]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.eq    4f
2:  add     x9, x9, #NodeCheckpoint__mem
    add     x11, x11, #1
    b       1b
3:  mov     x0, #-1
    ret
4:  mov     x0, x11
    mov     x1, x9
    ret
END_FUNCTION node_find_checkpoint

/* L0: x0 = a WORK action: kind x0, state_a x1, state_b x2, data x3, target x4, arg x5; state_c 0. */
LOCAL_FUNCTION node_work
    FRAME 48
    stp     x0, x1, [sp, #16]
    stp     x2, x3, [sp, #32]
    stp     x4, x5, [sp, #48]
    mov     x0, #NODE_ACT_WORK
    mov     x1, #NODE_ACT_WORK_SIZE
    bl      node_act
    ldp     x9, x10, [sp, #16]
    stp     x9, x10, [x0, #NodeAction_work_kind]
    ldp     x9, x10, [sp, #32]
    str     x9, [x0, #NodeAction_state_b]
    str     xzr, [x0, #NodeAction_state_c]
    str     x10, [x0, #NodeAction_data]
    ldp     x9, x10, [sp, #48]
    stp     x9, x10, [x0, #NodeAction_target]
    UNFRAME 48
END_FUNCTION node_work

/* L0: an action of kind x0 with the two ids x1 and x2 (STATE_COPY: source, new; the FREE kinds: x1). */
LOCAL_FUNCTION node_ids
    FRAME 32
    stp     x1, x2, [sp, #16]
    mov     x1, #32
    bl      node_act
    ldp     x9, x10, [sp, #16]
    stp     x9, x10, [x0, #16]
    UNFRAME 32
END_FUNCTION node_ids

/*
 * L0: the state id of the checkpoint state of (epoch x0, root at x1), or 0 when the root's
 * block has no post-state: a new checkpoint is a copy of that post-state and a TARGET_STATE work.
 * x21 epoch, x22 root, x25 the new id.
 */
LOCAL_FUNCTION node_checkpoint_state
    ENTER 0
    mov     x21, x0
    mov     x22, x1
    bl      node_find_checkpoint
    cmn     x0, #1
    b.eq    1f
    ldr     x0, [x1, #NodeCheckpoint_state_id]
    LEAVE 0
1:  mov     x0, x22                         /* the root's block, imported */
    bl      node_find_block
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    9f
    ldr     x23, [x1, #NodeBlock_state_id]
    bl      node_new_id
    mov     x25, x0
    mov     x0, #NODE_ACT_STATE_COPY
    mov     x1, x23
    mov     x2, x25
    bl      node_ids
    PART    x9, x10, x19, Node_checkpoints  /* the entry */
    mov     x11, #NodeCheckpoint__mem
    madd    x9, x10, x11, x9
    str     x21, [x9, #NodeCheckpoint_epoch]
    add     x12, x9, #NodeCheckpoint_root
    COPY32  x12, x22
    str     x25, [x9, #NodeCheckpoint_state_id]
    add     x11, x10, #1
    str     x11, [x19, #(Node_checkpoints + 8)]
    mov     x0, #NODE_WORK_TARGET_STATE
    mov     x1, x25
    mov     x2, #0
    mov     x3, #0
    mov     x4, x10
    mov     x5, x21
    bl      node_work
    mov     x0, x25
    LEAVE 0
9:  mov     x0, #0
    LEAVE 0
END_FUNCTION node_checkpoint_state

/* L0: a JUSTIFIED_STATE work for store.justified_checkpoint, unless one is queued. */
LOCAL_FUNCTION node_justified
    ENTER 0
    ldr     x9, [x19, #Node_flags]
    tbnz    x9, #1, 9f
    ldr     x0, [x20, #Store_justified_checkpoint]      /* a Checkpoint: the epoch, then the root at 8 */
    add     x1, x20, #(Store_justified_checkpoint + 8)
    bl      node_checkpoint_state
    cbz     x0, 9f
    mov     x1, x0
    mov     x0, #NODE_WORK_JUSTIFIED_STATE
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    mov     x5, #0
    bl      node_work
    ldr     x9, [x19, #Node_flags]
    orr     x9, x9, #NODE_FLAG_JUSTIFIED_PENDING
    str     x9, [x19, #Node_flags]
9:  LEAVE 0
END_FUNCTION node_justified

/*
 * L0: the import of the block of index x0 when its parent has a post-state; a block whose parent
 * is invalid becomes invalid. With NODE_FLAG_ENGINE a block of bellatrix or later takes
 * NODE_BLOCK_PAYLOAD instead: its import waits for engine_newPayload. x21 index, x22 entry.
 */
LOCAL_FUNCTION node_try_import
    ENTER 0
    mov     x21, x0
    PART    x22, x9, x19, Node_blocks
    mov     x9, #NodeBlock__mem
    madd    x22, x21, x9, x22
    add     x0, x22, #NodeBlock_parent_root
    bl      node_find_block
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_INVALID
    b.eq    8f
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    9f
    ldr     x9, [x19, #Node_flags]
    tbz     x9, #4, 1f                      /* NODE_FLAG_ENGINE */
    ldr     x0, [x22, #NodeBlock_slot]
    add     x1, x19, #Node_config
    bl      node_fork
    cmp     x0, #FORK_BELLATRIX
    b.lo    1f
    mov     x9, #NODE_BLOCK_PAYLOAD
    str     x9, [x22, #NodeBlock_status]
    str     xzr, [x22, #NodeBlock_retry]
    LEAVE 0
1:  ldr     x9, [x19, #Node_flags]          /* VALID, or NOT_VALIDATED with NODE_FLAG_OPTIMISTIC */
    tst     x9, #NODE_FLAG_OPTIMISTIC
    mov     x1, #PAYLOAD_STATUS_VALID
    mov     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    csel    x1, x9, x1, ne
    mov     x0, x21
    bl      node_import_now
    LEAVE 0
8:  mov     x9, #NODE_BLOCK_INVALID
    str     x9, [x22, #NodeBlock_status]
9:  LEAVE 0
END_FUNCTION node_try_import

/*
 * L0: the import of the block of index x0, whose parent is imported, with the payload status x1:
 * a copy of the parent's post-state and an IMPORT_BLOCK work. x21 index, x22 entry, x23 the
 * parent's state id.
 */
LOCAL_FUNCTION node_import_now
    ENTER 0
    mov     x21, x0
    PART    x22, x9, x19, Node_blocks
    mov     x9, #NodeBlock__mem
    madd    x22, x21, x9, x22
    str     x1, [x22, #NodeBlock_payload_status]
    add     x0, x22, #NodeBlock_parent_root
    bl      node_find_block
    cmn     x0, #1
    b.eq    9f
    ldr     x23, [x1, #NodeBlock_state_id]
    bl      node_new_id
    str     x0, [x22, #NodeBlock_state_id]
    mov     x2, x0
    mov     x0, #NODE_ACT_STATE_COPY
    mov     x1, x23
    bl      node_ids
    mov     x9, #NODE_BLOCK_IMPORTING
    str     x9, [x22, #NodeBlock_status]
    mov     x0, #NODE_WORK_IMPORT_BLOCK
    ldr     x1, [x22, #NodeBlock_state_id]
    mov     x2, #0
    ldr     x3, [x22, #NodeBlock_data_id]
    mov     x4, x21
    mov     x5, #0
    bl      node_work
9:  LEAVE 0
END_FUNCTION node_import_now

/* L0: x0 = the index of the store's node whose root is at x0, or 2^64 - 1; x1 = its entry. Uses x9-x15. */
LOCAL_FUNCTION node_store_find
    UNWIND_END_PROLOGUE
    PART    x9, x10, x20, Store_blocks
    mov     x11, #0
1:  cmp     x11, x10
    b.hs    3f
    ldp     x12, x13, [x9]
    ldp     x14, x15, [x0]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.ne    2f
    ldp     x12, x13, [x9, #16]
    ldp     x14, x15, [x0, #16]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.eq    4f
2:  add     x9, x9, #BlockNode__mem
    add     x11, x11, #1
    b       1b
3:  mov     x0, #-1
    ret
4:  mov     x0, x11
    mov     x1, x9
    ret
END_FUNCTION node_store_find

/*
 * L0: with NODE_FLAG_ENGINE, the next engine call when none is in flight and the store's slot is
 * at least engine_wait: a NEW_PAYLOAD work for the first block in NODE_BLOCK_PAYLOAD whose retry
 * is at most the slot, else with NODE_FLAG_FCU from bellatrix on a FORKCHOICE work. x21 an entry,
 * x22 the count, x25 the slot, x26 the index.
 */
LOCAL_FUNCTION node_engine_next
    ENTER 0
    ldr     x9, [x19, #Node_flags]
    tbz     x9, #4, 9f
    ldr     x9, [x19, #Node_engine_method]
    cbnz    x9, 9f
    mov     x0, x20
    bl      node_store_slot
    mov     x25, x0
    ldr     x9, [x19, #Node_engine_wait]
    cmp     x25, x9
    b.lo    9f
    PART    x21, x22, x19, Node_blocks
    mov     x26, #0
1:  cmp     x26, x22
    b.hs    3f
    ldr     x9, [x21, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_PAYLOAD
    b.ne    2f
    ldr     x9, [x21, #NodeBlock_retry]
    cmp     x9, x25
    b.hi    2f
    mov     x9, #NODE_BLOCK_EXECUTING
    str     x9, [x21, #NodeBlock_status]
    mov     x9, #ENGINE_METHOD_NEW_PAYLOAD
    str     x9, [x19, #Node_engine_method]
    str     x26, [x19, #Node_engine_target]
    ldr     x5, [x19, #Node_engine_id]
    add     x9, x5, #1
    str     x9, [x19, #Node_engine_id]
    mov     x0, #NODE_WORK_NEW_PAYLOAD
    mov     x1, #0
    mov     x2, #0
    ldr     x3, [x21, #NodeBlock_data_id]
    mov     x4, x26
    bl      node_work
    LEAVE 0
2:  add     x21, x21, #NodeBlock__mem
    add     x26, x26, #1
    b       1b
3:  ldr     x9, [x19, #Node_flags]
    tbz     x9, #5, 9f                      /* NODE_FLAG_FCU */
    mov     x0, x25
    add     x1, x19, #Node_config
    bl      node_fork
    cmp     x0, #FORK_BELLATRIX
    b.lo    9f
    ldr     x9, [x19, #Node_flags]
    bic     x9, x9, #NODE_FLAG_FCU
    str     x9, [x19, #Node_flags]
    mov     x9, #ENGINE_METHOD_FORKCHOICE_UPDATED
    str     x9, [x19, #Node_engine_method]
    ldr     x5, [x19, #Node_engine_id]
    add     x9, x5, #1
    str     x9, [x19, #Node_engine_id]
    mov     x0, #NODE_WORK_FORKCHOICE
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    bl      node_work
9:  LEAVE 0
END_FUNCTION node_engine_next

/* L0: the import of each waiting block whose parent is the block of the entry x0. x21 the root, x22 index, x25 count. */
LOCAL_FUNCTION node_children
    ENTER 0
    mov     x21, x0
    mov     x22, #0
1:  ldr     x25, [x19, #(Node_blocks + 8)]
    cmp     x22, x25
    b.hs    9f
    PART    x9, x10, x19, Node_blocks
    mov     x10, #NodeBlock__mem
    madd    x9, x22, x10, x9
    ldr     x10, [x9, #NodeBlock_status]
    cmp     x10, #NODE_BLOCK_WAITING
    b.ne    2f
    ldp     x10, x11, [x9, #NodeBlock_parent_root]
    ldp     x12, x13, [x21]
    cmp     x10, x12
    ccmp    x11, x13, #0, eq
    b.ne    2f
    ldp     x10, x11, [x9, #(NodeBlock_parent_root + 16)]
    ldp     x12, x13, [x21, #16]
    cmp     x10, x12
    ccmp    x11, x13, #0, eq
    b.ne    2f
    mov     x0, x22
    bl      node_try_import
2:  add     x22, x22, #1
    b       1b
9:  LEAVE 0
END_FUNCTION node_children

/* L0: a BYTES_PUT action of the ByteList x0 with a new id: x0 = the id. x21 the ByteList, x22 the id. */
LOCAL_FUNCTION node_put
    ENTER 0
    mov     x21, x0
    bl      node_new_id
    mov     x22, x0
    ldr     x9, [x21, #16]                  /* the header, 16 id, then a ByteList: size, offset 24, count, bytes */
    add     x1, x9, #(48 + 7)
    and     x1, x1, #~7
    mov     x0, #NODE_ACT_BYTES_PUT
    bl      node_act
    str     x22, [x0, #16]
    ldr     x9, [x0]
    sub     x9, x9, #24
    mov     x10, #24
    ldr     x11, [x21, #16]
    stp     x9, x10, [x0, #24]
    str     x11, [x0, #40]
    add     x0, x0, #48
    ldr     x9, [x21, #8]
    add     x1, x21, x9
    mov     x2, x11
    bl      lantern_copy
    mov     x0, x22
    LEAVE 0
END_FUNCTION node_put

/* L0: x0 = the node's NODE_BLOB_VALID entry of the root at x0 and the index x1, or 0. Uses x9-x15. */
LOCAL_FUNCTION node_blob_held
    UNWIND_END_PROLOGUE
    PART    x9, x10, x19, Node_blobs
1:  cbz     x10, 3f
    ldr     x11, [x9, #NodeBlob_status]
    cmp     x11, #NODE_BLOB_VALID
    b.ne    2f
    ldr     x11, [x9, #NodeBlob_index]
    cmp     x11, x1
    b.ne    2f
    ldp     x12, x13, [x9]
    ldp     x14, x15, [x0]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.ne    2f
    ldp     x12, x13, [x9, #16]
    ldp     x14, x15, [x0, #16]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.ne    2f
    mov     x0, x9
    ret
2:  add     x9, x9, #NodeBlob__mem
    sub     x10, x10, #1
    b       1b
3:  mov     x0, #0
    ret
END_FUNCTION node_blob_held

/*
 * L0: x0 = 1 when the node holds a NODE_BLOB_VALID entry of the root at x0 for each index below
 * x1 (1 to NODE_BLOB_MAX), else 0. Uses x9-x16.
 */
LOCAL_FUNCTION node_blobs_held
    UNWIND_END_PROLOGUE
    PART    x9, x10, x19, Node_blobs
    mov     x11, #0                         /* a bit for each index held */
1:  cbz     x10, 3f
    ldr     x12, [x9, #NodeBlob_status]
    cmp     x12, #NODE_BLOB_VALID
    b.ne    2f
    ldr     x12, [x9, #NodeBlob_index]
    cmp     x12, x1
    b.hs    2f
    ldp     x13, x14, [x9]
    ldp     x15, x16, [x0]
    cmp     x13, x15
    ccmp    x14, x16, #0, eq
    b.ne    2f
    ldp     x13, x14, [x9, #16]
    ldp     x15, x16, [x0, #16]
    cmp     x13, x15
    ccmp    x14, x16, #0, eq
    b.ne    2f
    mov     x13, #1
    lsl     x13, x13, x12
    orr     x11, x11, x13
2:  add     x9, x9, #NodeBlob__mem
    sub     x10, x10, #1
    b       1b
3:  mov     x12, #64                        /* every index below x1 */
    sub     x12, x12, x1
    mov     x13, #-1
    lsr     x13, x13, x12
    cmp     x11, x13
    cset    x0, eq
    ret
END_FUNCTION node_blobs_held

/*
 * L0: the block of index x0, from the network, waits for its blobs: NODE_BLOCK_BLOBS while it
 * needs blobs the node does not hold; else data_available 1, NODE_BLOCK_WAITING and its import.
 * It needs blobs when its fork is deneb or electra, its blob count is 1 to the fork's limit and
 * NODE_BLOB_MAX, and its epoch is from max(the store's epoch - MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS,
 * DENEB_FORK_EPOCH) on. x21 the index, x22 the entry, x25 the count.
 */
LOCAL_FUNCTION node_await
    ENTER 0
    mov     x21, x0
    PART    x22, x9, x19, Node_blocks
    mov     x9, #NodeBlock__mem
    madd    x22, x21, x9, x22
    ldr     x25, [x22, #NodeBlock_blobs]
    cbz     x25, 5f
    cmp     x25, #NODE_BLOB_MAX
    b.hi    5f
    ldr     x0, [x22, #NodeBlock_slot]
    add     x1, x19, #Node_config
    bl      node_fork
    cmp     x0, #FORK_DENEB
    b.eq    1f
    cmp     x0, #FORK_ELECTRA
    b.ne    5f
    LDQ     x9, x19, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
    b       2f
1:  LDQ     x9, x19, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK
2:  cmp     x25, x9
    b.hi    5f
    mov     x0, x20                         /* the blob window */
    bl      node_store_slot
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x0, x0, x9
    LDQ     x10, x19, Node_config + CONFIG_MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS
    subs    x0, x0, x10
    csel    x0, xzr, x0, lo
    ldr     x10, [x19, #(Node_config + 16 * FORK_DENEB)]
    cmp     x0, x10
    csel    x0, x10, x0, lo
    ldr     x9, [x22, #NodeBlock_slot]
    mov     x10, #SLOTS_PER_EPOCH
    udiv    x9, x9, x10
    cmp     x9, x0
    b.lo    5f
    mov     x0, x22
    mov     x1, x25
    bl      node_blobs_held
    cbnz    x0, 5f
    mov     x9, #NODE_BLOCK_BLOBS
    str     x9, [x22, #NodeBlock_status]
    LEAVE 0
5:  mov     x9, #1
    str     x9, [x22, #NodeBlock_data_available]
    mov     x9, #NODE_BLOCK_WAITING
    str     x9, [x22, #NodeBlock_status]
    mov     x0, x21
    bl      node_try_import
    LEAVE 0
END_FUNCTION node_await

/*
 * L0: the engine call in flight failed: an engine_newPayload's block takes NODE_BLOCK_PAYLOAD with
 * retry the store's slot + 1, an engine_forkchoiceUpdated sets NODE_FLAG_FCU again; engine_wait
 * becomes the slot + 1 and the call ends. x21 the slot + 1.
 */
LOCAL_FUNCTION node_engine_failed
    ENTER 0
    mov     x0, x20
    bl      node_store_slot
    add     x21, x0, #1
    str     x21, [x19, #Node_engine_wait]
    ldr     x9, [x19, #Node_engine_method]
    str     xzr, [x19, #Node_engine_method]
    cmp     x9, #ENGINE_METHOD_FORKCHOICE_UPDATED
    b.ne    1f
    ldr     x9, [x19, #Node_flags]
    orr     x9, x9, #NODE_FLAG_FCU
    str     x9, [x19, #Node_flags]
    LEAVE 0
1:  cmp     x9, #ENGINE_METHOD_NEW_PAYLOAD
    b.ne    9f
    ldr     x0, [x19, #Node_engine_target]
    bl      node_payload_retry
9:  LEAVE 0
END_FUNCTION node_engine_failed

/* L0: the block of index x0, if NODE_BLOCK_EXECUTING, takes NODE_BLOCK_PAYLOAD with retry the store's slot + 1. x21 the entry. */
LOCAL_FUNCTION node_payload_retry
    ENTER 0
    PART    x21, x9, x19, Node_blocks
    cmp     x0, x9
    b.hs    9f
    mov     x9, #NodeBlock__mem
    madd    x21, x0, x9, x21
    ldr     x9, [x21, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_EXECUTING
    b.ne    9f
    mov     x9, #NODE_BLOCK_PAYLOAD
    str     x9, [x21, #NodeBlock_status]
    mov     x0, x20
    bl      node_store_slot
    add     x0, x0, #1
    str     x0, [x21, #NodeBlock_retry]
9:  LEAVE 0
END_FUNCTION node_payload_retry

/*
 * L0: latestValidHash (optimistic-sync.md) from the store's node x0: up its chain by parent, each
 * node whose block_hash is not the hash at x1 gets store_payload_status INVALIDATED, until the
 * node with that hash; a zero hash stops at the first zero block_hash. With x1 0 (null), or a hash
 * the chain does not have, only the node x2 (2^64 - 1 for none) gets it. x21 start, x22 the hash,
 * x25 a node, x26 the node x2. Locals: L a node, L+8 a status, L+16 a result.
 */
LOCAL_FUNCTION node_lvh
    ENTER 32
    mov     x21, x0
    mov     x22, x1
    mov     x26, x2
    cbz     x22, 5f
    mov     x25, x21                        /* the node of the hash, up the chain */
1:  PART    x9, x10, x20, Store_blocks
    cmp     x25, x10
    b.hs    5f
    mov     x11, #BlockNode__mem
    madd    x9, x25, x11, x9
    ldp     x12, x13, [x9, #BlockNode_block_hash]
    ldp     x14, x15, [x22]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.ne    2f
    ldp     x12, x13, [x9, #(BlockNode_block_hash + 16)]
    ldp     x14, x15, [x22, #16]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.eq    3f
2:  ldr     x25, [x9, #BlockNode_parent]
    b       1b
3:  cmp     x21, x25                        /* found at x25: each node from x21 below it */
    b.eq    9f
    str     x21, [sp, #L]
    mov     x9, #PAYLOAD_STATUS_INVALIDATED
    str     x9, [sp, #(L + 8)]
    mov     x0, x20
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    add     x3, sp, #(L + 16)
    bl      lantern_store_payload_status
    PART    x9, x10, x20, Store_blocks
    mov     x11, #BlockNode__mem
    madd    x9, x21, x11, x9
    ldr     x21, [x9, #BlockNode_parent]
    b       3b
5:  cmn     x26, #1                         /* null, or not found: the node in question */
    b.eq    9f
    str     x26, [sp, #L]
    mov     x9, #PAYLOAD_STATUS_INVALIDATED
    str     x9, [sp, #(L + 8)]
    mov     x0, x20
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    add     x3, sp, #(L + 16)
    bl      lantern_store_payload_status
9:  LEAVE 32
END_FUNCTION node_lvh

/*
 * L0: the bytes of engine_in: a whole HTTP response of the call in flight ends it. x21 engine_in,
 * x22 the method, x25 the scratch size, restored on return, x26 the body's ByteList, x27 a block
 * entry. Locals: L an HttpResponse (16), L+16 eof, L+24 the method, L+32 an EngineResponse (96),
 * L+128 a status, L+136 a result.
 */
LOCAL_FUNCTION node_engine_read
    ENTER 144
    ldr     x21, [x19, #Node_engine_in]
    add     x21, x19, x21
    ldr     x22, [x19, #Node_engine_method]
    cbz     x22, 8f                         /* no call in flight: the bytes go */
    ldr     x25, [x23]
    ldr     x9, [x21, #16]                  /* the body's ByteList at the end of scratch, as long as the bytes */
    add     x9, x9, #(24 + 7)
    and     x9, x9, #~7
    subs    x10, x25, x9
    b.lo    7f
    str     x10, [x23]
    add     x26, x23, x10
    mov     x11, #24
    stp     x9, x11, [x26]
    str     xzr, [x26, #16]
    str     xzr, [sp, #(L + 16)]
    mov     x0, x21
    add     x1, sp, #(L + 16)
    mov     x2, x26
    add     x3, sp, #L
    bl      lantern_http_parse_response
    cmp     x0, #LANTERN_HTTP_MORE
    b.eq    6f
    cbnz    x0, 7f
    ldr     x9, [sp, #L]                    /* HttpResponse status */
    cmp     x9, #200
    b.ne    70f
    str     x22, [sp, #(L + 24)]
    mov     x0, x26
    add     x1, sp, #(L + 24)
    add     x2, sp, #(L + 32)
    bl      lantern_engine_parse_response
    cbnz    x0, 70f
    ldr     x9, [sp, #(L + 32 + EngineResponse_error)]
    cbnz    x9, 70f
    ldr     x9, [sp, #(L + 32 + EngineResponse_id)]
    ldr     x10, [x19, #Node_engine_id]
    sub     x10, x10, #1
    cmp     x9, x10
    b.ne    70f
    mov     x0, x21
    ldr     x1, [sp, #(L + 8)]
    bl      node_engine_consume
    str     x25, [x23]
    str     xzr, [x19, #Node_engine_method] /* the call ends */
    ldr     x9, [sp, #(L + 32 + EngineResponse_status)]
    cmp     x22, #ENGINE_METHOD_NEW_PAYLOAD
    b.ne    40f
    ldr     x0, [x19, #Node_engine_target]  /* engine_newPayload: its block */
    PART    x27, x10, x19, Node_blocks
    cmp     x0, x10
    b.hs    9f
    mov     x10, #NodeBlock__mem
    madd    x27, x0, x10, x27
    ldr     x10, [x27, #NodeBlock_status]
    cmp     x10, #NODE_BLOCK_EXECUTING
    b.ne    9f
    cmp     x9, #ENGINE_STATUS_VALID
    b.ne    20f
    mov     x1, #PAYLOAD_STATUS_VALID       /* VALID: the import */
    bl      node_import_now
    b       9f
20: cmp     x9, #ENGINE_STATUS_SYNCING
    ccmp    x9, #ENGINE_STATUS_ACCEPTED, #4, ne
    b.ne    30f
    add     x0, x27, #NodeBlock_parent_root /* SYNCING, ACCEPTED: optimistic when a candidate */
    bl      node_store_find
    cmn     x0, #1
    b.eq    21f
    ldp     x10, x11, [x1, #BlockNode_block_hash]
    ldp     x12, x13, [x1, #(BlockNode_block_hash + 16)]
    orr     x10, x10, x11
    orr     x12, x12, x13
    orr     x10, x10, x12
    cbnz    x10, 22f
21: mov     x0, x20
    bl      node_store_slot
    ldr     x10, [x27, #NodeBlock_slot]
    add     x10, x10, #SAFE_SLOTS_TO_IMPORT_OPTIMISTICALLY
    cmp     x10, x0
    b.ls    22f
    ldr     x0, [x19, #Node_engine_target]  /* no candidate: again in a later slot */
    bl      node_payload_retry
    b       9f
22: ldr     x0, [x19, #Node_engine_target]
    mov     x1, #PAYLOAD_STATUS_NOT_VALIDATED
    bl      node_import_now
    b       9f
30: mov     x10, #NODE_BLOCK_INVALID        /* INVALID, INVALID_BLOCK_HASH: the block is invalid, latestValidHash from its parent */
    str     x10, [x27, #NodeBlock_status]
    mov     x0, #NODE_ACT_BYTES_FREE
    ldr     x1, [x27, #NodeBlock_data_id]
    mov     x2, #0
    bl      node_ids
    add     x0, x27, #NodeBlock_parent_root
    bl      node_store_find
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [sp, #(L + 32 + EngineResponse_has_latest_valid_hash)]
    add     x1, sp, #(L + 32 + EngineResponse_latest_valid_hash)
    cmp     x9, #0
    csel    x1, xzr, x1, eq
    mov     x2, #-1
    bl      node_lvh
    b       9f
40: add     x0, x19, #Node_head_root        /* engine_forkchoiceUpdated: of the head */
    bl      node_store_find
    cmn     x0, #1
    b.eq    9f
    mov     x27, x0
    ldr     x9, [sp, #(L + 32 + EngineResponse_status)]
    cmp     x9, #ENGINE_STATUS_VALID
    b.ne    41f
    str     x27, [sp, #(L + 128)]
    mov     x9, #PAYLOAD_STATUS_VALID
    str     x9, [sp, #(L + 136)]
    mov     x0, x20
    add     x1, sp, #(L + 128)
    add     x2, sp, #(L + 136)
    add     x3, sp, #(L + 16)
    bl      lantern_store_payload_status
    b       9f
41: cmp     x9, #ENGINE_STATUS_INVALID
    ccmp    x9, #ENGINE_STATUS_INVALID_BLOCK_HASH, #4, ne
    b.ne    9f
    ldr     x9, [sp, #(L + 32 + EngineResponse_has_latest_valid_hash)]
    add     x1, sp, #(L + 32 + EngineResponse_latest_valid_hash)
    cmp     x9, #0
    csel    x1, xzr, x1, eq
    mov     x0, x27
    mov     x2, x27
    bl      node_lvh
9:  LEAVE 144
6:  str     x25, [x23]                      /* part of a response: more bytes */
    LEAVE 144
70: mov     x0, x21                         /* a failed call, its response read */
    ldr     x1, [sp, #(L + 8)]
    bl      node_engine_consume
7:  str     x25, [x23]
    bl      node_engine_failed
8:  ldr     x21, [x19, #Node_engine_in]     /* the bytes left go */
    add     x21, x19, x21
    str     xzr, [x21, #16]
    LEAVE 144
END_FUNCTION node_engine_read

/* L0: the first x1 bytes of the ByteList x0 (engine_in) leave it. */
LOCAL_FUNCTION node_engine_consume
    FRAME 0
    ldr     x9, [x0, #16]
    sub     x2, x9, x1
    str     x2, [x0, #16]
    add     x0, x0, #24
    add     x1, x0, x1
    bl      lantern_copy
    UNFRAME 0
END_FUNCTION node_engine_consume

/* L0: a blob of the root at x0 became NODE_BLOB_VALID: the block of that root in NODE_BLOCK_BLOBS waits for its blobs again. */
LOCAL_FUNCTION node_blob_added
    FRAME 16
    bl      node_find_block
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_BLOBS
    b.ne    9f
    bl      node_await
9:  UNFRAME 16
END_FUNCTION node_blob_added

/* L0: the head: the root of get_head of the fork of the store's slot into the node, or a JUSTIFIED_STATE work. Locals: L the node. */
LOCAL_FUNCTION node_head
    ENTER 16
    mov     x0, x20
    bl      node_store_slot
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x20
    mov     x1, x23
    add     x2, sp, #L
    FORK_CALL get_head
    cmp     x0, #LANTERN_NEED_JUSTIFIED_STATE
    b.ne    1f
    bl      node_justified
    LEAVE 16
1:  cbnz    x0, 9f
    ldr     x9, [sp, #L]
    PART    x10, x11, x20, Store_blocks
    cmp     x9, x11
    b.hs    9f
    mov     x11, #BlockNode__mem
    madd    x10, x9, x11, x10
    add     x9, x19, #Node_head_root
    ldp     x11, x12, [x9]                  /* a new head with NODE_FLAG_ENGINE: a forkchoiceUpdated is due */
    ldp     x13, x14, [x10]
    cmp     x11, x13
    ccmp    x12, x14, #0, eq
    b.ne    2f
    ldp     x11, x12, [x9, #16]
    ldp     x13, x14, [x10, #16]
    cmp     x11, x13
    ccmp    x12, x14, #0, eq
    b.eq    3f
2:  ldr     x11, [x19, #Node_flags]
    tst     x11, #NODE_FLAG_ENGINE
    b.eq    3f
    orr     x11, x11, #NODE_FLAG_FCU
    str     x11, [x19, #Node_flags]
3:  COPY32  x9, x10
9:  LEAVE 16
END_FUNCTION node_head

/*
 * L0: the event x0. x21 the event; x28 the root entry of the step's first pass for a BLOCK
 * event. Locals: L+32 a result, L+40 the index.
 */
LOCAL_FUNCTION node_event
    ENTER 48
    mov     x21, x0
    ldr     x9, [x21, #8]
    cmp     x9, #NODE_EV_TICK
    b.ne    10f
    ldr     x9, [x21, #16]                  /* TICK: on_tick of the fork of the new slot */
    str     x9, [x19, #Node_time_ms]
    ldr     x10, [x20, #Store_genesis_time_ms]
    subs    x9, x9, x10
    csel    x9, xzr, x9, lo
    LDQ     x10, x20, Store_config + CONFIG_SLOT_DURATION_MS
    mov     x0, #0
    cbz     x10, 1f
    udiv    x0, x9, x10
1:  add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x20
    add     x1, x21, #16
    add     x2, sp, #(L + 32)
    FORK_CALL on_tick
    LEAVE 48
10: cmp     x9, #NODE_EV_BLOCK
    b.ne    20f
    mov     x27, x28                        /* BLOCK: its root entry from the step's first pass */
    ldr     x9, [x27]
    cbnz    x9, 19f
    add     x0, x27, #8                     /* a known block: nothing */
    bl      node_find_block
    cmn     x0, #1
    b.ne    19f
    add     x22, x21, #NodeEvent_bytes      /* its bytes, then its entry */
    ldr     x9, [x22, #8]
    add     x25, x22, x9
    mov     x0, x22
    bl      node_put
    mov     x26, x0
    PART    x9, x10, x19, Node_blocks
    str     x10, [sp, #(L + 40)]
    mov     x11, #NodeBlock__mem
    madd    x9, x10, x11, x9
    add     x11, x27, #8
    COPY32  x9, x11
    add     x11, x9, #NodeBlock_parent_root
    add     x12, x25, #116
    ldp     x13, x14, [x12]
    stp     x13, x14, [x11]
    ldp     x13, x14, [x12, #16]
    stp     x13, x14, [x11, #16]
    ldr     x11, [x25, #100]
    str     x11, [x9, #NodeBlock_slot]
    str     x26, [x9, #NodeBlock_data_id]
    str     xzr, [x9, #NodeBlock_state_id]
    mov     x11, #NODE_BLOCK_WAITING
    str     x11, [x9, #NodeBlock_status]
    ldr     x11, [x21, #16]
    str     x11, [x9, #NodeBlock_data_available]
    str     xzr, [x9, #NodeBlock_result]
    str     xzr, [x9, #NodeBlock_blobs]
    add     x10, x10, #1
    str     x10, [x19, #(Node_blocks + 8)]
    ldr     x0, [sp, #(L + 40)]
    bl      node_try_import
19: LEAVE 48
20: cmp     x9, #NODE_EV_ATTESTATION
    b.ne    30f
    add     x22, x21, #NodeEvent_bytes      /* ATTESTATION: its target checkpoint state, if made */
    ldr     x9, [x22, #16]
    cmp     x9, #(4 + 128 + 96)
    b.lo    29f
    mov     x0, x22
    bl      node_put
    mov     x26, x0
    ldr     x9, [x22, #8]
    add     x25, x22, x9
    ldr     x0, [x25, #92]
    add     x1, x25, #100
    bl      node_find_checkpoint
    mov     x9, #0
    cmn     x0, #1
    b.eq    21f
    ldr     x9, [x1, #NodeCheckpoint_state_id]
21: mov     x1, x9
    mov     x0, #NODE_WORK_ATTESTATION
    mov     x2, #0
    mov     x3, x26
    mov     x4, #0
    ldr     x5, [x21, #16]                  /* is_from_block */
    bl      node_work
29: LEAVE 48
30: cmp     x9, #NODE_EV_ATTESTER_SLASHING
    b.ne    40f
    add     x0, x20, #(Store_justified_checkpoint + 8)   /* the justified root's post-state */
    bl      node_find_block
    cmn     x0, #1
    b.eq    39f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    39f
    ldr     x25, [x1, #NodeBlock_state_id]
    add     x0, x21, #NodeEvent_bytes
    bl      node_put
    mov     x3, x0
    mov     x0, #NODE_WORK_ATTESTER_SLASHING
    mov     x1, x25
    mov     x2, #0
    mov     x4, #0
    mov     x5, #0
    bl      node_work
39: LEAVE 48
40: cmp     x9, #NODE_EV_POW_BLOCK
    b.ne    45f
    add     x22, x21, #NodeEvent_bytes      /* POW_BLOCK: a PowBlock of the node */
    ldr     x9, [x22, #16]
    cmp     x9, #POW_BLOCK_BYTES
    b.ne    49f
    PART    x10, x11, x19, Node_pow_blocks
    mov     x12, #POW_BLOCK_BYTES
    madd    x0, x11, x12, x10
    add     x11, x11, #1
    str     x11, [x19, #(Node_pow_blocks + 8)]
    ldr     x9, [x22, #8]
    add     x1, x22, x9
    mov     x2, #POW_BLOCK_BYTES
    bl      lantern_copy
49: LEAVE 48
45: cmp     x9, #NODE_EV_ENGINE
    b.ne    47f
    ldr     x9, [x21, #16]
    cbz     x9, 46f
    bl      node_engine_failed              /* ENGINE 1: the connection failed */
    ldr     x9, [x19, #Node_engine_in]
    add     x9, x19, x9
    str     xzr, [x9, #16]
    LEAVE 48
46: add     x22, x21, #NodeEvent_bytes      /* ENGINE 0: its bytes join engine_in */
    ldr     x25, [x19, #Node_engine_in]
    add     x25, x19, x25
    ldr     x9, [x25, #16]
    add     x0, x25, #24
    add     x0, x0, x9
    ldr     x10, [x22, #8]
    add     x1, x22, x10
    ldr     x2, [x22, #16]
    add     x9, x9, x2
    str     x9, [x25, #16]
    bl      lantern_copy
    bl      node_engine_read
    LEAVE 48
47: cmp     x9, #NODE_EV_ENR
    b.ne    50f
    mov     x0, x21                         /* ENR: a record discv5 found */
    bl      node_enr
    LEAVE 48
50: ldr     x9, [x21, #NodeAction_work_kind]    /* WORK_DONE */
    ldr     x10, [x21, #NodeEvent_result]
    cmp     x9, #NODE_WORK_IMPORT_BLOCK
    b.ne    60f
    ldr     x0, [x21, #NodeAction_target]
    PART    x22, x11, x19, Node_blocks
    cmp     x0, x11
    b.hs    59f
    mov     x11, #NodeBlock__mem
    madd    x22, x0, x11, x22
    str     x10, [x22, #NodeBlock_result]
    cmp     x10, #LANTERN_NEED_JUSTIFIED_STATE
    b.ne    51f
    bl      node_justified                  /* the justified state, then the same import again */
    ldp     x0, x1, [x21, #NodeAction_work_kind]
    ldr     x2, [x21, #NodeAction_state_b]
    ldr     x3, [x21, #NodeAction_data]
    ldp     x4, x5, [x21, #NodeAction_target]
    bl      node_work
    ldr     x9, [x21, #NodeAction_state_c]
    str     x9, [x0, #NodeAction_state_c]
    LEAVE 48
51: cbnz    x10, 52f
    mov     x9, #NODE_BLOCK_IMPORTED        /* imported: then its waiting children */
    str     x9, [x22, #NodeBlock_status]
    mov     x0, x22
    bl      node_children
    LEAVE 48
52: mov     x9, #NODE_BLOCK_INVALID         /* invalid: its state copy is freed */
    str     x9, [x22, #NodeBlock_status]
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [x22, #NodeBlock_state_id]
    mov     x2, #0
    bl      node_ids
    str     xzr, [x22, #NodeBlock_state_id]
59: LEAVE 48
60: cmp     x9, #NODE_WORK_JUSTIFIED_STATE
    b.ne    61f
    ldr     x9, [x19, #Node_flags]
    bic     x9, x9, #NODE_FLAG_JUSTIFIED_PENDING
    str     x9, [x19, #Node_flags]
    LEAVE 48
61: cmp     x9, #NODE_WORK_ATTESTATION
    b.ne    62f
    cmp     x10, #LANTERN_NEED_TARGET_STATE
    b.ne    70f
    ldr     x0, [x21, #NodeEvent_checkpoint]    /* the target state, then the same attestation again */
    add     x1, x21, #(NodeEvent_checkpoint + 8)
    bl      node_checkpoint_state
    cbz     x0, 71f
    mov     x1, x0
    mov     x0, #NODE_WORK_ATTESTATION
    ldr     x2, [x21, #NodeAction_state_b]
    ldr     x3, [x21, #NodeAction_data]
    ldp     x4, x5, [x21, #NodeAction_target]
    bl      node_work
    LEAVE 48
62: cmp     x9, #NODE_WORK_SERVE               /* SERVE: the chunk to its stream, then the next block or the close */
    b.ne    63f
    ldr     x0, [x21, #NodeAction_target]
    bl      node_find_stream
    cmn     x0, #1
    b.eq    69f
    mov     x22, x1
    ldr     x9, [x21, #NodeEvent_result]
    cbnz    x9, 68f
    ldr     x25, [x21, #(NodeEvent_chunk + 16)]
    add     x0, x25, #(32 + 7)
    and     x0, x0, #~7
    str     x0, [sp, #(L + 32)]
    bl      node_out
    cbz     x0, 68f
    ldr     x9, [sp, #(L + 32)]
    mov     x10, #LIBP2P_EVENT_STREAM_WRITE
    stp     x9, x10, [x0]
    ldr     x10, [x22, #NodeStream_handle]
    stp     x10, x25, [x0, #16]
    add     x0, x0, #32
    add     x1, x21, #(NodeEvent_chunk + 24)
    mov     x2, x25
    bl      lantern_copy
    ldr     x9, [x22, #NodeStream_next]
    add     x9, x9, #1
    str     x9, [x22, #NodeStream_next]
    ldr     x10, [x22, #(NodeStream_list + 16)]
    lsr     x10, x10, #3
    cmp     x9, x10
    b.hs    67f
    mov     x9, #NODE_STREAM_SERVE
    str     x9, [x22, #NodeStream_state]
    LEAVE 48
67: mov     x0, #LIBP2P_EVENT_STREAM_CLOSE
    ldr     x1, [x22, #NodeStream_handle]
    bl      node_out_handle
    mov     x0, x22
    bl      node_drop_stream
69: LEAVE 48
68: mov     x0, #LIBP2P_EVENT_STREAM_RESET     /* no chunk, or no room for it: a reset */
    ldr     x1, [x22, #NodeStream_handle]
    bl      node_out_handle
    mov     x0, x22
    bl      node_drop_stream
    LEAVE 48
63: cmp     x9, #NODE_WORK_GOSSIP              /* GOSSIP: the VALIDATION, then a valid block to import */
    b.ne    75f
    mov     x0, #LIBP2P_ACCEPT
    mov     x11, #LIBP2P_IGNORE
    mov     x12, #LIBP2P_REJECT
    cmp     x10, #LANTERN_GOSSIP_REJECT
    csel    x11, x12, x11, eq
    cmp     x10, #LANTERN_VALID
    csel    x25, x0, x11, eq
    ldr     x0, [x21, #NodeAction_target]
    mov     x1, x25
    bl      node_validation
    ldr     x1, [x21, #NodeAction_state_b]     /* the proposer state */
    cbz     x1, 64f
    mov     x0, #NODE_ACT_STATE_FREE
    mov     x2, #0
    bl      node_ids
64: ldr     x0, [x21, #NodeAction_target]
    bl      node_find_message
    cmn     x0, #1
    b.eq    66f
    mov     x22, x1
    cmp     x25, #LIBP2P_ACCEPT
    b.ne    65f
    ldr     x9, [x22, #NodeMessage_topic]
    cmp     x9, #GOSSIP_ATTESTER_SLASHING
    b.ne    641f
    ldr     x1, [x21, #NodeAction_state_c]     /* a valid attester slashing keeps the bytes: on_attester_slashing with the justified root's state */
    cbz     x1, 65f
    mov     x0, #NODE_WORK_ATTESTER_SLASHING
    mov     x2, #0
    ldr     x3, [x21, #NodeAction_data]
    mov     x4, #0
    mov     x5, #0
    bl      node_work
    mov     x0, x22
    bl      node_drop_message
    LEAVE 48
641: cmp    x9, #GOSSIP_BEACON_BLOCK
    b.ne    642f
    add     x0, x21, #NodeEvent_root           /* a new block keeps the bytes */
    bl      node_find_block
    cmn     x0, #1
    b.ne    65f
    PART    x9, x10, x19, Node_blocks
    str     x10, [sp, #(L + 40)]
    mov     x11, #NodeBlock__mem
    madd    x9, x10, x11, x9
    add     x11, x21, #NodeEvent_root
    COPY32  x9, x11
    add     x11, x9, #NodeBlock_parent_root
    add     x12, x22, #NodeMessage_parent_root
    COPY32  x11, x12
    ldr     x11, [x22, #NodeMessage_slot]
    str     x11, [x9, #NodeBlock_slot]
    ldr     x11, [x21, #NodeAction_data]
    str     x11, [x9, #NodeBlock_data_id]
    str     xzr, [x9, #NodeBlock_state_id]
    mov     x11, #NODE_BLOCK_WAITING
    str     x11, [x9, #NodeBlock_status]
    str     xzr, [x9, #NodeBlock_data_available]
    str     xzr, [x9, #NodeBlock_result]
    ldr     x11, [x21, #NodeEvent_index]
    str     x11, [x9, #NodeBlock_blobs]
    add     x10, x10, #1
    str     x10, [x19, #(Node_blocks + 8)]
    mov     x0, x22
    bl      node_drop_message
    ldr     x0, [sp, #(L + 40)]
    bl      node_await
    LEAVE 48
642: cmp    x9, #GOSSIP_BLOB_SIDECAR           /* a new valid sidecar keeps the bytes */
    b.ne    65f
    add     x0, x21, #NodeEvent_root
    ldr     x1, [x21, #NodeEvent_index]
    bl      node_blob_held
    cbnz    x0, 65f
    PART    x9, x10, x19, Node_blobs
    mov     x11, #NodeBlob__mem
    madd    x9, x10, x11, x9
    add     x11, x21, #NodeEvent_root
    COPY32  x9, x11
    ldr     x11, [x21, #NodeEvent_index]
    str     x11, [x9, #NodeBlob_index]
    ldr     x11, [x22, #NodeMessage_slot]
    str     x11, [x9, #NodeBlob_slot]
    ldr     x11, [x21, #NodeAction_data]
    str     x11, [x9, #NodeBlob_data_id]
    mov     x11, #NODE_BLOB_VALID
    str     x11, [x9, #NodeBlob_status]
    add     x10, x10, #1
    str     x10, [x19, #(Node_blobs + 8)]
    mov     x0, x22
    bl      node_drop_message
    add     x0, x21, #NodeEvent_root
    bl      node_blob_added
    LEAVE 48
65: mov     x0, x22
    bl      node_drop_message
66: mov     x0, #NODE_ACT_BYTES_FREE           /* else its bytes go */
    ldr     x1, [x21, #NodeAction_data]
    mov     x2, #0
    bl      node_ids
    LEAVE 48
75: cmp     x9, #NODE_WORK_SYNC_BLOCK          /* SYNC_BLOCK: the root of a block of a response */
    b.ne    77f
    ldr     x0, [x21, #NodeAction_target]
    PART    x9, x11, x19, Node_blocks
    cmp     x0, x11
    b.hs    79f
    mov     x12, #NodeBlock__mem
    madd    x22, x0, x12, x9
    str     x0, [sp, #(L + 40)]
    ldr     x9, [x22, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_HASHING
    b.ne    79f
    cbnz    x10, 76f
    add     x0, x21, #NodeEvent_root           /* a new root: the block waits for its parent */
    bl      node_find_block
    cmn     x0, #1
    b.ne    76f
    add     x9, x21, #NodeEvent_root           /* a new root: the block waits for its blobs, then its parent */
    COPY32  x22, x9
    ldr     x9, [x21, #NodeEvent_index]
    str     x9, [x22, #NodeBlock_blobs]
    str     xzr, [x22, #NodeBlock_data_available]
    ldr     x0, [sp, #(L + 40)]
    bl      node_await
    LEAVE 48
76: mov     x9, #NODE_BLOCK_INVALID            /* not a block, or a known root: invalid, its bytes go */
    str     x9, [x22, #NodeBlock_status]
    mov     x0, #NODE_ACT_BYTES_FREE
    ldr     x1, [x22, #NodeBlock_data_id]
    mov     x2, #0
    bl      node_ids
    LEAVE 48
77: cmp     x9, #NODE_WORK_BLOB                /* BLOB: a sidecar of a response, checked */
    b.ne    85f
    ldr     x0, [x21, #NodeAction_target]
    PART    x9, x11, x19, Node_blobs
    cmp     x0, x11
    b.hs    79f
    mov     x12, #NodeBlob__mem
    madd    x22, x0, x12, x9
    ldr     x9, [x22, #NodeBlob_status]
    cmp     x9, #NODE_BLOB_VERIFYING
    b.ne    79f
    cbnz    x10, 78f
    add     x0, x21, #NodeEvent_root           /* valid, and not held yet: the entry takes the root */
    ldr     x1, [x22, #NodeBlob_index]
    bl      node_blob_held
    cbnz    x0, 78f
    add     x9, x21, #NodeEvent_root
    COPY32  x22, x9
    mov     x9, #NODE_BLOB_VALID
    str     x9, [x22, #NodeBlob_status]
    mov     x0, x22
    bl      node_blob_added
    LEAVE 48
78: mov     x9, #NODE_BLOB_INVALID             /* not valid, or held: its bytes go */
    str     x9, [x22, #NodeBlob_status]
    mov     x0, #NODE_ACT_BYTES_FREE
    ldr     x1, [x22, #NodeBlob_data_id]
    mov     x2, #0
    bl      node_ids
    LEAVE 48
85: cmp     x9, #NODE_WORK_NEW_PAYLOAD         /* NEW_PAYLOAD, FORKCHOICE: the request to the execution engine */
    ccmp    x9, #NODE_WORK_FORKCHOICE, #4, ne
    b.ne    70f
    cbnz    x10, 87f
    ldr     x25, [x21, #(NodeEvent_chunk + 16)]
    add     x1, x25, #(48 + 7)
    and     x1, x1, #~7
    mov     x0, #NODE_ACT_ENGINE
    bl      node_act
    str     xzr, [x0, #16]
    ldr     x9, [x0]
    sub     x9, x9, #24
    mov     x10, #24
    stp     x9, x10, [x0, #24]
    str     x25, [x0, #40]
    add     x0, x0, #48
    add     x1, x21, #(NodeEvent_chunk + 24)
    mov     x2, x25
    bl      lantern_copy
    LEAVE 48
87: str     xzr, [x19, #Node_engine_method]    /* no request: the call ends */
    ldr     x9, [x21, #NodeAction_work_kind]
    cmp     x9, #NODE_WORK_NEW_PAYLOAD
    b.ne    79f
    ldr     x0, [x21, #NodeAction_target]
    PART    x22, x11, x19, Node_blocks
    cmp     x0, x11
    b.hs    79f
    mov     x11, #NodeBlock__mem
    madd    x22, x0, x11, x22
    ldr     x11, [x22, #NodeBlock_status]
    cmp     x11, #NODE_BLOCK_EXECUTING
    b.ne    79f
    cmp     x10, #LANTERN_NO_PAYLOAD
    b.ne    88f
    mov     x1, #PAYLOAD_STATUS_VALID          /* no payload: the import */
    bl      node_import_now
    LEAVE 48
88: mov     x9, #NODE_BLOCK_INVALID
    str     x9, [x22, #NodeBlock_status]
    mov     x0, #NODE_ACT_BYTES_FREE
    ldr     x1, [x22, #NodeBlock_data_id]
    mov     x2, #0
    bl      node_ids
    LEAVE 48
70: cmp     x9, #NODE_WORK_ATTESTATION         /* done with an attestation or a slashing: free its bytes */
    ccmp    x9, #NODE_WORK_ATTESTER_SLASHING, #4, ne
    b.ne    79f
71: mov     x0, #NODE_ACT_BYTES_FREE
    ldr     x1, [x21, #NodeAction_data]
    mov     x2, #0
    bl      node_ids
79: LEAVE 48
END_FUNCTION node_event

/* ------------------------------------------------------------ libp2p */

/* L0: x0 = room for an event of x0 bytes at the end of the node's queued libp2p events, its size written, or 0. Uses x9-x12. */
LOCAL_FUNCTION node_out
    UNWIND_END_PROLOGUE
    P2P_OUT x9
    ldr     x10, [x9, #16]
    ldr     x11, [x9]
    sub     x11, x11, #24
    sub     x11, x11, x10
    cmp     x11, x0
    b.lo    1f
    add     x12, x9, #24
    add     x12, x12, x10
    add     x10, x10, x0
    str     x10, [x9, #16]
    str     x0, [x12]
    mov     x0, x12
    ret
1:  mov     x0, #0
    ret
END_FUNCTION node_out

/* L0: a queued libp2p event of kind x0 with the handle x1: DISCONNECT, STREAM_CLOSE or STREAM_RESET. */
LOCAL_FUNCTION node_out_handle
    FRAME 16
    stp     x0, x1, [sp, #16]
    mov     x0, #24
    bl      node_out
    cbz     x0, 1f
    ldp     x9, x10, [sp, #16]
    stp     x9, x10, [x0, #8]
1:  UNFRAME 16
END_FUNCTION node_out_handle

/* L0: drops the first x0 queued libp2p events, which libp2p took. */
LOCAL_FUNCTION node_out_consume
    FRAME 16
    P2P_OUT x9
    ldr     x10, [x9, #16]
    add     x11, x9, #24
    mov     x12, #0
1:  cbz     x0, 2f
    cmp     x12, x10
    b.hs    2f
    ldr     x13, [x11, x12]
    add     x12, x12, x13
    sub     x0, x0, #1
    b       1b
2:  sub     x2, x10, x12
    str     x2, [x9, #16]
    mov     x0, x11
    add     x1, x11, x12
    bl      lantern_copy
    UNFRAME 16
END_FUNCTION node_out_consume

/* L0: x0 = the index of the peer of libp2p handle x0, or 2^64 - 1; x1 = its entry. Uses x9-x11. */
LOCAL_FUNCTION node_find_peer
    UNWIND_END_PROLOGUE
    PART    x1, x10, x19, Node_peers
    mov     x9, #0
1:  cmp     x9, x10
    b.hs    2f
    ldr     x11, [x1, #NodePeer_handle]
    cmp     x11, x0
    b.eq    3f
    add     x1, x1, #NodePeer__mem
    add     x9, x9, #1
    b       1b
2:  mov     x0, #-1
    ret
3:  mov     x0, x9
    ret
END_FUNCTION node_find_peer

/* L0: x0 = the index of the stream of libp2p handle x0, or 2^64 - 1; x1 = its entry. Uses x9-x12. */
LOCAL_FUNCTION node_find_stream
    UNWIND_END_PROLOGUE
    PART    x1, x10, x19, Node_streams
    ldr     x12, [x19, #Node_stream_bytes]
    mov     x9, #0
1:  cmp     x9, x10
    b.hs    2f
    ldr     x11, [x1, #NodeStream_handle]
    cmp     x11, x0
    b.eq    3f
    add     x1, x1, x12
    add     x9, x9, #1
    b       1b
2:  mov     x0, #-1
    ret
3:  mov     x0, x9
    ret
END_FUNCTION node_find_stream

/* L0: removes the stream entry x0: the last entry takes its place. */
LOCAL_FUNCTION node_drop_stream
    FRAME 16
    PART    x9, x10, x19, Node_streams
    ldr     x11, [x19, #Node_stream_bytes]
    sub     x10, x10, #1
    str     x10, [x19, #(Node_streams + 8)]
    madd    x1, x10, x11, x9
    cmp     x1, x0
    b.eq    1f
    mov     x2, x11
    bl      lantern_copy
1:  UNFRAME 16
END_FUNCTION node_drop_stream

/* L0: removes the peer entry x0 and its streams. x21 the entry, x22 its handle. */
LOCAL_FUNCTION node_drop_peer
    ENTER 0
    mov     x21, x0
    ldr     x22, [x21, #NodePeer_handle]
1:  PART    x9, x10, x19, Node_streams      /* its streams */
    ldr     x11, [x19, #Node_stream_bytes]
2:  cbz     x10, 3f
    ldr     x12, [x9, #NodeStream_peer]
    cmp     x12, x22
    b.ne    21f
    mov     x0, x9
    bl      node_end_stream
    b       1b
21: add     x9, x9, x11
    sub     x10, x10, #1
    b       2b
3:  PART    x9, x10, x19, Node_peers        /* the entry: the last takes its place */
    sub     x10, x10, #1
    str     x10, [x19, #(Node_peers + 8)]
    mov     x11, #NodePeer__mem
    madd    x1, x10, x11, x9
    cmp     x1, x21
    b.eq    9f
    mov     x0, x21
    mov     x2, #NodePeer__mem
    bl      lantern_copy
9:  LEAVE 0
END_FUNCTION node_drop_peer

/*
 * L0: x0 = the method of protocol index x0 of lantern_node_protocols, or 0; x1 = its version.
 * The protocols go by method, then by version. Uses x9-x13.
 */
LOCAL_FUNCTION node_protocol
    UNWIND_END_PROLOGUE
    ADDRESS x9, reqresp_names
    mov     x10, #1
1:  cmp     x10, #REQRESP_METHODS
    b.hi    8f
    ldr     x11, [x9, #8]
    lsr     x11, x11, #8                    /* the mask of its versions */
    mov     x12, #1
2:  cmp     x12, #8
    b.hs    4f
    lsr     x13, x11, x12
    tbz     x13, #0, 3f
    cbz     x0, 5f
    sub     x0, x0, #1
3:  add     x12, x12, #1
    b       2b
4:  add     x10, x10, #1
    add     x9, x9, #16
    b       1b
5:  mov     x0, x10
    mov     x1, x12
    ret
8:  mov     x0, #0
    mov     x1, #0
    ret
END_FUNCTION node_protocol

/*
 * L0: a response of one chunk on the stream entry x0, result x1, payload x2 of x3 bytes: a
 * STREAM_WRITE and a STREAM_CLOSE, or a STREAM_RESET when the node has no room; then the entry
 * goes. x21 entry, x22 result, x25 payload, x26 its bytes then the chunk's, x27 the scratch
 * size, x28 the chunk's ByteList. Locals: L a ChunkHeader, L+48 a size, L+56 the payload's ByteList.
 */
LOCAL_FUNCTION node_respond
    ENTER 64
    mov     x21, x0
    mov     x22, x1
    mov     x25, x2
    mov     x26, x3
    str     x26, [sp, #(L + 48)]
    add     x0, sp, #(L + 48)
    add     x1, sp, #(L + 48)
    bl      lantern_reqresp_chunk_size
    ldr     x27, [x23]                      /* the chunk, then the payload, at the end of scratch */
    add     x9, x26, #(24 + 7)
    and     x9, x9, #~7
    ldr     x10, [sp, #(L + 48)]
    add     x10, x10, #(24 + 7)
    and     x10, x10, #~7
    add     x11, x9, x10
    subs    x12, x27, x11
    b.lo    8f
    str     x12, [x23]
    add     x28, x23, x12
    add     x13, x28, x10
    mov     x14, #24
    stp     x10, x14, [x28]
    str     xzr, [x28, #16]
    stp     x9, x14, [x13]
    str     x26, [x13, #16]
    str     x13, [sp, #(L + 56)]
    add     x0, x13, #24
    mov     x1, x25
    mov     x2, x26
    bl      lantern_copy
    mov     x9, #CHUNK_RESPONSE
    str     x9, [sp, #(L + ChunkHeader_kind)]
    str     xzr, [sp, #(L + ChunkHeader_context_length)]
    str     x22, [sp, #(L + ChunkHeader_result)]
    add     x0, sp, #L
    ldr     x1, [sp, #(L + 56)]
    mov     x2, x23
    mov     x3, x28
    bl      lantern_reqresp_write_chunk
    cbnz    x0, 8f
    ldr     x26, [x28, #16]                 /* a STREAM_WRITE of the chunk, then a STREAM_CLOSE */
    add     x9, x26, #(32 + 7)
    and     x9, x9, #~7
    str     x9, [sp, #(L + 48)]
    add     x0, x9, #24
    bl      node_out
    cbz     x0, 8f
    ldr     x9, [sp, #(L + 48)]
    mov     x10, #LIBP2P_EVENT_STREAM_WRITE
    stp     x9, x10, [x0]
    ldr     x10, [x21, #NodeStream_handle]
    stp     x10, x26, [x0, #16]
    add     x11, x0, x9
    mov     x12, #24
    mov     x13, #LIBP2P_EVENT_STREAM_CLOSE
    stp     x12, x13, [x11]
    str     x10, [x11, #16]
    add     x0, x0, #32
    ldr     x1, [x28, #8]
    add     x1, x28, x1
    mov     x2, x26
    bl      lantern_copy
    b       9f
8:  mov     x0, #LIBP2P_EVENT_STREAM_RESET
    ldr     x1, [x21, #NodeStream_handle]
    bl      node_out_handle
9:  str     x27, [x23]
    mov     x0, x21
    bl      node_drop_stream
    LEAVE 64
END_FUNCTION node_respond

/*
 * L0: the request of the stream entry x0, when its bytes are all there: Status, Ping and
 * MetaData get their answer, Goodbye a close; other methods get ResourceUnavailable.
 * x21 entry, x22 method, x25 the request's size, x26 the scratch size, x27 the payload's
 * ByteList. Locals: L a ChunkHeader, L+48 consumed, L+56 a fork digest, L+64 a payload (96).
 */
LOCAL_FUNCTION node_request
    ENTER 160
    mov     x21, x0
    ldr     x9, [x21, #NodeStream_state]    /* a request already answered: nothing */
    cmp     x9, #NODE_STREAM_EOF
    b.hi    99f
    ldr     x22, [x21, #NodeStream_method]
    cmp     x22, #REQRESP_METADATA          /* MetaData: no request bytes */
    b.eq    50f
    ldr     x9, [x21, #NodeStream_version]  /* the SSZ size of the request */
    mov     x25, #84
    cmp     x22, #REQRESP_STATUS
    b.ne    1f
    cmp     x9, #2
    b.lo    3f
    mov     x25, #92
    b       3f
1:  mov     x25, #8
    cmp     x22, #REQRESP_GOODBYE
    b.eq    3f
    cmp     x22, #REQRESP_PING
    b.eq    3f
    mov     x25, #24
    cmp     x22, #REQRESP_BEACON_BLOCKS_BY_RANGE
    b.eq    3f
    mov     x25, #0                         /* by root: a multiple of 32 bytes, at most the request limit */
    cmp     x22, #REQRESP_BEACON_BLOCKS_BY_ROOT
    b.eq    3f
    mov     x25, #16                        /* blob sidecars, from deneb on: by range 16 bytes, by root a multiple of 40 */
    cmp     x22, #REQRESP_BLOB_SIDECARS_BY_RANGE
    b.eq    2f
    mov     x25, #0
    cmp     x22, #REQRESP_BLOB_SIDECARS_BY_ROOT
    b.ne    92f
2:  mov     x0, x20
    bl      node_store_slot
    add     x1, x19, #Node_config
    bl      node_fork
    cmp     x0, #FORK_DENEB
    b.hs    3f
92: mov     x1, #3                          /* ResourceUnavailable */
    b       91f
3:  str     xzr, [sp, #(L + ChunkHeader_kind)]      /* CHUNK_REQUEST */
    str     xzr, [sp, #(L + ChunkHeader_context_length)]
    add     x0, x21, #NodeStream_list
    add     x1, sp, #L
    bl      lantern_reqresp_read_header
    cmp     x0, #LANTERN_REQRESP_MORE
    b.eq    80f
    cbnz    x0, 90f
    ldr     x9, [sp, #(L + ChunkHeader_length)]
    cbnz    x25, 4f
    cmp     x22, #REQRESP_BLOB_SIDECARS_BY_ROOT
    b.eq    5f
    tst     x9, #31                         /* by root */
    b.ne    90f
    bl      node_max_blocks
    ldr     x9, [sp, #(L + ChunkHeader_length)]
    cmp     x9, x0, lsl #5
    b.hi    90f
    mov     x25, x9
    b       4f
5:  mov     x10, #40                        /* blob identifiers */
    udiv    x11, x9, x10
    msub    x12, x11, x10, x9
    cbnz    x12, 90f
    bl      node_max_blobs
    ldr     x9, [sp, #(L + ChunkHeader_length)]
    mov     x10, #40
    udiv    x11, x9, x10
    cmp     x11, x0
    b.hi    90f
    mov     x25, x9
4:  cmp     x9, x25
    b.ne    90f
    ldr     x26, [x23]                      /* the payload's ByteList at the end of scratch */
    add     x10, x25, #(24 + 7)
    and     x10, x10, #~7
    sub     x9, x26, x10
    str     x9, [x23]
    add     x27, x23, x9
    mov     x11, #24
    stp     x10, x11, [x27]
    str     xzr, [x27, #16]
    str     x25, [sp, #(L + 56)]            /* length and eof, by address */
    ldr     x9, [x21, #NodeStream_state]
    cmp     x9, #NODE_STREAM_EOF
    cset    x9, eq
    str     x9, [sp, #(L + 64)]
    add     x0, x21, #NodeStream_list
    add     x1, sp, #(L + ChunkHeader_header_bytes)
    add     x2, sp, #(L + 56)
    add     x3, sp, #(L + 64)
    mov     x4, x23
    mov     x5, x27
    add     x6, sp, #(L + 48)
    bl      lantern_reqresp_read_payload
    str     x26, [x23]
    cmp     x0, #LANTERN_REQRESP_MORE
    b.eq    80f
    cbnz    x0, 90f
    add     x27, x27, #24                   /* the SSZ bytes */
    cmp     x22, #REQRESP_BEACON_BLOCKS_BY_RANGE
    b.eq    60f
    cmp     x22, #REQRESP_BEACON_BLOCKS_BY_ROOT
    b.eq    70f
    cmp     x22, #REQRESP_BLOB_SIDECARS_BY_RANGE
    b.eq    65f
    cmp     x22, #REQRESP_BLOB_SIDECARS_BY_ROOT
    b.eq    75f
    cmp     x22, #REQRESP_GOODBYE
    b.ne    10f
    mov     x0, #LIBP2P_EVENT_STREAM_CLOSE  /* Goodbye: a close */
    ldr     x1, [x21, #NodeStream_handle]
    bl      node_out_handle
    mov     x0, x21
    bl      node_drop_stream
    LEAVE 160
10: cmp     x22, #REQRESP_PING
    b.ne    20f
    ldr     x9, [x19, #Node_metadata_seq]   /* Ping: our seq_number */
    str     x9, [sp, #(L + 64)]
    mov     x0, x21
    mov     x1, #0
    add     x2, sp, #(L + 64)
    mov     x3, #8
    bl      node_respond
    LEAVE 160
20: ldr     x0, [x21, #NodeStream_peer]     /* Status: the peer's, then ours */
    mov     x1, x27
    mov     x2, x25
    bl      node_peer_status
    add     x0, sp, #(L + 64)
    bl      node_status_bytes
    mov     x0, x21
    mov     x1, #0
    add     x2, sp, #(L + 64)
    mov     x3, x25
    bl      node_respond
    LEAVE 160
50: add     x0, sp, #(L + 64)               /* MetaData: seq_number, attnets, syncnets, custody_group_count */
    mov     x1, #32
    bl      lantern_zero
    ldr     x9, [x19, #Node_metadata_seq]
    str     x9, [sp, #(L + 64)]
    LDQ     x9, x19, Node_config + CONFIG_CUSTODY_REQUIREMENT
    str     x9, [sp, #(L + 56)]
    add     x0, sp, #(L + 64 + 17)
    add     x1, sp, #(L + 56)
    mov     x2, #8
    bl      lantern_copy
    ldr     x9, [x21, #NodeStream_version]
    mov     x3, #16
    cmp     x9, #2
    b.lo    51f
    mov     x3, #17
    b.eq    51f
    mov     x3, #25
51: mov     x0, x21
    mov     x1, #0
    add     x2, sp, #(L + 64)
    bl      node_respond
    LEAVE 160
60: ldp     x25, x26, [x27]             /* BlocksByRange: start_slot, count */
    ldr     x9, [x19, #Node_earliest_slot]
    cmp     x25, x9
    b.lo    92b
    bl      node_max_blocks                 /* at most the limit, and the room of the list */
    cmp     x26, x0
    csel    x26, x26, x0, ls
    adds    x26, x25, x26                   /* the end slot */
    csinv   x26, x26, xzr, cc
    mov     x28, #0                         /* the canonical blocks of the range, from the head down */
    add     x27, x19, #Node_head_root
61: mov     x0, x27
    bl      node_find_block
    cmn     x0, #1
    b.eq    63f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    63f
    ldr     x9, [x1, #NodeBlock_slot]
    cmp     x9, x25
    b.lo    63f
    add     x27, x1, #NodeBlock_parent_root
    cmp     x9, x26
    b.hs    61b
    ldr     x9, [x1, #NodeBlock_data_id]
    cbz     x9, 61b
    add     x10, x21, #NodeStream_request
    str     x9, [x10, x28, lsl #3]
    add     x28, x28, #1
    b       61b
63: add     x9, x21, #NodeStream_request    /* in slot order */
    add     x10, x9, x28, lsl #3
    sub     x10, x10, #8
64: cmp     x9, x10
    b.hs    77f
    ldr     x11, [x9]
    ldr     x12, [x10]
    str     x12, [x9], #8
    str     x11, [x10], #-8
    b       64b
65: ldp     x25, x26, [x27]                 /* BlobSidecarsByRange: start_slot, count */
    ldr     x9, [x19, #Node_earliest_slot]
    cmp     x25, x9
    b.lo    92b
    LDQ     x9, x19, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK   /* the indices of a block */
    LDQ     x10, x19, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
    cmp     x9, x10
    csel    x9, x10, x9, lo
    mov     x10, #NODE_BLOB_MAX
    cmp     x9, x10
    csel    x9, x10, x9, hi
    cbz     x9, 78f
    str     x9, [sp, #(L + 72)]
    bl      node_max_blobs                  /* at most the limit: the slots whose sidecars it can hold */
    ldr     x9, [sp, #(L + 72)]
    udiv    x10, x0, x9
    cmp     x26, x10
    csel    x26, x26, x10, ls
    adds    x26, x25, x26                   /* the end slot */
    csinv   x26, x26, xzr, cc
    mov     x28, #0                         /* the sidecars of the canonical blocks of the range, from the head down */
    add     x27, x19, #Node_head_root
66: mov     x0, x27
    bl      node_find_block
    cmn     x0, #1
    b.eq    63b
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    63b
    ldr     x9, [x1, #NodeBlock_slot]
    cmp     x9, x25
    b.lo    63b
    add     x27, x1, #NodeBlock_parent_root
    cmp     x9, x26
    b.hs    66b
    str     x1, [sp, #(L + 64)]             /* its indices, from the last */
    ldr     x9, [sp, #(L + 72)]
    str     x9, [sp, #(L + 80)]
67: ldr     x1, [sp, #(L + 80)]
    cbz     x1, 66b
    sub     x1, x1, #1
    str     x1, [sp, #(L + 80)]
    ldr     x0, [sp, #(L + 64)]
    bl      node_blob_held
    cbz     x0, 67b
    ldr     x9, [x0, #NodeBlob_data_id]
    add     x10, x21, #NodeStream_request
    str     x9, [x10, x28, lsl #3]
    add     x28, x28, #1
    b       67b
75: mov     x10, #40                        /* BlobSidecarsByRoot: the sidecars the node holds, in the request's order */
    udiv    x26, x25, x10
    mov     x28, #0
76: cbz     x26, 77f
    mov     x0, x27
    ldr     x1, [x27, #32]
    add     x27, x27, #40
    sub     x26, x26, #1
    bl      node_blob_held
    cbz     x0, 76b
    ldr     x9, [x0, #NodeBlob_data_id]
    str     x9, [sp, #(L + 64)]
    bl      node_find_block                 /* not of an invalid block */
    cmn     x0, #1
    b.eq    74f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_INVALID
    b.eq    76b
74: ldr     x9, [sp, #(L + 64)]
    add     x10, x21, #NodeStream_request
    str     x9, [x10, x28, lsl #3]
    add     x28, x28, #1
    b       76b
70: lsr     x25, x25, #5                    /* BlocksByRoot: the blocks the node has, in the request's order */
    mov     x28, #0
    mov     x26, x27
71: cbz     x25, 77f
    mov     x0, x26
    bl      node_find_block
    add     x26, x26, #32
    sub     x25, x25, #1
    cmn     x0, #1
    b.eq    71b
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    71b
    ldr     x9, [x1, #NodeBlock_data_id]
    cbz     x9, 71b
    add     x10, x21, #NodeStream_request
    str     x9, [x10, x28, lsl #3]
    add     x28, x28, #1
    b       71b
77: cbz     x28, 78f                        /* the list, then a SERVE work for each block in turn */
    lsl     x9, x28, #3
    str     x9, [x21, #(NodeStream_list + 16)]
    str     xzr, [x21, #NodeStream_next]
    mov     x9, #NODE_STREAM_SERVE
    str     x9, [x21, #NodeStream_state]
    LEAVE 160
78: mov     x0, #LIBP2P_EVENT_STREAM_CLOSE  /* no block: an empty answer */
    ldr     x1, [x21, #NodeStream_handle]
    bl      node_out_handle
    mov     x0, x21
    bl      node_drop_stream
    LEAVE 160
80: ldr     x9, [x21, #NodeStream_state]    /* more bytes come, unless the peer closed */
    cmp     x9, #NODE_STREAM_EOF
    b.eq    90f
    LEAVE 160
90: mov     x1, #1                          /* InvalidRequest */
91: mov     x0, x21
    mov     x2, sp
    mov     x3, #0
    bl      node_respond
99: LEAVE 160
END_FUNCTION node_request

/*
 * L0: x0 = the blocks one request may name: MAX_REQUEST_BLOCKS_DENEB from deneb on, else
 * MAX_REQUEST_BLOCKS, of the fork of the store's slot; at most the BufferIds a stream's list
 * holds. Uses x9-x13.
 */
LOCAL_FUNCTION node_max_blocks
    FRAME 0
    mov     x0, x20
    bl      node_store_slot
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x9, #REQUEST_BLOCKS_LIMIT
    mov     x10, #REQUEST_BLOCKS_LIMIT_DENEB
    cmp     x0, #FORK_DENEB
    csel    x0, x10, x9, hs
    ldr     x9, [x19, #Node_stream_bytes]
    sub     x9, x9, #NodeStream__fixed
    lsr     x9, x9, #3
    cmp     x0, x9
    csel    x0, x0, x9, ls
    UNFRAME 0
END_FUNCTION node_max_blocks

/*
 * L0: x0 = the blob sidecars one response may hold: MAX_REQUEST_BLOCKS_DENEB times
 * MAX_BLOBS_PER_BLOCK (deneb) or MAX_BLOBS_PER_BLOCK_ELECTRA (electra and later) of the fork of
 * the store's slot; at most the BufferIds a stream's list holds. Uses x9-x13, x16.
 */
LOCAL_FUNCTION node_max_blobs
    FRAME 0
    mov     x0, x20
    bl      node_store_slot
    add     x1, x19, #Node_config
    bl      node_fork
    LDQ     x9, x19, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK
    LDQ     x10, x19, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
    cmp     x0, #FORK_ELECTRA
    csel    x9, x10, x9, hs
    mov     x10, #REQUEST_BLOCKS_LIMIT_DENEB
    umulh   x11, x9, x10
    mul     x9, x9, x10
    cbz     x11, 1f
    mov     x9, #-1
1:  ldr     x10, [x19, #Node_stream_bytes]
    sub     x10, x10, #NodeStream__fixed
    lsr     x10, x10, #3
    cmp     x9, x10
    csel    x0, x9, x10, ls
    UNFRAME 0
END_FUNCTION node_max_blobs

/*
 * L0: x0 = 1 when a stream waits for room for its SERVE work, else 0: a SERVE work of the next
 * block of each stream in NODE_STREAM_SERVE, while the actions have room for it and 4096 bytes.
 * x21 a stream, x22 the streams left, x25 the stream bytes.
 */
LOCAL_FUNCTION node_serve
    ENTER 0
    PART    x21, x22, x19, Node_streams
    ldr     x25, [x19, #Node_stream_bytes]
1:  cbz     x22, 8f
    ldr     x9, [x21, #NodeStream_state]
    cmp     x9, #NODE_STREAM_SERVE
    b.ne    2f
    ldp     x9, x10, [x24, #8]
    ldr     x11, [x24]
    sub     x11, x11, x9
    sub     x11, x11, x10
    mov     x12, #(NODE_ACT_WORK_SIZE + 4096)
    cmp     x11, x12
    b.lo    9f
    mov     x9, #NODE_STREAM_SERVING
    str     x9, [x21, #NodeStream_state]
    ldr     x9, [x21, #NodeStream_next]
    add     x10, x21, #NodeStream_request
    ldr     x3, [x10, x9, lsl #3]
    mov     x0, #NODE_WORK_SERVE
    mov     x1, #0
    mov     x2, #0
    ldr     x4, [x21, #NodeStream_handle]
    ldr     x5, [x21, #NodeStream_version]  /* arg: the version + 256 * the method */
    ldr     x9, [x21, #NodeStream_method]
    add     x5, x5, x9, lsl #8
    bl      node_work
2:  add     x21, x21, x25
    sub     x22, x22, #1
    b       1b
8:  mov     x0, #0
    LEAVE 0
9:  mov     x0, #1
    LEAVE 0
END_FUNCTION node_serve

/* ------------------------------------------------------------ gossip */

/* L0: x0 = the index of the message of libp2p handle x0, or 2^64 - 1; x1 = its entry. Uses x9-x11. */
LOCAL_FUNCTION node_find_message
    UNWIND_END_PROLOGUE
    PART    x1, x10, x19, Node_messages
    mov     x9, #0
1:  cmp     x9, x10
    b.hs    2f
    ldr     x11, [x1, #NodeMessage_handle]
    cmp     x11, x0
    b.eq    3f
    add     x1, x1, #NodeMessage__mem
    add     x9, x9, #1
    b       1b
2:  mov     x0, #-1
    ret
3:  mov     x0, x9
    ret
END_FUNCTION node_find_message

/* L0: removes the message entry x0: the last entry takes its place. */
LOCAL_FUNCTION node_drop_message
    FRAME 16
    PART    x9, x10, x19, Node_messages
    sub     x10, x10, #1
    str     x10, [x19, #(Node_messages + 8)]
    mov     x11, #NodeMessage__mem
    madd    x1, x10, x11, x9
    cmp     x1, x0
    b.eq    1f
    mov     x2, #NodeMessage__mem
    bl      lantern_copy
1:  UNFRAME 16
END_FUNCTION node_drop_message

/* L0: x0 = 1 when the actions have room for x0 bytes and 4096 more, else 0. Uses x9-x12. */
LOCAL_FUNCTION node_room
    UNWIND_END_PROLOGUE
    ldp     x9, x10, [x24, #8]
    ldr     x11, [x24]
    sub     x11, x11, x9
    sub     x11, x11, x10
    add     x12, x0, #4096
    cmp     x11, x12
    cset    x0, hs
    ret
END_FUNCTION node_room

/* L0: a VALIDATION of the libp2p message handle x0 with the result x1. */
LOCAL_FUNCTION node_validation
    FRAME 16
    stp     x0, x1, [sp, #16]
    mov     x0, #LIBP2P_EV_VALIDATION_SIZE
    bl      node_out
    cbz     x0, 1f
    mov     x9, #LIBP2P_EVENT_VALIDATION
    str     x9, [x0, #8]
    ldp     x9, x10, [sp, #16]
    stp     x9, x10, [x0, #16]
1:  UNFRAME 16
END_FUNCTION node_validation

/* L0: the gossip topic x0 with the subnet x1 at the node's ForkDigest: a SUBSCRIBE event. x21 the topic's length. Locals: L a GossipTopic, L+24 a ByteList of the topic. */
LOCAL_FUNCTION node_sub
    ENTER 176
    ldr     x9, [x19, #Node_fork_digest]
    str     x9, [sp, #(L + GossipTopic_fork_digest)]
    stp     x0, x1, [sp, #(L + GossipTopic_name)]
    mov     x9, #(24 + 128)
    mov     x10, #24
    stp     x9, x10, [sp, #(L + 24)]
    str     xzr, [sp, #(L + 40)]
    add     x0, sp, #L
    add     x1, sp, #(L + 24)
    bl      lantern_gossip_topic
    cbnz    x0, 9f
    ldr     x21, [sp, #(L + 40)]
    add     x0, x21, #(24 + 7)
    and     x0, x0, #~7
    bl      node_out
    cbz     x0, 9f
    mov     x9, #LIBP2P_EVENT_SUBSCRIBE
    stp     x9, x21, [x0, #8]
    add     x0, x0, #24
    add     x1, sp, #(L + 48)
    mov     x2, x21
    bl      lantern_copy
9:  LEAVE 176
END_FUNCTION node_sub

/*
 * L0: the node's Status at x0 (92 bytes: v2; v1 is its first 84): compute_fork_digest of the
 * store's epoch, the store's finalized checkpoint (a zero root at GENESIS_EPOCH), head_root and its
 * slot, and earliest_slot.
 * x21 out, x22 the slot. Locals: L an epoch, L+8 a ForkDigest, L+16 a slot.
 */
LOCAL_FUNCTION node_status_bytes
    ENTER 32
    mov     x21, x0
    mov     x0, x20
    bl      node_store_slot
    mov     x22, x0
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x9, x22, x9
    str     x9, [sp, #L]
    str     xzr, [sp, #(L + 8)]
    add     x0, x19, #Node_genesis_validators_root
    add     x1, sp, #L
    add     x2, x19, #Node_config
    mov     x3, x23
    add     x4, sp, #(L + 8)
    FORK_CALL compute_fork_digest
    mov     x0, x21                         /* fork_digest */
    add     x1, sp, #(L + 8)
    mov     x2, #4
    bl      lantern_copy
    add     x0, x21, #4                     /* finalized_root, finalized_epoch */
    add     x1, x20, #(Store_finalized_checkpoint + 8)
    mov     x2, #32
    bl      lantern_copy
    add     x0, x21, #36
    add     x1, x20, #Store_finalized_checkpoint
    mov     x2, #8
    bl      lantern_copy
    ldr     x9, [x20, #Store_finalized_checkpoint]  /* the genesis finalized checkpoint: a zero root */
    cbnz    x9, 2f
    add     x0, x21, #4
    mov     x1, #32
    bl      lantern_zero
2:  add     x0, x21, #44                    /* head_root, head_slot */
    add     x1, x19, #Node_head_root
    mov     x2, #32
    bl      lantern_copy
    add     x0, x19, #Node_head_root
    bl      node_find_block
    mov     x9, #0
    cmn     x0, #1
    b.eq    1f
    ldr     x9, [x1, #NodeBlock_slot]
1:  str     x9, [sp, #(L + 16)]
    add     x0, x21, #76
    add     x1, sp, #(L + 16)
    mov     x2, #8
    bl      lantern_copy
    add     x0, x21, #84                    /* earliest_available_slot: Status v2 */
    add     x1, x19, #Node_earliest_slot
    mov     x2, #8
    bl      lantern_copy
    LEAVE 32
END_FUNCTION node_status_bytes

/*
 * L0: with NODE_FLAG_DISCV5, the node's record entries for the epoch at x0 of the fork x1: a
 * NODE_ACT_DISCV5 of SET_ENTRY events: eth2, attnets, from altair syncnets, from fulu cgc and nfd.
 * x21 the fork, x22 the action, x25 the next event. Locals: L the epoch.
 */
.set NODE_ENR_ACTION, 48 + 64 + 56 * 4
LOCAL_FUNCTION node_enr_entries
    ENTER 16
    ldr     x9, [x19, #Node_flags]
    tbz     x9, #6, 9f                      /* NODE_FLAG_DISCV5 */
    ldr     x9, [x0]
    str     x9, [sp, #L]
    mov     x21, x1
    mov     x0, #NODE_ACT_DISCV5
    mov     x1, #NODE_ENR_ACTION
    bl      node_act
    mov     x22, x0
    str     xzr, [x22, #16]
    mov     x9, #(NODE_ENR_ACTION - 24)
    mov     x10, #24
    stp     x9, x10, [x22, #24]
    add     x25, x22, #48
    mov     x9, #64                         /* eth2: the ENRForkID of the epoch */
    mov     x10, #DISCV5_EVENT_SET_ENTRY
    stp     x9, x10, [x25]
    mov     x9, #4
    MOVQ    x10, 0x32687465
    stp     x9, x10, [x25, #16]
    mov     x9, #16
    stp     xzr, x9, [x25, #32]
    add     x0, x19, #Node_genesis_validators_root
    add     x1, sp, #L
    add     x2, x19, #Node_config
    mov     x3, x23
    add     x4, x25, #48
    mov     x15, x21
    FORK_CALL compute_enr_fork_id
    add     x25, x25, #64
    mov     x9, #56                         /* attnets: no subnet */
    mov     x10, #DISCV5_EVENT_SET_ENTRY
    stp     x9, x10, [x25]
    mov     x9, #7
    MOVQ    x10, 0x007374656e747461
    stp     x9, x10, [x25, #16]
    mov     x9, #8
    stp     xzr, x9, [x25, #32]
    str     xzr, [x25, #48]
    add     x25, x25, #56
    cmp     x21, #FORK_ALTAIR
    b.lo    8f
    mov     x9, #56                         /* syncnets: no subnet */
    mov     x10, #DISCV5_EVENT_SET_ENTRY
    stp     x9, x10, [x25]
    mov     x9, #8
    MOVQ    x10, 0x7374656e636e7973
    stp     x9, x10, [x25, #16]
    mov     x9, #1
    stp     xzr, x9, [x25, #32]
    str     xzr, [x25, #48]
    add     x25, x25, #56
    cmp     x21, #FORK_FULU
    b.lo    8f
    mov     x9, #56                         /* cgc: CUSTODY_REQUIREMENT, big-endian, no leading zero byte */
    mov     x10, #DISCV5_EVENT_SET_ENTRY
    stp     x9, x10, [x25]
    mov     x9, #3
    MOVQ    x10, 0x636763
    stp     x9, x10, [x25, #16]
    str     xzr, [x25, #32]
    str     xzr, [x25, #48]
    LDQ     x11, x19, Node_config + CONFIG_CUSTODY_REQUIREMENT
    clz     x12, x11                        /* n bytes: 8 - its leading zero bytes */
    lsr     x12, x12, #3
    mov     x13, #8
    sub     x12, x13, x12
    str     x12, [x25, #40]
    cbz     x12, 1f
    rev     x11, x11                        /* big-endian; its last n bytes move to the front */
    sub     x13, x13, x12
    lsl     x13, x13, #3
    lsr     x11, x11, x13
    str     x11, [x25, #48]
1:  add     x25, x25, #56
    mov     x9, #56                         /* nfd: the next fork digest */
    mov     x10, #DISCV5_EVENT_SET_ENTRY
    stp     x9, x10, [x25]
    mov     x9, #3
    MOVQ    x10, 0x64666e
    stp     x9, x10, [x25, #16]
    mov     x9, #4
    stp     xzr, x9, [x25, #32]
    str     xzr, [x25, #48]
    add     x0, x19, #Node_genesis_validators_root
    add     x1, sp, #L
    add     x2, x19, #Node_config
    mov     x3, x23
    add     x4, x25, #48
    CALL_GLOBAL lantern_fulu_compute_next_fork_digest
    add     x25, x25, #56
8:  add     x9, x22, #48                    /* the events' bytes */
    sub     x9, x25, x9
    str     x9, [x22, #40]
9:  LEAVE 16
END_FUNCTION node_enr_entries

/*
 * L0: x0 = the value of the byte string pair whose key is the x3 (at most 8) bytes of x2, little
 * end first, of the Enr x0 of the record bytes at x1, or 0; x1 = its length. Uses x9-x16.
 */
LOCAL_FUNCTION node_enr_pair
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #DISCV5_ENR_COUNT]
    add     x10, x0, #DISCV5_ENR_PAIRS
1:  cbz     x9, 3f
    ldr     w11, [x10, #DISCV5_PAIR_KEY_LEN]
    cmp     x11, x3
    b.ne    2f
    ldr     w12, [x10, #DISCV5_PAIR_KEY_OFFSET]
    add     x12, x1, x12
    mov     x13, #0                         /* the key's bytes as a number */
    mov     x14, #0
4:  cmp     x14, x3
    b.hs    5f
    ldrb    w15, [x12, x14]
    lsl     x16, x14, #3
    lsl     x15, x15, x16
    orr     x13, x13, x15
    add     x14, x14, #1
    b       4b
5:  cmp     x13, x2
    b.ne    2f
    ldr     w11, [x10, #DISCV5_PAIR_VALUE_KIND]
    cmp     w11, #1
    b.ne    2f
    ldr     w12, [x10, #DISCV5_PAIR_VALUE_OFFSET]
    add     x0, x1, x12
    ldr     w1, [x10, #DISCV5_PAIR_VALUE_LEN]
    ret
2:  add     x10, x10, #DISCV5_PAIR_SIZE
    sub     x9, x9, #1
    b       1b
3:  mov     x0, #0
    mov     x1, #0
    ret
END_FUNCTION node_enr_pair

/*
 * L0: the node record of the NODE_EV_ENR x0: a DIAL of its TCP address when it has an ip, a tcp
 * pair of 1 or 2 bytes, an eth2 pair of compute_fork_digest at the store's epoch, a peer ID no
 * NodePeer has, and room for a peer. x21 the record's ByteList, x22 the Enr, x25 the scratch size,
 * restored on return, x26 the port, x27 the DIAL. Locals: L the peer ID (39 bytes), L+48 the
 * node's Status (96), whose first 4 bytes are that digest.
 */
LOCAL_FUNCTION node_enr
    ENTER 144
    add     x21, x0, #NodeEvent_bytes
    ldr     x25, [x23]
    MOVQ    x9, DISCV5_ENR_SIZE + DISCV5_ENR_SCRATCH    /* the Enr and its scratch at the end of scratch */
    subs    x10, x25, x9
    b.lo    9f
    str     x10, [x23]
    add     x22, x23, x10
    add     x1, x22, #DISCV5_ENR_SIZE
    MOVQ    x9, DISCV5_ENR_SCRATCH
    str     x9, [x1]
    mov     x0, x21
    mov     x2, x22
    CALL_GLOBAL discv5_enr_decode
    cbnz    x0, 9f
    ldr     x9, [x22, #DISCV5_ENR_HAS]
    tbz     x9, #0, 9f                      /* an ip */
    mov     x0, x22                         /* a tcp port of 1 or 2 bytes */
    ldr     x1, [x21, #8]
    add     x1, x21, x1
    MOVQ    x2, 0x706374
    mov     x3, #3
    bl      node_enr_pair
    cbz     x0, 9f
    cmp     x1, #1
    b.lo    9f
    cmp     x1, #2
    b.hi    9f
    ldrb    w26, [x0]
    b.ne    1f
    ldrb    w9, [x0, #1]
    orr     x26, x9, x26, lsl #8
1:  mov     x0, x22                         /* an eth2 of the node's fork_digest */
    ldr     x1, [x21, #8]
    add     x1, x21, x1
    MOVQ    x2, 0x32687465
    mov     x3, #4
    bl      node_enr_pair
    cbz     x0, 9f
    cmp     x1, #4
    b.lo    9f
    ldrb    w9, [x0]
    ldrb    w10, [x0, #1]
    orr     w9, w9, w10, lsl #8
    ldrb    w10, [x0, #2]
    orr     w9, w9, w10, lsl #16
    ldrb    w10, [x0, #3]
    orr     w9, w9, w10, lsl #24
    str     w9, [sp, #L]
    add     x0, sp, #(L + 48)
    bl      node_status_bytes
    ldr     w9, [sp, #L]
    ldr     w10, [sp, #(L + 48)]
    cmp     w9, w10
    b.ne    9f
    MOVQ    x9, 0x0000211202082500          /* the peer ID: identity multihash of the protobuf secp256k1 key */
    str     x9, [sp, #L]
    add     x0, sp, #(L + 6)
    add     x1, x22, #DISCV5_ENR_PUBKEY
    mov     x2, #33
    bl      lantern_copy
    PART    x9, x10, x19, Node_peers        /* not a peer of the node */
2:  cbz     x10, 4f
    ldr     x11, [x9, #NodePeer_id_len]
    cmp     x11, #39
    b.ne    3f
    mov     x12, #0
5:  cmp     x12, #39
    b.hs    9f
    add     x13, x9, #NodePeer_id
    ldrb    w14, [x13, x12]
    add     x15, sp, #L
    ldrb    w15, [x15, x12]
    cmp     w14, w15
    b.ne    3f
    add     x12, x12, #1
    b       5b
3:  add     x9, x9, #NodePeer__mem
    sub     x10, x10, #1
    b       2b
4:  ldr     x10, [x19, #(Node_peers + 8)]   /* room for a peer */
    ldr     x11, [x19, #Node_dialing]
    add     x10, x10, x11
    ldr     x12, [x19, #Node_streams]
    ldr     x13, [x19, #Node_peers]
    sub     x12, x12, x13
    mov     x13, #NodePeer__mem
    udiv    x12, x12, x13
    cmp     x10, x12
    b.hs    9f
    mov     x0, #LIBP2P_EV_DIAL_SIZE        /* the DIAL */
    bl      node_out
    cbz     x0, 9f
    mov     x27, x0
    mov     x9, #LIBP2P_EVENT_DIAL
    str     x9, [x27, #8]
    bl      node_new_id
    orr     x0, x0, #NODE_DIAL_TAG
    str     x0, [x27, #LIBP2P_EV_TAG]
    mov     x9, #4
    stp     x9, x26, [x27, #(LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_FAMILY)]
    stp     xzr, xzr, [x27, #(LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_IP)]
    ldr     w9, [x22, #DISCV5_ENR_IP4]
    str     w9, [x27, #(LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_IP)]
    mov     x9, #39
    str     x9, [x27, #LIBP2P_EV_DIAL_ID_LEN]
    add     x0, x27, #LIBP2P_EV_DIAL_ID
    mov     x1, #48
    bl      lantern_zero
    add     x0, x27, #LIBP2P_EV_DIAL_ID
    add     x1, sp, #L
    mov     x2, #39
    bl      lantern_copy
    mov     x9, #LIBP2P_TCP
    stp     x9, xzr, [x27, #LIBP2P_EV_DIAL_TRANSPORT]
    ldr     x9, [x19, #Node_dialing]
    add     x9, x9, #1
    str     x9, [x19, #Node_dialing]
9:  str     x25, [x23]
    LEAVE 144
END_FUNCTION node_enr

/*
 * L0: with NODE_FLAG_DISCV5 and room for more peers, a NODE_ACT_DISCV5 of a LOOKUP whose target is
 * the 32 entropy bytes of the tick x0, when lookup_ms is 0 or NODE_LOOKUP_MS before time_ms.
 * x21 the tick, x22 the action.
 */
LOCAL_FUNCTION node_lookup
    ENTER 0
    mov     x21, x0
    ldr     x9, [x19, #Node_flags]
    tbz     x9, #6, 9f
    ldr     x10, [x19, #(Node_peers + 8)]
    ldr     x11, [x19, #Node_dialing]
    add     x10, x10, x11
    ldr     x12, [x19, #Node_streams]
    ldr     x13, [x19, #Node_peers]
    sub     x12, x12, x13
    mov     x13, #NodePeer__mem
    udiv    x12, x12, x13
    cmp     x10, x12
    b.hs    9f
    ldr     x9, [x19, #Node_lookup_ms]
    cbz     x9, 1f
    ldr     x10, [x19, #Node_time_ms]
    MOVQ    x11, NODE_LOOKUP_MS
    add     x9, x9, x11
    cmp     x10, x9
    b.lo    9f
1:  mov     x0, #96                         /* the action: 16, 24 a ByteList, 48 the LOOKUP */
    bl      node_room
    cbz     x0, 9f
    mov     x0, #NODE_ACT_DISCV5
    mov     x1, #96
    bl      node_act
    mov     x22, x0
    str     xzr, [x22, #16]
    mov     x9, #72
    mov     x10, #24
    stp     x9, x10, [x22, #24]
    mov     x9, #DISCV5_EV_LOOKUP_SIZE
    str     x9, [x22, #40]
    mov     x10, #DISCV5_EVENT_LOOKUP
    stp     x9, x10, [x22, #48]
    add     x0, x22, #(48 + DISCV5_EV_LOOKUP_TARGET)
    add     x1, x21, #LIBP2P_TICK_ENTROPY
    mov     x2, #32
    bl      lantern_copy
    ldr     x9, [x19, #Node_time_ms]
    cmp     x9, #1
    csinc   x9, x9, xzr, hs
    str     x9, [x19, #Node_lookup_ms]
9:  LEAVE 0
END_FUNCTION node_lookup

/*
 * L0: the gossip topics of the fork of the store's epoch, at its ForkDigest: SUBSCRIBE events,
 * once for each digest, when p2p_out has room for them. x21 the fork, x22 a subnet, x25 the
 * subnets. Locals: L an epoch, L+8 a ForkDigest.
 */
LOCAL_FUNCTION node_subscribe
    ENTER 16
    P2P_OUT x9
    ldr     x11, [x9]
    ldr     x10, [x9, #16]
    sub     x11, x11, #24
    sub     x11, x11, x10
    mov     x12, #(64 * 128)
    cmp     x11, x12
    b.lo    9f
    mov     x0, #NODE_ENR_ACTION            /* and the actions room for the record entries */
    bl      node_room
    cbz     x0, 9f
    mov     x0, x20
    bl      node_store_slot
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x9, x0, x9
    str     x9, [sp, #L]
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x21, x0
    mov     x15, x0
    str     xzr, [sp, #(L + 8)]
    add     x0, x19, #Node_genesis_validators_root
    add     x1, sp, #L
    add     x2, x19, #Node_config
    mov     x3, x23
    add     x4, sp, #(L + 8)
    FORK_CALL compute_fork_digest
    cbnz    x0, 9f
    ldr     x9, [x19, #Node_flags]
    ldr     x10, [sp, #(L + 8)]
    tbz     x9, #2, 1f                      /* NODE_FLAG_SUBSCRIBED */
    ldr     x11, [x19, #Node_fork_digest]
    cmp     x10, x11
    b.eq    9f
1:  str     x10, [x19, #Node_fork_digest]
    orr     x9, x9, #NODE_FLAG_SUBSCRIBED
    str     x9, [x19, #Node_flags]
    add     x0, sp, #L                      /* the record entries of the new digest */
    mov     x1, x21
    bl      node_enr_entries
    .irp name, GOSSIP_BEACON_BLOCK, GOSSIP_BEACON_AGGREGATE_AND_PROOF, GOSSIP_VOLUNTARY_EXIT, GOSSIP_PROPOSER_SLASHING, GOSSIP_ATTESTER_SLASHING
    mov     x0, #\name
    mov     x1, #0
    bl      node_sub
    .endr
    cmp     x21, #FORK_ALTAIR
    b.lo    9f
    mov     x0, #GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF
    mov     x1, #0
    bl      node_sub
    cmp     x21, #FORK_CAPELLA
    b.lo    9f
    mov     x0, #GOSSIP_BLS_TO_EXECUTION_CHANGE
    mov     x1, #0
    bl      node_sub
    cmp     x21, #FORK_DENEB                /* deneb and electra: every blob sidecar subnet */
    b.lo    9f
    cmp     x21, #FORK_FULU
    b.hs    9f
    LDQ     x25, x19, Node_config + CONFIG_BLOB_SIDECAR_SUBNET_COUNT
    cmp     x21, #FORK_ELECTRA
    b.lo    2f
    LDQ     x25, x19, Node_config + CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA
2:  mov     x22, #0
3:  cmp     x22, x25
    b.hs    9f
    mov     x0, #GOSSIP_BLOB_SIDECAR
    mov     x1, x22
    bl      node_sub
    add     x22, x22, #1
    b       3b
9:  LEAVE 16
END_FUNCTION node_subscribe

/*
 * L0: the MESSAGE x0 of libp2p, whose data is in the libp2p state x1: its MESSAGE_ID, then a
 * NodeMessage with its bytes, uncompressed, in a BYTES_PUT. x21 the notice, x22 the libp2p state,
 * x25 the entry, x26 the scratch size, restored on return, x27 the topic's ByteList, then the
 * bytes', x28 the data's ByteList. Locals: L a GossipTopic, L+24 the message-id, L+48 a length.
 */
LOCAL_FUNCTION node_message
    ENTER 64
    mov     x21, x0
    mov     x22, x1
    ldr     x26, [x23]
    ldr     x9, [x21, #LIBP2P_ACT_MSG_TOPIC_LEN]    /* the topic's and the data's ByteLists at the end of scratch */
    add     x9, x9, #(24 + 7)
    and     x9, x9, #~7
    ldr     x10, [x21, #LIBP2P_ACT_MSG_DATA_LEN]
    add     x10, x10, #(24 + 7)
    and     x10, x10, #~7
    add     x11, x9, x10
    MOVQ    x12, LANTERN_SCRATCH_FIXED
    add     x12, x11, x12
    cmp     x26, x12
    b.lo    99f
    sub     x12, x26, x11
    str     x12, [x23]
    add     x27, x23, x12
    add     x28, x27, x9
    mov     x13, #24
    ldr     x14, [x21, #LIBP2P_ACT_MSG_TOPIC_LEN]
    stp     x9, x13, [x27]
    str     x14, [x27, #16]
    ldr     x15, [x21, #LIBP2P_ACT_MSG_DATA_LEN]
    stp     x10, x13, [x28]
    str     x15, [x28, #16]
    add     x0, x27, #24
    add     x1, x21, #LIBP2P_ACT_MSG_TOPIC
    mov     x2, x14
    bl      lantern_copy
    add     x0, x28, #24
    ldr     x9, [x21, #LIBP2P_ACT_MSG_DATA_OFF]
    add     x1, x22, x9
    ldr     x2, [x21, #LIBP2P_ACT_MSG_DATA_LEN]
    bl      lantern_copy
    mov     x0, x27                         /* the topic */
    add     x1, sp, #L
    bl      lantern_gossip_topic_parse
    cbz     x0, 1f
    stp     xzr, xzr, [sp, #(L + GossipTopic_name)]
1:  mov     x0, x20                         /* the message-id, of the fork of the store's slot */
    bl      node_store_slot
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x27
    mov     x1, x28
    add     x2, x19, #Node_config
    mov     x3, x23
    add     x4, sp, #(L + 24)
    FORK_CALL compute_message_id
    cbnz    x0, 99f
    mov     x0, #LIBP2P_EV_MSG_ID_SIZE      /* MESSAGE_ID */
    bl      node_out
    cbz     x0, 99f
    mov     x9, #LIBP2P_EVENT_MESSAGE_ID
    str     x9, [x0, #8]
    ldr     x9, [x21, #LIBP2P_ACT_HANDLE]
    mov     x10, #20
    stp     x9, x10, [x0, #16]
    add     x0, x0, #32
    stp     xzr, xzr, [x0]
    stp     xzr, xzr, [x0, #16]
    add     x1, sp, #(L + 24)
    mov     x2, #20
    bl      lantern_copy
    PART    x9, x10, x19, Node_messages     /* the entry */
    ldr     x11, [x19, #Node_blobs]
    ldr     x12, [x19, #Node_messages]
    sub     x11, x11, x12
    mov     x12, #NodeMessage__mem
    udiv    x11, x11, x12
    cmp     x10, x11
    b.hs    99f
    madd    x25, x10, x12, x9
    add     x10, x10, #1
    str     x10, [x19, #(Node_messages + 8)]
    mov     x0, x25
    mov     x1, #NodeMessage__mem
    bl      lantern_zero
    ldr     x9, [x21, #LIBP2P_ACT_HANDLE]
    ldr     x10, [x21, #LIBP2P_ACT_MSG_PEER]
    stp     x9, x10, [x25, #NodeMessage_handle]
    ldp     x9, x10, [sp, #(L + GossipTopic_name)]
    stp     x9, x10, [x25, #NodeMessage_topic]
    mov     x9, #NODE_MESSAGE_CORRUPT       /* the bytes, uncompressed */
    str     x9, [x25, #NodeMessage_state]
    mov     x0, x28
    add     x1, sp, #(L + 48)
    CALL_GLOBAL snappy_get_uncompressed_length
    cbnz    x0, 99f
    ldr     x9, [sp, #(L + 48)]
    LDQ     x10, x19, Node_config + CONFIG_MAX_PAYLOAD_SIZE
    cmp     x9, x10
    b.hi    99f
    mov     x10, #NODE_MESSAGE_NO_ROOM
    str     x10, [x25, #NodeMessage_state]
    add     x9, x9, #(24 + 7)
    and     x9, x9, #~7
    ldr     x10, [x23]
    cmp     x10, x9
    b.lo    99f
    add     x0, x9, #48                     /* room for its BYTES_PUT */
    bl      node_room
    cbz     x0, 99f
    ldr     x10, [x23]
    ldr     x9, [sp, #(L + 48)]
    add     x9, x9, #(24 + 7)
    and     x9, x9, #~7
    sub     x10, x10, x9
    str     x10, [x23]
    add     x27, x23, x10
    mov     x10, #24
    stp     x9, x10, [x27]
    str     xzr, [x27, #16]
    mov     x0, x28
    mov     x1, x27
    CALL_GLOBAL snappy_uncompress
    cbz     x0, 2f
    mov     x9, #NODE_MESSAGE_CORRUPT
    str     x9, [x25, #NodeMessage_state]
    b       99f
2:  ldr     x9, [x25, #NodeMessage_topic]   /* the slot and parent root of a block or a block header */
    ldr     x10, [x27, #16]
    add     x11, x27, #24
    cmp     x9, #GOSSIP_BEACON_BLOCK
    b.ne    3f
    cmp     x10, #(100 + 84)
    b.lo    5f
    add     x11, x11, #100
    b       4f
3:  cmp     x9, #GOSSIP_BLOB_SIDECAR
    b.ne    31f
    MOVQ    x12, NODE_BLOB_HEADER + 48
    cmp     x10, x12
    b.lo    5f
    MOVQ    x12, NODE_BLOB_HEADER
    add     x11, x11, x12
    b       4f
31: cmp     x9, #GOSSIP_DATA_COLUMN_SIDECAR
    b.ne    5f
    cmp     x10, #(20 + 48)
    b.lo    5f
    add     x11, x11, #20
4:  ldr     x12, [x11]
    str     x12, [x25, #NodeMessage_slot]
    add     x0, x25, #NodeMessage_parent_root
    add     x1, x11, #16
    mov     x2, #32
    bl      lantern_copy
5:  mov     x0, x27                         /* the bytes, kept by the shell */
    bl      node_put
    str     x0, [x25, #NodeMessage_data_id]
    mov     x9, #NODE_MESSAGE_ID
    str     x9, [x25, #NodeMessage_state]
99: str     x26, [x23]
    LEAVE 64
END_FUNCTION node_message

/*
 * L0: the MESSAGE_STATUS x0 of libp2p. NEW: a GOSSIP work with the head state, for a block or
 * block header a copy of its parent's post-state, and the state of the justified root; or a
 * VALIDATION when the node holds no bytes for it. Else its bytes and its entry go. x21 the notice,
 * x22 the entry, x25 the head state, x26 the proposer state, x27 the justified state.
 */
LOCAL_FUNCTION node_message_status
    ENTER 0
    mov     x21, x0
    ldr     x0, [x21, #LIBP2P_ACT_HANDLE]
    bl      node_find_message
    cmn     x0, #1
    b.eq    99f
    mov     x22, x1
    ldr     x9, [x21, #LIBP2P_ACT_STATUS]
    cmp     x9, #LIBP2P_MSG_NEW
    b.ne    80f
    ldr     x9, [x22, #NodeMessage_state]
    cmp     x9, #NODE_MESSAGE_ID
    b.eq    1f
    mov     x1, #LIBP2P_IGNORE
    cmp     x9, #NODE_MESSAGE_CORRUPT
    b.ne    70f
    mov     x1, #LIBP2P_REJECT
70: ldr     x0, [x22, #NodeMessage_handle]
    bl      node_validation
    b       80f
1:  mov     x0, #(NODE_ACT_WORK_SIZE + 32)  /* room for the work and a state copy */
    bl      node_room
    mov     x1, #LIBP2P_IGNORE
    cbz     x0, 70b
    mov     x25, #0                         /* the head state */
    add     x0, x19, #Node_head_root
    bl      node_find_block
    cmn     x0, #1
    b.eq    2f
    ldr     x25, [x1, #NodeBlock_state_id]
2:  mov     x26, #0                         /* the proposer state: a copy of the parent's, when it comes before */
    ldr     x9, [x22, #NodeMessage_topic]
    cmp     x9, #GOSSIP_BEACON_BLOCK
    ccmp    x9, #GOSSIP_BLOB_SIDECAR, #4, ne
    ccmp    x9, #GOSSIP_DATA_COLUMN_SIDECAR, #4, ne
    b.ne    3f
    add     x0, x22, #NodeMessage_parent_root
    bl      node_find_block
    cmn     x0, #1
    b.eq    3f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    3f
    ldr     x9, [x1, #NodeBlock_slot]
    ldr     x10, [x22, #NodeMessage_slot]
    cmp     x10, x9
    b.ls    3f
    ldr     x27, [x1, #NodeBlock_state_id]
    bl      node_new_id
    mov     x26, x0
    mov     x0, #NODE_ACT_STATE_COPY
    mov     x1, x27
    mov     x2, x26
    bl      node_ids
3:  mov     x27, #0                         /* the state of the justified root */
    add     x0, x20, #(Store_justified_checkpoint + 8)
    bl      node_find_block
    cmn     x0, #1
    b.eq    4f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    4f
    ldr     x27, [x1, #NodeBlock_state_id]
4:  mov     x0, #NODE_WORK_GOSSIP
    mov     x1, x25
    mov     x2, x26
    ldr     x3, [x22, #NodeMessage_data_id]
    ldr     x4, [x22, #NodeMessage_handle]
    ldp     x5, x9, [x22, #NodeMessage_topic]
    orr     x5, x5, x9, lsl #8
    bl      node_work
    str     x27, [x0, #NodeAction_state_c]
    mov     x9, #NODE_MESSAGE_VALIDATING
    str     x9, [x22, #NodeMessage_state]
    LEAVE 0
80: ldr     x1, [x22, #NodeMessage_data_id] /* no work: its bytes and its entry go */
    cbz     x1, 81f
    mov     x0, #32
    bl      node_room
    cbz     x0, 81f
    mov     x0, #NODE_ACT_BYTES_FREE
    ldr     x1, [x22, #NodeMessage_data_id]
    mov     x2, #0
    bl      node_ids
81: mov     x0, x22
    bl      node_drop_message
99: LEAVE 0
END_FUNCTION node_message_status

/* ------------------------------------------------------------ sync */

/* L0: the Status of x2 bytes at x1 (84, or 92 for v2) of the peer of handle x0, kept in its entry. x21 the bytes, x22 their size, x25 the entry. */
LOCAL_FUNCTION node_peer_status
    ENTER 0
    mov     x21, x1
    mov     x22, x2
    bl      node_find_peer
    cmn     x0, #1
    b.eq    9f
    mov     x25, x1
    str     xzr, [x25, #NodePeer_fork_digest]
    add     x0, x25, #NodePeer_fork_digest
    mov     x1, x21
    mov     x2, #4
    bl      lantern_copy
    add     x0, x25, #NodePeer_finalized_root
    add     x1, x21, #4
    mov     x2, #(32 + 8 + 32 + 8)          /* finalized root and epoch, head root and slot */
    bl      lantern_copy
    str     xzr, [x25, #NodePeer_earliest_slot]
    cmp     x22, #92
    b.ne    1f
    add     x0, x25, #NodePeer_earliest_slot
    add     x1, x21, #84
    mov     x2, #8
    bl      lantern_copy
1:  ldr     x9, [x25, #NodePeer_flags]
    orr     x9, x9, #NODE_PEER_STATUS
    str     x9, [x25, #NodePeer_flags]
9:  LEAVE 0
END_FUNCTION node_peer_status

/* L0: x0 = the index of the node's stream in NODE_STREAM_OPENING of tag x0, or 2^64 - 1; x1 = its entry. Uses x9-x13. */
LOCAL_FUNCTION node_find_opening
    UNWIND_END_PROLOGUE
    PART    x1, x10, x19, Node_streams
    ldr     x11, [x19, #Node_stream_bytes]
    mov     x9, #0
1:  cmp     x9, x10
    b.hs    2f
    ldp     x12, x13, [x1, #NodeStream_handle]
    ldr     x13, [x1, #NodeStream_state]
    cmp     x13, #NODE_STREAM_OPENING
    ccmp    x12, x0, #0, eq
    b.eq    3f
    add     x1, x1, x11
    add     x9, x9, #1
    b       1b
2:  mov     x0, #-1
    ret
3:  mov     x0, x9
    ret
END_FUNCTION node_find_opening

/* L0: the stream entry x0 goes; the node's BeaconBlocksByRange request ends with it. */
LOCAL_FUNCTION node_end_stream
    FRAME 16
    ldr     x9, [x0, #NodeStream_state]
    cmp     x9, #NODE_STREAM_OPENING
    b.lo    1f
    ldr     x9, [x0, #NodeStream_method]
    cmp     x9, #REQRESP_BEACON_BLOCKS_BY_RANGE
    b.ne    1f
    ldr     x9, [x19, #Node_flags]
    and     x9, x9, #~NODE_FLAG_SYNCING
    str     x9, [x19, #Node_flags]
1:  bl      node_drop_stream
    UNFRAME 16
END_FUNCTION node_end_stream

/*
 * L0: a request of the node: method x0, version x1, to the peer of handle x2, its SSZ bytes at x3
 * of x4 bytes: a NodeStream in NODE_STREAM_OPENING whose list holds the request chunk, and an
 * OPEN_STREAM of its protocol ID; x0 = the entry, or 0 when the streams part, scratch or p2p_out
 * has no room. x21 the entry, x22 the request's ByteList, x25 the scratch size, restored on
 * return, x26 the peer, x27 the bytes, x28 their size. Locals: L a ChunkHeader, L+48 a
 * ReqRespProtocol, L+64 a ByteList of the protocol ID (152), L+216 the tag.
 */
LOCAL_FUNCTION node_open
    ENTER 224
    stp     x0, x1, [sp, #(L + 48)]
    mov     x26, x2
    mov     x27, x3
    mov     x28, x4
    ldr     x25, [x23]
    PART    x10, x11, x19, Node_streams     /* room for the entry */
    ldr     x12, [x19, #Node_messages]
    ldr     x13, [x19, #Node_streams]
    sub     x12, x12, x13
    ldr     x13, [x19, #Node_stream_bytes]
    udiv    x12, x12, x13
    cmp     x11, x12
    b.hs    8f
    madd    x21, x11, x13, x10
    add     x9, x28, #(24 + 7)              /* the request's ByteList at the end of scratch */
    and     x9, x9, #~7
    subs    x10, x25, x9
    b.lo    8f
    str     x10, [x23]
    add     x22, x23, x10
    mov     x11, #24
    stp     x9, x11, [x22]
    str     x28, [x22, #16]
    add     x0, x22, #24
    mov     x1, x27
    mov     x2, x28
    bl      lantern_copy
    mov     x0, x21                         /* the entry, its list empty */
    mov     x1, #NodeStream__fixed
    bl      lantern_zero
    ldr     x9, [x19, #Node_stream_bytes]
    sub     x9, x9, #NodeStream_list
    mov     x10, #24
    stp     x9, x10, [x21, #NodeStream_list]
    mov     x9, #CHUNK_REQUEST              /* the request chunk in the list */
    str     x9, [sp, #(L + ChunkHeader_kind)]
    str     xzr, [sp, #(L + ChunkHeader_context_length)]
    str     xzr, [sp, #(L + ChunkHeader_result)]
    add     x0, sp, #L
    mov     x1, x22
    mov     x2, x23
    add     x3, x21, #NodeStream_list
    bl      lantern_reqresp_write_chunk
    cbnz    x0, 8f
    mov     x9, #(24 + 128)                 /* the protocol ID */
    mov     x10, #24
    stp     x9, x10, [sp, #(L + 64)]
    str     xzr, [sp, #(L + 80)]
    add     x0, sp, #(L + 48)
    add     x1, sp, #(L + 64)
    bl      lantern_reqresp_protocol_id
    cbnz    x0, 8f
    bl      node_new_id                     /* the tag */
    orr     x0, x0, #NODE_STREAM_TAG
    str     x0, [sp, #(L + 216)]
    mov     x0, #(40 + LIBP2P_PROTO_SIZE)   /* OPEN_STREAM */
    bl      node_out
    cbz     x0, 8f
    mov     x22, x0
    mov     x9, #LIBP2P_EVENT_OPEN_STREAM
    str     x9, [x22, #8]
    ldr     x9, [sp, #(L + 216)]
    stp     x26, x9, [x22, #16]
    mov     x9, #1
    ldr     x10, [sp, #(L + 80)]
    stp     x9, x10, [x22, #32]
    add     x0, x22, #48
    mov     x1, #128
    bl      lantern_zero
    add     x0, x22, #48
    add     x1, sp, #(L + 88)
    ldr     x2, [sp, #(L + 80)]
    bl      lantern_copy
    ldr     x9, [sp, #(L + 216)]            /* the entry joins the part */
    stp     x9, x26, [x21, #NodeStream_handle]
    ldp     x9, x10, [sp, #(L + 48)]
    stp     x9, x10, [x21, #NodeStream_method]
    mov     x9, #NODE_STREAM_OPENING
    str     x9, [x21, #NodeStream_state]
    ldr     x9, [x19, #(Node_streams + 8)]
    add     x9, x9, #1
    str     x9, [x19, #(Node_streams + 8)]
    str     x25, [x23]
    mov     x0, x21
    LEAVE 224
8:  str     x25, [x23]
    mov     x0, #0
    LEAVE 224
END_FUNCTION node_open

/*
 * L0: x0 = 1 when the response bytes of the node's request stream x0 wait for room, else 0. Each
 * complete chunk is read: a Status goes to the peer's entry; a block becomes a NodeBlock in
 * NODE_BLOCK_HASHING, a BYTES_PUT of its bytes and a SYNC_BLOCK work of its root. After a Status,
 * after the last chunk and STREAM_EOF, after an error result, or on a bad chunk (with a
 * STREAM_RESET), the stream ends. x21 the entry, x22 the method, x25 the scratch size, restored on
 * return, x26 the payload's ByteList, x27 the SSZ size, x28 a block entry, then the chunk's bytes.
 * Locals: L a ChunkHeader, L+48 a length, then a block index, L+56 eof, L+64 the payload bytes read.
 */
LOCAL_FUNCTION node_response
    ENTER 80
    mov     x21, x0
    ldr     x22, [x21, #NodeStream_method]
    ldr     x25, [x23]
1:  ldr     x9, [x21, #(NodeStream_list + 16)]
    cbnz    x9, 2f
    ldr     x9, [x21, #NodeStream_next]     /* no bytes: the end after STREAM_EOF */
    cbnz    x9, 80f
    b       90f
2:  mov     x9, #CHUNK_RESPONSE             /* blocks by range v2 and blob sidecars by range: a ForkDigest context */
    str     x9, [sp, #(L + ChunkHeader_kind)]
    mov     x9, #4
    cmp     x22, #REQRESP_BLOB_SIDECARS_BY_RANGE
    b.eq    3f
    mov     x9, #0
    cmp     x22, #REQRESP_BEACON_BLOCKS_BY_RANGE
    b.ne    3f
    ldr     x10, [x21, #NodeStream_version]
    cmp     x10, #2
    b.lo    3f
    mov     x9, #4
3:  str     x9, [sp, #(L + ChunkHeader_context_length)]
    add     x0, x21, #NodeStream_list
    add     x1, sp, #L
    bl      lantern_reqresp_read_header
    cmp     x0, #LANTERN_REQRESP_MORE
    b.eq    5f
    cbnz    x0, 85f
    ldr     x9, [sp, #(L + ChunkHeader_result)]
    cbnz    x9, 80f
    ldr     x27, [sp, #(L + ChunkHeader_length)]
    cmp     x22, #REQRESP_STATUS
    b.ne    4f
    ldr     x10, [x21, #NodeStream_version]
    mov     x11, #84
    cmp     x10, #2
    b.lo    31f
    mov     x11, #92
31: cmp     x27, x11
    b.ne    85f
    b       41f
4:  cmp     x22, #REQRESP_BLOB_SIDECARS_BY_RANGE
    b.ne    42f
    MOVQ    x10, NODE_BLOB_BYTES            /* a blob sidecar: room for its BYTES_PUT, its work, its entry */
    cmp     x27, x10
    b.ne    85f
    MOVQ    x0, NODE_BLOB_BYTES + 48 + NODE_ACT_WORK_SIZE + 7
    bl      node_room
    cbz     x0, 95f
    ldr     x10, [x19, #(Node_blobs + 8)]
    ldr     x11, [x19, #Node_p2p_out]
    ldr     x12, [x19, #Node_blobs]
    sub     x11, x11, x12
    mov     x12, #NodeBlob__mem
    udiv    x11, x11, x12
    cmp     x10, x11
    b.hs    95f
    b       41f
42: cmp     x27, #(100 + 84)                /* a block: room for its BYTES_PUT, its work, its entry */
    b.lo    85f
    LDQ     x10, x19, Node_config + CONFIG_MAX_PAYLOAD_SIZE
    cmp     x27, x10
    b.hi    85f
    add     x0, x27, #(48 + NODE_ACT_WORK_SIZE + 7)
    bl      node_room
    cbz     x0, 95f
    ldr     x10, [x19, #(Node_blocks + 8)]
    ldr     x11, [x19, #Node_checkpoints]
    ldr     x12, [x19, #Node_blocks]
    sub     x11, x11, x12
    mov     x12, #NodeBlock__mem
    udiv    x11, x11, x12
    cmp     x10, x11
    b.hs    95f
41: add     x9, x27, #(24 + 7)              /* the payload's ByteList at the end of scratch */
    and     x9, x9, #~7
    subs    x10, x25, x9
    b.lo    85f
    str     x10, [x23]
    add     x26, x23, x10
    mov     x11, #24
    stp     x9, x11, [x26]
    str     xzr, [x26, #16]
    str     x27, [sp, #(L + 48)]            /* length and eof, by address */
    ldr     x9, [x21, #NodeStream_next]
    str     x9, [sp, #(L + 56)]
    add     x0, x21, #NodeStream_list
    add     x1, sp, #(L + ChunkHeader_header_bytes)
    add     x2, sp, #(L + 48)
    add     x3, sp, #(L + 56)
    mov     x4, x23
    mov     x5, x26
    add     x6, sp, #(L + 64)
    bl      lantern_reqresp_read_payload
    cmp     x0, #LANTERN_REQRESP_MORE
    b.eq    5f
    cbnz    x0, 85f
    cmp     x22, #REQRESP_STATUS
    b.ne    6f
    ldr     x0, [x21, #NodeStream_peer]     /* Status: the peer's */
    add     x1, x26, #24
    mov     x2, x27
    bl      node_peer_status
    b       7f
6:  cmp     x22, #REQRESP_BLOB_SIDECARS_BY_RANGE
    b.eq    61f
    PART    x9, x10, x19, Node_blocks       /* a block: its entry, its bytes, the work of its root */
    mov     x11, #NodeBlock__mem
    madd    x28, x10, x11, x9
    str     x10, [sp, #(L + 48)]
    add     x10, x10, #1
    str     x10, [x19, #(Node_blocks + 8)]
    mov     x0, x28
    mov     x1, #NodeBlock__mem
    bl      lantern_zero
    ldr     x9, [x26, #(24 + 100)]
    str     x9, [x28, #NodeBlock_slot]
    add     x0, x28, #NodeBlock_parent_root
    add     x1, x26, #(24 + 116)
    mov     x2, #32
    bl      lantern_copy
    mov     x9, #NODE_BLOCK_HASHING
    str     x9, [x28, #NodeBlock_status]
    mov     x9, #1
    str     x9, [x28, #NodeBlock_data_available]
    mov     x0, x26
    bl      node_put
    str     x0, [x28, #NodeBlock_data_id]
    mov     x3, x0
    mov     x0, #NODE_WORK_SYNC_BLOCK
    mov     x1, #0
    mov     x2, #0
    ldr     x4, [sp, #(L + 48)]
    mov     x5, #0
    bl      node_work
    b       7f
61: PART    x9, x10, x19, Node_blobs        /* a blob sidecar: its entry, its bytes, the work of its checks */
    mov     x11, #NodeBlob__mem
    madd    x28, x10, x11, x9
    str     x10, [sp, #(L + 48)]
    add     x10, x10, #1
    str     x10, [x19, #(Node_blobs + 8)]
    mov     x0, x28
    mov     x1, #NodeBlob__mem
    bl      lantern_zero
    ldr     x9, [x26, #24]                  /* its index, and the slot of its block header */
    str     x9, [x28, #NodeBlob_index]
    LDQ     x9, x26, 24 + NODE_BLOB_HEADER
    str     x9, [x28, #NodeBlob_slot]
    mov     x9, #NODE_BLOB_VERIFYING
    str     x9, [x28, #NodeBlob_status]
    mov     x0, x26
    bl      node_put
    str     x0, [x28, #NodeBlob_data_id]
    mov     x3, x0
    mov     x0, #NODE_WORK_BLOB
    mov     x1, #0
    mov     x2, #0
    ldr     x4, [sp, #(L + 48)]
    mov     x5, #0
    bl      node_work
7:  str     x25, [x23]                      /* the chunk leaves the list */
    ldr     x9, [sp, #(L + ChunkHeader_header_bytes)]
    ldr     x10, [sp, #(L + 64)]
    add     x28, x9, x10
    ldr     x9, [x21, #(NodeStream_list + 16)]
    sub     x2, x9, x28
    str     x2, [x21, #(NodeStream_list + 16)]
    add     x0, x21, #NodeStream_request
    add     x1, x0, x28
    bl      lantern_copy
    cmp     x22, #REQRESP_STATUS            /* Status: one chunk */
    b.eq    80f
    b       1b
5:  str     x25, [x23]                      /* part of a chunk: more bytes, or the end after STREAM_EOF */
    ldr     x9, [x21, #NodeStream_next]
    cbnz    x9, 80f
90: mov     x0, #0
    LEAVE 80
95: mov     x0, #1
    LEAVE 80
85: str     x25, [x23]                      /* a bad chunk: a reset */
    mov     x0, #LIBP2P_EVENT_STREAM_RESET
    ldr     x1, [x21, #NodeStream_handle]
    bl      node_out_handle
80: mov     x0, x21
    bl      node_end_stream
    mov     x0, #0
    LEAVE 80
END_FUNCTION node_response

/*
 * L0: x0 = 1 when a response waits for room, else 0. The bytes of each response are read; then,
 * with no BeaconBlocksByRange of the node open, one to a peer of the node's ForkDigest whose
 * Status head_slot is at least the next slot: max(the head's slot + 1, sync_slot), at most
 * NODE_SYNC_BATCH slots. Before it, with room for two streams, a BlobSidecarsByRange of the
 * range's slots in the blob window before fulu. x21 a peer, x22 the streams or peers left, x26
 * the result, x27 the start slot. Locals: L the request (24), L+24 the blob request (16).
 */
LOCAL_FUNCTION node_sync
    ENTER 48
    mov     x26, #0
    ldr     x22, [x19, #(Node_streams + 8)] /* the responses, from the last stream: an end moves the last */
1:  cbz     x22, 3f
    sub     x22, x22, #1
    ldr     x9, [x19, #Node_streams]
    add     x9, x19, x9
    ldr     x10, [x19, #Node_stream_bytes]
    madd    x0, x22, x10, x9
    ldr     x9, [x0, #NodeStream_state]
    cmp     x9, #NODE_STREAM_RESPONSE
    b.ne    1b
    bl      node_response
    orr     x26, x26, x0
    b       1b
3:  ldr     x9, [x19, #Node_flags]
    tbnz    x9, #3, 9f                      /* NODE_FLAG_SYNCING */
    add     x0, x19, #Node_head_root
    bl      node_find_block
    cmn     x0, #1
    b.eq    9f
    ldr     x27, [x1, #NodeBlock_slot]
    add     x27, x27, #1
    ldr     x9, [x19, #Node_sync_slot]
    cmp     x9, x27
    csel    x27, x9, x27, hi
    PART    x21, x22, x19, Node_peers       /* a peer ahead */
4:  cbz     x22, 9f
    ldr     x9, [x21, #NodePeer_flags]
    tbz     x9, #0, 5f                      /* NODE_PEER_STATUS */
    ldr     x9, [x21, #NodePeer_fork_digest]
    ldr     x10, [x19, #Node_fork_digest]
    cmp     x9, x10
    b.ne    5f
    ldr     x9, [x21, #NodePeer_head_slot]
    cmp     x9, x27
    b.hs    6f
5:  add     x21, x21, #NodePeer__mem
    sub     x22, x22, #1
    b       4b
6:  sub     x9, x9, x27                     /* the request: start_slot, count, step 1 */
    add     x9, x9, #1
    mov     x10, #NODE_SYNC_BATCH
    cmp     x9, x10
    csel    x9, x9, x10, lo
    stp     x27, x9, [sp, #L]
    mov     x10, #1
    str     x10, [sp, #(L + 16)]
    mov     x0, x20                         /* the blob window's first slot: of max(store epoch - MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS, DENEB_FORK_EPOCH) */
    bl      node_store_slot
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x0, x0, x9
    LDQ     x10, x19, Node_config + CONFIG_MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS
    subs    x0, x0, x10
    csel    x0, xzr, x0, lo
    ldr     x10, [x19, #(Node_config + 16 * FORK_DENEB)]
    cmp     x0, x10
    csel    x0, x10, x0, lo
    umulh   x10, x0, x9
    cbnz    x10, 7f
    mul     x0, x0, x9
    ldp     x11, x12, [sp, #L]              /* the range from there, before fulu's first slot */
    adds    x12, x11, x12
    csinv   x12, x12, xzr, cc
    cmp     x11, x0
    csel    x11, x0, x11, lo
    ldr     x10, [x19, #(Node_config + 16 * FORK_FULU)]
    umulh   x13, x10, x9
    cbnz    x13, 8f
    mul     x10, x10, x9
    cmp     x12, x10
    csel    x12, x10, x12, hi
8:  cmp     x11, x12
    b.hs    7f
    sub     x12, x12, x11
    stp     x11, x12, [sp, #(L + 24)]
    ldr     x11, [x19, #(Node_streams + 8)] /* room for it and the blocks' request */
    ldr     x12, [x19, #Node_messages]
    ldr     x13, [x19, #Node_streams]
    sub     x12, x12, x13
    ldr     x13, [x19, #Node_stream_bytes]
    udiv    x12, x12, x13
    add     x11, x11, #2
    cmp     x11, x12
    b.hi    9f
    mov     x0, #REQRESP_BLOB_SIDECARS_BY_RANGE
    mov     x1, #1
    ldr     x2, [x21, #NodePeer_handle]
    add     x3, sp, #(L + 24)
    mov     x4, #16
    bl      node_open
    cbz     x0, 9f
7:  mov     x0, x20                         /* version 2 from altair on */
    bl      node_store_slot
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x1, #1
    cmp     x0, #FORK_ALTAIR
    cinc    x1, x1, hs
    mov     x0, #REQRESP_BEACON_BLOCKS_BY_RANGE
    ldr     x2, [x21, #NodePeer_handle]
    add     x3, sp, #L
    mov     x4, #24
    bl      node_open
    cbz     x0, 9f
    ldr     x9, [x19, #Node_flags]
    orr     x9, x9, #NODE_FLAG_SYNCING
    str     x9, [x19, #Node_flags]
    ldp     x9, x10, [sp, #L]
    add     x9, x9, x10
    str     x9, [x19, #Node_sync_slot]
9:  mov     x0, x26
    LEAVE 48
END_FUNCTION node_sync

/*
 * L0: the libp2p application notice x0 of the libp2p state x1. x21 the notice, x22 an entry, x25
 * method, x26 version, x27 the state. Locals: L a Status (96).
 */
LOCAL_FUNCTION node_notice
    ENTER 96
    mov     x21, x0
    mov     x27, x1
    ldr     x9, [x21, #LIBP2P_ACT_KIND]
    cmp     x9, #LIBP2P_ACTION_MESSAGE
    b.ne    60f
    mov     x0, x21
    mov     x1, x27
    bl      node_message
    LEAVE 96
60: cmp     x9, #LIBP2P_ACTION_MESSAGE_STATUS
    b.ne    62f
    mov     x0, x21
    bl      node_message_status
    LEAVE 96
62: cmp     x9, #LIBP2P_ACTION_STREAM_OPENED
    b.ne    63f
    ldr     x0, [x21, #LIBP2P_ACT_SO_TAG]   /* the node's request stream: the request, then the close of our side */
    bl      node_find_opening
    cmn     x0, #1
    b.eq    69f
    mov     x22, x1
    ldr     x9, [x21, #LIBP2P_ACT_STREAM]
    str     x9, [x22, #NodeStream_handle]
    mov     x9, #NODE_STREAM_RESPONSE
    str     x9, [x22, #NodeStream_state]
    str     xzr, [x22, #NodeStream_next]
    ldr     x26, [x22, #(NodeStream_list + 16)]
    add     x25, x26, #(32 + 7)
    and     x25, x25, #~7
    add     x0, x25, #24
    bl      node_out
    cbz     x0, 68f
    mov     x10, #LIBP2P_EVENT_STREAM_WRITE
    stp     x25, x10, [x0]
    ldr     x10, [x22, #NodeStream_handle]
    stp     x10, x26, [x0, #16]
    add     x11, x0, x25
    mov     x12, #24
    mov     x13, #LIBP2P_EVENT_STREAM_CLOSE
    stp     x12, x13, [x11]
    str     x10, [x11, #16]
    add     x0, x0, #32
    add     x1, x22, #NodeStream_request
    mov     x2, x26
    bl      lantern_copy
    str     xzr, [x22, #(NodeStream_list + 16)]
69: LEAVE 96
68: mov     x0, #LIBP2P_EVENT_STREAM_RESET  /* no room: a reset */
    ldr     x1, [x22, #NodeStream_handle]
    bl      node_out_handle
    mov     x0, x22
    bl      node_end_stream
    LEAVE 96
63: cmp     x9, #LIBP2P_ACTION_STREAM_FAILED
    b.ne    61f
    ldr     x0, [x21, #LIBP2P_ACT_STREAM]   /* its tag */
    bl      node_find_opening
    cmn     x0, #1
    b.eq    69b
    mov     x0, x1
    bl      node_end_stream
    LEAVE 96
61: cmp     x9, #LIBP2P_ACTION_PEER_CONNECTED
    b.ne    64f
    ldr     x10, [x21, #LIBP2P_ACT_PC_TAG]  /* a dial of the node ends */
    tst     x10, #NODE_DIAL_TAG
    b.eq    65f
    ldr     x10, [x19, #Node_dialing]
    cbz     x10, 65f
    sub     x10, x10, #1
    str     x10, [x19, #Node_dialing]
65: PART    x10, x11, x19, Node_peers       /* a new peer: its entry, or DISCONNECT when the table is full */
    ldr     x12, [x19, #Node_streams]
    ldr     x13, [x19, #Node_peers]
    sub     x12, x12, x13
    mov     x13, #NodePeer__mem
    udiv    x12, x12, x13
    cmp     x11, x12
    b.lo    1f
    mov     x0, #LIBP2P_EVENT_DISCONNECT
    ldr     x1, [x21, #LIBP2P_ACT_PEER]
    bl      node_out_handle
    LEAVE 96
1:  madd    x22, x11, x13, x10
    add     x11, x11, #1
    str     x11, [x19, #(Node_peers + 8)]
    mov     x0, x22
    mov     x1, #NodePeer__mem
    bl      lantern_zero
    ldr     x9, [x21, #LIBP2P_ACT_PEER]
    str     x9, [x22, #NodePeer_handle]
    ldr     x9, [x21, #LIBP2P_ACT_PC_DIRECTION]
    str     x9, [x22, #NodePeer_direction]
    ldr     x2, [x21, #LIBP2P_ACT_PC_ID_LEN]
    cmp     x2, #48
    b.ls    2f
    mov     x2, #48
2:  str     x2, [x22, #NodePeer_id_len]
    add     x0, x22, #NodePeer_id
    add     x1, x21, #LIBP2P_ACT_PC_ID
    bl      lantern_copy
    ldr     x9, [x22, #NodePeer_direction]  /* we dialled: our Status first (v2 from fulu, v1 before) */
    cmp     x9, #LIBP2P_OUTBOUND
    b.ne    69b
    add     x0, sp, #L
    bl      node_status_bytes
    mov     x0, x20
    bl      node_store_slot
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x1, #1
    mov     x4, #84
    cmp     x0, #FORK_FULU
    b.lo    3f
    mov     x1, #2
    mov     x4, #92
3:  mov     x0, #REQRESP_STATUS
    ldr     x2, [x22, #NodePeer_handle]
    add     x3, sp, #L
    bl      node_open
    LEAVE 96
64: cmp     x9, #LIBP2P_ACTION_DIAL_FAILED
    b.ne    10f
    ldr     x10, [x21, #LIBP2P_ACT_TAG]     /* a dial of the node ends */
    tst     x10, #NODE_DIAL_TAG
    b.eq    69b
    ldr     x10, [x19, #Node_dialing]
    cbz     x10, 69b
    sub     x10, x10, #1
    str     x10, [x19, #Node_dialing]
    LEAVE 96
10: cmp     x9, #LIBP2P_ACTION_PEER_DISCONNECTED
    b.ne    20f
    ldr     x0, [x21, #LIBP2P_ACT_PEER]
    bl      node_find_peer
    cmn     x0, #1
    b.eq    19f
    mov     x0, x1
    bl      node_drop_peer
19: LEAVE 96
20: cmp     x9, #LIBP2P_ACTION_STREAM_INBOUND
    b.ne    30f
    ldr     x0, [x21, #LIBP2P_ACT_SI_PROTOCOL]      /* a request stream: its entry, or a reset */
    bl      node_protocol
    cbz     x0, 28f
    mov     x25, x0
    mov     x26, x1
    PART    x10, x11, x19, Node_streams
    ldr     x12, [x19, #Node_messages]
    ldr     x13, [x19, #Node_streams]
    sub     x12, x12, x13
    ldr     x13, [x19, #Node_stream_bytes]
    udiv    x12, x12, x13
    cmp     x11, x12
    b.hs    28f
    madd    x22, x11, x13, x10
    add     x11, x11, #1
    str     x11, [x19, #(Node_streams + 8)]
    ldr     x9, [x21, #LIBP2P_ACT_STREAM]
    ldr     x10, [x21, #LIBP2P_ACT_SI_PEER]
    stp     x9, x10, [x22, #NodeStream_handle]
    stp     x25, x26, [x22, #NodeStream_method]
    mov     x9, #NODE_STREAM_REQUEST
    str     x9, [x22, #NodeStream_state]
    sub     x9, x13, #NodeStream_list
    mov     x10, #24
    stp     x9, x10, [x22, #NodeStream_list]
    str     xzr, [x22, #(NodeStream_list + 16)]
    mov     x0, x22
    bl      node_request
    LEAVE 96
28: mov     x0, #LIBP2P_EVENT_STREAM_RESET
    ldr     x1, [x21, #LIBP2P_ACT_STREAM]
    bl      node_out_handle
    LEAVE 96
30: cmp     x9, #LIBP2P_ACTION_STREAM_DATA
    b.ne    40f
    ldr     x0, [x21, #LIBP2P_ACT_STREAM]   /* request bytes: kept, then read */
    bl      node_find_stream
    cmn     x0, #1
    b.eq    39f
    mov     x22, x1
    ldr     x9, [x22, #(NodeStream_list + 16)]
    ldr     x10, [x21, #LIBP2P_ACT_SD_COUNT]
    ldr     x11, [x22, #NodeStream_list]
    sub     x11, x11, #24
    sub     x11, x11, x9
    cmp     x10, x11
    b.hi    38f
    add     x0, x22, #NodeStream_request
    add     x0, x0, x9
    add     x1, x21, #LIBP2P_ACT_SD_DATA
    mov     x2, x10
    add     x9, x9, x10
    str     x9, [x22, #(NodeStream_list + 16)]
    bl      lantern_copy
    mov     x0, x22
    ldr     x9, [x22, #NodeStream_state]
    cmp     x9, #NODE_STREAM_RESPONSE
    b.ne    37f
    bl      node_response                   /* response bytes of the node's request */
    LEAVE 96
37: bl      node_request
39: LEAVE 96
38: mov     x0, #LIBP2P_EVENT_STREAM_RESET  /* more than the room: a reset */
    ldr     x1, [x22, #NodeStream_handle]
    bl      node_out_handle
    mov     x0, x22
    bl      node_end_stream
    LEAVE 96
40: cmp     x9, #LIBP2P_ACTION_STREAM_EOF
    b.ne    50f
    ldr     x0, [x21, #LIBP2P_ACT_STREAM]
    bl      node_find_stream
    cmn     x0, #1
    b.eq    49f
    ldr     x9, [x1, #NodeStream_state]
    cmp     x9, #NODE_STREAM_RESPONSE
    b.ne    41f
    mov     x9, #1                          /* the response is complete */
    str     x9, [x1, #NodeStream_next]
    mov     x0, x1
    bl      node_response
    LEAVE 96
41: cmp     x9, #NODE_STREAM_EOF            /* while its request is read */
    b.hi    49f
    mov     x9, #NODE_STREAM_EOF
    str     x9, [x1, #NodeStream_state]
    mov     x0, x1
    bl      node_request
49: LEAVE 96
50: cmp     x9, #LIBP2P_ACTION_STREAM_RESET
    b.ne    59f
    ldr     x0, [x21, #LIBP2P_ACT_STREAM]
    bl      node_find_stream
    cmn     x0, #1
    b.eq    59f
    mov     x0, x1
    bl      node_end_stream
59: LEAVE 96
END_FUNCTION node_notice

/* L0: x0 = the WAKEUP time of the libp2p actions in the ByteList x0, after their application notices, of the libp2p state x1. x21 an action, x22 the end, x25 the time, x26 the state. */
LOCAL_FUNCTION node_p2p_notices
    ENTER 0
    mov     x26, x1
    ldp     x9, x10, [x0, #8]
    add     x21, x0, x9
    add     x22, x21, x10
    mov     x25, #-1
1:  cmp     x21, x22
    b.hs    9f
    ldr     x9, [x21, #LIBP2P_ACT_KIND]
    cmp     x9, #LIBP2P_ACTION_WAKEUP
    b.ne    2f
    ldr     x25, [x21, #LIBP2P_ACT_TIME]
    b       3f
2:  cmp     x9, #LIBP2P_ACTION_PEER_CONNECTED
    b.lo    3f
    cmp     x9, #LIBP2P_ACTION_SEND_DATAGRAM
    b.hs    3f
    mov     x0, x21
    mov     x1, x26
    bl      node_notice
3:  ldr     x9, [x21]
    add     x21, x21, x9
    b       1b
9:  mov     x0, x25
    LEAVE 0
END_FUNCTION node_p2p_notices

/* L0: the libp2p events of the P2P events from x0 to x1 join the end of the node's queued events. x21, x22 the range, x25 the queue. */
LOCAL_FUNCTION node_p2p_append
    ENTER 0
    mov     x21, x0
    mov     x22, x1
    P2P_OUT x25
1:  cmp     x21, x22
    b.hs    9f
    ldr     x9, [x21, #8]
    cmp     x9, #NODE_EV_P2P
    b.ne    2f
    ldr     x2, [x21, #16]
    ldr     x9, [x25, #16]
    add     x0, x25, #24
    add     x0, x0, x9
    add     x10, x9, x2
    str     x10, [x25, #16]
    add     x1, x21, #16
    bl      lantern_copy
2:  ldr     x9, [x21]
    add     x21, x21, x9
    b       1b
9:  LEAVE 0
END_FUNCTION node_p2p_append

/*
 * L0: of the P2P events from x0 to x1, the first x2 were taken: x0 = the next P2P event, or x1;
 * x1 = the bytes of the libp2p events of the P2P events from there on. Uses x9-x11.
 */
LOCAL_FUNCTION node_p2p_left
    UNWIND_END_PROLOGUE
    mov     x9, x0
    mov     x10, x1
    mov     x0, x1
    mov     x1, #0
1:  cmp     x9, x10
    b.hs    9f
    ldr     x11, [x9, #8]
    cmp     x11, #NODE_EV_P2P
    b.ne    3f
    cbz     x2, 2f
    sub     x2, x2, #1
    b       3f
2:  cmp     x0, x10
    b.ne    21f
    mov     x0, x9
21: ldr     x11, [x9, #16]
    add     x1, x1, x11
3:  ldr     x11, [x9]
    add     x9, x9, x11
    b       1b
9:  ret
END_FUNCTION node_p2p_left

/* L0: x0 = the events in the first x0 bytes of the node's queue. Uses x9-x12. */
LOCAL_FUNCTION node_out_count
    UNWIND_END_PROLOGUE
    P2P_OUT x9
    add     x9, x9, #24
    mov     x10, #0
    mov     x11, #0
1:  cmp     x10, x0
    b.hs    2f
    ldr     x12, [x9, x10]
    add     x10, x10, x12
    add     x11, x11, #1
    b       1b
2:  mov     x0, x11
    ret
END_FUNCTION node_out_count

/*
 * L0: libp2p_step of the state x0 with the tick x1, the event list x2 and the scratch x3, its
 * actions in a P2P_LIST action that takes the action room left less x4 bytes, its StepResult at
 * x5: x0 = 0 and x1 = the actions' ByteList; 1 when the room is short; or libp2p's status, with
 * no action added. x21 state, x22 tick, x25 list, x26 scratch, x27 result, x28 the action.
 */
LOCAL_FUNCTION node_p2p_round
    ENTER 0
    mov     x21, x0
    mov     x22, x1
    mov     x25, x2
    mov     x26, x3
    mov     x27, x5
    ldp     x9, x10, [x24, #8]
    ldr     x11, [x24]
    sub     x11, x11, x9
    sub     x11, x11, x10
    subs    x11, x11, x4
    b.lo    8f
    MOVQ    x12, LIBP2P_ACTIONS_MIN + 24 + 16
    cmp     x11, x12
    b.lo    8f
    lsr     x13, x11, #1                    /* half of it, when that is enough: the rest for the notices */
    cmp     x13, x12
    csel    x11, x13, x11, hs
    and     x11, x11, #~7
    add     x28, x24, x9
    add     x28, x28, x10
    mov     x12, #NODE_ACT_P2P_LIST
    stp     x11, x12, [x28]
    sub     x12, x11, #16
    mov     x13, #24
    stp     x12, x13, [x28, #16]
    str     xzr, [x28, #32]
    mov     x0, x21
    mov     x1, x22
    mov     x2, x25
    mov     x3, x26
    add     x4, x28, #16
    mov     x5, x27
    CALL_GLOBAL libp2p_step
    cbnz    x0, 9f
    ldr     x9, [x28, #32]                  /* the action holds the actions written */
    add     x10, x9, #24
    str     x10, [x28, #16]
    add     x10, x10, #16
    str     x10, [x28]
    ldr     x11, [x24, #16]
    add     x11, x11, x10
    str     x11, [x24, #16]
    add     x1, x28, #16
    mov     x0, #0
    LEAVE 0
8:  mov     x0, #1
9:  LEAVE 0
END_FUNCTION node_p2p_round

/*
 * (out, count): the protocol IDs of the req/resp protocols the node answers, as libp2p
 * ProtocolEntry values in the ByteList out, by method then version; count = how many.
 * x19 out, x20 count, x21 the protocols, x22 an index, x23 an entry. Locals: L a ReqRespProtocol,
 * L+16 a ByteList of an ID.
 */
FUNCTION lantern_node_protocols
    ENTER 176
    mov     x19, x0
    mov     x20, x1
    mov     x21, #0
1:  mov     x0, x21
    bl      node_protocol
    cbz     x0, 2f
    add     x21, x21, #1
    b       1b
2:  mov     x9, #LIBP2P_PROTO_SIZE
    mul     x9, x21, x9
    add     x10, x9, #24
    ldr     x11, [x19]
    cmp     x11, x10
    b.lo    8f
    mov     x10, #24
    stp     x10, x9, [x19, #8]
    str     x21, [x20]
    mov     x22, #0
    add     x23, x19, #24
3:  cmp     x22, x21
    b.hs    7f
    mov     x0, x22
    bl      node_protocol
    stp     x0, x1, [sp, #L]
    mov     x0, x23
    mov     x1, #LIBP2P_PROTO_SIZE
    bl      lantern_zero
    mov     x9, #(24 + 128)
    mov     x10, #24
    stp     x9, x10, [sp, #(L + 16)]
    str     xzr, [sp, #(L + 32)]
    add     x0, sp, #L
    add     x1, sp, #(L + 16)
    bl      lantern_reqresp_protocol_id
    ldr     x2, [sp, #(L + 32)]
    str     x2, [x23]
    add     x0, x23, #8
    add     x1, sp, #(L + 40)
    bl      lantern_copy
    add     x23, x23, #LIBP2P_PROTO_SIZE
    add     x22, x22, #1
    b       3b
7:  mov     x0, #LANTERN_OK
    LEAVE 176
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 176
END_FUNCTION lantern_node_protocols

/*
 * L0: the root entry at x28 of the BLOCK event x0: its first u64 is 0 and the root follows, or the
 * first u64 is not 0 when the bytes are no SignedBeaconBlock. x0 = the status.
 */
LOCAL_FUNCTION node_block_entry
    ENTER 16
    add     x21, x0, #NodeEvent_bytes
    mov     x9, #1
    str     x9, [x28]
    ldr     x9, [x21, #16]
    cmp     x9, #(100 + 84)
    b.lo    9f
    ldr     x9, [x21, #8]
    add     x9, x21, x9
    ldr     x0, [x9, #100]                  /* the slot of the message */
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x21
    mov     x1, x23
    add     x2, x28, #8
    mov     x3, x28
    add     x4, sp, #L                      /* its blob count: not kept */
    FORK_CALL node_block_root
    LEAVE 16
9:  mov     x0, #LANTERN_OK
    LEAVE 16
END_FUNCTION node_block_entry

/*
 * (node, store, p2p, tick, events, scratch, actions, result): x19 node, x20 store, x21 the
 * events, x22 their end, x23 scratch, x24 actions, x25 result, x26 the event count, x27 the
 * BLOCK, POW_BLOCK and GOSSIP WORK_DONE events, x28 the event bytes, then the root entries of the BLOCK events.
 * Locals: L the WORK_DONE events, L+8 the scratch size, L+16 p2p, L+24 tick, L+32 the end of
 * the events handled, L+40 the queue's free bytes the P2P events take, saved, L+48 the libp2p scratch, L+56 the bytes of
 * the P2P events, L+64 the P2P events, L+72 the action room kept for the node, L+80 wakeup,
 * L+88 libp2p's StepResult, L+96 libp2p's actions, L+104 the libp2p steps, L+112 a stream waits,
 * L+120 the GOSSIP WORK_DONE events, L+128 the bytes of the ENGINE events, L+136 1 with an ENR event.
 */
FUNCTION lantern_node_step
    ENTER 144
    mov     x19, x0
    mov     x20, x1
    stp     x2, x3, [sp, #(L + 16)]
    ldp     x9, x10, [x4, #8]
    add     x21, x4, x9
    add     x22, x21, x10
    mov     x23, x5
    mov     x24, x6
    mov     x25, x7
    mov     x26, #0                         /* first: check every event, and count */
    mov     x27, #0
    mov     x28, #0
    str     xzr, [sp, #L]
    str     xzr, [sp, #(L + 120)]
    str     xzr, [sp, #(L + 128)]
    str     xzr, [sp, #(L + 136)]
    stp     xzr, xzr, [sp, #(L + 56)]
    mov     x11, x21
1:  cmp     x11, x22
    b.hs    5f
    sub     x9, x22, x11
    cmp     x9, #16
    b.lo    7f
    ldp     x12, x13, [x11]                 /* size, kind */
    cmp     x12, #16
    b.lo    7f
    tst     x12, #7
    b.ne    7f
    cmp     x12, x9
    b.hi    7f
    sub     x14, x13, #1
    cmp     x14, #NODE_EV_LAST
    b.hs    7f
    cmp     x13, #NODE_EV_TICK
    b.ne    2f
    cmp     x12, #24
    b.lo    7f
    b       4f
2:  cmp     x13, #NODE_EV_WORK_DONE
    b.ne    21f
    cmp     x12, #NODE_EV_WORK_DONE_SIZE
    b.lo    7f
    ldr     x14, [x11, #NodeAction_work_kind]   /* SERVE, and NEW_PAYLOAD or FORKCHOICE of LANTERN_VALID: a ByteList of the chunk inside */
    cmp     x14, #NODE_WORK_GOSSIP          /* GOSSIP: a block or a blob it may add */
    cinc    x27, x27, eq
    b.ne    23f
    ldr     x15, [sp, #(L + 120)]
    add     x15, x15, #1
    str     x15, [sp, #(L + 120)]
23: cmp     x14, #NODE_WORK_SERVE
    b.eq    24f
    cmp     x14, #NODE_WORK_NEW_PAYLOAD
    ccmp    x14, #NODE_WORK_FORKCHOICE, #4, ne
    b.ne    22f
    ldr     x15, [x11, #NodeEvent_result]
    cbnz    x15, 22f
24:
    cmp     x12, #(NodeEvent_chunk + 24)
    b.lo    7f
    ldp     x14, x15, [x11, #(NodeEvent_chunk + 8)]
    cmp     x14, #24
    b.ne    7f
    sub     x14, x12, #(NodeEvent_chunk + 24)
    cmp     x15, x14
    b.hi    7f
22: ldr     x14, [sp, #L]
    add     x14, x14, #1
    str     x14, [sp, #L]
    b       4f
21: cmp     x13, #NODE_EV_ENGINE            /* ENGINE: arg 0 with bytes, or 1; with NODE_FLAG_ENGINE */
    b.ne    211f
    ldr     x14, [x19, #Node_flags]
    tbz     x14, #4, 7f
    cmp     x12, #24
    b.lo    7f
    ldr     x14, [x11, #16]
    cmp     x14, #1
    b.hi    7f
    b.eq    4f
    cmp     x12, #(24 + 24)
    b.lo    7f
    ldp     x14, x15, [x11, #(24 + 8)]
    cmp     x14, #24
    b.ne    7f
    sub     x14, x12, #(24 + 24)
    cmp     x15, x14
    b.hi    7f
    ldr     x14, [sp, #(L + 128)]
    add     x14, x14, x15
    str     x14, [sp, #(L + 128)]
    b       4f
211: cmp    x13, #NODE_EV_P2P               /* a libp2p event inside, for a node with a libp2p state */
    b.ne    3f
    ldr     x14, [sp, #(L + 16)]
    cbz     x14, 7f
    cmp     x12, #(16 + 16)
    b.lo    7f
    ldr     x14, [x11, #16]
    cmp     x14, #16
    b.lo    7f
    tst     x14, #7
    b.ne    7f
    sub     x15, x12, #16
    cmp     x14, x15
    b.hi    7f
    ldp     x15, x16, [sp, #(L + 56)]
    add     x15, x15, x14
    add     x16, x16, #1
    stp     x15, x16, [sp, #(L + 56)]
    b       4f
3:  cmp     x13, #NODE_EV_PAYLOAD_STATUS    /* the ByteList at 24: its bytes inside the event */
    b.eq    7f
    cmp     x12, #(24 + 24)
    b.lo    7f
    ldp     x14, x15, [x11, #(24 + 8)]
    cmp     x14, #24
    b.ne    7f
    sub     x14, x12, #(24 + 24)
    cmp     x15, x14
    b.hi    7f
    cmp     x13, #NODE_EV_ENR               /* ENR: with p2p */
    b.ne    31f
    ldr     x14, [sp, #(L + 16)]
    cbz     x14, 7f
    mov     x14, #1
    str     x14, [sp, #(L + 136)]
31: cmp     x13, #NODE_EV_BLOCK
    ccmp    x13, #NODE_EV_POW_BLOCK, #4, ne
    cinc    x27, x27, eq
4:  add     x26, x26, #1
    add     x28, x28, x12
    add     x11, x11, x12
    b       1b
5:  mov     x12, #512                       /* room: actions, node parts, scratch */
    madd    x12, x26, x12, x28
    ldr     x13, [x19, #(Node_blocks + 8)]
    mov     x14, #128
    madd    x12, x13, x14, x12
    add     x12, x12, #512
    str     x12, [sp, #(L + 72)]
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 51f
    MOVQ    x9, LIBP2P_ACTIONS_MIN + 24 + 16
    add     x12, x12, x9
51: ldp     x9, x10, [x24, #8]
    ldr     x11, [x24]
    subs    x11, x11, x9
    b.lo    81f
    subs    x11, x11, x10
    b.lo    81f
    cmp     x11, x12
    b.lo    81f
    ldr     x9, [x19, #Node_checkpoints]    /* blocks: one entry for each BLOCK event */
    ldr     x10, [x19, #Node_blocks]
    sub     x9, x9, x10
    mov     x10, #NodeBlock__mem
    udiv    x9, x9, x10
    ldr     x10, [x19, #(Node_blocks + 8)]
    sub     x9, x9, x10
    ldr     x11, [sp, #(L + 16)]            /* with p2p, NODE_SYNC_BATCH more for the responses */
    cmp     x11, #0
    mov     x12, #NODE_SYNC_BATCH
    csel    x12, x12, xzr, ne
    add     x10, x27, x12
    cmp     x9, x10
    b.lo    82f
    ldr     x9, [x19, #Node_p2p_out]        /* blobs: one for each GOSSIP WORK_DONE event, and with p2p a batch's sidecars */
    ldr     x10, [x19, #Node_blobs]
    sub     x9, x9, x10
    mov     x10, #NodeBlob__mem
    udiv    x9, x9, x10
    ldr     x10, [x19, #(Node_blobs + 8)]
    sub     x9, x9, x10
    ldr     x10, [sp, #(L + 120)]
    ldr     x11, [sp, #(L + 16)]
    cbz     x11, 54f
    LDQ     x11, x19, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK
    LDQ     x12, x19, Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
    cmp     x11, x12
    csel    x11, x12, x11, lo
    lsr     x12, x11, #32
    cbnz    x12, 82f
    mov     x12, #NODE_SYNC_BATCH
    madd    x10, x11, x12, x10
54: cmp     x9, x10
    b.lo    82f
    ldr     x9, [x19, #Node_engine_in]      /* engine_in: the bytes of the ENGINE events */
    add     x9, x19, x9
    ldr     x10, [x9]
    ldr     x11, [x9, #16]
    sub     x10, x10, #24
    sub     x10, x10, x11
    ldr     x11, [sp, #(L + 128)]
    cmp     x10, x11
    b.lo    82f
    ldr     x9, [x19, #Node_pow_blocks]     /* checkpoints: two for each WORK_DONE event, and two */
    ldr     x10, [x19, #Node_checkpoints]
    sub     x9, x9, x10
    mov     x10, #NodeCheckpoint__mem
    udiv    x9, x9, x10
    ldr     x10, [x19, #(Node_checkpoints + 8)]
    sub     x9, x9, x10
    ldr     x10, [sp, #L]
    lsl     x10, x10, #1
    add     x10, x10, #2
    cmp     x9, x10
    b.lo    82f
    ldr     x9, [x19, #Node_peers]          /* pow blocks: one for each POW_BLOCK event */
    ldr     x10, [x19, #Node_pow_blocks]
    sub     x9, x9, x10
    mov     x10, #POW_BLOCK_BYTES
    udiv    x9, x9, x10
    ldr     x10, [x19, #(Node_pow_blocks + 8)]
    sub     x9, x9, x10
    cmp     x9, x27
    b.lo    82f
    mov     x9, #NODE_ROOT_ENTRY            /* scratch: the root entries, and with p2p the queue's bytes the P2P events take and libp2p's scratch, at its end */
    mul     x12, x27, x9
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 52f
    P2P_OUT x13                             /* the queue has room for the P2P events */
    ldr     x9, [x13]
    ldr     x10, [x13, #16]
    sub     x9, x9, #24
    sub     x9, x9, x10
    ldr     x10, [sp, #(L + 56)]
    cmp     x9, x10
    b.lo    82f
    add     x12, x12, x10
    MOVQ    x9, LIBP2P_SCRATCH_SIZE
    add     x12, x12, x9
52: ldr     x9, [x20, #Store_validators]    /* and what get_head needs */
    ldr     x10, [x20, #Store_blocks]
    sub     x9, x9, x10
    lsl     x9, x9, #4
    mov     x10, #BlockNode__mem
    udiv    x9, x9, x10
    MOVQ    x10, LANTERN_SCRATCH_FIXED + 64
    add     x9, x9, x10
    add     x9, x9, x12
    ldr     x10, [sp, #(L + 136)]           /* with an ENR event, the record's decoding */
    cbz     x10, 55f
    MOVQ    x10, DISCV5_ENR_SIZE + DISCV5_ENR_SCRATCH
    add     x9, x9, x10
55:
    ldr     x10, [x23]
    cmp     x10, x9
    b.lo    83f
    str     x10, [sp, #(L + 8)]
    sub     x10, x10, x12
    str     x10, [x23]
    add     x28, x23, x10
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 53f
    mov     x9, #NODE_ROOT_ENTRY
    madd    x9, x27, x9, x28                /* the saved queue bytes, then libp2p's scratch */
    str     x9, [sp, #(L + 40)]
    ldr     x10, [sp, #(L + 56)]
    add     x9, x9, x10
    str     x9, [sp, #(L + 48)]
    MOVQ    x10, LIBP2P_SCRATCH_SIZE
    str     x10, [x9]
53: mov     x9, #NODE_SHORT_SCRATCH         /* the root of each BLOCK event, before any change; its room: scratch */
    str     x9, [x25, #NodeStepResult_short]
    mov     x27, x21
11: cmp     x27, x22
    b.hs    13f
    ldr     x9, [x27, #8]
    cmp     x9, #NODE_EV_BLOCK
    b.ne    12f
    mov     x0, x27
    bl      node_block_entry
    cbnz    x0, 14f
    add     x28, x28, #NODE_ROOT_ENTRY
12: ldr     x9, [x27]
    add     x27, x27, x9
    b       11b
13: str     x22, [sp, #(L + 32)]            /* libp2p: the queued events, then the P2P events */
    mov     x9, #-1
    str     x9, [sp, #(L + 80)]
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 30f
    P2P_OUT x27                             /* x27 the queue, x28 its bytes before the P2P events */
    ldr     x28, [x27, #16]
    ldr     x0, [sp, #(L + 40)]             /* the free bytes of the queue the P2P events take, kept */
    add     x1, x27, #24
    add     x1, x1, x28
    ldr     x2, [sp, #(L + 56)]
    bl      lantern_copy
    mov     x0, x21
    mov     x1, x22
    bl      node_p2p_append
    ldp     x0, x1, [sp, #(L + 16)]
    mov     x2, x27
    ldr     x3, [sp, #(L + 48)]
    ldr     x4, [sp, #(L + 72)]
    add     x5, sp, #(L + 88)
    bl      node_p2p_round
    cbz     x0, 24f
    str     x0, [sp, #(L + 104)]            /* a status of libp2p: the queue as it was, and nothing else changed */
    str     x28, [x27, #16]
    add     x0, x27, #24
    add     x0, x0, x28
    ldr     x1, [sp, #(L + 40)]
    ldr     x2, [sp, #(L + 56)]
    bl      lantern_copy
    ldr     x9, [sp, #(L + 104)]
    cmp     x9, #LIBP2P_BUFFER_TOO_SMALL
    mov     x9, #LANTERN_BUFFER_TOO_SMALL
    mov     x10, #LANTERN_INVALID_EVENT
    csel    x0, x9, x10, eq
    mov     x9, #NODE_SHORT_ACTIONS         /* libp2p's room: actions */
    str     x9, [x25, #NodeStepResult_short]
    b       14f
24: str     x1, [sp, #(L + 96)]             /* from here on the step holds */
    mov     x0, x28                         /* the P2P events libp2p took: k less the queued ones */
    bl      node_out_count
    ldr     x9, [sp, #(L + 88)]
    subs    x2, x9, x0
    csel    x2, x2, xzr, hs
    mov     x0, x21
    mov     x1, x22
    bl      node_p2p_left
    str     x0, [sp, #(L + 32)]             /* the step ends at the next one */
    ldr     x9, [x27, #16]                  /* the ones left go from the queue's end */
    sub     x9, x9, x1
    str     x9, [x27, #16]
    ldr     x0, [sp, #(L + 88)]             /* the ones taken from its front */
    bl      node_out_consume
29: ldr     x0, [sp, #(L + 96)]
    ldr     x1, [sp, #(L + 16)]
    bl      node_p2p_notices
    str     x0, [sp, #(L + 80)]
30: ldr     x9, [x23]                       /* then each event, in order */
    add     x28, x23, x9
    mov     x26, #0
    mov     x27, x21
6:  ldr     x9, [sp, #(L + 32)]
    cmp     x27, x9
    b.hs    9f
    add     x26, x26, #1
    ldr     x9, [x27, #8]
    cmp     x9, #NODE_EV_P2P
    b.eq    15f
    mov     x0, x27
    bl      node_event
    ldr     x9, [x27, #8]
    cmp     x9, #NODE_EV_BLOCK
    b.ne    15f
    add     x28, x28, #NODE_ROOT_ENTRY
15: ldr     x9, [x27]
    add     x27, x27, x9
    b       6b
9:  bl      node_head
    bl      node_engine_next
    str     xzr, [sp, #(L + 112)]
    ldr     x9, [sp, #(L + 16)]             /* the next block of each stream that serves, then libp2p again */
    cbz     x9, 40f
    bl      node_subscribe
    bl      node_serve
    str     x0, [sp, #(L + 112)]
    bl      node_sync
    ldr     x9, [sp, #(L + 112)]
    orr     x9, x9, x0
    str     x9, [sp, #(L + 112)]
    ldr     x0, [sp, #(L + 24)]
    bl      node_lookup
    str     xzr, [sp, #(L + 104)]
32: P2P_OUT x2
    ldr     x9, [x2, #16]
    cbz     x9, 40f
    ldr     x10, [sp, #(L + 104)]
    cmp     x10, #NODE_P2P_ROUNDS
    b.hs    40f
    add     x10, x10, #1
    str     x10, [sp, #(L + 104)]
    ldp     x0, x1, [sp, #(L + 16)]
    ldr     x3, [sp, #(L + 48)]
    mov     x4, #4096
    add     x5, sp, #(L + 88)
    bl      node_p2p_round
    cbnz    x0, 40f
    str     x1, [sp, #(L + 96)]
    ldr     x0, [sp, #(L + 88)]
    bl      node_out_consume
    ldr     x0, [sp, #(L + 96)]
    ldr     x1, [sp, #(L + 16)]
    bl      node_p2p_notices
    str     x0, [sp, #(L + 80)]
    b       32b
40: P2P_OUT x9                              /* events left, or a stream that waits: the next step is due now */
    ldr     x9, [x9, #16]
    ldr     x10, [sp, #(L + 112)]
    orr     x9, x9, x10
    cbz     x9, 41f
    ldr     x10, [sp, #(L + 24)]
    ldr     x10, [x10, #LIBP2P_TICK_NOW]
    str     x10, [sp, #(L + 80)]
41: ldr     x9, [sp, #(L + 8)]
    str     x9, [x23]
    ldr     x9, [sp, #(L + 80)]
    stp     x26, x9, [x25]
    mov     x0, #LANTERN_OK
    LEAVE 144
14: ldr     x9, [sp, #(L + 8)]              /* a status before any change */
    str     x9, [x23]
    LEAVE 144
7:  mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 144
81: mov     x9, #NODE_SHORT_ACTIONS         /* the buffer with too little room */
    b       84f
82: mov     x9, #NODE_SHORT_NODE
    b       84f
83: mov     x9, #NODE_SHORT_SCRATCH
84: str     x9, [x25, #NodeStepResult_short]
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 144
END_FUNCTION lantern_node_step

/*
 * (node, store, seen, work, state_a, state_b, state_c, data, settings, scratch, event): x19 node,
 * x20 store, x21 work, x22 state_a, x23 data, x24 scratch, x25 event, x26 the event's room.
 * Locals: L the BlockOptions (32), or a chunk's size, a fork digest and a ChunkHeader (64);
 * L+64 seen, L+72 state_b, L+80 state_c, L+88 settings, L+96 a NodeGossip.
 */
FUNCTION lantern_node_run
    ENTER 192
    mov     x19, x0
    mov     x20, x1
    mov     x21, x3
    mov     x22, x4
    stp     x2, x5, [sp, #(L + 64)]         /* seen, state_b, state_c, settings */
    str     x6, [sp, #(L + 80)]
    mov     x23, x7
    ldp     x9, x24, [sp, #(96 + 192)]      /* the ninth to eleventh arguments */
    str     x9, [sp, #(L + 88)]
    ldr     x25, [sp, #(96 + 192 + 16)]
    ldr     x26, [x25]                      /* the event's room */
    cmp     x26, #NODE_EV_WORK_DONE_SIZE
    b.lo    7f
    mov     x9, #NODE_EV_WORK_DONE_SIZE     /* the event: the work's fields, the result */
    mov     x10, #NODE_EV_WORK_DONE
    stp     x9, x10, [x25]
    .irp off, 16, 24, 32, 40, 48, 56, 64
    ldr     x9, [x21, #\off]
    str     x9, [x25, #\off]
    .endr
    add     x0, x25, #NodeEvent_result
    mov     x1, #(NODE_EV_WORK_DONE_SIZE - NodeEvent_result)
    bl      lantern_zero
    ldr     x9, [x21, #NodeAction_work_kind]
    cmp     x9, #NODE_WORK_IMPORT_BLOCK
    b.ne    10f
    ldr     x9, [x19, #Node_flags]          /* IMPORT_BLOCK: the options, then the fork's on_block */
    tst     x9, #NODE_FLAG_OPTIMISTIC
    mov     x12, #PAYLOAD_STATUS_VALID
    mov     x10, #PAYLOAD_STATUS_NOT_VALIDATED
    csel    x12, x10, x12, ne
    ldr     x0, [x21, #NodeAction_target]
    PART    x9, x10, x19, Node_blocks
    mov     x11, #0
    cmp     x0, x10
    b.hs    1f
    mov     x10, #NodeBlock__mem
    madd    x9, x0, x10, x9
    ldr     x11, [x9, #NodeBlock_data_available]
    ldr     x10, [x19, #Node_flags]         /* with NODE_FLAG_ENGINE, the block's: the engine's answer */
    tst     x10, #NODE_FLAG_ENGINE
    b.eq    1f
    ldr     x12, [x9, #NodeBlock_payload_status]
1:  str     x12, [sp, #(L + BlockOptions_payload_status)]
    str     x11, [sp, #(L + BlockOptions_data_available)]
    str     xzr, [sp, #(L + BlockOptions_pow_block)]
    str     xzr, [sp, #(L + BlockOptions_pow_parent)]
    ldr     x9, [x23, #16]
    cmp     x9, #(100 + 84)
    b.lo    18f
    ldr     x9, [x23, #8]
    add     x9, x23, x9
    ldr     x0, [x9, #100]
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x20
    mov     x1, x19
    mov     x2, x23
    mov     x3, x22
    add     x4, sp, #L
    mov     x5, x24
    add     x6, x25, #NodeEvent_result
    FORK_CALL node_import
    cmp     x0, #LANTERN_NEED_JUSTIFIED_STATE
    b.ne    99f
    str     x0, [x25, #NodeEvent_result]
    mov     x0, #LANTERN_OK
    LEAVE 192
18: mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x25, #NodeEvent_result]
    mov     x0, #LANTERN_OK
    LEAVE 192
10: cmp     x9, #NODE_WORK_JUSTIFIED_STATE
    b.ne    20f
    ldr     x0, [x22, #NODE_STATE_SLOT]     /* JUSTIFIED_STATE: the fork of the state's slot */
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x20
    mov     x1, x22
    FORK_CALL store_justified_checkpoint_state
    LEAVE 192
20: cmp     x9, #NODE_WORK_TARGET_STATE
    b.ne    30f
    ldr     x0, [x22, #NODE_STATE_SLOT]     /* TARGET_STATE: store_target_checkpoint_state of the checkpoint */
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    ldr     x9, [x21, #NodeAction_target]
    PART    x1, x10, x19, Node_checkpoints
    cmp     x9, x10
    b.hs    8f
    mov     x10, #NodeCheckpoint__mem
    madd    x1, x9, x10, x1
    mov     x0, x22
    add     x2, x19, #Node_config
    mov     x3, x24
    add     x4, x25, #NodeEvent_result
    FORK_CALL store_target_checkpoint_state
    LEAVE 192
30: cmp     x9, #NODE_WORK_ATTESTATION
    b.ne    40f
    ldr     x9, [x23, #16]                  /* ATTESTATION: the fork of its slot */
    cmp     x9, #(4 + 128 + 96)
    b.lo    18b
    ldr     x9, [x23, #8]
    add     x9, x23, x9
    ldr     x0, [x9, #4]
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x20
    mov     x1, x23
    add     x2, x21, #NodeAction_arg
    mov     x3, x22
    mov     x4, x24
    add     x5, x25, #NodeEvent_result
    add     x6, x25, #NodeEvent_checkpoint
    FORK_CALL node_attestation
    LEAVE 192
40: cmp     x9, #NODE_WORK_ATTESTER_SLASHING
    b.ne    50f
    mov     x0, x20                         /* ATTESTER_SLASHING: the fork of the store's slot */
    bl      node_store_slot
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x20
    mov     x1, x23
    mov     x2, x22
    mov     x3, x24
    add     x4, x25, #NodeEvent_result
    FORK_CALL node_attester_slashing
99: LEAVE 192
50: cmp     x9, #NODE_WORK_SERVE
    b.ne    60f
    ldr     x10, [x21, #NodeAction_arg]     /* SERVE: the chunk of the block's or sidecar's bytes, with room for it */
    lsr     x10, x10, #8
    cmp     x10, #REQRESP_BLOB_SIDECARS_BY_RANGE
    ccmp    x10, #REQRESP_BLOB_SIDECARS_BY_ROOT, #4, ne
    ldr     x9, [x23, #16]
    mov     x11, #(100 + 84)
    MOVQ    x12, NODE_BLOB_HEADER + 8
    csel    x11, x12, x11, eq
    cmp     x9, x11
    b.lo    18b
    str     x9, [sp, #L]
    add     x0, sp, #L
    add     x1, sp, #L
    bl      lantern_reqresp_chunk_size
    ldr     x9, [sp, #L]
    add     x9, x9, #(NodeEvent_chunk + 24 + 7)
    and     x9, x9, #~7
    cmp     x26, x9
    b.lo    7f
    ldr     x9, [x23, #8]                   /* the context: ForkDigest of the epoch of the block's or header's slot */
    add     x9, x23, x9
    ldr     x10, [x21, #NodeAction_arg]
    lsr     x10, x10, #8
    cmp     x10, #REQRESP_BLOB_SIDECARS_BY_RANGE
    ccmp    x10, #REQRESP_BLOB_SIDECARS_BY_ROOT, #4, ne
    b.eq    51f
    ldr     x27, [x9, #100]
    b       52f
51: LDQ     x27, x9, NODE_BLOB_HEADER
52:
    mov     x0, x27
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x9, x27, x9
    str     x9, [sp, #L]
    str     xzr, [sp, #(L + 8)]
    add     x0, x19, #Node_genesis_validators_root
    add     x1, sp, #L
    add     x2, x19, #Node_config
    mov     x3, x24
    add     x4, sp, #(L + 8)
    FORK_CALL compute_fork_digest
    cbnz    x0, 99b
    mov     x9, #CHUNK_RESPONSE             /* the header: blocks v1 have no context bytes */
    str     x9, [sp, #(L + 16 + ChunkHeader_kind)]
    ldr     x9, [x21, #NodeAction_arg]
    and     x10, x9, #255
    lsr     x9, x9, #8
    cmp     x9, #REQRESP_BLOB_SIDECARS_BY_RANGE
    ccmp    x9, #REQRESP_BLOB_SIDECARS_BY_ROOT, #4, ne
    ccmp    x10, #2, #2, ne                 /* a blob method: C set, so hs */
    mov     x9, #4
    csel    x9, x9, xzr, hs
    str     x9, [sp, #(L + 16 + ChunkHeader_context_length)]
    str     xzr, [sp, #(L + 16 + ChunkHeader_result)]
    ldr     w9, [sp, #(L + 8)]
    str     x9, [sp, #(L + 16 + ChunkHeader_context)]
    add     x27, x25, #NodeEvent_chunk      /* the chunk's ByteList after the WORK_DONE fields */
    sub     x9, x26, #NodeEvent_chunk
    mov     x10, #24
    stp     x9, x10, [x27]
    str     xzr, [x27, #16]
    add     x0, sp, #(L + 16)
    mov     x1, x23
    mov     x2, x24
    mov     x3, x27
    bl      lantern_reqresp_write_chunk
    cbnz    x0, 99b
    ldr     x9, [x27, #16]                  /* the sizes of the list and the event */
    add     x9, x9, #(24 + 7)
    and     x9, x9, #~7
    str     x9, [x27]
    add     x9, x9, #NodeEvent_chunk
    str     x9, [x25]
    mov     x0, #LANTERN_OK
    LEAVE 192
60: cmp     x9, #NODE_WORK_GOSSIP
    b.ne    70f
    ldr     x9, [sp, #(L + 64)]             /* GOSSIP: the inputs of the fork's node_gossip */
    str     x9, [sp, #(L + 96 + NodeGossip_seen)]
    str     x20, [sp, #(L + 96 + NodeGossip_store)]
    ldr     x9, [x19, #Node_time_ms]
    str     x9, [sp, #(L + 96 + NodeGossip_time_ms)]
    ldr     x9, [x21, #NodeAction_arg]
    and     x10, x9, #255
    lsr     x9, x9, #8
    str     x10, [sp, #(L + 96 + NodeGossip_topic)]
    str     x9, [sp, #(L + 96 + NodeGossip_subnet)]
    str     x22, [sp, #(L + 96 + NodeGossip_head)]
    ldp     x9, x10, [sp, #(L + 72)]
    str     x9, [sp, #(L + 96 + NodeGossip_proposer)]
    str     x10, [sp, #(L + 96 + NodeGossip_justified)]
    ldr     x9, [sp, #(L + 88)]
    str     x9, [sp, #(L + 96 + NodeGossip_settings)]
    add     x9, x19, #Node_config
    str     x9, [sp, #(L + 96 + NodeGossip_config)]
    mov     x0, x20
    bl      node_store_slot
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    add     x0, sp, #(L + 96)
    mov     x1, x23
    mov     x2, x24
    add     x3, x25, #NodeEvent_result
    add     x4, x25, #NodeEvent_root
    add     x5, x25, #NodeEvent_index
    FORK_CALL node_gossip
    LEAVE 192
70: cmp     x9, #NODE_WORK_SYNC_BLOCK
    b.ne    80f
    ldr     x9, [x23, #16]                  /* SYNC_BLOCK: node_block_root of the fork of its slot */
    cmp     x9, #(100 + 84)
    b.lo    18b
    ldr     x9, [x23, #8]
    add     x9, x23, x9
    ldr     x0, [x9, #100]
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x23
    mov     x1, x24
    add     x2, x25, #NodeEvent_root
    add     x3, x25, #NodeEvent_result
    add     x4, x25, #NodeEvent_index
    FORK_CALL node_block_root
    LEAVE 192
80: cmp     x9, #NODE_WORK_BLOB
    b.ne    82f
    ldr     x9, [x23, #16]                  /* BLOB: node_blob_sidecar of the fork of its slot, deneb or electra */
    MOVQ    x10, NODE_BLOB_HEADER + 8
    cmp     x9, x10
    b.lo    18b
    ldr     x9, [x23, #8]
    add     x9, x23, x9
    LDQ     x0, x9, NODE_BLOB_HEADER
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x23
    add     x1, x19, #Node_config
    ldr     x2, [sp, #(L + 88)]
    mov     x3, x24
    add     x4, x25, #NodeEvent_result
    add     x5, x25, #NodeEvent_root
    cmp     x15, #FORK_DENEB
    b.ne    81f
    CALL_GLOBAL lantern_deneb_node_blob_sidecar
    LEAVE 192
81: cmp     x15, #FORK_ELECTRA
    b.ne    18b
    CALL_GLOBAL lantern_electra_node_blob_sidecar
    LEAVE 192
82: cmp     x9, #NODE_WORK_NEW_PAYLOAD
    b.ne    83f
    ldr     x9, [x23, #16]                  /* NEW_PAYLOAD: node_new_payload of the fork of the block's slot */
    cmp     x9, #(100 + 84)
    b.lo    18b
    ldr     x9, [x23, #8]
    add     x9, x23, x9
    ldr     x0, [x9, #100]
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    cmp     x15, #FORK_BELLATRIX
    b.lo    86f
    cmp     x26, #(NodeEvent_chunk + 24)
    b.lo    7f
    add     x27, x25, #NodeEvent_chunk      /* the request's ByteList after the WORK_DONE fields */
    sub     x9, x26, #NodeEvent_chunk
    mov     x10, #24
    stp     x9, x10, [x27]
    str     xzr, [x27, #16]
    mov     x0, x23
    mov     x1, x19
    add     x2, x21, #NodeAction_arg
    mov     x3, x24
    mov     x4, x27
    add     x5, x25, #NodeEvent_result
    FORK_CALL_BELLATRIX node_new_payload
    cbnz    x0, 99b
    ldr     x9, [x25, #NodeEvent_result]
    cbnz    x9, 99b
    b       84f
83: cmp     x9, #NODE_WORK_FORKCHOICE
    b.ne    8f
    mov     x0, x20                         /* FORKCHOICE: of the fork of the store's slot */
    bl      node_store_slot
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x28, x0
    cmp     x28, #FORK_BELLATRIX
    b.lo    86f
    add     x0, x19, #Node_head_root        /* the ForkchoiceState at L+96: head, safe (justified), finalized */
    bl      node_store_find
    cmn     x0, #1
    b.eq    87f
    add     x9, sp, #(L + 96)
    add     x10, x1, #BlockNode_block_hash
    COPY32  x9, x10
    add     x0, x20, #(Store_justified_checkpoint + 8)
    bl      node_store_find
    cmn     x0, #1
    b.eq    87f
    add     x9, sp, #(L + 128)
    add     x10, x1, #BlockNode_block_hash
    COPY32  x9, x10
    add     x0, x20, #(Store_finalized_checkpoint + 8)
    bl      node_store_find
    cmn     x0, #1
    b.eq    87f
    add     x9, sp, #(L + 160)
    add     x10, x1, #BlockNode_block_hash
    COPY32  x9, x10
    ldp     x9, x10, [sp, #(L + 96)]        /* a head of no payload: no call */
    ldp     x11, x12, [sp, #(L + 112)]
    orr     x9, x9, x10
    orr     x11, x11, x12
    orr     x9, x9, x11
    cbz     x9, 86f
    cmp     x26, #(NodeEvent_chunk + 24)
    b.lo    7f
    ldr     x27, [x24]                      /* at the end of scratch: the JSON (536), the token (280), the host (88) */
    MOVQ    x9, 904 + 512
    cmp     x27, x9
    b.lo    7f
    sub     x10, x27, #904
    str     x10, [x24]
    add     x22, x24, x10
    mov     x11, #24
    mov     x9, #536
    stp     x9, x11, [x22]
    str     xzr, [x22, #16]
    mov     x9, #280
    add     x12, x22, #536
    stp     x9, x11, [x12]
    str     xzr, [x12, #16]
    mov     x9, #88
    add     x12, x22, #816
    stp     x9, x11, [x12]
    ldr     x2, [x19, #Node_engine_host_len]
    str     x2, [x12, #16]
    add     x0, x22, #(816 + 24)
    add     x1, x19, #Node_engine_host
    bl      lantern_copy
    add     x0, sp, #(L + 96)
    add     x1, x21, #NodeAction_arg
    mov     x2, x22
    mov     x15, x28
    FORK_CALL_BELLATRIX engine_forkchoice_updated
    cbnz    x0, 85f
    ldr     x9, [x19, #Node_time_ms]        /* the JWT at the time in seconds */
    mov     x10, #1000
    udiv    x9, x9, x10
    str     x9, [sp, #L]
    add     x0, x19, #Node_jwt_secret
    add     x1, sp, #L
    mov     x2, x24
    add     x3, x22, #536
    bl      lantern_jwt_token
    cbnz    x0, 85f
    add     x3, x25, #NodeEvent_chunk       /* the HTTP request after the WORK_DONE fields */
    sub     x9, x26, #NodeEvent_chunk
    mov     x10, #24
    stp     x9, x10, [x3]
    str     xzr, [x3, #16]
    add     x0, x22, #816
    add     x1, x22, #536
    mov     x2, x22
    bl      lantern_http_post
    cbnz    x0, 85f
    str     x27, [x24]
    add     x27, x25, #NodeEvent_chunk
84: ldr     x9, [x27, #16]                  /* the sizes of the list and the event */
    add     x9, x9, #(24 + 7)
    and     x9, x9, #~7
    str     x9, [x27]
    add     x9, x9, #NodeEvent_chunk
    str     x9, [x25]
    mov     x0, #LANTERN_OK
    LEAVE 192
85: str     x27, [x24]                      /* a status, with the scratch's size back */
    LEAVE 192
86: mov     x9, #LANTERN_NO_PAYLOAD
    str     x9, [x25, #NodeEvent_result]
    mov     x0, #LANTERN_OK
    LEAVE 192
87: mov     x9, #LANTERN_INVALID_UNKNOWN_BLOCK
    str     x9, [x25, #NodeEvent_result]
    mov     x0, #LANTERN_OK
    LEAVE 192
8:  mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 192
7:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 192
END_FUNCTION lantern_node_run
