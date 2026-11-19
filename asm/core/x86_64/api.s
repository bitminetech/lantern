/*
 * The Beacon API answers of the node, x86-64: in the common object. Requirements:
 * docs/reference/beacon-api.md (Common rules) and docs/reference/node.md (NODE_EV_API).
 *
 * The writer: r12 the cursor, r13 the pass (0 counts the bytes, 1 writes them), r14 the end of
 * the room, r15 1 when the room ran out, rbp the ApiView. The writer's functions keep r12-r15
 * and rbp for it; only api_respond calls them.
 */

    RODATA
.include "api_text.inc"

/* The text at label joins the response. */
.macro API_LIT label
    lea     \label(%rip), %rdi
    mov     $\label\()_len, %esi
    call    api_put
.endm

/* The rsi bytes at rdi join the response; the first pass only counts them. Uses rax, rcx, rsi, rdi. */
LOCAL_FUNCTION api_put
    UNWIND_END_PROLOGUE
    test    %r13, %r13
    jz      2f
    lea     (%r12,%rsi), %rax
    cmp     %r14, %rax
    ja      3f
    mov     %rsi, %rcx
    mov     %rdi, %rsi
    mov     %r12, %rdi
    rep movsb
    mov     %rdi, %r12
    ret
2:  add     %rsi, %r12
    ret
3:  mov     $1, %r15d
    ret
END_FUNCTION api_put

/* The decimal digits of rdi join the response. Locals: the digits, from the end. */
LOCAL_FUNCTION api_dec
    FRAME 32
    lea     32(%rsp), %r8
    mov     %rdi, %rax
    mov     $10, %ecx
1:  xor     %edx, %edx
    div     %rcx
    add     $0x30, %dl
    dec     %r8
    mov     %dl, (%r8)
    test    %rax, %rax
    jnz     1b
    mov     %r8, %rdi
    lea     32(%rsp), %rsi
    sub     %r8, %rsi
    call    api_put
    UNFRAME 32
END_FUNCTION api_dec

/* The decimal digits of rdi, in quotes. Locals: rdi. */
LOCAL_FUNCTION api_qdec
    FRAME 16
    mov     %rdi, (%rsp)
    API_LIT api_quote
    mov     (%rsp), %rdi
    call    api_dec
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION api_qdec

/* "0x" and the lower case hex of the rsi bytes at rdi, in quotes. Locals: rdi, rsi, then 2 digits. */
LOCAL_FUNCTION api_qhex
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    API_LIT api_quote
    API_LIT api_0x
1:  mov     8(%rsp), %rsi
    test    %rsi, %rsi
    jz      2f
    mov     (%rsp), %rdi
    movzbl  (%rdi), %eax
    inc     %rdi
    dec     %rsi
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    lea     api_hex(%rip), %rcx
    mov     %eax, %edx
    shr     $4, %edx
    movzbl  (%rcx,%rdx), %edx
    mov     %dl, 16(%rsp)
    and     $15, %eax
    movzbl  (%rcx,%rax), %eax
    mov     %al, 17(%rsp)
    lea     16(%rsp), %rdi
    mov     $2, %esi
    call    api_put
    jmp     1b
2:  API_LIT api_quote
    UNFRAME 32
END_FUNCTION api_qhex

/* The text at rdi (its length, then its bytes), in quotes. Locals: rdi. */
LOCAL_FUNCTION api_text
    FRAME 16
    mov     %rdi, (%rsp)
    API_LIT api_quote
    mov     (%rsp), %rax
    mov     (%rax), %rsi
    lea     8(%rax), %rdi
    call    api_put
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION api_text

/* true when rdi is not 0, else false. */
LOCAL_FUNCTION api_bool
    FRAME 0
    test    %rdi, %rdi
    jz      1f
    API_LIT api_true
    UNFRAME 0
1:  API_LIT api_false
    UNFRAME 0
END_FUNCTION api_bool

/* A Checkpoint of the view at rdi: {"epoch":…,"root":…}. Locals: rdi. */
LOCAL_FUNCTION api_checkpoint
    FRAME 16
    mov     %rdi, (%rsp)
    API_LIT api_f_epoch
    mov     (%rsp), %rax
    mov     (%rax), %rdi
    call    api_qdec
    API_LIT api_f_root
    mov     (%rsp), %rdi
    add     $8, %rdi
    mov     $32, %esi
    call    api_qhex
    API_LIT api_end1
    UNFRAME 16
END_FUNCTION api_checkpoint

/* rax = the api_codes entry of the status rdi, or 0. Uses rcx. */
LOCAL_FUNCTION api_code
    UNWIND_END_PROLOGUE
    lea     api_codes(%rip), %rax
    lea     api_codes_end(%rip), %rcx
1:  cmp     %rcx, %rax
    jae     2f
    cmp     (%rax), %rdi
    je      3f
    add     $API_CODE_ENTRY, %rax
    jmp     1b
