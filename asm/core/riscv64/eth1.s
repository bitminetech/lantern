/*
 * The eth1 follower's functions, RISC-V: in the common object. Requirements: docs/reference/eth1.md.
 *
 * The parsers use the JSON helpers of jsonrpc.s, which read the end of the text from s1; the cursor
 * is in a0.
 */

    RODATA
.include "eth1_text.inc"
e1_digits:
    .ascii  "0123456789abcdef"

# The QUANTITY of a0 to the cursor a1: "0x", then hex digits with no leading zero; a1 = the end. Uses t0-t3.
LOCAL_FUNCTION lantern_e1_qty
    UNWIND_END_PROLOGUE
    li      t0, '0'
    sb      t0, 0(a1)
    li      t0, 'x'
    sb      t0, 1(a1)
    addi    a1, a1, 2
    li      t0, 60                          # the highest nibble that is not zero, or the last
1:  beqz    t0, 2f
    srl     t1, a0, t0
    andi    t1, t1, 15
    bnez    t1, 2f
    addi    t0, t0, -4
    j       1b
2:  ADDRESS t2, e1_digits
3:  srl     t1, a0, t0
    andi    t1, t1, 15
    add     t1, t2, t1
    lbu     t3, 0(t1)
    sb      t3, 0(a1)
    addi    a1, a1, 1
    beqz    t0, 4f
    addi    t0, t0, -4
    j       3b
4:  ret
END_FUNCTION lantern_e1_qty

# The a2 bytes at a0 as lowercase hex to the cursor a1; a1 = the end. Uses t0-t3.
LOCAL_FUNCTION lantern_e1_hex
    UNWIND_END_PROLOGUE
    ADDRESS t2, e1_digits
1:  beqz    a2, 2f
    lbu     t0, 0(a0)
    addi    a0, a0, 1
    srli    t1, t0, 4
    add     t1, t2, t1
    lbu     t3, 0(t1)
    sb      t3, 0(a1)
    andi    t1, t0, 15
    add     t1, t2, t1
    lbu     t3, 0(t1)
    sb      t3, 1(a1)
    addi    a1, a1, 2
    addi    a2, a2, -1
    j       1b
2:  ret
END_FUNCTION lantern_e1_hex

# The ByteList a0 holds the bytes from its byte 24 to the cursor a1: its offset 24 and its length. Uses t0.
LOCAL_FUNCTION lantern_e1_close
    UNWIND_END_PROLOGUE
    addi    t0, a0, 24
    sub     t0, a1, t0
    sd      t0, 16(a0)
    li      t0, 24
    sd      t0, 8(a0)
    ret
END_FUNCTION lantern_e1_close

# (number, id, out): eth_getBlockByNumber. s2 number, s3 id, s4 out.
FUNCTION lantern_eth_get_block_by_number
    ENTER 0
    ld      s2, 0(a0)
    ld      s3, 0(a1)
    mv      s4, a2
    ld      t0, 0(s4)
    li      t1, 24 + 128
    bltu    t0, t1, 8f
    ADDRESS a0, e1_open
    li      a1, e1_open_len
    addi    a2, s4, 24
    call    lantern_put_bytes
    mv      a0, s3
    mv      a1, a2
    call    lantern_decimal
    mv      a2, a1
    ADDRESS a0, e1_block
    li      a1, e1_block_len
    call    lantern_put_bytes
    li      t0, -1                          # 2^64 - 1: latest
    bne     s2, t0, 1f
    ADDRESS a0, e1_latest
    li      a1, e1_latest_len
    call    lantern_put_bytes
    j       2f
1:  mv      a0, s2
    mv      a1, a2
    call    lantern_e1_qty
    mv      a2, a1
2:  ADDRESS a0, e1_bclose
    li      a1, e1_bclose_len
    call    lantern_put_bytes
    mv      a0, s4
    mv      a1, a2
    call    lantern_e1_close
    li      a0, LANTERN_OK
    LEAVE 0
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_eth_get_block_by_number

