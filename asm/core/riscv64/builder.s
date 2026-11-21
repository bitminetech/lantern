/*
 * The builder of the node, RISC-V: in the common object. Requirements: docs/reference/node.md (the
 * builder calls) and beacon-api.md (registerValidator). A registration's SSZ bytes have no
 * alignment: its numbers load with LCS_LD64 (lcstore.s).
 */

    RODATA
bld_post_validators:
    .ascii  "POST /eth/v1/builder/validators HTTP/1.1\r\nHost: "
bld_post_validators_len = . - bld_post_validators
bld_head_json:
    .ascii  "\r\nAccept: application/json\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: "
bld_head_json_len = . - bld_head_json
bld_head_end:
    .ascii  "\r\n\r\n"
bld_head_end_len = . - bld_head_end
bld_reg_1:
    .ascii  "{\"message\":{\"fee_recipient\":\"0x"
bld_reg_1_len = . - bld_reg_1
bld_reg_2:
    .ascii  "\",\"gas_limit\":\""
bld_reg_2_len = . - bld_reg_2
bld_reg_3:
    .ascii  "\",\"timestamp\":\""
bld_reg_3_len = . - bld_reg_3
bld_reg_4:
    .ascii  "\",\"pubkey\":\"0x"
bld_reg_4_len = . - bld_reg_4
bld_reg_5:
    .ascii  "\"},\"signature\":\"0x"
bld_reg_5_len = . - bld_reg_5
bld_reg_6:
    .ascii  "\"}"
bld_reg_6_len = . - bld_reg_6
/*
 * The bytes of a registration's JSON other than its two numbers (the texts, 2 hex digits a byte of
 * 20 + 48 + 96), and of the request's head other than the host and Content-Length's digits.
 */
.set BLD_REG_FIXED, 423
.set BLD_HEAD_FIXED, 147
.if (bld_reg_1_len + bld_reg_2_len + bld_reg_3_len + bld_reg_4_len + bld_reg_5_len + bld_reg_6_len + 2 * (20 + 48 + 96) != BLD_REG_FIXED) || (bld_post_validators_len + bld_head_json_len + bld_head_end_len != BLD_HEAD_FIXED)
.error "a builder text's length is wrong"
.endif
/* The lengths of the texts, as numbers: li takes no difference of labels here. */
.set BLD_POST_VALIDATORS_LEN, 48
.set BLD_HEAD_JSON_LEN, 95
.set BLD_HEAD_END_LEN, 4
.set BLD_REG_1_LEN, 31
.set BLD_REG_2_LEN, 15
.set BLD_REG_3_LEN, 15
.set BLD_REG_4_LEN, 14
.set BLD_REG_5_LEN, 18
.set BLD_REG_6_LEN, 2
.if (bld_post_validators_len != BLD_POST_VALIDATORS_LEN) || (bld_head_json_len != BLD_HEAD_JSON_LEN) || (bld_head_end_len != BLD_HEAD_END_LEN) || (bld_reg_1_len != BLD_REG_1_LEN) || (bld_reg_2_len != BLD_REG_2_LEN) || (bld_reg_3_len != BLD_REG_3_LEN) || (bld_reg_4_len != BLD_REG_4_LEN) || (bld_reg_5_len != BLD_REG_5_LEN) || (bld_reg_6_len != BLD_REG_6_LEN)
.error "a builder text's length is wrong"
.endif
bld_hex_digits:
    .ascii  "0123456789abcdef"

# L0: a0 = the count of decimal digits of a0. Uses t0, t1.
LOCAL_FUNCTION bld_digits
    UNWIND_END_PROLOGUE
    li      t0, 1
    li      t1, 10
1:  bltu    a0, t1, 2f
    divu    a0, a0, t1
    addi    t0, t0, 1
    j       1b
2:  mv      a0, t0
    ret
END_FUNCTION bld_digits

# L0: a0 = the cursor a0 past the decimal digits of a1, written there. Uses t0-t3.
LOCAL_FUNCTION bld_dec
    UNWIND_END_PROLOGUE
    li      t0, 1
    li      t1, 10
    mv      t2, a1
1:  bltu    t2, t1, 2f
    divu    t2, t2, t1
    addi    t0, t0, 1
    j       1b
2:  add     a0, a0, t0
    mv      t2, a0
3:  remu    t3, a1, t1                      # from the last digit back
    divu    a1, a1, t1
    addi    t3, t3, '0'
    addi    t2, t2, -1
    sb      t3, 0(t2)
    addi    t0, t0, -1
    bnez    t0, 3b
    ret
