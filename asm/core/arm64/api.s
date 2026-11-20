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
.include "api_spec.inc"

/* A record of API_SPEC_KEYS: the name's length, its kind, its value, then the name in CONFIG_KEY_NAME_MAX bytes. */
.set API_SPEC_BYTES, 24 + CONFIG_KEY_NAME_MAX
.macro API_SPEC_RECORD name, kind, value
    .quad 72f - 71f, \kind, \value
71: .ascii "\name"
72: .space CONFIG_KEY_NAME_MAX - (72b - 71b)
.endm
    .p2align 3
api_spec_keys:
    API_SPEC_KEYS API_SPEC_RECORD
api_spec_keys_end:

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

/* L1: the decimal digits of the Uint256 at x0, little endian, in quotes. Locals: its eight 32-bit words, then the text from its end. */
LOCAL_FUNCTION api_qdec256
    FRAME 128
    ldp     x10, x11, [x0]
    stp     x10, x11, [sp, #16]
    ldp     x10, x11, [x0, #16]
    stp     x10, x11, [sp, #32]
    add     x9, sp, #(16 + 128)             /* the closing quote, then the digits backwards */
    mov     w10, #0x22
    strb    w10, [x9, #-1]!
    add     x7, sp, #16
    mov     x10, #10
1:  mov     x4, #0                          /* divide by 10, from the top word down */
    mov     x5, #7
    mov     x6, #0                          /* any word not zero */
2:  ldr     w11, [x7, x5, lsl #2]
    orr     x11, x11, x4, lsl #32
    udiv    x12, x11, x10
    msub    x4, x12, x10, x11
    str     w12, [x7, x5, lsl #2]
    orr     x6, x6, x12
    subs    x5, x5, #1
    b.hs    2b
    add     x4, x4, #0x30
    strb    w4, [x9, #-1]!
    cbnz    x6, 1b
    mov     w10, #0x22
    strb    w10, [x9, #-1]!
    mov     x0, x9
    add     x1, sp, #(16 + 128)
    sub     x1, x1, x9
    bl      api_put
    UNFRAME 128
END_FUNCTION api_qdec256

/*
 * L2: the body of getSpec (beacon-api.md, Common rules): each key of API_SPEC_KEYS, with the
 * config of the view x22. Locals: L the record, L+8 an index, L+16 32 bytes of a value, L+48 a count.
 */
LOCAL_FUNCTION api_spec
    FRAME 64
    ADDRESS x9, api_spec_keys
    str     x9, [sp, #16]
    API_LIT api_p_open
    b       2f
1:  ldr     x9, [sp, #16]                   /* the next record */
    add     x9, x9, #API_SPEC_BYTES
    str     x9, [sp, #16]
    ADDRESS x10, api_spec_keys_end
    cmp     x9, x10
    b.hs    9f
    API_LIT api_p_next
2:  ldr     x9, [sp, #16]                   /* "<name>": */
    ldr     x1, [x9]
    add     x0, x9, #24
    bl      api_put
    API_LIT api_p_key
    ldr     x9, [sp, #16]
    ldp     x10, x0, [x9, #8]               /* the kind, the value */
    lsr     x12, x10, #8                    /* the kind's arg */
    and     x10, x10, #255
    stp     x0, xzr, [sp, #32]              /* the value's bytes, then zero bytes */
    stp     xzr, xzr, [sp, #48]
    str     x12, [sp, #64]
    cmp     x10, #SPEC_NUMBER
    b.ne    3f
    bl      api_qdec
    b       1b
3:  cmp     x10, #SPEC_HEX
    b.ne    4f
    add     x0, sp, #32
    mov     x1, x12
    bl      api_qhex
    b       1b
4:  cmp     x10, #SPEC_TEXT
    b.ne    5f
    API_LIT api_quote
    add     x0, sp, #32
    ldr     x1, [sp, #64]
    bl      api_put
    API_LIT api_quote
    b       1b
5:  cmp     x10, #SPEC_LIST
    b.ne    6f
    API_LIT api_p_lbracket
    str     xzr, [sp, #24]
51: ldr     x9, [sp, #24]
    ldr     x10, [sp, #64]
    cmp     x9, x10
    b.hs    52f
    cbz     x9, 53f
    API_LIT api_p_comma
53: ldr     x9, [sp, #24]
    add     x10, sp, #32
    ldrb    w0, [x10, x9]
    add     x9, x9, #1
    str     x9, [sp, #24]
    bl      api_qdec
    b       51b
52: API_LIT api_p_rbracket
    b       1b
6:  ldr     x9, [x22, #ApiView_config]
    add     x0, x9, x0                      /* the config's field */
    cmp     x10, #SPEC_SECONDS
    b.ne    7f
    ldr     x0, [x0]
    mov     x9, #1000
    udiv    x0, x0, x9
    bl      api_qdec
    b       1b
7:  cmp     x10, #SPEC_CONFIG
    b.ne    8f
    cmp     x12, #CONFIG_KIND_U64
    b.ne    71f
    ldr     x0, [x0]
    bl      api_qdec
    b       1b
71: cmp     x12, #CONFIG_KIND_UINT256
    b.ne    72f
    bl      api_qdec256
    b       1b
72: cmp     x12, #CONFIG_KIND_TEXT
    b.ne    73f
    bl      api_text                        /* in quotes */
    b       1b
73: mov     x1, #4                          /* Version: 4 bytes; Hash32: 32; Address: 20 */
    cmp     x12, #CONFIG_KIND_HASH32
    mov     x9, #32
    csel    x1, x9, x1, eq
    cmp     x12, #CONFIG_KIND_ADDRESS
    mov     x9, #20
    csel    x1, x9, x1, eq
    bl      api_qhex
    b       1b
    /* SPEC_SCHEDULE: [{"EPOCH":…,"MAX_BLOBS_PER_BLOCK":…},…] */
8:  API_LIT api_p_lbracket
    str     xzr, [sp, #24]
81: ldr     x9, [sp, #24]
    ldr     x11, [x22, #ApiView_config]
    LDQ     x10, x11, CONFIG_BLOB_SCHEDULE_COUNT
    cmp     x9, x10
    b.hs    82f
    cbz     x9, 83f
    API_LIT api_p_comma
83: API_LIT api_p_epoch
    ldr     x9, [sp, #24]
    ldr     x11, [x22, #ApiView_config]
    add     x11, x11, #CONFIG_BLOB_SCHEDULE
    add     x11, x11, x9, lsl #4
    ldr     x0, [x11]
    bl      api_qdec
    API_LIT api_p_max
    ldr     x9, [sp, #24]
    ldr     x11, [x22, #ApiView_config]
    add     x11, x11, #(CONFIG_BLOB_SCHEDULE + 8)
    add     x11, x11, x9, lsl #4
    ldr     x0, [x11]
    bl      api_qdec
    API_LIT api_end1
    ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    b       81b
82: API_LIT api_p_rbracket
    b       1b
9:  API_LIT api_end2
    UNFRAME 64
END_FUNCTION api_spec

/*
 * L2: the body of getForkSchedule (beacon-api.md, Common rules), with the config of the view x22:
 * phase0, then each fork to fulu whose epoch is below 2^64 - 1. Locals: L the fork, L+8 the
 * previous version, L+16 the version, L+24 the epoch.
 */
LOCAL_FUNCTION api_fork_schedule
    FRAME 32
    API_LIT api_o_open
    ldr     x9, [x22, #ApiView_config]
    ldr     x10, [x9, #CONFIG_GENESIS_FORK_VERSION]
    stp     xzr, x10, [sp, #16]
    stp     x10, xzr, [sp, #32]
    b       2f
1:  ldr     x9, [sp, #16]                   /* the next fork: its version at 16 * fork - 8, its epoch at 16 * fork */
    add     x9, x9, #1
    str     x9, [sp, #16]
    cmp     x9, #FORK_FULU
    b.hi    9f
    ldr     x10, [x22, #ApiView_config]
    add     x10, x10, x9, lsl #4
    ldur    x11, [x10, #-8]
    ldr     x12, [x10]
    cmn     x12, #1
    b.eq    1b
    stp     x11, x12, [sp, #32]
    API_LIT api_p_comma
    /* {"previous_version":…,"current_version":…,"epoch":…} */
2:  API_LIT api_o_entry
    add     x0, sp, #24
    mov     x1, #4
    bl      api_qhex
    API_LIT api_k_current
    add     x0, sp, #32
    mov     x1, #4
    bl      api_qhex
    API_LIT api_k_epoch
    ldr     x0, [sp, #40]
    bl      api_qdec
    API_LIT api_end1
    ldr     x9, [sp, #32]                   /* the next fork's previous version */
    str     x9, [sp, #24]
    b       1b
9:  API_LIT api_o_end
    UNFRAME 32
END_FUNCTION api_fork_schedule

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
    LDQ     x0, x22, ApiView_head_finalized
    bl      api_bool
    API_LIT api_x_data
    API_LIT api_h_root
    add     x0, x22, #ApiView_head_root
    mov     x1, #32
    bl      api_qhex
    API_LIT api_h_canonical
    ldr     x0, [x22, #ApiView_canonical]
    bl      api_bool
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
    LDQ     x0, x22, ApiView_head_finalized
    bl      api_bool
    API_LIT api_x_data
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
    UNFRAME 16
9:  cmp     x28, #API_OP_GET_BLOCK_ROOT     /* getBlockRoot, getStateRoot: {"execution_optimistic":…,"finalized":…,"data":{"root":…}} */
    b.eq    10f
    cmp     x28, #API_OP_GET_STATE_ROOT
    b.eq    10f
    cmp     x28, #API_OP_GET_STATE_FORK
    b.ne    12f
10: API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      api_bool
    API_LIT api_x_data
    cmp     x28, #API_OP_GET_STATE_FORK
    b.eq    11f
    API_LIT api_h_root
    add     x0, x22, #ApiView_head_root
    mov     x1, #32
    bl      api_qhex
    API_LIT api_end2
    UNFRAME 16
    /* getStateFork: {"previous_version":…,"current_version":…,"epoch":…} */
11: API_LIT api_k_previous
    ADDQ    x0, x22, ApiView_state_fork
    mov     x1, #4
    bl      api_qhex
    API_LIT api_k_current
    ADDQ    x0, x22, ApiView_state_fork + 4
    mov     x1, #4
    bl      api_qhex
    API_LIT api_k_epoch
    LDQ     x0, x22, ApiView_state_fork + 8
    bl      api_qdec
    API_LIT api_end2
    UNFRAME 16
12: cmp     x28, #API_OP_GET_SPEC
    b.ne    13f
    bl      api_spec
    UNFRAME 16
13: cmp     x28, #API_OP_GET_FORK_SCHEDULE
    b.ne    17f
    bl      api_fork_schedule
    UNFRAME 16
17: cmp     x28, #API_OP_GET_DEPOSIT_CONTRACT   /* {"data":{"chain_id":…,"address":…}} */
    b.ne    99f
    API_LIT api_d_chain
    ldr     x9, [x22, #ApiView_config]
    LDQ     x0, x9, CONFIG_DEPOSIT_CHAIN_ID
    bl      api_qdec
    API_LIT api_d_address
    ldr     x9, [x22, #ApiView_config]
    ADDQ    x0, x9, CONFIG_DEPOSIT_CONTRACT_ADDRESS
    mov     x1, #20
    bl      api_qhex
    API_LIT api_end2
99: UNFRAME 16
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
    add     x9, x19, #Node_config
    STQ     x9, x0, ApiView_config
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
    ldr     x0, [sp, #16]
    bl      api_view_finalized
    UNFRAME 16
END_FUNCTION node_api_view

/* L0: ApiView_head_finalized of the view x0: 1 when its head_root is the root of the store x20's finalized checkpoint. Uses x9-x16. */
LOCAL_FUNCTION api_view_finalized
    UNWIND_END_PROLOGUE
    add     x9, x0, #ApiView_head_root
    add     x10, x20, #(Store_finalized_checkpoint + 8)
    mov     x13, #0
    ldp     x11, x12, [x9]
    ldp     x14, x15, [x10]
    cmp     x11, x14
    ccmp    x12, x15, #0, eq
    b.ne    1f
    ldp     x11, x12, [x9, #16]
    ldp     x14, x15, [x10, #16]
    cmp     x11, x14
    ccmp    x12, x15, #0, eq
    cset    x13, eq
1:  STQ     x13, x0, ApiView_head_finalized
    ret
END_FUNCTION api_view_finalized

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
5:  ldr     x12, [x0, #16]                  /* API: a connection, not 0 */
    cbz     x12, 8f
    cmp     x10, #HTTP_REQUEST_FIXED        /* an HttpRequest of the count's size */
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
    cmp     x3, #API_OP_GET_FORK_SCHEDULE
    b.eq    81f
    cmp     x3, #API_OP_GET_DEPOSIT_CONTRACT
    b.eq    81f
    mov     x2, #404
    ldr     x9, [x22, #HttpRequest_version] /* x21: the answer flags of a work or a stream */
    cmp     x9, #10
    cset    x9, eq
    tst     x28, #API_R_CLOSE
    cset    x21, ne
    orr     x21, x21, x9, lsl #1
    cmp     x3, #API_OP_GET_BLOCK_ROOT
    b.eq    65f
    cmp     x3, #API_OP_GET_BLOCK_HEADER
    b.eq    65f
    cmp     x3, #API_OP_GET_BLOCK_V2
    b.eq    65f
    cmp     x3, #API_OP_GET_STATE_ROOT
    b.eq    66f
    cmp     x3, #API_OP_GET_STATE_FORK
    b.eq    66f
    cmp     x3, #API_OP_GET_STATE_FINALITY_CHECKPOINTS
    b.eq    66f
    cmp     x3, #API_OP_GET_SPEC
    b.eq    67f
    cmp     x3, #API_OP_GET_STATE_V2
    b.ne    7f
66: ldr     x9, [x25, #ApiRoute_id_kind]    /* a state root: a work finds its slot first */
    cmp     x9, #API_ID_ROOT
    b.ne    69f
    mov     x0, x27
    mov     x1, x25
    mov     x2, x21
    bl      node_api_lookup
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
69: mov     x0, x25                         /* a state: its lookup, then the state at its slot */
    mov     x1, x26
    bl      node_api_state
    mov     x2, x0
    cbnz    x0, 80f
    mov     x0, x26
    bl      node_api_advance
    ldr     x0, [x25, #ApiRoute_op]
    cmp     x0, #API_OP_GET_STATE_V2
    b.eq    64f
    b       67f
65: mov     x0, x25                         /* a block: its lookup */
    mov     x1, x26
    bl      node_api_block
    mov     x2, x0
    cbnz    x0, 80f
    ldr     x3, [x25, #ApiRoute_op]
    mov     x2, #200
    cmp     x3, #API_OP_GET_BLOCK_ROOT      /* getBlockRoot: the answer at once */
    b.eq    81f
    cmp     x3, #API_OP_GET_BLOCK_V2
    b.eq    64f
67: ldr     x0, [x25, #ApiRoute_op]         /* a work */
    mov     x1, x27
    mov     x2, x21
    mov     x3, x26
    bl      node_api_encode
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
64: mov     x0, x27                         /* a stream of the answer */
    mov     x1, x25
    mov     x2, x21
    mov     x3, x26
    bl      node_api_stream
    cbz     x0, 90f
    mov     x2, x0
    b       80f
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
 * the event, x26 the ApiView at the end of scratch, x27 the operation, x28 the room. Locals: L the
 * scratch's size, L+8 a kept word, L+16 a Result, L+24 a blob count.
 */
LOCAL_FUNCTION node_api_run
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    mov     x28, x7
    ldr     x9, [x21, #NodeAction_arg]      /* the operation; a block index past the blocks part */
    and     x27, x9, #255
    lsr     x10, x9, #24
    cmp     x27, #API_OP_GET_BLOCK_HEADER
    b.ne    1f
    ldr     x11, [x19, #(Node_blocks + 8)]
    cmp     x10, x11
    b.hi    8f
    orr     x11, x23, x10                   /* a header: bytes, or a block of the node with a post-state */
    cbz     x11, 8f
    cbnz    x23, 2f
    cbz     x10, 8f
    cbz     x22, 8f
    b       2f
1:  cmp     x27, #API_OP_GET_SPEC           /* getSpec: no state */
    b.eq    2f
    cbz     x22, 8f                         /* a state's answer: a state */
    cmp     x27, #API_OP_GET_STATE_FINALITY_CHECKPOINTS
    b.eq    2f
    cmp     x27, #API_OP_GET_STATE_ROOT
    b.eq    2f
    cmp     x27, #API_OP_GET_STATE_FORK
    b.ne    8f
2:  ldr     x9, [x24]                       /* the ApiView at the end of scratch, with the work's values */
    str     x9, [sp, #L]
    MOVQ    x10, ApiView__size
    subs    x9, x9, x10
    b.lo    7f
    str     x9, [x24]
    add     x26, x24, x9
    mov     x0, x26
    bl      node_api_view
    ldr     x9, [x21, #NodeAction_arg]
    ubfx    x10, x9, #16, #1
    str     x10, [x26, #ApiView_canonical]
    ubfx    x10, x9, #17, #1
    STQ     x10, x26, ApiView_head_finalized
    ubfx    x10, x9, #18, #1
    str     x10, [x26, #ApiView_is_optimistic]
    cmp     x27, #API_OP_GET_BLOCK_HEADER
    b.eq    3f
    cmp     x27, #API_OP_GET_SPEC
    b.eq    5f
    ldr     x0, [x22, #NODE_STATE_SLOT]     /* a state at the work's slot, else the work that brought it there failed */
    lsr     x9, x9, #24
    cmp     x0, x9
    b.ne    42f
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    cmp     x27, #API_OP_GET_STATE_FINALITY_CHECKPOINTS
    b.ne    21f
    mov     x0, x22                         /* finality_checkpoints */
    add     x1, x26, #ApiView_previous_justified
    FORK_CALL node_state_checkpoints
    b       5f
21: cmp     x27, #API_OP_GET_STATE_FORK
    b.ne    22f
    ADDQ    x0, x26, ApiView_state_fork     /* fork */
    add     x1, x22, #NODE_STATE_FORK
    mov     x2, #16
    bl      lantern_copy
    b       5f
22: mov     x0, x22                         /* root */
    LDQ     x1, x19, Node_config + CONFIG_STATE_CACHE
    mov     x2, x24
    add     x3, x26, #ApiView_head_root
    FORK_CALL state_root
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbnz    x0, 41f
    b       5f
3:  cbz     x23, 33f
    ldr     x9, [x23, #16]                  /* header: of the bytes, at the fork of their slot */
    cmp     x9, #(100 + 84)
    b.lo    41f
    ldr     x9, [x23, #8]
    add     x9, x23, x9
    ldr     x0, [x9, #100]
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    str     x15, [sp, #(L + 24)]
    mov     x0, x23
    mov     x1, x24
    add     x2, x26, #(ApiView_proposer_index - 8)  /* the header's slot lands on the root's last 8 bytes */
    FORK_CALL node_block_header
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbnz    x0, 41f
    ldr     x9, [x26, #(ApiView_proposer_index - 8)]
    str     x9, [x26, #ApiView_head_slot]
    ldr     x9, [x21, #NodeAction_arg]      /* the root: the node's block's, else of the bytes */
    lsr     x9, x9, #24
    cbnz    x9, 34f
    ldr     x15, [sp, #(L + 24)]
    mov     x0, x23
    mov     x1, x24
    add     x2, x26, #ApiView_head_root
    add     x3, sp, #(L + 16)
    add     x4, sp, #(L + 24)
    FORK_CALL node_block_root
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbnz    x0, 41f
    ldr     x9, [sp, #(L + 16)]
    cbnz    x9, 41f
    b       5f
33: add     x0, x26, #ApiView_proposer_index    /* no bytes: the state's latest_block_header, a zero signature */
    add     x1, x22, #(NODE_STATE_HEADER + 8)
    mov     x2, #(112 - 8)
    bl      lantern_copy
    ldr     x9, [x22, #NODE_STATE_HEADER]
    str     x9, [x26, #ApiView_head_slot]
    ldp     x9, x10, [x26, #ApiView_state_root]
    ldp     x11, x12, [x26, #(ApiView_state_root + 16)]
    orr     x9, x9, x10
    orr     x11, x11, x12
    orr     x9, x9, x11
    cbnz    x9, 34f
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
34: ldr     x9, [x21, #NodeAction_arg]      /* the root of the node's block, index - 1 */
    lsr     x9, x9, #24
    cbz     x9, 5f
    sub     x9, x9, #1
    PART    x10, x11, x19, Node_blocks
    mov     x11, #NodeBlock__mem
    madd    x1, x9, x11, x10
    add     x0, x26, #ApiView_head_root
    bl      lantern_copy_root
5:  ldr     x9, [x21, #NodeAction_arg]      /* the response, in the event */
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
    mov     x3, x27
    bl      api_respond
    cbnz    x0, 71f
    ldr     x9, [x25, #(NodeEvent_chunk + 16)]  /* the event's size covers the chunk */
    add     x9, x9, #(NodeEvent_chunk + 24 + 7)
    and     x9, x9, #~7
    str     x9, [x25]
    sub     x9, x9, #NodeEvent_chunk
    str     x9, [x25, #NodeEvent_chunk]
    b       9f
42: mov     x9, #LANTERN_INVALID_SLOT
    str     x9, [x25, #NodeEvent_result]
    b       9f
41: mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x25, #NodeEvent_result]
9:  ldr     x9, [sp, #L]
    str     x9, [x24]
    mov     x0, #LANTERN_OK
    LEAVE 32
8:  mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 32
71: ldr     x9, [sp, #L]
    str     x9, [x24]
7:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION node_api_run

/* ---------------------------------------------------------------- Lookup (beacon-api.md, Common rules) */

/* L1: x0 = the NodeBlock index of the imported parent of the entry x0, or 2^64 - 1; x1 = its entry. Uses x9-x15. */
LOCAL_FUNCTION node_api_parent
    FRAME 0
    add     x0, x0, #NodeBlock_parent_root
    bl      node_find_block
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.eq    9f
    mov     x0, #-1
9:  UNFRAME 0
END_FUNCTION node_api_parent

/*
 * L1: the block of the chain at or below the slot x0: x0 = its NodeBlock index, x1 = its entry; or
 * x0 = 2^64 - 1 when the lowest block of the chain the node keeps, x1 (0 with no head), is above
 * the slot. Locals: L the slot, L+8 an entry.
 */
LOCAL_FUNCTION node_api_below
    FRAME 32
    str     x0, [sp, #16]
    add     x0, x19, #Node_head_root
    bl      node_find_block
    cmn     x0, #1
    b.ne    1f
    mov     x1, #0
    UNFRAME 32
1:  ldr     x9, [x1, #NodeBlock_slot]
    ldr     x10, [sp, #16]
    cmp     x9, x10
    b.ls    9f
    str     x1, [sp, #24]
    mov     x0, x1
    bl      node_api_parent
    cmn     x0, #1
    b.ne    1b
    ldr     x1, [sp, #24]
9:  UNFRAME 32
END_FUNCTION node_api_below

/* L1: x0 = 1 when the block entry x0 is on the chain, else 0. Locals: L the entry. */
LOCAL_FUNCTION node_api_on_chain
    FRAME 16
    str     x0, [sp, #16]
    ldr     x0, [x0, #NodeBlock_slot]
    bl      node_api_below
    cmn     x0, #1
    b.eq    8f
    ldr     x9, [sp, #16]
    cmp     x1, x9
    cset    x0, eq
    UNFRAME 16
8:  mov     x0, #0
    UNFRAME 16
END_FUNCTION node_api_on_chain

/* L1: x0 = 1 when the slot x0 is at most that of the block of the store's finalized root, else 0. Locals: x0. */
LOCAL_FUNCTION node_api_final_block
    FRAME 16
    str     x0, [sp, #16]
    bl      node_f_slot
    ldr     x9, [sp, #16]
    cmn     x0, #1
    b.eq    8f
    cmp     x9, x0
    cset    x0, ls
    UNFRAME 16
8:  mov     x0, #0
    UNFRAME 16
END_FUNCTION node_api_final_block

/*
 * L2: the block of the block_id of the ApiRoute x0 into the ApiView x1 (beacon-api.md, Common
 * rules): head_root, head_slot, canonical, head_finalized, is_optimistic, look_index, look_data,
 * and for a block the node keeps look_state and look_state_slot. x0 = 0, or 404 for none. x21 the
 * route, x22 the view, x25 the entry, x26 the slot. Locals: L the Db's slot.
 */
LOCAL_FUNCTION node_api_block
    ENTER 16
    mov     x21, x0
    mov     x22, x1
    mov     x9, #-1
    str     x9, [x22, #ApiView_look_index]
    str     xzr, [x22, #ApiView_look_data]
    str     xzr, [x22, #ApiView_look_state]
    str     xzr, [x22, #ApiView_look_copy]
    ldr     x9, [x21, #ApiRoute_id_kind]
    add     x0, x19, #Node_head_root        /* head */
    cmp     x9, #API_ID_HEAD
    b.eq    4f
    add     x0, x20, #(Store_finalized_checkpoint + 8)  /* finalized */
    cmp     x9, #API_ID_FINALIZED
    b.eq    4f
    cmp     x9, #API_ID_ROOT
    b.ne    3f
    add     x0, x21, #ApiRoute_id_root      /* a root: the node's imported block, else the Db's */
    bl      node_find_block
    cmn     x0, #1
    b.eq    1f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.eq    5f
1:  ldr     x9, [x19, #Node_flags]
    tst     x9, #NODE_FLAG_DB
    b.eq    80f
    ldr     x0, [x19, #Node_db]
    add     x0, x19, x0
    add     x1, x21, #ApiRoute_id_root
    add     x2, sp, #L
    bl      lantern_db_find_root
    ldr     x26, [sp, #L]
    cmn     x26, #1
    b.eq    80f
    add     x0, x21, #ApiRoute_id_root
    b       6f
3:  mov     x26, #0                         /* genesis: the slot 0; a slot */
    cmp     x9, #API_ID_SLOT
    b.ne    31f
    ldr     x26, [x21, #ApiRoute_id_slot]
31: mov     x0, x26
    bl      node_api_below
    cmn     x0, #1
    b.eq    32f
    ldr     x9, [x1, #NodeBlock_slot]
    cmp     x9, x26
    b.ne    80f                             /* an empty slot, or past the head */
    b       5f
32: ldr     x9, [x19, #Node_flags]          /* below the chain's blocks the node keeps: the Db's */
    tst     x9, #NODE_FLAG_DB
    b.eq    80f
    mov     x0, x26
    bl      node_db_slot
    cbz     x0, 80f
    b       6f                              /* DbSlot_root is at 0 */
4:  bl      node_find_block                 /* head, finalized: the block of that root */
    cmn     x0, #1
    b.eq    80f
5:  mov     x25, x1                         /* a block the node keeps */
    str     x0, [x22, #ApiView_look_index]
    add     x0, x22, #ApiView_head_root
    bl      lantern_copy_root
    ldr     x26, [x25, #NodeBlock_slot]
    str     x26, [x22, #ApiView_head_slot]
    ldr     x9, [x25, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
    str     x9, [x22, #ApiView_is_optimistic]
    ldr     x9, [x25, #NodeBlock_state_id]
    str     x9, [x22, #ApiView_look_state]
    str     x26, [x22, #ApiView_look_state_slot]
    ldr     x0, [x25, #NodeBlock_data_id]
    cbnz    x0, 51f
    mov     x0, x25
    bl      node_api_db_ref
51: str     x0, [x22, #ApiView_look_data]
    mov     x0, x25
    bl      node_api_on_chain
    str     x0, [x22, #ApiView_canonical]
    cbz     x0, 52f
    mov     x0, x26
    bl      node_api_final_block
52: STQ     x0, x22, ApiView_head_finalized
    mov     x0, #0
    LEAVE 16
6:  mov     x1, x0                          /* a block of the Db: its root at x0, its slot x26 */
    add     x0, x22, #ApiView_head_root
    bl      lantern_copy_root
    str     x26, [x22, #ApiView_head_slot]
    str     xzr, [x22, #ApiView_is_optimistic]
    mov     x9, #1
    str     x9, [x22, #ApiView_canonical]
    mov     x0, x26
    bl      node_db_block
    str     x0, [x22, #ApiView_look_data]
    mov     x0, x26
    bl      node_api_final_block
    STQ     x0, x22, ApiView_head_finalized
    mov     x0, #0
    LEAVE 16
80: mov     x0, #404
    LEAVE 16
END_FUNCTION node_api_block

/*
 * L2: the state of the state_id of the ApiRoute x0 into the ApiView x1 (beacon-api.md, Common
 * rules): look_state, a state the node keeps, at look_state_slot; head_slot the slot it goes to;
 * head_finalized and is_optimistic. x0 = 0, or 404 for none. x21 the route, x22 the view, x25 the
 * block's entry, x26 the slot, x27 the checkpoint.
 */
LOCAL_FUNCTION node_api_state
    ENTER 0
    mov     x21, x0
    mov     x22, x1
    str     xzr, [x22, #ApiView_look_state]
    str     xzr, [x22, #ApiView_look_copy]
    mov     x9, #-1
    str     x9, [x22, #ApiView_look_index]
    ldr     x9, [x21, #ApiRoute_id_kind]
    cmp     x9, #API_ID_HEAD
    b.ne    1f
    add     x0, x19, #Node_head_root        /* head: its post-state at its slot */
    bl      node_find_block
    cmn     x0, #1
    b.eq    80f
    ldr     x26, [x1, #NodeBlock_slot]
    b       5f
1:  add     x27, x20, #Store_finalized_checkpoint
    cmp     x9, #API_ID_FINALIZED
    b.eq    2f
    add     x27, x20, #Store_justified_checkpoint
    cmp     x9, #API_ID_JUSTIFIED
    b.ne    3f
2:  ldr     x26, [x27]                      /* a checkpoint: at the first slot of its epoch */
    mov     x9, #SLOTS_PER_EPOCH
    mul     x26, x26, x9
    add     x0, x27, #8
    bl      node_find_block                 /* the optimistic status of its block */
    mov     x9, #0
    cmn     x0, #1
    b.eq    21f
    mov     x25, x1
    ldr     x9, [x25, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
21: str     x9, [x22, #ApiView_is_optimistic]
    ldr     x0, [x27]                       /* its NodeCheckpoint's state, else its block's post-state */
    add     x1, x27, #8
    bl      node_find_checkpoint
    cmn     x0, #1
    b.eq    22f
    ldr     x9, [x1, #NodeCheckpoint_state_id]
    cbz     x9, 22f
    str     x9, [x22, #ApiView_look_state]
    str     x26, [x22, #ApiView_look_state_slot]
    b       7f
22: add     x0, x27, #8
    bl      node_find_block
    cmn     x0, #1
    b.eq    80f
    b       5f
3:  cmp     x9, #API_ID_ROOT                /* a state root: none in this version */
    b.eq    80f
    mov     x26, #0                         /* genesis: the slot 0; a slot, at most the store's */
    cmp     x9, #API_ID_SLOT
    b.ne    31f
    ldr     x26, [x21, #ApiRoute_id_slot]
31: mov     x0, x20
    bl      node_store_slot
    cmp     x26, x0
    b.hi    80f
    mov     x0, x26
    bl      node_api_below
    cmn     x0, #1
    b.eq    80f
5:  mov     x25, x1                         /* the block's post-state, again when the node let it go */
    ldr     x9, [x25, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
    str     x9, [x22, #ApiView_is_optimistic]
    ldr     x0, [x25, #NodeBlock_state_id]
    cbnz    x0, 6f
    bl      node_f_slot
    ldr     x9, [x25, #NodeBlock_slot]
    cmn     x0, #1
    b.eq    80f
    cmp     x9, x0
    b.ls    80f
    mov     x0, x25
    bl      node_rebuild
    cbz     x0, 80f
6:  str     x0, [x22, #ApiView_look_state]
    ldr     x9, [x25, #NodeBlock_slot]
    str     x9, [x22, #ApiView_look_state_slot]
7:  str     x26, [x22, #ApiView_head_slot]  /* finalized: at most the first slot of the finalized epoch */
    ldr     x9, [x20, #Store_finalized_checkpoint]
    mov     x10, #SLOTS_PER_EPOCH
    mul     x9, x9, x10
    cmp     x26, x9
    cset    x9, ls
    STQ     x9, x22, ApiView_head_finalized
    mov     x0, #0
    LEAVE 0
80: mov     x0, #404
    LEAVE 0
END_FUNCTION node_api_state

/*
 * L2: the state of the ApiView x0 at its slot (node.md, NODE_EV_API): when head_slot is past
 * look_state_slot, a STATE_COPY of look_state, the copy across the fork boundaries to head_slot,
 * and a SLOTS work of it to head_slot when it is below it; look_state is the copy, look_copy 1.
 * x21 the view, x22 the copy, x25 the copy's slot.
 */
LOCAL_FUNCTION node_api_advance
    ENTER 0
    mov     x21, x0
    ldr     x9, [x21, #ApiView_look_state_slot]
    ldr     x10, [x21, #ApiView_head_slot]
    cmp     x10, x9
    b.ls    9f
    bl      node_new_id
    mov     x22, x0
    mov     x2, x0
    mov     x0, #NODE_ACT_STATE_COPY
    ldr     x1, [x21, #ApiView_look_state]
    bl      node_ids
    mov     x0, x22
    ldr     x1, [x21, #ApiView_look_state]
    ldr     x2, [x21, #ApiView_look_state_slot]
    ldr     x3, [x21, #ApiView_head_slot]
    bl      node_cross
    mov     x22, x0
    ldr     x25, [x21, #ApiView_look_state_slot]    /* the copy's slot: the first of the target's fork, when it crossed one */
    mov     x0, x25
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x26, x0
    ldr     x0, [x21, #ApiView_head_slot]
    add     x1, x19, #Node_config
    bl      node_fork
    cmp     x0, x26
    b.ls    1f
    add     x9, x19, #Node_config
    add     x9, x9, x0, lsl #4
    ldr     x9, [x9]
    mov     x10, #SLOTS_PER_EPOCH
    mul     x9, x9, x10
    cmp     x9, x25
    csel    x25, x9, x25, hi
1:  ldr     x5, [x21, #ApiView_head_slot]
    cmp     x5, x25
    b.ls    2f
    mov     x0, #NODE_WORK_SLOTS
    mov     x1, x22
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    bl      node_work
2:  str     x22, [x21, #ApiView_look_state]
    mov     x9, #1
    str     x9, [x21, #ApiView_look_copy]
9:  LEAVE 0
END_FUNCTION node_api_advance

/*
 * L1: a NODE_WORK_API_ENCODE of the operation x0 for the connection x1 with the answer flags x2,
 * from the lookup in the ApiView x3 (node.md, NODE_EV_API); then a STATE_FREE of the state when it
 * is a copy. x0 = 0, or 404 for a header with neither bytes nor a post-state. Locals: L the view.
 */
LOCAL_FUNCTION node_api_encode
    FRAME 16
    str     x3, [sp, #16]
    ldr     x9, [x3, #ApiView_canonical]
    LDQ     x10, x3, ApiView_head_finalized
    ldr     x11, [x3, #ApiView_is_optimistic]
    orr     x9, x9, x10, lsl #1
    orr     x9, x9, x11, lsl #2
    orr     x5, x0, x2, lsl #8
    mov     x4, x1
    cmp     x0, #API_OP_GET_SPEC            /* getSpec: no state, no bytes, no values */
    b.ne    1f
    mov     x1, #0
    mov     x3, #0
    b       3f
1:  orr     x5, x5, x9, lsl #16
    cmp     x0, #API_OP_GET_BLOCK_HEADER
    b.ne    2f
    ldr     x9, [x3, #ApiView_look_index]   /* getBlockHeader: the block's index + 1, its bytes or post-state */
    add     x9, x9, #1
    orr     x5, x5, x9, lsl #24
    mov     x1, #0
    ldr     x3, [x3, #ApiView_look_data]
    cbnz    x3, 3f
    ldr     x9, [sp, #16]
    ldr     x1, [x9, #ApiView_look_state]
    cbnz    x1, 3f
    mov     x0, #404
    UNFRAME 16
2:  ldr     x9, [x3, #ApiView_head_slot]    /* the others: the state at its slot */
    orr     x5, x5, x9, lsl #24
    ldr     x1, [x3, #ApiView_look_state]
    mov     x3, #0
3:  mov     x0, #NODE_WORK_API_ENCODE
    mov     x2, #0
    bl      node_work
    ldr     x9, [sp, #16]                   /* a copy goes after the work */
    ldr     x10, [x9, #ApiView_look_copy]
    cbz     x10, 9f
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [x9, #ApiView_look_state]
    mov     x2, #0
    bl      node_ids
9:  mov     x0, #0
    UNFRAME 16
END_FUNCTION node_api_encode

/*
 * L2: (connection x0, route x1, answer flags x2) -> x0: a state_id of a root (node.md, NODE_EV_API):
 * a NodeApi entry with API_STREAM_LOOKUP and a NODE_WORK_API_LOOKUP with the head's post-state;
 * 0, or 404 with no head post-state. x21 the route, x25 the flags, x27 the connection. Locals: L
 * the entry's index, L+8 the entry.
 */
LOCAL_FUNCTION node_api_lookup
    ENTER 16
    mov     x27, x0
    mov     x21, x1
    orr     x25, x2, #API_STREAM_LOOKUP
    orr     x25, x25, #API_STREAM_BUSY
    ldr     x9, [x21, #ApiRoute_response]
    cmp     x9, #API_TYPE_SSZ
    b.ne    1f
    orr     x25, x25, #API_STREAM_SSZ
1:  add     x0, x19, #Node_head_root
    bl      node_find_block
    cmn     x0, #1
    b.eq    80f
    ldr     x9, [x1, #NodeBlock_state_id]
    cbz     x9, 80f
    bl      node_api_new
    stp     x0, x1, [sp, #L]
    mov     x0, x1
    mov     x1, #NodeApi__mem
    bl      lantern_zero
    ldr     x1, [sp, #(L + 8)]
    str     x27, [x1, #NodeApi_connection]
    ldr     x9, [x21, #ApiRoute_op]
    str     x9, [x1, #NodeApi_op]
    str     x25, [x1, #NodeApi_flags]
    add     x0, x1, #NodeApi_cursor
    add     x1, x21, #ApiRoute_id_root
    bl      lantern_copy_root
    add     x0, x19, #Node_head_root
    bl      node_find_block
    ldr     x1, [x1, #NodeBlock_state_id]
    mov     x0, #NODE_WORK_API_LOOKUP
    mov     x2, #0
    mov     x3, #0
    mov     x4, x27
    ldr     x5, [sp, #L]
    bl      node_work
    mov     x0, #0
    LEAVE 16
80: mov     x0, #404
    LEAVE 16
END_FUNCTION node_api_lookup

/*
 * L2: the NODE_EV_WORK_DONE x0 of a NODE_WORK_API_LOOKUP (node.md, lantern_node_step): the entry
 * ends; the answer for the state_id of the slot found, or 404. x19 the node, x20 the store, x23 the
 * scratch, x24 the actions. x21 the event, x22 the entry, x25 the flags, x26 the view, x27 the
 * connection, x28 the operation. Locals: L the scratch's size, L+8 the route.
 */
LOCAL_FUNCTION node_api_lookup_done
    ENTER 16
    mov     x21, x0
    ldr     x9, [x21, #NodeAction_arg]
    PART    x10, x11, x19, Node_api
    cmp     x9, x11
    b.hs    99f
    mov     x12, #NodeApi__mem
    madd    x22, x9, x12, x10
    ldr     x27, [x22, #NodeApi_connection]
    cbz     x27, 99f
    ldr     x10, [x21, #NodeAction_target]
    cmp     x27, x10
    b.ne    99f
    ldr     x25, [x22, #NodeApi_flags]
    tst     x25, #API_STREAM_LOOKUP
    b.eq    99f
    ldr     x28, [x22, #NodeApi_op]
    and     x9, x25, #~API_STREAM_OWN       /* the entry ends; it owns no bytes */
    str     x9, [x22, #NodeApi_flags]
    mov     x0, x22
    bl      node_api_end
    tbnz    x25, #5, 99f                    /* API_STREAM_GONE */
    ldr     x9, [x23]                       /* the ApiView, then an ApiRoute, at the end of scratch */
    str     x9, [sp, #L]
    MOVQ    x10, ApiView__size + API_ROUTE_FIXED
    sub     x9, x9, x10
    str     x9, [x23]
    add     x26, x23, x9
    mov     x0, x26
    bl      node_api_view
    MOVQ    x9, ApiView__size
    add     x0, x26, x9
    str     x0, [sp, #(L + 8)]
    mov     x1, #API_ROUTE_FIXED
    bl      lantern_zero
    ldr     x0, [sp, #(L + 8)]
    mov     x9, #API_ROUTE_FIXED
    str     x9, [x0]
    str     x28, [x0, #ApiRoute_op]
    tst     x25, #API_STREAM_SSZ
    mov     x9, #API_TYPE_SSZ
    mov     x10, #API_TYPE_JSON
    csel    x9, x9, x10, ne
    str     x9, [x0, #ApiRoute_response]
    mov     x9, #API_ID_SLOT
    str     x9, [x0, #ApiRoute_id_kind]
    ldr     x9, [x21, #NodeEvent_index]
    str     x9, [x0, #ApiRoute_id_slot]
    mov     x2, #404
    cmn     x9, #1
    b.eq    80f
    mov     x1, x26
    bl      node_api_state
    mov     x2, x0
    cbnz    x0, 80f
    mov     x0, x26
    bl      node_api_advance
    and     x2, x25, #(API_STREAM_CLOSE | API_STREAM_HTTP10)
    cmp     x28, #API_OP_GET_STATE_V2
    b.ne    1f
    mov     x0, x27                         /* getStateV2: a stream */
    ldr     x1, [sp, #(L + 8)]
    mov     x3, x26
    bl      node_api_stream
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
1:  mov     x0, x28                         /* the others: a work */
    mov     x1, x27
    mov     x3, x26
    bl      node_api_encode
    mov     x2, x0
    cbz     x0, 90f
80: mov     x0, x27                         /* an error: with close, or keep-alive for HTTP/1.0 */
    mov     x1, #0
    mov     x3, #API_BODY_ERROR
    and     x4, x25, #API_R_CLOSE
    cbnz    x4, 81f
    tst     x25, #API_STREAM_HTTP10
    mov     x9, #API_R_KEEP
    csel    x4, x9, xzr, ne
81: bl      node_api_send
90: ldr     x9, [sp, #L]
    str     x9, [x23]
99: LEAVE 16
END_FUNCTION node_api_lookup_done

/*
 * (node, work, state_a, scratch, event) -> status: a NODE_WORK_API_LOOKUP of lantern_node_run
 * (node.md): at NodeEvent_index of the event, the slot whose state on the chain of state_a has the
 * root of the NodeApi entry at the work's arg, or 2^64 - 1. x19 the node, x21 the work, x22 the
 * state, x23 the event, x24 the root, x25 the slot, x26 the lowest slot.
 */
LOCAL_FUNCTION node_api_lookup_run
    ENTER 0
    mov     x19, x0
    mov     x21, x1
    mov     x22, x2
    mov     x23, x4
    mov     x9, #-1
    str     x9, [x23, #NodeEvent_index]
    cbz     x22, 98f
    ldr     x9, [x21, #NodeAction_arg]
    PART    x10, x11, x19, Node_api
    cmp     x9, x11
    b.hs    90f
    mov     x12, #NodeApi__mem
    madd    x10, x9, x12, x10
    ldr     x11, [x10, #NodeApi_flags]
    tst     x11, #API_STREAM_LOOKUP
    b.eq    90f
    add     x24, x10, #NodeApi_cursor
    ldr     x0, [x22, #NODE_STATE_SLOT]     /* the state's own root */
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    mov     x0, x22
    LDQ     x1, x19, Node_config + CONFIG_STATE_CACHE
    mov     x2, x3
    add     x3, x23, #NodeEvent_root
    FORK_CALL state_root
    cbnz    x0, 97f
    ldr     x25, [x22, #NODE_STATE_SLOT]
    add     x0, x23, #NodeEvent_root
    mov     x1, x24
    bl      node_api_same_root
    cbnz    x0, 80f
    subs    x26, x25, #SLOTS_PER_HISTORICAL_ROOT    /* then its state_roots, from the slot below it down */
    csel    x26, xzr, x26, lo
1:  cmp     x25, x26
    b.ls    90f
    sub     x25, x25, #1
    and     x9, x25, #(SLOTS_PER_HISTORICAL_ROOT - 1)
    ADDQ    x0, x22, NODE_STATE_STATE_ROOTS
    add     x0, x0, x9, lsl #5
    mov     x1, x24
    bl      node_api_same_root
    cbz     x0, 1b
80: str     x25, [x23, #NodeEvent_index]
90: mov     x0, #LANTERN_OK
    LEAVE 0
97: cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    96f
    mov     x9, #LANTERN_INVALID_ENCODING   /* a state lantern_state_root does not take */
    str     x9, [x23, #NodeEvent_result]
    b       90f
96: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
98: mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 0
END_FUNCTION node_api_lookup_run

/* L0: x0 = 1 when the 32 bytes at x0 and x1 are the same, else 0. Uses x9-x12. */
LOCAL_FUNCTION node_api_same_root
    UNWIND_END_PROLOGUE
    ldp     x9, x10, [x0]
    ldp     x11, x12, [x1]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    8f
    ldp     x9, x10, [x0, #16]
    ldp     x11, x12, [x1, #16]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    cset    x0, eq
    ret
8:  mov     x0, #0
    ret
END_FUNCTION node_api_same_root

/* ---------------------------------------------------------------- Streams (node.md, NodeApi) */

/* L0: x0 = the free NodeApi entries of the node x19: the capacity past the count, and the free ones below it. Uses x9-x12, x16. */
LOCAL_FUNCTION node_api_free
    UNWIND_END_PROLOGUE
    PART    x9, x10, x19, Node_api
    LDQ     x11, x19, Node_p2p_out
    LDQ     x12, x19, Node_api
    sub     x11, x11, x12
    mov     x12, #NodeApi__mem
    udiv    x0, x11, x12
    sub     x0, x0, x10
1:  cbz     x10, 9f
    ldr     x11, [x9, #NodeApi_connection]
    cmp     x11, #0
    cinc    x0, x0, eq
    add     x9, x9, #NodeApi__mem
    sub     x10, x10, #1
    b       1b
9:  ret
END_FUNCTION node_api_free

/* L0: x0 = the index of the NodeApi entry of the connection x0, or 2^64 - 1; x1 = the entry. Uses x9-x12, x16. */
LOCAL_FUNCTION node_api_find
    UNWIND_END_PROLOGUE
    PART    x9, x10, x19, Node_api
    mov     x11, #0
    cbz     x0, 3f
1:  cmp     x11, x10
    b.hs    3f
    ldr     x12, [x9, #NodeApi_connection]
    cmp     x12, x0
    b.eq    4f
    add     x9, x9, #NodeApi__mem
    add     x11, x11, #1
    b       1b
3:  mov     x0, #-1
    ret
4:  mov     x0, x11
    mov     x1, x9
    ret
END_FUNCTION node_api_find

/* L0: x0 = the index of a free NodeApi entry (the first free, else the next; the step checked one is free), x1 = the entry. Uses x9-x12, x16. */
LOCAL_FUNCTION node_api_new
    UNWIND_END_PROLOGUE
    PART    x9, x10, x19, Node_api
    mov     x11, #0
1:  cmp     x11, x10
    b.hs    2f
    ldr     x12, [x9, #NodeApi_connection]
    cbz     x12, 3f
    add     x9, x9, #NodeApi__mem
    add     x11, x11, #1
    b       1b
2:  add     x10, x10, #1
    STQ     x10, x19, Node_api + 8
3:  mov     x0, x11
    mov     x1, x9
    ret
END_FUNCTION node_api_new

/*
 * L1: the end of the stream of the NodeApi entry x0: the entry is free, the api part's count drops
 * past the free entries at its end; with API_STREAM_OWN, a BYTES_FREE of its data, which node_ids
 * gives to another entry that sends the same bytes. Locals: L data, L+8 flags.
 */
LOCAL_FUNCTION node_api_end
    FRAME 32
    ldp     x9, x10, [x0, #NodeApi_flags]
    stp     x10, x9, [sp, #16]
    str     xzr, [x0, #NodeApi_connection]
    PART    x9, x10, x19, Node_api
1:  cbz     x10, 2f
    sub     x11, x10, #1
    mov     x12, #NodeApi__mem
    madd    x12, x11, x12, x9
    ldr     x12, [x12, #NodeApi_connection]
    cbnz    x12, 2f
    mov     x10, x11
    b       1b
2:  STQ     x10, x19, Node_api + 8
    ldr     x9, [sp, #24]
    tbz     x9, #3, 9f                      /* API_STREAM_OWN */
    mov     x0, #NODE_ACT_BYTES_FREE
    ldr     x1, [sp, #16]
    mov     x2, #0
    bl      node_ids
9:  UNFRAME 32
END_FUNCTION node_api_end

/* L1: a NODE_WORK_API_CHUNK of the NodeApi entry x1 at index x0, which takes API_STREAM_BUSY. */
LOCAL_FUNCTION node_api_chunk_work
    FRAME 0
    ldr     x9, [x1, #NodeApi_flags]
    orr     x9, x9, #API_STREAM_BUSY
    str     x9, [x1, #NodeApi_flags]
    mov     x5, x0
    ldr     x3, [x1, #NodeApi_data]
    ldr     x4, [x1, #NodeApi_connection]
    mov     x0, #NODE_WORK_API_CHUNK
    mov     x1, #0
    mov     x2, #0
    bl      node_work
    UNFRAME 0
END_FUNCTION node_api_chunk_work

/* L1: NODE_EV_API_SENT of the connection x0: the next chunk of its stream, unless one is queued. */
LOCAL_FUNCTION node_api_sent
    FRAME 0
    bl      node_api_find
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeApi_flags]
    tbnz    x9, #4, 9f                      /* API_STREAM_BUSY */
    bl      node_api_chunk_work
9:  UNFRAME 0
END_FUNCTION node_api_sent

/* L1: NODE_EV_API_CLOSED of the connection x0: its stream ends, or with a chunk queued takes API_STREAM_GONE. */
LOCAL_FUNCTION node_api_closed
    FRAME 0
    bl      node_api_find
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeApi_flags]
    tbz     x9, #4, 1f
    orr     x9, x9, #API_STREAM_GONE
    str     x9, [x1, #NodeApi_flags]
    b       9f
1:  mov     x0, x1
    bl      node_api_end
9:  UNFRAME 0
END_FUNCTION node_api_closed

/*
 * L2: (connection x0, route x1, flags x2, view x3) -> x0: a stream of getBlockV2 or getStateV2 of
 * the lookup in the view (node.md, NODE_EV_API): 0 once it started, else the status of the error to
 * answer. flags: API_STREAM_CLOSE and API_STREAM_HTTP10. x19 the node, x24 the actions. x21 the
 * data, x25 the route, x26 the view, x27 the connection, x28 the flags. Locals: L the entry's
 * index, L+8 the entry.
 */
LOCAL_FUNCTION node_api_stream
    ENTER 16
    mov     x27, x0
    mov     x25, x1
    mov     x28, x2
    mov     x26, x3
    ldr     x9, [x25, #ApiRoute_response]   /* SSZ, else JSON; the values of the JSON */
    cmp     x9, #API_TYPE_SSZ
    b.ne    1f
    orr     x28, x28, #API_STREAM_SSZ
1:  ldr     x9, [x26, #ApiView_is_optimistic]
    cbz     x9, 2f
    orr     x28, x28, #API_STREAM_OPTIMISTIC
2:  LDQ     x9, x26, ApiView_head_finalized
    cbz     x9, 3f
    orr     x28, x28, #API_STREAM_FINALIZED
3:  ldr     x9, [x25, #ApiRoute_op]
    cmp     x9, #API_OP_GET_STATE_V2
    b.eq    5f
    ldr     x21, [x26, #ApiView_look_data]  /* getBlockV2: the block's bytes */
    cbz     x21, 80f
    b       6f
5:  bl      node_new_id                     /* getStateV2: the state's SSZ bytes, as a new id the stream owns */
    mov     x21, x0
    mov     x0, #NODE_ACT_STATE_BYTES
    mov     x1, #NODE_ACT_STATE_BYTES_SIZE
    bl      node_act
    ldr     x9, [x26, #ApiView_look_state]
    stp     x9, x21, [x0, #16]
    orr     x28, x28, #API_STREAM_OWN
    ldr     x9, [x26, #ApiView_look_copy]   /* a copy goes after its bytes */
    cbz     x9, 6f
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [x26, #ApiView_look_state]
    mov     x2, #0
    bl      node_ids
6:  bl      node_api_new                    /* the entry */
    stp     x0, x1, [sp, #L]
    mov     x0, x1
    mov     x1, #NodeApi__mem
    bl      lantern_zero
    ldr     x0, [x26, #ApiView_head_slot]
    ldr     x1, [sp, #(L + 8)]
    str     x0, [x1, #NodeApi_slot]
    add     x1, x19, #Node_config
    bl      node_fork
    ldr     x1, [sp, #(L + 8)]
    str     x0, [x1, #NodeApi_fork]
    str     x27, [x1, #NodeApi_connection]
    ldr     x9, [x25, #ApiRoute_op]
    str     x9, [x1, #NodeApi_op]
    stp     x28, x21, [x1, #NodeApi_flags]
    ldr     x0, [sp, #L]
    bl      node_api_chunk_work
    mov     x0, #0
    LEAVE 16
80: mov     x0, #404
    LEAVE 16
END_FUNCTION node_api_stream

/*
 * L2: the NODE_EV_WORK_DONE x0 of a NODE_WORK_API_CHUNK (node.md, lantern_node_step). x19 the
 * node, x24 the actions. x21 the event, x22 the entry, x23 the action, x25 the flags.
 */
LOCAL_FUNCTION node_api_chunk_done
    ENTER 0
    mov     x21, x0
    ldr     x9, [x21, #NodeAction_arg]
    PART    x10, x11, x19, Node_api
    cmp     x9, x11
    b.hs    99f
    mov     x12, #NodeApi__mem
    madd    x22, x9, x12, x10
    ldr     x9, [x22, #NodeApi_connection]
    cbz     x9, 99f
    ldr     x10, [x21, #NodeAction_target]
    cmp     x9, x10
    b.ne    99f
    ldr     x25, [x22, #NodeApi_flags]
    and     x25, x25, #~API_STREAM_BUSY
    str     x25, [x22, #NodeApi_flags]
    tbnz    x25, #5, 90f                    /* API_STREAM_GONE: the stream ends */
    ldr     x10, [x21, #NodeEvent_result]
    cbnz    x10, 50f
    ldr     x9, [x21, #NodeEvent_api]       /* valid: the entry takes sent, flags and cursor */
    str     x9, [x22, #NodeApi_sent]
    ldr     x9, [x21, #(NodeEvent_api + 8)]
    and     x9, x9, #~(API_STREAM_BUSY | API_STREAM_OWN)
    and     x10, x25, #API_STREAM_OWN
    orr     x25, x9, x10
    str     x25, [x22, #NodeApi_flags]
    add     x0, x22, #NodeApi_cursor
    add     x1, x21, #(NodeEvent_api + 16)
    mov     x2, #JSON_CURSOR_SIZE
    bl      lantern_copy
    ldr     x9, [x21, #(NodeEvent_api_bytes + 16)]  /* the chunk in a SEND */
    add     x1, x9, #(56 + 7)
    and     x1, x1, #~7
    mov     x0, #NODE_ACT_API_SEND
    bl      node_act
    mov     x23, x0
    ldr     x9, [x22, #NodeApi_connection]
    ubfx    x10, x25, #10, #1               /* last: API_STREAM_DONE */
    stp     x9, x10, [x23, #16]
    ldr     x9, [x23]
    sub     x9, x9, #32
    mov     x10, #24
    stp     x9, x10, [x23, #32]
    ldr     x2, [x21, #(NodeEvent_api_bytes + 16)]
    str     x2, [x23, #48]
    add     x0, x23, #56
    ldr     x9, [x21, #(NodeEvent_api_bytes + 8)]
    add     x1, x21, #NodeEvent_api_bytes
    add     x1, x1, x9
    bl      lantern_copy
    ldr     x9, [x23, #48]                  /* zero bytes to the size */
    add     x0, x23, #56
    add     x0, x0, x9
    ldr     x10, [x23]
    sub     x1, x10, #56
    sub     x1, x1, x9
    bl      lantern_zero
    tbz     x25, #10, 99f                   /* not the last: the next chunk at the next API_SENT */
    tbz     x25, #0, 90f                    /* API_STREAM_CLOSE: a CLOSE after it */
    b       60f
50: tbnz    x25, #6, 60f                    /* another result: before API_STREAM_STARTED the error 500, after it a CLOSE */
    ldr     x0, [x22, #NodeApi_connection]
    mov     x1, #0
    mov     x2, #500
    mov     x3, #API_BODY_ERROR
    and     x4, x25, #API_R_CLOSE           /* API_STREAM_CLOSE is API_R_CLOSE; HTTP/1.0 kept open says so */
    cbnz    x4, 51f
    tst     x25, #API_STREAM_HTTP10
    mov     x9, #API_R_KEEP
    csel    x4, x9, xzr, ne
51: bl      node_api_send
    b       90f
60: mov     x0, #NODE_ACT_API_CLOSE
    mov     x1, #NODE_ACT_API_CLOSE_SIZE
    bl      node_act
    ldr     x9, [x22, #NodeApi_connection]
    str     x9, [x0, #16]
90: mov     x0, x22
    bl      node_api_end
99: LEAVE 0
END_FUNCTION node_api_chunk_done

/* L1: the name of the fork x0 joins the response. */
LOCAL_FUNCTION api_fork_name
    FRAME 0
    ADDRESS x9, api_forks
    add     x9, x9, x0, lsl #4
    ldrb    w1, [x9], #1
    mov     x0, x9
    bl      api_put
    UNFRAME 0
END_FUNCTION api_fork_name

/*
 * L1: the head of a streamed answer (beacon-api.md, Common rules) for the flags at
 * NodeEvent_api + 8 of the event x23 and the fork of the entry x22: with Content-Length x0, or
 * for x0 = 2^64 - 1 Transfer-Encoding: chunked when API_STREAM_CHUNKED is set, else neither.
 * Locals: x0.
 */
LOCAL_FUNCTION api_stream_head
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_ok
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #2, 1f
    API_LIT api_octet
    b       2f
1:  API_LIT api_type
2:  API_LIT api_version
    ldr     x0, [x22, #NodeApi_fork]
    bl      api_fork_name
    API_LIT api_crlf
    ldr     x0, [sp, #16]
    cmn     x0, #1
    b.eq    3f
    API_LIT api_length
    ldr     x0, [sp, #16]
    bl      api_dec
    API_LIT api_crlf
    b       4f
3:  ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #7, 4f
    API_LIT api_chunked
4:  ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #0, 5f
    API_LIT api_close
    b       6f
5:  tbz     x9, #1, 6f
    API_LIT api_keep
6:  API_LIT api_crlf
    UNFRAME 16
END_FUNCTION api_stream_head

/* L0: the 4 lower case hex digits of x0 at x1. Uses x9, x10. */
LOCAL_FUNCTION api_hex4
    UNWIND_END_PROLOGUE
    ADDRESS x9, api_hex
    ubfx    x10, x0, #12, #4
    ldrb    w10, [x9, x10]
    strb    w10, [x1]
    ubfx    x10, x0, #8, #4
    ldrb    w10, [x9, x10]
    strb    w10, [x1, #1]
    ubfx    x10, x0, #4, #4
    ldrb    w10, [x9, x10]
    strb    w10, [x1, #2]
    and     x10, x0, #15
    ldrb    w10, [x9, x10]
    strb    w10, [x1, #3]
    ret
END_FUNCTION api_hex4

/*
 * L1: the JSON of the entry x22's SSZ bytes x21 from the cursor at NodeEvent_api + 16 of the event
 * x23, at the writer's cursor x24 up to x26 less a byte, through the event's ByteList at
 * NodeEvent_api_bytes whose bytes start at x28; then } once it is whole. x0 = 1 when whole, 0
 * when more is to come, 2 for bytes that are no encoding.
 */
LOCAL_FUNCTION api_stream_json
    FRAME 0
    add     x9, x23, #NodeEvent_api_bytes   /* the ByteList: its room to x26 - 1, its bytes to x24 */
    sub     x10, x26, #1
    sub     x10, x10, x9
    mov     x11, #24
    stp     x10, x11, [x9]
    sub     x10, x24, x28
    str     x10, [x9, #16]
    ldr     x9, [x22, #NodeApi_op]
    cmp     x9, #API_OP_GET_STATE_V2
    cset    x0, eq                          /* NODE_JSON_STATE, else NODE_JSON_BLOCK */
    mov     x1, x21
    add     x2, x23, #(NodeEvent_api + 16)
    add     x3, x23, #NodeEvent_api_bytes
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL node_json
    ldr     x9, [x23, #(NodeEvent_api_bytes + 16)]
    add     x24, x28, x9
    cmp     x0, #LANTERN_JSON_MORE
    b.eq    8f
    cbnz    x0, 7f
    API_LIT api_end1
    mov     x0, #1
    UNFRAME 0
7:  mov     x0, #2
    UNFRAME 0
8:  mov     x0, #0
    UNFRAME 0
END_FUNCTION api_stream_json

/*
 * (node, work, data, scratch, event, room) -> status: a NODE_WORK_API_CHUNK of lantern_node_run
 * (node.md): the next chunk of the NodeApi entry at the work's arg, from the SSZ bytes in data,
 * at NodeEvent_api of the event, whose buffer has room bytes. x19 the node, x20 the work, x21
 * data, x22 the entry, x23 the event; the writer's x24-x27 (api_put); x28 where the chunk's bytes
 * start. Locals: L the end of the chunk's room, L+8 the SSZ bytes, L+16 their count, L+24 the
 * body's start, L+32 the head's bytes.
 */
LOCAL_FUNCTION node_api_chunk_run
    ENTER 48
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x23, x4
    ldr     x9, [x20, #NodeAction_arg]      /* the entry */
    PART    x10, x11, x19, Node_api
    cmp     x9, x11
    b.hs    98f
    mov     x12, #NodeApi__mem
    madd    x22, x9, x12, x10
    ldr     x9, [x22, #NodeApi_connection]
    cbz     x9, 98f
    ldr     x9, [x22, #NodeApi_op]
    cmp     x9, #API_OP_GET_BLOCK_V2
    b.eq    1f
    cmp     x9, #API_OP_GET_STATE_V2
    b.ne    98f
1:
    cbz     x21, 98f
    mov     x9, #(NodeEvent_api_bytes + 24) /* the chunk's room: at most NODE_API_CHUNK */
    subs    x10, x5, x9
    b.lo    97f
    and     x10, x10, #~7
    MOVQ    x11, NODE_API_CHUNK
    cmp     x10, x11
    csel    x10, x11, x10, hi
    ldr     x9, [x22, #NodeApi_flags]
    tst     x9, #API_STREAM_STARTED
    mov     x11, #NODE_API_FIRST_ROOM
    mov     x12, #64
    csel    x11, x12, x11, ne
    cmp     x10, x11
    b.lo    97f
    add     x28, x23, #(NodeEvent_api_bytes + 24)
    add     x9, x28, x10
    str     x9, [sp, #L]
    ldr     x9, [x21, #8]                   /* the SSZ bytes */
    add     x9, x21, x9
    ldr     x10, [x21, #16]
    stp     x9, x10, [sp, #(L + 8)]
    ldr     x11, [x22, #NodeApi_op]         /* their slot: a state's at byte 40, a block's at 100 */
    cmp     x11, #API_OP_GET_STATE_V2
    mov     x11, #40
    mov     x12, #100
    csel    x11, x11, x12, eq
    add     x12, x11, #8
    cmp     x10, x12
    b.lo    96f
    ldr     x11, [x9, x11]
    ldr     x12, [x22, #NodeApi_slot]
    cmp     x11, x12
    b.ne    96f
    ldr     x9, [x22, #NodeApi_sent]        /* the entry's sent, flags and cursor go on in the event */
    str     x9, [x23, #NodeEvent_api]
    ldr     x9, [x22, #NodeApi_flags]
    str     x9, [x23, #(NodeEvent_api + 8)]
    add     x0, x23, #(NodeEvent_api + 16)
    add     x1, x22, #NodeApi_cursor
    mov     x2, #JSON_CURSOR_SIZE
    bl      lantern_copy
    mov     x24, x28                        /* the writer */
    mov     x25, #1
    ldr     x26, [sp, #L]
    mov     x27, #0
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #2, 30f
    tbnz    x9, #6, 11f                     /* SSZ: the head first, with Content-Length */
    ldr     x0, [sp, #(L + 16)]
    bl      api_stream_head
11: ldp     x1, x10, [sp, #(L + 8)]         /* then the bytes from sent, as many as fit */
    ldr     x9, [x23, #NodeEvent_api]
    sub     x2, x10, x9
    sub     x11, x26, x24
    cmp     x2, x11
    csel    x2, x11, x2, hi
    add     x1, x1, x9
    add     x9, x9, x2
    str     x9, [x23, #NodeEvent_api]
    mov     x0, x24
    add     x24, x24, x2
    bl      lantern_copy
    ldr     x9, [x23, #NodeEvent_api]
    ldr     x10, [sp, #(L + 16)]
    ldr     x11, [x23, #(NodeEvent_api + 8)]
    orr     x11, x11, #API_STREAM_STARTED
    cmp     x9, x10
    b.ne    12f
    orr     x11, x11, #API_STREAM_DONE
12: str     x11, [x23, #(NodeEvent_api + 8)]
    b       80f
30: tbnz    x9, #6, 40f                     /* JSON, the first chunk: the body after room for the head */
    add     x24, x28, #API_HEAD_ROOM
    str     x24, [sp, #(L + 24)]
    ldr     x9, [sp, #L]
    sub     x26, x9, #7                     /* room for CRLF and the last chunk */
    /* {"version":"<fork>","execution_optimistic":…,"finalized":…,"data": */
    API_LIT api_j_version
    ldr     x0, [x22, #NodeApi_fork]
    bl      api_fork_name
    API_LIT api_j_optimistic
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #8, #1
    bl      api_bool
    API_LIT api_x_finalized
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #9, #1
    bl      api_bool
    API_LIT api_j_data
    bl      api_stream_json
    cmp     x0, #2
    b.eq    96f
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    orr     x9, x9, #API_STREAM_STARTED
    mov     x10, #-1                        /* not whole: chunked, or for HTTP/1.0 no length and a close */
    cbz     x0, 31f
    orr     x9, x9, #API_STREAM_DONE        /* whole: Content-Length */
    ldr     x10, [sp, #(L + 24)]
    sub     x10, x24, x10
    b       33f
31: tst     x9, #API_STREAM_HTTP10
    b.eq    32f
    orr     x9, x9, #API_STREAM_CLOSE
    b       33f
32: orr     x9, x9, #API_STREAM_CHUNKED
33: str     x9, [x23, #(NodeEvent_api + 8)]
    str     x10, [sp, #(L + 32)]
    ldr     x9, [sp, #(L + 24)]             /* the body's bytes */
    sub     x9, x24, x9
    str     x9, [sp, #(L + 16)]
    mov     x25, #0                         /* the head's bytes: a pass that counts */
    mov     x24, #0
    ldr     x0, [sp, #(L + 32)]
    bl      api_stream_head
    add     x0, x28, x24                    /* the body after the head, and a size line when chunked */
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    tst     x9, #API_STREAM_CHUNKED
    add     x10, x0, #6
    csel    x0, x10, x0, ne
    ldr     x1, [sp, #(L + 24)]
    ldr     x2, [sp, #(L + 16)]
    add     x9, x0, x2
    str     x9, [sp, #(L + 24)]             /* now the body's end */
    bl      lantern_copy
    mov     x25, #1                         /* the head */
    mov     x24, x28
    ldr     x26, [sp, #L]
    ldr     x0, [sp, #(L + 32)]
    bl      api_stream_head
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #7, 34f
    ldr     x0, [sp, #(L + 16)]             /* chunked: the size line, then CRLF after the bytes */
    mov     x1, x24
    bl      api_hex4
    mov     w9, #0x0a0d
    strh    w9, [x24, #4]
    ldr     x24, [sp, #(L + 24)]
    API_LIT api_crlf
    b       80f
34: ldr     x24, [sp, #(L + 24)]
    b       80f
40: tbz     x9, #7, 45f                     /* JSON, a later chunk; chunked: a size line, the bytes, CRLF */
    add     x24, x28, #6
    ldr     x9, [sp, #L]
    sub     x26, x9, #7
    bl      api_stream_json
    cmp     x0, #2
    b.eq    96f
    str     x0, [sp, #(L + 32)]
    sub     x0, x24, x28
    sub     x0, x0, #6
    mov     x1, x28
    bl      api_hex4
    mov     w9, #0x0a0d
    strh    w9, [x28, #4]
    ldr     x26, [sp, #L]
    API_LIT api_crlf
    ldr     x9, [sp, #(L + 32)]
    cbz     x9, 80f
    API_LIT api_last_chunk
    b       44f
45: bl      api_stream_json                 /* HTTP/1.0: the bytes alone */
    cmp     x0, #2
    b.eq    96f
    cbz     x0, 80f
44: ldr     x9, [x23, #(NodeEvent_api + 8)]
    orr     x9, x9, #API_STREAM_DONE
    str     x9, [x23, #(NodeEvent_api + 8)]
80: sub     x9, x24, x28                    /* the chunk's ByteList; the event's size covers it */
    add     x10, x9, #(24 + 7)
    and     x10, x10, #~7
    add     x11, x23, #NodeEvent_api_bytes
    mov     x12, #24
    stp     x10, x12, [x11]
    str     x9, [x11, #16]
    add     x12, x10, #NodeEvent_api_bytes
    str     x12, [x23]
    mov     x0, x24
    sub     x1, x10, #24
    sub     x1, x1, x9
    bl      lantern_zero
    mov     x0, #LANTERN_OK
    LEAVE 48
96: mov     x9, #LANTERN_INVALID_ENCODING   /* bytes that are no encoding of the type */
    str     x9, [x23, #NodeEvent_result]
    mov     x9, #NODE_EV_WORK_DONE_SIZE
    str     x9, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 48
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
98: mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 48
END_FUNCTION node_api_chunk_run

    RODATA
    .p2align 3
node_api_rooms:                             /* the room of each text of an ApiIdentity, then 0 */
    .quad 64, 512, 128, 128, 64, 0
