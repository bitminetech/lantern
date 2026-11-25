/*
 * Engine API JSON-RPC requests, x86-64: in the objects of bellatrix and later.
 * Requirements: docs/reference/engine-api.md.
 *
 * The writers keep the write position in rdi: each takes it and gives the new one.
 */

.if FORK >= FORK_BELLATRIX

/* The JSON text, before the code that takes its lengths. */
    RODATA
.include "engine_json.inc"

/* The text at label (include/engine_json.inc) to rdi. Uses rsi, rcx. */
.macro JTEXT label
    lea     \label(%rip), %rsi
    mov     $\label\()_len, %ecx
    rep movsb
.endm

/* The byte c, a character code, to rdi. */
.macro JCHAR c
    movb    $\c, (%rdi)
    inc     %rdi
.endm

/* L0: DATA: "0x" and two lowercase hex digits for each of the rcx bytes at rsi, to rdi. Uses rax, rdx. */
LOCAL_FUNCTION lantern_jdata
    UNWIND_END_PROLOGUE
    movb    $'"', (%rdi)
    movb    $'0', 1(%rdi)
    movb    $'x', 2(%rdi)
    add     $3, %rdi
    test    %rcx, %rcx
    jz      3f
1:  movzbl  (%rsi), %eax
    inc     %rsi
    mov     %eax, %edx
    shr     $4, %edx
    cmp     $10, %edx
    jb      4f
    add     $('a' - 10 - '0'), %edx
4:  add     $'0', %edx
    mov     %dl, (%rdi)
    and     $15, %eax
    cmp     $10, %eax
    jb      5f
    add     $('a' - 10 - '0'), %eax
5:  add     $'0', %eax
    mov     %al, 1(%rdi)
    add     $2, %rdi
    dec     %rcx
    jnz     1b
3:  movb    $'"', (%rdi)
    inc     %rdi
    ret
END_FUNCTION lantern_jdata

/* L0: QUANTITY of the rcx bytes, little endian, at rsi: "0x" and the hex with no leading zeros, to rdi. Uses rax, rdx, r8. */
LOCAL_FUNCTION lantern_jquantity
    UNWIND_END_PROLOGUE
    movb    $'"', (%rdi)
    movb    $'0', 1(%rdi)
    movb    $'x', 2(%rdi)
    add     $3, %rdi
    lea     (%rcx,%rcx), %rdx               # the digits, from the most significant
    xor     %r8d, %r8d                      # 1 once a digit other than 0 is written
1:  dec     %rdx
    mov     %rdx, %rax
    shr     $1, %rax
    movzbl  (%rsi,%rax), %eax
    test    $1, %dl
    jz      2f
    shr     $4, %eax
2:  and     $15, %eax
    test    %r8, %r8
    jnz     3f
    test    %rdx, %rdx                      # a leading zero, but the last digit is always written
    jz      3f
    test    %eax, %eax
    jz      5f
3:  mov     $1, %r8d
    cmp     $10, %eax
    jb      6f
    add     $('a' - 10 - '0'), %eax
6:  add     $'0', %eax
    mov     %al, (%rdi)
    inc     %rdi
5:  test    %rdx, %rdx
    jnz     1b
    movb    $'"', (%rdi)
    inc     %rdi
    ret
END_FUNCTION lantern_jquantity

/* L0: the decimal digits of rax to rdi. Uses rax, rcx, rdx, r8. */
LOCAL_FUNCTION lantern_jdecimal
    UNWIND_END_PROLOGUE
    mov     $10, %ecx
    mov     %rax, %r8
1:  xor     %edx, %edx
    div     %rcx
    inc     %rdi
    test    %rax, %rax
    jnz     1b
    mov     %r8, %rax
    mov     %rdi, %r8
2:  xor     %edx, %edx
    div     %rcx
    add     $'0', %dl
    dec     %r8
    mov     %dl, (%r8)
    test    %rax, %rax
    jnz     2b
    ret
END_FUNCTION lantern_jdecimal

/* QUANTITY of the u64 at base + off, to rdi. Uses rsi, rcx, rax, rdx, r8. */
.macro JQ64 base, off
    lea     (\off)(\base), %rsi
    mov     $8, %ecx
    call    lantern_jquantity
.endm

