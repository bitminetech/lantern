/*
 * The builder of the node, x86-64: in the common object. Requirements: docs/reference/node.md (the
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
bld_post_blinded:
    .ascii  "POST /eth/v2/builder/blinded_blocks HTTP/1.1\r\nHost: "
bld_post_blinded_len = . - bld_post_blinded
bld_submit_1:
    .ascii  "\r\nAccept: application/json\r\nConnection: close\r\nEth-Consensus-Version: "
bld_submit_1_len = . - bld_submit_1
bld_submit_2:
    .ascii  "\r\nContent-Type: application/json\r\nContent-Length: "
bld_submit_2_len = . - bld_submit_2
/* The bytes of a submitBlindedBlockV2 request's head other than the host, the fork's name and Content-Length's digits. */
.set BLD_SUBMIT_FIXED, 176
.if bld_post_blinded_len + bld_submit_1_len + bld_submit_2_len + bld_head_end_len != BLD_SUBMIT_FIXED
.error "the submitBlindedBlockV2 request's length is wrong"
.endif
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

# L0: rax = the count of decimal digits of rdi. Uses rcx, rdx, r8.
LOCAL_FUNCTION lantern_bld_digits
    UNWIND_END_PROLOGUE
    mov     %rdi, %rax
    mov     $1, %ecx
    mov     $10, %r8d
1:  cmp     $10, %rax
    jb      2f
    xor     %edx, %edx
    div     %r8
    inc     %rcx
    jmp     1b
2:  mov     %rcx, %rax
    ret
END_FUNCTION lantern_bld_digits

# L1: rax = the cursor rdi past the decimal digits of rsi, written there. Uses rcx, rdx, r8-r11.
LOCAL_FUNCTION lantern_bld_dec
    FRAME 0
    mov     %rdi, %r10                      # the start
    mov     %rsi, %rdi
    call    lantern_bld_digits
    lea     (%r10,%rax), %r9                # the end; the digits from the last back
    mov     %r9, %r11
    mov     %rsi, %rax
    mov     $10, %ecx
1:  xor     %edx, %edx
    div     %rcx
    add     $'0', %dl
    dec     %r11
    mov     %dl, (%r11)
    cmp     %r10, %r11
    ja      1b
    mov     %r9, %rax
    UNFRAME 0
END_FUNCTION lantern_bld_dec

# L0: rax = the cursor rdi past the lower case hex digits of the rdx bytes at rsi, written there. Uses rcx, r8, r9.
LOCAL_FUNCTION lantern_bld_hex
    UNWIND_END_PROLOGUE
    ADDRESS %r9, bld_hex_digits
1:  test    %rdx, %rdx
    jz      2f
    movzbl  (%rsi), %ecx
    mov     %ecx, %r8d
    shr     $4, %ecx
    and     $15, %r8d
    movzbl  (%r9,%rcx), %ecx
    mov     %cl, (%rdi)
    movzbl  (%r9,%r8), %ecx
    mov     %cl, 1(%rdi)
    add     $2, %rdi
    inc     %rsi
    dec     %rdx
    jmp     1b
2:  mov     %rdi, %rax
    ret
END_FUNCTION lantern_bld_hex

# L1: rax = the cursor rdi past the rdx bytes at rsi, copied there. Locals: the cursor, the count.
LOCAL_FUNCTION lantern_bld_put
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rdx, 8(%rsp)
    call    lantern_copy
    mov     (%rsp), %rax
    add     8(%rsp), %rax
    UNFRAME 16
END_FUNCTION lantern_bld_put

# L0: rax = the index of a free entry of builder_calls (node.md, the builder calls), now of the kind
# rdi, the NodeApi entry rsi and time_ms; 2^64 - 1 with none free. rbx the node. Uses rcx, rdx.
LOCAL_FUNCTION lantern_node_builder_call
    UNWIND_END_PROLOGUE
    lea     Node_builder_calls(%rbx), %rcx
    xor     %eax, %eax
1:  cmp     $NODE_BUILDER_CALLS, %rax
    jae     8f
    cmpq    $0, (%rcx)
    je      2f
    add     $NODE_BUILDER_CALL_SIZE, %rcx
    inc     %rax
    jmp     1b
2:  mov     %rdi, (%rcx)
    mov     %rsi, 8(%rcx)
    mov     Node_time_ms(%rbx), %rdx
    mov     %rdx, 16(%rcx)
    ret
8:  mov     $-1, %rax
    ret
END_FUNCTION lantern_node_builder_call

