/*
 * The JSON-RPC response parser of the Engine API client, ARM64: in the common object.
 * Requirements: docs/reference/engine-api.md.
 *
 * The local functions read the end of the body from x19 and the EngineResponse from x20,
 * which lantern_engine_parse_response sets. A cursor of 0 means the JSON is not valid.
 */

/* The names and strings the parser reads, before the code that takes their lengths. */
    RODATA
.include "jsonrpc_names.inc"

/* L0: x0 = the cursor x0 after any whitespace. Uses x9. */
LOCAL_FUNCTION lantern_jws
    UNWIND_END_PROLOGUE
1:  cmp     x0, x19
    b.hs    2f
    ldrb    w9, [x0]
    cmp     w9, #' '
    b.eq    3f
    cmp     w9, #9
    b.eq    3f
    cmp     w9, #10
    b.eq    3f
    cmp     w9, #13
    b.ne    2f
3:  add     x0, x0, #1
    b       1b
2:  ret
END_FUNCTION lantern_jws

/*
 * L0: a string at the cursor x0, its quote included: x0 = the cursor after it, x1 = where its
 * bytes start, x2 = their count, x3 = 1 when it has an escape. Uses x9, x10.
 */
LOCAL_FUNCTION lantern_jstring
    UNWIND_END_PROLOGUE
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0], #1
    cmp     w9, #'"'
    b.ne    9f
    mov     x1, x0
    mov     x3, #0
1:  cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0], #1
    cmp     w9, #'"'
    b.eq    8f
    cmp     w9, #0x20                       /* no control character */
    b.lo    9f
    cmp     w9, #'\\'
    b.ne    1b
    mov     x3, #1                          /* an escape */
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0], #1
    cmp     w9, #'u'
    b.eq    2f
    ADDRESS x10, json_escapes
    mov     x2, #0
3:  ldrb    w11, [x10, x2]
    cmp     w9, w11
    b.eq    1b
    add     x2, x2, #1
    cmp     x2, #8
    b.lo    3b
    b       9f
2:  mov     x2, #4                          /* \uXXXX */
4:  cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0], #1
    sub     w10, w9, #'0'
    cmp     w10, #10
    b.lo    5f
    orr     w9, w9, #0x20
    sub     w10, w9, #'a'
    cmp     w10, #6
    b.hs    9f
5:  subs    x2, x2, #1
    b.ne    4b
    b       1b
8:  sub     x2, x0, x1
    sub     x2, x2, #1
    ret
9:  mov     x0, #0
    ret
END_FUNCTION lantern_jstring

/* L0: a number at the cursor x0, as RFC 8259 writes it: x0 = the cursor after it, x1 = 1 when it is digits only. Uses x9, x10. */
LOCAL_FUNCTION lantern_jnumber
    UNWIND_END_PROLOGUE
    mov     x1, #1
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0]
    cmp     w9, #'-'
    b.ne    1f
    add     x0, x0, #1
1:  cmp     x0, x19                         /* 0, or a digit 1 to 9 and digits */
    b.hs    9f
    ldrb    w9, [x0], #1
    cmp     w9, #'0'
    b.eq    3f
    sub     w9, w9, #'1'
    cmp     w9, #9
    b.hs    9f
2:  cmp     x0, x19
    b.hs    7f
    ldrb    w9, [x0]
    sub     w9, w9, #'0'
    cmp     w9, #10
    b.hs    3f
    add     x0, x0, #1
    b       2b
3:  cmp     x0, x19                         /* a fraction */
    b.hs    7f
    ldrb    w9, [x0]
    cmp     w9, #'.'
    b.ne    5f
    mov     x1, #0
    add     x0, x0, #1
    mov     x10, #0
4:  cmp     x0, x19
    b.hs    6f
    ldrb    w9, [x0]
    sub     w9, w9, #'0'
    cmp     w9, #10
    b.hs    6f
    add     x0, x0, #1
    add     x10, x10, #1
    b       4b
