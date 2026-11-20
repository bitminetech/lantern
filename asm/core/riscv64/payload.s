/*
 * The execution payload, RISC-V. Requirements: docs/reference/block-processing.md.
 */

.if FORK >= FORK_FULU
SPEC_LEAF get_blob_parameters
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
SPEC_END get_blob_parameters
.endif

.if FORK >= FORK_DENEB
/* Locals: sp+0 out. */
SPEC_FUNCTION kzg_commitment_to_versioned_hash
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
SPEC_END kzg_commitment_to_versioned_hash
.endif

SPEC_LEAF compute_time_at_slot
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
SPEC_END compute_time_at_slot

.if FORK >= FORK_BELLATRIX
/* dst = the bytes of the transactions part of payload p: up to the withdrawals part from capella on, else to the end of the value. Uses tmp. */
.macro TX_BYTES dst, p, tmp
.if FORK >= FORK_CAPELLA
    LDQ     \dst, \p, ExecutionPayload_withdrawals
.else
    ld      \dst, 0(\p)
.endif
    LDQ     \tmp, \p, ExecutionPayload_transactions
    sub     \dst, \dst, \tmp
.endm
.if FORK >= FORK_CAPELLA
.set PAYLOAD_WLIST_BYTES, WLIST_BYTES
.else
.set PAYLOAD_WLIST_BYTES, 0
.endif
.endif

.if FORK == FORK_BELLATRIX
/* L0: a0 = 1 when the a1 bytes at a0 are all zero, else 0. A leaf. */
LOCAL_FUNCTION all_zero
    UNWIND_END_PROLOGUE
1:  beqz    a1, 2f
    lbu     t0, 0(a0)
    bnez    t0, 3f
    addi    a0, a0, 1
    addi    a1, a1, -1
    j       1b
2:  li      a0, 1
    ret
3:  li      a0, 0
    ret
END_FUNCTION all_zero

/*
 * a0 = 1 when the fields that ExecutionPayload and ExecutionPayloadHeader share are all zero
 * and extra_data is empty in the value of type at a0, else 0: parent_hash to prev_randao,
 * block_number to timestamp, extra_data, base_fee_per_gas and block_hash. Uses s1.
 */
.macro EMPTY_SHARED_FIELDS type
    mv      s1, a0
    ADDQ    a0, s1, \type\()_parent_hash
    li      a1, \type\()_prev_randao + 32 - \type\()_parent_hash
    call    all_zero
    beqz    a0, 99f
    ADDQ    a0, s1, \type\()_block_number
    li      a1, 32
    call    all_zero
    beqz    a0, 99f
    LDQ     t0, s1, \type\()_extra_data + 8
    li      a0, 0
    bnez    t0, 99f
    ADDQ    a0, s1, \type\()_base_fee_per_gas
    li      a1, 64
    call    all_zero
99:
.endm
.if (ExecutionPayload_block_hash != ExecutionPayload_base_fee_per_gas + 32) || (ExecutionPayloadHeader_block_hash != ExecutionPayloadHeader_base_fee_per_gas + 32) || (ExecutionPayload_timestamp != ExecutionPayload_block_number + 24) || (ExecutionPayloadHeader_timestamp != ExecutionPayloadHeader_block_number + 24)
.error "EMPTY_SHARED_FIELDS checks base_fee_per_gas with block_hash, and block_number to timestamp, as one range"
.endif

/* s1 the header. Locals: L out. */
SPEC_FUNCTION is_merge_transition_complete
    ENTER 16
    sd      a1, L(sp)
    LDQ     t0, a0, BeaconState_latest_execution_payload_header
    add     a0, a0, t0                      # state.latest_execution_payload_header != ExecutionPayloadHeader.empty()
    EMPTY_SHARED_FIELDS ExecutionPayloadHeader
    beqz    a0, 1f
    ADDQ    a0, s1, ExecutionPayloadHeader_transactions_root
    li      a1, 32
    call    all_zero
1:  xori    a0, a0, 1
    ld      a1, L(sp)
    sd      a0, 0(a1)
    li      a0, LANTERN_OK
    LEAVE 16
SPEC_END is_merge_transition_complete

/* s1 the payload, s2 out, s3 body. Locals: L complete. */
SPEC_FUNCTION is_merge_transition_block
    ENTER 16
    mv      s3, a1
    mv      s2, a2
    addi    a1, sp, L
    call    lantern_is_merge_transition_complete
    ld      t0, L(sp)
    li      a0, 0
    bnez    t0, 7f                          # not is_merge_transition_complete(state)
    PART    a0, t0, s3, BeaconBlockBody_execution_payload    # and body.execution_payload != ExecutionPayload.empty()
    EMPTY_SHARED_FIELDS ExecutionPayload
    beqz    a0, 1f
    LDQ     t0, s1, ExecutionPayload_transactions + 8
    seqz    a0, t0