# (address, from, to, id, out): eth_getLogs of the DepositEvent logs. s2 address, s3 from, s4 to, s7 id, s8 out.
FUNCTION lantern_eth_get_deposit_logs
    ENTER 0
    mv      s2, a0
    ld      s3, 0(a1)
    ld      s4, 0(a2)
    ld      s7, 0(a3)
    mv      s8, a4
    ld      t0, 0(s8)
    li      t1, 24 + 384
    bltu    t0, t1, 8f
    ADDRESS a0, e1_open
    li      a1, e1_open_len
    addi    a2, s8, 24
    call    lantern_put_bytes
    mv      a0, s7
    mv      a1, a2
    call    lantern_decimal
    mv      a2, a1
    ADDRESS a0, e1_logs
    li      a1, e1_logs_len
    call    lantern_put_bytes
    mv      a1, a2
    mv      a0, s2
    li      a2, 20
    call    lantern_e1_hex
    mv      a2, a1
    ADDRESS a0, e1_topics
    li      a1, e1_topics_len
    call    lantern_put_bytes
    mv      a0, s3
    mv      a1, a2
    call    lantern_e1_qty
    mv      a2, a1
    ADDRESS a0, e1_to
    li      a1, e1_to_len
    call    lantern_put_bytes
    mv      a0, s4
    mv      a1, a2
    call    lantern_e1_qty
    mv      a2, a1
    ADDRESS a0, e1_lclose
    li      a1, e1_lclose_len
    call    lantern_put_bytes
    mv      a0, s8
    mv      a1, a2
    call    lantern_e1_close
    li      a0, LANTERN_OK
    LEAVE 0
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_eth_get_deposit_logs

# A QUANTITY string at the cursor a0: a0 = the cursor after it and a1 its value, or a0 = 0 for
# none: "0x", then 1 to 16 hex digits with no leading zero. Uses a1-a3, t0-t4.
LOCAL_FUNCTION lantern_e1_qty_in
    FRAME 16
    call    lantern_jstring
    beqz    a0, 9f
    bnez    a3, 9f
    li      t0, 3
    bltu    a2, t0, 9f
    li      t0, 18
    bgtu    a2, t0, 9f
    lbu     t0, 0(a1)
    li      t1, '0'
    bne     t0, t1, 9f
    lbu     t0, 1(a1)
    li      t1, 'x'
    bne     t0, t1, 9f
    addi    a1, a1, 2
    addi    a2, a2, -2
    lbu     t0, 0(a1)                       # no leading zero, but 0x0
    li      t1, '0'
    bne     t0, t1, 1f
    li      t1, 1
    bne     a2, t1, 9f
1:  li      t4, 0
2:  lbu     t0, 0(a1)
    addi    a1, a1, 1
    addi    t1, t0, -'0'
    li      t2, 10
    bltu    t1, t2, 3f
    ori     t0, t0, 0x20
    addi    t1, t0, -'a'
    li      t2, 6
    bgeu    t1, t2, 9f
    addi    t1, t1, 10
3:  slli    t4, t4, 4
    or      t4, t4, t1
    addi    a2, a2, -1
    bnez    a2, 2b
    mv      a1, t4
    UNFRAME 16
9:  li      a0, 0
    UNFRAME 16
END_FUNCTION lantern_e1_qty_in

# (json, out): the number, hash and timestamp of an eth_getBlockByNumber result. s1 the text's
# end, s2 out, s3 the members read: 1 number, 2 hash, 4 timestamp.
FUNCTION lantern_eth1_block
    ENTER 0
    mv      s2, a1
    sd      zero, 0(s2)
    sd      zero, 8(s2)
    sd      zero, 16(s2)
    sd      zero, 24(s2)
    sd      zero, 32(s2)
    sd      zero, 40(s2)
    sd      zero, 48(s2)
    sd      zero, 56(s2)
    sd      zero, 64(s2)
    sd      zero, 72(s2)
    sd      zero, 80(s2)
    ld      t0, 8(a0)
    ld      t1, 16(a0)
    add     a0, a0, t0
    add     s1, a0, t1
    li      s3, 0
    call    lantern_jws
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    li      t1, '{'
    bne     t0, t1, 9f
    addi    a0, a0, 1
    li      a1, 1
