/*
 * Engine API client, x86-64: the JWT and HTTP/1.1 functions of the common object.
 * Requirements: docs/reference/engine-api.md.
 */

/* L0: lantern_base64url of the rsi bytes at rdi, without padding, to rdx; rdx = the end. Uses rax, rcx, r8, r9. */
LOCAL_FUNCTION lantern_base64url
    UNWIND_END_PROLOGUE
    lea     base64url_alphabet(%rip), %r9
1:  cmp     $3, %rsi
    jb      2f
    movzbl  (%rdi), %eax
    shl     $16, %eax
    movzbl  1(%rdi), %ecx
    shl     $8, %ecx
    or      %ecx, %eax
    movzbl  2(%rdi), %ecx
    or      %ecx, %eax
    add     $3, %rdi
    sub     $3, %rsi
    mov     %eax, %ecx
    shr     $18, %ecx
    movzbl  (%r9,%rcx), %r8d
    mov     %r8b, (%rdx)
    mov     %eax, %ecx
    shr     $12, %ecx
    and     $63, %ecx
    movzbl  (%r9,%rcx), %r8d
    mov     %r8b, 1(%rdx)
    mov     %eax, %ecx
    shr     $6, %ecx
    and     $63, %ecx
    movzbl  (%r9,%rcx), %r8d
    mov     %r8b, 2(%rdx)
    and     $63, %eax
    movzbl  (%r9,%rax), %r8d
    mov     %r8b, 3(%rdx)
    add     $4, %rdx
    jmp     1b
2:  test    %rsi, %rsi
    jz      4f
    movzbl  (%rdi), %eax
    shl     $16, %eax
    cmp     $2, %rsi
    jb      3f
    movzbl  1(%rdi), %ecx
    shl     $8, %ecx
    or      %ecx, %eax
3:  mov     %eax, %ecx                      # 1 byte: 2 characters; 2 bytes: 3
    shr     $18, %ecx
    movzbl  (%r9,%rcx), %r8d
    mov     %r8b, (%rdx)
    mov     %eax, %ecx
    shr     $12, %ecx
    and     $63, %ecx
    movzbl  (%r9,%rcx), %r8d
    mov     %r8b, 1(%rdx)
    add     $2, %rdx
    cmp     $2, %rsi
    jb      4f
    shr     $6, %eax
    and     $63, %eax
    movzbl  (%r9,%rax), %r8d
    mov     %r8b, (%rdx)
    inc     %rdx
4:  ret
END_FUNCTION lantern_base64url

/* L0: the decimal digits of rax to rdi; rdi = the end. Uses rax, rcx, rdx, r8. */
LOCAL_FUNCTION lantern_decimal
    UNWIND_END_PROLOGUE
    mov     $10, %ecx                       # count the digits, then write them from the last
    mov     %rax, %r8
1:  xor     %edx, %edx
    div     %rcx
    inc     %rdi
    test    %rax, %rax
    jnz     1b
    mov     %r8, %rax
    mov     %rdi, %r8
2:  xor     %edx, %edx
    div     %rcx
    add     $'0', %dl
    dec     %r8
    mov     %dl, (%r8)
    test    %rax, %rax
    jnz     2b
    ret
END_FUNCTION lantern_decimal

/*
 * (secret, iat, scratch, out): rbx secret, rbp iat, r12 scratch, r13 out, r14 the token's end.
 * Scratch: its size, the key's ByteList at +8, the signing input's ByteList at +64 (bytes
 * at +88), HMAC's scratch at +176. Locals: L the claims JSON, L+32 the MAC.
 */
