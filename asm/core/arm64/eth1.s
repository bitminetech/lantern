/*
 * The eth1 follower's functions, ARM64: in the common object. Requirements: docs/reference/eth1.md.
 *
 * The parsers use the JSON helpers of jsonrpc.s, which read the end of the text from x19.
 */

    RODATA
.include "eth1_text.inc"
e1_digits:
    .ascii  "0123456789abcdef"

/* The QUANTITY of x0 to the cursor x1: "0x", then hex digits with no leading zero; x1 = the end. Uses x9-x12. */
LOCAL_FUNCTION lantern_e1_qty
    UNWIND_END_PROLOGUE
    mov     w9, #'0'
    strb    w9, [x1], #1
    mov     w9, #'x'
    strb    w9, [x1], #1
    mov     x9, #60                         /* the highest nibble that is not zero, or the last */
1:  cbz     x9, 2f
    lsr     x10, x0, x9
    and     x10, x10, #15
    cbnz    x10, 2f
    sub     x9, x9, #4
    b       1b
2:  ADDRESS x11, e1_digits
3:  lsr     x10, x0, x9
    and     x10, x10, #15
    ldrb    w12, [x11, x10]
    strb    w12, [x1], #1
    cbz     x9, 4f
    sub     x9, x9, #4
    b       3b
4:  ret
END_FUNCTION lantern_e1_qty

/* The x2 bytes at x0 as lowercase hex to the cursor x1; x1 = the end. Uses x9-x12. */
LOCAL_FUNCTION lantern_e1_hex
    UNWIND_END_PROLOGUE
    ADDRESS x11, e1_digits
1:  cbz     x2, 2f
    ldrb    w9, [x0], #1
    lsr     w10, w9, #4
    ldrb    w12, [x11, x10]
    strb    w12, [x1], #1
    and     w10, w9, #15
    ldrb    w12, [x11, x10]
    strb    w12, [x1], #1
    sub     x2, x2, #1
    b       1b
2:  ret
END_FUNCTION lantern_e1_hex