# L2: the NODE_EV_BUILDER r12 (node.md, the builder calls): a header call still awaited by its
# produceBlockV3 entry ends there, the answer's bytes in a NODE_ACT_BYTES_PUT to a new id at
# PRODUCE_BID when the call did not fail and the actions have room; then the call's entry goes
# free. rbx the node, r15 the actions; r13 the call, r14 its entry; S7 the failure bit, S8 the
# NodeApi entry.
LOCAL_FUNCTION lantern_node_builder_event
    ENTER 0
    mov     %r14, S9(%rsp)                  # the step's scratch
    mov     16(%r12), %rax
    movzbl  %al, %r13d
    shr     $8, %eax
    and     $1, %eax
    mov     %rax, S7(%rsp)
    cmp     $NODE_BUILDER_CALLS, %r13
    jae     9f
    imul    $NODE_BUILDER_CALL_SIZE, %r13, %rax
    lea     Node_builder_calls(%rbx,%rax), %r14
    cmpq    $NODE_BUILDER_HEADER, (%r14)    # a header call: to its entry, when that waits for it
    jne     20f
    mov     8(%r14), %rax
    PART    %rcx, %rdx, %rbx, Node_api
    cmp     %rdx, %rax
    jae     8f
    imul    $NodeApi__mem, %rax, %rax
    add     %rax, %rcx
    mov     %rcx, S8(%rsp)
    cmpq    $0, NodeApi_connection(%rcx)
    je      8f
    cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%rcx)
    jne     8f
    lea     1(%r13), %rax
    cmp     %rax, (NodeApi_cursor + PRODUCE_CALL)(%rcx)
    jne     8f
    movq    $0, (NodeApi_cursor + PRODUCE_CALL)(%rcx)
    cmpq    $0, S7(%rsp)
    jne     8f
    mov     (24 + 16)(%r12), %rdi           # the answer's bytes
    add     $(48 + 7), %rdi
    call    lantern_node_room
    test    %rax, %rax
    jz      8f
    lea     24(%r12), %rdi
    call    lantern_node_put
    mov     S8(%rsp), %rcx
    mov     %rax, (NodeApi_cursor + PRODUCE_BID)(%rcx)
    jmp     8f
20: cmpq    $NODE_BUILDER_SUBMIT, (%r14)    # a submit call: to its publish entry, when that waits for it
    jne     8f
    mov     8(%r14), %rax
    PART    %rcx, %rdx, %rbx, Node_api
    cmp     %rdx, %rax
    jae     8f
    imul    $NodeApi__mem, %rax, %rax
    add     %rax, %rcx
    mov     %rcx, S8(%rsp)
    cmpq    $0, NodeApi_connection(%rcx)
    je      8f
    cmpq    $API_OP_PUBLISH_BLOCK_V2, NodeApi_op(%rcx)
    jne     8f
    lea     1(%r13), %rax
    cmp     %rax, (NodeApi_cursor + PUBLISH_CALL)(%rcx)
    jne     8f
    movq    $0, (NodeApi_cursor + PUBLISH_CALL)(%rcx)
    movq    $0, (%r14)
    mov     $500, %esi                      # the builder's 202: 200; else 500
    cmpq    $0, S7(%rsp)
    jne     22f
    lea     24(%r12), %rdi
    mov     S9(%rsp), %rsi
    call    lantern_bld_status
    mov     $500, %esi
    mov     $200, %ecx
    cmp     $202, %rax
    cmove   %ecx, %esi
22: mov     S8(%rsp), %rdi
    call    lantern_node_publish_answer
    LEAVE 0
8:  movq    $0, (%r14)
9:  LEAVE 0
END_FUNCTION lantern_node_builder_event

# L2: rax = the status of the HTTP answer in the ByteList rdi (lantern_http_parse_response with eof
# 1, its body at the end of the scratch rsi), or 0 when it is none. rbx the answer, rbp scratch.
# Locals: L the HttpResponse (16), L+16 eof, L+24 the scratch size.
LOCAL_FUNCTION lantern_bld_status
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     16(%rbx), %rax                  # the body: at most the answer's bytes
    add     $(24 + 7), %rax
    and     $-8, %rax
    mov     (%rbp), %rcx
    mov     %rcx, (L + 24)(%rsp)
    sub     %rax, %rcx
    jb      8f
    mov     %rcx, (%rbp)
    lea     (%rbp,%rcx), %rdx
    mov     %rax, (%rdx)
    movq    $24, 8(%rdx)
    movq    $0, 16(%rdx)
    movq    $1, (L + 16)(%rsp)
    mov     %rbx, %rdi
    lea     (L + 16)(%rsp), %rsi
    lea     L(%rsp), %rcx
    call    lantern_http_parse_response
    mov     (L + 24)(%rsp), %rcx
    mov     %rcx, (%rbp)
    test    %rax, %rax
    jnz     8f
    mov     L(%rsp), %rax
    LEAVE 32
8:  xor     %eax, %eax
    LEAVE 32
END_FUNCTION lantern_bld_status

