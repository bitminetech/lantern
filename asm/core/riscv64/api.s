/*
 * The Beacon API answers of the node, RISC-V: in the common object. Requirements:
 * docs/reference/beacon-api.md (Common rules) and docs/reference/node.md (NODE_EV_API).
 *
 * The writer: s6 the cursor, s7 the pass (0 counts the bytes, 1 writes them), s8 the end of the
 * room, s9 1 when the room ran out, s4 the ApiView, s10 the body kind. The writer's functions
 * keep s4 and s6-s10 for it; only api_respond calls them.
 */

    RODATA
.include "api_text.inc"

/* The text at label joins the response. */
.macro API_LIT label
    ADDRESS a0, \label
    li      a1, \label\()_len
    call    api_put
.endm

/* The a1 bytes at a0 join the response; the first pass only counts them. Uses t0, t1, a0, a1. */
LOCAL_FUNCTION api_put
    UNWIND_END_PROLOGUE
    beqz    s7, 2f
    add     t0, s6, a1
    bgtu    t0, s8, 3f
1:  beqz    a1, 9f
    lbu     t1, 0(a0)
    sb      t1, 0(s6)
    addi    a0, a0, 1
    addi    s6, s6, 1
    addi    a1, a1, -1
    j       1b
2:  add     s6, s6, a1
9:  ret
3:  li      s9, 1
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

/* The text at a0 (its length, then its bytes), in quotes. Locals: a0. */
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

/* a0 = the api_codes entry of the status a0, or 0. Uses t0-t2. */
LOCAL_FUNCTION api_code
    UNWIND_END_PROLOGUE
    ADDRESS t0, api_codes
    ADDRESS t1, api_codes_end
1:  bgeu    t0, t1, 2f
    ld      t2, 0(t0)
    beq     t2, a0, 3f
    addi    t0, t0, API_CODE_ENTRY
    j       1b
2:  li      a0, 0
    ret
3:  mv      a0, t0
    ret
END_FUNCTION api_code

/* The text of the api_codes entry a0 at its byte a1 (8 the reason, 24 the message), or none for no entry. */
LOCAL_FUNCTION api_code_text
    FRAME 0
    beqz    a0, 9f
    add     t0, a0, a1
    ld      t1, 0(t0)
    ld      a1, 8(t0)
    ADDRESS a0, api_texts
    add     a0, a0, t1
    call    api_put
9:  UNFRAME 0
END_FUNCTION api_code_text

/*
 * The body of the kind s10 for the view s4: an error body of the status at (a0), or the JSON of
 * an operation (beacon-api.md, Common rules). Locals: a0.
 */
LOCAL_FUNCTION api_body
    FRAME 16
    sd      a0, 0(sp)
    li      t0, API_BODY_ERROR
    bne     s10, t0, 1f
    # {"code":<n>,"message":"<m>"}
    API_LIT api_e_code
    ld      t0, 0(sp)
    ld      a0, 0(t0)
    call    api_dec
    API_LIT api_e_message
    ld      t0, 0(sp)
    ld      a0, 0(t0)
    call    api_code
    li      a1, 24
    call    api_code_text
    API_LIT api_e_end
    UNFRAME 16
1:  li      t0, API_OP_GET_NETWORK_IDENTITY
    bne     s10, t0, 2f
    API_LIT api_i_peer_id
    addi    a0, s4, ApiView_peer_id
    call    api_text
    API_LIT api_i_enr
    addi    a0, s4, ApiView_enr
    call    api_text
    API_LIT api_i_p2p
    ld      t0, ApiView_p2p_address(s4)
    beqz    t0, 14f
    addi    a0, s4, ApiView_p2p_address
    call    api_text
14: API_LIT api_i_discovery
    ld      t0, ApiView_discovery_address(s4)
    beqz    t0, 15f
    addi    a0, s4, ApiView_discovery_address
    call    api_text
15: API_LIT api_i_seq
    ld      a0, ApiView_seq_number(s4)
    call    api_qdec
    API_LIT api_i_attnets
    addi    a0, s4, ApiView_attnets
    li      a1, 8
    call    api_qhex
    ld      t0, ApiView_fork(s4)
    li      t1, FORK_ALTAIR
    bltu    t0, t1, 16f
    API_LIT api_i_syncnets
    addi    a0, s4, ApiView_syncnets
    li      a1, 1
    call    api_qhex
    ld      t0, ApiView_fork(s4)
    li      t1, FORK_FULU
    bltu    t0, t1, 16f
    API_LIT api_i_cgc
    ld      a0, ApiView_custody_group_count(s4)
    call    api_qdec