1:  call    lantern_jmember
    beqz    a0, 9f
    bnez    a3, 7f
    JIS     e1_n_number
    beqz    t0, 2f
    call    lantern_e1_qty_in
    beqz    a0, 9f
    sd      a1, Eth1Block_number(s2)
    ori     s3, s3, 1
    j       6f
2:  JIS     e1_n_timestamp
    beqz    t0, 3f
    call    lantern_e1_qty_in
    beqz    a0, 9f
    sd      a1, Eth1Block_timestamp(s2)
    ori     s3, s3, 4
    j       6f
3:  JIS     e1_n_hash
    beqz    t0, 4f
    li      a1, 0
    li      a2, 32
    addi    a3, s2, Eth1Block_hash
    call    lantern_jdata_in
    beqz    a0, 9f
    ori     s3, s3, 2
    j       6f
4:  call    lantern_jskip
    beqz    a0, 9f
6:  li      a1, 0
    j       1b
7:  call    lantern_jws                             # nothing after the object, and each of the three
    bne     a0, s1, 9f
    li      t0, 7
    bne     s3, t0, 9f
    li      a0, LANTERN_OK
    LEAVE 0
9:  sd      zero, 0(s2)
    sd      zero, 8(s2)
    sd      zero, 16(s2)
    sd      zero, 24(s2)
    sd      zero, 32(s2)
    sd      zero, 40(s2)
    sd      zero, 48(s2)
    sd      zero, 56(s2)
    li      a0, LANTERN_INVALID_JSON
    LEAVE 0
END_FUNCTION lantern_eth1_block

# (json, out): the deposits of an eth_getLogs result. s1 the text's end, s2 out, s3 the next entry,
# s7 the entries' end, s8 the members read (1 blockNumber, 2 topics, 4 data, 8 removed true, 16
# data of another length), s9 blockNumber, s10 a cursor. Locals: L the topic (32), L+32 the data
# (576), L+608 where the data's bytes go, or 0.
FUNCTION lantern_eth1_deposit_logs
    ENTER 624
    mv      s2, a1
    ld      t0, 8(a0)
    ld      t1, 16(a0)
    add     a0, a0, t0
    add     s1, a0, t1
    ld      t0, 0(s2)
    add     s7, s2, t0
    addi    s3, s2, 24
    li      t0, 24
    sd      t0, 8(s2)
    sd      zero, 16(s2)
    call    lantern_jws
    bgeu    a0, s1, 90f
    lbu     t0, 0(a0)
    li      t1, '['
    bne     t0, t1, 90f
    addi    a0, a0, 1
    call    lantern_jws
    bgeu    a0, s1, 90f
    lbu     t0, 0(a0)
    li      t1, ']'
    bne     t0, t1, 1f
    addi    a0, a0, 1
    j       80f
1:  bgeu    a0, s1, 90f                     # a log
    lbu     t0, 0(a0)
    li      t1, '{'
    bne     t0, t1, 90f
    addi    a0, a0, 1
    li      s8, 0
    li      a1, 1
2:  call    lantern_jmember
    beqz    a0, 90f
    bnez    a3, 40f
    JIS     e1_n_block_number
    beqz    t0, 3f
    call    lantern_e1_qty_in
    beqz    a0, 90f
    mv      s9, a1
    ori     s8, s8, 1
    j       30f
3:  JIS     e1_n_removed
    beqz    t0, 4f
    andi    s8, s8, ~8
    mv      s10, a0
    ADDRESS a1, json_false
    li      a2, json_false_len
    call    lantern_jliteral
    bnez    a0, 30f
    mv      a0, s10
    ADDRESS a1, json_true
    li      a2, json_true_len
    call    lantern_jliteral
    beqz    a0, 90f
    ori     s8, s8, 8
    j       30f
