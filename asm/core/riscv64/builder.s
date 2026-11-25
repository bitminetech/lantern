/*
 * The builder of the node, RISC-V: in the common object. Requirements: docs/reference/node.md (the
 * builder calls) and beacon-api.md (registerValidator). A registration's SSZ bytes have no
 * alignment: its numbers load with LCS_LD64 (lcstore.s).
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
/* The lengths of the texts, as numbers: li takes no difference of labels here. */
.set BLD_POST_VALIDATORS_LEN, 48
.set BLD_HEAD_JSON_LEN, 95
.set BLD_HEAD_END_LEN, 4
.set BLD_REG_1_LEN, 31
.set BLD_REG_2_LEN, 15
.set BLD_REG_3_LEN, 15
.set BLD_REG_4_LEN, 14
.set BLD_REG_5_LEN, 18
.set BLD_REG_6_LEN, 2
.if (bld_post_validators_len != BLD_POST_VALIDATORS_LEN) || (bld_head_json_len != BLD_HEAD_JSON_LEN) || (bld_head_end_len != BLD_HEAD_END_LEN) || (bld_reg_1_len != BLD_REG_1_LEN) || (bld_reg_2_len != BLD_REG_2_LEN) || (bld_reg_3_len != BLD_REG_3_LEN) || (bld_reg_4_len != BLD_REG_4_LEN) || (bld_reg_5_len != BLD_REG_5_LEN) || (bld_reg_6_len != BLD_REG_6_LEN)
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
bld_post_blinded:
    .ascii  "POST /eth/v2/builder/blinded_blocks HTTP/1.1\r\nHost: "
bld_post_blinded_len = . - bld_post_blinded
bld_submit_1:
    .ascii  "\r\nAccept: application/json\r\nConnection: close\r\nEth-Consensus-Version: "
bld_submit_1_len = . - bld_submit_1
bld_submit_2:
    .ascii  "\r\nContent-Type: application/json\r\nContent-Length: "
bld_submit_2_len = . - bld_submit_2
/* The submitBlindedBlockV2 texts' lengths as numbers, and the request head's bytes other than the host, the fork's name and Content-Length's digits. */
.set BLD_POST_BLINDED_LEN, 52
.set BLD_SUBMIT_1_LEN, 70
.set BLD_SUBMIT_2_LEN, 50
.set BLD_SUBMIT_FIXED, 176
.if (bld_post_blinded_len != BLD_POST_BLINDED_LEN) || (bld_submit_1_len != BLD_SUBMIT_1_LEN) || (bld_submit_2_len != BLD_SUBMIT_2_LEN) || (BLD_POST_BLINDED_LEN + BLD_SUBMIT_1_LEN + BLD_SUBMIT_2_LEN + BLD_HEAD_END_LEN != BLD_SUBMIT_FIXED)
.error "a submitBlindedBlockV2 text's length is wrong"
.endif
bld_version:
    .ascii  "version"
bld_data:
    .ascii  "data"
/* The getHeader texts' lengths as numbers, and the request's bytes other than the slot's digits and the host. */
.set BLD_GET_HEADER_LEN, 27
.set BLD_GET_0X_LEN, 3
.set BLD_GET_HTTP_LEN, 17
.set BLD_GET_END_LEN, 49
.set BLD_GET_FIXED, BLD_GET_HEADER_LEN + 2 * BLD_GET_0X_LEN + BLD_GET_HTTP_LEN + BLD_GET_END_LEN + 2 * (32 + 48)
.if (bld_get_header_len != BLD_GET_HEADER_LEN) || (bld_get_0x_len != BLD_GET_0X_LEN) || (bld_get_http_len != BLD_GET_HTTP_LEN) || (bld_get_end_len != BLD_GET_END_LEN)
.error "a getHeader text's length is wrong"
.endif
bld_hex_digits:
    .ascii  "0123456789abcdef"

# a0 = the count of decimal digits of a0. Uses t0, t1.
LOCAL_FUNCTION lantern_bld_digits
    UNWIND_END_PROLOGUE
    li      t0, 1
    li      t1, 10
1:  bltu    a0, t1, 2f
    divu    a0, a0, t1
    addi    t0, t0, 1
    j       1b
2:  mv      a0, t0
    ret
END_FUNCTION lantern_bld_digits

# a0 = the cursor a0 past the decimal digits of a1, written there. Uses t0-t3.
LOCAL_FUNCTION lantern_bld_dec
    UNWIND_END_PROLOGUE
    li      t0, 1
    li      t1, 10
    mv      t2, a1
1:  bltu    t2, t1, 2f
    divu    t2, t2, t1
    addi    t0, t0, 1
    j       1b
2:  add     a0, a0, t0
    mv      t2, a0
3:  remu    t3, a1, t1                      # from the last digit back
    divu    a1, a1, t1
    addi    t3, t3, '0'
    addi    t2, t2, -1
    sb      t3, 0(t2)
    addi    t0, t0, -1
    bnez    t0, 3b
    ret
END_FUNCTION lantern_bld_dec

