/*
 * The node core, x86-64: in the common object. Requirements: docs/reference/node.md.
 */

.set NODE_ROOT_ENTRY, 40                # lantern_node_step: a flag, then the root of a BLOCK event

/* Call lantern_<fork>_<name> for the fork in r10 (FORK_PHASE0 to FORK_FULU). */
.macro FORK_CALL name
    cmp     $FORK_ALTAIR, %r10
    jae     81f
    CALL_GLOBAL lantern_phase0_\name
    jmp     89f
81: cmp     $FORK_BELLATRIX, %r10
    jae     82f
    CALL_GLOBAL lantern_altair_\name
    jmp     89f
82: cmp     $FORK_CAPELLA, %r10
    jae     83f
    CALL_GLOBAL lantern_bellatrix_\name
    jmp     89f
83: cmp     $FORK_DENEB, %r10
    jae     84f
    CALL_GLOBAL lantern_capella_\name
    jmp     89f
84: cmp     $FORK_ELECTRA, %r10
    jae     85f
    CALL_GLOBAL lantern_deneb_\name
    jmp     89f
85: cmp     $FORK_FULU, %r10
    jae     86f
    CALL_GLOBAL lantern_electra_\name
    jmp     89f
86: CALL_GLOBAL lantern_fulu_\name
89:
.endm

/* rax = the fork of the slot rdi with the config rsi: the last fork whose epoch is at most the slot's. Uses rcx, rdx. */
LOCAL_FUNCTION node_fork
    UNWIND_END_PROLOGUE
    mov     %rdi, %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     $(16 * FORK_FULU), %ecx
1:  test    %rcx, %rcx
    jz      2f
    cmp     (%rsi,%rcx), %rax
    jae     2f
    sub     $16, %rcx
    jmp     1b
2:  shr     $4, %rcx
    mov     %rcx, %rax
    ret
END_FUNCTION node_fork

/* rax = the current slot of the store rdi: (time_ms - genesis_time_ms) // SLOT_DURATION_MS, 0 before genesis. Uses rcx, rdx. */
LOCAL_FUNCTION node_store_slot
    UNWIND_END_PROLOGUE
    mov     Store_time_ms(%rdi), %rax
    sub     Store_genesis_time_ms(%rdi), %rax
    jae     1f
    xor     %eax, %eax
1:  mov     (Store_config + CONFIG_SLOT_DURATION_MS)(%rdi), %rcx
    test    %rcx, %rcx
    jz      2f
    xor     %edx, %edx
    div     %rcx
    ret
2:  xor     %eax, %eax
    ret
END_FUNCTION node_store_slot

/* (room, size): NODE_FIXED + the room of each part. */
FUNCTION lantern_node_size
    UNWIND_END_PROLOGUE
    mov     NodeRoom_blocks(%rdi), %rax
    mov     $NodeBlock__mem, %ecx
    mul     %rcx
    jc      9f
    mov     %rax, %r8
    mov     NodeRoom_checkpoints(%rdi), %rax
    mov     $NodeCheckpoint__mem, %ecx
    mul     %rcx
    jc      9f
    add     %rax, %r8
    jc      9f
    mov     NodeRoom_pow_blocks(%rdi), %rax
    mov     $POW_BLOCK_BYTES, %ecx
    mul     %rcx
    jc      9f
    add     %rax, %r8
    jc      9f
    MOVQ    %rax, NODE_FIXED
    add     %rax, %r8
    jc      9f
    mov     %r8, (%rsi)
    xor     %eax, %eax
    ret
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
END_FUNCTION lantern_node_size

/* Lay out the parts of the node rdi for the room rsi at NODE_FIXED, with no entries. Uses rax, rcx. */
LOCAL_FUNCTION node_layout
    UNWIND_END_PROLOGUE
    MOVQ    %rax, NODE_FIXED
    mov     %rax, Node_blocks(%rdi)
    movq    $0, (Node_blocks + 8)(%rdi)
    imul    $NodeBlock__mem, NodeRoom_blocks(%rsi), %rcx
    add     %rcx, %rax
    mov     %rax, Node_checkpoints(%rdi)
    movq    $0, (Node_checkpoints + 8)(%rdi)
    imul    $NodeCheckpoint__mem, NodeRoom_checkpoints(%rsi), %rcx
    add     %rcx, %rax
    mov     %rax, Node_pow_blocks(%rdi)
    movq    $0, (Node_pow_blocks + 8)(%rdi)
    ret
END_FUNCTION node_layout

/*
 * (room, config, anchor_root, anchor_slot, flags, node): a node whose one block is the anchor,
 * imported, with post-state id 1, and whose one checkpoint is (anchor epoch, anchor root) at
 * state id 1. rbx room, rbp config, r12 anchor root, r13 anchor slot, r14 flags, r15 node.
 * Locals: L the size.
 */