4:  JIS     e1_n_topics
    beqz    t0, 5f
    bgeu    a0, s1, 90f                     # an array: its first item the DepositEvent topic
    lbu     t0, 0(a0)
    li      t1, '['
    bne     t0, t1, 90f
    addi    a0, a0, 1
    call    lantern_jws
    li      a1, 0
    li      a2, 32
    addi    a3, sp, L
    call    lantern_jdata_in
    beqz    a0, 90f
    addi    t0, sp, L
    ADDRESS t1, e1_topic
    li      t2, 0
43: add     t3, t0, t2
    lbu     t3, 0(t3)
    add     t4, t1, t2
    lbu     t4, 0(t4)
    bne     t3, t4, 90f
    addi    t2, t2, 1
    li      t3, 32
    bltu    t2, t3, 43b
41: call    lantern_jws
    bgeu    a0, s1, 90f
    lbu     t0, 0(a0)
    addi    a0, a0, 1
    li      t1, ']'
    beq     t0, t1, 42f
    li      t1, ','
    bne     t0, t1, 90f
    call    lantern_jws
    call    lantern_jskip
    beqz    a0, 90f
    j       41b
42: ori     s8, s8, 2
    j       30f
5:  JIS     e1_n_data
    beqz    t0, 6f
    call    lantern_jstring                         # "0x", then 2 hex digits a byte; 576 bytes, else no deposit's
    beqz    a0, 90f
    bnez    a3, 90f
    li      t0, 2
    bltu    a2, t0, 90f
    andi    t0, a2, 1
    bnez    t0, 90f
    lbu     t0, 0(a1)
    li      t1, '0'
    bne     t0, t1, 90f
    lbu     t0, 1(a1)
    li      t1, 'x'
    bne     t0, t1, 90f
    andi    s8, s8, ~16
    addi    a1, a1, 2
    addi    a2, a2, -2
    addi    t0, sp, (L + 32)
    sd      t0, (L + 608)(sp)
    li      t0, 1152
    beq     a2, t0, 52f
    ori     s8, s8, 16
    sd      zero, (L + 608)(sp)             # only the digits checked
52: beqz    a2, 55f
    li      t4, 0
    li      t5, 2
53: lbu     t0, 0(a1)
    addi    a1, a1, 1
    addi    t1, t0, -'0'
    li      t2, 10
    bltu    t1, t2, 54f
    ori     t0, t0, 0x20
    addi    t1, t0, -'a'
    li      t2, 6
    bgeu    t1, t2, 90f
    addi    t1, t1, 10
54: slli    t4, t4, 4
    or      t4, t4, t1
    addi    a2, a2, -1
    addi    t5, t5, -1
    bnez    t5, 53b
    ld      t0, (L + 608)(sp)
    beqz    t0, 52b
    sb      t4, 0(t0)
    addi    t0, t0, 1
    sd      t0, (L + 608)(sp)
    j       52b
55: ori     s8, s8, 4
    j       30f
6:  call    lantern_jskip
    beqz    a0, 90f
30: li      a1, 0
    j       2b
40: andi    t0, s8, 7                       # the log's end: blockNumber, topics and data
    li      t1, 7
    bne     t0, t1, 90f
    andi    t0, s8, 8                       # removed: no deposit
    bnez    t0, 70f
    andi    t0, s8, 16
    bnez    t0, 91f
    mv      s10, a0
    addi    a0, sp, (L + 32)                # the contract's encoding: the bytes of e1_abi but the values
    call    lantern_e1_abi_check
    beqz    a0, 91f
    addi    t0, s3, Eth1Deposit__mem
    bgtu    t0, s7, 92f
    sd      s9, Eth1Deposit_block_number(s3)
    ld      t0, (L + 32 + 544)(sp)          # index
    sd      t0, Eth1Deposit_index(s3)
    addi    a0, s3, Eth1Deposit_data        # pubkey
    addi    a1, sp, (L + 32 + 192)
    li      a2, 48
    call    lantern_copy
    addi    a0, s3, (Eth1Deposit_data + 48) # withdrawal_credentials
    addi    a1, sp, (L + 32 + 288)
    li      a2, 32
    call    lantern_copy
    ld      t0, (L + 32 + 352)(sp)          # amount
    sd      t0, (Eth1Deposit_data + 80)(s3)
    addi    a0, s3, (Eth1Deposit_data + 88) # signature
    addi    a1, sp, (L + 32 + 416)
    li      a2, 96
    call    lantern_copy
    addi    s3, s3, Eth1Deposit__mem
    mv      a0, s10
