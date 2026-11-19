/*
 * lantern_api_route, x86-64: in the common object. Requirements: docs/reference/beacon-api.md.
 * Uses http_find, http_trim and http_same of http.s.
 */

    API_ROUTE_DATA
    .p2align 3
route_base58:                               # the base58btc alphabet, a bit each
    .quad   0x03fe000000000000, 0x07ffeffe07ff7dfe
route_t_json:
    .ascii  "application/json"
.set route_t_json_len, 16
route_t_ssz:
    .ascii  "application/octet-stream"
.set route_t_ssz_len, 24
route_t_any_application:
    .ascii  "application/*"
.set route_t_any_application_len, 13
route_t_any:
    .ascii  "*/*"
.set route_t_any_len, 3

# reg = the value of the hex digit in reg (either case), else jump to bad. 32-bit registers. Uses tmp.
.macro ROUTE_HEX reg, tmp, bad
    mov     \reg, \tmp
    sub     $'0', \tmp
    cmp     $9, \tmp
    jbe     77f
    mov     \reg, \tmp
    or      $0x20, \tmp
    sub     $'a', \tmp
    cmp     $5, \tmp
    ja      \bad
    add     $10, \tmp
77: mov     \tmp, \reg
.endm

# L0: rax = 1 when each % of the rsi bytes at rdi is followed by two hex digits, else 0. A leaf. Uses rcx, rdx, r8.
LOCAL_FUNCTION route_pct_ok
    UNWIND_END_PROLOGUE
    xor     %ecx, %ecx
1:  cmp     %rsi, %rcx
    jae     9f
    movzbl  (%rdi,%rcx), %eax
    inc     %rcx
    cmp     $0x25, %eax
    jne     1b
    lea     2(%rcx), %rdx
    cmp     %rsi, %rdx
    ja      8f
    movzbl  (%rdi,%rcx), %eax
    ROUTE_HEX %eax, %r8d, 8f
    movzbl  1(%rdi,%rcx), %eax
    ROUTE_HEX %eax, %r8d, 8f
    add     $2, %rcx
    jmp     1b
8:  xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION route_pct_ok

# L0: the rsi bytes at rdi, percent-decoded (each % is followed by two hex digits), to rdx: at most rcx
# bytes written; rax = the decoded length, which may pass rcx. A leaf. Uses r8-r11.
LOCAL_FUNCTION route_decode
    UNWIND_END_PROLOGUE
    xor     %r8d, %r8d
    xor     %r9d, %r9d
1:  cmp     %rsi, %r8
    jae     9f
    movzbl  (%rdi,%r8), %r10d
    inc     %r8
    cmp     $0x25, %r10d
    jne     2f
    movzbl  (%rdi,%r8), %r10d
    ROUTE_HEX %r10d, %r11d, 9f
    movzbl  1(%rdi,%r8), %eax
    ROUTE_HEX %eax, %r11d, 9f
    shl     $4, %r10d
    or      %eax, %r10d
    add     $2, %r8
2:  cmp     %rcx, %r9
    jae     3f
    mov     %r10b, (%rdx,%r9)
3:  inc     %r9
    jmp     1b
9:  mov     %r9, %rax
    ret
END_FUNCTION route_decode

# L0: one item of a list value: the bytes at rdi from index rsi to index rdx, percent-decoded, up to
# the first decoded `,`, to rcx with at most r8 bytes written. rax = the index after the item and its
# comma, rdx = the item's decoded length (it may pass r8), rcx = 1 when a comma ended it. A leaf. Uses r9-r11.
LOCAL_FUNCTION route_next_item
    UNWIND_END_PROLOGUE
    xor     %r9d, %r9d
1:  cmp     %rdx, %rsi
    jae     9f
    movzbl  (%rdi,%rsi), %r10d
    inc     %rsi
    cmp     $0x25, %r10d
    jne     2f
    movzbl  (%rdi,%rsi), %r10d
    ROUTE_HEX %r10d, %eax, 9f
    movzbl  1(%rdi,%rsi), %eax
    ROUTE_HEX %eax, %r11d, 9f
    shl     $4, %r10d
    or      %eax, %r10d
    add     $2, %rsi
2:  cmp     $0x2c, %r10d
    je      8f
    cmp     %r8, %r9
    jae     3f
    mov     %r10b, (%rcx,%r9)
3:  inc     %r9
    jmp     1b
8:  mov     $1, %ecx
    jmp     91f
9:  xor     %ecx, %ecx
91: mov     %rsi, %rax
    mov     %r9, %rdx
    ret
END_FUNCTION route_next_item

# L0: the rsi bytes at rdi as a decimal number below 2^64: rax = 0 and rdx = its value, else rax = 1. A leaf. Uses rcx, r8, r9.
LOCAL_FUNCTION route_number
    UNWIND_END_PROLOGUE
    test    %rsi, %rsi
    jz      8f
    xor     %eax, %eax
    xor     %ecx, %ecx
    mov     $10, %r9d
