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
    call    lantern_jput
.endm

/* The byte c, a character code, to a2. Uses t0. */
.macro JCHAR c
    li      t0, \c
    sb      t0, 0(a2)
    addi    a2, a2, 1
.endm

/* The a1 bytes at a0 to a2. Uses t0. */
LOCAL_FUNCTION lantern_jput
    UNWIND_END_PROLOGUE
    beqz    a1, 2f
1:  lbu     t0, 0(a0)
    sb      t0, 0(a2)
    addi    a0, a0, 1
    addi    a2, a2, 1
    addi    a1, a1, -1
    bnez    a1, 1b
2:  ret
END_FUNCTION lantern_jput

/* The lowercase hex digit of the value 0 to 15 in t1, to a2. Uses t2. */
.macro JHEX
    li      t2, 10
    bltu    t1, t2, 91f
    addi    t1, t1, 'a' - 10 - '0'
91: addi    t1, t1, '0'
    sb      t1, 0(a2)
    addi    a2, a2, 1
.endm

/* DATA: "0x" and two lowercase hex digits for each of the a1 bytes at a0, to a2. Uses t0-t2. */
LOCAL_FUNCTION lantern_jdata
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
END_FUNCTION lantern_jdata

/* QUANTITY of the a1 bytes, little endian, at a0: "0x" and the hex with no leading zeros, to a2. Uses t0-t4. */
LOCAL_FUNCTION lantern_jquantity
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
END_FUNCTION lantern_jquantity

/* The decimal digits of a0 to a2. Uses t0-t3. */
LOCAL_FUNCTION lantern_jdecimal
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
END_FUNCTION lantern_jdecimal

/* QUANTITY of the u64 at base + off, to a2. Uses a0, a1, t0-t4. */
.macro JQ64 base, off
    ADDQ    a0, \base, \off
    li      a1, 8
    call    lantern_jquantity
.endm

/* DATA of the n bytes at base + off, to a2. Uses a0, a1, t0-t2. */
.macro JDATA base, off, n
    ADDQ    a0, \base, \off
    li      a1, \n
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

/*
 * (list, out): s1 the list's bytes, s2 their count, s3 out, s4 the item, s5 the items, s6 the
 * lowest type the item may have. Locals: L, L+16, L+32 the data of each type, its address and its
 * bytes.
 */
SPEC_FUNCTION get_execution_requests
    ENTER 48
    ld      t0, 8(a0)
    ld      s2, 16(a0)
    add     s1, a0, t0
    mv      s3, a1
    sd      zero, (L + 0)(sp)
    sd      zero, (L + 8)(sp)
    sd      zero, (L + 16)(sp)
    sd      zero, (L + 24)(sp)
    sd      zero, (L + 32)(sp)
    sd      zero, (L + 40)(sp)
    beqz    s2, 5f                          # the SSZ list: no item, or the first offset, 4 an item, at most 3
    li      t0, 4
    bltu    s2, t0, 9f
    lwu     t0, 0(s1)
    andi    t1, t0, 3
    bnez    t1, 9f
    beqz    t0, 9f
    li      t1, 12
    bgtu    t0, t1, 9f
    bgtu    t0, s2, 9f
    srli    s5, t0, 2
    li      s4, 0
    li      s6, 0
1:  slli    t1, s4, 2                       # item s4: from its offset to the next, or to the end
    add     t1, s1, t1
    lwu     t0, 0(t1)
    mv      t2, s2
    addi    t3, s4, 1
    bgeu    t3, s5, 2f
    lwu     t2, 4(t1)
2:  bgtu    t0, t2, 9f
    bgtu    t2, s2, 9f
    sub     t2, t2, t0                      # a type in ascending order, and data
    li      t3, 2
    bltu    t2, t3, 9f
    add     t1, s1, t0
    lbu     t3, 0(t1)
    bltu    t3, s6, 9f
    li      t4, 3
    bgeu    t3, t4, 9f
    addi    s6, t3, 1
    addi    t2, t2, -1
    addi    t1, t1, 1
    li      t4, DEPOSIT_REQUEST_SSZ         # the data: whole requests of the type, at most its limit
    li      t5, DEPOSIT_REQUEST_SSZ * MAX_DEPOSIT_REQUESTS_PER_PAYLOAD
    beqz    t3, 6f
    li      t4, WITHDRAWAL_REQUEST_SSZ
    li      t5, WITHDRAWAL_REQUEST_SSZ * MAX_WITHDRAWAL_REQUESTS_PER_PAYLOAD
    li      t6, 1
    beq     t3, t6, 6f
    li      t4, CONSOLIDATION_REQUEST_SSZ
    li      t5, CONSOLIDATION_REQUEST_SSZ * MAX_CONSOLIDATION_REQUESTS_PER_PAYLOAD
