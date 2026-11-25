/*
 * lantern_http_request, x86-64: in the common object. Requirements: docs/reference/beacon-api.md.
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

# L0: rax = the index of the first byte cl in [rsi, rdx) of rdi's bytes, else rdx. A leaf.
LOCAL_FUNCTION lantern_http_find
    UNWIND_END_PROLOGUE
1:  cmp     %rdx, %rsi
    jae     2f
    cmp     %cl, (%rdi,%rsi)
    je      2f
    inc     %rsi
    jmp     1b
2:  mov     %rsi, %rax
    ret
END_FUNCTION lantern_http_find

# L0: rax = the index of the first CRLF that starts in [rsi, rdx - 1) of rdi's bytes, else rdx. A leaf. Uses r8.
LOCAL_FUNCTION lantern_http_crlf
    UNWIND_END_PROLOGUE
    lea     -1(%rdx), %r8
1:  cmp     %r8, %rsi
    jge     2f
    cmpb    $13, (%rdi,%rsi)
    jne     3f
    cmpb    $10, 1(%rdi,%rsi)
    je      4f
3:  inc     %rsi
    jmp     1b
2:  mov     %rdx, %rax
    ret
4:  mov     %rsi, %rax
    ret
END_FUNCTION lantern_http_crlf

# L0: rax = 1 when [rsi, rdx) of rdi's bytes is a token (RFC 9110 section 5.6.2), else 0. A leaf. Uses r8.
LOCAL_FUNCTION lantern_http_token
    UNWIND_END_PROLOGUE
    cmp     %rdx, %rsi
    jae     8f
    lea     http_tchar(%rip), %r8
1:  cmp     %rdx, %rsi
    jae     9f
    movzbl  (%rdi,%rsi), %eax
    bt      %rax, (%r8)
    jnc     8f
    inc     %rsi
    jmp     1b
8:  xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION lantern_http_token

# L0: rax = 1 when the rsi bytes at rdi are the rcx lower case bytes at rdx, without regard to ASCII case, else 0. A leaf. Uses r8.
LOCAL_FUNCTION lantern_http_same
    UNWIND_END_PROLOGUE
    cmp     %rcx, %rsi
    jne     8f
1:  test    %rsi, %rsi
    jz      9f
    movzbl  (%rdi), %eax
    lea     -'A'(%rax), %r8d
    cmp     $25, %r8d
    ja      2f
    add     $32, %eax
2:  cmp     (%rdx), %al
    jne     8f
    inc     %rdi
    inc     %rdx
    dec     %rsi
    jmp     1b
8:  xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION lantern_http_same

# L0: [rsi, rdx) of rdi's bytes without leading and trailing spaces and tabs: rax = its start, rdx = its end. A leaf.
LOCAL_FUNCTION lantern_http_trim
    UNWIND_END_PROLOGUE
1:  cmp     %rdx, %rsi
    jae     3f
    movzbl  (%rdi,%rsi), %eax
    cmp     $' ', %eax
    je      2f
    cmp     $9, %eax
    jne     3f
2:  inc     %rsi
    jmp     1b
3:  cmp     %rsi, %rdx
    jbe     5f
    movzbl  -1(%rdi,%rdx), %eax
    cmp     $' ', %eax
    je      4f
    cmp     $9, %eax
    jne     5f
4:  dec     %rdx
    jmp     3b
5:  mov     %rsi, %rax
    ret
END_FUNCTION lantern_http_trim

# L0: the rcx bytes at rdx become a part of HttpRequest rdi at offset rsi, with its PartRef at rdi + r8:
# rax = rsi + rcx rounded up to a multiple of 8. A leaf. Uses r9.
LOCAL_FUNCTION lantern_http_part
    UNWIND_END_PROLOGUE
    mov     %rsi, (%rdi,%r8)
    mov     %rcx, 8(%rdi,%r8)
    lea     (%rdi,%rsi), %r9
    add     %rcx, %rsi
1:  test    %rcx, %rcx
    jz      2f
    movzbl  (%rdx), %eax
    mov     %al, (%r9)
    inc     %rdx
    inc     %r9
    dec     %rcx
    jmp     1b
2:  lea     7(%rsi), %rax
    and     $-8, %rax
    ret
END_FUNCTION lantern_http_part

# L0: the chunked body that starts at index rcx of the rdx bytes at rsi, with head_max r8 and body_max
# r9 (lantern_http_request's rules). rdi = 0 checks it: rax = LANTERN_OK with rdx the index past the
# trailers and rcx the body's bytes, LANTERN_HTTP_MORE, or LANTERN_INVALID_HTTP with rdx the HTTP
# status. rdi = a destination: a body checked before, its bytes copied there.
# rbx data, rbp count, r12 destination, r13 body bytes, r14 a CRLF, r15 a size, S7 head_max, S8
# body_max, S9 trailer bytes, rcx the index.
LOCAL_FUNCTION lantern_http_chunks
    ENTER 16
    mov     %rsi, %rbx
    mov     %rdx, %rbp
    mov     %rdi, %r12
    xor     %r13d, %r13d
    mov     %r8, S7(%rsp)
    mov     %r9, S8(%rsp)
1:  mov     %rcx, %r14                      # a size line: find its CRLF
    lea     -1(%rbp), %r10
2:  cmp     %r10, %r14
    jge     3f
    cmpb    $13, (%rbx,%r14)
    jne     21f
    cmpb    $10, 1(%rbx,%r14)
    je      4f
21: inc     %r14
    jmp     2b
3:  mov     %rbp, %rax                      # no CRLF yet
    sub     %rcx, %rax
    cmp     S7(%rsp), %rax
    ja      80f
    jmp     90f
4:  mov     %r14, %rax
    sub     %rcx, %rax
    cmp     S7(%rsp), %rax
    ja      80f
    mov     %rcx, %r10                      # the hex size
    xor     %r15d, %r15d
5:  cmp     %r14, %r10
    jae     7f
    movzbl  (%rbx,%r10), %eax
    lea     -'0'(%rax), %r11d
    cmp     $9, %r11d
    jbe     6f
    or      $0x20, %eax
    lea     -'a'(%rax), %r11d
    cmp     $5, %r11d
    ja      7f
    add     $10, %r11d
6:  mov     %r15, %rax
    shr     $60, %rax
    jnz     80f                             # past 2^64 - 1
    shl     $4, %r15
    add     %r11, %r15
    inc     %r10
    jmp     5b
7:  cmp     %rcx, %r10
    je      80f                             # no hex digit
    cmp     %r14, %r10
    jae     72f
    movzbl  (%rbx,%r10), %eax               # an extension: ; space or tab, then no CR, LF or NUL
    cmp     $';', %eax
    je      71f
    cmp     $' ', %eax
    je      71f
    cmp     $9, %eax
    jne     80f
71: cmp     %r14, %r10
    jae     72f
    movzbl  (%rbx,%r10), %eax
    test    %eax, %eax
    jz      80f
    cmp     $10, %eax
    je      80f
    cmp     $13, %eax
    je      80f
    inc     %r10
    jmp     71b
72: lea     2(%r14), %rcx
    test    %r15, %r15
    jz      10f                             # the last chunk
    mov     S8(%rsp), %rax                  # body_max
    sub     %r13, %rax
    cmp     %rax, %r15
    ja      81f
    mov     %rbp, %rax
    sub     %rcx, %rax
    cmp     %rax, %r15
    ja      90f
    sub     %r15, %rax
    cmp     $2, %rax
    jb      90f
    lea     (%rcx,%r15), %rax               # the data, then CRLF
    cmpb    $13, (%rbx,%rax)
    jne     80f
    cmpb    $10, 1(%rbx,%rax)
    jne     80f
    test    %r12, %r12
    jz      9f
    lea     (%rbx,%rcx), %r10               # copy the data
    mov     %r15, %r11
8:  movzbl  (%r10), %eax
    mov     %al, (%r12)
    inc     %r10
    inc     %r12
    dec     %r11
    jnz     8b
9:  add     %r15, %r13
    lea     2(%rcx,%r15), %rcx
    jmp     1b
10: movq    $0, S9(%rsp)                    # trailer lines, skipped, up to the empty line
11: mov     %rcx, %r14
    lea     -1(%rbp), %r10
12: cmp     %r10, %r14
    jge     13f
    cmpb    $13, (%rbx,%r14)
    jne     121f
    cmpb    $10, 1(%rbx,%r14)
    je      14f
121: inc    %r14
    jmp     12b
13: mov     %rbp, %rax
    sub     %rcx, %rax
    add     S9(%rsp), %rax
    cmp     S7(%rsp), %rax
    ja      82f
    jmp     90f
14: lea     2(%r14), %rax
    sub     %rcx, %rax
    add     S9(%rsp), %rax
    mov     %rax, S9(%rsp)
    cmp     S7(%rsp), %rax
    ja      82f
    cmp     %rcx, %r14                      # the empty line ends them
    lea     2(%r14), %rcx
    jne     11b
    mov     $LANTERN_OK, %eax
    mov     %rcx, %rdx
    mov     %r13, %rcx
    LEAVE 16
80: mov     $LANTERN_INVALID_HTTP, %eax
    mov     $400, %edx
    LEAVE 16
81: mov     $LANTERN_INVALID_HTTP, %eax
    mov     $413, %edx
    LEAVE 16
82: mov     $LANTERN_INVALID_HTTP, %eax
    mov     $431, %edx
    LEAVE 16
90: mov     $LANTERN_HTTP_MORE, %eax
    LEAVE 16
END_FUNCTION lantern_http_chunks

# L0: the values of the field lines named by the r8 lower case bytes at rcx, between index rsi and the
# head's CRLF CRLF at rdx of the bytes at rdi, joined with ", ", become a part of HttpRequest r9 at
# the offset of the 7th argument, with its PartRef at r9 + the 8th: rax = the next part's offset.
# The lines are checked before. rbx bytes, rbp the line, r12 the head's end, r13 out, r14 the PartRef,
# r15 the part's end; locals: L name, L+8 its length, L+16 the offset, L+24 the line's end, L+32 the colon.
.set HJ_LOCALS, 48
LOCAL_FUNCTION lantern_http_joined
    ENTER HJ_LOCALS
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, L(%rsp)
    mov     %r8, (L + 8)(%rsp)
    mov     %r9, %r13
    mov     (HJ_LOCALS + 96)(%rsp), %rax    # the 7th argument
    mov     %rax, (L + 16)(%rsp)
    mov     %rax, %r15
    mov     (HJ_LOCALS + 104)(%rsp), %r14   # the 8th
    add     %r13, %r14
    movq    $0, 8(%r14)                     # lines so far: 0
1:  cmp     %r12, %rbp
    ja      9f
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    lea     2(%r12), %rdx
    call    lantern_http_crlf
    mov     %rax, (L + 24)(%rsp)
    mov     %rbx, %rdi
    mov     %rbp, %rsi
    mov     %rax, %rdx
    mov     $':', %ecx
    call    lantern_http_find
    mov     %rax, (L + 32)(%rsp)
    lea     (%rbx,%rbp), %rdi
    mov     %rax, %rsi
    sub     %rbp, %rsi
    mov     L(%rsp), %rdx
    mov     (L + 8)(%rsp), %rcx
    call    lantern_http_same
    test    %rax, %rax
    jz      5f
    mov     %rbx, %rdi
    mov     (L + 32)(%rsp), %rsi
    inc     %rsi
    mov     (L + 24)(%rsp), %rdx
    call    lantern_http_trim
    cmpq    $0, 8(%r14)                     # ", " before all but the first line
    je      2f
    movb    $',', (%r13,%r15)
    movb    $' ', 1(%r13,%r15)
    add     $2, %r15
2:  movq    $1, 8(%r14)
3:  cmp     %rdx, %rax
    jae     5f
    movzbl  (%rbx,%rax), %ecx
    mov     %cl, (%r13,%r15)
    inc     %rax
    inc     %r15
    jmp     3b
5:  mov     (L + 24)(%rsp), %rbp
    add     $2, %rbp
    jmp     1b
9:  mov     (L + 16)(%rsp), %rax
    mov     %rax, (%r14)
    mov     %r15, %rcx
    sub     %rax, %rcx
    mov     %rcx, 8(%r14)
    lea     7(%r15), %rax
    and     $-8, %rax
    LEAVE HJ_LOCALS
END_FUNCTION lantern_http_joined

# The name of the field line at the cursor, the name length's bytes before its colon, is the text at label: jump to dest.
.macro HTTP_NAME label, dest
    mov     (L + 224)(%rsp), %rdi
    add     %rbx, %rdi
    mov     (L + 240)(%rsp), %rsi
    lea     \label(%rip), %rdx
    mov     $\label\()_len, %ecx
    call    lantern_http_same
    test    %rax, %rax
    jnz     \dest
.endm

# lantern_http_joined of the field name at label into the part at field of out, from the offset in rax:
# the 7th and 8th arguments go at S7 and S8. rax = the next part's offset.
.macro HTTP_JOINED label, field
    mov     %rax, S7(%rsp)
    movq    $\field, S8(%rsp)
    mov     %rbx, %rdi
    mov     (L + 216)(%rsp), %rsi
    add     $2, %rsi
    mov     %r15, %rdx
    lea     \label(%rip), %rcx
    mov     $\label\()_len, %r8d
    mov     %r13, %r9
    call    lantern_http_joined
.endm

# acc += rax rounded up to a multiple of 8. Uses rax.
.macro HTTP_ROOM acc
    add     $7, %rax
    and     $-8, %rax
    add     %rax, \acc
.endm

# rbx the bytes, rbp their count, r12 limits, r13 out, r14 the request line, r15 the head's CRLF CRLF.
# Locals: L method, L+8 version, L+16 target start, L+24 target end, L+32 Host lines, L+40
# Transfer-Encoding lines, L+48 1 when one is chunked, L+56 Content-Length lines, L+64 its value,
# L+72 1 when one is bad, L+80 the token close, L+88 the token keep-alive, L+96 Accept bytes and
# L+104 lines, L+112 Content-Type bytes and L+120 lines, L+128 Eth-Consensus-Version bytes and
# L+136 lines, L+144 body start, L+152 body bytes, L+160 used, L+168 a value's start, L+176 its end,
# L+184 the path's end, L+192 1 once a length item is in, L+200 a token's start, L+208 its length,
# L+216 the request line's CRLF, L+224 a line or an item, L+232 the line's end, L+240 a name's length
# or an item's end, L+248 the room.
.set HR_LOCALS, 256
FUNCTION lantern_http_request
    ENTER HR_LOCALS
    cmpq    $HTTP_REQUEST_FIXED, (%rdx)
    jb      97f
    mov     8(%rdi), %rbx
    add     %rdi, %rbx
    mov     16(%rdi), %rbp
    mov     %rsi, %r12
    mov     %rdx, %r13
    lea     L(%rsp), %rdi                   # every local 0
    xor     %eax, %eax
    mov     $(HR_LOCALS / 8), %ecx
1:  mov     %rax, (%rdi)
    add     $8, %rdi
    dec     %ecx
    jnz     1b
    xor     %r14d, %r14d                    # empty lines before the request line
2:  lea     2(%r14), %rax
    cmp     %rbp, %rax
    ja      3f
    cmpb    $13, (%rbx,%r14)
    jne     3f
    cmpb    $10, 1(%rbx,%r14)
    jne     3f
    add     $2, %r14
    jmp     2b
3:  mov     %r14, %r15                      # the head ends at the first CRLF CRLF
4:  lea     4(%r15), %rax
    cmp     %rbp, %rax
    ja      5f
    cmpl    $0x0a0d0a0d, (%rbx,%r15)
    je      6f
    inc     %r15
    jmp     4b
5:  cmp     HttpLimits_head_max(%r12), %rbp
    jae     431f
    jmp     98f
6:  lea     4(%r15), %rax
    cmp     HttpLimits_head_max(%r12), %rax
    ja      431f
    mov     %rbx, %rdi                      # the request line: method SP target SP version
    mov     %r14, %rsi
    lea     2(%r15), %rdx
    call    lantern_http_crlf
    mov     %rax, (L + 216)(%rsp)
    mov     %rbx, %rdi
    mov     %r14, %rsi
    mov     %rax, %rdx
    mov     $' ', %ecx
    call    lantern_http_find
    cmp     (L + 216)(%rsp), %rax
    je      400f
    mov     %rax, (L + 224)(%rsp)           # the first space
    mov     %rbx, %rdi
    mov     %r14, %rsi
    mov     %rax, %rdx
    call    lantern_http_token
    test    %rax, %rax
    jz      400f
    mov     %rbx, %rdi
    mov     (L + 224)(%rsp), %rsi
    inc     %rsi
    mov     (L + 216)(%rsp), %rdx
    mov     $' ', %ecx
    call    lantern_http_find
    cmp     (L + 216)(%rsp), %rax
    je      400f
    mov     %rax, (L + 232)(%rsp)           # the second space
    mov     (L + 224)(%rsp), %rcx           # the target: / then visible bytes
    inc     %rcx
    mov     %rcx, (L + 16)(%rsp)
    mov     %rax, (L + 24)(%rsp)
    cmp     %rax, %rcx
    jae     400f
    cmpb    $'/', (%rbx,%rcx)
    jne     400f
7:  cmp     %rax, %rcx
    jae     8f
    movzbl  (%rbx,%rcx), %edx
    sub     $0x21, %edx
    cmp     $(0x7e - 0x21), %edx
    ja      400f
    inc     %rcx
    jmp     7b
8:  mov     (L + 216)(%rsp), %rcx           # the version: HTTP/ digit . digit
    sub     %rax, %rcx
    cmp     $9, %rcx
    jne     400f
    lea     (%rbx,%rax), %rcx
    cmpb    $'H', 1(%rcx)
    jne     400f
    cmpb    $'T', 2(%rcx)
    jne     400f
    cmpb    $'T', 3(%rcx)
    jne     400f
    cmpb    $'P', 4(%rcx)
    jne     400f
    cmpb    $'/', 5(%rcx)
    jne     400f
    cmpb    $'.', 7(%rcx)
    jne     400f
    movzbl  6(%rcx), %edx
    sub     $'0', %edx
    cmp     $9, %edx
    ja      400f
    movzbl  8(%rcx), %esi
    sub     $'0', %esi
    cmp     $9, %esi
    ja      400f
    cmp     $1, %edx
    jne     505f
    mov     $11, %eax
    cmp     $1, %esi
    je      9f
    test    %esi, %esi
    jnz     505f
    mov     $10, %eax
9:  mov     %rax, (L + 8)(%rsp)
    mov     (L + 224)(%rsp), %rcx           # the method
    sub     %r14, %rcx
    mov     $HTTP_METHOD_OTHER, %eax
    lea     (%rbx,%r14), %rdx
    cmp     $3, %rcx
    jne     10f
    cmpw    $0x4547, (%rdx)                 # GE
    jne     11f
    cmpb    $'T', 2(%rdx)
    jne     11f
    mov     $HTTP_METHOD_GET, %eax
    jmp     11f
10: cmp     $4, %rcx
    jne     11f
    cmpl    $0x54534f50, (%rdx)             # POST
    jne     11f
    mov     $HTTP_METHOD_POST, %eax
11: mov     %rax, L(%rsp)
    mov     (L + 216)(%rsp), %rax           # each field line, up to the head's CRLF CRLF
    add     $2, %rax
    mov     %rax, (L + 224)(%rsp)
12: mov     (L + 224)(%rsp), %rsi
    cmp     %r15, %rsi
    ja      30f
    mov     %rbx, %rdi
    lea     2(%r15), %rdx
    call    lantern_http_crlf
    mov     %rax, (L + 232)(%rsp)
    mov     (L + 224)(%rsp), %rsi
    movzbl  (%rbx,%rsi), %ecx               # no folded line
    cmp     $' ', %ecx
    je      400f
    cmp     $9, %ecx
    je      400f
    mov     %rbx, %rdi
    mov     %rax, %rdx
    mov     $':', %ecx
    call    lantern_http_find
    cmp     (L + 232)(%rsp), %rax
    je      400f
    mov     (L + 224)(%rsp), %rsi
    sub     %rsi, %rax                      # the name's length
    jz      400f
    mov     %rax, (L + 240)(%rsp)
    mov     %rbx, %rdi
    lea     (%rsi,%rax), %rdx
    call    lantern_http_token
    test    %rax, %rax
    jz      400f
    mov     %rbx, %rdi                      # the value, without spaces and tabs around it
    mov     (L + 224)(%rsp), %rsi
    add     (L + 240)(%rsp), %rsi
    inc     %rsi
    mov     (L + 232)(%rsp), %rdx
    call    lantern_http_trim
    mov     %rax, (L + 168)(%rsp)
    mov     %rdx, (L + 176)(%rsp)
13: cmp     %rdx, %rax                      # no CR, LF or NUL
    jae     14f
    movzbl  (%rbx,%rax), %ecx
    test    %ecx, %ecx
    jz      400f
    cmp     $10, %ecx
    je      400f
    cmp     $13, %ecx
    je      400f
    inc     %rax
    jmp     13b
14: HTTP_NAME http_n_host, 20f
    HTTP_NAME http_n_length, 21f
    HTTP_NAME http_n_te, 22f
    HTTP_NAME http_n_connection, 23f
    HTTP_NAME http_n_accept, 24f
    HTTP_NAME http_n_type, 25f
    HTTP_NAME http_n_version, 26f
    jmp     29f
20: incq    (L + 32)(%rsp)                  # Host
    jmp     29f
21: incq    (L + 56)(%rsp)                  # Content-Length: a list of equal decimal values
    mov     (L + 168)(%rsp), %rax
    mov     %rax, (L + 224)(%rsp)
211: mov    %rbx, %rdi                      # an item: up to the next comma
    mov     (L + 224)(%rsp), %rsi
    mov     (L + 176)(%rsp), %rdx
    mov     $',', %ecx
    call    lantern_http_find
    mov     %rax, (L + 240)(%rsp)
    mov     %rbx, %rdi
    mov     (L + 224)(%rsp), %rsi
    mov     %rax, %rdx
    call    lantern_http_trim
    cmp     %rdx, %rax
    jae     218f                            # empty
    xor     %ecx, %ecx
212: cmp    %rdx, %rax
    jae     213f
    movzbl  (%rbx,%rax), %esi
    sub     $'0', %esi
    cmp     $9, %esi
    ja      218f
    mov     %rax, %rdi
    mov     %rcx, %rax
    mov     %rdx, %r8
    mov     $10, %r9d
    mul     %r9
    jc      218f
    add     %rsi, %rax
    jc      218f
    mov     %rax, %rcx
    mov     %r8, %rdx
    lea     1(%rdi), %rax
    jmp     212b
213: cmpq   $0, (L + 192)(%rsp)             # the first item sets the length; the others match it
    jne     214f
    mov     %rcx, (L + 64)(%rsp)
    movq    $1, (L + 192)(%rsp)
    jmp     215f
214: cmp    (L + 64)(%rsp), %rcx
    jne     218f
215: mov    (L + 240)(%rsp), %rax
    cmp     (L + 176)(%rsp), %rax
    jae     29f
    inc     %rax
    mov     %rax, (L + 224)(%rsp)
    jmp     211b
218: movq   $1, (L + 72)(%rsp)
    jmp     29f
22: incq    (L + 40)(%rsp)                  # Transfer-Encoding
    mov     (L + 168)(%rsp), %rdi
    mov     (L + 176)(%rsp), %rsi
    sub     %rdi, %rsi
    add     %rbx, %rdi
    lea     http_t_chunked(%rip), %rdx
    mov     $http_t_chunked_len, %ecx
    call    lantern_http_same
    mov     %rax, (L + 48)(%rsp)
    jmp     29f
23: mov     (L + 168)(%rsp), %rax           # Connection: its tokens
    mov     %rax, (L + 224)(%rsp)
231: mov    %rbx, %rdi
    mov     (L + 224)(%rsp), %rsi
    mov     (L + 176)(%rsp), %rdx
    mov     $',', %ecx
    call    lantern_http_find
    mov     %rax, (L + 240)(%rsp)
    mov     %rbx, %rdi
    mov     (L + 224)(%rsp), %rsi
    mov     %rax, %rdx
    call    lantern_http_trim
    sub     %rax, %rdx
    mov     %rax, (L + 200)(%rsp)
    mov     %rdx, (L + 208)(%rsp)
    lea     (%rbx,%rax), %rdi
    mov     %rdx, %rsi
    lea     http_t_close(%rip), %rdx
    mov     $http_t_close_len, %ecx
    call    lantern_http_same
    test    %rax, %rax
    jz      232f
    movq    $1, (L + 80)(%rsp)
232: mov    (L + 200)(%rsp), %rdi
    add     %rbx, %rdi
    mov     (L + 208)(%rsp), %rsi
    lea     http_t_keep_alive(%rip), %rdx
    mov     $http_t_keep_alive_len, %ecx
    call    lantern_http_same
    test    %rax, %rax
    jz      233f
    movq    $1, (L + 88)(%rsp)
233: mov    (L + 240)(%rsp), %rax
    cmp     (L + 176)(%rsp), %rax
    jae     29f
    inc     %rax
    mov     %rax, (L + 224)(%rsp)
    jmp     231b
24: lea     (L + 96)(%rsp), %rdi            # Accept, Content-Type, Eth-Consensus-Version: their joined bytes
    jmp     27f
25: lea     (L + 112)(%rsp), %rdi
    jmp     27f
26: lea     (L + 128)(%rsp), %rdi
27: mov     (L + 176)(%rsp), %rax
    sub     (L + 168)(%rsp), %rax
    cmpq    $0, 8(%rdi)
    je      28f
    add     $2, %rax
28: add     %rax, (%rdi)
    incq    8(%rdi)
29: mov     (L + 232)(%rsp), %rax           # the next line
    add     $2, %rax
    mov     %rax, (L + 224)(%rsp)
    jmp     12b
30: mov     (L + 32)(%rsp), %rax            # Host: at most one; one in HTTP/1.1
    cmp     $1, %rax
    ja      400f
    cmpq    $11, (L + 8)(%rsp)
    jne     31f
    test    %rax, %rax
    jz      400f
31: mov     (L + 40)(%rsp), %rax            # Transfer-Encoding: chunked alone
    test    %rax, %rax
    jz      32f
    cmpq    $0, (L + 56)(%rsp)
    jne     400f
    cmpq    $10, (L + 8)(%rsp)
    je      400f
    cmp     $1, %rax
    jne     501f
    cmpq    $0, (L + 48)(%rsp)
    je      501f
32: cmpq    $0, (L + 56)(%rsp)              # Content-Length
    je      33f
    cmpq    $0, (L + 72)(%rsp)
    jne     400f
    mov     (L + 64)(%rsp), %rax
    cmp     HttpLimits_body_max(%r12), %rax
    ja      413f
33: cmpq    $0, (L + 80)(%rsp)              # close: the token close, or HTTP/1.0 without keep-alive
    jne     34f
    xor     %eax, %eax
    cmpq    $10, (L + 8)(%rsp)
    jne     35f
    cmpq    $0, (L + 88)(%rsp)
    jne     35f
34: mov     $1, %eax
35: mov     %rax, (L + 80)(%rsp)
    lea     4(%r15), %rsi                   # the body
    mov     %rsi, (L + 144)(%rsp)
    cmpq    $0, (L + 56)(%rsp)
    je      36f
    mov     (L + 64)(%rsp), %rax
    mov     %rbp, %rcx
    sub     %rsi, %rcx
    cmp     %rax, %rcx
    jb      98f
    mov     %rax, (L + 152)(%rsp)
    add     %rax, %rsi
    jmp     40f
36: cmpq    $0, (L + 40)(%rsp)
    je      40f
    xor     %edi, %edi                      # chunked: check the framing, count the bytes
    mov     %rsi, %rcx
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    mov     HttpLimits_head_max(%r12), %r8
    mov     HttpLimits_body_max(%r12), %r9
    call    lantern_http_chunks
    cmp     $LANTERN_HTTP_MORE, %rax
    je      98f
    cmp     $LANTERN_INVALID_HTTP, %rax
    jne     37f
    mov     %rdx, %rax
    jmp     96f
37: mov     %rcx, (L + 152)(%rsp)
    mov     %rdx, %rsi
40: mov     %rsi, (L + 160)(%rsp)           # used; then the room the parts need
    mov     %rbx, %rdi
    mov     (L + 16)(%rsp), %rsi
    mov     (L + 24)(%rsp), %rdx
    mov     $'?', %ecx
    call    lantern_http_find
    mov     %rax, (L + 184)(%rsp)           # the path's end
    mov     $HTTP_REQUEST_FIXED, %r8d
    sub     (L + 16)(%rsp), %rax
    HTTP_ROOM %r8
    mov     (L + 24)(%rsp), %rax
    sub     (L + 184)(%rsp), %rax
    jz      41f
    dec     %rax                            # the query: after the ?
41: HTTP_ROOM %r8
    mov     (L + 96)(%rsp), %rax
    HTTP_ROOM %r8
    mov     (L + 112)(%rsp), %rax
    HTTP_ROOM %r8
    mov     (L + 128)(%rsp), %rax
    HTTP_ROOM %r8
    mov     (L + 152)(%rsp), %rax
    HTTP_ROOM %r8
    cmp     (%r13), %r8
    ja      97f
    movq    $0, HttpRequest_status(%r13)
    mov     (L + 160)(%rsp), %rax
    mov     %rax, HttpRequest_used(%r13)
    mov     L(%rsp), %rax
    mov     %rax, HttpRequest_method(%r13)
    mov     (L + 8)(%rsp), %rax
    mov     %rax, HttpRequest_version(%r13)
    mov     (L + 80)(%rsp), %rax
    mov     %rax, HttpRequest_close(%r13)
    mov     %r13, %rdi                      # path
    mov     $HTTP_REQUEST_FIXED, %esi
    mov     (L + 16)(%rsp), %rdx
    mov     (L + 184)(%rsp), %rcx
    sub     %rdx, %rcx
    add     %rbx, %rdx
    mov     $HttpRequest_path, %r8d
    call    lantern_http_part
    mov     %r13, %rdi                      # query
    mov     %rax, %rsi
    mov     (L + 184)(%rsp), %rdx
    mov     (L + 24)(%rsp), %rax
    xor     %ecx, %ecx
    cmp     %rax, %rdx
    jae     42f
    inc     %rdx
    mov     %rax, %rcx
    sub     %rdx, %rcx
42: add     %rbx, %rdx
    mov     $HttpRequest_query, %r8d
    call    lantern_http_part
    HTTP_JOINED http_n_accept, HttpRequest_accept     # the three fields
    HTTP_JOINED http_n_type, HttpRequest_content_type
    HTTP_JOINED http_n_version, HttpRequest_consensus_version
    mov     %rax, %rsi                      # body
    cmpq    $0, (L + 40)(%rsp)
    jne     44f
    mov     %r13, %rdi
    mov     (L + 144)(%rsp), %rdx
    add     %rbx, %rdx
    mov     (L + 152)(%rsp), %rcx
    mov     $HttpRequest_body, %r8d
    call    lantern_http_part
    jmp     45f
44: mov     %rsi, HttpRequest_body(%r13)    # chunked: its bytes, unchunked
    mov     (L + 152)(%rsp), %rax
    mov     %rax, (HttpRequest_body + 8)(%r13)
    lea     (%r13,%rsi), %rdi
    mov     %rbx, %rsi
    mov     %rbp, %rdx
    mov     (L + 144)(%rsp), %rcx
    mov     HttpLimits_head_max(%r12), %r8
    mov     HttpLimits_body_max(%r12), %r9
    call    lantern_http_chunks
45: xor     %eax, %eax
    LEAVE HR_LOCALS
400: mov    $400, %eax
    jmp     96f
413: mov    $413, %eax
    jmp     96f
431: mov    $431, %eax
    jmp     96f
501: mov    $501, %eax
    jmp     96f
505: mov    $505, %eax
96: mov     %rax, HttpRequest_status(%r13)
    movq    $1, HttpRequest_close(%r13)
    mov     $LANTERN_INVALID_HTTP, %eax
    LEAVE HR_LOCALS
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE HR_LOCALS
98: mov     $LANTERN_HTTP_MORE, %eax
    LEAVE HR_LOCALS
END_FUNCTION lantern_http_request
