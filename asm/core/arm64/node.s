/*
 * The node core, ARM64: in the common object. Requirements: docs/reference/node.md.
 */

.set NODE_ROOT_ENTRY, 40                /* lantern_node_step: a flag, then the root of a BLOCK event */

/* Call lantern_<fork>_<name> for the fork in x15 (FORK_PHASE0 to FORK_FULU). */
.macro FORK_CALL name
    cmp     x15, #FORK_ALTAIR
    b.hs    81f
    CALL_GLOBAL lantern_phase0_\name
    b       89f
81: cmp     x15, #FORK_BELLATRIX
    b.hs    82f
    CALL_GLOBAL lantern_altair_\name
    b       89f
82: cmp     x15, #FORK_CAPELLA
    b.hs    83f
    CALL_GLOBAL lantern_bellatrix_\name
    b       89f
83: cmp     x15, #FORK_DENEB
    b.hs    84f
    CALL_GLOBAL lantern_capella_\name
    b       89f
84: cmp     x15, #FORK_ELECTRA
    b.hs    85f
    CALL_GLOBAL lantern_deneb_\name
    b       89f
85: cmp     x15, #FORK_FULU
    b.hs    86f
    CALL_GLOBAL lantern_electra_\name
    b       89f
86: CALL_GLOBAL lantern_fulu_\name
89:
.endm

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
    ldr     x10, [x0, #NodeRoom_p2p_out]
    adds    x10, x10, #7
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
    str     x9, [x0, #Node_p2p_out]
    str     xzr, [x0, #(Node_p2p_out + 8)]
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
    mov     x0, x24
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
    NODE_COPY_ROOM p2p_out, Node_p2p_out
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
    PART    x1, x2, x19, Node_p2p_out       /* the queued bytes */
    str     x2, [x21, #(Node_p2p_out + 8)]
    ldr     x9, [x21, #Node_p2p_out]
    add     x0, x21, x9
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

/* L0: a WORK action: kind x0, state_a x1, state_b x2, data x3, target x4, arg x5. */
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
    stp     x9, x10, [x0, #NodeAction_state_b]
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
 * L0: the import of the block of index x0 when its parent has a post-state: a copy of it and an
 * IMPORT_BLOCK work; a block whose parent is invalid becomes invalid. x21 index, x22 entry.
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
    LEAVE 0
8:  mov     x9, #NODE_BLOCK_INVALID
    str     x9, [x22, #NodeBlock_status]
9:  LEAVE 0
END_FUNCTION node_try_import

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
    COPY32  x9, x10
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
    b.ne    50f
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
    add     x0, x21, #NodeAction_work_kind
    ldp     x0, x1, [x0]
    ldp     x2, x3, [x21, #NodeAction_state_b]
    ldp     x4, x5, [x21, #NodeAction_target]
    bl      node_work
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
    b.ne    70f
    cmp     x10, #LANTERN_NEED_TARGET_STATE
    b.ne    70f
    ldr     x0, [x21, #NodeEvent_checkpoint]    /* the target state, then the same attestation again */
    add     x1, x21, #(NodeEvent_checkpoint + 8)
    bl      node_checkpoint_state
    cbz     x0, 71f
    mov     x1, x0
    mov     x0, #NODE_WORK_ATTESTATION
    ldp     x2, x3, [x21, #NodeAction_state_b]
    ldp     x4, x5, [x21, #NodeAction_target]
    bl      node_work
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
    ldp     x9, x10, [x19, #Node_p2p_out]   /* offset, bytes used; the part ends at the node's end */
    ldr     x11, [x19]
    sub     x11, x11, x9
    sub     x11, x11, x10
    cmp     x11, x0
    b.lo    1f
    add     x12, x19, x9
    add     x12, x12, x10
    add     x10, x10, x0
    str     x10, [x19, #(Node_p2p_out + 8)]
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
    ldp     x9, x10, [x19, #Node_p2p_out]
    add     x11, x19, x9
    mov     x12, #0
1:  cbz     x0, 2f
    cmp     x12, x10
    b.hs    2f
    ldr     x13, [x11, x12]
    add     x12, x12, x13
    sub     x0, x0, #1
    b       1b
2:  sub     x2, x10, x12
    str     x2, [x19, #(Node_p2p_out + 8)]
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
    bl      node_drop_stream
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
    mov     x1, #3                          /* ResourceUnavailable */
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
    cmp     x9, x25
    b.ne    90f
    ldr     x26, [x23]                      /* the payload's ByteList at the end of scratch */
    sub     x9, x26, #128
    str     x9, [x23]
    add     x27, x23, x9
    mov     x9, #128
    mov     x10, #24
    stp     x9, x10, [x27]
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
    bl      node_find_peer
    cmn     x0, #1
    b.eq    21f
    mov     x26, x1
    str     xzr, [x26, #NodePeer_fork_digest]
    add     x0, x26, #NodePeer_fork_digest
    mov     x1, x27
    mov     x2, #4
    bl      lantern_copy
    add     x0, x26, #NodePeer_finalized_root
    add     x1, x27, #4
    mov     x2, #(32 + 8 + 32 + 8)          /* finalized root and epoch, head root and slot */
    bl      lantern_copy
    str     xzr, [x26, #NodePeer_earliest_slot]
    cmp     x25, #92
    b.ne    22f
    add     x0, x26, #NodePeer_earliest_slot
    add     x1, x27, #84
    mov     x2, #8
    bl      lantern_copy
22: ldr     x9, [x26, #NodePeer_flags]
    orr     x9, x9, #NODE_PEER_STATUS
    str     x9, [x26, #NodePeer_flags]
21: mov     x0, x20                         /* ForkDigest of the store's epoch */
    bl      node_store_slot
    mov     x26, x0
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x9, x26, x9
    str     x9, [sp, #(L + 48)]
    add     x1, sp, #(L + 48)
    add     x0, x19, #Node_genesis_validators_root
    add     x2, x19, #Node_config
    mov     x3, x23
    add     x4, sp, #(L + 56)
    FORK_CALL compute_fork_digest
    add     x0, sp, #(L + 64)
    add     x1, sp, #(L + 56)
    mov     x2, #4
    bl      lantern_copy
    add     x0, sp, #(L + 64 + 4)           /* finalized_root, finalized_epoch */
    add     x1, x20, #(Store_finalized_checkpoint + 8)
    mov     x2, #32
    bl      lantern_copy
    add     x0, sp, #(L + 64 + 36)
    add     x1, x20, #Store_finalized_checkpoint
    mov     x2, #8
    bl      lantern_copy
    add     x0, sp, #(L + 64 + 44)          /* head_root, head_slot */
    add     x1, x19, #Node_head_root
    mov     x2, #32
    bl      lantern_copy
    add     x0, x19, #Node_head_root
    bl      node_find_block
    mov     x9, #0
    cmn     x0, #1
    b.eq    23f
    ldr     x9, [x1, #NodeBlock_slot]
23: str     x9, [sp, #(L + 56)]
    add     x0, sp, #(L + 64 + 76)
    add     x1, sp, #(L + 56)
    mov     x2, #8
    bl      lantern_copy
    add     x0, sp, #(L + 64 + 84)          /* earliest_available_slot: Status v2 */
    add     x1, x19, #Node_earliest_slot
    mov     x2, #8
    bl      lantern_copy
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
80: ldr     x9, [x21, #NodeStream_state]    /* more bytes come, unless the peer closed */
    cmp     x9, #NODE_STREAM_EOF
    b.eq    90f
    LEAVE 160
90: mov     x1, #1                          /* InvalidRequest */
91: mov     x0, x21
    mov     x2, sp
    mov     x3, #0
    bl      node_respond
    LEAVE 160
END_FUNCTION node_request

/* L0: the libp2p application notice x0. x21 the notice, x22 an entry, x25 method, x26 version. */
LOCAL_FUNCTION node_notice
    ENTER 0
    mov     x21, x0
    ldr     x9, [x21, #LIBP2P_ACT_KIND]
    cmp     x9, #LIBP2P_ACTION_PEER_CONNECTED
    b.ne    10f
    PART    x10, x11, x19, Node_peers       /* a new peer: its entry, or DISCONNECT when the table is full */
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
    LEAVE 0
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
    LEAVE 0
10: cmp     x9, #LIBP2P_ACTION_PEER_DISCONNECTED
    b.ne    20f
    ldr     x0, [x21, #LIBP2P_ACT_PEER]
    bl      node_find_peer
    cmn     x0, #1
    b.eq    19f
    mov     x0, x1
    bl      node_drop_peer
19: LEAVE 0
20: cmp     x9, #LIBP2P_ACTION_STREAM_INBOUND
    b.ne    30f
    ldr     x0, [x21, #LIBP2P_ACT_SI_PROTOCOL]      /* a request stream: its entry, or a reset */
    bl      node_protocol
    cbz     x0, 28f
    mov     x25, x0
    mov     x26, x1
    PART    x10, x11, x19, Node_streams
    ldr     x12, [x19, #Node_p2p_out]
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
    LEAVE 0
28: mov     x0, #LIBP2P_EVENT_STREAM_RESET
    ldr     x1, [x21, #LIBP2P_ACT_STREAM]
    bl      node_out_handle
    LEAVE 0
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
    bl      node_request
39: LEAVE 0
38: mov     x0, #LIBP2P_EVENT_STREAM_RESET  /* more than the room: a reset */
    ldr     x1, [x22, #NodeStream_handle]
    bl      node_out_handle
    mov     x0, x22
    bl      node_drop_stream
    LEAVE 0
40: cmp     x9, #LIBP2P_ACTION_STREAM_EOF
    b.ne    50f
    ldr     x0, [x21, #LIBP2P_ACT_STREAM]
    bl      node_find_stream
    cmn     x0, #1
    b.eq    49f
    mov     x9, #NODE_STREAM_EOF
    str     x9, [x1, #NodeStream_state]
    mov     x0, x1
    bl      node_request
49: LEAVE 0
50: cmp     x9, #LIBP2P_ACTION_STREAM_RESET
    b.ne    59f
    ldr     x0, [x21, #LIBP2P_ACT_STREAM]
    bl      node_find_stream
    cmn     x0, #1
    b.eq    59f
    mov     x0, x1
    bl      node_drop_stream
59: LEAVE 0
END_FUNCTION node_notice

/* L0: x0 = the WAKEUP time of the libp2p actions in the ByteList x0, after their application notices. x21 an action, x22 the end, x25 the time. */
LOCAL_FUNCTION node_p2p_notices
    ENTER 0
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
    bl      node_notice
3:  ldr     x9, [x21]
    add     x21, x21, x9
    b       1b
9:  mov     x0, x25
    LEAVE 0
END_FUNCTION node_p2p_notices

/* L0: the libp2p event list x0: the libp2p events of the P2P events from x1 to x2, then the node's queued events. */
LOCAL_FUNCTION node_p2p_fill
    ENTER 0
    mov     x25, x0
    mov     x21, x1
    mov     x22, x2
    mov     x9, #24
    str     x9, [x25, #8]
    add     x26, x25, #24
1:  cmp     x21, x22
    b.hs    2f
    ldr     x9, [x21, #8]
    cmp     x9, #NODE_EV_P2P
    b.ne    11f
    mov     x0, x26
    add     x1, x21, #16
    ldr     x2, [x21, #16]
    add     x26, x26, x2
    bl      lantern_copy
11: ldr     x9, [x21]
    add     x21, x21, x9
    b       1b
2:  mov     x0, x26
    ldp     x9, x2, [x19, #Node_p2p_out]
    add     x1, x19, x9
    add     x26, x26, x2
    bl      lantern_copy
    sub     x9, x26, x25
    sub     x9, x9, #24
    str     x9, [x25, #16]
    LEAVE 0
END_FUNCTION node_p2p_fill

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
    and     x11, x11, #~7
    MOVQ    x12, LIBP2P_ACTIONS_MIN + 24 + 16
    cmp     x11, x12
    b.lo    8f
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
    ENTER 0
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
    FORK_CALL node_block_root
    LEAVE 0
9:  mov     x0, #LANTERN_OK
    LEAVE 0
END_FUNCTION node_block_entry

/*
 * (node, store, p2p, tick, events, scratch, actions, result): x19 node, x20 store, x21 the
 * events, x22 their end, x23 scratch, x24 actions, x25 result, x26 the event count, x27 the
 * BLOCK and POW_BLOCK events, x28 the event bytes, then the root entries of the BLOCK events.
 * Locals: L the WORK_DONE events, L+8 the scratch size, L+16 p2p, L+24 tick, L+32 the end of
 * the events handled, L+40 the libp2p event list, L+48 the libp2p scratch, L+56 the bytes of
 * the P2P events, L+64 the P2P events, L+72 the action room kept for the node, L+80 wakeup,
 * L+88 libp2p's StepResult, L+96 libp2p's actions, L+104 the libp2p steps.
 */
FUNCTION lantern_node_step
    ENTER 112
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
    ldr     x14, [sp, #L]
    add     x14, x14, #1
    str     x14, [sp, #L]
    b       4f
21: cmp     x13, #NODE_EV_P2P               /* a libp2p event inside, for a node with a libp2p state */
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
    cmp     x13, #NODE_EV_BLOCK
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
    b.lo    8f
    subs    x11, x11, x10
    b.lo    8f
    cmp     x11, x12
    b.lo    8f
    ldr     x9, [x19, #Node_checkpoints]    /* blocks: one entry for each BLOCK event */
    ldr     x10, [x19, #Node_blocks]
    sub     x9, x9, x10
    mov     x10, #NodeBlock__mem
    udiv    x9, x9, x10
    ldr     x10, [x19, #(Node_blocks + 8)]
    sub     x9, x9, x10
    cmp     x9, x27
    b.lo    8f
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
    b.lo    8f
    ldr     x9, [x19, #Node_peers]          /* pow blocks: one for each POW_BLOCK event */
    ldr     x10, [x19, #Node_pow_blocks]
    sub     x9, x9, x10
    mov     x10, #POW_BLOCK_BYTES
    udiv    x9, x9, x10
    ldr     x10, [x19, #(Node_pow_blocks + 8)]
    sub     x9, x9, x10
    cmp     x9, x27
    b.lo    8f
    mov     x9, #NODE_ROOT_ENTRY            /* scratch: the root entries and libp2p's lists at its end */
    mul     x12, x27, x9
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 52f
    ldr     x9, [sp, #(L + 56)]
    add     x12, x12, x9
    ldr     x9, [x19]
    ldr     x10, [x19, #Node_p2p_out]
    sub     x9, x9, x10
    add     x12, x12, x9
    MOVQ    x9, 24 + LIBP2P_SCRATCH_SIZE
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
    ldr     x10, [x23]
    cmp     x10, x9
    b.lo    8f
    str     x10, [sp, #(L + 8)]
    sub     x10, x10, x12
    str     x10, [x23]
    add     x28, x23, x10
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 53f
    mov     x9, #NODE_ROOT_ENTRY
    madd    x9, x27, x9, x28                /* the libp2p event list, then libp2p's scratch */
    str     x9, [sp, #(L + 40)]
    ldr     x10, [sp, #(L + 56)]
    ldr     x11, [x19]
    ldr     x12, [x19, #Node_p2p_out]
    sub     x11, x11, x12
    add     x10, x10, x11
    add     x10, x10, #24
    str     x10, [x9]
    add     x9, x9, x10
    str     x9, [sp, #(L + 48)]
    MOVQ    x10, LIBP2P_SCRATCH_SIZE
    str     x10, [x9]
53: mov     x27, x21                        /* the root of each BLOCK event, before any change */
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
13: str     x22, [sp, #(L + 32)]            /* libp2p: the P2P events and the queued events */
    mov     x9, #-1
    str     x9, [sp, #(L + 80)]
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 30f
    ldr     x0, [sp, #(L + 40)]
    mov     x1, x21
    mov     x2, x22
    bl      node_p2p_fill
    ldp     x0, x1, [sp, #(L + 16)]
    ldr     x2, [sp, #(L + 40)]
    ldr     x3, [sp, #(L + 48)]
    ldr     x4, [sp, #(L + 72)]
    add     x5, sp, #(L + 88)
    bl      node_p2p_round
    cbz     x0, 24f
    cmp     x0, #LIBP2P_BUFFER_TOO_SMALL    /* a status of libp2p: nothing is changed */
    mov     x9, #LANTERN_BUFFER_TOO_SMALL
    mov     x10, #LANTERN_INVALID_EVENT
    csel    x0, x9, x10, eq
    b       14f
24: str     x1, [sp, #(L + 96)]             /* from here on the step holds */
    ldr     x9, [sp, #(L + 88)]
    ldr     x10, [sp, #(L + 64)]
    cmp     x9, x10
    b.hs    25f
    mov     x11, x21                        /* libp2p took k < n P2P events: the step ends at the next */
26: ldr     x12, [x11, #8]
    cmp     x12, #NODE_EV_P2P
    b.ne    27f
    cbz     x9, 28f
    sub     x9, x9, #1
27: ldr     x12, [x11]
    add     x11, x11, x12
    b       26b
28: str     x11, [sp, #(L + 32)]
    b       29f
25: sub     x0, x9, x10                     /* and the queued events it took */
    bl      node_out_consume
29: ldr     x0, [sp, #(L + 96)]
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
    ldr     x9, [sp, #(L + 16)]             /* libp2p again with the node's queued events */
    cbz     x9, 40f
    str     xzr, [sp, #(L + 104)]
32: ldr     x9, [x19, #(Node_p2p_out + 8)]
    cbz     x9, 40f
    ldr     x10, [sp, #(L + 104)]
    cmp     x10, #NODE_P2P_ROUNDS
    b.hs    40f
    add     x10, x10, #1
    str     x10, [sp, #(L + 104)]
    ldr     x0, [sp, #(L + 40)]
    mov     x1, x22
    mov     x2, x22
    bl      node_p2p_fill
    ldp     x0, x1, [sp, #(L + 16)]
    ldr     x2, [sp, #(L + 40)]
    ldr     x3, [sp, #(L + 48)]
    mov     x4, #4096
    add     x5, sp, #(L + 88)
    bl      node_p2p_round
    cbnz    x0, 40f
    str     x1, [sp, #(L + 96)]
    ldr     x0, [sp, #(L + 88)]
    bl      node_out_consume
    ldr     x0, [sp, #(L + 96)]
    bl      node_p2p_notices
    str     x0, [sp, #(L + 80)]
    b       32b
40: ldr     x9, [x19, #(Node_p2p_out + 8)]  /* events left: the next step is due now */
    cbz     x9, 41f
    ldr     x10, [sp, #(L + 24)]
    ldr     x10, [x10, #LIBP2P_TICK_NOW]
    str     x10, [sp, #(L + 80)]
41: ldr     x9, [sp, #(L + 8)]
    str     x9, [x23]
    ldr     x9, [sp, #(L + 80)]
    stp     x26, x9, [x25]
    mov     x0, #LANTERN_OK
    LEAVE 112
14: ldr     x9, [sp, #(L + 8)]              /* a status before any change */
    str     x9, [x23]
    LEAVE 112
7:  mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 112
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 112
END_FUNCTION lantern_node_step

/*
 * (node, store, seen, work, state_a, state_b, data, scratch, event): x19 node, x20 store,
 * x21 work, x22 state_a, x23 data, x24 scratch, x25 event. Locals: L the BlockOptions (32).
 */
FUNCTION lantern_node_run
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x3
    mov     x22, x4
    mov     x23, x6
    mov     x24, x7
    ldr     x25, [sp, #(96 + 32)]           /* the ninth argument */
    mov     x9, #NODE_EV_WORK_DONE_SIZE     /* the event: the work's fields, the result */
    mov     x10, #NODE_EV_WORK_DONE
    stp     x9, x10, [x25]
    .irp off, 16, 24, 32, 40, 48, 56
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
    mov     x9, #PAYLOAD_STATUS_VALID
    mov     x10, #PAYLOAD_STATUS_NOT_VALIDATED
    csel    x9, x10, x9, ne
    str     x9, [sp, #(L + BlockOptions_payload_status)]
    ldr     x0, [x21, #NodeAction_target]
    PART    x9, x10, x19, Node_blocks
    mov     x11, #0
    cmp     x0, x10
    b.hs    1f
    mov     x10, #NodeBlock__mem
    madd    x9, x0, x10, x9
    ldr     x11, [x9, #NodeBlock_data_available]
1:  str     x11, [sp, #(L + BlockOptions_data_available)]
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
    LEAVE 32
18: mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x25, #NodeEvent_result]
    mov     x0, #LANTERN_OK
    LEAVE 32
10: cmp     x9, #NODE_WORK_JUSTIFIED_STATE
    b.ne    20f
    ldr     x0, [x22, #NODE_STATE_SLOT]     /* JUSTIFIED_STATE: the fork of the state's slot */
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x20
    mov     x1, x22
    FORK_CALL store_justified_checkpoint_state
    LEAVE 32
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
    LEAVE 32
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
    LEAVE 32
40: cmp     x9, #NODE_WORK_ATTESTER_SLASHING
    b.ne    8f
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
99: LEAVE 32
8:  mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 32
END_FUNCTION lantern_node_run
