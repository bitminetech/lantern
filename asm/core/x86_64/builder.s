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
bld_hex_digits:
    .ascii  "0123456789abcdef"

# L0: rax = the count of decimal digits of rdi. Uses rcx, rdx, r8.
LOCAL_FUNCTION bld_digits
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
END_FUNCTION bld_digits

# L1: rax = the cursor rdi past the decimal digits of rsi, written there. Uses rcx, rdx, r8-r11.
LOCAL_FUNCTION bld_dec
    FRAME 0
    mov     %rdi, %r10                      # the start
    mov     %rsi, %rdi
    call    bld_digits
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
END_FUNCTION bld_dec

# L0: rax = the cursor rdi past the lower case hex digits of the rdx bytes at rsi, written there. Uses rcx, r8, r9.
LOCAL_FUNCTION bld_hex
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
END_FUNCTION bld_hex

# L1: rax = the cursor rdi past the rdx bytes at rsi, copied there. Locals: the cursor, the count.
LOCAL_FUNCTION bld_put
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rdx, 8(%rsp)
    call    lantern_copy
    mov     (%rsp), %rax
    add     8(%rsp), %rax
    UNFRAME 16
END_FUNCTION bld_put

# L0: rax = the index of a free entry of builder_calls (node.md, the builder calls), now of the kind
# rdi, the NodeApi entry rsi and time_ms; 2^64 - 1 with none free. rbx the node. Uses rcx, rdx.
LOCAL_FUNCTION node_builder_call
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
END_FUNCTION node_builder_call

# L1: the NODE_EV_BUILDER r12 (node.md, the builder calls): its call's entry goes free. rbx the node, r15 the actions.
LOCAL_FUNCTION node_builder_event
    UNWIND_END_PROLOGUE
    movzbl  16(%r12), %eax
    cmp     $NODE_BUILDER_CALLS, %rax
    jae     9f
    imul    $NODE_BUILDER_CALL_SIZE, %rax, %rax
    movq    $0, Node_builder_calls(%rbx,%rax)
9:  ret
END_FUNCTION node_builder_event

# L1: rax = the bytes of the JSON of the SignedValidatorRegistrationV1 at rdi (180 bytes). Locals: the registration, a count.
LOCAL_FUNCTION bld_reg_len
    FRAME 16
    mov     %rdi, (%rsp)
    mov     20(%rdi), %rdi                  # gas_limit
    call    bld_digits
    mov     %rax, 8(%rsp)
    mov     (%rsp), %rdi
    mov     28(%rdi), %rdi                  # timestamp
    call    bld_digits
    add     8(%rsp), %rax
    add     $BLD_REG_FIXED, %rax
    UNFRAME 16
END_FUNCTION bld_reg_len

# L1: rax = the cursor rdi past the JSON of the SignedValidatorRegistrationV1 at rsi, written there
# (node.md, NODE_WORK_API_SUBMIT of registerValidator). Locals: the registration.
LOCAL_FUNCTION bld_reg_json
    FRAME 16
    mov     %rsi, (%rsp)
    ADDRESS %rsi, bld_reg_1
    mov     $bld_reg_1_len, %edx
    call    bld_put
    mov     %rax, %rdi
    mov     (%rsp), %rsi                    # fee_recipient
    mov     $20, %edx
    call    bld_hex
    mov     %rax, %rdi
    ADDRESS %rsi, bld_reg_2
    mov     $bld_reg_2_len, %edx
    call    bld_put
    mov     %rax, %rdi
    mov     (%rsp), %rsi
    mov     20(%rsi), %rsi                  # gas_limit
    call    bld_dec
    mov     %rax, %rdi
    ADDRESS %rsi, bld_reg_3
    mov     $bld_reg_3_len, %edx
    call    bld_put
    mov     %rax, %rdi
    mov     (%rsp), %rsi
    mov     28(%rsi), %rsi                  # timestamp
    call    bld_dec
    mov     %rax, %rdi
    ADDRESS %rsi, bld_reg_4
    mov     $bld_reg_4_len, %edx
    call    bld_put
    mov     %rax, %rdi
    mov     (%rsp), %rsi                    # pubkey
    add     $36, %rsi
    mov     $48, %edx
    call    bld_hex
    mov     %rax, %rdi
    ADDRESS %rsi, bld_reg_5
    mov     $bld_reg_5_len, %edx
    call    bld_put
    mov     %rax, %rdi
    mov     (%rsp), %rsi                    # signature
    add     $84, %rsi
    mov     $96, %edx
    call    bld_hex
    mov     %rax, %rdi
    ADDRESS %rsi, bld_reg_6
    mov     $bld_reg_6_len, %edx
    call    bld_put
    UNFRAME 16