# L2: (entry rdi, JSON rsi) -> rax: the submitBlindedBlockV2 call of the publishBlindedBlockV2 entry
# rdi (node.md, NODE_PUBLISH_SUBMIT), the block's JSON in the ByteList rsi: 0 once it went, the entry
# in NODE_PUBLISH_SUBMIT with the call + 1 at PUBLISH_CALL; 500 with no builder, no free call or no
# room. rbx the node, r15 the actions; r12 the entry, r13 the JSON, r14 its bytes, rbp the fork's
# name; S7 the request's bytes, S8 the call.
LOCAL_FUNCTION lantern_node_publish_submit
    ENTER 16
    mov     %rdi, %r12
    mov     %rsi, %r13
    testq   $NODE_FLAG_BUILDER, Node_flags(%rbx)
    jz      8f
    mov     16(%r13), %r14
    mov     %r14, %rdi
    call    lantern_bld_digits
    add     Node_builder_host_len(%rbx), %rax
    add     $BLD_SUBMIT_FIXED, %rax
    add     %r14, %rax
    mov     NodeApi_fork(%r12), %rcx        # the fork's name: its length, then its bytes
    shl     $4, %rcx
    ADDRESS %rbp, api_forks
    add     %rcx, %rbp
    movzbl  (%rbp), %ecx
    add     %rcx, %rax
    mov     %rax, S7(%rsp)
    lea     (48 + 7)(%rax), %rdi
    call    lantern_node_room
    test    %rax, %rax
    jz      8f
    PART    %rcx, %rdx, %rbx, Node_api
    mov     %r12, %rax
    sub     %rcx, %rax
    xor     %edx, %edx
    mov     $NodeApi__mem, %ecx
    div     %rcx
    mov     %rax, %rsi
    mov     $NODE_BUILDER_SUBMIT, %edi
    call    lantern_node_builder_call
    cmp     $-1, %rax
    je      8f
    mov     %rax, S8(%rsp)
    inc     %rax
    mov     %rax, (NodeApi_cursor + PUBLISH_CALL)(%r12)
    movq    $NODE_PUBLISH_SUBMIT, NodeApi_member(%r12)
    mov     S7(%rsp), %rsi
    add     $(48 + 7), %rsi
    and     $-8, %rsi
    mov     $NODE_ACT_BUILDER, %edi
    call    lantern_node_act
    mov     S8(%rsp), %rcx
    mov     %rcx, 16(%rax)
    mov     (%rax), %rcx
    sub     $24, %rcx
    mov     %rcx, 24(%rax)
    movq    $24, 32(%rax)
    mov     S7(%rsp), %rcx
    mov     %rcx, 40(%rax)
    lea     48(%rax), %rdi
    ADDRESS %rsi, bld_post_blinded
    mov     $bld_post_blinded_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    lea     Node_builder_host(%rbx), %rsi
    mov     Node_builder_host_len(%rbx), %rdx
    call    lantern_bld_put
    mov     %rax, %rdi
    ADDRESS %rsi, bld_submit_1
    mov     $bld_submit_1_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    lea     1(%rbp), %rsi
    movzbl  (%rbp), %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    ADDRESS %rsi, bld_submit_2
    mov     $bld_submit_2_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    mov     %r14, %rsi
    call    lantern_bld_dec
    mov     %rax, %rdi
    ADDRESS %rsi, bld_head_end
    mov     $bld_head_end_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    mov     8(%r13), %rsi
    add     %r13, %rsi
    mov     %r14, %rdx
    call    lantern_bld_put
    xor     %eax, %eax
    LEAVE 16
8:  mov     $500, %eax
    LEAVE 16
END_FUNCTION lantern_node_publish_submit

# L2: on the way into NODE_PRODUCE_PAYLOAD of the produceBlockV3 entry rdi (node.md, Block
# production), the event rsi of its PRODUCE_CHECK and the head's block_hash at rdx: with
# NODE_FLAG_BUILDER, a NODE_BUILDER_HEADER call of its slot, the hash and the pubkey of the
# proposer's NodeProposer entry, when builder_boost_factor is not 0, the entry has registered 1,
# the head's NodeBlock is not NOT_VALIDATED and the check says the chain is healthy; the entry
# keeps the call + 1 and the registration's fee recipient. None with no free call or no room in
# the actions. rbx the node, r15 the actions; r12 the entry, r13 the event, r14 the hash, rbp the
# NodeProposer; S7 the request's bytes, S8 the call.
LOCAL_FUNCTION lantern_node_produce_header
    ENTER 16
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     %rdx, %r14
    testq   $NODE_FLAG_BUILDER, Node_flags(%rbx)
    jz      9f
    cmpq    $0, (NodeApi_cursor + PRODUCE_BOOST)(%r12)
    je      9f
    cmpq    $0, (NodeEvent_root + 8)(%r13)
    je      9f
    mov     NodeEvent_root(%r13), %rax      # the proposer's registration
    PART    %rbp, %rcx, %rbx, Node_proposers