# a0 = the cursor a0 past the lower case hex digits of the a2 bytes at a1, written there. Uses t0-t2.
LOCAL_FUNCTION lantern_bld_hex
    UNWIND_END_PROLOGUE
    ADDRESS t0, bld_hex_digits
1:  beqz    a2, 2f
    lbu     t1, 0(a1)
    srli    t2, t1, 4
    andi    t1, t1, 15
    add     t2, t0, t2
    lbu     t2, 0(t2)
    add     t1, t0, t1
    lbu     t1, 0(t1)
    sb      t2, 0(a0)
    sb      t1, 1(a0)
    addi    a0, a0, 2
    addi    a1, a1, 1
    addi    a2, a2, -1
    j       1b
2:  ret
END_FUNCTION lantern_bld_hex

# a0 = the cursor a0 past the a2 bytes at a1, copied there. Locals: the cursor, the count.
LOCAL_FUNCTION lantern_bld_put
    FRAME 16
    sd      a0, 0(sp)
    sd      a2, 8(sp)
    call    lantern_copy
    ld      a0, 0(sp)
    ld      a2, 8(sp)
    add     a0, a0, a2
    UNFRAME 16
END_FUNCTION lantern_bld_put

# a0 = the index of a free entry of builder_calls (node.md, the builder calls), now of the kind
# a0, the NodeApi entry a1 and time_ms; 2^64 - 1 with none free. s1 the node. Uses t0-t3, a7.
LOCAL_FUNCTION lantern_node_builder_call
    UNWIND_END_PROLOGUE
    ADDQ    t0, s1, Node_builder_calls
    li      t1, 0
1:  li      t2, NODE_BUILDER_CALLS
    bgeu    t1, t2, 8f
    ld      t2, 0(t0)
    beqz    t2, 2f
    addi    t0, t0, NODE_BUILDER_CALL_SIZE
    addi    t1, t1, 1
    j       1b
2:  ld      t3, Node_time_ms(s1)
    sd      a0, 0(t0)
    sd      a1, 8(t0)
    sd      t3, 16(t0)
    mv      a0, t1
    ret
8:  li      a0, -1
    ret
END_FUNCTION lantern_node_builder_call

# The NODE_EV_BUILDER s3 (node.md, the builder calls): a header call still awaited by its
# produceBlockV3 entry ends there, the answer's bytes in a NODE_ACT_BYTES_PUT to a new id at
# PRODUCE_BID when the call did not fail and the actions have room; then the call's entry goes
# free; a submit call answers its publish entry. s1 the node, s5 scratch, s6 the actions; s7 the
# call, s8 the failure bit, s9 the call's entry, s10 the NodeApi entry.
LOCAL_FUNCTION lantern_node_builder_event
    ENTER 0
    ld      t0, 16(s3)
    andi    s7, t0, 255
    srli    s8, t0, 8
    andi    s8, s8, 1
    li      t1, NODE_BUILDER_CALLS
    bgeu    s7, t1, 9f
    ADDQ    t2, s1, Node_builder_calls
    li      t1, NODE_BUILDER_CALL_SIZE
    mul     t0, s7, t1
    add     s9, t2, t0
    ld      t0, 0(s9)                       # a header call: to its entry, when that waits for it
    li      t1, NODE_BUILDER_HEADER
    bne     t0, t1, 20f
    ld      t0, 8(s9)
    PART    t1, t2, s1, Node_api
    bgeu    t0, t2, 8f
    li      t3, NodeApi__mem
    mul     t0, t0, t3
    add     s10, t1, t0
    ld      t0, NodeApi_connection(s10)
    beqz    t0, 8f
    ld      t0, NodeApi_op(s10)
    li      t1, API_OP_PRODUCE_BLOCK_V3
    bne     t0, t1, 8f
    ld      t0, (NodeApi_cursor + PRODUCE_CALL)(s10)
    addi    t1, s7, 1
    bne     t0, t1, 8f
    sd      zero, (NodeApi_cursor + PRODUCE_CALL)(s10)
    bnez    s8, 8f
    ld      a0, (24 + 16)(s3)               # the answer's bytes
    addi    a0, a0, (48 + 7)
    call    lantern_node_room
    beqz    a0, 8f
    addi    a0, s3, 24
    call    lantern_node_put
    sd      a0, (NodeApi_cursor + PRODUCE_BID)(s10)
    j       8f
20: li      t1, NODE_BUILDER_SUBMIT         # a submit call: to its publish entry, when that waits for it
    bne     t0, t1, 8f
    ld      t0, 8(s9)
    PART    t1, t2, s1, Node_api
    bgeu    t0, t2, 8f
    li      t3, NodeApi__mem
    mul     t0, t0, t3
    add     s10, t1, t0
    ld      t0, NodeApi_connection(s10)
    beqz    t0, 8f
    ld      t0, NodeApi_op(s10)
    li      t1, API_OP_PUBLISH_BLOCK_V2
    bne     t0, t1, 8f
    ld      t0, (NodeApi_cursor + PUBLISH_CALL)(s10)
    addi    t1, s7, 1
    bne     t0, t1, 8f
    sd      zero, (NodeApi_cursor + PUBLISH_CALL)(s10)
    sd      zero, 0(s9)
    li      a1, 500                         # the builder's 202: 200; else 500
    bnez    s8, 22f
    addi    a0, s3, 24
    mv      a1, s5
    call    lantern_bld_status
    li      t0, 202
    li      a1, 500
    bne     a0, t0, 22f
    li      a1, 200