END_FUNCTION bld_dec

# L0: a0 = the cursor a0 past the lower case hex digits of the a2 bytes at a1, written there. Uses t0-t2.
LOCAL_FUNCTION bld_hex
    UNWIND_END_PROLOGUE
    ADDRESS t0, bld_hex_digits
1:  beqz    a2, 2f
    lbu     t1, 0(a1)
    srli    t2, t1, 4
    andi    t1, t1, 15
    add     t2, t0, t2
    lbu     t2, 0(t2)
    add     t1, t0, t1
    lbu     t1, 0(t1)
    sb      t2, 0(a0)
    sb      t1, 1(a0)
    addi    a0, a0, 2
    addi    a1, a1, 1
    addi    a2, a2, -1
    j       1b
2:  ret
END_FUNCTION bld_hex

# L1: a0 = the cursor a0 past the a2 bytes at a1, copied there. Locals: the cursor, the count.
LOCAL_FUNCTION bld_put
    FRAME 16
    sd      a0, 0(sp)
    sd      a2, 8(sp)
    call    lantern_copy
    ld      a0, 0(sp)
    ld      a2, 8(sp)
    add     a0, a0, a2
    UNFRAME 16
END_FUNCTION bld_put

# L0: a0 = the index of a free entry of builder_calls (node.md, the builder calls), now of the kind
# a0, the NodeApi entry a1 and time_ms; 2^64 - 1 with none free. s1 the node. Uses t0-t3, a7.
LOCAL_FUNCTION node_builder_call
    UNWIND_END_PROLOGUE
    ADDQ    t0, s1, Node_builder_calls
    li      t1, 0
1:  li      t2, NODE_BUILDER_CALLS
    bgeu    t1, t2, 8f
    ld      t2, 0(t0)
    beqz    t2, 2f
    addi    t0, t0, NODE_BUILDER_CALL_SIZE
    addi    t1, t1, 1
    j       1b
2:  ld      t3, Node_time_ms(s1)
    sd      a0, 0(t0)
    sd      a1, 8(t0)
    sd      t3, 16(t0)
    mv      a0, t1
    ret
8:  li      a0, -1
    ret
END_FUNCTION node_builder_call

# L1: the NODE_EV_BUILDER s3 (node.md, the builder calls): its call's entry goes free. s1 the node, s6 the actions.
LOCAL_FUNCTION node_builder_event
    UNWIND_END_PROLOGUE
    ld      t0, 16(s3)
    andi    t0, t0, 255
    li      t1, NODE_BUILDER_CALLS
    bgeu    t0, t1, 9f
    ADDQ    t2, s1, Node_builder_calls
    li      t1, NODE_BUILDER_CALL_SIZE
    mul     t0, t0, t1
    add     t2, t2, t0
    sd      zero, 0(t2)
9:  ret
END_FUNCTION node_builder_event

# L1: a0 = the bytes of the JSON of the SignedValidatorRegistrationV1 at a0 (180 bytes). Locals: the registration, a count.
LOCAL_FUNCTION bld_reg_len
    FRAME 16
    sd      a0, 0(sp)
    addi    a1, a0, 20                      # gas_limit
    LCS_LD64 a0, a1
    call    bld_digits
    sd      a0, 8(sp)
    ld      a1, 0(sp)
    addi    a1, a1, 28                      # timestamp
    LCS_LD64 a0, a1
    call    bld_digits
    ld      t0, 8(sp)
    add     a0, a0, t0
    addi    a0, a0, BLD_REG_FIXED
    UNFRAME 16
END_FUNCTION bld_reg_len

