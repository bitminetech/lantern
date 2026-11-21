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
    NODE_SIZE_ADD api_streams, NodeApi__mem
    NODE_SIZE_ADD pool, NodePool__mem
    NODE_SIZE_ADD proposers, NodeProposer__mem
    NODE_SIZE_ADD eth1_blocks, Eth1Block__mem
    NODE_SIZE_ADD eth1_deposits, Eth1Deposit__mem + 32 + Eth1Count__mem   # the deposits, their leaves and counts
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
    mov     NodeRoom_db_roots(%rdi), %rax   # the Db: DB_FIXED, its slots, a power of two of roots
    test    %rax, %rax
    jz      9f
    lea     -1(%rax), %rcx
    test    %rcx, %rax
    jnz     9f
    mov     %rax, %rcx
    shr     $60, %rcx
    jnz     9f
    shl     $3, %rax
    add     %rax, %r8
    jc      9f
    NODE_SIZE_ADD db_slots, DbSlot__mem
    add     $DB_FIXED, %r8
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
    NODE_PART api, api_streams, NodeApi__mem
    NODE_PART pool, pool, NodePool__mem
    NODE_PART proposers, proposers, NodeProposer__mem
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
    add     %rcx, %rax
    mov     %rax, Node_db(%rdi)             # one Db, its size set
    movq    $1, (Node_db + 8)(%rdi)
    imul    $DbSlot__mem, NodeRoom_db_slots(%rsi), %rcx
    mov     NodeRoom_db_roots(%rsi), %rdx
    lea     DB_FIXED(%rcx,%rdx,8), %rcx
    mov     %rcx, (%rdi,%rax)
    add     %rcx, %rax
    NODE_PART eth1_blocks, eth1_blocks, Eth1Block__mem
    NODE_PART eth1_deposits, eth1_deposits, Eth1Deposit__mem
    NODE_PART eth1_leaves, eth1_deposits, 32
    NODE_PART eth1_counts, eth1_deposits, Eth1Count__mem
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
    movq    $3, Node_next_id(%r15)          # 1 the anchor state, 2 the light client store
    movq    $1, Node_anchor_state_id(%r15)
    mov     %r14, Node_flags(%r15)
    mov     %r13, Node_earliest_slot(%r15)
    mov     %r13, Node_base_slot(%r15)      # the base state: the anchor's post-state, at its slot
    movq    $-1, Node_archive_slot(%r15)    # the archive: no state record yet; with NODE_FLAG_DB, the anchor's archive_slots
    movq    $-1, Node_archive_first(%r15)
    movq    $-1, Node_archive_segment(%r15)
    test    $NODE_FLAG_DB, %r14
    jz      1701f
    mov     NodeAnchor_archive_slots(%r12), %rax
    mov     %rax, Node_archive_slots(%r15)
1701:
    lea     Node_head_root(%r15), %rdi
    COPY32  %rdi, %r12
    lea     Node_event_head(%r15), %rdi     # the events: the anchor's head and finalized epoch
    COPY32  %rdi, %r12
    mov     %r13, Node_event_slot(%r15)
    mov     %r13, %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, Node_event_epoch(%r15)
    lea     Node_genesis_validators_root(%r15), %rdi
    lea     NodeAnchor_genesis_validators_root(%r12), %rsi
    COPY32  %rdi, %rsi
    lea     Node_node_id(%r15), %rdi
    lea     NodeAnchor_node_id(%r12), %rsi
    COPY32  %rdi, %rsi
    lea     Node_config(%r15), %rdi
    mov     %rbp, %rsi
    MOVQ    %rdx, CONFIG_SIZE
    call    lantern_copy
    mov     CONFIG_CUSTODY_REQUIREMENT(%rbp), %rax  # custody_count: the higher of CUSTODY_REQUIREMENT and the anchor's, at most every group
    cmp     NodeAnchor_custody_count(%r12), %rax
    cmovb   NodeAnchor_custody_count(%r12), %rax
    cmp     CONFIG_NUMBER_OF_CUSTODY_GROUPS(%rbp), %rax
    cmova   CONFIG_NUMBER_OF_CUSTODY_GROUPS(%rbp), %rax
    test    $NODE_FLAG_SUPERNODE, %r14      # a supernode: every group
    cmovnz  CONFIG_NUMBER_OF_CUSTODY_GROUPS(%rbp), %rax
    mov     %rax, Node_custody_count(%r15)
    mov     NodeAnchor_custody_slot(%r12), %rcx
    mov     %rcx, Node_custody_slot(%r15)
    mov     CONFIG_SAMPLES_PER_SLOT(%rbp), %rsi  # the columns: of max(SAMPLES_PER_SLOT, the custody group count) groups
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
1:  test    $NODE_FLAG_BUILDER, %r14        # the builder's host
    jz      16f
    mov     NodeAnchor_builder_host_len(%r12), %rdx
    cmp     $NODE_ENGINE_HOST_MAX, %rdx
    ja      7f
    mov     %rdx, Node_builder_host_len(%r15)
    lea     Node_builder_host(%r15), %rdi
    lea     NodeAnchor_builder_host(%r12), %rsi
    call    lantern_copy
16: mov     %r15, %rdi
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
    mov     NodeAnchor_history_slot(%r12), %rax    # the Db: from the segment of history_slot, the anchor, or the backfill's target; its archive after the anchor
    cmp     %r13, %rax
    cmova   %r13, %rax
    mov     %rax, L(%rsp)
    mov     CONFIG_MIN_VALIDATOR_WITHDRAWABILITY_DELAY(%rbp), %rcx    # compute_min_epochs_for_block_requests
    mov     CONFIG_CHURN_LIMIT_QUOTIENT(%rbp), %rdx
    shr     $1, %rdx
    add     %rdx, %rcx
    jnc     60f
    mov     $-1, %rcx
60: mov     %r13, %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %r8d
    div     %r8
    sub     %rcx, %rax
    jae     61f
    xor     %eax, %eax
61: imul    $SLOTS_PER_EPOCH, %rax, %rax
    cmp     L(%rsp), %rax
    jb      62f
    mov     L(%rsp), %rax
62:
    and     $-DB_SEGMENT_SLOTS, %rax
    mov     %rax, L(%rsp)
    lea     NodeRoom_db_slots(%rbx), %rdi
    lea     L(%rsp), %rsi
    mov     Node_db(%r15), %rdx
    add     %r15, %rdx
    call    lantern_db_init
    test    %rax, %rax
    jnz     9f
    mov     L(%rsp), %rax                   # the Db's first slot: no sidecar dropped yet
    mov     %rax, Node_sidecar_floor(%r15)
    lea     1(%r13), %rax
    mov     %rax, Node_db_next_slot(%r15)
    movq    $-1, Node_db_block_segment(%r15)
    movq    $-1, Node_db_sidecar_segment(%r15)
    movq    $-1, Node_backfill_segment(%r15)   # the backfill: from the anchor's block down
    movq    $-1, Node_backfill_sidecar_segment(%r15)
    movq    $-1, Node_backfill_start(%r15)
    lea     1(%r13), %rax
    mov     %rax, Node_backfill_slot(%r15)
    mov     %rax, Node_backfill_next(%r15)
    lea     Node_backfill_root(%r15), %rdi
    COPY32  %rdi, %r12
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
    NODE_COPY_ROOM api_streams, Node_api
    NODE_COPY_ROOM pool, Node_pool
    NODE_COPY_ROOM proposers, Node_proposers
    NODE_COPY_ROOM eth1_blocks, Node_eth1_blocks
    NODE_COPY_ROOM eth1_deposits, Node_eth1_deposits
    NODE_COPY_ROOM eth1_deposits, Node_eth1_counts
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
    mov     Node_db(%rbx), %rdi             # the Db, at its new room
    add     %rbx, %rdi
    lea     NodeRoom_db_slots(%rbp), %rsi
    mov     Node_db(%r12), %rdx
    add     %r12, %rdx
    call    lantern_db_copy
    test    %rax, %rax
    jnz     8f
    NODE_COPY_PART Node_blocks, NodeBlock__mem      # the entries of each part
    NODE_COPY_PART Node_checkpoints, NodeCheckpoint__mem
    NODE_COPY_PART Node_pow_blocks, POW_BLOCK_BYTES
    NODE_COPY_PART Node_peers, NodePeer__mem
    NODE_COPY_PART Node_messages, NodeMessage__mem
    NODE_COPY_PART Node_blobs, NodeBlob__mem
    NODE_COPY_PART Node_api, NodeApi__mem
    NODE_COPY_PART Node_pool, NodePool__mem
    NODE_COPY_PART Node_proposers, NodeProposer__mem
    NODE_COPY_PART Node_eth1_blocks, Eth1Block__mem
    NODE_COPY_PART Node_eth1_deposits, Eth1Deposit__mem
    NODE_COPY_PART Node_eth1_leaves, 32
    NODE_COPY_PART Node_eth1_counts, Eth1Count__mem
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
    cmp     $NODE_WORK_BLOCK_ATTESTATION, %rdi  # a block's vote: event_votes takes 1 more
    je      1f
    cmp     $NODE_WORK_BLOCK_SLASHING, %rdi
    jne     2f
1:  incq    Node_event_votes(%rbx)
2:  mov     8(%r15), %rax
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

/*
 * An action of kind rdi with the two ids rsi and rdx (STATE_COPY: source, new; the FREE kinds: rsi).
 * A BYTES_FREE of bytes a NodeApi entry sends goes to the entry instead: API_STREAM_OWN; so does a
 * STATE_FREE of the state a validator stream reads: API_STREAM_OWN_STATE. A STATE_FREE of the base
 * state is none. Uses rax, r10, r11.
 */
LOCAL_FUNCTION node_ids
    UNWIND_END_PROLOGUE
    cmp     $NODE_ACT_STATE_FREE, %rdi
    jne     5f
    cmp     Node_anchor_state_id(%rbx), %rsi    # the base state stays for the node's life
    jne     40f
    ret
40: PART    %rax, %r10, %rbx, Node_api
4:  test    %r10, %r10
    jz      3f
    cmpq    $0, NodeApi_connection(%rax)
    je      41f
    cmp     %rsi, NodeApi_state(%rax)
    jne     41f
    mov     NodeApi_flags(%rax), %r11
    test    $API_STREAM_OWN_STATE, %r11
    jnz     41f                             # API_STREAM_OWN_STATE: its own state already
    or      $API_STREAM_OWN_STATE, %r11
    mov     %r11, NodeApi_flags(%rax)
    ret
41: add     $NodeApi__mem, %rax
    dec     %r10
    jmp     4b
5:  cmp     $NODE_ACT_BYTES_FREE, %rdi
    jne     3f
    PART    %rax, %r10, %rbx, Node_pool     # bytes a pool entry keeps stay
6:  test    %r10, %r10
    jz      7f
    cmpq    $0, NodePool_topic(%rax)
    je      61f
    cmp     %rsi, NodePool_data_id(%rax)
    jne     61f
    ret
61: add     $NodePool__mem, %rax
    dec     %r10
    jmp     6b
7:  PART    %rax, %r10, %rbx, Node_api
1:  test    %r10, %r10
    jz      3f
    cmpq    $0, NodeApi_connection(%rax)
    je      2f
    cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%rax)  # a produceBlockV3 in its folds: the pool bytes of its fold in flight
    jne     11f
    cmpq    $NODE_PRODUCE_FOLD, NodeApi_member(%rax)
    jne     2f
    cmp     %rsi, NodeApi_root(%rax)
    jne     2f
    orq     $API_STREAM_PRODUCE_OWN, NodeApi_flags(%rax)
    ret
11: cmp     %rsi, NodeApi_data(%rax)
    jne     2f
    mov     NodeApi_flags(%rax), %r11
    test    $API_STREAM_OWN, %r11
    jnz     2f                              # API_STREAM_OWN: its own bytes already
    or      $API_STREAM_OWN, %r11
    mov     %r11, NodeApi_flags(%rax)
    ret
2:  add     $NodeApi__mem, %rax
    dec     %r10
    jmp     1b
3:
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

/* ------------------------------------------------------------ the pool (node.md) */

/*
 * rax = 1 when the bytes rsi (rdx bytes) of the topic rdi, of the fork rcx, join the pool: a
 * voluntary_exit, proposer_slashing, attester_slashing, bls_to_execution_change or
 * beacon_attestation (with the slot, committee index and member at r8), in the first free entry,
 * for an attestation one below 3/4 of the pool's capacity; else 0. Uses r9, r10, r11.
 */
LOCAL_FUNCTION node_pool_add
    UNWIND_END_PROLOGUE
    cmp     $GOSSIP_VOLUNTARY_EXIT, %rdi
    je      1f
    cmp     $GOSSIP_PROPOSER_SLASHING, %rdi
    je      1f
    cmp     $GOSSIP_ATTESTER_SLASHING, %rdi
    je      1f
    cmp     $GOSSIP_BEACON_ATTESTATION, %rdi
    je      1f
    cmp     $GOSSIP_SYNC_COMMITTEE, %rdi
    je      1f
    cmp     $GOSSIP_BLS_TO_EXECUTION_CHANGE, %rdi
    jne     8f
1:  mov     Node_p2p_out(%rbx), %rax        # the capacity, for an attestation or a sync message 3/4 of it
    sub     Node_pool(%rbx), %rax
    shr     $6, %rax
    cmp     $GOSSIP_BEACON_ATTESTATION, %rdi
    je      12f
    cmp     $GOSSIP_SYNC_COMMITTEE, %rdi
    jne     11f
12: lea     (%rax,%rax,2), %rax
    shr     $2, %rax
11: PART    %r9, %r10, %rbx, Node_pool
    xor     %r11d, %r11d
2:  cmp     %r10, %r11
    jae     3f
    cmp     %rax, %r11
    jae     8f
    cmpq    $0, NodePool_topic(%r9)
    je      4f
    add     $NodePool__mem, %r9
    inc     %r11
    jmp     2b
3:  cmp     %rax, %r10                      # past the count: one more within the capacity
    jae     8f
    inc     %r10
    mov     %r10, (Node_pool + 8)(%rbx)
4:  mov     %rdi, NodePool_topic(%r9)
    movq    $NODE_POOL_KEPT, NodePool_state(%r9)
    mov     %rsi, NodePool_data_id(%r9)
    mov     %rdx, NodePool_length(%r9)
    mov     %rcx, NodePool_fork(%r9)
    movq    $0, NodePool_slot(%r9)
    movq    $0, NodePool_index(%r9)
    movq    $0, NodePool_member(%r9)
    cmp     $GOSSIP_BEACON_ATTESTATION, %rdi    # an attestation's or a sync message's slot, index and member
    je      6f
    cmp     $GOSSIP_SYNC_COMMITTEE, %rdi
    jne     5f
6:  mov     (%r8), %rax
    mov     %rax, NodePool_slot(%r9)
    mov     8(%r8), %rax
    mov     %rax, NodePool_index(%r9)
    mov     16(%r8), %rax
    mov     %rax, NodePool_member(%r9)
5:  mov     $1, %eax
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION node_pool_add
.if NodePool__mem != 64
.error "node_pool_add: the capacity takes NodePool__mem as 2^6"
.endif

/*
 * The pool entry rdi goes: it is free (topic 0), the pool's count drops past the free entries at
 * its end, and its bytes get a NODE_ACT_BYTES_FREE.
 */
LOCAL_FUNCTION node_pool_drop
    FRAME 0
    mov     NodePool_data_id(%rdi), %rsi
    movq    $0, NodePool_topic(%rdi)
    PART    %rax, %r10, %rbx, Node_pool
1:  test    %r10, %r10
    jz      2f
    lea     -1(%r10), %rcx
    imul    $NodePool__mem, %rcx, %rdx
    cmpq    $0, NodePool_topic(%rax,%rdx)
    jne     2f
    mov     %rcx, %r10
    jmp     1b
2:  mov     %r10, (Node_pool + 8)(%rbx)
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    node_ids
    UNFRAME 0
END_FUNCTION node_pool_drop

/*
 * At a new head, each attestation of the pool whose slot's epoch + 1 is below the epoch of the
 * store rbp's slot goes, and each sync committee message whose slot + 1 is below that slot; then
 * each other entry in NODE_POOL_KEPT gets a NODE_WORK_POOL_CHECK with the head's post-state rdi,
 * and takes NODE_POOL_CHECKING; with rdi = 0, none. Locals: the state, the index, the epoch, the
 * slot.
 */
LOCAL_FUNCTION node_pool_checks
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, 24(%rsp)
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, 16(%rsp)
    movq    $0, 8(%rsp)
5:  mov     8(%rsp), %r8
    PART    %rax, %r10, %rbx, Node_pool
    cmp     %r10, %r8
    jae     6f
    imul    $NodePool__mem, %r8, %rdx
    lea     (%rax,%rdx), %rdi
    cmpq    $GOSSIP_SYNC_COMMITTEE, NodePool_topic(%rdi)  # a sync message: its slot + 1 below the store's slot
    jne     71f
    mov     NodePool_slot(%rdi), %rax
    inc     %rax
    cmp     24(%rsp), %rax
    jae     7f
    call    node_pool_drop
    jmp     7f
71: cmpq    $GOSSIP_BEACON_ATTESTATION, NodePool_topic(%rdi)
    jne     7f
    mov     NodePool_slot(%rdi), %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    inc     %rax
    cmp     16(%rsp), %rax
    jae     7f
    call    node_pool_drop
7:  incq    8(%rsp)
    jmp     5b
6:  cmpq    $0, (%rsp)
    je      9f
    movq    $0, 8(%rsp)
1:  mov     8(%rsp), %r8
    PART    %rax, %r10, %rbx, Node_pool
    cmp     %r10, %r8
    jae     9f
    imul    $NodePool__mem, %r8, %rdx
    add     %rdx, %rax
    cmpq    $0, NodePool_topic(%rax)
    je      2f
    cmpq    $GOSSIP_BEACON_ATTESTATION, NodePool_topic(%rax)
    je      2f
    cmpq    $GOSSIP_SYNC_COMMITTEE, NodePool_topic(%rax)
    je      2f
    cmpq    $NODE_POOL_KEPT, NodePool_state(%rax)
    jne     2f
    movq    $NODE_POOL_CHECKING, NodePool_state(%rax)
    mov     $NODE_WORK_POOL_CHECK, %edi
    mov     (%rsp), %rsi
    xor     %edx, %edx
    mov     NodePool_data_id(%rax), %rcx
    mov     NodePool_topic(%rax), %r9
    call    node_work
2:  incq    8(%rsp)
    jmp     1b
9:  UNFRAME 32
END_FUNCTION node_pool_checks

/*
 * The NODE_EV_WORK_DONE rdi of a NODE_WORK_POOL_CHECK, of the entry at index target in
 * NODE_POOL_CHECKING with its bytes: LANTERN_VALID, it takes NODE_POOL_KEPT; else it goes.
 */
LOCAL_FUNCTION node_pool_check_done
    FRAME 0
    mov     NodeAction_target(%rdi), %rcx
    PART    %rax, %r10, %rbx, Node_pool
    cmp     %r10, %rcx
    jae     9f
    imul    $NodePool__mem, %rcx, %rcx
    add     %rcx, %rax
    cmpq    $0, NodePool_topic(%rax)
    je      9f
    cmpq    $NODE_POOL_CHECKING, NodePool_state(%rax)
    jne     9f
    mov     NodePool_data_id(%rax), %rcx
    cmp     NodeAction_data(%rdi), %rcx
    jne     9f
    cmpq    $0, NodeEvent_result(%rdi)
    jne     1f
    movq    $NODE_POOL_KEPT, NodePool_state(%rax)
    jmp     9f
1:  mov     %rax, %rdi
    call    node_pool_drop
9:  UNFRAME 0
END_FUNCTION node_pool_check_done

/* rax = the slot of the block of the store's finalized root, or 2^64 - 1 when the node keeps none. Uses rcx, rdx, r11, xmm0-xmm2. */
LOCAL_FUNCTION node_f_slot
    FRAME 0
    lea     (Store_finalized_checkpoint + 8)(%rbp), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      1f
    mov     NodeBlock_slot(%rdx), %rax
1:  UNFRAME 0
END_FUNCTION node_f_slot

/*
 * rax = the post-state again of the imported block entry rdi above F's slot, or 0 (node.md): the
 * path up to its nearest ancestor with a post-state, a copy of that post-state, then for each block
 * of the path from the ancestor's child, in slot order, the copy across the fork boundaries to its
 * slot and a REPLAY work; the block takes the copy as its post-state. The path is a list at the end
 * of scratch, at most 8 bytes for each NodeBlock entry. r12 the block, r13 the list, S7 its count,
 * S8 the copy, S9 the ancestor's post-state, S10 the copy's slot. Locals: L the scratch size, L+8
 * an entry.
 */
LOCAL_FUNCTION node_rebuild
    ENTER 16
    mov     %rdi, %r12
    mov     (%r14), %rax
    mov     %rax, L(%rsp)
    mov     (Node_blocks + 8)(%rbx), %rcx
    shl     $3, %rcx
    sub     %rcx, %rax
    jb      8f
    mov     %rax, (%r14)
    lea     (%r14,%rax), %r13
    movq    $0, S7(%rsp)
    mov     %r12, %rdi
1:  cmpq    $0, NodeBlock_data_id(%rdi)     # each block of the path keeps its bytes
    je      7f
    mov     S7(%rsp), %rcx
    cmp     (Node_blocks + 8)(%rbx), %rcx
    jae     7f
    mov     %rdi, (%r13,%rcx,8)
    incq    S7(%rsp)
    add     $NodeBlock_parent_root, %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      7f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     7f
    mov     NodeBlock_state_id(%rdx), %rax
    mov     %rax, S9(%rsp)
    mov     %rdx, %rdi
    test    %rax, %rax
    jz      1b
    mov     NodeBlock_slot(%rdx), %rax      # the ancestor: a copy of its post-state
    mov     %rax, S10(%rsp)
    call    node_new_id
    mov     %rax, S8(%rsp)
    mov     $NODE_ACT_STATE_COPY, %edi
    mov     S9(%rsp), %rsi
    mov     %rax, %rdx
    call    node_ids
2:  cmpq    $0, S7(%rsp)                    # each block, from the ancestor's child
    je      3f
    decq    S7(%rsp)
    mov     S7(%rsp), %rcx
    mov     (%r13,%rcx,8), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     S8(%rsp), %rdi
    mov     S9(%rsp), %rsi
    mov     S10(%rsp), %rdx
    mov     NodeBlock_slot(%rax), %rcx
    call    node_cross
    mov     %rax, S8(%rsp)
    mov     (L + 8)(%rsp), %rax
    mov     NodeBlock_slot(%rax), %rcx
    mov     %rcx, S10(%rsp)
    mov     $NODE_WORK_REPLAY, %edi
    mov     S8(%rsp), %rsi
    xor     %edx, %edx
    mov     NodeBlock_data_id(%rax), %rcx
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    call    node_work
    jmp     2b
3:  mov     S8(%rsp), %rax
    mov     %rax, NodeBlock_state_id(%r12)
    mov     L(%rsp), %rcx
    mov     %rcx, (%r14)
    LEAVE 16
7:  mov     L(%rsp), %rcx
    mov     %rcx, (%r14)
8:  xor     %eax, %eax
    LEAVE 16
END_FUNCTION node_rebuild

/*
 * The post-states the node can rebuild go (node.md): each imported block above F's slot with a
 * post-state, other than the head and the justified root, whose slot is not the first of its epoch
 * and is NODE_STATE_KEEP_SLOTS or more before the store's, with an imported child and every
 * imported child of its epoch (with NODE_FLAG_FEW_STATES, no slot or epoch rule): a STATE_FREE, and
 * state_id 0. Then a head with no post-state above F's slot gets it again. r12 the entry, r13 the
 * entries left, S7 the store's slot, S8 F's slot, S9 a child, S10 the children. Locals: L the
 * entries left to look at.
 */
LOCAL_FUNCTION node_shed
    ENTER 16
    call    node_f_slot
    mov     %rax, S8(%rsp)
    cmp     $-1, %rax
    je      9f
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, S7(%rsp)
    PART    %r12, %r13, %rbx, Node_blocks
1:  test    %r13, %r13
    jz      7f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%r12)
    jne     6f
    cmpq    $0, NodeBlock_state_id(%r12)
    je      6f
    mov     NodeBlock_slot(%r12), %rax
    cmp     S8(%rsp), %rax
    jbe     6f
    testq   $NODE_FLAG_FEW_STATES, Node_flags(%rbx)
    jnz     11f
    test    $(SLOTS_PER_EPOCH - 1), %rax
    jz      6f
    add     $NODE_STATE_KEEP_SLOTS, %rax
    cmp     S7(%rsp), %rax
    jae     6f
11: lea     Node_head_root(%rbx), %rcx
    NE32    %r12, %rcx, 2f
    jmp     6f
2:  lea     (Store_justified_checkpoint + 8)(%rbp), %rcx
    NE32    %r12, %rcx, 3f
    jmp     6f
3:  PART    %rax, %rcx, %rbx, Node_blocks   # its imported children: one at least, all of its epoch
    mov     %rax, S9(%rsp)
    mov     %rcx, L(%rsp)
    movq    $0, S10(%rsp)
4:  cmpq    $0, L(%rsp)
    je      5f
    decq    L(%rsp)
    mov     S9(%rsp), %rax
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rax)
    jne     41f
    lea     NodeBlock_parent_root(%rax), %rcx
    NE32    %rcx, %r12, 41f
    incq    S10(%rsp)
    testq   $NODE_FLAG_FEW_STATES, Node_flags(%rbx)
    jnz     41f
    mov     S9(%rsp), %rax
    mov     NodeBlock_slot(%rax), %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, %rsi
    mov     NodeBlock_slot(%r12), %rax
    xor     %edx, %edx
    div     %rcx
    cmp     %rax, %rsi
    jne     6f
41: addq    $NodeBlock__mem, S9(%rsp)
    jmp     4b
5:  cmpq    $0, S10(%rsp)
    je      6f
    mov     $NODE_ACT_STATE_FREE, %edi
    mov     NodeBlock_state_id(%r12), %rsi
    xor     %edx, %edx
    call    node_ids
    movq    $0, NodeBlock_state_id(%r12)
6:  add     $NodeBlock__mem, %r12
    dec     %r13
    jmp     1b
7:  lea     Node_head_root(%rbx), %rdi      # a head with no post-state above F's slot: it again
    call    node_find_block
    cmp     $-1, %rax
    je      9f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     9f
    cmpq    $0, NodeBlock_state_id(%rdx)
    jne     9f
    mov     NodeBlock_slot(%rdx), %rax
    cmp     S8(%rsp), %rax
    jbe     9f
    mov     %rdx, %rdi
    call    node_rebuild
9:  LEAVE 16
END_FUNCTION node_shed

/*
 * The copy rdi of the state of id rsi, at slot rdx, crosses each fork boundary up to the fork of
 * slot rcx (node.md): for each, a SLOTS work to the next fork's first slot when the copy is before
 * it, a copy of the state rsi as the upgrade's buffer, an UPGRADE work and a STATE_FREE of the copy
 * before. rax = the id of the last copy. r12 the copy's slot, r13 the upgrade's buffer, S7 the
 * copy, S8 the state rsi, S9 the fork, S10 the last fork.
 */
LOCAL_FUNCTION node_cross
    ENTER 0
    mov     %rdi, S7(%rsp)
    mov     %rsi, S8(%rsp)
    mov     %rdx, %r12
    mov     %rcx, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, S10(%rsp)
    mov     %r12, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, S9(%rsp)
1:  mov     S9(%rsp), %rax
    cmp     S10(%rsp), %rax
    jae     9f
    inc     %rax
    mov     %rax, S9(%rsp)
    shl     $4, %rax                        # the next fork's first slot
    mov     Node_config(%rbx,%rax), %rax
    imul    $SLOTS_PER_EPOCH, %rax, %rax
    cmp     %rax, %r12
    jae     2f
    mov     %rax, %r12
    mov     $NODE_WORK_SLOTS, %edi
    mov     S7(%rsp), %rsi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    mov     %r12, %r9
    call    node_work
2:  call    node_new_id                     # the upgrade's buffer: a copy of the state
    mov     %rax, %r13
    mov     $NODE_ACT_STATE_COPY, %edi
    mov     S8(%rsp), %rsi
    mov     %r13, %rdx
    call    node_ids
    mov     $NODE_WORK_UPGRADE, %edi
    mov     S7(%rsp), %rsi
    mov     %r13, %rdx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    mov     S9(%rsp), %r9
    call    node_work
    mov     $NODE_ACT_STATE_FREE, %edi
    mov     S7(%rsp), %rsi
    xor     %edx, %edx
    call    node_ids
    mov     %r13, S7(%rsp)
    jmp     1b
9:  mov     S7(%rsp), %rax
    LEAVE 0
END_FUNCTION node_cross

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
    test    %rax, %rax                      # no post-state: above F's slot, rebuilt first; an ancestor of F keeps none
    jnz     2f
    mov     %rdx, S10(%rsp)
    call    node_f_slot
    mov     S10(%rsp), %rdx
    cmp     %rax, NodeBlock_slot(%rdx)
    jbe     9f
    mov     %rdx, %rdi
    call    node_rebuild
    test    %rax, %rax
    jz      9f
    mov     S10(%rsp), %rdx
2:  mov     %rax, S8(%rsp)
    mov     NodeBlock_slot(%rdx), %rax
    mov     %rax, S9(%rsp)
    call    node_new_id
    mov     %rax, S7(%rsp)
    mov     $NODE_ACT_STATE_COPY, %edi
    mov     S8(%rsp), %rsi
    mov     %rax, %rdx
    call    node_ids
    mov     S7(%rsp), %rdi                  # across the forks to the epoch's first slot
    mov     S8(%rsp), %rsi
    mov     S9(%rsp), %rdx
    imul    $SLOTS_PER_EPOCH, %r12, %rcx
    call    node_cross
    mov     %rax, S7(%rsp)
    call    node_new_checkpoint             # the entry
    mov     %rax, %r8
    mov     %r12, NodeCheckpoint_epoch(%rdi)
    lea     NodeCheckpoint_root(%rdi), %rax
    COPY32  %rax, %r13
    mov     S7(%rsp), %rax
    mov     %rax, NodeCheckpoint_state_id(%rdi)
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
    cmpq    $0, NodeBlock_state_id(%rdx)    # no post-state: above F's slot, rebuilt at the import; else an ancestor of F, no descendant of it
    jne     2f
    mov     NodeBlock_slot(%rdx), %rax
    mov     %rax, S8(%rsp)
    call    node_f_slot
    cmp     %rax, S8(%rsp)
    jbe     8f
