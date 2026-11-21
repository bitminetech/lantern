# The light client data of the node, x86-64: in the common object. Requirements: docs/reference/node.md,
# beacon-api.md and light-client.md.

# L2: (route, connection, flags) -> rax: a light client read of NODE_EV_API (node.md): a
# NODE_WORK_API_ENCODE with the light client store as state_c; 0. The node rbx, the actions r15.
# r12 the route, r13 the connection, r14 the answer flags, rbp the operation; S7 the bytes' id.
# Locals: L a ByteList of the bytes put.
LOCAL_FUNCTION node_api_lc
    ENTER 64
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     %rdx, %r14
    cmpq    $API_TYPE_SSZ, ApiRoute_response(%r12)
    jne     1f
    or      $API_ANSWER_SSZ, %r14
1:  mov     ApiRoute_op(%r12), %rbp
    movq    $0, S7(%rsp)
    cmp     $API_OP_GET_LIGHT_CLIENT_BOOTSTRAP, %rbp
    jne     2f
    lea     L(%rsp), %rax                   # getLightClientBootstrap: the root's 32 bytes
    movq    $56, (%rax)
    movq    $24, 8(%rax)
    movq    $32, 16(%rax)
    lea     24(%rax), %rdi
    lea     ApiRoute_id_root(%r12), %rsi
    COPY32  %rdi, %rsi
    jmp     3f
2:  cmp     $API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE, %rbp
    jne     4f
    mov     ApiRoute_start_period(%r12), %rax   # the periods: start, and past the last
    mov     ApiRoute_count(%r12), %rcx
    mov     $MAX_REQUEST_LIGHT_CLIENT_UPDATES, %edx
    cmp     %rdx, %rcx
    cmova   %rdx, %rcx
    add     %rax, %rcx
    jnc     21f
    mov     $-1, %rcx
21: lea     L(%rsp), %rdx
    movq    $40, (%rdx)
    movq    $24, 8(%rdx)
    movq    $16, 16(%rdx)
    mov     %rax, 24(%rdx)
    mov     %rcx, 32(%rdx)
3:  lea     L(%rsp), %rdi
    call    node_put
    mov     %rax, S7(%rsp)
4:  mov     $NODE_WORK_API_ENCODE, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     S7(%rsp), %rcx
    mov     %r13, %r8
    mov     %r14, %r9
    shl     $8, %r9
    or      %rbp, %r9
    call    node_work
    movq    $NODE_LC_ID, NodeAction_state_c(%rax)
    xor     %eax, %eax
    LEAVE 64
END_FUNCTION node_api_lc

# L2: (lc, work, data, scratch, view) -> status, the node rbx: the light client read of a
# NODE_WORK_API_ENCODE (node.md) into the view: for getLightClientUpdatesByRange its store, periods,
# node, JSON room and cursor, which its body reads; else the object's SSZ bytes (ApiView_lc_bytes),
# its fork, and as JSON its JSON (ApiView_lc_json). With none, ApiView_status 404; a fault of the
# JSON, 500. LANTERN_INVALID_EVENT without the store or the work's bytes; LANTERN_BUFFER_TOO_SMALL
# with too little scratch. rbp lc, r12 work, r13 data, r14 scratch, r15 view; S7 the kind, S8 the
# object, S9 the JSON, S10 the cursor. Locals: L the fork, L + 8 1 for SSZ, L + 16 the node.
LOCAL_FUNCTION node_api_lc_read
    ENTER 32
    mov     %rbx, (L + 16)(%rsp)
    mov     %rdi, %rbp
    mov     %rsi, %r12
    mov     %rdx, %r13
    mov     %rcx, %r14
    mov     %r8, %r15
    test    %rbp, %rbp
    jz      97f
    mov     NodeAction_arg(%r12), %rax
    xor     %ecx, %ecx
    testq   $(API_ANSWER_SSZ << 8), %rax
    setnz   %cl
    mov     %rcx, (L + 8)(%rsp)
    movzbl  %al, %eax
    movq    $LC_OBJECT_FINALITY_UPDATE, S7(%rsp)
    cmp     $API_OP_GET_LIGHT_CLIENT_FINALITY_UPDATE, %eax
    je      2f
    movq    $LC_OBJECT_OPTIMISTIC_UPDATE, S7(%rsp)
    cmp     $API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE, %eax
    je      2f
    movq    $LC_OBJECT_UPDATE, S7(%rsp)
    mov     $16, %ecx
    cmp     $API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE, %eax
    je      1f
    movq    $LC_OBJECT_BOOTSTRAP, S7(%rsp)
    mov     $32, %ecx
