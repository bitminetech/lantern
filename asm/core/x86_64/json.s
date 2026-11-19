/*
 * The JSON of SSZ values, x86-64: in the common object. Requirements: docs/reference/beacon-api.md,
 * lantern_json_encode.
 *
 * rbx the cursor, rbp the value, r12 the top level of the cursor, r13 out, r14 where the next byte
 * goes, r15 the end of out's room; S7 the type, S8 its nodes, S9 its fields, S10 the names after
 * the fields.
 */

/*
 * The bytes rdi .. rdi + rsi of a token go out from the cursor's done bytes on, while out has
 * room: rax = 0 when the token is whole (done 0), else 1 (done counts the bytes written). Uses rcx,
 * rdx.
 */
LOCAL_FUNCTION json_put
    UNWIND_END_PROLOGUE
    mov     JsonCursor_done(%rbx), %rcx
1:  cmp     %rsi, %rcx
    jae     2f
    cmp     %r15, %r14
    jae     3f
    movzbl  (%rdi,%rcx), %edx
    mov     %dl, (%r14)
    inc     %r14
    inc     %rcx
    jmp     1b
2:  movq    $0, JsonCursor_done(%rbx)
    xor     %eax, %eax
    ret
3:  mov     %rcx, JsonCursor_done(%rbx)
    mov     $1, %eax
    ret
END_FUNCTION json_put

/*
 * The hex token of the byte or bit string of the level r12 (kind rdi): its bytes from the cursor's
 * done bytes on, while out has room: rax = 0 when whole, else 1. Uses rcx, rdx, rsi, r8-r11;
 * r10 holds the SSZ bytes until the token's length is known.
 */
LOCAL_FUNCTION json_hex
    UNWIND_END_PROLOGUE
    mov     JsonLevel_base(%r12), %r8       # the bytes
    add     %rbp, %r8
    mov     JsonLevel_count(%r12), %r9      # the bit list's bits
    mov     %r9, %r10                       # the SSZ bytes
    cmp     $SSZ_KIND_BIT_VECTOR, %rdi
    jne     1f
    lea     7(%r9), %r10
    shr     $3, %r10
1:  cmp     $SSZ_KIND_BIT_LIST, %rdi
    jne     2f
    mov     %r9, %r10
    shr     $3, %r10
    inc     %r10
2:  lea     4(%r10,%r10), %r11              # the token's bytes: 4 + 2 per byte
    mov     JsonCursor_done(%rbx), %rcx
3:  cmp     %r11, %rcx
    jae     8f
    cmp     %r15, %r14
    jae     9f
    mov     $0x22, %eax                     # " at either end, then 0x
    test    %rcx, %rcx
    jz      7f
    lea     -1(%r11), %rdx
    cmp     %rdx, %rcx
    je      7f
    mov     $0x30, %eax
    cmp     $1, %rcx
    je      7f
    mov     $0x78, %eax
    cmp     $2, %rcx
    je      7f
    lea     -3(%rcx), %rsi                  # a digit: byte rsi / 2
    mov     %rsi, %rdx
    shr     $1, %rdx
    xor     %eax, %eax
    cmp     $SSZ_KIND_BIT_LIST, %rdi
    jne     5f
    lea     7(%r9), %r10                    # a bit list: its bytes, then the delimiter bit
    shr     $3, %r10
    cmp     %r10, %rdx
    jae     4f
    movzbl  (%r8,%rdx), %eax
4:  mov     %r9, %r10
    shr     $3, %r10
    cmp     %r10, %rdx
    jne     6f
    mov     %r9, %r10
    and     $7, %r10d
    bts     %r10d, %eax
    jmp     6f
5:  movzbl  (%r8,%rdx), %eax
6:  test    $1, %sil
    jnz     61f
    shr     $4, %eax
61: and     $15, %eax
    lea     api_hex(%rip), %rdx
    movzbl  (%rdx,%rax), %eax
7:  mov     %al, (%r14)
    inc     %r14
    inc     %rcx
    jmp     3b
8:  movq    $0, JsonCursor_done(%rbx)
    xor     %eax, %eax
    ret
