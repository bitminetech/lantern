/*
 * The Beacon API answers, ARM64: in the common object. Requirements: docs/reference/beacon-api.md.
 *
 * The writer: x24 the cursor, x25 the pass (0 counts the bytes, 1 writes them), x26 the end of
 * the room, x27 1 when the room ran out. The functions below keep x24-x27 for it.
 */

    RODATA
.include "api_text.inc"

.set API_HEALTH, 0                          /* the routes */
.set API_IDENTITY, 1
.set API_VERSION, 2
.set API_SYNCING, 3
.set API_PEER_COUNT, 4
.set API_GENESIS, 5
.set API_HEADERS, 6
.set API_FINALITY, 7
.set API_ERROR, 8                           /* the code in the locals */

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

/* L1: the text field at x0 of the view (its length, then its bytes), in quotes. Locals: x0. */
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

/*
 * L1: the body of the route x28 for the view x22: the JSON of beacon-api.md, or an error body
 * with the code at [x0]. Locals: the code.
 */
LOCAL_FUNCTION api_body
    FRAME 16
    str     x0, [sp, #16]
    cmp     x28, #API_ERROR
    b.ne    1f
    /* {"code":<n>,"message":"<m>"} */
    API_LIT api_e_code
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      api_dec
    API_LIT api_e_message
    ldr     x9, [sp, #16]
    ldr     x9, [x9]
    cmp     x9, #400
    b.ne    11f
    API_LIT api_m400
    b       12f
11: cmp     x9, #405
    b.ne    13f
    API_LIT api_m405
    b       12f
13: API_LIT api_m404
12: API_LIT api_e_end
    UNFRAME 16
1:  cmp     x28, #API_IDENTITY
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
2:  cmp     x28, #API_VERSION
    b.ne    3f
    API_LIT api_v_version
    add     x0, x22, #ApiView_version
    bl      api_text
    API_LIT api_end2
    UNFRAME 16
3:  cmp     x28, #API_SYNCING
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
4:  cmp     x28, #API_PEER_COUNT
    b.ne    5f
    API_LIT api_c_connected
    ldr     x0, [x22, #ApiView_peers]
    bl      api_qdec
    API_LIT api_c_end
    UNFRAME 16
5:  cmp     x28, #API_GENESIS
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
6:  cmp     x28, #API_HEADERS
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
7:  cmp     x28, #API_FINALITY
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

/* L0: x0 = 1 when the x1 bytes at x0 are the x3 bytes at x2, else 0. Uses x9, x10. */
LOCAL_FUNCTION api_same
    UNWIND_END_PROLOGUE
    cmp     x1, x3
    b.ne    2f
1:  cbz     x1, 3f
    ldrb    w9, [x0], #1
    ldrb    w10, [x2], #1
    cmp     w9, w10
    b.ne    2f
    sub     x1, x1, #1
    b       1b
2:  mov     x0, #0
    ret
3:  mov     x0, #1
    ret
END_FUNCTION api_same

/* x0 = 1 when the path (x20 + [L + 32], [L + 40] bytes) is the text at label. */
.macro API_PATH_IS label
    ldp     x9, x1, [sp, #(L + 32)]
    add     x0, x20, x9
    ADDRESS x2, \label
    mov     x3, #\label\()_len
    bl      api_same
.endm

/*
 * (request, view, out): docs/reference/beacon-api.md. x19 request, x20 its bytes, x21 their count,
 * x22 view, x23 out, x24-x27 the writer, x28 the route. Locals: L the code, L+8 1 for a code with
 * no reason, L+16 the query's start, L+24 its length, L+32 the path's start, L+40 its length,
 * L+48 the body's length, L+56 the end of the request line.
 */
FUNCTION lantern_api_answer
    ENTER 64
    mov     x19, x0
    mov     x22, x1
    mov     x23, x2
    ldr     x9, [x19, #8]
    add     x20, x19, x9
    ldr     x21, [x19, #16]
    mov     x9, #0                          /* the end of the head: CR LF CR LF */
1:  add     x10, x9, #4
    cmp     x10, x21
    b.hi    90f
    ldr     w11, [x20, x9]
    MOVQ    x12, 0x0a0d0a0d
    cmp     w11, w12
    b.eq    2f
    add     x9, x9, #1
    b       1b
2:  mov     x9, #0                          /* the end of the request line */
3:  ldrh    w11, [x20, x9]
    mov     w12, #0x0a0d
    cmp     w11, w12
    b.eq    4f
    add     x9, x9, #1
    b       3b
4:  str     x9, [sp, #(L + 56)]
    str     xzr, [sp, #(L + 8)]
    mov     x28, #API_ERROR
    mov     x10, #400
    str     x10, [sp, #L]
    mov     x0, #0                          /* the method: visible bytes, then a space */
    ldr     x1, [sp, #(L + 56)]
    bl      api_token_at
    cbz     x0, 50f
    mov     x13, x0                         /* its length */
    add     x14, x0, #1                     /* the target */
    mov     x0, x14
    ldr     x1, [sp, #(L + 56)]
    bl      api_token_at
    cbz     x0, 50f
    add     x15, x14, x0                    /* the space after the target */
    ldr     x9, [sp, #(L + 56)]             /* then " HTTP/1." and a digit, to the end of the line */
    sub     x9, x9, x15
    cmp     x9, #(api_version_prefix_len + 1)
    b.ne    50f
    stp     x13, x14, [sp, #(L + 16)]       /* the method's length and the target, kept a moment */
    str     x15, [sp, #(L + 40)]
    add     x0, x20, x15
    mov     x1, #api_version_prefix_len
    ADDRESS x2, api_version_prefix
    mov     x3, #api_version_prefix_len
    bl      api_same
    cbz     x0, 50f
    ldr     x15, [sp, #(L + 40)]
    add     x9, x15, #api_version_prefix_len
    ldrb    w9, [x20, x9]
    sub     w9, w9, #0x30
    cmp     w9, #9
    b.hi    50f
    ldp     x13, x14, [sp, #(L + 16)]       /* GET only */
    mov     x10, #405
    str     x10, [sp, #L]
    mov     x0, x20
    mov     x1, x13
    ADDRESS x2, api_get
    mov     x3, #api_get_len
    bl      api_same
    cbz     x0, 50f
    ldp     x13, x14, [sp, #(L + 16)]       /* the path and the query: split at the first ? */
    ldr     x15, [sp, #(L + 40)]
    mov     x9, x14
5:  cmp     x9, x15
    b.hs    6f
    ldrb    w10, [x20, x9]
    cmp     w10, #0x3f
    b.eq    6f
    add     x9, x9, #1
    b       5b
6:  sub     x10, x9, x14
    stp     x14, x10, [sp, #(L + 32)]
    add     x11, x9, #1
    subs    x12, x15, x11
    csel    x12, xzr, x12, lo
    stp     x11, x12, [sp, #(L + 16)]
    mov     x10, #404
    str     x10, [sp, #L]
    API_PATH_IS api_p_health
    cbnz    x0, 30f
    mov     x28, #API_IDENTITY
    API_PATH_IS api_p_identity
    cbnz    x0, 49f
    mov     x28, #API_VERSION
    API_PATH_IS api_p_version
    cbnz    x0, 49f
    mov     x28, #API_SYNCING
    API_PATH_IS api_p_syncing
    cbnz    x0, 49f
    mov     x28, #API_PEER_COUNT
    API_PATH_IS api_p_peer_count
    cbnz    x0, 49f
    mov     x28, #API_GENESIS
    API_PATH_IS api_p_genesis
    cbnz    x0, 49f
    mov     x28, #API_FINALITY
    API_PATH_IS api_p_finality
    cbnz    x0, 49f
    mov     x28, #API_ERROR
    ldp     x9, x10, [sp, #(L + 32)]        /* the headers of the head: head, or its root in hex */
    cmp     x10, #api_p_headers_len
    b.lo    50f
    add     x0, x20, x9
    mov     x1, #api_p_headers_len
    ADDRESS x2, api_p_headers
    mov     x3, #api_p_headers_len
    bl      api_same
    cbz     x0, 50f
    ldp     x9, x10, [sp, #(L + 32)]
    add     x9, x9, #api_p_headers_len
    sub     x10, x10, #api_p_headers_len
    add     x0, x20, x9
    mov     x1, x10
    ADDRESS x2, api_head
    mov     x3, #api_head_len
    bl      api_same
    cbnz    x0, 7f
    ldp     x9, x10, [sp, #(L + 32)]        /* 0x and 64 lower case hex digits of head_root */
    add     x9, x9, #api_p_headers_len
    sub     x10, x10, #api_p_headers_len
    cmp     x10, #66
    b.ne    50f
    add     x9, x20, x9
    ldrh    w11, [x9]
    mov     w12, #0x7830                    /* 0x */
    cmp     w11, w12
    b.ne    50f
    add     x9, x9, #2
    ADDRESS x13, api_hex
    mov     x10, #0
8:  cmp     x10, #32
    b.hs    7f
    add     x11, x22, #ApiView_head_root
    ldrb    w11, [x11, x10]
    lsr     w12, w11, #4
    ldrb    w12, [x13, x12]
    ldrb    w14, [x9], #1
    cmp     w12, w14
    b.ne    50f
    and     w12, w11, #15
    ldrb    w12, [x13, x12]
    ldrb    w14, [x9], #1
    cmp     w12, w14
    b.ne    50f
    add     x10, x10, #1
    b       8b
7:  mov     x28, #API_HEADERS
    b       49f
30: mov     x28, #API_HEALTH                /* health: 200, or 206 or syncing_status while not ready */
    ldp     x11, x12, [sp, #(L + 16)]
    mov     x13, #0                         /* the query's code, or 0 */
    cbz     x12, 32f
    mov     x28, #API_ERROR
    mov     x10, #400
    str     x10, [sp, #L]
    cmp     x12, #(api_q_status_len + 1)
    b.lo    50f
    add     x0, x20, x11
    mov     x1, #api_q_status_len
    ADDRESS x2, api_q_status
    mov     x3, #api_q_status_len
    bl      api_same
    cbz     x0, 50f
    ldp     x11, x12, [sp, #(L + 16)]
    add     x0, x20, x11
    add     x0, x0, #api_q_status_len
    add     x1, x20, x11
    add     x1, x1, x12
    bl      api_number
    cbnz    x0, 50f
    cmp     x1, #100
    b.lo    50f
    cmp     x1, #599
    b.hi    50f
    mov     x13, x1
    mov     x28, #API_HEALTH
32: mov     x10, #200
    ldr     x9, [x22, #ApiView_is_syncing]
    ldr     x11, [x22, #ApiView_is_optimistic]
    orr     x9, x9, x11
    ldr     x11, [x22, #ApiView_el_offline]
    orr     x9, x9, x11
    cbz     x9, 33f
    mov     x10, #206
    cbz     x13, 33f
    mov     x10, x13
    mov     x9, #1
    str     x9, [sp, #(L + 8)]
33: str     x10, [sp, #L]
    b       50f
49: mov     x10, #200
    str     x10, [sp, #L]
50: mov     x25, #0                         /* the body's length */
    mov     x24, #0
    mov     x27, #0
    cmp     x28, #API_HEALTH
    b.eq    51f
    add     x0, sp, #L
    bl      api_body
51: str     x24, [sp, #(L + 48)]
    mov     x25, #1                         /* the response */
    add     x24, x23, #24
    ldr     x9, [x23]
    add     x26, x23, x9
    API_LIT api_http
    ldr     x0, [sp, #L]
    bl      api_dec
    ldr     x9, [sp, #(L + 8)]
    cbz     x9, 52f
    API_LIT api_rnone
    b       59f
52: ldr     x9, [sp, #L]
    cmp     x9, #200
    b.ne    53f
    API_LIT api_r200
    b       59f
53: cmp     x9, #206
    b.ne    54f
    API_LIT api_r206
    b       59f
54: cmp     x9, #400
    b.ne    55f
    API_LIT api_r400
    b       59f
55: cmp     x9, #405
    b.ne    56f
    API_LIT api_r405
    b       59f
56: API_LIT api_r404
59: ldr     x9, [sp, #(L + 48)]
    cbz     x9, 60f
    API_LIT api_type
60: API_LIT api_length
    ldr     x0, [sp, #(L + 48)]
    bl      api_dec
    API_LIT api_close
    cmp     x28, #API_HEALTH
    b.eq    61f
    add     x0, sp, #L
    bl      api_body
61: cbnz    x27, 91f
    add     x9, x23, #24
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    mov     x0, #LANTERN_OK
    LEAVE 64
90: mov     x0, #LANTERN_HTTP_MORE
    LEAVE 64
91: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_api_answer

/*
 * L0: x0 = the length of the token at x0 of the request bytes x20 (visible bytes 0x21 to 0x7e)
 * when a space follows it before x1, the end of the request line; else 0. Uses x9-x11.
 */
LOCAL_FUNCTION api_token_at
    UNWIND_END_PROLOGUE
    mov     x9, x0
1:  cmp     x9, x1
    b.hs    8f
    ldrb    w10, [x20, x9]
    sub     w11, w10, #0x21
    cmp     w11, #(0x7e - 0x21)
    b.hi    2f
    add     x9, x9, #1
    b       1b
2:  cmp     w10, #0x20
    b.ne    8f
    subs    x0, x9, x0
    ret
8:  mov     x0, #0
    ret
END_FUNCTION api_token_at

/* L0: x0 = 0 and x1 = the u64 of the decimal digits x0 to x1, one or more; else x0 = 1. Uses x9-x12. */
LOCAL_FUNCTION api_number
    UNWIND_END_PROLOGUE
    cmp     x0, x1
    b.hs    9f
    mov     x9, #0
1:  cmp     x0, x1
    b.hs    8f
    ldrb    w10, [x0], #1
    sub     w10, w10, #0x30
    cmp     w10, #9
    b.hi    9f
    mov     x11, #10
    umulh   x12, x9, x11
    cbnz    x12, 9f
    mul     x9, x9, x11
    adds    x9, x9, x10
    b.cs    9f
    b       1b
8:  mov     x1, x9
    mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION api_number
