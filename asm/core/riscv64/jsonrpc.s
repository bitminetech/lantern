/*
 * The JSON-RPC response parser of the Engine API client, RISC-V: in the common object.
 * Requirements: docs/reference/engine-api.md.
 *
 * The local functions read the end of the body from s1, the EngineResponse from s2 and the
 * method from s3, which lantern_engine_parse_response sets. The cursor is in a0; a cursor
 * of 0 means the JSON is not valid.
 */

/* The names and strings the parser reads, before the code that takes their lengths. */
    RODATA
.include "jsonrpc_names.inc"

/* L0: a0 = the cursor a0 after any whitespace. Uses t0, t1. */
LOCAL_FUNCTION lantern_jws
    UNWIND_END_PROLOGUE
1:  bgeu    a0, s1, 2f
    lbu     t0, 0(a0)
    li      t1, ' '
    beq     t0, t1, 3f
    li      t1, 9
    beq     t0, t1, 3f
    li      t1, 10
    beq     t0, t1, 3f
    li      t1, 13
    bne     t0, t1, 2f
3:  addi    a0, a0, 1
    j       1b
2:  ret
END_FUNCTION lantern_jws

/*
 * L0: a string at the cursor a0, its quote included: a0 = the cursor after it, a1 = where its
 * bytes start, a2 = their count, a3 = 1 when it has an escape. Uses t0-t3.
 */
LOCAL_FUNCTION lantern_jstring
    UNWIND_END_PROLOGUE
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    li      t1, '"'
    bne     t0, t1, 9f
    addi    a0, a0, 1
    mv      a1, a0
    li      a3, 0
1:  bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    addi    a0, a0, 1
    li      t1, '"'
    beq     t0, t1, 8f
    li      t1, 0x20                        # no control character
    bltu    t0, t1, 9f
    li      t1, '\\'
    bne     t0, t1, 1b
    li      a3, 1                           # an escape
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    addi    a0, a0, 1
    li      t1, 'u'
    beq     t0, t1, 2f
    ADDRESS t2, json_escapes
    li      t3, 8
3:  lbu     t1, 0(t2)
    beq     t0, t1, 1b
    addi    t2, t2, 1
    addi    t3, t3, -1
    bnez    t3, 3b
    j       9f
2:  li      t3, 4                           # \uXXXX
4:  bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    addi    a0, a0, 1
    addi    t1, t0, -'0'
    li      t2, 10
    bltu    t1, t2, 5f
    ori     t0, t0, 0x20
    addi    t1, t0, -'a'
    li      t2, 6
    bgeu    t1, t2, 9f
5:  addi    t3, t3, -1
    bnez    t3, 4b
    j       1b
8:  sub     a2, a0, a1
    addi    a2, a2, -1
    ret
9:  li      a0, 0
    ret
END_FUNCTION lantern_jstring

/* The digit at a0 below the end: t0 = its value, branch to label when there is none. Uses t1. */
.macro JDIGIT none
    bgeu    a0, s1, \none
    lbu     t0, 0(a0)
    addi    t0, t0, -'0'
    li      t1, 10
    bgeu    t0, t1, \none
.endm

/* L0: a number at the cursor a0, as RFC 8259 writes it: a0 = the cursor after it, a1 = 1 when it is digits only. Uses t0-t2. */
LOCAL_FUNCTION lantern_jnumber
    UNWIND_END_PROLOGUE
    li      a1, 1
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    li      t1, '-'
    bne     t0, t1, 1f
    addi    a0, a0, 1
1:  bgeu    a0, s1, 9f                      # 0, or a digit 1 to 9 and digits
    lbu     t0, 0(a0)
    addi    a0, a0, 1
    li      t1, '0'
    beq     t0, t1, 3f
    addi    t0, t0, -'1'
    li      t1, 9
    bgeu    t0, t1, 9f
2:  JDIGIT  3f
    addi    a0, a0, 1
    j       2b