/* DATA of the n bytes at base + off, to rdi. Uses rsi, rcx, rax, rdx. */
.macro JDATA base, off, n
    lea     (\off)(\base), %rsi
    mov     $\n, %ecx
    call    lantern_jdata
.endm

.set DEPOSIT_REQUEST_SSZ, 48 + 32 + 8 + 96 + 8
.set WITHDRAWAL_REQUEST_SSZ, 20 + 48 + 8
.set CONSOLIDATION_REQUEST_SSZ, 20 + 48 + 48

.if FORK >= FORK_ELECTRA
.if DepositRequest_pubkey != 0 || DepositRequest_withdrawal_credentials != 48 || DepositRequest_amount != 80 || DepositRequest_signature != 88 || DepositRequest_index != 184 || DepositRequest__mem != DEPOSIT_REQUEST_SSZ
.error "a DepositRequest value is its SSZ bytes"
.endif
.if ConsolidationRequest_source_address != 0 || ConsolidationRequest_source_pubkey != 20 || ConsolidationRequest_target_pubkey != 68 || ConsolidationRequest__mem != CONSOLIDATION_REQUEST_SSZ
.error "a ConsolidationRequest value is its SSZ bytes"
.endif
.if WithdrawalRequest_source_address != 0 || WithdrawalRequest_validator_pubkey != 20
.error "a WithdrawalRequest value starts with its first 68 SSZ bytes"
.endif

/*
 * (execution_requests, out): rbx the requests, rbp out, r12 the write position, r13 the type,
 * r14 the entries, r15 their count, S7 the SSZ bytes of one request.
 */
SPEC_FUNCTION get_execution_requests_list
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     24(%rbp), %r12
    xor     %r13d, %r13d
1:  cmp     $3, %r13                        # each kind, in type order
    jae     9f
    cmp     $1, %r13
    je      2f
    ja      3f
    PART    %r14, %r15, %rbx, ExecutionRequests_deposits
    movq    $DEPOSIT_REQUEST_SSZ, S7(%rsp)
    jmp     4f
2:  PART    %r14, %r15, %rbx, ExecutionRequests_withdrawals
    movq    $WITHDRAWAL_REQUEST_SSZ, S7(%rsp)
    jmp     4f
3:  PART    %r14, %r15, %rbx, ExecutionRequests_consolidations
    movq    $CONSOLIDATION_REQUEST_SSZ, S7(%rsp)
4:  test    %r15, %r15                      # an empty list: no element
    jz      8f
    mov     S7(%rsp), %rax                  # the element: its length, the type, the requests
    imul    %r15, %rax
    inc     %rax
    mov     (%rbp), %rcx                    # room: 8 + the element
    add     %rbp, %rcx
    sub     %r12, %rcx
    lea     8(%rax), %rdx
    cmp     %rdx, %rcx
    jb      7f
    mov     %rax, (%r12)
    mov     %r13b, 8(%r12)
    add     $9, %r12
5:  mov     %r12, %rdi                      # each request's SSZ bytes
    mov     %r14, %rsi
    cmp     $1, %r13
    je      6f
    mov     S7(%rsp), %rcx
    add     %rcx, %r12
    rep movsb
    mov     $DepositRequest__mem, %eax
    mov     $ConsolidationRequest__mem, %ecx
    test    %r13, %r13
    cmovne  %rcx, %rax
    jmp     11f
6:  mov     $(20 + 48), %ecx                # a withdrawal request: its amount after a pad
    rep movsb
    mov     WithdrawalRequest_amount(%r14), %rax
    mov     %rax, (%rdi)
    add     $WITHDRAWAL_REQUEST_SSZ, %r12
    mov     $WithdrawalRequest__mem, %eax
11: add     %rax, %r14
    dec     %r15
    jnz     5b
8:  inc     %r13
    jmp     1b
9:  lea     24(%rbp), %rax
    mov     %r12, %rcx
    sub     %rax, %rcx
    movq    $24, 8(%rbp)
    mov     %rcx, 16(%rbp)
    xor     %eax, %eax
    LEAVE 0
7:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
SPEC_END get_execution_requests_list

/*
 * (list, out): rbx the list's bytes, rbp their count, r12 out, r13 the item, r14 the items, r15 the
 * lowest type the item may have. Locals: L, L+16, L+32 the data of each type, its address and its
 * bytes.
 */