16: API_LIT api_end3
    UNFRAME 16
2:  li      t0, API_OP_GET_NODE_VERSION
    bne     s10, t0, 3f
    API_LIT api_v_version
    addi    a0, s4, ApiView_version
    call    api_text
    API_LIT api_end2
    UNFRAME 16
3:  li      t0, API_OP_GET_SYNCING_STATUS
    bne     s10, t0, 4f
    API_LIT api_s_head
    ld      a0, ApiView_head_slot(s4)
    call    api_qdec
    API_LIT api_s_distance
    ld      t0, ApiView_current_slot(s4)
    ld      t1, ApiView_head_slot(s4)
    li      a0, 0
    bltu    t0, t1, 31f
    sub     a0, t0, t1
31: call    api_qdec
    API_LIT api_s_syncing
    ld      a0, ApiView_is_syncing(s4)
    call    api_bool
    API_LIT api_s_optimistic
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_s_offline
    ld      a0, ApiView_el_offline(s4)
    call    api_bool
    API_LIT api_end2
    UNFRAME 16
4:  li      t0, API_OP_GET_PEER_COUNT
    bne     s10, t0, 5f
    API_LIT api_c_connected
    ld      a0, ApiView_peers(s4)
    call    api_qdec
    API_LIT api_c_end
    UNFRAME 16
5:  li      t0, API_OP_GET_GENESIS
    bne     s10, t0, 6f
    API_LIT api_g_time
    ld      a0, ApiView_genesis_time(s4)
    call    api_qdec
    API_LIT api_g_root
    addi    a0, s4, ApiView_genesis_validators_root
    li      a1, 32
    call    api_qhex
    API_LIT api_g_version
    addi    a0, s4, ApiView_genesis_fork_version
    li      a1, 4
    call    api_qhex
    API_LIT api_end2
    UNFRAME 16
6:  li      t0, API_OP_GET_BLOCK_HEADER
    bne     s10, t0, 7f
    API_LIT api_x_optimistic
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_x_finalized
    API_LIT api_h_root
    addi    a0, s4, ApiView_head_root
    li      a1, 32
    call    api_qhex
    API_LIT api_h_slot
    ld      a0, ApiView_head_slot(s4)
    call    api_qdec
    API_LIT api_h_proposer
    ld      a0, ApiView_proposer_index(s4)
    call    api_qdec
    API_LIT api_h_parent
    addi    a0, s4, ApiView_parent_root
    li      a1, 32
    call    api_qhex
    API_LIT api_h_state
    addi    a0, s4, ApiView_state_root
    li      a1, 32
    call    api_qhex
    API_LIT api_h_body
    addi    a0, s4, ApiView_body_root
    li      a1, 32
    call    api_qhex
    API_LIT api_h_signature
    addi    a0, s4, ApiView_signature
    li      a1, 96
    call    api_qhex
    API_LIT api_end3
    UNFRAME 16
7:  li      t0, API_OP_GET_STATE_FINALITY_CHECKPOINTS
    bne     s10, t0, 9f
    API_LIT api_x_optimistic
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_x_finalized
    API_LIT api_f_previous
    addi    a0, s4, ApiView_previous_justified
    call    api_checkpoint
    API_LIT api_f_current
    addi    a0, s4, ApiView_current_justified
    call    api_checkpoint
    API_LIT api_f_finalized
    addi    a0, s4, ApiView_finalized
    call    api_checkpoint
    API_LIT api_end2
9:  UNFRAME 16
END_FUNCTION api_body

/*
 * (view a0, out a1, status a2, body a3, flags a4) -> a0: the HTTP response of beacon-api.md,
 * Common rules, into the ByteList out, its count set: the status line, its fields, then the body
 * of the kind body (0 none, API_BODY_ERROR, or an API_OP_*) from the ApiView view. flags:
 * API_R_CLOSE, API_R_KEEP, API_R_NO_REASON, and the allow bits from bit 8. a0 = LANTERN_OK, or
 * LANTERN_BUFFER_TOO_SMALL when out has too little room. s5 out. Locals: L status, L+8 flags,
 * L+16 the body's bytes.
 */