22: mv      a0, s10
    call    lantern_node_publish_answer
    LEAVE 0
8:  sd      zero, 0(s9)
9:  LEAVE 0
END_FUNCTION lantern_node_builder_event

# a0 = the status of the HTTP answer in the ByteList a0 (lantern_http_parse_response with eof
# 1, its body at the end of the scratch a1), or 0 when it is none. s7 the answer, s8 scratch.
# Locals: L the HttpResponse (16), L+16 eof, L+24 the scratch size.
LOCAL_FUNCTION lantern_bld_status
    ENTER 32
    mv      s7, a0
    mv      s8, a1
    ld      t0, 16(s7)                      # the body: at most the answer's bytes
    addi    t0, t0, (24 + 7)
    andi    t0, t0, -8
    ld      t1, 0(s8)
    sd      t1, (L + 24)(sp)
    bltu    t1, t0, 8f
    sub     t1, t1, t0
    sd      t1, 0(s8)
    add     a2, s8, t1
    sd      t0, 0(a2)
    li      t2, 24
    sd      t2, 8(a2)
    sd      zero, 16(a2)
    li      t0, 1
    sd      t0, (L + 16)(sp)
    mv      a0, s7
    addi    a1, sp, (L + 16)
    addi    a3, sp, L
    call    lantern_http_parse_response
    ld      t0, (L + 24)(sp)
    sd      t0, 0(s8)
    bnez    a0, 8f
    ld      a0, L(sp)
    LEAVE 32
8:  li      a0, 0
    LEAVE 32
END_FUNCTION lantern_bld_status

# (entry a0, JSON a1) -> a0: the submitBlindedBlockV2 call of the publishBlindedBlockV2 entry
# a0 (node.md, NODE_PUBLISH_SUBMIT), the block's JSON in the ByteList a1: 0 once it went, the
# entry in NODE_PUBLISH_SUBMIT with the call + 1 at PUBLISH_CALL; 500 with no builder, no free
# call or no room. s1 the node, s6 the actions; s7 the entry, s8 the JSON, s9 its bytes, s10 the
# fork's name, s4 the request's bytes. Locals: L the call.
LOCAL_FUNCTION lantern_node_publish_submit
    ENTER 16
    mv      s7, a0
    mv      s8, a1
    ld      t0, Node_flags(s1)
    li      t1, NODE_FLAG_BUILDER
    and     t0, t0, t1
    beqz    t0, 8f
    ld      s9, 16(s8)
    mv      a0, s9
    call    lantern_bld_digits
    LDQ     t0, s1, Node_builder_host_len
    add     s4, a0, t0
    addi    s4, s4, BLD_SUBMIT_FIXED
    add     s4, s4, s9
    ld      t0, NodeApi_fork(s7)            # the fork's name: its length, then its bytes
    ADDRESS s10, api_forks
    slli    t0, t0, 4
    add     s10, s10, t0
    lbu     t0, 0(s10)
    add     s4, s4, t0
    addi    a0, s4, (48 + 7)
    call    lantern_node_room
    beqz    a0, 8f
    PART    t0, t1, s1, Node_api
    sub     a1, s7, t0
    li      t1, NodeApi__mem
    divu    a1, a1, t1
    li      a0, NODE_BUILDER_SUBMIT
    call    lantern_node_builder_call
    li      t0, -1
    beq     a0, t0, 8f
    sd      a0, L(sp)
    addi    t0, a0, 1
    sd      t0, (NodeApi_cursor + PUBLISH_CALL)(s7)
    li      t0, NODE_PUBLISH_SUBMIT
    sd      t0, NodeApi_member(s7)
    addi    a1, s4, (48 + 7)
    andi    a1, a1, -8
    li      a0, NODE_ACT_BUILDER
    call    lantern_node_act
    ld      t0, L(sp)
    sd      t0, 16(a0)
    ld      t0, 0(a0)
    addi    t0, t0, -24
    sd      t0, 24(a0)
    li      t0, 24
    sd      t0, 32(a0)
    sd      s4, 40(a0)
    addi    a0, a0, 48
    ADDRESS a1, bld_post_blinded
    li      a2, BLD_POST_BLINDED_LEN
    call    lantern_bld_put
    ADDQ    a1, s1, Node_builder_host
    LDQ     a2, s1, Node_builder_host_len
    call    lantern_bld_put
    ADDRESS a1, bld_submit_1
    li      a2, BLD_SUBMIT_1_LEN
    call    lantern_bld_put
    addi    a1, s10, 1
    lbu     a2, 0(s10)
    call    lantern_bld_put
    ADDRESS a1, bld_submit_2
    li      a2, BLD_SUBMIT_2_LEN
    call    lantern_bld_put
    mv      a1, s9
    call    lantern_bld_dec
    ADDRESS a1, bld_head_end
    li      a2, BLD_HEAD_END_LEN
    call    lantern_bld_put
    ld      t0, 8(s8)
    add     a1, s8, t0
    mv      a2, s9
    call    lantern_bld_put
    li      a0, 0
    LEAVE 16
