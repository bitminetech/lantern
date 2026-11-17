/*
 * Engine API JSON-RPC requests, ARM64: in the objects of bellatrix and later.
 * Requirements: docs/reference/engine-api.md.
 *
 * The writers keep the write position in x2: each takes it and gives the new one.
 */

.if FORK >= FORK_BELLATRIX

/* The JSON text, before the code that takes its lengths. */
    RODATA
.include "engine_json.inc"

/* The text at label (include/engine_json.inc) to x2. Uses x0, x1, x9. */
.macro JTEXT label
    ADDRESS x0, \label
    mov     x1, #\label\()_len
    bl      jput
.endm

/* The byte c, a character code, to x2. Uses x9. */
.macro JCHAR c
    mov     w9, #\c
    strb    w9, [x2], #1
.endm

/* L0: the x1 bytes at x0 to x2. Uses x9. */
LOCAL_FUNCTION jput
    UNWIND_END_PROLOGUE
    cbz     x1, 2f
1:  ldrb    w9, [x0], #1
    strb    w9, [x2], #1
    subs    x1, x1, #1
    b.ne    1b
2:  ret
END_FUNCTION jput

/* L0: DATA: "0x" and two lowercase hex digits for each of the x1 bytes at x0, to x2. Uses x9-x11. */
LOCAL_FUNCTION jdata
    UNWIND_END_PROLOGUE
    mov     w9, #'"'
    strb    w9, [x2], #1
    mov     w9, #'0'
    strb    w9, [x2], #1
    mov     w9, #'x'
    strb    w9, [x2], #1
    cbz     x1, 3f
1:  ldrb    w10, [x0], #1
    lsr     w11, w10, #4
    cmp     w11, #10
    add     w9, w11, #'0'
    add     w11, w11, #('a' - 10)
    csel    w11, w9, w11, lo
    strb    w11, [x2], #1
    and     w11, w10, #15
    cmp     w11, #10
    add     w9, w11, #'0'
    add     w11, w11, #('a' - 10)
    csel    w11, w9, w11, lo
    strb    w11, [x2], #1
    subs    x1, x1, #1
    b.ne    1b
3:  mov     w9, #'"'
    strb    w9, [x2], #1
    ret
END_FUNCTION jdata

/* L0: QUANTITY of the x1 bytes, little endian, at x0: "0x" and the hex with no leading zeros, to x2. Uses x9-x12. */
LOCAL_FUNCTION jquantity
    UNWIND_END_PROLOGUE
    mov     w9, #'"'
    strb    w9, [x2], #1
    mov     w9, #'0'
    strb    w9, [x2], #1
    mov     w9, #'x'
    strb    w9, [x2], #1
    lsl     x12, x1, #1                     /* the digits, from the most significant */
    mov     x11, #0                         /* 1 once a digit other than 0 is written */
1:  sub     x12, x12, #1
    lsr     x10, x12, #1
    ldrb    w10, [x0, x10]
    tbz     x12, #0, 2f
    lsr     w10, w10, #4
2:  and     w10, w10, #15
    cbnz    x11, 3f
    cbnz    x12, 4f                         /* a leading zero, but the last digit is always written */
    b       3f
4:  cbz     w10, 5f
3:  mov     x11, #1
    cmp     w10, #10
    add     w9, w10, #'0'
    add     w10, w10, #('a' - 10)
    csel    w10, w9, w10, lo
    strb    w10, [x2], #1
5:  cbnz    x12, 1b
    mov     w9, #'"'
    strb    w9, [x2], #1
    ret
END_FUNCTION jquantity

/* L0: the decimal digits of x0 to x2. Uses x9-x12. */
LOCAL_FUNCTION jdecimal
    UNWIND_END_PROLOGUE
    mov     x12, #10
    mov     x9, x0
1:  udiv    x9, x9, x12
    add     x2, x2, #1
    cbnz    x9, 1b
    mov     x9, x2