6:  cbz     x10, 9f
5:  cmp     x0, x19                         /* an exponent */
    b.hs    7f
    ldrb    w9, [x0]
    orr     w9, w9, #0x20
    cmp     w9, #'e'
    b.ne    7f
    mov     x1, #0
    add     x0, x0, #1
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0]
    cmp     w9, #'+'
    b.eq    10f
    cmp     w9, #'-'
    b.ne    11f
10: add     x0, x0, #1
11: mov     x10, #0
12: cmp     x0, x19
    b.hs    13f
    ldrb    w9, [x0]
    sub     w9, w9, #'0'
    cmp     w9, #10
    b.hs    13f
    add     x0, x0, #1
    add     x10, x10, #1
    b       12b
13: cbz     x10, 9f
7:  ret
9:  mov     x0, #0
    ret
END_FUNCTION lantern_jnumber

/* L0: whether the x2 bytes at x1 are the literal label: x9 = 1 or 0. Uses x10, x11. */
.macro JIS label
    mov     x9, #0
    cmp     x2, #\label\()_len
    b.ne    93f
    ADDRESS x10, \label
    mov     x11, #0
91: ldrb    w12, [x1, x11]
    ldrb    w13, [x10, x11]
    cmp     w12, w13
    b.ne    93f
    add     x11, x11, #1
    cmp     x11, x2
    b.lo    91b
    mov     x9, #1
93:
.endm

/*
 * L0: the literal at the cursor x0 of the x2 bytes at x1: x0 = the cursor after it, or 0. Uses x9-x11.
 */
LOCAL_FUNCTION lantern_jliteral
    UNWIND_END_PROLOGUE
    sub     x9, x19, x0
    cmp     x9, x2
    b.lo    9f
    mov     x10, #0
1:  ldrb    w9, [x0, x10]
    ldrb    w11, [x1, x10]
    cmp     w9, w11
    b.ne    9f
    add     x10, x10, #1
    cmp     x10, x2
    b.lo    1b
    add     x0, x0, x2
    ret
9:  mov     x0, #0
    ret
END_FUNCTION lantern_jliteral

/*
 * L0: any value at the cursor x0, as RFC 8259 writes it: x0 = the cursor after it. Brackets nest
 * to 64 levels, their kinds in x21 (1 for an object), the depth in x22; x12 what comes next: 0 a
 * value, 1 a value or the array's end, 2 a name, 3 a name or the object's end. Uses x1-x3,
 * x9-x12.
 */
LOCAL_FUNCTION lantern_jskip
    FRAME 16
    stp     x21, x22, [sp, #16]
    mov     x21, #0
    mov     x22, #0
    mov     x12, #0
1:  bl      lantern_jws
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0]
    cmp     x12, #2
    b.lo    30f
    cmp     w9, #'}'                        /* a name and a colon, or the end of an empty object */
    b.ne    31f
    cmp     x12, #3
    b.eq    5f
    b       9f
31: cmp     w9, #'"'
    b.ne    9f
    bl      lantern_jstring
    cbz     x0, 9f
    bl      lantern_jws
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0]
    cmp     w9, #':'
    b.ne    9f
    add     x0, x0, #1
    mov     x12, #0
    b       1b
30: cmp     w9, #']'                        /* a value, or the end of an empty array */
    b.ne    32f
    cmp     x12, #1
    b.eq    5f
    b       9f
32: cmp     w9, #'"'
    b.ne    2f
    bl      lantern_jstring
    cbz     x0, 9f
    b       6f
2:  cmp     w9, #'{'
    b.eq    3f
    cmp     w9, #'['
    b.ne    7f
3:  cmp     x22, #64
    b.hs    9f
    lsl     x21, x21, #1
    cmp     w9, #'{'
    cinc    x21, x21, eq
    mov     x12, #1
    mov     x9, #3
    csel    x12, x9, x12, eq
    add     x22, x22, #1
    add     x0, x0, #1
    b       1b