2:  xor     %eax, %eax
3:  ret
END_FUNCTION api_code

/* The text of the api_codes entry rdi at its byte rsi (8 the reason, 24 the message), or none for no entry. */
LOCAL_FUNCTION api_code_text
    FRAME 0
    test    %rdi, %rdi
    jz      9f
    mov     (%rdi,%rsi), %rax
    mov     8(%rdi,%rsi), %rsi
    lea     api_texts(%rip), %rdi
    add     %rax, %rdi
    call    api_put
9:  UNFRAME 0
END_FUNCTION api_code_text

/*
 * The body of the kind rsi for the view rbp: an error body of the status at (rdi), or the JSON of
 * an operation (beacon-api.md, Common rules). Locals: rdi, rsi.
 */
LOCAL_FUNCTION api_body
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    cmp     $API_BODY_ERROR, %rsi
    jne     1f
    # {"code":<n>,"message":"<m>"}
    API_LIT api_e_code
    mov     (%rsp), %rax
    mov     (%rax), %rdi
    call    api_dec
    API_LIT api_e_message
    mov     (%rsp), %rax
    mov     (%rax), %rdi
    call    api_code
    mov     %rax, %rdi
    mov     $24, %esi
    call    api_code_text
    API_LIT api_e_end
    UNFRAME 16
1:  cmp     $API_OP_GET_NETWORK_IDENTITY, %rsi
    jne     2f
    API_LIT api_i_peer_id
    lea     ApiView_peer_id(%rbp), %rdi
    call    api_text
    API_LIT api_i_enr
    lea     ApiView_enr(%rbp), %rdi
    call    api_text
    API_LIT api_i_p2p
    cmpq    $0, ApiView_p2p_address(%rbp)
    je      14f
    lea     ApiView_p2p_address(%rbp), %rdi
    call    api_text
14: API_LIT api_i_discovery
    cmpq    $0, ApiView_discovery_address(%rbp)
    je      15f
    lea     ApiView_discovery_address(%rbp), %rdi
    call    api_text
15: API_LIT api_i_seq
    mov     ApiView_seq_number(%rbp), %rdi
    call    api_qdec
    API_LIT api_i_attnets
    lea     ApiView_attnets(%rbp), %rdi
    mov     $8, %esi
    call    api_qhex
    cmpq    $FORK_ALTAIR, ApiView_fork(%rbp)
    jb      16f
    API_LIT api_i_syncnets
    lea     ApiView_syncnets(%rbp), %rdi
    mov     $1, %esi
    call    api_qhex
    cmpq    $FORK_FULU, ApiView_fork(%rbp)
    jb      16f
    API_LIT api_i_cgc
    mov     ApiView_custody_group_count(%rbp), %rdi
    call    api_qdec
16: API_LIT api_end3
    UNFRAME 16
2:  cmp     $API_OP_GET_NODE_VERSION, %rsi
    jne     3f
    API_LIT api_v_version
    lea     ApiView_version(%rbp), %rdi
    call    api_text
    API_LIT api_end2
    UNFRAME 16
3:  cmp     $API_OP_GET_SYNCING_STATUS, %rsi
    jne     4f
    API_LIT api_s_head
    mov     ApiView_head_slot(%rbp), %rdi
    call    api_qdec
    API_LIT api_s_distance
    mov     ApiView_current_slot(%rbp), %rdi
    sub     ApiView_head_slot(%rbp), %rdi
    jae     31f
    xor     %edi, %edi
31: call    api_qdec
    API_LIT api_s_syncing
    mov     ApiView_is_syncing(%rbp), %rdi
    call    api_bool
    API_LIT api_s_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    api_bool
    API_LIT api_s_offline
    mov     ApiView_el_offline(%rbp), %rdi
    call    api_bool
    API_LIT api_end2
    UNFRAME 16
4:  cmp     $API_OP_GET_PEER_COUNT, %rsi
    jne     5f
    API_LIT api_c_connected
    mov     ApiView_peers(%rbp), %rdi
    call    api_qdec
    API_LIT api_c_end
    UNFRAME 16
5:  cmp     $API_OP_GET_GENESIS, %rsi
    jne     6f
    API_LIT api_g_time
    mov     ApiView_genesis_time(%rbp), %rdi
    call    api_qdec
    API_LIT api_g_root
    lea     ApiView_genesis_validators_root(%rbp), %rdi
    mov     $32, %esi
    call    api_qhex
    API_LIT api_g_version
    lea     ApiView_genesis_fork_version(%rbp), %rdi
    mov     $4, %esi
    call    api_qhex
    API_LIT api_end2
    UNFRAME 16