SPEC_FUNCTION get_execution_requests
    ENTER 48
    mov     8(%rdi), %rax
    mov     16(%rdi), %rbp
    lea     (%rdi,%rax), %rbx
    mov     %rsi, %r12
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, L(%rsp)
    movdqu  %xmm0, (L + 16)(%rsp)
    movdqu  %xmm0, (L + 32)(%rsp)
    test    %rbp, %rbp                      # the SSZ list: no item, or the first offset, 4 an item, at most 3
    jz      5f
    cmp     $4, %rbp
    jb      9f
    mov     (%rbx), %eax
    test    $3, %eax
    jnz     9f
    test    %eax, %eax
    jz      9f
    cmp     $12, %eax
    ja      9f
    cmp     %rbp, %rax
    ja      9f
    shr     $2, %eax
    mov     %rax, %r14
    xor     %r13d, %r13d
    xor     %r15d, %r15d
1:  mov     (%rbx,%r13,4), %eax             # item r13: from its offset to the next, or to the end
    mov     %rbp, %rcx
    lea     1(%r13), %rdx
    cmp     %r14, %rdx
    jae     2f
    mov     (%rbx,%rdx,4), %ecx
2:  cmp     %rcx, %rax
    ja      9f
    cmp     %rbp, %rcx
    ja      9f
    sub     %rax, %rcx                      # a type in ascending order, and data
    cmp     $2, %rcx
    jb      9f
    movzbl  (%rbx,%rax), %edx
    cmp     %r15, %rdx
    jb      9f
    cmp     $3, %rdx
    jae     9f
    lea     1(%rdx), %r15
    dec     %rcx
    lea     1(%rbx,%rax), %rsi
    mov     $DEPOSIT_REQUEST_SSZ, %r8d      # the data: whole requests of the type, at most its limit
    mov     $(DEPOSIT_REQUEST_SSZ * MAX_DEPOSIT_REQUESTS_PER_PAYLOAD), %r9d
    cmp     $1, %edx
    jb      6f
    mov     $WITHDRAWAL_REQUEST_SSZ, %r8d
    mov     $(WITHDRAWAL_REQUEST_SSZ * MAX_WITHDRAWAL_REQUESTS_PER_PAYLOAD), %r9d
    je      6f
    mov     $CONSOLIDATION_REQUEST_SSZ, %r8d
    mov     $(CONSOLIDATION_REQUEST_SSZ * MAX_CONSOLIDATION_REQUESTS_PER_PAYLOAD), %r9d
6:  cmp     %r9, %rcx
    ja      9f
    mov     %rdx, %r10
    mov     %rcx, %rax
    xor     %edx, %edx
    div     %r8
    test    %rdx, %rdx
    jnz     9f
    shl     $4, %r10
    mov     %rsi, L(%rsp,%r10)
    mov     %rcx, (L + 8)(%rsp,%r10)
    inc     %r13
    cmp     %r14, %r13
    jb      1b
5:  mov     (L + 8)(%rsp), %rax             # ExecutionRequests: three offsets, then the data of each type
    add     (L + 24)(%rsp), %rax
    add     (L + 40)(%rsp), %rax
    add     $12, %rax
    mov     (%r12), %rcx
    sub     $24, %rcx
    jb      8f
    cmp     %rax, %rcx
    jb      8f
    movq    $24, 8(%r12)
    mov     %rax, 16(%r12)
    lea     24(%r12), %rdi
    mov     $12, %eax
    mov     %eax, (%rdi)
    add     (L + 8)(%rsp), %eax
    mov     %eax, 4(%rdi)
    add     (L + 24)(%rsp), %eax
    mov     %eax, 8(%rdi)
    add     $12, %rdi
    xor     %r13d, %r13d
7:  mov     %r13, %rax
    shl     $4, %rax
    mov     L(%rsp,%rax), %rsi
    mov     (L + 8)(%rsp,%rax), %rcx
    rep movsb
    inc     %r13
    cmp     $3, %r13
    jb      7b
    xor     %eax, %eax
    LEAVE 48
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
9:  mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 48
SPEC_END get_execution_requests
.endif