END_FUNCTION bld_reg_json

# L2: the NODE_EV_WORK_DONE r12 of a NODE_WORK_API_SUBMIT of registerValidator, with
# NODE_FLAG_BUILDER (node.md): a NODE_BUILDER_REGISTER call of the JSON array of the registrations
# of LANTERN_VALID; none with none, with no free call, or with no room in the actions. rbx the
# node, r15 the actions; r13 a record, r14 the records left, rbp the body's bytes, S7 the valid
# ones, S8 the request's bytes, S9 the call, S10 the cursor.
LOCAL_FUNCTION node_builder_register
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
    call    bld_reg_len
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
    call    bld_digits
    add     Node_builder_host_len(%rbx), %rax
    add     $BLD_HEAD_FIXED, %rax
    add     %rbp, %rax
    mov     %rax, S8(%rsp)
    lea     (48 + 7)(%rax), %rdi
    call    node_room
    test    %rax, %rax
    jz      9f
    mov     $NODE_BUILDER_REGISTER, %edi
    mov     $-1, %rsi
    call    node_builder_call
    cmp     $-1, %rax
    je      9f
    mov     %rax, S9(%rsp)
    mov     S8(%rsp), %rsi
    add     $(48 + 7), %rsi
    and     $-8, %rsi
    mov     $NODE_ACT_BUILDER, %edi
    call    node_act
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
    call    bld_put
    mov     %rax, %rdi
    lea     Node_builder_host(%rbx), %rsi
    mov     Node_builder_host_len(%rbx), %rdx
    call    bld_put
    mov     %rax, %rdi
    ADDRESS %rsi, bld_head_json
    mov     $bld_head_json_len, %edx
    call    bld_put
    mov     %rax, %rdi
    mov     %rbp, %rsi
    call    bld_dec
    mov     %rax, %rdi
    ADDRESS %rsi, bld_head_end
    mov     $bld_head_end_len, %edx
    call    bld_put
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
    call    bld_reg_json
    mov     %rax, S10(%rsp)
31: mov     16(%r13), %rax
    lea     16(%r13,%rax), %r13
    dec     %r14
    jmp     3b
4:  mov     S10(%rsp), %rax
    movb    $']', (%rax)
9:  LEAVE 0
END_FUNCTION node_builder_register

# L1: the registration of LANTERN_VALID at rdi (a ByteList of its 180 SSZ bytes) of the validator rsi
# (beacon-api.md, registerValidator): its NodeProposer entry takes it, unless the entry holds one of a
# later timestamp; with none, the first free entry (until_epoch at most the store rbp's epoch,
# registered 0), else a new one when the part has room; else none. rbx the node. Locals: the bytes,
# the index, the epoch.
LOCAL_FUNCTION node_registration_put
    FRAME 32
    mov     8(%rdi), %rax
    add     %rdi, %rax
    mov     %rax, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rbp, %rdi
    call    node_store_slot
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
9:  UNFRAME 32
END_FUNCTION node_registration_put

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
LOCAL_FUNCTION node_registrations_find
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
END_FUNCTION node_registrations_find
