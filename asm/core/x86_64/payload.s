/*
 * The execution payload, x86-64. Requirements: docs/reference/block-processing.md.
 */

.if FORK >= FORK_FULU
SPEC_LEAF get_blob_parameters
    mov     (%rdi), %rax                    # epoch
    mov     CONFIG_BLOB_SCHEDULE_COUNT(%rsi), %rcx
1:  test    %rcx, %rcx                      # the schedule, from its latest epoch down
    jz      2f
    dec     %rcx
    mov     %rcx, %r8
    shl     $4, %r8
    mov     CONFIG_BLOB_SCHEDULE(%rsi,%r8), %r9
    cmp     %r9, %rax
    jb      1b
    mov     (CONFIG_BLOB_SCHEDULE + 8)(%rsi,%r8), %r8
    mov     %r9, (%rdx)
    mov     %r8, 8(%rdx)
    RETURN_OK
2:  mov     CONFIG_ELECTRA_FORK_EPOCH(%rsi), %r9
    mov     CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA(%rsi), %r8
    mov     %r9, (%rdx)
    mov     %r8, 8(%rdx)
    RETURN_OK
SPEC_END get_blob_parameters
.endif

.if FORK >= FORK_DENEB
/* Locals: rsp+0 out. */
SPEC_FUNCTION kzg_commitment_to_versioned_hash
    FRAME 16
    mov     %rsi, 0(%rsp)
    mov     %rsi, %rdx
    mov     $48, %esi
    call    sha256_short
    mov     0(%rsp), %rsi
    movb    $VERSIONED_HASH_VERSION_KZG, (%rsi)
    xor     %eax, %eax
    UNFRAME 16
SPEC_END kzg_commitment_to_versioned_hash
.endif

SPEC_LEAF compute_time_at_slot
    mov     %rdx, %r8                       # config
    mov     (%rdi), %rax                    # genesis_time
    mov     $1000, %r9d
    mul     %r9                             # seconds_to_milliseconds saturates at UINT64_MAX
    test    %rdx, %rdx
    jz      1f
    mov     $-1, %rax
1:  mov     %rax, %r10
    mov     (%rsi), %rax                    # genesis_time_ms + slot * SLOT_DURATION_MS
    mulq    CONFIG_SLOT_DURATION_MS(%r8)
    test    %rdx, %rdx
    jnz     2f
    add     %r10, %rax
    jc      2f
    xor     %edx, %edx                      # milliseconds_to_seconds
    div     %r9
    mov     %rax, (%rcx)
    RETURN_OK
2:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END compute_time_at_slot

.if FORK >= FORK_BELLATRIX
/*
 * rbx state, rbp body, r12 config, r13 scratch, r14 result, r15 payload,
 * S7 execution_valid, S8 the new header, S9 scratch size.
 * Locals: L epoch, L+8 mix, L+40 time, L+48 blob parameters (16).
 */