/* (block, out): the bound of engine-api.md. rax the bound; rcx, rdx, r8-r11 work. */
SPEC_LEAF engine_new_payload_size
    PART    %r8, %r9, %rdi, BeaconBlock_body
    PART    %r10, %r9, %r8, BeaconBlockBody_execution_payload
    mov     $4096, %eax
    PART    %r11, %rcx, %r10, ExecutionPayload_extra_data   # twice the bytes of extra_data
    lea     (%rax,%rcx,2), %rax
    PART    %r11, %rcx, %r10, ExecutionPayload_transactions  # 8 + twice the bytes of each transaction
1:  test    %rcx, %rcx
    jz      2f
    mov     16(%r11), %rdx
    lea     8(%rax,%rdx,2), %rax
    add     (%r11), %r11
    dec     %rcx
    jmp     1b
2:
.if FORK >= FORK_CAPELLA
    imul    $160, (ExecutionPayload_withdrawals + 8)(%r10), %rcx    # 160 for each withdrawal
    add     %rcx, %rax
.endif
.if FORK >= FORK_DENEB
    imul    $72, (BeaconBlockBody_blob_kzg_commitments + 8)(%r8), %rcx    # 72 for each commitment
    add     %rcx, %rax
.endif
.if FORK >= FORK_ELECTRA
    PART    %r10, %r9, %r8, BeaconBlockBody_execution_requests      # 8 + twice the bytes of each list
    imul    $(2 * DEPOSIT_REQUEST_SSZ), (ExecutionRequests_deposits + 8)(%r10), %rcx
    add     %rcx, %rax
    imul    $(2 * WITHDRAWAL_REQUEST_SSZ), (ExecutionRequests_withdrawals + 8)(%r10), %rcx
    add     %rcx, %rax
    imul    $(2 * CONSOLIDATION_REQUEST_SSZ), (ExecutionRequests_consolidations + 8)(%r10), %rcx
    add     %rcx, %rax
    add     $(3 * (8 + 2)), %rax
.endif
    mov     %rax, (%rsi)
    RETURN_OK
SPEC_END engine_new_payload_size

/*
 * (block, id, scratch, out): rbx block, rbp id, r12 scratch, r13 out, r14 body, r15 payload,
 * S7 entries, S8 their count, S9 the end of the request lists.
 * Locals: L the bound, L+16 a versioned hash.
 */
SPEC_FUNCTION engine_new_payload
    ENTER 48
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    lea     L(%rsp), %rsi                   # room for the bound
    call    lantern_engine_new_payload_size
    mov     (%r13), %rax
    sub     $24, %rax
    jb      8f
    cmp     L(%rsp), %rax
    jb      8f
    PART    %r14, %rax, %rbx, BeaconBlock_body
    PART    %r15, %rax, %r14, BeaconBlockBody_execution_payload
    lea     24(%r13), %rdi
    # {"jsonrpc":"2.0","id":id,"method":"engine_newPayloadVn","params":[
    JTEXT   j_open
    mov     %rbp, %rax
    call    lantern_jdecimal
    JTEXT   j_method_np
.if FORK == FORK_BELLATRIX
    JCHAR   49
.elseif FORK == FORK_CAPELLA
    JCHAR   50
.elseif FORK == FORK_DENEB
    JCHAR   51
.else
    JCHAR   52
.endif
    JTEXT   j_params
    # the payload
    JTEXT   j_parent_hash
    JDATA   %r15, ExecutionPayload_parent_hash, 32
    JTEXT   j_fee_recipient
    JDATA   %r15, ExecutionPayload_fee_recipient, 20
    JTEXT   j_state_root
    JDATA   %r15, ExecutionPayload_state_root, 32
    JTEXT   j_receipts_root
    JDATA   %r15, ExecutionPayload_receipts_root, 32
    JTEXT   j_logs_bloom
    JDATA   %r15, ExecutionPayload_logs_bloom, BYTES_PER_LOGS_BLOOM
    JTEXT   j_prev_randao
    JDATA   %r15, ExecutionPayload_prev_randao, 32
    JTEXT   j_block_number
    JQ64    %r15, ExecutionPayload_block_number
    JTEXT   j_gas_limit
    JQ64    %r15, ExecutionPayload_gas_limit
    JTEXT   j_gas_used
    JQ64    %r15, ExecutionPayload_gas_used
    JTEXT   j_timestamp
    JQ64    %r15, ExecutionPayload_timestamp
    JTEXT   j_extra_data
    PART    %rsi, %rcx, %r15, ExecutionPayload_extra_data
    call    lantern_jdata
    JTEXT   j_base_fee
    lea     ExecutionPayload_base_fee_per_gas(%r15), %rsi
    mov     $32, %ecx
    call    lantern_jquantity
    JTEXT   j_block_hash
    JDATA   %r15, ExecutionPayload_block_hash, 32
    # each transaction: a nested ByteList value
    JTEXT   j_transactions
    PART    %rax, %rcx, %r15, ExecutionPayload_transactions
    mov     %rax, S7(%rsp)
    mov     %rcx, S8(%rsp)
    test    %rcx, %rcx
    jz      2f
