/*
 * The Beacon API answers, RISC-V: in the common object. Requirements: docs/reference/beacon-api.md.
 *
 * The writer: s3 the cursor, s4 the pass (0 counts the bytes, 1 writes them), s5 the end of the
 * room, s6 1 when the room ran out. The functions below keep s3-s6 for it; s1 holds the request's
 * bytes and s2 the view.
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
    ADDRESS a0, \label
    li      a1, \label\()_len
    call    api_put
.endm

/* The a1 bytes at a0 join the response; the first pass only counts them. Uses t0, t1, a0, a1. */
LOCAL_FUNCTION api_put
    UNWIND_END_PROLOGUE
    beqz    s4, 2f
    add     t0, s3, a1
    bgtu    t0, s5, 3f
1:  beqz    a1, 9f
    lbu     t1, 0(a0)
    sb      t1, 0(s3)
    addi    a0, a0, 1
    addi    s3, s3, 1
    addi    a1, a1, -1
    j       1b
2:  add     s3, s3, a1
9:  ret
3:  li      s6, 1
    ret
END_FUNCTION api_put

/* The decimal digits of a0 join the response. Locals: the digits, from the end. */
LOCAL_FUNCTION api_dec
    FRAME 32
    addi    t2, sp, 32
    li      t3, 10
1:  remu    t4, a0, t3
    divu    a0, a0, t3
    addi    t4, t4, 0x30
    addi    t2, t2, -1
    sb      t4, 0(t2)
    bnez    a0, 1b
    mv      a0, t2
    addi    a1, sp, 32
    sub     a1, a1, t2
    call    api_put
    UNFRAME 32
END_FUNCTION api_dec

/* The decimal digits of a0, in quotes. Locals: a0. */
LOCAL_FUNCTION api_qdec
    FRAME 16
    sd      a0, 0(sp)
    API_LIT api_quote
    ld      a0, 0(sp)
    call    api_dec
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION api_qdec

/* "0x" and the lower case hex of the a1 bytes at a0, in quotes. Locals: a0, a1, then 2 digits. */
LOCAL_FUNCTION api_qhex
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    API_LIT api_quote
    API_LIT api_0x
1:  ld      a1, 8(sp)
    beqz    a1, 2f
    ld      a0, 0(sp)
    lbu     t2, 0(a0)
    addi    a0, a0, 1
    addi    a1, a1, -1
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    ADDRESS t3, api_hex
    srli    t4, t2, 4
    add     t4, t3, t4
    lbu     t4, 0(t4)
    sb      t4, 16(sp)
    andi    t4, t2, 15
    add     t4, t3, t4
    lbu     t4, 0(t4)
    sb      t4, 17(sp)
    addi    a0, sp, 16
    li      a1, 2
    call    api_put
    j       1b
2:  API_LIT api_quote
    UNFRAME 32
END_FUNCTION api_qhex

/* The text field at a0 of the view (its length, then its bytes), in quotes. Locals: a0. */
LOCAL_FUNCTION api_text
    FRAME 16
    sd      a0, 0(sp)
    API_LIT api_quote
    ld      t2, 0(sp)
    ld      a1, 0(t2)
    addi    a0, t2, 8
    call    api_put
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION api_text

/* true when a0 is not 0, else false. */
LOCAL_FUNCTION api_bool
    FRAME 0
    beqz    a0, 1f
    API_LIT api_true
    UNFRAME 0
1:  API_LIT api_false
    UNFRAME 0
END_FUNCTION api_bool

/* A Checkpoint of the view at a0: {"epoch":…,"root":…}. Locals: a0. */
LOCAL_FUNCTION api_checkpoint
    FRAME 16
    sd      a0, 0(sp)
    API_LIT api_f_epoch
    ld      t2, 0(sp)
    ld      a0, 0(t2)
    call    api_qdec
    API_LIT api_f_root
    ld      a0, 0(sp)
    addi    a0, a0, 8
    li      a1, 32
    call    api_qhex
    API_LIT api_end1
    UNFRAME 16
END_FUNCTION api_checkpoint

/* The body of the route s7 for the view s2: the JSON of beacon-api.md, or an error body with the code a0. Locals: the code. */
LOCAL_FUNCTION api_body
    FRAME 16
    sd      a0, 0(sp)
    li      t2, API_ERROR
    bne     s7, t2, 1f
    # {"code":<n>,"message":"<m>"}
    API_LIT api_e_code
    ld      a0, 0(sp)
    call    api_dec
    API_LIT api_e_message
    ld      t2, 0(sp)
    li      t3, 400
    bne     t2, t3, 11f
    API_LIT api_m400
    j       12f