1:  test    %r13, %r13                      # the root, or the two periods
    jz      97f
    cmp     %rcx, 16(%r13)
    jne     97f
2:  mov     (%r14), %rax                    # the object at the end of scratch
    sub     $(24 + LC_UPDATE_ROOM), %rax
    jb      98f
    mov     %rax, (%r14)
    add     %r14, %rax
    movq    $(24 + LC_UPDATE_ROOM), (%rax)
    mov     %rax, S8(%rsp)
    mov     %rax, ApiView_lc_bytes(%r15)
    movq    $0, ApiView_lc_json(%r15)
    mov     (%r14), %rax                    # its JSON's room, and a cursor
    sub     $(24 + 4 * LC_UPDATE_ROOM + 4096 + JSON_CURSOR_SIZE), %rax
    jb      98f
    mov     %rax, (%r14)
    add     %r14, %rax
    movq    $(24 + 4 * LC_UPDATE_ROOM + 4096), (%rax)
    movq    $24, 8(%rax)
    movq    $0, 16(%rax)
    mov     %rax, S9(%rsp)
    add     $(24 + 4 * LC_UPDATE_ROOM + 4096), %rax
    mov     %rax, S10(%rsp)
    cmpq    $LC_OBJECT_UPDATE, S7(%rsp)
    jne     3f
    mov     %rbp, ApiView_lc_store(%r15)    # getLightClientUpdatesByRange: its body reads them
    mov     S10(%rsp), %rax
    mov     %rax, ApiView_lc_cursor(%r15)
    mov     S9(%rsp), %rax
    mov     %rax, ApiView_lc_json(%r15)
    mov     (L + 8)(%rsp), %rax
    mov     %rax, ApiView_lc_ssz(%r15)
    mov     8(%r13), %rax
    add     %r13, %rax
    mov     (%rax), %rcx
    mov     %rcx, ApiView_lc_start(%r15)
    mov     8(%rax), %rcx
    mov     %rcx, ApiView_lc_end(%r15)
    mov     (L + 16)(%rsp), %rcx
    mov     %rcx, ApiView_node(%r15)
    xor     %eax, %eax
    LEAVE 32
3:  mov     %rbp, %rdi
    mov     S7(%rsp), %rsi
    xor     %edx, %edx
    test    %rsi, %rsi
    jnz     31f
    mov     8(%r13), %rdx                   # the bootstrap: of the root
    add     %r13, %rdx
31: mov     S8(%rsp), %rcx
    lea     L(%rsp), %r8
    call    lantern_lc_read
    cmp     $LANTERN_NO_STATE_ANSWER, %rax
    je      80f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      98f
    test    %rax, %rax
    jnz     81f
    mov     L(%rsp), %rax
    mov     %rax, ApiView_fork(%r15)
    cmpq    $0, (L + 8)(%rsp)
    jne     9f
    mov     S10(%rsp), %rdi
    mov     $JSON_CURSOR_SIZE, %esi
    call    lantern_zero
    mov     $NODE_JSON_LC_BOOTSTRAP, %edi   # the JSON of the kind
    mov     $NODE_JSON_LC_FINALITY_UPDATE, %eax
    cmpq    $LC_OBJECT_FINALITY_UPDATE, S7(%rsp)
    cmove   %rax, %rdi
    mov     $NODE_JSON_LC_OPTIMISTIC_UPDATE, %eax
    cmpq    $LC_OBJECT_OPTIMISTIC_UPDATE, S7(%rsp)
    cmove   %rax, %rdi
    mov     S8(%rsp), %rsi
    mov     S10(%rsp), %rdx
    mov     S9(%rsp), %rcx
    mov     L(%rsp), %r10
    FORK_CALL node_json
    cmp     $LANTERN_JSON_MORE, %rax
    je      98f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      98f
    test    %rax, %rax
    jnz     81f
    mov     S9(%rsp), %rax
    mov     %rax, ApiView_lc_json(%r15)
9:  xor     %eax, %eax
    LEAVE 32
80: movq    $404, ApiView_status(%r15)
    xor     %eax, %eax
    LEAVE 32
81: movq    $500, ApiView_status(%r15)
    xor     %eax, %eax
    LEAVE 32
97: mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 32
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
END_FUNCTION node_api_lc_read