1:  test    %rcx, %rcx
    jz      9f
    cmp     %rax, NodeProposer_validator_index(%rbp)
    jne     2f
    cmpq    $0, NodeProposer_registered(%rbp)
    jne     3f
2:  add     $NodeProposer__mem, %rbp
    dec     %rcx
    jmp     1b
3:  lea     Node_head_root(%rbx), %rdi      # the head is not optimistic
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      9f
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, NodeBlock_payload_status(%rdx)
    je      9f
    mov     NodeApi_slot(%r12), %rdi        # the request's bytes
    call    lantern_bld_digits
    add     Node_builder_host_len(%rbx), %rax
    add     $BLD_GET_FIXED, %rax
    mov     %rax, S7(%rsp)
    lea     (48 + 7)(%rax), %rdi
    call    lantern_node_room
    test    %rax, %rax
    jz      9f
    PART    %rcx, %rdx, %rbx, Node_api
    mov     %r12, %rax
    sub     %rcx, %rax
    xor     %edx, %edx
    mov     $NodeApi__mem, %ecx
    div     %rcx
    mov     %rax, %rsi
    mov     $NODE_BUILDER_HEADER, %edi
    call    lantern_node_builder_call
    cmp     $-1, %rax
    je      9f
    mov     %rax, S8(%rsp)
    inc     %rax
    mov     %rax, (NodeApi_cursor + PRODUCE_CALL)(%r12)
    lea     (NodeApi_cursor + PRODUCE_FEE)(%r12), %rdi
    lea     NodeProposer_registration_fee_recipient(%rbp), %rsi
    mov     $20, %edx
    call    lantern_copy
    mov     S7(%rsp), %rsi
    add     $(48 + 7), %rsi
    and     $-8, %rsi
    mov     $NODE_ACT_BUILDER, %edi
    call    lantern_node_act
    mov     S8(%rsp), %rcx
    mov     %rcx, 16(%rax)
    mov     (%rax), %rcx
    sub     $24, %rcx
    mov     %rcx, 24(%rax)
    movq    $24, 32(%rax)
    mov     S7(%rsp), %rcx
    mov     %rcx, 40(%rax)
    lea     48(%rax), %rdi
    ADDRESS %rsi, bld_get_header
    mov     $bld_get_header_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    mov     NodeApi_slot(%r12), %rsi
    call    lantern_bld_dec
    mov     %rax, %rdi
    ADDRESS %rsi, bld_get_0x
    mov     $bld_get_0x_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    mov     %r14, %rsi
    mov     $32, %edx
    call    lantern_bld_hex
    mov     %rax, %rdi
    ADDRESS %rsi, bld_get_0x
    mov     $bld_get_0x_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    lea     NodeProposer_pubkey(%rbp), %rsi
    mov     $48, %edx
    call    lantern_bld_hex
    mov     %rax, %rdi
    ADDRESS %rsi, bld_get_http
    mov     $bld_get_http_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    lea     Node_builder_host(%rbx), %rsi
    mov     Node_builder_host_len(%rbx), %rdx
    call    lantern_bld_put
    mov     %rax, %rdi
    ADDRESS %rsi, bld_get_end
    mov     $bld_get_end_len, %edx
    call    lantern_bld_put
9:  LEAVE 16
END_FUNCTION lantern_node_produce_header

# L0: rax = 1 when the rcx bytes at rdi are the rdx bytes at rsi, else 0. Uses rdi, rsi, rdx.
LOCAL_FUNCTION lantern_bld_same
    UNWIND_END_PROLOGUE
    cmp     %rcx, %rdx
    jne     8f
1:  test    %rdx, %rdx
    jz      9f
    movzbl  (%rdi), %eax
    cmp     (%rsi), %al
    jne     8f
    inc     %rdi
    inc     %rsi
    dec     %rdx
    jmp     1b
9:  mov     $1, %eax
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION lantern_bld_same