5:  lsr     x21, x21, #1                    /* the end of the container */
    sub     x22, x22, #1
    add     x0, x0, #1
6:  cbz     x22, 8f                         /* a whole value at depth 0 */
    bl      lantern_jws                             /* in a container: a comma, or the end of its kind */
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0]
    and     x10, x21, #1
    cmp     w9, #','
    b.ne    33f
    add     x0, x0, #1
    lsl     x12, x10, #1
    b       1b
33: mov     w11, #']'
    mov     w9, #'}'
    cmp     x10, #0
    csel    w11, w9, w11, ne
    ldrb    w9, [x0]
    cmp     w9, w11
    b.eq    5b
    b       9f
7:  cmp     w9, #'t'                        /* true, false, null, or a number */
    b.ne    11f
    ADDRESS x1, json_true
    mov     x2, #4
    bl      lantern_jliteral
    cbz     x0, 9f
    b       6b
11: cmp     w9, #'f'
    b.ne    12f
    ADDRESS x1, json_false
    mov     x2, #5
    bl      lantern_jliteral
    cbz     x0, 9f
    b       6b
12: cmp     w9, #'n'
    b.ne    13f
    ADDRESS x1, json_null
    mov     x2, #4
    bl      lantern_jliteral
    cbz     x0, 9f
    b       6b
13: bl      lantern_jnumber
    cbz     x0, 9f
    b       6b
