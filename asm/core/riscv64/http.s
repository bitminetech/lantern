/*
 * lantern_http_request, RISC-V: in the common object. Requirements: docs/reference/beacon-api.md.
 */

    RODATA
    .p2align 3
http_tchar:                                 # the token characters of RFC 9110 section 5.6.2, a bit each
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

/* a0 = the index of the first byte a3 in [a1, a2) of a0's bytes, else a2. A leaf. Uses t0, t1. */
LOCAL_FUNCTION lantern_http_find
    UNWIND_END_PROLOGUE
1:  bgeu    a1, a2, 2f
    add     t0, a0, a1
    lbu     t1, 0(t0)
    beq     t1, a3, 2f
    addi    a1, a1, 1
    j       1b
2:  mv      a0, a1
    ret
END_FUNCTION lantern_http_find

/* a0 = the index of the first CRLF that starts in [a1, a2 - 1) of a0's bytes, else a2. A leaf. Uses t0-t3. */
LOCAL_FUNCTION lantern_http_crlf
    UNWIND_END_PROLOGUE
    addi    t2, a2, -1
    li      t3, 13
1:  bge     a1, t2, 2f
    add     t0, a0, a1
    lbu     t1, 0(t0)
    bne     t1, t3, 3f
    lbu     t1, 1(t0)
    li      t0, 10
    beq     t1, t0, 4f
3:  addi    a1, a1, 1
    j       1b
2:  mv      a0, a2
    ret
4:  mv      a0, a1
    ret
END_FUNCTION lantern_http_crlf

/* a0 = 1 when [a1, a2) of a0's bytes is a token (RFC 9110 section 5.6.2), else 0. A leaf. Uses t0-t3. */
LOCAL_FUNCTION lantern_http_token
    UNWIND_END_PROLOGUE
    bgeu    a1, a2, 8f
    lla     t3, http_tchar
1:  bgeu    a1, a2, 9f
    add     t0, a0, a1
    lbu     t0, 0(t0)
    srli    t1, t0, 6
    slli    t1, t1, 3
    add     t1, t3, t1
    ld      t1, 0(t1)
    srl     t1, t1, t0
    andi    t1, t1, 1
    beqz    t1, 8f
    addi    a1, a1, 1
    j       1b
8:  li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION lantern_http_token

/* a0 = 1 when the a1 bytes at a0 are the a3 lower case bytes at a2, without regard to ASCII case, else 0. A leaf. Uses t0-t2. */
LOCAL_FUNCTION lantern_http_same
    UNWIND_END_PROLOGUE
    bne     a1, a3, 8f
1:  beqz    a1, 9f
    lbu     t0, 0(a0)
    lbu     t1, 0(a2)
    addi    t2, t0, -65
    sltiu   t2, t2, 26
    slli    t2, t2, 5
    add     t0, t0, t2
    bne     t0, t1, 8f
    addi    a0, a0, 1
    addi    a2, a2, 1
    addi    a1, a1, -1
    j       1b
8:  li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION lantern_http_same

/* [a1, a2) of a0's bytes without leading and trailing spaces and tabs: a0 = its start, a1 = its end. A leaf. Uses t0-t2. */
LOCAL_FUNCTION lantern_http_trim
    UNWIND_END_PROLOGUE
    li      t2, 9
1:  bgeu    a1, a2, 3f
    add     t0, a0, a1
    lbu     t1, 0(t0)
    li      t0, 32
    beq     t1, t0, 2f
    bne     t1, t2, 3f
2:  addi    a1, a1, 1
    j       1b
3:  bgeu    a1, a2, 5f
    add     t0, a0, a2
    lbu     t1, -1(t0)
    li      t0, 32
    beq     t1, t0, 4f
    bne     t1, t2, 5f
4:  addi    a2, a2, -1
    j       3b
5:  mv      a0, a1
    mv      a1, a2
    ret
END_FUNCTION lantern_http_trim