# L2: (answer rdi, scratch rsi, fork rdx) -> rax: the JSON text of the bid in a builder's getHeader
# answer (node.md, NODE_WORK_PRODUCE_BID): lantern_http_parse_response with eof 1, the body
# unchunked at the end of scratch, whose size drops below it (the caller restores it); status 200;
# the body an object whose first member version is a string, the fork's name, and whose first
# member data is a value. LANTERN_OK with rsi the data's text and rdx its bytes; else
# LANTERN_INVALID_HTTP, LANTERN_NO_BID, LANTERN_INVALID_JSON, LANTERN_INVALID_BID or
# LANTERN_BUFFER_TOO_SMALL. rbx the body's end (the JSON scan's), rbp scratch, r12 the fork, r13
# the body, r14 the version's text or 0, r15 its bytes; S7 the data or 0, S8 its end, S9 the
# answer. Locals: L the HttpResponse (16), L+16 eof, L+24 a name and its bytes, L+40 the cursor.
LOCAL_FUNCTION lantern_node_bid_data
    ENTER 48
    mov     %rdi, S9(%rsp)
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     16(%rdi), %rax                  # the body: at most the answer's bytes
    add     $(24 + 7), %rax
    and     $-8, %rax
    mov     (%rbp), %rcx
    sub     %rax, %rcx
    jb      98f
    cmp     $64, %rcx
    jb      98f
    mov     %rcx, (%rbp)
    lea     (%rbp,%rcx), %r13
    mov     %rax, (%r13)
    movq    $24, 8(%r13)
    movq    $0, 16(%r13)
    movq    $1, (L + 16)(%rsp)
    mov     S9(%rsp), %rdi
    lea     (L + 16)(%rsp), %rsi
    mov     %r13, %rdx
    lea     L(%rsp), %rcx
    call    lantern_http_parse_response
    test    %rax, %rax
    jnz     97f
    cmpq    $200, L(%rsp)
    jne     96f
    mov     8(%r13), %rdi                   # the body's object: its members
    add     %r13, %rdi
    mov     16(%r13), %rbx
    add     %rdi, %rbx
    xor     %r14d, %r14d
    movq    $0, S7(%rsp)
    call    lantern_jws
    cmp     %rbx, %rdi
    jae     95f
    cmpb    $'{', (%rdi)
    jne     95f
    inc     %rdi
    mov     $1, %esi
1:  call    lantern_jmember
    test    %rdi, %rdi
    jz      95f
    test    %rcx, %rcx
    jnz     5f
    mov     %rsi, (L + 24)(%rsp)            # the name
    mov     %rdx, (L + 32)(%rsp)
    mov     %rdi, (L + 40)(%rsp)
    mov     %rsi, %rdi
    mov     %rdx, %rcx
    ADDRESS %rsi, bld_version
    mov     $7, %edx
    call    lantern_bld_same
    mov     (L + 40)(%rsp), %rdi
    test    %rax, %rax
    jz      2f
    test    %r14, %r14
    jnz     2f
    call    lantern_jstring                         # version: a string with no escape
    test    %rdi, %rdi
    jz      95f
    test    %rcx, %rcx
    jnz     95f
    mov     %rsi, %r14
    mov     %rdx, %r15
    xor     %esi, %esi
    jmp     1b
2:  mov     (L + 24)(%rsp), %rdi
    mov     (L + 32)(%rsp), %rcx
    ADDRESS %rsi, bld_data
    mov     $4, %edx
    call    lantern_bld_same
    mov     (L + 40)(%rsp), %rdi
    test    %rax, %rax
    jz      3f
    cmpq    $0, S7(%rsp)
    jne     3f
    mov     %rdi, S7(%rsp)                  # data: its text
    call    lantern_jskip
    test    %rdi, %rdi
    jz      95f
    mov     %rdi, S8(%rsp)
    xor     %esi, %esi
    jmp     1b
3:  call    lantern_jskip                           # another member: skipped
    test    %rdi, %rdi
    jz      95f
    xor     %esi, %esi
    jmp     1b
5:  call    lantern_jws                             # nothing after the object
    cmp     %rbx, %rdi
    jne     95f
    test    %r14, %r14
    jz      95f
    cmpq    $0, S7(%rsp)
    je      95f
    ADDRESS %rdi, api_forks                 # version: the fork's name
    mov     %r12, %rax
    shl     $4, %rax
    add     %rax, %rdi
    movzbl  (%rdi), %ecx
    inc     %rdi
    mov     %r14, %rsi
    mov     %r15, %rdx
    call    lantern_bld_same
    test    %rax, %rax
    jz      94f
    xor     %eax, %eax
    mov     S7(%rsp), %rsi
    mov     S8(%rsp), %rdx
    sub     %rsi, %rdx
    LEAVE 48
94: mov     $LANTERN_INVALID_BID, %eax
    LEAVE 48
95: mov     $LANTERN_INVALID_JSON, %eax
    LEAVE 48
96: mov     $LANTERN_NO_BID, %eax
    LEAVE 48
97: mov     $LANTERN_INVALID_HTTP, %eax
    LEAVE 48
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
END_FUNCTION lantern_node_bid_data

