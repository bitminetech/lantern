/*
 * Engine API JSON-RPC requests, RISC-V: in the objects of bellatrix and later.
 * Requirements: docs/reference/engine-api.md.
 *
 * The writers keep the write position in a2: each takes it and gives the new one.
 */

.if FORK >= FORK_BELLATRIX

/* The JSON text, before the code that takes its lengths. */
    RODATA
.include "engine_json.inc"

/* The text at label (include/engine_json.inc) to a2. Uses a0, a1, t0. */
.macro JTEXT label
    ADDRESS a0, \label
    li      a1, \label\()_len
    call    jput
.endm

/* The byte c, a character code, to a2. Uses t0. */
.macro JCHAR c
    li      t0, \c
    sb      t0, 0(a2)
    addi    a2, a2, 1
.endm

/* L0: the a1 bytes at a0 to a2. Uses t0. */
LOCAL_FUNCTION jput
    UNWIND_END_PROLOGUE
    beqz    a1, 2f
1:  lbu     t0, 0(a0)
    sb      t0, 0(a2)
    addi    a0, a0, 1
    addi    a2, a2, 1
    addi    a1, a1, -1
    bnez    a1, 1b
2:  ret
END_FUNCTION jput

/* The lowercase hex digit of the value 0 to 15 in t1, to a2. Uses t2. */
.macro JHEX
    li      t2, 10
    bltu    t1, t2, 91f
    addi    t1, t1, 'a' - 10 - '0'
91: addi    t1, t1, '0'
    sb      t1, 0(a2)
    addi    a2, a2, 1
.endm

/* L0: DATA: "0x" and two lowercase hex digits for each of the a1 bytes at a0, to a2. Uses t0-t2. */
LOCAL_FUNCTION jdata
    UNWIND_END_PROLOGUE
    li      t0, '"'
    sb      t0, 0(a2)
    li      t0, '0'
    sb      t0, 1(a2)
    li      t0, 'x'
    sb      t0, 2(a2)
    addi    a2, a2, 3
    beqz    a1, 3f
1:  lbu     t0, 0(a0)
    addi    a0, a0, 1
    srli    t1, t0, 4
    JHEX
    andi    t1, t0, 15
    JHEX
    addi    a1, a1, -1
    bnez    a1, 1b
3:  li      t0, '"'
    sb      t0, 0(a2)
    addi    a2, a2, 1
    ret
END_FUNCTION jdata

/* L0: QUANTITY of the a1 bytes, little endian, at a0: "0x" and the hex with no leading zeros, to a2. Uses t0-t4. */
LOCAL_FUNCTION jquantity
    UNWIND_END_PROLOGUE
    li      t0, '"'
    sb      t0, 0(a2)
    li      t0, '0'
    sb      t0, 1(a2)
    li      t0, 'x'
    sb      t0, 2(a2)
    addi    a2, a2, 3
    slli    t3, a1, 1                       # the digits, from the most significant
    li      t4, 0                           # 1 once a digit other than 0 is written
1:  addi    t3, t3, -1
    srli    t0, t3, 1
    add     t0, a0, t0
    lbu     t1, 0(t0)
    andi    t0, t3, 1
    beqz    t0, 2f
    srli    t1, t1, 4
2:  andi    t1, t1, 15
    bnez    t4, 3f
    beqz    t3, 3f                          # a leading zero, but the last digit is always written
    beqz    t1, 5f
3:  li      t4, 1
    JHEX
5:  bnez    t3, 1b
    li      t0, '"'
    sb      t0, 0(a2)
    addi    a2, a2, 1
    ret
END_FUNCTION jquantity

/* L0: the decimal digits of a0 to a2. Uses t0-t3. */
LOCAL_FUNCTION jdecimal
    UNWIND_END_PROLOGUE
    li      t3, 10
    mv      t0, a0
1:  divu    t0, t0, t3
    addi    a2, a2, 1
    bnez    t0, 1b
    mv      t0, a2
2:  remu    t1, a0, t3
    divu    a0, a0, t3
    addi    t1, t1, '0'
    addi    t0, t0, -1
    sb      t1, 0(t0)
    bnez    a0, 2b
    ret
