/*
 * lantern_api_route, ARM64: in the common object. Requirements: docs/reference/beacon-api.md.
 * Uses lantern_http_find, lantern_http_trim and lantern_http_same of http.s.
 */

    API_ROUTE_DATA
    .p2align 3
route_base58:                                 /* the base58btc alphabet, a bit each */
    .quad   0x03fe000000000000, 0x07ffeffe07ff7dfe
route_t_json:
    .ascii  "application/json"
.set api_t_json_len, 16
route_t_ssz:
    .ascii  "application/octet-stream"
.set api_t_ssz_len, 24
route_t_any_application:
    .ascii  "application/*"
.set api_t_any_application_len, 13
route_t_any:
    .ascii  "*/*"
.set api_t_any_len, 3
route_k_ids:
    .ascii  "ids"
route_k_statuses:
    .ascii  "statuses"
route_k_null:
    .ascii  "null"

/* reg = the value of the hex digit in reg (either case), else branch to bad. Uses tmp. */
.macro ROUTE_HEX reg, tmp, bad
    sub     \tmp, \reg, #'0'
    cmp     \tmp, #9
    b.ls    77f
    orr     \tmp, \reg, #0x20
    sub     \tmp, \tmp, #'a'
    cmp     \tmp, #5
    b.hi    \bad
    add     \tmp, \tmp, #10
77: mov     \reg, \tmp
.endm

/* x0 = 1 when each % of the x1 bytes at x0 is followed by two hex digits, else 0. A leaf. Uses x9-x12. */
LOCAL_FUNCTION lantern_route_pct_ok
    UNWIND_END_PROLOGUE
    mov     x9, #0
1:  cmp     x9, x1
    b.hs    9f
    ldrb    w10, [x0, x9]
    add     x9, x9, #1
    cmp     w10, #'%'
    b.ne    1b
    add     x11, x9, #2
    cmp     x11, x1
    b.hi    8f
    ldrb    w10, [x0, x9]
    ROUTE_HEX w10, w12, 8f
    add     x11, x9, #1
    ldrb    w10, [x0, x11]
    ROUTE_HEX w10, w12, 8f
    add     x9, x9, #2
    b       1b
8:  mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION lantern_route_pct_ok

/*
 * The x1 bytes at x0, percent-decoded (each % is followed by two hex digits), to x2: at most x3
 * bytes written; x0 = the decoded length, which may pass x3. A leaf. Uses x9-x13.
 */
LOCAL_FUNCTION lantern_route_decode
    UNWIND_END_PROLOGUE
    mov     x9, #0
    mov     x10, #0
1:  cmp     x9, x1
    b.hs    9f
    ldrb    w11, [x0, x9]
    add     x9, x9, #1
    cmp     w11, #'%'
    b.ne    2f
    ldrb    w11, [x0, x9]
    ROUTE_HEX w11, w12, 9f
    add     x13, x9, #1
    ldrb    w13, [x0, x13]
    ROUTE_HEX w13, w12, 9f
    orr     w11, w13, w11, lsl #4
    add     x9, x9, #2
2:  cmp     x10, x3
    b.hs    3f
    strb    w11, [x2, x10]
3:  add     x10, x10, #1
    b       1b
9:  mov     x0, x10
    ret
END_FUNCTION lantern_route_decode

/*
 * One item of a list value: the bytes at x0 from index x1 to index x2, percent-decoded, up to
 * the first decoded `,`, to x3 with at most x4 bytes written. x0 = the index after the item and its
 * comma, x1 = the item's decoded length (it may pass x4), x2 = 1 when a comma ended it. A leaf. Uses x5, x9-x13.
 */
LOCAL_FUNCTION lantern_route_next_item
    UNWIND_END_PROLOGUE
    mov     x10, #0
    mov     x5, #0
1:  cmp     x1, x2
    b.hs    9f
    ldrb    w11, [x0, x1]
    add     x1, x1, #1
    cmp     w11, #'%'
    b.ne    2f
    ldrb    w11, [x0, x1]
    ROUTE_HEX w11, w12, 9f
    add     x13, x1, #1
    ldrb    w13, [x0, x13]
    ROUTE_HEX w13, w12, 9f
    orr     w11, w13, w11, lsl #4
    add     x1, x1, #2
2:  cmp     w11, #','
    b.eq    8f
    cmp     x10, x4
    b.hs    3f
    strb    w11, [x3, x10]
3:  add     x10, x10, #1
    b       1b
8:  mov     x5, #1
9:  mov     x0, x1
    mov     x1, x10
    mov     x2, x5
    ret
END_FUNCTION lantern_route_next_item

/* The x1 bytes at x0 as a decimal number below 2^64: x0 = 0 and x1 = its value, else x0 = 1. A leaf. Uses x9-x13. */
LOCAL_FUNCTION lantern_route_number
    UNWIND_END_PROLOGUE
    cbz     x1, 8f
    mov     x9, #0
    mov     x10, #0
    mov     x13, #10
1:  cmp     x10, x1
    b.hs    9f
    ldrb    w11, [x0, x10]
    sub     w11, w11, #'0'
    cmp     w11, #9
    b.hi    8f
    umulh   x12, x9, x13
    cbnz    x12, 8f
    mul     x9, x9, x13
    adds    x9, x9, x11
    b.cs    8f
    add     x10, x10, #1
    b       1b
8:  mov     x0, #1
    ret
9:  mov     x0, #0
    mov     x1, x9
    ret
END_FUNCTION lantern_route_number