9:  mov     %rcx, JsonCursor_done(%rbx)
    mov     $1, %eax
    ret
END_FUNCTION json_hex

/*
 * The token of the uint or Boolean of the level r12 (kind rdi): rax = 0 when whole, else 1.
 * Locals: the number's 32-bit words at 0, the text from its end at 128.
 */
LOCAL_FUNCTION json_number
    FRAME 128
    mov     JsonLevel_base(%r12), %rsi
    add     %rbp, %rsi
    cmp     $SSZ_KIND_BOOLEAN, %rdi
    jne     1f
    cmpb    $0, (%rsi)
    lea     api_true(%rip), %rdi
    mov     $api_true_len, %esi
    jne     9f
    lea     api_false(%rip), %rdi
    mov     $api_false_len, %esi
    jmp     9f
1:  lea     120(%rsp), %r8                  # the closing quote, then the digits backwards
    dec     %r8
    movb    $0x22, (%r8)
    mov     JsonLevel_count(%r12), %r9      # the width
    cmp     $8, %r9
    ja      4f
    mov     (%rsi), %rax                    # up to 8 bytes: one u64
    je      2f
    movzbl  %al, %eax
2:  mov     $10, %ecx
3:  xor     %edx, %edx
    div     %rcx
    add     $0x30, %dl
    dec     %r8
    mov     %dl, (%r8)
    test    %rax, %rax
    jnz     3b
    jmp     8f
4:  movdqu  (%rsi), %xmm0                   # 32 bytes: eight 32-bit words at 0
    movdqu  16(%rsi), %xmm1
    movdqu  %xmm0, (%rsp)
    movdqu  %xmm1, 16(%rsp)
5:  xor     %edx, %edx                      # divide by 10, from the top word down
    mov     $7, %r9
    xor     %r10d, %r10d                    # any word not zero
    mov     $10, %ecx
6:  mov     (%rsp,%r9,4), %eax
    div     %ecx
    mov     %eax, (%rsp,%r9,4)
    or      %eax, %r10d
    dec     %r9
    jns     6b
    add     $0x30, %dl
    dec     %r8
    mov     %dl, (%r8)
    test    %r10d, %r10d
    jnz     5b
8:  dec     %r8
    movb    $0x22, (%r8)
    mov     %r8, %rdi
    lea     120(%rsp), %rsi
    sub     %r8, %rsi
9:  call    json_put
    UNFRAME 128
END_FUNCTION json_number

/*
 * The level r12 for the type node rdi whose storage is at offset rsi of the value: inline when rdx
 * is 2^64 - 1 and the type is of fixed size; a value of its own with its size first when rdx is
 * 2^64 - 1 and the type is of variable size; else a PartRef at rsi whose offset counts from rdx.
 * rcx the type's nodes. Uses rax, r8-r11.
 */
LOCAL_FUNCTION json_open
    UNWIND_END_PROLOGUE
    imul    $SSZ_NODE_STRIDE, %rdi, %r8
    add     %rcx, %r8
    mov     %rdi, JsonLevel_node(%r12)
    movq    $0, JsonLevel_step(%r12)
    movq    $0, JsonLevel_item(%r12)
    mov     SSZ_NODE_LENGTH(%r8), %rax
    mov     %rax, JsonLevel_count(%r12)     # the width, the length, the field count
    mov     %rsi, JsonLevel_base(%r12)
    cmpq    $0, SSZ_NODE_SSZ_SIZE(%r8)
    jne     9f                              # fixed size: inline
    cmpq    $SSZ_KIND_CONTAINER, SSZ_NODE_KIND(%r8)
    jne     2f
    cmp     $-1, %rdx                       # a container: its own value, or the part of a PartRef
    je      9f
    mov     (%rbp,%rsi), %rax
    add     %rdx, %rax
    mov     %rax, JsonLevel_base(%r12)
    jmp     9f
2:  lea     (%rbp,%rsi), %r9                # a list or bit list or byte list: its PartRef
    mov     %rdx, %r10
    cmp     $-1, %rdx
    jne     3f
    mov     %rsi, %r10                      # its own value: the PartRef at byte 8
    add     $8, %r9