# L2: the body of getLightClientUpdatesByRange (beacon-api.md) of the view rbp (its node
# ApiView_node), with the writer of api_put: from the first period with an update, each update to
# the first period of none. Locals: 0 the fork, 8 1 once an update is in, 16 the period, 24 a
# chunk's length, 32 an epoch, 40 a digest.
LOCAL_FUNCTION api_lc_updates_body
    FRAME 48
    movq    $0, (%rsp)
    movq    $0, 8(%rsp)
    mov     ApiView_lc_start(%rbp), %rax
    mov     %rax, 16(%rsp)
    cmpq    $0, ApiView_lc_ssz(%rbp)
    jne     1f
    API_LIT api_lc_open
1:  mov     16(%rsp), %rax
    cmp     ApiView_lc_end(%rbp), %rax
    jae     8f
    mov     ApiView_lc_store(%rbp), %rdi
    mov     $LC_OBJECT_UPDATE, %esi
    mov     16(%rsp), %rdx
    mov     ApiView_lc_bytes(%rbp), %rcx
    movq    $(24 + LC_UPDATE_ROOM), (%rcx)
    lea     (%rsp), %r8
    call    lantern_lc_read
    test    %rax, %rax
    jz      2f
    cmpq    $0, 8(%rsp)                     # none: after an update, the end; before, the next period
    jne     8f
    incq    16(%rsp)
    jmp     1b
2:  cmpq    $0, ApiView_lc_ssz(%rbp)
    je      3f
    mov     ApiView_lc_bytes(%rbp), %rax    # SSZ: response_chunk_len, the context, the bytes
    mov     16(%rax), %rcx
    add     $4, %rcx
    mov     %rcx, 24(%rsp)
    lea     24(%rsp), %rdi
    mov     $8, %esi
    call    api_put
    mov     ApiView_lc_bytes(%rbp), %rax
    mov     8(%rax), %rcx
    add     %rcx, %rax
    cmpq    $FORK_CAPELLA, (%rsp)
    jb      21f
    mov     (%rax), %ecx
    add     %rcx, %rax
21: mov     (%rax), %rax                    # attested_header.beacon.slot: its epoch's fork digest
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, 32(%rsp)
    mov     ApiView_lc_json(%rbp), %rcx     # its room, as the digest's scratch
    movq    $(24 + 4 * LC_UPDATE_ROOM + 4096), (%rcx)
    mov     ApiView_node(%rbp), %rax
    lea     Node_genesis_validators_root(%rax), %rdi
    lea     32(%rsp), %rsi
    lea     Node_config(%rax), %rdx
    lea     40(%rsp), %r8
    mov     (%rsp), %r10
    FORK_CALL compute_fork_digest
    lea     40(%rsp), %rdi
    mov     $4, %esi
    call    api_put
    mov     ApiView_lc_bytes(%rbp), %rax
    mov     8(%rax), %rdi
    add     %rax, %rdi
    mov     16(%rax), %rsi
    call    api_put
    jmp     4f
3:  cmpq    $0, 8(%rsp)                     # JSON: {"version":…,"data":…}, with , between
    je      31f
    API_LIT api_lc_comma
31: API_LIT api_j_version
    mov     (%rsp), %rdi
    call    api_fork_name
    API_LIT api_g_data
    mov     ApiView_lc_json(%rbp), %rax
    movq    $(24 + 4 * LC_UPDATE_ROOM + 4096), (%rax)
    movq    $24, 8(%rax)
    movq    $0, 16(%rax)
    mov     ApiView_lc_cursor(%rbp), %rdi
    mov     $JSON_CURSOR_SIZE, %esi
    call    lantern_zero
    mov     $NODE_JSON_LC_UPDATE, %edi
    mov     ApiView_lc_bytes(%rbp), %rsi
    mov     ApiView_lc_cursor(%rbp), %rdx
    mov     ApiView_lc_json(%rbp), %rcx
    mov     (%rsp), %r10
    FORK_CALL node_json
    test    %rax, %rax
    jnz     8f
    mov     ApiView_lc_json(%rbp), %rax
    mov     8(%rax), %rdi
    add     %rax, %rdi
    mov     16(%rax), %rsi
    call    api_put
    API_LIT api_end1
4:  movq    $1, 8(%rsp)
    incq    16(%rsp)
    jmp     1b
8:  cmpq    $0, ApiView_lc_ssz(%rbp)
    jne     9f
    API_LIT api_lc_close