1:  xori    a0, a0, 1
7:  sd      a0, 0(s2)
    li      a0, LANTERN_OK
    LEAVE 16
SPEC_END is_merge_transition_block

/* s1 state, s2 body, s3 out. Locals: L block, L+8 complete. */
SPEC_FUNCTION is_execution_enabled
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    addi    a2, sp, L
    call    lantern_is_merge_transition_block
    mv      a0, s1
    addi    a1, sp, (L + 8)
    call    lantern_is_merge_transition_complete
    ld      t0, L(sp)                       # is_merge_transition_block(state, body) or is_merge_transition_complete(state)
    ld      t1, (L + 8)(sp)
    or      t0, t0, t1
    sd      t0, 0(s3)
    li      a0, LANTERN_OK
    LEAVE 16
SPEC_END is_execution_enabled
.endif

.if FORK >= FORK_BELLATRIX
/*
 * s1 state, s2 body, s3 execution_valid, s4 config, s5 scratch, s6 result,
 * s7 payload, s8 the new header, s9 scratch size.
 * Locals: L epoch, L+8 mix, L+40 time, L+48 blob parameters (16).
 */
SPEC_FUNCTION process_execution_payload
    ENTER 64
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    PART    s7, t0, s2, BeaconBlockBody_execution_payload
    # Scratch: the new header value, then a standalone Transactions or Withdrawals value to hash.
    TX_BYTES t1, s7, t2                     # bytes of the transactions part
    li      t0, LANTERN_SCRATCH_FIXED + HEADER_ROOM + 24 + PAYLOAD_WLIST_BYTES
    add     t0, t0, t1
    ld      s9, 0(s5)
    bltu    s9, t0, 9f
.if FORK == FORK_BELLATRIX
    mv      a0, s1                          # if is_merge_transition_complete(state):
    addi    a1, sp, (L + 48)
    call    lantern_is_merge_transition_complete
    ld      t0, (L + 48)(sp)
    beqz    t0, 2f
.endif
    LDQ     t0, s1, BeaconState_latest_execution_payload_header   # the header value in its part
    add     t0, s1, t0
    ADDQ    t0, t0, ExecutionPayloadHeader_block_hash
    addi    t1, s7, ExecutionPayload_parent_hash
    li      a0, LANTERN_INVALID_PAYLOAD_PARENT_HASH  # assert payload.parent_hash == latest header's block_hash
    NE32    t1, t0, 6f
2:  mv      a0, s1
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
.if FORK >= FORK_DENEB
.if FORK >= FORK_FULU
    addi    a0, sp, L                       # assert len(blob_kzg_commitments) <= get_blob_parameters(epoch).max_blobs_per_block
    mv      a1, s4
    addi    a2, sp, (L + 48)
    call    lantern_get_blob_parameters
    ld      t1, (L + 56)(sp)
.elseif FORK == FORK_ELECTRA
    LDQ     t1, s4, CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
.else
    LDQ     t1, s4, CONFIG_MAX_BLOBS_PER_BLOCK
.endif
    LDQ     t0, s2, BeaconBlockBody_blob_kzg_commitments + 8
    li      a0, LANTERN_INVALID_BLOB_COUNT
    bgtu    t0, t1, 6f
.endif
    ld      t0, 0(s3)                       # assert execution_engine.verify_and_notify_new_payload(...): bit 0
    li      a0, LANTERN_INVALID_PAYLOAD
    andi    t0, t0, 1
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
SPEC_END process_execution_payload
.endif

.if FORK >= FORK_BELLATRIX
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
    .irp f, block_number, gas_limit, gas_used, timestamp
    LDQ     t0, s7, ExecutionPayload_\f
    STQ     t0, s1, ExecutionPayloadHeader_\f
    .endr
.if FORK >= FORK_DENEB
    .irp f, blob_gas_used, excess_blob_gas
    LDQ     t0, s7, ExecutionPayload_\f
    STQ     t0, s1, ExecutionPayloadHeader_\f
    .endr
.endif
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
.if FORK >= FORK_CAPELLA
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
.endif
    # transactions_root = hash_tree_root(payload.transactions): its part copied into a standalone value.
    TX_BYTES s3, s7, t1                     # bytes of the part
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
.endif

.if FORK >= FORK_BELLATRIX
.if (ExecutionPayload_parent_hash != ExecutionPayloadHeader_parent_hash) || (ExecutionPayload_prev_randao != ExecutionPayloadHeader_prev_randao) || (ExecutionPayload_block_number != ExecutionPayloadHeader_block_number)
.error "build_payload_header copies parent_hash to prev_randao in one block"
.endif
.endif