FUNCTION lantern_node_init
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rcx), %r13
    mov     (%r8), %r14
    mov     %r9, %r15
    lea     L(%rsp), %rsi
    call    lantern_node_size
    test    %rax, %rax
    jnz     9f
    mov     L(%rsp), %rax
    cmp     %rax, (%r15)
    jb      8f
    cmpq    $0, NodeRoom_blocks(%rbx)       # room for the anchor
    je      8f
    cmpq    $0, NodeRoom_checkpoints(%rbx)
    je      8f
    lea     8(%r15), %rdi                   # the fixed fields: zero, then set
    MOVQ    %rsi, NODE_FIXED - 8
    call    lantern_zero
    movq    $2, Node_next_id(%r15)
    movq    $1, Node_anchor_state_id(%r15)
    mov     %r14, Node_flags(%r15)
    lea     Node_head_root(%r15), %rdi
    COPY32  %rdi, %r12
    lea     Node_config(%r15), %rdi
    mov     %rbp, %rsi
    MOVQ    %rdx, CONFIG_SIZE
    call    lantern_copy
    mov     %r15, %rdi
    mov     %rbx, %rsi
    call    node_layout
    PART    %rdi, %rax, %r15, Node_blocks   # the anchor block
    mov     $NodeBlock__mem, %esi
    call    lantern_zero
    PART    %rdi, %rax, %r15, Node_blocks
    COPY32  %rdi, %r12
    mov     %r13, NodeBlock_slot(%rdi)
    movq    $1, NodeBlock_state_id(%rdi)
    movq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdi)
    movq    $1, NodeBlock_data_available(%rdi)
    movq    $1, (Node_blocks + 8)(%r15)
    PART    %rdi, %rax, %r15, Node_checkpoints      # the anchor checkpoint
    mov     %r13, %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, NodeCheckpoint_epoch(%rdi)
    lea     NodeCheckpoint_root(%rdi), %rsi
    COPY32  %rsi, %r12
    movq    $1, NodeCheckpoint_state_id(%rdi)
    movq    $1, (Node_checkpoints + 8)(%r15)
    xor     %eax, %eax
9:  LEAVE 16
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION lantern_node_init

/* Copy the entries of the part at ref of the node rbx, of width bytes each, into the node r12. */
.macro NODE_COPY_PART ref, width
    PART    %rsi, %rdx, %rbx, \ref
    mov     %rdx, ((\ref) + 8)(%r12)
    imul    $(\width), %rdx, %rdx
    mov     (\ref)(%r12), %rdi
    add     %r12, %rdi
    call    lantern_copy
.endm

/* (node, room, out): the node in out, with the capacities of room. rbx node, rbp room, r12 out. Locals: L the size. */
FUNCTION lantern_node_copy
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rbp, %rdi
    lea     L(%rsp), %rsi
    call    lantern_node_size
    test    %rax, %rax
    jnz     9f
    mov     L(%rsp), %rax
    cmp     %rax, (%r12)
    jb      8f
    mov     NodeRoom_blocks(%rbp), %rax     # each capacity holds the entries
    cmp     (Node_blocks + 8)(%rbx), %rax
    jb      8f
    mov     NodeRoom_checkpoints(%rbp), %rax
    cmp     (Node_checkpoints + 8)(%rbx), %rax
    jb      8f
    mov     NodeRoom_pow_blocks(%rbp), %rax
    cmp     (Node_pow_blocks + 8)(%rbx), %rax
    jb      8f
    lea     8(%r12), %rdi                   # the fixed fields
    lea     8(%rbx), %rsi
    MOVQ    %rdx, NODE_FIXED - 8
    call    lantern_copy
    mov     %r12, %rdi
    mov     %rbp, %rsi
    call    node_layout
    NODE_COPY_PART Node_blocks, NodeBlock__mem      # the entries of each part
    NODE_COPY_PART Node_checkpoints, NodeCheckpoint__mem
    NODE_COPY_PART Node_pow_blocks, POW_BLOCK_BYTES
    xor     %eax, %eax
9:  LEAVE 16
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION lantern_node_copy

/*
 * The step's helpers read the node from rbx, the store from rbp, the scratch from r14 and the
 * actions from r15. An action is added at the end of the actions' bytes, whose room the step
 * checks first.
 */

/* rax = a new action of kind rdi and rsi bytes, its size and kind written. Uses rcx. */
LOCAL_FUNCTION node_act
    UNWIND_END_PROLOGUE
    mov     8(%r15), %rax
    add     %r15, %rax
    mov     16(%r15), %rcx
    add     %rcx, %rax
    add     %rsi, %rcx
    mov     %rcx, 16(%r15)
    mov     %rsi, (%rax)
    mov     %rdi, 8(%rax)
    ret
END_FUNCTION node_act

/* rax = a new BufferId. Uses rcx. */
LOCAL_FUNCTION node_new_id
    UNWIND_END_PROLOGUE
    mov     Node_next_id(%rbx), %rax
    lea     1(%rax), %rcx
    mov     %rcx, Node_next_id(%rbx)
    ret
END_FUNCTION node_new_id

/* rax = the index of the block whose root is at rdi, or 2^64 - 1; rdx = its entry. Uses rcx, r11, xmm0-xmm2. */
LOCAL_FUNCTION node_find_block
    UNWIND_END_PROLOGUE
    PART    %rdx, %rcx, %rbx, Node_blocks
    xor     %eax, %eax
1:  cmp     %rcx, %rax
    jae     3f
    NE32    %rdx, %rdi, 2f
    ret
2:  add     $NodeBlock__mem, %rdx
    inc     %rax
    jmp     1b