/*
 * The a3 bytes at a2 become a part of HttpRequest a0 at offset a1, with its PartRef at a0 + a4:
 * a0 = a1 + a3 rounded up to a multiple of 8. A leaf. Uses t0, t1.
 */
LOCAL_FUNCTION lantern_http_part
    UNWIND_END_PROLOGUE
    add     t0, a0, a4
    sd      a1, 0(t0)
    sd      a3, 8(t0)
    add     t0, a0, a1
    add     a1, a1, a3
1:  beqz    a3, 2f
    lbu     t1, 0(a2)
    sb      t1, 0(t0)
    addi    a2, a2, 1
    addi    t0, t0, 1
    addi    a3, a3, -1
    j       1b
2:  addi    a0, a1, 7
    andi    a0, a0, -8
    ret
END_FUNCTION lantern_http_part

/*
 * The chunked body that starts at index a3 of the a2 bytes at a1, with head_max a4 and body_max
 * a5 (lantern_http_request's rules). a0 = 0 checks it: a0 = LANTERN_OK with a1 the index past the
 * trailers and a2 the body's bytes, LANTERN_HTTP_MORE, or LANTERN_INVALID_HTTP with a1 the HTTP
 * status. a0 = a destination: a body checked before, its bytes copied there. A leaf. Uses a6, a7, t0-t5.
 * a0 the destination, a7 the body's bytes, a6 a CRLF, t2 a size, t5 trailer bytes.
 */
LOCAL_FUNCTION lantern_http_chunks
    UNWIND_END_PROLOGUE
    li      a7, 0
1:  mv      a6, a3                          # a size line: find its CRLF
    addi    t0, a2, -1
2:  bge     a6, t0, 3f
    add     t1, a1, a6
    lbu     t3, 0(t1)
    li      t4, 13
    bne     t3, t4, 21f
    lbu     t3, 1(t1)
    li      t4, 10
    beq     t3, t4, 4f
21: addi    a6, a6, 1
    j       2b
3:  sub     t0, a2, a3                      # no CRLF yet
    bgtu    t0, a4, 80f
    j       90f
4:  sub     t0, a6, a3
    bgtu    t0, a4, 80f
    mv      t0, a3                          # the hex size
    li      t2, 0
5:  bgeu    t0, a6, 7f
    add     t1, a1, t0
    lbu     t1, 0(t1)
    addi    t3, t1, -48
    li      t4, 9
    bleu    t3, t4, 6f
    ori     t1, t1, 0x20
    addi    t3, t1, -97
    li      t4, 5
    bgtu    t3, t4, 7f
    addi    t3, t3, 10
6:  srli    t4, t2, 60
    bnez    t4, 80f                         # past 2^64 - 1
    slli    t2, t2, 4
    add     t2, t2, t3
    addi    t0, t0, 1
    j       5b
7:  beq     t0, a3, 80f                     # no hex digit
    bgeu    t0, a6, 72f
    add     t1, a1, t0                      # an extension: ; space or tab, then no CR, LF or NUL
    lbu     t1, 0(t1)
    li      t4, 59
    beq     t1, t4, 71f
    li      t4, 32
    beq     t1, t4, 71f
    li      t4, 9
    bne     t1, t4, 80f
71: bgeu    t0, a6, 72f
    add     t1, a1, t0
    lbu     t1, 0(t1)
    beqz    t1, 80f
    li      t4, 10
    beq     t1, t4, 80f
    li      t4, 13
    beq     t1, t4, 80f
    addi    t0, t0, 1
    j       71b
72: addi    a3, a6, 2
    beqz    t2, 10f                         # the last chunk
    sub     t0, a5, a7                      # body_max
    bgtu    t2, t0, 81f
    sub     t0, a2, a3
    bgtu    t2, t0, 90f
    sub     t0, t0, t2
    li      t4, 2
    bltu    t0, t4, 90f
    add     t0, a1, a3                      # the data, then CRLF
    add     t0, t0, t2
    lbu     t1, 0(t0)
    li      t4, 13
    bne     t1, t4, 80f
    lbu     t1, 1(t0)
    li      t4, 10
    bne     t1, t4, 80f
    beqz    a0, 9f
    add     t0, a1, a3                      # copy the data
    mv      t1, t2