9:  UNFRAME 48
END_FUNCTION api_lc_updates_body

# L2: (node, store, work, state_a, data, state_c; scratch r10, event r11) -> status: a
# NODE_WORK_LC_BLOCK or NODE_WORK_LC_HEAD of lantern_node_run (node.md). rbx node, rbp store, r12
# work, r13 state_a, r14 data, r15 the LcStore; S7 scratch, S8 event, S9 the latest update.
LOCAL_FUNCTION node_run_lc
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    mov     %r10, S7(%rsp)
    mov     %r11, S8(%rsp)
    test    %r15, %r15
    jz      97f
    cmpq    $NODE_WORK_LC_HEAD, NodeAction_work_kind(%r12)
    je      2f
    test    %r13, %r13                      # LC_BLOCK: lantern_lc_on_block of the post-state and the block
    jz      97f
    test    %r14, %r14
    jz      97f
    mov     %r15, %rdi
    lea     Node_config(%rbx), %rsi
    mov     %r13, %rdx
    mov     %r14, %rcx
    xor     %r8d, %r8d
    mov     S7(%rsp), %r9
    call    lantern_lc_on_block
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      9f
    mov     S8(%rsp), %rcx
    mov     %rax, NodeEvent_result(%rcx)
    xor     %eax, %eax
    LEAVE 0
2:  mov     %r15, %rdi                      # LC_HEAD: lantern_lc_on_head of the head and the store's finalized checkpoint
    lea     Node_config(%rbx), %rsi
    lea     Node_head_root(%rbx), %rdx
    lea     Store_finalized_checkpoint(%rbp), %rcx
    mov     S7(%rsp), %r8
    call    lantern_lc_on_head
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      9f
    mov     S8(%rsp), %rcx
    mov     %rax, NodeEvent_result(%rcx)
    test    %rax, %rax
    jnz     8f
    mov     LcStore_latest(%r15), %rdx      # the latest finality update's slots and supermajority
    test    %rdx, %rdx
    jz      8f
    mov     %r15, %rdi
    mov     $LC_PART_UPDATES, %esi
    call    lc_ref
    mov     %rax, S9(%rsp)
    mov     %r15, %rdi
    mov     $LC_PART_HEADERS, %esi
    mov     LcUpdate_finalized_header(%rax), %rdx
    call    lc_ref
    lea     LcHeader_header(%rax), %rax
    mov     8(%rax), %rcx
    mov     (%rax,%rcx), %rcx
    mov     S8(%rsp), %rdx
    mov     %rcx, NodeEvent_index(%rdx)
    mov     %r15, %rdi
    mov     $LC_PART_HEADERS, %esi
    mov     S9(%rsp), %rax
    mov     LcUpdate_attested_header(%rax), %rdx
    call    lc_ref
    lea     LcHeader_header(%rax), %rax
    mov     8(%rax), %rcx
    mov     (%rax,%rcx), %rcx
    mov     S8(%rsp), %rdx
    mov     %rcx, NodeEvent_root(%rdx)
    mov     S9(%rsp), %rdi
    add     $LcUpdate_sync_aggregate, %rdi
    call    lc_participants
    imul    $3, %rax, %rax
    xor     %ecx, %ecx
    cmp     $(SYNC_COMMITTEE_SIZE * 2), %rax
    setae   %cl
    mov     S8(%rsp), %rdx
    mov     %rcx, (NodeEvent_root + 8)(%rdx)
    movq    $1, (NodeEvent_root + 16)(%rdx)
8:  xor     %eax, %eax
    LEAVE 0
9:  LEAVE 0
97: mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 0
END_FUNCTION node_run_lc

# L1: the NODE_EV_WORK_DONE r12 of a NODE_WORK_LC_HEAD (node.md, The events): a new finality update,
# or a new optimistic update, sets the node's fields and gives the event of its topic. rbx the node,
# r15 the actions; r13 its finalized slot, r14 its attested slot, rbp its supermajority.
LOCAL_FUNCTION node_lc_head_done
    ENTER 0
    cmpq    $0, NodeEvent_result(%r12)
    jne     9f
    cmpq    $0, (NodeEvent_root + 16)(%r12)
    je      9f
    mov     NodeEvent_index(%r12), %r13
    mov     NodeEvent_root(%r12), %r14
    mov     (NodeEvent_root + 8)(%r12), %rbp
    cmp     Node_lc_finality_slot(%rbx), %r13   # finality: a higher finalized slot, or the same with a new supermajority
    ja      1f
    jne     2f
    cmpq    $0, Node_lc_finality_super(%rbx)
    jne     2f
    test    %rbp, %rbp
    jz      2f