2:  testq   $NODE_FLAG_ENGINE, Node_flags(%rbx)
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
    test    %rax, %rax                      # no post-state above F's slot: rebuilt first
    jnz     2f
    mov     %rdx, S9(%rsp)
    call    node_f_slot
    mov     S9(%rsp), %rdx
    cmp     %rax, NodeBlock_slot(%rdx)
    jbe     8f
    mov     %rdx, %rdi
    call    node_rebuild
    test    %rax, %rax
    jz      8f
    mov     S9(%rsp), %rdx
2:  mov     %rax, S7(%rsp)
    mov     NodeBlock_slot(%rdx), %rax
    mov     %rax, S8(%rsp)
    call    node_new_id
    mov     %rax, NodeBlock_state_id(%r13)
    mov     %rax, %rdx
    mov     $NODE_ACT_STATE_COPY, %edi
    mov     S7(%rsp), %rsi
    call    node_ids
    mov     NodeBlock_state_id(%r13), %rdi  # across the forks from the parent's slot to the block's
    mov     S7(%rsp), %rsi
    mov     S8(%rsp), %rdx
    mov     NodeBlock_slot(%r13), %rcx
    call    node_cross
    mov     %rax, NodeBlock_state_id(%r13)
    movq    $NODE_BLOCK_IMPORTING, NodeBlock_status(%r13)
    mov     $NODE_WORK_IMPORT_BLOCK, %edi
    mov     NodeBlock_state_id(%r13), %rsi
    xor     %edx, %edx
    mov     NodeBlock_data_id(%r13), %rcx
    mov     %r12, %r8
    xor     %r9d, %r9d
    call    node_work
9:  LEAVE 0
8:  movq    $NODE_BLOCK_INVALID, NodeBlock_status(%r13)     # its parent is an ancestor of the finalized block
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     NodeBlock_data_id(%r13), %rsi
    xor     %edx, %edx
    call    node_ids
    movq    $0, NodeBlock_data_id(%r13)
    LEAVE 0
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
    call    node_produce_engine             # a produceBlockV3 waiting for its payload goes first
    test    %rax, %rax
    jnz     9f
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
3:  mov     S7(%rsp), %rdi                  # a payload's preparation, when it is due
    call    node_prepare
    test    %rax, %rax
    jnz     9f
    testq   $NODE_FLAG_FCU, Node_flags(%rbx)
    jz      50f
    mov     S7(%rsp), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_BELLATRIX, %rax
    jb      50f
    andq    $~NODE_FLAG_FCU, Node_flags(%rbx)
    movq    $ENGINE_METHOD_FORKCHOICE_UPDATED, Node_engine_method(%rbx)
    movq    $0, Node_engine_target(%rbx)
    mov     Node_engine_id(%rbx), %r9
    incq    Node_engine_id(%rbx)
    mov     $NODE_WORK_FORKCHOICE, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    node_work
    LEAVE 0
50: call    node_eth1_next                  # then the eth1 follower's call
9:  LEAVE 0
END_FUNCTION node_engine_next

/*
 * The preparation of a payload for slot rdi + 1, rdi the store's slot, when it is due (node.md,
 * Payload preparation): a copy of the head's post-state at that slot, a PREPARE_PAYLOAD work of
 * it with the next engine id, and the copy's STATE_FREE. rax = 1 when it went, else 0. r12 the
 * head's entry, r13 the copy, S7 the copy's slot, S8 a fork, S9 the store's slot, S10 the slot.
 */
LOCAL_FUNCTION node_prepare
    ENTER 0
    mov     %rdi, S9(%rsp)
    inc     %rdi
    mov     %rdi, S10(%rsp)
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_BELLATRIX, %rax
    jb      8f
    mov     S9(%rsp), %rax                  # a proposers entry past the store's epoch
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    PART    %rsi, %rcx, %rbx, Node_proposers
1:  test    %rcx, %rcx
    jz      8f
    cmp     %rax, NodeProposer_until_epoch(%rsi)
    ja      2f
    add     $NodeProposer__mem, %rsi
    dec     %rcx
    jmp     1b
2:  lea     Node_head_root(%rbx), %rdi      # the head's block, with its post-state
    call    node_find_block
    cmp     $-1, %rax
    je      8f
    mov     %rdx, %r12
    cmpq    $0, NodeBlock_state_id(%r12)
    je      8f
    mov     S9(%rsp), %rax                  # a head of the slot, or the slot's attestation due time
    cmp     %rax, NodeBlock_slot(%r12)
    je      3f
    mov     (Node_config + CONFIG_SLOT_DURATION_MS)(%rbx), %rcx
    mul     %rcx
    mov     %rax, %r8
    mov     (Node_config + CONFIG_ATTESTATION_DUE_BPS)(%rbx), %rax
    mul     %rcx
    mov     $10000, %ecx
    xor     %edx, %edx
    div     %rcx
    add     %r8, %rax
    add     Store_genesis_time_ms(%rbp), %rax
    cmp     %rax, Node_time_ms(%rbx)
    jb      8f
3:  mov     S10(%rsp), %rax                 # not this slot on this head yet
    cmp     %rax, Node_payload_slot(%rbx)
    jne     4f
    lea     Node_payload_root(%rbx), %rdi
    lea     Node_head_root(%rbx), %rsi
    NE32    %rdi, %rsi, 4f
    jmp     8f
4:  mov     S10(%rsp), %rdi
    xor     %esi, %esi
    call    node_prepare_go
    LEAVE 0
8:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION node_prepare

/*
 * With no engine call in flight, the call of the first produceBlockV3 entry in
 * NODE_PRODUCE_PAYLOAD (node.md, Block production): a GET_PAYLOAD of payload_id when the payload
 * of its slot on the head is NODE_PAYLOAD_READY; else a forced preparation of its slot, once (a
 * second that ends with no payloadId: 500). rax = 1 when a call went. r12 an entry, r13 its index,
 * S7 the count.
 */
LOCAL_FUNCTION node_produce_engine
    ENTER 0
    PART    %r12, %rax, %rbx, Node_api
    mov     %rax, S7(%rsp)
    xor     %r13d, %r13d
1:  cmp     S7(%rsp), %r13
    jae     8f
    cmpq    $0, NodeApi_connection(%r12)
    je      2f
    cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%r12)
    jne     2f
    cmpq    $NODE_PRODUCE_PAYLOAD, NodeApi_member(%r12)
    je      3f
2:  add     $NodeApi__mem, %r12
    inc     %r13
    jmp     1b
3:  mov     NodeApi_slot(%r12), %rax        # the payload of its slot on the head
    cmp     %rax, Node_payload_slot(%rbx)
    jne     6f
    lea     Node_payload_root(%rbx), %rdi
    lea     Node_head_root(%rbx), %rsi
    NE32    %rdi, %rsi, 6f
    cmpq    $NODE_PAYLOAD_READY, Node_payload_status(%rbx)
    je      4f
    testq   $API_STREAM_PRODUCE_FORCED, NodeApi_flags(%r12)  # no payloadId: a preparation of its own, else 500
    jz      6f
    mov     %r12, %rdi
    mov     $500, %esi
    call    node_produce_fail
    xor     %eax, %eax
    LEAVE 0
4:  orq     $API_STREAM_BUSY, NodeApi_flags(%r12)  # busy with its getPayload
    movq    $ENGINE_METHOD_GET_PAYLOAD, Node_engine_method(%rbx)
    mov     %r13, Node_engine_target(%rbx)
    mov     Node_engine_id(%rbx), %r9
    incq    Node_engine_id(%rbx)
    mov     $NODE_WORK_GET_PAYLOAD, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    xor     %ecx, %ecx
    mov     %r13, %r8
    call    node_work
    mov     $1, %eax
    LEAVE 0
6:  orq     $API_STREAM_PRODUCE_FORCED, NodeApi_flags(%r12)
    mov     NodeApi_slot(%r12), %rdi
    mov     $1, %esi
    call    node_prepare_go
    test    %rax, %rax
    jnz     7f
    mov     %r12, %rdi
    mov     $500, %esi
    call    node_produce_fail
    xor     %eax, %eax
    LEAVE 0
7:  mov     $1, %eax
    LEAVE 0
8:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION node_produce_engine

/*
 * The preparation of a payload for slot rdi on the head (node.md, Payload preparation), forced
 * with rsi = 1 (a fee recipient of zero bytes when the proposer has none): a copy of the head's
 * post-state at that slot, a PREPARE_PAYLOAD work of it with the next engine id and rsi as its
 * target, and the copy's STATE_FREE; it is the call in flight. rax = 1 when it went, 0 with no
 * head post-state. r12 the head's entry, r13 the copy; S7 the copy's slot, S8 a fork, S9 forced,
 * S10 the slot.
 */
LOCAL_FUNCTION node_prepare_go
    ENTER 0
    mov     %rdi, S10(%rsp)
    mov     %rsi, S9(%rsp)
    lea     Node_head_root(%rbx), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      8f
    mov     %rdx, %r12
    cmpq    $0, NodeBlock_state_id(%r12)
    je      8f
    mov     S10(%rsp), %rax
    mov     %rax, Node_payload_slot(%rbx)
    lea     Node_payload_root(%rbx), %rdi
    lea     Node_head_root(%rbx), %rsi
    COPY32  %rdi, %rsi
    movq    $NODE_PAYLOAD_PREPARING, Node_payload_status(%rbx)
    movq    $ENGINE_METHOD_FORKCHOICE_UPDATED, Node_engine_method(%rbx)
    movq    $1, Node_engine_target(%rbx)
    call    node_new_id                     # the copy, across the fork boundaries to the slot
    mov     %rax, %r13
    mov     $NODE_ACT_STATE_COPY, %edi
    mov     NodeBlock_state_id(%r12), %rsi
    mov     %r13, %rdx
    call    node_ids
    mov     %r13, %rdi
    mov     NodeBlock_state_id(%r12), %rsi
    mov     NodeBlock_slot(%r12), %rdx
    mov     S10(%rsp), %rcx
    call    node_cross
    mov     %rax, %r13
    mov     NodeBlock_slot(%r12), %rax      # its slot: the first of the slot's fork, when it crossed one
    mov     %rax, S7(%rsp)
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, S8(%rsp)
    mov     S10(%rsp), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     S8(%rsp), %rax
    jbe     5f
    shl     $4, %rax
    mov     Node_config(%rbx,%rax), %rax
    imul    $SLOTS_PER_EPOCH, %rax, %rax
    cmp     S7(%rsp), %rax
    jbe     5f
    mov     %rax, S7(%rsp)
5:  mov     S10(%rsp), %r9
    cmp     S7(%rsp), %r9
    jbe     6f
    mov     $NODE_WORK_SLOTS, %edi
    mov     %r13, %rsi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    node_work
6:  mov     $API_TOPIC_PAYLOAD_ATTRIBUTES, %edi  # target: 1 forced, + 2 with an entry of payload_attributes
    call    node_api_subscribed
    shl     $1, %rax
    or      %rax, S9(%rsp)
    mov     Node_engine_id(%rbx), %r9       # the work, of the call's id
    incq    Node_engine_id(%rbx)
    mov     $NODE_WORK_PREPARE_PAYLOAD, %edi
    mov     %r13, %rsi
    xor     %edx, %edx
    xor     %ecx, %ecx
    mov     S9(%rsp), %r8
    call    node_work
    mov     $NODE_ACT_STATE_FREE, %edi
    mov     %r13, %rsi
    xor     %edx, %edx
    call    node_ids
    mov     $1, %eax
    LEAVE 0
8:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION node_prepare_go

/*
 * The engine call in flight failed: an engine_newPayload's block takes NODE_BLOCK_PAYLOAD with
 * retry the store's slot + 1, an engine_forkchoiceUpdated sets NODE_FLAG_FCU again; engine_wait
 * becomes the slot + 1 and the call ends.
 */
LOCAL_FUNCTION node_engine_failed
    ENTER 0
    mov     Node_engine_method(%rbx), %rax  # an eth1 call: the follower waits for the next head poll
    cmp     $ENGINE_METHOD_ETH_BLOCK, %rax
    je      10f
    cmp     $ENGINE_METHOD_ETH_LOGS, %rax
    jne     11f
10: movq    $0, Node_engine_method(%rbx)
    mov     Node_time_ms(%rbx), %rax
    mov     %rax, Node_eth1_head_ms(%rbx)
    LEAVE 0
11: mov     %rbp, %rdi
    call    node_store_slot
    inc     %rax
    mov     %rax, Node_engine_wait(%rbx)
    mov     Node_engine_method(%rbx), %rax
    movq    $0, Node_engine_method(%rbx)
    cmp     $ENGINE_METHOD_FORKCHOICE_UPDATED, %rax
    jne     1f
    orq     $NODE_FLAG_FCU, Node_flags(%rbx)
    cmpq    $0, Node_engine_target(%rbx)    # a preparation's: again
    je      9f
    movq    $0, Node_payload_slot(%rbx)
    movq    $0, Node_payload_status(%rbx)
    LEAVE 0
1:  cmp     $ENGINE_METHOD_GET_PAYLOAD, %rax  # a getPayload's entry: 500
    jne     2f
    mov     Node_engine_target(%rbx), %rdi
    call    node_produce_fail_at
    LEAVE 0
2:  cmp     $ENGINE_METHOD_NEW_PAYLOAD, %rax
    jne     9f
    mov     Node_engine_target(%rbx), %rdi
    call    node_payload_retry
9:  LEAVE 0
END_FUNCTION node_engine_failed

/* The produceBlockV3 entry at index rdi, while it waits for its payload: 500. */
LOCAL_FUNCTION node_produce_fail_at
    FRAME 0
    PART    %rcx, %rax, %rbx, Node_api
    cmp     %rax, %rdi
    jae     9f
    imul    $NodeApi__mem, %rdi, %rdi
    add     %rcx, %rdi
    cmpq    $0, NodeApi_connection(%rdi)
    je      9f
    cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%rdi)
    jne     9f
    cmpq    $NODE_PRODUCE_PAYLOAD, NodeApi_member(%rdi)
    jne     9f
    mov     $500, %esi
    call    node_produce_fail
9:  UNFRAME 0
END_FUNCTION node_produce_fail_at

/*
 * The engine_getPayload body rdi (a ByteList in scratch r14, which stays short) with its
 * EngineResponse rsi, for the produceBlockV3 entry at engine_target in NODE_PRODUCE_PAYLOAD: its
 * result decoded by lantern_node_payload_result into a BYTES_PUT action, whose id the entry keeps
 * as filter_index before its fold; a result that does not decode: 500, and the action goes. r12
 * the body, r13 the entry; S7 the action, S8 its size. Locals: L a JsonFault (128).
 */
LOCAL_FUNCTION node_produce_payload
    ENTER 128
    mov     %rdi, %r12
    mov     Node_engine_target(%rbx), %rax
    PART    %r13, %rcx, %rbx, Node_api
    cmp     %rcx, %rax
    jae     9f
    imul    $NodeApi__mem, %rax, %rax
    add     %rax, %r13
    cmpq    $0, NodeApi_connection(%r13)
    je      9f
    cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%r13)
    jne     9f
    cmpq    $NODE_PRODUCE_PAYLOAD, NodeApi_member(%r13)
    jne     9f
    andq    $~API_STREAM_BUSY, NodeApi_flags(%r13)  # its call is done; the connection closed meanwhile: the entry ends
    testq   $API_STREAM_GONE, NodeApi_flags(%r13)
    jz      1f
    mov     %r13, %rdi
    call    node_produce_release
    mov     %r13, %rdi
    call    node_api_end
    LEAVE 128
1:  mov     EngineResponse_result_offset(%rsi), %rax     # the body becomes the result's bytes
    mov     EngineResponse_result_length(%rsi), %rcx
    add     %rax, 8(%r12)
    mov     %rcx, 16(%r12)
    lea     (48 + 1024 + 7)(%rcx), %rsi     # the action: room for the SSZ bytes, at most the text's + 1024
    and     $-8, %rsi
    mov     %rsi, S8(%rsp)
    mov     $NODE_ACT_BYTES_PUT, %edi
    call    node_act
    mov     %rax, S7(%rsp)
    call    node_new_id
    mov     S7(%rsp), %rcx
    mov     %rax, 16(%rcx)
    mov     S8(%rsp), %rax
    sub     $24, %rax
    mov     %rax, 24(%rcx)
    movq    $24, 32(%rcx)
    movq    $0, 40(%rcx)
    mov     NodeApi_slot(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r12, %rdi
    mov     %r14, %rsi
    mov     S7(%rsp), %rdx
    add     $24, %rdx
    lea     L(%rsp), %rcx
    FORK_CALL_BELLATRIX node_payload_result
    test    %rax, %rax
    jnz     8f
    mov     S7(%rsp), %rcx                  # the entry keeps the result, then folds
    mov     16(%rcx), %rax
    mov     %rax, NodeApi_filter_index(%r13)
    movq    $NODE_PRODUCE_FOLD, NodeApi_member(%r13)
    movq    $0, NodeApi_filter_slot(%r13)
    mov     %r13, %rdi
    call    node_produce_next
    LEAVE 128
8:  mov     S8(%rsp), %rax                  # no result: the action goes, and 500
    sub     %rax, 16(%r15)
    mov     %r13, %rdi
    mov     $500, %esi
    call    node_produce_fail
9:  LEAVE 128
END_FUNCTION node_produce_payload

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
 * Locals: L an HttpResponse (16), L+16 eof, L+24 the method, L+32 an EngineResponse (112), L+144 a
 * node, L+152 a status.
 */
LOCAL_FUNCTION node_engine_read
    ENTER 160
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
    andq    $~NODE_FLAG_EL_OFFLINE, Node_flags(%rbx)   # a whole response: the engine is online
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
    cmp     $ENGINE_METHOD_ETH_BLOCK, %r13  # the eth1 follower's calls: their result, with the body still in scratch
    je      43f
    cmp     $ENGINE_METHOD_ETH_LOGS, %r13
    jne     45f
43: mov     S8(%rsp), %rdi
    lea     (L + 32)(%rsp), %rsi
    call    node_eth1_answer
    mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    movq    $0, Node_engine_method(%rbx)
    jmp     9f
45: cmp     $ENGINE_METHOD_GET_PAYLOAD, %r13  # engine_getPayload: its result, decoded with the body still in scratch
    jne     44f
    mov     S8(%rsp), %rdi
    lea     (L + 32)(%rsp), %rsi
    call    node_produce_payload
    mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    movq    $0, Node_engine_method(%rbx)
    jmp     9f
44: mov     S7(%rsp), %rax
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
    mov     S9(%rsp), %rcx
    movq    $0, NodeBlock_data_id(%rcx)
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
40: cmpq    $0, Node_engine_target(%rbx)    # engine_forkchoiceUpdated of a preparation: its payloadId
    je      42f
    mov     $NODE_PAYLOAD_NONE, %eax
    cmpq    $0, (L + 32 + EngineResponse_has_payload_id)(%rsp)
    je      43f
    mov     (L + 32 + EngineResponse_payload_id)(%rsp), %rcx
    mov     %rcx, Node_payload_id(%rbx)
    mov     $NODE_PAYLOAD_READY, %eax
43: mov     %rax, Node_payload_status(%rbx)
42: lea     Node_head_root(%rbx), %rdi      # engine_forkchoiceUpdated: of the head
    call    node_store_find
    cmp     $-1, %rax
    je      9f
    mov     %rax, (L + 144)(%rsp)
    mov     (L + 32 + EngineResponse_status)(%rsp), %rcx
    cmp     $ENGINE_STATUS_VALID, %rcx
    jne     41f
    movq    $PAYLOAD_STATUS_VALID, (L + 152)(%rsp)
    mov     %rbp, %rdi
    lea     (L + 144)(%rsp), %rsi
    lea     (L + 152)(%rsp), %rdx
    lea     (L + 16)(%rsp), %rcx
    call    lantern_store_payload_status
    jmp     9f
41: cmp     $ENGINE_STATUS_INVALID, %rcx
    je      42f
    cmp     $ENGINE_STATUS_INVALID_BLOCK_HASH, %rcx
    jne     9f
42: mov     (L + 144)(%rsp), %rdi
    mov     %rdi, %rdx
    lea     (L + 32 + EngineResponse_latest_valid_hash)(%rsp), %rsi
    xor     %ecx, %ecx
    cmpq    $0, (L + 32 + EngineResponse_has_latest_valid_hash)(%rsp)
    cmove   %rcx, %rsi
    call    node_lvh
9:  LEAVE 160
6:  mov     S7(%rsp), %rax                  # part of a response: more bytes
    mov     %rax, (%r14)
    LEAVE 160
70: mov     %r12, %rdi                      # a failed call, its response read
    mov     (L + 8)(%rsp), %rsi
    call    node_engine_consume
7:  mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    call    node_engine_failed
8:  mov     Node_engine_in(%rbx), %rax      # the bytes left go
    movq    $0, 16(%rbx,%rax)
    LEAVE 160
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

/* rax = the index, rdi = the zeroed entry, of a NODE_BLOCK_FREE block or a new one at the end. Uses rcx. */
LOCAL_FUNCTION node_new_block
    UNWIND_END_PROLOGUE
    PART    %rdi, %rcx, %rbx, Node_blocks
    xor     %eax, %eax
1:  cmp     %rcx, %rax
    jae     2f
    cmpq    $NODE_BLOCK_FREE, NodeBlock_status(%rdi)
    je      3f
    add     $NodeBlock__mem, %rdi
    inc     %rax
    jmp     1b
2:  inc     %rcx
    mov     %rcx, (Node_blocks + 8)(%rbx)
3:  xor     %ecx, %ecx
4:  movq    $0, (%rdi,%rcx)
    add     $8, %rcx
    cmp     $NodeBlock__mem, %rcx
    jb      4b
    ret
END_FUNCTION node_new_block

/* rax = the index, rdi = the zeroed entry, of a NODE_BLOB_FREE sidecar or a new one at the end. Uses rcx. */
LOCAL_FUNCTION node_new_blob
    UNWIND_END_PROLOGUE
    PART    %rdi, %rcx, %rbx, Node_blobs
    xor     %eax, %eax
1:  cmp     %rcx, %rax
    jae     2f
    cmpq    $NODE_BLOB_FREE, NodeBlob_status(%rdi)
    je      3f
    add     $NodeBlob__mem, %rdi
    inc     %rax
    jmp     1b
2:  inc     %rcx
    mov     %rcx, (Node_blobs + 8)(%rbx)
3:  xor     %ecx, %ecx
4:  movq    $0, (%rdi,%rcx)
    add     $8, %rcx
    cmp     $NodeBlob__mem, %rcx
    jb      4b
    ret
END_FUNCTION node_new_blob

/* rax = the index, rdi = the zeroed entry, of a free checkpoint (epoch 2^64 - 1) or a new one at the end. Uses rcx. */
LOCAL_FUNCTION node_new_checkpoint
    UNWIND_END_PROLOGUE
    PART    %rdi, %rcx, %rbx, Node_checkpoints
    xor     %eax, %eax
1:  cmp     %rcx, %rax
    jae     2f
    cmpq    $-1, NodeCheckpoint_epoch(%rdi)
    je      3f
    add     $NodeCheckpoint__mem, %rdi
    inc     %rax
    jmp     1b
2:  inc     %rcx
    mov     %rcx, (Node_checkpoints + 8)(%rbx)
3:  xor     %ecx, %ecx
4:  movq    $0, (%rdi,%rcx)
    add     $8, %rcx
    cmp     $NodeCheckpoint__mem, %rcx
    jb      4b
    ret
END_FUNCTION node_new_checkpoint

/* rax = 1 when a stream that serves lists the BufferId rdi at or after its next, else 0. Uses rcx, rdx, rsi, r8, r9. */
LOCAL_FUNCTION node_serving
    UNWIND_END_PROLOGUE
    xor     %eax, %eax
    test    %rdi, %rdi
    jz      9f
    PART    %rsi, %rcx, %rbx, Node_streams
1:  test    %rcx, %rcx
    jz      9f
    mov     NodeStream_state(%rsi), %rdx
    cmp     $NODE_STREAM_SERVE, %rdx
    je      2f
    cmp     $NODE_STREAM_SERVING, %rdx
    jne     4f
2:  mov     NodeStream_next(%rsi), %r8
    mov     (NodeStream_list + 16)(%rsi), %r9
    shr     $3, %r9
3:  cmp     %r9, %r8
    jae     4f
    cmp     NodeStream_request(%rsi,%r8,8), %rdi
    je      8f
    inc     %r8
    jmp     3b
4:  add     Node_stream_bytes(%rbx), %rsi
    dec     %rcx
    jmp     1b
8:  mov     $1, %eax
9:  ret
END_FUNCTION node_serving

/*
 * At a new finalized epoch of the store, lantern_store_prune; then the node keeps the finalized
 * block, the blocks of the store, and the bytes and sidecars of the finalized block's ancestors.
 * Their states go, and so do the other branches, the invalid and waiting blocks at or below the
 * finalized slot, and the checkpoints below the finalized epoch. Bytes a stream sends stay until
 * a later prune. r12 an entry, r13 the finalized slot, S7 i, S9 the finalized block.
 */
LOCAL_FUNCTION node_prune
    ENTER 0
    mov     Store_finalized_checkpoint(%rbp), %rax
    cmp     Node_pruned_epoch(%rbx), %rax
    jbe     99f
    mov     %rbp, %rdi
    mov     %r14, %rsi
    call    lantern_store_prune
    test    %rax, %rax
    jnz     99f
    mov     Store_finalized_checkpoint(%rbp), %rax
    mov     %rax, Node_pruned_epoch(%rbx)
    lea     (Store_finalized_checkpoint + 8)(%rbp), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      99f
    mov     %rdx, S9(%rsp)
    mov     NodeBlock_slot(%rdx), %r13
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)  # F with no post-state: it again first, while its ancestors keep theirs
    jne     5f
    cmpq    $0, NodeBlock_state_id(%rdx)
    jne     5f
    mov     %rdx, %rdi
    call    node_rebuild
5:  mov     S9(%rsp), %rdx
    lea     NodeBlock_parent_root(%rdx), %rdi       # its ancestors: their states go
1:  call    node_find_block
    cmp     $-1, %rax
    je      2f
    mov     %rdx, %r12
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%r12)
    jne     2f
    mov     NodeBlock_state_id(%r12), %rsi  # each, through those with none
    test    %rsi, %rsi
    jz      4f
    mov     $NODE_ACT_STATE_FREE, %edi
    xor     %edx, %edx
    call    node_ids
    movq    $0, NodeBlock_state_id(%r12)
4:  lea     NodeBlock_parent_root(%r12), %rdi
    jmp     1b
2:  mov     S9(%rsp), %rdi                  # with NODE_FLAG_DB, the archive
    call    node_archive
    movq    $0, S7(%rsp)                    # each other block
3:  mov     S7(%rsp), %rax
    cmp     (Node_blocks + 8)(%rbx), %rax
    jae     20f
    imul    $NodeBlock__mem, %rax, %r12
    add     Node_blocks(%rbx), %r12
    add     %rbx, %r12
    cmp     S9(%rsp), %r12
    je      19f
    mov     NodeBlock_status(%r12), %rax
    cmp     $NODE_BLOCK_IMPORTED, %rax
    jne     10f
    cmpq    $0, NodeBlock_state_id(%r12)
    jne     12f
    cmp     NodeBlock_slot(%r12), %r13      # none above the finalized slot: a descendant, or another branch
    jb      12f
    testq   $NODE_FLAG_DB, Node_flags(%rbx) # an ancestor: its bytes stay, but those in the Db go
    jz      19f
    mov     NodeBlock_slot(%r12), %rax
    cmp     Node_db_next_slot(%rbx), %rax
    jae     19f
    mov     NodeBlock_data_id(%r12), %rdi
    call    node_serving
    test    %rax, %rax
    jnz     19f
    jmp     15f
12: mov     %r12, %rdi
    call    node_store_find                 # a descendant: in the store
    cmp     $-1, %rax
    jne     19f
    mov     NodeBlock_data_id(%r12), %rdi   # another branch: its state and bytes go
    call    node_serving
    test    %rax, %rax
    jnz     19f
    mov     NodeBlock_state_id(%r12), %rsi
    test    %rsi, %rsi
    jz      15f
    mov     $NODE_ACT_STATE_FREE, %edi
    xor     %edx, %edx
    call    node_ids
    jmp     15f
10: cmp     $NODE_BLOCK_INVALID, %rax       # invalid or waiting, at or below the finalized slot
    je      11f
    cmp     $NODE_BLOCK_WAITING, %rax
    je      11f
    cmp     $NODE_BLOCK_BLOBS, %rax
    je      11f
    cmp     $NODE_BLOCK_PAYLOAD, %rax
    jne     19f
11: cmp     %r13, NodeBlock_slot(%r12)
    ja      19f
    mov     NodeBlock_data_id(%r12), %rdi
    call    node_serving
    test    %rax, %rax
    jnz     19f
15: mov     NodeBlock_data_id(%r12), %rsi   # the bytes go, and the entry is free
    test    %rsi, %rsi
    jz      16f
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    node_ids
16: mov     $-1, %rax
    mov     %rax, (%r12)
    mov     %rax, 8(%r12)
    mov     %rax, 16(%r12)
    mov     %rax, 24(%r12)
    mov     %rax, 32(%r12)
    mov     %rax, 40(%r12)
    mov     %rax, 48(%r12)
    mov     %rax, 56(%r12)
    mov     %rax, NodeBlock_slot(%r12)
    movq    $0, NodeBlock_data_id(%r12)
    movq    $0, NodeBlock_state_id(%r12)
    movq    $NODE_BLOCK_FREE, NodeBlock_status(%r12)
19: incq    S7(%rsp)
    jmp     3b
20: movq    $0, S7(%rsp)                    # each sidecar: invalid, or at or below the finalized slot and of no kept block
21: mov     S7(%rsp), %rax
    cmp     (Node_blobs + 8)(%rbx), %rax
    jae     30f
    imul    $NodeBlob__mem, %rax, %r12
    add     Node_blobs(%rbx), %r12
    add     %rbx, %r12
    mov     NodeBlob_status(%r12), %rax
    cmp     $NODE_BLOB_INVALID, %rax
    je      26f
    cmp     $NODE_BLOB_VALID, %rax
    jne     29f
    cmp     %r13, NodeBlob_slot(%r12)
    ja      29f
    mov     %r12, %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      25f
    cmpq    $NODE_BLOCK_BACKFILL, NodeBlock_status(%rdx)  # of a block of the backfill: it stays for it
    je      29f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     25f
    testq   $NODE_FLAG_DB, Node_flags(%rbx) # of a kept block: but those in the Db go
    jz      29f
    mov     NodeBlob_slot(%r12), %rax
    cmp     Node_db_next_slot(%rbx), %rax
    jae     29f
25: mov     NodeBlob_data_id(%r12), %rdi
    call    node_serving
    test    %rax, %rax
    jnz     29f
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     NodeBlob_data_id(%r12), %rsi
    xor     %edx, %edx
    call    node_ids