/* The x1 bytes at x0 as 0x and the hex of x2 bytes: x0 = 0 and the bytes at x3, else x0 = 1. A leaf. Uses x9-x12. */
LOCAL_FUNCTION lantern_route_hex
    UNWIND_END_PROLOGUE
    lsl     x9, x2, #1
    add     x9, x9, #2
    cmp     x1, x9
    b.ne    8f
    ldrb    w10, [x0]
    cmp     w10, #'0'
    b.ne    8f
    ldrb    w10, [x0, #1]
    cmp     w10, #'x'
    b.ne    8f
    add     x0, x0, #2
1:  cbz     x2, 9f
    ldrb    w10, [x0], #1
    ROUTE_HEX w10, w12, 8f
    ldrb    w11, [x0], #1
    ROUTE_HEX w11, w12, 8f
    orr     w10, w11, w10, lsl #4
    strb    w10, [x3], #1
    sub     x2, x2, #1
    b       1b
8:  mov     x0, #1
    ret
9:  mov     x0, #0
    ret
END_FUNCTION lantern_route_hex

/* The word of api_words for parameter x0 that is the x2 bytes at x1: x0 = 1 and x1 = its value, else x0 = 0. A leaf. Uses x6, x7, x9-x14. */
LOCAL_FUNCTION lantern_route_word
    UNWIND_END_PROLOGUE
    ADDRESS x9, api_words
    ADDRESS x10, api_word_text
    mov     x11, #API_WORDS
1:  cbz     x11, 8f
    ldr     x12, [x9]
    cmp     x12, x0
    b.ne    5f
    ldr     x12, [x9, #16]
    cmp     x12, x2
    b.ne    5f
    ldr     x13, [x9, #8]
    add     x13, x10, x13
    mov     x14, #0
2:  cmp     x14, x2
    b.hs    7f
    ldrb    w6, [x13, x14]
    ldrb    w7, [x1, x14]
    cmp     w6, w7
    b.ne    5f
    add     x14, x14, #1
    b       2b
7:  mov     x0, #1
    ldr     x1, [x9, #24]
    ret
5:  add     x9, x9, #32
    sub     x11, x11, #1
    b       1b
8:  mov     x0, #0
    ret
END_FUNCTION lantern_route_word

/*
 * Whether the x1 bytes at x0, a path whose percent-encoding is good, match the template of x3
 * bytes at x2: x0 = 1 or 0. Each parameter segment goes to the list at x4: its count, then for each
 * its API_PARAM_*, start and end in the path. A leaf. Uses x9-x15.
 */
LOCAL_FUNCTION lantern_route_match
    UNWIND_END_PROLOGUE
    mov     x9, #1
    mov     x10, #1
    mov     x11, #0
    str     xzr, [x4]
1:  cmp     x10, x3
    b.hs    8f
    ldrb    w12, [x2, x10]
    cmp     w12, #0x20
    b.hs    3f
    mov     x13, x9                         /* a parameter: up to the next / */
2:  cmp     x9, x1
    b.hs    21f
    ldrb    w14, [x0, x9]
    cmp     w14, #'/'
    b.eq    21f
    add     x9, x9, #1
    b       2b
21: cmp     x9, x13
    b.eq    7f
    mov     x14, #24
    madd    x14, x11, x14, x4
    str     x12, [x14, #8]
    stp     x13, x9, [x14, #16]
    add     x11, x11, #1
    str     x11, [x4]
    add     x10, x10, #1
    b       1b
3:  cmp     w12, #'/'                       /* a separator: a / of the path itself */
    b.ne    4f
    cmp     x9, x1
    b.hs    7f
    ldrb    w14, [x0, x9]
    cmp     w14, #'/'
    b.ne    7f
    add     x9, x9, #1
    add     x10, x10, #1
    b       1b
4:  cmp     x9, x1                          /* a fixed byte: the path's next decoded byte */
    b.hs    7f
    ldrb    w14, [x0, x9]
    add     x9, x9, #1
    cmp     w14, #'%'
    b.ne    5f
    ldrb    w14, [x0, x9]
    ROUTE_HEX w14, w13, 7f
    add     x15, x9, #1
    ldrb    w15, [x0, x15]
    ROUTE_HEX w15, w13, 7f
    orr     w14, w15, w14, lsl #4
    add     x9, x9, #2
5:  cmp     w14, w12
    b.ne    7f
    add     x10, x10, #1
    b       1b
8:  cmp     x9, x1
    cset    x0, eq
    ret
7:  mov     x0, #0
    ret
END_FUNCTION lantern_route_match

/*
 * The x3 decoded bytes at x2 as a value of parameter x1, into ApiRoute x0; an item of a list
 * goes to the 64 bytes at x4. x0 = 0, or 1 when the value breaks its type.
 * x19 out, x20 the parameter, x21 bytes, x22 length, x23 the item's place, x24 the field.
 */
LOCAL_FUNCTION lantern_route_value
    ENTER 0
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    ADDRESS x9, api_params
    add     x9, x9, x20, lsl #5
    ldr     x24, [x9, #24]
    ldr     x9, [x9, #16]
    cmp     x9, #API_KIND_NUMBER
    b.eq    10f
    cmp     x9, #API_KIND_STATE_ID
    b.eq    11f
    cmp     x9, #API_KIND_BLOCK_ID
    b.eq    11f
    cmp     x9, #API_KIND_BLOCK_ROOT
    b.eq    13f
    cmp     x9, #API_KIND_VALIDATOR
    b.eq    14f
    cmp     x9, #API_KIND_ID_LIST
    b.eq    15f
    cmp     x9, #API_KIND_PEER_ID
    b.eq    16f
    cmp     x9, #API_KIND_SYNCING
    b.eq    17f
    cmp     x9, #API_KIND_ROOT
    b.eq    18f
    cmp     x9, #API_KIND_RANDAO
    b.eq    19f
    cmp     x9, #API_KIND_GRAFFITI
    b.eq    20f
    cmp     x9, #API_KIND_FLAG
    b.eq    21f
    cmp     x9, #API_KIND_WORD
    b.eq    22f
    cmp     x9, #API_KIND_SET
    b.eq    23f
    cmp     x9, #API_KIND_INDEX_LIST
    b.eq    24f
    cmp     x9, #API_KIND_HASH_LIST
    b.eq    25f
    b       98f
10: mov     x0, x21                         /* a number, to its field */
    mov     x1, x22
    bl      lantern_route_number
    cbnz    x0, 98f
    str     x1, [x19, x24]
    b       90f
11: mov     x0, x20                         /* state_id, block_id: a word, a slot or a root */
    mov     x1, x21
    mov     x2, x22
    bl      lantern_route_word
    cbz     x0, 12f
    str     x1, [x19, #ApiRoute_id_kind]
    b       90f
12: mov     x0, x21
    mov     x1, x22
    bl      lantern_route_number
    cbnz    x0, 13f
    mov     x9, #API_ID_SLOT
    stp     x9, x1, [x19, #ApiRoute_id_kind]
    b       90f
13: mov     x0, x21                         /* a root */
    mov     x1, x22
    mov     x2, #32
    add     x3, x19, #ApiRoute_id_root
    bl      lantern_route_hex
    cbnz    x0, 98f
    mov     x9, #API_ID_ROOT
    str     x9, [x19, #ApiRoute_id_kind]
    b       90f
14: add     x23, x19, #ApiRoute_validator   /* validator_id, an id: an index or a public key */
15: stp     xzr, xzr, [x23]
    stp     xzr, xzr, [x23, #16]
    stp     xzr, xzr, [x23, #32]
    stp     xzr, xzr, [x23, #48]
    mov     x0, x21
    mov     x1, x22
    bl      lantern_route_number
    cbnz    x0, 151f
    mov     x9, #API_VALIDATOR_INDEX
    stp     x9, x1, [x23]
    b       90f
151: mov    x0, x21
    mov     x1, x22
    mov     x2, #48
    add     x3, x23, #ValidatorRef_pubkey
    bl      lantern_route_hex
    cbnz    x0, 98f
    mov     x9, #API_VALIDATOR_PUBKEY
    str     x9, [x23]
    b       90f
16: cbz     x22, 98f                        /* peer_id: 1 to 128 bytes of base58btc */
    cmp     x22, #128
    b.hi    98f
    ADDRESS x10, route_base58
    mov     x9, #0
161: cmp    x9, x22
    b.hs    90f
    ldrb    w11, [x21, x9]
    lsr     x12, x11, #6
    cmp     x12, #1
    b.hi    98f
    ldr     x12, [x10, x12, lsl #3]
    lsr     x12, x12, x11
    tbz     x12, #0, 98f
    add     x9, x9, #1
    b       161b
17: mov     x0, x21                         /* syncing_status: 100 to 599 */
    mov     x1, x22
    bl      lantern_route_number
    cbnz    x0, 98f
    cmp     x1, #100
    b.lo    98f
    cmp     x1, #599
    b.hi    98f
    str     x1, [x19, x24]
    b       90f
18: mov     x2, #32                         /* hex to its field: a root, the reveal, the graffiti */
    b       26f
19: mov     x2, #96
    b       26f
20: mov     x2, #32
26: mov     x0, x21
    mov     x1, x22
    add     x3, x19, x24
    bl      lantern_route_hex
    cbnz    x0, 98f
    b       90f
21: cbnz    x22, 98f                        /* skip_randao_verification: empty */
    b       90f
22: mov     x0, x20                         /* broadcast_validation: a word */
    mov     x1, x21
    mov     x2, x22
    bl      lantern_route_word
    cbz     x0, 98f
    str     x1, [x19, x24]
    b       90f
23: mov     x0, x20                         /* a set: the word's bits */
    mov     x1, x21
    mov     x2, x22
    bl      lantern_route_word
    cbz     x0, 98f
    ldr     x9, [x19, x24]
    orr     x9, x9, x1
    str     x9, [x19, x24]
    b       90f
24: mov     x0, x21                         /* indices: a number */
    mov     x1, x22
    bl      lantern_route_number
    cbnz    x0, 98f
    str     x1, [x23]
    b       90f
25: mov     x0, x21                         /* versioned_hashes: a root */
    mov     x1, x22
    mov     x2, #32
    mov     x3, x23
    bl      lantern_route_hex
    cbnz    x0, 98f
90: mov     x0, #0
    LEAVE 0
98: mov     x0, #1
    LEAVE 0
END_FUNCTION lantern_route_value

/* x21 past the JSON white space (space, tab, LF, CR) before x25. A leaf. Uses x9. */
LOCAL_FUNCTION lantern_route_ws
    UNWIND_END_PROLOGUE
1:  cmp     x21, x25
    b.hs    9f
    ldrb    w9, [x21]
    cmp     w9, #32
    b.eq    2f
    cmp     w9, #9
    b.eq    2f
    cmp     w9, #10
    b.eq    2f
    cmp     w9, #13
    b.ne    9f
2:  add     x21, x21, #1
    b       1b
9:  ret
END_FUNCTION lantern_route_ws

/* x0 = 1 when the x1 bytes at x0 start the bytes at x21 (before x25), x21 then past them; else 0. A leaf. Uses x9-x11. */
LOCAL_FUNCTION lantern_route_lit
    UNWIND_END_PROLOGUE
    sub     x9, x25, x21
    cmp     x9, x1
    b.lo    8f
    mov     x9, #0
1:  cmp     x9, x1
    b.hs    2f
    ldrb    w10, [x0, x9]
    ldrb    w11, [x21, x9]
    cmp     w10, w11
    b.ne    8f
    add     x9, x9, #1
    b       1b
2:  add     x21, x21, x1
    mov     x0, #1
    ret
8:  mov     x0, #0
    ret
END_FUNCTION lantern_route_lit

/*
 * The JSON string at x21 (before x25), RFC 8259 section 7: its value, each escape decoded (a \u
 * of 0x80 or more as the byte 0x80), into the 200 bytes at x22 + 192; x21 then past it. x0 = 0, or
 * 1 when it breaks the rules; x1 = the value's length, 201 when it is longer than 200. A leaf. Uses
 * x9-x13.
 */
LOCAL_FUNCTION lantern_route_string
    UNWIND_END_PROLOGUE
    cmp     x21, x25
    b.hs    8f
    ldrb    w9, [x21], #1
    cmp     w9, #34                         /* " */
    b.ne    8f
    add     x10, x22, #192
    mov     x1, #0
1:  cmp     x21, x25
    b.hs    8f
    ldrb    w9, [x21], #1
    cmp     w9, #34
    b.eq    9f
    cmp     w9, #32
    b.lo    8f
    cmp     w9, #92                         /* \ */
    b.ne    5f
    cmp     x21, x25                        /* an escape */
    b.hs    8f
    ldrb    w9, [x21], #1
    mov     w11, #34
    cmp     w9, #34
    b.eq    4f
    mov     w11, #92
    cmp     w9, #92
    b.eq    4f
    mov     w11, #47
    cmp     w9, #47
    b.eq    4f
    mov     w11, #8
    cmp     w9, #'b'
    b.eq    4f
    mov     w11, #12
    cmp     w9, #'f'
    b.eq    4f
    mov     w11, #10
    cmp     w9, #'n'
    b.eq    4f
    mov     w11, #13
    cmp     w9, #'r'
    b.eq    4f
    mov     w11, #9
    cmp     w9, #'t'
    b.eq    4f
    cmp     w9, #'u'
    b.ne    8f
    sub     x12, x25, x21                   /* \u and 4 hex digits */
    cmp     x12, #4
    b.lo    8f
    mov     w11, #0
    mov     x13, #4
2:  ldrb    w9, [x21], #1
    ROUTE_HEX w9, w12, 8f
    orr     w11, w9, w11, lsl #4
    subs    x13, x13, #1
    b.ne    2b
    cmp     w11, #0x80
    mov     w12, #0x80
    csel    w11, w12, w11, hs
4:  mov     w9, w11
5:  cmp     x1, #200                        /* the byte joins the value */
    b.hs    6f
    strb    w9, [x10, x1]
6:  add     x1, x1, #1
    b       1b
9:  cmp     x1, #200
    mov     x9, #201
    csel    x1, x9, x1, hi
    mov     x0, #0
    ret
8:  mov     x0, #1
    ret
END_FUNCTION lantern_route_string

/* x0 = API_PARAM_ID when the x1 bytes at x22 + 192 are ids, API_PARAM_STATUS when they are statuses, else 0. A leaf. Uses x9-x13. */
LOCAL_FUNCTION lantern_route_key
    UNWIND_END_PROLOGUE
    ADDRESS x9, route_k_ids
    mov     x10, #3
    mov     x0, #API_PARAM_ID
    cmp     x1, #3
    b.eq    1f
    ADDRESS x9, route_k_statuses
    mov     x10, #8
    mov     x0, #API_PARAM_STATUS
    cmp     x1, #8
    b.ne    8f
1:  add     x11, x22, #192
2:  ldrb    w12, [x9], #1
    ldrb    w13, [x11], #1
    cmp     w12, w13
    b.ne    8f
    subs    x10, x10, #1
    b.ne    2b
    ret
8:  mov     x0, #0
    ret
END_FUNCTION lantern_route_key

/*
 * Null, or an array of strings, at x21 of a body that ends at x25: each string an item of the
 * parameter x0 (API_PARAM_ID: into the list of out x20, x27 items; API_PARAM_STATUS: its bits), its
 * bit of present (x26) set; x21 then past the value. x0 = 0, or the fault + 1. x22 the locals of
 * lantern_api_route: +56 1 when the list has no room, +128 an item. Locals: the parameter, an
 * item's start.
 */
LOCAL_FUNCTION lantern_route_ids_array
    FRAME 16
    str     x0, [sp, #16]
    ADDRESS x0, route_k_null
    mov     x1, #4
    bl      lantern_route_lit
    cbnz    x0, 7f
    cmp     x21, x25                        /* [ */
    b.hs    8f
    ldrb    w9, [x21], #1
    cmp     w9, #'['
    b.ne    8f
    bl      lantern_route_ws
    cmp     x21, x25
    b.hs    8f
    ldrb    w9, [x21]
    cmp     w9, #']'
    b.ne    2f
    add     x21, x21, #1
    b       7f
2:  bl      lantern_route_ws                        /* a string: its value is the item */
    bl      lantern_route_string
    cbnz    x0, 8f
    cmp     x1, #200
    b.hi    9f
    mov     x3, x1
    mov     x0, x20
    ldr     x1, [sp, #16]
    add     x2, x22, #192
    add     x4, x22, #128
    bl      lantern_route_value
    cbnz    x0, 9f
    ldr     x9, [sp, #16]
    cmp     x9, #API_PARAM_STATUS
    b.eq    5f
    mov     x9, #64                         /* an id: into out, while there is room */
    madd    x10, x27, x9, x9
    add     x10, x10, #API_ROUTE_FIXED
    ldr     x11, [x20]
    cmp     x10, x11
    b.ls    41f
    mov     x11, #1
    str     x11, [x22, #56]
    b       42f
41: sub     x10, x10, x9
    add     x10, x20, x10
    add     x11, x22, #128
411: ldr    x12, [x11], #8
    str     x12, [x10], #8
    subs    x9, x9, #8
    b.ne    411b
42: add     x27, x27, #1
5:  ldr     x9, [sp, #16]                   /* the parameter is given */
    mov     x10, #1
    lsl     x10, x10, x9
    orr     x26, x26, x10
    bl      lantern_route_ws                        /* then , or ] */
    cmp     x21, x25
    b.hs    8f
    ldrb    w9, [x21], #1
    cmp     w9, #','
    b.eq    2b
    cmp     w9, #']'
    b.ne    8f
7:  mov     x0, #0
    UNFRAME 16
8:  mov     x0, #1
    UNFRAME 16
9:  ldr     x0, [sp, #16]
    add     x0, x0, #1
    UNFRAME 16
END_FUNCTION lantern_route_ids_array

/*
 * The weight, 0 to 1000, that the Accept value of x1 bytes at x0 gives the media type of x3
 * lower case bytes at x2 (lantern_api_route's rules). x19 bytes, x20 length, x21 media, x22 its
 * length, x23 the best kind of range (-1 none, 0 any type, 1 any application type, 2 the type), x24 its weight,
 * x25 an item's start, x26 its end, x27 a parameter's start, x28 a range's kind; L the item's weight.
 */
LOCAL_FUNCTION lantern_route_weight
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, #-1
    mov     x24, #0
    mov     x25, #0
1:  cmp     x25, x20                        /* each item, up to a , */
    b.hi    9f
    mov     x0, x19
    mov     x1, x25
    mov     x2, x20
    mov     w3, #','
    bl      lantern_http_find
    mov     x26, x0
    mov     x0, x19                         /* the range: up to the first ; */
    mov     x1, x25
    mov     x2, x26
    mov     w3, #';'
    bl      lantern_http_find
    mov     x27, x0
    mov     x0, x19
    mov     x1, x25
    mov     x2, x27
    bl      lantern_http_trim
    stp     x0, x1, [sp, #L]
    add     x0, x19, x0
    ldr     x1, [sp, #(L + 8)]
    ldr     x9, [sp, #L]
    sub     x1, x1, x9
    mov     x2, x21
    mov     x3, x22
    bl      lantern_http_same
    mov     x28, #2
    cbnz    x0, 3f
    ldp     x9, x1, [sp, #L]
    add     x0, x19, x9
    sub     x1, x1, x9
    ADDRESS x2, route_t_any_application
    mov     x3, #api_t_any_application_len
    bl      lantern_http_same
    mov     x28, #1
    cbnz    x0, 3f
    ldp     x9, x1, [sp, #L]
    add     x0, x19, x9
    sub     x1, x1, x9
    ADDRESS x2, route_t_any
    mov     x3, #api_t_any_len
    bl      lantern_http_same
    mov     x28, #0
    cbz     x0, 8f                          /* a range of another type: skipped */
3:  mov     x9, #1000                       /* the parameters: q= sets the weight */
    str     x9, [sp, #L]
4:  cmp     x27, x26
    b.hs    7f
    add     x27, x27, #1
    mov     x0, x19
    mov     x1, x27
    mov     x2, x26
    mov     w3, #';'
    bl      lantern_http_find
    str     x0, [sp, #(L + 8)]
    mov     x2, x0
    mov     x0, x19
    mov     x1, x27
    bl      lantern_http_trim
    ldr     x27, [sp, #(L + 8)]
    sub     x10, x1, x0                     /* x0, x1: the parameter */
    cmp     x10, #2
    b.lo    4b
    add     x11, x19, x0
    ldrb    w12, [x11]
    orr     w12, w12, #0x20
    cmp     w12, #'q'
    b.ne    4b
    ldrb    w12, [x11, #1]
    cmp     w12, #'='
    b.ne    4b
    add     x11, x11, #2                    /* the value: 0, 0.ddd or 1, 1.000 */
    sub     x10, x10, #2
    cbz     x10, 8f
    cmp     x10, #1
    b.eq    5f
    cmp     x10, #5
    b.hi    8f
    ldrb    w12, [x11, #1]
    cmp     w12, #'.'
    b.ne    8f
5:  ldrb    w12, [x11]
    cmp     w12, #'1'
    b.eq    6f
    cmp     w12, #'0'
    b.ne    8f
    mov     x13, #0                         /* 0.ddd: the digits, then scaled to thousandths */
    mov     x14, #2
    mov     x15, #10
51: cmp     x14, x10
    b.hs    52f
    ldrb    w12, [x11, x14]
    sub     w12, w12, #'0'
    cmp     w12, #9
    b.hi    8f
    madd    x13, x13, x15, x12
    add     x14, x14, #1
    b       51b
52: cmp     x14, #5
    b.hs    53f
    mul     x13, x13, x15
    add     x14, x14, #1
    b       52b
53: cmp     x10, #1
    csel    x13, xzr, x13, eq
    str     x13, [sp, #L]
    b       4b
6:  mov     x14, #2                         /* 1.000 */
61: cmp     x14, x10
    b.hs    62f
    ldrb    w12, [x11, x14]
    cmp     w12, #'0'
    b.ne    8f
    add     x14, x14, #1
    b       61b
62: mov     x13, #1000
    str     x13, [sp, #L]
    b       4b
7:  ldr     x13, [sp, #L]                   /* the most specific range, then the heaviest */
    cmp     x28, x23
    b.gt    71f
    b.lt    8f
    cmp     x13, x24
    b.ls    8f
71: mov     x23, x28
    mov     x24, x13
8:  add     x25, x26, #1
    b       1b
9:  cmp     x23, #0
    csel    x0, x24, xzr, ge
    LEAVE 16
END_FUNCTION lantern_route_weight

/*
 * x19 the request, x20 out, x21 a path's start or a query item's start, x22 the path's length or
 * the item's end, x23 the operation's entry of api_routes, x24 the query, x25 its length, x26
 * present, x27 the list's items, x28 the parameter at hand. Locals: L the path parameters (a count,
 * then API_PARAM_*, start, end for each, 2 at most), L+56 1 when the list has no room, L+64 the
 * size of a list item, L+72 and L+80 the peer id's start and end in the path, L+88 its length,
 * L+96 the end of an item's name, L+104 a value's cursor, L+112 1 when a comma ended an item,
 * L+128 an item (64 bytes), L+192 a decoded value (200 bytes).
 */
FUNCTION lantern_api_route
    ENTER 400
    ldr     x9, [x1]
    cmp     x9, #API_ROUTE_FIXED
    b.lo    97f
    mov     x19, x0
    mov     x20, x1
    add     x9, x20, #8                     /* every field after size 0 */
    mov     x10, #((API_ROUTE_FIXED - 8) / 8)
1:  str     xzr, [x9], #8
    subs    x10, x10, #1
    b.ne    1b
    add     x9, sp, #L
    mov     x10, #8
2:  stp     xzr, xzr, [x9], #16
    subs    x10, x10, #1
    b.ne    2b
    mov     x26, #0
    mov     x27, #0
    mov     x28, #0
    ldp     x9, x22, [x19, #HttpRequest_path]
    add     x21, x19, x9
    ldp     x9, x25, [x19, #HttpRequest_query]
    add     x24, x19, x9
    mov     x0, x21                         /* the path: its percent-encoding, then its template */
    mov     x1, x22
    bl      lantern_route_pct_ok
    cbz     x0, 400f
    ADDRESS x23, api_routes
    mov     x10, #API_OPS
3:  ADDRESS x2, api_route_text
    ldr     x9, [x23]
    add     x2, x2, x9
    ldr     x3, [x23, #8]
    and     x3, x3, #0xffff
    mov     x0, x21
    mov     x1, x22
    add     x4, sp, #L
    str     x10, [sp, #(L + 120)]
    bl      lantern_route_match
    ldr     x10, [sp, #(L + 120)]
    cbnz    x0, 4f
    add     x23, x23, #32
    subs    x10, x10, #1
    b.ne    3b
    b       404f
4:  ldr     x13, [x23]                      /* allow: the methods of the template; the operation of the method */
    ldr     x15, [x19, #HttpRequest_method]
    ADDRESS x9, api_routes
    mov     x10, #API_OPS
    mov     x11, #0
    mov     x14, #0
5:  ldr     x12, [x9]
    cmp     x12, x13
    b.ne    6f
    ldr     x12, [x9, #8]
    ubfx    x12, x12, #16, #8
    sub     x6, x12, #1
    mov     x7, #1
    lsl     x7, x7, x6
    orr     x11, x11, x7
    cmp     x12, x15
    b.ne    6f
    cbnz    x14, 6f
    mov     x14, x9
6:  add     x9, x9, #32
    subs    x10, x10, #1
    b.ne    5b
    str     x11, [x20, #ApiRoute_allow]
    cbz     x14, 405f
    mov     x23, x14
    ADDRESS x9, api_routes
    sub     x9, x23, x9
    lsr     x9, x9, #5
    add     x9, x9, #1
    str     x9, [x20, #ApiRoute_op]
    mov     x0, x24                         /* the query's percent-encoding */
    mov     x1, x25
    bl      lantern_route_pct_ok
    cbz     x0, 400f
    add     x21, sp, #(L + 8)               /* the path parameters */
    ldr     x22, [sp, #L]
7:  cbz     x22, 20f
    ldr     x28, [x21]
    ldp     x9, x10, [x19, #HttpRequest_path]
    add     x0, x19, x9
    ldp     x9, x10, [x21, #8]
    add     x0, x0, x9
    sub     x1, x10, x9
    add     x2, sp, #(L + 192)
    mov     x3, #200
    bl      lantern_route_decode
    cmp     x0, #200
    b.hi    401f
    mov     x3, x0
    str     x0, [sp, #(L + 88)]
    mov     x0, x20
    mov     x1, x28
    add     x2, sp, #(L + 192)
    add     x4, sp, #(L + 128)
    bl      lantern_route_value
    cbnz    x0, 401f
    mov     x9, #1
    lsl     x9, x9, x28
    orr     x26, x26, x9
    cmp     x28, #API_PARAM_PEER_ID         /* the peer id: written once the room is known */
    b.ne    8f
    ldp     x9, x10, [x21, #8]
    stp     x9, x10, [sp, #(L + 72)]
    b       9f
8:  str     xzr, [sp, #(L + 88)]
9:  add     x21, x21, #24
    sub     x22, x22, #1
    b       7b
20: mov     x21, #0                         /* each query item */
21: cmp     x21, x25
    b.hs    40f
    mov     x0, x24
    mov     x1, x21
    mov     x2, x25
    mov     w3, #'&'
    bl      lantern_http_find
    mov     x22, x0
    cmp     x22, x21
    b.eq    39f
    mov     x0, x24                         /* the name, up to the first = */
    mov     x1, x21
    mov     x2, x22
    mov     w3, #'='
    bl      lantern_http_find
    str     x0, [sp, #(L + 96)]
    sub     x1, x0, x21
    add     x0, x24, x21
    add     x2, sp, #(L + 192)
    mov     x3, #32
    bl      lantern_route_decode
    cmp     x0, #32
    b.hi    39f
    ldr     x10, [x23, #16]                 /* a parameter the operation takes, by name */
    mov     x28, #1
22: cmp     x28, #API_PARAMS
    b.hi    39f
    lsr     x11, x10, x28
    tbz     x11, #0, 24f
    ADDRESS x12, api_params
    add     x12, x12, x28, lsl #5
    ldr     x13, [x12, #8]
    cmp     x13, x0
    b.ne    24f
    ldr     x14, [x12]
    ADDRESS x15, api_param_text
    add     x14, x15, x14
    add     x15, sp, #(L + 192)
    mov     x6, #0
23: cmp     x6, x0
    b.hs    25f
    ldrb    w7, [x15, x6]
    ldrb    w8, [x14, x6]
    cmp     w7, w8
    b.ne    24f
    add     x6, x6, #1
    b       23b
24: add     x28, x28, #1
    b       22b
25: ldr     x9, [sp, #(L + 96)]             /* the value: after the =, or empty */
    cmp     x9, x22
    b.hs    26f
    add     x9, x9, #1
26: str     x9, [sp, #(L + 104)]
    mov     x10, #1
    lsl     x10, x10, x28
    ADDRESS x12, api_params
    add     x12, x12, x28, lsl #5
    ldr     x11, [x12, #16]
    cmp     x11, #API_KIND_SET
    b.hs    30f
    tst     x26, x10                        /* one value: given once */
    b.ne    401f
    orr     x26, x26, x10
    add     x0, x24, x9
    sub     x1, x22, x9
    add     x2, sp, #(L + 192)
    mov     x3, #200
    bl      lantern_route_decode
    cmp     x0, #200
    b.hi    401f
    mov     x3, x0
    mov     x0, x20
    mov     x1, x28
    add     x2, sp, #(L + 192)
    add     x4, sp, #(L + 128)
    bl      lantern_route_value
    cbnz    x0, 401f
    b       39f
30: orr     x26, x26, x10                   /* a list or a set: each item */
    mov     x9, #64
    cmp     x11, #API_KIND_ID_LIST
    b.eq    31f
    mov     x9, #8
    cmp     x11, #API_KIND_INDEX_LIST
    b.eq    31f
    mov     x9, #32
    cmp     x11, #API_KIND_HASH_LIST
    b.eq    31f
    mov     x9, #0
31: str     x9, [sp, #(L + 64)]
32: cmp     x28, #API_PARAM_ID              /* the 65th id */
    b.ne    33f
    ldr     x11, [x23, #8]
    tst     x11, #(API_FLAG_ID_MAX << 24)
    b.eq    33f
    cmp     x27, #64
    b.eq    414f
33: mov     x0, x24
    ldr     x1, [sp, #(L + 104)]
    mov     x2, x22
    add     x3, sp, #(L + 192)
    mov     x4, #200
    bl      lantern_route_next_item
    stp     x0, x2, [sp, #(L + 104)]
    cbz     x1, 401f
    cmp     x1, #200
    b.hi    401f
    mov     x3, x1
    mov     x0, x20
    mov     x1, x28
    add     x2, sp, #(L + 192)
    add     x4, sp, #(L + 128)
    bl      lantern_route_value
    cbnz    x0, 401f
    ldr     x9, [sp, #(L + 64)]             /* a list item: into out, while there is room */
    cbz     x9, 36f
    madd    x10, x27, x9, x9
    add     x10, x10, #API_ROUTE_FIXED
    ldr     x11, [x20]
    cmp     x10, x11
    b.ls    34f
    mov     x11, #1
    str     x11, [sp, #(L + 56)]
    b       35f
34: sub     x10, x10, x9
    add     x10, x20, x10
    add     x11, sp, #(L + 128)
341: ldr    x12, [x11], #8
    str     x12, [x10], #8
    subs    x9, x9, #8
    b.ne    341b
35: add     x27, x27, #1
36: ldr     x9, [sp, #(L + 112)]
    cbnz    x9, 32b
39: add     x21, x22, #1
    b       21b
40: ldr     x9, [x23, #24]                  /* required parameters */
    bic     x9, x9, x26
    cbz     x9, 41f
    rbit    x9, x9
    clz     x28, x9
    b       401f
41: ldr     x11, [x23, #8]                  /* Eth-Consensus-Version */
    tst     x11, #(API_FLAG_VERSION << 24)
    b.eq    42f
    mov     x28, #API_PARAM_CONSENSUS_VERSION
    ldp     x9, x2, [x19, #HttpRequest_consensus_version]
    add     x1, x19, x9
    mov     x0, x28
    bl      lantern_route_word
    cbz     x0, 401f
    str     x1, [x20, #ApiRoute_consensus_version]
    orr     x26, x26, #(1 << API_PARAM_CONSENSUS_VERSION)
42: ldr     x9, [x19, #HttpRequest_method]  /* Content-Type */
    cmp     x9, #HTTP_METHOD_POST
    b.ne    44f
    mov     x9, #API_TYPE_JSON
    str     x9, [x20, #ApiRoute_body]
    ldr     x11, [x23, #8]
    tst     x11, #(API_FLAG_SSZ_BODY << 24)
    b.eq    44f
    ldp     x9, x2, [x19, #HttpRequest_content_type]
    cbz     x2, 44f
    add     x21, x19, x9
    mov     x0, x21
    mov     x1, #0
    mov     w3, #';'
    bl      lantern_http_find
    mov     x2, x0
    mov     x0, x21
    mov     x1, #0
    bl      lantern_http_trim
    add     x21, x21, x0
    sub     x22, x1, x0
    mov     x0, x21
    mov     x1, x22
    ADDRESS x2, route_t_ssz
    mov     x3, #api_t_ssz_len
    bl      lantern_http_same
    cbz     x0, 43f
    mov     x9, #API_TYPE_SSZ
    str     x9, [x20, #ApiRoute_body]
    b       44f
43: mov     x0, x21
    mov     x1, x22
    ADDRESS x2, route_t_json
    mov     x3, #api_t_json_len
    bl      lantern_http_same
    cbz     x0, 415f
44: ldr     x11, [x23, #8]                  /* the JSON body of ids */
    tst     x11, #((API_FLAG_IDS_OBJECT | API_FLAG_IDS_ARRAY) << 24)
    b.eq    45f
    ldp     x9, x10, [x19, #HttpRequest_body]
    add     x24, x19, x9
    add     x25, x24, x10
    mov     x21, x24
    add     x22, sp, #L
    mov     x9, #64
    str     x9, [sp, #(L + 64)]
    tst     x11, #(API_FLAG_IDS_OBJECT << 24)
    b.ne    51f
    cbz     x10, 45f                        /* an array: no body, null, or the ids */
    bl      lantern_route_ws
    mov     x0, #API_PARAM_ID
    bl      lantern_route_ids_array
    cbnz    x0, 59f
    b       58f
51: bl      lantern_route_ws                        /* an object: {"ids":…,"statuses":…} */
    cmp     x21, x25
    b.hs    400f
    ldrb    w9, [x21], #1
    cmp     w9, #'{'
    b.ne    400f
    str     xzr, [sp, #(L + 96)]            /* the members seen: 1 ids, 2 statuses */
    bl      lantern_route_ws
    cmp     x21, x25
    b.hs    400f
    ldrb    w9, [x21]
    cmp     w9, #'}'
    b.ne    52f
    add     x21, x21, #1
    b       58f
52: bl      lantern_route_ws                        /* a member: its key, once */
    bl      lantern_route_string
    cbnz    x0, 400f
    bl      lantern_route_key
    mov     x28, x0
    cbz     x28, 400f
    cmp     x28, #API_PARAM_ID
    mov     x12, #1
    mov     x9, #2
    csel    x12, x12, x9, eq
53: ldr     x9, [sp, #(L + 96)]
    tst     x9, x12
    b.ne    400f
    orr     x9, x9, x12
    str     x9, [sp, #(L + 96)]
    bl      lantern_route_ws
    cmp     x21, x25
    b.hs    400f
    ldrb    w9, [x21], #1
    cmp     w9, #':'
    b.ne    400f
    bl      lantern_route_ws
    mov     x0, x28
    bl      lantern_route_ids_array
    cbnz    x0, 59f
    bl      lantern_route_ws                        /* then , or } */
    cmp     x21, x25
    b.hs    400f
    ldrb    w9, [x21], #1
    cmp     w9, #','
    b.eq    52b
    cmp     w9, #'}'
    b.ne    400f
58: bl      lantern_route_ws                        /* nothing after the value */
    cmp     x21, x25
    b.ne    400f
    b       45f
59: sub     x28, x0, #1                     /* the fault */
    b       401f
45: mov     x9, #API_TYPE_JSON              /* Accept */
    str     x9, [x20, #ApiRoute_response]
    ldr     x11, [x23, #8]
    tst     x11, #(API_FLAG_SSZ_RESPONSE << 24)
    b.eq    46f
    ldp     x9, x22, [x19, #HttpRequest_accept]
    cbz     x22, 46f
    add     x21, x19, x9
    mov     x0, x21
    mov     x1, x22
    ADDRESS x2, route_t_json
    mov     x3, #api_t_json_len
    bl      lantern_route_weight
    mov     x28, x0
    mov     x0, x21
    mov     x1, x22
    ADDRESS x2, route_t_ssz
    mov     x3, #api_t_ssz_len
    bl      lantern_route_weight
    orr     x9, x0, x28
    cbz     x9, 406f
    cmp     x0, x28
    b.ls    46f
    mov     x9, #API_TYPE_SSZ
    str     x9, [x20, #ApiRoute_response]
46: ldr     x9, [sp, #(L + 56)]             /* the room: the list, then the peer id */
    cbnz    x9, 97f
    ldr     x9, [sp, #(L + 64)]
    mul     x21, x27, x9
    ldr     x22, [sp, #(L + 88)]
    add     x9, x22, #7
    and     x9, x9, #-8
    add     x9, x9, x21
    add     x9, x9, #API_ROUTE_FIXED
    ldr     x10, [x20]
    cmp     x9, x10
    b.hi    97f
    cbz     x27, 47f
    mov     x9, #API_ROUTE_FIXED
    stp     x9, x27, [x20, #ApiRoute_list]
47: cbz     x22, 48f
    add     x21, x21, #API_ROUTE_FIXED
    stp     x21, x22, [x20, #ApiRoute_peer_id]
    ldp     x9, x10, [x19, #HttpRequest_path]
    add     x0, x19, x9
    ldp     x9, x10, [sp, #(L + 72)]
    add     x0, x0, x9
    sub     x1, x10, x9
    add     x2, x20, x21
    mov     x3, x22
    bl      lantern_route_decode
    add     x9, x21, x22                    /* zero bytes up to a multiple of 8 */
471: tst    x9, #7
    b.eq    48f
    strb    wzr, [x20, x9]
    add     x9, x9, #1
    b       471b
48: ldr     x9, [x23, #16]                  /* broadcast_validation: 1 when it is missing */
    tbz     x9, #API_PARAM_BROADCAST_VALIDATION, 49f
    tbnz    x26, #API_PARAM_BROADCAST_VALIDATION, 49f
    mov     x9, #1
    str     x9, [x20, #ApiRoute_broadcast_validation]
49: str     x26, [x20, #ApiRoute_present]
    mov     x0, #LANTERN_OK
    LEAVE 400
400: mov    x28, #0
401: mov    x9, #400
    b       96f
404: mov    x9, #404
    mov     x28, #0
    b       96f
405: mov    x9, #405
    mov     x28, #0
    b       96f
406: mov    x9, #406
    mov     x28, #0
    b       96f
414: mov    x9, #414
    b       96f
415: mov    x9, #415
    mov     x28, #0
96: str     x9, [x20, #ApiRoute_status]
    str     x28, [x20, #ApiRoute_fault]
    mov     x0, #LANTERN_INVALID_ROUTE
    LEAVE 400
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 400
END_FUNCTION lantern_api_route
