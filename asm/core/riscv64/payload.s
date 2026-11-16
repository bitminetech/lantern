/*
 * The execution payload, RISC-V. Requirements: docs/reference/block-processing.md.
 */

LEAF lantern_get_blob_parameters
    ld      a3, 0(a0)                       # epoch
    ld      a4, CONFIG_BLOB_SCHEDULE_COUNT(a1)
    addi    a5, a1, CONFIG_BLOB_SCHEDULE
1:  beqz    a4, 2f                          # the schedule, from its latest epoch down
    addi    a4, a4, -1
    slli    a6, a4, 4
    add     a6, a5, a6
    ld      t0, 0(a6)
    bltu    a3, t0, 1b
    ld      t1, 8(a6)
    sd      t0, 0(a2)
    sd      t1, 8(a2)
    RETURN_OK
2:  ld      t0, CONFIG_ELECTRA_FORK_EPOCH(a1)
    ld      t1, CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA(a1)
    sd      t0, 0(a2)
    sd      t1, 8(a2)
    RETURN_OK
END_FUNCTION lantern_get_blob_parameters

/* Locals: sp+0 out. */
FUNCTION lantern_kzg_commitment_to_versioned_hash
    FRAME 16
    sd      a1, 0(sp)
    mv      a2, a1
    li      a1, 48
    call    sha256_short
    ld      a1, 0(sp)
    li      t0, VERSIONED_HASH_VERSION_KZG
    sb      t0, 0(a1)
    li      a0, LANTERN_OK
    UNFRAME 16
END_FUNCTION lantern_kzg_commitment_to_versioned_hash

LEAF lantern_compute_time_at_slot
    ld      a4, 0(a0)                       # genesis_time
    ld      a5, 0(a1)                       # slot
    li      a6, 1000
    mulhu   t0, a4, a6                      # seconds_to_milliseconds saturates at UINT64_MAX
    mul     t1, a4, a6
    beqz    t0, 1f
    li      t1, -1
1:  ld      t2, CONFIG_SLOT_DURATION_MS(a2)
    mulhu   t0, a5, t2                      # genesis_time_ms + slot * SLOT_DURATION_MS
    bnez    t0, 2f
    mul     t0, a5, t2
    add     t1, t1, t0
    bltu    t1, t0, 2f
    divu    t1, t1, a6                      # milliseconds_to_seconds
    sd      t1, 0(a3)
    RETURN_OK
2:  li      a0, LANTERN_INVALID_OVERFLOW
    ret
END_FUNCTION lantern_compute_time_at_slot

/*
 * s1 state, s2 body, s3 execution_valid, s4 config, s5 scratch, s6 result,
 * s7 payload, s8 the new header, s9 scratch size.
 * Locals: L epoch, L+8 mix, L+40 time, L+48 blob parameters (16).
 */
FUNCTION lantern_process_execution_payload
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    PART    s7, t0, s2, BeaconBlockBody_execution_payload
    # Scratch: the new header value, then a standalone Transactions or Withdrawals value to hash.
    LDQ     t1, s7, ExecutionPayload_withdrawals
    LDQ     t2, s7, ExecutionPayload_transactions
    sub     t1, t1, t2                      # bytes of the transactions part
    li      t0, LANTERN_SCRATCH_FIXED + HEADER_ROOM + 24 + WLIST_BYTES
    add     t0, t0, t1
    ld      s9, 0(s5)
    bltu    s9, t0, 9f
    LDQ     t0, s1, BeaconState_latest_execution_payload_header   # the header value in its part
    add     t0, s1, t0
    ADDQ    t0, t0, ExecutionPayloadHeader_block_hash
    addi    t1, s7, ExecutionPayload_parent_hash
    li      a0, LANTERN_INVALID_PAYLOAD_PARENT_HASH  # assert payload.parent_hash == latest header's block_hash
    NE32    t1, t0, 6f
    mv      a0, s1
    addi    a1, sp, L
    call    lantern_get_current_epoch
    mv      a0, s1                          # assert payload.prev_randao == get_randao_mix(state, epoch)
    addi    a1, sp, L
    addi    a2, sp, (L + 8)
    call    lantern_get_randao_mix
    ADDQ    t0, s7, ExecutionPayload_prev_randao
    addi    t1, sp, (L + 8)
    li      a0, LANTERN_INVALID_PAYLOAD_PREV_RANDAO
    NE32W   t0, t1, 6f                      # prev_randao is 4-aligned
    ADDQ    a0, s1, BeaconState_genesis_time    # assert payload.timestamp == compute_time_at_slot(...)
    ADDQ    a1, s1, BeaconState_slot
    mv      a2, s4
    addi    a3, sp, (L + 40)
    call    lantern_compute_time_at_slot
    bnez    a0, 6f
    LDQ     t0, s7, ExecutionPayload_timestamp
    ld      t1, (L + 40)(sp)
    li      a0, LANTERN_INVALID_PAYLOAD_TIMESTAMP
    bne     t0, t1, 6f
    addi    a0, sp, L                       # assert len(blob_kzg_commitments) <= max_blobs_per_block
    mv      a1, s4
    addi    a2, sp, (L + 48)
    call    lantern_get_blob_parameters
    LDQ     t0, s2, BeaconBlockBody_blob_kzg_commitments + 8
    ld      t1, (L + 56)(sp)
    li      a0, LANTERN_INVALID_BLOB_COUNT
    bgtu    t0, t1, 6f
    ld      t0, 0(s3)                       # assert execution_engine.verify_and_notify_new_payload(...)
    li      a0, LANTERN_INVALID_PAYLOAD
    beqz    t0, 6f
    # The new header, built in scratch before the state changes.
    li      t0, HEADER_ROOM
    sub     t0, s9, t0
    add     s8, s5, t0
    mv      a0, s8
    call    build_payload_header
    bnez    a0, 7f
    LDQ     t0, s1, BeaconState_latest_execution_payload_header     # state.latest_execution_payload_header = header
    add     a0, s1, t0
    mv      a1, s8
    ld      a2, 0(s8)
    call    lantern_copy
    sd      zero, 0(s6)
    li      a0, LANTERN_OK