1:  mov     %r13, Node_lc_finality_slot(%rbx)
    mov     %rbp, Node_lc_finality_super(%rbx)
    mov     $API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE, %edi
    call    node_lc_event
2:  cmp     Node_lc_optimistic_slot(%rbx), %r14 # optimistic: a higher attested slot
    jbe     9f
    mov     %r14, Node_lc_optimistic_slot(%rbx)
    mov     $API_TOPIC_LIGHT_CLIENT_OPTIMISTIC_UPDATE, %edi
    call    node_lc_event
9:  LEAVE 0
END_FUNCTION node_lc_head_done

# L1: a NODE_WORK_API_EVENT of the topic rdi with the light client store as state_c, when an entry has the topic.
LOCAL_FUNCTION node_lc_event
    FRAME 16
    mov     %rdi, (%rsp)
    call    node_api_subscribed
    test    %rax, %rax
    jz      9f
    mov     $NODE_WORK_API_EVENT, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    mov     (%rsp), %r9
    call    node_work
    movq    $NODE_LC_ID, NodeAction_state_c(%rax)
9:  UNFRAME 16
END_FUNCTION node_lc_event

# L2: (out, topic, lc, scratch) -> rax: the text of a light client event (beacon-api.md, eventstream):
# event: <topic> LF data: {"version":…,"data":…} LF LF, into the ByteList out, its count set;
# LANTERN_OK, LANTERN_NO_STATE_ANSWER with no update, LANTERN_BUFFER_TOO_SMALL. The writer's
# registers r12-r15; rbx out, rbp the topic; S7 lc, S8 scratch, S9 the object, S10 the kind.
# Locals: L the fork, L + 8 the scratch's size.
LOCAL_FUNCTION api_lc_event_text
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, S7(%rsp)
    mov     %rcx, S8(%rsp)
    mov     (%rcx), %rax
    mov     %rax, (L + 8)(%rsp)
    sub     $(24 + LC_UPDATE_ROOM + JSON_CURSOR_SIZE), %rax  # the object and a cursor at the end of scratch
    jb      98f
    mov     %rax, (%rcx)
    add     %rcx, %rax
    movq    $(24 + LC_UPDATE_ROOM), (%rax)
    mov     %rax, S9(%rsp)
    mov     $LC_OBJECT_FINALITY_UPDATE, %esi
    mov     $LC_OBJECT_OPTIMISTIC_UPDATE, %eax
    cmp     $API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE, %rbp
    cmovne  %rax, %rsi
    mov     %rsi, S10(%rsp)
    mov     S7(%rsp), %rdi
    xor     %edx, %edx
    mov     S9(%rsp), %rcx
    lea     L(%rsp), %r8
    call    lantern_lc_read
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      98f
    test    %rax, %rax
    jnz     9f
    mov     $1, %r13d                       # the writer
    xor     %r15d, %r15d
    lea     24(%rbx), %r12
    mov     (%rbx), %r14
    add     %rbx, %r14
    API_LIT api_ev_event
    cmp     $API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE, %rbp
    jne     1f
    API_LIT api_ev_t_lc_finality
    jmp     2f
1:  API_LIT api_ev_t_lc_optimistic
2:  API_LIT api_ev_data
    API_LIT api_j_version
    mov     L(%rsp), %rdi
    call    api_fork_name
    API_LIT api_g_data
    test    %r15, %r15
    jnz     98f
    lea     24(%rbx), %rax                  # the JSON after the bytes so far
    mov     %r12, %rcx
    sub     %rax, %rcx
    movq    $24, 8(%rbx)
    mov     %rcx, 16(%rbx)
    mov     S9(%rsp), %rdi
    add     $(24 + LC_UPDATE_ROOM), %rdi
    mov     $JSON_CURSOR_SIZE, %esi
    call    lantern_zero
    mov     $NODE_JSON_LC_FINALITY_UPDATE, %edi
    mov     $NODE_JSON_LC_OPTIMISTIC_UPDATE, %eax
    cmpq    $LC_OBJECT_FINALITY_UPDATE, S10(%rsp)
    cmovne  %rax, %rdi
    mov     S9(%rsp), %rsi
    lea     (24 + LC_UPDATE_ROOM)(%rsi), %rdx
    mov     %rbx, %rcx
    mov     L(%rsp), %r10
    FORK_CALL node_json
    cmp     $LANTERN_JSON_MORE, %rax
    je      98f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      98f
    test    %rax, %rax
    jnz     97f
    mov     16(%rbx), %rax
    lea     24(%rbx,%rax), %r12
    API_LIT api_end1
    API_LIT api_ev_lf2
    test    %r15, %r15
    jnz     98f
    lea     24(%rbx), %rax
    mov     %r12, %rcx
    sub     %rax, %rcx
    movq    $24, 8(%rbx)
    mov     %rcx, 16(%rbx)
    xor     %eax, %eax