LOCAL_FUNCTION api_respond
    ENTER 32
    mv      s4, a0
    mv      s5, a1
    sd      a2, (L + 0)(sp)
    sd      a4, (L + 8)(sp)
    mv      s10, a3
    li      s7, 0                           # the body's bytes
    li      s6, 0
    li      s9, 0
    beqz    s10, 1f
    addi    a0, sp, L
    call    api_body
1:  sd      s6, (L + 16)(sp)
    li      s7, 1                           # the response
    addi    s6, s5, 24
    ld      t0, 0(s5)
    add     s8, s5, t0
    # HTTP/1.1 <code> <reason> CRLF
    API_LIT api_http
    ld      a0, (L + 0)(sp)
    call    api_dec
    API_LIT api_sp
    ld      t0, (L + 8)(sp)
    andi    t0, t0, API_R_NO_REASON
    bnez    t0, 2f
    ld      a0, (L + 0)(sp)
    call    api_code
    li      a1, 8
    call    api_code_text
2:  API_LIT api_crlf
    ld      t0, (L + 16)(sp)
    beqz    t0, 3f
    API_LIT api_type
3:  API_LIT api_length
    ld      a0, (L + 16)(sp)
    call    api_dec
    API_LIT api_crlf
    ld      t0, (L + 0)(sp)
    li      t1, 405
    bne     t0, t1, 5f
    # Allow: GET, POST or GET, POST
    API_LIT api_allow
    ld      t0, (L + 8)(sp)
    andi    t0, t0, 0x100
    beqz    t0, 4f
    API_LIT api_get
    ld      t0, (L + 8)(sp)
    andi    t0, t0, 0x200
    beqz    t0, 41f
    API_LIT api_comma
4:  ld      t0, (L + 8)(sp)
    andi    t0, t0, 0x200
    beqz    t0, 41f
    API_LIT api_post
41: API_LIT api_crlf
5:  ld      t0, (L + 8)(sp)
    andi    t1, t0, API_R_CLOSE
    beqz    t1, 6f
    API_LIT api_close
    j       7f
6:  andi    t1, t0, API_R_KEEP
    beqz    t1, 7f
    API_LIT api_keep
7:  API_LIT api_crlf
    beqz    s10, 8f
    addi    a0, sp, L
    call    api_body
8:  bnez    s9, 9f
    addi    t0, s5, 24
    sub     t0, s6, t0
    li      t1, 24
    sd      t1, 8(s5)
    sd      t0, 16(s5)
    li      a0, LANTERN_OK
    LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION api_respond

/*
 * The values of the ApiView a0 that the node, s1, and the store, s2, give (beacon-api.md, Common
 * rules); the header and the checkpoints zero. Locals: the view.
 */
LOCAL_FUNCTION node_api_view
    FRAME 16
    sd      a0, 0(sp)
    li      a1, ApiView__size
    call    lantern_zero
    ld      a0, 0(sp)
    ld      t0, Store_genesis_time_ms(s2)
    li      t1, 1000
    divu    t0, t0, t1
    sd      t0, ApiView_genesis_time(a0)
    addi    t0, a0, ApiView_genesis_validators_root
    addi    t1, s1, Node_genesis_validators_root
    COPY32  t0, t1
    LDQ     t0, s1, Node_config + CONFIG_GENESIS_FORK_VERSION
    sd      t0, ApiView_genesis_fork_version(a0)
    addi    a0, s1, Node_head_root          # the head
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 1f
    ld      a0, 0(sp)
    ld      t0, NodeBlock_slot(a1)
    sd      t0, ApiView_head_slot(a0)
    ld      t0, NodeBlock_payload_status(a1)
    addi    t0, t0, -PAYLOAD_STATUS_NOT_VALIDATED
    seqz    t0, t0
    sd      t0, ApiView_is_optimistic(a0)
    addi    t0, a0, ApiView_head_root
    COPY32  t0, a1