1:  cmp     %rsi, %rcx
    jae     9f
    movzbl  (%rdi,%rcx), %r8d
    sub     $'0', %r8d
    cmp     $9, %r8d
    ja      8f
    mul     %r9
    jc      8f
    add     %r8, %rax
    jc      8f
    inc     %rcx
    jmp     1b
8:  mov     $1, %eax
    ret
9:  mov     %rax, %rdx
    xor     %eax, %eax
    ret
END_FUNCTION route_number

# L0: the rsi bytes at rdi as 0x and the hex of rdx bytes: rax = 0 and the bytes at rcx, else rax = 1. A leaf. Uses r8, r9.
LOCAL_FUNCTION route_hex
    UNWIND_END_PROLOGUE
    lea     2(%rdx,%rdx), %rax
    cmp     %rax, %rsi
    jne     8f
    cmpb    $'0', (%rdi)
    jne     8f
    cmpb    $'x', 1(%rdi)
    jne     8f
    add     $2, %rdi
1:  test    %rdx, %rdx
    jz      9f
    movzbl  (%rdi), %eax
    ROUTE_HEX %eax, %r8d, 8f
    movzbl  1(%rdi), %r9d
    ROUTE_HEX %r9d, %r8d, 8f
    shl     $4, %eax
    or      %r9d, %eax
    mov     %al, (%rcx)
    add     $2, %rdi
    inc     %rcx
    dec     %rdx
    jmp     1b
8:  mov     $1, %eax
    ret
9:  xor     %eax, %eax
    ret
END_FUNCTION route_hex

# L0: the word of api_words for parameter rdi that is the rdx bytes at rsi: rax = 1 and rdx = its value, else rax = 0. A leaf. Uses rcx, r8-r11.
LOCAL_FUNCTION route_word
    UNWIND_END_PROLOGUE
    lea     api_words(%rip), %r8
    lea     api_word_text(%rip), %r9
    mov     $API_WORDS, %ecx
1:  test    %rcx, %rcx
    jz      8f
    cmp     %rdi, (%r8)
    jne     5f
    cmp     %rdx, 16(%r8)
    jne     5f
    mov     8(%r8), %r10
    add     %r9, %r10
    xor     %r11d, %r11d
2:  cmp     %rdx, %r11
    jae     7f
    movzbl  (%r10,%r11), %eax
    cmp     %al, (%rsi,%r11)
    jne     5f
    inc     %r11
    jmp     2b
7:  mov     24(%r8), %rdx
    mov     $1, %eax
    ret
5:  add     $32, %r8
    dec     %rcx
    jmp     1b
8:  xor     %eax, %eax
    ret
END_FUNCTION route_word

# L0: whether the rsi bytes at rdi, a path whose percent-encoding is good, match the template of rcx
# bytes at rdx: rax = 1 or 0. Each parameter segment goes to the list at r8: its count, then for each
# its API_PARAM_*, start and end in the path. rbx the path's index, rbp the template's, r12 the count.
LOCAL_FUNCTION route_match
    ENTER 0
    mov     $1, %ebx
    mov     $1, %ebp
    xor     %r12d, %r12d
    movq    $0, (%r8)
1:  cmp     %rcx, %rbp
    jae     8f
    movzbl  (%rdx,%rbp), %eax
    cmp     $0x20, %eax
    jae     3f
    mov     %rbx, %r9                       # a parameter: up to the next /
2:  cmp     %rsi, %rbx
    jae     21f
    cmpb    $0x2f, (%rdi,%rbx)
    je      21f
    inc     %rbx
    jmp     2b
21: cmp     %r9, %rbx
    je      7f
    imul    $24, %r12, %r11
    add     %r8, %r11
    mov     %rax, 8(%r11)
    mov     %r9, 16(%r11)
    mov     %rbx, 24(%r11)
    inc     %r12
    mov     %r12, (%r8)
    inc     %rbp
    jmp     1b
3:  cmp     $0x2f, %eax                     # a separator: a / of the path itself
    jne     4f
    cmp     %rsi, %rbx
    jae     7f
    cmpb    $0x2f, (%rdi,%rbx)
    jne     7f
    inc     %rbx
    inc     %rbp
    jmp     1b
4:  cmp     %rsi, %rbx                      # a fixed byte: the path's next decoded byte
    jae     7f
    movzbl  (%rdi,%rbx), %r11d
    inc     %rbx
    cmp     $0x25, %r11d
    jne     5f
    movzbl  (%rdi,%rbx), %r11d
    ROUTE_HEX %r11d, %r10d, 7f
    movzbl  1(%rdi,%rbx), %r9d
    ROUTE_HEX %r9d, %r10d, 7f
    shl     $4, %r11d
    or      %r9d, %r11d
    add     $2, %rbx
