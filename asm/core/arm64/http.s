/*
 * lantern_http_request, ARM64: in the common object. Requirements: docs/reference/beacon-api.md.
 */

    RODATA
    .p2align 3
http_tchar:                                 /* the token characters of RFC 9110 section 5.6.2, a bit each */
    .quad   0x03ff6cfa00000000, 0x57ffffffc7fffffe, 0, 0
http_n_host:
    .ascii  "host"
.set http_n_host_len, 4
http_n_length:
    .ascii  "content-length"
.set http_n_length_len, 14
http_n_te:
    .ascii  "transfer-encoding"
.set http_n_te_len, 17
http_n_connection:
    .ascii  "connection"
.set http_n_connection_len, 10
http_n_accept:
    .ascii  "accept"
.set http_n_accept_len, 6
http_n_type:
    .ascii  "content-type"
.set http_n_type_len, 12
http_n_version:
    .ascii  "eth-consensus-version"
.set http_n_version_len, 21
http_t_chunked:
    .ascii  "chunked"
.set http_t_chunked_len, 7
http_t_close:
    .ascii  "close"
.set http_t_close_len, 5
http_t_keep_alive:
    .ascii  "keep-alive"
.set http_t_keep_alive_len, 10

/* x0, x1 = the label's address and its length (label_end - label). */
.macro HTTP_TEXT label
    ADDRESS x0, \label
    mov     x1, #\label\()_len
.endm

/* x0 = the index of the first byte w3 in [x1, x2) of x0's bytes, else x2. A leaf. Uses x9, x10. */
LOCAL_FUNCTION lantern_http_find
    UNWIND_END_PROLOGUE
    mov     x9, x0
1:  cmp     x1, x2
    b.hs    2f
    ldrb    w10, [x9, x1]
    cmp     w10, w3
    b.eq    2f
    add     x1, x1, #1
    b       1b
2:  mov     x0, x1
    ret
END_FUNCTION lantern_http_find

/* x0 = the index of the first CRLF that starts in [x1, x2 - 1) of x0's bytes, else x2. A leaf. Uses x9-x11. */
LOCAL_FUNCTION lantern_http_crlf
    UNWIND_END_PROLOGUE
    mov     x9, x0
    sub     x11, x2, #1
1:  cmp     x1, x11
    b.ge    2f
    ldrb    w10, [x9, x1]
    cmp     w10, #13
    b.ne    3f
    add     x10, x1, #1
    ldrb    w10, [x9, x10]
    cmp     w10, #10
    b.eq    4f
3:  add     x1, x1, #1
    b       1b
2:  mov     x0, x2
    ret
4:  mov     x0, x1
    ret
END_FUNCTION lantern_http_crlf

/* x0 = 1 when [x1, x2) of x0's bytes is a token (RFC 9110 section 5.6.2), else 0. A leaf. Uses x9-x13. */
LOCAL_FUNCTION lantern_http_token
    UNWIND_END_PROLOGUE
    mov     x9, x0
    cmp     x1, x2
    b.hs    8f
    ADDRESS x12, http_tchar
