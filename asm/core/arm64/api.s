/*
 * The Beacon API answers of the node, ARM64: in the common object. Requirements:
 * docs/reference/beacon-api.md (Common rules) and docs/reference/node.md (NODE_EV_API).
 *
 * The writer: x24 the cursor, x25 the pass (0 counts the bytes, 1 writes them), x26 the end of
 * the room, x27 1 when the room ran out, x22 the ApiView, x28 the body kind. The writer's
 * functions keep x22 and x24-x28 for it; only api_respond calls them.
 */

    RODATA
.include "api_text.inc"

/* The text at label joins the response. */
.macro API_LIT label
    ADDRESS x0, \label
    mov     x1, #\label\()_len
    bl      api_put
.endm

/* L0: the x1 bytes at x0 join the response; the first pass only counts them. Uses x0, x1, x9, x10. */
LOCAL_FUNCTION api_put
    UNWIND_END_PROLOGUE
    cbz     x25, 2f
    add     x9, x24, x1
    cmp     x9, x26
    b.hi    3f
1:  cbz     x1, 9f
    ldrb    w10, [x0], #1
    strb    w10, [x24], #1
    sub     x1, x1, #1
    b       1b
2:  add     x24, x24, x1
9:  ret
3:  mov     x27, #1
    ret
END_FUNCTION api_put

/* L1: the decimal digits of x0 join the response. Locals: the digits, from the end. */
LOCAL_FUNCTION api_dec
    FRAME 32
    add     x9, sp, #48
    mov     x10, #10