11: li      t3, 405
    bne     t2, t3, 13f
    API_LIT api_m405
    j       12f
13: API_LIT api_m404
12: API_LIT api_e_end
    UNFRAME 16
1:  li      t2, API_IDENTITY
    bne     s7, t2, 2f
    API_LIT api_i_peer_id
    addi    a0, s2, ApiView_peer_id
    call    api_text
    API_LIT api_i_enr
    addi    a0, s2, ApiView_enr
    call    api_text
    API_LIT api_i_p2p
    ld      t2, ApiView_p2p_address(s2)
    beqz    t2, 14f
    addi    a0, s2, ApiView_p2p_address
    call    api_text
14: API_LIT api_i_discovery
    ld      t2, ApiView_discovery_address(s2)
    beqz    t2, 15f
    addi    a0, s2, ApiView_discovery_address
    call    api_text
15: API_LIT api_i_seq
    ld      a0, ApiView_seq_number(s2)
    call    api_qdec
    API_LIT api_i_attnets
    addi    a0, s2, ApiView_attnets
    li      a1, 8
    call    api_qhex
    ld      t2, ApiView_fork(s2)
    li      t3, FORK_ALTAIR
    bltu    t2, t3, 16f
    API_LIT api_i_syncnets
    addi    a0, s2, ApiView_syncnets
    li      a1, 1
    call    api_qhex
    ld      t2, ApiView_fork(s2)
    li      t3, FORK_FULU
    bltu    t2, t3, 16f
    API_LIT api_i_cgc
    ld      a0, ApiView_custody_group_count(s2)
    call    api_qdec
16: API_LIT api_end3
    UNFRAME 16
2:  li      t2, API_VERSION
    bne     s7, t2, 3f
    API_LIT api_v_version
    li      t2, ApiView_version
    add     a0, s2, t2
    call    api_text
    API_LIT api_end2
    UNFRAME 16
3:  li      t2, API_SYNCING
    bne     s7, t2, 4f
    API_LIT api_s_head
    ld      a0, ApiView_head_slot(s2)
    call    api_qdec
    API_LIT api_s_distance
    ld      t2, ApiView_current_slot(s2)
    ld      t3, ApiView_head_slot(s2)
    li      a0, 0
    bltu    t2, t3, 31f
    sub     a0, t2, t3
31: call    api_qdec
    API_LIT api_s_syncing
    ld      a0, ApiView_is_syncing(s2)
    call    api_bool
    API_LIT api_s_optimistic
    ld      a0, ApiView_is_optimistic(s2)
    call    api_bool
    API_LIT api_s_offline
    ld      a0, ApiView_el_offline(s2)
    call    api_bool
    API_LIT api_end2
    UNFRAME 16
4:  li      t2, API_PEER_COUNT
    bne     s7, t2, 5f
    API_LIT api_c_connected
    ld      a0, ApiView_peers(s2)
    call    api_qdec
    API_LIT api_c_end
    UNFRAME 16
5:  li      t2, API_GENESIS
    bne     s7, t2, 6f
    API_LIT api_g_time
    ld      a0, ApiView_genesis_time(s2)
    call    api_qdec
    API_LIT api_g_root
    addi    a0, s2, ApiView_genesis_validators_root
    li      a1, 32
    call    api_qhex
    API_LIT api_g_version
    addi    a0, s2, ApiView_genesis_fork_version
    li      a1, 4
    call    api_qhex
    API_LIT api_end2
    UNFRAME 16
6:  li      t2, API_HEADERS
    bne     s7, t2, 7f
    API_LIT api_x_optimistic
    ld      a0, ApiView_is_optimistic(s2)
    call    api_bool
    API_LIT api_x_finalized
    API_LIT api_h_root
    addi    a0, s2, ApiView_head_root
    li      a1, 32
    call    api_qhex
    API_LIT api_h_slot
    ld      a0, ApiView_head_slot(s2)
    call    api_qdec
    API_LIT api_h_proposer
    ld      a0, ApiView_proposer_index(s2)
    call    api_qdec
    API_LIT api_h_parent
    addi    a0, s2, ApiView_parent_root
    li      a1, 32
    call    api_qhex
    API_LIT api_h_state
    addi    a0, s2, ApiView_state_root
    li      a1, 32
    call    api_qhex
    API_LIT api_h_body
    addi    a0, s2, ApiView_body_root
    li      a1, 32
    call    api_qhex
    API_LIT api_h_signature
    addi    a0, s2, ApiView_signature
    li      a1, 96
    call    api_qhex
    API_LIT api_end3
    UNFRAME 16