3:  mov     (%r9), %rax
    add     %r10, %rax
    mov     8(%r9), %r11
    mov     %r11, JsonLevel_count(%r12)
    mov     %rax, JsonLevel_base(%r12)
    mov     %rax, JsonLevel_next(%r12)
9:  ret
END_FUNCTION json_open

/* The next item of the compound level r12 at index item, one level deeper. rdi the nodes, rsi the fields. */
LOCAL_FUNCTION json_child
    FRAME 16
    mov     %rdi, (%rsp)
    imul    $SSZ_NODE_STRIDE, JsonLevel_node(%r12), %r8
    add     %rdi, %r8
    mov     JsonLevel_item(%r12), %r9
    mov     JsonLevel_base(%r12), %r10
    cmpq    $SSZ_KIND_CONTAINER, SSZ_NODE_KIND(%r8)
    jne     2f
    mov     SSZ_NODE_ELEMENT(%r8), %rax     # a field: inline, or a PartRef from the container
    add     %r9, %rax
    shl     $5, %rax
    add     %rsi, %rax
    mov     SSZ_FIELD_NODE(%rax), %rdi
    mov     SSZ_FIELD_MEM_OFFSET(%rax), %rsi
    add     %r10, %rsi
    mov     $-1, %rdx
    testq   $SSZ_FIELD_VARIABLE, SSZ_FIELD_FLAGS(%rax)
    cmovnz  %r10, %rdx
    jmp     5f
2:  mov     SSZ_NODE_ELEMENT(%r8), %rdi     # an item: at its stride, or the next value of its own
    imul    $SSZ_NODE_STRIDE, %rdi, %r11
    add     (%rsp), %r11
    mov     $-1, %rdx
    cmpq    $0, SSZ_NODE_SSZ_SIZE(%r11)
    je      3f
    mov     SSZ_NODE_MEM_SIZE(%r11), %rsi
    imul    %r9, %rsi
    add     %r10, %rsi
    jmp     5f
3:  mov     JsonLevel_next(%r12), %rsi
    mov     (%rbp,%rsi), %rax
    add     %rsi, %rax
    mov     %rax, JsonLevel_next(%r12)
5:  incq    JsonCursor_depth(%rbx)
    add     $JSON_LEVEL_SIZE, %r12
    mov     (%rsp), %rcx
    call    json_open
    UNFRAME 16
END_FUNCTION json_child

/* (type, value, cursor, out): docs/reference/beacon-api.md. Locals: L a token of punctuation or a name. */
FUNCTION lantern_json_encode
    ENTER 48
    mov     %rdi, S7(%rsp)
    mov     %rsi, %rbp
    mov     %rdx, %rbx
    mov     %rcx, %r13
    mov     8(%r13), %r14                   # out: its offset, its count, its room
    add     %r13, %r14
    add     16(%r13), %r14
    mov     (%r13), %r15
    add     %r13, %r15
    cmp     %r15, %r14
    jae     97f
    cmpq    $0, JsonCursor_whole(%rbx)
    jne     90f
    mov     8(%rdi), %rax                   # the nodes, the fields, the names after them
    add     %rdi, %rax
    mov     %rax, S8(%rsp)
    mov     24(%rdi), %rax
    add     %rdi, %rax
    mov     %rax, S9(%rsp)
    mov     32(%rdi), %rcx
    shl     $5, %rcx
    add     %rcx, %rax
    mov     %rax, S10(%rsp)
    cmpq    $0, JsonCursor_depth(%rbx)
    jne     1f
    movq    $1, JsonCursor_depth(%rbx)      # the root: inline, or a value of its own
    movq    $0, JsonCursor_done(%rbx)
    lea     JsonCursor_levels(%rbx), %r12
    mov     40(%rdi), %rdi
    xor     %esi, %esi
    mov     $-1, %rdx
    mov     S8(%rsp), %rcx
    call    json_open
1:  mov     JsonCursor_depth(%rbx), %rax
    dec     %rax
    imul    $JSON_LEVEL_SIZE, %rax, %rax
    lea     JsonCursor_levels(%rbx,%rax), %r12
