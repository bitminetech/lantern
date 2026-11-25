/*
 * Engine API client, RISC-V: the JWT and HTTP/1.1 functions of the common object.
 * Requirements: docs/reference/engine-api.md.
 */

/* One lantern_base64url character of the 6 bits of t1 to a2. Uses t2. */
.macro B64_PUT
    add     t2, t6, t1
    lbu     t2, 0(t2)
    sb      t2, 0(a2)
    addi    a2, a2, 1
.endm

/* lantern_base64url of the a1 bytes at a0, without padding, to a2; a2 = the end. Uses t0-t2, t6. */
LOCAL_FUNCTION lantern_base64url
    UNWIND_END_PROLOGUE
    ADDRESS t6, base64url_alphabet
1:  li      t1, 3
    bltu    a1, t1, 2f
    lbu     t0, 0(a0)
    slli    t0, t0, 16
    lbu     t1, 1(a0)
    slli    t1, t1, 8
    or      t0, t0, t1
    lbu     t1, 2(a0)
    or      t0, t0, t1
    addi    a0, a0, 3
    addi    a1, a1, -3
    srli    t1, t0, 18
    B64_PUT
    srli    t1, t0, 12
    andi    t1, t1, 63
    B64_PUT
    srli    t1, t0, 6
    andi    t1, t1, 63
    B64_PUT
    andi    t1, t0, 63
    B64_PUT
    j       1b
2:  beqz    a1, 4f
    lbu     t0, 0(a0)
    slli    t0, t0, 16
    li      t1, 2
    bltu    a1, t1, 3f
    lbu     t1, 1(a0)
    slli    t1, t1, 8
    or      t0, t0, t1
3:  srli    t1, t0, 18                      # 1 byte: 2 characters; 2 bytes: 3
    B64_PUT
    srli    t1, t0, 12
    andi    t1, t1, 63
    B64_PUT
    li      t1, 2
    bltu    a1, t1, 4f
    srli    t1, t0, 6
    andi    t1, t1, 63
    B64_PUT
4:  ret
END_FUNCTION lantern_base64url

/* The decimal digits of a0 to a1; a1 = the end. Uses t0-t3. */
LOCAL_FUNCTION lantern_decimal
    UNWIND_END_PROLOGUE
    li      t3, 10                          # count the digits, then write them from the last
    mv      t0, a0
1:  divu    t0, t0, t3
    addi    a1, a1, 1
    bnez    t0, 1b
    mv      t0, a1
2:  remu    t1, a0, t3
    divu    a0, a0, t3
    addi    t1, t1, '0'
    addi    t0, t0, -1
    sb      t1, 0(t0)
    bnez    a0, 2b
    ret
END_FUNCTION lantern_decimal

/*
 * (secret, iat, scratch, out): s1 secret, s2 iat, s3 scratch, s4 out, s5 the token's end.
 * Scratch: its size, the key's ByteList at +8, the signing input's ByteList at +64 (bytes
 * at +88), HMAC's scratch at +176. Locals: L the claims JSON, L+32 the MAC.
 */