6:  cmp     $API_OP_GET_BLOCK_HEADER, %rsi
    jne     7f
    API_LIT api_x_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    api_bool
    API_LIT api_x_finalized
    API_LIT api_h_root
    lea     ApiView_head_root(%rbp), %rdi
    mov     $32, %esi
    call    api_qhex
    API_LIT api_h_slot
    mov     ApiView_head_slot(%rbp), %rdi
    call    api_qdec
    API_LIT api_h_proposer
    mov     ApiView_proposer_index(%rbp), %rdi
    call    api_qdec
    API_LIT api_h_parent
    lea     ApiView_parent_root(%rbp), %rdi
    mov     $32, %esi
    call    api_qhex
    API_LIT api_h_state
    lea     ApiView_state_root(%rbp), %rdi
    mov     $32, %esi
    call    api_qhex
    API_LIT api_h_body
    lea     ApiView_body_root(%rbp), %rdi
    mov     $32, %esi
    call    api_qhex
    API_LIT api_h_signature
    lea     ApiView_signature(%rbp), %rdi
    mov     $96, %esi
    call    api_qhex
    API_LIT api_end3
    UNFRAME 16
7:  cmp     $API_OP_GET_STATE_FINALITY_CHECKPOINTS, %rsi
    jne     9f
    API_LIT api_x_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    api_bool
    API_LIT api_x_finalized
    API_LIT api_f_previous
    lea     ApiView_previous_justified(%rbp), %rdi
    call    api_checkpoint
    API_LIT api_f_current
    lea     ApiView_current_justified(%rbp), %rdi
    call    api_checkpoint
    API_LIT api_f_finalized
    lea     ApiView_finalized(%rbp), %rdi
    call    api_checkpoint
    API_LIT api_end2
9:  UNFRAME 16
END_FUNCTION api_body

/*
 * (view rdi, out rsi, status rdx, body rcx, flags r8) -> rax: the HTTP response of beacon-api.md,
 * Common rules, into the ByteList out, its count set: the status line, its fields, then the body
 * of the kind body (0 none, API_BODY_ERROR, or an API_OP_*) from the ApiView view. flags:
 * API_R_CLOSE, API_R_KEEP, API_R_NO_REASON, and the allow bits from bit 8. rax = LANTERN_OK, or
 * LANTERN_BUFFER_TOO_SMALL when out has too little room. rbx out. Locals: L status, L+8 flags,
 * L+16 the body's bytes, L+24 the body's kind.
 */
LOCAL_FUNCTION api_respond
    ENTER 32
    mov     %rdi, %rbp
    mov     %rsi, %rbx
    mov     %rdx, L(%rsp)
    mov     %r8, (L + 8)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
    xor     %r13d, %r13d                    # the body's bytes
    xor     %r12d, %r12d
    xor     %r15d, %r15d
    test    %rcx, %rcx
    jz      1f
    lea     L(%rsp), %rdi
    mov     %rcx, %rsi
    call    api_body
1:  mov     %r12, (L + 16)(%rsp)
    mov     $1, %r13d                       # the response
    lea     24(%rbx), %r12
    mov     (%rbx), %r14
    add     %rbx, %r14
    # HTTP/1.1 <code> <reason> CRLF
    API_LIT api_http
    mov     L(%rsp), %rdi
    call    api_dec
    API_LIT api_sp
    testq   $API_R_NO_REASON, (L + 8)(%rsp)
    jnz     2f
    mov     L(%rsp), %rdi
    call    api_code
    mov     %rax, %rdi
    mov     $8, %esi
    call    api_code_text
2:  API_LIT api_crlf
    cmpq    $0, (L + 16)(%rsp)
    je      3f
    API_LIT api_type
3:  API_LIT api_length
    mov     (L + 16)(%rsp), %rdi
    call    api_dec
    API_LIT api_crlf
    cmpq    $405, L(%rsp)
    jne     5f
    # Allow: GET, POST or GET, POST
    API_LIT api_allow
    testq   $0x100, (L + 8)(%rsp)
    jz      4f
    API_LIT api_get
    testq   $0x200, (L + 8)(%rsp)
    jz      41f
    API_LIT api_comma
4:  testq   $0x200, (L + 8)(%rsp)
    jz      41f
    API_LIT api_post
41: API_LIT api_crlf
5:  testq   $API_R_CLOSE, (L + 8)(%rsp)
    jz      6f
    API_LIT api_close
    jmp     7f
6:  testq   $API_R_KEEP, (L + 8)(%rsp)
    jz      7f
    API_LIT api_keep
7:  API_LIT api_crlf
    cmpq    $0, (L + 24)(%rsp)
    je      8f
    lea     L(%rsp), %rdi
    mov     (L + 24)(%rsp), %rsi
    call    api_body
8:  test    %r15, %r15
    jnz     9f
    lea     24(%rbx), %rax
    mov     %r12, %rcx
    sub     %rax, %rcx
    movq    $24, 8(%rbx)
    mov     %rcx, 16(%rbx)
    xor     %eax, %eax
    LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
