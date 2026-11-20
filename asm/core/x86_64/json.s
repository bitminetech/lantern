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

/*
 * rax = the offset of the next variable field after field rsi of the container level r12 in an SSZ
 * encoding, or the level's end with none. rdi the nodes, rdx the fields. Uses rcx, r8-r11.
 */
LOCAL_FUNCTION jss_field_end
    UNWIND_END_PROLOGUE
    imul    $SSZ_NODE_STRIDE, JsonLevel_node(%r12), %r8
    add     %rdi, %r8
    mov     SSZ_NODE_LENGTH(%r8), %r9
    mov     SSZ_NODE_ELEMENT(%r8), %r8
    mov     JsonLevel_base(%r12), %r10
1:  inc     %rsi
    cmp     %r9, %rsi
    jae     9f
    lea     (%r8,%rsi), %r11
    shl     $5, %r11
    add     %rdx, %r11
    testq   $SSZ_FIELD_VARIABLE, SSZ_FIELD_FLAGS(%r11)
    jz      1b
    mov     SSZ_FIELD_SSZ_OFFSET(%r11), %rcx
    add     %r10, %rcx
    mov     (%rbp,%rcx), %eax
    add     %r10, %rax
    ret
9:  mov     JsonLevel_next(%r12), %rax
    ret
END_FUNCTION jss_field_end

/*
 * The level r12 for the type node rdi whose SSZ encoding is the bytes rsi to rdx of the encoding:
 * base and end (next), and the count of its items or bytes. rcx the nodes. Uses rax, r8-r11.
 */
LOCAL_FUNCTION jss_open
    UNWIND_END_PROLOGUE
    imul    $SSZ_NODE_STRIDE, %rdi, %r8
    add     %rcx, %r8
    mov     %rdi, JsonLevel_node(%r12)
    movq    $0, JsonLevel_step(%r12)
    movq    $0, JsonLevel_item(%r12)
    mov     %rsi, JsonLevel_base(%r12)
    mov     %rdx, JsonLevel_next(%r12)
    mov     SSZ_NODE_KIND(%r8), %r9
    mov     SSZ_NODE_LENGTH(%r8), %rax
    cmp     $SSZ_KIND_BYTE_LIST, %r9        # a byte or bit list: its bytes
    je      1f
    cmp     $SSZ_KIND_BIT_LIST, %r9
    jne     2f
1:  mov     %rdx, %rax
    sub     %rsi, %rax
    jmp     9f
2:  cmp     $SSZ_KIND_LIST, %r9
    jne     9f
    imul    $SSZ_NODE_STRIDE, SSZ_NODE_ELEMENT(%r8), %r10    # a list: its bytes over the item's size, or its first offset over 4
    add     %rcx, %r10
    mov     SSZ_NODE_SSZ_SIZE(%r10), %r10
    mov     %rdx, %rax
    sub     %rsi, %rax
    test    %r10, %r10
    jz      3f
    mov     %rdx, %r11
    xor     %edx, %edx
    div     %r10
    mov     %r11, %rdx
    jmp     9f
3:  test    %rax, %rax
    jz      9f
    mov     (%rbp,%rsi), %eax
    shr     $2, %rax
9:  mov     %rax, JsonLevel_count(%r12)
    ret
END_FUNCTION jss_open

/* The next item of the compound level r12 of an SSZ encoding at index item, one level deeper. rdi the nodes, rsi the fields. */
LOCAL_FUNCTION jss_child
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    imul    $SSZ_NODE_STRIDE, JsonLevel_node(%r12), %r8
    add     %rdi, %r8
    mov     JsonLevel_item(%r12), %r9
    mov     JsonLevel_base(%r12), %r10
    cmpq    $SSZ_KIND_CONTAINER, SSZ_NODE_KIND(%r8)
    jne     3f
    mov     SSZ_NODE_ELEMENT(%r8), %rax     # a field: at its ssz_offset, or from its offset to the next
    add     %r9, %rax
    shl     $5, %rax
    add     %rsi, %rax
    mov     SSZ_FIELD_SSZ_OFFSET(%rax), %r11
    add     %r10, %r11
    testq   $SSZ_FIELD_VARIABLE, SSZ_FIELD_FLAGS(%rax)
    jnz     2f
    mov     SSZ_FIELD_NODE(%rax), %rdi
    mov     %r11, %rsi
    imul    $SSZ_NODE_STRIDE, %rdi, %rdx
    add     (%rsp), %rdx
    mov     SSZ_NODE_SSZ_SIZE(%rdx), %rdx
    add     %r11, %rdx
    jmp     5f
2:  mov     SSZ_FIELD_NODE(%rax), %rcx
    mov     %rcx, 16(%rsp)
    mov     (%rbp,%r11), %ecx
    add     %r10, %rcx
    mov     %rcx, 24(%rsp)
    mov     (%rsp), %rdi
    mov     8(%rsp), %rdx
    mov     %r9, %rsi
    call    jss_field_end
    mov     %rax, %rdx
    mov     16(%rsp), %rdi
    mov     24(%rsp), %rsi
    jmp     5f
3:  mov     SSZ_NODE_ELEMENT(%r8), %rdi     # an item: at its index times its size, or from its offset to the next
    imul    $SSZ_NODE_STRIDE, %rdi, %r11
    add     (%rsp), %r11
    mov     SSZ_NODE_SSZ_SIZE(%r11), %r11
    test    %r11, %r11
    jz      4f
    mov     %r11, %rsi
    imul    %r9, %rsi
    add     %r10, %rsi
    lea     (%rsi,%r11), %rdx
    jmp     5f
4:  lea     (%r10,%r9,4), %rax
    mov     (%rbp,%rax), %esi
    add     %r10, %rsi
    mov     JsonLevel_next(%r12), %rdx
    lea     1(%r9), %rax
    cmp     JsonLevel_count(%r12), %rax
    jae     5f
    lea     (%r10,%rax,4), %rax
    mov     (%rbp,%rax), %edx
    add     %r10, %rdx