3:  mov     $-1, %rax
    ret
END_FUNCTION node_find_block

/* rax = the index of the checkpoint (epoch rdi, root at rsi), or 2^64 - 1; rdx = its entry. Uses rcx, r8, r11, xmm0-xmm2. */
LOCAL_FUNCTION node_find_checkpoint
    UNWIND_END_PROLOGUE
    PART    %rdx, %rcx, %rbx, Node_checkpoints
    xor     %eax, %eax
1:  cmp     %rcx, %rax
    jae     3f
    cmp     NodeCheckpoint_epoch(%rdx), %rdi
    jne     2f
    lea     NodeCheckpoint_root(%rdx), %r8
    NE32    %r8, %rsi, 2f
    ret
2:  add     $NodeCheckpoint__mem, %rdx
    inc     %rax
    jmp     1b
3:  mov     $-1, %rax
    ret
END_FUNCTION node_find_checkpoint

/* A WORK action: kind rdi, state_a rsi, state_b rdx, data rcx, target r8, arg r9. Uses rax, r10. */
LOCAL_FUNCTION node_work
    UNWIND_END_PROLOGUE
    mov     8(%r15), %rax
    add     %r15, %rax
    mov     16(%r15), %r10
    add     %r10, %rax
    add     $NODE_ACT_WORK_SIZE, %r10
    mov     %r10, 16(%r15)
    movq    $NODE_ACT_WORK_SIZE, (%rax)
    movq    $NODE_ACT_WORK, 8(%rax)
    mov     %rdi, NodeAction_work_kind(%rax)
    mov     %rsi, NodeAction_state_a(%rax)
    mov     %rdx, NodeAction_state_b(%rax)
    mov     %rcx, NodeAction_data(%rax)
    mov     %r8, NodeAction_target(%rax)
    mov     %r9, NodeAction_arg(%rax)
    ret
END_FUNCTION node_work

/* An action of kind rdi with the two ids rsi and rdx (STATE_COPY: source, new; the FREE kinds: rsi). Uses rax, r10. */
LOCAL_FUNCTION node_ids
    UNWIND_END_PROLOGUE
    mov     8(%r15), %rax
    add     %r15, %rax
    mov     16(%r15), %r10
    add     %r10, %rax
    add     $32, %r10
    mov     %r10, 16(%r15)
    movq    $32, (%rax)
    mov     %rdi, 8(%rax)
    mov     %rsi, 16(%rax)
    mov     %rdx, 24(%rax)
    ret
END_FUNCTION node_ids

/*
 * rax = the state id of the checkpoint state of (epoch rdi, root at rsi), or 0 when the root's
 * block has no post-state: a new checkpoint is a copy of that post-state and a TARGET_STATE work.
 * r12 epoch, r13 root, S7 the new id, S8 the block's state id.
 */
LOCAL_FUNCTION node_checkpoint_state
    ENTER 0
    mov     %rdi, %r12
    mov     %rsi, %r13
    call    node_find_checkpoint
    cmp     $-1, %rax
    je      1f
    mov     NodeCheckpoint_state_id(%rdx), %rax
    LEAVE 0
1:  mov     %r13, %rdi                      # the root's block, imported
    call    node_find_block
    cmp     $-1, %rax
    je      9f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     9f
    mov     NodeBlock_state_id(%rdx), %rax
    mov     %rax, S8(%rsp)
    call    node_new_id
    mov     %rax, S7(%rsp)
    mov     $NODE_ACT_STATE_COPY, %edi
    mov     S8(%rsp), %rsi
    mov     %rax, %rdx
    call    node_ids
    PART    %rdi, %rcx, %rbx, Node_checkpoints      # the entry
    imul    $NodeCheckpoint__mem, %rcx, %rax
    add     %rax, %rdi
    mov     %r12, NodeCheckpoint_epoch(%rdi)
    lea     NodeCheckpoint_root(%rdi), %rax
    COPY32  %rax, %r13
    mov     S7(%rsp), %rax
    mov     %rax, NodeCheckpoint_state_id(%rdi)
    lea     1(%rcx), %rax
    mov     %rax, (Node_checkpoints + 8)(%rbx)
    mov     %rcx, %r8
    mov     $NODE_WORK_TARGET_STATE, %edi
    mov     S7(%rsp), %rsi
    xor     %edx, %edx
    xor     %ecx, %ecx
    mov     %r12, %r9
    call    node_work
    mov     S7(%rsp), %rax
    LEAVE 0
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION node_checkpoint_state

/* A JUSTIFIED_STATE work for store.justified_checkpoint, unless one is queued. */
LOCAL_FUNCTION node_justified
    ENTER 0
    testq   $NODE_FLAG_JUSTIFIED_PENDING, Node_flags(%rbx)
    jnz     9f
    mov     Store_justified_checkpoint(%rbp), %rdi      # a Checkpoint: the epoch, then the root at 8
    lea     (Store_justified_checkpoint + 8)(%rbp), %rsi
    call    node_checkpoint_state
    test    %rax, %rax
    jz      9f
    mov     %rax, %rsi
    mov     $NODE_WORK_JUSTIFIED_STATE, %edi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    call    node_work
    orq     $NODE_FLAG_JUSTIFIED_PENDING, Node_flags(%rbx)