2:  udiv    x10, x0, x12
    msub    x11, x10, x12, x0
    add     w11, w11, #'0'
    strb    w11, [x9, #-1]!
    mov     x0, x10
    cbnz    x0, 2b
    ret
END_FUNCTION jdecimal

/* QUANTITY of the u64 at base + off, to x2. Uses x0, x1, x9-x12. */
.macro JQ64 base, off
    add     x0, \base, #(\off)
    mov     x1, #8
    bl      jquantity
.endm

/* DATA of the n bytes at base + off, to x2. Uses x0, x1, x9-x11. */
.macro JDATA base, off, n
    ADDQ    x0, \base, \off
    mov     x1, #\n
    bl      jdata
.endm

/* The SSZ bytes of one request of each kind, and the copies that make them from a value. */
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
 * (execution_requests, out): x19 the requests, x20 out, x21 the write position, x22 the type,
 * x23 the entries, x24 their count.
 */
SPEC_FUNCTION get_execution_requests_list
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    add     x21, x20, #24
    mov     x22, #0
1:  cmp     x22, #3                         /* each kind, in type order */
    b.hs    9f
    cmp     x22, #1
    b.eq    2f
    b.hi    3f
    PART    x23, x24, x19, ExecutionRequests_deposits
    mov     x9, #DEPOSIT_REQUEST_SSZ
    b       4f
2:  PART    x23, x24, x19, ExecutionRequests_withdrawals
    mov     x9, #WITHDRAWAL_REQUEST_SSZ
    b       4f
3:  PART    x23, x24, x19, ExecutionRequests_consolidations
    mov     x9, #CONSOLIDATION_REQUEST_SSZ
4:  cbz     x24, 8f                         /* an empty list: no element */
    mul     x9, x9, x24                     /* the element: its length, the type, the requests */
    add     x9, x9, #1
    ldr     x10, [x20]                      /* room: 8 + the element */
    add     x11, x20, x10
    sub     x11, x11, x21
    add     x12, x9, #8
    cmp     x11, x12
    b.lo    7f
    str     x9, [x21], #8
    strb    w22, [x21], #1
5:  mov     x0, x21                         /* each request's SSZ bytes */
    mov     x1, x23
    cmp     x22, #1
    b.eq    6f
    mov     x2, #DEPOSIT_REQUEST_SSZ
    cmp     x22, #0
    b.eq    10f
    mov     x2, #CONSOLIDATION_REQUEST_SSZ
10: add     x21, x21, x2
    bl      lantern_copy
    cmp     x22, #0
    mov     x9, #DepositRequest__mem
    mov     x10, #ConsolidationRequest__mem
    csel    x9, x9, x10, eq
    b       11f
6:  mov     x2, #(20 + 48)                  /* a withdrawal request: its amount after a pad */
    bl      lantern_copy
    ldr     x9, [x23, #WithdrawalRequest_amount]
    str     x9, [x21, #(20 + 48)]
    add     x21, x21, #WITHDRAWAL_REQUEST_SSZ
    mov     x9, #WithdrawalRequest__mem
11: add     x23, x23, x9
    subs    x24, x24, #1
    b.ne    5b
8:  add     x22, x22, #1
    b       1b
9:  add     x9, x20, #24
    sub     x9, x21, x9
    mov     x10, #24
    stp     x10, x9, [x20, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
7:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END get_execution_requests_list
.endif

/* (block, out): the bound of engine-api.md. x9 the bound; x10-x15 work. */
SPEC_LEAF engine_new_payload_size
    PART    x10, x11, x0, BeaconBlock_body
    PART    x12, x11, x10, BeaconBlockBody_execution_payload
    mov     x9, #4096
    PART    x13, x14, x12, ExecutionPayload_extra_data   /* twice the bytes of extra_data */
    add     x9, x9, x14, lsl #1
    PART    x13, x14, x12, ExecutionPayload_transactions  /* 8 + twice the bytes of each transaction */
1:  cbz     x14, 2f
    ldr     x15, [x13, #16]
    add     x9, x9, x15, lsl #1
    add     x9, x9, #8
    ldr     x15, [x13]
    add     x13, x13, x15
    sub     x14, x14, #1
    b       1b
2:
.if FORK >= FORK_CAPELLA
    LDQ     x14, x12, ExecutionPayload_withdrawals + 8   /* 160 for each withdrawal */
    mov     x15, #160
    madd    x9, x14, x15, x9
.endif
.if FORK >= FORK_DENEB
    LDQ     x14, x10, BeaconBlockBody_blob_kzg_commitments + 8   /* 72 for each commitment */
    mov     x15, #72
    madd    x9, x14, x15, x9
.endif
.if FORK >= FORK_ELECTRA
    PART    x12, x11, x10, BeaconBlockBody_execution_requests    /* 8 + twice the bytes of each list */
    LDQ     x14, x12, ExecutionRequests_deposits + 8
    mov     x15, #(2 * DEPOSIT_REQUEST_SSZ)
    madd    x9, x14, x15, x9
    LDQ     x14, x12, ExecutionRequests_withdrawals + 8
    mov     x15, #(2 * WITHDRAWAL_REQUEST_SSZ)
    madd    x9, x14, x15, x9
    LDQ     x14, x12, ExecutionRequests_consolidations + 8
    mov     x15, #(2 * CONSOLIDATION_REQUEST_SSZ)
    madd    x9, x14, x15, x9
    add     x9, x9, #(3 * (8 + 2))
.endif
    str     x9, [x1]
    RETURN_OK
SPEC_END engine_new_payload_size

/*
 * (block, id, scratch, out): x19 block, x20 id, x21 scratch, x22 out, x23 body, x24 payload,
 * x25 the write position, x26 entries, x27 their count. Locals: L the bound, L+16 a versioned hash.
 */
SPEC_FUNCTION engine_new_payload
    ENTER 48
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    mov     x22, x3
    add     x1, sp, #L                      /* room for the bound */
    bl      lantern_engine_new_payload_size
    ldr     x9, [x22]
    subs    x9, x9, #24
    b.lo    8f
    ldr     x10, [sp, #L]
    cmp     x9, x10
    b.lo    8f
    PART    x23, x9, x19, BeaconBlock_body
    PART    x24, x9, x23, BeaconBlockBody_execution_payload
    add     x2, x22, #24
    /* {"jsonrpc":"2.0","id":id,"method":"engine_newPayloadVn","params":[ */
    JTEXT   j_open
    mov     x0, x20
    bl      jdecimal
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
    /* the payload */
    JTEXT   j_parent_hash
    JDATA   x24, ExecutionPayload_parent_hash, 32
    JTEXT   j_fee_recipient
    JDATA   x24, ExecutionPayload_fee_recipient, 20
    JTEXT   j_state_root
    JDATA   x24, ExecutionPayload_state_root, 32
    JTEXT   j_receipts_root
    JDATA   x24, ExecutionPayload_receipts_root, 32
    JTEXT   j_logs_bloom
    JDATA   x24, ExecutionPayload_logs_bloom, BYTES_PER_LOGS_BLOOM
    JTEXT   j_prev_randao
    JDATA   x24, ExecutionPayload_prev_randao, 32
    JTEXT   j_block_number
    JQ64    x24, ExecutionPayload_block_number
    JTEXT   j_gas_limit
    JQ64    x24, ExecutionPayload_gas_limit
    JTEXT   j_gas_used
    JQ64    x24, ExecutionPayload_gas_used
    JTEXT   j_timestamp
    JQ64    x24, ExecutionPayload_timestamp
    JTEXT   j_extra_data
    PART    x0, x1, x24, ExecutionPayload_extra_data
    bl      jdata
    JTEXT   j_base_fee
    ADDQ    x0, x24, ExecutionPayload_base_fee_per_gas
    mov     x1, #32
    bl      jquantity
    JTEXT   j_block_hash
    JDATA   x24, ExecutionPayload_block_hash, 32
    /* each transaction: a nested ByteList value */
    JTEXT   j_transactions
    PART    x26, x27, x24, ExecutionPayload_transactions
    cbz     x27, 2f
1:  ldr     x9, [x26, #8]
    add     x0, x26, x9
    ldr     x1, [x26, #16]
    bl      jdata
    ldr     x9, [x26]
    add     x26, x26, x9
    subs    x27, x27, #1
    b.eq    2f
    JCHAR   44
    b       1b
2:
.if FORK >= FORK_CAPELLA
    JTEXT   j_withdrawals
    PART    x26, x27, x24, ExecutionPayload_withdrawals
    cbz     x27, 4f
3:  JTEXT   j_w_index
    JQ64    x26, Withdrawal_index
    JTEXT   j_w_validator
    JQ64    x26, Withdrawal_validator_index
    JTEXT   j_w_address
    JDATA   x26, Withdrawal_address, 20
    JTEXT   j_w_amount
    JQ64    x26, Withdrawal_amount
    JCHAR   125
    add     x26, x26, #Withdrawal__mem
    subs    x27, x27, #1
    b.eq    4f
    JCHAR   44
    b       3b
4:
.endif
.if FORK >= FORK_DENEB
    JTEXT   j_blob_gas_used
    JQ64    x24, ExecutionPayload_blob_gas_used
    JTEXT   j_excess_blob_gas
    JQ64    x24, ExecutionPayload_excess_blob_gas
    JCHAR   125
    JCHAR   44                             /* the versioned hashes of the commitments */
    JCHAR   91
    PART    x26, x27, x23, BeaconBlockBody_blob_kzg_commitments
    cbz     x27, 6f
5:  mov     x25, x2
    mov     x0, x26
    add     x1, sp, #(L + 16)
    bl      lantern_kzg_commitment_to_versioned_hash
    mov     x2, x25
    add     x0, sp, #(L + 16)
    mov     x1, #32
    bl      jdata
    add     x26, x26, #48
    subs    x27, x27, #1
    b.eq    6f
    JCHAR   44
    b       5b
6:  JCHAR   93
    JCHAR   44
    JDATA   x19, BeaconBlock_parent_root, 32    /* parentBeaconBlockRoot */
.else
    JCHAR   93
    JCHAR   125
.endif
.if FORK >= FORK_ELECTRA
    JCHAR   44                             /* the request lists, through scratch */
    JCHAR   91
    mov     x25, x2
    PART    x0, x9, x23, BeaconBlockBody_execution_requests
    mov     x1, x21
    mov     x9, #24
    str     x9, [x21, #8]
    str     xzr, [x21, #16]
    bl      lantern_get_execution_requests_list
    cbnz    x0, 8f
    mov     x2, x25
    add     x26, x21, #24
    ldr     x27, [x21, #16]
    add     x27, x26, x27                   /* the end */
7:  cmp     x26, x27
    b.hs    9f
    add     x0, x26, #8
    ldr     x1, [x26]
    add     x26, x0, x1
    bl      jdata
    cmp     x26, x27
    b.hs    9f
    JCHAR   44
    b       7b
9:  JCHAR   93
.endif
    JTEXT   j_close
    add     x9, x22, #24
    sub     x9, x2, x9
    mov     x10, #24
    stp     x10, x9, [x22, #8]
    mov     x0, #LANTERN_OK
    LEAVE 48
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
SPEC_END engine_new_payload

/* (state, id, out): x19 state, x20 id, x21 out. */
SPEC_FUNCTION engine_forkchoice_updated
    ENTER 0
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    ldr     x9, [x21]
    cmp     x9, #(24 + 512)
    b.lo    8f
    add     x2, x21, #24
    JTEXT   j_open
    mov     x0, x20
    bl      jdecimal
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
    JDATA   x19, 0, 32
    JTEXT   j_safe
    JDATA   x19, 32, 32
    JTEXT   j_finalized
    JDATA   x19, 64, 32
    JTEXT   j_fcu_close
    add     x9, x21, #24
    sub     x9, x2, x9
    mov     x10, #24
    stp     x10, x9, [x21, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END engine_forkchoice_updated

.endif