8:  li      a0, 500
    LEAVE 16
END_FUNCTION lantern_node_publish_submit

# On the way into NODE_PRODUCE_PAYLOAD of the produceBlockV3 entry a0 (node.md, Block
# production), the event a1 of its PRODUCE_CHECK and the head's block_hash at a2: with
# NODE_FLAG_BUILDER, a NODE_BUILDER_HEADER call of its slot, the hash and the pubkey of the
# proposer's NodeProposer entry, when builder_boost_factor is not 0, the entry has registered 1,
# the head's NodeBlock is not NOT_VALIDATED and the check says the chain is healthy; the entry
# keeps the call + 1 and the registration's fee recipient. None with no free call or no room in
# the actions. s1 the node, s6 the actions; s7 the entry, s8 the event, s9 the hash, s10 the
# NodeProposer. Locals: L the request's bytes, L+8 the call.
LOCAL_FUNCTION lantern_node_produce_header
    ENTER 16
    mv      s7, a0
    mv      s8, a1
    mv      s9, a2
    ld      t0, Node_flags(s1)
    li      t1, NODE_FLAG_BUILDER
    and     t0, t0, t1
    beqz    t0, 9f
    ld      t0, (NodeApi_cursor + PRODUCE_BOOST)(s7)
    beqz    t0, 9f
    ld      t0, (NodeEvent_root + 8)(s8)
    beqz    t0, 9f
    ld      t0, NodeEvent_root(s8)          # the proposer's registration
    PART    s10, t1, s1, Node_proposers
1:  beqz    t1, 9f
    ld      t2, NodeProposer_validator_index(s10)
    bne     t2, t0, 2f
    ld      t2, NodeProposer_registered(s10)
    bnez    t2, 3f
2:  addi    s10, s10, NodeProposer__mem
    addi    t1, t1, -1
    j       1b
3:  ADDQ    a0, s1, Node_head_root          # the head is not optimistic
    call    lantern_node_find_block
    li      t0, -1
    beq     a0, t0, 9f
    ld      t0, NodeBlock_payload_status(a1)
    li      t1, PAYLOAD_STATUS_NOT_VALIDATED
    beq     t0, t1, 9f
    ld      a0, NodeApi_slot(s7)            # the request's bytes
    call    lantern_bld_digits
    LDQ     t0, s1, Node_builder_host_len
    add     a0, a0, t0
    addi    a0, a0, BLD_GET_FIXED
    sd      a0, L(sp)
    addi    a0, a0, (48 + 7)
    call    lantern_node_room
    beqz    a0, 9f
    PART    t0, t1, s1, Node_api
    sub     a1, s7, t0
    li      t1, NodeApi__mem
    divu    a1, a1, t1
    li      a0, NODE_BUILDER_HEADER
    call    lantern_node_builder_call
    li      t0, -1
    beq     a0, t0, 9f
    sd      a0, (L + 8)(sp)
    addi    t0, a0, 1
    sd      t0, (NodeApi_cursor + PRODUCE_CALL)(s7)
    addi    a0, s7, (NodeApi_cursor + PRODUCE_FEE)
    addi    a1, s10, NodeProposer_registration_fee_recipient
    li      a2, 20
    call    lantern_copy
    ld      a1, L(sp)
    addi    a1, a1, (48 + 7)
    andi    a1, a1, -8
    li      a0, NODE_ACT_BUILDER
    call    lantern_node_act
    ld      t0, (L + 8)(sp)
    sd      t0, 16(a0)
    ld      t0, 0(a0)
    addi    t0, t0, -24
    sd      t0, 24(a0)
    li      t0, 24
    sd      t0, 32(a0)
    ld      t0, L(sp)
    sd      t0, 40(a0)
    addi    a0, a0, 48
    ADDRESS a1, bld_get_header
    li      a2, BLD_GET_HEADER_LEN
    call    lantern_bld_put
    ld      a1, NodeApi_slot(s7)
    call    lantern_bld_dec
    ADDRESS a1, bld_get_0x
    li      a2, BLD_GET_0X_LEN
    call    lantern_bld_put
    mv      a1, s9
    li      a2, 32
    call    lantern_bld_hex
    ADDRESS a1, bld_get_0x
    li      a2, BLD_GET_0X_LEN
    call    lantern_bld_put
    addi    a1, s10, NodeProposer_pubkey
    li      a2, 48
    call    lantern_bld_hex
    ADDRESS a1, bld_get_http
    li      a2, BLD_GET_HTTP_LEN
    call    lantern_bld_put
    ADDQ    a1, s1, Node_builder_host
    LDQ     a2, s1, Node_builder_host_len
    call    lantern_bld_put
    ADDRESS a1, bld_get_end
    li      a2, BLD_GET_END_LEN
    call    lantern_bld_put
9:  LEAVE 16
END_FUNCTION lantern_node_produce_header