# L1: rax = the bytes of the JSON of the SignedValidatorRegistrationV1 at rdi (180 bytes). Locals: the registration, a count.
LOCAL_FUNCTION lantern_bld_reg_len
    FRAME 16
    mov     %rdi, (%rsp)
    mov     20(%rdi), %rdi                  # gas_limit
    call    lantern_bld_digits
    mov     %rax, 8(%rsp)
    mov     (%rsp), %rdi
    mov     28(%rdi), %rdi                  # timestamp
    call    lantern_bld_digits
    add     8(%rsp), %rax
    add     $BLD_REG_FIXED, %rax
    UNFRAME 16
END_FUNCTION lantern_bld_reg_len

# L1: rax = the cursor rdi past the JSON of the SignedValidatorRegistrationV1 at rsi, written there
# (node.md, NODE_WORK_API_SUBMIT of registerValidator). Locals: the registration.
LOCAL_FUNCTION lantern_bld_reg_json
    FRAME 16
    mov     %rsi, (%rsp)
    ADDRESS %rsi, bld_reg_1
    mov     $bld_reg_1_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    mov     (%rsp), %rsi                    # fee_recipient
    mov     $20, %edx
    call    lantern_bld_hex
    mov     %rax, %rdi
    ADDRESS %rsi, bld_reg_2
    mov     $bld_reg_2_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    mov     (%rsp), %rsi
    mov     20(%rsi), %rsi                  # gas_limit
    call    lantern_bld_dec
    mov     %rax, %rdi
    ADDRESS %rsi, bld_reg_3
    mov     $bld_reg_3_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    mov     (%rsp), %rsi
    mov     28(%rsi), %rsi                  # timestamp
    call    lantern_bld_dec
    mov     %rax, %rdi
    ADDRESS %rsi, bld_reg_4
    mov     $bld_reg_4_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    mov     (%rsp), %rsi                    # pubkey
    add     $36, %rsi
    mov     $48, %edx
    call    lantern_bld_hex
    mov     %rax, %rdi
    ADDRESS %rsi, bld_reg_5
    mov     $bld_reg_5_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    mov     (%rsp), %rsi                    # signature
    add     $84, %rsi
    mov     $96, %edx
    call    lantern_bld_hex
    mov     %rax, %rdi
    ADDRESS %rsi, bld_reg_6
    mov     $bld_reg_6_len, %edx
    call    lantern_bld_put
    UNFRAME 16
END_FUNCTION lantern_bld_reg_json

# L2: the NODE_EV_WORK_DONE r12 of a NODE_WORK_API_SUBMIT of registerValidator, with
# NODE_FLAG_BUILDER (node.md): a NODE_BUILDER_REGISTER call of the JSON array of the registrations
# of LANTERN_VALID; none with none, with no free call, or with no room in the actions. rbx the
# node, r15 the actions; r13 a record, r14 the records left, rbp the body's bytes, S7 the valid
# ones, S8 the request's bytes, S9 the call, S10 the cursor.
LOCAL_FUNCTION lantern_node_builder_register
    ENTER 0
    testq   $NODE_FLAG_BUILDER, Node_flags(%rbx)
    jz      9f
    mov     (NodeEvent_chunk + 8)(%r12), %r13   # the body: [, each valid registration's JSON with , between, ]
    lea     NodeEvent_chunk(%r12,%r13), %r13
    mov     NodeEvent_index(%r12), %r14
    mov     $2, %ebp
    movq    $0, S7(%rsp)
1:  test    %r14, %r14
    jz      2f
    cmpq    $0, (%r13)
    jne     11f
    cmpq    $180, (16 + 16)(%r13)           # its SSZ bytes: 180
    jne     11f
    mov     (16 + 8)(%r13), %rdi
    lea     16(%r13,%rdi), %rdi
    call    lantern_bld_reg_len
    add     %rax, %rbp
    cmpq    $0, S7(%rsp)
    je      12f
    inc     %rbp                            # the , before it
12: incq    S7(%rsp)
11: mov     16(%r13), %rax
    lea     16(%r13,%rax), %r13
    dec     %r14
    jmp     1b