5:  incq    JsonCursor_depth(%rbx)
    add     $JSON_LEVEL_SIZE, %r12
    mov     (%rsp), %rcx
    call    jss_open
    UNFRAME 32
END_FUNCTION jss_child

/* (type, value, cursor, out): docs/reference/beacon-api.md. */
FUNCTION lantern_json_encode
    FRAME 0
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    call    json_main
    UNFRAME 0
END_FUNCTION lantern_json_encode

/* (type, ssz, cursor, out): docs/reference/beacon-api.md. */
FUNCTION lantern_json_encode_ssz
    FRAME 0
    mov     16(%rsi), %r9
    add     8(%rsi), %rsi
    mov     $1, %r8d
    call    json_main
    UNFRAME 0
END_FUNCTION lantern_json_encode_ssz

/*
 * (type, value or encoding, cursor, out, mode r8, the encoding's bytes r9): the JSON of a value
 * (mode 0) or of an encoding (mode 1). Locals: L a token of punctuation or a name, L+40 the kind,
 * L+48 the mode, L+56 the encoding's bytes.
 */
LOCAL_FUNCTION json_main
    ENTER 64
    mov     %r8, (L + 48)(%rsp)
    mov     %r9, (L + 56)(%rsp)
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
    mov     S8(%rsp), %rcx
    cmpq    $0, (L + 48)(%rsp)
    jne     2f
    mov     $-1, %rdx
    call    json_open
    jmp     1f
2:  mov     (L + 56)(%rsp), %rdx
    call    jss_open
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
    cmp     $SSZ_KIND_BIT_LIST, %rdi        # a byte or bit string; a bit list's encoding as its bytes
    jne     12f
    cmpq    $0, (L + 48)(%rsp)
    je      12f
    mov     $SSZ_KIND_BYTE_LIST, %edi
12: call    json_hex
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
    cmpq    $0, (L + 48)(%rsp)
    jne     28f
    call    json_child
    jmp     10b
28: call    jss_child
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
    LEAVE 64
91: mov     %r14, %rax
    sub     %r13, %rax
    sub     8(%r13), %rax
    mov     %rax, 16(%r13)
    mov     $LANTERN_JSON_MORE, %eax
    LEAVE 64
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
END_FUNCTION json_main

/*
 * ---------------------------------------------------------------- lantern_json_decode
 *
 * rbp the JSON's first byte, r12 its end, r13 the bytes of the encoding so far, r14 where the
 * encoding goes, r15 1 when the bytes are written (0 counts them), rbx the context: JD_TABLES the
 * field tables in scratch (512 bytes a level), JD_NODES the type's nodes, JD_FIELDS its fields,
 * JD_NAMES the names after the fields, JD_FAULT the JsonFault, whose path the levels fill.
 */
.set JD_TABLES, 0
.set JD_NODES, 8
.set JD_FIELDS, 16
.set JD_NAMES, 24
.set JD_FAULT, 32

/* rax = the first byte at or after rdi that is no white space. */
LOCAL_FUNCTION jd_ws
    UNWIND_END_PROLOGUE
    mov     %rdi, %rax
1:  cmp     %r12, %rax
    jae     9f
    movzbl  (%rax), %ecx
    cmp     $0x20, %ecx
    je      2f
    cmp     $0x09, %ecx
    je      2f
    cmp     $0x0a, %ecx
    je      2f
    cmp     $0x0d, %ecx
    jne     9f
2:  inc     %rax
    jmp     1b
9:  ret
END_FUNCTION jd_ws

/* The fault rdi at the byte rsi (the end when past it), at depth rdx: rax = 1. Uses rcx. */
LOCAL_FUNCTION jd_fault
    UNWIND_END_PROLOGUE
    cmp     %r12, %rsi
    cmova   %r12, %rsi
    sub     %rbp, %rsi
    mov     JD_FAULT(%rbx), %rcx
    mov     %rdi, JsonFault_kind(%rcx)
    mov     %rsi, JsonFault_offset(%rcx)
    mov     %rdx, JsonFault_depth(%rcx)
    mov     $1, %eax
    ret
END_FUNCTION jd_fault

/*
 * The string at rdi (its quote): rdi = after its closing quote, r8 its first byte, r9 its end,
 * rax = 0; a \ or a byte below 0x20, or the end, is a fault at depth rdx (rax = 1). Uses rcx.
 */
LOCAL_FUNCTION jd_string
    FRAME 0
    lea     1(%rdi), %r8
    mov     %r8, %r9
1:  cmp     %r12, %r9
    jae     8f
    movzbl  (%r9), %ecx
    cmp     $0x22, %ecx
    je      2f
    cmp     $0x5c, %ecx
    je      8f
    cmp     $0x20, %ecx
    jb      8f
    inc     %r9
    jmp     1b
2:  lea     1(%r9), %rdi
    xor     %eax, %eax
    UNFRAME 0
8:  mov     $JSON_FAULT_SYNTAX, %edi
    mov     %r9, %rsi
    call    jd_fault
    UNFRAME 0
END_FUNCTION jd_string

/* ecx = 1 when the byte at reg is a decimal digit, below the end; else 0. */
.macro JD_DIGIT at
    xor     %ecx, %ecx
    cmp     %r12, \at
    jae     77f
    movzbl  (\at), %ecx
    sub     $0x30, %ecx
    cmp     $9, %ecx
    setbe   %cl
    movzbl  %cl, %ecx
77:
.endm

/* The number at rdi (RFC 8259 section 6): rdi = after it, rax = 0; else a fault at depth rdx. Uses rcx. */
LOCAL_FUNCTION jd_number
    FRAME 0
    cmp     %r12, %rdi
    jae     8f
    cmpb    $0x2d, (%rdi)                   # -
    jne     1f
    inc     %rdi