# a0 = 1 when the a2 bytes at a1 are the a3 bytes at a0, else 0. Uses t0, t1.
LOCAL_FUNCTION lantern_bld_same
    UNWIND_END_PROLOGUE
    bne     a2, a3, 8f
1:  beqz    a2, 9f
    lbu     t0, 0(a0)
    lbu     t1, 0(a1)
    bne     t0, t1, 8f
    addi    a0, a0, 1
    addi    a1, a1, 1
    addi    a2, a2, -1
    j       1b
9:  li      a0, 1
    ret
8:  li      a0, 0
    ret
END_FUNCTION lantern_bld_same

# (answer a0, scratch a1, fork a2) -> a0: the JSON text of the bid in a builder's getHeader
# answer (node.md, NODE_WORK_PRODUCE_BID): lantern_http_parse_response with eof 1, the body
# unchunked at the end of scratch, whose size drops below it (the caller restores it); status 200;
# the body an object whose first member version is a string, the fork's name, and whose first
# member data is a value. LANTERN_OK with a1 the data's text and a2 its bytes; else
# LANTERN_INVALID_HTTP, LANTERN_NO_BID, LANTERN_INVALID_JSON, LANTERN_INVALID_BID or
# LANTERN_BUFFER_TOO_SMALL. s1 the body's end (the JSON scan's), s2 scratch, s3 the fork, s6 the
# body, s7 the version's text or 0, s8 its bytes, s9 the data or 0, s10 its end. Locals: L the
# answer, L+16 the HttpResponse (16), L+32 eof, L+40 a name and its bytes, L+56 the cursor.
LOCAL_FUNCTION lantern_node_bid_data
    ENTER 64
    sd      a0, L(sp)
    mv      s2, a1
    mv      s3, a2
    ld      t0, 16(a0)                      # the body: at most the answer's bytes
    addi    t0, t0, (24 + 7)
    andi    t0, t0, -8
    ld      t1, 0(s2)
    bltu    t1, t0, 98f
    sub     t1, t1, t0
    li      t2, 64
    bltu    t1, t2, 98f
    sd      t1, 0(s2)
    add     s6, s2, t1
    sd      t0, 0(s6)
    li      t2, 24
    sd      t2, 8(s6)
    sd      zero, 16(s6)
    li      t0, 1
    sd      t0, (L + 32)(sp)
    ld      a0, L(sp)
    addi    a1, sp, (L + 32)
    mv      a2, s6
    addi    a3, sp, (L + 16)
    call    lantern_http_parse_response
    bnez    a0, 97f
    ld      t0, (L + 16)(sp)
    li      t1, 200
    bne     t0, t1, 96f
    ld      t0, 8(s6)                       # the body's object: its members
    add     a0, s6, t0
    ld      t1, 16(s6)
    add     s1, a0, t1
    li      s7, 0
    li      s9, 0
    call    lantern_jws
    bgeu    a0, s1, 95f
    lbu     t0, 0(a0)
    li      t1, '{'
    bne     t0, t1, 95f
    addi    a0, a0, 1
    li      a1, 1
1:  call    lantern_jmember
    beqz    a0, 95f
    bnez    a3, 5f
    sd      a1, (L + 40)(sp)                # the name
    sd      a2, (L + 48)(sp)
    sd      a0, (L + 56)(sp)
    mv      a0, a1
    mv      a3, a2
    ADDRESS a1, bld_version
    li      a2, 7
    call    lantern_bld_same
    mv      t4, a0
    ld      a0, (L + 56)(sp)
    beqz    t4, 2f
    bnez    s7, 2f
    call    lantern_jstring                         # version: a string with no escape
    beqz    a0, 95f
    bnez    a3, 95f
    mv      s7, a1
    mv      s8, a2
    li      a1, 0
    j       1b
2:  ld      a0, (L + 40)(sp)
    ld      a3, (L + 48)(sp)
    ADDRESS a1, bld_data
    li      a2, 4
    call    lantern_bld_same
    mv      t4, a0
    ld      a0, (L + 56)(sp)
    beqz    t4, 3f
    bnez    s9, 3f
    mv      s9, a0                          # data: its text
    call    lantern_jskip
    beqz    a0, 95f
    mv      s10, a0
    li      a1, 0
    j       1b
3:  call    lantern_jskip                           # another member: skipped
    beqz    a0, 95f
    li      a1, 0
    j       1b
5:  call    lantern_jws                             # nothing after the object
    bne     a0, s1, 95f
    beqz    s7, 95f
    beqz    s9, 95f
    ADDRESS a0, api_forks                   # version: the fork's name
    slli    t0, s3, 4
    add     a0, a0, t0
    lbu     a3, 0(a0)
    addi    a0, a0, 1
    mv      a1, s7
    mv      a2, s8
    call    lantern_bld_same
    beqz    a0, 94f
    li      a0, LANTERN_OK
    mv      a1, s9
    sub     a2, s10, s9
    LEAVE 64
94: li      a0, LANTERN_INVALID_BID
    LEAVE 64
95: li      a0, LANTERN_INVALID_JSON
    LEAVE 64
96: li      a0, LANTERN_NO_BID
    LEAVE 64