6:  bgtu    t2, t5, 9f
    remu    t6, t2, t4
    bnez    t6, 9f
    slli    t3, t3, 4
    add     t3, sp, t3
    sd      t1, (L + 0)(t3)
    sd      t2, (L + 8)(t3)
    addi    s4, s4, 1
    bltu    s4, s5, 1b
5:  ld      t0, (L + 8)(sp)                 # ExecutionRequests: three offsets, then the data of each type
    ld      t1, (L + 24)(sp)
    ld      t2, (L + 40)(sp)
    add     t3, t0, t1
    add     t3, t3, t2
    addi    t3, t3, 12
    ld      t4, 0(s3)
    li      t5, 24
    bltu    t4, t5, 8f
    addi    t4, t4, -24
    bltu    t4, t3, 8f
    sd      t5, 8(s3)
    sd      t3, 16(s3)
    addi    s1, s3, 24
    li      t3, 12
    sw      t3, 0(s1)
    add     t3, t3, t0
    sw      t3, 4(s1)
    add     t3, t3, t1
    sw      t3, 8(s1)
    addi    s1, s1, 12
    li      s4, 0
7:  slli    t0, s4, 4
    add     t0, sp, t0
    ld      a1, (L + 0)(t0)
    ld      a2, (L + 8)(t0)
    mv      a0, s1
    add     s1, s1, a2
    call    lantern_copy
    addi    s4, s4, 1
    li      t0, 3
    bltu    s4, t0, 7b
    li      a0, LANTERN_OK
    LEAVE 48
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
9:  li      a0, LANTERN_INVALID_ENCODING
    LEAVE 48
SPEC_END get_execution_requests
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
    call    lantern_jdata
    JTEXT   j_base_fee
    ADDQ    a0, s6, ExecutionPayload_base_fee_per_gas
    li      a1, 32
    call    lantern_jquantity
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
    call    lantern_jdata
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
    call    lantern_jdata
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
    call    lantern_jdata
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

/* (state, attributes, id, out): s1 state, s2 id, s3 out, s4 attributes, s5 a withdrawal, s6 those left. */
SPEC_FUNCTION engine_forkchoice_updated
    ENTER 0
    mv      s1, a0
    mv      s4, a1
    ld      s2, 0(a2)
    mv      s3, a3
    ld      t0, 0(s3)                       # the room: 512 bytes, or 1024 and 192 a withdrawal
    li      t1, 24 + 512
    beqz    s4, 1f
    li      t1, 24 + 1024
.if FORK >= FORK_CAPELLA
    ld      t2, PayloadAttributes_withdrawals(s4)
    li      t3, 192
    mul     t2, t2, t3
    add     t1, t1, t2
.endif
1:  bltu    t0, t1, 8f
    addi    a2, s3, 24
    JTEXT   j_open
    mv      a0, s2
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
    JDATA   s1, 0, 32
    JTEXT   j_safe
    JDATA   s1, 32, 32
    JTEXT   j_finalized
    JDATA   s1, 64, 32
    bnez    s4, 2f
    JTEXT   j_fcu_close
    j       7f
    # the PayloadAttributes
2:  JTEXT   j_attr_open
    JQ64    s4, PayloadAttributes_timestamp
    JTEXT   j_prev_randao
    JDATA   s4, PayloadAttributes_prev_randao, 32
    JTEXT   j_attr_fee_recipient
    JDATA   s4, PayloadAttributes_suggested_fee_recipient, 20
.if FORK >= FORK_CAPELLA
    # each withdrawal: its 44 SSZ bytes
    JTEXT   j_attr_withdrawals
    addi    s5, s4, PAYLOAD_ATTRIBUTES_WITHDRAWAL
    ld      s6, PayloadAttributes_withdrawals(s4)
    beqz    s6, 4f
3:  JTEXT   j_w_index
    JQ64    s5, 0
    JTEXT   j_w_validator
    JQ64    s5, 8
    JTEXT   j_w_address
    JDATA   s5, 16, 20
    JTEXT   j_w_amount
    JQ64    s5, 36
    JCHAR   125
    addi    s5, s5, PAYLOAD_ATTRIBUTES_WITHDRAWAL_SIZE
    addi    s6, s6, -1
    beqz    s6, 4f
    JCHAR   44
    j       3b
4:  JCHAR   93
.endif
.if FORK >= FORK_DENEB
    JTEXT   j_attr_parent_root
    JDATA   s4, PayloadAttributes_parent_beacon_block_root, 32
.endif
    JTEXT   j_attr_close
7:  addi    t0, s3, 24
    sub     t0, a2, t0
    li      t1, 24
    sd      t1, 8(s3)
    sd      t0, 16(s3)
    li      a0, LANTERN_OK
    LEAVE 0
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END engine_forkchoice_updated