70: call    lantern_jws                             # a comma and the next log, or the array's end
    bgeu    a0, s1, 90f
    lbu     t0, 0(a0)
    addi    a0, a0, 1
    li      t1, ','
    bne     t0, t1, 71f
    call    lantern_jws
    j       1b
71: li      t1, ']'
    bne     t0, t1, 90f
80: call    lantern_jws                             # nothing after the array
    bne     a0, s1, 90f
    addi    t0, s2, 24
    sub     t0, s3, t0
    sd      t0, 16(s2)
    li      a0, LANTERN_OK
    LEAVE 624
90: li      a0, LANTERN_INVALID_JSON
    LEAVE 624
91: li      a0, LANTERN_INVALID_DEPOSIT_LOG
    LEAVE 624
92: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 624
END_FUNCTION lantern_eth1_deposit_logs

# a0 = 1 when the 576 bytes at a0 are e1_abi but in the values (pubkey 192, withdrawal
# credentials 288, amount 352, signature 416, index 544), else 0. Uses t0-t4.
LOCAL_FUNCTION lantern_e1_abi_check
    UNWIND_END_PROLOGUE
    ADDRESS t1, e1_abi
    li      t0, 0
1:  li      t2, 576
    bgeu    t0, t2, 8f
    li      t2, 192                         # the value ranges are skipped
    bltu    t0, t2, 3f
    li      t2, 240
    bltu    t0, t2, 2f
    li      t2, 288
    bltu    t0, t2, 3f
    li      t2, 320
    bltu    t0, t2, 2f
    li      t2, 352
    bltu    t0, t2, 3f
    li      t2, 360
    bltu    t0, t2, 2f
    li      t2, 416
    bltu    t0, t2, 3f
    li      t2, 512
    bltu    t0, t2, 2f
    li      t2, 544
    bltu    t0, t2, 3f
    li      t2, 552
    bltu    t0, t2, 2f
3:  add     t3, a0, t0
    lbu     t3, 0(t3)
    add     t4, t1, t0
    lbu     t4, 0(t4)
    bne     t3, t4, 9f
2:  addi    t0, t0, 1
    j       1b
8:  li      a0, 1
    ret
9:  li      a0, 0
    ret
END_FUNCTION lantern_e1_abi_check

# SHA-256 of the 32 bytes at a0 and the 32 bytes at a1, to a2. Locals: out, then a ByteList of 64 bytes.
LOCAL_FUNCTION lantern_e1_hash2
    FRAME 96
    sd      a2, 0(sp)
    li      t0, 88
    sd      t0, 8(sp)
    li      t0, 24
    sd      t0, 16(sp)
    li      t0, 64
    sd      t0, 24(sp)
    addi    t0, sp, 32
    COPY32  t0, a0
    addi    t0, sp, 64
    COPY32  t0, a1
    addi    a0, sp, 8
    ld      a1, 0(sp)
    CALL_GLOBAL crypto_sha256
    UNFRAME 96
END_FUNCTION lantern_e1_hash2