FUNCTION lantern_jwt_token
    ENTER 64
    mv      s1, a0
    ld      s2, 0(a1)
    mv      s3, a2
    mv      s4, a3
    ld      t0, 0(s4)
    li      t1, 24 + 128
    bltu    t0, t1, 8f
    ld      t0, 0(s3)
    li      t1, 512
    bltu    t0, t1, 8f
    li      t0, 56                          # the key: a ByteList of the 32 bytes
    sd      t0, 8(s3)
    li      t0, 24
    sd      t0, 16(s3)
    li      t0, 32
    sd      t0, 24(s3)
    addi    a0, s3, 32
    mv      a1, s1
    li      a2, 32
    call    lantern_copy
    ADDRESS a0, jwt_header                  # lantern_base64url(header) + .
    li      a1, 37
    addi    a2, s3, 88
    call    lantern_put_bytes
    mv      s5, a2
    li      t0, '{'                         # the claims: {"iat":<iat>}
    sb      t0, L(sp)
    ADDRESS a0, jwt_claims
    li      a1, 6
    addi    a2, sp, L + 1
    call    lantern_put_bytes
    mv      a0, s2
    mv      a1, a2
    call    lantern_decimal
    li      t0, '}'
    sb      t0, 0(a1)
    addi    a1, a1, 1
    addi    a0, sp, L
    sub     a1, a1, a0
    mv      a2, s5
    call    lantern_base64url
    addi    t0, s3, 88                      # the signing input's ByteList
    sub     t1, a2, t0
    mv      s5, a2
    li      t0, 112
    sd      t0, 64(s3)
    li      t0, 24
    sd      t0, 72(s3)
    sd      t1, 80(s3)
    addi    a0, s3, 8                       # HMAC-SHA256(secret, signing input)
    addi    a1, s3, 64
    addi    a2, s3, 176
    ld      t0, 0(s3)
    addi    t0, t0, -176
    sd      t0, 0(a2)
    addi    a3, sp, L + 32
    CALL_GLOBAL crypto_hmac_sha256
    bnez    a0, 8f
    addi    a0, s3, 88                      # out: the signing input, ., lantern_base64url(mac)
    sub     a1, s5, a0
    addi    a2, s4, 24
    call    lantern_put_bytes
    li      t0, '.'
    sb      t0, 0(a2)
    addi    a2, a2, 1
    addi    a0, sp, L + 32
    li      a1, 32
    call    lantern_base64url
    addi    t0, s4, 24
    sub     t1, a2, t0
    li      t0, 24
    sd      t0, 8(s4)
    sd      t1, 16(s4)
    li      a0, LANTERN_OK
    LEAVE 64
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_jwt_token

/* The a1 bytes at a0 to a2; a2 = the end. Uses t0. */
LOCAL_FUNCTION lantern_put_bytes
    UNWIND_END_PROLOGUE
    beqz    a1, 2f
1:  lbu     t0, 0(a0)
    sb      t0, 0(a2)
    addi    a0, a0, 1
    addi    a2, a2, 1
    addi    a1, a1, -1
    bnez    a1, 1b
2:  ret
END_FUNCTION lantern_put_bytes

/* (host, token, body, out): s1-s4 the arguments, s5 the request's length, s6 the digits. Locals: L the digits. */
FUNCTION lantern_http_post
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    ld      a0, 16(s3)                      # the body's length in decimal
    addi    a1, sp, L
    call    lantern_decimal
    addi    t0, sp, L
    sub     s6, a1, t0
    ld      s5, 16(s1)                      # the request's length
    ld      t0, 16(s2)
    add     s5, s5, t0
    ld      t0, 16(s3)
    add     s5, s5, t0
    add     s5, s5, s6
    addi    s5, s5, 23 + 56 + 18 + 4
    ld      t0, 0(s4)
    li      t1, 24
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    bltu    t0, s5, 8f
    sd      t1, 8(s4)
    sd      s5, 16(s4)
    addi    a2, s4, 24
    ADDRESS a0, http_post_1                 # POST / HTTP/1.1, Host:
    li      a1, 23
    call    lantern_put_bytes
    ld      t0, 8(s1)
    add     a0, s1, t0
    ld      a1, 16(s1)
    call    lantern_put_bytes
    ADDRESS a0, http_post_2                 # Content-Type, Authorization: Bearer
    li      a1, 56
    call    lantern_put_bytes
    ld      t0, 8(s2)
    add     a0, s2, t0
    ld      a1, 16(s2)
    call    lantern_put_bytes
    ADDRESS a0, http_post_3                 # Content-Length:
    li      a1, 18
    call    lantern_put_bytes
    addi    a0, sp, L
    mv      a1, s6
    call    lantern_put_bytes
    ADDRESS a0, http_crlf2
    li      a1, 4
    call    lantern_put_bytes
    ld      t0, 8(s3)
    add     a0, s3, t0
    ld      a1, 16(s3)
    call    lantern_put_bytes
    li      a0, LANTERN_OK
    LEAVE 32
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION lantern_http_post

