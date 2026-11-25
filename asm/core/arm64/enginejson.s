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
    bl      lantern_jput
.endm

/* The byte c, a character code, to x2. Uses x9. */
.macro JCHAR c
    mov     w9, #\c
    strb    w9, [x2], #1
.endm

/* The x1 bytes at x0 to x2. Uses x9. */
LOCAL_FUNCTION lantern_jput
    UNWIND_END_PROLOGUE
    cbz     x1, 2f
1:  ldrb    w9, [x0], #1
    strb    w9, [x2], #1
    subs    x1, x1, #1
    b.ne    1b
2:  ret
END_FUNCTION lantern_jput

/* DATA: "0x" and two lowercase hex digits for each of the x1 bytes at x0, to x2. Uses x9-x11. */
LOCAL_FUNCTION lantern_jdata
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
END_FUNCTION lantern_jdata

/* QUANTITY of the x1 bytes, little endian, at x0: "0x" and the hex with no leading zeros, to x2. Uses x9-x12. */
LOCAL_FUNCTION lantern_jquantity
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
END_FUNCTION lantern_jquantity

/* The decimal digits of x0 to x2. Uses x9-x12. */
LOCAL_FUNCTION lantern_jdecimal
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
END_FUNCTION lantern_jdecimal

/* QUANTITY of the u64 at base + off, to x2. Uses x0, x1, x9-x12. */
.macro JQ64 base, off
    add     x0, \base, #(\off)
    mov     x1, #8
    bl      lantern_jquantity
.endm

/* DATA of the n bytes at base + off, to x2. Uses x0, x1, x9-x11. */
.macro JDATA base, off, n
    ADDQ    x0, \base, \off
    mov     x1, #\n
    bl      lantern_jdata
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

/*
 * (list, out): x19 the list's bytes, x20 their count, x21 out, x22 the write position, x23 the
 * item, x24 the items, x25 the lowest type the item may have. Locals: L, L+16, L+32 the data of
 * each type, its address and its bytes.
 */