END_FUNCTION jdecimal

/* QUANTITY of the u64 at base + off, to a2. Uses a0, a1, t0-t4. */
.macro JQ64 base, off
    ADDQ    a0, \base, \off
    li      a1, 8
    call    jquantity
.endm

/* DATA of the n bytes at base + off, to a2. Uses a0, a1, t0-t2. */
.macro JDATA base, off, n
    ADDQ    a0, \base, \off
    li      a1, \n
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
 * (execution_requests, out): s1 the requests, s2 out, s3 the write position, s4 the type,
 * s5 the entries, s6 their count, s7 the SSZ bytes of one request, s8 the stride.
 */
SPEC_FUNCTION get_execution_requests_list
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    addi    s3, s2, 24
    li      s4, 0
1:  li      t0, 3                           # each kind, in type order
    bgeu    s4, t0, 9f
    li      t0, 1
    beq     s4, t0, 2f
    bltu    t0, s4, 3f
    PART    s5, s6, s1, ExecutionRequests_deposits
    li      s7, DEPOSIT_REQUEST_SSZ
    li      s8, DepositRequest__mem
    j       4f
2:  PART    s5, s6, s1, ExecutionRequests_withdrawals
    li      s7, WITHDRAWAL_REQUEST_SSZ
    li      s8, WithdrawalRequest__mem
    j       4f
3:  PART    s5, s6, s1, ExecutionRequests_consolidations
    li      s7, CONSOLIDATION_REQUEST_SSZ
    li      s8, ConsolidationRequest__mem
4:  beqz    s6, 8f                          # an empty list: no element
    mul     t0, s7, s6                      # the element: its length, the type, the requests
    addi    t0, t0, 1
    ld      t1, 0(s2)                       # room: 8 + the element
    add     t1, s2, t1
    sub     t1, t1, s3
    addi    t2, t0, 8
    bltu    t1, t2, 7f
    li      t2, 8                           # the length, a byte at a time
5:  sb      t0, 0(s3)
    srli    t0, t0, 8
    addi    s3, s3, 1
    addi    t2, t2, -1
    bnez    t2, 5b
    sb      s4, 0(s3)
    addi    s3, s3, 1
6:  mv      a0, s3                          # each request's SSZ bytes
    mv      a1, s5
    li      t0, 1
    beq     s4, t0, 10f
    mv      a2, s7
    add     s3, s3, s7
    call    lantern_copy
    j       11f
10: li      a2, 20 + 48                     # a withdrawal request: its amount after a pad
    call    lantern_copy
    ld      t0, WithdrawalRequest_amount(s5)
    li      t2, 8
12: sb      t0, 68(s3)
    srli    t0, t0, 8
    addi    s3, s3, 1
    addi    t2, t2, -1
    bnez    t2, 12b
    addi    s3, s3, WITHDRAWAL_REQUEST_SSZ - 8
11: add     s5, s5, s8
    addi    s6, s6, -1
    bnez    s6, 6b
8:  addi    s4, s4, 1
    j       1b
9:  addi    t0, s2, 24
    sub     t0, s3, t0
    li      t1, 24
    sd      t1, 8(s2)
    sd      t0, 16(s2)
    li      a0, LANTERN_OK
    LEAVE 0
7:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END get_execution_requests_list
.endif

/* (block, out): the bound of engine-api.md. t0 the bound; t1-t6, a2-a5 work. */
SPEC_LEAF engine_new_payload_size
    PART    a2, t1, a0, BeaconBlock_body
    PART    a3, t1, a2, BeaconBlockBody_execution_payload
    li      t0, 4096
    PART    a4, t1, a3, ExecutionPayload_extra_data   # twice the bytes of extra_data
    slli    t1, t1, 1
    add     t0, t0, t1
    PART    a4, a5, a3, ExecutionPayload_transactions  # 8 + twice the bytes of each transaction
1:  beqz    a5, 2f
    ld      t1, 16(a4)
    slli    t1, t1, 1
    add     t0, t0, t1
    addi    t0, t0, 8
    ld      t1, 0(a4)
    add     a4, a4, t1
    addi    a5, a5, -1
    j       1b