1:  mv      a0, s2                          # the clock, sync, peers, MetaData
    call    node_store_slot
    ld      t3, 0(sp)
    sd      a0, ApiView_current_slot(t3)
    addi    a1, s1, Node_config
    call    node_fork
    ld      t3, 0(sp)
    sd      a0, ApiView_fork(t3)
    ld      t0, Node_flags(s1)
    srli    t1, t0, 3                       # NODE_FLAG_SYNCING
    andi    t1, t1, 1
    sd      t1, ApiView_is_syncing(t3)
    srli    t1, t0, 9                       # NODE_FLAG_EL_OFFLINE
    andi    t1, t1, 1
    sd      t1, ApiView_el_offline(t3)
    ld      t0, (Node_peers + 8)(s1)
    sd      t0, ApiView_peers(t3)
    ld      t0, Node_metadata_seq(s1)
    sd      t0, ApiView_seq_number(t3)
    ld      t0, Node_attnets(s1)
    sd      t0, ApiView_attnets(t3)
    LDQ     t0, s1, Node_config + CONFIG_CUSTODY_REQUIREMENT
    sd      t0, ApiView_custody_group_count(t3)
    addi    a0, t3, ApiView_peer_id         # the identity's texts
    ADDQ    a1, s1, Node_api_identity
    li      a2, API_IDENTITY_SIZE
    call    lantern_copy
    UNFRAME 16
END_FUNCTION node_api_view

/*
 * One NODE_ACT_API_SEND of the connection a0, with last 1, at the end of the actions s6: the
 * response of api_respond with the view a1, the status a2, the body a3 and the flags a4; when it
 * does not fit, the error 500. With API_R_CLOSE, then a NODE_ACT_API_CLOSE. Locals: the
 * connection, the flags, the action, its size.
 */
LOCAL_FUNCTION node_api_send
    FRAME 32
    sd      a0, 0(sp)
    sd      a4, 8(sp)
    ld      t0, 8(s6)                       # the action, and the room after it
    ld      t1, 16(s6)
    add     t2, s6, t0
    add     t2, t2, t1
    sd      t2, 16(sp)
    ld      t3, 0(s6)
    sub     t3, t3, t0
    sub     t3, t3, t1
    addi    t3, t3, -32
    andi    t3, t3, -8
    sd      t3, 32(t2)                      # its ByteList at 32
    mv      a0, a1
    addi    a1, t2, 32
    call    api_respond
    beqz    a0, 1f
    li      a0, 0                           # no room: the error 500
    ld      a1, 16(sp)
    addi    a1, a1, 32
    li      a2, 500
    li      a3, API_BODY_ERROR
    ld      a4, 8(sp)
    andi    a4, a4, (API_R_CLOSE | API_R_KEEP)
    call    api_respond
1:  ld      t2, 16(sp)
    ld      t0, 48(t2)                      # the count; the size to a multiple of 8, zero bytes after
    addi    t1, t0, (56 + 7)
    andi    t1, t1, -8
    sd      t1, 24(sp)
    add     a0, t2, t0
    addi    a0, a0, 56
    addi    a1, t1, -56
    sub     a1, a1, t0
    call    lantern_zero
    ld      t2, 16(sp)
    ld      t1, 24(sp)
    sd      t1, 0(t2)
    li      t0, NODE_ACT_API_SEND
    sd      t0, 8(t2)
    ld      t0, 0(sp)
    sd      t0, 16(t2)
    li      t0, 1
    sd      t0, 24(t2)
    addi    t0, t1, -32
    sd      t0, 32(t2)
    ld      t0, 16(s6)
    add     t0, t0, t1
    sd      t0, 16(s6)
    ld      t0, 8(sp)
    andi    t0, t0, API_R_CLOSE
    beqz    t0, 9f
    li      a0, NODE_ACT_API_CLOSE
    li      a1, NODE_ACT_API_CLOSE_SIZE
    call    node_act
    ld      t0, 0(sp)
    sd      t0, 16(a0)
9:  UNFRAME 32
END_FUNCTION node_api_send

/*
 * The NODE_EV_API or NODE_EV_API_IDENTITY a0, whose ByteList at 24 is inside it (node.md,
 * NodeEvent): a0 = 0 when it keeps its rules, else 1; a1 = the scratch it needs. Uses t0-t6.
 */