8:  lbu     t3, 0(t0)
    sb      t3, 0(a0)
    addi    t0, t0, 1
    addi    a0, a0, 1
    addi    t1, t1, -1
    bnez    t1, 8b
9:  add     a7, a7, t2
    add     a3, a3, t2
    addi    a3, a3, 2
    j       1b
10: li      t5, 0                           # trailer lines, skipped, up to the empty line
11: mv      a6, a3
    addi    t0, a2, -1
12: bge     a6, t0, 13f
    add     t1, a1, a6
    lbu     t3, 0(t1)
    li      t4, 13
    bne     t3, t4, 121f
    lbu     t3, 1(t1)
    li      t4, 10
    beq     t3, t4, 14f
121: addi   a6, a6, 1
    j       12b
13: sub     t0, a2, a3
    add     t0, t0, t5
    bgtu    t0, a4, 82f
    j       90f
14: addi    t0, a6, 2
    sub     t0, t0, a3
    add     t5, t5, t0
    bgtu    t5, a4, 82f
    mv      t0, a3                          # the empty line ends them
    addi    a3, a6, 2
    bne     a6, t0, 11b
    li      a0, LANTERN_OK
    mv      a1, a3
    mv      a2, a7
    ret
80: li      a0, LANTERN_INVALID_HTTP
    li      a1, 400
    ret
81: li      a0, LANTERN_INVALID_HTTP
    li      a1, 413
    ret
82: li      a0, LANTERN_INVALID_HTTP
    li      a1, 431
    ret
90: li      a0, LANTERN_HTTP_MORE
    ret
END_FUNCTION lantern_http_chunks

/*
 * The values of the field lines named by the a4 lower case bytes at a3, between index a1 and the
 * head's CRLF CRLF at a2 of the bytes at a0, joined with ", ", become a part of HttpRequest a5 at
 * offset a6 with its PartRef at a5 + a7: a0 = the next part's offset. The lines are checked before.
 * s1 bytes, s2 the line, s3 the head's end, s4 name, s5 its length, s6 out, s7 the offset, s8 the
 * PartRef, s9 the line's end, s10 the part's end; L the colon.
 */
LOCAL_FUNCTION lantern_http_joined
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    mv      s7, a6
    add     s8, a5, a7
    sd      zero, 8(s8)                     # lines so far: 0
    mv      s10, a6
1:  bgtu    s2, s3, 9f
    mv      a0, s1
    mv      a1, s2
    addi    a2, s3, 2
    call    lantern_http_crlf
    mv      s9, a0
    mv      a0, s1
    mv      a1, s2
    mv      a2, s9
    li      a3, 58
    call    lantern_http_find
    sd      a0, L(sp)
    sub     a1, a0, s2
    add     a0, s1, s2
    mv      a2, s4
    mv      a3, s5
    call    lantern_http_same
    beqz    a0, 5f
    mv      a0, s1
    ld      a1, L(sp)
    addi    a1, a1, 1
    mv      a2, s9
    call    lantern_http_trim
    ld      t0, 8(s8)                       # ", " before all but the first line
    beqz    t0, 2f
    add     t1, s6, s10
    li      t0, 44
    sb      t0, 0(t1)
    li      t0, 32
    sb      t0, 1(t1)
    addi    s10, s10, 2
2:  li      t0, 1
    sd      t0, 8(s8)
3:  bgeu    a0, a1, 5f
    add     t0, s1, a0
    lbu     t0, 0(t0)
    add     t1, s6, s10
    sb      t0, 0(t1)
    addi    a0, a0, 1
    addi    s10, s10, 1
    j       3b
5:  addi    s2, s9, 2
    j       1b
9:  sd      s7, 0(s8)
    sub     t0, s10, s7
    sd      t0, 8(s8)
    addi    a0, s10, 7
    andi    a0, a0, -8
    LEAVE 16