END_FUNCTION api_respond

/*
 * The values of the ApiView rdi that the node, rbx, and the store, rbp, give (beacon-api.md,
 * Common rules); the header and the checkpoints zero. Locals: the view.
 */
LOCAL_FUNCTION node_api_view
    FRAME 16
    mov     %rdi, (%rsp)
    mov     $ApiView__size, %esi
    call    lantern_zero
    mov     (%rsp), %rdi
    mov     Store_genesis_time_ms(%rbp), %rax
    xor     %edx, %edx
    mov     $1000, %ecx
    div     %rcx
    mov     %rax, ApiView_genesis_time(%rdi)
    lea     ApiView_genesis_validators_root(%rdi), %rax
    lea     Node_genesis_validators_root(%rbx), %rcx
    COPY32  %rax, %rcx
    mov     (Node_config + CONFIG_GENESIS_FORK_VERSION)(%rbx), %rax
    mov     %rax, ApiView_genesis_fork_version(%rdi)
    lea     Node_head_root(%rbx), %rdi      # the head
    call    node_find_block
    cmp     $-1, %rax
    je      1f
    mov     (%rsp), %rdi
    mov     NodeBlock_slot(%rdx), %rax
    mov     %rax, ApiView_head_slot(%rdi)
    xor     %eax, %eax
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, NodeBlock_payload_status(%rdx)
    sete    %al
    mov     %rax, ApiView_is_optimistic(%rdi)
    lea     ApiView_head_root(%rdi), %rax
    COPY32  %rax, %rdx
1:  mov     %rbp, %rdi                      # the clock, sync, peers, MetaData
    call    node_store_slot
    mov     (%rsp), %rdi
    mov     %rax, ApiView_current_slot(%rdi)
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     (%rsp), %rdi
    mov     %rax, ApiView_fork(%rdi)
    mov     Node_flags(%rbx), %rax
    mov     %rax, %rcx
    shr     $3, %rcx                        # NODE_FLAG_SYNCING
    and     $1, %ecx
    mov     %rcx, ApiView_is_syncing(%rdi)
    shr     $9, %rax                        # NODE_FLAG_EL_OFFLINE
    and     $1, %eax
    mov     %rax, ApiView_el_offline(%rdi)
    mov     (Node_peers + 8)(%rbx), %rax
    mov     %rax, ApiView_peers(%rdi)
    mov     Node_metadata_seq(%rbx), %rax
    mov     %rax, ApiView_seq_number(%rdi)
    mov     Node_attnets(%rbx), %rax
    mov     %rax, ApiView_attnets(%rdi)
    mov     (Node_config + CONFIG_CUSTODY_REQUIREMENT)(%rbx), %rax
    mov     %rax, ApiView_custody_group_count(%rdi)
    add     $ApiView_peer_id, %rdi          # the identity's texts
    lea     Node_api_identity(%rbx), %rsi
    mov     $API_IDENTITY_SIZE, %edx
    call    lantern_copy
    UNFRAME 16
END_FUNCTION node_api_view

/*
 * One NODE_ACT_API_SEND of the connection rdi, with last 1, at the end of the actions r15: the
 * response of api_respond with the view rsi, the status rdx, the body rcx and the flags r8; when it
 * does not fit, the error 500. With API_R_CLOSE, then a NODE_ACT_API_CLOSE. Locals: the
 * connection, the flags, the action, its size.
 */
LOCAL_FUNCTION node_api_send
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %r8, 8(%rsp)
    mov     8(%r15), %rax                   # the action, and the room after it
    add     %r15, %rax
    add     16(%r15), %rax
    mov     %rax, 16(%rsp)
    mov     (%r15), %r9
    sub     8(%r15), %r9
    sub     16(%r15), %r9
    sub     $32, %r9
    and     $~7, %r9
    mov     %r9, 32(%rax)                   # its ByteList at 32
    mov     %rsi, %rdi
    lea     32(%rax), %rsi
    call    api_respond
    test    %eax, %eax
    jz      1f
    xor     %edi, %edi                      # no room: the error 500
    mov     16(%rsp), %rsi
    add     $32, %rsi
    mov     $500, %edx
    mov     $API_BODY_ERROR, %ecx
    mov     8(%rsp), %r8
    and     $(API_R_CLOSE | API_R_KEEP), %r8
    call    api_respond