3:  bgeu    a0, s1, 7f                      # a fraction
    lbu     t0, 0(a0)
    li      t1, '.'
    bne     t0, t1, 5f
    li      a1, 0
    addi    a0, a0, 1
    li      t2, 0
4:  JDIGIT  6f
    addi    a0, a0, 1
    addi    t2, t2, 1
    j       4b
6:  beqz    t2, 9f
5:  bgeu    a0, s1, 7f                      # an exponent
    lbu     t0, 0(a0)
    ori     t0, t0, 0x20
    li      t1, 'e'
    bne     t0, t1, 7f
    li      a1, 0
    addi    a0, a0, 1
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    li      t1, '+'
    beq     t0, t1, 10f
    li      t1, '-'
    bne     t0, t1, 11f
10: addi    a0, a0, 1
11: li      t2, 0
12: JDIGIT  13f
    addi    a0, a0, 1
    addi    t2, t2, 1
    j       12b
13: beqz    t2, 9f
7:  ret
9:  li      a0, 0
    ret
END_FUNCTION lantern_jnumber

/* Whether the a2 bytes at a1 are the literal label: t0 = 1 or 0. Uses t1-t4. */
.macro JIS label
    li      t0, 0
    li      t1, \label\()_len
    bne     a2, t1, 93f
    ADDRESS t1, \label
    li      t2, 0
91: add     t3, a1, t2
    lbu     t3, 0(t3)
    add     t4, t1, t2
    lbu     t4, 0(t4)
    bne     t3, t4, 93f
    addi    t2, t2, 1
    bltu    t2, a2, 91b
    li      t0, 1
93:
.endm

/* L0: the literal at the cursor a0 of the a2 bytes at a1: a0 = the cursor after it, or 0. Uses t0-t2. */
LOCAL_FUNCTION lantern_jliteral
    UNWIND_END_PROLOGUE
    sub     t0, s1, a0
    bltu    t0, a2, 9f
    li      t0, 0
1:  add     t1, a0, t0
    lbu     t1, 0(t1)
    add     t2, a1, t0
    lbu     t2, 0(t2)
    bne     t1, t2, 9f
    addi    t0, t0, 1
    bltu    t0, a2, 1b
    add     a0, a0, a2
    ret
9:  li      a0, 0
    ret
END_FUNCTION lantern_jliteral

/*
 * L0: any value at the cursor a0, as RFC 8259 writes it: a0 = the cursor after it. Brackets nest
 * to 64 levels, their kinds in s4 (1 for an object), the depth in s5; t5 what comes next: 0 a
 * value, 1 a value or the array's end, 2 a name, 3 a name or the object's end. Uses a1-a3, t0-t5.
 */
LOCAL_FUNCTION lantern_jskip
    FRAME 16
    sd      s4, F + 0(sp)
    sd      s5, F + 8(sp)
    li      s4, 0
    li      s5, 0
    li      t5, 0
1:  call    lantern_jws
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    li      t1, 2
    bltu    t5, t1, 30f
    li      t1, '}'                         # a name and a colon, or the end of an empty object
    bne     t0, t1, 31f
    li      t1, 3
    beq     t5, t1, 5f
    j       9f
31: li      t1, '"'
    bne     t0, t1, 9f
    call    lantern_jstring
    beqz    a0, 9f
    call    lantern_jws
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    li      t1, ':'
    bne     t0, t1, 9f
    addi    a0, a0, 1
    li      t5, 0
    j       1b
30: li      t1, ']'                         # a value, or the end of an empty array
    bne     t0, t1, 32f
    li      t1, 1
    beq     t5, t1, 5f
    j       9f
32: li      t1, '"'
    bne     t0, t1, 2f
    call    lantern_jstring
    beqz    a0, 9f
    j       6f
2:  li      t1, '{'
    beq     t0, t1, 3f
    li      t1, '['
    bne     t0, t1, 7f
3:  li      t2, 64
    bgeu    s5, t2, 9f
    slli    s4, s4, 1
    li      t5, 1
    li      t1, '{'
    bne     t0, t1, 14f
    ori     s4, s4, 1
    li      t5, 3