8:  ldp     x21, x22, [sp, #16]
    UNFRAME 16
9:  mov     x0, #0
    ldp     x21, x22, [sp, #16]
    UNFRAME 16
END_FUNCTION lantern_jskip

/*
 * L0: the next member of an object, from the cursor x0 after its brace (x1 = 1) or after a
 * value (x1 = 0): x3 = 1 at the closing brace, x0 after it; else x0 = its value after
 * whitespace, x1 = where its name's bytes start, x2 = their count, 2^64 - 1 for a name with
 * an escape. x0 = 0 when the JSON is not valid.
 */
LOCAL_FUNCTION lantern_jmember
    FRAME 16
    str     x1, [sp, #16]
    bl      lantern_jws
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0]
    cmp     w9, #'}'
    b.ne    1f
    ldr     x1, [sp, #16]                   /* the end: after the brace or a value, not after a comma */
    add     x0, x0, #1
    mov     x3, #1
    UNFRAME 16
1:  ldr     x1, [sp, #16]
    cbnz    x1, 2f
    cmp     w9, #','
    b.ne    9f
    add     x0, x0, #1
    bl      lantern_jws
2:  bl      lantern_jstring
    cbz     x0, 9f
    cbz     x3, 3f
    mov     x2, #-1
3:  stp     x1, x2, [sp, #16]
    bl      lantern_jws
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0], #1
    cmp     w9, #':'
    b.ne    9f
    bl      lantern_jws
    ldp     x1, x2, [sp, #16]
    mov     x3, #0
    UNFRAME 16
9:  mov     x0, #0
    UNFRAME 16
END_FUNCTION lantern_jmember

/*
 * L0: DATA of x2 bytes at the cursor x0, or null when x1 = 1 allows it, to x3:
 * x0 = the cursor after it, x1 = 1 when it is not null. Uses x9-x13.
 */
LOCAL_FUNCTION lantern_jdata_in
    FRAME 32
    stp     x2, x3, [sp, #16]
    cbz     x1, 1f
    cmp     x0, x19
    b.hs    1f
    ldrb    w9, [x0]
    cmp     w9, #'n'
    b.ne    1f
    ADDRESS x1, json_null
    mov     x2, #4
    bl      lantern_jliteral
    mov     x1, #0
    UNFRAME 32
1:  bl      lantern_jstring
    cbz     x0, 9f
    cbnz    x3, 9f                          /* "0x", then 2 hex digits a byte */
    ldp     x10, x11, [sp, #16]
    add     x12, x10, #1
    lsl     x12, x12, #1
    cmp     x2, x12
    b.ne    9f
    ldrb    w9, [x1]
    cmp     w9, #'0'
    b.ne    9f
    ldrb    w9, [x1, #1]
    cmp     w9, #'x'
    b.ne    9f
    add     x1, x1, #2
2:  cbz     x10, 5f
    mov     x13, #0
    mov     x12, #2
3:  ldrb    w9, [x1], #1
    sub     w2, w9, #'0'
    cmp     w2, #10
    b.lo    4f
    orr     w9, w9, #0x20
    sub     w2, w9, #'a'
    cmp     w2, #6
    b.hs    9f
    add     w2, w2, #10
4:  orr     x13, x2, x13, lsl #4
    subs    x12, x12, #1
    b.ne    3b
    strb    w13, [x11], #1
    sub     x10, x10, #1
    b       2b
5:  mov     x1, #1
    UNFRAME 32
9:  mov     x0, #0
    UNFRAME 32
END_FUNCTION lantern_jdata_in

/* L0: a PayloadStatusV1 object at the cursor x0, into x20: x0 = the cursor after it. x23 1 when status is seen. */
LOCAL_FUNCTION lantern_jpayload_status
    ENTER 0
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0], #1
    cmp     w9, #'{'
    b.ne    9f
    mov     x23, #0
    mov     x1, #1
1:  bl      lantern_jmember
    cbz     x0, 9f
    cbnz    x3, 8f
    JIS     json_status
    cbz     x9, 3f
    bl      lantern_jstring                         /* status: one of the five */
    cbz     x0, 9f
    cbnz    x3, 9f
    mov     x24, x0
    mov     x25, #1
    ADDRESS x26, json_statuses
2:  ldrb    w27, [x26], #1                  /* each entry: its length, then its bytes */
    cbz     w27, 9f
    mov     x9, #0
    cmp     x2, x27
    b.ne    4f
5:  ldrb    w10, [x1, x9]
    ldrb    w11, [x26, x9]
    cmp     w10, w11
    b.ne    4f
    add     x9, x9, #1
    cmp     x9, x2
    b.lo    5b
    str     x25, [x20, #EngineResponse_status]
    mov     x23, #1
    mov     x0, x24
    b       7f
4:  add     x26, x26, x27
    add     x25, x25, #1
    b       2b
3:  JIS     json_latest_valid_hash
    cbz     x9, 6f
    mov     x1, #1                          /* latestValidHash: 32 bytes or null */
    mov     x2, #32
    add     x3, x20, #EngineResponse_latest_valid_hash
    bl      lantern_jdata_in
    cbz     x0, 9f
    str     x1, [x20, #EngineResponse_has_latest_valid_hash]
    b       7f
6:  bl      lantern_jskip
    cbz     x0, 9f
7:  mov     x1, #0
    b       1b
8:  cbz     x23, 9f
    LEAVE 0
9:  mov     x0, #0
    LEAVE 0
END_FUNCTION lantern_jpayload_status

/* L0: the result of the method in x21 at the cursor x0: x0 = the cursor after it. */
LOCAL_FUNCTION lantern_jresult
    ENTER 0
    cmp     x21, #ENGINE_METHOD_NEW_PAYLOAD
    b.ne    1f
    bl      lantern_jpayload_status
    LEAVE 0
1:  cmp     x21, #ENGINE_METHOD_FORKCHOICE_UPDATED
    b.ne    5f
    cmp     x0, x19                         /* {"payloadStatus": ..., "payloadId": ...} */
    b.hs    9f
    ldrb    w9, [x0], #1
    cmp     w9, #'{'
    b.ne    9f
    mov     x28, #0
    mov     x1, #1
2:  bl      lantern_jmember
    cbz     x0, 9f
    cbnz    x3, 4f
    JIS     json_payload_status
    cbz     x9, 3f
    bl      lantern_jpayload_status
    cbz     x0, 9f
    mov     x28, #1
    mov     x1, #0
    b       2b
3:  JIS     json_payload_id
    cbz     x9, 6f
    mov     x1, #1                          /* payloadId: 8 bytes or null */
    mov     x2, #8
    add     x3, x20, #EngineResponse_payload_id
    bl      lantern_jdata_in
    cbz     x0, 9f
    str     x1, [x20, #EngineResponse_has_payload_id]
    mov     x1, #0
    b       2b
6:  bl      lantern_jskip
    cbz     x0, 9f
    mov     x1, #0
    b       2b
4:  cbz     x28, 9f
    LEAVE 0
5:  cmp     x21, #ENGINE_METHOD_ETH_BLOCK   /* the eth_ methods: any value, its bytes kept */
    ccmp    x21, #ENGINE_METHOD_ETH_LOGS, #4, ne
    b.ne    51f
    sub     x9, x0, x24
    str     x9, [x20, #EngineResponse_result_offset]
    bl      lantern_jskip
    cbz     x0, 9f
    sub     x9, x0, x24
    ldr     x10, [x20, #EngineResponse_result_offset]
    sub     x9, x9, x10
    str     x9, [x20, #EngineResponse_result_length]
    LEAVE 0
51: cmp     x21, #ENGINE_METHOD_GET_PAYLOAD
    b.ne    17f
    cmp     x0, x19                         /* getPayload: an object, its bytes kept */
    b.hs    9f
    ldrb    w9, [x0]
    cmp     w9, #'{'
    b.ne    9f
    sub     x9, x0, x24
    str     x9, [x20, #EngineResponse_result_offset]
    bl      lantern_jskip
    cbz     x0, 9f
    sub     x9, x0, x24
    ldr     x10, [x20, #EngineResponse_result_offset]
    sub     x9, x9, x10
    str     x9, [x20, #EngineResponse_result_length]
    LEAVE 0
17: cmp     x0, x19                         /* exchangeCapabilities: an array of strings */
    b.hs    9f
    ldrb    w9, [x0], #1
    cmp     w9, #'['
    b.ne    9f
    bl      lantern_jws
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0]
    cmp     w9, #']'
    b.eq    13f
10: bl      lantern_jstring
    cbz     x0, 9f
    cbnz    x3, 12f                         /* a name with an escape matches no method */
    ADDRESS x26, json_methods
    mov     x25, #0
11: ldrb    w27, [x26], #1                  /* each entry: its length, then its bytes */
    cbz     w27, 12f
    mov     x9, #0
    cmp     x2, x27
    b.ne    14f
15: ldrb    w10, [x1, x9]
    ldrb    w11, [x26, x9]
    cmp     w10, w11
    b.ne    14f
    add     x9, x9, #1
    cmp     x9, x2
    b.lo    15b
    ldr     x9, [x20, #EngineResponse_capabilities]
    mov     x10, #1
    lsl     x10, x10, x25
    orr     x9, x9, x10
    str     x9, [x20, #EngineResponse_capabilities]
    b       12f
14: add     x26, x26, x27
    add     x25, x25, #1
    b       11b
12: bl      lantern_jws
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0], #1
    cmp     w9, #']'
    b.eq    16f
    cmp     w9, #','
    b.ne    9f
    bl      lantern_jws
    b       10b
13: add     x0, x0, #1
16: LEAVE 0
9:  mov     x0, #0
    LEAVE 0
END_FUNCTION lantern_jresult

/* L0: an error object at the cursor x0, into x20: x0 = the cursor after it. x28 1 when code is seen. */
LOCAL_FUNCTION lantern_jerror
    ENTER 0
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0], #1
    cmp     w9, #'{'
    b.ne    9f
    mov     x28, #0
    mov     x1, #1
1:  bl      lantern_jmember
    cbz     x0, 9f
    cbnz    x3, 8f
    JIS     json_code
    cbz     x9, 6f
    mov     x23, x0                         /* code: an integer from -2^63 to 2^63 - 1 */
    bl      lantern_jnumber
    cbz     x0, 9f
    cbz     x1, 9f
    mov     x24, x0
    mov     x10, x23
    mov     x11, #0                         /* 1 for a minus */
    ldrb    w9, [x10]
    cmp     w9, #'-'
    b.ne    2f
    mov     x11, #1
    add     x10, x10, #1
2:  mov     x12, #0
    mov     x13, #10
3:  cmp     x10, x24
    b.hs    4f
    ldrb    w9, [x10], #1
    sub     w9, w9, #'0'
    umulh   x14, x12, x13
    cbnz    x14, 9f
    mul     x12, x12, x13
    adds    x12, x12, x9
    b.cs    9f
    b       3b
4:  mov     x9, #(1 << 63)                  /* the magnitude: at most 2^63, or 2^63 - 1 */
    sub     x9, x9, #1
    add     x9, x9, x11
    cmp     x12, x9
    b.hi    9f
    cbz     x11, 5f
    neg     x12, x12
5:  str     x12, [x20, #EngineResponse_error_code]
    mov     x28, #1
    mov     x0, x24
    b       7f
6:  bl      lantern_jskip
    cbz     x0, 9f
7:  mov     x1, #0
    b       1b
8:  cbz     x28, 9f
    LEAVE 0
9:  mov     x0, #0
    LEAVE 0
END_FUNCTION lantern_jerror

/*
 * (body, method, out): x19 the end, x20 out, x21 method, x22 1 when id is seen, x23 2 for an
 * error, 1 for a result, x24 the cursor. Locals: L the error code, L+8 the status fields.
 */
FUNCTION lantern_engine_parse_response
    ENTER 16
    ldp     x9, x10, [x0, #8]
    add     x24, x0, x9
    add     x19, x24, x10
    ldr     x21, [x1]
    mov     x20, x2
    mov     x9, #0                          /* out: zero */
1:  str     xzr, [x20, x9]
    add     x9, x9, #8
    cmp     x9, #EngineResponse__mem
    b.lo    1b
    mov     x22, #0
    mov     x25, #0                         /* 1 for an error, 2 for a result */
    mov     x0, x24
    bl      lantern_jws
    cmp     x0, x19
    b.hs    9f
    ldrb    w9, [x0], #1
    cmp     w9, #'{'
    b.ne    9f
    mov     x1, #1
2:  bl      lantern_jmember
    cbz     x0, 9f
    cbnz    x3, 8f
    JIS     json_id
    cbz     x9, 4f
    mov     x23, x0                         /* id: digits, at most 2^64 - 1 */
    bl      lantern_jnumber
    cbz     x0, 9f
    cbz     x1, 9f
    ldrb    w9, [x23]
    cmp     w9, #'-'
    b.eq    9f
    mov     x10, #0
    mov     x13, #10
3:  cmp     x23, x0
    b.hs    5f
    ldrb    w9, [x23], #1
    sub     w9, w9, #'0'
    umulh   x14, x10, x13
    cbnz    x14, 9f
    mul     x10, x10, x13
    adds    x10, x10, x9
    b.cs    9f
    b       3b
5:  str     x10, [x20, #EngineResponse_id]
    mov     x22, #1
    b       7f
4:  JIS     json_result
    cbz     x9, 6f
    bl      lantern_jresult
    cbz     x0, 9f
    orr     x25, x25, #2
    b       7f
6:  JIS     json_error
    cbz     x9, 10f
    bl      lantern_jerror
    cbz     x0, 9f
    orr     x25, x25, #1
    b       7f
10: bl      lantern_jskip
    cbz     x0, 9f
7:  mov     x1, #0
    b       2b
8:  bl      lantern_jws                             /* then nothing but whitespace */
    cmp     x0, x19
    b.ne    9f
    cbz     x22, 9f
    cbz     x25, 9f
    and     x9, x25, #1
    str     x9, [x20, #EngineResponse_error]
    mov     x0, #LANTERN_OK
    LEAVE 16
9:  mov     x0, #LANTERN_INVALID_JSON
    LEAVE 16
END_FUNCTION lantern_engine_parse_response