1:  cmp     %r12, %rdi
    jae     8f
    movzbl  (%rdi), %ecx
    cmp     $0x30, %ecx
    jne     2f
    inc     %rdi
    jmp     3f
2:  sub     $0x31, %ecx
    cmp     $8, %ecx
    ja      8f
21: inc     %rdi
    JD_DIGIT %rdi
    test    %ecx, %ecx
    jnz     21b
3:  cmp     %r12, %rdi                      # a fraction
    jae     9f
    cmpb    $0x2e, (%rdi)
    jne     4f
    inc     %rdi
    JD_DIGIT %rdi
    test    %ecx, %ecx
    jz      8f
31: inc     %rdi
    JD_DIGIT %rdi
    test    %ecx, %ecx
    jnz     31b
4:  cmp     %r12, %rdi                      # an exponent
    jae     9f
    movzbl  (%rdi), %ecx
    or      $0x20, %ecx
    cmp     $0x65, %ecx
    jne     9f
    inc     %rdi
    cmp     %r12, %rdi
    jae     8f
    movzbl  (%rdi), %ecx
    cmp     $0x2b, %ecx
    je      40f
    cmp     $0x2d, %ecx
    jne     41f
40: inc     %rdi
41: JD_DIGIT %rdi
    test    %ecx, %ecx
    jz      8f
42: inc     %rdi
    JD_DIGIT %rdi
    test    %ecx, %ecx
    jnz     42b
9:  xor     %eax, %eax
    UNFRAME 0
8:  mov     %rdi, %rsi
    mov     $JSON_FAULT_SYNTAX, %edi
    call    jd_fault
    UNFRAME 0
END_FUNCTION jd_number

/* eax = 1 when the rdx bytes of text at rsi start at rdi below the end, else 0. Uses rcx, r8. */
LOCAL_FUNCTION jd_literal
    UNWIND_END_PROLOGUE
    lea     (%rdi,%rdx), %rcx
    cmp     %r12, %rcx
    ja      8f
    xor     %ecx, %ecx
1:  cmp     %rdx, %rcx
    jae     9f
    movzbl  (%rdi,%rcx), %r8d
    cmpb    %r8b, (%rsi,%rcx)
    jne     8f
    inc     %rcx
    jmp     1b
9:  mov     $1, %eax
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION jd_literal

/* '"name":' at rdi, in a skipped object: rdi = its value's first byte, rax = 0; else a fault at depth rdx. Locals: rdx. */
LOCAL_FUNCTION jd_key
    FRAME 16
    mov     %rdx, (%rsp)
    cmp     %r12, %rdi
    jae     8f
    cmpb    $0x22, (%rdi)
    jne     8f
    call    jd_string
    test    %rax, %rax
    jnz     9f
    call    jd_ws
    mov     %rax, %rdi
    cmp     %r12, %rdi
    jae     8f
    cmpb    $0x3a, (%rdi)
    jne     8f
    inc     %rdi
    xor     %eax, %eax
    UNFRAME 16
8:  mov     %rdi, %rsi
    mov     $JSON_FAULT_SYNTAX, %edi
    mov     (%rsp), %rdx
    call    jd_fault
9:  UNFRAME 16
END_FUNCTION jd_key

/*
 * The value at rdi, skipped with only the checks of the text, faults at depth rdx: rdi = after
 * it, rax = 0. Locals: the depth, the nesting (a bit each, 1 an object), its count.
 */
LOCAL_FUNCTION jd_skip
    FRAME 32
    mov     %rdx, (%rsp)
    movq    $0, 8(%rsp)
    movq    $0, 16(%rsp)
1:  call    jd_ws                           # a value
    mov     %rax, %rdi
    mov     (%rsp), %rdx
    cmp     %r12, %rdi
    jae     80f
    movzbl  (%rdi), %ecx
    cmp     $0x22, %ecx
    jne     2f
    call    jd_string
    test    %rax, %rax
    jnz     99f
    jmp     10f
2:  cmp     $0x2d, %ecx
    je      21f
    sub     $0x30, %ecx
    cmp     $9, %ecx
    ja      3f
21: call    jd_number
    test    %rax, %rax
    jnz     99f
    jmp     10f
3:  lea     api_true(%rip), %rsi
    mov     $4, %edx
    call    jd_literal
    test    %eax, %eax
    jz      31f
    add     $4, %rdi
    jmp     10f
31: lea     api_false(%rip), %rsi
    mov     $5, %edx
    call    jd_literal
    test    %eax, %eax
    jz      32f
    add     $5, %rdi
    jmp     10f
32: lea     jd_null(%rip), %rsi
    mov     $4, %edx
    call    jd_literal
    test    %eax, %eax
    jz      33f
    add     $4, %rdi
    jmp     10f
33: mov     (%rsp), %rdx
    movzbl  (%rdi), %ecx
    cmp     $0x5b, %ecx
    je      331f
    cmp     $0x7b, %ecx
    jne     80f
331: cmpq   $64, 16(%rsp)                   # [ or {: one level more, at most 64
    jae     80f
    shlq    $1, 8(%rsp)
    cmp     $0x7b, %ecx
    jne     332f
    orq     $1, 8(%rsp)
332: incq   16(%rsp)
    inc     %rdi
    call    jd_ws
    mov     %rax, %rdi
    mov     (%rsp), %rdx
    cmp     %r12, %rdi
    jae     80f
    movzbl  (%rdi), %ecx
    mov     $0x5d, %eax
    testq   $1, 8(%rsp)
    jz      333f
    mov     $0x7d, %eax
333: cmp    %eax, %ecx
    jne     34f
    inc     %rdi                            # empty: closed at once
    jmp     12f