5:  cmp     %eax, %r11d
    jne     7f
    inc     %rbp
    jmp     1b
8:  xor     %eax, %eax
    cmp     %rsi, %rbx
    sete    %al
    LEAVE 0
7:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION route_match

# L0: the rcx decoded bytes at rdx as a value of parameter rsi, into ApiRoute rdi; an item of a list
# goes to the 64 bytes at r8. rax = 0, or 1 when the value breaks its type.
# rbx out, rbp the parameter, r12 bytes, r13 length, r14 the item's place, r15 the field.
LOCAL_FUNCTION route_value
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    lea     api_params(%rip), %rax
    mov     %rbp, %rcx
    shl     $5, %rcx
    add     %rcx, %rax
    mov     24(%rax), %r15
    mov     16(%rax), %rax
    cmp     $API_KIND_NUMBER, %rax
    je      10f
    cmp     $API_KIND_STATE_ID, %rax
    je      11f
    cmp     $API_KIND_BLOCK_ID, %rax
    je      11f
    cmp     $API_KIND_BLOCK_ROOT, %rax
    je      13f
    cmp     $API_KIND_VALIDATOR, %rax
    je      14f
    cmp     $API_KIND_ID_LIST, %rax
    je      15f
    cmp     $API_KIND_PEER_ID, %rax
    je      16f
    cmp     $API_KIND_SYNCING, %rax
    je      17f
    cmp     $API_KIND_ROOT, %rax
    je      18f
    cmp     $API_KIND_RANDAO, %rax
    je      19f
    cmp     $API_KIND_GRAFFITI, %rax
    je      20f
    cmp     $API_KIND_FLAG, %rax
    je      21f
    cmp     $API_KIND_WORD, %rax
    je      22f
    cmp     $API_KIND_SET, %rax
    je      23f
    cmp     $API_KIND_INDEX_LIST, %rax
    je      24f
    cmp     $API_KIND_HASH_LIST, %rax
    je      25f
    jmp     98f
10: mov     %r12, %rdi                      # a number, to its field
    mov     %r13, %rsi
    call    route_number
    test    %eax, %eax
    jnz     98f
    mov     %rdx, (%rbx,%r15)
    jmp     90f
11: mov     %rbp, %rdi                      # state_id, block_id: a word, a slot or a root
    mov     %r12, %rsi
    mov     %r13, %rdx
    call    route_word
    test    %eax, %eax
    jz      12f
    mov     %rdx, ApiRoute_id_kind(%rbx)
    jmp     90f
12: mov     %r12, %rdi
    mov     %r13, %rsi
    call    route_number
    test    %eax, %eax
    jnz     13f
    movq    $API_ID_SLOT, ApiRoute_id_kind(%rbx)
    mov     %rdx, ApiRoute_id_slot(%rbx)
    jmp     90f
13: mov     %r12, %rdi                      # a root
    mov     %r13, %rsi
    mov     $32, %edx
    lea     ApiRoute_id_root(%rbx), %rcx
    call    route_hex
    test    %eax, %eax
    jnz     98f
    movq    $API_ID_ROOT, ApiRoute_id_kind(%rbx)
    jmp     90f
14: lea     ApiRoute_validator(%rbx), %r14  # validator_id, an id: an index or a public key
15: xor     %eax, %eax
    mov     %rax, (%r14)
    mov     %rax, 8(%r14)
    mov     %rax, 16(%r14)
    mov     %rax, 24(%r14)
    mov     %rax, 32(%r14)
    mov     %rax, 40(%r14)
    mov     %rax, 48(%r14)
    mov     %rax, 56(%r14)
    mov     %r12, %rdi
    mov     %r13, %rsi
    call    route_number
    test    %eax, %eax
    jnz     151f
    movq    $API_VALIDATOR_INDEX, (%r14)
    mov     %rdx, 8(%r14)
    jmp     90f
151: mov    %r12, %rdi
    mov     %r13, %rsi
    mov     $48, %edx
    lea     ValidatorRef_pubkey(%r14), %rcx
    call    route_hex
    test    %eax, %eax
    jnz     98f
    movq    $API_VALIDATOR_PUBKEY, (%r14)
    jmp     90f
16: test    %r13, %r13                      # peer_id: 1 to 128 bytes of base58btc
    jz      98f
    cmp     $128, %r13
    ja      98f
    lea     route_base58(%rip), %r8
    xor     %ecx, %ecx
161: cmp    %r13, %rcx
    jae     90f
    movzbl  (%r12,%rcx), %eax
    cmp     $127, %eax
    ja      98f
    bt      %rax, (%r8)
    jnc     98f
    inc     %rcx
    jmp     161b