# (data, out): hash_tree_root of a DepositData, from a copy of its bytes (any alignment). s2 the
# copy, s3 out. Locals: L the pubkey's last chunk, L+32 the pubkey's root, then the first half's,
# L+64 the signature's halves and root, then the second half's, L+96 a chunk, L+128 a zero chunk,
# L+160 the copy (184).
FUNCTION lantern_deposit_leaf
    ENTER 352
    mv      s3, a1
    mv      a1, a0
    addi    a0, sp, (L + 160)
    mv      s2, a0
    li      a2, 184
    call    lantern_copy
    ld      t0, 32(s2)                      # pubkey: its two chunks
    sd      t0, L(sp)
    ld      t0, 40(s2)
    sd      t0, (L + 8)(sp)
    sd      zero, (L + 16)(sp)
    sd      zero, (L + 24)(sp)
    mv      a0, s2
    addi    a1, sp, L
    addi    a2, sp, (L + 32)
    call    lantern_e1_hash2
    addi    a0, sp, (L + 32)                # with withdrawal_credentials
    addi    a1, s2, 48
    addi    a2, sp, (L + 32)
    call    lantern_e1_hash2
    addi    a0, s2, 88                      # signature: its four chunks, the last zero
    addi    a1, s2, 120
    addi    a2, sp, (L + 64)
    call    lantern_e1_hash2
    sd      zero, (L + 128)(sp)
    sd      zero, (L + 136)(sp)
    sd      zero, (L + 144)(sp)
    sd      zero, (L + 152)(sp)
    addi    a0, s2, 152
    addi    a1, sp, (L + 128)
    addi    a2, sp, (L + 96)
    call    lantern_e1_hash2
    addi    a0, sp, (L + 64)
    addi    a1, sp, (L + 96)
    addi    a2, sp, (L + 64)
    call    lantern_e1_hash2
    ld      t0, 80(s2)                      # amount, then the signature
    sd      t0, (L + 96)(sp)
    sd      zero, (L + 104)(sp)
    sd      zero, (L + 112)(sp)
    sd      zero, (L + 120)(sp)
    addi    a0, sp, (L + 96)
    addi    a1, sp, (L + 64)
    addi    a2, sp, (L + 64)
    call    lantern_e1_hash2
    addi    a0, sp, (L + 32)                # the two halves
    addi    a1, sp, (L + 64)
    mv      a2, s3
    call    lantern_e1_hash2
    li      a0, LANTERN_OK
    LEAVE 352
END_FUNCTION lantern_deposit_leaf

# (tree, leaf): the deposit contract's deposit. s2 the tree, s3 the size, s4 the height. Locals: L the node (32).
FUNCTION lantern_deposit_tree_push
    ENTER 32
    mv      s2, a0
    ld      t0, DepositTree_count(s2)
    li      t1, 0xffffffff
    bgeu    t0, t1, 8f
    addi    t0, t0, 1
    sd      t0, DepositTree_count(s2)
    mv      s3, t0
    addi    a0, sp, L                       # the leaf, which may have any alignment
    li      a2, 32
    call    lantern_copy
    li      s4, 0
1:  slli    t0, s4, 5
    add     a0, s2, t0
    addi    a0, a0, DepositTree_branch
    andi    t1, s3, 1
    beqz    t1, 2f
    addi    t0, sp, L                       # an odd size: the node is the branch at this height
    COPY32  a0, t0
    j       7f
2:  addi    a1, sp, L
    addi    a2, sp, L
    call    lantern_e1_hash2
    srli    s3, s3, 1
    addi    s4, s4, 1
    li      t0, DEPOSIT_CONTRACT_TREE_DEPTH
    bltu    s4, t0, 1b
7:  li      a0, LANTERN_OK
    LEAVE 32
8:  li      a0, LANTERN_INVALID_OVERFLOW
    LEAVE 32
END_FUNCTION lantern_deposit_tree_push

# (tree, out): get_deposit_root. s2 the tree, s3 out, s4 the size, s7 the height. Locals: L the
# node (32), L+32 the zero hash of the height (32), L+64 the count's 32 bytes.
FUNCTION lantern_deposit_tree_root
    ENTER 96
    mv      s2, a0
    mv      s3, a1
    sd      zero, L(sp)
    sd      zero, (L + 8)(sp)
    sd      zero, (L + 16)(sp)
    sd      zero, (L + 24)(sp)
    sd      zero, (L + 32)(sp)
    sd      zero, (L + 40)(sp)
    sd      zero, (L + 48)(sp)
    sd      zero, (L + 56)(sp)
    ld      s4, DepositTree_count(s2)
    li      s7, 0
1:  slli    t0, s7, 5
    add     a0, s2, t0
    addi    a0, a0, DepositTree_branch
    addi    a1, sp, L
    andi    t1, s4, 1
    bnez    t1, 2f
    addi    a0, sp, L                       # an even size: the node, then the zero hash
    addi    a1, sp, (L + 32)