7:  LEAVE 64
6:  sd      a0, 0(s6)
    li      a0, LANTERN_OK
    LEAVE 64
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_process_execution_payload

/*
 * The ExecutionPayloadHeader of payload s7 at a0, with scratch s5 of size s9 whose last
 * HEADER_ROOM bytes hold a0. Uses the callee saved registers of
 * lantern_process_execution_payload, and saves its own.
 */
LOCAL_FUNCTION build_payload_header
    ENTER 16
    mv      s1, a0
    li      t0, ExecutionPayloadHeader__fixed
    sd      t0, 0(s1)                       # size, without extra_data so far
    addi    a0, s1, ExecutionPayloadHeader_parent_hash  # parent_hash to prev_randao: one layout
    addi    a1, s7, ExecutionPayload_parent_hash
    li      a2, ExecutionPayload_block_number - ExecutionPayload_parent_hash
    call    lantern_copy
    .irp f, block_number, gas_limit, gas_used, timestamp, blob_gas_used, excess_blob_gas
    LDQ     t0, s7, ExecutionPayload_\f
    STQ     t0, s1, ExecutionPayloadHeader_\f
    .endr
    ADDQ    a0, s1, ExecutionPayloadHeader_base_fee_per_gas
    ADDQ    a1, s7, ExecutionPayload_base_fee_per_gas
    COPY32  a0, a1
    ADDQ    a0, s1, ExecutionPayloadHeader_block_hash
    ADDQ    a1, s7, ExecutionPayload_block_hash
    COPY32  a0, a1
    PART    a1, a2, s7, ExecutionPayload_extra_data     # extra_data: its part after the fixed fields
    li      t0, ExecutionPayloadHeader__fixed
    STQ     t0, s1, ExecutionPayloadHeader_extra_data
    STQ     a2, s1, ExecutionPayloadHeader_extra_data + 8
    add     a0, s1, t0
    add     t0, t0, a2
    addi    t0, t0, 7
    andi    t0, t0, -8
    sd      t0, 0(s1)
    call    lantern_copy
    # withdrawals_root = hash_tree_root(payload.withdrawals): a standalone Withdrawals value in scratch.
    li      t0, HEADER_ROOM + WLIST_BYTES
    sub     t0, s9, t0
    add     s2, s5, t0
    li      t0, WLIST_BYTES
    sd      t0, LIST_SIZE(s2)
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s2)
    PART    a1, a2, s7, ExecutionPayload_withdrawals
    sd      a2, LIST_COUNT(s2)
    addi    a0, s2, LIST_FIXED
    li      t0, Withdrawal__mem
    mul     a2, a2, t0
    call    lantern_copy
    li      t0, HEADER_ROOM + WLIST_BYTES
    sub     t0, s9, t0
    sd      t0, 0(s5)
    ADDRESS a0, lantern_type_Withdrawals
    mv      a1, s2
    mv      a2, s5
    ADDQ    a3, s1, ExecutionPayloadHeader_withdrawals_root
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 7f
    # transactions_root = hash_tree_root(payload.transactions): its part copied into a standalone value.
    LDQ     t0, s7, ExecutionPayload_withdrawals
    LDQ     t1, s7, ExecutionPayload_transactions
    sub     s3, t0, t1                      # bytes of the part
    li      t0, HEADER_ROOM + LIST_FIXED
    add     t0, t0, s3
    sub     t0, s9, t0
    add     s2, s5, t0
    addi    t0, s3, LIST_FIXED
    sd      t0, LIST_SIZE(s2)
    li      t0, LIST_FIXED
    sd      t0, LIST_OFFSET(s2)
    PART    a1, a2, s7, ExecutionPayload_transactions
    sd      a2, LIST_COUNT(s2)
    addi    a0, s2, LIST_FIXED
    mv      a2, s3
    call    lantern_copy
    sub     t0, s2, s5
    sd      t0, 0(s5)
    ADDRESS a0, lantern_type_Transactions
    mv      a1, s2
    mv      a2, s5
    ADDQ    a3, s1, ExecutionPayloadHeader_transactions_root
    CALL_GLOBAL ssz_hash_tree_root
7:  LEAVE 16
END_FUNCTION build_payload_header

.if (ExecutionPayload_parent_hash != ExecutionPayloadHeader_parent_hash) || (ExecutionPayload_prev_randao != ExecutionPayloadHeader_prev_randao) || (ExecutionPayload_block_number != ExecutionPayloadHeader_block_number)
.error "build_payload_header copies parent_hash to prev_randao in one block"
.endif