17: mov     %r12, %rdi                      # syncing_status: 100 to 599
    mov     %r13, %rsi
    call    route_number
    test    %eax, %eax
    jnz     98f
    cmp     $100, %rdx
    jb      98f
    cmp     $599, %rdx
    ja      98f
    mov     %rdx, (%rbx,%r15)
    jmp     90f
18: mov     $32, %edx                       # hex to its field: a root, the reveal, the graffiti
    jmp     26f
19: mov     $96, %edx
    jmp     26f
20: mov     $32, %edx
26: mov     %r12, %rdi
    mov     %r13, %rsi
    lea     (%rbx,%r15), %rcx
    call    route_hex
    test    %eax, %eax
    jnz     98f
    jmp     90f
21: test    %r13, %r13                      # skip_randao_verification: empty
    jnz     98f
    jmp     90f
22: mov     %rbp, %rdi                      # broadcast_validation: a word
    mov     %r12, %rsi
    mov     %r13, %rdx
    call    route_word
    test    %eax, %eax
    jz      98f
    mov     %rdx, (%rbx,%r15)
    jmp     90f
23: mov     %rbp, %rdi                      # a set: the word's bits
    mov     %r12, %rsi
    mov     %r13, %rdx
    call    route_word
    test    %eax, %eax
    jz      98f
    or      %rdx, (%rbx,%r15)
    jmp     90f
24: mov     %r12, %rdi                      # indices: a number
    mov     %r13, %rsi
    call    route_number
    test    %eax, %eax
    jnz     98f
    mov     %rdx, (%r14)
    jmp     90f
25: mov     %r12, %rdi                      # versioned_hashes: a root
    mov     %r13, %rsi
    mov     $32, %edx
    mov     %r14, %rcx
    call    route_hex
    test    %eax, %eax
    jnz     98f
90: xor     %eax, %eax
    LEAVE 0
98: mov     $1, %eax
    LEAVE 0
END_FUNCTION route_value

# L0: the weight, 0 to 1000, that the Accept value of rsi bytes at rdi gives the media type of rcx
# lower case bytes at rdx (lantern_api_route's rules). rbx bytes, rbp length, r12 media, r13 its
# length, r14 the best kind of range (-1 none, 0 any type, 1 any application type, 2 the type), r15
# its weight; S7 an item's start, S8 its end, S9 a parameter's start, S10 a range's kind; L the
# item's weight, L+8 the range's end or the next parameter's end.
LOCAL_FUNCTION route_weight
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     $-1, %r14
    xor     %r15d, %r15d
    movq    $0, S7(%rsp)
1:  mov     S7(%rsp), %rsi                  # each item, up to a ,
    cmp     %rbp, %rsi
    ja      9f
    mov     %rbx, %rdi
    mov     %rbp, %rdx
    mov     $0x2c, %ecx
    call    http_find
    mov     %rax, S8(%rsp)
    mov     %rbx, %rdi                      # the range: up to the first ;
    mov     S7(%rsp), %rsi
    mov     %rax, %rdx
    mov     $0x3b, %ecx
    call    http_find
    mov     %rax, S9(%rsp)
    mov     %rbx, %rdi
    mov     S7(%rsp), %rsi
    mov     %rax, %rdx
    call    http_trim
    mov     %rax, L(%rsp)
    mov     %rdx, (L + 8)(%rsp)
    lea     (%rbx,%rax), %rdi
    mov     %rdx, %rsi
    sub     %rax, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    call    http_same
    movq    $2, S10(%rsp)
    test    %eax, %eax
    jnz     3f
    mov     L(%rsp), %rax
    lea     (%rbx,%rax), %rdi
    mov     (L + 8)(%rsp), %rsi
    sub     %rax, %rsi
    lea     route_t_any_application(%rip), %rdx
    mov     $route_t_any_application_len, %ecx
    call    http_same
    movq    $1, S10(%rsp)
    test    %eax, %eax
    jnz     3f
    mov     L(%rsp), %rax
    lea     (%rbx,%rax), %rdi
    mov     (L + 8)(%rsp), %rsi
    sub     %rax, %rsi
    lea     route_t_any(%rip), %rdx
    mov     $route_t_any_len, %ecx
    call    http_same
    movq    $0, S10(%rsp)
    test    %eax, %eax
    jz      8f                              # a range of another type: skipped