LOCAL_FUNCTION node_api_check
    UNWIND_END_PROLOGUE
    ld      t0, 8(a0)
    ld      t1, (NodeEvent_bytes + 16)(a0)  # the count
    addi    t2, a0, (NodeEvent_bytes + 24)  # the bytes
    li      t3, NODE_EV_API_IDENTITY
    bne     t0, t3, 5f
    li      t3, API_IDENTITY_SIZE           # IDENTITY: each text in its room, its bytes 0x21 to 0x7e but " and \
    bne     t1, t3, 8f
    ADDRESS t3, node_api_rooms
1:  ld      t4, 0(t3)
    addi    t3, t3, 8
    beqz    t4, 4f
    ld      t5, 0(t2)
    addi    t2, t2, 8
    bgtu    t5, t4, 8f
    li      t6, 0
2:  bgeu    t6, t5, 3f
    add     t0, t2, t6
    lbu     t0, 0(t0)
    addi    t1, t0, -0x21
    li      a1, (0x7e - 0x21)
    bgtu    t1, a1, 8f
    li      a1, 0x22
    beq     t0, a1, 8f
    li      a1, 0x5c
    beq     t0, a1, 8f
    addi    t6, t6, 1
    j       2b
3:  add     t2, t2, t4
    j       1b
4:  li      a0, 0
    li      a1, 0
    ret
5:  li      t3, HTTP_REQUEST_FIXED          # API: an HttpRequest of the count's size
    bltu    t1, t3, 8f
    andi    t3, t1, 7
    bnez    t3, 8f
    ld      t3, HttpRequest_size(t2)
    bne     t3, t1, 8f
    ld      t3, HttpRequest_status(t2)
    bnez    t3, 7f
    li      t4, HttpRequest_path            # with status 0, each part inside
6:  li      t3, HTTP_REQUEST_FIXED
    bgeu    t4, t3, 7f
    add     t3, t2, t4
    ld      t5, 0(t3)
    ld      t6, 8(t3)
    bgtu    t5, t1, 8f
    sub     t5, t1, t5
    bgtu    t6, t5, 8f
    addi    t4, t4, 16
    j       6b
7:  li      a1, NODE_API_SCRATCH
    ld      t3, HttpRequest_status(t2)
    bnez    t3, 71f
    ld      t3, (HttpRequest_query + 8)(t2)
    slli    t3, t3, 2
    add     a1, a1, t3
71: li      a0, 0
    ret
8:  li      a0, 1
    li      a1, 0
    ret
END_FUNCTION node_api_check

/* a0 = the NODE_DB_REF of the Db's record of the block at a0, or 0. Locals: the slot. */
LOCAL_FUNCTION node_api_db_ref
    FRAME 16
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 9f
    mv      a1, a0
    ld      a0, Node_db(s1)
    add     a0, s1, a0
    mv      a2, sp
    call    lantern_db_find_root
    ld      a0, 0(sp)
    li      t0, -1
    beq     a0, t0, 9f
    call    node_db_block
    UNFRAME 16
9:  li      a0, 0
    UNFRAME 16
END_FUNCTION node_api_db_ref

/*
 * The answer to the NODE_EV_API a0 (node.md, lantern_node_step): s1 the node, s2 the store, s5
 * the scratch, s6 the actions. s3 the event, s4 its HttpRequest, s7 the ApiRoute, s8 the ApiView,
 * s9 the connection, s10 the flags of api_respond. Locals: L the scratch's size.
 */
LOCAL_FUNCTION node_api_event
    ENTER 16
    mv      s3, a0
    ld      s9, 16(s3)
    ld      t0, (NodeEvent_bytes + 8)(s3)
    addi    s4, s3, NodeEvent_bytes
    add     s4, s4, t0
    li      s10, 0                          # close after a fault or with close; HTTP/1.0 kept open says so
    ld      t0, HttpRequest_status(s4)
    ld      t1, HttpRequest_close(s4)
    or      t0, t0, t1
    beqz    t0, 1f
    li      s10, API_R_CLOSE
    j       2f
1:  ld      t0, HttpRequest_version(s4)
    li      t1, 10
    bne     t0, t1, 2f
    li      s10, API_R_KEEP