2:  cmpq    $0, S7(%rsp)
    je      9f
    mov     %rbp, %rdi                      # the request: the head, then the body
    call    lantern_bld_digits
    add     Node_builder_host_len(%rbx), %rax
    add     $BLD_HEAD_FIXED, %rax
    add     %rbp, %rax
    mov     %rax, S8(%rsp)
    lea     (48 + 7)(%rax), %rdi
    call    lantern_node_room
    test    %rax, %rax
    jz      9f
    mov     $NODE_BUILDER_REGISTER, %edi
    mov     $-1, %rsi
    call    lantern_node_builder_call
    cmp     $-1, %rax
    je      9f
    mov     %rax, S9(%rsp)
    mov     S8(%rsp), %rsi
    add     $(48 + 7), %rsi
    and     $-8, %rsi
    mov     $NODE_ACT_BUILDER, %edi
    call    lantern_node_act
    mov     S9(%rsp), %rcx
    mov     %rcx, 16(%rax)
    mov     (%rax), %rcx
    sub     $24, %rcx
    mov     %rcx, 24(%rax)
    movq    $24, 32(%rax)
    mov     S8(%rsp), %rcx
    mov     %rcx, 40(%rax)
    lea     48(%rax), %rdi
    ADDRESS %rsi, bld_post_validators
    mov     $bld_post_validators_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    lea     Node_builder_host(%rbx), %rsi
    mov     Node_builder_host_len(%rbx), %rdx
    call    lantern_bld_put
    mov     %rax, %rdi
    ADDRESS %rsi, bld_head_json
    mov     $bld_head_json_len, %edx
    call    lantern_bld_put
    mov     %rax, %rdi
    mov     %rbp, %rsi
    call    lantern_bld_dec
    mov     %rax, %rdi
    ADDRESS %rsi, bld_head_end
    mov     $bld_head_end_len, %edx
    call    lantern_bld_put
    movb    $'[', (%rax)
    inc     %rax
    mov     %rax, S10(%rsp)
    mov     (NodeEvent_chunk + 8)(%r12), %r13
    lea     NodeEvent_chunk(%r12,%r13), %r13
    mov     NodeEvent_index(%r12), %r14
    movq    $0, S7(%rsp)
3:  test    %r14, %r14
    jz      4f
    cmpq    $0, (%r13)
    jne     31f
    cmpq    $180, (16 + 16)(%r13)
    jne     31f
    cmpq    $0, S7(%rsp)
    je      32f
    mov     S10(%rsp), %rax
    movb    $',', (%rax)
    incq    S10(%rsp)
32: incq    S7(%rsp)
    mov     (16 + 8)(%r13), %rsi
    lea     16(%r13,%rsi), %rsi
    mov     S10(%rsp), %rdi
    call    lantern_bld_reg_json
    mov     %rax, S10(%rsp)
31: mov     16(%r13), %rax
    lea     16(%r13,%rax), %r13
    dec     %r14
    jmp     3b
4:  mov     S10(%rsp), %rax
    movb    $']', (%rax)
9:  LEAVE 0
END_FUNCTION lantern_node_builder_register

# L1: the registration of LANTERN_VALID at rdi (a ByteList of its 180 SSZ bytes) of the validator rsi
# (beacon-api.md, registerValidator): its NodeProposer entry takes it, unless the entry holds one of a
# later timestamp; with none, the first free entry (until_epoch at most the store rbp's epoch,
# registered 0), else a new one when the part has room; else none. rbx the node. Locals: the bytes,
# the index, the epoch.
LOCAL_FUNCTION lantern_node_registration_put
    FRAME 32
    mov     8(%rdi), %rax
    add     %rdi, %rax
    mov     %rax, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, 16(%rsp)
    mov     8(%rsp), %r8                    # the validator index
    PART    %r9, %r10, %rbx, Node_proposers
    xor     %r11d, %r11d
    xor     %edx, %edx                      # the first free entry, or 0
1:  cmp     %r10, %r11
    jae     3f
    cmp     %r8, NodeProposer_validator_index(%r9)
    je      4f
    test    %rdx, %rdx
    jnz     2f
    cmp     %rax, NodeProposer_until_epoch(%r9)
    ja      2f
    cmpq    $0, NodeProposer_registered(%r9)
    jne     2f
    mov     %r9, %rdx
2:  add     $NodeProposer__mem, %r9
    inc     %r11
    jmp     1b
3:  mov     %rdx, %r9                       # none of its index: a free entry, else a new one
    test    %r9, %r9
    jnz     5f
    mov     Node_p2p_out(%rbx), %rax        # the capacity: up to the next part
    sub     Node_proposers(%rbx), %rax
    xor     %edx, %edx
    mov     $NodeProposer__mem, %ecx
    div     %rcx
    cmp     %rax, %r10
    jae     9f
    PART    %r9, %rcx, %rbx, Node_proposers
    imul    $NodeProposer__mem, %r10, %rax
    add     %rax, %r9
    inc     %r10
    mov     %r10, (Node_proposers + 8)(%rbx)
    movq    $0, NodeProposer_until_epoch(%r9)   # a new entry: no preparation
    movq    $0, NodeProposer_fee_recipient(%r9)
    movq    $0, (NodeProposer_fee_recipient + 8)(%r9)
    movq    $0, (NodeProposer_fee_recipient + 16)(%r9)
5:  mov     %r8, NodeProposer_validator_index(%r9)
    jmp     6f
4:  cmpq    $0, NodeProposer_registered(%r9)    # its entry: unless it holds a later registration
    je      6f
    mov     (%rsp), %rcx
    mov     28(%rcx), %rcx
    cmp     %rcx, NodeProposer_timestamp(%r9)
    ja      9f