7:  li      t2, API_FINALITY
    bne     s7, t2, 9f
    API_LIT api_x_optimistic
    ld      a0, ApiView_is_optimistic(s2)
    call    api_bool
    API_LIT api_x_finalized
    API_LIT api_f_previous
    addi    a0, s2, ApiView_previous_justified
    call    api_checkpoint
    API_LIT api_f_current
    addi    a0, s2, ApiView_current_justified
    call    api_checkpoint
    API_LIT api_f_finalized
    addi    a0, s2, ApiView_finalized
    call    api_checkpoint
    API_LIT api_end2
9:  UNFRAME 16
END_FUNCTION api_body

/*
 * a0 = the length of the token at a0 of the request bytes s1 (visible bytes 0x21 to 0x7e) when a
 * space follows it before a1, the end of the request line; else 0. Uses t0-t2.
 */
LOCAL_FUNCTION api_token_at
    UNWIND_END_PROLOGUE
    mv      t0, a0
1:  bgeu    t0, a1, 8f
    add     t1, s1, t0
    lbu     t1, 0(t1)
    addi    t2, t1, -0x21
    li      a2, 0x7e - 0x21
    bgtu    t2, a2, 2f
    addi    t0, t0, 1
    j       1b
2:  li      t2, 0x20
    bne     t1, t2, 8f
    sub     a0, t0, a0
    ret
8:  li      a0, 0
    ret
END_FUNCTION api_token_at

/* a0 = 1 when the path (s1 + [L + 32], [L + 40] bytes, of lantern_api_answer's frame) is the a1 bytes at a0. */
LOCAL_FUNCTION api_path_is
    UNWIND_END_PROLOGUE
    mv      a2, a0
    mv      a3, a1
    ld      a0, (L + 32)(sp)
    add     a0, s1, a0
    ld      a1, (L + 40)(sp)
    j       config_name_is
END_FUNCTION api_path_is

/*
 * (request, view, out): docs/reference/beacon-api.md. s1 the request's bytes, s2 view, s3-s6 the
 * writer, s7 the route, s8 out, s9 the request's count. Locals: L the code, L+8 1 for a code with
 * no reason, L+16 the query's start, L+24 its length, L+32 the path's start, L+40 its length, L+48
 * the body's length, L+56 the end of the request line, L+64 the method's length, L+72 the target,
 * L+80 the space after it.
 */
FUNCTION lantern_api_answer
    ENTER 96
    ld      t0, 8(a0)
    add     s1, a0, t0
    ld      s9, 16(a0)
    mv      s2, a1
    mv      s8, a2
    li      t0, 0                           # the end of the head: CR LF CR LF
    li      t3, 0x0a0d0a0d
1:  addi    t1, t0, 4
    bgtu    t1, s9, 90f
    add     t2, s1, t0
    lbu     t4, 0(t2)
    lbu     t5, 1(t2)
    slli    t5, t5, 8
    or      t4, t4, t5
    lbu     t5, 2(t2)
    slli    t5, t5, 16
    or      t4, t4, t5
    lbu     t5, 3(t2)
    slli    t5, t5, 24
    or      t4, t4, t5
    beq     t4, t3, 2f
    addi    t0, t0, 1
    j       1b
2:  li      t0, 0                           # the end of the request line
    li      t3, 0x0d
3:  add     t2, s1, t0
    lbu     t4, 0(t2)
    bne     t4, t3, 31f
    lbu     t4, 1(t2)
    li      t5, 0x0a
    beq     t4, t5, 4f
31: addi    t0, t0, 1
    j       3b