2:
.if FORK >= FORK_CAPELLA
    LDQ     t1, a3, ExecutionPayload_withdrawals + 8    # 160 for each withdrawal
    li      t2, 160
    mul     t1, t1, t2
    add     t0, t0, t1
.endif
.if FORK >= FORK_DENEB
    LDQ     t1, a2, BeaconBlockBody_blob_kzg_commitments + 8    # 72 for each commitment
    li      t2, 72
    mul     t1, t1, t2
    add     t0, t0, t1
.endif
.if FORK >= FORK_ELECTRA
    PART    a3, t1, a2, BeaconBlockBody_execution_requests      # 8 + twice the bytes of each list
    LDQ     t1, a3, ExecutionRequests_deposits + 8
    li      t2, 2 * DEPOSIT_REQUEST_SSZ
    mul     t1, t1, t2
    add     t0, t0, t1
    LDQ     t1, a3, ExecutionRequests_withdrawals + 8
    li      t2, 2 * WITHDRAWAL_REQUEST_SSZ
    mul     t1, t1, t2
    add     t0, t0, t1
    LDQ     t1, a3, ExecutionRequests_consolidations + 8
    li      t2, 2 * CONSOLIDATION_REQUEST_SSZ
    mul     t1, t1, t2
    add     t0, t0, t1
    addi    t0, t0, 3 * (8 + 2)
.endif
    sd      t0, 0(a1)
    RETURN_OK
SPEC_END engine_new_payload_size

/*
 * (block, id, scratch, out): s1 block, s2 id, s3 scratch, s4 out, s5 body, s6 payload,
 * s7 the write position, s8 entries, s9 their count. Locals: L the bound, L+16 a versioned hash.
 */
SPEC_FUNCTION engine_new_payload
    ENTER 48
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    mv      s4, a3
    addi    a1, sp, L                       # room for the bound
    call    lantern_engine_new_payload_size
    ld      t0, 0(s4)
    li      t1, 24
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    ld      t1, L(sp)
    bltu    t0, t1, 8f
    PART    s5, t0, s1, BeaconBlock_body
    PART    s6, t0, s5, BeaconBlockBody_execution_payload
    addi    a2, s4, 24
    # {"jsonrpc":"2.0","id":id,"method":"engine_newPayloadVn","params":[
    JTEXT   j_open
    mv      a0, s2
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
    JDATA   s6, ExecutionPayload_parent_hash, 32
    JTEXT   j_fee_recipient
    JDATA   s6, ExecutionPayload_fee_recipient, 20
    JTEXT   j_state_root
    JDATA   s6, ExecutionPayload_state_root, 32
    JTEXT   j_receipts_root
    JDATA   s6, ExecutionPayload_receipts_root, 32
    JTEXT   j_logs_bloom
    JDATA   s6, ExecutionPayload_logs_bloom, BYTES_PER_LOGS_BLOOM
    JTEXT   j_prev_randao
    JDATA   s6, ExecutionPayload_prev_randao, 32
    JTEXT   j_block_number
    JQ64    s6, ExecutionPayload_block_number
    JTEXT   j_gas_limit
    JQ64    s6, ExecutionPayload_gas_limit
    JTEXT   j_gas_used
    JQ64    s6, ExecutionPayload_gas_used
    JTEXT   j_timestamp
    JQ64    s6, ExecutionPayload_timestamp
    JTEXT   j_extra_data
    PART    a0, a1, s6, ExecutionPayload_extra_data
    call    jdata
    JTEXT   j_base_fee
    ADDQ    a0, s6, ExecutionPayload_base_fee_per_gas
    li      a1, 32
    call    jquantity
    JTEXT   j_block_hash
    JDATA   s6, ExecutionPayload_block_hash, 32
    # each transaction: a nested ByteList value
    JTEXT   j_transactions
    PART    s8, s9, s6, ExecutionPayload_transactions
    beqz    s9, 2f
1:  ld      t0, 8(s8)
    add     a0, s8, t0
    ld      a1, 16(s8)
    ld      t0, 0(s8)
    add     s8, s8, t0
    call    jdata
    addi    s9, s9, -1
    beqz    s9, 2f
    JCHAR   44
    j       1b