END_FUNCTION lantern_http_joined

/*
 * The name of the field line at s8, s10 bytes before its colon, is the text at label: branch to dest.
 * Uses a0-a3, t0-t2.
 */
.macro HTTP_NAME label, dest
    add     a0, s1, s8
    mv      a1, s10
    lla     a2, \label
    li      a3, \label\()_len
    call    lantern_http_same
    bnez    a0, \dest
.endm

/* acc += t0 rounded up to a multiple of 8. Uses t0. */
.macro HTTP_ROOM acc
    addi    t0, t0, 7
    andi    t0, t0, -8
    add     \acc, \acc, t0
.endm

/*
 * s1 the bytes, s2 their count, s3 limits, s4 out, s5 the request line, s6 the head's CRLF CRLF,
 * s7 the request line's CRLF, s8 a line or an item, s9 the line's end, s10 a name's length or an item's end.
 * Locals: L method, L+8 version, L+16 target start, L+24 target end, L+32 Host lines, L+40
 * Transfer-Encoding lines, L+48 1 when one is chunked, L+56 Content-Length lines, L+64 its value,
 * L+72 1 when one is bad, L+80 the token close, L+88 the token keep-alive, L+96 Accept bytes and
 * L+104 lines, L+112 Content-Type bytes and L+120 lines, L+128 Eth-Consensus-Version bytes and
 * L+136 lines, L+144 body start, L+152 body bytes, L+160 used, L+168 a value's start, L+176 its end,
 * L+184 the path's end, L+192 1 once a length item is in, L+200 a token's start, L+208 its length.
 */
FUNCTION lantern_http_request
    ENTER 224
    ld      t0, 0(a2)
    li      t1, HTTP_REQUEST_FIXED
    bltu    t0, t1, 97f
    ld      t0, 8(a0)
    add     s1, a0, t0
    ld      s2, 16(a0)
    mv      s3, a1
    mv      s4, a2
    addi    t0, sp, L                       # every local 0
    li      t1, 28
1:  sd      zero, 0(t0)
    addi    t0, t0, 8
    addi    t1, t1, -1
    bnez    t1, 1b
    li      t4, 13
    li      t5, 10
    li      s5, 0                           # empty lines before the request line
2:  addi    t0, s5, 2
    bgtu    t0, s2, 3f
    add     t1, s1, s5
    lbu     t2, 0(t1)
    bne     t2, t4, 3f
    lbu     t2, 1(t1)
    bne     t2, t5, 3f
    addi    s5, s5, 2
    j       2b
3:  mv      s6, s5                          # the head ends at the first CRLF CRLF
4:  addi    t0, s6, 4
    bgtu    t0, s2, 5f
    add     t1, s1, s6
    lbu     t2, 0(t1)
    bne     t2, t4, 45f
    lbu     t2, 1(t1)
    bne     t2, t5, 45f
    lbu     t2, 2(t1)
    bne     t2, t4, 45f
    lbu     t2, 3(t1)
    beq     t2, t5, 6f
45: addi    s6, s6, 1
    j       4b
5:  ld      t0, HttpLimits_head_max(s3)
    bgeu    s2, t0, 431f
    j       98f
6:  addi    t0, s6, 4
    ld      t1, HttpLimits_head_max(s3)
    bgtu    t0, t1, 431f
    mv      a0, s1                          # the request line: method SP target SP version
    mv      a1, s5
    addi    a2, s6, 2
    call    lantern_http_crlf
    mv      s7, a0
    mv      a0, s1
    mv      a1, s5
    mv      a2, s7
    li      a3, ' '
    call    lantern_http_find
    beq     a0, s7, 400f
    mv      s8, a0                          # the first space
    mv      a0, s1
    mv      a1, s5
    mv      a2, s8
    call    lantern_http_token
    beqz    a0, 400f
    mv      a0, s1
    addi    a1, s8, 1
    mv      a2, s7
    li      a3, ' '
    call    lantern_http_find
    beq     a0, s7, 400f
    mv      s9, a0                          # the second space
    addi    t0, s8, 1                       # the target: / then visible bytes
    sd      t0, (L + 16)(sp)
    sd      s9, (L + 24)(sp)
    bgeu    t0, s9, 400f
    add     t1, s1, t0
    lbu     t1, 0(t1)
    li      t2, '/'
    bne     t1, t2, 400f