1:  mov     S7(%rsp), %rax
    mov     8(%rax), %rsi
    add     %rax, %rsi
    mov     16(%rax), %rcx
    add     (%rax), %rax
    mov     %rax, S7(%rsp)
    call    lantern_jdata
    decq    S8(%rsp)
    jz      2f
    JCHAR   44
    jmp     1b
2:
.if FORK >= FORK_CAPELLA
    JTEXT   j_withdrawals
    PART    %rax, %rcx, %r15, ExecutionPayload_withdrawals
    mov     %rax, S7(%rsp)
    mov     %rcx, S8(%rsp)
    test    %rcx, %rcx
    jz      4f
3:  JTEXT   j_w_index
    mov     S7(%rsp), %rax
    JQ64    %rax, Withdrawal_index
    JTEXT   j_w_validator
    mov     S7(%rsp), %rax
    JQ64    %rax, Withdrawal_validator_index
    JTEXT   j_w_address
    mov     S7(%rsp), %rax
    JDATA   %rax, Withdrawal_address, 20
    JTEXT   j_w_amount
    mov     S7(%rsp), %rax
    JQ64    %rax, Withdrawal_amount
    JCHAR   125
    addq    $Withdrawal__mem, S7(%rsp)
    decq    S8(%rsp)
    jz      4f
    JCHAR   44
    jmp     3b
4:
.endif
.if FORK >= FORK_DENEB
    JTEXT   j_blob_gas_used
    JQ64    %r15, ExecutionPayload_blob_gas_used
    JTEXT   j_excess_blob_gas
    JQ64    %r15, ExecutionPayload_excess_blob_gas
    JCHAR   125
    # the versioned hashes of the commitments
    JCHAR   44
    JCHAR   91
    PART    %rax, %rcx, %r14, BeaconBlockBody_blob_kzg_commitments
    mov     %rax, S7(%rsp)
    mov     %rcx, S8(%rsp)
    test    %rcx, %rcx
    jz      6f
5:  mov     %rdi, S9(%rsp)
    mov     S7(%rsp), %rdi
    lea     (L + 16)(%rsp), %rsi
    call    lantern_kzg_commitment_to_versioned_hash
    mov     S9(%rsp), %rdi
    JDATA   %rsp, (L + 16), 32
    addq    $48, S7(%rsp)
    decq    S8(%rsp)
    jz      6f
    JCHAR   44
    jmp     5b
6:  JCHAR   93
    JCHAR   44
    # parentBeaconBlockRoot
    JDATA   %rbx, BeaconBlock_parent_root, 32
.else
    JCHAR   93
    JCHAR   125
.endif
.if FORK >= FORK_ELECTRA
    # the request lists, through scratch
    JCHAR   44
    JCHAR   91
    mov     %rdi, S9(%rsp)
    PART    %rdi, %rax, %r14, BeaconBlockBody_execution_requests
    mov     %r12, %rsi
    movq    $24, 8(%r12)
    movq    $0, 16(%r12)
    call    lantern_get_execution_requests_list
    test    %rax, %rax
    jnz     8f
    mov     S9(%rsp), %rdi
    lea     24(%r12), %rax
    mov     %rax, S7(%rsp)
    add     16(%r12), %rax
    mov     %rax, S8(%rsp)                  # the end
7:  mov     S7(%rsp), %rax
    cmp     S8(%rsp), %rax
    jae     9f
    lea     8(%rax), %rsi
    mov     (%rax), %rcx
    lea     (%rsi,%rcx), %rax
    mov     %rax, S7(%rsp)
    call    lantern_jdata
    mov     S7(%rsp), %rax
    cmp     S8(%rsp), %rax
    jae     9f
    JCHAR   44
    jmp     7b