97: li      a0, LANTERN_INVALID_HTTP
    LEAVE 64
98: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_node_bid_data

# a0 = the bytes of the JSON of the SignedValidatorRegistrationV1 at a0 (180 bytes). Locals: the registration, a count.
LOCAL_FUNCTION lantern_bld_reg_len
    FRAME 16
    sd      a0, 0(sp)
    addi    a1, a0, 20                      # gas_limit
    LCS_LD64 a0, a1
    call    lantern_bld_digits
    sd      a0, 8(sp)
    ld      a1, 0(sp)
    addi    a1, a1, 28                      # timestamp
    LCS_LD64 a0, a1
    call    lantern_bld_digits
    ld      t0, 8(sp)
    add     a0, a0, t0
    addi    a0, a0, BLD_REG_FIXED
    UNFRAME 16
END_FUNCTION lantern_bld_reg_len

# a0 = the cursor a0 past the JSON of the SignedValidatorRegistrationV1 at a1, written there
# (node.md, NODE_WORK_API_SUBMIT of registerValidator). Locals: the registration.
LOCAL_FUNCTION lantern_bld_reg_json
    FRAME 16
    sd      a1, 8(sp)
    ADDRESS a1, bld_reg_1
    li      a2, BLD_REG_1_LEN
    call    lantern_bld_put
    ld      a1, 8(sp)                       # fee_recipient
    li      a2, 20
    call    lantern_bld_hex
    ADDRESS a1, bld_reg_2
    li      a2, BLD_REG_2_LEN
    call    lantern_bld_put
    ld      t0, 8(sp)                       # gas_limit
    addi    t0, t0, 20
    LCS_LD64 a1, t0
    call    lantern_bld_dec
    ADDRESS a1, bld_reg_3
    li      a2, BLD_REG_3_LEN
    call    lantern_bld_put
    ld      t0, 8(sp)                       # timestamp
    addi    t0, t0, 28
    LCS_LD64 a1, t0
    call    lantern_bld_dec
    ADDRESS a1, bld_reg_4
    li      a2, BLD_REG_4_LEN
    call    lantern_bld_put
    ld      a1, 8(sp)                       # pubkey
    addi    a1, a1, 36
    li      a2, 48
    call    lantern_bld_hex
    ADDRESS a1, bld_reg_5
    li      a2, BLD_REG_5_LEN
    call    lantern_bld_put
    ld      a1, 8(sp)                       # signature
    addi    a1, a1, 84
    li      a2, 96
    call    lantern_bld_hex
    ADDRESS a1, bld_reg_6
    li      a2, BLD_REG_6_LEN
    call    lantern_bld_put
    UNFRAME 16
END_FUNCTION lantern_bld_reg_json

# The NODE_EV_WORK_DONE s3 of a NODE_WORK_API_SUBMIT of registerValidator, with
# NODE_FLAG_BUILDER (node.md): a NODE_BUILDER_REGISTER call of the JSON array of the registrations
# of LANTERN_VALID; none with none, with no free call, or with no room in the actions. s1 the
# node, s6 the actions; s4 a record, s5 the records left, s7 the body's bytes, s8 the valid ones,
# s9 the request's bytes, s10 the cursor. Locals: 0 the call.
LOCAL_FUNCTION lantern_node_builder_register
    ENTER 16
    ld      t0, Node_flags(s1)
    li      t1, NODE_FLAG_BUILDER
    and     t0, t0, t1
    beqz    t0, 9f
    ld      t0, (NodeEvent_chunk + 8)(s3)   # the body: [, each valid registration's JSON with , between, ]
    addi    s4, s3, NodeEvent_chunk
    add     s4, s4, t0
    ld      s5, NodeEvent_index(s3)
    li      s7, 2
    li      s8, 0
1:  beqz    s5, 2f
    ld      t0, 0(s4)
    bnez    t0, 11f
    ld      t0, (16 + 16)(s4)               # its SSZ bytes: 180
    li      t1, 180
    bne     t0, t1, 11f
    ld      t0, (16 + 8)(s4)
    addi    a0, s4, 16
    add     a0, a0, t0
    call    lantern_bld_reg_len
    add     s7, s7, a0
    beqz    s8, 12f
    addi    s7, s7, 1                       # the , before it
12: addi    s8, s8, 1
11: ld      t0, 16(s4)
    addi    s4, s4, 16
    add     s4, s4, t0
    addi    s5, s5, -1
    j       1b