7:  bgeu    t0, s9, 8f
    add     t1, s1, t0
    lbu     t1, 0(t1)
    addi    t1, t1, -0x21
    sltiu   t2, t1, (0x7e - 0x21 + 1)
    beqz    t2, 400f
    addi    t0, t0, 1
    j       7b
8:  sub     t0, s7, s9                      # the version: HTTP/ digit . digit
    li      t1, 9
    bne     t0, t1, 400f
    add     t0, s1, s9
    lbu     t1, 1(t0)
    li      t2, 'H'
    bne     t1, t2, 400f
    li      t2, 'T'
    lbu     t1, 2(t0)
    bne     t1, t2, 400f
    lbu     t1, 3(t0)
    bne     t1, t2, 400f
    lbu     t1, 4(t0)
    li      t2, 'P'
    bne     t1, t2, 400f
    lbu     t1, 5(t0)
    li      t2, '/'
    bne     t1, t2, 400f
    lbu     t1, 7(t0)
    li      t2, '.'
    bne     t1, t2, 400f
    li      t3, 9
    lbu     t1, 6(t0)
    addi    t1, t1, -'0'
    bgtu    t1, t3, 400f
    lbu     t2, 8(t0)
    addi    t2, t2, -'0'
    bgtu    t2, t3, 400f
    li      t3, 1
    bne     t1, t3, 505f
    li      t1, 11
    beq     t2, t3, 9f
    bnez    t2, 505f
    li      t1, 10
9:  sd      t1, (L + 8)(sp)
    sub     t0, s8, s5                      # the method
    li      t1, HTTP_METHOD_OTHER
    add     t2, s1, s5
    li      t3, 3
    bne     t0, t3, 10f
    lbu     t3, 0(t2)
    li      t4, 'G'
    bne     t3, t4, 11f
    lbu     t3, 1(t2)
    li      t4, 'E'
    bne     t3, t4, 11f
    lbu     t3, 2(t2)
    li      t4, 'T'
    bne     t3, t4, 11f
    li      t1, HTTP_METHOD_GET
    j       11f
10: li      t3, 4
    bne     t0, t3, 11f
    lbu     t3, 0(t2)
    li      t4, 'P'
    bne     t3, t4, 11f
    lbu     t3, 1(t2)
    li      t4, 'O'
    bne     t3, t4, 11f
    lbu     t3, 2(t2)
    li      t4, 'S'
    bne     t3, t4, 11f
    lbu     t3, 3(t2)
    li      t4, 'T'
    bne     t3, t4, 11f
    li      t1, HTTP_METHOD_POST
11: sd      t1, L(sp)
    addi    s8, s7, 2                       # each field line, up to the head's CRLF CRLF
12: bgtu    s8, s6, 30f
    mv      a0, s1
    mv      a1, s8
    addi    a2, s6, 2
    call    lantern_http_crlf
    mv      s9, a0
    add     t0, s1, s8                      # no folded line
    lbu     t0, 0(t0)
    li      t1, ' '
    beq     t0, t1, 400f
    li      t1, 9
    beq     t0, t1, 400f
    mv      a0, s1
    mv      a1, s8
    mv      a2, s9
    li      a3, ':'
    call    lantern_http_find
    beq     a0, s9, 400f
    sub     s10, a0, s8                     # the name's length
    beqz    s10, 400f
    mv      a0, s1
    mv      a1, s8
    add     a2, s8, s10
    call    lantern_http_token
    beqz    a0, 400f
    mv      a0, s1                          # the value, without spaces and tabs around it
    add     a1, s8, s10
    addi    a1, a1, 1
    mv      a2, s9
    call    lantern_http_trim
    sd      a0, (L + 168)(sp)
    sd      a1, (L + 176)(sp)
    mv      t0, a0