34: testq   $1, 8(%rsp)                     # an array: its first item; an object: its first key
    jz      1b
    call    jd_key
    test    %rax, %rax
    jnz     99f
    jmp     1b
10: cmpq    $0, 16(%rsp)                    # after a value: done at the top, else , or the close
    je      98f
    call    jd_ws
    mov     %rax, %rdi
    mov     (%rsp), %rdx
    cmp     %r12, %rdi
    jae     80f
    movzbl  (%rdi), %ecx
    cmp     $0x2c, %ecx
    jne     11f
    inc     %rdi
    testq   $1, 8(%rsp)
    jz      1b
    call    jd_ws
    mov     %rax, %rdi
    mov     (%rsp), %rdx
    call    jd_key
    test    %rax, %rax
    jnz     99f
    jmp     1b
11: mov     $0x5d, %eax
    testq   $1, 8(%rsp)
    jz      111f
    mov     $0x7d, %eax
111: cmp    %eax, %ecx
    jne     80f
    inc     %rdi
12: shrq    $1, 8(%rsp)                     # one level up
    decq    16(%rsp)
    jmp     10b
80: mov     %rdi, %rsi
    mov     $JSON_FAULT_SYNTAX, %edi
    call    jd_fault
    jmp     99f
98: xor     %eax, %eax
99: UNFRAME 32
END_FUNCTION jd_skip

/* The rsi bytes at rdi join the encoding, written when r15 is 1. Uses rcx, rdx. */
LOCAL_FUNCTION jd_out
    UNWIND_END_PROLOGUE
    test    %r15, %r15
    jz      2f
    xor     %ecx, %ecx
1:  cmp     %rsi, %rcx
    jae     2f
    movzbl  (%rdi,%rcx), %edx
    mov     %dl, (%r14,%r13)
    inc     %r13
    inc     %rcx
    jmp     1b
2:  test    %r15, %r15
    jnz     3f
    add     %rsi, %r13
3:  ret
END_FUNCTION jd_out

/* The 4-byte offset edi at byte rsi of the encoding, when r15 is 1. */
LOCAL_FUNCTION jd_offset
    UNWIND_END_PROLOGUE
    test    %r15, %r15
    jz      9f
    mov     %edi, (%r14,%rsi)
9:  ret
END_FUNCTION jd_offset

/* eax = the value of the hex digit in edi, or 16 for another byte. */
LOCAL_FUNCTION jd_hexdigit
    UNWIND_END_PROLOGUE
    lea     -0x30(%rdi), %eax
    cmp     $9, %eax
    jbe     1f
    mov     %edi, %eax
    or      $0x20, %eax
    sub     $0x61, %eax
    cmp     $5, %eax
    ja      2f
    add     $10, %eax
1:  ret
2:  mov     $16, %eax
    ret
END_FUNCTION jd_hexdigit

/*
 * The value of the type node rdi at rsi, at depth rdx: its encoding joins at r13; rdi = after it,
 * rax = 0, else a fault (rax = 1). Locals: 0 node, 8 depth, 16 the value's first byte, 24 the end,
 * 32 an index, 40 the count, 48 the encoding's start, 56 its tail, 64 the field table, 72 the text
 * cursor or a name's start, 80 the kind's node entry, 88 a string's end, 96 an element node, 104
 * an item's size, 112 the bytes of a number (32), 144 a string's content start, 152 its end.
 */
LOCAL_FUNCTION jd_value
    FRAME 160
    mov     %rdi, (%rsp)
    mov     %rdx, 8(%rsp)
    mov     %rsi, %rdi
    call    jd_ws
    mov     %rax, %rdi
    mov     %rdi, 16(%rsp)
    mov     8(%rsp), %rdx
    cmp     %r12, %rdi
    jae     880f
    imul    $SSZ_NODE_STRIDE, (%rsp), %rax
    add     JD_NODES(%rbx), %rax
    mov     %rax, 80(%rsp)
    mov     SSZ_NODE_KIND(%rax), %rax
    movzbl  (%rdi), %ecx
    cmp     $SSZ_KIND_CONTAINER, %rax
    je      100f
    cmp     $SSZ_KIND_VECTOR, %rax
    jae     200f
    cmp     $SSZ_KIND_BOOLEAN, %rax
    je      300f
    cmp     $0x22, %ecx                     # a uint, a byte or bit string: a string
    jne     870f
    call    jd_string
    test    %rax, %rax
    jnz     899f
    mov     %rdi, 24(%rsp)
    mov     %r8, 144(%rsp)
    mov     %r9, 152(%rsp)
    mov     %r9, %r10
    sub     %r8, %r10                       # the content's bytes
    mov     80(%rsp), %rax
    cmpq    $SSZ_KIND_UINT, SSZ_NODE_KIND(%rax)
    jne     400f
    mov     JD_TABLES(%rbx), %rax           # the Engine API: a QUANTITY
    cmpb    $0, -8(%rax)
    jne     150f
    test    %r10, %r10                      # uint: 1 to 78 digits, below 2^(8 width)
    jz      860f
    cmp     $78, %r10
    ja      860f
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, 112(%rsp)
    movdqu  %xmm0, 128(%rsp)
1:  cmp     %r9, %r8
    jae     3f
    movzbl  (%r8), %ecx
    inc     %r8
    sub     $0x30, %ecx
    cmp     $9, %ecx
    ja      860f
    xor     %esi, %esi                      # the 256-bit number times 10, plus the digit
    mov     %rcx, %r11
2:  mov     112(%rsp,%rsi,8), %rax
    mov     $10, %ecx
    mul     %rcx
    add     %r11, %rax
    adc     $0, %rdx
    mov     %rax, 112(%rsp,%rsi,8)
    mov     %rdx, %r11
    inc     %rsi
    cmp     $4, %rsi
    jb      2b
    test    %r11, %r11
    jnz     860f
    jmp     1b