9:  LEAVE 0
END_FUNCTION node_justified

/*
 * The import of the block of index rdi when its parent has a post-state: a copy of it and an
 * IMPORT_BLOCK work; a block whose parent is invalid becomes invalid. r12 index, r13 entry,
 * S7 the parent's state id.
 */
LOCAL_FUNCTION node_try_import
    ENTER 0
    mov     %rdi, %r12
    PART    %r13, %rax, %rbx, Node_blocks
    imul    $NodeBlock__mem, %r12, %rax
    add     %rax, %r13
    lea     NodeBlock_parent_root(%r13), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      9f
    mov     NodeBlock_status(%rdx), %rax
    cmp     $NODE_BLOCK_INVALID, %rax
    je      8f
    cmp     $NODE_BLOCK_IMPORTED, %rax
    jne     9f
    mov     NodeBlock_state_id(%rdx), %rax
    mov     %rax, S7(%rsp)
    call    node_new_id
    mov     %rax, NodeBlock_state_id(%r13)
    mov     %rax, %rdx
    mov     $NODE_ACT_STATE_COPY, %edi
    mov     S7(%rsp), %rsi
    call    node_ids
    movq    $NODE_BLOCK_IMPORTING, NodeBlock_status(%r13)
    mov     $NODE_WORK_IMPORT_BLOCK, %edi
    mov     NodeBlock_state_id(%r13), %rsi
    xor     %edx, %edx
    mov     NodeBlock_data_id(%r13), %rcx
    mov     %r12, %r8
    xor     %r9d, %r9d
    call    node_work
    LEAVE 0
8:  movq    $NODE_BLOCK_INVALID, NodeBlock_status(%r13)
9:  LEAVE 0
END_FUNCTION node_try_import

/* The import of each waiting block whose parent is the block of the entry rdi. r12 the root, r13 index. */
LOCAL_FUNCTION node_children
    ENTER 0
    mov     %rdi, %r12
    xor     %r13d, %r13d
1:  cmp     (Node_blocks + 8)(%rbx), %r13
    jae     9f
    PART    %rdi, %rax, %rbx, Node_blocks
    imul    $NodeBlock__mem, %r13, %rax
    add     %rax, %rdi
    cmpq    $NODE_BLOCK_WAITING, NodeBlock_status(%rdi)
    jne     2f
    lea     NodeBlock_parent_root(%rdi), %rax
    NE32    %rax, %r12, 2f
    mov     %r13, %rdi
    call    node_try_import
2:  inc     %r13
    jmp     1b
9:  LEAVE 0
END_FUNCTION node_children

/* A BYTES_PUT action of the ByteList rdi with a new id: rax = the id. r12 the ByteList, r13 the id. */
LOCAL_FUNCTION node_put
    ENTER 0
    mov     %rdi, %r12
    call    node_new_id
    mov     %rax, %r13
    mov     16(%r12), %rsi                  # the header, 16 id, then a ByteList: size, offset 24, count, bytes
    add     $(48 + 7), %rsi
    and     $-8, %rsi
    mov     $NODE_ACT_BYTES_PUT, %edi
    call    node_act
    mov     %r13, 16(%rax)
    mov     (%rax), %rcx
    sub     $24, %rcx
    mov     %rcx, 24(%rax)
    movq    $24, 32(%rax)
    mov     16(%r12), %rdx
    mov     %rdx, 40(%rax)
    lea     48(%rax), %rdi
    mov     8(%r12), %rsi
    add     %r12, %rsi
    call    lantern_copy
    mov     %r13, %rax
    LEAVE 0
END_FUNCTION node_put

/* The head: the root of get_head of the fork of the store's slot into the node, or a JUSTIFIED_STATE work. Locals: L the node. */
LOCAL_FUNCTION node_head
    ENTER 16
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %rbp, %rdi
    mov     %r14, %rsi
    lea     L(%rsp), %rdx
    FORK_CALL get_head
    cmp     $LANTERN_NEED_JUSTIFIED_STATE, %rax
    jne     1f
    call    node_justified
    LEAVE 16
1:  test    %rax, %rax
    jnz     9f
    mov     L(%rsp), %rax
    PART    %rcx, %rdx, %rbp, Store_blocks
    cmp     %rdx, %rax
    jae     9f
    imul    $BlockNode__mem, %rax, %rax
    add     %rax, %rcx
    lea     Node_head_root(%rbx), %rdi
    COPY32  %rdi, %rcx
9:  LEAVE 16
END_FUNCTION node_head

/*
 * The event rdi. r12 the event, r13 its ByteList, S7 its bytes, S8 a BufferId, S9 the root entry
 * rsi of the step's first pass for a BLOCK event. Locals: L+32 a result, L+40 the index.
 */
LOCAL_FUNCTION node_event
    ENTER 48
    mov     %rdi, %r12
    mov     %rsi, S9(%rsp)
    mov     8(%r12), %rax
    cmp     $NODE_EV_TICK, %rax
    jne     10f
    mov     16(%r12), %rax                  # TICK: on_tick of the fork of the new slot
    mov     %rax, Node_time_ms(%rbx)
    sub     Store_genesis_time_ms(%rbp), %rax
    jae     1f
    xor     %eax, %eax
