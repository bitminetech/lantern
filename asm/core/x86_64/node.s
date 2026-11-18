/*
 * The node core, x86-64: in the common object. Requirements: docs/reference/node.md.
 */

.set NODE_ROOT_ENTRY, 40                # lantern_node_step: a flag, then the root of a BLOCK event
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

/* reg = the node rbx's ByteList of the libp2p events it queued. */
.macro P2P_OUT reg
    mov     Node_p2p_out(%rbx), \reg
    add     %rbx, \reg
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

/* r8 += the room rdi field times width; to 9f on overflow. Uses rax, rcx, rdx. */
.macro NODE_SIZE_ADD field, width
    mov     NodeRoom_\field(%rdi), %rax
    mov     $(\width), %ecx
    mul     %rcx
    jc      9f
    add     %rax, %r8
    jc      9f
.endm

/* (room, size): NODE_FIXED + the room of each part. */
FUNCTION lantern_node_size
    UNWIND_END_PROLOGUE
    mov     NodeRoom_request_bytes(%rdi), %rcx      # the bytes of a stream
    mov     %rcx, %rax
    shr     $32, %rax
    jnz     9f
    add     $(NodeStream__fixed + 7), %rcx
    and     $-8, %rcx
    mov     NodeRoom_streams(%rdi), %rax
    mul     %rcx
    jc      9f
    mov     %rax, %r8
    NODE_SIZE_ADD blocks, NodeBlock__mem
    NODE_SIZE_ADD checkpoints, NodeCheckpoint__mem
    NODE_SIZE_ADD pow_blocks, POW_BLOCK_BYTES
    NODE_SIZE_ADD peers, NodePeer__mem
    NODE_SIZE_ADD messages, NodeMessage__mem
    NODE_SIZE_ADD blobs, NodeBlob__mem
    mov     NodeRoom_p2p_out(%rdi), %rax    # a ByteList
    add     $(24 + 7), %rax
    jc      9f
    and     $-8, %rax
    add     %rax, %r8
    jc      9f
    mov     NodeRoom_engine_bytes(%rdi), %rax       # a ByteList
    add     $(24 + 7), %rax
    jc      9f
    and     $-8, %rax
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

/* The next part of the node rdi at rax; rax += the room rsi field times width. Uses rcx. */
.macro NODE_PART part, field, width
    mov     %rax, Node_\part(%rdi)
    movq    $(0), (Node_\part + 8)(%rdi)
    imul    $(\width), NodeRoom_\field(%rsi), %rcx
    add     %rcx, %rax
.endm

/* Lay out the parts of the node rdi for the room rsi at NODE_FIXED, with no entries. Uses rax, rcx, rdx. */
LOCAL_FUNCTION node_layout
    UNWIND_END_PROLOGUE
    mov     NodeRoom_request_bytes(%rsi), %rdx
    add     $(NodeStream__fixed + 7), %rdx
    and     $-8, %rdx
    mov     %rdx, Node_stream_bytes(%rdi)
    MOVQ    %rax, NODE_FIXED
    NODE_PART blocks, blocks, NodeBlock__mem
    NODE_PART checkpoints, checkpoints, NodeCheckpoint__mem
    NODE_PART pow_blocks, pow_blocks, POW_BLOCK_BYTES
    NODE_PART peers, peers, NodePeer__mem
    mov     %rax, Node_streams(%rdi)
    movq    $0, (Node_streams + 8)(%rdi)
    mov     NodeRoom_streams(%rsi), %rcx
    imul    %rdx, %rcx
    add     %rcx, %rax
    NODE_PART messages, messages, NodeMessage__mem
    NODE_PART blobs, blobs, NodeBlob__mem
    mov     %rax, Node_p2p_out(%rdi)        # one ByteList, empty
    movq    $1, (Node_p2p_out + 8)(%rdi)
    mov     NodeRoom_p2p_out(%rsi), %rcx
    add     $(24 + 7), %rcx
    and     $-8, %rcx
    mov     %rcx, (%rdi,%rax)
    movq    $24, 8(%rdi,%rax)
    movq    $0, 16(%rdi,%rax)
    add     %rcx, %rax
    mov     %rax, Node_engine_in(%rdi)      # one ByteList, empty
    movq    $1, (Node_engine_in + 8)(%rdi)
    mov     NodeRoom_engine_bytes(%rsi), %rcx
    add     $(24 + 7), %rcx
    and     $-8, %rcx
    mov     %rcx, (%rdi,%rax)
    movq    $24, 8(%rdi,%rax)
    movq    $0, 16(%rdi,%rax)
    ret
END_FUNCTION node_layout

/*
 * (room, config, anchor, flags, node): a node whose one block is the anchor, imported, with
 * post-state id 1, and whose one checkpoint is (anchor epoch, anchor root) at state id 1.
 * rbx room, rbp config, r12 anchor, r13 anchor slot, r14 flags, r15 node. Locals: L the size.
 */
FUNCTION lantern_node_init
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     NodeAnchor_slot(%r12), %r13
    mov     (%rcx), %r14
    mov     %r8, %r15
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
    mov     %r13, Node_earliest_slot(%r15)
    lea     Node_head_root(%r15), %rdi
    COPY32  %rdi, %r12
    lea     Node_genesis_validators_root(%r15), %rdi
    lea     NodeAnchor_genesis_validators_root(%r12), %rsi
    COPY32  %rdi, %rsi
    lea     Node_config(%r15), %rdi
    mov     %rbp, %rsi
    MOVQ    %rdx, CONFIG_SIZE
    call    lantern_copy
    mov     CONFIG_SAMPLES_PER_SLOT(%rbp), %rsi  # the columns: of max(SAMPLES_PER_SLOT, CUSTODY_REQUIREMENT) groups
    mov     CONFIG_CUSTODY_REQUIREMENT(%rbp), %rax
    cmp     %rax, %rsi
    cmovb   %rax, %rsi
    lea     NodeAnchor_node_id(%r12), %rdi
    mov     %rbp, %rdx
    lea     Node_columns(%r15), %rcx
    call    node_custody_columns
    test    %rax, %rax
    jnz     9f
    test    $NODE_FLAG_ENGINE, %r14         # the secret, the host, the first id, and a forkchoiceUpdated due
    jz      1f
    mov     NodeAnchor_engine_host_len(%r12), %rdx
    cmp     $NODE_ENGINE_HOST_MAX, %rdx
    ja      7f
    mov     %rdx, Node_engine_host_len(%r15)
    lea     Node_engine_host(%r15), %rdi
    lea     NodeAnchor_engine_host(%r12), %rsi
    call    lantern_copy
    lea     Node_jwt_secret(%r15), %rdi
    lea     NodeAnchor_jwt_secret(%r12), %rsi
    COPY32  %rdi, %rsi
    movq    $1, Node_engine_id(%r15)
    orq     $NODE_FLAG_FCU, Node_flags(%r15)
1:  mov     %r15, %rdi
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
7:  mov     $LANTERN_INVALID_EVENT, %eax
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

/* Branch to 8f when the room rbp field is below the entries of the part at ref of the node rbx. Uses rax. */
.macro NODE_COPY_ROOM field, ref
    mov     NodeRoom_\field(%rbp), %rax
    cmp     ((\ref) + 8)(%rbx), %rax
    jb      8f
.endm

/*
 * (node, room, out): the node in out, with the capacities of room. rbx node, rbp room, r12 out,
 * r13 a stream, r14 the streams left, r15 the old stream bytes, S7 the new stream. Locals: L the size.
 */
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
    NODE_COPY_ROOM blocks, Node_blocks      # each capacity holds the entries
    NODE_COPY_ROOM checkpoints, Node_checkpoints
    NODE_COPY_ROOM pow_blocks, Node_pow_blocks
    NODE_COPY_ROOM peers, Node_peers
    NODE_COPY_ROOM streams, Node_streams
    NODE_COPY_ROOM messages, Node_messages
    NODE_COPY_ROOM blobs, Node_blobs
    mov     Node_p2p_out(%rbx), %rax        # the queued bytes fit
    mov     16(%rbx,%rax), %rax
    cmp     %rax, NodeRoom_p2p_out(%rbp)
    jb      8f
    mov     Node_engine_in(%rbx), %rax      # the execution engine's bytes fit
    mov     16(%rbx,%rax), %rax
    cmp     %rax, NodeRoom_engine_bytes(%rbp)
    jb      8f
    mov     Node_stream_bytes(%rbx), %r15   # a stream's request bytes fit
    mov     NodeRoom_request_bytes(%rbp), %rax
    add     $(NodeStream__fixed + 7), %rax
    and     $-8, %rax
    cmp     %r15, %rax
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
    NODE_COPY_PART Node_peers, NodePeer__mem
    NODE_COPY_PART Node_messages, NodeMessage__mem
    NODE_COPY_PART Node_blobs, NodeBlob__mem
    mov     Node_p2p_out(%rbx), %rsi        # the queued bytes
    add     %rbx, %rsi
    mov     16(%rsi), %rdx
    mov     Node_p2p_out(%r12), %rdi
    add     %r12, %rdi
    mov     %rdx, 16(%rdi)
    add     $24, %rdi
    add     $24, %rsi
    call    lantern_copy
    mov     Node_engine_in(%rbx), %rsi      # the execution engine's bytes
    add     %rbx, %rsi
    mov     16(%rsi), %rdx
    mov     Node_engine_in(%r12), %rdi
    add     %r12, %rdi
    mov     %rdx, 16(%rdi)
    add     $24, %rdi
    add     $24, %rsi
    call    lantern_copy
    PART    %r13, %r14, %rbx, Node_streams  # each stream, with the request room of the new stride
    mov     %r14, (Node_streams + 8)(%r12)
    mov     Node_streams(%r12), %rax
    add     %r12, %rax
    mov     %rax, S7(%rsp)
1:  test    %r14, %r14
    jz      2f
    mov     S7(%rsp), %rdi
    mov     %r13, %rsi
    mov     %r15, %rdx
    call    lantern_copy
    mov     S7(%rsp), %rdi
    mov     Node_stream_bytes(%r12), %rax
    lea     -NodeStream_list(%rax), %rcx
    mov     %rcx, NodeStream_list(%rdi)
    add     %rax, S7(%rsp)
    add     %r15, %r13
    dec     %r14
    jmp     1b
2:  xor     %eax, %eax
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