14: addi    s5, s5, 1
    addi    a0, a0, 1
    j       1b
5:  srli    s4, s4, 1                       # the end of the container
    addi    s5, s5, -1
    addi    a0, a0, 1
6:  beqz    s5, 8f                          # a whole value at depth 0
    call    lantern_jws                             # in a container: a comma, or the end of its kind
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    andi    t4, s4, 1
    li      t1, ','
    bne     t0, t1, 33f
    addi    a0, a0, 1
    slli    t5, t4, 1
    j       1b
33: li      t1, ']'
    beqz    t4, 34f
    li      t1, '}'
34: beq     t0, t1, 5b
    j       9f
7:  li      t1, 't'                         # true, false, null, or a number
    bne     t0, t1, 11f
    ADDRESS a1, json_true
    li      a2, 4
    call    lantern_jliteral
    beqz    a0, 9f
    j       6b
11: li      t1, 'f'
    bne     t0, t1, 12f
    ADDRESS a1, json_false
    li      a2, 5
    call    lantern_jliteral
    beqz    a0, 9f
    j       6b
12: li      t1, 'n'
    bne     t0, t1, 13f
    ADDRESS a1, json_null
    li      a2, 4
    call    lantern_jliteral
    beqz    a0, 9f
    j       6b
13: call    lantern_jnumber
    beqz    a0, 9f
    j       6b
9:  li      a0, 0
8:  ld      s4, F + 0(sp)
    ld      s5, F + 8(sp)
    UNFRAME 16
END_FUNCTION lantern_jskip

/*
 * L0: the next member of an object, from the cursor a0 after its brace (a1 = 1) or after a
 * value (a1 = 0): a3 = 1 at the closing brace, a0 after it; else a0 = its value after
 * whitespace, a1 = where its name's bytes start, a2 = their count, 2^64 - 1 for a name with
 * an escape. a0 = 0 when the JSON is not valid. Uses t0-t3, t5.
 */
LOCAL_FUNCTION lantern_jmember
    FRAME 16
    mv      t5, a1
    sd      t5, F(sp)
    call    lantern_jws
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    li      t1, '}'
    bne     t0, t1, 1f
    addi    a0, a0, 1                       # the end: after the brace or a value, not after a comma
    li      a3, 1
    UNFRAME 16
1:  ld      t5, F(sp)
    bnez    t5, 2f
    li      t1, ','
    bne     t0, t1, 9f
    addi    a0, a0, 1
    call    lantern_jws
2:  call    lantern_jstring
    beqz    a0, 9f
    beqz    a3, 3f
    li      a2, -1
3:  call    lantern_jws
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    li      t1, ':'
    bne     t0, t1, 9f
    addi    a0, a0, 1
    call    lantern_jws
    li      a3, 0
    UNFRAME 16
9:  li      a0, 0
    UNFRAME 16
END_FUNCTION lantern_jmember

/*
 * L0: DATA of a2 bytes at the cursor a0, or null when a1 = 1 allows it, to a3:
 * a0 = the cursor after it, a1 = 1 when it is not null. Uses t0-t6, a4, a5.
 */
LOCAL_FUNCTION lantern_jdata_in
    FRAME 16
    mv      a4, a2
    mv      a5, a3
    sd      a4, F + 0(sp)
    sd      a5, F + 8(sp)
    beqz    a1, 1f
    bgeu    a0, s1, 1f
    lbu     t0, 0(a0)
    li      t1, 'n'
    bne     t0, t1, 1f
    ADDRESS a1, json_null
    li      a2, 4
    call    lantern_jliteral
    li      a1, 0
    UNFRAME 16
1:  call    lantern_jstring
    beqz    a0, 9f
    bnez    a3, 9f                          # "0x", then 2 hex digits a byte
    ld      a4, F + 0(sp)
    ld      a5, F + 8(sp)
    addi    t0, a4, 1
    slli    t0, t0, 1
    bne     a2, t0, 9f
    lbu     t0, 0(a1)
    li      t1, '0'
    bne     t0, t1, 9f
    lbu     t0, 1(a1)
    li      t1, 'x'
    bne     t0, t1, 9f
    addi    a1, a1, 2