/* (payload_id, id, out): s1 payload_id, s2 id, s3 out. */
SPEC_FUNCTION engine_get_payload
    ENTER 0
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    ld      t0, 0(s3)
    li      t1, 24 + 256
    bltu    t0, t1, 8f
    addi    a2, s3, 24
    JTEXT   j_open
    mv      a0, s2
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
    JDATA   s1, 0, 8
    JTEXT   j_close
    addi    t0, s3, 24
    sub     t0, a2, t0
    li      t1, 24
    sd      t1, 8(s3)
    sd      t0, 16(s3)
    li      a0, LANTERN_OK
    LEAVE 0
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END engine_get_payload

.if FORK >= FORK_CAPELLA
.if Withdrawal_index != 0 || Withdrawal_validator_index != 8 || Withdrawal_address != 16
.error "get_payload_attributes copies the first 36 bytes of a Withdrawal as its SSZ bytes"
.endif
.endif

/*
 * (state, fee_recipient, config, scratch, out): s1 state, s2 fee_recipient, s3 config, s4 scratch,
 * s5 out, s6 the scratch size, s7 the ExpectedWithdrawals. Locals: L the current epoch.
 */
SPEC_FUNCTION get_payload_attributes
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    ADDQ    a0, s1, BeaconState_genesis_time
    ADDQ    a1, s1, BeaconState_slot
    mv      a2, s3
    addi    a3, s5, PayloadAttributes_timestamp
    call    lantern_compute_time_at_slot
    bnez    a0, 9f
    mv      a0, s1                          # prev_randao: the mix of the current epoch
    addi    a1, sp, L
    call    lantern_get_current_epoch
    bnez    a0, 9f
    mv      a0, s1
    addi    a1, sp, L
    addi    a2, s5, PayloadAttributes_prev_randao
    call    lantern_get_randao_mix
    bnez    a0, 9f
    li      t0, 0                           # the fee recipient a byte at a time, then 4 zero bytes
1:  add     t1, s2, t0
    lbu     t2, 0(t1)
    add     t1, s5, t0
    sb      t2, PayloadAttributes_suggested_fee_recipient(t1)
    addi    t0, t0, 1
    li      t1, 20
    bltu    t0, t1, 1b
    sw      zero, (PayloadAttributes_suggested_fee_recipient + 20)(s5)
    sd      zero, (PayloadAttributes_parent_beacon_block_root + 0)(s5)
    sd      zero, (PayloadAttributes_parent_beacon_block_root + 8)(s5)
    sd      zero, (PayloadAttributes_parent_beacon_block_root + 16)(s5)
    sd      zero, (PayloadAttributes_parent_beacon_block_root + 24)(s5)
    sd      zero, PayloadAttributes_withdrawals(s5)
.if FORK >= FORK_DENEB
    ADDRESS a0, lantern_type_BeaconBlockHeader  # parent_beacon_block_root = hash_tree_root(state.latest_block_header)
    ADDQ    a1, s1, BeaconState_latest_block_header
    mv      a2, s4
    addi    a3, s5, PayloadAttributes_parent_beacon_block_root
    CALL_GLOBAL ssz_hash_tree_root
    bnez    a0, 9f
.endif
.if FORK >= FORK_CAPELLA
    ld      s6, 0(s4)                       # get_expected_withdrawals, its value at the end of scratch
    li      t0, EXPECTED_SCRATCH + SWEEP_BYTES
    bltu    s6, t0, 8f
    li      t0, SWEEP_BYTES
    sub     t0, s6, t0
    add     s7, s4, t0
    sd      t0, 0(s4)
    mv      a0, s1
    mv      a1, s4
    mv      a2, s7
    call    lantern_get_expected_withdrawals
    sd      s6, 0(s4)
    bnez    a0, 9f
    ld      t3, (16 + LIST_COUNT)(s7)
    sd      t3, PayloadAttributes_withdrawals(s5)
    addi    t4, s7, 16 + LIST_FIXED
    addi    t5, s5, PAYLOAD_ATTRIBUTES_WITHDRAWAL
2:  beqz    t3, 4f                          # each withdrawal: its 44 SSZ bytes, a word at a time
    li      t0, 0
3:  add     t1, t4, t0
    lwu     t2, 0(t1)
    add     t1, t5, t0
    sw      t2, 0(t1)
    addi    t0, t0, 4
    li      t1, 36
    bltu    t0, t1, 3b
    lwu     t2, Withdrawal_amount(t4)
    sw      t2, 36(t5)
    lwu     t2, (Withdrawal_amount + 4)(t4)
    sw      t2, 40(t5)
    addi    t4, t4, Withdrawal__mem
    addi    t5, t5, PAYLOAD_ATTRIBUTES_WITHDRAWAL_SIZE
    addi    t3, t3, -1
    j       2b
4:
.endif
    li      a0, LANTERN_OK
9:  LEAVE 16
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_payload_attributes

.endif