26: mov     $-1, %rax
    mov     %rax, (%r12)
    mov     %rax, 8(%r12)
    mov     %rax, 16(%r12)
    mov     %rax, 24(%r12)
    mov     %rax, NodeBlob_slot(%r12)
    movq    $0, NodeBlob_data_id(%r12)
    movq    $NODE_BLOB_FREE, NodeBlob_status(%r12)
29: incq    S7(%rsp)
    jmp     21b
30: movq    $0, S7(%rsp)                    # each checkpoint below the finalized epoch: its state goes; the anchor's goes with the anchor block
31: mov     S7(%rsp), %rax
    cmp     (Node_checkpoints + 8)(%rbx), %rax
    jae     99f
    imul    $NodeCheckpoint__mem, %rax, %r12
    add     Node_checkpoints(%rbx), %r12
    add     %rbx, %r12
    mov     Store_finalized_checkpoint(%rbp), %rax
    cmp     %rax, NodeCheckpoint_epoch(%r12)
    jae     39f
    mov     NodeCheckpoint_state_id(%r12), %rsi
    cmp     Node_anchor_state_id(%rbx), %rsi
    je      32f
    test    %rsi, %rsi
    jz      32f
    mov     $NODE_ACT_STATE_FREE, %edi
    xor     %edx, %edx
    call    node_ids
32: mov     $-1, %rax
    mov     %rax, NodeCheckpoint_epoch(%r12)
    mov     %rax, NodeCheckpoint_root(%r12)
    mov     %rax, (NodeCheckpoint_root + 8)(%r12)
    mov     %rax, (NodeCheckpoint_root + 16)(%r12)
    mov     %rax, (NodeCheckpoint_root + 24)(%r12)
    movq    $0, NodeCheckpoint_state_id(%r12)
39: incq    S7(%rsp)
    jmp     31b
99: LEAVE 0
END_FUNCTION node_prune

/* dst = the DbSlot of slot slot in the node's Db; to fail outside first_slot to end_slot. Uses rax, rcx. */
.macro DB_SLOT dst, slot, fail
    mov     Node_db(%rbx), %rax
    add     %rbx, %rax
    cmp     Db_end_slot(%rax), \slot
    jae     \fail
    mov     \slot, %rcx
    sub     Db_first_slot(%rax), %rcx
    jb      \fail
    imul    $DbSlot__mem, %rcx, %rcx
    add     Db_slots(%rax), %rcx
    lea     (%rax,%rcx), \dst
.endm

/* rax = the DbSlot of slot rdi in the node's Db when it holds a block of that slot, else 0. Uses rcx, rdx. */
LOCAL_FUNCTION node_db_slot
    UNWIND_END_PROLOGUE
    DB_SLOT %rdx, %rdi, 9f
    cmpq    $0, DbSlot_block(%rdx)
    je      9f
    mov     %rdx, %rax
    ret
9:  xor     %eax, %eax
    ret
END_FUNCTION node_db_slot

/* rax = the NODE_DB_REF of the Db record of the block of slot rdi, or 0. Uses rcx, rsi. */
LOCAL_FUNCTION node_db_block
    UNWIND_END_PROLOGUE
    DB_SLOT %rsi, %rdi, 9f
    mov     DbSlot_block(%rsi), %rax
    test    %rax, %rax
    jz      9f
    dec     %rax
    mov     %rdi, %rcx
    shr     $DB_SEGMENT_SHIFT, %rcx
    shl     $NODE_DB_SEGMENT_SHIFT, %rcx
    or      %rcx, %rax
    bts     $63, %rax
    ret
9:  xor     %eax, %eax
    ret
END_FUNCTION node_db_block

/*
 * rax = the NODE_DB_REF of the Db record of the sidecar of index rsi of slot rdi, or 0: at the
 * slot's first sidecar record, plus its size times the slot's indices below rsi. Uses rcx, rdx,
 * r8-r11.
 */
LOCAL_FUNCTION node_db_sidecar
    UNWIND_END_PROLOGUE
    cmp     $DB_SIDECAR_INDICES, %rsi
    jae     9f
    DB_SLOT %r8, %rdi, 9f
    bt      %rsi, DbSlot_indices(%r8)
    jnc     9f
    mov     DbSlot_indices(%r8), %r9
    mov     (DbSlot_indices + 8)(%r8), %r10
    cmp     $64, %rsi
    jae     1f
    mov     %rsi, %rcx
    mov     $1, %eax
    shl     %cl, %rax
    dec     %rax
    and     %rax, %r9
    xor     %r10d, %r10d
    jmp     2f
1:  lea     -64(%rsi), %rcx
    mov     $1, %eax
    shl     %cl, %rax
    dec     %rax
    and     %rax, %r10
2:  xor     %r11d, %r11d                    # the indices below it
3:  test    %r9, %r9
    jz      4f
    lea     -1(%r9), %rax
    and     %rax, %r9
    inc     %r11
    jmp     3b
4:  test    %r10, %r10
    jz      5f
    lea     -1(%r10), %rax
    and     %rax, %r10
    inc     %r11
    jmp     4b
5:  mov     DbSlot_sidecars(%r8), %r9
    dec     %r9
    mov     DbSlot_sidecar_end(%r8), %rax
    sub     %r9, %rax
    xor     %edx, %edx
    divq    DbSlot_sidecar_count(%r8)
    imul    %r11, %rax
    add     %r9, %rax
    mov     %rdi, %rcx
    shr     $DB_SEGMENT_SHIFT, %rcx
    shl     $NODE_DB_SEGMENT_SHIFT, %rcx
    or      %rcx, %rax
    bts     $63, %rax
    bts     $62, %rax
    ret
9:  xor     %eax, %eax
    ret
END_FUNCTION node_db_sidecar

/*
 * rax = the replay's base among the Db's state records (node.md, the replay) for the slot rdi: the
 * highest slot at or below it with a state record, from archive_first and above base_slot when
 * that is at most rdi, rdx = its DbSlot's state; rax = 2^64 - 1 with none. Uses rcx, rsi, r8-r11.
 */
LOCAL_FUNCTION node_archive_base
    UNWIND_END_PROLOGUE
    mov     Node_archive_first(%rbx), %r8
    cmp     $-1, %r8
    je      9f
    mov     Node_base_slot(%rbx), %r9
    cmp     %rdi, %r9
    ja      1f
    inc     %r9
    cmp     %r9, %r8
    cmovb   %r9, %r8
1:  mov     Node_db(%rbx), %rsi             # inside the Db's slots
    add     %rbx, %rsi
    mov     Db_first_slot(%rsi), %r10
    cmp     %r10, %r8
    cmovb   %r10, %r8
    mov     Db_end_slot(%rsi), %r11
    test    %r11, %r11
    jz      9f
    dec     %r11
    mov     %rdi, %r10
    cmp     %r11, %r10
    cmova   %r11, %r10
2:  cmp     %r8, %r10
    jb      9f
    DB_SLOT %rsi, %r10, 9f
    mov     DbSlot_state(%rsi), %rdx
    test    %rdx, %rdx
    jz      3f
    mov     %r10, %rax
    ret
3:  test    %r10, %r10
    jz      9f
    dec     %r10
    jmp     2b
9:  mov     $-1, %rax
    ret
END_FUNCTION node_archive_base

/*
 * The archive (node.md) of the finalized NodeBlock rdi at slot rsi, in the Db: with archive_slots
 * not 0, a post-state, archive_busy 0, and archive_slot 2^64 - 1 or below the slot by a run of
 * archive_slots, a NODE_ACT_DB_ARCHIVE of its post-state. r12 the block, r13 the slot.
 */
LOCAL_FUNCTION node_archive_queue
    ENTER 0
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     Node_archive_slots(%rbx), %rcx
    test    %rcx, %rcx
    jz      9f
    cmpq    $0, NodeBlock_state_id(%r12)
    je      9f
    cmpq    $0, Node_archive_busy(%rbx)
    jne     9f
    mov     Node_archive_slot(%rbx), %r8
    cmp     $-1, %r8
    je      1f
    mov     %r13, %rax
    xor     %edx, %edx
    div     %rcx
    mov     %rax, %r9
    mov     %r8, %rax
    xor     %edx, %edx
    div     %rcx
    cmp     %rax, %r9
    jbe     9f
1:  mov     $NODE_ACT_DB_ARCHIVE, %edi
    mov     $NODE_ACT_DB_ARCHIVE_SIZE, %esi
    call    node_act
    mov     NodeBlock_state_id(%r12), %rcx
    mov     %rcx, 16(%rax)
    mov     %r13, %rcx
    shr     $DB_SEGMENT_SHIFT, %rcx
    mov     %rcx, 24(%rax)
    xor     %edx, %edx                      # at the end of its state segment, or a new one
    cmp     Node_archive_segment(%rbx), %rcx
    jne     2f
    mov     Node_archive_end(%rbx), %rdx
2:  mov     %rdx, 32(%rax)
    mov     $DB_STATE, %ecx                 # the DbRecord: a full state at offset 0, else a diff
    mov     $DB_STATE_DIFF, %r8d
    test    %rdx, %rdx
    cmovnz  %r8, %rcx
    mov     %rcx, (40 + DbRecord_kind)(%rax)
    mov     %r13, (40 + DbRecord_slot)(%rax)
    movq    $0, (40 + DbRecord_index)(%rax)
    lea     (40 + DbRecord_root)(%rax), %rdi
    lea     NodeBlock_root(%r12), %rsi
    COPY32  %rdi, %rsi
    movq    $0, (40 + DbRecord_bytes)(%rax)
    movq    $0, (40 + DbRecord_bytes + 8)(%rax)
    movq    $0, (40 + DbRecord_length)(%rax)
    movq    $1, Node_archive_busy(%rbx)
9:  LEAVE 0
END_FUNCTION node_archive_queue

/*
 * NODE_EV_DB_ARCHIVE rdi (node.md, the archive): archive_busy 0; a record of kind not 0, of the
 * segment of its slot, goes in the index with lantern_db_add, and on LANTERN_OK the archive's
 * fields take it. r12 the event.
 */
LOCAL_FUNCTION node_archive_done
    ENTER 0
    mov     %rdi, %r12
    movq    $0, Node_archive_busy(%rbx)
    cmpq    $0, (32 + DbRecord_kind)(%r12)
    je      9f
    mov     (32 + DbRecord_slot)(%r12), %rax
    shr     $DB_SEGMENT_SHIFT, %rax
    cmp     16(%r12), %rax
    jne     9f
    mov     Node_db(%rbx), %rdi
    add     %rbx, %rdi
    lea     32(%r12), %rsi
    lea     24(%r12), %rdx
    call    lantern_db_add
    test    %rax, %rax
    jnz     9f
    mov     16(%r12), %rax
    mov     %rax, Node_archive_segment(%rbx)
    mov     (32 + DbRecord_length)(%r12), %rax
    add     $(DbRecord__mem + 7), %rax
    and     $-8, %rax
    add     24(%r12), %rax
    mov     %rax, Node_archive_end(%rbx)
    mov     (32 + DbRecord_slot)(%r12), %rax
    mov     %rax, Node_archive_slot(%rbx)
    cmp     Node_archive_first(%rbx), %rax
    jae     9f
    mov     %rax, Node_archive_first(%rbx)
9:  LEAVE 0
END_FUNCTION node_archive_done

/*
 * NODE_WORK_ARCHIVE_LOAD (node.md): (state rdi, the full record's bytes rsi or 0, the record's
 * bytes rdx, scratch rcx, node r8): rax = LANTERN_VALID, LANTERN_INVALID_ENCODING, or
 * LANTERN_BUFFER_TOO_SMALL with nothing changed. r12 the state, r13 the bytes, r14 scratch, r15
 * its size, rbp the node. Locals: L the patch's size.
 */
LOCAL_FUNCTION node_run_archive
    ENTER 16
    mov     %rdi, %r12
    mov     %rdx, %r13
    mov     %rcx, %r14
    mov     (%r14), %r15
    mov     %r8, %rbp
    test    %rsi, %rsi
    jz      2f
    cmpq    $8, 16(%r13)                    # a diff: the patch at the end of the scratch
    jb      7f
    mov     8(%r13), %rax
    mov     (%r13,%rax), %rax
    add     $(24 + 7), %rax
    jc      7f
    and     $-8, %rax
    mov     %rax, %rcx
    add     $64, %rcx
    jc      8f
    cmp     %r15, %rcx
    ja      8f
    mov     %r15, %rcx
    sub     %rax, %rcx
    mov     %rcx, (%r14)
    lea     (%r14,%rcx), %rdx
    mov     %rax, (%rdx)
    mov     %rsi, %rdi
    mov     %r13, %rsi
    lea     L(%rsp), %rcx
    mov     %rdx, %r13
    call    lantern_db_state_patch
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8f
    test    %rax, %rax
    jnz     7f
2:  cmpq    $48, 16(%r13)                   # the state's slot at bytes 40 to 47: its fork
    jb      7f
    mov     8(%r13), %rax
    add     %r13, %rax
    mov     40(%rax), %rdi
    lea     Node_config(%rbp), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    ADDRESS %rsi, node_upgrade_room
    mov     %r14, %rdx
    mov     %r12, %rcx
    FORK_CALL node_archive_state
    mov     %r15, (%r14)
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      9f
    mov     $LANTERN_INVALID_ENCODING, %ecx
    xor     %edx, %edx
    test    %rax, %rax
    cmovnz  %rcx, %rdx
    mov     %rdx, %rax
9:  LEAVE 16
8:  mov     %r15, (%r14)
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
7:  mov     %r15, (%r14)
    mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 16
END_FUNCTION node_run_archive

/* A DB_APPEND action: sidecars rdi, BufferId rsi, segment rdx, offset rcx, the DbRecord at r8. Uses rax, r10, xmm0. */
LOCAL_FUNCTION node_db_append
    UNWIND_END_PROLOGUE
    mov     8(%r15), %rax
    add     %r15, %rax
    mov     16(%r15), %r10
    add     %r10, %rax
    add     $NODE_ACT_DB_APPEND_SIZE, %r10
    mov     %r10, 16(%r15)
    movq    $NODE_ACT_DB_APPEND_SIZE, (%rax)
    movq    $NODE_ACT_DB_APPEND, 8(%rax)
    mov     %rsi, 16(%rax)
    mov     %rdx, 24(%rax)
    mov     %rdi, 32(%rax)
    mov     %rcx, 40(%rax)
    movdqu  (%r8), %xmm0
    movdqu  %xmm0, 48(%rax)
    movdqu  16(%r8), %xmm0
    movdqu  %xmm0, 64(%rax)
    movdqu  32(%r8), %xmm0
    movdqu  %xmm0, 80(%rax)
    movdqu  48(%r8), %xmm0
    movdqu  %xmm0, 96(%rax)
    movdqu  64(%r8), %xmm0
    movdqu  %xmm0, 112(%rax)
    ret
END_FUNCTION node_db_append

/*
 * rax = the end of the block segment rdi: db_block_end for db_block_segment, else backfill_end
 * for backfill_segment, else 0, a new segment. Uses rax only.
 */
LOCAL_FUNCTION node_seg_end
    UNWIND_END_PROLOGUE
    cmp     Node_db_block_segment(%rbx), %rdi
    jne     1f
    mov     Node_db_block_end(%rbx), %rax
    ret
1:  cmp     Node_backfill_segment(%rbx), %rdi
    jne     2f
    mov     Node_backfill_end(%rbx), %rax
    ret
2:  xor     %eax, %eax
    ret
END_FUNCTION node_seg_end

/* The NodeBlock entry rdi is free: its bytes go (a BYTES_FREE), root and parent_root all 0xff bytes. Locals: rsp+0 the entry. */
LOCAL_FUNCTION node_free_block
    FRAME 16
    mov     %rdi, 0(%rsp)
    mov     NodeBlock_data_id(%rdi), %rsi
    test    %rsi, %rsi
    jz      1f
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    node_ids
1:  mov     0(%rsp), %rdi
    pcmpeqd %xmm0, %xmm0
    movdqu  %xmm0, (%rdi)
    movdqu  %xmm0, 16(%rdi)
    movdqu  %xmm0, 32(%rdi)
    movdqu  %xmm0, 48(%rdi)
    movq    $-1, NodeBlock_slot(%rdi)
    movq    $0, NodeBlock_data_id(%rdi)
    movq    $0, NodeBlock_state_id(%rdi)
    movq    $NODE_BLOCK_FREE, NodeBlock_status(%rdi)
    UNFRAME 16
END_FUNCTION node_free_block

/*
 * With NODE_FLAG_DB, the backfill's blocks join the Db (node.md): while a block in
 * NODE_BLOCK_BACKFILL has the root backfill_root and a slot below backfill_slot, its record at the
 * end of the segment of its slot and a DB_APPEND; backfill_slot and backfill_root follow; the entry
 * is free. Then, with no backfill stream and no block in NODE_BLOCK_BF_CHECKING, the blocks left in
 * NODE_BLOCK_BACKFILL go. r12 an entry, r13 the entries left, S7 its segment. Locals: L a DbRecord
 * (80), L+80 the offset.
 */
LOCAL_FUNCTION node_backfill_link
    ENTER 96
    testq   $NODE_FLAG_DB, Node_flags(%rbx)
    jz      99f
1:  PART    %r12, %r13, %rbx, Node_blocks   # the next block of the chain
2:  test    %r13, %r13
    jz      20f
    cmpq    $NODE_BLOCK_BACKFILL, NodeBlock_status(%r12)
    jne     3f
    mov     NodeBlock_slot(%r12), %rax
    cmp     Node_backfill_slot(%rbx), %rax
    jae     3f
    lea     Node_backfill_root(%rbx), %rcx
    NE32    %r12, %rcx, 3f
    jmp     4f
3:  add     $NodeBlock__mem, %r12
    dec     %r13
    jmp     2b
4:  mov     %r12, %rdi                      # its sidecars first: else it waits, and the link ends
    call    node_lacks_sidecars
    test    %rax, %rax
    jnz     20f
    movq    $DB_BLOCK, L(%rsp)              # its record
    mov     NodeBlock_slot(%r12), %rax
    mov     %rax, (L + 8)(%rsp)
    movq    $0, (L + 16)(%rsp)
    lea     (L + 24)(%rsp), %rdi
    COPY32  %rdi, %r12
    mov     NodeBlock_length(%r12), %rax
    mov     %rax, (L + 72)(%rsp)
    add     $24, %rax
    mov     %rax, (L + 56)(%rsp)
    movq    $24, (L + 64)(%rsp)
    mov     NodeBlock_slot(%r12), %rdi
    shr     $DB_SEGMENT_SHIFT, %rdi
    mov     %rdi, S7(%rsp)
    call    node_seg_end
    mov     %rax, (L + 80)(%rsp)
    mov     Node_db(%rbx), %rdi
    add     %rbx, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 80)(%rsp), %rdx
    call    lantern_db_add
    test    %rax, %rax
    jnz     99f                             # no room, or refused: until the next step
    xor     %edi, %edi
    mov     NodeBlock_data_id(%r12), %rsi
    mov     S7(%rsp), %rdx
    mov     (L + 80)(%rsp), %rcx
    lea     L(%rsp), %r8
    call    node_db_append
    mov     (L + 72)(%rsp), %rax            # the segment's new end, for each writer of it
    add     $(DbRecord__mem + 7), %rax
    and     $-8, %rax
    add     (L + 80)(%rsp), %rax
    mov     S7(%rsp), %rcx
    mov     %rcx, Node_backfill_segment(%rbx)
    mov     %rax, Node_backfill_end(%rbx)
    cmp     Node_db_block_segment(%rbx), %rcx
    jne     5f
    mov     %rax, Node_db_block_end(%rbx)
5:  mov     %r12, %rdi                      # its sidecars
    mov     $1, %esi
    call    node_db_sidecars
    mov     NodeBlock_slot(%r12), %rax
    mov     %rax, Node_backfill_slot(%rbx)
    cmp     Node_earliest_slot(%rbx), %rax
    jae     51f
    mov     %rax, Node_earliest_slot(%rbx)
51:
    lea     Node_backfill_root(%rbx), %rdi
    lea     NodeBlock_parent_root(%r12), %rsi
    COPY32  %rdi, %rsi
    mov     %r12, %rdi
    call    node_free_block
    jmp     1b
20: cmpq    $0, Node_backfill_handle(%rbx)  # no stream and no check left: the rest are of no chain
    jne     99f
    PART    %r12, %r13, %rbx, Node_blocks
21: test    %r13, %r13
    jz      22f
    cmpq    $NODE_BLOCK_BF_CHECKING, NodeBlock_status(%r12)
    je      99f
    add     $NodeBlock__mem, %r12
    dec     %r13
    jmp     21b
22: PART    %r12, %r13, %rbx, Node_blobs    # and no sidecar check below backfill_slot
221: test   %r13, %r13
    jz      223f
    cmpq    $NODE_BLOB_VERIFYING, NodeBlob_status(%r12)
    jne     222f
    mov     NodeBlob_slot(%r12), %rax
    cmp     Node_backfill_slot(%rbx), %rax
    jb      99f
222: add    $NodeBlob__mem, %r12
    dec     %r13
    jmp     221b
223: mov    (Node_streams + 8)(%rbx), %r13  # and no sidecar request of the node open
    mov     Node_streams(%rbx), %r12
    add     %rbx, %r12
224: test   %r13, %r13
    jz      23f
    cmpq    $NODE_STREAM_OPENING, NodeStream_state(%r12)
    jb      225f
    cmpq    $REQRESP_BLOB_SIDECARS_BY_RANGE, NodeStream_method(%r12)
    je      99f
    cmpq    $REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE, NodeStream_method(%r12)
    je      99f
225: add    Node_stream_bytes(%rbx), %r12
    dec     %r13
    jmp     224b
23: PART    %r12, %r13, %rbx, Node_blocks
24: test    %r13, %r13
    jz      26f
    cmpq    $NODE_BLOCK_BACKFILL, NodeBlock_status(%r12)
    jne     25f
    mov     %r12, %rdi
    call    node_free_block
25: add     $NodeBlock__mem, %r12
    dec     %r13
    jmp     24b
26: cmpq    $-1, Node_backfill_start(%rbx)  # the last request, weighed
    je      99f
    mov     Node_backfill_slot(%rbx), %rax
    cmp     Node_backfill_next(%rbx), %rax
    jae     27f
    mov     %rax, Node_backfill_next(%rbx)  # blocks joined: on from the lowest
    jmp     29f
27: cmpq    $0, Node_backfill_got(%rbx)
    jne     28f
    call    node_serve_slot                 # no block in the range: the range below
    mov     Node_backfill_start(%rbx), %rcx
    cmp     %rax, %rcx
    jbe     28f
    mov     %rcx, Node_backfill_next(%rbx)
    jmp     29f
28: mov     Node_backfill_slot(%rbx), %rax  # else again later, from the next peer
    mov     %rax, Node_backfill_next(%rbx)
    mov     Node_time_ms(%rbx), %rax
    add     $NODE_STATUS_MS, %rax
    mov     %rax, Node_backfill_ms(%rbx)
    incq    Node_backfill_peer(%rbx)
29: movq    $-1, Node_backfill_start(%rbx)
99: LEAVE 96
END_FUNCTION node_backfill_link

/*
 * With NODE_FLAG_DB, after the sync's requests: the backfill's BeaconBlocksByRange (node.md) of the
 * slots below backfill_next, to a peer from backfill_peer on, when no request is open or unweighed,
 * from backfill_ms on, while backfill_next is above the target and the streams part has room for
 * three entries. rbp the store. r12 the peers part, r13 the peers, S7 the target, S8 the start
 * slot, S9 the first index, S10 the peers checked. Locals: L the request (24), L+24 the index,
 * L+32 the peer, L+40 the fork, L+48 the pass: 1 for peers of any earliest_slot.
 */
LOCAL_FUNCTION node_backfill_ask
    ENTER 64
    testq   $NODE_FLAG_DB, Node_flags(%rbx)
    jz      99f
    cmpq    $0, Node_backfill_handle(%rbx)
    jne     99f
    cmpq    $-1, Node_backfill_start(%rbx)
    jne     99f
    mov     Node_backfill_root(%rbx), %rax
    or      (Node_backfill_root + 8)(%rbx), %rax
    or      (Node_backfill_root + 16)(%rbx), %rax
    or      (Node_backfill_root + 24)(%rbx), %rax
    jz      99f
    mov     Node_time_ms(%rbx), %rax
    cmp     Node_backfill_ms(%rbx), %rax
    jb      99f
    mov     Node_messages(%rbx), %rax       # room for it and two more
    sub     Node_streams(%rbx), %rax
    xor     %edx, %edx
    divq    Node_stream_bytes(%rbx)
    mov     (Node_streams + 8)(%rbx), %rcx
    add     $3, %rcx
    cmp     %rax, %rcx
    ja      99f
    call    node_serve_slot                 # the target
    mov     %rax, S7(%rsp)
    mov     Node_backfill_next(%rbx), %rcx
    cmp     %rax, %rcx
    jbe     99f
    mov     %rcx, %rdx
    sub     $NODE_SYNC_BATCH, %rdx
    jae     31f
    xor     %edx, %edx
31: cmp     %rax, %rdx
    cmovb   %rax, %rdx
    mov     %rdx, S8(%rsp)
    PART    %r12, %r13, %rbx, Node_peers    # the first peer from backfill_peer
    test    %r13, %r13
    jz      99f
    mov     Node_backfill_peer(%rbx), %rax
    xor     %edx, %edx
    div     %r13
    mov     %rdx, S9(%rsp)
    movq    $0, S10(%rsp)
    movq    $0, (L + 48)(%rsp)              # first the peers whose earliest_slot is at most the start
4:  mov     S10(%rsp), %rax
    cmp     %r13, %rax
    jb      40f
    cmpq    $0, (L + 48)(%rsp)              # with none, a peer of any earliest_slot
    jne     99f
    movq    $1, (L + 48)(%rsp)
    movq    $0, S10(%rsp)
    xor     %eax, %eax
40: add     S9(%rsp), %rax
    xor     %edx, %edx
    div     %r13
    mov     %rdx, (L + 24)(%rsp)
    incq    S10(%rsp)
    imul    $NodePeer__mem, %rdx, %rax
    lea     (%r12,%rax), %rcx
    testq   $1, NodePeer_flags(%rcx)        # NODE_PEER_STATUS
    jz      4b
    mov     NodePeer_fork_digest(%rcx), %rax
    cmp     Node_fork_digest(%rbx), %rax
    jne     4b
    mov     NodePeer_earliest_slot(%rcx), %rax
    cmp     S8(%rsp), %rax
    jbe     42f
    cmpq    $0, (L + 48)(%rsp)              # above the start in the first pass: the next peer
    je      4b
42:
    testq   $NODE_PEER_METADATA, NodePeer_flags(%rcx)   # from fulu, its MetaData read: its custody
    jnz     41f
    mov     %rcx, (L + 32)(%rsp)
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_FULU, %rax
    jae     4b
    mov     (L + 32)(%rsp), %rcx
41:
    mov     %rcx, (L + 32)(%rsp)
    mov     S8(%rsp), %rax                  # start, count, step 1
    mov     %rax, L(%rsp)
    mov     Node_backfill_next(%rbx), %rcx
    sub     %rax, %rcx
    mov     %rcx, (L + 8)(%rsp)
    movq    $1, (L + 16)(%rsp)
    mov     %rbp, %rdi                      # the fork of the store's slot: the sidecar requests of the range first
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, (L + 40)(%rsp)
    mov     (L + 32)(%rsp), %rdi
    mov     L(%rsp), %rsi
    mov     (L + 8)(%rsp), %rdx
    mov     %rax, %rcx
    call    node_sidecar_ask
    test    %rax, %rax
    jnz     99f
    mov     $1, %esi                        # version 2 from altair on
    cmpq    $FORK_ALTAIR, (L + 40)(%rsp)
    jb      5f
    mov     $2, %esi
5:  mov     $REQRESP_BEACON_BLOCKS_BY_RANGE, %edi
    mov     (L + 32)(%rsp), %rdx
    mov     NodePeer_handle(%rdx), %rdx
    lea     L(%rsp), %rcx
    mov     $24, %r8d
    call    node_open
    test    %rax, %rax
    jz      99f
    mov     NodeStream_handle(%rax), %rcx
    mov     %rcx, Node_backfill_handle(%rbx)
    mov     S8(%rsp), %rcx
    mov     %rcx, Node_backfill_start(%rbx)
    movq    $0, Node_backfill_got(%rbx)
    mov     (L + 24)(%rsp), %rcx
    mov     %rcx, Node_backfill_peer(%rbx)
99: LEAVE 64
END_FUNCTION node_backfill_ask

/*
 * The list of the body of the SignedBeaconBlock in the ByteList rdi: rsi 0 attester_slashings, 1
 * attestations (offsets at bytes 204 and 208 of the body in every fork). rax = its count, or
 * 2^64 - 1 when the bytes do not hold it; for an index rdx below the count, rdx the item's SSZ
 * bytes and rcx their length, else 0 and 0. Uses r8-r11.
 */
LOCAL_FUNCTION node_body_item
    UNWIND_END_PROLOGUE
    mov     16(%rdi), %r8                   # the length
    mov     8(%rdi), %r9
    add     %rdi, %r9                       # the bytes
    cmp     $(100 + 84), %r8
    jb      9f
    mov     (%r9), %eax                     # the message
    cmp     %r8, %rax
    ja      9f
    add     %rax, %r9
    sub     %rax, %r8
    cmp     $88, %r8
    jb      9f
    mov     80(%r9), %eax                   # the body: its offset at 80
    cmp     %r8, %rax
    ja      9f
    add     %rax, %r9
    sub     %rax, %r8
    cmp     $216, %r8
    jb      9f
    mov     204(%r9,%rsi,4), %r10d          # the list: from its offset to the next field's
    mov     208(%r9,%rsi,4), %r11d
    cmp     %r11, %r10
    ja      9f
    cmp     %r8, %r11
    ja      9f
    sub     %r10, %r11                      # the list's bytes
    add     %r10, %r9
    test    %r11, %r11
    jz      7f
    cmp     $4, %r11
    jb      9f
    mov     (%r9), %eax                     # its first offset: 4 times the count
    test    $3, %al
    jnz     9f
    cmp     %r11, %rax
    ja      9f
    shr     $2, %rax
    test    %rax, %rax
    jz      9f
    cmp     %rax, %rdx
    jae     8f
    mov     (%r9,%rdx,4), %r10d
    lea     1(%rdx), %rcx
    mov     %r11, %r8
    cmp     %rax, %rcx
    jae     1f
    mov     (%r9,%rcx,4), %r8d