1:  mov     (Store_config + CONFIG_SLOT_DURATION_MS)(%rbp), %rcx
    test    %rcx, %rcx
    jz      2f
    xor     %edx, %edx
    div     %rcx
    jmp     3f
2:  xor     %eax, %eax
3:  mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %rbp, %rdi
    lea     16(%r12), %rsi
    lea     (L + 32)(%rsp), %rdx
    FORK_CALL on_tick
    LEAVE 48
10: cmp     $NODE_EV_BLOCK, %rax
    jne     20f
    mov     S9(%rsp), %rdi                  # BLOCK: its root entry from the step's first pass
    cmpq    $0, (%rdi)
    jne     19f
    add     $8, %rdi                        # a known block: nothing
    call    node_find_block
    cmp     $-1, %rax
    jne     19f
    lea     NodeEvent_bytes(%r12), %r13     # its bytes, then its entry
    mov     8(%r13), %rax
    add     %r13, %rax
    mov     %rax, S7(%rsp)
    mov     %r13, %rdi
    call    node_put
    mov     %rax, S8(%rsp)
    PART    %rdi, %rcx, %rbx, Node_blocks
    mov     %rcx, (L + 40)(%rsp)
    imul    $NodeBlock__mem, %rcx, %rax
    add     %rax, %rdi
    mov     S9(%rsp), %rsi
    add     $8, %rsi
    COPY32  %rdi, %rsi
    mov     S7(%rsp), %rsi
    lea     116(%rsi), %rax                 # the message's parent_root
    lea     NodeBlock_parent_root(%rdi), %rdx
    COPY32  %rdx, %rax
    mov     100(%rsi), %rax                 # the message's slot
    mov     %rax, NodeBlock_slot(%rdi)
    mov     S8(%rsp), %rax
    mov     %rax, NodeBlock_data_id(%rdi)
    movq    $0, NodeBlock_state_id(%rdi)
    movq    $NODE_BLOCK_WAITING, NodeBlock_status(%rdi)
    mov     16(%r12), %rax
    mov     %rax, NodeBlock_data_available(%rdi)
    movq    $0, NodeBlock_result(%rdi)
    inc     %rcx
    mov     %rcx, (Node_blocks + 8)(%rbx)
    mov     (L + 40)(%rsp), %rdi
    call    node_try_import
19: LEAVE 48
20: cmp     $NODE_EV_ATTESTATION, %rax
    jne     30f
    lea     NodeEvent_bytes(%r12), %r13     # ATTESTATION: its target checkpoint state, if made
    cmpq    $(4 + 128 + 96), 16(%r13)
    jb      29f
    mov     %r13, %rdi
    call    node_put
    mov     %rax, S8(%rsp)
    mov     8(%r13), %rsi
    add     %r13, %rsi
    mov     92(%rsi), %rdi                  # data.target: the epoch, then the root
    add     $100, %rsi
    call    node_find_checkpoint
    xor     %esi, %esi
    cmp     $-1, %rax
    je      21f
    mov     NodeCheckpoint_state_id(%rdx), %rsi
21: mov     $NODE_WORK_ATTESTATION, %edi
    xor     %edx, %edx
    mov     S8(%rsp), %rcx
    xor     %r8d, %r8d
    mov     16(%r12), %r9                   # is_from_block
    call    node_work
29: LEAVE 48
30: cmp     $NODE_EV_ATTESTER_SLASHING, %rax
    jne     40f
    lea     (Store_justified_checkpoint + 8)(%rbp), %rdi    # the justified root's post-state
    call    node_find_block
    cmp     $-1, %rax
    je      39f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     39f
    mov     NodeBlock_state_id(%rdx), %rax
    mov     %rax, S7(%rsp)
    lea     NodeEvent_bytes(%r12), %rdi
    call    node_put
    mov     %rax, %rcx
    mov     $NODE_WORK_ATTESTER_SLASHING, %edi
    mov     S7(%rsp), %rsi
    xor     %edx, %edx
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    call    node_work
39: LEAVE 48
40: cmp     $NODE_EV_POW_BLOCK, %rax
    jne     50f
    lea     NodeEvent_bytes(%r12), %r13     # POW_BLOCK: a PowBlock of the node
    cmpq    $POW_BLOCK_BYTES, 16(%r13)
    jne     49f
    PART    %rdi, %rcx, %rbx, Node_pow_blocks
    imul    $POW_BLOCK_BYTES, %rcx, %rax
    add     %rax, %rdi
    inc     %rcx
    mov     %rcx, (Node_pow_blocks + 8)(%rbx)
    mov     8(%r13), %rsi
    add     %r13, %rsi
    mov     $POW_BLOCK_BYTES, %edx
    call    lantern_copy