2:  beqz    a4, 5f
    li      t6, 0
    li      t3, 2
3:  lbu     t0, 0(a1)
    addi    a1, a1, 1
    addi    t1, t0, -'0'
    li      t2, 10
    bltu    t1, t2, 4f
    ori     t0, t0, 0x20
    addi    t1, t0, -'a'
    li      t2, 6
    bgeu    t1, t2, 9f
    addi    t1, t1, 10
4:  slli    t6, t6, 4
    or      t6, t6, t1
    addi    t3, t3, -1
    bnez    t3, 3b
    sb      t6, 0(a5)
    addi    a5, a5, 1
    addi    a4, a4, -1
    j       2b
5:  li      a1, 1
    UNFRAME 16
9:  li      a0, 0
    UNFRAME 16
END_FUNCTION lantern_jdata_in

/*
 * L0: an entry of the table at a4 (a length byte and the bytes, then a 0 byte) that the a2
 * bytes at a1 match: a5 = its index, or 2^64 - 1. Uses t0-t3.
 */
LOCAL_FUNCTION lantern_jtable
    UNWIND_END_PROLOGUE
    li      a5, 0
1:  lbu     t0, 0(a4)
    addi    a4, a4, 1
    beqz    t0, 4f
    bne     t0, a2, 3f
    li      t1, 0
2:  add     t2, a1, t1
    lbu     t2, 0(t2)
    add     t3, a4, t1
    lbu     t3, 0(t3)
    bne     t2, t3, 3f
    addi    t1, t1, 1
    bltu    t1, a2, 2b
    ret
3:  add     a4, a4, t0
    addi    a5, a5, 1
    j       1b
4:  li      a5, -1
    ret
END_FUNCTION lantern_jtable

/* L0: a PayloadStatusV1 object at the cursor a0, into s2: a0 = the cursor after it. s6 1 when status is seen. */
LOCAL_FUNCTION lantern_jpayload_status
    ENTER 0
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    li      t1, '{'
    bne     t0, t1, 9f
    addi    a0, a0, 1
    li      s6, 0
    li      a1, 1
1:  call    lantern_jmember
    beqz    a0, 9f
    bnez    a3, 8f
    JIS     json_status
    beqz    t0, 3f
    call    lantern_jstring                         # status: one of the five
    beqz    a0, 9f
    bnez    a3, 9f
    ADDRESS a4, json_statuses
    call    lantern_jtable
    li      t0, -1
    beq     a5, t0, 9f
    addi    a5, a5, 1
    sd      a5, EngineResponse_status(s2)
    li      s6, 1
    j       7f
3:  JIS     json_latest_valid_hash
    beqz    t0, 6f
    li      a1, 1                           # latestValidHash: 32 bytes or null
    li      a2, 32
    addi    a3, s2, EngineResponse_latest_valid_hash
    call    lantern_jdata_in
    beqz    a0, 9f
    sd      a1, EngineResponse_has_latest_valid_hash(s2)
    j       7f
6:  call    lantern_jskip
    beqz    a0, 9f
7:  li      a1, 0
    j       1b
8:  beqz    s6, 9f
    LEAVE 0
9:  li      a0, 0
    LEAVE 0
END_FUNCTION lantern_jpayload_status

/* L0: the result of the method in s3 at the cursor a0, s8 the body's first byte: a0 = the cursor after it. */
LOCAL_FUNCTION lantern_jresult
    ENTER 0
    li      t0, ENGINE_METHOD_NEW_PAYLOAD
    bne     s3, t0, 1f
    call    lantern_jpayload_status
    LEAVE 0