1:  cmp     %r8, %r10
    ja      9f
    cmp     %r11, %r8
    ja      9f
    lea     (%r9,%r10), %rdx
    mov     %r8, %rcx
    sub     %r10, %rcx
    ret
7:  xor     %eax, %eax
8:  xor     %edx, %edx
    xor     %ecx, %ecx
    ret
9:  mov     $-1, %rax
    xor     %edx, %edx
    xor     %ecx, %ecx
    ret
END_FUNCTION node_body_item

/*
 * The votes of the imported block entry rdi (node.md): a BLOCK_ATTESTATION of each of its rsi
 * attestations, then a BLOCK_SLASHING of each of its rdx attester slashings with the post-state of
 * the justified root; at most NODE_VOTES_MAX in all. r12 the entry, r13 the index, S7 the
 * attestations, S8 the slashings, S9 the justified state.
 */
LOCAL_FUNCTION node_votes
    ENTER 0
    mov     %rdi, %r12
    mov     $128, %eax
    cmp     %rax, %rsi
    cmova   %rax, %rsi
    mov     %rsi, S7(%rsp)
    mov     $2, %eax
    cmp     %rax, %rdx
    cmova   %rax, %rdx
    mov     %rdx, S8(%rsp)
    xor     %r13d, %r13d
1:  cmp     S7(%rsp), %r13
    jae     2f
    mov     $NODE_WORK_BLOCK_ATTESTATION, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     NodeBlock_data_id(%r12), %rcx
    xor     %r8d, %r8d
    mov     %r13, %r9
    call    node_work
    inc     %r13
    jmp     1b
2:  cmpq    $0, S8(%rsp)
    je      9f
    lea     (Store_justified_checkpoint + 8)(%rbp), %rdi
    call    node_find_block
    movq    $0, S9(%rsp)
    cmp     $-1, %rax
    je      3f
    mov     NodeBlock_state_id(%rdx), %rax
    mov     %rax, S9(%rsp)
3:  xor     %r13d, %r13d
4:  cmp     S8(%rsp), %r13
    jae     9f
    mov     $NODE_WORK_BLOCK_SLASHING, %edi
    mov     S9(%rsp), %rsi
    xor     %edx, %edx
    mov     NodeBlock_data_id(%r12), %rcx
    xor     %r8d, %r8d
    mov     %r13, %r9
    call    node_work
    inc     %r13
    jmp     4b
9:  LEAVE 0
END_FUNCTION node_votes

/*
 * The aggregate of the SignedAggregateAndProof in the ByteList rdi: rax = 0 and rdx its SSZ bytes,
 * rcx their length; rax = 2^64 - 1 when the bytes do not hold it. The message's offset is at byte
 * 0, the aggregate's at byte 8 of the message; the aggregate runs to the end. Uses r8-r10.
 */
LOCAL_FUNCTION node_aggregate
    UNWIND_END_PROLOGUE
    mov     16(%rdi), %r8
    mov     8(%rdi), %r9
    add     %rdi, %r9
    cmp     $4, %r8
    jb      9f
    mov     (%r9), %r10d                    # the message
    cmp     %r8, %r10
    ja      9f
    add     %r10, %r9
    sub     %r10, %r8
    cmp     $12, %r8
    jb      9f
    mov     8(%r9), %r10d                   # the aggregate
    cmp     %r8, %r10
    ja      9f
    lea     (%r9,%r10), %rdx
    mov     %r8, %rcx
    sub     %r10, %rcx
    xor     %eax, %eax
    ret
9:  mov     $-1, %rax
    xor     %edx, %edx
    xor     %ecx, %ecx
    ret
END_FUNCTION node_aggregate

/*
 * After the head (node.md): each NodeMessage in NODE_MESSAGE_VOTE whose slot is below the store's
 * gets a GOSSIP_VOTE work and takes NODE_MESSAGE_VOTING, while the actions have room for it and
 * 4096 bytes. rax = 1 when an entry is left waiting, else 0. r12 an entry, r13 the entries left,
 * S7 the store's slot, S8 left waiting.
 */
LOCAL_FUNCTION node_vote_due
    ENTER 0
    movq    $0, S8(%rsp)
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, S7(%rsp)
    PART    %r12, %r13, %rbx, Node_messages
1:  test    %r13, %r13
    jz      9f
    cmpq    $NODE_MESSAGE_VOTE, NodeMessage_state(%r12)
    jne     2f
    mov     NodeMessage_slot(%r12), %rax
    cmp     S7(%rsp), %rax
    jae     2f
    mov     $NODE_ACT_WORK_SIZE, %edi
    call    node_room
    test    %rax, %rax
    jnz     3f
    movq    $1, S8(%rsp)
    jmp     9f
3:  mov     $NODE_WORK_GOSSIP_VOTE, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     NodeMessage_data_id(%r12), %rcx
    mov     NodeMessage_handle(%r12), %r8
    xor     %r9d, %r9d
    call    node_work
    movq    $NODE_MESSAGE_VOTING, NodeMessage_state(%r12)
2:  add     $NodeMessage__mem, %r12
    dec     %r13
    jmp     1b
9:  mov     S8(%rsp), %rax
    LEAVE 0
END_FUNCTION node_vote_due

/*
 * rax = the end of the sidecar segment rdi: db_sidecar_end for db_sidecar_segment, else
 * backfill_sidecar_end for backfill_sidecar_segment, else 0, a new segment. Uses rax only.
 */
LOCAL_FUNCTION node_side_end
    UNWIND_END_PROLOGUE
    cmp     Node_db_sidecar_segment(%rbx), %rdi
    jne     1f
    mov     Node_db_sidecar_end(%rbx), %rax
    ret
1:  cmp     Node_backfill_sidecar_segment(%rbx), %rdi
    jne     2f
    mov     Node_backfill_sidecar_end(%rbx), %rax
    ret
2:  xor     %eax, %eax
    ret
END_FUNCTION node_side_end

/*
 * Each NODE_BLOB_VALID sidecar of the block entry rdi, by index, to the Db (node.md): its record at
 * the end of the sidecar segment of the block's slot and a DB_APPEND; the writer rsi (0 the archive,
 * 1 the backfill) takes that segment, and each end of it the record's end; its bytes and entry go
 * unless a stream sends them. A record lantern_db_add refuses stays for the prune. S8 the block,
 * S9 the index, S10 its slot. Locals: L a DbRecord (80), L+80 the offset, L+88 the sidecar, L+96
 * the writer, L+104 the segment.
 */
LOCAL_FUNCTION node_db_sidecars
    ENTER 112
    mov     %rdi, S8(%rsp)
    mov     NodeBlock_slot(%rdi), %rax
    mov     %rax, S10(%rsp)
    mov     %rsi, (L + 96)(%rsp)
    cmp     Node_sidecar_floor(%rbx), %rax  # below sidecar_floor: no record
    jb      9f
    movq    $0, S9(%rsp)
4:  cmpq    $DB_SIDECAR_INDICES, S9(%rsp)
    jae     9f
    mov     S8(%rsp), %rdi
    mov     S9(%rsp), %rsi
    call    node_blob_held
    test    %rax, %rax
    jz      19f
    mov     %rax, (L + 88)(%rsp)
    mov     S10(%rsp), %rdi                 # a column sidecar from fulu on, else a blob sidecar
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     $DB_BLOB_SIDECAR, %ecx
    mov     $DB_COLUMN_SIDECAR, %edx
    cmp     $FORK_FULU, %rax
    cmovae  %rdx, %rcx
    mov     %rcx, L(%rsp)
    mov     S10(%rsp), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     S9(%rsp), %rax
    mov     %rax, (L + 16)(%rsp)
    mov     (L + 88)(%rsp), %rax
    mov     NodeBlob_length(%rax), %rax
    mov     %rax, (L + 72)(%rsp)
    add     $24, %rax
    mov     %rax, (L + 56)(%rsp)
    movq    $24, (L + DbRecord_bytes + 8)(%rsp)
    mov     S10(%rsp), %rdi                 # its segment, and its offset at the segment's end
    shr     $DB_SEGMENT_SHIFT, %rdi
    mov     %rdi, (L + 104)(%rsp)
    call    node_side_end
    mov     %rax, (L + 80)(%rsp)
    mov     Node_db(%rbx), %rdi
    add     %rbx, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 80)(%rsp), %rdx
    call    lantern_db_add
    test    %rax, %rax
    jnz     19f                             # refused: the entry stays for the prune
    mov     $1, %edi
    mov     (L + 88)(%rsp), %rax
    mov     NodeBlob_data_id(%rax), %rsi
    mov     (L + 104)(%rsp), %rdx
    mov     (L + 80)(%rsp), %rcx
    lea     L(%rsp), %r8
    call    node_db_append
    mov     (L + 72)(%rsp), %rax            # the segment's new end: the writer's segment, each end of it
    add     $(DbRecord__mem + 7), %rax
    and     $-8, %rax
    add     (L + 80)(%rsp), %rax
    mov     (L + 104)(%rsp), %rcx
    cmpq    $0, (L + 96)(%rsp)
    jne     1f
    mov     %rcx, Node_db_sidecar_segment(%rbx)
    jmp     2f
1:  mov     %rcx, Node_backfill_sidecar_segment(%rbx)
2:  cmp     Node_db_sidecar_segment(%rbx), %rcx
    jne     3f
    mov     %rax, Node_db_sidecar_end(%rbx)
3:  cmp     Node_backfill_sidecar_segment(%rbx), %rcx
    jne     5f
    mov     %rax, Node_backfill_sidecar_end(%rbx)
5:  mov     (L + 88)(%rsp), %rax            # its bytes and entry go, unless a stream sends them
    mov     NodeBlob_data_id(%rax), %rdi
    call    node_serving
    test    %rax, %rax
    jnz     19f
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     (L + 88)(%rsp), %rax
    mov     NodeBlob_data_id(%rax), %rsi
    xor     %edx, %edx
    call    node_ids
    mov     (L + 88)(%rsp), %rdx
    mov     $-1, %rax
    mov     %rax, (%rdx)
    mov     %rax, 8(%rdx)
    mov     %rax, 16(%rdx)
    mov     %rax, 24(%rdx)
    mov     %rax, NodeBlob_slot(%rdx)
    movq    $0, NodeBlob_data_id(%rdx)
    movq    $NODE_BLOB_FREE, NodeBlob_status(%rdx)
19: incq    S9(%rsp)
    jmp     4b
9:  LEAVE 112
END_FUNCTION node_db_sidecars

/*
 * With NODE_FLAG_DB, the sidecars the node no longer serves go (node.md): the drop slot, the first
 * slot of the earlier of the blob window's and the column window's first epochs, at most the Db's
 * end_slot, down to a multiple of DB_SEGMENT_SLOTS, at most 16 segments above sidecar_floor; a
 * DB_DROP of each sidecar segment below it from sidecar_floor's, lantern_db_drop_sidecars, and
 * sidecar_floor takes it. r12 the drop slot, r13 a segment. Locals: L the slot.
 */
LOCAL_FUNCTION node_drop_sidecars
    ENTER 16
    testq   $NODE_FLAG_DB, Node_flags(%rbx)
    jz      9f
    mov     (Node_config + CONFIG_MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS)(%rbx), %rdi
    mov     $FORK_DENEB, %esi
    call    node_window
    mov     %rax, %r12
    mov     (Node_config + CONFIG_MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS)(%rbx), %rdi
    mov     $FORK_FULU, %esi
    call    node_window
    cmp     %r12, %rax
    cmovb   %rax, %r12
    mov     %r12, %rax
    mov     $SLOTS_PER_EPOCH, %ecx
    mul     %rcx
    jnc     1f
    mov     $-1, %rax
1:  mov     Node_db(%rbx), %rcx
    add     %rbx, %rcx
    mov     Db_end_slot(%rcx), %rcx
    cmp     %rcx, %rax
    cmova   %rcx, %rax
    and     $-DB_SEGMENT_SLOTS, %rax
    mov     Node_sidecar_floor(%rbx), %rcx
    cmp     %rcx, %rax
    jbe     9f
    add     $(16 * DB_SEGMENT_SLOTS), %rcx  # at most 16 segments a step
    cmp     %rcx, %rax
    cmova   %rcx, %rax
    mov     %rax, %r12
    mov     Node_sidecar_floor(%rbx), %r13
    shr     $DB_SEGMENT_SHIFT, %r13
2:  mov     %r13, %rax                      # each sidecar segment below the drop slot
    shl     $DB_SEGMENT_SHIFT, %rax
    cmp     %r12, %rax
    jae     3f
    mov     $NODE_ACT_DB_DROP, %edi
    mov     $NODE_ACT_DB_DROP_SIZE, %esi
    call    node_act
    mov     %r13, 16(%rax)
    movq    $1, 24(%rax)
    inc     %r13
    jmp     2b
3:  mov     %r12, L(%rsp)
    mov     Node_db(%rbx), %rdi
    add     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_db_drop_sidecars
    mov     %r12, Node_sidecar_floor(%rbx)
    shr     $DB_SEGMENT_SHIFT, %r12         # a writer's segment below it: none
    cmp     Node_db_sidecar_segment(%rbx), %r12
    jbe     4f
    movq    $-1, Node_db_sidecar_segment(%rbx)
4:  cmp     Node_backfill_sidecar_segment(%rbx), %r12
    jbe     9f
    movq    $-1, Node_backfill_sidecar_segment(%rbx)
9:  LEAVE 16
END_FUNCTION node_drop_sidecars

/*
 * With NODE_FLAG_DB, the canonical blocks from db_next_slot to the finalized block rdi and their
 * sidecars go to the Db, in slot order: a record of each in the index and in a DB_APPEND action,
 * then their bytes and entries go, but the finalized block's entry and bytes a stream sends. A
 * record the Db refuses stops the archive until a later prune. r12 the finalized block, r13 the
 * chain (an entry address for each, at the end of scratch), S7 its count, S8 a block, S9 an
 * index, S10 the slot. Locals: L a DbRecord, L+64 an offset, L+72 a sidecar entry.
 */
LOCAL_FUNCTION node_archive
    ENTER 96
    testq   $NODE_FLAG_DB, Node_flags(%rbx)
    jz      99f
    mov     %rdi, %r12
    mov     (%r14), %r13                    # the chain at the end of scratch
    mov     (Node_blocks + 8)(%rbx), %rax
    shl     $3, %rax
    sub     %rax, %r13
    add     %r14, %r13
    movq    $0, S7(%rsp)
    mov     %r12, %rdx                      # from the finalized block down to db_next_slot
1:  cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     2f
    mov     NodeBlock_slot(%rdx), %rax
    cmp     Node_db_next_slot(%rbx), %rax
    jb      2f
    mov     S7(%rsp), %rax
    mov     %rdx, (%r13,%rax,8)
    inc     %rax
    mov     %rax, S7(%rsp)
    cmp     (Node_blocks + 8)(%rbx), %rax
    jae     2f
    lea     NodeBlock_parent_root(%rdx), %rdi
    call    node_find_block
    cmp     $-1, %rax
    jne     1b
2:  mov     S7(%rsp), %rax                  # then from the lowest slot
    test    %rax, %rax
    jz      99f
    dec     %rax
    mov     %rax, S7(%rsp)
    mov     (%r13,%rax,8), %rdx
    mov     %rdx, S8(%rsp)
    mov     NodeBlock_slot(%rdx), %rax
    mov     %rax, S10(%rsp)
    cmpq    $0, NodeBlock_data_id(%rdx)
    je      30f                             # no bytes: the anchor
    mov     Node_db(%rbx), %rdi             # a block the Db holds already, as after a restart: no record
    add     %rbx, %rdi
    mov     %rdx, %rsi
    lea     (L + 80)(%rsp), %rdx
    call    lantern_db_find_root
    cmpq    $-1, (L + 80)(%rsp)
    jne     40f
    mov     S8(%rsp), %rdx
    movq    $DB_BLOCK, L(%rsp)              # the block's record
    mov     S10(%rsp), %rax
    mov     %rax, (L + 8)(%rsp)
    movq    $0, (L + 16)(%rsp)
    lea     (L + 24)(%rsp), %rdi
    COPY32  %rdi, %rdx
    mov     NodeBlock_length(%rdx), %rax
    mov     %rax, (L + 72)(%rsp)
    add     $24, %rax
    mov     %rax, (L + 56)(%rsp)
    movq    $24, (L + DbRecord_bytes + 8)(%rsp)
    mov     S10(%rsp), %rax                 # its segment, and its offset at the segment's end
    shr     $DB_SEGMENT_SHIFT, %rax
    cmp     Node_db_block_segment(%rbx), %rax
    je      3f
    mov     %rax, %rdi
    call    node_seg_end
    mov     %rdi, Node_db_block_segment(%rbx)
    mov     %rax, Node_db_block_end(%rbx)
3:  mov     Node_db_block_end(%rbx), %rax
    mov     %rax, (L + 80)(%rsp)
    mov     Node_db(%rbx), %rdi
    add     %rbx, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 80)(%rsp), %rdx
    call    lantern_db_add
    test    %rax, %rax
    jnz     99f
    xor     %edi, %edi
    mov     S8(%rsp), %rax
    mov     NodeBlock_data_id(%rax), %rsi
    mov     Node_db_block_segment(%rbx), %rdx
    mov     (L + 80)(%rsp), %rcx
    lea     L(%rsp), %r8
    call    node_db_append
    mov     (L + 72)(%rsp), %rax
    add     $(DbRecord__mem + 7), %rax
    and     $-8, %rax
    add     %rax, Node_db_block_end(%rbx)
    mov     Node_backfill_segment(%rbx), %rax   # the backfill's end too, of the same segment
    cmp     Node_db_block_segment(%rbx), %rax
    jne     42f
    mov     Node_db_block_end(%rbx), %rax
    mov     %rax, Node_backfill_end(%rbx)
42: mov     S8(%rsp), %rdi                  # each sidecar the node holds, by index
    xor     %esi, %esi
    call    node_db_sidecars
20: mov     S8(%rsp), %rdx                  # the finalized block: its state and bytes to the shell, for a restart
    cmp     %r12, %rdx
    jne     21f
    mov     8(%r15), %rax
    add     %r15, %rax
    mov     16(%r15), %rcx
    add     %rcx, %rax
    add     $NODE_ACT_DB_STATE_SIZE, %rcx
    mov     %rcx, 16(%r15)
    movq    $NODE_ACT_DB_STATE_SIZE, (%rax)
    movq    $NODE_ACT_DB_STATE, 8(%rax)
    mov     NodeBlock_state_id(%rdx), %rcx
    mov     %rcx, 16(%rax)
    mov     NodeBlock_data_id(%rdx), %rcx
    mov     %rcx, 24(%rax)
    mov     S10(%rsp), %rcx
    mov     %rcx, 32(%rax)
    mov     Node_custody_count(%rbx), %rcx
    mov     %rcx, 40(%rax)
    mov     Node_custody_slot(%rbx), %rcx
    mov     %rcx, 48(%rax)
    mov     S8(%rsp), %rdi                  # and the archive's state record
    mov     S10(%rsp), %rsi
    call    node_archive_queue
21: mov     S8(%rsp), %rax                  # the block's bytes go, unless a stream sends them
    mov     NodeBlock_data_id(%rax), %rdi
    call    node_serving
    test    %rax, %rax
    jnz     30f
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     S8(%rsp), %rax
    mov     NodeBlock_data_id(%rax), %rsi
    xor     %edx, %edx
    call    node_ids
    mov     S8(%rsp), %rdx
    movq    $0, NodeBlock_data_id(%rdx)
    cmp     %r12, %rdx                      # and its entry, but the finalized block's
    je      30f
    mov     $-1, %rax
    mov     %rax, (%rdx)
    mov     %rax, 8(%rdx)
    mov     %rax, 16(%rdx)
    mov     %rax, 24(%rdx)
    mov     %rax, 32(%rdx)
    mov     %rax, 40(%rdx)
    mov     %rax, 48(%rdx)
    mov     %rax, 56(%rdx)
    mov     %rax, NodeBlock_slot(%rdx)
    movq    $0, NodeBlock_state_id(%rdx)
    movq    $NODE_BLOCK_FREE, NodeBlock_status(%rdx)
30: mov     S10(%rsp), %rax
    inc     %rax
    mov     %rax, Node_db_next_slot(%rbx)
    jmp     2b
40: movq    $0, S9(%rsp)                    # in the Db: the sidecars the node holds of it go
41: cmpq    $DB_SIDECAR_INDICES, S9(%rsp)
    jae     20b
    mov     S8(%rsp), %rdi
    mov     S9(%rsp), %rsi
    incq    S9(%rsp)
    call    node_blob_held
    test    %rax, %rax
    jz      41b
    mov     %rax, (L + 88)(%rsp)
    mov     NodeBlob_data_id(%rax), %rdi
    call    node_serving
    test    %rax, %rax
    jnz     41b
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     (L + 88)(%rsp), %rax
    mov     NodeBlob_data_id(%rax), %rsi
    xor     %edx, %edx
    call    node_ids
    mov     (L + 88)(%rsp), %rdx
    mov     $-1, %rax
    mov     %rax, (%rdx)
    mov     %rax, 8(%rdx)
    mov     %rax, 16(%rdx)
    mov     %rax, 24(%rdx)
    mov     %rax, NodeBlob_slot(%rdx)
    movq    $0, NodeBlob_data_id(%rdx)
    movq    $NODE_BLOB_FREE, NodeBlob_status(%rdx)
    jmp     41b
99: LEAVE 96
END_FUNCTION node_archive

/*
 * (node, segment, sidecars, bytes, valid): lantern_db_scan of a segment's bytes into the node's
 * Db; then the segment is the one of its kind to append to, at valid, unless the current one is
 * higher; db_next_slot is at least the Db's end_slot, and earliest_slot the Db's first block when
 * that is lower. rbx node, rbp valid, r12 sidecars, r13 segment.
 */
FUNCTION lantern_node_db_scan
    ENTER 0
    mov     %rdi, %rbx
    mov     (%rsi), %r13
    mov     (%rdx), %r12
    mov     %r8, %rbp
    mov     %rcx, %r14
    mov     Node_db(%rbx), %rdi
    add     %rbx, %rdi
    call    lantern_db_scan
    test    %rax, %rax
    jnz     9f
    cmp     $2, %r12
    je      20f
    test    %r12, %r12                      # a sidecar segment: the backfill's, when it has none
    jz      14f
    cmpq    $-1, Node_backfill_sidecar_segment(%rbx)
    jne     10f
    mov     %r13, Node_backfill_sidecar_segment(%rbx)
    mov     (%rbp), %rax
    mov     %rax, Node_backfill_sidecar_end(%rbx)
    jmp     10f
14:                                         # a block segment: the backfill's, when it has none; its lowest block
    cmpq    $-1, Node_backfill_segment(%rbx)
    jne     11f
    mov     %r13, Node_backfill_segment(%rbx)
    mov     (%rbp), %rax
    mov     %rax, Node_backfill_end(%rbx)
11: mov     8(%r14), %rsi
    add     %r14, %rsi
    mov     (%rbp), %rdi
    add     %rsi, %rdi                      # the end of the records added
12: lea     DbRecord__mem(%rsi), %rax
    cmp     %rdi, %rax
    ja      10f
    mov     DbRecord_slot(%rsi), %rax
    cmp     Node_backfill_slot(%rbx), %rax
    jae     13f
    mov     %rax, Node_backfill_slot(%rbx)
    mov     %rax, Node_backfill_next(%rbx)
    lea     Node_backfill_root(%rbx), %rcx
    lea     (DbRecord__mem + 116)(%rsi), %rdx
    COPY32  %rcx, %rdx
13: mov     DbRecord_length(%rsi), %rax
    add     $(DbRecord__mem + 7), %rax
    and     $-8, %rax
    add     %rax, %rsi
    jmp     12b
10:
    mov     $Node_db_block_segment, %ecx
    test    %r12, %r12
    jz      1f
    mov     $Node_db_sidecar_segment, %ecx
1:  mov     (%rbx,%rcx), %rax
    cmp     $-1, %rax
    je      2f
    cmp     %rax, %r13
    jb      3f
2:  mov     %r13, (%rbx,%rcx)
    mov     (%rbp), %rax
    mov     %rax, 8(%rbx,%rcx)
3:  mov     Node_db(%rbx), %rsi
    add     %rbx, %rsi
    mov     Db_end_slot(%rsi), %rax
    cmp     Node_db_next_slot(%rbx), %rax
    jbe     4f
    mov     %rax, Node_db_next_slot(%rbx)
4:  mov     Db_first_slot(%rsi), %rcx       # the first block below earliest_slot
    mov     Node_earliest_slot(%rbx), %rdx
    mov     Db_end_slot(%rsi), %rax
    cmp     %rax, %rdx
    cmovae  %rax, %rdx
    mov     Db_slots(%rsi), %rdi
    add     %rsi, %rdi
5:  cmp     %rdx, %rcx
    jae     8f
    cmpq    $0, DbSlot_block(%rdi)
    jne     6f
    add     $DbSlot__mem, %rdi
    inc     %rcx
    jmp     5b
6:  mov     %rcx, Node_earliest_slot(%rbx)
8:  xor     %eax, %eax
9:  LEAVE 0
20: mov     Node_archive_segment(%rbx), %rax    # a state segment: the archive's, unless it has a higher one; its records' slots
    cmp     $-1, %rax
    je      21f
    cmp     %rax, %r13
    jb      22f
21: mov     %r13, Node_archive_segment(%rbx)
    mov     (%rbp), %rax
    mov     %rax, Node_archive_end(%rbx)
22: mov     8(%r14), %rsi
    add     %r14, %rsi
    mov     (%rbp), %rdi
    add     %rsi, %rdi
23: lea     DbRecord__mem(%rsi), %rax
    cmp     %rdi, %rax
    ja      8b
    mov     DbRecord_slot(%rsi), %rax
    mov     Node_archive_slot(%rbx), %rcx
    cmp     $-1, %rcx
    je      24f
    cmp     %rcx, %rax
    jbe     25f
24: mov     %rax, Node_archive_slot(%rbx)
25: cmp     Node_archive_first(%rbx), %rax
    jae     26f
    mov     %rax, Node_archive_first(%rbx)
26: mov     DbRecord_length(%rsi), %rax
    add     $(DbRecord__mem + 7), %rax
    and     $-8, %rax
    add     %rax, %rsi
    jmp     23b
END_FUNCTION lantern_node_db_scan

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

/* rax = 1 when the block entry rdi needs blobs or columns it does not hold (node.md), else 0. r13 the entry, S7 its blob count, S8 a window. */
LOCAL_FUNCTION node_lacks_sidecars
    ENTER 0
    mov     %rdi, %r13
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
4:  mov     $1, %eax
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
5:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION node_lacks_sidecars

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
    mov     %r13, %rdi
    call    node_lacks_sidecars
    test    %rax, %rax
    jz      5f
    movq    $NODE_BLOCK_BLOBS, NodeBlock_status(%r13)
    LEAVE 0
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
    call    node_new_block
    mov     %rax, (L + 40)(%rsp)
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
    mov     16(%r13), %rax
    mov     %rax, NodeBlock_length(%rdi)
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
    orq     $NODE_FLAG_EL_OFFLINE, Node_flags(%rbx) # ENGINE 1: the connection failed; the engine is offline
    call    node_engine_failed
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
47: cmp     $NODE_EV_BUILDER, %rax          # BUILDER: the answer of a builder call
    jne     470f
    call    node_builder_event
    LEAVE 48
470: cmp    $NODE_EV_DB_ARCHIVE, %rax
    jne     4701f
    mov     %r12, %rdi                      # DB_ARCHIVE: the state record goes in the index
    call    node_archive_done
    LEAVE 48
4701: cmp   $NODE_EV_ENR, %rax
    jne     471f
    mov     %r12, %rdi                      # ENR: a record discv5 found
    call    node_enr
    LEAVE 48
471: cmp    $NODE_EV_API, %rax
    jne     472f
    mov     %r12, %rdi                      # API: the answer to a request
    call    node_api_event
    LEAVE 48
472: cmp    $NODE_EV_API_IDENTITY, %rax
    jne     473f
    lea     Node_api_identity(%rbx), %rdi   # API_IDENTITY: the node keeps the texts
    mov     (NodeEvent_bytes + 8)(%r12), %rsi
    lea     NodeEvent_bytes(%r12,%rsi), %rsi
    mov     $API_IDENTITY_SIZE, %edx
    call    lantern_copy
    LEAVE 48
473: cmp    $NODE_EV_API_SENT, %rax
    jne     474f
    mov     16(%r12), %rdi                  # API_SENT: the next chunk of the connection's stream
    call    node_api_sent
    LEAVE 48
474: cmp    $NODE_EV_API_CLOSED, %rax
    jne     50f
    mov     16(%r12), %rdi                  # API_CLOSED: the connection's stream ends
    call    node_api_closed
    LEAVE 48
50: mov     NodeAction_work_kind(%r12), %rax        # WORK_DONE
    cmp     $NODE_WORK_BLOCK_ATTESTATION, %rax  # a block's vote done: event_votes takes 1 off
    je      501f
    cmp     $NODE_WORK_BLOCK_SLASHING, %rax
    jne     502f
501: decq   Node_event_votes(%rbx)
502: mov    NodeEvent_result(%r12), %rcx
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
    movq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%r13)    # imported: the block event, its light client data, its votes, then its waiting children
    mov     %r13, %rdi
    call    node_api_block_event
    mov     $NODE_WORK_LC_BLOCK, %edi
    mov     NodeBlock_state_id(%r13), %rsi
    xor     %edx, %edx
    mov     NodeBlock_data_id(%r13), %rcx
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    call    node_work
    movq    $NODE_LC_ID, NodeAction_state_c(%rax)
    mov     %r13, %rdi
    mov     NodeEvent_index(%r12), %rsi
    mov     NodeEvent_root(%r12), %rdx
    call    node_votes
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
60: cmp     $NODE_WORK_LC_HEAD, %rax         # the light client events of a new latest update
    jne     601f
    call    node_lc_head_done
    LEAVE 48
601: cmp    $NODE_WORK_LC_BLOCK, %rax
    jne     603f
    LEAVE 48
603: cmp    $NODE_WORK_LC_SERVE, %rax        # the light client answer to its stream
    jne     604f
    call    node_lc_served
    LEAVE 48
604: cmp    $NODE_WORK_LC_GOSSIP, %rax       # the light client gossip: a message's validation, a publish
    jne     605f
    call    node_lc_validated
    LEAVE 48
605: cmp    $NODE_WORK_LC_PUBLISH, %rax
    jne     602f
    call    node_lc_published
    LEAVE 48