49: LEAVE 48
50: mov     NodeAction_work_kind(%r12), %rax        # WORK_DONE
    mov     NodeEvent_result(%r12), %rcx
    cmp     $NODE_WORK_IMPORT_BLOCK, %rax
    jne     60f
    mov     NodeAction_target(%r12), %rdi
    PART    %r13, %rdx, %rbx, Node_blocks
    cmp     %rdx, %rdi
    jae     59f
    imul    $NodeBlock__mem, %rdi, %rax
    add     %rax, %r13
    mov     %rcx, NodeBlock_result(%r13)
    cmp     $LANTERN_NEED_JUSTIFIED_STATE, %rcx
    jne     51f
    call    node_justified                  # the justified state, then the same import again
    mov     NodeAction_work_kind(%r12), %rdi
    mov     NodeAction_state_a(%r12), %rsi
    mov     NodeAction_state_b(%r12), %rdx
    mov     NodeAction_data(%r12), %rcx
    mov     NodeAction_target(%r12), %r8
    mov     NodeAction_arg(%r12), %r9
    call    node_work
    LEAVE 48
51: test    %rcx, %rcx
    jnz     52f
    movq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%r13)    # imported: then its waiting children
    mov     %r13, %rdi
    call    node_children
    LEAVE 48
52: movq    $NODE_BLOCK_INVALID, NodeBlock_status(%r13)     # invalid: its state copy is freed
    mov     $NODE_ACT_STATE_FREE, %edi
    mov     NodeBlock_state_id(%r13), %rsi
    xor     %edx, %edx
    call    node_ids
    movq    $0, NodeBlock_state_id(%r13)
59: LEAVE 48
60: cmp     $NODE_WORK_JUSTIFIED_STATE, %rax
    jne     61f
    andq    $~NODE_FLAG_JUSTIFIED_PENDING, Node_flags(%rbx)
    LEAVE 48
61: cmp     $NODE_WORK_ATTESTATION, %rax
    jne     70f
    cmp     $LANTERN_NEED_TARGET_STATE, %rcx
    jne     70f
    mov     NodeEvent_checkpoint(%r12), %rdi        # the target state, then the same attestation again
    lea     (NodeEvent_checkpoint + 8)(%r12), %rsi
    call    node_checkpoint_state
    test    %rax, %rax
    jz      71f
    mov     %rax, %rsi
    mov     $NODE_WORK_ATTESTATION, %edi
    mov     NodeAction_state_b(%r12), %rdx
    mov     NodeAction_data(%r12), %rcx
    mov     NodeAction_target(%r12), %r8
    mov     NodeAction_arg(%r12), %r9
    call    node_work
    LEAVE 48
70: cmp     $NODE_WORK_ATTESTATION, %rax    # done with an attestation or a slashing: free its bytes
    je      71f
    cmp     $NODE_WORK_ATTESTER_SLASHING, %rax
    jne     79f
71: mov     $NODE_ACT_BYTES_FREE, %edi
    mov     NodeAction_data(%r12), %rsi
    xor     %edx, %edx
    call    node_ids
79: LEAVE 48
END_FUNCTION node_event

/*
 * The root entry at rsi of the BLOCK event rdi: its first u64 is 0 and the root follows, or the
 * first u64 is not 0 when the bytes are no SignedBeaconBlock. rax = the status. r12 the ByteList,
 * r13 the entry.
 */
LOCAL_FUNCTION node_block_entry
    ENTER 0
    lea     NodeEvent_bytes(%rdi), %r12
    mov     %rsi, %r13
    movq    $1, (%r13)
    cmpq    $(100 + 84), 16(%r12)
    jb      9f
    mov     8(%r12), %rax
    add     %r12, %rax
    mov     100(%rax), %rdi                 # the slot of the message
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r12, %rdi
    mov     %r14, %rsi
    lea     8(%r13), %rdx
    mov     %r13, %rcx
    FORK_CALL node_block_root
    LEAVE 0
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION node_block_entry

/*
 * (node, store, events, scratch, actions, result): rbx node, rbp store, r12 the events, r13 their
 * end, r14 scratch, r15 actions, S7 result, S8 the event count, S9 an event, S10 a root entry
 * at the end of scratch. The first pass counts in r8 the events, r9 the BLOCK and POW_BLOCK
 * events, r10 the event bytes, r11 the WORK_DONE events. Locals: L the WORK_DONE events, L+8
 * the scratch size.
 */
FUNCTION lantern_node_step
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     8(%rdx), %r12
    add     %rdx, %r12
    mov     16(%rdx), %r13
    add     %r12, %r13
    mov     %rcx, %r14
    mov     %r8, %r15
    mov     %r9, S7(%rsp)
    xor     %r8d, %r8d                      # first: check every event, and count
    xor     %r9d, %r9d
    xor     %r10d, %r10d
    xor     %r11d, %r11d
    mov     %r12, %rdi
1:  cmp     %r13, %rdi
    jae     5f
    mov     %r13, %rax
    sub     %rdi, %rax
    cmp     $16, %rax
    jb      7f
    mov     (%rdi), %rcx                    # size, kind
    mov     8(%rdi), %rdx
    cmp     $16, %rcx
    jb      7f
    test    $7, %cl
    jnz     7f
    cmp     %rax, %rcx
    ja      7f
    lea     -1(%rdx), %rsi
    cmp     $NODE_EV_WORK_DONE, %rsi
    jae     7f
    cmp     $NODE_EV_TICK, %rdx
    jne     2f
    cmp     $24, %rcx
    jb      7f
    jmp     4f
2:  cmp     $NODE_EV_WORK_DONE, %rdx
    jne     3f
    cmp     $NODE_EV_WORK_DONE_SIZE, %rcx
    jb      7f
    inc     %r11
    jmp     4f