1:  li      t0, ENGINE_METHOD_FORKCHOICE_UPDATED
    bne     s3, t0, 5f
    bgeu    a0, s1, 9f                      # {"payloadStatus": ..., "payloadId": ...}
    lbu     t0, 0(a0)
    li      t1, '{'
    bne     t0, t1, 9f
    addi    a0, a0, 1
    li      s7, 0
    li      a1, 1
2:  call    lantern_jmember
    beqz    a0, 9f
    bnez    a3, 4f
    JIS     json_payload_status
    beqz    t0, 3f
    call    lantern_jpayload_status
    beqz    a0, 9f
    li      s7, 1
    li      a1, 0
    j       2b
3:  JIS     json_payload_id
    beqz    t0, 6f
    li      a1, 1                           # payloadId: 8 bytes or null
    li      a2, 8
    addi    a3, s2, EngineResponse_payload_id
    call    lantern_jdata_in
    beqz    a0, 9f
    sd      a1, EngineResponse_has_payload_id(s2)
    li      a1, 0
    j       2b
6:  call    lantern_jskip
    beqz    a0, 9f
    li      a1, 0
    j       2b
4:  beqz    s7, 9f
    LEAVE 0
5:  li      t0, ENGINE_METHOD_ETH_BLOCK     # the eth_ methods: any value, its bytes kept
    beq     s3, t0, 51f
    li      t0, ENGINE_METHOD_ETH_LOGS
    bne     s3, t0, 52f
51: sub     t0, a0, s8
    sd      t0, EngineResponse_result_offset(s2)
    call    lantern_jskip
    beqz    a0, 9f
    sub     t0, a0, s8
    ld      t1, EngineResponse_result_offset(s2)
    sub     t0, t0, t1
    sd      t0, EngineResponse_result_length(s2)
    LEAVE 0
52: li      t0, ENGINE_METHOD_GET_PAYLOAD
    bne     s3, t0, 17f
    bgeu    a0, s1, 9f                      # getPayload: an object, its bytes kept
    lbu     t0, 0(a0)
    li      t1, '{'
    bne     t0, t1, 9f
    sub     t0, a0, s8
    sd      t0, EngineResponse_result_offset(s2)
    call    lantern_jskip
    beqz    a0, 9f
    sub     t0, a0, s8
    ld      t1, EngineResponse_result_offset(s2)
    sub     t0, t0, t1
    sd      t0, EngineResponse_result_length(s2)
    LEAVE 0
17: bgeu    a0, s1, 9f                      # exchangeCapabilities: an array of strings
    lbu     t0, 0(a0)
    li      t1, '['
    bne     t0, t1, 9f
    addi    a0, a0, 1
    call    lantern_jws
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    li      t1, ']'
    beq     t0, t1, 13f
10: call    lantern_jstring
    beqz    a0, 9f
    bnez    a3, 12f                         # a name with an escape matches no method
    ADDRESS a4, json_methods
    call    lantern_jtable
    li      t0, -1
    beq     a5, t0, 12f
    li      t0, 1
    sll     t0, t0, a5
    ld      t1, EngineResponse_capabilities(s2)
    or      t1, t1, t0
    sd      t1, EngineResponse_capabilities(s2)
12: call    lantern_jws
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    addi    a0, a0, 1
    li      t1, ']'
    beq     t0, t1, 16f
    li      t1, ','
    bne     t0, t1, 9f
    call    lantern_jws
    j       10b
13: addi    a0, a0, 1
16: LEAVE 0
9:  li      a0, 0
    LEAVE 0
END_FUNCTION lantern_jresult

/* L0: an error object at the cursor a0, into s2: a0 = the cursor after it. s7 1 when code is seen. */
LOCAL_FUNCTION lantern_jerror
    ENTER 0
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    li      t1, '{'
    bne     t0, t1, 9f
    addi    a0, a0, 1
    li      s7, 0
    li      a1, 1