3:  movq    $1000, L(%rsp)                  # the parameters: q= sets the weight
4:  mov     S9(%rsp), %rsi
    cmp     S8(%rsp), %rsi
    jae     7f
    inc     %rsi
    mov     %rsi, S9(%rsp)
    mov     %rbx, %rdi
    mov     S8(%rsp), %rdx
    mov     $0x3b, %ecx
    call    http_find
    mov     %rax, (L + 8)(%rsp)
    mov     %rbx, %rdi
    mov     S9(%rsp), %rsi
    mov     %rax, %rdx
    call    http_trim
    mov     (L + 8)(%rsp), %rcx
    mov     %rcx, S9(%rsp)
    mov     %rdx, %r8                       # rax, rdx: the parameter
    sub     %rax, %r8
    cmp     $2, %r8
    jb      4b
    lea     (%rbx,%rax), %r9
    movzbl  (%r9), %eax
    or      $0x20, %eax
    cmp     $'q', %eax
    jne     4b
    cmpb    $0x3d, 1(%r9)
    jne     4b
    add     $2, %r9                         # the value: 0, 0.ddd or 1, 1.000
    sub     $2, %r8
    jz      8f
    cmp     $1, %r8
    je      5f
    cmp     $5, %r8
    ja      8f
    cmpb    $0x2e, 1(%r9)
    jne     8f
5:  movzbl  (%r9), %eax
    cmp     $'1', %eax
    je      6f
    cmp     $'0', %eax
    jne     8f
    xor     %ecx, %ecx                      # 0.ddd: the digits, then scaled to thousandths
    mov     $2, %edx
51: cmp     %r8, %rdx
    jae     52f
    movzbl  (%r9,%rdx), %eax
    sub     $'0', %eax
    cmp     $9, %eax
    ja      8f
    imul    $10, %rcx, %rcx
    add     %rax, %rcx
    inc     %rdx
    jmp     51b
52: cmp     $5, %rdx
    jae     53f
    imul    $10, %rcx, %rcx
    inc     %rdx
    jmp     52b
53: cmp     $1, %r8
    jne     54f
    xor     %ecx, %ecx
54: mov     %rcx, L(%rsp)
    jmp     4b
6:  mov     $2, %edx                        # 1.000
61: cmp     %r8, %rdx
    jae     62f
    cmpb    $'0', (%r9,%rdx)
    jne     8f
    inc     %rdx
    jmp     61b
62: movq    $1000, L(%rsp)
    jmp     4b
7:  mov     L(%rsp), %rcx                   # the most specific range, then the heaviest
    mov     S10(%rsp), %rax
    cmp     %r14, %rax
    jg      71f
    jl      8f
    cmp     %r15, %rcx
    jbe     8f
71: mov     %rax, %r14
    mov     %rcx, %r15
8:  mov     S8(%rsp), %rax
    inc     %rax
    mov     %rax, S7(%rsp)
    jmp     1b
9:  xor     %eax, %eax
    test    %r14, %r14
    js      91f
    mov     %r15, %rax
91: LEAVE 16
END_FUNCTION route_weight

# rbx the request, rbp out, r12 a path parameter's entry or a query item's start, r13 their count or
# the item's end, r14 the operation's entry of api_routes, r15 the query; S7 its length, S8 present,
# S9 the list's items, S10 the parameter at hand. Locals: L the path parameters (a count, then
# API_PARAM_*, start, end for each, 2 at most), L+56 1 when the list has no room, L+64 the size of a
# list item, L+72 and L+80 the peer id's start and end in the path, L+88 its length, L+96 the end of
# an item's name, L+104 a value's cursor, L+112 1 when a comma ended an item, L+120 a count, L+128 an
# item (64 bytes), L+192 a decoded value (200 bytes).
FUNCTION lantern_api_route
    ENTER 400
    cmpq    $API_ROUTE_FIXED, (%rsi)
    jb      97f
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     8(%rbp), %rdi                   # every field after size 0
    mov     $((API_ROUTE_FIXED - 8) / 8), %ecx
    xor     %eax, %eax
1:  mov     %rax, (%rdi)
    add     $8, %rdi
    dec     %ecx
    jnz     1b
    lea     L(%rsp), %rdi
    mov     $16, %ecx
2:  mov     %rax, (%rdi)
    add     $8, %rdi
    dec     %ecx
    jnz     2b
    mov     %rax, S8(%rsp)
    mov     %rax, S9(%rsp)
    mov     %rax, S10(%rsp)
    mov     HttpRequest_path(%rbx), %r12
    add     %rbx, %r12
    mov     (HttpRequest_path + 8)(%rbx), %r13
    mov     HttpRequest_query(%rbx), %r15
    add     %rbx, %r15
    mov     (HttpRequest_query + 8)(%rbx), %rax
    mov     %rax, S7(%rsp)
    mov     %r12, %rdi                      # the path: its percent-encoding, then its template
    mov     %r13, %rsi
    call    route_pct_ok
    test    %eax, %eax
    jz      400f
    lea     api_routes(%rip), %r14
    movq    $API_OPS, (L + 120)(%rsp)
3:  lea     api_route_text(%rip), %rdx
    add     (%r14), %rdx
    movzwl  8(%r14), %ecx
    mov     %r12, %rdi
    mov     %r13, %rsi
    lea     L(%rsp), %r8
    call    route_match
    test    %eax, %eax
    jnz     4f
    add     $32, %r14
    decq    (L + 120)(%rsp)
    jnz     3b
    jmp     404f