2:  beqz    s8, 9f
    mv      a0, s7                          # the request: the head, then the body
    call    lantern_bld_digits
    LDQ     t0, s1, Node_builder_host_len
    add     s9, a0, t0
    addi    s9, s9, BLD_HEAD_FIXED
    add     s9, s9, s7
    addi    a0, s9, 48 + 7
    call    lantern_node_room
    beqz    a0, 9f
    li      a0, NODE_BUILDER_REGISTER
    li      a1, -1
    call    lantern_node_builder_call
    li      t0, -1
    beq     a0, t0, 9f
    sd      a0, 0(sp)
    addi    a1, s9, 48 + 7
    andi    a1, a1, -8
    li      a0, NODE_ACT_BUILDER
    call    lantern_node_act
    ld      t0, 0(sp)
    sd      t0, 16(a0)
    ld      t0, 0(a0)
    addi    t0, t0, -24
    sd      t0, 24(a0)
    li      t0, 24
    sd      t0, 32(a0)
    sd      s9, 40(a0)
    addi    a0, a0, 48
    ADDRESS a1, bld_post_validators
    li      a2, BLD_POST_VALIDATORS_LEN
    call    lantern_bld_put
    ADDQ    a1, s1, Node_builder_host
    LDQ     a2, s1, Node_builder_host_len
    call    lantern_bld_put
    ADDRESS a1, bld_head_json
    li      a2, BLD_HEAD_JSON_LEN
    call    lantern_bld_put
    mv      a1, s7
    call    lantern_bld_dec
    ADDRESS a1, bld_head_end
    li      a2, BLD_HEAD_END_LEN
    call    lantern_bld_put
    li      t0, '['
    sb      t0, 0(a0)
    addi    s10, a0, 1
    ld      t0, (NodeEvent_chunk + 8)(s3)
    addi    s4, s3, NodeEvent_chunk
    add     s4, s4, t0
    ld      s5, NodeEvent_index(s3)
    li      s8, 0
3:  beqz    s5, 4f
    ld      t0, 0(s4)
    bnez    t0, 31f
    ld      t0, (16 + 16)(s4)
    li      t1, 180
    bne     t0, t1, 31f
    beqz    s8, 32f
    li      t0, ','
    sb      t0, 0(s10)
    addi    s10, s10, 1
32: addi    s8, s8, 1
    ld      t0, (16 + 8)(s4)
    addi    a1, s4, 16
    add     a1, a1, t0
    mv      a0, s10
    call    lantern_bld_reg_json
    mv      s10, a0
31: ld      t0, 16(s4)
    addi    s4, s4, 16
    add     s4, s4, t0
    addi    s5, s5, -1
    j       3b
4:  li      t0, ']'
    sb      t0, 0(s10)
9:  LEAVE 16
END_FUNCTION lantern_node_builder_register

# The registration of LANTERN_VALID at a0 (a ByteList of its 180 SSZ bytes) of the validator a1
# (beacon-api.md, registerValidator): its NodeProposer entry takes it, unless the entry holds one of a
# later timestamp; with none, the first free entry (until_epoch at most the store s2's epoch,
# registered 0), else a new one when the part has room; else none. s1 the node. Locals: the bytes,
# the index or the entry, the epoch.
LOCAL_FUNCTION lantern_node_registration_put
    FRAME 32
    ld      t0, 8(a0)
    add     t0, a0, t0
    sd      t0, 0(sp)
    sd      a1, 8(sp)
    mv      a0, s2
    call    lantern_node_store_slot
    li      t0, SLOTS_PER_EPOCH
    divu    a0, a0, t0
    sd      a0, 16(sp)
    ld      t5, 8(sp)                       # the validator index
    PART    t0, t1, s1, Node_proposers
    li      t2, 0
    li      t6, 0                           # the first free entry, or 0
1:  bgeu    t2, t1, 3f
    ld      t3, NodeProposer_validator_index(t0)
    beq     t3, t5, 4f
    bnez    t6, 2f
    ld      t3, NodeProposer_until_epoch(t0)
    bgtu    t3, a0, 2f
    ld      t3, NodeProposer_registered(t0)
    bnez    t3, 2f
    mv      t6, t0
2:  addi    t0, t0, NodeProposer__mem
    addi    t2, t2, 1
    j       1b
3:  mv      t0, t6                          # none of its index: a free entry, else a new one
    bnez    t0, 5f
    LDQ     t3, s1, Node_p2p_out            # the capacity: up to the next part
    LDQ     t4, s1, Node_proposers
    sub     t3, t3, t4
    li      t4, NodeProposer__mem
    divu    t3, t3, t4
    bgeu    t1, t3, 9f
    PART    t0, t2, s1, Node_proposers
    li      t4, NodeProposer__mem
    mul     t4, t1, t4
    add     t0, t0, t4
    addi    t1, t1, 1
    STQ     t1, s1, Node_proposers + 8
    sd      zero, NodeProposer_until_epoch(t0)  # a new entry: no preparation
    sd      zero, NodeProposer_fee_recipient(t0)
    sd      zero, (NodeProposer_fee_recipient + 8)(t0)
    sd      zero, (NodeProposer_fee_recipient + 16)(t0)
5:  sd      t5, NodeProposer_validator_index(t0)
    j       6f
4:  ld      t3, NodeProposer_registered(t0) # its entry: unless it holds a later registration
    beqz    t3, 6f
    ld      t3, NodeProposer_timestamp(t0)
    ld      t4, 0(sp)
    addi    t4, t4, 28
    LCS_LD64 t2, t4
    bgtu    t3, t2, 9f