602: cmp    $NODE_WORK_JUSTIFIED_STATE, %rax
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
62: cmp     $NODE_WORK_BLOCK_ATTESTATION, %rax  # BLOCK_ATTESTATION: with NEED_TARGET_STATE, the target state, then again
    jne     622f
    cmp     $LANTERN_NEED_TARGET_STATE, %rcx
    jne     79f
    mov     NodeEvent_checkpoint(%r12), %rdi
    lea     (NodeEvent_checkpoint + 8)(%r12), %rsi
    call    node_checkpoint_state
    test    %rax, %rax
    jz      79f
    mov     %rax, %rsi
    mov     $NODE_WORK_BLOCK_ATTESTATION, %edi
    mov     NodeAction_state_b(%r12), %rdx
    mov     NodeAction_data(%r12), %rcx
    mov     NodeAction_target(%r12), %r8
    mov     NodeAction_arg(%r12), %r9
    call    node_work
    LEAVE 48
622: cmp    $NODE_WORK_GOSSIP_VOTE, %rax    # GOSSIP_VOTE: the target state; a future slot waits; else the entry goes
    jne     623f
    cmp     $LANTERN_NEED_TARGET_STATE, %rcx
    jne     6221f
    mov     NodeEvent_checkpoint(%r12), %rdi
    lea     (NodeEvent_checkpoint + 8)(%r12), %rsi
    call    node_checkpoint_state
    test    %rax, %rax
    jz      6221f
    mov     %rax, %rsi
    mov     $NODE_WORK_GOSSIP_VOTE, %edi
    mov     NodeAction_state_b(%r12), %rdx
    mov     NodeAction_data(%r12), %rcx
    mov     NodeAction_target(%r12), %r8
    mov     NodeAction_arg(%r12), %r9
    call    node_work
    LEAVE 48
6221: mov   NodeAction_target(%r12), %rdi
    call    node_find_message
    cmp     $-1, %rax
    je      79f
    mov     %rdx, %r13
    cmpq    $LANTERN_INVALID_FUTURE_SLOT, NodeEvent_result(%r12)
    jne     6222f
    movq    $NODE_MESSAGE_VOTE, NodeMessage_state(%r13)
    LEAVE 48
6222: mov   $NODE_ACT_BYTES_FREE, %edi
    mov     NodeMessage_data_id(%r13), %rsi
    xor     %edx, %edx
    call    node_ids
    mov     %r13, %rdi
    call    node_drop_message
    LEAVE 48
623: cmp    $NODE_WORK_SERVE, %rax          # SERVE: the chunk to its stream, then the next block or the close
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
    mov     %rbp, %rdi                      # the event of an operation (node.md, The events), before its bytes go
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %rdx
    mov     NodeMessage_topic(%r13), %rdi
    mov     NodeAction_data(%r12), %rsi
    call    node_op_event
    cmpq    $GOSSIP_BEACON_BLOCK, NodeMessage_topic(%r13)  # a block: its block_gossip event
    jne     638f
    mov     $API_TOPIC_BLOCK_GOSSIP, %edi
    lea     NodeEvent_root(%r12), %rsi
    mov     NodeMessage_slot(%r13), %rdx
    xor     %ecx, %ecx
    call    node_api_root_event
638: mov    %rbp, %rdi                      # an operation of the pool keeps its bytes there too
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %rcx
    mov     NodeMessage_topic(%r13), %rdi
    mov     NodeAction_data(%r12), %rsi
    mov     NodeMessage_length(%r13), %rdx
    lea     NodeEvent_root(%r12), %r8       # an attestation: its slot, committee index and member
    call    node_pool_add
    test    %rax, %rax
    jz      639f
    cmpq    $GOSSIP_ATTESTER_SLASHING, NodeMessage_topic(%r13)
    je      639f
    mov     %r13, %rdi
    call    node_drop_message
    LEAVE 48
639: cmpq   $GOSSIP_BEACON_AGGREGATE_AND_PROOF, NodeMessage_topic(%r13)
    jne     640f
    mov     Node_blobs(%rbx), %rax          # a valid aggregate: kept for its vote, with half the part free
    sub     Node_messages(%rbx), %rax
    xor     %edx, %edx
    mov     $NodeMessage__mem, %ecx
    div     %rcx
    mov     (Node_messages + 8)(%rbx), %rcx
    shl     $1, %rcx
    cmp     %rax, %rcx
    jae     65f
    movq    $NODE_MESSAGE_VOTE, NodeMessage_state(%r13)
    LEAVE 48
640: cmpq   $GOSSIP_ATTESTER_SLASHING, NodeMessage_topic(%r13)
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
    call    node_new_block
    mov     %rax, (L + 40)(%rsp)
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
    mov     NodeMessage_length(%r13), %rax
    mov     %rax, NodeBlock_length(%rdi)
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
    call    node_new_blob
    lea     NodeEvent_root(%r12), %rsi
    COPY32  %rdi, %rsi
    mov     NodeEvent_index(%r12), %rax
    mov     %rax, NodeBlob_index(%rdi)
    mov     NodeMessage_slot(%r13), %rax
    mov     %rax, NodeBlob_slot(%rdi)
    mov     NodeAction_data(%r12), %rax
    mov     %rax, NodeBlob_data_id(%rdi)
    movq    $NODE_BLOB_VALID, NodeBlob_status(%rdi)
    mov     NodeMessage_length(%r13), %rax
    mov     %rax, NodeBlob_length(%rdi)
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
75: cmp     $NODE_WORK_BACKFILL, %rax       # BACKFILL: a block of the backfill, checked
    jne     751f
    mov     NodeAction_target(%r12), %rax
    PART    %rdx, %rsi, %rbx, Node_blocks
    cmp     %rsi, %rax
    jae     79f
    imul    $NodeBlock__mem, %rax, %rax
    lea     (%rdx,%rax), %r13
    cmpq    $NODE_BLOCK_BF_CHECKING, NodeBlock_status(%r13)
    jne     79f
    test    %rcx, %rcx
    jnz     76f
    lea     NodeEvent_root(%r12), %rsi
    COPY32  %r13, %rsi
    mov     NodeEvent_index(%r12), %rax
    mov     %rax, NodeBlock_blobs(%r13)
    movq    $NODE_BLOCK_BACKFILL, NodeBlock_status(%r13)
    LEAVE 48
751: cmp    $NODE_WORK_SYNC_BLOCK, %rax     # SYNC_BLOCK: the root of a block of a response
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
    movq    $0, NodeBlock_data_id(%r13)
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
    movq    $0, NodeBlob_data_id(%r13)
    LEAVE 48
85: cmp     $NODE_WORK_NEW_PAYLOAD, %rax    # NEW_PAYLOAD, FORKCHOICE, PREPARE_PAYLOAD: the request to the execution engine
    je      86f
    cmp     $NODE_WORK_FORKCHOICE, %rax
    je      86f
    cmp     $NODE_WORK_PREPARE_PAYLOAD, %rax
    je      86f
    cmp     $NODE_WORK_GET_PAYLOAD, %rax
    jne     701f
86: test    %rcx, %rcx
    jnz     87f
    cmp     $NODE_WORK_PREPARE_PAYLOAD, %rax  # a preparation: its proposer; its call updates the fork choice too
    jne     851f
    andq    $~NODE_FLAG_FCU, Node_flags(%rbx)
    mov     NodeEvent_index(%r12), %rdx
    mov     %rdx, Node_payload_proposer(%rbx)
    movq    $NODE_PAYLOAD_SENT, Node_payload_status(%rbx)
    testq   $2, NodeAction_target(%r12)     # its payload_attributes text, after the request: to the topic's entries
    jz      851f
    mov     NodeEvent_chunk(%r12), %rax
    add     $NodeEvent_chunk, %rax
    cmp     (%r12), %rax
    jae     851f
    lea     (%r12,%rax), %rdi
    mov     $API_TOPIC_PAYLOAD_ATTRIBUTES, %esi
    call    node_api_events
851: mov    (NodeEvent_chunk + 16)(%r12), %r13
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
    cmpq    $NODE_WORK_PREPARE_PAYLOAD, NodeAction_work_kind(%r12)
    jne     870f
    movq    $0, Node_payload_status(%rbx)
    LEAVE 48
870: cmpq   $NODE_WORK_GET_PAYLOAD, NodeAction_work_kind(%r12)
    jne     871f
    mov     NodeAction_target(%r12), %rdi
    call    node_produce_fail_at
    LEAVE 48
871: cmpq   $NODE_WORK_NEW_PAYLOAD, NodeAction_work_kind(%r12)
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
    movq    $0, NodeBlock_data_id(%r13)
    LEAVE 48
701: cmp    $NODE_WORK_API_ENCODE, %rax     # API_ENCODE: the response to its connection
    jne     702f
    mov     %r12, %rdi
    call    node_api_done
    LEAVE 48
702: cmp    $NODE_WORK_API_CHUNK, %rax      # API_CHUNK: the chunk to its connection
    jne     703f
    mov     %r12, %rdi
    call    node_api_chunk_done
    LEAVE 48
703: cmp    $NODE_WORK_API_LOOKUP, %rax     # API_LOOKUP: the answer for the slot it found
    jne     704f
    mov     %r12, %rdi
    call    node_api_lookup_done
    LEAVE 48
704: cmp    $NODE_WORK_API_EVENT, %rax      # API_EVENT: the text to the streams of its topic
    jne     705f
    mov     %r12, %rdi
    call    node_api_event_done
    LEAVE 48
705: cmp    $NODE_WORK_API_SUBMIT, %rax     # API_SUBMIT: the operations to the pool and out, then the answer
    jne     706f
    mov     %r12, %rdi
    call    node_api_submit_done
    LEAVE 48
706: cmp    $NODE_WORK_POOL_CHECK, %rax     # POOL_CHECK: the entry stays, or goes
    jne     707f
    mov     %r12, %rdi
    call    node_pool_check_done
    LEAVE 48
707: cmp    $NODE_WORK_PRODUCE_CHECK, %rax  # the works of block production: their entry goes on
    je      708f
    cmp     $NODE_WORK_PRODUCE_FOLD, %rax
    je      708f
    cmp     $NODE_WORK_PRODUCE_BLOCK, %rax
    je      708f
    cmp     $NODE_WORK_PRODUCE_BID, %rax
    je      708f
    cmp     $NODE_WORK_PRODUCE_ETH1, %rax
    jne     709f
708: mov    %r12, %rdi
    call    node_produce_done
    LEAVE 48
709: cmp    $NODE_WORK_ETH1_CHECK, %rax     # ETH1_CHECK: the follower runs while the bridge is open
    jne     7091f
    mov     $2, %ecx
    mov     $1, %edx
    cmpq    $0, NodeEvent_index(%r12)
    cmovne  %rdx, %rcx
    mov     %rcx, Node_eth1_state(%rbx)
    mov     NodeEvent_checkpoint(%r12), %rcx
    mov     %rcx, Node_eth1_deposit_index(%rbx)
    LEAVE 48
7091: cmp   $NODE_WORK_CUSTODY, %rax        # CUSTODY: custody_need, when more
    jne     7094f
    mov     NodeEvent_index(%r12), %rcx
    cmp     Node_custody_need(%rbx), %rcx
    jbe     7095f
    mov     %rcx, Node_custody_need(%rbx)
7095: LEAVE 48
7094: cmp   $NODE_WORK_ARCHIVE_LOAD, %rax   # ARCHIVE_LOAD of the replay's copy: the replay goes on, or ends (2)
    jne     7092f
    mov     Node_replay_copy(%rbx), %rcx
    test    %rcx, %rcx
    jz      7093f
    cmp     NodeAction_state_a(%r12), %rcx
    jne     7093f
    xor     %ecx, %ecx
    mov     $2, %edx
    cmpq    $LANTERN_VALID, NodeEvent_result(%r12)
    cmovne  %rdx, %rcx
    mov     %rcx, Node_replay_loading(%rbx)
7093: LEAVE 48
7092: lea   -NODE_WORK_PUBLISH_DECODE(%rax), %rcx    # the works of block publishing: their entry goes on
    cmp     $(NODE_WORK_PUBLISH_SIDECAR - NODE_WORK_PUBLISH_DECODE), %rcx
    ja      70f
    mov     %r12, %rdi
    call    node_publish_done
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
 * rax = the first slot of the epochs a node must serve blocks of: max(0, the store's epoch -
 * compute_min_epochs_for_block_requests) * SLOTS_PER_EPOCH. Apart from node_request, as FORK_CALL
 * takes the labels 81 to 89. r12 the epoch. Locals: L the epochs.
 */
LOCAL_FUNCTION node_serve_slot
    ENTER 16
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %rdi
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, %r12
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    movq    $-1, L(%rsp)                    # no sum: every epoch
    lea     Node_config(%rbx), %rdi
    lea     L(%rsp), %rsi
    FORK_CALL compute_min_epochs_for_block_requests
    mov     %r12, %rax
    sub     L(%rsp), %rax
    jae     1f
    xor     %eax, %eax
1:  imul    $SLOTS_PER_EPOCH, %rax, %rax
    LEAVE 16
END_FUNCTION node_serve_slot

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
    movq    $40, (L + 160)(%rsp)            # blocks by head, from fulu on: 40 bytes
    cmp     $REQRESP_BEACON_BLOCKS_BY_HEAD, %r13
    je      21f
    movq    $32, (L + 160)(%rsp)            # the light client methods: 32 bytes, 16, or none
    cmp     $REQRESP_LIGHT_CLIENT_BOOTSTRAP, %r13
    je      3f
    movq    $16, (L + 160)(%rsp)
    cmp     $REQRESP_LIGHT_CLIENT_UPDATES_BY_RANGE, %r13
    je      3f
    movq    $0, (L + 160)(%rsp)
    cmp     $REQRESP_LIGHT_CLIENT_FINALITY_UPDATE, %r13
    je      55f
    cmp     $REQRESP_LIGHT_CLIENT_OPTIMISTIC_UPDATE, %r13
    je      55f
    movq    $0, (L + 160)(%rsp)
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
    cmp     $REQRESP_BEACON_BLOCKS_BY_HEAD, %r13
    je      94f
    cmp     $REQRESP_LIGHT_CLIENT_BOOTSTRAP, %r13
    je      55f
    cmp     $REQRESP_LIGHT_CLIENT_UPDATES_BY_RANGE, %r13
    je      55f
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
    mov     Node_attnets(%rbx), %rax
    mov     %rax, (L + 72)(%rsp)
    mov     Node_syncnets(%rbx), %rax
    mov     %al, (L + 80)(%rsp)
    mov     Node_custody_count(%rbx), %rax  # the custody group count
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
    mov     Node_earliest_slot(%rbx), %rax  # from the lower of earliest_slot and backfill_slot
    cmp     Node_backfill_slot(%rbx), %rax
    cmova   Node_backfill_slot(%rbx), %rax
    cmp     %rax, %r13
    jb      92b
    call    node_max_blocks                 # at most the limit, and the room of the list
    mov     S10(%rsp), %rcx
    cmp     %rax, %rcx
    cmova   %rax, %rcx
    add     %r13, %rcx                      # the end slot
    mov     $-1, %rax
    cmovc   %rax, %rcx
    mov     %rcx, S10(%rsp)
    movq    $0, (L + 160)(%rsp)             # the blocks of the Db in the range, in slot order
    mov     %r13, (L + 144)(%rsp)
600: mov    (L + 144)(%rsp), %rdi
    cmp     Node_db_next_slot(%rbx), %rdi
    jae     601f
    cmp     S10(%rsp), %rdi
    jae     601f
    incq    (L + 144)(%rsp)
    call    node_db_block
    test    %rax, %rax
    jz      600b
    mov     (L + 160)(%rsp), %rcx
    mov     %rax, NodeStream_request(%r12,%rcx,8)
    incq    (L + 160)(%rsp)
    jmp     600b
601: mov    (L + 160)(%rsp), %rax           # then the canonical blocks of the range from the head down, reversed
    mov     %rax, (L + 128)(%rsp)
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
    cmp     Node_db_next_slot(%rbx), %rax
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
63: lea     NodeStream_request(%r12), %rdi  # in slot order: the part from the head, reversed
    mov     (L + 160)(%rsp), %rcx
    lea     -8(%rdi,%rcx,8), %rsi
    mov     (L + 128)(%rsp), %rcx
    lea     (%rdi,%rcx,8), %rdi
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
    movq    $0, (L + 160)(%rsp)             # the sidecars of the Db in the range, of deneb or electra, in (slot, index) order
    mov     %r13, (L + 144)(%rsp)
650: mov    (L + 144)(%rsp), %rdi
    cmp     Node_db_next_slot(%rbx), %rdi
    jae     653f
    cmp     S10(%rsp), %rdi
    jae     653f
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_DENEB, %rax
    je      654f
    cmp     $FORK_ELECTRA, %rax
    jne     652f
654: movq   $0, (L + 152)(%rsp)
651: mov    (L + 152)(%rsp), %rsi
    cmp     (L + 72)(%rsp), %rsi
    jae     652f
    incq    (L + 152)(%rsp)
    mov     (L + 144)(%rsp), %rdi
    call    node_db_sidecar
    test    %rax, %rax
    jz      651b
    mov     (L + 160)(%rsp), %rcx
    mov     %rax, NodeStream_request(%r12,%rcx,8)
    incq    (L + 160)(%rsp)
    jmp     651b
652: incq   (L + 144)(%rsp)
    jmp     650b
653: mov    (L + 160)(%rsp), %rax           # then those of the canonical blocks from the head down, reversed
    mov     %rax, (L + 128)(%rsp)
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
    cmp     Node_db_next_slot(%rbx), %rax
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
    jz      762f
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
762: mov    Node_db(%rbx), %rdi             # else the Db's sidecar of the root and index, of deneb or electra
    add     %rbx, %rdi
    mov     S9(%rsp), %rsi
    sub     $40, %rsi
    lea     (L + 136)(%rsp), %rdx
    call    lantern_db_find_root
    mov     (L + 136)(%rsp), %rdi
    cmp     $-1, %rdi
    je      76b
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_DENEB, %rax
    je      763f
    cmp     $FORK_ELECTRA, %rax
    jne     76b
763: mov    (L + 136)(%rsp), %rdi
    mov     S9(%rsp), %rsi
    mov     -8(%rsi), %rsi
    call    node_db_sidecar
    test    %rax, %rax
    jz      76b
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
    je      711f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     71b
    mov     NodeBlock_data_id(%rdx), %rax
    test    %rax, %rax
    jnz     712f
711: mov    Node_db(%rbx), %rdi             # else the Db's block of the root
    add     %rbx, %rdi
    mov     S9(%rsp), %rsi
    sub     $32, %rsi
    lea     (L + 136)(%rsp), %rdx
    call    lantern_db_find_root
    mov     (L + 136)(%rsp), %rdi
    cmp     $-1, %rdi
    je      71b
    call    node_db_block
    test    %rax, %rax
    jz      71b
712: mov    S10(%rsp), %rcx
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
94: mov     S9(%rsp), %rax                  # BlocksByHead: the ancestry of beacon_root, from it, in descending slot order
    mov     32(%rax), %rax
    mov     %rax, (L + 168)(%rsp)
    call    node_max_blocks                 # at most count, the limit, and the room of the list
    cmp     (L + 168)(%rsp), %rax
    jae     941f
    mov     %rax, (L + 168)(%rsp)
941: call   node_serve_slot                 # the first slot of the epochs the node serves: L+152
    mov     %rax, (L + 152)(%rsp)
    movq    $0, S10(%rsp)
    mov     S9(%rsp), %rdi
    call    node_find_block
    cmp     $-1, %rax
    jne     95f
    mov     S9(%rsp), %rdi                  # a root the node does not keep: the Db's
    jmp     97f
95: mov     S10(%rsp), %rax                 # the node's imported blocks, by parent_root
    cmp     (L + 168)(%rsp), %rax
    jae     72b
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     72b
    mov     NodeBlock_data_id(%rdx), %rax
    test    %rax, %rax
    jz      96f
    mov     NodeBlock_slot(%rdx), %rcx
    cmp     (L + 152)(%rsp), %rcx
    jb      72b
    mov     S10(%rsp), %rcx
    mov     %rax, NodeStream_request(%r12,%rcx,8)
    incq    S10(%rsp)
    lea     NodeBlock_parent_root(%rdx), %rdi
    mov     %rdi, (L + 144)(%rsp)
    call    node_find_block
    cmp     $-1, %rax
    jne     95b
    mov     (L + 144)(%rsp), %rdi           # a parent the node does not keep: the Db's
    jmp     97f
96: mov     %rdx, %rdi                      # a block with no bytes: its record in the Db, or none
97: mov     %rdi, %rsi                      # the Db's blocks from the root at rdi, in descending slot order
    mov     Node_db(%rbx), %rdi
    add     %rbx, %rdi
    lea     (L + 136)(%rsp), %rdx
    call    lantern_db_find_root
    mov     (L + 136)(%rsp), %r13
    cmp     $-1, %r13
    je      72b
98: mov     S10(%rsp), %rax
    cmp     (L + 168)(%rsp), %rax
    jae     72b
    cmp     (L + 152)(%rsp), %r13
    jb      72b
    mov     %r13, %rdi
    call    node_db_block
    test    %rax, %rax
    jz      981f
    mov     S10(%rsp), %rcx
    mov     %rax, NodeStream_request(%r12,%rcx,8)
    incq    S10(%rsp)
981: mov    Node_db(%rbx), %rax
    add     %rbx, %rax
    cmp     Db_first_slot(%rax), %r13
    jbe     72b
    dec     %r13
    jmp     98b
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
    movq    $0, (L + 160)(%rsp)             # the sidecars of the Db in the range, of fulu or later, in (slot, column) order
    mov     %r13, (L + 144)(%rsp)
854: mov    (L + 144)(%rsp), %rdi
    cmp     Node_db_next_slot(%rbx), %rdi
    jae     857f
    cmp     S10(%rsp), %rdi
    jae     857f
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_FULU, %rax
    jb      856f
    movq    $0, (L + 152)(%rsp)
855: mov    (L + 152)(%rsp), %rsi
    cmp     $128, %rsi
    jae     856f
    incq    (L + 152)(%rsp)
    mov     %rsi, %rax
    shr     $6, %rax
    mov     (L + 80)(%rsp,%rax,8), %rax
    bt      %rsi, %rax
    jnc     855b
    mov     (L + 144)(%rsp), %rdi
    call    node_db_sidecar
    test    %rax, %rax
    jz      855b
    mov     (L + 160)(%rsp), %rcx
    mov     %rax, NodeStream_request(%r12,%rcx,8)
    incq    (L + 160)(%rsp)
    jmp     855b
856: incq   (L + 144)(%rsp)
    jmp     854b
857: mov    (L + 160)(%rsp), %rax           # then those of the canonical blocks from the head down, reversed
    mov     %rax, (L + 128)(%rsp)
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
    cmp     Node_db_next_slot(%rbx), %rax
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
    mov     %rsi, (L + 152)(%rsp)
    mov     (L + 64)(%rsp), %rdi
    call    node_blob_held
    test    %rax, %rax
    jz      892f
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
892: mov    Node_db(%rbx), %rdi             # else the Db's column of the root, of fulu or later
    add     %rbx, %rdi
    mov     (L + 64)(%rsp), %rsi
    lea     (L + 136)(%rsp), %rdx
    call    lantern_db_find_root
    mov     (L + 136)(%rsp), %rdi
    cmp     $-1, %rdi
    je      89b
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_FULU, %rax
    jb      89b
    mov     (L + 136)(%rsp), %rdi
    mov     (L + 152)(%rsp), %rsi
    call    node_db_sidecar
    test    %rax, %rax
    jz      89b
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
55: mov     %r12, %rdi                      # a light client method: its work
    mov     S9(%rsp), %rsi
    mov     (L + 160)(%rsp), %rdx
    call    node_lc_request
    LEAVE 176
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

/* The gossip topic rdi with the subnet rsi at the ForkDigest rdx: an event of kind rcx (SUBSCRIBE or UNSUBSCRIBE). r12 the topic's length, r13 the kind. Locals: L a GossipTopic, L+24 a ByteList of the topic. */
LOCAL_FUNCTION node_sub
    ENTER 176
    mov     %rcx, %r13
    mov     %rdx, (L + GossipTopic_fork_digest)(%rsp)
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
    mov     %r13, 8(%rax)
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
    mov     Node_earliest_slot(%rbx), %rcx  # earliest_available_slot: Status v2; custody_slot above it and the column window's start
    mov     Node_custody_slot(%rbx), %rax
    cmp     %rcx, %rax
    jbe     2f
    mov     %rcx, (L + 24)(%rsp)
    mov     %rbp, %rdi
    call    node_store_slot
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    sub     (Node_config + CONFIG_MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS)(%rbx), %rax
    jae     3f
    xor     %eax, %eax
3:  imul    $SLOTS_PER_EPOCH, %rax, %rax
    mov     (L + 24)(%rsp), %rcx
    cmp     Node_custody_slot(%rbx), %rax
    jae     2f
    mov     Node_custody_slot(%rbx), %rcx
2:  mov     %rcx, (L + 16)(%rsp)
    lea     84(%r12), %rdi
    lea     (L + 16)(%rsp), %rsi
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
    movq    $56, (%rax)                     # attnets: the bits of the node's subnets
    movq    $DISCV5_EVENT_SET_ENTRY, 8(%rax)
    movq    $7, 16(%rax)
    movabs  $0x007374656e747461, %rcx
    mov     %rcx, 24(%rax)
    movq    $0, 32(%rax)
    movq    $8, 40(%rax)
    mov     Node_attnets(%rbx), %rcx
    mov     %rcx, 48(%rax)
    add     $56, %rax
    mov     %rax, S7(%rsp)
    cmp     $FORK_ALTAIR, %r12
    jb      8f
    movq    $56, (%rax)                     # syncnets: the bits of the sync subnets the node keeps
    movq    $DISCV5_EVENT_SET_ENTRY, 8(%rax)
    movq    $8, 16(%rax)
    movabs  $0x7374656e636e7973, %rcx
    mov     %rcx, 24(%rax)
    movq    $0, 32(%rax)
    movq    $1, 40(%rax)
    mov     Node_syncnets(%rbx), %rcx
    mov     %rcx, 48(%rax)
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
    mov     Node_custody_count(%rbx), %rdx  # the custody group count
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
 * The gossip topics of the fork rdi at the ForkDigest rsi: an event of kind rdx (SUBSCRIBE or
 * UNSUBSCRIBE) for each. r12 the fork, r13 a subnet, S7 the subnets. Locals: L the digest, L+8 the
 * kind.
 */
LOCAL_FUNCTION node_topics
    ENTER 16
    mov     %rdi, %r12
    mov     %rsi, L(%rsp)
    mov     %rdx, (L + 8)(%rsp)
    .irp name, GOSSIP_BEACON_BLOCK, GOSSIP_BEACON_AGGREGATE_AND_PROOF, GOSSIP_VOLUNTARY_EXIT, GOSSIP_PROPOSER_SLASHING, GOSSIP_ATTESTER_SLASHING
    mov     $\name, %edi
    xor     %esi, %esi
    mov     L(%rsp), %rdx
    mov     (L + 8)(%rsp), %rcx
    call    node_sub
    .endr
    xor     %r13d, %r13d                    # beacon_attestation of each subnet the node keeps
10: cmp     $ATTESTATION_SUBNET_COUNT, %r13
    jae     12f
    mov     Node_subnets(%rbx), %rax
    bt      %r13, %rax
    jnc     11f
    mov     $GOSSIP_BEACON_ATTESTATION, %edi
    mov     %r13, %rsi
    mov     L(%rsp), %rdx
    mov     (L + 8)(%rsp), %rcx
    call    node_sub
11: inc     %r13
    jmp     10b
12:
    cmp     $FORK_ALTAIR, %r12
    jb      9f
    mov     $GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF, %edi
    xor     %esi, %esi
    mov     L(%rsp), %rdx
    mov     (L + 8)(%rsp), %rcx
    call    node_sub
    xor     %r13d, %r13d                    # sync_committee of each sync subnet the node keeps
13: cmp     $SYNC_COMMITTEE_SUBNET_COUNT, %r13
    jae     14f
    mov     Node_syncnets(%rbx), %rax
    bt      %r13, %rax
    jnc     15f
    mov     $GOSSIP_SYNC_COMMITTEE, %edi
    mov     %r13, %rsi
    mov     L(%rsp), %rdx
    mov     (L + 8)(%rsp), %rcx
    call    node_sub
15: inc     %r13
    jmp     13b
14: mov     $GOSSIP_LIGHT_CLIENT_FINALITY_UPDATE, %edi  # the light client topics
    xor     %esi, %esi
    mov     L(%rsp), %rdx
    mov     (L + 8)(%rsp), %rcx
    call    node_sub
    mov     $GOSSIP_LIGHT_CLIENT_OPTIMISTIC_UPDATE, %edi
    xor     %esi, %esi
    mov     L(%rsp), %rdx
    mov     (L + 8)(%rsp), %rcx
    call    node_sub
    cmp     $FORK_CAPELLA, %r12
    jb      9f
    mov     $GOSSIP_BLS_TO_EXECUTION_CHANGE, %edi
    xor     %esi, %esi
    mov     L(%rsp), %rdx
    mov     (L + 8)(%rsp), %rcx
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
    mov     L(%rsp), %rdx
    mov     (L + 8)(%rsp), %rcx
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
    mov     L(%rsp), %rdx
    mov     (L + 8)(%rsp), %rcx
    call    node_sub
7:  inc     %r13
    jmp     5b
9:  LEAVE 16
END_FUNCTION node_topics

/*
 * rax = the attestation subnets of the node at epoch rdi (node.md), bit i for subnet i:
 * lantern_compute_subscribed_subnet of the node ID for each index below SUBNETS_PER_NODE, of the
 * fork of the store's slot; 0 on a failure. Apart from node_subscribe, as FORK_CALL takes the
 * labels 81 to 89. r12 the subnets, r13 the index, S7 the fork. Locals: L the epoch, L+8 the
 * index, L+16 a subnet.
 */
LOCAL_FUNCTION node_attnets
    ENTER 32
    mov     %rdi, L(%rsp)
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, S7(%rsp)
    xor     %r12d, %r12d
    xor     %r13d, %r13d