# L1: a0 = the cursor a0 past the JSON of the SignedValidatorRegistrationV1 at a1, written there
# (node.md, NODE_WORK_API_SUBMIT of registerValidator). Locals: the registration.
LOCAL_FUNCTION bld_reg_json
    FRAME 16
    sd      a1, 8(sp)
    ADDRESS a1, bld_reg_1
    li      a2, BLD_REG_1_LEN
    call    bld_put
    ld      a1, 8(sp)                       # fee_recipient
    li      a2, 20
    call    bld_hex
    ADDRESS a1, bld_reg_2
    li      a2, BLD_REG_2_LEN
    call    bld_put
    ld      t0, 8(sp)                       # gas_limit
    addi    t0, t0, 20
    LCS_LD64 a1, t0
    call    bld_dec
    ADDRESS a1, bld_reg_3
    li      a2, BLD_REG_3_LEN
    call    bld_put
    ld      t0, 8(sp)                       # timestamp
    addi    t0, t0, 28
    LCS_LD64 a1, t0
    call    bld_dec
    ADDRESS a1, bld_reg_4
    li      a2, BLD_REG_4_LEN
    call    bld_put
    ld      a1, 8(sp)                       # pubkey
    addi    a1, a1, 36
    li      a2, 48
    call    bld_hex
    ADDRESS a1, bld_reg_5
    li      a2, BLD_REG_5_LEN
    call    bld_put
    ld      a1, 8(sp)                       # signature
    addi    a1, a1, 84
    li      a2, 96
    call    bld_hex
    ADDRESS a1, bld_reg_6
    li      a2, BLD_REG_6_LEN
    call    bld_put
    UNFRAME 16
END_FUNCTION bld_reg_json

# L2: the NODE_EV_WORK_DONE s3 of a NODE_WORK_API_SUBMIT of registerValidator, with
# NODE_FLAG_BUILDER (node.md): a NODE_BUILDER_REGISTER call of the JSON array of the registrations
# of LANTERN_VALID; none with none, with no free call, or with no room in the actions. s1 the
# node, s6 the actions; s4 a record, s5 the records left, s7 the body's bytes, s8 the valid ones,
# s9 the request's bytes, s10 the cursor. Locals: 0 the call.
LOCAL_FUNCTION node_builder_register
    ENTER 16
    ld      t0, Node_flags(s1)
    li      t1, NODE_FLAG_BUILDER
    and     t0, t0, t1
    beqz    t0, 9f
    ld      t0, (NodeEvent_chunk + 8)(s3)   # the body: [, each valid registration's JSON with , between, ]
    addi    s4, s3, NodeEvent_chunk
    add     s4, s4, t0
    ld      s5, NodeEvent_index(s3)
    li      s7, 2
    li      s8, 0
1:  beqz    s5, 2f
    ld      t0, 0(s4)
    bnez    t0, 11f
    ld      t0, (16 + 16)(s4)               # its SSZ bytes: 180
    li      t1, 180
    bne     t0, t1, 11f
    ld      t0, (16 + 8)(s4)
    addi    a0, s4, 16
    add     a0, a0, t0
    call    bld_reg_len
    add     s7, s7, a0
    beqz    s8, 12f
    addi    s7, s7, 1                       # the , before it
12: addi    s8, s8, 1
11: ld      t0, 16(s4)
    addi    s4, s4, 16
    add     s4, s4, t0
    addi    s5, s5, -1
    j       1b
2:  beqz    s8, 9f
    mv      a0, s7                          # the request: the head, then the body
    call    bld_digits
    LDQ     t0, s1, Node_builder_host_len
    add     s9, a0, t0
    addi    s9, s9, BLD_HEAD_FIXED
    add     s9, s9, s7
    addi    a0, s9, 48 + 7
    call    node_room
    beqz    a0, 9f
    li      a0, NODE_BUILDER_REGISTER
    li      a1, -1
    call    node_builder_call
    li      t0, -1
    beq     a0, t0, 9f
    sd      a0, 0(sp)
    addi    a1, s9, 48 + 7
    andi    a1, a1, -8
    li      a0, NODE_ACT_BUILDER
    call    node_act
    ld      t0, 0(sp)
    sd      t0, 16(a0)
    ld      t0, 0(a0)
    addi    t0, t0, -24
    sd      t0, 24(a0)
    li      t0, 24
    sd      t0, 32(a0)
    sd      s9, 40(a0)
    addi    a0, a0, 48
    ADDRESS a1, bld_post_validators
    li      a2, BLD_POST_VALIDATORS_LEN
    call    bld_put
    ADDQ    a1, s1, Node_builder_host
    LDQ     a2, s1, Node_builder_host_len
    call    bld_put
    ADDRESS a1, bld_head_json
    li      a2, BLD_HEAD_JSON_LEN
    call    bld_put
    mv      a1, s7
    call    bld_dec
    ADDRESS a1, bld_head_end
    li      a2, BLD_HEAD_END_LEN
    call    bld_put
    li      t0, '['
    sb      t0, 0(a0)
    addi    s10, a0, 1
    ld      t0, (NodeEvent_chunk + 8)(s3)
    addi    s4, s3, NodeEvent_chunk
    add     s4, s4, t0
    ld      s5, NodeEvent_index(s3)
    li      s8, 0