9:  JCHAR   93
.endif
    JTEXT   j_close
    lea     24(%r13), %rax
    sub     %rax, %rdi
    movq    $24, 8(%r13)
    mov     %rdi, 16(%r13)
    xor     %eax, %eax
    LEAVE 48
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
SPEC_END engine_new_payload

/* (state, attributes, id, out): rbx state, rbp id, r12 out, r13 attributes, r14 a withdrawal, r15 those left. */
SPEC_FUNCTION engine_forkchoice_updated
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %r13
    mov     (%rdx), %rbp
    mov     %rcx, %r12
    mov     $(24 + 512), %eax               # the room: 512 bytes, or 1024 and 192 a withdrawal
    test    %r13, %r13
    jz      1f
    mov     $(24 + 1024), %eax
.if FORK >= FORK_CAPELLA
    imul    $192, PayloadAttributes_withdrawals(%r13), %rcx
    add     %rcx, %rax
.endif
1:  cmp     %rax, (%r12)
    jb      8f
    lea     24(%r12), %rdi
    JTEXT   j_open
    mov     %rbp, %rax
    call    lantern_jdecimal
    JTEXT   j_method_fcu
.if FORK == FORK_BELLATRIX
    JCHAR   49
.elseif FORK == FORK_CAPELLA
    JCHAR   50
.else
    JCHAR   51
.endif
    JTEXT   j_params
    JTEXT   j_head
    JDATA   %rbx, 0, 32
    JTEXT   j_safe
    JDATA   %rbx, 32, 32
    JTEXT   j_finalized
    JDATA   %rbx, 64, 32
    test    %r13, %r13
    jnz     2f
    JTEXT   j_fcu_close
    jmp     7f
    # the PayloadAttributes
2:  JTEXT   j_attr_open
    JQ64    %r13, PayloadAttributes_timestamp
    JTEXT   j_prev_randao
    JDATA   %r13, PayloadAttributes_prev_randao, 32
    JTEXT   j_attr_fee_recipient
    JDATA   %r13, PayloadAttributes_suggested_fee_recipient, 20
.if FORK >= FORK_CAPELLA
    # each withdrawal: its 44 SSZ bytes
    JTEXT   j_attr_withdrawals
    lea     PAYLOAD_ATTRIBUTES_WITHDRAWAL(%r13), %r14
    mov     PayloadAttributes_withdrawals(%r13), %r15
    test    %r15, %r15
    jz      4f
3:  JTEXT   j_w_index
    JQ64    %r14, 0
    JTEXT   j_w_validator
    JQ64    %r14, 8
    JTEXT   j_w_address
    JDATA   %r14, 16, 20
    JTEXT   j_w_amount
    JQ64    %r14, 36
    JCHAR   125
    add     $PAYLOAD_ATTRIBUTES_WITHDRAWAL_SIZE, %r14
    dec     %r15
    jz      4f
    JCHAR   44
    jmp     3b
4:  JCHAR   93
.endif
.if FORK >= FORK_DENEB
    JTEXT   j_attr_parent_root
    JDATA   %r13, PayloadAttributes_parent_beacon_block_root, 32
.endif
    JTEXT   j_attr_close
7:  lea     24(%r12), %rax
    sub     %rax, %rdi
    movq    $24, 8(%r12)
    mov     %rdi, 16(%r12)
    xor     %eax, %eax
    LEAVE 0
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
SPEC_END engine_forkchoice_updated

/* (payload_id, id, out): rbx payload_id, rbp id, r12 out. */
SPEC_FUNCTION engine_get_payload
    ENTER 0
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    cmpq    $(24 + 256), (%r12)
    jb      8f
    lea     24(%r12), %rdi
    JTEXT   j_open
    mov     %rbp, %rax
    call    lantern_jdecimal
    JTEXT   j_method_gp
.if FORK == FORK_BELLATRIX
    JCHAR   49
.elseif FORK == FORK_CAPELLA
    JCHAR   50
.elseif FORK == FORK_DENEB
    JCHAR   51
.elseif FORK == FORK_ELECTRA
    JCHAR   52
.else
    JCHAR   53