13: bgeu    t0, a1, 14f                     # no CR, LF or NUL
    add     t1, s1, t0
    lbu     t1, 0(t1)
    beqz    t1, 400f
    li      t2, 10
    beq     t1, t2, 400f
    li      t2, 13
    beq     t1, t2, 400f
    addi    t0, t0, 1
    j       13b
14: HTTP_NAME http_n_host, 20f
    HTTP_NAME http_n_length, 21f
    HTTP_NAME http_n_te, 22f
    HTTP_NAME http_n_connection, 23f
    HTTP_NAME http_n_accept, 24f
    HTTP_NAME http_n_type, 25f
    HTTP_NAME http_n_version, 26f
    j       29f
20: ld      t0, (L + 32)(sp)                # Host
    addi    t0, t0, 1
    sd      t0, (L + 32)(sp)
    j       29f
21: ld      t0, (L + 56)(sp)                # Content-Length: a list of equal decimal values
    addi    t0, t0, 1
    sd      t0, (L + 56)(sp)
    ld      s8, (L + 168)(sp)
211: mv     a0, s1                          # an item: up to the next comma
    mv      a1, s8
    ld      a2, (L + 176)(sp)
    li      a3, ','
    call    lantern_http_find
    mv      s10, a0
    mv      a0, s1
    mv      a1, s8
    mv      a2, s10
    call    lantern_http_trim
    bgeu    a0, a1, 218f                    # empty
    li      t0, 0
    li      t3, 10
212: bgeu   a0, a1, 213f
    add     t1, s1, a0
    lbu     t1, 0(t1)
    addi    t1, t1, -'0'
    li      t2, 9
    bgtu    t1, t2, 218f
    mulhu   t2, t0, t3
    bnez    t2, 218f
    mul     t0, t0, t3
    add     t0, t0, t1
    bltu    t0, t1, 218f                    # past 2^64 - 1
    addi    a0, a0, 1
    j       212b
213: ld     t1, (L + 192)(sp)               # the first item sets the length; the others match it
    bnez    t1, 214f
    sd      t0, (L + 64)(sp)
    li      t1, 1
    sd      t1, (L + 192)(sp)
    j       215f
214: ld     t1, (L + 64)(sp)
    bne     t0, t1, 218f
215: ld     t1, (L + 176)(sp)
    bgeu    s10, t1, 29f
    addi    s8, s10, 1
    j       211b
218: li     t0, 1
    sd      t0, (L + 72)(sp)
    j       29f
22: ld      t0, (L + 40)(sp)                # Transfer-Encoding
    addi    t0, t0, 1
    sd      t0, (L + 40)(sp)
    ld      t0, (L + 168)(sp)
    ld      t1, (L + 176)(sp)
    add     a0, s1, t0
    sub     a1, t1, t0
    lla     a2, http_t_chunked
    li      a3, http_t_chunked_len
    call    lantern_http_same
    sd      a0, (L + 48)(sp)
    j       29f
23: ld      s8, (L + 168)(sp)               # Connection: its tokens
231: mv     a0, s1
    mv      a1, s8
    ld      a2, (L + 176)(sp)
    li      a3, ','
    call    lantern_http_find
    mv      s10, a0
    mv      a0, s1
    mv      a1, s8
    mv      a2, s10
    call    lantern_http_trim
    sub     a1, a1, a0
    sd      a0, (L + 200)(sp)
    sd      a1, (L + 208)(sp)
    add     a0, s1, a0
    lla     a2, http_t_close
    li      a3, http_t_close_len
    call    lantern_http_same
    beqz    a0, 232f
    li      t0, 1
    sd      t0, (L + 80)(sp)