3:  beqz    s5, 4f
    ld      t0, 0(s4)
    bnez    t0, 31f
    ld      t0, (16 + 16)(s4)
    li      t1, 180
    bne     t0, t1, 31f
    beqz    s8, 32f
    li      t0, ','
    sb      t0, 0(s10)
    addi    s10, s10, 1
32: addi    s8, s8, 1
    ld      t0, (16 + 8)(s4)
    addi    a1, s4, 16
    add     a1, a1, t0
    mv      a0, s10
    call    bld_reg_json
    mv      s10, a0
31: ld      t0, 16(s4)
    addi    s4, s4, 16
    add     s4, s4, t0
    addi    s5, s5, -1
    j       3b
4:  li      t0, ']'
    sb      t0, 0(s10)
9:  LEAVE 16
END_FUNCTION node_builder_register

# L1: the registration of LANTERN_VALID at a0 (a ByteList of its 180 SSZ bytes) of the validator a1
# (beacon-api.md, registerValidator): its NodeProposer entry takes it, unless the entry holds one of a
# later timestamp; with none, the first free entry (until_epoch at most the store s2's epoch,
# registered 0), else a new one when the part has room; else none. s1 the node. Locals: the bytes,
# the index or the entry, the epoch.
LOCAL_FUNCTION node_registration_put
    FRAME 32
    ld      t0, 8(a0)
    add     t0, a0, t0
    sd      t0, 0(sp)
    sd      a1, 8(sp)
    mv      a0, s2
    call    node_store_slot
    li      t0, SLOTS_PER_EPOCH
    divu    a0, a0, t0
    sd      a0, 16(sp)
    ld      t5, 8(sp)                       # the validator index
    PART    t0, t1, s1, Node_proposers
    li      t2, 0
    li      t6, 0                           # the first free entry, or 0
1:  bgeu    t2, t1, 3f
    ld      t3, NodeProposer_validator_index(t0)
    beq     t3, t5, 4f
    bnez    t6, 2f
    ld      t3, NodeProposer_until_epoch(t0)
    bgtu    t3, a0, 2f
    ld      t3, NodeProposer_registered(t0)
    bnez    t3, 2f
    mv      t6, t0
2:  addi    t0, t0, NodeProposer__mem
    addi    t2, t2, 1
    j       1b
3:  mv      t0, t6                          # none of its index: a free entry, else a new one
    bnez    t0, 5f
    LDQ     t3, s1, Node_p2p_out            # the capacity: up to the next part
    LDQ     t4, s1, Node_proposers
    sub     t3, t3, t4
    li      t4, NodeProposer__mem
    divu    t3, t3, t4
    bgeu    t1, t3, 9f
    PART    t0, t2, s1, Node_proposers
    li      t4, NodeProposer__mem
    mul     t4, t1, t4
    add     t0, t0, t4
    addi    t1, t1, 1
    STQ     t1, s1, Node_proposers + 8
    sd      zero, NodeProposer_until_epoch(t0)  # a new entry: no preparation
    sd      zero, NodeProposer_fee_recipient(t0)
    sd      zero, (NodeProposer_fee_recipient + 8)(t0)
    sd      zero, (NodeProposer_fee_recipient + 16)(t0)
5:  sd      t5, NodeProposer_validator_index(t0)
    j       6f
4:  ld      t3, NodeProposer_registered(t0) # its entry: unless it holds a later registration
    beqz    t3, 6f
    ld      t3, NodeProposer_timestamp(t0)
    ld      t4, 0(sp)
    addi    t4, t4, 28
    LCS_LD64 t2, t4
    bgtu    t3, t2, 9f
6:  li      t1, 1
    sd      t1, NodeProposer_registered(t0)
    sd      t0, 8(sp)
    ld      t4, 0(sp)                       # gas_limit, timestamp
    addi    t4, t4, 20
    LCS_LD64 t2, t4
    ld      t0, 8(sp)
    sd      t2, NodeProposer_gas_limit(t0)
    ld      t4, 0(sp)
    addi    t4, t4, 28
    LCS_LD64 t2, t4
    ld      t0, 8(sp)
    sd      t2, NodeProposer_timestamp(t0)
    addi    a0, t0, NodeProposer_registration_fee_recipient
    ld      a1, 0(sp)
    li      a2, 20
    call    lantern_copy