2:  ld      t0, 0(s5)                       # the ApiView, then the ApiRoute, at the end of scratch
    sd      t0, (L + 0)(sp)
    mv      a0, s3
    call    node_api_check
    ld      t0, (L + 0)(sp)
    sub     t0, t0, a1
    sd      t0, 0(s5)
    add     s8, s5, t0
    addi    s7, s8, ApiView__size
    addi    t0, a1, -ApiView__size
    sd      t0, 0(s7)
    mv      a0, s8
    call    node_api_view
    ld      a2, HttpRequest_status(s4)      # a fault of the request: its status
    bnez    a2, 80f
    mv      a0, s4
    mv      a1, s7
    call    lantern_api_route
    li      t0, LANTERN_INVALID_ROUTE
    bne     a0, t0, 3f
    ld      a2, ApiRoute_status(s7)
    ld      t0, ApiRoute_allow(s7)
    slli    t0, t0, 8
    or      s10, s10, t0
    j       80f
3:  li      a2, 500
    bnez    a0, 80f
    ld      a3, ApiRoute_op(s7)
    li      a2, 200
    li      t0, API_OP_GET_HEALTH
    bne     a3, t0, 4f
    ld      t0, ApiView_is_syncing(s8)      # health: 200, else 206 or syncing_status
    ld      t1, ApiView_is_optimistic(s8)
    or      t0, t0, t1
    ld      t1, ApiView_el_offline(s8)
    or      t0, t0, t1
    li      a3, 0
    beqz    t0, 81f
    li      a2, 206
    ld      t0, ApiRoute_present(s7)
    srli    t0, t0, API_PARAM_SYNCING_STATUS
    andi    t0, t0, 1
    beqz    t0, 81f
    ld      a2, ApiRoute_syncing_status(s7)
    ori     s10, s10, API_R_NO_REASON
    j       81f
4:  li      t0, API_OP_GET_NETWORK_IDENTITY
    beq     a3, t0, 81f
    li      t0, API_OP_GET_NODE_VERSION
    beq     a3, t0, 81f
    li      t0, API_OP_GET_SYNCING_STATUS
    beq     a3, t0, 81f
    li      t0, API_OP_GET_PEER_COUNT
    beq     a3, t0, 81f
    li      t0, API_OP_GET_GENESIS
    beq     a3, t0, 81f
    li      a2, 404
    ld      t1, ApiRoute_id_kind(s7)
    li      t0, API_OP_GET_STATE_FINALITY_CHECKPOINTS
    bne     a3, t0, 5f
    li      t0, API_ID_HEAD                 # finality_checkpoints: of head
    bne     t1, t0, 80f
    j       60f
5:  li      t0, API_OP_GET_BLOCK_HEADER
    bne     a3, t0, 7f
    li      t0, API_ID_HEAD                 # headers: of head, or of the head's root
    beq     t1, t0, 60f
    li      t0, API_ID_ROOT
    bne     t1, t0, 80f
    addi    t2, s7, ApiRoute_id_root
    addi    t3, s1, Node_head_root
    NE32    t2, t3, 80f
60: addi    a0, s1, Node_head_root          # a work with the head's post-state and bytes
    call    node_find_block
    li      a2, 500
    li      t0, -1
    beq     a0, t0, 80f
    mv      s8, a0
    mv      s3, a1
    ld      a0, NodeBlock_data_id(s3)
    bnez    a0, 61f
    mv      a0, s3
    call    node_api_db_ref
61: mv      a3, a0
    ld      a5, ApiRoute_op(s7)             # arg: the operation, the answer flags, the block's index
    andi    t0, s10, API_R_CLOSE
    snez    t0, t0
    ld      t1, HttpRequest_version(s4)
    addi    t1, t1, -10
    seqz    t1, t1
    slli    t1, t1, 1
    or      t0, t0, t1
    slli    t0, t0, 8
    or      a5, a5, t0
    slli    t0, s8, 16
    or      a5, a5, t0
    li      a0, NODE_WORK_API_ENCODE
    ld      a1, NodeBlock_state_id(s3)
    li      a2, 0
    mv      a4, s9
    call    node_work
    j       90f
7:  li      a2, 501                         # another operation
80: li      a3, API_BODY_ERROR
81: mv      a0, s9
    mv      a1, s8
    mv      a4, s10
    call    node_api_send
