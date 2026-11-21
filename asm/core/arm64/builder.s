/*
 * The builder of the node, ARM64: in the common object. Requirements: docs/reference/node.md (the
 * builder calls) and beacon-api.md (registerValidator).
 */

    RODATA
bld_post_validators:
    .ascii  "POST /eth/v1/builder/validators HTTP/1.1\r\nHost: "
bld_post_validators_len = . - bld_post_validators
bld_head_json:
    .ascii  "\r\nAccept: application/json\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: "
bld_head_json_len = . - bld_head_json
bld_head_end:
    .ascii  "\r\n\r\n"
bld_head_end_len = . - bld_head_end
bld_reg_1:
    .ascii  "{\"message\":{\"fee_recipient\":\"0x"
bld_reg_1_len = . - bld_reg_1
bld_reg_2:
    .ascii  "\",\"gas_limit\":\""
bld_reg_2_len = . - bld_reg_2
bld_reg_3:
    .ascii  "\",\"timestamp\":\""
bld_reg_3_len = . - bld_reg_3
bld_reg_4:
    .ascii  "\",\"pubkey\":\"0x"
bld_reg_4_len = . - bld_reg_4
bld_reg_5:
    .ascii  "\"},\"signature\":\"0x"
bld_reg_5_len = . - bld_reg_5
bld_reg_6:
    .ascii  "\"}"
bld_reg_6_len = . - bld_reg_6
/*
 * The bytes of a registration's JSON other than its two numbers (the texts, 2 hex digits a byte of
 * 20 + 48 + 96), and of the request's head other than the host and Content-Length's digits.
 */
.set BLD_REG_FIXED, 423
.set BLD_HEAD_FIXED, 147
.if (bld_reg_1_len + bld_reg_2_len + bld_reg_3_len + bld_reg_4_len + bld_reg_5_len + bld_reg_6_len + 2 * (20 + 48 + 96) != BLD_REG_FIXED) || (bld_post_validators_len + bld_head_json_len + bld_head_end_len != BLD_HEAD_FIXED)
.error "a builder text's length is wrong"
.endif
bld_get_header:
    .ascii  "GET /eth/v1/builder/header/"
bld_get_header_len = . - bld_get_header
bld_get_0x:
    .ascii  "/0x"
bld_get_0x_len = . - bld_get_0x
bld_get_http:
    .ascii  " HTTP/1.1\r\nHost: "
bld_get_http_len = . - bld_get_http
bld_get_end:
    .ascii  "\r\nAccept: application/json\r\nConnection: close\r\n\r\n"
bld_get_end_len = . - bld_get_end
bld_version:
    .ascii  "version"
bld_data:
    .ascii  "data"
/* The bytes of a getHeader request other than the slot's digits and the host (2 hex digits a byte of the hash and the key). */
.set BLD_GET_FIXED, 259
.if bld_get_header_len + 2 * bld_get_0x_len + bld_get_http_len + bld_get_end_len + 2 * (32 + 48) != BLD_GET_FIXED
.error "the getHeader request's length is wrong"
.endif
bld_hex_digits:
    .ascii  "0123456789abcdef"

/* L0: x0 = the count of decimal digits of x0. Uses x9, x10. */
LOCAL_FUNCTION bld_digits
    UNWIND_END_PROLOGUE
    mov     x9, #1
    mov     x10, #10
1:  cmp     x0, x10
    b.lo    2f
    udiv    x0, x0, x10
    add     x9, x9, #1
    b       1b
2:  mov     x0, x9
    ret
END_FUNCTION bld_digits

/* L0: x0 = the cursor x0 past the decimal digits of x1, written there. Uses x9-x13. */
LOCAL_FUNCTION bld_dec
    UNWIND_END_PROLOGUE
    mov     x9, #1                          /* the digits */
    mov     x10, #10
    mov     x11, x1
1:  cmp     x11, x10
    b.lo    2f
    udiv    x11, x11, x10
    add     x9, x9, #1
    b       1b
2:  add     x0, x0, x9
    mov     x11, x0