150: cmp    $3, %r10                        # QUANTITY: 0x, then 0 alone or hex digits from a non-zero one; its value below 2^256
    jb      860f
    cmpb    $0x30, (%r8)
    jne     860f
    cmpb    $0x78, 1(%r8)
    jne     860f
    cmpb    $0x30, 2(%r8)
    jne     151f
    cmp     $3, %r10
    jne     860f
151: add    $2, %r8
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, 112(%rsp)
    movdqu  %xmm0, 128(%rsp)
152: cmp    %r9, %r8
    jae     3f
    movzbl  (%r8), %edi
    inc     %r8
    call    jd_hexdigit
    cmp     $16, %eax
    jae     860f
    mov     136(%rsp), %rcx                 # the 256-bit number times 16, plus the digit
    shr     $60, %rcx
    jnz     860f
    mov     128(%rsp), %rcx
    shld    $4, %rcx, 136(%rsp)
    mov     120(%rsp), %rcx
    shld    $4, %rcx, 128(%rsp)
    mov     112(%rsp), %rcx
    shld    $4, %rcx, 120(%rsp)
    shl     $4, %rcx
    or      %rax, %rcx
    mov     %rcx, 112(%rsp)
    jmp     152b
3:  mov     80(%rsp), %rax
    mov     SSZ_NODE_LENGTH(%rax), %rsi     # the width: bytes past it zero
    mov     %rsi, %rcx
4:  cmp     $32, %rcx
    jae     5f
    cmpb    $0, 112(%rsp,%rcx)
    jne     860f
    inc     %rcx
    jmp     4b
5:  lea     112(%rsp), %rdi
    call    jd_out
    mov     24(%rsp), %rdi
    xor     %eax, %eax
    UNFRAME 160
400: cmp    $2, %r10                        # a byte or bit string: 0x and pairs of hex digits
    jb      850f
    cmpb    $0x30, (%r8)
    jne     850f
    cmpb    $0x78, 1(%r8)
    jne     850f
    test    $1, %r10b
    jnz     850f
    lea     2(%r8), %r11                    # every digit hex
41: cmp     %r9, %r11
    jae     42f
    movzbl  (%r11), %edi
    inc     %r11
    call    jd_hexdigit
    cmp     $16, %eax
    jae     850f
    jmp     41b
42: mov     144(%rsp), %r8
    mov     152(%rsp), %r9
    mov     %r9, %r10
    sub     %r8, %r10
    sub     $2, %r10
    shr     $1, %r10                        # the bytes
    mov     80(%rsp), %rax
    mov     SSZ_NODE_KIND(%rax), %rcx
    mov     SSZ_NODE_LENGTH(%rax), %rsi
    cmp     $SSZ_KIND_BYTE_VECTOR, %rcx
    jne     43f
    cmp     %rsi, %r10
    jne     850f
    jmp     47f
43: cmp     $SSZ_KIND_BYTE_LIST, %rcx
    jne     44f
    cmp     %rsi, %r10
    ja      850f
    jmp     47f
44: xor     %r11d, %r11d                    # the last byte, for the bit kinds
    test    %r10, %r10
    jz      45f
    movzbl  -2(%r9), %edi
    call    jd_hexdigit
    shl     $4, %eax
    mov     %eax, %r11d
    movzbl  -1(%r9), %edi
    call    jd_hexdigit
    or      %eax, %r11d
45: mov     80(%rsp), %rax
    mov     SSZ_NODE_KIND(%rax), %rcx
    mov     SSZ_NODE_LENGTH(%rax), %rsi
    cmp     $SSZ_KIND_BIT_VECTOR, %rcx
    jne     46f
    lea     7(%rsi), %rax                   # a bit vector: its bytes, the bits past N zero
    shr     $3, %rax
    cmp     %rax, %r10
    jne     850f
    mov     %rsi, %rcx
    and     $7, %ecx
    jz      47f
    shr     %cl, %r11d
    test    %r11d, %r11d
    jnz     850f
    jmp     47f
46: test    %r10, %r10                      # a bit list: the last byte not zero, at most N bits
    jz      850f
    test    %r11d, %r11d
    jz      850f
    bsr     %r11d, %eax                     # the delimiter's bit
    lea     -1(%r10), %rcx
    lea     (%rax,%rcx,8), %rax
    cmp     %rsi, %rax
    ja      850f
47: mov     144(%rsp), %r11                 # the bytes join the encoding
    add     $2, %r11
48: cmp     152(%rsp), %r11
    jae     49f
    movzbl  (%r11), %edi
    call    jd_hexdigit
    shl     $4, %eax
    mov     %eax, 112(%rsp)
    movzbl  1(%r11), %edi
    call    jd_hexdigit
    or      %al, 112(%rsp)
    lea     112(%rsp), %rdi
    mov     $1, %esi
    call    jd_out
    add     $2, %r11
    jmp     48b
49: mov     24(%rsp), %rdi
    xor     %eax, %eax
    UNFRAME 160
300: lea    api_true(%rip), %rsi            # Boolean: true or false
    mov     $4, %edx
    call    jd_literal
    movb    $1, 112(%rsp)
    test    %eax, %eax
    jnz     301f
    mov     16(%rsp), %rdi
    lea     api_false(%rip), %rsi
    mov     $5, %edx
    call    jd_literal
    test    %eax, %eax
    jz      870f
    movb    $0, 112(%rsp)
301: mov    16(%rsp), %rdi
    mov     $5, %eax
    mov     $4, %ecx
    cmpb    $0x74, (%rdi)
    cmove   %ecx, %eax
    add     %rax, %rdi
    mov     %rdi, 24(%rsp)
    lea     112(%rsp), %rdi
    mov     $1, %esi
    call    jd_out
    mov     24(%rsp), %rdi
    xor     %eax, %eax
    UNFRAME 160
