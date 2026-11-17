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
LOCAL_FUNCTION jdata
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
END_FUNCTION jdata

/* L0: QUANTITY of the rcx bytes, little endian, at rsi: "0x" and the hex with no leading zeros, to rdi. Uses rax, rdx, r8. */
LOCAL_FUNCTION jquantity
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
END_FUNCTION jquantity

/* L0: the decimal digits of rax to rdi. Uses rax, rcx, rdx, r8. */
LOCAL_FUNCTION jdecimal
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
END_FUNCTION jdecimal

/* QUANTITY of the u64 at base + off, to rdi. Uses rsi, rcx, rax, rdx, r8. */
.macro JQ64 base, off
    lea     (\off)(\base), %rsi
    mov     $8, %ecx
    call    jquantity
.endm

/* DATA of the n bytes at base + off, to rdi. Uses rsi, rcx, rax, rdx. */
.macro JDATA base, off, n
    lea     (\off)(\base), %rsi
    mov     $\n, %ecx
    call    jdata
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
    call    jdecimal
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
    call    jdata
    JTEXT   j_base_fee
    lea     ExecutionPayload_base_fee_per_gas(%r15), %rsi
    mov     $32, %ecx
    call    jquantity
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
    call    jdata
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
    call    jdata
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

/* (state, id, out): rbx state, rbp id, r12 out. */
SPEC_FUNCTION engine_forkchoice_updated
    ENTER 0
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    cmpq    $(24 + 512), (%r12)
    jb      8f
    lea     24(%r12), %rdi
    JTEXT   j_open
    mov     %rbp, %rax
    call    jdecimal
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
    JTEXT   j_fcu_close
    lea     24(%r12), %rax
    sub     %rax, %rdi
    movq    $24, 8(%r12)
    mov     %rdi, 16(%r12)
    xor     %eax, %eax
    LEAVE 0
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
SPEC_END engine_forkchoice_updated

.endif