9:  UNFRAME 32
END_FUNCTION node_registration_put

# The table slot of a record's pubkey at key, which has no alignment: its bytes 8 to 16 and 16 to 24, mixed, and the mask. Uses t3-t6.
.macro BLD_HASH_U out, key, mask
    addi    t4, \key, 8
    LCS_LD64 \out, t4
    addi    t4, \key, 16
    LCS_LD64 t3, t4
    xor     \out, \out, t3
    srli    t3, \out, 29
    xor     \out, \out, t3
    and     \out, \out, \mask
.endm

# The same of a validator's pubkey at key, 8-aligned. Uses t3.
.macro BLD_HASH_A out, key, mask
    ld      \out, 8(\key)
    ld      t3, 16(\key)
    xor     \out, \out, t3
    srli    t3, \out, 29
    xor     \out, \out, t3
    and     \out, \out, \mask
.endm

# L1: (state, records, count, scratch) -> a0: the validators of the records of a registerValidator
# (node.md, NODE_WORK_API_SUBMIT): one scan of the state's validators, through a table of the
# records' pubkeys at the end of scratch (a power of two of slots, at least twice the count, each a
# record or 0); each record whose pubkey is of a validator eligible at the state's epoch
# (builder-specs is_eligible_for_registration) takes LANTERN_VALID and the validator's index.
# LANTERN_OK, or LANTERN_BUFFER_TOO_SMALL with no room for the table. s1 state, s2 records, s3
# count, s4 scratch, s5 the table, s6 the mask, s7 a validator, s8 the validators left, s9 its
# index, s10 the epoch.
LOCAL_FUNCTION node_registrations_find
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    li      t0, 8
    slli    t1, s3, 1
1:  bgeu    t0, t1, 2f
    slli    t0, t0, 1
    j       1b
2:  addi    s6, t0, -1
    slli    t1, t0, 3
    ld      t2, 0(s4)
    addi    t3, t1, 64
    bltu    t2, t3, 98f
    sub     t2, t2, t1
    add     s5, s4, t2
    mv      a0, s5
    mv      a1, t1
    call    lantern_zero
    mv      a0, s2                          # each record's pubkey: its bytes at 36
    mv      a1, s3
3:  beqz    a1, 4f
    ld      t0, 24(a0)
    add     t0, a0, t0
    addi    t0, t0, 16 + 36
    BLD_HASH_U a2, t0, s6
31: slli    t1, a2, 3
    add     t1, s5, t1
    ld      t2, 0(t1)
    beqz    t2, 32f
    addi    a2, a2, 1
    and     a2, a2, s6
    j       31b
32: sd      a0, 0(t1)
    ld      t0, 16(a0)
    addi    a0, a0, 16
    add     a0, a0, t0
    addi    a1, a1, -1
    j       3b
4:  ld      s10, NODE_STATE_SLOT(s1)        # the state's epoch
    li      t0, SLOTS_PER_EPOCH
    divu    s10, s10, t0
    PART    s7, s8, s1, NODE_STATE_VALIDATORS
    li      s9, 0
5:  beqz    s8, 8f
    BLD_HASH_A a2, s7, s6
51: slli    t1, a2, 3
    add     t1, s5, t1
    ld      a3, 0(t1)
    beqz    a3, 6f
    ld      t0, 24(a3)                      # the record's pubkey, against the validator's
    add     t0, a3, t0
    addi    t0, t0, 16 + 36
    li      t1, 0
52: add     t2, t0, t1
    lbu     t2, 0(t2)
    add     t3, s7, t1
    lbu     t3, 0(t3)
    bne     t2, t3, 55f
    addi    t1, t1, 1
    li      t2, 48
    bltu    t1, t2, 52b
    ld      t2, NODE_VALIDATOR_ACTIVATION(s7)   # is_active_validator, or activation_epoch past the epoch
    ld      t3, NODE_VALIDATOR_EXIT(s7)
    bgtu    t2, s10, 53f
    bgeu    s10, t3, 55f
53: sd      zero, 0(a3)                     # LANTERN_VALID, the index
    sd      s9, 8(a3)
55: addi    a2, a2, 1
    and     a2, a2, s6
    j       51b
6:  addi    s7, s7, NODE_VALIDATOR_MEM
    addi    s9, s9, 1
    addi    s8, s8, -1
    j       5b
8:  li      a0, LANTERN_OK
    LEAVE 0
98: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION node_registrations_find