100: cmp    $0x7b, %ecx                     # a container: an object
    jne     870f
    mov     8(%rsp), %rax                   # its field table: zero
    shl     $9, %rax
    add     JD_TABLES(%rbx), %rax
    mov     %rax, 64(%rsp)
    mov     %rax, %rdi
    mov     $512, %esi
    call    lantern_zero
    mov     16(%rsp), %rdi
    inc     %rdi
    call    jd_ws
    mov     %rax, %rdi
    mov     8(%rsp), %rdx
    cmp     %r12, %rdi
    jae     880f
    cmpb    $0x7d, (%rdi)
    jne     110f
    inc     %rdi
    mov     %rdi, 24(%rsp)
    jmp     130f
110: mov    %rdi, 72(%rsp)                  # a member: its name, a field not seen yet
    mov     8(%rsp), %rdx
    cmpb    $0x22, (%rdi)
    jne     880f
    call    jd_string
    test    %rax, %rax
    jnz     899f
    mov     %rdi, 88(%rsp)
    mov     80(%rsp), %rax
    mov     SSZ_NODE_LENGTH(%rax), %r10
    mov     SSZ_NODE_ELEMENT(%rax), %r11
    xor     %esi, %esi
    mov     JD_TABLES(%rbx), %rax           # the Engine API: camelCase names, others skipped
    cmpb    $0, -8(%rax)
    jne     117f
111: cmp    %r10, %rsi
    jae     890f
    lea     (%r11,%rsi), %rax
    shl     $5, %rax
    add     JD_NAMES(%rbx), %rax            # the name of field rsi
    mov     %r9, %rcx
    sub     %r8, %rcx
    cmp     $32, %rcx
    ja      114f
    xor     %edx, %edx
112: cmp     %rcx, %rdx
    jae     113f
    movzbl  (%r8,%rdx), %edi
    cmpb    %dil, (%rax,%rdx)
    jne     114f
    inc     %rdx
    jmp     112b
113: cmp    $32, %rcx
    je      115f
    cmpb    $0, (%rax,%rcx)
    je      115f
114: inc    %rsi
    jmp     111b
115: mov    64(%rsp), %rax                  # field rsi: seen before?
    cmpq    $0, (%rax,%rsi,8)
    jne     890f
    mov     %rsi, 32(%rsp)
    mov     88(%rsp), %rdi
    call    jd_ws
    mov     %rax, %rdi
    mov     8(%rsp), %rdx
    cmp     %r12, %rdi
    jae     880f
    cmpb    $0x3a, (%rdi)
    jne     880f
    inc     %rdi
    call    jd_ws
    mov     %rax, %rdi
    mov     64(%rsp), %rax                  # its value: kept, then skipped one level down
    mov     32(%rsp), %rsi
    mov     %rdi, %rcx
    sub     %rbp, %rcx
    inc     %rcx
    mov     %rcx, (%rax,%rsi,8)
    mov     8(%rsp), %rdx
    mov     JD_FAULT(%rbx), %rax
    mov     %rsi, JsonFault_path(%rax,%rdx,8)
    inc     %rdx
    call    jd_skip
    test    %rax, %rax
    jnz     899f
119: call   jd_ws
    mov     %rax, %rdi
    mov     8(%rsp), %rdx
    cmp     %r12, %rdi
    jae     880f
    cmpb    $0x2c, (%rdi)
    jne     116f
    inc     %rdi
    call    jd_ws
    mov     %rax, %rdi
    mov     8(%rsp), %rdx
    cmp     %r12, %rdi
    jae     880f
    jmp     110b
116: cmpb   $0x7d, (%rdi)
    jne     880f
    inc     %rdi
    mov     %rdi, 24(%rsp)
    jmp     130f
117: cmp    %r10, %rsi                      # field rsi's name, each _x as X: the member's name?
    jae     118f
    lea     (%r11,%rsi), %rax
    shl     $5, %rax
    add     JD_NAMES(%rbx), %rax
    mov     %r8, %rcx
    xor     %edx, %edx
1171: cmp   $32, %rdx
    jae     1173f
    movzbl  (%rax,%rdx), %edi
    test    %edi, %edi
    jz      1173f
    cmp     $0x5f, %edi
    jne     1172f
    inc     %rdx
    cmp     $32, %rdx
    jae     1174f
    movzbl  (%rax,%rdx), %edi
    sub     $0x20, %edi
1172: cmp   %r9, %rcx
    jae     1174f
    cmpb    %dil, (%rcx)
    jne     1174f
    inc     %rcx
    inc     %rdx
    jmp     1171b
1173: cmp   %r9, %rcx
    je      115b
1174: inc   %rsi
    jmp     117b
118: mov    88(%rsp), %rdi                  # a member of no field: its value skipped
    call    jd_ws
    mov     %rax, %rdi
    mov     8(%rsp), %rdx
    cmp     %r12, %rdi
    jae     880f
    cmpb    $0x3a, (%rdi)
    jne     880f
    inc     %rdi
    call    jd_ws
    mov     %rax, %rdi
    mov     8(%rsp), %rdx                   # its faults at the path of the field count
    mov     80(%rsp), %rax
    mov     SSZ_NODE_LENGTH(%rax), %rsi
    mov     JD_FAULT(%rbx), %rax
    mov     %rsi, JsonFault_path(%rax,%rdx,8)
    inc     %rdx
    call    jd_skip
    test    %rax, %rax
    jnz     899f
    jmp     119b
130: mov    80(%rsp), %rax                  # each field given
    mov     SSZ_NODE_LENGTH(%rax), %r10
    mov     64(%rsp), %r11
    xor     %esi, %esi
131: cmp    %r10, %rsi
    jae     132f
    cmpq    $0, (%r11,%rsi,8)
    je      840f
    inc     %rsi
    jmp     131b