1:  mov     16(%rsp), %rax
    mov     48(%rax), %rcx                  # the count; the size to a multiple of 8, zero bytes after
    lea     (56 + 7)(%rcx), %rdx
    and     $~7, %rdx
    mov     %rdx, 24(%rsp)
    lea     56(%rax,%rcx), %rdi
    mov     %rdx, %rsi
    sub     $56, %rsi
    sub     %rcx, %rsi
    call    lantern_zero
    mov     16(%rsp), %rax
    mov     24(%rsp), %rdx
    mov     %rdx, (%rax)
    movq    $NODE_ACT_API_SEND, 8(%rax)
    mov     (%rsp), %rcx
    mov     %rcx, 16(%rax)
    movq    $1, 24(%rax)
    lea     -32(%rdx), %rcx
    mov     %rcx, 32(%rax)
    add     %rdx, 16(%r15)
    testq   $API_R_CLOSE, 8(%rsp)
    jz      9f
    mov     $NODE_ACT_API_CLOSE, %edi
    mov     $NODE_ACT_API_CLOSE_SIZE, %esi
    call    node_act
    mov     (%rsp), %rcx
    mov     %rcx, 16(%rax)
9:  UNFRAME 32
END_FUNCTION node_api_send

/*
 * The NODE_EV_API or NODE_EV_API_IDENTITY rdi, whose ByteList at 24 is inside it (node.md,
 * NodeEvent): rax = 0 when it keeps its rules, else 1; rdx = the scratch it needs. Uses rcx,
 * rsi, r8-r11.
 */
LOCAL_FUNCTION node_api_check
    UNWIND_END_PROLOGUE
    mov     (NodeEvent_bytes + 16)(%rdi), %r8   # the count
    lea     (NodeEvent_bytes + 24)(%rdi), %rsi  # the bytes
    cmpq    $NODE_EV_API_IDENTITY, 8(%rdi)
    jne     5f
    cmp     $API_IDENTITY_SIZE, %r8         # IDENTITY: each text in its room, its bytes 0x21 to 0x7e but " and \
    jne     8f
    lea     node_api_rooms(%rip), %r9
1:  mov     (%r9), %r10
    add     $8, %r9
    test    %r10, %r10
    jz      4f
    mov     (%rsi), %r11
    add     $8, %rsi
    cmp     %r10, %r11
    ja      8f
    xor     %ecx, %ecx
2:  cmp     %r11, %rcx
    jae     3f
    movzbl  (%rsi,%rcx), %eax
    lea     -0x21(%rax), %edx
    cmp     $(0x7e - 0x21), %edx
    ja      8f
    cmp     $0x22, %eax
    je      8f
    cmp     $0x5c, %eax
    je      8f
    inc     %rcx
    jmp     2b
3:  add     %r10, %rsi
    jmp     1b
4:  xor     %eax, %eax
    xor     %edx, %edx
    ret
5:  cmp     $HTTP_REQUEST_FIXED, %r8        # API: an HttpRequest of the count's size
    jb      8f
    test    $7, %r8b
    jnz     8f
    cmp     HttpRequest_size(%rsi), %r8
    jne     8f
    cmpq    $0, HttpRequest_status(%rsi)
    jne     7f
    mov     $HttpRequest_path, %ecx         # with status 0, each part inside
6:  cmp     $HTTP_REQUEST_FIXED, %rcx
    jae     7f
    mov     (%rsi,%rcx), %r9
    cmp     %r8, %r9
    ja      8f
    mov     %r8, %r10
    sub     %r9, %r10
    cmp     %r10, 8(%rsi,%rcx)
    ja      8f
    add     $16, %rcx
    jmp     6b
7:  mov     $NODE_API_SCRATCH, %edx
    cmpq    $0, HttpRequest_status(%rsi)
    jne     71f
    mov     (HttpRequest_query + 8)(%rsi), %rax
    lea     (%rdx,%rax,4), %rdx
71: xor     %eax, %eax
    ret
8:  mov     $1, %eax
    xor     %edx, %edx
    ret
END_FUNCTION node_api_check

/* rax = the NODE_DB_REF of the Db's record of the block at rdi, or 0. Locals: the slot. */
LOCAL_FUNCTION node_api_db_ref
    FRAME 16
    testq   $NODE_FLAG_DB, Node_flags(%rbx)
    jz      9f
    mov     %rdi, %rsi
    mov     Node_db(%rbx), %rdi
    add     %rbx, %rdi
    mov     %rsp, %rdx
    call    lantern_db_find_root
    mov     (%rsp), %rdi
    cmp     $-1, %rdi
    je      9f
    call    node_db_block
    UNFRAME 16
9:  xor     %eax, %eax
    UNFRAME 16
END_FUNCTION node_api_db_ref

/*
 * The answer to the NODE_EV_API rdi (node.md, lantern_node_step): rbx the node, rbp the store,
 * r14 the scratch, r15 the actions. r12 the event, r13 its HttpRequest, S7 the ApiRoute, S8 the
 * ApiView, S9 the connection, S10 the flags of api_respond. Locals: L the scratch's size.
 */
