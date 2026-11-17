/*
 * The node core, RISC-V: in the common object. Requirements: docs/reference/node.md.
 * The SSZ bytes inside events start 8-aligned, so their u64 and root fields at 4 mod 8 are
 * read as words.
 */

.set NODE_ROOT_ENTRY, 40                # lantern_node_step: a flag, then the root of a BLOCK event

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

/* (room, size): NODE_FIXED + the room of each part. */
FUNCTION lantern_node_size
    UNWIND_END_PROLOGUE
    ld      t0, NodeRoom_blocks(a0)
    li      t1, NodeBlock__mem
    mulhu   t2, t0, t1
    bnez    t2, 9f
    mul     t3, t0, t1
    ld      t0, NodeRoom_checkpoints(a0)
    li      t1, NodeCheckpoint__mem
    mulhu   t2, t0, t1
    bnez    t2, 9f
    mul     t0, t0, t1
    add     t0, t3, t0
    bltu    t0, t3, 9f
    mv      t3, t0
    ld      t0, NodeRoom_pow_blocks(a0)
    li      t1, POW_BLOCK_BYTES
    mulhu   t2, t0, t1
    bnez    t2, 9f
    mul     t0, t0, t1
    add     t0, t3, t0
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

/* Lay out the parts of the node a0 for the room a1 at NODE_FIXED, with no entries. Uses t0-t2. */
LOCAL_FUNCTION node_layout
    UNWIND_END_PROLOGUE
    li      t0, NODE_FIXED
    sd      t0, Node_blocks(a0)
    sd      zero, (Node_blocks + 8)(a0)
    ld      t1, NodeRoom_blocks(a1)
    li      t2, NodeBlock__mem
    mul     t1, t1, t2
    add     t0, t0, t1
    sd      t0, Node_checkpoints(a0)
    sd      zero, (Node_checkpoints + 8)(a0)
    ld      t1, NodeRoom_checkpoints(a1)
    li      t2, NodeCheckpoint__mem
    mul     t1, t1, t2
    add     t0, t0, t1
    sd      t0, Node_pow_blocks(a0)
    sd      zero, (Node_pow_blocks + 8)(a0)
    ret
END_FUNCTION node_layout

/*
 * (room, config, anchor_root, anchor_slot, flags, node): a node whose one block is the anchor,
 * imported, with post-state id 1, and whose one checkpoint is (anchor epoch, anchor root) at
 * state id 1. s1 room, s2 config, s3 anchor root, s4 anchor slot, s5 flags, s6 node.
 * Locals: L the size.
 */
FUNCTION lantern_node_init
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    ld      s4, 0(a3)
    ld      s5, 0(a4)
    mv      s6, a5
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
    addi    t0, s6, Node_head_root
    COPY32  t0, s3
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

/* (node, room, out): the node in out, with the capacities of room. s1 node, s2 room, s3 out. Locals: L the size. */
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
    ld      t0, NodeRoom_blocks(s2)         # each capacity holds the entries
    ld      t1, (Node_blocks + 8)(s1)
    bltu    t0, t1, 8f
    ld      t0, NodeRoom_checkpoints(s2)
    ld      t1, (Node_checkpoints + 8)(s1)
    bltu    t0, t1, 8f
    ld      t0, NodeRoom_pow_blocks(s2)
    ld      t1, (Node_pow_blocks + 8)(s1)
    bltu    t0, t1, 8f
    addi    a0, s3, 8                       # the fixed fields
    addi    a1, s1, 8
    li      a2, NODE_FIXED - 8
    call    lantern_copy
    mv      a0, s3
    mv      a1, s2
    call    node_layout
    NODE_COPY_PART Node_blocks, NodeBlock__mem     # the entries of each part
    NODE_COPY_PART Node_checkpoints, NodeCheckpoint__mem
    NODE_COPY_PART Node_pow_blocks, POW_BLOCK_BYTES
    li      a0, LANTERN_OK
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

/* A WORK action: kind a0, state_a a1, state_b a2, data a3, target a4, arg a5. Uses t0-t2. */
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
    sd      a3, NodeAction_data(t2)
    sd      a4, NodeAction_target(t2)
    sd      a5, NodeAction_arg(t2)
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
    bne     t0, t2, 70f
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

/*
 * The root entry at a1 of the BLOCK event a0: its first u64 is 0 and the root follows, or the
 * first u64 is not 0 when the bytes are no SignedBeaconBlock. a0 = the status. s3 the ByteList,
 * s4 the entry.
 */
LOCAL_FUNCTION node_block_entry
    ENTER 0
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
    FORK_CALL node_block_root
    LEAVE 0
9:  li      a0, LANTERN_OK
    LEAVE 0
END_FUNCTION node_block_entry

/*
 * (node, store, events, scratch, actions, result): s1 node, s2 store, s3 the events, s4 their
 * end, s5 scratch, s6 actions, s7 result, s8 the event count, s9 the BLOCK and POW_BLOCK
 * events then an event, s10 the event bytes then a root entry at the end of scratch, t5 the
 * WORK_DONE events in the first pass. Locals: L the WORK_DONE events, L+8 the scratch size.
 */