/* a0 = the position of the CR LF at or after a2 in the a1 bytes at a0, or 2^64 - 1. Uses t0-t2. */
LOCAL_FUNCTION lantern_find_crlf
    UNWIND_END_PROLOGUE
    mv      t0, a2
1:  addi    t1, t0, 1
    bgeu    t1, a1, 3f
    add     t1, a0, t0
    lbu     t2, 0(t1)
    li      t1, 13
    bne     t2, t1, 2f
    add     t1, a0, t0
    lbu     t2, 1(t1)
    li      t1, 10
    beq     t2, t1, 4f
2:  addi    t0, t0, 1
    j       1b
3:  li      t0, -1
4:  mv      a0, t0
    ret
END_FUNCTION lantern_find_crlf

/* Whether the a5 bytes at a4 are the n byte name at label (lowercase): t0 = 1 or 0. Uses t1-t4. */
.macro HEADER_IS label, n
    li      t0, 0
    li      t1, \n
    bne     a5, t1, 93f
    ADDRESS t1, \label
    li      t2, 0
91: add     t3, a4, t2
    lbu     t3, 0(t3)
    addi    t4, t3, -'A'
    sltiu   t4, t4, 26
    slli    t4, t4, 5
    add     t3, t3, t4                      # to lowercase
    add     t4, t1, t2
    lbu     t4, 0(t4)
    bne     t3, t4, 93f
    addi    t2, t2, 1
    li      t3, \n
    bltu    t2, t3, 91b
    li      t0, 1
93:
.endm

/*
 * (input, eof, body, out): s1 the bytes, s2 their count, s3 eof, s4 body, s5 out, s6 the position,
 * s7 the status, s8 Content-Length or 2^64 - 1, s9 1 for chunked, 2 for another coding,
 * s10 the body's length so far. Locals: L the line's end, L+8 where a chunked body starts,
 * L+16 the pass of a chunked body.
 */
FUNCTION lantern_http_parse_response
    ENTER 32
    ld      t0, 8(a0)
    add     s1, a0, t0
    ld      s2, 16(a0)
    ld      s3, 0(a1)
    mv      s4, a2
    mv      s5, a3
    mv      a0, s1                          # the status line
    mv      a1, s2
    li      a2, 0
    call    lantern_find_crlf
    li      t0, -1
    beq     a0, t0, 7f
    mv      s6, a0
    li      t0, 13                          # HTTP/1.d ddd SP
    bltu    s6, t0, 9f
    ADDRESS t0, http_version
    li      t1, 0
1:  add     t2, s1, t1
    lbu     t2, 0(t2)
    add     t3, t0, t1
    lbu     t3, 0(t3)
    bne     t2, t3, 9f
    addi    t1, t1, 1
    li      t3, 7
    bltu    t1, t3, 1b
    lbu     t2, 7(s1)
    addi    t2, t2, -'0'
    li      t3, 10
    bgeu    t2, t3, 9f
    lbu     t2, 8(s1)
    li      t3, ' '
    bne     t2, t3, 9f
    li      s7, 0
    li      t1, 9
2:  add     t2, s1, t1
    lbu     t2, 0(t2)
    addi    t2, t2, -'0'
    li      t3, 10
    bgeu    t2, t3, 9f
    mul     s7, s7, t3
    add     s7, s7, t2
    addi    t1, t1, 1
    li      t3, 12
    bltu    t1, t3, 2b
    lbu     t2, 12(s1)
    li      t3, ' '
    bne     t2, t3, 9f
    li      t1, 13                          # the reason phrase: no CR, no LF
3:  bgeu    t1, s6, 4f
    add     t2, s1, t1
    lbu     t2, 0(t2)
    li      t3, 13
    beq     t2, t3, 9f
    li      t3, 10
    beq     t2, t3, 9f
    addi    t1, t1, 1
    j       3b
4:  addi    s6, s6, 2
    li      s8, -1
    li      s9, 0