LOCAL_FUNCTION node_api_event
    ENTER 16
    mov     %rdi, %r12
    mov     16(%r12), %rax
    mov     %rax, S9(%rsp)
    mov     (NodeEvent_bytes + 8)(%r12), %r13
    lea     NodeEvent_bytes(%r12,%r13), %r13
    movq    $0, S10(%rsp)                   # close after a fault or with close; HTTP/1.0 kept open says so
    mov     HttpRequest_status(%r13), %rax
    or      HttpRequest_close(%r13), %rax
    jz      1f
    movq    $API_R_CLOSE, S10(%rsp)
    jmp     2f
1:  cmpq    $10, HttpRequest_version(%r13)
    jne     2f
    movq    $API_R_KEEP, S10(%rsp)
2:  mov     (%r14), %rax                    # the ApiView, then the ApiRoute, at the end of scratch
    mov     %rax, L(%rsp)
    mov     %r12, %rdi
    call    node_api_check
    mov     L(%rsp), %rax
    sub     %rdx, %rax
    mov     %rax, (%r14)
    add     %r14, %rax
    mov     %rax, S8(%rsp)
    lea     ApiView__size(%rax), %rcx
    mov     %rcx, S7(%rsp)
    sub     $ApiView__size, %rdx
    mov     %rdx, (%rcx)
    mov     %rax, %rdi
    call    node_api_view
    mov     HttpRequest_status(%r13), %rdx  # a fault of the request: its status
    test    %rdx, %rdx
    jnz     80f
    mov     %r13, %rdi
    mov     S7(%rsp), %rsi
    call    lantern_api_route
    cmp     $LANTERN_INVALID_ROUTE, %rax
    jne     3f
    mov     S7(%rsp), %rcx
    mov     ApiRoute_status(%rcx), %rdx
    mov     ApiRoute_allow(%rcx), %rax
    shl     $8, %rax
    or      %rax, S10(%rsp)
    jmp     80f
3:  mov     $500, %edx
    test    %rax, %rax
    jnz     80f
    mov     S7(%rsp), %rax
    mov     ApiRoute_op(%rax), %rcx
    mov     $200, %edx
    cmp     $API_OP_GET_HEALTH, %rcx
    jne     4f
    mov     S8(%rsp), %rax                  # health: 200, else 206 or syncing_status
    mov     ApiView_is_syncing(%rax), %rsi
    or      ApiView_is_optimistic(%rax), %rsi
    or      ApiView_el_offline(%rax), %rsi
    xor     %ecx, %ecx
    test    %rsi, %rsi
    jz      81f
    mov     $206, %edx
    mov     S7(%rsp), %rax
    btq     $API_PARAM_SYNCING_STATUS, ApiRoute_present(%rax)
    jnc     81f
    mov     ApiRoute_syncing_status(%rax), %rdx
    orq     $API_R_NO_REASON, S10(%rsp)
    jmp     81f
4:  cmp     $API_OP_GET_NETWORK_IDENTITY, %rcx
    je      81f
    cmp     $API_OP_GET_NODE_VERSION, %rcx
    je      81f
    cmp     $API_OP_GET_SYNCING_STATUS, %rcx
    je      81f
    cmp     $API_OP_GET_PEER_COUNT, %rcx
    je      81f
    cmp     $API_OP_GET_GENESIS, %rcx
    je      81f
    mov     $404, %edx
    mov     S7(%rsp), %rax
    cmp     $API_OP_GET_STATE_FINALITY_CHECKPOINTS, %rcx
    jne     5f
    cmpq    $API_ID_HEAD, ApiRoute_id_kind(%rax)    # finality_checkpoints: of head
    jne     80f
    jmp     60f
5:  cmp     $API_OP_GET_BLOCK_HEADER, %rcx
    jne     7f
    cmpq    $API_ID_HEAD, ApiRoute_id_kind(%rax)    # headers: of head, or of the head's root
    je      60f
    cmpq    $API_ID_ROOT, ApiRoute_id_kind(%rax)
    jne     80f
    lea     ApiRoute_id_root(%rax), %rsi
    lea     Node_head_root(%rbx), %rdi
    NE32    %rsi, %rdi, 80f
60: lea     Node_head_root(%rbx), %rdi      # a work with the head's post-state and bytes
    call    node_find_block
    mov     %rdx, %r12
    mov     $500, %edx
    cmp     $-1, %rax
    je      80f
    mov     %rax, S8(%rsp)
    mov     NodeBlock_data_id(%r12), %rax
    test    %rax, %rax
    jnz     61f
    mov     %r12, %rdi
    call    node_api_db_ref
61: mov     %rax, %rcx
    mov     S7(%rsp), %rax                  # arg: the operation, the answer flags, the block's index
    mov     ApiRoute_op(%rax), %r9
    xor     %eax, %eax
    testq   $API_R_CLOSE, S10(%rsp)
    setnz   %al
    xor     %edx, %edx
    cmpq    $10, HttpRequest_version(%r13)
    sete    %dl
    lea     (%rax,%rdx,2), %rax
    shl     $8, %rax
    or      %rax, %r9
    mov     S8(%rsp), %rax
    shl     $16, %rax
    or      %rax, %r9
    mov     $NODE_WORK_API_ENCODE, %edi
    mov     NodeBlock_state_id(%r12), %rsi
    xor     %edx, %edx
    mov     S9(%rsp), %r8
    call    node_work
    jmp     90f