3:  udiv    x12, x1, x10                    /* from the last digit back */
    msub    x13, x12, x10, x1
    add     x13, x13, #'0'
    strb    w13, [x11, #-1]!
    mov     x1, x12
    subs    x9, x9, #1
    b.ne    3b
    ret
END_FUNCTION bld_dec

/* L0: x0 = the cursor x0 past the lower case hex digits of the x2 bytes at x1, written there. Uses x9-x12. */
LOCAL_FUNCTION bld_hex
    UNWIND_END_PROLOGUE
    ADDRESS x9, bld_hex_digits
1:  cbz     x2, 2f
    ldrb    w10, [x1], #1
    lsr     w11, w10, #4
    and     w10, w10, #15
    ldrb    w11, [x9, x11]
    ldrb    w12, [x9, x10]
    strb    w11, [x0], #1
    strb    w12, [x0], #1
    sub     x2, x2, #1
    b       1b
2:  ret
END_FUNCTION bld_hex

/* L1: x0 = the cursor x0 past the x2 bytes at x1, copied there. */
LOCAL_FUNCTION bld_put
    FRAME 16
    str     x0, [sp, #16]
    str     x2, [sp, #24]
    bl      lantern_copy
    ldp     x0, x2, [sp, #16]
    add     x0, x0, x2
    UNFRAME 16
END_FUNCTION bld_put

/*
 * L0: x0 = the index of a free entry of builder_calls (node.md, the builder calls), now of the kind
 * x0, the NodeApi entry x1 and time_ms; 2^64 - 1 with none free. x19 the node. Uses x9-x12, x16.
 */
LOCAL_FUNCTION node_builder_call
    UNWIND_END_PROLOGUE
    ADDQ    x9, x19, Node_builder_calls
    mov     x10, #0
1:  cmp     x10, #NODE_BUILDER_CALLS
    b.hs    8f
    ldr     x11, [x9]
    cbz     x11, 2f
    add     x9, x9, #NODE_BUILDER_CALL_SIZE
    add     x10, x10, #1
    b       1b
2:  ldr     x12, [x19, #Node_time_ms]
    stp     x0, x1, [x9]
    str     x12, [x9, #16]
    mov     x0, x10
    ret
8:  mov     x0, #-1
    ret
END_FUNCTION node_builder_call

/*
 * L2: the NODE_EV_BUILDER x21 (node.md, the builder calls): a header call still awaited by its
 * produceBlockV3 entry ends there, the answer's bytes in a NODE_ACT_BYTES_PUT to a new id at
 * PRODUCE_BID when the call did not fail and the actions have room; then the call's entry goes
 * free. x19 the node, x24 the actions; x22 the call, x23 the failure bit, x25 the call's entry,
 * x26 the NodeApi entry.
 */
LOCAL_FUNCTION node_builder_event
    ENTER 0
    ldr     x9, [x21, #16]
    and     x22, x9, #255
    ubfx    x23, x9, #8, #1
    cmp     x22, #NODE_BUILDER_CALLS
    b.hs    9f
    ADDQ    x10, x19, Node_builder_calls
    mov     x11, #NODE_BUILDER_CALL_SIZE
    madd    x25, x22, x11, x10
    ldr     x9, [x25]                       /* a header call: to its entry, when that waits for it */
    cmp     x9, #NODE_BUILDER_HEADER
    b.ne    8f
    ldr     x9, [x25, #8]
    PART    x10, x11, x19, Node_api
    cmp     x9, x11
    b.hs    8f
    mov     x12, #NodeApi__mem
    madd    x26, x9, x12, x10
    ldr     x9, [x26, #NodeApi_connection]
    cbz     x9, 8f
    ldr     x9, [x26, #NodeApi_op]
    cmp     x9, #API_OP_PRODUCE_BLOCK_V3
    b.ne    8f
    ldr     x9, [x26, #(NodeApi_cursor + PRODUCE_CALL)]
    add     x10, x22, #1
    cmp     x9, x10
    b.ne    8f
    str     xzr, [x26, #(NodeApi_cursor + PRODUCE_CALL)]
    cbnz    x23, 8f
    ldr     x9, [x21, #(24 + 16)]           /* the answer's bytes */
    add     x0, x9, #(48 + 7)
    bl      node_room
    cbz     x0, 8f
    add     x0, x21, #24
    bl      node_put
    str     x0, [x26, #(NodeApi_cursor + PRODUCE_BID)]
8:  str     xzr, [x25]
9:  LEAVE 0
END_FUNCTION node_builder_event

/*
 * L2: on the way into NODE_PRODUCE_PAYLOAD of the produceBlockV3 entry x0 (node.md, Block
 * production), the event x1 of its PRODUCE_CHECK and the head's block_hash at x2: with
 * NODE_FLAG_BUILDER, a NODE_BUILDER_HEADER call of its slot, the hash and the pubkey of the
 * proposer's NodeProposer entry, when builder_boost_factor is not 0, the entry has registered 1,
 * the head's NodeBlock is not NOT_VALIDATED and the check says the chain is healthy; the entry
 * keeps the call + 1 and the registration's fee recipient. None with no free call or no room in
 * the actions. x21 the entry, x22 the event, x23 the hash, x25 the NodeProposer, x27 the
 * request's bytes. Locals: L the call.
 */
LOCAL_FUNCTION node_produce_header
    ENTER 16
    mov     x21, x0
    mov     x22, x1
    mov     x23, x2
    ldr     x9, [x19, #Node_flags]
    tbz     x9, #11, 9f                     /* NODE_FLAG_BUILDER */
    ldr     x9, [x21, #(NodeApi_cursor + PRODUCE_BOOST)]
    cbz     x9, 9f
    ldr     x9, [x22, #(NodeEvent_root + 8)]
    cbz     x9, 9f
    ldr     x10, [x22, #NodeEvent_root]     /* the proposer's registration */
    PART    x25, x11, x19, Node_proposers
1:  cbz     x11, 9f
    ldr     x12, [x25, #NodeProposer_validator_index]
    cmp     x12, x10
    b.ne    2f
    ldr     x12, [x25, #NodeProposer_registered]
    cbnz    x12, 3f
2:  add     x25, x25, #NodeProposer__mem
    sub     x11, x11, #1
    b       1b
3:  add     x0, x19, #Node_head_root        /* the head is not optimistic */
    bl      node_find_block
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    b.eq    9f
    ldr     x0, [x21, #NodeApi_slot]        /* the request's bytes */
    bl      bld_digits
    LDQ     x9, x19, Node_builder_host_len
    add     x27, x0, x9
    add     x27, x27, #BLD_GET_FIXED
    add     x0, x27, #(48 + 7)
    bl      node_room
    cbz     x0, 9f
    PART    x9, x10, x19, Node_api
    sub     x1, x21, x9
    mov     x10, #NodeApi__mem
    udiv    x1, x1, x10
    mov     x0, #NODE_BUILDER_HEADER
    bl      node_builder_call
    cmn     x0, #1
    b.eq    9f
    str     x0, [sp, #L]
    add     x9, x0, #1
    str     x9, [x21, #(NodeApi_cursor + PRODUCE_CALL)]
    add     x0, x21, #(NodeApi_cursor + PRODUCE_FEE)
    add     x1, x25, #NodeProposer_registration_fee_recipient
    mov     x2, #20
    bl      lantern_copy
    add     x1, x27, #(48 + 7)
    and     x1, x1, #~7
    mov     x0, #NODE_ACT_BUILDER
    bl      node_act
    ldr     x9, [sp, #L]
    str     x9, [x0, #16]
    ldr     x9, [x0]
    sub     x9, x9, #24
    mov     x10, #24
    stp     x9, x10, [x0, #24]
    str     x27, [x0, #40]
    add     x0, x0, #48
    ADDRESS x1, bld_get_header
    mov     x2, #bld_get_header_len
    bl      bld_put
    ldr     x1, [x21, #NodeApi_slot]
    bl      bld_dec
    ADDRESS x1, bld_get_0x
    mov     x2, #bld_get_0x_len
    bl      bld_put
    mov     x1, x23
    mov     x2, #32
    bl      bld_hex
    ADDRESS x1, bld_get_0x
    mov     x2, #bld_get_0x_len
    bl      bld_put
    add     x1, x25, #NodeProposer_pubkey
    mov     x2, #48
    bl      bld_hex
    ADDRESS x1, bld_get_http
    mov     x2, #bld_get_http_len
    bl      bld_put
    ADDQ    x1, x19, Node_builder_host
    LDQ     x2, x19, Node_builder_host_len
    bl      bld_put
    ADDRESS x1, bld_get_end
    mov     x2, #bld_get_end_len
    bl      bld_put
9:  LEAVE 16
END_FUNCTION node_produce_header

/* L0: x0 = 1 when the x2 bytes at x1 are the x3 bytes at x0, else 0. Uses x9-x10. */
LOCAL_FUNCTION bld_same
    UNWIND_END_PROLOGUE
    cmp     x2, x3
    b.ne    8f
1:  cbz     x2, 9f
    ldrb    w9, [x0], #1
    ldrb    w10, [x1], #1
    cmp     w9, w10
    b.ne    8f
    sub     x2, x2, #1
    b       1b
9:  mov     x0, #1
    ret
8:  mov     x0, #0
    ret
END_FUNCTION bld_same

/*
 * L2: (answer x0, scratch x1, fork x2) -> x0: the JSON text of the bid in a builder's getHeader
 * answer (node.md, NODE_WORK_PRODUCE_BID): lantern_http_parse_response with eof 1, the body
 * unchunked at the end of scratch, whose size drops below it (the caller restores it); status
 * 200; the body an object whose first member version is a string, the fork's name, and whose
 * first member data is a value. LANTERN_OK with x1 the data's text and x2 its bytes; else
 * LANTERN_INVALID_HTTP, LANTERN_NO_BID, LANTERN_INVALID_JSON, LANTERN_INVALID_BID or
 * LANTERN_BUFFER_TOO_SMALL. x19 the body's end (the JSON scan's), x20 scratch, x21 the fork, x22
 * the body, x23 the version's text or 0, x24 its bytes, x25 the data or 0, x26 its end, x27 the
 * answer. Locals: L the HttpResponse (16), L+16 eof.
 */
LOCAL_FUNCTION node_bid_data
    ENTER 32
    mov     x27, x0
    mov     x20, x1
    mov     x21, x2
    ldr     x9, [x27, #16]                  /* the body: at most the answer's bytes */
    add     x9, x9, #(24 + 7)
    and     x9, x9, #~7
    ldr     x10, [x20]
    subs    x10, x10, x9
    b.lo    98f
    cmp     x10, #64
    b.lo    98f
    str     x10, [x20]
    add     x22, x20, x10
    mov     x11, #24
    stp     x9, x11, [x22]
    str     xzr, [x22, #16]
    mov     x9, #1
    str     x9, [sp, #(L + 16)]
    mov     x0, x27
    add     x1, sp, #(L + 16)
    mov     x2, x22
    add     x3, sp, #L
    bl      lantern_http_parse_response
    cbnz    x0, 97f
    ldr     x9, [sp, #L]
    cmp     x9, #200
    b.ne    96f
    ldr     x9, [x22, #8]                   /* the body's object: its members */
    add     x0, x22, x9
    ldr     x10, [x22, #16]
    add     x19, x0, x10
    mov     x23, #0
    mov     x25, #0
    bl      jws
    cmp     x0, x19
    b.hs    95f
    ldrb    w9, [x0], #1
    cmp     w9, #'{'
    b.ne    95f
    mov     x1, #1
1:  bl      jmember
    cbz     x0, 95f
    cbnz    x3, 5f
    stp     x1, x2, [sp, #L]                /* the name */
    mov     x3, #7
    mov     x26, x0
    mov     x0, x1
    ADDRESS x1, bld_version
    bl      bld_same
    mov     x9, x0
    mov     x0, x26
    cbz     x9, 2f
    cbnz    x23, 2f
    bl      jstring                         /* version: a string with no escape */
    cbz     x0, 95f
    cbnz    x3, 95f
    mov     x23, x1
    mov     x24, x2
    mov     x1, #0
    b       1b
2:  ldp     x1, x2, [sp, #L]
    mov     x3, #4
    mov     x26, x0
    mov     x0, x1
    ADDRESS x1, bld_data
    bl      bld_same
    mov     x9, x0
    mov     x0, x26
    cbz     x9, 3f
    cbnz    x25, 3f
    mov     x25, x0                         /* data: its text */
    bl      jskip
    cbz     x0, 95f
    mov     x26, x0
    mov     x1, #0
    b       1b
3:  bl      jskip                           /* another member: skipped */
    cbz     x0, 95f
    mov     x1, #0
    b       1b
5:  bl      jws                             /* nothing after the object */
    cmp     x0, x19
    b.ne    95f
    cbz     x23, 95f
    cbz     x25, 95f
    ADDRESS x9, api_forks                   /* version: the fork's name */
    add     x9, x9, x21, lsl #4
    ldrb    w3, [x9], #1
    mov     x0, x9
    mov     x1, x23
    mov     x2, x24
    bl      bld_same
    cbz     x0, 94f
    mov     x0, #LANTERN_OK
    mov     x1, x25
    sub     x2, x26, x25
    LEAVE 32
94: mov     x0, #LANTERN_INVALID_BID
    LEAVE 32
95: mov     x0, #LANTERN_INVALID_JSON
    LEAVE 32
96: mov     x0, #LANTERN_NO_BID
    LEAVE 32
97: mov     x0, #LANTERN_INVALID_HTTP
    LEAVE 32
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION node_bid_data

/* L0: x0 = the bytes of the JSON of the SignedValidatorRegistrationV1 at x0 (180 bytes). Uses x9-x12. */
LOCAL_FUNCTION bld_reg_len
    FRAME 16
    str     x0, [sp, #16]
    ldr     x0, [x0, #20]                   /* gas_limit */
    bl      bld_digits
    mov     x12, x0
    ldr     x0, [sp, #16]
    ldr     x0, [x0, #28]                   /* timestamp */
    str     x12, [sp, #24]
    bl      bld_digits
    ldr     x12, [sp, #24]
    add     x0, x0, x12
    add     x0, x0, #BLD_REG_FIXED
    UNFRAME 16
END_FUNCTION bld_reg_len

/*
 * L1: the cursor x0 past the JSON of the SignedValidatorRegistrationV1 at x1, written there
 * (node.md, NODE_WORK_API_SUBMIT of registerValidator). x20 the registration (callee-saved by
 * the caller's frame: kept in the locals). Locals: the cursor, the registration.
 */
LOCAL_FUNCTION bld_reg_json
    FRAME 16
    str     x1, [sp, #24]
    ADDRESS x1, bld_reg_1
    mov     x2, #bld_reg_1_len
    bl      bld_put
    ldr     x1, [sp, #24]                   /* fee_recipient */
    mov     x2, #20
    bl      bld_hex
    ADDRESS x1, bld_reg_2
    mov     x2, #bld_reg_2_len
    bl      bld_put
    ldr     x1, [sp, #24]
    ldr     x1, [x1, #20]                   /* gas_limit */
    bl      bld_dec
    ADDRESS x1, bld_reg_3
    mov     x2, #bld_reg_3_len
    bl      bld_put
    ldr     x1, [sp, #24]
    ldr     x1, [x1, #28]                   /* timestamp */
    bl      bld_dec
    ADDRESS x1, bld_reg_4
    mov     x2, #bld_reg_4_len
    bl      bld_put
    ldr     x1, [sp, #24]                   /* pubkey */
    add     x1, x1, #36
    mov     x2, #48
    bl      bld_hex
    ADDRESS x1, bld_reg_5
    mov     x2, #bld_reg_5_len
    bl      bld_put
    ldr     x1, [sp, #24]                   /* signature */
    add     x1, x1, #84
    mov     x2, #96
    bl      bld_hex
    ADDRESS x1, bld_reg_6
    mov     x2, #bld_reg_6_len
    bl      bld_put
    UNFRAME 16
END_FUNCTION bld_reg_json

/*
 * L2: the NODE_EV_WORK_DONE x21 of a NODE_WORK_API_SUBMIT of registerValidator, with
 * NODE_FLAG_BUILDER (node.md): a NODE_BUILDER_REGISTER call of the JSON array of the registrations
 * of LANTERN_VALID; none with none, with no free call, or with no room in the actions. x19 the
 * node, x24 the actions; x22 a record, x23 the records left, x25 the body's bytes, x26 the valid
 * ones, x27 the request's bytes, x28 the cursor. Locals: L the call.
 */
LOCAL_FUNCTION node_builder_register
    ENTER 16
    ldr     x9, [x19, #Node_flags]
    tbz     x9, #11, 9f                     /* NODE_FLAG_BUILDER */
    add     x9, x21, #NodeEvent_chunk       /* the body: [, each valid registration's JSON with , between, ] */
    ldr     x10, [x9, #8]
    add     x22, x9, x10
    ldr     x23, [x21, #NodeEvent_index]
    mov     x25, #2
    mov     x26, #0
1:  cbz     x23, 2f
    ldr     x9, [x22]
    cbnz    x9, 11f
    ldr     x9, [x22, #(16 + 16)]           /* its SSZ bytes: 180 */
    cmp     x9, #180
    b.ne    11f
    ldr     x9, [x22, #(16 + 8)]
    add     x0, x22, #16
    add     x0, x0, x9
    bl      bld_reg_len
    add     x25, x25, x0
    cmp     x26, #0
    cinc    x25, x25, ne                    /* the , before it */
    add     x26, x26, #1
11: ldr     x9, [x22, #16]
    add     x22, x22, #16
    add     x22, x22, x9
    sub     x23, x23, #1
    b       1b
2:  cbz     x26, 9f
    mov     x0, x25                         /* the request: the head, then the body */
    bl      bld_digits
    LDQ     x9, x19, Node_builder_host_len
    add     x27, x0, x9
    add     x27, x27, #BLD_HEAD_FIXED
    add     x27, x27, x25
    add     x0, x27, #(48 + 7)
    bl      node_room
    cbz     x0, 9f
    mov     x0, #NODE_BUILDER_REGISTER
    mov     x1, #-1
    bl      node_builder_call
    cmn     x0, #1
    b.eq    9f
    str     x0, [sp, #L]
    add     x1, x27, #(48 + 7)
    and     x1, x1, #~7
    mov     x0, #NODE_ACT_BUILDER
    bl      node_act
    ldr     x9, [sp, #L]
    str     x9, [x0, #16]
    ldr     x9, [x0]
    sub     x9, x9, #24
    mov     x10, #24
    stp     x9, x10, [x0, #24]
    str     x27, [x0, #40]
    add     x0, x0, #48
    ADDRESS x1, bld_post_validators
    mov     x2, #bld_post_validators_len
    bl      bld_put
    ADDQ    x1, x19, Node_builder_host
    LDQ     x2, x19, Node_builder_host_len
    bl      bld_put
    ADDRESS x1, bld_head_json
    mov     x2, #bld_head_json_len
    bl      bld_put
    mov     x1, x25
    bl      bld_dec
    ADDRESS x1, bld_head_end
    mov     x2, #bld_head_end_len
    bl      bld_put
    mov     x9, #'['
    strb    w9, [x0], #1
    mov     x28, x0
    add     x9, x21, #NodeEvent_chunk
    ldr     x10, [x9, #8]
    add     x22, x9, x10
    ldr     x23, [x21, #NodeEvent_index]
    mov     x26, #0
3:  cbz     x23, 4f
    ldr     x9, [x22]
    cbnz    x9, 31f
    ldr     x9, [x22, #(16 + 16)]
    cmp     x9, #180
    b.ne    31f
    cbz     x26, 32f
    mov     x9, #','
    strb    w9, [x28], #1
32: add     x26, x26, #1
    ldr     x9, [x22, #(16 + 8)]
    add     x1, x22, #16
    add     x1, x1, x9
    mov     x0, x28
    bl      bld_reg_json
    mov     x28, x0
31: ldr     x9, [x22, #16]
    add     x22, x22, #16
    add     x22, x22, x9
    sub     x23, x23, #1
    b       3b
4:  mov     x9, #']'
    strb    w9, [x28]
9:  LEAVE 16
END_FUNCTION node_builder_register

/*
 * L1: the registration of LANTERN_VALID at x0 (a ByteList of its 180 SSZ bytes) of the validator x1
 * (beacon-api.md, registerValidator): its NodeProposer entry takes it, unless the entry holds one of
 * a later timestamp; with none, the first free entry (until_epoch at most the store x20's epoch,
 * registered 0), else a new one when the part has room; else none. Locals: the bytes, the index,
 * the epoch.
 */
LOCAL_FUNCTION node_registration_put
    FRAME 32
    ldr     x9, [x0, #8]
    add     x9, x0, x9
    stp     x9, x1, [sp, #16]
    mov     x0, x20
    bl      node_store_slot
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x0, x0, x9
    str     x0, [sp, #32]
    ldr     x14, [sp, #24]                  /* the validator index */
    PART    x9, x10, x19, Node_proposers
    mov     x11, #0
    mov     x15, #0                         /* the first free entry, or 0 */
1:  cmp     x11, x10
    b.hs    3f
    ldr     x12, [x9, #NodeProposer_validator_index]
    cmp     x12, x14
    b.eq    4f
    cbnz    x15, 2f
    ldr     x12, [x9, #NodeProposer_until_epoch]
    cmp     x12, x0
    b.hi    2f
    ldr     x12, [x9, #NodeProposer_registered]
    cbnz    x12, 2f
    mov     x15, x9
2:  add     x9, x9, #NodeProposer__mem
    add     x11, x11, #1
    b       1b
3:  mov     x9, x15                         /* none of its index: a free entry, else a new one */
    cbnz    x9, 5f
    LDQ     x12, x19, Node_proposers        /* the capacity: up to the next part */
    LDQ     x13, x19, Node_p2p_out
    sub     x13, x13, x12
    mov     x12, #NodeProposer__mem
    udiv    x13, x13, x12
    cmp     x10, x13
    b.hs    9f
    PART    x9, x11, x19, Node_proposers
    mov     x12, #NodeProposer__mem
    madd    x9, x10, x12, x9
    add     x10, x10, #1
    STQ     x10, x19, Node_proposers + 8
    stp     xzr, xzr, [x9, #NodeProposer_until_epoch]   /* a new entry: no preparation */
    stp     xzr, xzr, [x9, #(NodeProposer_fee_recipient + 8)]
5:  str     x14, [x9, #NodeProposer_validator_index]
    b       6f
4:  ldr     x12, [x9, #NodeProposer_registered]  /* its entry: unless it holds a later registration */
    cbz     x12, 6f
    ldr     x12, [x9, #NodeProposer_timestamp]
    ldr     x13, [sp, #16]
    ldr     x13, [x13, #28]
    cmp     x12, x13
    b.hi    9f
6:  mov     x10, #1
    str     x10, [x9, #NodeProposer_registered]
    ldr     x13, [sp, #16]
    ldr     x10, [x13, #20]                 /* gas_limit, timestamp */
    ldr     x11, [x13, #28]
    stp     x10, x11, [x9, #NodeProposer_gas_limit]
    str     x9, [sp, #24]
    add     x0, x9, #NodeProposer_registration_fee_recipient
    mov     x1, x13
    mov     x2, #20
    bl      lantern_copy
    ldr     x9, [sp, #24]                   /* and its pubkey */
    add     x0, x9, #NodeProposer_pubkey
    ldr     x1, [sp, #16]
    add     x1, x1, #36
    mov     x2, #48
    bl      lantern_copy
9:  UNFRAME 32
END_FUNCTION node_registration_put

/* The table slot of the pubkey at reg: its bytes 8 to 16 and 16 to 24, mixed, and the mask. */
.macro BLD_HASH out, key, mask, t
    ldr     \out, [\key, #8]
    ldr     \t, [\key, #16]
    eor     \out, \out, \t
    eor     \out, \out, \out, lsr #29
    and     \out, \out, \mask
.endm

/*
 * L1: (state, records, count, scratch) -> x0: the validators of the records of a registerValidator
 * (node.md, NODE_WORK_API_SUBMIT): one scan of the state's validators, through a table of the
 * records' pubkeys at the end of scratch (a power of two of slots, at least twice the count, each
 * a record or 0); each record whose pubkey is of a validator eligible at the state's epoch
 * (builder-specs is_eligible_for_registration) takes LANTERN_VALID and the validator's index.
 * LANTERN_OK, or LANTERN_BUFFER_TOO_SMALL with no room for the table. x19 state, x20 records, x21
 * count, x22 scratch, x23 the table, x24 the mask, x25 a validator, x26 the validators left, x27
 * its index, x28 the epoch.
 */
LOCAL_FUNCTION node_registrations_find
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x9, #8
1:  cmp     x9, x21, lsl #1
    b.hs    2f
    lsl     x9, x9, #1
    b       1b
2:  sub     x24, x9, #1
    lsl     x10, x9, #3
    ldr     x11, [x22]
    add     x12, x10, #64
    cmp     x11, x12
    b.lo    98f
    sub     x11, x11, x10
    add     x23, x22, x11
    mov     x0, x23
    mov     x1, x10
    bl      lantern_zero
    mov     x9, x20                         /* each record's pubkey: its bytes at 36 */
    mov     x10, x21
3:  cbz     x10, 4f
    ldr     x11, [x9, #24]
    add     x11, x11, x9
    add     x11, x11, #(16 + 36)
    BLD_HASH x12, x11, x24, x13
31: ldr     x13, [x23, x12, lsl #3]
    cbz     x13, 32f
    add     x12, x12, #1
    and     x12, x12, x24
    b       31b
32: str     x9, [x23, x12, lsl #3]
    ldr     x11, [x9, #16]
    add     x9, x9, #16
    add     x9, x9, x11
    sub     x10, x10, #1
    b       3b
4:  ldr     x28, [x19, #NODE_STATE_SLOT]    /* the state's epoch */
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x28, x28, x9
    PART    x25, x26, x19, NODE_STATE_VALIDATORS
    mov     x27, #0
5:  cbz     x26, 8f
    BLD_HASH x12, x25, x24, x13
51: ldr     x13, [x23, x12, lsl #3]
    cbz     x13, 6f
    ldr     x14, [x13, #24]                 /* the record's pubkey, against the validator's */
    add     x14, x14, x13
    add     x14, x14, #(16 + 36)
    mov     x15, #0
52: ldr     x9, [x14, x15]
    ldr     x10, [x25, x15]
    cmp     x9, x10
    b.ne    55f
    add     x15, x15, #8
    cmp     x15, #48
    b.lo    52b
    ldr     x9, [x25, #NODE_VALIDATOR_ACTIVATION]   /* is_active_validator, or activation_epoch past the epoch */
    ldr     x10, [x25, #NODE_VALIDATOR_EXIT]
    cmp     x9, x28
    b.hi    53f
    cmp     x28, x10
    b.hs    55f
53: str     xzr, [x13]                      /* LANTERN_VALID, the index */
    str     x27, [x13, #8]
55: add     x12, x12, #1
    and     x12, x12, x24
    b       51b
6:  add     x25, x25, #NODE_VALIDATOR_MEM
    add     x27, x27, #1
    sub     x26, x26, #1
    b       5b
8:  mov     x0, #LANTERN_OK
    LEAVE 0
98: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION node_registrations_find