FUNCTION lantern_node_step
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    ld      t0, 8(a2)
    ld      t1, 16(a2)
    add     s3, a2, t0
    add     s4, s3, t1
    mv      s5, a3
    mv      s6, a4
    mv      s7, a5
    li      s8, 0                           # first: check every event, and count
    li      s9, 0
    li      s10, 0
    li      t5, 0
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
    li      t6, NODE_EV_WORK_DONE
    bgeu    t4, t6, 7f
    li      t4, NODE_EV_TICK
    bne     t3, t4, 2f
    li      t4, 24
    bltu    t2, t4, 7f
    j       4f
2:  li      t4, NODE_EV_WORK_DONE
    bne     t3, t4, 3f
    li      t4, NODE_EV_WORK_DONE_SIZE
    bltu    t2, t4, 7f
    addi    t5, t5, 1
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
    ld      t0, 0(s6)                       # room: actions, node parts, scratch
    ld      t1, 8(s6)
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    ld      t1, 16(s6)
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    li      t1, 512
    mul     t1, s8, t1
    add     t1, t1, s10
    ld      t2, (Node_blocks + 8)(s1)
    li      t3, 128
    mul     t2, t2, t3
    add     t1, t1, t2
    addi    t1, t1, 512
    bltu    t0, t1, 8f
    ld      t0, Node_checkpoints(s1)        # blocks: one entry for each BLOCK event
    ld      t1, Node_blocks(s1)
    sub     t0, t0, t1
    li      t1, NodeBlock__mem
    divu    t0, t0, t1
    ld      t1, (Node_blocks + 8)(s1)
    sub     t0, t0, t1
    bltu    t0, s9, 8f
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
    ld      t0, 0(s1)                       # pow blocks: one for each POW_BLOCK event
    ld      t1, Node_pow_blocks(s1)
    sub     t0, t0, t1
    li      t1, POW_BLOCK_BYTES
    divu    t0, t0, t1
    ld      t1, (Node_pow_blocks + 8)(s1)
    sub     t0, t0, t1
    bltu    t0, s9, 8f
    LDQ     t0, s2, Store_validators        # scratch for get_head
    LDQ     t1, s2, Store_blocks
    sub     t0, t0, t1
    slli    t0, t0, 4
    li      t1, BlockNode__mem
    divu    t0, t0, t1
    li      t1, LANTERN_SCRATCH_FIXED + 64
    add     t0, t0, t1
    ld      t1, 0(s5)
    bltu    t1, t0, 8f
    ld      t0, 0(s5)                       # scratch: a root entry for each BLOCK event at its end
    sd      t0, (L + 8)(sp)
    li      t1, NODE_ROOT_ENTRY
    mul     t1, s9, t1
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    li      t1, LANTERN_SCRATCH_FIXED
    bltu    t0, t1, 8f
    sd      t0, 0(s5)
    add     s10, s5, t0
    mv      s9, s3                          # the root of each BLOCK event, before any change
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
13: ld      t0, 0(s5)
    add     s10, s5, t0
    mv      s9, s3                          # then each event, in order
6:  bgeu    s9, s4, 9f
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
9:  ld      t0, (L + 8)(sp)
    sd      t0, 0(s5)
    call    node_head
    sd      s8, 0(s7)
    li      a0, LANTERN_OK
    LEAVE 16
14: ld      t0, (L + 8)(sp)                 # a status of the first pass: nothing is changed
    sd      t0, 0(s5)
    LEAVE 16
7:  li      a0, LANTERN_INVALID_EVENT
    LEAVE 16
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION lantern_node_step

/*
 * (node, store, seen, work, state_a, state_b, data, scratch, event): s1 node, s2 store, s3 work,
 * s4 state_a, s5 data, s6 scratch, s7 event. Locals: L the BlockOptions (32).
 */
FUNCTION lantern_node_run
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a3
    mv      s4, a4
    mv      s5, a6
    mv      s6, a7
    ld      s7, (32 + 96)(sp)               # the ninth argument
    li      t0, NODE_EV_WORK_DONE_SIZE      # the event: the work's fields, the result
    sd      t0, 0(s7)
    li      t0, NODE_EV_WORK_DONE
    sd      t0, 8(s7)
    .irp off, 16, 24, 32, 40, 48, 56
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
    LEAVE 32
18: li      t0, LANTERN_INVALID_ENCODING
    sd      t0, NodeEvent_result(s7)
    li      a0, LANTERN_OK
    LEAVE 32
10: li      t1, NODE_WORK_JUSTIFIED_STATE
    bne     t0, t1, 20f
    ld      a0, NODE_STATE_SLOT(s4)         # JUSTIFIED_STATE: the fork of the state's slot
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s2
    mv      a1, s4
    FORK_CALL store_justified_checkpoint_state
    LEAVE 32
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
    LEAVE 32
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
    LEAVE 32
40: li      t1, NODE_WORK_ATTESTER_SLASHING
    bne     t0, t1, 8f
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
99: LEAVE 32
8:  li      a0, LANTERN_INVALID_EVENT
    LEAVE 32
END_FUNCTION lantern_node_run