2:
.if FORK >= FORK_CAPELLA
    JTEXT   j_withdrawals
    PART    s8, s9, s6, ExecutionPayload_withdrawals
    beqz    s9, 4f
3:  JTEXT   j_w_index
    JQ64    s8, Withdrawal_index
    JTEXT   j_w_validator
    JQ64    s8, Withdrawal_validator_index
    JTEXT   j_w_address
    JDATA   s8, Withdrawal_address, 20
    JTEXT   j_w_amount
    JQ64    s8, Withdrawal_amount
    JCHAR   125
    addi    s8, s8, Withdrawal__mem
    addi    s9, s9, -1
    beqz    s9, 4f
    JCHAR   44
    j       3b
4:
.endif
.if FORK >= FORK_DENEB
    JTEXT   j_blob_gas_used
    JQ64    s6, ExecutionPayload_blob_gas_used
    JTEXT   j_excess_blob_gas
    JQ64    s6, ExecutionPayload_excess_blob_gas
    JCHAR   125
    # the versioned hashes of the commitments
    JCHAR   44
    JCHAR   91
    PART    s8, s9, s5, BeaconBlockBody_blob_kzg_commitments
    beqz    s9, 6f
5:  mv      s7, a2
    mv      a0, s8
    addi    a1, sp, L + 16
    call    lantern_kzg_commitment_to_versioned_hash
    mv      a2, s7
    addi    a0, sp, L + 16
    li      a1, 32
    call    jdata
    addi    s8, s8, 48
    addi    s9, s9, -1
    beqz    s9, 6f
    JCHAR   44
    j       5b
6:  JCHAR   93
    JCHAR   44
    # parentBeaconBlockRoot
    JDATA   s1, BeaconBlock_parent_root, 32
.else
    JCHAR   93
    JCHAR   125
.endif
.if FORK >= FORK_ELECTRA
    # the request lists, through scratch
    JCHAR   44
    JCHAR   91
    mv      s7, a2
    PART    a0, t0, s5, BeaconBlockBody_execution_requests
    mv      a1, s3
    li      t0, 24
    sd      t0, 8(s3)
    sd      zero, 16(s3)
    call    lantern_get_execution_requests_list
    bnez    a0, 8f
    mv      a2, s7
    addi    s8, s3, 24
    ld      s9, 16(s3)
    add     s9, s8, s9                      # the end
7:  bgeu    s8, s9, 9f
    lbu     a1, 0(s8)                       # the length, a byte at a time
    lbu     t0, 1(s8)
    slli    t0, t0, 8
    or      a1, a1, t0
    lbu     t0, 2(s8)
    slli    t0, t0, 16
    or      a1, a1, t0
    lbu     t0, 3(s8)
    slli    t0, t0, 24
    or      a1, a1, t0
    addi    a0, s8, 8
    add     s8, a0, a1
    call    jdata
    bgeu    s8, s9, 9f
    JCHAR   44
    j       7b
9:  JCHAR   93
.endif
    JTEXT   j_close
    addi    t0, s4, 24
    sub     t0, a2, t0
    li      t1, 24
    sd      t1, 8(s4)
    sd      t0, 16(s4)
    li      a0, LANTERN_OK
    LEAVE 48
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END engine_new_payload

/* (state, id, out): s1 state, s2 id, s3 out. */
SPEC_FUNCTION engine_forkchoice_updated
    ENTER 0
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    ld      t0, 0(s3)
    li      t1, 24 + 512
    bltu    t0, t1, 8f
    addi    a2, s3, 24
    JTEXT   j_open
    mv      a0, s2
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
    JDATA   s1, 0, 32
    JTEXT   j_safe
    JDATA   s1, 32, 32
    JTEXT   j_finalized
    JDATA   s1, 64, 32
    JTEXT   j_fcu_close
    addi    t0, s3, 24
    sub     t0, a2, t0
    li      t1, 24
    sd      t1, 8(s3)
    sd      t0, 16(s3)
    li      a0, LANTERN_OK
    LEAVE 0
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END engine_forkchoice_updated

.endif