9:  mov     S8(%rsp), %rcx
    mov     (L + 8)(%rsp), %rdx
    mov     %rdx, (%rcx)
    LEAVE 16
97: mov     $LANTERN_INVALID_ENCODING, %eax
    jmp     9b
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    jmp     9b
END_FUNCTION api_lc_event_text

# L2: (node, work, data, lc, scratch, event; room r10) -> status: a NODE_WORK_LC_SERVE of
# lantern_node_run (node.md): the response chunks of the light client method arg at NodeEvent_chunk
# of the event. rbx node, r12 work, r13 data, r14 lc, r15 scratch, rbp event; S7 the chunks'
# ByteList, S8 the object at the end of scratch, S9 the period, S10 the end period. Locals: L the
# scratch's size, L + 8 1 once an update is in, L + 16 an empty ByteList.
LOCAL_FUNCTION node_run_lc_serve
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %r12
    mov     %rdx, %r13
    mov     %rcx, %r14
    mov     %r8, %r15
    mov     %r9, %rbp
    test    %r14, %r14
    jz      97f
    mov     (%r15), %rax
    mov     %rax, L(%rsp)
    lea     -NodeEvent_chunk(%r10), %rax    # the chunks, in the event
    and     $-8, %rax
    cmp     $64, %rax
    jb      98f
    lea     NodeEvent_chunk(%rbp), %rcx
    mov     %rcx, S7(%rsp)
    mov     %rax, (%rcx)
    movq    $24, 8(%rcx)
    movq    $0, 16(%rcx)
    mov     (%r15), %rax                    # the object at the end of scratch
    sub     $(24 + LC_UPDATE_ROOM), %rax
    jb      98f
    mov     %rax, (%r15)
    add     %r15, %rax
    mov     %rax, S8(%rsp)
    mov     NodeAction_arg(%r12), %rax
    cmp     $REQRESP_LIGHT_CLIENT_UPDATES_BY_RANGE, %rax
    je      10f
    mov     $LC_OBJECT_FINALITY_UPDATE, %esi
    cmp     $REQRESP_LIGHT_CLIENT_FINALITY_UPDATE, %rax
    je      2f
    mov     $LC_OBJECT_OPTIMISTIC_UPDATE, %esi
    cmp     $REQRESP_LIGHT_CLIENT_OPTIMISTIC_UPDATE, %rax
    je      2f
    cmp     $REQRESP_LIGHT_CLIENT_BOOTSTRAP, %rax
    jne     96f
    test    %r13, %r13                      # GetLightClientBootstrap: of the root's 32 bytes
    jz      96f
    cmpq    $32, 16(%r13)
    jne     96f
    mov     $LC_OBJECT_BOOTSTRAP, %esi
    mov     8(%r13), %rdx
    add     %r13, %rdx
    jmp     3f
2:  xor     %edx, %edx
3:  mov     %r14, %rdi
    mov     S8(%rsp), %rcx
    mov     S7(%rsp), %r8
    mov     %r15, %r9
    mov     %rbx, %r10
    call    node_lc_chunk
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      98f
    cmp     $LANTERN_NO_STATE_ANSWER, %rax
    jne     4f
    movq    $24, (L + 16)(%rsp)             # none: ResourceUnavailable, no payload
    movq    $24, (L + 24)(%rsp)
    movq    $0, (L + 32)(%rsp)
    mov     $3, %edi
    lea     (L + 16)(%rsp), %rsi
    mov     %r15, %rdx
    mov     S7(%rsp), %rcx
    call    node_lc_error_chunk
    test    %rax, %rax
    jnz     98f
    jmp     20f
4:  test    %rax, %rax
    jnz     96f
    jmp     20f