90: ld      t0, (L + 0)(sp)
    sd      t0, 0(s5)
    LEAVE 16
END_FUNCTION node_api_event

/*
 * The NODE_EV_WORK_DONE a0 of a NODE_WORK_API_ENCODE (node.md, lantern_node_step): its response
 * to the connection, or the error 500. s1 the node, s6 the actions. s3 the event, s4 the action,
 * s7 the flags.
 */
LOCAL_FUNCTION node_api_done
    ENTER 0
    mv      s3, a0
    ld      t0, NodeAction_arg(s3)
    srli    t0, t0, 8
    andi    t0, t0, 255
    andi    s7, t0, API_ANSWER_CLOSE        # API_R_CLOSE, or API_R_KEEP for HTTP/1.0 kept open
    bnez    s7, 1f
    andi    t1, t0, API_ANSWER_HTTP10
    beqz    t1, 1f
    li      s7, API_R_KEEP
1:  ld      t0, NodeEvent_result(s3)
    bnez    t0, 5f
    ld      a1, (NodeEvent_chunk + 16)(s3)  # the chunk's bytes in a SEND
    addi    a1, a1, (56 + 7)
    andi    a1, a1, -8
    li      a0, NODE_ACT_API_SEND
    call    node_act
    mv      s4, a0
    ld      t0, NodeAction_target(s3)
    sd      t0, 16(s4)
    li      t0, 1
    sd      t0, 24(s4)
    ld      t0, 0(s4)
    addi    t0, t0, -32
    sd      t0, 32(s4)
    li      t0, 24
    sd      t0, 40(s4)
    ld      a2, (NodeEvent_chunk + 16)(s3)
    sd      a2, 48(s4)
    addi    a0, s4, 56
    ld      t0, (NodeEvent_chunk + 8)(s3)
    addi    a1, s3, NodeEvent_chunk
    add     a1, a1, t0
    call    lantern_copy
    ld      t0, 48(s4)                      # zero bytes to the size
    addi    a0, s4, 56
    add     a0, a0, t0
    ld      a1, 0(s4)
    addi    a1, a1, -56
    sub     a1, a1, t0
    call    lantern_zero
    andi    t0, s7, API_R_CLOSE
    beqz    t0, 9f
    li      a0, NODE_ACT_API_CLOSE
    li      a1, NODE_ACT_API_CLOSE_SIZE
    call    node_act
    ld      t0, NodeAction_target(s3)
    sd      t0, 16(a0)
    LEAVE 0
5:  ld      a0, NodeAction_target(s3)       # not valid: the error 500
    li      a1, 0
    li      a2, 500
    li      a3, API_BODY_ERROR
    mv      a4, s7
    call    node_api_send
9:  LEAVE 0
END_FUNCTION node_api_done

/*
 * (node, store, work, state_a, data, scratch, event, room) -> a0: a NODE_WORK_API_ENCODE of
 * lantern_node_run (node.md): the response at NodeEvent_chunk of the event, whose buffer has room
 * bytes. s1 the node, s2 the store, s3 the work, s4 state_a, s5 data, s6 the scratch, s7 the
 * event, s8 the ApiView at the end of scratch, s9 the block's entry, s10 the room. Locals: L the
 * scratch's size, L+8 a kept word.
 */
LOCAL_FUNCTION node_api_run
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    mv      s7, a6
    mv      s10, a7
    ld      t0, NodeAction_arg(s3)          # the block's entry
    srli    t0, t0, 16
    PART    s9, t1, s1, Node_blocks
    bgeu    t0, t1, 8f
    beqz    s4, 8f
    li      t1, NodeBlock__mem
    mul     t0, t0, t1
    add     s9, s9, t0
    ld      t0, 0(s6)                       # the ApiView at the end of scratch
    sd      t0, (L + 0)(sp)
    li      t1, ApiView__size
    bltu    t0, t1, 7f
    sub     t0, t0, t1
    sd      t0, 0(s6)
    add     s8, s6, t0
    mv      a0, s8
    call    node_api_view
    ld      t0, NodeBlock_slot(s9)          # the block's root and slot
    sd      t0, ApiView_head_slot(s8)
    addi    t0, s8, ApiView_head_root
    COPY32  t0, s9
    ld      t0, NodeBlock_payload_status(s9)
    addi    t0, t0, -PAYLOAD_STATUS_NOT_VALIDATED
    seqz    t0, t0
    sd      t0, ApiView_is_optimistic(s8)
    ld      t2, NodeAction_arg(s3)
    andi    t2, t2, 255
    li      t0, API_OP_GET_STATE_FINALITY_CHECKPOINTS
    bne     t2, t0, 2f
    ld      a0, NODE_STATE_SLOT(s4)         # finality_checkpoints: the state's
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s4
    addi    a1, s8, ApiView_previous_justified
    FORK_CALL node_state_checkpoints
    j       5f
