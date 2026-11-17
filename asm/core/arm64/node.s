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

/* (room, size): NODE_FIXED + the room of each part. */
FUNCTION lantern_node_size
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #NodeRoom_blocks]
    mov     x10, #NodeBlock__mem
    umulh   x11, x9, x10
    cbnz    x11, 9f
    mul     x9, x9, x10
    ldr     x12, [x0, #NodeRoom_checkpoints]
    mov     x10, #NodeCheckpoint__mem
    umulh   x11, x12, x10
    cbnz    x11, 9f
    mul     x12, x12, x10
    adds    x9, x9, x12
    b.cs    9f
    ldr     x12, [x0, #NodeRoom_pow_blocks]
    mov     x10, #POW_BLOCK_BYTES
    umulh   x11, x12, x10
    cbnz    x11, 9f
    mul     x12, x12, x10
    adds    x9, x9, x12
    b.cs    9f
    MOVQ    x10, NODE_FIXED
    adds    x9, x9, x10
    b.cs    9f
    str     x9, [x1]
    mov     x0, #LANTERN_OK
    ret
9:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_node_size

/* L0: lay out the parts of the node x0 for the room x1 at NODE_FIXED, with no entries. Uses x9-x12. */
LOCAL_FUNCTION node_layout
    UNWIND_END_PROLOGUE
    MOVQ    x9, NODE_FIXED
    str     x9, [x0, #Node_blocks]
    str     xzr, [x0, #(Node_blocks + 8)]
    ldr     x10, [x1, #NodeRoom_blocks]
    mov     x11, #NodeBlock__mem
    madd    x9, x10, x11, x9
    str     x9, [x0, #Node_checkpoints]
    str     xzr, [x0, #(Node_checkpoints + 8)]
    ldr     x10, [x1, #NodeRoom_checkpoints]
    mov     x11, #NodeCheckpoint__mem
    madd    x9, x10, x11, x9
    str     x9, [x0, #Node_pow_blocks]
    str     xzr, [x0, #(Node_pow_blocks + 8)]
    ret
END_FUNCTION node_layout

/*
 * (room, config, anchor_root, anchor_slot, flags, node): a node whose one block is the anchor,
 * imported, with post-state id 1, and whose one checkpoint is (anchor epoch, anchor root) at
 * state id 1. x19 room, x20 config, x21 anchor root, x22 anchor slot, x23 flags, x24 node.
 * Locals: L the size.
 */
FUNCTION lantern_node_init
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x22, [x3]
    ldr     x23, [x4]
    mov     x24, x5
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
    add     x9, x24, #Node_head_root
    COPY32  x9, x21
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

/* (node, room, out): the node in out, with the capacities of room. x19 node, x20 room, x21 out. Locals: L the size. */
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
    ldr     x9, [x20, #NodeRoom_blocks]     /* each capacity holds the entries */
    ldr     x10, [x19, #(Node_blocks + 8)]
    cmp     x9, x10
    b.lo    8f
    ldr     x9, [x20, #NodeRoom_checkpoints]
    ldr     x10, [x19, #(Node_checkpoints + 8)]
    cmp     x9, x10
    b.lo    8f
    ldr     x9, [x20, #NodeRoom_pow_blocks]
    ldr     x10, [x19, #(Node_pow_blocks + 8)]
    cmp     x9, x10
    b.lo    8f
    add     x0, x21, #8                     /* the fixed fields */
    add     x1, x19, #8
    MOVQ    x2, NODE_FIXED - 8
    bl      lantern_copy
    mov     x0, x21
    mov     x1, x20
    bl      node_layout
    PART    x1, x2, x19, Node_blocks        /* the entries of each part */
    str     x2, [x21, #(Node_blocks + 8)]
    mov     x9, #NodeBlock__mem
    mul     x2, x2, x9
    ldr     x9, [x21, #Node_blocks]
    add     x0, x21, x9
    bl      lantern_copy
    PART    x1, x2, x19, Node_checkpoints
    str     x2, [x21, #(Node_checkpoints + 8)]
    mov     x9, #NodeCheckpoint__mem
    mul     x2, x2, x9
    ldr     x9, [x21, #Node_checkpoints]
    add     x0, x21, x9
    bl      lantern_copy
    PART    x1, x2, x19, Node_pow_blocks
    str     x2, [x21, #(Node_pow_blocks + 8)]
    mov     x9, #POW_BLOCK_BYTES
    mul     x2, x2, x9
    ldr     x9, [x21, #Node_pow_blocks]
    add     x0, x21, x9
    bl      lantern_copy
    mov     x0, #LANTERN_OK
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
 * (node, store, events, scratch, actions, result): x19 node, x20 store, x21 the events, x22 their
 * end, x23 scratch, x24 actions, x25 result, x26 the event count, x27 the BLOCK and POW_BLOCK
 * events, x28 the event bytes, then the root entries of the BLOCK events at the end of scratch.
 * Locals: L the WORK_DONE events, L+8 the scratch size.
 */
FUNCTION lantern_node_step
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    ldp     x9, x10, [x2, #8]
    add     x21, x2, x9
    add     x22, x21, x10
    mov     x23, x3
    mov     x24, x4
    mov     x25, x5
    mov     x26, #0                         /* first: check every event, and count */
    mov     x27, #0
    mov     x28, #0
    str     xzr, [sp, #L]
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
    cmp     x14, #NODE_EV_WORK_DONE
    b.hs    7f
    cmp     x13, #NODE_EV_TICK
    b.ne    2f
    cmp     x12, #24
    b.lo    7f
    b       4f
2:  cmp     x13, #NODE_EV_WORK_DONE
    b.ne    3f
    cmp     x12, #NODE_EV_WORK_DONE_SIZE
    b.lo    7f
    ldr     x14, [sp, #L]
    add     x14, x14, #1
    str     x14, [sp, #L]
    b       4f
3:  cmp     x13, #NODE_EV_PAYLOAD_STATUS        /* the ByteList at 24: its bytes inside the event */
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
5:  ldp     x9, x10, [x24, #8]              /* room: actions, node parts, scratch */
    ldr     x11, [x24]
    subs    x11, x11, x9
    b.lo    8f
    subs    x11, x11, x10
    b.lo    8f
    mov     x12, #512
    madd    x12, x26, x12, x28
    ldr     x13, [x19, #(Node_blocks + 8)]
    mov     x14, #128
    madd    x12, x13, x14, x12
    add     x12, x12, #512
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
    ldr     x9, [x19]                       /* pow blocks: one for each POW_BLOCK event */
    ldr     x10, [x19, #Node_pow_blocks]
    sub     x9, x9, x10
    mov     x10, #POW_BLOCK_BYTES
    udiv    x9, x9, x10
    ldr     x10, [x19, #(Node_pow_blocks + 8)]
    sub     x9, x9, x10
    cmp     x9, x27
    b.lo    8f
    ldr     x9, [x20, #Store_validators]    /* scratch for get_head */
    ldr     x10, [x20, #Store_blocks]
    sub     x9, x9, x10
    lsl     x9, x9, #4
    mov     x10, #BlockNode__mem
    udiv    x9, x9, x10
    MOVQ    x10, LANTERN_SCRATCH_FIXED + 64
    add     x9, x9, x10
    ldr     x10, [x23]
    cmp     x10, x9
    b.lo    8f
    ldr     x9, [x23]                       /* scratch: a root entry for each BLOCK event at its end */
    str     x9, [sp, #(L + 8)]
    mov     x10, #NODE_ROOT_ENTRY
    mul     x10, x27, x10
    subs    x9, x9, x10
    b.lo    8f
    MOVQ    x10, LANTERN_SCRATCH_FIXED
    cmp     x9, x10
    b.lo    8f
    str     x9, [x23]
    add     x28, x23, x9
    mov     x27, x21                        /* the root of each BLOCK event, before any change */
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
13: ldr     x9, [x23]
    add     x28, x23, x9
    mov     x27, x21                        /* then each event, in order */
6:  cmp     x27, x22
    b.hs    9f
    mov     x0, x27
    bl      node_event
    ldr     x9, [x27, #8]
    cmp     x9, #NODE_EV_BLOCK
    b.ne    15f
    add     x28, x28, #NODE_ROOT_ENTRY
15: ldr     x9, [x27]
    add     x27, x27, x9
    b       6b
9:  ldr     x9, [sp, #(L + 8)]
    str     x9, [x23]
    bl      node_head
    str     x26, [x25]
    mov     x0, #LANTERN_OK
    LEAVE 16
14: ldr     x9, [sp, #(L + 8)]              /* a status of the first pass: nothing is changed */
    str     x9, [x23]
    LEAVE 16
7:  mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 16
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
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