132: mov    SSZ_NODE_ELEMENT(%rax), %r11    # the fixed part: each field's bytes, or 4
    xor     %esi, %esi
    xor     %ecx, %ecx
133: cmp    %r10, %rsi
    jae     134f
    lea     (%r11,%rsi), %rdx
    shl     $5, %rdx
    add     JD_FIELDS(%rbx), %rdx
    mov     $4, %r8d
    testq   $SSZ_FIELD_VARIABLE, SSZ_FIELD_FLAGS(%rdx)
    jnz     1331f
    imul    $SSZ_NODE_STRIDE, SSZ_FIELD_NODE(%rdx), %r8
    add     JD_NODES(%rbx), %r8
    mov     SSZ_NODE_SSZ_SIZE(%r8), %r8
1331: add   %r8, %rcx
    inc     %rsi
    jmp     133b
134: mov    %r13, 48(%rsp)                  # start; the tail after the fixed part
    add     %r13, %rcx
    mov     %rcx, 56(%rsp)
    movq    $0, 32(%rsp)
135: mov    80(%rsp), %rax                  # each field, in order
    mov     32(%rsp), %rsi
    cmp     SSZ_NODE_LENGTH(%rax), %rsi
    jae     139f
    mov     SSZ_NODE_ELEMENT(%rax), %rdx
    add     %rsi, %rdx
    shl     $5, %rdx
    add     JD_FIELDS(%rbx), %rdx
    mov     %rdx, 72(%rsp)
    mov     48(%rsp), %rcx
    add     SSZ_FIELD_SSZ_OFFSET(%rdx), %rcx    # where the field, or its offset, goes
    testq   $SSZ_FIELD_VARIABLE, SSZ_FIELD_FLAGS(%rdx)
    jz      136f
    mov     56(%rsp), %rdi                  # variable: its offset, then its bytes at the tail
    sub     48(%rsp), %rdi
    mov     %rcx, %rsi
    call    jd_offset
    mov     56(%rsp), %r13
    jmp     137f
136: mov    %rcx, %r13
137: mov    8(%rsp), %rdx                   # the field's value, one level down
    mov     32(%rsp), %rsi
    mov     JD_FAULT(%rbx), %rax
    mov     %rsi, JsonFault_path(%rax,%rdx,8)
    inc     %rdx
    mov     64(%rsp), %rax
    mov     (%rax,%rsi,8), %rsi
    lea     -1(%rbp,%rsi), %rsi
    mov     72(%rsp), %rax
    mov     SSZ_FIELD_NODE(%rax), %rdi
    call    jd_value
    test    %rax, %rax
    jnz     899f
    mov     72(%rsp), %rax
    testq   $SSZ_FIELD_VARIABLE, SSZ_FIELD_FLAGS(%rax)
    jz      138f
    mov     %r13, 56(%rsp)
138: incq   32(%rsp)
    jmp     135b
139: mov    56(%rsp), %r13
    mov     24(%rsp), %rdi
    xor     %eax, %eax
    UNFRAME 160
200: cmp    $0x5b, %ecx                     # a list or vector: an array, its items counted
    jne     870f
    mov     16(%rsp), %rdi
    inc     %rdi
    call    jd_ws
    mov     %rax, %rdi
    mov     8(%rsp), %rdx
    cmp     %r12, %rdi
    jae     880f
    movq    $0, 40(%rsp)
    cmpb    $0x5d, (%rdi)
    jne     210f
    inc     %rdi
    mov     %rdi, 24(%rsp)
    jmp     220f
210: mov    8(%rsp), %rdx                   # an item, skipped one level down
    mov     40(%rsp), %rsi
    mov     JD_FAULT(%rbx), %rax
    mov     %rsi, JsonFault_path(%rax,%rdx,8)
    inc     %rdx
    call    jd_skip
    test    %rax, %rax
    jnz     899f
    incq    40(%rsp)
    call    jd_ws
    mov     %rax, %rdi
    mov     8(%rsp), %rdx
    cmp     %r12, %rdi
    jae     880f
    cmpb    $0x2c, (%rdi)
    jne     211f
    inc     %rdi
    call    jd_ws
    mov     %rax, %rdi
    jmp     210b
211: cmpb   $0x5d, (%rdi)
    jne     880f
    inc     %rdi
    mov     %rdi, 24(%rsp)
220: mov    80(%rsp), %rax                  # the count: N for a vector, at most N for a list
    mov     40(%rsp), %rcx
    cmp     SSZ_NODE_LENGTH(%rax), %rcx
    ja      830f
    cmpq    $SSZ_KIND_VECTOR, SSZ_NODE_KIND(%rax)
    jne     221f
    cmp     SSZ_NODE_LENGTH(%rax), %rcx
    jne     830f
221: mov    SSZ_NODE_ELEMENT(%rax), %rdx    # the items: fixed in a row, or 4-byte offsets first
    mov     %rdx, 96(%rsp)
    imul    $SSZ_NODE_STRIDE, %rdx, %rdx
    add     JD_NODES(%rbx), %rdx
    mov     SSZ_NODE_SSZ_SIZE(%rdx), %rdx
    mov     %rdx, 104(%rsp)
    mov     %r13, 48(%rsp)
    lea     (%r13,%rcx,4), %rax
    test    %rdx, %rdx
    cmovnz  %r13, %rax
    mov     %rax, 56(%rsp)
    mov     16(%rsp), %rdi
    inc     %rdi
    call    jd_ws
    mov     %rax, 72(%rsp)
    movq    $0, 32(%rsp)
222: mov    32(%rsp), %rsi
    cmp     40(%rsp), %rsi
    jae     229f
    cmpq    $0, 104(%rsp)
    jne     223f
    mov     56(%rsp), %rdi                  # variable: its offset, then its bytes at the tail
    sub     48(%rsp), %rdi
    mov     48(%rsp), %rax
    lea     (%rax,%rsi,4), %rsi
    call    jd_offset
    mov     56(%rsp), %r13