1:  cmp     x1, x2
    b.hs    9f
    ldrb    w10, [x9, x1]
    lsr     x11, x10, #6
    ldr     x13, [x12, x11, lsl #3]
    lsr     x13, x13, x10
    tbz     x13, #0, 8f
    add     x1, x1, #1
    b       1b
8:  mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION lantern_http_token

/* x0 = 1 when the x1 bytes at x0 are the x3 lower case bytes at x2, without regard to ASCII case, else 0. A leaf. Uses x9-x11. */
LOCAL_FUNCTION lantern_http_same
    UNWIND_END_PROLOGUE
    cmp     x1, x3
    b.ne    8f
1:  cbz     x1, 9f
    ldrb    w9, [x0], #1
    ldrb    w10, [x2], #1
    sub     w11, w9, #'A'
    cmp     w11, #25
    b.hi    2f
    add     w9, w9, #32
2:  cmp     w9, w10
    b.ne    8f
    sub     x1, x1, #1
    b       1b
8:  mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION lantern_http_same

/* [x1, x2) of x0's bytes without leading and trailing spaces and tabs: x0 = its start, x1 = its end. A leaf. Uses x9, x10. */
LOCAL_FUNCTION lantern_http_trim
    UNWIND_END_PROLOGUE
    mov     x9, x0
1:  cmp     x1, x2
    b.hs    3f
    ldrb    w10, [x9, x1]
    cmp     w10, #' '
    ccmp    w10, #9, #4, ne
    b.ne    3f
    add     x1, x1, #1
    b       1b
3:  cmp     x2, x1
    b.ls    4f
    sub     x10, x2, #1
    ldrb    w10, [x9, x10]
    cmp     w10, #' '
    ccmp    w10, #9, #4, ne
    b.ne    4f
    sub     x2, x2, #1
    b       3b
4:  mov     x0, x1
    mov     x1, x2
    ret
END_FUNCTION lantern_http_trim

/*
 * The x3 bytes at x2 become a part of HttpRequest x0 at offset x1, with its PartRef at x0 + x4:
 * x0 = x1 + x3 rounded up to a multiple of 8. A leaf. Uses x9, x10.
 */
LOCAL_FUNCTION lantern_http_part
    UNWIND_END_PROLOGUE
    add     x9, x0, x4
    stp     x1, x3, [x9]
    add     x9, x0, x1
    add     x1, x1, x3
1:  cbz     x3, 2f
    ldrb    w10, [x2], #1
    strb    w10, [x9], #1
    sub     x3, x3, #1
    b       1b
2:  add     x0, x1, #7
    and     x0, x0, #-8
    ret
END_FUNCTION lantern_http_part

/*
 * The chunked body that starts at index x3 of the x2 bytes at x1, with head_max x4 and body_max
 * x5 (lantern_http_request's rules). x0 = 0 checks it: x0 = LANTERN_OK with x1 the index past the
 * trailers and x2 the body's bytes, LANTERN_HTTP_MORE, or LANTERN_INVALID_HTTP with x1 the HTTP
 * status. x0 = a destination: a body checked before, its bytes copied there. A leaf. Uses x6-x17.
 */
LOCAL_FUNCTION lantern_http_chunks
    UNWIND_END_PROLOGUE
    mov     x6, x0                          /* the destination, or 0 */
    mov     x7, #0                          /* the body's bytes */
1:  mov     x8, x3                          /* a size line: find its CRLF */
    sub     x9, x2, #1
2:  cmp     x8, x9
    b.ge    3f
    ldrb    w10, [x1, x8]
    cmp     w10, #13
    b.ne    21f
    add     x10, x8, #1
    ldrb    w10, [x1, x10]
    cmp     w10, #10
    b.eq    4f
21: add     x8, x8, #1
    b       2b
3:  sub     x9, x2, x3                      /* no CRLF yet */
    cmp     x9, x4
    b.hi    80f
    b       90f
4:  sub     x9, x8, x3                      /* x8: the CRLF */
    cmp     x9, x4
    b.hi    80f
    mov     x9, x3                          /* the hex size */
    mov     x11, #0
5:  cmp     x9, x8
    b.hs    7f
    ldrb    w10, [x1, x9]
    sub     w12, w10, #'0'
    cmp     w12, #9
    b.ls    6f
    orr     w10, w10, #0x20
    sub     w12, w10, #'a'
    cmp     w12, #5
    b.hi    7f
    add     w12, w12, #10
6:  lsr     x13, x11, #60
    cbnz    x13, 80f                        /* past 2^64 - 1 */
    lsl     x11, x11, #4
    add     x11, x11, x12
    add     x9, x9, #1
    b       5b
7:  cmp     x9, x3
    b.eq    80f                             /* no hex digit */
    cmp     x9, x8
    b.hs    72f
    ldrb    w10, [x1, x9]                   /* an extension: ; space or tab, then no CR, LF or NUL */
    cmp     w10, #';'
    b.eq    71f
    cmp     w10, #' '
    b.eq    71f
    cmp     w10, #9
    b.ne    80f
71: cmp     x9, x8
    b.hs    72f
    ldrb    w10, [x1, x9]
    cbz     w10, 80f
    cmp     w10, #10
    b.eq    80f
    cmp     w10, #13
    b.eq    80f
    add     x9, x9, #1
    b       71b
72: add     x3, x8, #2
    cbz     x11, 10f                        /* the last chunk */
    sub     x9, x5, x7                      /* body_max */
    cmp     x11, x9
    b.hi    81f
    sub     x9, x2, x3
    cmp     x11, x9
    b.hi    90f
    sub     x9, x9, x11
    cmp     x9, #2
    b.lo    90f
    add     x9, x3, x11                     /* the data, then CRLF */
    ldrb    w10, [x1, x9]
    cmp     w10, #13
    b.ne    80f
    add     x9, x9, #1
    ldrb    w10, [x1, x9]
    cmp     w10, #10
    b.ne    80f
    cbz     x6, 9f
    add     x9, x1, x3                      /* copy the data */
    mov     x10, x11
8:  ldrb    w12, [x9], #1
    strb    w12, [x6], #1
    subs    x10, x10, #1
    b.ne    8b
9:  add     x7, x7, x11
    add     x3, x3, x11
    add     x3, x3, #2
    b       1b
10: mov     x14, #0                         /* trailer lines, skipped, up to the empty line */
11: mov     x8, x3
    sub     x9, x2, #1
12: cmp     x8, x9
    b.ge    13f
    ldrb    w10, [x1, x8]
    cmp     w10, #13
    b.ne    121f
    add     x10, x8, #1
    ldrb    w10, [x1, x10]
    cmp     w10, #10
    b.eq    14f
121: add    x8, x8, #1
    b       12b
13: sub     x9, x2, x3
    add     x9, x9, x14
    cmp     x9, x4
    b.hi    82f
    b       90f
14: add     x9, x8, #2
    sub     x9, x9, x3
    add     x14, x14, x9
    cmp     x14, x4
    b.hi    82f
    cmp     x8, x3                          /* the empty line ends them */
    add     x3, x8, #2
    b.ne    11b
    mov     x0, #LANTERN_OK
    mov     x1, x3
    mov     x2, x7
    ret
80: mov     x0, #LANTERN_INVALID_HTTP
    mov     x1, #400
    ret
81: mov     x0, #LANTERN_INVALID_HTTP
    mov     x1, #413
    ret
82: mov     x0, #LANTERN_INVALID_HTTP
    mov     x1, #431
    ret
90: mov     x0, #LANTERN_HTTP_MORE
    ret
END_FUNCTION lantern_http_chunks

/*
 * The values of the field lines named by the x4 lower case bytes at x3, between index x1 and the
 * head's CRLF CRLF at x2 of the bytes at x0, joined with ", ", become a part of HttpRequest x5 at
 * offset x6 with its PartRef at x5 + x7: x0 = the next part's offset. The lines are checked before.
 * x19 bytes, x20 the line, x21 the head's end, x22 name, x23 its length, x24 out, x25 the offset, x26
 * the PartRef, x27 the line's end, x28 the part's end.
 */
LOCAL_FUNCTION lantern_http_joined
    ENTER 16
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    add     x26, x5, x7
    str     xzr, [x26, #8]                  /* lines so far: 0 */
    mov     x28, x6                         /* the end so far */
1:  cmp     x20, x21
    b.hi    9f
    mov     x0, x19
    mov     x1, x20
    add     x2, x21, #2
    bl      lantern_http_crlf
    mov     x27, x0
    mov     x0, x19
    mov     x1, x20
    mov     x2, x27
    mov     w3, #':'
    bl      lantern_http_find
    str     x0, [sp, #L]                    /* the colon */
    add     x0, x19, x20
    ldr     x1, [sp, #L]
    sub     x1, x1, x20
    mov     x2, x22
    mov     x3, x23
    bl      lantern_http_same
    cbz     x0, 5f
    mov     x0, x19
    ldr     x1, [sp, #L]
    add     x1, x1, #1
    mov     x2, x27
    bl      lantern_http_trim
    ldr     x9, [x26, #8]                   /* ", " before all but the first line */
    cbz     x9, 2f
    mov     w9, #','
    strb    w9, [x24, x28]
    add     x28, x28, #1
    mov     w9, #' '
    strb    w9, [x24, x28]
    add     x28, x28, #1
2:  mov     x9, #1
    str     x9, [x26, #8]
3:  cmp     x0, x1
    b.hs    5f
    ldrb    w9, [x19, x0]
    strb    w9, [x24, x28]
    add     x0, x0, #1
    add     x28, x28, #1
    b       3b
5:  add     x20, x27, #2
    b       1b
9:  sub     x9, x28, x25
    stp     x25, x9, [x26]
    add     x0, x28, #7
    and     x0, x0, #-8
    LEAVE 16
END_FUNCTION lantern_http_joined

/*
 * The name of the field line at x26, x28 bytes before its colon, is the text at label: branch to dest.
 * Uses x0-x3, x9-x11.
 */
.macro HTTP_NAME label, dest
    add     x0, x19, x26
    mov     x1, x28
    ADDRESS x2, \label
    mov     x3, #\label\()_len
    bl      lantern_http_same
    cbnz    x0, \dest
.endm

/* acc += x9 rounded up to a multiple of 8. Uses x9. */
.macro HTTP_ROOM acc
    add     x9, x9, #7
    and     x9, x9, #-8
    add     \acc, \acc, x9
.endm

/*
 * x19 the bytes, x20 their count, x21 limits, x22 out, x23 the request line, x24 the head's CRLF CRLF,
 * x25 the request line's CRLF, x26 a line or an item, x27 the line's end, x28 a name's length or an item's end.
 * Locals: L method, L+8 version, L+16 target start, L+24 target end, L+32 Host lines, L+40
 * Transfer-Encoding lines, L+48 1 when one is chunked, L+56 Content-Length lines, L+64 its value,
 * L+72 1 when one is bad, L+80 the token close, L+88 the token keep-alive, L+96 Accept bytes and
 * L+104 lines, L+112 Content-Type bytes and L+120 lines, L+128 Eth-Consensus-Version bytes and
 * L+136 lines, L+144 body start, L+152 body bytes, L+160 used, L+168 a value's start, L+176 its end,
 * L+184 the path's end, L+192 1 once a length item is in, L+200 a token's start, L+208 its length.
 */
FUNCTION lantern_http_request
    ENTER 224
    ldr     x9, [x2]
    cmp     x9, #HTTP_REQUEST_FIXED
    b.lo    97f
    ldr     x9, [x0, #8]
    add     x19, x0, x9
    ldr     x20, [x0, #16]
    mov     x21, x1
    mov     x22, x2
    add     x9, sp, #L                      /* every local 0 */
    mov     x10, #14
1:  stp     xzr, xzr, [x9], #16
    subs    x10, x10, #1
    b.ne    1b
    mov     x23, #0                         /* empty lines before the request line */
2:  add     x9, x23, #2
    cmp     x9, x20
    b.hi    3f
    ldrb    w10, [x19, x23]
    cmp     w10, #13
    b.ne    3f
    add     x10, x23, #1
    ldrb    w10, [x19, x10]
    cmp     w10, #10
    b.ne    3f
    add     x23, x23, #2
    b       2b
3:  mov     x24, x23                        /* the head ends at the first CRLF CRLF */
    movz    w11, #0x0a0d
    movk    w11, #0x0a0d, lsl #16
4:  add     x9, x24, #4
    cmp     x9, x20
    b.hi    5f
    ldr     w10, [x19, x24]
    cmp     w10, w11
    b.eq    6f
    add     x24, x24, #1
    b       4b
5:  ldr     x9, [x21, #HttpLimits_head_max]
    cmp     x20, x9
    b.hs    431f
    b       98f
6:  add     x9, x24, #4
    ldr     x10, [x21, #HttpLimits_head_max]
    cmp     x9, x10
    b.hi    431f
    mov     x0, x19                         /* the request line: method SP target SP version */
    mov     x1, x23
    add     x2, x24, #2
    bl      lantern_http_crlf
    mov     x25, x0
    mov     x0, x19
    mov     x1, x23
    mov     x2, x25
    mov     w3, #' '
    bl      lantern_http_find
    cmp     x0, x25
    b.eq    400f
    mov     x26, x0                         /* the first space */
    mov     x0, x19
    mov     x1, x23
    mov     x2, x26
    bl      lantern_http_token
    cbz     x0, 400f
    mov     x0, x19
    add     x1, x26, #1
    mov     x2, x25
    mov     w3, #' '
    bl      lantern_http_find
    cmp     x0, x25
    b.eq    400f
    mov     x27, x0                         /* the second space */
    add     x9, x26, #1                     /* the target: / then visible bytes */
    str     x9, [sp, #(L + 16)]
    str     x27, [sp, #(L + 24)]
    cmp     x9, x27
    b.hs    400f
    ldrb    w10, [x19, x9]
    cmp     w10, #'/'
    b.ne    400f
7:  cmp     x9, x27
    b.hs    8f
    ldrb    w10, [x19, x9]
    sub     w10, w10, #0x21
    cmp     w10, #(0x7e - 0x21)
    b.hi    400f
    add     x9, x9, #1
    b       7b
8:  sub     x9, x25, x27                    /* the version: HTTP/ digit . digit */
    cmp     x9, #9
    b.ne    400f
    add     x9, x19, x27
    ldrb    w10, [x9, #1]
    cmp     w10, #'H'
    b.ne    400f
    ldrb    w10, [x9, #2]
    cmp     w10, #'T'
    b.ne    400f
    ldrb    w10, [x9, #3]
    cmp     w10, #'T'
    b.ne    400f
    ldrb    w10, [x9, #4]
    cmp     w10, #'P'
    b.ne    400f
    ldrb    w10, [x9, #5]
    cmp     w10, #'/'
    b.ne    400f
    ldrb    w10, [x9, #7]
    cmp     w10, #'.'
    b.ne    400f
    ldrb    w10, [x9, #6]
    sub     w10, w10, #'0'
    cmp     w10, #9
    b.hi    400f
    ldrb    w11, [x9, #8]
    sub     w11, w11, #'0'
    cmp     w11, #9
    b.hi    400f
    cmp     w10, #1
    b.ne    505f
    mov     x10, #11
    cmp     w11, #1
    b.eq    9f
    cbnz    w11, 505f
    mov     x10, #10
9:  str     x10, [sp, #(L + 8)]
    sub     x9, x26, x23                    /* the method */
    mov     x10, #HTTP_METHOD_OTHER
    add     x11, x19, x23
    cmp     x9, #3
    b.ne    10f
    ldrb    w12, [x11]
    cmp     w12, #'G'
    b.ne    11f
    ldrb    w12, [x11, #1]
    cmp     w12, #'E'
    b.ne    11f
    ldrb    w12, [x11, #2]
    cmp     w12, #'T'
    b.ne    11f
    mov     x10, #HTTP_METHOD_GET
    b       11f
10: cmp     x9, #4
    b.ne    11f
    ldrb    w12, [x11]
    cmp     w12, #'P'
    b.ne    11f
    ldrb    w12, [x11, #1]
    cmp     w12, #'O'
    b.ne    11f
    ldrb    w12, [x11, #2]
    cmp     w12, #'S'
    b.ne    11f
    ldrb    w12, [x11, #3]
    cmp     w12, #'T'
    b.ne    11f
    mov     x10, #HTTP_METHOD_POST
11: str     x10, [sp, #L]
    add     x26, x25, #2                    /* each field line, up to the head's CRLF CRLF */
12: cmp     x26, x24
    b.hi    30f
    mov     x0, x19
    mov     x1, x26
    add     x2, x24, #2
    bl      lantern_http_crlf
    mov     x27, x0
    ldrb    w10, [x19, x26]                 /* no folded line */
    cmp     w10, #' '
    b.eq    400f
    cmp     w10, #9
    b.eq    400f
    mov     x0, x19
    mov     x1, x26
    mov     x2, x27
    mov     w3, #':'
    bl      lantern_http_find
    cmp     x0, x27
    b.eq    400f
    sub     x28, x0, x26                    /* the name's length */
    cbz     x28, 400f
    mov     x0, x19
    mov     x1, x26
    add     x2, x26, x28
    bl      lantern_http_token
    cbz     x0, 400f
    mov     x0, x19                         /* the value, without spaces and tabs around it */
    add     x1, x26, x28
    add     x1, x1, #1
    mov     x2, x27
    bl      lantern_http_trim
    str     x0, [sp, #(L + 168)]
    str     x1, [sp, #(L + 176)]
    mov     x9, x0
13: cmp     x9, x1                          /* no CR, LF or NUL */
    b.hs    14f
    ldrb    w10, [x19, x9]
    cbz     w10, 400f
    cmp     w10, #10
    b.eq    400f
    cmp     w10, #13
    b.eq    400f
    add     x9, x9, #1
    b       13b
14: HTTP_NAME http_n_host, 20f
    HTTP_NAME http_n_length, 21f
    HTTP_NAME http_n_te, 22f
    HTTP_NAME http_n_connection, 23f
    HTTP_NAME http_n_accept, 24f
    HTTP_NAME http_n_type, 25f
    HTTP_NAME http_n_version, 26f
    b       29f
20: ldr     x9, [sp, #(L + 32)]             /* Host */
    add     x9, x9, #1
    str     x9, [sp, #(L + 32)]
    b       29f
21: ldr     x9, [sp, #(L + 56)]             /* Content-Length: a list of equal decimal values */
    add     x9, x9, #1
    str     x9, [sp, #(L + 56)]
    ldr     x26, [sp, #(L + 168)]
211: mov    x0, x19                         /* an item: up to the next comma */
    mov     x1, x26
    ldr     x2, [sp, #(L + 176)]
    mov     w3, #','
    bl      lantern_http_find
    mov     x28, x0
    mov     x0, x19
    mov     x1, x26
    mov     x2, x28
    bl      lantern_http_trim
    cmp     x0, x1
    b.hs    218f                            /* empty */
    mov     x9, #0
212: cmp    x0, x1
    b.hs    213f
    ldrb    w10, [x19, x0]
    sub     w10, w10, #'0'
    cmp     w10, #9
    b.hi    218f
    mov     x11, #10
    umulh   x12, x9, x11
    cbnz    x12, 218f
    mul     x9, x9, x11
    adds    x9, x9, x10
    b.cs    218f
    add     x0, x0, #1
    b       212b
213: ldr    x10, [sp, #(L + 192)]           /* the first item sets the length; the others match it */
    cbnz    x10, 214f
    str     x9, [sp, #(L + 64)]
    mov     x10, #1
    str     x10, [sp, #(L + 192)]
    b       215f
214: ldr    x10, [sp, #(L + 64)]
    cmp     x9, x10
    b.ne    218f
215: ldr    x10, [sp, #(L + 176)]
    cmp     x28, x10
    b.hs    29f
    add     x26, x28, #1
    b       211b
218: mov    x9, #1
    str     x9, [sp, #(L + 72)]
    b       29f
22: ldr     x9, [sp, #(L + 40)]             /* Transfer-Encoding */
    add     x9, x9, #1
    str     x9, [sp, #(L + 40)]
    ldp     x9, x10, [sp, #(L + 168)]
    add     x0, x19, x9
    sub     x1, x10, x9
    ADDRESS x2, http_t_chunked
    mov     x3, #http_t_chunked_len
    bl      lantern_http_same
    str     x0, [sp, #(L + 48)]
    b       29f
23: ldr     x26, [sp, #(L + 168)]           /* Connection: its tokens */
231: mov    x0, x19
    mov     x1, x26
    ldr     x2, [sp, #(L + 176)]
    mov     w3, #','
    bl      lantern_http_find
    mov     x28, x0
    mov     x0, x19
    mov     x1, x26
    mov     x2, x28
    bl      lantern_http_trim
    sub     x1, x1, x0
    stp     x0, x1, [sp, #(L + 200)]
    add     x0, x19, x0
    ADDRESS x2, http_t_close
    mov     x3, #http_t_close_len
    bl      lantern_http_same
    cbz     x0, 232f
    mov     x9, #1
    str     x9, [sp, #(L + 80)]
232: ldp    x0, x1, [sp, #(L + 200)]
    add     x0, x19, x0
    ADDRESS x2, http_t_keep_alive
    mov     x3, #http_t_keep_alive_len
    bl      lantern_http_same
    cbz     x0, 233f
    mov     x9, #1
    str     x9, [sp, #(L + 88)]
233: ldr    x10, [sp, #(L + 176)]
    cmp     x28, x10
    b.hs    29f
    add     x26, x28, #1
    b       231b
24: add     x9, sp, #(L + 96)               /* Accept, Content-Type, Eth-Consensus-Version: their joined bytes */
    b       27f
25: add     x9, sp, #(L + 112)
    b       27f
26: add     x9, sp, #(L + 128)
27: ldp     x10, x11, [x9]
    ldp     x12, x13, [sp, #(L + 168)]
    sub     x13, x13, x12
    cbz     x11, 28f
    add     x10, x10, #2
28: add     x10, x10, x13
    add     x11, x11, #1
    stp     x10, x11, [x9]
29: add     x26, x27, #2                    /* the next line */
    b       12b
30: ldr     x9, [sp, #(L + 32)]             /* Host: at most one; one in HTTP/1.1 */
    cmp     x9, #1
    b.hi    400f
    ldr     x10, [sp, #(L + 8)]
    cmp     x10, #11
    b.ne    31f
    cbz     x9, 400f
31: ldr     x9, [sp, #(L + 40)]             /* Transfer-Encoding: chunked alone */
    cbz     x9, 32f
    ldr     x10, [sp, #(L + 56)]
    cbnz    x10, 400f
    ldr     x10, [sp, #(L + 8)]
    cmp     x10, #10
    b.eq    400f
    cmp     x9, #1
    b.ne    501f
    ldr     x10, [sp, #(L + 48)]
    cbz     x10, 501f
32: ldr     x9, [sp, #(L + 56)]             /* Content-Length */
    cbz     x9, 33f
    ldr     x10, [sp, #(L + 72)]
    cbnz    x10, 400f
    ldr     x10, [sp, #(L + 64)]
    ldr     x11, [x21, #HttpLimits_body_max]
    cmp     x10, x11
    b.hi    413f
33: ldr     x9, [sp, #(L + 80)]             /* close: the token close, or HTTP/1.0 without keep-alive */
    cbnz    x9, 34f
    ldr     x10, [sp, #(L + 8)]
    cmp     x10, #10
    b.ne    35f
    ldr     x10, [sp, #(L + 88)]
    cbnz    x10, 35f
34: mov     x9, #1
35: str     x9, [sp, #(L + 80)]
    add     x26, x24, #4                    /* the body */
    str     x26, [sp, #(L + 144)]
    ldr     x9, [sp, #(L + 56)]
    cbz     x9, 36f
    ldr     x10, [sp, #(L + 64)]
    sub     x11, x20, x26
    cmp     x11, x10
    b.lo    98f
    str     x10, [sp, #(L + 152)]
    add     x26, x26, x10
    b       40f
36: ldr     x9, [sp, #(L + 40)]
    cbz     x9, 40f
    mov     x0, #0                          /* chunked: check the framing, count the bytes */
    mov     x1, x19
    mov     x2, x20
    mov     x3, x26
    ldp     x4, x5, [x21]
    bl      lantern_http_chunks
    cmp     x0, #LANTERN_HTTP_MORE
    b.eq    98f
    cmp     x0, #LANTERN_INVALID_HTTP
    b.ne    37f
    mov     x9, x1
    b       96f
37: mov     x26, x1
    str     x2, [sp, #(L + 152)]
40: str     x26, [sp, #(L + 160)]           /* used; then the room the parts need */
    mov     x0, x19
    ldp     x1, x2, [sp, #(L + 16)]
    mov     w3, #'?'
    bl      lantern_http_find
    str     x0, [sp, #(L + 184)]            /* the path's end */
    mov     x12, #HTTP_REQUEST_FIXED
    ldr     x10, [sp, #(L + 16)]
    sub     x9, x0, x10
    HTTP_ROOM x12
    ldr     x10, [sp, #(L + 24)]
    sub     x9, x10, x0
    cbz     x9, 41f
    sub     x9, x9, #1                      /* the query: after the ? */
41: HTTP_ROOM x12
    ldr     x9, [sp, #(L + 96)]
    HTTP_ROOM x12
    ldr     x9, [sp, #(L + 112)]
    HTTP_ROOM x12
    ldr     x9, [sp, #(L + 128)]
    HTTP_ROOM x12
    ldr     x9, [sp, #(L + 152)]
    HTTP_ROOM x12
    ldr     x9, [x22]
    cmp     x9, x12
    b.lo    97f
    str     xzr, [x22, #HttpRequest_status]
    ldr     x9, [sp, #(L + 160)]
    str     x9, [x22, #HttpRequest_used]
    ldp     x9, x10, [sp, #L]
    str     x9, [x22, #HttpRequest_method]
    str     x10, [x22, #HttpRequest_version]
    ldr     x9, [sp, #(L + 80)]
    str     x9, [x22, #HttpRequest_close]
    mov     x0, x22                         /* path */
    mov     x1, #HTTP_REQUEST_FIXED
    ldr     x9, [sp, #(L + 16)]
    add     x2, x19, x9
    ldr     x3, [sp, #(L + 184)]
    sub     x3, x3, x9
    mov     x4, #HttpRequest_path
    bl      lantern_http_part
    mov     x1, x0                          /* query */
    mov     x0, x22
    ldr     x9, [sp, #(L + 184)]
    ldr     x10, [sp, #(L + 24)]
    mov     x3, #0
    cmp     x9, x10
    b.hs    42f
    add     x9, x9, #1
    sub     x3, x10, x9
42: add     x2, x19, x9
    mov     x4, #HttpRequest_query
    bl      lantern_http_part
    mov     x6, x0                          /* the three fields */
    mov     x0, x19
    add     x1, x25, #2
    mov     x2, x24
    ADDRESS x3, http_n_accept
    mov     x4, #http_n_accept_len
    mov     x5, x22
    mov     x7, #HttpRequest_accept
    bl      lantern_http_joined
    mov     x6, x0
    mov     x0, x19
    add     x1, x25, #2
    mov     x2, x24
    ADDRESS x3, http_n_type
    mov     x4, #http_n_type_len
    mov     x5, x22
    mov     x7, #HttpRequest_content_type
    bl      lantern_http_joined
    mov     x6, x0
    mov     x0, x19
    add     x1, x25, #2
    mov     x2, x24
    ADDRESS x3, http_n_version
    mov     x4, #http_n_version_len
    mov     x5, x22
    mov     x7, #HttpRequest_consensus_version
    bl      lantern_http_joined
    mov     x1, x0                          /* body */
    ldr     x9, [sp, #(L + 40)]
    cbnz    x9, 43f
    mov     x0, x22
    ldr     x9, [sp, #(L + 144)]
    add     x2, x19, x9
    ldr     x3, [sp, #(L + 152)]
    mov     x4, #HttpRequest_body
    bl      lantern_http_part
    b       44f
43: add     x9, x22, #HttpRequest_body      /* chunked: its bytes, unchunked */
    ldr     x10, [sp, #(L + 152)]
    stp     x1, x10, [x9]
    add     x0, x22, x1
    mov     x1, x19
    mov     x2, x20
    ldr     x3, [sp, #(L + 144)]
    ldp     x4, x5, [x21]
    bl      lantern_http_chunks
44: mov     x0, #LANTERN_OK
    LEAVE 224
400: mov    x9, #400
    b       96f
413: mov    x9, #413
    b       96f
431: mov    x9, #431
    b       96f
501: mov    x9, #501
    b       96f
505: mov    x9, #505
96: str     x9, [x22, #HttpRequest_status]
    mov     x9, #1
    str     x9, [x22, #HttpRequest_close]
    mov     x0, #LANTERN_INVALID_HTTP
    LEAVE 224
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 224
98: mov     x0, #LANTERN_HTTP_MORE
    LEAVE 224
END_FUNCTION lantern_http_request