1:  udiv    x11, x0, x10
    msub    x12, x11, x10, x0
    add     x12, x12, #0x30
    strb    w12, [x9, #-1]!
    mov     x0, x11
    cbnz    x0, 1b
    mov     x0, x9
    add     x1, sp, #48
    sub     x1, x1, x9
    bl      api_put
    UNFRAME 32
END_FUNCTION api_dec

/* L1: the decimal digits of x0, in quotes. Locals: x0. */
LOCAL_FUNCTION api_qdec
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_quote
    ldr     x0, [sp, #16]
    bl      api_dec
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION api_qdec

/* L1: "0x" and the lower case hex of the x1 bytes at x0, in quotes. Locals: x0, x1, then 2 digits. */
LOCAL_FUNCTION api_qhex
    FRAME 32
    stp     x0, x1, [sp, #16]
    API_LIT api_quote
    API_LIT api_0x
1:  ldp     x0, x1, [sp, #16]
    cbz     x1, 2f
    ldrb    w9, [x0], #1
    sub     x1, x1, #1
    stp     x0, x1, [sp, #16]
    ADDRESS x10, api_hex
    lsr     w11, w9, #4
    ldrb    w11, [x10, x11]
    strb    w11, [sp, #32]
    and     w11, w9, #15
    ldrb    w11, [x10, x11]
    strb    w11, [sp, #33]
    add     x0, sp, #32
    mov     x1, #2
    bl      api_put
    b       1b
2:  API_LIT api_quote
    UNFRAME 32
END_FUNCTION api_qhex

/* L1: the text at x0 (its length, then its bytes), in quotes. Locals: x0. */
LOCAL_FUNCTION api_text
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_quote
    ldr     x9, [sp, #16]
    ldr     x1, [x9]
    add     x0, x9, #8
    bl      api_put
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION api_text

/* L1: true when x0 is not 0, else false. */
LOCAL_FUNCTION api_bool
    FRAME 0
    cbz     x0, 1f
    API_LIT api_true
    UNFRAME 0
1:  API_LIT api_false
    UNFRAME 0
END_FUNCTION api_bool

/* L1: a Checkpoint of the view at x0: {"epoch":…,"root":…}. Locals: x0. */
LOCAL_FUNCTION api_checkpoint
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_f_epoch
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      api_qdec
    API_LIT api_f_root
    ldr     x0, [sp, #16]
    add     x0, x0, #8
    mov     x1, #32
    bl      api_qhex
    API_LIT api_end1
    UNFRAME 16
END_FUNCTION api_checkpoint

/* L0: x0 = the api_codes entry of the status x0, or 0. Uses x9-x11. */
LOCAL_FUNCTION api_code
    UNWIND_END_PROLOGUE
    ADDRESS x9, api_codes
    ADDRESS x10, api_codes_end
1:  cmp     x9, x10
    b.hs    2f
    ldr     x11, [x9]
    cmp     x11, x0
    b.eq    3f
    add     x9, x9, #API_CODE_ENTRY
    b       1b
2:  mov     x0, #0
    ret
3:  mov     x0, x9
    ret
END_FUNCTION api_code

/* L1: the text of the api_codes entry x0 at its byte x1 (8 the reason, 24 the message), or none for no entry. */
LOCAL_FUNCTION api_code_text
    FRAME 0
    cbz     x0, 9f
    add     x9, x0, x1
    ldp     x10, x1, [x9]
    ADDRESS x0, api_texts
    add     x0, x0, x10
    bl      api_put
9:  UNFRAME 0
END_FUNCTION api_code_text

/*
 * L1: the body of the kind x28 for the view x22: an error body of the status at [x0], or the
 * JSON of an operation (beacon-api.md, Common rules). Locals: x0.
 */
LOCAL_FUNCTION api_body
    FRAME 16
    str     x0, [sp, #16]
    cmp     x28, #API_BODY_ERROR
    b.ne    1f
    /* {"code":<n>,"message":"<m>"} */
    API_LIT api_e_code
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      api_dec
    API_LIT api_e_message
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      api_code
    mov     x1, #24
    bl      api_code_text
    API_LIT api_e_end
    UNFRAME 16
1:  cmp     x28, #API_OP_GET_NETWORK_IDENTITY
    b.ne    2f
    API_LIT api_i_peer_id
    add     x0, x22, #ApiView_peer_id
    bl      api_text
    API_LIT api_i_enr
    add     x0, x22, #ApiView_enr
    bl      api_text
    API_LIT api_i_p2p
    ldr     x9, [x22, #ApiView_p2p_address]
    cbz     x9, 14f
    add     x0, x22, #ApiView_p2p_address
    bl      api_text
14: API_LIT api_i_discovery
    ldr     x9, [x22, #ApiView_discovery_address]
    cbz     x9, 15f
    add     x0, x22, #ApiView_discovery_address
    bl      api_text
15: API_LIT api_i_seq
    ldr     x0, [x22, #ApiView_seq_number]
    bl      api_qdec
    API_LIT api_i_attnets
    add     x0, x22, #ApiView_attnets
    mov     x1, #8
    bl      api_qhex
    ldr     x9, [x22, #ApiView_fork]
    cmp     x9, #FORK_ALTAIR
    b.lo    16f
    API_LIT api_i_syncnets
    add     x0, x22, #ApiView_syncnets
    mov     x1, #1
    bl      api_qhex
    ldr     x9, [x22, #ApiView_fork]
    cmp     x9, #FORK_FULU
    b.lo    16f
    API_LIT api_i_cgc
    ldr     x0, [x22, #ApiView_custody_group_count]
    bl      api_qdec
16: API_LIT api_end3
    UNFRAME 16
2:  cmp     x28, #API_OP_GET_NODE_VERSION
    b.ne    3f
    API_LIT api_v_version
    add     x0, x22, #ApiView_version
    bl      api_text
    API_LIT api_end2
    UNFRAME 16
3:  cmp     x28, #API_OP_GET_SYNCING_STATUS
    b.ne    4f
    API_LIT api_s_head
    ldr     x0, [x22, #ApiView_head_slot]
    bl      api_qdec
    API_LIT api_s_distance
    ldr     x9, [x22, #ApiView_current_slot]
    ldr     x10, [x22, #ApiView_head_slot]
    subs    x0, x9, x10
    csel    x0, xzr, x0, lo
    bl      api_qdec
    API_LIT api_s_syncing
    ldr     x0, [x22, #ApiView_is_syncing]
    bl      api_bool
    API_LIT api_s_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
    API_LIT api_s_offline
    ldr     x0, [x22, #ApiView_el_offline]
    bl      api_bool
    API_LIT api_end2
    UNFRAME 16
4:  cmp     x28, #API_OP_GET_PEER_COUNT
    b.ne    5f
    API_LIT api_c_connected
    ldr     x0, [x22, #ApiView_peers]
    bl      api_qdec
    API_LIT api_c_end
    UNFRAME 16
5:  cmp     x28, #API_OP_GET_GENESIS
    b.ne    6f
    API_LIT api_g_time
    ldr     x0, [x22, #ApiView_genesis_time]
    bl      api_qdec
    API_LIT api_g_root
    add     x0, x22, #ApiView_genesis_validators_root
    mov     x1, #32
    bl      api_qhex
    API_LIT api_g_version
    add     x0, x22, #ApiView_genesis_fork_version
    mov     x1, #4
    bl      api_qhex
    API_LIT api_end2
    UNFRAME 16
6:  cmp     x28, #API_OP_GET_BLOCK_HEADER
    b.ne    7f
    API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
    API_LIT api_x_finalized
    API_LIT api_h_root
    add     x0, x22, #ApiView_head_root
    mov     x1, #32
    bl      api_qhex
    API_LIT api_h_slot
    ldr     x0, [x22, #ApiView_head_slot]
    bl      api_qdec
    API_LIT api_h_proposer
    ldr     x0, [x22, #ApiView_proposer_index]
    bl      api_qdec
    API_LIT api_h_parent
    add     x0, x22, #ApiView_parent_root
    mov     x1, #32
    bl      api_qhex
    API_LIT api_h_state
    add     x0, x22, #ApiView_state_root
    mov     x1, #32
    bl      api_qhex
    API_LIT api_h_body
    add     x0, x22, #ApiView_body_root
    mov     x1, #32
    bl      api_qhex
    API_LIT api_h_signature
    add     x0, x22, #ApiView_signature
    mov     x1, #96
    bl      api_qhex
    API_LIT api_end3
    UNFRAME 16
7:  cmp     x28, #API_OP_GET_STATE_FINALITY_CHECKPOINTS
    b.ne    9f
    API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
    API_LIT api_x_finalized
    API_LIT api_f_previous
    add     x0, x22, #ApiView_previous_justified
    bl      api_checkpoint
    API_LIT api_f_current
    add     x0, x22, #ApiView_current_justified
    bl      api_checkpoint
    API_LIT api_f_finalized
    add     x0, x22, #ApiView_finalized
    bl      api_checkpoint
    API_LIT api_end2
9:  UNFRAME 16
END_FUNCTION api_body

/*
 * L1: (view, out, status, body, flags) -> status: the HTTP response of beacon-api.md, Common
 * rules, into the ByteList out, its count set: the status line of status, then its fields, then the
 * body of the kind body (0 none, API_BODY_ERROR, or an API_OP_*) from the ApiView view. flags:
 * API_R_CLOSE, API_R_KEEP, API_R_NO_REASON, and the allow bits from bit 8. x0 = LANTERN_OK, or
 * LANTERN_BUFFER_TOO_SMALL when out has too little room. Locals: L status, L+8 flags, L+16 the
 * body's bytes.
 */
LOCAL_FUNCTION api_respond
    ENTER 32
    mov     x22, x0
    mov     x23, x1
    stp     x2, x4, [sp, #L]
    mov     x28, x3
    mov     x25, #0                         /* the body's bytes */
    mov     x24, #0
    mov     x27, #0
    cbz     x28, 1f
    add     x0, sp, #L
    bl      api_body
1:  str     x24, [sp, #(L + 16)]
    mov     x25, #1                         /* the response */
    add     x24, x23, #24
    ldr     x9, [x23]
    add     x26, x23, x9
    /* HTTP/1.1 <code> <reason> CRLF */
    API_LIT api_http
    ldr     x0, [sp, #L]
    bl      api_dec
    API_LIT api_sp
    ldr     x9, [sp, #(L + 8)]
    tbnz    x9, #2, 2f
    ldr     x0, [sp, #L]
    bl      api_code
    mov     x1, #8
    bl      api_code_text
2:  API_LIT api_crlf
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 3f
    API_LIT api_type
3:  API_LIT api_length
    ldr     x0, [sp, #(L + 16)]
    bl      api_dec
    API_LIT api_crlf
    ldr     x9, [sp, #L]
    cmp     x9, #405
    b.ne    5f
    /* Allow: GET, POST or GET, POST */
    API_LIT api_allow
    ldr     x9, [sp, #(L + 8)]
    tbz     x9, #8, 4f
    API_LIT api_get
    ldr     x9, [sp, #(L + 8)]
    tbz     x9, #9, 41f
    API_LIT api_comma
4:  ldr     x9, [sp, #(L + 8)]
    tbz     x9, #9, 41f
    API_LIT api_post
41: API_LIT api_crlf
5:  ldr     x9, [sp, #(L + 8)]
    tbz     x9, #0, 6f
    API_LIT api_close
    b       7f
6:  tbz     x9, #1, 7f
    API_LIT api_keep
7:  API_LIT api_crlf
    cbz     x28, 8f
    add     x0, sp, #L
    bl      api_body
8:  cbnz    x27, 9f
    add     x9, x23, #24
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    mov     x0, #LANTERN_OK
    LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION api_respond

/*
 * L1: the values of the ApiView x0 that the node, x19, and the store, x20, give (beacon-api.md,
 * Common rules); the header and the checkpoints zero. Locals: L the view.
 */
LOCAL_FUNCTION node_api_view
    FRAME 16
    str     x0, [sp, #16]
    MOVQ    x1, ApiView__size
    bl      lantern_zero
    ldr     x0, [sp, #16]
    ldr     x9, [x20, #Store_genesis_time_ms]
    mov     x10, #1000
    udiv    x9, x9, x10
    str     x9, [x0, #ApiView_genesis_time]
    add     x0, x0, #ApiView_genesis_validators_root
    add     x1, x19, #Node_genesis_validators_root
    mov     x2, #32
    bl      lantern_copy
    ldr     x0, [sp, #16]
    LDQ     x9, x19, Node_config + CONFIG_GENESIS_FORK_VERSION
    str     x9, [x0, #ApiView_genesis_fork_version]
    add     x0, x19, #Node_head_root        /* the head */
    bl      node_find_block
    cmn     x0, #1
    b.eq    1f
    ldr     x0, [sp, #16]
    ldr     x9, [x1, #NodeBlock_slot]
    str     x9, [x0, #ApiView_head_slot]
    ldr     x9, [x1, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
    str     x9, [x0, #ApiView_is_optimistic]
    add     x0, x0, #ApiView_head_root
    bl      lantern_copy_root
1:  mov     x0, x20                         /* the clock, sync, peers, MetaData */
    bl      node_store_slot
    ldr     x9, [sp, #16]
    str     x0, [x9, #ApiView_current_slot]
    add     x1, x19, #Node_config
    bl      node_fork
    ldr     x9, [sp, #16]
    str     x0, [x9, #ApiView_fork]
    ldr     x10, [x19, #Node_flags]
    ubfx    x11, x10, #3, #1                /* NODE_FLAG_SYNCING */
    str     x11, [x9, #ApiView_is_syncing]
    ubfx    x11, x10, #9, #1                /* NODE_FLAG_EL_OFFLINE */
    str     x11, [x9, #ApiView_el_offline]
    ldr     x10, [x19, #(Node_peers + 8)]
    str     x10, [x9, #ApiView_peers]
    ldr     x10, [x19, #Node_metadata_seq]
    str     x10, [x9, #ApiView_seq_number]
    ldr     x10, [x19, #Node_attnets]
    str     x10, [x9, #ApiView_attnets]
    LDQ     x10, x19, Node_config + CONFIG_CUSTODY_REQUIREMENT
    str     x10, [x9, #ApiView_custody_group_count]
    add     x0, x9, #ApiView_peer_id        /* the identity's texts */
    ADDQ    x1, x19, Node_api_identity
    mov     x2, #API_IDENTITY_SIZE
    bl      lantern_copy
    UNFRAME 16
END_FUNCTION node_api_view

/* L0: the 32 bytes at x1 to x0. Uses x16, x17. */
LOCAL_FUNCTION lantern_copy_root
    UNWIND_END_PROLOGUE
    COPY32  x0, x1
    ret
END_FUNCTION lantern_copy_root

/*
 * L1: one NODE_ACT_API_SEND of the connection x0, with last 1, at the end of the actions x24: the
 * response of api_respond with the view x1, the status x2, the body x3 and the flags x4; when it
 * does not fit, the error 500. With API_R_CLOSE, then a NODE_ACT_API_CLOSE. Locals: L the
 * connection, L+8 the flags, L+16 the action.
 */
LOCAL_FUNCTION node_api_send
    FRAME 48
    stp     x0, x4, [sp, #16]
    ldp     x9, x10, [x24, #8]              /* the action, and the room after it */
    add     x11, x24, x9
    add     x11, x11, x10
    str     x11, [sp, #32]
    ldr     x12, [x24]
    sub     x12, x12, x9
    sub     x12, x12, x10
    sub     x12, x12, #32
    and     x12, x12, #~7
    str     x12, [x11, #32]                 /* its ByteList at 32 */
    mov     x0, x1
    add     x1, x11, #32
    bl      api_respond
    cbz     x0, 1f
    mov     x0, #0                          /* no room: the error 500 */
    ldr     x1, [sp, #32]
    add     x1, x1, #32
    mov     x2, #500
    mov     x3, #API_BODY_ERROR
    ldr     x4, [sp, #24]
    and     x4, x4, #(API_R_CLOSE | API_R_KEEP)
    bl      api_respond
1:  ldr     x11, [sp, #32]
    ldr     x9, [x11, #48]                  /* the count; the size to a multiple of 8, zero bytes after */
    add     x0, x11, #56
    add     x0, x0, x9
    add     x10, x9, #(56 + 7)
    and     x10, x10, #~7
    sub     x1, x10, #56
    sub     x1, x1, x9
    str     x10, [sp, #40]
    bl      lantern_zero
    ldr     x11, [sp, #32]
    ldr     x10, [sp, #40]
    mov     x9, #NODE_ACT_API_SEND
    stp     x10, x9, [x11]
    ldr     x9, [sp, #16]
    mov     x12, #1
    stp     x9, x12, [x11, #16]
    sub     x9, x10, #32
    str     x9, [x11, #32]
    ldr     x9, [x24, #16]
    add     x9, x9, x10
    str     x9, [x24, #16]
    ldr     x9, [sp, #24]
    tbz     x9, #0, 9f
    mov     x0, #NODE_ACT_API_CLOSE
    mov     x1, #NODE_ACT_API_CLOSE_SIZE
    bl      node_act
    ldr     x9, [sp, #16]
    str     x9, [x0, #16]
9:  UNFRAME 48
END_FUNCTION node_api_send

/*
 * L0: the NODE_EV_API or NODE_EV_API_IDENTITY x0 of size x1, whose ByteList at 24 is inside it
 * (node.md, NodeEvent): x0 = 0 when it keeps its rules, else 1; x1 = the scratch it needs. Uses
 * x9-x15.
 */
LOCAL_FUNCTION node_api_check
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #8]
    ldr     x10, [x0, #(NodeEvent_bytes + 16)]  /* the count */
    add     x11, x0, #(NodeEvent_bytes + 24)    /* the bytes */
    cmp     x9, #NODE_EV_API_IDENTITY
    b.ne    5f
    cmp     x10, #API_IDENTITY_SIZE         /* IDENTITY: each text in its room, its bytes 0x21 to 0x7e but " and \ */
    b.ne    8f
    ADDRESS x12, node_api_rooms
1:  ldr     x13, [x12], #8
    cbz     x13, 4f
    ldr     x14, [x11], #8
    cmp     x14, x13
    b.hi    8f
    mov     x15, #0
2:  cmp     x15, x14
    b.hs    3f
    ldrb    w9, [x11, x15]
    sub     w10, w9, #0x21
    cmp     w10, #(0x7e - 0x21)
    b.hi    8f
    cmp     w9, #0x22
    b.eq    8f
    cmp     w9, #0x5c
    b.eq    8f
    add     x15, x15, #1
    b       2b
3:  add     x11, x11, x13
    b       1b
4:  mov     x0, #0
    mov     x1, #0
    ret
5:  cmp     x10, #HTTP_REQUEST_FIXED        /* API: an HttpRequest of the count's size */
    b.lo    8f
    tst     x10, #7
    b.ne    8f
    ldr     x12, [x11, #HttpRequest_size]
    cmp     x12, x10
    b.ne    8f
    ldr     x12, [x11, #HttpRequest_status]
    cbnz    x12, 7f
    mov     x13, #HttpRequest_path          /* with status 0, each part inside */
6:  cmp     x13, #HTTP_REQUEST_FIXED
    b.hs    7f
    add     x14, x11, x13
    ldp     x14, x15, [x14]
    cmp     x14, x10
    b.hi    8f
    sub     x14, x10, x14
    cmp     x15, x14
    b.hi    8f
    add     x13, x13, #16
    b       6b
7:  MOVQ    x1, NODE_API_SCRATCH
    ldr     x12, [x11, #HttpRequest_status]
    cbnz    x12, 71f
    ldr     x12, [x11, #(HttpRequest_query + 8)]
    add     x1, x1, x12, lsl #2
71: mov     x0, #0
    ret
8:  mov     x0, #1
    mov     x1, #0
    ret
END_FUNCTION node_api_check

/* L0: x0 = the NODE_DB_REF of the Db's record of the block at x0, or 0. Uses x9-x13, and the stack. */
LOCAL_FUNCTION node_api_db_ref
    FRAME 16
    ldr     x9, [x19, #Node_flags]
    tst     x9, #NODE_FLAG_DB
    b.eq    9f
    mov     x1, x0
    ldr     x0, [x19, #Node_db]
    add     x0, x19, x0
    add     x2, sp, #16
    bl      lantern_db_find_root
    ldr     x0, [sp, #16]
    cmn     x0, #1
    b.eq    9f
    bl      node_db_block
    UNFRAME 16
9:  mov     x0, #0
    UNFRAME 16
END_FUNCTION node_api_db_ref

/*
 * L2: the answer to the NODE_EV_API x0 (node.md, lantern_node_step): x19 the node, x20 the store,
 * x23 the scratch, x24 the actions. x21 the event, x22 its HttpRequest, x25 the ApiRoute, x26 the
 * ApiView, x27 the connection, x28 the flags of api_respond. Locals: L the scratch's size.
 */
LOCAL_FUNCTION node_api_event
    ENTER 16
    mov     x21, x0
    ldr     x27, [x21, #16]
    ldr     x9, [x21, #(NodeEvent_bytes + 8)]
    add     x22, x21, #NodeEvent_bytes
    add     x22, x22, x9
    mov     x28, #0                         /* close after a fault or with close; HTTP/1.0 kept open says so */
    ldr     x9, [x22, #HttpRequest_status]
    ldr     x10, [x22, #HttpRequest_close]
    orr     x9, x9, x10
    cbz     x9, 1f
    mov     x28, #API_R_CLOSE
    b       2f
1:  ldr     x9, [x22, #HttpRequest_version]
    cmp     x9, #10
    b.ne    2f
    mov     x28, #API_R_KEEP
2:  ldr     x9, [x23]                       /* the ApiView, then the ApiRoute, at the end of scratch */
    str     x9, [sp, #L]
    mov     x0, x21
    bl      node_api_check
    ldr     x9, [sp, #L]
    sub     x9, x9, x1
    str     x9, [x23]
    add     x26, x23, x9
    add     x25, x26, #ApiView__size
    MOVQ    x9, ApiView__size
    sub     x9, x1, x9
    str     x9, [x25]
    mov     x0, x26
    bl      node_api_view
    ldr     x2, [x22, #HttpRequest_status]  /* a fault of the request: its status */
    cbnz    x2, 80f
    mov     x0, x22
    mov     x1, x25
    bl      lantern_api_route
    cmp     x0, #LANTERN_INVALID_ROUTE
    b.ne    3f
    ldr     x2, [x25, #ApiRoute_status]
    ldr     x9, [x25, #ApiRoute_allow]
    orr     x28, x28, x9, lsl #8
    b       80f
3:  mov     x2, #500
    cbnz    x0, 80f
    ldr     x3, [x25, #ApiRoute_op]
    mov     x2, #200
    cmp     x3, #API_OP_GET_HEALTH
    b.ne    4f
    ldr     x9, [x26, #ApiView_is_syncing]  /* health: 200, else 206 or syncing_status */
    ldr     x10, [x26, #ApiView_is_optimistic]
    orr     x9, x9, x10
    ldr     x10, [x26, #ApiView_el_offline]
    orr     x9, x9, x10
    mov     x3, #0
    cbz     x9, 81f
    mov     x2, #206
    ldr     x9, [x25, #ApiRoute_present]
    tbz     x9, #API_PARAM_SYNCING_STATUS, 81f
    ldr     x2, [x25, #ApiRoute_syncing_status]
    orr     x28, x28, #API_R_NO_REASON
    b       81f
4:  cmp     x3, #API_OP_GET_NETWORK_IDENTITY
    b.eq    81f
    cmp     x3, #API_OP_GET_NODE_VERSION
    b.eq    81f
    cmp     x3, #API_OP_GET_SYNCING_STATUS
    b.eq    81f
    cmp     x3, #API_OP_GET_PEER_COUNT
    b.eq    81f
    cmp     x3, #API_OP_GET_GENESIS
    b.eq    81f
    mov     x2, #404
    cmp     x3, #API_OP_GET_STATE_FINALITY_CHECKPOINTS
    b.ne    5f
    ldr     x9, [x25, #ApiRoute_id_kind]    /* finality_checkpoints: of head */
    cmp     x9, #API_ID_HEAD
    b.ne    80f
    b       60f
5:  cmp     x3, #API_OP_GET_BLOCK_HEADER
    b.ne    7f
    ldr     x9, [x25, #ApiRoute_id_kind]    /* headers: of head, or of the head's root */
    cmp     x9, #API_ID_HEAD
    b.eq    60f
    cmp     x9, #API_ID_ROOT
    b.ne    80f
    add     x0, x25, #ApiRoute_id_root
    add     x1, x19, #Node_head_root
    ldp     x9, x10, [x0]
    ldp     x11, x12, [x1]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    80f
    ldp     x9, x10, [x0, #16]
    ldp     x11, x12, [x1, #16]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    80f
60: add     x0, x19, #Node_head_root        /* a work with the head's post-state and bytes */
    bl      node_find_block
    mov     x2, #500
    cmn     x0, #1
    b.eq    80f
    mov     x26, x0
    mov     x21, x1
    ldr     x0, [x21, #NodeBlock_data_id]
    cbnz    x0, 61f
    mov     x0, x21
    bl      node_api_db_ref
61: mov     x3, x0
    ldr     x5, [x25, #ApiRoute_op]         /* arg: the operation, the answer flags, the block's index */
    tst     x28, #API_R_CLOSE
    cset    x9, ne
    ldr     x10, [x22, #HttpRequest_version]
    cmp     x10, #10
    cset    x10, eq
    orr     x9, x9, x10, lsl #1
    orr     x5, x5, x9, lsl #8
    orr     x5, x5, x26, lsl #16
    mov     x0, #NODE_WORK_API_ENCODE
    ldr     x1, [x21, #NodeBlock_state_id]
    mov     x2, #0
    mov     x4, x27
    bl      node_work
    b       90f
7:  mov     x2, #501                        /* another operation */
80: mov     x3, #API_BODY_ERROR
81: mov     x0, x27
    mov     x1, x26
    mov     x4, x28
    bl      node_api_send
90: ldr     x9, [sp, #L]
    str     x9, [x23]
    LEAVE 16
END_FUNCTION node_api_event

/*
 * L2: the NODE_EV_WORK_DONE x0 of a NODE_WORK_API_ENCODE (node.md, lantern_node_step): its
 * response to the connection, or the error 500. x19 the node, x24 the actions. x21 the event,
 * x22 the action, x23 the response's bytes, x25 the flags.
 */
LOCAL_FUNCTION node_api_done
    ENTER 0
    mov     x21, x0
    ldr     x9, [x21, #NodeAction_arg]
    ubfx    x10, x9, #8, #8
    and     x25, x10, #API_ANSWER_CLOSE     /* API_R_CLOSE, or API_R_KEEP for HTTP/1.0 kept open */
    cbnz    x25, 1f
    tst     x10, #API_ANSWER_HTTP10
    mov     x11, #API_R_KEEP
    csel    x25, x11, xzr, ne
1:  ldr     x9, [x21, #NodeEvent_result]
    cbnz    x9, 5f
    ldr     x9, [x21, #(NodeEvent_chunk + 16)]  /* the chunk's bytes in a SEND */
    add     x1, x9, #(56 + 7)
    and     x1, x1, #~7
    mov     x0, #NODE_ACT_API_SEND
    bl      node_act
    mov     x22, x0
    ldr     x9, [x21, #NodeAction_target]
    mov     x10, #1
    stp     x9, x10, [x22, #16]
    ldr     x9, [x22]
    sub     x9, x9, #32
    mov     x10, #24
    stp     x9, x10, [x22, #32]
    ldr     x2, [x21, #(NodeEvent_chunk + 16)]
    str     x2, [x22, #48]
    add     x0, x22, #56
    ldr     x9, [x21, #(NodeEvent_chunk + 8)]
    add     x1, x21, #NodeEvent_chunk
    add     x1, x1, x9
    bl      lantern_copy
    ldr     x9, [x22, #48]                  /* zero bytes to the size */
    add     x0, x22, #56
    add     x0, x0, x9
    ldr     x10, [x22]
    sub     x1, x10, #56
    sub     x1, x1, x9
    bl      lantern_zero
    tbz     x25, #0, 9f
    mov     x0, #NODE_ACT_API_CLOSE
    mov     x1, #NODE_ACT_API_CLOSE_SIZE
    bl      node_act
    ldr     x9, [x21, #NodeAction_target]
    str     x9, [x0, #16]
    LEAVE 0
5:  ldr     x0, [x21, #NodeAction_target]   /* not valid: the error 500 */
    mov     x1, #0
    mov     x2, #500
    mov     x3, #API_BODY_ERROR
    mov     x4, x25
    bl      node_api_send
9:  LEAVE 0
END_FUNCTION node_api_done

/*
 * (node, store, work, state_a, data, scratch, event, room) -> status: a NODE_WORK_API_ENCODE of
 * lantern_node_run (node.md): the response at NodeEvent_chunk of the event, whose buffer has room
 * bytes. x19 the node, x20 the store, x21 the work, x22 state_a, x23 data, x24 the scratch, x25
 * the event, x26 the ApiView at the end of scratch, x27 the block's entry, x28 the room. Locals:
 * L the scratch's size.
 */
LOCAL_FUNCTION node_api_run
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    mov     x28, x7
    ldr     x9, [x21, #NodeAction_arg]      /* the block's entry */
    lsr     x9, x9, #16
    PART    x27, x10, x19, Node_blocks
    cmp     x9, x10
    b.hs    8f
    cbz     x22, 8f
    mov     x10, #NodeBlock__mem
    madd    x27, x9, x10, x27
    ldr     x9, [x24]                       /* the ApiView at the end of scratch */
    str     x9, [sp, #L]
    MOVQ    x10, ApiView__size
    subs    x9, x9, x10
    b.lo    7f
    str     x9, [x24]
    add     x26, x24, x9
    mov     x0, x26
    bl      node_api_view
    ldr     x9, [x27, #NodeBlock_slot]      /* the block's root and slot */
    str     x9, [x26, #ApiView_head_slot]
    add     x0, x26, #ApiView_head_root
    mov     x1, x27
    bl      lantern_copy_root
    ldr     x9, [x27, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
    str     x9, [x26, #ApiView_is_optimistic]
    ldr     x9, [x21, #NodeAction_arg]
    and     x9, x9, #255
    cmp     x9, #API_OP_GET_STATE_FINALITY_CHECKPOINTS
    b.ne    2f
    ldr     x0, [x22, #NODE_STATE_SLOT]     /* finality_checkpoints: the state's */
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x22
    add     x1, x26, #ApiView_previous_justified
    FORK_CALL node_state_checkpoints
    b       5f
2:  cmp     x9, #API_OP_GET_BLOCK_HEADER
    b.ne    6f
    cbz     x23, 3f
    ldr     x9, [x23, #16]                  /* header: of the bytes, at the fork of their slot */
    cmp     x9, #(100 + 84)
    b.lo    41f
    ldr     x9, [x23, #8]
    add     x9, x23, x9
    ldr     x0, [x9, #100]
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x23
    mov     x1, x24
    add     x2, x26, #(ApiView_proposer_index - 8)  /* the header's slot lands on the root's last 8 bytes: kept */
    ldr     x9, [x26, #(ApiView_proposer_index - 8)]
    str     x9, [sp, #(L + 8)]
    FORK_CALL node_block_header
    ldr     x9, [sp, #(L + 8)]
    str     x9, [x26, #(ApiView_proposer_index - 8)]
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbnz    x0, 41f
    b       5f
3:  add     x0, x26, #ApiView_proposer_index    /* no bytes: the state's latest_block_header, a zero signature */
    add     x1, x22, #(NODE_STATE_HEADER + 8)
    mov     x2, #(112 - 8)
    bl      lantern_copy
    ldp     x9, x10, [x26, #ApiView_state_root]
    ldp     x11, x12, [x26, #(ApiView_state_root + 16)]
    orr     x9, x9, x10
    orr     x11, x11, x12
    orr     x9, x9, x11
    cbnz    x9, 5f
    ldr     x0, [x22, #NODE_STATE_SLOT]     /* a zero state_root: the state's root */
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x22
    LDQ     x1, x19, Node_config + CONFIG_STATE_CACHE
    mov     x2, x24
    add     x3, x26, #ApiView_state_root
    FORK_CALL state_root
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbnz    x0, 41f
5:  ldr     x9, [x21, #NodeAction_arg]      /* the response, in the event */
    and     x3, x9, #255
    ubfx    x10, x9, #8, #8
    and     x4, x10, #API_ANSWER_CLOSE
    cbnz    x4, 51f
    tst     x10, #API_ANSWER_HTTP10
    mov     x11, #API_R_KEEP
    csel    x4, x11, xzr, ne
51: sub     x9, x28, #NodeEvent_chunk
    and     x9, x9, #~7
    cmp     x9, #24
    b.lo    71f
    str     x9, [x25, #NodeEvent_chunk]
    mov     x0, x26
    add     x1, x25, #NodeEvent_chunk
    mov     x2, #200
    bl      api_respond
    cbnz    x0, 71f
    ldr     x9, [x25, #(NodeEvent_chunk + 16)]  /* the event's size covers the chunk */
    add     x9, x9, #(NodeEvent_chunk + 24 + 7)
    and     x9, x9, #~7
    str     x9, [x25]
    sub     x9, x9, #NodeEvent_chunk
    str     x9, [x25, #NodeEvent_chunk]
    b       9f
41: mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x25, #NodeEvent_result]
9:  ldr     x9, [sp, #L]
    str     x9, [x24]
    mov     x0, #LANTERN_OK
    LEAVE 16
6:  ldr     x9, [sp, #L]
    str     x9, [x24]
8:  mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 16
71: ldr     x9, [sp, #L]
    str     x9, [x24]
7:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION node_api_run

    RODATA
    .p2align 3
node_api_rooms:                             /* the room of each text of an ApiIdentity, then 0 */
    .quad 64, 512, 128, 128, 64, 0