4:  sd      t0, (L + 56)(sp)
    sd      zero, (L + 8)(sp)
    li      s7, API_ERROR
    li      t0, 400
    sd      t0, L(sp)
    li      a0, 0                           # the method: visible bytes, then a space
    ld      a1, (L + 56)(sp)
    call    api_token_at
    beqz    a0, 50f
    sd      a0, (L + 64)(sp)
    addi    a0, a0, 1                       # the target
    sd      a0, (L + 72)(sp)
    ld      a1, (L + 56)(sp)
    call    api_token_at
    beqz    a0, 50f
    ld      t0, (L + 72)(sp)
    add     t0, t0, a0
    sd      t0, (L + 80)(sp)                # the space after the target
    ld      t1, (L + 56)(sp)                # then " HTTP/1." and a digit, to the end of the line
    sub     t1, t1, t0
    li      t2, api_version_prefix_len + 1
    bne     t1, t2, 50f
    add     a0, s1, t0
    li      a1, api_version_prefix_len
    ADDRESS a2, api_version_prefix
    li      a3, api_version_prefix_len
    call    config_name_is
    beqz    a0, 50f
    ld      t0, (L + 80)(sp)
    addi    t0, t0, api_version_prefix_len
    add     t0, s1, t0
    lbu     t1, 0(t0)
    addi    t1, t1, -0x30
    li      t2, 9
    bgtu    t1, t2, 50f
    li      t0, 405                         # GET only
    sd      t0, L(sp)
    mv      a0, s1
    ld      a1, (L + 64)(sp)
    ADDRESS a2, api_get
    li      a3, api_get_len
    call    config_name_is
    beqz    a0, 50f
    ld      t1, (L + 72)(sp)                # the path and the query: split at the first ?
    ld      t2, (L + 80)(sp)
    mv      t0, t1
    li      t3, 0x3f
5:  bgeu    t0, t2, 6f
    add     t4, s1, t0
    lbu     t4, 0(t4)
    beq     t4, t3, 6f
    addi    t0, t0, 1
    j       5b
6:  sd      t1, (L + 32)(sp)
    sub     t4, t0, t1
    sd      t4, (L + 40)(sp)
    addi    t5, t0, 1
    sd      t5, (L + 16)(sp)
    li      t6, 0
    bltu    t2, t5, 61f
    sub     t6, t2, t5
61: sd      t6, (L + 24)(sp)
    li      t0, 404
    sd      t0, L(sp)
    ADDRESS a0, api_p_health
    li      a1, api_p_health_len
    call    api_path_is
    bnez    a0, 30f
    li      s7, API_IDENTITY
    ADDRESS a0, api_p_identity
    li      a1, api_p_identity_len
    call    api_path_is
    bnez    a0, 49f
    li      s7, API_VERSION
    ADDRESS a0, api_p_version
    li      a1, api_p_version_len
    call    api_path_is
    bnez    a0, 49f
    li      s7, API_SYNCING
    ADDRESS a0, api_p_syncing
    li      a1, api_p_syncing_len
    call    api_path_is
    bnez    a0, 49f
    li      s7, API_PEER_COUNT
    ADDRESS a0, api_p_peer_count
    li      a1, api_p_peer_count_len
    call    api_path_is
    bnez    a0, 49f
    li      s7, API_GENESIS
    ADDRESS a0, api_p_genesis
    li      a1, api_p_genesis_len
    call    api_path_is
    bnez    a0, 49f
    li      s7, API_FINALITY
    ADDRESS a0, api_p_finality
    li      a1, api_p_finality_len
    call    api_path_is
    bnez    a0, 49f
    li      s7, API_ERROR                   # the headers of the head: head, or its root in hex
    ld      t0, (L + 40)(sp)
    li      t1, api_p_headers_len
    bltu    t0, t1, 50f
    ld      a0, (L + 32)(sp)
    add     a0, s1, a0
    li      a1, api_p_headers_len
    ADDRESS a2, api_p_headers
    li      a3, api_p_headers_len
    call    config_name_is
    beqz    a0, 50f
    ld      a0, (L + 32)(sp)
    addi    a0, a0, api_p_headers_len
    add     a0, s1, a0
    ld      a1, (L + 40)(sp)
    addi    a1, a1, -api_p_headers_len
    ADDRESS a2, api_head
    li      a3, api_head_len
    call    config_name_is
    bnez    a0, 7f
    ld      t0, (L + 40)(sp)                # 0x and 64 lower case hex digits of head_root
    addi    t0, t0, -api_p_headers_len
    li      t1, 66
    bne     t0, t1, 50f
    ld      t0, (L + 32)(sp)
    addi    t0, t0, api_p_headers_len
    add     t0, s1, t0
    lbu     t1, 0(t0)
    li      t2, 0x30
    bne     t1, t2, 50f
    lbu     t1, 1(t0)
    li      t2, 0x78
    bne     t1, t2, 50f
    addi    t0, t0, 2
    ADDRESS t6, api_hex
    li      t1, 0