4:  mov     (%r14), %rdx                    # allow: the methods of the template; the operation of the method
    mov     HttpRequest_method(%rbx), %r9
    lea     api_routes(%rip), %rdi
    mov     $API_OPS, %ecx
    xor     %r8d, %r8d
    xor     %esi, %esi
5:  cmp     %rdx, (%rdi)
    jne     6f
    movzbl  10(%rdi), %eax
    lea     -1(%rax), %r11
    bts     %r11, %r8
    cmp     %r9, %rax
    jne     6f
    test    %rsi, %rsi
    jnz     6f
    mov     %rdi, %rsi
6:  add     $32, %rdi
    dec     %ecx
    jnz     5b
    mov     %r8, ApiRoute_allow(%rbp)
    test    %rsi, %rsi
    jz      405f
    mov     %rsi, %r14
    lea     api_routes(%rip), %rax
    mov     %r14, %rcx
    sub     %rax, %rcx
    shr     $5, %rcx
    inc     %rcx
    mov     %rcx, ApiRoute_op(%rbp)
    mov     %r15, %rdi                      # the query's percent-encoding
    mov     S7(%rsp), %rsi
    call    route_pct_ok
    test    %eax, %eax
    jz      400f
    lea     (L + 8)(%rsp), %r12             # the path parameters
    mov     L(%rsp), %r13
7:  test    %r13, %r13
    jz      20f
    mov     (%r12), %rax
    mov     %rax, S10(%rsp)
    mov     HttpRequest_path(%rbx), %rdi
    add     %rbx, %rdi
    mov     8(%r12), %rax
    add     %rax, %rdi
    mov     16(%r12), %rsi
    sub     %rax, %rsi
    lea     (L + 192)(%rsp), %rdx
    mov     $200, %ecx
    call    route_decode
    cmp     $200, %rax
    ja      401f
    mov     %rax, (L + 88)(%rsp)
    mov     %rax, %rcx
    mov     %rbp, %rdi
    mov     S10(%rsp), %rsi
    lea     (L + 192)(%rsp), %rdx
    lea     (L + 128)(%rsp), %r8
    call    route_value
    test    %eax, %eax
    jnz     401f
    mov     S10(%rsp), %rax
    mov     S8(%rsp), %rcx
    bts     %rax, %rcx
    mov     %rcx, S8(%rsp)
    cmp     $API_PARAM_PEER_ID, %rax        # the peer id: written once the room is known
    jne     8f
    mov     8(%r12), %rax
    mov     %rax, (L + 72)(%rsp)
    mov     16(%r12), %rax
    mov     %rax, (L + 80)(%rsp)
    jmp     9f
8:  movq    $0, (L + 88)(%rsp)
9:  add     $24, %r12
    dec     %r13
    jmp     7b
20: xor     %r12d, %r12d                    # each query item
21: cmp     S7(%rsp), %r12
    jae     40f
    mov     %r15, %rdi
    mov     %r12, %rsi
    mov     S7(%rsp), %rdx
    mov     $0x26, %ecx
    call    http_find
    mov     %rax, %r13
    cmp     %r12, %r13
    je      39f
    mov     %r15, %rdi                      # the name, up to the first =
    mov     %r12, %rsi
    mov     %r13, %rdx
    mov     $0x3d, %ecx
    call    http_find
    mov     %rax, (L + 96)(%rsp)
    lea     (%r15,%r12), %rdi
    mov     %rax, %rsi
    sub     %r12, %rsi
    lea     (L + 192)(%rsp), %rdx
    mov     $32, %ecx
    call    route_decode
    cmp     $32, %rax
    ja      39f
    mov     16(%r14), %r8                   # a parameter the operation takes, by name
    mov     $1, %r9d
22: cmp     $API_PARAMS, %r9
    ja      39f
    bt      %r9, %r8
    jnc     24f
    lea     api_params(%rip), %rdx
    mov     %r9, %rcx
    shl     $5, %rcx
    add     %rcx, %rdx
    cmp     %rax, 8(%rdx)
    jne     24f
    mov     (%rdx), %rsi
    lea     api_param_text(%rip), %rcx
    add     %rcx, %rsi
    lea     (L + 192)(%rsp), %rdi
    xor     %ecx, %ecx
23: cmp     %rax, %rcx
    jae     25f
    movzbl  (%rdi,%rcx), %edx
    cmp     %dl, (%rsi,%rcx)
    jne     24f
    inc     %rcx
    jmp     23b
24: inc     %r9
    jmp     22b
25: mov     %r9, S10(%rsp)
    mov     (L + 96)(%rsp), %rax            # the value: after the =, or empty
    cmp     %r13, %rax
    jae     26f
    inc     %rax