FUNCTION lantern_jwt_token
    ENTER 64
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    cmpq    $(24 + 128), (%r13)
    jb      8f
    cmpq    $512, (%r12)
    jb      8f
    movq    $56, 8(%r12)                    # the key: a ByteList of the 32 bytes
    movq    $24, 16(%r12)
    movq    $32, 24(%r12)
    movdqu  (%rbx), %xmm0
    movdqu  %xmm0, 32(%r12)
    movdqu  16(%rbx), %xmm0
    movdqu  %xmm0, 48(%r12)
    lea     jwt_header(%rip), %rsi          # lantern_base64url(header) + .
    lea     88(%r12), %rdi
    mov     $37, %ecx
    rep movsb
    mov     %rdi, %r14
    movb    $'{', L(%rsp)                   # the claims: {"iat":<iat>}
    lea     jwt_claims(%rip), %rsi
    lea     (L + 1)(%rsp), %rdi
    mov     $6, %ecx
    rep movsb
    mov     %rbp, %rax
    call    lantern_decimal
    movb    $'}', (%rdi)
    inc     %rdi
    lea     L(%rsp), %rax
    mov     %rdi, %rsi
    sub     %rax, %rsi
    mov     %rax, %rdi
    mov     %r14, %rdx
    call    lantern_base64url
    lea     88(%r12), %rax                  # the signing input's ByteList
    mov     %rdx, %r14
    sub     %rax, %rdx
    movq    $112, 64(%r12)
    movq    $24, 72(%r12)
    mov     %rdx, 80(%r12)
    lea     8(%r12), %rdi                   # HMAC-SHA256(secret, signing input)
    lea     64(%r12), %rsi
    lea     176(%r12), %rdx
    mov     (%r12), %rax
    sub     $176, %rax
    mov     %rax, (%rdx)
    lea     (L + 32)(%rsp), %rcx
    CALL_GLOBAL crypto_hmac_sha256
    test    %rax, %rax
    jnz     8f
    lea     88(%r12), %rsi                  # out: the signing input, ., lantern_base64url(mac)
    mov     %r14, %rcx
    sub     %rsi, %rcx
    lea     24(%r13), %rdi
    rep movsb
    movb    $'.', (%rdi)
    lea     1(%rdi), %rdx
    lea     (L + 32)(%rsp), %rdi
    mov     $32, %esi
    call    lantern_base64url
    lea     24(%r13), %rax
    sub     %rax, %rdx
    movq    $24, 8(%r13)
    mov     %rdx, 16(%r13)
    xor     %eax, %eax
    LEAVE 64
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
END_FUNCTION lantern_jwt_token

/* (host, token, body, out): rbx, rbp, r12, r13 the arguments, r14 the request's length, r15 the digits. Locals: L the digits. */
FUNCTION lantern_http_post
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     16(%r12), %rax                  # the body's length in decimal
    lea     L(%rsp), %rdi
    call    lantern_decimal
    lea     L(%rsp), %rax
    mov     %rdi, %r15
    sub     %rax, %r15
    mov     16(%rbx), %r14                  # the request's length
    add     16(%rbp), %r14
    add     16(%r12), %r14
    add     %r15, %r14
    add     $(23 + 56 + 18 + 4), %r14
    mov     (%r13), %rax
    sub     $24, %rax
    jb      8f
    cmp     %r14, %rax
    jb      8f
    movq    $24, 8(%r13)
    mov     %r14, 16(%r13)
    lea     24(%r13), %rdi
    lea     http_post_1(%rip), %rsi         # POST / HTTP/1.1, Host:
    mov     $23, %ecx
    rep movsb
    mov     8(%rbx), %rsi
    add     %rbx, %rsi
    mov     16(%rbx), %rcx
    rep movsb
    lea     http_post_2(%rip), %rsi         # Content-Type, Authorization: Bearer
    mov     $56, %ecx
    rep movsb
    mov     8(%rbp), %rsi
    add     %rbp, %rsi
    mov     16(%rbp), %rcx
    rep movsb
    lea     http_post_3(%rip), %rsi         # Content-Length:
    mov     $18, %ecx
    rep movsb
    lea     L(%rsp), %rsi
    mov     %r15, %rcx
    rep movsb
    lea     http_crlf2(%rip), %rsi
    mov     $4, %ecx
    rep movsb
    mov     8(%r12), %rsi
    add     %r12, %rsi
    mov     16(%r12), %rcx
    rep movsb
    xor     %eax, %eax
    LEAVE 32
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
END_FUNCTION lantern_http_post