10: imul    $SSZ_NODE_STRIDE, JsonLevel_node(%r12), %rax    # the top level
    add     S8(%rsp), %rax
    mov     SSZ_NODE_KIND(%rax), %rdi
    cmp     $SSZ_KIND_BOOLEAN, %rdi
    ja      11f
    call    json_number
    test    %rax, %rax
    jnz     91f
    jmp     50f
11: cmp     $SSZ_KIND_VECTOR, %rdi
    jae     20f
    call    json_hex                        # a byte or bit string
    test    %rax, %rax
    jnz     91f
    jmp     50f
20: mov     JsonLevel_step(%r12), %rax      # a list, vector or container
    mov     $0x5b, %ecx                     # [ ] or { }
    mov     $0x5d, %edx
    cmp     $SSZ_KIND_CONTAINER, %rdi
    jne     21f
    mov     $0x7b, %ecx
    mov     $0x7d, %edx
21: mov     %rdi, (L + 40)(%rsp)
    test    %rax, %rax
    jnz     22f
    mov     %cl, L(%rsp)                    # step 0: the opening
    lea     L(%rsp), %rdi
    mov     $1, %esi
    call    json_put
    test    %rax, %rax
    jnz     91f
    movq    $1, JsonLevel_step(%r12)
    jmp     10b
22: cmp     $1, %rax
    jne     25f
    mov     JsonLevel_item(%r12), %r8       # step 1: the closing after the last item, or ,
    cmp     JsonLevel_count(%r12), %r8
    jb      23f
    mov     %dl, L(%rsp)
    lea     L(%rsp), %rdi
    mov     $1, %esi
    call    json_put
    test    %rax, %rax
    jnz     91f
    jmp     50f
23: test    %r8, %r8
    jz      24f
    movb    $0x2c, L(%rsp)
    lea     L(%rsp), %rdi
    mov     $1, %esi
    call    json_put
    test    %rax, %rax
    jnz     91f
24: movq    $2, JsonLevel_step(%r12)
    jmp     10b
25: cmpq    $SSZ_KIND_CONTAINER, (L + 40)(%rsp)     # step 2: a field's "name":, then the item, deeper
    jne     27f
    imul    $SSZ_NODE_STRIDE, JsonLevel_node(%r12), %rax
    add     S8(%rsp), %rax
    mov     SSZ_NODE_ELEMENT(%rax), %rax
    add     JsonLevel_item(%r12), %rax
    shl     $5, %rax
    add     S10(%rsp), %rax
    movb    $0x22, L(%rsp)
    xor     %ecx, %ecx
26: cmp     $32, %rcx
    jae     261f
    movzbl  (%rax,%rcx), %edx
    test    %edx, %edx
    jz      261f
    mov     %dl, (L + 1)(%rsp,%rcx)
    inc     %rcx
    jmp     26b
261: movb   $0x22, (L + 1)(%rsp,%rcx)
    movb    $0x3a, (L + 2)(%rsp,%rcx)
    lea     L(%rsp), %rdi
    lea     3(%rcx), %rsi
    call    json_put
    test    %rax, %rax
    jnz     91f
27: movq    $3, JsonLevel_step(%r12)
    cmpq    $JSON_LEVELS, JsonCursor_depth(%rbx)
    jae     97f
    mov     S8(%rsp), %rdi
    mov     S9(%rsp), %rsi
    call    json_child
    jmp     10b
50: decq    JsonCursor_depth(%rbx)          # the level is whole: up one, the next item there
    jz      80f
    sub     $JSON_LEVEL_SIZE, %r12
    incq    JsonLevel_item(%r12)
    movq    $1, JsonLevel_step(%r12)
    jmp     10b
80: movq    $1, JsonCursor_whole(%rbx)      # the JSON is whole
90: mov     %r14, %rax
    sub     %r13, %rax
    sub     8(%r13), %rax
    mov     %rax, 16(%r13)
    xor     %eax, %eax
    LEAVE 48
91: mov     %r14, %rax
    sub     %r13, %rax
    sub     8(%r13), %rax
    mov     %rax, 16(%r13)
    mov     $LANTERN_JSON_MORE, %eax
    LEAVE 48
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 48
END_FUNCTION lantern_json_encode