1:  cmp     (Node_config + CONFIG_SUBNETS_PER_NODE)(%rbx), %r13
    jae     9f
    cmp     $ATTESTATION_SUBNET_COUNT, %r13
    jae     9f
    mov     %r13, (L + 8)(%rsp)
    mov     S7(%rsp), %r10
    lea     Node_node_id(%rbx), %rdi
    lea     L(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    lea     Node_config(%rbx), %rcx
    mov     %r14, %r8
    lea     (L + 16)(%rsp), %r9
    FORK_CALL compute_subscribed_subnet
    test    %rax, %rax
    jnz     8f
    mov     (L + 16)(%rsp), %rcx
    and     $(ATTESTATION_SUBNET_COUNT - 1), %ecx
    mov     $1, %eax
    shl     %cl, %rax
    or      %rax, %r12
    inc     %r13
    jmp     1b
8:  xor     %r12d, %r12d
9:  mov     %r12, %rax
    LEAVE 32
END_FUNCTION node_attnets

/* attnets takes the subnets of epoch rdi; a change adds 1 to metadata_seq. */
LOCAL_FUNCTION node_attnets_set
    FRAME 0
    call    node_attnets
    cmp     Node_attnets(%rbx), %rax
    je      1f
    mov     %rax, Node_attnets(%rbx)
    incq    Node_metadata_seq(%rbx)
1:  UNFRAME 0
END_FUNCTION node_attnets_set

/*
 * An event rsi (SUBSCRIBE or UNSUBSCRIBE) of the topic rdx (beacon_attestation or sync_committee)
 * of each subnet of rdi, at fork_digest and at next_digest when it is not 0. r12 the subnets, r13
 * the event, r14 the topic, S7 a subnet.
 */
LOCAL_FUNCTION node_subnet_topics
    ENTER 0
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     %rdx, %r14
    movq    $0, S7(%rsp)
1:  mov     S7(%rsp), %rax
    cmp     $64, %rax
    jae     9f
    bt      %rax, %r12
    jnc     3f
    mov     %r14, %rdi
    mov     S7(%rsp), %rsi
    mov     Node_fork_digest(%rbx), %rdx
    mov     %r13, %rcx
    call    node_sub
    mov     Node_next_digest(%rbx), %rdx
    test    %rdx, %rdx
    jz      3f
    mov     %r14, %rdi
    mov     S7(%rsp), %rsi
    mov     %r13, %rcx
    call    node_sub
3:  incq    S7(%rsp)
    jmp     1b
9:  LEAVE 0
END_FUNCTION node_subnet_topics

/*
 * rax = the beacon_attestation subnets the node keeps: those of attnets, and each whose
 * subnet_until is above the store rbp's slot (an aggregator's subscription).
 */
LOCAL_FUNCTION node_subnets_want
    FRAME 0
    mov     %rbp, %rdi
    call    node_store_slot
    mov     Node_attnets(%rbx), %rdx
    xor     %ecx, %ecx
1:  cmp     $ATTESTATION_SUBNET_COUNT, %rcx
    jae     9f
    cmp     %rax, Node_subnet_until(%rbx,%rcx,8)
    jbe     2f
    bts     %rcx, %rdx
2:  inc     %rcx
    jmp     1b
9:  mov     %rdx, %rax
    UNFRAME 0
END_FUNCTION node_subnets_want

/* rax = the sync_committee subnets the node keeps: each whose sync_until is above the epoch of the store rbp's slot. */
LOCAL_FUNCTION node_syncnets_want
    FRAME 0
    mov     %rbp, %rdi
    call    node_store_slot
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    xor     %r8d, %r8d
    xor     %ecx, %ecx
1:  cmp     $SYNC_COMMITTEE_SUBNET_COUNT, %rcx
    jae     9f
    cmp     %rax, Node_sync_until(%rbx,%rcx,8)
    jbe     2f
    bts     %rcx, %r8
2:  inc     %rcx
    jmp     1b
9:  mov     %r8, %rax
    UNFRAME 0
END_FUNCTION node_syncnets_want

/*
 * A SUBSCRIBE of data_column_sidecar of each subnet of a column of columns that no column of the
 * 16 bytes at rdi (the columns before) had, at fork_digest and at next_digest when it is not 0. r12
 * the old subnets below 64, r13 from 64, r14 the new ones below 64, r15 from 64, S7 a column, S8
 * the old columns.
 */
LOCAL_FUNCTION node_column_raise_topics
    ENTER 0
    mov     %rdi, S8(%rsp)
    xor     %r12d, %r12d
    xor     %r13d, %r13d
    xor     %r14d, %r14d
    xor     %r15d, %r15d
    mov     (Node_config + CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT)(%rbx), %r8
    test    %r8, %r8
    jz      9f
    xor     %r9d, %r9d                      # the column
1:  cmp     $128, %r9
    jae     5f
    mov     %r9, %rax
    xor     %edx, %edx
    div     %r8                             # rdx: its subnet
    mov     S8(%rsp), %rsi
    bt      %r9, (%rsi)
    jnc     2f
    cmp     $64, %rdx
    jae     11f
    bts     %rdx, %r12
    jmp     2f
11: lea     -64(%rdx), %rcx
    bts     %rcx, %r13
2:  bt      %r9, Node_columns(%rbx)
    jnc     3f
    cmp     $64, %rdx
    jae     21f
    bts     %rdx, %r14
    jmp     3f
21: lea     -64(%rdx), %rcx
    bts     %rcx, %r15
3:  inc     %r9
    jmp     1b
5:  not     %r12                            # the new ones
    and     %r12, %r14
    not     %r13
    and     %r13, %r15
    movq    $0, S7(%rsp)
6:  mov     S7(%rsp), %rax
    cmp     $128, %rax
    jae     9f
    cmp     $64, %rax
    jae     61f
    bt      %rax, %r14
    jmp     62f
61: lea     -64(%rax), %rcx
    bt      %rcx, %r15
62: jnc     7f
    mov     $GOSSIP_DATA_COLUMN_SIDECAR, %edi
    mov     S7(%rsp), %rsi
    mov     Node_fork_digest(%rbx), %rdx
    mov     $LIBP2P_EVENT_SUBSCRIBE, %ecx
    call    node_sub
    mov     Node_next_digest(%rbx), %rdx
    test    %rdx, %rdx
    jz      7f
    mov     $GOSSIP_DATA_COLUMN_SIDECAR, %edi
    mov     S7(%rsp), %rsi
    mov     $LIBP2P_EVENT_SUBSCRIBE, %ecx
    call    node_sub
7:  incq    S7(%rsp)
    jmp     6b
9:  LEAVE 0
END_FUNCTION node_column_raise_topics

/*
 * Validator custody (node.md), from fulu: once each store epoch, with a NodeProposer entry whose
 * until_epoch is above the store's epoch and F's post-state held, a NODE_WORK_CUSTODY of it. r12
 * the epoch, r13 the epoch + 1.
 */
LOCAL_FUNCTION node_custody_due
    ENTER 0
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %r14
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, %r12
    lea     1(%rax), %r13
    mov     %r14, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     $FORK_FULU, %rax
    jb      9f
    cmp     Node_custody_epoch(%rbx), %r13
    jbe     9f
    mov     Node_proposers(%rbx), %rcx      # a live preparation
    add     %rbx, %rcx
    mov     (Node_proposers + 8)(%rbx), %rdx
1:  test    %rdx, %rdx
    jz      9f
    cmp     NodeProposer_until_epoch(%rcx), %r12
    jb      2f
    add     $NodeProposer__mem, %rcx
    dec     %rdx
    jmp     1b
2:  lea     (Store_finalized_checkpoint + 8)(%rbp), %rdi
    call    node_find_block
    cmp     $-1, %rax
    je      9f
    mov     NodeBlock_state_id(%rdx), %rsi
    test    %rsi, %rsi
    jz      9f
    mov     %r13, Node_custody_epoch(%rbx)
    mov     $NODE_WORK_CUSTODY, %edi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    call    node_work
9:  LEAVE 0
END_FUNCTION node_custody_due

/*
 * The node's gossip topics (node.md; altair p2p-interface.md, Transitioning the gossip), one change
 * a step, when p2p_out has room: the topics of the fork of the store's epoch at its ForkDigest,
 * once for each digest, with the record entries; else those of the epoch NODE_SUBSCRIBE_AHEAD
 * later, when its digest differs; else, from NODE_SUBSCRIBE_AHEAD epochs after the digest changed,
 * the old digest's topics leave. r12 the epoch, r13 its fork, S7 its digest, S8 a fork. Locals: L
 * an epoch, L+8 a ForkDigest.
 */
LOCAL_FUNCTION node_subscribe
    ENTER 32
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
    mov     %rax, %rdi
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, %r12
    mov     %rax, L(%rsp)
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r13
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
    mov     %rax, S7(%rsp)
    testq   $NODE_FLAG_SUBSCRIBED, Node_flags(%rbx)
    jz      1f
    mov     Node_fork_digest(%rbx), %rcx
    cmp     %rcx, %rax
    je      20f
    mov     %rcx, Node_old_digest(%rbx)     # a new digest: the old one's topics leave later
    lea     NODE_SUBSCRIBE_AHEAD(%r12), %rax
    mov     %rax, Node_old_epoch(%rbx)
    xor     %edi, %edi                      # of the fork of the epoch before
    test    %r12, %r12
    jz      11f
    lea     -1(%r12), %rdi
    imul    $SLOTS_PER_EPOCH, %rdi, %rdi
11: lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, Node_old_fork(%rbx)
1:  mov     S7(%rsp), %rax
    mov     %rax, Node_fork_digest(%rbx)
    orq     $NODE_FLAG_SUBSCRIBED, Node_flags(%rbx)
    mov     %r12, %rdi                      # the subnets of the epoch, then those the node keeps
    call    node_attnets_set
    call    node_subnets_want
    mov     %rax, Node_subnets(%rbx)
    lea     L(%rsp), %rdi                   # the record entries of the new digest
    mov     %r13, %rsi
    call    node_enr_entries
    mov     Node_next_digest(%rbx), %rax    # its topics, unless they are there ahead
    movq    $0, Node_next_digest(%rbx)
    cmp     S7(%rsp), %rax
    je      9f
    mov     %r13, %rdi
    mov     S7(%rsp), %rsi
    mov     $LIBP2P_EVENT_SUBSCRIBE, %edx
    call    node_topics
    jmp     9f
20: lea     NODE_SUBSCRIBE_AHEAD(%r12), %rax    # ahead: the topics of the digest of a later epoch
    mov     %rax, L(%rsp)
    imul    $SLOTS_PER_EPOCH, %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, S8(%rsp)
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
    cmp     S7(%rsp), %rax
    je      30f
    cmp     Node_next_digest(%rbx), %rax
    je      30f
    mov     %rax, Node_next_digest(%rbx)
    mov     S8(%rsp), %rdi
    mov     %rax, %rsi
    mov     $LIBP2P_EVENT_SUBSCRIBE, %edx
    call    node_topics
    jmp     9f
30: mov     %r12, %rdi                      # the subnets of the epoch, when they changed: attnets and the record
    call    node_attnets
    cmp     Node_attnets(%rbx), %rax
    je      32f
    mov     %r12, %rdi
    call    node_attnets_set
    mov     %r12, L(%rsp)
    lea     L(%rsp), %rdi
    mov     %r13, %rsi
    call    node_enr_entries
    jmp     9f
32: call    node_subnets_want               # the subnets the node keeps, when they changed
    mov     Node_subnets(%rbx), %rcx
    cmp     %rcx, %rax
    je      33f
    mov     %rax, S8(%rsp)
    mov     %rcx, S9(%rsp)
    mov     %rax, %rdi                      # those that go, then those that come
    not     %rdi
    and     %rcx, %rdi
    mov     $LIBP2P_EVENT_UNSUBSCRIBE, %esi
    mov     $GOSSIP_BEACON_ATTESTATION, %edx
    call    node_subnet_topics
    mov     S9(%rsp), %rdi
    not     %rdi
    and     S8(%rsp), %rdi
    mov     $LIBP2P_EVENT_SUBSCRIBE, %esi
    mov     $GOSSIP_BEACON_ATTESTATION, %edx
    call    node_subnet_topics
    mov     S8(%rsp), %rax
    mov     %rax, Node_subnets(%rbx)
    jmp     9f
33: cmp     $FORK_ALTAIR, %r13              # the sync subnets the node keeps, when they changed: the MetaData and the record
    jb      34f
    call    node_syncnets_want
    mov     Node_syncnets(%rbx), %rcx
    cmp     %rcx, %rax
    je      34f
    mov     %rax, S8(%rsp)
    mov     %rcx, S9(%rsp)
    mov     %rax, %rdi
    not     %rdi
    and     %rcx, %rdi
    mov     $LIBP2P_EVENT_UNSUBSCRIBE, %esi
    mov     $GOSSIP_SYNC_COMMITTEE, %edx
    call    node_subnet_topics
    mov     S9(%rsp), %rdi
    not     %rdi
    and     S8(%rsp), %rdi
    mov     $LIBP2P_EVENT_SUBSCRIBE, %esi
    mov     $GOSSIP_SYNC_COMMITTEE, %edx
    call    node_subnet_topics
    mov     S8(%rsp), %rax
    mov     %rax, Node_syncnets(%rbx)
    incq    Node_metadata_seq(%rbx)
    mov     %r12, L(%rsp)
    lea     L(%rsp), %rdi
    mov     %r13, %rsi
    call    node_enr_entries
    jmp     9f
34: cmp     $FORK_FULU, %r13                # validator custody: a raise of custody_count, its columns, topics, MetaData and record
    jb      31f
    mov     Node_custody_need(%rbx), %rax
    cmp     Node_custody_count(%rbx), %rax
    jbe     31f
    mov     %rax, Node_custody_count(%rbx)
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, Node_custody_slot(%rbx)
    movdqu  Node_columns(%rbx), %xmm0
    movdqu  %xmm0, (L + 16)(%rsp)
    mov     (Node_config + CONFIG_SAMPLES_PER_SLOT)(%rbx), %rsi
    cmp     Node_custody_count(%rbx), %rsi
    cmovb   Node_custody_count(%rbx), %rsi
    lea     Node_node_id(%rbx), %rdi
    lea     Node_config(%rbx), %rdx
    lea     Node_columns(%rbx), %rcx
    call    node_custody_columns
    lea     (L + 16)(%rsp), %rdi
    call    node_column_raise_topics
    incq    Node_metadata_seq(%rbx)
    mov     %r12, L(%rsp)
    lea     L(%rsp), %rdi
    mov     %r13, %rsi
    call    node_enr_entries
    jmp     9f
31: mov     Node_old_digest(%rbx), %rsi     # the old digest's topics leave
    test    %rsi, %rsi
    jz      9f
    cmp     Node_old_epoch(%rbx), %r12
    jb      9f
    movq    $0, Node_old_digest(%rbx)
    mov     Node_old_fork(%rbx), %rdi
    mov     $LIBP2P_EVENT_UNSUBSCRIBE, %edx
    call    node_topics
9:  LEAVE 32
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
    mov     Node_fork_digest(%rbx), %rax    # a topic of no name: as of the node's ForkDigest
    mov     %rax, (L + GossipTopic_fork_digest)(%rsp)
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
    movq    $NODE_MESSAGE_OTHER_DIGEST, NodeMessage_state(%r13)    # a topic of another ForkDigest: IGNORE, unread
    mov     (L + GossipTopic_fork_digest)(%rsp), %rax
    cmp     Node_fork_digest(%rbx), %rax
    jne     99f
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
    jne     32f
    cmp     $(20 + 48), %rcx
    jb      5f
    add     $20, %rsi
4:  mov     (%rsi), %rax
    mov     %rax, NodeMessage_slot(%r13)
    lea     NodeMessage_parent_root(%r13), %rdi
    add     $16, %rsi
    mov     $32, %edx
    call    lantern_copy
    jmp     5f
32: cmp     $GOSSIP_BEACON_AGGREGATE_AND_PROOF, %rax  # an aggregate: the slot of its data
    jne     5f
    mov     S9(%rsp), %rdi
    call    node_aggregate
    mov     $-1, %rsi
    test    %rax, %rax
    jnz     33f
    cmp     $12, %rcx
    jb      33f
    mov     4(%rdx), %rsi
33: mov     %rsi, NodeMessage_slot(%r13)
5:  mov     S9(%rsp), %rdi                  # the bytes, kept by the shell
    call    node_put
    mov     %rax, NodeMessage_data_id(%r13)
    mov     S9(%rsp), %rcx
    mov     16(%rcx), %rcx
    mov     %rcx, NodeMessage_length(%r13)
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
    mov     NodeMessage_topic(%r13), %r9    # a light client update: matched against the light client store's
    cmp     $GOSSIP_LIGHT_CLIENT_FINALITY_UPDATE, %r9
    je      11f
    cmp     $GOSSIP_LIGHT_CLIENT_OPTIMISTIC_UPDATE, %r9
    jne     12f
11: mov     $NODE_WORK_LC_GOSSIP, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     NodeMessage_data_id(%r13), %rcx
    mov     NodeMessage_handle(%r13), %r8
    call    node_work
    movq    $NODE_LC_ID, NodeAction_state_c(%rax)
    movq    $NODE_MESSAGE_VALIDATING, NodeMessage_state(%r13)
    LEAVE 0
12: movq    $0, S7(%rsp)                    # the head state
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
    test    %rax, %rax
    jnz     22f
    mov     %rdx, S10(%rsp)                 # a parent with no post-state above F's slot: it again
    call    node_f_slot
    mov     S10(%rsp), %rdx
    cmp     %rax, NodeBlock_slot(%rdx)
    jbe     3f
    mov     %rdx, %rdi
    call    node_rebuild
    test    %rax, %rax
    jz      3f
    mov     S10(%rsp), %rdx
22: mov     %rax, S9(%rsp)
    mov     NodeBlock_slot(%rdx), %rdi      # of the same fork
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, S10(%rsp)
    mov     NodeMessage_slot(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     S10(%rsp), %rax
    jne     3f
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

/*
 * The Status of rdx bytes at rsi (84, or 92 for v2) of the peer of handle rdi, kept in its entry;
 * then the Status rules (phase0 p2p-interface.md): a fork_digest the node does not have, or a
 * finalized checkpoint of the node's finalized epoch or before that is not of the node's chain,
 * gives a DISCONNECT. r12 the bytes, then the peer's finalized epoch, r13 their size, then a slot,
 * S7 the entry. Locals: L the node's Status (92).
 */
LOCAL_FUNCTION node_peer_status
    ENTER 96
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
    lea     L(%rsp), %rdi                   # its fork_digest: the node's of the store's epoch, or the one ahead or before around a fork
    call    node_status_bytes
    mov     S7(%rsp), %rdx
    mov     NodePeer_fork_digest(%rdx), %rax
    mov     L(%rsp), %ecx
    cmp     %rcx, %rax
    je      2f
    cmp     Node_next_digest(%rbx), %rax
    je      2f
    cmp     Node_old_digest(%rbx), %rax
    jne     8f
2:  mov     NodePeer_finalized_epoch(%rdx), %r12    # its finalized checkpoint: of GENESIS_EPOCH, or after the store's, as it is
    test    %r12, %r12
    jz      9f
    cmp     Store_finalized_checkpoint(%rbp), %r12
    ja      9f
    jb      3f
    lea     NodePeer_finalized_root(%rdx), %rax     # the store's finalized epoch: its root
    lea     (Store_finalized_checkpoint + 8)(%rbp), %rcx
    NE32    %rax, %rcx, 8f
    jmp     9f
3:  mov     Node_db(%rbx), %rsi             # before: the Db's last block at or before the epoch's first slot
    add     %rbx, %rsi
    imul    $SLOTS_PER_EPOCH, %r12, %r13
    mov     Db_end_slot(%rsi), %rax
    test    %rax, %rax
    jz      9f
    dec     %rax
    cmp     %rax, %r13
    cmova   %rax, %r13
4:  cmp     Db_first_slot(%rsi), %r13
    jb      9f
    mov     %r13, %rax
    sub     Db_first_slot(%rsi), %rax
    imul    $DbSlot__mem, %rax, %rax
    add     Db_slots(%rsi), %rax
    add     %rsi, %rax
    cmpq    $0, DbSlot_block(%rax)
    jne     5f
    test    %r13, %r13
    jz      9f
    dec     %r13
    jmp     4b
5:  mov     S7(%rsp), %rdx
    lea     NodePeer_finalized_root(%rdx), %rcx
    NE32    %rcx, %rax, 8f                  # DbSlot_root
    jmp     9f
8:  mov     $LIBP2P_EVENT_DISCONNECT, %edi  # a DISCONNECT; it syncs nothing until it goes
    mov     S7(%rsp), %rax
    mov     NodePeer_handle(%rax), %rsi
    call    node_out_handle
    mov     S7(%rsp), %rax
    andq    $~NODE_PEER_STATUS, NodePeer_flags(%rax)
9:  LEAVE 96
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
    mov     Node_backfill_handle(%rbx), %rax    # the backfill's stream: the backfill has none
    test    %rax, %rax
    jz      2f
    cmp     NodeStream_handle(%rdi), %rax
    jne     2f
    movq    $0, Node_backfill_handle(%rbx)
    jmp     1f
2:  cmpq    $NODE_STREAM_OPENING, NodeStream_state(%rdi)
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
    mov     Node_api(%rbx), %rax            # the blobs' capacity: up to the api part
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
    call    node_new_block                  # a block: its entry, its bytes, the work of its root
    mov     %rax, (L + 48)(%rsp)
    mov     %rdi, (L + 96)(%rsp)
    mov     (L + 88)(%rsp), %rsi
    mov     (24 + 100)(%rsi), %rax
    mov     %rax, NodeBlock_slot(%rdi)
    add     $NodeBlock_parent_root, %rdi
    add     $(24 + 116), %rsi
    mov     $32, %edx
    call    lantern_copy
    mov     (L + 96)(%rsp), %rdi
    movq    $NODE_BLOCK_HASHING, NodeBlock_status(%rdi)    # of the backfill's stream: NODE_BLOCK_BF_CHECKING
    mov     NodeStream_handle(%r12), %rax
    cmp     Node_backfill_handle(%rbx), %rax
    jne     64f
    movq    $NODE_BLOCK_BF_CHECKING, NodeBlock_status(%rdi)
64: movq    $1, NodeBlock_data_available(%rdi)
    mov     (L + 88)(%rsp), %rdi
    call    node_put
    mov     (L + 96)(%rsp), %rdi
    mov     %rax, NodeBlock_data_id(%rdi)
    mov     %rax, (L + 80)(%rsp)
    mov     (L + 88)(%rsp), %rsi
    mov     16(%rsi), %rsi
    mov     %rsi, NodeBlock_length(%rdi)
    mov     $NODE_WORK_SYNC_BLOCK, %edi
    xor     %esi, %esi
    mov     (L + 96)(%rsp), %rax
    cmpq    $NODE_BLOCK_BF_CHECKING, NodeBlock_status(%rax)
    jne     641f
    incq    Node_backfill_got(%rbx)
    lea     (Store_finalized_checkpoint + 8)(%rbp), %rdi   # BACKFILL: with F's post-state
    call    node_find_block
    xor     %esi, %esi
    cmp     $-1, %rax
    je      642f
    mov     NodeBlock_state_id(%rdx), %rsi
642: mov    $NODE_WORK_BACKFILL, %edi
641: xor    %edx, %edx
    mov     (L + 80)(%rsp), %rcx
    mov     (L + 48)(%rsp), %r8
    xor     %r9d, %r9d
    call    node_work
    jmp     7f
61: call    node_new_blob                   # a blob sidecar: its entry, its bytes, the work of its checks
    mov     %rax, (L + 48)(%rsp)
    mov     %rdi, (L + 96)(%rsp)
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
    mov     (L + 88)(%rsp), %rsi
    mov     16(%rsi), %rsi
    mov     %rsi, NodeBlob_length(%rdi)
    mov     %rax, %rcx
    mov     $NODE_WORK_BLOB, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     (L + 48)(%rsp), %r8
    xor     %r9d, %r9d
    call    node_work
    jmp     7f
63: call    node_new_blob                   # a column sidecar: its entry, its bytes, the work of its checks
    mov     %rax, (L + 48)(%rsp)
    mov     %rdi, (L + 96)(%rsp)
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
    mov     (L + 88)(%rsp), %rsi
    mov     16(%rsi), %rsi
    mov     %rsi, NodeBlob_length(%rdi)
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
 * The sidecar requests of a range (node.md): a BlobSidecarsByRange v1 to the peer rdi of the slots of
 * rsi, count rdx, in the blob window whose fork is deneb or electra, then from fulu (rcx the fork of
 * the store's slot) the DataColumnSidecarsByRange v1 of the slots in the column window to the peers
 * with NODE_PEER_METADATA. rax = 1 when a request has no room or the node cannot open it, else 0.
 * Locals as node_sync's: L the range, L+24 a request's range, L+40 the fork, L+48 the columns asked,
 * L+64 count or send, L+72 the column requests, L+80 the peer, L+88 the request's bytes. r12 a peer,
 * r13 the peers left, S9 the scratch size.
 */
LOCAL_FUNCTION node_sidecar_ask
    ENTER 96
    mov     %rdi, (L + 80)(%rsp)
    mov     %rsi, L(%rsp)
    mov     %rdx, (L + 8)(%rsp)
    mov     %rcx, (L + 40)(%rsp)
    mov     %rdi, %r12
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
71: xor     %eax, %eax
    LEAVE 96
9:  mov     $1, %eax
    LEAVE 96
END_FUNCTION node_sidecar_ask

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
    jz      90f
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
    mov     (L + 80)(%rsp), %rdi            # the sidecar requests of the range
    mov     L(%rsp), %rsi
    mov     (L + 8)(%rsp), %rdx
    mov     (L + 40)(%rsp), %rcx
    call    node_sidecar_ask
    test    %rax, %rax
    jnz     9f
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
    jmp     9f
90: mov     %rbp, %rdi                      # none: a fresh Status of a peer, when the store's slot is above the start
    call    node_store_slot
    cmp     S8(%rsp), %rax
    jbe     9f
    mov     Node_status_ms(%rbx), %rax      # at most each NODE_STATUS_MS
    test    %rax, %rax
    jz      91f
    add     $NODE_STATUS_MS, %rax
    cmp     %rax, Node_time_ms(%rbx)
    jb      9f
91: mov     Node_messages(%rbx), %rax       # room for it
    sub     Node_streams(%rbx), %rax
    xor     %edx, %edx
    divq    Node_stream_bytes(%rbx)
    mov     (Node_streams + 8)(%rbx), %rcx
    inc     %rcx
    cmp     %rax, %rcx
    ja      9f
    PART    %r12, %r13, %rbx, Node_peers    # the first peer with a Status of the node's fork_digest
92: test    %r13, %r13
    jz      9f
    testq   $NODE_PEER_STATUS, NodePeer_flags(%r12)
    jz      93f
    mov     NodePeer_fork_digest(%r12), %rax
    cmp     Node_fork_digest(%rbx), %rax
    je      94f
93: add     $NodePeer__mem, %r12
    dec     %r13
    jmp     92b
94: mov     (L + 40)(%rsp), %rax            # the fork of the store's slot: v2 from fulu
    mov     %rax, S9(%rsp)
    lea     L(%rsp), %rdi
    call    node_status_bytes
    mov     $1, %esi
    mov     $84, %r8d
    cmpq    $FORK_FULU, S9(%rsp)
    jb      95f
    mov     $2, %esi
    mov     $92, %r8d
95: mov     $REQRESP_STATUS, %edi
    mov     NodePeer_handle(%r12), %rdx
    lea     L(%rsp), %rcx
    call    node_open
    test    %rax, %rax
    jz      9f
    mov     Node_time_ms(%rbx), %rax
    mov     %rax, Node_status_ms(%rbx)
9:  call    node_backfill_ask
    mov     S7(%rsp), %rax
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
    mov     LIBP2P_ACT_SO_TAG(%r12), %rcx   # the backfill's stream: its handle
    cmp     Node_backfill_handle(%rbx), %rcx
    jne     621f
    mov     %rax, Node_backfill_handle(%rbx)
621: movq   $NODE_STREAM_RESPONSE, NodeStream_state(%r13)
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
    lea     NodePeer_address(%r13), %rdi    # its connection's address and transport
    lea     LIBP2P_ACT_PC_ADDR(%r12), %rsi
    mov     $32, %edx
    call    lantern_copy
    mov     LIBP2P_ACT_PC_TRANSPORT(%r12), %rax
    mov     %rax, NodePeer_transport(%r13)
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
    ENTER 240
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, (L + 16)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
    mov     8(%r8), %r12
    add     %r8, %r12
    mov     16(%r8), %r13
    add     %r12, %r13
    mov     %r9, %r14
    mov     (240 + 96)(%rsp), %r15          # the seventh and eighth arguments
    mov     (240 + 104)(%rsp), %rax
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
    movq    $0, (L + 208)(%rsp)              # API: the largest scratch, and the API events
    movq    $0, (L + 216)(%rsp)
    movq    $0, (L + 224)(%rsp)             # the p2p_out bytes of the pool POSTs' publishes
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
    cmp     $NODE_EV_BUILDER, %rdx          # BUILDER: a call, + 256 for a failure, else its bytes; with NODE_FLAG_BUILDER
    jne     161f
    testq   $NODE_FLAG_BUILDER, Node_flags(%rbx)
    jz      7f
    cmp     $24, %rcx
    jb      7f
    movzbl  16(%rdi), %esi
    cmp     $NODE_BUILDER_CALLS, %rsi
    jae     7f
    mov     16(%rdi), %rsi
    shr     $8, %rsi
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
    jmp     4f
161: cmp    $NODE_EV_DB_ARCHIVE, %rdx       # DB_ARCHIVE: a state record the shell wrote; with NODE_FLAG_DB
    jne     162f
    testq   $NODE_FLAG_DB, Node_flags(%rbx)
    jz      7f
    cmp     $NODE_EV_DB_ARCHIVE_SIZE, %rcx
    jb      7f
    jmp     4f
162: cmp    $NODE_EV_API_SENT, %rdx         # API_SENT, API_CLOSED: the connection at 16
    jb      11f
    cmp     $24, %rcx
    jb      7f
    jmp     4f
11: cmp     $NODE_EV_TICK, %rdx
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
    cmp     $NODE_WORK_IMPORT_BLOCK, %rsi   # a valid IMPORT_BLOCK: a work for each vote
    jne     204f
    cmpq    $0, NodeEvent_result(%rdi)
    jne     22f
    mov     NodeEvent_index(%rdi), %rsi
    cmp     $128, %rsi
    jbe     205f
    mov     $128, %esi
205: mov    NodeEvent_root(%rdi), %rdx
    cmp     $2, %rdx
    jbe     206f
    mov     $2, %edx
206: add    %rdx, %rsi
    inc     %rsi                            # and its light client work
    imul    $NODE_ACT_WORK_SIZE, %rsi, %rsi
    add     %rsi, %r10
    jmp     22f
204: lea    -NODE_WORK_PUBLISH_DECODE(%rsi), %rax   # the works of a publish: an API answer; of LANTERN_VALID, bytes inside
    cmp     $(NODE_WORK_PUBLISH_SIDECAR - NODE_WORK_PUBLISH_DECODE), %rax
    ja      2042f
    incq    (L + 216)(%rsp)
    cmp     $NODE_WORK_PUBLISH_CHECK, %rsi  # a block, or a blob, it may add
    jne     2043f
    inc     %r9
2043: cmp   $NODE_WORK_PUBLISH_SIDECAR, %rsi
    jne     2044f
    incq    (L + 120)(%rsp)
2044: cmpq  $0, NodeEvent_result(%rdi)
    jne     22f
    cmp     $NODE_WORK_PUBLISH_SIDECARS, %rsi
    je      22f
    cmp     $(NodeEvent_chunk + 24), %rcx   # its ByteList at NodeEvent_chunk
    jb      7f
    cmpq    $24, (NodeEvent_chunk + 8)(%rdi)
    jne     7f
    lea     -(NodeEvent_chunk + 24)(%rcx), %rax
    cmp     %rax, (NodeEvent_chunk + 16)(%rdi)
    ja      7f
    add     %rcx, %r10                      # its bytes of actions
    testq   $NODE_FLAG_SUBSCRIBED, Node_flags(%rbx) # subscribed: p2p_out for its publish, and scratch for it
    jz      22f
    lea     512(,%rcx,2), %rax
    add     %rax, (L + 224)(%rsp)
    lea     (SNAPPY_SCRATCH_COMPRESS + 192)(%rcx), %rax
    cmp     (L + 208)(%rsp), %rax
    jbe     22f
    mov     %rax, (L + 208)(%rsp)
    jmp     22f
2042: cmp   $NODE_WORK_SERVE, %rsi
    je      202f
    cmp     $NODE_WORK_API_SUBMIT, %rsi     # API_SUBMIT: an API answer; of LANTERN_VALID, its records inside
    jne     2041f
    incq    (L + 216)(%rsp)
    cmpq    $0, NodeEvent_result(%rdi)
    jne     22f
    call    node_submit_check
    test    %rax, %rax
    jnz     7f
    add     %rcx, %r10                      # twice its bytes of actions
    testq   $NODE_FLAG_SUBSCRIBED, Node_flags(%rbx) # subscribed: p2p_out for its publishes, and scratch for one
    jz      22f
    imul    $512, NodeEvent_index(%rdi), %rax
    lea     (%rax,%rcx,2), %rax
    add     %rax, (L + 224)(%rsp)
    lea     (SNAPPY_SCRATCH_COMPRESS + 192)(%rcx), %rax
    cmp     (L + 208)(%rsp), %rax
    jbe     22f
    mov     %rax, (L + 208)(%rsp)
    jmp     22f
2041:
    cmp     $NODE_WORK_API_LOOKUP, %rsi     # API_LOOKUP: an API answer's scratch and actions
    jne     208f
    cmpq    $NODE_API_SCRATCH, (L + 208)(%rsp)
    jae     209f
    movq    $NODE_API_SCRATCH, (L + 208)(%rsp)
209: incq   (L + 216)(%rsp)
    jmp     22f
208: cmp    $NODE_WORK_API_CHUNK, %rsi      # API_CHUNK of LANTERN_VALID: its ByteList at NodeEvent_api_bytes
    jne     207f
    cmpq    $0, NodeEvent_result(%rdi)
    jne     22f
    cmp     $(NodeEvent_api_bytes + 24), %rcx
    jb      7f
    cmpq    $24, (NodeEvent_api_bytes + 8)(%rdi)
    jne     7f
    lea     -(NodeEvent_api_bytes + 24)(%rcx), %rsi
    cmp     %rsi, (NodeEvent_api_bytes + 16)(%rdi)
    ja      7f
    jmp     22f
207: cmp    $NODE_WORK_API_ENCODE, %rsi
    je      203f
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
33: cmp     $NODE_EV_API, %rdx              # API, API_IDENTITY: their bytes keep their rules
    jb      34f
    mov     %rdi, (L + 160)(%rsp)
    mov     %rcx, (L + 168)(%rsp)
    mov     %r8, (L + 176)(%rsp)
    mov     %r9, (L + 184)(%rsp)
    mov     %r10, (L + 192)(%rsp)
    mov     %r11, (L + 200)(%rsp)
    call    node_api_check
    mov     (L + 160)(%rsp), %rdi
    mov     (L + 168)(%rsp), %rcx
    mov     (L + 176)(%rsp), %r8
    mov     (L + 184)(%rsp), %r9
    mov     (L + 192)(%rsp), %r10
    mov     (L + 200)(%rsp), %r11
    test    %rax, %rax
    jnz     7f
    cmp     (L + 208)(%rsp), %rdx
    jbe     35f
    mov     %rdx, (L + 208)(%rsp)
35: cmpq    $NODE_EV_API, 8(%rdi)
    jne     4f
    incq    (L + 216)(%rsp)
    cmpq    $0, (NodeEvent_bytes + 24 + HttpRequest_status)(%rdi)  # API: 16 bytes of actions for each byte of the body, its ids
    jne     4f
    mov     (NodeEvent_bytes + 24 + HttpRequest_body + 8)(%rdi), %rax
    shl     $4, %rax
    add     %rax, %r10
    jmp     4f
34: cmp     $NODE_EV_BLOCK, %rdx
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
    call    node_api_publish_count          # an answer for each publishBlockV2 that waits
    add     %rax, (L + 216)(%rsp)
    mov     %r8, S8(%rsp)
    mov     %r11, L(%rsp)
    call    node_api_event_count            # with event streams: NODE_API_SCRATCH of scratch, 1024 per event for each
    test    %rax, %rax
    jz      58f
    cmpq    $NODE_API_SCRATCH, (L + 208)(%rsp)
    jae     58f
    movq    $NODE_API_SCRATCH, (L + 208)(%rsp)
58: shl     $10, %rax
    add     $512, %rax
    imul    %r8, %rax
    mov     %rax, %rcx                      # room: actions, node parts, scratch
    add     %r10, %rcx
    add     $(2 * NODE_ACT_WORK_SIZE), %rcx
    imul    $NODE_ACT_WORK_SIZE, (Node_pool + 8)(%rbx), %rdx    # a POOL_CHECK for each pool entry
    add     %rdx, %rcx
    mov     (L + 216)(%rsp), %rdx           # 2048 for each API answer
    shl     $11, %rdx
    add     %rdx, %rcx
    imul    $384, (Node_blocks + 8)(%rbx), %rdx    # the prune's and the rebuilds' actions: 384 for each block, 160 for each blob, 32 for each checkpoint
    add     %rdx, %rcx
    imul    $160, (Node_blobs + 8)(%rbx), %rdx
    add     %rdx, %rcx
    mov     (Node_checkpoints + 8)(%rbx), %rdx
    shl     $5, %rdx
    add     %rdx, %rcx
    add     $2048, %rcx                     # and 2048 free: the crossing of a fork boundary takes 208
    cmpq    $ENGINE_METHOD_GET_PAYLOAD, Node_engine_method(%rbx)  # a getPayload in flight: its result's bytes, as engine_in holds them, and 1072
    jne     581f
    mov     Node_engine_in(%rbx), %rdx
    add     16(%rbx,%rdx), %rcx
    add     $1072, %rcx
581: cmpq   $1, Node_eth1_state(%rbx)    # the eth1 follower: its snapshot and its call
    jne     582f
    mov     %rcx, (L + 72)(%rsp)
    call    node_eth1_snapshot_size
    mov     (L + 72)(%rsp), %rcx
    add     %rax, %rcx
    add     $2048, %rcx
582: mov    %rcx, (L + 72)(%rsp)
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
    mov     Node_api(%rbx), %rax            # blobs: one for each GOSSIP WORK_DONE event, and with p2p a batch's sidecars
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
    testq   $NODE_FLAG_DB, Node_flags(%rbx) # with NODE_FLAG_DB at a new finalized epoch: the Db's room for the archive
    jz      56f
    mov     Node_db(%rbx), %rsi
    add     %rbx, %rsi
    mov     Store_finalized_checkpoint(%rbp), %rax
    cmp     Node_pruned_epoch(%rbx), %rax
    jbe     561f
    imul    $SLOTS_PER_EPOCH, %rax, %rax    # the slots to the finalized checkpoint's
    inc     %rax
    xor     %ecx, %ecx
    sub     Db_first_slot(%rsi), %rax
    cmovb   %rcx, %rax
    cmp     %rax, (Db_slots + 8)(%rsi)
    jb      93f
561: mov    Db_blocks(%rsi), %rax           # the roots, at each step for the backfill: twice the blocks
    add     (Node_blocks + 8)(%rbx), %rax
    shl     $1, %rax
    cmp     %rax, (Db_roots + 8)(%rsi)
    jb      94f
    cmpq    $-1, Node_backfill_start(%rbx)  # a backfill request open or unweighed: the slots below backfill_slot
    je      56f
    mov     Node_backfill_slot(%rbx), %rax
    xor     %ecx, %ecx
    sub     Db_first_slot(%rsi), %rax
    cmovb   %rcx, %rax
    cmp     %rax, (Db_slots + 8)(%rsi)
    jb      93f
56:
    cmpq    $0, (L + 216)(%rsp)             # api: an entry free for each API event
    je      57f
    call    node_api_free
    cmp     (L + 216)(%rsp), %rax
    jb      95f
57: cmpq    $1, Node_eth1_state(%rbx)    # eth1_deposits: NODE_ETH1_ROOM entries free while the follower runs
    jne     571f
    mov     Node_eth1_leaves(%rbx), %rax
    sub     Node_eth1_deposits(%rbx), %rax
    xor     %edx, %edx
    mov     $Eth1Deposit__mem, %ecx
    div     %rcx
    sub     (Node_eth1_deposits + 8)(%rbx), %rax
    cmp     $NODE_ETH1_ROOM, %rax
    jb      9601f
571:
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
    P2P_OUT %rcx                            # the queue has room for the P2P events, and the publishes of the pool POSTs
    mov     (%rcx), %rax
    sub     $24, %rax
    sub     16(%rcx), %rax
    mov     (L + 56)(%rsp), %rdx
    add     (L + 224)(%rsp), %rdx
    cmp     %rdx, %rax
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
    mov     (Node_blocks + 8)(%rbx), %rcx   # and the prune's chain of blocks
    shl     $3, %rcx
    add     %rcx, %rax
    cmpq    $0, (L + 136)(%rsp)             # with an ENR event, the record's decoding
    je      53f
    MOVQ    %rcx, DISCV5_ENR_SIZE + DISCV5_ENR_SCRATCH
    add     %rcx, %rax
53: add     (L + 208)(%rsp), %rax           # and the largest API answer's
    mov     (%r14), %rcx
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
30: call    node_prune                      # at a new finalized epoch, the prune; then each event, in order
    mov     (%r14), %rax
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
    call    node_publish_poll               # the answers of the published blocks whose import ended
    call    node_eth1_check_due             # the eth1 follower's check, each store epoch
    call    node_custody_due                # validator custody's check, each store epoch
    call    node_engine_next
    call    node_shed                       # the post-states the node can rebuild go
    call    node_api_head_events            # the head and finalized_checkpoint events, at a quiet point
    call    node_lc_due                     # the light client updates due on gossip
    call    node_produce_due                # the produceBlockV3 entries whose bid is late
    call    node_replay_due                 # the replay in flight: its next blocks
    call    node_backfill_link              # the backfill's blocks of the chain join the Db
    call    node_drop_sidecars              # the sidecars the node no longer serves go
    movq    $0, (L + 112)(%rsp)
    cmpq    $0, (L + 16)(%rsp)              # the next block of each stream that serves, then libp2p again
    je      40f
    call    node_subscribe
    call    node_serve
    mov     %rax, (L + 112)(%rsp)
    call    node_vote_due                   # the votes of valid aggregates whose slot is past
    or      %rax, (L + 112)(%rsp)
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
    LEAVE 240
14: mov     (L + 8)(%rsp), %rcx             # a status before any change
    mov     %rcx, (%r14)
    LEAVE 240
7:  mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 240
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
93: mov     $NodeRoom_db_slots, %ecx
    jmp     82f
94: mov     $NodeRoom_db_roots, %ecx
    jmp     82f
95: mov     $NodeRoom_api_streams, %ecx
    jmp     82f
9601: mov   $NodeRoom_eth1_deposits, %ecx
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
    LEAVE 240
END_FUNCTION lantern_node_step

/*
 * (node, store, seen, work, state_a, state_b, state_c, data, settings, scratch, event): rbx node,
 * rbp store, r12 work, r13 state_a, r14 data, r15 scratch, S7 the seventh argument of a call, S8
 * event, S9 the event's room, S10 a temporary. Locals: L the BlockOptions (32), or a chunk's size,
 * a fork digest and a ChunkHeader (64); L+64 seen, L+72 state_b, L+80 state_c, L+88 settings,
 * L+96 a NodeGossip.
 */
# The StateRoom of an upgraded state (node.md, NODE_WORK_UPGRADE): as the binary's anchor has.
    RODATA
    .p2align 3
node_upgrade_room:
    .quad 1024, 2048, 64, 1024, 64, 64, 4, 4096

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
    cmp     $NODE_WORK_LC_SERVE, %rax       # LC_SERVE: the answer of a light client method, in the event's room
    jne     4f
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %r14, %rdx
    mov     (L + 80)(%rsp), %rcx
    mov     %r15, %r8
    mov     S8(%rsp), %r9
    mov     S9(%rsp), %r10
    call    node_run_lc_serve
    LEAVE 192
4:  lea     -NODE_WORK_LC_GOSSIP(%rax), %rcx    # LC_GOSSIP, LC_PUBLISH: the latest update of a topic, in the event's room
    cmp     $(NODE_WORK_LC_PUBLISH - NODE_WORK_LC_GOSSIP), %rcx
    ja      41f
    mov     %rbx, %rdi
    mov     %r12, %rsi
    mov     %r14, %rdx
    mov     (L + 80)(%rsp), %rcx
    mov     %r15, %r8
    mov     S8(%rsp), %r9
    mov     S9(%rsp), %r10
    call    node_run_lc_gossip
    LEAVE 192
41: lea     -NODE_WORK_LC_BLOCK(%rax), %rcx # the light client works: of the light client store, state_c
    cmp     $(NODE_WORK_LC_HEAD - NODE_WORK_LC_BLOCK), %rcx
    ja      5f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    mov     (L + 80)(%rsp), %r9
    mov     %r15, %r10
    mov     S8(%rsp), %r11
    call    node_run_lc
    LEAVE 192
5:  cmp     $NODE_WORK_IMPORT_BLOCK, %rax
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
    mov     %rdi, (L + 40)(%rsp)            # the block's slot, then its fork
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, (L + 48)(%rsp)
    mov     NODE_STATE_SLOT(%r13), %rdi     # the state's slot of the block's fork
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     (L + 48)(%rsp), %rax
    jne     19f
    xor     %eax, %eax                      # slots_done: the state at the block's slot, the first of its fork
    mov     NODE_STATE_SLOT(%r13), %rdi
    cmp     (L + 40)(%rsp), %rdi
    jne     11f
    test    %rdi, %rdi
    jz      11f
    dec     %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     (L + 48)(%rsp), %rax
    setne   %al
    movzbl  %al, %eax
11: mov     %rax, (L + BlockOptions_slots_done)(%rsp)
    mov     (L + 48)(%rsp), %r10
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
    jne     972f
    mov     S8(%rsp), %rcx
    mov     %rax, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
972: test   %rax, %rax                      # valid: the counts of its votes
    jnz     973f
    mov     S8(%rsp), %rsi
    cmpq    $0, NodeEvent_result(%rsi)
    jne     973f
    mov     %r14, %rdi
    call    node_vote_counts
    xor     %eax, %eax
973: LEAVE 192
18: mov     S8(%rsp), %rcx
    movq    $LANTERN_INVALID_ENCODING, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
19: mov     S8(%rsp), %rcx
    movq    $LANTERN_INVALID_SLOT, NodeEvent_result(%rcx)
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
    mov     %rax, (L + 40)(%rsp)
    test    %r13, %r13                      # a state of another fork: IGNORE
    jz      41f
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     (L + 40)(%rsp), %rax
    jne     69f
41: mov     (L + 40)(%rsp), %r10
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
    mov     NodeAction_arg(%r12), %rdx      # blocks by head: a context too
    shr     $8, %rdx
    cmp     $REQRESP_BEACON_BLOCKS_BY_HEAD, %rdx
    cmove   %rcx, %rax
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
    mov     %rbp, %rdi                      # GOSSIP: the fork of the store's slot; a head state of another: IGNORE
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, (L + 40)(%rsp)
    test    %r13, %r13
    jz      61f
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     (L + 40)(%rsp), %rax
    jne     69f
61: mov     (L + 64)(%rsp), %rax            # the inputs of the fork's node_gossip
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
    mov     (L + 72)(%rsp), %rax            # the proposer and justified states, 0 when of another fork
    test    %rax, %rax
    jz      62f
    mov     NODE_STATE_SLOT(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     (L + 40)(%rsp), %rax
    mov     $0, %eax
    cmove   (L + 72)(%rsp), %rax
62: mov     %rax, (L + 96 + NodeGossip_proposer)(%rsp)
    mov     (L + 80)(%rsp), %rax
    test    %rax, %rax
    jz      63f
    mov     NODE_STATE_SLOT(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     (L + 40)(%rsp), %rax
    mov     $0, %eax
    cmove   (L + 80)(%rsp), %rax
63: mov     %rax, (L + 96 + NodeGossip_justified)(%rsp)
    mov     (L + 88)(%rsp), %rax
    mov     %rax, (L + 96 + NodeGossip_settings)(%rsp)
    lea     Node_config(%rbx), %rax
    mov     %rax, (L + 96 + NodeGossip_config)(%rsp)
    mov     (L + 40)(%rsp), %r10
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
69: mov     S8(%rsp), %rcx
    movq    $LANTERN_GOSSIP_IGNORE, NodeEvent_result(%rcx)
    xor     %eax, %eax
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
    jne     830f
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
    xor     %r14d, %r14d                    # no payload attributes
    mov     (%r15), %rax
    mov     %rax, S10(%rsp)
    # The request of the ForkchoiceState at L+96 and the attributes r14 (or 0), with S10 the
    # scratch's size to give back. At the end of scratch: the JSON (536, or FCU_JSON_ATTRIBUTES
    # with attributes), the token (280), the host (88); L+8 the JSON's room.
831: cmpq   $(NodeEvent_chunk + 24), S9(%rsp)
    jb      832f
    mov     $536, %ecx
    mov     $FCU_JSON_ATTRIBUTES, %edx
    test    %r14, %r14
    cmovnz  %rdx, %rcx
    mov     %rcx, (L + 8)(%rsp)
    lea     368(%rcx), %rdx
    mov     (%r15), %rax
    lea     512(%rdx), %rsi
    cmp     %rsi, %rax
    jb      832f
    sub     %rdx, %rax
    mov     %rax, (%r15)
    lea     (%r15,%rax), %r13
    mov     %rcx, (%r13)
    movq    $24, 8(%r13)
    movq    $0, 16(%r13)
    lea     (%r13,%rcx), %rsi               # the token, then the host
    movq    $280, (%rsi)
    movq    $24, 8(%rsi)
    movq    $0, 16(%rsi)
    movq    $88, 280(%rsi)
    movq    $24, (280 + 8)(%rsi)
    mov     Node_engine_host_len(%rbx), %rdx
    mov     %rdx, (280 + 16)(%rsi)
    lea     (280 + 24)(%rsi), %rdi
    lea     Node_engine_host(%rbx), %rsi
    call    lantern_copy
    lea     (L + 96)(%rsp), %rdi
    mov     %r14, %rsi
    lea     NodeAction_arg(%r12), %rdx
    mov     %r13, %rcx
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
    mov     (L + 8)(%rsp), %rcx
    add     %r13, %rcx
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
    mov     (L + 8)(%rsp), %rsi
    add     %r13, %rsi
    lea     280(%rsi), %rdi
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
    cmpq    $NODE_WORK_PREPARE_PAYLOAD, NodeAction_work_kind(%r12)  # a preparation with 2 in target: the payload_attributes text after it
    jne     841f
    testq   $2, NodeAction_target(%r12)
    jz      841f
    lea     (%rcx,%rax), %rdi
    mov     S9(%rsp), %rdx
    sub     %rax, %rdx
    and     $-8, %rdx
    cmp     $64, %rdx
    jb      842f
    mov     %rdx, (%rdi)
    movq    $24, 8(%rdi)
    movq    $0, 16(%rdi)
    mov     (L + 32)(%rsp), %rsi
    mov     %r14, %rdx
    mov     NodeEvent_index(%rcx), %rcx
    lea     Node_payload_root(%rbx), %r8
    mov     S7(%rsp), %r10
    call    api_payload_event_text
    test    %rax, %rax
    jnz     842f
    mov     S8(%rsp), %rcx
    mov     (%rcx), %rax
    lea     (%rcx,%rax), %rdx
    mov     16(%rdx), %r8
    add     $(24 + 7), %r8
    and     $-8, %r8
    mov     %r8, (%rdx)
    add     %r8, %rax
    mov     %rax, (%rcx)
841: xor    %eax, %eax
    LEAVE 192
842: mov    $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 192
85: mov     S10(%rsp), %rcx                 # a status, with the scratch's size back
    mov     %rcx, (%r15)
    LEAVE 192
832: mov    S10(%rsp), %rcx                 # too little room, with the scratch's size back
    mov     %rcx, (%r15)
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 192
86: mov     S8(%rsp), %rcx
    movq    $LANTERN_NO_PAYLOAD, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
87: mov     S8(%rsp), %rcx
    movq    $LANTERN_INVALID_UNKNOWN_BLOCK, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
830: cmp    $NODE_WORK_PREPARE_PAYLOAD, %rax
    jne     890f
    test    %r13, %r13                      # PREPARE_PAYLOAD: of the fork of the state's slot; the state at L+32
    jz      837f
    mov     %r13, (L + 32)(%rsp)
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, S7(%rsp)
    cmp     $FORK_BELLATRIX, %rax
    jb      836f
    mov     %r13, %rdi                      # the proposer: (state, out) in fulu, (state, scratch, out) before
    lea     (L + 16)(%rsp), %rdx
    mov     %r15, %rsi
    cmp     $FORK_FULU, %rax
    cmovae  %rdx, %rsi
    mov     %rax, %r10
    FORK_CALL get_beacon_proposer_index
    test    %rax, %rax
    jnz     838f
    mov     (L + 16)(%rsp), %rdx
    mov     S8(%rsp), %rcx
    mov     %rdx, NodeEvent_index(%rcx)
    mov     NODE_STATE_SLOT(%r13), %rax     # its fee recipient: an entry past the state's epoch
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     (L + 16)(%rsp), %rdx
    PART    %rsi, %rcx, %rbx, Node_proposers
833: test   %rcx, %rcx
    jz      8335f
    cmp     %rdx, NodeProposer_validator_index(%rsi)
    jne     8331f
    cmp     %rax, NodeProposer_until_epoch(%rsi)
    ja      834f
8331: add   $NodeProposer__mem, %rsi
    dec     %rcx
    jmp     833b
834: mov    %rsi, (L + 24)(%rsp)
    jmp     8336f
8335: testq $1, NodeAction_target(%r12)    # forced (1): a fee recipient of zero bytes, at L+40
    jz      836f
    xorps   %xmm0, %xmm0
    movdqu  %xmm0, (L + 40)(%rsp)
    movq    $0, (L + 56)(%rsp)
    lea     (L + 24)(%rsp), %rax
    mov     %rax, (L + 24)(%rsp)
8336:
    lea     Node_payload_root(%rbx), %rdi   # the ForkchoiceState: the parent hash, safe (justified), finalized
    call    node_store_find
    cmp     $-1, %rax
    je      839f
    lea     (L + 96)(%rsp), %rdi
    lea     BlockNode_block_hash(%rdx), %rsi
    COPY32  %rdi, %rsi
    lea     (Store_justified_checkpoint + 8)(%rbp), %rdi
    call    node_store_find
    cmp     $-1, %rax
    je      839f
    lea     (L + 128)(%rsp), %rdi
    lea     BlockNode_block_hash(%rdx), %rsi
    COPY32  %rdi, %rsi
    lea     (Store_finalized_checkpoint + 8)(%rbp), %rdi
    call    node_store_find
    cmp     $-1, %rax
    je      839f
    lea     (L + 160)(%rsp), %rdi
    lea     BlockNode_block_hash(%rdx), %rsi
    COPY32  %rdi, %rsi
    mov     (L + 96)(%rsp), %rax            # a parent of no payload: no call
    or      (L + 104)(%rsp), %rax
    or      (L + 112)(%rsp), %rax
    or      (L + 120)(%rsp), %rax
    jz      836f
    mov     (%r15), %rax                    # the attributes at the end of scratch
    mov     %rax, S10(%rsp)
    cmp     $(PAYLOAD_ATTRIBUTES_ROOM + 512), %rax
    jb      832b
    sub     $PAYLOAD_ATTRIBUTES_ROOM, %rax
    mov     %rax, (%r15)
    lea     (%r15,%rax), %r14
    mov     %r13, %rdi
    mov     (L + 24)(%rsp), %rsi
    add     $NodeProposer_fee_recipient, %rsi
    lea     Node_config(%rbx), %rdx
    mov     %r15, %rcx
    mov     %r14, %r8
    mov     S7(%rsp), %r10
    FORK_CALL_BELLATRIX get_payload_attributes
    test    %rax, %rax
    jz      831b
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      835f
    mov     S10(%rsp), %rcx
    mov     %rcx, (%r15)
838: mov    S8(%rsp), %rcx                  # a failed check: the result
    mov     %rax, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
836: mov    S8(%rsp), %rcx
    movq    $LANTERN_NO_PAYLOAD, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
837: mov    $LANTERN_INVALID_EVENT, %eax
    LEAVE 192
835: mov    S10(%rsp), %rcx                 # a status, with the scratch's size back
    mov     %rcx, (%r15)
    LEAVE 192
839: mov    S8(%rsp), %rcx
    movq    $LANTERN_INVALID_UNKNOWN_BLOCK, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
890: cmp    $NODE_WORK_PRODUCE_CHECK, %rax
    jne     8410f
    test    %r13, %r13                      # PRODUCE_CHECK: lantern_node_produce_check of the request in the entry's cursor
    jz      837b
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     NodeAction_target(%r12), %rax
    PART    %rsi, %rcx, %rbx, Node_api
    cmp     %rcx, %rax
    jae     837b
    imul    $NodeApi__mem, %rax, %rax
    lea     NodeApi_cursor(%rsi,%rax), %rsi
    mov     %r13, %rdi
    mov     %r15, %rdx
    mov     S8(%rsp), %rcx
    add     $NodeEvent_root, %rcx           # the proposer, then the health
    FORK_CALL node_produce_check
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8401f
    mov     S8(%rsp), %rcx
    mov     %rax, NodeEvent_result(%rcx)
    xor     %eax, %eax
8401: LEAVE 192
8410: cmp   $NODE_WORK_GET_PAYLOAD, %rax
    jne     8420f
    mov     NodeAction_target(%r12), %rax   # GET_PAYLOAD: engine_getPayload of the fork of the entry's slot
    PART    %rsi, %rcx, %rbx, Node_api
    cmp     %rcx, %rax
    jae     837b
    imul    $NodeApi__mem, %rax, %rax
    mov     NodeApi_slot(%rsi,%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, S7(%rsp)
    cmpq    $(NodeEvent_chunk + 24), S9(%rsp)
    jb      8419f
    mov     (%r15), %rax                    # at the end of scratch: the JSON (536), the token (280), the host (88)
    mov     %rax, S10(%rsp)
    cmp     $(904 + 512), %rax
    jb      8419f
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
    lea     Node_payload_id(%rbx), %rdi
    lea     NodeAction_arg(%r12), %rsi
    mov     %r13, %rdx
    mov     S7(%rsp), %r10
    FORK_CALL_BELLATRIX engine_get_payload
    test    %rax, %rax
    jnz     8418f
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
    jnz     8418f
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
    jnz     8418f
    mov     S10(%rsp), %rax
    mov     %rax, (%r15)
    jmp     8441f
8418: mov   S10(%rsp), %rcx                 # a status, with the scratch's size back
    mov     %rcx, (%r15)
    LEAVE 192
8419: mov   $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 192
8420: cmp   $NODE_WORK_PRODUCE_FOLD, %rax
    jne     8425f
    test    %r13, %r13                      # PRODUCE_FOLD: lantern_node_produce_fold of the pool entry in state_b, into the draft in place
    jz      837b
    cmpq    $0, (L + 72)(%rsp)
    je      837b
    test    %r14, %r14
    jz      837b
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    mov     (L + 72)(%rsp), %rsi
    mov     %r14, %rdx
    mov     NodeAction_arg(%r12), %rcx
    mov     %r15, %r8
    FORK_CALL node_produce_fold
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8449f
    mov     S8(%rsp), %rcx
    mov     %rax, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
8425: cmp   $NODE_WORK_PRODUCE_ETH1, %rax
    jne     8426f
    test    %r13, %r13                      # PRODUCE_ETH1: lantern_node_produce_eth1 into the draft, from the snapshot in state_b
    jz      837b
    test    %r14, %r14
    jz      837b
    cmpq    $0, (L + 72)(%rsp)
    je      837b
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    mov     %r14, %rsi
    mov     (L + 72)(%rsp), %rdx
    lea     Node_config(%rbx), %rcx
    mov     %r15, %r8
    FORK_CALL node_produce_eth1
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8449f
    mov     S8(%rsp), %rcx
    mov     %rax, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
8426: cmp   $NODE_WORK_ETH1_CHECK, %rax
    jne     8427f
    test    %r13, %r13                      # ETH1_CHECK: lantern_node_eth1_check, its two words at index and checkpoint
    jz      837b
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    lea     (L + 96)(%rsp), %rsi
    FORK_CALL node_eth1_check
    mov     S8(%rsp), %rcx
    mov     (L + 96)(%rsp), %rax
    mov     %rax, NodeEvent_index(%rcx)
    mov     (L + 104)(%rsp), %rax
    mov     %rax, NodeEvent_checkpoint(%rcx)
    xor     %eax, %eax
    LEAVE 192
8427: cmp   $NODE_WORK_ARCHIVE_LOAD, %rax
    jne     8428f
    test    %r13, %r13                      # ARCHIVE_LOAD: the state of a Db state record into state_a
    jz      837b
    test    %r14, %r14
    jz      837b
    mov     %r13, %rdi
    mov     (L + 72)(%rsp), %rsi
    mov     %r14, %rdx
    mov     %r15, %rcx
    mov     %rbx, %r8
    call    node_run_archive
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8449f
    mov     S8(%rsp), %rcx
    mov     %rax, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
8428: cmp   $NODE_WORK_CUSTODY, %rax
    jne     8430f
    test    %r13, %r13                      # CUSTODY: lantern_node_custody with the store's epoch, its count at NodeEvent_index
    jz      837b
    mov     %rbp, %rdi
    call    node_store_slot
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, (L + 96)(%rsp)
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    mov     %rbx, %rsi
    lea     (L + 96)(%rsp), %rdx
    lea     (L + 104)(%rsp), %rcx
    FORK_CALL node_custody
    mov     S8(%rsp), %rcx
    mov     (L + 104)(%rsp), %rax
    mov     %rax, NodeEvent_index(%rcx)
    xor     %eax, %eax
    LEAVE 192
8430: cmp   $NODE_WORK_PRODUCE_BLOCK, %rax
    jne     8445f
    test    %r13, %r13                      # PRODUCE_BLOCK: lantern_node_produce_block, as a ByteList at NodeEvent_chunk
    jz      837b
    test    %r14, %r14
    jz      837b
    cmpq    $(NodeEvent_chunk + 24), S9(%rsp)
    jb      8419b
    mov     S8(%rsp), %rcx
    mov     S9(%rsp), %rax
    sub     $NodeEvent_chunk, %rax
    mov     %rax, NodeEvent_chunk(%rcx)
    movq    $24, (NodeEvent_chunk + 8)(%rcx)
    movq    $0, (NodeEvent_chunk + 16)(%rcx)
    mov     NodeAction_target(%r12), %rax   # the request: the entry's cursor
    PART    %rsi, %rcx, %rbx, Node_api
    cmp     %rcx, %rax
    jae     837b
    imul    $NodeApi__mem, %rax, %rax
    lea     NodeApi_cursor(%rsi,%rax), %rax
    mov     %rax, (L + 96)(%rsp)            # ProduceParams at L+96: request, config, result, values
    lea     Node_config(%rbx), %rax
    mov     %rax, (L + 104)(%rsp)
    mov     (L + 72)(%rsp), %rax
    mov     %rax, (L + 112)(%rsp)
    mov     S8(%rsp), %rcx
    lea     NodeEvent_root(%rcx), %rax
    mov     %rax, (L + 120)(%rsp)
    lea     NodeEvent_index(%rcx), %rax
    mov     %rax, (L + 128)(%rsp)
    mov     (L + 80)(%rsp), %rax            # the bid: state_c; then where blinded goes
    mov     %rax, (L + 136)(%rsp)
    lea     NodeEvent_checkpoint(%rcx), %rax
    mov     %rax, (L + 144)(%rsp)
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    mov     %r14, %rsi
    lea     (L + 96)(%rsp), %rdx
    mov     %r15, %rcx
    mov     S8(%rsp), %r8
    add     $NodeEvent_chunk, %r8
    FORK_CALL node_produce_block
8440: cmp   $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8449f
    test    %rax, %rax
    jz      8441f
    mov     S8(%rsp), %rcx                  # a failed check: the result, no bytes
    mov     %rax, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
8441: mov   S8(%rsp), %r8                   # the sizes of the list and the event
    lea     NodeEvent_chunk(%r8), %r8
    mov     16(%r8), %rax
    add     $(24 + 7), %rax
    and     $-8, %rax
    mov     %rax, (%r8)
    add     $NodeEvent_chunk, %rax
    mov     S8(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
8449: LEAVE 192
8445: cmp   $NODE_WORK_PRODUCE_BID, %rax
    jne     8450f
    test    %r13, %r13                      # PRODUCE_BID: the bid's JSON of the answer, lantern_node_produce_bid as a ByteList at NodeEvent_chunk
    jz      837b
    test    %r14, %r14
    jz      837b
    cmpq    $(NodeEvent_chunk + 24), S9(%rsp)
    jb      8419b
    mov     S8(%rsp), %rcx
    mov     S9(%rsp), %rax
    sub     $NodeEvent_chunk, %rax
    mov     %rax, NodeEvent_chunk(%rcx)
    movq    $24, (NodeEvent_chunk + 8)(%rcx)
    movq    $0, (NodeEvent_chunk + 16)(%rcx)
    mov     NodeAction_target(%r12), %rax   # ProduceParams at L+96: the entry's cursor, the config
    PART    %rsi, %rcx, %rbx, Node_api
    cmp     %rcx, %rax
    jae     837b
    imul    $NodeApi__mem, %rax, %rax
    lea     NodeApi_cursor(%rsi,%rax), %rax
    mov     %rax, (L + 96)(%rsp)
    lea     Node_config(%rbx), %rax
    mov     %rax, (L + 104)(%rsp)
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, (L + 152)(%rsp)
    mov     (%r15), %rax                    # the scratch's size, back after the call
    mov     %rax, (L + 160)(%rsp)
    mov     %r14, %rdi
    mov     %r15, %rsi
    mov     (L + 152)(%rsp), %rdx
    call    node_bid_data
    test    %rax, %rax
    jnz     8446f
    lea     (L + 168)(%rsp), %rcx           # a ByteList view of the data's text
    mov     %rsi, %rax
    sub     %rcx, %rax
    mov     %rax, 8(%rcx)
    add     %rdx, %rax
    mov     %rax, (%rcx)
    mov     %rdx, 16(%rcx)
    mov     (L + 152)(%rsp), %r10
    mov     %r13, %rdi
    lea     (L + 168)(%rsp), %rsi
    lea     (L + 96)(%rsp), %rdx
    mov     %r15, %rcx
    mov     S8(%rsp), %r8
    add     $NodeEvent_chunk, %r8
    FORK_CALL node_produce_bid
8446: mov   (L + 160)(%rsp), %rcx
    mov     %rcx, (%r15)
    jmp     8440b
8450: cmp   $NODE_WORK_PUBLISH_DECODE, %rax
    jne     8460f
    test    %r14, %r14                      # PUBLISH_DECODE: lantern_node_publish_decode, the block as a ByteList at NodeEvent_chunk
    jz      837b
    cmpq    $(NodeEvent_chunk + 24), S9(%rsp)
    jb      8419b
    mov     S8(%rsp), %rcx
    mov     S9(%rsp), %rax
    sub     $NodeEvent_chunk, %rax
    mov     %rax, NodeEvent_chunk(%rcx)
    movq    $24, (NodeEvent_chunk + 8)(%rcx)
    movq    $0, (NodeEvent_chunk + 16)(%rcx)
    mov     NodeAction_arg(%r12), %rax
    movzbl  %al, %r10d
    mov     %rax, %rsi
    shr     $8, %esi
    and     $1, %esi
    xor     $1, %esi                        # JSON without the SSZ bit, + 2 for a blinded block
    shr     $9, %eax
    and     $1, %eax
    lea     (%rsi,%rax,2), %rsi
    mov     %r14, %rdi
    mov     %r15, %rdx
    add     $NodeEvent_chunk, %rcx
    lea     (L + 96)(%rsp), %r8             # facts: the slot, the blob count, 0, a blinded block's root
    FORK_CALL node_publish_decode
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8449b
    test    %rax, %rax
    jnz     8458f
    mov     S8(%rsp), %rcx
    mov     (L + 96)(%rsp), %rax
    mov     %rax, NodeEvent_index(%rcx)
    mov     (L + 104)(%rsp), %rax
    mov     %rax, NodeEvent_checkpoint(%rcx)
    testq   $512, NodeAction_arg(%r12)      # its root: a blinded block's from the decode
    jz      8457f
    lea     NodeEvent_root(%rcx), %rdi
    lea     (L + 120)(%rsp), %rsi
    COPY32  %rdi, %rsi
    jmp     8441b
8457: movzbl NodeAction_arg(%r12), %r10d
    lea     NodeEvent_chunk(%rcx), %rdi
    mov     %r15, %rsi
    lea     NodeEvent_root(%rcx), %rdx
    lea     (L + 112)(%rsp), %rcx
    lea     (L + 120)(%rsp), %r8
    FORK_CALL node_block_root
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8449b
    test    %rax, %rax
    jnz     8458f
    mov     (L + 112)(%rsp), %rax
    test    %rax, %rax
    jz      8441b
8458: mov   S8(%rsp), %rcx                  # a failed check: the result, no bytes
    mov     %rax, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 192
8460: cmp   $NODE_WORK_PUBLISH_CHECK, %rax
    jne     8470f
    test    %r13, %r13                      # PUBLISH_CHECK: lantern_node_publish_check, then the block's bytes at NodeEvent_chunk
    jz      837b
    test    %r14, %r14
    jz      837b
    mov     (L + 80)(%rsp), %rcx
    test    %rcx, %rcx
    jz      837b
    mov     16(%r14), %rax
    testq   $256, NodeAction_arg(%r12)      # a blinded block: room for its JSON and a cursor
    jz      8461f
    shl     $2, %rax
    add     $(4096 + JSON_CURSOR_SIZE), %rax
8461: add   $(NodeEvent_chunk + 24 + 7), %rax
    cmp     %rax, S9(%rsp)
    jb      8419b
    mov     (L + 64)(%rsp), %rax            # a NodeGossip at L+96: seen, store, time_ms, topic, subnet,
    mov     %rax, (L + 96)(%rsp)            # head, proposer, justified, settings, config
    mov     %rbp, (L + 104)(%rsp)
    mov     Node_time_ms(%rbx), %rax
    mov     %rax, (L + 112)(%rsp)
    movq    $0, (L + 120)(%rsp)
    movq    $0, (L + 128)(%rsp)
    mov     %rcx, (L + 136)(%rsp)
    mov     %r13, (L + 144)(%rsp)
    movq    $0, (L + 152)(%rsp)
    mov     (L + 88)(%rsp), %rax
    mov     %rax, (L + 160)(%rsp)
    lea     Node_config(%rbx), %rax
    mov     %rax, (L + 168)(%rsp)
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    lea     (L + 96)(%rsp), %rdi
    mov     %r14, %rsi
    mov     (L + 72)(%rsp), %rdx
    mov     NodeAction_arg(%r12), %rcx
    mov     %r15, %r8
    FORK_CALL node_publish_check
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8449b
    test    %rax, %rax
    jnz     8458b
    testq   $256, NodeAction_arg(%r12)
    jnz     8462f
    mov     S8(%rsp), %rcx                  # the block's bytes
    mov     S9(%rsp), %rax
    sub     $NodeEvent_chunk, %rax
    mov     %rax, NodeEvent_chunk(%rcx)
    movq    $24, (NodeEvent_chunk + 8)(%rcx)
    mov     16(%r14), %rdx
    mov     %rdx, (NodeEvent_chunk + 16)(%rcx)
    lea     (NodeEvent_chunk + 24)(%rcx), %rdi
    mov     8(%r14), %rsi
    add     %r14, %rsi
    call    lantern_copy
    jmp     8441b
8462: mov   S9(%rsp), %rax                  # a blinded block: its JSON, the cursor at the end of the event
    sub     $JSON_CURSOR_SIZE, %rax
    and     $-8, %rax
    add     S8(%rsp), %rax
    mov     %rax, (L + 176)(%rsp)
    mov     %rax, %rdi
    mov     $JSON_CURSOR_SIZE, %esi
    call    lantern_zero
    mov     S8(%rsp), %rcx
    mov     (L + 176)(%rsp), %rax
    lea     NodeEvent_chunk(%rcx), %rdx
    sub     %rdx, %rax
    mov     %rax, NodeEvent_chunk(%rcx)
    movq    $24, (NodeEvent_chunk + 8)(%rcx)
    movq    $0, (NodeEvent_chunk + 16)(%rcx)
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     $NODE_JSON_BLINDED_BLOCK, %edi
    mov     %r14, %rsi
    mov     (L + 176)(%rsp), %rdx
    mov     S8(%rsp), %rcx
    add     $NodeEvent_chunk, %rcx
    FORK_CALL node_json
    test    %rax, %rax
    jz      8441b
    mov     $LANTERN_INVALID_ENCODING, %eax
    jmp     8458b
8470: cmp   $NODE_WORK_PUBLISH_SIDECARS, %rax
    jne     8480f
    test    %r14, %r14                      # PUBLISH_SIDECARS: lantern_node_publish_sidecars of the fork arg & 255, into state_b
    jz      837b
    mov     (L + 72)(%rsp), %rcx
    test    %rcx, %rcx
    jz      837b
    mov     NodeAction_arg(%r12), %rax
    movzbl  %al, %r10d
    shr     $8, %eax
    and     $1, %eax
    xor     $1, %eax
    mov     %rax, %rsi                      # JSON without the SSZ bit
    mov     %r14, %rdi
    mov     %r15, %rdx
    cmp     $FORK_DENEB, %r10
    jb      837b
    cmp     $FORK_ELECTRA, %r10
    jae     8471f
    CALL_GLOBAL lantern_deneb_node_publish_sidecars
    jmp     8473f
8471: cmp   $FORK_FULU, %r10
    jae     8472f
    CALL_GLOBAL lantern_electra_node_publish_sidecars
    jmp     8473f
8472: CALL_GLOBAL lantern_fulu_node_publish_sidecars
8473: cmp   $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8449b
    test    %rax, %rax
    jnz     8458b
    LEAVE 192
8480: cmp   $NODE_WORK_PUBLISH_SIDECAR, %rax
    jne     8490f
    mov     (L + 72)(%rsp), %rcx            # PUBLISH_SIDECAR: the sidecar arg of state_b, as a ByteList at NodeEvent_chunk
    test    %rcx, %rcx
    jz      837b
    mov     NodeAction_arg(%r12), %rdx
    mov     8(%rcx), %rsi
    add     %rcx, %rsi                      # the first sidecar's ByteList
    mov     16(%rcx), %rdi
    add     %rsi, %rdi                      # their end
8481: cmp   %rdi, %rsi
    jae     8483f
    test    %rdx, %rdx
    jz      8482f
    add     (%rsi), %rsi
    dec     %rdx
    jmp     8481b
8482: mov   16(%rsi), %r8                   # its length
    lea     (NodeEvent_chunk + 24 + 7)(%r8), %rax
    cmp     S9(%rsp), %rax
    ja      8419b
    mov     %rsi, (L + 96)(%rsp)
    mov     NodeAction_target(%r12), %rax   # its block's root and slot: the entry's
    PART    %rcx, %rdx, %rbx, Node_api
    cmp     %rdx, %rax
    jae     837b
    imul    $NodeApi__mem, %rax, %rax
    add     %rax, %rcx
    mov     S8(%rsp), %rdx
    lea     NodeEvent_root(%rdx), %rdi
    lea     NodeApi_root(%rcx), %rax
    COPY32  %rdi, %rax
    mov     NodeApi_slot(%rcx), %rax
    mov     %rax, NodeEvent_checkpoint(%rdx)
    mov     (L + 96)(%rsp), %rsi
    mov     8(%rsi), %rax                   # its index: the u64 at byte 0 of its bytes
    mov     (%rsi,%rax), %rax
    mov     %rax, NodeEvent_index(%rdx)
    mov     S9(%rsp), %rax                  # its bytes as a ByteList
    sub     $NodeEvent_chunk, %rax
    mov     %rax, NodeEvent_chunk(%rdx)
    movq    $24, (NodeEvent_chunk + 8)(%rdx)
    mov     %r8, (NodeEvent_chunk + 16)(%rdx)
    lea     (NodeEvent_chunk + 24)(%rdx), %rdi
    mov     8(%rsi), %rax
    add     %rax, %rsi
    mov     %r8, %rdx
    call    lantern_copy
    jmp     8441b
8483: mov   $LANTERN_INVALID_EVENT, %eax    # past the last
    jmp     8458b
8490:
89: cmp     $NODE_WORK_SLOTS, %rax
    jne     90f
    mov     NODE_STATE_SLOT(%r13), %rdi     # SLOTS: process_slots of the fork of the state's slot, to arg
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    lea     NodeAction_arg(%r12), %rsi
    lea     Node_config(%rbx), %rdx
    mov     %r15, %rcx
    mov     S8(%rsp), %r8
    add     $NodeEvent_result, %r8
    FORK_CALL process_slots
    LEAVE 192
90: cmp     $NODE_WORK_UPGRADE, %rax
    jne     97f
    mov     NodeAction_arg(%r12), %rax      # UPGRADE: node_upgrade of the fork arg, of a state at its first slot
    cmp     $FORK_ALTAIR, %rax
    jb      19b
    cmp     $FORK_FULU, %rax
    ja      19b
    shl     $4, %rax
    mov     Node_config(%rbx,%rax), %rax
    mov     $SLOTS_PER_EPOCH, %ecx
    mul     %rcx
    jc      19b
    cmp     NODE_STATE_SLOT(%r13), %rax
    jne     19b
    mov     %r13, %rdi
    ADDRESS %rsi, node_upgrade_room
    lea     Node_config(%rbx), %rdx
    mov     %r15, %rcx
    mov     (L + 72)(%rsp), %r8
    mov     NodeAction_arg(%r12), %r10
    FORK_CALL node_upgrade
    LEAVE 192
97: cmp     $NODE_WORK_REPLAY, %rax
    jne     971f
    cmpq    $(100 + 84), 16(%r14)           # REPLAY: node_replay of the fork of the block's slot, of a state of that fork
    jb      18b
    mov     8(%r14), %rax
    add     %r14, %rax
    mov     100(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, (L + 48)(%rsp)
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     (L + 48)(%rsp), %rax
    jne     19b
    mov     (L + 48)(%rsp), %r10
    mov     %r14, %rdi
    mov     %r13, %rsi
    lea     Node_config(%rbx), %rdx
    mov     %r15, %rcx
    mov     S8(%rsp), %r8
    add     $NodeEvent_result, %r8
    FORK_CALL node_replay
    LEAVE 192
971: cmp    $NODE_WORK_BLOCK_ATTESTATION, %rax
    je      975f
    cmp     $NODE_WORK_GOSSIP_VOTE, %rax
    je      975f
    cmp     $NODE_WORK_BLOCK_SLASHING, %rax
    jne     974f
975: mov    %rax, %rdi                      # BLOCK_ATTESTATION, BLOCK_SLASHING
    mov     S8(%rsp), %rsi
    call    node_run_vote
    LEAVE 192
974: cmp    $NODE_WORK_BACKFILL, %rax
    jne     975f
    cmpq    $(100 + 84), 16(%r14)           # BACKFILL: its root, then the signature with state_a
    jb      18b
    test    %r13, %r13
    jz      19b
    mov     %r14, %rdi
    mov     %r13, %rsi
    mov     %r15, %rdx
    mov     S8(%rsp), %rcx
    call    node_run_backfill
    LEAVE 192
975: cmp    $NODE_WORK_API_ENCODE, %rax
    jne     976f
    mov     %rbx, %rdi                      # API_ENCODE: the response of an answer; the seen in rax
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     %r14, %r8
    mov     %r15, %r9
    mov     S8(%rsp), %r10
    mov     S9(%rsp), %r11
    lea     (L + 64)(%rsp), %rax            # the seen, state_b and state_c
    call    node_api_run
    LEAVE 192
976: cmp    $NODE_WORK_API_CHUNK, %rax
    jne     977f
    mov     %rbx, %rdi                      # API_CHUNK: the next chunk of a stream
    mov     %r12, %rsi
    mov     %r14, %rdx
    mov     %r15, %rcx
    mov     S8(%rsp), %r8
    mov     S9(%rsp), %r9
    mov     %r13, %r10
    call    node_api_chunk_run
    LEAVE 192
977: cmp    $NODE_WORK_API_EVENT, %rax
    jne     978f
    mov     %rbx, %rdi                      # API_EVENT: the text of an event
    mov     %r12, %rsi
    mov     %r13, %rdx
    mov     %r14, %rcx
    mov     %r15, %r8
    mov     S8(%rsp), %r9
    mov     S9(%rsp), %r10
    mov     (L + 80)(%rsp), %r11
    call    node_api_event_run
    LEAVE 192
978: cmp    $NODE_WORK_API_SUBMIT, %rax
    jne     979f
    mov     %rbx, %rdi                      # API_SUBMIT: the operations of a body, checked
    mov     %rbp, %rsi
    mov     (L + 64)(%rsp), %rdx
    mov     %r12, %rcx
    mov     %r13, %r8
    mov     %r14, %r9
    mov     %r15, %r10
    mov     S8(%rsp), %r11
    mov     S9(%rsp), %rax
    call    node_api_submit_run
    LEAVE 192
979: cmp    $NODE_WORK_POOL_CHECK, %rax
    jne     9780f
    test    %r13, %r13                      # POOL_CHECK: the gossip validation of the bytes, with an empty Seen
    jz      8f
    test    %r14, %r14
    jz      8f
    mov     NodeAction_arg(%r12), %rax
    cmp     $GOSSIP_VOLUNTARY_EXIT, %rax
    je      9785f
    cmp     $GOSSIP_PROPOSER_SLASHING, %rax
    je      9785f
    cmp     $GOSSIP_ATTESTER_SLASHING, %rax
    je      9785f
    cmp     $GOSSIP_BLS_TO_EXECUTION_CHANGE, %rax
    jne     8f
9785: mov   16(%r14), %rax                  # its SeenRoom: a key for each 8 bytes, and 1
    shr     $3, %rax
    inc     %rax
    mov     %rax, (L + 16)(%rsp)
    movq    $0, (L + 24)(%rsp)
    movq    $0, (L + 32)(%rsp)
    movq    $0, (L + 40)(%rsp)
    lea     (L + 16)(%rsp), %rdi
    lea     L(%rsp), %rsi
    call    lantern_seen_size
    test    %rax, %rax
    jnz     9781f
    mov     (%r15), %rax                    # the Seen at the end of scratch, with LANTERN_SCRATCH_FIXED before it
    mov     %rax, (L + 8)(%rsp)
    sub     L(%rsp), %rax
    jb      9781f
    cmp     $(LANTERN_SCRATCH_FIXED + 8), %rax
    jb      9781f
    and     $-8, %rax
    mov     %rax, (%r15)
    lea     (%r15,%rax), %rcx
    mov     %rcx, S10(%rsp)
    mov     L(%rsp), %rdx
    mov     %rdx, (%rcx)
    lea     (L + 16)(%rsp), %rdi
    mov     %rcx, %rsi
    call    lantern_seen_init
    test    %rax, %rax
    jnz     9782f
    mov     %rbp, %rdi
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, (L + 48)(%rsp)
    mov     NODE_STATE_SLOT(%r13), %rdi     # a head state of another fork: IGNORE, as for gossip
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     (L + 48)(%rsp), %rax
    jne     9782f
    mov     S10(%rsp), %rax
    mov     %rax, (L + 96 + NodeGossip_seen)(%rsp)
    mov     %rbp, (L + 96 + NodeGossip_store)(%rsp)
    mov     Node_time_ms(%rbx), %rax
    mov     %rax, (L + 96 + NodeGossip_time_ms)(%rsp)
    mov     NodeAction_arg(%r12), %rax
    mov     %rax, (L + 96 + NodeGossip_topic)(%rsp)
    movq    $0, (L + 96 + NodeGossip_subnet)(%rsp)
    mov     %r13, (L + 96 + NodeGossip_head)(%rsp)
    movq    $0, (L + 96 + NodeGossip_proposer)(%rsp)
    movq    $0, (L + 96 + NodeGossip_justified)(%rsp)
    movq    $0, (L + 96 + NodeGossip_settings)(%rsp)
    lea     Node_config(%rbx), %rax
    mov     %rax, (L + 96 + NodeGossip_config)(%rsp)
    mov     (L + 48)(%rsp), %r10
    lea     (L + 96)(%rsp), %rdi
    mov     %r14, %rsi
    mov     %r15, %rdx
    mov     S8(%rsp), %rcx
    lea     NodeEvent_index(%rcx), %r9
    lea     NodeEvent_root(%rcx), %r8
    lea     NodeEvent_result(%rcx), %rcx
    FORK_CALL node_gossip
    mov     (L + 8)(%rsp), %rcx             # scratch whole again; a short one: IGNORE
    mov     %rcx, (%r15)
    test    %rax, %rax
    jz      9783f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    jne     9784f
    jmp     9781f
9782: mov   (L + 8)(%rsp), %rcx
    mov     %rcx, (%r15)
9781: mov   S8(%rsp), %rcx
    movq    $LANTERN_GOSSIP_IGNORE, NodeEvent_result(%rcx)
9783: xor   %eax, %eax
9784: LEAVE 192
9780: cmp   $NODE_WORK_API_LOOKUP, %rax
    jne     8f
    mov     %rbx, %rdi                      # API_LOOKUP: the slot of a state root
    mov     %r12, %rsi
    mov     %r13, %rdx
    mov     %r15, %rcx
    mov     S8(%rsp), %r8
    call    node_api_lookup_run
    LEAVE 192
8:  mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 192
7:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 192
END_FUNCTION lantern_node_run

/* The counts of the votes of the block in data rdi, at NodeEvent_index and NodeEvent_root of the event rsi. Locals: rsp+0 data, rsp+8 event. */
LOCAL_FUNCTION node_vote_counts
    FRAME 16
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    mov     $1, %esi
    mov     $-1, %rdx
    call    node_body_item
    xor     %ecx, %ecx
    cmp     $-1, %rax
    cmove   %rcx, %rax
    mov     8(%rsp), %rsi
    mov     %rax, NodeEvent_index(%rsi)
    mov     0(%rsp), %rdi
    xor     %esi, %esi
    mov     $-1, %rdx
    call    node_body_item
    xor     %ecx, %ecx
    cmp     $-1, %rax
    cmove   %rcx, %rax
    mov     8(%rsp), %rsi
    mov     %rax, NodeEvent_root(%rsi)
    UNFRAME 16
END_FUNCTION node_vote_counts

/*
 * The BLOCK_ATTESTATION or BLOCK_SLASHING work rdi of lantern_node_run, with the event rsi
 * (node.md): the item at index arg of the block's body, as a ByteList at the end of scratch, then
 * node_attestation with is_from_block 1 of the fork of its slot, or node_attester_slashing of the
 * fork of the store's slot. The run's rbx node, rbp store, r12 work, r13 state_a, r14 data, r15
 * scratch. S7 the seventh argument, S8 the event, S9 the kind, S10 the scratch size. Locals: L
 * is_from_block, L+8 the ByteList, L+16 a fork.
 */
LOCAL_FUNCTION node_run_vote
    ENTER 32
    mov     %rdi, S9(%rsp)
    mov     %rsi, S8(%rsp)
    mov     (%r15), %rax
    mov     %rax, S10(%rsp)
    cmp     $NODE_WORK_GOSSIP_VOTE, %rdi
    jne     1f
    mov     %r14, %rdi                      # GOSSIP_VOTE: the aggregate
    call    node_aggregate
    test    %rax, %rax
    jnz     7f
    jmp     2f
1:  xor     %esi, %esi
    cmp     $NODE_WORK_BLOCK_ATTESTATION, %rdi
    sete    %sil
    mov     %r14, %rdi
    mov     NodeAction_arg(%r12), %rdx
    call    node_body_item
2:  test    %rcx, %rcx
    jz      7f
    lea     (24 + 7)(%rcx), %rax            # the ByteList at the end of scratch
    and     $-8, %rax
    mov     S10(%rsp), %rdi
    sub     %rax, %rdi
    jb      8f
    mov     %rdi, (%r15)
    add     %r15, %rdi
    mov     %rdi, (L + 8)(%rsp)
    mov     %rax, (%rdi)
    movq    $24, 8(%rdi)
    mov     %rcx, 16(%rdi)
    mov     %rdx, %rsi
    add     $24, %rdi
    mov     %rcx, %rdx
    call    lantern_copy
    cmpq    $NODE_WORK_BLOCK_SLASHING, S9(%rsp)
    je      3f
    mov     (L + 8)(%rsp), %rax             # ATTESTATION: the fork of its slot
    cmpq    $(4 + 128 + 96), 16(%rax)
    jb      61f
    mov     (24 + 4)(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    xor     %eax, %eax                      # is_from_block: 1 for a block's, 0 for an aggregate's
    cmpq    $NODE_WORK_BLOCK_ATTESTATION, S9(%rsp)
    sete    %al
    mov     %rax, L(%rsp)
    mov     %rbp, %rdi
    mov     (L + 8)(%rsp), %rsi
    lea     L(%rsp), %rdx
    mov     %r13, %rcx
    mov     %r15, %r8
    mov     S8(%rsp), %r9
    lea     NodeEvent_checkpoint(%r9), %rax
    mov     %rax, S7(%rsp)                  # target, the seventh argument
    add     $NodeEvent_result, %r9
    FORK_CALL node_attestation
    jmp     9f
3:  mov     %rbp, %rdi                      # SLASHING: the fork of the store's slot, a state of it
    call    node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, (L + 16)(%rsp)
    test    %r13, %r13
    jz      4f
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    cmp     (L + 16)(%rsp), %rax
    jne     62f
4:  mov     (L + 16)(%rsp), %r10
    mov     %rbp, %rdi
    mov     (L + 8)(%rsp), %rsi
    mov     %r13, %rdx
    mov     %r15, %rcx
    mov     S8(%rsp), %r8
    add     $NodeEvent_result, %r8
    FORK_CALL node_attester_slashing
    jmp     9f
61: mov     S8(%rsp), %rcx
    movq    $LANTERN_INVALID_ENCODING, NodeEvent_result(%rcx)
    xor     %eax, %eax
    jmp     9f
62: mov     S8(%rsp), %rcx
    movq    $LANTERN_GOSSIP_IGNORE, NodeEvent_result(%rcx)
    xor     %eax, %eax
    jmp     9f
7:  mov     S8(%rsp), %rcx                  # no such item
    movq    $LANTERN_INVALID_ENCODING, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 32
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
9:  mov     S10(%rsp), %rcx
    mov     %rcx, (%r15)
    LEAVE 32
END_FUNCTION node_run_vote

/*
 * The BACKFILL work (node.md): node_block_root of the fork of the block's slot of data rdi, its
 * root at NodeEvent_root of the event rcx; then, for LANTERN_VALID, node_backfill of the fork of
 * the slot of the state rsi, with scratch rdx. r12 data, r13 state, r14 scratch, r15 event. Apart
 * from lantern_node_run, as FORK_CALL takes the labels 81 to 89.
 */
LOCAL_FUNCTION node_run_backfill
    ENTER 0
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     %rdx, %r14
    mov     %rcx, %r15
    mov     8(%r12), %rax
    add     %r12, %rax
    mov     100(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r12, %rdi
    mov     %r14, %rsi
    lea     NodeEvent_root(%r15), %rdx
    lea     NodeEvent_result(%r15), %rcx
    lea     NodeEvent_index(%r15), %r8
    FORK_CALL node_block_root
    test    %rax, %rax
    jnz     1f
    cmpq    $0, NodeEvent_result(%r15)
    jne     1f
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r12, %rdi
    mov     %r13, %rsi
    lea     Node_config(%rbx), %rdx
    lea     NodeEvent_root(%r15), %rcx
    mov     %r14, %r8
    lea     NodeEvent_result(%r15), %r9
    FORK_CALL node_backfill
1:  LEAVE 0
END_FUNCTION node_run_backfill