/* L0: rax = the position of the CR LF at or after rdx in the rsi bytes at rdi, or 2^64 - 1. Uses rcx. */
LOCAL_FUNCTION lantern_find_crlf
    UNWIND_END_PROLOGUE
    mov     %rdx, %rax
1:  lea     1(%rax), %rcx
    cmp     %rsi, %rcx
    jae     3f
    cmpb    $13, (%rdi,%rax)
    jne     2f
    cmpb    $10, 1(%rdi,%rax)
    je      4f
2:  inc     %rax
    jmp     1b
3:  mov     $-1, %rax
4:  ret
END_FUNCTION lantern_find_crlf

/* Whether the rcx bytes at rsi are the n byte name at label (lowercase): al = 1 or 0. Uses r8, r9, r10. */
.macro HEADER_IS label, n
    xor     %eax, %eax
    cmp     $\n, %rcx
    jne     93f
    lea     \label(%rip), %r8
    xor     %r9d, %r9d
91: movzbl  (%rsi,%r9), %r10d
    lea     -'A'(%r10), %eax
    cmp     $26, %eax
    jae     92f
    add     $32, %r10d
92: xor     %eax, %eax
    cmp     (%r8,%r9), %r10b
    jne     93f
    inc     %r9
    cmp     $\n, %r9
    jb      91b
    mov     $1, %eax
93:
.endm

/*
 * (input, eof, body, out): rbx the bytes, rbp their count, r12 body, r13 out, r14 the position,
 * r15 the status, S7 eof, S8 Content-Length or 2^64 - 1, S9 1 for chunked, 2 for another coding,
 * S10 the body's length so far. Locals: L the line's end, L+8 where a chunked body starts,
 * L+16 the pass of a chunked body, L+24 a saved value.
 */
FUNCTION lantern_http_parse_response
    ENTER 32
    mov     8(%rdi), %rax
    lea     (%rdi,%rax), %rbx
    mov     16(%rdi), %rbp
    mov     (%rsi), %rax
    mov     %rax, S7(%rsp)
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %rbx, %rdi                      # the status line
    mov     %rbp, %rsi
    xor     %edx, %edx
    call    lantern_find_crlf
    cmp     $-1, %rax
    je      7f
    mov     %rax, %r14
    cmp     $13, %r14                       # HTTP/1.d ddd SP
    jb      9f
    lea     http_version(%rip), %rsi
    xor     %ecx, %ecx
1:  movzbl  (%rbx,%rcx), %eax
    cmp     (%rsi,%rcx), %al
    jne     9f
    inc     %ecx
    cmp     $7, %ecx
    jb      1b
    movzbl  7(%rbx), %eax
    sub     $'0', %eax
    cmp     $10, %eax
    jae     9f
    cmpb    $' ', 8(%rbx)
    jne     9f
    xor     %r15d, %r15d
    mov     $9, %ecx
2:  movzbl  (%rbx,%rcx), %eax
    sub     $'0', %eax
    cmp     $10, %eax
    jae     9f
    imul    $10, %r15, %r15
    add     %rax, %r15
    inc     %ecx
    cmp     $12, %ecx
    jb      2b
    cmpb    $' ', 12(%rbx)
    jne     9f
    mov     $13, %ecx                       # the reason phrase: no CR, no LF
3:  cmp     %r14, %rcx
    jae     4f
    movzbl  (%rbx,%rcx), %eax
    cmp     $13, %eax
    je      9f
    cmp     $10, %eax
    je      9f
    inc     %rcx
    jmp     3b
4:  add     $2, %r14
    movq    $-1, S8(%rsp)
    movq    $0, S9(%rsp)
5:  mov     %rbx, %rdi                      # each header line, to the empty line
    mov     %rbp, %rsi
    mov     %r14, %rdx
    call    lantern_find_crlf
    cmp     $-1, %rax
    je      7f
    cmp     %r14, %rax
    je      20f
    mov     %rax, L(%rsp)                   # the line's end
    mov     %r14, %rdx                      # name: to the colon, no space, tab, CR or LF
