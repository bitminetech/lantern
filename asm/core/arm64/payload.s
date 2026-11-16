/*
 * The execution payload, ARM64. Requirements: docs/reference/block-processing.md.
 */

LEAF lantern_get_blob_parameters
    ldr     x3, [x0]                        /* epoch */
    ldr     x4, [x1, #CONFIG_BLOB_SCHEDULE_COUNT]
    add     x5, x1, #CONFIG_BLOB_SCHEDULE
1:  cbz     x4, 2f                          /* the schedule, from its latest epoch down */
    sub     x4, x4, #1
    add     x6, x5, x4, lsl #4
    ldr     x7, [x6]
    cmp     x3, x7
    b.lo    1b
    ldr     x8, [x6, #8]
    stp     x7, x8, [x2]
    RETURN_OK
2:  ldr     x7, [x1, #CONFIG_ELECTRA_FORK_EPOCH]
    ldr     x8, [x1, #CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA]
    stp     x7, x8, [x2]
    RETURN_OK
END_FUNCTION lantern_get_blob_parameters

FUNCTION lantern_kzg_commitment_to_versioned_hash
    FRAME 16
    str     x1, [sp, #16]
    mov     x2, x1
    mov     x1, #48
    bl      sha256_short
    ldr     x1, [sp, #16]
    mov     w9, #VERSIONED_HASH_VERSION_KZG
    strb    w9, [x1]
    mov     x0, #LANTERN_OK
    UNFRAME 16
END_FUNCTION lantern_kzg_commitment_to_versioned_hash

LEAF lantern_compute_time_at_slot
    ldr     x4, [x0]                        /* genesis_time */
    ldr     x5, [x1]                        /* slot */
    mov     x6, #1000
    mov     x7, #-1                         /* seconds_to_milliseconds saturates at UINT64_MAX */
    umulh   x8, x4, x6
    mul     x9, x4, x6
    cmp     x8, #0
    csel    x9, x9, x7, eq
    ldr     x7, [x2, #CONFIG_SLOT_DURATION_MS]
    umulh   x8, x5, x7                      /* genesis_time_ms + slot * SLOT_DURATION_MS */
    cbnz    x8, 1f
    mul     x8, x5, x7
    adds    x9, x9, x8
    b.cs    1f
    udiv    x9, x9, x6                      /* milliseconds_to_seconds */
    str     x9, [x3]
    RETURN_OK
1:  mov     x0, #LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_compute_time_at_slot

/*
 * x19 state, x20 body, x21 execution_valid, x22 config, x23 scratch, x24 result,
 * x25 payload, x26 the new header, x27 scratch size.
 * Locals: L epoch, L+8 mix, L+40 time, L+48 blob parameters (16).
 */
FUNCTION lantern_process_execution_payload
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    PART    x25, x9, x20, BeaconBlockBody_execution_payload
    /* Scratch: the new header value, then a standalone Transactions or Withdrawals value to hash. */
    PART    x9, x10, x25, ExecutionPayload_transactions
    LDQ     x11, x25, ExecutionPayload_withdrawals
    LDQ     x12, x25, ExecutionPayload_transactions
    sub     x11, x11, x12                   /* bytes of the transactions part */
    MOVQ    x9, LANTERN_SCRATCH_FIXED + HEADER_ROOM + 24 + WLIST_BYTES
    add     x9, x9, x11
    ldr     x27, [x23]
    cmp     x27, x9
    b.lo    9f
    LDQ     x9, x19, BeaconState_latest_execution_payload_header     /* the header value in its part */
    add     x9, x19, x9
    add     x9, x9, #ExecutionPayloadHeader_block_hash
    add     x14, x25, #ExecutionPayload_parent_hash
    NE32    x14, x9, 1f                     /* assert payload.parent_hash == latest header's block_hash */
    b       2f
1:  mov     x0, #LANTERN_INVALID_PAYLOAD_PARENT_HASH
    b       6f
2:  mov     x0, x19
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    mov     x0, x19                         /* assert payload.prev_randao == get_randao_mix(state, epoch) */
    add     x1, sp, #L
    add     x2, sp, #(L + 8)
    bl      lantern_get_randao_mix
    add     x14, x25, #ExecutionPayload_prev_randao
    add     x15, sp, #(L + 8)
    NE32    x14, x15, 3f
    b       4f
3:  mov     x0, #LANTERN_INVALID_PAYLOAD_PREV_RANDAO
    b       6f
4:  ADDQ    x0, x19, BeaconState_genesis_time   /* assert payload.timestamp == compute_time_at_slot(...) */
    ADDQ    x1, x19, BeaconState_slot
    mov     x2, x22
    add     x3, sp, #(L + 40)
    bl      lantern_compute_time_at_slot
    cbnz    x0, 6f
    ldr     x9, [x25, #ExecutionPayload_timestamp]
    ldr     x10, [sp, #(L + 40)]
    cmp     x9, x10
    mov     x0, #LANTERN_INVALID_PAYLOAD_TIMESTAMP
    b.ne    6f
    add     x0, sp, #L                      /* assert len(blob_kzg_commitments) <= max_blobs_per_block */
    mov     x1, x22
    add     x2, sp, #(L + 48)
    bl      lantern_get_blob_parameters
    LDQ     x9, x20, BeaconBlockBody_blob_kzg_commitments + 8
    ldr     x10, [sp, #(L + 56)]
    cmp     x9, x10
    mov     x0, #LANTERN_INVALID_BLOB_COUNT
    b.hi    6f
    ldr     x9, [x21]                       /* assert execution_engine.verify_and_notify_new_payload(...) */
    mov     x0, #LANTERN_INVALID_PAYLOAD
    cbz     x9, 6f
    /* The new header, built in scratch before the state changes. */
    MOVQ    x9, HEADER_ROOM
    sub     x9, x27, x9
    add     x26, x23, x9
    mov     x0, x26
    bl      build_payload_header
    cbnz    x0, 7f
    LDQ     x9, x19, BeaconState_latest_execution_payload_header       /* state.latest_execution_payload_header = header */
    add     x0, x19, x9
    mov     x1, x26
    ldr     x2, [x26]
    bl      lantern_copy
    str     xzr, [x24]
    mov     x0, #LANTERN_OK
7:  LEAVE 64
6:  str     x0, [x24]
    mov     x0, #LANTERN_OK
    LEAVE 64
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_process_execution_payload

/*
 * The ExecutionPayloadHeader of payload x25 at x0, with scratch x23 of size x27 whose last
 * HEADER_ROOM bytes hold x0. Uses the callee saved registers of
 * lantern_process_execution_payload, and saves its own.
 */
LOCAL_FUNCTION build_payload_header
    ENTER 16
    mov     x19, x0
    MOVQ    x9, ExecutionPayloadHeader__fixed
    str     x9, [x19]                       /* size, without extra_data so far */
    add     x0, x19, #ExecutionPayloadHeader_parent_hash    /* parent_hash to prev_randao: one layout */
    add     x1, x25, #ExecutionPayload_parent_hash
    MOVQ    x2, ExecutionPayload_block_number - ExecutionPayload_parent_hash
    bl      lantern_copy
    ldr     x9, [x25, #ExecutionPayload_block_number]
    str     x9, [x19, #ExecutionPayloadHeader_block_number]
    ldr     x9, [x25, #ExecutionPayload_gas_limit]
    str     x9, [x19, #ExecutionPayloadHeader_gas_limit]
    ldr     x9, [x25, #ExecutionPayload_gas_used]
    str     x9, [x19, #ExecutionPayloadHeader_gas_used]
    ldr     x9, [x25, #ExecutionPayload_timestamp]
    str     x9, [x19, #ExecutionPayloadHeader_timestamp]
    add     x0, x19, #ExecutionPayloadHeader_base_fee_per_gas
    add     x1, x25, #ExecutionPayload_base_fee_per_gas
    COPY32  x0, x1
    add     x0, x19, #ExecutionPayloadHeader_block_hash
    add     x1, x25, #ExecutionPayload_block_hash
    COPY32  x0, x1
    ldr     x9, [x25, #ExecutionPayload_blob_gas_used]
    str     x9, [x19, #ExecutionPayloadHeader_blob_gas_used]
    ldr     x9, [x25, #ExecutionPayload_excess_blob_gas]
    str     x9, [x19, #ExecutionPayloadHeader_excess_blob_gas]
    PART    x1, x2, x25, ExecutionPayload_extra_data        /* extra_data: its part after the fixed fields */
    MOVQ    x9, ExecutionPayloadHeader__fixed
    str     x9, [x19, #ExecutionPayloadHeader_extra_data]
    str     x2, [x19, #(ExecutionPayloadHeader_extra_data + 8)]
    add     x0, x19, x9
    add     x9, x9, x2
    add     x9, x9, #7
    and     x9, x9, #-8
    str     x9, [x19]
    bl      lantern_copy
    /* withdrawals_root = hash_tree_root(payload.withdrawals): a standalone Withdrawals value in scratch. */
    MOVQ    x9, HEADER_ROOM + WLIST_BYTES
    sub     x9, x27, x9
    add     x20, x23, x9
    MOVQ    x9, WLIST_BYTES
    str     x9, [x20, #LIST_SIZE]
    mov     x9, #LIST_FIXED
    str     x9, [x20, #LIST_OFFSET]
    PART    x1, x2, x25, ExecutionPayload_withdrawals
    str     x2, [x20, #LIST_COUNT]
    add     x0, x20, #LIST_FIXED
    mov     x9, #Withdrawal__mem
    mul     x2, x2, x9
    bl      lantern_copy
    MOVQ    x9, HEADER_ROOM + WLIST_BYTES
    sub     x9, x27, x9
    str     x9, [x23]
    ADDRESS x0, lantern_type_Withdrawals
    mov     x1, x20
    mov     x2, x23
    add     x3, x19, #ExecutionPayloadHeader_withdrawals_root
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 7f
    /* transactions_root = hash_tree_root(payload.transactions): its part copied into a standalone value. */
    LDQ     x9, x25, ExecutionPayload_withdrawals
    LDQ     x10, x25, ExecutionPayload_transactions
    sub     x21, x9, x10                    /* bytes of the part */
    MOVQ    x9, HEADER_ROOM + LIST_FIXED
    add     x9, x9, x21
    sub     x9, x27, x9
    add     x20, x23, x9
    add     x9, x21, #LIST_FIXED
    str     x9, [x20, #LIST_SIZE]
    mov     x9, #LIST_FIXED
    str     x9, [x20, #LIST_OFFSET]
    PART    x1, x2, x25, ExecutionPayload_transactions
    str     x2, [x20, #LIST_COUNT]
    add     x0, x20, #LIST_FIXED
    mov     x2, x21
    bl      lantern_copy
    sub     x9, x20, x23
    str     x9, [x23]
    ADDRESS x0, lantern_type_Transactions
    mov     x1, x20
    mov     x2, x23
    add     x3, x19, #ExecutionPayloadHeader_transactions_root
    CALL_GLOBAL ssz_hash_tree_root
7:  LEAVE 16
END_FUNCTION build_payload_header

.if (ExecutionPayload_parent_hash != ExecutionPayloadHeader_parent_hash) || (ExecutionPayload_prev_randao != ExecutionPayloadHeader_prev_randao) || (ExecutionPayload_block_number != ExecutionPayloadHeader_block_number)
.error "build_payload_header copies parent_hash to prev_randao in one block"
.endif