10: test    %r13, %r13                      # LightClientUpdatesByRange: start_period, count
    jz      96f
    cmpq    $16, 16(%r13)
    jne     96f
    mov     8(%r13), %rax
    add     %r13, %rax
    mov     (%rax), %rcx
    mov     %rcx, S9(%rsp)
    mov     8(%rax), %rdx
    mov     $MAX_REQUEST_LIGHT_CLIENT_UPDATES, %eax
    cmp     %rax, %rdx
    cmova   %rax, %rdx
    add     %rcx, %rdx
    mov     $-1, %rax
    cmovc   %rax, %rdx
    mov     %rdx, S10(%rsp)
    movq    $0, (L + 8)(%rsp)
11: mov     S9(%rsp), %rdx
    cmp     S10(%rsp), %rdx
    jae     20f
    mov     %r14, %rdi
    mov     $LC_OBJECT_UPDATE, %esi
    mov     S8(%rsp), %rcx
    mov     S7(%rsp), %r8
    mov     %r15, %r9
    mov     %rbx, %r10
    call    node_lc_chunk
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      98f
    incq    S9(%rsp)
    test    %rax, %rax
    jz      12f
    cmpq    $0, (L + 8)(%rsp)               # none: after an update, the end; before, the next period
    jne     20f
    jmp     11b
12: movq    $1, (L + 8)(%rsp)
    jmp     11b
20: mov     S7(%rsp), %rcx                  # the event's size covers the chunks
    mov     16(%rcx), %rax
    add     $(NodeEvent_chunk + 24 + 7), %rax
    and     $-8, %rax
    mov     %rax, (%rbp)
    sub     $NodeEvent_chunk, %rax
    mov     %rax, (%rcx)
    mov     L(%rsp), %rax
    mov     %rax, (%r15)
    xor     %eax, %eax
    LEAVE 48
96: movq    $LANTERN_INVALID_ENCODING, NodeEvent_result(%rbp)
    mov     L(%rsp), %rax
    mov     %rax, (%r15)
    xor     %eax, %eax
    LEAVE 48
97: mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 48
98: mov     L(%rsp), %rax
    mov     %rax, (%r15)
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
END_FUNCTION node_run_lc_serve

# L2: (lc, kind, key, object, out, scratch; node r10) -> status: lantern_lc_read of the kind and key
# into the object, then its response chunk after the bytes of out: result 0, the context
# compute_fork_digest of the epoch of its attested slot. The statuses of lantern_lc_read and
# lantern_reqresp_write_chunk. The scratch's size as it came. rbx node, r12 the object, r13 out, r14
# scratch. Locals: L a ChunkHeader, L + 48 the fork, L + 56 the epoch, L + 64 the scratch's size.
LOCAL_FUNCTION node_lc_chunk
    ENTER 80
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     %r9, %r14
    mov     %r10, %rbx
    mov     (%r14), %rax
    mov     %rax, (L + 64)(%rsp)
    movq    $(24 + LC_UPDATE_ROOM), (%r12)
    lea     (L + 48)(%rsp), %r8
    call    lantern_lc_read
    test    %rax, %rax
    jnz     9f
    mov     8(%r12), %rax                   # attested_header.beacon.slot, a bootstrap's header.beacon.slot
    add     %r12, %rax
    cmpq    $FORK_CAPELLA, (L + 48)(%rsp)
    jb      1f
    mov     (%rax), %ecx
    add     %rcx, %rax
1:  mov     (%rax), %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, (L + 56)(%rsp)
    movq    $CHUNK_RESPONSE, (L + ChunkHeader_kind)(%rsp)
    movq    $4, (L + ChunkHeader_context_length)(%rsp)
    movq    $0, (L + ChunkHeader_result)(%rsp)
    movq    $0, (L + ChunkHeader_context)(%rsp)
    lea     Node_genesis_validators_root(%rbx), %rdi
    lea     (L + 56)(%rsp), %rsi
    lea     Node_config(%rbx), %rdx
    mov     %r14, %rcx
    lea     (L + ChunkHeader_context)(%rsp), %r8
    mov     (L + 48)(%rsp), %r10
    FORK_CALL compute_fork_digest
    test    %rax, %rax
    jnz     8f
    mov     (L + 64)(%rsp), %rax            # the scratch's size again (asm-standard: before each call)
    mov     %rax, (%r14)
    lea     L(%rsp), %rdi
    mov     %r12, %rsi
    mov     %r14, %rdx
    mov     %r13, %rcx
    call    lantern_reqresp_write_chunk