3:  cmp     $NODE_EV_PAYLOAD_STATUS, %rdx   # the ByteList at 24: its bytes inside the event
    je      7f
    cmp     $(24 + 24), %rcx
    jb      7f
    cmpq    $24, (24 + 8)(%rdi)
    jne     7f
    lea     -(24 + 24)(%rcx), %rsi
    cmp     %rsi, (24 + 16)(%rdi)
    ja      7f
    cmp     $NODE_EV_BLOCK, %rdx
    je      31f
    cmp     $NODE_EV_POW_BLOCK, %rdx
    jne     4f
31: inc     %r9
4:  inc     %r8
    add     %rcx, %r10
    add     %rcx, %rdi
    jmp     1b
5:  mov     %r8, S8(%rsp)
    mov     %r11, L(%rsp)
    mov     (%r15), %rax                    # room: actions, node parts, scratch
    sub     8(%r15), %rax
    jb      8f
    sub     16(%r15), %rax
    jb      8f
    imul    $512, %r8, %rcx
    add     %r10, %rcx
    imul    $128, (Node_blocks + 8)(%rbx), %rdx
    add     %rdx, %rcx
    add     $512, %rcx
    cmp     %rcx, %rax
    jb      8f
    mov     Node_checkpoints(%rbx), %rax    # blocks: one entry for each BLOCK event
    sub     Node_blocks(%rbx), %rax
    xor     %edx, %edx
    mov     $NodeBlock__mem, %ecx
    div     %rcx
    sub     (Node_blocks + 8)(%rbx), %rax
    cmp     %r9, %rax
    jb      8f
    mov     Node_pow_blocks(%rbx), %rax     # checkpoints: two for each WORK_DONE event, and two
    sub     Node_checkpoints(%rbx), %rax
    xor     %edx, %edx
    mov     $NodeCheckpoint__mem, %ecx
    div     %rcx
    sub     (Node_checkpoints + 8)(%rbx), %rax
    lea     2(%r11,%r11), %rcx
    cmp     %rcx, %rax
    jb      8f
    mov     (%rbx), %rax                    # pow blocks: one for each POW_BLOCK event
    sub     Node_pow_blocks(%rbx), %rax
    xor     %edx, %edx
    mov     $POW_BLOCK_BYTES, %ecx
    div     %rcx
    sub     (Node_pow_blocks + 8)(%rbx), %rax
    cmp     %r9, %rax
    jb      8f
    mov     Store_validators(%rbp), %rax    # scratch for get_head
    sub     Store_blocks(%rbp), %rax
    shl     $4, %rax
    xor     %edx, %edx
    mov     $BlockNode__mem, %ecx
    div     %rcx
    MOVQ    %rcx, LANTERN_SCRATCH_FIXED + 64
    add     %rcx, %rax
    cmp     %rax, (%r14)
    jb      8f
    mov     (%r14), %rax                    # scratch: a root entry for each BLOCK event at its end
    mov     %rax, (L + 8)(%rsp)
    imul    $NODE_ROOT_ENTRY, %r9, %rcx
    sub     %rcx, %rax
    jb      8f
    MOVQ    %rcx, LANTERN_SCRATCH_FIXED
    cmp     %rcx, %rax
    jb      8f
    mov     %rax, (%r14)
    add     %r14, %rax
    mov     %rax, S10(%rsp)
    mov     %r12, S9(%rsp)                  # the root of each BLOCK event, before any change
11: mov     S9(%rsp), %rdi
    cmp     %r13, %rdi
    jae     13f
    cmpq    $NODE_EV_BLOCK, 8(%rdi)
    jne     12f
    mov     S10(%rsp), %rsi
    call    node_block_entry
    test    %rax, %rax
    jnz     14f
    addq    $NODE_ROOT_ENTRY, S10(%rsp)
12: mov     S9(%rsp), %rdi
    add     (%rdi), %rdi
    mov     %rdi, S9(%rsp)
    jmp     11b
13: mov     (%r14), %rax
    add     %r14, %rax
    mov     %rax, S10(%rsp)
    mov     %r12, S9(%rsp)                  # then each event, in order
6:  mov     S9(%rsp), %rdi
    cmp     %r13, %rdi
    jae     9f
    mov     S10(%rsp), %rsi
    call    node_event
    mov     S9(%rsp), %rdi
    cmpq    $NODE_EV_BLOCK, 8(%rdi)
    jne     15f
    addq    $NODE_ROOT_ENTRY, S10(%rsp)
15: add     (%rdi), %rdi
    mov     %rdi, S9(%rsp)
    jmp     6b
9:  mov     (L + 8)(%rsp), %rax
    mov     %rax, (%r14)
    call    node_head
    mov     S7(%rsp), %rdi
    mov     S8(%rsp), %rax
    mov     %rax, (%rdi)
    xor     %eax, %eax
    LEAVE 16
14: mov     (L + 8)(%rsp), %rcx             # a status of the first pass: nothing is changed
    mov     %rcx, (%r14)
    LEAVE 16
7:  mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 16
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION lantern_node_step

/*
 * (node, store, seen, work, state_a, state_b, data, scratch, event): rbx node, rbp store, r12 work,
 * r13 state_a, r14 data, r15 scratch, S7 the seventh argument of a call, S8 event. Locals: L the
 * BlockOptions (32).
 */