26: mov     %rax, (L + 104)(%rsp)
    lea     api_params(%rip), %rdx
    mov     %r9, %rcx
    shl     $5, %rcx
    mov     16(%rdx,%rcx), %rcx
    cmp     $API_KIND_SET, %rcx
    jae     30f
    mov     S8(%rsp), %rdx                  # one value: given once
    bt      %r9, %rdx
    jc      401f
    bts     %r9, %rdx
    mov     %rdx, S8(%rsp)
    lea     (%r15,%rax), %rdi
    mov     %r13, %rsi
    sub     %rax, %rsi
    lea     (L + 192)(%rsp), %rdx
    mov     $200, %ecx
    call    route_decode
    cmp     $200, %rax
    ja      401f
    mov     %rax, %rcx
    mov     %rbp, %rdi
    mov     S10(%rsp), %rsi
    lea     (L + 192)(%rsp), %rdx
    lea     (L + 128)(%rsp), %r8
    call    route_value
    test    %eax, %eax
    jnz     401f
    jmp     39f
30: mov     S8(%rsp), %rdx                  # a list or a set: each item
    bts     %r9, %rdx
    mov     %rdx, S8(%rsp)
    mov     $64, %eax
    cmp     $API_KIND_ID_LIST, %rcx
    je      31f
    mov     $8, %eax
    cmp     $API_KIND_INDEX_LIST, %rcx
    je      31f
    mov     $32, %eax
    cmp     $API_KIND_HASH_LIST, %rcx
    je      31f
    xor     %eax, %eax
31: mov     %rax, (L + 64)(%rsp)
32: cmpq    $API_PARAM_ID, S10(%rsp)        # the 65th id
    jne     33f
    testl   $(API_FLAG_ID_MAX << 24), 8(%r14)
    jz      33f
    cmpq    $64, S9(%rsp)
    je      414f
33: mov     %r15, %rdi
    mov     (L + 104)(%rsp), %rsi
    mov     %r13, %rdx
    lea     (L + 192)(%rsp), %rcx
    mov     $200, %r8d
    call    route_next_item
    mov     %rax, (L + 104)(%rsp)
    mov     %rcx, (L + 112)(%rsp)
    test    %rdx, %rdx
    jz      401f
    cmp     $200, %rdx
    ja      401f
    mov     %rdx, %rcx
    mov     %rbp, %rdi
    mov     S10(%rsp), %rsi
    lea     (L + 192)(%rsp), %rdx
    lea     (L + 128)(%rsp), %r8
    call    route_value
    test    %eax, %eax
    jnz     401f
    mov     (L + 64)(%rsp), %rcx            # a list item: into out, while there is room
    test    %rcx, %rcx
    jz      36f
    mov     S9(%rsp), %rax
    inc     %rax
    imul    %rcx, %rax
    add     $API_ROUTE_FIXED, %rax
    cmp     (%rbp), %rax
    jbe     34f
    movq    $1, (L + 56)(%rsp)
    jmp     35f
34: sub     %rcx, %rax
    add     %rbp, %rax
    lea     (L + 128)(%rsp), %rsi
341: mov    (%rsi), %rdx
    mov     %rdx, (%rax)
    add     $8, %rsi
    add     $8, %rax
    sub     $8, %rcx
    jnz     341b
35: incq    S9(%rsp)
36: cmpq    $0, (L + 112)(%rsp)
    jne     32b
39: lea     1(%r13), %r12
    jmp     21b
40: mov     24(%r14), %rax                  # required parameters
    mov     S8(%rsp), %rcx
    not     %rcx
    and     %rcx, %rax
    jz      41f
    bsf     %rax, %rax
    mov     %rax, S10(%rsp)
    jmp     401f
41: testl   $(API_FLAG_VERSION << 24), 8(%r14)  # Eth-Consensus-Version
    jz      42f
    movq    $API_PARAM_CONSENSUS_VERSION, S10(%rsp)
    mov     $API_PARAM_CONSENSUS_VERSION, %edi
    mov     HttpRequest_consensus_version(%rbx), %rsi
    add     %rbx, %rsi
    mov     (HttpRequest_consensus_version + 8)(%rbx), %rdx
    call    route_word
    test    %eax, %eax
    jz      401f
    mov     %rdx, ApiRoute_consensus_version(%rbp)
    mov     S8(%rsp), %rax
    bts     $API_PARAM_CONSENSUS_VERSION, %rax
    mov     %rax, S8(%rsp)