9:  mov     (L + 64)(%rsp), %rcx            # the scratch's size, as it came
    mov     %rcx, (%r14)
    LEAVE 80
8:  mov     $LANTERN_INVALID_ENCODING, %eax
    jmp     9b
END_FUNCTION node_lc_chunk

# L1: (result, payload, scratch, out) -> status: a response chunk of the result, with no context bytes, after the bytes of out. Locals: 0 a ChunkHeader.
LOCAL_FUNCTION node_lc_error_chunk
    FRAME 48
    movq    $CHUNK_RESPONSE, ChunkHeader_kind(%rsp)
    movq    $0, ChunkHeader_context_length(%rsp)
    mov     %rdi, ChunkHeader_result(%rsp)
    movq    $0, ChunkHeader_context(%rsp)
    mov     %rsp, %rdi
    call    lantern_reqresp_write_chunk
    UNFRAME 48
END_FUNCTION node_lc_error_chunk

# L1: a light client request of the stream entry rdi (node.md): its rdx bytes at rsi (none with 0) to
# a new id, a NODE_WORK_LC_SERVE of them with the light client store as state_c; the stream takes
# NODE_STREAM_SERVING, its list empty. r12 the entry, r13 the id. Locals: L a ByteList of the bytes.
LOCAL_FUNCTION node_lc_request
    ENTER 64
    mov     %rdi, %r12
    xor     %r13d, %r13d
    test    %rdx, %rdx
    jz      1f
    lea     24(%rdx), %rax
    mov     %rax, L(%rsp)
    movq    $24, (L + 8)(%rsp)
    mov     %rdx, (L + 16)(%rsp)
    lea     (L + 24)(%rsp), %rdi
    call    lantern_copy
    lea     L(%rsp), %rdi
    call    node_put
    mov     %rax, %r13
1:  mov     $NODE_WORK_LC_SERVE, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     %r13, %rcx
    mov     NodeStream_handle(%r12), %r8
    mov     NodeStream_method(%r12), %r9
    call    node_work
    movq    $NODE_LC_ID, NodeAction_state_c(%rax)
    movq    $NODE_STREAM_SERVING, NodeStream_state(%r12)
    movq    $0, (NodeStream_list + 16)(%r12)
    LEAVE 64
END_FUNCTION node_lc_request

# L1: the NODE_EV_WORK_DONE r12 of a NODE_WORK_LC_SERVE (node.md): its bytes go, then the chunks to
# the stream in a STREAM_WRITE and a STREAM_CLOSE, or a STREAM_RESET; then the stream goes. rbx
# the node, r15 the actions; r13 the stream, r14 the chunks' bytes, rbp the event's size.
LOCAL_FUNCTION node_lc_served
    ENTER 0
    mov     NodeAction_data(%r12), %rsi
    test    %rsi, %rsi
    jz      1f
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    node_ids
1:  mov     NodeAction_target(%r12), %rdi
    call    node_find_stream
    cmp     $-1, %rax
    je      9f
    mov     %rdx, %r13
    cmpq    $0, NodeEvent_result(%r12)
    jne     8f
    mov     (NodeEvent_chunk + 16)(%r12), %r14
    test    %r14, %r14
    jz      7f
    lea     (32 + 7)(%r14), %rbp
    and     $-8, %rbp
    mov     %rbp, %rdi
    call    node_out
    test    %rax, %rax
    jz      8f
    mov     %rbp, (%rax)
    movq    $LIBP2P_EVENT_STREAM_WRITE, 8(%rax)
    mov     NodeStream_handle(%r13), %rcx
    mov     %rcx, 16(%rax)
    mov     %r14, 24(%rax)
    lea     32(%rax), %rdi
    lea     (NodeEvent_chunk + 24)(%r12), %rsi
    mov     %r14, %rdx
    call    lantern_copy
7:  mov     $LIBP2P_EVENT_STREAM_CLOSE, %edi
    mov     NodeStream_handle(%r13), %rsi
    call    node_out_handle
    mov     %r13, %rdi
    call    node_drop_stream
9:  LEAVE 0
8:  mov     $LIBP2P_EVENT_STREAM_RESET, %edi
    mov     NodeStream_handle(%r13), %rsi
    call    node_out_handle
    mov     %r13, %rdi
    call    node_drop_stream
    LEAVE 0
END_FUNCTION node_lc_served