5:  mv      a0, s1                          # each header line, to the empty line
    mv      a1, s2
    mv      a2, s6
    call    lantern_find_crlf
    li      t0, -1
    beq     a0, t0, 7f
    beq     a0, s6, 20f
    sd      a0, L(sp)                       # the line's end
    mv      t1, s6                          # name: to the colon, no space, tab, CR or LF
6:  bgeu    t1, a0, 9f
    add     t2, s1, t1
    lbu     t2, 0(t2)
    li      t3, ':'
    beq     t2, t3, 10f
    li      t3, ' '
    beq     t2, t3, 9f
    li      t3, 9
    beq     t2, t3, 9f
    li      t3, 13
    beq     t2, t3, 9f
    li      t3, 10
    beq     t2, t3, 9f
    addi    t1, t1, 1
    j       6b
10: sub     a5, t1, s6                      # the name's length
    beqz    a5, 9f
    addi    a6, t1, 1                       # the value: a6 to a7, trimmed of spaces and tabs
    mv      a7, a0
11: bgeu    a6, a7, 12f
    add     t2, s1, a6
    lbu     t2, 0(t2)
    li      t3, ' '
    beq     t2, t3, 18f
    li      t3, 9
    bne     t2, t3, 12f
18: addi    a6, a6, 1
    j       11b
12: bgeu    a6, a7, 13f
    add     t2, s1, a7
    lbu     t2, -1(t2)
    li      t3, ' '
    beq     t2, t3, 19f
    li      t3, 9
    bne     t2, t3, 13f
19: addi    a7, a7, -1
    j       12b
13: add     a4, s1, s6                      # the name's bytes
    HEADER_IS http_content_length, 14
    beqz    t0, 15f
    beq     a6, a7, 9f                      # Content-Length: a decimal number
    li      t0, 0
    li      t5, 10
14: bgeu    a6, a7, 16f
    add     t2, s1, a6
    lbu     t2, 0(t2)
    addi    t2, t2, -'0'
    bgeu    t2, t5, 9f
    mulhu   t3, t0, t5
    bnez    t3, 9f
    mul     t0, t0, t5
    add     t3, t0, t2
    bltu    t3, t0, 9f
    mv      t0, t3
    addi    a6, a6, 1
    j       14b
16: li      t1, -1                          # a second Content-Length must agree
    beq     s8, t1, 17f
    bne     s8, t0, 9f
17: mv      s8, t0
    j       24f
15: HEADER_IS http_transfer_encoding, 17
    beqz    t0, 24f
    li      s9, 2                           # chunked, or another coding
    sub     a5, a7, a6
    add     a4, s1, a6
    HEADER_IS http_chunked, 7
    beqz    t0, 24f
    li      s9, 1
24: ld      s6, L(sp)                       # the next line
    addi    s6, s6, 2
    j       5b
20: addi    s6, s6, 2                       # the body
    li      s10, 0
    li      t0, 200                         # 1xx, 204 and 304: no body
    bltu    s7, t0, 40f
    li      t0, 204
    beq     s7, t0, 40f
    li      t0, 304
    beq     s7, t0, 40f
    li      t0, 1
    bne     s9, t0, 21f
    sd      s6, (L + 8)(sp)                 # chunked: walk the chunks, then copy them
    sd      zero, (L + 16)(sp)
    j       30f
21: bnez    s9, 25f
    li      t0, -1
    beq     s8, t0, 25f
    sub     t1, s2, s6                      # Content-Length bytes
    bltu    t1, s8, 7f
    mv      s10, s8
    j       26f
25: beqz    s3, 7f                          # every byte to the end of the connection
    sub     s10, s2, s6
26: ld      t0, 0(s4)                       # copy the body
    li      t1, 24
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    bltu    t0, s10, 8f
    addi    a0, s4, 24
    add     a1, s1, s6
    mv      a2, s10
    add     s6, s6, s10
    call    lantern_copy
    j       40f
30: mv      a0, s1                          # chunked: a chunk size line
    mv      a1, s2
    mv      a2, s6
    call    lantern_find_crlf
    li      t0, -1
    beq     a0, t0, 7f
    li      t0, 0
    mv      t1, s6
    bgeu    t1, a0, 9f
