/*
 * The Beacon API answers, x86-64: in the common object. Requirements: docs/reference/beacon-api.md.
 *
 * The writer: r12 the cursor, r13 the pass (0 counts the bytes, 1 writes them), r14 the end of
 * the room, r15 1 when the room ran out. The functions below keep r12-r15 for it; rbx holds the
 * request's bytes and rbp the view.
 */

    RODATA
.include "api_text.inc"

.set API_HEALTH, 0                          # the routes
.set API_IDENTITY, 1
.set API_VERSION, 2
.set API_SYNCING, 3
.set API_PEER_COUNT, 4
.set API_GENESIS, 5
.set API_HEADERS, 6
.set API_FINALITY, 7
.set API_ERROR, 8                           # the code in the locals

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

/* The text field at rdi of the view (its length, then its bytes), in quotes. Locals: rdi. */
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

/* The body of the route rsi for the view rbp: the JSON of beacon-api.md, or an error body with the code rdi. Locals: the code, the route. */
LOCAL_FUNCTION api_body
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    cmp     $API_ERROR, %rsi
    jne     1f
    # {"code":<n>,"message":"<m>"}
    API_LIT api_e_code
    mov     (%rsp), %rdi
    call    api_dec
    API_LIT api_e_message
    mov     (%rsp), %rax
    cmp     $400, %rax
    jne     11f
    API_LIT api_m400
    jmp     12f
11: cmp     $405, %rax
    jne     13f
    API_LIT api_m405
    jmp     12f
13: API_LIT api_m404
12: API_LIT api_e_end
    UNFRAME 16
1:  cmp     $API_IDENTITY, %rsi
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
2:  cmp     $API_VERSION, %rsi
    jne     3f
    API_LIT api_v_version
    lea     ApiView_version(%rbp), %rdi
    call    api_text
    API_LIT api_end2
    UNFRAME 16
3:  cmp     $API_SYNCING, %rsi
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
4:  cmp     $API_PEER_COUNT, %rsi
    jne     5f
    API_LIT api_c_connected
    mov     ApiView_peers(%rbp), %rdi
    call    api_qdec
    API_LIT api_c_end
    UNFRAME 16
5:  cmp     $API_GENESIS, %rsi
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
6:  cmp     $API_HEADERS, %rsi
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
7:  cmp     $API_FINALITY, %rsi
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
 * rax = the length of the token at rdi of the request bytes rbx (visible bytes 0x21 to 0x7e)
 * when a space follows it before rsi, the end of the request line; else 0. Uses rcx, rdx.
 */
LOCAL_FUNCTION api_token_at
    UNWIND_END_PROLOGUE
    mov     %rdi, %rcx
1:  cmp     %rsi, %rcx
    jae     8f
    movzbl  (%rbx,%rcx), %edx
    lea     -0x21(%rdx), %eax
    cmp     $(0x7e - 0x21), %eax
    ja      2f
    inc     %rcx
    jmp     1b
2:  cmp     $0x20, %edx
    jne     8f
    mov     %rcx, %rax
    sub     %rdi, %rax
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION api_token_at

/* Compares through a call that takes lantern_api_answer's frame: see API_PATH_IS. */
LOCAL_FUNCTION api_path_is
    UNWIND_END_PROLOGUE
    mov     %rdi, %rdx
    mov     %rsi, %rcx
    mov     (L + 32 + 8)(%rsp), %rdi
    add     %rbx, %rdi
    mov     (L + 40 + 8)(%rsp), %rsi
    jmp     config_name_is
END_FUNCTION api_path_is

/*
 * (request, view, out): docs/reference/beacon-api.md. rbx the request's bytes, rbp view, r12-r15
 * the writer, S7 the route, S8 out, S9 the request's count. Locals: L the code, L+8 1 for a code
 * with no reason, L+16 the query's start, L+24 its length, L+32 the path's start, L+40 its length,
 * L+48 the body's length, L+56 the end of the request line, L+64 the method's length, L+72 the
 * target, L+80 the space after it.
 */
FUNCTION lantern_api_answer
    ENTER 96
    mov     8(%rdi), %rbx
    add     %rdi, %rbx
    mov     16(%rdi), %rax
    mov     %rax, S9(%rsp)
    mov     %rsi, %rbp
    mov     %rdx, S8(%rsp)
    xor     %ecx, %ecx                      # the end of the head: CR LF CR LF
1:  lea     4(%rcx), %rax
    cmp     S9(%rsp), %rax
    ja      90f
    cmpl    $0x0a0d0a0d, (%rbx,%rcx)
    je      2f
    inc     %rcx
    jmp     1b
2:  xor     %ecx, %ecx                      # the end of the request line
3:  cmpw    $0x0a0d, (%rbx,%rcx)
    je      4f
    inc     %rcx
    jmp     3b