7:  mov     $501, %edx                      # another operation
80: mov     $API_BODY_ERROR, %ecx
81: mov     S9(%rsp), %rdi
    mov     S8(%rsp), %rsi
    mov     S10(%rsp), %r8
    call    node_api_send
90: mov     L(%rsp), %rax
    mov     %rax, (%r14)
    LEAVE 16
END_FUNCTION node_api_event

/*
 * The NODE_EV_WORK_DONE rdi of a NODE_WORK_API_ENCODE (node.md, lantern_node_step): its response
 * to the connection, or the error 500. rbx the node, r15 the actions. r12 the event, r13 the
 * action, S7 the flags.
 */
LOCAL_FUNCTION node_api_done
    ENTER 0
    mov     %rdi, %r12
    mov     NodeAction_arg(%r12), %rax
    shr     $8, %rax
    movzbl  %al, %eax
    mov     %rax, %rcx
    and     $API_ANSWER_CLOSE, %ecx         # API_R_CLOSE, or API_R_KEEP for HTTP/1.0 kept open
    jnz     1f
    test    $API_ANSWER_HTTP10, %al
    jz      1f
    mov     $API_R_KEEP, %ecx
1:  mov     %rcx, S7(%rsp)
    cmpq    $0, NodeEvent_result(%r12)
    jne     5f
    mov     (NodeEvent_chunk + 16)(%r12), %rsi  # the chunk's bytes in a SEND
    add     $(56 + 7), %rsi
    and     $~7, %rsi
    mov     $NODE_ACT_API_SEND, %edi
    call    node_act
    mov     %rax, %r13
    mov     NodeAction_target(%r12), %rax
    mov     %rax, 16(%r13)
    movq    $1, 24(%r13)
    mov     (%r13), %rax
    sub     $32, %rax
    mov     %rax, 32(%r13)
    movq    $24, 40(%r13)
    mov     (NodeEvent_chunk + 16)(%r12), %rdx
    mov     %rdx, 48(%r13)
    lea     56(%r13), %rdi
    mov     (NodeEvent_chunk + 8)(%r12), %rsi
    lea     NodeEvent_chunk(%r12,%rsi), %rsi
    call    lantern_copy
    mov     48(%r13), %rcx                  # zero bytes to the size
    lea     56(%r13,%rcx), %rdi
    mov     (%r13), %rsi
    sub     $56, %rsi
    sub     %rcx, %rsi
    call    lantern_zero
    testq   $API_R_CLOSE, S7(%rsp)
    jz      9f
    mov     $NODE_ACT_API_CLOSE, %edi
    mov     $NODE_ACT_API_CLOSE_SIZE, %esi
    call    node_act
    mov     NodeAction_target(%r12), %rcx
    mov     %rcx, 16(%rax)
    LEAVE 0
5:  mov     NodeAction_target(%r12), %rdi   # not valid: the error 500
    xor     %esi, %esi
    mov     $500, %edx
    mov     $API_BODY_ERROR, %ecx
    mov     S7(%rsp), %r8
    call    node_api_send
9:  LEAVE 0
END_FUNCTION node_api_done

/*
 * (node rdi, store rsi, work rdx, state_a rcx, data r8, scratch r9, event r10, room r11) -> rax:
 * a NODE_WORK_API_ENCODE of lantern_node_run (node.md): the response at NodeEvent_chunk of the
 * event, whose buffer has room bytes. rbx the node, rbp the store, r12 the work, r13 state_a, r14
 * the scratch, r15 the event, S7 data, S8 the ApiView at the end of scratch, S9 the block's entry,
 * S10 the room. Locals: L the scratch's size, L+8 a kept word.
 */