2:  addi    a2, sp, L
    call    lantern_e1_hash2
    addi    a0, sp, (L + 32)                # the zero hash of the next height
    mv      a1, a0
    mv      a2, a0
    call    lantern_e1_hash2
    srli    s4, s4, 1
    addi    s7, s7, 1
    li      t0, DEPOSIT_CONTRACT_TREE_DEPTH
    bltu    s7, t0, 1b
    ld      t0, DepositTree_count(s2)       # the count, little endian, and 24 zero bytes
    sd      t0, (L + 64)(sp)
    sd      zero, (L + 72)(sp)
    sd      zero, (L + 80)(sp)
    sd      zero, (L + 88)(sp)
    addi    a0, sp, L
    addi    a1, sp, (L + 64)
    mv      a2, s3
    call    lantern_e1_hash2
    li      a0, LANTERN_OK
    LEAVE 96
END_FUNCTION lantern_deposit_tree_root

# (leaves, count, index, scratch, out): the proof of the leaf at index in the tree of the first
# count leaves. s2 the level's nodes, s3 its count, s4 the index at the level, s7 out, s8 the
# height, s9 scratch's nodes, s10 the count. Locals: L the zero hash of the height (32), L+32 a
# node (32), L+64 the next level's index.
FUNCTION lantern_deposit_proof
    ENTER 80
    ld      s10, 0(a1)
    ld      s4, 0(a2)
    mv      s7, a4
    bgeu    s4, s10, 7f
    ld      t0, 8(a0)
    ld      t1, 16(a0)
    srli    t1, t1, 5
    bgtu    s10, t1, 7f
    add     s2, a0, t0
    ld      t0, 0(a3)                       # the next level's nodes from scratch's byte 8
    slli    t1, s10, 4
    addi    t1, t1, 8 + 32
    bltu    t0, t1, 8f
    addi    s9, a3, 8
    mv      s3, s10
    sd      zero, L(sp)
    sd      zero, (L + 8)(sp)
    sd      zero, (L + 16)(sp)
    sd      zero, (L + 24)(sp)
    li      s8, 0
1:  xori    t0, s4, 1                       # the sibling, or the zero hash past the level's count
    slli    t1, s8, 5
    add     a0, s7, t1
    addi    a1, sp, L
    bgeu    t0, s3, 2f
    slli    t0, t0, 5
    add     a1, s2, t0
2:  COPY32  a0, a1
    sd      zero, (L + 64)(sp)              # the next level, in scratch
3:  ld      t0, (L + 64)(sp)
    slli    t0, t0, 1
    bgeu    t0, s3, 5f
    slli    t1, t0, 5
    add     a0, s2, t1
    addi    t0, t0, 1
    addi    a1, sp, L
    bgeu    t0, s3, 4f
    slli    t1, t0, 5
    add     a1, s2, t1
4:  addi    a2, sp, (L + 32)
    call    lantern_e1_hash2
    ld      t0, (L + 64)(sp)
    slli    t1, t0, 5
    add     a0, s9, t1
    addi    a1, sp, (L + 32)
    COPY32  a0, a1
    addi    t0, t0, 1
    sd      t0, (L + 64)(sp)
    j       3b
5:  mv      s2, s9
    ld      s3, (L + 64)(sp)
    srli    s4, s4, 1
    addi    a0, sp, L                       # the zero hash of the next height
    mv      a1, a0
    mv      a2, a0
    call    lantern_e1_hash2
    addi    s8, s8, 1
    li      t0, DEPOSIT_CONTRACT_TREE_DEPTH
    bltu    s8, t0, 1b
    li      t0, 32 * DEPOSIT_CONTRACT_TREE_DEPTH    # then the count as 32 little endian bytes
    add     t0, s7, t0
    sd      s10, 0(t0)
    sd      zero, 8(t0)
    sd      zero, 16(t0)
    sd      zero, 24(t0)
    li      a0, LANTERN_OK
    LEAVE 80
7:  li      a0, LANTERN_INVALID_INDEX
    LEAVE 80
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
END_FUNCTION lantern_deposit_proof