SPEC_FUNCTION get_execution_requests
    ENTER 48
    ldp     x9, x20, [x0, #8]
    add     x19, x0, x9
    mov     x21, x1
    stp     xzr, xzr, [sp, #L]
    stp     xzr, xzr, [sp, #(L + 16)]
    stp     xzr, xzr, [sp, #(L + 32)]
    cbz     x20, 5f                         /* the SSZ list: no item, or the first offset, 4 an item, at most 3 */
    cmp     x20, #4
    b.lo    9f
    ldr     w9, [x19]
    tst     x9, #3
    b.ne    9f
    cbz     x9, 9f
    cmp     x9, #12
    b.hi    9f
    cmp     x9, x20
    b.hi    9f
    lsr     x24, x9, #2
    mov     x23, #0
    mov     x25, #0
1:  ldr     w10, [x19, x23, lsl #2]         /* item x23: from its offset to the next, or to the end */
    mov     x12, x20
    add     x11, x23, #1
    cmp     x11, x24
    b.hs    2f
    ldr     w12, [x19, x11, lsl #2]
2:  cmp     x10, x12
    b.hi    9f
    cmp     x12, x20
    b.hi    9f
    sub     x13, x12, x10                   /* a type in ascending order, and data */
    cmp     x13, #2
    b.lo    9f
    ldrb    w14, [x19, x10]
    cmp     x14, x25
    b.lo    9f
    cmp     x14, #3
    b.hs    9f
    add     x25, x14, #1
    sub     x13, x13, #1
    add     x10, x10, #1
    add     x10, x19, x10
    cmp     x14, #1                         /* the data: whole requests of the type, at most its limit */
    b.eq    3f
    b.hi    4f
    mov     x15, #DEPOSIT_REQUEST_SSZ
    MOVQ    x16, DEPOSIT_REQUEST_SSZ * MAX_DEPOSIT_REQUESTS_PER_PAYLOAD
    b       6f
3:  mov     x15, #WITHDRAWAL_REQUEST_SSZ
    MOVQ    x16, WITHDRAWAL_REQUEST_SSZ * MAX_WITHDRAWAL_REQUESTS_PER_PAYLOAD
    b       6f
4:  mov     x15, #CONSOLIDATION_REQUEST_SSZ
    MOVQ    x16, CONSOLIDATION_REQUEST_SSZ * MAX_CONSOLIDATION_REQUESTS_PER_PAYLOAD
6:  cmp     x13, x16
    b.hi    9f
    udiv    x9, x13, x15
    msub    x9, x9, x15, x13
    cbnz    x9, 9f
    add     x9, sp, #L
    add     x9, x9, x14, lsl #4
    stp     x10, x13, [x9]
    add     x23, x23, #1
    cmp     x23, x24
    b.lo    1b
5:  ldr     x9, [sp, #(L + 8)]              /* ExecutionRequests: three offsets, then the data of each type */
    ldr     x10, [sp, #(L + 24)]
    ldr     x11, [sp, #(L + 40)]
    add     x12, x9, x10
    add     x12, x12, x11
    add     x12, x12, #12
    ldr     x13, [x21]
    subs    x13, x13, #24
    b.lo    8f
    cmp     x13, x12
    b.lo    8f
    mov     x13, #24
    stp     x13, x12, [x21, #8]
    add     x22, x21, #24
    mov     w12, #12
    str     w12, [x22]
    add     w12, w12, w9
    str     w12, [x22, #4]
    add     w12, w12, w10
    str     w12, [x22, #8]
    add     x22, x22, #12
    mov     x23, #0
7:  add     x9, sp, #L
    add     x9, x9, x23, lsl #4
    ldp     x1, x2, [x9]
    mov     x0, x22
    add     x22, x22, x2
    bl      lantern_copy
    add     x23, x23, #1
    cmp     x23, #3
    b.lo    7b
    mov     x0, #LANTERN_OK
    LEAVE 48
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
9:  mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 48
SPEC_END get_execution_requests
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
    bl      lantern_jdecimal
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
    bl      lantern_jdata
    JTEXT   j_base_fee
    ADDQ    x0, x24, ExecutionPayload_base_fee_per_gas
    mov     x1, #32
    bl      lantern_jquantity
    JTEXT   j_block_hash
    JDATA   x24, ExecutionPayload_block_hash, 32
    /* each transaction: a nested ByteList value */
    JTEXT   j_transactions
    PART    x26, x27, x24, ExecutionPayload_transactions
    cbz     x27, 2f
1:  ldr     x9, [x26, #8]
    add     x0, x26, x9
    ldr     x1, [x26, #16]
    bl      lantern_jdata
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
    bl      lantern_jdata
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
    bl      lantern_jdata
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

/* (state, attributes, id, out): x19 state, x20 id, x21 out, x22 attributes, x23 a withdrawal, x24 those left. */
SPEC_FUNCTION engine_forkchoice_updated
    ENTER 0
    mov     x19, x0
    mov     x22, x1
    ldr     x20, [x2]
    mov     x21, x3
    ldr     x9, [x21]                       /* the room: 512 bytes, or 1024 and 192 a withdrawal */
    mov     x10, #(24 + 512)
    cbz     x22, 1f
    mov     x10, #(24 + 1024)
.if FORK >= FORK_CAPELLA
    ldr     x11, [x22, #PayloadAttributes_withdrawals]
    mov     x12, #192
    madd    x10, x11, x12, x10
.endif
1:  cmp     x9, x10
    b.lo    8f
    add     x2, x21, #24
    JTEXT   j_open
    mov     x0, x20
    bl      lantern_jdecimal
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
    cbnz    x22, 2f
    JTEXT   j_fcu_close
    b       7f
    /* the PayloadAttributes */
2:  JTEXT   j_attr_open
    JQ64    x22, PayloadAttributes_timestamp
    JTEXT   j_prev_randao
    JDATA   x22, PayloadAttributes_prev_randao, 32
    JTEXT   j_attr_fee_recipient
    JDATA   x22, PayloadAttributes_suggested_fee_recipient, 20
.if FORK >= FORK_CAPELLA
    /* each withdrawal: its 44 SSZ bytes */
    JTEXT   j_attr_withdrawals
    add     x23, x22, #PAYLOAD_ATTRIBUTES_WITHDRAWAL
    ldr     x24, [x22, #PayloadAttributes_withdrawals]
    cbz     x24, 4f
3:  JTEXT   j_w_index
    JQ64    x23, 0
    JTEXT   j_w_validator
    JQ64    x23, 8
    JTEXT   j_w_address
    JDATA   x23, 16, 20
    JTEXT   j_w_amount
    JQ64    x23, 36
    JCHAR   125
    add     x23, x23, #PAYLOAD_ATTRIBUTES_WITHDRAWAL_SIZE
    subs    x24, x24, #1
    b.eq    4f
    JCHAR   44
    b       3b
4:  JCHAR   93
.endif
.if FORK >= FORK_DENEB
    JTEXT   j_attr_parent_root
    JDATA   x22, PayloadAttributes_parent_beacon_block_root, 32
.endif
    JTEXT   j_attr_close
7:  add     x9, x21, #24
    sub     x9, x2, x9
    mov     x10, #24
    stp     x10, x9, [x21, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END engine_forkchoice_updated

/* (payload_id, id, out): x19 payload_id, x20 id, x21 out. */
SPEC_FUNCTION engine_get_payload
    ENTER 0
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    ldr     x9, [x21]
    cmp     x9, #(24 + 256)
    b.lo    8f
    add     x2, x21, #24
    JTEXT   j_open
    mov     x0, x20
    bl      lantern_jdecimal
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
    JDATA   x19, 0, 8
    JTEXT   j_close
    add     x9, x21, #24
    sub     x9, x2, x9
    mov     x10, #24
    stp     x10, x9, [x21, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
SPEC_END engine_get_payload

.if FORK >= FORK_CAPELLA
.if Withdrawal_index != 0 || Withdrawal_validator_index != 8
.error "get_payload_attributes copies index and validator_index as the first 16 bytes of a Withdrawal"
.endif
.endif

/*
 * (state, fee_recipient, config, scratch, out): x19 state, x20 fee_recipient, x21 config, x22
 * scratch, x23 out, x24 the scratch size, x25 the ExpectedWithdrawals, x26 a withdrawal, x27 those
 * left. Locals: L the current epoch.
 */
SPEC_FUNCTION get_payload_attributes
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ADDQ    x0, x19, BeaconState_genesis_time
    ADDQ    x1, x19, BeaconState_slot
    mov     x2, x21
    add     x3, x23, #PayloadAttributes_timestamp
    bl      lantern_compute_time_at_slot
    cbnz    x0, 9f
    mov     x0, x19                         /* prev_randao: the mix of the current epoch */
    add     x1, sp, #L
    bl      lantern_get_current_epoch
    cbnz    x0, 9f
    mov     x0, x19
    add     x1, sp, #L
    add     x2, x23, #PayloadAttributes_prev_randao
    bl      lantern_get_randao_mix
    cbnz    x0, 9f
    ldp     x9, x10, [x20]                  /* the fee recipient, then 4 zero bytes */
    ldr     w11, [x20, #16]
    stp     x9, x10, [x23, #PayloadAttributes_suggested_fee_recipient]
    str     x11, [x23, #(PayloadAttributes_suggested_fee_recipient + 16)]
    add     x9, x23, #PayloadAttributes_parent_beacon_block_root
    stp     xzr, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    str     xzr, [x23, #PayloadAttributes_withdrawals]
.if FORK >= FORK_DENEB
    ADDRESS x0, lantern_type_BeaconBlockHeader  /* parent_beacon_block_root = hash_tree_root(state.latest_block_header) */
    ADDQ    x1, x19, BeaconState_latest_block_header
    mov     x2, x22
    add     x3, x23, #PayloadAttributes_parent_beacon_block_root
    CALL_GLOBAL ssz_hash_tree_root
    cbnz    x0, 9f
.endif
.if FORK >= FORK_CAPELLA
    ldr     x24, [x22]                      /* get_expected_withdrawals, its value at the end of scratch */
    MOVQ    x9, EXPECTED_SCRATCH + SWEEP_BYTES
    cmp     x24, x9
    b.lo    8f
    MOVQ    x9, SWEEP_BYTES
    sub     x9, x24, x9
    add     x25, x22, x9
    str     x9, [x22]
    mov     x0, x19
    mov     x1, x22
    mov     x2, x25
    bl      lantern_get_expected_withdrawals
    str     x24, [x22]
    cbnz    x0, 9f
    ldr     x27, [x25, #(16 + LIST_COUNT)]
    add     x26, x25, #(16 + LIST_FIXED)
    str     x27, [x23, #PayloadAttributes_withdrawals]
    add     x9, x23, #PAYLOAD_ATTRIBUTES_WITHDRAWAL
1:  cbz     x27, 2f                         /* each withdrawal: its 44 SSZ bytes */
    ldp     x10, x11, [x26]
    stp     x10, x11, [x9]
    ldp     x10, x11, [x26, #Withdrawal_address]
    stp     x10, x11, [x9, #16]
    ldr     w10, [x26, #(Withdrawal_address + 16)]
    str     w10, [x9, #32]
    ldr     x10, [x26, #Withdrawal_amount]
    stur    x10, [x9, #36]
    add     x26, x26, #Withdrawal__mem
    add     x9, x9, #PAYLOAD_ATTRIBUTES_WITHDRAWAL_SIZE
    sub     x27, x27, #1
    b       1b
2:
.endif
    mov     x0, #LANTERN_OK
9:  LEAVE 16
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
SPEC_END get_payload_attributes

.endif