LOCAL_FUNCTION node_api_run
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, S7(%rsp)
    mov     %r9, %r14
    mov     %r10, %r15
    mov     %r11, S10(%rsp)
    mov     NodeAction_arg(%r12), %rax      # the block's entry
    shr     $16, %rax
    PART    %rcx, %rdx, %rbx, Node_blocks
    cmp     %rdx, %rax
    jae     8f
    test    %r13, %r13
    jz      8f
    imul    $NodeBlock__mem, %rax, %rax
    add     %rcx, %rax
    mov     %rax, S9(%rsp)
    mov     (%r14), %rax                    # the ApiView at the end of scratch
    mov     %rax, L(%rsp)
    sub     $ApiView__size, %rax
    jb      7f
    mov     %rax, (%r14)
    add     %r14, %rax
    mov     %rax, S8(%rsp)
    mov     %rax, %rdi
    call    node_api_view
    mov     S8(%rsp), %rdi                  # the block's root and slot
    mov     S9(%rsp), %rsi
    mov     NodeBlock_slot(%rsi), %rax
    mov     %rax, ApiView_head_slot(%rdi)
    lea     ApiView_head_root(%rdi), %rax
    COPY32  %rax, %rsi
    xor     %eax, %eax
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, NodeBlock_payload_status(%rsi)
    sete    %al
    mov     %rax, ApiView_is_optimistic(%rdi)
    movzbl  NodeAction_arg(%r12), %eax
    cmp     $API_OP_GET_STATE_FINALITY_CHECKPOINTS, %eax
    jne     2f
    mov     NODE_STATE_SLOT(%r13), %rdi     # finality_checkpoints: the state's
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    mov     S8(%rsp), %rsi
    add     $ApiView_previous_justified, %rsi
    FORK_CALL node_state_checkpoints
    jmp     5f
2:  cmp     $API_OP_GET_BLOCK_HEADER, %eax
    jne     6f
    mov     S7(%rsp), %rdi
    test    %rdi, %rdi
    jz      3f
    cmpq    $(100 + 84), 16(%rdi)           # header: of the bytes, at the fork of their slot
    jb      41f
    mov     8(%rdi), %rax
    add     %rdi, %rax
    mov     100(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     S8(%rsp), %rdx                  # the header's slot lands on the root's last 8 bytes: kept
    mov     (ApiView_proposer_index - 8)(%rdx), %rax
    mov     %rax, (L + 8)(%rsp)
    add     $(ApiView_proposer_index - 8), %rdx
    mov     S7(%rsp), %rdi
    mov     %r14, %rsi
    FORK_CALL node_block_header
    mov     S8(%rsp), %rdx
    mov     (L + 8)(%rsp), %rcx
    mov     %rcx, (ApiView_proposer_index - 8)(%rdx)
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jnz     41f
    jmp     5f
3:  mov     S8(%rsp), %rdi                  # no bytes: the state's latest_block_header, a zero signature
    add     $ApiView_proposer_index, %rdi
    lea     (NODE_STATE_HEADER + 8)(%r13), %rsi
    mov     $(112 - 8), %edx
    call    lantern_copy
    mov     S8(%rsp), %rdi
    mov     ApiView_state_root(%rdi), %rax
    or      (ApiView_state_root + 8)(%rdi), %rax
    or      (ApiView_state_root + 16)(%rdi), %rax
    or      (ApiView_state_root + 24)(%rdi), %rax
    jnz     5f
    mov     NODE_STATE_SLOT(%r13), %rdi     # a zero state_root: the state's root
    lea     Node_config(%rbx), %rsi
    call    node_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    mov     (Node_config + CONFIG_STATE_CACHE)(%rbx), %rsi
    mov     %r14, %rdx
    mov     S8(%rsp), %rcx
    add     $ApiView_state_root, %rcx
    FORK_CALL state_root
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jnz     41f
5:  mov     NodeAction_arg(%r12), %rax      # the response, in the event
    movzbl  %al, %ecx
    shr     $8, %rax
    movzbl  %al, %eax
    mov     %rax, %r8
    and     $API_ANSWER_CLOSE, %r8d
    jnz     51f
    test    $API_ANSWER_HTTP10, %al
    jz      51f
    mov     $API_R_KEEP, %r8d
51: mov     S10(%rsp), %rax
    sub     $NodeEvent_chunk, %rax
    and     $~7, %rax
    cmp     $24, %rax
    jb      71f
    mov     %rax, NodeEvent_chunk(%r15)
    mov     S8(%rsp), %rdi
    lea     NodeEvent_chunk(%r15), %rsi
    mov     $200, %edx
    call    api_respond
    test    %rax, %rax
    jnz     71f
    mov     (NodeEvent_chunk + 16)(%r15), %rax  # the event's size covers the chunk
    add     $(NodeEvent_chunk + 24 + 7), %rax
    and     $~7, %rax
    mov     %rax, (%r15)
    sub     $NodeEvent_chunk, %rax
    mov     %rax, NodeEvent_chunk(%r15)
    jmp     9f
41: movq    $LANTERN_INVALID_ENCODING, NodeEvent_result(%r15)
9:  mov     L(%rsp), %rax
    mov     %rax, (%r14)
    xor     %eax, %eax
    LEAVE 16
6:  mov     L(%rsp), %rax
    mov     %rax, (%r14)
8:  mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 16
71: mov     L(%rsp), %rax
    mov     %rax, (%r14)
7:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION node_api_run

    RODATA
    .p2align 3
node_api_rooms:                             # the room of each text of an ApiIdentity, then 0
    .quad 64, 512, 128, 128, 64, 0
