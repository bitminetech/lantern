/*
 * Engine API client, ARM64: the JWT and HTTP/1.1 functions of the common object.
 * Requirements: docs/reference/engine-api.md.
 */

/* L0: lantern_base64url of the x1 bytes at x0, without padding, to x2; x2 = the end. Uses x9-x13. */
LOCAL_FUNCTION lantern_base64url
    UNWIND_END_PROLOGUE
    ADDRESS x13, base64url_alphabet
1:  cmp     x1, #3
    b.lo    2f
    ldrb    w9, [x0]
    ldrb    w10, [x0, #1]
    ldrb    w11, [x0, #2]
    add     x0, x0, #3
    sub     x1, x1, #3
    orr     w9, w11, w9, lsl #16
    orr     w9, w9, w10, lsl #8
    lsr     w10, w9, #18
    ldrb    w10, [x13, x10]
    strb    w10, [x2], #1
    ubfx    w10, w9, #12, #6
    ldrb    w10, [x13, x10]
    strb    w10, [x2], #1
    ubfx    w10, w9, #6, #6
    ldrb    w10, [x13, x10]
    strb    w10, [x2], #1
    and     w10, w9, #63
    ldrb    w10, [x13, x10]
    strb    w10, [x2], #1
    b       1b
2:  cbz     x1, 4f
    ldrb    w9, [x0]
    lsl     w9, w9, #16
    cmp     x1, #2
    b.lo    3f
    ldrb    w10, [x0, #1]
    orr     w9, w9, w10, lsl #8
3:  lsr     w10, w9, #18                    /* 1 byte: 2 characters; 2 bytes: 3 */
    ldrb    w10, [x13, x10]
    strb    w10, [x2], #1
    ubfx    w10, w9, #12, #6
    ldrb    w10, [x13, x10]
    strb    w10, [x2], #1
    cmp     x1, #2
    b.lo    4f
    ubfx    w10, w9, #6, #6
    ldrb    w10, [x13, x10]
    strb    w10, [x2], #1
4:  ret
END_FUNCTION lantern_base64url

/* L0: the decimal digits of x0 to x1; x1 = the end. Uses x9-x12. */
LOCAL_FUNCTION lantern_decimal
    UNWIND_END_PROLOGUE
    mov     x12, #10                        /* count the digits, then write them from the last */
    mov     x9, x0
1:  udiv    x9, x9, x12
    add     x1, x1, #1
    cbnz    x9, 1b
    mov     x9, x1
2:  udiv    x10, x0, x12
    msub    x11, x10, x12, x0
    add     w11, w11, #'0'
    strb    w11, [x9, #-1]!
    mov     x0, x10
    cbnz    x0, 2b
    ret
END_FUNCTION lantern_decimal

/* L0: the x1 bytes at x0 to x2; x2 = the end. Uses x9. */
LOCAL_FUNCTION lantern_put_bytes
    UNWIND_END_PROLOGUE
    cbz     x1, 2f
1:  ldrb    w9, [x0], #1
    strb    w9, [x2], #1
    subs    x1, x1, #1
    b.ne    1b
2:  ret
END_FUNCTION lantern_put_bytes

/*
 * (secret, iat, scratch, out): x19 secret, x20 iat, x21 scratch, x22 out, x23 the token's end.
 * Scratch: its size, the key's ByteList at +8, the signing input's ByteList at +64 (bytes
 * at +88), HMAC's scratch at +176. Locals: L the claims JSON, L+32 the MAC.
 */
FUNCTION lantern_jwt_token
    ENTER 64
    mov     x19, x0
    ldr     x20, [x1]
    mov     x21, x2
    mov     x22, x3
    ldr     x9, [x22]
    cmp     x9, #(24 + 128)
    b.lo    8f
    ldr     x9, [x21]
    cmp     x9, #512
    b.lo    8f
    mov     x9, #56                         /* the key: a ByteList of the 32 bytes */
    mov     x10, #24
    mov     x11, #32
    stp     x9, x10, [x21, #8]
    str     x11, [x21, #24]
    ldp     x9, x10, [x19]
    stp     x9, x10, [x21, #32]
    ldp     x9, x10, [x19, #16]
    stp     x9, x10, [x21, #48]
    ADDRESS x0, jwt_header                  /* lantern_base64url(header) + . */
    mov     x1, #37
    add     x2, x21, #88
    bl      lantern_put_bytes
    mov     x23, x2
    mov     w9, #'{'                        /* the claims: {"iat":<iat>} */
    strb    w9, [sp, #L]
    ADDRESS x0, jwt_claims
    mov     x1, #6
    add     x2, sp, #(L + 1)
    bl      lantern_put_bytes
    mov     x0, x20
    mov     x1, x2
    bl      lantern_decimal
    mov     w9, #'}'
    strb    w9, [x1], #1
    add     x0, sp, #L
    sub     x1, x1, x0
    mov     x2, x23
    bl      lantern_base64url
    add     x9, x21, #88                    /* the signing input's ByteList */
    sub     x10, x2, x9
    mov     x11, #24
    mov     x12, #112
    stp     x12, x11, [x21, #64]
    str     x10, [x21, #80]
    mov     x23, x2
    add     x0, x21, #8                     /* HMAC-SHA256(secret, signing input) */
    add     x1, x21, #64
    add     x2, x21, #176
    ldr     x9, [x21]
    sub     x9, x9, #176
    str     x9, [x2]
    add     x3, sp, #(L + 32)
    CALL_GLOBAL crypto_hmac_sha256
    cbnz    x0, 8f
    add     x0, x21, #88                    /* out: the signing input, ., lantern_base64url(mac) */
    sub     x1, x23, x0
    add     x2, x22, #24
    bl      lantern_put_bytes
    mov     w9, #'.'
    strb    w9, [x2], #1
    add     x0, sp, #(L + 32)
    mov     x1, #32
    bl      lantern_base64url
    add     x9, x22, #24
    sub     x10, x2, x9
    mov     x11, #24
    stp     x11, x10, [x22, #8]
    mov     x0, #LANTERN_OK
    LEAVE 64
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_jwt_token

/* (host, token, body, out): x19-x22 the arguments, x23 the request's length. Locals: L the length's digits. */
FUNCTION lantern_http_post
    ENTER 32
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    ldr     x0, [x21, #16]                  /* the body's length in decimal */
    add     x1, sp, #L
    bl      lantern_decimal
    add     x9, sp, #L
    sub     x24, x1, x9                     /* its digits */
    ldr     x23, [x19, #16]                 /* the request's length */
    ldr     x9, [x20, #16]
    add     x23, x23, x9
    ldr     x9, [x21, #16]
    add     x23, x23, x9
    add     x23, x23, x24
    add     x23, x23, #(23 + 56 + 18 + 4)
    ldr     x9, [x22]
    subs    x9, x9, #24
    b.lo    8f
    cmp     x9, x23
    b.lo    8f
    mov     x9, #24
    stp     x9, x23, [x22, #8]
    add     x2, x22, #24
    ADDRESS x0, http_post_1                 /* POST / HTTP/1.1, Host: */
    mov     x1, #23
    bl      lantern_put_bytes
    ldr     x9, [x19, #8]
    add     x0, x19, x9
    ldr     x1, [x19, #16]
    bl      lantern_put_bytes
    ADDRESS x0, http_post_2                 /* Content-Type, Authorization: Bearer */
    mov     x1, #56
    bl      lantern_put_bytes
    ldr     x9, [x20, #8]
    add     x0, x20, x9
    ldr     x1, [x20, #16]
    bl      lantern_put_bytes
    ADDRESS x0, http_post_3                 /* Content-Length: */
    mov     x1, #18
    bl      lantern_put_bytes
    add     x0, sp, #L
    mov     x1, x24
    bl      lantern_put_bytes
    ADDRESS x0, http_crlf2
    mov     x1, #4
    bl      lantern_put_bytes
    ldr     x9, [x21, #8]
    add     x0, x21, x9
    ldr     x1, [x21, #16]
    bl      lantern_put_bytes
    mov     x0, #LANTERN_OK
    LEAVE 32
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION lantern_http_post

/*
 * L0: x0 = the position of the CR LF at or after x2 in the x1 bytes at x0, or 2^64 - 1 when
 * there is none. Uses x9, x10.
 */
LOCAL_FUNCTION lantern_find_crlf
    UNWIND_END_PROLOGUE
    mov     x9, x2
1:  add     x10, x9, #1
    cmp     x10, x1
    b.hs    3f
    ldrb    w10, [x0, x9]
    cmp     w10, #13
    b.ne    2f
    add     x10, x0, x9
    ldrb    w10, [x10, #1]
    cmp     w10, #10
    b.eq    4f
2:  add     x9, x9, #1
    b       1b
3:  mov     x9, #-1
4:  mov     x0, x9
    ret
END_FUNCTION lantern_find_crlf

/* Whether the x11 bytes at x10 are the name at label (lowercase): x9 = 1 or 0. Uses x12-x14. */
.macro HEADER_IS label, n
    mov     x9, #0
    cmp     x11, #\n
    b.ne    93f
    ADDRESS x12, \label
    mov     x13, #0
91: ldrb    w14, [x10, x13]
    sub     w9, w14, #'A'                   /* to lowercase */
    cmp     w9, #26
    b.hs    92f
    add     w14, w14, #32
92: ldrb    w9, [x12, x13]
    cmp     w14, w9
    mov     x9, #0
    b.ne    93f
    add     x13, x13, #1
    cmp     x13, #\n
    b.lo    91b
    mov     x9, #1
93:
.endm

/*
 * (input, eof, body, out): x19 the bytes, x20 their count, x21 eof, x22 body, x23 out,
 * x24 the position, x25 the status, x26 Content-Length or 2^64 - 1, x27 1 for chunked,
 * 2 for another transfer coding, x28 the body's length so far.
 */
FUNCTION lantern_http_parse_response
    ENTER 16
    ldr     x9, [x0, #8]
    add     x19, x0, x9
    ldr     x20, [x0, #16]
    ldr     x21, [x1]
    mov     x22, x2
    mov     x23, x3
    mov     x0, x19                         /* the status line */
    mov     x1, x20
    mov     x2, #0
    bl      lantern_find_crlf
    cmn     x0, #1
    b.eq    7f
    mov     x24, x0
    cmp     x24, #13                        /* HTTP/1.d ddd SP */
    b.lo    9f
    ADDRESS x9, http_version
    mov     x10, #0
1:  ldrb    w11, [x19, x10]
    ldrb    w12, [x9, x10]
    cmp     w11, w12
    b.ne    9f
    add     x10, x10, #1
    cmp     x10, #7
    b.lo    1b
    ldrb    w11, [x19, #7]
    sub     w11, w11, #'0'
    cmp     w11, #10
    b.hs    9f
    ldrb    w11, [x19, #8]
    cmp     w11, #' '
    b.ne    9f
    mov     x25, #0
    mov     x10, #9
2:  ldrb    w11, [x19, x10]
    sub     w11, w11, #'0'
    cmp     w11, #10
    b.hs    9f
    mov     x12, #10
    madd    x25, x25, x12, x11
    add     x10, x10, #1
    cmp     x10, #12
    b.lo    2b
    ldrb    w11, [x19, #12]
    cmp     w11, #' '
    b.ne    9f
    mov     x10, #13                        /* the reason phrase: no CR, no LF */
3:  cmp     x10, x24
    b.hs    4f
    ldrb    w11, [x19, x10]
    cmp     w11, #13
    b.eq    9f
    cmp     w11, #10
    b.eq    9f
    add     x10, x10, #1
    b       3b
4:  add     x24, x24, #2
    mov     x26, #-1
    mov     x27, #0
5:  mov     x0, x19                         /* each header line, to the empty line */
    mov     x1, x20
    mov     x2, x24
    bl      lantern_find_crlf
    cmn     x0, #1
    b.eq    7f
    cmp     x0, x24
    b.eq    20f
    str     x0, [sp, #L]                    /* the line's end */
    mov     x10, x24                        /* name: to the colon, no space, tab, CR or LF */
6:  cmp     x10, x0
    b.hs    9f
    ldrb    w11, [x19, x10]
    cmp     w11, #':'
    b.eq    10f
    cmp     w11, #' '
    b.eq    9f
    cmp     w11, #9
    b.eq    9f
    cmp     w11, #13
    b.eq    9f
    cmp     w11, #10
    b.eq    9f
    add     x10, x10, #1
    b       6b
10: sub     x11, x10, x24                   /* the name's length */
    cbz     x11, 9f
    add     x15, x10, #1                    /* the value: trimmed of spaces and tabs */
    mov     x16, x0
11: cmp     x15, x16
    b.hs    12f
    ldrb    w9, [x19, x15]
    cmp     w9, #' '
    ccmp    w9, #9, #4, ne
    b.ne    12f
    add     x15, x15, #1
    b       11b
12: cmp     x16, x15
    b.ls    13f
    sub     x9, x16, #1
    ldrb    w9, [x19, x9]
    cmp     w9, #' '
    ccmp    w9, #9, #4, ne
    b.ne    13f
    sub     x16, x16, #1
    b       12b
13: add     x10, x19, x24                   /* the name's bytes */
    HEADER_IS http_content_length, 14
    cbz     x9, 15f
    sub     x10, x16, x15                   /* Content-Length: a decimal number */
    cbz     x10, 9f
    mov     x9, #0
    mov     x12, #10
14: cmp     x15, x16
    b.hs    16f
    ldrb    w13, [x19, x15]
    sub     w13, w13, #'0'
    cmp     w13, #10
    b.hs    9f
    umulh   x14, x9, x12
    cbnz    x14, 9f
    mul     x9, x9, x12
    adds    x9, x9, x13
    b.cs    9f
    add     x15, x15, #1
    b       14b
16: cmn     x26, #1                         /* a second Content-Length must agree */
    b.eq    17f
    cmp     x26, x9
    b.ne    9f
17: mov     x26, x9
    b       19f
15: HEADER_IS http_transfer_encoding, 17
    cbz     x9, 19f
    mov     x27, #2                         /* chunked, or another coding */
    sub     x11, x16, x15
    add     x10, x19, x15
    HEADER_IS http_chunked, 7
    cbz     x9, 19f
    mov     x27, #1
19: ldr     x24, [sp, #L]                   /* the next line */
    add     x24, x24, #2
    b       5b
20: add     x24, x24, #2                    /* the body */
    mov     x28, #0
    cmp     x25, #200                       /* 1xx, 204 and 304: no body */
    b.lo    40f
    cmp     x25, #204
    b.eq    40f
    cmp     x25, #304
    b.eq    40f
    cmp     x27, #1
    b.ne    21f
    str     x24, [sp, #(L + 8)]             /* chunked: walk the chunks, then copy them */
    mov     x26, #0                         /* the pass: 0 walks, 1 copies */
    b       30f
21: cbnz    x27, 25f
    cmn     x26, #1
    b.eq    25f
    sub     x9, x20, x24                    /* Content-Length bytes */
    cmp     x9, x26
    b.lo    7f
    mov     x28, x26
    b       26f
25: cbz     x21, 7f                         /* every byte to the end of the connection */
    sub     x28, x20, x24
26: ldr     x9, [x22]                       /* copy the body */
    subs    x9, x9, #24
    b.lo    8f
    cmp     x9, x28
    b.lo    8f
    add     x0, x22, #24
    add     x1, x19, x24
    mov     x2, x28
    bl      lantern_copy
    add     x24, x24, x28
    b       40f
30: mov     x0, x19                         /* chunked: a chunk size line */
    mov     x1, x20
    mov     x2, x24
    bl      lantern_find_crlf
    cmn     x0, #1
    b.eq    7f
    mov     x9, #0
    mov     x10, x24
    cmp     x10, x0
    b.hs    9f
31: cmp     x10, x0
    b.hs    33f
    ldrb    w11, [x19, x10]
    cmp     w11, #';'
    b.eq    33f
    sub     w12, w11, #'0'
    cmp     w12, #10
    b.lo    32f
    orr     w11, w11, #0x20
    sub     w12, w11, #'a'
    cmp     w12, #6
    b.hs    9f
    add     w12, w12, #10
32: lsr     x13, x9, #60
    cbnz    x13, 9f
    orr     x9, x12, x9, lsl #4
    add     x10, x10, #1
    b       31b
33: cmp     x10, x24                        /* at least one digit */
    b.eq    9f
    add     x24, x0, #2
    cbz     x9, 36f
    sub     x10, x20, x24                   /* the data and its CR LF */
    cmp     x10, #2
    b.lo    7f
    sub     x10, x10, #2
    cmp     x10, x9
    b.lo    7f
    add     x10, x24, x9
    ldrb    w11, [x19, x10]
    cmp     w11, #13
    b.ne    9f
    add     x10, x10, #1
    ldrb    w11, [x19, x10]
    cmp     w11, #10
    b.ne    9f
    cbz     x26, 34f                        /* the copying pass */
    mov     x25, x9
    add     x0, x22, #24
    add     x0, x0, x28
    add     x1, x19, x24
    mov     x2, x9
    bl      lantern_copy
    mov     x9, x25
    ldr     x25, [x23, #HttpResponse_status]
34: adds    x28, x28, x9
    b.cs    9f
    add     x24, x24, x9
    add     x24, x24, #2
    b       30b
36: mov     x0, x19                         /* the trailer section, to its empty line */
    mov     x1, x20
    mov     x2, x24
    bl      lantern_find_crlf
    cmn     x0, #1
    b.eq    7f
    cmp     x0, x24
    add     x24, x0, #2
    b.ne    36b
    cbnz    x26, 40f                        /* the walk is done: room for the body, then copy */
    ldr     x9, [x22]
    subs    x9, x9, #24
    b.lo    8f
    cmp     x9, x28
    b.lo    8f
    str     x25, [x23, #HttpResponse_status]
    mov     x26, #1
    mov     x28, #0
    ldr     x24, [sp, #(L + 8)]
    b       30b
40: str     x25, [x23, #HttpResponse_status]
    str     x24, [x23, #HttpResponse_consumed]
    mov     x9, #24
    stp     x9, x28, [x22, #8]
    mov     x0, #LANTERN_OK
    LEAVE 16
7:  cbnz    x21, 9f                         /* more bytes to come, unless the connection has ended */
    mov     x0, #LANTERN_HTTP_MORE
    LEAVE 16
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
9:  mov     x0, #LANTERN_INVALID_HTTP
    LEAVE 16
END_FUNCTION lantern_http_parse_response

/* The text of engine_exchangeCapabilities, before the code that takes its lengths. */
    RODATA
.include "engine_caps.inc"

/* (id, out): the request of engine_exchangeCapabilities. x19 id, x20 out. */
FUNCTION lantern_engine_exchange_capabilities
    ENTER 0
    ldr     x19, [x0]
    mov     x20, x1
    ldr     x9, [x20]
    cmp     x9, #(24 + 512)
    b.lo    8f
    ADDRESS x0, j_caps_open
    mov     x1, #j_caps_open_len
    add     x2, x20, #24
    bl      lantern_put_bytes
    mov     x0, x19
    mov     x1, x2
    bl      lantern_decimal
    mov     x2, x1
    ADDRESS x0, j_caps_close
    mov     x1, #j_caps_close_len
    bl      lantern_put_bytes
    add     x9, x20, #24
    sub     x9, x2, x9
    mov     x10, #24
    stp     x10, x9, [x20, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
8:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_engine_exchange_capabilities

ENGINE_TEXT_DATA