232: ld     a0, (L + 200)(sp)
    ld      a1, (L + 208)(sp)
    add     a0, s1, a0
    lla     a2, http_t_keep_alive
    li      a3, http_t_keep_alive_len
    call    lantern_http_same
    beqz    a0, 233f
    li      t0, 1
    sd      t0, (L + 88)(sp)
233: ld     t1, (L + 176)(sp)
    bgeu    s10, t1, 29f
    addi    s8, s10, 1
    j       231b
24: addi    t0, sp, (L + 96)                # Accept, Content-Type, Eth-Consensus-Version: their joined bytes
    j       27f
25: addi    t0, sp, (L + 112)
    j       27f
26: addi    t0, sp, (L + 128)
27: ld      t1, 0(t0)
    ld      t2, 8(t0)
    ld      t3, (L + 168)(sp)
    ld      t4, (L + 176)(sp)
    sub     t4, t4, t3
    beqz    t2, 28f
    addi    t1, t1, 2
28: add     t1, t1, t4
    addi    t2, t2, 1
    sd      t1, 0(t0)
    sd      t2, 8(t0)
29: addi    s8, s9, 2                       # the next line
    j       12b
30: ld      t0, (L + 32)(sp)                # Host: at most one; one in HTTP/1.1
    li      t1, 1
    bgtu    t0, t1, 400f
    ld      t1, (L + 8)(sp)
    li      t2, 11
    bne     t1, t2, 31f
    beqz    t0, 400f
31: ld      t0, (L + 40)(sp)                # Transfer-Encoding: chunked alone
    beqz    t0, 32f
    ld      t1, (L + 56)(sp)
    bnez    t1, 400f
    ld      t1, (L + 8)(sp)
    li      t2, 10
    beq     t1, t2, 400f
    li      t2, 1
    bne     t0, t2, 501f
    ld      t1, (L + 48)(sp)
    beqz    t1, 501f
32: ld      t0, (L + 56)(sp)                # Content-Length
    beqz    t0, 33f
    ld      t1, (L + 72)(sp)
    bnez    t1, 400f
    ld      t1, (L + 64)(sp)
    ld      t2, HttpLimits_body_max(s3)
    bgtu    t1, t2, 413f
33: ld      t0, (L + 80)(sp)                # close: the token close, or HTTP/1.0 without keep-alive
    bnez    t0, 34f
    ld      t1, (L + 8)(sp)
    li      t2, 10
    bne     t1, t2, 35f
    ld      t1, (L + 88)(sp)
    bnez    t1, 35f
34: li      t0, 1
35: sd      t0, (L + 80)(sp)
    addi    s8, s6, 4                       # the body
    sd      s8, (L + 144)(sp)
    ld      t0, (L + 56)(sp)
    beqz    t0, 36f
    ld      t1, (L + 64)(sp)
    sub     t2, s2, s8
    bltu    t2, t1, 98f
    sd      t1, (L + 152)(sp)
    add     s8, s8, t1
    j       40f
36: ld      t0, (L + 40)(sp)
    beqz    t0, 40f
    li      a0, 0                           # chunked: check the framing, count the bytes
    mv      a1, s1
    mv      a2, s2
    mv      a3, s8
    ld      a4, HttpLimits_head_max(s3)
    ld      a5, HttpLimits_body_max(s3)
    call    lantern_http_chunks
    li      t0, LANTERN_HTTP_MORE
    beq     a0, t0, 98f
    li      t0, LANTERN_INVALID_HTTP
    bne     a0, t0, 37f
    mv      t0, a1
    j       96f
37: mv      s8, a1
    sd      a2, (L + 152)(sp)
40: sd      s8, (L + 160)(sp)               # used; then the room the parts need
    mv      a0, s1
    ld      a1, (L + 16)(sp)
    ld      a2, (L + 24)(sp)
    li      a3, '?'
    call    lantern_http_find
    sd      a0, (L + 184)(sp)               # the path's end
    li      t5, HTTP_REQUEST_FIXED
    ld      t1, (L + 16)(sp)
    sub     t0, a0, t1
    HTTP_ROOM t5
    ld      t1, (L + 24)(sp)
    sub     t0, t1, a0
    beqz    t0, 41f
    addi    t0, t0, -1                      # the query: after the ?