31: bgeu    t1, a0, 33f
    add     t2, s1, t1
    lbu     t2, 0(t2)
    li      t3, ';'
    beq     t2, t3, 33f
    addi    t3, t2, -'0'
    li      t4, 10
    bltu    t3, t4, 32f
    ori     t2, t2, 0x20
    addi    t3, t2, -'a'
    li      t4, 6
    bgeu    t3, t4, 9f
    addi    t3, t3, 10
32: srli    t4, t0, 60
    bnez    t4, 9f
    slli    t0, t0, 4
    or      t0, t0, t3
    addi    t1, t1, 1
    j       31b
33: beq     t1, s6, 9f                      # at least one digit
    addi    s6, a0, 2
    beqz    t0, 36f
    sub     t1, s2, s6                      # the data and its CR LF
    li      t2, 2
    bltu    t1, t2, 7f
    addi    t1, t1, -2
    bltu    t1, t0, 7f
    add     t1, s6, t0
    add     t1, s1, t1
    lbu     t2, 0(t1)
    li      t3, 13
    bne     t2, t3, 9f
    lbu     t2, 1(t1)
    li      t3, 10
    bne     t2, t3, 9f
    ld      t1, (L + 16)(sp)                # the copying pass
    beqz    t1, 34f
    sd      t0, (L + 24)(sp)
    addi    a0, s4, 24
    add     a0, a0, s10
    add     a1, s1, s6
    mv      a2, t0
    call    lantern_copy
    ld      t0, (L + 24)(sp)
34: add     t1, s10, t0
    bltu    t1, s10, 9f
    mv      s10, t1
    add     s6, s6, t0
    addi    s6, s6, 2
    j       30b
36: mv      a0, s1                          # the trailer section, to its empty line
    mv      a1, s2
    mv      a2, s6
    call    lantern_find_crlf
    li      t0, -1
    beq     a0, t0, 7f
    mv      t0, s6
    addi    s6, a0, 2
    bne     a0, t0, 36b
    ld      t1, (L + 16)(sp)                # the walk is done: room for the body, then copy
    bnez    t1, 40f
    ld      t0, 0(s4)
    li      t1, 24
    bltu    t0, t1, 8f
    sub     t0, t0, t1
    bltu    t0, s10, 8f
    li      t1, 1
    sd      t1, (L + 16)(sp)
    li      s10, 0
    ld      s6, (L + 8)(sp)
    j       30b
40: sd      s7, HttpResponse_status(s5)
    sd      s6, HttpResponse_consumed(s5)
    li      t0, 24
    sd      t0, 8(s4)
    sd      s10, 16(s4)
    li      a0, LANTERN_OK
    LEAVE 32
7:  bnez    s3, 9f                          # more bytes to come, unless the connection has ended
    li      a0, LANTERN_HTTP_MORE
    LEAVE 32
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
9:  li      a0, LANTERN_INVALID_HTTP
    LEAVE 32
END_FUNCTION lantern_http_parse_response

/* The text of engine_exchangeCapabilities, before the code that takes its lengths. */
    RODATA
.include "engine_caps.inc"

/* (id, out): the request of engine_exchangeCapabilities. s1 id, s2 out. */
FUNCTION lantern_engine_exchange_capabilities
    ENTER 0
    ld      s1, 0(a0)
    mv      s2, a1
    ld      t0, 0(s2)
    li      t1, 24 + 512
    bltu    t0, t1, 8f
    ADDRESS a0, j_caps_open
    li      a1, j_caps_open_len
    addi    a2, s2, 24
    call    lantern_put_bytes
    mv      a0, s1
    mv      a1, a2
    call    lantern_decimal
    mv      a2, a1
    ADDRESS a0, j_caps_close
    li      a1, j_caps_close_len
    call    lantern_put_bytes
    addi    t0, s2, 24
    sub     t0, a2, t0
    li      t1, 24
    sd      t1, 8(s2)
    sd      t0, 16(s2)
    li      a0, LANTERN_OK
    LEAVE 0
8:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_engine_exchange_capabilities

ENGINE_TEXT_DATA