/* rax = a WORK action: kind rdi, state_a rsi, state_b rdx, data rcx, target r8, arg r9; state_c 0. Uses r10. */
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
    movq    $0, NodeAction_state_c(%rax)
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
 * The import of the block of index rdi when its parent has a post-state; a block whose parent is
 * invalid becomes invalid. With NODE_FLAG_ENGINE a block of bellatrix or later takes
 * NODE_BLOCK_PAYLOAD instead: its import waits for engine_newPayload. r12 index, r13 entry.
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
    testq   $NODE_FLAG_ENGINE, Node_flags(%rbx)
    jz      1f
    mov     NodeBlock_slot(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_BELLATRIX, %rax
    jb      1f
    movq    $NODE_BLOCK_PAYLOAD, NodeBlock_status(%r13)
    movq    $0, NodeBlock_retry(%r13)
    LEAVE 0
1:  mov     $PAYLOAD_STATUS_VALID, %esi     # VALID, or NOT_VALIDATED with NODE_FLAG_OPTIMISTIC
    mov     $PAYLOAD_STATUS_NOT_VALIDATED, %eax
    testq   $NODE_FLAG_OPTIMISTIC, Node_flags(%rbx)
    cmovnz  %rax, %rsi
    mov     %r12, %rdi
    call    node_import_now
    LEAVE 0
8:  movq    $NODE_BLOCK_INVALID, NodeBlock_status(%r13)
9:  LEAVE 0
END_FUNCTION node_try_import

/*
 * The import of the block of index rdi, whose parent is imported, with the payload status rsi: a
 * copy of the parent's post-state and an IMPORT_BLOCK work. r12 index, r13 entry, S7 the parent's
 * state id.
 */
LOCAL_FUNCTION node_import_now
    ENTER 0
    mov     %rdi, %r12
    PART    %r13, %rax, %rbx, Node_blocks
    imul    $NodeBlock__mem, %r12, %rax
    add     %rax, %r13
    mov     %rsi, NodeBlock_payload_status(%r13)
    lea     NodeBlock_parent_root(%r13), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      9f
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
9:  LEAVE 0
END_FUNCTION node_import_now

/* rax = the index of the store's node whose root is at rdi, or 2^64 - 1; rdx = its entry. Uses rcx, r11, xmm0-xmm2. */
LOCAL_FUNCTION node_store_find
    UNWIND_END_PROLOGUE
    PART    %rdx, %rcx, %rbp, Store_blocks
    xor     %eax, %eax
1:  cmp     %rcx, %rax
    jae     3f
    NE32    %rdx, %rdi, 2f
    ret
2:  add     $BlockNode__mem, %rdx
    inc     %rax
    jmp     1b
3:  mov     $-1, %rax
    ret
END_FUNCTION node_store_find

/*
 * With NODE_FLAG_ENGINE, the next engine call when none is in flight and the store's slot is at
 * least engine_wait: a NEW_PAYLOAD work for the first block in NODE_BLOCK_PAYLOAD whose retry is
 * at most the slot, else with NODE_FLAG_FCU from bellatrix on a FORKCHOICE work. r12 an entry,
 * r13 the index, S7 the slot, S8 the count.
 */
LOCAL_FUNCTION node_engine_next
    ENTER 0
    testq   $NODE_FLAG_ENGINE, Node_flags(%rbx)
    jz      9f
    cmpq    $0, Node_engine_method(%rbx)
    jne     9f
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, S7(%rsp)
    cmp     Node_engine_wait(%rbx), %rax
    jb      9f
    PART    %r12, %rax, %rbx, Node_blocks
    mov     %rax, S8(%rsp)
    xor     %r13d, %r13d
1:  cmp     S8(%rsp), %r13
    jae     3f
    cmpq    $NODE_BLOCK_PAYLOAD, NodeBlock_status(%r12)
    jne     2f
    mov     NodeBlock_retry(%r12), %rax
    cmp     S7(%rsp), %rax
    ja      2f
    movq    $NODE_BLOCK_EXECUTING, NodeBlock_status(%r12)
    movq    $ENGINE_METHOD_NEW_PAYLOAD, Node_engine_method(%rbx)
    mov     %r13, Node_engine_target(%rbx)
    mov     Node_engine_id(%rbx), %r9
    incq    Node_engine_id(%rbx)
    mov     $NODE_WORK_NEW_PAYLOAD, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     NodeBlock_data_id(%r12), %rcx
    mov     %r13, %r8
    call    node_work
    LEAVE 0
2:  add     $NodeBlock__mem, %r12
    inc     %r13
    jmp     1b
3:  testq   $NODE_FLAG_FCU, Node_flags(%rbx)
    jz      9f
    mov     S7(%rsp), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_BELLATRIX, %rax
    jb      9f
    andq    $~NODE_FLAG_FCU, Node_flags(%rbx)
    movq    $ENGINE_METHOD_FORKCHOICE_UPDATED, Node_engine_method(%rbx)
    mov     Node_engine_id(%rbx), %r9
    incq    Node_engine_id(%rbx)
    mov     $NODE_WORK_FORKCHOICE, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    node_work
9:  LEAVE 0
END_FUNCTION node_engine_next

/*
 * The engine call in flight failed: an engine_newPayload's block takes NODE_BLOCK_PAYLOAD with
 * retry the store's slot + 1, an engine_forkchoiceUpdated sets NODE_FLAG_FCU again; engine_wait
 * becomes the slot + 1 and the call ends.
 */
LOCAL_FUNCTION node_engine_failed
    ENTER 0
    mov     %rbp, %rdi
    call    node_store_slot
    inc     %rax
    mov     %rax, Node_engine_wait(%rbx)
    mov     Node_engine_method(%rbx), %rax
    movq    $0, Node_engine_method(%rbx)
    cmp     $ENGINE_METHOD_FORKCHOICE_UPDATED, %rax
    jne     1f
    orq     $NODE_FLAG_FCU, Node_flags(%rbx)
    LEAVE 0
1:  cmp     $ENGINE_METHOD_NEW_PAYLOAD, %rax
    jne     9f
    mov     Node_engine_target(%rbx), %rdi
    call    node_payload_retry
9:  LEAVE 0
END_FUNCTION node_engine_failed

/* The block of index rdi, if NODE_BLOCK_EXECUTING, takes NODE_BLOCK_PAYLOAD with retry the store's slot + 1. r12 the entry. */
LOCAL_FUNCTION node_payload_retry
    ENTER 0
    PART    %r12, %rax, %rbx, Node_blocks
    cmp     %rax, %rdi
    jae     9f
    imul    $NodeBlock__mem, %rdi, %rax
    add     %rax, %r12
    cmpq    $NODE_BLOCK_EXECUTING, NodeBlock_status(%r12)
    jne     9f
    movq    $NODE_BLOCK_PAYLOAD, NodeBlock_status(%r12)
    mov     %rbp, %rdi
    call    node_store_slot
    inc     %rax
    mov     %rax, NodeBlock_retry(%r12)
9:  LEAVE 0
END_FUNCTION node_payload_retry

/*
 * latestValidHash (optimistic-sync.md) from the store's node rdi: up its chain by parent, each
 * node whose block_hash is not the hash at rsi gets store_payload_status INVALIDATED, until the
 * node with that hash; a zero hash stops at the first zero block_hash. With rsi 0 (null), or a hash
 * the chain does not have, only the node rdx (2^64 - 1 for none) gets it. r12 a node, r13 the hash,
 * S7 the node found, S8 the node rdx. Locals: L a node, L+8 a status, L+16 a result.
 */
LOCAL_FUNCTION node_lvh
    ENTER 32
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     %rdx, S8(%rsp)
    test    %r13, %r13
    jz      5f
    mov     %r12, %rax                      # the node of the hash, up the chain
1:  PART    %rcx, %rdx, %rbp, Store_blocks
    cmp     %rdx, %rax
    jae     5f
    imul    $BlockNode__mem, %rax, %rdx
    add     %rdx, %rcx
    lea     BlockNode_block_hash(%rcx), %rdx
    NE32    %rdx, %r13, 2f
    jmp     3f
2:  mov     BlockNode_parent(%rcx), %rax
    jmp     1b
3:  mov     %rax, S7(%rsp)                  # found: each node from r12 below it
4:  cmp     S7(%rsp), %r12
    je      9f
    mov     %r12, L(%rsp)
    movq    $PAYLOAD_STATUS_INVALIDATED, (L + 8)(%rsp)
    mov     %rbp, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_store_payload_status
    imul    $BlockNode__mem, %r12, %rax
    add     Store_blocks(%rbp), %rax
    mov     BlockNode_parent(%rbp,%rax), %r12
    jmp     4b
5:  mov     S8(%rsp), %rax                  # null, or not found: the node in question
    cmp     $-1, %rax
    je      9f
    mov     %rax, L(%rsp)
    movq    $PAYLOAD_STATUS_INVALIDATED, (L + 8)(%rsp)
    mov     %rbp, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_store_payload_status
9:  LEAVE 32
END_FUNCTION node_lvh

/* The first rsi bytes of the ByteList rdi (engine_in) leave it. */
LOCAL_FUNCTION node_engine_consume
    FRAME 0
    mov     16(%rdi), %rdx
    sub     %rsi, %rdx
    mov     %rdx, 16(%rdi)
    add     $24, %rdi
    add     %rdi, %rsi
    call    lantern_copy
    UNFRAME 0
END_FUNCTION node_engine_consume

/*
 * The bytes of engine_in: a whole HTTP response of the call in flight ends it. r12 engine_in, r13
 * the method, S7 the scratch size, restored on return, S8 the body's ByteList, S9 a block entry.
 * Locals: L an HttpResponse (16), L+16 eof, L+24 the method, L+32 an EngineResponse (96), L+128 a
 * node, L+136 a status.
 */
LOCAL_FUNCTION node_engine_read
    ENTER 144
    mov     Node_engine_in(%rbx), %r12
    add     %rbx, %r12
    mov     Node_engine_method(%rbx), %r13
    test    %r13, %r13
    jz      8f                              # no call in flight: the bytes go
    mov     (%r14), %rax
    mov     %rax, S7(%rsp)
    mov     16(%r12), %rcx                  # the body's ByteList at the end of scratch, as long as the bytes
    add     $(24 + 7), %rcx
    and     $-8, %rcx
    sub     %rcx, %rax
    jb      7f
    mov     %rax, (%r14)
    lea     (%r14,%rax), %rdx
    mov     %rdx, S8(%rsp)
    mov     %rcx, (%rdx)
    movq    $24, 8(%rdx)
    movq    $0, 16(%rdx)
    movq    $0, (L + 16)(%rsp)
    mov     %r12, %rdi
    lea     (L + 16)(%rsp), %rsi
    mov     S8(%rsp), %rdx
    lea     L(%rsp), %rcx
    call    lantern_http_parse_response
    cmp     $LANTERN_HTTP_MORE, %rax
    je      6f
    test    %rax, %rax
    jnz     7f
    cmpq    $200, L(%rsp)
    jne     70f
    mov     %r13, (L + 24)(%rsp)
    mov     S8(%rsp), %rdi
    lea     (L + 24)(%rsp), %rsi
    lea     (L + 32)(%rsp), %rdx
    call    lantern_engine_parse_response
    test    %rax, %rax
    jnz     70f
    cmpq    $0, (L + 32 + EngineResponse_error)(%rsp)
    jne     70f
    mov     Node_engine_id(%rbx), %rax
    dec     %rax
    cmp     (L + 32 + EngineResponse_id)(%rsp), %rax
    jne     70f
    mov     %r12, %rdi
    mov     (L + 8)(%rsp), %rsi
    call    node_engine_consume
    mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    movq    $0, Node_engine_method(%rbx)    # the call ends
    mov     (L + 32 + EngineResponse_status)(%rsp), %rax
    cmp     $ENGINE_METHOD_NEW_PAYLOAD, %r13
    jne     40f
    mov     Node_engine_target(%rbx), %rdi  # engine_newPayload: its block
    PART    %rcx, %rdx, %rbx, Node_blocks
    cmp     %rdx, %rdi
    jae     9f
    imul    $NodeBlock__mem, %rdi, %rdx
    add     %rdx, %rcx
    mov     %rcx, S9(%rsp)
    cmpq    $NODE_BLOCK_EXECUTING, NodeBlock_status(%rcx)
    jne     9f
    cmp     $ENGINE_STATUS_VALID, %rax
    jne     20f
    mov     $PAYLOAD_STATUS_VALID, %esi     # VALID: the import
    call    node_import_now
    jmp     9f
20: cmp     $ENGINE_STATUS_SYNCING, %rax
    je      21f
    cmp     $ENGINE_STATUS_ACCEPTED, %rax
    jne     30f
21: mov     S9(%rsp), %rdi                  # SYNCING, ACCEPTED: optimistic when a candidate
    add     $NodeBlock_parent_root, %rdi
    call    node_store_find
    cmp     $-1, %rax
    je      23f
    mov     BlockNode_block_hash(%rdx), %rax
    or      (BlockNode_block_hash + 8)(%rdx), %rax
    or      (BlockNode_block_hash + 16)(%rdx), %rax
    or      (BlockNode_block_hash + 24)(%rdx), %rax
    jnz     22f
23: mov     %rbp, %rdi
    call    node_store_slot
    mov     S9(%rsp), %rcx
    mov     NodeBlock_slot(%rcx), %rdx
    add     $SAFE_SLOTS_TO_IMPORT_OPTIMISTICALLY, %rdx
    cmp     %rax, %rdx
    jbe     22f
    mov     Node_engine_target(%rbx), %rdi  # no candidate: again in a later slot
    call    node_payload_retry
    jmp     9f
22: mov     Node_engine_target(%rbx), %rdi
    mov     $PAYLOAD_STATUS_NOT_VALIDATED, %esi
    call    node_import_now
    jmp     9f
30: mov     S9(%rsp), %rcx                  # INVALID, INVALID_BLOCK_HASH: the block is invalid, latestValidHash from its parent
    movq    $NODE_BLOCK_INVALID, NodeBlock_status(%rcx)
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     NodeBlock_data_id(%rcx), %rsi
    xor     %edx, %edx
    call    node_ids
    mov     S9(%rsp), %rdi
    add     $NodeBlock_parent_root, %rdi
    call    node_store_find
    cmp     $-1, %rax
    je      9f
    mov     %rax, %rdi
    lea     (L + 32 + EngineResponse_latest_valid_hash)(%rsp), %rsi
    xor     %ecx, %ecx
    cmpq    $0, (L + 32 + EngineResponse_has_latest_valid_hash)(%rsp)
    cmove   %rcx, %rsi
    mov     $-1, %rdx
    call    node_lvh
    jmp     9f
40: lea     Node_head_root(%rbx), %rdi      # engine_forkchoiceUpdated: of the head
    call    node_store_find
    cmp     $-1, %rax
    je      9f
    mov     %rax, (L + 128)(%rsp)
    mov     (L + 32 + EngineResponse_status)(%rsp), %rcx
    cmp     $ENGINE_STATUS_VALID, %rcx
    jne     41f
    movq    $PAYLOAD_STATUS_VALID, (L + 136)(%rsp)
    mov     %rbp, %rdi
    lea     (L + 128)(%rsp), %rsi
    lea     (L + 136)(%rsp), %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_store_payload_status
    jmp     9f
41: cmp     $ENGINE_STATUS_INVALID, %rcx
    je      42f
    cmp     $ENGINE_STATUS_INVALID_BLOCK_HASH, %rcx
    jne     9f
42: mov     (L + 128)(%rsp), %rdi
    mov     %rdi, %rdx
    lea     (L + 32 + EngineResponse_latest_valid_hash)(%rsp), %rsi
    xor     %ecx, %ecx
    cmpq    $0, (L + 32 + EngineResponse_has_latest_valid_hash)(%rsp)
    cmove   %rcx, %rsi
    call    node_lvh
9:  LEAVE 144
6:  mov     S7(%rsp), %rax                  # part of a response: more bytes
    mov     %rax, (%r14)
    LEAVE 144
70: mov     %r12, %rdi                      # a failed call, its response read
    mov     (L + 8)(%rsp), %rsi
    call    node_engine_consume
7:  mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    call    node_engine_failed
8:  mov     Node_engine_in(%rbx), %rax      # the bytes left go
    movq    $0, 16(%rbx,%rax)
    LEAVE 144
END_FUNCTION node_engine_read

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

/* rax = the node's NODE_BLOB_VALID entry of the root at rdi and the index rsi, or 0. Uses rcx, rdx, r11, xmm0-xmm2. */
LOCAL_FUNCTION node_blob_held
    UNWIND_END_PROLOGUE
    PART    %rdx, %rcx, %rbx, Node_blobs
1:  test    %rcx, %rcx
    jz      3f
    cmpq    $NODE_BLOB_VALID, NodeBlob_status(%rdx)
    jne     2f
    cmp     NodeBlob_index(%rdx), %rsi
    jne     2f
    NE32    %rdx, %rdi, 2f
    mov     %rdx, %rax
    ret
2:  add     $NodeBlob__mem, %rdx
    dec     %rcx
    jmp     1b
3:  xor     %eax, %eax
    ret
END_FUNCTION node_blob_held

/*
 * rax = 1 when the node holds a NODE_BLOB_VALID entry of the root at rdi for each index below rsi
 * (1 to NODE_BLOB_MAX), else 0. Uses rcx, rdx, r8, r9, r11, xmm0-xmm2.
 */
LOCAL_FUNCTION node_blobs_held
    UNWIND_END_PROLOGUE
    PART    %rdx, %r8, %rbx, Node_blobs
    xor     %r9d, %r9d                      # a bit for each index held
1:  test    %r8, %r8
    jz      3f
    cmpq    $NODE_BLOB_VALID, NodeBlob_status(%rdx)
    jne     2f
    mov     NodeBlob_index(%rdx), %rcx
    cmp     %rsi, %rcx
    jae     2f
    NE32    %rdx, %rdi, 2f
    bts     %rcx, %r9
2:  add     $NodeBlob__mem, %rdx
    dec     %r8
    jmp     1b
3:  mov     $64, %ecx                       # every index below rsi
    sub     %rsi, %rcx
    mov     $-1, %rax
    shr     %cl, %rax
    cmp     %rax, %r9
    sete    %al
    movzbl  %al, %eax
    ret
END_FUNCTION node_blobs_held

/* rax = 1 when the node rbx samples the column rdi, else 0. A leaf; uses rcx. */
LOCAL_FUNCTION node_sampled
    UNWIND_END_PROLOGUE
    xor     %eax, %eax
    cmp     $128, %rdi
    jae     1f
    mov     %rdi, %rcx
    shr     $3, %rcx
    movzbl  Node_columns(%rbx,%rcx), %eax
    mov     %edi, %ecx
    and     $7, %ecx
    shr     %cl, %eax
    and     $1, %eax
1:  ret
END_FUNCTION node_sampled

/* rax = the columns the node rbx samples: the bits of Node_columns. A leaf; uses rcx, rdx. */
LOCAL_FUNCTION node_column_count
    UNWIND_END_PROLOGUE
    xor     %eax, %eax
    mov     Node_columns(%rbx), %rcx
1:  test    %rcx, %rcx
    jz      2f
    lea     -1(%rcx), %rdx
    and     %rdx, %rcx
    inc     %rax
    jmp     1b
2:  mov     (Node_columns + 8)(%rbx), %rcx
3:  test    %rcx, %rcx
    jz      4f
    lea     -1(%rcx), %rdx
    and     %rdx, %rcx
    inc     %rax
    jmp     3b
4:  ret
END_FUNCTION node_column_count

/*
 * rax = 1 when the node holds a NODE_BLOB_VALID entry of the root at rdi for each column it
 * samples, else 0. A leaf; uses rcx, rdx, rsi, r8, r9, r11, xmm0-xmm2.
 */
LOCAL_FUNCTION node_columns_held
    UNWIND_END_PROLOGUE
    PART    %rdx, %r8, %rbx, Node_blobs
    xor     %r9d, %r9d                      # a bit for each column held: r9 below 64, rsi from 64
    xor     %esi, %esi
1:  test    %r8, %r8
    jz      3f
    cmpq    $NODE_BLOB_VALID, NodeBlob_status(%rdx)
    jne     2f
    mov     NodeBlob_index(%rdx), %rcx
    cmp     $128, %rcx
    jae     2f
    NE32    %rdx, %rdi, 2f
    cmp     $64, %rcx
    jae     21f
    bts     %rcx, %r9
    jmp     2f
21: bts     %rcx, %rsi
2:  add     $NodeBlob__mem, %rdx
    dec     %r8
    jmp     1b
3:  mov     Node_columns(%rbx), %rax        # each sampled column held
    not     %r9
    and     %r9, %rax
    mov     (Node_columns + 8)(%rbx), %rcx
    not     %rsi
    and     %rsi, %rcx
    or      %rcx, %rax
    sete    %al
    movzbl  %al, %eax
    ret
END_FUNCTION node_columns_held

/*
 * rax = the first epoch of a sidecar window: max(the epoch of the store rbp - rdi, the epoch of
 * the fork rsi in the node rbx's config). Locals: 0 rdi, 8 rsi.
 */
LOCAL_FUNCTION node_window
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rbp, %rdi
    call    node_store_slot
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    sub     (%rsp), %rax
    jae     1f
    xor     %eax, %eax
1:  mov     8(%rsp), %rcx
    shl     $4, %rcx
    mov     Node_config(%rbx,%rcx), %rcx
    cmp     %rcx, %rax
    cmovb   %rcx, %rax
    UNFRAME 16
END_FUNCTION node_window

/*
 * The columns of the groups of get_custody_groups(the NodeID at rdi, rsi groups) of the config
 * rdx, as bits in the 16 bytes at rcx: rax = 0, or LANTERN_INVALID_CUSTODY_GROUP and no bits (a
 * count above NUMBER_OF_CUSTODY_GROUPS or 128). rbx config, rbp out, r12 a group, r13 the groups
 * left, r14 NUMBER_OF_CUSTODY_GROUPS. Locals: L the count, L+16 an IndexList.
 */
LOCAL_FUNCTION node_custody_columns
    ENTER NODE_CUSTODY_LOCALS
    mov     %rdx, %rbx
    mov     %rcx, %rbp
    movq    $0, (%rbp)
    movq    $0, 8(%rbp)
    mov     %rsi, L(%rsp)
    cmp     $128, %rsi
    ja      8f
    movq    $NODE_CUSTODY_LIST, (L + 16)(%rsp)
    lea     L(%rsp), %rsi
    mov     %rbx, %rdx
    lea     (L + 16)(%rsp), %rcx
    CALL_GLOBAL lantern_fulu_get_custody_groups
    test    %rax, %rax
    jnz     8f
    mov     (L + 16 + 16)(%rsp), %r13
    lea     (L + 16 + LIST_FIXED)(%rsp), %r12
    mov     CONFIG_NUMBER_OF_CUSTODY_GROUPS(%rbx), %r14
1:  test    %r13, %r13
    jz      9f
    mov     (%r12), %rsi                    # a group g: the columns N * i + g, i below NUMBER_OF_COLUMNS // N
    add     $8, %r12
    MOVQ    %rax, NUMBER_OF_COLUMNS
    xor     %edx, %edx
    div     %r14
    mov     %rax, %rdi
2:  test    %rdi, %rdi
    jz      3f
    mov     %rsi, %rcx
    shr     $6, %rcx
    mov     (%rbp,%rcx,8), %rax
    bts     %rsi, %rax
    mov     %rax, (%rbp,%rcx,8)
    add     %r14, %rsi
    dec     %rdi
    jmp     2b
3:  dec     %r13
    jmp     1b
9:  xor     %eax, %eax
    LEAVE NODE_CUSTODY_LOCALS
8:  movq    $0, (%rbp)
    movq    $0, 8(%rbp)
    mov     $LANTERN_INVALID_CUSTODY_GROUP, %eax
    LEAVE NODE_CUSTODY_LOCALS
END_FUNCTION node_custody_columns

/*
 * The peer rdi takes NODE_PEER_METADATA, and as custody the columns of the groups of
 * get_custody_groups(its node ID, rsi groups) when its peer ID holds a secp256k1 key that
 * decompresses; else no custody. r12 the peer, r13 the count. Locals: L the point (64), L+64 a
 * ByteList of the point (88), L+152 the digest (32), L+184 the NodeID (32).
 */
LOCAL_FUNCTION node_peer_custody
    ENTER 224
    mov     %rdi, %r12
    mov     %rsi, %r13
    orq     $NODE_PEER_METADATA, NodePeer_flags(%r12)
    movq    $0, NodePeer_custody(%r12)
    movq    $0, (NodePeer_custody + 8)(%r12)
    cmpq    $39, NodePeer_id_len(%r12)      # 0x00 0x25 0x08 0x02 0x12 0x21, then the key
    jne     9f
    mov     NodePeer_id(%r12), %rax
    shl     $16, %rax
    MOVQ    %rcx, 0x211202082500 << 16
    cmp     %rcx, %rax
    jne     9f
    lea     (NodePeer_id + 6)(%r12), %rdi
    lea     L(%rsp), %rsi
    CALL_GLOBAL crypto_secp256k1_decompress
    test    %rax, %rax
    jnz     9f
    movq    $(24 + 64), (L + 64)(%rsp)      # keccak256(x || y)
    movq    $24, (L + 72)(%rsp)
    movq    $64, (L + 80)(%rsp)
    lea     (L + 88)(%rsp), %rdi
    lea     L(%rsp), %rsi
    mov     $64, %edx
    call    lantern_copy
    lea     (L + 64)(%rsp), %rdi
    lea     (L + 152)(%rsp), %rsi
    CALL_GLOBAL crypto_keccak256
    test    %rax, %rax
    jnz     9f
    mov     (L + 152)(%rsp), %rax           # the NodeID: the digest's bytes in reverse order
    mov     (L + 160)(%rsp), %rcx
    mov     (L + 168)(%rsp), %rdx
    mov     (L + 176)(%rsp), %rsi
    bswap   %rax
    bswap   %rcx
    bswap   %rdx
    bswap   %rsi
    mov     %rsi, (L + 184)(%rsp)
    mov     %rdx, (L + 192)(%rsp)
    mov     %rcx, (L + 200)(%rsp)
    mov     %rax, (L + 208)(%rsp)
    lea     (L + 184)(%rsp), %rdi
    mov     %r13, %rsi
    lea     Node_config(%rbx), %rdx
    lea     NodePeer_custody(%r12), %rcx
    call    node_custody_columns
9:  LEAVE 224
END_FUNCTION node_peer_custody

/*
 * The block of index rdi, from the network, waits for its blobs or columns: NODE_BLOCK_BLOBS
 * while it needs sidecars the node does not hold; else data_available 1, NODE_BLOCK_WAITING and
 * its import. Deneb and electra: it needs blobs when its blob count is 1 to the fork's limit and
 * NODE_BLOB_MAX and its epoch is in the blob window. Fulu: it needs columns when its blob count is
 * above 0 and its epoch is in the column window. r12 the index, r13 the entry, S7 the count, S8
 * the window's first epoch.
 */
LOCAL_FUNCTION node_await
    ENTER 0
    mov     %rdi, %r12
    PART    %r13, %rax, %rbx, Node_blocks
    imul    $NodeBlock__mem, %r12, %rax
    add     %rax, %r13
    mov     NodeBlock_blobs(%r13), %rax
    mov     %rax, S7(%rsp)
    test    %rax, %rax
    jz      5f
    mov     NodeBlock_slot(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_FULU, %rax
    jae     6f
    cmpq    $NODE_BLOB_MAX, S7(%rsp)
    ja      5f
    mov     (Node_config + CONFIG_MAX_BLOBS_PER_BLOCK)(%rbx), %rcx
    cmp     $FORK_DENEB, %rax
    je      2f
    cmp     $FORK_ELECTRA, %rax
    jne     5f
    mov     (Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA)(%rbx), %rcx
2:  cmp     %rcx, S7(%rsp)
    ja      5f
    mov     (Node_config + CONFIG_MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS)(%rbx), %rdi  # the blob window
    mov     $FORK_DENEB, %esi
    call    node_window
    mov     %rax, S8(%rsp)
    mov     NodeBlock_slot(%r13), %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    cmp     S8(%rsp), %rax
    jb      5f
    mov     %r13, %rdi
    mov     S7(%rsp), %rsi
    call    node_blobs_held
    test    %rax, %rax
    jnz     5f
4:  movq    $NODE_BLOCK_BLOBS, NodeBlock_status(%r13)
    LEAVE 0
6:  mov     (Node_config + CONFIG_MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS)(%rbx), %rdi  # the column window
    mov     $FORK_FULU, %esi
    call    node_window
    mov     %rax, S8(%rsp)
    mov     NodeBlock_slot(%r13), %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    cmp     S8(%rsp), %rax
    jb      5f
    mov     %r13, %rdi
    call    node_columns_held
    test    %rax, %rax
    jz      4b
5:  movq    $1, NodeBlock_data_available(%r13)
    movq    $NODE_BLOCK_WAITING, NodeBlock_status(%r13)
    mov     %r12, %rdi
    call    node_try_import
    LEAVE 0
END_FUNCTION node_await

/* A blob of the root at rdi became NODE_BLOB_VALID: the block of that root in NODE_BLOCK_BLOBS waits for its blobs again. */
LOCAL_FUNCTION node_blob_added
    FRAME 0
    call    node_find_block
    cmp     $-1, %rax
    je      9f
    cmpq    $NODE_BLOCK_BLOBS, NodeBlock_status(%rdx)
    jne     9f
    mov     %rax, %rdi
    call    node_await
9:  UNFRAME 0
END_FUNCTION node_blob_added

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
    NE32    %rdi, %rcx, 2f                  # a new head with NODE_FLAG_ENGINE: a forkchoiceUpdated is due
    jmp     3f
2:  testq   $NODE_FLAG_ENGINE, Node_flags(%rbx)
    jz      3f
    orq     $NODE_FLAG_FCU, Node_flags(%rbx)
3:  COPY32  %rdi, %rcx
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
    movq    $0, NodeBlock_blobs(%rdi)
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
    jne     45f
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
45: cmp     $NODE_EV_ENGINE, %rax
    jne     47f
    cmpq    $0, 16(%r12)
    je      46f
    call    node_engine_failed              # ENGINE 1: the connection failed
    mov     Node_engine_in(%rbx), %rax
    movq    $0, 16(%rbx,%rax)
    LEAVE 48
46: lea     NodeEvent_bytes(%r12), %rsi     # ENGINE 0: its bytes join engine_in
    mov     Node_engine_in(%rbx), %rdi
    add     %rbx, %rdi
    mov     16(%rdi), %rax
    mov     16(%rsi), %rdx
    lea     (%rax,%rdx), %rcx
    mov     %rcx, 16(%rdi)
    lea     24(%rdi,%rax), %rdi
    add     8(%rsi), %rsi
    call    lantern_copy
    call    node_engine_read
    LEAVE 48
47: cmp     $NODE_EV_ENR, %rax
    jne     50f
    mov     %r12, %rdi                      # ENR: a record discv5 found
    call    node_enr
    LEAVE 48
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
    mov     NodeAction_state_c(%r12), %rcx
    mov     %rcx, NodeAction_state_c(%rax)
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
    jne     62f
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
62: cmp     $NODE_WORK_SERVE, %rax          # SERVE: the chunk to its stream, then the next block or the close
    jne     63f
    mov     NodeAction_target(%r12), %rdi
    call    node_find_stream
    cmp     $-1, %rax
    je      69f
    mov     %rdx, %r13
    cmpq    $0, NodeEvent_result(%r12)
    jne     68f
    mov     (NodeEvent_chunk + 16)(%r12), %rax
    mov     %rax, S7(%rsp)
    lea     (32 + 7)(%rax), %rdi
    and     $-8, %rdi
    mov     %rdi, (L + 32)(%rsp)
    call    node_out
    test    %rax, %rax
    jz      68f
    mov     (L + 32)(%rsp), %rcx
    mov     %rcx, (%rax)
    movq    $LIBP2P_EVENT_STREAM_WRITE, 8(%rax)
    mov     NodeStream_handle(%r13), %rcx
    mov     %rcx, 16(%rax)
    mov     S7(%rsp), %rdx
    mov     %rdx, 24(%rax)
    lea     32(%rax), %rdi
    lea     (NodeEvent_chunk + 24)(%r12), %rsi
    call    lantern_copy
    mov     NodeStream_next(%r13), %rax
    inc     %rax
    mov     %rax, NodeStream_next(%r13)
    mov     (NodeStream_list + 16)(%r13), %rcx
    shr     $3, %rcx
    cmp     %rcx, %rax
    jae     67f
    movq    $NODE_STREAM_SERVE, NodeStream_state(%r13)
    LEAVE 48
67: mov     $LIBP2P_EVENT_STREAM_CLOSE, %edi
    mov     NodeStream_handle(%r13), %rsi
    call    node_out_handle
    mov     %r13, %rdi
    call    node_drop_stream
69: LEAVE 48
68: mov     $LIBP2P_EVENT_STREAM_RESET, %edi        # no chunk, or no room for it: a reset
    mov     NodeStream_handle(%r13), %rsi
    call    node_out_handle
    mov     %r13, %rdi
    call    node_drop_stream
    LEAVE 48
63: cmp     $NODE_WORK_GOSSIP, %rax         # GOSSIP: the VALIDATION, then a valid block to import
    jne     75f
    mov     $LIBP2P_IGNORE, %esi
    mov     $LIBP2P_REJECT, %edx
    cmp     $LANTERN_GOSSIP_REJECT, %rcx
    cmove   %rdx, %rsi
    mov     $LIBP2P_ACCEPT, %edx
    test    %rcx, %rcx
    cmovz   %rdx, %rsi
    mov     %rsi, S7(%rsp)
    mov     NodeAction_target(%r12), %rdi
    call    node_validation
    mov     NodeAction_state_b(%r12), %rsi  # the proposer state
    test    %rsi, %rsi
    jz      64f
    mov     $NODE_ACT_STATE_FREE, %edi
    xor     %edx, %edx
    call    node_ids
64: mov     NodeAction_target(%r12), %rdi
    call    node_find_message
    cmp     $-1, %rax
    je      66f
    mov     %rdx, %r13
    cmpq    $LIBP2P_ACCEPT, S7(%rsp)
    jne     65f
    cmpq    $GOSSIP_ATTESTER_SLASHING, NodeMessage_topic(%r13)
    jne     641f
    mov     NodeAction_state_c(%r12), %rsi  # a valid attester slashing keeps the bytes: on_attester_slashing with the justified root's state
    test    %rsi, %rsi
    jz      65f
    mov     $NODE_WORK_ATTESTER_SLASHING, %edi
    xor     %edx, %edx
    mov     NodeAction_data(%r12), %rcx
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    call    node_work
    mov     %r13, %rdi
    call    node_drop_message
    LEAVE 48
641: cmpq   $GOSSIP_BEACON_BLOCK, NodeMessage_topic(%r13)
    jne     642f
    lea     NodeEvent_root(%r12), %rdi      # a new block keeps the bytes
    call    node_find_block
    cmp     $-1, %rax
    jne     65f
    PART    %rdi, %rcx, %rbx, Node_blocks
    mov     %rcx, (L + 40)(%rsp)
    imul    $NodeBlock__mem, %rcx, %rax
    add     %rax, %rdi
    lea     NodeEvent_root(%r12), %rsi
    COPY32  %rdi, %rsi
    lea     NodeBlock_parent_root(%rdi), %rax
    lea     NodeMessage_parent_root(%r13), %rsi
    COPY32  %rax, %rsi
    mov     NodeMessage_slot(%r13), %rax
    mov     %rax, NodeBlock_slot(%rdi)
    mov     NodeAction_data(%r12), %rax
    mov     %rax, NodeBlock_data_id(%rdi)
    movq    $0, NodeBlock_state_id(%rdi)
    movq    $NODE_BLOCK_WAITING, NodeBlock_status(%rdi)
    movq    $0, NodeBlock_data_available(%rdi)
    movq    $0, NodeBlock_result(%rdi)
    mov     NodeEvent_index(%r12), %rax
    mov     %rax, NodeBlock_blobs(%rdi)
    inc     %rcx
    mov     %rcx, (Node_blocks + 8)(%rbx)
    mov     %r13, %rdi
    call    node_drop_message
    mov     (L + 40)(%rsp), %rdi
    call    node_await
    LEAVE 48
642: cmpq   $GOSSIP_BLOB_SIDECAR, NodeMessage_topic(%r13)  # a new valid sidecar keeps the bytes
    je      643f
    cmpq    $GOSSIP_DATA_COLUMN_SIDECAR, NodeMessage_topic(%r13)  # a column sidecar: of a column the node samples
    jne     65f
    mov     NodeEvent_index(%r12), %rdi
    call    node_sampled
    test    %rax, %rax
    jz      65f
643: lea    NodeEvent_root(%r12), %rdi
    mov     NodeEvent_index(%r12), %rsi
    call    node_blob_held
    test    %rax, %rax
    jnz     65f
    PART    %rdi, %rcx, %rbx, Node_blobs
    imul    $NodeBlob__mem, %rcx, %rax
    add     %rax, %rdi
    lea     NodeEvent_root(%r12), %rsi
    COPY32  %rdi, %rsi
    mov     NodeEvent_index(%r12), %rax
    mov     %rax, NodeBlob_index(%rdi)
    mov     NodeMessage_slot(%r13), %rax
    mov     %rax, NodeBlob_slot(%rdi)
    mov     NodeAction_data(%r12), %rax
    mov     %rax, NodeBlob_data_id(%rdi)
    movq    $NODE_BLOB_VALID, NodeBlob_status(%rdi)
    inc     %rcx
    mov     %rcx, (Node_blobs + 8)(%rbx)
    mov     %r13, %rdi
    call    node_drop_message
    lea     NodeEvent_root(%r12), %rdi
    call    node_blob_added
    LEAVE 48
65: mov     %r13, %rdi
    call    node_drop_message
66: mov     $NODE_ACT_BYTES_FREE, %edi      # else its bytes go
    mov     NodeAction_data(%r12), %rsi
    xor     %edx, %edx
    call    node_ids
    LEAVE 48
75: cmp     $NODE_WORK_SYNC_BLOCK, %rax     # SYNC_BLOCK: the root of a block of a response
    jne     77f
    mov     NodeAction_target(%r12), %rax
    PART    %rdx, %rsi, %rbx, Node_blocks
    cmp     %rsi, %rax
    jae     79f
    mov     %rax, (L + 40)(%rsp)
    imul    $NodeBlock__mem, %rax, %rax
    lea     (%rdx,%rax), %r13
    cmpq    $NODE_BLOCK_HASHING, NodeBlock_status(%r13)
    jne     79f
    test    %rcx, %rcx
    jnz     76f
    lea     NodeEvent_root(%r12), %rdi      # a new root: the block waits for its parent
    call    node_find_block
    cmp     $-1, %rax
    jne     76f
    lea     NodeEvent_root(%r12), %rsi      # the block waits for its blobs, then its parent
    COPY32  %r13, %rsi
    mov     NodeEvent_index(%r12), %rax
    mov     %rax, NodeBlock_blobs(%r13)
    movq    $0, NodeBlock_data_available(%r13)
    mov     (L + 40)(%rsp), %rdi
    call    node_await
    LEAVE 48
76: movq    $NODE_BLOCK_INVALID, NodeBlock_status(%r13)     # not a block, or a known root: invalid, its bytes go
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     NodeBlock_data_id(%r13), %rsi
    xor     %edx, %edx
    call    node_ids
    LEAVE 48
77: cmp     $NODE_WORK_BLOB, %rax           # BLOB: a sidecar of a response, checked
    jne     85f
    mov     NodeAction_target(%r12), %rax
    PART    %rdx, %rsi, %rbx, Node_blobs
    cmp     %rsi, %rax
    jae     79f
    imul    $NodeBlob__mem, %rax, %rax
    lea     (%rdx,%rax), %r13
    cmpq    $NODE_BLOB_VERIFYING, NodeBlob_status(%r13)
    jne     79f
    test    %rcx, %rcx
    jnz     78f
    mov     NodeBlob_slot(%r13), %rdi       # fulu: a column the node samples
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_FULU, %rax
    jb      771f
    mov     NodeBlob_index(%r13), %rdi
    call    node_sampled
    test    %rax, %rax
    jz      78f
771: lea    NodeEvent_root(%r12), %rdi      # valid, and not held yet: the entry takes the root
    mov     NodeBlob_index(%r13), %rsi
    call    node_blob_held
    test    %rax, %rax
    jnz     78f
    lea     NodeEvent_root(%r12), %rsi
    COPY32  %r13, %rsi
    movq    $NODE_BLOB_VALID, NodeBlob_status(%r13)
    mov     %r13, %rdi
    call    node_blob_added
    LEAVE 48
78: movq    $NODE_BLOB_INVALID, NodeBlob_status(%r13)      # not valid, or held: its bytes go
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     NodeBlob_data_id(%r13), %rsi
    xor     %edx, %edx
    call    node_ids
    LEAVE 48
85: cmp     $NODE_WORK_NEW_PAYLOAD, %rax    # NEW_PAYLOAD, FORKCHOICE: the request to the execution engine
    je      86f
    cmp     $NODE_WORK_FORKCHOICE, %rax
    jne     70f
86: test    %rcx, %rcx
    jnz     87f
    mov     (NodeEvent_chunk + 16)(%r12), %r13
    lea     (48 + 7)(%r13), %rsi
    and     $-8, %rsi
    mov     $NODE_ACT_ENGINE, %edi
    call    node_act
    movq    $0, 16(%rax)
    mov     (%rax), %rcx
    sub     $24, %rcx
    mov     %rcx, 24(%rax)
    movq    $24, 32(%rax)
    mov     %r13, 40(%rax)
    lea     48(%rax), %rdi
    lea     (NodeEvent_chunk + 24)(%r12), %rsi
    mov     %r13, %rdx
    call    lantern_copy
    LEAVE 48
87: movq    $0, Node_engine_method(%rbx)    # no request: the call ends
    cmpq    $NODE_WORK_NEW_PAYLOAD, NodeAction_work_kind(%r12)
    jne     79f
    mov     NodeAction_target(%r12), %rdi
    PART    %r13, %rdx, %rbx, Node_blocks
    cmp     %rdx, %rdi
    jae     79f
    imul    $NodeBlock__mem, %rdi, %rdx
    add     %rdx, %r13
    cmpq    $NODE_BLOCK_EXECUTING, NodeBlock_status(%r13)
    jne     79f
    cmp     $LANTERN_NO_PAYLOAD, %rcx
    jne     88f
    mov     $PAYLOAD_STATUS_VALID, %esi     # no payload: the import
    call    node_import_now
    LEAVE 48
88: movq    $NODE_BLOCK_INVALID, NodeBlock_status(%r13)
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     NodeBlock_data_id(%r13), %rsi
    xor     %edx, %edx
    call    node_ids
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

/* ------------------------------------------------------------ libp2p */

/* rax = room for an event of rdi bytes at the end of the node's queued libp2p events, its size written, or 0. Uses rcx, rdx, r8. */
LOCAL_FUNCTION node_out
    UNWIND_END_PROLOGUE
    P2P_OUT %rcx
    mov     16(%rcx), %rdx
    mov     (%rcx), %r8
    sub     $24, %r8
    sub     %rdx, %r8
    cmp     %rdi, %r8
    jb      1f
    lea     24(%rcx,%rdx), %rax
    add     %rdi, %rdx
    mov     %rdx, 16(%rcx)
    mov     %rdi, (%rax)
    ret
1:  xor     %eax, %eax
    ret
END_FUNCTION node_out

/* A queued libp2p event of kind rdi with the handle rsi: DISCONNECT, STREAM_CLOSE or STREAM_RESET. */
LOCAL_FUNCTION node_out_handle
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     $24, %edi
    call    node_out
    test    %rax, %rax
    jz      1f
    mov     (%rsp), %rcx
    mov     %rcx, 8(%rax)
    mov     8(%rsp), %rcx
    mov     %rcx, 16(%rax)
1:  UNFRAME 16
END_FUNCTION node_out_handle

/* Drops the first rdi queued libp2p events, which libp2p took. */
LOCAL_FUNCTION node_out_consume
    FRAME 0
    P2P_OUT %r10
    lea     24(%r10), %r8
    mov     16(%r10), %r9
    xor     %ecx, %ecx
1:  test    %rdi, %rdi
    jz      2f
    cmp     %r9, %rcx
    jae     2f
    add     (%r8,%rcx), %rcx
    dec     %rdi
    jmp     1b
2:  mov     %r9, %rdx
    sub     %rcx, %rdx
    mov     %rdx, 16(%r10)
    lea     (%r8,%rcx), %rsi
    mov     %r8, %rdi
    call    lantern_copy
    UNFRAME 0
END_FUNCTION node_out_consume

/* rax = the index of the peer of libp2p handle rdi, or 2^64 - 1; rdx = its entry. Uses rcx. */
LOCAL_FUNCTION node_find_peer
    UNWIND_END_PROLOGUE
    PART    %rdx, %rcx, %rbx, Node_peers
    xor     %eax, %eax
1:  cmp     %rcx, %rax
    jae     2f
    cmp     NodePeer_handle(%rdx), %rdi
    je      3f
    add     $NodePeer__mem, %rdx
    inc     %rax
    jmp     1b
2:  mov     $-1, %rax
3:  ret
END_FUNCTION node_find_peer

/* rax = the index of the stream of libp2p handle rdi, or 2^64 - 1; rdx = its entry. Uses rcx, rsi. */
LOCAL_FUNCTION node_find_stream
    UNWIND_END_PROLOGUE
    PART    %rdx, %rcx, %rbx, Node_streams
    mov     Node_stream_bytes(%rbx), %rsi
    xor     %eax, %eax
1:  cmp     %rcx, %rax
    jae     2f
    cmp     NodeStream_handle(%rdx), %rdi
    je      3f
    add     %rsi, %rdx
    inc     %rax
    jmp     1b
2:  mov     $-1, %rax
3:  ret
END_FUNCTION node_find_stream

/* Removes the stream entry rdi: the last entry takes its place. */
LOCAL_FUNCTION node_drop_stream
    FRAME 0
    PART    %rax, %rcx, %rbx, Node_streams
    mov     Node_stream_bytes(%rbx), %rdx
    dec     %rcx
    mov     %rcx, (Node_streams + 8)(%rbx)
    imul    %rdx, %rcx
    lea     (%rax,%rcx), %rsi
    cmp     %rdi, %rsi
    je      1f
    call    lantern_copy
1:  UNFRAME 0
END_FUNCTION node_drop_stream

/* Removes the peer entry rdi and its streams. r12 the entry, r13 its handle. */
LOCAL_FUNCTION node_drop_peer
    ENTER 0
    mov     %rdi, %r12
    mov     NodePeer_handle(%r12), %r13
1:  PART    %rdi, %rcx, %rbx, Node_streams  # its streams
    mov     Node_stream_bytes(%rbx), %rdx
2:  test    %rcx, %rcx
    jz      3f
    cmp     NodeStream_peer(%rdi), %r13
    jne     21f
    call    node_end_stream
    jmp     1b
21: add     %rdx, %rdi
    dec     %rcx
    jmp     2b
3:  PART    %rax, %rcx, %rbx, Node_peers    # the entry: the last takes its place
    dec     %rcx
    mov     %rcx, (Node_peers + 8)(%rbx)
    imul    $NodePeer__mem, %rcx, %rcx
    lea     (%rax,%rcx), %rsi
    cmp     %r12, %rsi
    je      9f
    mov     %r12, %rdi
    mov     $NodePeer__mem, %edx
    call    lantern_copy
9:  LEAVE 0
END_FUNCTION node_drop_peer

/*
 * rax = the method of protocol index rdi of lantern_node_protocols, or 0; rdx = its version.
 * The protocols go by method, then by version. Uses rsi, r8.
 */
LOCAL_FUNCTION node_protocol
    UNWIND_END_PROLOGUE
    ADDRESS %rsi, reqresp_names
    mov     $1, %eax
1:  cmp     $REQRESP_METHODS, %rax
    ja      8f
    mov     8(%rsi), %r8
    shr     $8, %r8                         # the mask of its versions
    mov     $1, %edx
2:  cmp     $8, %rdx
    jae     4f
    bt      %rdx, %r8
    jnc     3f
    test    %rdi, %rdi
    jz      5f
    dec     %rdi
3:  inc     %rdx
    jmp     2b
4:  inc     %rax
    add     $16, %rsi
    jmp     1b
5:  ret
8:  xor     %eax, %eax
    xor     %edx, %edx
    ret
END_FUNCTION node_protocol

/*
 * A response of one chunk on the stream entry rdi, result rsi, payload rdx of rcx bytes: a
 * STREAM_WRITE and a STREAM_CLOSE, or a STREAM_RESET when the node has no room; then the entry
 * goes. r12 entry, r13 result, S7 payload, S8 its bytes then the chunk's, S9 the scratch size,
 * S10 the chunk's ByteList. Locals: L a ChunkHeader, L+48 a size, L+56 the payload's ByteList.
 */
LOCAL_FUNCTION node_respond
    ENTER 64
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     %rdx, S7(%rsp)
    mov     %rcx, S8(%rsp)
    mov     %rcx, (L + 48)(%rsp)
    lea     (L + 48)(%rsp), %rdi
    lea     (L + 48)(%rsp), %rsi
    call    lantern_reqresp_chunk_size
    mov     (%r14), %rax                    # the chunk, then the payload, at the end of scratch
    mov     %rax, S9(%rsp)
    mov     S8(%rsp), %rcx
    add     $(24 + 7), %rcx
    and     $-8, %rcx
    mov     (L + 48)(%rsp), %rdx
    add     $(24 + 7), %rdx
    and     $-8, %rdx
    lea     (%rcx,%rdx), %r8
    mov     %rax, %r9
    sub     %r8, %r9
    jb      8f
    mov     %r9, (%r14)
    lea     (%r14,%r9), %r10
    mov     %r10, S10(%rsp)
    lea     (%r10,%rdx), %r11
    mov     %rdx, (%r10)
    movq    $24, 8(%r10)
    movq    $0, 16(%r10)
    mov     %rcx, (%r11)
    movq    $24, 8(%r11)
    mov     S8(%rsp), %rax
    mov     %rax, 16(%r11)
    mov     %r11, (L + 56)(%rsp)
    lea     24(%r11), %rdi
    mov     S7(%rsp), %rsi
    mov     S8(%rsp), %rdx
    call    lantern_copy
    movq    $CHUNK_RESPONSE, (L + ChunkHeader_kind)(%rsp)
    movq    $0, (L + ChunkHeader_context_length)(%rsp)
    mov     %r13, (L + ChunkHeader_result)(%rsp)
    lea     L(%rsp), %rdi
    mov     (L + 56)(%rsp), %rsi
    mov     %r14, %rdx
    mov     S10(%rsp), %rcx
    call    lantern_reqresp_write_chunk
    test    %rax, %rax
    jnz     8f
    mov     S10(%rsp), %rax                 # a STREAM_WRITE of the chunk, then a STREAM_CLOSE
    mov     16(%rax), %rcx
    mov     %rcx, S8(%rsp)
    add     $(32 + 7), %rcx
    and     $-8, %rcx
    mov     %rcx, (L + 48)(%rsp)
    lea     24(%rcx), %rdi
    call    node_out
    test    %rax, %rax
    jz      8f
    mov     (L + 48)(%rsp), %rcx
    mov     %rcx, (%rax)
    movq    $LIBP2P_EVENT_STREAM_WRITE, 8(%rax)
    mov     NodeStream_handle(%r12), %rdx
    mov     %rdx, 16(%rax)
    mov     S8(%rsp), %rsi
    mov     %rsi, 24(%rax)
    lea     (%rax,%rcx), %r8
    movq    $24, (%r8)
    movq    $LIBP2P_EVENT_STREAM_CLOSE, 8(%r8)
    mov     %rdx, 16(%r8)
    lea     32(%rax), %rdi
    mov     S10(%rsp), %rsi
    add     8(%rsi), %rsi
    mov     S8(%rsp), %rdx
    call    lantern_copy
    jmp     9f
8:  mov     $LIBP2P_EVENT_STREAM_RESET, %edi
    mov     NodeStream_handle(%r12), %rsi
    call    node_out_handle
9:  mov     S9(%rsp), %rax
    mov     %rax, (%r14)
    mov     %r12, %rdi
    call    node_drop_stream
    LEAVE 64
END_FUNCTION node_respond

/*
 * The request of the stream entry rdi, when its bytes are all there: Status, Ping and MetaData
 * get their answer, Goodbye a close; other methods get ResourceUnavailable. r12 entry, r13
 * method, S7 the seventh argument of a call, S8 the scratch size, S9 the payload, S10 a peer.
 * Locals: L a ChunkHeader, L+48 consumed or an epoch, L+56 a length or a fork digest, L+64 eof
 * or a payload (96), L+160 the request's size.
 */
LOCAL_FUNCTION node_request
    ENTER 176
    mov     %rdi, %r12
    cmpq    $NODE_STREAM_EOF, NodeStream_state(%r12)        # a request already answered: nothing
    ja      99f
    mov     NodeStream_method(%r12), %r13
    cmp     $REQRESP_METADATA, %r13         # MetaData: no request bytes
    je      50f
    mov     NodeStream_version(%r12), %rax  # the SSZ size of the request
    movq    $84, (L + 160)(%rsp)
    cmp     $REQRESP_STATUS, %r13
    jne     1f
    cmp     $2, %rax
    jb      3f
    movq    $92, (L + 160)(%rsp)
    jmp     3f
1:  movq    $8, (L + 160)(%rsp)
    cmp     $REQRESP_GOODBYE, %r13
    je      3f
    cmp     $REQRESP_PING, %r13
    je      3f
    movq    $24, (L + 160)(%rsp)
    cmp     $REQRESP_BEACON_BLOCKS_BY_RANGE, %r13
    je      3f
    movq    $0, (L + 160)(%rsp)             # by root: a multiple of 32 bytes, at most the request limit
    cmp     $REQRESP_BEACON_BLOCKS_BY_ROOT, %r13
    je      3f
    movq    $16, (L + 160)(%rsp)            # blob sidecars, from deneb on: by range 16 bytes, by root a multiple of 40
    cmp     $REQRESP_BLOB_SIDECARS_BY_RANGE, %r13
    je      2f
    movq    $0, (L + 160)(%rsp)
    cmp     $REQRESP_BLOB_SIDECARS_BY_ROOT, %r13
    je      2f
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE, %r13    # column sidecars, from fulu on: sizes below
    je      21f
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT, %r13
    jne     92f
21: mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_FULU, %rax
    jae     3f
    jmp     92f
2:  mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_DENEB, %rax
    jae     3f
92: mov     $3, %esi                        # ResourceUnavailable
    jmp     91f
3:  movq    $0, (L + ChunkHeader_kind)(%rsp)        # CHUNK_REQUEST
    movq    $0, (L + ChunkHeader_context_length)(%rsp)
    lea     NodeStream_list(%r12), %rdi
    lea     L(%rsp), %rsi
    call    lantern_reqresp_read_header
    cmp     $LANTERN_REQRESP_MORE, %rax
    je      80f
    test    %rax, %rax
    jnz     90f
    cmpq    $0, (L + 160)(%rsp)
    jne     4f
    cmp     $REQRESP_BLOB_SIDECARS_BY_ROOT, %r13
    je      5f
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE, %r13
    je      81f
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT, %r13
    je      82f
    testq   $31, (L + ChunkHeader_length)(%rsp)     # by root
    jnz     90f
    call    node_max_blocks
    shl     $5, %rax
    mov     (L + ChunkHeader_length)(%rsp), %rcx
    cmp     %rax, %rcx
    ja      90f
    mov     %rcx, (L + 160)(%rsp)
    jmp     4f
5:  mov     (L + ChunkHeader_length)(%rsp), %rax    # blob identifiers
    xor     %edx, %edx
    mov     $40, %ecx
    div     %rcx
    test    %rdx, %rdx
    jnz     90f
    mov     %rax, (L + 72)(%rsp)
    call    node_max_blobs
    cmp     %rax, (L + 72)(%rsp)
    ja      90f
    mov     (L + ChunkHeader_length)(%rsp), %rax
    mov     %rax, (L + 160)(%rsp)
    jmp     4f
81: mov     (L + ChunkHeader_length)(%rsp), %rax    # column sidecars by range: 20 bytes, then 8 for each column
    sub     $20, %rax
    jb      90f
    test    $7, %al
    jnz     90f
    cmp     $(8 * NUMBER_OF_COLUMNS), %rax
    ja      90f
    add     $20, %rax
    mov     %rax, (L + 160)(%rsp)
    jmp     4f
82: mov     (L + ChunkHeader_length)(%rsp), %rax    # by root: at most that many identifiers
    MOVQ    %rcx, 4 * REQUEST_BLOCKS_LIMIT_DENEB + REQUEST_BLOCKS_LIMIT_DENEB * (36 + 8 * NUMBER_OF_COLUMNS)
    cmp     %rcx, %rax
    ja      90f
    mov     %rax, (L + 160)(%rsp)
4:  mov     (L + ChunkHeader_length)(%rsp), %rax
    cmp     (L + 160)(%rsp), %rax
    jne     90f
    mov     (%r14), %rax                    # the payload's ByteList at the end of scratch
    mov     %rax, S8(%rsp)
    mov     (L + 160)(%rsp), %rdx
    add     $(24 + 7), %rdx
    and     $-8, %rdx
    sub     %rdx, %rax
    mov     %rax, (%r14)
    lea     (%r14,%rax), %rcx
    mov     %rcx, S9(%rsp)
    mov     %rdx, (%rcx)
    movq    $24, 8(%rcx)
    movq    $0, 16(%rcx)
    mov     (L + 160)(%rsp), %rax           # length and eof, by address
    mov     %rax, (L + 56)(%rsp)
    xor     %eax, %eax
    cmpq    $NODE_STREAM_EOF, NodeStream_state(%r12)
    sete    %al
    mov     %rax, (L + 64)(%rsp)
    lea     (L + 48)(%rsp), %rax
    mov     %rax, S7(%rsp)                  # consumed, the seventh argument
    lea     NodeStream_list(%r12), %rdi
    lea     (L + ChunkHeader_header_bytes)(%rsp), %rsi
    lea     (L + 56)(%rsp), %rdx
    lea     (L + 64)(%rsp), %rcx
    mov     %r14, %r8
    mov     S9(%rsp), %r9
    call    lantern_reqresp_read_payload
    mov     S8(%rsp), %rcx
    mov     %rcx, (%r14)
    cmp     $LANTERN_REQRESP_MORE, %rax
    je      80f
    test    %rax, %rax
    jnz     90f
    addq    $24, S9(%rsp)                   # the SSZ bytes
    cmp     $REQRESP_BEACON_BLOCKS_BY_RANGE, %r13
    je      60f
    cmp     $REQRESP_BEACON_BLOCKS_BY_ROOT, %r13
    je      70f
    cmp     $REQRESP_BLOB_SIDECARS_BY_RANGE, %r13
    je      65f
    cmp     $REQRESP_BLOB_SIDECARS_BY_ROOT, %r13
    je      75f
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE, %r13
    je      83f
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT, %r13
    je      86f
    cmp     $REQRESP_GOODBYE, %r13
    jne     10f
    mov     $LIBP2P_EVENT_STREAM_CLOSE, %edi        # Goodbye: a close
    mov     NodeStream_handle(%r12), %rsi
    call    node_out_handle
    mov     %r12, %rdi
    call    node_drop_stream
    LEAVE 176
10: cmp     $REQRESP_PING, %r13
    jne     20f
    mov     Node_metadata_seq(%rbx), %rax   # Ping: our seq_number
    mov     %rax, (L + 64)(%rsp)
    mov     %r12, %rdi
    xor     %esi, %esi
    lea     (L + 64)(%rsp), %rdx
    mov     $8, %ecx
    call    node_respond
    LEAVE 176
20: mov     NodeStream_peer(%r12), %rdi     # Status: the peer's, then ours
    mov     S9(%rsp), %rsi
    mov     (L + 160)(%rsp), %rdx
    call    node_peer_status
    lea     (L + 64)(%rsp), %rdi
    call    node_status_bytes
    mov     %r12, %rdi
    xor     %esi, %esi
    lea     (L + 64)(%rsp), %rdx
    mov     (L + 160)(%rsp), %rcx
    call    node_respond
    LEAVE 176
50: lea     (L + 64)(%rsp), %rdi            # MetaData: seq_number, attnets, syncnets, custody_group_count
    mov     $32, %esi
    call    lantern_zero
    mov     Node_metadata_seq(%rbx), %rax
    mov     %rax, (L + 64)(%rsp)
    mov     (Node_config + CONFIG_CUSTODY_REQUIREMENT)(%rbx), %rax
    mov     %rax, (L + 56)(%rsp)
    lea     (L + 64 + 17)(%rsp), %rdi
    lea     (L + 56)(%rsp), %rsi
    mov     $8, %edx
    call    lantern_copy
    mov     NodeStream_version(%r12), %rax
    mov     $16, %ecx
    cmp     $2, %rax
    jb      51f
    mov     $17, %ecx
    je      51f
    mov     $25, %ecx
51: mov     %r12, %rdi
    xor     %esi, %esi
    lea     (L + 64)(%rsp), %rdx
    call    node_respond
    LEAVE 176
60: mov     S9(%rsp), %rax                  # BlocksByRange: start_slot, count
    mov     (%rax), %r13
    mov     8(%rax), %rcx
    mov     %rcx, S10(%rsp)
    cmp     Node_earliest_slot(%rbx), %r13
    jb      92b
    call    node_max_blocks                 # at most the limit, and the room of the list
    mov     S10(%rsp), %rcx
    cmp     %rax, %rcx
    cmova   %rax, %rcx
    add     %r13, %rcx                      # the end slot
    mov     $-1, %rax
    cmovc   %rax, %rcx
    mov     %rcx, S10(%rsp)
    movq    $0, (L + 160)(%rsp)             # the canonical blocks of the range, from the head down
    lea     Node_head_root(%rbx), %rax
    mov     %rax, S9(%rsp)
61: mov     S9(%rsp), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      63f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     63f
    mov     NodeBlock_slot(%rdx), %rax
    cmp     %r13, %rax
    jb      63f
    lea     NodeBlock_parent_root(%rdx), %rcx
    mov     %rcx, S9(%rsp)
    cmp     S10(%rsp), %rax
    jae     61b
    mov     NodeBlock_data_id(%rdx), %rax
    test    %rax, %rax
    jz      61b
    mov     (L + 160)(%rsp), %rcx
    mov     %rax, NodeStream_request(%r12,%rcx,8)
    incq    (L + 160)(%rsp)
    jmp     61b
63: lea     NodeStream_request(%r12), %rdi  # in slot order
    mov     (L + 160)(%rsp), %rcx
    lea     -8(%rdi,%rcx,8), %rsi
64: cmp     %rsi, %rdi
    jae     77f
    mov     (%rdi), %rax
    mov     (%rsi), %rdx
    mov     %rdx, (%rdi)
    mov     %rax, (%rsi)
    add     $8, %rdi
    sub     $8, %rsi
    jmp     64b
65: mov     S9(%rsp), %rax                  # BlobSidecarsByRange: start_slot, count
    mov     (%rax), %r13
    mov     8(%rax), %rcx
    mov     %rcx, S10(%rsp)
    cmp     Node_earliest_slot(%rbx), %r13
    jb      92b
    mov     (Node_config + CONFIG_MAX_BLOBS_PER_BLOCK)(%rbx), %rax     # the indices of a block
    mov     (Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA)(%rbx), %rcx
    cmp     %rcx, %rax
    cmovb   %rcx, %rax
    mov     $NODE_BLOB_MAX, %ecx
    cmp     %rcx, %rax
    cmova   %rcx, %rax
    test    %rax, %rax
    jz      78f
    mov     %rax, (L + 72)(%rsp)
    call    node_max_blobs                  # at most the limit: the slots whose sidecars it can hold
    xor     %edx, %edx
    divq    (L + 72)(%rsp)
    mov     S10(%rsp), %rcx
    cmp     %rax, %rcx
    cmova   %rax, %rcx
    add     %r13, %rcx                      # the end slot
    mov     $-1, %rax
    cmovc   %rax, %rcx
    mov     %rcx, S10(%rsp)
    movq    $0, (L + 160)(%rsp)             # the sidecars of the canonical blocks of the range, from the head down
    lea     Node_head_root(%rbx), %rax
    mov     %rax, S9(%rsp)
66: mov     S9(%rsp), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      63b
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     63b
    mov     NodeBlock_slot(%rdx), %rax
    cmp     %r13, %rax
    jb      63b
    lea     NodeBlock_parent_root(%rdx), %rcx
    mov     %rcx, S9(%rsp)
    cmp     S10(%rsp), %rax
    jae     66b
    mov     %rdx, (L + 64)(%rsp)            # its indices, from the last, of a block of deneb or electra
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_DENEB, %rax
    je      661f
    cmp     $FORK_ELECTRA, %rax
    jne     66b
661: mov    (L + 72)(%rsp), %rax
    mov     %rax, (L + 80)(%rsp)
67: mov     (L + 80)(%rsp), %rsi
    test    %rsi, %rsi
    jz      66b
    dec     %rsi
    mov     %rsi, (L + 80)(%rsp)
    mov     (L + 64)(%rsp), %rdi
    call    node_blob_held
    test    %rax, %rax
    jz      67b
    mov     NodeBlob_data_id(%rax), %rax
    mov     (L + 160)(%rsp), %rcx
    mov     %rax, NodeStream_request(%r12,%rcx,8)
    incq    (L + 160)(%rsp)
    jmp     67b
75: mov     (L + 160)(%rsp), %rax           # BlobSidecarsByRoot: the sidecars the node holds, in the request's order
    xor     %edx, %edx
    mov     $40, %ecx
    div     %rcx
    mov     %rax, (L + 160)(%rsp)
    movq    $0, S10(%rsp)
76: cmpq    $0, (L + 160)(%rsp)
    je      72f
    mov     S9(%rsp), %rdi
    mov     32(%rdi), %rsi
    addq    $40, S9(%rsp)
    decq    (L + 160)(%rsp)
    call    node_blob_held
    test    %rax, %rax
    jz      76b
    mov     NodeBlob_data_id(%rax), %rcx
    mov     %rcx, (L + 64)(%rsp)
    mov     %rax, (L + 72)(%rsp)
    mov     NodeBlob_slot(%rax), %rdi       # a sidecar of deneb or electra
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_DENEB, %rax
    je      761f
    cmp     $FORK_ELECTRA, %rax
    jne     76b
761: mov    (L + 72)(%rsp), %rdi
    call    node_find_block                 # not of an invalid block
    cmp     $-1, %rax
    je      74f
    cmpq    $NODE_BLOCK_INVALID, NodeBlock_status(%rdx)
    je      76b
74: mov     (L + 64)(%rsp), %rax
    mov     S10(%rsp), %rcx
    mov     %rax, NodeStream_request(%r12,%rcx,8)
    incq    S10(%rsp)
    jmp     76b
70: shrq    $5, (L + 160)(%rsp)             # BlocksByRoot: the blocks the node has, in the request's order
    movq    $0, S10(%rsp)
71: cmpq    $0, (L + 160)(%rsp)
    je      72f
    mov     S9(%rsp), %rdi
    call    node_find_block
    addq    $32, S9(%rsp)
    decq    (L + 160)(%rsp)
    cmp     $-1, %rax
    je      71b
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     71b
    mov     NodeBlock_data_id(%rdx), %rax
    test    %rax, %rax
    jz      71b
    mov     S10(%rsp), %rcx
    mov     %rax, NodeStream_request(%r12,%rcx,8)
    incq    S10(%rsp)
    jmp     71b
72: mov     S10(%rsp), %rax
    mov     %rax, (L + 160)(%rsp)
77: mov     (L + 160)(%rsp), %rax           # the list, then a SERVE work for each block in turn
    test    %rax, %rax
    jz      78f
    shl     $3, %rax
    mov     %rax, (NodeStream_list + 16)(%r12)
    movq    $0, NodeStream_next(%r12)
    movq    $NODE_STREAM_SERVE, NodeStream_state(%r12)
    LEAVE 176
78: mov     $LIBP2P_EVENT_STREAM_CLOSE, %edi        # no block: an empty answer
    mov     NodeStream_handle(%r12), %rsi
    call    node_out_handle
    mov     %r12, %rdi
    call    node_drop_stream
    LEAVE 176
83: mov     S9(%rsp), %rsi                  # DataColumnSidecarsByRange: the offset 20, then the columns
    cmpl    $20, 16(%rsi)
    jne     90f
    movq    $0, (L + 80)(%rsp)              # the columns asked, then of those the ones sampled
    movq    $0, (L + 88)(%rsp)
    mov     (L + 160)(%rsp), %rcx
    sub     $20, %rcx
    shr     $3, %rcx
    lea     20(%rsi), %rdx
84: test    %rcx, %rcx
    jz      841f
    mov     (%rdx), %rax
    add     $8, %rdx
    cmp     $NUMBER_OF_COLUMNS, %rax
    jae     90f
    mov     %rax, %rdi
    shr     $6, %rdi
    mov     (L + 80)(%rsp,%rdi,8), %r8
    bts     %rax, %r8
    mov     %r8, (L + 80)(%rsp,%rdi,8)
    dec     %rcx
    jmp     84b
841: mov    Node_columns(%rbx), %rax
    and     %rax, (L + 80)(%rsp)
    mov     (Node_columns + 8)(%rbx), %rax
    and     %rax, (L + 88)(%rsp)
    xor     %ecx, %ecx                      # their count: the sidecars of a block
    mov     (L + 80)(%rsp), %rax
842: test   %rax, %rax
    jz      843f
    lea     -1(%rax), %rdx
    and     %rdx, %rax
    inc     %rcx
    jmp     842b
843: mov    (L + 88)(%rsp), %rax
844: test   %rax, %rax
    jz      845f
    lea     -1(%rax), %rdx
    and     %rdx, %rax
    inc     %rcx
    jmp     844b
845: test   %rcx, %rcx
    jz      78b
    mov     %rcx, (L + 72)(%rsp)
    mov     S9(%rsp), %rax                  # start_slot, count
    mov     (%rax), %r13
    mov     8(%rax), %rcx
    mov     %rcx, S10(%rsp)
    cmp     Node_earliest_slot(%rbx), %r13
    jb      92b
    call    node_max_columns                # at most the limit: the slots whose sidecars it can hold
    xor     %edx, %edx
    divq    (L + 72)(%rsp)
    mov     S10(%rsp), %rcx
    cmp     %rax, %rcx
    cmova   %rax, %rcx
    add     %r13, %rcx                      # the end slot
    mov     $-1, %rax
    cmovc   %rax, %rcx
    mov     %rcx, S10(%rsp)
    movq    $0, (L + 160)(%rsp)             # the sidecars of the canonical blocks of the range, from the head down
    lea     Node_head_root(%rbx), %rax
    mov     %rax, S9(%rsp)
85: mov     S9(%rsp), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      63b
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     63b
    mov     NodeBlock_slot(%rdx), %rax
    cmp     %r13, %rax
    jb      63b
    lea     NodeBlock_parent_root(%rdx), %rcx
    mov     %rcx, S9(%rsp)
    cmp     S10(%rsp), %rax
    jae     85b
    mov     %rdx, (L + 64)(%rsp)            # its columns, from the last, of a block of fulu or later
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_FULU, %rax
    jb      85b
    movq    $128, (L + 96)(%rsp)
851: mov    (L + 96)(%rsp), %rsi
    test    %rsi, %rsi
    jz      85b
    dec     %rsi
    mov     %rsi, (L + 96)(%rsp)
    mov     %rsi, %rax
    shr     $6, %rax
    mov     (L + 80)(%rsp,%rax,8), %rax
    bt      %rsi, %rax
    jnc     851b
    mov     (L + 64)(%rsp), %rdi
    call    node_blob_held
    test    %rax, %rax
    jz      851b
    mov     NodeBlob_data_id(%rax), %rax
    mov     (L + 160)(%rsp), %rcx
    mov     %rax, NodeStream_request(%r12,%rcx,8)
    incq    (L + 160)(%rsp)
    jmp     851b
86: mov     (L + 160)(%rsp), %rcx           # DataColumnSidecarsByRoot: the identifiers' offsets, then each
    test    %rcx, %rcx
    jz      78b
    mov     %rcx, S10(%rsp)
    mov     S9(%rsp), %rsi
    mov     (%rsi), %eax
    test    $3, %al
    jnz     90f
    cmp     %rcx, %rax
    ja      90f
    shr     $2, %rax
    jz      90f
    cmp     $REQUEST_BLOCKS_LIMIT_DENEB, %rax
    ja      90f
    mov     %rax, %r13
    xor     %r8d, %r8d                      # first check each identifier, and count the columns
    xor     %edi, %edi
87: cmp     %r13, %rdi
    jae     871f
    mov     (%rsi,%rdi,4), %eax
    lea     1(%rdi), %r9
    mov     %rcx, %rdx
    cmp     %r13, %r9
    jae     872f
    mov     (%rsi,%r9,4), %edx
872: cmp    %rax, %rdx
    jb      90f
    cmp     %rcx, %rdx
    ja      90f
    sub     %rax, %rdx                      # block_root, the offset 36, 8 bytes for each column
    sub     $36, %rdx
    jb      90f
    test    $7, %dl
    jnz     90f
    lea     (%rsi,%rax), %r10
    cmpl    $36, 32(%r10)
    jne     90f
    shr     $3, %rdx
    cmp     $NUMBER_OF_COLUMNS, %rdx
    ja      90f
    add     %rdx, %r8
    add     $36, %r10
873: test   %rdx, %rdx
    jz      874f
    cmpq    $NUMBER_OF_COLUMNS, (%r10)
    jae     90f
    add     $8, %r10
    dec     %rdx
    jmp     873b
874: mov    %r9, %rdi
    jmp     87b
871: mov    %r8, (L + 72)(%rsp)
    call    node_max_columns                # at most the limit of columns in all
    cmp     %rax, (L + 72)(%rsp)
    ja      90f
    movq    $0, (L + 160)(%rsp)             # then the sidecars the node holds, in the request's order
    movq    $0, (L + 96)(%rsp)
88: mov     (L + 96)(%rsp), %rdi
    cmp     %r13, %rdi
    jae     77b
    mov     S9(%rsp), %rsi
    mov     (%rsi,%rdi,4), %eax
    inc     %rdi
    mov     %rdi, (L + 96)(%rsp)
    mov     S10(%rsp), %rdx
    cmp     %r13, %rdi
    jae     881f
    mov     (%rsi,%rdi,4), %edx
881: lea    (%rsi,%rax), %r8
    mov     %r8, (L + 64)(%rsp)
    sub     %rax, %rdx
    sub     $36, %rdx
    shr     $3, %rdx
    mov     %rdx, (L + 112)(%rsp)
    add     $36, %r8
    mov     %r8, (L + 104)(%rsp)
89: mov     (L + 112)(%rsp), %rdx
    test    %rdx, %rdx
    jz      88b
    dec     %rdx
    mov     %rdx, (L + 112)(%rsp)
    mov     (L + 104)(%rsp), %r8
    mov     (%r8), %rsi
    add     $8, %r8
    mov     %r8, (L + 104)(%rsp)
    mov     (L + 64)(%rsp), %rdi
    call    node_blob_held
    test    %rax, %rax
    jz      89b
    mov     %rax, (L + 120)(%rsp)
    mov     NodeBlob_slot(%rax), %rdi       # a sidecar of fulu or later
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_FULU, %rax
    jb      89b
    mov     (L + 64)(%rsp), %rdi            # not of an invalid block
    call    node_find_block
    cmp     $-1, %rax
    je      891f
    cmpq    $NODE_BLOCK_INVALID, NodeBlock_status(%rdx)
    je      89b
891: mov    (L + 120)(%rsp), %rax
    mov     NodeBlob_data_id(%rax), %rax
    mov     (L + 160)(%rsp), %rcx
    mov     %rax, NodeStream_request(%r12,%rcx,8)
    incq    (L + 160)(%rsp)
    jmp     89b
80: cmpq    $NODE_STREAM_EOF, NodeStream_state(%r12)        # more bytes come, unless the peer closed
    je      90f
    LEAVE 176
90: mov     $1, %esi                        # InvalidRequest
91: mov     %r12, %rdi
    mov     %rsp, %rdx
    xor     %ecx, %ecx
    call    node_respond
99: LEAVE 176
END_FUNCTION node_request

/*
 * rax = the blocks one request may name: MAX_REQUEST_BLOCKS_DENEB from deneb on, else
 * MAX_REQUEST_BLOCKS, of the fork of the store's slot; at most the BufferIds a stream's list
 * holds. Uses rcx, rdx, rdi, rsi.
 */
LOCAL_FUNCTION node_max_blocks
    FRAME 0
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     $REQUEST_BLOCKS_LIMIT, %ecx
    mov     $REQUEST_BLOCKS_LIMIT_DENEB, %edx
    cmp     $FORK_DENEB, %rax
    cmovae  %rdx, %rcx
    mov     Node_stream_bytes(%rbx), %rax
    sub     $NodeStream__fixed, %rax
    shr     $3, %rax
    cmp     %rax, %rcx
    cmovb   %rcx, %rax
    UNFRAME 0
END_FUNCTION node_max_blocks

/*
 * rax = the blob sidecars one response may hold: MAX_REQUEST_BLOCKS_DENEB times
 * MAX_BLOBS_PER_BLOCK (deneb) or MAX_BLOBS_PER_BLOCK_ELECTRA (electra and later) of the fork of
 * the store's slot; at most the BufferIds a stream's list holds. Uses rcx, rdx, rsi, rdi.
 */
LOCAL_FUNCTION node_max_blobs
    FRAME 0
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     (Node_config + CONFIG_MAX_BLOBS_PER_BLOCK)(%rbx), %rcx
    cmp     $FORK_ELECTRA, %rax
    jb      1f
    mov     (Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA)(%rbx), %rcx
1:  mov     $REQUEST_BLOCKS_LIMIT_DENEB, %eax
    mul     %rcx
    jnc     2f
    mov     $-1, %rax
2:  mov     Node_stream_bytes(%rbx), %rcx
    sub     $NodeStream__fixed, %rcx
    shr     $3, %rcx
    cmp     %rcx, %rax
    cmova   %rcx, %rax
    UNFRAME 0
END_FUNCTION node_max_blobs

/*
 * rax = the column sidecars one response may hold: compute_max_request_data_column_sidecars,
 * MAX_REQUEST_BLOCKS_DENEB times NUMBER_OF_COLUMNS; at most the BufferIds a stream's list holds.
 * A leaf; uses rcx.
 */
LOCAL_FUNCTION node_max_columns
    UNWIND_END_PROLOGUE
    MOVQ    %rax, REQUEST_BLOCKS_LIMIT_DENEB * NUMBER_OF_COLUMNS
    mov     Node_stream_bytes(%rbx), %rcx
    sub     $NodeStream__fixed, %rcx
    shr     $3, %rcx
    cmp     %rcx, %rax
    cmova   %rcx, %rax
    ret
END_FUNCTION node_max_columns

/*
 * rax = 1 when a stream waits for room for its SERVE work, else 0: a SERVE work of the next
 * block of each stream in NODE_STREAM_SERVE, while the actions have room for it and 4096 bytes.
 * r12 a stream, r13 the streams left.
 */
LOCAL_FUNCTION node_serve
    ENTER 0
    PART    %r12, %r13, %rbx, Node_streams
1:  test    %r13, %r13
    jz      8f
    cmpq    $NODE_STREAM_SERVE, NodeStream_state(%r12)
    jne     2f
    mov     (%r15), %rax
    sub     8(%r15), %rax
    sub     16(%r15), %rax
    cmp     $(NODE_ACT_WORK_SIZE + 4096), %rax
    jb      9f
    movq    $NODE_STREAM_SERVING, NodeStream_state(%r12)
    mov     NodeStream_next(%r12), %rax
    mov     NodeStream_request(%r12,%rax,8), %rcx
    mov     $NODE_WORK_SERVE, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     NodeStream_handle(%r12), %r8
    mov     NodeStream_method(%r12), %r9    # arg: the version + 256 * the method
    shl     $8, %r9
    add     NodeStream_version(%r12), %r9
    call    node_work
2:  add     Node_stream_bytes(%rbx), %r12
    dec     %r13
    jmp     1b
8:  xor     %eax, %eax
    LEAVE 0
9:  mov     $1, %eax
    LEAVE 0
END_FUNCTION node_serve

/* ------------------------------------------------------------ gossip */

/* rax = the index of the message of libp2p handle rdi, or 2^64 - 1; rdx = its entry. Uses rcx. */
LOCAL_FUNCTION node_find_message
    UNWIND_END_PROLOGUE
    PART    %rdx, %rcx, %rbx, Node_messages
    xor     %eax, %eax
1:  cmp     %rcx, %rax
    jae     2f
    cmp     NodeMessage_handle(%rdx), %rdi
    je      3f
    add     $NodeMessage__mem, %rdx
    inc     %rax
    jmp     1b
2:  mov     $-1, %rax
3:  ret
END_FUNCTION node_find_message

/* Removes the message entry rdi: the last entry takes its place. */
LOCAL_FUNCTION node_drop_message
    FRAME 0
    PART    %rax, %rcx, %rbx, Node_messages
    dec     %rcx
    mov     %rcx, (Node_messages + 8)(%rbx)
    imul    $NodeMessage__mem, %rcx, %rcx
    lea     (%rax,%rcx), %rsi
    cmp     %rdi, %rsi
    je      1f
    mov     $NodeMessage__mem, %edx
    call    lantern_copy
1:  UNFRAME 0
END_FUNCTION node_drop_message

/* rax = 1 when the actions have room for rdi bytes and 4096 more, else 0. Uses rcx. */
LOCAL_FUNCTION node_room
    UNWIND_END_PROLOGUE
    mov     (%r15), %rcx
    sub     8(%r15), %rcx
    sub     16(%r15), %rcx
    lea     4096(%rdi), %rax
    cmp     %rax, %rcx
    setae   %al
    movzx   %al, %eax
    ret
END_FUNCTION node_room

/* A VALIDATION of the libp2p message handle rdi with the result rsi. */
LOCAL_FUNCTION node_validation
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     $LIBP2P_EV_VALIDATION_SIZE, %edi
    call    node_out
    test    %rax, %rax
    jz      1f
    movq    $LIBP2P_EVENT_VALIDATION, 8(%rax)
    mov     (%rsp), %rcx
    mov     %rcx, 16(%rax)
    mov     8(%rsp), %rcx
    mov     %rcx, 24(%rax)
1:  UNFRAME 16
END_FUNCTION node_validation

/* The gossip topic rdi with the subnet rsi at the node's ForkDigest: a SUBSCRIBE event. r12 the topic's length. Locals: L a GossipTopic, L+24 a ByteList of the topic. */
LOCAL_FUNCTION node_sub
    ENTER 176
    mov     Node_fork_digest(%rbx), %rax
    mov     %rax, (L + GossipTopic_fork_digest)(%rsp)
    mov     %rdi, (L + GossipTopic_name)(%rsp)
    mov     %rsi, (L + GossipTopic_subnet_id)(%rsp)
    movq    $(24 + 128), (L + 24)(%rsp)
    movq    $24, (L + 32)(%rsp)
    movq    $0, (L + 40)(%rsp)
    lea     L(%rsp), %rdi
    lea     (L + 24)(%rsp), %rsi
    call    lantern_gossip_topic
    test    %rax, %rax
    jnz     9f
    mov     (L + 40)(%rsp), %r12
    lea     (24 + 7)(%r12), %rdi
    and     $-8, %rdi
    call    node_out
    test    %rax, %rax
    jz      9f
    movq    $LIBP2P_EVENT_SUBSCRIBE, 8(%rax)
    mov     %r12, 16(%rax)
    lea     24(%rax), %rdi
    lea     (L + 48)(%rsp), %rsi
    mov     %r12, %rdx
    call    lantern_copy
9:  LEAVE 176
END_FUNCTION node_sub

/*
 * The node's Status at rdi (92 bytes: v2; v1 is its first 84): compute_fork_digest of the store's
 * epoch, the store's finalized checkpoint, head_root and its slot, and earliest_slot. r12 out.
 * Locals: L an epoch, L+8 a ForkDigest, L+16 a slot.
 */
LOCAL_FUNCTION node_status_bytes
    ENTER 32
    mov     %rdi, %r12
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, L(%rsp)
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     L(%rsp), %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, L(%rsp)
    movq    $0, (L + 8)(%rsp)
    lea     Node_genesis_validators_root(%rbx), %rdi
    lea     L(%rsp), %rsi
    lea     Node_config(%rbx), %rdx
    mov     %r14, %rcx
    lea     (L + 8)(%rsp), %r8
    FORK_CALL compute_fork_digest
    mov     %r12, %rdi                      # fork_digest
    lea     (L + 8)(%rsp), %rsi
    mov     $4, %edx
    call    lantern_copy
    lea     4(%r12), %rdi                   # finalized_root, finalized_epoch
    lea     (Store_finalized_checkpoint + 8)(%rbp), %rsi
    mov     $32, %edx
    call    lantern_copy
    lea     36(%r12), %rdi
    lea     Store_finalized_checkpoint(%rbp), %rsi
    mov     $8, %edx
    call    lantern_copy
    cmpq    $0, Store_finalized_checkpoint(%rbp)    # the genesis finalized checkpoint: a zero root
    jne     2f
    lea     4(%r12), %rdi
    mov     $32, %esi
    call    lantern_zero
2:  lea     44(%r12), %rdi                  # head_root, head_slot
    lea     Node_head_root(%rbx), %rsi
    mov     $32, %edx
    call    lantern_copy
    lea     Node_head_root(%rbx), %rdi
    call    node_find_block
    xor     %ecx, %ecx
    cmp     $-1, %rax
    je      1f
    mov     NodeBlock_slot(%rdx), %rcx
1:  mov     %rcx, (L + 16)(%rsp)
    lea     76(%r12), %rdi
    lea     (L + 16)(%rsp), %rsi
    mov     $8, %edx
    call    lantern_copy
    lea     84(%r12), %rdi                  # earliest_available_slot: Status v2
    lea     Node_earliest_slot(%rbx), %rsi
    mov     $8, %edx
    call    lantern_copy
    LEAVE 32
END_FUNCTION node_status_bytes

/*
 * With NODE_FLAG_DISCV5, the node's record entries for the epoch at rdi of the fork rsi: a
 * NODE_ACT_DISCV5 of SET_ENTRY events: eth2, attnets, from altair syncnets, from fulu cgc and nfd.
 * r12 the fork, r13 the action, S7 the next event. Locals: L the epoch.
 */
.set NODE_ENR_ACTION, 48 + 64 + 56 * 4
LOCAL_FUNCTION node_enr_entries
    ENTER 16
    testq   $NODE_FLAG_DISCV5, Node_flags(%rbx)
    jz      9f
    mov     (%rdi), %rax
    mov     %rax, L(%rsp)
    mov     %rsi, %r12
    mov     $NODE_ACT_DISCV5, %edi
    mov     $NODE_ENR_ACTION, %esi
    call    node_act
    mov     %rax, %r13
    movq    $0, 16(%r13)
    movq    $(NODE_ENR_ACTION - 24), 24(%r13)
    movq    $24, 32(%r13)
    lea     48(%r13), %rax
    mov     %rax, S7(%rsp)
    movq    $64, (%rax)                     # eth2: the ENRForkID of the epoch
    movq    $DISCV5_EVENT_SET_ENTRY, 8(%rax)
    movq    $4, 16(%rax)
    movq    $0x32687465, 24(%rax)
    movq    $0, 32(%rax)
    movq    $16, 40(%rax)
    lea     Node_genesis_validators_root(%rbx), %rdi
    lea     L(%rsp), %rsi
    lea     Node_config(%rbx), %rdx
    mov     %r14, %rcx
    lea     48(%rax), %r8
    mov     %r12, %r10
    FORK_CALL compute_enr_fork_id
    mov     S7(%rsp), %rax
    add     $64, %rax
    movq    $56, (%rax)                     # attnets: no subnet
    movq    $DISCV5_EVENT_SET_ENTRY, 8(%rax)
    movq    $7, 16(%rax)
    movabs  $0x007374656e747461, %rcx
    mov     %rcx, 24(%rax)
    movq    $0, 32(%rax)
    movq    $8, 40(%rax)
    movq    $0, 48(%rax)
    add     $56, %rax
    mov     %rax, S7(%rsp)
    cmp     $FORK_ALTAIR, %r12
    jb      8f
    movq    $56, (%rax)                     # syncnets: no subnet
    movq    $DISCV5_EVENT_SET_ENTRY, 8(%rax)
    movq    $8, 16(%rax)
    movabs  $0x7374656e636e7973, %rcx
    mov     %rcx, 24(%rax)
    movq    $0, 32(%rax)
    movq    $1, 40(%rax)
    movq    $0, 48(%rax)
    add     $56, %rax
    mov     %rax, S7(%rsp)
    cmp     $FORK_FULU, %r12
    jb      8f
    movq    $56, (%rax)                     # cgc: CUSTODY_REQUIREMENT, big-endian, no leading zero byte
    movq    $DISCV5_EVENT_SET_ENTRY, 8(%rax)
    movq    $3, 16(%rax)
    movq    $0x636763, 24(%rax)
    movq    $0, 32(%rax)
    movq    $0, 48(%rax)
    mov     (Node_config + CONFIG_CUSTODY_REQUIREMENT)(%rbx), %rdx
    xor     %ecx, %ecx                      # n bytes: 8 - its leading zero bytes
    mov     %rdx, %rsi
1:  test    %rsi, %rsi
    jz      2f
    inc     %rcx
    shr     $8, %rsi
    jmp     1b
2:  mov     %rcx, 40(%rax)
    test    %rcx, %rcx
    jz      3f
    bswap   %rdx                            # big-endian; its last n bytes move to the front
    neg     %rcx
    add     $8, %rcx
    shl     $3, %rcx
    shr     %cl, %rdx
    mov     %rdx, 48(%rax)
3:  add     $56, %rax
    mov     %rax, S7(%rsp)
    movq    $56, (%rax)                     # nfd: the next fork digest
    movq    $DISCV5_EVENT_SET_ENTRY, 8(%rax)
    movq    $3, 16(%rax)
    movq    $0x64666e, 24(%rax)
    movq    $0, 32(%rax)
    movq    $4, 40(%rax)
    movq    $0, 48(%rax)
    lea     Node_genesis_validators_root(%rbx), %rdi
    lea     L(%rsp), %rsi
    lea     Node_config(%rbx), %rdx
    mov     %r14, %rcx
    lea     48(%rax), %r8
    CALL_GLOBAL lantern_fulu_compute_next_fork_digest
    addq    $56, S7(%rsp)
8:  mov     S7(%rsp), %rax                  # the events' bytes
    lea     48(%r13), %rcx
    sub     %rcx, %rax
    mov     %rax, 40(%r13)
9:  LEAVE 16
END_FUNCTION node_enr_entries

/*
 * rax = the value of the byte string pair whose key is the rcx (at most 8) bytes of rdx, little
 * end first, of the Enr rdi of the record bytes at rsi, or 0; rdx = its length. Uses rdi, r8-r11.
 */
LOCAL_FUNCTION node_enr_pair
    UNWIND_END_PROLOGUE
    mov     DISCV5_ENR_COUNT(%rdi), %r8
    lea     DISCV5_ENR_PAIRS(%rdi), %r9
1:  test    %r8, %r8
    jz      3f
    mov     DISCV5_PAIR_KEY_LEN(%r9), %eax
    cmp     %rcx, %rax
    jne     2f
    mov     DISCV5_PAIR_KEY_OFFSET(%r9), %eax
    lea     (%rsi,%rax), %r10
    xor     %r11d, %r11d                    # the key's bytes as a number
    mov     %rcx, %rdi
4:  test    %rdi, %rdi
    jz      5f
    dec     %rdi
    shl     $8, %r11
    movzbl  (%r10,%rdi), %eax
    or      %rax, %r11
    jmp     4b
5:  cmp     %rdx, %r11
    jne     2f
    cmpl    $1, DISCV5_PAIR_VALUE_KIND(%r9)
    jne     2f
    mov     DISCV5_PAIR_VALUE_OFFSET(%r9), %eax
    add     %rsi, %rax
    mov     DISCV5_PAIR_VALUE_LEN(%r9), %edx
    ret
2:  add     $DISCV5_PAIR_SIZE, %r9
    dec     %r8
    jmp     1b
3:  xor     %eax, %eax
    xor     %edx, %edx
    ret
END_FUNCTION node_enr_pair

/*
 * The node record of the NODE_EV_ENR rdi: a DIAL of its TCP address when it has an ip, a tcp pair
 * of 1 or 2 bytes, an eth2 pair of compute_fork_digest at the store's epoch, a peer ID no NodePeer
 * has, and room for a peer. r12 the record's ByteList, r13 the Enr, S7 the scratch size, restored
 * on return, S8 the port, S9 the DIAL. Locals: L the peer ID (39 bytes), L+48 the node's Status
 * (96), whose first 4 bytes are that digest.
 */
LOCAL_FUNCTION node_enr
    ENTER 144
    lea     NodeEvent_bytes(%rdi), %r12
    mov     (%r14), %rax
    mov     %rax, S7(%rsp)
    MOVQ    %rcx, DISCV5_ENR_SIZE + DISCV5_ENR_SCRATCH  # the Enr and its scratch at the end of scratch
    sub     %rcx, %rax
    jb      9f
    mov     %rax, (%r14)
    lea     (%r14,%rax), %r13
    MOVQ    %rcx, DISCV5_ENR_SCRATCH
    mov     %rcx, DISCV5_ENR_SIZE(%r13)
    mov     %r12, %rdi
    lea     DISCV5_ENR_SIZE(%r13), %rsi
    mov     %r13, %rdx
    CALL_GLOBAL discv5_enr_decode
    test    %rax, %rax
    jnz     9f
    testq   $1, DISCV5_ENR_HAS(%r13)        # an ip
    jz      9f
    mov     %r13, %rdi                      # a tcp port of 1 or 2 bytes
    mov     8(%r12), %rsi
    add     %r12, %rsi
    mov     $0x706374, %edx
    mov     $3, %ecx
    call    node_enr_pair
    test    %rax, %rax
    jz      9f
    cmp     $1, %rdx
    jb      9f
    cmp     $2, %rdx
    ja      9f
    movzbl  (%rax), %ecx
    jne     1f
    shl     $8, %ecx
    movzbl  1(%rax), %eax
    or      %eax, %ecx
1:  mov     %rcx, S8(%rsp)
    mov     %r13, %rdi                      # an eth2 of the node's fork_digest
    mov     8(%r12), %rsi
    add     %r12, %rsi
    mov     $0x32687465, %edx
    mov     $4, %ecx
    call    node_enr_pair
    test    %rax, %rax
    jz      9f
    cmp     $4, %rdx
    jb      9f
    mov     (%rax), %eax
    mov     %eax, L(%rsp)
    lea     (L + 48)(%rsp), %rdi
    call    node_status_bytes
    mov     L(%rsp), %eax
    cmp     (L + 48)(%rsp), %eax
    jne     9f
    MOVQ    %rax, 0x0000211202082500        # the peer ID: identity multihash of the protobuf secp256k1 key
    mov     %rax, L(%rsp)
    lea     (L + 6)(%rsp), %rdi
    lea     DISCV5_ENR_PUBKEY(%r13), %rsi
    mov     $33, %edx
    call    lantern_copy
    PART    %r8, %r9, %rbx, Node_peers      # not a peer of the node
2:  test    %r9, %r9
    jz      4f
    cmpq    $39, NodePeer_id_len(%r8)
    jne     3f
    xor     %ecx, %ecx
5:  cmp     $39, %rcx
    jae     9f
    movzbl  NodePeer_id(%r8,%rcx), %eax
    cmp     L(%rsp,%rcx), %al
    jne     3f
    inc     %rcx
    jmp     5b
3:  add     $NodePeer__mem, %r8
    dec     %r9
    jmp     2b
4:  mov     (Node_peers + 8)(%rbx), %rcx    # room for a peer
    add     Node_dialing(%rbx), %rcx
    mov     Node_streams(%rbx), %rax
    sub     Node_peers(%rbx), %rax
    xor     %edx, %edx
    mov     $NodePeer__mem, %r8d
    div     %r8
    cmp     %rax, %rcx
    jae     9f
    mov     $LIBP2P_EV_DIAL_SIZE, %edi      # the DIAL
    call    node_out
    test    %rax, %rax
    jz      9f
    mov     %rax, S9(%rsp)
    movq    $LIBP2P_EVENT_DIAL, 8(%rax)
    call    node_new_id
    MOVQ    %rcx, NODE_DIAL_TAG
    or      %rcx, %rax
    mov     S9(%rsp), %rdx
    mov     %rax, LIBP2P_EV_TAG(%rdx)
    movq    $4, (LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_FAMILY)(%rdx)
    mov     S8(%rsp), %rax
    mov     %rax, (LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_PORT)(%rdx)
    movq    $0, (LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_IP)(%rdx)
    movq    $0, (LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_IP + 8)(%rdx)
    mov     DISCV5_ENR_IP4(%r13), %eax
    mov     %eax, (LIBP2P_EV_DIAL_ADDR + LIBP2P_ADDR_IP)(%rdx)
    movq    $39, LIBP2P_EV_DIAL_ID_LEN(%rdx)
    lea     LIBP2P_EV_DIAL_ID(%rdx), %rdi
    mov     $48, %esi
    call    lantern_zero
    mov     S9(%rsp), %rdi
    add     $LIBP2P_EV_DIAL_ID, %rdi
    lea     L(%rsp), %rsi
    mov     $39, %edx
    call    lantern_copy
    mov     S9(%rsp), %rdx
    movq    $LIBP2P_TCP, LIBP2P_EV_DIAL_TRANSPORT(%rdx)
    movq    $0, (LIBP2P_EV_DIAL_TRANSPORT + 8)(%rdx)
    incq    Node_dialing(%rbx)
9:  mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    LEAVE 144
END_FUNCTION node_enr

/*
 * With NODE_FLAG_DISCV5 and room for more peers, a NODE_ACT_DISCV5 of a LOOKUP whose target is
 * the 32 entropy bytes of the tick rdi, when lookup_ms is 0 or NODE_LOOKUP_MS before time_ms.
 * r12 the tick, r13 the action.
 */
LOCAL_FUNCTION node_lookup
    ENTER 0
    mov     %rdi, %r12
    testq   $NODE_FLAG_DISCV5, Node_flags(%rbx)
    jz      9f
    mov     (Node_peers + 8)(%rbx), %rcx
    add     Node_dialing(%rbx), %rcx
    mov     Node_streams(%rbx), %rax
    sub     Node_peers(%rbx), %rax
    xor     %edx, %edx
    mov     $NodePeer__mem, %r8d
    div     %r8
    cmp     %rax, %rcx
    jae     9f
    mov     Node_lookup_ms(%rbx), %rax
    test    %rax, %rax
    jz      1f
    MOVQ    %rcx, NODE_LOOKUP_MS
    add     %rcx, %rax
    cmp     %rax, Node_time_ms(%rbx)
    jb      9f
1:  mov     $96, %edi                       # the action: 16, 24 a ByteList, 48 the LOOKUP
    call    node_room
    test    %rax, %rax
    jz      9f
    mov     $NODE_ACT_DISCV5, %edi
    mov     $96, %esi
    call    node_act
    mov     %rax, %r13
    movq    $0, 16(%r13)
    movq    $72, 24(%r13)
    movq    $24, 32(%r13)
    movq    $DISCV5_EV_LOOKUP_SIZE, 40(%r13)
    movq    $DISCV5_EV_LOOKUP_SIZE, 48(%r13)
    movq    $DISCV5_EVENT_LOOKUP, 56(%r13)
    lea     (48 + DISCV5_EV_LOOKUP_TARGET)(%r13), %rdi
    lea     LIBP2P_TICK_ENTROPY(%r12), %rsi
    mov     $32, %edx
    call    lantern_copy
    mov     Node_time_ms(%rbx), %rax
    cmp     $1, %rax                        # 0 becomes 1
    adc     $0, %rax
    mov     %rax, Node_lookup_ms(%rbx)
9:  LEAVE 0
END_FUNCTION node_lookup

/*
 * The gossip topics of the fork of the store's epoch, at its ForkDigest: SUBSCRIBE events, once
 * for each digest, when p2p_out has room for them. r12 the fork, r13 a subnet, S7 the subnets.
 * Locals: L an epoch, L+8 a ForkDigest.
 */
LOCAL_FUNCTION node_subscribe
    ENTER 16
    P2P_OUT %rcx
    mov     (%rcx), %rax
    sub     $24, %rax
    sub     16(%rcx), %rax
    cmp     $(64 * 128), %rax
    jb      9f
    mov     $NODE_ENR_ACTION, %edi          # and the actions room for the record entries
    call    node_room
    test    %rax, %rax
    jz      9f
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %r12
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, L(%rsp)
    mov     %r12, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r12
    mov     %rax, %r10
    movq    $0, (L + 8)(%rsp)
    lea     Node_genesis_validators_root(%rbx), %rdi
    lea     L(%rsp), %rsi
    lea     Node_config(%rbx), %rdx
    mov     %r14, %rcx
    lea     (L + 8)(%rsp), %r8
    FORK_CALL compute_fork_digest
    test    %rax, %rax
    jnz     9f
    mov     (L + 8)(%rsp), %rax
    testq   $NODE_FLAG_SUBSCRIBED, Node_flags(%rbx)
    jz      1f
    cmp     Node_fork_digest(%rbx), %rax
    je      9f
1:  mov     %rax, Node_fork_digest(%rbx)
    orq     $NODE_FLAG_SUBSCRIBED, Node_flags(%rbx)
    lea     L(%rsp), %rdi                   # the record entries of the new digest
    mov     %r12, %rsi
    call    node_enr_entries
    .irp name, GOSSIP_BEACON_BLOCK, GOSSIP_BEACON_AGGREGATE_AND_PROOF, GOSSIP_VOLUNTARY_EXIT, GOSSIP_PROPOSER_SLASHING, GOSSIP_ATTESTER_SLASHING
    mov     $\name, %edi
    xor     %esi, %esi
    call    node_sub
    .endr
    cmp     $FORK_ALTAIR, %r12
    jb      9f
    mov     $GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF, %edi
    xor     %esi, %esi
    call    node_sub
    cmp     $FORK_CAPELLA, %r12
    jb      9f
    mov     $GOSSIP_BLS_TO_EXECUTION_CHANGE, %edi
    xor     %esi, %esi
    call    node_sub
    cmp     $FORK_DENEB, %r12               # deneb and electra: every blob sidecar subnet
    jb      9f
    cmp     $FORK_FULU, %r12
    jae     4f
    mov     (Node_config + CONFIG_BLOB_SIDECAR_SUBNET_COUNT)(%rbx), %rax
    cmp     $FORK_ELECTRA, %r12
    jb      2f
    mov     (Node_config + CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA)(%rbx), %rax
2:  mov     %rax, S7(%rsp)
    xor     %r13d, %r13d
3:  cmp     S7(%rsp), %r13
    jae     9f
    mov     $GOSSIP_BLOB_SIDECAR, %edi
    mov     %r13, %rsi
    call    node_sub
    inc     %r13
    jmp     3b
4:  mov     (Node_config + CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT)(%rbx), %rax  # fulu: the subnet of each column sampled, once
    test    %rax, %rax
    jz      9f
    mov     %rax, S7(%rsp)
    movq    $0, S8(%rsp)                    # the subnets subscribed: S8 below 64, S9 from 64
    movq    $0, S9(%rsp)
    xor     %r13d, %r13d
5:  cmp     $128, %r13
    jae     9f
    mov     %r13, %rdi
    call    node_sampled
    test    %rax, %rax
    jz      7f
    mov     %r13, %rax                      # compute_subnet_for_data_column_sidecar: column % DATA_COLUMN_SIDECAR_SUBNET_COUNT
    xor     %edx, %edx
    divq    S7(%rsp)
    mov     %rdx, %rsi
    mov     %rsi, %rcx
    shr     $6, %rcx
    lea     S8(%rsp,%rcx,8), %rcx
    mov     (%rcx), %rax
    bt      %rsi, %rax
    jc      7f
    bts     %rsi, %rax
    mov     %rax, (%rcx)
    mov     $GOSSIP_DATA_COLUMN_SIDECAR, %edi
    call    node_sub
7:  inc     %r13
    jmp     5b
9:  LEAVE 16
END_FUNCTION node_subscribe

/*
 * The MESSAGE rdi of libp2p, whose data is in the libp2p state rsi: its MESSAGE_ID, then a
 * NodeMessage with its bytes, uncompressed, in a BYTES_PUT. r12 the notice, r13 the entry, S7 the
 * libp2p state, S8 the scratch size, restored on return, S9 the topic's ByteList, then the
 * bytes', S10 the data's ByteList. Locals: L a GossipTopic, L+24 the message-id, L+48 a length.
 */
LOCAL_FUNCTION node_message
    ENTER 64
    mov     %rdi, %r12
    mov     %rsi, S7(%rsp)
    mov     (%r14), %rax
    mov     %rax, S8(%rsp)
    mov     LIBP2P_ACT_MSG_TOPIC_LEN(%r12), %rcx    # the topic's and the data's ByteLists at the end of scratch
    add     $(24 + 7), %rcx
    and     $-8, %rcx
    mov     LIBP2P_ACT_MSG_DATA_LEN(%r12), %rdx
    add     $(24 + 7), %rdx
    and     $-8, %rdx
    lea     (%rcx,%rdx), %r8
    MOVQ    %r9, LANTERN_SCRATCH_FIXED
    add     %r8, %r9
    cmp     %r9, %rax
    jb      99f
    sub     %r8, %rax
    mov     %rax, (%r14)
    lea     (%r14,%rax), %rdi
    mov     %rdi, S9(%rsp)
    lea     (%rdi,%rcx), %rsi
    mov     %rsi, S10(%rsp)
    mov     %rcx, (%rdi)
    movq    $24, 8(%rdi)
    mov     LIBP2P_ACT_MSG_TOPIC_LEN(%r12), %rax
    mov     %rax, 16(%rdi)
    mov     %rdx, (%rsi)
    movq    $24, 8(%rsi)
    mov     LIBP2P_ACT_MSG_DATA_LEN(%r12), %rax
    mov     %rax, 16(%rsi)
    add     $24, %rdi
    lea     LIBP2P_ACT_MSG_TOPIC(%r12), %rsi
    mov     LIBP2P_ACT_MSG_TOPIC_LEN(%r12), %rdx
    call    lantern_copy
    mov     S10(%rsp), %rdi
    add     $24, %rdi
    mov     S7(%rsp), %rsi
    add     LIBP2P_ACT_MSG_DATA_OFF(%r12), %rsi
    mov     LIBP2P_ACT_MSG_DATA_LEN(%r12), %rdx
    call    lantern_copy
    mov     S9(%rsp), %rdi                  # the topic
    lea     L(%rsp), %rsi
    call    lantern_gossip_topic_parse
    test    %rax, %rax
    jz      1f
    movq    $0, (L + GossipTopic_name)(%rsp)
    movq    $0, (L + GossipTopic_subnet_id)(%rsp)
1:  mov     %rbp, %rdi                      # the message-id, of the fork of the store's slot
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     S9(%rsp), %rdi
    mov     S10(%rsp), %rsi
    lea     Node_config(%rbx), %rdx
    mov     %r14, %rcx
    lea     (L + 24)(%rsp), %r8
    FORK_CALL compute_message_id
    test    %rax, %rax
    jnz     99f
    mov     $LIBP2P_EV_MSG_ID_SIZE, %edi    # MESSAGE_ID
    call    node_out
    test    %rax, %rax
    jz      99f
    movq    $LIBP2P_EVENT_MESSAGE_ID, 8(%rax)
    mov     LIBP2P_ACT_HANDLE(%r12), %rcx
    mov     %rcx, 16(%rax)
    movq    $20, 24(%rax)
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, 32(%rax)
    movdqu  %xmm0, 48(%rax)
    lea     32(%rax), %rdi
    lea     (L + 24)(%rsp), %rsi
    mov     $20, %edx
    call    lantern_copy
    mov     Node_blobs(%rbx), %rax          # the entry
    sub     Node_messages(%rbx), %rax
    xor     %edx, %edx
    mov     $NodeMessage__mem, %ecx
    div     %rcx
    mov     (Node_messages + 8)(%rbx), %rcx
    cmp     %rax, %rcx
    jae     99f
    imul    $NodeMessage__mem, %rcx, %r13
    add     Node_messages(%rbx), %r13
    add     %rbx, %r13
    inc     %rcx
    mov     %rcx, (Node_messages + 8)(%rbx)
    mov     %r13, %rdi
    mov     $NodeMessage__mem, %esi
    call    lantern_zero
    mov     LIBP2P_ACT_HANDLE(%r12), %rax
    mov     %rax, NodeMessage_handle(%r13)
    mov     LIBP2P_ACT_MSG_PEER(%r12), %rax
    mov     %rax, NodeMessage_peer(%r13)
    mov     (L + GossipTopic_name)(%rsp), %rax
    mov     %rax, NodeMessage_topic(%r13)
    mov     (L + GossipTopic_subnet_id)(%rsp), %rax
    mov     %rax, NodeMessage_subnet(%r13)
    movq    $NODE_MESSAGE_CORRUPT, NodeMessage_state(%r13)  # the bytes, uncompressed
    mov     S10(%rsp), %rdi
    lea     (L + 48)(%rsp), %rsi
    CALL_GLOBAL snappy_get_uncompressed_length
    test    %rax, %rax
    jnz     99f
    mov     (L + 48)(%rsp), %rax
    cmp     (Node_config + CONFIG_MAX_PAYLOAD_SIZE)(%rbx), %rax
    ja      99f
    movq    $NODE_MESSAGE_NO_ROOM, NodeMessage_state(%r13)
    add     $(24 + 7), %rax
    and     $-8, %rax
    cmp     %rax, (%r14)
    jb      99f
    lea     48(%rax), %rdi                  # room for its BYTES_PUT
    call    node_room
    test    %rax, %rax
    jz      99f
    mov     (L + 48)(%rsp), %rcx
    add     $(24 + 7), %rcx
    and     $-8, %rcx
    mov     (%r14), %rax
    sub     %rcx, %rax
    mov     %rax, (%r14)
    lea     (%r14,%rax), %rsi
    mov     %rsi, S9(%rsp)
    mov     %rcx, (%rsi)
    movq    $24, 8(%rsi)
    movq    $0, 16(%rsi)
    mov     S10(%rsp), %rdi
    CALL_GLOBAL snappy_uncompress
    test    %rax, %rax
    jz      2f
    movq    $NODE_MESSAGE_CORRUPT, NodeMessage_state(%r13)
    jmp     99f
2:  mov     NodeMessage_topic(%r13), %rax   # the slot and parent root of a block or a block header
    mov     S9(%rsp), %rsi
    mov     16(%rsi), %rcx
    add     $24, %rsi
    cmp     $GOSSIP_BEACON_BLOCK, %rax
    jne     3f
    cmp     $(100 + 84), %rcx
    jb      5f
    add     $100, %rsi
    jmp     4f
3:  cmp     $GOSSIP_BLOB_SIDECAR, %rax
    jne     31f
    cmp     $(NODE_BLOB_HEADER + 48), %rcx
    jb      5f
    add     $NODE_BLOB_HEADER, %rsi
    jmp     4f
31: cmp     $GOSSIP_DATA_COLUMN_SIDECAR, %rax
    jne     5f
    cmp     $(20 + 48), %rcx
    jb      5f
    add     $20, %rsi
4:  mov     (%rsi), %rax
    mov     %rax, NodeMessage_slot(%r13)
    lea     NodeMessage_parent_root(%r13), %rdi
    add     $16, %rsi
    mov     $32, %edx
    call    lantern_copy
5:  mov     S9(%rsp), %rdi                  # the bytes, kept by the shell
    call    node_put
    mov     %rax, NodeMessage_data_id(%r13)
    movq    $NODE_MESSAGE_ID, NodeMessage_state(%r13)
99: mov     S8(%rsp), %rax
    mov     %rax, (%r14)
    LEAVE 64
END_FUNCTION node_message

/*
 * The MESSAGE_STATUS rdi of libp2p. NEW: a GOSSIP work with the head state, for a block or block
 * header a copy of its parent's post-state, and the state of the justified root; or a VALIDATION
 * when the node holds no bytes for it. Else its bytes and its entry go. r12 the notice, r13 the
 * entry, S7 the head state, S8 the proposer state, S9 the justified state.
 */
LOCAL_FUNCTION node_message_status
    ENTER 0
    mov     %rdi, %r12
    mov     LIBP2P_ACT_HANDLE(%r12), %rdi
    call    node_find_message
    cmp     $-1, %rax
    je      99f
    mov     %rdx, %r13
    cmpq    $LIBP2P_MSG_NEW, LIBP2P_ACT_STATUS(%r12)
    jne     80f
    mov     NodeMessage_state(%r13), %rax
    cmp     $NODE_MESSAGE_ID, %rax
    je      1f
    mov     $LIBP2P_IGNORE, %esi
    cmp     $NODE_MESSAGE_CORRUPT, %rax
    jne     70f
    mov     $LIBP2P_REJECT, %esi
70: mov     NodeMessage_handle(%r13), %rdi
    call    node_validation
    jmp     80f
1:  mov     $(NODE_ACT_WORK_SIZE + 32), %edi        # room for the work and a state copy
    call    node_room
    mov     $LIBP2P_IGNORE, %esi
    test    %rax, %rax
    jz      70b
    movq    $0, S7(%rsp)                    # the head state
    lea     Node_head_root(%rbx), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      2f
    mov     NodeBlock_state_id(%rdx), %rax
    mov     %rax, S7(%rsp)
2:  movq    $0, S8(%rsp)                    # the proposer state: a copy of the parent's, when it comes before
    mov     NodeMessage_topic(%r13), %rax
    cmp     $GOSSIP_BEACON_BLOCK, %rax
    je      21f
    cmp     $GOSSIP_BLOB_SIDECAR, %rax
    je      21f
    cmp     $GOSSIP_DATA_COLUMN_SIDECAR, %rax
    jne     3f
21: lea     NodeMessage_parent_root(%r13), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      3f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     3f
    mov     NodeMessage_slot(%r13), %rax
    cmp     NodeBlock_slot(%rdx), %rax
    jbe     3f
    mov     NodeBlock_state_id(%rdx), %rax
    mov     %rax, S9(%rsp)
    call    node_new_id
    mov     %rax, S8(%rsp)
    mov     $NODE_ACT_STATE_COPY, %edi
    mov     S9(%rsp), %rsi
    mov     %rax, %rdx
    call    node_ids
3:  movq    $0, S9(%rsp)                    # the state of the justified root
    lea     (Store_justified_checkpoint + 8)(%rbp), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      4f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     4f
    mov     NodeBlock_state_id(%rdx), %rax
    mov     %rax, S9(%rsp)
4:  mov     $NODE_WORK_GOSSIP, %edi
    mov     S7(%rsp), %rsi
    mov     S8(%rsp), %rdx
    mov     NodeMessage_data_id(%r13), %rcx
    mov     NodeMessage_handle(%r13), %r8
    mov     NodeMessage_subnet(%r13), %r9
    shl     $8, %r9
    or      NodeMessage_topic(%r13), %r9
    call    node_work
    mov     S9(%rsp), %rcx
    mov     %rcx, NodeAction_state_c(%rax)
    movq    $NODE_MESSAGE_VALIDATING, NodeMessage_state(%r13)
    LEAVE 0
80: cmpq    $0, NodeMessage_data_id(%r13)   # no work: its bytes and its entry go
    je      81f
    mov     $32, %edi
    call    node_room
    test    %rax, %rax
    jz      81f
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     NodeMessage_data_id(%r13), %rsi
    xor     %edx, %edx
    call    node_ids
81: mov     %r13, %rdi
    call    node_drop_message
99: LEAVE 0
END_FUNCTION node_message_status

/* ------------------------------------------------------------ sync */

/* The Status of rdx bytes at rsi (84, or 92 for v2) of the peer of handle rdi, kept in its entry. r12 the bytes, r13 their size, S7 the entry. */
LOCAL_FUNCTION node_peer_status
    ENTER 0
    mov     %rsi, %r12
    mov     %rdx, %r13
    call    node_find_peer
    cmp     $-1, %rax
    je      9f
    mov     %rdx, S7(%rsp)
    movq    $0, NodePeer_fork_digest(%rdx)
    lea     NodePeer_fork_digest(%rdx), %rdi
    mov     %r12, %rsi
    mov     $4, %edx
    call    lantern_copy
    mov     S7(%rsp), %rdi                  # finalized root and epoch, head root and slot
    add     $NodePeer_finalized_root, %rdi
    lea     4(%r12), %rsi
    mov     $(32 + 8 + 32 + 8), %edx
    call    lantern_copy
    mov     S7(%rsp), %rdi
    movq    $0, NodePeer_earliest_slot(%rdi)
    cmp     $92, %r13
    jne     1f
    add     $NodePeer_earliest_slot, %rdi
    lea     84(%r12), %rsi
    mov     $8, %edx
    call    lantern_copy
1:  mov     S7(%rsp), %rdi
    orq     $NODE_PEER_STATUS, NodePeer_flags(%rdi)
9:  LEAVE 0
END_FUNCTION node_peer_status

/* rax = the index of the node's stream in NODE_STREAM_OPENING of tag rdi, or 2^64 - 1; rdx = its entry. Uses rcx, rsi. */
LOCAL_FUNCTION node_find_opening
    UNWIND_END_PROLOGUE
    PART    %rdx, %rcx, %rbx, Node_streams
    mov     Node_stream_bytes(%rbx), %rsi
    xor     %eax, %eax
1:  cmp     %rcx, %rax
    jae     2f
    cmpq    $NODE_STREAM_OPENING, NodeStream_state(%rdx)
    jne     11f
    cmp     NodeStream_handle(%rdx), %rdi
    je      3f
11: add     %rsi, %rdx
    inc     %rax
    jmp     1b
2:  mov     $-1, %rax
3:  ret
END_FUNCTION node_find_opening

/* The stream entry rdi goes; the node's BeaconBlocksByRange request ends with it. */
LOCAL_FUNCTION node_end_stream
    FRAME 0
    cmpq    $NODE_STREAM_OPENING, NodeStream_state(%rdi)
    jb      1f
    cmpq    $REQRESP_BEACON_BLOCKS_BY_RANGE, NodeStream_method(%rdi)
    jne     1f
    andq    $~NODE_FLAG_SYNCING, Node_flags(%rbx)
1:  call    node_drop_stream
    UNFRAME 0
END_FUNCTION node_end_stream

/*
 * A request of the node: method rdi, version rsi, to the peer of handle rdx, its SSZ bytes at rcx
 * of r8 bytes: a NodeStream in NODE_STREAM_OPENING whose list holds the request chunk, and an
 * OPEN_STREAM of its protocol ID; rax = the entry, or 0 when the streams part, scratch or p2p_out
 * has no room. r12 the entry, r13 the request's ByteList, then the OPEN_STREAM, S7 the scratch
 * size, restored on return, S8 the peer, S9 the bytes, S10 their size. Locals: L a ChunkHeader,
 * L+48 a ReqRespProtocol, L+64 a ByteList of the protocol ID (152), L+216 the tag.
 */
LOCAL_FUNCTION node_open
    ENTER 224
    mov     %rdi, (L + 48)(%rsp)
    mov     %rsi, (L + 56)(%rsp)
    mov     %rdx, S8(%rsp)
    mov     %rcx, S9(%rsp)
    mov     %r8, S10(%rsp)
    mov     (%r14), %rax
    mov     %rax, S7(%rsp)
    mov     Node_messages(%rbx), %rax       # room for the entry
    sub     Node_streams(%rbx), %rax
    xor     %edx, %edx
    divq    Node_stream_bytes(%rbx)
    mov     (Node_streams + 8)(%rbx), %rcx
    cmp     %rax, %rcx
    jae     8f
    imul    Node_stream_bytes(%rbx), %rcx
    add     Node_streams(%rbx), %rcx
    lea     (%rbx,%rcx), %r12
    mov     S10(%rsp), %rax                 # the request's ByteList at the end of scratch
    add     $(24 + 7), %rax
    and     $-8, %rax
    mov     S7(%rsp), %rcx
    sub     %rax, %rcx
    jb      8f
    mov     %rcx, (%r14)
    lea     (%r14,%rcx), %r13
    mov     %rax, (%r13)
    movq    $24, 8(%r13)
    mov     S10(%rsp), %rax
    mov     %rax, 16(%r13)
    lea     24(%r13), %rdi
    mov     S9(%rsp), %rsi
    mov     S10(%rsp), %rdx
    call    lantern_copy
    mov     %r12, %rdi                      # the entry, its list empty
    mov     $NodeStream__fixed, %esi
    call    lantern_zero
    mov     Node_stream_bytes(%rbx), %rax
    sub     $NodeStream_list, %rax
    mov     %rax, NodeStream_list(%r12)
    movq    $24, (NodeStream_list + 8)(%r12)
    cmpq    $0, S10(%rsp)                   # no request bytes: an empty list
    je      1f
    movq    $CHUNK_REQUEST, (L + ChunkHeader_kind)(%rsp)    # the request chunk in the list
    movq    $0, (L + ChunkHeader_context_length)(%rsp)
    movq    $0, (L + ChunkHeader_result)(%rsp)
    lea     L(%rsp), %rdi
    mov     %r13, %rsi
    mov     %r14, %rdx
    lea     NodeStream_list(%r12), %rcx
    call    lantern_reqresp_write_chunk
    test    %rax, %rax
    jnz     8f
1:  movq    $(24 + 128), (L + 64)(%rsp)     # the protocol ID
    movq    $24, (L + 72)(%rsp)
    movq    $0, (L + 80)(%rsp)
    lea     (L + 48)(%rsp), %rdi
    lea     (L + 64)(%rsp), %rsi
    call    lantern_reqresp_protocol_id
    test    %rax, %rax
    jnz     8f
    call    node_new_id                     # the tag
    bts     $63, %rax
    mov     %rax, (L + 216)(%rsp)
    mov     $(40 + LIBP2P_PROTO_SIZE), %edi # OPEN_STREAM
    call    node_out
    test    %rax, %rax
    jz      8f
    mov     %rax, %r13
    movq    $LIBP2P_EVENT_OPEN_STREAM, 8(%r13)
    mov     S8(%rsp), %rax
    mov     %rax, 16(%r13)
    mov     (L + 216)(%rsp), %rax
    mov     %rax, 24(%r13)
    movq    $1, 32(%r13)
    mov     (L + 80)(%rsp), %rax
    mov     %rax, 40(%r13)
    lea     48(%r13), %rdi
    mov     $128, %esi
    call    lantern_zero
    lea     48(%r13), %rdi
    lea     (L + 88)(%rsp), %rsi
    mov     (L + 80)(%rsp), %rdx
    call    lantern_copy
    mov     (L + 216)(%rsp), %rax           # the entry joins the part
    mov     %rax, NodeStream_handle(%r12)
    mov     S8(%rsp), %rax
    mov     %rax, NodeStream_peer(%r12)
    mov     (L + 48)(%rsp), %rax
    mov     %rax, NodeStream_method(%r12)
    mov     (L + 56)(%rsp), %rax
    mov     %rax, NodeStream_version(%r12)
    movq    $NODE_STREAM_OPENING, NodeStream_state(%r12)
    incq    (Node_streams + 8)(%rbx)
    mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    mov     %r12, %rax
    LEAVE 224
8:  mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    xor     %eax, %eax
    LEAVE 224
END_FUNCTION node_open

/*
 * rax = 1 when the response bytes of the node's request stream rdi wait for room, else 0. Each
 * complete chunk is read: a Status goes to the peer's entry; a block becomes a NodeBlock in
 * NODE_BLOCK_HASHING, a BYTES_PUT of its bytes and a SYNC_BLOCK work of its root. After a Status,
 * after the last chunk and STREAM_EOF, after an error result, or on a bad chunk (with a
 * STREAM_RESET), the stream ends. r12 the entry, r13 the method. Locals: L a ChunkHeader, L+48 a
 * length, then a block index, L+56 eof, L+64 the payload bytes read, L+72 the scratch size,
 * restored on return, L+80 the SSZ size, L+88 the payload's ByteList, L+96 a block entry.
 */
LOCAL_FUNCTION node_response
    ENTER 112
    mov     %rdi, %r12
    mov     NodeStream_method(%r12), %r13
    mov     (%r14), %rax
    mov     %rax, (L + 72)(%rsp)
1:  cmpq    $0, (NodeStream_list + 16)(%r12)
    jne     2f
    cmpq    $0, NodeStream_next(%r12)       # no bytes: the end after STREAM_EOF
    jne     80f
    jmp     90f
2:  movq    $CHUNK_RESPONSE, (L + ChunkHeader_kind)(%rsp)  # blocks by range v2, blob and column sidecars: a ForkDigest context
    mov     $4, %eax
    cmp     $REQRESP_BLOB_SIDECARS_BY_RANGE, %r13
    je      3f
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE, %r13
    je      3f
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT, %r13
    je      3f
    xor     %eax, %eax
    cmp     $REQRESP_BEACON_BLOCKS_BY_RANGE, %r13
    jne     3f
    cmpq    $2, NodeStream_version(%r12)
    jb      3f
    mov     $4, %eax
3:  mov     %rax, (L + ChunkHeader_context_length)(%rsp)
    lea     NodeStream_list(%r12), %rdi
    lea     L(%rsp), %rsi
    call    lantern_reqresp_read_header
    cmp     $LANTERN_REQRESP_MORE, %rax
    je      5f
    test    %rax, %rax
    jnz     85f
    cmpq    $0, (L + ChunkHeader_result)(%rsp)
    jne     80f
    mov     (L + ChunkHeader_length)(%rsp), %rax
    mov     %rax, (L + 80)(%rsp)
    cmp     $REQRESP_STATUS, %r13
    jne     4f
    mov     $84, %ecx
    cmpq    $2, NodeStream_version(%r12)
    jb      31f
    mov     $92, %ecx
31: cmp     %rcx, %rax
    jne     85f
    jmp     41f
4:  cmp     $REQRESP_METADATA, %r13         # MetaData v3
    jne     43f
    cmp     $NODE_METADATA_V3, %rax
    jne     85f
    jmp     41f
43: cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE, %r13
    je      431f
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT, %r13
    jne     44f
431: cmp    $NODE_COLUMN_FIXED, %rax        # a column sidecar: room for its BYTES_PUT, its work, its entry
    jb      85f
    cmp     $NODE_COLUMN_BYTES, %rax
    ja      85f
    lea     (48 + NODE_ACT_WORK_SIZE + 7)(%rax), %rdi
    jmp     45f
44: cmp     $REQRESP_BLOB_SIDECARS_BY_RANGE, %r13
    jne     42f
    cmp     $NODE_BLOB_BYTES, %rax          # a blob sidecar: room for its BYTES_PUT, its work, its entry
    jne     85f
    mov     $(NODE_BLOB_BYTES + 48 + NODE_ACT_WORK_SIZE + 7), %edi
45: call    node_room
    test    %rax, %rax
    jz      95f
    mov     Node_p2p_out(%rbx), %rax
    sub     Node_blobs(%rbx), %rax
    xor     %edx, %edx
    mov     $NodeBlob__mem, %ecx
    div     %rcx
    cmp     %rax, (Node_blobs + 8)(%rbx)
    jae     95f
    jmp     41f
42: cmp     $(100 + 84), %rax               # a block: room for its BYTES_PUT, its work, its entry
    jb      85f
    cmp     (Node_config + CONFIG_MAX_PAYLOAD_SIZE)(%rbx), %rax
    ja      85f
    lea     (48 + NODE_ACT_WORK_SIZE + 7)(%rax), %rdi
    call    node_room
    test    %rax, %rax
    jz      95f
    mov     Node_checkpoints(%rbx), %rax
    sub     Node_blocks(%rbx), %rax
    xor     %edx, %edx
    mov     $NodeBlock__mem, %ecx
    div     %rcx
    cmp     %rax, (Node_blocks + 8)(%rbx)
    jae     95f
41: mov     (L + 80)(%rsp), %rax            # the payload's ByteList at the end of scratch
    add     $(24 + 7), %rax
    and     $-8, %rax
    mov     (L + 72)(%rsp), %rcx
    sub     %rax, %rcx
    jb      85f
    mov     %rcx, (%r14)
    lea     (%r14,%rcx), %rdi
    mov     %rdi, (L + 88)(%rsp)
    mov     %rax, (%rdi)
    movq    $24, 8(%rdi)
    movq    $0, 16(%rdi)
    mov     (L + 80)(%rsp), %rax            # length and eof, by address
    mov     %rax, (L + 48)(%rsp)
    mov     NodeStream_next(%r12), %rax
    mov     %rax, (L + 56)(%rsp)
    lea     (L + 64)(%rsp), %rax
    mov     %rax, S7(%rsp)                  # consumed, the seventh argument
    lea     NodeStream_list(%r12), %rdi
    lea     (L + ChunkHeader_header_bytes)(%rsp), %rsi
    lea     (L + 48)(%rsp), %rdx
    lea     (L + 56)(%rsp), %rcx
    mov     %r14, %r8
    mov     (L + 88)(%rsp), %r9
    call    lantern_reqresp_read_payload
    cmp     $LANTERN_REQRESP_MORE, %rax
    je      5f
    test    %rax, %rax
    jnz     85f
    cmp     $REQRESP_STATUS, %r13
    jne     6f
    mov     NodeStream_peer(%r12), %rdi     # Status: the peer's
    mov     (L + 88)(%rsp), %rsi
    add     $24, %rsi
    mov     (L + 80)(%rsp), %rdx
    call    node_peer_status
    jmp     7f
6:  cmp     $REQRESP_METADATA, %r13
    jne     62f
    mov     NodeStream_peer(%r12), %rdi     # MetaData: the peer's custody
    call    node_find_peer
    cmp     $-1, %rax
    je      7f
    mov     %rdx, %rdi
    mov     (L + 88)(%rsp), %rsi
    mov     (24 + 17)(%rsi), %rsi           # custody_group_count
    call    node_peer_custody
    jmp     7f
62: cmp     $REQRESP_BLOB_SIDECARS_BY_RANGE, %r13
    je      61f
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE, %r13
    je      63f
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT, %r13
    je      63f
    PART    %rdi, %rax, %rbx, Node_blocks   # a block: its entry, its bytes, the work of its root
    mov     %rax, (L + 48)(%rsp)
    imul    $NodeBlock__mem, %rax, %rcx
    add     %rcx, %rdi
    mov     %rdi, (L + 96)(%rsp)
    inc     %rax
    mov     %rax, (Node_blocks + 8)(%rbx)
    mov     $NodeBlock__mem, %esi
    call    lantern_zero
    mov     (L + 96)(%rsp), %rdi
    mov     (L + 88)(%rsp), %rsi
    mov     (24 + 100)(%rsi), %rax
    mov     %rax, NodeBlock_slot(%rdi)
    add     $NodeBlock_parent_root, %rdi
    add     $(24 + 116), %rsi
    mov     $32, %edx
    call    lantern_copy
    mov     (L + 96)(%rsp), %rdi
    movq    $NODE_BLOCK_HASHING, NodeBlock_status(%rdi)
    movq    $1, NodeBlock_data_available(%rdi)
    mov     (L + 88)(%rsp), %rdi
    call    node_put
    mov     (L + 96)(%rsp), %rdi
    mov     %rax, NodeBlock_data_id(%rdi)
    mov     %rax, %rcx
    mov     $NODE_WORK_SYNC_BLOCK, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     (L + 48)(%rsp), %r8
    xor     %r9d, %r9d
    call    node_work
    jmp     7f
61: PART    %rdi, %rax, %rbx, Node_blobs    # a blob sidecar: its entry, its bytes, the work of its checks
    mov     %rax, (L + 48)(%rsp)
    imul    $NodeBlob__mem, %rax, %rcx
    add     %rcx, %rdi
    mov     %rdi, (L + 96)(%rsp)
    inc     %rax
    mov     %rax, (Node_blobs + 8)(%rbx)
    mov     $NodeBlob__mem, %esi
    call    lantern_zero
    mov     (L + 96)(%rsp), %rdi
    mov     (L + 88)(%rsp), %rsi
    mov     24(%rsi), %rax                  # its index, and the slot of its block header
    mov     %rax, NodeBlob_index(%rdi)
    mov     (24 + NODE_BLOB_HEADER)(%rsi), %rax
    mov     %rax, NodeBlob_slot(%rdi)
    movq    $NODE_BLOB_VERIFYING, NodeBlob_status(%rdi)
    mov     %rsi, %rdi
    call    node_put
    mov     (L + 96)(%rsp), %rdi
    mov     %rax, NodeBlob_data_id(%rdi)
    mov     %rax, %rcx
    mov     $NODE_WORK_BLOB, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     (L + 48)(%rsp), %r8
    xor     %r9d, %r9d
    call    node_work
    jmp     7f
63: PART    %rdi, %rax, %rbx, Node_blobs    # a column sidecar: its entry, its bytes, the work of its checks
    mov     %rax, (L + 48)(%rsp)
    imul    $NodeBlob__mem, %rax, %rcx
    add     %rcx, %rdi
    mov     %rdi, (L + 96)(%rsp)
    inc     %rax
    mov     %rax, (Node_blobs + 8)(%rbx)
    mov     $NodeBlob__mem, %esi
    call    lantern_zero
    mov     (L + 96)(%rsp), %rdi
    mov     (L + 88)(%rsp), %rsi
    mov     24(%rsi), %rax                  # its index, and the slot of its block header
    mov     %rax, NodeBlob_index(%rdi)
    mov     (24 + NODE_COLUMN_HEADER)(%rsi), %rax
    mov     %rax, NodeBlob_slot(%rdi)
    movq    $NODE_BLOB_VERIFYING, NodeBlob_status(%rdi)
    mov     %rsi, %rdi
    call    node_put
    mov     (L + 96)(%rsp), %rdi
    mov     %rax, NodeBlob_data_id(%rdi)
    mov     %rax, %rcx
    mov     $NODE_WORK_BLOB, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     (L + 48)(%rsp), %r8
    mov     $1, %r9d
    call    node_work
7:  mov     (L + 72)(%rsp), %rax            # the chunk leaves the list
    mov     %rax, (%r14)
    mov     (L + ChunkHeader_header_bytes)(%rsp), %rax
    add     (L + 64)(%rsp), %rax
    mov     (NodeStream_list + 16)(%r12), %rdx
    sub     %rax, %rdx
    mov     %rdx, (NodeStream_list + 16)(%r12)
    lea     NodeStream_request(%r12), %rdi
    lea     (%rdi,%rax), %rsi
    call    lantern_copy
    cmp     $REQRESP_STATUS, %r13           # Status and MetaData: one chunk
    je      80f
    cmp     $REQRESP_METADATA, %r13
    je      80f
    jmp     1b
5:  mov     (L + 72)(%rsp), %rax            # part of a chunk: more bytes, or the end after STREAM_EOF
    mov     %rax, (%r14)
    cmpq    $0, NodeStream_next(%r12)
    jne     80f
90: xor     %eax, %eax
    LEAVE 112
95: mov     $1, %eax
    LEAVE 112
85: mov     (L + 72)(%rsp), %rax            # a bad chunk: a reset
    mov     %rax, (%r14)
    mov     $LIBP2P_EVENT_STREAM_RESET, %edi
    mov     NodeStream_handle(%r12), %rsi
    call    node_out_handle
80: mov     %r12, %rdi
    call    node_end_stream
    xor     %eax, %eax
    LEAVE 112
END_FUNCTION node_response

/*
 * rax = 1 when a response waits for room, else 0. The bytes of each response are read. From
 * fulu, each peer with a Status and no MetaData asked gets a GetMetaData v3. Then, with no
 * BeaconBlocksByRange of the node open, one to a peer of the node's ForkDigest (from fulu, with its
 * MetaData read) whose Status head_slot is at least the next slot: max(the head's slot + 1,
 * sync_slot), at most NODE_SYNC_BATCH slots. Before it, with room for two streams, a
 * BlobSidecarsByRange of the range's slots in the blob window before fulu; from fulu, a
 * DataColumnSidecarsByRange of the range's slots in the column window to each peer whose custody
 * holds sampled columns no earlier peer was asked for, with room for those and the blocks'
 * request. r12 a peer, r13 the streams or peers left, S7 the result, S8 the start slot, S9 the
 * scratch size. Locals: L the request (24), L+24 the blob or column range (16), L+40 the fork of
 * the store's slot, L+48 the columns asked (16), L+64 the pass (0 counts, 1 sends), L+72 the
 * column requests, L+80 the peer of the blocks, L+88 a column request at the end of scratch.
 */
LOCAL_FUNCTION node_sync
    ENTER 96
    movq    $0, S7(%rsp)
    mov     (Node_streams + 8)(%rbx), %r13  # the responses, from the last stream: an end moves the last
1:  test    %r13, %r13
    jz      3f
    dec     %r13
    mov     Node_stream_bytes(%rbx), %rdi
    imul    %r13, %rdi
    add     Node_streams(%rbx), %rdi
    add     %rbx, %rdi
    cmpq    $NODE_STREAM_RESPONSE, NodeStream_state(%rdi)
    jne     1b
    call    node_response
    or      %rax, S7(%rsp)
    jmp     1b
3:  mov     %rbp, %rdi                      # the fork of the store's slot
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, (L + 40)(%rsp)
    cmp     $FORK_FULU, %rax
    jb      31f
    PART    %r12, %r13, %rbx, Node_peers    # fulu: a GetMetaData v3 to each peer with a Status and none asked
30: test    %r13, %r13
    jz      31f
    mov     NodePeer_flags(%r12), %rax
    test    $NODE_PEER_STATUS, %rax
    jz      32f
    test    $(NODE_PEER_METADATA | NODE_PEER_METADATA_ASKED), %rax
    jnz     32f
    mov     Node_messages(%rbx), %rax       # room for it and two more
    sub     Node_streams(%rbx), %rax
    xor     %edx, %edx
    divq    Node_stream_bytes(%rbx)
    mov     (Node_streams + 8)(%rbx), %rcx
    add     $3, %rcx
    cmp     %rax, %rcx
    ja      31f
    mov     $REQRESP_METADATA, %edi
    mov     $3, %esi
    mov     NodePeer_handle(%r12), %rdx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    node_open
    test    %rax, %rax
    jz      31f
    orq     $NODE_PEER_METADATA_ASKED, NodePeer_flags(%r12)
32: add     $NodePeer__mem, %r12
    dec     %r13
    jmp     30b
31: testq   $NODE_FLAG_SYNCING, Node_flags(%rbx)
    jnz     9f
    lea     Node_head_root(%rbx), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      9f
    mov     NodeBlock_slot(%rdx), %rax
    inc     %rax
    mov     Node_sync_slot(%rbx), %rcx
    cmp     %rax, %rcx
    cmova   %rcx, %rax
    mov     %rax, S8(%rsp)
    PART    %r12, %r13, %rbx, Node_peers    # a peer ahead
4:  test    %r13, %r13
    jz      9f
    mov     NodePeer_flags(%r12), %rax
    test    $NODE_PEER_STATUS, %rax
    jz      5f
    cmpq    $FORK_FULU, (L + 40)(%rsp)      # from fulu: its MetaData read
    jb      41f
    test    $NODE_PEER_METADATA, %rax
    jz      5f
41: mov     NodePeer_fork_digest(%r12), %rax
    cmp     Node_fork_digest(%rbx), %rax
    jne     5f
    mov     NodePeer_head_slot(%r12), %rax
    cmp     S8(%rsp), %rax
    jae     6f
5:  add     $NodePeer__mem, %r12
    dec     %r13
    jmp     4b
6:  mov     %r12, (L + 80)(%rsp)
    sub     S8(%rsp), %rax                  # the request: start_slot, count, step 1
    inc     %rax
    mov     $NODE_SYNC_BATCH, %ecx
    cmp     %rcx, %rax
    cmova   %rcx, %rax
    mov     S8(%rsp), %rcx
    mov     %rcx, L(%rsp)
    mov     %rax, (L + 8)(%rsp)
    movq    $1, (L + 16)(%rsp)
    mov     (Node_config + CONFIG_MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS)(%rbx), %rdi  # the blob window's first slot
    mov     $FORK_DENEB, %esi
    call    node_window
    mov     $SLOTS_PER_EPOCH, %ecx
    mul     %rcx
    jc      12f
    mov     L(%rsp), %rsi                   # the range from there, before fulu's first slot
    mov     (L + 8)(%rsp), %rdi
    add     %rsi, %rdi
    jnc     11f
    mov     $-1, %rdi
11: cmp     %rax, %rsi
    cmovb   %rax, %rsi
    mov     (Node_config + 16 * FORK_FULU)(%rbx), %rax
    mov     $SLOTS_PER_EPOCH, %ecx
    mul     %rcx
    jc      13f
    cmp     %rax, %rdi
    cmova   %rax, %rdi
13: cmp     %rdi, %rsi
    jae     12f
    sub     %rsi, %rdi
    mov     %rsi, (L + 24)(%rsp)
    mov     %rdi, (L + 32)(%rsp)
    mov     Node_messages(%rbx), %rax       # room for it and the blocks' request
    sub     Node_streams(%rbx), %rax
    xor     %edx, %edx
    divq    Node_stream_bytes(%rbx)
    mov     (Node_streams + 8)(%rbx), %rcx
    add     $2, %rcx
    cmp     %rax, %rcx
    ja      9f
    mov     $REQRESP_BLOB_SIDECARS_BY_RANGE, %edi
    mov     $1, %esi
    mov     NodePeer_handle(%r12), %rdx
    lea     (L + 24)(%rsp), %rcx
    mov     $16, %r8d
    call    node_open
    test    %rax, %rax
    jz      9f
12: cmpq    $FORK_FULU, (L + 40)(%rsp)      # fulu: the column requests
    jb      71f
    mov     (Node_config + CONFIG_MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS)(%rbx), %rdi  # the column window's first slot
    mov     $FORK_FULU, %esi
    call    node_window
    mov     $SLOTS_PER_EPOCH, %ecx
    mul     %rcx
    jc      71f
    mov     L(%rsp), %rsi                   # the range from there
    mov     (L + 8)(%rsp), %rdi
    add     %rsi, %rdi
    jnc     14f
    mov     $-1, %rdi
14: cmp     %rax, %rsi
    cmovb   %rax, %rsi
    cmp     %rdi, %rsi
    jae     71f
    sub     %rsi, %rdi
    mov     %rsi, (L + 24)(%rsp)
    mov     %rdi, (L + 32)(%rsp)
    mov     (%r14), %rax                    # the request's bytes at the end of scratch
    mov     %rax, S9(%rsp)
    sub     $(24 + 8 * 128), %rax         # 8-aligned
    jb      9f
    mov     %rax, (%r14)
    add     %r14, %rax
    mov     %rax, (L + 88)(%rsp)
    movq    $0, (L + 64)(%rsp)              # first count the requests, then send them
72: movq    $0, (L + 48)(%rsp)
    movq    $0, (L + 56)(%rsp)
    movq    $0, (L + 72)(%rsp)
    PART    %r12, %r13, %rbx, Node_peers
73: test    %r13, %r13
    jz      76f
    testq   $NODE_PEER_METADATA, NodePeer_flags(%r12)
    jz      75f
    mov     Node_columns(%rbx), %rax        # the sampled columns it custodies, not asked yet
    and     NodePeer_custody(%r12), %rax
    mov     (L + 48)(%rsp), %rcx
    not     %rcx
    and     %rcx, %rax
    mov     (Node_columns + 8)(%rbx), %rdx
    and     (NodePeer_custody + 8)(%r12), %rdx
    mov     (L + 56)(%rsp), %rcx
    not     %rcx
    and     %rcx, %rdx
    mov     %rax, %rcx
    or      %rdx, %rcx
    jz      75f
    or      %rax, (L + 48)(%rsp)
    or      %rdx, (L + 56)(%rsp)
    incq    (L + 72)(%rsp)
    cmpq    $0, (L + 64)(%rsp)
    je      75f
    mov     (L + 88)(%rsp), %rdi            # start_slot, count, the offset 20, the columns in ascending order
    mov     (L + 24)(%rsp), %rcx
    mov     %rcx, (%rdi)
    mov     (L + 32)(%rsp), %rcx
    mov     %rcx, 8(%rdi)
    movl    $20, 16(%rdi)
    lea     20(%rdi), %r8
    xor     %ecx, %ecx
74: cmp     $128, %rcx
    jae     741f
    mov     %rax, %r9
    cmp     $64, %rcx
    cmovae  %rdx, %r9
    bt      %rcx, %r9
    jnc     742f
    mov     %rcx, (%r8)
    add     $8, %r8
742: inc    %rcx
    jmp     74b
741: mov    $REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE, %edi
    mov     $1, %esi
    mov     NodePeer_handle(%r12), %rdx
    mov     (L + 88)(%rsp), %rcx
    sub     %rcx, %r8
    call    node_open
    test    %rax, %rax
    jz      78f
75: add     $NodePeer__mem, %r12
    dec     %r13
    jmp     73b
76: cmpq    $0, (L + 64)(%rsp)
    jne     77f
    mov     Node_messages(%rbx), %rax       # room for the column requests and the blocks' request
    sub     Node_streams(%rbx), %rax
    xor     %edx, %edx
    divq    Node_stream_bytes(%rbx)
    mov     (Node_streams + 8)(%rbx), %rcx
    add     (L + 72)(%rsp), %rcx
    inc     %rcx
    cmp     %rax, %rcx
    ja      78f
    movq    $1, (L + 64)(%rsp)
    jmp     72b
78: mov     S9(%rsp), %rax
    mov     %rax, (%r14)
    jmp     9f
77: mov     S9(%rsp), %rax
    mov     %rax, (%r14)
71: mov     (L + 80)(%rsp), %r12
    mov     %rbp, %rdi                      # version 2 from altair on
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     $1, %esi
    cmp     $FORK_ALTAIR, %rax
    jb      7f
    mov     $2, %esi
7:  mov     $REQRESP_BEACON_BLOCKS_BY_RANGE, %edi
    mov     NodePeer_handle(%r12), %rdx
    lea     L(%rsp), %rcx
    mov     $24, %r8d
    call    node_open
    test    %rax, %rax
    jz      9f
    orq     $NODE_FLAG_SYNCING, Node_flags(%rbx)
    mov     L(%rsp), %rax
    add     (L + 8)(%rsp), %rax
    mov     %rax, Node_sync_slot(%rbx)
9:  mov     S7(%rsp), %rax
    LEAVE 96
END_FUNCTION node_sync

/*
 * The libp2p application notice rdi of the libp2p state rsi. r12 the notice, r13 an entry, S7
 * method, S8 version. Locals: L a Status (96).
 */
LOCAL_FUNCTION node_notice
    ENTER 96
    mov     %rdi, %r12
    mov     LIBP2P_ACT_KIND(%r12), %rax
    cmp     $LIBP2P_ACTION_MESSAGE, %rax
    jne     60f
    call    node_message                    # rdi, rsi as given
    LEAVE 96
60: cmp     $LIBP2P_ACTION_MESSAGE_STATUS, %rax
    jne     62f
    call    node_message_status
    LEAVE 96
62: cmp     $LIBP2P_ACTION_STREAM_OPENED, %rax
    jne     63f
    mov     LIBP2P_ACT_SO_TAG(%r12), %rdi   # the node's request stream: the request, then the close of our side
    call    node_find_opening
    cmp     $-1, %rax
    je      69f
    mov     %rdx, %r13
    mov     LIBP2P_ACT_STREAM(%r12), %rax
    mov     %rax, NodeStream_handle(%r13)
    movq    $NODE_STREAM_RESPONSE, NodeStream_state(%r13)
    movq    $0, NodeStream_next(%r13)
    mov     (NodeStream_list + 16)(%r13), %rax
    mov     %rax, S8(%rsp)
    test    %rax, %rax                      # no request bytes: only the close
    jz      66f
    add     $(32 + 7), %rax
    and     $-8, %rax
    mov     %rax, S7(%rsp)
    lea     24(%rax), %rdi
    call    node_out
    test    %rax, %rax
    jz      68f
    mov     S7(%rsp), %rcx
    mov     %rcx, (%rax)
    movq    $LIBP2P_EVENT_STREAM_WRITE, 8(%rax)
    mov     NodeStream_handle(%r13), %rdx
    mov     %rdx, 16(%rax)
    mov     S8(%rsp), %rsi
    mov     %rsi, 24(%rax)
    lea     (%rax,%rcx), %rsi
    movq    $24, (%rsi)
    movq    $LIBP2P_EVENT_STREAM_CLOSE, 8(%rsi)
    mov     %rdx, 16(%rsi)
    lea     32(%rax), %rdi
    lea     NodeStream_request(%r13), %rsi
    mov     S8(%rsp), %rdx
    call    lantern_copy
    movq    $0, (NodeStream_list + 16)(%r13)
69: LEAVE 96
66: mov     $24, %edi
    call    node_out
    test    %rax, %rax
    jz      68f
    movq    $LIBP2P_EVENT_STREAM_CLOSE, 8(%rax)
    mov     NodeStream_handle(%r13), %rdx
    mov     %rdx, 16(%rax)
    LEAVE 96
68: mov     $LIBP2P_EVENT_STREAM_RESET, %edi        # no room: a reset
    mov     NodeStream_handle(%r13), %rsi
    call    node_out_handle
    mov     %r13, %rdi
    call    node_end_stream
    LEAVE 96
63: cmp     $LIBP2P_ACTION_STREAM_FAILED, %rax
    jne     61f
    mov     LIBP2P_ACT_STREAM(%r12), %rdi   # its tag
    call    node_find_opening
    cmp     $-1, %rax
    je      69b
    mov     %rdx, %rdi
    call    node_end_stream
    LEAVE 96
61: mov     LIBP2P_ACT_KIND(%r12), %rax
    cmp     $LIBP2P_ACTION_PEER_CONNECTED, %rax
    jne     64f
    MOVQ    %rcx, NODE_DIAL_TAG             # a dial of the node ends
    test    %rcx, LIBP2P_ACT_PC_TAG(%r12)
    jz      65f
    cmpq    $0, Node_dialing(%rbx)
    je      65f
    decq    Node_dialing(%rbx)
65: mov     Node_streams(%rbx), %rax        # a new peer: its entry, or DISCONNECT when the table is full
    sub     Node_peers(%rbx), %rax
    xor     %edx, %edx
    mov     $NodePeer__mem, %ecx
    div     %rcx
    mov     (Node_peers + 8)(%rbx), %rcx
    cmp     %rax, %rcx
    jb      1f
    mov     $LIBP2P_EVENT_DISCONNECT, %edi
    mov     LIBP2P_ACT_PEER(%r12), %rsi
    call    node_out_handle
    LEAVE 96
1:  imul    $NodePeer__mem, %rcx, %r13
    add     Node_peers(%rbx), %r13
    add     %rbx, %r13
    inc     %rcx
    mov     %rcx, (Node_peers + 8)(%rbx)
    mov     %r13, %rdi
    mov     $NodePeer__mem, %esi
    call    lantern_zero
    mov     LIBP2P_ACT_PEER(%r12), %rax
    mov     %rax, NodePeer_handle(%r13)
    mov     LIBP2P_ACT_PC_DIRECTION(%r12), %rax
    mov     %rax, NodePeer_direction(%r13)
    mov     LIBP2P_ACT_PC_ID_LEN(%r12), %rdx
    cmp     $48, %rdx
    jbe     2f
    mov     $48, %edx
2:  mov     %rdx, NodePeer_id_len(%r13)
    lea     NodePeer_id(%r13), %rdi
    lea     LIBP2P_ACT_PC_ID(%r12), %rsi
    call    lantern_copy
    cmpq    $LIBP2P_OUTBOUND, NodePeer_direction(%r13)      # we dialled: our Status first (v2 from fulu, v1 before)
    jne     69b
    lea     L(%rsp), %rdi
    call    node_status_bytes
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     $1, %esi
    mov     $84, %r8d
    cmp     $FORK_FULU, %rax
    jb      3f
    mov     $2, %esi
    mov     $92, %r8d
3:  mov     $REQRESP_STATUS, %edi
    mov     NodePeer_handle(%r13), %rdx
    lea     L(%rsp), %rcx
    call    node_open
    LEAVE 96
64: cmp     $LIBP2P_ACTION_DIAL_FAILED, %rax
    jne     10f
    MOVQ    %rcx, NODE_DIAL_TAG             # a dial of the node ends
    test    %rcx, LIBP2P_ACT_TAG(%r12)
    jz      69b
    cmpq    $0, Node_dialing(%rbx)
    je      69b
    decq    Node_dialing(%rbx)
    LEAVE 96
10: cmp     $LIBP2P_ACTION_PEER_DISCONNECTED, %rax
    jne     20f
    mov     LIBP2P_ACT_PEER(%r12), %rdi
    call    node_find_peer
    cmp     $-1, %rax
    je      19f
    mov     %rdx, %rdi
    call    node_drop_peer
19: LEAVE 96
20: cmp     $LIBP2P_ACTION_STREAM_INBOUND, %rax
    jne     30f
    mov     LIBP2P_ACT_SI_PROTOCOL(%r12), %rdi      # a request stream: its entry, or a reset
    call    node_protocol
    test    %rax, %rax
    jz      28f
    mov     %rax, S7(%rsp)
    mov     %rdx, S8(%rsp)
    mov     Node_messages(%rbx), %rax
    sub     Node_streams(%rbx), %rax
    xor     %edx, %edx
    mov     Node_stream_bytes(%rbx), %rcx
    div     %rcx
    mov     (Node_streams + 8)(%rbx), %rdx
    cmp     %rax, %rdx
    jae     28f
    imul    %rdx, %rcx
    lea     1(%rdx), %rax
    mov     %rax, (Node_streams + 8)(%rbx)
    mov     Node_streams(%rbx), %r13
    add     %rbx, %r13
    add     %rcx, %r13
    mov     LIBP2P_ACT_STREAM(%r12), %rax
    mov     %rax, NodeStream_handle(%r13)
    mov     LIBP2P_ACT_SI_PEER(%r12), %rax
    mov     %rax, NodeStream_peer(%r13)
    mov     S7(%rsp), %rax
    mov     %rax, NodeStream_method(%r13)
    mov     S8(%rsp), %rax
    mov     %rax, NodeStream_version(%r13)
    movq    $NODE_STREAM_REQUEST, NodeStream_state(%r13)
    mov     Node_stream_bytes(%rbx), %rax
    sub     $NodeStream_list, %rax
    mov     %rax, NodeStream_list(%r13)
    movq    $24, (NodeStream_list + 8)(%r13)
    movq    $0, (NodeStream_list + 16)(%r13)
    mov     %r13, %rdi
    call    node_request
    LEAVE 96
28: mov     $LIBP2P_EVENT_STREAM_RESET, %edi
    mov     LIBP2P_ACT_STREAM(%r12), %rsi
    call    node_out_handle
    LEAVE 96
30: cmp     $LIBP2P_ACTION_STREAM_DATA, %rax
    jne     40f
    mov     LIBP2P_ACT_STREAM(%r12), %rdi   # request bytes: kept, then read
    call    node_find_stream
    cmp     $-1, %rax
    je      39f
    mov     %rdx, %r13
    mov     (NodeStream_list + 16)(%r13), %rax
    mov     LIBP2P_ACT_SD_COUNT(%r12), %rdx
    mov     NodeStream_list(%r13), %rcx
    sub     $24, %rcx
    sub     %rax, %rcx
    cmp     %rcx, %rdx
    ja      38f
    lea     NodeStream_request(%r13,%rax), %rdi
    lea     LIBP2P_ACT_SD_DATA(%r12), %rsi
    add     %rdx, %rax
    mov     %rax, (NodeStream_list + 16)(%r13)
    call    lantern_copy
    mov     %r13, %rdi
    cmpq    $NODE_STREAM_RESPONSE, NodeStream_state(%r13)
    jne     37f
    call    node_response                   # response bytes of the node's request
    LEAVE 96
37: call    node_request
39: LEAVE 96
38: mov     $LIBP2P_EVENT_STREAM_RESET, %edi        # more than the room: a reset
    mov     NodeStream_handle(%r13), %rsi
    call    node_out_handle
    mov     %r13, %rdi
    call    node_end_stream
    LEAVE 96
40: cmp     $LIBP2P_ACTION_STREAM_EOF, %rax
    jne     50f
    mov     LIBP2P_ACT_STREAM(%r12), %rdi
    call    node_find_stream
    cmp     $-1, %rax
    je      49f
    cmpq    $NODE_STREAM_RESPONSE, NodeStream_state(%rdx)
    jne     41f
    movq    $1, NodeStream_next(%rdx)       # the response is complete
    mov     %rdx, %rdi
    call    node_response
    LEAVE 96
41: cmpq    $NODE_STREAM_EOF, NodeStream_state(%rdx)        # while its request is read
    ja      49f
    movq    $NODE_STREAM_EOF, NodeStream_state(%rdx)
    mov     %rdx, %rdi
    call    node_request
49: LEAVE 96
50: cmp     $LIBP2P_ACTION_STREAM_RESET, %rax
    jne     59f
    mov     LIBP2P_ACT_STREAM(%r12), %rdi
    call    node_find_stream
    cmp     $-1, %rax
    je      59f
    mov     %rdx, %rdi
    call    node_end_stream
59: LEAVE 96
END_FUNCTION node_notice

/* rax = the WAKEUP time of the libp2p actions in the ByteList rdi, after their application notices, of the libp2p state rsi. r12 an action, r13 the end, S7 the time, S8 the state. */
LOCAL_FUNCTION node_p2p_notices
    ENTER 0
    mov     %rsi, S8(%rsp)
    mov     8(%rdi), %r12
    add     %rdi, %r12
    mov     16(%rdi), %r13
    add     %r12, %r13
    movq    $-1, S7(%rsp)
1:  cmp     %r13, %r12
    jae     9f
    mov     LIBP2P_ACT_KIND(%r12), %rax
    cmp     $LIBP2P_ACTION_WAKEUP, %rax
    jne     2f
    mov     LIBP2P_ACT_TIME(%r12), %rax
    mov     %rax, S7(%rsp)
    jmp     3f
2:  cmp     $LIBP2P_ACTION_PEER_CONNECTED, %rax
    jb      3f
    cmp     $LIBP2P_ACTION_SEND_DATAGRAM, %rax
    jae     3f
    mov     %r12, %rdi
    mov     S8(%rsp), %rsi
    call    node_notice
3:  add     (%r12), %r12
    jmp     1b
9:  mov     S7(%rsp), %rax
    LEAVE 0
END_FUNCTION node_p2p_notices

/* The libp2p events of the P2P events from rdi to rsi join the end of the node's queued events. r12, r13 the range, S7 the queue. */
LOCAL_FUNCTION node_p2p_append
    ENTER 0
    mov     %rdi, %r12
    mov     %rsi, %r13
    P2P_OUT %rax
    mov     %rax, S7(%rsp)
1:  cmp     %r13, %r12
    jae     9f
    cmpq    $NODE_EV_P2P, 8(%r12)
    jne     2f
    mov     S7(%rsp), %rax
    mov     16(%r12), %rdx
    mov     16(%rax), %rcx
    lea     24(%rax,%rcx), %rdi
    add     %rdx, %rcx
    mov     %rcx, 16(%rax)
    lea     16(%r12), %rsi
    call    lantern_copy
2:  add     (%r12), %r12
    jmp     1b
9:  LEAVE 0
END_FUNCTION node_p2p_append

/*
 * Of the P2P events from rdi to rsi, the first rdx were taken: rax = the next P2P event, or rsi;
 * rdx = the bytes of the libp2p events of the P2P events from there on. Uses rcx, r8.
 */
LOCAL_FUNCTION node_p2p_left
    UNWIND_END_PROLOGUE
    mov     %rsi, %rax
    xor     %r8d, %r8d
1:  cmp     %rsi, %rdi
    jae     9f
    cmpq    $NODE_EV_P2P, 8(%rdi)
    jne     3f
    test    %rdx, %rdx
    jz      2f
    dec     %rdx
    jmp     3f
2:  cmp     %rsi, %rax
    jne     21f
    mov     %rdi, %rax
21: add     16(%rdi), %r8
3:  add     (%rdi), %rdi
    jmp     1b
9:  mov     %r8, %rdx
    ret
END_FUNCTION node_p2p_left

/* rax = the events in the first rdi bytes of the node's queue. Uses rcx, rdx. */
LOCAL_FUNCTION node_out_count
    UNWIND_END_PROLOGUE
    P2P_OUT %rdx
    add     $24, %rdx
    xor     %ecx, %ecx
    xor     %eax, %eax
1:  cmp     %rdi, %rcx
    jae     2f
    add     (%rdx,%rcx), %rcx
    inc     %rax
    jmp     1b
2:  ret
END_FUNCTION node_out_count

/*
 * libp2p_step of the state rdi with the tick rsi, the event list rdx and the scratch rcx, its
 * actions in a P2P_LIST action that takes the action room left less r8 bytes, its StepResult at
 * r9: rax = 0 and rdx = the actions' ByteList; 1 when the room is short; or libp2p's status, with
 * no action added. r12 state, r13 tick, S7 list, S8 scratch, S9 result, S10 the action.
 */
LOCAL_FUNCTION node_p2p_round
    ENTER 0
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     %rdx, S7(%rsp)
    mov     %rcx, S8(%rsp)
    mov     %r9, S9(%rsp)
    mov     (%r15), %rax
    sub     8(%r15), %rax
    sub     16(%r15), %rax
    sub     %r8, %rax
    jb      8f
    cmp     $(LIBP2P_ACTIONS_MIN + 24 + 16), %rax
    jb      8f
    mov     %rax, %rcx                      # half of it, when that is enough: the rest for the notices
    shr     $1, %rcx
    cmp     $(LIBP2P_ACTIONS_MIN + 24 + 16), %rcx
    cmovae  %rcx, %rax
    and     $-8, %rax
    mov     8(%r15), %rcx
    add     16(%r15), %rcx
    add     %r15, %rcx
    mov     %rcx, S10(%rsp)
    mov     %rax, (%rcx)
    movq    $NODE_ACT_P2P_LIST, 8(%rcx)
    lea     -16(%rax), %rdx
    mov     %rdx, 16(%rcx)
    movq    $24, 24(%rcx)
    movq    $0, 32(%rcx)
    mov     %r12, %rdi
    mov     %r13, %rsi
    mov     S7(%rsp), %rdx
    lea     16(%rcx), %r8
    mov     S8(%rsp), %rcx
    mov     S9(%rsp), %r9
    CALL_GLOBAL libp2p_step
    test    %rax, %rax
    jnz     9f
    mov     S10(%rsp), %rcx                 # the action holds the actions written
    mov     32(%rcx), %rax
    add     $24, %rax
    mov     %rax, 16(%rcx)
    add     $16, %rax
    mov     %rax, (%rcx)
    add     %rax, 16(%r15)
    lea     16(%rcx), %rdx
    xor     %eax, %eax
    LEAVE 0
8:  mov     $1, %eax
9:  LEAVE 0
END_FUNCTION node_p2p_round

/*
 * (out, count): the protocol IDs of the req/resp protocols the node answers, as libp2p
 * ProtocolEntry values in the ByteList out, by method then version; count = how many.
 * rbx out, rbp count, r12 the protocols, r13 an index, r14 an entry. Locals: L a ReqRespProtocol,
 * L+16 a ByteList of an ID.
 */
FUNCTION lantern_node_protocols
    ENTER 176
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    xor     %r12d, %r12d
1:  mov     %r12, %rdi
    call    node_protocol
    test    %rax, %rax
    jz      2f
    inc     %r12
    jmp     1b
2:  imul    $LIBP2P_PROTO_SIZE, %r12, %rax
    lea     24(%rax), %rcx
    cmp     %rcx, (%rbx)
    jb      8f
    movq    $24, 8(%rbx)
    mov     %rax, 16(%rbx)
    mov     %r12, (%rbp)
    xor     %r13d, %r13d
    lea     24(%rbx), %r14
3:  cmp     %r12, %r13
    jae     7f
    mov     %r13, %rdi
    call    node_protocol
    mov     %rax, L(%rsp)
    mov     %rdx, (L + 8)(%rsp)
    mov     %r14, %rdi
    mov     $LIBP2P_PROTO_SIZE, %esi
    call    lantern_zero
    movq    $(24 + 128), (L + 16)(%rsp)
    movq    $24, (L + 24)(%rsp)
    movq    $0, (L + 32)(%rsp)
    lea     L(%rsp), %rdi
    lea     (L + 16)(%rsp), %rsi
    call    lantern_reqresp_protocol_id
    mov     (L + 32)(%rsp), %rdx
    mov     %rdx, (%r14)
    lea     8(%r14), %rdi
    lea     (L + 40)(%rsp), %rsi
    call    lantern_copy
    add     $LIBP2P_PROTO_SIZE, %r14
    inc     %r13
    jmp     3b
7:  xor     %eax, %eax
    LEAVE 176
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 176
END_FUNCTION lantern_node_protocols

/*
 * The root entry at rsi of the BLOCK event rdi: its first u64 is 0 and the root follows, or the
 * first u64 is not 0 when the bytes are no SignedBeaconBlock. rax = the status. r12 the ByteList,
 * r13 the entry.
 */
LOCAL_FUNCTION node_block_entry
    ENTER 16
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
    lea     L(%rsp), %r8                    # its blob count: not kept
    FORK_CALL node_block_root
    LEAVE 16
9:  xor     %eax, %eax
    LEAVE 16
END_FUNCTION node_block_entry

/*
 * (node, store, p2p, tick, events, scratch, actions, result): rbx node, rbp store, r12 the
 * events, r13 their end, r14 scratch, r15 actions, S7 result, S8 the event count, S9 an event,
 * S10 a root entry at the end of scratch. The first pass counts in r8 the events, r9 the BLOCK
 * and GOSSIP WORK_DONE events, r10 the event bytes, r11 the WORK_DONE events. Locals: L the WORK_DONE
 * events, L+8 the scratch size, L+16 p2p, L+24 tick, L+32 the end of the events handled, L+40
 * the queue's free bytes the P2P events take, saved, L+48 the libp2p scratch, L+56 the bytes of the P2P events, L+64 the P2P
 * events, L+72 the action room kept for the node, L+80 wakeup, L+88 libp2p's StepResult, L+96
 * libp2p's actions, L+104 the libp2p steps, L+112 a stream waits, L+120 the GOSSIP WORK_DONE events,
 * L+128 the bytes of the ENGINE events, L+136 1 with an ENR event,
 * L+144 the POW_BLOCK events.
 */
FUNCTION lantern_node_step
    ENTER 160
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, (L + 16)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
    mov     8(%r8), %r12
    add     %r8, %r12
    mov     16(%r8), %r13
    add     %r12, %r13
    mov     %r9, %r14
    mov     (160 + 96)(%rsp), %r15          # the seventh and eighth arguments
    mov     (160 + 104)(%rsp), %rax
    mov     %rax, S7(%rsp)
    xor     %r8d, %r8d                      # first: check every event, and count
    xor     %r9d, %r9d
    xor     %r10d, %r10d
    xor     %r11d, %r11d
    movq    $0, (L + 56)(%rsp)
    movq    $0, (L + 64)(%rsp)
    movq    $0, (L + 120)(%rsp)
    movq    $0, (L + 128)(%rsp)
    movq    $0, (L + 136)(%rsp)
    movq    $0, (L + 144)(%rsp)
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
    cmp     $NODE_EV_LAST, %rsi
    jae     7f
    cmp     $NODE_EV_TICK, %rdx
    jne     2f
    cmp     $24, %rcx
    jb      7f
    jmp     4f
2:  cmp     $NODE_EV_WORK_DONE, %rdx
    jne     21f
    cmp     $NODE_EV_WORK_DONE_SIZE, %rcx
    jb      7f
    cmpq    $NODE_WORK_GOSSIP, NodeAction_work_kind(%rdi)   # GOSSIP: a block or a blob it may add
    jne     201f
    inc     %r9
    incq    (L + 120)(%rsp)
201: mov    NodeAction_work_kind(%rdi), %rsi    # SERVE, and NEW_PAYLOAD or FORKCHOICE of LANTERN_VALID: a ByteList of the chunk inside
    cmp     $NODE_WORK_SERVE, %rsi
    je      202f
    cmp     $NODE_WORK_NEW_PAYLOAD, %rsi
    je      203f
    cmp     $NODE_WORK_FORKCHOICE, %rsi
    jne     22f
203: cmpq   $0, NodeEvent_result(%rdi)
    jne     22f
202:
    cmp     $(NodeEvent_chunk + 24), %rcx
    jb      7f
    cmpq    $24, (NodeEvent_chunk + 8)(%rdi)
    jne     7f
    lea     -(NodeEvent_chunk + 24)(%rcx), %rsi
    cmp     %rsi, (NodeEvent_chunk + 16)(%rdi)
    ja      7f
22: inc     %r11
    jmp     4f
21: cmp     $NODE_EV_ENGINE, %rdx           # ENGINE: arg 0 with bytes, or 1; with NODE_FLAG_ENGINE
    jne     211f
    testq   $NODE_FLAG_ENGINE, Node_flags(%rbx)
    jz      7f
    cmp     $24, %rcx
    jb      7f
    mov     16(%rdi), %rsi
    cmp     $1, %rsi
    ja      7f
    je      4f
    cmp     $(24 + 24), %rcx
    jb      7f
    cmpq    $24, (24 + 8)(%rdi)
    jne     7f
    lea     -(24 + 24)(%rcx), %rsi
    cmp     %rsi, (24 + 16)(%rdi)
    ja      7f
    mov     (24 + 16)(%rdi), %rsi
    add     %rsi, (L + 128)(%rsp)
    jmp     4f
211: cmp    $NODE_EV_P2P, %rdx              # a libp2p event inside, for a node with a libp2p state
    jne     3f
    cmpq    $0, (L + 16)(%rsp)
    je      7f
    cmp     $(16 + 16), %rcx
    jb      7f
    mov     16(%rdi), %rsi
    cmp     $16, %rsi
    jb      7f
    test    $7, %sil
    jnz     7f
    lea     -16(%rcx), %rax
    cmp     %rax, %rsi
    ja      7f
    add     %rsi, (L + 56)(%rsp)
    incq    (L + 64)(%rsp)
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
    cmp     $NODE_EV_ENR, %rdx              # ENR: with p2p
    jne     33f
    cmpq    $0, (L + 16)(%rsp)
    je      7f
    movq    $1, (L + 136)(%rsp)
33: cmp     $NODE_EV_BLOCK, %rdx
    je      31f
    cmp     $NODE_EV_POW_BLOCK, %rdx
    jne     4f
    incq    (L + 144)(%rsp)                 # POW_BLOCK: counted at L+144
    jmp     4f
31: inc     %r9
4:  inc     %r8
    add     %rcx, %r10
    add     %rcx, %rdi
    jmp     1b
5:  call    node_column_count               # the columns sampled, for the blobs part
    mov     %rax, (L + 152)(%rsp)
    mov     %r8, S8(%rsp)
    mov     %r11, L(%rsp)
    imul    $512, %r8, %rcx                 # room: actions, node parts, scratch
    add     %r10, %rcx
    imul    $128, (Node_blocks + 8)(%rbx), %rdx
    add     %rdx, %rcx
    add     $512, %rcx
    mov     %rcx, (L + 72)(%rsp)
    cmpq    $0, (L + 16)(%rsp)
    je      51f
    add     $(LIBP2P_ACTIONS_MIN + 24 + 16), %rcx
51: mov     (%r15), %rax
    sub     8(%r15), %rax
    jb      81f
    sub     16(%r15), %rax
    jb      81f
    cmp     %rcx, %rax
    jb      81f
    mov     Node_checkpoints(%rbx), %rax    # blocks: one entry for each BLOCK event
    sub     Node_blocks(%rbx), %rax
    xor     %edx, %edx
    mov     $NodeBlock__mem, %ecx
    div     %rcx
    sub     (Node_blocks + 8)(%rbx), %rax
    xor     %ecx, %ecx                      # with p2p, NODE_SYNC_BATCH more for the responses
    cmpq    $0, (L + 16)(%rsp)
    je      1f
    mov     $NODE_SYNC_BATCH, %ecx
1:  add     %r9, %rcx
    cmp     %rcx, %rax
    jb      85f
    mov     Node_p2p_out(%rbx), %rax        # blobs: one for each GOSSIP WORK_DONE event, and with p2p a batch's sidecars
    sub     Node_blobs(%rbx), %rax
    xor     %edx, %edx
    mov     $NodeBlob__mem, %ecx
    div     %rcx
    sub     (Node_blobs + 8)(%rbx), %rax
    mov     (L + 120)(%rsp), %rcx
    cmpq    $0, (L + 16)(%rsp)
    je      54f
    mov     (Node_config + CONFIG_MAX_BLOBS_PER_BLOCK)(%rbx), %rdx
    mov     (Node_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA)(%rbx), %rsi
    cmp     %rsi, %rdx
    cmovb   %rsi, %rdx
    cmp     (L + 152)(%rsp), %rdx
    cmovb   (L + 152)(%rsp), %rdx
    mov     %rdx, %rsi
    shr     $32, %rsi
    jnz     86f
    imul    $NODE_SYNC_BATCH, %rdx, %rdx
    add     %rdx, %rcx
54: cmp     %rcx, %rax
    jb      86f
    mov     Node_engine_in(%rbx), %rax      # engine_in: the bytes of the ENGINE events
    mov     (%rbx,%rax), %rcx
    sub     $24, %rcx
    sub     16(%rbx,%rax), %rcx
    cmp     (L + 128)(%rsp), %rcx
    jb      87f
    mov     Node_pow_blocks(%rbx), %rax     # checkpoints: two for each WORK_DONE event, and two
    sub     Node_checkpoints(%rbx), %rax
    xor     %edx, %edx
    mov     $NodeCheckpoint__mem, %ecx
    div     %rcx
    sub     (Node_checkpoints + 8)(%rbx), %rax
    lea     2(%r11,%r11), %rcx
    cmp     %rcx, %rax
    jb      88f
    mov     Node_peers(%rbx), %rax          # pow blocks: one for each POW_BLOCK event
    sub     Node_pow_blocks(%rbx), %rax
    xor     %edx, %edx
    mov     $POW_BLOCK_BYTES, %ecx
    div     %rcx
    sub     (Node_pow_blocks + 8)(%rbx), %rax
    cmp     (L + 144)(%rsp), %rax
    jb      89f
    imul    $NODE_ROOT_ENTRY, %r9, %r8      # scratch: the root entries, and with p2p the queue's bytes the P2P events take and libp2p's scratch, at its end
    cmpq    $0, (L + 16)(%rsp)
    je      52f
    P2P_OUT %rcx                            # the queue has room for the P2P events
    mov     (%rcx), %rax
    sub     $24, %rax
    sub     16(%rcx), %rax
    cmp     (L + 56)(%rsp), %rax
    jb      90f
    add     (L + 56)(%rsp), %r8
    add     $LIBP2P_SCRATCH_SIZE, %r8
52: mov     Store_validators(%rbp), %rax    # and what get_head needs
    sub     Store_blocks(%rbp), %rax
    shl     $4, %rax
    xor     %edx, %edx
    mov     $BlockNode__mem, %ecx
    div     %rcx
    MOVQ    %rcx, LANTERN_SCRATCH_FIXED + 64
    add     %rcx, %rax
    add     %r8, %rax
    cmpq    $0, (L + 136)(%rsp)             # with an ENR event, the record's decoding
    je      53f
    MOVQ    %rcx, DISCV5_ENR_SIZE + DISCV5_ENR_SCRATCH
    add     %rcx, %rax
53: mov     (%r14), %rcx
    cmp     %rax, %rcx
    jb      83f
    mov     %rcx, (L + 8)(%rsp)
    sub     %r8, %rcx
    mov     %rcx, (%r14)
    lea     (%r14,%rcx), %rax
    mov     %rax, S10(%rsp)
    cmpq    $0, (L + 16)(%rsp)
    je      53f
    imul    $NODE_ROOT_ENTRY, %r9, %rcx     # the saved queue bytes, then libp2p's scratch
    add     %rcx, %rax
    mov     %rax, (L + 40)(%rsp)
    add     (L + 56)(%rsp), %rax
    mov     %rax, (L + 48)(%rsp)
    movq    $LIBP2P_SCRATCH_SIZE, (%rax)
53: mov     S7(%rsp), %rax                  # the root of each BLOCK event, before any change; its room: scratch
    movq    $NODE_SHORT_SCRATCH, NodeStepResult_short(%rax)
    mov     %r12, S9(%rsp)
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
13: mov     %r13, (L + 32)(%rsp)            # libp2p: the queued events, then the P2P events
    movq    $-1, (L + 80)(%rsp)
    cmpq    $0, (L + 16)(%rsp)
    je      30f
    P2P_OUT %rax                            # S9 the queue, S10 its bytes before the P2P events
    mov     %rax, S9(%rsp)
    mov     16(%rax), %rcx
    mov     %rcx, S10(%rsp)
    mov     (L + 40)(%rsp), %rdi            # the free bytes of the queue the P2P events take, kept
    lea     24(%rax,%rcx), %rsi
    mov     (L + 56)(%rsp), %rdx
    call    lantern_copy
    mov     %r12, %rdi
    mov     %r13, %rsi
    call    node_p2p_append
    mov     (L + 16)(%rsp), %rdi
    mov     (L + 24)(%rsp), %rsi
    mov     S9(%rsp), %rdx
    mov     (L + 48)(%rsp), %rcx
    mov     (L + 72)(%rsp), %r8
    lea     (L + 88)(%rsp), %r9
    call    node_p2p_round
    test    %rax, %rax
    jz      24f
    mov     %rax, (L + 104)(%rsp)           # a status of libp2p: the queue as it was, and nothing else changed
    mov     S9(%rsp), %rax
    mov     S10(%rsp), %rcx
    mov     %rcx, 16(%rax)
    lea     24(%rax,%rcx), %rdi
    mov     (L + 40)(%rsp), %rsi
    mov     (L + 56)(%rsp), %rdx
    call    lantern_copy
    mov     (L + 104)(%rsp), %rcx
    mov     $LANTERN_INVALID_EVENT, %eax
    mov     $LANTERN_BUFFER_TOO_SMALL, %edx
    cmp     $LIBP2P_BUFFER_TOO_SMALL, %rcx
    cmove   %rdx, %rax
    mov     S7(%rsp), %rcx                  # libp2p's room: actions
    movq    $NODE_SHORT_ACTIONS, NodeStepResult_short(%rcx)
    jmp     14f
24: mov     %rdx, (L + 96)(%rsp)            # from here on the step holds
    mov     S10(%rsp), %rdi                 # the P2P events libp2p took: k less the queued ones
    call    node_out_count
    mov     (L + 88)(%rsp), %rdx
    sub     %rax, %rdx
    jae     23f
    xor     %edx, %edx
23: mov     %r12, %rdi
    mov     %r13, %rsi
    call    node_p2p_left
    mov     %rax, (L + 32)(%rsp)            # the step ends at the next one
    mov     S9(%rsp), %rax                  # the ones left go from the queue's end
    sub     %rdx, 16(%rax)
    mov     (L + 88)(%rsp), %rdi            # the ones taken from its front
    call    node_out_consume
29: mov     (L + 96)(%rsp), %rdi
    mov     (L + 16)(%rsp), %rsi
    call    node_p2p_notices
    mov     %rax, (L + 80)(%rsp)
30: mov     (%r14), %rax                    # then each event, in order
    add     %r14, %rax
    mov     %rax, S10(%rsp)
    movq    $0, S8(%rsp)
    mov     %r12, S9(%rsp)
6:  mov     S9(%rsp), %rdi
    cmp     (L + 32)(%rsp), %rdi
    jae     9f
    incq    S8(%rsp)
    cmpq    $NODE_EV_P2P, 8(%rdi)
    je      15f
    mov     S10(%rsp), %rsi
    call    node_event
    mov     S9(%rsp), %rdi
    cmpq    $NODE_EV_BLOCK, 8(%rdi)
    jne     15f
    addq    $NODE_ROOT_ENTRY, S10(%rsp)
15: mov     S9(%rsp), %rdi
    add     (%rdi), %rdi
    mov     %rdi, S9(%rsp)
    jmp     6b
9:  call    node_head
    call    node_engine_next
    movq    $0, (L + 112)(%rsp)
    cmpq    $0, (L + 16)(%rsp)              # the next block of each stream that serves, then libp2p again
    je      40f
    call    node_subscribe
    call    node_serve
    mov     %rax, (L + 112)(%rsp)
    call    node_sync
    or      %rax, (L + 112)(%rsp)
    mov     (L + 24)(%rsp), %rdi
    call    node_lookup
    movq    $0, (L + 104)(%rsp)
32: P2P_OUT %rdx
    cmpq    $0, 16(%rdx)
    je      40f
    cmpq    $NODE_P2P_ROUNDS, (L + 104)(%rsp)
    jae     40f
    incq    (L + 104)(%rsp)
    mov     (L + 16)(%rsp), %rdi
    mov     (L + 24)(%rsp), %rsi
    mov     (L + 48)(%rsp), %rcx
    mov     $4096, %r8d
    lea     (L + 88)(%rsp), %r9
    call    node_p2p_round
    test    %rax, %rax
    jnz     40f
    mov     %rdx, (L + 96)(%rsp)
    mov     (L + 88)(%rsp), %rdi
    call    node_out_consume
    mov     (L + 96)(%rsp), %rdi
    mov     (L + 16)(%rsp), %rsi
    call    node_p2p_notices
    mov     %rax, (L + 80)(%rsp)
    jmp     32b
40: P2P_OUT %rax                            # events left, or a stream that waits: the next step is due now
    mov     16(%rax), %rax
    or      (L + 112)(%rsp), %rax
    jz      41f
    mov     (L + 24)(%rsp), %rax
    mov     LIBP2P_TICK_NOW(%rax), %rax
    mov     %rax, (L + 80)(%rsp)
41: mov     (L + 8)(%rsp), %rax
    mov     %rax, (%r14)
    mov     S7(%rsp), %rdi
    mov     S8(%rsp), %rax
    mov     %rax, NodeStepResult_accepted(%rdi)
    mov     (L + 80)(%rsp), %rax
    mov     %rax, NodeStepResult_wakeup(%rdi)
    xor     %eax, %eax
    LEAVE 160
14: mov     (L + 8)(%rsp), %rcx             # a status before any change
    mov     %rcx, (%r14)
    LEAVE 160
7:  mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 160
81: mov     $NODE_SHORT_ACTIONS, %ecx       # the buffer with too little room
    jmp     84f
85: mov     $NodeRoom_blocks, %ecx          # a part of the node: the NodeRoom field of its capacity
    jmp     82f
86: mov     $NodeRoom_blobs, %ecx
    jmp     82f
87: mov     $NodeRoom_engine_bytes, %ecx
    jmp     82f
88: mov     $NodeRoom_checkpoints, %ecx
    jmp     82f
89: mov     $NodeRoom_pow_blocks, %ecx
    jmp     82f
90: mov     $NodeRoom_p2p_out, %ecx
82: mov     S7(%rsp), %rdx
    mov     %rcx, NodeStepResult_room(%rdx)
    mov     $NODE_SHORT_NODE, %ecx
    jmp     84f
83: mov     $NODE_SHORT_SCRATCH, %ecx
84: mov     S7(%rsp), %rdx
    mov     %rcx, NodeStepResult_short(%rdx)
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 160
END_FUNCTION lantern_node_step

/*
 * (node, store, seen, work, state_a, state_b, state_c, data, settings, scratch, event): rbx node,
 * rbp store, r12 work, r13 state_a, r14 data, r15 scratch, S7 the seventh argument of a call, S8
 * event, S9 the event's room, S10 a temporary. Locals: L the BlockOptions (32), or a chunk's size,
 * a fork digest and a ChunkHeader (64); L+64 seen, L+72 state_b, L+80 state_c, L+88 settings,
 * L+96 a NodeGossip.
 */
FUNCTION lantern_node_run
    ENTER 192
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     %rdx, (L + 64)(%rsp)            # seen, state_b, state_c, settings
    mov     %r9, (L + 72)(%rsp)
    mov     (192 + 96)(%rsp), %rax           # the seventh to eleventh arguments
    mov     %rax, (L + 80)(%rsp)
    mov     (192 + 96 + 8)(%rsp), %r14
    mov     (192 + 96 + 16)(%rsp), %rax
    mov     %rax, (L + 88)(%rsp)
    mov     (192 + 96 + 24)(%rsp), %r15
    mov     (192 + 96 + 32)(%rsp), %rax
    mov     %rax, S8(%rsp)
    mov     (%rax), %rcx                    # the event's room
    mov     %rcx, S9(%rsp)
    cmp     $NODE_EV_WORK_DONE_SIZE, %rcx
    jb      7f
    movq    $NODE_EV_WORK_DONE_SIZE, (%rax) # the event: the work's fields, the result
    movq    $NODE_EV_WORK_DONE, 8(%rax)
    .irp off, 16, 24, 32, 40, 48, 56, 64
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
    testq   $NODE_FLAG_ENGINE, Node_flags(%rbx)     # with NODE_FLAG_ENGINE, the block's: the engine's answer
    jz      1f
    mov     NodeBlock_payload_status(%rsi,%rdi), %rcx
    mov     %rcx, (L + BlockOptions_payload_status)(%rsp)
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
    LEAVE 192
18: mov     S8(%rsp), %rcx
    movq    $LANTERN_INVALID_ENCODING, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
10: cmp     $NODE_WORK_JUSTIFIED_STATE, %rax
    jne     20f
    mov     NODE_STATE_SLOT(%r13), %rdi     # JUSTIFIED_STATE: the fork of the state's slot
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %rbp, %rdi
    mov     %r13, %rsi
    FORK_CALL store_justified_checkpoint_state
    LEAVE 192
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
    LEAVE 192
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
    LEAVE 192
40: cmp     $NODE_WORK_ATTESTER_SLASHING, %rax
    jne     50f
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
99: LEAVE 192
50: cmp     $NODE_WORK_SERVE, %rax
    jne     60f
    mov     NodeAction_arg(%r12), %rax      # SERVE: L+176 1 for a blob method, 2 for a column method
    shr     $8, %rax
    xor     %ecx, %ecx
    cmp     $REQRESP_BLOB_SIDECARS_BY_RANGE, %rax
    sete    %cl
    cmp     $REQRESP_BLOB_SIDECARS_BY_ROOT, %rax
    sete    %dl
    or      %dl, %cl
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE, %rax
    sete    %dl
    add     %dl, %dl
    or      %dl, %cl
    cmp     $REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT, %rax
    sete    %dl
    add     %dl, %dl
    or      %dl, %cl
    movzbl  %cl, %ecx
    mov     %rcx, (L + 176)(%rsp)
    mov     16(%r14), %rax                  # the chunk of the block's or sidecar's bytes, with room for it
    mov     $(100 + 84), %edx
    cmp     $1, %rcx
    jb      501f
    mov     $(NODE_BLOB_HEADER + 8), %edx
    je      501f
    mov     $(NODE_COLUMN_HEADER + 8), %edx
501: cmp    %rdx, %rax
    jb      18b
    mov     %rax, L(%rsp)
    lea     L(%rsp), %rdi
    lea     L(%rsp), %rsi
    call    lantern_reqresp_chunk_size
    mov     L(%rsp), %rax
    add     $(NodeEvent_chunk + 24 + 7), %rax
    and     $-8, %rax
    cmp     %rax, S9(%rsp)
    jb      7f
    mov     8(%r14), %rax                   # the context: ForkDigest of the epoch of the block's or header's slot
    add     %r14, %rax
    cmpq    $0, (L + 176)(%rsp)
    jne     502f
    mov     100(%rax), %rax
    jmp     503f
502: cmpq   $2, (L + 176)(%rsp)
    je      504f
    mov     NODE_BLOB_HEADER(%rax), %rax
    jmp     503f
504: mov    NODE_COLUMN_HEADER(%rax), %rax
503: mov    %rax, S10(%rsp)
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     S10(%rsp), %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, L(%rsp)
    movq    $0, (L + 8)(%rsp)
    lea     Node_genesis_validators_root(%rbx), %rdi
    lea     L(%rsp), %rsi
    lea     Node_config(%rbx), %rdx
    mov     %r15, %rcx
    lea     (L + 8)(%rsp), %r8
    FORK_CALL compute_fork_digest
    test    %rax, %rax
    jnz     99b
    movq    $CHUNK_RESPONSE, (L + 16 + ChunkHeader_kind)(%rsp)      # the header: blocks v1 have no context bytes
    movzbl  NodeAction_arg(%r12), %edx
    xor     %eax, %eax
    mov     $4, %ecx
    cmp     $2, %rdx
    cmovae  %rcx, %rax
    cmpq    $0, (L + 176)(%rsp)
    cmovne  %rcx, %rax
    mov     %rax, (L + 16 + ChunkHeader_context_length)(%rsp)
    movq    $0, (L + 16 + ChunkHeader_result)(%rsp)
    mov     (L + 8)(%rsp), %eax
    mov     %rax, (L + 16 + ChunkHeader_context)(%rsp)
    mov     S8(%rsp), %rcx                  # the chunk's ByteList after the WORK_DONE fields
    lea     NodeEvent_chunk(%rcx), %rcx
    mov     %rcx, S10(%rsp)
    mov     S9(%rsp), %rax
    sub     $NodeEvent_chunk, %rax
    mov     %rax, (%rcx)
    movq    $24, 8(%rcx)
    movq    $0, 16(%rcx)
    lea     (L + 16)(%rsp), %rdi
    mov     %r14, %rsi
    mov     %r15, %rdx
    call    lantern_reqresp_write_chunk
    test    %rax, %rax
    jnz     99b
    mov     S10(%rsp), %rcx                 # the sizes of the list and the event
    mov     16(%rcx), %rax
    add     $(24 + 7), %rax
    and     $-8, %rax
    mov     %rax, (%rcx)
    add     $NodeEvent_chunk, %rax
    mov     S8(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
    LEAVE 192
60: cmp     $NODE_WORK_GOSSIP, %rax
    jne     70f
    mov     (L + 64)(%rsp), %rax            # GOSSIP: the inputs of the fork's node_gossip
    mov     %rax, (L + 96 + NodeGossip_seen)(%rsp)
    mov     %rbp, (L + 96 + NodeGossip_store)(%rsp)
    mov     Node_time_ms(%rbx), %rax
    mov     %rax, (L + 96 + NodeGossip_time_ms)(%rsp)
    mov     NodeAction_arg(%r12), %rax
    movzbl  %al, %ecx
    shr     $8, %rax
    mov     %rcx, (L + 96 + NodeGossip_topic)(%rsp)
    mov     %rax, (L + 96 + NodeGossip_subnet)(%rsp)
    mov     %r13, (L + 96 + NodeGossip_head)(%rsp)
    mov     (L + 72)(%rsp), %rax
    mov     %rax, (L + 96 + NodeGossip_proposer)(%rsp)
    mov     (L + 80)(%rsp), %rax
    mov     %rax, (L + 96 + NodeGossip_justified)(%rsp)
    mov     (L + 88)(%rsp), %rax
    mov     %rax, (L + 96 + NodeGossip_settings)(%rsp)
    lea     Node_config(%rbx), %rax
    mov     %rax, (L + 96 + NodeGossip_config)(%rsp)
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    lea     (L + 96)(%rsp), %rdi
    mov     %r14, %rsi
    mov     %r15, %rdx
    mov     S8(%rsp), %rcx
    lea     NodeEvent_index(%rcx), %r9
    lea     NodeEvent_result(%rcx), %r8
    lea     NodeEvent_root(%rcx), %rcx
    xchg    %rcx, %r8
    FORK_CALL node_gossip
    LEAVE 192
70: cmp     $NODE_WORK_SYNC_BLOCK, %rax
    jne     80f
    cmpq    $(100 + 84), 16(%r14)           # SYNC_BLOCK: node_block_root of the fork of its slot
    jb      18b
    mov     8(%r14), %rax
    add     %r14, %rax
    mov     100(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r14, %rdi
    mov     %r15, %rsi
    mov     S8(%rsp), %rcx
    lea     NodeEvent_root(%rcx), %rdx
    lea     NodeEvent_index(%rcx), %r8
    lea     NodeEvent_result(%rcx), %rcx
    FORK_CALL node_block_root
    LEAVE 192
80: cmp     $NODE_WORK_BLOB, %rax
    jne     82f
    cmpq    $0, NodeAction_arg(%r12)
    jne     88f
    cmpq    $(NODE_BLOB_HEADER + 8), 16(%r14)   # BLOB: node_blob_sidecar of the fork of its slot, deneb or electra
    jb      18b
    mov     8(%r14), %rax
    add     %r14, %rax
    mov     NODE_BLOB_HEADER(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r14, %rdi
    lea     Node_config(%rbx), %rsi
    mov     (L + 88)(%rsp), %rdx
    mov     %r15, %rcx
    mov     S8(%rsp), %r9
    lea     NodeEvent_result(%r9), %r8
    lea     NodeEvent_root(%r9), %r9
    cmp     $FORK_DENEB, %r10
    jne     81f
    CALL_GLOBAL lantern_deneb_node_blob_sidecar
    LEAVE 192
81: cmp     $FORK_ELECTRA, %r10
    jne     18b
    CALL_GLOBAL lantern_electra_node_blob_sidecar
    LEAVE 192
88: cmpq    $(NODE_COLUMN_HEADER + 8), 16(%r14)  # arg 1: node_column_sidecar, of a slot of fulu
    jb      18b
    mov     8(%r14), %rax
    add     %r14, %rax
    mov     NODE_COLUMN_HEADER(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_FULU, %rax
    jne     18b
    mov     %r14, %rdi
    lea     Node_config(%rbx), %rsi
    mov     (L + 88)(%rsp), %rdx
    mov     %r15, %rcx
    mov     S8(%rsp), %r9
    lea     NodeEvent_result(%r9), %r8
    lea     NodeEvent_root(%r9), %r9
    CALL_GLOBAL lantern_fulu_node_column_sidecar
    LEAVE 192
82: cmp     $NODE_WORK_NEW_PAYLOAD, %rax
    jne     83f
    cmpq    $(100 + 84), 16(%r14)           # NEW_PAYLOAD: node_new_payload of the fork of the block's slot
    jb      18b
    mov     8(%r14), %rax
    add     %r14, %rax
    mov     100(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    cmp     $FORK_BELLATRIX, %r10
    jb      86f
    cmpq    $(NodeEvent_chunk + 24), S9(%rsp)
    jb      7f
    mov     S8(%rsp), %r8                   # the request's ByteList after the WORK_DONE fields
    lea     NodeEvent_chunk(%r8), %r8
    mov     S9(%rsp), %rax
    sub     $NodeEvent_chunk, %rax
    mov     %rax, (%r8)
    movq    $24, 8(%r8)
    movq    $0, 16(%r8)
    mov     %r8, S10(%rsp)
    mov     %r14, %rdi
    mov     %rbx, %rsi
    lea     NodeAction_arg(%r12), %rdx
    mov     %r15, %rcx
    mov     S8(%rsp), %r9
    lea     NodeEvent_result(%r9), %r9
    FORK_CALL_BELLATRIX node_new_payload
    test    %rax, %rax
    jnz     99b
    mov     S8(%rsp), %rcx
    cmpq    $0, NodeEvent_result(%rcx)
    jne     99b
    jmp     84f
83: cmp     $NODE_WORK_FORKCHOICE, %rax
    jne     8f
    mov     %rbp, %rdi                      # FORKCHOICE: of the fork of the store's slot
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, S7(%rsp)
    cmp     $FORK_BELLATRIX, %rax
    jb      86f
    lea     Node_head_root(%rbx), %rdi      # the ForkchoiceState at L+96: head, safe (justified), finalized
    call    node_store_find
    cmp     $-1, %rax
    je      87f
    lea     (L + 96)(%rsp), %rdi
    lea     BlockNode_block_hash(%rdx), %rsi
    COPY32  %rdi, %rsi
    lea     (Store_justified_checkpoint + 8)(%rbp), %rdi
    call    node_store_find
    cmp     $-1, %rax
    je      87f
    lea     (L + 128)(%rsp), %rdi
    lea     BlockNode_block_hash(%rdx), %rsi
    COPY32  %rdi, %rsi
    lea     (Store_finalized_checkpoint + 8)(%rbp), %rdi
    call    node_store_find
    cmp     $-1, %rax
    je      87f
    lea     (L + 160)(%rsp), %rdi
    lea     BlockNode_block_hash(%rdx), %rsi
    COPY32  %rdi, %rsi
    mov     (L + 96)(%rsp), %rax            # a head of no payload: no call
    or      (L + 104)(%rsp), %rax
    or      (L + 112)(%rsp), %rax
    or      (L + 120)(%rsp), %rax
    jz      86f
    cmpq    $(NodeEvent_chunk + 24), S9(%rsp)
    jb      7f
    mov     (%r15), %rax                    # at the end of scratch: the JSON (536), the token (280), the host (88)
    mov     %rax, S10(%rsp)
    cmp     $(904 + 512), %rax
    jb      7f
    sub     $904, %rax
    mov     %rax, (%r15)
    lea     (%r15,%rax), %r13
    movq    $536, (%r13)
    movq    $24, 8(%r13)
    movq    $0, 16(%r13)
    movq    $280, 536(%r13)
    movq    $24, (536 + 8)(%r13)
    movq    $0, (536 + 16)(%r13)
    movq    $88, 816(%r13)
    movq    $24, (816 + 8)(%r13)
    mov     Node_engine_host_len(%rbx), %rdx
    mov     %rdx, (816 + 16)(%r13)
    lea     (816 + 24)(%r13), %rdi
    lea     Node_engine_host(%rbx), %rsi
    call    lantern_copy
    lea     (L + 96)(%rsp), %rdi
    lea     NodeAction_arg(%r12), %rsi
    mov     %r13, %rdx
    mov     S7(%rsp), %r10
    FORK_CALL_BELLATRIX engine_forkchoice_updated
    test    %rax, %rax
    jnz     85f
    mov     Node_time_ms(%rbx), %rax        # the JWT at the time in seconds
    xor     %edx, %edx
    mov     $1000, %ecx
    div     %rcx
    mov     %rax, L(%rsp)
    lea     Node_jwt_secret(%rbx), %rdi
    lea     L(%rsp), %rsi
    mov     %r15, %rdx
    lea     536(%r13), %rcx
    call    lantern_jwt_token
    test    %rax, %rax
    jnz     85f
    mov     S8(%rsp), %rcx                  # the HTTP request after the WORK_DONE fields
    lea     NodeEvent_chunk(%rcx), %rcx
    mov     S9(%rsp), %rax
    sub     $NodeEvent_chunk, %rax
    mov     %rax, (%rcx)
    movq    $24, 8(%rcx)
    movq    $0, 16(%rcx)
    lea     816(%r13), %rdi
    lea     536(%r13), %rsi
    mov     %r13, %rdx
    call    lantern_http_post
    test    %rax, %rax
    jnz     85f
    mov     S10(%rsp), %rax
    mov     %rax, (%r15)
    mov     S8(%rsp), %r8
    lea     NodeEvent_chunk(%r8), %r8
    mov     %r8, S10(%rsp)
84: mov     S10(%rsp), %r8                  # the sizes of the list and the event
    mov     16(%r8), %rax
    add     $(24 + 7), %rax
    and     $-8, %rax
    mov     %rax, (%r8)
    add     $NodeEvent_chunk, %rax
    mov     S8(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
    LEAVE 192
85: mov     S10(%rsp), %rcx                 # a status, with the scratch's size back
    mov     %rcx, (%r15)
    LEAVE 192
86: mov     S8(%rsp), %rcx
    movq    $LANTERN_NO_PAYLOAD, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
87: mov     S8(%rsp), %rcx
    movq    $LANTERN_INVALID_UNKNOWN_BLOCK, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
8:  mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 192
7:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 192
END_FUNCTION lantern_node_run