FUNCTION lantern_node_run
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     (32 + 96)(%rsp), %r14           # the seventh to ninth arguments
    mov     (32 + 96 + 8)(%rsp), %r15
    mov     (32 + 96 + 16)(%rsp), %rax
    mov     %rax, S8(%rsp)
    movq    $NODE_EV_WORK_DONE_SIZE, (%rax) # the event: the work's fields, the result
    movq    $NODE_EV_WORK_DONE, 8(%rax)
    .irp off, 16, 24, 32, 40, 48, 56
    mov     \off(%r12), %rcx
    mov     %rcx, \off(%rax)
    .endr
    lea     NodeEvent_result(%rax), %rdi
    mov     $(NODE_EV_WORK_DONE_SIZE - NodeEvent_result), %esi
    call    lantern_zero
    mov     NodeAction_work_kind(%r12), %rax
    cmp     $NODE_WORK_IMPORT_BLOCK, %rax
    jne     10f
    mov     $PAYLOAD_STATUS_VALID, %eax     # IMPORT_BLOCK: the options, then the fork's on_block
    mov     $PAYLOAD_STATUS_NOT_VALIDATED, %ecx
    testq   $NODE_FLAG_OPTIMISTIC, Node_flags(%rbx)
    cmovnz  %rcx, %rax
    mov     %rax, (L + BlockOptions_payload_status)(%rsp)
    mov     NodeAction_target(%r12), %rdi
    PART    %rsi, %rdx, %rbx, Node_blocks
    xor     %eax, %eax
    cmp     %rdx, %rdi
    jae     1f
    imul    $NodeBlock__mem, %rdi, %rdi
    mov     NodeBlock_data_available(%rsi,%rdi), %rax
1:  mov     %rax, (L + BlockOptions_data_available)(%rsp)
    movq    $0, (L + BlockOptions_pow_block)(%rsp)
    movq    $0, (L + BlockOptions_pow_parent)(%rsp)
    cmpq    $(100 + 84), 16(%r14)
    jb      18f
    mov     8(%r14), %rax
    add     %r14, %rax
    mov     100(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %rbp, %rdi
    mov     %rbx, %rsi
    mov     %r14, %rdx
    mov     %r13, %rcx
    lea     L(%rsp), %r8
    mov     %r15, %r9
    mov     S8(%rsp), %rax
    add     $NodeEvent_result, %rax
    mov     %rax, S7(%rsp)                  # result, the seventh argument
    FORK_CALL node_import
    cmp     $LANTERN_NEED_JUSTIFIED_STATE, %rax
    jne     99f
    mov     S8(%rsp), %rcx
    mov     %rax, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 32
18: mov     S8(%rsp), %rcx
    movq    $LANTERN_INVALID_ENCODING, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 32
10: cmp     $NODE_WORK_JUSTIFIED_STATE, %rax
    jne     20f
    mov     NODE_STATE_SLOT(%r13), %rdi     # JUSTIFIED_STATE: the fork of the state's slot
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %rbp, %rdi
    mov     %r13, %rsi
    FORK_CALL store_justified_checkpoint_state
    LEAVE 32
20: cmp     $NODE_WORK_TARGET_STATE, %rax
    jne     30f
    mov     NODE_STATE_SLOT(%r13), %rdi     # TARGET_STATE: store_target_checkpoint_state of the checkpoint
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     NodeAction_target(%r12), %rax
    PART    %rsi, %rcx, %rbx, Node_checkpoints
    cmp     %rcx, %rax
    jae     8f
    imul    $NodeCheckpoint__mem, %rax, %rax
    add     %rax, %rsi
    mov     %r13, %rdi
    lea     Node_config(%rbx), %rdx
    mov     %r15, %rcx
    mov     S8(%rsp), %r8
    add     $NodeEvent_result, %r8
    FORK_CALL store_target_checkpoint_state
    LEAVE 32
30: cmp     $NODE_WORK_ATTESTATION, %rax
    jne     40f
    cmpq    $(4 + 128 + 96), 16(%r14)       # ATTESTATION: the fork of its slot
    jb      18b
    mov     8(%r14), %rax
    add     %r14, %rax
    mov     4(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %rbp, %rdi
    mov     %r14, %rsi
    lea     NodeAction_arg(%r12), %rdx
    mov     %r13, %rcx
    mov     %r15, %r8
    mov     S8(%rsp), %r9
    lea     NodeEvent_checkpoint(%r9), %rax
    mov     %rax, S7(%rsp)                  # target, the seventh argument
    add     $NodeEvent_result, %r9
    FORK_CALL node_attestation
    LEAVE 32
40: cmp     $NODE_WORK_ATTESTER_SLASHING, %rax
    jne     8f
    mov     %rbp, %rdi                      # ATTESTER_SLASHING: the fork of the store's slot
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %rbp, %rdi
    mov     %r14, %rsi
    mov     %r13, %rdx
    mov     %r15, %rcx
    mov     S8(%rsp), %r8
    add     $NodeEvent_result, %r8
    FORK_CALL node_attester_slashing
99: LEAVE 32
8:  mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 32
END_FUNCTION lantern_node_run