.endif
    JTEXT   j_params
    JDATA   %rbx, 0, 8
    JTEXT   j_close
    lea     24(%r12), %rax
    sub     %rax, %rdi
    movq    $24, 8(%r12)
    mov     %rdi, 16(%r12)
    xor     %eax, %eax
    LEAVE 0
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
SPEC_END engine_get_payload

.if FORK >= FORK_CAPELLA
.if Withdrawal_index != 0 || Withdrawal_validator_index != 8
.error "get_payload_attributes copies index and validator_index as the first 16 bytes of a Withdrawal"
.endif
.endif

/*
 * (state, fee_recipient, config, scratch, out): rbx state, rbp fee_recipient, r12 config, r13
 * scratch, r14 out, r15 the ExpectedWithdrawals. Locals: L the current epoch, L+8 the scratch size.
 */
SPEC_FUNCTION get_payload_attributes
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    lea     BeaconState_genesis_time(%rbx), %rdi
    lea     BeaconState_slot(%rbx), %rsi
    mov     %r12, %rdx
    lea     PayloadAttributes_timestamp(%r14), %rcx
    call    lantern_compute_time_at_slot
    test    %rax, %rax
    jnz     9f
    mov     %rbx, %rdi                      # prev_randao: the mix of the current epoch
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    test    %rax, %rax
    jnz     9f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    lea     PayloadAttributes_prev_randao(%r14), %rdx
    call    lantern_get_randao_mix
    test    %rax, %rax
    jnz     9f
    mov     (%rbp), %rax                    # the fee recipient, then 4 zero bytes
    mov     8(%rbp), %rcx
    mov     16(%rbp), %edx
    mov     %rax, PayloadAttributes_suggested_fee_recipient(%r14)
    mov     %rcx, (PayloadAttributes_suggested_fee_recipient + 8)(%r14)
    mov     %rdx, (PayloadAttributes_suggested_fee_recipient + 16)(%r14)
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, PayloadAttributes_parent_beacon_block_root(%r14)
    movdqu  %xmm0, (PayloadAttributes_parent_beacon_block_root + 16)(%r14)
    movq    $0, PayloadAttributes_withdrawals(%r14)
.if FORK >= FORK_DENEB
    # parent_beacon_block_root = hash_tree_root(state.latest_block_header)
    ADDRESS %rdi, lantern_type_BeaconBlockHeader
    lea     BeaconState_latest_block_header(%rbx), %rsi
    mov     %r13, %rdx
    lea     PayloadAttributes_parent_beacon_block_root(%r14), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     9f
.endif
.if FORK >= FORK_CAPELLA
    mov     (%r13), %rax                    # get_expected_withdrawals, its value at the end of scratch
    mov     %rax, (L + 8)(%rsp)
    cmp     $(EXPECTED_SCRATCH + SWEEP_BYTES), %rax
    jb      8f
    sub     $SWEEP_BYTES, %rax
    lea     (%r13,%rax), %r15
    mov     %rax, (%r13)
    mov     %rbx, %rdi
    mov     %r13, %rsi
    mov     %r15, %rdx
    call    lantern_get_expected_withdrawals
    mov     (L + 8)(%rsp), %rcx
    mov     %rcx, (%r13)
    test    %rax, %rax
    jnz     9f
    mov     (16 + LIST_COUNT)(%r15), %rcx
    mov     %rcx, PayloadAttributes_withdrawals(%r14)
    lea     (16 + LIST_FIXED)(%r15), %rsi
    lea     PAYLOAD_ATTRIBUTES_WITHDRAWAL(%r14), %rdi
1:  test    %rcx, %rcx                      # each withdrawal: its 44 SSZ bytes
    jz      2f
    movdqu  (%rsi), %xmm0
    movdqu  %xmm0, (%rdi)
    movdqu  Withdrawal_address(%rsi), %xmm0
    movdqu  %xmm0, 16(%rdi)
    mov     (Withdrawal_address + 16)(%rsi), %eax
    mov     %eax, 32(%rdi)
    mov     Withdrawal_amount(%rsi), %rax
    mov     %rax, 36(%rdi)
    add     $Withdrawal__mem, %rsi
    add     $PAYLOAD_ATTRIBUTES_WITHDRAWAL_SIZE, %rdi
    dec     %rcx
    jmp     1b
2:
.endif
    xor     %eax, %eax
9:  LEAVE 16
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END get_payload_attributes

.endif