42: cmpq    $HTTP_METHOD_POST, HttpRequest_method(%rbx)  # Content-Type
    jne     44f
    movq    $API_TYPE_JSON, ApiRoute_body(%rbp)
    testl   $(API_FLAG_SSZ_BODY << 24), 8(%r14)
    jz      44f
    mov     (HttpRequest_content_type + 8)(%rbx), %rdx
    test    %rdx, %rdx
    jz      44f
    mov     HttpRequest_content_type(%rbx), %r12
    add     %rbx, %r12
    mov     %r12, %rdi
    xor     %esi, %esi
    mov     $0x3b, %ecx
    call    http_find
    mov     %rax, %rdx
    mov     %r12, %rdi
    xor     %esi, %esi
    call    http_trim
    add     %rax, %r12
    sub     %rax, %rdx
    mov     %rdx, %r13
    mov     %r12, %rdi
    mov     %r13, %rsi
    lea     route_t_ssz(%rip), %rdx
    mov     $route_t_ssz_len, %ecx
    call    http_same
    test    %eax, %eax
    jz      43f
    movq    $API_TYPE_SSZ, ApiRoute_body(%rbp)
    jmp     44f
43: mov     %r12, %rdi
    mov     %r13, %rsi
    lea     route_t_json(%rip), %rdx
    mov     $route_t_json_len, %ecx
    call    http_same
    test    %eax, %eax
    jz      415f
44: movq    $API_TYPE_JSON, ApiRoute_response(%rbp)  # Accept
    testl   $(API_FLAG_SSZ_RESPONSE << 24), 8(%r14)
    jz      46f
    mov     (HttpRequest_accept + 8)(%rbx), %r13
    test    %r13, %r13
    jz      46f
    mov     HttpRequest_accept(%rbx), %r12
    add     %rbx, %r12
    mov     %r12, %rdi
    mov     %r13, %rsi
    lea     route_t_json(%rip), %rdx
    mov     $route_t_json_len, %ecx
    call    route_weight
    mov     %rax, S10(%rsp)
    mov     %r12, %rdi
    mov     %r13, %rsi
    lea     route_t_ssz(%rip), %rdx
    mov     $route_t_ssz_len, %ecx
    call    route_weight
    mov     S10(%rsp), %rcx
    mov     %rax, %rdx
    or      %rcx, %rdx
    jz      406f
    cmp     %rcx, %rax
    jbe     46f
    movq    $API_TYPE_SSZ, ApiRoute_response(%rbp)
46: cmpq    $0, (L + 56)(%rsp)              # the room: the list, then the peer id
    jne     97f
    mov     S9(%rsp), %r12
    imul    (L + 64)(%rsp), %r12
    mov     (L + 88)(%rsp), %r13
    lea     7(%r13), %rax
    and     $-8, %rax
    add     %r12, %rax
    add     $API_ROUTE_FIXED, %rax
    cmp     (%rbp), %rax
    ja      97f
    mov     S9(%rsp), %rax
    test    %rax, %rax
    jz      47f
    movq    $API_ROUTE_FIXED, ApiRoute_list(%rbp)
    mov     %rax, (ApiRoute_list + 8)(%rbp)
47: test    %r13, %r13
    jz      48f
    add     $API_ROUTE_FIXED, %r12
    mov     %r12, ApiRoute_peer_id(%rbp)
    mov     %r13, (ApiRoute_peer_id + 8)(%rbp)
    mov     HttpRequest_path(%rbx), %rdi
    add     %rbx, %rdi
    mov     (L + 72)(%rsp), %rax
    add     %rax, %rdi
    mov     (L + 80)(%rsp), %rsi
    sub     %rax, %rsi
    lea     (%rbp,%r12), %rdx
    mov     %r13, %rcx
    call    route_decode
    lea     (%r12,%r13), %rax               # zero bytes up to a multiple of 8
471: test   $7, %al
    jz      48f
    movb    $0, (%rbp,%rax)
    inc     %rax
    jmp     471b
48: mov     16(%r14), %rax                  # broadcast_validation: 1 when it is missing
    bt      $API_PARAM_BROADCAST_VALIDATION, %rax
    jnc     49f
    mov     S8(%rsp), %rax
    bt      $API_PARAM_BROADCAST_VALIDATION, %rax
    jc      49f
    movq    $1, ApiRoute_broadcast_validation(%rbp)
49: mov     S8(%rsp), %rax
    mov     %rax, ApiRoute_present(%rbp)
    mov     $LANTERN_OK, %eax
    LEAVE 400
400: movq   $0, S10(%rsp)
401: mov    $400, %eax
    jmp     96f
404: mov    $404, %eax
    movq    $0, S10(%rsp)
    jmp     96f
405: mov    $405, %eax
    movq    $0, S10(%rsp)
    jmp     96f
406: mov    $406, %eax
    movq    $0, S10(%rsp)
    jmp     96f
414: mov    $414, %eax
    jmp     96f
415: mov    $415, %eax
    movq    $0, S10(%rsp)
96: mov     %rax, ApiRoute_status(%rbp)
    mov     S10(%rsp), %rax
    mov     %rax, ApiRoute_fault(%rbp)
    mov     $LANTERN_INVALID_ROUTE, %eax
    LEAVE 400
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 400
END_FUNCTION lantern_api_route