8:  li      t2, 32
    bgeu    t1, t2, 7f
    add     t2, s2, t1
    lbu     t2, ApiView_head_root(t2)
    srli    t3, t2, 4
    add     t3, t6, t3
    lbu     t3, 0(t3)
    lbu     t4, 0(t0)
    bne     t3, t4, 50f
    andi    t3, t2, 15
    add     t3, t6, t3
    lbu     t3, 0(t3)
    lbu     t4, 1(t0)
    bne     t3, t4, 50f
    addi    t0, t0, 2
    addi    t1, t1, 1
    j       8b
7:  li      s7, API_HEADERS
    j       49f
30: li      s7, API_HEALTH                  # health: 200, or 206 or syncing_status while not ready
    li      s10, 0                          # the query's code, or 0
    ld      t0, (L + 24)(sp)
    beqz    t0, 32f
    li      s7, API_ERROR
    li      t1, 400
    sd      t1, L(sp)
    li      t1, api_q_status_len + 1
    bltu    t0, t1, 50f
    ld      a0, (L + 16)(sp)
    add     a0, s1, a0
    li      a1, api_q_status_len
    ADDRESS a2, api_q_status
    li      a3, api_q_status_len
    call    config_name_is
    beqz    a0, 50f
    ld      t0, (L + 16)(sp)
    add     a0, s1, t0
    ld      t1, (L + 24)(sp)
    add     a1, a0, t1
    addi    a0, a0, api_q_status_len
    call    app_decimal
    bnez    a0, 50f
    li      t0, 100
    bltu    a1, t0, 50f
    li      t0, 599
    bgtu    a1, t0, 50f
    mv      s10, a1
    li      s7, API_HEALTH
32: li      t0, 200
    ld      t1, ApiView_is_syncing(s2)
    ld      t2, ApiView_is_optimistic(s2)
    or      t1, t1, t2
    ld      t2, ApiView_el_offline(s2)
    or      t1, t1, t2
    beqz    t1, 33f
    li      t0, 206
    beqz    s10, 33f
    mv      t0, s10
    li      t1, 1
    sd      t1, (L + 8)(sp)
33: sd      t0, L(sp)
    j       50f
49: li      t0, 200
    sd      t0, L(sp)
50: li      s4, 0                           # the body's length
    li      s3, 0
    li      s6, 0
    li      t0, API_HEALTH
    beq     s7, t0, 51f
    ld      a0, L(sp)
    call    api_body
51: sd      s3, (L + 48)(sp)
    li      s4, 1                           # the response
    addi    s3, s8, 24
    ld      t0, 0(s8)
    add     s5, s8, t0
    API_LIT api_http
    ld      a0, L(sp)
    call    api_dec
    ld      t0, (L + 8)(sp)
    beqz    t0, 52f
    API_LIT api_rnone
    j       59f
52: ld      t0, L(sp)
    li      t1, 200
    bne     t0, t1, 53f
    API_LIT api_r200
    j       59f
53: li      t1, 206
    bne     t0, t1, 54f
    API_LIT api_r206
    j       59f
54: li      t1, 400
    bne     t0, t1, 55f
    API_LIT api_r400
    j       59f
55: li      t1, 405
    bne     t0, t1, 56f
    API_LIT api_r405
    j       59f
56: API_LIT api_r404
59: ld      t0, (L + 48)(sp)
    beqz    t0, 60f
    API_LIT api_type
60: API_LIT api_length
    ld      a0, (L + 48)(sp)
    call    api_dec
    API_LIT api_close
    li      t0, API_HEALTH
    beq     s7, t0, 61f
    ld      a0, L(sp)
    call    api_body
61: bnez    s6, 91f
    li      t0, 24
    sd      t0, 8(s8)
    addi    t1, s8, 24
    sub     t1, s3, t1
    sd      t1, 16(s8)
    li      a0, LANTERN_OK
    LEAVE 96
90: li      a0, LANTERN_HTTP_MORE
    LEAVE 96
91: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 96
END_FUNCTION lantern_api_answer