4:  mov     %rcx, (L + 56)(%rsp)
    movq    $0, (L + 8)(%rsp)
    movq    $API_ERROR, S7(%rsp)
    movq    $400, L(%rsp)
    xor     %edi, %edi                      # the method: visible bytes, then a space
    mov     (L + 56)(%rsp), %rsi
    call    api_token_at
    test    %rax, %rax
    jz      50f
    mov     %rax, (L + 64)(%rsp)
    inc     %rax                            # the target
    mov     %rax, (L + 72)(%rsp)
    mov     %rax, %rdi
    mov     (L + 56)(%rsp), %rsi
    call    api_token_at
    test    %rax, %rax
    jz      50f
    add     (L + 72)(%rsp), %rax
    mov     %rax, (L + 80)(%rsp)            # the space after the target
    mov     (L + 56)(%rsp), %rcx            # then " HTTP/1." and a digit, to the end of the line
    sub     %rax, %rcx
    mov     $api_version_prefix_len, %edx
    inc     %rdx
    cmp     %rdx, %rcx
    jne     50f
    lea     (%rbx,%rax), %rdi
    mov     $api_version_prefix_len, %esi
    lea     api_version_prefix(%rip), %rdx
    mov     $api_version_prefix_len, %ecx
    call    config_name_is
    test    %rax, %rax
    jz      50f
    mov     (L + 80)(%rsp), %rax
    mov     $api_version_prefix_len, %ecx
    add     %rcx, %rax
    movzbl  (%rbx,%rax), %eax
    sub     $0x30, %eax
    cmp     $9, %eax
    ja      50f
    movq    $405, L(%rsp)                   # GET only
    mov     %rbx, %rdi
    mov     (L + 64)(%rsp), %rsi
    lea     api_get(%rip), %rdx
    mov     $api_get_len, %ecx
    call    config_name_is
    test    %rax, %rax
    jz      50f
    mov     (L + 72)(%rsp), %rcx            # the path and the query: split at the first ?
    mov     (L + 80)(%rsp), %rdx
    mov     %rcx, %rax
5:  cmp     %rdx, %rax
    jae     6f
    cmpb    $0x3f, (%rbx,%rax)
    je      6f
    inc     %rax
    jmp     5b
6:  mov     %rcx, (L + 32)(%rsp)
    mov     %rax, %rsi
    sub     %rcx, %rsi
    mov     %rsi, (L + 40)(%rsp)
    lea     1(%rax), %rcx
    mov     %rcx, (L + 16)(%rsp)
    sub     %rcx, %rdx
    jae     61f
    xor     %edx, %edx
61: mov     %rdx, (L + 24)(%rsp)
    movq    $404, L(%rsp)
    lea     api_p_health(%rip), %rdi
    mov     $api_p_health_len, %esi
    call    api_path_is
    test    %rax, %rax
    jnz     30f
    movq    $API_IDENTITY, S7(%rsp)
    lea     api_p_identity(%rip), %rdi
    mov     $api_p_identity_len, %esi
    call    api_path_is
    test    %rax, %rax
    jnz     49f
    movq    $API_VERSION, S7(%rsp)
    lea     api_p_version(%rip), %rdi
    mov     $api_p_version_len, %esi
    call    api_path_is
    test    %rax, %rax
    jnz     49f
    movq    $API_SYNCING, S7(%rsp)
    lea     api_p_syncing(%rip), %rdi
    mov     $api_p_syncing_len, %esi
    call    api_path_is
    test    %rax, %rax
    jnz     49f
    movq    $API_PEER_COUNT, S7(%rsp)
    lea     api_p_peer_count(%rip), %rdi
    mov     $api_p_peer_count_len, %esi
    call    api_path_is
    test    %rax, %rax
    jnz     49f
    movq    $API_GENESIS, S7(%rsp)
    lea     api_p_genesis(%rip), %rdi
    mov     $api_p_genesis_len, %esi
    call    api_path_is
    test    %rax, %rax
    jnz     49f
    movq    $API_FINALITY, S7(%rsp)
    lea     api_p_finality(%rip), %rdi
    mov     $api_p_finality_len, %esi
    call    api_path_is
    test    %rax, %rax
    jnz     49f
    movq    $API_ERROR, S7(%rsp)            # the headers of the head: head, or its root in hex
    mov     $api_p_headers_len, %eax
    cmp     %rax, (L + 40)(%rsp)
    jb      50f
    mov     (L + 32)(%rsp), %rdi
    add     %rbx, %rdi
    mov     $api_p_headers_len, %esi
    lea     api_p_headers(%rip), %rdx
    mov     $api_p_headers_len, %ecx
    call    config_name_is
    test    %rax, %rax
    jz      50f
    mov     $api_p_headers_len, %eax
    mov     (L + 32)(%rsp), %rdi
    add     %rax, %rdi
    add     %rbx, %rdi
    mov     (L + 40)(%rsp), %rsi
    sub     %rax, %rsi
    lea     api_head(%rip), %rdx
    mov     $api_head_len, %ecx
    call    config_name_is
    test    %rax, %rax
    jnz     7f
    mov     $api_p_headers_len, %eax        # 0x and 64 lower case hex digits of head_root
    mov     (L + 40)(%rsp), %rcx
    sub     %rax, %rcx
    cmp     $66, %rcx
    jne     50f
    mov     (L + 32)(%rsp), %rdi
    add     %rax, %rdi
    add     %rbx, %rdi
    cmpw    $0x7830, (%rdi)                 # 0x
    jne     50f
    add     $2, %rdi
    lea     api_hex(%rip), %r8
    xor     %ecx, %ecx