6:  li      t1, 1
    sd      t1, NodeProposer_registered(t0)
    sd      t0, 8(sp)
    ld      t4, 0(sp)                       # gas_limit, timestamp
    addi    t4, t4, 20
    LCS_LD64 t2, t4
    ld      t0, 8(sp)
    sd      t2, NodeProposer_gas_limit(t0)
    ld      t4, 0(sp)
    addi    t4, t4, 28
    LCS_LD64 t2, t4
    ld      t0, 8(sp)
    sd      t2, NodeProposer_timestamp(t0)
    addi    a0, t0, NodeProposer_registration_fee_recipient
    ld      a1, 0(sp)
    li      a2, 20
    call    lantern_copy
    ld      t0, 8(sp)                       # and its pubkey
    addi    a0, t0, NodeProposer_pubkey
    ld      a1, 0(sp)
    addi    a1, a1, 36
    li      a2, 48
    call    lantern_copy
9:  UNFRAME 32
END_FUNCTION lantern_node_registration_put

# The table slot of a record's pubkey at key, which has no alignment: its bytes 8 to 16 and 16 to 24, mixed, and the mask. Uses t3-t6.
.macro BLD_HASH_U out, key, mask
    addi    t4, \key, 8
    LCS_LD64 \out, t4
    addi    t4, \key, 16
    LCS_LD64 t3, t4
    xor     \out, \out, t3
    srli    t3, \out, 29
    xor     \out, \out, t3
    and     \out, \out, \mask
.endm

# The same of a validator's pubkey at key, 8-aligned. Uses t3.
.macro BLD_HASH_A out, key, mask
    ld      \out, 8(\key)
    ld      t3, 16(\key)
    xor     \out, \out, t3
    srli    t3, \out, 29
    xor     \out, \out, t3
    and     \out, \out, \mask
.endm

# (state, records, count, scratch) -> a0: the validators of the records of a registerValidator
# (node.md, NODE_WORK_API_SUBMIT): one scan of the state's validators, through a table of the
# records' pubkeys at the end of scratch (a power of two of slots, at least twice the count, each a
# record or 0); each record whose pubkey is of a validator eligible at the state's epoch
# (builder-specs is_eligible_for_registration) takes LANTERN_VALID and the validator's index.
# LANTERN_OK, or LANTERN_BUFFER_TOO_SMALL with no room for the table. s1 state, s2 records, s3
# count, s4 scratch, s5 the table, s6 the mask, s7 a validator, s8 the validators left, s9 its
# index, s10 the epoch.
LOCAL_FUNCTION lantern_node_registrations_find
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    li      t0, 8
    slli    t1, s3, 1
1:  bgeu    t0, t1, 2f
    slli    t0, t0, 1
    j       1b
2:  addi    s6, t0, -1
    slli    t1, t0, 3
    ld      t2, 0(s4)
    addi    t3, t1, 64
    bltu    t2, t3, 98f
    sub     t2, t2, t1
    add     s5, s4, t2
    mv      a0, s5
    mv      a1, t1
    call    lantern_zero
    mv      a0, s2                          # each record's pubkey: its bytes at 36
    mv      a1, s3
3:  beqz    a1, 4f
    ld      t0, 24(a0)
    add     t0, a0, t0
    addi    t0, t0, 16 + 36
    BLD_HASH_U a2, t0, s6
31: slli    t1, a2, 3
    add     t1, s5, t1
    ld      t2, 0(t1)
    beqz    t2, 32f
    addi    a2, a2, 1
    and     a2, a2, s6
    j       31b
32: sd      a0, 0(t1)
    ld      t0, 16(a0)
    addi    a0, a0, 16
    add     a0, a0, t0
    addi    a1, a1, -1
    j       3b
4:  ld      s10, NODE_STATE_SLOT(s1)        # the state's epoch
    li      t0, SLOTS_PER_EPOCH
    divu    s10, s10, t0
    PART    s7, s8, s1, NODE_STATE_VALIDATORS
    li      s9, 0
5:  beqz    s8, 8f
    BLD_HASH_A a2, s7, s6
51: slli    t1, a2, 3
    add     t1, s5, t1
    ld      a3, 0(t1)
    beqz    a3, 6f
    ld      t0, 24(a3)                      # the record's pubkey, against the validator's
    add     t0, a3, t0
    addi    t0, t0, 16 + 36
    li      t1, 0
52: add     t2, t0, t1
    lbu     t2, 0(t2)
    add     t3, s7, t1
    lbu     t3, 0(t3)
    bne     t2, t3, 55f
    addi    t1, t1, 1
    li      t2, 48
    bltu    t1, t2, 52b
    ld      t2, NODE_VALIDATOR_ACTIVATION(s7)   # is_active_validator, or activation_epoch past the epoch
    ld      t3, NODE_VALIDATOR_EXIT(s7)
    bgtu    t2, s10, 53f
    bgeu    s10, t3, 55f
53: sd      zero, 0(a3)                     # LANTERN_VALID, the index
    sd      s9, 8(a3)
55: addi    a2, a2, 1
    and     a2, a2, s6
    j       51b
6:  addi    s7, s7, NODE_VALIDATOR_MEM
    addi    s9, s9, 1
    addi    s8, s8, -1
    j       5b
8:  li      a0, LANTERN_OK
    LEAVE 0
98: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_node_registrations_find