6:  cmp     %rax, %rdx
    jae     9f
    movzbl  (%rbx,%rdx), %ecx
    cmp     $':', %ecx
    je      10f
    cmp     $' ', %ecx
    je      9f
    cmp     $9, %ecx
    je      9f
    cmp     $13, %ecx
    je      9f
    cmp     $10, %ecx
    je      9f
    inc     %rdx
    jmp     6b
10: mov     %rdx, %rcx
    sub     %r14, %rcx                      # the name's length
    jz      9f
    lea     1(%rdx), %rdi                   # the value: rdi to rdx, trimmed of spaces and tabs
    mov     %rax, %rdx
11: cmp     %rdx, %rdi
    jae     12f
    movzbl  (%rbx,%rdi), %eax
    cmp     $' ', %eax
    je      18f
    cmp     $9, %eax
    jne     12f
18: inc     %rdi
    jmp     11b
12: cmp     %rdi, %rdx
    jbe     13f
    movzbl  -1(%rbx,%rdx), %eax
    cmp     $' ', %eax
    je      19f
    cmp     $9, %eax
    jne     13f
19: dec     %rdx
    jmp     12b
13: lea     (%rbx,%r14), %rsi               # the name's bytes
    HEADER_IS http_content_length, 14
    test    %eax, %eax
    jz      15f
    cmp     %rdi, %rdx                      # Content-Length: a decimal number
    je      9f
    mov     %rdx, (L + 24)(%rsp)
    xor     %eax, %eax
14: cmp     (L + 24)(%rsp), %rdi
    jae     16f
    movzbl  (%rbx,%rdi), %ecx
    sub     $'0', %ecx
    cmp     $10, %ecx
    jae     9f
    mov     $10, %r8d
    mul     %r8
    jc      9f
    add     %rcx, %rax
    jc      9f
    inc     %rdi
    jmp     14b
16: cmpq    $-1, S8(%rsp)                   # a second Content-Length must agree
    je      17f
    cmp     S8(%rsp), %rax
    jne     9f
17: mov     %rax, S8(%rsp)
    jmp     24f
15: HEADER_IS http_transfer_encoding, 17
    test    %eax, %eax
    jz      24f
    movq    $2, S9(%rsp)                    # chunked, or another coding
    mov     %rdx, %rcx
    sub     %rdi, %rcx
    lea     (%rbx,%rdi), %rsi
    HEADER_IS http_chunked, 7
    test    %eax, %eax
    jz      24f
    movq    $1, S9(%rsp)
24: mov     L(%rsp), %r14                   # the next line
    add     $2, %r14
    jmp     5b
20: add     $2, %r14                        # the body
    movq    $0, S10(%rsp)
    cmp     $200, %r15                      # 1xx, 204 and 304: no body
    jb      40f
    cmp     $204, %r15
    je      40f
    cmp     $304, %r15
    je      40f
    cmpq    $1, S9(%rsp)
    jne     21f
    mov     %r14, (L + 8)(%rsp)             # chunked: walk the chunks, then copy them
    movq    $0, (L + 16)(%rsp)
    jmp     30f
21: cmpq    $0, S9(%rsp)
    jne     25f
    mov     S8(%rsp), %rax
    cmp     $-1, %rax
    je      25f
    mov     %rbp, %rcx                      # Content-Length bytes
    sub     %r14, %rcx
    cmp     %rax, %rcx
    jb      7f
    mov     %rax, S10(%rsp)
    jmp     26f
25: cmpq    $0, S7(%rsp)                    # every byte to the end of the connection
    je      7f
    mov     %rbp, %rax
    sub     %r14, %rax
    mov     %rax, S10(%rsp)
26: mov     (%r12), %rax                    # copy the body
    sub     $24, %rax
    jb      8f
    cmp     S10(%rsp), %rax
    jb      8f
    lea     24(%r12), %rdi
    lea     (%rbx,%r14), %rsi
    mov     S10(%rsp), %rdx
    add     %rdx, %r14
    call    lantern_copy
    jmp     40f
30: mov     %rbx, %rdi                      # chunked: a chunk size line
    mov     %rbp, %rsi
    mov     %r14, %rdx
    call    lantern_find_crlf
    cmp     $-1, %rax
    je      7f
    xor     %edx, %edx
    mov     %r14, %rcx
    cmp     %rax, %rcx
    jae     9f