223: mov    8(%rsp), %rdx
    mov     32(%rsp), %rsi
    mov     JD_FAULT(%rbx), %rax
    mov     %rsi, JsonFault_path(%rax,%rdx,8)
    inc     %rdx
    mov     96(%rsp), %rdi
    mov     72(%rsp), %rsi
    call    jd_value
    test    %rax, %rax
    jnz     899f
    cmpq    $0, 104(%rsp)
    jne     224f
    mov     %r13, 56(%rsp)
224: call   jd_ws                           # past the ,
    mov     %rax, %rdi
    cmp     %r12, %rdi
    jae     225f
    cmpb    $0x2c, (%rdi)
    jne     225f
    inc     %rdi
    call    jd_ws
    mov     %rax, %rdi
225: mov    %rdi, 72(%rsp)
    incq    32(%rsp)
    jmp     222b
229: cmpq   $0, 104(%rsp)
    jne     2291f
    mov     56(%rsp), %r13
2291: mov   24(%rsp), %rdi
    xor     %eax, %eax
    UNFRAME 160
830: mov    $JSON_FAULT_LENGTH, %edi        # the faults of this level
    mov     16(%rsp), %rsi
    jmp     898f
840: mov    $JSON_FAULT_MISSING, %edi
    mov     24(%rsp), %rsi
    dec     %rsi
    jmp     898f
850: mov    $JSON_FAULT_HEX, %edi
    mov     16(%rsp), %rsi
    jmp     898f
860: mov    $JSON_FAULT_NUMBER, %edi
    mov     16(%rsp), %rsi
    jmp     898f
870: mov    $JSON_FAULT_TYPE, %edi
    mov     16(%rsp), %rsi
    jmp     898f
880: mov    %rdi, %rsi
    mov     $JSON_FAULT_SYNTAX, %edi
    jmp     898f
890: mov    $JSON_FAULT_FIELD, %edi
    mov     72(%rsp), %rsi
898: mov    8(%rsp), %rdx
    call    jd_fault
899: UNFRAME 160
END_FUNCTION jd_value

/* (type, json, scratch, out, fault): docs/reference/beacon-api.md. */
FUNCTION lantern_json_decode
    FRAME 0
    xor     %r9d, %r9d
    call    json_decode_mode
    UNFRAME 0
END_FUNCTION lantern_json_decode

/* (type, json, scratch, out, fault): docs/reference/engine-api.md, the Engine API's JSON. */
FUNCTION lantern_engine_json_decode
    FRAME 0
    mov     $1, %r9d
    call    json_decode_mode
    UNFRAME 0
END_FUNCTION lantern_engine_json_decode

/*
 * L2: (type, json, scratch, out, fault, mode): lantern_json_decode for mode 0, of the Beacon API's
 * JSON; lantern_engine_json_decode for mode 1, of the Engine API's: the mode at byte 56 of scratch,
 * before the field tables. Locals: L the context, L+40 out, L+48 the root, L+56 the mode.
 */
LOCAL_FUNCTION json_decode_mode
    ENTER 64
    mov     %rcx, (L + 40)(%rsp)
    mov     %r9, (L + 56)(%rsp)
    lea     L(%rsp), %rbx
    mov     %r8, JD_FAULT(%rbx)
    mov     %rdi, %r9
    mov     %rsi, %r10
    mov     %rdx, %r11
    mov     %r8, %rdi                       # the fault: zero
    xor     %eax, %eax
    mov     $JSON_FAULT_SIZE, %ecx
    rep stosb
    cmpq    $JSON_DECODE_SCRATCH, (%r11)
    jb      97f
    mov     (L + 56)(%rsp), %rax
    mov     %al, 56(%r11)
    lea     64(%r11), %rax                  # the field tables: 512 bytes a level
    mov     %rax, JD_TABLES(%rbx)
    mov     8(%r10), %rbp
    add     %r10, %rbp
    mov     16(%r10), %r12
    add     %rbp, %r12
    mov     8(%r9), %rax
    add     %r9, %rax
    mov     %rax, JD_NODES(%rbx)
    mov     24(%r9), %rax
    add     %r9, %rax
    mov     %rax, JD_FIELDS(%rbx)
    mov     32(%r9), %rcx
    shl     $5, %rcx
    add     %rcx, %rax
    mov     %rax, JD_NAMES(%rbx)
    mov     40(%r9), %rax
    mov     %rax, (L + 48)(%rsp)
    xor     %r15d, %r15d                    # first the count, with every check
    xor     %r13d, %r13d
    mov     %rax, %rdi
    mov     %rbp, %rsi
    xor     %edx, %edx
    call    jd_value
    test    %rax, %rax
    jnz     98f
    call    jd_ws
    cmp     %r12, %rax
    jne     96f
    mov     (L + 40)(%rsp), %rax            # then the bytes, with room for them
    mov     (%rax), %rcx
    sub     $24, %rcx
    cmp     %rcx, %r13
    ja      95f
    lea     24(%rax), %r14
    movq    $24, 8(%rax)
    mov     %r13, 16(%rax)
    mov     $1, %r15d
    xor     %r13d, %r13d
    mov     (L + 48)(%rsp), %rdi
    mov     %rbp, %rsi
    xor     %edx, %edx
    call    jd_value
    xor     %eax, %eax
    LEAVE 64
95: mov     JD_FAULT(%rbx), %rax
    mov     %r13, JsonFault_size(%rax)
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
96: mov     %rax, %rsi
    mov     $JSON_FAULT_SYNTAX, %edi
    xor     %edx, %edx
    call    jd_fault
98: mov     $LANTERN_INVALID_JSON, %eax
    LEAVE 64
END_FUNCTION json_decode_mode

    RODATA
jd_null:
    .ascii "null"
