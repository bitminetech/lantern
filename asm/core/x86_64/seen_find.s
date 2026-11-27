/*
 * Finding a block of Seen, x86-64: a helper of the common object and of each fork's object.
 * Requirements: docs/reference/networking.md.
 */

/* rax = the SeenBlock of root rsi in seen rdi, or 0. A leaf; uses rcx, rdx, xmm0-xmm2, r11. */
LOCAL_FUNCTION lantern_seen_find_block
    UNWIND_END_PROLOGUE
    PART    %rax, %rcx, %rdi, Seen_blocks
1:  test    %rcx, %rcx
    jz      3f
    NE32    %rax, %rsi, 2f
    ret
2:  add     $SeenBlock__mem, %rax
    dec     %rcx
    jmp     1b
3:  xor     %eax, %eax
    ret
END_FUNCTION lantern_seen_find_block

/*
 * dst = the index hash of a SeenKey (networking.md, Seen): h = kind, then h = h * M + c, h * M + b,
 * h * M + a, then h xor (h >> 29). The operands may be memory; tmp a register.
 */
.macro SEEN_HASH dst, kind, a, b, c, tmp
    mov     \kind, \dst
    imul    $SEEN_HASH_M, \dst, \dst
    add     \c, \dst
    imul    $SEEN_HASH_M, \dst, \dst
    add     \b, \dst
    imul    $SEEN_HASH_M, \dst, \dst
    add     \a, \dst
    mov     \dst, \tmp
    shr     $29, \tmp
    xor     \tmp, \dst
.endm

/* rax = 1 when seen rdi holds the SeenKey (rsi kind, rdx a, rcx b, r8 c), else 0. A leaf; uses r9-r11. */
LOCAL_FUNCTION lantern_seen_find_key
    UNWIND_END_PROLOGUE
    SEEN_HASH %r9, %rsi, %rdx, %rcx, %r8, %rax
    mov     (Seen_index + 8)(%rdi), %r10    # the mask of the slots
    dec     %r10
    mov     Seen_index(%rdi), %r11
    add     %rdi, %r11
1:  and     %r10, %r9
    mov     (%r11,%r9,4), %eax              # an empty slot: not held
    test    %eax, %eax
    jz      3f
    shl     $5, %rax                        # the key of position + 1, at its end
    add     Seen_keys(%rdi), %rax
    cmp     %rsi, -32(%rdi,%rax)
    jne     2f
    cmp     %rdx, -24(%rdi,%rax)
    jne     2f
    cmp     %rcx, -16(%rdi,%rax)
    jne     2f
    cmp     %r8, -8(%rdi,%rax)
    je      4f
2:  inc     %r9
    jmp     1b
3:  xor     %eax, %eax
    ret
4:  mov     $1, %eax
    ret
END_FUNCTION lantern_seen_find_key

/*
 * Append the SeenKey (rsi kind, rdx a, rcx b, r8 c) to seen rdi, which has room, and its position + 1 to the
 * first empty slot from its hash. Uses r9, r10. Locals: rsp+0 rax, rsp+8 r11.
 */
LOCAL_FUNCTION lantern_seen_add_key
    FRAME 16
    mov     %rax, 0(%rsp)
    mov     %r11, 8(%rsp)
    PART    %r9, %r10, %rdi, Seen_keys
    shl     $5, %r10
    add     %r10, %r9
    mov     %rsi, 0(%r9)
    mov     %rdx, 8(%r9)
    mov     %rcx, 16(%r9)
    mov     %r8, 24(%r9)
    incq    (Seen_keys + 8)(%rdi)
    SEEN_HASH %r9, %rsi, %rdx, %rcx, %r8, %rax
    mov     (Seen_index + 8)(%rdi), %r10
    dec     %r10
    mov     Seen_index(%rdi), %r11
    add     %rdi, %r11
1:  and     %r10, %r9
    cmpl    $0, (%r11,%r9,4)
    je      2f
    inc     %r9
    jmp     1b
2:  mov     (Seen_keys + 8)(%rdi), %rax
    mov     %eax, (%r11,%r9,4)
    mov     0(%rsp), %rax
    mov     8(%rsp), %r11
    UNFRAME 16
END_FUNCTION lantern_seen_add_key

/*
 * The index of seen rdi from its keys: every slot empty, then each key's position + 1, in key order, at the
 * first empty slot from its hash; rax = 0. A leaf; uses rcx, rdx, rsi, r8-r11. rsi the key, rdx the keys
 * left, r8 its position + 1, r9 a slot, r10 the mask, r11 the slots.
 */
LOCAL_FUNCTION lantern_seen_index
    UNWIND_END_PROLOGUE
    mov     (Seen_index + 8)(%rdi), %r10
    mov     Seen_index(%rdi), %r11
    add     %rdi, %r11
    mov     %r10, %rcx
1:  test    %rcx, %rcx
    jz      2f
    dec     %rcx
    movl    $0, (%r11,%rcx,4)
    jmp     1b
2:  dec     %r10
    PART    %rsi, %rdx, %rdi, Seen_keys
    xor     %r8d, %r8d
3:  test    %rdx, %rdx
    jz      9f
    inc     %r8
    SEEN_HASH %r9, 0(%rsi), 8(%rsi), 16(%rsi), 24(%rsi), %rax
4:  and     %r10, %r9
    cmpl    $0, (%r11,%r9,4)
    je      5f
    inc     %r9
    jmp     4b
5:  mov     %r8d, (%r11,%r9,4)
    add     $SeenKey__mem, %rsi
    dec     %rdx
    jmp     3b
9:  xor     %eax, %eax
    ret
END_FUNCTION lantern_seen_index