2:  li      t0, API_OP_GET_BLOCK_HEADER
    bne     t2, t0, 6f
    beqz    s5, 3f
    ld      t0, 16(s5)                      # header: of the bytes, at the fork of their slot
    li      t1, (100 + 84)
    bltu    t0, t1, 41f
    ld      t0, 8(s5)
    add     t0, s5, t0
    ld      a0, 100(t0)
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    ld      t0, (ApiView_proposer_index - 8)(s8)    # the header's slot lands on the root's last 8 bytes: kept
    sd      t0, (L + 8)(sp)
    mv      a0, s5
    mv      a1, s6
    addi    a2, s8, (ApiView_proposer_index - 8)
    FORK_CALL node_block_header
    ld      t0, (L + 8)(sp)
    sd      t0, (ApiView_proposer_index - 8)(s8)
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    bnez    a0, 41f
    j       5f
3:  addi    a0, s8, ApiView_proposer_index  # no bytes: the state's latest_block_header, a zero signature
    addi    a1, s4, (NODE_STATE_HEADER + 8)
    li      a2, (112 - 8)
    call    lantern_copy
    ld      t0, ApiView_state_root(s8)
    ld      t1, (ApiView_state_root + 8)(s8)
    or      t0, t0, t1
    ld      t1, (ApiView_state_root + 16)(s8)
    or      t0, t0, t1
    ld      t1, (ApiView_state_root + 24)(s8)
    or      t0, t0, t1
    bnez    t0, 5f
    ld      a0, NODE_STATE_SLOT(s4)         # a zero state_root: the state's root
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s4
    LDQ     a1, s1, Node_config + CONFIG_STATE_CACHE
    mv      a2, s6
    addi    a3, s8, ApiView_state_root
    FORK_CALL state_root
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    bnez    a0, 41f
5:  ld      t0, NodeAction_arg(s3)          # the response, in the event
    andi    a3, t0, 255
    srli    t0, t0, 8
    andi    t0, t0, 255
    andi    a4, t0, API_ANSWER_CLOSE
    bnez    a4, 51f
    andi    t1, t0, API_ANSWER_HTTP10
    beqz    t1, 51f
    li      a4, API_R_KEEP
51: addi    t0, s10, -NodeEvent_chunk
    andi    t0, t0, -8
    li      t1, 24
    bltu    t0, t1, 71f
    sd      t0, NodeEvent_chunk(s7)
    mv      a0, s8
    addi    a1, s7, NodeEvent_chunk
    li      a2, 200
    call    api_respond
    bnez    a0, 71f
    ld      t0, (NodeEvent_chunk + 16)(s7)  # the event's size covers the chunk
    addi    t0, t0, (NodeEvent_chunk + 24 + 7)
    andi    t0, t0, -8
    sd      t0, 0(s7)
    addi    t0, t0, -NodeEvent_chunk
    sd      t0, NodeEvent_chunk(s7)
    j       9f
41: li      t0, LANTERN_INVALID_ENCODING
    sd      t0, NodeEvent_result(s7)
9:  ld      t0, (L + 0)(sp)
    sd      t0, 0(s6)
    li      a0, LANTERN_OK
    LEAVE 16
6:  ld      t0, (L + 0)(sp)
    sd      t0, 0(s6)
8:  li      a0, LANTERN_INVALID_EVENT
    LEAVE 16
71: ld      t0, (L + 0)(sp)
    sd      t0, 0(s6)
7:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION node_api_run

    RODATA
    .p2align 3
node_api_rooms:                             # the room of each text of an ApiIdentity, then 0
    .quad 64, 512, 128, 128, 64, 0