/* The ByteList x0 holds the bytes from its byte 24 to the cursor x1: its offset 24 and its length. Uses x9, x10. */
LOCAL_FUNCTION lantern_e1_close
    UNWIND_END_PROLOGUE
    add     x9, x0, #24
    sub     x9, x1, x9
    mov     x10, #24
    stp     x10, x9, [x0, #8]
    ret
END_FUNCTION lantern_e1_close

/* (number, id, out): eth_getBlockByNumber. x19 number, x20 id, x21 out. */
FUNCTION lantern_eth_get_block_by_number
    ENTER 0
    ldr     x19, [x0]
    ldr     x20, [x1]
    mov     x21, x2
    ldr     x9, [x21]
    cmp     x9, #(24 + 128)
    b.lo    8f
    ADDRESS x0, e1_open
    mov     x1, #e1_open_len
    add     x2, x21, #24
    bl      lantern_put_bytes
    mov     x0, x20
    mov     x1, x2
    bl      lantern_decimal
    mov     x2, x1
    ADDRESS x0, e1_block
    mov     x1, #e1_block_len
    bl      lantern_put_bytes
    cmn     x19, #1                         /* 2^64 - 1: latest */
    b.ne    1f
    ADDRESS x0, e1_latest
    mov     x1, #e1_latest_len
    bl      lantern_put_bytes
    b       2f
1:  mov     x0, x19
    mov     x1, x2
    bl      lantern_e1_qty
    mov     x2, x1
2:  ADDRESS x0, e1_bclose
    mov     x1, #e1_bclose_len
    bl      lantern_put_bytes
    mov     x0, x21
    mov     x1, x2
    bl      lantern_e1_close
    mov     x0, #LANTERN_OK
    LEAVE 0
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_eth_get_block_by_number

/* (address, from, to, id, out): eth_getLogs of the DepositEvent logs. x19 address, x20 from, x21 to, x22 id, x23 out. */
FUNCTION lantern_eth_get_deposit_logs
    ENTER 0
    mov     x19, x0
    ldr     x20, [x1]
    ldr     x21, [x2]
    ldr     x22, [x3]
    mov     x23, x4
    ldr     x9, [x23]
    cmp     x9, #(24 + 384)
    b.lo    8f
    ADDRESS x0, e1_open
    mov     x1, #e1_open_len
    add     x2, x23, #24
    bl      lantern_put_bytes
    mov     x0, x22
    mov     x1, x2
    bl      lantern_decimal
    mov     x2, x1
    ADDRESS x0, e1_logs
    mov     x1, #e1_logs_len
    bl      lantern_put_bytes
    mov     x1, x2
    mov     x0, x19
    mov     x2, #20
    bl      lantern_e1_hex
    mov     x2, x1
    ADDRESS x0, e1_topics
    mov     x1, #e1_topics_len
    bl      lantern_put_bytes
    mov     x0, x20
    mov     x1, x2
    bl      lantern_e1_qty
    mov     x2, x1
    ADDRESS x0, e1_to
    mov     x1, #e1_to_len
    bl      lantern_put_bytes
    mov     x0, x21
    mov     x1, x2
    bl      lantern_e1_qty
    mov     x2, x1
    ADDRESS x0, e1_lclose
    mov     x1, #e1_lclose_len
    bl      lantern_put_bytes
    mov     x0, x23
    mov     x1, x2
    bl      lantern_e1_close
    mov     x0, #LANTERN_OK
    LEAVE 0
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_eth_get_deposit_logs

/*
 * A QUANTITY string at the cursor x0: x0 = the cursor after it and x1 its value, or x0 = 0 for
 * none: "0x", then 1 to 16 hex digits with no leading zero. Uses x1-x3, x9-x11.
 */
LOCAL_FUNCTION lantern_e1_qty_in
    FRAME 16
    bl      lantern_jstring
    cbz     x0, 9f
    cbnz    x3, 9f
    cmp     x2, #3
    b.lo    9f
    cmp     x2, #18
    b.hi    9f
    ldrb    w9, [x1]
    cmp     w9, #'0'
    b.ne    9f
    ldrb    w9, [x1, #1]
    cmp     w9, #'x'
    b.ne    9f
    add     x1, x1, #2
    sub     x2, x2, #2
    ldrb    w9, [x1]                        /* no leading zero, but 0x0 */
    cmp     w9, #'0'
    b.ne    1f
    cmp     x2, #1
    b.ne    9f
1:  mov     x10, #0
2:  ldrb    w9, [x1], #1
    sub     w11, w9, #'0'
    cmp     w11, #10
    b.lo    3f
    orr     w9, w9, #0x20
    sub     w11, w9, #'a'
    cmp     w11, #6
    b.hs    9f
    add     w11, w11, #10
3:  orr     x10, x11, x10, lsl #4
    subs    x2, x2, #1
    b.ne    2b
    mov     x1, x10
    UNFRAME 16
9:  mov     x0, #0
    UNFRAME 16
END_FUNCTION lantern_e1_qty_in

/*
 * (json, out): the number, hash and timestamp of an eth_getBlockByNumber result. x19 the text's
 * end, x20 out, x21 the members read: 1 number, 2 hash, 4 timestamp.
 */
FUNCTION lantern_eth1_block
    ENTER 0
    mov     x20, x1
    stp     xzr, xzr, [x20]
    stp     xzr, xzr, [x20, #16]
    stp     xzr, xzr, [x20, #32]
    stp     xzr, xzr, [x20, #48]
    stp     xzr, xzr, [x20, #64]
    str     xzr, [x20, #80]
    ldp     x9, x10, [x0, #8]
    add     x0, x0, x9
    add     x19, x0, x10
    mov     x21, #0
    bl      lantern_jws
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0], #1
    cmp     w9, #'{'
    b.ne    9f
    mov     x1, #1
1:  bl      lantern_jmember
    cbz     x0, 9f
    cbnz    x3, 7f
    JIS     e1_n_number
    cbz     x9, 2f
    bl      lantern_e1_qty_in
    cbz     x0, 9f
    str     x1, [x20, #Eth1Block_number]
    orr     x21, x21, #1
    b       6f
2:  JIS     e1_n_timestamp
    cbz     x9, 3f
    bl      lantern_e1_qty_in
    cbz     x0, 9f
    str     x1, [x20, #Eth1Block_timestamp]
    orr     x21, x21, #4
    b       6f
3:  JIS     e1_n_hash
    cbz     x9, 4f
    mov     x1, #0
    mov     x2, #32
    add     x3, x20, #Eth1Block_hash
    bl      lantern_jdata_in
    cbz     x0, 9f
    orr     x21, x21, #2
    b       6f
4:  bl      lantern_jskip
    cbz     x0, 9f
6:  mov     x1, #0
    b       1b
7:  bl      lantern_jws                             /* nothing after the object, and each of the three */
    cmp     x0, x19
    b.ne    9f
    cmp     x21, #7
    b.ne    9f
    mov     x0, #LANTERN_OK
    LEAVE 0
9:  stp     xzr, xzr, [x20]
    stp     xzr, xzr, [x20, #16]
    stp     xzr, xzr, [x20, #32]
    stp     xzr, xzr, [x20, #48]
    mov     x0, #LANTERN_INVALID_JSON
    LEAVE 0
END_FUNCTION lantern_eth1_block

/*
 * (json, out): the deposits of an eth_getLogs result. x19 the text's end, x20 out, x23 the next
 * entry, x24 the entries' end, x25 the members read (1 blockNumber, 2 topics, 4 data, 8 removed
 * true, 16 data of another length), x26 blockNumber. Below the saved registers, at sp: the topic
 * (32), then the data (576).
 */
FUNCTION lantern_eth1_deposit_logs
    ENTER_OUT 0, 608
    mov     x20, x1
    ldp     x9, x10, [x0, #8]
    add     x0, x0, x9
    add     x19, x0, x10
    ldr     x9, [x20]
    add     x24, x20, x9
    add     x23, x20, #24
    mov     x9, #24
    stp     x9, xzr, [x20, #8]
    bl      lantern_jws
    cmp     x0, x19
    b.hs    90f
    ldrb    w9, [x0], #1
    cmp     w9, #'['
    b.ne    90f
    bl      lantern_jws
    cmp     x0, x19
    b.hs    90f
    ldrb    w9, [x0]
    cmp     w9, #']'
    b.ne    1f
    add     x0, x0, #1
    b       80f
1:  cmp     x0, x19                         /* a log */
    b.hs    90f
    ldrb    w9, [x0], #1
    cmp     w9, #'{'
    b.ne    90f
    mov     x25, #0
    mov     x1, #1
2:  bl      lantern_jmember
    cbz     x0, 90f
    cbnz    x3, 40f
    JIS     e1_n_block_number
    cbz     x9, 3f
    bl      lantern_e1_qty_in
    cbz     x0, 90f
    mov     x26, x1
    orr     x25, x25, #1
    b       30f
3:  JIS     e1_n_removed
    cbz     x9, 4f
    bic     x25, x25, #8
    ADDRESS x1, json_false
    mov     x2, #json_false_len
    mov     x27, x0
    bl      lantern_jliteral
    cbnz    x0, 30f
    mov     x0, x27
    ADDRESS x1, json_true
    mov     x2, #json_true_len
    bl      lantern_jliteral
    cbz     x0, 90f
    orr     x25, x25, #8
    b       30f
4:  JIS     e1_n_topics
    cbz     x9, 5f
    cmp     x0, x19                         /* an array: its first item the DepositEvent topic */
    b.hs    90f
    ldrb    w9, [x0], #1
    cmp     w9, #'['
    b.ne    90f
    bl      lantern_jws
    mov     x1, #0
    mov     x2, #32
    add     x3, sp, #0
    bl      lantern_jdata_in
    cbz     x0, 90f
    add     x9, sp, #0
    ADDRESS x15, e1_topic
    NE32    x9, x15, 90f
41: bl      lantern_jws
    cmp     x0, x19
    b.hs    90f
    ldrb    w9, [x0], #1
    cmp     w9, #']'
    b.eq    42f
    cmp     w9, #','
    b.ne    90f
    bl      lantern_jws
    bl      lantern_jskip
    cbz     x0, 90f
    b       41b
42: orr     x25, x25, #2
    b       30f
5:  JIS     e1_n_data
    cbz     x9, 6f
    bl      lantern_jstring                         /* "0x", then 2 hex digits a byte; 576 bytes, else no deposit's */
    cbz     x0, 90f
    cbnz    x3, 90f
    cmp     x2, #2
    b.lo    90f
    tst     x2, #1
    b.ne    90f
    ldrh    w9, [x1]
    mov     w10, #0x7830                    /* "0x" */
    cmp     w9, w10
    b.ne    90f
    bic     x25, x25, #16
    sub     x2, x2, #2
    add     x1, x1, #2
    cmp     x2, #1152
    b.eq    51f
    orr     x25, x25, #16
    mov     x3, #0                          /* only the digits checked */
    b       52f
51: add     x3, sp, #32
52: cbz     x2, 55f
    mov     x13, #0
    mov     x12, #2
53: ldrb    w9, [x1], #1
    sub     w10, w9, #'0'
    cmp     w10, #10
    b.lo    54f
    orr     w9, w9, #0x20
    sub     w10, w9, #'a'
    cmp     w10, #6
    b.hs    90f
    add     w10, w10, #10
54: orr     x13, x10, x13, lsl #4
    sub     x2, x2, #1
    subs    x12, x12, #1
    b.ne    53b
    cbz     x3, 52b
    strb    w13, [x3], #1
    b       52b
55: orr     x25, x25, #4
    b       30f
6:  bl      lantern_jskip
    cbz     x0, 90f
30: mov     x1, #0
    b       2b
40: and     x9, x25, #7                     /* the log's end: blockNumber, topics and data */
    cmp     x9, #7
    b.ne    90f
    tbnz    x25, #3, 70f                    /* removed: no deposit */
    tbnz    x25, #4, 91f
    mov     x27, x0
    add     x0, sp, #32               /* the contract's encoding: the bytes of e1_abi but the values */
    bl      lantern_e1_abi_check
    cbz     x0, 91f
    add     x9, x23, #Eth1Deposit__mem
    cmp     x9, x24
    b.hi    92f
    str     x26, [x23, #Eth1Deposit_block_number]
    add     x10, sp, #32
    ldr     x9, [x10, #544]                 /* index */
    str     x9, [x23, #Eth1Deposit_index]
    add     x0, x23, #Eth1Deposit_data      /* pubkey */
    add     x1, x10, #192
    mov     x2, #48
    bl      lantern_copy
    add     x0, x23, #(Eth1Deposit_data + 48)   /* withdrawal_credentials */
    add     x10, sp, #32
    add     x1, x10, #288
    mov     x2, #32
    bl      lantern_copy
    add     x10, sp, #32
    ldr     x9, [x10, #352]                 /* amount */
    str     x9, [x23, #(Eth1Deposit_data + 80)]
    add     x0, x23, #(Eth1Deposit_data + 88)   /* signature */
    add     x1, x10, #416
    mov     x2, #96
    bl      lantern_copy
    add     x23, x23, #Eth1Deposit__mem
    mov     x0, x27
70: bl      lantern_jws                             /* a comma and the next log, or the array's end */
    cmp     x0, x19
    b.hs    90f
    ldrb    w9, [x0], #1
    cmp     w9, #','
    b.ne    71f
    bl      lantern_jws
    b       1b
71: cmp     w9, #']'
    b.ne    90f
80: bl      lantern_jws                             /* nothing after the array */
    cmp     x0, x19
    b.ne    90f
    add     x9, x20, #24
    sub     x9, x23, x9
    str     x9, [x20, #16]
    mov     x0, #LANTERN_OK
    LEAVE_OUT 0, 608
90: mov     x0, #LANTERN_INVALID_JSON
    LEAVE_OUT 0, 608
91: mov     x0, #LANTERN_INVALID_DEPOSIT_LOG
    LEAVE_OUT 0, 608
92: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE_OUT 0, 608
END_FUNCTION lantern_eth1_deposit_logs

/*
 * x0 = 1 when the 576 bytes at x0 are e1_abi but in the values (pubkey 192, withdrawal
 * credentials 288, amount 352, signature 416, index 544), else 0. Uses x9-x13.
 */
LOCAL_FUNCTION lantern_e1_abi_check
    UNWIND_END_PROLOGUE
    ADDRESS x10, e1_abi
    mov     x11, #0
1:  cmp     x11, #576
    b.hs    8f
    cmp     x11, #192                       /* the value ranges are skipped */
    b.lo    3f
    cmp     x11, #240
    b.lo    2f
    cmp     x11, #288
    b.lo    3f
    cmp     x11, #320
    b.lo    2f
    cmp     x11, #352
    b.lo    3f
    cmp     x11, #360
    b.lo    2f
    cmp     x11, #416
    b.lo    3f
    cmp     x11, #512
    b.lo    2f
    cmp     x11, #544
    b.lo    3f
    cmp     x11, #552
    b.lo    2f
3:  ldrb    w12, [x0, x11]
    ldrb    w13, [x10, x11]
    cmp     w12, w13
    b.ne    9f
2:  add     x11, x11, #1
    b       1b
8:  mov     x0, #1
    ret
9:  mov     x0, #0
    ret
END_FUNCTION lantern_e1_abi_check

/* SHA-256 of the 32 bytes at x0 and the 32 bytes at x1, to x2. Locals: a ByteList of 64 bytes. */
LOCAL_FUNCTION lantern_e1_hash2
    FRAME 96
    str     x2, [sp, #16]
    add     x9, sp, #24
    mov     x10, #88
    mov     x11, #24
    stp     x10, x11, [x9]
    mov     x10, #64
    str     x10, [x9, #16]
    add     x9, sp, #48
    COPY32  x9, x0
    add     x9, sp, #80
    COPY32  x9, x1
    add     x0, sp, #24
    ldr     x1, [sp, #16]
    CALL_GLOBAL crypto_sha256
    UNFRAME 96
END_FUNCTION lantern_e1_hash2

/*
 * (data, out): hash_tree_root of a DepositData. x19 data, x20 out. Locals: L the pubkey's last
 * chunk, L+32 the pubkey's root, then the first half's, L+64 the signature's halves and root, then
 * the second half's, L+96 a chunk, L+128 a zero chunk.
 */
FUNCTION lantern_deposit_leaf
    ENTER 160
    mov     x19, x0
    mov     x20, x1
    add     x9, sp, #L                      /* pubkey: its two chunks */
    ldp     x10, x11, [x19, #32]
    stp     x10, x11, [x9]
    stp     xzr, xzr, [x9, #16]
    mov     x0, x19
    add     x1, sp, #L
    add     x2, sp, #(L + 32)
    bl      lantern_e1_hash2
    add     x0, sp, #(L + 32)               /* with withdrawal_credentials */
    add     x1, x19, #48
    add     x2, sp, #(L + 32)
    bl      lantern_e1_hash2
    add     x0, x19, #88                    /* signature: its four chunks, the last zero */
    add     x1, x19, #120
    add     x2, sp, #(L + 64)
    bl      lantern_e1_hash2
    add     x9, sp, #(L + 128)
    stp     xzr, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    add     x0, x19, #152
    add     x1, sp, #(L + 128)
    add     x2, sp, #(L + 96)
    bl      lantern_e1_hash2
    add     x0, sp, #(L + 64)
    add     x1, sp, #(L + 96)
    add     x2, sp, #(L + 64)
    bl      lantern_e1_hash2
    add     x9, sp, #(L + 96)               /* amount, then the signature */
    ldr     x10, [x19, #80]
    stp     x10, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    add     x0, sp, #(L + 96)
    add     x1, sp, #(L + 64)
    add     x2, sp, #(L + 64)
    bl      lantern_e1_hash2
    add     x0, sp, #(L + 32)               /* the two halves */
    add     x1, sp, #(L + 64)
    mov     x2, x20
    bl      lantern_e1_hash2
    mov     x0, #LANTERN_OK
    LEAVE 160
END_FUNCTION lantern_deposit_leaf

/* (tree, leaf): the deposit contract's deposit: x19 the tree, x20 the node, x21 the size, x22 the height. Locals: L the node (32). */
FUNCTION lantern_deposit_tree_push
    ENTER 32
    mov     x19, x0
    ldr     x9, [x19, #DepositTree_count]
    mov     x10, #0xffffffff
    cmp     x9, x10
    b.hs    8f
    add     x9, x9, #1
    str     x9, [x19, #DepositTree_count]
    mov     x21, x9
    add     x20, sp, #L
    COPY32  x20, x1
    mov     x22, #0
1:  add     x9, x19, #DepositTree_branch
    add     x9, x9, x22, lsl #5
    tbz     x21, #0, 2f
    COPY32  x9, x20                         /* an odd size: the node is the branch at this height */
    b       7f
2:  mov     x0, x9
    mov     x1, x20
    mov     x2, x20
    bl      lantern_e1_hash2
    lsr     x21, x21, #1
    add     x22, x22, #1
    cmp     x22, #DEPOSIT_CONTRACT_TREE_DEPTH
    b.lo    1b
7:  mov     x0, #LANTERN_OK
    LEAVE 32
8:  mov     x0, #LANTERN_INVALID_OVERFLOW
    LEAVE 32
END_FUNCTION lantern_deposit_tree_push

/*
 * (tree, out): get_deposit_root. x19 the tree, x20 out, x21 the size, x22 the height. Locals: L
 * the node (32), L+32 the zero hash of the height (32), L+64 the count's 32 bytes.
 */
FUNCTION lantern_deposit_tree_root
    ENTER 96
    mov     x19, x0
    mov     x20, x1
    add     x9, sp, #L
    stp     xzr, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    stp     xzr, xzr, [x9, #32]
    stp     xzr, xzr, [x9, #48]
    ldr     x21, [x19, #DepositTree_count]
    mov     x22, #0
1:  add     x9, x19, #DepositTree_branch
    add     x0, x9, x22, lsl #5
    add     x1, sp, #L
    tbnz    x21, #0, 2f
    add     x0, sp, #L                      /* an even size: the node, then the zero hash */
    add     x1, sp, #(L + 32)
2:  add     x2, sp, #L
    bl      lantern_e1_hash2
    add     x0, sp, #(L + 32)               /* the zero hash of the next height */
    mov     x1, x0
    mov     x2, x0
    bl      lantern_e1_hash2
    lsr     x21, x21, #1
    add     x22, x22, #1
    cmp     x22, #DEPOSIT_CONTRACT_TREE_DEPTH
    b.lo    1b
    add     x9, sp, #(L + 64)               /* the count, little endian, and 24 zero bytes */
    ldr     x10, [x19, #DepositTree_count]
    stp     x10, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    add     x0, sp, #L
    add     x1, sp, #(L + 64)
    mov     x2, x20
    bl      lantern_e1_hash2
    mov     x0, #LANTERN_OK
    LEAVE 96
END_FUNCTION lantern_deposit_tree_root

/*
 * (leaves, count, index, scratch, out): the proof of the leaf at index in the tree of the first
 * count leaves. x19 the level's nodes, x20 its count, x21 the index at the level, x22 out, x23 the
 * height, x24 scratch's nodes, x25 the count. Locals: L the zero hash of the height (32), L+32 a
 * node (32).
 */
FUNCTION lantern_deposit_proof
    ENTER 64
    ldr     x25, [x1]
    ldr     x21, [x2]
    mov     x22, x4
    cmp     x21, x25
    b.hs    7f
    ldp     x9, x10, [x0, #8]
    lsr     x11, x10, #5
    cmp     x25, x11
    b.hi    7f
    add     x19, x0, x9
    ldr     x9, [x3]                        /* the next level's nodes from scratch's byte 8 */
    lsl     x10, x25, #4
    add     x10, x10, #(8 + 32)
    cmp     x9, x10
    b.lo    8f
    add     x24, x3, #8
    mov     x20, x25
    add     x9, sp, #L
    stp     xzr, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    mov     x23, #0
1:  eor     x9, x21, #1                     /* the sibling, or the zero hash past the level's count */
    add     x0, x22, x23, lsl #5
    add     x1, x19, x9, lsl #5
    cmp     x9, x20
    b.lo    2f
    add     x1, sp, #L
2:  COPY32  x0, x1
    mov     x26, #0                         /* the next level, in scratch */
3:  lsl     x9, x26, #1
    cmp     x9, x20
    b.hs    5f
    add     x0, x19, x9, lsl #5
    add     x9, x9, #1
    add     x1, x19, x9, lsl #5
    cmp     x9, x20
    b.lo    4f
    add     x1, sp, #L
4:  add     x2, sp, #(L + 32)
    bl      lantern_e1_hash2
    add     x0, x24, x26, lsl #5
    add     x1, sp, #(L + 32)
    COPY32  x0, x1
    add     x26, x26, #1
    b       3b
5:  mov     x19, x24
    mov     x20, x26
    lsr     x21, x21, #1
    add     x0, sp, #L                      /* the zero hash of the next height */
    mov     x1, x0
    mov     x2, x0
    bl      lantern_e1_hash2
    add     x23, x23, #1
    cmp     x23, #DEPOSIT_CONTRACT_TREE_DEPTH
    b.lo    1b
    add     x9, x22, #(32 * DEPOSIT_CONTRACT_TREE_DEPTH)  /* then the count as 32 little endian bytes */
    stp     x25, xzr, [x9]
    stp     xzr, xzr, [x9, #16]
    mov     x0, #LANTERN_OK
    LEAVE 64
7:  mov     x0, #LANTERN_INVALID_INDEX
    LEAVE 64
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_deposit_proof