31: cmp     %rax, %rcx
    jae     33f
    movzbl  (%rbx,%rcx), %edi
    cmp     $';', %edi
    je      33f
    lea     -'0'(%rdi), %esi
    cmp     $10, %esi
    jb      32f
    or      $0x20, %edi
    lea     -'a'(%rdi), %esi
    cmp     $6, %esi
    jae     9f
    add     $10, %esi
32: mov     %rdx, %rdi
    shr     $60, %rdi
    jnz     9f
    shl     $4, %rdx
    or      %rsi, %rdx
    inc     %rcx
    jmp     31b
33: cmp     %r14, %rcx                      # at least one digit
    je      9f
    lea     2(%rax), %r14
    test    %rdx, %rdx
    jz      36f
    mov     %rbp, %rcx                      # the data and its CR LF
    sub     %r14, %rcx
    cmp     $2, %rcx
    jb      7f
    sub     $2, %rcx
    cmp     %rdx, %rcx
    jb      7f
    lea     (%r14,%rdx), %rcx
    cmpb    $13, (%rbx,%rcx)
    jne     9f
    cmpb    $10, 1(%rbx,%rcx)
    jne     9f
    cmpq    $0, (L + 16)(%rsp)              # the copying pass
    je      34f
    mov     %rdx, (L + 24)(%rsp)
    lea     24(%r12), %rdi
    add     S10(%rsp), %rdi
    lea     (%rbx,%r14), %rsi
    call    lantern_copy
    mov     (L + 24)(%rsp), %rdx
34: add     %rdx, S10(%rsp)
    jc      9f
    add     %rdx, %r14
    add     $2, %r14
    jmp     30b
36: mov     %rbx, %rdi                      # the trailer section, to its empty line
    mov     %rbp, %rsi
    mov     %r14, %rdx
    call    lantern_find_crlf
    cmp     $-1, %rax
    je      7f
    cmp     %r14, %rax
    lea     2(%rax), %r14
    jne     36b
    cmpq    $0, (L + 16)(%rsp)              # the walk is done: room for the body, then copy
    jne     40f
    mov     (%r12), %rax
    sub     $24, %rax
    jb      8f
    cmp     S10(%rsp), %rax
    jb      8f
    movq    $1, (L + 16)(%rsp)
    movq    $0, S10(%rsp)
    mov     (L + 8)(%rsp), %r14
    jmp     30b
40: mov     %r15, HttpResponse_status(%r13)
    mov     %r14, HttpResponse_consumed(%r13)
    movq    $24, 8(%r12)
    mov     S10(%rsp), %rax
    mov     %rax, 16(%r12)
    xor     %eax, %eax
    LEAVE 32
7:  cmpq    $0, S7(%rsp)                    # more bytes to come, unless the connection has ended
    jne     9f
    mov     $LANTERN_HTTP_MORE, %eax
    LEAVE 32
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
9:  mov     $LANTERN_INVALID_HTTP, %eax
    LEAVE 32
END_FUNCTION lantern_http_parse_response

/* The text of engine_exchangeCapabilities, before the code that takes its lengths. */
    RODATA
.include "engine_caps.inc"

/* (id, out): the request of engine_exchangeCapabilities. */
FUNCTION lantern_engine_exchange_capabilities
    UNWIND_END_PROLOGUE
    mov     (%rdi), %rax
    cmpq    $(24 + 512), (%rsi)
    jb      8f
    mov     %rsi, %r9
    lea     24(%rsi), %rdi
    lea     j_caps_open(%rip), %rsi
    mov     $j_caps_open_len, %ecx
    rep movsb
    call    lantern_decimal
    lea     j_caps_close(%rip), %rsi
    mov     $j_caps_close_len, %ecx
    rep movsb
    lea     24(%r9), %rax
    sub     %rax, %rdi
    movq    $24, 8(%r9)
    mov     %rdi, 16(%r9)
    xor     %eax, %eax
    ret
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    ret
END_FUNCTION lantern_engine_exchange_capabilities

ENGINE_TEXT_DATA