1:  call    lantern_jmember
    beqz    a0, 9f
    bnez    a3, 8f
    JIS     json_code
    beqz    t0, 6f
    mv      s8, a0                          # code: an integer from -2^63 to 2^63 - 1
    call    lantern_jnumber
    beqz    a0, 9f
    beqz    a1, 9f
    li      s9, 0                           # 1 for a minus
    lbu     t0, 0(s8)
    li      t1, '-'
    bne     t0, t1, 2f
    li      s9, 1
    addi    s8, s8, 1
2:  li      t2, 0
    li      t3, 10
3:  bgeu    s8, a0, 4f
    lbu     t0, 0(s8)
    addi    s8, s8, 1
    addi    t0, t0, -'0'
    mulhu   t4, t2, t3
    bnez    t4, 9f
    mul     t2, t2, t3
    add     t4, t2, t0
    bltu    t4, t2, 9f
    mv      t2, t4
    j       3b
4:  li      t0, -1                          # the magnitude: at most 2^63, or 2^63 - 1
    srli    t0, t0, 1
    add     t0, t0, s9
    bltu    t0, t2, 9f
    beqz    s9, 5f
    neg     t2, t2
5:  sd      t2, EngineResponse_error_code(s2)
    li      s7, 1
    j       7f
6:  call    lantern_jskip
    beqz    a0, 9f
7:  li      a1, 0
    j       1b
8:  beqz    s7, 9f
    LEAVE 0
9:  li      a0, 0
    LEAVE 0
END_FUNCTION lantern_jerror

/*
 * (body, method, out): s1 the end, s2 out, s3 method, s4 1 when id is seen, s5 1 for an error, 2
 * for a result, s8 the body's first byte.
 */
FUNCTION lantern_engine_parse_response
    ENTER 0
    ld      t0, 8(a0)
    ld      t1, 16(a0)
    add     a0, a0, t0
    add     s1, a0, t1
    mv      s8, a0
    ld      s3, 0(a1)
    mv      s2, a2
    li      t0, 0                           # out: zero
1:  add     t1, s2, t0
    sd      zero, 0(t1)
    addi    t0, t0, 8
    li      t1, EngineResponse__mem
    bltu    t0, t1, 1b
    li      s4, 0
    li      s5, 0
    call    lantern_jws
    bgeu    a0, s1, 9f
    lbu     t0, 0(a0)
    li      t1, '{'
    bne     t0, t1, 9f
    addi    a0, a0, 1
    li      a1, 1
2:  call    lantern_jmember
    beqz    a0, 9f
    bnez    a3, 8f
    JIS     json_id
    beqz    t0, 4f
    mv      s6, a0                          # id: digits, at most 2^64 - 1
    call    lantern_jnumber
    beqz    a0, 9f
    beqz    a1, 9f
    lbu     t0, 0(s6)
    li      t1, '-'
    beq     t0, t1, 9f
    li      t2, 0
    li      t3, 10
3:  bgeu    s6, a0, 5f
    lbu     t0, 0(s6)
    addi    s6, s6, 1
    addi    t0, t0, -'0'
    mulhu   t4, t2, t3
    bnez    t4, 9f
    mul     t2, t2, t3
    add     t4, t2, t0
    bltu    t4, t2, 9f
    mv      t2, t4
    j       3b
5:  sd      t2, EngineResponse_id(s2)
    li      s4, 1
    j       7f
4:  JIS     json_result
    beqz    t0, 6f
    call    lantern_jresult
    beqz    a0, 9f
    ori     s5, s5, 2
    j       7f
6:  JIS     json_error
    beqz    t0, 10f
    call    lantern_jerror
    beqz    a0, 9f
    ori     s5, s5, 1
    j       7f
10: call    lantern_jskip
    beqz    a0, 9f
7:  li      a1, 0
    j       2b
8:  call    lantern_jws                             # then nothing but whitespace
    bne     a0, s1, 9f
    beqz    s4, 9f
    beqz    s5, 9f
    andi    t0, s5, 1
    sd      t0, EngineResponse_error(s2)
    li      a0, LANTERN_OK
    LEAVE 0
9:  li      a0, LANTERN_INVALID_JSON
    LEAVE 0
END_FUNCTION lantern_engine_parse_response