SPEC_FUNCTION process_execution_payload
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, S7(%rsp)
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     %r9, %r14
    PART    %r15, %rax, %rbp, BeaconBlockBody_execution_payload
    # Scratch: the new header value, then a standalone Transactions or Withdrawals value to hash.
    mov     ExecutionPayload_withdrawals(%r15), %rcx
    sub     ExecutionPayload_transactions(%r15), %rcx  # bytes of the transactions part
    MOVQ    %rax, LANTERN_SCRATCH_FIXED + HEADER_ROOM + 24 + WLIST_BYTES
    add     %rcx, %rax
    mov     (%r13), %rcx
    mov     %rcx, S9(%rsp)
    cmp     %rax, %rcx
    jb      9f
    mov     BeaconState_latest_execution_payload_header(%rbx), %rax    # the header value in its part
    lea     ExecutionPayloadHeader_block_hash(%rbx,%rax), %rcx
    lea     ExecutionPayload_parent_hash(%r15), %rdx
    mov     $LANTERN_INVALID_PAYLOAD_PARENT_HASH, %eax  # assert payload.parent_hash == latest header's block_hash
    NE32    %rdx, %rcx, 6f
    mov     %rbx, %rdi
    lea     L(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     %rbx, %rdi                      # assert payload.prev_randao == get_randao_mix(state, epoch)
    lea     L(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_get_randao_mix
    lea     ExecutionPayload_prev_randao(%r15), %rcx
    lea     (L + 8)(%rsp), %rdx
    mov     $LANTERN_INVALID_PAYLOAD_PREV_RANDAO, %eax
    NE32    %rcx, %rdx, 6f
    lea     BeaconState_genesis_time(%rbx), %rdi    # assert payload.timestamp == compute_time_at_slot(...)
    lea     BeaconState_slot(%rbx), %rsi
    mov     %r12, %rdx
    lea     (L + 40)(%rsp), %rcx
    call    lantern_compute_time_at_slot
    test    %rax, %rax
    jnz     6f
    mov     ExecutionPayload_timestamp(%r15), %rcx
    mov     $LANTERN_INVALID_PAYLOAD_TIMESTAMP, %eax
    cmp     (L + 40)(%rsp), %rcx
    jne     6f
    lea     L(%rsp), %rdi                   # assert len(blob_kzg_commitments) <= max_blobs_per_block
    mov     %r12, %rsi
    lea     (L + 48)(%rsp), %rdx
    call    lantern_get_blob_parameters
    mov     (BeaconBlockBody_blob_kzg_commitments + 8)(%rbp), %rcx
    mov     $LANTERN_INVALID_BLOB_COUNT, %eax
    cmp     (L + 56)(%rsp), %rcx
    ja      6f
    mov     S7(%rsp), %rcx                  # assert execution_engine.verify_and_notify_new_payload(...)
    mov     $LANTERN_INVALID_PAYLOAD, %eax
    cmpq    $0, (%rcx)
    je      6f
    # The new header, built in scratch before the state changes.
    mov     S9(%rsp), %rax
    sub     $HEADER_ROOM, %rax
    add     %r13, %rax
    mov     %rax, S8(%rsp)
    mov     %rax, %rdi
    mov     %r15, %rsi
    mov     %r13, %rdx
    mov     S9(%rsp), %rcx
    call    build_payload_header
    test    %rax, %rax
    jnz     7f
    mov     BeaconState_latest_execution_payload_header(%rbx), %rdi    # state.latest_execution_payload_header = header
    add     %rbx, %rdi
    mov     S8(%rsp), %rsi
    mov     (%rsi), %rdx
    call    lantern_copy
    movq    $0, (%r14)
    xor     %eax, %eax
7:  LEAVE 64
6:  mov     %rax, (%r14)
    xor     %eax, %eax
    LEAVE 64
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
SPEC_END process_execution_payload
.endif

.if FORK >= FORK_BELLATRIX
/*
 * The ExecutionPayloadHeader of payload rsi at rdi, with scratch rdx of size rcx whose last
 * HEADER_ROOM bytes hold rdi. rbx header, rbp payload, r12 scratch, r13 scratch size,
 * r14 a standalone value to hash, r15 bytes of the transactions part.
 */
LOCAL_FUNCTION build_payload_header
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    movq    $ExecutionPayloadHeader__fixed, (%rbx)  # size, without extra_data so far
    lea     ExecutionPayloadHeader_parent_hash(%rbx), %rdi  # parent_hash to prev_randao: one layout
    lea     ExecutionPayload_parent_hash(%rbp), %rsi
    mov     $(ExecutionPayload_block_number - ExecutionPayload_parent_hash), %edx
    call    lantern_copy
    .irp f, block_number, gas_limit, gas_used, timestamp, blob_gas_used, excess_blob_gas
    mov     ExecutionPayload_\f(%rbp), %rax
    mov     %rax, ExecutionPayloadHeader_\f(%rbx)
    .endr
    lea     ExecutionPayloadHeader_base_fee_per_gas(%rbx), %rdi
    lea     ExecutionPayload_base_fee_per_gas(%rbp), %rsi
    COPY32  %rdi, %rsi
    lea     ExecutionPayloadHeader_block_hash(%rbx), %rdi
    lea     ExecutionPayload_block_hash(%rbp), %rsi
    COPY32  %rdi, %rsi
    PART    %rsi, %rdx, %rbp, ExecutionPayload_extra_data   # extra_data: its part after the fixed fields
    movq    $ExecutionPayloadHeader__fixed, ExecutionPayloadHeader_extra_data(%rbx)
    mov     %rdx, (ExecutionPayloadHeader_extra_data + 8)(%rbx)
    lea     ExecutionPayloadHeader__fixed(%rbx), %rdi
    lea     (ExecutionPayloadHeader__fixed + 7)(%rdx), %rax
    and     $-8, %rax
    mov     %rax, (%rbx)
    call    lantern_copy
    # withdrawals_root = hash_tree_root(payload.withdrawals): a standalone Withdrawals value in scratch.
    lea     -(HEADER_ROOM + WLIST_BYTES)(%r13), %rax
    lea     (%r12,%rax), %r14
    movq    $WLIST_BYTES, LIST_SIZE(%r14)
    movq    $LIST_FIXED, LIST_OFFSET(%r14)
    PART    %rsi, %rdx, %rbp, ExecutionPayload_withdrawals
    mov     %rdx, LIST_COUNT(%r14)
    lea     LIST_FIXED(%r14), %rdi
    imul    $Withdrawal__mem, %rdx, %rdx
    call    lantern_copy
    lea     -(HEADER_ROOM + WLIST_BYTES)(%r13), %rax
    mov     %rax, (%r12)
    ADDRESS %rdi, lantern_type_Withdrawals
    mov     %r14, %rsi
    mov     %r12, %rdx
    lea     ExecutionPayloadHeader_withdrawals_root(%rbx), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    # transactions_root = hash_tree_root(payload.transactions): its part copied into a standalone value.
    mov     ExecutionPayload_withdrawals(%rbp), %r15
    sub     ExecutionPayload_transactions(%rbp), %r15  # bytes of the part
    mov     %r13, %rax
    sub     $(HEADER_ROOM + LIST_FIXED), %rax
    sub     %r15, %rax
    lea     (%r12,%rax), %r14
    lea     LIST_FIXED(%r15), %rax
    mov     %rax, LIST_SIZE(%r14)
    movq    $LIST_FIXED, LIST_OFFSET(%r14)
    PART    %rsi, %rdx, %rbp, ExecutionPayload_transactions
    mov     %rdx, LIST_COUNT(%r14)
    lea     LIST_FIXED(%r14), %rdi
    mov     %r15, %rdx
    call    lantern_copy
    mov     %r14, %rax
    sub     %r12, %rax
    mov     %rax, (%r12)
    ADDRESS %rdi, lantern_type_Transactions
    mov     %r14, %rsi
    mov     %r12, %rdx
    lea     ExecutionPayloadHeader_transactions_root(%rbx), %rcx
    CALL_GLOBAL ssz_hash_tree_root
7:  LEAVE 16
END_FUNCTION build_payload_header
.endif

.if FORK >= FORK_BELLATRIX
.if (ExecutionPayload_parent_hash != ExecutionPayloadHeader_parent_hash) || (ExecutionPayload_prev_randao != ExecutionPayloadHeader_prev_randao) || (ExecutionPayload_block_number != ExecutionPayloadHeader_block_number)
.error "build_payload_header copies parent_hash to prev_randao in one block"
.endif
.endif