6:  movq    $1, NodeProposer_registered(%r9)
    mov     (%rsp), %rsi
    mov     20(%rsi), %rax                  # gas_limit, timestamp
    mov     %rax, NodeProposer_gas_limit(%r9)
    mov     28(%rsi), %rax
    mov     %rax, NodeProposer_timestamp(%r9)
    lea     NodeProposer_registration_fee_recipient(%r9), %rdi
    mov     $20, %edx
    call    lantern_copy
    lea     NodeProposer_pubkey(%r9), %rdi  # and its pubkey
    mov     (%rsp), %rsi
    add     $36, %rsi
    mov     $48, %edx
    call    lantern_copy
9:  UNFRAME 32
END_FUNCTION lantern_node_registration_put

# The table slot of the pubkey at key in out: its bytes 8 to 16 and 16 to 24, mixed, and the mask.
.macro BLD_HASH out, key, mask, t
    mov     8(\key), \out
    xor     16(\key), \out
    mov     \out, \t
    shr     $(29), \t
    xor     \t, \out
    and     \mask, \out
.endm

# L1: (state, records, count, scratch) -> rax: the validators of the records of a registerValidator
# (node.md, NODE_WORK_API_SUBMIT): one scan of the state's validators, through a table of the
# records' pubkeys at the end of scratch (a power of two of slots, at least twice the count, each a
# record or 0); each record whose pubkey is of a validator eligible at the state's epoch
# (builder-specs is_eligible_for_registration) takes LANTERN_VALID and the validator's index.
# LANTERN_OK, or LANTERN_BUFFER_TOO_SMALL with no room for the table. rbx state, r12 records, r13
# count, r14 the table, r15 the mask, rbp a validator; S7 the validators left, S8 its index, S9
# the epoch.
LOCAL_FUNCTION lantern_node_registrations_find
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %r12
    mov     %rdx, %r13
    mov     $8, %eax
    lea     (%r13,%r13), %r8
1:  cmp     %r8, %rax
    jae     2f
    shl     %rax
    jmp     1b
2:  lea     -1(%rax), %r15
    shl     $3, %rax
    mov     (%rcx), %r9
    lea     64(%rax), %r10
    cmp     %r10, %r9
    jb      98f
    sub     %rax, %r9
    lea     (%rcx,%r9), %r14
    mov     %r14, %rdi
    mov     %rax, %rsi
    call    lantern_zero
    mov     %r12, %r9                       # each record's pubkey: its bytes at 36
    mov     %r13, %r10
3:  test    %r10, %r10
    jz      4f
    mov     24(%r9), %r11
    lea     (16 + 36)(%r9,%r11), %r11
    BLD_HASH %rax, %r11, %r15, %rcx
31: cmpq    $0, (%r14,%rax,8)
    je      32f
    inc     %rax
    and     %r15, %rax
    jmp     31b
32: mov     %r9, (%r14,%rax,8)
    mov     16(%r9), %r11
    lea     16(%r9,%r11), %r9
    dec     %r10
    jmp     3b
4:  mov     NODE_STATE_SLOT(%rbx), %rax     # the state's epoch
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, S9(%rsp)
    PART    %rbp, %rax, %rbx, NODE_STATE_VALIDATORS
    mov     %rax, S7(%rsp)
    movq    $0, S8(%rsp)
5:  cmpq    $0, S7(%rsp)
    je      8f
    BLD_HASH %rax, %rbp, %r15, %rcx
51: mov     (%r14,%rax,8), %rdx
    test    %rdx, %rdx
    jz      6f
    mov     24(%rdx), %r11                  # the record's pubkey, against the validator's
    lea     (16 + 36)(%rdx,%r11), %r11
    xor     %ecx, %ecx
52: mov     (%r11,%rcx), %r8
    cmp     (%rbp,%rcx), %r8
    jne     55f
    add     $8, %ecx
    cmp     $48, %ecx
    jb      52b
    mov     S9(%rsp), %r8                   # is_active_validator, or activation_epoch past the epoch
    cmp     %r8, NODE_VALIDATOR_ACTIVATION(%rbp)
    ja      53f
    cmp     NODE_VALIDATOR_EXIT(%rbp), %r8
    jae     55f
53: movq    $LANTERN_VALID, (%rdx)          # LANTERN_VALID, the index
    mov     S8(%rsp), %r8
    mov     %r8, 8(%rdx)
55: inc     %rax
    and     %r15, %rax
    jmp     51b
6:  add     $NODE_VALIDATOR_MEM, %rbp
    incq    S8(%rsp)
    decq    S7(%rsp)
    jmp     5b
8:  xor     %eax, %eax
    LEAVE 0
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
END_FUNCTION lantern_node_registrations_find