41: HTTP_ROOM t5
    ld      t0, (L + 96)(sp)
    HTTP_ROOM t5
    ld      t0, (L + 112)(sp)
    HTTP_ROOM t5
    ld      t0, (L + 128)(sp)
    HTTP_ROOM t5
    ld      t0, (L + 152)(sp)
    HTTP_ROOM t5
    ld      t0, 0(s4)
    bltu    t0, t5, 97f
    sd      zero, HttpRequest_status(s4)
    ld      t0, (L + 160)(sp)
    sd      t0, HttpRequest_used(s4)
    ld      t0, L(sp)
    sd      t0, HttpRequest_method(s4)
    ld      t0, (L + 8)(sp)
    sd      t0, HttpRequest_version(s4)
    ld      t0, (L + 80)(sp)
    sd      t0, HttpRequest_close(s4)
    mv      a0, s4                          # path
    li      a1, HTTP_REQUEST_FIXED
    ld      t0, (L + 16)(sp)
    add     a2, s1, t0
    ld      a3, (L + 184)(sp)
    sub     a3, a3, t0
    li      a4, HttpRequest_path
    call    lantern_http_part
    mv      a1, a0                          # query
    mv      a0, s4
    ld      t0, (L + 184)(sp)
    ld      t1, (L + 24)(sp)
    li      a3, 0
    bgeu    t0, t1, 42f
    addi    t0, t0, 1
    sub     a3, t1, t0
42: add     a2, s1, t0
    li      a4, HttpRequest_query
    call    lantern_http_part
    mv      a6, a0                          # the three fields
    mv      a0, s1
    addi    a1, s7, 2
    mv      a2, s6
    lla     a3, http_n_accept
    li      a4, http_n_accept_len
    mv      a5, s4
    li      a7, HttpRequest_accept
    call    lantern_http_joined
    mv      a6, a0
    mv      a0, s1
    addi    a1, s7, 2
    mv      a2, s6
    lla     a3, http_n_type
    li      a4, http_n_type_len
    mv      a5, s4
    li      a7, HttpRequest_content_type
    call    lantern_http_joined
    mv      a6, a0
    mv      a0, s1
    addi    a1, s7, 2
    mv      a2, s6
    lla     a3, http_n_version
    li      a4, http_n_version_len
    mv      a5, s4
    li      a7, HttpRequest_consensus_version
    call    lantern_http_joined
    mv      a1, a0                          # body
    ld      t0, (L + 40)(sp)
    bnez    t0, 43f
    mv      a0, s4
    ld      t0, (L + 144)(sp)
    add     a2, s1, t0
    ld      a3, (L + 152)(sp)
    li      a4, HttpRequest_body
    call    lantern_http_part
    j       44f
43: ld      t1, (L + 152)(sp)               # chunked: its bytes, unchunked
    sd      a1, HttpRequest_body(s4)
    sd      t1, (HttpRequest_body + 8)(s4)
    add     a0, s4, a1
    mv      a1, s1
    mv      a2, s2
    ld      a3, (L + 144)(sp)
    ld      a4, HttpLimits_head_max(s3)
    ld      a5, HttpLimits_body_max(s3)
    call    lantern_http_chunks
44: li      a0, LANTERN_OK
    LEAVE 224
400: li     t0, 400
    j       96f
413: li     t0, 413
    j       96f
431: li     t0, 431
    j       96f
501: li     t0, 501
    j       96f
505: li     t0, 505
96: sd      t0, HttpRequest_status(s4)
    li      t0, 1
    sd      t0, HttpRequest_close(s4)
    li      a0, LANTERN_INVALID_HTTP
    LEAVE 224
97: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 224
98: li      a0, LANTERN_HTTP_MORE
    LEAVE 224
END_FUNCTION lantern_http_request