8:  cmp     $32, %ecx
    jae     7f
    movzbl  ApiView_head_root(%rbp,%rcx), %eax
    mov     %eax, %edx
    shr     $4, %edx
    movzbl  (%r8,%rdx), %edx
    cmp     (%rdi), %dl
    jne     50f
    and     $15, %eax
    movzbl  (%r8,%rax), %eax
    cmp     1(%rdi), %al
    jne     50f
    add     $2, %rdi
    inc     %ecx
    jmp     8b
7:  movq    $API_HEADERS, S7(%rsp)
    jmp     49f
30: movq    $API_HEALTH, S7(%rsp)           # health: 200, or 206 or syncing_status while not ready
    xor     %r8d, %r8d                      # the query's code, or 0
    cmpq    $0, (L + 24)(%rsp)
    je      32f
    movq    $API_ERROR, S7(%rsp)
    movq    $400, L(%rsp)
    mov     $api_q_status_len, %eax
    inc     %rax
    cmp     %rax, (L + 24)(%rsp)
    jb      50f
    mov     (L + 16)(%rsp), %rdi
    add     %rbx, %rdi
    mov     $api_q_status_len, %esi
    lea     api_q_status(%rip), %rdx
    mov     $api_q_status_len, %ecx
    call    config_name_is
    test    %rax, %rax
    jz      50f
    mov     (L + 16)(%rsp), %rdi
    add     %rbx, %rdi
    mov     (L + 24)(%rsp), %rsi
    add     %rdi, %rsi
    mov     $api_q_status_len, %eax
    add     %rax, %rdi
    call    app_decimal
    test    %rax, %rax
    jnz     50f
    cmp     $100, %rdx
    jb      50f
    cmp     $599, %rdx
    ja      50f
    mov     %rdx, %r8
    movq    $API_HEALTH, S7(%rsp)
32: mov     $200, %eax
    mov     ApiView_is_syncing(%rbp), %rcx
    or      ApiView_is_optimistic(%rbp), %rcx
    or      ApiView_el_offline(%rbp), %rcx
    jz      33f
    mov     $206, %eax
    test    %r8, %r8
    jz      33f
    mov     %r8, %rax
    movq    $1, (L + 8)(%rsp)
33: mov     %rax, L(%rsp)
    jmp     50f
49: movq    $200, L(%rsp)
50: xor     %r13d, %r13d                    # the body's length
    xor     %r12d, %r12d
    xor     %r15d, %r15d
    cmpq    $API_HEALTH, S7(%rsp)
    je      51f
    mov     L(%rsp), %rdi
    mov     S7(%rsp), %rsi
    call    api_body
51: mov     %r12, (L + 48)(%rsp)
    mov     $1, %r13d                       # the response
    mov     S8(%rsp), %rax
    lea     24(%rax), %r12
    mov     %rax, %r14
    add     (%rax), %r14
    API_LIT api_http
    mov     L(%rsp), %rdi
    call    api_dec
    cmpq    $0, (L + 8)(%rsp)
    je      52f
    API_LIT api_rnone
    jmp     59f
52: mov     L(%rsp), %rax
    cmp     $200, %rax
    jne     53f
    API_LIT api_r200
    jmp     59f
53: cmp     $206, %rax
    jne     54f
    API_LIT api_r206
    jmp     59f
54: cmp     $400, %rax
    jne     55f
    API_LIT api_r400
    jmp     59f
55: cmp     $405, %rax
    jne     56f
    API_LIT api_r405
    jmp     59f
56: API_LIT api_r404
59: cmpq    $0, (L + 48)(%rsp)
    je      60f
    API_LIT api_type
60: API_LIT api_length
    mov     (L + 48)(%rsp), %rdi
    call    api_dec
    API_LIT api_close
    cmpq    $API_HEALTH, S7(%rsp)
    je      61f
    mov     L(%rsp), %rdi
    mov     S7(%rsp), %rsi
    call    api_body
61: test    %r15, %r15
    jnz     91f
    mov     S8(%rsp), %rax
    movq    $24, 8(%rax)
    lea     24(%rax), %rcx
    mov     %r12, %rdx
    sub     %rcx, %rdx
    mov     %rdx, 16(%rax)
    xor     %eax, %eax
    LEAVE 96
90: mov     $LANTERN_HTTP_MORE, %eax
    LEAVE 96
91: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 96
END_FUNCTION lantern_api_answer
